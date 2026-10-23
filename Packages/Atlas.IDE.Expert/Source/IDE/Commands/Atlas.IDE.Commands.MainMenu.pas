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
// MCP-Prozesse am Projekt; sichtbar nach diagnostics.processes.
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
// Persönliche Notizen (#545) gehen an TAtlasIdeNotes; sichtbar nur bei
// eingeschalteter Einstellung „Notizen“. Benannte Lesezeichen (#622) gehen an
// TAtlasIdeBookmarks; sichtbar nur bei bookmarks.named, das Fenster auch bei
// bookmarks.quick. Schnelle Lesezeichen (#1104: setzen/entfernen, nächstes,
// voriges) sichtbar nur bei bookmarks.quick. „Gliederung …“ (#537)
// öffnet TAtlasIdeOutline; sichtbar nur bei outline.enabled.
// Das Atlas-Symbol (#751) steht am Menü und an den Einträgen für Einstellungen
// und Optionen; UpdateImage wählt nach einem Themenwechsel die passende Variante.
// Willkommensseite (#753): „Atlas-Start“ (auch unter Ansicht), „Atlas-Layout
// anwenden“ und „Atlas-Layout zurücksetzen“ rufen OnWelcome; sichtbar nur bei
// welcomePage.enabled, Anwenden nur ohne, Zurücksetzen nur mit Atlas-Layout.
// Befehle mit einer Kennung der Befehlspalette melden sich bei den
// Tastenkürzel-Tipps (#600) als Aufruf per Menü (TAtlasIdeShortcutTips.Invoked).
// „Atlas-Prüfung“ (#909) öffnet das Fenster der Befunde, auch unter Ansicht ›
// Atlas › Prüfung; sichtbar nur bei problems.window.
// Unter Navigation die Abschnittssprünge, der Rücksprung und „Methode suchen“
// der Editorleiste (#1101); sie arbeiten auch ohne die Leiste.
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
  TAtlasWelcomeCommand = (Start, Apply, Reset);
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
    FOnWelcome: TProc<TAtlasWelcomeCommand>;
    FWelcome: array[TAtlasWelcomeCommand] of TMenuItem;
    FWelcomeLine: TMenuItem;
    FViewStart: TMenuItem;
    FNoteItems: TArray<TMenuItem>;
    FBookmarkItems: TArray<TMenuItem>;
    FQuickItems: TArray<TMenuItem>;
    /// <summary>„Erzeugen…“ (#719), sichtbar nach keys.generateMenu.</summary>
    FGenerateItem: TMenuItem;
    /// <summary>„Formatieren“ (#43), nur mit editor.format.</summary>
    FFormatItem: TMenuItem;
    /// <summary>„Gliederung …“ (#537), sichtbar nach outline.enabled.</summary>
    FOutlineItem: TMenuItem;
    /// <summary>Untermenü „Notizen und Lesezeichen“ (#545, #622).</summary>
    FNotesGroup: TMenuItem;
    /// <summary>„Atlas-Prüfung“ (#909) im Atlas-Menü und unter Ansicht › Atlas.</summary>
    FProblemsItem: TMenuItem;
    /// <summary>„Atlas: Exception-Verlauf“ (#517), sichtbar nach debug.exceptionHistory.</summary>
    FDebugExceptionsItem: TMenuItem;
    FViewAtlas: TMenuItem;
    procedure WelcomeClick(Sender: TObject);
    procedure RenameClick(Sender: TObject);
    procedure ResultsClick(Sender: TObject);
    procedure EditorClick(Sender: TObject);
    procedure SectionClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure NotesClick(Sender: TObject);
    procedure BookmarksClick(Sender: TObject);
    procedure OutlineClick(Sender: TObject);
    procedure ProblemsClick(Sender: TObject);
    procedure DebugExceptionsClick(Sender: TObject);
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
    /// <summary>„Einrichtung prüfen…“ (#625).</summary>
    property OnSetup: TProc read FOnSetup write FOnSetup;
    /// <summary>„Tastenkürzel-Übersicht…“ (#520).</summary>
    property OnKeyMap: TProc read FOnKeyMap write FOnKeyMap;
    /// <summary>Eintrag „Tastenkürzel-Übersicht…“ nach keys.overview ein- oder ausblenden.</summary>
    procedure UpdateKeyMap;
    /// <summary>Befehle der Willkommensseite (#753).</summary>
    property OnWelcome: TProc<TAtlasWelcomeCommand> read FOnWelcome write FOnWelcome;
    /// <summary>Einträge der Willkommensseite nach den Einstellungen ein- oder ausblenden.</summary>
    procedure UpdateWelcome;
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
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Notes.Service,
  Atlas.IDE.Bookmarks.Service,
  Atlas.IDE.Outline.Service,
  Atlas.IDE.EditorToolbar.Service,
  Atlas.IDE.Problems.Service,
  Atlas.IDE.Debug.Exceptions,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.UnitSearch.Commands,
  Atlas.IDE.Generate.Commands,
  Atlas.IDE.Commands.KeyMap,
  Atlas.IDE.Commands.ShortcutTips,
  Atlas.IDE.Foundation.Symbol,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Results.Model,
  Atlas.Core.Setup.Checklist,
  Atlas.Core.Lsp.Progress;

const
  // Kennungen der Befehlspalette für die Tastenkürzel-Tipps (#600), je Tag der Einträge.
  EditorIds: array[0..11] of string = ('Atlas.CodeActions', 'Atlas.ExpandSelection', 'Atlas.ShrinkSelection',
    'Atlas.TypeDefinition', 'Atlas.CopyQualifiedName', 'Atlas.CopyQualifiedNameParams', 'Atlas.ToggleMethod',
    'Atlas.SwitchTestUnit', 'Atlas.UnitSearch', 'Atlas.UnitSearchIde', 'Atlas.GenerateMenu', 'Atlas.FormatCode');
  ResultsIds: array[0..7] of string = ('Atlas.References', 'Atlas.Implementations', 'Atlas.SymbolSearch',
    'Atlas.Callers', 'Atlas.Calls', 'Atlas.Supertypes', 'Atlas.Subtypes', 'Atlas.ResultsWindow');
  // Editorleiste (#1101), je Tag von SectionClick.
  SectionIds: array[0..5] of string = ('Atlas.GotoInterface', 'Atlas.GotoImplementation', 'Atlas.GotoUses',
    'Atlas.GotoInitialization', 'Atlas.ReturnFromSection', 'Atlas.FindMethod');
  UndoIds: array[0..2] of string = ('Atlas.UndoChange', 'Atlas.RedoChange', 'Atlas.ChangeList');
  NoteIds: array[0..2] of string = ('Atlas.NoteAdd', 'Atlas.NoteDelete', 'Atlas.NoteList');
  BookmarkIds: array[0..5] of string = ('Atlas.BookmarkAdd', 'Atlas.BookmarkGoTo', 'Atlas.BookmarkWindow',
    'Atlas.QuickBookmarkToggle', 'Atlas.NextBookmark', 'Atlas.PreviousBookmark');
  WelcomeIds: array[TAtlasWelcomeCommand] of string = ('Atlas.WelcomeStart', 'Atlas.WelcomeApply',
    'Atlas.WelcomeReset');
  // Name des Menüs „Tools“ in der IDE; Atlas steht dahinter, sonst am Ende.
  ToolsMenu = 'ToolsMenu';
  // Menü „Ansicht“ der IDE; dort steht „Atlas-Start“ zusätzlich (#753).
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
    Exit;
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
  // Units suchen (#777).
  AddItem(TAtlasTextId.UnitSearchMenu, 8, EditorClick);
  AddItem(TAtlasTextId.MenuSymbolSearch, 2, ResultsClick);
  FProblemsItem := AddItem(TAtlasTextId.ProblemsWindowCaption, 0, ProblemsClick);
  // Exception-Verlauf beim Debuggen (#517).
  FDebugExceptionsItem := AddItem(TAtlasTextId.DebugExceptionsCommand, 0, DebugExceptionsClick);
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
  // Der IDE-Dialog, falls Atlas Strg+F12 übernimmt.
  AddItem(TAtlasTextId.UnitSearchIdeDialog, 9, EditorClick);
  AddGroup(TAtlasTextId.MenuGroupSearch);
  AddItem(TAtlasTextId.MenuReferences, 0, ResultsClick);
  AddItem(TAtlasTextId.MenuImplementations, 1, ResultsClick);
  AddItem(TAtlasTextId.MenuIncoming, 3, ResultsClick);
  AddItem(TAtlasTextId.MenuOutgoing, 4, ResultsClick);
  AddItem(TAtlasTextId.MenuSupertypes, 5, ResultsClick);
  AddItem(TAtlasTextId.MenuSubtypes, 6, ResultsClick);
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
  // Persönliche Notizen (#545) und benannte Lesezeichen (#622) in einem Untermenü; Tag wählt den Befehl in
  // NotesClick bzw. BookmarksClick. Das Untermenü ist sichtbar, solange eins von beiden an ist.
  FNotesGroup := AddGroup(TAtlasTextId.MenuGroupNotes);
  FNoteItems := [AddItem(TAtlasTextId.NotesMenuAdd, 0, NotesClick)];
  FNoteItems := FNoteItems + [AddItem(TAtlasTextId.NotesMenuDelete, 1, NotesClick)];
  FNoteItems := FNoteItems + [AddItem(TAtlasTextId.NotesMenuList, 2, NotesClick)];
  FBookmarkItems := [NewLine];
  FParent.Add(FBookmarkItems[0]);
  FBookmarkItems := FBookmarkItems + [AddItem(TAtlasTextId.BookmarksMenuAdd, 0, BookmarksClick)];
  FBookmarkItems := FBookmarkItems + [AddItem(TAtlasTextId.BookmarksMenuGoTo, 1, BookmarksClick)];
  FBookmarkItems := FBookmarkItems + [AddItem(TAtlasTextId.BookmarksMenuWindow, 2, BookmarksClick)];
  FQuickItems := [AddItem(TAtlasTextId.QuickBookmarkToggleCommand, 3, BookmarksClick)];
  FQuickItems := FQuickItems + [AddItem(TAtlasTextId.NextBookmarkCommand, 4, BookmarksClick)];
  FQuickItems := FQuickItems + [AddItem(TAtlasTextId.PreviousBookmarkCommand, 5, BookmarksClick)];
  // Schalter und Willkommensseite (#753); Tag wählt den Befehl in ToggleClick bzw. WelcomeClick.
  AddGroup(TAtlasTextId.MenuGroupView);
  for Toggle := Low(TAtlasToggle) to High(TAtlasToggle) do
    FToggles[Toggle] := AddItem(ToggleText(Toggle), Ord(Toggle), ToggleClick);
  FWelcomeLine := NewLine;
  FParent.Add(FWelcomeLine);
  FWelcome[TAtlasWelcomeCommand.Start] := AddItem(TAtlasTextId.MenuWelcomeStart,
    Ord(TAtlasWelcomeCommand.Start), WelcomeClick);
  FWelcome[TAtlasWelcomeCommand.Apply] := AddItem(TAtlasTextId.MenuWelcomeApply,
    Ord(TAtlasWelcomeCommand.Apply), WelcomeClick);
  FWelcome[TAtlasWelcomeCommand.Reset] := AddItem(TAtlasTextId.MenuWelcomeReset,
    Ord(TAtlasWelcomeCommand.Reset), WelcomeClick);
  AddGroup(TAtlasTextId.MenuGroupIndex);
  AddItem(TAtlasTextId.MenuIndexStatus, 0, IndexStatusClick);
  AddItem(TAtlasTextId.MenuIndexRebuild, 0, IndexRebuildClick);
  AddGroup(TAtlasTextId.MenuGroupHelp);
  FKeyMapItem := AddItem(TAtlasTextId.KeyMapMenu, 0, KeyMapClick);
  AddItem(TAtlasTextId.SetupMenu, 0, SetupClick);
  AddItem(TAtlasTextId.DiagExportMenu, 0, DiagnosticExportClick);
  FProcessesItem := AddItem(TAtlasTextId.ProcessesMenu, 0, ProcessesClick);
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
    if SameText(Services.MainMenu.Items[Index].Name, ToolsMenu) then
      Position := Index + 1;
  Services.MainMenu.Items.Insert(Position, FRoot);
  for Index := 0 to Services.MainMenu.Items.Count - 1 do
    if SameText(Services.MainMenu.Items[Index].Name, ViewsMenu) then
    begin
      // Gehört dem Atlas-Menü, damit es mit ihm freigegeben wird; Freigeben nimmt es aus „Ansicht“.
      FViewStart := TMenuItem.Create(FRoot);
      FViewStart.Caption := TAtlasStrings.Text(TAtlasTextId.MenuWelcomeStart);
      FViewStart.Tag := Ord(TAtlasWelcomeCommand.Start);
      FViewStart.OnClick := WelcomeClick;
      Services.MainMenu.Items[Index].Add(FViewStart);
      // Ansicht › Atlas › Prüfung (#909).
      FViewAtlas := TMenuItem.Create(FRoot);
      FViewAtlas.Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsViewMenuAtlas);
      Item := TMenuItem.Create(FViewAtlas);
      Item.Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsViewMenuWindow);
      Item.OnClick := ProblemsClick;
      FViewAtlas.Add(Item);
      Services.MainMenu.Items[Index].Add(FViewAtlas);
      Break;
    end;
  UpdateWelcome;
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
    Item.ImageIndex := Image;
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

procedure TAtlasMainMenu.UpdateWelcome;
var
  Settings: TAtlasPluginSettings;
  AtlasLayout: Boolean;
begin
  if FRoot = nil then
    Exit;
  Settings := TAtlasIdeSettings.Current;
  AtlasLayout := SameText(Settings.WelcomePageLayout, 'atlas');
  FWelcomeLine.Visible := Settings.WelcomePage;
  FWelcome[TAtlasWelcomeCommand.Start].Visible := Settings.WelcomePage;
  // Das Layout gilt nur auf der Willkommensseite der IDE, nicht im Fenster „Atlas-Start“.
  FWelcome[TAtlasWelcomeCommand.Apply].Visible := Settings.WelcomePage and
    (Settings.WelcomePageHost = 'welcomePage') and not AtlasLayout;
  FWelcome[TAtlasWelcomeCommand.Reset].Visible := Settings.WelcomePage and AtlasLayout;
  if FViewStart <> nil then
    FViewStart.Visible := Settings.WelcomePage;
end;

procedure TAtlasMainMenu.WelcomeClick(Sender: TObject);
var
  Command: TAtlasWelcomeCommand;
begin
  if not Assigned(FOnWelcome) then
    Exit;
  Command := TAtlasWelcomeCommand(TMenuItem(Sender).Tag);
  TAtlasIdeShortcutTips.Invoked(WelcomeIds[Command]);
  TAtlasGuard.Run(TAtlasFeature.Menu,
    procedure
    begin
      FOnWelcome(Command);
    end);
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
    UpdateWelcome;
    UpdateKeyMap;
    for Toggle := Low(TAtlasToggle) to High(TAtlasToggle) do
      FToggles[Toggle].Checked := TAtlasIdeQuickToggles.Checked(ToggleKey(Toggle));
    // Anweisungen mitfärben wirkt nur mit der Paarfärbung (#653).
    FToggles[TAtlasToggle.PairOwners].Enabled := TAtlasIdeQuickToggles.Checked('PairColors');
    Names := '';
    for Feature in TAtlasGuard.DisabledSet do
      if Names = '' then
        Names := TAtlasGuard.FeatureName(Feature)
      else
        Names := Names + ', ' + TAtlasGuard.FeatureName(Feature);
    // Auch einzeln abgeschaltete Quellen (#493).
    for Name in TAtlasGuard.DisabledProviders do
      if Names = '' then
        Names := Name
      else
        Names := Names + ', ' + Name;
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
        Text := FProgress();
      if Text = FShownProgress then
        Exit;
      FShownProgress := Text;
      // Nur bei Änderung: Der Titel im Hauptmenü zeichnet die ganze Leiste neu.
      if Text = '' then
        FRoot.Caption := TAtlasStrings.Text(TAtlasTextId.MenuAtlas)
      else
        FRoot.Caption := TAtlasStrings.Text(TAtlasTextId.MenuAtlas) + ' – ' + Text;
    end);
end;

procedure TAtlasMainMenu.IndexStatusClick(Sender: TObject);
begin
  // Im Hintergrund: Ein Server, der gerade indexiert, antwortet erst danach (#874).
  TAtlasGuard.Run(TAtlasFeature.Server,
    procedure
    begin
      if not Assigned(FCommand) then
        Exit;
      FCommand('atlas.server.status',
        procedure(AStatus: TJSONValue)
        var
          Line: string;
        begin
          if AStatus = nil then
            FMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer))
          else
            for Line in TLspIndexStatus.Lines(AStatus) do
              FMessage(Line);
        end);
    end);
end;

procedure TAtlasMainMenu.IndexRebuildClick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Server,
    procedure
    begin
      if not Assigned(FCommand) then
        Exit;
      FCommand('atlas.server.rebuildIndex',
        procedure(AAnswer: TJSONValue)
        begin
          if AAnswer = nil then
            FMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer))
          else
            FMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexRebuilding));
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
            FCommand(TAtlasProcessesView.Command, ADone)
          else
            ADone(nil);
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
    TAtlasGuard.Run(TAtlasFeature.Menu,
      procedure
      begin
        FOnBugReport();
      end);
end;

procedure TAtlasMainMenu.SetupClick(Sender: TObject);
begin
  TAtlasIdeShortcutTips.Invoked(TAtlasSetupChecklist.CommandId);
  if Assigned(FOnSetup) then
    TAtlasGuard.Run(TAtlasFeature.Menu,
      procedure
      begin
        FOnSetup();
      end);
end;

procedure TAtlasMainMenu.KeyMapClick(Sender: TObject);
begin
  TAtlasIdeShortcutTips.Invoked(TAtlasIdeKeyMap.CommandId);
  if Assigned(FOnKeyMap) then
    TAtlasGuard.Run(TAtlasFeature.Menu,
      procedure
      begin
        FOnKeyMap();
      end);
end;

procedure TAtlasMainMenu.UpdateKeyMap;
var
  Item: TMenuItem;
  Marks: Boolean;
begin
  if FKeyMapItem <> nil then
    FKeyMapItem.Visible := TAtlasIdeSettings.Current.KeyOverview;
  // Prozesse am Projekt (#62) nach diagnostics.processes.
  if FProcessesItem <> nil then
    FProcessesItem.Visible := TAtlasIdeSettings.Current.DiagnosticsProcesses;
  // Notizen (#545) nach ihrer Einstellung.
  for Item in FNoteItems do
    Item.Visible := TAtlasIdeSettings.Current.Notes;
  // Erzeugen-Menü (#719) nach keys.generateMenu.
  if FGenerateItem <> nil then
    FGenerateItem.Visible := TAtlasIdeSettings.Current.GenerateMenu;
  // Formatieren (#43) nach editor.format.
  if FFormatItem <> nil then
    FFormatItem.Visible := TAtlasIdeSettings.Current.FormatCode;
  // Gliederung (#537) nach outline.enabled.
  if FOutlineItem <> nil then
    FOutlineItem.Visible := TAtlasIdeSettings.Current.Outline;
  // Atlas-Prüfung (#909) nach problems.window.
  if FProblemsItem <> nil then
    FProblemsItem.Visible := TAtlasIdeProblems.Enabled;
  if FViewAtlas <> nil then
    FViewAtlas.Visible := TAtlasIdeProblems.Enabled;
  // Exception-Verlauf (#517) nach debug.exceptionHistory.
  if FDebugExceptionsItem <> nil then
    FDebugExceptionsItem.Visible := TAtlasIdeSettings.Current.DebugExceptionHistory;
  // Benannte Lesezeichen (#622) nach bookmarks.named, schnelle (#1104) nach bookmarks.quick; das Fenster zeigt
  // beide.
  Marks := TAtlasIdeSettings.Current.BookmarksNamed or TAtlasIdeSettings.Current.QuickBookmarks;
  for Item in FBookmarkItems do
    Item.Visible := TAtlasIdeSettings.Current.BookmarksNamed;
  if Length(FBookmarkItems) > 3 then
    FBookmarkItems[3].Visible := Marks;
  for Item in FQuickItems do
    Item.Visible := TAtlasIdeSettings.Current.QuickBookmarks;
  // Trennlinie zwischen Notizen und Lesezeichen nur, wenn beide sichtbar sind.
  if Length(FBookmarkItems) > 0 then
    FBookmarkItems[0].Visible := TAtlasIdeSettings.Current.Notes and Marks;
  if FNotesGroup <> nil then
    FNotesGroup.Visible := TAtlasIdeSettings.Current.Notes or Marks;
end;

procedure TAtlasMainMenu.RenameClick(Sender: TObject);
begin
  TAtlasIdeShortcutTips.Invoked('Atlas.Rename');
  if Assigned(FOnRename) then
    TAtlasGuard.Run(TAtlasFeature.Menu,
      procedure
      begin
        FOnRename();
      end);
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
    TAtlasIdeShortcutTips.Invoked(ResultsIds[Command]);
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
    TAtlasIdeShortcutTips.Invoked(EditorIds[Command]);
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
        8: TAtlasIdeUnitSearch.Show;
        9: TAtlasIdeUnitSearch.ShowIdeDialog;
        10: TAtlasIdeGenerate.Show;
        11: TAtlasIdeEditorCommands.FormatCode;
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
    TAtlasIdeShortcutTips.Invoked(SectionIds[Command]);
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
    TAtlasIdeShortcutTips.Invoked(UndoIds[Command]);
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

procedure TAtlasMainMenu.NotesClick(Sender: TObject);
var
  Command: Integer;
begin
  Command := TMenuItem(Sender).Tag;
  if (Command >= Low(NoteIds)) and (Command <= High(NoteIds)) then
    TAtlasIdeShortcutTips.Invoked(NoteIds[Command]);
  TAtlasGuard.Run(TAtlasFeature.Notes,
    procedure
    begin
      case Command of
        0: TAtlasIdeNotes.AddOrEdit;
        1: TAtlasIdeNotes.DeleteAtLine;
      else
        TAtlasIdeNotes.ShowList;
      end;
    end);
end;

procedure TAtlasMainMenu.BookmarksClick(Sender: TObject);
var
  Command: Integer;
  Feature: TAtlasFeature;
begin
  Command := TMenuItem(Sender).Tag;
  if (Command >= Low(BookmarkIds)) and (Command <= High(BookmarkIds)) then
    TAtlasIdeShortcutTips.Invoked(BookmarkIds[Command]);
  Feature := TAtlasFeature.Bookmarks;
  if Command >= 3 then
    Feature := TAtlasFeature.QuickBookmarks;
  TAtlasGuard.Run(Feature,
    procedure
    begin
      case Command of
        0: TAtlasIdeBookmarks.AddBookmark;
        1: TAtlasIdeBookmarks.GoToBookmark;
        3: TAtlasIdeBookmarks.QuickToggle;
        4: TAtlasIdeBookmarks.NextBookmark;
        5: TAtlasIdeBookmarks.PreviousBookmark;
      else
        TAtlasIdeBookmarks.ShowWindow;
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

procedure TAtlasMainMenu.DebugExceptionsClick(Sender: TObject);
begin
  TAtlasIdeShortcutTips.Invoked('Atlas.DebugExceptions');
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      TAtlasIdeDebugExceptions.ShowWindow;
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
      Options.EditOptions('', 'Atlas');
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

end.
