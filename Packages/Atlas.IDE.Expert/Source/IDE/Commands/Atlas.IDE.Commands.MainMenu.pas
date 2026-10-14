unit Atlas.IDE.Commands.MainMenu;

// Hauptmenü „Atlas“ hinter „Tools“ (#227): Schnellschalter für die häufigsten
// Funktionen, darunter die Projekt-Einstellungen (atlas.json) und „Optionen…“,
// das die Seite Atlas unter Tools > Optionen öffnet. Die Schalter ändern die
// Plugin-Einstellungen wie die Optionsseite (Speichern, Strukturhervorhebung
// und Help Insight der IDE abgleichen); ihre Häkchen werden beim Öffnen des
// Menüs aus den aktuellen Einstellungen gesetzt.
// Index des Servers (#492): Der Titel zeigt eine laufende Indizierung
// ("Atlas – Index 45 %"); „Index-Status“ schreibt die Kennzahlen in die
// Meldungsansicht, „Index neu aufbauen“ liest alles ohne Cache neu ein.
// „Diagnoselog exportieren…“ (#647) packt das anonymisierte Log in eine ZIP.
// „Symbol umbenennen…“ (#397) ruft OnRename auf.
// Referenzen, Implementierungen, Symbolsuche und Hierarchien öffnen das
// Ergebnisfenster (#400).
// Code-Aktionen, Auswahl erweitern/verkleinern, Typdefinition und
// qualifizierter Name (#399) gehen an TAtlasIdeEditorCommands.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Vcl.Menus,
  Vcl.ExtCtrls,
  Atlas.UI.Strings,
  Atlas.Core.Settings.Plugin;

type
{$SCOPEDENUMS ON}
  TAtlasToggle = (Enabled, HoverTooltip, PairColors, PairGuides, Problems, InactiveDim, InlayHints);
{$SCOPEDENUMS OFF}

  TAtlasMainMenu = class
  private
    FRoot: TMenuItem;
    FToggles: array[TAtlasToggle] of TMenuItem;
    FEnableAll: TMenuItem;
    FTimer: TTimer;
    FProgress: TFunc<string>;
    FCommand: TFunc<string, TJSONValue>;
    FMessage: TProc<string>;
    FShownProgress: string;
    FOnRename: TProc;
    procedure RenameClick(Sender: TObject);
    procedure ResultsClick(Sender: TObject);
    procedure EditorClick(Sender: TObject);
    function AddItem(AText: TAtlasTextId; ATag: Integer; AOnClick: TNotifyEvent): TMenuItem;
    procedure EnableAllClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure IndexStatusClick(Sender: TObject);
    procedure IndexRebuildClick(Sender: TObject);
    procedure DiagnosticExportClick(Sender: TObject);
    procedure RootClick(Sender: TObject);
    procedure ToggleClick(Sender: TObject);
    procedure ProjectClick(Sender: TObject);
    procedure OptionsClick(Sender: TObject);
  public
    /// <summary>AProgress: Fortschritt des Servers; ACommand: Serverbefehl ausführen; AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(const AProgress: TFunc<string>; const ACommand: TFunc<string, TJSONValue>;
      const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Wert eines Schalters in ASettings.</summary>
    class function Get(const ASettings: TAtlasPluginSettings; AToggle: TAtlasToggle): Boolean; static;
    class procedure Put(var ASettings: TAtlasPluginSettings; AToggle: TAtlasToggle; AValue: Boolean); static;
    /// <summary>„Symbol umbenennen…“ (#397).</summary>
    property OnRename: TProc read FOnRename write FOnRename;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  ToolsAPI,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Editor.Structure,
  Atlas.IDE.Diagnostics.Export,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Commands.Editor,
  Atlas.Core.Results.Model,
  Atlas.Core.Lsp.Progress;

const
  // Name des Menüs „Tools“ in der IDE; Atlas steht dahinter, sonst am Ende.
  ToolsMenu = 'ToolsMenu';

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
  FRoot.Add(NewLine);
  Item := TMenuItem.Create(FRoot);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsMenu);
  Item.OnClick := ProjectClick;
  FRoot.Add(Item);
  Item := TMenuItem.Create(FRoot);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.MenuOptions);
  Item.OnClick := OptionsClick;
  FRoot.Add(Item);
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
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 500;
  FTimer.OnTimer := TimerTick;
end;

destructor TAtlasMainMenu.Destroy;
begin
  FreeAndNil(FTimer);
  // Freigeben nimmt den Eintrag auch aus dem Hauptmenü.
  FreeAndNil(FRoot);
  inherited;
end;

class function TAtlasMainMenu.Get(const ASettings: TAtlasPluginSettings; AToggle: TAtlasToggle): Boolean;
begin
  case AToggle of
    TAtlasToggle.Enabled:
      Result := ASettings.Enabled;
    TAtlasToggle.HoverTooltip:
      Result := ASettings.HoverTooltip;
    TAtlasToggle.PairColors:
      Result := ASettings.PairColors;
    TAtlasToggle.PairGuides:
      Result := ASettings.PairGuides;
    TAtlasToggle.InactiveDim:
      Result := ASettings.InactiveDim;
    TAtlasToggle.InlayHints:
      Result := ASettings.InlayHints;
  else
    Result := ASettings.Problems;
  end;
end;

class procedure TAtlasMainMenu.Put(var ASettings: TAtlasPluginSettings; AToggle: TAtlasToggle; AValue: Boolean);
begin
  case AToggle of
    TAtlasToggle.Enabled:
      ASettings.Enabled := AValue;
    TAtlasToggle.HoverTooltip:
      ASettings.HoverTooltip := AValue;
    TAtlasToggle.PairColors:
      ASettings.PairColors := AValue;
    TAtlasToggle.PairGuides:
      ASettings.PairGuides := AValue;
    TAtlasToggle.InactiveDim:
      ASettings.InactiveDim := AValue;
    TAtlasToggle.InlayHints:
      ASettings.InlayHints := AValue;
  else
    ASettings.Problems := AValue;
  end;
end;

procedure TAtlasMainMenu.RootClick(Sender: TObject);
var
  Toggle: TAtlasToggle;
  Settings: TAtlasPluginSettings;
  Feature: TAtlasFeature;
  Names: string;
begin
  try
    Settings := TAtlasIdeSettings.Current;
    for Toggle := Low(TAtlasToggle) to High(TAtlasToggle) do
      FToggles[Toggle].Checked := Get(Settings, Toggle);
    Names := '';
    for Feature in TAtlasGuard.DisabledSet do
      if Names = '' then
        Names := TAtlasGuard.FeatureName(Feature)
      else
        Names := Names + ', ' + TAtlasGuard.FeatureName(Feature);
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
  Settings: TAtlasPluginSettings;
begin
  try
    Toggle := TAtlasToggle(TMenuItem(Sender).Tag);
    Settings := TAtlasIdeSettings.Current;
    Put(Settings, Toggle, not Get(Settings, Toggle));
    TAtlasIdeSettings.Update(Settings);
    // Wie beim Schließen der Optionsseite: Strukturhervorhebung und Help Insight der IDE abgleichen.
    TAtlasIdeStructureSwitch.Sync;
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

procedure TAtlasMainMenu.RenameClick(Sender: TObject);
begin
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
