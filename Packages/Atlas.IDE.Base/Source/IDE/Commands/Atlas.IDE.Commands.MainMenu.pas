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
// UpdateModuleItems bei jedem Öffnen aus IAtlasMenuSource; Untermenüs nach
// Section, Trennlinien aus „-“, ein Untermenü ohne sichtbaren Eintrag fehlt.
// Einträge der Module unter Ansicht › Atlas (TAtlasMenuPlace.ViewMenu, etwa
// „Atlas-Abfrage“ der Suche) baut UpdateViewModuleItems beim Öffnen dort.
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
  Atlas.UI.Strings;

type
{$SCOPEDENUMS ON}
  TAtlasToggle = (Enabled, HoverTooltip, PairColors, PairGuides, PairOwners, Problems, InactiveDim, InlayHints);
{$SCOPEDENUMS OFF}

  TAtlasMainMenu = class
  private
    FRoot: TMenuItem;
    /// <summary>Ziel von AddItem: das Atlas-Menü oder das zuletzt angelegte Untermenü.</summary>
    FParent: TMenuItem;
    FToggles: array[TAtlasToggle] of TMenuItem;
    FEnableAll: TMenuItem;
    FImageItems: TArray<TMenuItem>;
    FTimer: TTimer;
    FProgress: TFunc<string>;
    FCommand: TProc<string, TProc<TJSONValue>>;
    FMessage: TProc<string>;
    FShownProgress: string;
    FOnRename: TProc;
    FOnBugReport: TProc;
    FOnSetup: TProc;
    FOnKeyMap: TProc;
    FKeyMapItem: TMenuItem;
    /// <summary>„Prozesse am Projekt…“ (#62), sichtbar nach diagnostics.processes.</summary>
    FProcessesItem: TMenuItem;
    /// <summary>„Atlas-Server: Speicher und Laufzeiten“ (#1356), sichtbar nach server.statusWindow.</summary>
    FServerStatusItem: TMenuItem;
    FOnServerStatus: TProc;
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
    /// <summary>Ab hier stehen die Einträge der Module (#1455, IAtlasMenuSource); unsichtbare Marke.</summary>
    FModuleAnchor: TMenuItem;
    /// <summary>Einträge und Untermenüs der Module; RootClick baut sie bei jedem Öffnen neu.</summary>
    FModuleItems: TArray<TMenuItem>;
    /// <summary>Befehls-Id je Eintrag (Index = Tag).</summary>
    FModuleIds: TArray<string>;
    /// <summary>„Woher/Wohin kommt der Wert?“ (#690), sichtbar nach navigation.dataFlow.</summary>
    FDataFlowItems: TArray<TMenuItem>;
    /// <summary>„Atlas: Compiler-Schalter“ (#558), sichtbar nach build.compilerSwitches.</summary>
    FViewAtlas: TMenuItem;
    FViewProblems: TMenuItem;
    /// <summary>Einträge der Module unter Ansicht › Atlas und ihre Befehls-Ids (Index = Tag).</summary>
    FViewModuleItems: TArray<TMenuItem>;
    FViewModuleIds: TArray<string>;
    /// <summary>„Auswirkungen anzeigen“ (#1120), sichtbar nach navigation.impact.</summary>
    FImpactItem: TMenuItem;
    /// <summary>Untermenü „Aufgaben“ (#900).</summary>
    procedure RenameClick(Sender: TObject);
    procedure ResultsClick(Sender: TObject);
    procedure EditorClick(Sender: TObject);
    procedure SectionClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure OutlineClick(Sender: TObject);
    procedure ProblemsClick(Sender: TObject);
    procedure ViewAtlasClick(Sender: TObject);
    procedure ViewModuleItemClick(Sender: TObject);
    /// <summary>Einträge der Module unter Ansicht › Atlas neu aufbauen.</summary>
    procedure UpdateViewModuleItems;
    /// <summary>Hat ein laufendes Modul einen sichtbaren Eintrag unter Ansicht › Atlas?</summary>
    class function HasViewModuleItems: Boolean; static;
    procedure ModuleItemClick(Sender: TObject);
    /// <summary>Einträge der Module nach der Marke neu aufbauen (Regel 2: sie kommen und gehen mit dem Modul).
    /// </summary>
    procedure UpdateModuleItems;
    /// <summary>Trennlinien und Sichtbarkeit eines Untermenüs der Module.</summary>
    class procedure TidyModuleSection(AGroup: TMenuItem); static;
    function AddItem(AText: TAtlasTextId; ATag: Integer; AOnClick: TNotifyEvent): TMenuItem; overload;
    function AddItem(const ACaption: string; ATag: Integer; AOnClick: TNotifyEvent): TMenuItem; overload;
    /// <summary>Untermenü im Atlas-Menü; folgende AddItem landen darin.</summary>
    function AddGroup(AText: TAtlasTextId): TMenuItem;
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
    /// <summary>Name der Einstellung eines Schalters (Schlüssel im Katalog der Schnellschalter, #604).</summary>
    class function ToggleKey(AToggle: TAtlasToggle): string; static;
    /// <summary>Atlas-Symbol (#751) für das aktive Thema an Menü und Einstellungseinträgen.</summary>
    procedure UpdateImage;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  ToolsAPI,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Settings.QuickToggles,
  Vcl.Clipbrd,
  Atlas.IDE.Diagnostics.Export,
  Atlas.IDE.Files.DirtyExport,
  Atlas.Core.Diagnostics.Processes,
  Atlas.UI.Diagnostics.ProcessesDialog,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Results.Impact,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Outline.Service,
  Atlas.IDE.EditorToolbar.Service,
  Atlas.IDE.Problems.Service,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Editor.MethodPlacement,
  Atlas.IDE.Generate.Commands,
  Atlas.IDE.Commands.KeyMap,
  Atlas.IDE.Commands.ShortcutTips,
  Atlas.IDE.Foundation.Symbol,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Results.Model,
  Atlas.Core.Lsp.DataFlow,
  Atlas.Core.Setup.Checklist,
  Atlas.Core.Lsp.Progress;

const
  // Kennungen der Befehlspalette für die Tastenkürzel-Tipps (#600), je Tag der Einträge.
  EditorIds: array[0..12] of string = ('Atlas.CodeActions', 'Atlas.ExpandSelection', 'Atlas.ShrinkSelection',
    'Atlas.TypeDefinition', 'Atlas.CopyQualifiedName', 'Atlas.CopyQualifiedNameParams', 'Atlas.ToggleMethod',
    'Atlas.SwitchTestUnit', '', '', 'Atlas.GenerateMenu', 'Atlas.FormatCode',
    'Atlas.MethodOrder');
  ResultsIds: array[0..11] of string = ('Atlas.References', 'Atlas.Implementations', 'Atlas.SymbolSearch',
    'Atlas.Callers', 'Atlas.Calls', 'Atlas.Supertypes', 'Atlas.Subtypes', 'Atlas.ResultsWindow', 'Atlas.CallDiagram',
    'Atlas.Impact', 'Atlas.DataFlowSources', 'Atlas.DataFlowTargets');
  // Editorleiste (#1101), je Tag von SectionClick.
  SectionIds: array[0..5] of string = ('Atlas.GotoInterface', 'Atlas.GotoImplementation', 'Atlas.GotoUses',
    'Atlas.GotoInitialization', 'Atlas.ReturnFromSection', 'Atlas.FindMethod');
  UndoIds: array[0..2] of string = ('Atlas.UndoChange', 'Atlas.RedoChange', 'Atlas.ChangeList');
  // Name des Menüs „Tools“ in der IDE; Atlas steht dahinter, sonst am Ende.
  ToolsMenu = 'ToolsMenu';
  // Menü „Ansicht“ der IDE; dort steht das Untermenü „Atlas“ (#909, #1455).
  ViewsMenu = 'ViewsMenu';

function ToggleText(AToggle: TAtlasToggle): string;
begin
  case AToggle of
    TAtlasToggle.Enabled:
      Result := TAtlasStrings.Text(TAtlasTextId.MenuToggleEnabled);
    TAtlasToggle.HoverTooltip:
      Result := TAtlasStrings.Text(TAtlasTextId.MenuToggleHover);
    TAtlasToggle.PairColors:
      Result := TAtlasStrings.Text(TAtlasTextId.MenuTogglePairs);
    TAtlasToggle.PairGuides:
      Result := TAtlasStrings.Text(TAtlasTextId.MenuToggleGuides);
    TAtlasToggle.PairOwners:
      Result := TAtlasStrings.Text(TAtlasTextId.MenuToggleOwners);
    TAtlasToggle.InactiveDim:
      Result := TAtlasStrings.Text(TAtlasTextId.MenuToggleInactive);
    TAtlasToggle.InlayHints:
      Result := TAtlasStrings.Text(TAtlasTextId.MenuToggleInlayHints);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.MenuToggleProblems);
  end;
end;

{ TAtlasMainMenu }

constructor TAtlasMainMenu.Create(const AProgress: TFunc<string>; const ACommand: TProc<string, TProc<TJSONValue>>;
  const AMessage: TProc<string>);
var
  Services: INTAServices;
  Toggle: TAtlasToggle;
  Item: TMenuItem;
  Index, Position: Integer;
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
  FModuleAnchor := AddItem('', 0, nil);
  FModuleAnchor.Visible := False;
  FRoot.Add(NewLine);
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
  // Schalter; Tag wählt den Befehl in ToggleClick.
  AddGroup(TAtlasTextId.MenuGroupView);
  for Toggle := Low(TAtlasToggle) to High(TAtlasToggle) do
  begin
    FToggles[Toggle] := AddItem(ToggleText(Toggle), Ord(Toggle), ToggleClick);
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
  FRoot.Add(NewLine);
  Item := TMenuItem.Create(FRoot);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsMenu);
  Item.OnClick := ProjectClick;
  FRoot.Add(Item);
  FImageItems := [FRoot, Item];
  // Globale Einstellungen stehen nur unter Tools › Optionen › Atlas, kein eigener Menüpunkt mehr.
  Item := TMenuItem.Create(FRoot);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.MenuOptions);
  Item.OnClick := OptionsClick;
  FRoot.Add(Item);
  FImageItems := FImageItems + [Item];
  // Nur sichtbar, wenn die Sicherung etwas abgeschaltet hat (#493).
  FEnableAll := TMenuItem.Create(FRoot);
  FEnableAll.OnClick := EnableAllClick;
  FEnableAll.Visible := False;
  FRoot.Add(FEnableAll);
  Position := Services.MainMenu.Items.Count;
  for Index := 0 to Services.MainMenu.Items.Count - 1 do
  begin
    if SameText(Services.MainMenu.Items[Index].Name, ToolsMenu) then
    begin
      Position := Index + 1;
    end;
  end;
  Services.MainMenu.Items.Insert(Position, FRoot);
  for Index := 0 to Services.MainMenu.Items.Count - 1 do
  begin
    if SameText(Services.MainMenu.Items[Index].Name, ViewsMenu) then
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
      Services.MainMenu.Items[Index].Add(FViewAtlas);
      Break;
    end;
  end;
  UpdateKeyMap;
  UpdateImage;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 500;
  FTimer.OnTimer := TimerTick;
end;

destructor TAtlasMainMenu.Destroy;
begin
  FreeAndNil(FTimer);
  FImageItems := nil;
  // Freigeben nimmt den Eintrag auch aus dem Hauptmenü.
  FreeAndNil(FRoot);
  inherited;
end;

procedure TAtlasMainMenu.UpdateImage;
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

class function TAtlasMainMenu.ToggleKey(AToggle: TAtlasToggle): string;
begin
  case AToggle of
    TAtlasToggle.Enabled:
      Result := 'Enabled';
    TAtlasToggle.HoverTooltip:
      Result := 'HoverTooltip';
    TAtlasToggle.PairColors:
      Result := 'PairColors';
    TAtlasToggle.PairGuides:
      Result := 'PairGuides';
    TAtlasToggle.PairOwners:
      Result := 'PairOwners';
    TAtlasToggle.InactiveDim:
      Result := 'InactiveDim';
    TAtlasToggle.InlayHints:
      Result := 'InlayHints';
  else
    Result := 'Problems';
  end;
end;

procedure TAtlasMainMenu.RootClick(Sender: TObject);
var
  Toggle: TAtlasToggle;
  Feature: TAtlasFeature;
  Names, Name: string;
begin
  try
    // Falls der Themenwechsel nicht gemeldet wurde.
    UpdateImage;
      UpdateKeyMap;
    UpdateModuleItems;
    for Toggle := Low(TAtlasToggle) to High(TAtlasToggle) do
    begin
      FToggles[Toggle].Checked := TAtlasIdeQuickToggles.Checked(ToggleKey(Toggle));
    end;
    // Anweisungen mitfärben wirkt nur mit der Paarfärbung (#653).
    FToggles[TAtlasToggle.PairOwners].Enabled := TAtlasIdeQuickToggles.Checked('PairColors');
    Names := '';
    for Feature in TAtlasGuard.DisabledSet do
    begin
      if Names = '' then
      begin
        Names := TAtlasGuard.FeatureName(Feature);
      end
      else
      begin
        Names := Names + ', ' + TAtlasGuard.FeatureName(Feature);
      end;
    end;
    // Auch einzeln abgeschaltete Quellen (#493).
    for Name in TAtlasGuard.DisabledProviders do
    begin
      if Names = '' then
      begin
        Names := Name;
      end
      else
      begin
        Names := Names + ', ' + Name;
      end;
    end;
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
  TAtlasGuard.Run(TAtlasFeature.Menu,
    procedure
    var
      Actions: TAtlasProcessesActions;
    begin
      Actions := Default(TAtlasProcessesActions);
      // Im Hintergrund wie der Index-Status (#874); die Antwort kommt im Hauptthread.
      Actions.Fetch :=
        procedure(ADone: TProc<TJSONValue>)
        begin
          if Assigned(FCommand) then
          begin
            FCommand(TAtlasProcessesView.Command, ADone);
          end
          else
          begin
            ADone(nil);
          end;
        end;
      Actions.ModifiedFiles :=
        function: TArray<string>
        begin
          Result := TAtlasDirtyExport.ModifiedFiles;
        end;
      Actions.CopyText :=
        procedure(AText: string)
        begin
          Clipboard.AsText := AText;
        end;
      TAtlasProcessesDialog.Execute(Actions);
    end);
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

procedure TAtlasMainMenu.UpdateKeyMap;
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
    FViewAtlas.Visible := TAtlasIdeProblems.Enabled or HasViewModuleItems;
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

function TAtlasMainMenu.AddItem(AText: TAtlasTextId; ATag: Integer; AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := AddItem(TAtlasStrings.Text(AText), ATag, AOnClick);
end;

function TAtlasMainMenu.AddItem(const ACaption: string; ATag: Integer; AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FRoot);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := AOnClick;
  FParent.Add(Result);
end;

function TAtlasMainMenu.AddGroup(AText: TAtlasTextId): TMenuItem;
begin
  Result := TMenuItem.Create(FRoot);
  Result.Caption := TAtlasStrings.Text(AText);
  FRoot.Add(Result);
  FParent := Result;
end;

procedure TAtlasMainMenu.ResultsClick(Sender: TObject);
var
  Command: Integer;
begin
  Command := TMenuItem(Sender).Tag;
  if (Command >= Low(ResultsIds)) and (Command <= High(ResultsIds)) then
  begin
    TAtlasIdeShortcutTips.Invoked(ResultsIds[Command]);
  end;
  TAtlasGuard.Run(TAtlasFeature.Results,
    procedure
    begin
      case Command of
        0: TAtlasIdeResults.FindReferences;
        1: TAtlasIdeResults.FindImplementations;
        2: TAtlasIdeResults.SearchSymbol;
        3: TAtlasIdeResults.ShowHierarchy(TAtlasHierarchyDirection.Incoming);
        4: TAtlasIdeResults.ShowHierarchy(TAtlasHierarchyDirection.Outgoing);
        5: TAtlasIdeResults.ShowHierarchy(TAtlasHierarchyDirection.Supertypes);
        6: TAtlasIdeResults.ShowHierarchy(TAtlasHierarchyDirection.Subtypes);
        8: TAtlasIdeResults.ShowCallDiagram;
        9: TAtlasIdeImpact.ShowAtCursor;
        10: TAtlasIdeResults.ShowDataFlow(TAtlasDataFlowDirection.Sources);
        11: TAtlasIdeResults.ShowDataFlow(TAtlasDataFlowDirection.Targets);
      else
        TAtlasIdeResults.ShowWindow;
      end;
    end);
end;

procedure TAtlasMainMenu.EditorClick(Sender: TObject);
var
  Command: Integer;
begin
  Command := TMenuItem(Sender).Tag;
  if (Command >= Low(EditorIds)) and (Command <= High(EditorIds)) then
  begin
    TAtlasIdeShortcutTips.Invoked(EditorIds[Command]);
  end;
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      case Command of
        0: TAtlasIdeEditorCommands.CodeActions;
        1: TAtlasIdeEditorCommands.ExpandSelection;
        2: TAtlasIdeEditorCommands.ShrinkSelection;
        3: TAtlasIdeEditorCommands.GoToTypeDefinition;
        4: TAtlasIdeEditorCommands.CopyQualifiedName(False);
        6: TAtlasIdeEditorCommands.ToggleMethod;
        7: TAtlasIdeEditorCommands.SwitchTestUnit;
        10: TAtlasIdeGenerate.Show;
        11: TAtlasIdeEditorCommands.FormatCode;
        12: TAtlasGuard.Run(TAtlasFeature.MethodPlacement, TAtlasIdeMethodPlacement.Run);
      else
        TAtlasIdeEditorCommands.CopyQualifiedName(True);
      end;
    end);
end;

procedure TAtlasMainMenu.SectionClick(Sender: TObject);
var
  Command: Integer;
begin
  Command := TMenuItem(Sender).Tag;
  if (Command >= Low(SectionIds)) and (Command <= High(SectionIds)) then
  begin
    TAtlasIdeShortcutTips.Invoked(SectionIds[Command]);
  end;
  TAtlasGuard.Run(TAtlasFeature.EditorToolbar,
    procedure
    begin
      case Command of
        0: TAtlasIdeEditorToolbar.GotoInterface;
        1: TAtlasIdeEditorToolbar.GotoImplementation;
        2: TAtlasIdeEditorToolbar.GotoUses;
        3: TAtlasIdeEditorToolbar.GotoInitialization;
        4: TAtlasIdeEditorToolbar.ReturnFromSection;
      else
        TAtlasIdeEditorToolbar.FindMethod;
      end;
    end);
end;

procedure TAtlasMainMenu.UndoClick(Sender: TObject);
var
  Command: Integer;
begin
  Command := TMenuItem(Sender).Tag;
  if (Command >= Low(UndoIds)) and (Command <= High(UndoIds)) then
  begin
    TAtlasIdeShortcutTips.Invoked(UndoIds[Command]);
  end;
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      case Command of
        0: TAtlasIdeUndo.UndoLast;
        1: TAtlasIdeUndo.RedoLast;
      else
        TAtlasIdeUndo.ShowList;
      end;
    end);
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
  TAtlasGuard.Run(TAtlasFeature.Menu, UpdateViewModuleItems);
end;

procedure TAtlasMainMenu.UpdateViewModuleItems;
var
  mItem: TMenuItem;
  mEntry: TAtlasMenuEntry;
  mCommand: TAtlasModuleCommand;
begin
  if FViewAtlas = nil then
  begin
    Exit;
  end;
  for mItem in FViewModuleItems do
  begin
    mItem.Free;
  end;
  FViewModuleItems := nil;
  FViewModuleIds := nil;
  for mEntry in TAtlasModuleContributions.MenuEntries(AtlasModuleRegistry, TAtlasMenuPlace.ViewMenu) do
  begin
    if TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, mEntry.CommandId, mCommand) then
    begin
      mItem := TMenuItem.Create(FViewAtlas);
      // Unter Ansicht › Atlas darf der Eintrag einen eigenen Text haben („Atlas: Hotspots“ statt „Hotspots …“).
      if mEntry.Caption <> '' then
      begin
        mItem.Caption := mEntry.Caption;
      end
      else
      begin
        mItem.Caption := mCommand.Caption;
      end;
      mItem.Tag := Length(FViewModuleIds);
      mItem.OnClick := ViewModuleItemClick;
      mItem.Visible := TAtlasModuleContributions.IsVisible(mCommand);
      FViewAtlas.Add(mItem);
      FViewModuleItems := FViewModuleItems + [mItem];
      FViewModuleIds := FViewModuleIds + [mCommand.Id];
    end;
  end;
end;

class function TAtlasMainMenu.HasViewModuleItems: Boolean;
var
  mEntry: TAtlasMenuEntry;
  mCommand: TAtlasModuleCommand;
begin
  for mEntry in TAtlasModuleContributions.MenuEntries(AtlasModuleRegistry, TAtlasMenuPlace.ViewMenu) do
  begin
    if TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, mEntry.CommandId, mCommand) and
      TAtlasModuleContributions.IsVisible(mCommand) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasMainMenu.ViewModuleItemClick(Sender: TObject);
var
  mIndex: Integer;
  mCommand: TAtlasModuleCommand;
begin
  mIndex := TMenuItem(Sender).Tag;
  if (mIndex < 0) or (mIndex > High(FViewModuleIds)) then
  begin
    Exit;
  end;
  // Beim Klick neu suchen (Regel 3).
  if TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, FViewModuleIds[mIndex], mCommand) and
    Assigned(mCommand.Run) then
  begin
    TAtlasIdeShortcutTips.Invoked(mCommand.Id);
    TAtlasGuard.Run(TAtlasFeature.Menu, mCommand.Run);
  end;
end;

procedure TAtlasMainMenu.ModuleItemClick(Sender: TObject);
var
  mIndex: Integer;
  mId: string;
  mCommand: TAtlasModuleCommand;
  mEntry: TAtlasMenuEntry;
begin
  mIndex := TMenuItem(Sender).Tag;
  if (mIndex < 0) or (mIndex > High(FModuleIds)) then
  begin
    Exit;
  end;
  mId := FModuleIds[mIndex];
  // Beim Klick neu suchen (Regel 3): Befehl, sonst Eintrag ohne Befehl.
  if TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, mId, mCommand) then
  begin
    if not Assigned(mCommand.Run) then
    begin
      Exit;
    end;
    TAtlasIdeShortcutTips.Invoked(mId);
    TAtlasGuard.Run(TAtlasFeature.Menu, mCommand.Run);
  end
  else if TAtlasModuleContributions.FindMenuEntry(AtlasModuleRegistry, TAtlasMenuPlace.AtlasMenu, mId, mEntry) and
    Assigned(mEntry.Run) then
  begin
    TAtlasGuard.Run(TAtlasFeature.Menu, mEntry.Run);
  end;
end;

procedure TAtlasMainMenu.UpdateModuleItems;
var
  mItem, mParent, mGroup: TMenuItem;
  mEntry: TAtlasMenuEntry;
  mCommand: TAtlasModuleCommand;
  mGroups: TArray<TMenuItem>;
  mPosition: Integer;
begin
  if (FRoot = nil) or (FModuleAnchor = nil) then
  begin
    Exit;
  end;
  // Rückwärts freigeben: Untermenüs geben ihre Einträge mit frei.
  for mItem in FModuleItems do
  begin
    if mItem.Parent = FRoot then
    begin
      mItem.Free;
    end;
  end;
  FModuleItems := nil;
  FModuleIds := nil;
  mGroups := nil;
  mPosition := FModuleAnchor.MenuIndex + 1;
  for mEntry in TAtlasModuleContributions.MenuEntries(AtlasModuleRegistry, TAtlasMenuPlace.AtlasMenu) do
  begin
    mItem := nil;
    if mEntry.CommandId = '-' then
    begin
      // Trennlinie; TidyModuleSection blendet sie am Rand und doppelt aus.
      mItem := TMenuItem.Create(FRoot);
      mItem.Caption := '-';
    end
    else if TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, mEntry.CommandId, mCommand) then
    begin
      mItem := TMenuItem.Create(FRoot);
      mItem.Caption := mCommand.Caption;
      mItem.Tag := Length(FModuleIds);
      mItem.OnClick := ModuleItemClick;
      mItem.Visible := TAtlasModuleContributions.IsVisible(mCommand);
      FModuleIds := FModuleIds + [mCommand.Id];
    end
    else if mEntry.Caption <> '' then
    begin
      // Eintrag ohne Befehl (etwa je Projektaufgabe, #900); ohne Run ausgegraut.
      mItem := TMenuItem.Create(FRoot);
      mItem.Caption := mEntry.Caption;
      mItem.Tag := Length(FModuleIds);
      mItem.OnClick := ModuleItemClick;
      mItem.Enabled := Assigned(mEntry.Run);
      FModuleIds := FModuleIds + [mEntry.CommandId];
    end;
    if mItem = nil then
    begin
      Continue;
    end;
    mParent := FRoot;
    if mEntry.Section <> '' then
    begin
      mParent := nil;
      for mGroup in mGroups do
      begin
        if mGroup.Caption = mEntry.Section then
        begin
          mParent := mGroup;
        end;
      end;
      if mParent = nil then
      begin
        mParent := TMenuItem.Create(FRoot);
        mParent.Caption := mEntry.Section;
        FRoot.Insert(mPosition, mParent);
        Inc(mPosition);
        mGroups := mGroups + [mParent];
        FModuleItems := FModuleItems + [mParent];
      end;
    end;
    if mParent = FRoot then
    begin
      FRoot.Insert(mPosition, mItem);
      Inc(mPosition);
      FModuleItems := FModuleItems + [mItem];
    end
    else
    begin
      mParent.Add(mItem);
    end;
  end;
  for mGroup in mGroups do
  begin
    TidyModuleSection(mGroup);
  end;
end;

class procedure TAtlasMainMenu.TidyModuleSection(AGroup: TMenuItem);
var
  mIndex: Integer;
  mItem: TMenuItem;
  mSeenItem, mPendingLine: Boolean;
  mLine: TMenuItem;
begin
  // Trennlinien nur zwischen sichtbaren Einträgen; das Untermenü nur mit mindestens einem.
  mSeenItem := False;
  mPendingLine := False;
  mLine := nil;
  for mIndex := 0 to AGroup.Count - 1 do
  begin
    mItem := AGroup.Items[mIndex];
    if mItem.IsLine then
    begin
      mItem.Visible := False;
      if mSeenItem then
      begin
        mPendingLine := True;
        mLine := mItem;
      end;
    end
    else if mItem.Visible then
    begin
      if mPendingLine and (mLine <> nil) then
      begin
        mLine.Visible := True;
      end;
      mPendingLine := False;
      mSeenItem := True;
    end;
  end;
  AGroup.Visible := mSeenItem;
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
