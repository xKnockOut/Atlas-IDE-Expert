unit Atlas.Core.Problems.Findings.Tests;

// Tests für das Modell des Fensters „Atlas-Prüfung“ (#909): Art und Kategorie,
// Befunde aus dem Speicher, Filter, Gruppierung, Sortierung, Zähler, Auswahl
// und Aufklappzustand über Aktualisierungen, mitwandernde Zeilen, Spalten.

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

implementation

uses
  System.SysUtils,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Problems.Findings;

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

initialization
  TDUnitX.RegisterTestFixture(TAtlasFindingsTests);

end.
