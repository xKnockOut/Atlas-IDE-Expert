unit Atlas.IDE.Foundation.Settings;

// Einstellungen des Plugins in der Registry (HKCU\Software\Atlas\IdePlugin,
// #227) und der aktuelle Stand für alle Teile des Plugins. Gelesen wird
// einmal beim ersten Zugriff, geschrieben über Update (Optionsseite, gezogene
// Breiten, eingeklapptes Panel).
// Schnellschalter (#604): Current liefert die wirksamen Werte, also die
// gespeicherten mit den Sitzungswerten darüber (nur für diese Sitzung, „Alles
// aus“); Stored die gespeicherten für Optionsseite und Update. Sitzungswerte
// landen nie in der Registry.
// Ort der Einstellungen: Index, Speicher, XMLDoc, Inlay-Hints, Schnellbefehle
// und Kompilieren nach dem Speichern gelten auch für den Server und liegen in
// %APPDATA%\Atlas\settings.json (TAtlasRoutedSettingsStore); der Server liest
// die Datei selbst und beobachtet sie. Alte Werte aus der Registry übernimmt
// das erste Lesen einmal in die Datei.
// Abgesicherter Start (#722): Vor jeder gespeicherten Änderung kommt der alte
// Stand in die Einstellungsstände (%APPDATA%\Atlas\settings-history.json),
// höchstens safeMode.keepSettingsHistory; Restore setzt auf einen davon zurück.
// Experimentelle Funktionen (#834): Ohne Hauptschalter experimental.enabled
// liefert Current für jede Einstellung mit x-experimental die Vorgabe; Stored
// behält den gespeicherten Wert.
// Modul-Schalter (#1454): Ist ein Modul aus, liefert Current für jede
// Einstellung des Moduls „aus“ (TAtlasModuleSwitches); Stored behält die
// gespeicherten Werte.
// Umbenannte Einstellungen (#1280, x-renamedFrom): Vor dem ersten Lesen
// übernimmt TAtlasSettingsRenames frühere Registry-Namen (z. B.
// WelcomePageIssuesTracker → IssuesTracker) und entfernt sie; jede Übernahme
// steht einmal im Protokoll.
// Abfragen (#1262): Ein früheres issues.query (Registry IssuesQuery bzw.
// WelcomePageIssuesQuery) wird einmal zur Abfrage „Standard“ in
// issues.queries (settings.json); der Registry-Name geht erst, wenn die Datei
// geschrieben ist.

interface

uses
  System.SysUtils,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Problems.InlineHints,
  Atlas.Core.Editor.SelectionMatches,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.QuickToggles,
  Atlas.Core.Settings.ModuleSwitches,
  Atlas.Core.Settings.QueryMigration;

type
  TAtlasIdeSettings = class
  private class var
    FOnChanged: TProc;
  private
    class procedure EnsureLoaded; static;
    class procedure Changed; static;
  public
    /// <summary>Globale Einstellungsdatei; öffentlich für die Seite Prüfregeln und das Fenster Atlas-Prüfung
    /// (#909), die Regeln ohne Projekt dort speichern.</summary>
    class function GlobalFile: string; static;
    /// <summary>False, wenn die Datei da, aber nicht lesbar ist; dann wird sie auch nicht geschrieben.
    /// Öffentlich für die gezielten Änderungen der Prüfregeln (#909).</summary>
    class function LoadGlobal(out AContent: TAtlasTextFileContent): Boolean; static;
    class procedure SaveGlobal(const AContent: TAtlasTextFileContent; const AText: string); static;
    /// <summary>Wirksame Werte: gespeichert, darüber die Sitzungswerte der Schnellschalter (#604).</summary>
    class function Current: TAtlasPluginSettings; static;
    /// <summary>Gespeicherte Werte (Registry) ohne Sitzungswerte; Grundlage für Optionsseite und Update.</summary>
    class function Stored: TAtlasPluginSettings; static;
    /// <summary>Plugin eingeschaltet und Inlay-Hints an; ohne Kopie des Einstellungsrecords (P-10).</summary>
    class function InlayHintsOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und Typmarken an (#453); ohne Kopie des Einstellungsrecords.</summary>
    class function InlayTypeHintsOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und Include-Symbole hinter {$I} an (#860); ohne Kopie des
    /// Einstellungsrecords.</summary>
    class function InlayDefineHintsOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und Codes von Steuerzeichen an (#862).</summary>
    class function InlayCharHintsOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und Marken „ohne Self“ an (#686).</summary>
    class function InlayMethodHintsOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und Blockende-Beschriftungen an (#620); ohne Kopie des Einstellungsrecords.
    /// </summary>
    class function BlockEndLabelsOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und ungenutzte uses abblenden an (#621); ohne Kopie des Einstellungsrecords.
    /// </summary>
    class function DimUnusedUsesOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und Rekursionssymbole an (#623); ohne Kopie des Einstellungsrecords.</summary>
    class function RecursionMarkersOn: Boolean; static;
    /// <summary>editor.recursionMarkers.depth (#623).</summary>
    class function RecursionMarkersDepth: Integer; static;
    /// <summary>Plugin eingeschaltet und Atlas-Spalte in der Zeilenleiste an (#768); ohne Kopie des
    /// Einstellungsrecords.</summary>
    class function GutterColumnOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und gleichen Text hervorheben an (#709); AOptions und ANavigateF3 aus
    /// highlight.selectionMatches.*, ohne Kopie des Einstellungsrecords.</summary>
    class function SelectionMatchesOn(out AOptions: TAtlasSelectionMatchOptions; out ANavigateF3: Boolean): Boolean;
      static;
    /// <summary>Plugin eingeschaltet und Austrittspunkte hervorheben an (#698); die Schalter aus
    /// editor.exitPoints.*, ohne Kopie des Einstellungsrecords.</summary>
    class function ExitPointsOn(out AExceptions, ALoops, ABadge: Boolean): Boolean; static;
    /// <summary>Plugin eingeschaltet und neu zugewiesene Variablen unterstreichen an (#712); Arten, Linie und Farbe
    /// aus highlight.reassigned.*, ohne Kopie des Einstellungsrecords.</summary>
    class function ReassignedOn(out ATargets, AStyle, AColor: string): Boolean; static;
    /// <summary>Plugin eingeschaltet und Problem-Markierungen an; ohne Kopie des Einstellungsrecords (P-10).</summary>
    class function ProblemMarksOn: Boolean; static;
    /// <summary>Fehlertext am Zeilenende (#509); Off, wenn das Plugin oder die Problem-Markierungen aus sind.
    /// </summary>
    class function InlineDiagnosticsMode: TAtlasInlineDiagnosticsMode; static;
    /// <summary>Plugin, Probleme und Zähler in der Statusleiste an (#509), außer die Atlas-Statusleiste am Editor
    /// zeigt ihre Befundzähler (#1155): Dann stünden Zahlen doppelt.</summary>
    class function ProblemsStatusCounterOn: Boolean; static;
    /// <summary>Übernimmt und speichert ASettings (gespeicherte Werte, ohne Sitzungswerte).</summary>
    class procedure Update(const ASettings: TAtlasPluginSettings); static;
    /// <summary>Inhalt von %APPDATA%\Atlas\settings.json ('' ohne Datei) für Export und Import (#723).</summary>
    class function GlobalText: string; static;
    /// <summary>Schreibt AText nach settings.json (#723); False, wenn die Datei da, aber nicht lesbar ist.
    /// Danach Update aufrufen, damit die umgeleiteten Plugin-Werte dazukommen.</summary>
    class function SaveGlobalText(const AText: string): Boolean; static;
    /// <summary>Sitzungswerte der Schnellschalter (#604).</summary>
    class function Session: TAtlasToggleSession; static;
    class procedure SetSession(const ASession: TAtlasToggleSession); static;
    /// <summary>Sitzungswert für AKey (z. B. XmlDocFull über dem Wert aus atlas.json); False ohne.</summary>
    class function SessionFlag(const AKey: string; out AValue: Boolean): Boolean; static;
    /// <summary>Schnellschalter aus Plugin-Katalog und atlas.schema.json in der Sprache der Oberfläche.</summary>
    class function QuickToggles: TArray<TAtlasQuickToggle>; static;
    /// <summary>Modul-Schalter aus dem Katalog (#1454), einmal gelesen.</summary>
    class function ModuleSwitches: TArray<TAtlasModuleSwitch>; static;
    /// <summary>Ist das Modul AModule (x-module, z. B. "debug") wirksam an, auch nach Schnellschaltern? Unbekannte
    /// Kennung = an.</summary>
    class function ModuleOn(const AModule: string): Boolean; static;
    /// <summary>Experimentelle Plugin-Einstellungen aus dem Katalog (#834), einmal gelesen.</summary>
    class function ExperimentalEntries: TArray<TAtlasCatalogEntry>; static;
    /// <summary>Schlüssel der experimentellen Schalter, die gerade wirken (Plugin und settings.json); leer ohne
    /// Hauptschalter. Für Statusfeld, Fehlerbericht und Diagnoselog.</summary>
    class function ActiveExperimental: TArray<string>; static;
    /// <summary>Gemerkte Einstellungsstände, neuester zuerst (#722).</summary>
    class function History: TAtlasSettingsHistory; static;
    /// <summary>Gespeicherte Einstellungen auf Stand AIndex zurücksetzen; der jetzige Stand wird selbst
    /// gemerkt.</summary>
    class procedure Restore(AIndex: Integer); static;
    /// <summary>Beim Entladen: Einstellungsstände freigeben.</summary>
    class procedure Release; static;
    /// <summary>Für Diagnose und Tests: beim nächsten Zugriff neu lesen.</summary>
    class procedure Reload; static;
    /// <summary>Nach Update (Optionsseite, Menü Atlas): z. B. Tastenkürzel neu belegen (#494).</summary>
    class property OnChanged: TProc read FOnChanged write FOnChanged;
  end;

const
  AtlasRegistryKey = 'Software\Atlas\IdePlugin';

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.DateUtils,
  System.Win.Registry,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.Layers,
  Atlas.Core.Settings.Scopes,
  Atlas.Core.Settings.Renames,
  Atlas.Core.Settings.Experimental,
  Atlas.Core.Settings.StatusBarItems,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.DataFile,
  Atlas.UI.Strings;

type
  TRegistryStore = class(TInterfacedObject, IAtlasSettingsStore, IAtlasSettingsNames)
  private
    FRegistry: TRegistry;
    FWritable: Boolean;
  public
    constructor Create(AWrite: Boolean);
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
    function Contains(const AName: string): Boolean;
    procedure Remove(const AName: string);
  end;

{ TRegistryStore }

constructor TRegistryStore.Create(AWrite: Boolean);
begin
  inherited Create;
  if AWrite then
  begin
    FRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  end
  else
  begin
    FRegistry := TRegistry.Create(KEY_READ);
  end;
  FRegistry.RootKey := HKEY_CURRENT_USER;
  if AWrite then
  begin
    FWritable := FRegistry.OpenKey(AtlasRegistryKey, True);
  end
  else
  begin
    FRegistry.OpenKeyReadOnly(AtlasRegistryKey);
  end;
end;

destructor TRegistryStore.Destroy;
begin
  FRegistry.Free;
  inherited Destroy;
end;

function TRegistryStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  Result := ADefault;
  try
    if (FRegistry.CurrentKey <> 0) and FRegistry.ValueExists(AName) and
      (FRegistry.GetDataType(AName) = rdInteger) then
    begin
      Result := FRegistry.ReadInteger(AName);
    end;
  except
    on ERegistryException do
      Result := ADefault;
  end;
end;

procedure TRegistryStore.WriteInteger(const AName: string; AValue: Integer);
begin
  if not FWritable then
  begin
    Exit;
  end;
  try
    FRegistry.WriteInteger(AName, AValue);
  except
    // Ohne Schreibrecht bleiben die Werte für diese Sitzung bestehen.
    on ERegistryException do
      ;
  end;
end;

function TRegistryStore.ReadString(const AName, ADefault: string): string;
begin
  Result := ADefault;
  try
    if (FRegistry.CurrentKey <> 0) and FRegistry.ValueExists(AName) and
      (FRegistry.GetDataType(AName) in [rdString, rdExpandString]) then
    begin
      Result := FRegistry.ReadString(AName);
    end;
  except
    on ERegistryException do
      Result := ADefault;
  end;
end;

procedure TRegistryStore.WriteString(const AName, AValue: string);
begin
  if not FWritable then
  begin
    Exit;
  end;
  try
    FRegistry.WriteString(AName, AValue);
  except
    // Ohne Schreibrecht bleiben die Werte für diese Sitzung bestehen.
    on ERegistryException do
      ;
  end;
end;

function TRegistryStore.Contains(const AName: string): Boolean;
begin
  try
    Result := (FRegistry.CurrentKey <> 0) and FRegistry.ValueExists(AName);
  except
    on ERegistryException do
      Result := False;
  end;
end;

procedure TRegistryStore.Remove(const AName: string);
begin
  if not FWritable then
  begin
    Exit;
  end;
  try
    if FRegistry.ValueExists(AName) then
    begin
      FRegistry.DeleteValue(AName);
    end;
  except
    // Ohne Schreibrecht bleibt der alte Wert; die Übernahme versucht es beim nächsten Start erneut.
    on ERegistryException do
      ;
  end;
end;

type
  /// <summary>Zustand von TAtlasIdeSettings (gelesene, wirksame Werte, Schnellschalter, Stände, Katalogteile).
  /// </summary>
  TSettingsState = record
    Stored: TAtlasPluginSettings;
    Effective: TAtlasPluginSettings;
    Session: TAtlasToggleSession;
    Toggles: TArray<TAtlasQuickToggle>;
    TogglesEnglish: Boolean;
    TogglesBuilt: Boolean;
    History: TAtlasSettingsHistory;
    /// <summary>settings-history.json war beim Lesen gesperrt: SaveHistory überschreibt sie nicht (Bericht N3).
    /// </summary>
    HistoryKept: Boolean;
    Loaded: Boolean;
    Experimental: TArray<TAtlasCatalogEntry>;
    ExperimentalRead: Boolean;
    Modules: TArray<TAtlasModuleSwitch>;
    ModulesRead: Boolean;
  end;

var
  GState: TSettingsState;

/// <summary>Umbenannte Einstellungen (x-renamedFrom, #1280) in der Registry übernehmen; jede Übernahme steht
/// einmal im Protokoll.</summary>
procedure ApplyRenames;
var
  Registry: TRegistryStore;
  Store: IAtlasSettingsStore;
  Catalog: TAtlasSettingsCatalog;
  Rename: TAtlasSettingsRename;
begin
  Registry := TRegistryStore.Create(True);
  Store := Registry;
  Catalog := TAtlasSettingsCatalog.CreateDefault;
  try
    for Rename in TAtlasSettingsRenames.Apply(Store, Registry, Catalog) do
    begin
      TAtlasGuard.Log(Rename.LogLine);
    end;
  finally
    Catalog.Free;
  end;
end;

/// <summary>issues.query als Abfrage „Standard“ nach issues.queries (#1262); True, wenn ARouted geändert
/// wurde. Der Registry-Name geht über RemoveLegacyQuery erst nach dem Speichern der Datei.</summary>
function MigrateQuery(const ARouted: IAtlasSettingsStore;
  out AMigration: TAtlasSettingsQueryMigration): Boolean;
var
  mRegistry: TRegistryStore;
  mLegacy: IAtlasSettingsStore;
begin
  mRegistry := TRegistryStore.Create(False);
  mLegacy := mRegistry;
  AMigration := TAtlasSettingsQueryMigrations.Migrate(mLegacy, mRegistry, ARouted);
  Result := AMigration.Moved;
end;

procedure RemoveLegacyQuery(const AMigration: TAtlasSettingsQueryMigration);
var
  mRegistry: TRegistryStore;
  mNames: IAtlasSettingsNames;
begin
  if not AMigration.Found then
  begin
    Exit;
  end;
  mRegistry := TRegistryStore.Create(True);
  mNames := mRegistry;
  TAtlasSettingsQueryMigrations.RemoveLegacy(mNames);
  TAtlasGuard.Log(AMigration.LogLine);
end;

function HistoryFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'Atlas'), 'settings-history.json');
end;

procedure SaveHistory;
var
  Snapshots: TAtlasSettingsHistory;
begin
  // Erst laden: Das setzt GState.HistoryKept.
  Snapshots := TAtlasIdeSettings.History;
  // Gesperrt gelesene Datei nicht mit den Ständen dieser Sitzung allein überschreiben.
  if not GState.HistoryKept then
  begin
    TAtlasDataFile.Write(HistoryFile, Snapshots.ToJson);
  end;
end;

/// <summary>Gespeichert, darüber Sitzungswerte, Einstellungen ausgeschalteter Module auf „aus“ (#1454), ohne
/// Hauptschalter experimentelle Werte auf Vorgabe.</summary>
function EffectiveSettings: TAtlasPluginSettings;
begin
  Result := TAtlasExperimental.Apply(TAtlasModuleSwitches.Apply(GState.Session.Apply(GState.Stored,
    TAtlasIdeSettings.QuickToggles), TAtlasIdeSettings.ModuleSwitches), TAtlasIdeSettings.ExperimentalEntries);
end;

{ TAtlasIdeSettings }

class function TAtlasIdeSettings.GlobalFile: string;
begin
  Result := TAtlasSettingsFiles.GlobalFile(GetEnvironmentVariable('APPDATA'));
end;

class function TAtlasIdeSettings.LoadGlobal(out AContent: TAtlasTextFileContent): Boolean;
begin
  AContent := Default(TAtlasTextFileContent);
  AContent.Encoding := TAtlasTextEncoding.Utf8;
  Result := True;
  try
    if (GlobalFile <> '') and TFile.Exists(GlobalFile) then
    begin
      AContent := TAtlasTextFile.Load(GlobalFile);
    end;
  except
    // Gesperrt oder unlesbar: wie keine Datei für diese Sitzung, aber nicht überschreiben.
    on Exception do
    begin
      AContent.Text := '';
      Result := False;
    end;
  end;
end;

class procedure TAtlasIdeSettings.SaveGlobal(const AContent: TAtlasTextFileContent; const AText: string);
var
  Content: TAtlasTextFileContent;
begin
  if (GlobalFile = '') or (AText = AContent.Text) then
  begin
    Exit;
  end;
  Content := AContent;
  Content.Text := AText;
  try
    ForceDirectories(ExtractFileDir(GlobalFile));
    TAtlasTextFile.Save(GlobalFile, Content);
  except
    // Ohne Schreibrecht oder bei fremder Sperre (Bericht M5) bleiben die Werte für diese Sitzung bestehen. Ins
    // Protokoll ohne Pfad: Die Meldung von EAtlasTextFileError nennt keinen, andere nur mit Klasse.
    on E: EAtlasTextFileError do
      TAtlasGuard.Log('Einstellungen nicht gespeichert: ' + TAtlasGuard.SafeMessage(E.Message));
    on E: Exception do
      TAtlasGuard.Log('Einstellungen nicht gespeichert: ' + E.ClassName);
  end;
end;

class procedure TAtlasIdeSettings.EnsureLoaded;
var
  Content: TAtlasTextFileContent;
  Readable: Boolean;
  Routed: TAtlasRoutedSettingsStore;
  Store: IAtlasSettingsStore;
  mChanged: Boolean;
  mMigration: TAtlasSettingsQueryMigration;
begin
  if GState.Loaded then
  begin
    Exit;
  end;
  GState.Stored := TAtlasPluginSettings.Defaults;
  ApplyRenames;
  Readable := LoadGlobal(Content);
  Routed := TAtlasRoutedSettingsStore.Create(TRegistryStore.Create(False), Content.Text);
  Store := Routed;
  // Einmalig: Werte, die bis hierher in der Registry lagen, nach settings.json.
  mChanged := Routed.Migrate;
  mMigration := Default(TAtlasSettingsQueryMigration);
  // Eine nicht lesbare Datei wird nicht geschrieben: dann bleibt auch issues.query in der Registry.
  if Readable and MigrateQuery(Store, mMigration) then
  begin
    mChanged := True;
  end;
  if mChanged and Readable then
  begin
    SaveGlobal(Content, Routed.Text);
  end;
  if Readable then
  begin
    RemoveLegacyQuery(mMigration);
  end;
  GState.Stored.Load(Store);
  GState.Loaded := True;
  GState.Effective := EffectiveSettings;
end;

class function TAtlasIdeSettings.ExperimentalEntries: TArray<TAtlasCatalogEntry>;
var
  Catalog: TAtlasSettingsCatalog;
begin
  if not GState.ExperimentalRead then
  begin
    Catalog := TAtlasSettingsCatalog.CreateDefault;
    try
      GState.Experimental := TAtlasExperimental.PluginEntries(Catalog);
    finally
      Catalog.Free;
    end;
    GState.ExperimentalRead := True;
  end;
  Result := GState.Experimental;
end;


class function TAtlasIdeSettings.ModuleSwitches: TArray<TAtlasModuleSwitch>;
var
  mCatalog: TAtlasSettingsCatalog;
begin
  if not GState.ModulesRead then
  begin
    mCatalog := TAtlasSettingsCatalog.CreateDefault;
    try
      GState.Modules := TAtlasModuleSwitches.Read(mCatalog);
    finally
      mCatalog.Free;
    end;
    GState.ModulesRead := True;
  end;
  Result := GState.Modules;
end;

class function TAtlasIdeSettings.ModuleOn(const AModule: string): Boolean;
begin
  EnsureLoaded;
  // Der Schalter selbst gehört nicht zu seinen Mitgliedern: In GState.Effective steht sein Wert samt Sitzungswert.
  Result := TAtlasModuleSwitches.IsOn(GState.Effective, ModuleSwitches, AModule);
end;

class function TAtlasIdeSettings.ActiveExperimental: TArray<string>;
var
  Catalog: TAtlasSettingsCatalog;
begin
  EnsureLoaded;
  Catalog := TAtlasSettingsCatalog.CreateDefault;
  try
    Result := TAtlasExperimental.Active(GState.Session.Apply(GState.Stored, QuickToggles), GlobalText, Catalog);
  finally
    Catalog.Free;
  end;
end;

class function TAtlasIdeSettings.Current: TAtlasPluginSettings;
begin
  EnsureLoaded;
  Result := GState.Effective;
end;

class function TAtlasIdeSettings.InlayHintsOn: Boolean;
begin
  EnsureLoaded;
  Result := GState.Effective.Enabled and GState.Effective.InlayHints;
end;

class function TAtlasIdeSettings.InlayTypeHintsOn: Boolean;
begin
  EnsureLoaded;
  Result := GState.Effective.Enabled and GState.Effective.InlayTypeHints;
end;

class function TAtlasIdeSettings.InlayDefineHintsOn: Boolean;
begin
  EnsureLoaded;
  Result := GState.Effective.Enabled and GState.Effective.InlayDefineHints;
end;

class function TAtlasIdeSettings.InlayCharHintsOn: Boolean;
begin
  EnsureLoaded;
  Result := GState.Effective.Enabled and GState.Effective.InlayCharHints;
end;

class function TAtlasIdeSettings.InlayMethodHintsOn: Boolean;
begin
  EnsureLoaded;
  Result := GState.Effective.Enabled and GState.Effective.InlayMethodHints;
end;

class function TAtlasIdeSettings.BlockEndLabelsOn: Boolean;
begin
  EnsureLoaded;
  Result := GState.Effective.Enabled and GState.Effective.BlockEndLabels;
end;

class function TAtlasIdeSettings.DimUnusedUsesOn: Boolean;
begin
  EnsureLoaded;
  Result := GState.Effective.Enabled and GState.Effective.DimUnusedUses;
end;

class function TAtlasIdeSettings.RecursionMarkersOn: Boolean;
begin
  EnsureLoaded;
  Result := GState.Effective.Enabled and GState.Effective.RecursionMarkers;
end;

class function TAtlasIdeSettings.GutterColumnOn: Boolean;
begin
  EnsureLoaded;
  Result := GState.Effective.Enabled and GState.Effective.GutterColumn;
end;

class function TAtlasIdeSettings.SelectionMatchesOn(out AOptions: TAtlasSelectionMatchOptions;
  out ANavigateF3: Boolean): Boolean;
begin
  EnsureLoaded;
  AOptions.MinLength := GState.Effective.SelectionMatchesMinLength;
  AOptions.CaseSensitive := GState.Effective.SelectionMatchesCaseSensitive;
  AOptions.WholeWord := GState.Effective.SelectionMatchesWholeWord;
  AOptions.MaxMatches := GState.Effective.SelectionMatchesMaxMatches;
  ANavigateF3 := GState.Effective.SelectionMatchesNavigateF3;
  Result := GState.Effective.Enabled and GState.Effective.SelectionMatches;
end;

class function TAtlasIdeSettings.ExitPointsOn(out AExceptions, ALoops, ABadge: Boolean): Boolean;
begin
  EnsureLoaded;
  AExceptions := GState.Effective.ExitPointsExceptions;
  ALoops := GState.Effective.ExitPointsLoops;
  ABadge := GState.Effective.ExitPointsBadge;
  Result := GState.Effective.Enabled and GState.Effective.ExitPoints;
end;

class function TAtlasIdeSettings.ReassignedOn(out ATargets, AStyle, AColor: string): Boolean;
begin
  EnsureLoaded;
  ATargets := GState.Effective.ReassignedTargets;
  AStyle := GState.Effective.ReassignedStyle;
  AColor := GState.Effective.ReassignedColor;
  Result := GState.Effective.Enabled and GState.Effective.Reassigned;
end;

class function TAtlasIdeSettings.RecursionMarkersDepth: Integer;
begin
  EnsureLoaded;
  Result := GState.Effective.RecursionMarkersDepth;
end;

class function TAtlasIdeSettings.ProblemMarksOn: Boolean;
begin
  EnsureLoaded;
  Result := GState.Effective.Enabled and GState.Effective.Problems;
end;

class function TAtlasIdeSettings.InlineDiagnosticsMode: TAtlasInlineDiagnosticsMode;
begin
  EnsureLoaded;
  if GState.Effective.Enabled and GState.Effective.Problems then
  begin
    Result := TAtlasInlineDiagnostics.ModeOf(GState.Effective.InlineDiagnostics);
  end
  else
  begin
    Result := TAtlasInlineDiagnosticsMode.Off;
  end;
end;

class function TAtlasIdeSettings.ProblemsStatusCounterOn: Boolean;
begin
  EnsureLoaded;
  Result := GState.Effective.Enabled and GState.Effective.Problems and GState.Effective.ProblemsStatusCounter and
    not (GState.Effective.EditorStatusBar and TAtlasStatusBarItems.Contains(
    TAtlasStatusBarItems.Parse(GState.Effective.EditorStatusBarItems), TAtlasStatusBarItems.Findings));
end;

class function TAtlasIdeSettings.Stored: TAtlasPluginSettings;
begin
  EnsureLoaded;
  Result := GState.Stored;
end;

class procedure TAtlasIdeSettings.Changed;
begin
  GState.Effective := EffectiveSettings;
  if Assigned(FOnChanged) then
  begin
    FOnChanged();
  end;
end;

class procedure TAtlasIdeSettings.Update(const ASettings: TAtlasPluginSettings);
var
  Content: TAtlasTextFileContent;
  Readable: Boolean;
  Routed: TAtlasRoutedSettingsStore;
  Store: IAtlasSettingsStore;
  Next: TAtlasPluginSettings;
begin
  EnsureLoaded;
  Next := ASettings;
  Next.Normalize;
  // Alten Stand merken (#722); Fehler beim Schreiben der Datei stören das Speichern nicht.
  try
    History.Push(GState.Stored, Next, TTimeZone.Local.ToUniversalTime(Now), Next.SafeKeepSettingsHistory);
    SaveHistory;
  except
    // Der Grund steht einmal im Protokoll (ohne Pfad).
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Einstellungsverlauf', E);
  end;
  GState.Stored := Next;
  GState.Loaded := True;
  // settings.json frisch lesen: Der Dialog der globalen Einstellungen schreibt dieselbe Datei.
  Readable := LoadGlobal(Content);
  Routed := TAtlasRoutedSettingsStore.Create(TRegistryStore.Create(True), Content.Text);
  Store := Routed;
  GState.Stored.Save(Store);
  if Readable then
  begin
    SaveGlobal(Content, Routed.Text);
  end;
  Changed;
end;

class function TAtlasIdeSettings.GlobalText: string;
var
  Content: TAtlasTextFileContent;
begin
  LoadGlobal(Content);
  Result := Content.Text;
end;

class function TAtlasIdeSettings.SaveGlobalText(const AText: string): Boolean;
var
  Content: TAtlasTextFileContent;
begin
  Result := LoadGlobal(Content);
  if Result then
  begin
    SaveGlobal(Content, AText);
  end;
end;

class function TAtlasIdeSettings.Session: TAtlasToggleSession;
begin
  Result := GState.Session;
end;

class procedure TAtlasIdeSettings.SetSession(const ASession: TAtlasToggleSession);
begin
  EnsureLoaded;
  GState.Session := ASession;
  Changed;
end;

class function TAtlasIdeSettings.SessionFlag(const AKey: string; out AValue: Boolean): Boolean;
begin
  Result := GState.Session.TryGet(AKey, AValue);
end;

class function TAtlasIdeSettings.History: TAtlasSettingsHistory;
begin
  if GState.History = nil then
  begin
    GState.History := TAtlasSettingsHistory.Create;
    // Fehlt, unbrauchbar (dann als .defekt beiseitegelegt) oder gesperrt: ohne gemerkte Stände weiter.
    GState.HistoryKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(HistoryFile, 'Einstellungsverlauf',
      function(const AText: string): Boolean
      begin
        Result := GState.History.LoadJson(AText);
      end));
    if GState.HistoryKept then
    begin
      GState.History.Clear;
    end;
  end;
  Result := GState.History;
end;

class procedure TAtlasIdeSettings.Restore(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= History.Count) then
  begin
    Exit;
  end;
  Update(History[AIndex].Settings);
end;

class procedure TAtlasIdeSettings.Release;
begin
  FreeAndNil(GState.History);
  GState.Experimental := nil;
  GState.ExperimentalRead := False;
  GState.Modules := nil;
  GState.ModulesRead := False;
end;

class function TAtlasIdeSettings.QuickToggles: TArray<TAtlasQuickToggle>;
var
  English: Boolean;
begin
  English := TAtlasStrings.Language = TAtlasLanguage.English;
  if not GState.TogglesBuilt or (English <> GState.TogglesEnglish) then
  begin
    GState.Toggles := TAtlasQuickToggles.Build(TAtlasQuickToggles.PluginCatalog, AtlasSchemaJson, English);
    GState.TogglesEnglish := English;
    GState.TogglesBuilt := True;
  end;
  Result := GState.Toggles;
end;

class procedure TAtlasIdeSettings.Reload;
begin
  GState.Loaded := False;
end;

end.
