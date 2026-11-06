unit Atlas.IDE.Tracker.Parts;

// Teile, Befehle und Menüeinträge des Moduls Tracker (#1455), aus
// Atlas.IDE.Tracker.Composition herausgelöst, damit die Komposition nur
// anmeldet und die Adapter baut (Rolle Composition). Die Komposition übergibt
// Scope und Zugänge (Install) und reicht Teile, Befehle, Menü, Tasten,
// Einstellungen und Palette ihres Moduls hierher weiter.
// - MyIssues: „Meine Issues“ (#765) mit Vorschau, Beginnen, Board,
//   Zeiterfassung, Anhängen und „Issue anlegen“ (#1268); die Kacheln „Meine
//   Issues“ und „Sprint“ (#1277) und IAtlasIssueCreation für Base (#1355).
// - IssueLinks und BlameIssues: Issue-Kennungen im Code (#1265) und in der
//   Zeilenhistorie (#1275); Base hält die Haken nur, solange BlameIssues läuft
//   (Regel 3).
// - TestResults: Kachel „Testergebnisse“ (#763) mit eigener Verbindung zur
//   Willkommensseite; hört als IAtlasProjectSummaryListener auf Base.
// Ohne MyIssues sind die Befehle des Trackers unsichtbar. Alle Anmeldungen
// laufen über den Scope des Moduls (Regel 4). Hauptthread; nur der Transport
// des Trackers läuft auch im Hintergrund.

interface

uses
  System.SysUtils,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.IDE.Tracker.Access;

type
  TAtlasTrackerParts = class
  public
    /// <summary>Vor Parts: AScope des Moduls, AAccess Zugang zum Tracker, ACiAccess Zugang zum Build-Server.
    /// </summary>
    class procedure Install(const AScope: IAtlasModuleScope; const AAccess: IAtlasTrackerAccess;
      const ACiAccess: IAtlasCiAccess); static;
    /// <summary>Nach dem Abmelden (alle Teile gestoppt): Scope und Zugänge loslassen.</summary>
    class procedure Uninstall; static;
    class function Parts: TArray<IAtlasFeaturePart>; static;
    class function Commands: TArray<TAtlasModuleCommand>; static;
    class function MenuEntries: TArray<TAtlasMenuEntry>; static;
    class function Keys: TArray<TAtlasModuleKey>; static;
    /// <summary>Geänderte Einstellungen an „Meine Issues“, Sprint und „Testergebnisse“.</summary>
    class procedure ApplySettings; static;
    /// <summary>Issues in der Befehlspalette (#1270); nil ohne „Meine Issues“.</summary>
    class function PaletteSource: IAtlasPaletteSource; static;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.IDE.Contracts.WelcomeTiles,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.LineChanges,
  Atlas.IDE.Projects.Summaries,
  Atlas.IDE.Settings.Options,
  Atlas.IDE.Tracker.IssuePreview,
  Atlas.IDE.Tracker.CodeLinks,
  Atlas.IDE.Tracker.BlameLinks,
  Atlas.IDE.Tracker.IssuesContext,
  Atlas.IDE.Tracker.MyIssues,
  Atlas.IDE.Tracker.NewIssue,
  Atlas.IDE.Tracker.TestResults,
  Atlas.IDE.Tracker.Tiles,
  Atlas.IDE.Tracker.WelcomeLink,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Strings;

const
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
  /// <summary>Zugang zum Tracker von Install bis Uninstall; der Transport liest ihn im Hintergrund.</summary>
  GAccess: IAtlasTrackerAccess;
  /// <summary>Zugang zum Build-Server für „Testergebnisse“.</summary>
  GCiAccess: IAtlasCiAccess;
  /// <summary>Kacheln der Willkommensseite und „Issue anlegen“ für Base, solange MyIssues läuft.</summary>
  GTiles: TArray<IAtlasRegistration>;
  /// <summary>„Testergebnisse“ (#763) mit eigener Verbindung zur Willkommensseite, solange TestResults läuft.
  /// </summary>
  GTestsWelcome: TAtlasTrackerWelcomeLink;
  GTests: TAtlasIdeTestResults;
  GTestsRef: IInterface;
  GTestsRegistrations: TArray<IAtlasRegistration>;

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
  Result := SessionAvailable and GIssues.Commands.CodeTarget(ATarget);
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
    Result := GIssues.Services.Preview;
  end;
end;

procedure SessionShow(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  if SessionAvailable then
  begin
    GIssues.Commands.ShowIssue(ATarget, AKey);
  end;
end;

procedure SessionBrowse(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  if SessionAvailable then
  begin
    GIssues.Commands.BrowseIssue(ATarget, AKey);
  end;
end;

procedure SessionStart(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  if SessionAvailable then
  begin
    GIssues.Commands.StartIssue(ATarget, AKey);
  end;
end;

function SessionCanStart: Boolean;
begin
  Result := SessionAvailable and GIssues.Context.CanStart;
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
  mAccess := GAccess;
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
  mAccess := GAccess;
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
var
  mHooks: TAtlasIdeIssuesHooks;
begin
  Result := TAtlasIdeIssues.Create(GWelcome, IssuesMessage);
  mHooks := Default(TAtlasIdeIssuesHooks);
  mHooks.Provider := ProviderOf;
  mHooks.Transport := TransportOf;
  mHooks.Credentials := CredentialsOf;
  mHooks.TimeStatus := TimeStatus;
  mHooks.Settings := ShowTrackerSettings;
  mHooks.AssignProject := AssignProject;
  mHooks.EditQueries := EditQueries;
  Result.Context.Hooks := mHooks;
end;

procedure StartMyIssues;
begin
  GWelcome := TAtlasTrackerWelcomeLink.Create(WelcomeLookup);
  GIssues := CreateIssues;
  GIssuesRef := GIssues as IInterface;
  GIssues.Start;
  // „Issue anlegen …“ (#1268): Tracker, Transport und „Beginnen“ wie „Meine Issues“.
  TAtlasIdeNewIssue.Start(GIssues, NewIssueMessage);
  GTiles := [GScope.Provide(IAtlasWelcomeTile, TAtlasTrackerIssuesTile.Create(GIssues) as IAtlasWelcomeTile),
    GScope.Provide(IAtlasWelcomeTile, TAtlasTrackerSprintTile.Create(GIssues) as IAtlasWelcomeTile),
    GScope.Provide(IAtlasIssueCreation, TAtlasIdeIssueCreation.Create as IAtlasIssueCreation)];
end;

procedure StopMyIssues;
var
  mIndex: Integer;
begin
  // Zuerst Kacheln und „Issue anlegen“: Die Seite gibt ihre Ansichten frei, solange die Quelle noch läuft.
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
end;

function MyIssuesStarted: Boolean;
begin
  Result := SessionAvailable;
end;

// „Testergebnisse“ (#763): Kachel und Zuhörer der Zusammenfassungen; abgefragt wird erst beim Anzeigen.
procedure StartTestResults;
begin
  GTestsWelcome := TAtlasTrackerWelcomeLink.Create(WelcomeLookup);
  GTests := TAtlasIdeTestResults.Create(GTestsWelcome, GCiAccess, NewIssueMessage);
  GTestsRef := GTests;
  GTests.Start;
  GTestsRegistrations := [
    GScope.Provide(IAtlasWelcomeTile, TAtlasTrackerTestsTile.Create(GTests) as IAtlasWelcomeTile),
    GScope.Provide(IAtlasProjectSummaryListener, GTests as IAtlasProjectSummaryListener)];
end;

procedure StopTestResults;
var
  mIndex: Integer;
begin
  // Zuerst Kachel und Zuhörer, dann die Abfrage (wartet kurz auf den Build-Server).
  for mIndex := High(GTestsRegistrations) downto 0 do
  begin
    GTestsRegistrations[mIndex].Revoke;
  end;
  GTestsRegistrations := nil;
  if GTests <> nil then
  begin
    GTests.Stop;
  end;
  GTests := nil;
  GTestsRef := nil;
  if GTestsWelcome <> nil then
  begin
    GTestsWelcome.Release;
  end;
  FreeAndNil(GTestsWelcome);
end;

function TestResultsStarted: Boolean;
begin
  Result := GTests <> nil;
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
    GIssues.Query.EnterCredentialsForActive;
  end;
end;

function TrackerLoginVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TrackerLogin and SessionAvailable;
end;

procedure EnterCiCredentials;
begin
  if GTests <> nil then
  begin
    GTests.EnterCredentialsForActive;
  end;
end;

function CiLoginVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.CiLogin and (GTests <> nil);
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
  TAtlasGuard.Run(TAtlasFeature.Tracker, CreateIssueNow);
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
    GIssues.Commands.ShowPreviewPrompt;
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
    GIssues.Services.ShowTimeOpen;
  end;
end;

function TimeVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesTimeTracking and SessionAvailable;
end;

procedure ShowBoard;
begin
  if SessionAvailable and (GIssues.Services.Board <> nil) then
  begin
    GIssues.Services.Board.Show;
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
    GIssues.Commands.AttachPrompt;
  end;
end;

function AttachVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesAttach and SessionAvailable;
end;


{ TAtlasTrackerParts }

class procedure TAtlasTrackerParts.Install(const AScope: IAtlasModuleScope; const AAccess: IAtlasTrackerAccess;
  const ACiAccess: IAtlasCiAccess);
begin
  GScope := AScope;
  GAccess := AAccess;
  GCiAccess := ACiAccess;
end;

class procedure TAtlasTrackerParts.Uninstall;
begin
  GScope := nil;
  GCiAccess := nil;
  GAccess := nil;
end;

class function TAtlasTrackerParts.Commands: TArray<TAtlasModuleCommand>;
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
      AttachVisible),
    // Zugang zum Build-Server (#763): für die .atlas des aktiven Projekts; sichtbar mit ci.login und der Kachel.
    Command('Atlas.CiLogin', TAtlasStrings.Text(TAtlasTextId.CiLoginCommand), EnterCiCredentials, CiLoginVisible)];
end;

class procedure TAtlasTrackerParts.ApplySettings;
begin
  // welcomePage.issues, issues.tracker, .query, die Muster, issues.notify, welcomePage.sprint (#765, #1277).
  if SessionAvailable then
  begin
    GIssues.Refresh;
  end;
  // welcomePage.tests, .maxFailures und .ci (#763).
  if GTests <> nil then
  begin
    GTests.Refresh;
  end;
end;

class function TAtlasTrackerParts.PaletteSource: IAtlasPaletteSource;
begin
  Result := nil;
  if SessionAvailable then
  begin
    Result := GIssues.Services.PaletteSearch;
  end;
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

class function TAtlasTrackerParts.MenuEntries: TArray<TAtlasMenuEntry>;
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

class function TAtlasTrackerParts.Keys: TArray<TAtlasModuleKey>;
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

class function TAtlasTrackerParts.Parts: TArray<IAtlasFeaturePart>;
begin
  // Zuerst „Meine Issues“ (Tracker und Vorschau), danach die Teile, die es brauchen; Abbau rückwärts.
  Result := [
    TAtlasFeaturePart.AtLevel('MyIssues', TAtlasSafeLevel.Safe, MyIssuesStarted, StartMyIssues, StopMyIssues),
    TAtlasFeaturePart.When('IssueLinks', WithSession, IssueLinksStarted, StartIssueLinks, StopIssueLinks),
    TAtlasFeaturePart.When('BlameIssues', WithSession, BlameIssuesStarted, StartBlameIssues, StopBlameIssues),
    // Unabhängig von „Meine Issues“: lokale Testläufe auch ohne Tracker.
    TAtlasFeaturePart.AtLevel('TestResults', TAtlasSafeLevel.Safe, TestResultsStarted, StartTestResults,
      StopTestResults)];
end;


end.
