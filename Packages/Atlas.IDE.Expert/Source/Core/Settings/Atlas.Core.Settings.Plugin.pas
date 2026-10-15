unit Atlas.Core.Settings.Plugin;

// Einstellungen des IDE-Plugins (#227, Teil Vervollständigung), ohne VCL und
// ohne Registry: Vorgaben, Grenzen, Lesen und Schreiben über einen Speicher.
// Die IDE-Schicht speichert in HKCU\Software\Atlas\IdePlugin, Tests im
// Arbeitsspeicher. Breiten in logischen Pixeln (96 dpi, #412).

interface

uses
  System.SysUtils,
  Atlas.Core.Style.Palette;

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
    /// <summary>Wie TAtlasTimeLimit.MinMs/MaxMs (#493).</summary>
    MinProviderTimeLimit = 50;
    MaxProviderTimeLimit = 5000;
    MinCheckDelay = 500;
    MaxCheckDelay = 10000;
    MinCheckMax = 200;
    MaxCheckMax = 20000;
    MaxXmlDocLines = 50;
    /// <summary>Verzögerung bis zum automatischen Öffnen der Liste (ARG-046, #227); 0 = sofort.</summary>
    MaxOpenDelay = 2000;
    /// <summary>Speichergrenze des Symbolindex im Server (#492); 0 = unbegrenzt.</summary>
    MaxMemoryBudgetMb = 65536;
    /// <summary>Grenzen für safeMode.startupTimeoutMs und safeMode.keepSettingsHistory (#722).</summary>
    MinSafeStartupTimeout = 1000;
    MaxSafeStartupTimeout = 120000;
    MaxSafeSettingsHistory = 50;
    /// <summary>Grenzen für undo.multiFile.depth und undo.multiFile.maxSizeMb (#721).</summary>
    MinUndoDepth = 1;
    MaxUndoDepth = 200;
    MinUndoMaxSizeMb = 1;
    MaxUndoMaxSizeMb = 1024;
    MinPairGuideWidth = 1;
    MaxPairGuideWidth = 3;
    MinPairGuideOpacity = 10;
    MaxPairGuideOpacity = 100;
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
    /// <summary>Übernehmen über "(", ";" und "." (#429).</summary>
    CommitCharacters: Boolean;
    /// <summary>Unit beim Übernehmen automatisch in uses eintragen (#180).</summary>
    AutoUses: Boolean;
    /// <summary>Parameter-Hint bei "(" und "," (#436).</summary>
    ParameterHints: Boolean;
    /// <summary>Millisekunden zwischen automatischem Auslösen (".") und dem Öffnen der Liste (ARG-046).</summary>
    OpenDelayMs: Integer;
    /// <summary>Tastenkürzel der Befehlspalette und der Syntaxprüfung (TShortCut, 0 = keins, #494).</summary>
    PaletteKey: Integer;
    CheckKey: Integer;
    /// <summary>Kürzel auch belegen, wenn die IDE oder eine andere Erweiterung es schon nutzt.</summary>
    PaletteKeyPriority: Boolean;
    CheckKeyPriority: Boolean;
    /// <summary>Eigene Tasten für Vervollständigung und Parameter-Hint (#494), 0 = die Taste der IDE
    /// (Strg+Leer bzw. Strg+Umschalt+Leer über Code Insight); sonst belegt Atlas sie zusätzlich.</summary>
    CompletionKey: Integer;
    SignatureKey: Integer;
    CompletionKeyPriority: Boolean;
    SignatureKeyPriority: Boolean;
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
    /// <summary>Zeitlimit für Aufrufe von Datenquellen aus dem Hauptthread (#493); länger gilt als Fehler.</summary>
    ProviderTimeLimitMs: Integer;
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
    /// <summary>Schlüsselwörter der Anweisung (if, then, else, for, do, procedure …) in der Farbe ihres
    /// Blocks; Blocklinien beginnen an der Anweisung (#653). Wirkt nur mit PairColors.</summary>
    PairOwners: Boolean;
    /// <summary>Breite der Blocklinien in Pixeln bei 100 % (1–3, #653).</summary>
    PairGuideWidth: Integer;
    /// <summary>Deckkraft der Blocklinien in Prozent; der Rest ist Hintergrund.</summary>
    PairGuideOpacity: Integer;
    /// <summary>Eigene Paarfarben je Thema („#RRGGBB,…“, fünf Stück); leer = Standardpalette.</summary>
    PairColorsLight: string;
    PairColorsDark: string;
    /// <summary>Probleme im Editor unterstreichen und im Meldungsfenster auflisten (#398).</summary>
    Problems: Boolean;
    /// <summary>Probleme zusätzlich im Meldungsfenster auflisten (Gruppe „Atlas-Probleme“); nur mit Problems.</summary>
    ProblemsList: Boolean;
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
    /// <summary>Live Templates der IDE als Code-Vorlagen einlesen (#51, completion.importIdeTemplates).</summary>
    ImportIdeTemplates: Boolean;
    /// <summary>Umfang des Symbolindex für alle Projekte (#652); index in atlas.json hat Vorrang.</summary>
    IndexProjectGroup: Boolean;
    IndexSearchPaths: Boolean;
    IndexLibraryPaths: Boolean;
    /// <summary>Verwendungen der Bezeichner mit indizieren (#492, index.usages).</summary>
    IndexUsages: Boolean;
    /// <summary>Speichergrenze des Symbolindex in MB (#492, memoryBudgetMb); darüber lagert der Server
    /// zuerst die Verwendungen aus. 0 = unbegrenzt.</summary>
    MemoryBudgetMb: Integer;
    /// <summary>XMLDoc in Tooltip und Detailpanel vollständig (#654); aus = Kurzform. hints in atlas.json
    /// hat Vorrang.</summary>
    XmlDocFull: Boolean;
    /// <summary>Höchstens so viele Zeilen Doku ohne Scrollen, 0 = bis zur Bildschirmhöhe (#654).</summary>
    XmlDocMaxLines: Integer;
    /// <summary>Atlas-Feld in der Statusleiste (#591, statusField.enabled).</summary>
    StatusField: Boolean;
    /// <summary>Kennungen der Zeilen, die im Fenster des Felds nicht erscheinen, durch Komma getrennt
    /// (#591, statusField.hidden).</summary>
    StatusFieldHidden: string;
    /// <summary>Kurztext neben „Atlas“ (#591, statusField.showSummary).</summary>
    StatusFieldSummary: Boolean;
    /// <summary>Doppelklick auf das Feld öffnet die Schnellschalter wie ein Rechtsklick
    /// (statusField.doubleClick).</summary>
    StatusFieldDoubleClick: Boolean;
    /// <summary>Tastenkürzel für das Fenster der Schnellschalter (#604, TShortCut, 0 = keins) und Vorrang wie
    /// bei den anderen Atlas-Tasten (#494).</summary>
    QuickToggleKey: Integer;
    QuickToggleKeyPriority: Boolean;
    /// <summary>Abgesicherter Start (#722): nach einem Absturz fragen (safeMode.askAfterCrash).</summary>
    SafeAskAfterCrash: Boolean;
    /// <summary>Nach zwei Abstürzen kurz hintereinander ohne Rückfrage abgesichert
    /// (safeMode.autoAfterRepeatedCrash).</summary>
    SafeAutoAfterRepeatedCrash: Boolean;
    /// <summary>Taste beim Laden für den abgesicherten Start: shift, ctrl, none (safeMode.startupKey).</summary>
    SafeStartupKey: string;
    /// <summary>Längste Ladezeit; länger gilt beim nächsten Start wie ein Absturz
    /// (safeMode.startupTimeoutMs).</summary>
    SafeStartupTimeoutMs: Integer;
    /// <summary>Gemerkte Einstellungsstände zum Zurücksetzen (safeMode.keepSettingsHistory).</summary>
    SafeKeepSettingsHistory: Integer;
    /// <summary>Dateiübergreifendes Zurücknehmen von Atlas-Änderungen (#721, undo.multiFile).</summary>
    UndoMultiFile: Boolean;
    /// <summary>Anzahl gemerkter Änderungssätze (undo.multiFile.depth).</summary>
    UndoMultiFileDepth: Integer;
    /// <summary>Protokoll über einen IDE-Neustart hinweg sichern (undo.multiFile.persist).</summary>
    UndoMultiFilePersist: Boolean;
    /// <summary>Größte Größe des gesicherten Protokolls in MB (undo.multiFile.maxSizeMb).</summary>
    UndoMultiFileMaxSizeMb: Integer;
    /// <summary>partial oder abort (undo.multiFile.onConflict).</summary>
    UndoMultiFileOnConflict: string;
    /// <summary>recycleBin, delete oder keep (undo.multiFile.newFiles).</summary>
    UndoMultiFileNewFiles: string;
    /// <summary>Tastenkürzel „Letzte Atlas-Änderung zurücknehmen“ und „… wiederherstellen“ (#721, wie die
    /// Editor-Kürzel aus #399 änderbar, TShortCut, 0 = keins).</summary>
    UndoKey: Integer;
    RedoKey: Integer;
    /// <summary>Einmal täglich nach einer neuen Version sehen (#495, updates.check); Vorgabe aus, beim ersten
    /// Start wird gefragt.</summary>
    UpdatesCheck: Boolean;
    /// <summary>Fehlerbericht anonymisieren (#108, diagnostics.bugReport.anonymize): Pfade, Benutzername und
    /// Bezeichner ersetzen; Vorgabe an.</summary>
    BugReportAnonymize: Boolean;
    class function Defaults: TAtlasPluginSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    procedure Load(const AStore: IAtlasSettingsStore);
    procedure Save(const AStore: IAtlasSettingsStore);
    /// <summary>Einstellungen für den Server als JSON-Objekt im Format von atlas.json (#652); geht als
    /// initializationOptions.settings.atlas und mit workspace/didChangeConfiguration an den Server.</summary>
    function ServerSettingsJson: string;
  end;

implementation

uses
  System.Math;

// Eigene Paarfarben einheitlich schreiben; ungültig = leer (Standardpalette).
function NormalPairs(const AText: string): string;
var
  Pairs: TAtlasPairColors;
begin
  if TAtlasColors.ParsePairs(AText, Pairs) then
    Result := TAtlasColors.PairsText(Pairs)
  else
    Result := '';
end;

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
  Result.CommitCharacters := True;
  Result.AutoUses := True;
  Result.ParameterHints := True;
  Result.OpenDelayMs := 150;
  Result.PaletteKey := $6050; // Strg+Umschalt+P
  Result.CheckKey := $C078; // Strg+Alt+F9
  Result.PaletteKeyPriority := False;
  Result.CheckKeyPriority := False;
  Result.CompletionKey := 0;
  Result.SignatureKey := 0;
  Result.CompletionKeyPriority := False;
  Result.SignatureKeyPriority := False;
  Result.FilterChips := True;
  Result.Learning := True;
  Result.GroupInherited := True;
  Result.Preview := False;
  Result.HoverTooltip := True;
  Result.HangThresholdMs := 500;
  Result.ProviderTimeLimitMs := 200;
  Result.HangHint := True;
  Result.ReloadExternal := True;
  Result.PairColors := True;
  Result.InactiveDim := True;
  Result.OpenForEdits := True;
  Result.InlayHints := False;
  Result.ServerPath := '';
  Result.PairGuides := True;
  Result.PairOwners := True;
  Result.PairGuideWidth := 1;
  Result.PairGuideOpacity := 75;
  Result.PairColorsLight := '';
  Result.PairColorsDark := '';
  Result.Problems := True;
  Result.ProblemsList := True;
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
  Result.ImportIdeTemplates := True;
  // Wie die Vorgaben im Schema (atlas.schema.json, index).
  Result.IndexProjectGroup := True;
  Result.IndexSearchPaths := True;
  Result.IndexLibraryPaths := False;
  Result.IndexUsages := True;
  Result.MemoryBudgetMb := 256;
  Result.XmlDocFull := True;
  Result.XmlDocMaxLines := 0;
  Result.StatusField := True;
  Result.StatusFieldHidden := '';
  Result.StatusFieldSummary := True;
  Result.StatusFieldDoubleClick := True;
  Result.QuickToggleKey := $E041; // Strg+Umschalt+Alt+A
  Result.QuickToggleKeyPriority := False;
  Result.SafeAskAfterCrash := True;
  Result.SafeAutoAfterRepeatedCrash := True;
  Result.SafeStartupKey := 'shift';
  Result.SafeStartupTimeoutMs := 10000;
  Result.SafeKeepSettingsHistory := 5;
  Result.UndoMultiFile := True;
  Result.UndoMultiFileDepth := 20;
  Result.UndoMultiFilePersist := True;
  Result.UndoMultiFileMaxSizeMb := 50;
  Result.UndoMultiFileOnConflict := 'partial';
  Result.UndoMultiFileNewFiles := 'recycleBin';
  Result.UndoKey := $C05A; // Strg+Alt+Z
  Result.RedoKey := $E05A; // Strg+Alt+Umschalt+Z
  Result.UpdatesCheck := False;
  Result.BugReportAnonymize := True;
end;

procedure TAtlasPluginSettings.Normalize;
begin
  VisibleRows := EnsureRange(VisibleRows, MinVisibleRows, MaxVisibleRows);
  if ListWidth <> 0 then
    ListWidth := EnsureRange(ListWidth, MinListWidth, MaxListWidth);
  PanelWidth := EnsureRange(PanelWidth, MinPanelWidth, MaxPanelWidth);
  HangThresholdMs := EnsureRange(HangThresholdMs, MinHangThreshold, MaxHangThreshold);
  ProviderTimeLimitMs := EnsureRange(ProviderTimeLimitMs, MinProviderTimeLimit, MaxProviderTimeLimit);
  CheckOnSaveDelayMs := EnsureRange(CheckOnSaveDelayMs, MinCheckDelay, MaxCheckDelay);
  CheckOnSaveMaxMs := EnsureRange(CheckOnSaveMaxMs, MinCheckMax, MaxCheckMax);
  XmlDocMaxLines := EnsureRange(XmlDocMaxLines, 0, MaxXmlDocLines);
  OpenDelayMs := EnsureRange(OpenDelayMs, 0, MaxOpenDelay);
  MemoryBudgetMb := EnsureRange(MemoryBudgetMb, 0, MaxMemoryBudgetMb);
  // TShortCut ist ein Word.
  PaletteKey := EnsureRange(PaletteKey, 0, $FFFF);
  CheckKey := EnsureRange(CheckKey, 0, $FFFF);
  CompletionKey := EnsureRange(CompletionKey, 0, $FFFF);
  SignatureKey := EnsureRange(SignatureKey, 0, $FFFF);
  QuickToggleKey := EnsureRange(QuickToggleKey, 0, $FFFF);
  SafeStartupTimeoutMs := EnsureRange(SafeStartupTimeoutMs, MinSafeStartupTimeout, MaxSafeStartupTimeout);
  SafeKeepSettingsHistory := EnsureRange(SafeKeepSettingsHistory, 0, MaxSafeSettingsHistory);
  SafeStartupKey := LowerCase(Trim(SafeStartupKey));
  if (SafeStartupKey <> 'shift') and (SafeStartupKey <> 'ctrl') and (SafeStartupKey <> 'none') then
    SafeStartupKey := 'shift';
  UndoMultiFileDepth := EnsureRange(UndoMultiFileDepth, MinUndoDepth, MaxUndoDepth);
  UndoMultiFileMaxSizeMb := EnsureRange(UndoMultiFileMaxSizeMb, MinUndoMaxSizeMb, MaxUndoMaxSizeMb);
  if SameText(Trim(UndoMultiFileOnConflict), 'abort') then
    UndoMultiFileOnConflict := 'abort'
  else
    UndoMultiFileOnConflict := 'partial';
  if SameText(Trim(UndoMultiFileNewFiles), 'delete') then
    UndoMultiFileNewFiles := 'delete'
  else if SameText(Trim(UndoMultiFileNewFiles), 'keep') then
    UndoMultiFileNewFiles := 'keep'
  else
    UndoMultiFileNewFiles := 'recycleBin';
  UndoKey := EnsureRange(UndoKey, 0, $FFFF);
  RedoKey := EnsureRange(RedoKey, 0, $FFFF);
  PairGuideWidth := EnsureRange(PairGuideWidth, MinPairGuideWidth, MaxPairGuideWidth);
  PairGuideOpacity := EnsureRange(PairGuideOpacity, MinPairGuideOpacity, MaxPairGuideOpacity);
  PairColorsLight := NormalPairs(PairColorsLight);
  PairColorsDark := NormalPairs(PairColorsDark);
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
  CommitCharacters := AStore.ReadInteger('CommitCharacters', BoolValue(Default.CommitCharacters)) <> 0;
  AutoUses := AStore.ReadInteger('AutoUses', BoolValue(Default.AutoUses)) <> 0;
  ParameterHints := AStore.ReadInteger('ParameterHints', BoolValue(Default.ParameterHints)) <> 0;
  OpenDelayMs := AStore.ReadInteger('OpenDelayMs', Default.OpenDelayMs);
  PaletteKey := AStore.ReadInteger('PaletteKey', Default.PaletteKey);
  CheckKey := AStore.ReadInteger('CheckKey', Default.CheckKey);
  PaletteKeyPriority := AStore.ReadInteger('PaletteKeyPriority', BoolValue(Default.PaletteKeyPriority)) <> 0;
  CheckKeyPriority := AStore.ReadInteger('CheckKeyPriority', BoolValue(Default.CheckKeyPriority)) <> 0;
  CompletionKey := AStore.ReadInteger('CompletionKey', Default.CompletionKey);
  SignatureKey := AStore.ReadInteger('SignatureKey', Default.SignatureKey);
  CompletionKeyPriority := AStore.ReadInteger('CompletionKeyPriority', BoolValue(Default.CompletionKeyPriority)) <> 0;
  SignatureKeyPriority := AStore.ReadInteger('SignatureKeyPriority', BoolValue(Default.SignatureKeyPriority)) <> 0;
  FilterChips := AStore.ReadInteger('FilterChips', BoolValue(Default.FilterChips)) <> 0;
  Learning := AStore.ReadInteger('Learning', BoolValue(Default.Learning)) <> 0;
  GroupInherited := AStore.ReadInteger('GroupInherited', BoolValue(Default.GroupInherited)) <> 0;
  Preview := AStore.ReadInteger('Preview', BoolValue(Default.Preview)) <> 0;
  HoverTooltip := AStore.ReadInteger('HoverTooltip', BoolValue(Default.HoverTooltip)) <> 0;
  HangThresholdMs := AStore.ReadInteger('HangThresholdMs', Default.HangThresholdMs);
  ProviderTimeLimitMs := AStore.ReadInteger('ProviderTimeLimitMs', Default.ProviderTimeLimitMs);
  HangHint := AStore.ReadInteger('HangHint', BoolValue(Default.HangHint)) <> 0;
  ReloadExternal := AStore.ReadInteger('ReloadExternal', BoolValue(Default.ReloadExternal)) <> 0;
  PairColors := AStore.ReadInteger('PairColors', BoolValue(Default.PairColors)) <> 0;
  InactiveDim := AStore.ReadInteger('InactiveDim', BoolValue(Default.InactiveDim)) <> 0;
  OpenForEdits := AStore.ReadInteger('OpenForEdits', BoolValue(Default.OpenForEdits)) <> 0;
  InlayHints := AStore.ReadInteger('InlayHints', BoolValue(Default.InlayHints)) <> 0;
  ServerPath := Trim(AStore.ReadString('ServerPath', Default.ServerPath));
  PairGuides := AStore.ReadInteger('PairGuides', BoolValue(Default.PairGuides)) <> 0;
  PairOwners := AStore.ReadInteger('PairOwners', BoolValue(Default.PairOwners)) <> 0;
  PairGuideWidth := AStore.ReadInteger('PairGuideWidth', Default.PairGuideWidth);
  PairGuideOpacity := AStore.ReadInteger('PairGuideOpacity', Default.PairGuideOpacity);
  PairColorsLight := AStore.ReadString('PairColorsLight', Default.PairColorsLight);
  PairColorsDark := AStore.ReadString('PairColorsDark', Default.PairColorsDark);
  Problems := AStore.ReadInteger('Problems', BoolValue(Default.Problems)) <> 0;
  ProblemsList := AStore.ReadInteger('ProblemsList', BoolValue(Default.ProblemsList)) <> 0;
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
  ImportIdeTemplates := AStore.ReadInteger('ImportIdeTemplates', BoolValue(Default.ImportIdeTemplates)) <> 0;
  IndexProjectGroup := AStore.ReadInteger('IndexProjectGroup', BoolValue(Default.IndexProjectGroup)) <> 0;
  IndexSearchPaths := AStore.ReadInteger('IndexSearchPaths', BoolValue(Default.IndexSearchPaths)) <> 0;
  IndexLibraryPaths := AStore.ReadInteger('IndexLibraryPaths', BoolValue(Default.IndexLibraryPaths)) <> 0;
  IndexUsages := AStore.ReadInteger('IndexUsages', BoolValue(Default.IndexUsages)) <> 0;
  MemoryBudgetMb := AStore.ReadInteger('MemoryBudgetMb', Default.MemoryBudgetMb);
  XmlDocFull := AStore.ReadInteger('XmlDocFull', BoolValue(Default.XmlDocFull)) <> 0;
  XmlDocMaxLines := AStore.ReadInteger('XmlDocMaxLines', Default.XmlDocMaxLines);
  StatusField := AStore.ReadInteger('StatusField', BoolValue(Default.StatusField)) <> 0;
  StatusFieldHidden := Trim(AStore.ReadString('StatusFieldHidden', Default.StatusFieldHidden));
  StatusFieldSummary := AStore.ReadInteger('StatusFieldSummary', BoolValue(Default.StatusFieldSummary)) <> 0;
  StatusFieldDoubleClick :=
    AStore.ReadInteger('StatusFieldDoubleClick', BoolValue(Default.StatusFieldDoubleClick)) <> 0;
  QuickToggleKey := AStore.ReadInteger('QuickToggleKey', Default.QuickToggleKey);
  QuickToggleKeyPriority :=
    AStore.ReadInteger('QuickToggleKeyPriority', BoolValue(Default.QuickToggleKeyPriority)) <> 0;
  SafeAskAfterCrash := AStore.ReadInteger('SafeAskAfterCrash', BoolValue(Default.SafeAskAfterCrash)) <> 0;
  SafeAutoAfterRepeatedCrash :=
    AStore.ReadInteger('SafeAutoAfterRepeatedCrash', BoolValue(Default.SafeAutoAfterRepeatedCrash)) <> 0;
  SafeStartupKey := AStore.ReadString('SafeStartupKey', Default.SafeStartupKey);
  SafeStartupTimeoutMs := AStore.ReadInteger('SafeStartupTimeoutMs', Default.SafeStartupTimeoutMs);
  SafeKeepSettingsHistory := AStore.ReadInteger('SafeKeepSettingsHistory', Default.SafeKeepSettingsHistory);
  UndoMultiFile := AStore.ReadInteger('UndoMultiFile', BoolValue(Default.UndoMultiFile)) <> 0;
  UndoMultiFileDepth := AStore.ReadInteger('UndoMultiFileDepth', Default.UndoMultiFileDepth);
  UndoMultiFilePersist := AStore.ReadInteger('UndoMultiFilePersist', BoolValue(Default.UndoMultiFilePersist)) <> 0;
  UndoMultiFileMaxSizeMb := AStore.ReadInteger('UndoMultiFileMaxSizeMb', Default.UndoMultiFileMaxSizeMb);
  UndoMultiFileOnConflict := AStore.ReadString('UndoMultiFileOnConflict', Default.UndoMultiFileOnConflict);
  UndoMultiFileNewFiles := AStore.ReadString('UndoMultiFileNewFiles', Default.UndoMultiFileNewFiles);
  UndoKey := AStore.ReadInteger('UndoKey', Default.UndoKey);
  RedoKey := AStore.ReadInteger('RedoKey', Default.RedoKey);
  UpdatesCheck := AStore.ReadInteger('UpdatesCheck', BoolValue(Default.UpdatesCheck)) <> 0;
  BugReportAnonymize := AStore.ReadInteger('BugReportAnonymize', BoolValue(Default.BugReportAnonymize)) <> 0;
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
  AStore.WriteInteger('CommitCharacters', BoolValue(CommitCharacters));
  AStore.WriteInteger('AutoUses', BoolValue(AutoUses));
  AStore.WriteInteger('ParameterHints', BoolValue(ParameterHints));
  AStore.WriteInteger('OpenDelayMs', OpenDelayMs);
  AStore.WriteInteger('PaletteKey', PaletteKey);
  AStore.WriteInteger('CheckKey', CheckKey);
  AStore.WriteInteger('PaletteKeyPriority', BoolValue(PaletteKeyPriority));
  AStore.WriteInteger('CheckKeyPriority', BoolValue(CheckKeyPriority));
  AStore.WriteInteger('CompletionKey', CompletionKey);
  AStore.WriteInteger('SignatureKey', SignatureKey);
  AStore.WriteInteger('CompletionKeyPriority', BoolValue(CompletionKeyPriority));
  AStore.WriteInteger('SignatureKeyPriority', BoolValue(SignatureKeyPriority));
  AStore.WriteInteger('FilterChips', BoolValue(FilterChips));
  AStore.WriteInteger('Learning', BoolValue(Learning));
  AStore.WriteInteger('GroupInherited', BoolValue(GroupInherited));
  AStore.WriteInteger('Preview', BoolValue(Preview));
  AStore.WriteInteger('HoverTooltip', BoolValue(HoverTooltip));
  AStore.WriteInteger('HangThresholdMs', HangThresholdMs);
  AStore.WriteInteger('ProviderTimeLimitMs', ProviderTimeLimitMs);
  AStore.WriteInteger('HangHint', BoolValue(HangHint));
  AStore.WriteInteger('ReloadExternal', BoolValue(ReloadExternal));
  AStore.WriteInteger('PairColors', BoolValue(PairColors));
  AStore.WriteInteger('InactiveDim', BoolValue(InactiveDim));
  AStore.WriteInteger('OpenForEdits', BoolValue(OpenForEdits));
  AStore.WriteInteger('InlayHints', BoolValue(InlayHints));
  AStore.WriteString('ServerPath', Trim(ServerPath));
  AStore.WriteInteger('PairGuides', BoolValue(PairGuides));
  AStore.WriteInteger('PairOwners', BoolValue(PairOwners));
  AStore.WriteInteger('PairGuideWidth', PairGuideWidth);
  AStore.WriteInteger('PairGuideOpacity', PairGuideOpacity);
  AStore.WriteString('PairColorsLight', PairColorsLight);
  AStore.WriteString('PairColorsDark', PairColorsDark);
  AStore.WriteInteger('Problems', BoolValue(Problems));
  AStore.WriteInteger('ProblemsList', BoolValue(ProblemsList));
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
  AStore.WriteInteger('ImportIdeTemplates', BoolValue(ImportIdeTemplates));
  AStore.WriteInteger('IndexProjectGroup', BoolValue(IndexProjectGroup));
  AStore.WriteInteger('IndexSearchPaths', BoolValue(IndexSearchPaths));
  AStore.WriteInteger('IndexLibraryPaths', BoolValue(IndexLibraryPaths));
  AStore.WriteInteger('IndexUsages', BoolValue(IndexUsages));
  AStore.WriteInteger('MemoryBudgetMb', MemoryBudgetMb);
  AStore.WriteInteger('XmlDocFull', BoolValue(XmlDocFull));
  AStore.WriteInteger('XmlDocMaxLines', XmlDocMaxLines);
  AStore.WriteInteger('StatusField', BoolValue(StatusField));
  AStore.WriteString('StatusFieldHidden', Trim(StatusFieldHidden));
  AStore.WriteInteger('StatusFieldSummary', BoolValue(StatusFieldSummary));
  AStore.WriteInteger('StatusFieldDoubleClick', BoolValue(StatusFieldDoubleClick));
  AStore.WriteInteger('QuickToggleKey', QuickToggleKey);
  AStore.WriteInteger('QuickToggleKeyPriority', BoolValue(QuickToggleKeyPriority));
  AStore.WriteInteger('SafeAskAfterCrash', BoolValue(SafeAskAfterCrash));
  AStore.WriteInteger('SafeAutoAfterRepeatedCrash', BoolValue(SafeAutoAfterRepeatedCrash));
  AStore.WriteString('SafeStartupKey', SafeStartupKey);
  AStore.WriteInteger('SafeStartupTimeoutMs', SafeStartupTimeoutMs);
  AStore.WriteInteger('SafeKeepSettingsHistory', SafeKeepSettingsHistory);
  AStore.WriteInteger('UndoMultiFile', BoolValue(UndoMultiFile));
  AStore.WriteInteger('UndoMultiFileDepth', UndoMultiFileDepth);
  AStore.WriteInteger('UndoMultiFilePersist', BoolValue(UndoMultiFilePersist));
  AStore.WriteInteger('UndoMultiFileMaxSizeMb', UndoMultiFileMaxSizeMb);
  AStore.WriteString('UndoMultiFileOnConflict', UndoMultiFileOnConflict);
  AStore.WriteString('UndoMultiFileNewFiles', UndoMultiFileNewFiles);
  AStore.WriteInteger('UndoKey', UndoKey);
  AStore.WriteInteger('RedoKey', RedoKey);
  AStore.WriteInteger('UpdatesCheck', BoolValue(UpdatesCheck));
  AStore.WriteInteger('BugReportAnonymize', BoolValue(BugReportAnonymize));
end;

function JsonBool(AValue: Boolean): string;
begin
  if AValue then
    Result := 'true'
  else
    Result := 'false';
end;

function TAtlasPluginSettings.ServerSettingsJson: string;
begin
  Result := '{"index":{"projectGroup":' + JsonBool(IndexProjectGroup) + ',"searchPaths":' +
    JsonBool(IndexSearchPaths) + ',"libraryPaths":' + JsonBool(IndexLibraryPaths) + ',"usages":' +
    JsonBool(IndexUsages) + '},"memoryBudgetMb":' + IntToStr(EnsureRange(MemoryBudgetMb, 0, MaxMemoryBudgetMb)) +
    ',"hints":{"xmlDocFull":' +
    JsonBool(XmlDocFull) + ',"xmlDocMaxLines":' + IntToStr(EnsureRange(XmlDocMaxLines, 0, MaxXmlDocLines)) + '}}';
end;

end.
