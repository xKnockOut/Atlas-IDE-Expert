unit Atlas.Common.Editing.ConditionalExpression;

// if-Anweisung und Bedingungsausdruck (Delphi 13: X := if C then A else B)
// ineinander umwandeln (#684):
//   In bedingten Ausdruck umwandeln: auf einem if mit else, dessen Zweige je
//     eine Anweisung derselben Form haben: Zuweisung an dasselbe Ziel,
//     Exit(A)/Exit(B) oder derselbe Aufruf mit genau einem anderen Argument
//     (ohne Seiteneffekte). else-if-Ketten werden verschachtelte Ausdrücke,
//     ab drei Bedingungen nicht mehr (dafür gibt es case, #646). Die Typen
//     der Werte müssen sicher bekannt und verträglich sein.
//   In if-Anweisung umwandeln: auf einem Bedingungsausdruck in einer
//     Zuweisung, einem Aufruf (auch Exit) oder einer Inline-Variablen mit
//     Typ. Die Anweisung wird je Zweig wiederholt; verschachtelte Ausdrücke
//     werden else if bzw. ein inneres if in begin … end. Der Rest der
//     Anweisung darf keine Seiteneffekte haben (er liefe sonst nach der
//     Bedingung statt davor).
//   IfThen durch bedingten Ausdruck ersetzen: IfThen aus System.Math bzw.
//     System.StrUtils wertet beide Zweige aus, der Ausdruck nur einen.
// Kommentare im umgeschriebenen Bereich verhindern die Aktion. Typen und die
// Herkunft von IfThen liefert der Aufrufer (TConditionalLookup).

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.StatementText;

type
  /// <summary>Grobe Art eines Werts für die Verträglichkeit der Zweige.</summary>
  TValueKind = (Unknown, Whole, Float, Text, Logical, NilValue, Named);

  TValueType = record
    Kind: TValueKind;
    /// <summary>Typname bei Named.</summary>
    Name: string;
    class function Create(AKind: TValueKind; const AName: string): TValueType; static;
  end;

  /// <summary>Typ des Ausdrucks ANode über die Namensauflösung; Unknown, wenn nicht sicher bekannt.</summary>
  TValueTypeFunc = reference to function(ANode: TSyntaxNode): TValueType;
  /// <summary>Ist der Aufruf ACall das IfThen aus System.Math bzw. System.StrUtils? ADefault: Wert des dritten
  /// Arguments, wenn es fehlt ('0' bzw. '''').</summary>
  TIfThenFunc = reference to function(ACall: TSyntaxNode; out ADefault: string): Boolean;

  TConditionalLookup = record
    ValueType: TValueTypeFunc;
    IfThen: TIfThenFunc;
    /// <summary>Typen und IfThen über AResolver für den Baum ATree der Datei AFileName (Baum festhalten, etwa mit
    /// PinTree, solange die Funktionen gebraucht werden).</summary>
    class function FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName: string): TConditionalLookup; static;
    /// <summary>Art eines aufgelösten Typs.</summary>
    class function KindOfType(const AType: TResolvedSymbol): TValueType; static;
  end;

  TConditionalExpression = class
  public const
    /// <summary>Höchstens so viele Bedingungen werden zum Ausdruck.</summary>
    cMaxConditions = 2;
  public
    class function ToExpressionTitle: string; static;
    class function ToStatementTitle: string; static;
    class function IfThenTitle: string; static;
    /// <summary>„In bedingten Ausdruck umwandeln“ für das if, dessen Kopf APosition enthält.</summary>
    class function ToExpression(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TConditionalLookup; out ARewrite: TStatementRewrite): Boolean; static;
    /// <summary>„In if-Anweisung umwandeln“ für den äußersten Bedingungsausdruck an APosition.</summary>
    class function ToStatement(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean; overload; static;
    /// <summary>Dasselbe für den Bedingungsausdruck AExpression.</summary>
    class function ToStatement(const AText: string; ATree: TSyntaxTree; AExpression: TSyntaxNode;
      const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean; overload; static;
    /// <summary>„IfThen durch bedingten Ausdruck ersetzen“ für den innersten IfThen-Aufruf an APosition.</summary>
    class function ReplaceIfThen(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TConditionalLookup; out ARewrite: TStatementRewrite): Boolean; static;
    /// <summary>Lassen sich Werte der Typen A und B in einem Bedingungsausdruck verbinden?</summary>
    class function Compatible(const A, B: TValueType): Boolean; static;
    /// <summary>Äußerster Bedingungsausdruck, der ANode enthält (ANode selbst eingeschlossen); nil ohne.</summary>
    class function Outermost(ANode: TSyntaxNode): TSyntaxNode; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.PureRoutines,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.ExpressionText,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TConditionalExpressionText = (ConvertToConditionalExpression, ConvertToIfStatement, ReplaceIfThenWithAConditional);

const
  cTexts: array[TConditionalExpressionText] of TAtlasText = (
    (De: 'In bedingten Ausdruck umwandeln'; En: 'Convert to conditional expression'),
    (De: 'In if-Anweisung umwandeln'; En: 'Convert to if statement'),
    (De: 'IfThen durch bedingten Ausdruck ersetzen'; En: 'Replace IfThen with a conditional expression'));

class function TConditionalExpression.ToExpressionTitle: string;
begin
  Result := cTexts[TConditionalExpressionText.ConvertToConditionalExpression].Text;
end;

class function TConditionalExpression.ToStatementTitle: string;
begin
  Result := cTexts[TConditionalExpressionText.ConvertToIfStatement].Text;
end;

class function TConditionalExpression.IfThenTitle: string;
begin
  Result := cTexts[TConditionalExpressionText.ReplaceIfThenWithAConditional].Text;
end;

{ TValueType }

class function TValueType.Create(AKind: TValueKind; const AName: string): TValueType;
begin
  Result.Kind := AKind;
  Result.Name := AName;
end;

{ TConditionalLookup }

/// <summary>Art eines eingebauten Typs aus System; Unknown bei anderen.</summary>
function BuiltinKind(const AName: string): TValueKind;
begin
  if MatchText(AName, ['Integer', 'Cardinal', 'ShortInt', 'SmallInt', 'Word', 'Byte', 'LongInt', 'LongWord',
    'Int8', 'Int16', 'Int32', 'Int64', 'UInt8', 'UInt16', 'UInt32', 'UInt64', 'NativeInt', 'NativeUInt',
    'FixedInt', 'FixedUInt']) then
  begin
    Result := TValueKind.Whole;
  end
  else if MatchText(AName, ['Single', 'Double', 'Extended', 'Real', 'Currency', 'Comp']) then
  begin
    Result := TValueKind.Float;
  end
  else if MatchText(AName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString', 'Char',
    'WideChar', 'AnsiChar', 'RawByteString', 'UTF8String']) then
  begin
    Result := TValueKind.Text;
  end
  else if SameText(AName, 'Boolean') then
  begin
    Result := TValueKind.Logical;
  end
  else
  begin
    Result := TValueKind.Unknown;
  end;
end;

class function TConditionalLookup.KindOfType(const AType: TResolvedSymbol): TValueType;
var
  mKind: TValueKind;
begin
  Result := TValueType.Create(TValueKind.Unknown, '');
  if not AType.Found then
  begin
    Exit;
  end;
  mKind := TValueKind.Unknown;
  if AType.Builtin or SameText(AType.UnitName, 'System') then
  begin
    mKind := BuiltinKind(AType.Name);
  end;
  if mKind <> TValueKind.Unknown then
  begin
    Result := TValueType.Create(mKind, '');
  end
  else
  begin
    Result := TValueType.Create(TValueKind.Named, AType.Name);
  end;
end;

class function TConditionalLookup.FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TConditionalLookup;
var
  mFileName: string;
begin
  mFileName := AFileName;
  Result.ValueType :=
    function(ANode: TSyntaxNode): TValueType
    var
      Symbol, TypeInfo: TResolvedSymbol;
      TypeFound: Boolean;
    begin
      Result := TValueType.Create(TValueKind.Unknown, '');
      if not (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
        TSyntaxKind.Call]) or not AResolver.NodeType(ATree, mFileName, ANode, Symbol, TypeInfo, TypeFound) then
      begin
        Exit;
      end;
      if TypeFound then
      begin
        Result := KindOfType(TypeInfo);
      end
      // Ein Aufzählungswert hat den Typ seiner Aufzählung.
      else if (Symbol.SymbolKind = TIndexSymbolKind.EnumMember) and (Symbol.Container <> '') then
      begin
        Result := TValueType.Create(TValueKind.Named, Symbol.Container);
      end;
    end;
  Result.IfThen :=
    function(ACall: TSyntaxNode; out ADefault: string): Boolean
    var
      Symbol, TypeInfo: TResolvedSymbol;
      TypeFound: Boolean;
    begin
      ADefault := '';
      Result := (ACall.ChildCount > 0) and AResolver.NodeType(ATree, mFileName, ACall[0], Symbol, TypeInfo,
        TypeFound) and MatchText(Symbol.UnitName, ['System.Math', 'System.StrUtils', 'Math', 'StrUtils']);
      if Result then
      begin
        if EndsText('StrUtils', Symbol.UnitName) then
        begin
          ADefault := '''''';
        end
        else
        begin
          ADefault := '0';
        end;
      end;
    end;
end;

{ Hilfen }

function ValueKindOf(const AText: string; ANode: TSyntaxNode; const ALookup: TConditionalLookup): TValueType;
  forward;

function KindValue(AKind: TValueKind): TValueType;
begin
  Result := TValueType.Create(AKind, '');
end;

/// <summary>Art eines Literals nach seinem ersten Zeichen.</summary>
function LiteralKind(const AText: string; ANode: TSyntaxNode): TValueType;
var
  mSource: string;
begin
  Result := KindValue(TValueKind.Unknown);
  mSource := TExpressionText.Source(AText, ANode);
  if mSource = '' then
  begin
    Exit;
  end;
  if CharInSet(mSource[1], ['''', '#']) then
  begin
    Result := KindValue(TValueKind.Text);
  end
  else if CharInSet(mSource[1], ['$', '%', '&']) then
  begin
    Result := KindValue(TValueKind.Whole);
  end
  else if CharInSet(mSource[1], ['0'..'9']) then
  begin
    if (Pos('.', mSource) > 0) or (Pos('e', LowerCase(mSource)) > 0) then
    begin
      Result := KindValue(TValueKind.Float);
    end
    else
    begin
      Result := KindValue(TValueKind.Whole);
    end;
  end
  else if TExpressionText.IsBooleanLiteral(ANode) then
  begin
    Result := KindValue(TValueKind.Logical);
  end
  else if SameText(mSource, 'nil') then
  begin
    Result := KindValue(TValueKind.NilValue);
  end;
end;

/// <summary>Typ über ALookup; Unknown ohne.</summary>
function LookupKind(ANode: TSyntaxNode; const ALookup: TConditionalLookup): TValueType;
begin
  Result := KindValue(TValueKind.Unknown);
  if Assigned(ALookup.ValueType) then
  begin
    Result := ALookup.ValueType(ANode);
  end;
end;

function IdentifierKind(ANode: TSyntaxNode; const ALookup: TConditionalLookup): TValueType;
begin
  if TExpressionText.IsBooleanLiteral(ANode) then
  begin
    Result := KindValue(TValueKind.Logical);
  end
  else if SameText(ANode.Name, 'nil') then
  begin
    Result := KindValue(TValueKind.NilValue);
  end
  else
  begin
    Result := LookupKind(ANode, ALookup);
  end;
end;

function UnaryKind(const AText: string; ANode: TSyntaxNode; const ALookup: TConditionalLookup): TValueType;
begin
  Result := KindValue(TValueKind.Unknown);
  if SameText(ANode.Name, 'not') then
  begin
    Result := KindValue(TValueKind.Logical);
  end
  else if (ANode.ChildCount = 1) and MatchStr(ANode.Name, ['-', '+']) then
  begin
    Result := ValueKindOf(AText, ANode[0], ALookup);
  end;
end;

function SameKind(const ALeft, ARight: TValueType; AKind: TValueKind): Boolean;
begin
  Result := (ALeft.Kind = AKind) and (ARight.Kind = AKind);
end;

function BothNumbers(const ALeft, ARight: TValueType): Boolean;
begin
  Result := (ALeft.Kind in [TValueKind.Whole, TValueKind.Float]) and
    (ARight.Kind in [TValueKind.Whole, TValueKind.Float]);
end;

/// <summary>Ergebnis eines zweistelligen Operators AOp (klein geschrieben, nicht relational).</summary>
function OperatorKind(const AOp: string; const ALeft, ARight: TValueType): TValueType;
begin
  Result := KindValue(TValueKind.Unknown);
  if MatchStr(AOp, ['and', 'or', 'xor']) and SameKind(ALeft, ARight, TValueKind.Logical) then
  begin
    Result := ALeft;
  end
  else if MatchStr(AOp, ['div', 'mod', 'shl', 'shr']) and SameKind(ALeft, ARight, TValueKind.Whole) then
  begin
    Result := ALeft;
  end
  else if (AOp = '/') and BothNumbers(ALeft, ARight) then
  begin
    Result := KindValue(TValueKind.Float);
  end
  else if MatchStr(AOp, ['+', '-', '*']) and BothNumbers(ALeft, ARight) then
  begin
    Result := ALeft;
    if (ALeft.Kind = TValueKind.Float) or (ARight.Kind = TValueKind.Float) then
    begin
      Result := KindValue(TValueKind.Float);
    end;
  end
  else if (AOp = '+') and SameKind(ALeft, ARight, TValueKind.Text) then
  begin
    Result := ALeft;
  end;
end;

function BinaryKind(const AText: string; ANode: TSyntaxNode; const ALookup: TConditionalLookup): TValueType;
var
  mOp: string;
begin
  Result := KindValue(TValueKind.Unknown);
  if ANode.ChildCount <> 2 then
  begin
    Exit;
  end;
  mOp := LowerCase(ANode.Name);
  if TExpressionText.OperatorPrecedence(mOp) = cPrecedenceRelational then
  begin
    Exit(KindValue(TValueKind.Logical));
  end;
  Result := OperatorKind(mOp, ValueKindOf(AText, ANode[0], ALookup), ValueKindOf(AText, ANode[1], ALookup));
end;

function IfExprKind(const AText: string; ANode: TSyntaxNode; const ALookup: TConditionalLookup): TValueType;
var
  mLeft, mRight: TValueType;
begin
  Result := KindValue(TValueKind.Unknown);
  if ANode.ChildCount <> 3 then
  begin
    Exit;
  end;
  mLeft := ValueKindOf(AText, ANode[1], ALookup);
  mRight := ValueKindOf(AText, ANode[2], ALookup);
  if not TConditionalExpression.Compatible(mLeft, mRight) then
  begin
    Exit;
  end;
  if mLeft.Kind in [TValueKind.Whole, TValueKind.NilValue] then
  begin
    Result := mRight;
  end
  else
  begin
    Result := mLeft;
  end;
end;

function ValueKindOf(const AText: string; ANode: TSyntaxNode; const ALookup: TConditionalLookup): TValueType;
var
  mNode: TSyntaxNode;
begin
  mNode := TExpressionText.Strip(ANode);
  case mNode.Kind of
    TSyntaxKind.Literal:
      Result := LiteralKind(AText, mNode);
    TSyntaxKind.Identifier:
      Result := IdentifierKind(mNode, ALookup);
    TSyntaxKind.UnaryExpr:
      Result := UnaryKind(AText, mNode, ALookup);
    TSyntaxKind.BinaryExpr:
      Result := BinaryKind(AText, mNode, ALookup);
    TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Call:
      Result := LookupKind(mNode, ALookup);
    TSyntaxKind.IfExpr:
      Result := IfExprKind(AText, mNode, ALookup);
  else
    Result := KindValue(TValueKind.Unknown);
  end;
end;

/// <summary>Teil eines neuen Bedingungsausdrucks: ein Bedingungsausdruck vor then bzw. else in Klammern.</summary>
function Inner(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := TExpressionText.Part(AText, ANode).AtLeast(cPrecedenceIfExpr + 1);
end;

/// <summary>Text von AText zwischen den Offsets AStart und AEnd.</summary>
function Slice(const AText: string; AStart, AEnd: Integer): string;
begin
  Result := Copy(AText, AStart + 1, AEnd - AStart);
end;

/// <summary>Anweisung eines Zweigs, wenn er genau eine hat; nil sonst.</summary>
function SoleStatement(ABranch: TSyntaxNode): TSyntaxNode;
var
  mStatements: TArray<TSyntaxNode>;
begin
  Result := nil;
  mStatements := TStatementText.Statements(ABranch);
  if Length(mStatements) = 1 then
  begin
    Result := mStatements[0];
  end;
end;

/// <summary>Aufruf einer Aufrufanweisung (Name mit Argumenten); nil ohne Klammern.</summary>
function CallOf(AStatement: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (AStatement.Kind = TSyntaxKind.CallStatement) and (AStatement.ChildCount = 1) and
    (AStatement[0].Kind = TSyntaxKind.Call) and (AStatement[0].ChildCount >= 2) then
  begin
    Result := AStatement[0];
  end;
end;

function IsExit(ACall: TSyntaxNode): Boolean;
begin
  Result := (ACall <> nil) and (ACall[0].Kind = TSyntaxKind.Identifier) and SameText(ACall[0].Name, 'Exit');
end;

{ TConditionalExpression }

class function TConditionalExpression.Compatible(const A, B: TValueType): Boolean;
begin
  if (A.Kind = TValueKind.Unknown) or (B.Kind = TValueKind.Unknown) then
  begin
    Exit(False);
  end;
  if (A.Kind in [TValueKind.Whole, TValueKind.Float]) and (B.Kind in [TValueKind.Whole, TValueKind.Float]) then
  begin
    Exit(True);
  end;
  if (A.Kind = TValueKind.NilValue) and (B.Kind in [TValueKind.NilValue, TValueKind.Named]) then
  begin
    Exit(True);
  end;
  if (B.Kind = TValueKind.NilValue) and (A.Kind = TValueKind.Named) then
  begin
    Exit(True);
  end;
  Result := (A.Kind = B.Kind) and ((A.Kind <> TValueKind.Named) or SameText(A.Name, B.Name));
end;

class function TConditionalExpression.Outermost(ANode: TSyntaxNode): TSyntaxNode;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  mNode := ANode;
  while (mNode <> nil) and not TRoutineBody.IsStatement(mNode) do
  begin
    if mNode.Kind = TSyntaxKind.IfExpr then
    begin
      Result := mNode;
    end;
    // Eine anonyme Methode beginnt einen eigenen Rumpf.
    if mNode.Kind = TSyntaxKind.AnonymousMethod then
    begin
      Break;
    end;
    mNode := mNode.Parent;
  end;
end;

/// <summary>Kette lesen: Bedingungen, je eine Anweisung, abschließendes else. False bei anderer Form.</summary>
function ReadChain(AHead: TSyntaxNode; out AConditions, AStatements: TArray<TSyntaxNode>): Boolean;
var
  mNode, mStatement: TSyntaxNode;
begin
  Result := False;
  AConditions := nil;
  AStatements := nil;
  mNode := AHead;
  while mNode.ChildCount >= 3 do
  begin
    mStatement := SoleStatement(mNode[1]);
    if mStatement = nil then
    begin
      Exit;
    end;
    AConditions := AConditions + [mNode[0]];
    AStatements := AStatements + [mStatement];
    if (mNode[2].Kind <> TSyntaxKind.IfStatement) or (SoleStatement(mNode[2]) <> mNode[2]) then
    begin
      mStatement := SoleStatement(mNode[2]);
      Result := mStatement <> nil;
      if Result then
      begin
        AStatements := AStatements + [mStatement];
      end;
      Exit;
    end;
    mNode := mNode[2];
  end;
end;

/// <summary>Zuweisungen an dasselbe Ziel: die zugewiesenen Werte.</summary>
function AssignedValues(ATree: TSyntaxTree; const AStatements: TArray<TSyntaxNode>;
  out AValues: TArray<TSyntaxNode>): Boolean;
var
  mFirst, mStatement: TSyntaxNode;
begin
  AValues := nil;
  mFirst := AStatements[0];
  Result := mFirst.ChildCount = 2;
  for mStatement in AStatements do
  begin
    if Result then
    begin
      Result := (mStatement.Kind = TSyntaxKind.AssignStatement) and (mStatement.ChildCount = 2) and
        TExpressionText.Same(ATree, mStatement[0], mFirst[0]);
    end;
    if Result then
    begin
      AValues := AValues + [mStatement[1]];
    end;
  end;
end;

/// <summary>Argumente von ACall, die sich von AFirst unterscheiden, in ADiffers zusammenführen; False, wenn es
/// mehr als ein Argument wäre.</summary>
function MergeDiffering(ATree: TSyntaxTree; ACall, AFirst: TSyntaxNode; var ADiffers: Integer): Boolean;
var
  mArg: Integer;
begin
  for mArg := 1 to ACall.ChildCount - 1 do
  begin
    if not TExpressionText.Same(ATree, ACall[mArg], AFirst[mArg]) then
    begin
      if (ADiffers >= 0) and (ADiffers <> mArg) then
      begin
        Exit(False);
      end;
      ADiffers := mArg;
    end;
  end;
  Result := True;
end;

/// <summary>Derselbe Aufruf mit genau einem anderen Argument (ADiffers; -1, wenn alle gleich sind).</summary>
function DifferingArgument(ATree: TSyntaxTree; const AStatements: TArray<TSyntaxNode>; AFirstCall: TSyntaxNode;
  out ADiffers: Integer): Boolean;
var
  mStatement, mCall: TSyntaxNode;
begin
  ADiffers := -1;
  for mStatement in AStatements do
  begin
    mCall := CallOf(mStatement);
    if (mCall = nil) or (mCall.ChildCount <> AFirstCall.ChildCount) or
      not TExpressionText.Same(ATree, mCall[0], AFirstCall[0]) or
      not MergeDiffering(ATree, mCall, AFirstCall, ADiffers) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function HasSideEffects(ACall: TSyntaxNode): Boolean;
var
  mArg: Integer;
begin
  for mArg := 1 to ACall.ChildCount - 1 do
  begin
    if not TExpressionText.IsSideEffectFree(ACall[mArg]) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Derselbe Aufruf mit genau einem anderen Argument: die abweichenden Argumente.</summary>
function CalledValues(ATree: TSyntaxTree; const AStatements: TArray<TSyntaxNode>;
  out AValues: TArray<TSyntaxNode>): Boolean;
var
  mFirstCall, mStatement, mCall: TSyntaxNode;
  mDiffers: Integer;
begin
  AValues := nil;
  mFirstCall := CallOf(AStatements[0]);
  // Exit(A)/Exit(A) oder Log('a')/Log('a'): nichts zu verbinden.
  Result := (mFirstCall <> nil) and DifferingArgument(ATree, AStatements, mFirstCall, mDiffers) and (mDiffers >= 0);
  if not Result then
  begin
    Exit;
  end;
  for mStatement in AStatements do
  begin
    mCall := CallOf(mStatement);
    // Nur bei Exit dürfen die Werte Seiteneffekte haben: Bei anderen Aufrufen liefe die Bedingung sonst nach
    // den Argumenten davor statt vor allen.
    if not IsExit(mFirstCall) and HasSideEffects(mCall) then
    begin
      Exit(False);
    end;
    AValues := AValues + [mCall[mDiffers]];
  end;
end;

/// <summary>Gleiche Form: Zuweisung an dasselbe Ziel oder derselbe Aufruf mit genau einem anderen Argument.
/// </summary>
function BranchValues(ATree: TSyntaxTree; const AStatements: TArray<TSyntaxNode>;
  out AValues: TArray<TSyntaxNode>): Boolean;
begin
  if AStatements[0].Kind = TSyntaxKind.AssignStatement then
  begin
    Result := AssignedValues(ATree, AStatements, AValues);
  end
  else
  begin
    Result := CalledValues(ATree, AStatements, AValues);
  end;
end;

/// <summary>Verträgliche, bekannte Typen aller Werte.</summary>
function HaveCommonType(const AText: string; const AValues: TArray<TSyntaxNode>;
  const ALookup: TConditionalLookup): Boolean;
var
  mFirst: TValueType;
  mIndex: Integer;
begin
  mFirst := ValueKindOf(AText, AValues[0], ALookup);
  Result := mFirst.Kind <> TValueKind.Unknown;
  mIndex := 1;
  while Result and (mIndex <= High(AValues)) do
  begin
    Result := TConditionalExpression.Compatible(mFirst, ValueKindOf(AText, AValues[mIndex], ALookup));
    Inc(mIndex);
  end;
end;

/// <summary>"if B1 then W1 else if … else Wn" aus Bedingungen und Werten.</summary>
function ChainExpression(const AText: string; const AConditions, AValues: TArray<TSyntaxNode>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(AConditions) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ' else ';
    end;
    Result := Result + 'if ' + Inner(AText, AConditions[mIndex]) + ' then ' + Inner(AText, AValues[mIndex]);
  end;
  Result := Result + ' else ' + TExpressionText.Source(AText, AValues[High(AValues)]);
end;

class function TConditionalExpression.ToExpression(const AText: string; ATree: TSyntaxTree;
  const APosition: TTextPosition; const ALookup: TConditionalLookup; out ARewrite: TStatementRewrite): Boolean;
var
  mHead, mFirst: TSyntaxNode;
  mConditions, mStatements, mValues: TArray<TSyntaxNode>;
  mCode: string;
begin
  Result := False;
  ARewrite := Default(TStatementRewrite);
  mHead := TStatementText.HeadAt(ATree, APosition, TSyntaxKind.IfStatement);
  if (mHead = nil) or not ReadChain(mHead, mConditions, mStatements) or (Length(mConditions) > cMaxConditions) or
    TStatementText.HasComment(ATree, mHead.StartOffset, mHead.EndOffset) then
  begin
    Exit;
  end;
  if not BranchValues(ATree, mStatements, mValues) or not HaveCommonType(AText, mValues, ALookup) then
  begin
    Exit;
  end;
  // Die erste Anweisung mit dem Ausdruck an der Stelle ihres Werts.
  mFirst := mStatements[0];
  mCode := Slice(AText, mFirst.StartOffset, mValues[0].StartOffset) + ChainExpression(AText, mConditions, mValues) +
    Slice(AText, mValues[0].EndOffset, mFirst.EndOffset);
  ARewrite := TStatementRewrite.Create(ToExpressionTitle, TTextEdit.Create(TTextRange.Create(mHead.StartPos,
    mHead.EndPos), mCode));
  Result := True;
end;

/// <summary>Aufruf ANode, der nicht der Aufruf der Anweisung (ACall) und keine reine Routine ist.</summary>
function IsImpureCall(ANode, ACall: TSyntaxNode): Boolean;
var
  mCallee: TSyntaxNode;
begin
  Result := False;
  if ANode = ACall then
  begin
    Exit;
  end;
  mCallee := nil;
  if ANode.ChildCount > 0 then
  begin
    mCallee := ANode[0];
  end;
  Result := (mCallee = nil) or (mCallee.Kind <> TSyntaxKind.Identifier) or not TPureRoutines.IsPure(mCallee.Name);
end;

/// <summary>Hat der Teil von AStatement außerhalb von AExpression Seiteneffekte oder einen weiteren
/// Bedingungsausdruck? Der Aufruf einer Aufrufanweisung selbst (ACall) zählt nicht.</summary>
function RestIsUnsafe(AStatement, AExpression, ACall: TSyntaxNode): Boolean;
begin
  Result := AStatement.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode = AExpression then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      case ANode.Kind of
        TSyntaxKind.IfExpr, TSyntaxKind.AnonymousMethod, TSyntaxKind.InheritedExpr, TSyntaxKind.Error:
          Result := TSyntaxSearchStep.Found;
        TSyntaxKind.Call:
          if IsImpureCall(ANode, ACall) then
          begin
            Result := TSyntaxSearchStep.Found;
          end;
      else
        // Übrige Arten: nichts zu tun.
      end;
    end) <> nil;
end;

type
  /// <summary>Baut die if-Anweisung zu einem Bedingungsausdruck: die Anweisung mit dem Wert an seiner Stelle,
  /// je Zweig.</summary>
  TStatementBuilder = record
    Text: string;
    Prefix: string;
    Suffix: string;
    /// <summary>Mindestvorrang des Werts an seiner Stelle.</summary>
    Context: Integer;
    Layout: TStatementLayout;
    function Statement(AValue: TSyntaxNode): string;
    function Branch(AValue: TSyntaxNode; const ALayout: TStatementLayout): string;
    function Chain(AExpression: TSyntaxNode; const ALayout: TStatementLayout): string;
    procedure SetAround(AStatement, AReplaced: TSyntaxNode);
    function PrepareInlineVar(AStatement, AReplaced: TSyntaxNode; const ALineBreak: string;
      out ADeclaration: string): Boolean;
    function Prepare(AStatement, AReplaced: TSyntaxNode; const ALineBreak: string; out ACall: TSyntaxNode;
      out ADeclaration: string): Boolean;
  end;

function TStatementBuilder.Statement(AValue: TSyntaxNode): string;
begin
  Result := Prefix + TExpressionText.Part(Text, TExpressionText.Strip(AValue)).AtLeast(Context) + Suffix;
end;

function TStatementBuilder.Branch(AValue: TSyntaxNode; const ALayout: TStatementLayout): string;
var
  mValue: TSyntaxNode;
  mDeeper: TStatementLayout;
begin
  mValue := TExpressionText.Strip(AValue);
  mDeeper := ALayout.Deeper;
  if mValue.Kind = TSyntaxKind.IfExpr then
  begin
    // Ein inneres if vor else braucht begin … end.
    Result := ALayout.LineBreak + ALayout.Indent + 'begin' + ALayout.LineBreak + mDeeper.Indent +
      Chain(mValue, mDeeper) + ';' + ALayout.LineBreak + ALayout.Indent + 'end';
  end
  else
  begin
    Result := ALayout.LineBreak + mDeeper.Indent + Statement(mValue);
  end;
end;

function TStatementBuilder.Chain(AExpression: TSyntaxNode; const ALayout: TStatementLayout): string;
var
  mNode, mElseValue: TSyntaxNode;
begin
  Result := '';
  mNode := AExpression;
  // else-if-Ketten in einer Schleife; nur Ausdrücke vor then werden verschachtelt.
  while True do
  begin
    Result := Result + 'if ' + TExpressionText.Source(Text, mNode[0]) + ' then' + Branch(mNode[1], ALayout);
    mElseValue := TExpressionText.Strip(mNode[2]);
    if mElseValue.Kind = TSyntaxKind.IfExpr then
    begin
      Result := Result + ALayout.LineBreak + ALayout.Indent + 'else ';
      mNode := mElseValue;
    end
    else
    begin
      Result := Result + ALayout.LineBreak + ALayout.Indent + 'else' + ALayout.LineBreak + ALayout.Deeper.Indent +
        Statement(mElseValue);
      Break;
    end;
  end;
end;

/// <summary>Vor und hinter dem Wert bleibt der Text der Anweisung.</summary>
procedure TStatementBuilder.SetAround(AStatement, AReplaced: TSyntaxNode);
begin
  Prefix := Slice(Text, AStatement.StartOffset, AReplaced.StartOffset);
  Suffix := Slice(Text, AReplaced.EndOffset, AStatement.EndOffset);
end;

/// <summary>var X: T := if … wird var X: T; und Zuweisungen; ohne Typ kein Angebot.</summary>
function TStatementBuilder.PrepareInlineVar(AStatement, AReplaced: TSyntaxNode; const ALineBreak: string;
  out ADeclaration: string): Boolean;
begin
  ADeclaration := '';
  Result := (AStatement.ChildCount = 2) and (AStatement[0].Kind = TSyntaxKind.TypeReference) and
    (AStatement[1] = AReplaced);
  if Result then
  begin
    ADeclaration := 'var ' + AStatement.Name + ': ' + TExpressionText.Source(Text, AStatement[0]) + ';' +
      ALineBreak + Layout.Indent;
    Prefix := AStatement.Name + ' := ';
    Suffix := '';
  end;
end;

/// <summary>Präfix und Suffix je nach Art der Anweisung; ACall ist der Aufruf einer Aufrufanweisung (sonst nil),
/// ADeclaration die neue Variablendeklaration einer Inline-Variable. False bei anderen Anweisungen.</summary>
function TStatementBuilder.Prepare(AStatement, AReplaced: TSyntaxNode; const ALineBreak: string;
  out ACall: TSyntaxNode; out ADeclaration: string): Boolean;
begin
  ACall := nil;
  ADeclaration := '';
  Result := True;
  case AStatement.Kind of
    TSyntaxKind.AssignStatement:
      SetAround(AStatement, AReplaced);
    TSyntaxKind.CallStatement:
      begin
        ACall := CallOf(AStatement);
        Result := ACall <> nil;
        SetAround(AStatement, AReplaced);
      end;
    TSyntaxKind.InlineVar:
      Result := PrepareInlineVar(AStatement, AReplaced, ALineBreak, ADeclaration);
  else
    Result := False;
  end;
end;

/// <summary>Anweisung, in der AExpression steht; nil ohne oder hinter einer anonymen Methode.</summary>
function EnclosingStatement(AExpression: TSyntaxNode): TSyntaxNode;
begin
  Result := AExpression.Parent;
  while (Result <> nil) and not TRoutineBody.IsStatement(Result) do
  begin
    if Result.Kind = TSyntaxKind.AnonymousMethod then
    begin
      Exit(nil);
    end;
    Result := Result.Parent;
  end;
end;

/// <summary>Ein Bedingungsausdruck der Kette hat nicht drei Teile.</summary>
function HasIncompleteIfExpr(AExpression: TSyntaxNode): Boolean;
begin
  Result := AExpression.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate.Kind = TSyntaxKind.IfExpr) and (ACandidate.ChildCount <> 3) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Der Ausdruck samt umschließender Klammern; Klammern setzt der Vorrang.</summary>
function ReplacedNode(AExpression: TSyntaxNode): TSyntaxNode;
begin
  Result := AExpression;
  while (Result.Parent <> nil) and (Result.Parent.Kind = TSyntaxKind.ParenExpr) and
    (Result.Parent.ChildCount = 1) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>In einer Aufrufanweisung (ACall) muss der Ausdruck ein Argument sein oder in einem stecken, nicht im
/// Namen; ohne Aufruf True.</summary>
function InArgument(ACall, AReplaced: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  Result := True;
  if ACall = nil then
  begin
    Exit;
  end;
  mNode := AReplaced;
  while (mNode <> nil) and (mNode.Parent <> ACall) do
  begin
    mNode := mNode.Parent;
  end;
  Result := (mNode <> nil) and (TStatementText.ChildIndex(ACall, mNode) >= 1);
end;

class function TConditionalExpression.ToStatement(const AText: string; ATree: TSyntaxTree;
  AExpression: TSyntaxNode; const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean;
var
  mExpression, mStatement, mReplaced, mCall: TSyntaxNode;
  mBuilder: TStatementBuilder;
  mDeclaration: string;
begin
  Result := False;
  ARewrite := Default(TStatementRewrite);
  if (AExpression = nil) or (AExpression.Kind <> TSyntaxKind.IfExpr) then
  begin
    Exit;
  end;
  mExpression := Outermost(AExpression);
  if (mExpression = nil) or (mExpression.ChildCount <> 3) then
  begin
    Exit;
  end;
  mStatement := EnclosingStatement(mExpression);
  if (mStatement = nil) or HasIncompleteIfExpr(mExpression) or
    TStatementText.HasComment(ATree, mStatement.StartOffset, mStatement.EndOffset) then
  begin
    Exit;
  end;
  mReplaced := ReplacedNode(mExpression);
  mBuilder := Default(TStatementBuilder);
  mBuilder.Text := AText;
  mBuilder.Context := TExpressionText.ContextPrecedence(mReplaced);
  mBuilder.Layout := TStatementLayout.Create(TTextLines.IndentOf(AText, mStatement.StartPos.Line),
    ALayout.IndentUnit, ALayout.LineBreak);
  if not mBuilder.Prepare(mStatement, mReplaced, ALayout.LineBreak, mCall, mDeclaration) or
    RestIsUnsafe(mStatement, mExpression, mCall) or not InArgument(mCall, mReplaced) then
  begin
    Exit;
  end;
  ARewrite := TStatementRewrite.Create(ToStatementTitle, TTextEdit.Create(TTextRange.Create(mStatement.StartPos,
    mStatement.EndPos), mDeclaration + mBuilder.Chain(mExpression, mBuilder.Layout)));
  Result := True;
end;

class function TConditionalExpression.ToStatement(const AText: string; ATree: TSyntaxTree;
  const APosition: TTextPosition; const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean;
var
  mPosition: TTextPosition;
  mFound: TSyntaxNode;
begin
  Result := False;
  ARewrite := Default(TStatementRewrite);
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mPosition := APosition;
  mFound := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if not TStatementText.Encloses(ANode, mPosition) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind = TSyntaxKind.IfExpr then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
  Result := ToStatement(AText, ATree, mFound, ALayout, ARewrite);
end;

class function TConditionalExpression.ReplaceIfThen(const AText: string; ATree: TSyntaxTree;
  const APosition: TTextPosition; const ALookup: TConditionalLookup; out ARewrite: TStatementRewrite): Boolean;
var
  mPosition: TTextPosition;
  mCall: TSyntaxNode;
  mFallback, mElseValue, mExpression: string;
begin
  Result := False;
  ARewrite := Default(TStatementRewrite);
  if (ATree = nil) or (ATree.Root = nil) or not Assigned(ALookup.IfThen) then
  begin
    Exit;
  end;
  mPosition := APosition;
  mCall := nil;
  // Der innerste IfThen-Aufruf an der Stelle.
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := TStatementText.Encloses(ANode, mPosition);
      if Result and (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount in [3, 4]) and
        (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'IfThen') then
      begin
        mCall := ANode;
      end;
    end);
  if (mCall = nil) or not ALookup.IfThen(mCall, mFallback) or
    TStatementText.HasComment(ATree, mCall.StartOffset, mCall.EndOffset) then
  begin
    Exit;
  end;
  if mCall.ChildCount = 4 then
  begin
    mElseValue := TExpressionText.Source(AText, mCall[3]);
  end
  else
  begin
    mElseValue := mFallback;
  end;
  mExpression := 'if ' + Inner(AText, mCall[1]) + ' then ' + Inner(AText, mCall[2]) + ' else ' + mElseValue;
  ARewrite := TStatementRewrite.Create(IfThenTitle, TTextEdit.Create(TTextRange.Create(mCall.StartPos, mCall.EndPos),
    TExpressionPart.Create(mExpression, cPrecedenceIfExpr).AtLeast(TExpressionText.ContextPrecedence(mCall))));
  Result := True;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.ConditionalExpression', cTexts);

end.
