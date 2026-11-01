unit Atlas.IDE.Tracker.Composition;

// Modul Tracker (#1455, ADR 0017): einzige Unit, die Issue-Kennungen im Code
// (#1265, Atlas.IDE.Tracker.CodeLinks) und Issues in der Zeilenhistorie
// (#1275, Atlas.IDE.Tracker.BlameLinks) einbindet. Sie meldet in ihrer
// Initialisierung das Modul „atlas.tracker“ (Modulschalter issues, #1454) bei
// der Registry von Base an und stellt über dessen Scope bereit:
// - die Teile IssueLinks und BlameIssues der Feature-Tabelle,
// - Befehle (Palette): Zugang zum Issue-Tracker und zum Build-Server, Issue
//   anlegen, Issue anzeigen, Issues zu dieser Methode, offene Zeitbuchungen,
//   Board, An Issue anhängen,
// - „An Issue anhängen …“ im Atlas-Menü, „Board“ unter Ansicht › Atlas,
//   „Issue anlegen …“ im Kontextmenü des Editors und auf seiner Taste.
// Alles, was „Meine Issues“ braucht (Tracker des Projekts, Vorschau,
// Beginnen, Board, Zeiterfassung, Anhängen, Issue anlegen), fragt das Modul bei
// jedem Gebrauch über IAtlasIssuesSession (Atlas.IDE.Tracker.Session) aus der
// Registry; ohne den Bereich sind die Befehle unsichtbar und die Teile starten
// nicht. Die Zeilenhistorie (Base) hält die Haken des Moduls nur, solange
// BlameIssues läuft (Regel 3).
// Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  TAtlasTrackerModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasKeySource)
  public const
    ModuleId = 'atlas.tracker';
    Switch = 'issues';
  private
    FActive: Boolean;
    class function Parts: TArray<IAtlasFeaturePart>; static;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    function Keys: TArray<TAtlasModuleKey>;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Tracker.Contract,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.LineChanges,
  Atlas.IDE.Tracker.Session,
  Atlas.IDE.Tracker.IssuePreview,
  Atlas.IDE.Tracker.CodeLinks,
  Atlas.IDE.Tracker.BlameLinks,
  Atlas.UI.Strings,  Atlas.UI.Tracker.Strings;

var
  GScope: IAtlasModuleScope;
  GIssueLinks: TAtlasIdeCodeLinks;
  GBlameIssues: TAtlasIdeBlameLinks;

{ „Meine Issues“ }

/// <summary>Der laufende Bereich „Meine Issues“; nil ohne.</summary>
function Session: IAtlasIssuesSession;
var
  mItem: IInterface;
begin
  Result := nil;
  if AtlasModuleRegistry = nil then
    Exit;
  for mItem in AtlasModuleRegistry.FindAll(IAtlasIssuesSession) do
    if Supports(mItem, IAtlasIssuesSession, Result) and Result.Available then
      Exit;
  Result := nil;
end;

function SessionAvailable: Boolean;
begin
  Result := Session <> nil;
end;

function SessionTarget(out ATarget: TAtlasTrackerTarget): Boolean;
var
  mSession: IAtlasIssuesSession;
begin
  ATarget := TAtlasTrackerTarget.Create('', '', '', '');
  mSession := Session;
  Result := (mSession <> nil) and mSession.CodeTarget(ATarget);
end;

function CommitPattern: string;
begin
  Result := TAtlasIdeSettings.Current.IssuesCommitPattern;
end;

function SessionPreview: TAtlasIdeIssuePreview;
var
  mSession: IAtlasIssuesSession;
begin
  Result := nil;
  mSession := Session;
  if mSession <> nil then
    Result := mSession.IssuePreview;
end;

procedure SessionShow(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mSession: IAtlasIssuesSession;
begin
  mSession := Session;
  if mSession <> nil then
    mSession.ShowIssue(ATarget, AKey);
end;

procedure SessionBrowse(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mSession: IAtlasIssuesSession;
begin
  mSession := Session;
  if mSession <> nil then
    mSession.BrowseIssue(ATarget, AKey);
end;

procedure SessionStart(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mSession: IAtlasIssuesSession;
begin
  mSession := Session;
  if mSession <> nil then
    mSession.StartIssue(ATarget, AKey);
end;

function SessionCanStart: Boolean;
var
  mSession: IAtlasIssuesSession;
begin
  mSession := Session;
  Result := (mSession <> nil) and mSession.CanStartIssue;
end;

/// <summary>Haken der Kennungen im Code und der Zeilenhistorie: alles über „Meine Issues“ (Tracker wie dort,
/// Zwischenspeicher der Vorschau); ohne den Bereich wirkungslos.</summary>
function IssueHooks: TAtlasCodeLinksHooks;
begin
  Result := Default(TAtlasCodeLinksHooks);
  Result.Target := SessionTarget;
  Result.CommitPattern := CommitPattern;
  Result.Preview := SessionPreview;
  Result.Show := SessionShow;
  Result.Browse := SessionBrowse;
  Result.Start := SessionStart;
  Result.CanStart := SessionCanStart;
end;

{ Teile }

/// <summary>Wie bisher nach „Meine Issues“ und nicht in der Stufe Minimal.</summary>
function WithSession(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := (ALevel <> TAtlasSafeLevel.Minimal) and SessionAvailable;
end;

// Issue-Kennungen im Code (#1265): issues.codeLinks prüft der Zeitgeber selbst (Schnellschalter ohne Neustart).
procedure StartIssueLinks;
begin
  GIssueLinks := TAtlasIdeCodeLinks.Create(IssueHooks);
end;

procedure StopIssueLinks;
begin
  FreeAndNil(GIssueLinks);
end;

function IssueLinksStarted: Boolean;
begin
  Result := GIssueLinks <> nil;
end;

// Issues in der Zeilenhistorie (#1275): issues.blameLinks prüfen die Haken selbst (Schnellschalter ohne Neustart).
procedure StartBlameIssues;
begin
  // Dieselben Haken wie die Kennungen im Code; die Zeilenhistorie bekommt ihre Ergänzungen (kein Zyklus).
  GBlameIssues := TAtlasIdeBlameLinks.Create(IssueHooks);
  TAtlasIdeLineChanges.SetBlameHooks(GBlameIssues.LineHooks);
end;

procedure StopBlameIssues;
begin
  // Base hält danach keinen Haken des Moduls mehr (Regel 3).
  TAtlasIdeLineChanges.SetBlameHooks(Default(TAtlasBlameHooks));
  FreeAndNil(GBlameIssues);
end;

function BlameIssuesStarted: Boolean;
begin
  Result := GBlameIssues <> nil;
end;

{ Befehle }

function Command(const AId, ACaption: string; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Run := ARun;
  Result.Visible := AVisible;
end;

procedure EnterCredentials;
var
  mSession: IAtlasIssuesSession;
begin
  mSession := Session;
  if mSession <> nil then
    mSession.EnterCredentials;
end;

function TrackerLoginVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TrackerLogin and SessionAvailable;
end;

procedure EnterCiCredentials;
var
  mSession: IAtlasIssuesSession;
begin
  mSession := Session;
  if mSession <> nil then
    mSession.EnterCiCredentials;
end;

function CiLoginVisible: Boolean;
var
  mSession: IAtlasIssuesSession;
begin
  mSession := Session;
  Result := TAtlasIdeSettings.Current.CiLogin and (mSession <> nil) and mSession.CanEnterCiCredentials;
end;

procedure CreateIssueNow;
var
  mSession: IAtlasIssuesSession;
begin
  mSession := Session;
  if (mSession <> nil) and mSession.CanCreateIssue then
    mSession.CreateIssueFromEditor;
end;

procedure CreateIssue;
begin
  // Läuft in „Issue anlegen“ der Willkommensseite, daher deren Sicherung.
  TAtlasGuard.Run(TAtlasFeature.WelcomePage, CreateIssueNow);
end;

function CreateIssueVisible: Boolean;
var
  mSession: IAtlasIssuesSession;
begin
  mSession := Session;
  Result := (mSession <> nil) and mSession.CanCreateIssue;
end;

function CreateIssueKey: Integer;
begin
  Result := TAtlasIdeSettings.Current.CreateIssueKey;
end;

procedure ShowPreviewPrompt;
var
  mSession: IAtlasIssuesSession;
begin
  mSession := Session;
  if mSession <> nil then
    mSession.ShowPreviewPrompt;
end;

function PreviewVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesPreview and SessionAvailable;
end;

procedure ShowBlameScope;
begin
  if GBlameIssues <> nil then
    TAtlasGuard.Run(TAtlasFeature.BlameIssues, GBlameIssues.ShowScope);
end;

function BlameVisible: Boolean;
begin
  Result := TAtlasIdeBlameLinks.Enabled and (GBlameIssues <> nil);
end;

procedure ShowTimeOpen;
var
  mSession: IAtlasIssuesSession;
begin
  mSession := Session;
  if mSession <> nil then
    mSession.ShowTimeOpen;
end;

function TimeVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesTimeTracking and SessionAvailable;
end;

procedure ShowBoard;
var
  mSession: IAtlasIssuesSession;
begin
  mSession := Session;
  if mSession <> nil then
    mSession.ShowBoard;
end;

function BoardVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesBoard and SessionAvailable;
end;

procedure AttachPrompt;
var
  mSession: IAtlasIssuesSession;
begin
  mSession := Session;
  if mSession <> nil then
    mSession.AttachPrompt;
end;

function AttachVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesAttach and SessionAvailable;
end;

{ TAtlasTrackerModule }

function TAtlasTrackerModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := ModuleId;
  Result.Name := 'Issue-Tracker';
  Result.Version := TAtlasVersion.Version;
  Result.Handle := HInstance;
  // Lief mit der Willkommensseite schon im abgesicherten Start.
  Result.MinLevel := TAtlasSafeLevel.Safe;
  Result.Switch := Switch;
end;

procedure TAtlasTrackerModule.Start;
begin
  FActive := True;
end;

procedure TAtlasTrackerModule.Stop;
begin
  FActive := False;
end;

function TAtlasTrackerModule.IsActive: Boolean;
begin
  Result := FActive;
end;

function TAtlasTrackerModule.Commands: TArray<TAtlasModuleCommand>;
var
  mCreate: TAtlasModuleCommand;
begin
  // Issue anlegen (#1268): aus Auswahl bzw. TODO im Editor; sichtbar mit issues.create.
  mCreate := Command('Atlas.CreateIssue', TAtlasStrings.Text(TAtlasTextId.CreateIssueCommand),
    CreateIssue, CreateIssueVisible);
  mCreate.Key := CreateIssueKey;
  Result := [
    // Zugang zum Build-Server (#763): für die .atlas des aktiven Projekts; sichtbar mit CiLogin.
    Command('Atlas.CiLogin', TAtlasStrings.Text(TAtlasTextId.CiLoginCommand), EnterCiCredentials, CiLoginVisible),
    // Zugang zum Issue-Tracker (#765): für die .atlas des aktiven Projekts; sichtbar mit TrackerLogin.
    Command('Atlas.TrackerLogin', TAtlasStrings.Text(TAtlasTextId.TrackerLoginCommand),
      EnterCredentials, TrackerLoginVisible),
    mCreate,
    // Issue-Vorschau (#1264): Kennung abfragen und das Issue in „Atlas-Issue“ zeigen; sichtbar mit issues.preview.
    Command('Atlas.IssueShow', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewCommand), ShowPreviewPrompt,
      PreviewVisible),
    // Issues zu dieser Methode (#1275); sichtbar mit issues.blameLinks.
    Command('Atlas.BlameIssues', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.BlameIssuesCommand), ShowBlameScope,
      BlameVisible),
    // Offene Zeitbuchungen (#1267): sichtbar mit issues.timeTracking.
    Command('Atlas.IssueTimeOpen', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeMenuOpen), ShowTimeOpen,
      TimeVisible),
    // Atlas-Board (#1272): Sprint als Spalten nach Zustand; sichtbar mit issues.board.
    Command('Atlas.Board', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.BoardCommand), ShowBoard, BoardVisible),
    // An Issue anhängen (#1276): Bildschirmfoto, Formular, Log, Debug-Notiz; sichtbar mit issues.attach.
    Command('Atlas.IssueAttach', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachCommand), AttachPrompt,
      AttachVisible)];
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

function TAtlasTrackerModule.MenuEntries: TArray<TAtlasMenuEntry>;
var
  mBoard: TAtlasMenuEntry;
begin
  // Ansicht › Atlas › Board (#1272) mit dem bisherigen Text.
  mBoard := MenuEntry('Atlas.Board', TAtlasMenuPlace.ViewMenu);
  mBoard.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.BoardViewMenu);
  Result := [
    MenuEntry('Atlas.IssueAttach', TAtlasMenuPlace.AtlasMenu),
    mBoard,
    // Issue anlegen (#1268): aus Auswahl bzw. TODO an der Schreibmarke, nur mit issues.create.
    MenuEntry('Atlas.CreateIssue', TAtlasMenuPlace.EditorContext)];
end;

function TAtlasTrackerModule.Keys: TArray<TAtlasModuleKey>;
var
  mKey: TAtlasModuleKey;
begin
  Result := nil;
  // Issue anlegen (#1268): frei belegbar, ohne Vorgabe.
  if TAtlasIdeSettings.Current.CreateIssueKey = 0 then
    Exit;
  mKey := Default(TAtlasModuleKey);
  mKey.Id := 'Atlas.CreateIssue';
  mKey.Caption := TAtlasStrings.Text(TAtlasTextId.CreateIssueCommand);
  mKey.Key := TAtlasIdeSettings.Current.CreateIssueKey;
  mKey.Priority := TAtlasKeyPriority.Shared;
  mKey.Run := CreateIssue;
  Result := [mKey];
end;

class function TAtlasTrackerModule.Parts: TArray<IAtlasFeaturePart>;
begin
  // Nach „Meine Issues“ (Tracker und Vorschau); Abbau vor der Willkommensseite, weil Module zuerst gehen.
  Result := [
    TAtlasFeaturePart.When('IssueLinks', WithSession, IssueLinksStarted, StartIssueLinks, StopIssueLinks),
    TAtlasFeaturePart.When('BlameIssues', WithSession, BlameIssuesStarted, StartBlameIssues, StopBlameIssues)];
end;

class function TAtlasTrackerModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasTrackerModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  mRegistry := AtlasModuleRegistry;
  if (mRegistry = nil) or (GScope <> nil) then
    Exit;
  // Regel 7: zuerst die Vertragsversion von Base (FindClassHInstance einer Base-Klasse, Regel 8).
  if TAtlasContractHandshake.Check(FindClassHInstance(TAtlasModuleRegistry), cAtlasCoreContractVersion) <>
    ccMatch then
  begin
    TAtlasGuard.Log('Modul ' + ModuleId + ': Vertragsversion von Base passt nicht, nicht angemeldet');
    Exit;
  end;
  mModule := TAtlasTrackerModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
    GScope.Provide(IAtlasFeaturePart, mPart);
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasKeySource, mRef);
  Result := True;
end;

class procedure TAtlasTrackerModule.UnregisterModule;
var
  mRegistry: IAtlasModuleRegistry;
  mFailure: string;
begin
  if GScope = nil then
    Exit;
  GScope := nil;
  // Regel 5: nur, solange Base noch läuft; sonst hat Base das Modul schon gestoppt und abgemeldet.
  mRegistry := AtlasModuleRegistry;
  if mRegistry <> nil then
    for mFailure in mRegistry.UnregisterModule(ModuleId) do
      TAtlasGuard.Log('Modul ' + ModuleId + ' nicht sauber abgemeldet: ' + mFailure);
end;

initialization
  TAtlasTrackerModule.RegisterModule;

finalization
  TAtlasTrackerModule.UnregisterModule;

end.
