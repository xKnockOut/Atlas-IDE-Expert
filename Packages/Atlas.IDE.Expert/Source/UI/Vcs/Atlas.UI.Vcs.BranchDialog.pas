unit Atlas.UI.Vcs.BranchDialog;

// Dialog „Branch anlegen“ (#1288): Name, Basis, (SVN) Nachricht und unter
// „Was passiert“ die Schritte in Klartext, genau so, wie Atlas sie danach
// ausführt (TAtlasVcsBranchPlan). Jede Änderung baut die Liste neu; Schritte,
// die den Server ändern, tragen den Zusatz „auf dem Server“. Ein ungültiger
// Name (TAtlasTrackerNaming.ValidBranchName) sperrt „Anlegen“ mit Hinweis
// unter dem Feld. Braucht der Plan Werte vom Server (SVN: HEAD-Revision),
// steht „wird ermittelt …“ und „Anlegen“ bleibt gesperrt, bis die IDE-Schicht
// Loaded aufruft. „Nicht mehr fragen, Vorgaben verwenden“ nur bei „Beginnen“
// (vcs.branch.confirm). Ausgeführt wird nicht hier: Der Aufrufer nimmt Request.
// Gruppe „Git“ (#1289) direkt unter der Basis, vorbelegt aus vcs.branch.git.*:
// vorher abrufen (nur mit Basis <Remote>/<Hauptbranch>), auf den Server
// (später/sofort), offene Änderungen (nur mit geänderten Dateien und ohne
// worktree; „nachfragen“ lässt die Auswahl leer und sperrt „Anlegen“, bis
// gewählt ist) und Ablage (umschalten/eigener Ordner). Der Ordner folgt dem
// Namen, bis er von Hand geändert wird; gibt es ihn schon, sperrt ein Hinweis
// „Anlegen“.
// Die Optionen aus #1290 und die Gruppe Externals aus #1291 kommen als
// weitere Zeilen dazu; bis dahin zeigt der Dialog bei svn:externals nur einen
// Hinweis.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.BranchPlan;

type
  TAtlasBranchDialog = class(TForm)
  private
    FFacts: TAtlasVcsBranchFacts;
    FBases: TArray<TAtlasVcsBranchBase>;
    FSteps: TArray<TAtlasVcsBranchStep>;
    FNameEdit: TEdit;
    FNameError: TLabel;
    FBaseBox: TComboBox;
    FMessagePanel: TPanel;
    FMessageEdit: TEdit;
    FInfoLabel: TLabel;
    FExternalsBox: TGroupBox;
    FStepsMemo: TMemo;
    FServerHint: TLabel;
    FNeverAsk: TCheckBox;
    FCreateButton: TButton;
    FFilling: Boolean;
    FKey: string;
    FGitOptions: TAtlasVcsGitBranchOptions;
    FGitBox: TGroupBox;
    FFetchCheck: TCheckBox;
    FPushBox: TComboBox;
    FUncommittedPanel: TPanel;
    FUncommittedBox: TComboBox;
    FUncommittedCount: TLabel;
    FPlaceBox: TComboBox;
    FFolderPanel: TPanel;
    FFolderEdit: TEdit;
    FGitError: TLabel;
    FFolderEdited: Boolean;
    function Row(const ACaption: string; AHeight: Integer): TPanel; overload;
    function Row(AParent: TWinControl; const ACaption: string; AHeight: Integer): TPanel; overload;
    procedure AddGitGroup;
    procedure UpdateGit;
    /// <summary>Zeile einblenden bzw. ausblenden; eingeblendet direkt unter AAfter (alTop ordnet nach Top).
    /// </summary>
    procedure ShowRow(ARow, AAfter: TControl; AVisible: Boolean);
    procedure FolderChanged(Sender: TObject);
    function GitState(out AText: string): Boolean;
    function SelectedBase: TAtlasVcsBranchBase;
    procedure Stack(AControl: TControl);
    procedure FillBases(APreferred: TAtlasVcsBranchBaseKind);
    procedure Changed(Sender: TObject);
    procedure CreateClick(Sender: TObject);
    function NameState(out AText: string): Boolean;
  public
    /// <summary>AFacts aus TAtlasVcsBranchPlan.Inspect; AName und AMessage vorbelegt ('' ohne Issue);
    /// AOfferNeverAsk zeigt „Nicht mehr fragen, Vorgaben verwenden“.</summary>
    constructor CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts; const AName, AMessage: string;
      AOfferNeverAsk: Boolean); overload;
    /// <summary>Wie oben mit den Git-Vorgaben (#1289) und der Kennung des Issues für {kennung} im
    /// worktree-Ordner ('' ohne Issue).</summary>
    constructor CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts; const AName, AMessage,
      AKey: string; const AGitOptions: TAtlasVcsGitBranchOptions; AOfferNeverAsk: Boolean); overload;
    /// <summary>Werte vom Server sind da (InspectServer): Basen neu, „Anlegen“ frei, wenn der Rest stimmt.
    /// </summary>
    procedure Loaded(const AFacts: TAtlasVcsBranchFacts);
    /// <summary>Gewählte Werte.</summary>
    function Request: TAtlasVcsBranchRequest;
    /// <summary>Name gültig, Basis gewählt, nichts mehr zu ermitteln.</summary>
    function CanCreate: Boolean;
    /// <summary>Text einer Basis in der Auswahl.</summary>
    class function BaseCaption(AKind: TAtlasVcsKind; const ABase: TAtlasVcsBranchBase): string; static;
    /// <summary>Zeilen für „Was passiert“: nummeriert, Serverschritte mit Zusatz.</summary>
    class function StepLines(AKind: TAtlasVcsKind; const ASteps: TArray<TAtlasVcsBranchStep>): TArray<string>;
      static;
    property Facts: TAtlasVcsBranchFacts read FFacts;
    property NameEdit: TEdit read FNameEdit;
    property NameError: TLabel read FNameError;
    property BaseBox: TComboBox read FBaseBox;
    property MessageEdit: TEdit read FMessageEdit;
    property MessagePanel: TPanel read FMessagePanel;
    property InfoLabel: TLabel read FInfoLabel;
    property ExternalsBox: TGroupBox read FExternalsBox;
    property StepsMemo: TMemo read FStepsMemo;
    property ServerHint: TLabel read FServerHint;
    property NeverAsk: TCheckBox read FNeverAsk;
    property CreateButton: TButton read FCreateButton;
    /// <summary>Gruppe „Git“ (#1289), nur unter Git sichtbar.</summary>
    property GitBox: TGroupBox read FGitBox;
    property FetchCheck: TCheckBox read FFetchCheck;
    /// <summary>0 beim ersten Push, 1 sofort.</summary>
    property PushBox: TComboBox read FPushBox;
    property UncommittedPanel: TPanel read FUncommittedPanel;
    /// <summary>0 mitnehmen, 1 beiseitelegen, -1 noch nicht gewählt.</summary>
    property UncommittedBox: TComboBox read FUncommittedBox;
    property UncommittedCount: TLabel read FUncommittedCount;
    /// <summary>0 umschalten, 1 eigener Ordner.</summary>
    property PlaceBox: TComboBox read FPlaceBox;
    property FolderPanel: TPanel read FFolderPanel;
    property FolderEdit: TEdit read FFolderEdit;
    property GitError: TLabel read FGitError;
  end;

implementation

uses
  Atlas.Core.Tracker.Naming,
  Atlas.UI.Strings;

const
  cGap = 8;
  cCaptionWidth = 96;
  cButtonWidth = 100;
  cBelowAll = 10000;

constructor TAtlasBranchDialog.CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts;
  const AName, AMessage: string; AOfferNeverAsk: Boolean);
begin
  CreateDialog(AOwner, AFacts, AName, AMessage, '', TAtlasVcsGitBranchOptions.Classic, AOfferNeverAsk);
end;

constructor TAtlasBranchDialog.CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts;
  const AName, AMessage, AKey: string; const AGitOptions: TAtlasVcsGitBranchOptions; AOfferNeverAsk: Boolean);
var
  mPanel, mBottom: TPanel;
  mSteps: TGroupBox;
  mExternals: TLabel;
  mCancel: TButton;
  mBase: TAtlasVcsBranchBase;
  mPreferred: TAtlasVcsBranchBaseKind;
begin
  inherited CreateNew(AOwner);
  FFacts := AFacts;
  FKey := AKey;
  FGitOptions := AGitOptions;
  FFilling := True;
  Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchTitle);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Width := 720;
  Height := 520;
  Constraints.MinWidth := 520;
  Constraints.MinHeight := 420;

  // Unten zuerst: die Knöpfe bleiben beim Verkleinern sichtbar.
  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := 44;
  mBottom.BevelOuter := bvNone;
  FNeverAsk := TCheckBox.Create(Self);
  FNeverAsk.Parent := mBottom;
  FNeverAsk.SetBounds(cGap, 12, 360, 20);
  FNeverAsk.Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchNeverAsk);
  FNeverAsk.Visible := AOfferNeverAsk;
  FCreateButton := TButton.Create(Self);
  FCreateButton.Parent := mBottom;
  FCreateButton.SetBounds(mBottom.Width - 2 * (cButtonWidth + cGap), 8, cButtonWidth, 28);
  FCreateButton.Anchors := [akTop, akRight];
  FCreateButton.Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchCreate);
  FCreateButton.Default := True;
  FCreateButton.OnClick := CreateClick;
  mCancel := TButton.Create(Self);
  mCancel.Parent := mBottom;
  mCancel.SetBounds(mBottom.Width - (cButtonWidth + cGap), 8, cButtonWidth, 28);
  mCancel.Anchors := [akTop, akRight];
  mCancel.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCancel);
  mCancel.Cancel := True;
  mCancel.ModalResult := mrCancel;

  mPanel := Row(TAtlasStrings.Text(TAtlasTextId.VcsBranchName), 28);
  FNameEdit := TEdit.Create(Self);
  FNameEdit.Parent := mPanel;
  FNameEdit.SetBounds(cCaptionWidth + cGap, 2, mPanel.Width - cCaptionWidth - 2 * cGap, 23);
  FNameEdit.Anchors := [akLeft, akTop, akRight];
  FNameEdit.Text := AName;
  FNameEdit.OnChange := Changed;
  FNameError := TLabel.Create(Self);
  FNameError.Parent := Self;
  Stack(FNameError);
  FNameError.AlignWithMargins := True;
  FNameError.Margins.SetBounds(cCaptionWidth + 2 * cGap, 0, cGap, 2);
  FNameError.Font.Color := clRed;
  FNameError.WordWrap := True;

  mPanel := Row(TAtlasStrings.Text(TAtlasTextId.VcsBranchBase), 28);
  FBaseBox := TComboBox.Create(Self);
  FBaseBox.Parent := mPanel;
  FBaseBox.Style := csDropDownList;
  FBaseBox.SetBounds(cCaptionWidth + cGap, 2, mPanel.Width - cCaptionWidth - 2 * cGap, 23);
  FBaseBox.Anchors := [akLeft, akTop, akRight];
  FBaseBox.OnChange := Changed;

  // Git-Optionen (#1289) gehören zur Basis: direkt darunter.
  AddGitGroup;
  if FGitBox.Visible then
  begin
    Height := Height + 176;
    Constraints.MinHeight := Constraints.MinHeight + 176;
  end;

  FMessagePanel := Row(TAtlasStrings.Text(TAtlasTextId.VcsBranchMessage), 28);
  FMessageEdit := TEdit.Create(Self);
  FMessageEdit.Parent := FMessagePanel;
  FMessageEdit.SetBounds(cCaptionWidth + cGap, 2, FMessagePanel.Width - cCaptionWidth - 2 * cGap, 23);
  FMessageEdit.Anchors := [akLeft, akTop, akRight];
  FMessageEdit.Text := AMessage;
  FMessageEdit.OnChange := Changed;
  // Nur svn copy hat eine Nachricht.
  FMessagePanel.Visible := AFacts.Kind = TAtlasVcsKind.Svn;

  FInfoLabel := TLabel.Create(Self);
  FInfoLabel.Parent := Self;
  Stack(FInfoLabel);
  FInfoLabel.AlignWithMargins := True;
  FInfoLabel.Margins.SetBounds(cCaptionWidth + 2 * cGap, 2, cGap, 4);
  FInfoLabel.WordWrap := True;

  FExternalsBox := TGroupBox.Create(Self);
  FExternalsBox.Parent := Self;
  Stack(FExternalsBox);
  FExternalsBox.AlignWithMargins := True;
  FExternalsBox.Margins.SetBounds(cGap, 4, cGap, 4);
  FExternalsBox.Height := 56;
  FExternalsBox.Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchExternals);
  mExternals := TLabel.Create(Self);
  mExternals.Parent := FExternalsBox;
  mExternals.Align := alClient;
  mExternals.AlignWithMargins := True;
  mExternals.WordWrap := True;
  mExternals.Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchExternalsKept);
  FExternalsBox.Visible := (AFacts.Kind = TAtlasVcsKind.Svn) and AFacts.Externals;

  mSteps := TGroupBox.Create(Self);
  mSteps.Parent := Self;
  mSteps.Align := alClient;
  mSteps.AlignWithMargins := True;
  mSteps.Margins.SetBounds(cGap, 4, cGap, 0);
  mSteps.Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchWhatHappens);
  FServerHint := TLabel.Create(Self);
  FServerHint.Parent := mSteps;
  FServerHint.Align := alBottom;
  FServerHint.AlignWithMargins := True;
  FServerHint.WordWrap := True;
  FServerHint.Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchServerHint);
  FStepsMemo := TMemo.Create(Self);
  FStepsMemo.Parent := mSteps;
  FStepsMemo.Align := alClient;
  FStepsMemo.AlignWithMargins := True;
  FStepsMemo.ReadOnly := True;
  FStepsMemo.ScrollBars := ssBoth;
  FStepsMemo.WordWrap := False;
  FStepsMemo.Font.Name := 'Consolas';
  FStepsMemo.Font.Size := 9;

  mPreferred := TAtlasVcsBranchBaseKind.Current;
  if TAtlasVcsBranchPlan.DefaultBase(AFacts, AGitOptions, mBase) then
    mPreferred := mBase.Kind;
  FFilling := False;
  FillBases(mPreferred);
end;

function TAtlasBranchDialog.Row(const ACaption: string; AHeight: Integer): TPanel;
begin
  Result := Row(Self, ACaption, AHeight);
end;

function TAtlasBranchDialog.Row(AParent: TWinControl; const ACaption: string; AHeight: Integer): TPanel;
var
  mCaption: TLabel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := AParent;
  Result.Height := AHeight;
  Result.BevelOuter := bvNone;
  Stack(Result);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(cGap, cGap div 2, cGap, 0);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := Result;
  mCaption.SetBounds(0, 5, cCaptionWidth, 17);
  mCaption.Caption := ACaption;
end;

procedure TAtlasBranchDialog.AddGitGroup;
var
  mPanel: TPanel;
  mWidth: Integer;
begin
  FGitBox := TGroupBox.Create(Self);
  FGitBox.Parent := Self;
  Stack(FGitBox);
  FGitBox.AlignWithMargins := True;
  FGitBox.Margins.SetBounds(cGap, 4, cGap, 4);
  FGitBox.Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchGit);
  FGitBox.Height := 120;
  FGitBox.Visible := FFacts.Kind = TAtlasVcsKind.Git;

  mPanel := Row(FGitBox, '', 24);
  FFetchCheck := TCheckBox.Create(Self);
  FFetchCheck.Parent := mPanel;
  FFetchCheck.SetBounds(cCaptionWidth + cGap, 3, mPanel.Width - cCaptionWidth - 2 * cGap, 20);
  FFetchCheck.Anchors := [akLeft, akTop, akRight];
  FFetchCheck.Checked := FGitOptions.Base = TAtlasVcsGitBaseOption.Remote;
  FFetchCheck.OnClick := Changed;

  mPanel := Row(FGitBox, TAtlasStrings.Text(TAtlasTextId.VcsBranchPush), 28);
  FPushBox := TComboBox.Create(Self);
  FPushBox.Parent := mPanel;
  FPushBox.Style := csDropDownList;
  FPushBox.SetBounds(cCaptionWidth + cGap, 2, mPanel.Width - cCaptionWidth - 2 * cGap, 23);
  FPushBox.Anchors := [akLeft, akTop, akRight];
  FPushBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.VcsBranchPushLater));
  FPushBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.VcsBranchPushNow));
  if FGitOptions.PushNow then
    FPushBox.ItemIndex := 1
  else
    FPushBox.ItemIndex := 0;
  FPushBox.OnChange := Changed;

  // Offene Änderungen: nur mit geänderten Dateien; „nachfragen“ lässt die Auswahl leer.
  FUncommittedPanel := Row(FGitBox, TAtlasStrings.Text(TAtlasTextId.VcsBranchUncommitted), 28);
  mWidth := 240;
  FUncommittedBox := TComboBox.Create(Self);
  FUncommittedBox.Parent := FUncommittedPanel;
  FUncommittedBox.Style := csDropDownList;
  FUncommittedBox.SetBounds(cCaptionWidth + cGap, 2, mWidth, 23);
  FUncommittedBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.VcsBranchCarry));
  FUncommittedBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.VcsBranchStash));
  case FGitOptions.Uncommitted of
    TAtlasVcsGitUncommitted.Carry:
      FUncommittedBox.ItemIndex := 0;
    TAtlasVcsGitUncommitted.Stash:
      FUncommittedBox.ItemIndex := 1;
  else
    FUncommittedBox.ItemIndex := -1;
  end;
  FUncommittedBox.OnChange := Changed;
  FUncommittedCount := TLabel.Create(Self);
  FUncommittedCount.Parent := FUncommittedPanel;
  FUncommittedCount.SetBounds(cCaptionWidth + 2 * cGap + mWidth, 5, 260, 17);
  FUncommittedCount.Caption := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchUncommittedCount, [FFacts.LocalChanges]);

  mPanel := Row(FGitBox, TAtlasStrings.Text(TAtlasTextId.VcsBranchPlace), 28);
  FPlaceBox := TComboBox.Create(Self);
  FPlaceBox.Parent := mPanel;
  FPlaceBox.Style := csDropDownList;
  FPlaceBox.SetBounds(cCaptionWidth + cGap, 2, mPanel.Width - cCaptionWidth - 2 * cGap, 23);
  FPlaceBox.Anchors := [akLeft, akTop, akRight];
  FPlaceBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.VcsBranchPlaceSwitch));
  FPlaceBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.VcsBranchPlaceWorktree));
  if FGitOptions.Worktree then
    FPlaceBox.ItemIndex := 1
  else
    FPlaceBox.ItemIndex := 0;
  FPlaceBox.OnChange := Changed;

  FFolderPanel := Row(FGitBox, TAtlasStrings.Text(TAtlasTextId.VcsBranchFolder), 28);
  FFolderEdit := TEdit.Create(Self);
  FFolderEdit.Parent := FFolderPanel;
  FFolderEdit.SetBounds(cCaptionWidth + cGap, 2, FFolderPanel.Width - cCaptionWidth - 2 * cGap, 23);
  FFolderEdit.Anchors := [akLeft, akTop, akRight];
  FFolderEdit.OnChange := FolderChanged;

  FGitError := TLabel.Create(Self);
  FGitError.Parent := FGitBox;
  Stack(FGitError);
  FGitError.AlignWithMargins := True;
  FGitError.Margins.SetBounds(cCaptionWidth + 2 * cGap, 0, cGap, 2);
  FGitError.Font.Color := clRed;
  FGitError.WordWrap := True;
end;

procedure TAtlasBranchDialog.FolderChanged(Sender: TObject);
begin
  // Von Hand geändert: folgt dem Namen nicht mehr.
  if not FFilling then
    FFolderEdited := True;
  Changed(Sender);
end;

function TAtlasBranchDialog.SelectedBase: TAtlasVcsBranchBase;
begin
  Result := TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Current, '', '');
  if (FBaseBox.ItemIndex >= 0) and (FBaseBox.ItemIndex <= High(FBases)) then
    Result := FBases[FBaseBox.ItemIndex];
end;

procedure TAtlasBranchDialog.UpdateGit;
var
  mBase: TAtlasVcsBranchBase;
  mWasFilling: Boolean;
begin
  if FFacts.Kind <> TAtlasVcsKind.Git then
    Exit;
  mBase := SelectedBase;
  FFetchCheck.Enabled := mBase.Kind = TAtlasVcsBranchBaseKind.RemoteMain;
  FFetchCheck.Caption := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFetch, [mBase.RemoteName, FFacts.MainBranch]);
  ShowRow(FUncommittedPanel, FPushBox.Parent, (FFacts.LocalChanges > 0) and (FPlaceBox.ItemIndex <> 1));
  ShowRow(FFolderPanel, FPlaceBox.Parent, FPlaceBox.ItemIndex = 1);
  if FFolderPanel.Visible and not FFolderEdited then
  begin
    mWasFilling := FFilling;
    FFilling := True;
    try
      FFolderEdit.Text := TAtlasVcsBranchPlan.WorktreePath(FFacts.Root, FGitOptions.WorktreeFolder,
        Trim(FNameEdit.Text), FKey);
    finally
      FFilling := mWasFilling;
    end;
  end;
end;

procedure TAtlasBranchDialog.ShowRow(ARow, AAfter: TControl; AVisible: Boolean);
begin
  if AVisible and not ARow.Visible then
    ARow.Top := AAfter.Top + AAfter.Height + 1;
  ARow.Visible := AVisible;
end;

function TAtlasBranchDialog.GitState(out AText: string): Boolean;
var
  mFolder: string;
begin
  AText := '';
  if FFacts.Kind = TAtlasVcsKind.Git then
  begin
    mFolder := Trim(FFolderEdit.Text);
    if FUncommittedPanel.Visible and (FUncommittedBox.ItemIndex < 0) then
      AText := TAtlasStrings.Text(TAtlasTextId.VcsBranchUncommittedChoose)
    else if FFolderPanel.Visible and not TAtlasVcsBranchPlan.SafeFolder(mFolder) then
      AText := TAtlasStrings.Text(TAtlasTextId.VcsBranchFolderInvalid)
    else if FFolderPanel.Visible and DirectoryExists(mFolder) then
      AText := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFolderExists, [mFolder]);
  end;
  Result := AText = '';
end;

procedure TAtlasBranchDialog.Stack(AControl: TControl);
begin
  // alTop ordnet nach Top: weit unten anfangen, dann steht das neue Element unter allen bisherigen.
  AControl.Top := cBelowAll;
  AControl.Align := alTop;
end;

class function TAtlasBranchDialog.BaseCaption(AKind: TAtlasVcsKind; const ABase: TAtlasVcsBranchBase): string;
begin
  case ABase.Kind of
    TAtlasVcsBranchBaseKind.RemoteMain:
      Result := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchBaseRemote, [ABase.Name]);
    TAtlasVcsBranchBaseKind.LocalMain:
      Result := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchBaseLocal, [ABase.Name]);
    TAtlasVcsBranchBaseKind.Head:
      if ABase.Revision = '' then
        Result := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchBaseHead, [ABase.Name])
      else
        Result := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchBaseHeadRevision, [ABase.Name, ABase.Revision]);
    TAtlasVcsBranchBaseKind.WorkingCopy:
      Result := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchBaseWorkingCopy, [ABase.Name, ABase.Revision]);
  else
    if ABase.Name = '' then
      Result := TAtlasStrings.Text(TAtlasTextId.VcsBranchBaseDetached)
    else
      Result := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchBaseCurrent, [ABase.Name]);
  end;
end;

class function TAtlasBranchDialog.StepLines(AKind: TAtlasVcsKind;
  const ASteps: TArray<TAtlasVcsBranchStep>): TArray<string>;
var
  mIndex: Integer;
  mLine: string;
begin
  Result := nil;
  for mIndex := 0 to High(ASteps) do
  begin
    mLine := Format('%d. %s', [mIndex + 1, TAtlasVcsBranchPlan.StepText(AKind, ASteps[mIndex])]);
    if ASteps[mIndex].ChangesServer then
      mLine := mLine + '   ' + TAtlasStrings.Text(TAtlasTextId.VcsBranchOnServer);
    Result := Result + [mLine];
  end;
end;

procedure TAtlasBranchDialog.FillBases(APreferred: TAtlasVcsBranchBaseKind);
var
  mBase: TAtlasVcsBranchBase;
  mIndex: Integer;
begin
  FFilling := True;
  try
    FBases := TAtlasVcsBranchPlan.Bases(FFacts);
    FBaseBox.Items.BeginUpdate;
    try
      FBaseBox.Items.Clear;
      for mBase in FBases do
        FBaseBox.Items.Add(BaseCaption(FFacts.Kind, mBase));
    finally
      FBaseBox.Items.EndUpdate;
    end;
    FBaseBox.ItemIndex := -1;
    for mIndex := 0 to High(FBases) do
      if FBases[mIndex].Kind = APreferred then
      begin
        FBaseBox.ItemIndex := mIndex;
        Break;
      end;
    if (FBaseBox.ItemIndex < 0) and (Length(FBases) > 0) then
      FBaseBox.ItemIndex := 0;
  finally
    FFilling := False;
  end;
  Changed(nil);
end;

procedure TAtlasBranchDialog.Loaded(const AFacts: TAtlasVcsBranchFacts);
var
  mKind: TAtlasVcsBranchBaseKind;
begin
  mKind := TAtlasVcsBranchBaseKind.Head;
  if (FBaseBox.ItemIndex >= 0) and (FBaseBox.ItemIndex <= High(FBases)) then
    mKind := FBases[FBaseBox.ItemIndex].Kind;
  FFacts := AFacts;
  FillBases(mKind);
end;

function TAtlasBranchDialog.NameState(out AText: string): Boolean;
var
  mName: string;
begin
  AText := '';
  mName := Trim(FNameEdit.Text);
  if mName = '' then
    AText := TAtlasStrings.Text(TAtlasTextId.VcsBranchNameMissing)
  else if (mName <> FNameEdit.Text) or not TAtlasTrackerNaming.ValidBranchName(mName) or
    not TAtlasVcsBranchPlan.SafeName(mName) then
    AText := TAtlasStrings.Text(TAtlasTextId.VcsBranchNameInvalid);
  Result := AText = '';
end;

function TAtlasBranchDialog.Request: TAtlasVcsBranchRequest;
var
  mBase: TAtlasVcsBranchBase;
begin
  mBase := SelectedBase;
  Result := TAtlasVcsBranchRequest.Make(FFacts.Kind, FNameEdit.Text, mBase, FMessageEdit.Text);
  if FFacts.Kind <> TAtlasVcsKind.Git then
    Exit;
  Result.Fetch := FFetchCheck.Checked and (mBase.Kind = TAtlasVcsBranchBaseKind.RemoteMain);
  Result.PushNow := FPushBox.ItemIndex = 1;
  if FPlaceBox.ItemIndex = 1 then
    Result.WorktreeFolder := Trim(FFolderEdit.Text)
  else
    Result.Stash := FUncommittedPanel.Visible and (FUncommittedBox.ItemIndex = 1);
end;

function TAtlasBranchDialog.CanCreate: Boolean;
var
  mText: string;
begin
  Result := NameState(mText) and GitState(mText) and not FFacts.NeedsServer and (FBaseBox.ItemIndex >= 0) and
    (Length(FSteps) > 0);
end;

procedure TAtlasBranchDialog.Changed(Sender: TObject);
var
  mText, mGitText: string;
  mHeight: Integer;
begin
  if FFilling then
    Exit;
  NameState(mText);
  FNameError.Caption := mText;
  FNameError.Visible := mText <> '';
  UpdateGit;
  GitState(mGitText);
  FGitError.Caption := mGitText;
  if (mGitText <> '') and not FGitError.Visible then
    FGitError.Top := cBelowAll;
  FGitError.Visible := mGitText <> '';
  if FGitBox.Visible then
  begin
    // Höhe nach den sichtbaren Zeilen: Überschrift, Abrufen, Server, Ablage, ggf. Änderungen, Ordner, Hinweis.
    mHeight := 24 + 28 + 2 * 32;
    if FUncommittedPanel.Visible then
      Inc(mHeight, 32);
    if FFolderPanel.Visible then
      Inc(mHeight, 32);
    if FGitError.Visible then
      Inc(mHeight, 36);
    FGitBox.Height := mHeight;
  end;
  // Info: Werte vom Server werden noch ermittelt bzw. konnten nicht ermittelt werden; ohne Basis.
  if FFacts.Outcome <> TAtlasVcsOutcome.Ok then
    FInfoLabel.Caption := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchNoWorkingCopy, [AtlasVcsOutcomeName(FFacts.Outcome)])
  else if FFacts.NeedsServer then
    FInfoLabel.Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchLoading)
  else if FFacts.ServerChecked and (FFacts.ServerOutcome <> TAtlasVcsOutcome.Ok) then
    FInfoLabel.Caption := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchHeadUnknown,
      [AtlasVcsOutcomeName(FFacts.ServerOutcome)])
  else if Length(FBases) = 0 then
    FInfoLabel.Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchNoBase)
  else
    FInfoLabel.Caption := '';
  FInfoLabel.Visible := FInfoLabel.Caption <> '';
  FSteps := nil;
  if (mText = '') and (FBaseBox.ItemIndex >= 0) then
    FSteps := TAtlasVcsBranchPlan.Steps(Request);
  FStepsMemo.Lines.Text := string.Join(sLineBreak, StepLines(FFacts.Kind, FSteps));
  FServerHint.Visible := Length(TAtlasVcsBranchPlan.ServerStepsDone(FSteps, Length(FSteps))) > 0;
  FCreateButton.Enabled := CanCreate;
end;

procedure TAtlasBranchDialog.CreateClick(Sender: TObject);
begin
  if CanCreate then
    ModalResult := mrOk;
end;

end.
