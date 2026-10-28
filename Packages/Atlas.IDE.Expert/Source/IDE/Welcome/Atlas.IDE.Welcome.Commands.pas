unit Atlas.IDE.Welcome.Commands;

// Steuerung der Atlas-Willkommensseite (#753):
// - Die Atlas-Bereiche stehen nur im andockbaren Fenster „Atlas-Start“
//   (#1114); auf der Willkommensseite der IDE meldet Atlas nichts mehr an.
//   Das Fenster öffnet über Ansicht › Atlas-Start, das Atlas-Menü, die
//   Befehlspalette und den Desktop der IDE; mit welcomePage.openOnStart auch
//   beim Start, mit welcomePage.openWhenNoProject (Vorgabe an), sobald das
//   letzte Projekt geschlossen ist (nicht beim Beenden der IDE). Sync füllt
//   es nach den Einstellungen; welcomePage.enabled aus: Fenster zu, nichts
//   angezeigt.
// - Aufräumen beim Start (#1114, TAtlasWelcomeRetire): Gibt es noch die
//   Sicherung %LOCALAPPDATA%\Atlas\welcomepage-layout-backup.json aus
//   „Atlas-Layout anwenden“ früherer Fassungen, schreibt Atlas sie zurück und
//   löscht sie; sonst nimmt es seine Kennungen aus dem Registry-Schlüssel
//   WelcomePage der IDE. Hält die IDE ihr Layout im Speicher und schreibt es
//   beim Beenden zurück, wiederholt der nächste Start den gewünschten Stand
//   (Marke …-pending).
// - Kopf: Grußzeile nach Uhrzeit und Vorname des Windows-Kontos, Version,
//   Kurzstatus aus Server und Index; neu bei jeder Änderung im Statusfeld.
//   Rechts das Suchfeld (#760, welcomePage.search), angebunden an Search.
// - Karte „Neu in Atlas“ (#756, WhatsNew): nach einem Update oben in der
//   ersten Spalte; Kontextmenü von Frame „Atlas“ und Kopf mit „Neuigkeiten
//   dieser Version zeigen“ und „Alle Versionen“ (nicht bei
//   welcomePage.whatsNew = off).
// - Bereich „Weiterarbeiten“ (#755, ContinueWork): Arbeitsstand je Projekt
//   (Reiter, letzte Änderung), eingehende Commits und „Gemerkt“; schreibt
//   beim Schließen und beim Beenden (Stop) und meldet sich selbst an.
// - Bereich „Projekte“ (#592, Projects): Zustand je zuletzt geöffnetem
//   Projekt aus den Projekt-Zusammenfassungen; meldet sich selbst an.
// - Schnellaktionen (#764, QuickActions): Knopfleiste in „Projekte“ und
//   „Weiterarbeiten“; die Quelle bekommen beide Bereiche für ihre Frames.
// - Bereich „Projektverlauf“ (#758, Trends): Linien je Reihe über die
//   letzten Builds des in „Projekte“ gewählten Projekts; meldet sich selbst
//   an.
// - Bereich „Testergebnisse“ (#763, TestResults): letzter Testlauf je Projekt
//   und, mit welcomePage.tests.ci, der letzte Build des Build-Servers;
//   meldet sich selbst an.
// - Bereich „Meine Issues“ (#765, Issues): offene Issues aus GitHub oder
//   YouTrack, „Beginnen“ und das aktuelle Issue im Statusfeld; meldet sich
//   selbst an.
// - Bereich „Nicht gesichert“ (#762, Unsaved): nicht Committetes, nicht
//   Gepushtes und Stashes je Projekt; meldet sich selbst an.
// - Zustandskachel „Atlas“ (#754, State): Server, Version, Index,
//   Einrichtung und Diagnosemodus aus den Zeilen des Statusfelds (#591);
//   meldet sich selbst an.
// - Karte „Atlas entdecken“ (#757, Discover): ein Tipp je Start aus tips.json
//   nach der gemeinsamen Zählung (#600); meldet sich selbst an.
// - Bereich „Hilfe und Rückmeldung“ (#766, Help): Atlas-Doku, Tastenkürzel
//   (#520) und „Problem melden …“ mit Diagnosepaket; meldet sich selbst an.
// - Bereich „<Projekt> für Atlas einrichten“ (#759, Setup): atlas.json,
//   Baseline, Suchpfade und Defines je Projekt sowie „Neu mit Atlas“; meldet
//   sich selbst an.
// - Seite anpassen (#767, Layouts): Bearbeitungsmodus, Anordnung, Breite,
//   Spalten, mehrere Layouts und Ein-/Ausblenden über die Einstellungen der
//   Bereiche im Fenster „Atlas-Start“ (mit gefalteten Spalten, wenn es schmal
//   ist); der Befehl öffnet das Fenster. Neue Bereiche meldet „Neu in Atlas“.
// Die Willkommensseite startet keinen Server und liest nur lokale Daten;
// einzige Ausnahme ist die Abfrage beim Build-Server (#763,
// welcomePage.tests.ci, Vorgabe aus).

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Status.Lines,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Backup,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Header,
  Atlas.UI.Welcome.Board,
  Atlas.IDE.Status.Lines,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.WhatsNew,
  Atlas.IDE.Welcome.Projects,
  Atlas.IDE.Welcome.QuickActions,
  Atlas.IDE.Welcome.Trends,
  Atlas.IDE.Welcome.TestResults,
  Atlas.IDE.Welcome.Issues,
  Atlas.IDE.Welcome.Unsaved,
  Atlas.IDE.Welcome.Continue,
  Atlas.IDE.Welcome.State,
  Atlas.IDE.Welcome.Discover,
  Atlas.IDE.Welcome.Help,
  Atlas.IDE.Welcome.Setup,
  Atlas.IDE.Welcome.Layouts;

type
  TAtlasIdeWelcome = class
  private
    FServerInfo: TFunc<TAtlasServerInfo>;
    FIndexing: TAtlasIndexingFunc;
    FUnits: TFunc<Integer>;
    FMessage: TProc<string>;
    FSectionsListener: Integer;
    FStatusListener: Integer;
    FQueued: Boolean;
    FDirty: TArray<string>;
    // Erster Sync gelaufen (welcomePage.openOnStart wirkt nur beim Start).
    FStarted: Boolean;
    // Beobachter für geschlossene Projekte (welcomePage.openWhenNoProject); die IDE hält ihn.
    FProjectWatch: TObject;
    FProjectWatchIndex: Integer;
    // Prüfung „noch ein Projekt offen?“ ist eingereiht.
    FNoProjectQueued: Boolean;
    FAccess: IAtlasRegistryAccess;
    FSearch: TAtlasIdeWelcomeSearch;
    FWhatsNew: TAtlasIdeWhatsNew;
    // Hält die Quelle der Karte am Leben; die Frames halten sie ebenfalls als Schnittstelle.
    FWhatsNewRef: IInterface;
    FProjects: TAtlasIdeProjects;
    // Hält die Quelle des Bereichs „Projekte“ am Leben; die Frames halten sie ebenfalls.
    FProjectsRef: IInterface;
    FQuickActions: TAtlasIdeQuickActions;
    // Hält die Quelle der Schnellaktionen am Leben; Bereiche und Frames halten sie ebenfalls.
    FQuickActionsRef: IInterface;
    FTrends: TAtlasIdeTrends;
    // Hält die Quelle des Bereichs „Projektverlauf“ am Leben; die Frames halten sie ebenfalls.
    FTrendsRef: IInterface;
    FTestResults: TAtlasIdeTestResults;
    // Hält die Quelle des Bereichs „Testergebnisse“ am Leben; die Frames halten sie ebenfalls.
    FTestResultsRef: IInterface;
    FIssues: TAtlasIdeIssues;
    // Hält die Quelle des Bereichs „Meine Issues“ am Leben; die Frames halten sie ebenfalls.
    FIssuesRef: IInterface;
    FUnsaved: TAtlasIdeUnsaved;
    // Hält die Quelle des Bereichs „Nicht gesichert“ am Leben; die Frames halten sie ebenfalls.
    FUnsavedRef: IInterface;
    FContinue: TAtlasIdeContinue;
    // Hält die Quelle des Bereichs „Weiterarbeiten“ am Leben; die Frames halten sie ebenfalls.
    FContinueRef: IInterface;
    FState: TAtlasIdeWelcomeState;
    // Hält die Quelle der Zustandskachel am Leben; die Frames halten sie ebenfalls.
    FStateRef: IInterface;
    FDiscover: TAtlasIdeDiscover;
    // Hält die Quelle der Karte „Atlas entdecken“ am Leben; die Frames halten sie ebenfalls.
    FDiscoverRef: IInterface;
    FHelp: TAtlasIdeHelp;
    // Hält die Quelle des Bereichs „Hilfe und Rückmeldung“ am Leben; die Frames halten sie ebenfalls.
    FHelpRef: IInterface;
    FSetup: TAtlasIdeSetup;
    // Hält die Quelle des Bereichs „Projekt für Atlas einrichten“ am Leben; die Frames halten sie ebenfalls.
    FSetupRef: IInterface;
    FLayouts: TAtlasIdeWelcomeLayouts;
    // Hält die Quelle für „Seite anpassen“ am Leben; die Tafeln halten sie ebenfalls.
    FLayoutsRef: IInterface;
    procedure Announce(const AIds: TArray<string>);
    procedure SetWhatsNew(AValue: TAtlasIdeWhatsNew);
    procedure SetState(AValue: TAtlasIdeWelcomeState);
    procedure SetDiscover(AValue: TAtlasIdeDiscover);
    procedure SetHelp(AValue: TAtlasIdeHelp);
    procedure SetSetup(AValue: TAtlasIdeSetup);
    procedure SetProjects(AValue: TAtlasIdeProjects);
    procedure SetQuickActions(AValue: TAtlasIdeQuickActions);
    procedure SetTrends(AValue: TAtlasIdeTrends);
    procedure SetTestResults(AValue: TAtlasIdeTestResults);
    procedure SetIssues(AValue: TAtlasIdeIssues);
    procedure SetUnsaved(AValue: TAtlasIdeUnsaved);
    procedure SetContinue(AValue: TAtlasIdeContinue);
    procedure AttachMenu(AFrame: TAtlasWelcomeFrame);
    procedure SectionChanged(const AId: string);
    procedure Flush;
    procedure UpdateSection(const AId: string);
    /// <summary>Tafel füllen; AFold: Fenster „Atlas-Start“ (Spalten falten, wenn es schmal ist).</summary>
    procedure FillBoard(ABoard: TAtlasWelcomeBoardFrame; AFold: Boolean);
    procedure FillHeader(AHeader: TAtlasWelcomeHeaderFrame);
    procedure UpdateHeaders;
    function WelcomeKey: string;
    procedure CheckPending;
    procedure RetireIdeLayout;
    procedure WatchProjects;
    procedure UnwatchProjects;
    /// <summary>Ein Projekt oder eine Projektgruppe wird geschlossen: danach prüfen, ob noch eines offen ist.
    /// </summary>
    procedure ProjectClosing;
    procedure CheckNoProject;
    class function OpenProjectCount: Integer; static;
    class function IdeRunning: Boolean; static;
    procedure Report(const AText: string);
    class function AtlasFolder: string; static;
    class function PendingFile: string; static;
  public
    /// <summary>AServerInfo: Phase und Version des Servers; AIndexing(Prozent): läuft die Indizierung;
    /// AUnits: Units im Index (-1 unbekannt); AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(const AServerInfo: TFunc<TAtlasServerInfo>; const AIndexing: TAtlasIndexingFunc;
      const AUnits: TFunc<Integer>; const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Einstellungen anwenden (beim Laden und nach jeder Änderung).</summary>
    procedure Sync;
    /// <summary>Menü Ansicht › Atlas-Start.</summary>
    procedure ShowStart;
    /// <summary>Befehle „Neuigkeiten dieser Version zeigen“ und „Alle Versionen“ (#756); im Fenster
    /// „Atlas-Start“ öffnet es dieses.</summary>
    procedure ShowWhatsNew(AView: TAtlasWhatsNewView);
    /// <summary>Befehl „Willkommensseite anpassen“ (#767): Bearbeitungsmodus an/aus im Fenster „Atlas-Start“
    /// (öffnet es beim Einschalten).</summary>
    procedure Customize;
    procedure ThemeChanged;
    /// <summary>Wird für Tests ersetzt; Vorgabe: Registry der IDE.</summary>
    property Access: IAtlasRegistryAccess read FAccess write FAccess;
    /// <summary>Suchfeld (#760); gehört danach der Steuerung. nil = ohne Suchfeld.</summary>
    property Search: TAtlasIdeWelcomeSearch read FSearch write FSearch;
    /// <summary>Karte „Neu in Atlas“ (#756); gehört danach der Steuerung (Start beim Setzen). nil = ohne.</summary>
    property WhatsNew: TAtlasIdeWhatsNew read FWhatsNew write SetWhatsNew;
    /// <summary>Bereich „Projekte“ (#592); gehört danach der Steuerung (Start beim Setzen). nil = ohne.</summary>
    property Projects: TAtlasIdeProjects read FProjects write SetProjects;
    /// <summary>Schnellaktionen (#764); vor ContinueWork und vor dem ersten Sync setzen, nach Projects.</summary>
    property QuickActions: TAtlasIdeQuickActions read FQuickActions write SetQuickActions;
    /// <summary>Bereich „Projektverlauf“ (#758); gehört danach der Steuerung (Start beim Setzen). nil = ohne.
    /// </summary>
    property Trends: TAtlasIdeTrends read FTrends write SetTrends;
    /// <summary>Bereich „Testergebnisse“ (#763); gehört danach der Steuerung (Start beim Setzen). nil = ohne.
    /// </summary>
    property TestResults: TAtlasIdeTestResults read FTestResults write SetTestResults;
    /// <summary>Bereich „Meine Issues“ (#765); gehört danach der Steuerung (Start beim Setzen). nil = ohne.</summary>
    property Issues: TAtlasIdeIssues read FIssues write SetIssues;
    /// <summary>Bereich „Nicht gesichert“ (#762); gehört danach der Steuerung (Start beim Setzen). nil = ohne.</summary>
    property Unsaved: TAtlasIdeUnsaved read FUnsaved write SetUnsaved;
    /// <summary>Bereich „Weiterarbeiten“ (#755); gehört danach der Steuerung (Start beim Setzen). nil = ohne.
    /// Nicht „Continue“: Das verdeckte in den Methoden die Prozedur System.Continue.</summary>
    property ContinueWork: TAtlasIdeContinue read FContinue write SetContinue;
    /// <summary>Zustandskachel „Atlas“ (#754); gehört danach der Steuerung (Start beim Setzen). nil = ohne.</summary>
    property State: TAtlasIdeWelcomeState read FState write SetState;
    /// <summary>Karte „Atlas entdecken“ (#757); gehört danach der Steuerung (Start beim Setzen). nil = ohne.
    /// </summary>
    property Discover: TAtlasIdeDiscover read FDiscover write SetDiscover;
    /// <summary>Bereich „Hilfe und Rückmeldung“ (#766); gehört danach der Steuerung (Start beim Setzen). nil =
    /// ohne.</summary>
    property Help: TAtlasIdeHelp read FHelp write SetHelp;
    /// <summary>Bereich „Projekt für Atlas einrichten“ (#759); gehört danach der Steuerung (Start beim Setzen).
    /// nil = ohne.</summary>
    property Setup: TAtlasIdeSetup read FSetup write SetSetup;
    /// <summary>Quelle für „Seite anpassen“ (#767); gehört der Steuerung.</summary>
    property Layouts: TAtlasIdeWelcomeLayouts read FLayouts;
    class function HeaderInfo(const AServer: TAtlasServerInfo; AIndexing: Boolean; APercent, AUnits: Integer;
      AHour: Integer; const AFirstName: string; AGreeting: Boolean): TAtlasWelcomeHeaderInfo; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Winapi.Windows,
  System.IOUtils,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Status.Registry,
  Atlas.Core.Welcome.Greeting,
  Atlas.Core.Welcome.Layout,
  Atlas.Core.Welcome.Layouts,
  Atlas.Core.Welcome.HostLayout,
  Atlas.Core.Welcome.Projects,
  Atlas.Core.Welcome.Search,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.WhatsNew,
  Atlas.UI.Welcome.Arrange,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Welcome.Registry,
  Atlas.IDE.Welcome.Window;

type
  // Meldet das Schließen von Projekten und Projektgruppen an die Steuerung (#1114).
  TAtlasWelcomeProjectWatch = class(TNotifierObject, IOTAIDENotifier)
  private
    FOwner: TAtlasIdeWelcome;
  public
    procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
    procedure AfterCompile(Succeeded: Boolean); overload;
  end;

const
  NameDisplay = 3;

function GetUserNameExW(ANameFormat: Integer; ABuffer: PWideChar; var ASize: ULONG): BOOL; stdcall;
  external 'secur32.dll' name 'GetUserNameExW';

var
  // Lebt die Steuerung noch? Für Arbeit, die über die Nachrichtenschleife kommt.
  Instance: TAtlasIdeWelcome;

function DisplayName: string;
var
  Size: ULONG;
  Buffer: array[0..255] of WideChar;
begin
  // Puffer leeren und nur die gemeldete Länge übernehmen: Bei lokalen Konten meldet die Funktion teils
  // Erfolg, ohne etwas zu schreiben; dann stand Speicherrest als Vorname im Gruß.
  FillChar(Buffer, SizeOf(Buffer), 0);
  Size := Length(Buffer);
  Result := '';
  if GetUserNameExW(NameDisplay, @Buffer[0], Size) and (Size > 0) and (Size < ULONG(Length(Buffer))) then
    SetString(Result, PWideChar(@Buffer[0]), Size);
  Result := Trim(Result);
end;

/// <summary>Textdatei lesen, mit oder ohne Byte-Order-Mark (frühere Fassungen schrieben eines); teilt Löschen,
/// damit es das atomare Ersetzen nicht blockiert. EInOutError, wenn sie nicht lesbar ist.</summary>
function ReadText(const AFileName: string): string;
begin
  if not TAtlasDataFile.TryRead(AFileName, Result) then
    raise EInOutError.Create('Datei der Willkommensseite nicht lesbar');
end;

function Settings: TAtlasPluginSettings;
begin
  Result := TAtlasIdeSettings.Current;
end;

{ TAtlasWelcomeProjectWatch }

procedure TAtlasWelcomeProjectWatch.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
var
  Owner: TAtlasIdeWelcome;
begin
  Owner := FOwner;
  if (Owner = nil) or (NotifyCode <> ofnFileClosing) or not TAtlasWelcomeSearch.IsProjectFile(FileName) then
    Exit;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      Owner.ProjectClosing;
    end);
end;

procedure TAtlasWelcomeProjectWatch.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TAtlasWelcomeProjectWatch.AfterCompile(Succeeded: Boolean);
begin
end;

{ TAtlasIdeWelcome }

constructor TAtlasIdeWelcome.Create(const AServerInfo: TFunc<TAtlasServerInfo>;
  const AIndexing: TAtlasIndexingFunc; const AUnits: TFunc<Integer>; const AMessage: TProc<string>);
begin
  inherited Create;
  Instance := Self;
  FServerInfo := AServerInfo;
  FIndexing := AIndexing;
  FUnits := AUnits;
  FMessage := AMessage;
  FAccess := TAtlasIdeRegistryAccess.Create;
  FLayouts := TAtlasIdeWelcomeLayouts.Create(
    procedure
    begin
      if Instance <> nil then
        Instance.Sync;
    end);
  FLayoutsRef := FLayouts;
  FLayouts.OnAnnounce :=
    procedure(AIds: TArray<string>)
    begin
      if Instance <> nil then
        Instance.Announce(AIds);
    end;
  FSectionsListener := TAtlasWelcomeSections.Default.AddListener(
    procedure(AId: string)
    begin
      SectionChanged(AId);
    end);
  FStatusListener := TAtlasStatusRegistry.Default.AddListener(
    procedure
    begin
      SectionChanged(TAtlasWelcomeIds.Header);
    end);
  TAtlasIdeWelcomeWindow.OnFrame :=
    procedure(ABoard: TAtlasWelcomeBoardFrame)
    begin
      FillBoard(ABoard, True);
    end;
  // Früh anmelden: Die IDE speichert das Fenster im Desktop und legt es beim Laden selbst an (#879).
  TAtlasIdeWelcomeWindow.Prepare;
  CheckPending;
  RetireIdeLayout;
  FProjectWatchIndex := -1;
  WatchProjects;
end;

destructor TAtlasIdeWelcome.Destroy;
begin
  Instance := nil;
  UnwatchProjects;
  // Vor den Frames: löst die Suchfelder, die noch leben.
  FreeAndNil(FSearch);
  TAtlasWelcomeSections.Default.RemoveListener(FSectionsListener);
  TAtlasStatusRegistry.Default.RemoveListener(FStatusListener);
  // Vor „Projekte“: Die Schnellaktionen fragen dort nach dem Stand der Versionsverwaltung.
  if FQuickActions <> nil then
    FQuickActions.Stop;
  if FWhatsNew <> nil then
    FWhatsNew.Stop;
  if FTrends <> nil then
    FTrends.Stop;
  // Wartet kurz auf eine laufende Abfrage beim Build-Server.
  if FTestResults <> nil then
    FTestResults.Stop;
  // Wartet kurz auf eine laufende Abfrage beim Issue-Tracker; meldet die Statuszeile ab.
  if FIssues <> nil then
    FIssues.Stop;
  if FProjects <> nil then
    FProjects.Stop;
  if FUnsaved <> nil then
    FUnsaved.Stop;
  // Schreibt den Arbeitsstand des noch offenen Projekts (Beenden der IDE).
  if FContinue <> nil then
    FContinue.Stop;
  if FState <> nil then
    FState.Stop;
  if FDiscover <> nil then
    FDiscover.Stop;
  if FHelp <> nil then
    FHelp.Stop;
  if FSetup <> nil then
    FSetup.Stop;
  TAtlasIdeWelcomeWindow.Release;
  // Nach den Frames: Sie halten die Quelle der Karte ebenfalls.
  FWhatsNew := nil;
  FWhatsNewRef := nil;
  FProjects := nil;
  FProjectsRef := nil;
  FQuickActions := nil;
  FQuickActionsRef := nil;
  FTrends := nil;
  FTrendsRef := nil;
  FTestResults := nil;
  FTestResultsRef := nil;
  FIssues := nil;
  FIssuesRef := nil;
  FUnsaved := nil;
  FUnsavedRef := nil;
  FContinue := nil;
  FContinueRef := nil;
  FState := nil;
  FStateRef := nil;
  FDiscover := nil;
  FDiscoverRef := nil;
  FHelp := nil;
  FHelpRef := nil;
  FSetup := nil;
  FSetupRef := nil;
  FLayouts := nil;
  FLayoutsRef := nil;
  inherited;
end;

procedure TAtlasIdeWelcome.SetState(AValue: TAtlasIdeWelcomeState);
begin
  FState := AValue;
  FStateRef := AValue;
  if FState <> nil then
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FState.Start;
      end);
end;

procedure TAtlasIdeWelcome.SetDiscover(AValue: TAtlasIdeDiscover);
begin
  FDiscover := AValue;
  FDiscoverRef := AValue;
  if FDiscover <> nil then
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FDiscover.Start;
      end);
end;

procedure TAtlasIdeWelcome.SetSetup(AValue: TAtlasIdeSetup);
begin
  FSetup := AValue;
  FSetupRef := AValue;
  if FSetup <> nil then
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FSetup.Start;
      end);
end;

procedure TAtlasIdeWelcome.SetHelp(AValue: TAtlasIdeHelp);
begin
  FHelp := AValue;
  FHelpRef := AValue;
  if FHelp <> nil then
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FHelp.Start;
      end);
end;

procedure TAtlasIdeWelcome.SetUnsaved(AValue: TAtlasIdeUnsaved);
begin
  FUnsaved := AValue;
  FUnsavedRef := AValue;
  if FUnsaved <> nil then
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FUnsaved.Start;
      end);
end;

procedure TAtlasIdeWelcome.SetQuickActions(AValue: TAtlasIdeQuickActions);
begin
  FQuickActions := AValue;
  FQuickActionsRef := AValue;
  // Die Bereiche reichen die Quelle an jeden neuen Frame weiter.
  if FProjects <> nil then
    FProjects.QuickActions := AValue;
  if FContinue <> nil then
    FContinue.QuickActions := AValue;
  if FQuickActions <> nil then
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FQuickActions.Start;
      end);
end;

procedure TAtlasIdeWelcome.SetContinue(AValue: TAtlasIdeContinue);
begin
  FContinue := AValue;
  FContinueRef := AValue;
  if (FContinue <> nil) and (FQuickActions <> nil) then
    FContinue.QuickActions := FQuickActions;
  if FContinue <> nil then
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FContinue.Start;
      end);
end;

procedure TAtlasIdeWelcome.SetProjects(AValue: TAtlasIdeProjects);
begin
  FProjects := AValue;
  FProjectsRef := AValue;
  if FProjects <> nil then
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FProjects.Start;
      end);
end;

procedure TAtlasIdeWelcome.SetTrends(AValue: TAtlasIdeTrends);
begin
  FTrends := AValue;
  FTrendsRef := AValue;
  if FTrends <> nil then
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FTrends.Start;
      end);
end;

procedure TAtlasIdeWelcome.SetTestResults(AValue: TAtlasIdeTestResults);
begin
  FTestResults := AValue;
  FTestResultsRef := AValue;
  if FTestResults <> nil then
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FTestResults.Start;
      end);
end;

procedure TAtlasIdeWelcome.SetIssues(AValue: TAtlasIdeIssues);
begin
  FIssues := AValue;
  FIssuesRef := AValue;
  if FIssues <> nil then
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FIssues.Start;
      end);
end;

procedure TAtlasIdeWelcome.SetWhatsNew(AValue: TAtlasIdeWhatsNew);
begin
  FWhatsNew := AValue;
  FWhatsNewRef := AValue;
  if FWhatsNew <> nil then
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FWhatsNew.Start;
      end);
end;

/// <summary>Kontextmenü „Neu in Atlas“ an Frame „Atlas“ bzw. Kopf hängen oder (off) entfernen.</summary>
procedure TAtlasIdeWelcome.AttachMenu(AFrame: TAtlasWelcomeFrame);
var
  Menu: TAtlasWhatsNewMenu;
begin
  if AFrame = nil then
    Exit;
  Menu := nil;
  if AFrame.PopupMenu is TAtlasWhatsNewMenu then
    Menu := TAtlasWhatsNewMenu(AFrame.PopupMenu);
  if (FWhatsNew = nil) or not FWhatsNew.Active then
  begin
    if Menu <> nil then
    begin
      AFrame.PopupMenu := nil;
      Menu.Free;
    end;
    Exit;
  end;
  if Menu = nil then
  begin
    Menu := TAtlasWhatsNewMenu.Create(AFrame);
    AFrame.PopupMenu := Menu;
  end;
  Menu.Source := FWhatsNew;
end;

class function TAtlasIdeWelcome.AtlasFolder: string;
begin
  Result := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas');
end;

class function TAtlasIdeWelcome.PendingFile: string;
begin
  Result := TPath.Combine(AtlasFolder, 'welcomepage-layout-pending');
end;

function TAtlasIdeWelcome.WelcomeKey: string;
begin
  Result := TAtlasWelcomeBackup.WelcomeKey(TAtlasIdeRegistryAccess.IdeBaseKey);
end;

class function TAtlasIdeWelcome.HeaderInfo(const AServer: TAtlasServerInfo; AIndexing: Boolean;
  APercent, AUnits: Integer; AHour: Integer; const AFirstName: string; AGreeting: Boolean): TAtlasWelcomeHeaderInfo;
begin
  Result.Greeting := AGreeting;
  Result.Hour := AHour;
  Result.FirstName := AFirstName;
  // Version des Plugins; die des Servers steht im Statusfeld.
  Result.Version := TAtlasPluginVersion.Version;
  Result.Phase := AServer.Phase;
  Result.Units := AUnits;
  Result.Indexing := AIndexing;
  Result.Percent := APercent;
end;

procedure TAtlasIdeWelcome.FillHeader(AHeader: TAtlasWelcomeHeaderFrame);
var
  Server: TAtlasServerInfo;
  Percent, Units: Integer;
  Indexing: Boolean;
  Hour, Minute, Second, MSec: Word;
begin
  if AHeader = nil then
    Exit;
  Server := Default(TAtlasServerInfo);
  if Assigned(FServerInfo) then
    Server := FServerInfo();
  Percent := -1;
  Indexing := False;
  if Assigned(FIndexing) then
    Indexing := FIndexing(Percent);
  Units := -1;
  if Assigned(FUnits) then
    Units := FUnits();
  DecodeTime(Now, Hour, Minute, Second, MSec);
  AHeader.ShowInfo(HeaderInfo(Server, Indexing, Percent, Units, Hour,
    TAtlasWelcomeGreeting.FirstName(DisplayName, GetEnvironmentVariable('USERNAME')), Settings.WelcomePageGreeting));
  AHeader.ShowSearch(Settings.WelcomePageSearch and (FSearch <> nil));
  if (FSearch <> nil) and (AHeader.Search <> nil) then
    FSearch.Attach(AHeader.Search);
  AttachMenu(AHeader);
end;

procedure TAtlasIdeWelcome.FillBoard(ABoard: TAtlasWelcomeBoardFrame; AFold: Boolean);
var
  Layout: TAtlasWelcomeLayout;
  Board: TAtlasWelcomeBoardFrame;
begin
  if ABoard = nil then
    Exit;
  Board := ABoard;
  // Eigenes Layout (#767) bzw. das feste Atlas-Layout (#753); neue Bereiche nach Höhe in die Spalte mit dem
  // meisten Platz.
  Layout := FLayouts.BoardLayout(
    function(const AId: string): Integer
    var
      View: TAtlasWelcomeSectionFrame;
    begin
      View := Board.View(AId);
      if View <> nil then
        Result := View.Height
      else
        Result := TAtlasWelcomeSectionFrame.DefaultBodyHeight;
    end);
  // Nach einem Update steht „Neu in Atlas“ oben in der ersten Spalte (#756); beim Anpassen der echte Platz.
  if (FWhatsNew <> nil) and FWhatsNew.OnTop and not FLayouts.Editing then
    Layout := Layout.MovedToTop(TAtlasWelcomeIds.News);
  ABoard.Header.Visible := Settings.WelcomePageHeader;
  FillHeader(ABoard.Header);
  AttachMenu(ABoard);
  ABoard.AutoFold := AFold;
  ABoard.Source := FLayouts;
  ABoard.Rebuild(TAtlasWelcomeSections.Default.Visible, Layout, Layout.Columns);
end;

procedure TAtlasIdeWelcome.Announce(const AIds: TArray<string>);
var
  Items: TArray<TAtlasWhatsNewItem>;
  Item: TAtlasWhatsNewItem;
  Section: TAtlasWelcomeSection;
  Id: string;
begin
  if FWhatsNew = nil then
    Exit;
  Items := nil;
  for Id in AIds do
  begin
    if not TAtlasWelcomeSections.Default.Find(Id, Section) then
      Continue;
    Item := Default(TAtlasWhatsNewItem);
    Item.Title := TAtlasStrings.Fmt(TAtlasTextId.WelcomeArrangeNewSection, [Section.Title]);
    Item.Text := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeNewSectionText);
    Item.Setting := TAtlasWelcomeCustomizing.SettingOf(Id);
    Item.Command := TAtlasIdeWelcomeLayouts.CommandId;
    Items := Items + [Item];
  end;
  FWhatsNew.Announce(Items);
end;

procedure TAtlasIdeWelcome.Customize;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if not FLayouts.CanCustomize then
        Exit;
      if not FLayouts.Editing then
        ShowStart;
      FLayouts.SetEditing(not FLayouts.Editing);
    end);
end;

procedure TAtlasIdeWelcome.Sync;
var
  Current: TAtlasPluginSettings;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      Current := Settings;
      // Titel und Reihenfolge der Karte „Neu in Atlas“ nach den Einstellungen (welcomePage.whatsNew).
      if FWhatsNew <> nil then
        FWhatsNew.Refresh;
      // Karte „Atlas entdecken“: eingeschaltete Funktionen und welcomePage.discover (#757).
      if FDiscover <> nil then
        FDiscover.Refresh;
      // Bereich „Hilfe und Rückmeldung“: welcomePage.help und keys.overview (#766).
      if FHelp <> nil then
        FHelp.Refresh;
      // Bereich „Projekt für Atlas einrichten“: welcomePage.projectSetup und .newFromTemplate (#759).
      if FSetup <> nil then
        FSetup.Refresh;
      // Bereich „Projektverlauf“: welcomePage.trends, .series und .points (#758).
      if FTrends <> nil then
        FTrends.Refresh;
      // Bereich „Testergebnisse“: welcomePage.tests, .maxFailures und .ci (#763).
      if FTestResults <> nil then
        FTestResults.Refresh;
      // Bereich „Meine Issues“: welcomePage.issues sowie issues.tracker, .query und die Muster (#765, #1280).
      if FIssues <> nil then
        FIssues.Refresh;
      // Schnellaktionen: welcomePage.quickActions, .items, .console und Tasten (#764).
      if FQuickActions <> nil then
        FQuickActions.Refresh;
      // „Atlas-Start“: beim ersten Sync nach Wunsch öffnen, danach nur nachführen; aus = schließen.
      if not Current.WelcomePage then
        TAtlasIdeWelcomeWindow.Hide
      else
      begin
        if not FStarted and Current.WelcomePageOpenOnStart then
          TAtlasIdeWelcomeWindow.Show;
        FillBoard(TAtlasIdeWelcomeWindow.ExistingBoard, True);
      end;
      FStarted := True;
      UpdateHeaders;
    end);
end;

procedure TAtlasIdeWelcome.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

procedure TAtlasIdeWelcome.WatchProjects;
var
  Services: IOTAServices;
  Watch: TAtlasWelcomeProjectWatch;
begin
  if (FProjectWatch <> nil) or not Supports(BorlandIDEServices, IOTAServices, Services) then
    Exit;
  Watch := TAtlasWelcomeProjectWatch.Create;
  Watch.FOwner := Self;
  FProjectWatch := Watch;
  FProjectWatchIndex := Services.AddNotifier(Watch);
end;

procedure TAtlasIdeWelcome.UnwatchProjects;
var
  Services: IOTAServices;
begin
  if FProjectWatch = nil then
    Exit;
  TAtlasWelcomeProjectWatch(FProjectWatch).FOwner := nil;
  // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter (#493).
  if (FProjectWatchIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, Services) then
    Services.RemoveNotifier(FProjectWatchIndex);
  FProjectWatch := nil;
  FProjectWatchIndex := -1;
end;

procedure TAtlasIdeWelcome.ProjectClosing;
begin
  // ofnFileClosing kommt, bevor das Projekt weg ist; eine Gruppe schließt mehrere Projekte nacheinander.
  // Darum einmal danach über die Nachrichtenschleife prüfen.
  if FNoProjectQueued then
    Exit;
  FNoProjectQueued := True;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if Instance <> nil then
        Instance.CheckNoProject;
    end);
end;

procedure TAtlasIdeWelcome.CheckNoProject;
var
  Current: TAtlasPluginSettings;
begin
  FNoProjectQueued := False;
  Current := Settings;
  if TAtlasWelcomeAutoOpen.AfterProjectClosed(Current.WelcomePage, Current.WelcomePageOpenWhenNoProject,
    OpenProjectCount, IdeRunning, TAtlasIdeWelcomeWindow.Visible) then
    ShowStart;
end;

class function TAtlasIdeWelcome.OpenProjectCount: Integer;
var
  Services: IOTAModuleServices;
  Group: IOTAProjectGroup;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit(-1);
  Group := Services.MainProjectGroup;
  if Group = nil then
    Exit(0);
  Result := Group.ProjectCount;
end;

class function TAtlasIdeWelcome.IdeRunning: Boolean;
begin
  // Beim Beenden schließt die IDE alle Projekte; dann kein Fenster mehr anlegen.
  Result := not Application.Terminated and (Application.MainForm <> nil) and Application.MainForm.Visible and
    not (csDestroying in Application.MainForm.ComponentState);
end;

procedure TAtlasIdeWelcome.SectionChanged(const AId: string);
var
  Id: string;
  Collect: TThreadProcedure;
begin
  Id := AId;
  // Beobachter melden auch aus Hintergrund-Threads; gesammelt und gezeichnet wird im Hauptthread.
  Collect :=
    procedure
    var
      Known: string;
      Flush: TThreadProcedure;
    begin
      if Instance = nil then
        Exit;
      for Known in Instance.FDirty do
        if SameText(Known, Id) then
          Exit;
      Instance.FDirty := Instance.FDirty + [Id];
      if Instance.FQueued then
        Exit;
      Instance.FQueued := True;
      Flush :=
        procedure
        begin
          if Instance <> nil then
            Instance.Flush;
        end;
      TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage, Flush);
    end;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage, Collect);
end;

procedure TAtlasIdeWelcome.Flush;
var
  Ids: TArray<string>;
  Id: string;
begin
  FQueued := False;
  Ids := FDirty;
  FDirty := nil;
  for Id in Ids do
    if Id = '' then
    begin
      // Bereiche kamen hinzu, fielen weg oder wurden ein- oder ausgeschaltet.
      Sync;
      Exit;
    end;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Item: string;
    begin
      for Item in Ids do
        if SameText(Item, TAtlasWelcomeIds.Header) then
          UpdateHeaders
        else
          UpdateSection(Item);
    end);
end;

procedure TAtlasIdeWelcome.UpdateSection(const AId: string);
var
  Board: TAtlasWelcomeBoardFrame;
begin
  Board := TAtlasIdeWelcomeWindow.ExistingBoard;
  if Board <> nil then
    Board.UpdateSection(AId);
end;

procedure TAtlasIdeWelcome.UpdateHeaders;
var
  Board: TAtlasWelcomeBoardFrame;
begin
  Board := TAtlasIdeWelcomeWindow.ExistingBoard;
  if Board <> nil then
  begin
    Board.Header.Visible := Settings.WelcomePageHeader;
    FillHeader(Board.Header);
  end;
end;

procedure TAtlasIdeWelcome.CheckPending;
begin
  // Die Marke enthält den gewünschten Stand des Schlüssels WelcomePage. Hat die IDE ihr Layout beim Beenden aus
  // dem Speicher zurückgeschrieben, wird der Stand hier wiederholt; gilt er beim Start schon, hat die IDE ihn
  // übernommen und die Marke entfällt. "atlas" (Atlas-Layout früherer Fassungen) gilt nicht mehr (#1114).
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Wanted: string;
    begin
      if not FileExists(PendingFile) then
        Exit;
      Wanted := Trim(ReadText(PendingFile));
      if Wanted = 'atlas' then
        System.SysUtils.DeleteFile(PendingFile)
      else if TAtlasWelcomeBackup.Matches(FAccess, Wanted) then
        System.SysUtils.DeleteFile(PendingFile)
      else if not TAtlasWelcomeBackup.Restore(FAccess, Wanted) then
        System.SysUtils.DeleteFile(PendingFile);
    end);
end;

procedure TAtlasIdeWelcome.RetireIdeLayout;
begin
  // Atlas-Bereiche früherer Fassungen von der Willkommensseite der IDE nehmen (#1114); meldet sich einmal.
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Backup, Saved, Snapshot: string;
      Outcome: TAtlasRetireResult;
    begin
      Backup := TAtlasWelcomeBackup.BackupFile(AtlasFolder);
      Saved := '';
      if FileExists(Backup) then
        Saved := ReadText(Backup);
      Outcome := TAtlasWelcomeRetire.Run(FAccess, WelcomeKey, Saved, TAtlasWelcomeIds.PluginPrefix, Snapshot);
      // Die Sicherung hat ausgedient, auch wenn sie nicht mehr lesbar war.
      if FileExists(Backup) then
        System.SysUtils.DeleteFile(Backup);
      if Outcome = TAtlasRetireResult.Nothing then
        Exit;
      TAtlasDataFile.Write(PendingFile, Snapshot);
      Report(TAtlasStrings.Text(TAtlasTextId.WelcomeRetired));
    end);
end;

procedure TAtlasIdeWelcome.ShowStart;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      FillBoard(TAtlasIdeWelcomeWindow.Show, True);
    end);
end;

procedure TAtlasIdeWelcome.ShowWhatsNew(AView: TAtlasWhatsNewView);
begin
  if FWhatsNew = nil then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      FWhatsNew.Show(AView);
      ShowStart;
    end);
end;

procedure TAtlasIdeWelcome.ThemeChanged;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      TAtlasIdeWelcomeWindow.ApplyTheme;
      // Farben der Ergebnisliste des Suchfelds (#760).
      UpdateHeaders;
    end);
end;

end.
