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
    /// <summary>Höchstzahl der Stellen; 0 = TImpactAnalysis.MaxPlaces.</summary>
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
    Method = 'atlas/impact';
    MinDepth = 1;
    MaxDepth = 5;
    DefaultDepth = 2;
    MaxPlaces = 1000;
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
  MaxCachedTrees = 64;
  // Nachfahren eines Typs, die nach Overrides durchsucht werden.
  MaxDescendants = 500;
  // Vorfahren bis zur überschriebenen Basismethode.
  MaxAncestors = 32;

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
  Bracket: Integer;
begin
  Bracket := Pos('<', AName);
  if Bracket > 0 then
  begin
    Result := Copy(AName, 1, Bracket - 1);
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
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType];
  MethodKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_];

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
  Tested: string;
begin
  Result := (AUnitName <> '') and ((IndexText(AUnitName, Units) >= 0) or
    TTestUnits.TestedUnitName(AUnitName, Pattern, Tested));
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
  Result.Depth := TImpactAnalysis.DefaultDepth;
  Result.MaxPlaces := TImpactAnalysis.MaxPlaces;
  Result.TimeoutMs := 0;
  Result.References := TReferenceSettings.Default;
  Result.Tests.Pattern := TTestUnits.DefaultPattern;
  Result.Tests.Units := nil;
end;

{ TImpactResult }

function TImpactResult.LevelCount(ALevel: Integer): Integer;
var
  Place: TImpactPlace;
begin
  Result := 0;
  for Place in Places do
  begin
    if Place.Level = ALevel then
    begin
      Inc(Result);
    end;
  end;
end;

function TImpactResult.RunNames: TArray<string>;
var
  Test: TImpactTest;
  Name: string;
  Seen: TDictionary<string, Boolean>;
begin
  Result := nil;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Test in Tests do
    begin
      for Name in Test.RunNames do
      begin
        if not Seen.ContainsKey(UpperCase(Name)) then
        begin
          Seen.Add(UpperCase(Name), True);
          Result := Result + [Name];
        end;
      end;
    end;
  finally
    Seen.Free;
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
  if (FMaxPlaces <= 0) or (FMaxPlaces > TImpactAnalysis.MaxPlaces) then
  begin
    FMaxPlaces := TImpactAnalysis.MaxPlaces;
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
  Text: string;
begin
  if FCache.Trees.TryGetValue(UpperCase(AFileName), Result) then
  begin
    Exit;
  end;
  Result := nil;
  if not ReadText(AFileName, Text) then
  begin
    Exit;
  end;
  // Große Gruppen: nicht alle Bäume zugleich halten.
  if FCache.Trees.Count >= MaxCachedTrees then
  begin
    FCache.Trees.Clear;
    FCache.Units.Clear;
  end;
  Result := TSyntaxTreeCache.Parse(Text);
  FCache.Trees.Add(UpperCase(AFileName), Result);
end;

function TImpactRun.ExtractedUnit(const AFileName: string; out AUnit: TUnitIndex): Boolean;
var
  Tree: TSyntaxTree;
begin
  if FCache.Units.TryGetValue(UpperCase(AFileName), AUnit) then
  begin
    Exit(True);
  end;
  Tree := TreeOf(AFileName);
  Result := Tree <> nil;
  if Result then
  begin
    AUnit := TIndexExtractor.Extract(Tree, AFileName);
    FCache.Units.AddOrSetValue(UpperCase(AFileName), AUnit);
  end;
end;

function TImpactRun.Declaration(const AItem: THierarchyItem; out ATarget: TDefinitionTarget): Boolean;
var
  Tree: TSyntaxTree;
  Targets: TArray<TDefinitionTarget>;
begin
  Result := False;
  Tree := TreeOf(AItem.FileName);
  if Tree = nil then
  begin
    Exit;
  end;
  Targets := TLspDefinition.Targets(FResolver, FIndex, Tree, AItem.FileName, AItem.SelectionRange.StartPos, True);
  Result := Length(Targets) > 0;
  if Result then
  begin
    ATarget := Targets[0];
  end;
end;

function TImpactRun.KeyOf(const AItem: THierarchyItem; ATerminal: Boolean): string;
var
  Target: TDefinitionTarget;
begin
  // Rumpf und Deklaration einer Methode sind dieselbe Stelle: Schlüssel ist die Deklaration.
  if not ATerminal and Declaration(AItem, Target) then
  begin
    Result := UpperCase(Target.FileName) + '|' + IntToStr(Target.SelectionRange.StartPos.Line) + ':' +
      IntToStr(Target.SelectionRange.StartPos.Character);
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
  Target: TDefinitionTarget;
  Index: Integer;
begin
  Result := False;
  if not Declaration(AItem, Target) then
  begin
    Exit;
  end;
  if not (FIndex.FindFile(Target.FileName, AUnit) or ExtractedUnit(Target.FileName, AUnit)) then
  begin
    Exit;
  end;
  for Index in AUnit.SymbolsNamed(AItem.Name) do
  begin
    if (AUnit.Symbols[Index].SelectionRange.StartPos = Target.SelectionRange.StartPos) and
      SameText(AUnit.SymbolFile(AUnit.Symbols[Index]), Target.FileName) then
    begin
      ASymbol := AUnit.Symbols[Index];
      Exit(True);
    end;
  end;
end;

function TImpactRun.UnitNameOf(const AFileName: string): string;
var
  Indexed: TUnitIndex;
begin
  if FIndex.FindFile(AFileName, Indexed) or ExtractedUnit(AFileName, Indexed) then
  begin
    Result := Indexed.UnitName;
  end
  else
  begin
    Result := '';
  end;
end;

function TImpactRun.TestOf(const AItem: THierarchyItem; ALevel: Integer): Integer;
var
  Text, UnitName: string;
  Indexed: TUnitIndex;
  Source: TDUnitXUnit;
  FixtureIndex, TestIndex: Integer;
  Test: TImpactTest;
begin
  Result := -1;
  if not TLspHierarchies.IsRoutine(AItem) or (AItem.Container = '') then
  begin
    Exit;
  end;
  if FIndex.FindFile(AItem.FileName, Indexed) then
  begin
    UnitName := Indexed.UnitName;
  end
  else
  begin
    UnitName := '';
  end;
  if not FCache.TestUnits.TryGetValue(UpperCase(AItem.FileName), Source) then
  begin
    Source := Default(TDUnitXUnit);
    // Nur Testunits parsen: Attribute stehen nicht im Index.
    if ((UnitName = '') or FOptions.Tests.Contains(UnitName)) and ReadText(AItem.FileName, Text) then
    begin
      Source := TDUnitXSource.Scan(TTextLines.SplitLines(Text));
      if not FOptions.Tests.Contains(Source.UnitName) then
      begin
        Source := Default(TDUnitXUnit);
      end;
    end;
    FCache.TestUnits.Add(UpperCase(AItem.FileName), Source);
  end;
  if not Source.Find(AItem.Container, AItem.Name, FixtureIndex, TestIndex) or (TestIndex < 0) then
  begin
    Exit;
  end;
  Test.Name := TDUnitXCommandLine.TestName(Source.UnitName, Source.Fixtures[FixtureIndex].Name,
    Source.Fixtures[FixtureIndex].Tests[TestIndex].Method);
  Test.RunNames := TDUnitXCommandLine.RunNames(Source, FixtureIndex, TestIndex, -1);
  if Test.RunNames = nil then
  begin
    Test.RunNames := [Test.Name];
  end;
  Test.FileName := AItem.FileName;
  Test.Line := Source.LineOf(Source.Fixtures[FixtureIndex].Name, Source.Fixtures[FixtureIndex].Tests[TestIndex].Method);
  Test.Level := ALevel;
  Result := FTests.Add(Test);
end;

function TImpactRun.Add(const AItem: THierarchyItem; const AStep: TImpactStep; AEdge: TImpactEdge;
  const ARanges: TArray<TTextRange>; const AConfidence: TReferenceConfidence; ATerminal: Boolean): Boolean;
var
  Key: string;
  Slot: Integer;
  Place: TImpactPlace;
begin
  Result := False;
  Key := KeyOf(AItem, ATerminal);
  if FKeys.TryGetValue(Key, Slot) then
  begin
    // Gleiche Stelle, gleiche Ursache: weitere Verwendungen. Sichere Verwendung schlägt erschlossene.
    if (Slot >= 0) and (FPlaces[Slot].Level = AStep.Level) and (FPlaces[Slot].Cause = AStep.Cause) then
    begin
      Place := FPlaces[Slot];
      Place.Ranges := Place.Ranges + ARanges;
      if AConfidence.IsSure then
      begin
        Place.Confidence := AConfidence;
      end;
      FPlaces[Slot] := Place;
    end;
    Exit;
  end;
  if FPlaces.Count >= FMaxPlaces then
  begin
    FFull := True;
    Exit;
  end;
  Place := Default(TImpactPlace);
  Place.Item := AItem;
  // Aufrufer aus dem Syntaxbaum (CallerAt) kennen ihre Unit nicht.
  if Place.Item.UnitName = '' then
  begin
    Place.Item.UnitName := UnitNameOf(AItem.FileName);
  end;
  Place.Level := AStep.Level;
  Place.Edge := AEdge;
  Place.Cause := AStep.Cause;
  Place.Ranges := ARanges;
  Place.Confidence := AConfidence;
  Place.Terminal := ATerminal;
  Place.Forms := FCache.Forms.Bindings(AItem.Name, AItem.FileName);
  Place.Test := TestOf(AItem, AStep.Level);
  Slot := FPlaces.Add(Place);
  FKeys.Add(Key, Slot);
  if not ATerminal then
  begin
    AStep.Next.Add(Slot);
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
  Extracted: TUnitIndex;
  Symbol, Best: TIndexSymbol;
  Found: Boolean;
begin
  Result := False;
  ATerminal := False;
  if not ExtractedUnit(AFileName, Extracted) then
  begin
    Exit;
  end;
  Found := False;
  for Symbol in Extracted.Symbols do
  begin
    if RangeContains(Symbol.Range, APosition) and (not Found or (RangeSize(Symbol.Range) < RangeSize(Best.Range))) then
    begin
      Best := Symbol;
      Found := True;
    end;
  end;
  if Found then
  begin
    AItem := TLspHierarchies.ItemOf(Extracted.UnitName, AFileName, Best);
    Exit(True);
  end;
  // Unit-Ebene (initialization, finalization, Rumpf des Programms): die Unit selbst.
  AItem := Default(THierarchyItem);
  AItem.Name := Extracted.UnitName;
  if AItem.Name = '' then
  begin
    AItem.Name := ChangeFileExt(ExtractFileName(AFileName), '');
  end;
  AItem.SymbolKind := TIndexSymbolKind.Variable;
  AItem.UnitName := Extracted.UnitName;
  AItem.FileName := AFileName;
  AItem.Range := TTextRange.Create(APosition, APosition);
  AItem.SelectionRange := AItem.Range;
  ATerminal := True;
  Result := True;
end;

function TImpactRun.MemberOf(const AFileName, ATypeName, AName: string; out AItem: THierarchyItem): Boolean;
var
  Indexed: TUnitIndex;
  Index: Integer;
begin
  Result := False;
  if not FIndex.FindFile(AFileName, Indexed) then
  begin
    Exit;
  end;
  for Index in Indexed.SymbolsNamed(AName) do
  begin
    if (Indexed.Symbols[Index].Kind in MethodKinds) and SameText(Indexed.Symbols[Index].Container, ATypeName) then
    begin
      AItem := TLspHierarchies.ItemOf(Indexed.UnitName, Indexed.SymbolFile(Indexed.Symbols[Index]),
        Indexed.Symbols[Index]);
      Exit(True);
    end;
  end;
end;

function TImpactRun.TypeSymbol(const AFromUnit: TUnitIndex; const ATypeName: string; out AUnit: TUnitIndex;
  out ASymbol: TIndexSymbol): Boolean;
var
  Resolved: TResolvedSymbol;
  Index: Integer;
begin
  Result := False;
  if not FResolver.ResolveTypeFrom(AFromUnit, WithoutGenerics(ATypeName), Resolved) or
    not (Resolved.SymbolKind in TypeKinds) or not FIndex.FindFile(Resolved.FileName, AUnit) then
  begin
    Exit;
  end;
  for Index in AUnit.SymbolsNamed(Resolved.Name) do
  begin
    if (AUnit.Symbols[Index].Kind in TypeKinds) and SameText(AUnit.Symbols[Index].Container, Resolved.Container) then
    begin
      ASymbol := AUnit.Symbols[Index];
      Exit(True);
    end;
  end;
end;

function TImpactRun.PlaceAt(const AItem: THierarchyItem; const ALocation: TReferenceLocation;
  out APlace: THierarchyItem; out ATerminal: Boolean): Boolean;
var
  Tree: TSyntaxTree;
begin
  ATerminal := False;
  // Formularbindungen gehören zur Stelle selbst (TImpactFormCache), nicht zur nächsten Ebene.
  Tree := nil;
  if not TImpactFormCache.IsFormFile(ALocation.FileName) then
  begin
    Tree := TreeOf(ALocation.FileName);
  end;
  if Tree = nil then
  begin
    Exit(False);
  end;
  if TLspHierarchies.CallerAt(Tree, ALocation.FileName, ALocation.Range.StartPos, APlace) then
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
  Tree: TSyntaxTree;
  Locations: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
  Place: THierarchyItem;
  Edge: TImpactEdge;
  Terminal: Boolean;
begin
  Tree := TreeOf(AItem.FileName);
  if Tree = nil then
  begin
    Exit;
  end;
  Locations := TLspReferences.Find(FResolver, FIndex, Tree, TReferenceSearch.Create(AItem.FileName,
    AItem.SelectionRange.StartPos, False, TImpactAnalysis.CandidateFiles(FIndex, FSources.Files, AItem.Name),
    FSources.ReadText), FOptions.References, FToken);
  Edge := TImpactEdge.Reference;
  if TLspHierarchies.IsRoutine(AItem) then
  begin
    Edge := TImpactEdge.Call;
  end;
  for Location in Locations do
  begin
    FToken.ThrowIfCancellationRequested;
    if PlaceAt(AItem, Location, Place, Terminal) then
    begin
      Add(Place, AStep, Edge, [Location.Range], Location.Confidence, Terminal);
    end;
  end;
end;

/// <summary>Umsetzung der Interface-Methode AOwn in einem Typ mit den Methodenzuordnungen AResolutions: die
/// gleichnamige Methode oder das Ziel von IFoo.Bar = Baz.</summary>
function ImplementationTarget(const AOwn: TIndexSymbol; const AResolutions: TArray<string>): string;
var
  Resolution: string;
  EqualsAt: Integer;
begin
  Result := AOwn.Name;
  for Resolution in AResolutions do
  begin
    EqualsAt := Pos('=', Resolution);
    if (EqualsAt > 0) and SameText(Trim(Copy(Resolution, 1, EqualsAt - 1)), AOwn.Container + '.' + AOwn.Name) then
    begin
      Result := Trim(Copy(Resolution, EqualsAt + 1, MaxInt));
    end;
  end;
end;

/// <summary>Methode des Interfaces AAncestor, die die Methode AName des Typs AOwner umsetzt: die gleichnamige
/// oder die per Methodenzuordnung IFoo.Bar = AName.</summary>
function InterfaceTarget(const AOwner: TIndexSymbol; const AAncestor, AName: string): string;
var
  Resolution, Prefix, Source: string;
  EqualsAt: Integer;
begin
  Result := AName;
  Prefix := WithoutGenerics(AAncestor) + '.';
  for Resolution in AOwner.Resolutions do
  begin
    EqualsAt := Pos('=', Resolution);
    Source := Trim(Copy(Resolution, 1, EqualsAt - 1));
    if (EqualsAt > 0) and SameText(Trim(Copy(Resolution, EqualsAt + 1, MaxInt)), AName) and
      StartsText(Prefix, Source) then
    begin
      Result := Copy(Source, Length(Prefix) + 1, MaxInt);
    end;
  end;
end;

/// <summary>Typ, zu dem die Methode AOwn in AUnit gehört.</summary>
function OwnerOf(const AUnit: TUnitIndex; const AOwn: TIndexSymbol; out AOwner: TIndexSymbol): Boolean;
var
  Index: Integer;
begin
  for Index in AUnit.SymbolsNamed(AOwn.Container) do
  begin
    if AUnit.Symbols[Index].Kind in TypeKinds then
    begin
      AOwner := AUnit.Symbols[Index];
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TImpactRun.AddDescendant(const AOwn: TIndexSymbol; AInterface: Boolean; const ALocation: TSymbolLocation;
  const AStep: TImpactStep);
var
  TypeUnit: TUnitIndex;
  Member: THierarchyItem;
  Index: Integer;
begin
  if AInterface then
  begin
    if (ALocation.Symbol.Kind <> TIndexSymbolKind.InterfaceType) and MemberOf(ALocation.FileName,
      ALocation.Symbol.Name, ImplementationTarget(AOwn, ALocation.Symbol.Resolutions), Member) then
    begin
      AddSure(Member, AStep, TImpactEdge.Implementation_);
    end;
    Exit;
  end;
  if not FIndex.FindFile(ALocation.FileName, TypeUnit) then
  begin
    Exit;
  end;
  for Index in TypeUnit.SymbolsNamed(AOwn.Name) do
  begin
    if SameText(TypeUnit.Symbols[Index].Container, ALocation.Symbol.Name) and
      TypeUnit.Symbols[Index].HasDirective('override') then
    begin
      AddSure(TLspHierarchies.ItemOf(TypeUnit.UnitName, TypeUnit.SymbolFile(TypeUnit.Symbols[Index]),
        TypeUnit.Symbols[Index]), AStep, TImpactEdge.Override_);
      Exit;
    end;
  end;
end;

procedure TImpactRun.AddDescendants(const AOwn: TIndexSymbol; AInterface: Boolean; const AStep: TImpactStep);
var
  Pending: TQueue<string>;
  Seen: TDictionary<string, Boolean>;
  Location: TSymbolLocation;
begin
  Pending := TQueue<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    Pending.Enqueue(AOwn.Container);
    Seen.Add(UpperCase(AOwn.Container), True);
    while (Pending.Count > 0) and (Seen.Count < MaxDescendants) do
    begin
      FToken.ThrowIfCancellationRequested;
      for Location in FIndex.Descendants(Pending.Dequeue) do
      begin
        if (Location.Symbol.Kind in TypeKinds) and not Seen.ContainsKey(UpperCase(Location.Symbol.Name)) then
        begin
          Seen.Add(UpperCase(Location.Symbol.Name), True);
          Pending.Enqueue(Location.Symbol.Name);
          AddDescendant(AOwn, AInterface, Location, AStep);
        end;
      end;
    end;
  finally
    Seen.Free;
    Pending.Free;
  end;
end;

procedure TImpactRun.AddBaseMethod(const AOwnUnit: TUnitIndex; const AOwn, AOwner: TIndexSymbol;
  const AStep: TImpactStep);
var
  TypeUnit, BaseUnit: TUnitIndex;
  Found, Base: TIndexSymbol;
  Member: THierarchyItem;
  Steps: Integer;
begin
  TypeUnit := AOwnUnit;
  Found := AOwner;
  for Steps := 1 to MaxAncestors do
  begin
    if (Length(Found.Ancestors) = 0) or not TypeSymbol(TypeUnit, Found.Ancestors[0], BaseUnit, Base) or
      (Base.Kind = TIndexSymbolKind.InterfaceType) then
    begin
      Exit;
    end;
    if MemberOf(BaseUnit.FileName, Base.Name, AOwn.Name, Member) then
    begin
      AddSure(Member, AStep, TImpactEdge.BaseMethod);
      Exit;
    end;
    TypeUnit := BaseUnit;
    Found := Base;
  end;
end;

procedure TImpactRun.AddInterfaceMethods(const AOwnUnit: TUnitIndex; const AOwn, AOwner: TIndexSymbol;
  const AStep: TImpactStep);
var
  BaseUnit: TUnitIndex;
  Base: TIndexSymbol;
  Member: THierarchyItem;
  Ancestor: string;
begin
  for Ancestor in AOwner.Ancestors do
  begin
    if TypeSymbol(AOwnUnit, Ancestor, BaseUnit, Base) and (Base.Kind = TIndexSymbolKind.InterfaceType) and
      MemberOf(BaseUnit.FileName, Base.Name, InterfaceTarget(AOwner, Ancestor, AOwn.Name), Member) then
    begin
      AddSure(Member, AStep, TImpactEdge.InterfaceMethod);
    end;
  end;
end;

procedure TImpactRun.AddStructural(const AItem: THierarchyItem; const AStep: TImpactStep);
var
  OwnUnit: TUnitIndex;
  Own, Owner: TIndexSymbol;
  OwnerFound, IsInterface: Boolean;
begin
  if not (AItem.SymbolKind in MethodKinds) or (AItem.Container = '') or
    not DeclarationSymbol(AItem, OwnUnit, Own) then
  begin
    Exit;
  end;
  OwnerFound := OwnerOf(OwnUnit, Own, Owner);
  IsInterface := OwnerFound and (Owner.Kind = TIndexSymbolKind.InterfaceType);
  if Own.IsVirtual or IsInterface then
  begin
    AddDescendants(Own, IsInterface, AStep);
  end;
  if not OwnerFound or IsInterface then
  begin
    Exit;
  end;
  if Own.HasDirective('override') then
  begin
    AddBaseMethod(OwnUnit, Own, Owner, AStep);
  end;
  AddInterfaceMethods(OwnUnit, Own, Owner, AStep);
end;

procedure TImpactRun.Expand(const AItem: THierarchyItem; const AStep: TImpactStep);
begin
  FToken.ThrowIfCancellationRequested;
  AddReferences(AItem, AStep);
  AddStructural(AItem, AStep);
end;

procedure TImpactRun.ExpandLevel(const AStart: THierarchyItem; AFrontier, ANext: TList<Integer>; ALevel: Integer);
var
  Step: TImpactStep;
  Slot: Integer;
begin
  Step.Level := ALevel;
  Step.Next := ANext;
  for Slot in AFrontier do
  begin
    if FFull then
    begin
      Exit;
    end;
    Step.Cause := Slot;
    if Slot < 0 then
    begin
      Expand(AStart, Step);
    end
    else
    begin
      Expand(FPlaces[Slot].Item, Step);
    end;
  end;
end;

function TImpactRun.Run(const AStart: THierarchyItem): TImpactResult;
var
  Frontier, Next: TList<Integer>;
  Level: Integer;
begin
  Result := Default(TImpactResult);
  Result.Symbol := AStart;
  Result.Depth := FOptions.Depth;
  Result.MaxPlaces := FMaxPlaces;
  Result.TimeoutMs := FOptions.TimeoutMs;
  Frontier := TList<Integer>.Create;
  Next := TList<Integer>.Create;
  try
    try
      Result.SymbolForms := FCache.Forms.Bindings(AStart.Name, AStart.FileName);
      FKeys.Add(KeyOf(AStart, False), -1);
      // Das Symbol selbst kann ein Test sein (Ebene 0).
      TestOf(AStart, 0);
      Frontier.Add(-1);
      for Level := 1 to FOptions.Depth do
      begin
        Next.Clear;
        ExpandLevel(AStart, Frontier, Next, Level);
        Frontier.Clear;
        Frontier.AddRange(Next.ToArray);
        if (Frontier.Count = 0) or FFull then
        begin
          Break;
        end;
      end;
      // Stellen der letzten Ebene, deren Verwendungen nicht mehr gesucht wurden.
      if not FFull and (Frontier.Count > 0) then
      begin
        Include(Result.Limits, TImpactLimit.Depth);
        Result.Unexpanded := Frontier.Count;
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
    Next.Free;
    Frontier.Free;
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
  ADispatcher.RegisterConcurrentRequest(Method, HandleImpact);
end;

class function TImpactAnalysis.ClampDepth(ADepth: Integer): Integer;
begin
  Result := ADepth;
  if Result < MinDepth then
  begin
    Result := MinDepth;
  end
  else if Result > MaxDepth then
  begin
    Result := MaxDepth;
  end;
end;

class function TImpactAnalysis.CandidateFiles(const AIndex: ISymbolIndex; const AFiles: TArray<string>;
  const AName: string): TArray<string>;
var
  FileName, Alternative: string;
  Count: Integer;
begin
  // Attribute (#119): [Foo] verwendet FooAttribute; wie in der Referenzsuche beide Schreibweisen.
  if EndsText('Attribute', AName) and (Length(AName) > Length('Attribute')) then
  begin
    Alternative := Copy(AName, 1, Length(AName) - Length('Attribute'));
  end
  else
  begin
    Alternative := AName + 'Attribute';
  end;
  SetLength(Result, Length(AFiles));
  Count := 0;
  for FileName in AFiles do
  begin
    if (TIndexUsages.Lookup(AIndex, FileName, AName) <> TIndexUsageAnswer.Absent) or
      (TIndexUsages.Lookup(AIndex, FileName, Alternative) <> TIndexUsageAnswer.Absent) then
    begin
      Result[Count] := FileName;
      Inc(Count);
    end;
  end;
  SetLength(Result, Count);
end;

class function TImpactAnalysis.Analyze(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AStart: THierarchyItem; const ASources: TImpactSources; const AOptions: TImpactOptions;
  const ACancellation: IJsonRpcCancellationToken): TImpactResult;
var
  Run: TImpactRun;
begin
  Run := TImpactRun.Create(AResolver, AIndex, ASources, AOptions, ACancellation, nil);
  try
    Result := Run.Run(AStart);
  finally
    Run.Free;
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
  Names: array[TImpactEdge] of string = ('call', 'reference', 'override', 'baseMethod', 'interfaceMethod',
    'implementation');
begin
  Result := Names[AEdge];
end;

class function TImpactAnalysis.LimitName(ALimit: TImpactLimit): string;
const
  Names: array[TImpactLimit] of string = ('depth', 'count', 'time');
begin
  Result := Names[ALimit];
end;

function FormsToJson(const AForms: TArray<TImpactFormBinding>): TJSONArray;
var
  Binding: TImpactFormBinding;
  Entry: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Binding in AForms do
  begin
    Entry := TJSONObject.Create;
    Entry.AddPair('uri', TDocumentUris.FromPath(Binding.FileName));
    Entry.AddPair('range', TLspPositions.RangeToJson(Binding.Range));
    Entry.AddPair('text', Binding.Text);
    Result.AddElement(Entry);
  end;
end;

function RangesToJson(const ARanges: TArray<TTextRange>): TJSONArray;
var
  Range: TTextRange;
begin
  Result := TJSONArray.Create;
  for Range in ARanges do
  begin
    Result.AddElement(TLspPositions.RangeToJson(Range));
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
  Names: TJSONArray;
  Name: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ATest.Name);
  Names := TJSONArray.Create;
  Result.AddPair('run', Names);
  for Name in ATest.RunNames do
  begin
    Names.Add(Name);
  end;
  Result.AddPair('uri', TDocumentUris.FromPath(ATest.FileName));
  Result.AddPair('line', TJSONNumber.Create(ATest.Line));
  Result.AddPair('level', TJSONNumber.Create(ATest.Level));
end;

function LimitsToJson(ALimits: TImpactLimits): TJSONObject;
var
  Limit: TImpactLimit;
begin
  Result := TJSONObject.Create;
  for Limit := Low(TImpactLimit) to High(TImpactLimit) do
  begin
    Result.AddPair(TImpactAnalysis.LimitName(Limit), TJSONBool.Create(Limit in ALimits));
  end;
end;

class function TImpactAnalysis.ToJson(const AResult: TImpactResult): TJSONObject;
var
  Places, Tests: TJSONArray;
  Place: TImpactPlace;
  Test: TImpactTest;
begin
  Result := TJSONObject.Create;
  Result.AddPair('symbol', TLspHierarchies.ItemToJson(AResult.Symbol));
  Result.AddPair('symbolForms', FormsToJson(AResult.SymbolForms));
  Result.AddPair('depth', TJSONNumber.Create(AResult.Depth));
  Places := TJSONArray.Create;
  Result.AddPair('places', Places);
  for Place in AResult.Places do
  begin
    Places.AddElement(PlaceToJson(Place, AResult.Tests));
  end;
  Tests := TJSONArray.Create;
  Result.AddPair('tests', Tests);
  for Test in AResult.Tests do
  begin
    Tests.AddElement(TestToJson(Test));
  end;
  Result.AddPair('limits', LimitsToJson(AResult.Limits));
  Result.AddPair('unexpanded', TJSONNumber.Create(AResult.Unexpanded));
  Result.AddPair('maxPlaces', TJSONNumber.Create(AResult.MaxPlaces));
  Result.AddPair('timeoutMs', TJSONNumber.Create(AResult.TimeoutMs));
end;

function TImpactAnalysis.OptionsFrom(AParams: TJSONObject; const AUri: string): TImpactOptions;
var
  Depth: Integer;
begin
  if Assigned(FOptionsFor) then
  begin
    Result := FOptionsFor(AUri);
  end
  else
  begin
    Result := TImpactOptions.Default;
  end;
  if AParams.TryGetValue<Integer>('depth', Depth) then
  begin
    Result.Depth := Depth;
  end;
end;

/// <summary>Baum der Datei AUri: aus dem Dokumentspeicher AStore (AShared) oder frisch gelesen (AOwnTree, der
/// Aufrufer gibt ihn frei); nil, wenn sie sich nicht lesen lässt.</summary>
function TreeFor(const AStore: IDocumentStore; const AReadText: TReferenceReadText; const AUri: string;
  const ACancellation: IPascalCancellation; out AShared: ISharedSyntaxTree; out AOwnTree: TSyntaxTree): TSyntaxTree;
var
  Document: ITextDocument;
  Text: string;
begin
  AShared := nil;
  AOwnTree := nil;
  Result := nil;
  if AStore.TryGet(AUri, Document) then
  begin
    AShared := TSyntaxTreeCache.Get(Document, ACancellation);
    Result := AShared.Tree;
  end
  else if Assigned(AReadText) and AReadText(TDocumentUris.ToPath(AUri), Text) then
  begin
    AOwnTree := TSyntaxTreeCache.Parse(Text, ACancellation);
    Result := AOwnTree;
  end;
end;

function TImpactAnalysis.HandleImpact(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Shared: ISharedSyntaxTree;
  Tree, OwnTree: TSyntaxTree;
  Resolver: TNameResolver;
  Start: THierarchyItem;
  Found: Boolean;
  Options: TImpactOptions;
  Files: TArray<string>;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TImpactText.FieldsTextDocumentUriAndPosition].Text + Method);
  end;
  Options := OptionsFrom(TJSONObject(AParams), Uri);
  Cancellation := TRequestCancellation.Create(ACancellation);
  Tree := TreeFor(FStore, FReadText, Uri, Cancellation, Shared, OwnTree);
  if Tree = nil then
  begin
    Exit(TJSONNull.Create);
  end;
  Files := nil;
  if Assigned(FFiles) then
  begin
    Files := FFiles();
  end;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := Namespaces;
    try
      Found := TLspHierarchies.SymbolItemAt(Resolver, Tree, TDocumentUris.ToPath(Uri),
        TLspPositions.ReadPosition(PositionValue), Start);
    finally
      OwnTree.Free;
    end;
    if not Found then
    begin
      Exit(TJSONNull.Create);
    end;
    Result := ToJson(Analyze(Resolver, FIndex, Start, TImpactSources.Create(Files, FReadText), Options,
      ACancellation));
  finally
    Resolver.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Impact', cTexts);

end.
