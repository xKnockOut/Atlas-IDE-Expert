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
  cUri = 'file:///c%3A/projekt/Main.pas';

{ TLspTextDocumentSyncTests }

procedure TLspTextDocumentSyncTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FSaved := 0;
  FStore.Subscribe(
    procedure(AKind: TDocumentEventKind; const ADocument: ITextDocument)
    begin
      if AKind = TDocumentEventKind.Saved then
      begin
        Inc(FSaved);
      end;
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
  mMessage: TJSONObject;
begin
  mMessage := TJsonRpcTestSupport.Parse(AJson);
  try
    Assert.IsNull(FDispatcher.DispatchMessage(mMessage));
  finally
    mMessage.Free;
  end;
end;

function TLspTextDocumentSyncTests.TextOf(const AUri: string): string;
var
  mDocument: ITextDocument;
begin
  Assert.IsTrue(FStore.TryGet(AUri, mDocument), 'Dokument nicht geöffnet');
  Result := mDocument.Text;
end;

procedure TLspTextDocumentSyncTests.DidOpenStoresDocument;
var
  mDocument: ITextDocument;
begin
  Send('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":' +
    '{"uri":"' + cUri + '","languageId":"pascal","version":3,"text":"unit Main;\r\nend."}}}');
  Assert.IsTrue(FStore.TryGet(cUri, mDocument));
  Assert.AreEqual('unit Main;'#13#10'end.', mDocument.Text);
  Assert.AreEqual(3, mDocument.Version);
  Assert.AreEqual('pascal', mDocument.LanguageId);
end;

procedure TLspTextDocumentSyncTests.DidChangeAppliesIncrementalChangesInOrder;
var
  mDocument: ITextDocument;
begin
  Send('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":' +
    '{"uri":"' + cUri + '","languageId":"pascal","version":1,"text":"unit Main;\nend."}}}');
  Send('{"jsonrpc":"2.0","method":"textDocument/didChange","params":{' +
    '"textDocument":{"uri":"' + cUri + '","version":2},"contentChanges":[' +
    '{"range":{"start":{"line":0,"character":5},"end":{"line":0,"character":9}},"text":"Haupt"},' +
    '{"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":0}},"text":"begin\n"}]}}');
  Assert.IsTrue(FStore.TryGet(cUri, mDocument));
  Assert.AreEqual('unit Haupt;'#10'begin'#10'end.', mDocument.Text);
  Assert.AreEqual(2, mDocument.Version);
end;

procedure TLspTextDocumentSyncTests.DidChangeWithoutRangeReplacesText;
begin
  Send('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":' +
    '{"uri":"' + cUri + '","languageId":"pascal","version":1,"text":"alt"}}}');
  Send('{"jsonrpc":"2.0","method":"textDocument/didChange","params":{' +
    '"textDocument":{"uri":"' + cUri + '","version":2},"contentChanges":[{"text":"neu"}]}}');
  Assert.AreEqual('neu', TextOf(cUri));
end;

procedure TLspTextDocumentSyncTests.DidSaveAndDidCloseReachStore;
var
  mDocument: ITextDocument;
begin
  Send('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":' +
    '{"uri":"' + cUri + '","languageId":"pascal","version":1,"text":"x"}}}');
  Send('{"jsonrpc":"2.0","method":"textDocument/didSave","params":{"textDocument":{"uri":"' + cUri + '"}}}');
  Assert.AreEqual(1, FSaved);
  Send('{"jsonrpc":"2.0","method":"textDocument/didClose","params":{"textDocument":{"uri":"' + cUri + '"}}}');
  Assert.IsFalse(FStore.TryGet(cUri, mDocument));
end;

procedure TLspTextDocumentSyncTests.RejectsMissingFieldsWithInvalidParams;
var
  mCode: Integer;
begin
  // Benachrichtigungen erhalten keine Antwort; der Fehler geht an die
  // Nachrichtenschleife, die ihn protokolliert.
  mCode := 0;
  try
    Send('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"' + cUri + '"}}}');
  except
    on E: EJsonRpcError do
      mCode := E.Code;
  end;
  Assert.AreEqual(TJsonRpcErrorCode.cInvalidParams, mCode);
end;

procedure TLspTextDocumentSyncTests.CapabilityAnnouncesIncrementalSync;
var
  mCapability: TJSONObject;
begin
  mCapability := TLspTextDocumentSync.Capability;
  try
    Assert.IsTrue(mCapability.GetValue<Boolean>('openClose'));
    Assert.AreEqual(2, mCapability.GetValue<Integer>('change'));
    Assert.IsFalse(mCapability.GetValue<Boolean>('save.includeText'));
  finally
    mCapability.Free;
  end;
end;

procedure TLspTextDocumentSyncTests.ConvertsRangeToJsonAndBack;
var
  mJson: TJSONObject;
  mRange: TTextRange;
begin
  mJson := TLspPositions.RangeToJson(TTextRange.Create(1, 2, 3, 4));
  try
    Assert.AreEqual(1, mJson.GetValue<Integer>('start.line'));
    Assert.AreEqual(4, mJson.GetValue<Integer>('end.character'));
    mRange := TLspPositions.ReadRange(mJson);
  finally
    mJson.Free;
  end;
  Assert.AreEqual(1, mRange.StartPos.Line);
  Assert.AreEqual(2, mRange.StartPos.Character);
  Assert.AreEqual(3, mRange.EndPos.Line);
  Assert.AreEqual(4, mRange.EndPos.Character);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspTextDocumentSyncTests);

end.
