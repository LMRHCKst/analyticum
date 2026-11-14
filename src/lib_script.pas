unit lib_script;

// M3: DSL конфигов. Лексер -> парсер -> AST -> Visitor.
// AST печатает себя обратно, evaluator поддерживает лямбды, карринг
// и слияние объектов (наследование конфигов через функции).

interface

uses System, System.Collections.Generic, System.Linq, System.Text, System.IO,
  System.Globalization, lib_core;

type
  EScriptError = class(Exception)
  public
    Line, Col: integer;
    constructor Create(message: string; line, col: integer);
  end;

  TTokenKind = (tkEof, tkIdent, tkInt, tkFloat, tkString,
    tkLBrace, tkRBrace, tkLBracket, tkRBracket, tkLParen, tkRParen,
    tkColon, tkSemicolon, tkComma, tkAssign, tkPlus, tkMinus, tkStar, tkSlash,
    tkArrow, tkDot, tkEq, tkNe, tkLt, tkLe, tkGt, tkGe,
    tkAnd, tkOr, tkNot, tkIf, tkThen, tkElse,
    tkLet, tkMonster, tkItem, tkTrue, tkFalse);

  TToken = record
    Kind: TTokenKind;
    Text: string;
    IntVal: int64;
    FloatVal: double;
    Line, Col: integer;
  end;

  TProgramNode = class;
  TLetNode = class;
  TMonsterNode = class;
  TItemNode = class;
  TIntLit = class;
  TFloatLit = class;
  TStringLit = class;
  TBoolLit = class;
  TIdent = class;
  TListLit = class;
  TObjectLit = class;
  TBinary = class;
  TUnary = class;
  TLambda = class;
  TCall = class;
  TField = class;
  TIfExpr = class;

  IAstVisitor = interface
    procedure VisitProgram(n: TProgramNode);
    procedure VisitLet(n: TLetNode);
    procedure VisitMonster(n: TMonsterNode);
    procedure VisitItem(n: TItemNode);
    procedure VisitInt(n: TIntLit);
    procedure VisitFloat(n: TFloatLit);
    procedure VisitString(n: TStringLit);
    procedure VisitBool(n: TBoolLit);
    procedure VisitIdent(n: TIdent);
    procedure VisitList(n: TListLit);
    procedure VisitObject(n: TObjectLit);
    procedure VisitBinary(n: TBinary);
    procedure VisitUnary(n: TUnary);
    procedure VisitLambda(n: TLambda);
    procedure VisitCall(n: TCall);
    procedure VisitField(n: TField);
    procedure VisitIf(n: TIfExpr);
  end;

  TAstNode = class
  public
    Line, Col: integer;
    procedure Accept(v: IAstVisitor); virtual; abstract;
  end;

  TExpr = class(TAstNode)
  end;

  TListEntry = record
    Value: TExpr;
    Count: integer;
  end;

  TObjField = record
    Name: string;
    Value: TExpr;
  end;

  TProgramNode = class(TAstNode)
  public
    Decls: List<TAstNode>;
    constructor Create;
    procedure Accept(v: IAstVisitor); override;
  end;

  TLetNode = class(TAstNode)
  public
    Name: string;
    Value: TExpr;
    procedure Accept(v: IAstVisitor); override;
  end;

  TMonsterNode = class(TAstNode)
  public
    Name: string;
    Body: TExpr;
    procedure Accept(v: IAstVisitor); override;
  end;

  TItemNode = class(TAstNode)
  public
    Name: string;
    Body: TExpr;
    procedure Accept(v: IAstVisitor); override;
  end;

  TIntLit = class(TExpr)
  public
    Value: int64;
    procedure Accept(v: IAstVisitor); override;
  end;

  TFloatLit = class(TExpr)
  public
    Value: double;
    procedure Accept(v: IAstVisitor); override;
  end;

  TStringLit = class(TExpr)
  public
    Value: string;
    procedure Accept(v: IAstVisitor); override;
  end;

  TBoolLit = class(TExpr)
  public
    Value: boolean;
    procedure Accept(v: IAstVisitor); override;
  end;

  TIdent = class(TExpr)
  public
    Name: string;
    procedure Accept(v: IAstVisitor); override;
  end;

  TListLit = class(TExpr)
  public
    Entries: List<TListEntry>;
    constructor Create;
    procedure Accept(v: IAstVisitor); override;
  end;

  TObjectLit = class(TExpr)
  public
    Fields: List<TObjField>;
    constructor Create;
    procedure Accept(v: IAstVisitor); override;
  end;

  TBinary = class(TExpr)
  public
    Op: string;
    Left, Right: TExpr;
    procedure Accept(v: IAstVisitor); override;
  end;

  TUnary = class(TExpr)
  public
    Op: string;
    Operand: TExpr;
    procedure Accept(v: IAstVisitor); override;
  end;

  TLambda = class(TExpr)
  public
    ParamNames: List<string>;
    Body: TExpr;
    constructor Create;
    procedure Accept(v: IAstVisitor); override;
  end;

  TCall = class(TExpr)
  public
    Callee: TExpr;
    Args: List<TExpr>;
    constructor Create;
    procedure Accept(v: IAstVisitor); override;
  end;

  TField = class(TExpr)
  public
    Base: TExpr;
    FieldName: string;
    procedure Accept(v: IAstVisitor); override;
  end;

  TIfExpr = class(TExpr)
  public
    Cond, ThenExpr, ElseExpr: TExpr;
    procedure Accept(v: IAstVisitor); override;
  end;

  TMonsterSpec = class
  public
    Key: string;
    Name: string;
    Hp, Damage, Defense, Xp, AggroRange: integer;
    Ai: string;
    Glyph: char;
    Boss: boolean;
    FleeAt: double;
    Loot: array of string;
    constructor Create;
  end;

  TItemSpec = class
  public
    Key: string;
    Name: string;
    Kind: string;
    Power, Value: integer;
    Glyph: char;
    constructor Create;
  end;

  TConfigSet = class
  private
    fMonsters: Dictionary<string, TMonsterSpec>;
    fItems: Dictionary<string, TItemSpec>;
    procedure AddMonster(spec: TMonsterSpec);
    procedure AddItem(spec: TItemSpec);
  public
    constructor Create;
    procedure LoadFile(path: string);
    procedure LoadDirectory(path: string);
    function MonsterKeys: array of string;
    function ItemKeys: array of string;
    function Monster(key: string): TMonsterSpec;
    function Item(key: string): TItemSpec;
    property Monsters: Dictionary<string, TMonsterSpec> read fMonsters;
    property Items: Dictionary<string, TItemSpec> read fItems;
  end;

  TLexer = class
  private
    fSource: string;
    fPos, fLine, fCol: integer;
    function Peek(offset: integer): char;
    procedure Advance;
    procedure Error(message: string);
    function ReadString(quote: char): string;
    function ReadNumber: TToken;
    function ReadIdent: TToken;
  public
    constructor Create(source: string);
    function Tokenize: array of TToken;
  end;

  TParser = class
  private
    fTokens: array of TToken;
    fPos: integer;
    function TokenAt(i: integer): TToken;
    function Current: TToken;
    procedure Advance;
    function Take(kind: TTokenKind): boolean;
    function Expect(kind: TTokenKind; what: string): TToken;
    function ExpectIdent: string;
    function LooksLikeLambda: boolean;
    function ParseLambda: TExpr;
    function ParseExpr: TExpr;
    function ParseOr: TExpr;
    function ParseAnd: TExpr;
    function ParseEquality: TExpr;
    function ParseComparison: TExpr;
    function ParseAdd: TExpr;
    function ParseMul: TExpr;
    function ParseUnary: TExpr;
    function ParsePostfix: TExpr;
    function ParsePrimary: TExpr;
    function ParseList: TExpr;
    function ParseObject: TExpr;
    function ParseIf: TExpr;
    function ParseCallArgs: List<TExpr>;
    function MakeBinary(op: string; left, right: TExpr; line, col: integer): TExpr;
    function ParseDecl: TAstNode;
  public
    constructor Create(tokens: array of TToken);
    function ParseProgram: TProgramNode;
  end;

  TAstPrinter = class(IAstVisitor)
  private
    fSb: StringBuilder;
    fIndent: integer;
    function Render(n: TAstNode): string;
    procedure WriteIndent;
  public
    constructor Create(indent: integer := 0);
    property Builder: StringBuilder read fSb;
    procedure VisitProgram(n: TProgramNode);
    procedure VisitLet(n: TLetNode);
    procedure VisitMonster(n: TMonsterNode);
    procedure VisitItem(n: TItemNode);
    procedure VisitInt(n: TIntLit);
    procedure VisitFloat(n: TFloatLit);
    procedure VisitString(n: TStringLit);
    procedure VisitBool(n: TBoolLit);
    procedure VisitIdent(n: TIdent);
    procedure VisitList(n: TListLit);
    procedure VisitObject(n: TObjectLit);
    procedure VisitBinary(n: TBinary);
    procedure VisitUnary(n: TUnary);
    procedure VisitLambda(n: TLambda);
    procedure VisitCall(n: TCall);
    procedure VisitField(n: TField);
    procedure VisitIf(n: TIfExpr);
  end;

function PrintAst(n: TAstNode): string;
function ParseSource(source: string): TProgramNode;

// --------------------------------------------------------------- JSON

type
  TJsonKind = (jkNull, jkBool, jkInt, jkFloat, jkString, jkArray, jkObject);

  TJsonValue = class
  public
    Kind: TJsonKind;
    BoolVal: boolean;
    IntVal: int64;
    FloatVal: double;
    StrVal: string;
    Arr: List<TJsonValue>;
    Obj: Dictionary<string, TJsonValue>;
    function AsInt: int64;
    function AsFloat: double;
    function AsString: string;
    function AsBool: boolean;
    function Item(name: string): TJsonValue;
    function Has(name: string): boolean;
    function Count: integer;
    procedure Add(v: TJsonValue);
    procedure Put(name: string; v: TJsonValue);
    function ToJson: string;
  end;

  TJsonParser = class
  private
    fText: string;
    fPos: integer;
    procedure SkipWs;
    function ParseValue: TJsonValue;
    function ParseString: string;
    function ParseNumber: TJsonValue;
    function ParseArray: TJsonValue;
    function ParseObject: TJsonValue;
    procedure Error(message: string);
  public
    constructor Create(text: string);
    function Parse: TJsonValue;
  end;

function JsonParse(text: string): TJsonValue;
function JNull: TJsonValue;
function JBool(v: boolean): TJsonValue;
function JInt(v: int64): TJsonValue;
function JFloat(v: double): TJsonValue;
function JStr(v: string): TJsonValue;
function JArray: TJsonValue;
function JObject: TJsonValue;

implementation

type
  TValueKind = (vkNull, vkInt, vkFloat, vkString, vkBool, vkList, vkObject,
    vkFunc, vkBuiltin);

  TObjectValue = class;
  TEnv = class;

  TValue = class
  public
    Kind: TValueKind;
    IntVal: int64;
    FloatVal: double;
    StrVal: string;
    BoolVal: boolean;
    ListVal: List<TValue>;
    ObjVal: TObjectValue;
    ParamNames: List<string>;
    Body: TExpr;
    Closure: TEnv;
    Applied: List<TValue>;
    BuiltinName: string;
    function AsInt: int64;
    function AsFloat: double;
    function AsString: string;
    function AsBool: boolean;
    function Truthy: boolean;
    function Display: string;
  end;

  TObjectValue = class
  public
    Fields: Dictionary<string, TValue>;
    constructor Create;
    function Get(name: string): TValue;
    procedure Put(name: string; value: TValue);
    function Has(name: string): boolean;
    function Clone: TObjectValue;
  end;

  TEnv = class
  private
    fValues: Dictionary<string, TValue>;
    fParent: TEnv;
  public
    constructor Create(parent: TEnv);
    procedure Define(name: string; value: TValue);
    function TryGet(name: string; var value: TValue): boolean;
    function Get(name: string): TValue;
  end;

  TEvaluator = class(IAstVisitor)
  private
    fGlobals: TEnv;
    fConfig: TConfigSet;
    fLast: TValue;
    fEnv: TEnv;
    fDepth: integer;
    function Eval(n: TExpr): TValue;
    function Apply(fn: TValue; args: List<TValue>): TValue;
    function CallBuiltin(name: string; args: List<TValue>): TValue;
    procedure DefineBuiltins;
    function ObjectToMonster(key: string; value: TValue): TMonsterSpec;
    function ObjectToItem(key: string; value: TValue): TItemSpec;
  public
    constructor Create(config: TConfigSet);
    procedure Run(prog: TProgramNode);
    procedure VisitProgram(n: TProgramNode);
    procedure VisitLet(n: TLetNode);
    procedure VisitMonster(n: TMonsterNode);
    procedure VisitItem(n: TItemNode);
    procedure VisitInt(n: TIntLit);
    procedure VisitFloat(n: TFloatLit);
    procedure VisitString(n: TStringLit);
    procedure VisitBool(n: TBoolLit);
    procedure VisitIdent(n: TIdent);
    procedure VisitList(n: TListLit);
    procedure VisitObject(n: TObjectLit);
    procedure VisitBinary(n: TBinary);
    procedure VisitUnary(n: TUnary);
    procedure VisitLambda(n: TLambda);
    procedure VisitCall(n: TCall);
    procedure VisitField(n: TField);
    procedure VisitIf(n: TIfExpr);
  end;

constructor EScriptError.Create(message: string; line, col: integer);
begin
  inherited Create($'{message} (строка {line}, колонка {col})');
  Self.Line := line;
  Self.Col := col;
end;

// ---------------------------------------------------------------- lexer

constructor TLexer.Create(source: string);
begin
  fSource := source;
  fPos := 1;
  fLine := 1;
  fCol := 1;
end;

function TLexer.Peek(offset: integer): char;
var
  p: integer;
begin
  p := fPos + offset;
  if (p >= 1) and (p <= fSource.Length) then
    Result := fSource[p]
  else
    Result := #0;
end;

procedure TLexer.Advance;
begin
  if fSource[fPos] = #10 then
  begin
    Inc(fLine);
    fCol := 1;
  end
  else
    Inc(fCol);
  Inc(fPos);
end;

procedure TLexer.Error(message: string);
begin
  raise new EScriptError(message, fLine, fCol);
end;

function TLexer.ReadString(quote: char): string;
var
  sb: StringBuilder;
  ch: char;
begin
  sb := new StringBuilder;
  Advance;
  while (fPos <= fSource.Length) and (fSource[fPos] <> quote) do
  begin
    ch := fSource[fPos];
    if ch = '\' then
    begin
      Advance;
      if fPos > fSource.Length then
        Error('Незакрытая строка');
      ch := fSource[fPos];
      case ch of
        'n': sb.Append(#10);
        't': sb.Append(#9);
        'r': sb.Append(#13);
        '\': sb.Append('\');
        '"': sb.Append('"');
        '''': sb.Append('''');
      else
        sb.Append(ch);
      end;
    end
    else
      sb.Append(ch);
    Advance;
  end;
  if (fPos > fSource.Length) or (fSource[fPos] <> quote) then
    Error('Незакрытая строка');
  Advance;
  Result := sb.ToString;
end;

function TLexer.ReadNumber: TToken;
var
  start: integer;
  isFloat: boolean;
  text: string;
begin
  start := fPos;
  isFloat := false;
  while (fPos <= fSource.Length) and Char.IsDigit(fSource[fPos]) do
    Advance;
  if (Peek(0) = '.') and Char.IsDigit(Peek(1)) then
  begin
    isFloat := true;
    Advance;
    while (fPos <= fSource.Length) and Char.IsDigit(fSource[fPos]) do
      Advance;
  end;
  if (Peek(0) = 'e') or (Peek(0) = 'E') then
  begin
    isFloat := true;
    Advance;
    if (Peek(0) = '+') or (Peek(0) = '-') then
      Advance;
    while (fPos <= fSource.Length) and Char.IsDigit(fSource[fPos]) do
      Advance;
  end;
  text := fSource.Substring(start - 1, fPos - start);
  Result := default(TToken);
  Result.Text := text;
  Result.Line := fLine;
  Result.Col := fCol - text.Length;
  if isFloat then
  begin
    Result.Kind := tkFloat;
    Result.FloatVal := double.Parse(text, CultureInfo.InvariantCulture);
  end
  else
  begin
    Result.Kind := tkInt;
    Result.IntVal := int64.Parse(text, CultureInfo.InvariantCulture);
  end;
end;

function TLexer.ReadIdent: TToken;
var
  start: integer;
  text: string;
begin
  start := fPos;
  while (fPos <= fSource.Length) and
        (Char.IsLetterOrDigit(fSource[fPos]) or (fSource[fPos] = '_')) do
    Advance;
  text := fSource.Substring(start - 1, fPos - start);
  Result := default(TToken);
  Result.Text := text;
  Result.Line := fLine;
  Result.Col := fCol - text.Length;
  case LowerCase(text) of
    'let': Result.Kind := tkLet;
    'monster': Result.Kind := tkMonster;
    'item': Result.Kind := tkItem;
    'true': Result.Kind := tkTrue;
    'false': Result.Kind := tkFalse;
    'and': Result.Kind := tkAnd;
    'or': Result.Kind := tkOr;
    'not': Result.Kind := tkNot;
    'if': Result.Kind := tkIf;
    'then': Result.Kind := tkThen;
    'else': Result.Kind := tkElse;
  else
    Result.Kind := tkIdent;
  end;
end;

function TLexer.Tokenize: array of TToken;
var
  tokens: List<TToken>;
  t: TToken;
  ch: char;
begin
  tokens := new List<TToken>;
  while fPos <= fSource.Length do
  begin
    ch := fSource[fPos];
    if Char.IsWhiteSpace(ch) then
    begin
      Advance;
      Continue;
    end;
    if ch = '#' then
    begin
      while (fPos <= fSource.Length) and (fSource[fPos] <> #10) do
        Advance;
      Continue;
    end;
    if (ch = '/') and (Peek(1) = '/') then
    begin
      Advance; Advance;
      while (fPos <= fSource.Length) and (fSource[fPos] <> #10) do
        Advance;
      Continue;
    end;
    if Char.IsDigit(ch) then
    begin
      tokens.Add(ReadNumber);
      Continue;
    end;
    if Char.IsLetter(ch) or (ch = '_') then
    begin
      tokens.Add(ReadIdent);
      Continue;
    end;
    t := default(TToken);
    t.Line := fLine;
    t.Col := fCol;
    if (ch = '''') or (ch = '"') then
    begin
      t.Kind := tkString;
      t.Text := ReadString(ch);
      tokens.Add(t);
      Continue;
    end;
    case ch of
      '{': begin t.Kind := tkLBrace; Advance; end;
      '}': begin t.Kind := tkRBrace; Advance; end;
      '[': begin t.Kind := tkLBracket; Advance; end;
      ']': begin t.Kind := tkRBracket; Advance; end;
      '(': begin t.Kind := tkLParen; Advance; end;
      ')': begin t.Kind := tkRParen; Advance; end;
      ':': begin t.Kind := tkColon; Advance; end;
      ';': begin t.Kind := tkSemicolon; Advance; end;
      ',': begin t.Kind := tkComma; Advance; end;
      '+': begin t.Kind := tkPlus; Advance; end;
      '-':
        begin
          Advance;
          if Peek(0) = '>' then
          begin
            Advance;
            t.Kind := tkArrow;
          end
          else
            t.Kind := tkMinus;
        end;
      '*': begin t.Kind := tkStar; Advance; end;
      '/': begin t.Kind := tkSlash; Advance; end;
      '.':
        begin
          t.Kind := tkDot;
          Advance;
        end;
      '=':
        begin
          t.Kind := tkEq;
          Advance;
        end;
      '!':
        begin
          Advance;
          if Peek(0) = '=' then
          begin
            Advance;
            t.Kind := tkNe;
          end
          else
            Error('Ожидалось !=');
        end;
      '<':
        begin
          Advance;
          if Peek(0) = '=' then
          begin
            Advance;
            t.Kind := tkLe;
          end
          else
            t.Kind := tkLt;
        end;
      '>':
        begin
          Advance;
          if Peek(0) = '=' then
          begin
            Advance;
            t.Kind := tkGe;
          end
          else
            t.Kind := tkGt;
        end;
    else
      Error($'Неизвестный символ "{ch}"');
    end;
    tokens.Add(t);
  end;
  t := default(TToken);
  t.Kind := tkEof;
  t.Line := fLine;
  t.Col := fCol;
  tokens.Add(t);
  Result := tokens.ToArray;
end;

// ---------------------------------------------------------------- nodes

constructor TProgramNode.Create;
begin
  Decls := new List<TAstNode>;
end;

procedure TProgramNode.Accept(v: IAstVisitor); begin v.VisitProgram(Self); end;
procedure TLetNode.Accept(v: IAstVisitor); begin v.VisitLet(Self); end;
procedure TMonsterNode.Accept(v: IAstVisitor); begin v.VisitMonster(Self); end;
procedure TItemNode.Accept(v: IAstVisitor); begin v.VisitItem(Self); end;
procedure TIntLit.Accept(v: IAstVisitor); begin v.VisitInt(Self); end;
procedure TFloatLit.Accept(v: IAstVisitor); begin v.VisitFloat(Self); end;
procedure TStringLit.Accept(v: IAstVisitor); begin v.VisitString(Self); end;
procedure TBoolLit.Accept(v: IAstVisitor); begin v.VisitBool(Self); end;
procedure TIdent.Accept(v: IAstVisitor); begin v.VisitIdent(Self); end;

constructor TListLit.Create;
begin
  Entries := new List<TListEntry>;
end;

procedure TListLit.Accept(v: IAstVisitor); begin v.VisitList(Self); end;

constructor TObjectLit.Create;
begin
  Fields := new List<TObjField>;
end;

procedure TObjectLit.Accept(v: IAstVisitor); begin v.VisitObject(Self); end;
procedure TBinary.Accept(v: IAstVisitor); begin v.VisitBinary(Self); end;
procedure TUnary.Accept(v: IAstVisitor); begin v.VisitUnary(Self); end;

constructor TLambda.Create;
begin
  ParamNames := new List<string>;
end;

procedure TLambda.Accept(v: IAstVisitor); begin v.VisitLambda(Self); end;

constructor TCall.Create;
begin
  Args := new List<TExpr>;
end;

procedure TCall.Accept(v: IAstVisitor); begin v.VisitCall(Self); end;
procedure TField.Accept(v: IAstVisitor); begin v.VisitField(Self); end;
procedure TIfExpr.Accept(v: IAstVisitor); begin v.VisitIf(Self); end;

// ---------------------------------------------------------------- parser

constructor TParser.Create(tokens: array of TToken);
begin
  fTokens := tokens;
  fPos := 0;
end;

function TParser.TokenAt(i: integer): TToken;
begin
  if (i >= 0) and (i < fTokens.Length) then
    Result := fTokens[i]
  else
  begin
    Result := default(TToken);
    Result.Kind := tkEof;
  end;
end;

function TParser.Current: TToken;
begin
  Result := TokenAt(fPos);
end;

procedure TParser.Advance;
begin
  if fPos < fTokens.Length - 1 then
    Inc(fPos);
end;

function TParser.Take(kind: TTokenKind): boolean;
begin
  if Current.Kind = kind then
  begin
    Advance;
    Exit(true);
  end;
  Result := false;
end;

function TParser.Expect(kind: TTokenKind; what: string): TToken;
begin
  if Current.Kind <> kind then
    raise new EScriptError($'Ожидалось {what}, а встречено "{Current.Text}"',
      Current.Line, Current.Col);
  Result := Current;
  Advance;
end;

function TParser.ExpectIdent: string;
var
  t: TToken;
begin
  if (Current.Kind <> tkIdent) and (Current.Kind <> tkMonster) and
     (Current.Kind <> tkItem) and (Current.Kind <> tkLet) then
    raise new EScriptError($'Ожидался идентификатор, а встречено "{Current.Text}"',
      Current.Line, Current.Col);
  t := Current;
  Advance;
  Result := t.Text;
end;

function TParser.LooksLikeLambda: boolean;
var
  i: integer;
begin
  Result := false;
  if Current.Kind = tkIdent then
    Exit(TokenAt(fPos + 1).Kind = tkArrow);
  if Current.Kind <> tkLParen then
    Exit(false);
  i := fPos + 1;
  if (TokenAt(i).Kind = tkRParen) and (TokenAt(i + 1).Kind = tkArrow) then
    Exit(true);
  if TokenAt(i).Kind <> tkIdent then
    Exit(false);
  Inc(i);
  while (TokenAt(i).Kind = tkComma) and (TokenAt(i + 1).Kind = tkIdent) do
    Inc(i, 2);
  Result := (TokenAt(i).Kind = tkRParen) and (TokenAt(i + 1).Kind = tkArrow);
end;

function TParser.ParseLambda: TExpr;
var
  lam: TLambda;
begin
  lam := new TLambda;
  lam.Line := Current.Line;
  lam.Col := Current.Col;
  if Current.Kind = tkIdent then
  begin
    lam.ParamNames.Add(ExpectIdent);
    Expect(tkArrow, '->');
  end
  else
  begin
    Expect(tkLParen, '(');
    if Current.Kind <> tkRParen then
    begin
      lam.ParamNames.Add(ExpectIdent);
      while Take(tkComma) do
        lam.ParamNames.Add(ExpectIdent);
    end;
    Expect(tkRParen, ')');
    Expect(tkArrow, '->');
  end;
  lam.Body := ParseExpr;
  Result := lam;
end;

function TParser.MakeBinary(op: string; left, right: TExpr; line, col: integer): TExpr;
var
  b: TBinary;
begin
  b := new TBinary;
  b.Op := op;
  b.Left := left;
  b.Right := right;
  b.Line := line;
  b.Col := col;
  Result := b;
end;

function TParser.ParseExpr: TExpr;
begin
  Result := ParseOr;
end;

function TParser.ParseOr: TExpr;
var
  t: TToken;
begin
  Result := ParseAnd;
  while Current.Kind = tkOr do
  begin
    t := Current;
    Advance;
    Result := MakeBinary('or', Result, ParseAnd, t.Line, t.Col);
  end;
end;

function TParser.ParseAnd: TExpr;
var
  t: TToken;
begin
  Result := ParseEquality;
  while Current.Kind = tkAnd do
  begin
    t := Current;
    Advance;
    Result := MakeBinary('and', Result, ParseEquality, t.Line, t.Col);
  end;
end;

function TParser.ParseEquality: TExpr;
var
  t: TToken;
  op: string;
begin
  Result := ParseComparison;
  while (Current.Kind = tkEq) or (Current.Kind = tkNe) do
  begin
    t := Current;
    if t.Kind = tkEq then op := '=' else op := '!=';
    Advance;
    Result := MakeBinary(op, Result, ParseComparison, t.Line, t.Col);
  end;
end;

function TParser.ParseComparison: TExpr;
var
  t: TToken;
  op: string;
begin
  Result := ParseAdd;
  while (Current.Kind = tkLt) or (Current.Kind = tkLe) or
        (Current.Kind = tkGt) or (Current.Kind = tkGe) do
  begin
    t := Current;
    case t.Kind of
      tkLt: op := '<';
      tkLe: op := '<=';
      tkGt: op := '>';
      tkGe: op := '>=';
    end;
    Advance;
    Result := MakeBinary(op, Result, ParseAdd, t.Line, t.Col);
  end;
end;

function TParser.ParseAdd: TExpr;
var
  t: TToken;
  op: string;
begin
  Result := ParseMul;
  while (Current.Kind = tkPlus) or (Current.Kind = tkMinus) do
  begin
    t := Current;
    if t.Kind = tkPlus then op := '+' else op := '-';
    Advance;
    Result := MakeBinary(op, Result, ParseMul, t.Line, t.Col);
  end;
end;

function TParser.ParseMul: TExpr;
var
  t: TToken;
  op: string;
begin
  Result := ParseUnary;
  while (Current.Kind = tkStar) or (Current.Kind = tkSlash) do
  begin
    t := Current;
    if t.Kind = tkStar then op := '*' else op := '/';
    Advance;
    Result := MakeBinary(op, Result, ParseUnary, t.Line, t.Col);
  end;
end;

function TParser.ParseUnary: TExpr;
var
  t: TToken;
  u: TUnary;
begin
  if (Current.Kind = tkMinus) or (Current.Kind = tkNot) then
  begin
    t := Current;
    Advance;
    u := new TUnary;
    if t.Kind = tkMinus then u.Op := '-' else u.Op := 'not';
    u.Operand := ParseUnary;
    u.Line := t.Line;
    u.Col := t.Col;
    Exit(u);
  end;
  Result := ParsePostfix;
end;

function TParser.ParsePostfix: TExpr;
var
  call: TCall;
  field: TField;
  t: TToken;
begin
  Result := ParsePrimary;
  while true do
  begin
    if Current.Kind = tkLParen then
    begin
      t := Current;
      call := new TCall;
      call.Callee := Result;
      call.Args := ParseCallArgs;
      call.Line := t.Line;
      call.Col := t.Col;
      Result := call;
    end
    else if Current.Kind = tkDot then
    begin
      t := Current;
      Advance;
      field := new TField;
      field.Base := Result;
      field.FieldName := ExpectIdent;
      field.Line := t.Line;
      field.Col := t.Col;
      Result := field;
    end
    else
      Break;
  end;
end;

function TParser.ParseCallArgs: List<TExpr>;
begin
  Result := new List<TExpr>;
  Expect(tkLParen, '(');
  if Current.Kind <> tkRParen then
  begin
    Result.Add(ParseExpr);
    while Take(tkComma) do
      Result.Add(ParseExpr);
  end;
  Expect(tkRParen, ')');
end;

function TParser.ParsePrimary: TExpr;
var
  t: TToken;
  n: TIntLit;
  f: TFloatLit;
  s: TStringLit;
  b: TBoolLit;
  id: TIdent;
begin
  t := Current;
  case t.Kind of
    tkInt:
      begin
        Advance;
        n := new TIntLit;
        n.Value := t.IntVal;
        n.Line := t.Line;
        n.Col := t.Col;
        Exit(n);
      end;
    tkFloat:
      begin
        Advance;
        f := new TFloatLit;
        f.Value := t.FloatVal;
        f.Line := t.Line;
        f.Col := t.Col;
        Exit(f);
      end;
    tkString:
      begin
        Advance;
        s := new TStringLit;
        s.Value := t.Text;
        s.Line := t.Line;
        s.Col := t.Col;
        Exit(s);
      end;
    tkTrue, tkFalse:
      begin
        Advance;
        b := new TBoolLit;
        b.Value := t.Kind = tkTrue;
        b.Line := t.Line;
        b.Col := t.Col;
        Exit(b);
      end;
    tkIdent:
      begin
        if LooksLikeLambda then
          Exit(ParseLambda);
        Advance;
        id := new TIdent;
        id.Name := t.Text;
        id.Line := t.Line;
        id.Col := t.Col;
        Exit(id);
      end;
    tkLParen:
      begin
        if LooksLikeLambda then
          Exit(ParseLambda);
        Advance;
        Result := ParseExpr;
        Expect(tkRParen, ')');
        Exit;
      end;
    tkLBracket:
      Exit(ParseList);
    tkLBrace:
      Exit(ParseObject);
    tkIf:
      Exit(ParseIf);
  else
    raise new EScriptError($'Неожиданный токен "{t.Text}"', t.Line, t.Col);
  end;
end;

function TParser.ParseList: TExpr;
var
  lst: TListLit;
  entry: TListEntry;
  count: integer;
  mult, digits: string;
  allDigits: boolean;
  j: integer;
begin
  lst := new TListLit;
  lst.Line := Current.Line;
  lst.Col := Current.Col;
  Expect(tkLBracket, '[');
  if Current.Kind <> tkRBracket then
  begin
    while true do
    begin
      entry.Value := ParseExpr;
      entry.Count := 1;
      if Current.Kind = tkIdent then
      begin
        mult := LowerCase(Current.Text);
        if (mult.Length > 1) and (mult[1] = 'x') then
        begin
          digits := Copy(mult, 2, mult.Length - 1);
          allDigits := true;
          for j := 1 to digits.Length do
            if not Char.IsDigit(digits[j]) then
              allDigits := false;
          if allDigits then
          begin
            count := integer(int64.Parse(digits, CultureInfo.InvariantCulture));
            entry.Count := Max(1, count);
            Advance;
          end;
        end
        else if (mult = 'x') and (TokenAt(fPos + 1).Kind = tkInt) then
        begin
          Advance;
          count := integer(Expect(tkInt, 'число после x').IntVal);
          entry.Count := Max(1, count);
        end;
      end;
      lst.Entries.Add(entry);
      if not Take(tkComma) then
        Break;
    end;
  end;
  Expect(tkRBracket, ']');
  Result := lst;
end;

function TParser.ParseObject: TExpr;
var
  obj: TObjectLit;
  fld: TObjField;
begin
  obj := new TObjectLit;
  obj.Line := Current.Line;
  obj.Col := Current.Col;
  Expect(tkLBrace, '{');
  while Current.Kind <> tkRBrace do
  begin
    fld.Name := ExpectIdent;
    Expect(tkColon, ':');
    fld.Value := ParseExpr;
    obj.Fields.Add(fld);
    if not (Take(tkSemicolon) or Take(tkComma)) then
      Break;
  end;
  Expect(tkRBrace, '}');
  Result := obj;
end;

function TParser.ParseIf: TExpr;
var
  e: TIfExpr;
begin
  e := new TIfExpr;
  e.Line := Current.Line;
  e.Col := Current.Col;
  Expect(tkIf, 'if');
  e.Cond := ParseExpr;
  Expect(tkThen, 'then');
  e.ThenExpr := ParseExpr;
  Expect(tkElse, 'else');
  e.ElseExpr := ParseExpr;
  Result := e;
end;

function TParser.ParseDecl: TAstNode;
var
  t: TToken;
  letNode: TLetNode;
  mon: TMonsterNode;
  it: TItemNode;
begin
  t := Current;
  case t.Kind of
    tkLet:
      begin
        Advance;
        letNode := new TLetNode;
        letNode.Name := ExpectIdent;
        Expect(tkEq, '=');
        letNode.Value := ParseExpr;
        Take(tkSemicolon);
        letNode.Line := t.Line;
        letNode.Col := t.Col;
        Exit(letNode);
      end;
    tkMonster:
      begin
        Advance;
        mon := new TMonsterNode;
        mon.Name := ExpectIdent;
        if Current.Kind = tkLBrace then
          mon.Body := ParseObject
        else
        begin
          Expect(tkEq, '=');
          mon.Body := ParseExpr;
        end;
        Take(tkSemicolon);
        mon.Line := t.Line;
        mon.Col := t.Col;
        Exit(mon);
      end;
    tkItem:
      begin
        Advance;
        it := new TItemNode;
        it.Name := ExpectIdent;
        if Current.Kind = tkLBrace then
          it.Body := ParseObject
        else
        begin
          Expect(tkEq, '=');
          it.Body := ParseExpr;
        end;
        Take(tkSemicolon);
        it.Line := t.Line;
        it.Col := t.Col;
        Exit(it);
      end;
  else
    raise new EScriptError($'Ожидалось объявление, а встречено "{t.Text}"',
      t.Line, t.Col);
  end;
end;

function TParser.ParseProgram: TProgramNode;
begin
  Result := new TProgramNode;
  while Current.Kind <> tkEof do
    Result.Decls.Add(ParseDecl);
end;

function ParseSource(source: string): TProgramNode;
var
  lexer: TLexer;
  parser: TParser;
begin
  lexer := new TLexer(source);
  parser := new TParser(lexer.Tokenize);
  Result := parser.ParseProgram;
end;

// --------------------------------------------------------------- printer

constructor TAstPrinter.Create(indent: integer);
begin
  fSb := new StringBuilder;
  fIndent := indent;
end;

procedure TAstPrinter.WriteIndent;
begin
  fSb.Append(RepeatText('  ', fIndent));
end;

function TAstPrinter.Render(n: TAstNode): string;
var
  sub: TAstPrinter;
begin
  sub := new TAstPrinter(fIndent);
  n.Accept(sub);
  Result := sub.Builder.ToString;
end;

procedure TAstPrinter.VisitProgram(n: TProgramNode);
var
  d: TAstNode;
begin
  foreach d in n.Decls do
  begin
    d.Accept(Self);
    fSb.AppendLine;
  end;
end;

procedure TAstPrinter.VisitLet(n: TLetNode);
begin
  WriteIndent;
  fSb.Append($'let {n.Name} = {Render(n.Value)};');
end;

procedure TAstPrinter.VisitMonster(n: TMonsterNode);
begin
  WriteIndent;
  fSb.Append($'monster {n.Name} = {Render(n.Body)};');
end;

procedure TAstPrinter.VisitItem(n: TItemNode);
begin
  WriteIndent;
  fSb.Append($'item {n.Name} = {Render(n.Body)};');
end;

procedure TAstPrinter.VisitInt(n: TIntLit);
begin
  fSb.Append(n.Value.ToString(CultureInfo.InvariantCulture));
end;

procedure TAstPrinter.VisitFloat(n: TFloatLit);
begin
  fSb.Append(n.Value.ToString('R', CultureInfo.InvariantCulture));
end;

procedure TAstPrinter.VisitString(n: TStringLit);
var
  i: integer;
  ch: char;
begin
  fSb.Append('"');
  for i := 1 to n.Value.Length do
  begin
    ch := n.Value[i];
    case ch of
      '"': fSb.Append('\"');
      '\': fSb.Append('\\');
      #10: fSb.Append('\n');
      #13: fSb.Append('\r');
      #9: fSb.Append('\t');
    else
      fSb.Append(ch);
    end;
  end;
  fSb.Append('"');
end;

procedure TAstPrinter.VisitBool(n: TBoolLit);
begin
  if n.Value then fSb.Append('true') else fSb.Append('false');
end;

procedure TAstPrinter.VisitIdent(n: TIdent);
begin
  fSb.Append(n.Name);
end;

procedure TAstPrinter.VisitList(n: TListLit);
var
  i: integer;
  e: TListEntry;
begin
  fSb.Append('[');
  for i := 0 to n.Entries.Count - 1 do
  begin
    if i > 0 then fSb.Append(', ');
    e := n.Entries[i];
    fSb.Append(Render(e.Value));
    if e.Count > 1 then
      fSb.Append($' x{e.Count}');
  end;
  fSb.Append(']');
end;

procedure TAstPrinter.VisitObject(n: TObjectLit);
var
  i: integer;
  fld: TObjField;
begin
  if n.Fields.Count = 0 then
  begin
    fSb.Append('{}');
    Exit;
  end;
  fSb.AppendLine('{');
  Inc(fIndent);
  for i := 0 to n.Fields.Count - 1 do
  begin
    WriteIndent;
    fld := n.Fields[i];
    fSb.Append($'{fld.Name}: {Render(fld.Value)};');
    fSb.AppendLine;
  end;
  Dec(fIndent);
  WriteIndent;
  fSb.Append('}');
end;

procedure TAstPrinter.VisitBinary(n: TBinary);
begin
  fSb.Append($'({Render(n.Left)} {n.Op} {Render(n.Right)})');
end;

procedure TAstPrinter.VisitUnary(n: TUnary);
begin
  fSb.Append($'({n.Op} {Render(n.Operand)})');
end;

procedure TAstPrinter.VisitLambda(n: TLambda);
var
  i: integer;
begin
  fSb.Append('(');
  for i := 0 to n.ParamNames.Count - 1 do
  begin
    if i > 0 then fSb.Append(', ');
    fSb.Append(n.ParamNames[i]);
  end;
  fSb.Append($') -> {Render(n.Body)}');
end;

procedure TAstPrinter.VisitCall(n: TCall);
var
  i: integer;
begin
  fSb.Append($'{Render(n.Callee)}(');
  for i := 0 to n.Args.Count - 1 do
  begin
    if i > 0 then fSb.Append(', ');
    fSb.Append(Render(n.Args[i]));
  end;
  fSb.Append(')');
end;

procedure TAstPrinter.VisitField(n: TField);
begin
  fSb.Append($'{Render(n.Base)}.{n.FieldName}');
end;

procedure TAstPrinter.VisitIf(n: TIfExpr);
begin
  fSb.Append($'if {Render(n.Cond)} then {Render(n.ThenExpr)} else {Render(n.ElseExpr)}');
end;

function PrintAst(n: TAstNode): string;
var
  p: TAstPrinter;
begin
  p := new TAstPrinter;
  n.Accept(p);
  Result := p.Builder.ToString;
end;

{$include lib_script_impl.inc}

end.
