unit Atlas.Core.Assistants.LinkProtocol.Tests;

// Assistenten-Kopplung (#2377): Nachrichten des Protokolls gegen eine gefälschte IDE. initialize mit Name des
// Clients, tools/list mit und ohne Vorschau (nie executeCode), Auswahl, openFile, Dateizustand, Speichern in der
// Pause, Befunde je Datei, openDiff mit Antwort erst nach der Entscheidung, Fehler nach JSON-RPC, Pfade als URI.

interface

uses
  System.SysUtils,
  System.JSON,
  DUnitX.TestFramework,
  Atlas.Core.Assistants.Contract.Link,
  Atlas.Core.Assistants.LinkProtocol;

type
  TFakePeer = class(TInterfacedObject, IAtlasLinkPeer)
  public
    Sent: TArray<string>;
    procedure Send(const AJson: string);
    function Last: string;
  end;

  TFakeIde = class(TInterfacedObject, IAtlasLinkIde)
  public
    Selection: TAtlasLinkSelection;
    Tabs: TArray<TAtlasLinkTab>;
    Folders: TArray<string>;
    Items: TArray<TAtlasLinkDiagnostic>;
    OpenFiles: TArray<string>;
    DirtyFiles: TArray<string>;
    Saved: string;
    IsPaused: Boolean;
    LastOpen: TAtlasLinkOpenRequest;
    LastDiff: TAtlasLinkDiffRequest;
    DiffDone: TAtlasLinkDiffDone;
    Closed: string;
    function WorkspaceFolders: TArray<string>;
    function OpenTabs: TArray<TAtlasLinkTab>;
    function CurrentSelection: TAtlasLinkSelection;
    function LatestSelection: TAtlasLinkSelection;
    function OpenFile(const ARequest: TAtlasLinkOpenRequest): TAtlasLinkOpenResult;
    function Document(const AFileName: string): TAtlasLinkDocument;
    function SaveDocument(const AFileName: string): Boolean;
    function Diagnostics(const AFileName: string): TArray<TAtlasLinkDiagnostic>;
    procedure OpenDiff(const ARequest: TAtlasLinkDiffRequest; const ADone: TAtlasLinkDiffDone);
    function CloseTab(const ATabName: string): Boolean;
    function CloseAllDiffs: Integer;
    function Paused: Boolean;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasLinkProtocolTests = class
  private
    FIde: TFakeIde;
    FIdeRef: IAtlasLinkIde;
    FPeer: TFakePeer;
    FPeerRef: IAtlasLinkPeer;
    FSession: TAtlasLinkSession;
    function Call(const ATool, AArguments: string): string;
    /// <summary>Text des ersten Inhalts der letzten Antwort auf tools/call.</summary>
    function ToolText(const AReply: string; AIndex: Integer = 0): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure InitializeNamesClient;
    [Test]
    procedure ToolsFollowDiffPreview;
    [Test]
    procedure SelectionWithAndWithoutEditor;
    [Test]
    procedure OpenFileReportsMissingFiles;
    [Test]
    procedure DocumentStateAndSave;
    [Test]
    procedure DiagnosticsGroupedByFile;
    [Test]
    procedure OpenDiffAnswersAfterDecision;
    [Test]
    procedure OpenDiffRejected;
    [Test]
    procedure PauseRefusesChanges;
    [Test]
    procedure ErrorsFollowJsonRpc;
    [Test]
    procedure UrisRoundTrip;
    [Test]
    procedure NotificationsCarryFields;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Text.Json;

{ TFakePeer }

procedure TFakePeer.Send(const AJson: string);
begin
  Sent := Sent + [AJson];
end;

function TFakePeer.Last: string;
begin
  Result := '';
  if Length(Sent) > 0 then
  begin
    Result := Sent[High(Sent)];
  end;
end;

{ TFakeIde }

function TFakeIde.WorkspaceFolders: TArray<string>;
begin
  Result := Folders;
end;

function TFakeIde.OpenTabs: TArray<TAtlasLinkTab>;
begin
  Result := Tabs;
end;

function TFakeIde.CurrentSelection: TAtlasLinkSelection;
begin
  Result := Selection;
end;

function TFakeIde.LatestSelection: TAtlasLinkSelection;
begin
  Result := Selection;
end;

function TFakeIde.OpenFile(const ARequest: TAtlasLinkOpenRequest): TAtlasLinkOpenResult;
begin
  LastOpen := ARequest;
  Result := Default(TAtlasLinkOpenResult);
  Result.Opened := IndexStr(ARequest.FileName, OpenFiles) >= 0;
  Result.LineCount := 42;
end;

function TFakeIde.Document(const AFileName: string): TAtlasLinkDocument;
begin
  Result := Default(TAtlasLinkDocument);
  Result.Open := IndexStr(AFileName, OpenFiles) >= 0;
  Result.Dirty := IndexStr(AFileName, DirtyFiles) >= 0;
end;

function TFakeIde.SaveDocument(const AFileName: string): Boolean;
begin
  Saved := AFileName;
  Result := True;
end;

function TFakeIde.Diagnostics(const AFileName: string): TArray<TAtlasLinkDiagnostic>;
var
  mItem: TAtlasLinkDiagnostic;
begin
  Result := nil;
  for mItem in Items do
  begin
    if (AFileName = '') or (mItem.FileName = AFileName) then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

procedure TFakeIde.OpenDiff(const ARequest: TAtlasLinkDiffRequest; const ADone: TAtlasLinkDiffDone);
begin
  LastDiff := ARequest;
  DiffDone := ADone;
end;

function TFakeIde.CloseTab(const ATabName: string): Boolean;
begin
  Closed := ATabName;
  Result := True;
end;

function TFakeIde.CloseAllDiffs: Integer;
begin
  Result := 3;
end;

function TFakeIde.Paused: Boolean;
begin
  Result := IsPaused;
end;

{ TAtlasLinkProtocolTests }

procedure TAtlasLinkProtocolTests.Setup;
begin
  FIde := TFakeIde.Create;
  FIdeRef := FIde;
  FPeer := TFakePeer.Create;
  FPeerRef := FPeer;
  FSession := TAtlasLinkSession.Create(FIdeRef, FPeerRef, '2.3.0');
end;

procedure TAtlasLinkProtocolTests.TearDown;
begin
  FreeAndNil(FSession);
  FIde.DiffDone := nil;
  FIde := nil;
  FIdeRef := nil;
  FPeer := nil;
  FPeerRef := nil;
end;

function TAtlasLinkProtocolTests.Call(const ATool, AArguments: string): string;
begin
  FSession.Handle('{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"' + ATool + '","arguments":' +
    AArguments + '}}');
  Result := FPeer.Last;
end;

function TAtlasLinkProtocolTests.ToolText(const AReply: string; AIndex: Integer): string;
var
  mRoot: TJSONObject;
  mContent: TJSONArray;
begin
  Result := '';
  mRoot := TJsonRead.ParseObject(AReply);
  try
    mContent := TJsonRead.Items(TJsonRead.Obj(mRoot, 'result'), 'content');
    if (mContent <> nil) and (mContent.Count > AIndex) then
    begin
      Result := TJsonRead.Text(TJsonRead.AsObject(mContent.Items[AIndex]), 'text');
    end;
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasLinkProtocolTests.InitializeNamesClient;
begin
  FSession.Handle('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18",' +
    '"clientInfo":{"name":"Assistent","version":"1"}}}');
  Assert.IsTrue(FSession.Initialized);
  Assert.AreEqual('Assistent', FSession.ClientName);
  Assert.Contains(FPeer.Last, '"id":1');
  Assert.Contains(FPeer.Last, '"protocolVersion":"2025-06-18"');
  Assert.Contains(FPeer.Last, '"serverInfo":{"name":"atlas-ide","version":"2.3.0"}');
  FSession.Handle('{"jsonrpc":"2.0","method":"notifications/initialized"}');
  Assert.AreEqual(1, Integer(Length(FPeer.Sent)), 'Benachrichtigung ohne Antwort');
end;

procedure TAtlasLinkProtocolTests.ToolsFollowDiffPreview;
begin
  FSession.Handle('{"jsonrpc":"2.0","id":"a","method":"tools/list"}');
  Assert.Contains(FPeer.Last, '"id":"a"');
  Assert.Contains(FPeer.Last, '"name":"openDiff"');
  Assert.Contains(FPeer.Last, '"name":"getDiagnostics"');
  Assert.DoesNotContain(FPeer.Last, 'executeCode');
  FSession.OffersDiffs := False;
  FSession.Handle('{"jsonrpc":"2.0","id":2,"method":"tools/list"}');
  Assert.DoesNotContain(FPeer.Last, 'openDiff');
  Assert.DoesNotContain(FPeer.Last, 'close_tab');
  Assert.Contains(Call('openDiff', '{}'), '"code":-32602', 'ohne Vorschau unbekannt');
  Assert.Contains(Call('executeCode', '{"code":"1"}'), 'Unknown tool');
end;

procedure TAtlasLinkProtocolTests.SelectionWithAndWithoutEditor;
var
  mText: string;
begin
  mText := ToolText(Call('getCurrentSelection', '{}'));
  Assert.Contains(mText, '"success":false');
  Assert.Contains(mText, 'No active editor found');
  FIde.Selection.Known := True;
  FIde.Selection.FileName := 'C:\Q\Kunde.pas';
  FIde.Selection.Text := 'Result := 1;';
  FIde.Selection.Start := TAtlasLinkPosition.At(4, 2);
  FIde.Selection.Stop := TAtlasLinkPosition.At(4, 14);
  mText := ToolText(Call('getLatestSelection', '{}'));
  Assert.Contains(mText, '"success":true');
  Assert.Contains(mText, '"filePath":"C:\\Q\\Kunde.pas"');
  Assert.Contains(mText, '"start":{"line":4,"character":2}');
  Assert.Contains(mText, '"isEmpty":false');
end;

procedure TAtlasLinkProtocolTests.OpenFileReportsMissingFiles;
var
  mReply: string;
begin
  mReply := Call('openFile', '{"filePath":"C:\\Q\\Fehlt.pas"}');
  Assert.Contains(mReply, '"isError":true');
  Assert.Contains(ToolText(mReply), 'File not found');
  FIde.OpenFiles := ['C:\Q\Kunde.pas'];
  mReply := Call('openFile', '{"filePath":"file:///C:/Q/Kunde.pas","startText":"begin","endText":"end",' +
    '"makeFrontmost":false}');
  Assert.AreEqual('C:\Q\Kunde.pas', FIde.LastOpen.FileName, 'URI als Pfad');
  Assert.AreEqual('begin', FIde.LastOpen.StartText);
  Assert.AreEqual('end', FIde.LastOpen.EndText);
  Assert.Contains(ToolText(mReply), '"lineCount":42');
  Assert.Contains(ToolText(mReply), '"languageId":"pascal"');
  Assert.AreEqual('Opened file: C:\Q\Kunde.pas', ToolText(Call('openFile', '{"filePath":"C:\\Q\\Kunde.pas"}')));
end;

procedure TAtlasLinkProtocolTests.DocumentStateAndSave;
begin
  FIde.OpenFiles := ['C:\Q\Kunde.pas'];
  FIde.DirtyFiles := ['C:\Q\Kunde.pas'];
  Assert.Contains(ToolText(Call('checkDocumentDirty', '{"filePath":"C:\\Q\\Kunde.pas"}')), '"isDirty":true');
  Assert.Contains(ToolText(Call('checkDocumentDirty', '{"filePath":"C:\\Q\\Zu.pas"}')),
    'Document not open: C:\\Q\\Zu.pas');
  Assert.Contains(ToolText(Call('saveDocument', '{"filePath":"C:\\Q\\Kunde.pas"}')), '"saved":true');
  Assert.AreEqual('C:\Q\Kunde.pas', FIde.Saved);
end;

procedure TAtlasLinkProtocolTests.DiagnosticsGroupedByFile;
var
  mItem: TAtlasLinkDiagnostic;
  mText: string;
begin
  mItem := Default(TAtlasLinkDiagnostic);
  mItem.FileName := 'C:\Q\A.pas';
  mItem.Message := 'Undeklarierter Bezeichner';
  mItem.Severity := 'Error';
  mItem.Source := 'dcc';
  mItem.Code := 'E2003';
  mItem.Start := TAtlasLinkPosition.At(3, 0);
  mItem.Stop := TAtlasLinkPosition.At(3, 5);
  FIde.Items := [mItem];
  mItem.FileName := 'C:\Q\B.pas';
  mItem.Severity := 'Warning';
  FIde.Items := FIde.Items + [mItem];
  mItem.FileName := 'C:\Q\A.pas';
  mItem.Source := 'Atlas';
  FIde.Items := FIde.Items + [mItem];
  mText := ToolText(Call('getDiagnostics', '{}'));
  Assert.StartsWith('[{"uri":"file:///C:/Q/A.pas","diagnostics":[{', mText);
  Assert.Contains(mText, '"source":"Atlas"');
  Assert.Contains(mText, '{"uri":"file:///C:/Q/B.pas"');
  mText := ToolText(Call('getDiagnostics', '{"uri":"file:///C:/Q/B.pas"}'));
  Assert.DoesNotContain(mText, 'A.pas');
  Assert.Contains(mText, '"severity":"Warning"');
end;

procedure TAtlasLinkProtocolTests.OpenDiffAnswersAfterDecision;
var
  mCount: Integer;
begin
  Call('openDiff', '{"old_file_path":"C:\\Q\\A.pas","new_file_path":"C:\\Q\\A.pas","new_file_contents":"neu",' +
    '"tab_name":"Vorschlag A"}');
  mCount := Length(FPeer.Sent);
  Assert.AreEqual(0, mCount, 'keine Antwort vor der Entscheidung');
  Assert.AreEqual('Vorschlag A', FIde.LastDiff.TabName);
  Assert.AreEqual('neu', FIde.LastDiff.NewText);
  FIde.DiffDone(True, 'neu und bearbeitet');
  Assert.Contains(FPeer.Last, '"id":7');
  Assert.AreEqual(TAtlasLinkSession.cFileSaved, ToolText(FPeer.Last));
  Assert.AreEqual('neu und bearbeitet', ToolText(FPeer.Last, 1));
  Assert.AreEqual(TAtlasLinkSession.cTabClosed, ToolText(Call('close_tab', '{"tab_name":"Vorschlag A"}')));
  Assert.AreEqual('Vorschlag A', FIde.Closed);
  Assert.AreEqual('CLOSED_3_DIFF_TABS', ToolText(Call('closeAllDiffTabs', '{}')));
end;

procedure TAtlasLinkProtocolTests.OpenDiffRejected;
begin
  Call('openDiff', '{"old_file_path":"C:\\Q\\A.pas","new_file_path":"","new_file_contents":"neu",' +
    '"tab_name":"Vorschlag A"}');
  Assert.AreEqual('C:\Q\A.pas', FIde.LastDiff.NewFileName, 'ohne neuen Pfad gilt der alte');
  FIde.DiffDone(False, '');
  Assert.AreEqual(TAtlasLinkSession.cDiffRejected, ToolText(FPeer.Last));
  Assert.AreEqual('Vorschlag A', ToolText(FPeer.Last, 1));
end;

procedure TAtlasLinkProtocolTests.PauseRefusesChanges;
begin
  FIde.IsPaused := True;
  FIde.OpenFiles := ['C:\Q\A.pas'];
  Assert.Contains(Call('saveDocument', '{"filePath":"C:\\Q\\A.pas"}'), '"isError":true');
  Assert.AreEqual('', FIde.Saved);
  Assert.Contains(Call('openDiff', '{"old_file_path":"C:\\Q\\A.pas","new_file_contents":"x","tab_name":"t"}'),
    '"isError":true');
  Assert.IsFalse(Assigned(FIde.DiffDone), 'in der Pause kein Vergleich');
end;

procedure TAtlasLinkProtocolTests.ErrorsFollowJsonRpc;
begin
  FSession.Handle('kein json');
  Assert.Contains(FPeer.Last, '"id":null,"error":{"code":-32700');
  FSession.Handle('{"jsonrpc":"2.0","id":3,"method":"gibt/esnicht"}');
  Assert.Contains(FPeer.Last, '"code":-32601');
  FSession.Handle('{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{}}');
  Assert.Contains(FPeer.Last, '"code":-32602');
  FSession.Handle('{"jsonrpc":"2.0","id":5,"method":"ping"}');
  Assert.AreEqual('{"jsonrpc":"2.0","id":5,"result":{}}', FPeer.Last);
end;

procedure TAtlasLinkProtocolTests.UrisRoundTrip;
begin
  Assert.AreEqual('file:///C:/Pro%20jekt/%C3%84.pas', TAtlasLinkMessages.UriOf('C:\Pro jekt\Ä.pas'));
  Assert.AreEqual('C:\Pro jekt\Ä.pas', TAtlasLinkMessages.FileNameOf('file:///C:/Pro%20jekt/%C3%84.pas'));
  Assert.AreEqual('file:///home/a/b.pas', TAtlasLinkMessages.UriOf('/home/a/b.pas'));
  Assert.AreEqual('/home/a/b.pas', TAtlasLinkMessages.FileNameOf('file:///home/a/b.pas'));
  Assert.AreEqual('C:\x.pas', TAtlasLinkMessages.FileNameOf('C:\x.pas'), 'kein URI bleibt');
end;

procedure TAtlasLinkProtocolTests.NotificationsCarryFields;
var
  mSelection: TAtlasLinkSelection;
  mText: string;
begin
  mSelection := Default(TAtlasLinkSelection);
  mSelection.Known := True;
  mSelection.FileName := 'C:\Q\A.pas';
  mSelection.Start := TAtlasLinkPosition.At(1, 0);
  mSelection.Stop := TAtlasLinkPosition.At(1, 0);
  mText := TAtlasLinkMessages.SelectionChanged(mSelection);
  Assert.StartsWith('{"jsonrpc":"2.0","method":"selection_changed","params":{"text":""', mText);
  Assert.Contains(mText, '"fileUrl":"file:///C:/Q/A.pas"');
  Assert.Contains(mText, '"isEmpty":true');
  Assert.AreEqual('{"jsonrpc":"2.0","method":"at_mentioned","params":{"filePath":"C:\\Q\\A.pas","lineStart":4,' +
    '"lineEnd":9}}', TAtlasLinkMessages.AtMentioned('C:\Q\A.pas', 4, 9));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLinkProtocolTests);

end.
