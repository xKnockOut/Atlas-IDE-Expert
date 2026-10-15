unit Atlas.Core.Settings.Tests;

// Tests für die Einstellungen des Plugins (#227, Teil Vervollständigung).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPluginSettingsTests = class
  public
    [Test]
    procedure EmptyStoreGivesDefaults;
    [Test]
    procedure SaveAndLoadRoundTrip;
    [Test]
    procedure ClampsOutOfRangeValues;
    [Test]
    procedure IndexOptionsGoToServer;
    [Test]
    procedure XmlDocOptionsGoToServer;
    [Test]
    procedure AcceptOptionsRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin;

type
  TMemoryStore = class(TInterfacedObject, IAtlasSettingsStore)
  private
    FValues: TDictionary<string, Integer>;
    FStrings: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

{ TMemoryStore }

constructor TMemoryStore.Create;
begin
  inherited Create;
  FValues := TDictionary<string, Integer>.Create;
  FStrings := TDictionary<string, string>.Create;
end;

destructor TMemoryStore.Destroy;
begin
  FStrings.Free;
  FValues.Free;
  inherited Destroy;
end;

function TMemoryStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  if not FValues.TryGetValue(AName, Result) then
    Result := ADefault;
end;

procedure TMemoryStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

function TMemoryStore.ReadString(const AName, ADefault: string): string;
begin
  if not FStrings.TryGetValue(AName, Result) then
    Result := ADefault;
end;

procedure TMemoryStore.WriteString(const AName, AValue: string);
begin
  FStrings.AddOrSetValue(AName, AValue);
end;

{ TAtlasPluginSettingsTests }

procedure TAtlasPluginSettingsTests.EmptyStoreGivesDefaults;
var
  Store: IAtlasSettingsStore;
  Settings: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Settings := Default(TAtlasPluginSettings);
  Settings.Load(Store);
  Assert.IsTrue(Settings.Enabled);
  Assert.AreEqual(9, Settings.VisibleRows);
  Assert.AreEqual(0, Settings.ListWidth, 'Liste automatisch');
  Assert.AreEqual(320, Settings.PanelWidth);
  Assert.IsTrue(Settings.AutoParentheses);
  Assert.IsFalse(Settings.Preview, 'Vorschau standardmäßig aus (#434)');
  Assert.IsTrue(Settings.OpenForEdits, 'Nicht geöffnete Dateien öffnen (#397)');
  Assert.IsFalse(Settings.InlayHints, 'Inlay-Hints standardmäßig aus (#401)');
  Assert.AreEqual($800D, Settings.ActionsKey, 'Code-Aktionen: Alt+Enter (#399)');
  Assert.AreEqual(0, Settings.TypeDefinitionKey, 'Typdefinition ohne Kürzel');
  Assert.IsTrue(Settings.MethodToggle, 'Deklaration/Implementierung wechseln standardmäßig an (#775)');
  Assert.AreEqual($6026, Settings.MethodToggleUpKey, 'Strg+Umschalt+Hoch (#775)');
  Assert.AreEqual($6028, Settings.MethodToggleDownKey, 'Strg+Umschalt+Runter (#775)');
  Assert.IsTrue(Settings.SlashCommands, 'Schnellbefehle standardmäßig an (#399)');
  Assert.IsTrue(Settings.Snippets, 'Code-Vorlagen standardmäßig an (#51)');
  Assert.IsTrue(Settings.ImportIdeTemplates, 'Live Templates der IDE standardmäßig an (#51)');
  // Vervollständigung und Parameter-Hint über die Tasten der IDE, ohne eigene Belegung (#494).
  Assert.AreEqual(0, Settings.CompletionKey);
  Assert.AreEqual(0, Settings.SignatureKey);
  Assert.IsFalse(Settings.SignatureKeyPriority);
  Assert.AreEqual(200, Settings.ProviderTimeLimitMs, 'Zeitlimit für Quellen (#493)');
  Assert.AreEqual($E041, Settings.QuickToggleKey, 'Schnellschalter: Strg+Umschalt+Alt+A (#604)');
  Assert.IsFalse(Settings.QuickToggleKeyPriority);
  // Abgesicherter Start (#722).
  Assert.IsTrue(Settings.SafeAskAfterCrash);
  Assert.IsTrue(Settings.SafeAutoAfterRepeatedCrash);
  Assert.AreEqual('shift', Settings.SafeStartupKey);
  Assert.AreEqual(10000, Settings.SafeStartupTimeoutMs);
  Assert.AreEqual(5, Settings.SafeKeepSettingsHistory);
  // Dateiübergreifendes Zurücknehmen (#721).
  Assert.IsTrue(Settings.UndoMultiFile);
  Assert.AreEqual(20, Settings.UndoMultiFileDepth);
  Assert.IsTrue(Settings.UndoMultiFilePersist);
  Assert.AreEqual(50, Settings.UndoMultiFileMaxSizeMb);
  Assert.AreEqual('partial', Settings.UndoMultiFileOnConflict);
  Assert.AreEqual('recycleBin', Settings.UndoMultiFileNewFiles);
  Assert.AreEqual($C05A, Settings.UndoKey, 'Strg+Alt+Z');
  Assert.AreEqual($E05A, Settings.RedoKey, 'Strg+Alt+Umschalt+Z');
  Assert.IsFalse(Settings.UpdatesCheck, 'Update-Prüfung nur nach Zustimmung');
  Assert.IsTrue(Settings.BugReportAnonymize, 'Fehlerbericht anonymisiert');
  Assert.IsTrue(Settings.PairOwners, 'Anweisungen mitfärben standardmäßig an (#653)');
  Assert.AreEqual(1, Settings.PairGuideWidth, 'Blocklinien 1 px');
  Assert.AreEqual(75, Settings.PairGuideOpacity, 'Blocklinien 75 % Deckkraft');
  Assert.IsTrue(Settings.ProblemsList, 'Liste „Atlas-Probleme“ standardmäßig an');
end;

procedure TAtlasPluginSettingsTests.SaveAndLoadRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Settings := TAtlasPluginSettings.Defaults;
  Settings.Enabled := False;
  Settings.VisibleRows := 14;
  Settings.ListWidth := 500;
  Settings.PanelWidth := 400;
  Settings.PanelCollapsed := True;
  Settings.Learning := False;
  Settings.Preview := True;
  Settings.OpenForEdits := False;
  Settings.InlayHints := True;
  Settings.ActionsKey := 0;
  Settings.ExpandKey := $4041;
  Settings.TypeDefinitionKey := $C054;
  Settings.MethodToggle := False;
  Settings.MethodToggleUpKey := 0;
  Settings.MethodToggleDownKey := $C044; // Strg+Alt+D
  Settings.EditorKeysPriority := True;
  Settings.SlashCommands := False;
  Settings.Snippets := False;
  Settings.ImportIdeTemplates := False;
  Settings.ServerPath := '  D:\Atlas\AtlasServer.exe ';
  Settings.SignatureKey := $6048; // Strg+Umschalt+H
  Settings.SignatureKeyPriority := True;
  Settings.CompletionKey := $4020; // Strg+Leer
  Settings.ProviderTimeLimitMs := 350;
  Settings.QuickToggleKey := $6051;
  Settings.QuickToggleKeyPriority := True;
  Settings.SafeAskAfterCrash := False;
  Settings.SafeAutoAfterRepeatedCrash := False;
  Settings.SafeStartupKey := 'none';
  Settings.SafeStartupTimeoutMs := 30000;
  Settings.SafeKeepSettingsHistory := 0;
  Settings.UndoMultiFile := False;
  Settings.UndoMultiFileDepth := 7;
  Settings.UndoMultiFilePersist := False;
  Settings.UndoMultiFileMaxSizeMb := 3;
  Settings.UndoMultiFileOnConflict := 'abort';
  Settings.UndoMultiFileNewFiles := 'keep';
  Settings.UndoKey := 0;
  Settings.RedoKey := $C059;
  Settings.UpdatesCheck := True;
  Settings.BugReportAnonymize := False;
  Settings.ProblemsList := False;
  Settings.PairOwners := False;
  Settings.PairGuideWidth := 3;
  Settings.PairGuideOpacity := 80;
  Settings.PairColorsDark := '#112233, #445566,#778899,#aabbcc,#DDEEFF';
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.Enabled);
  Assert.AreEqual(14, Loaded.VisibleRows);
  Assert.AreEqual(500, Loaded.ListWidth);
  Assert.AreEqual(400, Loaded.PanelWidth);
  Assert.IsTrue(Loaded.PanelCollapsed);
  Assert.IsFalse(Loaded.Learning);
  Assert.IsTrue(Loaded.Preview);
  Assert.IsFalse(Loaded.OpenForEdits);
  Assert.IsTrue(Loaded.InlayHints);
  Assert.AreEqual(0, Loaded.ActionsKey, '0 = keine Taste');
  Assert.AreEqual($4041, Loaded.ExpandKey);
  Assert.AreEqual($6057, Loaded.ShrinkKey);
  Assert.AreEqual($C054, Loaded.TypeDefinitionKey);
  Assert.IsFalse(Loaded.MethodToggle);
  Assert.AreEqual(0, Loaded.MethodToggleUpKey, '0 = keine Taste');
  Assert.AreEqual($C044, Loaded.MethodToggleDownKey);
  Assert.IsTrue(Loaded.EditorKeysPriority);
  Assert.IsFalse(Loaded.SlashCommands);
  Assert.IsFalse(Loaded.Snippets);
  Assert.IsFalse(Loaded.ImportIdeTemplates);
  Assert.IsFalse(Loaded.PairOwners);
  Assert.AreEqual(3, Loaded.PairGuideWidth);
  Assert.AreEqual(80, Loaded.PairGuideOpacity);
  Assert.AreEqual('#112233,#445566,#778899,#AABBCC,#DDEEFF', Loaded.PairColorsDark, 'einheitlich geschrieben');
  Assert.IsFalse(Loaded.ProblemsList, 'Liste „Atlas-Probleme“ abgeschaltet');
  Assert.IsTrue(Loaded.Problems, 'Wellenlinien bleiben an');
  Assert.AreEqual('D:\Atlas\AtlasServer.exe', Loaded.ServerPath, 'Serverpfad ohne Leerraum');
  Assert.AreEqual($6048, Loaded.SignatureKey);
  Assert.IsTrue(Loaded.SignatureKeyPriority);
  Assert.AreEqual($4020, Loaded.CompletionKey);
  Assert.IsFalse(Loaded.CompletionKeyPriority);
  Assert.AreEqual(350, Loaded.ProviderTimeLimitMs);
  Assert.AreEqual($6051, Loaded.QuickToggleKey);
  Assert.IsTrue(Loaded.QuickToggleKeyPriority);
  Assert.IsFalse(Loaded.SafeAskAfterCrash);
  Assert.IsFalse(Loaded.SafeAutoAfterRepeatedCrash);
  Assert.AreEqual('none', Loaded.SafeStartupKey);
  Assert.AreEqual(30000, Loaded.SafeStartupTimeoutMs);
  Assert.AreEqual(0, Loaded.SafeKeepSettingsHistory);
  Assert.IsFalse(Loaded.UndoMultiFile);
  Assert.AreEqual(7, Loaded.UndoMultiFileDepth);
  Assert.IsFalse(Loaded.UndoMultiFilePersist);
  Assert.AreEqual(3, Loaded.UndoMultiFileMaxSizeMb);
  Assert.AreEqual('abort', Loaded.UndoMultiFileOnConflict);
  Assert.AreEqual('keep', Loaded.UndoMultiFileNewFiles);
  Assert.AreEqual(0, Loaded.UndoKey);
  Assert.AreEqual($C059, Loaded.RedoKey);
  Assert.IsTrue(Loaded.UpdatesCheck);
  Assert.IsFalse(Loaded.BugReportAnonymize);
  Assert.AreEqual('', TAtlasPluginSettings.Defaults.ServerPath, 'Standard: leer');
end;

procedure TAtlasPluginSettingsTests.IndexOptionsGoToServer;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  // Vorgaben wie im Schema; atlas.json-Format für den Server (#652).
  Settings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('{"index":{"projectGroup":true,"searchPaths":true,"libraryPaths":false,"usages":true},' +
    '"memoryBudgetMb":256,"hints":{"xmlDocFull":true,"xmlDocMaxLines":0}}', Settings.ServerSettingsJson);
  Store := TMemoryStore.Create;
  Settings.IndexSearchPaths := False;
  Settings.IndexLibraryPaths := True;
  Settings.IndexUsages := False;
  Settings.MemoryBudgetMb := 512;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsTrue(Loaded.IndexProjectGroup);
  Assert.IsFalse(Loaded.IndexSearchPaths);
  Assert.IsTrue(Loaded.IndexLibraryPaths);
  Assert.IsFalse(Loaded.IndexUsages);
  Assert.AreEqual(512, Loaded.MemoryBudgetMb);
  Assert.AreEqual('{"index":{"projectGroup":true,"searchPaths":false,"libraryPaths":true,"usages":false},' +
    '"memoryBudgetMb":512,"hints":{"xmlDocFull":true,"xmlDocMaxLines":0}}', Loaded.ServerSettingsJson);
  // Speichergrenze (#492): 0 = unbegrenzt, nicht negativ, höchstens 64 GB.
  Store.WriteInteger('MemoryBudgetMb', -5);
  Loaded.Load(Store);
  Assert.AreEqual(0, Loaded.MemoryBudgetMb);
  Store.WriteInteger('MemoryBudgetMb', 999999);
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MaxMemoryBudgetMb, Loaded.MemoryBudgetMb);
end;

procedure TAtlasPluginSettingsTests.XmlDocOptionsGoToServer;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  // #654: Registry XmlDocFull/XmlDocMaxLines, an den Server als hints.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.XmlDocFull);
  Assert.AreEqual(0, Settings.XmlDocMaxLines);
  Store := TMemoryStore.Create;
  Settings.XmlDocFull := False;
  Settings.XmlDocMaxLines := 12;
  Settings.Save(Store);
  Assert.AreEqual(0, Store.ReadInteger('XmlDocFull', 1));
  Assert.AreEqual(12, Store.ReadInteger('XmlDocMaxLines', 0));
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.XmlDocFull);
  Assert.AreEqual(12, Loaded.XmlDocMaxLines);
  Assert.IsTrue(Pos('"hints":{"xmlDocFull":false,"xmlDocMaxLines":12}', Loaded.ServerSettingsJson) > 0);
  // Grenzen 0..50.
  Store.WriteInteger('XmlDocMaxLines', 99);
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MaxXmlDocLines, Loaded.XmlDocMaxLines);
  Store.WriteInteger('XmlDocMaxLines', -3);
  Loaded.Load(Store);
  Assert.AreEqual(0, Loaded.XmlDocMaxLines);
end;

procedure TAtlasPluginSettingsTests.AcceptOptionsRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  // ARG-046 (#227): Commit-Zeichen, uses, Parameter-Hint, Verzögerung bis zum Öffnen.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.CommitCharacters);
  Assert.IsTrue(Settings.AutoUses);
  Assert.IsTrue(Settings.ParameterHints);
  Assert.AreEqual(150, Settings.OpenDelayMs);
  Store := TMemoryStore.Create;
  Settings.CommitCharacters := False;
  Settings.AutoUses := False;
  Settings.ParameterHints := False;
  Settings.OpenDelayMs := 400;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.CommitCharacters);
  Assert.IsFalse(Loaded.AutoUses);
  Assert.IsFalse(Loaded.ParameterHints);
  Assert.AreEqual(400, Loaded.OpenDelayMs);
  Store.WriteInteger('OpenDelayMs', 99999);
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MaxOpenDelay, Loaded.OpenDelayMs);
  Store.WriteInteger('OpenDelayMs', -1);
  Loaded.Load(Store);
  Assert.AreEqual(0, Loaded.OpenDelayMs);
end;

procedure TAtlasPluginSettingsTests.ClampsOutOfRangeValues;
var
  Store: IAtlasSettingsStore;
  Settings: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Store.WriteInteger('VisibleRows', 99);
  Store.WriteInteger('ListWidth', 50);
  Store.WriteInteger('PanelWidth', 5000);
  Store.WriteInteger('SignatureKey', -3);
  Store.WriteInteger('ProviderTimeLimitMs', 10);
  Store.WriteInteger('SafeStartupTimeoutMs', 5);
  Store.WriteInteger('SafeKeepSettingsHistory', 1000);
  Store.WriteString('SafeStartupKey', ' Alt ');
  Store.WriteInteger('UndoMultiFileDepth', 0);
  Store.WriteInteger('UndoMultiFileMaxSizeMb', 100000);
  Store.WriteString('UndoMultiFileOnConflict', ' ABORT ');
  Store.WriteString('UndoMultiFileNewFiles', 'irgendwas');
  Settings := Default(TAtlasPluginSettings);
  Settings.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MinProviderTimeLimit, Settings.ProviderTimeLimitMs);
  Assert.AreEqual(0, Settings.SignatureKey, 'kein gültiges Kürzel');
  Store.WriteInteger('PairGuideWidth', 7);
  Store.WriteInteger('PairGuideOpacity', 0);
  Store.WriteString('PairColorsLight', '#123456,blau');
  Settings := Default(TAtlasPluginSettings);
  Settings.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MaxPairGuideWidth, Settings.PairGuideWidth);
  Assert.AreEqual(TAtlasPluginSettings.MinPairGuideOpacity, Settings.PairGuideOpacity);
  Assert.AreEqual('', Settings.PairColorsLight, 'ungültige Farben = Standard');
  Assert.AreEqual(TAtlasPluginSettings.MaxVisibleRows, Settings.VisibleRows);
  Assert.AreEqual(TAtlasPluginSettings.MinListWidth, Settings.ListWidth);
  Assert.AreEqual(TAtlasPluginSettings.MaxPanelWidth, Settings.PanelWidth);
  Assert.AreEqual(TAtlasPluginSettings.MinSafeStartupTimeout, Settings.SafeStartupTimeoutMs);
  Assert.AreEqual(TAtlasPluginSettings.MaxSafeSettingsHistory, Settings.SafeKeepSettingsHistory);
  Assert.AreEqual('shift', Settings.SafeStartupKey, 'unbekannte Taste: Umschalt');
  Assert.AreEqual(TAtlasPluginSettings.MinUndoDepth, Settings.UndoMultiFileDepth);
  Assert.AreEqual(TAtlasPluginSettings.MaxUndoMaxSizeMb, Settings.UndoMultiFileMaxSizeMb);
  Assert.AreEqual('abort', Settings.UndoMultiFileOnConflict);
  Assert.AreEqual('recycleBin', Settings.UndoMultiFileNewFiles, 'unbekannt: Papierkorb');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginSettingsTests);

end.
