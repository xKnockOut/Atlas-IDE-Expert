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
  Atlas.UI.Tracker.Strings;

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
  if FCommitTimer <> nil then
  begin
    FCommitTimer.Enabled := False;
  end;
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
  begin
    Result.Caption := ACaption;
  end;
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
    begin
      FParts[mIndex].Free;
    end;
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
  FStatus := AddNote(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevLoading));
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
  begin
    Result := FormatDateTime('dd.mm.yyyy hh:nn', TTimeZone.Local.ToLocalTime(ATime));
  end;
end;

function TAtlasIssueDevelopmentView.VcsText: string;
begin
  case FDevelopment.VcsOutcome of
    TAtlasVcsOutcome.Ok, TAtlasVcsOutcome.Cancelled:
      Result := '';
    TAtlasVcsOutcome.NoWorkingCopy:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevNoVcs);
    TAtlasVcsOutcome.Disabled:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevVcsOff);
    TAtlasVcsOutcome.ToolMissing:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevToolMissing,
        [AtlasVcsKindName(FDevelopment.VcsKind)]);
  else
    Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevVcsFailed,
      [AtlasVcsOutcomeName(FDevelopment.VcsOutcome)]);
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
      mVcs := VcsText;
    end;
    if mVcs <> '' then
    begin
      FStatus := AddNote(mVcs);
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

procedure TAtlasIssueDevelopmentView.AddBranches;
var
  mBranch: TAtlasIssueBranch;
  mItem: TListItem;
  mWhere, mState: string;
  mTools: TPanel;
begin
  AddLabel(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevBranches, [Length(FDevelopment.Branches)]), True);
  if Length(FDevelopment.Branches) = 0 then
  begin
    AddNote(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevNoBranch, [FDevelopment.Key]));
    Exit;
  end;
  FBranches := AddList(TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnBranch),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnWhere),
      TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnState)),
    Length(FDevelopment.Branches));
  FBranches.Items.BeginUpdate;
  try
    for mBranch in FDevelopment.Branches do
    begin
      if mBranch.Local and mBranch.Remote then
      begin
        mWhere := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevLocalRemote);
      end
      else if mBranch.Local then
      begin
        mWhere := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevLocal);
      end
      else
      begin
        mWhere := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevRemote);
      end;
      mState := '';
      if (mBranch.Base <> '') and (mBranch.Ahead >= 0) and (mBranch.Behind >= 0) then
      begin
        mState := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevAheadBehind,
          [mBranch.Ahead, mBranch.Behind, mBranch.Base]);
      end;
      if mBranch.Current then
      begin
        if mState <> '' then
        begin
          mState := ', ' + mState;
        end;
        mState := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevCurrent) + mState;
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
  FSwitch.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevSwitch);
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
  begin
    AddLabel(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevCommitsMore, [Length(FDevelopment.Commits)]), True);
  end
  else
  begin
    AddLabel(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevCommits, [Length(FDevelopment.Commits)]), True);
  end;
  if Length(FDevelopment.Commits) = 0 then
  begin
    AddNote(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevNoCommits, [FDevelopment.Key]));
    Exit;
  end;
  FCommits := AddList(TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnCommit),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnSubject),
      TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnAuthor),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnTime)), Length(FDevelopment.Commits));
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
  FCommits.Hint := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevCommitHint);
  FCommits.ShowHint := True;
  FCommits.OnClick := CommitsClick;
  FCommits.OnDblClick := CommitsDblClick;
  FCommits.OnKeyDown := CommitsKeyDown;
  AddNote(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevCommitHint));
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
    AddNote(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevTrackerFailed, [ATrackerNote]));
    Exit;
  end;
  if not FDevelopment.TrackerLoaded then
  begin
    Exit;
  end;
  // YouTrack kennt keine Pull Requests, aber verknüpfte Änderungen.
  if Length(FDevelopment.Tracker.Changes) > 0 then
  begin
    AddLabel(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevTrackerChanges,
      [Length(FDevelopment.Tracker.Changes)]), True);
    FChanges := AddList(TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnCommit),
      TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnSubject),
        TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnAuthor),
      TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnTime)), Length(FDevelopment.Tracker.Changes));
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
    begin
      Exit;
    end;
  end;
  AddLabel(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevPulls, [Length(FDevelopment.Tracker.Pulls)]), True);
  if Length(FDevelopment.Tracker.Pulls) = 0 then
  begin
    AddNote(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevNoPulls, [FDevelopment.Key]));
    Exit;
  end;
  FPulls := AddList(TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnNumber),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnSubject),
      TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnState),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevColumnChecks)), Length(FDevelopment.Tracker.Pulls));
  FPulls.Items.BeginUpdate;
  try
    for mPull in FDevelopment.Tracker.Pulls do
    begin
      case mPull.State of
        TAtlasTrackerPullState.Draft:
          mState := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevPullDraft);
        TAtlasTrackerPullState.Merged:
          mState := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevPullMerged);
        TAtlasTrackerPullState.Closed:
          mState := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevPullClosed);
      else
        mState := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevPullOpen);
      end;
      case mPull.Checks of
        TAtlasTrackerChecks.Pending:
          mChecks := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevChecksPending);
        TAtlasTrackerChecks.Success:
          mChecks := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevChecksSuccess);
        TAtlasTrackerChecks.Failure:
          mChecks := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevChecksFailure);
      else
        mChecks := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevChecksUnknown);
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
    begin
      Result := Copy(AUnit.Path, Length(mFolder) + 1, MaxInt);
    end;
  end;
  if AUnit.Deleted then
  begin
    Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevDeleted, [Result]);
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
  AddLabel(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevUnits, [FDevelopment.UnitCount]), True);
  if FDevelopment.UnitCount = 0 then
  begin
    AddNote(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevNoUnits));
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
      begin
        mCaption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevOtherFiles);
      end;
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
  begin
    ShowDevelopment(FDevelopment, FTrackerNote, FVcsNote);
  end
  else if FStatus <> nil then
  begin
    FStatus.Font.Color := ToColor(AColors.Muted);
  end;
end;

function TAtlasIssueDevelopmentView.StatusText: string;
begin
  Result := '';
  if FStatus <> nil then
  begin
    Result := FStatus.Caption;
  end;
end;

function TAtlasIssueDevelopmentView.UnitLines: TArray<string>;
var
  mIndex: Integer;
  mNode: TTreeNode;
begin
  Result := nil;
  if FUnits = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to FUnits.Items.Count - 1 do
  begin
    mNode := FUnits.Items[mIndex];
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

procedure TAtlasIssueDevelopmentView.BranchesSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FSwitch = nil then
  begin
    Exit;
  end;
  // Wechseln nur zu einem anderen als dem aktuellen Branch.
  FSwitch.Enabled := (FBranches.Selected <> nil) and (FBranches.Selected.Index <= High(FDevelopment.Branches)) and
    not FDevelopment.Branches[FBranches.Selected.Index].Current;
end;

procedure TAtlasIssueDevelopmentView.SwitchClick(Sender: TObject);
begin
  if (FBranches = nil) or (FBranches.Selected = nil) or (FBranches.Selected.Index > High(FDevelopment.Branches)) then
  begin
    Exit;
  end;
  if Assigned(FOnSwitchBranch) then
  begin
    FOnSwitchBranch(FDevelopment.Branches[FBranches.Selected.Index]);
  end;
end;

function TAtlasIssueDevelopmentView.SelectedCommit(out AEntry: TAtlasVcsLogEntry): Boolean;
begin
  Result := (FCommits <> nil) and (FCommits.Selected <> nil) and
    (FCommits.Selected.Index <= High(FDevelopment.Commits));
  if Result then
  begin
    AEntry := FDevelopment.Commits[FCommits.Selected.Index];
  end
  else
  begin
    AEntry := Default(TAtlasVcsLogEntry);
  end;
end;

procedure TAtlasIssueDevelopmentView.CommitsClick(Sender: TObject);
begin
  if (FCommits = nil) or (FCommits.Selected = nil) then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  if Assigned(FOnShowDiff) then
  begin
    FOnShowDiff(FDevelopment.Commits[mIndex]);
  end;
end;

procedure TAtlasIssueDevelopmentView.CommitsDblClick(Sender: TObject);
var
  mEntry: TAtlasVcsLogEntry;
begin
  FCommitTimer.Enabled := False;
  FPendingCommit := -1;
  if SelectedCommit(mEntry) and Assigned(FOnOpenCommit) then
  begin
    FOnOpenCommit(mEntry);
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
    if Assigned(FOnShowDiff) then
    begin
      FOnShowDiff(mEntry);
    end;
    Key := 0;
  end;
end;

procedure TAtlasIssueDevelopmentView.PullsDblClick(Sender: TObject);
begin
  if (FPulls = nil) or (FPulls.Selected = nil) or (FPulls.Selected.Index > High(FDevelopment.Tracker.Pulls)) then
  begin
    Exit;
  end;
  if Assigned(FOnOpenPull) then
  begin
    FOnOpenPull(FDevelopment.Tracker.Pulls[FPulls.Selected.Index]);
  end;
end;

procedure TAtlasIssueDevelopmentView.UnitsClick(Sender: TObject);
var
  mIndex: NativeInt;
begin
  if (FUnits = nil) or (FUnits.Selected = nil) then
  begin
    Exit;
  end;
  mIndex := NativeInt(FUnits.Selected.Data);
  if (mIndex < 0) or (mIndex > High(FUnitList)) or FUnitList[mIndex].Deleted then
  begin
    Exit;
  end;
  if Assigned(FOnOpenUnit) then
  begin
    FOnOpenUnit(FUnitList[mIndex]);
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
