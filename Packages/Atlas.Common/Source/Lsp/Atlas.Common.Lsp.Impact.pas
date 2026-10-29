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
  Atlas.Common.Lsp.Hierarchies;

type
{$SCOPEDENUMS ON}
  /// <summary>Wie eine Stelle von ihrer Ursache betroffen ist.</summary>
  TImpactEdge = (Call, Reference, Override_, BaseMethod, InterfaceMethod, Implementation_);
  TImpactLimit = (Depth, Count, Time);
{$SCOPEDENUMS OFF}
  TImpactLimits = set of TImpactLimit;

  /// <summary>Bindung einer Stelle in einem Formular: Ereignis-Handler oder Komponentenname.</summary>
  TImpactFormBinding = record
    FileName: string;
    Range: TTextRange;
    /// <summary>Zeile der Formulardatei ohne Einrückung, z. B. "OnClick = Button1Click".</summary>
    Text: string;
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
    function HandleImpact(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Auswirkungen des Symbols AStart (aus TLspHierarchies.SymbolItemAt). AFiles: Projektdateien.
    /// </summary>
    class function Analyze(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AStart: THierarchyItem;
      const AFiles: TArray<string>; const AReadText: TReferenceReadText; const AOptions: TImpactOptions;
      const ACancellation: IJsonRpcCancellationToken): TImpactResult; static;
    /// <summary>Wie Analyze für jedes Symbol aus AStarts (#1353), in derselben Reihenfolge; die Läufe teilen sich
    /// die gelesenen Dateien. AOptions.TimeoutMs gilt für alle zusammen: Jedes Symbol bekommt die verbleibende Zeit
    /// geteilt durch die Zahl der übrigen.</summary>
    class function AnalyzeEach(AResolver: TNameResolver; const AIndex: ISymbolIndex;
      const AStarts: TArray<THierarchyItem>; const AFiles: TArray<string>; const AReadText: TReferenceReadText;
      const AOptions: TImpactOptions; const ACancellation: IJsonRpcCancellationToken): TArray<TImpactResult>; static;
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
  Atlas.Common.Dfm.FormFiles,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Editing.TestUnits,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Pascal.Lexer,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX;

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
    Forms: TObjectDictionary<string, TFormModel>;
    TestUnits: TDictionary<string, TDUnitXUnit>;
    constructor Create;
    destructor Destroy; override;
  end;

  /// <summary>Zustand einer Analyse.</summary>
  TImpactRun = class
  private
    FResolver: TNameResolver;
    FIndex: ISymbolIndex;
    FFiles: TArray<string>;
    FReadText: TReferenceReadText;
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
    function FormBindings(const AItem: THierarchyItem): TArray<TImpactFormBinding>;
    function TestOf(const AItem: THierarchyItem; ALevel: Integer): Integer;
    function UnitNameOf(const AFileName: string): string;
    /// <summary>Neue Stelle; False, wenn sie schon auf einer kleineren oder derselben Ebene steht oder die
    /// Höchstzahl erreicht ist. Steht sie mit derselben Ursache schon da, kommen ARanges dazu.</summary>
    function Add(const AItem: THierarchyItem; ALevel: Integer; AEdge: TImpactEdge; ACause: Integer;
      const ARanges: TArray<TTextRange>; const AConfidence: TReferenceConfidence; ATerminal: Boolean;
      var ANext: TList<Integer>): Boolean;
    /// <summary>Innerste Deklaration um APosition; ohne eine die Unit selbst mit ATerminal.</summary>
    function EnclosingDeclaration(const AFileName: string; const APosition: TTextPosition;
      out AItem: THierarchyItem; out ATerminal: Boolean): Boolean;
    function MemberOf(const AFileName, ATypeName, AName: string; out AItem: THierarchyItem): Boolean;
    function TypeSymbol(const AFromUnit: TUnitIndex; const ATypeName: string; out AUnit: TUnitIndex;
      out ASymbol: TIndexSymbol): Boolean;
    procedure AddReferences(const AItem: THierarchyItem; ACause, ALevel: Integer; var ANext: TList<Integer>);
    procedure AddStructural(const AItem: THierarchyItem; ACause, ALevel: Integer; var ANext: TList<Integer>);
    procedure Expand(const AItem: THierarchyItem; ACause, ALevel: Integer; var ANext: TList<Integer>);
  public
    /// <summary>AShared: gelesene Dateien mehrerer Läufe (bleibt beim Aufrufer); nil = eigene.</summary>
    constructor Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AFiles: TArray<string>;
      const AReadText: TReferenceReadText; const AOptions: TImpactOptions;
      const ACancellation: IJsonRpcCancellationToken; AShared: TImpactFiles);
    destructor Destroy; override;
    function Run(const AStart: THierarchyItem): TImpactResult;
  end;

function WithoutGenerics(const AName: string): string;
var
  Bracket: Integer;
begin
  Bracket := Pos('<', AName);
  if Bracket > 0 then
    Result := Copy(AName, 1, Bracket - 1)
  else
    Result := AName;
end;

function IsFormFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dfm') or SameText(ExtractFileExt(AFileName), '.fmx');
end;

function RangeContains(const AOuter: TTextRange; const APosition: TTextPosition): Boolean;

  function Compare(const A, B: TTextPosition): Integer;
  begin
    if A.Line <> B.Line then
      Result := A.Line - B.Line
    else
      Result := A.Character - B.Character;
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
    FInner.ThrowIfCancellationRequested;
  if Expired then
    raise EImpactTimeLimit.Create('Zeitlimit der Auswirkungsanalyse erreicht');
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
    Result.Units := TUsesClauses.UsedUnits(TPascalLexer.Tokenize(AProgramText));
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
    if Place.Level = ALevel then
      Inc(Result);
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
      for Name in Test.RunNames do
        if not Seen.ContainsKey(UpperCase(Name)) then
        begin
          Seen.Add(UpperCase(Name), True);
          Result := Result + [Name];
        end;
  finally
    Seen.Free;
  end;
end;

{ TImpactFiles }

constructor TImpactFiles.Create;
begin
  inherited Create;
  Trees := TObjectDictionary<string, TSyntaxTree>.Create([doOwnsValues]);
  Units := TDictionary<string, TUnitIndex>.Create;
  Forms := TObjectDictionary<string, TFormModel>.Create([doOwnsValues]);
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

constructor TImpactRun.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AFiles: TArray<string>;
  const AReadText: TReferenceReadText; const AOptions: TImpactOptions;
  const ACancellation: IJsonRpcCancellationToken; AShared: TImpactFiles);
begin
  inherited Create;
  FResolver := AResolver;
  FIndex := AIndex;
  FFiles := AFiles;
  FReadText := AReadText;
  FOptions := AOptions;
  FOptions.Depth := TImpactAnalysis.ClampDepth(AOptions.Depth);
  FMaxPlaces := AOptions.MaxPlaces;
  if (FMaxPlaces <= 0) or (FMaxPlaces > TImpactAnalysis.MaxPlaces) then
    FMaxPlaces := TImpactAnalysis.MaxPlaces;
  FDeadline := TImpactDeadline.Create(ACancellation, AOptions.TimeoutMs);
  FToken := FDeadline;
  FPlaces := TList<TImpactPlace>.Create;
  FTests := TList<TImpactTest>.Create;
  FKeys := TDictionary<string, Integer>.Create;
  FOwnsFiles := AShared = nil;
  if FOwnsFiles then
    FCache := TImpactFiles.Create
  else
    FCache := AShared;
end;

destructor TImpactRun.Destroy;
begin
  if FOwnsFiles then
    FCache.Free;
  FKeys.Free;
  FTests.Free;
  FPlaces.Free;
  FToken := nil;
  inherited;
end;

function TImpactRun.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := Assigned(FReadText) and FReadText(AFileName, AText);
end;

function TImpactRun.TreeOf(const AFileName: string): TSyntaxTree;
var
  Text: string;
begin
  if FCache.Trees.TryGetValue(UpperCase(AFileName), Result) then
    Exit;
  Result := nil;
  if not ReadText(AFileName, Text) then
    Exit;
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
    Exit(True);
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
    Exit;
  Targets := TLspDefinition.Targets(FResolver, FIndex, Tree, AItem.FileName, AItem.SelectionRange.StartPos, True);
  Result := Length(Targets) > 0;
  if Result then
    ATarget := Targets[0];
end;

function TImpactRun.KeyOf(const AItem: THierarchyItem; ATerminal: Boolean): string;
var
  Target: TDefinitionTarget;
begin
  // Rumpf und Deklaration einer Methode sind dieselbe Stelle: Schlüssel ist die Deklaration.
  if not ATerminal and Declaration(AItem, Target) then
    Result := UpperCase(Target.FileName) + '|' + IntToStr(Target.SelectionRange.StartPos.Line) + ':' +
      IntToStr(Target.SelectionRange.StartPos.Character)
  else
    Result := UpperCase(AItem.FileName) + '|' + IntToStr(AItem.SelectionRange.StartPos.Line) + ':' +
      IntToStr(AItem.SelectionRange.StartPos.Character);
end;

function TImpactRun.DeclarationSymbol(const AItem: THierarchyItem; out AUnit: TUnitIndex;
  out ASymbol: TIndexSymbol): Boolean;
var
  Target: TDefinitionTarget;
  Index: Integer;
begin
  Result := False;
  if not Declaration(AItem, Target) then
    Exit;
  if not (FIndex.FindFile(Target.FileName, AUnit) or ExtractedUnit(Target.FileName, AUnit)) then
    Exit;
  for Index in AUnit.SymbolsNamed(AItem.Name) do
    if (AUnit.Symbols[Index].SelectionRange.StartPos = Target.SelectionRange.StartPos) and
      SameText(AUnit.SymbolFile(AUnit.Symbols[Index]), Target.FileName) then
    begin
      ASymbol := AUnit.Symbols[Index];
      Exit(True);
    end;
end;

function TImpactRun.FormBindings(const AItem: THierarchyItem): TArray<TImpactFormBinding>;
var
  Text, FormFile: string;
  Model: TFormModel;
  Range: TTextRange;
  Lines: TArray<string>;
  Binding: TImpactFormBinding;
begin
  Result := nil;
  if (AItem.Name = '') or IsFormFile(AItem.FileName) or not ReadText(AItem.FileName, Text) then
    Exit;
  for FormFile in TFormFiles.FormFiles(AItem.FileName, Text) do
  begin
    if not FCache.Forms.TryGetValue(UpperCase(FormFile), Model) then
    begin
      if not ReadText(FormFile, Text) then
        Continue;
      Model := TFormModel.Create(Text);
      FCache.Forms.Add(UpperCase(FormFile), Model);
    end;
    Lines := nil;
    for Range in Model.Occurrences(AItem.Name) do
    begin
      if Lines = nil then
      begin
        if not ReadText(FormFile, Text) then
          Text := '';
        Lines := TTextLines.SplitLines(Text);
      end;
      Binding.FileName := FormFile;
      Binding.Range := Range;
      Binding.Text := '';
      if (Range.StartPos.Line >= 0) and (Range.StartPos.Line < Length(Lines)) then
        Binding.Text := Trim(Lines[Range.StartPos.Line]);
      Result := Result + [Binding];
    end;
  end;
end;

function TImpactRun.UnitNameOf(const AFileName: string): string;
var
  Indexed: TUnitIndex;
begin
  if FIndex.FindFile(AFileName, Indexed) or ExtractedUnit(AFileName, Indexed) then
    Result := Indexed.UnitName
  else
    Result := '';
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
    Exit;
  if FIndex.FindFile(AItem.FileName, Indexed) then
    UnitName := Indexed.UnitName
  else
    UnitName := '';
  if not FCache.TestUnits.TryGetValue(UpperCase(AItem.FileName), Source) then
  begin
    Source := Default(TDUnitXUnit);
    // Nur Testunits parsen: Attribute stehen nicht im Index.
    if ((UnitName = '') or FOptions.Tests.Contains(UnitName)) and ReadText(AItem.FileName, Text) then
    begin
      Source := TDUnitXSource.Scan(TTextLines.SplitLines(Text));
      if not FOptions.Tests.Contains(Source.UnitName) then
        Source := Default(TDUnitXUnit);
    end;
    FCache.TestUnits.Add(UpperCase(AItem.FileName), Source);
  end;
  if not Source.Find(AItem.Container, AItem.Name, FixtureIndex, TestIndex) or (TestIndex < 0) then
    Exit;
  Test.Name := TDUnitXCommandLine.TestName(Source.UnitName, Source.Fixtures[FixtureIndex].Name,
    Source.Fixtures[FixtureIndex].Tests[TestIndex].Method);
  Test.RunNames := TDUnitXCommandLine.RunNames(Source, FixtureIndex, TestIndex, -1);
  if Test.RunNames = nil then
    Test.RunNames := [Test.Name];
  Test.FileName := AItem.FileName;
  Test.Line := Source.LineOf(Source.Fixtures[FixtureIndex].Name, Source.Fixtures[FixtureIndex].Tests[TestIndex].Method);
  Test.Level := ALevel;
  Result := FTests.Add(Test);
end;

function TImpactRun.Add(const AItem: THierarchyItem; ALevel: Integer; AEdge: TImpactEdge; ACause: Integer;
  const ARanges: TArray<TTextRange>; const AConfidence: TReferenceConfidence; ATerminal: Boolean;
  var ANext: TList<Integer>): Boolean;
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
    if (Slot >= 0) and (FPlaces[Slot].Level = ALevel) and (FPlaces[Slot].Cause = ACause) then
    begin
      Place := FPlaces[Slot];
      Place.Ranges := Place.Ranges + ARanges;
      if AConfidence.IsSure then
        Place.Confidence := AConfidence;
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
    Place.Item.UnitName := UnitNameOf(AItem.FileName);
  Place.Level := ALevel;
  Place.Edge := AEdge;
  Place.Cause := ACause;
  Place.Ranges := ARanges;
  Place.Confidence := AConfidence;
  Place.Terminal := ATerminal;
  Place.Forms := FormBindings(AItem);
  Place.Test := TestOf(AItem, ALevel);
  Slot := FPlaces.Add(Place);
  FKeys.Add(Key, Slot);
  if not ATerminal then
    ANext.Add(Slot);
  Result := True;
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
    Exit;
  Found := False;
  for Symbol in Extracted.Symbols do
    if RangeContains(Symbol.Range, APosition) and (not Found or (RangeSize(Symbol.Range) < RangeSize(Best.Range))) then
    begin
      Best := Symbol;
      Found := True;
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
    AItem.Name := ChangeFileExt(ExtractFileName(AFileName), '');
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
    Exit;
  for Index in Indexed.SymbolsNamed(AName) do
    if (Indexed.Symbols[Index].Kind in MethodKinds) and SameText(Indexed.Symbols[Index].Container, ATypeName) then
    begin
      AItem := TLspHierarchies.ItemOf(Indexed.UnitName, Indexed.SymbolFile(Indexed.Symbols[Index]),
        Indexed.Symbols[Index]);
      Exit(True);
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
    Exit;
  for Index in AUnit.SymbolsNamed(Resolved.Name) do
    if (AUnit.Symbols[Index].Kind in TypeKinds) and SameText(AUnit.Symbols[Index].Container, Resolved.Container) then
    begin
      ASymbol := AUnit.Symbols[Index];
      Exit(True);
    end;
end;

procedure TImpactRun.AddReferences(const AItem: THierarchyItem; ACause, ALevel: Integer; var ANext: TList<Integer>);
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
    Exit;
  Locations := TLspReferences.Find(FResolver, FIndex, Tree, AItem.FileName, AItem.SelectionRange.StartPos, False,
    TImpactAnalysis.CandidateFiles(FIndex, FFiles, AItem.Name), FReadText, FOptions.References, FToken);
  if TLspHierarchies.IsRoutine(AItem) then
    Edge := TImpactEdge.Call
  else
    Edge := TImpactEdge.Reference;
  for Location in Locations do
  begin
    FToken.ThrowIfCancellationRequested;
    // Formularbindungen gehören zur Stelle selbst (FormBindings), nicht zur nächsten Ebene.
    if IsFormFile(Location.FileName) then
      Continue;
    Tree := TreeOf(Location.FileName);
    if Tree = nil then
      Continue;
    Terminal := False;
    if not TLspHierarchies.CallerAt(Tree, Location.FileName, Location.Range.StartPos, Place) then
    begin
      // Die Unit selbst (Terminal) ist keine Deklaration, die man weiter verfolgen könnte.
      if not EnclosingDeclaration(Location.FileName, Location.Range.StartPos, Place, Terminal) then
        Continue;
      // Der Verweis steht in der eigenen Deklaration (Methodenkopf in der Klasse): keine neue Stelle.
      if not Terminal and (KeyOf(Place, False) = KeyOf(AItem, False)) then
        Continue;
    end;
    Add(Place, ALevel, Edge, ACause, [Location.Range], Location.Confidence, Terminal, ANext);
  end;
end;

procedure TImpactRun.AddStructural(const AItem: THierarchyItem; ACause, ALevel: Integer; var ANext: TList<Integer>);
var
  OwnUnit, TypeUnit, BaseUnit: TUnitIndex;
  Own, Owner, Base: TIndexSymbol;
  Found: TIndexSymbol;
  Pending: TQueue<string>;
  Seen: TDictionary<string, Boolean>;
  Location: TSymbolLocation;
  TypeName, Ancestor, Resolution, Target: string;
  Member: THierarchyItem;
  Index, Steps, EqualsAt: Integer;
  OwnerFound: Boolean;
begin
  if not (AItem.SymbolKind in MethodKinds) or (AItem.Container = '') or
    not DeclarationSymbol(AItem, OwnUnit, Own) then
    Exit;
  OwnerFound := False;
  for Index in OwnUnit.SymbolsNamed(Own.Container) do
    if OwnUnit.Symbols[Index].Kind in TypeKinds then
    begin
      Owner := OwnUnit.Symbols[Index];
      OwnerFound := True;
      Break;
    end;
  // Overrides in allen Nachfahren bzw. Umsetzungen der Interface-Methode.
  if Own.IsVirtual or (OwnerFound and (Owner.Kind = TIndexSymbolKind.InterfaceType)) then
  begin
    Pending := TQueue<string>.Create;
    Seen := TDictionary<string, Boolean>.Create;
    try
      Pending.Enqueue(Own.Container);
      Seen.Add(UpperCase(Own.Container), True);
      while (Pending.Count > 0) and (Seen.Count < MaxDescendants) do
      begin
        FToken.ThrowIfCancellationRequested;
        TypeName := Pending.Dequeue;
        for Location in FIndex.Descendants(TypeName) do
        begin
          if not (Location.Symbol.Kind in TypeKinds) or Seen.ContainsKey(UpperCase(Location.Symbol.Name)) then
            Continue;
          Seen.Add(UpperCase(Location.Symbol.Name), True);
          Pending.Enqueue(Location.Symbol.Name);
          if OwnerFound and (Owner.Kind = TIndexSymbolKind.InterfaceType) then
          begin
            // Umsetzung: gleichnamige Methode oder Methodenzuordnung IFoo.Bar = Baz.
            Target := Own.Name;
            for Resolution in Location.Symbol.Resolutions do
            begin
              EqualsAt := Pos('=', Resolution);
              if (EqualsAt > 0) and SameText(Trim(Copy(Resolution, 1, EqualsAt - 1)), Own.Container + '.' + Own.Name) then
                Target := Trim(Copy(Resolution, EqualsAt + 1, MaxInt));
            end;
            if (Location.Symbol.Kind <> TIndexSymbolKind.InterfaceType) and
              MemberOf(Location.FileName, Location.Symbol.Name, Target, Member) then
              Add(Member, ALevel, TImpactEdge.Implementation_, ACause, nil, TReferenceConfidence.Sure, False, ANext);
          end
          else if FIndex.FindFile(Location.FileName, TypeUnit) then
          begin
            for Index in TypeUnit.SymbolsNamed(Own.Name) do
              if SameText(TypeUnit.Symbols[Index].Container, Location.Symbol.Name) and
                TypeUnit.Symbols[Index].HasDirective('override') then
              begin
                Add(TLspHierarchies.ItemOf(TypeUnit.UnitName, TypeUnit.SymbolFile(TypeUnit.Symbols[Index]),
                  TypeUnit.Symbols[Index]), ALevel, TImpactEdge.Override_, ACause, nil, TReferenceConfidence.Sure,
                  False, ANext);
                Break;
              end;
          end;
        end;
      end;
    finally
      Seen.Free;
      Pending.Free;
    end;
  end;
  if not OwnerFound or (Owner.Kind = TIndexSymbolKind.InterfaceType) then
    Exit;
  // Überschriebene Basismethode: der nächste Vorfahr mit einer gleichnamigen Methode.
  if Own.HasDirective('override') then
  begin
    TypeUnit := OwnUnit;
    Found := Owner;
    for Steps := 1 to MaxAncestors do
    begin
      if (Length(Found.Ancestors) = 0) or not TypeSymbol(TypeUnit, Found.Ancestors[0], BaseUnit, Base) or
        (Base.Kind = TIndexSymbolKind.InterfaceType) then
        Break;
      if MemberOf(BaseUnit.FileName, Base.Name, Own.Name, Member) then
      begin
        Add(Member, ALevel, TImpactEdge.BaseMethod, ACause, nil, TReferenceConfidence.Sure, False, ANext);
        Break;
      end;
      TypeUnit := BaseUnit;
      Found := Base;
    end;
  end;
  // Interface-Methoden, die die Methode umsetzt: gleichnamige oder per Methodenzuordnung.
  for Ancestor in Owner.Ancestors do
    if TypeSymbol(OwnUnit, Ancestor, BaseUnit, Base) and (Base.Kind = TIndexSymbolKind.InterfaceType) then
    begin
      Target := Own.Name;
      for Resolution in Owner.Resolutions do
      begin
        EqualsAt := Pos('=', Resolution);
        if (EqualsAt > 0) and SameText(Trim(Copy(Resolution, EqualsAt + 1, MaxInt)), Own.Name) and
          StartsText(WithoutGenerics(Ancestor) + '.', Trim(Copy(Resolution, 1, EqualsAt - 1))) then
          Target := Copy(Trim(Copy(Resolution, 1, EqualsAt - 1)), Length(WithoutGenerics(Ancestor)) + 2, MaxInt);
      end;
      if MemberOf(BaseUnit.FileName, Base.Name, Target, Member) then
        Add(Member, ALevel, TImpactEdge.InterfaceMethod, ACause, nil, TReferenceConfidence.Sure, False, ANext);
    end;
end;

procedure TImpactRun.Expand(const AItem: THierarchyItem; ACause, ALevel: Integer; var ANext: TList<Integer>);
begin
  FToken.ThrowIfCancellationRequested;
  AddReferences(AItem, ACause, ALevel, ANext);
  AddStructural(AItem, ACause, ALevel, ANext);
end;

function TImpactRun.Run(const AStart: THierarchyItem): TImpactResult;
var
  Frontier, Next: TList<Integer>;
  Level, Slot: Integer;
  Item: THierarchyItem;
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
      Result.SymbolForms := FormBindings(AStart);
      FKeys.Add(KeyOf(AStart, False), -1);
      // Das Symbol selbst kann ein Test sein (Ebene 0).
      TestOf(AStart, 0);
      Frontier.Add(-1);
      for Level := 1 to FOptions.Depth do
      begin
        Next.Clear;
        for Slot in Frontier do
        begin
          if FFull then
            Break;
          if Slot < 0 then
            Item := AStart
          else
            Item := FPlaces[Slot].Item;
          Expand(Item, Slot, Level, Next);
        end;
        Frontier.Clear;
        Frontier.AddRange(Next.ToArray);
        if (Frontier.Count = 0) or FFull then
          Break;
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
      Include(Result.Limits, TImpactLimit.Count);
    Result.Places := FPlaces.ToArray;
    Result.Tests := FTests.ToArray;
  finally
    Next.Free;
    Frontier.Free;
  end;
end;

{ TImpactAnalysis }

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
    Result := MinDepth
  else if Result > MaxDepth then
    Result := MaxDepth;
end;

class function TImpactAnalysis.CandidateFiles(const AIndex: ISymbolIndex; const AFiles: TArray<string>;
  const AName: string): TArray<string>;
var
  FileName, Alternative: string;
  Count: Integer;
begin
  // Attribute (#119): [Foo] verwendet FooAttribute; wie in der Referenzsuche beide Schreibweisen.
  if EndsText('Attribute', AName) and (Length(AName) > Length('Attribute')) then
    Alternative := Copy(AName, 1, Length(AName) - Length('Attribute'))
  else
    Alternative := AName + 'Attribute';
  SetLength(Result, Length(AFiles));
  Count := 0;
  for FileName in AFiles do
    if (TIndexUsages.Lookup(AIndex, FileName, AName) <> TIndexUsageAnswer.Absent) or
      (TIndexUsages.Lookup(AIndex, FileName, Alternative) <> TIndexUsageAnswer.Absent) then
    begin
      Result[Count] := FileName;
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

class function TImpactAnalysis.Analyze(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AStart: THierarchyItem; const AFiles: TArray<string>; const AReadText: TReferenceReadText;
  const AOptions: TImpactOptions; const ACancellation: IJsonRpcCancellationToken): TImpactResult;
var
  Run: TImpactRun;
begin
  Run := TImpactRun.Create(AResolver, AIndex, AFiles, AReadText, AOptions, ACancellation, nil);
  try
    Result := Run.Run(AStart);
  finally
    Run.Free;
  end;
end;

class function TImpactAnalysis.AnalyzeEach(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AStarts: TArray<THierarchyItem>; const AFiles: TArray<string>; const AReadText: TReferenceReadText;
  const AOptions: TImpactOptions; const ACancellation: IJsonRpcCancellationToken): TArray<TImpactResult>;
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
  mShared := TImpactFiles.Create;
  try
    for mIndex := 0 to High(AStarts) do
    begin
      if ACancellation <> nil then
        ACancellation.ThrowIfCancellationRequested;
      if AOptions.TimeoutMs > 0 then
      begin
        // Mindestens 1 ms: 0 hieße ohne Zeitlimit.
        mLeft := (AOptions.TimeoutMs - mClock.ElapsedMilliseconds) div (Length(AStarts) - mIndex);
        if mLeft < 1 then
          mLeft := 1;
        mOptions.TimeoutMs := Integer(mLeft);
      end;
      mRun := TImpactRun.Create(AResolver, AIndex, AFiles, AReadText, mOptions, ACancellation, mShared);
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

class function TImpactAnalysis.ToJson(const AResult: TImpactResult): TJSONObject;
var
  Places, Tests, Ranges, Names: TJSONArray;
  Limits: TJSONObject;
  Entry: TJSONObject;
  Place: TImpactPlace;
  Test: TImpactTest;
  Range: TTextRange;
  Name: string;
  Limit: TImpactLimit;
begin
  Result := TJSONObject.Create;
  Result.AddPair('symbol', TLspHierarchies.ItemToJson(AResult.Symbol));
  Result.AddPair('symbolForms', FormsToJson(AResult.SymbolForms));
  Result.AddPair('depth', TJSONNumber.Create(AResult.Depth));
  Places := TJSONArray.Create;
  Result.AddPair('places', Places);
  for Place in AResult.Places do
  begin
    Entry := TJSONObject.Create;
    Places.AddElement(Entry);
    Entry.AddPair('level', TJSONNumber.Create(Place.Level));
    Entry.AddPair('edge', EdgeName(Place.Edge));
    Entry.AddPair('cause', TJSONNumber.Create(Place.Cause));
    Entry.AddPair('item', TLspHierarchies.ItemToJson(Place.Item));
    Ranges := TJSONArray.Create;
    Entry.AddPair('ranges', Ranges);
    for Range in Place.Ranges do
      Ranges.AddElement(TLspPositions.RangeToJson(Range));
    Entry.AddPair('atlasConfidence', Place.Confidence.ToJson);
    Entry.AddPair('forms', FormsToJson(Place.Forms));
    if Place.Terminal then
      Entry.AddPair('terminal', TJSONBool.Create(True));
    if Place.Test >= 0 then
      Entry.AddPair('test', AResult.Tests[Place.Test].Name);
  end;
  Tests := TJSONArray.Create;
  Result.AddPair('tests', Tests);
  for Test in AResult.Tests do
  begin
    Entry := TJSONObject.Create;
    Tests.AddElement(Entry);
    Entry.AddPair('name', Test.Name);
    Names := TJSONArray.Create;
    Entry.AddPair('run', Names);
    for Name in Test.RunNames do
      Names.Add(Name);
    Entry.AddPair('uri', TDocumentUris.FromPath(Test.FileName));
    Entry.AddPair('line', TJSONNumber.Create(Test.Line));
    Entry.AddPair('level', TJSONNumber.Create(Test.Level));
  end;
  Limits := TJSONObject.Create;
  Result.AddPair('limits', Limits);
  for Limit := Low(TImpactLimit) to High(TImpactLimit) do
    Limits.AddPair(LimitName(Limit), TJSONBool.Create(Limit in AResult.Limits));
  Result.AddPair('unexpanded', TJSONNumber.Create(AResult.Unexpanded));
  Result.AddPair('maxPlaces', TJSONNumber.Create(AResult.MaxPlaces));
  Result.AddPair('timeoutMs', TJSONNumber.Create(AResult.TimeoutMs));
end;

function TImpactAnalysis.HandleImpact(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Tree, OwnTree: TSyntaxTree;
  Text: string;
  Resolver: TNameResolver;
  Start: THierarchyItem;
  Found: Boolean;
  Options: TImpactOptions;
  Depth: Integer;
  Files: TArray<string>;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen in ' + Method);
  if Assigned(FOptionsFor) then
    Options := FOptionsFor(Uri)
  else
    Options := TImpactOptions.Default;
  if TJSONObject(AParams).TryGetValue<Integer>('depth', Depth) then
    Options.Depth := Depth;
  Cancellation := TRequestCancellation.Create(ACancellation);
  OwnTree := nil;
  if FStore.TryGet(Uri, Document) then
  begin
    Shared := TSyntaxTreeCache.Get(Document, Cancellation);
    Tree := Shared.Tree;
  end
  else if Assigned(FReadText) and FReadText(TDocumentUris.ToPath(Uri), Text) then
  begin
    OwnTree := TSyntaxTreeCache.Parse(Text, Cancellation);
    Tree := OwnTree;
  end
  else
    Exit(TJSONNull.Create);
  Files := nil;
  if Assigned(FFiles) then
    Files := FFiles();
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
      Exit(TJSONNull.Create);
    Result := ToJson(Analyze(Resolver, FIndex, Start, Files, FReadText, Options, ACancellation));
  finally
    Resolver.Free;
  end;
end;

end.
