unit lib_analytics;

// M5: локальная аналитика без сервера. Все срезы считаются LINQ-пайплайнами
// на лету, экспорт — свой CSV и свой JSON из lib_script.

interface

uses System, System.Collections.Generic, System.Linq, System.Text, System.IO,
  System.Globalization, lib_core, lib_script;

const
  ACTION_NAMES: array[0..7] of string = (
    'вверх', 'вниз', 'влево', 'вправо', 'ждать', 'зелье', 'лестница', 'осмотреться');

type
  TSessionStats = class
  private
    fSeed: uint64;
    fStart: DateTime;
    fTurns, fKills, fDamageDealt, fDamageTaken, fItemsUsed: integer;
    fLevels, fGold, fDeaths, fWins, fBatches: integer;
    fActionCounts: array[0..7] of integer;
    fAccuracy, fLoss: List<double>;
    fLastPrediction: string;
    fLastConfidence: double;
    fStyle: string;
    fCluster: integer;
  public
    constructor Create(seed: uint64);
    procedure Reset(seed: uint64);
    procedure RecordTurn;
    procedure RecordAction(kind: integer);
    procedure RecordKill;
    procedure RecordDamage(dealt, taken: integer);
    procedure RecordItem;
    procedure RecordLevel;
    procedure RecordGold(value: integer);
    procedure RecordDeath;
    procedure RecordWin;
    procedure UpdateModel(accuracy, loss: array of double; batches: integer);
    procedure SetPrediction(text: string; confidence: double);
    procedure SetStyle(style: string; cluster: integer);
    function SurvivalSeconds: double;
    function FrequentActions(topN: integer): array of string;
    function LastAccuracy(n: integer): array of double;
    function Sparkline: string;
    function Summary: string;
    procedure ExportCsv(path: string);
    procedure ExportJson(path: string);
    property Turns: integer read fTurns;
    property Kills: integer read fKills;
    property Accuracy: List<double> read fAccuracy;
    property Loss: List<double> read fLoss;
    property Batches: integer read fBatches;
    property Style: string read fStyle;
    property Cluster: integer read fCluster;
    property LastPrediction: string read fLastPrediction;
    property LastConfidence: double read fLastConfidence;
  end;

function ActionName(kind: integer): string;
function SparklineOf(values: array of double): string;
function JoinText(separator: string; params parts: array of string): string;

implementation

function ActionName(kind: integer): string;
begin
  if (kind >= 0) and (kind <= 7) then
    Result := ACTION_NAMES[kind]
  else
    Result := '?';
end;

function SparklineOf(values: array of double): string;
const
  blocks: array[0..7] of char = ('▁', '▂', '▃', '▄', '▅', '▆', '▇', '█');
var
  i, idx: integer;
  lo, hi, v: double;
  sb: StringBuilder;
begin
  if values.Length = 0 then
    Exit('—');
  lo := values[0];
  hi := values[0];
  for i := 1 to values.Length - 1 do
  begin
    if values[i] < lo then lo := values[i];
    if values[i] > hi then hi := values[i];
  end;
  sb := new StringBuilder;
  for i := 0 to values.Length - 1 do
  begin
    if Abs(hi - lo) < 1e-12 then
      idx := 4
    else
    begin
      v := (values[i] - lo) / (hi - lo);
      idx := Round(v * 7);
    end;
    sb.Append(blocks[idx]);
  end;
  Result := sb.ToString;
end;

function JoinText(separator: string; params parts: array of string): string;
var
  i: integer;
  sb: StringBuilder;
begin
  sb := new StringBuilder;
  for i := 0 to High(parts) do
  begin
    if i > 0 then sb.Append(separator);
    sb.Append(parts[i]);
  end;
  Result := sb.ToString;
end;

constructor TSessionStats.Create(seed: uint64);
begin
  Reset(seed);
end;

procedure TSessionStats.Reset(seed: uint64);
var
  i: integer;
begin
  fSeed := seed;
  fStart := DateTime.Now;
  fTurns := 0;
  fKills := 0;
  fDamageDealt := 0;
  fDamageTaken := 0;
  fItemsUsed := 0;
  fLevels := 0;
  fGold := 0;
  fDeaths := 0;
  fWins := 0;
  fBatches := 0;
  for i := 0 to 7 do
    fActionCounts[i] := 0;
  fAccuracy := new List<double>;
  fLoss := new List<double>;
  fLastPrediction := '—';
  fLastConfidence := 0;
  fStyle := 'не определён';
  fCluster := -1;
end;

procedure TSessionStats.RecordTurn;
begin
  Inc(fTurns);
end;

procedure TSessionStats.RecordAction(kind: integer);
begin
  if (kind >= 0) and (kind <= 7) then
    Inc(fActionCounts[kind]);
end;

procedure TSessionStats.RecordKill;
begin
  Inc(fKills);
end;

procedure TSessionStats.RecordDamage(dealt, taken: integer);
begin
  fDamageDealt += dealt;
  fDamageTaken += taken;
end;

procedure TSessionStats.RecordItem;
begin
  Inc(fItemsUsed);
end;

procedure TSessionStats.RecordLevel;
begin
  Inc(fLevels);
end;

procedure TSessionStats.RecordGold(value: integer);
begin
  fGold += value;
end;

procedure TSessionStats.RecordDeath;
begin
  Inc(fDeaths);
end;

procedure TSessionStats.RecordWin;
begin
  Inc(fWins);
end;

procedure TSessionStats.UpdateModel(accuracy, loss: array of double; batches: integer);
var
  i: integer;
begin
  fAccuracy.Clear;
  fLoss.Clear;
  for i := 0 to High(accuracy) do
    fAccuracy.Add(accuracy[i]);
  for i := 0 to High(loss) do
    fLoss.Add(loss[i]);
  fBatches := batches;
end;

procedure TSessionStats.SetPrediction(text: string; confidence: double);
begin
  fLastPrediction := text;
  fLastConfidence := confidence;
end;

procedure TSessionStats.SetStyle(style: string; cluster: integer);
begin
  fStyle := style;
  fCluster := cluster;
end;

function TSessionStats.SurvivalSeconds: double;
begin
  Result := (DateTime.Now - fStart).TotalSeconds;
end;

function TSessionStats.FrequentActions(topN: integer): array of string;
begin
  Result := (0..7)
    .Where(i -> fActionCounts[i] > 0)
    .OrderByDescending(i -> fActionCounts[i])
    .Take(Max(1, topN))
    .Select(i -> $'{ACTION_NAMES[i]} {fActionCounts[i]}')
    .ToArray;
end;

function TSessionStats.LastAccuracy(n: integer): array of double;
var
  a: array of double;
begin
  a := fAccuracy.ToArray;
  if a.Length = 0 then
    Exit([]);
  Result := a[Max(0, a.Length - n):];
end;

function TSessionStats.Sparkline: string;
begin
  Result := SparklineOf(fAccuracy.ToArray);
end;

function TSessionStats.Summary: string;
var
  sb: StringBuilder;
  total: integer;
begin
  total := (0..7).Aggregate(0, (acc, i) -> acc + fActionCounts[i]);
  sb := new StringBuilder;
  sb.AppendLine('  Ходов:        ' + fTurns.ToString);
  sb.AppendLine('  Действий:     ' + total.ToString);
  sb.AppendLine('  Убито:        ' + fKills.ToString);
  sb.AppendLine('  Урон:         ' + fDamageDealt.ToString + ' нанесено / ' + fDamageTaken.ToString + ' получено');
  sb.AppendLine('  Уровень:      ' + fLevels.ToString + ', золото: ' + fGold.ToString);
  sb.AppendLine('  Предметы:     ' + fItemsUsed.ToString);
  sb.AppendLine('  Модель:       ' + fBatches.ToString + ' батчей, точность ' + Sparkline);
  sb.AppendLine('  Предсказание: ' + fLastPrediction + ' (' + fLastConfidence.ToString('0.00', CultureInfo.InvariantCulture) + ')');
  sb.AppendLine('  Стиль:        ' + fStyle + ' (cluster ' + fCluster.ToString + ')');
  sb.Append('  Частые ходы:  ');
  sb.Append(JoinText(', ', FrequentActions(3)));
  Result := sb.ToString;
end;

procedure TSessionStats.ExportCsv(path: string);
var
  sb: StringBuilder;
  i: integer;
begin
  sb := new StringBuilder;
  sb.AppendLine('metric,value');
  sb.AppendLine('seed,' + fSeed.ToString);
  sb.AppendLine('turns,' + fTurns.ToString);
  sb.AppendLine('kills,' + fKills.ToString);
  sb.AppendLine('damage_dealt,' + fDamageDealt.ToString);
  sb.AppendLine('damage_taken,' + fDamageTaken.ToString);
  sb.AppendLine('items_used,' + fItemsUsed.ToString);
  sb.AppendLine('levels,' + fLevels.ToString);
  sb.AppendLine('gold,' + fGold.ToString);
  sb.AppendLine('deaths,' + fDeaths.ToString);
  sb.AppendLine('wins,' + fWins.ToString);
  sb.AppendLine('batches,' + fBatches.ToString);
  sb.AppendLine('survival_seconds,' + SurvivalSeconds.ToString('0.000', CultureInfo.InvariantCulture));
  sb.AppendLine;
  sb.AppendLine('epoch,accuracy,loss');
  for i := 0 to Min(fAccuracy.Count, fLoss.Count) - 1 do
    sb.AppendLine((i + 1).ToString + ',' +
      fAccuracy[i].ToString('0.0000', CultureInfo.InvariantCulture) + ',' +
      fLoss[i].ToString('0.0000', CultureInfo.InvariantCulture));
  sb.AppendLine;
  sb.AppendLine('action,count');
  for i := 0 to 7 do
    sb.AppendLine(ACTION_NAMES[i] + ',' + fActionCounts[i].ToString);
  System.IO.File.WriteAllText(path, sb.ToString);
end;

procedure TSessionStats.ExportJson(path: string);
var
  root, actions, acc, loss: TJsonValue;
  i: integer;
begin
  root := JObject;
  root.Put('seed', JInt(int64(fSeed)));
  root.Put('turns', JInt(fTurns));
  root.Put('kills', JInt(fKills));
  root.Put('damage_dealt', JInt(fDamageDealt));
  root.Put('damage_taken', JInt(fDamageTaken));
  root.Put('items_used', JInt(fItemsUsed));
  root.Put('levels', JInt(fLevels));
  root.Put('gold', JInt(fGold));
  root.Put('deaths', JInt(fDeaths));
  root.Put('wins', JInt(fWins));
  root.Put('batches', JInt(fBatches));
  root.Put('survival_seconds', JFloat(SurvivalSeconds));
  root.Put('style', JStr(fStyle));
  root.Put('cluster', JInt(fCluster));
  root.Put('prediction', JStr(fLastPrediction));
  root.Put('confidence', JFloat(fLastConfidence));
  actions := JObject;
  for i := 0 to 7 do
    actions.Put(ACTION_NAMES[i], JInt(fActionCounts[i]));
  root.Put('actions', actions);
  acc := JArray;
  for i := 0 to fAccuracy.Count - 1 do
    acc.Add(JFloat(fAccuracy[i]));
  root.Put('accuracy', acc);
  loss := JArray;
  for i := 0 to fLoss.Count - 1 do
    loss.Add(JFloat(fLoss[i]));
  root.Put('loss', loss);
  System.IO.File.WriteAllText(path, root.ToJson);
end;

end.
