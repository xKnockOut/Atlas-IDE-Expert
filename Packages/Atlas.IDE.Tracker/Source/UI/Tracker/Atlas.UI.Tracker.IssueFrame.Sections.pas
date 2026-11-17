unit Atlas.UI.Tracker.IssueFrame.Sections;

// Abschnitte des gezeigten Issues im Fenster „Atlas-Issue“ (#1264), abgelegt über TAtlasIssueLayout:
//   Kopf als Karte: Kennung (mit Fortschritt der Checkliste, #1273), Titel, Abzeichen;
//   Beschreibung als Markdown (Bilder als Vorschau, Kästchen der Checkliste anklickbar, „Punkt hinzufügen …“);
//   Kommentare als Karten, ältere eingeklappt, der Anker einer Meldung (#1271) hervorgehoben;
//   Anhänge als Liste; Verknüpfungen als Liste oder als Baum mit Knöpfen zum Anlegen und Verknüpfen (#1279).
// Die Steuerelemente stehen danach in Content. Was ein Klick bewirkt, entscheidet der Frame; hier nur, welcher
// Anhang oder welche Verknüpfung gewählt ist, und Bildlauf zu Anker und Checkliste.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Markdown,
  Atlas.Core.Tracker.Checklist,
  Atlas.UI.Tracker.DocBox,
  Atlas.UI.Tracker.IssueFrame.Contract,
  Atlas.UI.Tracker.IssueFrame.Layout;

type
  /// <summary>Baut den Inhalt eines Issues in den Bildlauf; Links aus Beschreibung und Kommentaren gehen an
  /// AOnLink. Gehört AOwner; der Inhalt entsteht später und wird deshalb vor ihr freigegeben.</summary>
  TAtlasIssueSections = class(TComponent)
  private
    FLayout: TAtlasIssueLayout;
    FOnLink: TProc<string>;
    FContent: TAtlasIssueFrameContent;
    /// <summary>Zustand und Schalter des laufenden bzw. letzten Build.</summary>
    FState: TAtlasIssueFrameState;
    FFlags: TAtlasIssueFlags;
    function AddDocBox(const ASegment: TAtlasMarkdownSegment): TAtlasIssueDocBox;
    procedure PrepareTasks(ADoc: TAtlasIssueDocBox);
    procedure AddImage(const ASegment: TAtlasMarkdownSegment);
    procedure AddMarkdown(const AText: string; ATasks: TAtlasMarkdownTasks);
    procedure AddBadges;
    procedure AddHeader(const AProgress: TAtlasChecklistProgress);
    procedure AddDescription(const AProgress: TAtlasChecklistProgress);
    procedure AddOlder(ACollapsed: Integer);
    procedure AddCommentHead(const AComment: TAtlasTrackerComment; AIndex, AAnchor: Integer);
    procedure AddComments;
    procedure AddAttachments;
    procedure AddLinkList;
    procedure AddLinkTools;
    procedure AddLinkTree;
    /// <summary>Ganze Höhe des Baums statt eigener Bildlaufleiste: die Vorschau rollt als Ganzes.</summary>
    procedure FitLinkTree;
    procedure LinkTreeExpanded(Sender: TObject; Node: TTreeNode);
    /// <summary>Enter in Anhängen und Verknüpfungsbaum: wie Klick.</summary>
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ClearContent;
    function SelectedListLink(out ALink: TAtlasTrackerLink): Boolean;
    function SelectedTreeLink(out ALink: TAtlasTrackerLink): Boolean;
  public
    /// <summary>Teile gehören AOwner und liegen in ABox; Klicks gehen an AOnClick.</summary>
    constructor Create(AOwner: TComponent; ABox: TScrollBox; AOnClick: TNotifyEvent;
      const AOnLink: TProc<string>); reintroduce;
    destructor Destroy; override;
    /// <summary>Bisherigen Inhalt freigeben und zu AState neu bauen (ohne Details leer). Liegt der Anker bei den
    /// eingeklappten Kommentaren, klappen sie auf (AState.CommentsExpanded).</summary>
    procedure Build(var AState: TAtlasIssueFrameState; AFlags: TAtlasIssueFlags);
    /// <summary>Adressen der Bilder, die geladen werden sollen.</summary>
    function ImageUrls: TArray<string>;
    /// <summary>Bild zu AUrl ist geladen (übernimmt AGraphic); nil = bleibt als Link.</summary>
    procedure SetImage(const AUrl: string; AGraphic: TGraphic);
    /// <summary>Gewählte Verknüpfung in der Liste (APart = Link) bzw. im Baum (LinkTree; Gruppen zählen nicht).
    /// </summary>
    function SelectedLink(APart: TAtlasIssuePart; out ALink: TAtlasTrackerLink): Boolean;
    function SelectedAttachment(out AAttachment: TAtlasTrackerAttachment): Boolean;
    /// <summary>Kopf des hervorgehobenen Kommentars oben ins Bild; True, wenn er der gesuchte ist (nicht nur der
    /// letzte als Ersatz): Dann hat der Anker seinen Zweck erfüllt.</summary>
    function RevealAnchor: Boolean;
    /// <summary>Zur Checkliste blättern; False ohne Checkliste.</summary>
    function ScrollToTasks: Boolean;
    property Content: TAtlasIssueFrameContent read FContent;
    property Layout: TAtlasIssueLayout read FLayout;
  end;

implementation

uses
  System.Generics.Collections,
  System.Math,
  System.UITypes,
  Winapi.Windows,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.IssueBoxes,
  Atlas.UI.Tracker.Issue.Strings;

const
  /// <summary>Deckkraft der Schrift über der Fläche für den Kopf und die Kommentarkarten.</summary>
  cHeadFill = 0.07;
  cCardFill = 0.04;
  /// <summary>Titel im Kopf: Schrifthöhe in Zehnteln der Fensterschrift.</summary>
  cTitleScale = 13;
  cTitleScaleBase = 10;
  /// <summary>Leiste über dem Baum und Mindestbreiten ihrer Knöpfe bei 96 dpi.</summary>
  cLinkToolsHeight = 30;
  cSubtaskWidth = 120;
  cLinkWidth = 100;
  /// <summary>Zeilen über die Einträge hinaus: Spaltenköpfe und Rand.</summary>
  cListExtraRows = 2;
  cKiloByte = 1024;

function BadgeHint(AKind: TAtlasIssueBadgeKind): string;
begin
  case AKind of
    TAtlasIssueBadgeKind.State:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewFieldState);
    TAtlasIssueBadgeKind.Priority:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewFieldPriority);
    TAtlasIssueBadgeKind.Kind:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewFieldKind);
    TAtlasIssueBadgeKind.Assignee:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewFieldAssignee);
    TAtlasIssueBadgeKind.Sprint:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewFieldSprint);
    TAtlasIssueBadgeKind.LabelName:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewFieldLabel);
  else
    Result := '';
  end;
end;

/// <summary>Text und Tooltip eines Abzeichens; Zeiten relativ zu ANow, Tooltip absolut.</summary>
procedure BadgeText(const ABadge: TAtlasIssueBadge; ANow: TDateTime; out AText, AHint: string);
begin
  AText := ABadge.Text;
  AHint := BadgeHint(ABadge.Kind) + ': ' + ABadge.Text;
  if ABadge.Kind = TAtlasIssueBadgeKind.Created then
  begin
    AText := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewBadgeCreated,
      [TAtlasIssueTimeText.Age(ABadge.Time, ANow)]);
    AHint := TAtlasIssueTimeText.Absolute(ABadge.Time);
  end
  else if ABadge.Kind = TAtlasIssueBadgeKind.Updated then
  begin
    AText := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewBadgeUpdated,
      [TAtlasIssueTimeText.Age(ABadge.Time, ANow)]);
    AHint := TAtlasIssueTimeText.Absolute(ABadge.Time);
  end;
end;

function SizeText(ASize: Int64): string;
begin
  Result := '–';
  if ASize >= 0 then
  begin
    Result := FormatFloat('#,##0.0', ASize / cKiloByte, FormatSettings) + ' KB';
  end;
end;

function RelationText(const ALink: TAtlasTrackerLink): string;
const
  // Beziehungen, die GitHub als Wort liefert.
  cMentioned = 'cross-referenced';
  cPull = 'pull request';
begin
  Result := ALink.Relation;
  if ALink.Relation = cMentioned then
  begin
    Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewRelationMentioned);
  end
  else if ALink.Relation = cPull then
  begin
    Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewRelationPull);
  end;
end;

{ TAtlasIssueSections }

constructor TAtlasIssueSections.Create(AOwner: TComponent; ABox: TScrollBox; AOnClick: TNotifyEvent;
  const AOnLink: TProc<string>);
begin
  inherited Create(AOwner);
  FLayout := TAtlasIssueLayout.Create(AOwner, ABox, AOnClick);
  FOnLink := AOnLink;
  FContent.Images := TList<TAtlasIssueImageBox>.Create;
  FContent.Docs := TList<TAtlasIssueDocBox>.Create;
  FContent.AnchorComment := -1;
  FState.Details := TAtlasTrackerDetails.Empty;
end;

destructor TAtlasIssueSections.Destroy;
begin
  FContent.Images.Free;
  FContent.Docs.Free;
  FLayout.Free;
  FOnLink := nil;
  inherited;
end;

procedure TAtlasIssueSections.ClearContent;
var
  mImages: TList<TAtlasIssueImageBox>;
  mDocs: TList<TAtlasIssueDocBox>;
begin
  FLayout.Clear;
  mImages := FContent.Images;
  mDocs := FContent.Docs;
  mImages.Clear;
  mDocs.Clear;
  FContent := Default(TAtlasIssueFrameContent);
  FContent.Images := mImages;
  FContent.Docs := mDocs;
  FContent.AnchorComment := -1;
end;

/// <summary>Doku-Fläche; Klick auf einen Link geht an FOnLink.</summary>
function TAtlasIssueSections.AddDocBox(const ASegment: TAtlasMarkdownSegment): TAtlasIssueDocBox;
begin
  Result := TAtlasIssueDocBox.Create(FLayout.Owner);
  FLayout.Place(Result);
  Result.SetDoc(ASegment.Doc, FLayout.ContentColors, FLayout.Mono);
  Result.OnLink := FOnLink;
  FContent.Docs.Add(Result);
end;

/// <summary>Kästchen der Beschreibung: lesend mit Tooltip oder anklickbar; die erste Fläche merken.</summary>
procedure TAtlasIssueSections.PrepareTasks(ADoc: TAtlasIssueDocBox);
var
  mReadOnly: Boolean;
begin
  mReadOnly := TAtlasIssueFlag.ChecklistReadOnly in FFlags;
  ADoc.TasksLocked := mReadOnly;
  if mReadOnly then
  begin
    ADoc.TaskHint := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssueChecklistReadOnly);
  end
  else
  begin
    ADoc.TaskHint := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssueChecklistToggleHint);
  end;
  if (FContent.TaskBox = nil) and ADoc.HasTasks then
  begin
    FContent.TaskBox := ADoc;
  end;
end;

/// <summary>Bild als Vorschau; relative Namen (YouTrack) sind Anhänge.</summary>
procedure TAtlasIssueSections.AddImage(const ASegment: TAtlasMarkdownSegment);
var
  mImage: TAtlasIssueImageBox;
begin
  mImage := TAtlasIssueImageBox.Create(FLayout.Owner);
  FLayout.Place(mImage);
  mImage.Url := TAtlasIssuePreview.ImageUrl(FState.Details, ASegment.Image.Url);
  mImage.Alt := ASegment.Image.Text;
  if mImage.Alt = '' then
  begin
    mImage.Alt := ASegment.Image.Url;
  end;
  mImage.Colors := FLayout.ContentColors;
  mImage.Tag := cAtlasIssuePartTag + Ord(TAtlasIssuePart.Image);
  mImage.OnEnlarge := FLayout.OnClick;
  FContent.Images.Add(mImage);
end;

procedure TAtlasIssueSections.AddMarkdown(const AText: string; ATasks: TAtlasMarkdownTasks);
var
  mSegment: TAtlasMarkdownSegment;
  mDoc: TAtlasIssueDocBox;
begin
  for mSegment in TAtlasTrackerMarkdown.Segments(AText, ATasks) do
  begin
    if mSegment.Kind <> TAtlasMarkdownSegmentKind.Doc then
    begin
      AddImage(mSegment);
    end
    else
    begin
      mDoc := AddDocBox(mSegment);
      if ATasks = TAtlasMarkdownTasks.Clickable then
      begin
        PrepareTasks(mDoc);
      end;
    end;
  end;
end;

procedure TAtlasIssueSections.AddBadges;
var
  mBadge: TAtlasIssueBadge;
  mTexts, mHints: TArray<string>;
  mText, mHint: string;
begin
  mTexts := nil;
  mHints := nil;
  for mBadge in TAtlasIssuePreview.Badges(FState.Details) do
  begin
    BadgeText(mBadge, FState.Now, mText, mHint);
    mTexts := mTexts + [mText];
    mHints := mHints + [mHint];
  end;
  FContent.Badges := TAtlasIssueBadgeBar.Create(FLayout.Owner);
  FLayout.Place(FContent.Badges);
  FContent.Badges.SetBadges(mTexts, mHints, FLayout.ContentColors);
end;

/// <summary>Kennung (mit Fortschritt der Checkliste, #1273), Titel und Abzeichen.</summary>
procedure TAtlasIssueSections.AddHeader(const AProgress: TAtlasChecklistProgress);
var
  mKey: TLabel;
begin
  FContent.Head := FLayout.BeginCard(cHeadFill);
  FContent.ProgressText := AProgress.Text;
  if FContent.ProgressText <> '' then
  begin
    mKey := FLayout.AddText(TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssueChecklistStatusLine, [FState.Details.Key,
      FContent.ProgressText]), False);
    mKey.Hint := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssueChecklistProgress, [AProgress.Done, AProgress.Total]);
    mKey.ShowHint := True;
  end
  else
  begin
    mKey := FLayout.AddText(FState.Details.Key, False);
  end;
  mKey.Font.Name := FLayout.Mono.Name;
  mKey.Font.Color := TColor(FLayout.Colors.Muted);
  FContent.KeyLabel := mKey;
  FContent.TitleLabel := FLayout.AddLinkText(FState.Details.Title, TAtlasIssuePart.Title);
  FContent.TitleLabel.Font.Style := [fsBold];
  FContent.TitleLabel.Font.Color := TColor(FLayout.Colors.Text);
  FContent.TitleLabel.Font.Height := MulDiv(FLayout.Box.Font.Height, cTitleScale, cTitleScaleBase);
  AddBadges;
  FLayout.EndCard;
end;

/// <summary>Beschreibung; mit issues.preview.checklists aus die Aufgabenlisten als Text wie geschrieben.</summary>
procedure TAtlasIssueSections.AddDescription(const AProgress: TAtlasChecklistProgress);
var
  mTasks: TAtlasMarkdownTasks;
begin
  mTasks := TAtlasMarkdownTasks.Plain;
  if TAtlasIssueFlag.Checklists in FFlags then
  begin
    mTasks := TAtlasMarkdownTasks.Clickable;
  end;
  FLayout.AddSection(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewDescription));
  if Trim(FState.Details.Description) = '' then
  begin
    FLayout.AddMuted(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewNoDescription), False);
  end
  else
  begin
    AddMarkdown(FState.Details.Description, mTasks);
  end;
  if AProgress.Any and not (TAtlasIssueFlag.ChecklistReadOnly in FFlags) then
  begin
    FContent.AddTask := FLayout.AddLinkText(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssueChecklistAdd),
      TAtlasIssuePart.AddTask);
  end;
end;

/// <summary>„n ältere Kommentare“, wenn welche eingeklappt sind.</summary>
procedure TAtlasIssueSections.AddOlder(ACollapsed: Integer);
var
  mText: string;
begin
  if ACollapsed <= 0 then
  begin
    Exit;
  end;
  if ACollapsed = 1 then
  begin
    mText := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewOlderComment);
  end
  else
  begin
    mText := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewOlderComments, [ACollapsed]);
  end;
  FContent.Older := FLayout.AddLinkText(mText, TAtlasIssuePart.Older);
end;

/// <summary>Kopf eines Kommentars; der Anker (#1271) in Akzentfarbe.</summary>
procedure TAtlasIssueSections.AddCommentHead(const AComment: TAtlasTrackerComment; AIndex, AAnchor: Integer);
var
  mHead: TLabel;
begin
  mHead := FLayout.AddText(AComment.Author + ' · ' + TAtlasIssueTimeText.Age(AComment.Created, FState.Now), True);
  mHead.Font.Color := TColor(FLayout.Colors.Muted);
  mHead.Hint := TAtlasIssueTimeText.Absolute(AComment.Created);
  mHead.ShowHint := True;
  if AIndex = AAnchor then
  begin
    mHead.Font.Color := TColor(FLayout.Colors.Accent);
    FContent.AnchorLabel := mHead;
    FContent.AnchorComment := AIndex;
  end;
end;

/// <summary>Kommentare: neueste unten, ältere eingeklappt; Checklisten darin nur als Kästchen.</summary>
procedure TAtlasIssueSections.AddComments;
var
  mComments: TArray<TAtlasTrackerComment>;
  mIndex, mCollapsed, mAnchor: Integer;
  mTasks: TAtlasMarkdownTasks;
begin
  mTasks := TAtlasMarkdownTasks.Plain;
  if TAtlasIssueFlag.Checklists in FFlags then
  begin
    mTasks := TAtlasMarkdownTasks.Boxes;
  end;
  mComments := FState.Details.Comments;
  if FState.CommentsOff then
  begin
    FLayout.AddMuted(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewCommentsOff), False);
    Exit;
  end;
  if Length(mComments) = 0 then
  begin
    Exit;
  end;
  FLayout.AddSection(TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewComments, [Length(mComments)]));
  mAnchor := TAtlasIssuePreview.CommentAt(mComments, FState.Anchor);
  // Der neue Kommentar einer Meldung liegt bei den eingeklappten: aufklappen.
  if (mAnchor >= 0) and
    (mAnchor < TAtlasIssuePreview.CollapsedComments(Length(mComments), FState.CommentsExpanded)) then
  begin
    FState.CommentsExpanded := True;
  end;
  mCollapsed := TAtlasIssuePreview.CollapsedComments(Length(mComments), FState.CommentsExpanded);
  AddOlder(mCollapsed);
  for mIndex := mCollapsed to High(mComments) do
  begin
    FLayout.BeginCard(cCardFill);
    AddCommentHead(mComments[mIndex], mIndex, mAnchor);
    AddMarkdown(mComments[mIndex].Text, mTasks);
    FLayout.EndCard;
  end;
end;

/// <summary>Anhänge: Name und Größe; Doppelklick öffnet.</summary>
procedure TAtlasIssueSections.AddAttachments;
var
  mAttachment: TAtlasTrackerAttachment;
  mItem: TListItem;
  mList: TListView;
  mAttachments: TArray<TAtlasTrackerAttachment>;
begin
  mAttachments := FState.Details.Attachments;
  if Length(mAttachments) = 0 then
  begin
    Exit;
  end;
  FLayout.AddSection(TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewAttachments, [Length(mAttachments)]));
  mList := FLayout.AddList(TArray<string>.Create(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewColumnName),
    TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewColumnSize)), TAtlasIssuePart.Attachment);
  mList.Items.BeginUpdate;
  try
    for mAttachment in mAttachments do
    begin
      mItem := mList.Items.Add;
      mItem.Caption := mAttachment.Name;
      mItem.SubItems.Add(SizeText(mAttachment.Size));
    end;
  finally
    mList.Items.EndUpdate;
  end;
  mList.Height := FLayout.RowsHeight(Length(mAttachments) + cListExtraRows);
  mList.OnDblClick := FLayout.OnClick;
  mList.OnKeyDown := ListKeyDown;
  FContent.Attachments := mList;
end;

/// <summary>Verknüpfte Issues als Liste: Klick öffnet sie im selben Fenster (bzw. im Browser).</summary>
procedure TAtlasIssueSections.AddLinkList;
var
  mLink: TAtlasTrackerLink;
  mItem: TListItem;
  mList: TListView;
  mLinks: TArray<TAtlasTrackerLink>;
begin
  mLinks := FState.Details.Links;
  if Length(mLinks) = 0 then
  begin
    Exit;
  end;
  FLayout.AddSection(TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewLinks, [Length(mLinks)]));
  mList := FLayout.AddList(TArray<string>.Create(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewColumnKey),
    TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewColumnTitle),
    TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewColumnRelation)), TAtlasIssuePart.Link);
  mList.Items.BeginUpdate;
  try
    for mLink in mLinks do
    begin
      mItem := mList.Items.Add;
      mItem.Caption := mLink.Key;
      mItem.SubItems.Add(mLink.Title);
      mItem.SubItems.Add(RelationText(mLink));
    end;
  finally
    mList.Items.EndUpdate;
  end;
  mList.Height := FLayout.RowsHeight(Length(mLinks) + cListExtraRows);
  mList.OnClick := FLayout.OnClick;
  FContent.Links := mList;
end;

/// <summary>[Unteraufgabe anlegen …] [Verknüpfen …] über dem Baum (#1279).</summary>
procedure TAtlasIssueSections.AddLinkTools;
var
  mTools: TPanel;
begin
  mTools := TPanel.Create(FLayout.Owner);
  FLayout.Place(mTools);
  mTools.BevelOuter := bvNone;
  mTools.ShowCaption := False;
  mTools.Height := MulDiv(cLinkToolsHeight, mTools.CurrentPPI, USER_DEFAULT_SCREEN_DPI);
  FContent.CreateSubtask := FLayout.AddButton(mTools, TAtlasIssueTextId.IssueLinksCreateSubtask, cSubtaskWidth,
    TAtlasIssuePart.CreateSubtask);
  FContent.AddLink := FLayout.AddButton(mTools, TAtlasIssueTextId.IssueLinksAddLink, cLinkWidth,
    TAtlasIssuePart.AddLink);
end;

procedure TAtlasIssueSections.FitLinkTree;
var
  mNode: TTreeNode;
  mRows: Integer;
begin
  if FContent.LinkTree = nil then
  begin
    Exit;
  end;
  mRows := 0;
  mNode := FContent.LinkTree.Items.GetFirstNode;
  while mNode <> nil do
  begin
    Inc(mRows);
    if mNode.Expanded then
    begin
      Inc(mRows, mNode.Count);
    end;
    mNode := mNode.getNextSibling;
  end;
  FContent.LinkTree.Height := FLayout.RowsHeight(mRows + 1);
end;

/// <summary>Verknüpfungen als Baum (#1279); mit CanWriteLinks die Knöpfe darüber.</summary>
procedure TAtlasIssueSections.AddLinkTree;
var
  mHasGroups: Boolean;
  mTree: TTreeView;
  mWrite: Boolean;
begin
  mHasGroups := TAtlasIssueLinkText.HasGroups(FState.Details.Links);
  mWrite := TAtlasIssueFlag.CanWriteLinks in FFlags;
  if not mHasGroups and not mWrite then
  begin
    Exit;
  end;
  FLayout.AddSection(TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssueLinksCaption, [Length(FState.Details.Links)]));
  if mWrite then
  begin
    AddLinkTools;
  end;
  if not mHasGroups then
  begin
    Exit;
  end;
  mTree := TTreeView.Create(FLayout.Owner);
  FLayout.Place(mTree);
  mTree.ReadOnly := True;
  mTree.RowSelect := True;
  mTree.HideSelection := False;
  mTree.ShowHint := True;
  mTree.Color := TColor(FLayout.Colors.Surface);
  mTree.Font.Color := TColor(FLayout.Colors.Text);
  FContent.LinkTree := mTree;
  TAtlasIssueLinkText.FillTree(mTree, FState.Details.Links, FContent.TreeLinks);
  mTree.Tag := cAtlasIssuePartTag + Ord(TAtlasIssuePart.LinkTree);
  mTree.OnClick := FLayout.OnClick;
  mTree.OnKeyDown := ListKeyDown;
  mTree.OnExpanded := LinkTreeExpanded;
  mTree.OnCollapsed := LinkTreeExpanded;
  FitLinkTree;
end;

procedure TAtlasIssueSections.LinkTreeExpanded(Sender: TObject; Node: TTreeNode);
begin
  FitLinkTree;
end;

procedure TAtlasIssueSections.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    FLayout.OnClick(Sender);
    Key := 0;
  end;
end;

procedure TAtlasIssueSections.Build(var AState: TAtlasIssueFrameState; AFlags: TAtlasIssueFlags);
var
  mProgress: TAtlasChecklistProgress;
begin
  FState := AState;
  FFlags := AFlags;
  ClearContent;
  if not FState.HasDetails then
  begin
    Exit;
  end;
  // Checklisten (#1273): Fortschritt in der Kopfzeile, Kästchen in der Beschreibung.
  mProgress := TAtlasChecklistProgress.Create(0, 0);
  if TAtlasIssueFlag.Checklists in FFlags then
  begin
    mProgress := TAtlasTrackerChecklist.Progress(FState.Details.Description);
  end;
  AddHeader(mProgress);
  AddDescription(mProgress);
  AddComments;
  AddAttachments;
  if TAtlasIssueFlag.LinksAsTree in FFlags then
  begin
    AddLinkTree;
  end
  else
  begin
    AddLinkList;
  end;
  AState.CommentsExpanded := FState.CommentsExpanded;
end;

function TAtlasIssueSections.ImageUrls: TArray<string>;
var
  mImage: TAtlasIssueImageBox;
begin
  Result := nil;
  for mImage in FContent.Images do
  begin
    if mImage.Url <> '' then
    begin
      Result := Result + [mImage.Url];
    end;
  end;
end;

procedure TAtlasIssueSections.SetImage(const AUrl: string; AGraphic: TGraphic);
var
  mImage: TAtlasIssueImageBox;
  mOwned: Boolean;
  mCopy: TGraphic;
begin
  if AGraphic = nil then
  begin
    Exit;
  end;
  mOwned := False;
  try
    for mImage in FContent.Images do
    begin
      if mImage.Url <> AUrl then
      begin
        Continue;
      end;
      // Dasselbe Bild mehrfach: jede Fläche bekommt ein eigenes.
      if not mOwned then
      begin
        mImage.SetGraphic(AGraphic);
        mOwned := True;
      end
      else
      begin
        mCopy := TGraphicClass(AGraphic.ClassType).Create;
        mCopy.Assign(AGraphic);
        mImage.SetGraphic(mCopy);
      end;
    end;
  finally
    if not mOwned then
    begin
      AGraphic.Free;
    end;
  end;
end;

function TAtlasIssueSections.SelectedListLink(out ALink: TAtlasTrackerLink): Boolean;
var
  mList: TListView;
begin
  ALink := Default(TAtlasTrackerLink);
  mList := FContent.Links;
  Result := (mList <> nil) and (mList.Selected <> nil) and (mList.Selected.Index <= High(FState.Details.Links));
  if Result then
  begin
    ALink := FState.Details.Links[mList.Selected.Index];
  end;
end;

function TAtlasIssueSections.SelectedTreeLink(out ALink: TAtlasTrackerLink): Boolean;
var
  mTree: TTreeView;
  mIndex: NativeInt;
begin
  ALink := Default(TAtlasTrackerLink);
  Result := False;
  mTree := FContent.LinkTree;
  if (mTree = nil) or (mTree.Selected = nil) or (mTree.Selected.Data = nil) then
  begin
    Exit;
  end;
  mIndex := NativeInt(mTree.Selected.Data) - 1;
  Result := (mIndex >= 0) and (mIndex <= High(FContent.TreeLinks));
  if Result then
  begin
    ALink := FContent.TreeLinks[mIndex];
  end;
end;

function TAtlasIssueSections.SelectedLink(APart: TAtlasIssuePart; out ALink: TAtlasTrackerLink): Boolean;
begin
  if APart = TAtlasIssuePart.LinkTree then
  begin
    Result := SelectedTreeLink(ALink);
  end
  else
  begin
    Result := SelectedListLink(ALink);
  end;
end;

function TAtlasIssueSections.SelectedAttachment(out AAttachment: TAtlasTrackerAttachment): Boolean;
var
  mList: TListView;
begin
  AAttachment := Default(TAtlasTrackerAttachment);
  mList := FContent.Attachments;
  Result := (mList <> nil) and (mList.Selected <> nil) and
    (mList.Selected.Index <= High(FState.Details.Attachments));
  if Result then
  begin
    AAttachment := FState.Details.Attachments[mList.Selected.Index];
  end;
end;

function TAtlasIssueSections.RevealAnchor: Boolean;
begin
  Result := False;
  if FContent.AnchorLabel = nil then
  begin
    Exit;
  end;
  FLayout.ScrollTo(FContent.AnchorLabel);
  Result := FState.Details.Comments[FContent.AnchorComment].Created >=
    FState.Anchor - TAtlasIssuePreview.cAnchorSlackMs / MSecsPerDay;
end;

function TAtlasIssueSections.ScrollToTasks: Boolean;
var
  mBar: TControlScrollBar;
begin
  Result := FContent.TaskBox <> nil;
  if not Result then
  begin
    Exit;
  end;
  mBar := FLayout.Box.VertScrollBar;
  mBar.Position := Max(0, FContent.TaskBox.Top + mBar.Position - FLayout.Box.Padding.Top);
end;

end.
