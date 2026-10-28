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
// SVN (#1290): Ablageort (vorbelegt aus vcs.branch.svn.location, folgt dem
// Namen, bis man ihn selbst ändert; ohne erkennbares Layout leer mit
// Hinweis), Danach (umschalten, frisch auschecken mit Ordner, nur anlegen)
// und eine Warnung bei gemischter Arbeitskopie, wenn von ihrer Revision
// kopiert wird.
// Gruppe „Git“ (#1289) direkt unter der Basis, vorbelegt aus vcs.branch.git.*:
// vorher abrufen (nur mit Basis <Remote>/<Hauptbranch>), auf den Server
// (später/sofort), offene Änderungen (nur mit geänderten Dateien und ohne
// worktree; „nachfragen“ lässt die Auswahl leer und sperrt „Anlegen“, bis
// gewählt ist) und Ablage (umschalten/eigener Ordner). Der worktree-Ordner
// folgt dem Namen, bis er von Hand geändert wird; gibt es ihn schon, sperrt
// ein Hinweis „Anlegen“.
// Externals (#1291): Gruppe „Externals (n)“ mit Ordner, Quelle und Auswahl je
// Zeile (festschreiben auf die Revision der External-Arbeitskopie,
// unverändert, mitverzweigen). Vorauswahl aus TAtlasVcsBranchPlan.DefaultActions
// (Regeln, vcs.externals.onBranch, suggestBranch); „mitverzweigen“ nur für
// Externals aus demselben Repository mit auflösbarem Ablageort, Externals mit
// fester Revision zeigen „bleibt r<N>“. Ohne Auswahl (onBranch = ask) bleibt
// „Anlegen“ gesperrt. Konnte Atlas die Externals nicht lesen, steht nur der
// Hinweis, dass sie unverändert mitgehen.

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
    FKey: string;
    FGitOptions: TAtlasVcsGitBranchOptions;
    FGitBox: TGroupBox;
    FFetchCheck: TCheckBox;
    FPushBox: TComboBox;
    FUncommittedPanel: TPanel;
    FUncommittedBox: TComboBox;
    FUncommittedCount: TLabel;
    FPlaceBox: TComboBox;
    FWorktreePanel: TPanel;
    FWorktreeEdit: TEdit;
    FGitError: TLabel;
    FWorktreeEdited: Boolean;
    FBases: TArray<TAtlasVcsBranchBase>;
    FSteps: TArray<TAtlasVcsBranchStep>;
    FNameEdit: TEdit;
    FNameError: TLabel;
    FBaseBox: TComboBox;
    FMessagePanel: TPanel;
    FMessageEdit: TEdit;
    FSvn: TAtlasVcsSvnBranchOptions;
    FLocationPanel: TPanel;
    FLocationEdit: TEdit;
    FLocationError: TLabel;
    FLocationEdited: Boolean;
    FAfterPanel: TPanel;
    FAfterBox: TComboBox;
    FFolderPanel: TPanel;
    FFolderEdit: TEdit;
    FFolderEdited: Boolean;
    FMixedLabel: TLabel;
    FInfoLabel: TLabel;
    FExternalsBox: TGroupBox;
    FExternalsHint: TLabel;
    /// <summary>Je External die Auswahl (nil bei fester Revision), ihre Einträge und die Vorauswahl.</summary>
    FExternalBoxes: TArray<TComboBox>;
    FExternalChoices: TArray<TArray<TAtlasVcsExternalAction>>;
    FExternalDefaults: TArray<TAtlasVcsExternalAction>;
    FStepsMemo: TMemo;
    FServerHint: TLabel;
    FNeverAsk: TCheckBox;
    FCreateButton: TButton;
    FFilling: Boolean;
    /// <summary>Alle Steuerelemente angelegt: CreateWnd darf die Auswahllisten füllen.</summary>
    FControlsReady: Boolean;
    function Row(const ACaption: string; AHeight: Integer): TPanel; overload;
    function Row(AParent: TWinControl; const ACaption: string; AHeight: Integer): TPanel; overload;
    procedure AddGitGroup;
    procedure UpdateGit;
    /// <summary>Zeile einblenden bzw. ausblenden; eingeblendet direkt unter AAfter (alTop ordnet nach Top).
    /// </summary>
    procedure ShowRow(ARow, AAfter: TControl; AVisible: Boolean);
    procedure WorktreeChanged(Sender: TObject);
    function GitState(out AText: string): Boolean;
    /// <summary>Einträge der Auswahllisten (brauchen ein Fenster); nur leere Listen.</summary>
    procedure FillChoices;
    procedure Stack(AControl: TControl);
    procedure FillBases(APreferred: TAtlasVcsBranchBaseKind);
    procedure Changed(Sender: TObject);
    procedure LocationChanged(Sender: TObject);
    procedure FolderChanged(Sender: TObject);
    procedure CreateClick(Sender: TObject);
    function NameState(out AText: string): Boolean;
    /// <summary>SVN: Ort und Ordner aus den Mustern für den aktuellen Namen, solange nicht selbst geändert.</summary>
    procedure FollowName;
    function SelectedBase(out ABase: TAtlasVcsBranchBase): Boolean;
    procedure AddExternals;
    procedure FillExternals;
    /// <summary>Wahl je External; Ask, solange eine Auswahl leer ist.</summary>
    function ExternalActions: TArray<TAtlasVcsExternalAction>;
    function ExternalsChosen: Boolean;
  protected
    procedure CreateWnd; override;
  public
    /// <summary>AFacts aus TAtlasVcsBranchPlan.Inspect; AName und AMessage vorbelegt ('' ohne Issue);
    /// AOfferNeverAsk zeigt „Nicht mehr fragen, Vorgaben verwenden“.</summary>
    constructor CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts; const AName, AMessage: string;
      AOfferNeverAsk: Boolean); overload;
    /// <summary>Wie oben mit den SVN-Optionen als Vorgaben (#1290): Ort, Quelle, Danach, Ordner.</summary>
    constructor CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts; const AName, AMessage: string;
      const ASvn: TAtlasVcsSvnBranchOptions; AOfferNeverAsk: Boolean); overload;
    /// <summary>Wie oben mit den Git-Vorgaben (#1289) und der Kennung des Issues für {kennung} im
    /// worktree-Ordner ('' ohne Issue).</summary>
    constructor CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts; const AName, AMessage,
      AKey: string; const AGitOptions: TAtlasVcsGitBranchOptions; AOfferNeverAsk: Boolean); overload;
    /// <summary>Mit Git- (#1289) und SVN-Vorgaben (#1290); je nach Art der Arbeitskopie zählt eine davon.</summary>
    constructor CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts; const AName, AMessage,
      AKey: string; const AGitOptions: TAtlasVcsGitBranchOptions; const ASvn: TAtlasVcsSvnBranchOptions;
      AOfferNeverAsk: Boolean); overload;
    /// <summary>Ort aus dem Feld ("^/Kasse/branches/x" → "Kasse/branches/x"); '' wenn es nicht mit ^/ beginnt.
    /// </summary>
    class function LocationOf(const AText: string): string; static;
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
    /// <summary>Ordner des worktree (Git); FolderPanel ist der Ordner fürs Auschecken (SVN).</summary>
    property WorktreePanel: TPanel read FWorktreePanel;
    property WorktreeEdit: TEdit read FWorktreeEdit;
    property GitError: TLabel read FGitError;
    property LocationPanel: TPanel read FLocationPanel;
    property LocationEdit: TEdit read FLocationEdit;
    property LocationError: TLabel read FLocationError;
    property AfterPanel: TPanel read FAfterPanel;
    property AfterBox: TComboBox read FAfterBox;
    property FolderPanel: TPanel read FFolderPanel;
    property FolderEdit: TEdit read FFolderEdit;
    property MixedLabel: TLabel read FMixedLabel;
    property InfoLabel: TLabel read FInfoLabel;
    property ExternalsBox: TGroupBox read FExternalsBox;
    property ExternalsHint: TLabel read FExternalsHint;
    /// <summary>Auswahl je External (nil bei fester Revision) und die Wahl hinter jedem Eintrag.</summary>
    property ExternalBoxes: TArray<TComboBox> read FExternalBoxes;
    property ExternalChoices: TArray<TArray<TAtlasVcsExternalAction>> read FExternalChoices;
    /// <summary>Text einer Wahl in der Auswahl eines Externals.</summary>
    class function ExternalCaption(const AExternal: TAtlasVcsSvnExternal; AAction: TAtlasVcsExternalAction): string;
      static;
    property StepsMemo: TMemo read FStepsMemo;
    property ServerHint: TLabel read FServerHint;
    property NeverAsk: TCheckBox read FNeverAsk;
    property CreateButton: TButton read FCreateButton;
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
  cExternalRow = 26;
  cExternalRowsVisible = 5;
  cFolderWidth = 150;
  cChoiceWidth = 200;

constructor TAtlasBranchDialog.CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts;
  const AName, AMessage: string; AOfferNeverAsk: Boolean);
begin
  CreateDialog(AOwner, AFacts, AName, AMessage, '', TAtlasVcsGitBranchOptions.Classic,
    TAtlasVcsSvnBranchOptions.Legacy, AOfferNeverAsk);
end;

constructor TAtlasBranchDialog.CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts;
  const AName, AMessage: string; const ASvn: TAtlasVcsSvnBranchOptions; AOfferNeverAsk: Boolean);
begin
  CreateDialog(AOwner, AFacts, AName, AMessage, '', TAtlasVcsGitBranchOptions.Classic, ASvn, AOfferNeverAsk);
end;

constructor TAtlasBranchDialog.CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts;
  const AName, AMessage, AKey: string; const AGitOptions: TAtlasVcsGitBranchOptions; AOfferNeverAsk: Boolean);
begin
  CreateDialog(AOwner, AFacts, AName, AMessage, AKey, AGitOptions, TAtlasVcsSvnBranchOptions.Legacy,
    AOfferNeverAsk);
end;

constructor TAtlasBranchDialog.CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts;
  const AName, AMessage, AKey: string; const AGitOptions: TAtlasVcsGitBranchOptions;
  const ASvn: TAtlasVcsSvnBranchOptions; AOfferNeverAsk: Boolean);
var
  mPanel, mBottom: TPanel;
  mSteps: TGroupBox;
  mCancel: TButton;
  mBase: TAtlasVcsBranchBase;
  mPreferred: TAtlasVcsBranchBaseKind;
begin
  inherited CreateNew(AOwner);
  FFacts := AFacts;
  FKey := AKey;
  FGitOptions := AGitOptions;
  FSvn := ASvn;
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

  // SVN (#1290): Ort, Danach, Ordner; nur für SVN sichtbar.
  FLocationPanel := Row(TAtlasStrings.Text(TAtlasTextId.VcsBranchLocation), 28);
  FLocationEdit := TEdit.Create(Self);
  FLocationEdit.Parent := FLocationPanel;
  FLocationEdit.SetBounds(cCaptionWidth + cGap, 2, FLocationPanel.Width - cCaptionWidth - 2 * cGap, 23);
  FLocationEdit.Anchors := [akLeft, akTop, akRight];
  FLocationEdit.OnChange := LocationChanged;
  FLocationError := TLabel.Create(Self);
  FLocationError.Parent := Self;
  Stack(FLocationError);
  FLocationError.AlignWithMargins := True;
  FLocationError.Margins.SetBounds(cCaptionWidth + 2 * cGap, 0, cGap, 2);
  FLocationError.Font.Color := clRed;
  FLocationError.WordWrap := True;
  FAfterPanel := Row(TAtlasStrings.Text(TAtlasTextId.VcsBranchAfter), 28);
  FAfterBox := TComboBox.Create(Self);
  FAfterBox.Parent := FAfterPanel;
  FAfterBox.Style := csDropDownList;
  FAfterBox.SetBounds(cCaptionWidth + cGap, 2, FAfterPanel.Width - cCaptionWidth - 2 * cGap, 23);
  FAfterBox.Anchors := [akLeft, akTop, akRight];
  FAfterBox.OnChange := Changed;
  FFolderPanel := Row(TAtlasStrings.Text(TAtlasTextId.VcsBranchFolder), 28);
  FFolderEdit := TEdit.Create(Self);
  FFolderEdit.Parent := FFolderPanel;
  FFolderEdit.SetBounds(cCaptionWidth + cGap, 2, FFolderPanel.Width - cCaptionWidth - 2 * cGap, 23);
  FFolderEdit.Anchors := [akLeft, akTop, akRight];
  FFolderEdit.OnChange := FolderChanged;
  FMixedLabel := TLabel.Create(Self);
  FMixedLabel.Parent := Self;
  Stack(FMixedLabel);
  FMixedLabel.AlignWithMargins := True;
  FMixedLabel.Margins.SetBounds(cCaptionWidth + 2 * cGap, 2, cGap, 2);
  FMixedLabel.Font.Color := clRed;
  FMixedLabel.WordWrap := True;
  FMixedLabel.Caption := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchMixed, [AFacts.Revision]);
  FLocationPanel.Visible := AFacts.Kind = TAtlasVcsKind.Svn;
  FAfterPanel.Visible := AFacts.Kind = TAtlasVcsKind.Svn;
  FFolderPanel.Visible := False;
  FLocationError.Visible := False;
  FMixedLabel.Visible := False;

  FInfoLabel := TLabel.Create(Self);
  FInfoLabel.Parent := Self;
  Stack(FInfoLabel);
  FInfoLabel.AlignWithMargins := True;
  FInfoLabel.Margins.SetBounds(cCaptionWidth + 2 * cGap, 2, cGap, 4);
  FInfoLabel.WordWrap := True;

  AddExternals;

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
  if AFacts.Kind = TAtlasVcsKind.Git then
  begin
    if TAtlasVcsBranchPlan.DefaultBase(AFacts, AGitOptions, mBase) then
      mPreferred := mBase.Kind;
  end
  else if TAtlasVcsBranchPlan.DefaultBase(AFacts, ASvn.Source, mBase) then
    mPreferred := mBase.Kind;
  // Hat schon ein Steuerelement das Fenster erzwungen, kam CreateWnd zu früh: jetzt füllen. Sonst füllt CreateWnd,
  // sobald FillBases das Fenster braucht.
  FControlsReady := True;
  if HandleAllocated then
    FillChoices;
  FFilling := False;
  FillBases(mPreferred);
end;

procedure TAtlasBranchDialog.CreateWnd;
var
  mFilling: Boolean;
begin
  inherited;
  // Combobox-Einträge brauchen ein Fenster: erst hier füllen (#1290). Das Fenster entsteht schon im
  // Konstruktor, sobald FillBases die Basen einträgt; FFilling bleibt dann gesetzt, Changed folgt dort.
  if not FControlsReady then
    Exit;
  mFilling := FFilling;
  FFilling := True;
  try
    FillChoices;
  finally
    FFilling := mFilling;
  end;
  if not mFilling then
    Changed(nil);
end;

procedure TAtlasBranchDialog.FillChoices;
var
  mFilling: Boolean;
begin
  mFilling := FFilling;
  FFilling := True;
  try
    if FAfterBox.Items.Count = 0 then
    begin
      FAfterBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.VcsBranchAfterSwitch));
      FAfterBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.VcsBranchAfterCheckout));
      FAfterBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.VcsBranchAfterNone));
      FAfterBox.ItemIndex := Ord(FSvn.After);
    end;
    // Git (#1289): Vorbelegung aus vcs.branch.git.*; „nachfragen“ lässt die Auswahl leer.
    if FPushBox.Items.Count = 0 then
    begin
      FPushBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.VcsBranchPushLater));
      FPushBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.VcsBranchPushNow));
      if FGitOptions.PushNow then
        FPushBox.ItemIndex := 1
      else
        FPushBox.ItemIndex := 0;
    end;
    if FUncommittedBox.Items.Count = 0 then
    begin
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
    end;
    if FPlaceBox.Items.Count = 0 then
    begin
      FPlaceBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.VcsBranchPlaceSwitch));
      FPlaceBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.VcsBranchPlaceWorktree));
      if FGitOptions.Worktree then
        FPlaceBox.ItemIndex := 1
      else
        FPlaceBox.ItemIndex := 0;
    end;
    FillExternals;
  finally
    FFilling := mFilling;
  end;
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

  // Einträge der Auswahllisten erst mit Fenster (FillChoices).
  mPanel := Row(FGitBox, TAtlasStrings.Text(TAtlasTextId.VcsBranchPush), 28);
  FPushBox := TComboBox.Create(Self);
  FPushBox.Parent := mPanel;
  FPushBox.Style := csDropDownList;
  FPushBox.SetBounds(cCaptionWidth + cGap, 2, mPanel.Width - cCaptionWidth - 2 * cGap, 23);
  FPushBox.Anchors := [akLeft, akTop, akRight];
  FPushBox.OnChange := Changed;

  // Offene Änderungen: nur mit geänderten Dateien; „nachfragen“ lässt die Auswahl leer.
  FUncommittedPanel := Row(FGitBox, TAtlasStrings.Text(TAtlasTextId.VcsBranchUncommitted), 28);
  mWidth := 240;
  FUncommittedBox := TComboBox.Create(Self);
  FUncommittedBox.Parent := FUncommittedPanel;
  FUncommittedBox.Style := csDropDownList;
  FUncommittedBox.SetBounds(cCaptionWidth + cGap, 2, mWidth, 23);
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
  FPlaceBox.OnChange := Changed;

  FWorktreePanel := Row(FGitBox, TAtlasStrings.Text(TAtlasTextId.VcsBranchFolder), 28);
  FWorktreeEdit := TEdit.Create(Self);
  FWorktreeEdit.Parent := FWorktreePanel;
  FWorktreeEdit.SetBounds(cCaptionWidth + cGap, 2, FWorktreePanel.Width - cCaptionWidth - 2 * cGap, 23);
  FWorktreeEdit.Anchors := [akLeft, akTop, akRight];
  FWorktreeEdit.OnChange := WorktreeChanged;

  FGitError := TLabel.Create(Self);
  FGitError.Parent := FGitBox;
  Stack(FGitError);
  FGitError.AlignWithMargins := True;
  FGitError.Margins.SetBounds(cCaptionWidth + 2 * cGap, 0, cGap, 2);
  FGitError.Font.Color := clRed;
  FGitError.WordWrap := True;
end;

procedure TAtlasBranchDialog.WorktreeChanged(Sender: TObject);
begin
  // Von Hand geändert: folgt dem Namen nicht mehr.
  if not FFilling then
    FWorktreeEdited := True;
  Changed(Sender);
end;

procedure TAtlasBranchDialog.UpdateGit;
var
  mBase: TAtlasVcsBranchBase;
  mWasFilling: Boolean;
begin
  if FFacts.Kind <> TAtlasVcsKind.Git then
    Exit;
  SelectedBase(mBase);
  FFetchCheck.Enabled := mBase.Kind = TAtlasVcsBranchBaseKind.RemoteMain;
  FFetchCheck.Caption := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFetch, [mBase.RemoteName, FFacts.MainBranch]);
  ShowRow(FUncommittedPanel, FPushBox.Parent, (FFacts.LocalChanges > 0) and (FPlaceBox.ItemIndex <> 1));
  ShowRow(FWorktreePanel, FPlaceBox.Parent, FPlaceBox.ItemIndex = 1);
  if FWorktreePanel.Visible and not FWorktreeEdited then
  begin
    mWasFilling := FFilling;
    FFilling := True;
    try
      FWorktreeEdit.Text := TAtlasVcsBranchPlan.WorktreePath(FFacts.Root, FGitOptions.WorktreeFolder,
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
    mFolder := Trim(FWorktreeEdit.Text);
    if FUncommittedPanel.Visible and (FUncommittedBox.ItemIndex < 0) then
      AText := TAtlasStrings.Text(TAtlasTextId.VcsBranchUncommittedChoose)
    else if FWorktreePanel.Visible and not TAtlasVcsBranchPlan.SafeFolder(mFolder) then
      AText := TAtlasStrings.Text(TAtlasTextId.VcsBranchFolderInvalid)
    else if FWorktreePanel.Visible and DirectoryExists(mFolder) then
      AText := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFolderExists, [mFolder]);
  end;
  Result := AText = '';
end;

procedure TAtlasBranchDialog.AddExternals;
var
  mHeader, mRow: TPanel;
  mScroll: TScrollBox;
  mLabel: TLabel;
  mIndex, mRows, mWidth: Integer;
  mExternal: TAtlasVcsSvnExternal;
  mAction: TAtlasVcsExternalAction;
  mPath: string;

  function AddLabel(AParent: TWinControl; ALeft, AWidth: Integer; const ACaption: string): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(ALeft, 5, AWidth, 17);
    Result.AutoSize := False;
    Result.EllipsisPosition := epPathEllipsis;
    Result.Caption := ACaption;
    Result.Hint := ACaption;
    Result.ShowHint := True;
  end;

begin
  FExternalsBox := TGroupBox.Create(Self);
  FExternalsBox.Parent := Self;
  Stack(FExternalsBox);
  FExternalsBox.AlignWithMargins := True;
  FExternalsBox.Margins.SetBounds(cGap, 4, cGap, 4);
  FExternalsBox.Visible := (FFacts.Kind = TAtlasVcsKind.Svn) and FFacts.Externals;
  FExternalsHint := TLabel.Create(Self);
  FExternalsHint.Parent := FExternalsBox;
  FExternalsHint.Align := alBottom;
  FExternalsHint.AlignWithMargins := True;
  FExternalsHint.WordWrap := True;
  FExternalBoxes := nil;
  FExternalChoices := nil;
  FExternalDefaults := nil;
  // Nicht gelesen (propget gescheitert): Hinweis wie vor #1291, die Externals gehen unverändert mit.
  if (FFacts.Kind <> TAtlasVcsKind.Svn) or (Length(FFacts.SvnExternals) = 0) then
  begin
    FExternalsBox.Height := 56;
    FExternalsBox.Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchExternals);
    FExternalsHint.Align := alClient;
    FExternalsHint.Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchExternalsKept);
    Exit;
  end;
  FExternalsBox.Caption := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchExternalsCount, [Length(FFacts.SvnExternals)]);
  FExternalsHint.Font.Color := clRed;
  FExternalsHint.Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchExternalsChoose);
  FExternalsHint.Visible := False;
  mRows := Length(FFacts.SvnExternals);
  if mRows > cExternalRowsVisible then
    mRows := cExternalRowsVisible;
  FExternalsBox.Height := 44 + 20 + mRows * cExternalRow;
  // Breite vorab wie im fertigen Dialog (ohne Fenster richtet alTop nicht aus); Anker gleichen den Rest aus.
  mWidth := Width - 4 * cGap - 20;
  mHeader := TPanel.Create(Self);
  mHeader.Parent := FExternalsBox;
  mHeader.Width := mWidth;
  mHeader.Align := alTop;
  mHeader.Height := 20;
  mHeader.BevelOuter := bvNone;
  AddLabel(mHeader, cGap, cFolderWidth, TAtlasStrings.Text(TAtlasTextId.VcsBranchExternalsFolder)).Font.Color :=
    clGrayText;
  AddLabel(mHeader, cGap + cFolderWidth + cGap, 200, TAtlasStrings.Text(TAtlasTextId.VcsBranchExternalsSource))
    .Font.Color := clGrayText;
  mLabel := AddLabel(mHeader, mHeader.Width - cChoiceWidth - cGap, cChoiceWidth,
    TAtlasStrings.Text(TAtlasTextId.VcsBranchExternalsInBranch));
  mLabel.Anchors := [akTop, akRight];
  mLabel.Font.Color := clGrayText;
  mScroll := TScrollBox.Create(Self);
  mScroll.Parent := FExternalsBox;
  mScroll.Width := mWidth;
  mScroll.Align := alClient;
  mScroll.BorderStyle := bsNone;
  mScroll.VertScrollBar.Increment := cExternalRow;
  FExternalDefaults := TAtlasVcsBranchPlan.DefaultActions(FFacts, FSvn);
  SetLength(FExternalBoxes, Length(FFacts.SvnExternals));
  SetLength(FExternalChoices, Length(FFacts.SvnExternals));
  for mIndex := 0 to High(FFacts.SvnExternals) do
  begin
    mExternal := FFacts.SvnExternals[mIndex];
    mRow := TPanel.Create(Self);
    mRow.Parent := mScroll;
    mRow.Width := mWidth;
    mRow.Height := cExternalRow;
    mRow.BevelOuter := bvNone;
    mRow.Top := mIndex * cExternalRow;
    mRow.Align := alTop;
    AddLabel(mRow, cGap, cFolderWidth, mExternal.Path);
    mLabel := AddLabel(mRow, cGap + cFolderWidth + cGap, mRow.Width - cFolderWidth - cChoiceWidth - 4 * cGap,
      mExternal.Line);
    mLabel.Anchors := [akLeft, akTop, akRight];
    if mExternal.Source <> '' then
      mLabel.Caption := '^/' + mExternal.Source
    else
      mLabel.Caption := mExternal.FullUrl;
    if mExternal.Revision <> '' then
      mLabel.Caption := mLabel.Caption + ' -r ' + mExternal.Revision;
    FExternalChoices[mIndex] := nil;
    FExternalBoxes[mIndex] := nil;
    // Feste Revision: bleibt, keine Auswahl.
    if mExternal.Fixed then
    begin
      mLabel := AddLabel(mRow, mRow.Width - cChoiceWidth - cGap, cChoiceWidth,
        TAtlasStrings.Fmt(TAtlasTextId.VcsBranchExternalFixed, [TAtlasVcsBranchPlan.ExternalRevision(mExternal)]));
      mLabel.Anchors := [akTop, akRight];
      Continue;
    end;
    // Festschreiben braucht die Revision der External-Arbeitskopie; mitverzweigen einen Ablageort (Layout im
    // Pfad des Packages; den Ort für den eingegebenen Namen löst ApplyExternals auf).
    for mAction in [TAtlasVcsExternalAction.Pin, TAtlasVcsExternalAction.Keep, TAtlasVcsExternalAction.Branch] do
      if ((mAction = TAtlasVcsExternalAction.Pin) and (mExternal.WorkingRevision <> '')) or
        (mAction = TAtlasVcsExternalAction.Keep) or ((mAction = TAtlasVcsExternalAction.Branch) and
        TAtlasVcsBranchPlan.ExternalLocation(mExternal, FSvn, 'x', mPath)) then
        FExternalChoices[mIndex] := FExternalChoices[mIndex] + [mAction];
    FExternalBoxes[mIndex] := TComboBox.Create(Self);
    FExternalBoxes[mIndex].Parent := mRow;
    FExternalBoxes[mIndex].Style := csDropDownList;
    FExternalBoxes[mIndex].SetBounds(mRow.Width - cChoiceWidth - cGap, 1, cChoiceWidth, 23);
    FExternalBoxes[mIndex].Anchors := [akTop, akRight];
    FExternalBoxes[mIndex].OnChange := Changed;
  end;
end;

procedure TAtlasBranchDialog.FillExternals;
var
  mIndex, mChoice: Integer;
begin
  for mIndex := 0 to High(FExternalBoxes) do
  begin
    if not Assigned(FExternalBoxes[mIndex]) or (FExternalBoxes[mIndex].Items.Count > 0) then
      Continue;
    for mChoice := 0 to High(FExternalChoices[mIndex]) do
      FExternalBoxes[mIndex].Items.Add(ExternalCaption(FFacts.SvnExternals[mIndex],
        FExternalChoices[mIndex][mChoice]));
    // Vorauswahl; Ask oder eine Wahl, die es hier nicht gibt: leer.
    FExternalBoxes[mIndex].ItemIndex := -1;
    for mChoice := 0 to High(FExternalChoices[mIndex]) do
      if (mIndex <= High(FExternalDefaults)) and (FExternalChoices[mIndex][mChoice] = FExternalDefaults[mIndex]) then
        FExternalBoxes[mIndex].ItemIndex := mChoice;
  end;
end;

class function TAtlasBranchDialog.ExternalCaption(const AExternal: TAtlasVcsSvnExternal;
  AAction: TAtlasVcsExternalAction): string;
begin
  case AAction of
    TAtlasVcsExternalAction.Pin:
      Result := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchExternalPin, [TAtlasVcsBranchPlan.ExternalRevision(AExternal)]);
    TAtlasVcsExternalAction.Branch:
      Result := TAtlasStrings.Text(TAtlasTextId.VcsBranchExternalBranch);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.VcsBranchExternalKeep);
  end;
end;

function TAtlasBranchDialog.ExternalActions: TArray<TAtlasVcsExternalAction>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(FExternalBoxes));
  for mIndex := 0 to High(FExternalBoxes) do
    if not Assigned(FExternalBoxes[mIndex]) then
      Result[mIndex] := TAtlasVcsExternalAction.Keep
    else if (FExternalBoxes[mIndex].ItemIndex >= 0) and
      (FExternalBoxes[mIndex].ItemIndex <= High(FExternalChoices[mIndex])) then
      Result[mIndex] := FExternalChoices[mIndex][FExternalBoxes[mIndex].ItemIndex]
    else
      Result[mIndex] := TAtlasVcsExternalAction.Ask;
end;

function TAtlasBranchDialog.ExternalsChosen: Boolean;
var
  mAction: TAtlasVcsExternalAction;
begin
  for mAction in ExternalActions do
    if mAction = TAtlasVcsExternalAction.Ask then
      Exit(False);
  Result := True;
end;

class function TAtlasBranchDialog.LocationOf(const AText: string): string;
begin
  Result := Trim(AText);
  if Copy(Result, 1, 2) <> '^/' then
    Exit('');
  Result := Copy(Result, 3, MaxInt);
  while (Result <> '') and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

procedure TAtlasBranchDialog.LocationChanged(Sender: TObject);
begin
  if not FFilling then
    FLocationEdited := True;
  Changed(Sender);
end;

procedure TAtlasBranchDialog.FolderChanged(Sender: TObject);
begin
  if not FFilling then
    FFolderEdited := True;
  Changed(Sender);
end;

procedure TAtlasBranchDialog.FollowName;
var
  mName, mPath: string;
begin
  if FFacts.Kind <> TAtlasVcsKind.Svn then
    Exit;
  mName := Trim(FNameEdit.Text);
  FFilling := True;
  try
    if not FLocationEdited then
    begin
      if (mName <> '') and TAtlasVcsBranchPlan.SvnLocation(FFacts, FSvn, mName, mPath) then
        FLocationEdit.Text := '^/' + mPath
      else
        FLocationEdit.Text := '';
    end;
    if not FFolderEdited then
    begin
      if mName <> '' then
        FFolderEdit.Text := TAtlasVcsBranchPlan.SvnCheckoutFolder(FFacts, FSvn, mName)
      else
        FFolderEdit.Text := '';
    end;
  finally
    FFilling := False;
  end;
end;

function TAtlasBranchDialog.SelectedBase(out ABase: TAtlasVcsBranchBase): Boolean;
begin
  ABase := TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Current, '', '');
  Result := (FBaseBox.ItemIndex >= 0) and (FBaseBox.ItemIndex <= High(FBases));
  if Result then
    ABase := FBases[FBaseBox.ItemIndex];
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
  SelectedBase(mBase);
  Result := TAtlasVcsBranchRequest.Make(FFacts.Kind, FNameEdit.Text, mBase, FMessageEdit.Text);
  if FFacts.Kind = TAtlasVcsKind.Git then
  begin
    // Git (#1289): Abruf nur mit Basis vom Server; worktree oder offene Änderungen beiseitelegen.
    Result.Fetch := FFetchCheck.Checked and (mBase.Kind = TAtlasVcsBranchBaseKind.RemoteMain);
    Result.PushNow := FPushBox.ItemIndex = 1;
    if FPlaceBox.ItemIndex = 1 then
      Result.WorktreeFolder := Trim(FWorktreeEdit.Text)
    else
      Result.Stash := FUncommittedPanel.Visible and (FUncommittedBox.ItemIndex = 1);
    Exit;
  end;
  if FFacts.Kind <> TAtlasVcsKind.Svn then
    Exit;
  // SVN (#1290): Ort und Ordner wie im Dialog angezeigt.
  Result.Location := LocationOf(FLocationEdit.Text);
  Result.After := FSvn.After;
  if (FAfterBox.ItemIndex >= 0) and (FAfterBox.ItemIndex <= Ord(High(TAtlasVcsSvnAfter))) then
    Result.After := TAtlasVcsSvnAfter(FAfterBox.ItemIndex);
  Result.CheckoutFolder := '';
  if Result.After = TAtlasVcsSvnAfter.Checkout then
    Result.CheckoutFolder := Trim(FFolderEdit.Text);
  // Externals (#1291): Wahl je Zeile, Orte der mitverzweigten Packages für den Namen.
  if Length(FExternalBoxes) > 0 then
    TAtlasVcsBranchPlan.ApplyExternals(Result, FFacts, FSvn, ExternalActions);
end;

function TAtlasBranchDialog.CanCreate: Boolean;
var
  mText: string;
begin
  Result := NameState(mText) and GitState(mText) and not FFacts.NeedsServer and (FBaseBox.ItemIndex >= 0) and
    (Length(FSteps) > 0) and ExternalsChosen;
end;

procedure TAtlasBranchDialog.Changed(Sender: TObject);
var
  mText, mGitText: string;
  mBase: TAtlasVcsBranchBase;
  mRequest: TAtlasVcsBranchRequest;
  mHeight: Integer;
begin
  if FFilling then
    Exit;
  NameState(mText);
  FNameError.Caption := mText;
  FNameError.Visible := mText <> '';
  FollowName;
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
    if FWorktreePanel.Visible then
      Inc(mHeight, 32);
    if FGitError.Visible then
      Inc(mHeight, 36);
    FGitBox.Height := mHeight;
  end;
  mRequest := Request;
  if FFacts.Kind = TAtlasVcsKind.Svn then
  begin
    // Ort: ohne erkennbares Layout bitten, ihn anzugeben; sonst muss er ein sicherer Pfad unter ^/ sein.
    if Trim(FLocationEdit.Text) = '' then
      FLocationError.Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchLocationMissing)
    else if not TAtlasVcsBranchPlan.SafeName(mRequest.Location) then
      FLocationError.Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchLocationInvalid)
    else
      FLocationError.Caption := '';
    FLocationError.Visible := (FLocationError.Caption <> '') and (mText = '');
    FFolderPanel.Visible := mRequest.After = TAtlasVcsSvnAfter.Checkout;
    FMixedLabel.Visible := FFacts.MixedRevision and SelectedBase(mBase) and
      (mBase.Kind = TAtlasVcsBranchBaseKind.WorkingCopy);
    if Length(FExternalBoxes) > 0 then
      FExternalsHint.Visible := not ExternalsChosen;
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
    FSteps := TAtlasVcsBranchPlan.Steps(mRequest);
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
