unit Atlas.Core.Tracker.PaletteSearchPlan.Tests;

// Tests der Issue-Suche in der Befehlspalette ohne IDE (#1967): was mit einer Antwort geschieht, Fehlertexte,
// anonymes Protokoll, Issue zur Zeile, Entprellung, Hinweis ohne Tracker und Tasten für Übergänge.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasIssuePaletteSearchPlanTests = class
  public
    [Test]
    procedure AnswerShowsIgnoresOrFails;
    [Test]
    procedure ErrorTextByKind;
    [Test]
    procedure LogIsAnonymous;
    [Test]
    procedure IssueFromAnswerOrRow;
    [Test]
    procedure InputKeyHintAndStateKeys;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.PaletteSearch,
  Atlas.Core.Tracker.PaletteSearchPlan;

procedure TAtlasIssuePaletteSearchPlanTests.AnswerShowsIgnoresOrFails;
begin
  Assert.AreEqual(Integer(Ord(TAtlasIssueSearchAnswer.Show)),
    Integer(Ord(TAtlasIssuePaletteSearchPlan.AnswerOf(True, TAtlasCiFetchError.None))));
  Assert.AreEqual(Integer(Ord(TAtlasIssueSearchAnswer.Ignore)),
    Integer(Ord(TAtlasIssuePaletteSearchPlan.AnswerOf(False, TAtlasCiFetchError.Cancelled))), 'abgebrochen');
  Assert.AreEqual(Integer(Ord(TAtlasIssueSearchAnswer.Error)),
    Integer(Ord(TAtlasIssuePaletteSearchPlan.AnswerOf(False, TAtlasCiFetchError.Network))));
end;

procedure TAtlasIssuePaletteSearchPlanTests.ErrorTextByKind;
begin
  Assert.AreEqual(Integer(Ord(TAtlasIssueSearchError.KeyNotFound)), Integer(Ord(TAtlasIssuePaletteSearchPlan.ErrorOf(
    TAtlasCiFetchError.NotFound, TAtlasIssueSearchKind.Key))));
  Assert.AreEqual(Integer(Ord(TAtlasIssueSearchError.NoneFound)), Integer(Ord(TAtlasIssuePaletteSearchPlan.ErrorOf(
    TAtlasCiFetchError.NotFound, TAtlasIssueSearchKind.Text))));
  Assert.AreEqual(Integer(Ord(TAtlasIssueSearchError.Config)), Integer(Ord(TAtlasIssuePaletteSearchPlan.ErrorOf(
    TAtlasCiFetchError.NotConfigured, TAtlasIssueSearchKind.Text))));
  Assert.AreEqual(Integer(Ord(TAtlasIssueSearchError.Token)), Integer(Ord(TAtlasIssuePaletteSearchPlan.ErrorOf(
    TAtlasCiFetchError.Unauthorized, TAtlasIssueSearchKind.Key))));
  Assert.AreEqual(Integer(Ord(TAtlasIssueSearchError.Timeout)), Integer(Ord(TAtlasIssuePaletteSearchPlan.ErrorOf(
    TAtlasCiFetchError.Timeout, TAtlasIssueSearchKind.Key))));
  Assert.AreEqual(Integer(Ord(TAtlasIssueSearchError.Invalid)), Integer(Ord(TAtlasIssuePaletteSearchPlan.ErrorOf(
    TAtlasCiFetchError.Server, TAtlasIssueSearchKind.Key))));
end;

procedure TAtlasIssuePaletteSearchPlanTests.LogIsAnonymous;
begin
  Assert.AreEqual('Palettensuche: GitHub, 3 Treffer', TAtlasIssuePaletteSearchPlan.AnswerLog('GitHub', True, 3,
    TAtlasCiFetchError.None));
  Assert.AreEqual('Palettensuche: YouTrack, keine Antwort (' + TAtlasCiBuild.ErrorKey(TAtlasCiFetchError.Timeout) +
    ')', TAtlasIssuePaletteSearchPlan.AnswerLog('YouTrack', False, 0, TAtlasCiFetchError.Timeout));
end;

procedure TAtlasIssuePaletteSearchPlanTests.IssueFromAnswerOrRow;
var
  mIssues: TArray<TAtlasTrackerIssue>;
  mItem: TAtlasCommand;
  mIssue: TAtlasTrackerIssue;
begin
  SetLength(mIssues, 1);
  mIssues[0] := TAtlasTrackerIssue.Empty;
  mIssues[0].Key := 'ATL-12';
  mIssues[0].State := 'Offen';
  mItem := Default(TAtlasCommand);
  mItem.Id := 'atl-12';
  Assert.IsTrue(TAtlasIssuePaletteSearchPlan.IssueOf(mIssues, mItem, mIssue));
  Assert.AreEqual('Offen', mIssue.State, 'aus der Antwort');
  mItem.Id := 'ATL-7';
  mItem.Description := 'Titel';
  Assert.IsTrue(TAtlasIssuePaletteSearchPlan.IssueOf(mIssues, mItem, mIssue));
  Assert.AreEqual('ATL-7', mIssue.Key);
  Assert.AreEqual('Titel', mIssue.Title, 'aus der Zeile');
  mItem.Id := '';
  Assert.IsFalse(TAtlasIssuePaletteSearchPlan.IssueOf(mIssues, mItem, mIssue));
  mIssues := nil;
end;

procedure TAtlasIssuePaletteSearchPlanTests.InputKeyHintAndStateKeys;
var
  mQuery: TAtlasIssueSearchQuery;
begin
  mQuery := TAtlasIssueSearchQuery.None;
  mQuery.Key := 'ATL-1';
  mQuery.Text := 'leck';
  Assert.AreEqual('ATL-1|leck', TAtlasIssuePaletteSearchPlan.InputKey(mQuery));
  Assert.IsTrue(TAtlasIssuePaletteSearchPlan.IsIssueInput('  #42'));
  Assert.IsFalse(TAtlasIssuePaletteSearchPlan.IsIssueInput('Optionen'));
  Assert.IsTrue(TAtlasIssuePaletteSearchPlan.RunsState(TAtlasPaletteAction.Open));
  Assert.IsTrue(TAtlasIssuePaletteSearchPlan.RunsState(TAtlasPaletteAction.Start));
  Assert.IsFalse(TAtlasIssuePaletteSearchPlan.RunsState(TAtlasPaletteAction.Browse));
  Assert.IsFalse(TAtlasIssuePaletteSearchPlan.RunsState(TAtlasPaletteAction.Copy));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssuePaletteSearchPlanTests);

end.
