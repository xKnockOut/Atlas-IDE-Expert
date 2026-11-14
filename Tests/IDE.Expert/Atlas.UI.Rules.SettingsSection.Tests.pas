unit Atlas.UI.Rules.SettingsSection.Tests;

// Abschnitte des Moduls Prüfregeln (#1456) auf den Seiten „Prüfregeln“ und „Editor“: Sammelkorrektur (#1352),
// Basislinie und DFM-Eigenschaftsregeln; Laden und Speichern über die Seite und der Platz auf den Unterpunkten.
// Seit #1755: Wege zu den Regeln, Stand der Baseline und Unterdrückungen je Regel über die Hooks.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract,
  Atlas.UI.Rules.SettingsSection;

type
  [TestFixture]
  [Category('Atlas.IDE.Rules')]
  TRulesSettingsSectionTests = class
  private
    FRegistrations: TArray<IAtlasRegistration>;
    FOpened: string;
    FDeleted: Boolean;
    function TestHooks: TAtlasRulesChecksHooks;
    /// <summary>Statt der Abschnitte aus Setup nur ASection anmelden.</summary>
    procedure ProvideOnly(const ASection: TAtlasRulesChecksSection);
  public
    [SetupFixture]
    procedure WarmUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RulesRoundTrip;
    /// <summary>Sammelkorrektur beim Prüffenster von Base, Basislinie und DFM-Regeln bei Code Lens.</summary>
    [Test]
    procedure RowsOnTheirNodes;
    /// <summary>#1755: Wege zu den Regeln, Baseline und Unterdrückungen im Hauptknoten, über die Hooks.</summary>
    [Test]
    procedure LinksBaselineAndSuppressionsUseHooks;
    /// <summary>Ohne Hooks sind die Knöpfe gesperrt, die Baseline zeigt „keine“.</summary>
    [Test]
    procedure WithoutHooksButtonsDisabled;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Rules.Strings;

procedure TRulesSettingsSectionTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure TRulesSettingsSectionTests.Setup;
begin
  FRegistrations := ProvideSections([TAtlasRulesChecksSection, TAtlasRulesEditorSection]);
end;

procedure TRulesSettingsSectionTests.TearDown;
begin
  RevokeAll(FRegistrations);
  FOpened := '';
end;

function TRulesSettingsSectionTests.TestHooks: TAtlasRulesChecksHooks;
begin
  Result := Default(TAtlasRulesChecksHooks);
  Result.OpenProject :=
    procedure
    begin
      FOpened := FOpened + 'P';
    end;
  Result.OpenGlobal :=
    procedure
    begin
      FOpened := FOpened + 'G';
    end;
  Result.BaselineInfo :=
    function: string
    begin
      Result := '5 Treffer in 2 Einträgen';
    end;
  Result.BaselineDelete :=
    function: string
    begin
      FDeleted := True;
      Result := 'gelöscht';
    end;
  Result.Suppressions :=
    function: TArray<string>
    begin
      Result := ['no-with: 3 (ungenutzt 1, in 2 Dateien)'];
    end;
  Result.Confirm :=
    function(AQuestion: string): Boolean
    begin
      Result := True;
    end;
end;

procedure TRulesSettingsSectionTests.ProvideOnly(const ASection: TAtlasRulesChecksSection);
var
  mSection: IAtlasSettingsSection;
begin
  RevokeAll(FRegistrations);
  mSection := ASection;
  FRegistrations := [ProvideSection(mSection)];
end;

procedure TRulesSettingsSectionTests.RulesRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'RuleChecksEnabled').Checked, 'Modulschalter');
    Assert.IsTrue(CheckOf(mPage, 'FixBulk').Checked, 'Sammelkorrektur standardmäßig an');
    Assert.IsTrue(CheckOf(mPage, 'BaselineUpdate').Checked);
    Assert.IsTrue(CheckOf(mPage, 'DfmPropertyRules').Checked);
    Assert.IsFalse(CheckOf(mPage, 'OwnershipHints').Checked, '„Wer gibt das frei?“ standardmäßig aus (#1877)');
    Assert.IsFalse(CheckOf(mPage, 'OwnershipHintsOnlyProblems').Checked);
    CheckOf(mPage, 'FixBulk').Checked := False;
    CheckOf(mPage, 'OwnershipHints').Checked := True;
    CheckOf(mPage, 'OwnershipHintsOnlyProblems').Checked := True;
    CheckOf(mPage, 'BaselineUpdate').Checked := False;
    CheckOf(mPage, 'DfmPropertyRules').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.FixBulk, 'Sammelkorrektur gespeichert');
    Assert.IsFalse(mSaved.BaselineUpdate);
    Assert.IsFalse(mSaved.DfmPropertyRules);
    Assert.IsTrue(mSaved.OwnershipHints, 'editor.ownershipHints gespeichert');
    Assert.IsTrue(mSaved.OwnershipHintsOnlyProblems, 'editor.ownershipHints.onlyProblems gespeichert');
    mSaved.DfmPropertyRules := True;
    mSaved.OwnershipHintsOnlyProblems := False;
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'FixBulk').Checked, 'Sammelkorrektur geladen');
    Assert.IsFalse(CheckOf(mPage, 'BaselineUpdate').Checked);
    Assert.IsTrue(CheckOf(mPage, 'DfmPropertyRules').Checked);
    Assert.IsTrue(CheckOf(mPage, 'OwnershipHints').Checked, 'editor.ownershipHints geladen');
    Assert.IsFalse(CheckOf(mPage, 'OwnershipHintsOnlyProblems').Checked);
  finally
    mPage.Free;
  end;
end;

procedure TRulesSettingsSectionTests.RowsOnTheirNodes;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
begin
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    Assert.AreSame(mPage.NodeSheet('rules.window'), SheetOf(CheckOf(mPage, 'FixBulk')));
    Assert.AreSame(mPage.NodeSheet('editor.codeLens'), SheetOf(CheckOf(mPage, 'BaselineUpdate')));
    Assert.AreSame(mPage.NodeSheet('editor.codeLens'), SheetOf(CheckOf(mPage, 'DfmPropertyRules')));
    Assert.AreSame(mPage.NodeSheet('editor.ownershipHints'), SheetOf(CheckOf(mPage, 'OwnershipHints')));
    Assert.AreSame(mPage.NodeSheet('editor.ownershipHints'), SheetOf(CheckOf(mPage, 'OwnershipHintsOnlyProblems')));
  finally
    mHost.Free;
  end;
end;

procedure TRulesSettingsSectionTests.LinksBaselineAndSuppressionsUseHooks;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSection: TAtlasRulesChecksSection;
begin
  mSection := TAtlasRulesChecksSection.Create;
  mSection.Hooks := TestHooks;
  ProvideOnly(mSection);
  FDeleted := False;
  // Liste und Knöpfe brauchen ein Fenster, wie in der IDE.
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    // Alles im Hauptknoten der Seite, im Rahmen des Modulschalters.
    Assert.AreEqual('', mPage.NodeOfSheet(SheetOf(mSection.RulesProjectButton)));
    Assert.AreEqual('', mPage.NodeOfSheet(SheetOf(mSection.SuppressionsList)));
    mSection.RulesProjectButton.Click;
    mSection.RulesGlobalButton.Click;
    Assert.AreEqual('PG', FOpened);
    Assert.AreEqual('5 Treffer in 2 Einträgen', mSection.BaselineInfoLabel.Caption);
    Assert.IsFalse(mSection.BaselineUpdateButton.Enabled, 'ohne Hook gesperrt');
    mSection.BaselineDeleteButton.Click;
    Assert.IsTrue(FDeleted);
    Assert.AreEqual('gelöscht', mSection.BaselineInfoLabel.Caption);
    mSection.SuppressionsRefreshButton.Click;
    Assert.AreEqual(1, Integer(mSection.SuppressionsList.Items.Count));
  finally
    mHost.Free;
  end;
end;

procedure TRulesSettingsSectionTests.WithoutHooksButtonsDisabled;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSection: TAtlasRulesChecksSection;
begin
  mSection := TAtlasRulesChecksSection.Create;
  ProvideOnly(mSection);
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    Assert.IsFalse(mSection.RulesProjectButton.Enabled);
    Assert.IsFalse(mSection.RulesGlobalButton.Enabled);
    Assert.IsFalse(mSection.BaselineDeleteButton.Enabled);
    Assert.IsFalse(mSection.SuppressionsRefreshButton.Enabled);
    Assert.AreEqual(TAtlasRulesStrings.Text(TAtlasRulesTextId.ServerPageBaselineNone),
      mSection.BaselineInfoLabel.Caption);
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRulesSettingsSectionTests);

end.
