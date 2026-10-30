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
  Atlas.Core.Vcs.Contract;

type
  TAtlasIssueDevelopmentView = class(TScrollBox)
  private
    FParts: TList<TControl>;
    FNextTop: Integer;
    FColors: TAtlasColors;
    FDevelopment: TAtlasIssueDevelopment;
    FHasDevelopment: Boolean;
    FTrackerNote: string;
    FVcsNote: string;
    FStatus: TLabel;
    FBranches: TListView;
    FSwitch: TButton;
    FCommits: TListView;
    FPulls: TListView;
    FChanges: TListView;
    FUnits: TTreeView;
    FUnitList: TArray<TAtlasIssueUnit>;
    FCommitTimer: TTimer;
    FPendingCommit: Integer;
    FOnShowDiff: TProc<TAtlasVcsLogEntry>;
    FOnOpenCommit: TProc<TAtlasVcsLogEntry>;
    FOnSwitchBranch: TProc<TAtlasIssueBranch>;
    FOnOpenUnit: TProc<TAtlasIssueUnit>;
    FOnOpenPull: TProc<TAtlasTrackerPull>;
    procedure Place(AControl: TControl);
    function AddLabel(const ACaption: string; AHeading: Boolean): TLabel;
    function AddNote(const ACaption: string): TLabel;
    function AddList(const AColumns: TArray<string>; ARows: Integer): TListView;
    procedure Clear;
    procedure AddBranches;
    procedure AddCommits;
    procedure AddTracker(const ATrackerNote: string);
    procedure AddUnits;
    function VcsText: string;
    function WhenText(ATime: TDateTime): string;
    function UnitCaption(const AGroup: TAtlasIssueUnitGroup; const AUnit: TAtlasIssueUnit): string;
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
    /// <summary>Für Tests: Zeile über dem Inhalt bzw. die einzige Zeile.</summary>
    function StatusText: string;
    /// <summary>Für Tests: Beschriftungen der Units im Baum (Gruppe, dann Units eingerückt mit zwei Leerzeichen).
    /// </summary>
    function UnitLines: TArray<string>;
    property Development: TAtlasIssueDevelopment read FDevelopment;
    property HasDevelopment: Boolean read FHasDevelopment;
    property Branches: TListView read FBranches;
    property SwitchButton: TButton read FSwitch;
    property Commits: TListView read FCommits;
    property Pulls: TListView read FPulls;
    property Changes: TListView read FChanges;
    property Units: TTreeView read FUnits;
    property CommitTimer: TTimer read FCommitTimer;
    /// <summary>Klick auf einen Commit: Diff zeigen.</summary>
    property OnShowDiff: TProc<TAtlasVcsLogEntry> read FOnShowDiff write FOnShowDiff;
    /// <summary>Doppelklick bzw. Eingabe auf einen Commit: erste geänderte Unit an der Stelle öffnen.</summary>
    property OnOpenCommit: TProc<TAtlasVcsLogEntry> read FOnOpenCommit write FOnOpenCommit;
    property OnSwitchBranch: TProc<TAtlasIssueBranch> read FOnSwitchBranch write FOnSwitchBranch;
    property OnOpenUnit: TProc<TAtlasIssueUnit> read FOnOpenUnit write FOnOpenUnit;
    property OnOpenPull: TProc<TAtlasTrackerPull> read FOnOpenPull write FOnOpenPull;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.DateUtils,
  Vcl.Graphics,
  Atlas.Core.Style.Color,
  Atlas.UI.Strings;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasIssueDevelopmentView }

constructor TAtlasIssueDevelopmentView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FParts := TList<TControl>.Create;
  FColors := TAtlasColors.Light;
  FDevelopment := TAtlasIssueDevelopment.Empty;
  FPendingCommit := -1;
  BorderStyle := bsNone;
  VertScrollBar.Tracking := True;
  HorzScrollBar.Visible := False;
  Padding.SetBounds(8, 4, 8, 8);
  OnMouseWheel := ScrollWheel;
  FCommitTimer := TTimer.Create(Self);
  FCommitTimer.Enabled := False;
  FCommitTimer.Interval := GetDoubleClickTime;
  FCommitTimer.OnTimer := CommitTimerFired;
end;

destructor TAtlasIssueDevelopmentView.Destroy;
begin
  FCommitTimer.Enabled := False;
  FParts.Free;
  inherited;
end;

procedure TAtlasIssueDevelopmentView.Place(AControl: TControl);
begin
  // Untereinander in der Reihenfolge des Anlegens: alTop ordnet nach Top.
  Inc(FNextTop, 1000);
  AControl.Parent := Self;
  AControl.Align := alTop;
  AControl.AlignWithMargins := True;
  AControl.Top := FNextTop;
  FParts.Add(AControl);
end;

function TAtlasIssueDevelopmentView.AddLabel(const ACaption: string; AHeading: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Place(Result);
  Result.WordWrap := True;
  Result.ShowAccelChar := False;
  Result.Font.Color := ToColor(FColors.Text);
  if AHeading then
  begin
    Result.Caption := AnsiUpperCase(ACaption);
    Result.Font.Style := [fsBold];
    Result.Font.Color := ToColor(FColors.Muted);
  end
  else
    Result.Caption := ACaption;
end;

function TAtlasIssueDevelopmentView.AddNote(const ACaption: string): TLabel;
begin
  Result := AddLabel(ACaption, False);
  Result.Font.Color := ToColor(FColors.Muted);
end;

function TAtlasIssueDevelopmentView.AddList(const AColumns: TArray<string>; ARows: Integer): TListView;
var
  mCaption: string;
  mColumn: TListColumn;
begin
  Result := TListView.Create(Self);
  Place(Result);
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
  Result.Height := (Min(ARows, 12) + 2) * MulDiv(20, CurrentPPI, 96);
end;

procedure TAtlasIssueDevelopmentView.Clear;
var
  mIndex: Integer;
begin
  FCommitTimer.Enabled := False;
  FPendingCommit := -1;
  DisableAlign;
  try
    for mIndex := FParts.Count - 1 downto 0 do
      FParts[mIndex].Free;
    FParts.Clear;
    FStatus := nil;
    FBranches := nil;
    FSwitch := nil;
    FCommits := nil;
    FPulls := nil;
    FChanges := nil;
    FUnits := nil;
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
  FStatus := AddNote(TAtlasStrings.Text(TAtlasTextId.IssueDevLoading));
end;

procedure TAtlasIssueDevelopmentView.ShowNote(const AText: string);
begin
  FHasDevelopment := False;
  FDevelopment := TAtlasIssueDevelopment.Empty;
  Clear;
  FStatus := AddNote(AText);
end;

function TAtlasIssueDevelopmentView.WhenText(ATime: TDateTime): string;
begin
  Result := '';
  if ATime > 0 then
    Result := FormatDateTime('dd.mm.yyyy hh:nn', TTimeZone.Local.ToLocalTime(ATime));
end;

function TAtlasIssueDevelopmentView.VcsText: string;
begin
  case FDevelopment.VcsOutcome of
    TAtlasVcsOutcome.Ok, TAtlasVcsOutcome.Cancelled:
      Result := '';
    TAtlasVcsOutcome.NoWorkingCopy:
      Result := TAtlasStrings.Text(TAtlasTextId.IssueDevNoVcs);
    TAtlasVcsOutcome.Disabled:
      Result := TAtlasStrings.Text(TAtlasTextId.IssueDevVcsOff);
    TAtlasVcsOutcome.ToolMissing:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssueDevToolMissing, [AtlasVcsKindName(FDevelopment.VcsKind)]);
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.IssueDevVcsFailed, [AtlasVcsOutcomeName(FDevelopment.VcsOutcome)]);
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
      mVcs := VcsText;
    if mVcs <> '' then
      FStatus := AddNote(mVcs)
    else
    begin
      AddBranches;
      AddCommits;
    end;
    AddTracker(ATrackerNote);
    if mVcs = '' then
      AddUnits;
  finally
    EnableAlign;
  end;
  VertScrollBar.Position := 0;
end;

procedure TAtlasIssueDevelopmentView.AddBranches;
var
  mBranch: TAtlasIssueBranch;
  mItem: TListItem;
  mWhere, mState: string;
  mTools: TPanel;
begin
  AddLabel(TAtlasStrings.Fmt(TAtlasTextId.IssueDevBranches, [Length(FDevelopment.Branches)]), True);
  if Length(FDevelopment.Branches) = 0 then
  begin
    AddNote(TAtlasStrings.Fmt(TAtlasTextId.IssueDevNoBranch, [FDevelopment.Key]));
    Exit;
  end;
  FBranches := AddList(TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.IssueDevColumnBranch),
    TAtlasStrings.Text(TAtlasTextId.IssueDevColumnWhere), TAtlasStrings.Text(TAtlasTextId.IssueDevColumnState)),
    Length(FDevelopment.Branches));
  FBranches.Items.BeginUpdate;
  try
    for mBranch in FDevelopment.Branches do
    begin
      if mBranch.Local and mBranch.Remote then
        mWhere := TAtlasStrings.Text(TAtlasTextId.IssueDevLocalRemote)
      else if mBranch.Local then
        mWhere := TAtlasStrings.Text(TAtlasTextId.IssueDevLocal)
      else
        mWhere := TAtlasStrings.Text(TAtlasTextId.IssueDevRemote);
      mState := '';
      if (mBranch.Base <> '') and (mBranch.Ahead >= 0) and (mBranch.Behind >= 0) then
        mState := TAtlasStrings.Fmt(TAtlasTextId.IssueDevAheadBehind, [mBranch.Ahead, mBranch.Behind, mBranch.Base]);
      if mBranch.Current then
      begin
        if mState <> '' then
          mState := ', ' + mState;
        mState := TAtlasStrings.Text(TAtlasTextId.IssueDevCurrent) + mState;
      end;
      mItem := FBranches.Items.Add;
      mItem.Caption := mBranch.Name;
      mItem.SubItems.Add(mWhere);
      mItem.SubItems.Add(mState);
    end;
  finally
    FBranches.Items.EndUpdate;
  end;
  FBranches.OnSelectItem := BranchesSelect;
  mTools := TPanel.Create(Self);
  Place(mTools);
  mTools.BevelOuter := bvNone;
  mTools.ShowCaption := False;
  mTools.Height := MulDiv(30, CurrentPPI, 96);
  FSwitch := TButton.Create(Self);
  FSwitch.Parent := mTools;
  FSwitch.Align := alLeft;
  FSwitch.Caption := TAtlasStrings.Text(TAtlasTextId.IssueDevSwitch);
  FSwitch.Width := MulDiv(100, CurrentPPI, 96);
  FSwitch.Enabled := False;
  FSwitch.OnClick := SwitchClick;
end;

procedure TAtlasIssueDevelopmentView.AddCommits;
var
  mEntry: TAtlasVcsLogEntry;
  mItem: TListItem;
begin
  if FDevelopment.Truncated then
    AddLabel(TAtlasStrings.Fmt(TAtlasTextId.IssueDevCommitsMore, [Length(FDevelopment.Commits)]), True)
  else
    AddLabel(TAtlasStrings.Fmt(TAtlasTextId.IssueDevCommits, [Length(FDevelopment.Commits)]), True);
  if Length(FDevelopment.Commits) = 0 then
  begin
    AddNote(TAtlasStrings.Fmt(TAtlasTextId.IssueDevNoCommits, [FDevelopment.Key]));
    Exit;
  end;
  FCommits := AddList(TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.IssueDevColumnCommit),
    TAtlasStrings.Text(TAtlasTextId.IssueDevColumnSubject), TAtlasStrings.Text(TAtlasTextId.IssueDevColumnAuthor),
    TAtlasStrings.Text(TAtlasTextId.IssueDevColumnTime)), Length(FDevelopment.Commits));
  FCommits.Items.BeginUpdate;
  try
    for mEntry in FDevelopment.Commits do
    begin
      mItem := FCommits.Items.Add;
      mItem.Caption := mEntry.ShortRevision(FDevelopment.VcsKind);
      mItem.SubItems.Add(mEntry.Summary);
      mItem.SubItems.Add(mEntry.Author);
      mItem.SubItems.Add(WhenText(mEntry.Date));
    end;
  finally
    FCommits.Items.EndUpdate;
  end;
  FCommits.Hint := TAtlasStrings.Text(TAtlasTextId.IssueDevCommitHint);
  FCommits.ShowHint := True;
  FCommits.OnClick := CommitsClick;
  FCommits.OnDblClick := CommitsDblClick;
  FCommits.OnKeyDown := CommitsKeyDown;
  AddNote(TAtlasStrings.Text(TAtlasTextId.IssueDevCommitHint));
end;

procedure TAtlasIssueDevelopmentView.AddTracker(const ATrackerNote: string);
var
  mPull: TAtlasTrackerPull;
  mChange: TAtlasTrackerVcsChange;
  mItem: TListItem;
  mState, mChecks: string;
begin
  if ATrackerNote <> '' then
  begin
    AddNote(TAtlasStrings.Fmt(TAtlasTextId.IssueDevTrackerFailed, [ATrackerNote]));
    Exit;
  end;
  if not FDevelopment.TrackerLoaded then
    Exit;
  // YouTrack kennt keine Pull Requests, aber verknüpfte Änderungen.
  if Length(FDevelopment.Tracker.Changes) > 0 then
  begin
    AddLabel(TAtlasStrings.Fmt(TAtlasTextId.IssueDevTrackerChanges, [Length(FDevelopment.Tracker.Changes)]), True);
    FChanges := AddList(TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.IssueDevColumnCommit),
      TAtlasStrings.Text(TAtlasTextId.IssueDevColumnSubject), TAtlasStrings.Text(TAtlasTextId.IssueDevColumnAuthor),
      TAtlasStrings.Text(TAtlasTextId.IssueDevColumnTime)), Length(FDevelopment.Tracker.Changes));
    FChanges.Items.BeginUpdate;
    try
      for mChange in FDevelopment.Tracker.Changes do
      begin
        mItem := FChanges.Items.Add;
        mItem.Caption := Copy(mChange.Version, 1, 10);
        mItem.SubItems.Add(mChange.Text);
        mItem.SubItems.Add(mChange.Author);
        mItem.SubItems.Add(WhenText(mChange.Date));
      end;
    finally
      FChanges.Items.EndUpdate;
    end;
    if Length(FDevelopment.Tracker.Pulls) = 0 then
      Exit;
  end;
  AddLabel(TAtlasStrings.Fmt(TAtlasTextId.IssueDevPulls, [Length(FDevelopment.Tracker.Pulls)]), True);
  if Length(FDevelopment.Tracker.Pulls) = 0 then
  begin
    AddNote(TAtlasStrings.Fmt(TAtlasTextId.IssueDevNoPulls, [FDevelopment.Key]));
    Exit;
  end;
  FPulls := AddList(TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.IssueDevColumnNumber),
    TAtlasStrings.Text(TAtlasTextId.IssueDevColumnSubject), TAtlasStrings.Text(TAtlasTextId.IssueDevColumnState),
    TAtlasStrings.Text(TAtlasTextId.IssueDevColumnChecks)), Length(FDevelopment.Tracker.Pulls));
  FPulls.Items.BeginUpdate;
  try
    for mPull in FDevelopment.Tracker.Pulls do
    begin
      case mPull.State of
        TAtlasTrackerPullState.Draft:
          mState := TAtlasStrings.Text(TAtlasTextId.IssueDevPullDraft);
        TAtlasTrackerPullState.Merged:
          mState := TAtlasStrings.Text(TAtlasTextId.IssueDevPullMerged);
        TAtlasTrackerPullState.Closed:
          mState := TAtlasStrings.Text(TAtlasTextId.IssueDevPullClosed);
      else
        mState := TAtlasStrings.Text(TAtlasTextId.IssueDevPullOpen);
      end;
      case mPull.Checks of
        TAtlasTrackerChecks.Pending:
          mChecks := TAtlasStrings.Text(TAtlasTextId.IssueDevChecksPending);
        TAtlasTrackerChecks.Success:
          mChecks := TAtlasStrings.Text(TAtlasTextId.IssueDevChecksSuccess);
        TAtlasTrackerChecks.Failure:
          mChecks := TAtlasStrings.Text(TAtlasTextId.IssueDevChecksFailure);
      else
        mChecks := TAtlasStrings.Text(TAtlasTextId.IssueDevChecksUnknown);
      end;
      mItem := FPulls.Items.Add;
      mItem.Caption := '#' + IntToStr(mPull.Number);
      mItem.SubItems.Add(mPull.Title);
      mItem.SubItems.Add(mState);
      mItem.SubItems.Add(mChecks);
    end;
  finally
    FPulls.Items.EndUpdate;
  end;
  FPulls.OnDblClick := PullsDblClick;
end;

function TAtlasIssueDevelopmentView.UnitCaption(const AGroup: TAtlasIssueUnitGroup;
  const AUnit: TAtlasIssueUnit): string;
var
  mFolder: string;
begin
  // Unter dem Projektordner relativ, sonst vollständig.
  Result := AUnit.Path;
  if AGroup.ProjectFile <> '' then
  begin
    mFolder := IncludeTrailingPathDelimiter(ExtractFilePath(AGroup.ProjectFile));
    if SameText(Copy(AUnit.Path, 1, Length(mFolder)), mFolder) then
      Result := Copy(AUnit.Path, Length(mFolder) + 1, MaxInt);
  end;
  if AUnit.Deleted then
    Result := TAtlasStrings.Fmt(TAtlasTextId.IssueDevDeleted, [Result]);
end;

procedure TAtlasIssueDevelopmentView.AddUnits;
var
  mGroup: TAtlasIssueUnitGroup;
  mUnit: TAtlasIssueUnit;
  mNode: TTreeNode;
  mCaption: string;
  mRows: Integer;
begin
  AddLabel(TAtlasStrings.Fmt(TAtlasTextId.IssueDevUnits, [FDevelopment.UnitCount]), True);
  if FDevelopment.UnitCount = 0 then
  begin
    AddNote(TAtlasStrings.Text(TAtlasTextId.IssueDevNoUnits));
    Exit;
  end;
  FUnits := TTreeView.Create(Self);
  Place(FUnits);
  FUnits.ReadOnly := True;
  FUnits.HideSelection := False;
  FUnits.ShowRoot := True;
  mRows := 0;
  FUnits.Items.BeginUpdate;
  try
    for mGroup in FDevelopment.Units do
    begin
      mCaption := mGroup.Project;
      if mCaption = '' then
        mCaption := TAtlasStrings.Text(TAtlasTextId.IssueDevOtherFiles);
      mNode := FUnits.Items.AddChildObject(nil, Format('%s (%d)', [mCaption, Length(mGroup.Units)]), Pointer(-1));
      Inc(mRows);
      for mUnit in mGroup.Units do
      begin
        FUnitList := FUnitList + [mUnit];
        FUnits.Items.AddChildObject(mNode, UnitCaption(mGroup, mUnit), Pointer(NativeInt(High(FUnitList))));
        Inc(mRows);
      end;
      mNode.Expand(False);
    end;
  finally
    FUnits.Items.EndUpdate;
  end;
  FUnits.Height := (Min(mRows, 20) + 1) * MulDiv(19, CurrentPPI, 96);
  FUnits.OnClick := UnitsClick;
  FUnits.OnKeyDown := UnitsKeyDown;
end;

procedure TAtlasIssueDevelopmentView.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Color := ToColor(AColors.Surface);
  ParentBackground := False;
  if FHasDevelopment then
    ShowDevelopment(FDevelopment, FTrackerNote, FVcsNote)
  else if FStatus <> nil then
    FStatus.Font.Color := ToColor(AColors.Muted);
end;

function TAtlasIssueDevelopmentView.StatusText: string;
begin
  Result := '';
  if FStatus <> nil then
    Result := FStatus.Caption;
end;

function TAtlasIssueDevelopmentView.UnitLines: TArray<string>;
var
  mIndex: Integer;
  mNode: TTreeNode;
begin
  Result := nil;
  if FUnits = nil then
    Exit;
  for mIndex := 0 to FUnits.Items.Count - 1 do
  begin
    mNode := FUnits.Items[mIndex];
    if mNode.Level = 0 then
      Result := Result + [mNode.Text]
    else
      Result := Result + ['  ' + mNode.Text];
  end;
end;

procedure TAtlasIssueDevelopmentView.BranchesSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FSwitch = nil then
    Exit;
  // Wechseln nur zu einem anderen als dem aktuellen Branch.
  FSwitch.Enabled := (FBranches.Selected <> nil) and (FBranches.Selected.Index <= High(FDevelopment.Branches)) and
    not FDevelopment.Branches[FBranches.Selected.Index].Current;
end;

procedure TAtlasIssueDevelopmentView.SwitchClick(Sender: TObject);
begin
  if (FBranches = nil) or (FBranches.Selected = nil) or (FBranches.Selected.Index > High(FDevelopment.Branches)) then
    Exit;
  if Assigned(FOnSwitchBranch) then
    FOnSwitchBranch(FDevelopment.Branches[FBranches.Selected.Index]);
end;

function TAtlasIssueDevelopmentView.SelectedCommit(out AEntry: TAtlasVcsLogEntry): Boolean;
begin
  Result := (FCommits <> nil) and (FCommits.Selected <> nil) and
    (FCommits.Selected.Index <= High(FDevelopment.Commits));
  if Result then
    AEntry := FDevelopment.Commits[FCommits.Selected.Index]
  else
    AEntry := Default(TAtlasVcsLogEntry);
end;

procedure TAtlasIssueDevelopmentView.CommitsClick(Sender: TObject);
begin
  if (FCommits = nil) or (FCommits.Selected = nil) then
    Exit;
  // Erst nach der Doppelklickzeit: Ein Doppelklick öffnet statt des Diffs.
  FPendingCommit := FCommits.Selected.Index;
  FCommitTimer.Enabled := False;
  FCommitTimer.Enabled := True;
end;

procedure TAtlasIssueDevelopmentView.CommitTimerFired(Sender: TObject);
begin
  FCommitTimer.Enabled := False;
  FireCommitClick;
end;

procedure TAtlasIssueDevelopmentView.FireCommitClick;
var
  mIndex: Integer;
begin
  FCommitTimer.Enabled := False;
  mIndex := FPendingCommit;
  FPendingCommit := -1;
  if (mIndex < 0) or (mIndex > High(FDevelopment.Commits)) then
    Exit;
  if Assigned(FOnShowDiff) then
    FOnShowDiff(FDevelopment.Commits[mIndex]);
end;

procedure TAtlasIssueDevelopmentView.CommitsDblClick(Sender: TObject);
var
  mEntry: TAtlasVcsLogEntry;
begin
  FCommitTimer.Enabled := False;
  FPendingCommit := -1;
  if SelectedCommit(mEntry) and Assigned(FOnOpenCommit) then
    FOnOpenCommit(mEntry);
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
    if Assigned(FOnShowDiff) then
      FOnShowDiff(mEntry);
    Key := 0;
  end;
end;

procedure TAtlasIssueDevelopmentView.PullsDblClick(Sender: TObject);
begin
  if (FPulls = nil) or (FPulls.Selected = nil) or (FPulls.Selected.Index > High(FDevelopment.Tracker.Pulls)) then
    Exit;
  if Assigned(FOnOpenPull) then
    FOnOpenPull(FDevelopment.Tracker.Pulls[FPulls.Selected.Index]);
end;

procedure TAtlasIssueDevelopmentView.UnitsClick(Sender: TObject);
var
  mIndex: NativeInt;
begin
  if (FUnits = nil) or (FUnits.Selected = nil) then
    Exit;
  mIndex := NativeInt(FUnits.Selected.Data);
  if (mIndex < 0) or (mIndex > High(FUnitList)) or FUnitList[mIndex].Deleted then
    Exit;
  if Assigned(FOnOpenUnit) then
    FOnOpenUnit(FUnitList[mIndex]);
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
