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
//                       (wie E2010). Auch als Argument eines Parameters von
//                       prozeduralem Typ.
//                     - Routine an eine Methodenreferenz (reference to, auch
//                       generisch wie TFunc<string, TArray<string>>) mit anderer
//                       Zahl, Art (const, var, out) oder anderen Typen der
//                       Parameter (#1897, wie E2010), als Zuweisung und als
//                       Argument.
//                     - Parameterlose Funktion, deren Ergebnis genau den
//                       prozeduralen Typ des Ziels hat, ohne () zugewiesen oder
//                       übergeben (#1899, wie E2010): Delphi nimmt dann die
//                       Funktion selbst. Korrektur: () ergänzen.
//                     Sonst keine Korrektur: Welche Seite falsch ist, weiß nur
//                     der Entwickler.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cTypeMismatchRuleId = 'type-mismatch';

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
  System.RegularExpressions,
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
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTypeMismatchText = (Incompatible, MethodVsProc, ProcVsMethod, ParamList, IncStep, PtrArg, InvalidCast,
    VarParamTypes, IsNeedsClass, OperatorBinary, OperatorUnary, ReferenceParams, NotCalled, AddParens, Title);

const
  cTexts: array[TTypeMismatchText] of TAtlasText = (
    (De: 'Inkompatible Typen: ''%s'' und ''%s'' (wie E2010).';
     En: 'Incompatible types: ''%s'' and ''%s'' (like E2010).'),
    (De: 'Inkompatible Typen: ''Methodenzeiger und reguläre Prozedur''; %s ist keine Methode eines Objekts (wie ' +
      'E2009).';
     En: 'Incompatible types: ''method pointer and regular procedure''; %s is not a method of an object (like E2009).'),
    (De: 'Inkompatible Typen: ''Reguläre Prozedur und Methodenzeiger''; %s ist eine Methode, der Typ hat kein of ' +
      'object (wie E2009).';
     En: 'Incompatible types: ''regular procedure and method pointer''; %s is a method, the type has no of object ' +
      '(like E2009).'),
    (De: 'Inkompatible Typen: ''Liste der Parameter ist unterschiedlich''; %s passt nicht zum prozeduralen Typ (wie ' +
      'E2009).';
     En: 'Incompatible types: ''parameter lists differ''; %s does not fit the procedural type (like E2009).'),
    (De: 'Inkompatible Typen: %s erwartet als Schrittweite eine Ganzzahl, %s ist %s (wie E2008).';
     En: 'Incompatible types: %s expects an integer as step, %s is %s (like E2008).'),
    (De: 'Inkompatible Typen: Ptr erwartet eine Adresse als Ganzzahl, %s ist %s (wie E2008).';
     En: 'Incompatible types: Ptr expects an address as integer, %s is %s (like E2008).'),
    (De: 'Ungültige Typumwandlung: %s nach %s (wie E2089).'; En: 'Invalid typecast: %s to %s (like E2089).'),
    (De: 'Die Typen der tatsächlichen und formalen var-Parameter müssen übereinstimmen: %s und %s (wie E2033).';
     En: 'Types of actual and formal var parameters must be identical: %s and %s (like E2033).'),
    (De: 'Der Operator is braucht rechts eine Klasse; %s ist keine (wie E2015).';
     En: 'The operator is needs a class on the right; %s is none (like E2015).'),
    (De: 'Der Operator %s ist auf %s und %s nicht anwendbar (wie E2015).';
     En: 'The operator %s is not applicable to %s and %s (like E2015).'),
    (De: 'Der Operator %s ist auf %s nicht anwendbar (wie E2015).';
     En: 'The operator %s is not applicable to %s (like E2015).'),
    (De: 'Inkompatible Typen: ''%s'' und ''Procedure''; die Parameter von %s passen nicht zur Methodenreferenz ' +
      '(Zahl, const/var/out oder Typ, wie E2010).';
     En: 'Incompatible types: ''%s'' and ''Procedure''; the parameters of %s do not fit the method reference ' +
      '(count, const/var/out or type, like E2010).'),
    (De: 'Inkompatible Typen: ''%s'' und ''Procedure''; %s liefert %s, ohne () steht der Name aber für die ' +
      'Funktion selbst (wie E2010).';
     En: 'Incompatible types: ''%s'' and ''Procedure''; %s returns %s, but without () the name stands for the ' +
      'function itself (like E2010).'),
    (De: '() ergänzen'; En: 'Add ()'),
    (De: 'Inkompatible Typen'; En: 'Incompatible types'));

{$SCOPEDENUMS OFF}

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

  /// <summary>Urteil über alle Kandidaten einer Zuweisung an einen prozeduralen Typ.</summary>
  TProcVerdict = record
    First: TProcMatch;
    HasType: Boolean;
    Formal: string;
    Actual: string;
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
    function NodeText(ANode: TSyntaxNode): string;
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
    function ProceduralText(const ASymbol, AType: TResolvedSymbol): string;
    function ProceduralTarget(const ASymbol, AType: TResolvedSymbol; out AShape: TProcShape;
      out AName: string): Boolean;
    function NotCalled(ASource: TSyntaxNode; const ATargetName: string): Boolean;
    function RoutineCandidates(ANode: TSyntaxNode; out ACandidates: TArray<TResolvedSymbol>): Boolean;
    procedure Mismatch(ANode: TSyntaxNode; const ATarget, ASource: string);
    procedure CheckAssignment(ANode: TSyntaxNode);
    procedure CheckProcedural(ASource: TSyntaxNode; const ATarget: TProcShape; const ATargetName: string);
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
  begin
    if AText[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
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
end;

const
  // Aufrufkonventionen, die in einem Prozedurtyp direkt hinter procedure bzw. function stehen dürfen.
  cConventions: array[0..4] of string = ('stdcall', 'cdecl', 'register', 'pascal', 'safecall');

/// <summary>reference to, class und das Schlüsselwort procedure bzw. function von AText abtrennen; False ohne
/// Schlüsselwort.</summary>
function StripKind(var AText: string; var AShape: TProcShape): Boolean;
begin
  Result := True;
  if StartsText('reference to ', AText) then
  begin
    AShape.Reference := True;
    AText := Trim(Copy(AText, 14, MaxInt));
  end;
  if StartsText('class ', AText) then
  begin
    AText := Trim(Copy(AText, 7, MaxInt));
  end;
  if StartsText('procedure', AText) then
  begin
    AText := TrimLeft(Copy(AText, 10, MaxInt));
  end
  else if StartsText('function', AText) then
  begin
    AShape.IsFunction := True;
    AText := TrimLeft(Copy(AText, 9, MaxInt));
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Beginnt AText mit einer Aufrufkonvention?</summary>
function StartsWithConvention(const AText: string): Boolean;
var
  mConvention: string;
begin
  for mConvention in cConventions do
  begin
    if StartsText(mConvention, AText) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Index des ersten Zeichens aus AStops in AText ab 1; Length + 1 ohne.</summary>
function StopAt(const AText: string; const AStops: TSysCharSet): Integer;
begin
  Result := 1;
  while (Result <= Length(AText)) and not CharInSet(AText[Result], AStops) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Name überspringen (AWithName) bzw. prüfen, dass kein Name folgt; False bei einem Namen im Typ.
/// </summary>
function SkipName(var AText: string; AWithName: Boolean): Boolean;
begin
  Result := True;
  if AWithName then
  begin
    // Name bis zur Klammer, zum Doppelpunkt oder zum Semikolon (TKlasse.Machen, Foo<T>).
    AText := TrimLeft(Copy(AText, StopAt(AText, ['(', ':', ';', ' ']), MaxInt));
  end
  else if AText <> '' then
  begin
    Result := CharInSet(AText[1], ['(', ':', ';', 'o', 'O']) or StartsWithConvention(AText);
  end;
end;

/// <summary>Parameterliste in Klammern lesen, wenn AText damit beginnt; False ohne schließende Klammer.</summary>
function ReadParams(var AText: string; var AShape: TProcShape): Boolean;
var
  mRest: string;
  mClose: Integer;
begin
  Result := True;
  if not StartsStr('(', AText) then
  begin
    Exit;
  end;
  mRest := InParens(AText, 1, mClose);
  Result := mClose > 0;
  if Result then
  begin
    AShape.Params := TChangeSignature.ParseParameters(mRest);
    AText := TrimLeft(Copy(AText, mClose + 1, MaxInt));
  end;
end;

/// <summary>Ergebnistyp hinter dem Doppelpunkt lesen, wenn AText damit beginnt; Leerraum in und vor spitzen
/// Klammern gehört dazu ("TProc &lt;string&gt;" aus dem Index, "TFunc&lt;string, Integer&gt;").</summary>
procedure ReadResult(var AText: string; var AShape: TProcShape);
var
  mPosition, mDepth: Integer;
begin
  if not StartsStr(':', AText) then
  begin
    Exit;
  end;
  AText := TrimLeft(Copy(AText, 2, MaxInt));
  mPosition := 1;
  mDepth := 0;
  while (mPosition <= Length(AText)) and (AText[mPosition] <> ';') and ((AText[mPosition] <> ' ') or (mDepth > 0) or
    StartsStr('<', TrimLeft(Copy(AText, mPosition, MaxInt)))) do
  begin
    if AText[mPosition] = '<' then
    begin
      Inc(mDepth);
    end
    else if AText[mPosition] = '>' then
    begin
      Dec(mDepth);
    end;
    Inc(mPosition);
  end;
  AShape.ResultType := Copy(AText, 1, mPosition - 1);
  AText := TrimLeft(Copy(AText, mPosition, MaxInt));
end;

/// <summary>Kopf "procedure(A: Integer) of object", "reference to function: Boolean" bzw. einer Routine
/// "class procedure TKlasse.Machen; static;" (mit Namen, AWithName) zerlegen. False, wenn er nicht lesbar ist.
/// </summary>
function ParseShape(const AText: string; AWithName: Boolean; out AShape: TProcShape): Boolean;
var
  mText, mWord: string;
begin
  AShape := Default(TProcShape);
  mText := Trim(AText);
  Result := StripKind(mText, AShape) and SkipName(mText, AWithName) and ReadParams(mText, AShape);
  if not Result then
  begin
    Exit;
  end;
  ReadResult(mText, AShape);
  // of object und Direktiven.
  for mWord in mText.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    if SameText(mWord, 'object') then
    begin
      AShape.OfObject := True;
    end;
  end;
end;

function NormalizedModifier(const AModifier: string): string;
var
  mWords: TArray<string>;
begin
  // "[ref] const" → const.
  mWords := LowerCase(Trim(AModifier)).Split([' '], TStringSplitOptions.ExcludeEmpty);
  Result := '';
  if Length(mWords) > 0 then
  begin
    Result := mWords[High(mWords)];
  end;
end;

function IsStaticArrayText(const AText: string): Boolean;
var
  mText: string;
  mBracket, mOf: Integer;
begin
  mText := LowerCase(Trim(AText));
  if StartsStr('packed ', mText) then
  begin
    mText := Trim(Copy(mText, 8, MaxInt));
  end;
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
  begin
    Exit('Pointer');
  end;
  if AValue.Category = TExpressionCategory.Set_ then
  begin
    mElement := TValueType.FromBuiltin(TTypeCompatibility.SetElement(AValue.Name));
    if mElement.Category = TExpressionCategory.Integer_ then
    begin
      Result := 'Integer';
    end
    else if mElement.Category = TExpressionCategory.Char_ then
    begin
      Result := 'AnsiChar';
    end;
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

/// <summary>AText mit den gebundenen Typparametern ABindings ("T=string") eingesetzt, je ganzes Wort.</summary>
function BoundText(const AText: string; const ABindings: TArray<string>): string;
var
  mIndex, mStart: Integer;
  mWord, mBinding: string;
begin
  Result := '';
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if not CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '_']) then
    begin
      Result := Result + AText[mIndex];
      Inc(mIndex);
      Continue;
    end;
    mStart := mIndex;
    while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '_', '0'..'9', '.']) do
    begin
      Inc(mIndex);
    end;
    mWord := Copy(AText, mStart, mIndex - mStart);
    for mBinding in ABindings do
    begin
      if SameText(Copy(mBinding, 1, Pos('=', mBinding) - 1), mWord) then
      begin
        mWord := Copy(mBinding, Pos('=', mBinding) + 1, MaxInt);
        Break;
      end;
    end;
    Result := Result + mWord;
  end;
end;

/// <summary>Name des Typs wie bei dcc: TFunc&lt;string,TArray&lt;string&gt;&gt; mit den gebundenen Typargumenten.
/// </summary>
function BoundName(const AType: TResolvedSymbol): string;
var
  mBinding: string;
  mArguments: TArray<string>;
begin
  Result := AType.Name;
  mArguments := nil;
  for mBinding in AType.Bindings do
  begin
    // Ohne Unit-Qualifizierer wie bei dcc: System.TArray<string> → TArray<string>.
    mArguments := mArguments + [TRegEx.Replace(StringReplace(Copy(mBinding, Pos('=', mBinding) + 1, MaxInt), ' ', '',
      [rfReplaceAll]), '\b[A-Za-z_][A-Za-z0-9_]*\.', '')];
  end;
  if mArguments <> nil then
  begin
    Result := Result + '<' + string.Join(',', mArguments) + '>';
  end;
end;

/// <summary>Gleicher Typ als Text, Leerraum zwischen Typargumenten nicht mitgezählt.</summary>
function SameTypeText(const ALeft, ARight: string): Boolean;
begin
  Result := TTypeIdentity.Same(StringReplace(ALeft, ' ', '', [rfReplaceAll]),
    StringReplace(ARight, ' ', '', [rfReplaceAll]));
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

/// <summary>Rumpf hinter "=" der Alias-Deklaration ASymbol ohne Semikolon; False bei bedingter, fehlender oder
/// kommentierter.</summary>
function AliasBody(const ASymbol: TResolvedSymbol; out ABody: string): Boolean;
begin
  ABody := '';
  Result := (ASymbol.Condition = '') and (Pos('=', ASymbol.Signature) > 0);
  if not Result then
  begin
    Exit;
  end;
  ABody := Trim(Copy(ASymbol.Signature, Pos('=', ASymbol.Signature) + 1, MaxInt));
  if EndsStr(';', ABody) then
  begin
    ABody := Trim(Copy(ABody, 1, Length(ABody) - 1));
  end;
  Result := Pos('{', ABody) = 0;
end;

/// <summary>Passen Art (function/procedure, Methode/Routine), Anzahl und Modifizierer der Parameter von AShape zu
/// ATarget? Yes, wenn ja, sonst die erste Abweichung.</summary>
function ShapeKindMatch(const ATarget: TProcShape; const ACandidate: TResolvedSymbol;
  const AShape: TProcShape): TProcMatch;
var
  mParam: Integer;
  mIsMethod: Boolean;
begin
  if AShape.IsFunction <> ATarget.IsFunction then
  begin
    Exit(TProcMatch.Unsure);
  end;
  mIsMethod := (ACandidate.SymbolKind = TIndexSymbolKind.Method) and not MatchText('static', ACandidate.Directives);
  // Eine Methodenreferenz nimmt Methoden und freie Routinen.
  if (mIsMethod <> ATarget.OfObject) and not ATarget.Reference then
  begin
    Exit(TProcMatch.MethodKind);
  end;
  Result := TProcMatch.Parameters;
  if Length(AShape.Params) <> Length(ATarget.Params) then
  begin
    Exit;
  end;
  for mParam := 0 to High(ATarget.Params) do
  begin
    if NormalizedModifier(ATarget.Params[mParam].Modifier) <> NormalizedModifier(AShape.Params[mParam].Modifier) then
    begin
      Exit;
    end;
  end;
  Result := TProcMatch.Yes;
end;

/// <summary>Vergleicht die Parametertypen gleich langer Listen; AFormal/AActual nennen das erste abweichende Paar.
/// </summary>
function ParamTypesMatch(const ATarget, AShape: TProcShape; out AFormal, AActual: string): TProcMatch;
var
  mParam: Integer;
  mLeft, mRight: TValueType;
begin
  AFormal := '';
  AActual := '';
  Result := TProcMatch.Yes;
  for mParam := 0 to High(ATarget.Params) do
  begin
    if TTypeIdentity.Same(ATarget.Params[mParam].TypeName, AShape.Params[mParam].TypeName) then
    begin
      Continue;
    end;
    mLeft := TValueType.FromBuiltin(TTypeIdentity.Clean(ATarget.Params[mParam].TypeName));
    mRight := TValueType.FromBuiltin(TTypeIdentity.Clean(AShape.Params[mParam].TypeName));
    if (mLeft.Kind <> TValueKind.Builtin) or (mRight.Kind <> TValueKind.Builtin) or
      TTypeCompatibility.PlatformDependent(mLeft.Name) or TTypeCompatibility.PlatformDependent(mRight.Name) then
    begin
      Exit(TProcMatch.Unsure);
    end;
    if AFormal = '' then
    begin
      AFormal := mLeft.Name;
      AActual := mRight.Name;
    end;
    Result := TProcMatch.ParameterType;
  end;
end;

/// <summary>Wie die Routine ACandidate mit dem Kopf AShape zum prozeduralen Typ ATarget passt.</summary>
function CompareShape(const ATarget: TProcShape; const ACandidate: TResolvedSymbol; const AShape: TProcShape;
  out AFormal, AActual: string): TProcMatch;
begin
  AFormal := '';
  AActual := '';
  Result := ShapeKindMatch(ATarget, ACandidate, AShape);
  if Result = TProcMatch.Yes then
  begin
    Result := ParamTypesMatch(ATarget, AShape, AFormal, AActual);
  end;
  if (Result = TProcMatch.Yes) and AShape.IsFunction and
    not TTypeIdentity.Same(AShape.ResultType, ATarget.ResultType) then
  begin
    Result := TProcMatch.Unsure;
  end;
end;

/// <summary>Kopf des Kandidaten, wenn er nur als Routine (nicht als Aufruf) zugewiesen sein kann.</summary>
function AssignableShape(const ACandidate: TResolvedSymbol; out AShape: TProcShape): Boolean;
begin
  Result := ParseShape(ACandidate.Signature, True, AShape);
  // Eine Funktion ohne Pflichtparameter kann hier auch aufgerufen werden.
  if Result and AShape.IsFunction then
  begin
    Result := (Length(AShape.Params) > 0) and (AShape.Params[0].DefaultValue = '');
  end;
end;

/// <summary>True, wenn alle Kandidaten lesbar sind und keiner zu ATarget passt; AVerdict nennt die Abweichungen.
/// </summary>
function AllCandidatesFail(const ATarget: TProcShape; const ACandidates: TArray<TResolvedSymbol>;
  out AVerdict: TProcVerdict): Boolean;
var
  mIndex: Integer;
  mShape: TProcShape;
  mMatch: TProcMatch;
  mFormal, mActual: string;
begin
  AVerdict := Default(TProcVerdict);
  AVerdict.First := TProcMatch.Yes;
  Result := True;
  for mIndex := 0 to High(ACandidates) do
  begin
    if not AssignableShape(ACandidates[mIndex], mShape) then
    begin
      Exit(False);
    end;
    mMatch := CompareShape(ATarget, ACandidates[mIndex], mShape, mFormal, mActual);
    if mIndex = 0 then
    begin
      AVerdict.First := mMatch;
    end;
    Result := Result and not (mMatch in [TProcMatch.Yes, TProcMatch.Unsure]);
    if (mMatch = TProcMatch.ParameterType) and not AVerdict.HasType then
    begin
      AVerdict.HasType := True;
      AVerdict.Formal := mFormal;
      AVerdict.Actual := mActual;
    end;
  end;
end;

/// <summary>Bezeichner oder Memberzugriff ohne generische Argumente.</summary>
function IsPlainCallee(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
    (ANode.FindChild(TSyntaxKind.GenericArgs) = nil);
end;

/// <summary>Kandidat ohne Generik, Bindungen und Überladungen, dessen Parameter fest stehen.</summary>
function IsFixedRoutine(const ACandidate: TResolvedSymbol): Boolean;
begin
  Result := (ACandidate.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine,
    TIndexSymbolKind.Constructor_]) and not ACandidate.Builtin and (ACandidate.TypeParams = '');
  Result := Result and (Length(ACandidate.Bindings) = 0) and (Length(ACandidate.Overloads) = 0);
  Result := Result and (Length(ACandidate.VariantParams) <= 1) and not MatchText('overload', ACandidate.Directives);
  Result := Result and not ContainsText(ACandidate.Signature, 'overload');
end;

function TTypeMismatchCheck.NodeText(ANode: TSyntaxNode): string;
begin
  Result := FScope.Text(ANode);
  if Length(Result) > TExpressionTypes.cMaxExpressionLength then
  begin
    Result := Copy(Result, 1, TExpressionTypes.cMaxExpressionLength - 1) + #$2026;
  end;
end;

/// <summary>Innerste Deklaration in ATree, die APosition enthält; nil ohne.</summary>
function DeclarationAt(ATree: TSyntaxTree; const APosition: TTextPosition): TSyntaxNode;
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
  // Iterativ (tiefe Bäume sprengen den Stapel nicht); nur in Knoten absteigen, die die Stelle enthalten. Der innerste
  // gewinnt.
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ATree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if not Covers(mNode) then
      begin
        Continue;
      end;
      if mNode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.Field, TSyntaxKind.TypeDecl,
        TSyntaxKind.ConstDecl, TSyntaxKind.InlineVar] then
      begin
        Result := mNode;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
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
  begin
    Exit;
  end;
  mDecl := DeclarationAt(FContext.Tree, ASymbol.SelectionRange.StartPos);
  if mDecl = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mDecl.ChildCount - 1 do
  begin
    mChild := mDecl[mIndex];
    if mChild.Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.ProcedureType,
      TSyntaxKind.PointerType, TSyntaxKind.SetType, TSyntaxKind.SubrangeType, TSyntaxKind.RecordType,
      TSyntaxKind.EnumType, TSyntaxKind.FileType] then
    begin
      Exit(FScope.Text(mChild));
    end;
  end;
end;

function TTypeMismatchCheck.BuiltinCast(ACallee: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
begin
  // Byte(X), wenn System nicht im Index steht.
  AType := Default(TResolvedSymbol);
  Result := (ACallee <> nil) and (ACallee.Kind = TSyntaxKind.Identifier) and
    TResolverText.IsBuiltinTypeName(ACallee.Name) and
    (Length(FScope.Resolver.CallCandidates(FContext.Tree, FScope.FileName, ACallee)) = 0);
  if Result then
  begin
    AType := BuiltinSymbol(ACallee.Name);
  end;
end;

function TTypeMismatchCheck.IsIntrinsic(ACallee: TSyntaxNode): Boolean;
var
  mCandidates: TArray<TResolvedSymbol>;
begin
  Result := False;
  if (ACallee = nil) or (ACallee.Kind <> TSyntaxKind.Identifier) then
  begin
    Exit;
  end;
  mCandidates := FScope.Resolver.CallCandidates(FContext.Tree, FScope.FileName, ACallee);
  Result := (Length(mCandidates) = 0) or mCandidates[0].Builtin or SameText(mCandidates[0].UnitName, 'System');
end;

function TTypeMismatchCheck.HiddenMember(ANode: TSyntaxNode; const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and
    FScope.Resolver.MayBeHiddenMember(FContext.Tree, FScope.FileName, ANode, ASymbol);
end;

function TTypeMismatchCheck.SameResultType(ACallee: TSyntaxNode): Boolean;
var
  mCandidates: TArray<TResolvedSymbol>;
  mCandidate: TResolvedSymbol;
begin
  // Überladungen mit verschiedenen Ergebnistypen: Welche gilt, entscheiden die Argumente.
  mCandidates := FScope.Resolver.CallCandidates(FContext.Tree, FScope.FileName, ACallee);
  for mCandidate in mCandidates do
  begin
    if not TTypeIdentity.Same(mCandidate.TypeName, mCandidates[0].TypeName) then
    begin
      Exit(False);
    end;
    // Freie Routinen mit overload führt dcc über alle eingebundenen Units zusammen (IfThen aus System.Math und
    // System.StrUtils); die Kandidaten kommen nur aus einer Unit, der Ergebnistyp ist also offen.
    if (mCandidate.Container = '') and (MatchText('overload', mCandidate.Directives) or
      ContainsText(mCandidate.Signature, 'overload')) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TTypeMismatchCheck.ValueOfType(const AType: TResolvedSymbol): TValueType;

  /// <summary>Nächstes Glied der Alias-Kette hinter ACurrent mit dem Rumpf ABody (auch eingebaut ohne System im
  /// Index).</summary>
  function NextInChain(const ACurrent: TResolvedSymbol; const ABody: string; out ANext: TResolvedSymbol): Boolean;
  var
    mUnit: TUnitIndex;
  begin
    Result := FScope.Resolver.DeclaringUnit(ACurrent, mUnit) and (Pos('.', ABody) = 0) and
      FScope.Resolver.ResolveNameFrom(mUnit, ABody, ANext) and ANext.IsType;
    if not Result and TResolverText.IsBuiltinTypeName(ABody) then
    begin
      ANext := BuiltinSymbol(ABody);
      Result := True;
    end;
  end;

  // Kette TA = TB, TB = Single Glied für Glied: Steht ein Glied in einem bedingten Zweig (TDimension = Single bzw.
  // Integer je nach {$IFDEF}), ist der Typ offen.
  function AliasValue: TValueType;
  var
    mCurrent, mNext: TResolvedSymbol;
    mBody: string;
    mDepth: Integer;
  begin
    Result := Default(TValueType);
    mCurrent := AType;
    for mDepth := 0 to cMaxDepth do
    begin
      if not AliasBody(mCurrent, mBody) then
      begin
        Exit;
      end;
      if IsStaticArrayText(mBody) then
      begin
        Exit(TValueType.Create(AType.Name, TExpressionCategory.Other, TValueKind.StaticArray));
      end;
      // type Integer: eigener Typ, für Zuweisungen aber wie Integer.
      if StartsText('type ', mBody) then
      begin
        mBody := Trim(Copy(mBody, 6, MaxInt));
      end;
      if not NextInChain(mCurrent, mBody, mNext) then
      begin
        Exit;
      end;
      if mNext.Builtin or (mNext.SymbolKind <> TIndexSymbolKind.TypeAlias) then
      begin
        Result := ValueOfType(mNext);
        // TZahl = Integer rechnet wie Integer; der Name bleibt der des Alias.
        if Result.Known then
        begin
          Result.Name := AType.Name;
        end;
        Break;
      end;
      mCurrent := mNext;
    end;
  end;

begin
  Result := Default(TValueType);
  if (AType.Name = '') or (AType.Condition <> '') then
  begin
    Exit;
  end;
  if AType.Builtin then
  begin
    Result := TValueType.FromBuiltin(AType.Name);
    if Result.Kind <> TValueKind.Builtin then
    begin
      Result := Default(TValueType);
    end;
    Exit;
  end;
  case AType.SymbolKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType:
      Result := TValueType.Create(AType.Name, TExpressionCategory.Other, TValueKind.ClassLike);
    TIndexSymbolKind.EnumType:
      Result := TValueType.Create(AType.Name, TExpressionCategory.Other, TValueKind.Enum);
    TIndexSymbolKind.TypeAlias:
      Result := AliasValue;
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
  if (mText <> '') and not TResolverText.IsBuiltinTypeName(mText) then
  begin
    Result := Default(TValueType);
    if ASymbol.Kind = TResolvedKind.Local then
    begin
      mUnit := FLocal;
    end
    else if not FScope.Resolver.DeclaringUnit(ASymbol, mUnit) then
    begin
      Exit;
    end;
    // ResolveNameFrom liefert den Alias selbst, ResolveTypeFrom schon sein Ziel.
    if (Pos('.', mText) > 0) or not FScope.Resolver.ResolveNameFrom(mUnit, mText, mDeclared) or
      not mDeclared.IsType then
    begin
      Exit;
    end;
    Result := ValueOfType(mDeclared);
  end
  else
  begin
    Result := ValueOfType(AType);
  end;
  // Untypisierte Konstante 'a' ist auch ein Zeichen.
  if (ASymbol.SymbolKind = TIndexSymbolKind.Constant) and (ASymbol.TypeName = '') then
  begin
    Result.UntypedText := True;
  end;
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
  begin
    Exit;
  end;
  // Den Alias selbst (ResolveNameFrom), damit ValueOfType bedingte Glieder der Kette sieht.
  if FScope.Resolver.ResolveNameFrom(AUnit, mText, mType) and mType.IsType then
  begin
    Result := ValueOfType(mType);
  end
  else if TResolverText.IsBuiltinTypeName(mText) then
  begin
    // Ohne System im Index.
    Result := ValueOfType(BuiltinSymbol(mText));
  end;
end;

function TTypeMismatchCheck.DescribedValue(ANode: TSyntaxNode): TValueType;
var
  mInfo: TExpressionTypeInfo;
begin
  Result := Default(TValueType);
  mInfo := FTypes.Describe(ANode);
  if not mInfo.Found then
  begin
    Exit;
  end;
  Result := TValueType.FromBuiltin(mInfo.TypeName);
  if Result.Kind <> TValueKind.Builtin then
  begin
    Result := Default(TValueType);
  end;
end;

function TTypeMismatchCheck.LeafValue(ANode: TSyntaxNode): TValueType;

  /// <summary>Wert eines Aufrufs einer Typumwandlung oder eingebauten Routine; False bei anderen Aufrufen.
  /// </summary>
  function CallValue(out AValue: TValueType): Boolean;
  var
    mType: TResolvedSymbol;
  begin
    AValue := Default(TValueType);
    Result := True;
    if ANode.ChildCount = 0 then
    begin
      Exit;
    end;
    if BuiltinCast(ANode[0], mType) then
    begin
      if ANode.ChildCount = 2 then
      begin
        AValue := ValueOfType(mType);
      end;
    end
    else if IsIntrinsic(ANode[0]) then
    begin
      if MatchText(ANode[0].Name, cTypedIntrinsics) then
      begin
        AValue := DescribedValue(ANode);
      end;
    end
    else
    begin
      Result := False;
    end;
  end;

  /// <summary>Lässt sich ACallee über die Namensauflösung bestimmen (keine generischen Mitglieder)?</summary>
  function Resolvable(ACallee: TSyntaxNode): Boolean;
  begin
    Result := (ACallee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      (ANode.Kind = TSyntaxKind.IndexAccess);
    Result := Result and not ((ACallee.Kind = TSyntaxKind.MemberAccess) and
      (ACallee.FindChild(TSyntaxKind.GenericArgs) <> nil));
  end;

  /// <summary>Typname als Wert: S[1] ist ein Zeichen, Byte(X) ein Byte.</summary>
  function TypeNameValue(const ASymbol: TResolvedSymbol): TValueType;
  begin
    Result := Default(TValueType);
    if ((ANode.Kind = TSyntaxKind.IndexAccess) and ASymbol.Builtin) or
      ((ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2)) then
    begin
      Result := ValueOfType(ASymbol);
    end;
  end;

  /// <summary>Ist ASymbol sicher deklariert, nicht verdeckt, kein Konstruktor und hat als Routine einen
  /// eindeutigen Ergebnistyp?</summary>
  function UsableSymbol(ACallee: TSyntaxNode; const ASymbol: TResolvedSymbol; AFound: Boolean): Boolean;
  begin
    Result := AFound and FScope.DeclarationSure(ASymbol, ANode) and not HiddenMember(ACallee, ASymbol);
    Result := Result and (ASymbol.SymbolKind <> TIndexSymbolKind.Constructor_);
    if Result and (ASymbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) then
    begin
      Result := SameResultType(ACallee);
    end;
  end;

var
  mSymbol, mType: TResolvedSymbol;
  mFound: Boolean;
  mCallee: TSyntaxNode;
begin
  mCallee := ANode;
  if ANode.Kind = TSyntaxKind.Call then
  begin
    if CallValue(Result) then
    begin
      Exit;
    end;
    mCallee := ANode[0];
  end;
  Result := Default(TValueType);
  if not Resolvable(mCallee) or
    not FScope.Resolver.NodeType(FContext.Tree, FScope.FileName, ANode, mSymbol, mType, mFound) or
    (mSymbol.Kind = TResolvedKind.UnitName) then
  begin
    Exit;
  end;
  if mSymbol.IsType then
  begin
    Result := TypeNameValue(mSymbol);
  end
  else if UsableSymbol(mCallee, mSymbol, mFound) then
  begin
    Result := ValueOfSymbol(mSymbol, mType);
  end;
end;

function TTypeMismatchCheck.ComputeValue(ANode: TSyntaxNode): TValueType;

  /// <summary>Menge: nur, wenn jedes Element (bei Bereichen der Anfang) einen bekannten Wert hat.</summary>
  function SetValue(ANode: TSyntaxNode): TValueType;
  var
    mIndex: Integer;
    mElement: TSyntaxNode;
  begin
    Result := Default(TValueType);
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      mElement := ANode[mIndex];
      if mElement.Kind = TSyntaxKind.RangeExpr then
      begin
        if mElement.ChildCount = 0 then
        begin
          Exit;
        end;
        mElement := mElement[0];
      end;
      if not ValueOf(mElement).Known then
      begin
        Exit;
      end;
    end;
    Result := DescribedValue(ANode);
  end;

  function BinaryValue(ANode: TSyntaxNode): TValueType;
  var
    mOperator: string;
    mLeft: TValueType;
  begin
    Result := Default(TValueType);
    if ANode.ChildCount <> 2 then
    begin
      Exit;
    end;
    mOperator := LowerCase(ANode.Name);
    mLeft := ValueOf(ANode[0]);
    if MatchStr(mOperator, ['=', '<>', '<', '>', '<=', '>=', 'in', 'is']) then
    begin
      if mLeft.Known and ((mOperator = 'is') or ValueOf(ANode[1]).Known) then
      begin
        Result := TValueType.FromBuiltin('Boolean');
      end;
    end
    else if TTypeCompatibility.OperatorFit(mOperator, mLeft, ValueOf(ANode[1])) = TOperatorFit.Fits then
    begin
      Result := DescribedValue(ANode);
    end;
  end;

  function UnaryValue(ANode: TSyntaxNode): TValueType;
  var
    mOperand: TValueType;
  begin
    Result := Default(TValueType);
    if (ANode.ChildCount <> 1) or (ANode.Name = '@') then
    begin
      Exit;
    end;
    mOperand := ValueOf(ANode[0]);
    if mOperand.Known and not TTypeCompatibility.UnaryNotApplicable(ANode.Name, mOperand) and
      (mOperand.Kind = TValueKind.Builtin) then
    begin
      Result := DescribedValue(ANode);
    end;
  end;

var
  mNode: TSyntaxNode;
begin
  Result := Default(TValueType);
  mNode := Unwrapped(ANode);
  if mNode = nil then
  begin
    Exit;
  end;
  case mNode.Kind of
    TSyntaxKind.Literal:
      Result := DescribedValue(mNode);
    TSyntaxKind.Identifier:
      if MatchText(mNode.Name, ['nil', 'True', 'False']) then
      begin
        Result := DescribedValue(mNode);
      end
      else
      begin
        Result := LeafValue(mNode);
      end;
    TSyntaxKind.MemberAccess, TSyntaxKind.Call, TSyntaxKind.IndexAccess:
      Result := LeafValue(mNode);
    TSyntaxKind.AddressOf:
      Result := TValueType.FromBuiltin('Pointer');
    TSyntaxKind.SetConstructor:
      Result := SetValue(mNode);
    TSyntaxKind.BinaryExpr:
      Result := BinaryValue(mNode);
    TSyntaxKind.UnaryExpr:
      Result := UnaryValue(mNode);
  else
    // if-Ausdrücke, anonyme Methoden, Dereferenz, inherited: offen.
  end;
end;

function TTypeMismatchCheck.ValueOf(ANode: TSyntaxNode): TValueType;
begin
  Result := Default(TValueType);
  if (ANode = nil) or (FDepth > cMaxDepth) then
  begin
    Exit;
  end;
  if FValues.TryGetValue(ANode, Result) then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  if not FScope.Resolver.NodeType(FContext.Tree, FScope.FileName, ANode, ASymbol, AType, mFound) or
    (ASymbol.Kind = TResolvedKind.UnitName) or ASymbol.IsType then
  begin
    Exit;
  end;
  // Variablen, Felder, Properties und Parameter; Result zählt als Variable.
  if not (ASymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) then
  begin
    Exit;
  end;
  if not FScope.DeclarationSure(ASymbol, ANode) or HiddenMember(ANode, ASymbol) then
  begin
    Exit;
  end;
  if mFound then
  begin
    Result := ValueOfSymbol(ASymbol, AType);
  end
  else
  begin
    // array[0..2] of Integer ohne eigenen Typ.
    mText := DeclaredText(ASymbol);
    if IsStaticArrayText(mText) then
    begin
      Result := TValueType.Create(mText, TExpressionCategory.Other, TValueKind.StaticArray);
    end;
  end;
end;

function TTypeMismatchCheck.RoutineCandidates(ANode: TSyntaxNode; out ACandidates: TArray<TResolvedSymbol>): Boolean;
var
  mCandidate: TResolvedSymbol;

  function Usable(const ACandidate: TResolvedSymbol): Boolean;
  begin
    Result := (ACandidate.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and
      not ACandidate.Builtin;
    Result := Result and (ACandidate.Signature <> '') and (ACandidate.TypeParams = '');
    Result := Result and FScope.DeclarationSure(ACandidate, ANode) and not HiddenMember(ANode, ACandidate);
  end;

begin
  ACandidates := nil;
  Result := False;
  if not IsPlainCallee(ANode) then
  begin
    Exit;
  end;
  ACandidates := FScope.Resolver.CallCandidates(FContext.Tree, FScope.FileName, ANode);
  if Length(ACandidates) = 0 then
  begin
    Exit;
  end;
  for mCandidate in ACandidates do
  begin
    if not Usable(mCandidate) then
    begin
      Exit;
    end;
  end;
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
  begin
    Exit;
  end;
  for mCandidate in mCandidates do
  begin
    if not ParseShape(mCandidate.Signature, True, mShape) or mShape.IsFunction then
    begin
      Exit(False);
    end;
  end;
end;

function TTypeMismatchCheck.ProceduralText(const ASymbol, AType: TResolvedSymbol): string;
var
  mBody: string;
begin
  Result := '';
  if (AType.Name <> '') and not AType.Builtin and (Pos('=', AType.Signature) > 0) then
  begin
    mBody := Trim(Copy(AType.Signature, Pos('=', AType.Signature) + 1, MaxInt));
    if StartsText('procedure', mBody) or StartsText('function', mBody) or StartsText('reference', mBody) then
    begin
      Exit(mBody);
    end;
    Exit;
  end;
  if AType.Name <> '' then
  begin
    Exit;
  end;
  mBody := ASymbol.TypeName;
  if not (StartsText('procedure', mBody) or StartsText('function', mBody) or StartsText('reference', mBody)) then
  begin
    mBody := DeclaredText(ASymbol);
  end;
  if StartsText('procedure', mBody) or StartsText('function', mBody) or StartsText('reference', mBody) then
  begin
    Result := mBody;
  end;
end;

function TTypeMismatchCheck.ProceduralTarget(const ASymbol, AType: TResolvedSymbol; out AShape: TProcShape;
  out AName: string): Boolean;
var
  mText: string;
  mIndex: Integer;
begin
  AName := '';
  mText := ProceduralText(ASymbol, AType);
  Result := (mText <> '') and ParseShape(mText, False, AShape);
  if not Result then
  begin
    Exit;
  end;
  // TFunc<string, TArray<string>>: Typparameter des generischen Typs einsetzen.
  for mIndex := 0 to High(AShape.Params) do
  begin
    AShape.Params[mIndex].TypeName := BoundText(AShape.Params[mIndex].TypeName, AType.Bindings);
  end;
  AShape.ResultType := BoundText(AShape.ResultType, AType.Bindings);
  AName := mText;
  if AType.Name <> '' then
  begin
    AName := BoundName(AType);
  end;
end;

function TTypeMismatchCheck.NotCalled(ASource: TSyntaxNode; const ATargetName: string): Boolean;
var
  mCandidates: TArray<TResolvedSymbol>;
  mCandidate: TResolvedSymbol;
  mShape: TProcShape;
  mFix: TRuleFix;
begin
  Result := RoutineCandidates(ASource, mCandidates);
  if not Result then
  begin
    Exit;
  end;
  // Jede Kandidatin ist eine Funktion ohne Pflichtparameter mit genau dem Typ des Ziels als Ergebnis (#1899).
  for mCandidate in mCandidates do
  begin
    if not ParseShape(mCandidate.Signature, True, mShape) or not mShape.IsFunction or
      ((Length(mShape.Params) > 0) and (mShape.Params[0].DefaultValue = '')) or
      not SameTypeText(mShape.ResultType, ATargetName) then
    begin
      Exit(False);
    end;
  end;
  mFix := TRuleFix.Create(cTexts[TTypeMismatchText.AddParens].Text,
    [TTextEdit.Create(TTextRange.Create(ASource.EndPos, ASource.EndPos), '()')]);
  FReport.Add(TTextRange.Create(ASource.StartPos, ASource.EndPos), cTexts[TTypeMismatchText.NotCalled].Fmt(
    [ATargetName, NodeText(ASource), ATargetName]), TRuleConfidence.High, [mFix]);
end;

procedure TTypeMismatchCheck.Mismatch(ANode: TSyntaxNode; const ATarget, ASource: string);
begin
  FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), cTexts[TTypeMismatchText.Incompatible].Fmt([ATarget,
    ASource]), TRuleConfidence.High);
end;

procedure TTypeMismatchCheck.CheckAssignment(ANode: TSyntaxNode);
var
  mTarget: TValueType;
  mSymbol, mType: TResolvedSymbol;
  mProcedural: string;
  mShape: TProcShape;

  procedure CheckValue(ASource: TSyntaxNode);
  var
    mSource: TValueType;
  begin
    // Eine Prozedur hat keinen Wert (dcc: E2010 mit "procedure, untyped pointer or untyped parameter").
    if IsDataCategory(mTarget) and (ASource.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
      IsProcedure(ASource) then
    begin
      Mismatch(ASource, mTarget.Name, cNoResultName);
      Exit;
    end;
    mSource := ValueOf(ASource);
    if TTypeCompatibility.AssignIncompatible(mTarget, mSource) then
    begin
      Mismatch(ASource, mTarget.Name, ShownName(mSource));
    end;
  end;

begin
  if ANode.ChildCount <> 2 then
  begin
    Exit;
  end;
  mTarget := TargetValue(ANode[0], mSymbol, mType);
  if mSymbol.Name = '' then
  begin
    Exit;
  end;
  if ProceduralTarget(mSymbol, mType, mShape, mProcedural) then
  begin
    CheckProcedural(Unwrapped(ANode[1]), mShape, mProcedural);
  end
  else if (ProceduralText(mSymbol, mType) = '') and mTarget.Known then
  begin
    CheckValue(Unwrapped(ANode[1]));
  end;
end;

procedure TTypeMismatchCheck.CheckProcedural(ASource: TSyntaxNode; const ATarget: TProcShape;
  const ATargetName: string);
var
  mCandidates: TArray<TResolvedSymbol>;
  mVerdict: TProcVerdict;

  procedure ReportSingle;
  begin
    if ATarget.Reference and (mVerdict.First in [TProcMatch.Parameters, TProcMatch.ParameterType]) then
    begin
      FReport.Add(TTextRange.Create(ASource.StartPos, ASource.EndPos),
        cTexts[TTypeMismatchText.ReferenceParams].Fmt([ATargetName, NodeText(ASource)]), TRuleConfidence.High);
      Exit;
    end;
    case mVerdict.First of
      TProcMatch.MethodKind:
        if ATarget.OfObject then
        begin
          FReport.Add(TTextRange.Create(ASource.StartPos, ASource.EndPos), cTexts[TTypeMismatchText.MethodVsProc].Fmt(
            [NodeText(ASource)]), TRuleConfidence.High);
        end
        else
        begin
          FReport.Add(TTextRange.Create(ASource.StartPos, ASource.EndPos), cTexts[TTypeMismatchText.ProcVsMethod].Fmt(
            [NodeText(ASource)]), TRuleConfidence.High);
        end;
      TProcMatch.Parameters, TProcMatch.ParameterType:
        FReport.Add(TTextRange.Create(ASource.StartPos, ASource.EndPos),
          cTexts[TTypeMismatchText.ParamList].Fmt([NodeText(ASource)]),
          TRuleConfidence.High);
    else
      // Yes und Unsure sind oben ausgeschieden.
    end;
  end;

begin
  if (ASource.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and NotCalled(ASource, ATargetName) then
  begin
    Exit;
  end;
  if not RoutineCandidates(ASource, mCandidates) or not AllCandidatesFail(ATarget, mCandidates, mVerdict) then
  begin
    Exit;
  end;
  if Length(mCandidates) = 1 then
  begin
    ReportSingle;
  end
  else if mVerdict.HasType then
  begin
    // Von den Überladungen passt keine: dcc nennt die Typen der ersten mit gleich vielen Parametern.
    Mismatch(ASource, mVerdict.Formal, mVerdict.Actual);
  end;
end;

procedure TTypeMismatchCheck.CheckDefault(ANode: TSyntaxNode);
var
  mTypeNode, mValueNode: TSyntaxNode;
  mTarget, mSource: TValueType;
begin
  // Parameter: [Attribute] TypeReference Standardwert.
  if ANode.ChildCount < 2 then
  begin
    Exit;
  end;
  mTypeNode := ANode[ANode.ChildCount - 2];
  mValueNode := ANode[ANode.ChildCount - 1];
  if (mTypeNode.Kind <> TSyntaxKind.TypeReference) or not TExpressionTypes.IsExpression(mValueNode) then
  begin
    Exit;
  end;
  mTarget := TypeValueFrom(FLocal, TIndexExtractor.TypeText(mTypeNode));
  if not mTarget.Known then
  begin
    Exit;
  end;
  mSource := ValueOf(mValueNode);
  if TTypeCompatibility.AssignIncompatible(mTarget, mSource) then
  begin
    Mismatch(mValueNode, mTarget.Name, ShownName(mSource));
  end;
end;

procedure TTypeMismatchCheck.CheckIntrinsic(ANode: TSyntaxNode; const AName: string);
var
  mValue: TValueType;
begin
  if MatchText(AName, ['Inc', 'Dec']) and (ANode.ChildCount = 3) then
  begin
    mValue := ValueOf(ANode[2]);
    if (mValue.Kind = TValueKind.Builtin) and (mValue.Category in [TExpressionCategory.Float,
      TExpressionCategory.Currency_, TExpressionCategory.String_]) then
    begin
      FReport.Add(TTextRange.Create(ANode[2].StartPos, ANode[2].EndPos), cTexts[TTypeMismatchText.IncStep].Fmt([AName,
        NodeText(ANode[2]), mValue.Name]),
        TRuleConfidence.High);
    end;
  end
  else if SameText(AName, 'Ptr') and (ANode.ChildCount = 2) then
  begin
    mValue := ValueOf(ANode[1]);
    if (mValue.Kind = TValueKind.Builtin) and (mValue.Category = TExpressionCategory.String_) then
    begin
      FReport.Add(TTextRange.Create(ANode[1].StartPos, ANode[1].EndPos),
        cTexts[TTypeMismatchText.PtrArg].Fmt([NodeText(ANode[1]), mValue.Name]), TRuleConfidence.High);
    end;
  end;
end;

procedure TTypeMismatchCheck.CheckCast(ANode: TSyntaxNode; const AType: TResolvedSymbol);
var
  mTarget, mSource: TValueType;
  mWidth: Integer;
  mSigned, mInvalid: Boolean;
begin
  if (ANode.ChildCount <> 2) or not AType.Builtin then
  begin
    Exit;
  end;
  mTarget := TValueType.FromBuiltin(AType.Name);
  mSource := ValueOf(ANode[1]);
  if (mTarget.Kind <> TValueKind.Builtin) or (mSource.Kind <> TValueKind.Builtin) then
  begin
    Exit;
  end;
  TExpressionTypes.CategoryOf(mTarget.Name, mWidth, mSigned);
  // Ein langer String ist ein Zeiger: in Byte oder Word passt er auf keiner Plattform.
  mInvalid := (mTarget.Category = TExpressionCategory.Integer_) and (mWidth in [1, 2]) and
    TTypeCompatibility.IsLongString(mSource.Name);
  // Gleitkomma nach Ordinal geht nur über Round oder Trunc.
  mInvalid := mInvalid or ((mTarget.Category in [TExpressionCategory.Integer_, TExpressionCategory.Char_,
    TExpressionCategory.Boolean_]) and (mSource.Category = TExpressionCategory.Float));
  if mInvalid then
  begin
    FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
      cTexts[TTypeMismatchText.InvalidCast].Fmt([mSource.Name, mTarget.Name]), TRuleConfidence.High);
  end;
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
  begin
    Exit;
  end;
  if not FScope.Resolver.NodeType(FContext.Tree, FScope.FileName, mArgument, mSymbol, mType, mFound) or not mFound or
    not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) or
    not FScope.DeclarationSure(mSymbol, mArgument) or HiddenMember(mArgument, mSymbol) then
  begin
    Exit;
  end;
  // const-Parameter meldet invalid-var-argument (wie E2197).
  if mSymbol.IsParameter and (mSymbol.Kind = TResolvedKind.Local) then
  begin
    mDecl := DeclarationAt(FContext.Tree, mSymbol.SelectionRange.StartPos);
    if (mDecl = nil) or (mDecl.Kind <> TSyntaxKind.Parameter) or
      (mDecl.Modifier in [TParameterModifier.ConstParam, TParameterModifier.ConstRefParam]) then
    begin
      Exit;
    end;
  end;
  mActual := ValueOfSymbol(mSymbol, mType);
  if TTypeCompatibility.VarParamDiffers(AFormal, mActual) then
  begin
    FReport.Add(TTextRange.Create(mArgument.StartPos, mArgument.EndPos),
      cTexts[TTypeMismatchText.VarParamTypes].Fmt([AFormal.Name, mActual.Name]),
      TRuleConfidence.High);
  end;
end;

procedure TTypeMismatchCheck.CheckCall(ANode: TSyntaxNode);
var
  mCallee: TSyntaxNode;
  mCandidate: TResolvedSymbol;
  mShape: TProcShape;
  mUnit: TUnitIndex;
  mIndex: Integer;

  // Prüft Typumwandlungen und Intrinsics selbst; True mit dem einzigen Kandidaten einer Routine.
  function SingleRoutine(out ACandidate: TResolvedSymbol): Boolean;
  var
    mCandidates: TArray<TResolvedSymbol>;
  begin
    Result := False;
    if BuiltinCast(mCallee, ACandidate) then
    begin
      CheckCast(ANode, ACandidate);
      Exit;
    end;
    if IsIntrinsic(mCallee) then
    begin
      CheckIntrinsic(ANode, mCallee.Name);
      Exit;
    end;
    mCandidates := FScope.Resolver.CallCandidates(FContext.Tree, FScope.FileName, mCallee);
    if (Length(mCandidates) > 0) and mCandidates[0].IsType then
    begin
      CheckCast(ANode, mCandidates[0]);
    end
    else if Length(mCandidates) = 1 then
    begin
      ACandidate := mCandidates[0];
      Result := IsFixedRoutine(ACandidate) and FScope.DeclarationSure(ACandidate, mCallee) and
        not HiddenMember(mCallee, ACandidate);
    end;
  end;

  // Parameter von prozeduralem Typ (TProc<string>, TNotifyEvent): wie eine Zuweisung an ihn.
  function ProceduralArgument(AArgument: TSyntaxNode; const AParam: TSignatureParameter): Boolean;
  var
    mType: TResolvedSymbol;
    mTarget: TProcShape;
    mName: string;
  begin
    Result := FScope.Resolver.ResolveTypeTextFrom(mUnit, AParam.TypeName, mType) and
      ProceduralTarget(Default(TResolvedSymbol), mType, mTarget, mName);
    if Result and not MatchText(NormalizedModifier(AParam.Modifier), ['var', 'out']) then
    begin
      CheckProcedural(Unwrapped(AArgument), mTarget, mName);
    end;
  end;

  procedure CheckArgument(AArgument: TSyntaxNode; const AParam: TSignatureParameter);
  var
    mFormal, mActual: TValueType;
    mModifier: string;
  begin
    if (AParam.TypeName = '') or StartsText('array', Trim(AParam.TypeName)) or
      ProceduralArgument(AArgument, AParam) then
    begin
      Exit;
    end;
    mFormal := TypeValueFrom(mUnit, AParam.TypeName);
    if not mFormal.Known then
    begin
      Exit;
    end;
    mModifier := NormalizedModifier(AParam.Modifier);
    if (mModifier = 'var') or (mModifier = 'out') then
    begin
      CheckVarArgument(AArgument, mFormal);
      Exit;
    end;
    mActual := ValueOf(AArgument);
    if TTypeCompatibility.AssignIncompatible(mFormal, mActual) then
    begin
      Mismatch(AArgument, mFormal.Name, ShownName(mActual));
    end;
  end;

begin
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  mCallee := ANode[0];
  if not IsPlainCallee(mCallee) or not SingleRoutine(mCandidate) then
  begin
    Exit;
  end;
  if not ParseShape(StringReplace(mCandidate.Signature, 'constructor', 'procedure', [rfIgnoreCase]), True, mShape) or
    (ANode.ChildCount - 1 > Length(mShape.Params)) or not FScope.Resolver.DeclaringUnit(mCandidate, mUnit) then
  begin
    Exit;
  end;
  for mIndex := 1 to ANode.ChildCount - 1 do
  begin
    CheckArgument(ANode[mIndex], mShape.Params[mIndex - 1]);
  end;
end;

procedure TTypeMismatchCheck.CheckIndexer(ANode: TSyntaxNode);
var
  mSymbol, mType: TResolvedSymbol;
  mFound: Boolean;
  mUnit: TUnitIndex;
  mIndex: Integer;
  mFormal, mActual: TValueType;

  function Indexable: Boolean;
  begin
    Result := (ANode.ChildCount >= 2) and
      FScope.Resolver.NodeType(FContext.Tree, FScope.FileName, ANode, mSymbol, mType, mFound);
    Result := Result and (mSymbol.SymbolKind = TIndexSymbolKind.Property_) and (mSymbol.MaxArgs <> 0);
    Result := Result and (Length(mSymbol.ParamTypes) >= ANode.ChildCount - 1) and (Length(mSymbol.Overloads) = 0);
    Result := Result and FScope.DeclarationSure(mSymbol, ANode) and FScope.Resolver.DeclaringUnit(mSymbol, mUnit);
  end;

  // Überladene Array-Properties (zwei default-Properties bzw. gleiche Namen) wählt dcc nach den Argumenten.
  function SameIndexers: Integer;
  var
    mIndexSymbol: TIndexSymbol;
  begin
    Result := 0;
    for mIndexSymbol in mUnit.Symbols do
    begin
      if (mIndexSymbol.Kind = TIndexSymbolKind.Property_) and SameText(mIndexSymbol.Container, mSymbol.Container) and
        (SameText(mIndexSymbol.Name, mSymbol.Name) or (mSymbol.IsDefault and mIndexSymbol.IsDefault)) then
      begin
        Inc(Result);
      end;
    end;
  end;

begin
  if not Indexable or (SameIndexers <> 1) then
  begin
    Exit;
  end;
  for mIndex := 1 to ANode.ChildCount - 1 do
  begin
    mFormal := TypeValueFrom(mUnit, mSymbol.ParamTypes[mIndex - 1]);
    mActual := ValueOf(ANode[mIndex]);
    if TTypeCompatibility.AssignIncompatible(mFormal, mActual) then
    begin
      Mismatch(ANode[mIndex], mFormal.Name, ShownName(mActual));
    end;
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
  begin
    Exit;
  end;
  mOperator := LowerCase(ANode.Name);
  if mOperator = 'is' then
  begin
    // X is Integer: rechts muss eine Klasse stehen.
    mRightNode := Unwrapped(ANode[1]);
    if (mRightNode.Kind = TSyntaxKind.Identifier) and not BuiltinCast(mRightNode, mSymbol) and
      not (FScope.Resolver.NodeType(FContext.Tree, FScope.FileName, mRightNode, mSymbol, mType, mFound) and
      mSymbol.IsType) then
    begin
      Exit;
    end;
    if mSymbol.Builtin and IsDataCategory(TValueType.FromBuiltin(mSymbol.Name)) then
    begin
      FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
        cTexts[TTypeMismatchText.IsNeedsClass].Fmt([mSymbol.Name]), TRuleConfidence.High);
    end;
    Exit;
  end;
  mLeft := ValueOf(ANode[0]);
  mRight := ValueOf(ANode[1]);
  case TTypeCompatibility.OperatorFit(mOperator, mLeft, mRight) of
    TOperatorFit.NotApplicable:
      FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
        cTexts[TTypeMismatchText.OperatorBinary].Fmt([ANode.Name, mLeft.Name, mRight.Name]), TRuleConfidence.High);
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
  begin
    Exit;
  end;
  mOperand := ValueOf(ANode[0]);
  if TTypeCompatibility.UnaryNotApplicable(ANode.Name, mOperand) then
  begin
    FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
      cTexts[TTypeMismatchText.OperatorUnary].Fmt([ANode.Name, mOperand.Name]), TRuleConfidence.High);
  end;
end;

procedure TTypeMismatchCheck.Run;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(FContext.Tree.Root);
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
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

{ TTypeMismatchRule }

function TTypeMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cTypeMismatchRuleId, TRuleSeverity.Error, cTexts[TTypeMismatchText.Title].Text);
end;

procedure TTypeMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TTypeMismatchCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TypeMismatch', cTexts);

end.
