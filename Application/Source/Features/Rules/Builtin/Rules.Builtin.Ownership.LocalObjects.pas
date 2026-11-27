unit Rules.Builtin.Ownership.LocalObjects;

// Leckregeln für lokale Variablen (#1876):
//   local-object-not-freed     Eine lokale Variable (auch Inline-Variable) erhält T.Create(…) einer Klasse ohne
//                              Owner, wird nie freigegeben und verlässt die Routine nicht.
//   created-result-not-freed   Eine lokale Variable erhält das Ergebnis einer Funktion, die immer ein neues Objekt
//                              liefert (alle Zuweisungen an Result sind T.Create ohne Owner, Result geht sonst
//                              nirgends hin), oder einer Funktion aus der Option factories; Rest wie oben.
// Jedes Vorkommen der Variablen wird im Syntaxbaum nach oben eingeordnet (Atlas.Common.Pascal.ObjectUses): Free,
// Destroy, DisposeOf, Release, FreeAndNil und Routinen mit Free/Release/Destroy/Dispose im Namen geben frei;
// Zuweisung an etwas anderes, Exit(X), raise X, X as I, @X, [X], with X, X.Parent := …, Einfangen in einer
// anonymen Methode und Erwähnung in einer lokalen Routine lassen die Regel schweigen. Bei Weitergabe als Argument
// zählt, was die gerufene Routine laut Index damit macht, auch in einer anderen Unit
// (Rules.CallOwnership): Gibt sie frei, ist das Objekt frei; leiht sie es nur (liest, füllt), zählt
// der Aufruf nicht; übernimmt sie es oder ist das unklar, schweigt die Regel. Lesende Routinen wie Assign,
// AddStrings, CopyFrom und SaveToStream leihen immer. Records, dynamische Arrays, Threads, Komponenten mit Owner und
// Interface-Variablen bleiben außen vor. Korrektur: try … finally X.Free end.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Rules.Contract,
  Rules.Registry,
  Atlas.Common.Semantics.Ancestry;

const
  cLocalObjectNotFreedRuleId = 'local-object-not-freed';
  cCreatedResultNotFreedRuleId = 'created-result-not-freed';

type
  TLocalObjectNotFreedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCreatedResultNotFreedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  /// <summary>Ein Aufruf T.Create(…) bzw. T.Create: Klasse, ob Argumente folgen, erstes Argument (Name oder nil).
  /// </summary>
  TConstructorCall = record
    Node: TSyntaxNode;
    ClassName: string;
    HasArguments: Boolean;
    FirstArgument: string;
  end;

  /// <summary>Erkennung neuer Objekte ohne Besitzer, gemeinsam für local-object-not-freed und multiple-create-in-try:
  /// Klassen, deren Vorfahren bis TObject bekannt sind (Datei, Index oder eine bekannte RTL-Klasse), Komponenten nur
  /// ohne Owner bzw. mit nil.</summary>
  TOwnerlessObjects = record
  private
    FRoot: TSyntaxNode;
    FAncestry: TAncestry;
  public
    /// <summary>ARoot: Wurzel des Syntaxbaums der Datei; AAncestry gehört dem Aufrufer.</summary>
    class function Create(ARoot: TSyntaxNode; AAncestry: TAncestry): TOwnerlessObjects; static;
    /// <summary>Ist AClassName eine Klasse? Records, Arrays und Interfaces der Datei bzw. des Index und bekannte
    /// Records der RTL nicht; unbekannte Namen gelten als Klasse.</summary>
    function IsClass(const AClassName: string): Boolean;
    /// <summary>Bleibt das von ACall erzeugte Objekt ohne Besitzer?</summary>
    function IsLost(const ACall: TConstructorCall): Boolean;
    /// <summary>Ist AClassName sicher eine Klasse (Vorfahren bis TObject bekannt oder bekannte RTL-Klasse)?</summary>
    function IsKnownClass(const AClassName: string): Boolean;
  end;

/// <summary>Ist AValue ein Konstruktoraufruf T.Create(…), T.CreateFmt(…) … über einen Typnamen?</summary>
function ConstructorCall(AValue: TSyntaxNode; out ACall: TConstructorCall): Boolean;

/// <summary>Typ einer Variablendeklaration (VarDecl oder InlineVar); '' ohne Typangabe.</summary>
function DeclaredType(ADecl: TSyntaxNode): string;

/// <summary>Registriert local-object-not-freed und created-result-not-freed.</summary>
procedure RegisterOwnershipLocalObjectRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.RoutineBody,
  Rules.Derived,
  Atlas.Common.Configuration.RuleOptions,
  Rules.Builtin.Ownership.TryFinally,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Pascal.SyntaxNodes,
  Atlas.Common.Pascal.ObjectUses,
  Atlas.Common.Pascal.ParamOwnership,
  Rules.CallOwnership,
  Atlas.Text.Names,
  Atlas.Common.Findings.Contract,
  Rules.Trees;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TLocalObjectText = (LocalTitle, ResultTitle, LocalLeak, ResultLeak, InsertTryFinally);

const
  cTexts: array[TLocalObjectText] of TAtlasText = (
    (De: 'Lokales Objekt nie freigegeben'; En: 'Local object never released'),
    (De: 'Neues Objekt aus einer Funktion nie freigegeben'; En: 'New object from a function never released'),
    (De: '%s erhält ein neues %s, das die Routine weder freigibt noch weitergibt (Speicherleck).';
     En: '%s receives a new %s that the routine neither releases nor passes on (memory leak).'),
    (De: '%s erhält von %s ein neues Objekt, das die Routine weder freigibt noch weitergibt (Speicherleck).';
     En: '%s receives a new object from %s that the routine neither releases nor passes on (memory leak).'),
    (De: 'try … finally %s.Free end einfügen'; En: 'Insert try … finally %s.Free end'));

type
  /// <summary>Wie eine lokale Variable an einer Stelle vorkommt.</summary>
  TLocalUse = (Use, Alloc, Release, Escape);

  /// <summary>Art der erzeugten Klasse: Unknown, wenn die Vorfahrenkette vor TObject abbricht.</summary>
  TLocalClassKind = (Unknown, Plain, Component, Thread, NoClass);

  /// <summary>Welche Belegung die Regel sucht.</summary>
  TLocalScanMode = (Constructors, Factories);

{$SCOPEDENUMS OFF}

const
  // Konstruktoren; Klassenfunktionen wie CreateIssue liefern womöglich etwas anderes.
  cConstructorNames: array[0..9] of string = ('Create', 'CreateNew', 'CreateFmt', 'CreateRes', 'CreateResFmt',
    'CreateHelp', 'CreateFmtHelp', 'CreateResHelp', 'CreateParented', 'CreateSize');
  // Klassen der RTL, die ohne Index als Klassen ohne Owner gelten (Datei und Index kennen die RTL nicht).
  cRtlClasses: array[0..33] of string = ('TObject', 'TStringList', 'TList', 'TObjectList', 'TDictionary',
    'TObjectDictionary', 'TQueue', 'TStack', 'TObjectQueue', 'TObjectStack', 'THashSet', 'TThreadList',
    'TMemoryStream', 'TFileStream', 'TStringStream', 'TBytesStream', 'TResourceStream', 'TBufferedFileStream',
    'TStreamReader', 'TStreamWriter', 'TStringReader', 'TStringWriter', 'TBinaryReader', 'TBinaryWriter',
    'TStringBuilder', 'TJSONObject', 'TJSONArray', 'TIniFile', 'TMemIniFile', 'TRegistry', 'TCriticalSection',
    'TEvent', 'TBitmap', 'TPicture');
  // Bekannte Records, dynamische Arrays und Typen, deren Create ein Interface liefert.
  cNoObjectTypes: array[0..27] of string = ('TPoint', 'TPointF', 'TRect', 'TRectF', 'TSize', 'TSizeF', 'TStopwatch',
    'TTimeSpan', 'TRegEx', 'TFormatSettings', 'TArray', 'TBytes', 'TTask', 'TGUID', 'TValue', 'TSpinLock',
    'TSpinWait', 'TLightweightMREW', 'TMatch', 'TColorRec', 'TAlphaColorRec', 'TVector', 'TMatrix', 'TPointerStream',
    'TEncoding', 'TPath', 'TDirectory', 'TCompareResult');

function InList(const AName: string; const AList: array of string): Boolean;
begin
  Result := MatchText(AName, AList);
end;

/// <summary>Folgt AName der Namensregel für Typen (TName)?</summary>
function LooksLikeType(const AName: string): Boolean;
begin
  Result := (Length(AName) > 1) and (AName[1] = 'T') and CharInSet(AName[2], ['A'..'Z']);
end;

function ConstructorCall(AValue: TSyntaxNode; out ACall: TConstructorCall): Boolean;
var
  mAccess: TSyntaxNode;
begin
  ACall := Default(TConstructorCall);
  mAccess := AValue;
  if (AValue <> nil) and (AValue.Kind = TSyntaxKind.Call) and (AValue.ChildCount > 0) then
  begin
    mAccess := AValue[0];
    ACall.HasArguments := AValue.ChildCount > 1;
    if ACall.HasArguments and (AValue[1].Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal]) then
    begin
      ACall.FirstArgument := AValue[1].Name;
    end;
  end;
  Result := (mAccess <> nil) and (mAccess.Kind = TSyntaxKind.MemberAccess) and
    InList(mAccess.Name, cConstructorNames) and (mAccess.ChildCount > 0) and
    (mAccess[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and LooksLikeType(mAccess[0].Name);
  if Result then
  begin
    ACall.Node := AValue;
    ACall.ClassName := mAccess[0].Name;
  end;
end;

type
  /// <summary>Gemeinsamer Lauf beider Regeln über eine Unit.</summary>
  TLocalObjectScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FMode: TLocalScanMode;
    FLines: TArray<string>;
    FLineBreak: string;
    FAncestry: TAncestry;
    FObjects: TOwnerlessObjects;
    FDerived: IRuleDerivedCache;
    /// <summary>Kurznamen der Funktionen der Datei, die immer ein neues Objekt liefern (Wert True), bzw. nicht.
    /// </summary>
    FFactories: TDictionary<string, Boolean>;
    FOptionFactories: TArray<string>;
    /// <summary>Was gerufene Routinen mit einem übergebenen Objekt machen, auch in anderen Units.</summary>
    FCalls: TRuleCallOwnership;
    function IsFactoryRoutine(ARoutine: TSyntaxNode): Boolean;
    procedure CollectFactories;
    function FactoryCall(AValue: TSyntaxNode; out AName: string): Boolean;
    function IsAllocation(AValue: TSyntaxNode; out AWhat: string): Boolean;
    function UseInCall(const AUse: TObjectUse): TLocalUse;
    function UseInAssign(AAssign: TSyntaxNode): TLocalUse;
    function Classify(ANode: TSyntaxNode): TLocalUse;
    procedure ReportLeak(AStatement: TSyntaxNode; const AName, AWhat: string);
    procedure CheckVariable(ARoutine: TSyntaxNode; const AName, ATypeName: string; AInline: TSyntaxNode);
    procedure CheckSection(ARoutine, ASection: TSyntaxNode);
    procedure CheckRoutine(ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport; AMode: TLocalScanMode);
    destructor Destroy; override;
    procedure Run;
  end;

{ Hilfen über dem Baum }

/// <summary>Enthält ANode asm oder with? Dort sind Vorkommen der Variablen nicht sicher einzuordnen.</summary>
function HasAsmOrWith(ANode: TSyntaxNode): Boolean;
var
  mFound: Boolean;
begin
  mFound := False;
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      if AChild.Kind in [TSyntaxKind.AsmBlock, TSyntaxKind.WithStatement] then
      begin
        mFound := True;
      end;
      Result := not mFound;
    end);
  Result := mFound;
end;

/// <summary>Inline-Variablen der Routine außerhalb lokaler Routinen und anonymer Methoden.</summary>
function InlineVariables(ABody: TSyntaxNode): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  ABody.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.InlineVar then
      begin
        mFound := mFound + [ANode];
      end;
      Result := not (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) or (ANode = ABody);
    end);
  Result := mFound;
end;

function DeclaredType(ADecl: TSyntaxNode): string;
begin
  Result := '';
  if (ADecl.ChildCount > 0) and (ADecl[0].Kind = TSyntaxKind.TypeReference) then
  begin
    Result := ADecl[0].Name;
  end;
end;

/// <summary>Anfangswert einer Inline-Variablen; nil ohne.</summary>
function InlineValue(ADecl: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ADecl.ChildCount > 0) and (ADecl[ADecl.ChildCount - 1].Kind <> TSyntaxKind.TypeReference) then
  begin
    Result := ADecl[ADecl.ChildCount - 1];
  end;
end;

/// <summary>Die Anweisung, die das Vorkommen ANode enthält.</summary>
function StatementOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and not (Result.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.AssignStatement,
    TSyntaxKind.InlineVar]) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Kurzname einer Routine: Bar bei TFoo.Bar.</summary>
function ShortName(const AName: string): string;
begin
  Result := AName;
  if Result.Contains('.') then
  begin
    Result := Copy(Result, Result.LastIndexOf('.') + 2, MaxInt);
  end;
end;

/// <summary>Ergebnistyp der Routine ARoutine; '' bei Prozeduren.</summary>
function ResultType(ARoutine: TSyntaxNode): string;
var
  mHeader: TSyntaxNode;
  mIndex: Integer;
begin
  Result := '';
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mHeader.ChildCount - 1 do
  begin
    if mHeader[mIndex].Kind = TSyntaxKind.TypeReference then
    begin
      Result := mHeader[mIndex].Name;
    end;
  end;
end;

/// <summary>Liefert jedes Exit(…) in ABody ein neues Objekt (Exit(T.Create…))?</summary>
function OnlyCreatingExits(ABody: TSyntaxNode): Boolean;
var
  mOk: Boolean;
  mCall: TConstructorCall;
begin
  mOk := True;
  ABody.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.Call) and SameText(ANode.Name, 'Exit') and (ANode.ChildCount > 1) and
        not ConstructorCall(ANode[1], mCall) then
      begin
        mOk := False;
      end;
      Result := mOk;
    end);
  Result := mOk;
end;

{ TOwnerlessObjects }

class function TOwnerlessObjects.Create(ARoot: TSyntaxNode; AAncestry: TAncestry): TOwnerlessObjects;
begin
  Result.FRoot := ARoot;
  Result.FAncestry := AAncestry;
end;

function TOwnerlessObjects.IsClass(const AClassName: string): Boolean;
var
  mBody: TSyntaxNode;
  mType: TSymbolLocation;
begin
  mBody := TRoutineBody.TypeBody(FRoot, AClassName);
  if mBody <> nil then
  begin
    Result := mBody.Kind = TSyntaxKind.ClassType;
  end
  else
  begin
    Result := not FAncestry.FindAnyType(AClassName, mType) or (mType.Symbol.Kind = TIndexSymbolKind.ClassType);
  end;
  // Bekannte RTL-Klassen auch dann, wenn ein anderes RTL (FPC) sie als Alias führt (TStringBuilder).
  Result := (Result or InList(AClassName, cRtlClasses)) and not InList(AClassName, cNoObjectTypes);
end;

/// <summary>Art der Klasse über die Vorfahren in Datei und Index; Unknown, wenn die Kette vor TObject abbricht.
/// </summary>
function KindOf(const AObjects: TOwnerlessObjects; const AClassName: string): TLocalClassKind;
var
  mName: string;
  mDepth: Integer;
begin
  Result := TLocalClassKind.NoClass;
  if not AObjects.IsClass(AClassName) then
  begin
    Exit;
  end;
  Result := TLocalClassKind.Unknown;
  mName := AClassName;
  mDepth := 0;
  while (Result = TLocalClassKind.Unknown) and (mName <> '') and (mDepth < 64) do
  begin
    if SameText(mName, 'TComponent') then
    begin
      Result := TLocalClassKind.Component;
    end
    else if SameText(mName, 'TThread') then
    begin
      Result := TLocalClassKind.Thread;
    end
    else if SameText(mName, 'TObject') then
    begin
      Result := TLocalClassKind.Plain;
    end;
    mName := AObjects.FAncestry.ParentOf(mName);
    Inc(mDepth);
  end;
end;

/// <summary>Bleibt das erzeugte Objekt ohne Besitzer? Nur Klassen, deren Vorfahren bis TObject bekannt sind (Datei,
/// Index oder eine bekannte RTL-Klasse); Komponenten nur ohne Owner bzw. mit nil.</summary>
function TOwnerlessObjects.IsLost(const ACall: TConstructorCall): Boolean;
var
  mKind: TLocalClassKind;
begin
  mKind := KindOf(Self, ACall.ClassName);
  if (mKind = TLocalClassKind.Unknown) and InList(ACall.ClassName, cRtlClasses) then
  begin
    mKind := TLocalClassKind.Plain;
  end;
  // Unbekannte Klassen können Records mit einer Funktion Create sein oder sich selbst verwalten.
  if not (mKind in [TLocalClassKind.Plain, TLocalClassKind.Component]) then
  begin
    Exit(False);
  end;
  Result := not ACall.HasArguments or SameText(ACall.FirstArgument, 'nil') or ((mKind = TLocalClassKind.Plain) and
    not MatchText(ACall.FirstArgument, ['Self', 'Owner', 'AOwner', 'Application']));
end;

function TOwnerlessObjects.IsKnownClass(const AClassName: string): Boolean;
begin
  Result := (KindOf(Self, AClassName) in [TLocalClassKind.Plain, TLocalClassKind.Component, TLocalClassKind.Thread]) or
    (IsClass(AClassName) and InList(AClassName, cRtlClasses));
end;

{ TLocalObjectScan }

constructor TLocalObjectScan.Create(const AContext: TRuleContext; const AReport: IRuleReport;
  AMode: TLocalScanMode);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FMode := AMode;
  FFactories := TDictionary<string, Boolean>.Create;
end;

destructor TLocalObjectScan.Destroy;
begin
  FCalls.Free;
  FFactories.Free;
  FAncestry.Free;
  inherited Destroy;
end;

/// <summary>Liefert ARoutine immer ein neues Objekt ohne Owner? Der Ergebnistyp ist eine Klasse (kein Record aus
/// einer Klassenfunktion Create), alle Zuweisungen an Result sind T.Create, Result wird sonst nur über seine
/// Mitglieder benutzt oder freigegeben (Aufräumen im except), nie weitergegeben.</summary>
function TLocalObjectScan.IsFactoryRoutine(ARoutine: TSyntaxNode): Boolean;
var
  mFound: TArray<TSyntaxNode>;
  mNode: TSyntaxNode;
  mUse: TLocalUse;
  mCall: TConstructorCall;
  mCreates: Boolean;
begin
  if (ResultType(ARoutine) = '') or TTextNames.LooksLikeInterface(ResultType(ARoutine)) or
    not FObjects.IsClass(ResultType(ARoutine)) or
    (TRoutineBody.BodyOf(ARoutine) = nil) or HasAsmOrWith(ARoutine) then
  begin
    Exit(False);
  end;
  mFound := TSyntaxNode.IdentifierUses(TRoutineBody.BodyOf(ARoutine), 'Result');
  mCreates := False;
  for mNode in mFound do
  begin
    mUse := Classify(mNode);
    if mUse = TLocalUse.Alloc then
    begin
      if not ConstructorCall(mNode.Parent[1], mCall) or not FObjects.IsLost(mCall) then
      begin
        Exit(False);
      end;
      mCreates := True;
    end
    else if (mUse = TLocalUse.Escape) or (TSyntaxNodes.Enclosing(mNode, [TSyntaxKind.AnonymousMethod], ARoutine) <> nil) then
    begin
      Exit(False);
    end;
  end;
  Result := mCreates and not TSyntaxNode.UsedInNestedRoutine(ARoutine, 'Result') and
    OnlyCreatingExits(TRoutineBody.BodyOf(ARoutine));
end;

/// <summary>Kurznamen der Funktionen der Datei; gleichnamige Überladungen müssen alle ein neues Objekt liefern.
/// </summary>
procedure TLocalObjectScan.CollectFactories;
var
  mRoutine: TSyntaxNode;
  mName: string;
  mValue: Boolean;
begin
  for mRoutine in TRuleDerived.Routines(FDerived, FContext) do
  begin
    if mRoutine.Parent.Kind = TSyntaxKind.RoutineDecl then
    begin
      Continue;
    end;
    mName := LowerCase(ShortName(mRoutine.Name));
    mValue := IsFactoryRoutine(mRoutine);
    if FFactories.ContainsKey(mName) then
    begin
      mValue := mValue and FFactories[mName];
    end;
    FFactories.AddOrSetValue(mName, mValue);
  end;
end;

/// <summary>Ist AValue ein Aufruf einer Funktion, die ein neues Objekt liefert? Funktionen der Datei unqualifiziert
/// oder über Self bzw. einen Typnamen, Funktionen aus factories als Name, Klasse.Name oder Unit.Name.</summary>
function TLocalObjectScan.FactoryCall(AValue: TSyntaxNode; out AName: string): Boolean;
var
  mCallee: TSyntaxNode;
  mPrefix, mEntry: string;
  mFactory: Boolean;
begin
  Result := False;
  mCallee := AValue;
  if AValue.Kind = TSyntaxKind.Call then
  begin
    mCallee := AValue[0];
  end;
  if not (mCallee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
  begin
    Exit;
  end;
  AName := mCallee.Name;
  mPrefix := '';
  if (mCallee.Kind = TSyntaxKind.MemberAccess) and (mCallee.ChildCount > 0) and
    (mCallee[0].Kind = TSyntaxKind.Identifier) then
  begin
    mPrefix := mCallee[0].Name;
    AName := mPrefix + '.' + mCallee.Name;
  end;
  for mEntry in FOptionFactories do
  begin
    if SameText(mEntry, mCallee.Name) or SameText(mEntry, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := ((mCallee.Kind = TSyntaxKind.Identifier) or SameText(mPrefix, 'Self') or LooksLikeType(mPrefix)) and
    FFactories.TryGetValue(LowerCase(mCallee.Name), mFactory) and mFactory;
end;

/// <summary>Belegung je nach Regel: T.Create ohne Owner bzw. Aufruf einer Fabrikfunktion. AWhat: Klasse bzw.
/// Funktion für die Meldung.</summary>
function TLocalObjectScan.IsAllocation(AValue: TSyntaxNode; out AWhat: string): Boolean;
var
  mCall: TConstructorCall;
begin
  if AValue = nil then
  begin
    Exit(False);
  end;
  if FMode = TLocalScanMode.Constructors then
  begin
    Result := ConstructorCall(AValue, mCall) and FObjects.IsLost(mCall);
    AWhat := mCall.ClassName;
  end
  else
  begin
    Result := FactoryCall(AValue, AWhat);
  end;
end;

/// <summary>Weitergabe als Argument: Was die gerufene Routine laut Index damit macht; weiß er nichts, leihen nur
/// lesende Routinen wie Assign.</summary>
function TLocalObjectScan.UseInCall(const AUse: TObjectUse): TLocalUse;
begin
  case FCalls.EffectOf(AUse.Node, AUse.Argument).Effect of
    TParamEffect.Frees:
      Result := TLocalUse.Release;
    TParamEffect.Borrows:
      Result := TLocalUse.Use;
    TParamEffect.Keeps:
      Result := TLocalUse.Escape;
  else
    // Unklar: Die Routine kann das Objekt behalten, außer sie liest dem Namen nach nur.
    Result := TLocalUse.Escape;
    if AUse.Reading then
    begin
      Result := TLocalUse.Use;
    end;
  end;
end;

/// <summary>Die Variable steht links von := in AAssign.</summary>
function TLocalObjectScan.UseInAssign(AAssign: TSyntaxNode): TLocalUse;
var
  mWhat: string;
  mCall: TConstructorCall;
begin
  // Neu belegt mit etwas anderem: Herkunft bzw. Verbleib unklar.
  Result := TLocalUse.Escape;
  if (AAssign.ChildCount > 1) and (ConstructorCall(AAssign[1], mCall) or
    ((FMode = TLocalScanMode.Factories) and FactoryCall(AAssign[1], mWhat))) then
  begin
    Result := TLocalUse.Alloc;
  end;
end;

/// <summary>Art des Vorkommens ANode vom Knoten aus nach oben bis zur Anweisung.</summary>
function TLocalObjectScan.Classify(ANode: TSyntaxNode): TLocalUse;
var
  mUse: TObjectUse;
begin
  mUse := TObjectUses.Classify(ANode);
  case mUse.Kind of
    TObjectUseKind.Assigned:
      Result := UseInAssign(mUse.Node);
    TObjectUseKind.Release:
      Result := TLocalUse.Release;
    TObjectUseKind.Escape:
      Result := TLocalUse.Escape;
    TObjectUseKind.Argument:
      Result := UseInCall(mUse);
  else
    Result := TLocalUse.Use;
  end;
end;

procedure TLocalObjectScan.ReportLeak(AStatement: TSyntaxNode; const AName, AWhat: string);
var
  mEdit: TTextEdit;
  mFixes: TArray<TRuleFix>;
  mConfidence: TRuleConfidence;
  mMessage: string;
begin
  mFixes := nil;
  if TTryFinallyWrap.Create(FLines, FLineBreak, FContext.Formatting).Wrap(AStatement, '', AName + '.Free;', mEdit)
    then
  begin
    mFixes := [TRuleFix.Create(cTexts[TLocalObjectText.InsertTryFinally].Fmt([AName]), [mEdit])];
  end;
  // Konstruktoren nur bekannter Klassen: hoch; Fabriken der Datei werden über den Namen erkannt: mittel.
  mConfidence := TRuleConfidence.High;
  mMessage := cTexts[TLocalObjectText.LocalLeak].Fmt([AName, AWhat]);
  if FMode = TLocalScanMode.Factories then
  begin
    mConfidence := TRuleConfidence.Medium;
    mMessage := cTexts[TLocalObjectText.ResultLeak].Fmt([AName, AWhat]);
  end;
  FReport.Add(TTextRange.Create(AStatement.StartPos, AStatement.EndPos), mMessage, mConfidence, mFixes);
end;

/// <summary>Prüft eine Variable AName der Routine; AInline ist ihre Inline-Deklaration oder nil.</summary>
procedure TLocalObjectScan.CheckVariable(ARoutine: TSyntaxNode; const AName, ATypeName: string;
  AInline: TSyntaxNode);
var
  mFound: TArray<TSyntaxNode>;
  mNode, mFirst: TSyntaxNode;
  mUse: TLocalUse;
  mWhat, mFirstWhat: string;
begin
  if TTextNames.LooksLikeInterface(ATypeName) or TSyntaxNode.UsedInNestedRoutine(ARoutine, AName) then
  begin
    Exit;
  end;
  mFirst := nil;
  if (AInline <> nil) and IsAllocation(InlineValue(AInline), mFirstWhat) then
  begin
    mFirst := AInline;
  end;
  mFound := TSyntaxNode.IdentifierUses(TRoutineBody.BodyOf(ARoutine), AName);
  for mNode in mFound do
  begin
    mUse := Classify(mNode);
    if (mUse in [TLocalUse.Release, TLocalUse.Escape]) or (TSyntaxNodes.Enclosing(mNode, [TSyntaxKind.AnonymousMethod], ARoutine) <> nil) or
      ((mUse = TLocalUse.Alloc) and not IsAllocation(mNode.Parent[1], mWhat)) then
    begin
      Exit;
    end;
    if (mUse = TLocalUse.Alloc) and (mFirst = nil) then
    begin
      mFirst := StatementOf(mNode);
      mFirstWhat := mWhat;
    end;
  end;
  if mFirst <> nil then
  begin
    ReportLeak(mFirst, AName, mFirstWhat);
  end;
end;

/// <summary>Variablen eines var-Abschnitts der Routine prüfen.</summary>
procedure TLocalObjectScan.CheckSection(ARoutine, ASection: TSyntaxNode);
var
  mIndex: Integer;
  mName: string;
begin
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    if ASection[mIndex].Kind = TSyntaxKind.VarDecl then
    begin
      for mName in ASection[mIndex].Name.Split([',']) do
      begin
        CheckVariable(ARoutine, Trim(mName), DeclaredType(ASection[mIndex]), nil);
      end;
    end;
  end;
end;

procedure TLocalObjectScan.CheckRoutine(ARoutine: TSyntaxNode);
var
  mIndex: Integer;
  mDecl: TSyntaxNode;
begin
  if (TRoutineBody.BodyOf(ARoutine) = nil) or HasAsmOrWith(ARoutine) then
  begin
    Exit;
  end;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if ARoutine[mIndex].Kind = TSyntaxKind.VarSection then
    begin
      CheckSection(ARoutine, ARoutine[mIndex]);
    end;
  end;
  for mDecl in InlineVariables(TRoutineBody.BodyOf(ARoutine)) do
  begin
    if not mDecl.Name.Contains(',') then
    begin
      CheckVariable(ARoutine, mDecl.Name, DeclaredType(mDecl), mDecl);
    end;
  end;
end;

procedure TLocalObjectScan.Run;
var
  mRoutine: TSyntaxNode;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) or not ContainsText(FContext.Text, 'Create') then
  begin
    Exit;
  end;
  FDerived := TRuleDerived.Open(FContext);
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(FDerived, FContext));
  FObjects := TOwnerlessObjects.Create(FContext.Tree.Root, FAncestry);
  // Vor CollectFactories: IsFactoryRoutine fragt über UseInCall FCalls (sonst Zugriffsverletzung auf nil).
  FCalls := TRuleCallOwnership.Create(FContext);
  if FMode = TLocalScanMode.Factories then
  begin
    FOptionFactories := TRuleOptions.Strings(FContext.Options, 'factories', nil);
    CollectFactories;
  end;
  FLines := TTextLines.SplitLines(FContext.Text, FLineBreak);
  for mRoutine in TRuleDerived.Routines(FDerived, FContext) do
  begin
    CheckRoutine(mRoutine);
  end;
end;

{ TLocalObjectNotFreedRule }

function TLocalObjectNotFreedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cLocalObjectNotFreedRuleId, TRuleSeverity.Warning,
    cTexts[TLocalObjectText.LocalTitle].Text);
end;

procedure TLocalObjectNotFreedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TLocalObjectScan;
begin
  mScan := TLocalObjectScan.Create(AContext, AReport, TLocalScanMode.Constructors);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

{ TCreatedResultNotFreedRule }

function TCreatedResultNotFreedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cCreatedResultNotFreedRuleId, TRuleSeverity.Warning,
    cTexts[TLocalObjectText.ResultTitle].Text);
end;

procedure TCreatedResultNotFreedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TLocalObjectScan;
begin
  mScan := TLocalObjectScan.Create(AContext, AReport, TLocalScanMode.Factories);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

procedure RegisterOwnershipLocalObjectRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TLocalObjectNotFreedRule.Create);
  ARegistry.Register(TCreatedResultNotFreedRule.Create);
end;

initialization
  TAtlasTextTables.Add('Rules.Builtin.Ownership.LocalObjects', cTexts);

end.
