unit lib_game;

// M4b: игра. Карта 40x25, BSP-подземелья, FOV, инвентарь, бой.
// Враги используют TAiEngine: предсказание следующего хода игрока меняет
// агрессивность и патрули. Сохранение — seed + журнал действий, загрузка —
// детерминированный реплей.

interface

uses System, System.Collections.Generic, System.Linq, System.IO, lib_core,
  lib_lowlevel, lib_script, lib_ai, lib_analytics;

const
  MAP_W = 40;
  MAP_H = 25;

type
  TTile = (tWall, tFloor, tStairs);

  TPlayerAction = (paUp, paDown, paLeft, paRight, paWait, paPotion, paStairs, paNone);

  TRoom = record
    X, Y, W, H: integer;
    function Center: TPoint;
  end;

  TMap = class
  private
    fRng: TRng;
    fTiles: array of TTile;
    fVisible, fExplored: array of boolean;
    function GetTile(x, y: integer): TTile;
    procedure SetTile(x, y: integer; value: TTile);
    function GetVisible(x, y: integer): boolean;
    function GetExplored(x, y: integer): boolean;
    procedure FillMap(t: TTile);
    procedure CarveRoom(r: TRoom);
    procedure CarveCorridor(a, b: TPoint);
    procedure SplitRoom(x, y, w, h, depth: integer);
  public
    Rooms: List<TRoom>;
    Stairs: TPoint;
    property Tiles[x, y: integer]: TTile read GetTile write SetTile;
    property Visible[x, y: integer]: boolean read GetVisible;
    property Explored[x, y: integer]: boolean read GetExplored;
    constructor Create;
    procedure Generate(seed: uint64; level: integer);
    function InBounds(x, y: integer): boolean;
    function IsWall(x, y: integer): boolean;
    function IsWalkable(x, y: integer): boolean;
    function IsStairs(x, y: integer): boolean;
    function LineOfSight(x0, y0, x1, y1: integer): boolean;
    procedure ComputeFov(px, py, radius: integer);
  end;

  TPlayer = class
  public
    X, Y, Hp, MaxHp, Attack, Defense, Gold, Potions, Level, Xp: integer;
    Inventory: Dictionary<string, integer>;
    constructor Create;
    function IsAlive: boolean;
    procedure Heal(n: integer);
    procedure AddItem(spec: TItemSpec);
  end;

  TEnemy = class
  public
    X, Y, Hp, MaxHp, Damage, Defense, Xp, AggroRange: integer;
    Ai, Name, SpecKey: string;
    Glyph: char;
    Boss: boolean;
    FleeAt: double;
    Alert: integer;
    PatrolX, PatrolY: integer;
    LastSeenX, LastSeenY: integer;
    Spec: TMonsterSpec;
    constructor Create(spec: TMonsterSpec; x, y: integer);
    function IsAlive: boolean;
    function Pos: TPoint;
  end;

  TItemEntity = class
  public
    X, Y: integer;
    Key: string;
    constructor Create(key: string; x, y: integer);
  end;

  TStyleWindow = record
    Aggression, Exploration, Caution: double;
  end;

  TGame = class
  private
    FRng: TRng;
    FLastActions: array[0..AI_HISTORY - 1] of integer;
    FLastIdx: integer;
    FLastAction: integer;
    FWindowTurns, FAttackCount, FMoveCount, FWaitCount, FPotionCount: integer;
    FStyleWindows: List<TStyleWindow>;
    procedure StartLevel(level: integer);
    procedure SpawnLevel;
    procedure PlacePlayer;
    procedure SpawnEnemy(key: string; x, y: integer);
    procedure PlaceItem(key: string; x, y: integer);
    procedure TickStyle;
    function ChooseBossKey: string;
    function BuildView(e: TEnemy): TAgentView;
    function EnemyAt(x, y: integer; exceptEnemy: TEnemy): boolean;
    function PlayerAt(x, y: integer): boolean;
    procedure MoveEnemyToward(e: TEnemy; tx, ty: integer);
    procedure EnemiesAct;
    procedure AttackPlayer(e: TEnemy);
    procedure AttackEnemy(e: TEnemy);
    procedure PickupAt(x, y: integer);
    procedure UsePotion;
    procedure Descend;
    procedure AddMessage(s: string);
    procedure UpdateModelStats;
    function PredictedToward(pred: TPrediction; e: TEnemy): boolean;
    function PredictedAway(pred: TPrediction; e: TEnemy): boolean;
  public
    Config: TConfigSet;
    Stats: TSessionStats;
    Ai: TAiEngine;
    Map: TMap;
    Player: TPlayer;
    Enemies: List<TEnemy>;
    Items: List<TItemEntity>;
    Messages: List<string>;
    ActionLog: List<integer>;
    Seed: uint64;
    Level, Turn: integer;
    GameOver, Won: boolean;
    LastPrediction: TPrediction;
    BossKey: string;
    constructor Create(config: TConfigSet; seed: uint64; stats: TSessionStats);
    procedure Dispose;
    procedure Reset(seed: uint64);
    function Step(action: TPlayerAction): boolean;
    function BuildViewForNearest: TAgentView;
    procedure SaveTo(path: string);
    procedure LoadFrom(path: string);
    function BossAlive: boolean;
  end;

implementation

function TRoom.Center: TPoint;
begin
  Result := new TPoint(X + W div 2, Y + H div 2);
end;

// -------------------------------------------------------------------- TMap

constructor TMap.Create;
begin
  SetLength(fTiles, MAP_W * MAP_H);
  SetLength(fVisible, MAP_W * MAP_H);
  SetLength(fExplored, MAP_W * MAP_H);
  Rooms := new List<TRoom>;
  Stairs := new TPoint(MAP_W div 2, MAP_H div 2);
end;

function TMap.GetTile(x, y: integer): TTile;
begin
  Result := fTiles[y * MAP_W + x];
end;

procedure TMap.SetTile(x, y: integer; value: TTile);
begin
  fTiles[y * MAP_W + x] := value;
end;

function TMap.GetVisible(x, y: integer): boolean;
begin
  Result := fVisible[y * MAP_W + x];
end;

function TMap.GetExplored(x, y: integer): boolean;
begin
  Result := fExplored[y * MAP_W + x];
end;

procedure TMap.FillMap(t: TTile);
var
  x, y: integer;
begin
  for x := 0 to MAP_W - 1 do
    for y := 0 to MAP_H - 1 do
      Tiles[x, y] := t;
end;

procedure TMap.CarveRoom(r: TRoom);
var
  x, y: integer;
begin
  for x := Max(1, r.X) to Min(MAP_W - 2, r.X + r.W - 1) do
    for y := Max(1, r.Y) to Min(MAP_H - 2, r.Y + r.H - 1) do
      Tiles[x, y] := tFloor;
end;

procedure TMap.CarveCorridor(a, b: TPoint);
var
  x, y: integer;
begin
  if fRng.Chance(0.5) then
  begin
    for x := Min(a.X, b.X) to Max(a.X, b.X) do
      Tiles[x, a.Y] := tFloor;
    for y := Min(a.Y, b.Y) to Max(a.Y, b.Y) do
      Tiles[b.X, y] := tFloor;
  end
  else
  begin
    for y := Min(a.Y, b.Y) to Max(a.Y, b.Y) do
      Tiles[a.X, y] := tFloor;
    for x := Min(a.X, b.X) to Max(a.X, b.X) do
      Tiles[x, b.Y] := tFloor;
  end;
end;

procedure TMap.SplitRoom(x, y, w, h, depth: integer);
var
  r: TRoom;
  split, mx, my: integer;
begin
  if (depth >= 4) or (w < 10) or (h < 8) then
  begin
    if (w >= 4) and (h >= 3) then
    begin
      r.X := x + 1;
      r.Y := y + 1;
      r.W := Max(3, w - 2);
      r.H := Max(3, h - 2);
      Rooms.Add(r);
      CarveRoom(r);
    end;
    Exit;
  end;
  if w > h then
  begin
    split := w div 2 + fRng.NextRange(-1, 1);
    mx := x + Max(6, Min(w - 6, split));
    SplitRoom(x, y, mx - x, h, depth + 1);
    SplitRoom(mx, y, x + w - mx, h, depth + 1);
  end
  else
  begin
    split := h div 2 + fRng.NextRange(-1, 1);
    my := y + Max(5, Min(h - 5, split));
    SplitRoom(x, y, w, my - y, depth + 1);
    SplitRoom(x, my, w, y + h - my, depth + 1);
  end;
end;

procedure TMap.Generate(seed: uint64; level: integer);
var
  i: integer;
begin
  fRng := new TRng(seed + uint64(level) * 7919);
  FillMap(tWall);
  Rooms.Clear;
  SplitRoom(1, 1, MAP_W - 2, MAP_H - 2, 0);
  if Rooms.Count = 0 then
  begin
    var rr: TRoom;
    rr.X := 2;
    rr.Y := 2;
    rr.W := 8;
    rr.H := 6;
    Rooms.Add(rr);
    CarveRoom(rr);
  end;
  for i := 1 to Rooms.Count - 1 do
    CarveCorridor(Rooms[i - 1].Center, Rooms[i].Center);
  Stairs := Rooms[Rooms.Count - 1].Center;
  Tiles[Stairs.X, Stairs.Y] := tStairs;
end;

function TMap.InBounds(x, y: integer): boolean;
begin
  Result := (x >= 0) and (y >= 0) and (x < MAP_W) and (y < MAP_H);
end;

function TMap.IsWall(x, y: integer): boolean;
begin
  Result := (not InBounds(x, y)) or (Tiles[x, y] = tWall);
end;

function TMap.IsWalkable(x, y: integer): boolean;
begin
  Result := InBounds(x, y) and (Tiles[x, y] <> tWall);
end;

function TMap.IsStairs(x, y: integer): boolean;
begin
  Result := InBounds(x, y) and (Tiles[x, y] = tStairs);
end;

function TMap.LineOfSight(x0, y0, x1, y1: integer): boolean;
var
  dx, dy, steps, i, x, y: integer;
begin
  dx := x1 - x0;
  dy := y1 - y0;
  steps := Max(Abs(dx), Abs(dy));
  if steps = 0 then
    Exit(true);
  for i := 1 to steps - 1 do
  begin
    x := x0 + Round(dx * i / steps);
    y := y0 + Round(dy * i / steps);
    if IsWall(x, y) then
      Exit(false);
  end;
  Result := true;
end;

procedure TMap.ComputeFov(px, py, radius: integer);
var
  x, y, ang, step, maxStep, cx, cy: integer;
  rad, dx, dy: double;
begin
  for x := 0 to MAP_W - 1 do
    for y := 0 to MAP_H - 1 do
      fVisible[y * MAP_W + x] := false;
  fVisible[py * MAP_W + px] := true;
  fExplored[py * MAP_W + px] := true;
  maxStep := radius * 4;
  for ang := 0 to 359 do
  begin
    rad := ang * Pi / 180.0;
    dx := Cos(rad);
    dy := Sin(rad);
    for step := 1 to maxStep do
    begin
      cx := px + Round(dx * step / 4.0);
      cy := py + Round(dy * step / 4.0);
      if not InBounds(cx, cy) then
        Break;
      fVisible[cy * MAP_W + cx] := true;
      fExplored[cy * MAP_W + cx] := true;
      if Tiles[cx, cy] = tWall then
        Break;
    end;
  end;
end;

// ------------------------------------------------------------------ TPlayer

constructor TPlayer.Create;
begin
  Hp := 40;
  MaxHp := 40;
  Attack := 7;
  Defense := 1;
  Gold := 0;
  Potions := 3;
  Level := 1;
  Xp := 0;
  Inventory := new Dictionary<string, integer>;
end;

function TPlayer.IsAlive: boolean;
begin
  Result := Hp > 0;
end;

procedure TPlayer.Heal(n: integer);
begin
  Hp := Min(MaxHp, Hp + n);
end;

procedure TPlayer.AddItem(spec: TItemSpec);
begin
  if Inventory.ContainsKey(spec.Key) then
    Inventory[spec.Key] := Inventory[spec.Key] + 1
  else
    Inventory[spec.Key] := 1;
  if spec.Kind = 'heal' then
    Inc(Potions)
  else if spec.Kind = 'gold' then
    Gold += spec.Value
  else if spec.Kind = 'weapon' then
    Attack += spec.Power
  else if spec.Kind = 'artifact' then
  begin
    Xp += spec.Value;
    Gold += spec.Value;
  end;
end;

// ------------------------------------------------------------------- TEnemy

constructor TEnemy.Create(spec: TMonsterSpec; x, y: integer);
begin
  Self.Spec := spec;
  SpecKey := spec.Key;
  Name := spec.Name;
  Self.X := x;
  Self.Y := y;
  Hp := spec.Hp;
  MaxHp := spec.Hp;
  Damage := spec.Damage;
  Defense := spec.Defense;
  Xp := spec.Xp;
  AggroRange := spec.AggroRange;
  Ai := spec.Ai;
  Glyph := spec.Glyph;
  Boss := spec.Boss;
  FleeAt := spec.FleeAt;
  Alert := 0;
  PatrolX := x;
  PatrolY := y;
  LastSeenX := -1;
  LastSeenY := -1;
end;

function TEnemy.IsAlive: boolean;
begin
  Result := Hp > 0;
end;

function TEnemy.Pos: TPoint;
begin
  Result := new TPoint(X, Y);
end;

constructor TItemEntity.Create(key: string; x, y: integer);
begin
  Self.Key := key;
  Self.X := x;
  Self.Y := y;
end;

// -------------------------------------------------------------------- TGame

constructor TGame.Create(config: TConfigSet; seed: uint64; stats: TSessionStats);
begin
  Self.Config := config;
  Self.Stats := stats;
  Reset(seed);
end;

procedure TGame.Dispose;
begin
  Ai.Dispose;
end;

procedure TGame.Reset(seed: uint64);
var
  i: integer;
begin
  Self.Seed := seed;
  Level := 1;
  Turn := 0;
  GameOver := false;
  Won := false;
  BossKey := '';
  FRng := new TRng(seed xor $C0FFEE);
  Player := new TPlayer;
  Enemies := new List<TEnemy>;
  Items := new List<TItemEntity>;
  Messages := new List<string>;
  ActionLog := new List<integer>;
  FStyleWindows := new List<TStyleWindow>;
  for i := 0 to AI_HISTORY - 1 do
    FLastActions[i] := -1;
  FLastIdx := 0;
  FLastAction := 4;
  FWindowTurns := 0;
  FAttackCount := 0;
  FMoveCount := 0;
  FWaitCount := 0;
  FPotionCount := 0;
  if Ai <> nil then
    Ai.Dispose;
  Ai := new TAiEngine(seed xor $BEEF);
  Stats.Reset(seed);
  SetLength(LastPrediction.Probs, 0);
  LastPrediction.Best := 4;
  LastPrediction.Confidence := 0;
  Map := new TMap;
  StartLevel(1);
end;

procedure TGame.StartLevel(level: integer);
begin
  Self.Level := level;
  Map.Generate(Seed + uint64(Level) * 104729, Level);
  Enemies.Clear;
  Items.Clear;
  PlacePlayer;
  SpawnLevel;
  Map.ComputeFov(Player.X, Player.Y, 8);
  AddMessage($'Уровень {Level}. Спуск вниз ждёт на лестнице.');
end;

procedure TGame.PlacePlayer;
var
  r: TRoom;
begin
  r := Map.Rooms[0];
  Player.X := r.Center.X;
  Player.Y := r.Center.Y;
end;

procedure TGame.SpawnEnemy(key: string; x, y: integer);
var
  spec: TMonsterSpec;
begin
  spec := Config.Monster(key);
  Enemies.Add(new TEnemy(spec, x, y));
end;

procedure TGame.PlaceItem(key: string; x, y: integer);
begin
  Items.Add(new TItemEntity(key, x, y));
end;

procedure TGame.SpawnLevel;
var
  i, count, roomIdx, x, y: integer;
  itemKeys: array of string;
  r: TRoom;
  normalKeys: List<string>;
  key: string;
begin
  normalKeys := new List<string>;
  foreach key in Config.MonsterKeys do
    if not Config.Monster(key).Boss then
      normalKeys.Add(key);
  count := 2 + Level + FRng.NextInt(2);
  for i := 1 to count do
  begin
    roomIdx := FRng.NextInt(Map.Rooms.Count);
    r := Map.Rooms[roomIdx];
    x := r.X + FRng.NextInt(Max(1, r.W - 1));
    y := r.Y + FRng.NextInt(Max(1, r.H - 1));
    if Map.IsWalkable(x, y) and (not PlayerAt(x, y)) and
       (not ((x = Map.Stairs.X) and (y = Map.Stairs.Y))) and
       (not EnemyAt(x, y, nil)) then
      SpawnEnemy(normalKeys[FRng.NextInt(normalKeys.Count)], x, y);
  end;

  if Level = 3 then
  begin
    BossKey := ChooseBossKey;
    r := Map.Rooms[Map.Rooms.Count - 1];
    for i := Enemies.Count - 1 downto 0 do
      if (Enemies[i].X = r.Center.X) and (Enemies[i].Y = r.Center.Y) then
        Enemies.RemoveAt(i);
    SpawnEnemy(BossKey, r.Center.X, r.Center.Y);
    AddMessage($'Здесь босс: {Config.Monster(BossKey).Name}.');
  end;

  itemKeys := Config.ItemKeys;
  for i := 1 to 2 + FRng.NextInt(2) do
  begin
    r := Map.Rooms[FRng.NextInt(Map.Rooms.Count)];
    x := r.X + FRng.NextInt(Max(1, r.W - 1));
    y := r.Y + FRng.NextInt(Max(1, r.H - 1));
    if Map.IsWalkable(x, y) then
      PlaceItem(itemKeys[FRng.NextInt(itemKeys.Length)], x, y);
  end;
  // Один зельёк гарантированно, иначе первый уровень может быть непроходим.
  r := Map.Rooms[FRng.NextInt(Map.Rooms.Count)];
  PlaceItem('potion', r.Center.X, r.Center.Y);
  if Level > 1 then
    Map.Tiles[Map.Stairs.X, Map.Stairs.Y] := tStairs;
end;

procedure TGame.TickStyle;
var
  w: TStyleWindow;
  denom: double;
begin
  Inc(FWindowTurns);
  if FWindowTurns < 10 then
    Exit;
  denom := Max(1, FWindowTurns);
  w.Aggression := FAttackCount / denom;
  w.Exploration := FMoveCount / denom;
  w.Caution := (FWaitCount + FPotionCount * 2) / denom;
  FStyleWindows.Add(w);
  FWindowTurns := 0;
  FAttackCount := 0;
  FMoveCount := 0;
  FWaitCount := 0;
  FPotionCount := 0;
end;

function TGame.ChooseBossKey: string;
var
  pts: TDenseMatrix;
  km: TKMeans;
  i, cluster, bestDim: integer;
  w: TStyleWindow;
  cur: array of double;
  styleLabel: string;
begin
  if FStyleWindows.Count < 3 then
  begin
    i := (Turn div 40 + Level) mod 3;
    case i of
      0: Result := 'boss_butcher';
      1: Result := 'boss_whisper';
    else
      Result := 'boss_architect';
    end;
    Stats.SetStyle('мало данных', -1);
    Exit;
  end;
  pts := new TDenseMatrix(FStyleWindows.Count, 3);
  for i := 0 to FStyleWindows.Count - 1 do
  begin
    w := FStyleWindows[i];
    pts.SetValue(i, 0, w.Aggression);
    pts.SetValue(i, 1, w.Exploration);
    pts.SetValue(i, 2, w.Caution);
  end;
  km := new TKMeans(3, FRng);
  km.Fit(pts);
  w := FStyleWindows[FStyleWindows.Count - 1];
  SetLength(cur, 3);
  cur[0] := w.Aggression;
  cur[1] := w.Exploration;
  cur[2] := w.Caution;
  cluster := km.ClusterOf(cur);
  bestDim := 0;
  for i := 1 to 2 do
    if km.Centroids.Get(cluster, i) > km.Centroids.Get(cluster, bestDim) then
      bestDim := i;
  case bestDim of
    0: begin Result := 'boss_butcher'; styleLabel := 'агрессия'; end;
    1: begin Result := 'boss_architect'; styleLabel := 'исследование'; end;
  else
    begin Result := 'boss_whisper'; styleLabel := 'осторожность'; end;
  end;
  Stats.SetStyle(styleLabel, cluster);
  km.Dispose;
  pts.Dispose;
end;

function TGame.PlayerAt(x, y: integer): boolean;
begin
  Result := (Player.X = x) and (Player.Y = y);
end;

function TGame.EnemyAt(x, y: integer; exceptEnemy: TEnemy): boolean;
var
  e: TEnemy;
begin
  foreach e in Enemies do
    if e.IsAlive and (e <> exceptEnemy) and (e.X = x) and (e.Y = y) then
      Exit(true);
  Result := false;
end;

function TGame.BuildView(e: TEnemy): TAgentView;
var
  i, idx: integer;
  v: TAgentView;
begin
  v := TAgentView.Create(Player.X - e.X, Player.Y - e.Y,
    Abs(Player.X - e.X) + Abs(Player.Y - e.Y),
    Player.Hp / Player.MaxHp, e.Hp / e.MaxHp,
    Map.IsWall(Player.X, Player.Y - 1), Map.IsWall(Player.X, Player.Y + 1),
    Map.IsWall(Player.X - 1, Player.Y), Map.IsWall(Player.X + 1, Player.Y));
  for i := 0 to AI_HISTORY - 1 do
  begin
    idx := (FLastIdx - AI_HISTORY + i + AI_HISTORY) mod AI_HISTORY;
    v.LastActions[i] := FLastActions[idx];
  end;
  Result := v;
end;

function TGame.BuildViewForNearest: TAgentView;
var
  e, best: TEnemy;
  d, bestD: integer;
begin
  best := nil;
  bestD := MaxInt;
  foreach e in Enemies do
    if e.IsAlive then
    begin
      d := e.Pos.Manhattan(new TPoint(Player.X, Player.Y));
      if d < bestD then
      begin
        bestD := d;
        best := e;
      end;
    end;
  if best = nil then
    Exit(TAgentView.Create(0, 0, 99, Player.Hp / Player.MaxHp, 0,
      false, false, false, false));
  Result := BuildView(best);
end;

function TGame.PredictedToward(pred: TPrediction; e: TEnemy): boolean;
var
  a, nx, ny, curD, newD: integer;
begin
  a := pred.Best;
  nx := Player.X;
  ny := Player.Y;
  case a of
    0: Dec(ny);
    1: Inc(ny);
    2: Dec(nx);
    3: Inc(nx);
  end;
  curD := Abs(Player.X - e.X) + Abs(Player.Y - e.Y);
  newD := Abs(nx - e.X) + Abs(ny - e.Y);
  Result := newD < curD;
end;

function TGame.PredictedAway(pred: TPrediction; e: TEnemy): boolean;
var
  a, nx, ny, curD, newD: integer;
begin
  a := pred.Best;
  nx := Player.X;
  ny := Player.Y;
  case a of
    0: Dec(ny);
    1: Inc(ny);
    2: Dec(nx);
    3: Inc(nx);
  end;
  curD := Abs(Player.X - e.X) + Abs(Player.Y - e.Y);
  newD := Abs(nx - e.X) + Abs(ny - e.Y);
  Result := newD > curD;
end;

procedure TGame.MoveEnemyToward(e: TEnemy; tx, ty: integer);
var
  path: TPathResult;
  passable: TGridPredicate;
  px, py, oldX, oldY: integer;
begin
  px := Player.X;
  py := Player.Y;
  oldX := e.X;
  oldY := e.Y;
  passable := (x, y) -> Map.IsWalkable(x, y) and
    ((not EnemyAt(x, y, e)) or ((x = px) and (y = py)));
  path := TAStar.FindPath(MAP_W, MAP_H, e.Pos, new TPoint(tx, ty), passable);
  if path.Found and (path.Path.Length > 1) then
  begin
    e.X := path.Path[1].X;
    e.Y := path.Path[1].Y;
  end
  else
  begin
    // Если пути нет — короткий жадный шаг, но только в проходимую клетку.
    if Abs(tx - e.X) > Abs(ty - e.Y) then
      e.X += SignOf(tx - e.X)
    else
      e.Y += SignOf(ty - e.Y);
    if (not Map.IsWalkable(e.X, e.Y)) or EnemyAt(e.X, e.Y, e) or PlayerAt(e.X, e.Y) then
    begin
      e.X := oldX;
      e.Y := oldY;
    end;
  end;
end;

procedure TGame.AttackPlayer(e: TEnemy);
var
  dmg: integer;
begin
  dmg := Max(1, e.Damage + FRng.NextRange(-1, 1) - Player.Defense div 2);
  Player.Hp -= dmg;
  Stats.RecordDamage(0, dmg);
  AddMessage($'{e.Name} бьёт на {dmg}.');
  if not Player.IsAlive then
  begin
    GameOver := true;
    Stats.RecordDeath;
    AddMessage('Ты пал. Сессия окончена.');
  end;
end;

procedure TGame.AttackEnemy(e: TEnemy);
var
  dmg: integer;
  key: string;
begin
  dmg := Max(1, Player.Attack + FRng.NextRange(-1, 1) - e.Defense div 2);
  e.Hp -= dmg;
  Stats.RecordDamage(dmg, 0);
  AddMessage($'Ты бьёшь {e.Name} на {dmg}.');
  if not e.IsAlive then
  begin
    Stats.RecordKill;
    Player.Xp += e.Xp;
    AddMessage($'{e.Name} повержен.');
    foreach key in e.Spec.Loot do
      PlaceItem(key, e.X, e.Y);
    while Player.Xp >= Player.Level * 20 do
    begin
      Player.Xp -= Player.Level * 20;
      Inc(Player.Level);
      Inc(Player.MaxHp, 5);
      Player.Hp := Player.MaxHp;
      Inc(Player.Attack);
      AddMessage($'Новый уровень {Player.Level}: +5 HP, +1 атака.');
    end;
  end;
  if e.Boss and not e.IsAlive then
    AddMessage('Босс мёртв. Лестница открыта.');
end;

procedure TGame.PickupAt(x, y: integer);
var
  i: integer;
  it: TItemEntity;
  spec: TItemSpec;
begin
  for i := Items.Count - 1 downto 0 do
  begin
    it := Items[i];
    if (it.X = x) and (it.Y = y) then
    begin
      spec := Config.Item(it.Key);
      Player.AddItem(spec);
      Stats.RecordGold(spec.Value);
      AddMessage($'Подобрано: {spec.Name}.');
      Items.RemoveAt(i);
    end;
  end;
end;

procedure TGame.UsePotion;
begin
  Inc(FPotionCount);
  if Player.Potions <= 0 then
  begin
    AddMessage('Зелий нет.');
    Exit;
  end;
  if Player.Hp >= Player.MaxHp then
  begin
    AddMessage('Здоровье полное, зелье не потрачено.');
    Exit;
  end;
  Dec(Player.Potions);
  Player.Heal(10);
  Stats.RecordItem;
  AddMessage('Зелье: +10 HP.');
end;

procedure TGame.Descend;
begin
  if BossAlive then
  begin
    AddMessage('Лестница запечатана, пока жив босс.');
    Exit;
  end;
  if Level >= 5 then
  begin
    Won := true;
    GameOver := true;
    Stats.RecordWin;
    AddMessage('Пятый уровень пройден. Победа.');
    Exit;
  end;
  Stats.RecordLevel;
  StartLevel(Level + 1);
end;

procedure TGame.AddMessage(s: string);
begin
  Messages.Add(s);
  while Messages.Count > 7 do
    Messages.RemoveAt(0);
end;

function TGame.BossAlive: boolean;
var
  e: TEnemy;
begin
  foreach e in Enemies do
    if e.Boss and e.IsAlive then
      Exit(true);
  Result := false;
end;

procedure TGame.EnemiesAct;
var
  e: TEnemy;
  view: TAgentView;
  pred: TPrediction;
  dist: integer;
  sees: boolean;
  target: TPoint;
  away: TPoint;
  hasEnemy: boolean;
begin
  hasEnemy := false;
  foreach e in Enemies do
    if e.IsAlive then
    begin
      hasEnemy := true;
      Break;
    end;
  // Один сэмпл на ход игрока, а не на каждого врага: обучение идёт
  // ровно раз в 20 ходов, как в ТЗ.
  if hasEnemy then
    Ai.Observe(BuildViewForNearest, FLastAction);

  foreach e in Enemies do
  begin
    if not e.IsAlive then
      Continue;
    view := BuildView(e);
    pred := Ai.Predict(view);
    LastPrediction := pred;
    Stats.SetPrediction(ActionName(pred.Best), pred.Confidence);
    dist := e.Pos.Manhattan(new TPoint(Player.X, Player.Y));
    sees := (dist <= e.AggroRange) and Map.LineOfSight(e.X, e.Y, Player.X, Player.Y);
    if sees then
    begin
      e.Alert := 6;
      e.LastSeenX := Player.X;
      e.LastSeenY := Player.Y;
    end
    else if e.Alert > 0 then
      Dec(e.Alert);

    // Предсказание хода игрока: если он идёт навстречу — агрессивнее,
    // если отступает, а враг ранен — отходим и лечимся дистанцией.
    if sees and (e.Ai = 'patrol') and PredictedToward(pred, e) and (pred.Confidence > 0.35) then
      e.Ai := 'aggressive';
    if e.Ai = 'coward' then
    begin
      if (e.Hp / e.MaxHp < e.FleeAt) or (PredictedAway(pred, e) and (e.Hp / e.MaxHp < 0.5)) then
      begin
        away := new TPoint(e.X - SignOf(Player.X - e.X), e.Y - SignOf(Player.Y - e.Y));
        if Map.IsWalkable(away.X, away.Y) and not EnemyAt(away.X, away.Y, e) and not PlayerAt(away.X, away.Y) then
        begin
          e.X := away.X;
          e.Y := away.Y;
        end
        else
          MoveEnemyToward(e, e.PatrolX, e.PatrolY);
        Continue;
      end;
    end;

    if (sees or (e.Alert > 0)) and (dist <= e.AggroRange + 2) then
    begin
      if dist = 1 then
        AttackPlayer(e)
      else
        MoveEnemyToward(e, Player.X, Player.Y);
    end
    else
    begin
      // Патруль: блуждаем вокруг своей точки.
      if (e.X = e.PatrolX) and (e.Y = e.PatrolY) then
      begin
        target := new TPoint(e.PatrolX + FRng.NextRange(-3, 3), e.PatrolY + FRng.NextRange(-2, 2));
        if Map.IsWalkable(target.X, target.Y) and not EnemyAt(target.X, target.Y, e) then
          MoveEnemyToward(e, target.X, target.Y);
      end
      else
        MoveEnemyToward(e, e.PatrolX, e.PatrolY);
    end;
    if GameOver then
      Break;
  end;
end;

procedure TGame.UpdateModelStats;
begin
  Stats.UpdateModel(Ai.AccuracyHistory, Ai.LossHistory, Ai.TrainedBatches);
end;

function TGame.Step(action: TPlayerAction): boolean;
var
  dx, dy, tx, ty: integer;
  e: TEnemy;
  actionLabel: integer;
begin
  if GameOver then
    Exit(false);
  ActionLog.Add(Ord(action));
  Stats.RecordAction(Ord(action));
  actionLabel := Ord(action);
  if actionLabel > 4 then
    actionLabel := 4;
  FLastAction := actionLabel;
  FLastActions[FLastIdx] := actionLabel;
  FLastIdx := (FLastIdx + 1) mod AI_HISTORY;

  dx := 0;
  dy := 0;
  case action of
    paUp: dy := -1;
    paDown: dy := 1;
    paLeft: dx := -1;
    paRight: dx := 1;
  end;

  if action in [paUp, paDown, paLeft, paRight] then
  begin
    tx := Player.X + dx;
    ty := Player.Y + dy;
    if not Map.InBounds(tx, ty) or Map.IsWall(tx, ty) then
      AddMessage('Там стена.')
    else
    begin
      e := nil;
      foreach var en in Enemies do
        if en.IsAlive and (en.X = tx) and (en.Y = ty) then
          e := en;
      if e <> nil then
        AttackEnemy(e)
      else
      begin
        Player.X := tx;
        Player.Y := ty;
        Inc(FMoveCount);
        PickupAt(tx, ty);
      end;
    end;
  end
  else if action = paWait then
  begin
    Inc(FWaitCount);
    AddMessage('Ты ждёшь.');
  end
  else if action = paPotion then
    UsePotion
  else if action = paStairs then
  begin
    if Map.IsStairs(Player.X, Player.Y) then
      Descend
    else
      AddMessage('Здесь нет лестницы.');
  end;

  if GameOver then
  begin
    UpdateModelStats;
    Exit(false);
  end;

  Inc(Turn);
  Stats.RecordTurn;
  TickStyle;
  EnemiesAct;
  Map.ComputeFov(Player.X, Player.Y, 8);
  UpdateModelStats;
  Result := Player.IsAlive and not GameOver;
end;

procedure TGame.SaveTo(path: string);
var
  root, acts: TJsonValue;
  i, a: integer;
begin
  root := JObject;
  root.Put('version', JInt(1));
  root.Put('seed', JInt(int64(Seed)));
  root.Put('level', JInt(Level));
  root.Put('turn', JInt(Turn));
  root.Put('hp', JInt(Player.Hp));
  root.Put('maxhp', JInt(Player.MaxHp));
  root.Put('attack', JInt(Player.Attack));
  root.Put('gold', JInt(Player.Gold));
  root.Put('potions', JInt(Player.Potions));
  root.Put('boss', JStr(BossKey));
  acts := JArray;
  for i := 0 to ActionLog.Count - 1 do
  begin
    a := ActionLog[i];
    acts.Add(JInt(a));
  end;
  root.Put('actions', acts);
  System.IO.File.WriteAllText(path, root.ToJson);
end;

procedure TGame.LoadFrom(path: string);
var
  root, acts: TJsonValue;
  i, a, savedTurn, savedLevel: integer;
  savedSeed: uint64;
begin
  root := JsonParse(System.IO.File.ReadAllText(path));
  if root.Item('version') = nil then
    raise new Exception('Нет поля version');
  savedSeed := uint64(root.Item('seed').AsInt);
  savedLevel := root.Item('level').AsInt;
  savedTurn := root.Item('turn').AsInt;
  Reset(savedSeed);
  acts := root.Item('actions');
  for i := 0 to acts.Count - 1 do
  begin
    a := acts.Arr[i].AsInt;
    Step(TPlayerAction(a));
    if GameOver then
      Break;
  end;
  if (Turn <> savedTurn) or (Level <> savedLevel) then
    raise new Exception($'Реплей разошёлся: turn {Turn} <> {savedTurn}, level {Level} <> {savedLevel}');
end;

end.
