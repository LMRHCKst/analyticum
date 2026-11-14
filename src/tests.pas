program tests;

// Свой мини-фреймворк: ассерты, секции, отчёт, ненулевой exit code при провале.

uses System, System.Collections.Generic, System.Linq, System.IO,
  lib_core, lib_lowlevel, lib_script, lib_ai, lib_analytics, lib_game;

var
  Passed, Failed: integer;

procedure Section(name: string);
begin
  Writeln;
  Writeln('== ', name, ' ==');
end;

function ScriptsDir: string;
var
  candidates: array of string;
  c: string;
begin
  candidates := ['scripts', '..\scripts', '..\..\scripts'];
  foreach c in candidates do
    if System.IO.Directory.Exists(c) then
      Exit(c);
  raise new Exception('каталог scripts не найден');
end;

function OutDir: string;
var
  candidates: array of string;
  c: string;
begin
  candidates := ['out', '..\out'];
  foreach c in candidates do
    if System.IO.Directory.Exists(c) then
      Exit(c);
  System.IO.Directory.CreateDirectory('out');
  Result := 'out';
end;

procedure Check(condition: boolean; name: string);
begin
  if condition then
  begin
    Inc(Passed);
    Writeln('  ok   ', name);
  end
  else
  begin
    Inc(Failed);
    Writeln('  FAIL ', name);
  end;
end;

procedure CheckInt(actual, expected: integer; name: string);
begin
  if actual = expected then
    Check(true, name)
  else
  begin
    Check(false, name);
    Writeln($'       получено {actual}, ожидалось {expected}');
  end;
end;

procedure CheckStr(actual, expected, name: string);
begin
  if actual = expected then
    Check(true, name)
  else
  begin
    Check(false, name);
    Writeln($'       получено "{actual}", ожидалось "{expected}"');
  end;
end;

procedure TestCore;
var
  rng1, rng2: TRng;
  r: TResult<integer, string>;
  o: TOption<integer>;
  p: TPoint;
begin
  Section('M1 core');
  rng1 := new TRng(123);
  rng2 := new TRng(123);
  Check(rng1.NextU64 = rng2.NextU64, 'RNG детерминирован по seed');
  Check(rng1.NextInt(100) <> rng1.NextInt(100), 'RNG не залипает');
  r := new TResult<integer, string>(true, 5, '');
  CheckInt(r.Map(x -> x * 2).Value, 10, 'Result.Map');
  CheckInt(r.Bind(x -> new TResult<integer, string>(true, x + 1, '')).Value, 6, 'Result.Bind');
  o := new TOption<integer>(true, 3);
  CheckInt(o.MatchWith(x -> x * 3, () -> -1), 9, 'Option.MatchWith');
  CheckInt((new TOption<integer>(false, 0)).MatchWith(x -> x, () -> -1), -1, 'Option.None');
  p := new TPoint(2, 3);
  CheckInt((p + new TPoint(1, 1)).X, 3, 'operator +');
  CheckInt(p.Manhattan(new TPoint(0, 0)), 5, 'TPoint.Manhattan');
  CheckInt(Clamp(15, 0, 10), 10, 'Clamp');
end;

procedure TestLowLevel;
var
  arena: TArena;
  p: pointer;
  i: integer;
  aligned: boolean;
  m: TDenseMatrix;
  v, w: array of double;
  path: TPathResult;
  trie: TTrie;
  blocked: array[,] of boolean;
begin
  Section('M2 lowlevel');
  arena := new TArena(65536);
  aligned := true;
  for i := 1 to 1000 do
  begin
    p := arena.Alloc(24, 16);
    if (IntPtr(p).ToInt64 mod 16) <> 0 then aligned := false;
  end;
  CheckInt(arena.LivePointers, 1000, 'arena live до reset');
  Check(aligned, 'arena выравнивает по 16');
  arena.Reset;
  CheckInt(arena.LivePointers, 0, 'arena live после reset');
  arena.Dispose;

  m := new TDenseMatrix(2, 3);
  for i := 0 to 5 do
    m.SetValue(i div 3, i mod 3, i + 1);
  SetLength(v, 3);
  SetLength(w, 2);
  v[0] := 1; v[1] := 1; v[2] := 1;
  m.MatVec(v, w);
  CheckInt(Round(w[0]), 6, 'matrix row-major: r0');
  CheckInt(Round(w[1]), 15, 'matrix row-major: r1');
  m.Dispose;

  SetLength(blocked, 10, 10);
  path := TAStar.FindPath(10, 10, new TPoint(0, 0), new TPoint(9, 9),
    (x, y) -> not blocked[x, y]);
  Check(path.Found, 'A* находит путь');
  CheckInt(path.Cost, 18, 'A* манхэттенская цена');

  trie := new TTrie;
  trie.Insert('save');
  trie.Insert('stats');
  trie.Insert('seed');
  Check(trie.Contains('save'), 'trie contains');
  CheckStr(string.Join(',', trie.Complete('s')), 'save,seed,stats', 'trie autocomplete');
  Check(PerfFrequency > 0, 'QPC frequency > 0');
end;

procedure TestScript;
var
  src, printed, printed2: string;
  p1: TProgramNode;
  cfg: TConfigSet;
  mon: TMonsterSpec;
  j, j2: TJsonValue;
  js: string;
begin
  Section('M3 DSL/JSON');
  src := '''
let scale = (k) -> (x) -> x * k;
let tough = scale(2);
monster orc = { name: "орк"; hp: tough(15); ai: aggressive; loot: [coin x3, potion]; };
item coin { kind: gold; value: 3; }
''';
  p1 := ParseSource(src);
  printed := PrintAst(p1);
  printed2 := PrintAst(ParseSource(printed));
  CheckStr(printed2, printed, 'AST round-trip');

  cfg := new TConfigSet;
  cfg.LoadDirectory(ScriptsDir);
  Check(cfg.Monsters.Count >= 5, 'конфиги монстров загружены');
  Check(cfg.Items.Count >= 4, 'конфиги предметов загружены');
  mon := cfg.Monster('orc');
  CheckInt(mon.Hp, 30, 'карринг base(30)(5): hp');
  CheckInt(mon.Damage, 5, 'карринг base(30)(5): damage');
  CheckInt(Length(mon.Loot), 4, 'loot x3 развёрнут');
  Check(cfg.Monster('boss_butcher').Boss, 'boss-флаг из конфига');

  j := JsonParse('{"b":[true,null,"x"],"a":1}');
  js := j.ToJson;
  j2 := JsonParse(js);
  CheckStr(j2.ToJson, js, 'JSON round-trip');
  CheckStr(JsonParse('"\u043e"').AsString, 'о', 'JSON unicode escape');
end;

procedure TestAI;
var
  rng: TRng;
  x: TDenseMatrix;
  y: array of integer;
  model: TSoftmaxModel;
  i, j, c, hits: integer;
  engine: TAiEngine;
  view: TAgentView;
  km: TKMeans;
  pts: TDenseMatrix;
  labels: array of integer;
begin
  Section('M4 AI');
  rng := new TRng(777);
  x := new TDenseMatrix(300, AI_FEATURE_COUNT);
  SetLength(y, 300);
  for i := 0 to 299 do
  begin
    c := i mod 5;
    y[i] := c;
    for j := 0 to 4 do
      if j = c then x.SetValue(i, j, 1.0) else x.SetValue(i, j, 0.0);
    for j := 5 to AI_FEATURE_COUNT - 1 do
      x.SetValue(i, j, rng.NextDouble * 0.05);
  end;
  model := new TSoftmaxModel(rng, 0.5, 0.0001);
  model.TrainBatch(x, y, 25, 16);
  Check(model.Accuracy(x, y) > 0.9, 'softmax учится на синтетике');
  Check(model.Loss(x, y) < 0.5, 'softmax loss падает');
  model.Dispose;
  x.Dispose;

  engine := new TAiEngine(1234);
  for i := 1 to 60 do
  begin
    view := new TAgentView(1, 0, 1, 0.8, 0.5, false, false, true, false);
    for j := 0 to AI_HISTORY - 1 do
      view.LastActions[j] := 3;
    engine.Observe(view, 3);
  end;
  Check(engine.TrainedBatches >= 2, 'AI-движок обучается батчами');
  engine.Dispose;

  pts := new TDenseMatrix(9, 3);
  for i := 0 to 8 do
  begin
    c := i div 3;
    pts.SetValue(i, 0, c * 10 + rng.NextDouble);
    pts.SetValue(i, 1, c * 10 + rng.NextDouble);
    pts.SetValue(i, 2, c * 10 + rng.NextDouble);
  end;
  km := new TKMeans(3, rng);
  km.Fit(pts);
  labels := km.Labels;
  hits := 0;
  for i := 0 to 8 do
    if labels[i] = labels[(i div 3) * 3] then Inc(hits);
  CheckInt(hits, 9, 'k-means разделяет 3 группы');
  km.Dispose;
  pts.Dispose;
end;

procedure TestGame;
var
  cfg: TConfigSet;
  stats, stats2: TSessionStats;
  g, g2: TGame;
  path: TPathResult;
  i: integer;
  savePath: string;
  ok: boolean;
begin
  Section('M4 игра');
  cfg := new TConfigSet;
  cfg.LoadDirectory(ScriptsDir);
  stats := new TSessionStats(7);
  g := new TGame(cfg, 7, stats);
  Check(g.Map.Rooms.Count > 0, 'BSP создал комнаты');
  Check(g.Player.IsAlive, 'игрок жив на старте');
  Check(g.Enemies.Count > 0, 'враги заспавнены');
  path := TAStar.FindPath(MAP_W, MAP_H,
    new TPoint(g.Player.X, g.Player.Y), g.Map.Stairs,
    (x, y) -> g.Map.IsWalkable(x, y));
  Check(path.Found, 'от игрока до лестницы есть путь');
  g.Map.ComputeFov(g.Player.X, g.Player.Y, 8);
  Check(g.Map.Visible[g.Player.X, g.Player.Y], 'FOV видит игрока');
  Check(g.Map.Explored[g.Player.X, g.Player.Y], 'FOV помечает explored');

  // Буст HP только для теста детерминизма, не для баланса.
  g.Player.Hp := 500;
  g.Player.MaxHp := 500;
  for i := 1 to 20 do
    if not g.Step(TPlayerAction(i mod 4)) then Break;
  savePath := System.IO.Path.Combine(OutDir, 'test_save.json');
  g.SaveTo(savePath);
  stats2 := new TSessionStats(7);
  g2 := new TGame(cfg, 7, stats2);
  ok := true;
  try
    g2.LoadFrom(savePath);
  except
    on e: Exception do
    begin
      ok := false;
      Writeln('  load error: ', e.Message);
    end;
  end;
  Check(ok, 'сохранение загружается реплеем');
  if ok then
  begin
    CheckInt(g2.Turn, g.Turn, 'replay: turn');
    CheckInt(g2.Level, g.Level, 'replay: level');
    CheckInt(g2.ActionLog.Count, g.ActionLog.Count, 'replay: длина журнала');
  end;
  g.Dispose;
  g2.Dispose;
end;

procedure TestAnalytics;
var
  stats: TSessionStats;
  csv, json: string;
  j: TJsonValue;
begin
  Section('M5 аналитика');
  CheckStr(SparklineOf([0.0, 0.5, 1.0]), '▁▅█', 'sparkline');
  stats := new TSessionStats(9);
  stats.RecordTurn;
  stats.RecordAction(0);
  stats.RecordAction(0);
  stats.RecordKill;
  stats.RecordDamage(5, 2);
  CheckInt(stats.Turns, 1, 'stats turns');
  CheckInt(stats.Kills, 1, 'stats kills');
  Check(Length(stats.FrequentActions(2)) > 0, 'stats frequent actions');
  csv := System.IO.Path.Combine(OutDir, 'test_stats.csv');
  json := System.IO.Path.Combine(OutDir, 'test_stats.json');
  stats.ExportCsv(csv);
  stats.ExportJson(json);
  Check(System.IO.File.Exists(csv), 'CSV создан');
  Check(System.IO.File.Exists(json), 'JSON создан');
  j := JsonParse(System.IO.File.ReadAllText(json));
  Check(j <> nil, 'JSON статистики парсится');
  CheckInt(j.Item('turns').AsInt, 1, 'JSON turns');
end;

begin
  Passed := 0;
  Failed := 0;
  Writeln('АНАЛИТИКУМ: тесты');
  TestCore;
  TestLowLevel;
  TestScript;
  TestAI;
  TestGame;
  TestAnalytics;
  Writeln;
  Writeln($'ИТОГО: passed={Passed}, failed={Failed}');
  if Failed > 0 then
    Halt(1);
end.
