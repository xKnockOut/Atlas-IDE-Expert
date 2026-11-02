unit Shell.Composition.FileOptions.Tests;

// Vorgaben je Datei ohne Arbeitsbereich: keine Delphi-Version, Schnellbefehle mit Alias "uses", Doku-Kommentare,
// Formatstil und Präfixe neuer Namen aus den Einstellungen ohne Ordner.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings,
  Shell.Composition.FileOptions;

type
  [TestFixture]
  TShellFileOptionsTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
    FOptions: TShellFileOptions;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne Arbeitsbereich keine Delphi-Version; der Sprachstand folgt den Vorgaben.</summary>
    [Test]
    procedure NoWorkspaceNoVersion;
    /// <summary>usesCommand = false sperrt den Schnellbefehl "uses" zusätzlich (#254).</summary>
    [Test]
    procedure SlashCommandsHonourUsesCommand;
    /// <summary>Doku-Kommentare und Formatstil kommen aus den Einstellungen der Editor-Ebene.</summary>
    [Test]
    procedure EditorLevelReachesFile;
    /// <summary>Präfixe neuer Namen ohne Arbeitsbereich: wie die Vorgaben der Namensregel.</summary>
    [Test]
    procedure NewNamesWithoutWorkspace;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Logging.Providers.Logger;

const
  cUri = 'file:///C:/Projekt/A.pas';

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

function NoLanguageLevel(const AUri: string): string;
begin
  Result := '';
end;

procedure TShellFileOptionsTests.Setup;
var
  mRegistry: TShellWorkspaceRegistryServices;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mRegistry);
  FSettings := TShellSettings.Create(FRegistry, NoLanguageLevel);
  FOptions := TShellFileOptions.Create(FRegistry, FSettings);
end;

procedure TShellFileOptionsTests.TearDown;
begin
  FreeAndNil(FOptions);
  FreeAndNil(FSettings);
  FreeAndNil(FRegistry);
end;

procedure TShellFileOptionsTests.NoWorkspaceNoVersion;
begin
  Assert.AreEqual('', FOptions.DelphiVersionFor(cUri));
  Assert.AreEqual(TLanguageFeatures.LanguageLevel('', TServerSettings.Default.MinDelphiVersion),
    FOptions.LanguageLevelFor(cUri));
end;

procedure TShellFileOptionsTests.SlashCommandsHonourUsesCommand;
var
  mDisabled: TArray<string>;
begin
  FSettings.SetEditorSettings('{"usesCommand":false}');
  FOptions.SlashCommands()(cUri, mDisabled);
  Assert.IsTrue(string.Join(',', mDisabled).Contains('uses'));
end;

procedure TShellFileOptionsTests.EditorLevelReachesFile;
var
  mDefault: TServerSettings;
begin
  mDefault := TServerSettings.Default;
  Assert.AreEqual(mDefault.CompleteBlocksDocComment, FOptions.DocCommentsFor(cUri));
  Assert.AreEqual(mDefault.Formatting.IndentSize, FOptions.FormatStyleFor(cUri).IndentSize);
end;

procedure TShellFileOptionsTests.NewNamesWithoutWorkspace;
var
  mContext: TRuleContext;
  mExpected, mActual: TPascalNamePrefixes;
begin
  mContext := Default(TRuleContext);
  mContext.UnitName := 'A';
  mExpected := TRuleEngine.NewNames(BuiltinRules, TServerSettings.Default, mContext);
  mActual := FOptions.NewNamesFor(cUri);
  Assert.AreEqual(mExpected.LocalPrefix, mActual.LocalPrefix);
  Assert.AreEqual(mExpected.FieldPrefix, mActual.FieldPrefix);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellFileOptionsTests);

end.
