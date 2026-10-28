unit Atlas.UI.Tracker.CommentEditor.Tests;

// Tests des Kommentar-Editors (#1278) mit einem Fenster, aber ohne IDE: ein
// Assist mit festen, sofortigen Antworten statt Tracker und Versionsverwaltung.
// Geprüft werden das einfache Feld (issues.commentEditor aus), Vorschläge
// annehmen, Tastenkürzel, Textbausteine, Entwurf anbieten, behalten und
// löschen sowie die Einbindung in Vorschau und Beenden-Dialog.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCommentEditorUiTests = class
  private
    FSaved: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Aus: keine Leiste, keine Vorschläge, kein Entwurf; Strg+Enter sendet trotzdem.</summary>
    [Test]
    procedure PlainFieldWhenSwitchedOff;
    /// <summary>"@an" zeigt Benutzer, Pfeil und Enter setzen "@andreas " ein.</summary>
    [Test]
    procedure AcceptMention;
    /// <summary>"ATL-" zeigt sofort die zuletzt geöffneten; Tab setzt die Kennung ein.</summary>
    [Test]
    procedure AcceptRecentIssue;
    /// <summary>Esc schließt erst die Liste, dann (mit gesichertem Entwurf) das Feld.</summary>
    [Test]
    procedure EscapeClosesListThenField;
    [Test]
    procedure ShortcutsBoldItalicCode;
    /// <summary>Textbaustein mit Platzhaltern an der Schreibmarke.</summary>
    [Test]
    procedure SnippetWithPlaceholders;
    /// <summary>Leeres Feld: Entwurf gleich darin mit „Verwerfen“; Verwerfen löscht ihn.</summary>
    [Test]
    procedure DraftRestoredAndDiscarded;
    /// <summary>Vorgefülltes Feld: Entwurf nur angeboten, „Übernehmen“ setzt ihn ein; die Vorgabe ist kein Entwurf.
    /// </summary>
    [Test]
    procedure DraftOfferedForPrefilledField;
    /// <summary>Unbind sichert den geänderten Text, Sent löscht den Entwurf und leert das Feld.</summary>
    [Test]
    procedure DraftKeptAndDeletedAfterSend;
    /// <summary>Vorschau setzt Markdown; leerer Text zeigt einen Hinweis.</summary>
    [Test]
    procedure PreviewToggles;
    /// <summary>Vorschau und Beenden-Dialog nutzen den Editor; CommentEdit bzw. CommentMemo ist sein Memo.</summary>
    [Test]
    procedure HostsUseEditor;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.Tracker.PaletteSearch,
  Atlas.Core.Tracker.CommentEditor,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.IssueFrame,
  Atlas.UI.Tracker.EndDialog,
  Atlas.UI.Tracker.CommentEditor;

type
  /// <summary>Assist mit festen Antworten, sofort im selben Aufruf.</summary>
  TFakeAssist = class(TInterfacedObject, IAtlasCommentAssist)
  public
    Draft: string;
    Saved: TArray<string>;
    Deleted: Integer;
    Cancelled: Integer;
    UserQueries: TArray<string>;
    function Target: TAtlasTrackerTarget;
    function Snippets: TArray<TAtlasCommentSnippet>;
    procedure FindUsers(const AText: string; const ADone: TAtlasCommentUsersDone);
    procedure FindIssues(const AQuery: TAtlasIssueSearchQuery; const ADone: TAtlasCommentIssuesDone);
    procedure Values(const ADone: TAtlasCommentValuesDone);
    procedure Cancel;
    function LoadDraft(out AText: string; out ASaved: TDateTime): Boolean;
    procedure SaveDraft(const AText: string);
    procedure DeleteDraft;
  end;

function TFakeAssist.Target: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('youtrack', 'https://yt.firma.de', 'ATL', '');
end;

function TFakeAssist.Snippets: TArray<TAtlasCommentSnippet>;
begin
  Result := TArray<TAtlasCommentSnippet>.Create(TAtlasCommentSnippet.Create('Build', 'Bitte prüfen.'),
    TAtlasCommentSnippet.Create('Behoben', 'Behoben in {commit} auf {branch} ({issue}).'));
end;

procedure TFakeAssist.FindUsers(const AText: string; const ADone: TAtlasCommentUsersDone);
begin
  UserQueries := UserQueries + [AText];
  ADone(TArray<TAtlasTrackerUser>.Create(TAtlasTrackerUser.Create('anna', 'Anna Berger'),
    TAtlasTrackerUser.Create('andreas', 'Andreas Koch')));
end;

procedure TFakeAssist.FindIssues(const AQuery: TAtlasIssueSearchQuery; const ADone: TAtlasCommentIssuesDone);
var
  mIssue: TAtlasTrackerIssue;
begin
  mIssue := TAtlasTrackerIssue.Empty;
  mIssue.Key := 'ATL-7';
  mIssue.Title := 'Zuletzt';
  ADone(TArray<TAtlasTrackerIssue>.Create(mIssue));
end;

procedure TFakeAssist.Values(const ADone: TAtlasCommentValuesDone);
begin
  ADone(TAtlasCommentValues.Create('ATL-12', 'feature/ATL-12', '4f2c9e1', '1.2.0.0'));
end;

procedure TFakeAssist.Cancel;
begin
  Inc(Cancelled);
end;

function TFakeAssist.LoadDraft(out AText: string; out ASaved: TDateTime): Boolean;
begin
  AText := Draft;
  // Mittag (UTC): in jeder Zeitzone derselbe Tag.
  ASaved := EncodeDate(2026, 10, 28) + 0.5;
  Result := Draft <> '';
end;

procedure TFakeAssist.SaveDraft(const AText: string);
begin
  Saved := Saved + [AText];
  Draft := AText;
end;

procedure TFakeAssist.DeleteDraft;
begin
  Inc(Deleted);
  Draft := '';
end;

type
  TSendCounter = class
  public
    Sends: Integer;
    Cancels: Integer;
    procedure Send(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  end;

procedure TSendCounter.Send(Sender: TObject);
begin
  Inc(Sends);
end;

procedure TSendCounter.CancelClick(Sender: TObject);
begin
  Inc(Cancels);
end;

procedure Press(AEditor: TAtlasCommentEditor; AKey: Word; AShift: TShiftState);
var
  mKey: Word;
begin
  mKey := AKey;
  AEditor.Memo.OnKeyDown(AEditor.Memo, mKey, AShift);
end;

function NewEditor(AHost: TForm): TAtlasCommentEditor;
begin
  Result := TAtlasCommentEditor.Create(AHost);
  Result.Parent := AHost;
  Result.Align := alClient;
  Result.RequestDelay := 0;
end;

procedure TypeText(AEditor: TAtlasCommentEditor; const AText: string);
begin
  AEditor.Memo.Text := AText;
  AEditor.Memo.SelStart := Length(AText);
  AEditor.CheckTrigger;
end;

{ TAtlasCommentEditorUiTests }

procedure TAtlasCommentEditorUiTests.Setup;
begin
  FSaved := Ord(TAtlasStrings.Language);
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasCommentEditorUiTests.TearDown;
begin
  TAtlasStrings.Language := TAtlasLanguage(FSaved);
end;

procedure TAtlasCommentEditorUiTests.PlainFieldWhenSwitchedOff;
var
  mHost: TForm;
  mEditor: TAtlasCommentEditor;
  mCounter: TSendCounter;
  mAssist: TFakeAssist;
  mRef: IAtlasCommentAssist;
begin
  mHost := TForm.CreateNew(nil);
  mCounter := TSendCounter.Create;
  mAssist := TFakeAssist.Create;
  mRef := mAssist;
  try
    mEditor := NewEditor(mHost);
    mEditor.OnSend := mCounter.Send;
    mAssist.Draft := 'alter Entwurf';
    mEditor.Enhanced := False;
    mEditor.Bind(mRef);
    Assert.AreEqual('', mEditor.Memo.Text, 'kein Entwurf ohne Editor');
    TypeText(mEditor, 'Danke @an');
    Assert.AreEqual(0, Integer(Length(mEditor.Rows)), 'keine Vorschläge');
    Assert.AreEqual(0, Integer(Length(mAssist.UserQueries)), 'keine Anfrage');
    Press(mEditor, VK_RETURN, [ssCtrl]);
    Assert.AreEqual(1, mCounter.Sends, 'Strg+Enter sendet');
    mEditor.Unbind;
    Assert.AreEqual(0, Integer(Length(mAssist.Saved)), 'nichts gespeichert');
  finally
    mHost.Free;
    mCounter.Free;
    mRef := nil;
  end;
end;

procedure TAtlasCommentEditorUiTests.AcceptMention;
var
  mHost: TForm;
  mEditor: TAtlasCommentEditor;
  mRef: IAtlasCommentAssist;
begin
  mHost := TForm.CreateNew(nil);
  mRef := TFakeAssist.Create;
  try
    mEditor := NewEditor(mHost);
    mEditor.Bind(mRef);
    TypeText(mEditor, 'Danke @an');
    Assert.IsTrue(mEditor.Trigger.Kind = TAtlasCommentTriggerKind.Mention);
    Assert.AreEqual(2, Integer(Length(mEditor.Rows)));
    Assert.AreEqual('@anna · Anna Berger', mEditor.Rows[0]);
    Assert.AreEqual(0, mEditor.Selected);
    Press(mEditor, VK_DOWN, []);
    Assert.AreEqual(1, mEditor.Selected);
    Press(mEditor, VK_DOWN, []);
    Assert.AreEqual(1, mEditor.Selected, 'bleibt am Ende');
    Press(mEditor, VK_RETURN, []);
    Assert.AreEqual('Danke @andreas ', mEditor.Memo.Text);
    Assert.AreEqual(15, mEditor.Memo.SelStart, 'Schreibmarke hinter dem Leerzeichen');
    Assert.AreEqual(0, Integer(Length(mEditor.Rows)), 'Liste zu');
  finally
    mHost.Free;
    mRef := nil;
  end;
end;

procedure TAtlasCommentEditorUiTests.AcceptRecentIssue;
var
  mHost: TForm;
  mEditor: TAtlasCommentEditor;
  mRef: IAtlasCommentAssist;
begin
  mHost := TForm.CreateNew(nil);
  mRef := TFakeAssist.Create;
  try
    mEditor := NewEditor(mHost);
    mEditor.RequestDelay := TAtlasCommentEditor.DelayMs;
    mEditor.Bind(mRef);
    TypeText(mEditor, 'siehe ATL-');
    Assert.IsTrue(mEditor.Trigger.Query.Kind = TAtlasIssueSearchKind.Recent);
    Assert.AreEqual(1, Integer(Length(mEditor.Rows)), 'ohne Wartezeit');
    Assert.AreEqual('ATL-7 · Zuletzt', mEditor.Rows[0]);
    Press(mEditor, VK_TAB, []);
    Assert.AreEqual('siehe ATL-7 ', mEditor.Memo.Text);
  finally
    mHost.Free;
    mRef := nil;
  end;
end;

procedure TAtlasCommentEditorUiTests.EscapeClosesListThenField;
var
  mHost: TForm;
  mEditor: TAtlasCommentEditor;
  mCounter: TSendCounter;
  mAssist: TFakeAssist;
  mRef: IAtlasCommentAssist;
begin
  mHost := TForm.CreateNew(nil);
  mCounter := TSendCounter.Create;
  mAssist := TFakeAssist.Create;
  mRef := mAssist;
  try
    mEditor := NewEditor(mHost);
    mEditor.OnCancel := mCounter.CancelClick;
    mEditor.Bind(mRef);
    TypeText(mEditor, 'Danke @an');
    Press(mEditor, VK_ESCAPE, []);
    Assert.AreEqual(0, Integer(Length(mEditor.Rows)), 'erst die Liste');
    Assert.AreEqual(0, mCounter.Cancels);
    Press(mEditor, VK_ESCAPE, []);
    Assert.AreEqual(1, mCounter.Cancels, 'dann das Feld');
    Assert.AreEqual('Danke @an', mAssist.Draft, 'Entwurf gesichert');
  finally
    mHost.Free;
    mCounter.Free;
    mRef := nil;
  end;
end;

procedure TAtlasCommentEditorUiTests.ShortcutsBoldItalicCode;
var
  mHost: TForm;
  mEditor: TAtlasCommentEditor;
begin
  mHost := TForm.CreateNew(nil);
  try
    mEditor := NewEditor(mHost);
    mEditor.Memo.Text := 'ab cd';
    mEditor.Memo.SelStart := 3;
    mEditor.Memo.SelLength := 2;
    Press(mEditor, Ord('B'), [ssCtrl]);
    Assert.AreEqual('ab **cd**', mEditor.Memo.Text);
    Assert.AreEqual('cd', mEditor.Memo.SelText, 'Auswahl bleibt');
    Press(mEditor, Ord('I'), [ssCtrl]);
    Assert.AreEqual('ab **_cd_**', mEditor.Memo.Text);
    mEditor.Memo.Text := 'x := 1;';
    mEditor.Memo.SelStart := 0;
    mEditor.Memo.SelLength := 7;
    Press(mEditor, Ord('K'), [ssCtrl, ssShift]);
    Assert.AreEqual('```pascal'#13#10'x := 1;'#13#10'```', mEditor.Memo.Text);
    Assert.AreEqual('x := 1;'#10'```', Copy(mEditor.Text, 11, MaxInt), 'Text mit #10');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasCommentEditorUiTests.SnippetWithPlaceholders;
var
  mHost: TForm;
  mEditor: TAtlasCommentEditor;
  mRef: IAtlasCommentAssist;
begin
  mHost := TForm.CreateNew(nil);
  mRef := TFakeAssist.Create;
  try
    mEditor := NewEditor(mHost);
    mEditor.Bind(mRef);
    mEditor.Memo.Text := 'Hallo. ';
    mEditor.Memo.SelStart := 7;
    mEditor.InsertSnippet(1);
    Assert.AreEqual('Hallo. Behoben in 4f2c9e1 auf feature/ATL-12 (ATL-12).', mEditor.Memo.Text);
    mEditor.InsertSnippet(9);
    Assert.AreEqual('Hallo. Behoben in 4f2c9e1 auf feature/ATL-12 (ATL-12).', mEditor.Memo.Text, 'unbekannt');
  finally
    mHost.Free;
    mRef := nil;
  end;
end;

procedure TAtlasCommentEditorUiTests.DraftRestoredAndDiscarded;
var
  mHost: TForm;
  mEditor: TAtlasCommentEditor;
  mAssist: TFakeAssist;
  mRef: IAtlasCommentAssist;
begin
  mHost := TForm.CreateNew(nil);
  mAssist := TFakeAssist.Create;
  mRef := mAssist;
  try
    mAssist.Draft := 'Zeile 1'#10'Zeile 2';
    mEditor := NewEditor(mHost);
    mEditor.Bind(mRef);
    Assert.AreEqual('Zeile 1'#13#10'Zeile 2', mEditor.Memo.Text, 'leeres Feld: gleich eingesetzt');
    Assert.IsTrue(mEditor.DraftButton.Visible);
    Assert.AreEqual('Verwerfen', mEditor.DraftButton.Caption);
    Assert.IsTrue(mEditor.DraftNote.Caption.StartsWith('Entwurf vom 28.10.'));
    mEditor.DraftButton.Click;
    Assert.AreEqual('', mEditor.Memo.Text);
    Assert.AreEqual(1, mAssist.Deleted);
    Assert.IsFalse(mEditor.DraftButton.Visible);
  finally
    mHost.Free;
    mRef := nil;
  end;
end;

procedure TAtlasCommentEditorUiTests.DraftOfferedForPrefilledField;
var
  mHost: TForm;
  mEditor: TAtlasCommentEditor;
  mAssist: TFakeAssist;
  mRef: IAtlasCommentAssist;
begin
  mHost := TForm.CreateNew(nil);
  mAssist := TFakeAssist.Create;
  mRef := mAssist;
  try
    mAssist.Draft := 'mein Entwurf';
    mEditor := NewEditor(mHost);
    mEditor.SetText('Erledigt in x.'#10'abc');
    mEditor.Bind(mRef);
    Assert.AreEqual('Erledigt in x.'#13#10'abc', mEditor.Memo.Text, 'Vorgabe bleibt');
    Assert.AreEqual('mein Entwurf', mEditor.OfferedDraft);
    Assert.AreEqual('Übernehmen', mEditor.DraftButton.Caption);
    mEditor.Unbind;
    Assert.AreEqual(0, Integer(Length(mAssist.Saved)), 'unveränderte Vorgabe ist kein Entwurf');
    mEditor.Bind(mRef);
    mEditor.DraftButton.Click;
    Assert.AreEqual('mein Entwurf', mEditor.Memo.Text);
    Assert.AreEqual('', mEditor.OfferedDraft);
  finally
    mHost.Free;
    mRef := nil;
  end;
end;

procedure TAtlasCommentEditorUiTests.DraftKeptAndDeletedAfterSend;
var
  mHost: TForm;
  mEditor: TAtlasCommentEditor;
  mAssist: TFakeAssist;
  mRef: IAtlasCommentAssist;
begin
  mHost := TForm.CreateNew(nil);
  mAssist := TFakeAssist.Create;
  mRef := mAssist;
  try
    mEditor := NewEditor(mHost);
    mEditor.Bind(mRef);
    mEditor.Memo.Text := 'halb fertig';
    mEditor.Unbind;
    Assert.AreEqual('halb fertig', mAssist.Draft, 'beim Lösen gesichert');
    Assert.IsTrue(mAssist.Cancelled > 0, 'offene Anfragen verworfen');
    mEditor.Memo.Text := '';
    mEditor.Bind(mRef);
    Assert.AreEqual('halb fertig', mEditor.Memo.Text);
    mEditor.Sent;
    Assert.AreEqual('', mEditor.Memo.Text);
    Assert.AreEqual('', mAssist.Draft, 'gesendet: Entwurf gelöscht');
    Assert.AreEqual(1, mAssist.Deleted);
  finally
    mHost.Free;
    mRef := nil;
  end;
end;

procedure TAtlasCommentEditorUiTests.PreviewToggles;
var
  mHost: TForm;
  mEditor: TAtlasCommentEditor;
begin
  mHost := TForm.CreateNew(nil);
  try
    mEditor := NewEditor(mHost);
    mEditor.Previewing := True;
    Assert.IsTrue(mEditor.PreviewBox.Visible);
    Assert.IsFalse(mEditor.Memo.Visible);
    Assert.AreEqual(1, mEditor.PreviewBox.ControlCount, 'Hinweis bei leerem Text');
    Assert.AreEqual('Bearbeiten', mEditor.PreviewButton.Caption);
    mEditor.Previewing := False;
    mEditor.Memo.Text := '**fett**'#13#10#13#10'```pascal'#13#10'x := 1;'#13#10'```';
    mEditor.Previewing := True;
    Assert.IsTrue(mEditor.PreviewBox.ControlCount >= 1, 'gesetzter Text');
    Assert.IsFalse(mEditor.SnippetButton.Enabled, 'kein Textbaustein in der Vorschau');
    mEditor.Previewing := False;
    Assert.AreEqual(0, mEditor.PreviewBox.ControlCount, 'aufgeräumt');
    Assert.IsTrue(mEditor.Memo.Visible);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasCommentEditorUiTests.HostsUseEditor;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
  mDialog: TAtlasTrackerEndDialog;
  mAssist: TFakeAssist;
  mRef: IAtlasCommentAssist;
begin
  mHost := TForm.CreateNew(nil);
  mAssist := TFakeAssist.Create;
  mRef := mAssist;
  try
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    Assert.IsTrue(mFrame.CommentEdit = mFrame.CommentEditor.Memo);
    mFrame.CommentEditor.Bind(mRef);
    mFrame.CommentEdit.Text := 'gesendet';
    mFrame.CommentDone('');
    Assert.AreEqual('', mFrame.CommentEdit.Text, 'Erfolg leert das Feld');
    Assert.AreEqual(1, mAssist.Deleted, 'und löscht den Entwurf');
    mFrame.CommentEdit.Text := 'bleibt';
    mFrame.CommentDone('Fehler');
    Assert.AreEqual('bleibt', mFrame.CommentEdit.Text, 'Fehler: Text bleibt');
  finally
    mHost.Free;
  end;
  Assert.AreEqual('bleibt', mAssist.Draft, 'beim Schließen der Vorschau gesichert');
  mDialog := TAtlasTrackerEndDialog.CreateDialog(nil, 'ATL-1',
    TAtlasTrackerSyncOptions.Create(True, 'Status', '', '', False, '', '', ''), 'Vorlage');
  try
    Assert.IsTrue(mDialog.CommentMemo = mDialog.CommentEditor.Memo);
    Assert.AreEqual('Vorlage', mDialog.CommentMemo.Text);
  finally
    mDialog.Free;
  end;
  mRef := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCommentEditorUiTests);

end.
