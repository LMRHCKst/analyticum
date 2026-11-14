unit lib_ai;

// M4a: обучение без ML-библиотек.
//  * TSoftmaxModel — мультиномиальная логистическая регрессия на TDenseMatrix;
//  * TSampleBuffer — кольцевой буфер наблюдений в памяти (без датасетов);
//  * TAiEngine — признаки хода игрока, обучение мини-батчами каждые 20 ходов;
//  * TKMeans — свои 3 кластера по стилю игры.
// Никаких файлов модели и никаких вызовов Fit().

interface

uses System, System.Collections.Generic, System.Linq, lib_core, lib_lowlevel;

const
  AI_FEATURE_COUNT = 40;
  AI_ACTION_COUNT = 5;
  AI_HISTORY = 6;

type
  TAgentView = record
    Dx, Dy, Dist: integer;
    PlayerHpRatio, EnemyHpRatio: double;
    WallN, WallS, WallW, WallE: boolean;
    LastActions: array[0..AI_HISTORY - 1] of integer;
    constructor Create(dx, dy, dist: integer; php, ehp: double;
      wn, ws, ww, we: boolean);
  end;

  TPrediction = record
    Probs: array of double;
    Best: integer;
    Confidence: double;
  end;

  TSoftmaxModel = class
  private
    fWeights: TDenseMatrix;
    fGrad: TDenseMatrix;
    fRng: TRng;
    fLearnRate, fL2: double;
    function Logits(x: array of double): array of double;
  public
    constructor Create(rng: TRng; learnRate, l2: double);
    procedure Dispose;
    function PredictProbs(x: array of double): array of double;
    function Predict(x: array of double): TPrediction;
    procedure TrainBatch(x: TDenseMatrix; y: array of integer;
      epochs, batchSize: integer);
    function Accuracy(x: TDenseMatrix; y: array of integer): double;
    function Loss(x: TDenseMatrix; y: array of integer): double;
    property Weights: TDenseMatrix read fWeights;
  end;

  TSampleRow = record
    X: array of double;
    Y: integer;
  end;

  TSampleBuffer = class
  private
    fRows: array of TSampleRow;
    fCapacity, fCount, fNext: integer;
  public
    constructor Create(capacity: integer := 2048);
    procedure Add(x: array of double; y: integer);
    function Count: integer;
    procedure Clear;
    function ToMatrix(maxRows: integer; var labels: array of integer): TDenseMatrix;
    function LabelCounts: array of integer;
  end;

  TFeatureExtractor = class
  public
    class function Extract(v: TAgentView): array of double;
  end;

  TAiEngine = class
  private
    fModel: TSoftmaxModel;
    fBuffer: TSampleBuffer;
    fRng: TRng;
    fSinceTrain: integer;
    fTrainEvery: integer;
    fAccuracy: List<double>;
    fLoss: List<double>;
    fTrainedBatches: integer;
  public
    constructor Create(seed: uint64; capacity: integer := 2048);
    procedure Dispose;
    function Observe(v: TAgentView; actualAction: integer): boolean;
    function Predict(v: TAgentView): TPrediction;
    procedure TrainNow;
    function AccuracyHistory: array of double;
    function LossHistory: array of double;
    property SinceTrain: integer read fSinceTrain;
    property TrainedBatches: integer read fTrainedBatches;
    property Model: TSoftmaxModel read fModel;
    property Buffer: TSampleBuffer read fBuffer;
  end;

  TKMeans = class
  private
    fK: integer;
    fCentroids: TDenseMatrix;
    fLabels: array of integer;
    fInertia: double;
    fRng: TRng;
    function Nearest(x: array of double): integer;
  public
    constructor Create(k: integer; rng: TRng);
    procedure Dispose;
    procedure Fit(points: TDenseMatrix; maxIter: integer := 50);
    function ClusterOf(x: array of double): integer;
    property Centroids: TDenseMatrix read fCentroids;
    property Labels: array of integer read fLabels;
    property Inertia: double read fInertia;
  end;

implementation

constructor TAgentView.Create(dx, dy, dist: integer; php, ehp: double;
  wn, ws, ww, we: boolean);
begin
  Self.Dx := dx;
  Self.Dy := dy;
  Self.Dist := dist;
  PlayerHpRatio := php;
  EnemyHpRatio := ehp;
  WallN := wn;
  WallS := ws;
  WallW := ww;
  WallE := we;
end;

constructor TSoftmaxModel.Create(rng: TRng; learnRate, l2: double);
begin
  fRng := rng;
  fLearnRate := learnRate;
  fL2 := l2;
  fWeights := new TDenseMatrix(AI_ACTION_COUNT, AI_FEATURE_COUNT);
  fWeights.Randomize(fRng, 0.01);
  fGrad := new TDenseMatrix(AI_ACTION_COUNT, AI_FEATURE_COUNT);
end;

procedure TSoftmaxModel.Dispose;
begin
  fWeights.Dispose;
  fGrad.Dispose;
end;

function TSoftmaxModel.Logits(x: array of double): array of double;
var
  c, f: integer;
  sum: double;
begin
  SetLength(Result, AI_ACTION_COUNT);
  for c := 0 to AI_ACTION_COUNT - 1 do
  begin
    sum := 0;
    for f := 0 to AI_FEATURE_COUNT - 1 do
      sum += fWeights.Get(c, f) * x[f];
    Result[c] := sum;
  end;
end;

function TSoftmaxModel.PredictProbs(x: array of double): array of double;
var
  logitsArr: array of double;
  c: integer;
  maxLogit, sum: double;
begin
  logitsArr := Logits(x);
  maxLogit := logitsArr[0];
  for c := 1 to AI_ACTION_COUNT - 1 do
    if logitsArr[c] > maxLogit then
      maxLogit := logitsArr[c];
  sum := 0;
  SetLength(Result, AI_ACTION_COUNT);
  for c := 0 to AI_ACTION_COUNT - 1 do
  begin
    Result[c] := Exp(logitsArr[c] - maxLogit);
    sum += Result[c];
  end;
  for c := 0 to AI_ACTION_COUNT - 1 do
    Result[c] /= sum;
end;

function TSoftmaxModel.Predict(x: array of double): TPrediction;
var
  c, best: integer;
begin
  Result.Probs := PredictProbs(x);
  best := 0;
  for c := 1 to AI_ACTION_COUNT - 1 do
    if Result.Probs[c] > Result.Probs[best] then
      best := c;
  Result.Best := best;
  Result.Confidence := Result.Probs[best];
end;

procedure TSoftmaxModel.TrainBatch(x: TDenseMatrix; y: array of integer;
  epochs, batchSize: integer);
var
  n, epoch, startIdx, endIdx, i, c, f, sample: integer;
  order: array of integer;
  probs: array of double;
  delta: array of double;
  correct: integer;
  invBatch: double;
begin
  n := x.Rows;
  if n = 0 then
    Exit;
  batchSize := Max(1, batchSize);
  SetLength(order, n);
  for i := 0 to n - 1 do
    order[i] := i;
  for epoch := 1 to Max(1, epochs) do
  begin
    fRng.Shuffle(order);
    startIdx := 0;
    while startIdx < n do
    begin
      endIdx := Min(n, startIdx + batchSize);
      fGrad.Zero;
      for sample := startIdx to endIdx - 1 do
      begin
        i := order[sample];
        probs := PredictProbs(x.RowToArray(i));
        SetLength(delta, AI_ACTION_COUNT);
        correct := y[i];
        for c := 0 to AI_ACTION_COUNT - 1 do
        begin
          if c = correct then
            delta[c] := probs[c] - 1.0
          else
            delta[c] := probs[c];
        end;
        for c := 0 to AI_ACTION_COUNT - 1 do
          for f := 0 to AI_FEATURE_COUNT - 1 do
            fGrad.SetValue(c, f, fGrad.Get(c, f) + delta[c] * x.Get(i, f));
      end;
      invBatch := 1.0 / (endIdx - startIdx);
      // Клиппинг градиента: защита от взрывного роста на редких классах.
      if fGrad.MaxAbs > 5.0 then
        fGrad.Scale(5.0 / fGrad.MaxAbs);
      for c := 0 to AI_ACTION_COUNT - 1 do
        for f := 0 to AI_FEATURE_COUNT - 1 do
          fWeights.SetValue(c, f,
            fWeights.Get(c, f) - fLearnRate * (fGrad.Get(c, f) * invBatch + fL2 * fWeights.Get(c, f)));
      startIdx := endIdx;
    end;
  end;
end;

function TSoftmaxModel.Accuracy(x: TDenseMatrix; y: array of integer): double;
var
  i, c, best: integer;
  probs: array of double;
  hits: integer;
begin
  if x.Rows = 0 then
    Exit(0);
  hits := 0;
  for i := 0 to x.Rows - 1 do
  begin
    probs := PredictProbs(x.RowToArray(i));
    best := 0;
    for c := 1 to AI_ACTION_COUNT - 1 do
      if probs[c] > probs[best] then
        best := c;
    if best = y[i] then
      Inc(hits);
  end;
  Result := hits / x.Rows;
end;

function TSoftmaxModel.Loss(x: TDenseMatrix; y: array of integer): double;
var
  i: integer;
  probs: array of double;
  sum: double;
begin
  if x.Rows = 0 then
    Exit(0);
  sum := 0;
  for i := 0 to x.Rows - 1 do
  begin
    probs := PredictProbs(x.RowToArray(i));
    sum += -Ln(Max(1e-12, probs[y[i]]));
  end;
  Result := sum / x.Rows;
end;

constructor TSampleBuffer.Create(capacity: integer);
begin
  fCapacity := Max(16, capacity);
  SetLength(fRows, fCapacity);
  fCount := 0;
  fNext := 0;
end;

procedure TSampleBuffer.Add(x: array of double; y: integer);
begin
  fRows[fNext].X := Copy(x);
  fRows[fNext].Y := y;
  fNext := (fNext + 1) mod fCapacity;
  if fCount < fCapacity then
    Inc(fCount);
end;

function TSampleBuffer.Count: integer;
begin
  Result := fCount;
end;

procedure TSampleBuffer.Clear;
begin
  fCount := 0;
  fNext := 0;
end;

function TSampleBuffer.ToMatrix(maxRows: integer; var labels: array of integer): TDenseMatrix;
var
  n, i, j, startIdx, idx: integer;
begin
  n := Min(fCount, MaxRows);
  Result := new TDenseMatrix(n, AI_FEATURE_COUNT);
  SetLength(labels, n);
  startIdx := (fNext - n + fCapacity) mod fCapacity;
  for i := 0 to n - 1 do
  begin
    idx := (startIdx + i) mod fCapacity;
    for j := 0 to AI_FEATURE_COUNT - 1 do
      Result.SetValue(i, j, fRows[idx].X[j]);
    labels[i] := fRows[idx].Y;
  end;
end;

function TSampleBuffer.LabelCounts: array of integer;
var
  i: integer;
begin
  SetLength(Result, AI_ACTION_COUNT);
  for i := 0 to fCount - 1 do
    Inc(Result[fRows[i].Y]);
end;

class function TFeatureExtractor.Extract(v: TAgentView): array of double;
var
  i, base: integer;
begin
  SetLength(Result, AI_FEATURE_COUNT);
  Result[0] := Clamp(v.Dx / 20.0, -1.0, 1.0);
  Result[1] := Clamp(v.Dy / 20.0, -1.0, 1.0);
  Result[2] := Clamp(v.Dist / 40.0, 0.0, 1.0);
  Result[3] := Clamp(v.PlayerHpRatio, 0.0, 1.0);
  Result[4] := Clamp(v.EnemyHpRatio, 0.0, 1.0);
  if v.WallN then Result[5] := 1;
  if v.WallS then Result[6] := 1;
  if v.WallW then Result[7] := 1;
  if v.WallE then Result[8] := 1;
  Result[9] := 1.0;
  for i := 0 to AI_HISTORY - 1 do
  begin
    base := 10 + i * AI_ACTION_COUNT;
    if (v.LastActions[i] >= 0) and (v.LastActions[i] < AI_ACTION_COUNT) then
      Result[base + v.LastActions[i]] := 1.0;
  end;
end;

constructor TAiEngine.Create(seed: uint64; capacity: integer);
begin
  fRng := new TRng(seed xor $A1B2C3D4);
  fModel := new TSoftmaxModel(fRng, 0.15, 0.0005);
  fBuffer := new TSampleBuffer(capacity);
  fSinceTrain := 0;
  fTrainEvery := 20;
  fAccuracy := new List<double>;
  fLoss := new List<double>;
  fTrainedBatches := 0;
end;

procedure TAiEngine.Dispose;
begin
  fModel.Dispose;
end;

function TAiEngine.Observe(v: TAgentView; actualAction: integer): boolean;
var
  x: array of double;
begin
  x := TFeatureExtractor.Extract(v);
  fBuffer.Add(x, actualAction);
  Inc(fSinceTrain);
  Result := false;
  if fSinceTrain >= fTrainEvery then
  begin
    TrainNow;
    Result := true;
  end;
end;

function TAiEngine.Predict(v: TAgentView): TPrediction;
var
  x: array of double;
begin
  x := TFeatureExtractor.Extract(v);
  Result := fModel.Predict(x);
end;

procedure TAiEngine.TrainNow;
var
  x: TDenseMatrix;
  y: array of integer;
  acc, loss: double;
begin
  if fBuffer.Count < 8 then
  begin
    fSinceTrain := 0;
    Exit;
  end;
  x := fBuffer.ToMatrix(512, y);
  fModel.TrainBatch(x, y, 3, 32);
  acc := fModel.Accuracy(x, y);
  loss := fModel.Loss(x, y);
  fAccuracy.Add(acc);
  fLoss.Add(loss);
  fTrainedBatches += 1;
  x.Dispose;
  fSinceTrain := 0;
end;

function TAiEngine.AccuracyHistory: array of double;
begin
  Result := fAccuracy.ToArray;
end;

function TAiEngine.LossHistory: array of double;
begin
  Result := fLoss.ToArray;
end;

constructor TKMeans.Create(k: integer; rng: TRng);
begin
  fK := Max(1, k);
  fRng := rng;
end;

procedure TKMeans.Dispose;
begin
  if fCentroids <> nil then
    fCentroids.Dispose;
end;

function TKMeans.Nearest(x: array of double): integer;
var
  c, j: integer;
  dist, bestDist, d: double;
begin
  Result := 0;
  bestDist := 1e300;
  for c := 0 to fK - 1 do
  begin
    dist := 0;
    for j := 0 to High(x) do
    begin
      d := x[j] - fCentroids.Get(c, j);
      dist += d * d;
    end;
    if dist < bestDist then
    begin
      bestDist := dist;
      Result := c;
    end;
  end;
end;

procedure TKMeans.Fit(points: TDenseMatrix; maxIter: integer);
var
  n, dim, ci, i, j, c, iter, best, changed, emptyCount, pickIdx: integer;
  d, bestDist, sumDist, r: double;
  sums: TDenseMatrix;
  counts: array of integer;
begin
  n := points.Rows;
  dim := points.Cols;
  if (n = 0) or (dim = 0) then
    Exit;
  if fK > n then
    fK := n;
  fCentroids := new TDenseMatrix(fK, dim);
  // k-means++: первый центр случайный, дальше — пропорционально D^2.
  c := fRng.NextInt(n);
  for j := 0 to dim - 1 do
    fCentroids.SetValue(0, j, points.Get(c, j));
  for ci := 1 to fK - 1 do
  begin
    sumDist := 0;
    for i := 0 to n - 1 do
    begin
      bestDist := 1e300;
      for c := 0 to ci - 1 do
      begin
        d := 0;
        for j := 0 to dim - 1 do
          d += Sqr(points.Get(i, j) - fCentroids.Get(c, j));
        if d < bestDist then
          bestDist := d;
      end;
      sumDist += bestDist;
    end;
    r := fRng.NextDouble * sumDist;
    pickIdx := 0;
    for i := 0 to n - 1 do
    begin
      bestDist := 1e300;
      for c := 0 to ci - 1 do
      begin
        d := 0;
        for j := 0 to dim - 1 do
          d += Sqr(points.Get(i, j) - fCentroids.Get(c, j));
        if d < bestDist then
          bestDist := d;
      end;
      r -= bestDist;
      if r <= 0 then
      begin
        pickIdx := i;
        Break;
      end;
    end;
    for j := 0 to dim - 1 do
      fCentroids.SetValue(ci, j, points.Get(pickIdx, j));
  end;

  SetLength(fLabels, n);
  sums := new TDenseMatrix(fK, dim);
  SetLength(counts, fK);
  for iter := 1 to Max(1, maxIter) do
  begin
    changed := 0;
    for i := 0 to n - 1 do
    begin
      best := Nearest(points.RowToArray(i));
      if fLabels[i] <> best then
      begin
        fLabels[i] := best;
        Inc(changed);
      end;
    end;
    sums.Zero;
    for c := 0 to fK - 1 do counts[c] := 0;
    for i := 0 to n - 1 do
    begin
      c := fLabels[i];
      Inc(counts[c]);
      for j := 0 to dim - 1 do
        sums.SetValue(c, j, sums.Get(c, j) + points.Get(i, j));
    end;
    emptyCount := 0;
    for c := 0 to fK - 1 do
    begin
      if counts[c] = 0 then
      begin
        Inc(emptyCount);
        for j := 0 to dim - 1 do
          fCentroids.SetValue(c, j, points.Get(fRng.NextInt(n), j));
      end
      else
        for j := 0 to dim - 1 do
          fCentroids.SetValue(c, j, sums.Get(c, j) / counts[c]);
    end;
    if (changed = 0) and (emptyCount = 0) then
      Break;
  end;

  fInertia := 0;
  for i := 0 to n - 1 do
  begin
    c := fLabels[i];
    for j := 0 to dim - 1 do
      fInertia += Sqr(points.Get(i, j) - fCentroids.Get(c, j));
  end;
  sums.Dispose;
end;

function TKMeans.ClusterOf(x: array of double): integer;
begin
  Result := Nearest(x);
end;

end.
