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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
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
  Item: TAtlasFinding;
begin
  Result := '';
  for Item in AView.Visible do
    Result := Result + Item.Location + ' ';
  Result := Result.Trim;
end;

procedure TAtlasFindingsTests.SeverityMapsToKind;
begin
  Assert.IsTrue(TAtlasFindings.KindOf(TAtlasProblemSeverity.Error) = TAtlasFindingKind.Error);
  Assert.IsTrue(TAtlasFindings.KindOf(TAtlasProblemSeverity.Warning) = TAtlasFindingKind.Warning);
  Assert.IsTrue(TAtlasFindings.KindOf(TAtlasProblemSeverity.Information) = TAtlasFindingKind.Info);
  Assert.IsTrue(TAtlasFindings.KindOf(TAtlasProblemSeverity.Hint) = TAtlasFindingKind.Info);
end;

procedure TAtlasFindingsTests.CategoryFromCatalogAndCompiler;
var
  Item: TAtlasProblem;
begin
  Item := Problem(0, 'x', 'm', TAtlasProblemSeverity.Error);
  Item.Category := 'bug';
  Assert.IsTrue(TAtlasFindings.CategoryOf(Item) = TAtlasFindingCategory.Bug);
  Item.Category := 'security-hotspot';
  Assert.IsTrue(TAtlasFindings.CategoryOf(Item) = TAtlasFindingCategory.SecurityHotspot);
  Item.Category := '';
  Assert.IsTrue(TAtlasFindings.CategoryOf(Item) = TAtlasFindingCategory.Other);
  Item.Source := TAtlasProblem.CompilerSource;
  Item.Category := 'bug';
  Assert.IsTrue(TAtlasFindings.CategoryOf(Item) = TAtlasFindingCategory.Compiler);
end;

procedure TAtlasFindingsTests.StoreGivesFindingsWithLineTextWithoutInactiveUsesAndTests;
var
  Store: TAtlasProblemStore;
  Inactive, UsesHint: TAtlasProblem;
  Items: TArray<TAtlasFinding>;
begin
  Store := TAtlasProblemStore.Create;
  try
    Inactive := Problem(0, '', 'inaktiv', TAtlasProblemSeverity.Hint);
    Inactive.Unnecessary := True;
    UsesHint := Problem(0, 'unused-uses', 'ungenutzt', TAtlasProblemSeverity.Hint);
    UsesHint.UsesUnit := 'System.Math';
    UsesHint.UsesState := TAtlasProblem.UsesUnused;
    Store.Update('C:\P\A.pas', 'unit A;' + #10 + '    x := 1;   ' + #10, True,
      [Problem(1, 'r', 'Treffer', TAtlasProblemSeverity.Warning), Inactive, UsesHint], '', True);
    Items := TAtlasFindings.FromStore(Store, nil, nil);
    Assert.AreEqual(1, Integer(Length(Items)));
    Assert.AreEqual('x := 1;', Items[0].LineText);
    Assert.AreEqual('C:\P\A.pas', Items[0].FileName);
    Assert.IsTrue(Items[0].Kind = TAtlasFindingKind.Warning);
    Assert.IsFalse(TAtlasFindings.IsFinding(Inactive));
    Assert.IsFalse(TAtlasFindings.IsFinding(UsesHint));
    Inactive := Problem(0, '', 'Test', TAtlasProblemSeverity.Error);
    Inactive.Source := TAtlasProblemStore.TestSource;
    Assert.IsFalse(TAtlasFindings.IsFinding(Inactive));
  finally
    Store.Free;
  end;
end;

procedure TAtlasFindingsTests.ReadLineFillsTextOfUnopenedFiles;
var
  Store: TAtlasProblemStore;
  Items: TArray<TAtlasFinding>;
  ReadLine: TFunc<string, Integer, string>;
begin
  Store := TAtlasProblemStore.Create;
  try
    Store.Update('C:\P\Zu.pas', '', False, [Problem(4, 'r', 'Treffer', TAtlasProblemSeverity.Error)], '', True);
    ReadLine :=
      function(AFileName: string; ALine: Integer): string
      begin
        Result := Format('  %s:%d', [ExtractFileName(AFileName), ALine]);
      end;
    Items := TAtlasFindings.FromStore(Store, ['C:\P\Zu.pas'], ReadLine);
    Assert.AreEqual('Zu.pas:4', Items[0].LineText);
    Items := TAtlasFindings.FromStore(Store, nil, nil);
    Assert.AreEqual('', Items[0].LineText);
  finally
    Store.Free;
  end;
end;

procedure TAtlasFindingsTests.KeysDoNotDependOnTheLine;
var
  First, Moved: TArray<TAtlasFinding>;
begin
  First := TAtlasFindings.FromProblems('C:\P\A.pas', [Problem(3, 'r', 'm', TAtlasProblemSeverity.Error),
    Problem(5, 'r', 'm', TAtlasProblemSeverity.Error)], nil);
  Moved := TAtlasFindings.FromProblems('C:\P\A.pas', [Problem(13, 'r', 'm', TAtlasProblemSeverity.Error),
    Problem(15, 'r', 'm', TAtlasProblemSeverity.Error)], nil);
  Assert.AreEqual(First[0].Key, Moved[0].Key);
  Assert.AreEqual(First[1].Key, Moved[1].Key);
  Assert.AreNotEqual(First[0].Key, First[1].Key);
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
  View: TAtlasFindingsView;
begin
  View := TAtlasFindingsView.Create;
  try
    View.Grouping := TAtlasFindingGrouping.None;
    View.SetFindings(Sample);
    Assert.AreEqual('B.pas:4:3 A.pas:8:3 B.pas:10:3 A.pas:2:3', Locations(View));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.ColumnClickSortsAndSecondClickReverses;
var
  View: TAtlasFindingsView;
begin
  View := TAtlasFindingsView.Create;
  try
    View.Grouping := TAtlasFindingGrouping.None;
    View.SetFindings(Sample);
    View.SortBy(TAtlasFindingColumn.Location);
    Assert.AreEqual('A.pas:2:3 A.pas:8:3 B.pas:4:3 B.pas:10:3', Locations(View));
    View.SortBy(TAtlasFindingColumn.Location);
    Assert.IsTrue(View.SortDescending);
    Assert.AreEqual('B.pas:10:3 B.pas:4:3 A.pas:8:3 A.pas:2:3', Locations(View));
    View.SortBy(TAtlasFindingColumn.Rule);
    Assert.IsFalse(View.SortDescending);
    Assert.AreEqual('A.pas:8:3 B.pas:10:3 B.pas:4:3 A.pas:2:3', Locations(View));
    View.ResetSort;
    Assert.AreEqual('B.pas:4:3 A.pas:8:3 B.pas:10:3 A.pas:2:3', Locations(View));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.CompilerColumnText;
var
  Item: TAtlasFinding;
begin
  Item := Default(TAtlasFinding);
  Item.Problem := Problem(1, 'argument-count-mismatch', 'X erwartet 1 Argumente (wie E2035).',
    TAtlasProblemSeverity.Error);
  Assert.AreEqual('', Item.CompilerText);
  Item.Problem.CompilerCodes := ['E2034', 'E2035'];
  Assert.AreEqual('E2034, E2035', Item.CompilerText);
  Item.Problem.Confirmed := True;
  Item.Problem.ConfirmedCode := 'E2035';
  Assert.AreEqual('E2035 ' + #$00B7 + ' Atlas + dcc', Item.CompilerText);
  Assert.AreEqual('X erwartet 1 Argumente (wie E2035).', Item.MessageText(True));
  Assert.AreEqual('X erwartet 1 Argumente.', Item.MessageText(False));
  Item.Problem := Problem(1, 'W1036', 'Variable nicht initialisiert', TAtlasProblemSeverity.Warning);
  Item.Problem.Source := TAtlasProblem.CompilerSource;
  Assert.AreEqual('W1036', Item.CompilerText);
end;

procedure TAtlasFindingsTests.FiltersByKindCategoryTextAndCompiler;
var
  View: TAtlasFindingsView;
  Filter: TAtlasFindingFilter;
  Items: TArray<TAtlasFinding>;
  Compiler: TAtlasProblem;
begin
  Compiler := Problem(2, 'W1036', 'Variable nicht initialisiert', TAtlasProblemSeverity.Warning);
  Compiler.Source := TAtlasProblem.CompilerSource;
  Items := Sample + TAtlasFindings.FromProblems('C:\P\C.pas', [Compiler], nil);
  Items[1].Category := TAtlasFindingCategory.Bug;
  View := TAtlasFindingsView.Create;
  try
    View.Grouping := TAtlasFindingGrouping.None;
    View.SetFindings(Items);
    Assert.AreEqual(4, Integer(Length(View.Visible)));
    Filter := View.Filter;
    Filter.Compiler := True;
    View.Filter := Filter;
    Assert.AreEqual(5, Integer(Length(View.Visible)));
    Filter.Kinds := [TAtlasFindingKind.Warning];
    View.Filter := Filter;
    Assert.AreEqual('A.pas:8:3 B.pas:10:3 C.pas:3:3', Locations(View));
    Filter.Kinds := [TAtlasFindingKind.Error, TAtlasFindingKind.Warning, TAtlasFindingKind.Info];
    Filter.OneCategory := True;
    Filter.Category := TAtlasFindingCategory.Bug;
    View.Filter := Filter;
    Assert.AreEqual('B.pas:4:3', Locations(View));
    Filter.OneCategory := False;
    Filter.Text := 'TODO';
    View.Filter := Filter;
    Assert.AreEqual('A.pas:2:3', Locations(View));
    Filter.Text := 'b.pas';
    View.Filter := Filter;
    Assert.AreEqual(2, Integer(Length(View.Visible)));
    Filter.Text := 'EMPTY-except';
    View.Filter := Filter;
    Assert.AreEqual(2, Integer(Length(View.Visible)));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.ScopeLimitsFiles;
var
  View: TAtlasFindingsView;
  Filter: TAtlasFindingFilter;
begin
  View := TAtlasFindingsView.Create;
  try
    View.Grouping := TAtlasFindingGrouping.None;
    View.SetFindings(Sample);
    Filter := View.Filter;
    Filter.Scope := TAtlasFindingScope.CurrentFile;
    Filter.CurrentFile := 'c:\p\a.pas';
    View.Filter := Filter;
    Assert.AreEqual('A.pas:8:3 A.pas:2:3', Locations(View));
    Filter.Scope := TAtlasFindingScope.Project;
    Filter.Files := ['C:\P\B.pas'];
    View.Filter := Filter;
    Assert.AreEqual('B.pas:4:3 B.pas:10:3', Locations(View));
    Filter.Scope := TAtlasFindingScope.Group;
    Filter.Files := nil;
    View.Filter := Filter;
    Assert.AreEqual(4, Integer(Length(View.Visible)));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.CountsIgnoreKindToggles;
var
  View: TAtlasFindingsView;
  Filter: TAtlasFindingFilter;
  Counts: TAtlasFindingCounts;
begin
  View := TAtlasFindingsView.Create;
  try
    View.SetFindings(Sample);
    Filter := View.Filter;
    Filter.Kinds := [TAtlasFindingKind.Error];
    View.Filter := Filter;
    Counts := View.Counts;
    Assert.AreEqual(1, Counts.Errors);
    Assert.AreEqual(2, Counts.Warnings);
    Assert.AreEqual(1, Counts.Infos);
    Assert.AreEqual(4, Counts.Total);
    Assert.AreEqual(2, Counts.OfKind(TAtlasFindingKind.Warning));
    // Dateien zählen nur, was sichtbar ist: der eine Fehler steht in B.pas.
    Assert.AreEqual(1, Counts.Files);
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.GroupsByFileRuleAndCategory;
var
  View: TAtlasFindingsView;
  Rows: TArray<TAtlasFindingRow>;
begin
  View := TAtlasFindingsView.Create;
  try
    View.SetFindings(Sample);
    Rows := View.Rows;
    Assert.AreEqual(6, Integer(Length(Rows)));
    Assert.IsTrue(Rows[0].IsGroup);
    Assert.AreEqual('A.pas', Rows[0].Caption);
    Assert.AreEqual(2, Rows[0].Count);
    Assert.IsTrue(Rows[0].Expanded);
    Assert.AreEqual('A.pas:8:3', View.Finding(Rows[1].Finding).Location);
    Assert.AreEqual('B.pas', Rows[3].Caption);
    View.Grouping := TAtlasFindingGrouping.ByRule;
    Rows := View.Rows;
    Assert.AreEqual('empty-except', Rows[0].Caption);
    Assert.AreEqual(2, Rows[0].Count);
    Assert.AreEqual('syntax', Rows[3].Caption);
    Assert.AreEqual('todo-comment', Rows[5].Caption);
    View.Grouping := TAtlasFindingGrouping.ByCategory;
    Rows := View.Rows;
    Assert.AreEqual(5, Integer(Length(Rows)));
    Assert.AreEqual('code-smell', Rows[0].Caption);
    Assert.IsTrue(Rows[0].Category = TAtlasFindingCategory.CodeSmell);
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.CollapsedGroupStaysCollapsedAfterUpdate;
var
  View: TAtlasFindingsView;
begin
  View := TAtlasFindingsView.Create;
  try
    View.SetFindings(Sample);
    View.Toggle(0);
    Assert.AreEqual(4, Integer(Length(View.Rows)));
    Assert.IsFalse(View.Rows[0].Expanded);
    View.SetFindings(Sample);
    Assert.IsFalse(View.Rows[0].Expanded);
    Assert.AreEqual(4, Integer(Length(View.Rows)));
    // Auch eine Weile ohne Befunde: Die Gruppe bleibt zugeklappt.
    View.SetFindings(nil);
    View.SetFindings(Sample);
    Assert.IsFalse(View.Rows[0].Expanded);
    View.Toggle(0);
    Assert.AreEqual(6, Integer(Length(View.Rows)));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.SelectionSurvivesUpdateAndShiftedLines;
var
  View: TAtlasFindingsView;
  Store: TAtlasProblemStore;
  Selected: TAtlasFinding;
begin
  Store := TAtlasProblemStore.Create;
  View := TAtlasFindingsView.Create;
  try
    Store.Update('C:\P\A.pas', 'a' + #10 + 'b' + #10 + 'c' + #10, True,
      [Problem(1, 'r1', 'eins', TAtlasProblemSeverity.Warning), Problem(2, 'r2', 'zwei', TAtlasProblemSeverity.Warning)],
      '', True);
    View.SetFindings(TAtlasFindings.FromStore(Store, nil, nil));
    View.Select(1);
    Assert.IsTrue(View.SelectedFinding(Selected));
    Assert.AreEqual('r1', Selected.Rule);
    // Zwei Zeilen oben eingefügt: Die Befunde wandern mit, die Auswahl bleibt am selben Befund.
    Store.Edit('C:\P\A.pas', 'neu' + #10 + 'neu' + #10 + 'a' + #10 + 'b' + #10 + 'c' + #10);
    View.SetFindings(TAtlasFindings.FromStore(Store, nil, nil));
    Assert.AreEqual(1, View.SelectedRow);
    Assert.IsTrue(View.SelectedFinding(Selected));
    Assert.AreEqual('r1', Selected.Rule);
    Assert.AreEqual(3, Selected.Problem.StartLine);
    View.SetFindings(nil);
    Assert.AreEqual(-1, View.SelectedRow);
  finally
    View.Free;
    Store.Free;
  end;
end;

procedure TAtlasFindingsTests.NewFindingsAreMarkedOnlyAfterFirstFill;
var
  View: TAtlasFindingsView;
  Row: TAtlasFindingRow;
  NewCount: Integer;
begin
  View := TAtlasFindingsView.Create;
  try
    View.Grouping := TAtlasFindingGrouping.None;
    View.SetFindings(Copy(Sample, 0, 2));
    for Row in View.Rows do
      Assert.IsFalse(Row.IsNew);
    View.SetFindings(Sample);
    NewCount := 0;
    for Row in View.Rows do
      if Row.IsNew then
        Inc(NewCount);
    Assert.AreEqual(2, NewCount);
    View.ClearNew;
    for Row in View.Rows do
      Assert.IsFalse(Row.IsNew);
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.StepWrapsAndExpandsGroup;
var
  View: TAtlasFindingsView;
  Target: TAtlasFinding;
begin
  View := TAtlasFindingsView.Create;
  try
    View.SetFindings(Sample);
    // B.pas zuklappen: Der Schritt dorthin klappt sie wieder auf.
    View.Toggle(3);
    Assert.IsTrue(View.Step(True, Target));
    Assert.AreEqual('A.pas:8:3', Target.Location);
    Assert.IsTrue(View.Step(True, Target));
    Assert.AreEqual('A.pas:2:3', Target.Location);
    Assert.IsTrue(View.Step(True, Target));
    Assert.AreEqual('B.pas:4:3', Target.Location);
    Assert.IsTrue(View.Rows[3].Expanded);
    Assert.AreEqual(4, View.SelectedRow);
    Assert.IsTrue(View.Step(True, Target));
    Assert.IsTrue(View.Step(True, Target));
    Assert.AreEqual('A.pas:8:3', Target.Location);
    Assert.IsTrue(View.Step(False, Target));
    Assert.AreEqual('B.pas:10:3', Target.Location);
    View.SetFindings(nil);
    Assert.IsFalse(View.Step(True, Target));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.SelectAtFollowsCursor;
var
  View: TAtlasFindingsView;
  Selected: TAtlasFinding;
begin
  View := TAtlasFindingsView.Create;
  try
    View.SetFindings(Sample);
    View.Toggle(0);
    Assert.IsTrue(View.SelectAt('c:\p\a.pas', 7));
    Assert.IsTrue(View.Rows[0].Expanded);
    Assert.IsTrue(View.SelectedFinding(Selected));
    Assert.AreEqual('A.pas:8:3', Selected.Location);
    Assert.IsFalse(View.SelectAt('C:\P\A.pas', 5));
    Assert.IsTrue(View.SelectedFinding(Selected));
    Assert.AreEqual('A.pas:8:3', Selected.Location);
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.FindingsOfRowsTakesGroupMembersOnce;
var
  View: TAtlasFindingsView;
  Items: TArray<TAtlasFinding>;
begin
  View := TAtlasFindingsView.Create;
  try
    View.SetFindings(Sample);
    Items := View.FindingsOfRows([0, 1, 4]);
    Assert.AreEqual(3, Integer(Length(Items)));
    Assert.AreEqual('A.pas:8:3', Items[0].Location);
    Assert.AreEqual('A.pas:2:3', Items[1].Location);
    Assert.AreEqual('B.pas:4:3', Items[2].Location);
    Assert.AreEqual(0, Integer(Length(View.FindingsOfRows([99]))));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.ColumnsRoundTripAndKeepMandatoryVisible;
var
  Columns: TArray<TAtlasFindingColumnState>;
begin
  Columns := TAtlasFindings.ParseColumns('');
  Assert.AreEqual(8, Integer(Length(Columns)));
  Assert.AreEqual('icon,kind,category,message,line,location,rule,compiler', TAtlasFindings.FormatColumns(Columns));
  Columns := TAtlasFindings.ParseColumns('rule:120, -message, -kind, unbekannt, location:80, rule');
  Assert.IsTrue(Columns[0].Column = TAtlasFindingColumn.Rule);
  Assert.AreEqual(120, Columns[0].Width);
  Assert.IsFalse(Columns[1].Visible);
  // Art ist Pflicht: bleibt sichtbar.
  Assert.IsTrue(Columns[2].Visible);
  Assert.AreEqual('rule:120,-message,kind,location:80,icon,category,line,compiler',
    TAtlasFindings.FormatColumns(Columns));
  Assert.IsTrue(TAtlasFindings.IsMandatory(TAtlasFindingColumn.Location));
  Assert.IsFalse(TAtlasFindings.IsMandatory(TAtlasFindingColumn.Message));
  Assert.IsFalse(TAtlasFindings.IsMandatory(TAtlasFindingColumn.Compiler), 'Spalte Compiler abwählbar (#1024)');
  Assert.AreEqual('-compiler,icon,kind,category,message,line,location,rule',
    TAtlasFindings.FormatColumns(TAtlasFindings.ParseColumns('-compiler')));
end;

procedure TAtlasFindingsTests.ScopeAndGroupingNames;
var
  Scope: TAtlasFindingScope;
  Grouping: TAtlasFindingGrouping;
begin
  Assert.IsTrue(TAtlasFindings.TryParseScope('project', Scope));
  Assert.IsTrue(Scope = TAtlasFindingScope.Project);
  Assert.IsFalse(TAtlasFindings.TryParseScope('x', Scope));
  Assert.IsTrue(Scope = TAtlasFindingScope.Group);
  Assert.IsTrue(TAtlasFindings.TryParseGrouping('Rule', Grouping));
  Assert.IsTrue(Grouping = TAtlasFindingGrouping.ByRule);
  Assert.IsFalse(TAtlasFindings.TryParseGrouping('', Grouping));
  Assert.IsTrue(Grouping = TAtlasFindingGrouping.ByFile);
end;

procedure TAtlasFindingsTests.CheckedCountCountsDeliveredFiles;
var
  Store: TAtlasProblemStore;
begin
  Store := TAtlasProblemStore.Create;
  try
    Store.Update('C:\P\A.pas', '', False, nil, '', True);
    Store.Update('C:\P\B.pas', '', False, [Problem(0, 'r', 'm', TAtlasProblemSeverity.Error)], '', True);
    Assert.AreEqual(2, TAtlasFindings.CheckedCount(Store, ['C:\P\A.pas', 'C:\P\B.pas', 'C:\P\C.pas']));
  finally
    Store.Free;
  end;
end;

procedure TAtlasFindingsTests.CopyTextUsesCompilerFormat;
var
  Items: TArray<TAtlasFinding>;
begin
  Items := TAtlasFindings.FromProblems('C:\P\B.pas', [Problem(9, 'empty-except', 'Leer', TAtlasProblemSeverity.Warning),
    Problem(3, 'syntax', 'Fehlt', TAtlasProblemSeverity.Error)], ['', '', '', '  X := 1;']);
  Assert.AreEqual('B.pas:10:3: warning [empty-except] Leer'#13#10 +
    'B.pas:4:3: error [syntax] Fehlt'#13#10'    X := 1;'#13#10, TAtlasFindings.AsText(Items));
  Assert.AreEqual('', TAtlasFindings.AsText(nil));
end;

/// <summary>Z aktiv, A und B geöffnet, C und D nicht geöffnet; je Datei zwei Befunde (Fehler, Warnung).</summary>
function TierSample: TArray<TAtlasFinding>;
var
  Name: string;
begin
  Result := nil;
  for Name in ['C', 'Z', 'B', 'D', 'A'] do
    Result := Result + TAtlasFindings.FromProblems('C:\P\' + Name + '.pas',
      [Problem(5, 'empty-except', 'Leer', TAtlasProblemSeverity.Warning),
      Problem(2, 'syntax', 'Fehlt', TAtlasProblemSeverity.Error)], nil);
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
  Row: TAtlasFindingRow;
  Part: string;
begin
  Result := '';
  for Row in AView.Rows do
  begin
    if Row.IsSection then
    begin
      Part := 'S' + IntToStr(Ord(Row.Tier)) + ':' + Row.Caption + ':' + IntToStr(Row.Units) + '/' +
        IntToStr(Row.Count);
      if Row.IsCleanActive then
        Part := Part + ':clean';
    end
    else if Row.IsGroup then
      Part := 'G:' + Row.Caption
    else
      Part := 'F:' + AView.Finding(Row.Finding).Location;
    if Row.Pinned then
      Part := Part + '*';
    if Row.Dimmed then
      Part := Part + '~';
    Result := Result + Part + ' ';
  end;
  Result := Result.Trim;
end;

procedure TAtlasFindingsTests.TiersOrderFileGroups;
var
  View: TAtlasFindingsView;
begin
  View := TierView;
  try
    Assert.AreEqual('G:Z.pas* F:Z.pas:3:3* F:Z.pas:6:3* ' +
      'S1::2/4 G:A.pas F:A.pas:3:3 F:A.pas:6:3 G:B.pas F:B.pas:3:3 F:B.pas:6:3 ' +
      'S2::2/4~ G:C.pas~ F:C.pas:3:3~ F:C.pas:6:3~ G:D.pas~ F:D.pas:3:3~ F:D.pas:6:3~', RowsText(View));
    Assert.IsTrue(View.Rows[0].Tier = TAtlasFindingTier.Active);
    Assert.IsTrue(View.Finding(View.Rows[1].Finding).Tier = TAtlasFindingTier.Active);
    Assert.IsTrue(View.Finding(View.Rows[5].Finding).Tier = TAtlasFindingTier.Open);
    Assert.IsTrue(View.Rows[11].Tier = TAtlasFindingTier.Closed);
    Assert.IsTrue(View.Finding(View.Rows[12].Finding).Tier = TAtlasFindingTier.Closed);
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.TiersWithoutGroupingAreSections;
var
  View: TAtlasFindingsView;
  Items: TArray<TAtlasFinding>;
begin
  View := TierView;
  try
    View.Grouping := TAtlasFindingGrouping.None;
    // Innerhalb der Stufe die Vorgabe Art, Datei, Zeile.
    Assert.AreEqual('S0:Z.pas:1/2* F:Z.pas:3:3* F:Z.pas:6:3* ' +
      'S1::2/4 F:A.pas:3:3 F:B.pas:3:3 F:A.pas:6:3 F:B.pas:6:3 ' +
      'S2::2/4~ F:C.pas:3:3~ F:D.pas:3:3~ F:C.pas:6:3~ F:D.pas:6:3~', RowsText(View));
    Items := View.Visible;
    Assert.AreEqual(10, Integer(Length(Items)));
    Assert.AreEqual('Z.pas:3:3', Items[0].Location);
    Assert.IsFalse(TAtlasFindings.AsText(Items).Contains('Geöffnet'));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.TiersInsideRuleAndCategoryGroups;
var
  View: TAtlasFindingsView;
begin
  View := TierView;
  try
    View.Grouping := TAtlasFindingGrouping.ByRule;
    Assert.AreEqual('G:empty-except F:Z.pas:6:3* F:A.pas:6:3 F:B.pas:6:3 F:C.pas:6:3~ F:D.pas:6:3~ ' +
      'G:syntax F:Z.pas:3:3* F:A.pas:3:3 F:B.pas:3:3 F:C.pas:3:3~ F:D.pas:3:3~', RowsText(View));
    View.Grouping := TAtlasFindingGrouping.ByCategory;
    Assert.AreEqual('G:code-smell F:Z.pas:3:3* F:Z.pas:6:3* F:A.pas:3:3 F:B.pas:3:3 F:A.pas:6:3 F:B.pas:6:3 ' +
      'F:C.pas:3:3~ F:D.pas:3:3~ F:C.pas:6:3~ F:D.pas:6:3~', RowsText(View));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.ColumnSortWorksInsideTiers;
var
  View: TAtlasFindingsView;
begin
  View := TierView;
  try
    View.Grouping := TAtlasFindingGrouping.None;
    View.SortBy(TAtlasFindingColumn.Location);
    View.SortBy(TAtlasFindingColumn.Location);
    Assert.IsTrue(View.SortDescending);
    Assert.AreEqual('S0:Z.pas:1/2* F:Z.pas:6:3* F:Z.pas:3:3* ' +
      'S1::2/4 F:B.pas:6:3 F:B.pas:3:3 F:A.pas:6:3 F:A.pas:3:3 ' +
      'S2::2/4~ F:D.pas:6:3~ F:D.pas:3:3~ F:C.pas:6:3~ F:C.pas:3:3~', RowsText(View));
    View.ResetSort;
    Assert.AreEqual('Z.pas:3:3', View.Visible[0].Location);
    Assert.AreEqual('A.pas:3:3', View.Visible[2].Location);
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.SwitchingEditorMovesOnlyPinnedGroup;
var
  View: TAtlasFindingsView;
begin
  View := TierView;
  try
    View.SetOpenFiles('C:\P\B.pas', ['C:\P\Z.pas', 'C:\P\B.pas', 'C:\P\A.pas'], True);
    // B steht oben, Z rückt alphabetisch unter A; A bleibt, wo es war.
    Assert.AreEqual('G:B.pas* F:B.pas:3:3* F:B.pas:6:3* ' +
      'S1::2/4 G:A.pas F:A.pas:3:3 F:A.pas:6:3 G:Z.pas F:Z.pas:3:3 F:Z.pas:6:3 ' +
      'S2::2/4~ G:C.pas~ F:C.pas:3:3~ F:C.pas:6:3~ G:D.pas~ F:D.pas:3:3~ F:D.pas:6:3~', RowsText(View));
    // Unit schließen: rutscht nach „Nicht geöffnet“.
    View.SetOpenFiles('C:\P\B.pas', ['C:\P\B.pas', 'C:\P\A.pas'], True);
    Assert.AreEqual('G:B.pas* F:B.pas:3:3* F:B.pas:6:3* S1::1/2 G:A.pas F:A.pas:3:3 F:A.pas:6:3 ' +
      'S2::3/6~ G:C.pas~ F:C.pas:3:3~ F:C.pas:6:3~ G:D.pas~ F:D.pas:3:3~ F:D.pas:6:3~ ' +
      'G:Z.pas~ F:Z.pas:3:3~ F:Z.pas:6:3~', RowsText(View));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.SectionsAreSkippedBySelectionStepAndCopy;
var
  View: TAtlasFindingsView;
  Item: TAtlasFinding;
  Rows: TArray<TAtlasFindingRow>;
begin
  View := TierView;
  try
    View.Grouping := TAtlasFindingGrouping.None;
    Rows := View.Rows;
    Assert.IsTrue(Rows[3].IsSection);
    Assert.IsFalse(Rows[3].IsGroup);
    View.Select(2);
    View.Select(3);
    // Die Trennzeile ist nicht wählbar: Die Auswahl bleibt auf dem Befund davor.
    Assert.AreEqual(2, View.SelectedRow);
    View.Toggle(3);
    Assert.AreEqual(Integer(Length(Rows)), Integer(Length(View.Rows)));
    Assert.IsTrue(View.Step(True, Item));
    Assert.AreEqual('A.pas:3:3', Item.Location);
    Assert.AreEqual(4, View.SelectedRow);
    Assert.AreEqual(0, Integer(Length(View.FindingsOfRows([0, 3, 8]))));
    Assert.AreEqual(1, Integer(Length(View.FindingsOfRows([0, 3, 4]))));
    Assert.IsTrue(View.SelectAt('C:\P\C.pas', 2));
    Assert.AreEqual(9, View.SelectedRow);
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.ClosedUnitsDimmedNormalHidden;
var
  View: TAtlasFindingsView;
  Counts: TAtlasFindingCounts;
begin
  View := TierView;
  try
    Counts := View.Counts;
    Assert.AreEqual(10, Counts.Total);
    Assert.AreEqual(3, Counts.OpenUnits);
    Assert.AreEqual(6, Counts.OpenFindings);
    Assert.AreEqual(2, Counts.ClosedUnits);
    Assert.AreEqual(4, Counts.ClosedFindings);
    Assert.AreEqual(0, Counts.HiddenUnits);
    View.ClosedUnits := TAtlasClosedUnits.Normal;
    Assert.AreEqual('S2::2/4 G:C.pas F:C.pas:3:3 F:C.pas:6:3 G:D.pas F:D.pas:3:3 F:D.pas:6:3',
      RowsText(View).Substring(RowsText(View).IndexOf('S2')));
    View.ClosedUnits := TAtlasClosedUnits.Hidden;
    Assert.AreEqual('G:Z.pas* F:Z.pas:3:3* F:Z.pas:6:3* ' +
      'S1::2/4 G:A.pas F:A.pas:3:3 F:A.pas:6:3 G:B.pas F:B.pas:3:3 F:B.pas:6:3', RowsText(View));
    Counts := View.Counts;
    // Ausgeblendet zählt nicht mit, auch nicht auf den Umschaltern.
    Assert.AreEqual(6, Counts.Total);
    Assert.AreEqual(3, Counts.Warnings);
    Assert.AreEqual(0, Counts.ClosedUnits);
    Assert.AreEqual(2, Counts.HiddenUnits);
    Assert.AreEqual(3, Counts.Files);
    Assert.AreEqual(6, Integer(Length(View.Visible)));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.CleanActiveUnitShowsWithoutFindings;
var
  View: TAtlasFindingsView;
  Counts: TAtlasFindingCounts;
begin
  View := TierView;
  try
    View.SetOpenFiles('C:\P\Sauber.pas', ['C:\P\Sauber.pas', 'C:\P\A.pas'], False);
    Assert.IsTrue(RowsText(View).StartsWith('S0:Sauber.pas:0/0:clean* S1::1/2 G:A.pas '), RowsText(View));
    Assert.IsTrue(View.Rows[0].Checking);
    View.SetOpenFiles('C:\P\Sauber.pas', ['C:\P\Sauber.pas', 'C:\P\A.pas'], True);
    Assert.IsFalse(View.Rows[0].Checking);
    Assert.IsTrue(View.Rows[0].IsCleanActive);
    Counts := View.Counts;
    Assert.AreEqual(10, Counts.Total);
    Assert.AreEqual(5, Counts.Files);
    View.Grouping := TAtlasFindingGrouping.None;
    Assert.IsTrue(RowsText(View).StartsWith('S0:Sauber.pas:0/0:clean* S1::1/2 F:A.pas:3:3 '), RowsText(View));
    View.Grouping := TAtlasFindingGrouping.ByRule;
    Assert.IsTrue(RowsText(View).StartsWith('G:empty-except '), RowsText(View));
    View.Grouping := TAtlasFindingGrouping.ByFile;
    View.ShowCleanActive := False;
    Assert.IsTrue(RowsText(View).StartsWith('S1::1/2 G:A.pas '), RowsText(View));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.SelectionAndCollapseSurviveResort;
var
  View: TAtlasFindingsView;
  Item: TAtlasFinding;
  Key: string;
begin
  View := TierView;
  try
    View.SetExpanded('file:c:\p\c.pas', False);
    View.Select(5);
    Assert.IsTrue(View.SelectedFinding(Item));
    Key := Item.Key;
    Assert.AreEqual('A.pas:3:3', Item.Location);
    View.SetFindings(TierSample);
    View.SetOpenFiles('C:\P\A.pas', ['C:\P\A.pas', 'C:\P\C.pas'], True);
    Assert.IsTrue(View.SelectedFinding(Item));
    Assert.AreEqual(Key, Item.Key);
    Assert.AreEqual(1, View.SelectedRow);
    // C ist jetzt geöffnet und bleibt zugeklappt.
    Assert.IsTrue(RowsText(View).Contains('S1::1/2 G:C.pas S2'), RowsText(View));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.FormFilePinsItsUnitIgnoringCase;
var
  View: TAtlasFindingsView;
begin
  View := TierView;
  try
    View.SetOpenFiles('c:\p\b.DFM', ['C:\P\b.dfm', 'C:\P\A.PAS'], True);
    Assert.IsTrue(RowsText(View).StartsWith('G:B.pas* F:B.pas:3:3* F:B.pas:6:3* S1::1/2 G:A.pas '),
      RowsText(View));
    Assert.AreEqual('c:\p\b.pas', View.ActiveFile);
    Assert.AreEqual('c:\p\b.pas', TAtlasFindings.UnitKey('C:\P\B.dfm'));
    Assert.AreEqual('c:\p\b.pas', TAtlasFindings.UnitKey('C:\P\B.FMX'));
    Assert.AreEqual('c:\p\b.inc', TAtlasFindings.UnitKey('C:\P\B.inc'));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.OpenFirstOffKeepsOrderOf909;
var
  View, Plain: TAtlasFindingsView;
  Grouping: TAtlasFindingGrouping;
begin
  View := TierView;
  Plain := TAtlasFindingsView.Create;
  try
    View.OpenFirst := False;
    Plain.SetFindings(TierSample);
    for Grouping := Low(TAtlasFindingGrouping) to High(TAtlasFindingGrouping) do
    begin
      View.Grouping := Grouping;
      Plain.Grouping := Grouping;
      Assert.AreEqual(RowsText(Plain), RowsText(View));
    end;
    Assert.IsFalse(RowsText(View).Contains('*'));
    Assert.AreEqual(0, View.Counts.OpenUnits);
  finally
    Plain.Free;
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.CurrentFileScopeHasNoSections;
var
  View: TAtlasFindingsView;
  Filter: TAtlasFindingFilter;
begin
  View := TierView;
  try
    Filter := View.Filter;
    Filter.Scope := TAtlasFindingScope.CurrentFile;
    Filter.CurrentFile := 'C:\P\Z.pas';
    View.Filter := Filter;
    Assert.IsFalse(View.TiersActive);
    Assert.AreEqual('G:Z.pas F:Z.pas:3:3 F:Z.pas:6:3', RowsText(View));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.ProjectScopeLimitsClosedUnits;
var
  View: TAtlasFindingsView;
  Filter: TAtlasFindingFilter;
begin
  View := TierView;
  try
    Filter := View.Filter;
    Filter.Scope := TAtlasFindingScope.Project;
    Filter.Files := ['C:\P\Z.pas', 'C:\P\A.pas', 'C:\P\C.pas'];
    View.Filter := Filter;
    Assert.AreEqual('G:Z.pas* F:Z.pas:3:3* F:Z.pas:6:3* S1::1/2 G:A.pas F:A.pas:3:3 F:A.pas:6:3 ' +
      'S2::1/2~ G:C.pas~ F:C.pas:3:3~ F:C.pas:6:3~', RowsText(View));
    // Aktive Unit außerhalb des Projekts: keine Zeile „Keine Befunde“.
    View.SetOpenFiles('C:\Fremd\X.pas', ['C:\Fremd\X.pas'], True);
    Assert.IsTrue(RowsText(View).StartsWith('S2::'), RowsText(View));
  finally
    View.Free;
  end;
end;

procedure TAtlasFindingsTests.ClosedUnitsNames;
var
  Value: TAtlasClosedUnits;
begin
  Assert.IsTrue(TAtlasFindings.TryParseClosedUnits('hidden', Value));
  Assert.IsTrue(Value = TAtlasClosedUnits.Hidden);
  Assert.IsTrue(TAtlasFindings.TryParseClosedUnits('Normal', Value));
  Assert.IsTrue(Value = TAtlasClosedUnits.Normal);
  Assert.IsFalse(TAtlasFindings.TryParseClosedUnits('grau', Value));
  Assert.IsTrue(Value = TAtlasClosedUnits.Dimmed);
  Assert.AreEqual('dimmed', TAtlasFindings.ClosedUnitsNames[TAtlasClosedUnits.Dimmed]);
end;

procedure TAtlasFindingsTests.DimmedColorsStayReadable;
var
  Back, Text, Dimmed: TAtlasColor;
  Backs: array[0..3] of TAtlasColor;
  Texts: array[0..3] of TAtlasColor;
  Index: Integer;
  Error, Warn: TAtlasColor;
begin
  Backs[0] := TAtlasColorMath.FromHex('#FFFFFF');
  Texts[0] := TAtlasColorMath.FromHex('#1F2328');
  Backs[1] := TAtlasColorMath.FromHex('#1A1E25');
  Texts[1] := TAtlasColorMath.FromHex('#E6E8EB');
  Backs[2] := TAtlasColorMath.FromHex('#2B2B2B');
  Texts[2] := TAtlasColorMath.FromHex('#C8C8C8');
  Backs[3] := TAtlasColorMath.FromHex('#F0F0F0');
  Texts[3] := TAtlasColorMath.FromHex('#707070');
  for Index := 0 to High(Backs) do
  begin
    Back := Backs[Index];
    Text := Texts[Index];
    Dimmed := DimmedTextColor(Text, Back);
    Assert.IsTrue(TAtlasColorMath.Contrast(Dimmed, Back) >= AtlasDimmedMinContrast - 0.01,
      TAtlasColorMath.ToHex(Dimmed));
    // Ausgegraut heißt: weniger Kontrast als der Text, solange das Maß es erlaubt; zu blasser Text wird kräftiger.
    if TAtlasColorMath.Contrast(Text, Back) >= AtlasDimmedMinContrast then
      Assert.IsTrue(TAtlasColorMath.Contrast(Dimmed, Back) <= TAtlasColorMath.Contrast(Text, Back) + 0.01);
  end;
  Assert.AreNotEqual(TAtlasColorMath.ToHex(Texts[0]), TAtlasColorMath.ToHex(DimmedTextColor(Texts[0], Backs[0])));
  // Symbole bleiben unterscheidbar.
  Error := DimmedIconColor($003C3CD8, Backs[0]);
  Warn := DimmedIconColor($0020A8F0, Backs[0]);
  Assert.IsTrue(TAtlasColorMath.DeltaE2000(Error, Warn) > 10);
  Assert.AreNotEqual(TAtlasColorMath.ToHex($003C3CD8), TAtlasColorMath.ToHex(Error));
  // Angepinnt: hell etwa #EEF4FB.
  Assert.IsTrue(TAtlasColorMath.DeltaE2000(PinnedBackColor(Backs[0]), TAtlasColorMath.FromHex('#EEF4FB')) < 3,
    TAtlasColorMath.ToHex(PinnedBackColor(Backs[0])));
  Assert.IsTrue(TAtlasColorMath.IsDark(PinnedBackColor(Backs[1])));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFindingsTests);

end.
