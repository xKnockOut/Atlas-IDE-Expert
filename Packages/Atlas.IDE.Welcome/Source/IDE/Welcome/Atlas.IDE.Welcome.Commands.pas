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
//   Kurzstatus aus Server und Index; nach jeder Änderung im Statusfeld neu
//   bestimmt, gezeichnet aber nur, wenn sich daran etwas ändert (das Statusfeld
//   ändert sich oft, der Kopf selten).
//   Den Anzeigenamen des Kontos schlägt TAtlasWelcomeAccountName einmal im
//   Hintergrund nach (bei Domänenkonten fragt Windows dafür den
//   Domänencontroller; im Hauptthread kostete das bei jedem Neuzeichnen).
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
// Die Quellen der Bereiche hält Atlas.IDE.Welcome.Areas, das Layout der
// Willkommensseite der IDE Atlas.IDE.Welcome.IdeLayout, den Beobachter für
// welcomePage.openWhenNoProject Atlas.IDE.Welcome.ProjectWatch.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Status.Lines,
  Atlas.Core.Welcome.AccountName,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Header,
  Atlas.UI.Welcome.Board,
  Atlas.IDE.Status.Lines,
  Atlas.IDE.Welcome.Page,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.Layouts,
  Atlas.IDE.Welcome.Areas,
  Atlas.IDE.Welcome.IdeLayout,
  Atlas.IDE.Welcome.ProjectWatch;

type
  TAtlasIdeWelcome = class
  private type
    /// <summary>Was die Komposition hereinreicht (siehe Create).</summary>
    THooks = record
      ServerInfo: TFunc<TAtlasServerInfo>;
      Indexing: TAtlasIndexingFunc;
      Units: TFunc<Integer>;
      Message: TProc<string>;
      /// <summary>Anzeigename des Kontos für den Gruß; im Hintergrund nachgeschlagen (gehört der Steuerung).
      /// </summary>
      Account: TAtlasWelcomeAccountName;
    end;

    /// <summary>Kennungen der Beobachter bei den Bereichen und beim Statusfeld.</summary>
    TListeners = record
      Sections: Integer;
      Status: Integer;
    end;

    /// <summary>Geänderte Bereiche, die der eingereihte Flush zeichnet.</summary>
    TDirty = record
      Ids: TArray<string>;
      Queued: Boolean;
    end;

    /// <summary>Stand des letzten Sync.</summary>
    TSyncState = record
      /// <summary>Erster Sync gelaufen (welcomePage.openOnStart wirkt nur beim Start).</summary>
      Started: Boolean;
      /// <summary>Plugins auf der Willkommensseite der IDE beim letzten Sync gewollt.</summary>
      ShownIde: Boolean;
      /// <summary>Zuletzt gesehenes welcomePage.layout; '' vor dem ersten Sync.</summary>
      LastLayout: string;
    end;
  private
    // Abbau läuft: Was jetzt noch eingereiht würde, liefe nach dem Entladen des Moduls.
    FStopping: Boolean;
    FHooks: THooks;
    FListeners: TListeners;
    FDirty: TDirty;
    FSync: TSyncState;
    FIdeLayout: TAtlasIdeWelcomeIdeLayout;
    FProjectWatch: TAtlasIdeWelcomeProjectWatch;
    FSearch: TAtlasIdeWelcomeSearch;
    FAreas: TAtlasIdeWelcomeAreas;
    FLayouts: TAtlasIdeWelcomeLayouts;
    // Hält die Quelle für „Seite anpassen“ am Leben; die Tafeln halten sie ebenfalls.
    FLayoutsRef: IInterface;
    procedure Announce(const AIds: TArray<string>);
    procedure AttachMenu(AFrame: TAtlasWelcomeFrame);
    procedure SectionChanged(const AId: string);
    procedure Flush;
    function CreateClient(const APluginId: string; AOwner: TComponent): TAtlasWelcomeFrame;
    function FactoryOf(const APluginId: string): TAtlasWelcomeClientFactory;
    procedure RefreshClient(AClient: TAtlasWelcomeFrame);
    /// <summary>Tafel füllen; AFold: Fenster „Atlas-Start“ (Spalten falten, wenn es schmal ist).</summary>
    procedure FillBoard(ABoard: TAtlasWelcomeBoardFrame; AFold: Boolean);
    /// <summary>Gruß und Kurzstatus, wie der Kopf sie jetzt zeigen soll.</summary>
    function HeaderInfo: TAtlasWelcomeHeaderInfo;
    /// <summary>Kopf ganz füllen (Einstellungen, Suchfeld, Menü, Thema).</summary>
    procedure FillHeader(AHeader: TAtlasWelcomeHeaderFrame);
    procedure UpdateHeaders;
    /// <summary>Nur Gruß und Kurzstatus aller gezeigten Köpfe; unverändert bleibt der Kopf unberührt.</summary>
    procedure UpdateHeaderInfos;
    procedure SetLayout(const AValue: string);
  public
    /// <summary>Vor dem Abbau: Kacheln melden beim Freigeben Änderungen, die niemand mehr zeichnet.</summary>
    procedure BeginStop;
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
    /// <summary>Suchfeld (#760); gehört danach der Steuerung. nil = ohne Suchfeld.</summary>
    property Search: TAtlasIdeWelcomeSearch read FSearch write FSearch;
    /// <summary>Quellen der Bereiche; gehören der Steuerung (Start beim Setzen).</summary>
    property Areas: TAtlasIdeWelcomeAreas read FAreas;
    /// <summary>Quelle für „Seite anpassen“ (#767); gehört der Steuerung.</summary>
    property Layouts: TAtlasIdeWelcomeLayouts read FLayouts;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Winapi.Windows,
  Atlas.Core.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Status.Registry,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Greeting,
  Atlas.Core.Welcome.Layout,
  Atlas.Core.Welcome.Layouts,
  Atlas.Core.Welcome.HostLayout,
  Atlas.UI.Welcome.Strings,
  Atlas.UI.Welcome.WhatsNew,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Welcome.Window;

const
  cNameDisplay = 3;

function GetUserNameExW(ANameFormat: Integer; ABuffer: PWideChar; var ASize: ULONG): BOOL; stdcall;
  external 'secur32.dll' name 'GetUserNameExW';

var
  // Lebt die Steuerung noch? Für Arbeit, die über die Nachrichtenschleife kommt.
  Instance: TAtlasIdeWelcome;

/// <summary>Anzeigename des Windows-Kontos; fragt bei Domänenkonten den Domänencontroller (nur im Hintergrund
/// aufrufen, siehe TAtlasWelcomeAccountName).</summary>
function DisplayName: string;
var
  mSize: ULONG;
  mBuffer: array[0..255] of WideChar;
begin
  // Puffer leeren und nur die gemeldete Länge übernehmen: Bei lokalen Konten meldet die Funktion teils
  // Erfolg, ohne etwas zu schreiben; dann stand Speicherrest als Vorname im Gruß.
  FillChar(mBuffer, SizeOf(mBuffer), 0);
  mSize := Length(mBuffer);
  Result := '';
  if GetUserNameExW(cNameDisplay, @mBuffer[0], mSize) and (mSize > 0) and (mSize < ULONG(Length(mBuffer))) then
  begin
    SetString(Result, PWideChar(@mBuffer[0]), mSize);
  end;
  Result := Trim(Result);
end;

function Settings: TAtlasPluginSettings;
begin
  Result := TAtlasIdeSettings.Current;
end;

/// <summary>Nachschlagen des Anzeigenamens für TAtlasWelcomeAccountName (läuft im Hintergrund).</summary>
function AccountLookup: TFunc<string>;
begin
  Result :=
    function: string
    begin
      Result := DisplayName;
    end;
end;

/// <summary>Der Name ist da: Kopf neu zeichnen, solange die Steuerung lebt.</summary>
function AccountChanged: TProc;
begin
  Result :=
    procedure
    begin
      if Instance <> nil then
      begin
        Instance.SectionChanged(TAtlasWelcomeIds.cHeader);
      end;
    end;
end;

{ Hilfen }

function BoardId: string;
begin
  Result := TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.cBoard);
end;

/// <summary>Gezeigte Köpfe: eigener Bereich und Tafel auf der Willkommensseite der IDE, Tafel im Fenster
/// „Atlas-Start“.</summary>
function Headers: TArray<TAtlasWelcomeHeaderFrame>;
var
  mClient: TAtlasWelcomeFrame;
  mBoard: TAtlasWelcomeBoardFrame;
begin
  Result := nil;
  mClient := TAtlasIdeWelcomePage.Client(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.cHeader));
  if mClient is TAtlasWelcomeHeaderFrame then
  begin
    Result := Result + [TAtlasWelcomeHeaderFrame(mClient)];
  end;
  mClient := TAtlasIdeWelcomePage.Client(BoardId);
  if mClient is TAtlasWelcomeBoardFrame then
  begin
    Result := Result + [TAtlasWelcomeBoardFrame(mClient).Header];
  end;
  mBoard := TAtlasIdeWelcomeWindow.ExistingBoard;
  if mBoard <> nil then
  begin
    Result := Result + [mBoard.Header];
  end;
end;

/// <summary>Kopfzeile ohne Gruß: Version des Plugins (die des Servers steht im Statusfeld), Phase, Index.
/// </summary>
function StatusInfo(const AServer: TAtlasServerInfo; AIndexing: Boolean; APercent, AUnits: Integer):
  TAtlasWelcomeHeaderInfo;
begin
  Result := Default(TAtlasWelcomeHeaderInfo);
  Result.Version := TAtlasPluginVersion.cVersion;
  Result.Phase := AServer.Phase;
  Result.Units := AUnits;
  Result.Indexing := AIndexing;
  Result.Percent := APercent;
end;

function CaptionOf(const APluginId: string): string;
var
  mId: string;
  mSection: TAtlasWelcomeSection;
begin
  mId := TAtlasWelcomeIds.SectionOf(APluginId);
  if SameText(mId, TAtlasWelcomeIds.cHeader) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeHeaderTitle);
  end
  else if SameText(mId, TAtlasWelcomeIds.cBoard) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeBoardTitle);
  end
  else if TAtlasWelcomeSections.Default.Find(mId, mSection) then
  begin
    Result := mSection.Title;
  end
  else
  begin
    Result := APluginId;
  end;
end;

procedure UpdateSection(const AId: string);
var
  mClient: TAtlasWelcomeFrame;
  mBoard: TAtlasWelcomeBoardFrame;
begin
  mClient := TAtlasIdeWelcomePage.Client(TAtlasWelcomeIds.PluginId(AId));
  if mClient <> nil then
  begin
    mClient.UpdateContent;
  end;
  mClient := TAtlasIdeWelcomePage.Client(BoardId);
  if mClient is TAtlasWelcomeBoardFrame then
  begin
    TAtlasWelcomeBoardFrame(mClient).UpdateSection(AId);
  end;
  mBoard := TAtlasIdeWelcomeWindow.ExistingBoard;
  if mBoard <> nil then
  begin
    mBoard.UpdateSection(AId);
  end;
end;

function Contains(const AList: TArray<string>; const AValue: string): Boolean;
var
  mItem: string;
begin
  Result := False;
  for mItem in AList do
  begin
    Result := Result or SameText(mItem, AValue);
  end;
end;

/// <summary>Gewünschte Plugins auf der Willkommensseite der IDE: im Atlas-Layout nur die Tafel, sonst Kopf und
/// je sichtbarem Bereich eins.</summary>
function WantedPlugins(const ACurrent: TAtlasPluginSettings; AIdePage: Boolean): TArray<string>;
var
  mSection: TAtlasWelcomeSection;
begin
  Result := nil;
  if not AIdePage then
  begin
    Exit;
  end;
  if ACurrent.WelcomePageLayout = 'atlas' then
  begin
    Result := [BoardId];
    Exit;
  end;
  if ACurrent.WelcomePageHeader then
  begin
    Result := [TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.cHeader)];
  end;
  for mSection in TAtlasWelcomeSections.Default.Visible do
  begin
    if TAtlasWelcomeViews.Exists(mSection.Id) then
    begin
      Result := Result + [TAtlasWelcomeIds.PluginId(mSection.Id)];
    end;
  end;
end;

/// <summary>Plugins der Willkommensseite der IDE auf AWanted bringen; gebliebene neu füllen.</summary>
procedure SyncPlugins(ASelf: TAtlasIdeWelcome; const AWanted: TArray<string>);
var
  mRegistered: TArray<string>;
  mId, mPlugin: string;
begin
  mRegistered := TAtlasIdeWelcomePage.Registered;
  for mPlugin in mRegistered do
  begin
    if not Contains(AWanted, mPlugin) then
    begin
      TAtlasIdeWelcomePage.Unregister(mPlugin);
    end;
  end;
  for mId in AWanted do
  begin
    if Contains(mRegistered, mId) then
    begin
      ASelf.RefreshClient(TAtlasIdeWelcomePage.Client(mId));
    end
    else
    begin
      // Fabrik je Kennung über FactoryOf: Eine Closure hier sähe nur die letzte Schleifenvariable.
      TAtlasIdeWelcomePage.Register(mId, CaptionOf(mId), ASelf.FactoryOf(mId));
    end;
  end;
end;

/// <summary>„Atlas-Start“, unabhängig von der Willkommensseite der IDE: beim ersten Sync nach Wunsch öffnen,
/// danach nur nachführen; aus = schließen.</summary>
procedure SyncWindow(ASelf: TAtlasIdeWelcome; const ACurrent: TAtlasPluginSettings);
begin
  if not ACurrent.WelcomePage then
  begin
    TAtlasIdeWelcomeWindow.Hide;
    Exit;
  end;
  if not ASelf.FSync.Started and ACurrent.WelcomePageOpenOnStart then
  begin
    TAtlasIdeWelcomeWindow.Show;
  end;
  ASelf.FillBoard(TAtlasIdeWelcomeWindow.ExistingBoard, True);
end;

/// <summary>Umschalten in den Optionen: wie die Menübefehle, aber ohne Meldung. Beim Start gilt, was die IDE aus
/// der Registry liest (CheckPending und Aufräumen im Konstruktor).</summary>
procedure SyncIdeLayout(ASelf: TAtlasIdeWelcome; const ACurrent: TAtlasPluginSettings; AIdePage: Boolean);
var
  mStep: TAtlasIdePageStep;
begin
  for mStep in TAtlasIdePageSteps.After(ASelf.FSync.Started, ASelf.FSync.ShownIde, AIdePage, ASelf.FSync.LastLayout,
    ACurrent.WelcomePageLayout) do
  begin
    case mStep of
      TAtlasIdePageStep.Retire:
        ASelf.FIdeLayout.Retire;
      TAtlasIdePageStep.ClearPending:
        ASelf.FIdeLayout.ClearPending;
      TAtlasIdePageStep.PlaceBoard:
        ASelf.FIdeLayout.Place(False);
      TAtlasIdePageStep.Unplace:
        ASelf.FIdeLayout.Unplace(False);
      TAtlasIdePageStep.None: ;
    end;
  end;
end;

/// <summary>Kennung AId vormerken und einmal Flush einreihen (nur im Hauptthread).</summary>
procedure MarkDirty(const AId: string);
var
  mFlush: TThreadProcedure;
begin
  if (Instance = nil) or Contains(Instance.FDirty.Ids, AId) then
  begin
    Exit;
  end;
  Instance.FDirty.Ids := Instance.FDirty.Ids + [AId];
  if Instance.FDirty.Queued then
  begin
    Exit;
  end;
  Instance.FDirty.Queued := True;
  mFlush :=
    procedure
    begin
      if Instance <> nil then
      begin
        Instance.Flush;
      end;
    end;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomeUpdates, mFlush);
end;

/// <summary>Höhe des Bereichs AId auf der Tafel ABoard; sonst die Vorgabe.</summary>
function ViewHeight(ABoard: TAtlasWelcomeBoardFrame; const AId: string): Integer;
var
  mView: TAtlasWelcomeSectionFrame;
begin
  mView := ABoard.View(AId);
  Result := TAtlasWelcomeSectionFrame.cDefaultBodyHeight;
  if mView <> nil then
  begin
    Result := mView.Height;
  end;
end;

{ TAtlasIdeWelcome }

constructor TAtlasIdeWelcome.Create(const AServerInfo: TFunc<TAtlasServerInfo>;
  const AIndexing: TAtlasIndexingFunc; const AUnits: TFunc<Integer>; const AMessage: TProc<string>);
begin
  inherited Create;
  Instance := Self;
  FHooks.ServerInfo := AServerInfo;
  FHooks.Indexing := AIndexing;
  FHooks.Units := AUnits;
  FHooks.Message := AMessage;
  FAreas := TAtlasIdeWelcomeAreas.Create;
  FHooks.Account := TAtlasWelcomeAccountName.Create(AccountLookup(), AccountChanged());
  FIdeLayout := TAtlasIdeWelcomeIdeLayout.Create(AMessage);
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
  FListeners.Sections := TAtlasWelcomeSections.Default.AddListener(
    procedure(AId: string)
    begin
      SectionChanged(AId);
    end);
  FListeners.Status := TAtlasStatusRegistry.Default.AddListener(
    procedure
    begin
      SectionChanged(TAtlasWelcomeIds.cHeader);
    end);
  TAtlasIdeWelcomeWindow.OnFrame :=
    procedure(ABoard: TAtlasWelcomeBoardFrame)
    begin
      FillBoard(ABoard, True);
    end;
  // Früh anmelden: Die IDE speichert das Fenster im Desktop und legt es beim Laden selbst an (#879).
  TAtlasIdeWelcomeWindow.Prepare;
  FIdeLayout.CheckPending;
  if not TAtlasIdeWelcomeIdeLayout.Wanted(Settings) then
  begin
    FIdeLayout.Retire;
  end;
  FProjectWatch := TAtlasIdeWelcomeProjectWatch.Create(
    procedure
    begin
      if Instance <> nil then
      begin
        Instance.ShowStart;
      end;
    end);
end;

destructor TAtlasIdeWelcome.Destroy;
begin
  Instance := nil;
  // Zuerst: wartet eine laufende Abfrage des Namens ab; ihr Abschluss erreicht danach nichts mehr.
  FreeAndNil(FHooks.Account);
  FreeAndNil(FProjectWatch);
  // Vor den Frames: löst die Suchfelder, die noch leben.
  FreeAndNil(FSearch);
  TAtlasWelcomeSections.Default.RemoveListener(FListeners.Sections);
  TAtlasStatusRegistry.Default.RemoveListener(FListeners.Status);
  FAreas.Stop;
  // Beim Beenden der IDE: Hat die IDE ihr Layout aus dem Speicher zurückgeschrieben, gilt die Marke weiter.
  TAtlasIdeWelcomePage.RemoveAll;
  TAtlasIdeWelcomeWindow.Release;
  // Nach den Frames: Sie halten die Quellen ebenfalls.
  FAreas.Release;
  FreeAndNil(FAreas);
  FLayouts := nil;
  FLayoutsRef := nil;
  FreeAndNil(FIdeLayout);
  inherited;
end;

/// <summary>Kontextmenü „Neu in Atlas“ an Frame „Atlas“ bzw. Kopf hängen oder (off) entfernen.</summary>
procedure TAtlasIdeWelcome.AttachMenu(AFrame: TAtlasWelcomeFrame);
var
  mMenu: TAtlasWhatsNewMenu;
begin
  if AFrame = nil then
  begin
    Exit;
  end;
  mMenu := nil;
  if AFrame.PopupMenu is TAtlasWhatsNewMenu then
  begin
    mMenu := TAtlasWhatsNewMenu(AFrame.PopupMenu);
  end;
  if (FAreas.WhatsNew = nil) or not FAreas.WhatsNew.Active then
  begin
    if mMenu <> nil then
    begin
      AFrame.PopupMenu := nil;
      mMenu.Free;
    end;
    Exit;
  end;
  if mMenu = nil then
  begin
    mMenu := TAtlasWhatsNewMenu.Create(AFrame);
    AFrame.PopupMenu := mMenu;
  end;
  mMenu.Source := FAreas.WhatsNew;
end;

function TAtlasIdeWelcome.HeaderInfo: TAtlasWelcomeHeaderInfo;
var
  mServer: TAtlasServerInfo;
  mPercent, mUnits: Integer;
  mIndexing: Boolean;
  mHour, mMinute, mSecond, mMSec: Word;
begin
  mServer := Default(TAtlasServerInfo);
  if Assigned(FHooks.ServerInfo) then
  begin
    mServer := FHooks.ServerInfo();
  end;
  mPercent := -1;
  mIndexing := False;
  if Assigned(FHooks.Indexing) then
  begin
    mIndexing := FHooks.Indexing(mPercent);
  end;
  mUnits := -1;
  if Assigned(FHooks.Units) then
  begin
    mUnits := FHooks.Units();
  end;
  DecodeTime(Now, mHour, mMinute, mSecond, mMSec);
  Result := StatusInfo(mServer, mIndexing, mPercent, mUnits);
  Result.Greeting := Settings.WelcomePageGreeting;
  Result.Hour := mHour;
  // Ohne Grußzeile kein Nachschlagen des Namens (bei Domänenkonten eine Anfrage an den Domänencontroller).
  if Result.Greeting then
  begin
    Result.FirstName := TAtlasWelcomeGreeting.FirstName(FHooks.Account.Name, GetEnvironmentVariable('USERNAME'));
  end;
end;

procedure TAtlasIdeWelcome.FillHeader(AHeader: TAtlasWelcomeHeaderFrame);
begin
  if AHeader = nil then
  begin
    Exit;
  end;
  // Thema, Sprache oder Einstellungen können sich geändert haben: alles neu setzen.
  AHeader.Renew;
  AHeader.ShowInfo(HeaderInfo);
  AHeader.ShowSearch(Settings.WelcomePageSearch and (FSearch <> nil));
  if (FSearch <> nil) and (AHeader.Search <> nil) then
  begin
    FSearch.Attach(AHeader.Search);
  end;
  AttachMenu(AHeader);
end;

procedure TAtlasIdeWelcome.FillBoard(ABoard: TAtlasWelcomeBoardFrame; AFold: Boolean);
var
  mLayout: TAtlasWelcomeLayout;
  mBoard: TAtlasWelcomeBoardFrame;
begin
  if ABoard = nil then
  begin
    Exit;
  end;
  mBoard := ABoard;
  // Eigenes Layout (#767) bzw. das feste Atlas-Layout (#753); neue Bereiche nach Höhe in die Spalte mit dem
  // meisten Platz.
  mLayout := FLayouts.BoardLayout(
    function(const AId: string): Integer
    begin
      Result := ViewHeight(mBoard, AId);
    end);
  // Nach einem Update steht „Neu in Atlas“ oben in der ersten Spalte (#756); beim Anpassen der echte Platz.
  if (FAreas.WhatsNew <> nil) and FAreas.WhatsNew.OnTop and not FLayouts.Editing then
  begin
    mLayout := mLayout.MovedToTop(TAtlasWelcomeIds.cNews);
  end;
  ABoard.Header.Visible := Settings.WelcomePageHeader;
  FillHeader(ABoard.Header);
  AttachMenu(ABoard);
  ABoard.AutoFold := AFold;
  ABoard.Source := FLayouts;
  ABoard.Rebuild(TAtlasWelcomeSections.Default.Visible, mLayout, mLayout.Columns);
end;

procedure TAtlasIdeWelcome.Announce(const AIds: TArray<string>);
var
  mItems: TArray<TAtlasWhatsNewItem>;
  mItem: TAtlasWhatsNewItem;
  mSection: TAtlasWelcomeSection;
  mId: string;
begin
  if FAreas.WhatsNew = nil then
  begin
    Exit;
  end;
  mItems := nil;
  for mId in AIds do
  begin
    if not TAtlasWelcomeSections.Default.Find(mId, mSection) then
    begin
      Continue;
    end;
    mItem := Default(TAtlasWhatsNewItem);
    mItem.Title := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeArrangeNewSection, [mSection.Title]);
    mItem.Text := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeNewSectionText);
    mItem.Setting := TAtlasWelcomeCustomizing.SettingOf(mId);
    mItem.Command := TAtlasIdeWelcomeLayouts.cCommandId;
    mItems := mItems + [mItem];
  end;
  FAreas.WhatsNew.Announce(mItems);
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
      Client := TAtlasIdeWelcomePage.Client(BoardId);
      if not FLayouts.Editing and not (Client is TAtlasWelcomeBoardFrame) then
      begin
        ShowStart;
      end;
      FLayouts.SetEditing(not FLayouts.Editing);
    end);
end;

/// <summary>Millisekunden seit AStart (Now); genau genug für die Startzeiten in atlas.log.</summary>
function ElapsedMs(AStart: TDateTime): Int64;
begin
  Result := Round((Now - AStart) * MSecsPerDay);
end;

procedure TAtlasIdeWelcome.Sync;
const
  // Langsamer Abgleich (Startzeit 06.11.2026) mit Dauer je Schritt nach atlas.log.
  cSlowSyncMs = 200;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mCurrent: TAtlasPluginSettings;
      mIdePage: Boolean;
      mStart: TDateTime;
      mLaps: array[0..4] of Int64;
    begin
      mStart := Now;
      mCurrent := Settings;
      FAreas.Refresh;
      mLaps[0] := ElapsedMs(mStart);
      mIdePage := TAtlasIdeWelcomeIdeLayout.Wanted(mCurrent) and TAtlasIdeWelcomePage.Available;
      SyncPlugins(Self, WantedPlugins(mCurrent, mIdePage));
      mLaps[1] := ElapsedMs(mStart);
      SyncWindow(Self, mCurrent);
      mLaps[2] := ElapsedMs(mStart);
      SyncIdeLayout(Self, mCurrent, mIdePage);
      mLaps[3] := ElapsedMs(mStart);
      FSync.ShownIde := mIdePage;
      FSync.LastLayout := mCurrent.WelcomePageLayout;
      FSync.Started := True;
      UpdateHeaders;
      mLaps[4] := ElapsedMs(mStart);
      if mLaps[4] >= cSlowSyncMs then
      begin
        TAtlasGuard.Log(Format('Welcome sync %d ms: areas %d, plugins %d, window %d, ide layout %d, headers %d ms',
          [mLaps[4], mLaps[0], mLaps[1] - mLaps[0], mLaps[2] - mLaps[1], mLaps[3] - mLaps[2], mLaps[4] - mLaps[3]]));
      end;
    end);
end;

function TAtlasIdeWelcome.CreateClient(const APluginId: string; AOwner: TComponent): TAtlasWelcomeFrame;
var
  mId: string;
  mHeader: TAtlasWelcomeHeaderFrame;
  mBoard: TAtlasWelcomeBoardFrame;
  mView: TAtlasWelcomeSectionFrame;
begin
  mId := TAtlasWelcomeIds.SectionOf(APluginId);
  if SameText(mId, TAtlasWelcomeIds.cHeader) then
  begin
    mHeader := TAtlasWelcomeHeaderFrame.Create(AOwner);
    FillHeader(mHeader);
    Result := mHeader;
  end
  else if SameText(mId, TAtlasWelcomeIds.cBoard) then
  begin
    mBoard := TAtlasWelcomeBoardFrame.Create(AOwner);
    FillBoard(mBoard, False);
    Result := mBoard;
  end
  else
  begin
    // Die IDE zeigt den Titel im Rahmen; der Bereich selbst ohne Titelzeile.
    mView := TAtlasWelcomeViews.CreateView(mId, AOwner);
    if mView <> nil then
    begin
      mView.ShowTitle := False;
    end;
    Result := mView;
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

procedure TAtlasIdeWelcome.BeginStop;
begin
  FStopping := True;
end;

procedure TAtlasIdeWelcome.SectionChanged(const AId: string);
var
  mId: string;
  mCollect: TThreadProcedure;
begin
  if FStopping then
  begin
    Exit;
  end;
  mId := AId;
  // Beobachter melden auch aus Hintergrund-Threads; gesammelt und gezeichnet wird im Hauptthread.
  mCollect :=
    procedure
    begin
      MarkDirty(mId);
    end;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomeUpdates, mCollect);
end;

procedure TAtlasIdeWelcome.Flush;
var
  mIds: TArray<string>;
begin
  FDirty.Queued := False;
  mIds := FDirty.Ids;
  FDirty.Ids := nil;
  // Bereiche kamen hinzu, fielen weg oder wurden ein- oder ausgeschaltet.
  if Contains(mIds, '') then
  begin
    Sync;
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.WelcomeUpdates,
    procedure
    var
      Item: string;
    begin
      for Item in mIds do
      begin
        if SameText(Item, TAtlasWelcomeIds.cHeader) then
        begin
          // Statusfeld oder Kontoname: nur Gruß und Kurzstatus, und nur, wenn sich daran etwas ändert.
          UpdateHeaderInfos;
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

procedure TAtlasIdeWelcome.UpdateHeaders;
var
  mClient: TAtlasWelcomeFrame;
  mBoard: TAtlasWelcomeBoardFrame;
begin
  mClient := TAtlasIdeWelcomePage.Client(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.cHeader));
  if mClient is TAtlasWelcomeHeaderFrame then
  begin
    FillHeader(TAtlasWelcomeHeaderFrame(mClient));
  end;
  mClient := TAtlasIdeWelcomePage.Client(BoardId);
  if mClient is TAtlasWelcomeBoardFrame then
  begin
    TAtlasWelcomeBoardFrame(mClient).Header.Visible := Settings.WelcomePageHeader;
    FillHeader(TAtlasWelcomeBoardFrame(mClient).Header);
  end;
  mBoard := TAtlasIdeWelcomeWindow.ExistingBoard;
  if mBoard <> nil then
  begin
    mBoard.Header.Visible := Settings.WelcomePageHeader;
    FillHeader(mBoard.Header);
  end;
end;

procedure TAtlasIdeWelcome.UpdateHeaderInfos;
var
  mHeaders: TArray<TAtlasWelcomeHeaderFrame>;
  mHeader: TAtlasWelcomeHeaderFrame;
  mInfo: TAtlasWelcomeHeaderInfo;
begin
  mHeaders := Headers;
  if mHeaders = nil then
  begin
    Exit;
  end;
  mInfo := HeaderInfo;
  for mHeader in mHeaders do
  begin
    mHeader.ShowInfo(mInfo);
  end;
end;

procedure TAtlasIdeWelcome.SetLayout(const AValue: string);
var
  mNext: TAtlasPluginSettings;
begin
  mNext := TAtlasIdeSettings.Stored;
  if SameText(mNext.WelcomePageLayout, AValue) then
  begin
    Sync;
    Exit;
  end;
  mNext.WelcomePageLayout := AValue;
  // Update meldet OnChanged; die Komposition ruft daraufhin Sync.
  TAtlasIdeSettings.Update(mNext);
end;

procedure TAtlasIdeWelcome.ApplyLayout;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      // Nur auf der Willkommensseite der IDE; ist sie für Atlas aus, gibt es dort nichts anzuordnen.
      if not TAtlasIdeWelcomeIdeLayout.Wanted(Settings) or not FIdeLayout.Place(True) then
      begin
        Exit;
      end;
      // Sync soll nicht ein zweites Mal platzieren.
      FSync.LastLayout := 'atlas';
      SetLayout('atlas');
    end);
end;

procedure TAtlasIdeWelcome.ResetLayout;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if not FIdeLayout.Unplace(True) then
      begin
        Exit;
      end;
      FSync.LastLayout := 'off';
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
  if FAreas.WhatsNew = nil then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      FAreas.WhatsNew.Show(AView);
      // Auf der Willkommensseite der IDE zeigt die Karte sich dort; sonst im Fenster.
      if not FSync.ShownIde then
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
