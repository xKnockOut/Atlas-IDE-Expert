unit Atlas.IDE.Commands.MainMenu;

// Hauptmenü „Atlas“ hinter „Tools“ (#227): Schnellschalter für die häufigsten
// Funktionen, darunter die Projekt-Einstellungen (atlas.json) und „Optionen…“,
// das die Seite Atlas unter Tools > Optionen öffnet. Die Schalter ändern die
// Plugin-Einstellungen wie die Optionsseite (Speichern, Strukturhervorhebung
// und Help Insight der IDE abgleichen); ihre Häkchen werden beim Öffnen des
// Menüs aus den aktuellen Einstellungen gesetzt. Seit #604 gehen sie über die
// Schnellschalter: gleicher Zustand wie im Fenster (Sitzung, Projekt) und bei
// Werten aus atlas.json dieselbe Nachfrage.
// Index des Servers (#492): Der Titel zeigt eine laufende Indizierung
// ("Atlas – Index 45 %"), wenn IndexProgressPlace sie nicht ins Statusfeld legt; „Index-Status“ schreibt die Kennzahlen in die
// Meldungsansicht, „Index neu aufbauen“ liest alles ohne Cache neu ein.
// „Diagnoselog exportieren…“ (#647) packt das anonymisierte Log in eine ZIP.
// „Prozesse am Projekt…“ (#62) zeigt Index-Cache, Sperre und die LSP- und
// MCP-Prozesse am Projekt; sichtbar nach diagnostics.processes. „Atlas-Server:
// Speicher und Laufzeiten“ (#1356) sichtbar nach server.statusWindow.
// „Symbol umbenennen…“ (#397) ruft OnRename auf.
// „Einrichtung prüfen…“ (#625) ruft OnSetup auf.
// „Tastenkürzel-Übersicht…“ (#520) ruft OnKeyMap auf; sichtbar nach
// keys.overview (UpdateKeyMap).
// Referenzen, Implementierungen, Symbolsuche und Hierarchien öffnen das
// Ergebnisfenster (#400).
// Code-Aktionen, Auswahl erweitern/verkleinern, Typdefinition und
// qualifizierter Name (#399) gehen an TAtlasIdeEditorCommands.
// Letzte Atlas-Änderung zurücknehmen bzw. wiederherstellen und die Liste
// „Atlas-Änderungen“ (#721) gehen an TAtlasIdeUndo.
// Einträge der Module (#1455, etwa Notizen und Lesezeichen) baut
// TAtlasMenuModuleItems (Atlas.IDE.Commands.MenuModules) bei jedem Öffnen aus
// IAtlasMenuSource; Untermenüs nach Section, Trennlinien aus „-“, ein Untermenü
// ohne sichtbaren Eintrag fehlt. Einträge der Module unter Ansicht › Atlas
// (TAtlasMenuPlace.ViewMenu, etwa „Atlas-Abfrage“ der Suche) baut es beim Öffnen
// dort. Was die übrigen Einträge ausführen, steht in TAtlasMenuActions
// (Atlas.IDE.Commands.MenuActions).
// „Gliederung …“ (#537)
// öffnet TAtlasIdeOutline; sichtbar nur bei outline.enabled.
// Das Atlas-Symbol (#751) steht am Menü und an den Einträgen für Einstellungen
// und Optionen; UpdateImage wählt nach einem Themenwechsel die passende Variante.
// Die Einträge der Willkommensseite (#753, „Atlas-Start“ auch unter Ansicht ›
// Atlas) stellt das Modul atlas.welcome über IAtlasMenuSource (#1455).
// Befehle mit einer Kennung der Befehlspalette melden sich bei den
// Tastenkürzel-Tipps (#600) als Aufruf per Menü (TAtlasIdeShortcutTips.Invoked).
// „Atlas-Prüfung“ (#909) öffnet das Fenster der Befunde, auch unter Ansicht ›
// Atlas › Prüfung; sichtbar nur bei problems.window.
// „Architekturübersicht“ (#1118) öffnet das Fenster „Atlas-Architektur“, auch
// unter Ansicht › Atlas › Architektur; sichtbar nur bei architecture.enabled.
// Unter Navigation die Abschnittssprünge, der Rücksprung und „Methode suchen“
// der Editorleiste (#1101); sie arbeiten auch ohne die Leiste.
// Einträge der Module (#1455): Jedes Modul nennt sie über IAtlasMenuSource
// (Befehl oder eigener Eintrag, Untermenü; etwa „Compiler-Schalter“ und das
// Untermenü „Aufgaben“ des Moduls Build); RootClick baut sie bei jedem Öffnen neu auf, so
// kommen und gehen sie mit ihrem Modul.
// Aufbau: häufige Befehle direkt, der Rest in Untermenüs (Navigation, Suchen,
// Kopieren, Änderungen, Anzeige mit den Schaltern, Index, Hilfe und Diagnose).

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Vcl.Menus,
  Vcl.ExtCtrls,
  Atlas.UI.Strings,
  Atlas.IDE.Commands.MenuModules;

type
{$SCOPEDENUMS ON}
  TAtlasToggle = (Enabled, HoverTooltip, PairColors, PairGuides, PairOwners, Problems, InactiveDim, InlayHints);
{$SCOPEDENUMS OFF}

  /// <summary>Aufbau des Atlas-Menüs: die Einträge, deren Sichtbarkeit von Einstellungen abhängt, und die Rückrufe
  /// der Komposition. Die Klicks behandelt TAtlasMainMenu.</summary>
  TAtlasMainMenuItems = class
  private
    FRoot: TMenuItem;
    /// <summary>Ziel von AddItem: das Atlas-Menü oder das zuletzt angelegte Untermenü.</summary>
    FParent: TMenuItem;
    FToggles: array[TAtlasToggle] of TMenuItem;
    FEnableAll: TMenuItem;
    FImageItems: TArray<TMenuItem>;
    FOnRename: TProc;
    FOnBugReport: TProc;
    FOnSetup: TProc;
    FOnKeyMap: TProc;
    FOnServerStatus: TProc;
    FKeyMapItem: TMenuItem;
    /// <summary>„Prozesse am Projekt…“ (#62), sichtbar nach diagnostics.processes.</summary>
    FProcessesItem: TMenuItem;
    /// <summary>„Atlas-Server: Speicher und Laufzeiten“ (#1356), sichtbar nach server.statusWindow.</summary>
    FServerStatusItem: TMenuItem;
    FCallDiagramItem: TMenuItem;
    /// <summary>„Erzeugen…“ (#719), sichtbar nach keys.generateMenu.</summary>
    FGenerateItem: TMenuItem;
    /// <summary>„Formatieren“ (#43), nur mit editor.format.</summary>
    FFormatItem: TMenuItem;
    /// <summary>„implementation wie Klasse ordnen“ (#660), nur mit editor.methodPlacement.</summary>
    FMethodOrderItem: TMenuItem;
    /// <summary>„Gliederung …“ (#537), sichtbar nach outline.enabled.</summary>
    FOutlineItem: TMenuItem;
    /// <summary>„Atlas-Prüfung“ (#909) im Atlas-Menü und unter Ansicht › Atlas.</summary>
    FProblemsItem: TMenuItem;
    /// <summary>Einträge der Module (#1455, IAtlasMenuSource) im Atlas-Menü und unter Ansicht › Atlas.</summary>
    FModules: TAtlasMenuModuleItems;
    /// <summary>„Woher/Wohin kommt der Wert?“ (#690), sichtbar nach navigation.dataFlow.</summary>
    FDataFlowItems: TArray<TMenuItem>;
    /// <summary>Ansicht › Atlas mit „Prüfung“ (#909) und den Einträgen der Module.</summary>
    FViewAtlas: TMenuItem;
    FViewProblems: TMenuItem;
    /// <summary>„Auswirkungen anzeigen“ (#1120), sichtbar nach navigation.impact.</summary>
    FImpactItem: TMenuItem;
  protected
    function AddItem(AText: TAtlasTextId; ATag: Integer; AOnClick: TNotifyEvent): TMenuItem; overload;
    function AddItem(const ACaption: string; ATag: Integer; AOnClick: TNotifyEvent): TMenuItem; overload;
    /// <summary>Untermenü im Atlas-Menü; folgende AddItem landen darin.</summary>
    function AddGroup(AText: TAtlasTextId): TMenuItem;
  public
    /// <summary>„Symbol umbenennen…“ (#397).</summary>
    property OnRename: TProc read FOnRename write FOnRename;
    /// <summary>„Fehlerbericht erstellen…“ (#108).</summary>
    property OnBugReport: TProc read FOnBugReport write FOnBugReport;
    /// <summary>Fenster „Atlas-Server“ (#1356).</summary>
    property OnServerStatus: TProc read FOnServerStatus write FOnServerStatus;
    /// <summary>„Einrichtung prüfen…“ (#625).</summary>
    property OnSetup: TProc read FOnSetup write FOnSetup;
    /// <summary>„Tastenkürzel-Übersicht…“ (#520).</summary>
    property OnKeyMap: TProc read FOnKeyMap write FOnKeyMap;
    /// <summary>Eintrag „Tastenkürzel-Übersicht…“ nach keys.overview ein- oder ausblenden.</summary>
    procedure UpdateKeyMap;
    /// <summary>Atlas-Symbol (#751) für das aktive Thema an Menü und Einstellungseinträgen.</summary>
    procedure UpdateImage;
  end;

  TAtlasMainMenu = class(TAtlasMainMenuItems)
  private
    FTimer: TTimer;
    FProgress: TFunc<string>;
    FCommand: TProc<string, TProc<TJSONValue>>;
    FMessage: TProc<string>;
    FShownProgress: string;
    /// <summary>Häufige Befehle direkt im Atlas-Menü.</summary>
    procedure AddTopItems;
    procedure AddNavigationGroup;
    /// <summary>Untermenüs Suchen, Kopieren und Änderungen.</summary>
    procedure AddSearchGroups;
    /// <summary>Untermenüs Anzeige (Schalter), Index sowie Hilfe und Diagnose.</summary>
    procedure AddSettingsGroups;
    /// <summary>Projekt-Einstellungen, Optionen und „Alles wieder einschalten“ am Ende des Menüs.</summary>
    procedure AddSettingsItems;
    /// <summary>Atlas-Menü hinter „Tools“ einhängen, Ansicht › Atlas unter „Ansicht“.</summary>
    procedure InsertIntoIde(AMainMenu: TMainMenu);
    procedure RenameClick(Sender: TObject);
    procedure ResultsClick(Sender: TObject);
    procedure EditorClick(Sender: TObject);
    procedure SectionClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure OutlineClick(Sender: TObject);
    procedure ProblemsClick(Sender: TObject);
    procedure ViewAtlasClick(Sender: TObject);
    procedure EnableAllClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure IndexStatusClick(Sender: TObject);
    procedure IndexRebuildClick(Sender: TObject);
    procedure DiagnosticExportClick(Sender: TObject);
    procedure ProcessesClick(Sender: TObject);
    procedure BugReportClick(Sender: TObject);
    procedure ServerStatusClick(Sender: TObject);
    procedure SetupClick(Sender: TObject);
    procedure KeyMapClick(Sender: TObject);
    procedure RootClick(Sender: TObject);
    procedure ToggleClick(Sender: TObject);
    procedure ProjectClick(Sender: TObject);
    procedure OptionsClick(Sender: TObject);
  public
    /// <summary>AProgress: Fortschritt des Servers; ACommand: Serverbefehl im Hintergrund ausführen, das Ergebnis
    /// (nil ohne Server oder bei Fehler) kommt im Hauptthread (#874); AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(const AProgress: TFunc<string>; const ACommand: TProc<string, TProc<TJSONValue>>;
      const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Name der Einstellung eines Schalters (Schlüssel im Katalog der Schnellschalter, #604).</summary>
    class function ToggleKey(AToggle: TAtlasToggle): string; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  ToolsAPI,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Settings.QuickToggles,
  Atlas.IDE.Diagnostics.Export,
  Atlas.IDE.Results.Impact,
  Atlas.IDE.Outline.Service,
  Atlas.IDE.Problems.Service,
  Atlas.IDE.Editor.MethodPlacement,
  Atlas.IDE.Commands.KeyMap,
  Atlas.IDE.Commands.ShortcutTips,
  Atlas.IDE.Commands.MenuActions,
  Atlas.IDE.Foundation.Symbol,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Setup.Checklist,
  Atlas.Core.Lsp.Progress;

const
  // Name des Menüs „Tools“ in der IDE; Atlas steht dahinter, sonst am Ende.
  ToolsMenu = 'ToolsMenu';
  // Menü „Ansicht“ der IDE; dort steht das Untermenü „Atlas“ (#909, #1455).
  ViewsMenu = 'ViewsMenu';
  ToggleTexts: array[TAtlasToggle] of TAtlasTextId = (TAtlasTextId.MenuToggleEnabled, TAtlasTextId.MenuToggleHover,
    TAtlasTextId.MenuTogglePairs, TAtlasTextId.MenuToggleGuides, TAtlasTextId.MenuToggleOwners,
    TAtlasTextId.MenuToggleProblems, TAtlasTextId.MenuToggleInactive, TAtlasTextId.MenuToggleInlayHints);
  ToggleKeys: array[TAtlasToggle] of string = ('Enabled', 'HoverTooltip', 'PairColors', 'PairGuides', 'PairOwners',
    'Problems', 'InactiveDim', 'InlayHints');

/// <summary>Namen der von der Sicherung abgeschalteten Funktionen und Quellen (#493), mit Komma getrennt.</summary>
function DisabledNames: string;
var
  mFeature: TAtlasFeature;
  mName: string;
  mNames: TArray<string>;
begin
  mNames := nil;
  for mFeature in TAtlasGuard.DisabledSet do
  begin
    mNames := mNames + [TAtlasGuard.FeatureName(mFeature)];
  end;
  // Auch einzeln abgeschaltete Quellen (#493).
  for mName in TAtlasGuard.DisabledProviders do
  begin
    mNames := mNames + [mName];
  end;
  Result := string.Join(', ', mNames);
end;

{ TAtlasMainMenuItems }

procedure TAtlasMainMenuItems.UpdateImage;
var
  Item: TMenuItem;
  Image: Integer;
begin
  Image := TAtlasIdeSymbol.MenuImage;
  for Item in FImageItems do
  begin
    Item.ImageIndex := Image;
  end;
end;

procedure TAtlasMainMenuItems.UpdateKeyMap;
var
  Item: TMenuItem;
begin
  if FKeyMapItem <> nil then
  begin
    FKeyMapItem.Visible := TAtlasIdeSettings.Current.KeyOverview;
  end;
  // Prozesse am Projekt (#62) nach diagnostics.processes.
  if FProcessesItem <> nil then
  begin
    FProcessesItem.Visible := TAtlasIdeSettings.Current.DiagnosticsProcesses;
  end;
  // Fenster „Atlas-Server“ (#1356) nach server.statusWindow.
  if FServerStatusItem <> nil then
  begin
    FServerStatusItem.Visible := TAtlasIdeSettings.Current.ServerStatusWindow and Assigned(FOnServerStatus);
  end;
  // Aufrufdiagramm (#1122) nach callHierarchy.diagram.
  if FCallDiagramItem <> nil then
  begin
    FCallDiagramItem.Visible := TAtlasIdeSettings.Current.CallHierarchyDiagram;
  end;
  // Erzeugen-Menü (#719) nach keys.generateMenu.
  if FGenerateItem <> nil then
  begin
    FGenerateItem.Visible := TAtlasIdeSettings.Current.GenerateMenu;
  end;
  // Formatieren (#43) nach editor.format.
  if FFormatItem <> nil then
  begin
    FFormatItem.Visible := TAtlasIdeSettings.Current.FormatCode;
  end;
  // Methodenreihenfolge (#660) nach editor.methodPlacement.
  if FMethodOrderItem <> nil then
  begin
    FMethodOrderItem.Visible := TAtlasIdeMethodPlacement.Enabled;
  end;
  // Gliederung (#537) nach outline.enabled.
  if FOutlineItem <> nil then
  begin
    FOutlineItem.Visible := TAtlasIdeSettings.Current.Outline;
  end;
  // Atlas-Prüfung (#909) nach problems.window.
  if FProblemsItem <> nil then
  begin
    FProblemsItem.Visible := TAtlasIdeProblems.Enabled;
  end;
  if FViewProblems <> nil then
  begin
    FViewProblems.Visible := TAtlasIdeProblems.Enabled;
  end;
  if FViewAtlas <> nil then
  begin
    FViewAtlas.Visible := TAtlasIdeProblems.Enabled or TAtlasMenuModuleItems.HasViewItems;
  end;
  // Auswirkungen anzeigen (#1120) nach navigation.impact.
  if FImpactItem <> nil then
  begin
    FImpactItem.Visible := TAtlasIdeImpact.Enabled;
  end;
  // Datenfluss (#690) nach navigation.dataFlow.
  for Item in FDataFlowItems do
  begin
    Item.Visible := TAtlasIdeSettings.Current.DataFlow;
  end;
end;

function TAtlasMainMenuItems.AddItem(AText: TAtlasTextId; ATag: Integer; AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := AddItem(TAtlasStrings.Text(AText), ATag, AOnClick);
end;

function TAtlasMainMenuItems.AddItem(const ACaption: string; ATag: Integer; AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FRoot);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := AOnClick;
  FParent.Add(Result);
end;

function TAtlasMainMenuItems.AddGroup(AText: TAtlasTextId): TMenuItem;
begin
  Result := TMenuItem.Create(FRoot);
  Result.Caption := TAtlasStrings.Text(AText);
  FRoot.Add(Result);
  FParent := Result;
end;

{ TAtlasMainMenu }

constructor TAtlasMainMenu.Create(const AProgress: TFunc<string>; const ACommand: TProc<string, TProc<TJSONValue>>;
  const AMessage: TProc<string>);
var
  Services: INTAServices;
begin
  inherited Create;
  FProgress := AProgress;
  FCommand := ACommand;
  FMessage := AMessage;
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.MainMenu = nil) then
  begin
    Exit;
  end;
  FRoot := TMenuItem.Create(nil);
  FRoot.Name := 'AtlasMainMenu';
  FRoot.Caption := TAtlasStrings.Text(TAtlasTextId.MenuAtlas);
  FRoot.OnClick := RootClick;
  // Häufige Befehle direkt, der Rest in Untermenüs (sonst scrollt das Menü).
  FParent := FRoot;
  AddTopItems;
  AddNavigationGroup;
  AddSearchGroups;
  AddSettingsGroups;
  AddSettingsItems;
  InsertIntoIde(Services.MainMenu);
  UpdateKeyMap;
  UpdateImage;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 500;
  FTimer.OnTimer := TimerTick;
end;

procedure TAtlasMainMenu.AddTopItems;
var
  mAnchor: TMenuItem;
begin
  AddItem(TAtlasTextId.RenameMenu, 0, RenameClick);
  // Editorbefehle (#399) und Ergebnisfenster (#400); Tag wählt den Befehl in EditorClick bzw. ResultsClick.
  AddItem(TAtlasTextId.EditorActions, 0, EditorClick);
  // Erzeugen-Menü (#719).
  FGenerateItem := AddItem(TAtlasTextId.GenerateMenuCommand, 10, EditorClick);
  // Formatieren (#43).
  FFormatItem := AddItem(TAtlasTextId.FormatCodeCommand, 11, EditorClick);
  // Methodenrümpfe wie die Klasse ordnen (#660).
  FMethodOrderItem := AddItem(TAtlasTextId.MethodOrderCommand, 12, EditorClick);
  AddItem(TAtlasTextId.MenuSymbolSearch, 2, ResultsClick);
  FProblemsItem := AddItem(TAtlasTextId.ProblemsWindowCaption, 0, ProblemsClick);
  // Einträge der Module (#1455), z. B. Architektur und Hotspots der Analyse, Exception-Verlauf und „Auswerten“ des
  // Debuggers.
  mAnchor := AddItem('', 0, nil);
  mAnchor.Visible := False;
  FModules := TAtlasMenuModuleItems.Create(FRoot, mAnchor);
  FRoot.Add(NewLine);
end;

procedure TAtlasMainMenu.AddNavigationGroup;
begin
  AddGroup(TAtlasTextId.MenuGroupNavigation);
  AddItem(TAtlasTextId.EditorTypeDefinition, 3, EditorClick);
  AddItem(TAtlasTextId.EditorMethodToggle, 6, EditorClick);
  AddItem(TAtlasTextId.EditorTestUnit, 7, EditorClick);
  AddItem(TAtlasTextId.GotoInterfaceCommand, 0, SectionClick);
  AddItem(TAtlasTextId.GotoImplementationCommand, 1, SectionClick);
  AddItem(TAtlasTextId.GotoUsesCommand, 2, SectionClick);
  AddItem(TAtlasTextId.GotoInitializationCommand, 3, SectionClick);
  AddItem(TAtlasTextId.ReturnFromSectionCommand, 4, SectionClick);
  AddItem(TAtlasTextId.FindMethodCommand, 5, SectionClick);
  AddItem(TAtlasTextId.EditorExpand, 1, EditorClick);
  AddItem(TAtlasTextId.EditorShrink, 2, EditorClick);
  FOutlineItem := AddItem(TAtlasTextId.OutlineCommand, 0, OutlineClick);
end;

procedure TAtlasMainMenu.AddSearchGroups;
begin
  AddGroup(TAtlasTextId.MenuGroupSearch);
  AddItem(TAtlasTextId.MenuReferences, 0, ResultsClick);
  AddItem(TAtlasTextId.MenuImplementations, 1, ResultsClick);
  AddItem(TAtlasTextId.MenuIncoming, 3, ResultsClick);
  AddItem(TAtlasTextId.MenuOutgoing, 4, ResultsClick);
  // Aufrufdiagramm (#1122) nach callHierarchy.diagram.
  FCallDiagramItem := AddItem(TAtlasTextId.CallDiagramCommand, 8, ResultsClick);
  AddItem(TAtlasTextId.MenuSupertypes, 5, ResultsClick);
  AddItem(TAtlasTextId.MenuSubtypes, 6, ResultsClick);
  FImpactItem := AddItem(TAtlasTextId.ImpactCommand, 9, ResultsClick);
  // Datenfluss (#690).
  FDataFlowItems := [AddItem(TAtlasTextId.MenuDataFlowSources, 10, ResultsClick),
    AddItem(TAtlasTextId.MenuDataFlowTargets, 11, ResultsClick)];
  FParent.Add(NewLine);
  AddItem(TAtlasTextId.MenuResultsWindow, 7, ResultsClick);
  AddGroup(TAtlasTextId.MenuGroupCopy);
  AddItem(TAtlasTextId.EditorCopyQualified, 4, EditorClick);
  AddItem(TAtlasTextId.EditorCopyQualifiedParams, 5, EditorClick);
  // Atlas-Änderungen über mehrere Dateien (#721); Tag wählt den Befehl in UndoClick.
  AddGroup(TAtlasTextId.MenuGroupChanges);
  AddItem(TAtlasTextId.UndoMenu, 0, UndoClick);
  AddItem(TAtlasTextId.RedoMenu, 1, UndoClick);
  AddItem(TAtlasTextId.UndoListMenu, 2, UndoClick);
end;

procedure TAtlasMainMenu.AddSettingsGroups;
var
  mToggle: TAtlasToggle;
begin
  // Schalter; Tag wählt den Befehl in ToggleClick.
  AddGroup(TAtlasTextId.MenuGroupView);
  for mToggle := Low(TAtlasToggle) to High(TAtlasToggle) do
  begin
    FToggles[mToggle] := AddItem(ToggleTexts[mToggle], Ord(mToggle), ToggleClick);
  end;
  AddGroup(TAtlasTextId.MenuGroupIndex);
  AddItem(TAtlasTextId.MenuIndexStatus, 0, IndexStatusClick);
  AddItem(TAtlasTextId.MenuIndexRebuild, 0, IndexRebuildClick);
  AddGroup(TAtlasTextId.MenuGroupHelp);
  FKeyMapItem := AddItem(TAtlasTextId.KeyMapMenu, 0, KeyMapClick);
  AddItem(TAtlasTextId.SetupMenu, 0, SetupClick);
  AddItem(TAtlasTextId.DiagExportMenu, 0, DiagnosticExportClick);
  FProcessesItem := AddItem(TAtlasTextId.ProcessesMenu, 0, ProcessesClick);
  FServerStatusItem := AddItem(TAtlasTextId.ServerWindowCommand, 0, ServerStatusClick);
  AddItem(TAtlasTextId.BugReportMenu, 0, BugReportClick);
end;

procedure TAtlasMainMenu.AddSettingsItems;
var
  mItem: TMenuItem;
begin
  FRoot.Add(NewLine);
  mItem := TMenuItem.Create(FRoot);
  mItem.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsMenu);
  mItem.OnClick := ProjectClick;
  FRoot.Add(mItem);
  FImageItems := [FRoot, mItem];
  // Globale Einstellungen stehen nur unter Tools › Optionen › Atlas, kein eigener Menüpunkt mehr.
  mItem := TMenuItem.Create(FRoot);
  mItem.Caption := TAtlasStrings.Text(TAtlasTextId.MenuOptions);
  mItem.OnClick := OptionsClick;
  FRoot.Add(mItem);
  FImageItems := FImageItems + [mItem];
  // Nur sichtbar, wenn die Sicherung etwas abgeschaltet hat (#493).
  FEnableAll := TMenuItem.Create(FRoot);
  FEnableAll.OnClick := EnableAllClick;
  FEnableAll.Visible := False;
  FRoot.Add(FEnableAll);
end;

procedure TAtlasMainMenu.InsertIntoIde(AMainMenu: TMainMenu);
var
  mIndex, mPosition: Integer;
begin
  mPosition := AMainMenu.Items.Count;
  for mIndex := 0 to AMainMenu.Items.Count - 1 do
  begin
    if SameText(AMainMenu.Items[mIndex].Name, ToolsMenu) then
    begin
      mPosition := mIndex + 1;
    end;
  end;
  AMainMenu.Items.Insert(mPosition, FRoot);
  for mIndex := 0 to AMainMenu.Items.Count - 1 do
  begin
    if SameText(AMainMenu.Items[mIndex].Name, ViewsMenu) then
    begin
      // Gehört dem Atlas-Menü, damit es mit ihm freigegeben wird; Freigeben nimmt es aus „Ansicht“.
      // Ansicht › Atlas › Prüfung (#909) und Architektur (#1118).
      FViewAtlas := TMenuItem.Create(FRoot);
      FViewAtlas.Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsViewMenuAtlas);
      FViewProblems := TMenuItem.Create(FViewAtlas);
      FViewProblems.Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsViewMenuWindow);
      FViewProblems.OnClick := ProblemsClick;
      FViewAtlas.Add(FViewProblems);
      // Einträge der Module (#1455) kommen beim Öffnen dazu.
      FViewAtlas.OnClick := ViewAtlasClick;
      FModules.ViewAtlas := FViewAtlas;
      AMainMenu.Items[mIndex].Add(FViewAtlas);
      Break;
    end;
  end;
end;

destructor TAtlasMainMenu.Destroy;
begin
  FreeAndNil(FTimer);
  FImageItems := nil;
  FreeAndNil(FModules);
  // Freigeben nimmt den Eintrag auch aus dem Hauptmenü.
  FreeAndNil(FRoot);
  inherited;
end;

class function TAtlasMainMenu.ToggleKey(AToggle: TAtlasToggle): string;
begin
  Result := ToggleKeys[AToggle];
end;

procedure TAtlasMainMenu.RootClick(Sender: TObject);
var
  Toggle: TAtlasToggle;
  Names: string;
begin
  try
    // Falls der Themenwechsel nicht gemeldet wurde.
    UpdateImage;
    UpdateKeyMap;
    FModules.Update;
    for Toggle := Low(TAtlasToggle) to High(TAtlasToggle) do
    begin
      FToggles[Toggle].Checked := TAtlasIdeQuickToggles.Checked(ToggleKey(Toggle));
    end;
    // Anweisungen mitfärben wirkt nur mit der Paarfärbung (#653).
    FToggles[TAtlasToggle.PairOwners].Enabled := TAtlasIdeQuickToggles.Checked('PairColors');
    Names := DisabledNames;
    FEnableAll.Visible := Names <> '';
    FEnableAll.Caption := TAtlasStrings.Fmt(TAtlasTextId.MenuEnableAll, [Names]);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Menu, E);
  end;
end;

procedure TAtlasMainMenu.ToggleClick(Sender: TObject);
var
  Toggle: TAtlasToggle;
begin
  try
    Toggle := TAtlasToggle(TMenuItem(Sender).Tag);
    // Speichert wie die Optionsseite, gleicht die Strukturhervorhebung ab und zeichnet neu (#604).
    TAtlasIdeQuickToggles.Switch(ToggleKey(Toggle));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Menu, E);
  end;
end;

procedure TAtlasMainMenu.TimerTick(Sender: TObject);
var
  Text: string;
begin
  TAtlasGuard.Run(TAtlasFeature.Menu,
    procedure
    begin
      Text := '';
      if Assigned(FProgress) then
      begin
        Text := FProgress();
      end;
      if Text = FShownProgress then
      begin
        Exit;
      end;
      FShownProgress := Text;
      // Nur bei Änderung: Der Titel im Hauptmenü zeichnet die ganze Leiste neu.
      if Text = '' then
      begin
        FRoot.Caption := TAtlasStrings.Text(TAtlasTextId.MenuAtlas);
      end
      else
      begin
        FRoot.Caption := TAtlasStrings.Text(TAtlasTextId.MenuAtlas) + ' – ' + Text;
      end;
    end);
end;

procedure TAtlasMainMenu.IndexStatusClick(Sender: TObject);
begin
  // Im Hintergrund: Ein Server, der gerade indexiert, antwortet erst danach (#874).
  TAtlasGuard.Run(TAtlasFeature.Server,
    procedure
    begin
      if not Assigned(FCommand) then
      begin
        Exit;
      end;
      FCommand('atlas.server.status',
        procedure(AStatus: TJSONValue)
        var
          Line: string;
        begin
          if AStatus = nil then
          begin
            FMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
          end
          else
          begin
            for Line in TLspIndexStatus.Lines(AStatus) do
            begin
              FMessage(Line);
            end;
          end;
        end);
    end);
end;

procedure TAtlasMainMenu.IndexRebuildClick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Server,
    procedure
    begin
      if not Assigned(FCommand) then
      begin
        Exit;
      end;
      FCommand('atlas.server.rebuildIndex',
        procedure(AAnswer: TJSONValue)
        begin
          if AAnswer = nil then
          begin
            FMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
          end
          else
          begin
            FMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexRebuilding));
          end;
        end);
    end);
end;

procedure TAtlasMainMenu.DiagnosticExportClick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Menu,
    procedure
    begin
      TAtlasIdeDiagnosticExport.Execute(FMessage);
    end);
end;

procedure TAtlasMainMenu.ProcessesClick(Sender: TObject);
begin
  TAtlasMenuActions.ShowProcesses(FCommand);
end;

procedure TAtlasMainMenu.BugReportClick(Sender: TObject);
begin
  TAtlasIdeShortcutTips.Invoked('Atlas.BugReport');
  if Assigned(FOnBugReport) then
  begin
    TAtlasGuard.Run(TAtlasFeature.Menu,
      procedure
      begin
        FOnBugReport();
      end);
  end;
end;

procedure TAtlasMainMenu.ServerStatusClick(Sender: TObject);
begin
  if not Assigned(FOnServerStatus) then
  begin
    Exit;
  end;
  TAtlasIdeShortcutTips.Invoked('Atlas.ServerStatus');
  TAtlasGuard.Run(TAtlasFeature.Menu,
    procedure
    begin
      FOnServerStatus();
    end);
end;

procedure TAtlasMainMenu.SetupClick(Sender: TObject);
begin
  TAtlasIdeShortcutTips.Invoked(TAtlasSetupChecklist.CommandId);
  if Assigned(FOnSetup) then
  begin
    TAtlasGuard.Run(TAtlasFeature.Menu,
      procedure
      begin
        FOnSetup();
      end);
  end;
end;

procedure TAtlasMainMenu.KeyMapClick(Sender: TObject);
begin
  TAtlasIdeShortcutTips.Invoked(TAtlasIdeKeyMap.CommandId);
  if Assigned(FOnKeyMap) then
  begin
    TAtlasGuard.Run(TAtlasFeature.Menu,
      procedure
      begin
        FOnKeyMap();
      end);
  end;
end;

procedure TAtlasMainMenu.RenameClick(Sender: TObject);
begin
  TAtlasIdeShortcutTips.Invoked('Atlas.Rename');
  if Assigned(FOnRename) then
  begin
    TAtlasGuard.Run(TAtlasFeature.Menu,
      procedure
      begin
        FOnRename();
      end);
  end;
end;

procedure TAtlasMainMenu.ResultsClick(Sender: TObject);
begin
  TAtlasMenuActions.RunResults(TMenuItem(Sender).Tag);
end;

procedure TAtlasMainMenu.EditorClick(Sender: TObject);
begin
  TAtlasMenuActions.RunEditor(TMenuItem(Sender).Tag);
end;

procedure TAtlasMainMenu.SectionClick(Sender: TObject);
begin
  TAtlasMenuActions.RunSection(TMenuItem(Sender).Tag);
end;

procedure TAtlasMainMenu.UndoClick(Sender: TObject);
begin
  TAtlasMenuActions.RunUndo(TMenuItem(Sender).Tag);
end;

procedure TAtlasMainMenu.ProblemsClick(Sender: TObject);
begin
  TAtlasIdeShortcutTips.Invoked('Atlas.ProblemsWindow');
  TAtlasGuard.Run(TAtlasFeature.Problems,
    procedure
    begin
      TAtlasIdeProblems.ShowWindow;
    end);
end;

procedure TAtlasMainMenu.ViewAtlasClick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Menu,
    procedure
    begin
      FModules.UpdateView;
    end);
end;

procedure TAtlasMainMenu.OutlineClick(Sender: TObject);
begin
  TAtlasIdeShortcutTips.Invoked('Atlas.Outline');
  TAtlasGuard.Run(TAtlasFeature.Outline,
    procedure
    begin
      TAtlasIdeOutline.ShowWindow;
    end);
end;

procedure TAtlasMainMenu.EnableAllClick(Sender: TObject);
begin
  TAtlasGuard.EnableAll;
end;

procedure TAtlasMainMenu.ProjectClick(Sender: TObject);
begin
  try
    TAtlasProjectSettings.Execute;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

procedure TAtlasMainMenu.OptionsClick(Sender: TObject);
var
  Options: IOTAEnvironmentOptions140;
  Services: IOTAServices;
begin
  try
    if Supports(BorlandIDEServices, IOTAServices, Services) and
      Supports(Services.GetEnvironmentOptions, IOTAEnvironmentOptions140, Options) then
    begin
      Options.EditOptions('', 'Atlas');
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

end.
