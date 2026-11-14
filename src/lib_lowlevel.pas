unit lib_lowlevel;

// M2: низкий уровень.
//  * TArena — bump-аллокатор поверх GetMem/FreeMem, освобождает всё разом;
//  * TDenseMatrix — плотная матрица на сыром указателе, row-major вручную;
//  * TMinHeap + TAStar — своя бинарная куча и A* без коллекций .NET;
//  * TTrie — автодополнение команд;
//  * TPerfTimer — QueryPerformanceCounter через external;
//  * TBench — арена против new/List на 1 млн аллокаций, вывод в консоль и CSV.

interface

uses System, System.Collections.Generic, System.Linq, System.Globalization, System.Runtime.InteropServices, lib_core;

type
  TDisposable = abstract class
    procedure Dispose; virtual; abstract;
  end;

  TMemBlock = record
    Base: pointer;
    Size: integer;
    Used: integer;
  end;

  TArena = class(TDisposable)
  private
    fBlocks: List<TMemBlock>;
    fBlockSize: integer;
    fLive: integer;
    fBytes: int64;
    fAllocCount: int64;
    procedure AddBlock(minSize: integer);
  public
    constructor Create(blockSize: integer := 65536);
    procedure Dispose; override;
    function Alloc(size: integer; alignment: integer := 8): pointer;
    function AllocZero(size: integer; alignment: integer := 8): pointer;
    procedure Reset;
    property LivePointers: integer read fLive;
    property BytesRequested: int64 read fBytes;
    property AllocCount: int64 read fAllocCount;
    property BlockCount: integer read fBlocks.Count;
    property BlockSize: integer read fBlockSize;
  end;

  TDenseMatrix = class(TDisposable)
  private
    fRows, fCols: integer;
    fData: ^double;
  public
    constructor Create(rows, cols: integer; zeroFill: boolean := true);
    procedure Dispose; override;
    property Rows: integer read fRows;
    property Cols: integer read fCols;
    property Data: ^double read fData;
    function Get(r, c: integer): double;
    procedure SetValue(r, c: integer; value: double);
    function RowPtr(r: integer): ^double;
    function RowToArray(r: integer): array of double;
    procedure Fill(value: double);
    procedure Zero;
    procedure CopyFrom(other: TDenseMatrix);
    procedure MatVec(x: array of double; y: array of double);
    procedure TransposeMatVec(x: array of double; y: array of double);
    function DotRow(r: integer; x: array of double): double;
    procedure AxpyRow(r: integer; x: array of double; alpha: double);
    procedure Scale(alpha: double);
    function MaxAbs: double;
    procedure Randomize(rng: TRng; scale: double);
  end;

  THeapNode = record
    Key: integer;
    Pos: TPoint;
  end;

  TMinHeap = class
  private
    fData: array of THeapNode;
    fCount: integer;
    procedure Swap(i, j: integer);
    procedure SiftUp(i: integer);
    procedure SiftDown(i: integer);
  public
    constructor Create(capacity: integer := 16);
    procedure Push(key: integer; p: TPoint);
    function Pop: THeapNode;
    function Peek: THeapNode;
    function IsEmpty: boolean;
    property Count: integer read fCount;
  end;

  TGridPredicate = function(x, y: integer): boolean;
  TCellVisitor = procedure(x, y: integer);

  TPathResult = record
    Found: boolean;
    Cost: integer;
    Visited: integer;
    Path: array of TPoint;
  end;

  TAStar = class
  public
    class function FindPath(width, height: integer; start, goal: TPoint;
      passable: TGridPredicate): TPathResult;
    class function CountReachable(width, height: integer; start: TPoint;
      passable: TGridPredicate): integer;
  end;

  TTrieNode = class
    Children: Dictionary<char, TTrieNode>;
    Terminal: boolean;
    constructor Create;
  end;

  TTrie = class
  private
    fRoot: TTrieNode;
    fCount: integer;
    procedure Collect(node: TTrieNode; prefix: string; items: List<string>);
  public
    constructor Create;
    procedure Insert(word: string);
    function Contains(word: string): boolean;
    function Complete(prefix: string): array of string;
    property Count: integer read fCount;
  end;

  TPerfTimer = class
  private
    fStart: int64;
    fElapsed: int64;
    fRunning: boolean;
  public
    constructor Create;
    procedure Start;
    procedure Stop;
    function ElapsedMs: double;
    function ElapsedTicks: int64;
  end;

  TBenchResult = record
    Name: string;
    Ops: int64;
    Ms: double;
    Bytes: int64;
  end;

  TBenchBox = class
    Value: integer;
    constructor Create(v: integer);
  end;

  TBench = class
  public
    class function ArenaVsManaged(iterations: integer): array of TBenchResult;
    class procedure PrintResults(rows: array of TBenchResult);
    class procedure WriteCsv(path: string; rows: array of TBenchResult);
  end;

function PerfFrequency: int64;

implementation

function QueryPerformanceCounter(var value: int64): boolean;
  external 'kernel32.dll' name 'QueryPerformanceCounter';
function QueryPerformanceFrequency(var value: int64): boolean;
  external 'kernel32.dll' name 'QueryPerformanceFrequency';

var
  GPerfFrequency: int64 = 10000000;

function PerfFrequency: int64;
begin
  Result := GPerfFrequency;
end;

// PascalABC.NET не знает GetMem/FreeMem: язык живёт на managed-памяти.
// Арена берёт сырые блоки у Win32-кучи через Marshal.AllocHGlobal —
// это тот же unmanaged-аллокатор, только вызов идёт через .NET interop.

type
  TDoublePtr = ^double;

function DblPtr(base: pointer; index: integer): TDoublePtr;
begin
  Result := TDoublePtr(IntPtr.Add(IntPtr(base), index * SizeOf(double)).ToPointer);
end;

function RawAlloc(size: integer): pointer;
begin
  Result := pointer(Marshal.AllocHGlobal(size));
end;

procedure ZeroMem(p: pointer; count: integer);
var
  q: PByte;
  i: integer;
begin
  q := PByte(p);
  for i := 0 to count - 1 do
    PByte(IntPtr.Add(IntPtr(pointer(q)), i).ToPointer)^ := 0;
end;

procedure CopyMem(src, dst: pointer; count: integer);
var
  s, d: PByte;
  i: integer;
begin
  s := PByte(src);
  d := PByte(dst);
  for i := 0 to count - 1 do
    PByte(IntPtr.Add(IntPtr(pointer(d)), i).ToPointer)^ := PByte(IntPtr.Add(IntPtr(pointer(s)), i).ToPointer)^;
end;

procedure RawFree(p: pointer);
begin
  Marshal.FreeHGlobal(IntPtr(p));
end;

// ---------------------------------------------------------------- TArena

constructor TArena.Create(blockSize: integer);
begin
  fBlocks := new List<TMemBlock>;
  fBlockSize := Max(1024, blockSize);
  fLive := 0;
  fBytes := 0;
  fAllocCount := 0;
end;

procedure TArena.Dispose;
begin
  Reset;
end;

procedure TArena.AddBlock(minSize: integer);
var
  block: TMemBlock;
  size: integer;
begin
  size := Max(fBlockSize, minSize);
  block.Base := nil;
  block.Base := RawAlloc(size);
  block.Size := size;
  block.Used := 0;
  fBlocks.Add(block);
end;

function TArena.Alloc(size: integer; alignment: integer): pointer;
var
  block: TMemBlock;
  aligned, offset: integer;
begin
  if size <= 0 then
    size := 1;
  if alignment < 1 then
    alignment := 1;
  if (fBlocks.Count = 0) or
     (fBlocks[fBlocks.Count - 1].Size - fBlocks[fBlocks.Count - 1].Used < size + alignment) then
    AddBlock(size + alignment);
  block := fBlocks[fBlocks.Count - 1];
  offset := (block.Used + alignment - 1) div alignment * alignment;
  block.Used := offset + size;
  fBlocks[fBlocks.Count - 1] := block;
  Inc(fLive);
  Inc(fAllocCount);
  fBytes += size;
  Result := IntPtr.Add(IntPtr(block.Base), offset).ToPointer;
end;

function TArena.AllocZero(size: integer; alignment: integer): pointer;
begin
  Result := Alloc(size, alignment);
  ZeroMem(Result, size);
end;

procedure TArena.Reset;
var
  i: integer;
begin
  for i := 0 to fBlocks.Count - 1 do
    RawFree(fBlocks[i].Base);
  fBlocks.Clear;
  fLive := 0;
  fBytes := 0;
  fAllocCount := 0;
end;

// ----------------------------------------------------------- TDenseMatrix

constructor TDenseMatrix.Create(rows, cols: integer; zeroFill: boolean);
begin
  if (rows <= 0) or (cols <= 0) then
    raise new ArgumentException('Матрица должна иметь положительные размеры');
  fRows := rows;
  fCols := cols;
  fData := nil;
  fData := RawAlloc(rows * cols * SizeOf(double));
  if zeroFill then
    Zero;
end;

procedure TDenseMatrix.Dispose;
begin
  if fData <> nil then
  begin
    RawFree(fData);
    fData := nil;
  end;
end;

function TDenseMatrix.Get(r, c: integer): double;
begin
  Result := DblPtr(fData, r * fCols + c)^;
end;

procedure TDenseMatrix.SetValue(r, c: integer; value: double);
begin
  DblPtr(fData, r * fCols + c)^ := value;
end;

function TDenseMatrix.RowPtr(r: integer): ^double;
begin
  Result := DblPtr(fData, r * fCols);
end;

function TDenseMatrix.RowToArray(r: integer): array of double;
var
  c: integer;
begin
  SetLength(Result, fCols);
  for c := 0 to fCols - 1 do
    Result[c] := DblPtr(fData, r * fCols + c)^;
end;

procedure TDenseMatrix.Fill(value: double);
var
  i: integer;
begin
  for i := 0 to fRows * fCols - 1 do
    DblPtr(fData, i)^ := value;
end;

procedure TDenseMatrix.Zero;
begin
  ZeroMem(fData, fRows * fCols * SizeOf(double));
end;

procedure TDenseMatrix.CopyFrom(other: TDenseMatrix);
begin
  if (other.Rows <> fRows) or (other.Cols <> fCols) then
    raise new ArgumentException('Размеры матриц не совпадают');
  CopyMem(other.Data, fData, fRows * fCols * SizeOf(double));
end;

procedure TDenseMatrix.MatVec(x: array of double; y: array of double);
var
  r, c: integer;
  sum: double;
begin
  if (x.Length <> fCols) or (y.Length <> fRows) then
    raise new ArgumentException('MatVec: неверная длина вектора');
  for r := 0 to fRows - 1 do
  begin
    sum := 0;
    for c := 0 to fCols - 1 do
      sum += DblPtr(fData, r * fCols + c)^ * x[c];
    y[r] := sum;
  end;
end;

procedure TDenseMatrix.TransposeMatVec(x: array of double; y: array of double);
var
  r, c: integer;
begin
  if (x.Length <> fRows) or (y.Length <> fCols) then
    raise new ArgumentException('TransposeMatVec: неверная длина вектора');
  for c := 0 to fCols - 1 do
    y[c] := 0;
  for r := 0 to fRows - 1 do
    for c := 0 to fCols - 1 do
      y[c] += DblPtr(fData, r * fCols + c)^ * x[r];
end;

function TDenseMatrix.DotRow(r: integer; x: array of double): double;
var
  c: integer;
begin
  if x.Length <> fCols then
    raise new ArgumentException('DotRow: неверная длина вектора');
  Result := 0;
  for c := 0 to fCols - 1 do
    Result += DblPtr(fData, r * fCols + c)^ * x[c];
end;

procedure TDenseMatrix.AxpyRow(r: integer; x: array of double; alpha: double);
var
  c: integer;
begin
  if x.Length <> fCols then
    raise new ArgumentException('AxpyRow: неверная длина вектора');
  for c := 0 to fCols - 1 do
    DblPtr(fData, r * fCols + c)^ += alpha * x[c];
end;

procedure TDenseMatrix.Scale(alpha: double);
var
  i: integer;
begin
  for i := 0 to fRows * fCols - 1 do
    DblPtr(fData, i)^ *= alpha;
end;

function TDenseMatrix.MaxAbs: double;
var
  i: integer;
  v: double;
begin
  Result := 0;
  for i := 0 to fRows * fCols - 1 do
  begin
    v := Abs(DblPtr(fData, i)^);
    if v > Result then
      Result := v;
  end;
end;

procedure TDenseMatrix.Randomize(rng: TRng; scale: double);
var
  i: integer;
begin
  for i := 0 to fRows * fCols - 1 do
    DblPtr(fData, i)^ := (rng.NextDouble * 2 - 1) * scale;
end;

// ---------------------------------------------------------------- TMinHeap

constructor TMinHeap.Create(capacity: integer);
begin
  SetLength(fData, Max(4, capacity));
  fCount := 0;
end;

procedure TMinHeap.Swap(i, j: integer);
var
  tmp: THeapNode;
begin
  tmp := fData[i];
  fData[i] := fData[j];
  fData[j] := tmp;
end;

procedure TMinHeap.SiftUp(i: integer);
var
  parent: integer;
begin
  while i > 0 do
  begin
    parent := (i - 1) div 2;
    if fData[parent].Key <= fData[i].Key then
      Break;
    Swap(parent, i);
    i := parent;
  end;
end;

procedure TMinHeap.SiftDown(i: integer);
var
  left, right, smallest: integer;
begin
  while true do
  begin
    left := 2 * i + 1;
    right := left + 1;
    smallest := i;
    if (left < fCount) and (fData[left].Key < fData[smallest].Key) then
      smallest := left;
    if (right < fCount) and (fData[right].Key < fData[smallest].Key) then
      smallest := right;
    if smallest = i then
      Break;
    Swap(i, smallest);
    i := smallest;
  end;
end;

procedure TMinHeap.Push(key: integer; p: TPoint);
begin
  if fCount = fData.Length then
    SetLength(fData, fData.Length * 2);
  fData[fCount].Key := key;
  fData[fCount].Pos := p;
  Inc(fCount);
  SiftUp(fCount - 1);
end;

function TMinHeap.Pop: THeapNode;
begin
  if fCount = 0 then
    raise new InvalidOperationException('Куча пуста');
  Result := fData[0];
  Dec(fCount);
  if fCount > 0 then
  begin
    fData[0] := fData[fCount];
    SiftDown(0);
  end;
end;

function TMinHeap.Peek: THeapNode;
begin
  if fCount = 0 then
    raise new InvalidOperationException('Куча пуста');
  Result := fData[0];
end;

function TMinHeap.IsEmpty: boolean;
begin
  Result := fCount = 0;
end;

// ------------------------------------------------------------------ TAStar

class function TAStar.FindPath(width, height: integer; start, goal: TPoint;
  passable: TGridPredicate): TPathResult;
var
  n, i, ci, ni, nx, ny, tentative: integer;
  g: array of integer;
  from: array of TPoint;
  closed: array of boolean;
  heap: TMinHeap;
  cur: THeapNode;
  dirs: array of TPoint;
  d: TPoint;
  found: boolean;
  pathList: List<TPoint>;
  p: TPoint;

begin
  Result.Found := false;
  Result.Cost := 0;
  Result.Visited := 0;
  SetLength(Result.Path, 0);
  if (width <= 0) or (height <= 0) then
    Exit;
  if (start.X < 0) or (start.Y < 0) or (goal.X < 0) or (goal.Y < 0) or
     (start.X >= width) or (goal.X >= width) or (start.Y >= height) or (goal.Y >= height) then
    Exit;
  if start.SameAs(goal) then
  begin
    Result.Found := true;
    SetLength(Result.Path, 1);
    Result.Path[0] := start;
    Exit;
  end;

  n := width * height;
  SetLength(g, n);
  SetLength(from, n);
  SetLength(closed, n);
  for i := 0 to n - 1 do
    g[i] := MaxInt;
  ci := start.Y * width + start.X;
  g[ci] := 0;
  heap := new TMinHeap(64);
  heap.Push(Abs(start.X - goal.X) + Abs(start.Y - goal.Y), start);
  dirs := [new TPoint(0, -1), new TPoint(0, 1), new TPoint(-1, 0), new TPoint(1, 0)];
  found := false;

  while not heap.IsEmpty do
  begin
    cur := heap.Pop;
    ci := cur.Pos.Y * width + cur.Pos.X;
    if closed[ci] then
      Continue;
    closed[ci] := true;
    Inc(Result.Visited);
    if cur.Pos.SameAs(goal) then
    begin
      found := true;
      Break;
    end;
    foreach d in dirs do
    begin
      nx := cur.Pos.X + d.X;
      ny := cur.Pos.Y + d.Y;
      if (nx < 0) or (ny < 0) or (nx >= width) or (ny >= height) then
        Continue;
      if not passable(nx, ny) then
        Continue;
      ni := ny * width + nx;
      tentative := g[ci] + 1;
      if tentative < g[ni] then
      begin
        g[ni] := tentative;
        from[ni] := cur.Pos;
        heap.Push(tentative + Abs(nx - goal.X) + Abs(ny - goal.Y), new TPoint(nx, ny));
      end;
    end;
  end;

  if not found then
    Exit;

  Result.Found := true;
  Result.Cost := g[goal.Y * width + goal.X];
  pathList := new List<TPoint>;
  p := goal;
  while not p.SameAs(start) do
  begin
    pathList.Add(p);
    p := from[p.Y * width + p.X];
  end;
  pathList.Add(start);
  pathList.Reverse;
  Result.Path := pathList.ToArray;
end;

class function TAStar.CountReachable(width, height: integer; start: TPoint;
  passable: TGridPredicate): integer;
var
  seen: array of boolean;
  q: Queue<TPoint>;
  cur, np: TPoint;
  dirs: array of TPoint;
  d: TPoint;
  nx, ny, idx: integer;
begin
  Result := 0;
  if (width <= 0) or (height <= 0) then
    Exit;
  SetLength(seen, width * height);
  q := new Queue<TPoint>;
  q.Enqueue(start);
  idx := start.Y * width + start.X;
  seen[idx] := true;
  dirs := [new TPoint(0, -1), new TPoint(0, 1), new TPoint(-1, 0), new TPoint(1, 0)];
  while q.Count > 0 do
  begin
    cur := q.Dequeue;
    Inc(Result);
    foreach d in dirs do
    begin
      nx := cur.X + d.X;
      ny := cur.Y + d.Y;
      if (nx < 0) or (ny < 0) or (nx >= width) or (ny >= height) then
        Continue;
      idx := ny * width + nx;
      if seen[idx] then
        Continue;
      if not passable(nx, ny) then
        Continue;
      seen[idx] := true;
      np := new TPoint(nx, ny);
      q.Enqueue(np);
    end;
  end;
end;

// ------------------------------------------------------------------- TTrie

constructor TTrieNode.Create;
begin
  Children := new Dictionary<char, TTrieNode>;
  Terminal := false;
end;

constructor TTrie.Create;
begin
  fRoot := new TTrieNode;
  fCount := 0;
end;


procedure TTrie.Insert(word: string);
var
  node: TTrieNode;
  i: integer;
  ch: char;
  next: TTrieNode;
begin
  if word = '' then
    Exit;
  node := fRoot;
  for i := 1 to word.Length do
  begin
    ch := LowerCase(word[i]);
    if not node.Children.TryGetValue(ch, next) then
    begin
      next := new TTrieNode;
      node.Children[ch] := next;
    end;
    node := next;
  end;
  if not node.Terminal then
  begin
    node.Terminal := true;
    Inc(fCount);
  end;
end;

function TTrie.Contains(word: string): boolean;
var
  node: TTrieNode;
  i: integer;
  ch: char;
  next: TTrieNode;
begin
  node := fRoot;
  for i := 1 to word.Length do
  begin
    ch := LowerCase(word[i]);
    if not node.Children.TryGetValue(ch, next) then
      Exit(false);
    node := next;
  end;
  Result := node.Terminal;
end;

procedure TTrie.Collect(node: TTrieNode; prefix: string; items: List<string>);
var
  pair: KeyValuePair<char, TTrieNode>;
  ch: char;
begin
  if node.Terminal then
    items.Add(prefix);
  foreach pair in node.Children do
  begin
    ch := pair.Key;
    Collect(pair.Value, prefix + ch, items);
  end;
end;

function TTrie.Complete(prefix: string): array of string;
var
  node: TTrieNode;
  i: integer;
  ch: char;
  next: TTrieNode;
  items: List<string>;
begin
  node := fRoot;
  for i := 1 to prefix.Length do
  begin
    ch := LowerCase(prefix[i]);
    if not node.Children.TryGetValue(ch, next) then
      Exit([]);
    node := next;
  end;
  items := new List<string>;
  Collect(node, LowerCase(prefix), items);
  items.Sort;
  Result := items.ToArray;
end;

// --------------------------------------------------------------- TPerfTimer

constructor TPerfTimer.Create;
begin
  fStart := 0;
  fElapsed := 0;
  fRunning := false;
end;

procedure TPerfTimer.Start;
begin
  QueryPerformanceCounter(fStart);
  fRunning := true;
end;

procedure TPerfTimer.Stop;
var
  nowTicks: int64;
begin
  if not fRunning then
    Exit;
  QueryPerformanceCounter(nowTicks);
  fElapsed := nowTicks - fStart;
  fRunning := false;
end;

function TPerfTimer.ElapsedTicks: int64;
var
  nowTicks: int64;
begin
  if fRunning then
  begin
    QueryPerformanceCounter(nowTicks);
    Result := nowTicks - fStart;
  end
  else
    Result := fElapsed;
end;

function TPerfTimer.ElapsedMs: double;
begin
  Result := ElapsedTicks * 1000.0 / GPerfFrequency;
end;

// ------------------------------------------------------------------- TBench

constructor TBenchBox.Create(v: integer);
begin
  Value := v;
end;

class function TBench.ArenaVsManaged(iterations: integer): array of TBenchResult;
var
  arena: TArena;
  timer: TPerfTimer;
  rows: array of TBenchResult;
  lst: List<System.Object>;
  mem0, mem1: int64;
  i: integer;
  p: pointer;
begin
  SetLength(rows, 2);
  iterations := Max(1, iterations);

  // Прогрев JIT и аллокатора.
  arena := new TArena(65536);
  for i := 1 to 10000 do
    p := arena.Alloc(32);
  arena.Dispose;
  arena := nil;

  arena := new TArena(65536);
  timer := new TPerfTimer;
  timer.Start;
  for i := 1 to iterations do
    p := arena.Alloc(32);
  timer.Stop;
  rows[0].Name := 'arena/GetMem';
  rows[0].Ops := iterations;
  rows[0].Ms := timer.ElapsedMs;
  rows[0].Bytes := arena.BytesRequested;
  arena.Dispose;
  arena := nil;

  GC.Collect;
  GC.WaitForPendingFinalizers;
  GC.Collect;
  mem0 := GC.GetTotalMemory(true);
  lst := new List<System.Object>;
  timer := new TPerfTimer;
  timer.Start;
  for i := 1 to iterations do
  begin
    var box := new TBenchBox(i);
    lst.Add(box);
  end;
  timer.Stop;
  mem1 := GC.GetTotalMemory(false);
  rows[1].Name := 'new/List<System.Object>';
  rows[1].Ops := iterations;
  rows[1].Ms := timer.ElapsedMs;
  rows[1].Bytes := Max(0, mem1 - mem0);
  lst.Clear;
  lst := nil;

  Result := rows;
end;

class procedure TBench.PrintResults(rows: array of TBenchResult);
var
  r: TBenchResult;
  ns: double;
begin
  Writeln('  операция                млн/с      нс/оп      память');
  Writeln('  ---------------------------------------------------------');
  foreach r in rows do
  begin
    if r.Ms > 0 then
      ns := r.Ms * 1000000.0 / r.Ops
    else
      ns := 0;
    Writeln(Format('  {0,-22} {1,8:0.00} {2,10:0.0} {3,10:0.0} МБ',
      r.Name, r.Ops / (r.Ms * 1000.0), ns, r.Bytes / 1048576.0));
  end;
end;

class procedure TBench.WriteCsv(path: string; rows: array of TBenchResult);
var
  sb: StringBuilder;
  r: TBenchResult;
  ns: double;
begin
  sb := new StringBuilder;
  sb.AppendLine('operation,ops,ms,ns_per_op,bytes');
  foreach r in rows do
  begin
    if r.Ms > 0 then
      ns := r.Ms * 1000000.0 / r.Ops
    else
      ns := 0;
    sb.AppendFormat(CultureInfo.InvariantCulture, '{0},{1},{2:0.###},{3:0.0},{4}',
      r.Name, r.Ops, r.Ms, ns, r.Bytes);
    sb.AppendLine;
  end;
  System.IO.File.WriteAllText(path, sb.ToString);
end;

initialization
  if (not QueryPerformanceFrequency(GPerfFrequency)) or (GPerfFrequency <= 0) then
    GPerfFrequency := 10000000;

end.














