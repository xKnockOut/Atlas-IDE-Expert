unit Atlas.IDE.Welcome.Commands;

// Steuerung der Atlas-Willkommensseite (#753):
// - Zwei Orte, unabhängig abschaltbar (#761; #1114 hatte die Willkommensseite
//   der IDE entfernt, die Zugriffsverletzung beim Beenden ist seit #1233
//   behoben):
//   - Willkommensseite der IDE (welcomePage.ideWelcomePage, Vorgabe an): Sync
//     meldet je eingeschaltetem Bereich ein Plugin an (plus Kopf), im
//     Atlas-Layout (welcomePage.layout = atlas) ein einziges Plugin „Atlas“ mit
//     Kopf und allen Bereichen in zwei Spalten.
//   - Andockbares Fenster „Atlas-Start“: öffnet über Ansicht › Atlas-Start,
//     das Atlas-Menü, die Befehlspalette und den Desktop der IDE; mit
//     welcomePage.openOnStart auch beim Start, mit
//     welcomePage.openWhenNoProject (Vorgabe an), sobald das letzte Projekt
//     geschlossen ist (nicht beim Beenden der IDE).
//   welcomePage.enabled aus: keine Plugins, Fenster zu.
// - ApplyLayout sichert den Registry-Schlüssel WelcomePage der IDE nach
//   %LOCALAPPDATA%\Atlas\welcomepage-layout-backup.json (nur, wenn noch keine
//   Sicherung existiert), setzt „Atlas“ oben über alle Spalten, schiebt die
//   übrigen Bereiche nach unten und setzt welcomePage.layout = atlas.
//   ResetLayout schreibt die Sicherung exakt zurück und setzt layout = off.
// - Aufräumen (TAtlasWelcomeRetire), solange Atlas nicht auf der
//   Willkommensseite der IDE stehen soll (beim Start und beim Abschalten):
//   Gibt es die Sicherung, schreibt Atlas sie zurück und löscht sie; sonst
//   nimmt es seine Kennungen aus dem Registry-Schlüssel WelcomePage der IDE.
// - Hält die IDE ihr Layout im Speicher und schreibt es beim Beenden zurück,
//   wiederholt der nächste Start den gewünschten Stand (Marke …-pending:
//   "atlas" oder der Schlüssel als JSON).
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
// - „Meine Issues“, „Sprint“ und „Testergebnisse“ (#765, #1277, #763) sind
//   seit #1455 Kacheln des Moduls Tracker (Atlas.IDE.Contracts.WelcomeTiles).
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
//   Bereiche; gilt im Atlas-Layout und im Fenster „Atlas-Start“ (dort mit
//   gefalteten Spalten, wenn es schmal ist). Ohne Bereich „Atlas“ auf der
//   Willkommensseite der IDE öffnet der Befehl „Atlas-Start“. Neue Bereiche
//   meldet „Neu in Atlas“.
// Die Willkommensseite startet keinen Server und liest nur lokale Daten;
// einzige Ausnahme ist die Abfrage beim Build-Server (#763,
// welcomePage.tests.ci, Vorgabe aus).

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Status.Lines,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Backup,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Header,
  Atlas.UI.Welcome.Board,
  Atlas.IDE.Status.Lines,
  Atlas.IDE.Welcome.Page,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.WhatsNew,
  Atlas.IDE.Welcome.Projects,
  Atlas.IDE.Welcome.QuickActions,
  Atlas.IDE.Welcome.Trends,
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
    // Plugins auf der Willkommensseite der IDE beim letzten Sync gewollt.
    FShownIde: Boolean;
    // Zuletzt gesehenes welcomePage.layout; '' vor dem ersten Sync.
    FLastLayout: string;
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
    procedure SetUnsaved(AValue: TAtlasIdeUnsaved);
    procedure SetContinue(AValue: TAtlasIdeContinue);
    procedure AttachMenu(AFrame: TAtlasWelcomeFrame);
    procedure SectionChanged(const AId: string);
    procedure Flush;
    function CaptionOf(const APluginId: string): string;
    function CreateClient(const APluginId: string; AOwner: TComponent): TAtlasWelcomeFrame;
    function FactoryOf(const APluginId: string): TAtlasWelcomeClientFactory;
    procedure UpdateSection(const AId: string);
    procedure RefreshClient(AClient: TAtlasWelcomeFrame);
    /// <summary>Tafel füllen; AFold: Fenster „Atlas-Start“ (Spalten falten, wenn es schmal ist).</summary>
    procedure FillBoard(ABoard: TAtlasWelcomeBoardFrame; AFold: Boolean);
    procedure FillHeader(AHeader: TAtlasWelcomeHeaderFrame);
    procedure UpdateHeaders;
    function WelcomeKey: string;
    function PlaceBoard: Boolean;
    function BoardPlaced: Boolean;
    procedure CheckPending;
    procedure RetireIdeLayout;
    procedure SetLayout(const AValue: string);
    function Place(AReport: Boolean): Boolean;
    function Unplace(AReport: Boolean): Boolean;
    /// <summary>Sollen nach den Einstellungen Atlas-Bereiche auf der Willkommensseite der IDE stehen?</summary>
    class function IdePageWanted(const ASettings: TAtlasPluginSettings): Boolean; static;
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
    /// <summary>Befehl „Atlas-Layout anwenden“: Bereich „Atlas“ oben auf die Willkommensseite der IDE.</summary>
    procedure ApplyLayout;
    /// <summary>Befehl „Atlas-Layout zurücksetzen“: gesichertes Layout der IDE zurück.</summary>
    procedure ResetLayout;
    /// <summary>Befehl „Willkommensseite anpassen“ (#767): Bearbeitungsmodus an/aus; ohne Tafel auf der
    /// Willkommensseite im Fenster „Atlas-Start“ (öffnet es beim Einschalten).</summary>
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
  Atlas.Core.Status.Registry,
  Atlas.Core.Welcome.Greeting,
  Atlas.Core.Welcome.Layout,
  Atlas.Core.Welcome.Layouts,
  Atlas.Core.Welcome.HostLayout,
  Atlas.Core.Welcome.Projects,
  Atlas.Core.Welcome.Search,
  Atlas.UI.Welcome.Strings,
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
  begin
    SetString(Result, PWideChar(@Buffer[0]), Size);
  end;
  Result := Trim(Result);
end;

/// <summary>Textdatei lesen, mit oder ohne Byte-Order-Mark (frühere Fassungen schrieben eines); teilt Löschen,
/// damit es das atomare Ersetzen nicht blockiert. EInOutError, wenn sie nicht lesbar ist.</summary>
function ReadText(const AFileName: string): string;
begin
  if not TAtlasDataFile.TryRead(AFileName, Result) then
  begin
    raise EInOutError.Create('Datei der Willkommensseite nicht lesbar');
  end;
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
  begin
    Exit;
  end;
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
      begin
        Instance.Sync;
      end;
    end);
  FLayoutsRef := FLayouts;
  FLayouts.OnAnnounce :=
    procedure(AIds: TArray<string>)
    begin
      if Instance <> nil then
      begin
        Instance.Announce(AIds);
      end;
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
  if not IdePageWanted(Settings) then
  begin
    RetireIdeLayout;
  end;
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
  begin
    FQuickActions.Stop;
  end;
  if FWhatsNew <> nil then
  begin
    FWhatsNew.Stop;
  end;
  if FTrends <> nil then
  begin
    FTrends.Stop;
  end;
  if FProjects <> nil then
  begin
    FProjects.Stop;
  end;
  if FUnsaved <> nil then
  begin
    FUnsaved.Stop;
  end;
  // Schreibt den Arbeitsstand des noch offenen Projekts (Beenden der IDE).
  if FContinue <> nil then
  begin
    FContinue.Stop;
  end;
  if FState <> nil then
  begin
    FState.Stop;
  end;
  if FDiscover <> nil then
  begin
    FDiscover.Stop;
  end;
  if FHelp <> nil then
  begin
    FHelp.Stop;
  end;
  if FSetup <> nil then
  begin
    FSetup.Stop;
  end;
  // Beim Beenden der IDE: Hat die IDE ihr Layout aus dem Speicher zurückgeschrieben, gilt die Marke weiter.
  TAtlasIdeWelcomePage.RemoveAll;
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
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FState.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcome.SetDiscover(AValue: TAtlasIdeDiscover);
begin
  FDiscover := AValue;
  FDiscoverRef := AValue;
  if FDiscover <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FDiscover.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcome.SetSetup(AValue: TAtlasIdeSetup);
begin
  FSetup := AValue;
  FSetupRef := AValue;
  if FSetup <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FSetup.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcome.SetHelp(AValue: TAtlasIdeHelp);
begin
  FHelp := AValue;
  FHelpRef := AValue;
  if FHelp <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FHelp.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcome.SetUnsaved(AValue: TAtlasIdeUnsaved);
begin
  FUnsaved := AValue;
  FUnsavedRef := AValue;
  if FUnsaved <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FUnsaved.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcome.SetQuickActions(AValue: TAtlasIdeQuickActions);
begin
  FQuickActions := AValue;
  FQuickActionsRef := AValue;
  // Die Bereiche reichen die Quelle an jeden neuen Frame weiter.
  if FProjects <> nil then
  begin
    FProjects.QuickActions := AValue;
  end;
  if FContinue <> nil then
  begin
    FContinue.QuickActions := AValue;
  end;
  if FQuickActions <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FQuickActions.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcome.SetContinue(AValue: TAtlasIdeContinue);
begin
  FContinue := AValue;
  FContinueRef := AValue;
  if (FContinue <> nil) and (FQuickActions <> nil) then
  begin
    FContinue.QuickActions := FQuickActions;
  end;
  if FContinue <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FContinue.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcome.SetProjects(AValue: TAtlasIdeProjects);
begin
  FProjects := AValue;
  FProjectsRef := AValue;
  if FProjects <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FProjects.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcome.SetTrends(AValue: TAtlasIdeTrends);
begin
  FTrends := AValue;
  FTrendsRef := AValue;
  if FTrends <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FTrends.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcome.SetWhatsNew(AValue: TAtlasIdeWhatsNew);
begin
  FWhatsNew := AValue;
  FWhatsNewRef := AValue;
  if FWhatsNew <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FWhatsNew.Start;
      end);
  end;
end;

/// <summary>Kontextmenü „Neu in Atlas“ an Frame „Atlas“ bzw. Kopf hängen oder (off) entfernen.</summary>
procedure TAtlasIdeWelcome.AttachMenu(AFrame: TAtlasWelcomeFrame);
var
  Menu: TAtlasWhatsNewMenu;
begin
  if AFrame = nil then
  begin
    Exit;
  end;
  Menu := nil;
  if AFrame.PopupMenu is TAtlasWhatsNewMenu then
  begin
    Menu := TAtlasWhatsNewMenu(AFrame.PopupMenu);
  end;
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
  begin
    Exit;
  end;
  Server := Default(TAtlasServerInfo);
  if Assigned(FServerInfo) then
  begin
    Server := FServerInfo();
  end;
  Percent := -1;
  Indexing := False;
  if Assigned(FIndexing) then
  begin
    Indexing := FIndexing(Percent);
  end;
  Units := -1;
  if Assigned(FUnits) then
  begin
    Units := FUnits();
  end;
  DecodeTime(Now, Hour, Minute, Second, MSec);
  AHeader.ShowInfo(HeaderInfo(Server, Indexing, Percent, Units, Hour,
    TAtlasWelcomeGreeting.FirstName(DisplayName, GetEnvironmentVariable('USERNAME')), Settings.WelcomePageGreeting));
  AHeader.ShowSearch(Settings.WelcomePageSearch and (FSearch <> nil));
  if (FSearch <> nil) and (AHeader.Search <> nil) then
  begin
    FSearch.Attach(AHeader.Search);
  end;
  AttachMenu(AHeader);
end;

procedure TAtlasIdeWelcome.FillBoard(ABoard: TAtlasWelcomeBoardFrame; AFold: Boolean);
var
  Layout: TAtlasWelcomeLayout;
  Board: TAtlasWelcomeBoardFrame;
begin
  if ABoard = nil then
  begin
    Exit;
  end;
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
      begin
        Result := View.Height;
      end
      else
      begin
        Result := TAtlasWelcomeSectionFrame.DefaultBodyHeight;
      end;
    end);
  // Nach einem Update steht „Neu in Atlas“ oben in der ersten Spalte (#756); beim Anpassen der echte Platz.
  if (FWhatsNew <> nil) and FWhatsNew.OnTop and not FLayouts.Editing then
  begin
    Layout := Layout.MovedToTop(TAtlasWelcomeIds.News);
  end;
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
  begin
    Exit;
  end;
  Items := nil;
  for Id in AIds do
  begin
    if not TAtlasWelcomeSections.Default.Find(Id, Section) then
    begin
      Continue;
    end;
    Item := Default(TAtlasWhatsNewItem);
    Item.Title := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeArrangeNewSection, [Section.Title]);
    Item.Text := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeNewSectionText);
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
    var
      Client: TAtlasWelcomeFrame;
    begin
      if not FLayouts.CanCustomize then
      begin
        Exit;
      end;
      // Ohne Tafel auf der Willkommensseite der IDE (welcomePage.layout = off oder dort aus) im Fenster.
      Client := TAtlasIdeWelcomePage.Client(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Board));
      if not FLayouts.Editing and not (Client is TAtlasWelcomeBoardFrame) then
      begin
        ShowStart;
      end;
      FLayouts.SetEditing(not FLayouts.Editing);
    end);
end;

class function TAtlasIdeWelcome.IdePageWanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.WelcomePage and ASettings.WelcomePageIdePage;
end;

procedure TAtlasIdeWelcome.Sync;
var
  Current: TAtlasPluginSettings;
  IdePage: Boolean;
  Wanted: TArray<string>;
  Registered: TArray<string>;
  Keep: Boolean;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Section: TAtlasWelcomeSection;
      Id, Plugin: string;
      Step: TAtlasIdePageStep;
    begin
      Current := Settings;
      // Titel und Reihenfolge der Karte „Neu in Atlas“ nach den Einstellungen (welcomePage.whatsNew).
      if FWhatsNew <> nil then
      begin
        FWhatsNew.Refresh;
      end;
      // Karte „Atlas entdecken“: eingeschaltete Funktionen und welcomePage.discover (#757).
      if FDiscover <> nil then
      begin
        FDiscover.Refresh;
      end;
      // Bereich „Hilfe und Rückmeldung“: welcomePage.help und keys.overview (#766).
      if FHelp <> nil then
      begin
        FHelp.Refresh;
      end;
      // Bereich „Projekt für Atlas einrichten“: welcomePage.projectSetup und .newFromTemplate (#759).
      if FSetup <> nil then
      begin
        FSetup.Refresh;
      end;
      // Bereich „Projektverlauf“: welcomePage.trends, .series und .points (#758).
      if FTrends <> nil then
      begin
        FTrends.Refresh;
      end;
      // Schnellaktionen: welcomePage.quickActions, .items, .console und Tasten (#764).
      if FQuickActions <> nil then
      begin
        FQuickActions.Refresh;
      end;
      IdePage := IdePageWanted(Current) and TAtlasIdeWelcomePage.Available;
      // Gewünschte Plugins auf der Willkommensseite der IDE.
      Wanted := nil;
      if IdePage and (Current.WelcomePageLayout = 'atlas') then
      begin
        Wanted := [TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Board)];
      end
      else if IdePage then
      begin
        if Current.WelcomePageHeader then
        begin
          Wanted := [TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Header)];
        end;
        for Section in TAtlasWelcomeSections.Default.Visible do
        begin
          if TAtlasWelcomeViews.Exists(Section.Id) then
          begin
            Wanted := Wanted + [TAtlasWelcomeIds.PluginId(Section.Id)];
          end;
        end;
      end;
      Registered := TAtlasIdeWelcomePage.Registered;
      for Plugin in Registered do
      begin
        Keep := False;
        for Id in Wanted do
        begin
          Keep := Keep or SameText(Id, Plugin);
        end;
        if not Keep then
        begin
          TAtlasIdeWelcomePage.Unregister(Plugin);
        end;
      end;
      for Id in Wanted do
      begin
        Keep := False;
        for Plugin in Registered do
        begin
          Keep := Keep or SameText(Id, Plugin);
        end;
        if not Keep then
        begin
          // Fabrik je Kennung über FactoryOf: Eine Closure hier sähe nur die letzte Schleifenvariable.
          TAtlasIdeWelcomePage.Register(Id, CaptionOf(Id), FactoryOf(Id));
        end
        else
        begin
          RefreshClient(TAtlasIdeWelcomePage.Client(Id));
        end;
      end;
      // „Atlas-Start“, unabhängig davon: beim ersten Sync nach Wunsch öffnen, danach nur nachführen; aus =
      // schließen.
      if not Current.WelcomePage then
      begin
        TAtlasIdeWelcomeWindow.Hide;
      end
      else
      begin
        if not FStarted and Current.WelcomePageOpenOnStart then
        begin
          TAtlasIdeWelcomeWindow.Show;
        end;
        FillBoard(TAtlasIdeWelcomeWindow.ExistingBoard, True);
      end;
      // Umschalten in den Optionen: wie die Menübefehle, aber ohne Meldung. Beim Start gilt, was die IDE aus der
      // Registry liest (CheckPending und Aufräumen im Konstruktor).
      for Step in TAtlasIdePageSteps.After(FStarted, FShownIde, IdePage, FLastLayout, Current.WelcomePageLayout) do
        case Step of
          TAtlasIdePageStep.Retire:
            RetireIdeLayout;
          TAtlasIdePageStep.ClearPending:
            System.SysUtils.DeleteFile(PendingFile);
          TAtlasIdePageStep.PlaceBoard:
            Place(False);
          TAtlasIdePageStep.Unplace:
            Unplace(False);
          TAtlasIdePageStep.None: ;
        end;
      FShownIde := IdePage;
      FLastLayout := Current.WelcomePageLayout;
      FStarted := True;
      UpdateHeaders;
    end);
end;

procedure TAtlasIdeWelcome.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

procedure TAtlasIdeWelcome.WatchProjects;
var
  Services: IOTAServices;
  Watch: TAtlasWelcomeProjectWatch;
begin
  if (FProjectWatch <> nil) or not Supports(BorlandIDEServices, IOTAServices, Services) then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  TAtlasWelcomeProjectWatch(FProjectWatch).FOwner := nil;
  // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter (#493).
  if (FProjectWatchIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, Services) then
  begin
    Services.RemoveNotifier(FProjectWatchIndex);
  end;
  FProjectWatch := nil;
  FProjectWatchIndex := -1;
end;

procedure TAtlasIdeWelcome.ProjectClosing;
begin
  // ofnFileClosing kommt, bevor das Projekt weg ist; eine Gruppe schließt mehrere Projekte nacheinander.
  // Darum einmal danach über die Nachrichtenschleife prüfen.
  if FNoProjectQueued then
  begin
    Exit;
  end;
  FNoProjectQueued := True;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if Instance <> nil then
      begin
        Instance.CheckNoProject;
      end;
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
  begin
    ShowStart;
  end;
end;

class function TAtlasIdeWelcome.OpenProjectCount: Integer;
var
  Services: IOTAModuleServices;
  Group: IOTAProjectGroup;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
  begin
    Exit(-1);
  end;
  Group := Services.MainProjectGroup;
  if Group = nil then
  begin
    Exit(0);
  end;
  Result := Group.ProjectCount;
end;

class function TAtlasIdeWelcome.IdeRunning: Boolean;
begin
  // Beim Beenden schließt die IDE alle Projekte; dann kein Fenster mehr anlegen.
  Result := not Application.Terminated and (Application.MainForm <> nil) and Application.MainForm.Visible and
    not (csDestroying in Application.MainForm.ComponentState);
end;

function TAtlasIdeWelcome.CaptionOf(const APluginId: string): string;
var
  Id: string;
  Section: TAtlasWelcomeSection;
begin
  Id := TAtlasWelcomeIds.SectionOf(APluginId);
  if SameText(Id, TAtlasWelcomeIds.Header) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeHeaderTitle);
  end
  else if SameText(Id, TAtlasWelcomeIds.Board) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeBoardTitle);
  end
  else if TAtlasWelcomeSections.Default.Find(Id, Section) then
  begin
    Result := Section.Title;
  end
  else
  begin
    Result := APluginId;
  end;
end;

function TAtlasIdeWelcome.CreateClient(const APluginId: string; AOwner: TComponent): TAtlasWelcomeFrame;
var
  Id: string;
  Header: TAtlasWelcomeHeaderFrame;
  Board: TAtlasWelcomeBoardFrame;
  View: TAtlasWelcomeSectionFrame;
begin
  Id := TAtlasWelcomeIds.SectionOf(APluginId);
  if SameText(Id, TAtlasWelcomeIds.Header) then
  begin
    Header := TAtlasWelcomeHeaderFrame.Create(AOwner);
    FillHeader(Header);
    Result := Header;
  end
  else if SameText(Id, TAtlasWelcomeIds.Board) then
  begin
    Board := TAtlasWelcomeBoardFrame.Create(AOwner);
    FillBoard(Board, False);
    Result := Board;
  end
  else
  begin
    // Die IDE zeigt den Titel im Rahmen; der Bereich selbst ohne Titelzeile.
    View := TAtlasWelcomeViews.CreateView(Id, AOwner);
    if View <> nil then
    begin
      View.ShowTitle := False;
    end;
    Result := View;
  end;
end;

function TAtlasIdeWelcome.FactoryOf(const APluginId: string): TAtlasWelcomeClientFactory;
begin
  Result :=
    function(AOwner: TComponent): TAtlasWelcomeFrame
    begin
      Result := nil;
      if Instance <> nil then
      begin
        Result := Instance.CreateClient(APluginId, AOwner);
      end;
    end;
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
      begin
        Exit;
      end;
      for Known in Instance.FDirty do
      begin
        if SameText(Known, Id) then
        begin
          Exit;
        end;
      end;
      Instance.FDirty := Instance.FDirty + [Id];
      if Instance.FQueued then
      begin
        Exit;
      end;
      Instance.FQueued := True;
      Flush :=
        procedure
        begin
          if Instance <> nil then
          begin
            Instance.Flush;
          end;
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
  begin
    if Id = '' then
    begin
      // Bereiche kamen hinzu, fielen weg oder wurden ein- oder ausgeschaltet.
      Sync;
      Exit;
    end;
  end;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Item: string;
    begin
      for Item in Ids do
      begin
        if SameText(Item, TAtlasWelcomeIds.Header) then
        begin
          UpdateHeaders;
        end
        else
        begin
          UpdateSection(Item);
        end;
      end;
    end);
end;

/// <summary>Gezeigten Inhalt nach Einstellungen und Bereichen neu füllen.</summary>
procedure TAtlasIdeWelcome.RefreshClient(AClient: TAtlasWelcomeFrame);
begin
  if AClient is TAtlasWelcomeBoardFrame then
  begin
    FillBoard(TAtlasWelcomeBoardFrame(AClient), False);
  end
  else if AClient is TAtlasWelcomeHeaderFrame then
  begin
    FillHeader(TAtlasWelcomeHeaderFrame(AClient));
  end
  else if AClient <> nil then
  begin
    AClient.UpdateContent;
  end;
end;

procedure TAtlasIdeWelcome.UpdateSection(const AId: string);
var
  Client: TAtlasWelcomeFrame;
  Board: TAtlasWelcomeBoardFrame;
begin
  Client := TAtlasIdeWelcomePage.Client(TAtlasWelcomeIds.PluginId(AId));
  if Client <> nil then
  begin
    Client.UpdateContent;
  end;
  Client := TAtlasIdeWelcomePage.Client(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Board));
  if Client is TAtlasWelcomeBoardFrame then
  begin
    TAtlasWelcomeBoardFrame(Client).UpdateSection(AId);
  end;
  Board := TAtlasIdeWelcomeWindow.ExistingBoard;
  if Board <> nil then
  begin
    Board.UpdateSection(AId);
  end;
end;

procedure TAtlasIdeWelcome.UpdateHeaders;
var
  Client: TAtlasWelcomeFrame;
  Board: TAtlasWelcomeBoardFrame;
begin
  Client := TAtlasIdeWelcomePage.Client(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Header));
  if Client is TAtlasWelcomeHeaderFrame then
  begin
    FillHeader(TAtlasWelcomeHeaderFrame(Client));
  end;
  Client := TAtlasIdeWelcomePage.Client(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Board));
  if Client is TAtlasWelcomeBoardFrame then
  begin
    TAtlasWelcomeBoardFrame(Client).Header.Visible := Settings.WelcomePageHeader;
    FillHeader(TAtlasWelcomeBoardFrame(Client).Header);
  end;
  Board := TAtlasIdeWelcomeWindow.ExistingBoard;
  if Board <> nil then
  begin
    Board.Header.Visible := Settings.WelcomePageHeader;
    FillHeader(Board.Header);
  end;
end;

function TAtlasIdeWelcome.BoardPlaced: Boolean;
var
  Key: TAtlasRegKey;
  Layout: TAtlasHostLayout;
begin
  Key := FAccess.Read(WelcomeKey);
  try
    Result := (Key <> nil) and TAtlasHostLayout.Read(Key, Layout) and
      Layout.HasAtlasOnTop(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Board), TAtlasWelcomeIds.PluginPrefix);
  finally
    Key.Free;
  end;
end;

function TAtlasIdeWelcome.PlaceBoard: Boolean;
var
  Key: TAtlasRegKey;
  Layout, Placed: TAtlasHostLayout;
begin
  Key := FAccess.Read(WelcomeKey);
  try
    if Key = nil then
    begin
      Key := TAtlasRegKey.Create('WelcomePage');
    end;
    // Ohne Raster in der Registry zeigt die IDE ihre Vorgabe; von der gehen wir aus.
    if not TAtlasHostLayout.Read(Key, Layout) then
    begin
      Layout := TAtlasHostLayout.IdeDefault;
    end;
    Result := not Layout.HasAtlasOnTop(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Board),
      TAtlasWelcomeIds.PluginPrefix);
    if not Result then
    begin
      Exit;
    end;
    Placed := Layout.WithAtlasOnTop(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Board), TAtlasWelcomeIds.PluginPrefix);
    Placed.WriteTo(Key);
    FAccess.Replace(WelcomeKey, Key);
  finally
    Key.Free;
  end;
end;

procedure TAtlasIdeWelcome.CheckPending;
begin
  // Die Marke enthält den gewünschten Stand: "atlas" oder den Schlüssel WelcomePage, der gelten soll. Hat die
  // IDE ihr Layout beim Beenden aus dem Speicher zurückgeschrieben, wird der Stand hier wiederholt; gilt er beim
  // Start schon, hat die IDE ihn übernommen und die Marke entfällt.
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Wanted: string;
      Current: TAtlasPluginSettings;
    begin
      if not FileExists(PendingFile) then
      begin
        Exit;
      end;
      Wanted := Trim(ReadText(PendingFile));
      Current := Settings;
      if Wanted = 'atlas' then
      begin
        if not IdePageWanted(Current) or not SameText(Current.WelcomePageLayout, 'atlas') then
        begin
          System.SysUtils.DeleteFile(PendingFile);
        end
        else if BoardPlaced then
        begin
          System.SysUtils.DeleteFile(PendingFile);
        end
        else
        begin
          PlaceBoard;
        end;
      end
      else if TAtlasWelcomeBackup.Matches(FAccess, Wanted) then
      begin
        System.SysUtils.DeleteFile(PendingFile);
      end
      else if not TAtlasWelcomeBackup.Restore(FAccess, Wanted) then
      begin
        System.SysUtils.DeleteFile(PendingFile);
      end;
    end);
end;

procedure TAtlasIdeWelcome.RetireIdeLayout;
begin
  // Atlas-Bereiche von der Willkommensseite der IDE nehmen (#1114, #761); meldet sich nur, wenn es etwas zu tun
  // gab. Danach ist die Sicherung verbraucht: „Atlas-Layout anwenden“ sichert beim nächsten Mal neu.
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Backup, Saved, Snapshot: string;
      Outcome: TAtlasRetireResult;
    begin
      Backup := TAtlasWelcomeBackup.BackupFile(AtlasFolder);
      Saved := '';
      if FileExists(Backup) then
      begin
        Saved := ReadText(Backup);
      end;
      Outcome := TAtlasWelcomeRetire.Run(FAccess, WelcomeKey, Saved, TAtlasWelcomeIds.PluginPrefix, Snapshot);
      // Die Sicherung hat ausgedient, auch wenn sie nicht mehr lesbar war.
      if FileExists(Backup) then
      begin
        System.SysUtils.DeleteFile(Backup);
      end;
      if Outcome = TAtlasRetireResult.Nothing then
      begin
        Exit;
      end;
      TAtlasDataFile.Write(PendingFile, Snapshot);
      Report(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeRetired));
    end);
end;

procedure TAtlasIdeWelcome.SetLayout(const AValue: string);
var
  Next: TAtlasPluginSettings;
begin
  Next := TAtlasIdeSettings.Stored;
  if SameText(Next.WelcomePageLayout, AValue) then
  begin
    Sync;
    Exit;
  end;
  Next.WelcomePageLayout := AValue;
  // Update meldet OnChanged; die Komposition ruft daraufhin Sync.
  TAtlasIdeSettings.Update(Next);
end;

function TAtlasIdeWelcome.Place(AReport: Boolean): Boolean;
var
  Backup: string;
begin
  Result := False;
  if not TAtlasIdeWelcomePage.Available then
  begin
    Exit;
  end;
  Backup := TAtlasWelcomeBackup.BackupFile(AtlasFolder);
  // Nur die erste Sicherung zählt: Sie hält das Layout vor Atlas.
  if not FileExists(Backup) then
    try
      // Atomar (Bericht N3): Eine halb geschriebene Sicherung verlöre das Layout vor Atlas für immer.
      TAtlasDataFile.Write(Backup, TAtlasWelcomeBackup.Snapshot(FAccess, WelcomeKey));
    except
      on E: Exception do
      begin
        Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeBackupFailed, [E.Message]));
        Exit;
      end;
    end;
  PlaceBoard;
  TAtlasDataFile.Write(PendingFile, 'atlas');
  Result := True;
  if AReport then
  begin
    Report(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeApplied));
  end;
end;

function TAtlasIdeWelcome.Unplace(AReport: Boolean): Boolean;
var
  Backup, Snapshot: string;
begin
  Result := False;
  Snapshot := '';
  Backup := TAtlasWelcomeBackup.BackupFile(AtlasFolder);
  if FileExists(Backup) then
  begin
    Snapshot := ReadText(Backup);
    Result := TAtlasWelcomeBackup.Restore(FAccess, Snapshot);
  end;
  if not Result then
  begin
    if AReport then
    begin
      Report(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNoBackup));
    end;
    Exit;
  end;
  // Bis die IDE den Stand übernommen hat, gilt die Sicherung als gewünschter Stand (CheckPending).
  TAtlasDataFile.Write(PendingFile, Snapshot);
  System.SysUtils.DeleteFile(Backup);
  if AReport then
  begin
    Report(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeResetDone));
  end;
end;

procedure TAtlasIdeWelcome.ApplyLayout;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      // Nur auf der Willkommensseite der IDE; ist sie für Atlas aus, gibt es dort nichts anzuordnen.
      if not IdePageWanted(Settings) or not Place(True) then
      begin
        Exit;
      end;
      // Sync soll nicht ein zweites Mal platzieren.
      FLastLayout := 'atlas';
      SetLayout('atlas');
    end);
end;

procedure TAtlasIdeWelcome.ResetLayout;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if not Unplace(True) then
      begin
        Exit;
      end;
      FLastLayout := 'off';
      SetLayout('off');
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
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      FWhatsNew.Show(AView);
      // Auf der Willkommensseite der IDE zeigt die Karte sich dort; sonst im Fenster.
      if not FShownIde then
      begin
        ShowStart;
      end;
    end);
end;

procedure TAtlasIdeWelcome.ThemeChanged;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      TAtlasIdeWelcomePage.ApplyTheme;
      TAtlasIdeWelcomeWindow.ApplyTheme;
      // Farben der Ergebnisliste des Suchfelds (#760).
      UpdateHeaders;
    end);
end;

end.
