unit Atlas.Common.Lsp.Impact;

// Auswirkungsanalyse (#1120): Was ist betroffen, wenn ich X ändere?
//
// Vom Symbol rückwärts, Ebene für Ebene bis zur gewählten Tiefe (1–5):
// - Aufrufer und Verweise über die Referenzsuche samt Einstufung sicher oder
//   erschlossen (#1119). Ein Verweis in einer Routine macht diese Routine zur
//   betroffenen Stelle; außerhalb von Routinen die umgebende Deklaration
//   (property X read FX, Konstante, Typ), sonst die Unit selbst
//   (initialization), die nicht weiter verfolgt wird.
// - Overrides der Methode in allen Nachfahren und die überschriebene
//   Basismethode im nächsten Vorfahren.
// - Interface-Methode ↔ Umsetzung: von der Methode einer Klasse zur
//   gleichnamigen Methode ihrer Interfaces (auch über Methodenzuordnungen
//   IFoo.Bar = Baz) und von der Interface-Methode zu den Umsetzungen.
// - Formularbindungen: Ereignis-Handler und Komponentennamen einer Stelle in
//   den Formularen ihrer Unit (.dfm, .fmx). Sie gehören zur Stelle selbst und
//   kosten keine Ebene; so erscheint auch ein Handler der letzten Ebene als
//   solcher.
// Die gefundenen Stellen einer Ebene sind die Ausgangsmenge der nächsten.
// Jede Stelle erscheint nur einmal, auf ihrer kleinsten Ebene, zugeordnet der
// ersten verursachenden Stelle; Schlüssel ist ihre Deklaration (Rumpf und
// Deklaration einer Methode sind dieselbe Stelle). Zyklen enden daran.
//
// Betroffene Tests: Stellen in Testunits (Name nach testUnits.pattern oder
// Unit des Testprogramms) sind Tests, wenn sie Testmethoden einer DUnitX-Fixture
// sind (Atlas.Text.DUnitX). Ausgabe als Unit.Fixture.Methode, bei [TestCase]
// je Fall, genau die Namen für run_tests bzw. --run.
//
// Grenzen: Tiefe (Stellen der letzten Ebene werden gezählt, aber nicht
// weiter verfolgt), höchstens MaxPlaces Stellen und ein Zeitlimit. Jede
// erreichte Grenze steht in der Antwort.
//
// Leistung: Projektdateien, in denen der gesuchte Name laut den Verwendungen im
// Index (#492) nicht vorkommt, liest die Referenzsuche gar nicht erst.
//
// Mehrere Symbole (betroffene Tests einer Änderung, #1353): AnalyzeEach
// verfolgt jedes für sich, teilt aber die gelesenen Bäume, Formulare und
// Testunits zwischen den Läufen.
//
// LSP: atlas/impact {textDocument, position, depth?}.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Lsp.ReferenceConfidence,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Hierarchies,
  Atlas.Common.Lsp.Impact.Forms;

type
{$SCOPEDENUMS ON}
  /// <summary>Wie eine Stelle von ihrer Ursache betroffen ist.</summary>
  TImpactEdge = (Call, Reference, Override_, BaseMethod, InterfaceMethod, Implementation_);
  TImpactLimit = (Depth, Count, Time);
{$SCOPEDENUMS OFF}
  TImpactLimits = set of TImpactLimit;

  /// <summary>Bindung einer Stelle in einem Formular (Atlas.Common.Lsp.Impact.Forms).</summary>
  TImpactFormBinding = Atlas.Common.Lsp.Impact.Forms.TImpactFormBinding;

  /// <summary>Was die Analyse liest: Projektdateien und wie man eine Datei liest.</summary>
  TImpactSources = record
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    class function Create(const AFiles: TArray<string>; const AReadText: TReferenceReadText): TImpactSources; static;
  end;

  TImpactPlace = record
    Item: THierarchyItem;
    /// <summary>1 = direkt betroffen, 2 und mehr = indirekt.</summary>
    Level: Integer;
    Edge: TImpactEdge;
    /// <summary>Index der verursachenden Stelle in TImpactResult.Places; -1 = das Symbol selbst.</summary>
    Cause: Integer;
    /// <summary>Stellen in Item, an denen die Ursache verwendet wird (leer bei Overrides und Interfaces).</summary>
    Ranges: TArray<TTextRange>;
    Confidence: TReferenceConfidence;
    /// <summary>Formularbindungen der Stelle.</summary>
    Forms: TArray<TImpactFormBinding>;
    /// <summary>Die Unit selbst (initialization, Unit-Ebene): wird nicht weiter verfolgt.</summary>
    Terminal: Boolean;
    /// <summary>Index in TImpactResult.Tests, wenn die Stelle ein Test ist; sonst -1.</summary>
    Test: Integer;
  end;

  TImpactTest = record
    /// <summary>Unit.Fixture.Methode.</summary>
    Name: string;
    /// <summary>Namen für run_tests (--run): Name, bei [TestCase] je Fall Unit.Fixture.Methode.Fall.</summary>
    RunNames: TArray<string>;
    FileName: string;
    /// <summary>Kopf der Testmethode, 0-basiert.</summary>
    Line: Integer;
    /// <summary>Ebene der Stelle; 0, wenn das Symbol selbst ein Test ist.</summary>
    Level: Integer;
  end;

  /// <summary>Welche Units Testunits sind (testUnits.pattern, Units des Testprogramms).</summary>
  TImpactTestScope = record
    Pattern: string;
    /// <summary>Units in den uses des Testprogramms (testUnits.project bzw. erkannt).</summary>
    Units: TArray<string>;
    function Contains(const AUnitName: string): Boolean;
    /// <summary>Muster APattern und die Units aus den uses des Testprogramms (Quelltext AProgramText; '' = keins).
    /// </summary>
    class function FromProgram(const APattern, AProgramText: string): TImpactTestScope; static;
  end;

  TImpactOptions = record
    /// <summary>1–5, außerhalb wird begrenzt.</summary>
    Depth: Integer;
    /// <summary>Höchstzahl der Stellen; 0 = TImpactAnalysis.cMaxPlaces.</summary>
    MaxPlaces: Integer;
    /// <summary>Zeitlimit in ms; 0 = ohne.</summary>
    TimeoutMs: Integer;
    References: TReferenceSettings;
    Tests: TImpactTestScope;
    class function Default: TImpactOptions; static;
  end;

  TImpactResult = record
    Symbol: THierarchyItem;
    /// <summary>Formularbindungen des Symbols selbst.</summary>
    SymbolForms: TArray<TImpactFormBinding>;
    Depth: Integer;
    Places: TArray<TImpactPlace>;
    Tests: TArray<TImpactTest>;
    Limits: TImpactLimits;
    /// <summary>Stellen der letzten Ebene, die wegen der Tiefe nicht weiter verfolgt wurden.</summary>
    Unexpanded: Integer;
    MaxPlaces: Integer;
    TimeoutMs: Integer;
    /// <summary>Stellen der Ebene ALevel.</summary>
    function LevelCount(ALevel: Integer): Integer;
    /// <summary>Alle Namen für run_tests, ohne Doppelte, in Reihenfolge der Tests.</summary>
    function RunNames: TArray<string>;
  end;

  /// <summary>Optionen der Analyse für die Datei AUri (Tiefe, Einstufung, Testunits, Zeitlimit).</summary>
  TImpactOptionsProvider = reference to function(const AUri: string): TImpactOptions;

  TImpactAnalysis = class
  public const
    cMethod = 'atlas/impact';
    cMinDepth = 1;
    cMaxDepth = 5;
    cDefaultDepth = 2;
    cMaxPlaces = 1000;
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: TReferenceReadText;
    FFiles: TReferenceFilesProvider;
    FNamespaces: TArray<string>;
    FOptionsFor: TImpactOptionsProvider;
    function OptionsFrom(AParams: TJSONObject; const AUri: string): TImpactOptions;
    function HandleImpact(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Auswirkungen des Symbols AStart (aus TLspHierarchies.SymbolItemAt). AFiles: Projektdateien.
    /// </summary>
    class function Analyze(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AStart: THierarchyItem;
      const ASources: TImpactSources; const AOptions: TImpactOptions;
      const ACancellation: IJsonRpcCancellationToken): TImpactResult; static;
    /// <summary>Wie Analyze für jedes Symbol aus AStarts (#1353), in derselben Reihenfolge; die Läufe teilen sich
    /// die gelesenen Dateien. AOptions.TimeoutMs gilt für alle zusammen: Jedes Symbol bekommt die verbleibende Zeit
    /// geteilt durch die Zahl der übrigen.</summary>
    class function AnalyzeEach(AResolver: TNameResolver; const AIndex: ISymbolIndex;
      const AStarts: TArray<THierarchyItem>; const ASources: TImpactSources; const AOptions: TImpactOptions;
      const ACancellation: IJsonRpcCancellationToken): TArray<TImpactResult>; static;
    /// <summary>Projektdateien, in denen AName vorkommen kann: ohne die, in denen er laut Index fehlt.</summary>
    class function CandidateFiles(const AIndex: ISymbolIndex; const AFiles: TArray<string>;
      const AName: string): TArray<string>; static;
    /// <summary>Tiefe auf MinDepth..MaxDepth begrenzt.</summary>
    class function ClampDepth(ADepth: Integer): Integer; static;
    /// <summary>"call", "reference", "override", "baseMethod", "interfaceMethod", "implementation".</summary>
    class function EdgeName(AEdge: TImpactEdge): string; static;
    /// <summary>"depth", "count", "time".</summary>
    class function LimitName(ALimit: TImpactLimit): string; static;
    /// <summary>Antwort von atlas/impact; der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AResult: TImpactResult): TJSONObject; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Optionen je Datei; nicht gesetzt: Vorgaben.</summary>
    property OptionsFor: TImpactOptionsProvider read FOptionsFor write FOptionsFor;
  end;

implementation

uses
  System.StrUtils,
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Common.Lsp.Internals.Namespaces,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.Usages,
  Atlas.Common.Editing.TestUnits,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Pascal.Lexer,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TImpactText = (TimeLimitOfTheImpact, FieldsTextDocumentUriAndPosition);

const
  cTexts: array[TImpactText] of TAtlasText = (
    (De: 'Zeitlimit der Auswirkungsanalyse erreicht'; En: 'Time limit of the impact analysis reached'),
    (De: 'Felder "textDocument.uri" und "position" fehlen in ';
     En: 'Fields "textDocument.uri" and "position" missing in '));

{$SCOPEDENUMS OFF}

const
  // Bäume, die eine Analyse höchstens zugleich hält; danach werden sie verworfen.
  cMaxCachedTrees = 64;
  // Nachfahren eines Typs, die nach Overrides durchsucht werden.
  cMaxDescendants = 500;
  // Vorfahren bis zur überschriebenen Basismethode.
  cMaxAncestors = 32;

type
  /// <summary>Zeitlimit der Analyse; zu Ende gelaufen bricht die nächste Prüfung mit EImpactTimeLimit ab.</summary>
  EImpactTimeLimit = class(Exception);

  TImpactDeadline = class(TInterfacedObject, IJsonRpcCancellationToken)
  private
    FInner: IJsonRpcCancellationToken;
    FClock: TStopwatch;
    FLimitMs: Int64;
  public
    constructor Create(const AInner: IJsonRpcCancellationToken; ALimitMs: Integer);
    function Expired: Boolean;
    function IsCancellationRequested: Boolean;
    procedure ThrowIfCancellationRequested;
  end;

  /// <summary>Gelesene Dateien einer oder mehrerer Analysen (AnalyzeEach, #1353).</summary>
  TImpactFiles = class
  public
    Trees: TObjectDictionary<string, TSyntaxTree>;
    Units: TDictionary<string, TUnitIndex>;
    Forms: TImpactFormCache;
    TestUnits: TDictionary<string, TDUnitXUnit>;
    constructor Create(const AReadText: TReferenceReadText);
    destructor Destroy; override;
  end;

  /// <summary>Ein Schritt der Verfolgung: Ebene, verursachende Stelle und die Liste der Stellen der nächsten
  /// Ebene.</summary>
  TImpactStep = record
    Cause: Integer;
    Level: Integer;
    Next: TList<Integer>;
  end;

  /// <summary>Zustand einer Analyse.</summary>
  TImpactRun = class
  private
    FResolver: TNameResolver;
    FIndex: ISymbolIndex;
    FSources: TImpactSources;
    FOptions: TImpactOptions;
    FToken: IJsonRpcCancellationToken;
    FDeadline: TImpactDeadline;
    FPlaces: TList<TImpactPlace>;
    FTests: TList<TImpactTest>;
    /// <summary>Deklarationsschlüssel → Index in FPlaces; -1 = das Symbol.</summary>
    FKeys: TDictionary<string, Integer>;
    FCache: TImpactFiles;
    FOwnsFiles: Boolean;
    FMaxPlaces: Integer;
    FFull: Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function TreeOf(const AFileName: string): TSyntaxTree;
    function ExtractedUnit(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    function Declaration(const AItem: THierarchyItem; out ATarget: TDefinitionTarget): Boolean;
    /// <summary>Schlüssel einer Stelle: ihre Deklaration; bei der Unit selbst (ATerminal) die Fundstelle.</summary>
    function KeyOf(const AItem: THierarchyItem; ATerminal: Boolean): string;
    function DeclarationSymbol(const AItem: THierarchyItem; out AUnit: TUnitIndex; out ASymbol: TIndexSymbol): Boolean;
    function TestOf(const AItem: THierarchyItem; ALevel: Integer): Integer;
    function UnitNameOf(const AFileName: string): string;
    /// <summary>Neue Stelle; False, wenn sie schon auf einer kleineren oder derselben Ebene steht oder die
    /// Höchstzahl erreicht ist. Steht sie mit derselben Ursache schon da, kommen ARanges dazu.</summary>
    function Add(const AItem: THierarchyItem; const AStep: TImpactStep; AEdge: TImpactEdge;
      const ARanges: TArray<TTextRange>; const AConfidence: TReferenceConfidence; ATerminal: Boolean): Boolean;
    /// <summary>Wie Add für eine Stelle ohne Verwendungen (Override, Interface), sicher erkannt.</summary>
    procedure AddSure(const AItem: THierarchyItem; const AStep: TImpactStep; AEdge: TImpactEdge);
    /// <summary>Innerste Deklaration um APosition; ohne eine die Unit selbst mit ATerminal.</summary>
    function EnclosingDeclaration(const AFileName: string; const APosition: TTextPosition;
      out AItem: THierarchyItem; out ATerminal: Boolean): Boolean;
    function MemberOf(const AFileName, ATypeName, AName: string; out AItem: THierarchyItem): Boolean;
    function TypeSymbol(const AFromUnit: TUnitIndex; const ATypeName: string; out AUnit: TUnitIndex;
      out ASymbol: TIndexSymbol): Boolean;
    /// <summary>Betroffene Stelle eines Verweises auf AItem; False, wenn es keine neue ist.</summary>
    function PlaceAt(const AItem: THierarchyItem; const ALocation: TReferenceLocation; out APlace: THierarchyItem;
      out ATerminal: Boolean): Boolean;
    procedure AddReferences(const AItem: THierarchyItem; const AStep: TImpactStep);
    /// <summary>Overrides der Methode AOwn im Nachfahren ALocation bzw. ihre Umsetzung (AInterface).</summary>
    procedure AddDescendant(const AOwn: TIndexSymbol; AInterface: Boolean; const ALocation: TSymbolLocation;
      const AStep: TImpactStep);
    /// <summary>Overrides in allen Nachfahren bzw. Umsetzungen der Interface-Methode.</summary>
    procedure AddDescendants(const AOwn: TIndexSymbol; AInterface: Boolean; const AStep: TImpactStep);
    /// <summary>Überschriebene Basismethode: der nächste Vorfahr mit einer gleichnamigen Methode.</summary>
    procedure AddBaseMethod(const AOwnUnit: TUnitIndex; const AOwn, AOwner: TIndexSymbol; const AStep: TImpactStep);
    /// <summary>Interface-Methoden, die die Methode umsetzt: gleichnamige oder per Methodenzuordnung.</summary>
    procedure AddInterfaceMethods(const AOwnUnit: TUnitIndex; const AOwn, AOwner: TIndexSymbol;
      const AStep: TImpactStep);
    procedure AddStructural(const AItem: THierarchyItem; const AStep: TImpactStep);
    procedure Expand(const AItem: THierarchyItem; const AStep: TImpactStep);
    /// <summary>Eine Ebene: alle Stellen aus AFrontier verfolgen, neue nach ANext.</summary>
    procedure ExpandLevel(const AStart: THierarchyItem; AFrontier, ANext: TList<Integer>; ALevel: Integer);
  public
    /// <summary>AShared: gelesene Dateien mehrerer Läufe (bleibt beim Aufrufer); nil = eigene.</summary>
    constructor Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; const ASources: TImpactSources;
      const AOptions: TImpactOptions; const ACancellation: IJsonRpcCancellationToken; AShared: TImpactFiles);
    destructor Destroy; override;
    function Run(const AStart: THierarchyItem): TImpactResult;
  end;

function WithoutGenerics(const AName: string): string;
var
  mBracket: Integer;
begin
  mBracket := Pos('<', AName);
  if mBracket > 0 then
  begin
    Result := Copy(AName, 1, mBracket - 1);
  end
  else
  begin
    Result := AName;
  end;
end;

function RangeContains(const AOuter: TTextRange; const APosition: TTextPosition): Boolean;

  function Compare(const A, B: TTextPosition): Integer;
  begin
    if A.Line <> B.Line then
    begin
      Result := A.Line - B.Line;
    end
    else
    begin
      Result := A.Character - B.Character;
    end;
  end;

begin
  Result := (Compare(AOuter.StartPos, APosition) <= 0) and (Compare(APosition, AOuter.EndPos) <= 0);
end;

function RangeSize(const ARange: TTextRange): Int64;
begin
  Result := Int64(ARange.EndPos.Line - ARange.StartPos.Line) * 100000 + ARange.EndPos.Character -
    ARange.StartPos.Character;
end;

const
  cTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType];
  cMethodKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_];

{ TImpactDeadline }

constructor TImpactDeadline.Create(const AInner: IJsonRpcCancellationToken; ALimitMs: Integer);
begin
  inherited Create;
  FInner := AInner;
  FLimitMs := ALimitMs;
  FClock := TStopwatch.StartNew;
end;

function TImpactDeadline.Expired: Boolean;
begin
  Result := (FLimitMs > 0) and (FClock.ElapsedMilliseconds >= FLimitMs);
end;

function TImpactDeadline.IsCancellationRequested: Boolean;
begin
  Result := Expired or ((FInner <> nil) and FInner.IsCancellationRequested);
end;

procedure TImpactDeadline.ThrowIfCancellationRequested;
begin
  if FInner <> nil then
  begin
    FInner.ThrowIfCancellationRequested;
  end;
  if Expired then
  begin
    raise EImpactTimeLimit.Create(cTexts[TImpactText.TimeLimitOfTheImpact].Text);
  end;
end;

{ TImpactTestScope }

function TImpactTestScope.Contains(const AUnitName: string): Boolean;
var
  mTested: string;
begin
  Result := (AUnitName <> '') and ((IndexText(AUnitName, Units) >= 0) or
    TTestUnits.TestedUnitName(AUnitName, Pattern, mTested));
end;

class function TImpactTestScope.FromProgram(const APattern, AProgramText: string): TImpactTestScope;
begin
  Result := Default(TImpactTestScope);
  Result.Pattern := APattern;
  if AProgramText <> '' then
  begin
    Result.Units := TUsesClauses.UsedUnits(TPascalLexer.Tokenize(AProgramText));
  end;
end;

{ TImpactOptions }

class function TImpactOptions.Default: TImpactOptions;
begin
  // Ohne Default(TImpactOptions): Hier hieße das die Methode selbst.
  Result.Depth := TImpactAnalysis.cDefaultDepth;
  Result.MaxPlaces := TImpactAnalysis.cMaxPlaces;
  Result.TimeoutMs := 0;
  Result.References := TReferenceSettings.Default;
  Result.Tests.Pattern := TTestUnits.cDefaultPattern;
  Result.Tests.Units := nil;
end;

{ TImpactResult }

function TImpactResult.LevelCount(ALevel: Integer): Integer;
var
  mPlace: TImpactPlace;
begin
  Result := 0;
  for mPlace in Places do
  begin
    if mPlace.Level = ALevel then
    begin
      Inc(Result);
    end;
  end;
end;

function TImpactResult.RunNames: TArray<string>;
var
  mTest: TImpactTest;
  mName: string;
  mSeen: TDictionary<string, Boolean>;
begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mTest in Tests do
    begin
      for mName in mTest.RunNames do
      begin
        if not mSeen.ContainsKey(UpperCase(mName)) then
        begin
          mSeen.Add(UpperCase(mName), True);
          Result := Result + [mName];
        end;
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

{ TImpactFiles }

constructor TImpactFiles.Create(const AReadText: TReferenceReadText);
begin
  inherited Create;
  Trees := TObjectDictionary<string, TSyntaxTree>.Create([doOwnsValues]);
  Units := TDictionary<string, TUnitIndex>.Create;
  Forms := TImpactFormCache.Create(AReadText);
  TestUnits := TDictionary<string, TDUnitXUnit>.Create;
end;

destructor TImpactFiles.Destroy;
begin
  TestUnits.Free;
  Forms.Free;
  Units.Free;
  Trees.Free;
  inherited;
end;

{ TImpactRun }

constructor TImpactRun.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; const ASources: TImpactSources;
  const AOptions: TImpactOptions; const ACancellation: IJsonRpcCancellationToken; AShared: TImpactFiles);
begin
  inherited Create;
  FResolver := AResolver;
  FIndex := AIndex;
  FSources := ASources;
  FOptions := AOptions;
  FOptions.Depth := TImpactAnalysis.ClampDepth(AOptions.Depth);
  FMaxPlaces := AOptions.MaxPlaces;
  if (FMaxPlaces <= 0) or (FMaxPlaces > TImpactAnalysis.cMaxPlaces) then
  begin
    FMaxPlaces := TImpactAnalysis.cMaxPlaces;
  end;
  FDeadline := TImpactDeadline.Create(ACancellation, AOptions.TimeoutMs);
  FToken := FDeadline;
  FPlaces := TList<TImpactPlace>.Create;
  FTests := TList<TImpactTest>.Create;
  FKeys := TDictionary<string, Integer>.Create;
  FOwnsFiles := AShared = nil;
  if FOwnsFiles then
  begin
    FCache := TImpactFiles.Create(ASources.ReadText);
  end
  else
  begin
    FCache := AShared;
  end;
end;

destructor TImpactRun.Destroy;
begin
  if FOwnsFiles then
  begin
    FCache.Free;
  end;
  FKeys.Free;
  FTests.Free;
  FPlaces.Free;
  FToken := nil;
  inherited;
end;

function TImpactRun.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := Assigned(FSources.ReadText) and FSources.ReadText(AFileName, AText);
end;

function TImpactRun.TreeOf(const AFileName: string): TSyntaxTree;
var
  mText: string;
begin
  if FCache.Trees.TryGetValue(UpperCase(AFileName), Result) then
  begin
    Exit;
  end;
  Result := nil;
  if not ReadText(AFileName, mText) then
  begin
    Exit;
  end;
  // Große Gruppen: nicht alle Bäume zugleich halten.
  if FCache.Trees.Count >= cMaxCachedTrees then
  begin
    FCache.Trees.Clear;
    FCache.Units.Clear;
  end;
  Result := TSyntaxTreeCache.Parse(mText);
  FCache.Trees.Add(UpperCase(AFileName), Result);
end;

function TImpactRun.ExtractedUnit(const AFileName: string; out AUnit: TUnitIndex): Boolean;
var
  mTree: TSyntaxTree;
begin
  if FCache.Units.TryGetValue(UpperCase(AFileName), AUnit) then
  begin
    Exit(True);
  end;
  mTree := TreeOf(AFileName);
  Result := mTree <> nil;
  if Result then
  begin
    AUnit := TIndexExtractor.Extract(mTree, AFileName);
    FCache.Units.AddOrSetValue(UpperCase(AFileName), AUnit);
  end;
end;

function TImpactRun.Declaration(const AItem: THierarchyItem; out ATarget: TDefinitionTarget): Boolean;
var
  mTree: TSyntaxTree;
  mTargets: TArray<TDefinitionTarget>;
begin
  Result := False;
  mTree := TreeOf(AItem.FileName);
  if mTree = nil then
  begin
    Exit;
  end;
  mTargets := TLspDefinition.Targets(FResolver, FIndex, mTree, AItem.FileName, AItem.SelectionRange.StartPos, True);
  Result := Length(mTargets) > 0;
  if Result then
  begin
    ATarget := mTargets[0];
  end;
end;

function TImpactRun.KeyOf(const AItem: THierarchyItem; ATerminal: Boolean): string;
var
  mTarget: TDefinitionTarget;
begin
  // Rumpf und Deklaration einer Methode sind dieselbe Stelle: Schlüssel ist die Deklaration.
  if not ATerminal and Declaration(AItem, mTarget) then
  begin
    Result := UpperCase(mTarget.FileName) + '|' + IntToStr(mTarget.SelectionRange.StartPos.Line) + ':' +
      IntToStr(mTarget.SelectionRange.StartPos.Character);
  end
  else
  begin
    Result := UpperCase(AItem.FileName) + '|' + IntToStr(AItem.SelectionRange.StartPos.Line) + ':' +
      IntToStr(AItem.SelectionRange.StartPos.Character);
  end;
end;

function TImpactRun.DeclarationSymbol(const AItem: THierarchyItem; out AUnit: TUnitIndex;
  out ASymbol: TIndexSymbol): Boolean;
var
  mTarget: TDefinitionTarget;
  mIndex: Integer;
begin
  Result := False;
  if not Declaration(AItem, mTarget) then
  begin
    Exit;
  end;
  if not (FIndex.FindFile(mTarget.FileName, AUnit) or ExtractedUnit(mTarget.FileName, AUnit)) then
  begin
    Exit;
  end;
  for mIndex in AUnit.SymbolsNamed(AItem.Name) do
  begin
    if (AUnit.Symbols[mIndex].SelectionRange.StartPos = mTarget.SelectionRange.StartPos) and
      SameText(AUnit.SymbolFile(AUnit.Symbols[mIndex]), mTarget.FileName) then
    begin
      ASymbol := AUnit.Symbols[mIndex];
      Exit(True);
    end;
  end;
end;

function TImpactRun.UnitNameOf(const AFileName: string): string;
var
  mIndexed: TUnitIndex;
begin
  if FIndex.FindFile(AFileName, mIndexed) or ExtractedUnit(AFileName, mIndexed) then
  begin
    Result := mIndexed.UnitName;
  end
  else
  begin
    Result := '';
  end;
end;

function TImpactRun.TestOf(const AItem: THierarchyItem; ALevel: Integer): Integer;
var
  mText, mUnitName: string;
  mIndexed: TUnitIndex;
  mSource: TDUnitXUnit;
  mFixtureIndex, mTestIndex: Integer;
  mTest: TImpactTest;
begin
  Result := -1;
  if not TLspHierarchies.IsRoutine(AItem) or (AItem.Container = '') then
  begin
    Exit;
  end;
  if FIndex.FindFile(AItem.FileName, mIndexed) then
  begin
    mUnitName := mIndexed.UnitName;
  end
  else
  begin
    mUnitName := '';
  end;
  if not FCache.TestUnits.TryGetValue(UpperCase(AItem.FileName), mSource) then
  begin
    mSource := Default(TDUnitXUnit);
    // Nur Testunits parsen: Attribute stehen nicht im Index.
    if ((mUnitName = '') or FOptions.Tests.Contains(mUnitName)) and ReadText(AItem.FileName, mText) then
    begin
      mSource := TDUnitXSource.Scan(TTextLines.SplitLines(mText));
      if not FOptions.Tests.Contains(mSource.UnitName) then
      begin
        mSource := Default(TDUnitXUnit);
      end;
    end;
    FCache.TestUnits.Add(UpperCase(AItem.FileName), mSource);
  end;
  if not mSource.Find(AItem.Container, AItem.Name, mFixtureIndex, mTestIndex) or (mTestIndex < 0) then
  begin
    Exit;
  end;
  mTest.Name := TDUnitXCommandLine.TestName(mSource.UnitName, mSource.Fixtures[mFixtureIndex].Name,
    mSource.Fixtures[mFixtureIndex].Tests[mTestIndex].Method);
  mTest.RunNames := TDUnitXCommandLine.RunNames(mSource, mFixtureIndex, mTestIndex, -1);
  if mTest.RunNames = nil then
  begin
    mTest.RunNames := [mTest.Name];
  end;
  mTest.FileName := AItem.FileName;
  mTest.Line := mSource.LineOf(mSource.Fixtures[mFixtureIndex].Name,
    mSource.Fixtures[mFixtureIndex].Tests[mTestIndex].Method);
  mTest.Level := ALevel;
  Result := FTests.Add(mTest);
end;

function TImpactRun.Add(const AItem: THierarchyItem; const AStep: TImpactStep; AEdge: TImpactEdge;
  const ARanges: TArray<TTextRange>; const AConfidence: TReferenceConfidence; ATerminal: Boolean): Boolean;
var
  mKey: string;
  mSlot: Integer;
  mPlace: TImpactPlace;
begin
  Result := False;
  mKey := KeyOf(AItem, ATerminal);
  if FKeys.TryGetValue(mKey, mSlot) then
  begin
    // Gleiche Stelle, gleiche Ursache: weitere Verwendungen. Sichere Verwendung schlägt erschlossene.
    if (mSlot >= 0) and (FPlaces[mSlot].Level = AStep.Level) and (FPlaces[mSlot].Cause = AStep.Cause) then
    begin
      mPlace := FPlaces[mSlot];
      mPlace.Ranges := mPlace.Ranges + ARanges;
      if AConfidence.IsSure then
      begin
        mPlace.Confidence := AConfidence;
      end;
      FPlaces[mSlot] := mPlace;
    end;
    Exit;
  end;
  if FPlaces.Count >= FMaxPlaces then
  begin
    FFull := True;
    Exit;
  end;
  mPlace := Default(TImpactPlace);
  mPlace.Item := AItem;
  // Aufrufer aus dem Syntaxbaum (CallerAt) kennen ihre Unit nicht.
  if mPlace.Item.UnitName = '' then
  begin
    mPlace.Item.UnitName := UnitNameOf(AItem.FileName);
  end;
  mPlace.Level := AStep.Level;
  mPlace.Edge := AEdge;
  mPlace.Cause := AStep.Cause;
  mPlace.Ranges := ARanges;
  mPlace.Confidence := AConfidence;
  mPlace.Terminal := ATerminal;
  mPlace.Forms := FCache.Forms.Bindings(AItem.Name, AItem.FileName);
  mPlace.Test := TestOf(AItem, AStep.Level);
  mSlot := FPlaces.Add(mPlace);
  FKeys.Add(mKey, mSlot);
  if not ATerminal then
  begin
    AStep.Next.Add(mSlot);
  end;
  Result := True;
end;

procedure TImpactRun.AddSure(const AItem: THierarchyItem; const AStep: TImpactStep; AEdge: TImpactEdge);
begin
  Add(AItem, AStep, AEdge, nil, TReferenceConfidence.Sure, False);
end;

function TImpactRun.EnclosingDeclaration(const AFileName: string; const APosition: TTextPosition;
  out AItem: THierarchyItem; out ATerminal: Boolean): Boolean;
var
  mExtracted: TUnitIndex;
  mSymbol, mBest: TIndexSymbol;
  mFound: Boolean;
begin
  Result := False;
  ATerminal := False;
  if not ExtractedUnit(AFileName, mExtracted) then
  begin
    Exit;
  end;
  mFound := False;
  for mSymbol in mExtracted.Symbols do
  begin
    if RangeContains(mSymbol.Range, APosition) and
      (not mFound or (RangeSize(mSymbol.Range) < RangeSize(mBest.Range))) then
    begin
      mBest := mSymbol;
      mFound := True;
    end;
  end;
  if mFound then
  begin
    AItem := TLspHierarchies.ItemOf(mExtracted.UnitName, AFileName, mBest);
    Exit(True);
  end;
  // Unit-Ebene (initialization, finalization, Rumpf des Programms): die Unit selbst.
  AItem := Default(THierarchyItem);
  AItem.Name := mExtracted.UnitName;
  if AItem.Name = '' then
  begin
    AItem.Name := ChangeFileExt(ExtractFileName(AFileName), '');
  end;
  AItem.SymbolKind := TIndexSymbolKind.Variable;
  AItem.UnitName := mExtracted.UnitName;
  AItem.FileName := AFileName;
  AItem.Range := TTextRange.Create(APosition, APosition);
  AItem.SelectionRange := AItem.Range;
  ATerminal := True;
  Result := True;
end;

function TImpactRun.MemberOf(const AFileName, ATypeName, AName: string; out AItem: THierarchyItem): Boolean;
var
  mIndexed: TUnitIndex;
  mIndex: Integer;
begin
  Result := False;
  if not FIndex.FindFile(AFileName, mIndexed) then
  begin
    Exit;
  end;
  for mIndex in mIndexed.SymbolsNamed(AName) do
  begin
    if (mIndexed.Symbols[mIndex].Kind in cMethodKinds) and SameText(mIndexed.Symbols[mIndex].Container, ATypeName) then
    begin
      AItem := TLspHierarchies.ItemOf(mIndexed.UnitName, mIndexed.SymbolFile(mIndexed.Symbols[mIndex]),
        mIndexed.Symbols[mIndex]);
      Exit(True);
    end;
  end;
end;

function TImpactRun.TypeSymbol(const AFromUnit: TUnitIndex; const ATypeName: string; out AUnit: TUnitIndex;
  out ASymbol: TIndexSymbol): Boolean;
var
  mResolved: TResolvedSymbol;
  mIndex: Integer;
begin
  Result := False;
  if not FResolver.ResolveTypeFrom(AFromUnit, WithoutGenerics(ATypeName), mResolved) or
    not (mResolved.SymbolKind in cTypeKinds) or not FIndex.FindFile(mResolved.FileName, AUnit) then
  begin
    Exit;
  end;
  for mIndex in AUnit.SymbolsNamed(mResolved.Name) do
  begin
    if (AUnit.Symbols[mIndex].Kind in cTypeKinds) and
      SameText(AUnit.Symbols[mIndex].Container, mResolved.Container) then
    begin
      ASymbol := AUnit.Symbols[mIndex];
      Exit(True);
    end;
  end;
end;

function TImpactRun.PlaceAt(const AItem: THierarchyItem; const ALocation: TReferenceLocation;
  out APlace: THierarchyItem; out ATerminal: Boolean): Boolean;
var
  mTree: TSyntaxTree;
begin
  ATerminal := False;
  // Formularbindungen gehören zur Stelle selbst (TImpactFormCache), nicht zur nächsten Ebene.
  mTree := nil;
  if not TImpactFormCache.IsFormFile(ALocation.FileName) then
  begin
    mTree := TreeOf(ALocation.FileName);
  end;
  if mTree = nil then
  begin
    Exit(False);
  end;
  if TLspHierarchies.CallerAt(mTree, ALocation.FileName, ALocation.Range.StartPos, APlace) then
  begin
    Exit(True);
  end;
  // Die Unit selbst (Terminal) ist keine Deklaration, die man weiter verfolgen könnte.
  Result := EnclosingDeclaration(ALocation.FileName, ALocation.Range.StartPos, APlace, ATerminal);
  // Der Verweis steht in der eigenen Deklaration (Methodenkopf in der Klasse): keine neue Stelle.
  if Result and not ATerminal then
  begin
    Result := KeyOf(APlace, False) <> KeyOf(AItem, False);
  end;
end;

procedure TImpactRun.AddReferences(const AItem: THierarchyItem; const AStep: TImpactStep);
var
  mTree: TSyntaxTree;
  mLocations: TArray<TReferenceLocation>;
  mLocation: TReferenceLocation;
  mPlace: THierarchyItem;
  mEdge: TImpactEdge;
  mTerminal: Boolean;
begin
  mTree := TreeOf(AItem.FileName);
  if mTree = nil then
  begin
    Exit;
  end;
  mLocations := TLspReferences.Find(FResolver, FIndex, mTree, TReferenceSearch.Create(AItem.FileName,
    AItem.SelectionRange.StartPos, False, TImpactAnalysis.CandidateFiles(FIndex, FSources.Files, AItem.Name),
    FSources.ReadText), FOptions.References, FToken);
  mEdge := TImpactEdge.Reference;
  if TLspHierarchies.IsRoutine(AItem) then
  begin
    mEdge := TImpactEdge.Call;
  end;
  for mLocation in mLocations do
  begin
    FToken.ThrowIfCancellationRequested;
    if PlaceAt(AItem, mLocation, mPlace, mTerminal) then
    begin
      Add(mPlace, AStep, mEdge, [mLocation.Range], mLocation.Confidence, mTerminal);
    end;
  end;
end;

/// <summary>Umsetzung der Interface-Methode AOwn in einem Typ mit den Methodenzuordnungen AResolutions: die
/// gleichnamige Methode oder das Ziel von IFoo.Bar = Baz.</summary>
function ImplementationTarget(const AOwn: TIndexSymbol; const AResolutions: TArray<string>): string;
var
  mResolution: string;
  mEqualsAt: Integer;
begin
  Result := AOwn.Name;
  for mResolution in AResolutions do
  begin
    mEqualsAt := Pos('=', mResolution);
    if (mEqualsAt > 0) and SameText(Trim(Copy(mResolution, 1, mEqualsAt - 1)), AOwn.Container + '.' + AOwn.Name) then
    begin
      Result := Trim(Copy(mResolution, mEqualsAt + 1, MaxInt));
    end;
  end;
end;

/// <summary>Methode des Interfaces AAncestor, die die Methode AName des Typs AOwner umsetzt: die gleichnamige
/// oder die per Methodenzuordnung IFoo.Bar = AName.</summary>
function InterfaceTarget(const AOwner: TIndexSymbol; const AAncestor, AName: string): string;
var
  mResolution, mPrefix, mSource: string;
  mEqualsAt: Integer;
begin
  Result := AName;
  mPrefix := WithoutGenerics(AAncestor) + '.';
  for mResolution in AOwner.Resolutions do
  begin
    mEqualsAt := Pos('=', mResolution);
    mSource := Trim(Copy(mResolution, 1, mEqualsAt - 1));
    if (mEqualsAt > 0) and SameText(Trim(Copy(mResolution, mEqualsAt + 1, MaxInt)), AName) and
      StartsText(mPrefix, mSource) then
    begin
      Result := Copy(mSource, Length(mPrefix) + 1, MaxInt);
    end;
  end;
end;

/// <summary>Typ, zu dem die Methode AOwn in AUnit gehört.</summary>
function OwnerOf(const AUnit: TUnitIndex; const AOwn: TIndexSymbol; out AOwner: TIndexSymbol): Boolean;
var
  mIndex: Integer;
begin
  for mIndex in AUnit.SymbolsNamed(AOwn.Container) do
  begin
    if AUnit.Symbols[mIndex].Kind in cTypeKinds then
    begin
      AOwner := AUnit.Symbols[mIndex];
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TImpactRun.AddDescendant(const AOwn: TIndexSymbol; AInterface: Boolean; const ALocation: TSymbolLocation;
  const AStep: TImpactStep);
var
  mTypeUnit: TUnitIndex;
  mMember: THierarchyItem;
  mIndex: Integer;
begin
  if AInterface then
  begin
    if (ALocation.Symbol.Kind <> TIndexSymbolKind.InterfaceType) and MemberOf(ALocation.FileName,
      ALocation.Symbol.Name, ImplementationTarget(AOwn, ALocation.Symbol.Resolutions), mMember) then
    begin
      AddSure(mMember, AStep, TImpactEdge.Implementation_);
    end;
    Exit;
  end;
  if not FIndex.FindFile(ALocation.FileName, mTypeUnit) then
  begin
    Exit;
  end;
  for mIndex in mTypeUnit.SymbolsNamed(AOwn.Name) do
  begin
    if SameText(mTypeUnit.Symbols[mIndex].Container, ALocation.Symbol.Name) and
      mTypeUnit.Symbols[mIndex].HasDirective('override') then
    begin
      AddSure(TLspHierarchies.ItemOf(mTypeUnit.UnitName, mTypeUnit.SymbolFile(mTypeUnit.Symbols[mIndex]),
        mTypeUnit.Symbols[mIndex]), AStep, TImpactEdge.Override_);
      Exit;
    end;
  end;
end;

procedure TImpactRun.AddDescendants(const AOwn: TIndexSymbol; AInterface: Boolean; const AStep: TImpactStep);
var
  mPending: TQueue<string>;
  mSeen: TDictionary<string, Boolean>;
  mLocation: TSymbolLocation;
begin
  mPending := TQueue<string>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mPending.Enqueue(AOwn.Container);
    mSeen.Add(UpperCase(AOwn.Container), True);
    while (mPending.Count > 0) and (mSeen.Count < cMaxDescendants) do
    begin
      FToken.ThrowIfCancellationRequested;
      for mLocation in FIndex.Descendants(mPending.Dequeue) do
      begin
        if (mLocation.Symbol.Kind in cTypeKinds) and not mSeen.ContainsKey(UpperCase(mLocation.Symbol.Name)) then
        begin
          mSeen.Add(UpperCase(mLocation.Symbol.Name), True);
          mPending.Enqueue(mLocation.Symbol.Name);
          AddDescendant(AOwn, AInterface, mLocation, AStep);
        end;
      end;
    end;
  finally
    mSeen.Free;
    mPending.Free;
  end;
end;

procedure TImpactRun.AddBaseMethod(const AOwnUnit: TUnitIndex; const AOwn, AOwner: TIndexSymbol;
  const AStep: TImpactStep);
var
  mTypeUnit, mBaseUnit: TUnitIndex;
  mFound, mBase: TIndexSymbol;
  mMember: THierarchyItem;
  mSteps: Integer;
begin
  mTypeUnit := AOwnUnit;
  mFound := AOwner;
  for mSteps := 1 to cMaxAncestors do
  begin
    if (Length(mFound.Ancestors) = 0) or not TypeSymbol(mTypeUnit, mFound.Ancestors[0], mBaseUnit, mBase) or
      (mBase.Kind = TIndexSymbolKind.InterfaceType) then
    begin
      Exit;
    end;
    if MemberOf(mBaseUnit.FileName, mBase.Name, AOwn.Name, mMember) then
    begin
      AddSure(mMember, AStep, TImpactEdge.BaseMethod);
      Exit;
    end;
    mTypeUnit := mBaseUnit;
    mFound := mBase;
  end;
end;

procedure TImpactRun.AddInterfaceMethods(const AOwnUnit: TUnitIndex; const AOwn, AOwner: TIndexSymbol;
  const AStep: TImpactStep);
var
  mBaseUnit: TUnitIndex;
  mBase: TIndexSymbol;
  mMember: THierarchyItem;
  mAncestor: string;
begin
  for mAncestor in AOwner.Ancestors do
  begin
    if TypeSymbol(AOwnUnit, mAncestor, mBaseUnit, mBase) and (mBase.Kind = TIndexSymbolKind.InterfaceType) and
      MemberOf(mBaseUnit.FileName, mBase.Name, InterfaceTarget(AOwner, mAncestor, AOwn.Name), mMember) then
    begin
      AddSure(mMember, AStep, TImpactEdge.InterfaceMethod);
    end;
  end;
end;

procedure TImpactRun.AddStructural(const AItem: THierarchyItem; const AStep: TImpactStep);
var
  mOwnUnit: TUnitIndex;
  mOwn, mOwner: TIndexSymbol;
  mOwnerFound, mIsInterface: Boolean;
begin
  if not (AItem.SymbolKind in cMethodKinds) or (AItem.Container = '') or
    not DeclarationSymbol(AItem, mOwnUnit, mOwn) then
  begin
    Exit;
  end;
  mOwnerFound := OwnerOf(mOwnUnit, mOwn, mOwner);
  mIsInterface := mOwnerFound and (mOwner.Kind = TIndexSymbolKind.InterfaceType);
  if mOwn.IsVirtual or mIsInterface then
  begin
    AddDescendants(mOwn, mIsInterface, AStep);
  end;
  if not mOwnerFound or mIsInterface then
  begin
    Exit;
  end;
  if mOwn.HasDirective('override') then
  begin
    AddBaseMethod(mOwnUnit, mOwn, mOwner, AStep);
  end;
  AddInterfaceMethods(mOwnUnit, mOwn, mOwner, AStep);
end;

procedure TImpactRun.Expand(const AItem: THierarchyItem; const AStep: TImpactStep);
begin
  FToken.ThrowIfCancellationRequested;
  AddReferences(AItem, AStep);
  AddStructural(AItem, AStep);
end;

procedure TImpactRun.ExpandLevel(const AStart: THierarchyItem; AFrontier, ANext: TList<Integer>; ALevel: Integer);
var
  mStep: TImpactStep;
  mSlot: Integer;
begin
  mStep.Level := ALevel;
  mStep.Next := ANext;
  for mSlot in AFrontier do
  begin
    if FFull then
    begin
      Exit;
    end;
    mStep.Cause := mSlot;
    if mSlot < 0 then
    begin
      Expand(AStart, mStep);
    end
    else
    begin
      Expand(FPlaces[mSlot].Item, mStep);
    end;
  end;
end;

function TImpactRun.Run(const AStart: THierarchyItem): TImpactResult;
var
  mFrontier, mNext: TList<Integer>;
  mLevel: Integer;
begin
  Result := Default(TImpactResult);
  Result.Symbol := AStart;
  Result.Depth := FOptions.Depth;
  Result.MaxPlaces := FMaxPlaces;
  Result.TimeoutMs := FOptions.TimeoutMs;
  mFrontier := TList<Integer>.Create;
  mNext := TList<Integer>.Create;
  try
    try
      Result.SymbolForms := FCache.Forms.Bindings(AStart.Name, AStart.FileName);
      FKeys.Add(KeyOf(AStart, False), -1);
      // Das Symbol selbst kann ein Test sein (Ebene 0).
      TestOf(AStart, 0);
      mFrontier.Add(-1);
      for mLevel := 1 to FOptions.Depth do
      begin
        mNext.Clear;
        ExpandLevel(AStart, mFrontier, mNext, mLevel);
        mFrontier.Clear;
        mFrontier.AddRange(mNext.ToArray);
        if (mFrontier.Count = 0) or FFull then
        begin
          Break;
        end;
      end;
      // Stellen der letzten Ebene, deren Verwendungen nicht mehr gesucht wurden.
      if not FFull and (mFrontier.Count > 0) then
      begin
        Include(Result.Limits, TImpactLimit.Depth);
        Result.Unexpanded := mFrontier.Count;
      end;
    except
      on EImpactTimeLimit do
        Include(Result.Limits, TImpactLimit.Time);
    end;
    if FFull then
    begin
      Include(Result.Limits, TImpactLimit.Count);
    end;
    Result.Places := FPlaces.ToArray;
    Result.Tests := FTests.ToArray;
  finally
    mNext.Free;
    mFrontier.Free;
  end;
end;

{ TImpactSources }

class function TImpactSources.Create(const AFiles: TArray<string>; const AReadText: TReferenceReadText): TImpactSources;
begin
  Result.Files := AFiles;
  Result.ReadText := AReadText;
end;

{ TImpactAnalysis }

constructor TImpactAnalysis.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider);
begin
  Create(AStore, AIndex, AReadText, AFiles, nil);
end;

constructor TImpactAnalysis.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FFiles := AFiles;
  FEnsureUnit := AEnsureUnit;
end;

function TImpactAnalysis.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TImpactAnalysis.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

procedure TImpactAnalysis.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cMethod, HandleImpact);
end;

class function TImpactAnalysis.ClampDepth(ADepth: Integer): Integer;
begin
  Result := ADepth;
  if Result < cMinDepth then
  begin
    Result := cMinDepth;
  end
  else if Result > cMaxDepth then
  begin
    Result := cMaxDepth;
  end;
end;

class function TImpactAnalysis.CandidateFiles(const AIndex: ISymbolIndex; const AFiles: TArray<string>;
  const AName: string): TArray<string>;
var
  mFileName, mAlternative: string;
  mCount: Integer;
begin
  // Attribute (#119): [Foo] verwendet FooAttribute; wie in der Referenzsuche beide Schreibweisen.
  if EndsText('Attribute', AName) and (Length(AName) > Length('Attribute')) then
  begin
    mAlternative := Copy(AName, 1, Length(AName) - Length('Attribute'));
  end
  else
  begin
    mAlternative := AName + 'Attribute';
  end;
  SetLength(Result, Length(AFiles));
  mCount := 0;
  for mFileName in AFiles do
  begin
    if (TIndexUsages.Lookup(AIndex, mFileName, AName) <> TIndexUsageAnswer.Absent) or
      (TIndexUsages.Lookup(AIndex, mFileName, mAlternative) <> TIndexUsageAnswer.Absent) then
    begin
      Result[mCount] := mFileName;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

class function TImpactAnalysis.Analyze(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AStart: THierarchyItem; const ASources: TImpactSources; const AOptions: TImpactOptions;
  const ACancellation: IJsonRpcCancellationToken): TImpactResult;
var
  mRun: TImpactRun;
begin
  mRun := TImpactRun.Create(AResolver, AIndex, ASources, AOptions, ACancellation, nil);
  try
    Result := mRun.Run(AStart);
  finally
    mRun.Free;
  end;
end;

class function TImpactAnalysis.AnalyzeEach(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AStarts: TArray<THierarchyItem>; const ASources: TImpactSources; const AOptions: TImpactOptions;
  const ACancellation: IJsonRpcCancellationToken): TArray<TImpactResult>;
var
  mShared: TImpactFiles;
  mRun: TImpactRun;
  mIndex: Integer;
  mOptions: TImpactOptions;
  mClock: TStopwatch;
  mLeft: Int64;
begin
  SetLength(Result, Length(AStarts));
  mOptions := AOptions;
  mClock := TStopwatch.StartNew;
  mShared := TImpactFiles.Create(ASources.ReadText);
  try
    for mIndex := 0 to High(AStarts) do
    begin
      if ACancellation <> nil then
      begin
        ACancellation.ThrowIfCancellationRequested;
      end;
      if AOptions.TimeoutMs > 0 then
      begin
        // Mindestens 1 ms: 0 hieße ohne Zeitlimit.
        mLeft := (AOptions.TimeoutMs - mClock.ElapsedMilliseconds) div (Length(AStarts) - mIndex);
        if mLeft < 1 then
        begin
          mLeft := 1;
        end;
        mOptions.TimeoutMs := Integer(mLeft);
      end;
      mRun := TImpactRun.Create(AResolver, AIndex, ASources, mOptions, ACancellation, mShared);
      try
        Result[mIndex] := mRun.Run(AStarts[mIndex]);
      finally
        mRun.Free;
      end;
    end;
  finally
    mShared.Free;
  end;
end;

class function TImpactAnalysis.EdgeName(AEdge: TImpactEdge): string;
const
  cNames: array[TImpactEdge] of string = ('call', 'reference', 'override', 'baseMethod', 'interfaceMethod',
    'implementation');
begin
  Result := cNames[AEdge];
end;

class function TImpactAnalysis.LimitName(ALimit: TImpactLimit): string;
const
  cNames: array[TImpactLimit] of string = ('depth', 'count', 'time');
begin
  Result := cNames[ALimit];
end;

function FormsToJson(const AForms: TArray<TImpactFormBinding>): TJSONArray;
var
  mBinding: TImpactFormBinding;
  mEntry: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mBinding in AForms do
  begin
    mEntry := TJSONObject.Create;
    mEntry.AddPair('uri', TDocumentUris.FromPath(mBinding.FileName));
    mEntry.AddPair('range', TLspPositions.RangeToJson(mBinding.Range));
    mEntry.AddPair('text', mBinding.Text);
    Result.AddElement(mEntry);
  end;
end;

function RangesToJson(const ARanges: TArray<TTextRange>): TJSONArray;
var
  mRange: TTextRange;
begin
  Result := TJSONArray.Create;
  for mRange in ARanges do
  begin
    Result.AddElement(TLspPositions.RangeToJson(mRange));
  end;
end;

/// <summary>Eintrag einer Stelle in "places"; ATests: die Tests der Analyse für den Testnamen.</summary>
function PlaceToJson(const APlace: TImpactPlace; const ATests: TArray<TImpactTest>): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('level', TJSONNumber.Create(APlace.Level));
  Result.AddPair('edge', TImpactAnalysis.EdgeName(APlace.Edge));
  Result.AddPair('cause', TJSONNumber.Create(APlace.Cause));
  Result.AddPair('item', TLspHierarchies.ItemToJson(APlace.Item));
  Result.AddPair('ranges', RangesToJson(APlace.Ranges));
  Result.AddPair('atlasConfidence', APlace.Confidence.ToJson);
  Result.AddPair('forms', FormsToJson(APlace.Forms));
  if APlace.Terminal then
  begin
    Result.AddPair('terminal', TJSONBool.Create(True));
  end;
  if APlace.Test >= 0 then
  begin
    Result.AddPair('test', ATests[APlace.Test].Name);
  end;
end;

function TestToJson(const ATest: TImpactTest): TJSONObject;
var
  mNames: TJSONArray;
  mName: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ATest.Name);
  mNames := TJSONArray.Create;
  Result.AddPair('run', mNames);
  for mName in ATest.RunNames do
  begin
    mNames.Add(mName);
  end;
  Result.AddPair('uri', TDocumentUris.FromPath(ATest.FileName));
  Result.AddPair('line', TJSONNumber.Create(ATest.Line));
  Result.AddPair('level', TJSONNumber.Create(ATest.Level));
end;

function LimitsToJson(ALimits: TImpactLimits): TJSONObject;
var
  mLimit: TImpactLimit;
begin
  Result := TJSONObject.Create;
  for mLimit := Low(TImpactLimit) to High(TImpactLimit) do
  begin
    Result.AddPair(TImpactAnalysis.LimitName(mLimit), TJSONBool.Create(mLimit in ALimits));
  end;
end;

class function TImpactAnalysis.ToJson(const AResult: TImpactResult): TJSONObject;
var
  mPlaces, mTests: TJSONArray;
  mPlace: TImpactPlace;
  mTest: TImpactTest;
begin
  Result := TJSONObject.Create;
  Result.AddPair('symbol', TLspHierarchies.ItemToJson(AResult.Symbol));
  Result.AddPair('symbolForms', FormsToJson(AResult.SymbolForms));
  Result.AddPair('depth', TJSONNumber.Create(AResult.Depth));
  mPlaces := TJSONArray.Create;
  Result.AddPair('places', mPlaces);
  for mPlace in AResult.Places do
  begin
    mPlaces.AddElement(PlaceToJson(mPlace, AResult.Tests));
  end;
  mTests := TJSONArray.Create;
  Result.AddPair('tests', mTests);
  for mTest in AResult.Tests do
  begin
    mTests.AddElement(TestToJson(mTest));
  end;
  Result.AddPair('limits', LimitsToJson(AResult.Limits));
  Result.AddPair('unexpanded', TJSONNumber.Create(AResult.Unexpanded));
  Result.AddPair('maxPlaces', TJSONNumber.Create(AResult.MaxPlaces));
  Result.AddPair('timeoutMs', TJSONNumber.Create(AResult.TimeoutMs));
end;

function TImpactAnalysis.OptionsFrom(AParams: TJSONObject; const AUri: string): TImpactOptions;
var
  mDepth: Integer;
begin
  if Assigned(FOptionsFor) then
  begin
    Result := FOptionsFor(AUri);
  end
  else
  begin
    Result := TImpactOptions.Default;
  end;
  if AParams.TryGetValue<Integer>('depth', mDepth) then
  begin
    Result.Depth := mDepth;
  end;
end;

/// <summary>Baum der Datei AUri: aus dem Dokumentspeicher AStore (AShared) oder frisch gelesen (AOwnTree, der
/// Aufrufer gibt ihn frei); nil, wenn sie sich nicht lesen lässt.</summary>
function TreeFor(const AStore: IDocumentStore; const AReadText: TReferenceReadText; const AUri: string;
  const ACancellation: IPascalCancellation; out AShared: ISharedSyntaxTree; out AOwnTree: TSyntaxTree): TSyntaxTree;
var
  mDocument: ITextDocument;
  mText: string;
begin
  AShared := nil;
  AOwnTree := nil;
  Result := nil;
  if AStore.TryGet(AUri, mDocument) then
  begin
    AShared := TSyntaxTreeCache.Get(mDocument, ACancellation);
    Result := AShared.Tree;
  end
  else if Assigned(AReadText) and AReadText(TDocumentUris.ToPath(AUri), mText) then
  begin
    AOwnTree := TSyntaxTreeCache.Parse(mText, ACancellation);
    Result := AOwnTree;
  end;
end;

function TImpactAnalysis.HandleImpact(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mPositionValue: TJSONValue;
  mShared: ISharedSyntaxTree;
  mTree, mOwnTree: TSyntaxTree;
  mResolver: TNameResolver;
  mStart: THierarchyItem;
  mFound: Boolean;
  mOptions: TImpactOptions;
  mFiles: TArray<string>;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TImpactText.FieldsTextDocumentUriAndPosition].Text + cMethod);
  end;
  mOptions := OptionsFrom(TJSONObject(AParams), mUri);
  mCancellation := TRequestCancellation.Create(ACancellation);
  mTree := TreeFor(FStore, FReadText, mUri, mCancellation, mShared, mOwnTree);
  if mTree = nil then
  begin
    Exit(TJSONNull.Create);
  end;
  mFiles := nil;
  if Assigned(FFiles) then
  begin
    mFiles := FFiles();
  end;
  mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    mResolver.Namespaces := Namespaces;
    try
      mFound := TLspHierarchies.SymbolItemAt(mResolver, mTree, TDocumentUris.ToPath(mUri),
        TLspPositions.ReadPosition(mPositionValue), mStart);
    finally
      mOwnTree.Free;
    end;
    if not mFound then
    begin
      Exit(TJSONNull.Create);
    end;
    Result := ToJson(Analyze(mResolver, FIndex, mStart, TImpactSources.Create(mFiles, FReadText), mOptions,
      ACancellation));
  finally
    mResolver.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Impact', cTexts);

end.
