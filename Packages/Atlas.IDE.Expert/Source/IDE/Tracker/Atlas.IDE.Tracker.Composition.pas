unit Atlas.IDE.Tracker.Composition;

// Modul Tracker (#1455, ADR 0017): einzige Unit, die Issue-Kennungen im Code
// (#1265, Atlas.IDE.Tracker.CodeLinks) und Issues in der Zeilenhistorie
// (#1275, Atlas.IDE.Tracker.BlameLinks) einbindet. Sie meldet in ihrer
// Initialisierung das Modul „atlas.tracker“ (Modulschalter issues, #1454) bei
// der Registry von Base an und stellt über dessen Scope bereit:
// - die Teile IssueLinks und BlameIssues der Feature-Tabelle,
// - Befehle (Palette): Zugang zum Issue-Tracker, Issue anlegen, Issue anzeigen,
//   Issues zu dieser Methode, offene Zeitbuchungen, Board, An Issue anhängen
//   (der Zugang zum Build-Server gehört seit #1455 zur Willkommensseite,
//   Karte Testergebnisse),
// - „An Issue anhängen …“ im Atlas-Menü, „Board“ unter Ansicht › Atlas,
//   „Issue anlegen …“ im Kontextmenü des Editors und auf seiner Taste,
// - den Abschnitt „Issue-Tracker“ im Optionsdialog (Atlas.IDE.Tracker.Settings,
//   auch bei ausgeschaltetem Modul, damit man es einstellen kann).
// - „Meine Issues“ (#765) als Teil MyIssues: Tracker des Projekts, Vorschau,
//   Beginnen, Board, Zeiterfassung, Anhängen und „Issue anlegen“ (#1268);
//   die Kacheln „Meine Issues“ und „Sprint“ der Willkommensseite über
//   Atlas.IDE.Contracts.WelcomeTiles (Atlas.IDE.Tracker.Tiles), Projekte und
//   Meldungen an die Seite über Atlas.IDE.Tracker.WelcomeLink, Issues in der
//   Befehlspalette (#1270). Ohne Willkommensseite laufen Statuszeile,
//   Commit-Präfix und Befehle mit dem aktiven Projekt der IDE weiter.
// Anbieter, Token und Transport kommen über IAtlasTrackerAccess aus der
// Registry. Ohne MyIssues sind die Befehle unsichtbar und Kennungen im Code
// und Zeilenhistorie starten nicht. Die Zeilenhistorie (Base) hält die Haken
// des Moduls nur, solange BlameIssues läuft (Regel 3).
// Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Modules.Contract;

type
  TAtlasTrackerModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasKeySource, IAtlasAppliesSettings, IAtlasPaletteSourceProvider)
  public const
    cModuleId = 'atlas.tracker';
    cSwitch = 'issues';
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
    /// <summary>Geänderte Einstellungen an „Meine Issues“ und den Sprint (Sichtbarkeit, Titel, Inhalt).</summary>
    procedure ApplySettings;
    /// <summary>Issues in der Befehlspalette (#1270); nil ohne „Meine Issues“.</summary>
    function PaletteSource: IAtlasPaletteSource;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  System.Types,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.IDE.Contracts.WelcomeTiles,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.LineChanges,
  Atlas.IDE.Settings.Options,
  Atlas.IDE.Tracker.IssuePreview,
  Atlas.IDE.Tracker.CodeLinks,
  Atlas.IDE.Tracker.BlameLinks,
  Atlas.IDE.Tracker.MyIssues,
  Atlas.IDE.Tracker.NewIssue,
  Atlas.IDE.Tracker.Settings,
  Atlas.IDE.Tracker.Tiles,
  Atlas.IDE.Tracker.WelcomeLink,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Strings;

const
  // Protokoll beim An- und Abmelden.
  cLogContractMismatch = 'Modul %s: Vertragsversion von Base passt nicht, nicht angemeldet';
  cLogUnregisterFailed = 'Modul %s nicht sauber abgemeldet: %s';
  // Zusatzfeld der Zeiterfassung im Statusfeld (#1267).
  cIssueTimeExtra = 'issueTime';
  // Seiten und Tabellen des Abschnitts Issue-Tracker für „Einstellungen“, „zuordnen …“ und „Abfragen bearbeiten …“.
  cSettingConnections = 'IssuesConnections';
  cSettingProjects = 'IssuesProjects';
  cSettingQueries = 'IssuesQueries';

var
  GScope: IAtlasModuleScope;
  GIssueLinks: TAtlasIdeCodeLinks;
  GBlameIssues: TAtlasIdeBlameLinks;
  GWelcome: TAtlasTrackerWelcomeLink;
  GIssues: TAtlasIdeIssues;
  GIssuesRef: IInterface;
  /// <summary>Zugang zum Tracker; im Hauptthread einmal geholt, der Transport liest ihn im Hintergrund.</summary>
  GAccess: IAtlasTrackerAccess;
  /// <summary>Kacheln der Willkommensseite, solange MyIssues läuft.</summary>
  GTiles: TArray<IAtlasRegistration>;

{ Dienste aus der Registry }

/// <summary>Erstes unter AIID bereitgestelltes Objekt; nil ohne.</summary>
function Provided(const AIID: TGUID): IInterface;
var
  mItems: TArray<IInterface>;
begin
  Result := nil;
  if AtlasModuleRegistry = nil then
  begin
    Exit;
  end;
  mItems := AtlasModuleRegistry.FindAll(AIID);
  if Length(mItems) > 0 then
  begin
    Result := mItems[0];
  end;
end;

/// <summary>Zugang zum Tracker der Kompositionswurzel; im Hauptthread.</summary>
function TrackerAccess: IAtlasTrackerAccess;
begin
  if (GAccess = nil) and not Supports(Provided(IAtlasTrackerAccess), IAtlasTrackerAccess, GAccess) then
  begin
    GAccess := nil;
  end;
  Result := GAccess;
end;

function WelcomeProjects: IAtlasWelcomeProjects;
begin
  if not Supports(Provided(IAtlasWelcomeProjects), IAtlasWelcomeProjects, Result) then
  begin
    Result := nil;
  end;
end;

function WelcomeBoard: IAtlasWelcomeBoard;
begin
  if not Supports(Provided(IAtlasWelcomeBoard), IAtlasWelcomeBoard, Result) then
  begin
    Result := nil;
  end;
end;

{ „Meine Issues“ }

function SessionAvailable: Boolean;
begin
  Result := GIssues <> nil;
end;

function SessionTarget(out ATarget: TAtlasTrackerTarget): Boolean;
begin
  ATarget := TAtlasTrackerTarget.Create('', '', '', '');
  Result := SessionAvailable and GIssues.CodeTarget(ATarget);
end;

function CommitPattern: string;
begin
  Result := TAtlasIdeSettings.Current.IssuesCommitPattern;
end;

function SessionPreview: TAtlasIdeIssuePreview;
begin
  Result := nil;
  if SessionAvailable then
  begin
    Result := GIssues.IssuePreview;
  end;
end;

procedure SessionShow(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  if SessionAvailable then
  begin
    GIssues.ShowIssue(ATarget, AKey);
  end;
end;

procedure SessionBrowse(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  if SessionAvailable then
  begin
    GIssues.BrowseIssue(ATarget, AKey);
  end;
end;

procedure SessionStart(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  if SessionAvailable then
  begin
    GIssues.StartIssue(ATarget, AKey);
  end;
end;

function SessionCanStart: Boolean;
begin
  Result := SessionAvailable and GIssues.CanStartIssue;
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

/// <summary>Nach „Meine Issues“ und nicht in der Stufe Minimal.</summary>
function WithSession(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := (ALevel <> TAtlasSafeLevel.Minimal) and SessionAvailable;
end;

function ProviderOf(const AName: string): IAtlasTrackerProvider;
var
  mAccess: IAtlasTrackerAccess;
begin
  Result := nil;
  mAccess := TrackerAccess;
  if mAccess <> nil then
  begin
    Result := mAccess.Provider(AName);
  end;
end;

// Im Hintergrund-Thread: Token aus dem Anmeldespeicher, ohne Dialog; ohne Token kein Transport (kein Netz).
function TransportOf(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
var
  mAccess: IAtlasTrackerAccess;
begin
  Result := nil;
  mAccess := GAccess;
  if mAccess <> nil then
  begin
    Result := mAccess.Transport(AProvider, ATarget);
  end;
end;

function CredentialsOf(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): Boolean;
var
  mAccess: IAtlasTrackerAccess;
begin
  mAccess := TrackerAccess;
  Result := (mAccess <> nil) and mAccess.EnterToken(AProvider, ATarget);
end;

// Nur Meldungsansicht: Die Zeilen können Branch-Namen enthalten. Jede Meldung folgt auf eine Aktion des Benutzers
// (Zugang, Beginnen, Git-Hook), deshalb sichtbar machen.
procedure IssuesMessage(AText: string);
begin
  TAtlasIdeHost.Message(AText);
  TAtlasIdeHost.ShowMessages;
end;

procedure NewIssueMessage(AText: string);
begin
  TAtlasIdeHost.Message(AText);
end;

// Zeiterfassung (#1267): „ATL-123 · 1:25“ als Zusatzfeld im Statusfeld, Klick öffnet das Menü der Uhr.
procedure TimeStatus(const AText, AHint: string; const AOnClick: TProc<TPoint>);
begin
  TAtlasIdeHost.SetStatusField(cIssueTimeExtra, AText, AHint, AOnClick);
end;

procedure ShowConnections;
begin
  TAtlasOptionsRegistration.ShowSetting(cSettingConnections);
end;

// Knopf „Tracker-Einstellungen …“ der Issue-Vorschau (#1264).
procedure ShowTrackerSettings;
begin
  TAtlasGuard.Run(TAtlasFeature.Settings, ShowConnections);
end;

// „zuordnen …“ (#1261): Seite Issue-Tracker mit vorbefüllter Zeile der Tabelle Projekte.
procedure AssignProject(AMatch: string);
begin
  TAtlasOptionsRegistration.ShowSetting(cSettingProjects, AMatch);
end;

// „Abfragen bearbeiten …“ (#1262): Seite Issue-Tracker bei der Tabelle Abfragen.
procedure EditQueries;
begin
  TAtlasOptionsRegistration.ShowSetting(cSettingQueries);
end;

function WelcomeLookup: TAtlasTrackerWelcomeLookup;
begin
  Result := Default(TAtlasTrackerWelcomeLookup);
  Result.Projects := WelcomeProjects;
  Result.Board := WelcomeBoard;
end;

function CreateIssues: TAtlasIdeIssues;
begin
  Result := TAtlasIdeIssues.Create(GWelcome, IssuesMessage);
  Result.ProviderFactory := ProviderOf;
  Result.TransportFactory := TransportOf;
  Result.OnCredentials := CredentialsOf;
  Result.OnTimeStatus := TimeStatus;
  Result.OnSettings := ShowTrackerSettings;
  Result.OnAssignProject := AssignProject;
  Result.OnEditQueries := EditQueries;
end;

procedure StartMyIssues;
begin
  TrackerAccess;
  GWelcome := TAtlasTrackerWelcomeLink.Create(WelcomeLookup);
  GIssues := CreateIssues;
  GIssuesRef := GIssues as IInterface;
  GIssues.Start;
  // „Issue anlegen …“ (#1268): Tracker, Transport und „Beginnen“ wie „Meine Issues“.
  TAtlasIdeNewIssue.Start(GIssues, NewIssueMessage);
  GTiles := [GScope.Provide(IAtlasWelcomeTile, TAtlasTrackerIssuesTile.Create(GIssues) as IAtlasWelcomeTile),
    GScope.Provide(IAtlasWelcomeTile, TAtlasTrackerSprintTile.Create(GIssues) as IAtlasWelcomeTile)];
end;

procedure StopMyIssues;
var
  mIndex: Integer;
begin
  // Zuerst die Kacheln: Die Seite gibt ihre Ansichten frei, solange die Quelle noch läuft.
  for mIndex := High(GTiles) downto 0 do
  begin
    GTiles[mIndex].Revoke;
  end;
  GTiles := nil;
  // Vor „Meine Issues“: wartet auf laufende Anfragen.
  TAtlasIdeNewIssue.Stop;
  if GIssues <> nil then
  begin
    GIssues.Stop;
  end;
  GIssues := nil;
  GIssuesRef := nil;
  if GWelcome <> nil then
  begin
    GWelcome.Release;
  end;
  FreeAndNil(GWelcome);
  GAccess := nil;
end;

function MyIssuesStarted: Boolean;
begin
  Result := SessionAvailable;
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
begin
  if SessionAvailable then
  begin
    GIssues.EnterCredentialsForActive;
  end;
end;

function TrackerLoginVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TrackerLogin and SessionAvailable;
end;

procedure CreateIssueNow;
begin
  if SessionAvailable and TAtlasIdeNewIssue.Enabled then
  begin
    TAtlasIdeNewIssue.FromEditor;
  end;
end;

procedure CreateIssue;
begin
  // Läuft in „Issue anlegen“ der Willkommensseite, daher deren Sicherung.
  TAtlasGuard.Run(TAtlasFeature.WelcomePage, CreateIssueNow);
end;

function CreateIssueVisible: Boolean;
begin
  Result := SessionAvailable and TAtlasIdeNewIssue.Enabled;
end;

function CreateIssueKey: Integer;
begin
  Result := TAtlasIdeSettings.Current.CreateIssueKey;
end;

procedure ShowPreviewPrompt;
begin
  if SessionAvailable then
  begin
    GIssues.ShowPreviewPrompt;
  end;
end;

function PreviewVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesPreview and SessionAvailable;
end;

procedure ShowBlameScope;
begin
  if GBlameIssues <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.BlameIssues, GBlameIssues.ShowScope);
  end;
end;

function BlameVisible: Boolean;
begin
  Result := TAtlasIdeBlameLinks.Enabled and (GBlameIssues <> nil);
end;

procedure ShowTimeOpen;
begin
  if SessionAvailable then
  begin
    GIssues.ShowTimeOpen;
  end;
end;

function TimeVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesTimeTracking and SessionAvailable;
end;

procedure ShowBoard;
begin
  if SessionAvailable and (GIssues.Board <> nil) then
  begin
    GIssues.Board.Show;
  end;
end;

function BoardVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesBoard and SessionAvailable;
end;

procedure AttachPrompt;
begin
  if SessionAvailable then
  begin
    GIssues.AttachPrompt;
  end;
end;

function AttachVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesAttach and SessionAvailable;
end;

{ TAtlasTrackerModule }

function TAtlasTrackerModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := cModuleId;
  Result.Name := 'Issue-Tracker';
  Result.Version := TAtlasVersion.Version;
  Result.Handle := HInstance;
  // Lief mit der Willkommensseite schon im abgesicherten Start.
  Result.MinLevel := TAtlasSafeLevel.Safe;
  Result.Switch := cSwitch;
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

procedure TAtlasTrackerModule.ApplySettings;
begin
  // welcomePage.issues, issues.tracker, .query, die Muster, issues.notify, welcomePage.sprint (#765, #1277).
  if SessionAvailable then
  begin
    GIssues.Refresh;
  end;
end;

function TAtlasTrackerModule.PaletteSource: IAtlasPaletteSource;
begin
  Result := nil;
  if SessionAvailable then
  begin
    Result := GIssues.PaletteSearch;
  end;
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
  begin
    Exit;
  end;
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
  // Zuerst „Meine Issues“ (Tracker und Vorschau), danach die Teile, die es brauchen; Abbau rückwärts.
  Result := [
    TAtlasFeaturePart.AtLevel('MyIssues', TAtlasSafeLevel.Safe, MyIssuesStarted, StartMyIssues, StopMyIssues),
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
  begin
    Exit;
  end;
  // Regel 7: zuerst die Vertragsversion von Base (FindClassHInstance einer Base-Klasse, Regel 8).
  if TAtlasContractHandshake.Check(FindClassHInstance(TAtlasModuleRegistry), cAtlasCoreContractVersion) <>
    ccMatch then
  begin
    TAtlasGuard.Log(Format(cLogContractMismatch, [cModuleId], TFormatSettings.Invariant));
    Exit;
  end;
  mModule := TAtlasTrackerModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasKeySource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasPaletteSourceProvider, mRef);
  GScope.Provide(IAtlasSettingsSectionProvider, TAtlasIdeTrackerSettings.Create as IAtlasSettingsSectionProvider);
  Result := True;
end;

class procedure TAtlasTrackerModule.UnregisterModule;
var
  mRegistry: IAtlasModuleRegistry;
  mFailure: string;
begin
  if GScope = nil then
  begin
    Exit;
  end;
  GScope := nil;
  // Regel 5: nur, solange Base noch läuft; sonst hat Base das Modul schon gestoppt und abgemeldet.
  mRegistry := AtlasModuleRegistry;
  if mRegistry <> nil then
  begin
    for mFailure in mRegistry.UnregisterModule(cModuleId) do
    begin
      TAtlasGuard.Log(Format(cLogUnregisterFailed, [cModuleId, mFailure], TFormatSettings.Invariant));
    end;
  end;
  // Laufende Prüfungen der Optionsseite: Ihre Antwort erreicht das Modul danach nicht mehr (Regel 3).
  TAtlasIdeTrackerSettings.Release;
end;

initialization
  TAtlasTrackerModule.RegisterModule;

finalization
  TAtlasTrackerModule.UnregisterModule;

end.
