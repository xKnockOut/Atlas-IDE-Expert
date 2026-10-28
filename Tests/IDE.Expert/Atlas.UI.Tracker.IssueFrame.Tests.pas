unit Atlas.UI.Tracker.IssueFrame.Tests;

// Inhalt des Fensters „Atlas-Issue“ (#1264): leerer Zustand, Kopf mit
// Kennung, Titel und Abzeichen, Beschreibung als Doku mit Bild aus den
// Anhängen, eingeklappte ältere Kommentare, Listen der Anhänge und
// Verknüpfungen, Laden mit „Abbrechen“, Fehler mit Knopf zum Beheben,
// Verlauf und abgeschaltete Kommentare. Checklisten (#1273): Fortschritt in
// der Kopfzeile, Kästchen, „Punkt hinzufügen …“, nur lesbar, abgeschaltet.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasIssueFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure EmptyStateDisablesButtons;
    [Test]
    procedure ShowsHeaderBadgesAndLists;
    [Test]
    procedure OlderCommentsCollapsed;
    [Test]
    procedure LoadingErrorAndHistory;
    [Test]
    procedure CommentsSwitchedOff;
    [Test]
    procedure ChecklistProgressAndBoxes;
    [Test]
    procedure ChecklistReadOnlyAndSwitchedOff;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Forms,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.IssueFrame;

const
  cNow = 46323.5;

function Sample(ACommentCount: Integer): TAtlasTrackerDetails;
var
  mComment: TAtlasTrackerComment;
  mAttachment: TAtlasTrackerAttachment;
  mLink: TAtlasTrackerLink;
  mIndex: Integer;
begin
  Result := TAtlasTrackerDetails.Empty;
  Result.Key := 'ATL-123';
  Result.Number := 123;
  Result.Title := 'Tracker im Plugin anbinden';
  Result.State := 'In Progress';
  Result.Priority := 'Major';
  Result.Labels := TArray<string>.Create('plugin');
  Result.Created := cNow - 2;
  Result.Updated := cNow - 3.5 / 24;
  Result.Description := 'Text mit **fett**.' + #10#10 + '![Skizze](skizze.png)' + #10#10 + 'Danach.';
  Result.CommentsLoaded := True;
  for mIndex := 1 to ACommentCount do
  begin
    mComment := Default(TAtlasTrackerComment);
    mComment.Author := 'autor' + IntToStr(mIndex);
    mComment.Created := cNow - 1 + mIndex / 100;
    mComment.Text := 'Kommentar ' + IntToStr(mIndex);
    Result.Comments := Result.Comments + [mComment];
  end;
  mAttachment := Default(TAtlasTrackerAttachment);
  mAttachment.Name := 'skizze.png';
  mAttachment.Size := 2048;
  mAttachment.Url := 'https://beispiel.youtrack.cloud/api/files/1-2?sign=x';
  Result.Attachments := [mAttachment];
  mAttachment.Name := 'log.txt';
  mAttachment.Size := -1;
  mAttachment.Url := 'https://beispiel.youtrack.cloud/api/files/1-3';
  Result.Attachments := Result.Attachments + [mAttachment];
  mLink := Default(TAtlasTrackerLink);
  mLink.Key := 'ATL-100';
  mLink.Title := 'Einstellungen';
  mLink.Relation := 'depends on';
  mLink.Local := True;
  Result.Links := [mLink];
end;

{ TAtlasIssueFrameTests }

procedure TAtlasIssueFrameTests.WarmUpFirstUse;
begin
  Setup;
  try
    ShowsHeaderBadgesAndLists;
  finally
    TearDown;
  end;
end;

procedure TAtlasIssueFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasIssueFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasIssueFrameTests.EmptyStateDisablesButtons;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.ShowEmpty;
    Assert.IsFalse(mFrame.HasDetails);
    Assert.IsTrue(mFrame.EmptyLabel.Visible);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.IssuePreviewEmpty), mFrame.EmptyLabel.Caption);
    Assert.IsFalse(mFrame.StartButton.Enabled);
    Assert.IsFalse(mFrame.BrowseButton.Enabled);
    Assert.IsFalse(mFrame.CopyKeyButton.Enabled);
    Assert.IsFalse(mFrame.RefreshButton.Enabled);
    Assert.AreEqual('', mFrame.StatusText);
    Assert.AreEqual(0, mFrame.DocCount);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueFrameTests.ShowsHeaderBadgesAndLists;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
  mRequested: TArray<string>;
begin
  mRequested := nil;
  mHost := TForm.CreateNew(nil);
  try
    mHost.Width := 700;
    mHost.Height := 600;
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.OnImages :=
      procedure(AUrls: TArray<string>)
      begin
        mRequested := AUrls;
      end;
    mFrame.CanStart := True;
    mFrame.ShowDetails(Sample(1), cNow, '', False);
    Assert.IsTrue(mFrame.HasDetails);
    Assert.IsFalse(mFrame.EmptyLabel.Visible);
    Assert.AreEqual('ATL-123', mFrame.KeyLabel.Caption);
    Assert.AreEqual('Tracker im Plugin anbinden', mFrame.TitleLabel.Caption);
    Assert.IsTrue(mFrame.StartButton.Enabled);
    Assert.IsTrue(mFrame.BrowseButton.Enabled);
    // Zustand, Priorität, Label, erstellt, aktualisiert.
    Assert.AreEqual(5, Integer(Length(mFrame.Badges.Texts)));
    Assert.AreEqual('In Progress', mFrame.Badges.Texts[0]);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewBadgeUpdated,
      [TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewHours, [3])]), mFrame.Badges.Texts[4]);
    // Beschreibung in zwei Doku-Stücken um das Bild, dazu der Kommentar.
    Assert.AreEqual(3, mFrame.DocCount);
    Assert.AreEqual(1, Integer(Length(mFrame.ImageUrls)));
    Assert.AreEqual('https://beispiel.youtrack.cloud/api/files/1-2?sign=x', mFrame.ImageUrls[0], 'Bild aus dem Anhang');
    Assert.AreEqual(1, Integer(Length(mRequested)), 'Bild wird geladen');
    Assert.AreEqual(2, mFrame.Attachments.Items.Count);
    Assert.AreEqual('skizze.png', mFrame.Attachments.Items[0].Caption);
    Assert.AreEqual('2,0 KB', mFrame.Attachments.Items[0].SubItems[0].Replace('.', ','));
    Assert.AreEqual('–', mFrame.Attachments.Items[1].SubItems[0], 'Größe unbekannt');
    Assert.AreEqual(1, mFrame.Links.Items.Count);
    Assert.AreEqual('ATL-100', mFrame.Links.Items[0].Caption);
    Assert.AreEqual('depends on', mFrame.Links.Items[0].SubItems[1]);
    Assert.IsNull(mFrame.OlderLabel, 'ein Kommentar: nichts eingeklappt');
  finally
    mHost.Free;
    mRequested := nil;
  end;
end;

procedure TAtlasIssueFrameTests.OlderCommentsCollapsed;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.ShowDetails(Sample(TAtlasIssuePreview.ShownComments + 2), cNow, '', False);
    Assert.IsNotNull(mFrame.OlderLabel);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewOlderComments, [2]), mFrame.OlderLabel.Caption);
    Assert.IsFalse(mFrame.CommentsExpanded);
    // Beschreibung (zwei Stücke) und die neuesten Kommentare.
    Assert.AreEqual(2 + TAtlasIssuePreview.ShownComments, mFrame.DocCount);
    mFrame.ShowDetails(Sample(TAtlasIssuePreview.ShownComments + 1), cNow, '', False);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.IssuePreviewOlderComment), mFrame.OlderLabel.Caption);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueFrameTests.LoadingErrorAndHistory;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
  mFix: TAtlasIssueFix;
  mBack: Integer;
begin
  mFix := TAtlasIssueFix.None;
  mBack := 0;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.OnFix :=
      procedure(AFix: TAtlasIssueFix)
      begin
        mFix := AFix;
      end;
    mFrame.OnBack :=
      procedure
      begin
        Inc(mBack);
      end;
    mFrame.ShowEmpty;
    mFrame.SetLoading(True);
    Assert.IsTrue(mFrame.Loading);
    Assert.IsTrue(mFrame.Progress.Visible);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.IssuePreviewLoading), mFrame.StatusText);
    Assert.IsTrue(mFrame.RefreshButton.Enabled, 'Abbrechen');
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.IssuePreviewCancel), mFrame.RefreshButton.Caption);
    mFrame.SetLoading(False);
    mFrame.ShowError(TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorToken), TAtlasIssueFix.EnterToken);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorToken), mFrame.StatusText);
    Assert.IsTrue(mFrame.FixButton.Visible);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.IssuePreviewFixToken), mFrame.FixButton.Caption);
    mFrame.FixButton.Click;
    Assert.IsTrue(mFix = TAtlasIssueFix.EnterToken);
    // Alter Stand mit Hinweis statt Fehler.
    mFrame.ShowDetails(Sample(0), cNow, 'Stand vom 28.10.2026 10:00', False);
    Assert.AreEqual('Stand vom 28.10.2026 10:00', mFrame.StatusText);
    Assert.IsFalse(mFrame.FixButton.Visible);
    mFrame.SetHistory(True, False);
    Assert.IsTrue(mFrame.BackAction.Enabled);
    Assert.IsFalse(mFrame.ForwardAction.Enabled);
    mFrame.BackButton.Click;
    Assert.AreEqual(1, mBack);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueFrameTests.CommentsSwitchedOff;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.ShowDetails(Sample(5), cNow, '', True);
    Assert.IsNull(mFrame.OlderLabel);
    Assert.AreEqual(2, mFrame.DocCount, 'nur die Beschreibung');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueFrameTests.ChecklistProgressAndBoxes;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
  mDetails: TAtlasTrackerDetails;
begin
  mHost := TForm.CreateNew(nil);
  try
    mHost.Width := 700;
    mHost.Height := 600;
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    // Ohne Checkliste: Kopfzeile wie bisher, kein „Punkt hinzufügen …“.
    mFrame.ShowDetails(Sample(0), cNow, '', False);
    Assert.AreEqual('', mFrame.ProgressText);
    Assert.AreEqual('ATL-123', mFrame.KeyLabel.Caption);
    Assert.IsNull(mFrame.TaskBox);
    Assert.IsNull(mFrame.AddTaskLabel);
    mDetails := Sample(0);
    mDetails.Description := 'Vorher' + #10#10 + '- [x] a' + #10 + '- [ ] b' + #10 + '1. [x] c';
    mFrame.ShowDetails(mDetails, cNow, '', False);
    Assert.AreEqual('2/3', mFrame.ProgressText);
    Assert.AreEqual('ATL-123 · 2/3', mFrame.KeyLabel.Caption);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.IssueChecklistProgress, [2, 3]), mFrame.KeyLabel.Hint);
    Assert.IsNotNull(mFrame.TaskBox);
    Assert.IsTrue(mFrame.TaskBox.HasTasks);
    Assert.IsFalse(mFrame.TaskBox.TasksLocked);
    Assert.IsNotNull(mFrame.AddTaskLabel);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.IssueChecklistAdd), mFrame.AddTaskLabel.Caption);
    // Geschrieben: neuer Text ohne Neuladen.
    mFrame.ReplaceDescription('- [x] a' + #10 + '- [x] b' + #10 + '1. [x] c');
    Assert.AreEqual('3/3', mFrame.ProgressText);
    Assert.AreEqual('- [x] a' + #10 + '- [x] b' + #10 + '1. [x] c', mFrame.Details.Description);
    // Während des Schreibens die Meldung „Wird gespeichert …“.
    mFrame.SetChecklistBusy(True);
    Assert.IsTrue(mFrame.ChecklistBusy);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.IssueChecklistSaving), mFrame.StatusText);
    mFrame.SetChecklistBusy(False);
    Assert.IsFalse(mFrame.ChecklistBusy);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueFrameTests.ChecklistReadOnlyAndSwitchedOff;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
  mDetails: TAtlasTrackerDetails;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mDetails := Sample(0);
    mDetails.Description := '- [x] a' + #10 + '- [ ] b';
    mFrame.ChecklistReadOnly := True;
    mFrame.ShowDetails(mDetails, cNow, '', False);
    Assert.AreEqual('1/2', mFrame.ProgressText, 'Fortschritt auch ohne Schreibrecht');
    Assert.IsTrue(mFrame.TaskBox.TasksLocked);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.IssueChecklistReadOnly), mFrame.TaskBox.TaskHint);
    Assert.IsNull(mFrame.AddTaskLabel, 'ohne Schreibrecht nichts hinzufügen');
    // issues.preview.checklists aus: Listen wie geschrieben, kein Fortschritt.
    mFrame.ChecklistReadOnly := False;
    mFrame.Checklists := False;
    Assert.AreEqual('', mFrame.ProgressText);
    Assert.AreEqual('ATL-123', mFrame.KeyLabel.Caption);
    Assert.IsNull(mFrame.TaskBox);
    Assert.IsNull(mFrame.AddTaskLabel);
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssueFrameTests);

end.
