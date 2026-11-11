unit Atlas.UI.VersionControl.BranchDialog;

// Dialog „Branch anlegen“ (#1288): Name, Basis, (SVN) Nachricht und unter
// „Was passiert“ die Schritte in Klartext, genau so, wie Atlas sie danach
// ausführt (TAtlasVcsBranchPlan). Jede Änderung baut die Liste neu; Schritte,
// die den Server ändern, tragen den Zusatz „auf dem Server“. Ein ungültiger
// Name (TAtlasVcsBranchNames.Valid) sperrt „Anlegen“ mit Hinweis
// unter dem Feld. Braucht der Plan Werte vom Server (SVN: HEAD-Revision),
// steht „wird ermittelt …“ und „Anlegen“ bleibt gesperrt, bis die IDE-Schicht
// ServerLoaded aufruft. „Nicht mehr fragen, Vorgaben verwenden“ nur bei „Beginnen“
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

// Aufbau: Der Dialog ordnet nur an; Name und Basis, Git, SVN, Externals und
// „Was passiert“ sind eigene Teile (TAtlasBranchDialogPart), deren
// Steuerelemente dem Dialog gehören.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.BranchPlan,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasBranchDialog = class;

  /// <summary>Vorgaben für den Dialog: Name und Nachricht vorbelegt ('' ohne Issue), Kennung des Issues für
  /// {kennung} im worktree-Ordner, Git- (#1289) und SVN-Vorgaben (#1290); OfferNeverAsk zeigt „Nicht mehr
  /// fragen, Vorgaben verwenden“.</summary>
  TAtlasBranchDialogSetup = record
    Name: string;
    Message: string;
    Key: string;
    Git: TAtlasVcsGitBranchOptions;
    Svn: TAtlasVcsSvnBranchOptions;
    OfferNeverAsk: Boolean;
    /// <summary>Git-Vorgaben wie vor #1289 (Classic), SVN wie vor #1290 (Legacy).</summary>
    class function Make(const AName, AMessage, AKey: string; AOfferNeverAsk: Boolean): TAtlasBranchDialogSetup;
      static;
  end;

  /// <summary>Teil des Dialogs: legt seine Steuerelemente mit dem Dialog als Besitzer an.</summary>
  TAtlasBranchDialogPart = class
  protected
    FDialog: TAtlasBranchDialog;
  public
    constructor Create(ADialog: TAtlasBranchDialog);
  end;

  /// <summary>Name und Basis.</summary>
  TAtlasBranchNamePart = class(TAtlasBranchDialogPart)
  private
    FNameEdit: TEdit;
    FNameError: TLabel;
    FBaseBox: TComboBox;
    FBases: TArray<TAtlasVcsBranchBase>;
  public
    procedure Build(const AName: string);
    /// <summary>Basen aus den Fakten des Dialogs; APreferred vorgewählt, sonst die erste.</summary>
    procedure FillBases(APreferred: TAtlasVcsBranchBaseKind);
    /// <summary>Art der gewählten Basis; ADefault ohne Auswahl.</summary>
    function SelectedKind(ADefault: TAtlasVcsBranchBaseKind): TAtlasVcsBranchBaseKind;
    function SelectedBase(out ABase: TAtlasVcsBranchBase): Boolean;
    function NameState(out AText: string): Boolean;
    /// <summary>Hinweis unter dem Namen zeigen; True, wenn der Name gültig ist.</summary>
    function Refresh: Boolean;
    property NameEdit: TEdit read FNameEdit;
    property NameError: TLabel read FNameError;
    property BaseBox: TComboBox read FBaseBox;
    property Bases: TArray<TAtlasVcsBranchBase> read FBases;
  end;

  /// <summary>Gruppe „Git“ (#1289), nur unter Git sichtbar.</summary>
  TAtlasBranchGitPart = class(TAtlasBranchDialogPart)
  private
    FOptions: TAtlasVcsGitBranchOptions;
    FKey: string;
    FBox: TGroupBox;
    FFetchCheck: TCheckBox;
    FPushBox: TComboBox;
    FUncommittedPanel: TPanel;
    FUncommittedBox: TComboBox;
    FUncommittedCount: TLabel;
    FPlaceBox: TComboBox;
    FWorktreePanel: TPanel;
    FWorktreeEdit: TEdit;
    FError: TLabel;
    FWorktreeEdited: Boolean;
    procedure AddFetchAndPush;
    procedure AddUncommitted;
    procedure AddPlace;
    procedure WorktreeChanged(Sender: TObject);
    /// <summary>Zeilen nach Basis und Ablage; der worktree-Ordner folgt dem Namen, bis er von Hand geändert ist.
    /// </summary>
    procedure UpdateRows;
    procedure UpdateHeight;
  public
    procedure Build(const AOptions: TAtlasVcsGitBranchOptions; const AKey: string);
    /// <summary>Einträge der Auswahllisten (brauchen ein Fenster); nur leere Listen.</summary>
    procedure FillChoices;
    /// <summary>Zeilen, Hinweis und Höhe nach dem aktuellen Stand.</summary>
    procedure Refresh;
    function State(out AText: string): Boolean;
    /// <summary>Abruf, Push, worktree bzw. offene Änderungen in ARequest.</summary>
    procedure ApplyTo(const ABase: TAtlasVcsBranchBase; var ARequest: TAtlasVcsBranchRequest);
    property Box: TGroupBox read FBox;
    property FetchCheck: TCheckBox read FFetchCheck;
    /// <summary>0 beim ersten Push, 1 sofort.</summary>
    property PushBox: TComboBox read FPushBox;
    property UncommittedPanel: TPanel read FUncommittedPanel;
    /// <summary>0 mitnehmen, 1 beiseitelegen, -1 noch nicht gewählt.</summary>
    property UncommittedBox: TComboBox read FUncommittedBox;
    property UncommittedCount: TLabel read FUncommittedCount;
    /// <summary>0 umschalten, 1 eigener Ordner.</summary>
    property PlaceBox: TComboBox read FPlaceBox;
    /// <summary>Ordner des worktree; FolderPanel der SVN-Gruppe ist der Ordner fürs Auschecken.</summary>
    property WorktreePanel: TPanel read FWorktreePanel;
    property WorktreeEdit: TEdit read FWorktreeEdit;
    property Error: TLabel read FError;
  end;

  /// <summary>Nachricht, Ablageort, Danach, Ordner und Warnung bei gemischter Arbeitskopie (SVN, #1290).</summary>
  TAtlasBranchSvnPart = class(TAtlasBranchDialogPart)
  private
    FOptions: TAtlasVcsSvnBranchOptions;
    FMessagePanel: TPanel;
    FMessageEdit: TEdit;
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
    procedure AddMessage(const AMessage: string);
    procedure AddLocation;
    procedure AddAfterAndFolder;
    procedure AddMixed;
    procedure LocationChanged(Sender: TObject);
    procedure FolderChanged(Sender: TObject);
  public
    procedure Build(const AMessage: string; const AOptions: TAtlasVcsSvnBranchOptions);
    procedure FillChoices;
    /// <summary>Ort und Ordner aus den Mustern für den aktuellen Namen, solange nicht selbst geändert.</summary>
    procedure FollowName;
    /// <summary>Hinweise und Zeilen nach ARequest; ANameOk: Hinweis zum Ort nur bei gültigem Namen.</summary>
    procedure Refresh(const ARequest: TAtlasVcsBranchRequest; ANameOk: Boolean);
    /// <summary>Ort, Danach, Ordner und Externals wie im Dialog angezeigt.</summary>
    procedure ApplyTo(var ARequest: TAtlasVcsBranchRequest);
    property Options: TAtlasVcsSvnBranchOptions read FOptions;
    property MessagePanel: TPanel read FMessagePanel;
    property MessageEdit: TEdit read FMessageEdit;
    property LocationPanel: TPanel read FLocationPanel;
    property LocationEdit: TEdit read FLocationEdit;
    property LocationError: TLabel read FLocationError;
    property AfterPanel: TPanel read FAfterPanel;
    property FolderPanel: TPanel read FFolderPanel;
    property FolderEdit: TEdit read FFolderEdit;
    property MixedLabel: TLabel read FMixedLabel;
  end;

  /// <summary>Gruppe „Externals (n)“ (#1291).</summary>
  TAtlasBranchExternalsPart = class(TAtlasBranchDialogPart)
  private
    FBox: TGroupBox;
    FHint: TLabel;
    /// <summary>Je External die Auswahl (nil bei fester Revision), ihre Einträge und die Vorauswahl.</summary>
    FBoxes: TArray<TComboBox>;
    FChoices: TArray<TArray<TAtlasVcsExternalAction>>;
    FDefaults: TArray<TAtlasVcsExternalAction>;
    procedure AddHeader(AWidth: Integer);
    procedure AddRow(AParent: TWinControl; AIndex, AWidth: Integer);
  public
    procedure Build;
    procedure FillChoices;
    /// <summary>Wahl je External; Ask, solange eine Auswahl leer ist.</summary>
    function Actions: TArray<TAtlasVcsExternalAction>;
    function Chosen: Boolean;
    procedure Refresh;
    property Box: TGroupBox read FBox;
    property Hint: TLabel read FHint;
    /// <summary>Auswahl je External (nil bei fester Revision) und die Wahl hinter jedem Eintrag.</summary>
    property Boxes: TArray<TComboBox> read FBoxes;
    property Choices: TArray<TArray<TAtlasVcsExternalAction>> read FChoices;
  end;

  /// <summary>„Was passiert“: die Schritte in Klartext.</summary>
  TAtlasBranchStepsPart = class(TAtlasBranchDialogPart)
  private
    FSteps: TArray<TAtlasVcsBranchStep>;
    FMemo: TMemo;
    FServerHint: TLabel;
  public
    procedure Build;
    procedure Show(AKind: TAtlasVcsKind; const ASteps: TArray<TAtlasVcsBranchStep>);
    property Steps: TArray<TAtlasVcsBranchStep> read FSteps;
    property Memo: TMemo read FMemo;
    property ServerHint: TLabel read FServerHint;
  end;

  TAtlasBranchDialog = class(TAtlasDialog)
  private
    FFacts: TAtlasVcsBranchFacts;
    FInfoLabel: TLabel;
    FNeverAsk: TCheckBox;
    FCreateButton: TButton;
    FFilling: Boolean;
    /// <summary>Alle Steuerelemente angelegt: CreateWnd darf die Auswahllisten füllen.</summary>
    FControlsReady: Boolean;
    FNames: TAtlasBranchNamePart;
    FGit: TAtlasBranchGitPart;
    FSvn: TAtlasBranchSvnPart;
    FExternals: TAtlasBranchExternalsPart;
    FSteps: TAtlasBranchStepsPart;
    procedure SetupForm;
    procedure AddButtons(AOfferNeverAsk: Boolean);
    /// <summary>Einträge der Auswahllisten (brauchen ein Fenster); nur leere Listen.</summary>
    procedure FillChoices;
    procedure Changed(Sender: TObject);
    procedure CreateClick(Sender: TObject);
  protected
    procedure CreateWnd; override;
  public
    /// <summary>AFacts aus TAtlasVcsBranchPlan.Inspect; Vorgaben aus ASetup.</summary>
    constructor CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts;
      const ASetup: TAtlasBranchDialogSetup); overload;
    /// <summary>Wie oben mit TAtlasBranchDialogSetup.Make(AName, AMessage, '', AOfferNeverAsk).</summary>
    constructor CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts; const AName, AMessage: string;
      AOfferNeverAsk: Boolean); overload;
    /// <summary>Wie oben mit den SVN-Optionen als Vorgaben (#1290): Ort, Quelle, Danach, Ordner.</summary>
    constructor CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts; const AName, AMessage: string;
      const ASvn: TAtlasVcsSvnBranchOptions; AOfferNeverAsk: Boolean); overload;
    destructor Destroy; override;
    /// <summary>Werte vom Server sind da (InspectServer): Basen neu, „Anlegen“ frei, wenn der Rest stimmt.
    /// </summary>
    procedure ServerLoaded(const AFacts: TAtlasVcsBranchFacts);
    /// <summary>Gewählte Werte.</summary>
    function Request: TAtlasVcsBranchRequest;
    /// <summary>Name gültig, Basis gewählt, nichts mehr zu ermitteln.</summary>
    function CanCreate: Boolean;
    property Facts: TAtlasVcsBranchFacts read FFacts;
    property InfoLabel: TLabel read FInfoLabel;
    property NeverAsk: TCheckBox read FNeverAsk;
    property CreateButton: TButton read FCreateButton;
    property Names: TAtlasBranchNamePart read FNames;
    property Git: TAtlasBranchGitPart read FGit;
    property Svn: TAtlasBranchSvnPart read FSvn;
    property Externals: TAtlasBranchExternalsPart read FExternals;
    property Steps: TAtlasBranchStepsPart read FSteps;
  end;

implementation

uses
  System.Math,
  Atlas.Core.VersionControl.BranchNames,
  Atlas.UI.Strings,
  Atlas.UI.VersionControl.Strings,
  Atlas.Core.Style.Signal,
  Atlas.UI.Foundation.Theme;

const
  cGap = 8;
  cCaptionWidth = 96;
  cButtonWidth = 100;
  cBelowAll = 10000;
  cExternalRow = 26;
  cExternalRowsVisible = 5;
  cFolderWidth = 150;
  cChoiceWidth = 200;

{ Bausteine }

procedure Stack(AControl: TControl);
begin
  // alTop ordnet nach Top: weit unten anfangen, dann steht das neue Element unter allen bisherigen.
  AControl.Top := cBelowAll;
  AControl.Align := alTop;
end;

/// <summary>Zeile mit Beschriftung links, unter alle bisherigen gestapelt.</summary>
function Row(AOwner: TComponent; AParent: TWinControl; const ACaption: string; AHeight: Integer): TPanel;
var
  mCaption: TLabel;
begin
  Result := TPanel.Create(AOwner);
  Result.Parent := AParent;
  Result.Height := AHeight;
  Result.BevelOuter := bvNone;
  Stack(Result);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(cGap, cGap div 2, cGap, 0);
  mCaption := TLabel.Create(AOwner);
  mCaption.Parent := Result;
  mCaption.SetBounds(0, 5, cCaptionWidth, 17);
  mCaption.Caption := ACaption;
end;

/// <summary>Eingabefeld rechts neben der Beschriftung einer Zeile.</summary>
function RowEdit(AOwner: TComponent; ARow: TPanel; const AOnChange: TNotifyEvent): TEdit;
begin
  Result := TEdit.Create(AOwner);
  Result.Parent := ARow;
  Result.SetBounds(cCaptionWidth + cGap, 2, ARow.Width - cCaptionWidth - 2 * cGap, 23);
  Result.Anchors := [akLeft, akTop, akRight];
  Result.OnChange := AOnChange;
end;

/// <summary>Auswahlliste rechts neben der Beschriftung einer Zeile.</summary>
function RowChoice(AOwner: TComponent; ARow: TPanel; const AOnChange: TNotifyEvent): TComboBox;
begin
  Result := TComboBox.Create(AOwner);
  Result.Parent := ARow;
  Result.Style := csDropDownList;
  Result.SetBounds(cCaptionWidth + cGap, 2, ARow.Width - cCaptionWidth - 2 * cGap, 23);
  Result.Anchors := [akLeft, akTop, akRight];
  Result.OnChange := AOnChange;
end;

/// <summary>Hinweis unter den Feldern, eingerückt wie sie.</summary>
function NoteLabel(AOwner: TComponent; AParent: TWinControl; ATop, ABottom: Integer): TLabel;
begin
  Result := TLabel.Create(AOwner);
  Result.Parent := AParent;
  Stack(Result);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(cCaptionWidth + 2 * cGap, ATop, cGap, ABottom);
  Result.WordWrap := True;
end;

/// <summary>Roter Hinweis unter einem Feld.</summary>
function ErrorLabel(AOwner: TComponent; AParent: TWinControl; ATop: Integer): TLabel;
begin
  Result := NoteLabel(AOwner, AParent, ATop, 2);
  Result.Font.Color := TAtlasUiTheme.TextColor(TAtlasSignalKind.Error);
  // Mit seFont übergeht der Stil Font.Color.
  Result.StyleElements := Result.StyleElements - [seFont];
end;

/// <summary>Zelle der Externals-Tabelle; zu lange Pfade mit „…“ und vollständig als Hinweis.</summary>
function CellLabel(AOwner: TComponent; AParent: TWinControl; ALeft, AWidth: Integer; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(AOwner);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, 5, AWidth, 17);
  Result.AutoSize := False;
  Result.EllipsisPosition := epPathEllipsis;
  Result.Caption := ACaption;
  Result.Hint := ACaption;
  Result.ShowHint := True;
end;

/// <summary>Ort aus dem Feld ("^/Kasse/branches/x" → "Kasse/branches/x"); '' wenn es nicht mit ^/ beginnt.
/// </summary>
function LocationOf(const AText: string): string;
begin
  Result := Trim(AText);
  if Copy(Result, 1, 2) <> '^/' then
  begin
    Exit('');
  end;
  Result := Copy(Result, 3, MaxInt);
  while (Result <> '') and (Result[Length(Result)] = '/') do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

/// <summary>Text einer Basis in der Auswahl.</summary>
function BaseCaption(const ABase: TAtlasVcsBranchBase): string;
begin
  case ABase.Kind of
    TAtlasVcsBranchBaseKind.RemoteMain:
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchBaseRemote, [ABase.Name]);
    TAtlasVcsBranchBaseKind.LocalMain:
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchBaseLocal, [ABase.Name]);
    TAtlasVcsBranchBaseKind.Head:
      if ABase.Revision = '' then
      begin
        Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchBaseHead, [ABase.Name]);
      end
      else
      begin
        Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchBaseHeadRevision, [ABase.Name, ABase.Revision]);
      end;
    TAtlasVcsBranchBaseKind.WorkingCopy:
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchBaseWorkingCopy, [ABase.Name, ABase.Revision]);
  else
    if ABase.Name = '' then
    begin
      Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchBaseDetached);
    end
    else
    begin
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchBaseCurrent, [ABase.Name]);
    end;
  end;
end;

/// <summary>Zeilen für „Was passiert“: nummeriert, Serverschritte mit Zusatz.</summary>
function StepLines(AKind: TAtlasVcsKind; const ASteps: TArray<TAtlasVcsBranchStep>): TArray<string>;
var
  mIndex: Integer;
  mLine: string;
begin
  Result := nil;
  for mIndex := 0 to High(ASteps) do
  begin
    mLine := Format('%d. %s', [mIndex + 1, TAtlasVcsBranchPlan.StepText(AKind, ASteps[mIndex])]);
    if ASteps[mIndex].ChangesServer then
    begin
      mLine := mLine + '   ' + TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchOnServer);
    end;
    Result := Result + [mLine];
  end;
end;

/// <summary>Text einer Wahl in der Auswahl eines Externals.</summary>
function ExternalCaption(const AExternal: TAtlasVcsSvnExternal; AAction: TAtlasVcsExternalAction): string;
begin
  case AAction of
    TAtlasVcsExternalAction.Pin:
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchExternalPin,
        [TAtlasVcsBranchPlan.ExternalRevision(AExternal)]);
    TAtlasVcsExternalAction.Branch:
      Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchExternalBranch);
  else
    Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchExternalKeep);
  end;
end;

/// <summary>Quelle eines Externals wie in svn:externals, mit fester Revision.</summary>
function ExternalSource(const AExternal: TAtlasVcsSvnExternal): string;
begin
  if AExternal.Source <> '' then
  begin
    Result := '^/' + AExternal.Source;
  end
  else
  begin
    Result := AExternal.FullUrl;
  end;
  if AExternal.Revision <> '' then
  begin
    Result := Result + ' -r ' + AExternal.Revision;
  end;
end;

/// <summary>Festschreiben braucht die Revision der External-Arbeitskopie; mitverzweigen einen Ablageort (Layout
/// im Pfad des Packages; den Ort für den eingegebenen Namen löst ApplyExternals auf).</summary>
function ExternalChoices(const AExternal: TAtlasVcsSvnExternal;
  const ASvn: TAtlasVcsSvnBranchOptions): TArray<TAtlasVcsExternalAction>;
var
  mAction: TAtlasVcsExternalAction;
  mPath: string;
begin
  Result := nil;
  for mAction in [TAtlasVcsExternalAction.Pin, TAtlasVcsExternalAction.Keep, TAtlasVcsExternalAction.Branch] do
  begin
    if ((mAction = TAtlasVcsExternalAction.Pin) and (AExternal.WorkingRevision <> '')) or
      (mAction = TAtlasVcsExternalAction.Keep) or ((mAction = TAtlasVcsExternalAction.Branch) and
      TAtlasVcsBranchPlan.ExternalLocation(AExternal, ASvn, 'x', mPath)) then
    begin
      Result := Result + [mAction];
    end;
  end;
end;

/// <summary>Hinweis zum Ort: ohne erkennbares Layout bitten, ihn anzugeben; sonst muss er ein sicherer Pfad unter
/// ^/ sein.</summary>
function LocationError(const AText, ALocation: string): string;
begin
  if Trim(AText) = '' then
  begin
    Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchLocationMissing);
  end
  else if not TAtlasVcsBranchPlan.SafeName(ALocation) then
  begin
    Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchLocationInvalid);
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Werte vom Server werden noch ermittelt bzw. konnten nicht ermittelt werden; ohne Basis.</summary>
function InfoText(const AFacts: TAtlasVcsBranchFacts; ABaseCount: Integer): string;
begin
  Result := '';
  if AFacts.Outcome <> TAtlasVcsOutcome.Ok then
  begin
    Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchNoWorkingCopy, [AtlasVcsOutcomeName(AFacts.Outcome)]);
  end
  else if AFacts.NeedsServer then
  begin
    Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchLoading);
  end
  else if AFacts.ServerChecked and (AFacts.ServerOutcome <> TAtlasVcsOutcome.Ok) then
  begin
    Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchHeadUnknown, [AtlasVcsOutcomeName(AFacts.ServerOutcome)]);
  end
  else if ABaseCount = 0 then
  begin
    Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchNoBase);
  end;
end;

/// <summary>Vorgewählte Basis nach den Git- bzw. SVN-Vorgaben.</summary>
function PreferredBase(const AFacts: TAtlasVcsBranchFacts; const ASetup: TAtlasBranchDialogSetup):
  TAtlasVcsBranchBaseKind;
var
  mBase: TAtlasVcsBranchBase;
  mFound: Boolean;
begin
  Result := TAtlasVcsBranchBaseKind.Current;
  if AFacts.Kind = TAtlasVcsKind.Git then
  begin
    mFound := TAtlasVcsBranchPlan.DefaultBase(AFacts, ASetup.Git, mBase);
  end
  else
  begin
    mFound := TAtlasVcsBranchPlan.DefaultBase(AFacts, ASetup.Svn.Source, mBase);
  end;
  if mFound then
  begin
    Result := mBase.Kind;
  end;
end;

{ TAtlasBranchDialogSetup }

class function TAtlasBranchDialogSetup.Make(const AName, AMessage, AKey: string;
  AOfferNeverAsk: Boolean): TAtlasBranchDialogSetup;
begin
  Result.Name := AName;
  Result.Message := AMessage;
  Result.Key := AKey;
  Result.Git := TAtlasVcsGitBranchOptions.Classic;
  Result.Svn := TAtlasVcsSvnBranchOptions.Legacy;
  Result.OfferNeverAsk := AOfferNeverAsk;
end;

{ TAtlasBranchDialogPart }

constructor TAtlasBranchDialogPart.Create(ADialog: TAtlasBranchDialog);
begin
  inherited Create;
  FDialog := ADialog;
end;

{ TAtlasBranchNamePart }

procedure TAtlasBranchNamePart.Build(const AName: string);
var
  mPanel: TPanel;
begin
  mPanel := Row(FDialog, FDialog, TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchName), 28);
  FNameEdit := RowEdit(FDialog, mPanel, FDialog.Changed);
  FNameEdit.Text := AName;
  FNameError := ErrorLabel(FDialog, FDialog, 0);
  mPanel := Row(FDialog, FDialog, TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchBase), 28);
  FBaseBox := RowChoice(FDialog, mPanel, FDialog.Changed);
end;

procedure TAtlasBranchNamePart.FillBases(APreferred: TAtlasVcsBranchBaseKind);
var
  mBase: TAtlasVcsBranchBase;
  mIndex: Integer;
begin
  FDialog.FFilling := True;
  try
    FBases := TAtlasVcsBranchPlan.Bases(FDialog.FFacts);
    FBaseBox.Items.BeginUpdate;
    try
      FBaseBox.Items.Clear;
      for mBase in FBases do
      begin
        FBaseBox.Items.Add(BaseCaption(mBase));
      end;
    finally
      FBaseBox.Items.EndUpdate;
    end;
    FBaseBox.ItemIndex := -1;
    for mIndex := 0 to High(FBases) do
    begin
      if FBases[mIndex].Kind = APreferred then
      begin
        FBaseBox.ItemIndex := mIndex;
        Break;
      end;
    end;
    if (FBaseBox.ItemIndex < 0) and (Length(FBases) > 0) then
    begin
      FBaseBox.ItemIndex := 0;
    end;
  finally
    FDialog.FFilling := False;
  end;
  FDialog.Changed(nil);
end;

function TAtlasBranchNamePart.SelectedKind(ADefault: TAtlasVcsBranchBaseKind): TAtlasVcsBranchBaseKind;
var
  mBase: TAtlasVcsBranchBase;
begin
  Result := ADefault;
  if SelectedBase(mBase) then
  begin
    Result := mBase.Kind;
  end;
end;

function TAtlasBranchNamePart.SelectedBase(out ABase: TAtlasVcsBranchBase): Boolean;
begin
  ABase := TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Current, '', '');
  Result := (FBaseBox.ItemIndex >= 0) and (FBaseBox.ItemIndex <= High(FBases));
  if Result then
  begin
    ABase := FBases[FBaseBox.ItemIndex];
  end;
end;

function TAtlasBranchNamePart.NameState(out AText: string): Boolean;
var
  mName: string;
begin
  AText := '';
  mName := Trim(FNameEdit.Text);
  if mName = '' then
  begin
    AText := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchNameMissing);
  end
  else if (mName <> FNameEdit.Text) or not TAtlasVcsBranchNames.Valid(mName) or
    not TAtlasVcsBranchPlan.SafeName(mName) then
  begin
    AText := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchNameInvalid);
  end;
  Result := AText = '';
end;

function TAtlasBranchNamePart.Refresh: Boolean;
var
  mText: string;
begin
  Result := NameState(mText);
  FNameError.Caption := mText;
  FNameError.Visible := not Result;
end;

{ TAtlasBranchGitPart }

procedure TAtlasBranchGitPart.Build(const AOptions: TAtlasVcsGitBranchOptions; const AKey: string);
begin
  FOptions := AOptions;
  FKey := AKey;
  FBox := TGroupBox.Create(FDialog);
  FBox.Parent := FDialog;
  Stack(FBox);
  FBox.AlignWithMargins := True;
  FBox.Margins.SetBounds(cGap, 4, cGap, 4);
  FBox.Caption := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchGit);
  FBox.Height := FBox.ScaleValue(120);
  FBox.Visible := FDialog.FFacts.Kind = TAtlasVcsKind.Git;
  // Einträge der Auswahllisten erst mit Fenster (FillChoices).
  AddFetchAndPush;
  AddUncommitted;
  AddPlace;
  FError := ErrorLabel(FDialog, FBox, 0);
  if FBox.Visible then
  begin
    FDialog.Height := FDialog.Height + FDialog.ScaleValue(176);
    FDialog.Constraints.MinHeight := FDialog.Constraints.MinHeight + 176;
  end;
end;

procedure TAtlasBranchGitPart.AddFetchAndPush;
var
  mPanel: TPanel;
begin
  mPanel := Row(FDialog, FBox, '', 24);
  FFetchCheck := TCheckBox.Create(FDialog);
  FFetchCheck.Parent := mPanel;
  FFetchCheck.SetBounds(cCaptionWidth + cGap, 3, mPanel.Width - cCaptionWidth - 2 * cGap, 20);
  FFetchCheck.Anchors := [akLeft, akTop, akRight];
  FFetchCheck.Checked := FOptions.Base = TAtlasVcsGitBaseOption.Remote;
  FFetchCheck.OnClick := FDialog.Changed;
  mPanel := Row(FDialog, FBox, TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchPush), 28);
  FPushBox := RowChoice(FDialog, mPanel, FDialog.Changed);
end;

procedure TAtlasBranchGitPart.AddUncommitted;
const
  cBoxWidth = 240;
begin
  // Offene Änderungen: nur mit geänderten Dateien; „nachfragen“ lässt die Auswahl leer.
  FUncommittedPanel := Row(FDialog, FBox, TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchUncommitted), 28);
  FUncommittedBox := TComboBox.Create(FDialog);
  FUncommittedBox.Parent := FUncommittedPanel;
  FUncommittedBox.Style := csDropDownList;
  FUncommittedBox.SetBounds(cCaptionWidth + cGap, 2, cBoxWidth, 23);
  FUncommittedBox.OnChange := FDialog.Changed;
  FUncommittedCount := TLabel.Create(FDialog);
  FUncommittedCount.Parent := FUncommittedPanel;
  FUncommittedCount.SetBounds(cCaptionWidth + 2 * cGap + cBoxWidth, 5, 260, 17);
  FUncommittedCount.Caption := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchUncommittedCount,
    [FDialog.FFacts.LocalChanges]);
end;

procedure TAtlasBranchGitPart.AddPlace;
var
  mPanel: TPanel;
begin
  mPanel := Row(FDialog, FBox, TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchPlace), 28);
  FPlaceBox := RowChoice(FDialog, mPanel, FDialog.Changed);
  FWorktreePanel := Row(FDialog, FBox, TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchFolder), 28);
  FWorktreeEdit := RowEdit(FDialog, FWorktreePanel, WorktreeChanged);
end;

/// <summary>Eintrag 1 bei AOn, sonst 0.</summary>
function OnOffIndex(AOn: Boolean): Integer;
begin
  Result := 0;
  if AOn then
  begin
    Result := 1;
  end;
end;

procedure TAtlasBranchGitPart.FillChoices;
begin
  // Vorbelegung aus vcs.branch.git.*; „nachfragen“ lässt die Auswahl leer.
  if FPushBox.Items.Count = 0 then
  begin
    FPushBox.Items.Add(TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchPushLater));
    FPushBox.Items.Add(TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchPushNow));
    FPushBox.ItemIndex := OnOffIndex(FOptions.PushNow);
  end;
  if FUncommittedBox.Items.Count = 0 then
  begin
    FUncommittedBox.Items.Add(TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchCarry));
    FUncommittedBox.Items.Add(TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchStash));
    case FOptions.Uncommitted of
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
    FPlaceBox.Items.Add(TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchPlaceSwitch));
    FPlaceBox.Items.Add(TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchPlaceWorktree));
    FPlaceBox.ItemIndex := OnOffIndex(FOptions.Worktree);
  end;
end;

procedure TAtlasBranchGitPart.WorktreeChanged(Sender: TObject);
begin
  // Von Hand geändert: folgt dem Namen nicht mehr.
  if not FDialog.FFilling then
  begin
    FWorktreeEdited := True;
  end;
  FDialog.Changed(Sender);
end;

/// <summary>Zeile einblenden bzw. ausblenden; eingeblendet direkt unter AAfter (alTop ordnet nach Top).</summary>
procedure ShowRow(ARow, AAfter: TControl; AVisible: Boolean);
begin
  if AVisible and not ARow.Visible then
  begin
    ARow.Top := AAfter.Top + AAfter.Height + 1;
  end;
  ARow.Visible := AVisible;
end;

procedure TAtlasBranchGitPart.UpdateRows;
var
  mBase: TAtlasVcsBranchBase;
  mWasFilling: Boolean;
begin
  if FDialog.FFacts.Kind <> TAtlasVcsKind.Git then
  begin
    Exit;
  end;
  FDialog.FNames.SelectedBase(mBase);
  FFetchCheck.Enabled := mBase.Kind = TAtlasVcsBranchBaseKind.RemoteMain;
  FFetchCheck.Caption := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchFetch, [mBase.RemoteName,
    FDialog.FFacts.MainBranch]);
  ShowRow(FUncommittedPanel, FPushBox.Parent, (FDialog.FFacts.LocalChanges > 0) and (FPlaceBox.ItemIndex <> 1));
  ShowRow(FWorktreePanel, FPlaceBox.Parent, FPlaceBox.ItemIndex = 1);
  if not FWorktreePanel.Visible or FWorktreeEdited then
  begin
    Exit;
  end;
  mWasFilling := FDialog.FFilling;
  FDialog.FFilling := True;
  try
    FWorktreeEdit.Text := TAtlasVcsBranchPlan.WorktreePath(FDialog.FFacts.Root, FOptions.WorktreeFolder,
      Trim(FDialog.FNames.NameEdit.Text), FKey);
  finally
    FDialog.FFilling := mWasFilling;
  end;
end;

procedure TAtlasBranchGitPart.UpdateHeight;
var
  mHeight: Integer;
begin
  if not FBox.Visible then
  begin
    Exit;
  end;
  // Höhe nach den sichtbaren Zeilen: Überschrift, Abrufen, Server, Ablage, ggf. Änderungen, Ordner, Hinweis.
  mHeight := 24 + 28 + 2 * 32;
  if FUncommittedPanel.Visible then
  begin
    Inc(mHeight, 32);
  end;
  if FWorktreePanel.Visible then
  begin
    Inc(mHeight, 32);
  end;
  if FError.Visible then
  begin
    Inc(mHeight, 36);
  end;
  FBox.Height := mHeight;
end;

procedure TAtlasBranchGitPart.Refresh;
var
  mText: string;
begin
  UpdateRows;
  State(mText);
  FError.Caption := mText;
  if (mText <> '') and not FError.Visible then
  begin
    FError.Top := cBelowAll;
  end;
  FError.Visible := mText <> '';
  UpdateHeight;
end;

function TAtlasBranchGitPart.State(out AText: string): Boolean;
var
  mFolder: string;
begin
  AText := '';
  if FDialog.FFacts.Kind = TAtlasVcsKind.Git then
  begin
    mFolder := Trim(FWorktreeEdit.Text);
    if FUncommittedPanel.Visible and (FUncommittedBox.ItemIndex < 0) then
    begin
      AText := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchUncommittedChoose);
    end
    else if FWorktreePanel.Visible and not TAtlasVcsBranchPlan.SafeFolder(mFolder) then
    begin
      AText := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchFolderInvalid);
    end
    else if FWorktreePanel.Visible and DirectoryExists(mFolder) then
    begin
      AText := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchFolderExists, [mFolder]);
    end;
  end;
  Result := AText = '';
end;

procedure TAtlasBranchGitPart.ApplyTo(const ABase: TAtlasVcsBranchBase; var ARequest: TAtlasVcsBranchRequest);
begin
  // Abruf nur mit Basis vom Server; worktree oder offene Änderungen beiseitelegen.
  ARequest.Fetch := FFetchCheck.Checked and (ABase.Kind = TAtlasVcsBranchBaseKind.RemoteMain);
  ARequest.PushNow := FPushBox.ItemIndex = 1;
  if FPlaceBox.ItemIndex = 1 then
  begin
    ARequest.WorktreeFolder := Trim(FWorktreeEdit.Text);
  end
  else
  begin
    ARequest.Stash := FUncommittedPanel.Visible and (FUncommittedBox.ItemIndex = 1);
  end;
end;

{ TAtlasBranchSvnPart }

procedure TAtlasBranchSvnPart.Build(const AMessage: string; const AOptions: TAtlasVcsSvnBranchOptions);
var
  mSvn: Boolean;
begin
  FOptions := AOptions;
  mSvn := FDialog.FFacts.Kind = TAtlasVcsKind.Svn;
  AddMessage(AMessage);
  AddLocation;
  AddAfterAndFolder;
  AddMixed;
  // Nur svn copy hat eine Nachricht; Ort und Danach nur für SVN.
  FMessagePanel.Visible := mSvn;
  FLocationPanel.Visible := mSvn;
  FAfterPanel.Visible := mSvn;
  FFolderPanel.Visible := False;
  FLocationError.Visible := False;
  FMixedLabel.Visible := False;
end;

procedure TAtlasBranchSvnPart.AddMessage(const AMessage: string);
begin
  FMessagePanel := Row(FDialog, FDialog, TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchMessage), 28);
  FMessageEdit := RowEdit(FDialog, FMessagePanel, FDialog.Changed);
  FMessageEdit.Text := AMessage;
end;

procedure TAtlasBranchSvnPart.AddLocation;
begin
  FLocationPanel := Row(FDialog, FDialog, TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchLocation), 28);
  FLocationEdit := RowEdit(FDialog, FLocationPanel, LocationChanged);
  FLocationError := ErrorLabel(FDialog, FDialog, 0);
end;

procedure TAtlasBranchSvnPart.AddAfterAndFolder;
begin
  FAfterPanel := Row(FDialog, FDialog, TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchAfter), 28);
  FAfterBox := RowChoice(FDialog, FAfterPanel, FDialog.Changed);
  FFolderPanel := Row(FDialog, FDialog, TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchFolder), 28);
  FFolderEdit := RowEdit(FDialog, FFolderPanel, FolderChanged);
end;

procedure TAtlasBranchSvnPart.AddMixed;
begin
  FMixedLabel := ErrorLabel(FDialog, FDialog, 2);
  FMixedLabel.Caption := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchMixed, [FDialog.FFacts.Revision]);
end;

procedure TAtlasBranchSvnPart.FillChoices;
begin
  if FAfterBox.Items.Count = 0 then
  begin
    FAfterBox.Items.Add(TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchAfterSwitch));
    FAfterBox.Items.Add(TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchAfterCheckout));
    FAfterBox.Items.Add(TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchAfterNone));
    FAfterBox.ItemIndex := Ord(FOptions.After);
  end;
end;

procedure TAtlasBranchSvnPart.LocationChanged(Sender: TObject);
begin
  if not FDialog.FFilling then
  begin
    FLocationEdited := True;
  end;
  FDialog.Changed(Sender);
end;

procedure TAtlasBranchSvnPart.FolderChanged(Sender: TObject);
begin
  if not FDialog.FFilling then
  begin
    FFolderEdited := True;
  end;
  FDialog.Changed(Sender);
end;

/// <summary>Ort für AName als "^/…"; '' ohne Namen oder ohne erkennbares Layout.</summary>
function SuggestedLocation(const AFacts: TAtlasVcsBranchFacts; const ASvn: TAtlasVcsSvnBranchOptions;
  const AName: string): string;
var
  mPath: string;
begin
  Result := '';
  if (AName <> '') and TAtlasVcsBranchPlan.SvnLocation(AFacts, ASvn, AName, mPath) then
  begin
    Result := '^/' + mPath;
  end;
end;

/// <summary>Ordner fürs Auschecken für AName; '' ohne Namen.</summary>
function SuggestedFolder(const AFacts: TAtlasVcsBranchFacts; const ASvn: TAtlasVcsSvnBranchOptions;
  const AName: string): string;
begin
  Result := '';
  if AName <> '' then
  begin
    Result := TAtlasVcsBranchPlan.SvnCheckoutFolder(AFacts, ASvn, AName);
  end;
end;

procedure TAtlasBranchSvnPart.FollowName;
var
  mName: string;
begin
  if FDialog.FFacts.Kind <> TAtlasVcsKind.Svn then
  begin
    Exit;
  end;
  mName := Trim(FDialog.FNames.NameEdit.Text);
  FDialog.FFilling := True;
  try
    if not FLocationEdited then
    begin
      FLocationEdit.Text := SuggestedLocation(FDialog.FFacts, FOptions, mName);
    end;
    if not FFolderEdited then
    begin
      FFolderEdit.Text := SuggestedFolder(FDialog.FFacts, FOptions, mName);
    end;
  finally
    FDialog.FFilling := False;
  end;
end;

procedure TAtlasBranchSvnPart.Refresh(const ARequest: TAtlasVcsBranchRequest; ANameOk: Boolean);
var
  mBase: TAtlasVcsBranchBase;
begin
  if FDialog.FFacts.Kind <> TAtlasVcsKind.Svn then
  begin
    Exit;
  end;
  FLocationError.Caption := Atlas.UI.VersionControl.BranchDialog.LocationError(FLocationEdit.Text, ARequest.Location);
  FLocationError.Visible := (FLocationError.Caption <> '') and ANameOk;
  FFolderPanel.Visible := ARequest.After = TAtlasVcsSvnAfter.Checkout;
  FMixedLabel.Visible := FDialog.FFacts.MixedRevision and FDialog.FNames.SelectedBase(mBase) and
    (mBase.Kind = TAtlasVcsBranchBaseKind.WorkingCopy);
end;

procedure TAtlasBranchSvnPart.ApplyTo(var ARequest: TAtlasVcsBranchRequest);
begin
  ARequest.Location := LocationOf(FLocationEdit.Text);
  ARequest.After := FOptions.After;
  if (FAfterBox.ItemIndex >= 0) and (FAfterBox.ItemIndex <= Ord(High(TAtlasVcsSvnAfter))) then
  begin
    ARequest.After := TAtlasVcsSvnAfter(FAfterBox.ItemIndex);
  end;
  ARequest.CheckoutFolder := '';
  if ARequest.After = TAtlasVcsSvnAfter.Checkout then
  begin
    ARequest.CheckoutFolder := Trim(FFolderEdit.Text);
  end;
  // Externals (#1291): Wahl je Zeile, Orte der mitverzweigten Packages für den Namen.
  if Length(FDialog.FExternals.Boxes) > 0 then
  begin
    TAtlasVcsBranchPlan.ApplyExternals(ARequest, FDialog.FFacts, FOptions, FDialog.FExternals.Actions);
  end;
end;

{ TAtlasBranchExternalsPart }

procedure TAtlasBranchExternalsPart.Build;
var
  mScroll: TScrollBox;
  mFacts: TAtlasVcsBranchFacts;
  mIndex, mWidth: Integer;
begin
  mFacts := FDialog.FFacts;
  FBox := TGroupBox.Create(FDialog);
  FBox.Parent := FDialog;
  Stack(FBox);
  FBox.AlignWithMargins := True;
  FBox.Margins.SetBounds(cGap, 4, cGap, 4);
  FBox.Visible := (mFacts.Kind = TAtlasVcsKind.Svn) and mFacts.Externals;
  FHint := TLabel.Create(FDialog);
  FHint.Parent := FBox;
  FHint.Align := alBottom;
  FHint.AlignWithMargins := True;
  FHint.WordWrap := True;
  FBoxes := nil;
  FChoices := nil;
  FDefaults := nil;
  // Nicht gelesen (propget gescheitert): Hinweis wie vor #1291, die Externals gehen unverändert mit.
  if (mFacts.Kind <> TAtlasVcsKind.Svn) or (Length(mFacts.SvnExternals) = 0) then
  begin
    FBox.Height := FBox.ScaleValue(56);
    FBox.Caption := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchExternals);
    FHint.Align := alClient;
    FHint.Caption := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchExternalsKept);
    Exit;
  end;
  FBox.Caption := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchExternalsCount, [Length(mFacts.SvnExternals)]);
  FHint.Font.Color := TAtlasUiTheme.TextColor(TAtlasSignalKind.Error);
  // Mit seFont übergeht der Stil Font.Color.
  FHint.StyleElements := FHint.StyleElements - [seFont];
  FHint.Caption := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchExternalsChoose);
  FHint.Visible := False;
  FBox.Height := FBox.ScaleValue(44 + 20 + Min(Integer(Length(mFacts.SvnExternals)), cExternalRowsVisible) * cExternalRow);
  // Breite vorab wie im fertigen Dialog (ohne Fenster richtet alTop nicht aus); Anker gleichen den Rest aus.
  mWidth := FDialog.Width - 4 * cGap - 20;
  AddHeader(mWidth);
  mScroll := TScrollBox.Create(FDialog);
  mScroll.Parent := FBox;
  mScroll.Width := mWidth;
  mScroll.Align := alClient;
  mScroll.BorderStyle := bsNone;
  mScroll.VertScrollBar.Increment := mScroll.ScaleValue(cExternalRow);
  FDefaults := TAtlasVcsBranchPlan.DefaultActions(mFacts, FDialog.FSvn.Options);
  SetLength(FBoxes, Length(mFacts.SvnExternals));
  SetLength(FChoices, Length(mFacts.SvnExternals));
  for mIndex := 0 to High(mFacts.SvnExternals) do
  begin
    AddRow(mScroll, mIndex, mWidth);
  end;
end;

procedure TAtlasBranchExternalsPart.AddHeader(AWidth: Integer);
var
  mHeader: TPanel;
  mLabel: TLabel;
begin
  mHeader := TPanel.Create(FDialog);
  mHeader.Parent := FBox;
  mHeader.Width := AWidth;
  mHeader.Align := alTop;
  mHeader.Height := mHeader.ScaleValue(20);
  mHeader.BevelOuter := bvNone;
  mLabel := CellLabel(FDialog, mHeader, cGap, cFolderWidth,
    TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchExternalsFolder));
  mLabel.Font.Color := clGrayText;
  mLabel := CellLabel(FDialog, mHeader, cGap + cFolderWidth + cGap, 200,
    TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchExternalsSource));
  mLabel.Font.Color := clGrayText;
  mLabel := CellLabel(FDialog, mHeader, mHeader.Width - cChoiceWidth - cGap, cChoiceWidth,
    TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchExternalsInBranch));
  mLabel.Anchors := [akTop, akRight];
  mLabel.Font.Color := clGrayText;
end;

procedure TAtlasBranchExternalsPart.AddRow(AParent: TWinControl; AIndex, AWidth: Integer);
var
  mExternal: TAtlasVcsSvnExternal;
  mRow: TPanel;
  mLabel: TLabel;
begin
  mExternal := FDialog.FFacts.SvnExternals[AIndex];
  mRow := TPanel.Create(FDialog);
  mRow.Parent := AParent;
  mRow.Width := AWidth;
  mRow.Height := mRow.ScaleValue(cExternalRow);
  mRow.BevelOuter := bvNone;
  mRow.Top := mRow.ScaleValue(AIndex * cExternalRow);
  mRow.Align := alTop;
  CellLabel(FDialog, mRow, cGap, cFolderWidth, mExternal.Path);
  mLabel := CellLabel(FDialog, mRow, cGap + cFolderWidth + cGap, mRow.Width - cFolderWidth - cChoiceWidth - 4 * cGap,
    ExternalSource(mExternal));
  mLabel.Anchors := [akLeft, akTop, akRight];
  FChoices[AIndex] := nil;
  FBoxes[AIndex] := nil;
  // Feste Revision: bleibt, keine Auswahl.
  if mExternal.Fixed then
  begin
    mLabel := CellLabel(FDialog, mRow, mRow.Width - cChoiceWidth - cGap, cChoiceWidth,
      TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchExternalFixed, [TAtlasVcsBranchPlan.ExternalRevision(mExternal)]));
    mLabel.Anchors := [akTop, akRight];
    Exit;
  end;
  FChoices[AIndex] := ExternalChoices(mExternal, FDialog.FSvn.Options);
  FBoxes[AIndex] := TComboBox.Create(FDialog);
  FBoxes[AIndex].Parent := mRow;
  FBoxes[AIndex].Style := csDropDownList;
  FBoxes[AIndex].SetBounds(mRow.Width - cChoiceWidth - cGap, 1, cChoiceWidth, 23);
  FBoxes[AIndex].Anchors := [akTop, akRight];
  FBoxes[AIndex].OnChange := FDialog.Changed;
end;

procedure TAtlasBranchExternalsPart.FillChoices;
var
  mIndex, mChoice: Integer;
begin
  for mIndex := 0 to High(FBoxes) do
  begin
    if not Assigned(FBoxes[mIndex]) or (FBoxes[mIndex].Items.Count > 0) then
    begin
      Continue;
    end;
    for mChoice := 0 to High(FChoices[mIndex]) do
    begin
      FBoxes[mIndex].Items.Add(ExternalCaption(FDialog.FFacts.SvnExternals[mIndex], FChoices[mIndex][mChoice]));
    end;
    // Vorauswahl; Ask oder eine Wahl, die es hier nicht gibt: leer.
    FBoxes[mIndex].ItemIndex := -1;
    for mChoice := 0 to High(FChoices[mIndex]) do
    begin
      if (mIndex <= High(FDefaults)) and (FChoices[mIndex][mChoice] = FDefaults[mIndex]) then
      begin
        FBoxes[mIndex].ItemIndex := mChoice;
      end;
    end;
  end;
end;

function TAtlasBranchExternalsPart.Actions: TArray<TAtlasVcsExternalAction>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(FBoxes));
  for mIndex := 0 to High(FBoxes) do
  begin
    if not Assigned(FBoxes[mIndex]) then
    begin
      Result[mIndex] := TAtlasVcsExternalAction.Keep;
    end
    else if (FBoxes[mIndex].ItemIndex >= 0) and (FBoxes[mIndex].ItemIndex <= High(FChoices[mIndex])) then
    begin
      Result[mIndex] := FChoices[mIndex][FBoxes[mIndex].ItemIndex];
    end
    else
    begin
      Result[mIndex] := TAtlasVcsExternalAction.Ask;
    end;
  end;
end;

function TAtlasBranchExternalsPart.Chosen: Boolean;
var
  mAction: TAtlasVcsExternalAction;
begin
  for mAction in Actions do
  begin
    if mAction = TAtlasVcsExternalAction.Ask then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

procedure TAtlasBranchExternalsPart.Refresh;
begin
  if (FDialog.FFacts.Kind = TAtlasVcsKind.Svn) and (Length(FBoxes) > 0) then
  begin
    FHint.Visible := not Chosen;
  end;
end;

{ TAtlasBranchStepsPart }

procedure TAtlasBranchStepsPart.Build;
var
  mBox: TGroupBox;
begin
  mBox := TGroupBox.Create(FDialog);
  mBox.Parent := FDialog;
  mBox.Align := alClient;
  mBox.AlignWithMargins := True;
  mBox.Margins.SetBounds(cGap, 4, cGap, 0);
  mBox.Caption := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchWhatHappens);
  FServerHint := TLabel.Create(FDialog);
  FServerHint.Parent := mBox;
  FServerHint.Align := alBottom;
  FServerHint.AlignWithMargins := True;
  FServerHint.WordWrap := True;
  FServerHint.Caption := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchServerHint);
  FMemo := TMemo.Create(FDialog);
  FMemo.Parent := mBox;
  FMemo.Align := alClient;
  FMemo.AlignWithMargins := True;
  FMemo.ReadOnly := True;
  FMemo.ScrollBars := ssBoth;
  FMemo.WordWrap := False;
  FMemo.Font.Name := 'Consolas';
  FMemo.Font.Size := 9;
end;

procedure TAtlasBranchStepsPart.Show(AKind: TAtlasVcsKind; const ASteps: TArray<TAtlasVcsBranchStep>);
begin
  FSteps := ASteps;
  FMemo.Lines.Text := string.Join(sLineBreak, StepLines(AKind, FSteps));
  FServerHint.Visible := Length(TAtlasVcsBranchPlan.ServerStepsDone(FSteps, Length(FSteps))) > 0;
end;

{ TAtlasBranchDialog }

constructor TAtlasBranchDialog.CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts;
  const AName, AMessage: string; AOfferNeverAsk: Boolean);
begin
  CreateDialog(AOwner, AFacts, TAtlasBranchDialogSetup.Make(AName, AMessage, '', AOfferNeverAsk));
end;

constructor TAtlasBranchDialog.CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts;
  const AName, AMessage: string; const ASvn: TAtlasVcsSvnBranchOptions; AOfferNeverAsk: Boolean);
var
  mSetup: TAtlasBranchDialogSetup;
begin
  mSetup := TAtlasBranchDialogSetup.Make(AName, AMessage, '', AOfferNeverAsk);
  mSetup.Svn := ASvn;
  CreateDialog(AOwner, AFacts, mSetup);
end;

constructor TAtlasBranchDialog.CreateDialog(AOwner: TComponent; const AFacts: TAtlasVcsBranchFacts;
  const ASetup: TAtlasBranchDialogSetup);
begin
  inherited CreateDialog(AOwner, '', 0);
  FFacts := AFacts;
  FFilling := True;
  FNames := TAtlasBranchNamePart.Create(Self);
  FGit := TAtlasBranchGitPart.Create(Self);
  FSvn := TAtlasBranchSvnPart.Create(Self);
  FExternals := TAtlasBranchExternalsPart.Create(Self);
  FSteps := TAtlasBranchStepsPart.Create(Self);
  SetupForm;
  // Unten zuerst: die Knöpfe bleiben beim Verkleinern sichtbar.
  AddButtons(ASetup.OfferNeverAsk);
  FNames.Build(ASetup.Name);
  // Git-Optionen (#1289) gehören zur Basis: direkt darunter.
  FGit.Build(ASetup.Git, ASetup.Key);
  FSvn.Build(ASetup.Message, ASetup.Svn);
  FInfoLabel := NoteLabel(Self, Self, 2, 4);
  FExternals.Build;
  FSteps.Build;
  // Hat schon ein Steuerelement das Fenster erzwungen, kam CreateWnd zu früh: jetzt füllen. Sonst füllt CreateWnd,
  // sobald FillBases das Fenster braucht.
  FControlsReady := True;
  if HandleAllocated then
  begin
    FillChoices;
  end;
  FFilling := False;
  FNames.FillBases(PreferredBase(AFacts, ASetup));
end;

destructor TAtlasBranchDialog.Destroy;
begin
  // Ab hier baut Changed nichts mehr neu, auch wenn ein Steuerelement beim Abbau noch meldet.
  FFilling := True;
  FreeAndNil(FSteps);
  FreeAndNil(FExternals);
  FreeAndNil(FSvn);
  FreeAndNil(FGit);
  FreeAndNil(FNames);
  inherited;
end;

procedure TAtlasBranchDialog.SetupForm;
begin
  Caption := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchTitle);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Width := ScaleValue(720);
  Height := ScaleValue(520);
  Constraints.MinWidth := 520;
  Constraints.MinHeight := 420;
end;

procedure TAtlasBranchDialog.AddButtons(AOfferNeverAsk: Boolean);
var
  mBottom: TPanel;
  mCancel: TButton;
begin
  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := mBottom.ScaleValue(44);
  mBottom.BevelOuter := bvNone;
  FNeverAsk := TCheckBox.Create(Self);
  FNeverAsk.Parent := mBottom;
  FNeverAsk.SetBounds(cGap, 12, 360, 20);
  FNeverAsk.Caption := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchNeverAsk);
  FNeverAsk.Visible := AOfferNeverAsk;
  FCreateButton := TButton.Create(Self);
  FCreateButton.Parent := mBottom;
  FCreateButton.SetBounds(mBottom.Width - 2 * (cButtonWidth + cGap), 8, cButtonWidth, 28);
  FCreateButton.Anchors := [akTop, akRight];
  FCreateButton.Caption := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchCreate);
  FCreateButton.Default := True;
  FCreateButton.OnClick := CreateClick;
  mCancel := TButton.Create(Self);
  mCancel.Parent := mBottom;
  mCancel.SetBounds(mBottom.Width - (cButtonWidth + cGap), 8, cButtonWidth, 28);
  mCancel.Anchors := [akTop, akRight];
  mCancel.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCancel);
  mCancel.Cancel := True;
  mCancel.ModalResult := mrCancel;
end;

procedure TAtlasBranchDialog.CreateWnd;
var
  mFilling: Boolean;
begin
  inherited;
  // Combobox-Einträge brauchen ein Fenster: erst hier füllen (#1290). Das Fenster entsteht schon im
  // Konstruktor, sobald FillBases die Basen einträgt; FFilling bleibt dann gesetzt, Changed folgt dort.
  if not FControlsReady then
  begin
    Exit;
  end;
  mFilling := FFilling;
  FillChoices;
  if not mFilling then
  begin
    Changed(nil);
  end;
end;

procedure TAtlasBranchDialog.FillChoices;
var
  mFilling: Boolean;
begin
  mFilling := FFilling;
  FFilling := True;
  try
    FSvn.FillChoices;
    FGit.FillChoices;
    FExternals.FillChoices;
  finally
    FFilling := mFilling;
  end;
end;

procedure TAtlasBranchDialog.ServerLoaded(const AFacts: TAtlasVcsBranchFacts);
var
  mKind: TAtlasVcsBranchBaseKind;
begin
  mKind := FNames.SelectedKind(TAtlasVcsBranchBaseKind.Head);
  FFacts := AFacts;
  FNames.FillBases(mKind);
end;

function TAtlasBranchDialog.Request: TAtlasVcsBranchRequest;
var
  mBase: TAtlasVcsBranchBase;
begin
  FNames.SelectedBase(mBase);
  Result := TAtlasVcsBranchRequest.Make(FFacts.Kind, FNames.NameEdit.Text, mBase, FSvn.MessageEdit.Text);
  if FFacts.Kind = TAtlasVcsKind.Git then
  begin
    FGit.ApplyTo(mBase, Result);
  end
  else if FFacts.Kind = TAtlasVcsKind.Svn then
  begin
    FSvn.ApplyTo(Result);
  end;
end;

function TAtlasBranchDialog.CanCreate: Boolean;
var
  mText: string;
begin
  Result := FNames.NameState(mText) and FGit.State(mText) and not FFacts.NeedsServer and
    (FNames.BaseBox.ItemIndex >= 0) and (Length(FSteps.Steps) > 0) and FExternals.Chosen;
end;

procedure TAtlasBranchDialog.Changed(Sender: TObject);
var
  mNameOk: Boolean;
  mRequest: TAtlasVcsBranchRequest;
begin
  if FFilling then
  begin
    Exit;
  end;
  mNameOk := FNames.Refresh;
  FSvn.FollowName;
  FGit.Refresh;
  mRequest := Request;
  FSvn.Refresh(mRequest, mNameOk);
  FExternals.Refresh;
  FInfoLabel.Caption := InfoText(FFacts, Length(FNames.Bases));
  FInfoLabel.Visible := FInfoLabel.Caption <> '';
  if mNameOk and (FNames.BaseBox.ItemIndex >= 0) then
  begin
    FSteps.Show(FFacts.Kind, TAtlasVcsBranchPlan.Steps(mRequest));
  end
  else
  begin
    FSteps.Show(FFacts.Kind, nil);
  end;
  FCreateButton.Enabled := CanCreate;
end;

procedure TAtlasBranchDialog.CreateClick(Sender: TObject);
begin
  if CanCreate then
  begin
    ModalResult := mrOk;
  end;
end;

end.
