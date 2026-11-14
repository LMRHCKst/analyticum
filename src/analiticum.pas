program analiticum;

// АНАЛИТИКУМ: прототип. Один процесс, один exe, без сети.
// Интерактивный рогалик + demo-режим + бенчмарки + реплей сохранения.

uses System, System.Collections.Generic, System.Linq, System.Text, System.IO,
  lib_core, lib_lowlevel, lib_script, lib_ai, lib_analytics, lib_game;

var
  GConfig: TConfigSet;
  GStats: TSessionStats;
  GGame: TGame;
  GQuit: boolean;
  GScriptsDir, GOutDir: string;
  GCommands: TTrie;

function Fit(self: string; width: integer): string; extensionmethod;
begin
  if self.Length >= width then
    Result := Copy(self, 1, width)
  else
    Result := self + RepeatText(' ', width - self.Length);
end;

procedure Fatal(message: string);
begin
  Writeln('Ошибка: ', message);
  Halt(1);
end;

function FindScriptsDir: string;
var
  exeDir: string;
  candidates: array of string;
  c: string;
begin
  candidates := [
    System.IO.Path.Combine(System.IO.Directory.GetCurrentDirectory(), 'scripts'),
    System.IO.Path.Combine(System.IO.Path.GetDirectoryName(
      System.Reflection.Assembly.GetExecutingAssembly.Location), 'scripts'),
    System.IO.Path.GetFullPath(System.IO.Path.Combine(
      System.IO.Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly.Location), '..\scripts')),
    System.IO.Path.GetFullPath(System.IO.Path.Combine(
      System.IO.Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly.Location), '..\..\scripts'))
  ];
  foreach c in candidates do
    if System.IO.Directory.Exists(c) then
      Exit(c);
  Fatal('каталог scripts не найден; запускай из корня проекта');
end;

procedure InitConfig;
begin
  GScriptsDir := FindScriptsDir;
  GOutDir := System.IO.Path.Combine(System.IO.Path.GetDirectoryName(GScriptsDir), 'out');
  if not System.IO.Directory.Exists(GOutDir) then
    System.IO.Directory.CreateDirectory(GOutDir);
  GConfig := new TConfigSet;
  GConfig.LoadDirectory(GScriptsDir);
end;

function AliveEnemies(g: TGame): integer;
var
  e: TEnemy;
begin
  Result := 0;
  foreach e in g.Enemies do
    if e.IsAlive then
      Inc(Result);
end;

function HpBar(hp, maxHp: integer): string;
var
  n, i: integer;
  sb: StringBuilder;
begin
  n := Round(10.0 * Clamp(hp, 0, maxHp) / Max(1, maxHp));
  sb := new StringBuilder;
  for i := 1 to 10 do
    if i <= n then sb.Append('█') else sb.Append('░');
  Result := sb.ToString;
end;

function Sidebar(g: TGame): List<string>;
var
  lines: List<string>;
  acc, conf: double;
  hist: array of double;
  boss: string;
begin
  lines := new List<string>;
  for var i := 0 to MAP_H - 1 do lines.Add('');
  lines[0] := 'АНАЛИТИКУМ';
  lines[1] := $'HP {g.Player.Hp}/{g.Player.MaxHp} {HpBar(g.Player.Hp, g.Player.MaxHp)}';
  lines[2] := $'Уровень {g.Level}  ход {g.Turn}';
  lines[3] := $'Золото {g.Player.Gold}  зелья {g.Player.Potions}';
  lines[4] := $'Врагов {AliveEnemies(g)}  атака {g.Player.Attack}';
  lines[5] := '--- модель ---';
  lines[6] := $'батчей {g.Ai.TrainedBatches}  буфер {g.Ai.Buffer.Count}';
  hist := g.Ai.AccuracyHistory;
  if Length(hist) > 0 then acc := hist[High(hist)] else acc := 0;
  lines[7] := $'точность {acc:0.00}';
  lines[8] := '  ' + SparklineOf(hist);
  lines[9] := $'прогноз {ActionName(g.LastPrediction.Best)} {g.LastPrediction.Confidence:0.00}';
  lines[10] := '--- стиль ---';
  lines[11] := g.Stats.Style + ' / ' + g.Stats.Cluster.ToString;
  if g.Level = 3 then
  begin
    boss := g.BossKey;
    if g.BossAlive then boss := boss + ' жив' else boss := boss + ' мёртв';
    lines[12] := 'Босс: ' + boss;
  end;
  lines[13] := '--- управление ---';
  lines[14] := 'WASD/стрелки, . ждать';
  lines[15] := 'u зелье, > лестница';
  lines[16] := 'i инвентарь, Tab статы';
  lines[17] := ': команда, ? помощь, q выход';
  Result := lines;
end;

procedure RenderGame(g: TGame; interactive: boolean);
var
  x, y, i, idx: integer;
  ch: char;
  color: ConsoleColor;
  side: List<string>;
  it: TItemEntity;
  e: TEnemy;
  visible: boolean;
  showEnemy, showItem: boolean;
begin
  if interactive and (not Console.IsOutputRedirected) then
    Console.Clear
  else
    Writeln($'--- ход {g.Turn}, уровень {g.Level} ---');
  side := Sidebar(g);
  for y := 0 to MAP_H - 1 do
  begin
    for x := 0 to MAP_W - 1 do
    begin
      ch := ' ';
      color := ConsoleColor.Gray;
      visible := g.Map.Visible[x, y];
      if (g.Player.X = x) and (g.Player.Y = y) then
      begin
        ch := '@';
        color := ConsoleColor.Yellow;
      end
      else if visible then
      begin
        showEnemy := false;
        foreach e in g.Enemies do
          if e.IsAlive and (e.X = x) and (e.Y = y) then
          begin
            ch := e.Glyph;
            color := ConsoleColor.Red;
            showEnemy := true;
            Break;
          end;
        showItem := false;
        if not showEnemy then
          foreach it in g.Items do
            if (it.X = x) and (it.Y = y) then
            begin
              ch := GConfig.Item(it.Key).Glyph;
              color := ConsoleColor.Cyan;
              showItem := true;
              Break;
            end;
        if (not showEnemy) and (not showItem) then
          case g.Map.Tiles[x, y] of
            tWall: begin ch := '#'; color := ConsoleColor.Gray; end;
            tFloor: begin ch := '.'; color := ConsoleColor.DarkGray; end;
            tStairs: begin ch := '>'; color := ConsoleColor.Green; end;
          end;
      end
      else if g.Map.Explored[x, y] then
      begin
        if g.Map.Tiles[x, y] = tWall then
        begin
          ch := '#';
          color := ConsoleColor.DarkGray;
        end
        else if g.Map.Tiles[x, y] = tStairs then
        begin
          ch := '>';
          color := ConsoleColor.DarkGreen;
        end
        else
        begin
          ch := '.';
          color := ConsoleColor.DarkGray;
        end;
      end;
      if Console.IsOutputRedirected then
        Write(ch)
      else
      begin
        Console.ForegroundColor := color;
        Write(ch);
      end;
    end;
    if not Console.IsOutputRedirected then
      Console.ResetColor;
    Writeln('  ' + side[y]);
  end;
  Writeln;
  idx := Max(0, g.Messages.Count - 5);
  for i := idx to g.Messages.Count - 1 do
    Writeln('  ' + g.Messages[i]);
  if not interactive then
    Writeln;
end;

procedure WaitAnyKey;
begin
  if not Console.IsOutputRedirected then
  begin
    Writeln;
    Writeln('  [Enter] — назад');
    Console.ReadKey(true);
  end;
end;

procedure RenderDashboard(g: TGame);
var
  c: integer;
  pred: TPrediction;
  pair: (string, integer);
  counts: array of integer;
  labelsText: array of string;
begin
  if not Console.IsOutputRedirected then Console.Clear;
  Writeln('=== ДАШБОРД ===');
  Writeln(g.Stats.Summary);
  pair := (g.Stats.Style, g.Stats.Cluster);
  Writeln($'  Стиль: {pair.Item1} / {pair.Item2}');
  Writeln('  Точность (12): ' + SparklineOf(g.Stats.LastAccuracy(12)));
  Writeln('  Враги по AI: ' + string.Join(', ',
    g.Enemies.Where(e -> e.IsAlive).GroupBy(e -> e.Ai)
      .Select(gr -> $'{gr.Key}:{gr.Count()}').ToArray));
  Writeln;
  Writeln('  TCP-точность: ' + SparklineOf(g.Ai.AccuracyHistory));
  Writeln('  Потери:       ' + SparklineOf(g.Ai.LossHistory));
  Writeln($'  Модель: {g.Ai.TrainedBatches} батчей, буфер {g.Ai.Buffer.Count}, обучение каждые 20 ходов');
  counts := g.Ai.Buffer.LabelCounts;
  SetLength(labelsText, AI_ACTION_COUNT);
  for c := 0 to AI_ACTION_COUNT - 1 do
    labelsText[c] := $'{ActionName(c)}:{counts[c]}';
  Writeln('  Буфер по ходам: ' + JoinText(', ', labelsText));
  Writeln('  Вероятности следующего хода:');
  pred := g.LastPrediction;
  for c := 0 to AI_ACTION_COUNT - 1 do
    if c < Length(pred.Probs) then
      Writeln($'    {ActionName(c),-10} {pred.Probs[c]:0.00}');
  Writeln;
  Writeln('  Сохранение/загрузка — :save / :load, экспорт — :export');
  WaitAnyKey;
end;

procedure RenderInventory(g: TGame);
var
  keys: List<string>;
  k: string;
  spec: TItemSpec;
begin
  if not Console.IsOutputRedirected then Console.Clear;
  Writeln('=== ИНВЕНТАРЬ ===');
  Writeln($'  Золото: {g.Player.Gold}, зелья: {g.Player.Potions}, атака: {g.Player.Attack}');
  keys := new List<string>;
  foreach k in g.Player.Inventory.Keys do keys.Add(k);
  keys.Sort;
  foreach k in keys do
  begin
    spec := GConfig.Item(k);
    Writeln($'  {spec.Glyph} {spec.Name.Fit(18)} x{g.Player.Inventory[k]}  ({spec.Kind})');
  end;
  if keys.Count = 0 then
    Writeln('  пусто');
  WaitAnyKey;
end;

procedure RenderHelp;
begin
  if not Console.IsOutputRedirected then Console.Clear;
  Writeln('=== ПОМОЩЬ ===');
  Writeln('  WASD / стрелки — шаг, . или пробел — ждать');
  Writeln('  u или p — выпить зелье, > — спуститься по лестнице');
  Writeln('  i — инвентарь, Tab — дашборд, ? — помощь, q — выход');
  Writeln('  : — командная строка с автодополнением по Tab');
  Writeln('  команды: save [путь], load [путь], stats, export, seed, help, quit');
  WaitAnyKey;
end;

function ReadCommandLine: string;
var
  buf: string;
  comps: array of string;
  compIdx: integer;
  lastPrefix: string;
  k: ConsoleKeyInfo;
begin
  buf := '';
  comps := [];
  compIdx := 0;
  lastPrefix := '';
  while true do
  begin
    Console.Write(#13 + ':' + buf + RepeatText(' ', 30));
    if not Console.IsOutputRedirected then
      Console.CursorLeft := 1 + buf.Length;
    k := Console.ReadKey(true);
    if k.Key = ConsoleKey.Enter then
    begin
      Writeln;
      Exit(buf);
    end;
    if k.Key = ConsoleKey.Escape then
    begin
      Writeln;
      Exit('');
    end;
    if k.Key = ConsoleKey.Backspace then
    begin
      if buf.Length > 0 then
        buf := Copy(buf, 1, buf.Length - 1);
      lastPrefix := '';
      Continue;
    end;
    if k.Key = ConsoleKey.Tab then
    begin
      if (lastPrefix <> buf) or (Length(comps) = 0) then
      begin
        comps := GCommands.Complete(buf);
        compIdx := 0;
        lastPrefix := buf;
      end;
      if Length(comps) > 0 then
      begin
        buf := comps[compIdx];
        compIdx := (compIdx + 1) mod Length(comps);
      end;
      Continue;
    end;
    if (not Char.IsControl(k.KeyChar)) and (k.KeyChar <> #0) then
    begin
      buf += k.KeyChar;
      lastPrefix := '';
    end;
  end;
end;

procedure ExecuteCommand(g: TGame; line: string);
var
  verb, arg, path: string;
  sp: integer;
begin
  sp := line.IndexOf(' ');
  if sp < 0 then
  begin
    verb := LowerCase(line);
    arg := '';
  end
  else
  begin
    verb := LowerCase(Copy(line, 1, sp - 1));
    arg := Trim(Copy(line, sp + 1, line.Length - sp));
  end;
  case verb of
    'save':
      begin
        if arg = '' then path := System.IO.Path.Combine(GOutDir, 'save.json') else path := arg;
        g.SaveTo(path);
        Writeln('  сохранено: ', path);
      end;
    'load':
      begin
        if arg = '' then path := System.IO.Path.Combine(GOutDir, 'save.json') else path := arg;
        g.LoadFrom(path);
        Writeln('  загружено: ', path);
        RenderGame(g, true);
      end;
    'stats': RenderDashboard(g);
    'export':
      begin
        path := System.IO.Path.Combine(GOutDir, $'session_{g.Seed}.csv');
        g.Stats.ExportCsv(path);
        Writeln('  CSV: ', path);
        path := System.IO.Path.Combine(GOutDir, $'session_{g.Seed}.json');
        g.Stats.ExportJson(path);
        Writeln('  JSON: ', path);
      end;
    'seed': Writeln('  seed = ', g.Seed);
    'help': RenderHelp;
    'quit': GQuit := true;
  else
    Writeln('  неизвестная команда: ', verb, ' (help — список)');
  end;
end;

function ActionFromDelta(dxx, dyy: integer): TPlayerAction;
begin
  if dyy < 0 then Result := paUp
  else if dyy > 0 then Result := paDown
  else if dxx < 0 then Result := paLeft
  else if dxx > 0 then Result := paRight
  else Result := paWait;
end;

function MoveToward(g: TGame; tx, ty: integer): TPlayerAction;
var
  dx, dy: integer;
  path: TPathResult;
  passable: TGridPredicate;
  p: TPoint;
begin
  passable := (x, y) -> g.Map.IsWalkable(x, y);
  path := TAStar.FindPath(MAP_W, MAP_H,
    new TPoint(g.Player.X, g.Player.Y), new TPoint(tx, ty), passable);
  if path.Found and (path.Path.Length > 1) then
  begin
    p := path.Path[1];
    Exit(ActionFromDelta(p.X - g.Player.X, p.Y - g.Player.Y));
  end;

  dx := SignOf(tx - g.Player.X);
  dy := SignOf(ty - g.Player.Y);
  if Abs(tx - g.Player.X) >= Abs(ty - g.Player.Y) then
  begin
    if (dx <> 0) and g.Map.IsWalkable(g.Player.X + dx, g.Player.Y) then
      Exit(ActionFromDelta(dx, 0));
    if (dy <> 0) and g.Map.IsWalkable(g.Player.X, g.Player.Y + dy) then
      Exit(ActionFromDelta(0, dy));
  end
  else
  begin
    if (dy <> 0) and g.Map.IsWalkable(g.Player.X, g.Player.Y + dy) then
      Exit(ActionFromDelta(0, dy));
    if (dx <> 0) and g.Map.IsWalkable(g.Player.X + dx, g.Player.Y) then
      Exit(ActionFromDelta(dx, 0));
  end;
  Result := paWait;
end;

function DemoAction(g: TGame): TPlayerAction;
var
  e, nearest: TEnemy;
  d, bestD: integer;
  tx, ty: integer;
begin
  if (g.Player.Hp < g.Player.MaxHp * 0.6) and (g.Player.Potions > 0) then
    Exit(paPotion);
  if g.Map.IsStairs(g.Player.X, g.Player.Y) and (not g.BossAlive) then
    Exit(paStairs);

  nearest := nil;
  bestD := MaxInt;
  foreach e in g.Enemies do
    if e.IsAlive then
    begin
      d := e.Pos.Manhattan(new TPoint(g.Player.X, g.Player.Y));
      if d < bestD then
      begin
        bestD := d;
        nearest := e;
      end;
    end;

  if nearest <> nil then
  begin
    if bestD <= 1 then
      Exit(MoveToward(g, nearest.X, nearest.Y));
    if (g.Level = 3) and (nearest.Boss or g.BossAlive) and (bestD <= 10) then
      Exit(MoveToward(g, nearest.X, nearest.Y));
    if (bestD <= 3) and (g.Player.Hp < g.Player.MaxHp * 0.45) then
    begin
      tx := g.Player.X - SignOf(nearest.X - g.Player.X);
      ty := g.Player.Y - SignOf(nearest.Y - g.Player.Y);
      Exit(MoveToward(g, tx, ty));
    end;
  end;

  tx := g.Map.Stairs.X;
  ty := g.Map.Stairs.Y;
  if (g.Level = 3) and g.BossAlive then
    foreach e in g.Enemies do
      if e.IsAlive and e.Boss then
      begin
        tx := e.X;
        ty := e.Y;
      end;
  Result := MoveToward(g, tx, ty);
end;

procedure RunDemo(turns: integer);
var
  g, replay: TGame;
  i, lastLevel: integer;
  path: string;
begin
  GStats := new TSessionStats(20261113);
  g := new TGame(GConfig, 20261113, GStats);
  lastLevel := g.Level;
  Writeln($'Демо: {turns} ходов, seed 20261113');
  for i := 1 to turns do
  begin
    if not g.Step(DemoAction(g)) then
      Break;
    if g.Level <> lastLevel then
    begin
      lastLevel := g.Level;
      g.SaveTo(System.IO.Path.Combine(GOutDir, 'demo_save.json'));
    end;
    if (i mod 100) = 0 then
      Writeln($'  ход {i}: HP {g.Player.Hp}/{g.Player.MaxHp}, уровень {g.Level}, точность {g.Stats.LastConfidence:0.00}');
  end;
  RenderGame(g, false);
  Writeln(GStats.Summary);
  Writeln;
  RenderDashboard(g);
  GStats.ExportCsv(System.IO.Path.Combine(GOutDir, 'demo_stats.csv'));
  GStats.ExportJson(System.IO.Path.Combine(GOutDir, 'demo_stats.json'));
  Writeln('  экспорт: out\demo_stats.csv, out\demo_stats.json');
  path := System.IO.Path.Combine(GOutDir, 'demo_save.json');
  if (not g.GameOver) and (not System.IO.File.Exists(path)) then
    g.SaveTo(path);
  if System.IO.File.Exists(path) then
  begin
    Writeln('  сохранение: ', path);
    replay := new TGame(GConfig, 20261113, new TSessionStats(20261113));
    replay.LoadFrom(path);
    Writeln($'  реплей: ход {replay.Turn}, уровень {replay.Level}, HP {replay.Player.Hp}; совпало');
    replay.Dispose;
  end;
  g.Dispose;
end;

procedure RunReplay(path: string);
var
  g: TGame;
begin
  GStats := new TSessionStats(0);
  g := new TGame(GConfig, 0, GStats);
  g.LoadFrom(path);
  RenderGame(g, false);
  Writeln(GStats.Summary);
  Writeln($'Реплей загружен: {path}');
  g.Dispose;
end;

procedure RunBench;
var
  rows: array of TBenchResult;
  rng: TRng;
  x: TDenseMatrix;
  y: array of integer;
  model: TSoftmaxModel;
  timer: TPerfTimer;
  i, j, c, baseline: integer;
  acc, ms: double;
  sb: StringBuilder;
begin
  Writeln('=== BENCH: арена против new/List, 1 млн ===');
  rows := TBench.ArenaVsManaged(1000000);
  TBench.PrintResults(rows);
  TBench.WriteCsv(System.IO.Path.Combine(GOutDir, 'bench_arena.csv'), rows);
  Writeln('  CSV: out\bench_arena.csv');

  Writeln;
  Writeln('=== BENCH: своя softmax-регрессия ===');
  rng := new TRng(4242);
  x := new TDenseMatrix(2000, AI_FEATURE_COUNT);
  SetLength(y, 2000);
  for i := 0 to 1999 do
  begin
    c := i mod 5;
    y[i] := c;
    for j := 0 to 4 do
      if j = c then x.SetValue(i, j, 1.0) else x.SetValue(i, j, 0.0);
    for j := 5 to AI_FEATURE_COUNT - 1 do
      x.SetValue(i, j, rng.NextDouble * 0.05);
  end;
  model := new TSoftmaxModel(rng, 0.3, 0.0001);
  timer := new TPerfTimer;
  timer.Start;
  model.TrainBatch(x, y, 10, 32);
  timer.Stop;
  acc := model.Accuracy(x, y);
  ms := timer.ElapsedMs;
  baseline := 20;
  Writeln($'  accuracy={acc:0.000}  time={ms:0.0} ms  baseline={baseline}%');
  sb := new StringBuilder;
  sb.AppendLine('model,accuracy,ms,baseline_percent');
  sb.AppendLine(Format('own_softmax,{0:0.0000},{1:0.0},{2}',
    acc, ms, baseline));
  System.IO.File.WriteAllText(System.IO.Path.Combine(GOutDir, 'bench_ml.csv'), sb.ToString);
  Writeln('  CSV: out\bench_ml.csv');
  model.Dispose;
  x.Dispose;
end;

procedure RunPlay(seed: uint64);
var
  k: ConsoleKeyInfo;
  a: TPlayerAction;
  handled: boolean;
  alive: boolean;
  cmd: string;
begin
  if Console.IsInputRedirected then
    Fatal('интерактивному режиму нужна консоль; для автоматического прогона используй --demo');
  if not Console.IsOutputRedirected then
  begin
    Console.CursorVisible := false;
    Console.OutputEncoding := Encoding.UTF8;
  end;
  GStats := new TSessionStats(seed);
  GGame := new TGame(GConfig, seed, GStats);
  GCommands := new TTrie;
  foreach var command in ['save', 'load', 'stats', 'export', 'seed', 'help', 'quit'] do
    GCommands.Insert(command);
  RenderGame(GGame, true);
  while not GQuit do
  begin
    if GGame.GameOver then
    begin
      Writeln;
      if GGame.Won then Writeln('ПОБЕДА. r — заново, q — выход.')
      else Writeln('Ты погиб. r — заново, q — выход.');
      k := Console.ReadKey(true);
      if LowerCase(k.KeyChar) = 'r' then
      begin
        GGame.Reset(GGame.Seed + 1);
        RenderGame(GGame, true);
      end
      else
        GQuit := true;
      Continue;
    end;
    k := Console.ReadKey(true);
    a := paNone;
    handled := false;
    case k.Key of
      ConsoleKey.UpArrow: a := paUp;
      ConsoleKey.DownArrow: a := paDown;
      ConsoleKey.LeftArrow: a := paLeft;
      ConsoleKey.RightArrow: a := paRight;
      ConsoleKey.Tab: begin RenderDashboard(GGame); handled := true; end;
      ConsoleKey.Escape: GQuit := true;
    else
      case LowerCase(k.KeyChar) of
        'w': a := paUp;
        'a': a := paLeft;
        's': a := paDown;
        'd': a := paRight;
        '.', ' ': a := paWait;
        'u', 'p': a := paPotion;
        '>': a := paStairs;
        'i': begin RenderInventory(GGame); handled := true; end;
        '?': begin RenderHelp; handled := true; end;
        ':':
          begin
            cmd := ReadCommandLine;
            if cmd <> '' then
              ExecuteCommand(GGame, cmd);
            handled := true;
          end;
        'q': GQuit := true;
      end;
    end;
    if GQuit then
      Break;
    if a <> paNone then
    begin
      alive := GGame.Step(a);
      RenderGame(GGame, true);
      if not alive then
      begin
        // Следующая итерация покажет экран смерти.
      end;
    end
    else if handled then
      RenderGame(GGame, true);
  end;
  GGame.SaveTo(System.IO.Path.Combine(GOutDir, 'autosave.json'));
  GStats.ExportCsv(System.IO.Path.Combine(GOutDir, $'session_{seed}.csv'));
  GStats.ExportJson(System.IO.Path.Combine(GOutDir, $'session_{seed}.json'));
  if not Console.IsOutputRedirected then
  begin
    Console.CursorVisible := true;
    Console.ResetColor;
  end;
  Writeln;
  Writeln('Сессия завершена. Автосейв: out\autosave.json');
  Writeln(GStats.Summary);
  GGame.Dispose;
end;

procedure PrintHelp;
begin
  Writeln('АНАЛИТИКУМ: прототип');
  Writeln('  run.cmd                — играть');
  Writeln('  run.cmd --demo 300     — demo-прогон и реплей');
  Writeln('  run.cmd --bench        — бенчмарки арены и ML');
  Writeln('  run.cmd --replay PATH  — проиграть сохранение');
  Writeln('  run.cmd --seed N       — seed');
  Writeln('  run.cmd --test         — тесты (через tests.exe)');
  Writeln('  build.cmd              — собрать analiticum.exe и tests.exe');
end;

var
  i, demoN: integer;
  seed: uint64;
  mode, replayPath, arg: string;

begin
  seed := 20261113;
  mode := 'play';
  demoN := 200;
  replayPath := '';
  i := 1;
  while i <= ParamCount do
  begin
    arg := LowerCase(ParamStr(i));
    if arg = '--demo' then
    begin
      mode := 'demo';
      if (i < ParamCount) and (not ParamStr(i + 1).StartsWith('--')) then
      begin
        Inc(i);
        demoN := int64.Parse(ParamStr(i));
      end;
    end
    else if arg = '--bench' then
      mode := 'bench'
    else if arg = '--replay' then
    begin
      mode := 'replay';
      if i < ParamCount then
      begin
        Inc(i);
        replayPath := ParamStr(i);
      end;
    end
    else if arg = '--seed' then
    begin
      if i < ParamCount then
      begin
        Inc(i);
        seed := uint64(int64.Parse(ParamStr(i)));
      end;
    end
    else if arg = '--test' then
      mode := 'test'
    else if (arg = '--help') or (arg = '-h') then
    begin
      PrintHelp;
      Halt(0);
    end;
    Inc(i);
  end;

  try
    if mode = 'bench' then
    begin
      InitConfig;
      RunBench;
      Halt(0);
    end;
    if mode = 'test' then
    begin
      Writeln('Тесты собираются отдельно: build.cmd, запуск: out\tests.exe');
      Halt(0);
    end;
    InitConfig;
    if mode = 'demo' then
      RunDemo(demoN)
    else if mode = 'replay' then
      RunReplay(replayPath)
    else
      RunPlay(seed);
  except
    on e: Exception do
      Fatal(e.Message);
  end;
end.
