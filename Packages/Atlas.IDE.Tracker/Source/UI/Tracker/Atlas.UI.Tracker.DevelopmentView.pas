unit Atlas.UI.Tracker.DevelopmentView;

// Reiter „Entwicklung“ im Fenster „Atlas-Issue“ (#1269), reine VCL ohne Open
// Tools API:
//   BRANCHES (n)          Branch · Ort · Stand          [Wechseln]
//   COMMITS (n)           Commit · Betreff · Autor · Zeit
//                         Klick: Diff, Doppelklick: erste geänderte Unit öffnen
//   PULL REQUESTS (n)     Nummer · Titel · Stand · CI      (GitHub)
//   bzw. IM TRACKER VERKNÜPFTE ÄNDERUNGEN (n)              (YouTrack)
//   GEÄNDERTE UNITS (n)   Baum nach Projekt; Klick öffnet die Unit
// Was fehlt (kein Projekt, keine Arbeitskopie, Fehler), steht als Zeile im
// jeweiligen Abschnitt. Laden, Wechseln, Diff und Öffnen liegen in der
// IDE-Schicht; die Ansicht meldet nur Wünsche (On…). Klick und Doppelklick
// auf einen Commit trennt ein Zeitgeber mit der Doppelklickzeit des Systems:
// Erst wenn kein zweiter Klick kommt, folgt der Diff.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Types,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Development,
  Atlas.Core.VersionControl.Contract;

type
  /// <summary>Wünsche der Ansicht an die IDE-Schicht.</summary>
  TAtlasIssueDevelopmentEvents = record
    /// <summary>Klick auf einen Commit: Diff zeigen.</summary>
    ShowDiff: TProc<TAtlasVcsLogEntry>;
    /// <summary>Doppelklick bzw. Eingabe auf einen Commit: erste geänderte Unit an der Stelle öffnen.</summary>
    OpenCommit: TProc<TAtlasVcsLogEntry>;
    SwitchBranch: TProc<TAtlasIssueBranch>;
    OpenUnit: TProc<TAtlasIssueUnit>;
    OpenPull: TProc<TAtlasTrackerPull>;
  end;

  /// <summary>Steuerelemente des gezeigten Inhalts; nil, solange der Abschnitt fehlt. Status ist die Zeile über dem
  /// Inhalt bzw. die einzige Zeile.</summary>
  TAtlasIssueDevelopmentParts = record
    Status: TLabel;
    Branches: TListView;
    Switch: TButton;
    Commits: TListView;
    Pulls: TListView;
    Changes: TListView;
    Units: TTreeView;
    CommitTimer: TTimer;
  end;

  TAtlasIssueDevelopmentView = class(TScrollBox)
  private
    FItems: TList<TControl>;
    FNextTop: Integer;
    FColors: TAtlasColors;
    FDevelopment: TAtlasIssueDevelopment;
    FHasDevelopment: Boolean;
    FTrackerNote: string;
    FVcsNote: string;
    FParts: TAtlasIssueDevelopmentParts;
    FUnitList: TArray<TAtlasIssueUnit>;
    FPendingCommit: Integer;
    FEvents: TAtlasIssueDevelopmentEvents;
    procedure Clear;
    procedure AddBranches;
    procedure AddCommits;
    procedure AddTracker(const ATrackerNote: string);
    procedure AddUnits;
    procedure BranchesSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure SwitchClick(Sender: TObject);
    procedure CommitsClick(Sender: TObject);
    procedure CommitsDblClick(Sender: TObject);
    procedure CommitsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure CommitTimerFired(Sender: TObject);
    procedure PullsDblClick(Sender: TObject);
    procedure UnitsClick(Sender: TObject);
    procedure UnitsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function SelectedCommit(out AEntry: TAtlasVcsLogEntry): Boolean;
    procedure ScrollWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
      var Handled: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Suche läuft; der bisherige Inhalt weicht der Zeile.</summary>
    procedure ShowLoading;
    /// <summary>Nur eine Zeile (z. B. kein Projekt geöffnet).</summary>
    procedure ShowNote(const AText: string);
    /// <summary>Ergebnis zeigen. ATrackerNote: Fehler des Trackers ('' ohne).</summary>
    procedure ShowDevelopment(const ADevelopment: TAtlasIssueDevelopment; const ATrackerNote: string); overload;
    /// <summary>Wie oben; AVcsNote ersetzt Branches, Commits und Units (z. B. kein Projekt geöffnet).</summary>
    procedure ShowDevelopment(const ADevelopment: TAtlasIssueDevelopment; const ATrackerNote, AVcsNote: string);
      overload;
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Für Tests: Klick auf einen Commit sofort auswerten (statt nach der Doppelklickzeit).</summary>
    procedure FireCommitClick;
    property Development: TAtlasIssueDevelopment read FDevelopment;
    property HasDevelopment: Boolean read FHasDevelopment;
    property Parts: TAtlasIssueDevelopmentParts read FParts;
    property Events: TAtlasIssueDevelopmentEvents read FEvents write FEvents;
  end;

  /// <summary>Für Tests: Inhalt der Ansicht als Text.</summary>
  TAtlasIssueDevelopmentProbe = class
  public
    /// <summary>Zeile über dem Inhalt bzw. die einzige Zeile; '' ohne.</summary>
    class function StatusText(AView: TAtlasIssueDevelopmentView): string; static;
    /// <summary>Beschriftungen der Units im Baum (Gruppe, dann Units eingerückt mit zwei Leerzeichen).</summary>
    class function UnitLines(AView: TAtlasIssueDevelopmentView): TArray<string>; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.DateUtils,
  Vcl.Graphics,
  Atlas.Core.Style.Color,
  Atlas.UI.Foundation.WrapLabel,
  Atlas.UI.Tracker.Development.Strings;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasIssueDevelopmentView }

constructor TAtlasIssueDevelopmentView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TList<TControl>.Create;
  FColors := TAtlasColors.Light;
  FDevelopment := TAtlasIssueDevelopment.Empty;
  FPendingCommit := -1;
  BorderStyle := bsNone;
  VertScrollBar.Tracking := True;
  HorzScrollBar.Visible := False;
  Padding.SetBounds(8, 4, 8, 8);
  OnMouseWheel := ScrollWheel;
  FParts.CommitTimer := TTimer.Create(Self);
  FParts.CommitTimer.Enabled := False;
  FParts.CommitTimer.Interval := GetDoubleClickTime;
  FParts.CommitTimer.OnTimer := CommitTimerFired;
end;

destructor TAtlasIssueDevelopmentView.Destroy;
begin
  if FParts.CommitTimer <> nil then
  begin
    FParts.CommitTimer.Enabled := False;
  end;
  FItems.Free;
  inherited;
end;

/// <summary>Untereinander in der Reihenfolge des Anlegens: alTop ordnet nach Top.</summary>
procedure Place(AView: TAtlasIssueDevelopmentView; AControl: TControl);
begin
  Inc(AView.FNextTop, 1000);
  AControl.Parent := AView;
  AControl.Align := alTop;
  AControl.AlignWithMargins := True;
  AControl.Top := AView.FNextTop;
  AView.FItems.Add(AControl);
end;
function AddLabel(AView: TAtlasIssueDevelopmentView; const ACaption: string; AHeading: Boolean): TLabel;
begin
  Result := TAtlasWrapLabel.Create(AView);
  Place(AView, Result);
  Result.WordWrap := True;
  Result.ShowAccelChar := False;
  Result.Font.Color := ToColor(AView.FColors.Text);
  if AHeading then
  begin
    Result.Caption := AnsiUpperCase(ACaption);
    Result.Font.Style := [fsBold];
    Result.Font.Color := ToColor(AView.FColors.Muted);
  end
  else
  begin
    Result.Caption := ACaption;
  end;
end;
function AddNote(AView: TAtlasIssueDevelopmentView; const ACaption: string): TLabel;
begin
  Result := AddLabel(AView, ACaption, False);
  Result.Font.Color := ToColor(AView.FColors.Muted);
end;
function AddList(AView: TAtlasIssueDevelopmentView; const AColumns: TArray<string>; ARows: Integer): TListView;
var
  mCaption: string;
  mColumn: TListColumn;
begin
  Result := TListView.Create(AView);
  Place(AView, Result);
  Result.ViewStyle := vsReport;
  Result.ReadOnly := True;
  Result.RowSelect := True;
  Result.HideSelection := False;
  Result.ShowColumnHeaders := True;
  for mCaption in AColumns do
  begin
    mColumn := Result.Columns.Add;
    mColumn.Caption := mCaption;
    mColumn.AutoSize := True;
  end;
  Result.Height := (Min(ARows, 12) + 2) * MulDiv(20, AView.CurrentPPI, 96);
end;

/// <summary>Spalten Commit, Betreff, Autor, Zeit.</summary>
function CommitColumns: TArray<string>;
begin
  Result := TArray<string>.Create(TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevColumnCommit),
    TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevColumnSubject),
    TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevColumnAuthor),
    TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevColumnTime));
end;
procedure TAtlasIssueDevelopmentView.Clear;
var
  mIndex: Integer;
begin
  FParts.CommitTimer.Enabled := False;
  FPendingCommit := -1;
  DisableAlign;
  try
    for mIndex := FItems.Count - 1 downto 0 do
    begin
      FItems[mIndex].Free;
    end;
    FItems.Clear;
    FParts.Status := nil;
    FParts.Branches := nil;
    FParts.Switch := nil;
    FParts.Commits := nil;
    FParts.Pulls := nil;
    FParts.Changes := nil;
    FParts.Units := nil;
    FUnitList := nil;
    FNextTop := 0;
  finally
    EnableAlign;
  end;
end;

procedure TAtlasIssueDevelopmentView.ShowLoading;
begin
  FHasDevelopment := False;
  FDevelopment := TAtlasIssueDevelopment.Empty;
  Clear;
  FParts.Status := AddNote(Self, TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevLoading));
end;

procedure TAtlasIssueDevelopmentView.ShowNote(const AText: string);
begin
  FHasDevelopment := False;
  FDevelopment := TAtlasIssueDevelopment.Empty;
  Clear;
  FParts.Status := AddNote(Self, AText);
end;

function WhenText(ATime: TDateTime): string;
begin
  Result := '';
  if ATime > 0 then
  begin
    Result := FormatDateTime('dd.mm.yyyy hh:nn', TTimeZone.Local.ToLocalTime(ATime), FormatSettings);
  end;
end;
/// <summary>Zeile, warum Branches und Commits fehlen; '' wenn die Versionsverwaltung geantwortet hat.</summary>
function VcsText(const ADevelopment: TAtlasIssueDevelopment): string;
begin
  case ADevelopment.VcsOutcome of
    TAtlasVcsOutcome.Ok, TAtlasVcsOutcome.Cancelled:
      Result := '';
    TAtlasVcsOutcome.NoWorkingCopy:
      Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevNoVcs);
    TAtlasVcsOutcome.Disabled:
      Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevVcsOff);
    TAtlasVcsOutcome.ToolMissing:
      Result := TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevToolMissing,
        [AtlasVcsKindName(ADevelopment.VcsKind)]);
  else
    Result := TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevVcsFailed,
      [AtlasVcsOutcomeName(ADevelopment.VcsOutcome)]);
  end;
end;

procedure TAtlasIssueDevelopmentView.ShowDevelopment(const ADevelopment: TAtlasIssueDevelopment;
  const ATrackerNote: string);
begin
  ShowDevelopment(ADevelopment, ATrackerNote, '');
end;

procedure TAtlasIssueDevelopmentView.ShowDevelopment(const ADevelopment: TAtlasIssueDevelopment;
  const ATrackerNote, AVcsNote: string);
var
  mVcs: string;
begin
  FDevelopment := ADevelopment;
  FHasDevelopment := True;
  FTrackerNote := ATrackerNote;
  FVcsNote := AVcsNote;
  DisableAlign;
  try
    Clear;
    mVcs := AVcsNote;
    if mVcs = '' then
    begin
      mVcs := VcsText(ADevelopment);
    end;
    if mVcs <> '' then
    begin
      FParts.Status := AddNote(Self, mVcs);
    end
    else
    begin
      AddBranches;
      AddCommits;
    end;
    AddTracker(ATrackerNote);
    if mVcs = '' then
    begin
      AddUnits;
    end;
  finally
    EnableAlign;
  end;
  VertScrollBar.Position := 0;
end;

/// <summary>Ort eines Branches: lokal, entfernt oder beides.</summary>
function BranchWhere(const ABranch: TAtlasIssueBranch): string;
begin
  if ABranch.Local and ABranch.Remote then
  begin
    Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevLocalRemote);
  end
  else if ABranch.Local then
  begin
    Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevLocal);
  end
  else
  begin
    Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevRemote);
  end;
end;

/// <summary>Stand eines Branches: „aktuell“ und Vorsprung bzw. Rückstand gegen die Basis.</summary>
function BranchState(const ABranch: TAtlasIssueBranch): string;
begin
  Result := '';
  if (ABranch.Base <> '') and (ABranch.Ahead >= 0) and (ABranch.Behind >= 0) then
  begin
    Result := TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevAheadBehind,
      [ABranch.Ahead, ABranch.Behind, ABranch.Base]);
  end;
  if ABranch.Current and (Result <> '') then
  begin
    Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevCurrent) + ', ' + Result;
  end
  else if ABranch.Current then
  begin
    Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevCurrent);
  end;
end;

/// <summary>Knopf „Wechseln“ unter der Liste der Branches.</summary>
function AddSwitch(AView: TAtlasIssueDevelopmentView): TButton;
var
  mTools: TPanel;
begin
  mTools := TPanel.Create(AView);
  Place(AView, mTools);
  mTools.BevelOuter := bvNone;
  mTools.ShowCaption := False;
  mTools.Height := MulDiv(30, AView.CurrentPPI, 96);
  Result := TButton.Create(AView);
  Result.Parent := mTools;
  Result.Align := alLeft;
  Result.Caption := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevSwitch);
  Result.Width := MulDiv(100, AView.CurrentPPI, 96);
  Result.Enabled := False;
end;

procedure TAtlasIssueDevelopmentView.AddBranches;
var
  mBranch: TAtlasIssueBranch;
  mItem: TListItem;
begin
  AddLabel(Self, TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevBranches, [Length(FDevelopment.Branches)]),
    True);
  if Length(FDevelopment.Branches) = 0 then
  begin
    AddNote(Self, TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevNoBranch, [FDevelopment.Key]));
    Exit;
  end;
  FParts.Branches := AddList(Self, TArray<string>.Create(
    TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevColumnBranch),
    TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevColumnWhere),
    TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevColumnState)), Length(FDevelopment.Branches));
  FParts.Branches.Items.BeginUpdate;
  try
    for mBranch in FDevelopment.Branches do
    begin
      mItem := FParts.Branches.Items.Add;
      mItem.Caption := mBranch.Name;
      mItem.SubItems.Add(BranchWhere(mBranch));
      mItem.SubItems.Add(BranchState(mBranch));
    end;
  finally
    FParts.Branches.Items.EndUpdate;
  end;
  FParts.Branches.OnSelectItem := BranchesSelect;
  FParts.Switch := AddSwitch(Self);
  FParts.Switch.OnClick := SwitchClick;
end;
procedure TAtlasIssueDevelopmentView.AddCommits;
var
  mEntry: TAtlasVcsLogEntry;
  mItem: TListItem;
begin
  if FDevelopment.Truncated then
  begin
    AddLabel(Self, TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevCommitsMore, [Length(FDevelopment.Commits)]),
      True);
  end
  else
  begin
    AddLabel(Self, TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevCommits, [Length(FDevelopment.Commits)]),
      True);
  end;
  if Length(FDevelopment.Commits) = 0 then
  begin
    AddNote(Self, TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevNoCommits, [FDevelopment.Key]));
    Exit;
  end;
  FParts.Commits := AddList(Self, CommitColumns, Length(FDevelopment.Commits));
  FParts.Commits.Items.BeginUpdate;
  try
    for mEntry in FDevelopment.Commits do
    begin
      mItem := FParts.Commits.Items.Add;
      mItem.Caption := mEntry.ShortRevision(FDevelopment.VcsKind);
      mItem.SubItems.Add(mEntry.Summary);
      mItem.SubItems.Add(mEntry.Author);
      mItem.SubItems.Add(WhenText(mEntry.Date));
    end;
  finally
    FParts.Commits.Items.EndUpdate;
  end;
  FParts.Commits.Hint := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevCommitHint);
  FParts.Commits.ShowHint := True;
  FParts.Commits.OnClick := CommitsClick;
  FParts.Commits.OnDblClick := CommitsDblClick;
  FParts.Commits.OnKeyDown := CommitsKeyDown;
  AddNote(Self, TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevCommitHint));
end;
/// <summary>Im Tracker verknüpfte Änderungen (YouTrack kennt keine Pull Requests).</summary>
function AddChanges(AView: TAtlasIssueDevelopmentView; const AChanges: TArray<TAtlasTrackerVcsChange>): TListView;
var
  mChange: TAtlasTrackerVcsChange;
  mItem: TListItem;
begin
  AddLabel(AView, TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevTrackerChanges, [Length(AChanges)]), True);
  Result := AddList(AView, CommitColumns, Length(AChanges));
  Result.Items.BeginUpdate;
  try
    for mChange in AChanges do
    begin
      mItem := Result.Items.Add;
      mItem.Caption := Copy(mChange.Version, 1, 10);
      mItem.SubItems.Add(mChange.Text);
      mItem.SubItems.Add(mChange.Author);
      mItem.SubItems.Add(WhenText(mChange.Date));
    end;
  finally
    Result.Items.EndUpdate;
  end;
end;

function PullStateText(AState: TAtlasTrackerPullState): string;
begin
  case AState of
    TAtlasTrackerPullState.Draft:
      Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevPullDraft);
    TAtlasTrackerPullState.Merged:
      Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevPullMerged);
    TAtlasTrackerPullState.Closed:
      Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevPullClosed);
  else
    Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevPullOpen);
  end;
end;

function ChecksText(AChecks: TAtlasTrackerChecks): string;
begin
  case AChecks of
    TAtlasTrackerChecks.Pending:
      Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevChecksPending);
    TAtlasTrackerChecks.Success:
      Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevChecksSuccess);
    TAtlasTrackerChecks.Failure:
      Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevChecksFailure);
  else
    Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevChecksUnknown);
  end;
end;

/// <summary>Liste der Pull Requests: Nummer, Titel, Stand, CI.</summary>
function AddPulls(AView: TAtlasIssueDevelopmentView; const APulls: TArray<TAtlasTrackerPull>): TListView;
var
  mPull: TAtlasTrackerPull;
  mItem: TListItem;
begin
  Result := AddList(AView, TArray<string>.Create(TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevColumnNumber),
    TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevColumnSubject),
    TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevColumnState),
    TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevColumnChecks)), Length(APulls));
  Result.Items.BeginUpdate;
  try
    for mPull in APulls do
    begin
      mItem := Result.Items.Add;
      mItem.Caption := '#' + IntToStr(mPull.Number);
      mItem.SubItems.Add(mPull.Title);
      mItem.SubItems.Add(PullStateText(mPull.State));
      mItem.SubItems.Add(ChecksText(mPull.Checks));
    end;
  finally
    Result.Items.EndUpdate;
  end;
end;

procedure TAtlasIssueDevelopmentView.AddTracker(const ATrackerNote: string);
var
  mPulls: TArray<TAtlasTrackerPull>;
begin
  if ATrackerNote <> '' then
  begin
    AddNote(Self, TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevTrackerFailed, [ATrackerNote]));
    Exit;
  end;
  if not FDevelopment.TrackerLoaded then
  begin
    Exit;
  end;
  mPulls := FDevelopment.Tracker.Pulls;
  if Length(FDevelopment.Tracker.Changes) > 0 then
  begin
    FParts.Changes := AddChanges(Self, FDevelopment.Tracker.Changes);
  end;
  // Mit verknüpften Änderungen ohne Pull Requests entfällt der leere Abschnitt.
  if (Length(FDevelopment.Tracker.Changes) > 0) and (Length(mPulls) = 0) then
  begin
    Exit;
  end;
  AddLabel(Self, TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevPulls, [Length(mPulls)]), True);
  if Length(mPulls) = 0 then
  begin
    AddNote(Self, TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevNoPulls, [FDevelopment.Key]));
  end
  else
  begin
    FParts.Pulls := AddPulls(Self, mPulls);
    FParts.Pulls.OnDblClick := PullsDblClick;
  end;
end;
function UnitCaption(const AGroup: TAtlasIssueUnitGroup; const AUnit: TAtlasIssueUnit): string;
var
  mFolder: string;
begin
  // Unter dem Projektordner relativ, sonst vollständig.
  Result := AUnit.Path;
  if AGroup.ProjectFile <> '' then
  begin
    mFolder := IncludeTrailingPathDelimiter(ExtractFilePath(AGroup.ProjectFile));
    if SameText(Copy(AUnit.Path, 1, Length(mFolder)), mFolder) then
    begin
      Result := Copy(AUnit.Path, Length(mFolder) + 1, MaxInt);
    end;
  end;
  if AUnit.Deleted then
  begin
    Result := TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevDeleted, [Result]);
  end;
end;

procedure TAtlasIssueDevelopmentView.AddUnits;
var
  mGroup: TAtlasIssueUnitGroup;
  mUnit: TAtlasIssueUnit;
  mNode: TTreeNode;
  mCaption: string;
  mRows: Integer;
begin
  AddLabel(Self, TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevUnits, [FDevelopment.UnitCount]), True);
  if FDevelopment.UnitCount = 0 then
  begin
    AddNote(Self, TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevNoUnits));
    Exit;
  end;
  FParts.Units := TTreeView.Create(Self);
  Place(Self, FParts.Units);
  FParts.Units.ReadOnly := True;
  FParts.Units.HideSelection := False;
  FParts.Units.ShowRoot := True;
  mRows := 0;
  FParts.Units.Items.BeginUpdate;
  try
    for mGroup in FDevelopment.Units do
    begin
      mCaption := mGroup.Project;
      if mCaption = '' then
      begin
        mCaption := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevOtherFiles);
      end;
      mNode := FParts.Units.Items.AddChildObject(nil, Format('%s (%d)', [mCaption, Length(mGroup.Units)]),
        Pointer(-1));
      Inc(mRows);
      for mUnit in mGroup.Units do
      begin
        FUnitList := FUnitList + [mUnit];
        FParts.Units.Items.AddChildObject(mNode, UnitCaption(mGroup, mUnit), Pointer(NativeInt(High(FUnitList))));
        Inc(mRows);
      end;
      mNode.Expand(False);
    end;
  finally
    FParts.Units.Items.EndUpdate;
  end;
  FParts.Units.Height := (Min(mRows, 20) + 1) * MulDiv(19, CurrentPPI, 96);
  FParts.Units.OnClick := UnitsClick;
  FParts.Units.OnKeyDown := UnitsKeyDown;
end;

procedure TAtlasIssueDevelopmentView.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Color := ToColor(AColors.Surface);
  ParentBackground := False;
  if FHasDevelopment then
  begin
    ShowDevelopment(FDevelopment, FTrackerNote, FVcsNote);
  end
  else if FParts.Status <> nil then
  begin
    FParts.Status.Font.Color := ToColor(AColors.Muted);
  end;
end;

{ TAtlasIssueDevelopmentProbe }

class function TAtlasIssueDevelopmentProbe.StatusText(AView: TAtlasIssueDevelopmentView): string;
begin
  Result := '';
  if AView.Parts.Status <> nil then
  begin
    Result := AView.Parts.Status.Caption;
  end;
end;
class function TAtlasIssueDevelopmentProbe.UnitLines(AView: TAtlasIssueDevelopmentView): TArray<string>;
var
  mIndex: Integer;
  mNode: TTreeNode;
begin
  Result := nil;
  if AView.Parts.Units = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AView.Parts.Units.Items.Count - 1 do
  begin
    mNode := AView.Parts.Units.Items[mIndex];
    if mNode.Level = 0 then
    begin
      Result := Result + [mNode.Text];
    end
    else
    begin
      Result := Result + ['  ' + mNode.Text];
    end;
  end;
end;

{ TAtlasIssueDevelopmentView }
procedure TAtlasIssueDevelopmentView.BranchesSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FParts.Switch = nil then
  begin
    Exit;
  end;
  // Wechseln nur zu einem anderen als dem aktuellen Branch.
  FParts.Switch.Enabled := (FParts.Branches.Selected <> nil) and
    (FParts.Branches.Selected.Index <= High(FDevelopment.Branches)) and
    not FDevelopment.Branches[FParts.Branches.Selected.Index].Current;
end;

procedure TAtlasIssueDevelopmentView.SwitchClick(Sender: TObject);
begin
  if (FParts.Branches = nil) or (FParts.Branches.Selected = nil) or
    (FParts.Branches.Selected.Index > High(FDevelopment.Branches)) then
  begin
    Exit;
  end;
  if Assigned(FEvents.SwitchBranch) then
  begin
    FEvents.SwitchBranch(FDevelopment.Branches[FParts.Branches.Selected.Index]);
  end;
end;

function TAtlasIssueDevelopmentView.SelectedCommit(out AEntry: TAtlasVcsLogEntry): Boolean;
begin
  Result := (FParts.Commits <> nil) and (FParts.Commits.Selected <> nil) and
    (FParts.Commits.Selected.Index <= High(FDevelopment.Commits));
  if Result then
  begin
    AEntry := FDevelopment.Commits[FParts.Commits.Selected.Index];
  end
  else
  begin
    AEntry := Default(TAtlasVcsLogEntry);
  end;
end;

procedure TAtlasIssueDevelopmentView.CommitsClick(Sender: TObject);
begin
  if (FParts.Commits = nil) or (FParts.Commits.Selected = nil) then
  begin
    Exit;
  end;
  // Erst nach der Doppelklickzeit: Ein Doppelklick öffnet statt des Diffs.
  FPendingCommit := FParts.Commits.Selected.Index;
  FParts.CommitTimer.Enabled := False;
  FParts.CommitTimer.Enabled := True;
end;

procedure TAtlasIssueDevelopmentView.CommitTimerFired(Sender: TObject);
begin
  FParts.CommitTimer.Enabled := False;
  FireCommitClick;
end;

procedure TAtlasIssueDevelopmentView.FireCommitClick;
var
  mIndex: Integer;
begin
  FParts.CommitTimer.Enabled := False;
  mIndex := FPendingCommit;
  FPendingCommit := -1;
  if (mIndex < 0) or (mIndex > High(FDevelopment.Commits)) then
  begin
    Exit;
  end;
  if Assigned(FEvents.ShowDiff) then
  begin
    FEvents.ShowDiff(FDevelopment.Commits[mIndex]);
  end;
end;

procedure TAtlasIssueDevelopmentView.CommitsDblClick(Sender: TObject);
var
  mEntry: TAtlasVcsLogEntry;
begin
  FParts.CommitTimer.Enabled := False;
  FPendingCommit := -1;
  if SelectedCommit(mEntry) and Assigned(FEvents.OpenCommit) then
  begin
    FEvents.OpenCommit(mEntry);
  end;
end;

procedure TAtlasIssueDevelopmentView.CommitsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mEntry: TAtlasVcsLogEntry;
begin
  // Eingabe öffnet, Leertaste zeigt den Diff.
  if Key = VK_RETURN then
  begin
    CommitsDblClick(Sender);
    Key := 0;
  end
  else if (Key = VK_SPACE) and SelectedCommit(mEntry) then
  begin
    if Assigned(FEvents.ShowDiff) then
    begin
      FEvents.ShowDiff(mEntry);
    end;
    Key := 0;
  end;
end;

procedure TAtlasIssueDevelopmentView.PullsDblClick(Sender: TObject);
begin
  if (FParts.Pulls = nil) or (FParts.Pulls.Selected = nil) or
    (FParts.Pulls.Selected.Index > High(FDevelopment.Tracker.Pulls)) then
  begin
    Exit;
  end;
  if Assigned(FEvents.OpenPull) then
  begin
    FEvents.OpenPull(FDevelopment.Tracker.Pulls[FParts.Pulls.Selected.Index]);
  end;
end;

procedure TAtlasIssueDevelopmentView.UnitsClick(Sender: TObject);
var
  mIndex: NativeInt;
begin
  if (FParts.Units = nil) or (FParts.Units.Selected = nil) then
  begin
    Exit;
  end;
  mIndex := NativeInt(FParts.Units.Selected.Data);
  if (mIndex < 0) or (mIndex > High(FUnitList)) or FUnitList[mIndex].Deleted then
  begin
    Exit;
  end;
  if Assigned(FEvents.OpenUnit) then
  begin
    FEvents.OpenUnit(FUnitList[mIndex]);
  end;
end;

procedure TAtlasIssueDevelopmentView.UnitsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    UnitsClick(Sender);
    Key := 0;
  end;
end;

procedure TAtlasIssueDevelopmentView.ScrollWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
begin
  VertScrollBar.Position := VertScrollBar.Position - WheelDelta div 2;
  Handled := True;
end;

end.
