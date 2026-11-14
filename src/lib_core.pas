unit lib_core;

// M1: базовые типы, Result<T,E>, Option<T>, детерминированный RNG,
// перегрузка операторов и методы расширения. Только стандартная библиотека.

interface

uses System, System.Collections.Generic, System.Linq, System.Text;

type
  TPoint = record
    X, Y: integer;
    constructor(xx, yy: integer);
    class function operator+(a, b: TPoint): TPoint;
    class function operator-(a, b: TPoint): TPoint;
    function SameAs(other: TPoint): boolean;
    function Manhattan(other: TPoint): integer;
    function Length: double;
    function ToString: string; override;
  end;

  TDirection = (dNorth, dSouth, dWest, dEast, dNone);

  // Result<T,E>: либо значение, либо ошибка. Ветвление — через MatchWith,
  // преобразование — через Map/Bind. Статические generic-фабрики в 4.1
  // не парсятся в выражении, поэтому создание идёт через конструктор.
  TResult<T, E> = class
  private
    fOk: boolean;
    fValue: T;
    fError: E;
  public
    constructor(ok: boolean; value: T; err: E);
    property IsOk: boolean read fOk;
    property Value: T read fValue;
    property Error: E read fError;
    function Map<U>(f: T -> U): TResult<U, E>;
    function Bind<U>(f: T -> TResult<U, E>): TResult<U, E>;
    function MatchWith<U>(onOk: T -> U; onErr: E -> U): U;
  end;

  TOption<T> = class
  private
    fHas: boolean;
    fValue: T;
  public
    constructor(has: boolean; value: T);
    property HasValue: boolean read fHas;
    property Value: T read fValue;
    function Map<U>(f: T -> U): TOption<U>;
    function Bind<U>(f: T -> TOption<U>): TOption<U>;
    function MatchWith<U>(onSome: T -> U; onNone: () -> U): U;
  end;

  TRng = class
  private
    fState: uint64;
    class function Mix(z: uint64): uint64;
  public
    constructor(seed: uint64);
    function NextU64: uint64;
    function NextInt(n: integer): integer;
    function NextRange(a, b: integer): integer;
    function NextDouble: double;
    function Chance(p: double): boolean;
    procedure Shuffle<T>(items: array of T);
    property State: uint64 read fState write fState;
  end;

// Обычные функции: extension-методы в interface юнита PascalABC.NET
// запрещает, поэтому расширения объявляются в главном модуле и в
// implementation тех юнитов, где реально нужны.
function Clamp(value, lo, hi: integer): integer;
function Clamp(value, lo, hi: double): double;
function SignOf(value: integer): integer;
function RepeatText(s: string; n: integer): string;
function DirDelta(d: TDirection): TPoint;
function DirName(d: TDirection): string;
function DirFromDelta(dx, dy: integer): TDirection;

implementation

constructor TPoint.Create(xx, yy: integer);
begin
  X := xx;
  Y := yy;
end;

class function TPoint.operator+(a, b: TPoint): TPoint;
begin
  Result := new TPoint(a.X + b.X, a.Y + b.Y);
end;

class function TPoint.operator-(a, b: TPoint): TPoint;
begin
  Result := new TPoint(a.X - b.X, a.Y - b.Y);
end;

function TPoint.SameAs(other: TPoint): boolean;
begin
  Result := (X = other.X) and (Y = other.Y);
end;

function TPoint.Manhattan(other: TPoint): integer;
begin
  Result := Abs(X - other.X) + Abs(Y - other.Y);
end;

function TPoint.Length: double;
begin
  Result := Sqrt(X * X + Y * Y);
end;

function TPoint.ToString: string;
begin
  Result := $'({X},{Y})';
end;

constructor TResult<T, E>.Create(ok: boolean; value: T; err: E);
begin
  fOk := ok;
  fValue := value;
  fError := err;
end;

function TResult<T, E>.Map<U>(f: T -> U): TResult<U, E>;
begin
  if fOk then
    Result := new TResult<U, E>(true, f(fValue), default(E))
  else
    Result := new TResult<U, E>(false, default(U), fError);
end;

function TResult<T, E>.Bind<U>(f: T -> TResult<U, E>): TResult<U, E>;
begin
  if fOk then
    Result := f(fValue)
  else
    Result := new TResult<U, E>(false, default(U), fError);
end;

function TResult<T, E>.MatchWith<U>(onOk: T -> U; onErr: E -> U): U;
begin
  if fOk then
    Result := onOk(fValue)
  else
    Result := onErr(fError);
end;

constructor TOption<T>.Create(has: boolean; value: T);
begin
  fHas := has;
  fValue := value;
end;

function TOption<T>.Map<U>(f: T -> U): TOption<U>;
begin
  if fHas then
    Result := new TOption<U>(true, f(fValue))
  else
    Result := new TOption<U>(false, default(U));
end;

function TOption<T>.Bind<U>(f: T -> TOption<U>): TOption<U>;
begin
  if fHas then
    Result := f(fValue)
  else
    Result := new TOption<U>(false, default(U));
end;

function TOption<T>.MatchWith<U>(onSome: T -> U; onNone: () -> U): U;
begin
  if fHas then
    Result := onSome(fValue)
  else
    Result := onNone();
end;

constructor TRng.Create(seed: uint64);
begin
  // Ноль — плохое состояние для splitmix64, разворачиваем его.
  fState := seed xor uint64($9E3779B97F4A7C15);
  if fState = 0 then
    fState := uint64($9E3779B97F4A7C15);
end;

class function TRng.Mix(z: uint64): uint64;
begin
  z := (z xor (z shr 30)) * uint64($BF58476D1CE4E5B9);
  z := (z xor (z shr 27)) * uint64($94D049BB133111EB);
  Result := z xor (z shr 31);
end;

function TRng.NextU64: uint64;
begin
  fState := fState + uint64($9E3779B97F4A7C15);
  Result := Mix(fState);
end;

function TRng.NextInt(n: integer): integer;
begin
  if n <= 1 then
    Exit(0);
  Result := integer(NextU64 mod uint64(n));
end;

function TRng.NextRange(a, b: integer): integer;
begin
  if b < a then
    Exit(a);
  Result := a + NextInt(b - a + 1);
end;

function TRng.NextDouble: double;
begin
  // 53 значащих бита — ровно мантисса double.
  Result := (NextU64 shr 11) * (1.0 / 9007199254740992.0);
end;

function TRng.Chance(p: double): boolean;
begin
  Result := NextDouble < p;
end;

procedure TRng.Shuffle<T>(items: array of T);
var
  i, j: integer;
  tmp: T;
begin
  for i := items.Length - 1 downto 1 do
  begin
    j := NextInt(i + 1);
    tmp := items[i];
    items[i] := items[j];
    items[j] := tmp;
  end;
end;

function Clamp(value, lo, hi: integer): integer;
begin
  if value < lo then
    Result := lo
  else if value > hi then
    Result := hi
  else
    Result := value;
end;

function Clamp(value, lo, hi: double): double;
begin
  if value < lo then
    Result := lo
  else if value > hi then
    Result := hi
  else
    Result := value;
end;

function SignOf(value: integer): integer;
begin
  if value < 0 then
    Result := -1
  else if value > 0 then
    Result := 1
  else
    Result := 0;
end;

function RepeatText(s: string; n: integer): string;
var
  i: integer;
  sb: StringBuilder;
begin
  sb := new StringBuilder;
  for i := 1 to Max(0, n) do
    sb.Append(s);
  Result := sb.ToString;
end;

function DirDelta(d: TDirection): TPoint;
begin
  case d of
    dNorth: Result := new TPoint(0, -1);
    dSouth: Result := new TPoint(0, 1);
    dWest: Result := new TPoint(-1, 0);
    dEast: Result := new TPoint(1, 0);
  else
    Result := new TPoint(0, 0);
  end;
end;

function DirName(d: TDirection): string;
begin
  case d of
    dNorth: Result := 'север';
    dSouth: Result := 'юг';
    dWest: Result := 'запад';
    dEast: Result := 'восток';
  else
    Result := 'ожидание';
  end;
end;

function DirFromDelta(dx, dy: integer): TDirection;
begin
  if (dx = 0) and (dy < 0) then
    Result := dNorth
  else if (dx = 0) and (dy > 0) then
    Result := dSouth
  else if (dx < 0) and (dy = 0) then
    Result := dWest
  else if (dx > 0) and (dy = 0) then
    Result := dEast
  else
    Result := dNone;
end;

end.

