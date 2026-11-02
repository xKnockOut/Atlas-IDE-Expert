unit Shell.Composition.Settings.Tests;

// Wirksame Einstellungen ohne Arbeitsbereich: globale Ebene und Editor-Ebene ergeben die Einstellungen,
// unveränderter globaler Text meldet keine Änderung, Hervorhebungen und Zeichenketten fallen auf die Vorgaben.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings;

type
  [TestFixture]
  TShellSettingsTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
    FAskedUri: string;
    function LanguageLevel(const AUri: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne Arbeitsbereich gelten global und Editor; beide Ebenen zählen.</summary>
    [Test]
    procedure LooseSettingsFromGlobalAndEditor;
    /// <summary>Gleicher globaler Text meldet False, neuer True; der Text bleibt abrufbar.</summary>
    [Test]
    procedure GlobalChangeIsReported;
    /// <summary>Ohne Arbeitsbereich: keine Einstellungen des Ordners, Hervorhebung nach Vorgabe, Sprachstand zur
    /// Datei gefragt.</summary>
    [Test]
    procedure DefaultsWithoutWorkspace;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Logging.Providers.Logger;

function NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function NoSelection(const AOrigin: string): string;
begin
  Result := '';
end;

function NoActive: string;
begin
  Result := '';
end;

procedure TShellSettingsTests.Setup;
var
  mServices: TShellWorkspaceRegistryServices;
begin
  mServices := Default(TShellWorkspaceRegistryServices);
  mServices.Logger := TLogger.Create;
  mServices.SelectedProject := NoSelection;
  mServices.ActiveProject := NoActive;
  mServices.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mServices);
  FSettings := TShellSettings.Create(FRegistry, LanguageLevel);
  FAskedUri := '';
end;

procedure TShellSettingsTests.TearDown;
begin
  FSettings.Free;
  FSettings := nil;
  FRegistry.Free;
  FRegistry := nil;
  FAskedUri := '';
end;

function TShellSettingsTests.LanguageLevel(const AUri: string): string;
begin
  FAskedUri := AUri;
  Result := '';
end;

procedure TShellSettingsTests.LooseSettingsFromGlobalAndEditor;
var
  mSettings: TServerSettings;
begin
  Assert.IsTrue(FSettings.SetGlobalSettings('{"rules": {"no-with": "off"}}'));
  FSettings.SetEditorSettings('{"rules": {"magic-number": "error"}}');
  Assert.AreEqual('{"rules": {"magic-number": "error"}}', FSettings.EditorSettings);
  mSettings := FSettings.SettingsFor('file:///x/a.pas');
  Assert.AreEqual(Ord(TRuleSeverity.Off), Ord(mSettings.RuleSeverity('no-with', TRuleSeverity.Warning)), 'global');
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mSettings.RuleSeverity('magic-number', TRuleSeverity.Warning)),
    'Editor');
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(FSettings.Loose.RuleSeverity('magic-number', TRuleSeverity.Warning)));
end;

procedure TShellSettingsTests.GlobalChangeIsReported;
begin
  Assert.IsTrue(FSettings.SetGlobalSettings('{"rules": {"no-with": "off"}}'));
  Assert.IsFalse(FSettings.SetGlobalSettings('{"rules": {"no-with": "off"}}'));
  Assert.AreEqual('{"rules": {"no-with": "off"}}', FSettings.GlobalSettings);
end;

procedure TShellSettingsTests.DefaultsWithoutWorkspace;
var
  mSettings: TServerSettings;
  mMultiline: Boolean;
begin
  Assert.IsFalse(FSettings.WorkspaceSettingsOf('file:///x/a.pas', mSettings));
  Assert.AreEqual(THighlightSettings.Default.BlockPairs, FSettings.Highlight('file:///x/a.pas').BlockPairs);
  FSettings.StringLiteral('file:///x/a.pas', mMultiline);
  Assert.AreEqual('file:///x/a.pas', FAskedUri);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellSettingsTests);

end.
