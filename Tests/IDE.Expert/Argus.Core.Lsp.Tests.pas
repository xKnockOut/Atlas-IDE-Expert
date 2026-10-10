unit Argus.Core.Lsp.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspClientTests = class
  public
    [Test]
    procedure AnswersRequestFromSplitFrames;
    [Test]
    procedure RaisesOnErrorResponse;
    [Test]
    procedure AnswersServerRequestWithNull;
    [Test]
    procedure RejectsRequestsAfterClose;
  end;

  [TestFixture]
  TLspSessionTests = class
  public
    [Test]
    procedure ConvertsPathsAndUris;
    [Test]
    procedure ReadsAllHoverForms;
    [Test]
    procedure ReadsHoverParts;
    [Test]
    procedure MapsEditorColumnsWithTabs;
    [Test]
    procedure SendsOpenOnceAndChangeOnlyWhenTextChanged;
  end;

  [TestFixture]
  TLspServerProcessTests = class
  public
    // Startet den echten Server neben dem Testprogramm.
    [Test]
    [IgnoreMemoryLeaks]
    procedure HoverAndDefinitionAgainstServer;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Argus.Core.Lsp.Client,
  Argus.Core.Lsp.Session,
  Argus.Core.Lsp.Adapters.ServerProcess;

// Liest die JSON-Nachricht aus gerahmten Bytes.
function Unframe(const ABytes: TBytes): TJSONObject;
var
  Text: string;
begin
  Text := TEncoding.UTF8.GetString(ABytes);
  Result := TJSONObject.ParseJSONValue(Text.Substring(Text.IndexOf(#13#10#13#10) + 4)) as TJSONObject;
end;

{ TLspClientTests }

procedure TLspClientTests.AnswersRequestFromSplitFrames;
var
  Client: TLspClient;
  Response: TJSONValue;
  Wert: string;
begin
  Client := nil;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Request: TJSONObject;
      Reply: TBytes;
      Index, Id: Integer;
    begin
      Request := Unframe(ABytes);
      try
        Id := Request.GetValue<Integer>('id');
        Reply := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":{"wert":"Grüße"}}', [Id]));
      finally
        Request.Free;
      end;
      // Byteweise, um die Rahmung über Stückgrenzen zu prüfen.
      for Index := 0 to High(Reply) do
        Client.Receive(Copy(Reply, Index, 1), 1);
    end);
  try
    Response := Client.Request('test', nil, 1000);
    try
      Wert := Response.GetValue<string>('wert');
      Assert.AreEqual('Grüße', Wert);
    finally
      Response.Free;
    end;
  finally
    Client.Free;
  end;
end;

procedure TLspClientTests.RaisesOnErrorResponse;
var
  Client: TLspClient;
begin
  Client := nil;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Request: TJSONObject;
      Reply: TBytes;
      Id: Integer;
    begin
      Request := Unframe(ABytes);
      try
        Id := Request.GetValue<Integer>('id');
        Reply := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"error":{"code":-32601,"message":"unbekannt"}}', [Id]));
      finally
        Request.Free;
      end;
      Client.Receive(Reply, Length(Reply));
    end);
  try
    Assert.WillRaiseWithMessage(
      procedure
      begin
        Client.Request('test', nil, 1000).Free;
      end, ELspClientError, 'unbekannt');
  finally
    Client.Free;
  end;
end;

procedure TLspClientTests.AnswersServerRequestWithNull;
var
  Client: TLspClient;
  Sent: TList<string>;
  Incoming: TBytes;
begin
  Sent := TList<string>.Create;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
    begin
      Message := Unframe(ABytes);
      try
        Sent.Add(Message.ToJSON);
      finally
        Message.Free;
      end;
    end);
  try
    Incoming := TLspClient.Frame('{"jsonrpc":"2.0","id":"p1","method":"window/workDoneProgress/create","params":{}}') +
      TLspClient.Frame('{"jsonrpc":"2.0","method":"window/logMessage","params":{"type":3,"message":"x"}}');
    Client.Receive(Incoming, Length(Incoming));
    Assert.AreEqual(1, Integer(Sent.Count));
    Assert.AreEqual('{"jsonrpc":"2.0","id":"p1","result":null}', Sent[0]);
  finally
    Client.Free;
    Sent.Free;
  end;
end;

procedure TLspClientTests.RejectsRequestsAfterClose;
var
  Client: TLspClient;
begin
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
    end);
  try
    Client.Close;
    Assert.WillRaise(
      procedure
      begin
        Client.Request('test', nil, 1000).Free;
      end, ELspClientError);
  finally
    Client.Free;
  end;
end;

{ TLspSessionTests }

procedure TLspSessionTests.ConvertsPathsAndUris;
begin
  Assert.AreEqual('file:///C%3A/Mein%20Projekt/%C3%9Cbung.pas', TLspSession.PathToUri('C:\Mein Projekt\Übung.pas'));
  Assert.AreEqual('C:\Mein Projekt\Übung.pas', TLspSession.UriToPath('file:///C%3A/Mein%20Projekt/%C3%9Cbung.pas'));
  Assert.AreEqual('c:\x\a.pas', TLspSession.UriToPath('file:///c:/x/a.pas'));
  Assert.AreEqual('file://server/share/a.pas', TLspSession.PathToUri('\\server\share\a.pas'));
  Assert.AreEqual('\\server\share\a.pas', TLspSession.UriToPath('file://server/share/a.pas'));
  Assert.AreEqual('', TLspSession.UriToPath('untitled:1'));
end;

procedure TLspSessionTests.ReadsAllHoverForms;

  function Text(const AJson: string): string;
  var
    Value: TJSONValue;
  begin
    Value := TJSONObject.ParseJSONValue(AJson);
    try
      Result := TLspSession.HoverText(Value);
    finally
      Value.Free;
    end;
  end;

begin
  Assert.AreEqual('A: Integer;', Text('{"contents":"A: Integer;"}'));
  Assert.AreEqual('B', Text('{"contents":{"kind":"plaintext","value":"B"}}'));
  Assert.AreEqual('C' + sLineBreak + 'D', Text('{"contents":["C",{"language":"delphi","value":"D"}]}'));
  Assert.AreEqual('', Text('null'));
end;

procedure TLspSessionTests.ReadsHoverParts;
var
  Hover: TJSONValue;
  Parts: TLspHoverParts;
begin
  // Mit Teilen des Servers (#442).
  Hover := TJSONObject.ParseJSONValue('{"contents":"x","argus":{"declaration":"procedure BeginUpdate;",' +
    '"unit":"System.Classes","documentation":"Unterdrückt das Neuzeichnen."}}');
  try
    Parts := TLspHoverParts.FromHover(Hover);
    Assert.AreEqual('procedure BeginUpdate;', Parts.Declaration);
    Assert.AreEqual('System.Classes', Parts.UnitName);
    Assert.AreEqual('Unterdrückt das Neuzeichnen.', Parts.Documentation);
    Assert.IsTrue(Parts.Found);
  finally
    Hover.Free;
  end;
  // Ältere Server: erster Absatz Deklaration, Rest Doku.
  Hover := TJSONObject.ParseJSONValue('{"contents":"function Max(A, B: Integer): Integer;\n\nGrößerer Wert."}');
  try
    Parts := TLspHoverParts.FromHover(Hover);
    Assert.AreEqual('function Max(A, B: Integer): Integer;', Parts.Declaration);
    Assert.AreEqual('Größerer Wert.', Parts.Documentation);
  finally
    Hover.Free;
  end;
  Assert.IsFalse(TLspHoverParts.FromHover(nil).Found);
end;

procedure TLspSessionTests.MapsEditorColumnsWithTabs;
begin
  Assert.AreEqual(0, TLspSession.ColumnToIndex('abc', 1, 8));
  Assert.AreEqual(2, TLspSession.ColumnToIndex('abc', 3, 8));
  // Tab bis Spalte 9 (Breite 8), danach das 'x'.
  Assert.AreEqual(1, TLspSession.ColumnToIndex(#9'x', 9, 8));
  Assert.AreEqual(2, TLspSession.ColumnToIndex('a'#9'x', 3, 2));
  // Hinter dem Zeilenende: Länge der Zeile.
  Assert.AreEqual(3, TLspSession.ColumnToIndex('abc', 20, 8));
end;

procedure TLspSessionTests.SendsOpenOnceAndChangeOnlyWhenTextChanged;
var
  Client: TLspClient;
  Session: TLspSession;
  Methods: TList<string>;
begin
  Methods := TList<string>.Create;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
      Method, Version: string;
    begin
      Message := Unframe(ABytes);
      try
        Method := Message.GetValue<string>('method');
        Version := Message.GetValue<string>('params.textDocument.version', '');
        Methods.Add(Method + ':' + Version);
      finally
        Message.Free;
      end;
    end);
  Session := TLspSession.Create(Client);
  try
    Session.Sync('C:\P\A.pas', 'unit A;');
    Session.Sync('c:\p\a.pas', 'unit A;');
    Session.Sync('C:\P\A.pas', 'unit A; ');
    Assert.AreEqual(2, Integer(Methods.Count));
    Assert.AreEqual('textDocument/didOpen:1', Methods[0]);
    Assert.AreEqual('textDocument/didChange:2', Methods[1]);
  finally
    Session.Free;
    Client.Free;
    Methods.Free;
  end;
end;

{ TLspServerProcessTests }

procedure TLspServerProcessTests.HoverAndDefinitionAgainstServer;
const
  UnitText =
    'unit Probe;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '    FWert: Integer;'#13#10 +
    '    procedure Setze;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.Setze;'#13#10 +
    'begin'#13#10 +
    '  FWert := 1;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  ServerExe, FileName: string;
  Server: TLspServerProcess;
  Session: TLspSession;
  Location: TLspLocation;
begin
  ServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'ArgusServer.exe');
  if not FileExists(ServerExe) then
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + ServerExe);
  FileName := TPath.Combine(TPath.GetTempPath, 'ArgusPluginProbe.pas');
  Server := TLspServerProcess.Create(ServerExe, '');
  try
    Session := TLspSession.Create(Server.Client, 5000);
    try
      Session.Initialize;
      Assert.IsTrue(Server.Running);
      Assert.AreEqual('FWert: Integer;', Session.Hover(FileName, UnitText, 10, 3));
      Assert.IsTrue(Session.Definition(FileName, UnitText, 10, 3, Location));
      Assert.AreEqual(4, Location.Line);
      Assert.IsTrue(SameText(FileName, Location.FileName), Location.FileName);
    finally
      Session.Free;
    end;
  finally
    Server.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspClientTests);
  TDUnitX.RegisterTestFixture(TLspSessionTests);
  TDUnitX.RegisterTestFixture(TLspServerProcessTests);

end.
