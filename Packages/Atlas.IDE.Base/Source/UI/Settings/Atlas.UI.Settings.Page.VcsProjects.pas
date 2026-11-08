unit Atlas.UI.Settings.Page.VcsProjects;

// Versionsverwaltung: Tabellen „Projekte“ (#1286) und „Server“ (#1287).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Menus,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Projects.Vcs,
  Atlas.Core.Vcs.ServerCheck,
  Atlas.UI.Strings,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>„Hinzufügen …“ der Tabelle Projekte der Versionsverwaltung (#1286): .dproj bzw. .groupproj (AFolder
  /// False) oder Ordner wählen; False bei Abbruch.</summary>
  TAtlasProjectBrowseEvent = reference to function(AFolder: Boolean; out APath: string): Boolean;

const
  cVcsButtonGap = 6;

type
  /// <summary>Tabelle „Server“ (#1287): AFolder prüfen; das Ergebnis meldet VcsServerDone.</summary>
  TAtlasVcsServerCheckEvent = reference to procedure(const AFolder: string);
  /// <summary>„Anmelden …“ für ACheck; True, wenn die Konsole offen ist (nach dem Schließen prüft der Aufrufer
  /// erneut und meldet VcsServerDone).</summary>
  TAtlasVcsServerLoginEvent = reference to function(const AFolder: string; const ACheck: TAtlasVcsServerCheck):
    Boolean;
  /// <summary>Zeile der Tabelle „Server“: Projekt (Anzeige), Ordner und letzter Zustand.</summary>
  TAtlasVcsServerRow = record
    Name: string;
    Folder: string;
    Check: TAtlasVcsServerCheck;
    Checking: Boolean;
  end;

type
  /// <summary>Versionsverwaltung: Tabellen „Projekte“ (#1286) und „Server“ (#1287).</summary>
  TAtlasSettingsVcsProjectsPart = class(TAtlasSettingsPagePart)
  private
    // Art und Hauptbranch je Projekt (#1286): Tabelle wie die Zuordnung auf der Seite Issue-Tracker.
    FVcsProjectList: TListView;
    FVcsProjectMatch: TEdit;
    FVcsProjectProvider: TAtlasChoiceBox;
    FVcsProjectMainBranch: TEdit;
    FVcsProjectNote: TLabel;
    FVcsProjectRemove: TButton;
    /// <summary>Persönliche Zeilen, wie die Seite sie zeigt; gespeichert werden die mit Pfad.</summary>
    FVcsProjects: TArray<TAtlasVcsProjectMapping>;
    /// <summary>Aktives Projekt, geöffnete .groupproj und Zeile aus der .atlas (beim Aufbau der Tabelle).</summary>
    FVcsContext: TAtlasVcsProjectContext;
    FVcsProjectSelected: Integer;
    FVcsProjectFilling: Boolean;
    FOnVcsContext: TFunc<TAtlasVcsProjectContext>;
    /// <summary>Tabelle Projekte (#1286): Art und Hauptbranch je .dproj, .groupproj oder Ordner.</summary>
    procedure AddVcsProjectsSection;
    function VcsProjectEditable: Boolean;
    procedure VcsProjectShowItem(AIndex: Integer);
    procedure VcsProjectFillFields;
    procedure VcsProjectNoteFor(const AMapping: TAtlasVcsProjectMapping);
    procedure VcsProjectSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure VcsProjectDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure VcsProjectMatchChange(Sender: TObject);
    procedure VcsProjectProviderChange(Sender: TObject);
    procedure VcsProjectMainBranchChange(Sender: TObject);
    procedure VcsProjectRemoveClick(Sender: TObject);
    /// <summary>Zeile für AMatch anlegen (Art AProvider) bzw. wählen.</summary>
    procedure VcsProjectAdd(const AMatch, AProvider: string);
  public
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    function VcsProjectRows: TArray<TAtlasVcsProjectMapping>;
    procedure WindowReady; override;
    /// <summary>Tabelle Projekte der Versionsverwaltung neu aufbauen; ohne Fenster folgt es in CreateWnd.
    /// </summary>
    procedure RefreshVcsProjects;
    /// <summary>Tabelle Projekte (#1286): aktives Projekt, geöffnete .groupproj und Zeile aus der .atlas; nil =
    /// ohne Projekt.</summary>
    property OnVcsContext: TFunc<TAtlasVcsProjectContext> read FOnVcsContext write FOnVcsContext;
    /// <summary>Zum Testen: Art und Hauptbranch je Projekt (#1286).</summary>
    property VcsProjectList: TListView read FVcsProjectList;
    property VcsProjectMatch: TEdit read FVcsProjectMatch;
    property VcsProjectProvider: TAtlasChoiceBox read FVcsProjectProvider;
    property VcsProjectMainBranch: TEdit read FVcsProjectMainBranch;
    property VcsProjectNote: TLabel read FVcsProjectNote;
    property VcsProjectRemove: TButton read FVcsProjectRemove;
    /// <summary>Persönliche Zeilen, wie die Seite sie gerade zeigt.</summary>
    property VcsProjects: TArray<TAtlasVcsProjectMapping> read FVcsProjects;
    property VcsContext: TAtlasVcsProjectContext read FVcsContext;
  end;

  /// <summary>Knöpfe „Aktuelles Projekt“ und „Hinzufügen …“ der Tabelle Projekte der Versionsverwaltung (#1286).
  /// </summary>
  TAtlasSettingsVcsProjectAddPart = class(TAtlasSettingsPagePart)
  private
    FOnBrowseProject: TAtlasProjectBrowseEvent;
    FAddCurrent: TButton;
    FAdd: TButton;
    FAddMenu: TPopupMenu;
    function Projects: TAtlasSettingsVcsProjectsPart;
    procedure AddMenuItem(AId: TAtlasTextId; AClick: TNotifyEvent);
    /// <summary>„Hinzufügen …“ ohne OnBrowseProject: Datei- bzw. Ordnerauswahl von Windows.</summary>
    function BrowseProject(AFolder: Boolean; out APath: string): Boolean;
    procedure AddCurrentClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure AddFileClick(Sender: TObject);
    procedure AddFolderClick(Sender: TObject);
  public
    /// <summary>Knöpfe links in der Zeile APanel; „Hinzufügen …“ klappt Projektdatei oder Ordner auf (z. B. ein
    /// Paketordner aus SVN-Externals).</summary>
    procedure AddButtons(APanel: TWinControl);
    /// <summary>„Aktuelles Projekt“ nur mit aktivem Projekt.</summary>
    procedure AllowCurrent(AValue: Boolean);
    /// <summary>„Hinzufügen …“ der Projekttabellen (#1261, #1286); nil = Datei- bzw. Ordnerauswahl von Windows.
    /// </summary>
    property OnBrowseProject: TAtlasProjectBrowseEvent read FOnBrowseProject write FOnBrowseProject;
    /// <summary>Zum Testen.</summary>
    property AddCurrentButton: TButton read FAddCurrent;
    property AddMenu: TPopupMenu read FAddMenu;
  end;

  TAtlasSettingsVcsServersPart = class(TAtlasSettingsPagePart)
  private
    // Serverzugang (#1287): Zeilen aus aktuellem Projekt und Tabelle Projekte, Zustand nur aus der Sitzung.
    FVcsServerList: TListView;
    FVcsServerCheck: TButton;
    FVcsServerCheckAll: TButton;
    FVcsServerLogin: TButton;
    FVcsServerNote: TLabel;
    FVcsServerRows: TArray<TAtlasVcsServerRow>;
    FVcsServerSelected: Integer;
    /// <summary>Ordner aus „prüfen …“ der Willkommensseite, der nicht in der Tabelle Projekte steht.</summary>
    FVcsServerExtra: string;
    FOnVcsServerState: TFunc<string, TAtlasVcsServerCheck>;
    FOnVcsServerCheck: TAtlasVcsServerCheckEvent;
    FOnVcsServerLogin: TAtlasVcsServerLoginEvent;
    /// <summary>Tabelle „Server“ (#1287).</summary>
    procedure AddVcsServersSection;
    /// <summary>Zeile für AFolder, je Ordner einmal; Zustand aus OnVcsServerState.</summary>
    procedure AddServerRow(const AName, AFolder: string);
    procedure CollectServerRows;
    procedure FillServerList;
    procedure VcsServerShowItem(AIndex: Integer);
    procedure VcsServerFillButtons;
    procedure VcsServerStart(AIndex: Integer);
    procedure VcsServerSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure VcsServerCheckClick(Sender: TObject);
    procedure VcsServerCheckAllClick(Sender: TObject);
    procedure VcsServerLoginClick(Sender: TObject);
  public
    procedure Build;
    /// <summary>Tabelle „Server“ (#1287): Zeile je Projekt (aktuelles Projekt, Zeilen der Tabelle Projekte), je
    /// Ordner einmal; Zustand aus OnVcsServerState. Ohne Fenster folgt es in CreateWnd.</summary>
    procedure RefreshVcsServers;
    /// <summary>„Anmeldung am Server nötig – prüfen …“ (#1287): Zeile für AFolder zeigen (auch ohne Zeile in der
    /// Tabelle Projekte), wählen und prüfen.</summary>
    procedure RevealVcsServer(const AFolder: string);
    /// <summary>Ergebnis einer Prüfung für AFolder zeigen.</summary>
    procedure VcsServerDone(const AFolder: string; const ACheck: TAtlasVcsServerCheck);
    /// <summary>Spalte Zustand: „nicht geprüft“, „wird geprüft …“, „erreichbar · geprüft 14:05“, „Anmeldung nötig“ …
    /// </summary>
    class function VcsServerStateText(const ACheck: TAtlasVcsServerCheck; AChecking: Boolean): string; static;
    /// <summary>Letztes Ergebnis je Ordner aus dieser Sitzung; nil = „nicht geprüft“.</summary>
    property OnVcsServerState: TFunc<string, TAtlasVcsServerCheck> read FOnVcsServerState write FOnVcsServerState;
    /// <summary>„Prüfen“ im Hintergrund; nil = Knöpfe gesperrt.</summary>
    property OnVcsServerCheck: TAtlasVcsServerCheckEvent read FOnVcsServerCheck write FOnVcsServerCheck;
    property OnVcsServerLogin: TAtlasVcsServerLoginEvent read FOnVcsServerLogin write FOnVcsServerLogin;
    /// <summary>Zum Testen: Serverzugang (#1287).</summary>
    property VcsServerList: TListView read FVcsServerList;
    property VcsServerCheck: TButton read FVcsServerCheck;
    property VcsServerCheckAll: TButton read FVcsServerCheckAll;
    property VcsServerLogin: TButton read FVcsServerLogin;
    property VcsServerNote: TLabel read FVcsServerNote;
  end;

implementation

uses
  Vcl.Themes,
  System.Math,
  System.StrUtils,
  Vcl.Graphics,
  Vcl.Dialogs,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.ServerAccess,
  Atlas.UI.Settings.Page.Sheets,
  Atlas.Core.Projects.Matching,
  Atlas.UI.Settings.Page.Vcs,
  Atlas.UI.Settings.Page.VcsProject;

const
  /// <summary>Spalten, Felder und Knöpfe der Tabellen Projekte und Server der Versionsverwaltung (#1286, #1287).
  /// </summary>
  cVcsMatchColumn = 230;
  cVcsKindColumn = 90;
  cVcsBranchColumn = 100;
  cVcsSourceColumn = 150;
  cVcsWideField = 376;
  cVcsField = 180;
  cVcsAddCurrentWidth = 180;
  cVcsAddWidth = 110;
  cVcsRemoveWidth = 100;
  cVcsServerProjectColumn = 170;
  cVcsServerServerColumn = 200;
  cVcsServerStateColumn = 180;
  cVcsCheckWidth = 100;
  cVcsCheckAllWidth = 110;

/// <summary>Überdeckt die .atlas die persönliche Zeile AMapping (dann wirkt sie nicht)?</summary>
function VcsProjectCovered(const AContext: TAtlasVcsProjectContext; const AMapping: TAtlasVcsProjectMapping): Boolean;
begin
  Result := TAtlasVcsProjects.Covered(AMapping, AContext.HasTeam, AContext.ProjectFile,
    AContext.GroupFile);
end;

/// <summary>Spalte Quelle: aus der .atlas, überdeckt oder persönlich.</summary>
function VcsProjectSourceText(const AContext: TAtlasVcsProjectContext;
  const AMapping: TAtlasVcsProjectMapping): string;
begin
  if AMapping.ReadOnly then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectTeam);
  end
  else if VcsProjectCovered(AContext, AMapping) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectCovered);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectPersonal);
  end;
end;

/// <summary>Gespeicherte Zeilen: mit Pfad, je Pfad die erste.</summary>
function VcsProjectsJson(const AProjects: TArray<TAtlasVcsProjectMapping>): string;
var
  mKept: TArray<TAtlasVcsProjectMapping>;
  mMapping: TAtlasVcsProjectMapping;
begin
  mKept := nil;
  for mMapping in AProjects do
  begin
    if (mMapping.Match <> '') and (TAtlasVcsProjects.IndexOfMatch(mKept, mMapping.Match) < 0) then
    begin
      mKept := mKept + [mMapping];
    end;
  end;
  Result := TAtlasVcsProjects.ToJson(mKept);
end;

{ TAtlasSettingsVcsProjectsPart }

procedure TAtlasSettingsVcsProjectsPart.Build;
begin
  AddVcsProjectsSection;
end;

procedure TAtlasSettingsVcsProjectsPart.AddVcsProjectsSection;
var
  mPanel: TWinControl;
  mHint: TLabel;
begin
  FVcsProjectSelected := -1;
  FVcsContext := TAtlasVcsProjectContext.Empty;
  AddTitle(TAtlasTextId.SettingsVcsProjects);
  mPanel := AddPanel(110);
  // Die Zeilen erst mit Fenster (RefreshVcsProjects, auch aus CreateWnd).
  FVcsProjectList := TListView.Create(FPage);
  FVcsProjectList.Parent := mPanel;
  FVcsProjectList.Align := alClient;
  FVcsProjectList.ViewStyle := vsReport;
  FVcsProjectList.ReadOnly := True;
  FVcsProjectList.RowSelect := True;
  FVcsProjectList.HideSelection := False;
  FVcsProjectList.OnSelectItem := VcsProjectSelectItem;
  FVcsProjectList.OnCustomDrawItem := VcsProjectDrawItem;
  TAtlasSettingsPageSheets.AddListColumn(FVcsProjectList, TAtlasTextId.SettingsIssuesProjectMatch, cVcsMatchColumn);
  TAtlasSettingsPageSheets.AddListColumn(FVcsProjectList, TAtlasTextId.SettingsVcsProjectsKind, cVcsKindColumn);
  TAtlasSettingsPageSheets.AddListColumn(FVcsProjectList, TAtlasTextId.SettingsVcsProjectsMainBranch, cVcsBranchColumn);
  TAtlasSettingsPageSheets.AddListColumn(FVcsProjectList, TAtlasTextId.SettingsIssuesProjectSource, cVcsSourceColumn);
  FVcsProjectMatch := TEdit.Create(FPage);
  FVcsProjectMatch.OnChange := VcsProjectMatchChange;
  mPanel := AddFieldRow(TAtlasTextId.SettingsIssuesProjectMatch, FVcsProjectMatch, cVcsWideField);
  FVcsProjectMatch.Anchors := [akLeft, akTop, akRight];
  Attach(mPanel, FVcsProjectList);
  // Reihenfolge wie die Werte von vcs.projects[].provider (auto, git, svn, off).
  FVcsProjectProvider := TAtlasChoiceBox.Create(FPage);
  FVcsProjectProvider.OnChange := VcsProjectProviderChange;
  Attach(AddFieldRow(TAtlasTextId.SettingsVcsProjectsKind, FVcsProjectProvider, cVcsField), FVcsProjectList);
  FVcsProjectProvider.SetChoices(TArray<string>.Create(TAtlasSettingsVcsPart.VcsProviderCaption('auto'),
    TAtlasSettingsVcsPart.VcsProviderCaption('git'),
    TAtlasSettingsVcsPart.VcsProviderCaption('svn'), TAtlasSettingsVcsPart.VcsProviderCaption('off')));
  FVcsProjectMainBranch := TEdit.Create(FPage);
  FVcsProjectMainBranch.OnChange := VcsProjectMainBranchChange;
  Attach(AddFieldRow(TAtlasTextId.SettingsVcsProjectsMainBranch, FVcsProjectMainBranch, cVcsField),
    FVcsProjectList);
  FVcsProjectMainBranch.TextHint := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsGuess);
  // Grund, warum eine Zeile nicht greift oder nicht übernommen wird (.atlas, Pfad doppelt, Leerraum).
  mPanel := AddPanel(18);
  FVcsProjectNote := TLabel.Create(FPage);
  FVcsProjectNote.Parent := mPanel;
  FVcsProjectNote.Left := 90;
  FVcsProjectNote.Top := 1;
  FVcsProjectNote.Font.Color := clRed;
  Attach(mPanel, FVcsProjectList);
  mPanel := AddPanel(32);
  FPage.Part<TAtlasSettingsVcsProjectAddPart>.AddButtons(mPanel);
  FVcsProjectRemove := AddRowButton(mPanel, cVcsAddCurrentWidth + cVcsAddWidth + cVcsButtonGap + cVcsButtonGap,
    cVcsRemoveWidth, TAtlasTextId.SettingsIssuesConnectionRemove, VcsProjectRemoveClick);
  Attach(mPanel, FVcsProjectList);
  mHint := AddWrappedLabel(52, TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsHint));
  mHint.Font.Color := clGrayText;
  Attach(mHint.Parent, FVcsProjectList);
end;

function TAtlasSettingsVcsProjectsPart.VcsProjectRows: TArray<TAtlasVcsProjectMapping>;
begin
  Result := FVcsProjects + FVcsContext.Team;
end;

function TAtlasSettingsVcsProjectsPart.VcsProjectEditable: Boolean;
begin
  Result := (FVcsProjectSelected >= 0) and (FVcsProjectSelected < Length(FVcsProjects));
end;

procedure TAtlasSettingsVcsProjectsPart.VcsProjectShowItem(AIndex: Integer);
var
  mRows: TArray<TAtlasVcsProjectMapping>;
  mItem: TListItem;
  mBranch: string;
begin
  mRows := VcsProjectRows;
  if (AIndex < 0) or (AIndex > High(mRows)) or not ListReady(FVcsProjectList) or
    (AIndex >= FVcsProjectList.Items.Count) then
  begin
    Exit;
  end;
  mItem := FVcsProjectList.Items[AIndex];
  mItem.Caption := mRows[AIndex].Match;
  mBranch := mRows[AIndex].MainBranch;
  if mBranch = '' then
  begin
    mBranch := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsGuess);
  end;
  mItem.SubItems.Clear;
  mItem.SubItems.Add(FPage.Part<TAtlasSettingsVcsPart>.VcsProviderCaption(mRows[AIndex].Provider));
  mItem.SubItems.Add(mBranch);
  mItem.SubItems.Add(VcsProjectSourceText(FVcsContext, mRows[AIndex]));
end;

procedure TAtlasSettingsVcsProjectsPart.RefreshVcsProjects;
var
  mRows: TArray<TAtlasVcsProjectMapping>;
  mIndex: Integer;
begin
  if FVcsProjectList = nil then
  begin
    Exit;
  end;
  FVcsContext := TAtlasVcsProjectContext.Empty;
  if Assigned(FOnVcsContext) then
  begin
    FVcsContext := FOnVcsContext();
  end;
  mRows := VcsProjectRows;
  if FVcsProjectSelected > High(mRows) then
  begin
    FVcsProjectSelected := High(mRows);
  end;
  if ListReady(FVcsProjectList) then
  begin
    FVcsProjectFilling := True;
    FVcsProjectList.Items.BeginUpdate;
    try
      FVcsProjectList.Items.Clear;
      for mIndex := 0 to High(mRows) do
      begin
        FVcsProjectList.Items.Add;
        VcsProjectShowItem(mIndex);
      end;
      if FVcsProjectSelected >= 0 then
      begin
        FVcsProjectList.Items[FVcsProjectSelected].Selected := True;
      end;
    finally
      FVcsProjectList.Items.EndUpdate;
      FVcsProjectFilling := False;
    end;
  end;
  VcsProjectFillFields;
  FPage.Part<TAtlasSettingsVcsServersPart>.RefreshVcsServers;
end;

procedure TAtlasSettingsVcsProjectsPart.VcsProjectNoteFor(const AMapping: TAtlasVcsProjectMapping);
begin
  if AMapping.ReadOnly then
  begin
    FVcsProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectReadOnly);
  end
  else if VcsProjectCovered(FVcsContext, AMapping) then
  begin
    FVcsProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsCoveredHint);
  end
  else
  begin
    FVcsProjectNote.Caption := '';
  end;
end;

procedure TAtlasSettingsVcsProjectsPart.VcsProjectFillFields;
var
  mRows: TArray<TAtlasVcsProjectMapping>;
  mSelected, mEditable: Boolean;
begin
  mRows := VcsProjectRows;
  mSelected := (FVcsProjectSelected >= 0) and (FVcsProjectSelected <= High(mRows));
  mEditable := VcsProjectEditable;
  FVcsProjectFilling := True;
  try
    if mSelected then
    begin
      FVcsProjectMatch.Text := mRows[FVcsProjectSelected].Match;
      FVcsProjectMainBranch.Text := mRows[FVcsProjectSelected].MainBranch;
      FVcsProjectProvider.Choice := Max(0, IndexText(mRows[FVcsProjectSelected].Provider,
        ['auto', 'git', 'svn', 'off']));
      VcsProjectNoteFor(mRows[FVcsProjectSelected]);
    end
    else
    begin
      FVcsProjectMatch.Text := '';
      FVcsProjectMainBranch.Text := '';
      FVcsProjectProvider.Choice := -1;
      FVcsProjectNote.Caption := '';
    end;
  finally
    FVcsProjectFilling := False;
  end;
  Allow(FVcsProjectMatch, mEditable);
  Allow(FVcsProjectProvider, mEditable);
  Allow(FVcsProjectMainBranch, mEditable);
  Allow(FVcsProjectRemove, mEditable);
  FPage.Part<TAtlasSettingsVcsProjectAddPart>.AllowCurrent(FVcsContext.ProjectFile <> '');
end;

procedure TAtlasSettingsVcsProjectsPart.VcsProjectSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FVcsProjectFilling or not Selected or (Item = nil) then
  begin
    Exit;
  end;
  FVcsProjectSelected := Item.Index;
  VcsProjectFillFields;
end;

procedure TAtlasSettingsVcsProjectsPart.VcsProjectDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mRows: TArray<TAtlasVcsProjectMapping>;
begin
  // Von der .atlas überdeckte persönliche Zeile grau.
  mRows := VcsProjectRows;
  if (Item <> nil) and (Item.Index <= High(mRows)) and VcsProjectCovered(FVcsContext, mRows[Item.Index]) then
  begin
    // Hintergrund in der Stilfarbe, sonst zeichnet die Zeile auf weißem clWindow (dunkles Thema).
    if not (cdsSelected in State) then
    begin
      Sender.Canvas.Brush.Color := StyleServices(Sender).GetSystemColor(clWindow);
    end;
    Sender.Canvas.Font.Color := StyleServices(Sender).GetSystemColor(clGrayText);
  end;
  DefaultDraw := True;
end;

procedure TAtlasSettingsVcsProjectsPart.VcsProjectMatchChange(Sender: TObject);
var
  mMatch: string;
  mOther: Integer;
begin
  if FVcsProjectFilling or not VcsProjectEditable then
  begin
    Exit;
  end;
  mMatch := Trim(FVcsProjectMatch.Text);
  // Ein Pfad hat höchstens eine persönliche Zeile.
  mOther := TAtlasVcsProjects.IndexOfMatch(FVcsProjects, mMatch);
  if (mMatch <> '') and (mOther >= 0) and (mOther <> FVcsProjectSelected) then
  begin
    FVcsProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatchTaken);
    Exit;
  end;
  FVcsProjects[FVcsProjectSelected].Match := mMatch;
  VcsProjectNoteFor(FVcsProjects[FVcsProjectSelected]);
  VcsProjectShowItem(FVcsProjectSelected);
end;

procedure TAtlasSettingsVcsProjectsPart.VcsProjectProviderChange(Sender: TObject);
var
  mChoice: Integer;
begin
  mChoice := FVcsProjectProvider.Choice;
  if FVcsProjectFilling or not VcsProjectEditable or (mChoice < 0) or (mChoice > 3) then
  begin
    Exit;
  end;
  case mChoice of
    1:
      FVcsProjects[FVcsProjectSelected].Provider := 'git';
    2:
      FVcsProjects[FVcsProjectSelected].Provider := 'svn';
    3:
      FVcsProjects[FVcsProjectSelected].Provider := 'off';
  else
    FVcsProjects[FVcsProjectSelected].Provider := 'auto';
  end;
  VcsProjectShowItem(FVcsProjectSelected);
end;

procedure TAtlasSettingsVcsProjectsPart.VcsProjectMainBranchChange(Sender: TObject);
var
  mBranch: string;
  mIndex: Integer;
begin
  if FVcsProjectFilling or not VcsProjectEditable then
  begin
    Exit;
  end;
  mBranch := Trim(FVcsProjectMainBranch.Text);
  // Wie der Server (vcs.projects[].mainBranch): ein Branchname ohne Leerraum.
  for mIndex := 1 to Length(mBranch) do
  begin
    if CharInSet(mBranch[mIndex], [' ', #9]) then
    begin
      FVcsProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsBranchInvalid);
      Exit;
    end;
  end;
  FVcsProjects[FVcsProjectSelected].MainBranch := mBranch;
  VcsProjectNoteFor(FVcsProjects[FVcsProjectSelected]);
  VcsProjectShowItem(FVcsProjectSelected);
end;

procedure TAtlasSettingsVcsProjectsPart.VcsProjectAdd(const AMatch, AProvider: string);
var
  mIndex: Integer;
begin
  if Trim(AMatch) = '' then
  begin
    Exit;
  end;
  mIndex := TAtlasVcsProjects.IndexOfMatch(FVcsProjects, AMatch);
  if mIndex < 0 then
  begin
    FVcsProjects := FVcsProjects + [TAtlasVcsProjectMapping.Create(AMatch, AProvider, '')];
    mIndex := High(FVcsProjects);
  end;
  FVcsProjectSelected := mIndex;
  RefreshVcsProjects;
  if FVcsProjectMainBranch.CanFocus and FVcsProjectMainBranch.Showing then
  begin
    FVcsProjectMainBranch.SetFocus;
  end;
end;

procedure TAtlasSettingsVcsProjectsPart.VcsProjectRemoveClick(Sender: TObject);
begin
  if not VcsProjectEditable then
  begin
    Exit;
  end;
  Delete(FVcsProjects, FVcsProjectSelected, 1);
  if FVcsProjectSelected > High(VcsProjectRows) then
  begin
    FVcsProjectSelected := High(VcsProjectRows);
  end;
  RefreshVcsProjects;
end;

procedure TAtlasSettingsVcsProjectsPart.BindMarks;
begin
  FPage.Marks.Bind(FVcsProjectList, ['VcsProjects']);
end;

procedure TAtlasSettingsVcsProjectsPart.WindowReady;
begin
  RefreshVcsProjects;
end;

procedure TAtlasSettingsVcsProjectsPart.Load(const ASettings: TAtlasPluginSettings);
begin
  FVcsProjects := TAtlasVcsProjects.Read(ASettings.VcsProjects);
  FVcsProjectSelected := -1;
  if Length(FVcsProjects) > 0 then
  begin
    FVcsProjectSelected := 0;
  end;
  RefreshVcsProjects;
end;

procedure TAtlasSettingsVcsProjectsPart.Save(var ASettings: TAtlasPluginSettings);
begin
  ASettings.VcsProjects := VcsProjectsJson(FVcsProjects);
end;

{ TAtlasSettingsVcsProjectAddPart }

function TAtlasSettingsVcsProjectAddPart.Projects: TAtlasSettingsVcsProjectsPart;
begin
  Result := FPage.Part<TAtlasSettingsVcsProjectsPart>;
end;

procedure TAtlasSettingsVcsProjectAddPart.AddButtons(APanel: TWinControl);
begin
  FAddCurrent := AddRowButton(APanel, 0, cVcsAddCurrentWidth, TAtlasTextId.SettingsIssuesProjectAddCurrent,
    AddCurrentClick);
  FAdd := AddRowButton(APanel, cVcsAddCurrentWidth + cVcsButtonGap, cVcsAddWidth, TAtlasTextId.SettingsIssuesProjectAdd,
    AddClick);
  FAddMenu := TPopupMenu.Create(FPage);
  AddMenuItem(TAtlasTextId.SettingsIssuesProjectAddFile, AddFileClick);
  AddMenuItem(TAtlasTextId.SettingsIssuesProjectAddFolder, AddFolderClick);
end;

procedure TAtlasSettingsVcsProjectAddPart.AddMenuItem(AId: TAtlasTextId; AClick: TNotifyEvent);
var
  mItem: TMenuItem;
begin
  mItem := TMenuItem.Create(FPage);
  mItem.Caption := TAtlasStrings.Text(AId);
  mItem.OnClick := AClick;
  FAddMenu.Items.Add(mItem);
end;

procedure TAtlasSettingsVcsProjectAddPart.AllowCurrent(AValue: Boolean);
begin
  Allow(FAddCurrent, AValue);
end;

procedure TAtlasSettingsVcsProjectAddPart.AddCurrentClick(Sender: TObject);
var
  mMatch, mProvider: string;
begin
  Projects.RefreshVcsProjects;
  if Projects.FVcsContext.ProjectFile = '' then
  begin
    Projects.FVcsProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectNoProject);
    Exit;
  end;
  // Die geöffnete .groupproj, sonst die aktive .dproj; Art vorbelegt mit der erkannten Arbeitskopie.
  mMatch := TAtlasProjectMatching.CurrentMatch(Projects.FVcsContext.ProjectFile, Projects.FVcsContext.GroupFile);
  mProvider := 'auto';
  if SameText(FPage.Part<TAtlasSettingsVcsProjectPart>.VcsDetectedProject, Projects.FVcsContext.ProjectFile) then
    case FPage.Part<TAtlasSettingsVcsProjectPart>.VcsDetectedKind of
      TAtlasVcsKind.Git:
        mProvider := 'git';
      TAtlasVcsKind.Svn:
        mProvider := 'svn';
      TAtlasVcsKind.None: ;
    end;
  Projects.VcsProjectAdd(mMatch, mProvider);
end;

procedure TAtlasSettingsVcsProjectAddPart.AddClick(Sender: TObject);
begin
  // Unter dem Knopf aufklappen.
  FAddMenu.Popup(FAdd.ClientOrigin.X, FAdd.ClientOrigin.Y + FAdd.Height);
end;

procedure TAtlasSettingsVcsProjectAddPart.AddFileClick(Sender: TObject);
var
  mPath: string;
begin
  if BrowseProject(False, mPath) then
  begin
    Projects.VcsProjectAdd(mPath, 'auto');
  end;
end;

procedure TAtlasSettingsVcsProjectAddPart.AddFolderClick(Sender: TObject);
var
  mPath: string;
begin
  if BrowseProject(True, mPath) then
  begin
    Projects.VcsProjectAdd(mPath, 'auto');
  end;
end;

function TAtlasSettingsVcsProjectAddPart.BrowseProject(AFolder: Boolean; out APath: string): Boolean;
var
  mFolder: TFileOpenDialog;
  mFile: TOpenDialog;
begin
  APath := '';
  if Assigned(FOnBrowseProject) then
  begin
    Exit(FOnBrowseProject(AFolder, APath));
  end;
  if AFolder then
  begin
    mFolder := TFileOpenDialog.Create(nil);
    try
      mFolder.Options := mFolder.Options + [fdoPickFolders, fdoPathMustExist];
      Result := mFolder.Execute;
      if Result then
      begin
        APath := mFolder.FileName;
      end;
    finally
      mFolder.Free;
    end;
    Exit;
  end;
  mFile := TOpenDialog.Create(nil);
  try
    mFile.Filter := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectFileFilter);
    mFile.Options := mFile.Options + [ofFileMustExist];
    Result := mFile.Execute;
    if Result then
    begin
      APath := mFile.FileName;
    end;
  finally
    mFile.Free;
  end;
end;

{ TAtlasSettingsVcsServersPart }

procedure TAtlasSettingsVcsServersPart.Build;
begin
  AddVcsServersSection;
end;

procedure TAtlasSettingsVcsServersPart.AddVcsServersSection;
var
  mPanel: TWinControl;
  mHint: TLabel;
begin
  FVcsServerSelected := -1;
  AddTitle(TAtlasTextId.SettingsVcsServers);
  mPanel := AddPanel(96);
  FVcsServerList := TListView.Create(FPage);
  FVcsServerList.Parent := mPanel;
  FVcsServerList.Align := alClient;
  FVcsServerList.ViewStyle := vsReport;
  FVcsServerList.ReadOnly := True;
  FVcsServerList.RowSelect := True;
  FVcsServerList.HideSelection := False;
  FVcsServerList.OnSelectItem := VcsServerSelectItem;
  TAtlasSettingsPageSheets.AddListColumn(FVcsServerList, TAtlasTextId.SettingsVcsServerProject,
    cVcsServerProjectColumn);
  TAtlasSettingsPageSheets.AddListColumn(FVcsServerList, TAtlasTextId.SettingsVcsServerServer, cVcsServerServerColumn);
  TAtlasSettingsPageSheets.AddListColumn(FVcsServerList, TAtlasTextId.SettingsVcsServerState, cVcsServerStateColumn);
  mPanel := AddPanel(32);
  FVcsServerCheck := AddRowButton(mPanel, 0, cVcsCheckWidth, TAtlasTextId.SettingsVcsServerCheck, VcsServerCheckClick);
  FVcsServerCheckAll := AddRowButton(mPanel, cVcsCheckWidth + cVcsButtonGap, cVcsCheckAllWidth,
    TAtlasTextId.SettingsVcsServerCheckAll, VcsServerCheckAllClick);
  FVcsServerLogin := AddRowButton(mPanel, cVcsCheckWidth + cVcsCheckAllWidth + cVcsButtonGap + cVcsButtonGap,
    cVcsCheckAllWidth, TAtlasTextId.SettingsVcsServerLogin, VcsServerLoginClick);
  Attach(mPanel, FVcsServerList);
  mPanel := AddPanel(18);
  FVcsServerNote := TLabel.Create(FPage);
  FVcsServerNote.Parent := mPanel;
  FVcsServerNote.Left := 0;
  FVcsServerNote.Top := 1;
  Attach(mPanel, FVcsServerList);
  mHint := AddWrappedLabel(52, TAtlasStrings.Text(TAtlasTextId.SettingsVcsServersHint));
  mHint.Font.Color := clGrayText;
  Attach(mHint.Parent, FVcsServerList);
end;

class function TAtlasSettingsVcsServersPart.VcsServerStateText(const ACheck: TAtlasVcsServerCheck;
  AChecking: Boolean): string;
begin
  if AChecking then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerChecking));
  end;
  case ACheck.State of
    TAtlasVcsServerState.Reachable:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsServerReachable,
        [FormatDateTime('hh:nn', ACheck.CheckedAt, FormatSettings)]);
    TAtlasVcsServerState.LoginNeeded:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginNeeded);
    TAtlasVcsServerState.Unreachable:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerUnreachable);
    TAtlasVcsServerState.NoServer:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerNoServer);
    TAtlasVcsServerState.ToolMissing:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerToolMissing);
    TAtlasVcsServerState.Failed:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerFailed);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerUnknown);
  end;
end;

/// <summary>Laufende Prüfungen aus AOld bleiben in ARows sichtbar.</summary>
procedure KeepChecking(var ARows: TArray<TAtlasVcsServerRow>; const AOld: TArray<TAtlasVcsServerRow>);
var
  mIndex: Integer;
  mOldRow: TAtlasVcsServerRow;
begin
  for mIndex := 0 to High(ARows) do
  begin
    for mOldRow in AOld do
    begin
      if mOldRow.Checking and SameText(mOldRow.Folder, ARows[mIndex].Folder) then
      begin
        ARows[mIndex].Checking := True;
      end;
    end;
  end;
end;

procedure TAtlasSettingsVcsServersPart.AddServerRow(const AName, AFolder: string);
var
  mRow: TAtlasVcsServerRow;
begin
  if AFolder = '' then
  begin
    Exit;
  end;
  for mRow in FVcsServerRows do
  begin
    if SameText(mRow.Folder, AFolder) then
    begin
      Exit;
    end;
  end;
  mRow.Name := AName;
  mRow.Folder := AFolder;
  mRow.Check := TAtlasVcsServerCheck.Empty;
  if Assigned(FOnVcsServerState) then
  begin
    mRow.Check := FOnVcsServerState(AFolder);
  end;
  mRow.Checking := False;
  FVcsServerRows := FVcsServerRows + [mRow];
end;

procedure TAtlasSettingsVcsServersPart.CollectServerRows;
var
  mProjects: TAtlasSettingsVcsProjectsPart;
  mContext: TAtlasVcsProjectContext;
  mMapping: TAtlasVcsProjectMapping;
begin
  FVcsServerRows := nil;
  mProjects := FPage.Part<TAtlasSettingsVcsProjectsPart>;
  mContext := mProjects.VcsContext;
  // Erst das aktuelle Projekt, dann die Zeilen der Tabelle Projekte; .dproj und .groupproj gelten für ihren Ordner.
  if mContext.ProjectFile <> '' then
  begin
    AddServerRow(ExtractFileName(TAtlasProjectMatching.CurrentMatch(mContext.ProjectFile, mContext.GroupFile)),
      ExtractFileDir(mContext.ProjectFile));
  end;
  for mMapping in mProjects.VcsProjectRows do
  begin
    if mMapping.Kind = TAtlasProjectMatch.Folder then
    begin
      AddServerRow(ExtractFileName(ExcludeTrailingPathDelimiter(mMapping.Match)),
        ExcludeTrailingPathDelimiter(mMapping.Match));
    end
    else
    begin
      AddServerRow(ExtractFileName(mMapping.Match), ExtractFileDir(mMapping.Match));
    end;
  end;
  if FVcsServerExtra <> '' then
  begin
    AddServerRow(ExtractFileName(FVcsServerExtra), FVcsServerExtra);
  end;
end;

procedure TAtlasSettingsVcsServersPart.FillServerList;
var
  mIndex: Integer;
begin
  if not ListReady(FVcsServerList) then
  begin
    Exit;
  end;
  FVcsServerList.Items.BeginUpdate;
  try
    FVcsServerList.Items.Clear;
    for mIndex := 0 to High(FVcsServerRows) do
    begin
      FVcsServerList.Items.Add;
      VcsServerShowItem(mIndex);
    end;
    if FVcsServerSelected >= 0 then
    begin
      FVcsServerList.Items[FVcsServerSelected].Selected := True;
    end;
  finally
    FVcsServerList.Items.EndUpdate;
  end;
end;

procedure TAtlasSettingsVcsServersPart.RefreshVcsServers;
var
  mOld: TArray<TAtlasVcsServerRow>;
begin
  if FVcsServerList = nil then
  begin
    Exit;
  end;
  mOld := FVcsServerRows;
  CollectServerRows;
  KeepChecking(FVcsServerRows, mOld);
  if FVcsServerSelected > High(FVcsServerRows) then
  begin
    FVcsServerSelected := High(FVcsServerRows);
  end;
  if (FVcsServerSelected < 0) and (Length(FVcsServerRows) > 0) then
  begin
    FVcsServerSelected := 0;
  end;
  FillServerList;
  VcsServerFillButtons;
end;

procedure TAtlasSettingsVcsServersPart.VcsServerShowItem(AIndex: Integer);
var
  mItem: TListItem;
  mServer: string;
begin
  if (AIndex < 0) or (AIndex > High(FVcsServerRows)) or not ListReady(FVcsServerList) or
    (AIndex >= FVcsServerList.Items.Count) then
  begin
    Exit;
  end;
  mItem := FVcsServerList.Items[AIndex];
  mItem.Caption := FVcsServerRows[AIndex].Name;
  mServer := FVcsServerRows[AIndex].Check.ServerText;
  if mServer = '' then
  begin
    mServer := '–';
  end;
  mItem.SubItems.Clear;
  mItem.SubItems.Add(mServer);
  mItem.SubItems.Add(VcsServerStateText(FVcsServerRows[AIndex].Check, FVcsServerRows[AIndex].Checking));
end;

procedure TAtlasSettingsVcsServersPart.VcsServerFillButtons;
var
  mSelected: Boolean;
begin
  mSelected := (FVcsServerSelected >= 0) and (FVcsServerSelected <= High(FVcsServerRows));
  Allow(FVcsServerCheck, mSelected and Assigned(FOnVcsServerCheck) and
    not FVcsServerRows[Max(0, FVcsServerSelected)].Checking);
  Allow(FVcsServerCheckAll, (Length(FVcsServerRows) > 0) and Assigned(FOnVcsServerCheck));
  Allow(FVcsServerLogin, mSelected and Assigned(FOnVcsServerLogin) and
    FVcsServerRows[Max(0, FVcsServerSelected)].Check.CanLogin);
end;

procedure TAtlasSettingsVcsServersPart.VcsServerStart(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FVcsServerRows)) or not Assigned(FOnVcsServerCheck) or
    FVcsServerRows[AIndex].Checking then
  begin
    Exit;
  end;
  FVcsServerRows[AIndex].Checking := True;
  VcsServerShowItem(AIndex);
  VcsServerFillButtons;
  FOnVcsServerCheck(FVcsServerRows[AIndex].Folder);
end;

procedure TAtlasSettingsVcsServersPart.RevealVcsServer(const AFolder: string);
var
  mIndex: Integer;
begin
  if (FVcsServerList = nil) or (Trim(AFolder) = '') then
  begin
    Exit;
  end;
  FVcsServerExtra := ExcludeTrailingPathDelimiter(Trim(AFolder));
  RefreshVcsServers;
  for mIndex := 0 to High(FVcsServerRows) do
  begin
    if SameText(FVcsServerRows[mIndex].Folder, FVcsServerExtra) then
    begin
      FVcsServerSelected := mIndex;
      if ListReady(FVcsServerList) and (mIndex < FVcsServerList.Items.Count) then
      begin
        FVcsServerList.Items[mIndex].Selected := True;
      end;
      FPage.SelectPage(FPage.PageOf(FVcsServerList));
      VcsServerStart(mIndex);
      Break;
    end;
  end;
end;

procedure TAtlasSettingsVcsServersPart.VcsServerDone(const AFolder: string; const ACheck: TAtlasVcsServerCheck);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FVcsServerRows) do
  begin
    if SameText(FVcsServerRows[mIndex].Folder, AFolder) then
    begin
      FVcsServerRows[mIndex].Check := ACheck;
      FVcsServerRows[mIndex].Checking := False;
      VcsServerShowItem(mIndex);
    end;
  end;
  if FVcsServerNote <> nil then
  begin
    FVcsServerNote.Caption := '';
  end;
  VcsServerFillButtons;
end;

procedure TAtlasSettingsVcsServersPart.VcsServerSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if not Selected or (Item = nil) then
  begin
    Exit;
  end;
  FVcsServerSelected := Item.Index;
  VcsServerFillButtons;
end;

procedure TAtlasSettingsVcsServersPart.VcsServerCheckClick(Sender: TObject);
begin
  VcsServerStart(FVcsServerSelected);
end;

procedure TAtlasSettingsVcsServersPart.VcsServerCheckAllClick(Sender: TObject);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FVcsServerRows) do
  begin
    VcsServerStart(mIndex);
  end;
end;

procedure TAtlasSettingsVcsServersPart.VcsServerLoginClick(Sender: TObject);
var
  mRow: TAtlasVcsServerRow;
begin
  if (FVcsServerSelected < 0) or (FVcsServerSelected > High(FVcsServerRows)) or not Assigned(FOnVcsServerLogin) then
  begin
    Exit;
  end;
  mRow := FVcsServerRows[FVcsServerSelected];
  if not mRow.Check.CanLogin then
  begin
    Exit;
  end;
  if FOnVcsServerLogin(mRow.Folder, mRow.Check) then
  begin
    // Nach dem Schließen der Konsole prüft der Aufrufer erneut und meldet VcsServerDone.
    FVcsServerRows[FVcsServerSelected].Checking := True;
    VcsServerShowItem(FVcsServerSelected);
    FVcsServerNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginOpen);
  end
  else
  begin
    FVcsServerNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginFailed);
  end;
  VcsServerFillButtons;
end;

end.
