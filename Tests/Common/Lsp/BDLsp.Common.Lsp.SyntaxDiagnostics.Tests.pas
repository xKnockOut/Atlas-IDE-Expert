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
    procedure PublishesWithin200MsAfterLastChange;
    [Test]
    procedure BuildsParamsForSnapshot;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  BDLsp.Common.Documents.Providers.DocumentStore,
  BDLsp.Common.Lsp.SyntaxDiagnostics;

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

initialization
  TDUnitX.RegisterTestFixture(TLspSyntaxDiagnosticsTests);

end.
