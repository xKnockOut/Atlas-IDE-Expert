unit Atlas.UI.Tracker.SettingsGeneral;

// Übrige Schalter der Seite Issue-Tracker: Anbieter, „Beginnen“, Muster für
// Branch und Commit, Vorschau, Verweise im Code, Zeiterfassung (#1267),
// Checklisten, Board, Sprint, Meldungen und Anhänge. Alle hängen an ihrem
// Schlüssel; die Seite liest und schreibt sie selbst. Nur das Muster des
// Commits schreibt Save ungekürzt nach (das Leerzeichen am Ende trennt
// Kennung und Nachricht).

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Contract,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Tracker.Strings,
  Atlas.UI.Tracker.SettingsRows;

type
  /// <summary>Gebundene Schalter, Zahlen, Textzeilen und Auswahlen.</summary>
  TAtlasTrackerGeneralView = record
    Tracker: TAtlasChoiceBox;
    Start: TAtlasChoiceBox;
    BranchPattern: TEdit;
    BranchBase: TEdit;
    CommitPattern: TEdit;
    Login: TCheckBox;
    Preview: TCheckBox;
    PreviewComments: TCheckBox;
    CodeLinks: TCheckBox;
    BlameLinks: TCheckBox;
    BlameMaxRevisions: TEdit;
    PaletteSearch: TCheckBox;
    CommentEditor: TCheckBox;
    TimeTracking: TCheckBox;
    IdleMinutes: TEdit;
    TimeRounding: TEdit;
    PreviewChecklists: TCheckBox;
    ChecklistStatus: TCheckBox;
    PreviewLinks: TCheckBox;
    WarnBlocked: TCheckBox;
    Board: TCheckBox;
    BoardConfirmMove: TCheckBox;
    BoardOnlyMine: TCheckBox;
    SprintBurndown: TCheckBox;
    SprintCompare: TCheckBox;
    PreviewDevelopment: TCheckBox;
    Notify: TCheckBox;
    NotifyInterval: TEdit;
    NotifyScope: TAtlasChoiceBox;
    Attach: TCheckBox;
    AttachLogFiles: TEdit;
    AttachMaxImageWidth: TEdit;
  end;

  TAtlasTrackerGeneralPart = class
  public const
    cCommitPatternKey = 'issues.commitPattern';
  private
    FRows: TAtlasTrackerSettingsRows;
    FView: TAtlasTrackerGeneralView;
    procedure BuildTracker;
    procedure BuildPatterns;
    procedure BuildPreview;
    procedure BuildChecklists;
    procedure BuildBoard;
    procedure BuildNotify;
    procedure BuildAttach;
    function Check(const AKey: string; AText: TAtlasTrackerTextId): TCheckBox;
    function Number(const AKey: string; AText: TAtlasTrackerTextId): TEdit;
    function Line(const AKey: string; AText: TAtlasTrackerTextId): TEdit;
  public
    constructor Create(ARows: TAtlasTrackerSettingsRows);
    /// <summary>Anbieter bis Kommentar-Editor (unter den Abfragen).</summary>
    procedure BuildStart;
    /// <summary>Zeiterfassung (#1267) mit eigenem Titel.</summary>
    procedure BuildTime;
    /// <summary>Checklisten bis Anhänge (unter den Textbausteinen).</summary>
    procedure BuildMore;
    procedure Save(const AValues: IAtlasSettingsValues);
    property View: TAtlasTrackerGeneralView read FView;
  end;

implementation

uses
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Settings.Plugin;

const
  cGitHubCaption = 'GitHub';
  cYouTrackCaption = 'YouTrack';

{ TAtlasTrackerGeneralPart }

constructor TAtlasTrackerGeneralPart.Create(ARows: TAtlasTrackerSettingsRows);
begin
  inherited Create;
  FRows := ARows;
end;

function TAtlasTrackerGeneralPart.Check(const AKey: string; AText: TAtlasTrackerTextId): TCheckBox;
begin
  Result := FRows.AddCheck(AKey, TAtlasTrackerStrings.Text(AText));
end;

function TAtlasTrackerGeneralPart.Number(const AKey: string; AText: TAtlasTrackerTextId): TEdit;
begin
  Result := FRows.AddNumber(AKey, TAtlasTrackerStrings.Text(AText));
end;

function TAtlasTrackerGeneralPart.Line(const AKey: string; AText: TAtlasTrackerTextId): TEdit;
begin
  Result := FRows.AddText(AKey, TAtlasTrackerStrings.Text(AText));
end;

procedure TAtlasTrackerGeneralPart.BuildStart;
begin
  BuildTracker;
  BuildPatterns;
  BuildPreview;
end;

procedure TAtlasTrackerGeneralPart.BuildTracker;
begin
  // Anbieter (Vorgabe aus der .atlas) und „Beginnen“ (#765).
  FView.Tracker := FRows.AddChoice('issues.tracker',
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesTracker),
    TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesTrackerTeam), cGitHubCaption,
    cYouTrackCaption), TArray<string>.Create('', TAtlasTrackerTarget.cGitHub, TAtlasTrackerTarget.cYouTrack));
  FView.Start := FRows.AddChoice('issues.start', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesStart),
    TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesStartBranch),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesStartRemember)),
    TArray<string>.Create(TAtlasPluginSettings.cIssuesStartBranch, TAtlasPluginSettings.cIssuesStartRemember));
end;

procedure TAtlasTrackerGeneralPart.BuildPatterns;
begin
  FView.BranchPattern := Line('issues.branchPattern', TAtlasTrackerTextId.SettingsIssuesBranchPattern);
  FView.BranchBase := Line('issues.branchBase', TAtlasTrackerTextId.SettingsIssuesBranchBase);
  FView.CommitPattern := Line(cCommitPatternKey, TAtlasTrackerTextId.SettingsIssuesCommitPattern);
  FView.Login := Check('issues.login', TAtlasTrackerTextId.SettingsTrackerLogin);
end;

procedure TAtlasTrackerGeneralPart.BuildPreview;
begin
  // Issue-Vorschau (#1264): Hauptschalter, Kommentare darunter.
  FView.Preview := Check('issues.preview', TAtlasTrackerTextId.SettingsIssuesPreview);
  FView.PreviewComments := Check('issues.preview.comments', TAtlasTrackerTextId.SettingsIssuesPreviewComments);
  FView.CodeLinks := Check('issues.codeLinks', TAtlasTrackerTextId.SettingsIssuesCodeLinks);
  // Issues in der Zeilenhistorie (#1275): Schalter, darunter die Grenze für „Issues zu dieser Methode“.
  FView.BlameLinks := Check('issues.blameLinks', TAtlasTrackerTextId.SettingsIssuesBlameLinks);
  FView.BlameMaxRevisions := Number('issues.blameLinks.maxRevisions',
    TAtlasTrackerTextId.SettingsIssuesBlameMaxRevisions);
  // Issues in der Befehlspalette (#1270) und Kommentar-Editor (#1278).
  FView.PaletteSearch := Check('issues.paletteSearch', TAtlasTrackerTextId.SettingsIssuesPaletteSearch);
  FView.CommentEditor := Check('issues.commentEditor', TAtlasTrackerTextId.SettingsIssuesCommentEditor);
end;

procedure TAtlasTrackerGeneralPart.BuildTime;
begin
  // Hauptschalter, Leerlauf und Rundung (x-parent issues.timeTracking).
  FRows.AddTitle(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesTimeTitle));
  FView.TimeTracking := Check('issues.timeTracking', TAtlasTrackerTextId.SettingsIssuesTimeTracking);
  FView.IdleMinutes := Number('issues.idleMinutes', TAtlasTrackerTextId.SettingsIssuesIdleMinutes);
  FView.TimeRounding := Number('issues.timeRounding', TAtlasTrackerTextId.SettingsIssuesTimeRounding);
end;

procedure TAtlasTrackerGeneralPart.BuildMore;
begin
  BuildChecklists;
  BuildBoard;
  BuildNotify;
  BuildAttach;
end;

procedure TAtlasTrackerGeneralPart.BuildChecklists;
begin
  // Checklisten (#1273): in der Vorschau unter deren Hauptschalter, das Statusfeld eigenständig.
  FView.PreviewChecklists := Check('issues.preview.checklists', TAtlasTrackerTextId.SettingsIssuesPreviewChecklists);
  FView.ChecklistStatus := Check('issues.checklistStatus', TAtlasTrackerTextId.SettingsIssuesChecklistStatus);
  // Abhängigkeiten und Unteraufgaben (#1279): Baum in der Vorschau, Warnung beim Beginnen.
  FView.PreviewLinks := Check('issues.preview.links', TAtlasTrackerTextId.SettingsIssuesPreviewLinks);
  FView.WarnBlocked := Check('issues.warnBlocked', TAtlasTrackerTextId.SettingsIssuesWarnBlocked);
end;

procedure TAtlasTrackerGeneralPart.BuildBoard;
begin
  // Board (#1272): Hauptschalter, Rückfrage beim Ziehen, Filter beim Öffnen.
  FView.Board := Check('issues.board', TAtlasTrackerTextId.SettingsIssuesBoard);
  FView.BoardConfirmMove := Check('issues.board.confirmMove', TAtlasTrackerTextId.SettingsIssuesBoardConfirmMove);
  FView.BoardOnlyMine := Check('issues.board.onlyMine', TAtlasTrackerTextId.SettingsIssuesBoardOnlyMine);
  // Sprint-Kachel (#1277): Burndown-Linie, Vergleich mit dem Vorsprint und Velocity.
  FView.SprintBurndown := Check('issues.sprint.burndown', TAtlasTrackerTextId.SettingsIssuesSprintBurndown);
  FView.SprintCompare := Check('issues.sprint.compare', TAtlasTrackerTextId.SettingsIssuesSprintCompare);
  // Reiter „Entwicklung“ der Vorschau (#1269).
  FView.PreviewDevelopment := Check('issues.preview.development',
    TAtlasTrackerTextId.SettingsIssuesPreviewDevelopment);
end;

procedure TAtlasTrackerGeneralPart.BuildNotify;
begin
  // Meldungen zu meinen Issues (#1271): Hauptschalter, Abstand und Umfang darunter.
  FView.Notify := Check('issues.notify', TAtlasTrackerTextId.SettingsIssuesNotify);
  FView.NotifyInterval := Number('issues.notify.intervalMinutes', TAtlasTrackerTextId.SettingsIssuesNotifyInterval);
  // Reihenfolge wie TAtlasTrackerNotifyScope.
  FView.NotifyScope := FRows.AddChoice('issues.notify.scope',
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesNotifyScope),
    TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesNotifyScopeAssigned),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesNotifyScopeCreated),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesNotifyScopeWatched)),
    TArray<string>.Create(TAtlasPluginSettings.cIssuesNotifyAssigned, TAtlasPluginSettings.cIssuesNotifyAssignedOrCreated,
    TAtlasPluginSettings.cIssuesNotifyWatched));
end;

procedure TAtlasTrackerGeneralPart.BuildAttach;
begin
  // An Issue anhängen (#1276): Hauptschalter, Logdateien und Bildbreite darunter.
  FView.Attach := Check('issues.attach', TAtlasTrackerTextId.SettingsIssuesAttach);
  FView.AttachLogFiles := Line('issues.attach.logFiles', TAtlasTrackerTextId.SettingsIssuesAttachLogFiles);
  FView.AttachMaxImageWidth := Number('issues.attach.maxImageWidth',
    TAtlasTrackerTextId.SettingsIssuesAttachMaxImageWidth);
end;

procedure TAtlasTrackerGeneralPart.Save(const AValues: IAtlasSettingsValues);
begin
  // Nicht gekürzt: Das Leerzeichen am Ende von "{kennung} " trennt Kennung und Nachricht.
  AValues.WriteString(cCommitPatternKey, FView.CommitPattern.Text);
end;

end.
