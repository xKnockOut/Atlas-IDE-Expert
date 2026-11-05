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
    /// <summary>RequestCancellable (#1351): Abbruch schickt $/cancelRequest und wartet nicht bis zum Zeitlimit;
    /// ohne Abbruch kommt die Antwort.</summary>
    [Test]
    procedure CancellableRequestSendsCancel;
    /// <summary>Ende der Verbindung mit letzter und offenen Anfragen und den Angaben des Transports (Bericht H5).
    /// </summary>
    [Test]
    procedure CloseInfoNamesLastAndOpenRequests;
    [Test]
    procedure ForwardsServerMessagesToHandler;
    [Test]
    procedure RoutesPartialResultsToRequest;
    /// <summary>Obergrenzen der Rahmung (Code-Review D-10).</summary>
    [Test]
    procedure RejectsOversizedContentLength;
    [Test]
    procedure RejectsHeaderWithoutEnd;
    [Test]
    procedure AcceptsMessageAtHeaderLimit;
    /// <summary>Diagnose-Fenster (2.0-stable): Serverbefehle stehen je Befehl, nicht alle unter
    /// workspace/executeCommand.</summary>
    [Test]
    procedure TimingNamesExecutedCommand;
  end;

  [TestFixture]
  TLspSessionTests = class
  public
    /// <summary>Erste Benutzung (VCL, Codepages, RTTI) ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
    /// <summary>#1247: Stand der Projektprüfung aus der Antwort auf workspace/diagnostic.</summary>
    [Test]
    procedure ReadsWorkspaceRun;
    [Test]
    procedure ReportsProjectGroupChanges;
    [Test]
    procedure ReopensDocumentsOfPreviousSession;
    [Test]
    procedure SendsOnlyTheChangedRange;
    [Test]
    procedure ReportsWatchedFilesExceptSyncedChanges;
    [Test]
    procedure PreparesAndRequestsRename;
    [Test]
    procedure SendsProjectContextsInInitializeAndOnChange;
    [Test]
    procedure AcceptsApplyEditAndRepliesLater;
    /// <summary>Antwortet niemand, gibt die Sitzung die Id frei (Code-Review S-07).</summary>
    [Test]
    procedure FreesApplyEditIdWithoutReply;
    [Test]
    procedure RepliesToApplyEditOnlyOnce;
    [Test]
    procedure ReadsParameterInlayHints;
    [Test]
    procedure ReadsImplementationsAndSymbols;
    [Test]
    procedure WalksCallAndTypeHierarchies;
    [Test]
    procedure ReadsCodeActionsAndRunsCommands;
    [Test]
    procedure RequestsTypingSelectionAndTypeDefinition;
    /// <summary>#43: formatting für die Datei, rangeFormatting mit Bereich.</summary>
    [Test]
    procedure RequestsFormatting;
    /// <summary>#658: linkedEditingRange mit "atlasLocals", Antwort unverändert an den Aufrufer.</summary>
    [Test]
    procedure RequestsLinkedLocals;
    [Test]
    procedure RequestsDeclarationsAndDefinitions;
    [Test]
    procedure MapsIndexBackToColumn;
    [Test]
    procedure WrapsServerSettings;
    [Test]
    procedure ReadsShowMessageParams;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.SyncObjs,
  System.Diagnostics,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Files.WatchedChanges,
  Atlas.Core.Projects.Contract,
  Atlas.Core.InlayHints.Store,
  Atlas.Core.Results.Model,
  Atlas.Core.Diagnostics.PluginTimings;

// Liest die JSON-Nachricht aus gerahmten Bytes.
function Unframe(const ABytes: TBytes): TJSONObject;
var
  Text: string;
begin
  Text := TEncoding.UTF8.GetString(ABytes);
  Result := TJSONObject.ParseJSONValue(Text.Substring(Text.IndexOf(#13#10#13#10) + 4)) as TJSONObject;
end;
/// <summary>Client, der Gesendetes in ASent sammelt; antwortet auf initialize.</summary>
function ApplyEditClient(ASent: TList<string>): TLspClient;
var
  Client: TLspClient;
begin
  Client := nil;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
      Answer: TBytes;
    begin
      Message := Unframe(ABytes);
      try
        if Message.GetValue<string>('method', '') = 'initialize' then
        begin
          Answer := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":{"capabilities":{}}}',
            [Message.GetValue<Integer>('id')]));
          Client.Receive(Answer, Length(Answer));
        end
        else if Message.GetValue('method') = nil then
        begin
          ASent.Add(Message.ToJSON);
        end;
      finally
        Message.Free;
      end;
    end);
  Result := Client;
end;

const
  ApplyEditRequest = '{"jsonrpc":"2.0","id":7,"method":"workspace/applyEdit","params":{"edit":' +
    '{"changes":{"file:///c%3A/p/a.pas":[{"range":{"start":{"line":0,"character":0},' +
    '"end":{"line":0,"character":1}},"newText":"b"}]}}}}';

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
      begin
        Client.Receive(Copy(Reply, Index, 1), 1);
      end;
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
procedure TLspClientTests.TimingNamesExecutedCommand;
var
  mClient: TLspClient;
  mTiming: TAtlasRequestTiming;
  mNames: string;
begin
  mClient := nil;
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      mRequest: TJSONObject;
      mId: Integer;
      mReply: TBytes;
    begin
      mRequest := Unframe(ABytes);
      try
        mId := mRequest.GetValue<Integer>('id');
      finally
        mRequest.Free;
      end;
      mReply := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":null}', [mId]));
      mClient.Receive(mReply, Length(mReply));
    end);
  TAtlasPluginTimings.Shared.Reset;
  TAtlasPluginTimings.Enabled := True;
  try
    mClient.Request('workspace/executeCommand',
      TJSONObject.ParseJSONValue('{"command":"atlas.server.status","arguments":[]}'), 1000).Free;
    mNames := '';
    for mTiming in TAtlasPluginTimings.Shared.Snapshot.Requests do
    begin
      mNames := mNames + mTiming.Method + '|';
    end;
    Assert.AreEqual('workspace/executeCommand atlas.server.status|', mNames);
  finally
    TAtlasPluginTimings.Enabled := False;
    TAtlasPluginTimings.Shared.Reset;
    mClient.Free;
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
        begin
          Seen.Add(AMethod + ' ' + AParams.ToJSON);
        end
        else
        begin
          Seen.Add(AMethod);
        end;
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
procedure TLspClientTests.CancellableRequestSendsCancel;
var
  Client: TLspClient;
  Sent: TList<string>;
  Watch: TStopwatch;
  Calls: Integer;
begin
  Sent := TList<string>.Create;
  Client := nil;
  try
    Client := TLspClient.Create(
      procedure(const ABytes: TBytes)
      var
        Request: TJSONObject;
      begin
        Request := Unframe(ABytes);
        try
          Sent.Add(Request.GetValue<string>('method'));
        finally
          Request.Free;
        end;
      end);
    Calls := 0;
    Watch := TStopwatch.StartNew;
    Assert.WillRaise(
      procedure
      begin
        Client.RequestCancellable('atlas/query', nil, 10000,
          function: Boolean
          begin
            Inc(Calls);
            Result := Calls >= 2;
          end).Free;
      end, ELspCancelledError);
    Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, 'wartet bis zum Zeitlimit');
    Assert.AreEqual('atlas/query,$/cancelRequest', string.Join(',', Sent.ToArray));
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
/// <summary>Anfrage in einem eigenen Thread; endet mit dem Schließen des Clients.</summary>
function RequestInThread(AClient: TLspClient; const AMethod: string): TThread;
var
  Client: TLspClient;
  Method: string;
begin
  Client := AClient;
  Method := AMethod;
  Result := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        Client.Request(Method, nil, 10000).Free;
      except
        // Erwartet: Die Verbindung wird geschlossen, während die Anfrage wartet.
        on ELspClientError do
          ;
      end;
    end);
  Result.FreeOnTerminate := False;
  Result.Start;
end;
/// <summary>Client, der nie antwortet und das Senden von definition und diagnostic meldet.</summary>
function CreateSilentClient(const ADefinitionSent, ADiagnosticSent: TEvent): TLspClient;
begin
  Result := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
    begin
      // Nie antworten: Beide Anfragen sind beim Ende noch offen.
      Message := Unframe(ABytes);
      try
        if Message.GetValue<string>('method', '') = 'textDocument/definition' then
        begin
          ADefinitionSent.SetEvent;
        end
        else if Message.GetValue<string>('method', '') = 'workspace/diagnostic' then
        begin
          ADiagnosticSent.SetEvent;
        end;
      finally
        Message.Free;
      end;
    end);
end;
procedure TLspClientTests.CloseInfoNamesLastAndOpenRequests;
var
  Client: TLspClient;
  DefinitionSent, DiagnosticSent: TEvent;
  Definition, Diagnostic: TThread;
  Ended, Info: TLspCloseInfo;
begin
  DefinitionSent := TEvent.Create(nil, True, False, '');
  DiagnosticSent := TEvent.Create(nil, True, False, '');
  Client := CreateSilentClient(DefinitionSent, DiagnosticSent);
  Definition := nil;
  Diagnostic := nil;
  try
    Info := Client.CloseInfo;
    Assert.AreEqual('', Info.LastMethod, 'offen: noch nichts');
    Definition := RequestInThread(Client, 'textDocument/definition');
    Assert.AreEqual(Ord(wrSignaled), Ord(DefinitionSent.WaitFor(5000)));
    // Long-Polling zählt weder als letzte noch als offene Anfrage.
    Diagnostic := RequestInThread(Client, 'workspace/diagnostic');
    Assert.AreEqual(Ord(wrSignaled), Ord(DiagnosticSent.WaitFor(5000)));
    Ended := Default(TLspCloseInfo);
    Ended.ExitKnown := True;
    Ended.ExitCode := $C00000FD;
    Ended.RuntimeMs := 1234;
    Ended.ErrorLines := 3;
    Client.CloseWith(Ended);
    Definition.WaitFor;
    Diagnostic.WaitFor;
    Info := Client.CloseInfo;
    Assert.IsTrue(Info.ExitKnown);
    Assert.AreEqual(Int64($C00000FD), Int64(Info.ExitCode));
    Assert.AreEqual(Int64(1234), Info.RuntimeMs);
    Assert.AreEqual(3, Info.ErrorLines);
    Assert.AreEqual('textDocument/definition', Info.LastMethod);
    Assert.AreEqual(1, Integer(Length(Info.OpenMethods)));
    Assert.AreEqual('textDocument/definition', Info.OpenMethods[0]);
    // Nur das erste Schließen zählt.
    Client.Close;
    Assert.AreEqual(Int64($C00000FD), Int64(Client.CloseInfo.ExitCode));
  finally
    Definition.Free;
    Diagnostic.Free;
    Client.Free;
    DefinitionSent.Free;
    DiagnosticSent.Free;
  end;
end;
{ TLspSessionTests }

procedure TLspSessionTests.WarmUpFirstUse;
begin
  AcceptsApplyEditAndRepliesLater;
end;
procedure TLspSessionTests.ConvertsPathsAndUris;
begin
  Assert.AreEqual('file:///c%3A/Mein%20Projekt/%C3%9Cbung.pas', TLspSession.PathToUri('C:\Mein Projekt\Übung.pas'));
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
  // Seit #654: documentation strukturiert, Klartext in documentationText.
  Hover := TJSONObject.ParseJSONValue('{"contents":"x","atlas":{"declaration":"procedure BeginUpdate;",' +
    '"documentation":{"sections":[]},"documentationText":"Unterdrückt das Neuzeichnen."}}');
  try
    Assert.AreEqual('Unterdrückt das Neuzeichnen.', TLspHoverParts.FromHover(Hover).Documentation);
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
          begin
            Line := Line + Item.GetValue<string>('uri') + '=' + Item.GetValue<string>('type') + ' ';
          end;
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
procedure TLspSessionTests.PreparesAndRequestsRename;
var
  Client: TLspClient;
  Session: TLspSession;
  PrepareReply, NewName: string;
  Placeholder: string;
  Response: TJSONValue;
begin
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
      Method, Answer: string;
      Reply: TBytes;
    begin
      Message := Unframe(ABytes);
      try
        Method := Message.GetValue<string>('method', '');
        if Method = 'textDocument/prepareRename' then
        begin
          Answer := PrepareReply;
        end
        else if Method = 'textDocument/rename' then
        begin
          NewName := Message.GetValue<string>('params.newName');
          Answer := '{"changes":{}}';
        end
        else
        begin
          Exit;
        end;
        Reply := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":%s}',
          [Message.GetValue<Integer>('id'), Answer]));
        Client.Receive(Reply, Length(Reply));
      finally
        Message.Free;
      end;
    end);
  Session := TLspSession.Create(Client);
  try
    PrepareReply := '{"range":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}},"placeholder":"Alt"}';
    Assert.IsTrue(Session.PrepareRename('C:\P\A.pas', 'unit Foo;', 0, 6, Placeholder));
    Assert.AreEqual('Alt', Placeholder);
    // Nur ein Bereich: Der Name kommt aus dem Text.
    PrepareReply := '{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}';
    Assert.IsTrue(Session.PrepareRename('C:\P\A.pas', 'unit Foo;', 0, 6, Placeholder));
    Assert.AreEqual('Foo', Placeholder);
    PrepareReply := 'null';
    Assert.IsFalse(Session.PrepareRename('C:\P\A.pas', 'unit Foo;', 0, 0, Placeholder));
    Response := Session.Rename('C:\P\A.pas', 0, 6, 'Neu', 1000);
    try
      Assert.AreEqual('Neu', NewName);
      Assert.IsTrue(Response is TJSONObject);
    finally
      Response.Free;
    end;
  finally
    Session.Free;
    Client.Free;
  end;
end;
procedure TLspSessionTests.ReadsParameterInlayHints;
var
  Client: TLspClient;
  Session: TLspSession;
  Range: string;
  Hints: TArray<TAtlasInlayHint>;
begin
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
      Reply: TBytes;
    begin
      Message := Unframe(ABytes);
      try
        if Message.GetValue<string>('method', '') = 'textDocument/inlayHint' then
        begin
          Range := Message.GetValue<Integer>('params.range.start.line').ToString + '-' +
            Message.GetValue<Integer>('params.range.end.line').ToString;
          Reply := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":[' +
            '{"position":{"line":3,"character":9},"label":"AWert:","kind":2,"paddingRight":true},' +
            '{"position":{"line":4,"character":2},"label":": Integer","kind":1},' +
            '{"position":{"line":5,"character":7},"label":[{"value":"AName"},{"value":":"}],"kind":2},' +
            '{"position":{"line":8,"character":6},"label":"// TKunde.Speichern","paddingLeft":true},' +
            '{"position":{"line":9,"character":1},"label":"ohne Art"}]}',
            [Message.GetValue<Integer>('id')]));
          Client.Receive(Reply, Length(Reply));
        end;
      finally
        Message.Free;
      end;
    end);
  Session := TLspSession.Create(Client);
  try
    Hints := Session.InlayHints('C:\P\A.pas', 2, 9, 1000);
    // Bis zum Anfang der Zeile nach der letzten, damit sie ganz dabei ist.
    Assert.AreEqual('2-10', Range);
    Assert.AreEqual(4, Integer(Length(Hints)), 'Parameternamen, Typmarke (#453) und Endmarke (#620)');
    Assert.AreEqual(3, Hints[0].Line);
    Assert.AreEqual(9, Hints[0].Character);
    Assert.AreEqual('AWert', Hints[0].Name);
    Assert.IsFalse(Hints[0].EndLabel);
    Assert.IsFalse(Hints[0].TypeHint);
    // Typmarke ohne Doppelpunkt (#453).
    Assert.IsTrue(Hints[1].TypeHint);
    Assert.AreEqual('Integer', Hints[1].Name);
    Assert.AreEqual(4, Hints[1].Line);
    Assert.AreEqual('AName', Hints[2].Name);
    Assert.IsFalse(Hints[2].EndLabel);
    Assert.IsTrue(Hints[3].EndLabel);
    Assert.AreEqual('TKunde.Speichern', Hints[3].Name);
    Assert.AreEqual(8, Hints[3].Line);
  finally
    Session.Free;
    Client.Free;
  end;
end;

type
  /// <summary>Hält fest, was Client und Sitzung beim applyEdit-Test senden und empfangen.</summary>
  TApplyEditProbe = class
  public
    FClient: TLspClient;
    FSent: TList<string>;
    FAnnounced: Boolean;
    FReceived: TLspWorkspaceEdit;
    FReply: TLspApplyEditReply;
  end;

/// <summary>Client, der initialize beantwortet und Antworten des Plugins in der Probe sammelt.</summary>
function CreateApplyEditClient(const AProbe: TApplyEditProbe): TLspClient;
begin
  Result := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      mMessage: TJSONObject;
      mAnswer: TBytes;
    begin
      mMessage := Unframe(ABytes);
      try
        if mMessage.GetValue<string>('method', '') = 'initialize' then
        begin
          AProbe.FAnnounced := mMessage.GetValue<Boolean>('params.capabilities.workspace.applyEdit', False);
          mAnswer := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":{"capabilities":{}}}',
            [mMessage.GetValue<Integer>('id')]));
          AProbe.FClient.Receive(mAnswer, Length(mAnswer));
        end
        else if mMessage.GetValue('method') = nil then
        begin
          AProbe.FSent.Add(mMessage.ToJSON);
        end;
      finally
        mMessage.Free;
      end;
    end);
end;
/// <summary>Hängt den applyEdit-Empfang der Sitzung an die Probe.</summary>
procedure WireApplyEdit(const ASession: TLspSession; const AProbe: TApplyEditProbe);
begin
  ASession.OnApplyEdit :=
    procedure(const AEdit: TLspWorkspaceEdit; const AReply: TLspApplyEditReply)
    begin
      AProbe.FReceived := AEdit;
      AProbe.FReply := AReply;
    end;
end;
procedure TLspSessionTests.AcceptsApplyEditAndRepliesLater;
var
  mProbe: TApplyEditProbe;
  mSession: TLspSession;
  mIncoming: TBytes;
begin
  mProbe := TApplyEditProbe.Create;
  mProbe.FSent := TList<string>.Create;
  mProbe.FClient := CreateApplyEditClient(mProbe);
  mSession := TLspSession.Create(mProbe.FClient);
  try
    WireApplyEdit(mSession, mProbe);
    mSession.Initialize;
    Assert.IsTrue(mProbe.FAnnounced, 'applyEdit angekündigt');
    mIncoming := TLspClient.Frame('{"jsonrpc":"2.0","id":7,"method":"workspace/applyEdit","params":{"edit":' +
      '{"changes":{"file:///c%3A/p/a.pas":[{"range":{"start":{"line":0,"character":0},' +
      '"end":{"line":0,"character":1}},"newText":"b"}]}}}}');
    mProbe.FClient.Receive(mIncoming, Length(mIncoming));
    // Noch keine Antwort: Die kommt erst, wenn die Änderung im Hauptthread übernommen ist.
    Assert.AreEqual(0, Integer(mProbe.FSent.Count));
    Assert.AreEqual(1, mProbe.FReceived.EditCount);
    mProbe.FReply(False, 'gesperrt');
    Assert.AreEqual(1, Integer(mProbe.FSent.Count));
    Assert.AreEqual('{"jsonrpc":"2.0","id":7,"result":{"applied":false,"failureReason":"gesperrt"}}',
      mProbe.FSent[0]);
    // Andere Anfragen weiter mit null.
    mIncoming := TLspClient.Frame('{"jsonrpc":"2.0","id":8,"method":"window/workDoneProgress/create","params":{}}');
    mProbe.FClient.Receive(mIncoming, Length(mIncoming));
    Assert.AreEqual('{"jsonrpc":"2.0","id":8,"result":null}', mProbe.FSent[1]);
  finally
    // Probe lösen: FReply hält die Antwort-Prozedur der Sitzung, die sonst im Zyklus bliebe.
    mProbe.FReply := nil;
    mProbe.FReceived := Default(TLspWorkspaceEdit);
    mSession.OnApplyEdit := nil;
    mSession.Free;
    mProbe.FClient.Free;
    mProbe.FSent.Free;
    mProbe.Free;
  end;
end;
/// <summary>Projektkontext C:\P\A.dproj, Debug/Win32 mit DEBUG.</summary>
function DebugWin32Context: TAtlasProjectContext;
begin
  Result := Default(TAtlasProjectContext);
  Result.Project := 'C:\P\A.dproj';
  Result.Configuration := 'Debug';
  Result.Platform := 'Win32';
  Result.Defines := ['DEBUG'];
end;
procedure TLspSessionTests.SendsProjectContextsInInitializeAndOnChange;
var
  Client: TLspClient;
  Session: TLspSession;
  Initial: string;
  Sent: TList<string>;
  Context: TAtlasProjectContext;
begin
  Sent := TList<string>.Create;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
      Contexts: TJSONArray;
      Reply: TBytes;
    begin
      Message := Unframe(ABytes);
      try
        if Message.GetValue<string>('method', '') = 'initialize' then
        begin
          if Message.TryGetValue<TJSONArray>('params.initializationOptions.projectContexts', Contexts) then
          begin
            Initial := Contexts.ToJSON;
          end;
          Reply := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":{"capabilities":{}}}',
            [Message.GetValue<Integer>('id')]));
          Client.Receive(Reply, Length(Reply));
        end
        else if Message.GetValue<string>('method', '') = 'atlas/projectContext' then
        begin
          Sent.Add(Message.GetValue<string>('params.configuration') + '/' + Message.GetValue<string>('params.platform'));
        end;
      finally
        Message.Free;
      end;
    end);
  Session := TLspSession.Create(Client);
  try
    Context := DebugWin32Context;
    Assert.AreEqual(1, Integer(Length(Session.SetProjectContexts([Context]))), 'für initialize gemerkt');
    Session.Initialize;
    Assert.Contains(Initial, '"configuration":"Debug"');
    Assert.Contains(Initial, '"defines":["DEBUG"]');
    // Unverändert: nichts zu melden.
    Assert.AreEqual(0, Integer(Length(Session.SetProjectContexts([Context]))));
    Assert.AreEqual(0, Integer(Sent.Count));
    Context.Configuration := 'Release';
    Context.Platform := 'Win64';
    Assert.AreEqual(1, Integer(Length(Session.SetProjectContexts([Context]))), 'neu gemeldet');
    Session.SetProjectContexts([Context]);
    Assert.AreEqual(1, Integer(Sent.Count));
    Assert.AreEqual('Release/Win64', Sent[0]);
  finally
    Session.Free;
    Client.Free;
    Sent.Free;
  end;
end;
procedure TLspSessionTests.ReadsWorkspaceRun;
var
  Response: TJSONValue;
  Run: TLspWorkspaceRun;
begin
  Response := TJSONObject.ParseJSONValue('{"items":[],"atlas":{"run":{"serial":3,"active":true,"done":40,' +
    '"total":90,"skipped":1,"paused":"compile","elapsedMs":1500}}}');
  try
    Run := TLspWorkspaceRun.FromJson(Response);
  finally
    Response.Free;
  end;
  Assert.IsTrue(Run.Known);
  Assert.AreEqual(3, Run.Serial);
  Assert.IsTrue(Run.Active);
  Assert.AreEqual(40, Run.Done);
  Assert.AreEqual(90, Run.Total);
  Assert.AreEqual(1, Run.Skipped);
  Assert.AreEqual('compile', Run.Paused);
  Assert.AreEqual(Int64(1500), Run.ElapsedMs);
  // Ältere Server ohne Laufstand.
  Response := TJSONObject.ParseJSONValue('{"items":[]}');
  try
    Assert.IsFalse(TLspWorkspaceRun.FromJson(Response).Known);
  finally
    Response.Free;
  end;
  Run := Default(TLspWorkspaceRun);
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
procedure TLspSessionTests.WrapsServerSettings;
var
  Params: TJSONObject;
begin
  // Wie didChangeConfiguration aus VS Code: settings.atlas (#652).
  Params := TLspSession.SettingsParams('{"index":{"libraryPaths":true}}');
  try
    Assert.IsTrue(Params.GetValue<Boolean>('settings.atlas.index.libraryPaths'));
  finally
    Params.Free;
  end;
  Params := TLspSession.SettingsParams('kein JSON');
  try
    Assert.AreEqual('{"settings":{"atlas":{}}}', Params.ToJSON);
  finally
    Params.Free;
  end;
end;
procedure TLspSessionTests.ReadsShowMessageParams;
var
  Params: TJSONValue;
  MessageType: Integer;
  Text: string;
begin
  // Hinweis auf gemischte Kodierungen kommt als window/showMessage (#121).
  Params := TJSONObject.ParseJSONValue('{"type": 2, "message": "Gemischte Kodierungen"}');
  try
    Assert.IsTrue(TLspSession.ShowMessageParams(Params, MessageType, Text));
    Assert.AreEqual(2, MessageType);
    Assert.AreEqual('Gemischte Kodierungen', Text);
  finally
    Params.Free;
  end;
  Params := TJSONObject.ParseJSONValue('{"type": 1}');
  try
    Assert.IsFalse(TLspSession.ShowMessageParams(Params, MessageType, Text));
  finally
    Params.Free;
  end;
  Assert.IsFalse(TLspSession.ShowMessageParams(nil, MessageType, Text));
end;
procedure TLspSessionTests.ReportsProjectGroupChanges;
var
  Folders: TJSONArray;
  Added, Removed: TArray<string>;
begin
  Folders := TLspSession.ProjectFolders(['C:\Gruppe\App\App.dproj']);
  try
    Assert.AreEqual(1, Integer(Folders.Count));
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
procedure TLspSessionTests.FreesApplyEditIdWithoutReply;
var
  Client: TLspClient;
  Session: TLspSession;
  Sent: TList<string>;
  Calls: Integer;
  Incoming: TBytes;
begin
  Sent := TList<string>.Create;
  Calls := 0;
  Client := ApplyEditClient(Sent);
  Session := TLspSession.Create(Client);
  try
    // Wie ein beim Entladen verworfener Eintrag: Die Antwort-Prozedur wird nie gerufen.
    Session.OnApplyEdit :=
      procedure(const AEdit: TLspWorkspaceEdit; const AReply: TLspApplyEditReply)
      begin
        Inc(Calls);
      end;
    Session.Initialize;
    Incoming := TLspClient.Frame(ApplyEditRequest);
    Client.Receive(Incoming, Length(Incoming));
    Assert.AreEqual(1, Calls);
    // Keine Antwort; die Id gibt die Sitzung frei (der Leak-Monitor prüft das).
    Assert.AreEqual(0, Integer(Sent.Count));
  finally
    Session.OnApplyEdit := nil;
    Session.Free;
    Client.Free;
    Sent.Free;
  end;
end;
procedure TLspSessionTests.RepliesToApplyEditOnlyOnce;
var
  Client: TLspClient;
  Session: TLspSession;
  Sent: TList<string>;
  Reply: TLspApplyEditReply;
  Incoming: TBytes;
begin
  Sent := TList<string>.Create;
  Client := ApplyEditClient(Sent);
  Session := TLspSession.Create(Client);
  try
    Session.OnApplyEdit :=
      procedure(const AEdit: TLspWorkspaceEdit; const AReply: TLspApplyEditReply)
      begin
        Reply := AReply;
      end;
    Session.Initialize;
    Incoming := TLspClient.Frame(ApplyEditRequest);
    Client.Receive(Incoming, Length(Incoming));
    Reply(True, '');
    Reply(True, '');
    Assert.AreEqual(1, Integer(Sent.Count), 'genau eine Antwort');
    Assert.AreEqual('{"jsonrpc":"2.0","id":7,"result":{"applied":true}}', Sent[0]);
  finally
    Reply := nil;
    Session.OnApplyEdit := nil;
    Session.Free;
    Client.Free;
    Sent.Free;
  end;
end;
{ TLspClientTests (Obergrenzen) }

procedure TLspClientTests.RejectsOversizedContentLength;
var
  Client: TLspClient;
  Incoming: TBytes;
begin
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
    end);
  try
    Incoming := TEncoding.UTF8.GetBytes('Content-Length: 300000000'#13#10#13#10'{');
    Assert.WillRaise(
      procedure
      begin
        Client.Receive(Incoming, Length(Incoming));
      end, ELspClientError);
  finally
    Client.Free;
  end;
end;
procedure TLspClientTests.RejectsHeaderWithoutEnd;
var
  Client: TLspClient;
  Incoming: TBytes;
begin
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
    end);
  try
    Incoming := TEncoding.UTF8.GetBytes(StringOfChar('x', 9000));
    Assert.WillRaise(
      procedure
      begin
        Client.Receive(Incoming, Length(Incoming));
      end, ELspClientError);
  finally
    Client.Free;
  end;
end;
procedure TLspClientTests.AcceptsMessageAtHeaderLimit;
const
  Body = '{"jsonrpc":"2.0","method":"window/logMessage","params":{"type":3}}';
var
  Client: TLspClient;
  Seen: TList<string>;
  Header: string;
  Incoming: TBytes;
begin
  Seen := TList<string>.Create;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
    end);
  try
    Client.OnServerMessage :=
      procedure(const AMethod: string; const AParams: TJSONValue)
      begin
        Seen.Add(AMethod);
      end;
    // Kopf knapp unter der Grenze: ein langes Füllfeld vor Content-Length.
    Header := 'X-Fill: ' + StringOfChar('a', TLspClient.MaxHeaderLength - 40) + #13#10 +
      'Content-Length: ' + IntToStr(Length(Body)) + #13#10#13#10;
    Assert.IsTrue(Length(Header) - 4 <= TLspClient.MaxHeaderLength, 'Kopf innerhalb der Grenze');
    Incoming := TEncoding.UTF8.GetBytes(Header + Body);
    Client.Receive(Incoming, Length(Incoming));
    Assert.AreEqual(1, Integer(Seen.Count));
    Assert.AreEqual('window/logMessage', Seen[0]);
  finally
    Client.Free;
    Seen.Free;
  end;
end;
/// <summary>Client, der je Methode mit AReplies[Methode] antwortet und die Parameter in ASeen sammelt.</summary>
function CannedClient(const AReplies: TDictionary<string, string>; ASeen: TStrings): TLspClient;
var
  Client: TLspClient;
begin
  Client := nil;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
      Reply: TBytes;
      Method, Answer: string;
    begin
      Message := Unframe(ABytes);
      try
        Method := Message.GetValue<string>('method', '');
        if not AReplies.TryGetValue(Method, Answer) or (Message.GetValue('id') = nil) then
        begin
          Exit;
        end;
        ASeen.Add(Method + ' ' + Message.GetValue('params').ToJSON);
        Reply := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":%s}',
          [Message.GetValue<Integer>('id'), Answer]));
        Client.Receive(Reply, Length(Reply));
      finally
        Message.Free;
      end;
    end);
  Result := Client;
end;
procedure TLspSessionTests.ReadsImplementationsAndSymbols;
var
  Replies: TDictionary<string, string>;
  Seen: TStringList;
  Client: TLspClient;
  Session: TLspSession;
  Locations: TArray<TLspLocation>;
  Symbols: TArray<TAtlasSymbol>;
  Single: TJSONValue;
begin
  Replies := TDictionary<string, string>.Create;
  Seen := TStringList.Create;
  Client := CannedClient(Replies, Seen);
  Session := TLspSession.Create(Client);
  try
    // LocationLink: Ziel ist der Name (targetSelectionRange), nicht der ganze Rumpf.
    Replies.Add('textDocument/implementation', '[{"targetUri":"file:///c:/p/b.pas",' +
      '"targetRange":{"start":{"line":10,"character":0},"end":{"line":20,"character":4}},' +
      '"targetSelectionRange":{"start":{"line":10,"character":17},"end":{"line":10,"character":21}}}]');
    Replies.Add('workspace/symbol', '[{"name":"TKunde","kind":5,"containerName":"Kunden",' +
      '"location":{"uri":"file:///c:/p/kunden.pas","range":{"start":{"line":7,"character":2},' +
      '"end":{"line":7,"character":8}}}},{"name":"ohne Ort","kind":12}]');
    Locations := Session.Implementations('C:\P\A.pas', 3, 4);
    Assert.AreEqual(1, Integer(Length(Locations)));
    Assert.AreEqual('c:\p\b.pas', Locations[0].FileName);
    Assert.AreEqual(10, Locations[0].Line);
    Assert.AreEqual(17, Locations[0].Character);
    Symbols := Session.WorkspaceSymbols('Kun', 1000);
    Assert.AreEqual(1, Integer(Length(Symbols)), 'Symbole ohne Ort entfallen');
    Assert.AreEqual('TKunde', Symbols[0].Name);
    Assert.AreEqual('Kunden', Symbols[0].Container);
    Assert.AreEqual(5, Symbols[0].Kind);
    Assert.AreEqual('c:\p\kunden.pas', Symbols[0].FileName);
    Assert.AreEqual(7, Symbols[0].Line);
    Assert.Contains(Seen.Text, 'workspace/symbol {"query":"Kun"}');
    // Einzelne Location statt Liste.
    Single := TJSONObject.ParseJSONValue('{"uri":"file:///c:/p/c.pas","range":{"start":{"line":1,"character":2}}}');
    try
      Assert.AreEqual(1, Integer(Length(TLspSession.LocationsOf(Single))));
    finally
      Single.Free;
    end;
  finally
    Session.Free;
    Client.Free;
    Seen.Free;
    Replies.Free;
  end;
end;
procedure TLspSessionTests.WalksCallAndTypeHierarchies;
const
  Item = '{"name":"%s","kind":12,"detail":"%s","uri":"file:///c:/p/a.pas",' +
    '"range":{"start":{"line":%d,"character":0},"end":{"line":%d,"character":9}},' +
    '"selectionRange":{"start":{"line":%d,"character":10},"end":{"line":%d,"character":15}},"data":{"id":%d}}';
var
  Replies: TDictionary<string, string>;
  Seen: TStringList;
  Client: TLspClient;
  Session: TLspSession;
  Roots, Callers, Supers, Callees: TArray<TAtlasHierarchyItem>;
begin
  Replies := TDictionary<string, string>.Create;
  Seen := TStringList.Create;
  Client := CannedClient(Replies, Seen);
  Session := TLspSession.Create(Client);
  try
    Replies.Add('textDocument/prepareCallHierarchy', '[' + Format(Item, ['Laden', 'TKunde', 4, 9, 4, 4, 1]) + ']');
    Replies.Add('callHierarchy/incomingCalls', '[{"from":' + Format(Item, ['Start', 'TForm1', 30, 40, 30, 30, 2]) +
      ',"fromRanges":[]}]');
    // Aufruf über ein Interface mit zwei Umsetzungen (#1122) und ein gewöhnlicher.
    Replies.Add('callHierarchy/outgoingCalls', '[{"to":' + Format(Item, ['Speichern', 'ISpeicher', 7, 7, 7, 7, 5]) +
      ',"fromRanges":[],"atlasDispatch":{"kind":"interface","implementations":2}},{"to":' +
      Format(Item, ['Fertig', '', 8, 8, 8, 8, 6]) + ',"fromRanges":[]}]');
    Replies.Add('textDocument/prepareTypeHierarchy', '[' + Format(Item, ['TKunde', '', 2, 2, 2, 2, 3]) + ']');
    Replies.Add('typeHierarchy/supertypes', '[' + Format(Item, ['TPerson', '', 1, 1, 1, 1, 4]) + ']');
    Roots := Session.PrepareHierarchy(TAtlasHierarchyDirection.Incoming, 'C:\P\A.pas', 4, 12);
    Assert.AreEqual(1, Integer(Length(Roots)));
    Assert.AreEqual('Laden', Roots[0].Name);
    Assert.AreEqual('TKunde', Roots[0].Detail);
    Assert.AreEqual(4, Roots[0].Line);
    Assert.AreEqual(10, Roots[0].Character);
    Callers := Session.HierarchyChildren(TAtlasHierarchyDirection.Incoming, Roots[0]);
    Assert.AreEqual(1, Integer(Length(Callers)));
    Assert.AreEqual('Start', Callers[0].Name);
    Assert.AreEqual(30, Callers[0].Line);
    // Der Server bekommt seinen Eintrag samt data zurück.
    Assert.Contains(Seen.Text, 'callHierarchy/incomingCalls {"item":{"name":"Laden"');
    Assert.Contains(Seen.Text, '"data":{"id":1}');
    Callees := Session.HierarchyChildren(TAtlasHierarchyDirection.Outgoing, Roots[0]);
    Assert.AreEqual(2, Integer(Length(Callees)));
    Assert.AreEqual('interface', Callees[0].Dispatch);
    Assert.AreEqual(2, Callees[0].Implementations);
    Assert.AreEqual('', Callees[1].Dispatch);
    Assert.AreEqual(0, Callees[1].Implementations);
    Roots := Session.PrepareHierarchy(TAtlasHierarchyDirection.Supertypes, 'C:\P\A.pas', 2, 3);
    Supers := Session.HierarchyChildren(TAtlasHierarchyDirection.Supertypes, Roots[0]);
    Assert.AreEqual(1, Integer(Length(Supers)));
    Assert.AreEqual('TPerson', Supers[0].Name);
  finally
    Session.Free;
    Client.Free;
    Seen.Free;
    Replies.Free;
  end;
end;
procedure TLspSessionTests.ReadsCodeActionsAndRunsCommands;
var
  Replies: TDictionary<string, string>;
  Seen: TStringList;
  Client: TLspClient;
  Session: TLspSession;
  Actions: TArray<TLspCodeAction>;
  Answer: TJSONValue;
begin
  Replies := TDictionary<string, string>.Create;
  Seen := TStringList.Create;
  Client := CannedClient(Replies, Seen);
  Session := TLspSession.Create(Client);
  try
    Replies.Add('textDocument/codeAction', '[{"title":"try/finally ergänzen","kind":"refactor.rewrite",' +
      '"isPreferred":true,"edit":{"changes":{"file:///c:/p/a.pas":[{"range":{"start":{"line":2,"character":0},' +
      '"end":{"line":2,"character":0}},"newText":"try"}]}}},' +
      '{"title":"Befund kopieren","kind":"quickfix","command":{"title":"Befund kopieren","command":"atlas.copyText",' +
      '"arguments":["Text"]},"edit":{"changes":{}}},' +
      '{"title":"Status","command":"atlas.server.status"},' +
      '{"title":"Gesperrt","disabled":{"reason":"nur in Methoden"}},{"kind":"ohne Titel"}]');
    Replies.Add('workspace/executeCommand', '"Unit1.TForm1.Button1Click"');
    Actions := Session.CodeActions('C:\P\A.pas', TLspRange.Create(2, 4, 2, 9));
    Assert.AreEqual(4, Integer(Length(Actions)), 'Einträge ohne Titel entfallen');
    Assert.AreEqual('try/finally ergänzen', Actions[0].Title);
    Assert.IsTrue(Actions[0].Preferred);
    Assert.AreEqual(1, Actions[0].Edit.EditCount);
    Assert.AreEqual('', Actions[0].Command);
    Assert.AreEqual('atlas.copyText', Actions[1].Command);
    Assert.AreEqual('["Text"]', Actions[1].ArgumentsJson);
    Assert.IsTrue(Actions[1].Edit.IsEmpty);
    Assert.AreEqual('atlas.server.status', Actions[2].Command, 'Command statt CodeAction');
    Assert.AreEqual('[]', Actions[2].ArgumentsJson);
    Assert.AreEqual('nur in Methoden', Actions[3].Disabled);
    Assert.Contains(Seen.Text, '"range":{"start":{"line":2,"character":4},"end":{"line":2,"character":9}}');
    Assert.Contains(Seen.Text, '"triggerKind":1');
    Answer := Session.RunCommand('atlas.server.qualifiedName', '["file:///c:/p/a.pas",{"line":1,"character":2}]', 1000);
    try
      Assert.AreEqual('Unit1.TForm1.Button1Click', Answer.Value);
    finally
      Answer.Free;
    end;
    Assert.Contains(Seen.Text, '"arguments":["file:///c:/p/a.pas",{"line":1,"character":2}]');
    Answer := Session.RunCommand('atlas.server.status', '', 1000);
    Answer.Free;
    Assert.Contains(Seen.Text, '{"command":"atlas.server.status","arguments":[]}');
  finally
    Session.Free;
    Client.Free;
    Seen.Free;
    Replies.Free;
  end;
end;
procedure TLspSessionTests.RequestsTypingSelectionAndTypeDefinition;
var
  Replies: TDictionary<string, string>;
  Seen: TStringList;
  Client: TLspClient;
  Session: TLspSession;
  Edits: TArray<TLspTextEdit>;
  Ranges: TArray<TLspRange>;
  Locations: TArray<TLspLocation>;
begin
  Replies := TDictionary<string, string>.Create;
  Seen := TStringList.Create;
  Client := CannedClient(Replies, Seen);
  Session := TLspSession.Create(Client);
  try
    Replies.Add('textDocument/onTypeFormatting', '[{"range":{"start":{"line":4,"character":0},' +
      '"end":{"line":5,"character":0}},"newText":"uses\r\n  Unit2;\r\n"}]');
    Replies.Add('textDocument/selectionRange', '[{"range":{"start":{"line":3,"character":2},' +
      '"end":{"line":3,"character":7}},"parent":{"range":{"start":{"line":3,"character":2},' +
      '"end":{"line":3,"character":20}},"parent":{"range":{"start":{"line":0,"character":0},' +
      '"end":{"line":9,"character":0}}}}}]');
    Replies.Add('textDocument/typeDefinition', '{"uri":"file:///c:/p/kunde.pas","range":{"start":' +
      '{"line":12,"character":2},"end":{"line":12,"character":8}}}');
    Edits := Session.OnTypeFormatting('C:\P\A.pas', 5, 0, #10, TLspFormatOptions.Create(2, True), 1000);
    Assert.AreEqual(1, Integer(Length(Edits)));
    Assert.AreEqual(4, Edits[0].StartPos.Line);
    Assert.AreEqual('uses'#13#10'  Unit2;'#13#10, Edits[0].NewText);
    // Zeilenumbruch als \n oder \u000A, je nach Delphi-Version.
    Assert.IsTrue(Seen.Text.Contains('"ch":"\n"') or Seen.Text.Contains('"ch":"\u000A"'), Seen.Text);
    Assert.Contains(Seen.Text, '"options":{"tabSize":2,"insertSpaces":true}');
    Ranges := Session.SelectionRanges('C:\P\A.pas', 3, 4);
    Assert.AreEqual(3, Integer(Length(Ranges)), 'innen zuerst bis zur Datei');
    Assert.AreEqual(7, Ranges[0].EndPos.Character);
    Assert.AreEqual(20, Ranges[1].EndPos.Character);
    Assert.AreEqual(9, Ranges[2].EndPos.Line);
    Assert.Contains(Seen.Text, '"positions":[{"line":3,"character":4}]');
    Locations := Session.TypeDefinition('C:\P\A.pas', 3, 4);
    Assert.AreEqual(1, Integer(Length(Locations)));
    Assert.AreEqual(12, Locations[0].Line);
  finally
    Session.Free;
    Client.Free;
    Seen.Free;
    Replies.Free;
  end;
end;
procedure TLspSessionTests.RequestsFormatting;
var
  Replies: TDictionary<string, string>;
  Seen: TStringList;
  Client: TLspClient;
  Session: TLspSession;
  Edits: TArray<TLspTextEdit>;
begin
  Replies := TDictionary<string, string>.Create;
  Seen := TStringList.Create;
  Client := CannedClient(Replies, Seen);
  Session := TLspSession.Create(Client);
  try
    Replies.Add('textDocument/formatting', '[{"range":{"start":{"line":2,"character":0},' +
      '"end":{"line":2,"character":4}},"newText":"  A;"},{"range":{"start":{"line":3,"character":0},' +
      '"end":{"line":3,"character":1}},"newText":""}]');
    Replies.Add('textDocument/rangeFormatting', '[]');
    Edits := Session.Formatting('C:\P\A.pas', 4, False, 1000);
    Assert.AreEqual(2, Integer(Length(Edits)));
    Assert.AreEqual('  A;', Edits[0].NewText);
    Assert.AreEqual(3, Edits[1].StartPos.Line);
    Assert.Contains(Seen.Text, '"options":{"tabSize":4,"insertSpaces":false}');
    Edits := Session.Formatting('C:\P\A.pas', TLspRange.Create(1, 0, 3, 0), 2, True, 1000);
    Assert.AreEqual(0, Integer(Length(Edits)));
    Assert.Contains(Seen.Text, '"range":{"start":{"line":1,"character":0},"end":{"line":3,"character":0}}');
  finally
    Session.Free;
    Client.Free;
    Seen.Free;
    Replies.Free;
  end;
end;
procedure TLspSessionTests.RequestsLinkedLocals;
var
  Replies: TDictionary<string, string>;
  Seen: TStringList;
  Client: TLspClient;
  Session: TLspSession;
  Answer: TJSONValue;
begin
  Replies := TDictionary<string, string>.Create;
  Seen := TStringList.Create;
  Client := CannedClient(Replies, Seen);
  Session := TLspSession.Create(Client);
  try
    Replies.Add('textDocument/linkedEditingRange', '{"ranges":[{"start":{"line":3,"character":2},' +
      '"end":{"line":3,"character":8}}],"atlasConflicts":[]}');
    Answer := Session.LinkedLocals('C:\P\A.pas', 3, 4);
    try
      Assert.IsTrue(Answer is TJSONObject);
      Assert.AreEqual(1, TJSONObject(Answer).GetValue<TJSONArray>('ranges').Count);
    finally
      Answer.Free;
    end;
    Assert.Contains(Seen.Text, '"atlasLocals":true');
    Assert.Contains(Seen.Text, '"position":{"line":3,"character":4}');
  finally
    Session.Free;
    Client.Free;
    Seen.Free;
    Replies.Free;
  end;
end;
procedure TLspSessionTests.RequestsDeclarationsAndDefinitions;
var
  Replies: TDictionary<string, string>;
  Seen: TStringList;
  Client: TLspClient;
  Session: TLspSession;
  Locations: TArray<TLspLocation>;
begin
  Replies := TDictionary<string, string>.Create;
  Seen := TStringList.Create;
  Client := CannedClient(Replies, Seen);
  Session := TLspSession.Create(Client);
  try
    Replies.Add('textDocument/declaration', '[{"uri":"file:///c:/p/kunde.pas","range":{"start":' +
      '{"line":12,"character":4},"end":{"line":12,"character":8}}}]');
    Replies.Add('textDocument/definition', '[{"uri":"file:///c:/p/kunde.pas","range":{"start":' +
      '{"line":40,"character":15},"end":{"line":40,"character":19}}},{"uri":"file:///c:/p/b.pas","range":' +
      '{"start":{"line":2,"character":0},"end":{"line":2,"character":1}}}]');
    Locations := Session.Declarations('C:\P\A.pas', 3, 4);
    Assert.AreEqual(1, Integer(Length(Locations)));
    Assert.AreEqual(12, Locations[0].Line);
    Assert.AreEqual(4, Locations[0].Character);
    Assert.Contains(Seen.Text, 'textDocument/declaration');
    Locations := Session.Definitions('C:\P\A.pas', 3, 4);
    Assert.AreEqual(2, Integer(Length(Locations)));
    Assert.AreEqual(40, Locations[0].Line);
    Assert.AreEqual(2, Locations[1].Line);
  finally
    Session.Free;
    Client.Free;
    Seen.Free;
    Replies.Free;
  end;
end;
procedure TLspSessionTests.MapsIndexBackToColumn;
var
  Line: string;
  Index: Integer;
begin
  Assert.AreEqual(1, TLspSession.IndexToColumn('abc', 0, 8));
  Assert.AreEqual(3, TLspSession.IndexToColumn('abc', 2, 8));
  Assert.AreEqual(9, TLspSession.IndexToColumn(#9'x', 1, 8), 'Tab bis zur nächsten Tabulatorposition');
  Assert.AreEqual(6, TLspSession.IndexToColumn('abc', 5, 8), 'hinter dem Zeilenende je Zeichen eine Spalte');
  // Umkehrung von ColumnToIndex innerhalb der Zeile.
  Line := 'a'#9'bc'#9#9'd';
  for Index := 0 to Length(Line) do
  begin
    Assert.AreEqual(Index, TLspSession.ColumnToIndex(Line, TLspSession.IndexToColumn(Line, Index, 4), 4));
  end;
end;
initialization
  TDUnitX.RegisterTestFixture(TLspClientTests);
  TDUnitX.RegisterTestFixture(TLspSessionTests);

end.
