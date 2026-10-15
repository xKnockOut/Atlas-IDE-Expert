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
// ("Atlas – Index 45 %"); „Index-Status“ schreibt die Kennzahlen in die
// Meldungsansicht, „Index neu aufbauen“ liest alles ohne Cache neu ein.
// „Diagnoselog exportieren…“ (#647) packt das anonymisierte Log in eine ZIP.
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
// Das Atlas-Symbol (#751) steht am Menü und an den Einträgen für Einstellungen
// und Optionen; UpdateImage wählt nach einem Themenwechsel die passende Variante.
// Willkommensseite (#753): „Atlas-Start“ (auch unter Ansicht), „Atlas-Layout
// anwenden“ und „Atlas-Layout zurücksetzen“ rufen OnWelcome; sichtbar nur bei
// welcomePage.enabled, Anwenden nur ohne, Zurücksetzen nur mit Atlas-Layout.
// Befehle mit einer Kennung der Befehlspalette melden sich bei den
// Tastenkürzel-Tipps (#600) als Aufruf per Menü (TAtlasIdeShortcutTips.Invoked).

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
    FToggles: array[TAtlasToggle] of TMenuItem;
    FEnableAll: TMenuItem;
    FImageItems: TArray<TMenuItem>;
    FTimer: TTimer;
    FProgress: TFunc<string>;
    FCommand: TFunc<string, TJSONValue>;
    FMessage: TProc<string>;
    FShownProgress: string;
    FOnRename: TProc;
    FOnBugReport: TProc;
    FOnSetup: TProc;
    FOnKeyMap: TProc;
    FKeyMapItem: TMenuItem;
    FOnWelcome: TProc<TAtlasWelcomeCommand>;
    FWelcome: array[TAtlasWelcomeCommand] of TMenuItem;
    FWelcomeLine: TMenuItem;
    FViewStart: TMenuItem;
    procedure WelcomeClick(Sender: TObject);
    procedure RenameClick(Sender: TObject);
    procedure ResultsClick(Sender: TObject);
    procedure EditorClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    function AddItem(AText: TAtlasTextId; ATag: Integer; AOnClick: TNotifyEvent): TMenuItem;
    procedure EnableAllClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure IndexStatusClick(Sender: TObject);
    procedure IndexRebuildClick(Sender: TObject);
    procedure DiagnosticExportClick(Sender: TObject);
    procedure BugReportClick(Sender: TObject);
    procedure SetupClick(Sender: TObject);
    procedure KeyMapClick(Sender: TObject);
    procedure RootClick(Sender: TObject);
    procedure ToggleClick(Sender: TObject);
    procedure ProjectClick(Sender: TObject);
    procedure OptionsClick(Sender: TObject);
  public
    /// <summary>AProgress: Fortschritt des Servers; ACommand: Serverbefehl ausführen; AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(const AProgress: TFunc<string>; const ACommand: TFunc<string, TJSONValue>;
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
  Atlas.IDE.Diagnostics.Export,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Commands.KeyMap,
  Atlas.IDE.Commands.ShortcutTips,
  Atlas.IDE.Style.Symbol,
  Atlas.IDE.Settings.Store,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Results.Model,
  Atlas.Core.Setup.Checklist,
  Atlas.Core.Lsp.Progress;

const
  // Kennungen der Befehlspalette für die Tastenkürzel-Tipps (#600), je Tag der Einträge.
  EditorIds: array[0..5] of string = ('Atlas.CodeActions', 'Atlas.ExpandSelection', 'Atlas.ShrinkSelection',
    'Atlas.TypeDefinition', 'Atlas.CopyQualifiedName', 'Atlas.CopyQualifiedNameParams');
  ResultsIds: array[0..7] of string = ('Atlas.References', 'Atlas.Implementations', 'Atlas.SymbolSearch',
    'Atlas.Callers', 'Atlas.Calls', 'Atlas.Supertypes', 'Atlas.Subtypes', 'Atlas.ResultsWindow');
  UndoIds: array[0..2] of string = ('Atlas.UndoChange', 'Atlas.RedoChange', 'Atlas.ChangeList');
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

constructor TAtlasMainMenu.Create(const AProgress: TFunc<string>; const ACommand: TFunc<string, TJSONValue>;
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
  for Toggle := Low(TAtlasToggle) to High(TAtlasToggle) do
  begin
    Item := TMenuItem.Create(FRoot);
    Item.Caption := ToggleText(Toggle);
    Item.Tag := Ord(Toggle);
    Item.OnClick := ToggleClick;
    FRoot.Add(Item);
    FToggles[Toggle] := Item;
  end;
  FRoot.Add(NewLine);
  Item := TMenuItem.Create(FRoot);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.RenameMenu);
  Item.OnClick := RenameClick;
  FRoot.Add(Item);
  // Editorbefehle (#399); Tag wählt den Befehl in EditorClick.
  AddItem(TAtlasTextId.EditorActions, 0, EditorClick);
  AddItem(TAtlasTextId.EditorExpand, 1, EditorClick);
  AddItem(TAtlasTextId.EditorShrink, 2, EditorClick);
  AddItem(TAtlasTextId.EditorTypeDefinition, 3, EditorClick);
  AddItem(TAtlasTextId.EditorCopyQualified, 4, EditorClick);
  AddItem(TAtlasTextId.EditorCopyQualifiedParams, 5, EditorClick);
  FRoot.Add(NewLine);
  // Ergebnisfenster (#400); Tag wählt den Befehl in ResultsClick.
  AddItem(TAtlasTextId.MenuReferences, 0, ResultsClick);
  AddItem(TAtlasTextId.MenuImplementations, 1, ResultsClick);
  AddItem(TAtlasTextId.MenuSymbolSearch, 2, ResultsClick);
  AddItem(TAtlasTextId.MenuIncoming, 3, ResultsClick);
  AddItem(TAtlasTextId.MenuOutgoing, 4, ResultsClick);
  AddItem(TAtlasTextId.MenuSupertypes, 5, ResultsClick);
  AddItem(TAtlasTextId.MenuSubtypes, 6, ResultsClick);
  AddItem(TAtlasTextId.MenuResultsWindow, 7, ResultsClick);
  FRoot.Add(NewLine);
  // Atlas-Änderungen über mehrere Dateien (#721); Tag wählt den Befehl in UndoClick.
  AddItem(TAtlasTextId.UndoMenu, 0, UndoClick);
  AddItem(TAtlasTextId.RedoMenu, 1, UndoClick);
  AddItem(TAtlasTextId.UndoListMenu, 2, UndoClick);
  FRoot.Add(NewLine);
  Item := TMenuItem.Create(FRoot);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.MenuIndexStatus);
  Item.OnClick := IndexStatusClick;
  FRoot.Add(Item);
  Item := TMenuItem.Create(FRoot);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.MenuIndexRebuild);
  Item.OnClick := IndexRebuildClick;
  FRoot.Add(Item);
  Item := TMenuItem.Create(FRoot);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.DiagExportMenu);
  Item.OnClick := DiagnosticExportClick;
  FRoot.Add(Item);
  Item := TMenuItem.Create(FRoot);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.BugReportMenu);
  Item.OnClick := BugReportClick;
  FRoot.Add(Item);
  Item := TMenuItem.Create(FRoot);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.SetupMenu);
  Item.OnClick := SetupClick;
  FRoot.Add(Item);
  FKeyMapItem := TMenuItem.Create(FRoot);
  FKeyMapItem.Caption := TAtlasStrings.Text(TAtlasTextId.KeyMapMenu);
  FKeyMapItem.OnClick := KeyMapClick;
  FRoot.Add(FKeyMapItem);
  // Willkommensseite (#753); Tag wählt den Befehl in WelcomeClick.
  FWelcomeLine := NewLine;
  FRoot.Add(FWelcomeLine);
  FWelcome[TAtlasWelcomeCommand.Start] := AddItem(TAtlasTextId.MenuWelcomeStart,
    Ord(TAtlasWelcomeCommand.Start), WelcomeClick);
  FWelcome[TAtlasWelcomeCommand.Apply] := AddItem(TAtlasTextId.MenuWelcomeApply,
    Ord(TAtlasWelcomeCommand.Apply), WelcomeClick);
  FWelcome[TAtlasWelcomeCommand.Reset] := AddItem(TAtlasTextId.MenuWelcomeReset,
    Ord(TAtlasWelcomeCommand.Reset), WelcomeClick);
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
  TAtlasGuard.Run(TAtlasFeature.Server,
    procedure
    var
      Status: TJSONValue;
      Line: string;
    begin
      Status := nil;
      if Assigned(FCommand) then
        Status := FCommand('atlas.server.status');
      try
        if Status = nil then
          FMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer))
        else
          for Line in TLspIndexStatus.Lines(Status) do
            FMessage(Line);
      finally
        Status.Free;
      end;
    end);
end;

procedure TAtlasMainMenu.IndexRebuildClick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Server,
    procedure
    var
      Answer: TJSONValue;
    begin
      Answer := nil;
      if Assigned(FCommand) then
        Answer := FCommand('atlas.server.rebuildIndex');
      try
        if Answer = nil then
          FMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer))
        else
          FMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexRebuilding));
      finally
        Answer.Free;
      end;
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
begin
  if FKeyMapItem <> nil then
    FKeyMapItem.Visible := TAtlasIdeSettings.Current.KeyOverview;
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
  Result := TMenuItem.Create(FRoot);
  Result.Caption := TAtlasStrings.Text(AText);
  Result.Tag := ATag;
  Result.OnClick := AOnClick;
  FRoot.Add(Result);
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
      else
        TAtlasIdeEditorCommands.CopyQualifiedName(True);
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
