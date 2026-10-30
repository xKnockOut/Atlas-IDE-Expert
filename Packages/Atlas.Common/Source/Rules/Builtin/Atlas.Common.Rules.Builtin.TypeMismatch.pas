unit Atlas.Common.Rules.Builtin.TypeMismatch;

// Inkompatible Typen schon beim Tippen (#1369, Gruppe „Compiler vorab“, Stufe
// T): Zuweisung, Argument, var-Parameter, Operator, Typumwandlung und
// prozedurale Typen. Die Typen kommen aus TExpressionTypes (#689) und der
// Namensauflösung über TTypedScope; gemeldet wird nur, wenn beide Seiten sicher
// bekannt sind, ihre Deklarationen immer mit der Stelle übersetzt werden und
// TTypeCompatibility die Kombination sicher ablehnt. Nicht strenger als dcc
// (#1328): Records (class operator Implicit), Variant, Zeiger, Teilbereiche,
// Generics, überladene Routinen und with-Blöcke bleiben still.
//   type-mismatch
//                     - Zuweisung und Standardwert eines Parameters mit
//                       unverträglichem Typ: Integer := 'abc', TObject = 0,
//                       array[0..2] of Integer := nil (wie E2010); eine
//                       Prozedur ohne Ergebnis als Wert (wie E2010).
//                     - Argument eines Wertparameters bzw. Index einer
//                       Array-Property mit unverträglichem Typ (wie E2010),
//                       var-Argument mit anderem Typ als der Parameter (wie
//                       E2033); nur bei genau einer Routine ohne Überladungen.
//                     - Operator, der für einen Operanden nicht definiert ist:
//                       string - Char, Double div 2, not 'a', X is Integer (wie
//                       E2015); string + Integer und [1] + ['a'] (wie E2010).
//                     - Typumwandlung Byte(S) eines langen Strings in eine
//                       kleinere Ganzzahl und einer Gleitkommazahl in einen
//                       Ordinaltyp (wie E2089).
//                     - Inc/Dec mit einer Gleitkommazahl oder einem String als
//                       Schrittweite und Ptr(S) (wie E2008).
//                     - Routine an einen prozeduralen Typ mit anderer
//                       Parameterliste bzw. Methode an einen Typ ohne of object
//                       und umgekehrt (wie E2009); von Überladungen passt keine
//                       (wie E2010).
//                     Keine Korrektur: Welche Seite falsch ist, weiß nur der
//                     Entwickler.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  TypeMismatchRuleId = 'type-mismatch';

type
  TTypeMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterTypeMismatchRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ExpressionTypes,
  Atlas.Common.Semantics.TypeCompatibility,
  Atlas.Common.Semantics.TypeIdentity,
  Atlas.Common.Editing.ChangeSignature;

const
  cMaxDepth = 64;
  // Eingebaute Routinen, deren Ergebnistyp nicht von den Argumenten abhängt.
  cTypedIntrinsics: array[0..18] of string = ('Length', 'Pos', 'Ord', 'Round', 'Trunc', 'Chr', 'UpCase', 'Assigned',
    'Odd', 'Sqrt', 'Sin', 'Cos', 'Exp', 'Ln', 'ArcTan', 'Frac', 'Int', 'Pi', 'Concat');
  cNoResultName = 'procedure, untyped pointer or untyped parameter';

type
  /// <summary>Wie eine Routine zu einem prozeduralen Typ passt.</summary>
  TProcMatch = (Yes, Unsure, MethodKind, Parameters, ParameterType);

  /// <summary>Kopf eines prozeduralen Typs bzw. einer Routine.</summary>
  TProcShape = record
    IsFunction: Boolean;
    OfObject: Boolean;
    Reference: Boolean;
    Params: TArray<TSignatureParameter>;
    ResultType: string;
  end;

  /// <summary>Eine Prüfung einer Datei: Namensauflösung, Ausdruckstypen und gemerkte Typen je Knoten.</summary>
  TTypeMismatchCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FScope: TTypedScope;
    FTypes: TExpressionTypes;
    FLocal: TUnitIndex;
    FValues: TDictionary<TSyntaxNode, TValueType>;
    FDepth: Integer;
    function Tree: TSyntaxTree;
    function NodeText(ANode: TSyntaxNode): string;
    function DeclarationAt(const APosition: TTextPosition): TSyntaxNode;
    function DeclaredText(const ASymbol: TResolvedSymbol): string;
    function IsIntrinsic(ACallee: TSyntaxNode): Boolean;
    function BuiltinCast(ACallee: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
    function HiddenMember(ANode: TSyntaxNode; const ASymbol: TResolvedSymbol): Boolean;
    function SameResultType(ACallee: TSyntaxNode): Boolean;
    function ValueOfType(const AType: TResolvedSymbol): TValueType;
    function ValueOfSymbol(const ASymbol, AType: TResolvedSymbol): TValueType;
    function TypeValueFrom(const AUnit: TUnitIndex; const ATypeText: string): TValueType;
    function DescribedValue(ANode: TSyntaxNode): TValueType;
    function LeafValue(ANode: TSyntaxNode): TValueType;
    function ComputeValue(ANode: TSyntaxNode): TValueType;
    function ValueOf(ANode: TSyntaxNode): TValueType;
    function TargetValue(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): TValueType;
    function IsProcedure(ANode: TSyntaxNode): Boolean;
    function ProceduralText(ANode: TSyntaxNode; const ASymbol, AType: TResolvedSymbol): string;
    function RoutineCandidates(ANode: TSyntaxNode; out ACandidates: TArray<TResolvedSymbol>): Boolean;
    procedure Mismatch(ANode: TSyntaxNode; const ATarget, ASource: string);
    procedure CheckAssignment(ANode: TSyntaxNode);
    procedure CheckProcedural(ANode: TSyntaxNode; const ATarget: TProcShape);
    procedure CheckDefault(ANode: TSyntaxNode);
    procedure CheckCall(ANode: TSyntaxNode);
    procedure CheckIntrinsic(ANode: TSyntaxNode; const AName: string);
    procedure CheckCast(ANode: TSyntaxNode; const AType: TResolvedSymbol);
    procedure CheckVarArgument(AArgument: TSyntaxNode; const AFormal: TValueType);
    procedure CheckIndexer(ANode: TSyntaxNode);
    procedure CheckBinary(ANode: TSyntaxNode);
    procedure CheckUnary(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

/// <summary>Teil von AText innerhalb der Klammer ab AOpen (1-basiert) bis zur passenden schließenden; AClose die
/// Stelle der schließenden Klammer, 0 ohne.</summary>
function InParens(const AText: string; AOpen: Integer; out AClose: Integer): string;
var
  mIndex, mDepth: Integer;
begin
  Result := '';
  AClose := 0;
  mDepth := 0;
  for mIndex := AOpen to Length(AText) do
    if AText[mIndex] = '(' then
      Inc(mDepth)
    else if AText[mIndex] = ')' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        AClose := mIndex;
        Exit(Copy(AText, AOpen + 1, mIndex - AOpen - 1));
      end;
    end;
end;

/// <summary>Kopf "procedure(A: Integer) of object", "reference to function: Boolean" bzw. einer Routine
/// "class procedure TKlasse.Machen; static;" (mit Namen, AWithName) zerlegen. False, wenn er nicht lesbar ist.
/// </summary>
function ParseShape(const AText: string; AWithName: Boolean; out AShape: TProcShape): Boolean;
var
  mText, mRest, mWord: string;
  mPosition, mClose: Integer;
begin
  AShape := Default(TProcShape);
  Result := False;
  mText := Trim(AText);
  if StartsText('reference to ', mText) then
  begin
    AShape.Reference := True;
    mText := Trim(Copy(mText, 14, MaxInt));
  end;
  if StartsText('class ', mText) then
    mText := Trim(Copy(mText, 7, MaxInt));
  if StartsText('procedure', mText) then
    mText := Copy(mText, 10, MaxInt)
  else if StartsText('function', mText) then
  begin
    AShape.IsFunction := True;
    mText := Copy(mText, 9, MaxInt);
  end
  else
    Exit;
  mText := TrimLeft(mText);
  if AWithName then
  begin
    // Name bis zur Klammer, zum Doppelpunkt oder zum Semikolon (TKlasse.Machen, Foo<T>).
    mPosition := 1;
    while (mPosition <= Length(mText)) and not CharInSet(mText[mPosition], ['(', ':', ';', ' ']) do
      Inc(mPosition);
    mText := TrimLeft(Copy(mText, mPosition, MaxInt));
  end
  else if (mText <> '') and not CharInSet(mText[1], ['(', ':', ';', 'o', 'O']) and not StartsText('stdcall', mText) and
    not StartsText('cdecl', mText) and not StartsText('register', mText) and not StartsText('pascal', mText) and
    not StartsText('safecall', mText) then
    Exit;
  if StartsStr('(', mText) then
  begin
    mRest := InParens(mText, 1, mClose);
    if mClose = 0 then
      Exit;
    AShape.Params := TChangeSignature.ParseParameters(mRest);
    mText := TrimLeft(Copy(mText, mClose + 1, MaxInt));
  end;
  if StartsStr(':', mText) then
  begin
    mText := TrimLeft(Copy(mText, 2, MaxInt));
    mPosition := 1;
    while (mPosition <= Length(mText)) and not CharInSet(mText[mPosition], [';', ' ']) do
      Inc(mPosition);
    AShape.ResultType := Copy(mText, 1, mPosition - 1);
    mText := TrimLeft(Copy(mText, mPosition, MaxInt));
  end;
  // of object und Direktiven.
  for mWord in mText.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty) do
    if SameText(mWord, 'object') then
      AShape.OfObject := True;
  Result := True;
end;

function NormalizedModifier(const AModifier: string): string;
var
  mWords: TArray<string>;
begin
  // "[ref] const" → const.
  mWords := LowerCase(Trim(AModifier)).Split([' '], TStringSplitOptions.ExcludeEmpty);
  Result := '';
  if Length(mWords) > 0 then
    Result := mWords[High(mWords)];
end;

function IsStaticArrayText(const AText: string): Boolean;
var
  mText: string;
  mBracket, mOf: Integer;
begin
  mText := LowerCase(Trim(AText));
  if StartsStr('packed ', mText) then
    mText := Trim(Copy(mText, 8, MaxInt));
  mBracket := Pos('[', mText);
  mOf := Pos(' of ', mText);
  Result := StartsStr('array', mText) and (mBracket > 0) and (mOf > mBracket);
end;

function IsDataCategory(const AValue: TValueType): Boolean;
begin
  Result := (AValue.Kind = TValueKind.Builtin) and (AValue.Category in [TExpressionCategory.Integer_,
    TExpressionCategory.Float, TExpressionCategory.Currency_, TExpressionCategory.Boolean_, TExpressionCategory.Char_,
    TExpressionCategory.String_]);
end;

/// <summary>Name eines Werts in der Meldung: nil heißt bei dcc Pointer, Mengen aus Literalen nennen ihr Element.
/// </summary>
function ShownName(const AValue: TValueType): string;
var
  mElement: TValueType;
begin
  Result := AValue.Name;
  if AValue.Category = TExpressionCategory.Nil_ then
    Exit('Pointer');
  if AValue.Category = TExpressionCategory.Set_ then
  begin
    mElement := TValueType.FromBuiltin(TTypeCompatibility.SetElement(AValue.Name));
    if mElement.Category = TExpressionCategory.Integer_ then
      Result := 'Integer'
    else if mElement.Category = TExpressionCategory.Char_ then
      Result := 'AnsiChar';
  end;
end;

/// <summary>Eingebauter Typ AName als aufgelöstes Symbol.</summary>
function BuiltinSymbol(const AName: string): TResolvedSymbol;
begin
  Result := Default(TResolvedSymbol);
  Result.Kind := TResolvedKind.Symbol;
  Result.Name := AName;
  Result.Builtin := True;
end;

{ TTypeMismatchCheck }

constructor TTypeMismatchCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mOptions: TExpressionTypeOptions;
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FScope := TTypedScope.Create(AContext);
  mOptions := TExpressionTypeOptions.Default;
  mOptions.Conversions := False;
  mOptions.ConstValue := False;
  FTypes := TExpressionTypes.Create(FScope.Resolver, AContext.Tree, FScope.FileName, AContext.Text, AContext.Index,
    mOptions);
  FLocal := FScope.Resolver.ExtractedUnit(AContext.Tree, FScope.FileName);
  FValues := TDictionary<TSyntaxNode, TValueType>.Create;
end;

destructor TTypeMismatchCheck.Destroy;
begin
  FValues.Free;
  FTypes.Free;
  FScope.Free;
  inherited;
end;

function TTypeMismatchCheck.Tree: TSyntaxTree;
begin
  Result := FContext.Tree;
end;

function TTypeMismatchCheck.NodeText(ANode: TSyntaxNode): string;
begin
  Result := FScope.Text(ANode);
  if Length(Result) > TExpressionTypes.MaxExpressionLength then
    Result := Copy(Result, 1, TExpressionTypes.MaxExpressionLength - 1) + #$2026;
end;

function TTypeMismatchCheck.DeclarationAt(const APosition: TTextPosition): TSyntaxNode;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;

  function Covers(ANode: TSyntaxNode): Boolean;
  begin
    Result := ((ANode.StartPos.Line < APosition.Line) or ((ANode.StartPos.Line = APosition.Line) and
      (ANode.StartPos.Character <= APosition.Character))) and ((ANode.EndPos.Line > APosition.Line) or
      ((ANode.EndPos.Line = APosition.Line) and (ANode.EndPos.Character >= APosition.Character)));
  end;

begin
  Result := nil;
  // Iterativ (Bericht M1); nur in Knoten absteigen, die die Stelle enthalten. Der innerste gewinnt.
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(Tree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if not Covers(mNode) then
        Continue;
      if mNode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.Field, TSyntaxKind.TypeDecl,
        TSyntaxKind.ConstDecl, TSyntaxKind.InlineVar] then
        Result := mNode;
      for mIndex := mNode.ChildCount - 1 downto 0 do
        mPending.Push(mNode[mIndex]);
    end;
  finally
    mPending.Free;
  end;
end;

function TTypeMismatchCheck.DeclaredText(const ASymbol: TResolvedSymbol): string;
var
  mDecl, mChild: TSyntaxNode;
  mIndex: Integer;
begin
  Result := '';
  if not SameText(ASymbol.FileName, FScope.FileName) and (ASymbol.Kind <> TResolvedKind.Local) then
    Exit;
  mDecl := DeclarationAt(ASymbol.SelectionRange.StartPos);
  if mDecl = nil then
    Exit;
  for mIndex := 0 to mDecl.ChildCount - 1 do
  begin
    mChild := mDecl[mIndex];
    if mChild.Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.ProcedureType,
      TSyntaxKind.PointerType, TSyntaxKind.SetType, TSyntaxKind.SubrangeType, TSyntaxKind.RecordType,
      TSyntaxKind.EnumType, TSyntaxKind.FileType] then
      Exit(FScope.Text(mChild));
  end;
end;

function TTypeMismatchCheck.BuiltinCast(ACallee: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
begin
  // Byte(X), wenn System nicht im Index steht.
  AType := Default(TResolvedSymbol);
  Result := (ACallee <> nil) and (ACallee.Kind = TSyntaxKind.Identifier) and
    TNameResolver.IsBuiltinTypeName(ACallee.Name) and
    (Length(FScope.Resolver.CallCandidates(Tree, FScope.FileName, ACallee)) = 0);
  if Result then
    AType := BuiltinSymbol(ACallee.Name);
end;

function TTypeMismatchCheck.IsIntrinsic(ACallee: TSyntaxNode): Boolean;
var
  mCandidates: TArray<TResolvedSymbol>;
begin
  Result := False;
  if (ACallee = nil) or (ACallee.Kind <> TSyntaxKind.Identifier) then
    Exit;
  mCandidates := FScope.Resolver.CallCandidates(Tree, FScope.FileName, ACallee);
  Result := (Length(mCandidates) = 0) or mCandidates[0].Builtin or SameText(mCandidates[0].UnitName, 'System');
end;

function TTypeMismatchCheck.HiddenMember(ANode: TSyntaxNode; const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and FScope.Resolver.MayBeHiddenMember(Tree, FScope.FileName, ANode,
    ASymbol);
end;

function TTypeMismatchCheck.SameResultType(ACallee: TSyntaxNode): Boolean;
var
  mCandidates: TArray<TResolvedSymbol>;
  mCandidate: TResolvedSymbol;
begin
  // Überladungen mit verschiedenen Ergebnistypen: Welche gilt, entscheiden die Argumente.
  mCandidates := FScope.Resolver.CallCandidates(Tree, FScope.FileName, ACallee);
  for mCandidate in mCandidates do
  begin
    if not TTypeIdentity.Same(mCandidate.TypeName, mCandidates[0].TypeName) then
      Exit(False);
    // Freie Routinen mit overload führt dcc über alle eingebundenen Units zusammen (IfThen aus System.Math und
    // System.StrUtils); die Kandidaten kommen nur aus einer Unit, der Ergebnistyp ist also offen.
    if (mCandidate.Container = '') and (MatchText('overload', mCandidate.Directives) or
      ContainsText(mCandidate.Signature, 'overload')) then
      Exit(False);
  end;
  Result := True;
end;

function TTypeMismatchCheck.ValueOfType(const AType: TResolvedSymbol): TValueType;
var
  mCurrent, mNext: TResolvedSymbol;
  mUnit: TUnitIndex;
  mBody: string;
  mDepth: Integer;
begin
  Result := Default(TValueType);
  if (AType.Name = '') or (AType.Condition <> '') then
    Exit;
  if AType.Builtin then
  begin
    Result := TValueType.FromBuiltin(AType.Name);
    if Result.Kind <> TValueKind.Builtin then
      Result := Default(TValueType);
    Exit;
  end;
  case AType.SymbolKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType:
      Result := TValueType.Create(AType.Name, TExpressionCategory.Other, TValueKind.ClassLike);
    TIndexSymbolKind.EnumType:
      Result := TValueType.Create(AType.Name, TExpressionCategory.Other, TValueKind.Enum);
    TIndexSymbolKind.TypeAlias:
      begin
        // Kette TA = TB, TB = Single Glied für Glied: Steht ein Glied in einem bedingten Zweig (TDimension =
        // Single bzw. Integer je nach {$IFDEF}), ist der Typ offen.
        mCurrent := AType;
        for mDepth := 0 to cMaxDepth do
        begin
          if (mCurrent.Condition <> '') or (Pos('=', mCurrent.Signature) = 0) then
            Exit;
          mBody := Trim(Copy(mCurrent.Signature, Pos('=', mCurrent.Signature) + 1, MaxInt));
          if EndsStr(';', mBody) then
            mBody := Trim(Copy(mBody, 1, Length(mBody) - 1));
          if Pos('{', mBody) > 0 then
            Exit;
          if IsStaticArrayText(mBody) then
            Exit(TValueType.Create(AType.Name, TExpressionCategory.Other, TValueKind.StaticArray));
          // type Integer: eigener Typ, für Zuweisungen aber wie Integer.
          if StartsText('type ', mBody) then
            mBody := Trim(Copy(mBody, 6, MaxInt));
          if not FScope.Resolver.DeclaringUnit(mCurrent, mUnit) or (Pos('.', mBody) > 0) or
            not FScope.Resolver.ResolveNameFrom(mUnit, mBody, mNext) or not mNext.IsType then
          begin
            if not TNameResolver.IsBuiltinTypeName(mBody) then
              Exit;
            mNext := BuiltinSymbol(mBody);
          end;
          if mNext.Builtin or (mNext.SymbolKind <> TIndexSymbolKind.TypeAlias) then
          begin
            Result := ValueOfType(mNext);
            // TZahl = Integer rechnet wie Integer; der Name bleibt der des Alias.
            if Result.Known then
              Result.Name := AType.Name;
            Exit;
          end;
          mCurrent := mNext;
        end;
      end;
  else
    // Records, Objekte, Helfer: offen.
  end;
end;

function TTypeMismatchCheck.ValueOfSymbol(const ASymbol, AType: TResolvedSymbol): TValueType;
var
  mText: string;
  mUnit: TUnitIndex;
  mDeclared: TResolvedSymbol;
begin
  // AType ist schon über alle Aliase verfolgt; ob ein Glied der Kette bedingt ist, zeigt erst der deklarierte Name.
  mText := TTypeIdentity.Clean(ASymbol.TypeName);
  if (mText <> '') and not TNameResolver.IsBuiltinTypeName(mText) then
  begin
    Result := Default(TValueType);
    if ASymbol.Kind = TResolvedKind.Local then
      mUnit := FLocal
    else if not FScope.Resolver.DeclaringUnit(ASymbol, mUnit) then
      Exit;
    // ResolveNameFrom liefert den Alias selbst, ResolveTypeFrom schon sein Ziel.
    if (Pos('.', mText) > 0) or not FScope.Resolver.ResolveNameFrom(mUnit, mText, mDeclared) or
      not mDeclared.IsType then
      Exit;
    Result := ValueOfType(mDeclared);
  end
  else
    Result := ValueOfType(AType);
  // Untypisierte Konstante 'a' ist auch ein Zeichen.
  if (ASymbol.SymbolKind = TIndexSymbolKind.Constant) and (ASymbol.TypeName = '') then
    Result.UntypedText := True;
end;

function TTypeMismatchCheck.TypeValueFrom(const AUnit: TUnitIndex; const ATypeText: string): TValueType;
var
  mType: TResolvedSymbol;
  mText: string;
begin
  Result := Default(TValueType);
  mText := TTypeIdentity.Clean(ATypeText);
  if (mText = '') or (Pos(' ', mText) > 0) or (Pos('<', mText) > 0) or (Pos('^', mText) > 0) or
    (Pos('.', mText) > 0) then
    Exit;
  // Den Alias selbst (ResolveNameFrom), damit ValueOfType bedingte Glieder der Kette sieht.
  if FScope.Resolver.ResolveNameFrom(AUnit, mText, mType) and mType.IsType then
    Result := ValueOfType(mType)
  else if TNameResolver.IsBuiltinTypeName(mText) then
    // Ohne System im Index.
    Result := ValueOfType(BuiltinSymbol(mText));
end;

function TTypeMismatchCheck.DescribedValue(ANode: TSyntaxNode): TValueType;
var
  mInfo: TExpressionTypeInfo;
begin
  Result := Default(TValueType);
  mInfo := FTypes.Describe(ANode);
  if not mInfo.Found then
    Exit;
  Result := TValueType.FromBuiltin(mInfo.TypeName);
  if Result.Kind <> TValueKind.Builtin then
    Result := Default(TValueType);
end;

function TTypeMismatchCheck.LeafValue(ANode: TSyntaxNode): TValueType;
var
  mSymbol, mType: TResolvedSymbol;
  mFound: Boolean;
  mCallee: TSyntaxNode;
begin
  Result := Default(TValueType);
  mCallee := ANode;
  if ANode.Kind = TSyntaxKind.Call then
  begin
    if ANode.ChildCount = 0 then
      Exit;
    mCallee := ANode[0];
    if BuiltinCast(mCallee, mType) then
    begin
      if ANode.ChildCount = 2 then
        Result := ValueOfType(mType);
      Exit;
    end;
    if IsIntrinsic(mCallee) then
    begin
      if MatchText(mCallee.Name, cTypedIntrinsics) then
        Result := DescribedValue(ANode);
      Exit;
    end;
  end;
  if not (mCallee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
    (ANode.Kind <> TSyntaxKind.IndexAccess) then
    Exit;
  if (mCallee.Kind = TSyntaxKind.MemberAccess) and (mCallee.FindChild(TSyntaxKind.GenericArgs) <> nil) then
    Exit;
  if not FScope.Resolver.NodeType(Tree, FScope.FileName, ANode, mSymbol, mType, mFound) or
    (mSymbol.Kind = TResolvedKind.UnitName) then
    Exit;
  if mSymbol.IsType then
  begin
    // S[1] ist ein Zeichen, Byte(X) ein Byte.
    if (ANode.Kind = TSyntaxKind.IndexAccess) and mSymbol.Builtin then
      Result := ValueOfType(mSymbol)
    else if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) then
      Result := ValueOfType(mSymbol);
    Exit;
  end;
  if not mFound or not FScope.DeclarationSure(mSymbol, ANode) or HiddenMember(mCallee, mSymbol) then
    Exit;
  if (mSymbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and not SameResultType(mCallee) then
    Exit;
  if mSymbol.SymbolKind = TIndexSymbolKind.Constructor_ then
    Exit;
  Result := ValueOfSymbol(mSymbol, mType);
end;

function TTypeMismatchCheck.ComputeValue(ANode: TSyntaxNode): TValueType;
var
  mNode: TSyntaxNode;
  mOperator: string;
  mLeft, mRight, mOperand: TValueType;
  mIndex: Integer;
begin
  Result := Default(TValueType);
  mNode := Unwrapped(ANode);
  if mNode = nil then
    Exit;
  case mNode.Kind of
    TSyntaxKind.Literal:
      Result := DescribedValue(mNode);
    TSyntaxKind.Identifier:
      if SameText(mNode.Name, 'nil') or SameText(mNode.Name, 'True') or SameText(mNode.Name, 'False') then
        Result := DescribedValue(mNode)
      else
        Result := LeafValue(mNode);
    TSyntaxKind.MemberAccess, TSyntaxKind.Call, TSyntaxKind.IndexAccess:
      Result := LeafValue(mNode);
    TSyntaxKind.AddressOf:
      Result := TValueType.FromBuiltin('Pointer');
    TSyntaxKind.SetConstructor:
      begin
        for mIndex := 0 to mNode.ChildCount - 1 do
          if mNode[mIndex].Kind = TSyntaxKind.RangeExpr then
          begin
            if (mNode[mIndex].ChildCount = 0) or not ValueOf(mNode[mIndex][0]).Known then
              Exit;
          end
          else if not ValueOf(mNode[mIndex]).Known then
            Exit;
        Result := DescribedValue(mNode);
      end;
    TSyntaxKind.BinaryExpr:
      begin
        if mNode.ChildCount <> 2 then
          Exit;
        mOperator := LowerCase(mNode.Name);
        mLeft := ValueOf(mNode[0]);
        if MatchStr(mOperator, ['=', '<>', '<', '>', '<=', '>=', 'in', 'is']) then
        begin
          if mLeft.Known and ((mOperator = 'is') or ValueOf(mNode[1]).Known) then
            Result := TValueType.FromBuiltin('Boolean');
          Exit;
        end;
        mRight := ValueOf(mNode[1]);
        if TTypeCompatibility.OperatorFit(mOperator, mLeft, mRight) = TOperatorFit.Fits then
          Result := DescribedValue(mNode);
      end;
    TSyntaxKind.UnaryExpr:
      begin
        if (mNode.ChildCount <> 1) or (mNode.Name = '@') then
          Exit;
        mOperand := ValueOf(mNode[0]);
        if mOperand.Known and not TTypeCompatibility.UnaryNotApplicable(mNode.Name, mOperand) and
          (mOperand.Kind = TValueKind.Builtin) then
          Result := DescribedValue(mNode);
      end;
  else
    // if-Ausdrücke, anonyme Methoden, Dereferenz, inherited: offen.
  end;
end;

function TTypeMismatchCheck.ValueOf(ANode: TSyntaxNode): TValueType;
begin
  Result := Default(TValueType);
  if (ANode = nil) or (FDepth > cMaxDepth) then
    Exit;
  if FValues.TryGetValue(ANode, Result) then
    Exit;
  Inc(FDepth);
  try
    Result := ComputeValue(ANode);
  finally
    Dec(FDepth);
  end;
  FValues.AddOrSetValue(ANode, Result);
end;

function TTypeMismatchCheck.TargetValue(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): TValueType;
var
  mFound: Boolean;
  mText: string;
begin
  Result := Default(TValueType);
  ASymbol := Default(TResolvedSymbol);
  AType := Default(TResolvedSymbol);
  if not (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) then
    Exit;
  if not FScope.Resolver.NodeType(Tree, FScope.FileName, ANode, ASymbol, AType, mFound) or
    (ASymbol.Kind = TResolvedKind.UnitName) or ASymbol.IsType then
    Exit;
  // Variablen, Felder, Properties und Parameter; Result zählt als Variable.
  if not (ASymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) then
    Exit;
  if not FScope.DeclarationSure(ASymbol, ANode) or HiddenMember(ANode, ASymbol) then
    Exit;
  if mFound then
    Result := ValueOfSymbol(ASymbol, AType)
  else
  begin
    // array[0..2] of Integer ohne eigenen Typ.
    mText := DeclaredText(ASymbol);
    if IsStaticArrayText(mText) then
      Result := TValueType.Create(mText, TExpressionCategory.Other, TValueKind.StaticArray);
  end;
end;

function TTypeMismatchCheck.RoutineCandidates(ANode: TSyntaxNode; out ACandidates: TArray<TResolvedSymbol>): Boolean;
var
  mCandidate: TResolvedSymbol;
begin
  ACandidates := nil;
  Result := False;
  if not (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
    (ANode.FindChild(TSyntaxKind.GenericArgs) <> nil) then
    Exit;
  ACandidates := FScope.Resolver.CallCandidates(Tree, FScope.FileName, ANode);
  if Length(ACandidates) = 0 then
    Exit;
  for mCandidate in ACandidates do
    if not (mCandidate.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) or mCandidate.Builtin or
      (mCandidate.Signature = '') or (mCandidate.TypeParams <> '') or not FScope.DeclarationSure(mCandidate, ANode) or
      HiddenMember(ANode, mCandidate) then
      Exit;
  Result := True;
end;

function TTypeMismatchCheck.IsProcedure(ANode: TSyntaxNode): Boolean;
var
  mCandidates: TArray<TResolvedSymbol>;
  mCandidate: TResolvedSymbol;
  mShape: TProcShape;
begin
  Result := RoutineCandidates(ANode, mCandidates);
  if not Result then
    Exit;
  for mCandidate in mCandidates do
    if not ParseShape(mCandidate.Signature, True, mShape) or mShape.IsFunction then
      Exit(False);
end;

function TTypeMismatchCheck.ProceduralText(ANode: TSyntaxNode; const ASymbol, AType: TResolvedSymbol): string;
var
  mBody: string;
begin
  Result := '';
  if (AType.Name <> '') and not AType.Builtin and (Pos('=', AType.Signature) > 0) then
  begin
    mBody := Trim(Copy(AType.Signature, Pos('=', AType.Signature) + 1, MaxInt));
    if StartsText('procedure', mBody) or StartsText('function', mBody) or StartsText('reference', mBody) then
      Exit(mBody);
    Exit;
  end;
  if AType.Name <> '' then
    Exit;
  mBody := ASymbol.TypeName;
  if not (StartsText('procedure', mBody) or StartsText('function', mBody) or StartsText('reference', mBody)) then
    mBody := DeclaredText(ASymbol);
  if StartsText('procedure', mBody) or StartsText('function', mBody) or StartsText('reference', mBody) then
    Result := mBody;
end;

procedure TTypeMismatchCheck.Mismatch(ANode: TSyntaxNode; const ATarget, ASource: string);
begin
  FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('Inkompatible Typen: ''%s'' und ''%s'' ' +
    '(wie E2010).', [ATarget, ASource]), TRuleConfidence.High);
end;

procedure TTypeMismatchCheck.CheckAssignment(ANode: TSyntaxNode);
var
  mTarget, mSource: TValueType;
  mSymbol, mType: TResolvedSymbol;
  mProcedural: string;
  mShape: TProcShape;
  mSourceNode: TSyntaxNode;
begin
  if ANode.ChildCount <> 2 then
    Exit;
  mSourceNode := Unwrapped(ANode[1]);
  mTarget := TargetValue(ANode[0], mSymbol, mType);
  if mSymbol.Name = '' then
    Exit;
  mProcedural := ProceduralText(ANode[0], mSymbol, mType);
  if mProcedural <> '' then
  begin
    if ParseShape(mProcedural, False, mShape) then
      CheckProcedural(ANode, mShape);
    Exit;
  end;
  if not mTarget.Known then
    Exit;
  // Eine Prozedur hat keinen Wert (dcc: E2010 mit "procedure, untyped pointer or untyped parameter").
  if IsDataCategory(mTarget) and (mSourceNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
    IsProcedure(mSourceNode) then
  begin
    Mismatch(mSourceNode, mTarget.Name, cNoResultName);
    Exit;
  end;
  mSource := ValueOf(mSourceNode);
  if TTypeCompatibility.AssignIncompatible(mTarget, mSource) then
    Mismatch(mSourceNode, mTarget.Name, ShownName(mSource));
end;

procedure TTypeMismatchCheck.CheckProcedural(ANode: TSyntaxNode; const ATarget: TProcShape);
var
  mSource: TSyntaxNode;
  mCandidates: TArray<TResolvedSymbol>;
  mCandidate: TResolvedSymbol;
  mShape: TProcShape;
  mMatch, mFirst: TProcMatch;
  mFormal, mActual, mTypeFormal, mTypeActual: string;
  mAllFail, mHasType: Boolean;
  mIndex: Integer;

  function Compare(const ACandidate: TResolvedSymbol; const AShape: TProcShape; out AFormal, AActual: string): TProcMatch;
  var
    mParam: Integer;
    mIsMethod: Boolean;
    mLeft, mRight: TValueType;
  begin
    AFormal := '';
    AActual := '';
    if AShape.IsFunction <> ATarget.IsFunction then
      Exit(TProcMatch.Unsure);
    mIsMethod := (ACandidate.SymbolKind = TIndexSymbolKind.Method) and not MatchText('static', ACandidate.Directives);
    if mIsMethod <> ATarget.OfObject then
      Exit(TProcMatch.MethodKind);
    if Length(AShape.Params) <> Length(ATarget.Params) then
      Exit(TProcMatch.Parameters);
    for mParam := 0 to High(ATarget.Params) do
      if NormalizedModifier(ATarget.Params[mParam].Modifier) <> NormalizedModifier(AShape.Params[mParam].Modifier) then
        Exit(TProcMatch.Parameters);
    Result := TProcMatch.Yes;
    for mParam := 0 to High(ATarget.Params) do
    begin
      if TTypeIdentity.Same(ATarget.Params[mParam].TypeName, AShape.Params[mParam].TypeName) then
        Continue;
      mLeft := TValueType.FromBuiltin(TTypeIdentity.Clean(ATarget.Params[mParam].TypeName));
      mRight := TValueType.FromBuiltin(TTypeIdentity.Clean(AShape.Params[mParam].TypeName));
      if (mLeft.Kind <> TValueKind.Builtin) or (mRight.Kind <> TValueKind.Builtin) or
        TTypeCompatibility.PlatformDependent(mLeft.Name) or TTypeCompatibility.PlatformDependent(mRight.Name) then
        Exit(TProcMatch.Unsure);
      if AFormal = '' then
      begin
        AFormal := mLeft.Name;
        AActual := mRight.Name;
      end;
      Result := TProcMatch.ParameterType;
    end;
    if (Result = TProcMatch.Yes) and AShape.IsFunction and
      not TTypeIdentity.Same(AShape.ResultType, ATarget.ResultType) then
      Result := TProcMatch.Unsure;
  end;

begin
  if ATarget.Reference then
    Exit;
  mSource := Unwrapped(ANode[1]);
  if not RoutineCandidates(mSource, mCandidates) then
    Exit;
  mAllFail := True;
  mHasType := False;
  mFirst := TProcMatch.Yes;
  mTypeFormal := '';
  mTypeActual := '';
  for mIndex := 0 to High(mCandidates) do
  begin
    mCandidate := mCandidates[mIndex];
    if not ParseShape(mCandidate.Signature, True, mShape) then
      Exit;
    // Eine Funktion ohne Pflichtparameter kann hier auch aufgerufen werden.
    if mShape.IsFunction and ((Length(mShape.Params) = 0) or (mShape.Params[0].DefaultValue <> '')) then
      Exit;
    mMatch := Compare(mCandidate, mShape, mFormal, mActual);
    if mIndex = 0 then
      mFirst := mMatch;
    if mMatch in [TProcMatch.Yes, TProcMatch.Unsure] then
      mAllFail := False;
    if (mMatch = TProcMatch.ParameterType) and not mHasType then
    begin
      mHasType := True;
      mTypeFormal := mFormal;
      mTypeActual := mActual;
    end;
  end;
  if not mAllFail then
    Exit;
  if Length(mCandidates) > 1 then
  begin
    // Von den Überladungen passt keine: dcc nennt die Typen der ersten mit gleich vielen Parametern.
    if mHasType then
      Mismatch(mSource, mTypeFormal, mTypeActual);
    Exit;
  end;
  case mFirst of
    TProcMatch.MethodKind:
      if ATarget.OfObject then
        FReport.Add(TTextRange.Create(mSource.StartPos, mSource.EndPos), Format('Inkompatible Typen: ' +
          '''Methodenzeiger und reguläre Prozedur''; %s ist keine Methode eines Objekts (wie E2009).',
          [NodeText(mSource)]), TRuleConfidence.High)
      else
        FReport.Add(TTextRange.Create(mSource.StartPos, mSource.EndPos), Format('Inkompatible Typen: ' +
          '''Reguläre Prozedur und Methodenzeiger''; %s ist eine Methode, der Typ hat kein of object (wie E2009).',
          [NodeText(mSource)]), TRuleConfidence.High);
    TProcMatch.Parameters, TProcMatch.ParameterType:
      FReport.Add(TTextRange.Create(mSource.StartPos, mSource.EndPos), Format('Inkompatible Typen: ''Liste der ' +
        'Parameter ist unterschiedlich''; %s passt nicht zum prozeduralen Typ (wie E2009).', [NodeText(mSource)]),
        TRuleConfidence.High);
  else
    // Yes und Unsure sind oben ausgeschieden.
  end;
end;

procedure TTypeMismatchCheck.CheckDefault(ANode: TSyntaxNode);
var
  mTypeNode, mValueNode: TSyntaxNode;
  mTarget, mSource: TValueType;
begin
  // Parameter: [Attribute] TypeReference Standardwert.
  if ANode.ChildCount < 2 then
    Exit;
  mTypeNode := ANode[ANode.ChildCount - 2];
  mValueNode := ANode[ANode.ChildCount - 1];
  if (mTypeNode.Kind <> TSyntaxKind.TypeReference) or not TExpressionTypes.IsExpression(mValueNode) then
    Exit;
  mTarget := TypeValueFrom(FLocal, TIndexExtractor.TypeText(mTypeNode));
  if not mTarget.Known then
    Exit;
  mSource := ValueOf(mValueNode);
  if TTypeCompatibility.AssignIncompatible(mTarget, mSource) then
    Mismatch(mValueNode, mTarget.Name, ShownName(mSource));
end;

procedure TTypeMismatchCheck.CheckIntrinsic(ANode: TSyntaxNode; const AName: string);
var
  mValue: TValueType;
begin
  if (MatchText(AName, ['Inc', 'Dec']) and (ANode.ChildCount = 3)) then
  begin
    mValue := ValueOf(ANode[2]);
    if (mValue.Kind = TValueKind.Builtin) and (mValue.Category in [TExpressionCategory.Float,
      TExpressionCategory.Currency_, TExpressionCategory.String_]) then
      FReport.Add(TTextRange.Create(ANode[2].StartPos, ANode[2].EndPos), Format('Inkompatible Typen: %s erwartet ' +
        'als Schrittweite eine Ganzzahl, %s ist %s (wie E2008).', [AName, NodeText(ANode[2]), mValue.Name]),
        TRuleConfidence.High);
  end
  else if SameText(AName, 'Ptr') and (ANode.ChildCount = 2) then
  begin
    mValue := ValueOf(ANode[1]);
    if (mValue.Kind = TValueKind.Builtin) and (mValue.Category = TExpressionCategory.String_) then
      FReport.Add(TTextRange.Create(ANode[1].StartPos, ANode[1].EndPos), Format('Inkompatible Typen: Ptr erwartet ' +
        'eine Adresse als Ganzzahl, %s ist %s (wie E2008).', [NodeText(ANode[1]), mValue.Name]), TRuleConfidence.High);
  end;
end;

procedure TTypeMismatchCheck.CheckCast(ANode: TSyntaxNode; const AType: TResolvedSymbol);
var
  mTarget, mSource: TValueType;
  mWidth: Integer;
  mSigned, mInvalid: Boolean;
begin
  if (ANode.ChildCount <> 2) or not AType.Builtin then
    Exit;
  mTarget := TValueType.FromBuiltin(AType.Name);
  mSource := ValueOf(ANode[1]);
  if (mTarget.Kind <> TValueKind.Builtin) or (mSource.Kind <> TValueKind.Builtin) then
    Exit;
  TExpressionTypes.CategoryOf(mTarget.Name, mWidth, mSigned);
  // Ein langer String ist ein Zeiger: in Byte oder Word passt er auf keiner Plattform.
  mInvalid := (mTarget.Category = TExpressionCategory.Integer_) and (mWidth in [1, 2]) and
    TTypeCompatibility.IsLongString(mSource.Name);
  // Gleitkomma nach Ordinal geht nur über Round oder Trunc.
  mInvalid := mInvalid or ((mTarget.Category in [TExpressionCategory.Integer_, TExpressionCategory.Char_,
    TExpressionCategory.Boolean_]) and (mSource.Category = TExpressionCategory.Float));
  if mInvalid then
    FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('Ungültige Typumwandlung: %s nach %s ' +
      '(wie E2089).', [mSource.Name, mTarget.Name]), TRuleConfidence.High);
end;

procedure TTypeMismatchCheck.CheckVarArgument(AArgument: TSyntaxNode; const AFormal: TValueType);
var
  mArgument, mDecl: TSyntaxNode;
  mSymbol, mType: TResolvedSymbol;
  mFound: Boolean;
  mActual: TValueType;
begin
  mArgument := Unwrapped(AArgument);
  if not (mArgument.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
    Exit;
  if not FScope.Resolver.NodeType(Tree, FScope.FileName, mArgument, mSymbol, mType, mFound) or not mFound or
    not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) or
    not FScope.DeclarationSure(mSymbol, mArgument) or HiddenMember(mArgument, mSymbol) then
    Exit;
  // const-Parameter meldet invalid-var-argument (wie E2197).
  if mSymbol.IsParameter and (mSymbol.Kind = TResolvedKind.Local) then
  begin
    mDecl := DeclarationAt(mSymbol.SelectionRange.StartPos);
    if (mDecl = nil) or (mDecl.Kind <> TSyntaxKind.Parameter) or
      (mDecl.Modifier in [TParameterModifier.ConstParam, TParameterModifier.ConstRefParam]) then
      Exit;
  end;
  mActual := ValueOfSymbol(mSymbol, mType);
  if TTypeCompatibility.VarParamDiffers(AFormal, mActual) then
    FReport.Add(TTextRange.Create(mArgument.StartPos, mArgument.EndPos), Format('Die Typen der tatsächlichen und ' +
      'formalen var-Parameter müssen übereinstimmen: %s und %s (wie E2033).', [AFormal.Name, mActual.Name]),
      TRuleConfidence.High);
end;

procedure TTypeMismatchCheck.CheckCall(ANode: TSyntaxNode);
var
  mCallee: TSyntaxNode;
  mCandidates: TArray<TResolvedSymbol>;
  mCandidate: TResolvedSymbol;
  mShape: TProcShape;
  mUnit: TUnitIndex;
  mIndex: Integer;
  mParam: TSignatureParameter;
  mFormal, mActual: TValueType;
  mModifier: string;
begin
  if ANode.ChildCount = 0 then
    Exit;
  mCallee := ANode[0];
  if not (mCallee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
    (mCallee.FindChild(TSyntaxKind.GenericArgs) <> nil) then
    Exit;
  if BuiltinCast(mCallee, mCandidate) then
  begin
    CheckCast(ANode, mCandidate);
    Exit;
  end;
  if IsIntrinsic(mCallee) then
  begin
    CheckIntrinsic(ANode, mCallee.Name);
    Exit;
  end;
  mCandidates := FScope.Resolver.CallCandidates(Tree, FScope.FileName, mCallee);
  if Length(mCandidates) = 0 then
    Exit;
  if mCandidates[0].IsType then
  begin
    CheckCast(ANode, mCandidates[0]);
    Exit;
  end;
  if Length(mCandidates) <> 1 then
    Exit;
  mCandidate := mCandidates[0];
  if not (mCandidate.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_]) or
    mCandidate.Builtin or (mCandidate.TypeParams <> '') or (Length(mCandidate.Bindings) > 0) or
    (Length(mCandidate.Overloads) > 0) or (Length(mCandidate.VariantParams) > 1) or
    MatchText('overload', mCandidate.Directives) or ContainsText(mCandidate.Signature, 'overload') or
    not FScope.DeclarationSure(mCandidate, mCallee) or HiddenMember(mCallee, mCandidate) then
    Exit;
  if not ParseShape(StringReplace(mCandidate.Signature, 'constructor', 'procedure', [rfIgnoreCase]), True, mShape) or
    (ANode.ChildCount - 1 > Length(mShape.Params)) or not FScope.Resolver.DeclaringUnit(mCandidate, mUnit) then
    Exit;
  for mIndex := 1 to ANode.ChildCount - 1 do
  begin
    mParam := mShape.Params[mIndex - 1];
    if (mParam.TypeName = '') or StartsText('array', Trim(mParam.TypeName)) then
      Continue;
    mFormal := TypeValueFrom(mUnit, mParam.TypeName);
    if not mFormal.Known then
      Continue;
    mModifier := NormalizedModifier(mParam.Modifier);
    if (mModifier = 'var') or (mModifier = 'out') then
      CheckVarArgument(ANode[mIndex], mFormal)
    else
    begin
      mActual := ValueOf(ANode[mIndex]);
      if TTypeCompatibility.AssignIncompatible(mFormal, mActual) then
        Mismatch(ANode[mIndex], mFormal.Name, ShownName(mActual));
    end;
  end;
end;

procedure TTypeMismatchCheck.CheckIndexer(ANode: TSyntaxNode);
var
  mSymbol, mType: TResolvedSymbol;
  mFound: Boolean;
  mUnit: TUnitIndex;
  mIndexSymbol: TIndexSymbol;
  mDefaults, mIndex: Integer;
  mFormal, mActual: TValueType;
begin
  if (ANode.ChildCount < 2) or not FScope.Resolver.NodeType(Tree, FScope.FileName, ANode, mSymbol, mType, mFound) or
    (mSymbol.SymbolKind <> TIndexSymbolKind.Property_) or (mSymbol.MaxArgs = 0) or
    (Length(mSymbol.ParamTypes) < ANode.ChildCount - 1) or (Length(mSymbol.Overloads) > 0) or
    not FScope.DeclarationSure(mSymbol, ANode) or not FScope.Resolver.DeclaringUnit(mSymbol, mUnit) then
    Exit;
  // Überladene Array-Properties (zwei default-Properties bzw. gleiche Namen) wählt dcc nach den Argumenten.
  mDefaults := 0;
  for mIndexSymbol in mUnit.Symbols do
    if (mIndexSymbol.Kind = TIndexSymbolKind.Property_) and SameText(mIndexSymbol.Container, mSymbol.Container) and
      (SameText(mIndexSymbol.Name, mSymbol.Name) or (mSymbol.IsDefault and mIndexSymbol.IsDefault)) then
      Inc(mDefaults);
  if mDefaults <> 1 then
    Exit;
  for mIndex := 1 to ANode.ChildCount - 1 do
  begin
    mFormal := TypeValueFrom(mUnit, mSymbol.ParamTypes[mIndex - 1]);
    mActual := ValueOf(ANode[mIndex]);
    if TTypeCompatibility.AssignIncompatible(mFormal, mActual) then
      Mismatch(ANode[mIndex], mFormal.Name, ShownName(mActual));
  end;
end;

procedure TTypeMismatchCheck.CheckBinary(ANode: TSyntaxNode);
var
  mOperator: string;
  mLeft, mRight: TValueType;
  mSymbol, mType: TResolvedSymbol;
  mFound: Boolean;
  mRightNode: TSyntaxNode;
begin
  if ANode.ChildCount <> 2 then
    Exit;
  mOperator := LowerCase(ANode.Name);
  if mOperator = 'is' then
  begin
    // X is Integer: rechts muss eine Klasse stehen.
    mRightNode := Unwrapped(ANode[1]);
    if (mRightNode.Kind = TSyntaxKind.Identifier) and not BuiltinCast(mRightNode, mSymbol) and
      not (FScope.Resolver.NodeType(Tree, FScope.FileName, mRightNode, mSymbol, mType, mFound) and mSymbol.IsType) then
      Exit;
    if mSymbol.Builtin and IsDataCategory(TValueType.FromBuiltin(mSymbol.Name)) then
      FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('Der Operator is braucht rechts eine ' +
        'Klasse; %s ist keine (wie E2015).', [mSymbol.Name]), TRuleConfidence.High);
    Exit;
  end;
  mLeft := ValueOf(ANode[0]);
  mRight := ValueOf(ANode[1]);
  case TTypeCompatibility.OperatorFit(mOperator, mLeft, mRight) of
    TOperatorFit.NotApplicable:
      FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('Der Operator %s ist auf %s und %s nicht ' +
        'anwendbar (wie E2015).', [ANode.Name, mLeft.Name, mRight.Name]), TRuleConfidence.High);
    TOperatorFit.Incompatible:
      Mismatch(ANode, ShownName(mLeft), ShownName(mRight));
  else
    // Fits und Unknown: still.
  end;
end;

procedure TTypeMismatchCheck.CheckUnary(ANode: TSyntaxNode);
var
  mOperand: TValueType;
begin
  if (ANode.ChildCount <> 1) or (ANode.Name = '@') then
    Exit;
  mOperand := ValueOf(ANode[0]);
  if TTypeCompatibility.UnaryNotApplicable(ANode.Name, mOperand) then
    FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('Der Operator %s ist auf %s nicht ' +
      'anwendbar (wie E2015).', [ANode.Name, mOperand.Name]), TRuleConfidence.High);
end;

procedure TTypeMismatchCheck.Run;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(Tree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      case mNode.Kind of
        // with verdeckt Namen über den Typ des Objekts; Assembler hat keine Pascal-Typen.
        TSyntaxKind.WithStatement, TSyntaxKind.AsmBlock:
          Continue;
        TSyntaxKind.AssignStatement:
          CheckAssignment(mNode);
        TSyntaxKind.Parameter:
          CheckDefault(mNode);
        TSyntaxKind.Call:
          CheckCall(mNode);
        TSyntaxKind.IndexAccess:
          CheckIndexer(mNode);
        TSyntaxKind.BinaryExpr:
          CheckBinary(mNode);
        TSyntaxKind.UnaryExpr:
          CheckUnary(mNode);
      else
        // Übrige Knoten nur durchlaufen.
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
        mPending.Push(mNode[mIndex]);
    end;
  finally
    mPending.Free;
  end;
end;

{ TTypeMismatchRule }

function TTypeMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(TypeMismatchRuleId, TRuleSeverity.Error, 'Inkompatible Typen');
end;

procedure TTypeMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TTypeMismatchCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  mCheck := TTypeMismatchCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

procedure RegisterTypeMismatchRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TTypeMismatchRule.Create);
end;

end.
