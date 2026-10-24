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
  Atlas.Common.Documents.Uris,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Lsp.SyntaxDiagnostics;

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
  Uri = 'file:///c%3A/Projekt/A.pas';
  ValidCode = 'program P;'#13#10'begin'#13#10'  A := 1;'#13#10'end.';
  BrokenCode = 'program P;'#13#10'begin'#13#10'  A := 1'#13#10'  B := 2;'#13#10'end.';

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
  Watch: TStopwatch;
begin
  Watch := TStopwatch.StartNew;
  while Count < ACount do
  begin
    if Watch.ElapsedMilliseconds >= ATimeoutMs then
      Exit(False);
    FWritten.WaitFor(ATimeoutMs - Cardinal(Watch.ElapsedMilliseconds));
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
  Diagnostics: TLspSyntaxDiagnostics;
  Message: TJSONObject;
  Item: TJSONValue;
begin
  Diagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, 0);
  try
    Diagnostics.Attach;
    FStore.Open(Uri, 'objectpascal', 3, BrokenCode);
    Assert.AreEqual(1, Integer(FCapture.Count));
    Message := FCapture.MessageAt(0);
    try
      Assert.AreEqual('textDocument/publishDiagnostics', Message.GetValue<string>('method'));
      Assert.AreEqual(Uri, Message.GetValue<string>('params.uri'));
      Assert.AreEqual(3, Message.GetValue<Integer>('params.version'));
      Assert.AreEqual(1, Message.GetValue<TJSONArray>('params.diagnostics').Count);
      Item := Message.GetValue<TJSONArray>('params.diagnostics').Items[0];
      Assert.AreEqual(2, Item.GetValue<Integer>('range.start.line'));
      Assert.AreEqual(8, Item.GetValue<Integer>('range.start.character'));
      Assert.AreEqual(2, Item.GetValue<Integer>('range.end.line'));
      Assert.AreEqual(8, Item.GetValue<Integer>('range.end.character'));
      Assert.AreEqual(1, Item.GetValue<Integer>('severity'));
      Assert.AreEqual('Atlas', Item.GetValue<string>('source'));
      Assert.AreEqual(''';'' fehlt (wie E2066).', Item.GetValue<string>('message'));
    finally
      Message.Free;
    end;
  finally
    Diagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.PublishesEmptyListForValidCode;
var
  Diagnostics: TLspSyntaxDiagnostics;
  Message: TJSONObject;
begin
  Diagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, 0);
  try
    Diagnostics.Attach;
    FStore.Open(Uri, 'objectpascal', 1, ValidCode);
    Message := FCapture.MessageAt(0);
    try
      Assert.AreEqual(0, Message.GetValue<TJSONArray>('params.diagnostics').Count);
    finally
      Message.Free;
    end;
  finally
    Diagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.RepublishesAfterChange;
var
  Diagnostics: TLspSyntaxDiagnostics;
  Message: TJSONObject;
begin
  Diagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, 0);
  try
    Diagnostics.Attach;
    FStore.Open(Uri, 'objectpascal', 1, BrokenCode);
    FStore.Change(Uri, 2, [TTextChange.Full(ValidCode)]);
    Assert.AreEqual(2, Integer(FCapture.Count));
    Message := FCapture.MessageAt(1);
    try
      Assert.AreEqual(2, Message.GetValue<Integer>('params.version'));
      Assert.AreEqual(0, Message.GetValue<TJSONArray>('params.diagnostics').Count);
    finally
      Message.Free;
    end;
  finally
    Diagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.ClearsDiagnosticsOnClose;
var
  Diagnostics: TLspSyntaxDiagnostics;
  Message: TJSONObject;
begin
  Diagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, 0);
  try
    Diagnostics.Attach;
    FStore.Open(Uri, 'objectpascal', 1, BrokenCode);
    FStore.Close(Uri);
    Assert.AreEqual(2, Integer(FCapture.Count));
    Message := FCapture.MessageAt(1);
    try
      Assert.AreEqual(Uri, Message.GetValue<string>('params.uri'));
      Assert.IsNull(Message.GetValue<TJSONObject>('params').GetValue('version'));
      Assert.AreEqual(0, Message.GetValue<TJSONArray>('params.diagnostics').Count);
    finally
      Message.Free;
    end;
  finally
    Diagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.RefreshLaterBundlesCalls;
var
  Diagnostics: TLspSyntaxDiagnostics;
  Calls: Integer;
  Index: Integer;
begin
  // Jedes Projekt einer Gruppe meldet seine Indexstufen; neu geprüft wird einmal (#647).
  Calls := 0;
  Diagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport);
  try
    Diagnostics.PullMode := True;
    Diagnostics.OnPullChanged :=
      procedure
      begin
        TInterlocked.Increment(Calls);
      end;
    for Index := 1 to 5 do
      Diagnostics.RefreshLater;
    Assert.AreEqual(0, TInterlocked.CompareExchange(Calls, 0, 0), 'erst nach der Pause');
    Sleep(TLspSyntaxDiagnostics.RefreshDelayMs + 500);
    Assert.AreEqual(1, TInterlocked.CompareExchange(Calls, 0, 0));
  finally
    Diagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.PublishesWithin200MsAfterLastChange;
var
  Diagnostics: TLspSyntaxDiagnostics;
  Watch: TStopwatch;
  Version: Integer;
  Message: TJSONObject;
begin
  Diagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport);
  try
    Diagnostics.Attach;
    FStore.Open(Uri, 'objectpascal', 1, ValidCode);
    // Schnelles Tippen: Jede Änderung verschiebt die Auswertung.
    for Version := 2 to 6 do
    begin
      FStore.Change(Uri, Version, [TTextChange.Full(BrokenCode)]);
      Sleep(20);
    end;
    Watch := TStopwatch.StartNew;
    Assert.IsTrue(FCapture.WaitForCount(1, 1000), 'Keine Diagnose gemeldet');
    Assert.IsTrue(Watch.ElapsedMilliseconds < 200,
      Format('Diagnose nach %d ms', [Watch.ElapsedMilliseconds]));
    Sleep(TLspSyntaxDiagnostics.DefaultDelayMs * 2);
    Assert.AreEqual(1, Integer(FCapture.Count), 'Nur der letzte Stand wird ausgewertet');
    Message := FCapture.MessageAt(0);
    try
      Assert.AreEqual(6, Message.GetValue<Integer>('params.version'));
    finally
      Message.Free;
    end;
  finally
    Diagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.BuildsParamsForSnapshot;
var
  Params: TJSONObject;
  Document: ITextDocument;
begin
  Document := FStore.Open(Uri, 'objectpascal', 1, BrokenCode);
  Params := TLspSyntaxDiagnostics.BuildParams(Document);
  try
    Assert.AreEqual(1, Params.GetValue<Integer>('version'));
    Assert.AreEqual(1, Params.GetValue<TJSONArray>('diagnostics').Count);
  finally
    Params.Free;
  end;
end;

function RulesWith(const AConfigJson: string): TRuleCheckContext;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Result := Default(TRuleCheckContext);
  Result.Rules := BuiltinRules;
  if AConfigJson = '' then
    Result.Settings := TServerSettings.Default
  else
    Result.Settings := TConfigurationParser.Parse(AConfigJson, Issues);
  Result.RelativePath := 'A.pas';
end;

procedure TLspSyntaxDiagnosticsTests.AddsRuleFindingsWithCode;
var
  Params: TJSONObject;
  Document: ITextDocument;
  Item: TJSONObject;
begin
  Document := FStore.Open(Uri, 'objectpascal', 1, ValidCode + ' // ' + Char($202E));
  Params := TLspSyntaxDiagnostics.BuildParams(Document, nil, '', RulesWith(''));
  try
    Assert.AreEqual(1, Params.GetValue<TJSONArray>('diagnostics').Count);
    Item := Params.GetValue<TJSONArray>('diagnostics').Items[0] as TJSONObject;
    Assert.AreEqual('bidi-control', Item.GetValue<string>('code'));
    Assert.AreEqual(1, Item.GetValue<Integer>('severity'));
  finally
    Params.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.RuleOffInSettingsAddsNothing;
var
  Params: TJSONObject;
  Document: ITextDocument;
begin
  Document := FStore.Open(Uri, 'objectpascal', 1, ValidCode + ' // ' + Char($202E));
  Params := TLspSyntaxDiagnostics.BuildParams(Document, nil, '', RulesWith('{ "rules": { "bidi-control": "off" } }'));
  try
    Assert.AreEqual(0, Params.GetValue<TJSONArray>('diagnostics').Count);
  finally
    Params.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.BaselineHidesKnownRuleFindings;
var
  Params: TJSONObject;
  Document: ITextDocument;
  Rules: TRuleCheckContext;
  Source: TBaselineSource;
begin
  Document := FStore.Open(Uri, 'objectpascal', 1, ValidCode + ' // ' + Char($202E));
  Rules := RulesWith('');
  Source.Path := Rules.RelativePath;
  Source.Text := Document.Text;
  Source.Findings := TFileChecker.CheckText(Rules.Rules, Rules.Settings, Rules.RelativePath, Document.Text);
  Rules.Baseline := TRuleBaseline.FromJson(TRuleBaseline.Build([Source]));
  Params := TLspSyntaxDiagnostics.BuildParams(Document, nil, '', Rules);
  try
    Assert.AreEqual(0, Params.GetValue<TJSONArray>('diagnostics').Count);
  finally
    Params.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.MapsRuleSeverityAndConfidence;
var
  Finding: TRuleFinding;
  Item: TJSONObject;
begin
  Finding := Default(TRuleFinding);
  Finding.RuleId := 'x';
  Finding.Message := 'Meldung';
  Finding.Severity := TRuleSeverity.Information;
  Finding.Confidence := TRuleConfidence.Medium;
  Item := TLspSyntaxDiagnostics.FindingToJson(Finding);
  try
    Assert.AreEqual(3, Item.GetValue<Integer>('severity'));
    // Konfidenz als eigenes Feld, nicht im Meldungstext (#144).
    Assert.AreEqual('Meldung', Item.GetValue<string>('message'));
    Assert.AreEqual('medium', Item.GetValue<string>('data.confidence'));
    Assert.AreEqual(RuleDocumentationBaseUri + Finding.RuleId, Item.GetValue<string>('codeDescription.href'));
  finally
    Item.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.RelatedPlacesBecomeRelatedInformation;
var
  Finding: TRuleFinding;
  Related: TRuleRelated;
  Item: TJSONObject;
  Items: TJSONArray;
begin
  // Unit-Zyklus (#896): jede Unit des Pfads mit ihrem uses-Eintrag als relatedInformation.
  Finding := Default(TRuleFinding);
  Finding.RuleId := 'uses-cycle';
  Finding.Message := 'Zirkuläre Unit-Referenz: C → A → C';
  Related.FileName := 'C:\P\A.pas';
  Related.Range := TTextRange.Create(3, 2, 3, 3);
  Related.Message := 'C';
  Finding.Related := [Related];
  Item := TLspSyntaxDiagnostics.FindingToJson(Finding);
  try
    Items := Item.GetValue('relatedInformation') as TJSONArray;
    Assert.AreEqual(1, Items.Count);
    Assert.AreEqual('C', (Items.Items[0] as TJSONObject).GetValue('message').Value);
    Assert.AreEqual(3, (Items.Items[0] as TJSONObject).GetValue<Integer>('location.range.start.line'));
    Assert.AreEqual(2, (Items.Items[0] as TJSONObject).GetValue<Integer>('location.range.start.character'));
    Assert.IsTrue(EndsText('A.pas', (Items.Items[0] as TJSONObject).GetValue<string>('location.uri')));
  finally
    Item.Free;
  end;
  // Ohne weitere Stellen kein Feld.
  Finding.Related := nil;
  Item := TLspSyntaxDiagnostics.FindingToJson(Finding);
  try
    Assert.IsNull(Item.FindValue('relatedInformation'));
  finally
    Item.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.DataCarriesGroupCategoryAndFixTitle;
var
  Finding: TRuleFinding;
  Item: TJSONObject;
begin
  // Fenster „Atlas-Prüfung“ und Befund-Hover (#909) brauchen Gruppe, Kategorie und Korrekturtitel.
  Finding := Default(TRuleFinding);
  Finding.RuleId := 'empty-except';
  Finding.Message := 'Leerer except-Block';
  Finding.Severity := TRuleSeverity.Warning;
  Finding.Fixes := [TRuleFix.Create('Ausnahme protokollieren', nil)];
  Item := TLspSyntaxDiagnostics.FindingToJson(Finding);
  try
    Assert.AreEqual('exceptions', Item.GetValue<string>('data.group'));
    Assert.AreEqual('code-smell', Item.GetValue<string>('data.category'));
    Assert.AreEqual('Ausnahme protokollieren', Item.GetValue<string>('data.fix'));
    // Ohne Compilercodes kein Feld.
    Assert.IsNull((Item.GetValue('data') as TJSONObject).FindValue('compilerCodes'));
  finally
    Item.Free;
  end;
  // Gruppe „Compiler vorab“ (#1024): Codes für den Abgleich mit dcc im Plugin.
  Finding.RuleId := 'argument-count-mismatch';
  Finding.Fixes := nil;
  Item := TLspSyntaxDiagnostics.FindingToJson(Finding);
  try
    Assert.AreEqual('compiler', Item.GetValue<string>('data.group'));
    Assert.AreEqual('["E2034","E2035"]', (Item.GetValue('data') as TJSONObject).GetValue('compilerCodes').ToJSON);
    // Ohne Zusatz kein data.details.
    Assert.IsNull(Item.FindValue('data.details'));
  finally
    Item.Free;
  end;
  // Zusatz für den Befund-Hover (#1102).
  Finding.Details := 'Durchsucht: 3 Dateien der Projektgruppe';
  Item := TLspSyntaxDiagnostics.FindingToJson(Finding);
  try
    Assert.AreEqual('Durchsucht: 3 Dateien der Projektgruppe', Item.GetValue<string>('data.details'));
  finally
    Item.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.DataSkipsAlternativeFixesAndUnknownRules;
var
  Finding: TRuleFinding;
  First, Second: TRuleFix;
  Item: TJSONObject;
  Data: TJSONObject;
begin
  Finding := Default(TRuleFinding);
  Finding.RuleId := 'gibt-es-nicht';
  Finding.Message := 'Meldung';
  First := TRuleFix.Create('Variante A', nil);
  First.Alternative := True;
  Second := TRuleFix.Create('Bevorzugt', nil);
  Finding.Fixes := [Second, First];
  Item := TLspSyntaxDiagnostics.FindingToJson(Finding);
  try
    Data := Item.GetValue('data') as TJSONObject;
    Assert.IsNull(Data.FindValue('group'));
    Assert.IsNull(Data.FindValue('category'));
    Assert.AreEqual('Bevorzugt', Data.GetValue<string>('fix'));
  finally
    Item.Free;
  end;
  // Steht eine Alternative vorn, gibt es wie bei den Code-Aktionen keine bevorzugte Korrektur.
  Finding.Fixes := [First, Second];
  Item := TLspSyntaxDiagnostics.FindingToJson(Finding);
  try
    Data := Item.GetValue('data') as TJSONObject;
    Assert.IsNull(Data.FindValue('fix'));
  finally
    Item.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.AddsInactiveRangesAsUnnecessaryHints;
var
  Params: TJSONObject;
  Document: ITextDocument;
  Item: TJSONValue;
begin
  Document := FStore.Open(Uri, 'objectpascal', 1, ValidCode);
  Params := TLspSyntaxDiagnostics.BuildParams(Document,
    [TTextRange.Create(TTextPosition.Create(1, 0), TTextPosition.Create(2, 0))]);
  try
    Assert.AreEqual(1, Params.GetValue<TJSONArray>('diagnostics').Count);
    Item := Params.GetValue<TJSONArray>('diagnostics').Items[0];
    Assert.AreEqual(4, Item.GetValue<Integer>('severity'));
    Assert.AreEqual(1, Item.GetValue<Integer>('tags[0]'));
    Assert.AreEqual(1, Item.GetValue<Integer>('range.start.line'));
  finally
    Params.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.FindsInactiveRanges;
const
  Code =
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
  Ranges: TArray<TTextRange>;
begin
  Ranges := TLspInactiveRegions.Ranges(Code, ['WIN64']);
  Assert.AreEqual(1, Integer(Length(Ranges)));
  Assert.AreEqual(4, Ranges[0].StartPos.Line);
  Assert.AreEqual(6, Ranges[0].EndPos.Line);
  Ranges := TLspInactiveRegions.Ranges(Code, nil);
  Assert.AreEqual(1, Integer(Length(Ranges)));
  Assert.AreEqual(2, Ranges[0].StartPos.Line);
end;

procedure TLspSyntaxDiagnosticsTests.InactiveRegionsNameTheirCondition;
const
  Code =
    'unit U;'#10 +
    '{$IFDEF WIN64}'#10 +
    'const A = 1;'#10 +
    '{$ELSE}'#10 +
    'const A = 2;'#10 +
    '{$ENDIF}'#10 +
    '{$IFDEF DEBUG}{$IFDEF WIN64} const B = 1; {$ENDIF}{$ENDIF}'#10 +
    'end.';
var
  Regions: TArray<TLspInactiveRegion>;
begin
  Regions := TLspInactiveRegions.Regions(Code, ['WIN64']);
  Assert.AreEqual(2, Integer(Length(Regions)));
  Assert.AreEqual('not WIN64', Regions[0].Condition);
  Assert.AreEqual('DEBUG', Regions[1].Condition);
  Regions := TLspInactiveRegions.Regions(Code, ['DEBUG']);
  Assert.AreEqual(2, Integer(Length(Regions)));
  Assert.AreEqual('WIN64', Regions[0].Condition);
  // Zweig innerhalb einer Zeile, verschachtelt (#615).
  Assert.AreEqual('DEBUG und WIN64', Regions[1].Condition);
  Assert.AreEqual(6, Regions[1].Range.StartPos.Line);
  Assert.AreEqual(6, Regions[1].Range.EndPos.Line);
  Assert.AreEqual(28, Regions[1].Range.StartPos.Character);
end;

procedure TLspSyntaxDiagnosticsTests.InactiveHintNamesConditionAndTarget;
const
  Code = 'unit U;'#10'interface'#10'{$IFDEF WIN64}'#10'const A = 1;'#10'{$ENDIF}'#10'implementation'#10'end.';
var
  Diagnostics: TLspSyntaxDiagnostics;
  Document: ITextDocument;
  Params: TJSONObject;
  Item: TJSONValue;
begin
  Assert.AreEqual(TLspSyntaxDiagnostics.InactiveMessage, TLspSyntaxDiagnostics.InactiveMessageOf('', 'Win32', 'Debug'));
  Assert.AreEqual('Inaktiv: Bedingung DEBUG nicht erfüllt', TLspSyntaxDiagnostics.InactiveMessageOf('DEBUG', '', ''));
  Assert.AreEqual('Inaktiv: Bedingung DEBUG nicht erfüllt (Zielplattform Win64 · ?)',
    TLspSyntaxDiagnostics.InactiveMessageOf('DEBUG', 'Win64', ''));
  Diagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, 0);
  try
    Diagnostics.DefinesProvider :=
      function(const AUri: string; out ADefines: TArray<string>): Boolean
      begin
        ADefines := ['WIN32'];
        Result := True;
      end;
    Diagnostics.BuildTargetProvider :=
      function(const AUri: string; out APlatform, AConfig: string): Boolean
      begin
        APlatform := 'Win32';
        AConfig := 'Debug';
        Result := True;
      end;
    Document := FStore.Open(Uri, 'objectpascal', 1, Code);
    Params := Diagnostics.Compute(Document);
    try
      Assert.AreEqual(1, Params.GetValue<TJSONArray>('diagnostics').Count);
      Item := Params.GetValue<TJSONArray>('diagnostics').Items[0];
      Assert.AreEqual(1, Item.GetValue<TJSONArray>('tags').Count);
      Assert.AreEqual('Inaktiv: Bedingung WIN64 nicht erfüllt (Zielplattform Win32 · Debug)',
        Item.GetValue<string>('message'));
      Assert.AreEqual('WIN64', Item.GetValue<string>('data.inactive.condition'));
      Assert.AreEqual('Win32', Item.GetValue<string>('data.inactive.platform'));
      Assert.AreEqual('Debug', Item.GetValue<string>('data.inactive.config'));
    finally
      Params.Free;
    end;
  finally
    Diagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.ComputeReadsIncludeDefines;
const
  Code = 'unit U;'#10'interface'#10'{$I defs.inc}'#10'{$IFDEF FOO} uses A; {$ENDIF}'#10 +
    '{$IFNDEF FOO} uses B; uses C; {$ENDIF}'#10'{$I fehlt.inc}'#10'implementation'#10'end.';
var
  Diagnostics: TLspSyntaxDiagnostics;
  Document: ITextDocument;
  Params: TJSONObject;
  Item: TJSONValue;
  Messages: string;
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
  Diagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, 0);
  try
    Diagnostics.DefinesProvider :=
      function(const AUri: string; out ADefines: TArray<string>): Boolean
      begin
        ADefines := ['WIN32'];
        Result := True;
      end;
    Document := FStore.Open(Uri, 'objectpascal', 1, Code);
    Params := Diagnostics.Compute(Document);
    try
      Messages := '';
      for Item in Params.GetValue<TJSONArray>('diagnostics') do
        Messages := Messages + Item.GetValue<string>('message') + '|';
      // Kein Syntaxfehler: Der {$IFNDEF FOO}-Zweig ist abgeblendet, fehlt.inc ein Hinweis.
      Assert.AreEqual('Inaktiv: Bedingung not FOO nicht erfüllt|Include-Datei "fehlt.inc" nicht gefunden|',
        Messages);
    finally
      Params.Free;
    end;
  finally
    Diagnostics.Free;
    TSyntaxTreeCache.SetIncludeProvider(nil);
  end;
end;

procedure TLspSyntaxDiagnosticsTests.AddsCompilerMessagesToOpenDocuments;
var
  Diagnostics: TLspSyntaxDiagnostics;
  Message: TJSONObject;
  Items: TJSONArray;
begin
  Diagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, 0);
  try
    Diagnostics.CompilerMessagesProvider :=
      function(const AFileName: string): TArray<TCompilerMessage>
      begin
        Result := [CompilerMessage(2, 2, TCompilerSeverity.Error), CompilerMessage(1, -1, TCompilerSeverity.Hint)];
      end;
    Diagnostics.Attach;
    FStore.Open(Uri, 'objectpascal', 1, ValidCode);
    Message := FCapture.MessageAt(0);
    try
      Items := Message.GetValue<TJSONArray>('params.diagnostics');
      Assert.AreEqual(2, Integer(Items.Count));
      // Spalte 2 in "  A := 1;": der Bezeichner A.
      Assert.AreEqual(2, Items.Items[0].GetValue<Integer>('range.start.line'));
      Assert.AreEqual(2, Items.Items[0].GetValue<Integer>('range.start.character'));
      Assert.AreEqual(3, Items.Items[0].GetValue<Integer>('range.end.character'));
      Assert.AreEqual('E2003', Items.Items[0].GetValue<string>('code'));
      Assert.AreEqual('dcc', Items.Items[0].GetValue<string>('source'));
      Assert.AreEqual(1, Items.Items[0].GetValue<Integer>('severity'));
      // Ohne Spalte die ganze Zeile "begin".
      Assert.AreEqual(0, Items.Items[1].GetValue<Integer>('range.start.character'));
      Assert.AreEqual(5, Items.Items[1].GetValue<Integer>('range.end.character'));
      Assert.AreEqual(4, Items.Items[1].GetValue<Integer>('severity'));
    finally
      Message.Free;
    end;
  finally
    Diagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.PublishesCompilerMessagesForClosedFiles;
var
  Diagnostics: TLspSyntaxDiagnostics;
  Message: TJSONObject;
  Items: TJSONArray;
begin
  Diagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, 0);
  try
    Diagnostics.CompilerMessagesProvider :=
      function(const AFileName: string): TArray<TCompilerMessage>
      begin
        Result := [CompilerMessage(4, -1, TCompilerSeverity.Warning)];
      end;
    Diagnostics.Attach;
    Diagnostics.RefreshFiles(['C:\Projekt\B.pas']);
    Assert.AreEqual(1, Integer(FCapture.Count));
    Message := FCapture.MessageAt(0);
    try
      Assert.IsTrue(SameText('C:\Projekt\B.pas', TDocumentUris.ToPath(Message.GetValue<string>('params.uri'))));
      Items := Message.GetValue<TJSONArray>('params.diagnostics');
      Assert.AreEqual(1, Integer(Items.Count));
      // Ohne Zeilentext: die ganze Zeile bis zum Anfang der nächsten.
      Assert.AreEqual(4, Items.Items[0].GetValue<Integer>('range.start.line'));
      Assert.AreEqual(5, Items.Items[0].GetValue<Integer>('range.end.line'));
      Assert.AreEqual(2, Items.Items[0].GetValue<Integer>('severity'));
    finally
      Message.Free;
    end;
  finally
    Diagnostics.Free;
  end;
end;

procedure TLspSyntaxDiagnosticsTests.ReportsUnusedUsesUnlessSyntaxErrors;
const
  Code = 'unit U;'#10'interface'#10'uses'#10'  Vcl.Grids, Units.Reg;'#10'implementation'#10'end.';
var
  Diagnostics: TLspSyntaxDiagnostics;
  Document: ITextDocument;
  Params: TJSONObject;
  Items: TJSONArray;
begin
  Diagnostics := TLspSyntaxDiagnostics.Create(FStore, FTransport, 0);
  try
    Diagnostics.UsesProvider :=
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
    Document := FStore.Open(Uri, 'objectpascal', 1, Code);
    Params := Diagnostics.Compute(Document);
    try
      Items := Params.GetValue<TJSONArray>('diagnostics');
      Assert.AreEqual(2, Integer(Items.Count));
      Assert.AreEqual('Aus Vcl.Grids wird nichts verwendet', Items.Items[0].GetValue<string>('message'));
      Assert.AreEqual(1, Items.Items[0].GetValue<TJSONArray>('tags').Count);
      Assert.AreEqual(4, Items.Items[0].GetValue<Integer>('severity'));
      Assert.AreEqual('Vcl.Grids', Items.Items[0].GetValue<string>('data.uses.unit'));
      Assert.AreEqual('unused', Items.Items[0].GetValue<string>('data.uses.state'));
      Assert.AreEqual(3, Items.Items[0].GetValue<Integer>('range.start.line'));
      Assert.AreEqual(2, Items.Items[0].GetValue<Integer>('range.start.character'));
      Assert.AreEqual(11, Items.Items[0].GetValue<Integer>('range.end.character'));
      Assert.AreEqual('Units.Reg wird wegen initialization nicht als ungenutzt gezeigt',
        Items.Items[1].GetValue<string>('message'));
      Assert.IsNull(TJSONObject(Items.Items[1]).GetValue('tags'));
      Assert.AreEqual('initialization', Items.Items[1].GetValue<string>('data.uses.state'));
    finally
      Params.Free;
    end;
    // Syntaxfehler: keine uses-Hinweise, nur der Fehler.
    Document := FStore.Change(Uri, 2, [TTextChange.Full(Code.Replace('implementation', 'implementation'#10'procedure'))]);
    Params := Diagnostics.Compute(Document);
    try
      Items := Params.GetValue<TJSONArray>('diagnostics');
      Assert.IsTrue(Items.Count > 0);
      Assert.AreEqual(0, Pos('uses', Params.ToJSON), Params.ToJSON);
    finally
      Params.Free;
    end;
  finally
    Diagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSyntaxDiagnosticsTests);

end.
