unit Atlas.UI.Tracker.IssueTip.Tests;

// Hover über einer Issue-Kennung im Editor (#1265): Titel, Zustand,
// Zuständig und Alter, „Wird geladen …“, nicht gefunden, Fehlergrund und die
// Fußzeile je nach issues.preview.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasIssueTipTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Abnahme: Hover zeigt Titel und Zustand, dazu Zuständig und Aktualisiert.</summary>
    [Test]
    procedure FoundShowsTitleStateAssigneeAndAge;
    [Test]
    procedure FoundWithoutFieldsShowsOnlyTitle;
    [Test]
    procedure LoadingUntilAnswer;
    /// <summary>Abnahme: 404 zeigt „Issue ATL-9 nicht gefunden.“</summary>
    [Test]
    procedure NotFoundNamesKey;
    [Test]
    procedure FailedShowsReason;
    [Test]
    procedure FooterFollowsPreviewSetting;
    [Test]
    procedure AgeTextUnits;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.UI.Tracker.IssueTip;

const
  cNow = 46323.5;

function Sample: TAtlasTrackerDetails;
begin
  Result := TAtlasTrackerDetails.Empty;
  Result.Key := 'ATL-123';
  Result.Title := 'Sperre prüfen';
  Result.State := 'Open';
  Result.Assignee := 'Marco';
  Result.Updated := cNow - 3.5 / 24;
end;

procedure TAtlasIssueTipTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasIssueTipTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasIssueTipTests.FoundShowsTitleStateAssigneeAndAge;
var
  mTitle, mText: string;
begin
  TAtlasIssueTip.Compose('ATL-123', TAtlasIssueTipState.Found, Sample, TAtlasCiFetchError.None, cNow, True, mTitle,
    mText);
  Assert.AreEqual('ATL-123', mTitle);
  Assert.AreEqual('Sperre prüfen' + #10 + 'Zustand: Open · Zuständig: Marco · aktualisiert vor 3 Std.' + #10#10 +
    'Strg+Klick: Vorschau · Strg+Umschalt+Klick: Browser', mText);
end;

procedure TAtlasIssueTipTests.FoundWithoutFieldsShowsOnlyTitle;
var
  mDetails: TAtlasTrackerDetails;
  mTitle, mText: string;
begin
  mDetails := TAtlasTrackerDetails.Empty;
  mDetails.Key := '#42';
  mDetails.Title := 'Absturz beim Speichern';
  TAtlasIssueTip.Compose('#42', TAtlasIssueTipState.Found, mDetails, TAtlasCiFetchError.None, cNow, True, mTitle,
    mText);
  Assert.AreEqual('#42', mTitle);
  Assert.AreEqual('Absturz beim Speichern' + #10#10 + 'Strg+Klick: Vorschau · Strg+Umschalt+Klick: Browser', mText);
end;

procedure TAtlasIssueTipTests.LoadingUntilAnswer;
var
  mTitle, mText: string;
begin
  TAtlasIssueTip.Compose('ATL-1', TAtlasIssueTipState.Loading, TAtlasTrackerDetails.Empty, TAtlasCiFetchError.None,
    cNow, True, mTitle, mText);
  Assert.AreEqual('ATL-1', mTitle);
  Assert.IsTrue(mText.StartsWith(TAtlasStrings.Text(TAtlasTextId.IssuePreviewLoading) + #10#10));
end;

procedure TAtlasIssueTipTests.NotFoundNamesKey;
var
  mTitle, mText: string;
begin
  TAtlasIssueTip.Compose('ATL-9', TAtlasIssueTipState.NotFound, TAtlasTrackerDetails.Empty,
    TAtlasCiFetchError.NotFound, cNow, True, mTitle, mText);
  Assert.IsTrue(mText.StartsWith('Issue ATL-9 nicht gefunden.' + #10#10), mText);
end;

procedure TAtlasIssueTipTests.FailedShowsReason;
var
  mTitle, mText: string;
begin
  TAtlasIssueTip.Compose('ATL-9', TAtlasIssueTipState.Failed, TAtlasTrackerDetails.Empty,
    TAtlasCiFetchError.Unauthorized, cNow, True, mTitle, mText);
  Assert.IsTrue(mText.StartsWith(TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorToken)), mText);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorNetwork),
    TAtlasIssueTip.ErrorText(TAtlasCiFetchError.Network, 'ATL-9'));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorConfig),
    TAtlasIssueTip.ErrorText(TAtlasCiFetchError.UnknownProvider, 'ATL-9'));
end;

procedure TAtlasIssueTipTests.FooterFollowsPreviewSetting;
var
  mTitle, mText: string;
begin
  TAtlasIssueTip.Compose('ATL-1', TAtlasIssueTipState.Found, Sample, TAtlasCiFetchError.None, cNow, False, mTitle,
    mText);
  Assert.IsTrue(mText.EndsWith(#10#10 + 'Strg+Klick: im Browser öffnen'), mText);
  TAtlasStrings.Language := TAtlasLanguage.English;
  TAtlasIssueTip.Compose('ATL-1', TAtlasIssueTipState.Found, Sample, TAtlasCiFetchError.None, cNow, True, mTitle,
    mText);
  Assert.IsTrue(mText.EndsWith(#10#10 + 'Ctrl+click: preview · Ctrl+Shift+click: browser'), mText);
end;

procedure TAtlasIssueTipTests.AgeTextUnits;
begin
  Assert.AreEqual('gerade eben', TAtlasIssueTip.AgeText(cNow, cNow));
  Assert.AreEqual('vor 5 Min.', TAtlasIssueTip.AgeText(cNow - 5.5 / 1440, cNow));
  Assert.AreEqual('vor 2 Tg.', TAtlasIssueTip.AgeText(cNow - 2.2, cNow));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssueTipTests);

end.
