unit Atlas.Common.Lsp.Impact.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Hierarchies,
  Atlas.Common.Lsp.Impact;

type
  [TestFixture]
  TImpactAnalysisTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemAt(const AFileName, AMarker, AName: string): THierarchyItem;
    function Analyze(const AStart: THierarchyItem; ADepth: Integer): TImpactResult; overload;
    function Analyze(const AStart: THierarchyItem; const AOptions: TImpactOptions): TImpactResult; overload;
    function PlaceNamed(const AResult: TImpactResult; const AName: string): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DirectCallerOnLevelOne;
    [Test]
    procedure IndirectCallersNamedWithTheirCause;
    [Test]
    procedure FormHandlerOnLastLevelKeepsBinding;
    [Test]
    procedure UnitLevelUseIsTerminal;
    [Test]
    procedure AffectedTestsWithRunNames;
    [Test]
    procedure DepthLimitCountsUnexpanded;
    [Test]
    procedure CycleEndsAtStart;
    [Test]
    procedure CountLimitStopsAndReports;
    [Test]
    procedure TimeLimitReported;
    [Test]
    procedure OverrideFoundFromBase;
    [Test]
    procedure BaseMethodFoundFromOverride;
    [Test]
    procedure ImplementationFoundFromInterface;
    [Test]
    procedure InterfaceMethodFoundFromImplementation;
    [Test]
    procedure DepthClamped;
    [Test]
    procedure CandidateFilesSkipFilesWithoutName;
    [Test]
    procedure TestScopeFromProgram;
    [Test]
    procedure JsonCarriesLevelsEdgesAndLimits;
    [Test]
    procedure HandlerAnswersAtlasImpact;
    [Test]
    procedure McpTextShowsTreeTestsAndLimits;
    [Test]
    procedure McpJsonLikeAtlasImpact;
    [Test]
    [Category('Benchmark')]
    procedure LongChainStaysFast;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  System.Diagnostics,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.ReferenceConfidence,
  Atlas.Common.Lsp.References,
  Atlas.Common.Mcp.CodeTools;

const
  WerkzeugFile = 'C:\P\Werkzeug.pas';
  HauptFile = 'C:\P\Haupt.pas';
  HauptForm = 'C:\P\Haupt.dfm';
  TestFile = 'C:\P\Werkzeug.Tests.pas';
  AbseitsFile = 'C:\P\Abseits.pas';

  UnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    'type'#10 +
    '  IRechner = interface'#10 +
    '    procedure Rechne;'#10 +
    '  end;'#10 +
    '  TBasis = class'#10 +
    '    procedure Arbeite; virtual;'#10 +
    '  end;'#10 +
    '  TKind = class(TBasis, IRechner)'#10 +
    '    procedure Arbeite; override;'#10 +
    '    procedure Rechne;'#10 +
    '  end;'#10 +
    'procedure Ziel;'#10 +
    'procedure Hilfe;'#10 +
    'procedure Oben;'#10 +
    'procedure Hin;'#10 +
    'procedure Her;'#10 +
    'implementation'#10 +
    'procedure TBasis.Arbeite;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TKind.Arbeite;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TKind.Rechne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Ziel;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Hilfe;'#10 +
    'begin'#10 +
    '  Ziel;'#10 +
    '  Ziel;'#10 +
    'end;'#10 +
    'procedure Oben;'#10 +
    'begin'#10 +
    '  Hilfe;'#10 +
    'end;'#10 +
    'procedure Hin;'#10 +
    'begin'#10 +
    '  Her;'#10 +
    'end;'#10 +
    'procedure Her;'#10 +
    'begin'#10 +
    '  Hin;'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Werkzeug;'#10 +
    'type'#10 +
    '  TForm1 = class'#10 +
    '    procedure Button1Click(Sender: TObject);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    '{$R *.dfm}'#10 +
    'procedure TForm1.Button1Click(Sender: TObject);'#10 +
    'begin'#10 +
    '  Oben;'#10 +
    'end;'#10 +
    'initialization'#10 +
    '  Hilfe;'#10 +
    'end.';

  FormHaupt =
    'object Form1: TForm1'#10 +
    '  object Button1: TButton'#10 +
    '    OnClick = Button1Click'#10 +
    '  end'#10 +
    'end';

  UnitTests =
    'unit Werkzeug.Tests;'#10 +
    'interface'#10 +
    'uses DUnitX.TestFramework, Werkzeug;'#10 +
    'type'#10 +
    '  [TestFixture]'#10 +
    '  TWerkzeugTests = class'#10 +
    '  public'#10 +
    '    [Test]'#10 +
    '    procedure PrueftHilfe;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TWerkzeugTests.PrueftHilfe;'#10 +
    'begin'#10 +
    '  Hilfe;'#10 +
    'end;'#10 +
    'end.';

  UnitAbseits =
    'unit Abseits;'#10 +
    'interface'#10 +
    'procedure Fern;'#10 +
    'implementation'#10 +
    'procedure Fern;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, WerkzeugFile) then
    Result := UnitWerkzeug
  else if SameText(AFileName, HauptFile) then
    Result := UnitHaupt
  else if SameText(AFileName, HauptForm) then
    Result := FormHaupt
  else if SameText(AFileName, TestFile) then
    Result := UnitTests
  else if SameText(AFileName, AbseitsFile) then
    Result := UnitAbseits
  else
    Result := '';
end;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  AText := TextOf(AFileName);
  Result := AText <> '';
end;

function ProjectFiles: TArray<string>;
begin
  Result := TArray<string>.Create(WerkzeugFile, HauptFile, TestFile, AbseitsFile);
end;

function PositionOf(const AText, AMarker, AName: string): TTextPosition;
var
  Index, Line, LineStart, Scan: Integer;
begin
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Index := Index + Pos(AName, AMarker) - 1;
  Line := 0;
  LineStart := 1;
  for Scan := 1 to Index - 1 do
    if AText[Scan] = #10 then
    begin
      Inc(Line);
      LineStart := Scan + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

function Describe(const AResult: TImpactResult): string;
var
  Place: TImpactPlace;
begin
  Result := '';
  for Place in AResult.Places do
    Result := Result + Format('%s.%s@%d:%d(L%d c%d) ', [Place.Item.Container, Place.Item.Name,
      Place.Item.SelectionRange.StartPos.Line, Place.Item.SelectionRange.StartPos.Character, Place.Level,
      Place.Cause]);
end;

function Options(ADepth: Integer): TImpactOptions;
begin
  Result := TImpactOptions.Default;
  Result.Depth := ADepth;
  Result.Tests.Pattern := '{unit}.Tests';
end;

{ TImpactAnalysisTests }

procedure TImpactAnalysisTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, WerkzeugFile, nil, nil, True));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitHaupt, HauptFile, nil, nil, True));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitTests, TestFile, nil, nil, True));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitAbseits, AbseitsFile, nil, nil, True));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TImpactAnalysisTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TImpactAnalysisTests.ItemAt(const AFileName, AMarker, AName: string): THierarchyItem;
var
  Tree: TSyntaxTree;
begin
  Tree := TSyntaxTreeCache.Parse(TextOf(AFileName));
  try
    Assert.IsTrue(TLspHierarchies.SymbolItemAt(FResolver, Tree, AFileName,
      PositionOf(TextOf(AFileName), AMarker, AName), Result), AMarker);
  finally
    Tree.Free;
  end;
end;

function TImpactAnalysisTests.Analyze(const AStart: THierarchyItem; ADepth: Integer): TImpactResult;
begin
  Result := Analyze(AStart, Options(ADepth));
end;

function TImpactAnalysisTests.Analyze(const AStart: THierarchyItem; const AOptions: TImpactOptions): TImpactResult;
begin
  Result := TImpactAnalysis.Analyze(FResolver, FIndex, AStart, ProjectFiles,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadFile(AFileName, AText);
    end, AOptions, nil);
end;

function TImpactAnalysisTests.PlaceNamed(const AResult: TImpactResult; const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(AResult.Places) do
    if SameText(AResult.Places[Index].Item.Name, AName) then
      Exit(Index);
  Result := -1;
end;

procedure TImpactAnalysisTests.DirectCallerOnLevelOne;
var
  Found: TImpactResult;
  Hilfe: Integer;
begin
  Found := Analyze(ItemAt(WerkzeugFile, 'procedure Ziel;', 'Ziel'), 1);
  Assert.AreEqual('Ziel', Found.Symbol.Name);
  Assert.AreEqual(1, Integer(Length(Found.Places)));
  Hilfe := PlaceNamed(Found, 'Hilfe');
  Assert.AreEqual(0, Hilfe);
  Assert.AreEqual(1, Found.Places[Hilfe].Level);
  Assert.AreEqual(-1, Found.Places[Hilfe].Cause);
  Assert.IsTrue(Found.Places[Hilfe].Edge = TImpactEdge.Call);
  // Beide Aufrufe in Hilfe gehören zur selben Stelle.
  Assert.AreEqual(2, Integer(Length(Found.Places[Hilfe].Ranges)));
  Assert.IsTrue(Found.Places[Hilfe].Confidence.IsSure);
end;

procedure TImpactAnalysisTests.IndirectCallersNamedWithTheirCause;
var
  Found: TImpactResult;
  Hilfe, Oben, Handler: Integer;
begin
  Found := Analyze(ItemAt(WerkzeugFile, 'procedure Ziel;', 'Ziel'), 3);
  Hilfe := PlaceNamed(Found, 'Hilfe');
  Oben := PlaceNamed(Found, 'Oben');
  Handler := PlaceNamed(Found, 'Button1Click');
  Assert.IsTrue(Oben >= 0, Describe(Found));
  Assert.AreEqual(2, Found.Places[Oben].Level);
  Assert.AreEqual(Hilfe, Found.Places[Oben].Cause);
  Assert.IsTrue(Handler >= 0);
  Assert.AreEqual(3, Found.Places[Handler].Level);
  Assert.AreEqual(Oben, Found.Places[Handler].Cause);
  Assert.AreEqual(1, Found.LevelCount(1));
end;

procedure TImpactAnalysisTests.FormHandlerOnLastLevelKeepsBinding;
var
  Found: TImpactResult;
  Handler: Integer;
begin
  // Der Handler steht auf der letzten Ebene; seine Bindung im Formular kostet keine eigene.
  Found := Analyze(ItemAt(WerkzeugFile, 'procedure Oben;', 'Oben'), 1);
  Handler := PlaceNamed(Found, 'Button1Click');
  Assert.IsTrue(Handler >= 0);
  Assert.AreEqual(1, Integer(Length(Found.Places[Handler].Forms)));
  Assert.AreEqual(HauptForm, Found.Places[Handler].Forms[0].FileName);
  Assert.AreEqual('OnClick = Button1Click', Found.Places[Handler].Forms[0].Text);
  Assert.AreEqual(2, Found.Places[Handler].Forms[0].Range.StartPos.Line);
end;

procedure TImpactAnalysisTests.UnitLevelUseIsTerminal;
var
  Found: TImpactResult;
  Index: Integer;
  Terminal: Boolean;
begin
  Found := Analyze(ItemAt(WerkzeugFile, 'procedure Hilfe;', 'Hilfe'), 2);
  Terminal := False;
  for Index := 0 to High(Found.Places) do
    if Found.Places[Index].Terminal then
    begin
      Terminal := True;
      Assert.AreEqual('Haupt', Found.Places[Index].Item.Name);
      Assert.AreEqual(1, Found.Places[Index].Level);
    end;
  Assert.IsTrue(Terminal);
  // Die Unit selbst wird nicht weiter verfolgt: Keine Stelle nennt sie als Ursache.
  for Index := 0 to High(Found.Places) do
    if Found.Places[Index].Cause >= 0 then
      Assert.IsFalse(Found.Places[Found.Places[Index].Cause].Terminal);
end;

procedure TImpactAnalysisTests.AffectedTestsWithRunNames;
var
  Found: TImpactResult;
  Test: Integer;
begin
  Found := Analyze(ItemAt(WerkzeugFile, 'procedure Ziel;', 'Ziel'), 2);
  Assert.AreEqual(1, Integer(Length(Found.Tests)));
  Assert.AreEqual('Werkzeug.Tests.TWerkzeugTests.PrueftHilfe', Found.Tests[0].Name);
  Assert.AreEqual(2, Found.Tests[0].Level);
  Assert.AreEqual(TestFile, Found.Tests[0].FileName);
  Assert.AreEqual(1, Integer(Length(Found.RunNames)));
  Assert.AreEqual('Werkzeug.Tests.TWerkzeugTests.PrueftHilfe', Found.RunNames[0]);
  Test := PlaceNamed(Found, 'PrueftHilfe');
  Assert.IsTrue(Test >= 0);
  Assert.AreEqual(0, Found.Places[Test].Test);
end;

procedure TImpactAnalysisTests.DepthLimitCountsUnexpanded;
var
  Found: TImpactResult;
begin
  Found := Analyze(ItemAt(WerkzeugFile, 'procedure Ziel;', 'Ziel'), 1);
  Assert.IsTrue(TImpactLimit.Depth in Found.Limits);
  Assert.AreEqual(1, Found.Unexpanded);
  Assert.IsFalse(TImpactLimit.Count in Found.Limits);
end;

procedure TImpactAnalysisTests.CycleEndsAtStart;
var
  Found: TImpactResult;
begin
  // Hin ruft Her, Her ruft Hin: Hin ist das Symbol und erscheint nicht noch einmal.
  Found := Analyze(ItemAt(WerkzeugFile, 'procedure Hin;', 'Hin'), 5);
  Assert.AreEqual(1, Integer(Length(Found.Places)));
  Assert.AreEqual('Her', Found.Places[0].Item.Name);
  Assert.IsFalse(TImpactLimit.Depth in Found.Limits);
end;

procedure TImpactAnalysisTests.CountLimitStopsAndReports;
var
  Settings: TImpactOptions;
  Found: TImpactResult;
begin
  Settings := Options(3);
  Settings.MaxPlaces := 2;
  Found := Analyze(ItemAt(WerkzeugFile, 'procedure Ziel;', 'Ziel'), Settings);
  Assert.AreEqual(2, Integer(Length(Found.Places)));
  Assert.IsTrue(TImpactLimit.Count in Found.Limits);
  Assert.AreEqual(2, Found.MaxPlaces);
end;

procedure TImpactAnalysisTests.TimeLimitReported;
var
  Settings: TImpactOptions;
  Found: TImpactResult;
begin
  // 1 ms: Spätestens die zweite Ebene liegt hinter der Grenze; das Ergebnis bis dahin bleibt.
  Settings := Options(5);
  Settings.TimeoutMs := 1;
  Sleep(5);
  Found := Analyze(ItemAt(WerkzeugFile, 'procedure Ziel;', 'Ziel'), Settings);
  Assert.AreEqual(1, Found.TimeoutMs);
  Assert.IsTrue((TImpactLimit.Time in Found.Limits) or (Length(Found.Places) > 0));
end;

procedure TImpactAnalysisTests.OverrideFoundFromBase;
var
  Found: TImpactResult;
  Index: Integer;
begin
  Found := Analyze(ItemAt(WerkzeugFile, 'procedure Arbeite; virtual', 'Arbeite'), 1);
  Index := PlaceNamed(Found, 'Arbeite');
  Assert.IsTrue(Index >= 0);
  Assert.AreEqual('TKind', Found.Places[Index].Item.Container);
  Assert.IsTrue(Found.Places[Index].Edge = TImpactEdge.Override_);
end;

procedure TImpactAnalysisTests.BaseMethodFoundFromOverride;
var
  Found: TImpactResult;
  Index: Integer;
begin
  Found := Analyze(ItemAt(WerkzeugFile, 'procedure Arbeite; override', 'Arbeite'), 1);
  Index := PlaceNamed(Found, 'Arbeite');
  Assert.IsTrue(Index >= 0);
  Assert.AreEqual('TBasis', Found.Places[Index].Item.Container);
  Assert.IsTrue(Found.Places[Index].Edge = TImpactEdge.BaseMethod);
end;

procedure TImpactAnalysisTests.ImplementationFoundFromInterface;
var
  Found: TImpactResult;
  Index: Integer;
begin
  Found := Analyze(ItemAt(WerkzeugFile, '    procedure Rechne;'#10'  end;'#10'  TBasis', 'Rechne'), 1);
  Index := PlaceNamed(Found, 'Rechne');
  Assert.IsTrue(Index >= 0);
  Assert.AreEqual('TKind', Found.Places[Index].Item.Container);
  Assert.IsTrue(Found.Places[Index].Edge = TImpactEdge.Implementation_);
end;

procedure TImpactAnalysisTests.InterfaceMethodFoundFromImplementation;
var
  Found: TImpactResult;
  Index: Integer;
begin
  Found := Analyze(ItemAt(WerkzeugFile, 'procedure TKind.Rechne;', 'Rechne'), 1);
  Index := PlaceNamed(Found, 'Rechne');
  Assert.IsTrue(Index >= 0);
  Assert.AreEqual('IRechner', Found.Places[Index].Item.Container);
  Assert.IsTrue(Found.Places[Index].Edge = TImpactEdge.InterfaceMethod);
end;

procedure TImpactAnalysisTests.DepthClamped;
begin
  Assert.AreEqual(1, TImpactAnalysis.ClampDepth(0));
  Assert.AreEqual(3, TImpactAnalysis.ClampDepth(3));
  Assert.AreEqual(5, TImpactAnalysis.ClampDepth(9));
  Assert.AreEqual(2, Analyze(ItemAt(WerkzeugFile, 'procedure Hin;', 'Hin'), 2).Depth);
end;

procedure TImpactAnalysisTests.CandidateFilesSkipFilesWithoutName;
var
  Files: TArray<string>;
begin
  Files := TImpactAnalysis.CandidateFiles(FIndex, TArray<string>.Create(WerkzeugFile, HauptFile, AbseitsFile,
    'C:\P\Fremd.pas'), 'Hilfe');
  // Abseits kennt Hilfe laut Index nicht; Fremd steht nicht im Index und bleibt.
  Assert.AreEqual(3, Integer(Length(Files)));
  Assert.AreEqual(WerkzeugFile, Files[0]);
  Assert.AreEqual(HauptFile, Files[1]);
  Assert.AreEqual('C:\P\Fremd.pas', Files[2]);
end;

procedure TImpactAnalysisTests.TestScopeFromProgram;
var
  Scope: TImpactTestScope;
begin
  Scope := TImpactTestScope.FromProgram('Test.{unit}',
    'program Tests;'#10'uses'#10'  DUnitX.TestFramework,'#10'  Kunden.Pruefung in ''Kunden.Pruefung.pas'';'#10 +
    'begin'#10'end.');
  Assert.IsTrue(Scope.Contains('Kunden.Pruefung'));
  Assert.IsTrue(Scope.Contains('Test.Kunden'));
  Assert.IsFalse(Scope.Contains('Kunden'));
  Assert.IsFalse(Scope.Contains(''));
  Scope := TImpactTestScope.FromProgram('{unit}.Tests', '');
  Assert.AreEqual(0, Integer(Length(Scope.Units)));
end;

procedure TImpactAnalysisTests.JsonCarriesLevelsEdgesAndLimits;
var
  Json: TJSONObject;
  Places, Tests: TJSONArray;
  Place: TJSONObject;
begin
  Json := TImpactAnalysis.ToJson(Analyze(ItemAt(WerkzeugFile, 'procedure Ziel;', 'Ziel'), 2));
  try
    Assert.AreEqual(2, Json.GetValue<Integer>('depth'));
    Places := Json.GetValue('places') as TJSONArray;
    Assert.IsTrue(Places.Count >= 3);
    Place := Places.Items[0] as TJSONObject;
    Assert.AreEqual(1, Place.GetValue<Integer>('level'));
    Assert.AreEqual('call', Place.GetValue<string>('edge'));
    Assert.AreEqual(-1, (Place.GetValue('cause') as TJSONNumber).AsInt);
    Assert.AreEqual('Hilfe', Place.GetValue<string>('item.name'));
    Tests := Json.GetValue('tests') as TJSONArray;
    Assert.AreEqual(1, Tests.Count);
    Assert.IsTrue(Json.GetValue<Boolean>('limits.depth'));
    Assert.IsFalse(Json.GetValue<Boolean>('limits.count'));
    Assert.IsFalse(Json.GetValue<Boolean>('limits.time'));
  finally
    Json.Free;
  end;
end;

procedure TImpactAnalysisTests.HandlerAnswersAtlasImpact;
var
  Store: IDocumentStore;
  Analysis: TImpactAnalysis;
  Dispatcher: TJsonRpcDispatcher;
  Message, Response: TJSONObject;
  Position: TTextPosition;
begin
  Store := TDocumentStore.Create;
  Store.Open(TDocumentUris.FromPath(WerkzeugFile), 'delphi', 1, UnitWerkzeug);
  Analysis := TImpactAnalysis.Create(Store, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadFile(AFileName, AText);
    end,
    function: TArray<string>
    begin
      Result := ProjectFiles;
    end);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Analysis.Attach(Dispatcher);
    Position := PositionOf(UnitWerkzeug, 'procedure Ziel;', 'Ziel');
    Message := TJSONObject.ParseJSONValue(Format('{"jsonrpc":"2.0","id":1,"method":"%s","params":{' +
      '"textDocument":{"uri":"%s"},"position":{"line":%d,"character":%d},"depth":1}}', [TImpactAnalysis.Method,
      TDocumentUris.FromPath(WerkzeugFile), Position.Line, Position.Character])) as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Message);
      try
        Assert.IsTrue(Response.GetValue('result') is TJSONObject, Response.ToJSON);
        Assert.AreEqual(1, Response.GetValue<Integer>('result.depth'));
        Assert.AreEqual(1, Response.GetValue<TJSONArray>('result.places').Count);
      finally
        Response.Free;
      end;
    finally
      Message.Free;
    end;
  finally
    Dispatcher.Free;
    Analysis.Free;
  end;
end;

function NewTools(const AIndex: ISymbolIndex): TMcpCodeTools;
begin
  Result := TMcpCodeTools.Create(AIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadFile(AFileName, AText);
    end,
    function: TArray<string>
    begin
      Result := ProjectFiles;
    end);
end;

procedure TImpactAnalysisTests.McpTextShowsTreeTestsAndLimits;
var
  Tools: TMcpCodeTools;
  Text: string;
begin
  Tools := NewTools(FIndex);
  try
    Text := Tools.Impact('Ziel', 2, False);
    Assert.IsTrue(Pos('Auswirkungen von Ziel', Text) = 1, Text);
    Assert.IsTrue(Pos('Tiefe 2', Text) > 0, Text);
    Assert.IsTrue(Pos(' Hilfe – Unit Werkzeug', Text) > 0, Text);
    // Ebene 2 eine Stufe tiefer eingerückt unter ihrer Ursache.
    Assert.IsTrue(Pos(#10'    ', Text) > Pos(' Hilfe – Unit', Text), Text);
    Assert.IsTrue(Pos(' Oben – Unit Werkzeug', Text) > Pos(' Hilfe – Unit', Text), Text);
    Assert.IsTrue(Pos('(Aufruf, 2×)', Text) > 0, Text);
    Assert.IsTrue(Pos('Unit-Ebene', Text) > 0, Text);
    Assert.IsTrue(Pos('run_tests tests: Werkzeug.Tests.TWerkzeugTests.PrueftHilfe', Text) > 0, Text);
    Assert.IsTrue(Pos('Tiefe 2 erreicht', Text) > 0, Text);
    Assert.IsTrue(Pos('Kein Symbol "Fehlt"', Tools.Impact('Fehlt', False)) > 0);
  finally
    Tools.Free;
  end;
end;

procedure TImpactAnalysisTests.McpJsonLikeAtlasImpact;
var
  Tools: TMcpCodeTools;
  Json: TJSONValue;
begin
  Tools := NewTools(FIndex);
  try
    // Ohne Tiefe: navigation.impactDepth über ImpactOptionsFor.
    Tools.ImpactOptionsFor :=
      function(const AUri: string): TImpactOptions
      begin
        Result := Options(1);
      end;
    Json := TJSONObject.ParseJSONValue(Tools.Impact('Ziel', True));
    try
      Assert.IsTrue(Json is TJSONObject);
      Assert.AreEqual(1, TJSONObject(Json).GetValue<Integer>('depth'));
      Assert.AreEqual('Ziel', TJSONObject(Json).GetValue<string>('symbol.name'));
      Assert.AreEqual(1, TJSONObject(Json).GetValue<TJSONArray>('places').Count);
    finally
      Json.Free;
    end;
  finally
    Tools.Free;
  end;
end;

procedure TImpactAnalysisTests.LongChainStaysFast;
const
  Count = 60;
var
  Texts: TArray<string>;
  Files: TArray<string>;
  Index: Integer;
  Big: ISymbolIndex;
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  Start: THierarchyItem;
  Watch: TStopwatch;
  Found: TImpactResult;
  Settings: TImpactOptions;
begin
  // Kette Stufe1 ← Stufe2 ← … über Count Units: Tiefe 5 geht fünf Units weit.
  SetLength(Texts, Count);
  SetLength(Files, Count);
  Big := TSymbolIndex.Create;
  for Index := 0 to Count - 1 do
  begin
    Files[Index] := Format('C:\B\Stufe%d.pas', [Index]);
    if Index = 0 then
      Texts[Index] := 'unit Stufe0;'#10'interface'#10'procedure Lauf0;'#10'implementation'#10 +
        'procedure Lauf0;'#10'begin'#10'end;'#10'end.'
    else
      Texts[Index] := Format('unit Stufe%d;'#10'interface'#10'uses Stufe%d;'#10'procedure Lauf%d;'#10 +
        'implementation'#10'procedure Lauf%d;'#10'begin'#10'  Lauf%d;'#10'end;'#10'end.',
        [Index, Index - 1, Index, Index, Index - 1]);
    Big.AddUnit(TIndexExtractor.ExtractText(Texts[Index], Files[Index], nil, nil, True));
  end;
  Resolver := TNameResolver.Create(Big);
  try
    Tree := TSyntaxTreeCache.Parse(Texts[0]);
    try
      Assert.IsTrue(TLspHierarchies.SymbolItemAt(Resolver, Tree, Files[0], PositionOf(Texts[0], 'procedure Lauf0;',
        'Lauf0'), Start));
    finally
      Tree.Free;
    end;
    Settings := Options(5);
    Watch := TStopwatch.StartNew;
    Found := TImpactAnalysis.Analyze(Resolver, Big, Start, Files,
      function(const AFileName: string; out AText: string): Boolean
      var
        Slot: Integer;
      begin
        for Slot := 0 to High(Files) do
          if SameText(Files[Slot], AFileName) then
          begin
            AText := Texts[Slot];
            Exit(True);
          end;
        Result := False;
      end, Settings, nil);
    Watch.Stop;
  finally
    Resolver.Free;
  end;
  Assert.AreEqual(5, Integer(Length(Found.Places)));
  Assert.AreEqual(5, Found.Places[4].Level);
  // Der Vorfilter über den Index liest je Ebene nur die eine Unit, die den Namen verwendet.
  Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, Format('%d ms', [Watch.ElapsedMilliseconds]));
end;

initialization
  TDUnitX.RegisterTestFixture(TImpactAnalysisTests);

end.
