unit Atlas.Core.Lsp.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspClientTests = class
  public
    /// <summary>Erste Benutzung des gemeinsamen Rekorders (TAtlasPluginTimings.Shared, lebt bis zum Entladen)
    /// ungemessen vorwegnehmen; sonst meldet TimingNamesExecutedCommand ihn je nach Reihenfolge als Leck.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
    /// <summary>Ende der Verbindung mit letzter und offenen Anfragen und den Angaben des Transports.
    /// </summary>
    [Test]
    procedure CloseInfoNamesLastAndOpenRequests;
    [Test]
    procedure ForwardsServerMessagesToHandler;
    [Test]
    procedure RoutesPartialResultsToRequest;
    /// <summary>Obergrenzen der Rahmung.</summary>
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
    /// <summary>Antwortet niemand, gibt die Sitzung die Id frei.</summary>
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
  mText: string;
begin
  mText := TEncoding.UTF8.GetString(ABytes);
  Result := TJSONObject.ParseJSONValue(mText.Substring(mText.IndexOf(#13#10#13#10) + 4)) as TJSONObject;
end;
/// <summary>Client, der Gesendetes in ASent sammelt; antwortet auf initialize.</summary>
function ApplyEditClient(ASent: TList<string>): TLspClient;
var
  mClient: TLspClient;
begin
  mClient := nil;
  mClient := TLspClient.Create(
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
          mClient.Receive(Answer, Length(Answer));
        end
        else if Message.GetValue('method') = nil then
        begin
          ASent.Add(Message.ToJSON);
        end;
      finally
        Message.Free;
      end;
    end);
  Result := mClient;
end;

const
  cApplyEditRequest = '{"jsonrpc":"2.0","id":7,"method":"workspace/applyEdit","params":{"edit":' +
    '{"changes":{"file:///c%3A/p/a.pas":[{"range":{"start":{"line":0,"character":0},' +
    '"end":{"line":0,"character":1}},"newText":"b"}]}}}}';

{ TLspClientTests }

procedure TLspClientTests.WarmUpFirstUse;
begin
  TimingNamesExecutedCommand;
end;

procedure TLspClientTests.AnswersRequestFromSplitFrames;
var
  mClient: TLspClient;
  mResponse: TJSONValue;
  mWert: string;
begin
  mClient := nil;
  mClient := TLspClient.Create(
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
        mClient.Receive(Copy(Reply, Index, 1), 1);
      end;
    end);
  try
    mResponse := mClient.Request('test', nil, 1000);
    try
      mWert := mResponse.GetValue<string>('wert');
      Assert.AreEqual('Grüße', mWert);
    finally
      mResponse.Free;
    end;
  finally
    mClient.Free;
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
  mClient: TLspClient;
begin
  mClient := nil;
  mClient := TLspClient.Create(
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
      mClient.Receive(Reply, Length(Reply));
    end);
  try
    Assert.WillRaiseWithMessage(
      procedure
      begin
        mClient.Request('test', nil, 1000).Free;
      end, ELspClientError, 'unbekannt');
  finally
    mClient.Free;
  end;
end;
procedure TLspClientTests.AnswersServerRequestWithNull;
var
  mClient: TLspClient;
  mSent: TList<string>;
  mIncoming: TBytes;
begin
  mSent := TList<string>.Create;
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
    begin
      Message := Unframe(ABytes);
      try
        mSent.Add(Message.ToJSON);
      finally
        Message.Free;
      end;
    end);
  try
    mIncoming := TLspClient.Frame('{"jsonrpc":"2.0","id":"p1","method":"window/workDoneProgress/create","params":{}}') +
      TLspClient.Frame('{"jsonrpc":"2.0","method":"window/logMessage","params":{"type":3,"message":"x"}}');
    mClient.Receive(mIncoming, Length(mIncoming));
    Assert.AreEqual(1, Integer(mSent.Count));
    Assert.AreEqual('{"jsonrpc":"2.0","id":"p1","result":null}', mSent[0]);
  finally
    mClient.Free;
    mSent.Free;
  end;
end;
procedure TLspClientTests.ForwardsServerMessagesToHandler;
var
  mClient: TLspClient;
  mSent, mSeen: TList<string>;
  mIncoming: TBytes;
begin
  mSent := TList<string>.Create;
  mSeen := TList<string>.Create;
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
      mSent.Add(TEncoding.UTF8.GetString(ABytes));
    end);
  try
    mClient.OnServerMessage :=
      procedure(const AMethod: string; const AParams: TJSONValue)
      begin
        if AParams <> nil then
        begin
          mSeen.Add(AMethod + ' ' + AParams.ToJSON);
        end
        else
        begin
          mSeen.Add(AMethod);
        end;
      end;
    mIncoming := TLspClient.Frame('{"jsonrpc":"2.0","id":"r1","method":"workspace/diagnostic/refresh"}') +
      TLspClient.Frame('{"jsonrpc":"2.0","method":"window/logMessage","params":{"type":3}}');
    mClient.Receive(mIncoming, Length(mIncoming));
    Assert.AreEqual(2, Integer(mSeen.Count));
    Assert.AreEqual('workspace/diagnostic/refresh', mSeen[0]);
    Assert.AreEqual('window/logMessage {"type":3}', mSeen[1]);
    Assert.AreEqual(1, Integer(mSent.Count), 'Anfrage weiter mit null beantwortet');
  finally
    mClient.Free;
    mSeen.Free;
    mSent.Free;
  end;
end;
procedure TLspClientTests.RoutesPartialResultsToRequest;
var
  mClient: TLspClient;
  mPartials, mSeen: TList<string>;
  mResponse: TJSONValue;
  mParams: TJSONObject;
begin
  // #616: $/progress zum partialResultToken geht an die Anfrage, vor der Antwort; andere Tokens nicht.
  mPartials := TList<string>.Create;
  mSeen := TList<string>.Create;
  mClient := nil;
  mClient := TLspClient.Create(
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
      mClient.Receive(Reply, Length(Reply));
    end);
  try
    mClient.OnServerMessage :=
      procedure(const AMethod: string; const AParams: TJSONValue)
      begin
        mSeen.Add(AMethod);
      end;
    mParams := TJSONObject.Create;
    mResponse := mClient.Request('textDocument/completion', mParams, 1000,
      procedure(const AValue: TJSONValue)
      begin
        mPartials.Add(AValue.ToJSON);
      end);
    try
      Assert.AreEqual('[4]', mResponse.ToJSON);
    finally
      mResponse.Free;
    end;
    Assert.AreEqual(2, Integer(mPartials.Count));
    Assert.AreEqual('[1]', mPartials[0]);
    Assert.AreEqual('[2,3]', mPartials[1]);
    Assert.AreEqual(1, Integer(mSeen.Count), 'Fremder Fortschritt geht an OnServerMessage');
  finally
    mClient.Free;
    mSeen.Free;
    mPartials.Free;
  end;
end;
procedure TLspClientTests.CancellableRequestSendsCancel;
var
  mClient: TLspClient;
  mSent: TList<string>;
  mWatch: TStopwatch;
  mCalls: Integer;
begin
  mSent := TList<string>.Create;
  mClient := nil;
  try
    mClient := TLspClient.Create(
      procedure(const ABytes: TBytes)
      var
        Request: TJSONObject;
      begin
        Request := Unframe(ABytes);
        try
          mSent.Add(Request.GetValue<string>('method'));
        finally
          Request.Free;
        end;
      end);
    mCalls := 0;
    mWatch := TStopwatch.StartNew;
    Assert.WillRaise(
      procedure
      begin
        mClient.RequestCancellable('atlas/query', nil, 10000,
          function: Boolean
          begin
            Inc(mCalls);
            Result := mCalls >= 2;
          end).Free;
      end, ELspCancelledError);
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 5000, 'wartet bis zum Zeitlimit');
    Assert.AreEqual('atlas/query,$/cancelRequest', string.Join(',', mSent.ToArray));
  finally
    mClient.Free;
    mSent.Free;
  end;
end;
procedure TLspClientTests.RejectsRequestsAfterClose;
var
  mClient: TLspClient;
begin
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
    end);
  try
    mClient.Close;
    Assert.WillRaise(
      procedure
      begin
        mClient.Request('test', nil, 1000).Free;
      end, ELspClientError);
  finally
    mClient.Free;
  end;
end;
/// <summary>Anfrage in einem eigenen Thread; endet mit dem Schließen des Clients.</summary>
function RequestInThread(AClient: TLspClient; const AMethod: string): TThread;
var
  mClient: TLspClient;
  mMethod: string;
begin
  mClient := AClient;
  mMethod := AMethod;
  Result := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        mClient.Request(mMethod, nil, 10000).Free;
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
  mClient: TLspClient;
  mDefinitionSent, mDiagnosticSent: TEvent;
  mDefinition, mDiagnostic: TThread;
  mEnded, mInfo: TLspCloseInfo;
begin
  mDefinitionSent := TEvent.Create(nil, True, False, '');
  mDiagnosticSent := TEvent.Create(nil, True, False, '');
  mClient := CreateSilentClient(mDefinitionSent, mDiagnosticSent);
  mDefinition := nil;
  mDiagnostic := nil;
  try
    mInfo := mClient.CloseInfo;
    Assert.AreEqual('', mInfo.LastMethod, 'offen: noch nichts');
    mDefinition := RequestInThread(mClient, 'textDocument/definition');
    Assert.AreEqual(Ord(wrSignaled), Ord(mDefinitionSent.WaitFor(5000)));
    // Long-Polling zählt weder als letzte noch als offene Anfrage.
    mDiagnostic := RequestInThread(mClient, 'workspace/diagnostic');
    Assert.AreEqual(Ord(wrSignaled), Ord(mDiagnosticSent.WaitFor(5000)));
    mEnded := Default(TLspCloseInfo);
    mEnded.ExitKnown := True;
    mEnded.ExitCode := $C00000FD;
    mEnded.RuntimeMs := 1234;
    mEnded.ErrorLines := 3;
    mClient.CloseWith(mEnded);
    mDefinition.WaitFor;
    mDiagnostic.WaitFor;
    mInfo := mClient.CloseInfo;
    Assert.IsTrue(mInfo.ExitKnown);
    Assert.AreEqual(Int64($C00000FD), Int64(mInfo.ExitCode));
    Assert.AreEqual(Int64(1234), mInfo.RuntimeMs);
    Assert.AreEqual(3, mInfo.ErrorLines);
    Assert.AreEqual('textDocument/definition', mInfo.LastMethod);
    Assert.AreEqual(1, Integer(Length(mInfo.OpenMethods)));
    Assert.AreEqual('textDocument/definition', mInfo.OpenMethods[0]);
    // Nur das erste Schließen zählt.
    mClient.Close;
    Assert.AreEqual(Int64($C00000FD), Int64(mClient.CloseInfo.ExitCode));
  finally
    mDefinition.Free;
    mDiagnostic.Free;
    mClient.Free;
    mDefinitionSent.Free;
    mDiagnosticSent.Free;
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
    mValue: TJSONValue;
  begin
    mValue := TJSONObject.ParseJSONValue(AJson);
    try
      Result := TLspSession.HoverText(mValue);
    finally
      mValue.Free;
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
  mHover: TJSONValue;
  mParts: TLspHoverParts;
begin
  // Mit Teilen des Servers (#442).
  mHover := TJSONObject.ParseJSONValue('{"contents":"x","atlas":{"declaration":"procedure BeginUpdate;",' +
    '"unit":"System.Classes","documentation":"Unterdrückt das Neuzeichnen."}}');
  try
    mParts := TLspHoverParts.FromHover(mHover);
    Assert.AreEqual('procedure BeginUpdate;', mParts.Declaration);
    Assert.AreEqual('System.Classes', mParts.UnitName);
    Assert.AreEqual('Unterdrückt das Neuzeichnen.', mParts.Documentation);
    Assert.IsTrue(mParts.Found);
  finally
    mHover.Free;
  end;
  // Seit #654: documentation strukturiert, Klartext in documentationText.
  mHover := TJSONObject.ParseJSONValue('{"contents":"x","atlas":{"declaration":"procedure BeginUpdate;",' +
    '"documentation":{"sections":[]},"documentationText":"Unterdrückt das Neuzeichnen."}}');
  try
    Assert.AreEqual('Unterdrückt das Neuzeichnen.', TLspHoverParts.FromHover(mHover).Documentation);
  finally
    mHover.Free;
  end;
  // Ältere Server: erster Absatz Deklaration, Rest Doku.
  mHover := TJSONObject.ParseJSONValue('{"contents":"function Max(A, B: Integer): Integer;\n\nGrößerer Wert."}');
  try
    mParts := TLspHoverParts.FromHover(mHover);
    Assert.AreEqual('function Max(A, B: Integer): Integer;', mParts.Declaration);
    Assert.AreEqual('Größerer Wert.', mParts.Documentation);
  finally
    mHover.Free;
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
  mClient: TLspClient;
  mSession: TLspSession;
  mMethods: TList<string>;
begin
  mMethods := TList<string>.Create;
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
      Method, Version: string;
    begin
      Message := Unframe(ABytes);
      try
        Method := Message.GetValue<string>('method');
        Version := Message.GetValue<string>('params.textDocument.version', '');
        mMethods.Add(Method + ':' + Version);
      finally
        Message.Free;
      end;
    end);
  mSession := TLspSession.Create(mClient);
  try
    mSession.Sync('C:\P\A.pas', 'unit A;');
    mSession.Sync('c:\p\a.pas', 'unit A;');
    mSession.Sync('C:\P\A.pas', 'unit A; ');
    Assert.AreEqual(2, Integer(mMethods.Count));
    Assert.AreEqual('textDocument/didOpen:1', mMethods[0]);
    Assert.AreEqual('textDocument/didChange:2', mMethods[1]);
  finally
    mSession.Free;
    mClient.Free;
    mMethods.Free;
  end;
end;
procedure TLspSessionTests.ClosesSyncedDocumentsAndListsThem;
var
  mClient: TLspClient;
  mSession: TLspSession;
  mMethods: TList<string>;
  mText: string;
begin
  mMethods := TList<string>.Create;
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
    begin
      Message := Unframe(ABytes);
      try
        mMethods.Add(Message.GetValue<string>('method') + ' ' + Message.GetValue<string>('params.textDocument.uri', ''));
      finally
        Message.Free;
      end;
    end);
  mSession := TLspSession.Create(mClient);
  try
    mSession.Sync('C:\P\A.pas', 'unit A;');
    mSession.Sync('C:\P\B.pas', 'unit B;');
    Assert.AreEqual(2, Integer(Length(mSession.SyncedFiles)));
    Assert.IsTrue(mSession.SyncedText('c:\p\b.pas', mText));
    Assert.AreEqual('unit B;', mText);
    mSession.Close('c:\p\a.pas');
    mSession.Close('C:\P\X.pas');
    Assert.AreEqual(3, Integer(mMethods.Count), 'nur eine didClose');
    Assert.AreEqual('textDocument/didClose file:///c%3A/p/a.pas', mMethods[2]);
    Assert.AreEqual(1, Integer(Length(mSession.SyncedFiles)));
    Assert.AreEqual('C:\P\B.pas', mSession.SyncedFiles[0]);
    Assert.IsFalse(mSession.SyncedText('C:\P\A.pas', mText));
    // Nach didClose wieder didOpen.
    mSession.Sync('C:\P\A.pas', 'unit A;');
    Assert.StartsWith('textDocument/didOpen', mMethods[3]);
  finally
    mSession.Free;
    mClient.Free;
    mMethods.Free;
  end;
end;
procedure TLspSessionTests.ReopensDocumentsOfPreviousSession;
var
  mClient: TLspClient;
  mPrevious, mFresh: TLspSession;
  mMessages: TList<string>;
  mDocuments: TArray<TLspOpenDocument>;
begin
  mMessages := TList<string>.Create;
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
    begin
      Message := Unframe(ABytes);
      try
        mMessages.Add(Message.GetValue<string>('method') + ' ' +
          Message.GetValue<string>('params.textDocument.uri', '') + ' ' +
          Message.GetValue<string>('params.textDocument.text', ''));
      finally
        Message.Free;
      end;
    end);
  mPrevious := TLspSession.Create(mClient);
  mFresh := TLspSession.Create(mClient);
  try
    mPrevious.Sync('C:\P\A.pas', 'unit A;');
    mPrevious.Sync('C:\P\B.pas', 'unit B;');
    // Ungespeicherter Stand: Der neue Server muss den zuletzt geschickten Text bekommen.
    mPrevious.Sync('C:\P\B.pas', 'unit B; // neu');
    mDocuments := mPrevious.OpenDocuments;
    Assert.AreEqual(2, Integer(Length(mDocuments)));
    mMessages.Clear;
    // A ist in der neuen Sitzung schon abgeglichen und bleibt unverändert.
    mFresh.Sync('C:\P\A.pas', 'unit A; // getippt');
    mFresh.Reopen(mDocuments);
    Assert.AreEqual(2, Integer(mMessages.Count));
    Assert.AreEqual('textDocument/didOpen file:///c%3A/p/b.pas unit B; // neu', mMessages[1]);
    Assert.AreEqual(2, Integer(Length(mFresh.SyncedFiles)));
  finally
    mFresh.Free;
    mPrevious.Free;
    mClient.Free;
    mMessages.Free;
  end;
end;
procedure TLspSessionTests.SendsOnlyTheChangedRange;
var
  mClient: TLspClient;
  mSession: TLspSession;
  mChanges: TList<string>;
begin
  mChanges := TList<string>.Create;
  mClient := TLspClient.Create(
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
          mChanges.Add(Format('%d:%d-%d:%d "%s"', [Change.GetValue<Integer>('range.start.line'),
            Change.GetValue<Integer>('range.start.character'), Change.GetValue<Integer>('range.end.line'),
            Change.GetValue<Integer>('range.end.character'), Change.GetValue<string>('text')]));
        end;
      finally
        Message.Free;
      end;
    end);
  mSession := TLspSession.Create(mClient);
  try
    mSession.Sync('C:\P\A.pas', 'unit A;'#13#10'begin'#13#10'end.');
    mSession.Sync('C:\P\A.pas', 'unit A;'#13#10'begin'#13#10'  X;'#13#10'end.');
    mSession.Sync('C:\P\A.pas', 'unit A;'#13#10'begin'#13#10'end.');
    Assert.AreEqual(2, Integer(mChanges.Count));
    Assert.AreEqual('2:0-2:0 "  X;'#13#10'"', mChanges[0]);
    Assert.AreEqual('2:0-3:0 ""', mChanges[1]);
  finally
    mSession.Free;
    mClient.Free;
    mChanges.Free;
  end;
end;
procedure TLspSessionTests.ReportsWatchedFilesExceptSyncedChanges;
var
  mClient: TLspClient;
  mSession: TLspSession;
  mMessages: TList<string>;
begin
  mMessages := TList<string>.Create;
  mClient := TLspClient.Create(
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
          mMessages.Add(Line);
        end;
      finally
        Message.Free;
      end;
    end);
  mSession := TLspSession.Create(mClient);
  try
    mSession.Sync('C:\P\Open.pas', 'unit Open;');
    // Nur die offene Datei geändert: Ihr Editortext gilt, nichts zu melden.
    mSession.FilesChanged([TAtlasFileChange.Create('c:\p\open.pas', TAtlasFileChangeKind.Changed)]);
    Assert.AreEqual(0, Integer(mMessages.Count));
    mSession.FilesChanged([TAtlasFileChange.Create('C:\P\Open.pas', TAtlasFileChangeKind.Changed),
      TAtlasFileChange.Create('C:\P\B.pas', TAtlasFileChangeKind.Changed),
      TAtlasFileChange.Create('C:\P\Open.pas', TAtlasFileChangeKind.Deleted),
      TAtlasFileChange.Create('C:\P\N.pas', TAtlasFileChangeKind.Created)]);
    Assert.AreEqual(1, Integer(mMessages.Count));
    Assert.AreEqual('file:///c%3A/p/b.pas=2 file:///c%3A/p/open.pas=3 file:///c%3A/p/n.pas=1 ', mMessages[0]);
  finally
    mSession.Free;
    mClient.Free;
    mMessages.Free;
  end;
end;
procedure TLspSessionTests.PreparesAndRequestsRename;
var
  mClient: TLspClient;
  mSession: TLspSession;
  mPrepareReply, mNewName: string;
  mPlaceholder: string;
  mResponse: TJSONValue;
begin
  mClient := TLspClient.Create(
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
          Answer := mPrepareReply;
        end
        else if Method = 'textDocument/rename' then
        begin
          mNewName := Message.GetValue<string>('params.newName');
          Answer := '{"changes":{}}';
        end
        else
        begin
          Exit;
        end;
        Reply := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":%s}',
          [Message.GetValue<Integer>('id'), Answer]));
        mClient.Receive(Reply, Length(Reply));
      finally
        Message.Free;
      end;
    end);
  mSession := TLspSession.Create(mClient);
  try
    mPrepareReply := '{"range":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}},"placeholder":"Alt"}';
    Assert.IsTrue(mSession.PrepareRename('C:\P\A.pas', 'unit Foo;', 0, 6, mPlaceholder));
    Assert.AreEqual('Alt', mPlaceholder);
    // Nur ein Bereich: Der Name kommt aus dem Text.
    mPrepareReply := '{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}';
    Assert.IsTrue(mSession.PrepareRename('C:\P\A.pas', 'unit Foo;', 0, 6, mPlaceholder));
    Assert.AreEqual('Foo', mPlaceholder);
    mPrepareReply := 'null';
    Assert.IsFalse(mSession.PrepareRename('C:\P\A.pas', 'unit Foo;', 0, 0, mPlaceholder));
    mResponse := mSession.Rename('C:\P\A.pas', 0, 6, 'Neu', 1000);
    try
      Assert.AreEqual('Neu', mNewName);
      Assert.IsTrue(mResponse is TJSONObject);
    finally
      mResponse.Free;
    end;
  finally
    mSession.Free;
    mClient.Free;
  end;
end;
procedure TLspSessionTests.ReadsParameterInlayHints;
var
  mClient: TLspClient;
  mSession: TLspSession;
  mRange: string;
  mHints: TArray<TAtlasInlayHint>;
begin
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
      Reply: TBytes;
    begin
      Message := Unframe(ABytes);
      try
        if Message.GetValue<string>('method', '') = 'textDocument/inlayHint' then
        begin
          mRange := Message.GetValue<Integer>('params.range.start.line').ToString + '-' +
            Message.GetValue<Integer>('params.range.end.line').ToString;
          Reply := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":[' +
            '{"position":{"line":3,"character":9},"label":"AWert:","kind":2,"paddingRight":true},' +
            '{"position":{"line":4,"character":2},"label":": Integer","kind":1},' +
            '{"position":{"line":5,"character":7},"label":[{"value":"AName"},{"value":":"}],"kind":2},' +
            '{"position":{"line":8,"character":6},"label":"// TKunde.Speichern","paddingLeft":true},' +
            '{"position":{"line":9,"character":1},"label":"ohne Art"}]}',
            [Message.GetValue<Integer>('id')]));
          mClient.Receive(Reply, Length(Reply));
        end;
      finally
        Message.Free;
      end;
    end);
  mSession := TLspSession.Create(mClient);
  try
    mHints := mSession.InlayHints('C:\P\A.pas', 2, 9, 1000);
    // Bis zum Anfang der Zeile nach der letzten, damit sie ganz dabei ist.
    Assert.AreEqual('2-10', mRange);
    Assert.AreEqual(4, Integer(Length(mHints)), 'Parameternamen, Typmarke (#453) und Endmarke (#620)');
    Assert.AreEqual(3, mHints[0].Line);
    Assert.AreEqual(9, mHints[0].Character);
    Assert.AreEqual('AWert', mHints[0].Name);
    Assert.IsFalse(mHints[0].EndLabel);
    Assert.IsFalse(mHints[0].TypeHint);
    // Typmarke ohne Doppelpunkt (#453).
    Assert.IsTrue(mHints[1].TypeHint);
    Assert.AreEqual('Integer', mHints[1].Name);
    Assert.AreEqual(4, mHints[1].Line);
    Assert.AreEqual('AName', mHints[2].Name);
    Assert.IsFalse(mHints[2].EndLabel);
    Assert.IsTrue(mHints[3].EndLabel);
    Assert.AreEqual('TKunde.Speichern', mHints[3].Name);
    Assert.AreEqual(8, mHints[3].Line);
  finally
    mSession.Free;
    mClient.Free;
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
  mClient: TLspClient;
  mSession: TLspSession;
  mInitial: string;
  mSent: TList<string>;
  mContext: TAtlasProjectContext;
begin
  mSent := TList<string>.Create;
  mClient := TLspClient.Create(
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
            mInitial := Contexts.ToJSON;
          end;
          Reply := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":{"capabilities":{}}}',
            [Message.GetValue<Integer>('id')]));
          mClient.Receive(Reply, Length(Reply));
        end
        else if Message.GetValue<string>('method', '') = 'atlas/projectContext' then
        begin
          mSent.Add(Message.GetValue<string>('params.configuration') + '/' + Message.GetValue<string>('params.platform'));
        end;
      finally
        Message.Free;
      end;
    end);
  mSession := TLspSession.Create(mClient);
  try
    mContext := DebugWin32Context;
    Assert.AreEqual(1, Integer(Length(mSession.SetProjectContexts([mContext]))), 'für initialize gemerkt');
    mSession.Initialize;
    Assert.Contains(mInitial, '"configuration":"Debug"');
    Assert.Contains(mInitial, '"defines":["DEBUG"]');
    // Unverändert: nichts zu melden.
    Assert.AreEqual(0, Integer(Length(mSession.SetProjectContexts([mContext]))));
    Assert.AreEqual(0, Integer(mSent.Count));
    mContext.Configuration := 'Release';
    mContext.Platform := 'Win64';
    Assert.AreEqual(1, Integer(Length(mSession.SetProjectContexts([mContext]))), 'neu gemeldet');
    mSession.SetProjectContexts([mContext]);
    Assert.AreEqual(1, Integer(mSent.Count));
    Assert.AreEqual('Release/Win64', mSent[0]);
  finally
    mSession.Free;
    mClient.Free;
    mSent.Free;
  end;
end;
procedure TLspSessionTests.ReadsWorkspaceRun;
var
  mResponse: TJSONValue;
  mRun: TLspWorkspaceRun;
begin
  mResponse := TJSONObject.ParseJSONValue('{"items":[],"atlas":{"run":{"serial":3,"active":true,"done":40,' +
    '"total":90,"skipped":1,"paused":"compile","elapsedMs":1500}}}');
  try
    mRun := TLspWorkspaceRun.FromJson(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.IsTrue(mRun.Known);
  Assert.AreEqual(3, mRun.Serial);
  Assert.IsTrue(mRun.Active);
  Assert.AreEqual(40, mRun.Done);
  Assert.AreEqual(90, mRun.Total);
  Assert.AreEqual(1, mRun.Skipped);
  Assert.AreEqual('compile', mRun.Paused);
  Assert.AreEqual(Int64(1500), mRun.ElapsedMs);
  // Ältere Server ohne Laufstand.
  mResponse := TJSONObject.ParseJSONValue('{"items":[]}');
  try
    Assert.IsFalse(TLspWorkspaceRun.FromJson(mResponse).Known);
  finally
    mResponse.Free;
  end;
  mRun := Default(TLspWorkspaceRun);
end;
procedure TLspSessionTests.InitializeAnnouncesPullDiagnosticsAndCountsRefresh;
var
  mClient: TLspClient;
  mSession: TLspSession;
  mCapabilities: string;
begin
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Message: TJSONObject;
      Reply: TBytes;
    begin
      Message := Unframe(ABytes);
      try
        if Message.GetValue<string>('method', '') = 'initialize' then
        begin
          mCapabilities := Message.GetValue<TJSONObject>('params.capabilities').ToJSON;
          Reply := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":{"capabilities":{}}}',
            [Message.GetValue<Integer>('id')]));
          mClient.Receive(Reply, Length(Reply));
        end;
      finally
        Message.Free;
      end;
    end);
  mSession := TLspSession.Create(mClient);
  try
    mSession.Initialize;
    Assert.Contains(mCapabilities, '"diagnostic":{"dynamicRegistration":false');
    // Seit #648 meldet der Client unter "workspace" auch workspaceFolders; geprüft wird nur refreshSupport.
    Assert.Contains(mCapabilities, '"diagnostics":{"refreshSupport":true}');
    Assert.AreEqual(0, mSession.RefreshCount);
    mClient.Receive(TLspClient.Frame('{"jsonrpc":"2.0","id":"r1","method":"workspace/diagnostic/refresh"}'),
      Length(TLspClient.Frame('{"jsonrpc":"2.0","id":"r1","method":"workspace/diagnostic/refresh"}')));
    Assert.AreEqual(1, mSession.RefreshCount);
  finally
    mSession.Free;
    mClient.Free;
  end;
end;
procedure TLspSessionTests.WrapsServerSettings;
var
  mParams: TJSONObject;
begin
  // Wie didChangeConfiguration aus VS Code: settings.atlas (#652).
  mParams := TLspSession.SettingsParams('{"index":{"libraryPaths":true}}');
  try
    Assert.IsTrue(mParams.GetValue<Boolean>('settings.atlas.index.libraryPaths'));
  finally
    mParams.Free;
  end;
  mParams := TLspSession.SettingsParams('kein JSON');
  try
    Assert.AreEqual('{"settings":{"atlas":{}}}', mParams.ToJSON);
  finally
    mParams.Free;
  end;
end;
procedure TLspSessionTests.ReadsShowMessageParams;
var
  mParams: TJSONValue;
  mMessageType: Integer;
  mText: string;
begin
  // Hinweis auf gemischte Kodierungen kommt als window/showMessage (#121).
  mParams := TJSONObject.ParseJSONValue('{"type": 2, "message": "Gemischte Kodierungen"}');
  try
    Assert.IsTrue(TLspSession.ShowMessageParams(mParams, mMessageType, mText));
    Assert.AreEqual(2, mMessageType);
    Assert.AreEqual('Gemischte Kodierungen', mText);
  finally
    mParams.Free;
  end;
  mParams := TJSONObject.ParseJSONValue('{"type": 1}');
  try
    Assert.IsFalse(TLspSession.ShowMessageParams(mParams, mMessageType, mText));
  finally
    mParams.Free;
  end;
  Assert.IsFalse(TLspSession.ShowMessageParams(nil, mMessageType, mText));
end;
procedure TLspSessionTests.ReportsProjectGroupChanges;
var
  mFolders: TJSONArray;
  mAdded, mRemoved: TArray<string>;
begin
  mFolders := TLspSession.ProjectFolders(['C:\Gruppe\App\App.dproj']);
  try
    Assert.AreEqual(1, Integer(mFolders.Count));
    Assert.AreEqual(TLspSession.PathToUri('C:\Gruppe\App\App.dproj'), mFolders.Items[0].GetValue<string>('uri'));
    Assert.AreEqual('App', mFolders.Items[0].GetValue<string>('name'));
  finally
    mFolders.Free;
  end;
  // Groß- und Kleinschreibung zählt nicht; Doppelte nur einmal.
  TLspSession.ProjectChanges(['C:\G\A.dproj', 'C:\G\B.dproj'], ['c:\g\a.dproj', 'C:\G\C.dproj', 'C:\G\C.dproj'],
    mAdded, mRemoved);
  Assert.AreEqual<NativeInt>(1, Length(mAdded));
  Assert.AreEqual('C:\G\C.dproj', mAdded[0]);
  Assert.AreEqual<NativeInt>(1, Length(mRemoved));
  Assert.AreEqual('C:\G\B.dproj', mRemoved[0]);
  TLspSession.ProjectChanges(['C:\G\A.dproj'], ['C:\G\A.dproj'], mAdded, mRemoved);
  Assert.AreEqual<NativeInt>(0, Length(mAdded) + Length(mRemoved));
end;
procedure TLspSessionTests.FreesApplyEditIdWithoutReply;
var
  mClient: TLspClient;
  mSession: TLspSession;
  mSent: TList<string>;
  mCalls: Integer;
  mIncoming: TBytes;
begin
  mSent := TList<string>.Create;
  mCalls := 0;
  mClient := ApplyEditClient(mSent);
  mSession := TLspSession.Create(mClient);
  try
    // Wie ein beim Entladen verworfener Eintrag: Die Antwort-Prozedur wird nie gerufen.
    mSession.OnApplyEdit :=
      procedure(const AEdit: TLspWorkspaceEdit; const AReply: TLspApplyEditReply)
      begin
        Inc(mCalls);
      end;
    mSession.Initialize;
    mIncoming := TLspClient.Frame(cApplyEditRequest);
    mClient.Receive(mIncoming, Length(mIncoming));
    Assert.AreEqual(1, mCalls);
    // Keine Antwort; die Id gibt die Sitzung frei (der Leak-Monitor prüft das).
    Assert.AreEqual(0, Integer(mSent.Count));
  finally
    mSession.OnApplyEdit := nil;
    mSession.Free;
    mClient.Free;
    mSent.Free;
  end;
end;
procedure TLspSessionTests.RepliesToApplyEditOnlyOnce;
var
  mClient: TLspClient;
  mSession: TLspSession;
  mSent: TList<string>;
  mReply: TLspApplyEditReply;
  mIncoming: TBytes;
begin
  mSent := TList<string>.Create;
  mClient := ApplyEditClient(mSent);
  mSession := TLspSession.Create(mClient);
  try
    mSession.OnApplyEdit :=
      procedure(const AEdit: TLspWorkspaceEdit; const AReply: TLspApplyEditReply)
      begin
        mReply := AReply;
      end;
    mSession.Initialize;
    mIncoming := TLspClient.Frame(cApplyEditRequest);
    mClient.Receive(mIncoming, Length(mIncoming));
    mReply(True, '');
    mReply(True, '');
    Assert.AreEqual(1, Integer(mSent.Count), 'genau eine Antwort');
    Assert.AreEqual('{"jsonrpc":"2.0","id":7,"result":{"applied":true}}', mSent[0]);
  finally
    mReply := nil;
    mSession.OnApplyEdit := nil;
    mSession.Free;
    mClient.Free;
    mSent.Free;
  end;
end;
{ TLspClientTests (Obergrenzen) }

procedure TLspClientTests.RejectsOversizedContentLength;
var
  mClient: TLspClient;
  mIncoming: TBytes;
begin
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
    end);
  try
    mIncoming := TEncoding.UTF8.GetBytes('Content-Length: 300000000'#13#10#13#10'{');
    Assert.WillRaise(
      procedure
      begin
        mClient.Receive(mIncoming, Length(mIncoming));
      end, ELspClientError);
  finally
    mClient.Free;
  end;
end;
procedure TLspClientTests.RejectsHeaderWithoutEnd;
var
  mClient: TLspClient;
  mIncoming: TBytes;
begin
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
    end);
  try
    mIncoming := TEncoding.UTF8.GetBytes(StringOfChar('x', 9000));
    Assert.WillRaise(
      procedure
      begin
        mClient.Receive(mIncoming, Length(mIncoming));
      end, ELspClientError);
  finally
    mClient.Free;
  end;
end;
procedure TLspClientTests.AcceptsMessageAtHeaderLimit;
const
  cBody = '{"jsonrpc":"2.0","method":"window/logMessage","params":{"type":3}}';
var
  mClient: TLspClient;
  mSeen: TList<string>;
  mHeader: string;
  mIncoming: TBytes;
begin
  mSeen := TList<string>.Create;
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
    end);
  try
    mClient.OnServerMessage :=
      procedure(const AMethod: string; const AParams: TJSONValue)
      begin
        mSeen.Add(AMethod);
      end;
    // Kopf knapp unter der Grenze: ein langes Füllfeld vor Content-Length.
    mHeader := 'X-Fill: ' + StringOfChar('a', TLspClient.cMaxHeaderLength - 40) + #13#10 +
      'Content-Length: ' + IntToStr(Length(cBody)) + #13#10#13#10;
    Assert.IsTrue(Length(mHeader) - 4 <= TLspClient.cMaxHeaderLength, 'Kopf innerhalb der Grenze');
    mIncoming := TEncoding.UTF8.GetBytes(mHeader + cBody);
    mClient.Receive(mIncoming, Length(mIncoming));
    Assert.AreEqual(1, Integer(mSeen.Count));
    Assert.AreEqual('window/logMessage', mSeen[0]);
  finally
    mClient.Free;
    mSeen.Free;
  end;
end;
/// <summary>Client, der je Methode mit AReplies[Methode] antwortet und die Parameter in ASeen sammelt.</summary>
function CannedClient(const AReplies: TDictionary<string, string>; ASeen: TStrings): TLspClient;
var
  mClient: TLspClient;
begin
  mClient := nil;
  mClient := TLspClient.Create(
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
        mClient.Receive(Reply, Length(Reply));
      finally
        Message.Free;
      end;
    end);
  Result := mClient;
end;
procedure TLspSessionTests.ReadsImplementationsAndSymbols;
var
  mReplies: TDictionary<string, string>;
  mSeen: TStringList;
  mClient: TLspClient;
  mSession: TLspSession;
  mLocations: TArray<TLspLocation>;
  mSymbols: TArray<TAtlasSymbol>;
  mSingle: TJSONValue;
begin
  mReplies := TDictionary<string, string>.Create;
  mSeen := TStringList.Create;
  mClient := CannedClient(mReplies, mSeen);
  mSession := TLspSession.Create(mClient);
  try
    // LocationLink: Ziel ist der Name (targetSelectionRange), nicht der ganze Rumpf.
    mReplies.Add('textDocument/implementation', '[{"targetUri":"file:///c:/p/b.pas",' +
      '"targetRange":{"start":{"line":10,"character":0},"end":{"line":20,"character":4}},' +
      '"targetSelectionRange":{"start":{"line":10,"character":17},"end":{"line":10,"character":21}}}]');
    mReplies.Add('workspace/symbol', '[{"name":"TKunde","kind":5,"containerName":"Kunden",' +
      '"location":{"uri":"file:///c:/p/kunden.pas","range":{"start":{"line":7,"character":2},' +
      '"end":{"line":7,"character":8}}}},{"name":"ohne Ort","kind":12}]');
    mLocations := mSession.Implementations('C:\P\A.pas', 3, 4);
    Assert.AreEqual(1, Integer(Length(mLocations)));
    Assert.AreEqual('c:\p\b.pas', mLocations[0].FileName);
    Assert.AreEqual(10, mLocations[0].Line);
    Assert.AreEqual(17, mLocations[0].Character);
    mSymbols := mSession.WorkspaceSymbols('Kun', 1000);
    Assert.AreEqual(1, Integer(Length(mSymbols)), 'Symbole ohne Ort entfallen');
    Assert.AreEqual('TKunde', mSymbols[0].Name);
    Assert.AreEqual('Kunden', mSymbols[0].Container);
    Assert.AreEqual(5, mSymbols[0].Kind);
    Assert.AreEqual('c:\p\kunden.pas', mSymbols[0].FileName);
    Assert.AreEqual(7, mSymbols[0].Line);
    Assert.Contains(mSeen.Text, 'workspace/symbol {"query":"Kun"}');
    // Einzelne Location statt Liste.
    mSingle := TJSONObject.ParseJSONValue('{"uri":"file:///c:/p/c.pas","range":{"start":{"line":1,"character":2}}}');
    try
      Assert.AreEqual(1, Integer(Length(TLspSession.LocationsOf(mSingle))));
    finally
      mSingle.Free;
    end;
  finally
    mSession.Free;
    mClient.Free;
    mSeen.Free;
    mReplies.Free;
  end;
end;
procedure TLspSessionTests.WalksCallAndTypeHierarchies;
const
  cItem = '{"name":"%s","kind":12,"detail":"%s","uri":"file:///c:/p/a.pas",' +
    '"range":{"start":{"line":%d,"character":0},"end":{"line":%d,"character":9}},' +
    '"selectionRange":{"start":{"line":%d,"character":10},"end":{"line":%d,"character":15}},"data":{"id":%d}}';
var
  mReplies: TDictionary<string, string>;
  mSeen: TStringList;
  mClient: TLspClient;
  mSession: TLspSession;
  mRoots, mCallers, mSupers, mCallees: TArray<TAtlasHierarchyItem>;
begin
  mReplies := TDictionary<string, string>.Create;
  mSeen := TStringList.Create;
  mClient := CannedClient(mReplies, mSeen);
  mSession := TLspSession.Create(mClient);
  try
    mReplies.Add('textDocument/prepareCallHierarchy', '[' + Format(cItem, ['Laden', 'TKunde', 4, 9, 4, 4, 1]) + ']');
    mReplies.Add('callHierarchy/incomingCalls', '[{"from":' + Format(cItem, ['Start', 'TForm1', 30, 40, 30, 30, 2]) +
      ',"fromRanges":[]}]');
    // Aufruf über ein Interface mit zwei Umsetzungen (#1122) und ein gewöhnlicher.
    mReplies.Add('callHierarchy/outgoingCalls', '[{"to":' + Format(cItem, ['Speichern', 'ISpeicher', 7, 7, 7, 7, 5]) +
      ',"fromRanges":[],"atlasDispatch":{"kind":"interface","implementations":2}},{"to":' +
      Format(cItem, ['Fertig', '', 8, 8, 8, 8, 6]) + ',"fromRanges":[]}]');
    mReplies.Add('textDocument/prepareTypeHierarchy', '[' + Format(cItem, ['TKunde', '', 2, 2, 2, 2, 3]) + ']');
    mReplies.Add('typeHierarchy/supertypes', '[' + Format(cItem, ['TPerson', '', 1, 1, 1, 1, 4]) + ']');
    mRoots := mSession.PrepareHierarchy(TAtlasHierarchyDirection.Incoming, 'C:\P\A.pas', 4, 12);
    Assert.AreEqual(1, Integer(Length(mRoots)));
    Assert.AreEqual('Laden', mRoots[0].Name);
    Assert.AreEqual('TKunde', mRoots[0].Detail);
    Assert.AreEqual(4, mRoots[0].Line);
    Assert.AreEqual(10, mRoots[0].Character);
    mCallers := mSession.HierarchyChildren(TAtlasHierarchyDirection.Incoming, mRoots[0]);
    Assert.AreEqual(1, Integer(Length(mCallers)));
    Assert.AreEqual('Start', mCallers[0].Name);
    Assert.AreEqual(30, mCallers[0].Line);
    // Der Server bekommt seinen Eintrag samt data zurück.
    Assert.Contains(mSeen.Text, 'callHierarchy/incomingCalls {"item":{"name":"Laden"');
    Assert.Contains(mSeen.Text, '"data":{"id":1}');
    mCallees := mSession.HierarchyChildren(TAtlasHierarchyDirection.Outgoing, mRoots[0]);
    Assert.AreEqual(2, Integer(Length(mCallees)));
    Assert.AreEqual('interface', mCallees[0].Dispatch);
    Assert.AreEqual(2, mCallees[0].Implementations);
    Assert.AreEqual('', mCallees[1].Dispatch);
    Assert.AreEqual(0, mCallees[1].Implementations);
    mRoots := mSession.PrepareHierarchy(TAtlasHierarchyDirection.Supertypes, 'C:\P\A.pas', 2, 3);
    mSupers := mSession.HierarchyChildren(TAtlasHierarchyDirection.Supertypes, mRoots[0]);
    Assert.AreEqual(1, Integer(Length(mSupers)));
    Assert.AreEqual('TPerson', mSupers[0].Name);
  finally
    mSession.Free;
    mClient.Free;
    mSeen.Free;
    mReplies.Free;
  end;
end;
procedure TLspSessionTests.ReadsCodeActionsAndRunsCommands;
var
  mReplies: TDictionary<string, string>;
  mSeen: TStringList;
  mClient: TLspClient;
  mSession: TLspSession;
  mActions: TArray<TLspCodeAction>;
  mAnswer: TJSONValue;
begin
  mReplies := TDictionary<string, string>.Create;
  mSeen := TStringList.Create;
  mClient := CannedClient(mReplies, mSeen);
  mSession := TLspSession.Create(mClient);
  try
    mReplies.Add('textDocument/codeAction', '[{"title":"try/finally ergänzen","kind":"refactor.rewrite",' +
      '"isPreferred":true,"edit":{"changes":{"file:///c:/p/a.pas":[{"range":{"start":{"line":2,"character":0},' +
      '"end":{"line":2,"character":0}},"newText":"try"}]}}},' +
      '{"title":"Befund kopieren","kind":"quickfix","command":{"title":"Befund kopieren","command":"atlas.copyText",' +
      '"arguments":["Text"]},"edit":{"changes":{}}},' +
      '{"title":"Status","command":"atlas.server.status"},' +
      '{"title":"Gesperrt","disabled":{"reason":"nur in Methoden"}},{"kind":"ohne Titel"}]');
    mReplies.Add('workspace/executeCommand', '"Unit1.TForm1.Button1Click"');
    mActions := mSession.CodeActions('C:\P\A.pas', TLspRange.Create(2, 4, 2, 9));
    Assert.AreEqual(4, Integer(Length(mActions)), 'Einträge ohne Titel entfallen');
    Assert.AreEqual('try/finally ergänzen', mActions[0].Title);
    Assert.IsTrue(mActions[0].Preferred);
    Assert.AreEqual(1, mActions[0].Edit.EditCount);
    Assert.AreEqual('', mActions[0].Command);
    Assert.AreEqual('atlas.copyText', mActions[1].Command);
    Assert.AreEqual('["Text"]', mActions[1].ArgumentsJson);
    Assert.IsTrue(mActions[1].Edit.IsEmpty);
    Assert.AreEqual('atlas.server.status', mActions[2].Command, 'Command statt CodeAction');
    Assert.AreEqual('[]', mActions[2].ArgumentsJson);
    Assert.AreEqual('nur in Methoden', mActions[3].Disabled);
    Assert.Contains(mSeen.Text, '"range":{"start":{"line":2,"character":4},"end":{"line":2,"character":9}}');
    Assert.Contains(mSeen.Text, '"triggerKind":1');
    mAnswer := mSession.RunCommand('atlas.server.qualifiedName', '["file:///c:/p/a.pas",{"line":1,"character":2}]', 1000);
    try
      Assert.AreEqual('Unit1.TForm1.Button1Click', mAnswer.Value);
    finally
      mAnswer.Free;
    end;
    Assert.Contains(mSeen.Text, '"arguments":["file:///c:/p/a.pas",{"line":1,"character":2}]');
    mAnswer := mSession.RunCommand('atlas.server.status', '', 1000);
    mAnswer.Free;
    Assert.Contains(mSeen.Text, '{"command":"atlas.server.status","arguments":[]}');
  finally
    mSession.Free;
    mClient.Free;
    mSeen.Free;
    mReplies.Free;
  end;
end;
procedure TLspSessionTests.RequestsTypingSelectionAndTypeDefinition;
var
  mReplies: TDictionary<string, string>;
  mSeen: TStringList;
  mClient: TLspClient;
  mSession: TLspSession;
  mEdits: TArray<TLspTextEdit>;
  mRanges: TArray<TLspRange>;
  mLocations: TArray<TLspLocation>;
begin
  mReplies := TDictionary<string, string>.Create;
  mSeen := TStringList.Create;
  mClient := CannedClient(mReplies, mSeen);
  mSession := TLspSession.Create(mClient);
  try
    mReplies.Add('textDocument/onTypeFormatting', '[{"range":{"start":{"line":4,"character":0},' +
      '"end":{"line":5,"character":0}},"newText":"uses\r\n  Unit2;\r\n"}]');
    mReplies.Add('textDocument/selectionRange', '[{"range":{"start":{"line":3,"character":2},' +
      '"end":{"line":3,"character":7}},"parent":{"range":{"start":{"line":3,"character":2},' +
      '"end":{"line":3,"character":20}},"parent":{"range":{"start":{"line":0,"character":0},' +
      '"end":{"line":9,"character":0}}}}}]');
    mReplies.Add('textDocument/typeDefinition', '{"uri":"file:///c:/p/kunde.pas","range":{"start":' +
      '{"line":12,"character":2},"end":{"line":12,"character":8}}}');
    mEdits := mSession.OnTypeFormatting('C:\P\A.pas', 5, 0, #10, TLspFormatOptions.Create(2, True), 1000);
    Assert.AreEqual(1, Integer(Length(mEdits)));
    Assert.AreEqual(4, mEdits[0].StartPos.Line);
    Assert.AreEqual('uses'#13#10'  Unit2;'#13#10, mEdits[0].NewText);
    // Zeilenumbruch als \n oder \u000A, je nach Delphi-Version.
    Assert.IsTrue(mSeen.Text.Contains('"ch":"\n"') or mSeen.Text.Contains('"ch":"\u000A"'), mSeen.Text);
    Assert.Contains(mSeen.Text, '"options":{"tabSize":2,"insertSpaces":true}');
    mRanges := mSession.SelectionRanges('C:\P\A.pas', 3, 4);
    Assert.AreEqual(3, Integer(Length(mRanges)), 'innen zuerst bis zur Datei');
    Assert.AreEqual(7, mRanges[0].EndPos.Character);
    Assert.AreEqual(20, mRanges[1].EndPos.Character);
    Assert.AreEqual(9, mRanges[2].EndPos.Line);
    Assert.Contains(mSeen.Text, '"positions":[{"line":3,"character":4}]');
    mLocations := mSession.TypeDefinition('C:\P\A.pas', 3, 4);
    Assert.AreEqual(1, Integer(Length(mLocations)));
    Assert.AreEqual(12, mLocations[0].Line);
  finally
    mSession.Free;
    mClient.Free;
    mSeen.Free;
    mReplies.Free;
  end;
end;
procedure TLspSessionTests.RequestsFormatting;
var
  mReplies: TDictionary<string, string>;
  mSeen: TStringList;
  mClient: TLspClient;
  mSession: TLspSession;
  mEdits: TArray<TLspTextEdit>;
begin
  mReplies := TDictionary<string, string>.Create;
  mSeen := TStringList.Create;
  mClient := CannedClient(mReplies, mSeen);
  mSession := TLspSession.Create(mClient);
  try
    mReplies.Add('textDocument/formatting', '[{"range":{"start":{"line":2,"character":0},' +
      '"end":{"line":2,"character":4}},"newText":"  A;"},{"range":{"start":{"line":3,"character":0},' +
      '"end":{"line":3,"character":1}},"newText":""}]');
    mReplies.Add('textDocument/rangeFormatting', '[]');
    mEdits := mSession.Formatting('C:\P\A.pas', 4, False, 1000);
    Assert.AreEqual(2, Integer(Length(mEdits)));
    Assert.AreEqual('  A;', mEdits[0].NewText);
    Assert.AreEqual(3, mEdits[1].StartPos.Line);
    Assert.Contains(mSeen.Text, '"options":{"tabSize":4,"insertSpaces":false}');
    mEdits := mSession.Formatting('C:\P\A.pas', TLspRange.Create(1, 0, 3, 0), 2, True, 1000);
    Assert.AreEqual(0, Integer(Length(mEdits)));
    Assert.Contains(mSeen.Text, '"range":{"start":{"line":1,"character":0},"end":{"line":3,"character":0}}');
  finally
    mSession.Free;
    mClient.Free;
    mSeen.Free;
    mReplies.Free;
  end;
end;
procedure TLspSessionTests.RequestsLinkedLocals;
var
  mReplies: TDictionary<string, string>;
  mSeen: TStringList;
  mClient: TLspClient;
  mSession: TLspSession;
  mAnswer: TJSONValue;
begin
  mReplies := TDictionary<string, string>.Create;
  mSeen := TStringList.Create;
  mClient := CannedClient(mReplies, mSeen);
  mSession := TLspSession.Create(mClient);
  try
    mReplies.Add('textDocument/linkedEditingRange', '{"ranges":[{"start":{"line":3,"character":2},' +
      '"end":{"line":3,"character":8}}],"atlasConflicts":[]}');
    mAnswer := mSession.LinkedLocals('C:\P\A.pas', 3, 4);
    try
      Assert.IsTrue(mAnswer is TJSONObject);
      Assert.AreEqual(1, TJSONObject(mAnswer).GetValue<TJSONArray>('ranges').Count);
    finally
      mAnswer.Free;
    end;
    Assert.Contains(mSeen.Text, '"atlasLocals":true');
    Assert.Contains(mSeen.Text, '"position":{"line":3,"character":4}');
  finally
    mSession.Free;
    mClient.Free;
    mSeen.Free;
    mReplies.Free;
  end;
end;
procedure TLspSessionTests.RequestsDeclarationsAndDefinitions;
var
  mReplies: TDictionary<string, string>;
  mSeen: TStringList;
  mClient: TLspClient;
  mSession: TLspSession;
  mLocations: TArray<TLspLocation>;
begin
  mReplies := TDictionary<string, string>.Create;
  mSeen := TStringList.Create;
  mClient := CannedClient(mReplies, mSeen);
  mSession := TLspSession.Create(mClient);
  try
    mReplies.Add('textDocument/declaration', '[{"uri":"file:///c:/p/kunde.pas","range":{"start":' +
      '{"line":12,"character":4},"end":{"line":12,"character":8}}}]');
    mReplies.Add('textDocument/definition', '[{"uri":"file:///c:/p/kunde.pas","range":{"start":' +
      '{"line":40,"character":15},"end":{"line":40,"character":19}}},{"uri":"file:///c:/p/b.pas","range":' +
      '{"start":{"line":2,"character":0},"end":{"line":2,"character":1}}}]');
    mLocations := mSession.Declarations('C:\P\A.pas', 3, 4);
    Assert.AreEqual(1, Integer(Length(mLocations)));
    Assert.AreEqual(12, mLocations[0].Line);
    Assert.AreEqual(4, mLocations[0].Character);
    Assert.Contains(mSeen.Text, 'textDocument/declaration');
    mLocations := mSession.Definitions('C:\P\A.pas', 3, 4);
    Assert.AreEqual(2, Integer(Length(mLocations)));
    Assert.AreEqual(40, mLocations[0].Line);
    Assert.AreEqual(2, mLocations[1].Line);
  finally
    mSession.Free;
    mClient.Free;
    mSeen.Free;
    mReplies.Free;
  end;
end;
procedure TLspSessionTests.MapsIndexBackToColumn;
var
  mLine: string;
  mIndex: Integer;
begin
  Assert.AreEqual(1, TLspSession.IndexToColumn('abc', 0, 8));
  Assert.AreEqual(3, TLspSession.IndexToColumn('abc', 2, 8));
  Assert.AreEqual(9, TLspSession.IndexToColumn(#9'x', 1, 8), 'Tab bis zur nächsten Tabulatorposition');
  Assert.AreEqual(6, TLspSession.IndexToColumn('abc', 5, 8), 'hinter dem Zeilenende je Zeichen eine Spalte');
  // Umkehrung von ColumnToIndex innerhalb der Zeile.
  mLine := 'a'#9'bc'#9#9'd';
  for mIndex := 0 to Length(mLine) do
  begin
    Assert.AreEqual(mIndex, TLspSession.ColumnToIndex(mLine, TLspSession.IndexToColumn(mLine, mIndex, 4), 4));
  end;
end;
initialization
  TDUnitX.RegisterTestFixture(TLspClientTests);
  TDUnitX.RegisterTestFixture(TLspSessionTests);

end.
