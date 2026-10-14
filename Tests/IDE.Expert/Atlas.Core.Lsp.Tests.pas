unit Atlas.Core.Lsp.Tests;

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
    [Test]
    procedure ForwardsServerMessagesToHandler;
    [Test]
    procedure RoutesPartialResultsToRequest;
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
    [Test]
    procedure ClosesSyncedDocumentsAndListsThem;
    [Test]
    procedure InitializeAnnouncesPullDiagnosticsAndCountsRefresh;
    [Test]
    procedure ReportsProjectGroupChanges;
    [Test]
    procedure ReopensDocumentsOfPreviousSession;
    [Test]
    procedure SendsOnlyTheChangedRange;
    [Test]
    procedure ReportsWatchedFilesExceptSyncedChanges;
  end;

  [TestFixture]
  TLspTextChangesTests = class
  public
    [Test]
    procedure RangeCoversOnlyTheDifference;
    [Test]
    procedure NeverSplitsLineBreaksOrSurrogates;
    [Test]
    procedure AppliedChangeGivesNewText;
  end;

  [TestFixture]
  TLspServerProcessTests = class
  public
    // Startet den echten Server neben dem Testprogramm.
    [Test]
    [IgnoreMemoryLeaks]
    procedure HoverAndDefinitionAgainstServer;
    [Test]
    procedure PullsDiagnosticsAgainstServer;
    [Test]
    procedure CompilerMessagesReachPulledDiagnostics;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.Adapters.ServerProcess,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Files.WatchedChanges,
  Atlas.Core.Problems.Contract;

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

procedure TLspClientTests.ForwardsServerMessagesToHandler;
var
  Client: TLspClient;
  Sent, Seen: TList<string>;
  Incoming: TBytes;
begin
  Sent := TList<string>.Create;
  Seen := TList<string>.Create;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
      Sent.Add(TEncoding.UTF8.GetString(ABytes));
    end);
  try
    Client.OnServerMessage :=
      procedure(const AMethod: string; const AParams: TJSONValue)
      begin
        if AParams <> nil then
          Seen.Add(AMethod + ' ' + AParams.ToJSON)
        else
          Seen.Add(AMethod);
      end;
    Incoming := TLspClient.Frame('{"jsonrpc":"2.0","id":"r1","method":"workspace/diagnostic/refresh"}') +
      TLspClient.Frame('{"jsonrpc":"2.0","method":"window/logMessage","params":{"type":3}}');
    Client.Receive(Incoming, Length(Incoming));
    Assert.AreEqual(2, Integer(Seen.Count));
    Assert.AreEqual('workspace/diagnostic/refresh', Seen[0]);
    Assert.AreEqual('window/logMessage {"type":3}', Seen[1]);
    Assert.AreEqual(1, Integer(Sent.Count), 'Anfrage weiter mit null beantwortet');
  finally
    Client.Free;
    Seen.Free;
    Sent.Free;
  end;
end;

procedure TLspClientTests.RoutesPartialResultsToRequest;
var
  Client: TLspClient;
  Partials, Seen: TList<string>;
  Response: TJSONValue;
  Params: TJSONObject;
begin
  // #616: $/progress zum partialResultToken geht an die Anfrage, vor der Antwort; andere Tokens nicht.
  Partials := TList<string>.Create;
  Seen := TList<string>.Create;
  Client := nil;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Request: TJSONObject;
      Reply: TBytes;
      Id: Integer;
      Token: string;
    begin
      Request := Unframe(ABytes);
      try
        Id := Request.GetValue<Integer>('id');
        Token := Request.GetValue<string>('params.partialResultToken');
      finally
        Request.Free;
      end;
      Reply := TLspClient.Frame(Format('{"jsonrpc":"2.0","method":"$/progress","params":{"token":"%s","value":[1]}}',
        [Token])) +
        TLspClient.Frame('{"jsonrpc":"2.0","method":"$/progress","params":{"token":"fremd","value":{"kind":"end"}}}') +
        TLspClient.Frame(Format('{"jsonrpc":"2.0","method":"$/progress","params":{"token":"%s","value":[2,3]}}',
        [Token])) +
        TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":[4]}', [Id]));
      Client.Receive(Reply, Length(Reply));
    end);
  try
    Client.OnServerMessage :=
      procedure(const AMethod: string; const AParams: TJSONValue)
      begin
        Seen.Add(AMethod);
      end;
    Params := TJSONObject.Create;
    Response := Client.Request('textDocument/completion', Params, 1000,
      procedure(const AValue: TJSONValue)
      begin
        Partials.Add(AValue.ToJSON);
      end);
    try
      Assert.AreEqual('[4]', Response.ToJSON);
    finally
      Response.Free;
    end;
    Assert.AreEqual(2, Integer(Partials.Count));
    Assert.AreEqual('[1]', Partials[0]);
    Assert.AreEqual('[2,3]', Partials[1]);
    Assert.AreEqual(1, Integer(Seen.Count), 'Fremder Fortschritt geht an OnServerMessage');
  finally
    Client.Free;
    Seen.Free;
    Partials.Free;
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
  Hover := TJSONObject.ParseJSONValue('{"contents":"x","atlas":{"declaration":"procedure BeginUpdate;",' +
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

procedure TLspSessionTests.ClosesSyncedDocumentsAndListsThem;
var
  Client: TLspClient;
  Session: TLspSession;
  Methods: TList<string>;
  Text: string;
begin
  Methods := TList<string>.Create;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
    begin
      Message := Unframe(ABytes);
      try
        Methods.Add(Message.GetValue<string>('method') + ' ' + Message.GetValue<string>('params.textDocument.uri', ''));
      finally
        Message.Free;
      end;
    end);
  Session := TLspSession.Create(Client);
  try
    Session.Sync('C:\P\A.pas', 'unit A;');
    Session.Sync('C:\P\B.pas', 'unit B;');
    Assert.AreEqual(2, Integer(Length(Session.SyncedFiles)));
    Assert.IsTrue(Session.SyncedText('c:\p\b.pas', Text));
    Assert.AreEqual('unit B;', Text);
    Session.Close('c:\p\a.pas');
    Session.Close('C:\P\X.pas');
    Assert.AreEqual(3, Integer(Methods.Count), 'nur eine didClose');
    Assert.AreEqual('textDocument/didClose file:///c%3A/p/a.pas', Methods[2]);
    Assert.AreEqual(1, Integer(Length(Session.SyncedFiles)));
    Assert.AreEqual('C:\P\B.pas', Session.SyncedFiles[0]);
    Assert.IsFalse(Session.SyncedText('C:\P\A.pas', Text));
    // Nach didClose wieder didOpen.
    Session.Sync('C:\P\A.pas', 'unit A;');
    Assert.StartsWith('textDocument/didOpen', Methods[3]);
  finally
    Session.Free;
    Client.Free;
    Methods.Free;
  end;
end;

procedure TLspSessionTests.ReopensDocumentsOfPreviousSession;
var
  Client: TLspClient;
  Previous, Fresh: TLspSession;
  Messages: TList<string>;
  Documents: TArray<TLspOpenDocument>;
begin
  Messages := TList<string>.Create;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
    begin
      Message := Unframe(ABytes);
      try
        Messages.Add(Message.GetValue<string>('method') + ' ' +
          Message.GetValue<string>('params.textDocument.uri', '') + ' ' +
          Message.GetValue<string>('params.textDocument.text', ''));
      finally
        Message.Free;
      end;
    end);
  Previous := TLspSession.Create(Client);
  Fresh := TLspSession.Create(Client);
  try
    Previous.Sync('C:\P\A.pas', 'unit A;');
    Previous.Sync('C:\P\B.pas', 'unit B;');
    // Ungespeicherter Stand: Der neue Server muss den zuletzt geschickten Text bekommen.
    Previous.Sync('C:\P\B.pas', 'unit B; // neu');
    Documents := Previous.OpenDocuments;
    Assert.AreEqual(2, Integer(Length(Documents)));
    Messages.Clear;
    // A ist in der neuen Sitzung schon abgeglichen und bleibt unverändert.
    Fresh.Sync('C:\P\A.pas', 'unit A; // getippt');
    Fresh.Reopen(Documents);
    Assert.AreEqual(2, Integer(Messages.Count));
    Assert.AreEqual('textDocument/didOpen file:///c%3A/p/b.pas unit B; // neu', Messages[1]);
    Assert.AreEqual(2, Integer(Length(Fresh.SyncedFiles)));
  finally
    Fresh.Free;
    Previous.Free;
    Client.Free;
    Messages.Free;
  end;
end;

procedure TLspSessionTests.SendsOnlyTheChangedRange;
var
  Client: TLspClient;
  Session: TLspSession;
  Changes: TList<string>;
begin
  Changes := TList<string>.Create;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
      Change: TJSONObject;
    begin
      Message := Unframe(ABytes);
      try
        if Message.GetValue<string>('method') = 'textDocument/didChange' then
        begin
          Change := Message.GetValue<TJSONArray>('params.contentChanges').Items[0] as TJSONObject;
          Changes.Add(Format('%d:%d-%d:%d "%s"', [Change.GetValue<Integer>('range.start.line'),
            Change.GetValue<Integer>('range.start.character'), Change.GetValue<Integer>('range.end.line'),
            Change.GetValue<Integer>('range.end.character'), Change.GetValue<string>('text')]));
        end;
      finally
        Message.Free;
      end;
    end);
  Session := TLspSession.Create(Client);
  try
    Session.Sync('C:\P\A.pas', 'unit A;'#13#10'begin'#13#10'end.');
    Session.Sync('C:\P\A.pas', 'unit A;'#13#10'begin'#13#10'  X;'#13#10'end.');
    Session.Sync('C:\P\A.pas', 'unit A;'#13#10'begin'#13#10'end.');
    Assert.AreEqual(2, Integer(Changes.Count));
    Assert.AreEqual('2:0-2:0 "  X;'#13#10'"', Changes[0]);
    Assert.AreEqual('2:0-3:0 ""', Changes[1]);
  finally
    Session.Free;
    Client.Free;
    Changes.Free;
  end;
end;

procedure TLspSessionTests.ReportsWatchedFilesExceptSyncedChanges;
var
  Client: TLspClient;
  Session: TLspSession;
  Messages: TList<string>;
begin
  Messages := TList<string>.Create;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
      Item: TJSONValue;
      Line: string;
    begin
      Message := Unframe(ABytes);
      try
        if Message.GetValue<string>('method') = 'workspace/didChangeWatchedFiles' then
        begin
          Line := '';
          for Item in Message.GetValue<TJSONArray>('params.changes') do
            Line := Line + Item.GetValue<string>('uri') + '=' + Item.GetValue<string>('type') + ' ';
          Messages.Add(Line);
        end;
      finally
        Message.Free;
      end;
    end);
  Session := TLspSession.Create(Client);
  try
    Session.Sync('C:\P\Open.pas', 'unit Open;');
    // Nur die offene Datei geändert: Ihr Editortext gilt, nichts zu melden.
    Session.FilesChanged([TAtlasFileChange.Create('c:\p\open.pas', TAtlasFileChangeKind.Changed)]);
    Assert.AreEqual(0, Integer(Messages.Count));
    Session.FilesChanged([TAtlasFileChange.Create('C:\P\Open.pas', TAtlasFileChangeKind.Changed),
      TAtlasFileChange.Create('C:\P\B.pas', TAtlasFileChangeKind.Changed),
      TAtlasFileChange.Create('C:\P\Open.pas', TAtlasFileChangeKind.Deleted),
      TAtlasFileChange.Create('C:\P\N.pas', TAtlasFileChangeKind.Created)]);
    Assert.AreEqual(1, Integer(Messages.Count));
    Assert.AreEqual('file:///c%3A/p/b.pas=2 file:///c%3A/p/open.pas=3 file:///c%3A/p/n.pas=1 ', Messages[0]);
  finally
    Session.Free;
    Client.Free;
    Messages.Free;
  end;
end;

procedure TLspSessionTests.InitializeAnnouncesPullDiagnosticsAndCountsRefresh;
var
  Client: TLspClient;
  Session: TLspSession;
  Capabilities: string;
begin
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
      Reply: TBytes;
    begin
      Message := Unframe(ABytes);
      try
        if Message.GetValue<string>('method', '') = 'initialize' then
        begin
          Capabilities := Message.GetValue<TJSONObject>('params.capabilities').ToJSON;
          Reply := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":{"capabilities":{}}}',
            [Message.GetValue<Integer>('id')]));
          Client.Receive(Reply, Length(Reply));
        end;
      finally
        Message.Free;
      end;
    end);
  Session := TLspSession.Create(Client);
  try
    Session.Initialize;
    Assert.Contains(Capabilities, '"diagnostic":{"dynamicRegistration":false');
    // Seit #648 meldet der Client unter "workspace" auch workspaceFolders; geprüft wird nur refreshSupport.
    Assert.Contains(Capabilities, '"diagnostics":{"refreshSupport":true}');
    Assert.AreEqual(0, Session.RefreshCount);
    Client.Receive(TLspClient.Frame('{"jsonrpc":"2.0","id":"r1","method":"workspace/diagnostic/refresh"}'),
      Length(TLspClient.Frame('{"jsonrpc":"2.0","id":"r1","method":"workspace/diagnostic/refresh"}')));
    Assert.AreEqual(1, Session.RefreshCount);
  finally
    Session.Free;
    Client.Free;
  end;
end;

procedure TLspSessionTests.ReportsProjectGroupChanges;
var
  Folders: TJSONArray;
  Added, Removed: TArray<string>;
begin
  Folders := TLspSession.ProjectFolders(['C:\Gruppe\App\App.dproj']);
  try
    Assert.AreEqual(1, Folders.Count);
    Assert.AreEqual(TLspSession.PathToUri('C:\Gruppe\App\App.dproj'), Folders.Items[0].GetValue<string>('uri'));
    Assert.AreEqual('App', Folders.Items[0].GetValue<string>('name'));
  finally
    Folders.Free;
  end;
  // Groß- und Kleinschreibung zählt nicht; Doppelte nur einmal.
  TLspSession.ProjectChanges(['C:\G\A.dproj', 'C:\G\B.dproj'], ['c:\g\a.dproj', 'C:\G\C.dproj', 'C:\G\C.dproj'],
    Added, Removed);
  Assert.AreEqual<NativeInt>(1, Length(Added));
  Assert.AreEqual('C:\G\C.dproj', Added[0]);
  Assert.AreEqual<NativeInt>(1, Length(Removed));
  Assert.AreEqual('C:\G\B.dproj', Removed[0]);
  TLspSession.ProjectChanges(['C:\G\A.dproj'], ['C:\G\A.dproj'], Added, Removed);
  Assert.AreEqual<NativeInt>(0, Length(Added) + Length(Removed));
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
  ServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe');
  if not FileExists(ServerExe) then
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + ServerExe);
  FileName := TPath.Combine(TPath.GetTempPath, 'AtlasPluginProbe.pas');
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

procedure TLspServerProcessTests.PullsDiagnosticsAgainstServer;
const
  UnitText =
    'unit ProbeFehler;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  if then'#13#10 +
    'end;'#13#10 +
    'end.';
var
  ServerExe, FileName: string;
  Server: TLspServerProcess;
  Session: TLspSession;
  Report, Again: TLspDiagnosticReport;
begin
  ServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe');
  if not FileExists(ServerExe) then
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + ServerExe);
  FileName := TPath.Combine(TPath.GetTempPath, 'AtlasPluginProbeFehler.pas');
  Server := TLspServerProcess.Create(ServerExe, '');
  try
    Session := TLspSession.Create(Server.Client, 5000);
    try
      Session.Initialize;
      Session.Sync(FileName, UnitText);
      Report := Session.DocumentDiagnostics(FileName, '', 10000);
      Assert.IsFalse(Report.Unchanged);
      Assert.IsTrue(Length(Report.Problems) > 0, 'Syntaxfehler gemeldet');
      Assert.IsTrue(Report.Problems[0].Severity = TAtlasProblemSeverity.Error);
      Assert.AreEqual(5, Report.Problems[0].StartLine);
      Assert.AreNotEqual('', Report.ResultId);
      Again := Session.DocumentDiagnostics(FileName, Report.ResultId, 10000);
      Assert.IsTrue(Again.Unchanged, 'gleiche Version: unverändert');
    finally
      Session.Free;
    end;
  finally
    Server.Free;
  end;
end;

procedure TLspServerProcessTests.CompilerMessagesReachPulledDiagnostics;
const
  UnitText =
    'unit ProbeCompiler;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  Gibtsnicht.Create;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  ServerExe, FileName: string;
  Server: TLspServerProcess;
  Session: TLspSession;
  Report: TLspDiagnosticReport;
  Params: TJSONObject;
  Waited: Integer;
  Problem: TAtlasProblem;
  Found: Boolean;
begin
  ServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe');
  if not FileExists(ServerExe) then
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + ServerExe);
  FileName := TPath.Combine(TPath.GetTempPath, 'AtlasPluginProbeCompiler.pas');
  Server := TLspServerProcess.Create(ServerExe, '');
  try
    Session := TLspSession.Create(Server.Client, 5000);
    try
      Session.Initialize;
      Session.Sync(FileName, UnitText);
      Params := TJSONObject.ParseJSONValue(Format('{"project":"","platform":"Win32","success":false,"background":true,' +
        '"messages":[{"file":"%s","line":6,"column":3,"severity":"error","code":"E2003",' +
        '"text":"Undeklarierter Bezeichner: ''Gibtsnicht''"}]}', [StringReplace(FileName, '\', '\\', [rfReplaceAll])]))
        as TJSONObject;
      Session.Notify('atlas/compilerMessages', Params);
      // Der Server bittet danach um neues Holen.
      Waited := 0;
      while (Session.RefreshCount = 0) and (Waited < 5000) do
      begin
        Sleep(50);
        Inc(Waited, 50);
      end;
      Assert.AreEqual(1, Session.RefreshCount, 'workspace/diagnostic/refresh');
      Report := Session.DocumentDiagnostics(FileName, '', 10000);
      Found := False;
      for Problem in Report.Problems do
        if Problem.IsCompiler and (Problem.Code = 'E2003') then
        begin
          Found := True;
          Assert.AreEqual(5, Problem.StartLine);
          Assert.IsTrue(Problem.Severity = TAtlasProblemSeverity.Error);
        end;
      Assert.IsTrue(Found, 'dcc-Meldung in den Diagnosen der geöffneten Datei');
    finally
      Session.Free;
    end;
  finally
    Server.Free;
  end;
end;

{ TLspTextChangesTests }

function Applied(const AOld: string; const AChange: TLspTextChange): string;
var
  StartOffset, EndOffset: Integer;
begin
  StartOffset := TLspTextChanges.OffsetOf(AOld, AChange.StartPos);
  EndOffset := TLspTextChanges.OffsetOf(AOld, AChange.EndPos);
  Result := Copy(AOld, 1, StartOffset) + AChange.Text + Copy(AOld, EndOffset + 1, MaxInt);
end;

function RangeText(const AChange: TLspTextChange): string;
begin
  Result := Format('%d:%d-%d:%d "%s"', [AChange.StartPos.Line, AChange.StartPos.Character, AChange.EndPos.Line,
    AChange.EndPos.Character, AChange.Text]);
end;

procedure TLspTextChangesTests.RangeCoversOnlyTheDifference;
begin
  Assert.AreEqual('0:5-0:5 "X"', RangeText(TLspTextChanges.Between('unit A;', 'unit XA;')));
  Assert.AreEqual('1:1-1:2 ""', RangeText(TLspTextChanges.Between('a'#13#10'bcd', 'a'#13#10'bd')));
  Assert.AreEqual('0:0-0:0 "x"', RangeText(TLspTextChanges.Between('', 'x')));
  Assert.AreEqual('0:3-0:3 ""', RangeText(TLspTextChanges.Between('abc', 'abc')));
  // Lone CR und LF zählen wie beim Server als Zeilenende.
  Assert.AreEqual('2:0-2:1 "Y"', RangeText(TLspTextChanges.Between('a'#13'b'#10'X', 'a'#13'b'#10'Y')));
end;

procedure TLspTextChangesTests.NeverSplitsLineBreaksOrSurrogates;
var
  Change: TLspTextChange;
begin
  // CR bleibt gleich, LF wird zu "X"#10: Der Bereich darf nicht zwischen CR und LF beginnen.
  Change := TLspTextChanges.Between('a'#13#10'b', 'a'#13'X'#10'b');
  Assert.AreEqual('0:1-1:0 "'#13'X'#10'"', RangeText(Change));
  // Vor dem gleichen Ende "\n..." steht im alten Text CR: das LF gehört in den Bereich.
  Change := TLspTextChanges.Between('a'#13#10'b', 'aZ'#10'b');
  Assert.AreEqual('aZ'#10'b', Applied('a'#13#10'b', Change));
  Assert.AreEqual(0, Change.StartPos.Line);
  Assert.AreEqual(1, Change.EndPos.Line);
  // Zwei Emojis mit gleichem hohem Surrogat: nicht in der Mitte eines Paars trennen.
  Change := TLspTextChanges.Between('x'#$D83D#$DE00, 'x'#$D83D#$DE01);
  Assert.AreEqual('0:1-0:3 "'#$D83D#$DE01'"', RangeText(Change));
end;

procedure TLspTextChangesTests.AppliedChangeGivesNewText;
const
  Alphabet = 'ab'#13#10'x';
var
  Round, Index: Integer;
  Old, New_: string;

  function RandomText(ALength: Integer): string;
  var
    Position: Integer;
  begin
    Result := '';
    for Position := 1 to ALength do
      Result := Result + Alphabet[Random(Length(Alphabet)) + 1];
  end;

begin
  RandSeed := 395;
  for Round := 1 to 5000 do
  begin
    Old := RandomText(Random(12));
    Index := Random(Length(Old) + 1);
    New_ := Copy(Old, 1, Index) + RandomText(Random(4)) + Copy(Old, Index + Random(3) + 1, MaxInt);
    Assert.AreEqual(New_, Applied(Old, TLspTextChanges.Between(Old, New_)), Format('%d: "%s" -> "%s"', [Round, Old, New_]));
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspClientTests);
  TDUnitX.RegisterTestFixture(TLspTextChangesTests);
  TDUnitX.RegisterTestFixture(TLspSessionTests);
  TDUnitX.RegisterTestFixture(TLspServerProcessTests);

end.
