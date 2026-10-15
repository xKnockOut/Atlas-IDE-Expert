unit Atlas.IDE.Welcome.Commands;

// Steuerung der Atlas-Willkommensseite (#753):
// - Sync richtet nach den Einstellungen ein, was die IDE zeigt: auf der
//   Willkommensseite je eingeschaltetem Bereich ein Plugin (plus Kopf), im
//   Atlas-Layout ein einziges Plugin „Atlas“ mit Kopf und allen Bereichen in
//   zwei Spalten; ohne Schnittstelle bzw. mit welcomePage.host = dockWindow das
//   Fenster „Atlas-Start“ mit einer Spalte. welcomePage.enabled aus: nichts.
// - ApplyLayout sichert den Registry-Schlüssel WelcomePage der IDE nach
//   %LOCALAPPDATA%\Atlas\welcomepage-layout-backup.json (nur, wenn noch keine
//   Sicherung existiert), setzt „Atlas“ oben über alle Spalten, schiebt die
//   übrigen Bereiche nach unten und setzt welcomePage.layout = atlas.
//   ResetLayout schreibt die Sicherung exakt zurück und setzt layout = off.
//   Hält die IDE ihr Layout im Speicher und schreibt es beim Beenden zurück,
//   wiederholt der nächste Start die Platzierung (Marke …-pending).
// - Kopf: Grußzeile nach Uhrzeit und Vorname des Windows-Kontos, Version,
//   Kurzstatus aus Server und Index; neu bei jeder Änderung im Statusfeld.
//   Rechts das Suchfeld (#760, welcomePage.search), angebunden an Search.
// - Karte „Neu in Atlas“ (#756, WhatsNew): nach einem Update oben in der
//   ersten Spalte; Kontextmenü von Frame „Atlas“ und Kopf mit „Neuigkeiten
//   dieser Version zeigen“ und „Alle Versionen“ (nicht bei
//   welcomePage.whatsNew = off).
// - Bereich „Projekte“ (#592, Projects): Zustand je zuletzt geöffnetem
//   Projekt aus den Projekt-Zusammenfassungen; meldet sich selbst an.
// - Bereich „Nicht gesichert“ (#762, Unsaved): nicht Committetes, nicht
//   Gepushtes und Stashes je Projekt; meldet sich selbst an.
// - Zustandskachel „Atlas“ (#754, State): Server, Version, Index,
//   Einrichtung und Diagnosemodus aus den Zeilen des Statusfelds (#591);
//   meldet sich selbst an.
// - Karte „Atlas entdecken“ (#757, Discover): ein Tipp je Start aus tips.json
//   nach der gemeinsamen Zählung (#600); meldet sich selbst an.
// Die Willkommensseite startet keinen Server und liest nur lokale Daten.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Status.Lines,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Backup,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Header,
  Atlas.UI.Welcome.Board,
  Atlas.IDE.Status.Lines,
  Atlas.IDE.Welcome.Page,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.WhatsNew,
  Atlas.IDE.Welcome.Projects,
  Atlas.IDE.Welcome.Unsaved,
  Atlas.IDE.Welcome.State,
  Atlas.IDE.Welcome.Discover;

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
    FShownHost: string;
    // Zuletzt gesehenes welcomePage.layout; '' vor dem ersten Sync.
    FLastLayout: string;
    FAccess: IAtlasRegistryAccess;
    FSearch: TAtlasIdeWelcomeSearch;
    FWhatsNew: TAtlasIdeWhatsNew;
    // Hält die Quelle der Karte am Leben; die Frames halten sie ebenfalls als Schnittstelle.
    FWhatsNewRef: IInterface;
    FProjects: TAtlasIdeProjects;
    // Hält die Quelle des Bereichs „Projekte“ am Leben; die Frames halten sie ebenfalls.
    FProjectsRef: IInterface;
    FUnsaved: TAtlasIdeUnsaved;
    // Hält die Quelle des Bereichs „Nicht gesichert“ am Leben; die Frames halten sie ebenfalls.
    FUnsavedRef: IInterface;
    FState: TAtlasIdeWelcomeState;
    // Hält die Quelle der Zustandskachel am Leben; die Frames halten sie ebenfalls.
    FStateRef: IInterface;
    FDiscover: TAtlasIdeDiscover;
    // Hält die Quelle der Karte „Atlas entdecken“ am Leben; die Frames halten sie ebenfalls.
    FDiscoverRef: IInterface;
    procedure SetWhatsNew(AValue: TAtlasIdeWhatsNew);
    procedure SetState(AValue: TAtlasIdeWelcomeState);
    procedure SetDiscover(AValue: TAtlasIdeDiscover);
    procedure SetProjects(AValue: TAtlasIdeProjects);
    procedure SetUnsaved(AValue: TAtlasIdeUnsaved);
    procedure AttachMenu(AFrame: TAtlasWelcomeFrame);
    procedure SectionChanged(const AId: string);
    procedure Flush;
    function CaptionOf(const APluginId: string): string;
    function CreateClient(const APluginId: string; AOwner: TComponent): TAtlasWelcomeFrame;
    function FactoryOf(const APluginId: string): TAtlasWelcomeClientFactory;
    procedure UpdateSection(const AId: string);
    procedure RefreshClient(AClient: TAtlasWelcomeFrame);
    procedure FillBoard(ABoard: TAtlasWelcomeBoardFrame; AColumns: Integer);
    procedure FillHeader(AHeader: TAtlasWelcomeHeaderFrame);
    procedure UpdateHeaders;
    function WelcomeKey: string;
    function PlaceBoard: Boolean;
    function BoardPlaced: Boolean;
    procedure CheckPending;
    procedure SetLayout(const AValue: string);
    function Place(AReport: Boolean): Boolean;
    function Unplace(AReport: Boolean): Boolean;
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
    procedure ApplyLayout;
    procedure ResetLayout;
    procedure ThemeChanged;
    /// <summary>Wird für Tests ersetzt; Vorgabe: Registry der IDE.</summary>
    property Access: IAtlasRegistryAccess read FAccess write FAccess;
    /// <summary>Suchfeld (#760); gehört danach der Steuerung. nil = ohne Suchfeld.</summary>
    property Search: TAtlasIdeWelcomeSearch read FSearch write FSearch;
    /// <summary>Karte „Neu in Atlas“ (#756); gehört danach der Steuerung (Start beim Setzen). nil = ohne.</summary>
    property WhatsNew: TAtlasIdeWhatsNew read FWhatsNew write SetWhatsNew;
    /// <summary>Bereich „Projekte“ (#592); gehört danach der Steuerung (Start beim Setzen). nil = ohne.</summary>
    property Projects: TAtlasIdeProjects read FProjects write SetProjects;
    /// <summary>Bereich „Nicht gesichert“ (#762); gehört danach der Steuerung (Start beim Setzen). nil = ohne.</summary>
    property Unsaved: TAtlasIdeUnsaved read FUnsaved write SetUnsaved;
    /// <summary>Zustandskachel „Atlas“ (#754); gehört danach der Steuerung (Start beim Setzen). nil = ohne.</summary>
    property State: TAtlasIdeWelcomeState read FState write SetState;
    /// <summary>Karte „Atlas entdecken“ (#757); gehört danach der Steuerung (Start beim Setzen). nil = ohne.
    /// </summary>
    property Discover: TAtlasIdeDiscover read FDiscover write SetDiscover;
    class function HeaderInfo(const AServer: TAtlasServerInfo; AIndexing: Boolean; APercent, AUnits: Integer;
      AHour: Integer; const AFirstName: string; AGreeting: Boolean): TAtlasWelcomeHeaderInfo; static;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  Atlas.Core.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Status.Registry,
  Atlas.Core.Welcome.Greeting,
  Atlas.Core.Welcome.Layout,
  Atlas.Core.Welcome.HostLayout,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.WhatsNew,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Welcome.Registry,
  Atlas.IDE.Welcome.Window;

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
  Size := Length(Buffer);
  if GetUserNameExW(NameDisplay, @Buffer[0], Size) then
    Result := Buffer
  else
    Result := '';
end;

/// <summary>Textdatei lesen; ohne Byte-Order-Mark, das TFile.WriteAllText mit UTF-8 schreibt.</summary>
function ReadText(const AFileName: string): string;
begin
  Result := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
end;

function Settings: TAtlasPluginSettings;
begin
  Result := TAtlasIdeSettings.Current;
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
  FSectionsListener := TAtlasWelcomeSections.Default.AddListener(SectionChanged);
  FStatusListener := TAtlasStatusRegistry.Default.AddListener(
    procedure
    begin
      SectionChanged(TAtlasWelcomeIds.Header);
    end);
  TAtlasIdeWelcomeWindow.OnFrame :=
    procedure(ABoard: TAtlasWelcomeBoardFrame)
    begin
      FillBoard(ABoard, 1);
    end;
  CheckPending;
end;

destructor TAtlasIdeWelcome.Destroy;
begin
  Instance := nil;
  // Vor den Frames: löst die Suchfelder, die noch leben.
  FreeAndNil(FSearch);
  TAtlasWelcomeSections.Default.RemoveListener(FSectionsListener);
  TAtlasStatusRegistry.Default.RemoveListener(FStatusListener);
  if FWhatsNew <> nil then
    FWhatsNew.Stop;
  if FProjects <> nil then
    FProjects.Stop;
  if FUnsaved <> nil then
    FUnsaved.Stop;
  if FState <> nil then
    FState.Stop;
  if FDiscover <> nil then
    FDiscover.Stop;
  // Beim Beenden der IDE: Hat die IDE ihr Layout aus dem Speicher zurückgeschrieben, gilt die Marke weiter.
  TAtlasIdeWelcomePage.RemoveAll;
  TAtlasIdeWelcomeWindow.Release;
  // Nach den Frames: Sie halten die Quelle der Karte ebenfalls.
  FWhatsNew := nil;
  FWhatsNewRef := nil;
  FProjects := nil;
  FProjectsRef := nil;
  FUnsaved := nil;
  FUnsavedRef := nil;
  FState := nil;
  FStateRef := nil;
  FDiscover := nil;
  FDiscoverRef := nil;
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

procedure TAtlasIdeWelcome.FillBoard(ABoard: TAtlasWelcomeBoardFrame; AColumns: Integer);
var
  Layout: TAtlasWelcomeLayout;
begin
  if ABoard = nil then
    Exit;
  Layout := TAtlasWelcomeLayout.Atlas;
  // Nach einem Update steht „Neu in Atlas“ oben in der ersten Spalte (#756).
  if (FWhatsNew <> nil) and FWhatsNew.OnTop then
    Layout := Layout.MovedToTop(TAtlasWelcomeIds.News);
  ABoard.Header.Visible := Settings.WelcomePageHeader;
  FillHeader(ABoard.Header);
  AttachMenu(ABoard);
  ABoard.Rebuild(TAtlasWelcomeSections.Default.Visible, Layout, AColumns);
end;

procedure TAtlasIdeWelcome.Sync;
var
  Current: TAtlasPluginSettings;
  Host: string;
  Wanted: TArray<string>;
  Section: TAtlasWelcomeSection;
  Id, Plugin: string;
  Registered: TArray<string>;
  Keep: Boolean;
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
      if not Current.WelcomePage then
        Host := ''
      else if (Current.WelcomePageHost = 'dockWindow') or not TAtlasIdeWelcomePage.Available then
        Host := 'dockWindow'
      else
        Host := 'welcomePage';
      // Gewünschte Plugins auf der Willkommensseite.
      Wanted := nil;
      if (Host = 'welcomePage') and (Current.WelcomePageLayout = 'atlas') then
        Wanted := [TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Board)]
      else if Host = 'welcomePage' then
      begin
        if Current.WelcomePageHeader then
          Wanted := [TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Header)];
        for Section in TAtlasWelcomeSections.Default.Visible do
          if TAtlasWelcomeViews.Exists(Section.Id) then
            Wanted := Wanted + [TAtlasWelcomeIds.PluginId(Section.Id)];
      end;
      Registered := TAtlasIdeWelcomePage.Registered;
      for Plugin in Registered do
      begin
        Keep := False;
        for Id in Wanted do
          Keep := Keep or SameText(Id, Plugin);
        if not Keep then
          TAtlasIdeWelcomePage.Unregister(Plugin);
      end;
      for Id in Wanted do
      begin
        Keep := False;
        for Plugin in Registered do
          Keep := Keep or SameText(Id, Plugin);
        if not Keep then
          // Fabrik je Kennung über FactoryOf: Eine Closure hier sähe nur die letzte Schleifenvariable.
          TAtlasIdeWelcomePage.Register(Id, CaptionOf(Id), FactoryOf(Id))
        else
          RefreshClient(TAtlasIdeWelcomePage.Client(Id));
      end;
      // Fenster „Atlas-Start“: beim Wechsel dorthin öffnen, sonst nur nachführen.
      if Host = 'dockWindow' then
      begin
        if FShownHost <> 'dockWindow' then
          TAtlasIdeWelcomeWindow.Show;
        FillBoard(TAtlasIdeWelcomeWindow.ExistingBoard, 1);
      end
      else if Host = '' then
        TAtlasIdeWelcomeWindow.Hide
      else
        FillBoard(TAtlasIdeWelcomeWindow.ExistingBoard, 1);
      FShownHost := Host;
      // welcomePage.layout in den Optionen umgeschaltet: wie die Menübefehle, aber ohne Meldung.
      if (FLastLayout <> '') and not SameText(FLastLayout, Current.WelcomePageLayout) then
      begin
        if not SameText(Current.WelcomePageLayout, 'atlas') then
          Unplace(False)
        else if Host = 'welcomePage' then
          Place(False);
      end;
      FLastLayout := Current.WelcomePageLayout;
      UpdateHeaders;
    end);
end;

procedure TAtlasIdeWelcome.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

function TAtlasIdeWelcome.CaptionOf(const APluginId: string): string;
var
  Id: string;
  Section: TAtlasWelcomeSection;
begin
  Id := TAtlasWelcomeIds.SectionOf(APluginId);
  if SameText(Id, TAtlasWelcomeIds.Header) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeHeaderTitle)
  else if SameText(Id, TAtlasWelcomeIds.Board) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeBoardTitle)
  else if TAtlasWelcomeSections.Default.Find(Id, Section) then
    Result := Section.Title
  else
    Result := APluginId;
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
    FillBoard(Board, 2);
    Result := Board;
  end
  else
  begin
    // Die IDE zeigt den Titel im Rahmen; der Bereich selbst ohne Titelzeile.
    View := TAtlasWelcomeViews.CreateView(Id, AOwner);
    if View <> nil then
      View.ShowTitle := False;
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
        Result := Instance.CreateClient(APluginId, AOwner);
    end;
end;

procedure TAtlasIdeWelcome.SectionChanged(const AId: string);
var
  Id: string;
begin
  Id := AId;
  // Beobachter melden auch aus Hintergrund-Threads; gesammelt und gezeichnet wird im Hauptthread.
  TThread.ForceQueue(nil,
    procedure
    var
      Known: string;
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
      TThread.ForceQueue(nil,
        procedure
        begin
          if Instance <> nil then
            Instance.Flush;
        end);
    end);
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

/// <summary>Gezeigten Inhalt nach Einstellungen und Bereichen neu füllen.</summary>
procedure TAtlasIdeWelcome.RefreshClient(AClient: TAtlasWelcomeFrame);
begin
  if AClient is TAtlasWelcomeBoardFrame then
    FillBoard(TAtlasWelcomeBoardFrame(AClient), 2)
  else if AClient is TAtlasWelcomeHeaderFrame then
    FillHeader(TAtlasWelcomeHeaderFrame(AClient))
  else if AClient <> nil then
    AClient.UpdateContent;
end;

procedure TAtlasIdeWelcome.UpdateSection(const AId: string);
var
  Client: TAtlasWelcomeFrame;
  Board: TAtlasWelcomeBoardFrame;
begin
  Client := TAtlasIdeWelcomePage.Client(TAtlasWelcomeIds.PluginId(AId));
  if Client <> nil then
    Client.UpdateContent;
  Client := TAtlasIdeWelcomePage.Client(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Board));
  if Client is TAtlasWelcomeBoardFrame then
    TAtlasWelcomeBoardFrame(Client).UpdateSection(AId);
  Board := TAtlasIdeWelcomeWindow.ExistingBoard;
  if Board <> nil then
    Board.UpdateSection(AId);
end;

procedure TAtlasIdeWelcome.UpdateHeaders;
var
  Client: TAtlasWelcomeFrame;
  Board: TAtlasWelcomeBoardFrame;
begin
  Client := TAtlasIdeWelcomePage.Client(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Header));
  if Client is TAtlasWelcomeHeaderFrame then
    FillHeader(TAtlasWelcomeHeaderFrame(Client));
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
      Key := TAtlasRegKey.Create('WelcomePage');
    // Ohne Raster in der Registry zeigt die IDE ihre Vorgabe; von der gehen wir aus.
    if not TAtlasHostLayout.Read(Key, Layout) then
      Layout := TAtlasHostLayout.IdeDefault;
    Result := not Layout.HasAtlasOnTop(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Board),
      TAtlasWelcomeIds.PluginPrefix);
    if not Result then
      Exit;
    Placed := Layout.WithAtlasOnTop(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Board), TAtlasWelcomeIds.PluginPrefix);
    Placed.WriteTo(Key);
    FAccess.Replace(WelcomeKey, Key);
  finally
    Key.Free;
  end;
end;

procedure TAtlasIdeWelcome.CheckPending;
begin
  // Die Marke enthält den gewünschten Stand: "atlas" oder die Sicherung, die gelten soll. Hat die IDE das
  // Layout beim Beenden aus dem Speicher zurückgeschrieben, wird der Stand hier wiederholt; gilt er beim
  // Start schon, hat die IDE ihn übernommen und die Marke entfällt.
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Wanted: string;
    begin
      if not FileExists(PendingFile) then
        Exit;
      Wanted := Trim(ReadText(PendingFile));
      if Wanted = 'atlas' then
      begin
        if not SameText(Settings.WelcomePageLayout, 'atlas') then
          System.SysUtils.DeleteFile(PendingFile)
        else if BoardPlaced then
          System.SysUtils.DeleteFile(PendingFile)
        else
          PlaceBoard;
      end
      else if TAtlasWelcomeBackup.Matches(FAccess, Wanted) then
        System.SysUtils.DeleteFile(PendingFile)
      else if not TAtlasWelcomeBackup.Restore(FAccess, Wanted) then
        System.SysUtils.DeleteFile(PendingFile);
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

procedure TAtlasIdeWelcome.ShowStart;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      FillBoard(TAtlasIdeWelcomeWindow.Show, 1);
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
      if FShownHost = 'dockWindow' then
        ShowStart;
    end);
end;

function TAtlasIdeWelcome.Place(AReport: Boolean): Boolean;
var
  Backup: string;
begin
  Result := False;
  if not TAtlasIdeWelcomePage.Available then
    Exit;
  Backup := TAtlasWelcomeBackup.BackupFile(AtlasFolder);
  // Nur die erste Sicherung zählt: Sie hält das Layout vor Atlas.
  if not FileExists(Backup) then
    try
      ForceDirectories(AtlasFolder);
      TFile.WriteAllText(Backup, TAtlasWelcomeBackup.Snapshot(FAccess, WelcomeKey), TEncoding.UTF8);
    except
      on E: Exception do
      begin
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeBackupFailed, [E.Message]));
        Exit;
      end;
    end;
  PlaceBoard;
  TFile.WriteAllText(PendingFile, 'atlas', TEncoding.UTF8);
  Result := True;
  if AReport then
    Report(TAtlasStrings.Text(TAtlasTextId.WelcomeApplied));
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
      Report(TAtlasStrings.Text(TAtlasTextId.WelcomeNoBackup));
    Exit;
  end;
  // Bis die IDE den Stand übernommen hat, gilt die Sicherung als gewünschter Stand (CheckPending).
  TFile.WriteAllText(PendingFile, Snapshot, TEncoding.UTF8);
  System.SysUtils.DeleteFile(Backup);
  if AReport then
    Report(TAtlasStrings.Text(TAtlasTextId.WelcomeResetDone));
end;

procedure TAtlasIdeWelcome.ApplyLayout;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if not Place(True) then
        Exit;
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
        Exit;
      FLastLayout := 'off';
      SetLayout('off');
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
