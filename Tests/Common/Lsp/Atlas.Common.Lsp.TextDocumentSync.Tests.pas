unit Atlas.Common.Lsp.TextDocumentSync.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.TextDocumentSync;

type
  [TestFixture]
  TLspTextDocumentSyncTests = class
  private
    FStore: IDocumentStore;
    FSync: TLspTextDocumentSync;
    FDispatcher: TJsonRpcDispatcher;
    FSaved: Integer;
    procedure Send(const AJson: string);
    function TextOf(const AUri: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DidOpenStoresDocument;
    [Test]
    procedure DidChangeAppliesIncrementalChangesInOrder;
    [Test]
    procedure DidChangeWithoutRangeReplacesText;
    [Test]
    procedure DidSaveAndDidCloseReachStore;
    [Test]
    procedure RejectsMissingFieldsWithInvalidParams;
    [Test]
    procedure CapabilityAnnouncesIncrementalSync;
    [Test]
    procedure ConvertsRangeToJsonAndBack;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.TestSupport,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Lsp.Positions;

const
  Uri = 'file:///c%3A/projekt/Main.pas';

{ TLspTextDocumentSyncTests }

procedure TLspTextDocumentSyncTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FSaved := 0;
  FStore.Subscribe(
    procedure(AKind: TDocumentEventKind; const ADocument: ITextDocument)
    begin
      if AKind = TDocumentEventKind.Saved then
        Inc(FSaved);
    end);
  FSync := TLspTextDocumentSync.Create(FStore);
  FDispatcher := TJsonRpcDispatcher.Create;
  FSync.Attach(FDispatcher);
end;

procedure TLspTextDocumentSyncTests.TearDown;
begin
  FreeAndNil(FDispatcher);
  FreeAndNil(FSync);
  FStore := nil;
end;

procedure TLspTextDocumentSyncTests.Send(const AJson: string);
var
  Message: TJSONObject;
begin
  Message := TJsonRpcTestSupport.Parse(AJson);
  try
    Assert.IsNull(FDispatcher.DispatchMessage(Message));
  finally
    Message.Free;
  end;
end;

function TLspTextDocumentSyncTests.TextOf(const AUri: string): string;
var
  Document: ITextDocument;
begin
  Assert.IsTrue(FStore.TryGet(AUri, Document), 'Dokument nicht geöffnet');
  Result := Document.Text;
end;

procedure TLspTextDocumentSyncTests.DidOpenStoresDocument;
var
  Document: ITextDocument;
begin
  Send('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":' +
    '{"uri":"' + Uri + '","languageId":"pascal","version":3,"text":"unit Main;\r\nend."}}}');
  Assert.IsTrue(FStore.TryGet(Uri, Document));
  Assert.AreEqual('unit Main;'#13#10'end.', Document.Text);
  Assert.AreEqual(3, Document.Version);
  Assert.AreEqual('pascal', Document.LanguageId);
end;

procedure TLspTextDocumentSyncTests.DidChangeAppliesIncrementalChangesInOrder;
var
  Document: ITextDocument;
begin
  Send('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":' +
    '{"uri":"' + Uri + '","languageId":"pascal","version":1,"text":"unit Main;\nend."}}}');
  Send('{"jsonrpc":"2.0","method":"textDocument/didChange","params":{' +
    '"textDocument":{"uri":"' + Uri + '","version":2},"contentChanges":[' +
    '{"range":{"start":{"line":0,"character":5},"end":{"line":0,"character":9}},"text":"Haupt"},' +
    '{"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":0}},"text":"begin\n"}]}}');
  Assert.IsTrue(FStore.TryGet(Uri, Document));
  Assert.AreEqual('unit Haupt;'#10'begin'#10'end.', Document.Text);
  Assert.AreEqual(2, Document.Version);
end;

procedure TLspTextDocumentSyncTests.DidChangeWithoutRangeReplacesText;
begin
  Send('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":' +
    '{"uri":"' + Uri + '","languageId":"pascal","version":1,"text":"alt"}}}');
  Send('{"jsonrpc":"2.0","method":"textDocument/didChange","params":{' +
    '"textDocument":{"uri":"' + Uri + '","version":2},"contentChanges":[{"text":"neu"}]}}');
  Assert.AreEqual('neu', TextOf(Uri));
end;

procedure TLspTextDocumentSyncTests.DidSaveAndDidCloseReachStore;
var
  Document: ITextDocument;
begin
  Send('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":' +
    '{"uri":"' + Uri + '","languageId":"pascal","version":1,"text":"x"}}}');
  Send('{"jsonrpc":"2.0","method":"textDocument/didSave","params":{"textDocument":{"uri":"' + Uri + '"}}}');
  Assert.AreEqual(1, FSaved);
  Send('{"jsonrpc":"2.0","method":"textDocument/didClose","params":{"textDocument":{"uri":"' + Uri + '"}}}');
  Assert.IsFalse(FStore.TryGet(Uri, Document));
end;

procedure TLspTextDocumentSyncTests.RejectsMissingFieldsWithInvalidParams;
var
  Code: Integer;
begin
  // Benachrichtigungen erhalten keine Antwort; der Fehler geht an die
  // Nachrichtenschleife, die ihn protokolliert.
  Code := 0;
  try
    Send('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"' + Uri + '"}}}');
  except
    on E: EJsonRpcError do
      Code := E.Code;
  end;
  Assert.AreEqual(TJsonRpcErrorCode.InvalidParams, Code);
end;

procedure TLspTextDocumentSyncTests.CapabilityAnnouncesIncrementalSync;
var
  Capability: TJSONObject;
begin
  Capability := TLspTextDocumentSync.Capability;
  try
    Assert.IsTrue(Capability.GetValue<Boolean>('openClose'));
    Assert.AreEqual(2, Capability.GetValue<Integer>('change'));
    Assert.IsFalse(Capability.GetValue<Boolean>('save.includeText'));
  finally
    Capability.Free;
  end;
end;

procedure TLspTextDocumentSyncTests.ConvertsRangeToJsonAndBack;
var
  Json: TJSONObject;
  Range: TTextRange;
begin
  Json := TLspPositions.RangeToJson(TTextRange.Create(1, 2, 3, 4));
  try
    Assert.AreEqual(1, Json.GetValue<Integer>('start.line'));
    Assert.AreEqual(4, Json.GetValue<Integer>('end.character'));
    Range := TLspPositions.ReadRange(Json);
  finally
    Json.Free;
  end;
  Assert.IsTrue(TTextPosition.Create(1, 2) = Range.StartPos);
  Assert.IsTrue(TTextPosition.Create(3, 4) = Range.EndPos);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspTextDocumentSyncTests);

end.
