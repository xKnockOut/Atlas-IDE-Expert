unit Atlas.UI.Tracker.IssueTip.Tests;

// Hover über einer Issue-Kennung im Editor (#1265): Titel, Zustand,
// Zuständig und Alter, „Wird geladen …“, nicht gefunden, Fehlergrund und die
// Fußzeile je nach issues.preview. Für die Zeilenhistorie (#1275): Zeile je
// Kennung, Link „Issues zu dieser Methode (n)“, Zeilen und Titel des
// Ergebnisfensters.

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
    /// <summary>Abnahme #1275: Hover der Zeilenhistorie zeigt Titel und Zustand je Kennung.</summary>
    [Test]
    procedure KeyLineForBlameHover;
    [Test]
    procedure ScopeLinkAndFooter;
    [Test]
    procedure IssueAndCommitRows;
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

procedure TAtlasIssueTipTests.KeyLineForBlameHover;
begin
  Assert.AreEqual('ATL-123 · Sperre prüfen · Open', TAtlasIssueTip.KeyLine('ATL-123', TAtlasIssueTipState.Found,
    Sample, TAtlasCiFetchError.None));
  Assert.AreEqual('ATL-1 · Wird geladen …', TAtlasIssueTip.KeyLine('ATL-1', TAtlasIssueTipState.Loading,
    TAtlasTrackerDetails.Empty, TAtlasCiFetchError.None));
  Assert.AreEqual('ATL-9 · Issue ATL-9 nicht gefunden.', TAtlasIssueTip.KeyLine('ATL-9',
    TAtlasIssueTipState.NotFound, TAtlasTrackerDetails.Empty, TAtlasCiFetchError.NotFound));
  Assert.AreEqual('ATL-9 · ' + TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorNetwork),
    TAtlasIssueTip.KeyLine('ATL-9', TAtlasIssueTipState.Failed, TAtlasTrackerDetails.Empty,
    TAtlasCiFetchError.Network));
end;

procedure TAtlasIssueTipTests.ScopeLinkAndFooter;
begin
  Assert.AreEqual('Issues zu dieser Methode (3)', TAtlasIssueTip.ScopeLink(True, 3));
  Assert.AreEqual('Issues zu dieser Methode', TAtlasIssueTip.ScopeLink(True, -1), 'wird noch gesucht');
  Assert.AreEqual('Issues zu dieser Unit (0)', TAtlasIssueTip.ScopeLink(False, 0));
  Assert.AreEqual('Strg+Klick auf die Kennung: Vorschau', TAtlasIssueTip.BlameFooter(True));
  Assert.AreEqual('Strg+Klick auf die Kennung: im Browser öffnen', TAtlasIssueTip.BlameFooter(False));
  TAtlasStrings.Language := TAtlasLanguage.English;
  Assert.AreEqual('Issues for this method (3)', TAtlasIssueTip.ScopeLink(True, 3));
end;

procedure TAtlasIssueTipTests.IssueAndCommitRows;
begin
  Assert.AreEqual('ATL-123 · Sperre prüfen · Open · vor 2 Tg. · 4 Commits', TAtlasIssueTip.IssueRow('ATL-123', True,
    Sample, cNow - 2.2, cNow, 4));
  Assert.AreEqual('ATL-7 · vor 2 Tg. · 1 Commit', TAtlasIssueTip.IssueRow('ATL-7', False,
    TAtlasTrackerDetails.Empty, cNow - 2.2, cNow, 1), 'Titel und Zustand erst nach der Abfrage');
  Assert.AreEqual('2e17e3b · anna · 12.10.2026 · ATL-7 Rundung', TAtlasIssueTip.CommitRow('2e17e3b', 'anna',
    EncodeDate(2026, 10, 12) + 0.5, 'ATL-7 Rundung'));
  Assert.AreEqual('r42', TAtlasIssueTip.CommitRow('r42', '', 0, ''));
  Assert.AreEqual('Issues zu TKunde.Laden · 3 Issues aus 7 Commits · 2 ohne Kennung',
    TAtlasIssueTip.ScopeTitle('TKunde.Laden', 3, 7, 2));
  Assert.AreEqual('Issues zu Unit Kunde.pas · 0 Issues aus 0 Commits', TAtlasIssueTip.ScopeTitle('Unit Kunde.pas', 0,
    0, 0));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssueTipTests);

end.
