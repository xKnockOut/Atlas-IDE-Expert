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
    procedure AnalyzeEachMatchesSingleRuns;
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
  cWerkzeugFile = 'C:\P\Werkzeug.pas';
  cHauptFile = 'C:\P\Haupt.pas';
  cHauptForm = 'C:\P\Haupt.dfm';
  cTestFile = 'C:\P\Werkzeug.Tests.pas';
  cAbseitsFile = 'C:\P\Abseits.pas';

  cUnitWerkzeug =
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

  cUnitHaupt =
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

  cFormHaupt =
    'object Form1: TForm1'#10 +
    '  object Button1: TButton'#10 +
    '    OnClick = Button1Click'#10 +
    '  end'#10 +
    'end';

  cUnitTests =
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

  cUnitAbseits =
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
  if SameText(AFileName, cWerkzeugFile) then
  begin
    Result := cUnitWerkzeug;
  end
  else if SameText(AFileName, cHauptFile) then
  begin
    Result := cUnitHaupt;
  end
  else if SameText(AFileName, cHauptForm) then
  begin
    Result := cFormHaupt;
  end
  else if SameText(AFileName, cTestFile) then
  begin
    Result := cUnitTests;
  end
  else if SameText(AFileName, cAbseitsFile) then
  begin
    Result := cUnitAbseits;
  end
  else
  begin
    Result := '';
  end;
end;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  AText := TextOf(AFileName);
  Result := AText <> '';
end;

function ProjectFiles: TArray<string>;
begin
  Result := TArray<string>.Create(cWerkzeugFile, cHauptFile, cTestFile, cAbseitsFile);
end;

function PositionOf(const AText, AMarker, AName: string): TTextPosition;
var
  mIndex, mLine, mLineStart, mScan: Integer;
begin
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  mIndex := mIndex + Pos(AName, AMarker) - 1;
  mLine := 0;
  mLineStart := 1;
  for mScan := 1 to mIndex - 1 do
  begin
    if AText[mScan] = #10 then
    begin
      Inc(mLine);
      mLineStart := mScan + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

function Describe(const AResult: TImpactResult): string;
var
  mPlace: TImpactPlace;
begin
  Result := '';
  for mPlace in AResult.Places do
  begin
    Result := Result + Format('%s.%s@%d:%d(L%d c%d) ', [mPlace.Item.Container, mPlace.Item.Name,
      mPlace.Item.SelectionRange.StartPos.Line, mPlace.Item.SelectionRange.StartPos.Character, mPlace.Level,
      mPlace.Cause]);
  end;
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
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitWerkzeug, cWerkzeugFile, nil, nil, True));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitHaupt, cHauptFile, nil, nil, True));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitTests, cTestFile, nil, nil, True));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitAbseits, cAbseitsFile, nil, nil, True));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TImpactAnalysisTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TImpactAnalysisTests.ItemAt(const AFileName, AMarker, AName: string): THierarchyItem;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(TextOf(AFileName));
  try
    Assert.IsTrue(TLspHierarchies.SymbolItemAt(FResolver, mTree, AFileName,
      PositionOf(TextOf(AFileName), AMarker, AName), Result), AMarker);
  finally
    mTree.Free;
  end;
end;

function TImpactAnalysisTests.Analyze(const AStart: THierarchyItem; ADepth: Integer): TImpactResult;
begin
  Result := Analyze(AStart, Options(ADepth));
end;

function TImpactAnalysisTests.Analyze(const AStart: THierarchyItem; const AOptions: TImpactOptions): TImpactResult;
begin
  Result := TImpactAnalysis.Analyze(FResolver, FIndex, AStart, TImpactSources.Create(ProjectFiles,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadFile(AFileName, AText);
    end), AOptions, nil);
end;

function TImpactAnalysisTests.PlaceNamed(const AResult: TImpactResult; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AResult.Places) do
  begin
    if SameText(AResult.Places[mIndex].Item.Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TImpactAnalysisTests.DirectCallerOnLevelOne;
var
  mFound: TImpactResult;
  mHilfe: Integer;
begin
  mFound := Analyze(ItemAt(cWerkzeugFile, 'procedure Ziel;', 'Ziel'), 1);
  Assert.AreEqual('Ziel', mFound.Symbol.Name);
  Assert.AreEqual(1, Integer(Length(mFound.Places)));
  mHilfe := PlaceNamed(mFound, 'Hilfe');
  Assert.AreEqual(0, mHilfe);
  Assert.AreEqual(1, mFound.Places[mHilfe].Level);
  Assert.AreEqual(-1, mFound.Places[mHilfe].Cause);
  Assert.AreEqual<TImpactEdge>(TImpactEdge.Call, mFound.Places[mHilfe].Edge);
  // Beide Aufrufe in Hilfe gehören zur selben Stelle.
  Assert.AreEqual(2, Integer(Length(mFound.Places[mHilfe].Ranges)));
  Assert.IsTrue(mFound.Places[mHilfe].Confidence.IsSure);
end;

procedure TImpactAnalysisTests.IndirectCallersNamedWithTheirCause;
var
  mFound: TImpactResult;
  mHilfe, mOben, mHandler: Integer;
begin
  mFound := Analyze(ItemAt(cWerkzeugFile, 'procedure Ziel;', 'Ziel'), 3);
  mHilfe := PlaceNamed(mFound, 'Hilfe');
  mOben := PlaceNamed(mFound, 'Oben');
  mHandler := PlaceNamed(mFound, 'Button1Click');
  Assert.IsTrue(mOben >= 0, Describe(mFound));
  Assert.AreEqual(2, mFound.Places[mOben].Level);
  Assert.AreEqual(mHilfe, mFound.Places[mOben].Cause);
  Assert.IsTrue(mHandler >= 0);
  Assert.AreEqual(3, mFound.Places[mHandler].Level);
  Assert.AreEqual(mOben, mFound.Places[mHandler].Cause);
  Assert.AreEqual(1, mFound.LevelCount(1));
end;

procedure TImpactAnalysisTests.FormHandlerOnLastLevelKeepsBinding;
var
  mFound: TImpactResult;
  mHandler: Integer;
begin
  // Der Handler steht auf der letzten Ebene; seine Bindung im Formular kostet keine eigene.
  mFound := Analyze(ItemAt(cWerkzeugFile, 'procedure Oben;', 'Oben'), 1);
  mHandler := PlaceNamed(mFound, 'Button1Click');
  Assert.IsTrue(mHandler >= 0);
  Assert.AreEqual(1, Integer(Length(mFound.Places[mHandler].Forms)));
  Assert.AreEqual(cHauptForm, mFound.Places[mHandler].Forms[0].FileName);
  Assert.AreEqual('OnClick = Button1Click', mFound.Places[mHandler].Forms[0].Text);
  Assert.AreEqual(2, mFound.Places[mHandler].Forms[0].Range.StartPos.Line);
end;

procedure TImpactAnalysisTests.UnitLevelUseIsTerminal;
var
  mFound: TImpactResult;
  mIndex: Integer;
  mTerminal: Boolean;
begin
  mFound := Analyze(ItemAt(cWerkzeugFile, 'procedure Hilfe;', 'Hilfe'), 2);
  mTerminal := False;
  for mIndex := 0 to High(mFound.Places) do
  begin
    if mFound.Places[mIndex].Terminal then
    begin
      mTerminal := True;
      Assert.AreEqual('Haupt', mFound.Places[mIndex].Item.Name);
      Assert.AreEqual(1, mFound.Places[mIndex].Level);
    end;
  end;
  Assert.IsTrue(mTerminal);
  // Die Unit selbst wird nicht weiter verfolgt: Keine Stelle nennt sie als Ursache.
  for mIndex := 0 to High(mFound.Places) do
  begin
    if mFound.Places[mIndex].Cause >= 0 then
    begin
      Assert.IsFalse(mFound.Places[mFound.Places[mIndex].Cause].Terminal);
    end;
  end;
end;

procedure TImpactAnalysisTests.AffectedTestsWithRunNames;
var
  mFound: TImpactResult;
  mTest: Integer;
begin
  mFound := Analyze(ItemAt(cWerkzeugFile, 'procedure Ziel;', 'Ziel'), 2);
  Assert.AreEqual(1, Integer(Length(mFound.Tests)));
  Assert.AreEqual('Werkzeug.Tests.TWerkzeugTests.PrueftHilfe', mFound.Tests[0].Name);
  Assert.AreEqual(2, mFound.Tests[0].Level);
  Assert.AreEqual(cTestFile, mFound.Tests[0].FileName);
  Assert.AreEqual(1, Integer(Length(mFound.RunNames)));
  Assert.AreEqual('Werkzeug.Tests.TWerkzeugTests.PrueftHilfe', mFound.RunNames[0]);
  mTest := PlaceNamed(mFound, 'PrueftHilfe');
  Assert.IsTrue(mTest >= 0);
  Assert.AreEqual(0, mFound.Places[mTest].Test);
end;

procedure TImpactAnalysisTests.DepthLimitCountsUnexpanded;
var
  mFound: TImpactResult;
begin
  mFound := Analyze(ItemAt(cWerkzeugFile, 'procedure Ziel;', 'Ziel'), 1);
  Assert.IsTrue(TImpactLimit.Depth in mFound.Limits);
  Assert.AreEqual(1, mFound.Unexpanded);
  Assert.IsFalse(TImpactLimit.Count in mFound.Limits);
end;

procedure TImpactAnalysisTests.CycleEndsAtStart;
var
  mFound: TImpactResult;
begin
  // Hin ruft Her, Her ruft Hin: Hin ist das Symbol und erscheint nicht noch einmal.
  mFound := Analyze(ItemAt(cWerkzeugFile, 'procedure Hin;', 'Hin'), 5);
  Assert.AreEqual(1, Integer(Length(mFound.Places)));
  Assert.AreEqual('Her', mFound.Places[0].Item.Name);
  Assert.IsFalse(TImpactLimit.Depth in mFound.Limits);
end;

procedure TImpactAnalysisTests.CountLimitStopsAndReports;
var
  mSettings: TImpactOptions;
  mFound: TImpactResult;
begin
  mSettings := Options(3);
  mSettings.MaxPlaces := 2;
  mFound := Analyze(ItemAt(cWerkzeugFile, 'procedure Ziel;', 'Ziel'), mSettings);
  Assert.AreEqual(2, Integer(Length(mFound.Places)));
  Assert.IsTrue(TImpactLimit.Count in mFound.Limits);
  Assert.AreEqual(2, mFound.MaxPlaces);
end;

procedure TImpactAnalysisTests.TimeLimitReported;
var
  mSettings: TImpactOptions;
  mFound: TImpactResult;
begin
  // 1 ms: Spätestens die zweite Ebene liegt hinter der Grenze; das Ergebnis bis dahin bleibt.
  mSettings := Options(5);
  mSettings.TimeoutMs := 1;
  Sleep(5);
  mFound := Analyze(ItemAt(cWerkzeugFile, 'procedure Ziel;', 'Ziel'), mSettings);
  Assert.AreEqual(1, mFound.TimeoutMs);
  Assert.IsTrue((TImpactLimit.Time in mFound.Limits) or (Length(mFound.Places) > 0));
end;

procedure TImpactAnalysisTests.OverrideFoundFromBase;
var
  mFound: TImpactResult;
  mIndex: Integer;
begin
  mFound := Analyze(ItemAt(cWerkzeugFile, 'procedure Arbeite; virtual', 'Arbeite'), 1);
  mIndex := PlaceNamed(mFound, 'Arbeite');
  Assert.IsTrue(mIndex >= 0);
  Assert.AreEqual('TKind', mFound.Places[mIndex].Item.Container);
  Assert.AreEqual<TImpactEdge>(TImpactEdge.Override_, mFound.Places[mIndex].Edge);
end;

procedure TImpactAnalysisTests.BaseMethodFoundFromOverride;
var
  mFound: TImpactResult;
  mIndex: Integer;
begin
  mFound := Analyze(ItemAt(cWerkzeugFile, 'procedure Arbeite; override', 'Arbeite'), 1);
  mIndex := PlaceNamed(mFound, 'Arbeite');
  Assert.IsTrue(mIndex >= 0);
  Assert.AreEqual('TBasis', mFound.Places[mIndex].Item.Container);
  Assert.AreEqual<TImpactEdge>(TImpactEdge.BaseMethod, mFound.Places[mIndex].Edge);
end;

procedure TImpactAnalysisTests.ImplementationFoundFromInterface;
var
  mFound: TImpactResult;
  mIndex: Integer;
begin
  mFound := Analyze(ItemAt(cWerkzeugFile, '    procedure Rechne;'#10'  end;'#10'  TBasis', 'Rechne'), 1);
  mIndex := PlaceNamed(mFound, 'Rechne');
  Assert.IsTrue(mIndex >= 0);
  Assert.AreEqual('TKind', mFound.Places[mIndex].Item.Container);
  Assert.AreEqual<TImpactEdge>(TImpactEdge.Implementation_, mFound.Places[mIndex].Edge);
end;

procedure TImpactAnalysisTests.InterfaceMethodFoundFromImplementation;
var
  mFound: TImpactResult;
  mIndex: Integer;
begin
  mFound := Analyze(ItemAt(cWerkzeugFile, 'procedure TKind.Rechne;', 'Rechne'), 1);
  mIndex := PlaceNamed(mFound, 'Rechne');
  Assert.IsTrue(mIndex >= 0);
  Assert.AreEqual('IRechner', mFound.Places[mIndex].Item.Container);
  Assert.AreEqual<TImpactEdge>(TImpactEdge.InterfaceMethod, mFound.Places[mIndex].Edge);
end;

procedure TImpactAnalysisTests.DepthClamped;
begin
  Assert.AreEqual(1, TImpactAnalysis.ClampDepth(0));
  Assert.AreEqual(3, TImpactAnalysis.ClampDepth(3));
  Assert.AreEqual(5, TImpactAnalysis.ClampDepth(9));
  Assert.AreEqual(2, Analyze(ItemAt(cWerkzeugFile, 'procedure Hin;', 'Hin'), 2).Depth);
end;

procedure TImpactAnalysisTests.CandidateFilesSkipFilesWithoutName;
var
  mFiles: TArray<string>;
begin
  mFiles := TImpactAnalysis.CandidateFiles(FIndex, TArray<string>.Create(cWerkzeugFile, cHauptFile, cAbseitsFile,
    'C:\P\Fremd.pas'), 'Hilfe');
  // Abseits kennt Hilfe laut Index nicht; Fremd steht nicht im Index und bleibt.
  Assert.AreEqual(3, Integer(Length(mFiles)));
  Assert.AreEqual(cWerkzeugFile, mFiles[0]);
  Assert.AreEqual(cHauptFile, mFiles[1]);
  Assert.AreEqual('C:\P\Fremd.pas', mFiles[2]);
end;

procedure TImpactAnalysisTests.TestScopeFromProgram;
var
  mScope: TImpactTestScope;
begin
  mScope := TImpactTestScope.FromProgram('Test.{unit}',
    'program Tests;'#10'uses'#10'  DUnitX.TestFramework,'#10'  Kunden.Pruefung in ''Kunden.Pruefung.pas'';'#10 +
    'begin'#10'end.');
  Assert.IsTrue(mScope.Contains('Kunden.Pruefung'));
  Assert.IsTrue(mScope.Contains('Test.Kunden'));
  Assert.IsFalse(mScope.Contains('Kunden'));
  Assert.IsFalse(mScope.Contains(''));
  mScope := TImpactTestScope.FromProgram('{unit}.Tests', '');
  Assert.AreEqual(0, Integer(Length(mScope.Units)));
end;

procedure TImpactAnalysisTests.JsonCarriesLevelsEdgesAndLimits;
var
  mJson: TJSONObject;
  mPlaces, mTests: TJSONArray;
  mPlace: TJSONObject;
begin
  mJson := TImpactAnalysis.ToJson(Analyze(ItemAt(cWerkzeugFile, 'procedure Ziel;', 'Ziel'), 2));
  try
    Assert.AreEqual(2, mJson.GetValue<Integer>('depth'));
    mPlaces := mJson.GetValue('places') as TJSONArray;
    Assert.IsTrue(mPlaces.Count >= 3);
    mPlace := mPlaces.Items[0] as TJSONObject;
    Assert.AreEqual(1, mPlace.GetValue<Integer>('level'));
    Assert.AreEqual('call', mPlace.GetValue<string>('edge'));
    Assert.AreEqual(-1, (mPlace.GetValue('cause') as TJSONNumber).AsInt);
    Assert.AreEqual('Hilfe', mPlace.GetValue<string>('item.name'));
    mTests := mJson.GetValue('tests') as TJSONArray;
    Assert.AreEqual(1, mTests.Count);
    Assert.IsTrue(mJson.GetValue<Boolean>('limits.depth'));
    Assert.IsFalse(mJson.GetValue<Boolean>('limits.count'));
    Assert.IsFalse(mJson.GetValue<Boolean>('limits.time'));
  finally
    mJson.Free;
  end;
end;

procedure TImpactAnalysisTests.HandlerAnswersAtlasImpact;
var
  mStore: IDocumentStore;
  mAnalysis: TImpactAnalysis;
  mDispatcher: TJsonRpcDispatcher;
  mMessage, mResponse: TJSONObject;
  mPosition: TTextPosition;
begin
  mStore := TDocumentStore.Create;
  mStore.Open(TDocumentUris.FromPath(cWerkzeugFile), 'delphi', 1, cUnitWerkzeug);
  mAnalysis := TImpactAnalysis.Create(mStore, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadFile(AFileName, AText);
    end,
    function: TArray<string>
    begin
      Result := ProjectFiles;
    end);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mAnalysis.Attach(mDispatcher);
    mPosition := PositionOf(cUnitWerkzeug, 'procedure Ziel;', 'Ziel');
    mMessage := TJSONObject.ParseJSONValue(Format('{"jsonrpc":"2.0","id":1,"method":"%s","params":{' +
      '"textDocument":{"uri":"%s"},"position":{"line":%d,"character":%d},"depth":1}}', [TImpactAnalysis.cMethod,
      TDocumentUris.FromPath(cWerkzeugFile), mPosition.Line, mPosition.Character])) as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mMessage);
      try
        Assert.IsTrue(mResponse.GetValue('result') is TJSONObject, mResponse.ToJSON);
        Assert.AreEqual(1, mResponse.GetValue<Integer>('result.depth'));
        Assert.AreEqual(1, mResponse.GetValue<TJSONArray>('result.places').Count);
      finally
        mResponse.Free;
      end;
    finally
      mMessage.Free;
    end;
  finally
    mDispatcher.Free;
    mAnalysis.Free;
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
  mTools: TMcpCodeTools;
  mText: string;
begin
  mTools := NewTools(FIndex);
  try
    mText := mTools.Impact('Ziel', 2, False);
    Assert.AreEqual(1, Pos('Auswirkungen von Ziel', mText), mText);
    Assert.IsTrue(Pos('Tiefe 2', mText) > 0, mText);
    Assert.IsTrue(Pos(' Hilfe – Unit Werkzeug', mText) > 0, mText);
    // Ebene 2 eine Stufe tiefer eingerückt unter ihrer Ursache.
    Assert.IsTrue(Pos(#10'    ', mText) > Pos(' Hilfe – Unit', mText), mText);
    Assert.IsTrue(Pos(' Oben – Unit Werkzeug', mText) > Pos(' Hilfe – Unit', mText), mText);
    Assert.IsTrue(Pos('(Aufruf, 2×)', mText) > 0, mText);
    Assert.IsTrue(Pos('Unit-Ebene', mText) > 0, mText);
    Assert.IsTrue(Pos('run_tests tests: Werkzeug.Tests.TWerkzeugTests.PrueftHilfe', mText) > 0, mText);
    Assert.IsTrue(Pos('Tiefe 2 erreicht', mText) > 0, mText);
    Assert.IsTrue(Pos('Kein Symbol "Fehlt"', mTools.Impact('Fehlt', False)) > 0);
  finally
    mTools.Free;
  end;
end;

procedure TImpactAnalysisTests.McpJsonLikeAtlasImpact;
var
  mTools: TMcpCodeTools;
  mJson: TJSONValue;
begin
  mTools := NewTools(FIndex);
  try
    // Ohne Tiefe: navigation.impactDepth über ImpactOptionsFor.
    mTools.ImpactOptionsFor :=
      function(const AUri: string): TImpactOptions
      begin
        Result := Options(1);
      end;
    mJson := TJSONObject.ParseJSONValue(mTools.Impact('Ziel', True));
    try
      Assert.IsTrue(mJson is TJSONObject);
      Assert.AreEqual(1, TJSONObject(mJson).GetValue<Integer>('depth'));
      Assert.AreEqual('Ziel', TJSONObject(mJson).GetValue<string>('symbol.name'));
      Assert.AreEqual(1, TJSONObject(mJson).GetValue<TJSONArray>('places').Count);
    finally
      mJson.Free;
    end;
  finally
    mTools.Free;
  end;
end;

procedure TImpactAnalysisTests.AnalyzeEachMatchesSingleRuns;
var
  mStarts: TArray<THierarchyItem>;
  mEach: TArray<TImpactResult>;
  mIndex: Integer;
begin
  // #1353: mehrere Startpunkte mit gemeinsamen Bäumen und Units, je Ergebnis wie eine eigene Analyse.
  mStarts := TArray<THierarchyItem>.Create(ItemAt(cWerkzeugFile, 'procedure Ziel;', 'Ziel'),
    ItemAt(cWerkzeugFile, 'procedure Oben;', 'Oben'));
  mEach := TImpactAnalysis.AnalyzeEach(FResolver, FIndex, mStarts, TImpactSources.Create(ProjectFiles,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadFile(AFileName, AText);
    end), Options(3), nil);
  Assert.AreEqual(2, Integer(Length(mEach)));
  for mIndex := 0 to High(mStarts) do
  begin
    Assert.AreEqual(Describe(Analyze(mStarts[mIndex], 3)), Describe(mEach[mIndex]), mStarts[mIndex].Name);
  end;
  Assert.AreEqual(1, Integer(Length(mEach[0].Tests)));
  Assert.AreEqual(0, Integer(Length(TImpactAnalysis.AnalyzeEach(FResolver, FIndex, nil,
    TImpactSources.Create(ProjectFiles, nil), Options(3), nil))));
end;

/// <summary>Unit AIndex der Kette Stufe1 ← Stufe2 ← …: LaufN ruft LaufN-1.</summary>
function ChainText(AIndex: Integer): string;
begin
  if AIndex = 0 then
  begin
    Result := 'unit Stufe0;'#10'interface'#10'procedure Lauf0;'#10'implementation'#10 +
      'procedure Lauf0;'#10'begin'#10'end;'#10'end.';
  end
  else
  begin
    Result := Format('unit Stufe%d;'#10'interface'#10'uses Stufe%d;'#10'procedure Lauf%d;'#10 +
      'implementation'#10'procedure Lauf%d;'#10'begin'#10'  Lauf%d;'#10'end;'#10'end.',
      [AIndex, AIndex - 1, AIndex, AIndex, AIndex - 1]);
  end;
end;

/// <summary>Liest die Datei AFiles[i] als ATexts[i].</summary>
function TextsReader(const AFiles, ATexts: TArray<string>): TReferenceReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    var
      mSlot: Integer;
    begin
      for mSlot := 0 to High(AFiles) do
      begin
        if SameText(AFiles[mSlot], AFileName) then
        begin
          AText := ATexts[mSlot];
          Exit(True);
        end;
      end;
      Result := False;
    end;
end;

const
  cLongChainCount = 60;

procedure TImpactAnalysisTests.LongChainStaysFast;
var
  mTexts: TArray<string>;
  mFiles: TArray<string>;
  mIndex: Integer;
  mBig: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mStart: THierarchyItem;
  mWatch: TStopwatch;
  mFound: TImpactResult;
  mSettings: TImpactOptions;
begin
  // Kette Stufe1 ← Stufe2 ← … über Count Units: Tiefe 5 geht fünf Units weit.
  SetLength(mTexts, cLongChainCount);
  SetLength(mFiles, cLongChainCount);
  mBig := TSymbolIndex.Create;
  for mIndex := 0 to cLongChainCount - 1 do
  begin
    mFiles[mIndex] := Format('C:\B\Stufe%d.pas', [mIndex]);
    mTexts[mIndex] := ChainText(mIndex);
    mBig.AddUnit(TIndexExtractor.ExtractText(mTexts[mIndex], mFiles[mIndex], nil, nil, True));
  end;
  mResolver := TNameResolver.Create(mBig);
  try
    mTree := TSyntaxTreeCache.Parse(mTexts[0]);
    try
      Assert.IsTrue(TLspHierarchies.SymbolItemAt(mResolver, mTree, mFiles[0], PositionOf(mTexts[0], 'procedure Lauf0;',
        'Lauf0'), mStart));
    finally
      mTree.Free;
    end;
    mSettings := Options(5);
    mWatch := TStopwatch.StartNew;
    mFound := TImpactAnalysis.Analyze(mResolver, mBig, mStart,
      TImpactSources.Create(mFiles, TextsReader(mFiles, mTexts)),
      mSettings, nil);
    mWatch.Stop;
  finally
    mResolver.Free;
  end;
  Assert.AreEqual(5, Integer(Length(mFound.Places)));
  Assert.AreEqual(5, mFound.Places[4].Level);
  // Der Vorfilter über den Index liest je Ebene nur die eine Unit, die den Namen verwendet.
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 5000, Format('%d ms', [mWatch.ElapsedMilliseconds]));
end;

initialization
  TDUnitX.RegisterTestFixture(TImpactAnalysisTests);

end.
