unit Atlas.Core.Problems.Findings.Tests;

// Tests für das Modell des Fensters „Atlas-Prüfung“ (#909): Art und Kategorie,
// Befunde aus dem Speicher, Filter, Gruppierung, Sortierung, Zähler, Auswahl
// und Aufklappzustand über Aktualisierungen, mitwandernde Zeilen, Spalten.
// Offene Units zuerst (#1108): Stufen je Gruppierung, Trennzeilen, Grau,
// Ausblenden, aktive Unit ohne Befunde, Formulare, Farben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasFindingsTests = class
  public
    [Test]
    procedure SeverityMapsToKind;
    [Test]
    procedure CategoryFromCatalogAndCompiler;
    [Test]
    procedure StoreGivesFindingsWithLineTextWithoutInactiveUsesAndTests;
    [Test]
    procedure ReadLineFillsTextOfUnopenedFiles;
    [Test]
    procedure KeysDoNotDependOnTheLine;
    [Test]
    procedure ShortensLongLines;
    [Test]
    procedure LocationIsOneBased;
    [Test]
    procedure DefaultSortIsKindFileLine;
    [Test]
    procedure ColumnClickSortsAndSecondClickReverses;
    [Test]
    procedure FiltersByKindCategoryTextAndCompiler;
    /// <summary>#1024: Spalte „Compiler“ und Meldung ohne „(wie E2035)“.</summary>
    [Test]
    procedure CompilerColumnText;
    [Test]
    procedure ScopeLimitsFiles;
    [Test]
    procedure CountsIgnoreKindToggles;
    [Test]
    procedure GroupsByFileRuleAndCategory;
    [Test]
    procedure CollapsedGroupStaysCollapsedAfterUpdate;
    [Test]
    procedure SelectionSurvivesUpdateAndShiftedLines;
    [Test]
    procedure NewFindingsAreMarkedOnlyAfterFirstFill;
    [Test]
    procedure StepWrapsAndExpandsGroup;
    [Test]
    procedure SelectAtFollowsCursor;
    [Test]
    procedure FindingsOfRowsTakesGroupMembersOnce;
    [Test]
    procedure ColumnsRoundTripAndKeepMandatoryVisible;
    [Test]
    procedure ScopeAndGroupingNames;
    [Test]
    procedure CheckedCountCountsDeliveredFiles;
    [Test]
    procedure CopyTextUsesCompilerFormat;
  end;

  /// <summary>Stufen, angeheftete Gruppen, geschlossene Units und der Zeilencache der Befundliste.</summary>
  [TestFixture]
  TAtlasFindingsTierTests = class
  public
    /// <summary>#1108: aktive Unit angepinnt, Trennzeilen, geöffnete und nicht geöffnete Gruppen alphabetisch.
    /// </summary>
    [Test]
    procedure TiersOrderFileGroups;
    [Test]
    procedure TiersWithoutGroupingAreSections;
    [Test]
    procedure TiersInsideRuleAndCategoryGroups;
    [Test]
    procedure ColumnSortWorksInsideTiers;
    [Test]
    procedure SwitchingEditorMovesOnlyPinnedGroup;
    [Test]
    procedure SectionsAreSkippedBySelectionStepAndCopy;
    [Test]
    procedure ClosedUnitsDimmedNormalHidden;
    [Test]
    procedure CleanActiveUnitShowsWithoutFindings;
    [Test]
    procedure SelectionAndCollapseSurviveResort;
    [Test]
    procedure FormFilePinsItsUnitIgnoringCase;
    [Test]
    procedure OpenFirstOffKeepsOrderOf909;
    [Test]
    procedure CurrentFileScopeHasNoSections;
    [Test]
    procedure ProjectScopeLimitsClosedUnits;
    [Test]
    procedure ClosedUnitsNames;
    [Test]
    procedure DimmedColorsStayReadable;
    [Test]
    procedure ReadLinesOncePerFile;
    [Test]
    procedure StampChangesOnlyForTheChangedFile;
    [Test]
    procedure CacheRebuildsOnlyChangedFiles;
    [Test]
    procedure CacheSurvivesNewStore;
    [Test]
    [Category('Benchmark')]
    procedure CacheWithManyFindingsIsFast;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Problems.FindingsView,
  Atlas.Core.Problems.FindingsCache,
  Atlas.Core.Style.Color,
  Atlas.Core.Problems.Colors;

function Problem(ALine: Integer; const ACode, AMessage: string; ASeverity: TAtlasProblemSeverity): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.StartLine := ALine;
  Result.StartCharacter := 2;
  Result.EndLine := ALine;
  Result.EndCharacter := 5;
  Result.Code := ACode;
  Result.Message := AMessage;
  Result.Source := 'Atlas';
  Result.Severity := ASeverity;
  Result.Category := 'code-smell';
end;

function Finding(const AFileName: string; ALine: Integer; const ACode: string; ASeverity: TAtlasProblemSeverity):
  TAtlasFinding;
begin
  Result := TAtlasFindings.FromProblems(AFileName, [Problem(ALine, ACode, 'Meldung ' + ACode, ASeverity)], nil)[0];
end;

function Sample: TArray<TAtlasFinding>;
begin
  Result := TAtlasFindings.FromProblems('C:\P\B.pas', [Problem(9, 'empty-except', 'Leer', TAtlasProblemSeverity.Warning),
    Problem(3, 'syntax', 'Fehlt', TAtlasProblemSeverity.Error)], nil) +
    TAtlasFindings.FromProblems('C:\P\A.pas', [Problem(1, 'todo-comment', 'TODO', TAtlasProblemSeverity.Hint),
    Problem(7, 'empty-except', 'Leer', TAtlasProblemSeverity.Warning)], nil);
end;

function Locations(AView: TAtlasFindingsView): string;
var
  mItem: TAtlasFinding;
begin
  Result := '';
  for mItem in AView.Visible do
  begin
    Result := Result + mItem.Location + ' ';
  end;
  Result := Result.Trim;
end;

procedure TAtlasFindingsTests.SeverityMapsToKind;
begin
  Assert.AreEqual<TAtlasFindingKind>(TAtlasFindingKind.Error, TAtlasFindings.KindOf(TAtlasProblemSeverity.Error));
  Assert.AreEqual<TAtlasFindingKind>(TAtlasFindingKind.Warning, TAtlasFindings.KindOf(TAtlasProblemSeverity.Warning));
  Assert.AreEqual<TAtlasFindingKind>(TAtlasFindingKind.Info, TAtlasFindings.KindOf(TAtlasProblemSeverity.Information));
  Assert.AreEqual<TAtlasFindingKind>(TAtlasFindingKind.Info, TAtlasFindings.KindOf(TAtlasProblemSeverity.Hint));
end;

procedure TAtlasFindingsTests.CategoryFromCatalogAndCompiler;
var
  mItem: TAtlasProblem;
begin
  mItem := Problem(0, 'x', 'm', TAtlasProblemSeverity.Error);
  mItem.Category := 'bug';
  Assert.AreEqual<TAtlasFindingCategory>(TAtlasFindingCategory.Bug, TAtlasFindings.CategoryOf(mItem));
  mItem.Category := 'security-hotspot';
  Assert.AreEqual<TAtlasFindingCategory>(TAtlasFindingCategory.SecurityHotspot, TAtlasFindings.CategoryOf(mItem));
  mItem.Category := '';
  Assert.AreEqual<TAtlasFindingCategory>(TAtlasFindingCategory.Other, TAtlasFindings.CategoryOf(mItem));
  mItem.Source := TAtlasProblem.cCompilerSource;
  mItem.Category := 'bug';
  Assert.AreEqual<TAtlasFindingCategory>(TAtlasFindingCategory.Compiler, TAtlasFindings.CategoryOf(mItem));
end;

procedure TAtlasFindingsTests.StoreGivesFindingsWithLineTextWithoutInactiveUsesAndTests;
var
  mStore: TAtlasProblemStore;
  mInactive, mUsesHint: TAtlasProblem;
  mItems: TArray<TAtlasFinding>;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mInactive := Problem(0, '', 'inaktiv', TAtlasProblemSeverity.Hint);
    mInactive.Unnecessary := True;
    mUsesHint := Problem(0, 'unused-uses', 'ungenutzt', TAtlasProblemSeverity.Hint);
    mUsesHint.UsesUnit := 'System.Math';
    mUsesHint.UsesState := TAtlasProblem.cUsesUnused;
    mStore.Update('C:\P\A.pas', 'unit A;' + #10 + '    x := 1;   ' + #10, True,
      [Problem(1, 'r', 'Treffer', TAtlasProblemSeverity.Warning), mInactive, mUsesHint], '', True);
    mItems := TAtlasFindings.FromStore(mStore, nil, nil);
    Assert.AreEqual(1, Integer(Length(mItems)));
    Assert.AreEqual('x := 1;', mItems[0].LineText);
    Assert.AreEqual('C:\P\A.pas', mItems[0].FileName);
    Assert.AreEqual<TAtlasFindingKind>(TAtlasFindingKind.Warning, mItems[0].Kind);
    Assert.IsFalse(TAtlasFindings.IsFinding(mInactive));
    Assert.IsFalse(TAtlasFindings.IsFinding(mUsesHint));
    mInactive := Problem(0, '', 'Test', TAtlasProblemSeverity.Error);
    mInactive.Source := TAtlasProblemStore.cTestSource;
    Assert.IsFalse(TAtlasFindings.IsFinding(mInactive));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasFindingsTests.ReadLineFillsTextOfUnopenedFiles;
var
  mStore: TAtlasProblemStore;
  mItems: TArray<TAtlasFinding>;
  mReadLines: TFunc<string, TArray<string>>;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update('C:\P\Zu.pas', '', False, [Problem(4, 'r', 'Treffer', TAtlasProblemSeverity.Error)], '', True);
    mReadLines :=
      function(AFileName: string): TArray<string>
      begin
        Result := TArray<string>.Create('', '', '', '', Format('  %s:%d', [ExtractFileName(AFileName), 4]));
      end;
    mItems := TAtlasFindings.FromStore(mStore, ['C:\P\Zu.pas'], mReadLines);
    Assert.AreEqual('Zu.pas:4', mItems[0].LineText);
    mItems := TAtlasFindings.FromStore(mStore, nil, nil);
    Assert.AreEqual('', mItems[0].LineText);
  finally
    mStore.Free;
  end;
end;

procedure TAtlasFindingsTests.KeysDoNotDependOnTheLine;
var
  mFirst, mMoved: TArray<TAtlasFinding>;
begin
  mFirst := TAtlasFindings.FromProblems('C:\P\A.pas', [Problem(3, 'r', 'm', TAtlasProblemSeverity.Error),
    Problem(5, 'r', 'm', TAtlasProblemSeverity.Error)], nil);
  mMoved := TAtlasFindings.FromProblems('C:\P\A.pas', [Problem(13, 'r', 'm', TAtlasProblemSeverity.Error),
    Problem(15, 'r', 'm', TAtlasProblemSeverity.Error)], nil);
  Assert.AreEqual(mFirst[0].Key, mMoved[0].Key);
  Assert.AreEqual(mFirst[1].Key, mMoved[1].Key);
  Assert.AreNotEqual(mFirst[0].Key, mFirst[1].Key);
end;

procedure TAtlasFindingsTests.ShortensLongLines;
begin
  Assert.AreEqual('abc', TAtlasFindings.Shorten('   abc  ', 10));
  Assert.AreEqual('abcd…', TAtlasFindings.Shorten('abcdefghij', 5));
  Assert.AreEqual('abcdefghij', TAtlasFindings.Shorten('abcdefghij', 10));
end;

procedure TAtlasFindingsTests.LocationIsOneBased;
begin
  Assert.AreEqual('A.pas:4:3', Finding('C:\P\A.pas', 3, 'r', TAtlasProblemSeverity.Error).Location);
  Assert.AreEqual('r', Finding('C:\P\A.pas', 3, 'r', TAtlasProblemSeverity.Error).Rule);
end;

procedure TAtlasFindingsTests.DefaultSortIsKindFileLine;
var
  mView: TAtlasFindingsView;
begin
  mView := TAtlasFindingsView.Create;
  try
    mView.Grouping := TAtlasFindingGrouping.None;
    mView.SetFindings(Sample);
    Assert.AreEqual('B.pas:4:3 A.pas:8:3 B.pas:10:3 A.pas:2:3', Locations(mView));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTests.ColumnClickSortsAndSecondClickReverses;
var
  mView: TAtlasFindingsView;
begin
  mView := TAtlasFindingsView.Create;
  try
    mView.Grouping := TAtlasFindingGrouping.None;
    mView.SetFindings(Sample);
    mView.SortBy(TAtlasFindingColumn.Location);
    Assert.AreEqual('A.pas:2:3 A.pas:8:3 B.pas:4:3 B.pas:10:3', Locations(mView));
    mView.SortBy(TAtlasFindingColumn.Location);
    Assert.IsTrue(mView.SortDescending);
    Assert.AreEqual('B.pas:10:3 B.pas:4:3 A.pas:8:3 A.pas:2:3', Locations(mView));
    mView.SortBy(TAtlasFindingColumn.Rule);
    Assert.IsFalse(mView.SortDescending);
    Assert.AreEqual('A.pas:8:3 B.pas:10:3 B.pas:4:3 A.pas:2:3', Locations(mView));
    mView.ResetSort;
    Assert.AreEqual('B.pas:4:3 A.pas:8:3 B.pas:10:3 A.pas:2:3', Locations(mView));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTests.CompilerColumnText;
var
  mItem: TAtlasFinding;
begin
  mItem := Default(TAtlasFinding);
  mItem.Problem := Problem(1, 'argument-count-mismatch', 'X erwartet 1 Argumente (wie E2035).',
    TAtlasProblemSeverity.Error);
  Assert.AreEqual('', mItem.CompilerText);
  mItem.Problem.CompilerCodes := ['E2034', 'E2035'];
  Assert.AreEqual('E2034, E2035', mItem.CompilerText);
  mItem.Problem.Confirmed := True;
  mItem.Problem.ConfirmedCode := 'E2035';
  Assert.AreEqual('E2035 ' + #$00B7 + ' Atlas + dcc', mItem.CompilerText);
  Assert.AreEqual('X erwartet 1 Argumente (wie E2035).', mItem.MessageText(True));
  Assert.AreEqual('X erwartet 1 Argumente.', mItem.MessageText(False));
  mItem.Problem := Problem(1, 'W1036', 'Variable nicht initialisiert', TAtlasProblemSeverity.Warning);
  mItem.Problem.Source := TAtlasProblem.cCompilerSource;
  Assert.AreEqual('W1036', mItem.CompilerText);
end;

procedure TAtlasFindingsTests.FiltersByKindCategoryTextAndCompiler;
var
  mView: TAtlasFindingsView;
  mFilter: TAtlasFindingFilter;
  mItems: TArray<TAtlasFinding>;
  mCompiler: TAtlasProblem;
begin
  mCompiler := Problem(2, 'W1036', 'Variable nicht initialisiert', TAtlasProblemSeverity.Warning);
  mCompiler.Source := TAtlasProblem.cCompilerSource;
  mItems := Sample + TAtlasFindings.FromProblems('C:\P\C.pas', [mCompiler], nil);
  mItems[1].Category := TAtlasFindingCategory.Bug;
  mView := TAtlasFindingsView.Create;
  try
    mView.Grouping := TAtlasFindingGrouping.None;
    mView.SetFindings(mItems);
    Assert.AreEqual(4, Integer(Length(mView.Visible)));
    mFilter := mView.Filter;
    mFilter.Compiler := True;
    mView.Filter := mFilter;
    Assert.AreEqual(5, Integer(Length(mView.Visible)));
    mFilter.Kinds := [TAtlasFindingKind.Warning];
    mView.Filter := mFilter;
    Assert.AreEqual('A.pas:8:3 B.pas:10:3 C.pas:3:3', Locations(mView));
    mFilter.Kinds := [TAtlasFindingKind.Error, TAtlasFindingKind.Warning, TAtlasFindingKind.Info];
    mFilter.OneCategory := True;
    mFilter.Category := TAtlasFindingCategory.Bug;
    mView.Filter := mFilter;
    Assert.AreEqual('B.pas:4:3', Locations(mView));
    mFilter.OneCategory := False;
    mFilter.Text := 'TODO';
    mView.Filter := mFilter;
    Assert.AreEqual('A.pas:2:3', Locations(mView));
    mFilter.Text := 'b.pas';
    mView.Filter := mFilter;
    Assert.AreEqual(2, Integer(Length(mView.Visible)));
    mFilter.Text := 'EMPTY-except';
    mView.Filter := mFilter;
    Assert.AreEqual(2, Integer(Length(mView.Visible)));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTests.ScopeLimitsFiles;
var
  mView: TAtlasFindingsView;
  mFilter: TAtlasFindingFilter;
begin
  mView := TAtlasFindingsView.Create;
  try
    mView.Grouping := TAtlasFindingGrouping.None;
    mView.SetFindings(Sample);
    mFilter := mView.Filter;
    mFilter.Scope := TAtlasFindingScope.CurrentFile;
    mFilter.CurrentFile := 'c:\p\a.pas';
    mView.Filter := mFilter;
    Assert.AreEqual('A.pas:8:3 A.pas:2:3', Locations(mView));
    mFilter.Scope := TAtlasFindingScope.Project;
    mFilter.Files := ['C:\P\B.pas'];
    mView.Filter := mFilter;
    Assert.AreEqual('B.pas:4:3 B.pas:10:3', Locations(mView));
    mFilter.Scope := TAtlasFindingScope.Group;
    mFilter.Files := nil;
    mView.Filter := mFilter;
    Assert.AreEqual(4, Integer(Length(mView.Visible)));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTests.CountsIgnoreKindToggles;
var
  mView: TAtlasFindingsView;
  mFilter: TAtlasFindingFilter;
  mCounts: TAtlasFindingCounts;
begin
  mView := TAtlasFindingsView.Create;
  try
    mView.SetFindings(Sample);
    mFilter := mView.Filter;
    mFilter.Kinds := [TAtlasFindingKind.Error];
    mView.Filter := mFilter;
    mCounts := mView.Counts;
    Assert.AreEqual(1, mCounts.Errors);
    Assert.AreEqual(2, mCounts.Warnings);
    Assert.AreEqual(1, mCounts.Infos);
    Assert.AreEqual(4, mCounts.Total);
    Assert.AreEqual(2, mCounts.OfKind(TAtlasFindingKind.Warning));
    // Dateien zählen nur, was sichtbar ist: der eine Fehler steht in B.pas.
    Assert.AreEqual(1, mCounts.Files);
    // Gemerkte Zähler folgen jeder Änderung.
    mFilter.Kinds := [TAtlasFindingKind.Error, TAtlasFindingKind.Warning];
    mView.Filter := mFilter;
    Assert.AreEqual(4, mView.Counts.Total);
    Assert.AreEqual(2, mView.Counts.Files);
    mView.SetFindings(nil);
    Assert.AreEqual(0, mView.Counts.Total);
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTests.GroupsByFileRuleAndCategory;
var
  mView: TAtlasFindingsView;
  mRows: TArray<TAtlasFindingRow>;
begin
  mView := TAtlasFindingsView.Create;
  try
    mView.SetFindings(Sample);
    mRows := mView.Rows;
    Assert.AreEqual(6, Integer(Length(mRows)));
    Assert.IsTrue(mRows[0].IsGroup);
    Assert.AreEqual('A.pas', mRows[0].Caption);
    Assert.AreEqual(2, mRows[0].Count);
    Assert.IsTrue(mRows[0].Expanded);
    Assert.AreEqual('A.pas:8:3', mView.Finding(mRows[1].Finding).Location);
    Assert.AreEqual('B.pas', mRows[3].Caption);
    mView.Grouping := TAtlasFindingGrouping.ByRule;
    mRows := mView.Rows;
    Assert.AreEqual('empty-except', mRows[0].Caption);
    Assert.AreEqual(2, mRows[0].Count);
    Assert.AreEqual('syntax', mRows[3].Caption);
    Assert.AreEqual('todo-comment', mRows[5].Caption);
    mView.Grouping := TAtlasFindingGrouping.ByCategory;
    mRows := mView.Rows;
    Assert.AreEqual(5, Integer(Length(mRows)));
    Assert.AreEqual('code-smell', mRows[0].Caption);
    Assert.AreEqual<TAtlasFindingCategory>(TAtlasFindingCategory.CodeSmell, mRows[0].Category);
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTests.CollapsedGroupStaysCollapsedAfterUpdate;
var
  mView: TAtlasFindingsView;
begin
  mView := TAtlasFindingsView.Create;
  try
    mView.SetFindings(Sample);
    mView.Toggle(0);
    Assert.AreEqual(4, Integer(Length(mView.Rows)));
    Assert.IsFalse(mView.Rows[0].Expanded);
    mView.SetFindings(Sample);
    Assert.IsFalse(mView.Rows[0].Expanded);
    Assert.AreEqual(4, Integer(Length(mView.Rows)));
    // Auch eine Weile ohne Befunde: Die Gruppe bleibt zugeklappt.
    mView.SetFindings(nil);
    mView.SetFindings(Sample);
    Assert.IsFalse(mView.Rows[0].Expanded);
    mView.Toggle(0);
    Assert.AreEqual(6, Integer(Length(mView.Rows)));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTests.SelectionSurvivesUpdateAndShiftedLines;
var
  mView: TAtlasFindingsView;
  mStore: TAtlasProblemStore;
  mSelected: TAtlasFinding;
begin
  mStore := TAtlasProblemStore.Create;
  mView := TAtlasFindingsView.Create;
  try
    mStore.Update('C:\P\A.pas', 'a' + #10 + 'b' + #10 + 'c' + #10, True,
      [Problem(1, 'r1', 'eins', TAtlasProblemSeverity.Warning), Problem(2, 'r2', 'zwei', TAtlasProblemSeverity.Warning)],
      '', True);
    mView.SetFindings(TAtlasFindings.FromStore(mStore, nil, nil));
    mView.Select(1);
    Assert.IsTrue(mView.SelectedFinding(mSelected));
    Assert.AreEqual('r1', mSelected.Rule);
    // Zwei Zeilen oben eingefügt: Die Befunde wandern mit, die Auswahl bleibt am selben Befund.
    mStore.Edit('C:\P\A.pas', 'neu' + #10 + 'neu' + #10 + 'a' + #10 + 'b' + #10 + 'c' + #10);
    mView.SetFindings(TAtlasFindings.FromStore(mStore, nil, nil));
    Assert.AreEqual(1, mView.SelectedRow);
    Assert.IsTrue(mView.SelectedFinding(mSelected));
    Assert.AreEqual('r1', mSelected.Rule);
    Assert.AreEqual(3, mSelected.Problem.StartLine);
    mView.SetFindings(nil);
    Assert.AreEqual(-1, mView.SelectedRow);
  finally
    mView.Free;
    mStore.Free;
  end;
end;

procedure TAtlasFindingsTests.NewFindingsAreMarkedOnlyAfterFirstFill;
var
  mView: TAtlasFindingsView;
  mRow: TAtlasFindingRow;
  mNewCount: Integer;
begin
  mView := TAtlasFindingsView.Create;
  try
    mView.Grouping := TAtlasFindingGrouping.None;
    mView.SetFindings(Copy(Sample, 0, 2));
    for mRow in mView.Rows do
    begin
      Assert.IsFalse(mRow.IsNew);
    end;
    mView.SetFindings(Sample);
    mNewCount := 0;
    for mRow in mView.Rows do
    begin
      if mRow.IsNew then
      begin
        Inc(mNewCount);
      end;
    end;
    Assert.AreEqual(2, mNewCount);
    mView.ClearNew;
    for mRow in mView.Rows do
    begin
      Assert.IsFalse(mRow.IsNew);
    end;
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTests.StepWrapsAndExpandsGroup;
var
  mView: TAtlasFindingsView;
  mTarget: TAtlasFinding;
begin
  mView := TAtlasFindingsView.Create;
  try
    mView.SetFindings(Sample);
    // B.pas zuklappen: Der Schritt dorthin klappt sie wieder auf.
    mView.Toggle(3);
    Assert.IsTrue(mView.Step(True, mTarget));
    Assert.AreEqual('A.pas:8:3', mTarget.Location);
    Assert.IsTrue(mView.Step(True, mTarget));
    Assert.AreEqual('A.pas:2:3', mTarget.Location);
    Assert.IsTrue(mView.Step(True, mTarget));
    Assert.AreEqual('B.pas:4:3', mTarget.Location);
    Assert.IsTrue(mView.Rows[3].Expanded);
    Assert.AreEqual(4, mView.SelectedRow);
    Assert.IsTrue(mView.Step(True, mTarget));
    Assert.IsTrue(mView.Step(True, mTarget));
    Assert.AreEqual('A.pas:8:3', mTarget.Location);
    Assert.IsTrue(mView.Step(False, mTarget));
    Assert.AreEqual('B.pas:10:3', mTarget.Location);
    mView.SetFindings(nil);
    Assert.IsFalse(mView.Step(True, mTarget));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTests.SelectAtFollowsCursor;
var
  mView: TAtlasFindingsView;
  mSelected: TAtlasFinding;
begin
  mView := TAtlasFindingsView.Create;
  try
    mView.SetFindings(Sample);
    mView.Toggle(0);
    Assert.IsTrue(mView.SelectAt('c:\p\a.pas', 7));
    Assert.IsTrue(mView.Rows[0].Expanded);
    Assert.IsTrue(mView.SelectedFinding(mSelected));
    Assert.AreEqual('A.pas:8:3', mSelected.Location);
    Assert.IsFalse(mView.SelectAt('C:\P\A.pas', 5));
    Assert.IsTrue(mView.SelectedFinding(mSelected));
    Assert.AreEqual('A.pas:8:3', mSelected.Location);
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTests.FindingsOfRowsTakesGroupMembersOnce;
var
  mView: TAtlasFindingsView;
  mItems: TArray<TAtlasFinding>;
begin
  mView := TAtlasFindingsView.Create;
  try
    mView.SetFindings(Sample);
    mItems := mView.FindingsOfRows([0, 1, 4]);
    Assert.AreEqual(3, Integer(Length(mItems)));
    Assert.AreEqual('A.pas:8:3', mItems[0].Location);
    Assert.AreEqual('A.pas:2:3', mItems[1].Location);
    Assert.AreEqual('B.pas:4:3', mItems[2].Location);
    Assert.AreEqual(0, Integer(Length(mView.FindingsOfRows([99]))));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTests.ColumnsRoundTripAndKeepMandatoryVisible;
var
  mColumns: TArray<TAtlasFindingColumnState>;
begin
  mColumns := TAtlasFindings.ParseColumns('');
  Assert.AreEqual(9, Integer(Length(mColumns)));
  Assert.AreEqual('icon,kind,category,message,line,location,rule,compiler,source',
    TAtlasFindings.FormatColumns(mColumns));
  mColumns := TAtlasFindings.ParseColumns('rule:120, -message, -kind, unbekannt, location:80, rule');
  Assert.AreEqual<TAtlasFindingColumn>(TAtlasFindingColumn.Rule, mColumns[0].Column);
  Assert.AreEqual(120, mColumns[0].Width);
  Assert.IsFalse(mColumns[1].Visible);
  // Art ist Pflicht: bleibt sichtbar.
  Assert.IsTrue(mColumns[2].Visible);
  Assert.AreEqual('rule:120,-message,kind,location:80,icon,category,line,compiler,source',
    TAtlasFindings.FormatColumns(mColumns));
  Assert.IsTrue(TAtlasFindings.IsMandatory(TAtlasFindingColumn.Location));
  Assert.IsFalse(TAtlasFindings.IsMandatory(TAtlasFindingColumn.Message));
  Assert.IsFalse(TAtlasFindings.IsMandatory(TAtlasFindingColumn.Compiler), 'Spalte Compiler abwählbar (#1024)');
  Assert.AreEqual('-compiler,icon,kind,category,message,line,location,rule,source',
    TAtlasFindings.FormatColumns(TAtlasFindings.ParseColumns('-compiler')));
  Assert.IsFalse(TAtlasFindings.IsMandatory(TAtlasFindingColumn.Source), 'Spalte Quelle abwählbar (#1819)');
end;

procedure TAtlasFindingsTests.ScopeAndGroupingNames;
var
  mScope: TAtlasFindingScope;
  mGrouping: TAtlasFindingGrouping;
begin
  Assert.IsTrue(TAtlasFindings.TryParseScope('project', mScope));
  Assert.AreEqual<TAtlasFindingScope>(TAtlasFindingScope.Project, mScope);
  Assert.IsFalse(TAtlasFindings.TryParseScope('x', mScope));
  Assert.AreEqual<TAtlasFindingScope>(TAtlasFindingScope.Group, mScope);
  Assert.IsTrue(TAtlasFindings.TryParseGrouping('Rule', mGrouping));
  Assert.AreEqual<TAtlasFindingGrouping>(TAtlasFindingGrouping.ByRule, mGrouping);
  Assert.IsFalse(TAtlasFindings.TryParseGrouping('', mGrouping));
  Assert.AreEqual<TAtlasFindingGrouping>(TAtlasFindingGrouping.ByFile, mGrouping);
end;

procedure TAtlasFindingsTests.CheckedCountCountsDeliveredFiles;
var
  mStore: TAtlasProblemStore;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update('C:\P\A.pas', '', False, nil, '', True);
    mStore.Update('C:\P\B.pas', '', False, [Problem(0, 'r', 'm', TAtlasProblemSeverity.Error)], '', True);
    Assert.AreEqual(2, TAtlasFindings.CheckedCount(mStore, ['C:\P\A.pas', 'C:\P\B.pas', 'C:\P\C.pas']));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasFindingsTests.CopyTextUsesCompilerFormat;
var
  mItems: TArray<TAtlasFinding>;
begin
  mItems := TAtlasFindings.FromProblems('C:\P\B.pas', [Problem(9, 'empty-except', 'Leer', TAtlasProblemSeverity.Warning),
    Problem(3, 'syntax', 'Fehlt', TAtlasProblemSeverity.Error)], ['', '', '', '  X := 1;']);
  Assert.AreEqual('B.pas:10:3: warning [empty-except] Leer'#13#10 +
    'B.pas:4:3: error [syntax] Fehlt'#13#10'    X := 1;'#13#10, TAtlasFindings.AsText(mItems));
  Assert.AreEqual('', TAtlasFindings.AsText(nil));
end;

/// <summary>Z aktiv, A und B geöffnet, C und D nicht geöffnet; je Datei zwei Befunde (Fehler, Warnung).</summary>
function TierSample: TArray<TAtlasFinding>;
var
  mName: string;
begin
  Result := nil;
  for mName in ['C', 'Z', 'B', 'D', 'A'] do
  begin
    Result := Result + TAtlasFindings.FromProblems('C:\P\' + mName + '.pas',
      [Problem(5, 'empty-except', 'Leer', TAtlasProblemSeverity.Warning),
      Problem(2, 'syntax', 'Fehlt', TAtlasProblemSeverity.Error)], nil);
  end;
end;

function TierView: TAtlasFindingsView;
begin
  Result := TAtlasFindingsView.Create;
  Result.OpenFirst := True;
  Result.SetFindings(TierSample);
  Result.SetOpenFiles('C:\P\Z.pas', ['C:\P\Z.pas', 'C:\P\B.pas', 'C:\P\A.pas', 'C:\P\Leer.pas'], True);
end;

/// <summary>Zeilen als Text: G=Gruppe, S=Trennzeile, F=Befund; dahinter Name bzw. Stelle, * = angepinnt,
/// ~ = ausgegraut.</summary>
function RowsText(AView: TAtlasFindingsView): string;
var
  mRow: TAtlasFindingRow;
  mPart: string;
begin
  Result := '';
  for mRow in AView.Rows do
  begin
    if mRow.IsSection then
    begin
      mPart := 'S' + IntToStr(Ord(mRow.Tier)) + ':' + mRow.Caption + ':' + IntToStr(mRow.Units) + '/' +
        IntToStr(mRow.Count);
      if mRow.IsCleanActive then
      begin
        mPart := mPart + ':clean';
      end;
    end
    else if mRow.IsGroup then
    begin
      mPart := 'G:' + mRow.Caption;
    end
    else
    begin
      mPart := 'F:' + AView.Finding(mRow.Finding).Location;
    end;
    if mRow.Pinned then
    begin
      mPart := mPart + '*';
    end;
    if mRow.Dimmed then
    begin
      mPart := mPart + '~';
    end;
    Result := Result + mPart + ' ';
  end;
  Result := Result.Trim;
end;

procedure TAtlasFindingsTierTests.TiersOrderFileGroups;
var
  mView: TAtlasFindingsView;
begin
  mView := TierView;
  try
    Assert.AreEqual('G:Z.pas* F:Z.pas:3:3* F:Z.pas:6:3* ' +
      'S1::2/4 G:A.pas F:A.pas:3:3 F:A.pas:6:3 G:B.pas F:B.pas:3:3 F:B.pas:6:3 ' +
      'S2::2/4~ G:C.pas~ F:C.pas:3:3~ F:C.pas:6:3~ G:D.pas~ F:D.pas:3:3~ F:D.pas:6:3~', RowsText(mView));
    Assert.AreEqual<TAtlasFindingTier>(TAtlasFindingTier.Active, mView.Rows[0].Tier);
    Assert.AreEqual<TAtlasFindingTier>(TAtlasFindingTier.Active, mView.Finding(mView.Rows[1].Finding).Tier);
    Assert.AreEqual<TAtlasFindingTier>(TAtlasFindingTier.Open, mView.Finding(mView.Rows[5].Finding).Tier);
    Assert.AreEqual<TAtlasFindingTier>(TAtlasFindingTier.Closed, mView.Rows[11].Tier);
    Assert.AreEqual<TAtlasFindingTier>(TAtlasFindingTier.Closed, mView.Finding(mView.Rows[12].Finding).Tier);
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTierTests.TiersWithoutGroupingAreSections;
var
  mView: TAtlasFindingsView;
  mItems: TArray<TAtlasFinding>;
begin
  mView := TierView;
  try
    mView.Grouping := TAtlasFindingGrouping.None;
    // Innerhalb der Stufe die Vorgabe Art, Datei, Zeile.
    Assert.AreEqual('S0:Z.pas:1/2* F:Z.pas:3:3* F:Z.pas:6:3* ' +
      'S1::2/4 F:A.pas:3:3 F:B.pas:3:3 F:A.pas:6:3 F:B.pas:6:3 ' +
      'S2::2/4~ F:C.pas:3:3~ F:D.pas:3:3~ F:C.pas:6:3~ F:D.pas:6:3~', RowsText(mView));
    mItems := mView.Visible;
    Assert.AreEqual(10, Integer(Length(mItems)));
    Assert.AreEqual('Z.pas:3:3', mItems[0].Location);
    Assert.IsFalse(TAtlasFindings.AsText(mItems).Contains('Geöffnet'));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTierTests.TiersInsideRuleAndCategoryGroups;
var
  mView: TAtlasFindingsView;
begin
  mView := TierView;
  try
    mView.Grouping := TAtlasFindingGrouping.ByRule;
    Assert.AreEqual('G:empty-except F:Z.pas:6:3* F:A.pas:6:3 F:B.pas:6:3 F:C.pas:6:3~ F:D.pas:6:3~ ' +
      'G:syntax F:Z.pas:3:3* F:A.pas:3:3 F:B.pas:3:3 F:C.pas:3:3~ F:D.pas:3:3~', RowsText(mView));
    mView.Grouping := TAtlasFindingGrouping.ByCategory;
    Assert.AreEqual('G:code-smell F:Z.pas:3:3* F:Z.pas:6:3* F:A.pas:3:3 F:B.pas:3:3 F:A.pas:6:3 F:B.pas:6:3 ' +
      'F:C.pas:3:3~ F:D.pas:3:3~ F:C.pas:6:3~ F:D.pas:6:3~', RowsText(mView));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTierTests.ColumnSortWorksInsideTiers;
var
  mView: TAtlasFindingsView;
begin
  mView := TierView;
  try
    mView.Grouping := TAtlasFindingGrouping.None;
    mView.SortBy(TAtlasFindingColumn.Location);
    mView.SortBy(TAtlasFindingColumn.Location);
    Assert.IsTrue(mView.SortDescending);
    Assert.AreEqual('S0:Z.pas:1/2* F:Z.pas:6:3* F:Z.pas:3:3* ' +
      'S1::2/4 F:B.pas:6:3 F:B.pas:3:3 F:A.pas:6:3 F:A.pas:3:3 ' +
      'S2::2/4~ F:D.pas:6:3~ F:D.pas:3:3~ F:C.pas:6:3~ F:C.pas:3:3~', RowsText(mView));
    mView.ResetSort;
    Assert.AreEqual('Z.pas:3:3', mView.Visible[0].Location);
    Assert.AreEqual('A.pas:3:3', mView.Visible[2].Location);
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTierTests.SwitchingEditorMovesOnlyPinnedGroup;
var
  mView: TAtlasFindingsView;
begin
  mView := TierView;
  try
    mView.SetOpenFiles('C:\P\B.pas', ['C:\P\Z.pas', 'C:\P\B.pas', 'C:\P\A.pas'], True);
    // B steht oben, Z rückt alphabetisch unter A; A bleibt, wo es war.
    Assert.AreEqual('G:B.pas* F:B.pas:3:3* F:B.pas:6:3* ' +
      'S1::2/4 G:A.pas F:A.pas:3:3 F:A.pas:6:3 G:Z.pas F:Z.pas:3:3 F:Z.pas:6:3 ' +
      'S2::2/4~ G:C.pas~ F:C.pas:3:3~ F:C.pas:6:3~ G:D.pas~ F:D.pas:3:3~ F:D.pas:6:3~', RowsText(mView));
    // Unit schließen: rutscht nach „Nicht geöffnet“.
    mView.SetOpenFiles('C:\P\B.pas', ['C:\P\B.pas', 'C:\P\A.pas'], True);
    Assert.AreEqual('G:B.pas* F:B.pas:3:3* F:B.pas:6:3* S1::1/2 G:A.pas F:A.pas:3:3 F:A.pas:6:3 ' +
      'S2::3/6~ G:C.pas~ F:C.pas:3:3~ F:C.pas:6:3~ G:D.pas~ F:D.pas:3:3~ F:D.pas:6:3~ ' +
      'G:Z.pas~ F:Z.pas:3:3~ F:Z.pas:6:3~', RowsText(mView));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTierTests.SectionsAreSkippedBySelectionStepAndCopy;
var
  mView: TAtlasFindingsView;
  mItem: TAtlasFinding;
  mRows: TArray<TAtlasFindingRow>;
begin
  mView := TierView;
  try
    mView.Grouping := TAtlasFindingGrouping.None;
    mRows := mView.Rows;
    Assert.IsTrue(mRows[3].IsSection);
    Assert.IsFalse(mRows[3].IsGroup);
    mView.Select(2);
    mView.Select(3);
    // Die Trennzeile ist nicht wählbar: Die Auswahl bleibt auf dem Befund davor.
    Assert.AreEqual(2, mView.SelectedRow);
    mView.Toggle(3);
    Assert.AreEqual(Integer(Length(mRows)), Integer(Length(mView.Rows)));
    Assert.IsTrue(mView.Step(True, mItem));
    Assert.AreEqual('A.pas:3:3', mItem.Location);
    Assert.AreEqual(4, mView.SelectedRow);
    Assert.AreEqual(0, Integer(Length(mView.FindingsOfRows([0, 3, 8]))));
    Assert.AreEqual(1, Integer(Length(mView.FindingsOfRows([0, 3, 4]))));
    Assert.IsTrue(mView.SelectAt('C:\P\C.pas', 2));
    Assert.AreEqual(9, mView.SelectedRow);
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTierTests.ClosedUnitsDimmedNormalHidden;
var
  mView: TAtlasFindingsView;
  mCounts: TAtlasFindingCounts;
begin
  mView := TierView;
  try
    mCounts := mView.Counts;
    Assert.AreEqual(10, mCounts.Total);
    Assert.AreEqual(3, mCounts.OpenUnits);
    Assert.AreEqual(6, mCounts.OpenFindings);
    Assert.AreEqual(2, mCounts.ClosedUnits);
    Assert.AreEqual(4, mCounts.ClosedFindings);
    Assert.AreEqual(0, mCounts.HiddenUnits);
    mView.ClosedUnits := TAtlasClosedUnits.Normal;
    Assert.AreEqual('S2::2/4 G:C.pas F:C.pas:3:3 F:C.pas:6:3 G:D.pas F:D.pas:3:3 F:D.pas:6:3',
      RowsText(mView).Substring(RowsText(mView).IndexOf('S2')));
    mView.ClosedUnits := TAtlasClosedUnits.Hidden;
    Assert.AreEqual('G:Z.pas* F:Z.pas:3:3* F:Z.pas:6:3* ' +
      'S1::2/4 G:A.pas F:A.pas:3:3 F:A.pas:6:3 G:B.pas F:B.pas:3:3 F:B.pas:6:3', RowsText(mView));
    mCounts := mView.Counts;
    // Ausgeblendet zählt nicht mit, auch nicht auf den Umschaltern.
    Assert.AreEqual(6, mCounts.Total);
    Assert.AreEqual(3, mCounts.Warnings);
    Assert.AreEqual(0, mCounts.ClosedUnits);
    Assert.AreEqual(2, mCounts.HiddenUnits);
    Assert.AreEqual(3, mCounts.Files);
    Assert.AreEqual(6, Integer(Length(mView.Visible)));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTierTests.CleanActiveUnitShowsWithoutFindings;
var
  mView: TAtlasFindingsView;
  mCounts: TAtlasFindingCounts;
begin
  mView := TierView;
  try
    mView.SetOpenFiles('C:\P\Sauber.pas', ['C:\P\Sauber.pas', 'C:\P\A.pas'], False);
    Assert.IsTrue(RowsText(mView).StartsWith('S0:Sauber.pas:0/0:clean* S1::1/2 G:A.pas '), RowsText(mView));
    Assert.IsTrue(mView.Rows[0].Checking);
    mView.SetOpenFiles('C:\P\Sauber.pas', ['C:\P\Sauber.pas', 'C:\P\A.pas'], True);
    Assert.IsFalse(mView.Rows[0].Checking);
    Assert.IsTrue(mView.Rows[0].IsCleanActive);
    mCounts := mView.Counts;
    Assert.AreEqual(10, mCounts.Total);
    Assert.AreEqual(5, mCounts.Files);
    mView.Grouping := TAtlasFindingGrouping.None;
    Assert.IsTrue(RowsText(mView).StartsWith('S0:Sauber.pas:0/0:clean* S1::1/2 F:A.pas:3:3 '), RowsText(mView));
    mView.Grouping := TAtlasFindingGrouping.ByRule;
    Assert.IsTrue(RowsText(mView).StartsWith('G:empty-except '), RowsText(mView));
    mView.Grouping := TAtlasFindingGrouping.ByFile;
    mView.ShowCleanActive := False;
    Assert.IsTrue(RowsText(mView).StartsWith('S1::1/2 G:A.pas '), RowsText(mView));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTierTests.SelectionAndCollapseSurviveResort;
var
  mView: TAtlasFindingsView;
  mItem: TAtlasFinding;
  mKey: string;
begin
  mView := TierView;
  try
    mView.SetExpanded('file:c:\p\c.pas', False);
    mView.Select(5);
    Assert.IsTrue(mView.SelectedFinding(mItem));
    mKey := mItem.Key;
    Assert.AreEqual('A.pas:3:3', mItem.Location);
    mView.SetFindings(TierSample);
    mView.SetOpenFiles('C:\P\A.pas', ['C:\P\A.pas', 'C:\P\C.pas'], True);
    Assert.IsTrue(mView.SelectedFinding(mItem));
    Assert.AreEqual(mKey, mItem.Key);
    Assert.AreEqual(1, mView.SelectedRow);
    // C ist jetzt geöffnet und bleibt zugeklappt.
    Assert.IsTrue(RowsText(mView).Contains('S1::1/2 G:C.pas S2'), RowsText(mView));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTierTests.FormFilePinsItsUnitIgnoringCase;
var
  mView: TAtlasFindingsView;
begin
  mView := TierView;
  try
    mView.SetOpenFiles('c:\p\b.DFM', ['C:\P\b.dfm', 'C:\P\A.PAS'], True);
    Assert.IsTrue(RowsText(mView).StartsWith('G:B.pas* F:B.pas:3:3* F:B.pas:6:3* S1::1/2 G:A.pas '),
      RowsText(mView));
    Assert.AreEqual('c:\p\b.pas', mView.ActiveFile);
    Assert.AreEqual('c:\p\b.pas', TAtlasFindings.UnitKey('C:\P\B.dfm'));
    Assert.AreEqual('c:\p\b.pas', TAtlasFindings.UnitKey('C:\P\B.FMX'));
    Assert.AreEqual('c:\p\b.inc', TAtlasFindings.UnitKey('C:\P\B.inc'));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTierTests.OpenFirstOffKeepsOrderOf909;
var
  mView, mPlain: TAtlasFindingsView;
  mGrouping: TAtlasFindingGrouping;
begin
  mView := TierView;
  mPlain := TAtlasFindingsView.Create;
  try
    mView.OpenFirst := False;
    mPlain.SetFindings(TierSample);
    for mGrouping := Low(TAtlasFindingGrouping) to High(TAtlasFindingGrouping) do
    begin
      mView.Grouping := mGrouping;
      mPlain.Grouping := mGrouping;
      Assert.AreEqual(RowsText(mPlain), RowsText(mView));
    end;
    Assert.IsFalse(RowsText(mView).Contains('*'));
    Assert.AreEqual(0, mView.Counts.OpenUnits);
  finally
    mPlain.Free;
    mView.Free;
  end;
end;

procedure TAtlasFindingsTierTests.CurrentFileScopeHasNoSections;
var
  mView: TAtlasFindingsView;
  mFilter: TAtlasFindingFilter;
begin
  mView := TierView;
  try
    mFilter := mView.Filter;
    mFilter.Scope := TAtlasFindingScope.CurrentFile;
    mFilter.CurrentFile := 'C:\P\Z.pas';
    mView.Filter := mFilter;
    Assert.IsFalse(mView.TiersActive);
    Assert.AreEqual('G:Z.pas F:Z.pas:3:3 F:Z.pas:6:3', RowsText(mView));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTierTests.ProjectScopeLimitsClosedUnits;
var
  mView: TAtlasFindingsView;
  mFilter: TAtlasFindingFilter;
begin
  mView := TierView;
  try
    mFilter := mView.Filter;
    mFilter.Scope := TAtlasFindingScope.Project;
    mFilter.Files := ['C:\P\Z.pas', 'C:\P\A.pas', 'C:\P\C.pas'];
    mView.Filter := mFilter;
    Assert.AreEqual('G:Z.pas* F:Z.pas:3:3* F:Z.pas:6:3* S1::1/2 G:A.pas F:A.pas:3:3 F:A.pas:6:3 ' +
      'S2::1/2~ G:C.pas~ F:C.pas:3:3~ F:C.pas:6:3~', RowsText(mView));
    // Aktive Unit außerhalb des Projekts: keine Zeile „Keine Befunde“.
    mView.SetOpenFiles('C:\Fremd\X.pas', ['C:\Fremd\X.pas'], True);
    Assert.IsTrue(RowsText(mView).StartsWith('S2::'), RowsText(mView));
  finally
    mView.Free;
  end;
end;

procedure TAtlasFindingsTierTests.ClosedUnitsNames;
var
  mValue: TAtlasClosedUnits;
begin
  Assert.IsTrue(TAtlasFindings.TryParseClosedUnits('hidden', mValue));
  Assert.AreEqual<TAtlasClosedUnits>(TAtlasClosedUnits.Hidden, mValue);
  Assert.IsTrue(TAtlasFindings.TryParseClosedUnits('Normal', mValue));
  Assert.AreEqual<TAtlasClosedUnits>(TAtlasClosedUnits.Normal, mValue);
  Assert.IsFalse(TAtlasFindings.TryParseClosedUnits('grau', mValue));
  Assert.AreEqual<TAtlasClosedUnits>(TAtlasClosedUnits.Dimmed, mValue);
  Assert.AreEqual('dimmed', TAtlasFindings.cClosedUnitsNames[TAtlasClosedUnits.Dimmed]);
end;

procedure TAtlasFindingsTierTests.DimmedColorsStayReadable;
var
  mBack, mText, mDimmed: TAtlasColor;
  mBacks: array[0..3] of TAtlasColor;
  mTexts: array[0..3] of TAtlasColor;
  mIndex: Integer;
  mError, mWarn: TAtlasColor;
begin
  mBacks[0] := TAtlasColorMath.FromHex('#FFFFFF');
  mTexts[0] := TAtlasColorMath.FromHex('#1F2328');
  mBacks[1] := TAtlasColorMath.FromHex('#1A1E25');
  mTexts[1] := TAtlasColorMath.FromHex('#E6E8EB');
  mBacks[2] := TAtlasColorMath.FromHex('#2B2B2B');
  mTexts[2] := TAtlasColorMath.FromHex('#C8C8C8');
  mBacks[3] := TAtlasColorMath.FromHex('#F0F0F0');
  mTexts[3] := TAtlasColorMath.FromHex('#707070');
  for mIndex := 0 to High(mBacks) do
  begin
    mBack := mBacks[mIndex];
    mText := mTexts[mIndex];
    mDimmed := DimmedTextColor(mText, mBack);
    Assert.IsTrue(TAtlasColorMath.Contrast(mDimmed, mBack) >= cAtlasDimmedMinContrast - 0.01,
      TAtlasColorMath.ToHex(mDimmed));
    // Ausgegraut heißt: weniger Kontrast als der Text, solange das Maß es erlaubt; zu blasser Text wird kräftiger.
    if TAtlasColorMath.Contrast(mText, mBack) >= cAtlasDimmedMinContrast then
    begin
      Assert.IsTrue(TAtlasColorMath.Contrast(mDimmed, mBack) <= TAtlasColorMath.Contrast(mText, mBack) + 0.01);
    end;
  end;
  Assert.AreNotEqual(TAtlasColorMath.ToHex(mTexts[0]), TAtlasColorMath.ToHex(DimmedTextColor(mTexts[0], mBacks[0])));
  // Symbole bleiben unterscheidbar.
  mError := DimmedIconColor($003C3CD8, mBacks[0]);
  mWarn := DimmedIconColor($0020A8F0, mBacks[0]);
  Assert.IsTrue(TAtlasColorMath.DeltaE2000(mError, mWarn) > 10);
  Assert.AreNotEqual(TAtlasColorMath.ToHex($003C3CD8), TAtlasColorMath.ToHex(mError));
  // Angepinnt: hell etwa #EEF4FB.
  Assert.IsTrue(TAtlasColorMath.DeltaE2000(PinnedBackColor(mBacks[0]), TAtlasColorMath.FromHex('#EEF4FB')) < 3,
    TAtlasColorMath.ToHex(PinnedBackColor(mBacks[0])));
  Assert.IsTrue(TAtlasColorMath.IsDark(PinnedBackColor(mBacks[1])));
  // Neu dazugekommen: hell bleibt hell, dunkel bleibt dunkel (lesbar mit der Schrift des Themas).
  Assert.IsFalse(TAtlasColorMath.IsDark(NewBackColor(mBacks[0])));
  Assert.IsTrue(TAtlasColorMath.IsDark(NewBackColor(mBacks[1])));
  Assert.AreNotEqual(TAtlasColorMath.ToHex(mBacks[1]), TAtlasColorMath.ToHex(NewBackColor(mBacks[1])));
end;

type
  /// <summary>Zählt Lesezugriffe auf die Platte in den Tests unten.</summary>
  TReadCounter = class
  public
    Count: Integer;
    function Reader: TFunc<string, TArray<string>>;
  end;

function TReadCounter.Reader: TFunc<string, TArray<string>>;
begin
  Result :=
    function(AFileName: string): TArray<string>
    var
      Index: Integer;
    begin
      Inc(Count);
      SetLength(Result, 40);
      for Index := 0 to High(Result) do
      begin
        Result[Index] := Format('%s %d', [ExtractFileName(AFileName), Index]);
      end;
    end;
end;

function ManyProblems(ACount: Integer): TArray<TAtlasProblem>;
var
  mIndex: Integer;
begin
  SetLength(Result, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    Result[mIndex] := Problem(mIndex, 'r' + IntToStr(mIndex mod 7), 'Treffer ' + IntToStr(mIndex),
      TAtlasProblemSeverity.Warning);
  end;
end;

procedure TAtlasFindingsTierTests.ReadLinesOncePerFile;
var
  mStore: TAtlasProblemStore;
  mCounter: TReadCounter;
  mItems: TArray<TAtlasFinding>;
begin
  mStore := TAtlasProblemStore.Create;
  mCounter := TReadCounter.Create;
  try
    mStore.Update('C:\P\Zu.pas', '', False, ManyProblems(30), '', True);
    mItems := TAtlasFindings.FromStore(mStore, nil, mCounter.Reader());
    Assert.AreEqual(30, Integer(Length(mItems)));
    Assert.AreEqual(1, mCounter.Count);
    Assert.AreEqual('Zu.pas 29', mItems[29].LineText);
  finally
    mCounter.Free;
    mStore.Free;
  end;
end;

procedure TAtlasFindingsTierTests.StampChangesOnlyForTheChangedFile;
var
  mStore: TAtlasProblemStore;
  A, B: Integer;
begin
  mStore := TAtlasProblemStore.Create;
  try
    Assert.AreEqual(0, mStore.Stamp('C:\P\A.pas'));
    mStore.Update('C:\P\A.pas', 'a' + #10 + 'b' + #10, True, ManyProblems(2), '', True);
    mStore.Update('C:\P\B.pas', '', False, ManyProblems(1), '', True);
    A := mStore.Stamp('c:\p\a.pas');
    B := mStore.Stamp('C:\P\B.pas');
    Assert.IsTrue(A > 0);
    mStore.Update('C:\P\A.pas', 'a' + #10 + 'b' + #10, True, ManyProblems(1), '', True);
    Assert.AreNotEqual(A, mStore.Stamp('C:\P\A.pas'));
    Assert.AreEqual(B, mStore.Stamp('C:\P\B.pas'));
    // Text statt Platte: andere Zeilentexte, auch ohne neue Version.
    A := mStore.Stamp('C:\P\A.pas');
    mStore.Edit('C:\P\B.pas', 'x' + #10);
    Assert.AreNotEqual(B, mStore.Stamp('C:\P\B.pas'));
    B := mStore.Stamp('C:\P\B.pas');
    mStore.Edit('C:\P\A.pas', 'neu' + #10 + 'a' + #10 + 'b' + #10);
    Assert.AreNotEqual(A, mStore.Stamp('C:\P\A.pas'));
    Assert.AreEqual(B, mStore.Stamp('C:\P\B.pas'));
    // Ausblenden einer Aufgabe ändert ForFile aller Dateien.
    A := mStore.Stamp('C:\P\A.pas');
    mStore.SetTaskHidden('Aufgabe', True);
    Assert.AreNotEqual(A, mStore.Stamp('C:\P\A.pas'));
    Assert.AreNotEqual(B, mStore.Stamp('C:\P\B.pas'));
    mStore.Remove('C:\P\A.pas');
    Assert.AreEqual(0, mStore.Stamp('C:\P\A.pas'));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasFindingsTierTests.CacheRebuildsOnlyChangedFiles;
var
  mStore: TAtlasProblemStore;
  mCache: TAtlasFindingsCache;
  mCounter: TReadCounter;
  mItems: TArray<TAtlasFinding>;
  mChanged: Boolean;
begin
  mStore := TAtlasProblemStore.Create;
  mCache := TAtlasFindingsCache.Create;
  mCounter := TReadCounter.Create;
  try
    mStore.Update('C:\P\A.pas', '', False, ManyProblems(3), '', True);
    mStore.Update('C:\P\B.pas', '', False, ManyProblems(2), '', True);
    mItems := mCache.Build(mStore, nil, mCounter.Reader(), mChanged);
    Assert.IsTrue(mChanged);
    Assert.AreEqual(5, Integer(Length(mItems)));
    Assert.AreEqual(2, mCounter.Count);
    // Nichts geändert: keine Platte, keine Änderung.
    mItems := mCache.Build(mStore, nil, mCounter.Reader(), mChanged);
    Assert.IsFalse(mChanged);
    Assert.AreEqual(5, Integer(Length(mItems)));
    Assert.AreEqual(2, mCounter.Count);
    // Eine Datei neu: nur sie wird gelesen.
    mStore.Update('C:\P\B.pas', '', False, ManyProblems(4), '', True);
    mItems := mCache.Build(mStore, nil, mCounter.Reader(), mChanged);
    Assert.IsTrue(mChanged);
    Assert.AreEqual(7, Integer(Length(mItems)));
    Assert.AreEqual(3, mCounter.Count);
    // Eine Datei außerhalb der Auswahl ändert die Auswahl nicht.
    mItems := mCache.Build(mStore, ['C:\P\A.pas'], mCounter.Reader(), mChanged);
    Assert.IsTrue(mChanged);
    Assert.AreEqual(3, Integer(Length(mItems)));
    mStore.Update('C:\P\B.pas', '', False, ManyProblems(1), '', True);
    mItems := mCache.Build(mStore, ['C:\P\A.pas'], mCounter.Reader(), mChanged);
    Assert.IsFalse(mChanged);
    Assert.AreEqual(3, Integer(Length(mItems)));
    Assert.AreEqual(3, mCounter.Count);
    // Clear baut alles neu.
    mCache.Clear;
    mItems := mCache.Build(mStore, ['C:\P\A.pas'], mCounter.Reader(), mChanged);
    Assert.IsTrue(mChanged);
    Assert.AreEqual(3, Integer(Length(mItems)));
    Assert.AreEqual(4, mCounter.Count);
  finally
    mCounter.Free;
    mCache.Free;
    mStore.Free;
  end;
end;

procedure TAtlasFindingsTierTests.CacheSurvivesNewStore;
var
  mFirst, mSecond: TAtlasProblemStore;
  mCache: TAtlasFindingsCache;
  mItems: TArray<TAtlasFinding>;
  mChanged: Boolean;
begin
  mCache := TAtlasFindingsCache.Create;
  mFirst := TAtlasProblemStore.Create;
  mSecond := TAtlasProblemStore.Create;
  try
    mFirst.Update('C:\P\A.pas', '', False, ManyProblems(3), '', True);
    mItems := mCache.Build(mFirst, nil, nil, mChanged);
    Assert.AreEqual(3, Integer(Length(mItems)));
    // Neuer Speicher (Neustart des Servers) mit denselben Dateien: neuer Stand, kein alter Befund.
    mSecond.Update('C:\P\A.pas', '', False, ManyProblems(1), '', True);
    mItems := mCache.Build(mSecond, nil, nil, mChanged);
    Assert.IsTrue(mChanged);
    Assert.AreEqual(1, Integer(Length(mItems)));
  finally
    mSecond.Free;
    mFirst.Free;
    mCache.Free;
  end;
end;

procedure TAtlasFindingsTierTests.CacheWithManyFindingsIsFast;
const
  cFiles = 2000;
  cPerFile = 28;
var
  mStore: TAtlasProblemStore;
  mCache: TAtlasFindingsCache;
  mCounter: TReadCounter;
  mItems: TArray<TAtlasFinding>;
  mChanged: Boolean;
  mIndex: Integer;
  mWatch: TStopwatch;
  mFirstMs, mSameMs, mOneMs: Int64;
begin
  // Großes Projekt mit Prüfung über alle Units: 56000 Befunde, der Server liefert Datei für Datei.
  mStore := TAtlasProblemStore.Create;
  mCache := TAtlasFindingsCache.Create;
  mCounter := TReadCounter.Create;
  try
    for mIndex := 0 to cFiles - 1 do
    begin
      mStore.Update(Format('C:\P\Unit%d.pas', [mIndex]), '', False, ManyProblems(cPerFile), '', True);
    end;
    mWatch := TStopwatch.StartNew;
    mItems := mCache.Build(mStore, nil, mCounter.Reader(), mChanged);
    mFirstMs := mWatch.ElapsedMilliseconds;
    Assert.AreEqual(cFiles * cPerFile, Integer(Length(mItems)));
    mWatch := TStopwatch.StartNew;
    mItems := mCache.Build(mStore, nil, mCounter.Reader(), mChanged);
    mSameMs := mWatch.ElapsedMilliseconds;
    Assert.IsFalse(mChanged);
    Assert.AreEqual(cFiles * cPerFile, Integer(Length(mItems)));
    mStore.Update('C:\P\Unit7.pas', '', False, ManyProblems(cPerFile - 1), '', True);
    mWatch := TStopwatch.StartNew;
    mItems := mCache.Build(mStore, nil, mCounter.Reader(), mChanged);
    mOneMs := mWatch.ElapsedMilliseconds;
    Assert.IsTrue(mChanged);
    Assert.AreEqual(cFiles * cPerFile - 1, Integer(Length(mItems)));
    Assert.AreEqual(cFiles + 1, mCounter.Count);
    // Viertelsekunden-Takt des Fensters: Ein Takt muss deutlich darunter bleiben.
    Assert.IsTrue(mOneMs < 100, Format('erster Aufbau %d ms, unverändert %d ms, eine Datei neu %d ms',
      [mFirstMs, mSameMs, mOneMs]));
  finally
    mItems := nil;
    mCounter.Free;
    mCache.Free;
    mStore.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFindingsTests);
  TDUnitX.RegisterTestFixture(TAtlasFindingsTierTests);


end.
