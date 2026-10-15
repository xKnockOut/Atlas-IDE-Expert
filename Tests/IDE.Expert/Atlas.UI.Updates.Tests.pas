unit Atlas.UI.Updates.Tests;

// Rückfrage zur Update-Prüfung beim ersten Start (#495): Text, Knöpfe, nur
// die erste Antwort zählt; dazu Version und Schalter auf der Optionsseite.

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

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.Core.Product.Version,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Updates.Check,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Page,
  Atlas.UI.Updates.Consent;

procedure TAtlasUpdateConsentTests.WarmUpFirstUse;
begin
  AsksOnceAndRunsFirstAnswer;
end;

procedure TAtlasUpdateConsentTests.AsksOnceAndRunsFirstAnswer;
var
  Consent: TAtlasUpdateConsent;
  Yes, No: Integer;
begin
  Yes := 0;
  No := 0;
  Consent := TAtlasUpdateConsent.CreateConsent(nil);
  Consent.OnYes :=
    procedure
    begin
      Inc(Yes);
    end;
  Consent.OnNo :=
    procedure
    begin
      Inc(No);
    end;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.UpdatesConsentTitle), Consent.Caption);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.UpdatesConsentText), Consent.TextLabel.Caption);
  Assert.Contains(Consent.TextLabel.Caption, 'IDE-Version');
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.UpdatesConsentYes), Consent.YesButton.Caption);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.UpdatesConsentNo), Consent.NoButton.Caption);
  // Nur die erste Antwort zählt; ausgeführt nach dem Schließen (das Fenster gibt sich selbst frei).
  Consent.YesButton.Click;
  Consent.NoButton.Click;
  Application.ProcessMessages;
  CheckSynchronize;
  Assert.AreEqual(1, Yes);
  Assert.AreEqual(0, No);
end;

procedure TAtlasUpdateConsentTests.NoAnswersNo;
var
  Consent: TAtlasUpdateConsent;
  Yes, No: Integer;
begin
  Yes := 0;
  No := 0;
  Consent := TAtlasUpdateConsent.CreateConsent(nil);
  Consent.OnYes :=
    procedure
    begin
      Inc(Yes);
    end;
  Consent.OnNo :=
    procedure
    begin
      Inc(No);
    end;
  Consent.NoButton.Click;
  Application.ProcessMessages;
  CheckSynchronize;
  Assert.AreEqual(0, Yes);
  Assert.AreEqual(1, No);
end;

procedure TAtlasUpdateConsentTests.SettingsPageShowsVersionAndSwitch;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.UpdatesCheck.Checked, 'Vorgabe aus');
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SettingsVersion, [TAtlasPluginVersion.Version,
      TAtlasUpdates.IdeVersion]), Page.VersionLabel.Caption);
    Page.UpdatesCheck.Checked := True;
    // Fehlerbericht (#108): anonymisiert als Vorgabe, abschaltbar.
    Assert.IsTrue(Page.BugReportAnonymize.Checked);
    Page.BugReportAnonymize.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.UpdatesCheck);
    Assert.IsFalse(Saved.BugReportAnonymize);
  finally
    Page.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUpdateConsentTests);

end.
