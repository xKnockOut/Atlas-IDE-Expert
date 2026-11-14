unit Atlas.Common.Lsp.SyntaxDiagnostics.Tests;

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  System.JSON,
  DUnitX.TestFramework,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract;

type
  /// <summary>Transport, der geschriebene Nachrichten sammelt.</summary>
  TCapturingTransport = class(TInterfacedObject, IJsonRpcTransport)
  private
    FMessages: TObjectList<TJSONObject>;
    FWritten: TEvent;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadMessage: TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
    /// <summary>Wartet, bis mindestens ACount Nachrichten geschrieben sind.</summary>
    function WaitForCount(ACount: Integer; ATimeoutMs: Cardinal): Boolean;
    function Count: Integer;
    /// <summary>Kopie der Nachricht. Der Aufrufer gibt sie frei.</summary>
    function MessageAt(AIndex: Integer): TJSONObject;
  end;

  [TestFixture]
  TLspSyntaxDiagnosticsTests = class
  private
    FStore: IDocumentStore;
    FCapture: TCapturingTransport;
    FTransport: IJsonRpcTransport;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PublishesSyntaxErrorsOnOpen;
    [Test]
    procedure PublishesEmptyListForValidCode;
    [Test]
    procedure RepublishesAfterChange;
    [Test]
    procedure ClearsDiagnosticsOnClose;
    [Test]
    procedure PublishesWithin200MsAfterLastChange;
    [Test]
    procedure RefreshLaterBundlesCalls;
    [Test]
    procedure BuildsParamsForSnapshot;
    [Test]
    procedure AddsInactiveRangesAsUnnecessaryHints;
    [Test]
    procedure FindsInactiveRanges;
    [Test]
    procedure InactiveRegionsNameTheirCondition;
    [Test]
    procedure InactiveHintNamesConditionAndTarget;
    /// <summary>#860: Symbole aus {$I} wählen die Zweige; Abblenden und Include-Befunde kommen aus dem Lauf des
    /// gemeinsamen Baums.</summary>
    [Test]
    procedure ComputeReadsIncludeDefines;
    [Test]
    procedure AddsRuleFindingsWithCode;
    [Test]
    procedure RuleOffInSettingsAddsNothing;
    [Test]
    procedure BaselineHidesKnownRuleFindings;
    [Test]
    procedure MapsRuleSeverityAndConfidence;
    [Test]
    procedure DataCarriesGroupCategoryAndFixTitle;
    [Test]
    procedure RelatedPlacesBecomeRelatedInformation;
    [Test]
    procedure DataSkipsAlternativeFixesAndUnknownRules;
    [Test]
    procedure AddsCompilerMessagesToOpenDocuments;
    [Test]
    procedure PublishesCompilerMessagesForClosedFiles;
    /// <summary>#621: ungenutzte uses mit Tag Unnecessary und data.uses, behaltene ohne Tag; nichts bei
    /// Syntaxfehlern.</summary>
    [Test]
    procedure ReportsUnusedUsesUnlessSyntaxErrors;
    /// <summary>#1135: Das Abblenden folgt der Regel unused-uses: aus mit "off", "exclude" und lsp-ignore; ein
    /// lsp-ignore für die im Editor schweigende Regel ist kein unused-suppression.</summary>
    [Test]
    procedure UnusedUsesFollowRule;
    [Test]
    procedure OnlyImplementationFollowsRule;
  end;

implementation

uses
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Lsp.InactiveRegions,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.TreeCache,
  System.Classes,
  System.Diagnostics,
  System.StrUtils,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.DeadCode,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.DiagnosticItems;

function CompilerMessage(ALine, AColumn: Integer; ASeverity: TCompilerSeverity): TCompilerMessage;
begin
  Result := Default(TCompilerMessage);
  Result.FileName := 'C:\Projekt\A.pas';
  Result.Line := ALine;
  Result.Column := AColumn;
  Result.Severity := ASeverity;
  Result.Code := 'E2003';
  Result.Text := 'Undeklarierter Bezeichner: ''A''';
end;

const
  cUri = 'file:///c%3A/Projekt/A.pas';
  cValidCode = 'program P;'#13#10'begin'#13#10'  A := 1;'#13#10'end.';
  cBrokenCode = 'program P;'#13#10'begin'#13#10'  A := 1'#13#10'  B := 2;'#13#10'end.';

{ TCapturingTransport }

constructor TCapturingTransport.Create;
begin
  inherited Create;
  FMessages := TObjectList<TJSONObject>.Create(True);
  FWritten := TEvent.Create(nil, False, False, '');
end;

destructor TCapturingTransport.Destroy;
begin
  FWritten.Free;
  FMessages.Free;
  inherited;
end;

function TCapturingTransport.ReadMessage: TJSONObject;
begin
  raise EJsonRpcTransportClosed.Create('Keine Eingabe');
end;

procedure TCapturingTransport.WriteMessage(const AMessage: TJSONObject);
begin
  TMonitor.Enter(FMessages);
  try
    FMessages.Add(TJSONObject(AMessage.Clone));
  finally
    TMonitor.Exit(FMessages);
  end;
  FWritten.SetEvent;
end;

function TCapturingTransport.Count: Integer;
begin
  TMonitor.Enter(FMessages);
  try
    Result := FMessages.Count;
  finally
    TMonitor.Exit(FMessages);
  end;
end;

function TCapturingTransport.WaitForCount(ACount: Integer; ATimeoutMs: Cardinal): Boolean;
var
  mWatch: TStopwatch;
begin
  mWatch := TStopwatch.StartNew;
  while Count < ACount do
  begin
    if mWatch.ElapsedMilliseconds >= ATimeoutMs then
    begin
      Exit(False);
    end;
    FWritten.WaitFor(ATimeoutMs - Cardinal(mWatch.ElapsedMilliseconds));
  end;
  Result := True;
end;

function TCapturingTransport.MessageAt(AIndex: Integer): TJSONObject;
begin
  TMonitor.Enter(FMessages);
  try
    Result := TJSONObject(FMessages[AIndex].Clone);
  finally
    TMonitor.Exit(FMessages);
  end;
end;

{ TLspSyntaxDiagnosticsTests }

procedure TLspSyntaxDiagnosticsTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FCapture := TCapturingTransport.Create;
  FTransport := FCapture;
end;

procedure TLspSyntaxDiagnosticsTests.TearDown;
begin
  FTransport := nil;
  FCapture := nil;
  FStore := nil;
end;

procedure TLspSyntaxDiagnosticsTests.PublishesSyntaxErrorsOnOpen;
var
  mDiagnostics: TLspSyntaxDiagnostics;
  mMessage: TJSONObject;
  mItem: TJSONValue;
begin
  mDiagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, Default(TSyntaxDiagnosticsProviders), 0);
  try
    mDiagnostics.Attach;
    FStore.Open(cUri, 'objectpascal', 3, cBrokenCode);
    Assert.AreEqual(1, Integer(FCapture.Count));
    mMessage := FCapture.MessageAt(0);
    try
      Assert.AreEqual('textDocument/publishDiagnostics', mMessage.GetValue<string>('method'));
      Assert.AreEqual(cUri, mMessage.GetValue<string>('params.uri'));
      Assert.AreEqual(3, mMessage.GetValue<Integer>('params.version'));
      Assert.AreEqual(1, mMessage.GetValue<TJSONArray>('params.diagnostics').Count);
      mItem := mMessage.GetValue<TJSONArray>('params.diagnostics').Items[0];
      Assert.AreEqual(2, mItem.GetValue<Integer>('range.start.line'));
      Assert.AreEqual(8, mItem.GetValue<Integer>('range.start.character'));
      Assert.AreEqual(2, mItem.GetValue<Integer>('range.end.line'));
      Assert.AreEqual(8, mItem.GetValue<Integer>('range.end.character'));
      Assert.AreEqual(1, mItem.GetValue<Integer>('severity'));
      Assert.AreEqual('Atlas', mItem.GetValue<string>('source'));
      Assert.AreEqual(''';'' fehlt (wie E2066).', mItem.GetValue<string>('message'));
    finally
      mMessage.Free;
    end;
  finally
    mDiagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.PublishesEmptyListForValidCode;
var
  mDiagnostics: TLspSyntaxDiagnostics;
  mMessage: TJSONObject;
begin
  mDiagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, Default(TSyntaxDiagnosticsProviders), 0);
  try
    mDiagnostics.Attach;
    FStore.Open(cUri, 'objectpascal', 1, cValidCode);
    mMessage := FCapture.MessageAt(0);
    try
      Assert.AreEqual(0, mMessage.GetValue<TJSONArray>('params.diagnostics').Count);
    finally
      mMessage.Free;
    end;
  finally
    mDiagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.RepublishesAfterChange;
var
  mDiagnostics: TLspSyntaxDiagnostics;
  mMessage: TJSONObject;
begin
  mDiagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, Default(TSyntaxDiagnosticsProviders), 0);
  try
    mDiagnostics.Attach;
    FStore.Open(cUri, 'objectpascal', 1, cBrokenCode);
    FStore.Change(cUri, 2, [TTextChange.Full(cValidCode)]);
    Assert.AreEqual(2, Integer(FCapture.Count));
    mMessage := FCapture.MessageAt(1);
    try
      Assert.AreEqual(2, mMessage.GetValue<Integer>('params.version'));
      Assert.AreEqual(0, mMessage.GetValue<TJSONArray>('params.diagnostics').Count);
    finally
      mMessage.Free;
    end;
  finally
    mDiagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.ClearsDiagnosticsOnClose;
var
  mDiagnostics: TLspSyntaxDiagnostics;
  mMessage: TJSONObject;
begin
  mDiagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, Default(TSyntaxDiagnosticsProviders), 0);
  try
    mDiagnostics.Attach;
    FStore.Open(cUri, 'objectpascal', 1, cBrokenCode);
    FStore.Close(cUri);
    Assert.AreEqual(2, Integer(FCapture.Count));
    mMessage := FCapture.MessageAt(1);
    try
      Assert.AreEqual(cUri, mMessage.GetValue<string>('params.uri'));
      Assert.IsNull(mMessage.GetValue<TJSONObject>('params').GetValue('version'));
      Assert.AreEqual(0, mMessage.GetValue<TJSONArray>('params.diagnostics').Count);
    finally
      mMessage.Free;
    end;
  finally
    mDiagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.RefreshLaterBundlesCalls;
var
  mDiagnostics: TLspSyntaxDiagnostics;
  mCalls: Integer;
  mIndex: Integer;
begin
  // Jedes Projekt einer Gruppe meldet seine Indexstufen; neu geprüft wird einmal (#647).
  mCalls := 0;
  mDiagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, Default(TSyntaxDiagnosticsProviders));
  try
    mDiagnostics.PullMode := True;
    mDiagnostics.OnPullChanged :=
      procedure
      begin
        TInterlocked.Increment(mCalls);
      end;
    for mIndex := 1 to 5 do
    begin
      mDiagnostics.RefreshLater;
    end;
    Assert.AreEqual(0, TInterlocked.CompareExchange(mCalls, 0, 0), 'erst nach der Pause');
    Sleep(TLspSyntaxDiagnostics.cRefreshDelayMs + 500);
    Assert.AreEqual(1, TInterlocked.CompareExchange(mCalls, 0, 0));
  finally
    mDiagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.PublishesWithin200MsAfterLastChange;
var
  mDiagnostics: TLspSyntaxDiagnostics;
  mWatch: TStopwatch;
  mVersion: Integer;
  mMessage: TJSONObject;
begin
  mDiagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, Default(TSyntaxDiagnosticsProviders));
  try
    mDiagnostics.Attach;
    FStore.Open(cUri, 'objectpascal', 1, cValidCode);
    // Schnelles Tippen: Jede Änderung verschiebt die Auswertung.
    for mVersion := 2 to 6 do
    begin
      FStore.Change(cUri, mVersion, [TTextChange.Full(cBrokenCode)]);
      Sleep(20);
    end;
    mWatch := TStopwatch.StartNew;
    Assert.IsTrue(FCapture.WaitForCount(1, 1000), 'Keine Diagnose gemeldet');
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 200,
      Format('Diagnose nach %d ms', [mWatch.ElapsedMilliseconds]));
    Sleep(TLspSyntaxDiagnostics.cDefaultDelayMs * 2);
    Assert.AreEqual(1, Integer(FCapture.Count), 'Nur der letzte Stand wird ausgewertet');
    mMessage := FCapture.MessageAt(0);
    try
      Assert.AreEqual(6, mMessage.GetValue<Integer>('params.version'));
    finally
      mMessage.Free;
    end;
  finally
    mDiagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.BuildsParamsForSnapshot;
var
  mParams: TJSONObject;
  mDocument: ITextDocument;
begin
  mDocument := FStore.Open(cUri, 'objectpascal', 1, cBrokenCode);
  mParams := TLspSyntaxDiagnostics.BuildParams(mDocument);
  try
    Assert.AreEqual(1, mParams.GetValue<Integer>('version'));
    Assert.AreEqual(1, mParams.GetValue<TJSONArray>('diagnostics').Count);
  finally
    mParams.Free;
  end;
end;

function RulesWith(const AConfigJson: string): TRuleCheckContext;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Result := Default(TRuleCheckContext);
  Result.Rules := BuiltinRules;
  if AConfigJson = '' then
  begin
    Result.Settings := TServerSettings.Default;
  end
  else
  begin
    Result.Settings := TConfigurationParser.Parse(AConfigJson, mIssues);
  end;
  Result.RelativePath := 'A.pas';
end;

procedure TLspSyntaxDiagnosticsTests.AddsRuleFindingsWithCode;
var
  mParams: TJSONObject;
  mDocument: ITextDocument;
  mItem: TJSONObject;
begin
  mDocument := FStore.Open(cUri, 'objectpascal', 1, cValidCode + ' // ' + Char($202E));
  mParams := TLspSyntaxDiagnostics.BuildParams(mDocument, nil, '', RulesWith(''));
  try
    Assert.AreEqual(1, mParams.GetValue<TJSONArray>('diagnostics').Count);
    mItem := mParams.GetValue<TJSONArray>('diagnostics').Items[0] as TJSONObject;
    Assert.AreEqual('bidi-control', mItem.GetValue<string>('code'));
    Assert.AreEqual(1, mItem.GetValue<Integer>('severity'));
  finally
    mParams.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.RuleOffInSettingsAddsNothing;
var
  mParams: TJSONObject;
  mDocument: ITextDocument;
begin
  mDocument := FStore.Open(cUri, 'objectpascal', 1, cValidCode + ' // ' + Char($202E));
  mParams := TLspSyntaxDiagnostics.BuildParams(mDocument, nil, '', RulesWith('{ "rules": { "bidi-control": "off" } }'));
  try
    Assert.AreEqual(0, mParams.GetValue<TJSONArray>('diagnostics').Count);
  finally
    mParams.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.BaselineHidesKnownRuleFindings;
var
  mParams: TJSONObject;
  mDocument: ITextDocument;
  mRules: TRuleCheckContext;
  mSource: TBaselineSource;
begin
  mDocument := FStore.Open(cUri, 'objectpascal', 1, cValidCode + ' // ' + Char($202E));
  mRules := RulesWith('');
  mSource.Path := mRules.RelativePath;
  mSource.Text := mDocument.Text;
  mSource.Findings := TFileChecker.CheckText(mRules.Rules, mRules.Settings, mRules.RelativePath, mDocument.Text);
  mRules.Baseline := TRuleBaseline.FromJson(TRuleBaseline.Build([mSource]));
  mParams := TLspSyntaxDiagnostics.BuildParams(mDocument, nil, '', mRules);
  try
    Assert.AreEqual(0, mParams.GetValue<TJSONArray>('diagnostics').Count);
  finally
    mParams.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.MapsRuleSeverityAndConfidence;
var
  mFinding: TRuleFinding;
  mItem: TJSONObject;
begin
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'x';
  mFinding.Message := 'Meldung';
  mFinding.Severity := TRuleSeverity.Information;
  mFinding.Confidence := TRuleConfidence.Medium;
  mItem := TLspDiagnosticItems.FindingToJson(mFinding);
  try
    Assert.AreEqual(3, mItem.GetValue<Integer>('severity'));
    // Konfidenz als eigenes Feld, nicht im Meldungstext (#144).
    Assert.AreEqual('Meldung', mItem.GetValue<string>('message'));
    Assert.AreEqual('medium', mItem.GetValue<string>('data.confidence'));
    Assert.AreEqual(cRuleDocumentationBaseUri + mFinding.RuleId, mItem.GetValue<string>('codeDescription.href'));
  finally
    mItem.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.RelatedPlacesBecomeRelatedInformation;
var
  mFinding: TRuleFinding;
  mRelated: TRuleRelated;
  mItem: TJSONObject;
  mItems: TJSONArray;
begin
  // Unit-Zyklus (#896): jede Unit des Pfads mit ihrem uses-Eintrag als relatedInformation.
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'uses-cycle';
  mFinding.Message := 'Zirkuläre Unit-Referenz: C → A → C';
  mRelated.FileName := 'C:\P\A.pas';
  mRelated.Range := TTextRange.Create(3, 2, 3, 3);
  mRelated.Message := 'C';
  mFinding.Related := [mRelated];
  mItem := TLspDiagnosticItems.FindingToJson(mFinding);
  try
    mItems := mItem.GetValue('relatedInformation') as TJSONArray;
    Assert.AreEqual(1, mItems.Count);
    Assert.AreEqual('C', (mItems.Items[0] as TJSONObject).GetValue('message').Value);
    Assert.AreEqual(3, (mItems.Items[0] as TJSONObject).GetValue<Integer>('location.range.start.line'));
    Assert.AreEqual(2, (mItems.Items[0] as TJSONObject).GetValue<Integer>('location.range.start.character'));
    Assert.IsTrue(EndsText('A.pas', (mItems.Items[0] as TJSONObject).GetValue<string>('location.uri')));
  finally
    mItem.Free;
  end;
  // Ohne weitere Stellen kein Feld.
  mFinding.Related := nil;
  mItem := TLspDiagnosticItems.FindingToJson(mFinding);
  try
    Assert.IsNull(mItem.FindValue('relatedInformation'));
  finally
    mItem.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.DataCarriesGroupCategoryAndFixTitle;
var
  mFinding: TRuleFinding;
  mItem: TJSONObject;
begin
  // Fenster „Atlas-Prüfung“ und Befund-Hover (#909) brauchen Gruppe, Kategorie und Korrekturtitel.
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'empty-except';
  mFinding.Message := 'Leerer except-Block';
  mFinding.Severity := TRuleSeverity.Warning;
  mFinding.Fixes := [TRuleFix.Create('Ausnahme protokollieren', nil)];
  mItem := TLspDiagnosticItems.FindingToJson(mFinding);
  try
    Assert.AreEqual('exceptions', mItem.GetValue<string>('data.group'));
    Assert.AreEqual('code-smell', mItem.GetValue<string>('data.category'));
    Assert.AreEqual('Ausnahme protokollieren', mItem.GetValue<string>('data.fix'));
    // Ohne Compilercodes kein Feld.
    Assert.IsNull((mItem.GetValue('data') as TJSONObject).FindValue('compilerCodes'));
  finally
    mItem.Free;
  end;
  // Gruppe „Compiler vorab“ (#1024): Codes für den Abgleich mit dcc im Plugin.
  mFinding.RuleId := 'argument-count-mismatch';
  mFinding.Fixes := nil;
  mItem := TLspDiagnosticItems.FindingToJson(mFinding);
  try
    Assert.AreEqual('compiler', mItem.GetValue<string>('data.group'));
    Assert.AreEqual('["E2034","E2035"]', (mItem.GetValue('data') as TJSONObject).GetValue('compilerCodes').ToJSON);
    // Ohne Zusatz kein data.details.
    Assert.IsNull(mItem.FindValue('data.details'));
  finally
    mItem.Free;
  end;
  // Zusatz für den Befund-Hover (#1102).
  mFinding.Details := 'Durchsucht: 3 Dateien der Projektgruppe';
  mItem := TLspDiagnosticItems.FindingToJson(mFinding);
  try
    Assert.AreEqual('Durchsucht: 3 Dateien der Projektgruppe', mItem.GetValue<string>('data.details'));
  finally
    mItem.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.DataSkipsAlternativeFixesAndUnknownRules;
var
  mFinding: TRuleFinding;
  mFirst, mSecond: TRuleFix;
  mItem: TJSONObject;
  mData: TJSONObject;
begin
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'gibt-es-nicht';
  mFinding.Message := 'Meldung';
  mFirst := TRuleFix.Create('Variante A', nil);
  mFirst.Alternative := True;
  mSecond := TRuleFix.Create('Bevorzugt', nil);
  mFinding.Fixes := [mSecond, mFirst];
  mItem := TLspDiagnosticItems.FindingToJson(mFinding);
  try
    mData := mItem.GetValue('data') as TJSONObject;
    Assert.IsNull(mData.FindValue('group'));
    Assert.IsNull(mData.FindValue('category'));
    Assert.AreEqual('Bevorzugt', mData.GetValue<string>('fix'));
  finally
    mItem.Free;
  end;
  // Steht eine Alternative vorn, gibt es wie bei den Code-Aktionen keine bevorzugte Korrektur.
  mFinding.Fixes := [mFirst, mSecond];
  mItem := TLspDiagnosticItems.FindingToJson(mFinding);
  try
    mData := mItem.GetValue('data') as TJSONObject;
    Assert.IsNull(mData.FindValue('fix'));
  finally
    mItem.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.AddsInactiveRangesAsUnnecessaryHints;
var
  mParams: TJSONObject;
  mDocument: ITextDocument;
  mItem: TJSONValue;
  mInput: TSyntaxDiagnosticsInput;
begin
  mDocument := FStore.Open(cUri, 'objectpascal', 1, cValidCode);
  mInput := Default(TSyntaxDiagnosticsInput);
  mInput.Inactive := TLspInactiveRegions.FromRanges(
    [TTextRange.Create(TTextPosition.Create(1, 0), TTextPosition.Create(2, 0))]);
  mParams := TLspSyntaxDiagnostics.BuildParams(mDocument, mInput);
  try
    Assert.AreEqual(1, mParams.GetValue<TJSONArray>('diagnostics').Count);
    mItem := mParams.GetValue<TJSONArray>('diagnostics').Items[0];
    Assert.AreEqual(4, mItem.GetValue<Integer>('severity'));
    Assert.AreEqual(1, mItem.GetValue<Integer>('tags[0]'));
    Assert.AreEqual(1, mItem.GetValue<Integer>('range.start.line'));
  finally
    mParams.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.FindsInactiveRanges;
const
  cCode =
    'unit U;'#10 +
    'interface'#10 +
    '{$IFDEF WIN64}'#10 +
    'const A = 1;'#10 +
    '{$ELSE}'#10 +
    'const A = 2;'#10 +
    '{$ENDIF}'#10 +
    '{$IFDEF DEBUG}{$ENDIF}'#10 +
    'implementation'#10 +
    'end.';
var
  mRanges: TArray<TTextRange>;
begin
  mRanges := TLspInactiveRegions.Ranges(cCode, ['WIN64']);
  Assert.AreEqual(1, Integer(Length(mRanges)));
  Assert.AreEqual(4, mRanges[0].StartPos.Line);
  Assert.AreEqual(6, mRanges[0].EndPos.Line);
  mRanges := TLspInactiveRegions.Ranges(cCode, nil);
  Assert.AreEqual(1, Integer(Length(mRanges)));
  Assert.AreEqual(2, mRanges[0].StartPos.Line);
end;

procedure TLspSyntaxDiagnosticsTests.InactiveRegionsNameTheirCondition;
const
  cCode =
    'unit U;'#10 +
    '{$IFDEF WIN64}'#10 +
    'const A = 1;'#10 +
    '{$ELSE}'#10 +
    'const A = 2;'#10 +
    '{$ENDIF}'#10 +
    '{$IFDEF DEBUG}{$IFDEF WIN64} const B = 1; {$ENDIF}{$ENDIF}'#10 +
    'end.';
var
  mRegions: TArray<TLspInactiveRegion>;
begin
  mRegions := TLspInactiveRegions.Regions(cCode, ['WIN64']);
  Assert.AreEqual(2, Integer(Length(mRegions)));
  Assert.AreEqual('not WIN64', mRegions[0].Condition);
  Assert.AreEqual('DEBUG', mRegions[1].Condition);
  mRegions := TLspInactiveRegions.Regions(cCode, ['DEBUG']);
  Assert.AreEqual(2, Integer(Length(mRegions)));
  Assert.AreEqual('WIN64', mRegions[0].Condition);
  // Zweig innerhalb einer Zeile, verschachtelt (#615).
  Assert.AreEqual('DEBUG und WIN64', mRegions[1].Condition);
  Assert.AreEqual(6, mRegions[1].Range.StartPos.Line);
  Assert.AreEqual(6, mRegions[1].Range.EndPos.Line);
  Assert.AreEqual(28, mRegions[1].Range.StartPos.Character);
end;

procedure TLspSyntaxDiagnosticsTests.InactiveHintNamesConditionAndTarget;
const
  cCode = 'unit U;'#10'interface'#10'{$IFDEF WIN64}'#10'const A = 1;'#10'{$ENDIF}'#10'implementation'#10'end.';
var
  mDiagnostics: TLspSyntaxDiagnostics;
  mProviders: TSyntaxDiagnosticsProviders;
  mDocument: ITextDocument;
  mParams: TJSONObject;
  mItem: TJSONValue;
begin
  Assert.AreEqual(TLspDiagnosticItems.InactiveMessage, TLspDiagnosticItems.InactiveMessageOf('', 'Win32', 'Debug'));
  Assert.AreEqual('Inaktiv: Bedingung DEBUG nicht erfüllt', TLspDiagnosticItems.InactiveMessageOf('DEBUG', '', ''));
  Assert.AreEqual('Inaktiv: Bedingung DEBUG nicht erfüllt (Zielplattform Win64 · ?)',
    TLspDiagnosticItems.InactiveMessageOf('DEBUG', 'Win64', ''));
  mProviders := Default(TSyntaxDiagnosticsProviders);
  mProviders.Defines :=
    function(const AUri: string; out ADefines: TArray<string>): Boolean
    begin
      ADefines := ['WIN32'];
      Result := True;
    end;
  mProviders.BuildTarget :=
    function(const AUri: string; out APlatform, AConfig: string): Boolean
    begin
      APlatform := 'Win32';
      AConfig := 'Debug';
      Result := True;
    end;
  mDiagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, mProviders, 0);
  try
    mDocument := FStore.Open(cUri, 'objectpascal', 1, cCode);
    mParams := mDiagnostics.Compute(mDocument);
    try
      Assert.AreEqual(1, mParams.GetValue<TJSONArray>('diagnostics').Count);
      mItem := mParams.GetValue<TJSONArray>('diagnostics').Items[0];
      Assert.AreEqual(1, mItem.GetValue<TJSONArray>('tags').Count);
      Assert.AreEqual('Inaktiv: Bedingung WIN64 nicht erfüllt (Zielplattform Win32 · Debug)',
        mItem.GetValue<string>('message'));
      Assert.AreEqual('WIN64', mItem.GetValue<string>('data.inactive.condition'));
      Assert.AreEqual('Win32', mItem.GetValue<string>('data.inactive.platform'));
      Assert.AreEqual('Debug', mItem.GetValue<string>('data.inactive.config'));
    finally
      mParams.Free;
    end;
  finally
    mDiagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.ComputeReadsIncludeDefines;
const
  cCode = 'unit U;'#10'interface'#10'{$I defs.inc}'#10'{$IFDEF FOO} uses A; {$ENDIF}'#10 +
    '{$IFNDEF FOO} uses B; uses C; {$ENDIF}'#10'{$I fehlt.inc}'#10'implementation'#10'end.';
var
  mDiagnostics: TLspSyntaxDiagnostics;
  mProviders: TSyntaxDiagnosticsProviders;
  mDocument: ITextDocument;
  mParams: TJSONObject;
  mItem: TJSONValue;
  mMessages: string;
begin
  TSyntaxTreeCache.SetIncludeProvider(
    function(const AUri: string): TIncludeResolver
    begin
      Result :=
        function(const AName, AFromFile: string; out AFileName, AText: string): Boolean
        begin
          Result := SameText(AName, 'defs.inc');
          AFileName := 'C:\Projekt\defs.inc';
          AText := '{$DEFINE FOO}';
        end;
    end);
  mProviders := Default(TSyntaxDiagnosticsProviders);
  mProviders.Defines :=
    function(const AUri: string; out ADefines: TArray<string>): Boolean
    begin
      ADefines := ['WIN32'];
      Result := True;
    end;
  mDiagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, mProviders, 0);
  try
    mDocument := FStore.Open(cUri, 'objectpascal', 1, cCode);
    mParams := mDiagnostics.Compute(mDocument);
    try
      mMessages := '';
      for mItem in mParams.GetValue<TJSONArray>('diagnostics') do
      begin
        mMessages := mMessages + mItem.GetValue<string>('message') + '|';
      end;
      // Kein Syntaxfehler: Der {$IFNDEF FOO}-Zweig ist abgeblendet, fehlt.inc ein Hinweis.
      Assert.AreEqual('Inaktiv: Bedingung not FOO nicht erfüllt|Include-Datei "fehlt.inc" nicht gefunden|',
        mMessages);
    finally
      mParams.Free;
    end;
  finally
    mDiagnostics.Free;
    TSyntaxTreeCache.SetIncludeProvider(nil);
  end;
end;

procedure TLspSyntaxDiagnosticsTests.AddsCompilerMessagesToOpenDocuments;
var
  mDiagnostics: TLspSyntaxDiagnostics;
  mProviders: TSyntaxDiagnosticsProviders;
  mMessage: TJSONObject;
  mItems: TJSONArray;
begin
  mProviders := Default(TSyntaxDiagnosticsProviders);
  mProviders.CompilerMessages :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := [CompilerMessage(2, 2, TCompilerSeverity.Error), CompilerMessage(1, -1, TCompilerSeverity.Hint)];
    end;
  mDiagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, mProviders, 0);
  try
    mDiagnostics.Attach;
    FStore.Open(cUri, 'objectpascal', 1, cValidCode);
    mMessage := FCapture.MessageAt(0);
    try
      mItems := mMessage.GetValue<TJSONArray>('params.diagnostics');
      Assert.AreEqual(2, Integer(mItems.Count));
      // Spalte 2 in "  A := 1;": der Bezeichner A.
      Assert.AreEqual(2, mItems.Items[0].GetValue<Integer>('range.start.line'));
      Assert.AreEqual(2, mItems.Items[0].GetValue<Integer>('range.start.character'));
      Assert.AreEqual(3, mItems.Items[0].GetValue<Integer>('range.end.character'));
      Assert.AreEqual('E2003', mItems.Items[0].GetValue<string>('code'));
      Assert.AreEqual('dcc', mItems.Items[0].GetValue<string>('source'));
      Assert.AreEqual(1, mItems.Items[0].GetValue<Integer>('severity'));
      // Ohne Spalte die ganze Zeile "begin".
      Assert.AreEqual(0, mItems.Items[1].GetValue<Integer>('range.start.character'));
      Assert.AreEqual(5, mItems.Items[1].GetValue<Integer>('range.end.character'));
      Assert.AreEqual(4, mItems.Items[1].GetValue<Integer>('severity'));
    finally
      mMessage.Free;
    end;
  finally
    mDiagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.PublishesCompilerMessagesForClosedFiles;
var
  mDiagnostics: TLspSyntaxDiagnostics;
  mProviders: TSyntaxDiagnosticsProviders;
  mMessage: TJSONObject;
  mItems: TJSONArray;
begin
  mProviders := Default(TSyntaxDiagnosticsProviders);
  mProviders.CompilerMessages :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := [CompilerMessage(4, -1, TCompilerSeverity.Warning)];
    end;
  mDiagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, mProviders, 0);
  try
    mDiagnostics.Attach;
    mDiagnostics.RefreshFiles(['C:\Projekt\B.pas']);
    Assert.AreEqual(1, Integer(FCapture.Count));
    mMessage := FCapture.MessageAt(0);
    try
      Assert.IsTrue(SameText('C:\Projekt\B.pas', TDocumentUris.ToPath(mMessage.GetValue<string>('params.uri'))));
      mItems := mMessage.GetValue<TJSONArray>('params.diagnostics');
      Assert.AreEqual(1, Integer(mItems.Count));
      // Ohne Zeilentext: die ganze Zeile bis zum Anfang der nächsten.
      Assert.AreEqual(4, mItems.Items[0].GetValue<Integer>('range.start.line'));
      Assert.AreEqual(5, mItems.Items[0].GetValue<Integer>('range.end.line'));
      Assert.AreEqual(2, mItems.Items[0].GetValue<Integer>('severity'));
    finally
      mMessage.Free;
    end;
  finally
    mDiagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.ReportsUnusedUsesUnlessSyntaxErrors;
const
  cCode = 'unit U;'#10'interface'#10'uses'#10'  Vcl.Grids, Units.Reg;'#10'implementation'#10'end.';
var
  mDiagnostics: TLspSyntaxDiagnostics;
  mProviders: TSyntaxDiagnosticsProviders;
  mDocument: ITextDocument;
  mParams: TJSONObject;
  mItems: TJSONArray;
begin
  mProviders := Default(TSyntaxDiagnosticsProviders);
  mProviders.UsesContext :=
    function(const AUri: string; out AContext: TUsesContext): Boolean
    begin
      AContext := Default(TUsesContext);
      AContext.Info :=
        function(const AUnitName: string): TUsesUnitInfo
        begin
          Result := Default(TUsesUnitInfo);
          Result.Known := True;
          Result.Names := ['TStringGrid'];
          Result.HasInitialization := SameText(AUnitName, 'Units.Reg');
        end;
      Result := True;
    end;
  mDiagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, mProviders, 0);
  try
    mDocument := FStore.Open(cUri, 'objectpascal', 1, cCode);
    mParams := mDiagnostics.Compute(mDocument);
    try
      mItems := mParams.GetValue<TJSONArray>('diagnostics');
      Assert.AreEqual(2, Integer(mItems.Count));
      Assert.AreEqual('Aus Vcl.Grids wird nichts verwendet', mItems.Items[0].GetValue<string>('message'));
      Assert.AreEqual(1, mItems.Items[0].GetValue<TJSONArray>('tags').Count);
      Assert.AreEqual(4, mItems.Items[0].GetValue<Integer>('severity'));
      Assert.AreEqual('Vcl.Grids', mItems.Items[0].GetValue<string>('data.uses.unit'));
      Assert.AreEqual('unused', mItems.Items[0].GetValue<string>('data.uses.state'));
      Assert.AreEqual(3, mItems.Items[0].GetValue<Integer>('range.start.line'));
      Assert.AreEqual(2, mItems.Items[0].GetValue<Integer>('range.start.character'));
      Assert.AreEqual(11, mItems.Items[0].GetValue<Integer>('range.end.character'));
      Assert.AreEqual('Units.Reg wird wegen initialization nicht als ungenutzt gezeigt',
        mItems.Items[1].GetValue<string>('message'));
      Assert.IsNull(TJSONObject(mItems.Items[1]).GetValue('tags'));
      Assert.AreEqual('initialization', mItems.Items[1].GetValue<string>('data.uses.state'));
    finally
      mParams.Free;
    end;
    // Syntaxfehler: keine uses-Hinweise, nur der Fehler.
    mDocument := FStore.Change(cUri, 2, [TTextChange.Full(cCode.Replace('implementation', 'implementation'#10'procedure'))]);
    mParams := mDiagnostics.Compute(mDocument);
    try
      mItems := mParams.GetValue<TJSONArray>('diagnostics');
      Assert.IsTrue(mItems.Count > 0);
      Assert.AreEqual(0, Pos('uses', mParams.ToJSON), mParams.ToJSON);
    finally
      mParams.Free;
    end;
  finally
    mDiagnostics.Free;
  end;
end;

/// <summary>uses-Kontext, in dem jede Unit bekannt ist und nur TStringGrid anbietet.</summary>
function GridUses: TUsesContextProvider;
begin
  Result :=
    function(const AUri: string; out AContext: TUsesContext): Boolean
    begin
      AContext := Default(TUsesContext);
      AContext.Info :=
        function(const AUnitName: string): TUsesUnitInfo
        begin
          Result := Default(TUsesUnitInfo);
          Result.Known := True;
          Result.Names := ['TStringGrid'];
        end;
      Result := True;
    end;
end;

/// <summary>Regelkontext des Editors für A.pas mit den Einstellungen AConfig und der Regel unused-uses.</summary>
function EditorRules(const AConfig: string): TRuleContextProvider;
begin
  Result :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    var
      mIssues: TArray<TConfigurationIssue>;
    begin
      AContext := Default(TRuleCheckContext);
      AContext.Rules := TArray<IRule>.Create(TUnusedUsesRule.Create);
      AContext.Settings := TConfigurationParser.Parse(AConfig, mIssues);
      AContext.RelativePath := 'A.pas';
      AContext.FileName := 'C:\Projekt\A.pas';
      AContext.Live := True;
      Result := True;
    end;
end;

/// <summary>Meldungen der Diagnosen zu ACode mit den Einstellungen AConfig, durch | getrennt, mit Regelkennung.
/// </summary>
function UsesDiagnostics(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
  const ACode, AConfig: string): string;
var
  mProviders: TSyntaxDiagnosticsProviders;
  mDiagnostics: TLspSyntaxDiagnostics;
  mParams: TJSONObject;
  mItem: TJSONValue;
begin
  Result := '';
  mProviders := Default(TSyntaxDiagnosticsProviders);
  mProviders.UsesContext := GridUses();
  mProviders.Rules := EditorRules(AConfig);
  mDiagnostics := TLspSyntaxDiagnostics.Create(AStore, ATransport, mProviders, 0);
  try
    mParams := mDiagnostics.Compute(AStore.Open(cUri, 'objectpascal', 1, ACode));
    try
      for mItem in mParams.GetValue('diagnostics') as TJSONArray do
      begin
        Result := Result + mItem.GetValue<string>('message') + '|';
        if TJSONObject(mItem).GetValue('code') <> nil then
        begin
          Result := Result + mItem.GetValue<string>('code') + '|';
        end;
      end;
    finally
      mParams.Free;
    end;
    AStore.Close(cUri);
  finally
    mDiagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.UnusedUsesFollowRule;
const
  cCode = 'unit A;'#10'interface'#10'uses'#10'  Vcl.Grids;'#10'implementation'#10'end.';
  cIgnored = 'unit A;'#10'interface'#10'uses'#10'  // lsp-ignore: unused-uses'#10'  Vcl.Grids;'#10 +
    'implementation'#10'end.';
begin
  Assert.AreEqual('Aus Vcl.Grids wird nichts verwendet|', UsesDiagnostics(FStore, FTransport, cCode, '{}'));
  Assert.AreEqual('', UsesDiagnostics(FStore, FTransport, cCode, '{"rules": {"unused-uses": "off"}}'));
  Assert.AreEqual('', UsesDiagnostics(FStore, FTransport, cCode, '{"rules": {"group:style": "off"}}'));
  Assert.AreEqual('', UsesDiagnostics(FStore, FTransport, cCode,
    '{"rules": {"unused-uses": {"severity": "hint", "exclude": ["A"]}}}'));
  Assert.AreEqual('', UsesDiagnostics(FStore, FTransport, cCode, '{"exclude": ["A.pas"]}'));
  Assert.AreEqual('', UsesDiagnostics(FStore, FTransport, cIgnored, '{}'));
end;

procedure TLspSyntaxDiagnosticsTests.OnlyImplementationFollowsRule;
const
  cCode = 'unit A;'#10'interface'#10'uses'#10'  Vcl.Grids;'#10'implementation'#10'var'#10'  G: TStringGrid;'#10'end.';
  cIgnored = 'unit A;'#10'interface'#10'uses'#10'  // lsp-ignore: uses-only-in-implementation'#10'  Vcl.Grids;'#10 +
    'implementation'#10'var'#10'  G: TStringGrid;'#10'end.';
begin
  // Der Hinweis ist die Darstellung von uses-only-in-implementation (#1136), unabhängig von unused-uses.
  Assert.AreEqual('Vcl.Grids wird nur in der implementation gebraucht|', UsesDiagnostics(FStore, FTransport, cCode,
    '{}'));
  Assert.AreEqual('Vcl.Grids wird nur in der implementation gebraucht|', UsesDiagnostics(FStore, FTransport, cCode,
    '{"rules": {"unused-uses": "off"}}'));
  Assert.AreEqual('', UsesDiagnostics(FStore, FTransport, cCode, '{"rules": {"uses-only-in-implementation": "off"}}'));
  Assert.AreEqual('', UsesDiagnostics(FStore, FTransport, cCode,
    '{"rules": {"uses-only-in-implementation": {"severity": "hint", "exclude": ["A"]}}}'));
  Assert.AreEqual('', UsesDiagnostics(FStore, FTransport, cIgnored, '{}'));
  // Das lsp-ignore der einen Regel verbirgt nicht den Hinweis der anderen.
  Assert.AreEqual('Vcl.Grids wird nur in der implementation gebraucht|', UsesDiagnostics(FStore, FTransport,
    cIgnored.Replace('uses-only-in-implementation', 'unused-uses'), '{}'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSyntaxDiagnosticsTests);

end.
