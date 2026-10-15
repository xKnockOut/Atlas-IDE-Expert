unit Atlas.IDE.Settings.Store;

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

interface

uses
  System.SysUtils,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.QuickToggles;

type
  TAtlasIdeSettings = class
  private class var
    FStored: TAtlasPluginSettings;
    FEffective: TAtlasPluginSettings;
    FSession: TAtlasToggleSession;
    FToggles: TArray<TAtlasQuickToggle>;
    FTogglesEnglish: Boolean;
    FTogglesBuilt: Boolean;
    FHistory: TAtlasSettingsHistory;
    FOnChanged: TProc;
    FLoaded: Boolean;
    class procedure EnsureLoaded; static;
    class procedure Changed; static;
    class function HistoryFile: string; static;
    class procedure SaveHistory; static;
    class function GlobalFile: string; static;
    /// <summary>False, wenn die Datei da, aber nicht lesbar ist; dann wird sie auch nicht geschrieben.</summary>
    class function LoadGlobal(out AContent: TAtlasTextFileContent): Boolean; static;
    class procedure SaveGlobal(const AContent: TAtlasTextFileContent; const AText: string); static;
  public
    /// <summary>Wirksame Werte: gespeichert, darüber die Sitzungswerte der Schnellschalter (#604).</summary>
    class function Current: TAtlasPluginSettings; static;
    /// <summary>Gespeicherte Werte (Registry) ohne Sitzungswerte; Grundlage für Optionsseite und Update.</summary>
    class function Stored: TAtlasPluginSettings; static;
    /// <summary>Übernimmt und speichert ASettings (gespeicherte Werte, ohne Sitzungswerte).</summary>
    class procedure Update(const ASettings: TAtlasPluginSettings); static;
    /// <summary>Sitzungswerte der Schnellschalter (#604).</summary>
    class function Session: TAtlasToggleSession; static;
    class procedure SetSession(const ASession: TAtlasToggleSession); static;
    /// <summary>Sitzungswert für AKey (z. B. XmlDocFull über dem Wert aus atlas.json); False ohne.</summary>
    class function SessionFlag(const AKey: string; out AValue: Boolean): Boolean; static;
    /// <summary>Schnellschalter aus Plugin-Katalog und atlas.schema.json in der Sprache der Oberfläche.</summary>
    class function QuickToggles: TArray<TAtlasQuickToggle>; static;
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
  Atlas.UI.Strings;

type
  TRegistryStore = class(TInterfacedObject, IAtlasSettingsStore)
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
  end;

{ TRegistryStore }

constructor TRegistryStore.Create(AWrite: Boolean);
begin
  inherited Create;
  if AWrite then
    FRegistry := TRegistry.Create(KEY_READ or KEY_WRITE)
  else
    FRegistry := TRegistry.Create(KEY_READ);
  FRegistry.RootKey := HKEY_CURRENT_USER;
  if AWrite then
    FWritable := FRegistry.OpenKey(AtlasRegistryKey, True)
  else
    FRegistry.OpenKeyReadOnly(AtlasRegistryKey);
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
      Result := FRegistry.ReadInteger(AName);
  except
    on ERegistryException do
      Result := ADefault;
  end;
end;

procedure TRegistryStore.WriteInteger(const AName: string; AValue: Integer);
begin
  if not FWritable then
    Exit;
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
      Result := FRegistry.ReadString(AName);
  except
    on ERegistryException do
      Result := ADefault;
  end;
end;

procedure TRegistryStore.WriteString(const AName, AValue: string);
begin
  if not FWritable then
    Exit;
  try
    FRegistry.WriteString(AName, AValue);
  except
    // Ohne Schreibrecht bleiben die Werte für diese Sitzung bestehen.
    on ERegistryException do
      ;
  end;
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
      AContent := TAtlasTextFile.Load(GlobalFile);
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
    Exit;
  Content := AContent;
  Content.Text := AText;
  try
    ForceDirectories(ExtractFileDir(GlobalFile));
    TAtlasTextFile.Save(GlobalFile, Content);
  except
    // Ohne Schreibrecht bleiben die Werte für diese Sitzung bestehen.
    on Exception do
      ;
  end;
end;

class procedure TAtlasIdeSettings.EnsureLoaded;
var
  Content: TAtlasTextFileContent;
  Readable: Boolean;
  Routed: TAtlasRoutedSettingsStore;
  Store: IAtlasSettingsStore;
begin
  if FLoaded then
    Exit;
  FStored := TAtlasPluginSettings.Defaults;
  Readable := LoadGlobal(Content);
  Routed := TAtlasRoutedSettingsStore.Create(TRegistryStore.Create(False), Content.Text);
  Store := Routed;
  // Einmalig: Werte, die bis hierher in der Registry lagen, nach settings.json.
  if Routed.Migrate and Readable then
    SaveGlobal(Content, Routed.Text);
  FStored.Load(Store);
  FLoaded := True;
  FEffective := FSession.Apply(FStored, QuickToggles);
end;

class function TAtlasIdeSettings.Current: TAtlasPluginSettings;
begin
  EnsureLoaded;
  Result := FEffective;
end;

class function TAtlasIdeSettings.Stored: TAtlasPluginSettings;
begin
  EnsureLoaded;
  Result := FStored;
end;

class procedure TAtlasIdeSettings.Changed;
begin
  FEffective := FSession.Apply(FStored, QuickToggles);
  if Assigned(FOnChanged) then
    FOnChanged();
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
    History.Push(FStored, Next, TTimeZone.Local.ToUniversalTime(Now), Next.SafeKeepSettingsHistory);
    SaveHistory;
  except
    on Exception do
      ;
  end;
  FStored := Next;
  FLoaded := True;
  // settings.json frisch lesen: Der Dialog der globalen Einstellungen schreibt dieselbe Datei.
  Readable := LoadGlobal(Content);
  Routed := TAtlasRoutedSettingsStore.Create(TRegistryStore.Create(True), Content.Text);
  Store := Routed;
  FStored.Save(Store);
  if Readable then
    SaveGlobal(Content, Routed.Text);
  Changed;
end;

class function TAtlasIdeSettings.Session: TAtlasToggleSession;
begin
  Result := FSession;
end;

class procedure TAtlasIdeSettings.SetSession(const ASession: TAtlasToggleSession);
begin
  EnsureLoaded;
  FSession := ASession;
  Changed;
end;

class function TAtlasIdeSettings.SessionFlag(const AKey: string; out AValue: Boolean): Boolean;
begin
  Result := FSession.TryGet(AKey, AValue);
end;

class function TAtlasIdeSettings.HistoryFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'Atlas'), 'settings-history.json');
end;

class function TAtlasIdeSettings.History: TAtlasSettingsHistory;
begin
  if FHistory = nil then
  begin
    FHistory := TAtlasSettingsHistory.Create;
    try
      if TFile.Exists(HistoryFile) then
        FHistory.LoadJson(TFile.ReadAllText(HistoryFile, TEncoding.UTF8));
    except
      // Unlesbar: ohne gemerkte Stände weiter.
      on Exception do
        FHistory.Clear;
    end;
  end;
  Result := FHistory;
end;

class procedure TAtlasIdeSettings.SaveHistory;
begin
  ForceDirectories(ExtractFileDir(HistoryFile));
  TFile.WriteAllText(HistoryFile, History.ToJson, TEncoding.UTF8);
end;

class procedure TAtlasIdeSettings.Restore(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= History.Count) then
    Exit;
  Update(History[AIndex].Settings);
end;

class procedure TAtlasIdeSettings.Release;
begin
  FreeAndNil(FHistory);
end;

class function TAtlasIdeSettings.QuickToggles: TArray<TAtlasQuickToggle>;
var
  English: Boolean;
begin
  English := TAtlasStrings.Language = TAtlasLanguage.English;
  if not FTogglesBuilt or (English <> FTogglesEnglish) then
  begin
    FToggles := TAtlasQuickToggles.Build(TAtlasQuickToggles.PluginCatalog, AtlasSchemaJson, English);
    FTogglesEnglish := English;
    FTogglesBuilt := True;
  end;
  Result := FToggles;
end;

class procedure TAtlasIdeSettings.Reload;
begin
  FLoaded := False;
end;

end.
