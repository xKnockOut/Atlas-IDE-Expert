unit Atlas.UI.Tracker.IssueFrame.Tests;

// Inhalt des Fensters „Atlas-Issue“ (#1264): leerer Zustand, Kopf mit
// Kennung, Titel und Abzeichen, Beschreibung als Doku mit Bild aus den
// Anhängen, eingeklappte ältere Kommentare, Listen der Anhänge und
// Verknüpfungen, Laden mit „Abbrechen“, Fehler mit Knopf zum Beheben,
// Verlauf und abgeschaltete Kommentare; Verknüpfungen als Baum mit Gruppen,
// Fortschritt, Zustand und Knöpfen zum Anlegen und Verknüpfen (#1279);
// Checklisten (#1273): Fortschritt in der Kopfzeile, Kästchen, „Punkt
// hinzufügen …“, nur lesbar, abgeschaltet; Reiter „Details“ und „Entwicklung“
// mit Schalter (#1269).

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
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
    /// <summary>#1271: Aus einer Meldung am ersten neuen Kommentar; liegt er bei den eingeklappten, klappen sie auf.
    /// </summary>
    [Test]
    procedure AnchorExpandsAndMarksComment;
    [Test]
    procedure LoadingErrorAndHistory;
    [Test]
    procedure CommentsSwitchedOff;
    [Test]
    procedure ChecklistProgressAndBoxes;
    [Test]
    procedure ChecklistReadOnlyAndSwitchedOff;
    [Test]
    procedure LinksAsTree;
    [Test]
    procedure LinkRowAndGroupTexts;
    /// <summary>Abnahme: Reiter „Entwicklung“ neben „Details“; aus = Reiter fehlt, keine Suche.</summary>
    [Test]
    procedure DevelopmentTabAndSwitch;
    /// <summary>#1276: „Anhängen …“ nur mit CanAttach, aktiv erst mit Issue, meldet OnAttach.</summary>
    [Test]
    procedure AttachButtonAndMenu;
    /// <summary>#2126: „Prüfen …“ nur mit CanReview und Issue, meldet OnReview.</summary>
    [Test]
    procedure ReviewButton;
  end;

implementation

uses
  Atlas.UI.Tracker.Issue.Strings,
  System.SysUtils,
  Vcl.Forms,
  Vcl.ComCtrls,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Links,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.IssueBoxes,
  Atlas.UI.Tracker.IssueFrame,
  Atlas.UI.Tracker.IssueFrame.Contract;

const
  cNow = 46323.5;

/// <summary>Adressen aller Bilder im Inhalt.</summary>
function ImageUrls(AFrame: TAtlasIssueFrame): TArray<string>;
var
  mImage: TAtlasIssueImageBox;
begin
  Result := nil;
  for mImage in AFrame.Content.Images do
  begin
    Result := Result + [mImage.Url];
  end;
end;

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
    Assert.IsFalse(mFrame.State.HasDetails);
    Assert.IsTrue(mFrame.Parts.Empty.Visible);
    Assert.AreEqual(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewEmpty), mFrame.Parts.Empty.Caption);
    Assert.IsFalse(mFrame.Parts.Start.Enabled);
    Assert.IsFalse(mFrame.Parts.Browse.Enabled);
    Assert.IsFalse(mFrame.Parts.CopyKey.Enabled);
    Assert.IsFalse(mFrame.Parts.Refresh.Enabled);
    Assert.AreEqual('', mFrame.StatusText);
    Assert.AreEqual(0, Integer(mFrame.Content.Docs.Count));
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueFrameTests.ShowsHeaderBadgesAndLists;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
  mEvents: TAtlasIssueFrameEvents;
  mRequested: TArray<string>;
begin
  mRequested := nil;
  mHost := TForm.CreateNew(nil);
  try
    mHost.Width := 700;
    mHost.Height := 600;
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mEvents := mFrame.Events;
    mEvents.Images :=
      procedure(AUrls: TArray<string>)
      begin
        mRequested := AUrls;
      end;
    mFrame.Events := mEvents;
    mFrame.SetFlag(TAtlasIssueFlag.CanStart, True);
    mFrame.ShowDetails(Sample(1), cNow, '', False);
    Assert.IsTrue(mFrame.State.HasDetails);
    Assert.IsFalse(mFrame.Parts.Empty.Visible);
    Assert.AreEqual('ATL-123', mFrame.Content.KeyLabel.Caption);
    Assert.AreEqual('Tracker im Plugin anbinden', mFrame.Content.TitleLabel.Caption);
    Assert.IsTrue(mFrame.Parts.Start.Enabled);
    Assert.IsTrue(mFrame.Parts.Browse.Enabled);
    // Zustand, Priorität, Label, erstellt, aktualisiert.
    Assert.AreEqual(5, Integer(Length(mFrame.Content.Badges.Texts)));
    Assert.AreEqual('In Progress', mFrame.Content.Badges.Texts[0]);
    Assert.AreEqual(TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewBadgeUpdated,
      [TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewHours, [3])]), mFrame.Content.Badges.Texts[4]);
    // Beschreibung in zwei Doku-Stücken um das Bild, dazu der Kommentar.
    Assert.AreEqual(3, Integer(mFrame.Content.Docs.Count));
    Assert.AreEqual(1, Integer(Length(ImageUrls(mFrame))));
    Assert.AreEqual('https://beispiel.youtrack.cloud/api/files/1-2?sign=x', ImageUrls(mFrame)[0], 'Bild aus dem Anhang');
    Assert.AreEqual(1, Integer(Length(mRequested)), 'Bild wird geladen');
    Assert.AreEqual(2, mFrame.Content.Attachments.Items.Count);
    Assert.AreEqual('skizze.png', mFrame.Content.Attachments.Items[0].Caption);
    Assert.AreEqual('2,0 KB', mFrame.Content.Attachments.Items[0].SubItems[0].Replace('.', ','));
    Assert.AreEqual('–', mFrame.Content.Attachments.Items[1].SubItems[0], 'Größe unbekannt');
    Assert.AreEqual(1, mFrame.Content.Links.Items.Count);
    Assert.AreEqual('ATL-100', mFrame.Content.Links.Items[0].Caption);
    Assert.AreEqual('depends on', mFrame.Content.Links.Items[0].SubItems[1]);
    Assert.IsNull(mFrame.Content.Older, 'ein Kommentar: nichts eingeklappt');
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
    mFrame.ShowDetails(Sample(TAtlasIssuePreview.cShownComments + 2), cNow, '', False);
    Assert.IsNotNull(mFrame.Content.Older);
    Assert.AreEqual(TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewOlderComments, [2]),
      mFrame.Content.Older.Caption);
    Assert.IsFalse(mFrame.State.CommentsExpanded);
    // Beschreibung (zwei Stücke) und die neuesten Kommentare.
    Assert.AreEqual(2 + TAtlasIssuePreview.cShownComments, Integer(mFrame.Content.Docs.Count));
    mFrame.ShowDetails(Sample(TAtlasIssuePreview.cShownComments + 1), cNow, '', False);
    Assert.AreEqual(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewOlderComment),
      mFrame.Content.Older.Caption);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueFrameTests.AnchorExpandsAndMarksComment;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
  mDetails: TAtlasTrackerDetails;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mDetails := Sample(TAtlasIssuePreview.cShownComments + 2);
    mFrame.ShowDetails(mDetails, cNow, '', False);
    Assert.AreEqual(Integer(-1), mFrame.Content.AnchorComment, 'ohne Anker');
    // Der zweite Kommentar ist eingeklappt: Der Anker klappt auf und hebt ihn hervor.
    mFrame.SetAnchor(mDetails.Comments[1].Created);
    mFrame.ShowDetails(mDetails, cNow, '', False);
    Assert.AreEqual(Integer(1), mFrame.Content.AnchorComment);
    Assert.IsTrue(mFrame.State.CommentsExpanded);
    Assert.IsNull(mFrame.Content.Older, 'alle Kommentare sichtbar');
    // Gefunden: Ein erneutes Laden springt nicht noch einmal.
    mFrame.ShowDetails(mDetails, cNow, '', False);
    Assert.AreEqual(Integer(-1), mFrame.Content.AnchorComment);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueFrameTests.LoadingErrorAndHistory;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
  mEvents: TAtlasIssueFrameEvents;
  mFix: TAtlasIssueFix;
  mBack: Integer;
begin
  mFix := TAtlasIssueFix.None;
  mBack := 0;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mEvents := mFrame.Events;
    mEvents.Fix :=
      procedure(AFix: TAtlasIssueFix)
      begin
        mFix := AFix;
      end;
    mEvents.Back :=
      procedure
      begin
        Inc(mBack);
      end;
    mFrame.Events := mEvents;
    mFrame.ShowEmpty;
    mFrame.SetFlag(TAtlasIssueFlag.Loading, True);
    Assert.IsTrue((TAtlasIssueFlag.Loading in mFrame.Flags));
    Assert.IsTrue(mFrame.Parts.Progress.Visible);
    Assert.AreEqual(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewLoading), mFrame.StatusText);
    Assert.IsTrue(mFrame.Parts.Refresh.Enabled, 'Abbrechen');
    Assert.AreEqual(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewCancel), mFrame.Parts.Refresh.Caption);
    mFrame.SetFlag(TAtlasIssueFlag.Loading, False);
    mFrame.ShowError(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorToken), TAtlasIssueFix.EnterToken);
    Assert.AreEqual(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorToken), mFrame.StatusText);
    Assert.IsTrue(mFrame.Parts.Fix.Visible);
    Assert.AreEqual(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewFixToken), mFrame.Parts.Fix.Caption);
    mFrame.Parts.Fix.Click;
    Assert.AreEqual<TAtlasIssueFix>(TAtlasIssueFix.EnterToken, mFix);
    // Alter Stand mit Hinweis statt Fehler.
    mFrame.ShowDetails(Sample(0), cNow, 'Stand vom 28.10.2026 10:00', False);
    Assert.AreEqual('Stand vom 28.10.2026 10:00', mFrame.StatusText);
    Assert.IsFalse(mFrame.Parts.Fix.Visible);
    mFrame.SetHistory(True, False);
    Assert.IsTrue(mFrame.Parts.BackAction.Enabled);
    Assert.IsFalse(mFrame.Parts.ForwardAction.Enabled);
    mFrame.Parts.Back.Click;
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
    Assert.IsNull(mFrame.Content.Older);
    Assert.AreEqual(2, Integer(mFrame.Content.Docs.Count), 'nur die Beschreibung');
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
    Assert.AreEqual('', mFrame.Content.ProgressText);
    Assert.AreEqual('ATL-123', mFrame.Content.KeyLabel.Caption);
    Assert.IsNull(mFrame.Content.TaskBox);
    Assert.IsNull(mFrame.Content.AddTask);
    mDetails := Sample(0);
    mDetails.Description := 'Vorher' + #10#10 + '- [x] a' + #10 + '- [ ] b' + #10 + '1. [x] c';
    mFrame.ShowDetails(mDetails, cNow, '', False);
    Assert.AreEqual('2/3', mFrame.Content.ProgressText);
    Assert.AreEqual('ATL-123 · 2/3', mFrame.Content.KeyLabel.Caption);
    Assert.AreEqual(TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssueChecklistProgress, [2, 3]),
      mFrame.Content.KeyLabel.Hint);
    Assert.IsNotNull(mFrame.Content.TaskBox);
    Assert.IsTrue(mFrame.Content.TaskBox.HasTasks);
    Assert.IsFalse(mFrame.Content.TaskBox.TasksLocked);
    Assert.IsNotNull(mFrame.Content.AddTask);
    Assert.AreEqual(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssueChecklistAdd), mFrame.Content.AddTask.Caption);
    // Geschrieben: neuer Text ohne Neuladen.
    mFrame.ReplaceDescription('- [x] a' + #10 + '- [x] b' + #10 + '1. [x] c');
    Assert.AreEqual('3/3', mFrame.Content.ProgressText);
    Assert.AreEqual('- [x] a' + #10 + '- [x] b' + #10 + '1. [x] c', mFrame.State.Details.Description);
    // Während des Schreibens die Meldung „Wird gespeichert …“.
    mFrame.SetFlag(TAtlasIssueFlag.ChecklistBusy, True);
    Assert.IsTrue((TAtlasIssueFlag.ChecklistBusy in mFrame.Flags));
    Assert.AreEqual(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssueChecklistSaving), mFrame.StatusText);
    mFrame.SetFlag(TAtlasIssueFlag.ChecklistBusy, False);
    Assert.IsFalse((TAtlasIssueFlag.ChecklistBusy in mFrame.Flags));
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
    mFrame.SetFlag(TAtlasIssueFlag.ChecklistReadOnly, True);
    mFrame.ShowDetails(mDetails, cNow, '', False);
    Assert.AreEqual('1/2', mFrame.Content.ProgressText, 'Fortschritt auch ohne Schreibrecht');
    Assert.IsTrue(mFrame.Content.TaskBox.TasksLocked);
    Assert.AreEqual(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssueChecklistReadOnly),
      mFrame.Content.TaskBox.TaskHint);
    Assert.IsNull(mFrame.Content.AddTask, 'ohne Schreibrecht nichts hinzufügen');
    // issues.preview.checklists aus: Listen wie geschrieben, kein Fortschritt.
    mFrame.SetFlag(TAtlasIssueFlag.ChecklistReadOnly, False);
    mFrame.SetFlag(TAtlasIssueFlag.Checklists, False);
    Assert.AreEqual('', mFrame.Content.ProgressText);
    Assert.AreEqual('ATL-123', mFrame.Content.KeyLabel.Caption);
    Assert.IsNull(mFrame.Content.TaskBox);
    Assert.IsNull(mFrame.Content.AddTask);
  finally
    mHost.Free;
  end;
end;

function TreeSample: TAtlasTrackerDetails;

  function Linked(const AKey, ATitle, AState: string; AKind: TAtlasTrackerLinkKind;
    AResolved: Boolean): TAtlasTrackerLink;
  begin
    Result := Default(TAtlasTrackerLink);
    Result.Key := AKey;
    Result.Title := ATitle;
    Result.Kind := AKind;
    Result.State := AState;
    Result.StateKnown := True;
    Result.Resolved := AResolved;
    Result.Local := True;
  end;

begin
  Result := Sample(0);
  Result.Links := TArray<TAtlasTrackerLink>.Create(
    Linked('ATL-90', 'Alte Vorschau', '', TAtlasTrackerLinkKind.Duplicates, False),
    Linked('ATL-131', 'Baum', 'Fixed', TAtlasTrackerLinkKind.Subtask, True),
    Linked('ATL-129', 'Tracker-Anbindung', 'In Progress', TAtlasTrackerLinkKind.DependsOn, False),
    Linked('ATL-132', 'Warnung', '', TAtlasTrackerLinkKind.Subtask, True),
    Linked('ATL-133', 'Anlegen', 'Open', TAtlasTrackerLinkKind.Subtask, False));
end;

/// <summary>Drei Gruppen des Baums zu TreeSample in fester Reihenfolge: Hängt ab von, Unteraufgaben, Duplikat von.
/// </summary>
procedure CheckLinkGroups(ATree: TTreeView);
var
  mNode: TTreeNode;
begin
  mNode := ATree.Items.GetFirstNode;
  Assert.AreEqual('Hängt ab von (1)', mNode.Text);
  Assert.IsTrue(mNode.Expanded);
  Assert.AreEqual(1, mNode.Count);
  Assert.AreEqual(TAtlasIssueLinkText.Row(TreeSample.Links[2]), mNode.Item[0].Text);
  mNode := mNode.getNextSibling;
  Assert.AreEqual('Unteraufgaben 2/3', mNode.Text);
  Assert.IsTrue(mNode.Expanded);
  Assert.AreEqual(3, mNode.Count);
  Assert.IsTrue(mNode.Item[0].Text.Contains('ATL-131'), 'Reihenfolge des Trackers');
  mNode := mNode.getNextSibling;
  Assert.AreEqual('Duplikat von (1)', mNode.Text);
  Assert.IsFalse(mNode.Expanded, 'eingeklappt');
  Assert.IsNull(mNode.getNextSibling);
end;

procedure TAtlasIssueFrameTests.LinksAsTree;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
  mEvents: TAtlasIssueFrameEvents;
  mSubtask, mLink: Integer;
begin
  mSubtask := 0;
  mLink := 0;
  mHost := TForm.CreateNew(nil);
  try
    mHost.Width := 700;
    mHost.Height := 600;
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mEvents := mFrame.Events;
    mEvents.CreateSubtask :=
      procedure
      begin
        Inc(mSubtask);
      end;
    mEvents.AddLink :=
      procedure
      begin
        Inc(mLink);
      end;
    mFrame.Events := mEvents;
    mFrame.SetFlag(TAtlasIssueFlag.LinksAsTree, True);
    mFrame.SetFlag(TAtlasIssueFlag.CanWriteLinks, True);
    mFrame.ShowDetails(TreeSample, cNow, '', False);
    Assert.IsNull(mFrame.Content.Links, 'Baum statt Liste');
    Assert.IsNotNull(mFrame.Content.LinkTree);
    CheckLinkGroups(mFrame.Content.LinkTree);
    // Knöpfe über dem Baum.
    mFrame.Content.CreateSubtask.Click;
    mFrame.Content.AddLink.Click;
    Assert.AreEqual(1, mSubtask);
    Assert.AreEqual(1, mLink);
    // Ohne Schreibrecht keine Knöpfe; ohne Baum die Liste wie bisher.
    mFrame.SetFlag(TAtlasIssueFlag.CanWriteLinks, False);
    mFrame.ShowDetails(TreeSample, cNow, '', False);
    Assert.IsNull(mFrame.Content.CreateSubtask);
    Assert.IsNull(mFrame.Content.AddLink);
    mFrame.SetFlag(TAtlasIssueFlag.LinksAsTree, False);
    mFrame.ShowDetails(TreeSample, cNow, '', False);
    Assert.IsNull(mFrame.Content.LinkTree);
    Assert.AreEqual(5, mFrame.Content.Links.Items.Count);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueFrameTests.LinkRowAndGroupTexts;
var
  mLink: TAtlasTrackerLink;
  mGroup: TAtlasTrackerLinkGroup;
begin
  mLink := TreeSample.Links[2];
  Assert.AreEqual('⛔  ATL-129  Tracker-Anbindung  — In Progress · blockiert dieses Issue',
    TAtlasIssueLinkText.Row(mLink));
  mLink.Resolved := True;
  mLink.State := '';
  Assert.AreEqual('✓  ATL-129  Tracker-Anbindung  — erledigt', TAtlasIssueLinkText.Row(mLink));
  mLink.Kind := TAtlasTrackerLinkKind.Subtask;
  mLink.Resolved := False;
  mLink.Title := '';
  Assert.AreEqual('○  ATL-129  — offen', TAtlasIssueLinkText.Row(mLink));
  mLink.StateKnown := False;
  Assert.AreEqual('?  ATL-129  — Zustand unbekannt', TAtlasIssueLinkText.Row(mLink));
  mGroup := Default(TAtlasTrackerLinkGroup);
  mGroup.Kind := TAtlasTrackerLinkKind.Mentioned;
  mGroup.Total := 4;
  Assert.AreEqual('Erwähnt in (4)', TAtlasIssueLinkText.Group(mGroup));
  mGroup.Kind := TAtlasTrackerLinkKind.Subtask;
  mGroup.Done := 0;
  Assert.AreEqual('Unteraufgaben 0/4', TAtlasIssueLinkText.Group(mGroup));
end;

procedure TAtlasIssueFrameTests.DevelopmentTabAndSwitch;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
  mEvents: TAtlasIssueFrameEvents;
  mShown: Integer;
begin
  mShown := 0;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mEvents := mFrame.Events;
    mEvents.DevelopmentShown :=
      procedure
      begin
        Inc(mShown);
      end;
    mFrame.Events := mEvents;
    mFrame.ShowDetails(Sample(1), cNow, '', False);
    Assert.AreEqual(2, mFrame.Parts.Pages.PageCount);
    Assert.AreEqual(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewTabDetails),
      mFrame.Parts.Pages.Pages[0].Caption);
    Assert.AreEqual(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewTabDevelopment),
      mFrame.Parts.Pages.Pages[1].Caption);
    Assert.IsTrue((TAtlasIssueFlag.Development in mFrame.Flags), 'Vorgabe an');
    Assert.IsFalse(mFrame.DevelopmentActive, 'Details zuerst');
    Assert.AreEqual(0, mShown, 'gesucht wird erst beim Zeigen');
    mFrame.SelectTab(True);
    Assert.IsTrue(mFrame.DevelopmentActive);
    Assert.AreEqual(1, mShown);
    mFrame.SelectTab(True);
    Assert.AreEqual(1, mShown, 'schon sichtbar');
    // Aus: zurück auf Details, der Reiter fehlt und lässt sich nicht wählen.
    mFrame.SetFlag(TAtlasIssueFlag.Development, False);
    Assert.IsFalse((TAtlasIssueFlag.Development in mFrame.Flags));
    Assert.IsFalse(mFrame.DevelopmentActive);
    Assert.IsFalse(mFrame.Parts.Pages.Pages[1].TabVisible);
    mFrame.SelectTab(True);
    Assert.IsFalse(mFrame.DevelopmentActive);
    Assert.AreEqual(1, mShown);
    mFrame.SetFlag(TAtlasIssueFlag.Development, True);
    Assert.IsTrue(mFrame.Parts.Pages.Pages[0].TabVisible);
    Assert.IsTrue(mFrame.Parts.Pages.Pages[1].TabVisible);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueFrameTests.AttachButtonAndMenu;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
  mEvents: TAtlasIssueFrameEvents;
  mCalls: Integer;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mCalls := 0;
    mEvents := mFrame.Events;
    mEvents.Attach :=
      procedure
      begin
        Inc(mCalls);
      end;
    mFrame.Events := mEvents;
    mFrame.ShowEmpty;
    Assert.IsFalse(mFrame.Parts.Attach.Visible, 'issues.attach aus');
    Assert.IsFalse(mFrame.Parts.AttachItem.Visible);
    mFrame.SetFlag(TAtlasIssueFlag.CanAttach, True);
    Assert.IsTrue(mFrame.Parts.Attach.Visible);
    Assert.IsFalse(mFrame.Parts.Attach.Enabled, 'ohne Issue');
    mFrame.ShowDetails(Sample(1), cNow, '', False);
    Assert.IsTrue(mFrame.Parts.Attach.Enabled);
    Assert.IsTrue(mFrame.Parts.AttachItem.Visible);
    Assert.AreEqual(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewAttachMenu), mFrame.Parts.AttachItem.Caption);
    mFrame.Parts.Attach.Click;
    mFrame.Parts.AttachItem.Click;
    Assert.AreEqual(2, mCalls);
    mFrame.SetFlag(TAtlasIssueFlag.CanAttach, False);
    Assert.IsFalse(mFrame.Parts.Attach.Visible);
    mFrame.Events := Default(TAtlasIssueFrameEvents);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueFrameTests.ReviewButton;
var
  mHost: TForm;
  mFrame: TAtlasIssueFrame;
  mEvents: TAtlasIssueFrameEvents;
  mCalls: Integer;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasIssueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mCalls := 0;
    mEvents := mFrame.Events;
    mEvents.Review :=
      procedure
      begin
        Inc(mCalls);
      end;
    mFrame.Events := mEvents;
    mFrame.ShowEmpty;
    mFrame.SetFlag(TAtlasIssueFlag.CanReview, True);
    Assert.IsFalse(mFrame.Parts.Review.Visible, 'ohne Issue');
    mFrame.ShowDetails(Sample(1), cNow, '', False);
    Assert.IsTrue(mFrame.Parts.Review.Visible);
    Assert.AreEqual(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewReview), mFrame.Parts.Review.Caption);
    mFrame.Parts.Review.Click;
    Assert.AreEqual(1, mCalls);
    mFrame.SetFlag(TAtlasIssueFlag.CanReview, False);
    Assert.IsFalse(mFrame.Parts.Review.Visible, 'kein Prüfzustand');
    mFrame.Events := Default(TAtlasIssueFrameEvents);
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssueFrameTests);

end.
