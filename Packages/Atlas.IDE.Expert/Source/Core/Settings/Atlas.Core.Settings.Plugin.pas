unit Atlas.Core.Settings.Plugin;

// Einstellungen des IDE-Plugins (#227, Teil Vervollständigung), ohne VCL und
// ohne Registry: Vorgaben, Grenzen, Lesen und Schreiben über einen Speicher.
// Die IDE-Schicht speichert in HKCU\Software\Atlas\IdePlugin, Tests im
// Arbeitsspeicher. Breiten in logischen Pixeln (96 dpi, #412).

interface

uses
  System.SysUtils;

type
  /// <summary>Ablage für Einstellungen; Werte als ganze Zahlen (Wahrheitswerte 0/1).</summary>
  IAtlasSettingsStore = interface
    ['{4C8E2A17-9B3D-4F61-A5E2-7D0C1B9F3E84}']
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

  TAtlasPluginSettings = record
  public const
    MinVisibleRows = 5;
    MaxVisibleRows = 20;
    MinListWidth = 240;
    MaxListWidth = 720;
    MinPanelWidth = 220;
    MaxPanelWidth = 600;
    MinHangThreshold = 100;
    MaxHangThreshold = 10000;
    MinCheckDelay = 500;
    MaxCheckDelay = 10000;
    MinCheckMax = 200;
    MaxCheckMax = 20000;
  public
    /// <summary>Hauptschalter (#407): aus = eingebaute Code Insight der IDE.</summary>
    Enabled: Boolean;
    /// <summary>Sichtbare Zeilen der Liste (#413).</summary>
    VisibleRows: Integer;
    /// <summary>Von Hand gezogene Breite der Liste, 0 = automatisch (#416).</summary>
    ListWidth: Integer;
    /// <summary>Breite des Detailpanels (#416).</summary>
    PanelWidth: Integer;
    /// <summary>Detailpanel eingeklappt (#428).</summary>
    PanelCollapsed: Boolean;
    /// <summary>Klammern beim Übernehmen von Methoden (#430).</summary>
    AutoParentheses: Boolean;
    /// <summary>Schreibweise des getippten Worts beim Übernehmen korrigieren (#433).</summary>
    FixCase: Boolean;
    /// <summary>Tastenkürzel der Befehlspalette und der Syntaxprüfung (TShortCut, 0 = keins, #494).</summary>
    PaletteKey: Integer;
    CheckKey: Integer;
    /// <summary>Kürzel auch belegen, wenn die IDE oder eine andere Erweiterung es schon nutzt.</summary>
    PaletteKeyPriority: Boolean;
    CheckKeyPriority: Boolean;
    /// <summary>Filter-Chips über der Liste (#422).</summary>
    FilterChips: Boolean;
    /// <summary>Lernende Gewichtung (#418).</summary>
    Learning: Boolean;
    /// <summary>Geerbte Member nachrangig und gruppiert (#419).</summary>
    GroupInherited: Boolean;
    /// <summary>Vorschau des gewählten Eintrags im Editor (#434).</summary>
    Preview: Boolean;
    /// <summary>Eigener Hover-Tooltip (#442).</summary>
    HoverTooltip: Boolean;
    /// <summary>Ab so vielen Millisekunden ohne Antwort gilt die IDE als hängend (#501).</summary>
    HangThresholdMs: Integer;
    /// <summary>Hinweis im Meldungsfenster nach langen Hängern (ab 2 s, #501).</summary>
    HangHint: Boolean;
    /// <summary>Extern geänderte Dateien ohne eigene Änderungen still neu laden (#536).</summary>
    ReloadExternal: Boolean;
    /// <summary>Klammer- und Blockpaare nach Tiefe färben (#514).</summary>
    PairColors: Boolean;
    /// <summary>Inaktive {$IFDEF}-Zweige im Editor ausgrauen (#615).</summary>
    InactiveDim: Boolean;
    /// <summary>Änderungen des Servers an nicht geöffneten Dateien: im Editor öffnen (an) oder
    /// direkt auf die Platte schreiben (aus, #397).</summary>
    OpenForEdits: Boolean;
    /// <summary>Parameternamen vor Literal-Argumenten als Inlay-Hints (#401); standardmäßig aus.</summary>
    InlayHints: Boolean;
    /// <summary>Pfad zu AtlasServer.exe; leer: neben dem Plugin bzw. Output\Win64\Debug\Bin.</summary>
    ServerPath: string;
    /// <summary>Blocklinien in den Paarfarben statt der Strukturhervorhebung der IDE (#514).</summary>
    PairGuides: Boolean;
    /// <summary>Probleme im Editor unterstreichen und im Meldungsfenster auflisten (#398).</summary>
    Problems: Boolean;
    /// <summary>Syntaxprüfung des Compilers nach dem Speichern (#548).</summary>
    CheckOnSave: Boolean;
    /// <summary>Wartezeit nach dem letzten Speichern.</summary>
    CheckOnSaveDelayMs: Integer;
    /// <summary>Höchstdauer einer Prüfung; darüber nur noch von Hand (Strg+Alt+F9).</summary>
    CheckOnSaveMaxMs: Integer;
    /// <summary>Tastenkürzel im Editor (#399, TShortCut, 0 = keins): Code-Aktionen, Auswahl erweitern und
    /// verkleinern, Gehe zu Implementierung und zu Typdefinition.</summary>
    ActionsKey: Integer;
    ExpandKey: Integer;
    ShrinkKey: Integer;
    ImplementationKey: Integer;
    TypeDefinitionKey: Integer;
    /// <summary>Die Editor-Kürzel auch belegen, wenn die IDE oder eine andere Erweiterung sie nutzt.</summary>
    EditorKeysPriority: Boolean;
    /// <summary>Schnellbefehle mit „/“ nach Enter und „///“-Gerüste beim Server auslösen (#399).</summary>
    SlashCommands: Boolean;
    /// <summary>Code-Vorlagen in der Vervollständigung (#51, completion.snippets).</summary>
    Snippets: Boolean;
    class function Defaults: TAtlasPluginSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    procedure Load(const AStore: IAtlasSettingsStore);
    procedure Save(const AStore: IAtlasSettingsStore);
  end;

implementation

uses
  System.Math;

function BoolValue(AValue: Boolean): Integer;
begin
  if AValue then
    Result := 1
  else
    Result := 0;
end;

{ TAtlasPluginSettings }

class function TAtlasPluginSettings.Defaults: TAtlasPluginSettings;
begin
  Result.Enabled := True;
  Result.VisibleRows := 9;
  Result.ListWidth := 0;
  Result.PanelWidth := 320;
  Result.PanelCollapsed := False;
  Result.AutoParentheses := True;
  Result.FixCase := True;
  Result.PaletteKey := $6050; // Strg+Umschalt+P
  Result.CheckKey := $C078; // Strg+Alt+F9
  Result.PaletteKeyPriority := False;
  Result.CheckKeyPriority := False;
  Result.FilterChips := True;
  Result.Learning := True;
  Result.GroupInherited := True;
  Result.Preview := False;
  Result.HoverTooltip := True;
  Result.HangThresholdMs := 500;
  Result.HangHint := True;
  Result.ReloadExternal := True;
  Result.PairColors := True;
  Result.InactiveDim := True;
  Result.OpenForEdits := True;
  Result.InlayHints := False;
  Result.ServerPath := '';
  Result.PairGuides := True;
  Result.Problems := True;
  // Die Prüfung in der IDE zeigt deren Fortschritt; Standard ist die Prüfung des Servers mit dcc (compiler.onSave).
  Result.CheckOnSave := False;
  Result.CheckOnSaveDelayMs := 2000;
  Result.CheckOnSaveMaxMs := 1500;
  Result.ActionsKey := $800D; // Alt+Enter
  Result.ExpandKey := $4057; // Strg+W
  Result.ShrinkKey := $6057; // Strg+Umschalt+W
  Result.ImplementationKey := $C049; // Strg+Alt+I
  Result.TypeDefinitionKey := 0;
  Result.EditorKeysPriority := False;
  Result.SlashCommands := True;
  Result.Snippets := True;
end;

procedure TAtlasPluginSettings.Normalize;
begin
  VisibleRows := EnsureRange(VisibleRows, MinVisibleRows, MaxVisibleRows);
  if ListWidth <> 0 then
    ListWidth := EnsureRange(ListWidth, MinListWidth, MaxListWidth);
  PanelWidth := EnsureRange(PanelWidth, MinPanelWidth, MaxPanelWidth);
  HangThresholdMs := EnsureRange(HangThresholdMs, MinHangThreshold, MaxHangThreshold);
  CheckOnSaveDelayMs := EnsureRange(CheckOnSaveDelayMs, MinCheckDelay, MaxCheckDelay);
  CheckOnSaveMaxMs := EnsureRange(CheckOnSaveMaxMs, MinCheckMax, MaxCheckMax);
end;

procedure TAtlasPluginSettings.Load(const AStore: IAtlasSettingsStore);
var
  Default: TAtlasPluginSettings;
begin
  Default := Defaults;
  Enabled := AStore.ReadInteger('Enabled', BoolValue(Default.Enabled)) <> 0;
  VisibleRows := AStore.ReadInteger('VisibleRows', Default.VisibleRows);
  ListWidth := AStore.ReadInteger('ListWidth', Default.ListWidth);
  PanelWidth := AStore.ReadInteger('PanelWidth', Default.PanelWidth);
  PanelCollapsed := AStore.ReadInteger('PanelCollapsed', BoolValue(Default.PanelCollapsed)) <> 0;
  AutoParentheses := AStore.ReadInteger('AutoParentheses', BoolValue(Default.AutoParentheses)) <> 0;
  FixCase := AStore.ReadInteger('FixCase', BoolValue(Default.FixCase)) <> 0;
  PaletteKey := AStore.ReadInteger('PaletteKey', Default.PaletteKey);
  CheckKey := AStore.ReadInteger('CheckKey', Default.CheckKey);
  PaletteKeyPriority := AStore.ReadInteger('PaletteKeyPriority', BoolValue(Default.PaletteKeyPriority)) <> 0;
  CheckKeyPriority := AStore.ReadInteger('CheckKeyPriority', BoolValue(Default.CheckKeyPriority)) <> 0;
  FilterChips := AStore.ReadInteger('FilterChips', BoolValue(Default.FilterChips)) <> 0;
  Learning := AStore.ReadInteger('Learning', BoolValue(Default.Learning)) <> 0;
  GroupInherited := AStore.ReadInteger('GroupInherited', BoolValue(Default.GroupInherited)) <> 0;
  Preview := AStore.ReadInteger('Preview', BoolValue(Default.Preview)) <> 0;
  HoverTooltip := AStore.ReadInteger('HoverTooltip', BoolValue(Default.HoverTooltip)) <> 0;
  HangThresholdMs := AStore.ReadInteger('HangThresholdMs', Default.HangThresholdMs);
  HangHint := AStore.ReadInteger('HangHint', BoolValue(Default.HangHint)) <> 0;
  ReloadExternal := AStore.ReadInteger('ReloadExternal', BoolValue(Default.ReloadExternal)) <> 0;
  PairColors := AStore.ReadInteger('PairColors', BoolValue(Default.PairColors)) <> 0;
  InactiveDim := AStore.ReadInteger('InactiveDim', BoolValue(Default.InactiveDim)) <> 0;
  OpenForEdits := AStore.ReadInteger('OpenForEdits', BoolValue(Default.OpenForEdits)) <> 0;
  InlayHints := AStore.ReadInteger('InlayHints', BoolValue(Default.InlayHints)) <> 0;
  ServerPath := Trim(AStore.ReadString('ServerPath', Default.ServerPath));
  PairGuides := AStore.ReadInteger('PairGuides', BoolValue(Default.PairGuides)) <> 0;
  Problems := AStore.ReadInteger('Problems', BoolValue(Default.Problems)) <> 0;
  CheckOnSave := AStore.ReadInteger('CheckOnSave', BoolValue(Default.CheckOnSave)) <> 0;
  CheckOnSaveDelayMs := AStore.ReadInteger('CheckOnSaveDelayMs', Default.CheckOnSaveDelayMs);
  CheckOnSaveMaxMs := AStore.ReadInteger('CheckOnSaveMaxMs', Default.CheckOnSaveMaxMs);
  ActionsKey := AStore.ReadInteger('ActionsKey', Default.ActionsKey);
  ExpandKey := AStore.ReadInteger('ExpandKey', Default.ExpandKey);
  ShrinkKey := AStore.ReadInteger('ShrinkKey', Default.ShrinkKey);
  ImplementationKey := AStore.ReadInteger('ImplementationKey', Default.ImplementationKey);
  TypeDefinitionKey := AStore.ReadInteger('TypeDefinitionKey', Default.TypeDefinitionKey);
  EditorKeysPriority := AStore.ReadInteger('EditorKeysPriority', BoolValue(Default.EditorKeysPriority)) <> 0;
  SlashCommands := AStore.ReadInteger('SlashCommands', BoolValue(Default.SlashCommands)) <> 0;
  Snippets := AStore.ReadInteger('Snippets', BoolValue(Default.Snippets)) <> 0;
  Normalize;
end;

procedure TAtlasPluginSettings.Save(const AStore: IAtlasSettingsStore);
begin
  Normalize;
  AStore.WriteInteger('Enabled', BoolValue(Enabled));
  AStore.WriteInteger('VisibleRows', VisibleRows);
  AStore.WriteInteger('ListWidth', ListWidth);
  AStore.WriteInteger('PanelWidth', PanelWidth);
  AStore.WriteInteger('PanelCollapsed', BoolValue(PanelCollapsed));
  AStore.WriteInteger('AutoParentheses', BoolValue(AutoParentheses));
  AStore.WriteInteger('FixCase', BoolValue(FixCase));
  AStore.WriteInteger('PaletteKey', PaletteKey);
  AStore.WriteInteger('CheckKey', CheckKey);
  AStore.WriteInteger('PaletteKeyPriority', BoolValue(PaletteKeyPriority));
  AStore.WriteInteger('CheckKeyPriority', BoolValue(CheckKeyPriority));
  AStore.WriteInteger('FilterChips', BoolValue(FilterChips));
  AStore.WriteInteger('Learning', BoolValue(Learning));
  AStore.WriteInteger('GroupInherited', BoolValue(GroupInherited));
  AStore.WriteInteger('Preview', BoolValue(Preview));
  AStore.WriteInteger('HoverTooltip', BoolValue(HoverTooltip));
  AStore.WriteInteger('HangThresholdMs', HangThresholdMs);
  AStore.WriteInteger('HangHint', BoolValue(HangHint));
  AStore.WriteInteger('ReloadExternal', BoolValue(ReloadExternal));
  AStore.WriteInteger('PairColors', BoolValue(PairColors));
  AStore.WriteInteger('InactiveDim', BoolValue(InactiveDim));
  AStore.WriteInteger('OpenForEdits', BoolValue(OpenForEdits));
  AStore.WriteInteger('InlayHints', BoolValue(InlayHints));
  AStore.WriteString('ServerPath', Trim(ServerPath));
  AStore.WriteInteger('PairGuides', BoolValue(PairGuides));
  AStore.WriteInteger('Problems', BoolValue(Problems));
  AStore.WriteInteger('CheckOnSave', BoolValue(CheckOnSave));
  AStore.WriteInteger('CheckOnSaveDelayMs', CheckOnSaveDelayMs);
  AStore.WriteInteger('CheckOnSaveMaxMs', CheckOnSaveMaxMs);
  AStore.WriteInteger('ActionsKey', ActionsKey);
  AStore.WriteInteger('ExpandKey', ExpandKey);
  AStore.WriteInteger('ShrinkKey', ShrinkKey);
  AStore.WriteInteger('ImplementationKey', ImplementationKey);
  AStore.WriteInteger('TypeDefinitionKey', TypeDefinitionKey);
  AStore.WriteInteger('EditorKeysPriority', BoolValue(EditorKeysPriority));
  AStore.WriteInteger('SlashCommands', BoolValue(SlashCommands));
  AStore.WriteInteger('Snippets', BoolValue(Snippets));
end;

end.
