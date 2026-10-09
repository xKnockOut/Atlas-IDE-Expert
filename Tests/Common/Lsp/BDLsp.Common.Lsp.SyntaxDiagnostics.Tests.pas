unit BDLsp.Common.Lsp.SyntaxDiagnostics.Tests;

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  System.JSON,
  DUnitX.TestFramework,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.Documents.Contract;

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
    // Worker- bzw. Pool-Threads legen Verwaltungsdaten an, die erst nach dem Test freigegeben werden.
    [IgnoreMemoryLeaks]
    procedure PublishesWithin200MsAfterLastChange;
    [Test]
    procedure BuildsParamsForSnapshot;
    [Test]
    procedure AddsInactiveRangesAsUnnecessaryHints;
    [Test]
    procedure FindsInactiveRanges;
    [Test]
    procedure AddsRuleFindingsWithCode;
    [Test]
    procedure RuleOffInSettingsAddsNothing;
    [Test]
    procedure BaselineHidesKnownRuleFindings;
    [Test]
    procedure MapsRuleSeverityAndConfidence;
    [Test]
    procedure AddsCompilerMessagesToOpenDocuments;
    [Test]
    procedure PublishesCompilerMessagesForClosedFiles;
  end;

implementation

uses
  BDLsp.Common.Rules.Catalog,
  BDLsp.Common.Rules.Baseline,
  BDLsp.Common.Rules.Checker,
  BDLsp.Common.Lsp.InactiveRegions,
  System.Classes,
  System.Diagnostics,
  BDLsp.Common.Documents.Providers.DocumentStore,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Configuration.Parser,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Builtin,
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Compiler.Contract,
  BDLsp.Common.Lsp.SyntaxDiagnostics;

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
    Assert.AreEqual(1, FCapture.Count);
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
      Assert.AreEqual('BetterDelphiLSP', Item.GetValue<string>('source'));
      Assert.AreEqual('";" fehlt', Item.GetValue<string>('message'));
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
    Assert.AreEqual(2, FCapture.Count);
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
    Assert.AreEqual(2, FCapture.Count);
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
    Assert.AreEqual(1, FCapture.Count, 'Nur der letzte Stand wird ausgewertet');
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
    Assert.AreEqual('Meldung (Konfidenz: mittel)', Item.GetValue<string>('message'));
    Assert.AreEqual(RuleDocumentationBaseUri + Finding.RuleId, Item.GetValue<string>('codeDescription.href'));
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
      Assert.AreEqual(2, Items.Count);
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
    Assert.AreEqual(1, FCapture.Count);
    Message := FCapture.MessageAt(0);
    try
      Assert.IsTrue(SameText('C:\Projekt\B.pas', TDocumentUris.ToPath(Message.GetValue<string>('params.uri'))));
      Items := Message.GetValue<TJSONArray>('params.diagnostics');
      Assert.AreEqual(1, Items.Count);
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

initialization
  TDUnitX.RegisterTestFixture(TLspSyntaxDiagnosticsTests);

end.
