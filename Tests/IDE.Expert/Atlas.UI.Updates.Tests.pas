unit Atlas.UI.Updates.Tests;

// Rückfrage zur Update-Prüfung beim ersten Start (#495): Text, Knöpfe, nur
// die erste Antwort zählt; dazu Version und Schalter auf der Optionsseite.
// Update installieren (#1519): Texte zu Fehlercodes, Stand und Ergebnis,
// Auswahl der Module, Auswahllisten auf der Optionsseite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasUpdateConsentTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure AsksOnceAndRunsFirstAnswer;
    [Test]
    procedure NoAnswersNo;
    [Test]
    procedure SettingsPageShowsVersionAndSwitch;
  end;

  [TestFixture]
  TAtlasUpdateInstallUiTests = class
  public
    [Test]
    procedure ErrorCodesHaveTexts;
    [Test]
    procedure StageAndOutcomeTexts;
    [Test]
    procedure SelectionKeepsRequiredPackages;
    [Test]
    procedure SettingsPageSavesInstallChoices;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.Core.Product.Version,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Updates.Check,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Updates.Consent,
  Atlas.UI.Updates.Strings,
  Atlas.UI.Updates.Selection,
  Atlas.UI.Updates.Texts,
  Atlas.Text.UpdateRun,
  Atlas.UI.Settings.Page.Startup;

procedure TAtlasUpdateConsentTests.WarmUpFirstUse;
begin
  AsksOnceAndRunsFirstAnswer;
  SettingsPageShowsVersionAndSwitch;
end;

procedure TAtlasUpdateConsentTests.AsksOnceAndRunsFirstAnswer;
var
  mConsent: TAtlasUpdateConsent;
  mYes, mNo: Integer;
begin
  mYes := 0;
  mNo := 0;
  mConsent := TAtlasUpdateConsent.CreateConsent(nil);
  mConsent.OnYes :=
    procedure
    begin
      Inc(mYes);
    end;
  mConsent.OnNo :=
    procedure
    begin
      Inc(mNo);
    end;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.UpdatesConsentTitle), mConsent.Caption);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.UpdatesConsentText), mConsent.TextLabel.Caption);
  Assert.Contains(mConsent.TextLabel.Caption, 'IDE-Version');
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.UpdatesConsentYes), mConsent.YesButton.Caption);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.UpdatesConsentNo), mConsent.NoButton.Caption);
  // Nur die erste Antwort zählt; ausgeführt nach dem Schließen (das Fenster gibt sich selbst frei).
  mConsent.YesButton.Click;
  mConsent.NoButton.Click;
  Application.ProcessMessages;
  CheckSynchronize;
  Assert.AreEqual(1, mYes);
  Assert.AreEqual(0, mNo);
end;

procedure TAtlasUpdateConsentTests.NoAnswersNo;
var
  mConsent: TAtlasUpdateConsent;
  mYes, mNo: Integer;
begin
  mYes := 0;
  mNo := 0;
  mConsent := TAtlasUpdateConsent.CreateConsent(nil);
  mConsent.OnYes :=
    procedure
    begin
      Inc(mYes);
    end;
  mConsent.OnNo :=
    procedure
    begin
      Inc(mNo);
    end;
  mConsent.NoButton.Click;
  Application.ProcessMessages;
  CheckSynchronize;
  Assert.AreEqual(0, mYes);
  Assert.AreEqual(1, mNo);
end;

procedure TAtlasUpdateConsentTests.SettingsPageShowsVersionAndSwitch;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsFalse(CheckOf(mPage, 'UpdatesCheck').Checked, 'Vorgabe aus');
    Assert.AreEqual(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsVersion, [TAtlasPluginVersion.cVersion,
      TAtlasUpdates.IdeVersion]), mPage.Part<TAtlasSettingsStartupPart>.VersionLabel.Caption);
    CheckOf(mPage, 'UpdatesCheck').Checked := True;
    // Fehlerbericht (#108): anonymisiert als Vorgabe, abschaltbar.
    Assert.IsTrue(CheckOf(mPage, 'BugReportAnonymize').Checked);
    CheckOf(mPage, 'BugReportAnonymize').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.UpdatesCheck);
    Assert.IsFalse(mSaved.BugReportAnonymize);
  finally
    mPage.Free;
  end;
end;

{ TAtlasUpdateInstallUiTests }

function Candidate(const AName: string; ARequired, ASelected, AIsNew: Boolean): TUpdateCandidate;
begin
  Result := Default(TUpdateCandidate);
  Result.Name := AName;
  Result.Required := ARequired;
  Result.Selected := ASelected;
  Result.IsNew := AIsNew;
end;

function Txt(AId: TAtlasUpdatesTextId): string;
begin
  Result := TAtlasUpdatesStrings.Text(AId);
end;

function Fmt(AId: TAtlasUpdatesTextId; const AArgs: array of const): string;
begin
  Result := TAtlasUpdatesStrings.Fmt(AId, AArgs);
end;

procedure TAtlasUpdateInstallUiTests.ErrorCodesHaveTexts;
begin
  Assert.AreEqual(Txt(TAtlasUpdatesTextId.UpdatesErrorHash), TAtlasUpdateTexts.ErrorText('hash', ''));
  Assert.AreEqual(Txt(TAtlasUpdatesTextId.UpdatesErrorLocked) + ' (AtlasServer.exe)',
    TAtlasUpdateTexts.ErrorText(TUpdateErrors.cLocked, 'AtlasServer.exe'));
  Assert.AreEqual(Txt(TAtlasUpdatesTextId.UpdatesErrorUnexpected), TAtlasUpdateTexts.ErrorText('neu', ''),
    'unbekannter Code: unerwartet');
  Assert.AreEqual(Txt(TAtlasUpdatesTextId.UpdatesErrorStart), TAtlasUpdateTexts.ErrorText('start', ''));
end;

procedure TAtlasUpdateInstallUiTests.StageAndOutcomeTexts;
var
  mStage: TUpdateStage;
  mOutcome: TUpdateOutcome;
begin
  mStage := Default(TUpdateStage);
  mStage.Phase := TUpdatePhase.Downloading;
  mStage.Progress := 42;
  Assert.AreEqual(Fmt(TAtlasUpdatesTextId.UpdatesStagePreparing, [42]), TAtlasUpdateTexts.StageText(mStage));
  mStage.Phase := TUpdatePhase.Ready;
  mStage.AskSelection := True;
  Assert.AreEqual(Txt(TAtlasUpdatesTextId.UpdatesStageChoose), TAtlasUpdateTexts.StageText(mStage));
  mOutcome := Default(TUpdateOutcome);
  mOutcome.Kind := TUpdateOutcomeKind.Installed;
  mOutcome.Version := '2.1.0';
  mOutcome.Previous := '2.0.0';
  mOutcome.Added := TArray<string>.Create('Atlas.IDE.Notes');
  Assert.AreEqual(Fmt(TAtlasUpdatesTextId.UpdatesOutcomeInstalled, ['2.1.0', '2.0.0']) + sLineBreak +
    Fmt(TAtlasUpdatesTextId.UpdatesOutcomeAdded, ['Atlas.IDE.Notes']), TAtlasUpdateTexts.OutcomeText(mOutcome));
  mOutcome.Kind := TUpdateOutcomeKind.RolledBack;
  mOutcome.Reason := TUpdateErrors.cLocked;
  Assert.IsTrue(TAtlasUpdateTexts.OutcomeText(mOutcome).Contains(Txt(TAtlasUpdatesTextId.UpdatesErrorLocked)));
  mOutcome.Added := nil;
end;

procedure TAtlasUpdateInstallUiTests.SelectionKeepsRequiredPackages;
var
  mDialog: TAtlasUpdateSelectionDialog;
begin
  mDialog := TAtlasUpdateSelectionDialog.CreateSelection(nil, '2.1.0', TArray<TUpdateCandidate>.Create(
    Candidate('Atlas.IDE.Base', True, True, False), Candidate('Atlas.IDE.Debugger', False, True, False),
    Candidate('Atlas.IDE.Notes', False, False, True)));
  try
    mDialog.Fill;
    Assert.AreEqual(3, mDialog.List.Items.Count);
    Assert.IsFalse(mDialog.List.ItemEnabled[0], 'Kern nicht abwählbar');
    Assert.AreEqual(Fmt(TAtlasUpdatesTextId.UpdatesSelectionNew, ['Atlas.IDE.Notes']), mDialog.List.Items[2]);
    mDialog.List.Checked[1] := False;
    mDialog.List.Checked[2] := True;
    Assert.AreEqual('Atlas.IDE.Base,Atlas.IDE.Notes', string.Join(',', mDialog.Chosen));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasUpdateInstallUiTests.SettingsPageSavesInstallChoices;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsStartupPart>.UpdatesInstall.Choice, 'Vorgabe: anbieten');
    mPage.Part<TAtlasSettingsStartupPart>.UpdatesInstall.Choice := 1;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.AreEqual('auto', mSaved.UpdatesInstall);
    Assert.AreEqual('stable', mSaved.UpdatesChannel);
    Assert.AreEqual('ask', mSaved.UpdatesNewModules);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUpdateConsentTests);
  TDUnitX.RegisterTestFixture(TAtlasUpdateInstallUiTests);

end.
