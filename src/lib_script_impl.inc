// Реализация TValue/TEvaluator/TConfigSet/JSON. Подключается из
// lib_script.pas через {$include}: implementation разбит на части.

// ---------------------------------------------------------------- helpers

function VInt(v: int64): TValue;
begin
  Result := new TValue;
  Result.Kind := vkInt;
  Result.IntVal := v;
end;

function VFloat(v: double): TValue;
begin
  Result := new TValue;
  Result.Kind := vkFloat;
  Result.FloatVal := v;
end;

function VStr(v: string): TValue;
begin
  Result := new TValue;
  Result.Kind := vkString;
  Result.StrVal := v;
end;

function VBool(v: boolean): TValue;
begin
  Result := new TValue;
  Result.Kind := vkBool;
  Result.BoolVal := v;
end;

function VNull: TValue;
begin
  Result := new TValue;
  Result.Kind := vkNull;
end;

function VList: TValue;
begin
  Result := new TValue;
  Result.Kind := vkList;
  Result.ListVal := new List<TValue>;
end;

function VObject: TValue;
begin
  Result := new TValue;
  Result.Kind := vkObject;
  Result.ObjVal := new TObjectValue;
end;

function VFunc(paramNames: List<string>; body: TExpr; env: TEnv;
  applied: List<TValue>): TValue;
begin
  Result := new TValue;
  Result.Kind := vkFunc;
  Result.ParamNames := paramNames;
  Result.Body := body;
  Result.Closure := env;
  Result.Applied := applied;
end;

function VBuiltin(name: string): TValue;
begin
  Result := new TValue;
  Result.Kind := vkBuiltin;
  Result.BuiltinName := name;
end;

function IsNumeric(v: TValue): boolean;
begin
  Result := (v.Kind = vkInt) or (v.Kind = vkFloat);
end;

function NumValue(v: TValue): double;
begin
  case v.Kind of
    vkInt: Result := v.IntVal;
    vkFloat: Result := v.FloatVal;
  else
    raise new EScriptError('Ожидалось число', 0, 0);
  end;
end;

function ValuesEqual(a, b: TValue): boolean;
begin
  if IsNumeric(a) and IsNumeric(b) then
    Exit(Abs(NumValue(a) - NumValue(b)) < 1e-12);
  if (a.Kind = vkString) and (b.Kind = vkString) then
    Exit(a.StrVal = b.StrVal);
  if (a.Kind = vkBool) and (b.Kind = vkBool) then
    Exit(a.BoolVal = b.BoolVal);
  if (a.Kind = vkNull) and (b.Kind = vkNull) then
    Exit(true);
  Result := false;
end;

function CompareValues(a, b: TValue): integer;
begin
  if IsNumeric(a) and IsNumeric(b) then
  begin
    if NumValue(a) < NumValue(b) then Exit(-1);
    if NumValue(a) > NumValue(b) then Exit(1);
    Exit(0);
  end;
  if (a.Kind = vkString) and (b.Kind = vkString) then
    Exit(string.CompareOrdinal(a.StrVal, b.StrVal));
  raise new EScriptError('Сравнение неприменимо к этим значениям', 0, 0);
end;

// ---------------------------------------------------------------- TValue

function TValue.AsInt: int64;
begin
  case Kind of
    vkInt: Result := IntVal;
    vkFloat: Result := Round(FloatVal);
    vkString: Result := int64.Parse(StrVal, CultureInfo.InvariantCulture);
    vkBool: if BoolVal then Result := 1 else Result := 0;
  else
    raise new EScriptError('Ожидалось целое число', 0, 0);
  end;
end;

function TValue.AsFloat: double;
begin
  case Kind of
    vkInt: Result := IntVal;
    vkFloat: Result := FloatVal;
    vkString: Result := double.Parse(StrVal, CultureInfo.InvariantCulture);
    vkBool: if BoolVal then Result := 1 else Result := 0;
  else
    raise new EScriptError('Ожидалось число', 0, 0);
  end;
end;

function TValue.AsString: string;
begin
  if Kind = vkString then
    Result := StrVal
  else
    Result := Display;
end;

function TValue.AsBool: boolean;
begin
  case Kind of
    vkBool: Result := BoolVal;
    vkInt: Result := IntVal <> 0;
    vkFloat: Result := Abs(FloatVal) > 1e-12;
    vkString: Result := LowerCase(StrVal) = 'true';
  else
    Result := false;
  end;
end;

function TValue.Truthy: boolean;
begin
  case Kind of
    vkNull: Result := false;
    vkBool: Result := BoolVal;
    vkInt: Result := IntVal <> 0;
    vkFloat: Result := Abs(FloatVal) > 1e-12;
    vkString: Result := StrVal <> '';
    vkList: Result := ListVal.Count > 0;
    vkObject: Result := ObjVal.Fields.Count > 0;
    vkFunc, vkBuiltin: Result := true;
  end;
end;

function TValue.Display: string;
var
  i: integer;
  parts: List<string>;
  pair: KeyValuePair<string, TValue>;
begin
  case Kind of
    vkNull: Result := 'null';
    vkInt: Result := IntVal.ToString(CultureInfo.InvariantCulture);
    vkFloat: Result := FloatVal.ToString('0.####', CultureInfo.InvariantCulture);
    vkString: Result := StrVal;
    vkBool: if BoolVal then Result := 'true' else Result := 'false';
    vkList:
      begin
        parts := new List<string>;
        for i := 0 to ListVal.Count - 1 do
          parts.Add(ListVal[i].Display);
        Result := '[' + string.Join(', ', parts) + ']';
      end;
    vkObject:
      begin
        parts := new List<string>;
        foreach pair in ObjVal.Fields do
          parts.Add($'{pair.Key}: {pair.Value.Display}');
        Result := '{' + string.Join(', ', parts) + '}';
      end;
    vkFunc: Result := '<lambda>';
    vkBuiltin: Result := $'<builtin {BuiltinName}>';
  end;
end;

// ---------------------------------------------------------- TObjectValue

constructor TObjectValue.Create;
begin
  Fields := new Dictionary<string, TValue>;
end;

function TObjectValue.Get(name: string): TValue;
begin
  if not Fields.TryGetValue(name, Result) then
    raise new EScriptError($'В объекте нет поля "{name}"', 0, 0);
end;

procedure TObjectValue.Put(name: string; value: TValue);
begin
  Fields[name] := value;
end;

function TObjectValue.Has(name: string): boolean;
begin
  Result := Fields.ContainsKey(name);
end;

function TObjectValue.Clone: TObjectValue;
var
  pair: KeyValuePair<string, TValue>;
begin
  Result := new TObjectValue;
  foreach pair in Fields do
    Result.Fields[pair.Key] := pair.Value;
end;

// ------------------------------------------------------------------- TEnv

constructor TEnv.Create(parent: TEnv);
begin
  fValues := new Dictionary<string, TValue>;
  fParent := parent;
end;

procedure TEnv.Define(name: string; value: TValue);
begin
  fValues[name] := value;
end;

function TEnv.TryGet(name: string; var value: TValue): boolean;
begin
  if fValues.TryGetValue(name, value) then
    Exit(true);
  if fParent <> nil then
    Exit(fParent.TryGet(name, value));
  Result := false;
end;

function TEnv.Get(name: string): TValue;
begin
  if not TryGet(name, Result) then
    raise new EScriptError($'Неизвестное имя "{name}"', 0, 0);
end;

// ------------------------------------------------------- monster/item specs

constructor TMonsterSpec.Create;
begin
  Hp := 10;
  Damage := 2;
  Defense := 0;
  Xp := 3;
  AggroRange := 7;
  Ai := 'patrol';
  Glyph := '?';
  Boss := false;
  FleeAt := 0.25;
  SetLength(Loot, 0);
end;

constructor TItemSpec.Create;
begin
  Kind := 'misc';
  Power := 0;
  Value := 0;
  Glyph := '?';
end;

// ------------------------------------------------------------- evaluator

constructor TEvaluator.Create(config: TConfigSet);
begin
  fConfig := config;
  fGlobals := new TEnv(nil);
  fEnv := fGlobals;
  fDepth := 0;
  DefineBuiltins;
end;

procedure TEvaluator.DefineBuiltins;
var
  names: array of string;
  i: integer;
begin
  names := ['len', 'str', 'int', 'float', 'min', 'max', 'clamp', 'merge', 'type'];
  for i := 0 to names.Length - 1 do
    fGlobals.Define(names[i], VBuiltin(names[i]));
end;

procedure TEvaluator.Run(prog: TProgramNode);
begin
  prog.Accept(Self);
end;

function TEvaluator.Eval(n: TExpr): TValue;
begin
  n.Accept(Self);
  Result := fLast;
end;

procedure TEvaluator.VisitProgram(n: TProgramNode);
var
  d: TAstNode;
begin
  foreach d in n.Decls do
    d.Accept(Self);
end;

procedure TEvaluator.VisitLet(n: TLetNode);
begin
  fGlobals.Define(n.Name, Eval(n.Value));
end;

procedure TEvaluator.VisitMonster(n: TMonsterNode);
var
  v: TValue;
begin
  v := Eval(n.Body);
  fConfig.AddMonster(ObjectToMonster(n.Name, v));
end;

procedure TEvaluator.VisitItem(n: TItemNode);
var
  v: TValue;
begin
  v := Eval(n.Body);
  fConfig.AddItem(ObjectToItem(n.Name, v));
end;

procedure TEvaluator.VisitInt(n: TIntLit);
begin
  fLast := VInt(n.Value);
end;

procedure TEvaluator.VisitFloat(n: TFloatLit);
begin
  fLast := VFloat(n.Value);
end;

procedure TEvaluator.VisitString(n: TStringLit);
begin
  fLast := VStr(n.Value);
end;

procedure TEvaluator.VisitBool(n: TBoolLit);
begin
  fLast := VBool(n.Value);
end;

procedure TEvaluator.VisitIdent(n: TIdent);
var
  v: TValue;
begin
  if fEnv.TryGet(n.Name, v) then
    fLast := v
  else
    fLast := VStr(n.Name);
end;

procedure TEvaluator.VisitList(n: TListLit);
var
  lst: TValue;
  e: TListEntry;
  v: TValue;
  k: integer;
begin
  lst := VList;
  foreach e in n.Entries do
  begin
    v := Eval(e.Value);
    for k := 1 to e.Count do
      lst.ListVal.Add(v);
  end;
  fLast := lst;
end;

procedure TEvaluator.VisitObject(n: TObjectLit);
var
  obj: TValue;
  fld: TObjField;
begin
  obj := VObject;
  foreach fld in n.Fields do
    obj.ObjVal.Put(fld.Name, Eval(fld.Value));
  fLast := obj;
end;

procedure TEvaluator.VisitBinary(n: TBinary);
var
  a, b: TValue;
  bv: double;
  lst: TValue;
  i: integer;
  obj: TObjectValue;
begin
  if n.Op = 'and' then
  begin
    a := Eval(n.Left);
    if not a.Truthy then
      fLast := VBool(false)
    else
      fLast := VBool(Eval(n.Right).Truthy);
    Exit;
  end;
  if n.Op = 'or' then
  begin
    a := Eval(n.Left);
    if a.Truthy then
      fLast := VBool(true)
    else
      fLast := VBool(Eval(n.Right).Truthy);
    Exit;
  end;

  a := Eval(n.Left);
  b := Eval(n.Right);
  case n.Op of
    '=': fLast := VBool(ValuesEqual(a, b));
    '!=': fLast := VBool(not ValuesEqual(a, b));
    '<': fLast := VBool(CompareValues(a, b) < 0);
    '<=': fLast := VBool(CompareValues(a, b) <= 0);
    '>': fLast := VBool(CompareValues(a, b) > 0);
    '>=': fLast := VBool(CompareValues(a, b) >= 0);
    '+':
      begin
        if (a.Kind = vkObject) and (b.Kind = vkObject) then
        begin
          obj := a.ObjVal.Clone;
          foreach var pair in b.ObjVal.Fields do
            obj.Fields[pair.Key] := pair.Value;
          fLast := VObject;
          fLast.ObjVal := obj;
        end
        else if (a.Kind = vkList) and (b.Kind = vkList) then
        begin
          lst := VList;
          for i := 0 to a.ListVal.Count - 1 do lst.ListVal.Add(a.ListVal[i]);
          for i := 0 to b.ListVal.Count - 1 do lst.ListVal.Add(b.ListVal[i]);
          fLast := lst;
        end
        else if (a.Kind = vkString) or (b.Kind = vkString) then
          fLast := VStr(a.Display + b.Display)
        else if (a.Kind = vkInt) and (b.Kind = vkInt) then
          fLast := VInt(a.IntVal + b.IntVal)
        else
          fLast := VFloat(a.AsFloat + b.AsFloat);
      end;
    '-':
      if (a.Kind = vkInt) and (b.Kind = vkInt) then
        fLast := VInt(a.IntVal - b.IntVal)
      else
        fLast := VFloat(a.AsFloat - b.AsFloat);
    '*':
      if (a.Kind = vkInt) and (b.Kind = vkInt) then
        fLast := VInt(a.IntVal * b.IntVal)
      else
        fLast := VFloat(a.AsFloat * b.AsFloat);
    '/':
      begin
        bv := b.AsFloat;
        if Abs(bv) < 1e-15 then
          raise new EScriptError('Деление на ноль', n.Line, n.Col);
        fLast := VFloat(a.AsFloat / bv);
      end;
  else
    raise new EScriptError($'Неизвестная операция "{n.Op}"', n.Line, n.Col);
  end;
end;

procedure TEvaluator.VisitUnary(n: TUnary);
var
  v: TValue;
begin
  v := Eval(n.Operand);
  if n.Op = '-' then
  begin
    if v.Kind = vkInt then
      fLast := VInt(-v.IntVal)
    else
      fLast := VFloat(-v.AsFloat);
  end
  else
    fLast := VBool(not v.Truthy);
end;

procedure TEvaluator.VisitLambda(n: TLambda);
begin
  fLast := VFunc(n.ParamNames, n.Body, fEnv, new List<TValue>);
end;

procedure TEvaluator.VisitCall(n: TCall);
var
  fn: TValue;
  args: List<TValue>;
  a: TExpr;
begin
  fn := Eval(n.Callee);
  args := new List<TValue>;
  foreach a in n.Args do
    args.Add(Eval(a));
  fLast := Apply(fn, args);
end;

procedure TEvaluator.VisitField(n: TField);
var
  base: TValue;
begin
  base := Eval(n.Base);
  if base.Kind <> vkObject then
    raise new EScriptError($'Обращение к полю "{n.FieldName}" у не-объекта',
      n.Line, n.Col);
  fLast := base.ObjVal.Get(n.FieldName);
end;

procedure TEvaluator.VisitIf(n: TIfExpr);
begin
  if Eval(n.Cond).Truthy then
    fLast := Eval(n.ThenExpr)
  else
    fLast := Eval(n.ElseExpr);
end;

function TEvaluator.Apply(fn: TValue; args: List<TValue>): TValue;
var
  combined, extra: List<TValue>;
  child: TEnv;
  saved: TEnv;
  i: integer;
begin
  if fn.Kind = vkBuiltin then
    Exit(CallBuiltin(fn.BuiltinName, args));
  if fn.Kind <> vkFunc then
    raise new EScriptError('Вызов не-функции', 0, 0);

  combined := new List<TValue>;
  if fn.Applied <> nil then
    combined.AddRange(fn.Applied);
  combined.AddRange(args);

  if combined.Count < fn.ParamNames.Count then
    Exit(VFunc(fn.ParamNames, fn.Body, fn.Closure, combined));

  child := new TEnv(fn.Closure);
  for i := 0 to fn.ParamNames.Count - 1 do
    child.Define(fn.ParamNames[i], combined[i]);
  saved := fEnv;
  fEnv := child;
  Inc(fDepth);
  try
    if fDepth > 200 then
      raise new EScriptError('Слишком глубокая рекурсия', 0, 0);
    Result := Eval(fn.Body);
  finally
    Dec(fDepth);
    fEnv := saved;
  end;

  if combined.Count > fn.ParamNames.Count then
  begin
    extra := combined.GetRange(fn.ParamNames.Count, combined.Count - fn.ParamNames.Count);
    Result := Apply(Result, extra);
  end;
end;

function TEvaluator.CallBuiltin(name: string; args: List<TValue>): TValue;
var
  v: TValue;
  s: string;
begin
  case name of
    'len':
      begin
        if args.Count <> 1 then raise new EScriptError('len: нужен 1 аргумент', 0, 0);
        v := args[0];
        case v.Kind of
          vkString: Result := VInt(v.StrVal.Length);
          vkList: Result := VInt(v.ListVal.Count);
          vkObject: Result := VInt(v.ObjVal.Fields.Count);
        else
          raise new EScriptError('len: неподдерживаемый тип', 0, 0);
        end;
      end;
    'str': Result := VStr(args[0].Display);
    'int': Result := VInt(args[0].AsInt);
    'float': Result := VFloat(args[0].AsFloat);
    'min':
      begin
        if (args[0].Kind = vkInt) and (args[1].Kind = vkInt) then
          Result := VInt(Min(args[0].IntVal, args[1].IntVal))
        else
          Result := VFloat(Min(args[0].AsFloat, args[1].AsFloat));
      end;
    'max':
      begin
        if (args[0].Kind = vkInt) and (args[1].Kind = vkInt) then
          Result := VInt(Max(args[0].IntVal, args[1].IntVal))
        else
          Result := VFloat(Max(args[0].AsFloat, args[1].AsFloat));
      end;
    'clamp':
      begin
        if (args[0].Kind = vkInt) and (args[1].Kind = vkInt) and (args[2].Kind = vkInt) then
          Result := VInt(Clamp(args[0].IntVal, args[1].IntVal, args[2].IntVal))
        else
          Result := VFloat(Clamp(args[0].AsFloat, args[1].AsFloat, args[2].AsFloat));
      end;
    'merge':
      begin
        v := VObject;
        v.ObjVal := args[0].ObjVal.Clone;
        foreach var pair in args[1].ObjVal.Fields do
          v.ObjVal.Fields[pair.Key] := pair.Value;
        Result := v;
      end;
    'type':
      begin
        case args[0].Kind of
          vkNull: s := 'null';
          vkInt: s := 'int';
          vkFloat: s := 'float';
          vkString: s := 'string';
          vkBool: s := 'bool';
          vkList: s := 'list';
          vkObject: s := 'object';
          vkFunc: s := 'function';
          vkBuiltin: s := 'builtin';
        end;
        Result := VStr(s);
      end;
  else
    raise new EScriptError($'Неизвестная встроенная функция "{name}"', 0, 0);
  end;
end;

function TEvaluator.ObjectToMonster(key: string; value: TValue): TMonsterSpec;
var
  obj: TObjectValue;
  spec: TMonsterSpec;
  loot: TValue;
  i: integer;
  s: string;
begin
  if value.Kind <> vkObject then
    raise new EScriptError($'monster {key}: ожидался объект', 0, 0);
  obj := value.ObjVal;
  spec := new TMonsterSpec;
  spec.Key := key;
  if obj.Has('name') then spec.Name := obj.Get('name').AsString else spec.Name := key;
  if obj.Has('hp') then spec.Hp := Max(1, obj.Get('hp').AsInt);
  if obj.Has('damage') then spec.Damage := Max(1, obj.Get('damage').AsInt);
  if obj.Has('defense') then spec.Defense := Max(0, obj.Get('defense').AsInt);
  if obj.Has('xp') then spec.Xp := Max(0, obj.Get('xp').AsInt) else spec.Xp := Max(1, spec.Hp div 3);
  if obj.Has('aggro_range') then spec.AggroRange := Max(1, obj.Get('aggro_range').AsInt);
  if obj.Has('ai') then spec.Ai := LowerCase(obj.Get('ai').AsString);
  if obj.Has('glyph') then
  begin
    s := obj.Get('glyph').AsString;
    if s.Length > 0 then spec.Glyph := s[1];
  end;
  if obj.Has('boss') then spec.Boss := obj.Get('boss').AsBool;
  if obj.Has('flee_at') then spec.FleeAt := Clamp(obj.Get('flee_at').AsFloat, 0.0, 1.0);
  if obj.Has('loot') then
  begin
    loot := obj.Get('loot');
    if loot.Kind <> vkList then
      raise new EScriptError($'monster {key}: loot должен быть списком', 0, 0);
    SetLength(spec.Loot, loot.ListVal.Count);
    for i := 0 to loot.ListVal.Count - 1 do
      spec.Loot[i] := loot.ListVal[i].AsString;
  end;
  Result := spec;
end;

function TEvaluator.ObjectToItem(key: string; value: TValue): TItemSpec;
var
  obj: TObjectValue;
  spec: TItemSpec;
  s: string;
begin
  if value.Kind <> vkObject then
    raise new EScriptError($'item {key}: ожидался объект', 0, 0);
  obj := value.ObjVal;
  spec := new TItemSpec;
  spec.Key := key;
  if obj.Has('name') then spec.Name := obj.Get('name').AsString else spec.Name := key;
  if obj.Has('kind') then spec.Kind := LowerCase(obj.Get('kind').AsString);
  if obj.Has('power') then spec.Power := obj.Get('power').AsInt;
  if obj.Has('value') then spec.Value := obj.Get('value').AsInt;
  if obj.Has('glyph') then
  begin
    s := obj.Get('glyph').AsString;
    if s.Length > 0 then spec.Glyph := s[1];
  end;
  Result := spec;
end;

// -------------------------------------------------------------- config set

constructor TConfigSet.Create;
begin
  fMonsters := new Dictionary<string, TMonsterSpec>;
  fItems := new Dictionary<string, TItemSpec>;
end;

procedure TConfigSet.AddMonster(spec: TMonsterSpec);
begin
  if fMonsters.ContainsKey(spec.Key) then
    raise new EScriptError($'Монстр "{spec.Key}" объявлен дважды', 0, 0);
  fMonsters[spec.Key] := spec;
end;

procedure TConfigSet.AddItem(spec: TItemSpec);
begin
  if fItems.ContainsKey(spec.Key) then
    raise new EScriptError($'Предмет "{spec.Key}" объявлен дважды', 0, 0);
  fItems[spec.Key] := spec;
end;

procedure TConfigSet.LoadFile(path: string);
var
  code: string;
  prog: TProgramNode;
  ev: TEvaluator;
begin
  if not System.IO.File.Exists(path) then
    raise new EScriptError($'Файл конфигурации не найден: {path}', 0, 0);
  code := System.IO.File.ReadAllText(path);
  try
    prog := ParseSource(code);
    ev := new TEvaluator(Self);
    ev.Run(prog);
  except
    on e: EScriptError do
      raise new EScriptError($'{System.IO.Path.GetFileName(path)}: {e.Message}', e.Line, e.Col);
  end;
end;

procedure TConfigSet.LoadDirectory(path: string);
var
  files: array of string;
  f: string;
  monster: TMonsterSpec;
  itemName: string;
begin
  if not System.IO.Directory.Exists(path) then
    raise new EScriptError($'Каталог конфигурации не найден: {path}', 0, 0);
  files := System.IO.Directory.GetFiles(path, '*.cfg');
  System.Array.Sort(files);
  foreach f in files do
    LoadFile(f);
  foreach monster in fMonsters.Values do
    foreach itemName in monster.Loot do
      if not fItems.ContainsKey(itemName) then
        raise new EScriptError($'Монстр "{monster.Key}" ссылается на неизвестный предмет "{itemName}"', 0, 0);
end;

function TConfigSet.MonsterKeys: array of string;
var
  keys: List<string>;
  k: string;
begin
  keys := new List<string>;
  foreach k in fMonsters.Keys do keys.Add(k);
  keys.Sort;
  Result := keys.ToArray;
end;

function TConfigSet.ItemKeys: array of string;
var
  keys: List<string>;
  k: string;
begin
  keys := new List<string>;
  foreach k in fItems.Keys do keys.Add(k);
  keys.Sort;
  Result := keys.ToArray;
end;

function TConfigSet.Monster(key: string): TMonsterSpec;
begin
  if not fMonsters.TryGetValue(key, Result) then
    raise new EScriptError($'Нет монстра "{key}"', 0, 0);
end;

function TConfigSet.Item(key: string): TItemSpec;
begin
  if not fItems.TryGetValue(key, Result) then
    raise new EScriptError($'Нет предмета "{key}"', 0, 0);
end;

// ------------------------------------------------------------------- JSON

function JNull: TJsonValue;
begin
  Result := new TJsonValue;
  Result.Kind := jkNull;
end;

function JBool(v: boolean): TJsonValue;
begin
  Result := new TJsonValue;
  Result.Kind := jkBool;
  Result.BoolVal := v;
end;

function JInt(v: int64): TJsonValue;
begin
  Result := new TJsonValue;
  Result.Kind := jkInt;
  Result.IntVal := v;
end;

function JFloat(v: double): TJsonValue;
begin
  Result := new TJsonValue;
  Result.Kind := jkFloat;
  Result.FloatVal := v;
end;

function JStr(v: string): TJsonValue;
begin
  Result := new TJsonValue;
  Result.Kind := jkString;
  Result.StrVal := v;
end;

function JArray: TJsonValue;
begin
  Result := new TJsonValue;
  Result.Kind := jkArray;
  Result.Arr := new List<TJsonValue>;
end;

function JObject: TJsonValue;
begin
  Result := new TJsonValue;
  Result.Kind := jkObject;
  Result.Obj := new Dictionary<string, TJsonValue>;
end;

function TJsonValue.AsInt: int64;
begin
  case Kind of
    jkInt: Result := IntVal;
    jkFloat: Result := Round(FloatVal);
    jkBool: if BoolVal then Result := 1 else Result := 0;
    jkString: Result := int64.Parse(StrVal, CultureInfo.InvariantCulture);
  else
    Result := 0;
  end;
end;

function TJsonValue.AsFloat: double;
begin
  case Kind of
    jkInt: Result := IntVal;
    jkFloat: Result := FloatVal;
    jkBool: if BoolVal then Result := 1 else Result := 0;
    jkString: Result := double.Parse(StrVal, CultureInfo.InvariantCulture);
  else
    Result := 0;
  end;
end;

function TJsonValue.AsString: string;
begin
  case Kind of
    jkString: Result := StrVal;
    jkInt: Result := IntVal.ToString(CultureInfo.InvariantCulture);
    jkFloat: Result := FloatVal.ToString('R', CultureInfo.InvariantCulture);
    jkBool: if BoolVal then Result := 'true' else Result := 'false';
    jkNull: Result := '';
  else
    Result := '';
  end;
end;

function TJsonValue.AsBool: boolean;
begin
  case Kind of
    jkBool: Result := BoolVal;
    jkInt: Result := IntVal <> 0;
    jkFloat: Result := Abs(FloatVal) > 1e-12;
    jkString: Result := LowerCase(StrVal) = 'true';
  else
    Result := false;
  end;
end;

function TJsonValue.Item(name: string): TJsonValue;
begin
  if (Kind <> jkObject) or (not Obj.TryGetValue(name, Result)) then
    Result := nil;
end;

function TJsonValue.Has(name: string): boolean;
begin
  Result := (Kind = jkObject) and Obj.ContainsKey(name);
end;

function TJsonValue.Count: integer;
begin
  case Kind of
    jkArray: Result := Arr.Count;
    jkObject: Result := Obj.Count;
    jkString: Result := StrVal.Length;
  else
    Result := 0;
  end;
end;

procedure TJsonValue.Add(v: TJsonValue);
begin
  Arr.Add(v);
end;

procedure TJsonValue.Put(name: string; v: TJsonValue);
begin
  Obj[name] := v;
end;

function JsonEscape(s: string): string;
var
  i: integer;
  ch: char;
  sb: StringBuilder;
begin
  sb := new StringBuilder;
  for i := 1 to s.Length do
  begin
    ch := s[i];
    case ch of
      '"': sb.Append('\"');
      '\': sb.Append('\\');
      #8: sb.Append('\b');
      #9: sb.Append('\t');
      #10: sb.Append('\n');
      #12: sb.Append('\f');
      #13: sb.Append('\r');
    else
      if ch < #32 then
        sb.Append('\u' + Ord(ch).ToString('x4'))
      else
        sb.Append(ch);
    end;
  end;
  Result := sb.ToString;
end;

procedure JsonWrite(v: TJsonValue; sb: StringBuilder);
var
  i: integer;
  keys: List<string>;
  k: string;
begin
  if v = nil then
  begin
    sb.Append('null');
    Exit;
  end;
  case v.Kind of
    jkNull: sb.Append('null');
    jkBool: if v.BoolVal then sb.Append('true') else sb.Append('false');
    jkInt: sb.Append(v.IntVal.ToString(CultureInfo.InvariantCulture));
    jkFloat: sb.Append(v.FloatVal.ToString('R', CultureInfo.InvariantCulture));
    jkString: sb.Append('"' + JsonEscape(v.StrVal) + '"');
    jkArray:
      begin
        sb.Append('[');
        for i := 0 to v.Arr.Count - 1 do
        begin
          if i > 0 then sb.Append(',');
          JsonWrite(v.Arr[i], sb);
        end;
        sb.Append(']');
      end;
    jkObject:
      begin
        sb.Append('{');
        keys := new List<string>;
        foreach k in v.Obj.Keys do keys.Add(k);
        keys.Sort;
        for i := 0 to keys.Count - 1 do
        begin
          if i > 0 then sb.Append(',');
          sb.Append('"' + JsonEscape(keys[i]) + '":');
          JsonWrite(v.Obj[keys[i]], sb);
        end;
        sb.Append('}');
      end;
  end;
end;

function TJsonValue.ToJson: string;
var
  sb: StringBuilder;
begin
  sb := new StringBuilder;
  JsonWrite(Self, sb);
  Result := sb.ToString;
end;

constructor TJsonParser.Create(text: string);
begin
  fText := text;
  fPos := 1;
end;

procedure TJsonParser.SkipWs;
begin
  while (fPos <= fText.Length) and Char.IsWhiteSpace(fText[fPos]) do
    Inc(fPos);
end;

procedure TJsonParser.Error(message: string);
begin
  raise new EScriptError($'JSON: {message}', 1, fPos);
end;

function TJsonParser.ParseString: string;
var
  sb: StringBuilder;
  ch: char;
  code: integer;
  highSurrogate: integer;

  function ReadHex4: integer;
  var
    k: integer;
    c: char;
  begin
    Result := 0;
    for k := 1 to 4 do
    begin
      if fPos > fText.Length then
        Error('оборван \\u-escape');
      c := fText[fPos];
      Inc(fPos);
      Result := Result * 16;
      if (c >= '0') and (c <= '9') then Result += Ord(c) - Ord('0')
      else if (c >= 'a') and (c <= 'f') then Result += Ord(c) - Ord('a') + 10
      else if (c >= 'A') and (c <= 'F') then Result += Ord(c) - Ord('A') + 10
      else Error('плохой \\u-escape');
    end;
  end;

begin
  sb := new StringBuilder;
  if (fPos > fText.Length) or (fText[fPos] <> '"') then
    Error('ожидалась строка');
  Inc(fPos);
  while (fPos <= fText.Length) and (fText[fPos] <> '"') do
  begin
    ch := fText[fPos];
    Inc(fPos);
    if ch = '\' then
    begin
      if fPos > fText.Length then Error('оборван escape');
      ch := fText[fPos];
      Inc(fPos);
      case ch of
        '"': sb.Append('"');
        '\': sb.Append('\');
        '/': sb.Append('/');
        'b': sb.Append(#8);
        'f': sb.Append(#12);
        'n': sb.Append(#10);
        'r': sb.Append(#13);
        't': sb.Append(#9);
        'u':
          begin
            code := ReadHex4;
            if (code >= $D800) and (code <= $DBFF) then
            begin
              highSurrogate := code;
              if (fPos + 1 <= fText.Length) and (fText[fPos] = '\') and (fText[fPos + 1] = 'u') then
              begin
                Inc(fPos, 2);
                code := ReadHex4;
                sb.Append(Char.ConvertFromUtf32($10000 + ((highSurrogate - $D800) shl 10) + (code - $DC00)));
              end
              else
                sb.Append(char(highSurrogate));
            end
            else
              sb.Append(char(code));
          end;
      else
        Error('неизвестный escape');
      end;
    end
    else
      sb.Append(ch);
  end;
  if (fPos > fText.Length) or (fText[fPos] <> '"') then
    Error('незакрытая строка');
  Inc(fPos);
  Result := sb.ToString;
end;

function TJsonParser.ParseNumber: TJsonValue;
var
  start: integer;
  isFloat: boolean;
  text: string;
begin
  start := fPos;
  isFloat := false;
  if (fPos <= fText.Length) and (fText[fPos] = '-') then Inc(fPos);
  while (fPos <= fText.Length) and Char.IsDigit(fText[fPos]) do Inc(fPos);
  if (fPos <= fText.Length) and (fText[fPos] = '.') then
  begin
    isFloat := true;
    Inc(fPos);
    while (fPos <= fText.Length) and Char.IsDigit(fText[fPos]) do Inc(fPos);
  end;
  if (fPos <= fText.Length) and ((fText[fPos] = 'e') or (fText[fPos] = 'E')) then
  begin
    isFloat := true;
    Inc(fPos);
    if (fPos <= fText.Length) and ((fText[fPos] = '+') or (fText[fPos] = '-')) then Inc(fPos);
    while (fPos <= fText.Length) and Char.IsDigit(fText[fPos]) do Inc(fPos);
  end;
  text := fText.Substring(start - 1, fPos - start);
  if isFloat then
    Result := JFloat(double.Parse(text, CultureInfo.InvariantCulture))
  else
    Result := JInt(int64.Parse(text, CultureInfo.InvariantCulture));
end;

function TJsonParser.ParseArray: TJsonValue;
begin
  Result := JArray;
  Inc(fPos);
  SkipWs;
  if (fPos <= fText.Length) and (fText[fPos] = ']') then
  begin
    Inc(fPos);
    Exit;
  end;
  while true do
  begin
    Result.Add(ParseValue);
    SkipWs;
    if (fPos <= fText.Length) and (fText[fPos] = ',') then
    begin
      Inc(fPos);
      SkipWs;
    end
    else
      Break;
  end;
  if (fPos > fText.Length) or (fText[fPos] <> ']') then
    Error('ожидался ]');
  Inc(fPos);
end;

function TJsonParser.ParseObject: TJsonValue;
var
  key: string;
begin
  Result := JObject;
  Inc(fPos);
  SkipWs;
  if (fPos <= fText.Length) and (fText[fPos] = '}') then
  begin
    Inc(fPos);
    Exit;
  end;
  while true do
  begin
    SkipWs;
    key := ParseString;
    SkipWs;
    if (fPos > fText.Length) or (fText[fPos] <> ':') then
      Error('ожидался :');
    Inc(fPos);
    SkipWs;
    Result.Put(key, ParseValue);
    SkipWs;
    if (fPos <= fText.Length) and (fText[fPos] = ',') then
    begin
      Inc(fPos);
      Continue;
    end;
    Break;
  end;
  SkipWs;
  if (fPos > fText.Length) or (fText[fPos] <> '}') then
    Error('ожидался }');
  Inc(fPos);
end;

function TJsonParser.ParseValue: TJsonValue;
var
  ch: char;
begin
  SkipWs;
  if fPos > fText.Length then
    Error('неожиданный конец');
  ch := fText[fPos];
  case ch of
    '{': Result := ParseObject;
    '[': Result := ParseArray;
    '"': Result := JStr(ParseString);
    't':
      begin
        if fText.Substring(fPos - 1, 4) <> 'true' then Error('ожидалось true');
        Inc(fPos, 4);
        Result := JBool(true);
      end;
    'f':
      begin
        if fText.Substring(fPos - 1, 5) <> 'false' then Error('ожидалось false');
        Inc(fPos, 5);
        Result := JBool(false);
      end;
    'n':
      begin
        if fText.Substring(fPos - 1, 4) <> 'null' then Error('ожидалось null');
        Inc(fPos, 4);
        Result := JNull;
      end;
    '-', '0'..'9': Result := ParseNumber;
  else
    Error($'неожиданный символ "{ch}"');
  end;
end;

function TJsonParser.Parse: TJsonValue;
begin
  SkipWs;
  Result := ParseValue;
  SkipWs;
  if fPos <= fText.Length then
    Error('лишние данные после JSON');
end;

function JsonParse(text: string): TJsonValue;
var
  p: TJsonParser;
begin
  p := new TJsonParser(text);
  Result := p.Parse;
end;
