unit Atlas.Core.Debug.VariablesFlow.Tests;

// Tests für die Entscheidungen des Fensters „Variablen“ (#853, #1967): Text unten im Fenster, vorige Zeile für den
// Server und neue Überwachungen; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasVariablesFlowTests = class
  public
    [Test]
    procedure WithoutServerOnlyWatchCounts;
    [Test]
    procedure SearchStatesFollowSearch;
    [Test]
    procedure TruncatedSearchNamesLimit;
    [Test]
    procedure PreviousLineOnlyInSameFile;
    [Test]
    procedure WatchNeedsNewExpression;
  end;

implementation

uses
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.Variables,
  Atlas.Core.Debug.VariablesFlow;

{ TAtlasVariablesFlowTests }

procedure TAtlasVariablesFlowTests.WithoutServerOnlyWatchCounts;
var
  mSearch: TAtlasVariableSearch;
  mStatus: TAtlasVariablesStatus;
begin
  mSearch := TAtlasVariableSearch.Create;
  try
    mStatus := TAtlasVariablesFlow.Status(mSearch, TAtlasVariablesTab.Locals, 3, True, False);
    Assert.AreEqual<TAtlasVariablesStatusKind>(TAtlasVariablesStatusKind.NoServer, mStatus.Kind);
    mStatus := TAtlasVariablesFlow.Status(mSearch, TAtlasVariablesTab.Watch, 3, True, False);
    Assert.AreEqual<TAtlasVariablesStatusKind>(TAtlasVariablesStatusKind.Count, mStatus.Kind);
    Assert.AreEqual(3, mStatus.Count);
  finally
    mSearch.Free;
  end;
end;

procedure TAtlasVariablesFlowTests.SearchStatesFollowSearch;
var
  mSearch: TAtlasVariableSearch;
  mStatus: TAtlasVariablesStatus;
begin
  mSearch := TAtlasVariableSearch.Create;
  try
    mSearch.Start('Betrag', TAtlasVariableSearchMode.Name, False, 3, 500);
    mStatus := TAtlasVariablesFlow.Status(mSearch, TAtlasVariablesTab.Autos, 5, False, True);
    Assert.AreEqual<TAtlasVariablesStatusKind>(TAtlasVariablesStatusKind.Searching, mStatus.Kind);
    mStatus := TAtlasVariablesFlow.Status(mSearch, TAtlasVariablesTab.Autos, 5, True, True);
    Assert.AreEqual<TAtlasVariablesStatusKind>(TAtlasVariablesStatusKind.Hits, mStatus.Kind);
    Assert.AreEqual(0, mStatus.Hits);
  finally
    mSearch.Free;
  end;
end;

procedure TAtlasVariablesFlowTests.TruncatedSearchNamesLimit;
var
  mSearch: TAtlasVariableSearch;
  mList: TAtlasEvalList;
  mStatus: TAtlasVariablesStatus;
begin
  mSearch := TAtlasVariableSearch.Create;
  mList := TAtlasEvalList.Create;
  try
    mList.SetResult(mList.Add('Kunde'), True, '(Name: ''Meier''; Ort: ''Berlin'')');
    // Ohne erlaubte Auswertung ist die Suche sofort an der Grenze.
    mSearch.Start('Berlin', TAtlasVariableSearchMode.Value, True, 3, 0);
    Assert.IsNull(mSearch.NextToOpen(mList));
    mStatus := TAtlasVariablesFlow.Status(mSearch, TAtlasVariablesTab.Autos, 1, True, True);
    Assert.AreEqual<TAtlasVariablesStatusKind>(TAtlasVariablesStatusKind.Truncated, mStatus.Kind);
    Assert.AreEqual(0, mStatus.Evaluations);
  finally
    mList.Free;
    mSearch.Free;
  end;
end;

procedure TAtlasVariablesFlowTests.PreviousLineOnlyInSameFile;
begin
  Assert.AreEqual(41, TAtlasVariablesFlow.PreviousLine('C:\P\a.pas', 41, 'C:\P\A.PAS'));
  Assert.AreEqual(-1, TAtlasVariablesFlow.PreviousLine('C:\P\b.pas', 41, 'C:\P\a.pas'));
  Assert.AreEqual(-1, TAtlasVariablesFlow.PreviousLine('', -1, 'C:\P\a.pas'));
end;

procedure TAtlasVariablesFlowTests.WatchNeedsNewExpression;
var
  mList: TAtlasEvalList;
begin
  mList := TAtlasEvalList.Create;
  try
    mList.Add('Kunde.Name');
    Assert.IsFalse(TAtlasVariablesFlow.CanAddWatch(mList, '  '));
    Assert.IsFalse(TAtlasVariablesFlow.CanAddWatch(mList, ' Kunde.Name '));
    Assert.IsTrue(TAtlasVariablesFlow.CanAddWatch(mList, 'Kunde.Ort'));
  finally
    mList.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVariablesFlowTests);

end.
