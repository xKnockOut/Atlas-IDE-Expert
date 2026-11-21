unit Atlas.UI.Assistants.SettingsSection.Tests;

// Seite „KI-Assistenten“ (#1906): Modulschalter, Schreiben in offene Dateien und Builds für KI-Assistenten auf
// einer eigenen Seite des Moduls; die Werte bleiben unter ihren Schlüsseln. KI-Schattentext (#1922): Schalter
// standardmäßig aus, Anbieter und Modell bleiben, der Schlüssel geht nur über die Haken der Komposition.
// Anbieter der IDE (#2744, #2745): Quelle, Mitbenutzen, Name, Anmelden bei der IDE; Liste der Anbieter mit Status
// und Funktionen, Auswahl ohne den eigenen Eintrag. Seite in Smart CodeInsight: Anbieter und Anfragen heute.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAssistantsSettingsSectionTests = class
  private
    FRegistrations: TArray<IAtlasRegistration>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure OwnPageRoundTrips;
    /// <summary>#2377: Verbundene IDE, Vorgabe aus, Auswahl und Vergleich an.</summary>
    [Test]
    procedure LinkSettingsRoundTrip;
    [Test]
    procedure AiGhostSettingsRoundTrip;
    [Test]
    procedure KeyButtonsUseTheHooks;
    [Test]
    procedure IdeProviderSettingsRoundTrip;
    [Test]
    procedure IdeProvidersAreListed;
    [Test]
    procedure ProviderLinesShowStateAndFeatures;
    [Test]
    procedure PluginFrameTexts;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.Core.Assistants.Contract.IdeAi,
  Atlas.UI.Assistants.IdePluginFrame,
  Atlas.UI.Assistants.SettingsSection;

{ TAssistantsSettingsSectionTests }

procedure TAssistantsSettingsSectionTests.Setup;
begin
  FRegistrations := ProvideSections([TAtlasAssistantsSettingsSection]);
end;

procedure TAssistantsSettingsSectionTests.TearDown;
begin
  RevokeAll(FRegistrations);
  TAtlasAssistantsSettingsSection.KeyHooks := Default(TAtlasAssistantsKeyHooks);
end;

procedure TAssistantsSettingsSectionTests.OwnPageRoundTrips;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'McpBuild').Checked, 'Builds für KI-Assistenten standardmäßig an');
    Assert.AreSame(SheetOf(CheckOf(mPage, 'AssistantsEnabled')), SheetOf(CheckOf(mPage, 'McpBuild')),
      'alle Schalter auf der Seite des Moduls');
    Assert.AreSame(SheetOf(CheckOf(mPage, 'AssistantsEnabled')), SheetOf(CheckOf(mPage, 'AssistantsEdit')));
    // Debuggen durch KI-Assistenten (#1874): Vorgabe aus, Leiste an, alles auf derselben Seite.
    Assert.IsFalse(CheckOf(mPage, 'DebugMcp').Checked, 'Debuggen durch KI-Assistenten standardmäßig aus');
    Assert.IsFalse(CheckOf(mPage, 'DebugMcpSideEffects').Checked);
    Assert.IsFalse(CheckOf(mPage, 'DebugMcpModify').Checked);
    Assert.IsFalse(CheckOf(mPage, 'DebugMcpAttach').Checked);
    Assert.IsTrue(CheckOf(mPage, 'DebugMcpBanner').Checked);
    Assert.AreSame(SheetOf(CheckOf(mPage, 'AssistantsEnabled')), SheetOf(CheckOf(mPage, 'DebugMcp')));
    CheckOf(mPage, 'DebugMcp').Checked := True;
    Assert.AreSame(SheetOf(CheckOf(mPage, 'AssistantsEnabled')), SheetOf(CheckOf(mPage, 'AssistantsBanner')),
      'Anzeige mit Pause auf der Seite des Moduls (#1906)');
    Assert.IsTrue(CheckOf(mPage, 'AssistantsBanner').Checked, 'Anzeige standardmäßig an');
    // #2615: Hinweis auf veraltete Anweisungsdateien, standardmäßig an, auf derselben Seite.
    Assert.IsTrue(CheckOf(mPage, 'AssistantsInstructionsHint').Checked);
    Assert.AreSame(SheetOf(CheckOf(mPage, 'AssistantsEnabled')), SheetOf(CheckOf(mPage, 'AssistantsInstructionsHint')));
    CheckOf(mPage, 'AssistantsInstructionsHint').Checked := False;
    CheckOf(mPage, 'McpBuild').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.McpBuild, 'abschaltbar, Schlüssel unverändert');
    Assert.IsFalse(mSaved.AssistantsInstructionsHint);
    Assert.IsTrue(mSaved.DebugMcp, 'einschaltbar');
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'McpBuild').Checked);
    // IDE-Zustand für get_ide_context (#2050) auf derselben Seite, standardmäßig an.
    Assert.AreSame(SheetOf(CheckOf(mPage, 'AssistantsEnabled')), SheetOf(CheckOf(mPage, 'AssistantsContext')));
    Assert.IsTrue(CheckOf(mPage, 'AssistantsContextSelection').Checked);
    CheckOf(mPage, 'AssistantsContext').Checked := False;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.AssistantsContext);
    // Zurückhalten (#2605), Fragen in der IDE (#2620) und KI-Protokoll (#2049): standardmäßig an, abschaltbar.
    Assert.AreSame(SheetOf(CheckOf(mPage, 'AssistantsEnabled')),
      SheetOf(CheckOf(mPage, 'AssistantsEditHoldModified')));
    Assert.IsTrue(CheckOf(mPage, 'AssistantsEditHoldModified').Checked);
    Assert.IsTrue(CheckOf(mPage, 'AssistantsQuestionsInIde').Checked);
    Assert.IsTrue(CheckOf(mPage, 'AssistantsLog').Checked);
    CheckOf(mPage, 'AssistantsEditHoldModified').Checked := False;
    CheckOf(mPage, 'AssistantsQuestionsInIde').Checked := False;
    CheckOf(mPage, 'AssistantsLog').Checked := False;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.AssistantsEditHoldModified);
    Assert.IsFalse(mSaved.AssistantsQuestionsInIde);
    Assert.IsFalse(mSaved.AssistantsLog);
  finally
    mPage.Free;
  end;
end;

procedure TAssistantsSettingsSectionTests.LinkSettingsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    mSaved := TAtlasPluginSettings.Defaults;
    Assert.AreSame(SheetOf(CheckOf(mPage, 'AssistantsEnabled')), SheetOf(CheckOf(mPage, 'AssistantsLink')));
    Assert.IsFalse(CheckOf(mPage, 'AssistantsLink').Checked, 'Kopplung standardmäßig aus');
    Assert.IsTrue(CheckOf(mPage, 'AssistantsLinkShareSelection').Checked);
    Assert.IsTrue(CheckOf(mPage, 'AssistantsLinkDiffPreview').Checked);
    CheckOf(mPage, 'AssistantsLink').Checked := True;
    CheckOf(mPage, 'AssistantsLinkDiffPreview').Checked := False;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.AssistantsLink, 'einschaltbar');
    Assert.IsFalse(mSaved.AssistantsLinkDiffPreview);
  finally
    mPage.Free;
  end;
end;

procedure TAssistantsSettingsSectionTests.AiGhostSettingsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsFalse(CheckOf(mPage, 'AssistantsInlineSuggestions').Checked, 'KI-Schattentext standardmäßig aus');
    Assert.AreEqual(0, ChoiceOf(mPage, 'AssistantsProvider').Choice, 'kein Anbieter');
    CheckOf(mPage, 'AssistantsInlineSuggestions').Checked := True;
    ChoiceOf(mPage, 'AssistantsProvider').Choice := 1;
    EditOf(mPage, 'AssistantsModel').Text := 'modell-x';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.AssistantsInlineSuggestions);
    Assert.AreEqual('anthropic', mSaved.AssistantsProvider);
    Assert.AreEqual('modell-x', mSaved.AssistantsModel);
  finally
    mPage.Free;
  end;
end;

procedure TAssistantsSettingsSectionTests.KeyButtonsUseTheHooks;
var
  mSection: TAtlasAssistantsSettingsSection;
  mProvided: IAtlasSettingsSection;
  mPage: TAtlasSettingsPage;
  mHooks: TAtlasAssistantsKeyHooks;
  mStored, mDeleted: string;
begin
  // Eigene Registrierung mit einer Instanz, deren Knöpfe der Test erreicht.
  RevokeAll(FRegistrations);
  mStored := '';
  mDeleted := '';
  mHooks := Default(TAtlasAssistantsKeyHooks);
  mHooks.Has :=
    function(AId: string): Boolean
    begin
      Result := mStored <> '';
    end;
  mHooks.Store :=
    function(AId, AKey: string): Boolean
    begin
      mStored := AId + '=' + AKey;
      Result := True;
    end;
  mHooks.Delete :=
    procedure(AId: string)
    begin
      mDeleted := AId;
      mStored := '';
    end;
  mHooks.Ask :=
    function(const ATitle, ALabel: string; var AKey: string): Boolean
    begin
      AKey := ' k1 ';
      Result := True;
    end;
  TAtlasAssistantsSettingsSection.KeyHooks := mHooks;
  mSection := TAtlasAssistantsSettingsSection.Create;
  mProvided := mSection;
  FRegistrations := [ProvideSection(mProvided)];
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsFalse(mSection.KeyStoreButton.Enabled, 'ohne Anbieter gesperrt');
    mSection.ProviderBox.Choice := 1;
    mSection.KeyStoreButton.Click;
    Assert.AreEqual('anthropic=k1', mStored, 'Schlüssel ohne Leerzeichen an den Haken');
    Assert.IsTrue(Pos('anthropic', mSection.KeyStateLabel.Caption) > 0, 'Stand zeigt den Anbieter');
    Assert.IsFalse(Pos('k1', mSection.KeyStateLabel.Caption) > 0, 'nie den Schlüssel');
    mSection.KeyDeleteButton.Click;
    Assert.AreEqual('anthropic', mDeleted);
  finally
    mPage.Free;
  end;
end;

procedure TAssistantsSettingsSectionTests.IdeProviderSettingsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsFalse(CheckOf(mPage, 'AssistantsIdeProvider').Checked, 'Anbieter der IDE standardmäßig aus');
    Assert.IsFalse(CheckOf(mPage, 'AssistantsRegisterInIde').Checked, 'Anmelden bei der IDE standardmäßig aus');
    Assert.AreEqual(0, ChoiceOf(mPage, 'AssistantsTextSource').Choice, 'Vorgabe ide');
    Assert.AreSame(SheetOf(CheckOf(mPage, 'AssistantsEnabled')), SheetOf(CheckOf(mPage, 'AssistantsIdeProvider')));
    CheckOf(mPage, 'AssistantsIdeProvider').Checked := True;
    CheckOf(mPage, 'AssistantsRegisterInIde').Checked := True;
    ChoiceOf(mPage, 'AssistantsTextSource').Choice := 1;
    EditOf(mPage, 'AssistantsIdeProviderName').Text := 'OpenAI';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.AssistantsIdeProvider);
    Assert.IsTrue(mSaved.AssistantsRegisterInIde);
    Assert.AreEqual('own', mSaved.AssistantsTextSource);
    Assert.AreEqual('OpenAI', mSaved.AssistantsIdeProviderName);
  finally
    mPage.Free;
  end;
end;

/// <summary>Irgendein TLabel unter AParent, dessen Beschriftung AText enthält.</summary>
function HasLabelWith(AParent: TWinControl; const AText: string): Boolean;
var
  mIndex: Integer;
  mControl: TControl;
begin
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    mControl := AParent.Controls[mIndex];
    if ((mControl is TLabel) and (Pos(AText, TLabel(mControl).Caption) > 0)) or
      ((mControl is TWinControl) and HasLabelWith(TWinControl(mControl), AText)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAssistantsSettingsSectionTests.IdeProvidersAreListed;
var
  mSection: TAtlasAssistantsSettingsSection;
  mProvided: IAtlasSettingsSection;
  mPage: TAtlasSettingsPage;
  mHooks: TAtlasAssistantsKeyHooks;
begin
  RevokeAll(FRegistrations);
  mHooks := Default(TAtlasAssistantsKeyHooks);
  mHooks.IdeProviders :=
    function: TArray<TAtlasIdeAiProvider>
    begin
      Result := TArray<TAtlasIdeAiProvider>.Create(
        TAtlasIdeAiProvider.Make('OpenAI', True, [TAtlasIdeAiFeature.Chat, TAtlasIdeAiFeature.Instruction]));
    end;
  TAtlasAssistantsSettingsSection.KeyHooks := mHooks;
  mSection := TAtlasAssistantsSettingsSection.Create;
  mProvided := mSection;
  FRegistrations := [ProvideSection(mProvided)];
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    // Vom Reiter aus suchen: Ohne Fenster hängt die Seite ihre Reiter erst in CreateWnd ein (PageControl), unter
    // mPage ist der Reiter dann noch nicht zu finden.
    Assert.IsTrue(HasLabelWith(SheetOf(CheckOf(mPage, 'AssistantsIdeProvider')), 'OpenAI: '),
      'Liste der Anbieter der IDE');
  finally
    mPage.Free;
  end;
end;

procedure TAssistantsSettingsSectionTests.ProviderLinesShowStateAndFeatures;
var
  mLines: string;
begin
  mLines := TAtlasAssistantsIdeRows.ProviderLines(TArray<TAtlasIdeAiProvider>.Create(
    TAtlasIdeAiProvider.Make('OpenAI', True, [TAtlasIdeAiFeature.Chat, TAtlasIdeAiFeature.ListModels]),
    TAtlasIdeAiProvider.Make('Ollama', False, [TAtlasIdeAiFeature.Instruction])));
  Assert.AreEqual(2, Integer(Length(mLines.Split([sLineBreak]))), 'eine Zeile je Anbieter');
  Assert.IsTrue(mLines.StartsWith('OpenAI: '));
  Assert.AreEqual(2, Integer(Length(TAtlasAssistantsIdeRows.FeaturesText(
    [TAtlasIdeAiFeature.Chat, TAtlasIdeAiFeature.ListModels]).Split([', ']))));
  Assert.AreEqual('', TAtlasAssistantsIdeRows.FeaturesText([]));
  Assert.IsTrue(TAtlasAssistantsIdeRows.ProviderLines(nil) <> '', 'ohne Anbieter ein Hinweis');
end;

procedure TAssistantsSettingsSectionTests.PluginFrameTexts;
var
  mView: TAtlasIdePluginFrameView;
  mFrame: TAtlasAssistantsIdePluginFrame;
begin
  mView := Default(TAtlasIdePluginFrameView);
  mView.Provider := 'OpenAI-kompatibel, llama3.1';
  mView.Today := 42;
  mView.Limit := 300;
  Assert.IsTrue(Pos('llama3.1', TAtlasAssistantsIdePluginFrame.ProviderText(mView)) > 0);
  Assert.IsTrue(Pos('42', TAtlasAssistantsIdePluginFrame.TodayText(mView)) > 0);
  Assert.IsTrue(Pos('300', TAtlasAssistantsIdePluginFrame.TodayText(mView)) > 0);
  mFrame := TAtlasAssistantsIdePluginFrame.Create(nil);
  try
    mFrame.ShowView(mView);
    Assert.AreEqual(TAtlasAssistantsIdePluginFrame.ProviderText(mView), mFrame.ProviderLabel.Caption);
  finally
    mFrame.Free;
  end;
  mView.Provider := '';
  Assert.IsFalse(Pos('llama3.1', TAtlasAssistantsIdePluginFrame.ProviderText(mView)) > 0,
    'ohne Anbieter der Hinweis');
end;

initialization
  TDUnitX.RegisterTestFixture(TAssistantsSettingsSectionTests);

end.
