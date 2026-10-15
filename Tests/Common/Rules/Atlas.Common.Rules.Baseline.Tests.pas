unit Atlas.Common.Rules.Baseline.Tests;

// Tests für die Baseline bekannter Treffer (#97): Zuordnung über Regel,
// Routine und Zeile, ältere Dateien ohne Routine, umbenannte Routinen über
// den Kontext, Zähler und Einträge ohne Datei beim Aktualisieren und das
// Zusammenspiel mit Unterdrückungskommentaren (#147).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleBaselineTests = class
  public
    [Test]
    procedure HidesKnownFindings;
    [Test]
    procedure SurvivesShiftedLines;
    [Test]
    procedure ReportsChangedLine;
    [Test]
    procedure ReportsAdditionalIdenticalFinding;
    [Test]
    procedure MatchesPathsWithEitherSeparator;
    [Test]
    procedure IgnoresIndentation;
    [Test]
    procedure BuildDropsVanishedFindings;
    [Test]
    procedure BuildIsSortedAndCounts;
    [Test]
    procedure RejectsWrongVersion;
    [Test]
    procedure RejectsIncompleteEntry;
    [Test]
    procedure FilterDoesNotConsumeBaseline;
    /// <summary>Abnahme: zwei gleiche Zeilen X.Free; in verschiedenen Routinen.</summary>
    [Test]
    procedure SameLineInOtherRoutineIsNew;
    /// <summary>Abnahme: ein Treffer, der in eine andere Routine wandert, wird gemeldet.</summary>
    [Test]
    procedure MovedToOtherRoutineIsReported;
    [Test]
    procedure RenamedRoutineKeepsEntry;
    [Test]
    procedure LegacyEntryWithoutRoutineStillHides;
    [Test]
    procedure UpdateCompletesLegacyEntries;
    [Test]
    procedure UpdateCountsAddedRemovedUnchanged;
    /// <summary>Abnahme: nach Umbenennen einer Datei nennt das Aktualisieren die verwaisten Einträge.</summary>
    [Test]
    procedure UpdateReportsOrphansOfRenamedFile;
    [Test]
    procedure UpdateWithoutPreviousBaseline;
    [Test]
    procedure ClassifyMarksUnchangedAndAbsent;
    [Test]
    procedure BuildWritesRoutineAndContext;
    [Test]
    procedure ContextIgnoresIndentationAndRoutineName;
    [Test]
    procedure CountersJsonListsOrphans;
    /// <summary>Abnahme (#147): Unterdrückung für einen Treffer aus der Baseline ist keine unused-suppression.
    /// </summary>
    [Test]
    procedure SuppressionOfBaselineFindingIsNotUnused;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.Baseline;

const
  Original = 'unit U;' + #10 + 'begin' + #10 + '  X := 1;' + #10 + 'end.';
  // Zeile 5 in TFoo.A, Zeile 9 in TFoo.B.
  TwoRoutines =
    'unit U;' + #10 +
    'interface' + #10 +
    'implementation' + #10 +
    'procedure TFoo.A;' + #10 +
    'begin' + #10 +
    '  X.Free;' + #10 +
    'end;' + #10 +
    'procedure TFoo.B;' + #10 +
    'begin' + #10 +
    '  Y := 1;' + #10 +
    'end;' + #10 +
    'end.';

type
  /// <summary>Meldet jeden Bezeichner "Marker".</summary>
  TMarkerRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

function TMarkerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('marker', TRuleSeverity.Warning, 'Meldet den Bezeichner Marker');
end;

procedure TMarkerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Token: TPascalToken;
begin
  for Token in AContext.Tree.Tokens do
    if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, 'Marker') then
      AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos), 'Marker gefunden');
end;

function Swap(const AText, AOld, ANew: string): string;
begin
  Result := StringReplace(AText, AOld, ANew, []);
end;

function Finding(const ARuleId: string; ALine: Integer): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARuleId;
  Result.Range := TTextRange.Create(TTextPosition.Create(ALine, 0), TTextPosition.Create(ALine, 1));
end;

function Source(const APath, AText: string; const AFindings: TArray<TRuleFinding>): TBaselineSource;
begin
  Result.Path := APath;
  Result.Text := AText;
  Result.Findings := AFindings;
end;

function BaselineOf(const ASources: TArray<TBaselineSource>): IRuleBaseline;
begin
  Result := TRuleBaseline.FromJson(TRuleBaseline.Build(ASources));
end;

procedure ExpectBaselineError(const AJson: string);
var
  Raised: Boolean;
begin
  Raised := False;
  try
    TRuleBaseline.FromJson(AJson);
  except
    on ERuleBaseline do
      Raised := True;
  end;
  Assert.IsTrue(Raised, AJson);
end;

{ TRuleBaselineTests }

procedure TRuleBaselineTests.HidesKnownFindings;
var
  Baseline: IRuleBaseline;
begin
  Baseline := BaselineOf([Source('Src\U.pas', Original, [Finding('a', 2)])]);
  Assert.AreEqual(1, Baseline.Count);
  Assert.AreEqual<NativeInt>(0, Length(Baseline.Filter('Src\U.pas', Original, [Finding('a', 2)])));
  // Andere Regel in derselben Zeile ist neu.
  Assert.AreEqual<NativeInt>(1, Length(Baseline.Filter('Src\U.pas', Original, [Finding('b', 2)])));
  // Andere Datei ebenso.
  Assert.AreEqual<NativeInt>(1, Length(Baseline.Filter('Src\V.pas', Original, [Finding('a', 2)])));
end;

procedure TRuleBaselineTests.SurvivesShiftedLines;
var
  Baseline: IRuleBaseline;
  Shifted: string;
begin
  Baseline := BaselineOf([Source('U.pas', Original, [Finding('a', 2)])]);
  Shifted := 'unit U;' + #10 + '// neu' + #10 + '// neu' + #10 + 'begin' + #10 + '  X := 1;' + #10 + 'end.';
  Assert.AreEqual<NativeInt>(0, Length(Baseline.Filter('U.pas', Shifted, [Finding('a', 4)])));
end;

procedure TRuleBaselineTests.ReportsChangedLine;
var
  Baseline: IRuleBaseline;
begin
  Baseline := BaselineOf([Source('U.pas', Original, [Finding('a', 2)])]);
  Assert.AreEqual<NativeInt>(1, Length(Baseline.Filter('U.pas', StringReplace(Original, 'X := 1', 'X := 2', []),
    [Finding('a', 2)])));
end;

procedure TRuleBaselineTests.ReportsAdditionalIdenticalFinding;
var
  Baseline: IRuleBaseline;
  Twice: string;
  Remaining: TArray<TRuleFinding>;
begin
  Baseline := BaselineOf([Source('U.pas', Original, [Finding('a', 2)])]);
  Twice := 'unit U;' + #10 + 'begin' + #10 + '  X := 1;' + #10 + '  X := 1;' + #10 + 'end.';
  Remaining := Baseline.Filter('U.pas', Twice, [Finding('a', 2), Finding('a', 3)]);
  Assert.AreEqual<NativeInt>(1, Length(Remaining));
  Assert.AreEqual(3, Remaining[0].Range.StartPos.Line);
end;

procedure TRuleBaselineTests.MatchesPathsWithEitherSeparator;
var
  Baseline: IRuleBaseline;
begin
  Baseline := BaselineOf([Source('Src\Sub\U.pas', Original, [Finding('a', 2)])]);
  Assert.AreEqual<NativeInt>(0, Length(Baseline.Filter('src/sub/u.pas', Original, [Finding('A', 2)])));
end;

procedure TRuleBaselineTests.IgnoresIndentation;
var
  Baseline: IRuleBaseline;
begin
  Baseline := BaselineOf([Source('U.pas', Original, [Finding('a', 2)])]);
  Assert.AreEqual<NativeInt>(0, Length(Baseline.Filter('U.pas',
    StringReplace(Original, '  X := 1;', #9'X  :=   1;'#13, []), [Finding('a', 2)])));
end;

procedure TRuleBaselineTests.BuildDropsVanishedFindings;
var
  Baseline: IRuleBaseline;
begin
  // Neu geschrieben enthält die Baseline nur, was aktuell gefunden wird.
  Baseline := BaselineOf([Source('U.pas', Original, [Finding('a', 2)]), Source('V.pas', Original, nil)]);
  Assert.AreEqual(1, Baseline.Count);
  Baseline := BaselineOf([Source('U.pas', Original, nil)]);
  Assert.AreEqual(0, Baseline.Count);
  Assert.AreEqual<NativeInt>(1, Length(Baseline.Filter('U.pas', Original, [Finding('a', 2)])));
end;

procedure TRuleBaselineTests.BuildIsSortedAndCounts;
var
  Json: string;
begin
  Json := TRuleBaseline.Build([Source('B.pas', Original, [Finding('z', 2)]),
    Source('A.pas', Original, [Finding('a', 2), Finding('a', 2)])]);
  Assert.IsTrue(Pos('"version": 1', Json) > 0, Json);
  Assert.IsTrue(Pos('"path": "A.pas"', Json) < Pos('"path": "B.pas"', Json), Json);
  Assert.IsTrue(Pos('"rule": "a", "fingerprint": "' + TRuleBaseline.Fingerprint(Original, Finding('a', 2)) +
    '", "count": 2', Json) > 0, Json);
end;

procedure TRuleBaselineTests.RejectsWrongVersion;
begin
  ExpectBaselineError('{"version":2,"findings":[]}');
  ExpectBaselineError('[]');
end;

procedure TRuleBaselineTests.RejectsIncompleteEntry;
begin
  ExpectBaselineError('{"version":1,"findings":[{"path":"U.pas","rule":"a"}]}');
end;

procedure TRuleBaselineTests.FilterDoesNotConsumeBaseline;
var
  Baseline: IRuleBaseline;
begin
  Baseline := BaselineOf([Source('U.pas', Original, [Finding('a', 2)])]);
  Assert.AreEqual<NativeInt>(0, Length(Baseline.Filter('U.pas', Original, [Finding('a', 2)])));
  Assert.AreEqual<NativeInt>(0, Length(Baseline.Filter('U.pas', Original, [Finding('a', 2)])));
end;

procedure TRuleBaselineTests.SameLineInOtherRoutineIsNew;
var
  Baseline: IRuleBaseline;
  Text: string;
  Remaining: TArray<TRuleFinding>;
begin
  // Beide Routinen enthalten X.Free; in der Baseline steht nur der Treffer in TFoo.A.
  Text := Swap(TwoRoutines, '  Y := 1;', '  X.Free;');
  Baseline := BaselineOf([Source('U.pas', Text, [Finding('a', 5)])]);
  Remaining := Baseline.Filter('U.pas', Text, [Finding('a', 5), Finding('a', 9)]);
  Assert.AreEqual<NativeInt>(1, Length(Remaining));
  Assert.AreEqual(9, Remaining[0].Range.StartPos.Line);
  // Steht nur TFoo.B in der Baseline, bleibt TFoo.A gemeldet.
  Baseline := BaselineOf([Source('U.pas', Text, [Finding('a', 9)])]);
  Remaining := Baseline.Filter('U.pas', Text, [Finding('a', 5), Finding('a', 9)]);
  Assert.AreEqual<NativeInt>(1, Length(Remaining));
  Assert.AreEqual(5, Remaining[0].Range.StartPos.Line);
end;

procedure TRuleBaselineTests.MovedToOtherRoutineIsReported;
var
  Baseline: IRuleBaseline;
  Moved: string;
begin
  Baseline := BaselineOf([Source('U.pas', TwoRoutines, [Finding('a', 5)])]);
  // X.Free wandert von TFoo.A nach TFoo.B; TFoo.A gibt es weiter.
  Moved := Swap(Swap(TwoRoutines, '  X.Free;', '  Z := 2;'), '  Y := 1;', '  X.Free;');
  Assert.AreEqual<NativeInt>(1, Length(Baseline.Filter('U.pas', Moved, [Finding('a', 9)])));
end;

procedure TRuleBaselineTests.RenamedRoutineKeepsEntry;
var
  Baseline: IRuleBaseline;
  Renamed: string;
  Marks: TArray<TBaselineMark>;
begin
  Baseline := BaselineOf([Source('U.pas', TwoRoutines, [Finding('a', 5)])]);
  Renamed := Swap(TwoRoutines, 'procedure TFoo.A;', 'procedure TFoo.Umbenannt;');
  Marks := Baseline.Classify('U.pas', Renamed, TFindingScopes.FromText(Renamed), [Finding('a', 5)]);
  Assert.AreEqual<NativeInt>(1, Length(Marks));
  Assert.IsTrue(Marks[0].State = TBaselineState.Unchanged);
  Assert.IsTrue(Marks[0].Match = TBaselineMatch.Renamed);
  Assert.AreEqual('TFoo.Umbenannt', Marks[0].Routine);
  // Anderer Code in der umbenannten Routine bleibt neu.
  Renamed := Swap(Renamed, '  X.Free;', '  W.Free;');
  Assert.AreEqual<NativeInt>(1, Length(Baseline.Filter('U.pas', Renamed, [Finding('a', 5)])));
end;

procedure TRuleBaselineTests.LegacyEntryWithoutRoutineStillHides;
var
  Baseline: IRuleBaseline;
  Text: string;
begin
  Text := Swap(TwoRoutines, '  Y := 1;', '  X.Free;');
  // Datei vor #97: ohne "routine" und "context".
  Baseline := TRuleBaseline.FromJson('{"version": 1, "findings": [{"path": "U.pas", "rule": "a", "fingerprint": "' +
    TRuleBaseline.Fingerprint(Text, Finding('a', 5)) + '", "count": 1}]}');
  Assert.AreEqual(1, Baseline.LegacyCount);
  Assert.AreEqual<NativeInt>(0, Length(Baseline.Filter('U.pas', Text, [Finding('a', 5)])));
  // Wie bisher gilt der Eintrag für jede Routine, aber nur einmal.
  Assert.AreEqual<NativeInt>(0, Length(Baseline.Filter('U.pas', Text, [Finding('a', 9)])));
  Assert.AreEqual<NativeInt>(1, Length(Baseline.Filter('U.pas', Text, [Finding('a', 5), Finding('a', 9)])));
end;

procedure TRuleBaselineTests.UpdateCompletesLegacyEntries;
var
  Old: IRuleBaseline;
  Outcome: TBaselineUpdate;
begin
  Old := TRuleBaseline.FromJson('{"version": 1, "findings": [{"path": "U.pas", "rule": "a", "fingerprint": "' +
    TRuleBaseline.Fingerprint(TwoRoutines, Finding('a', 5)) + '"}]}');
  Outcome := TRuleBaseline.Update(Old, [Source('U.pas', TwoRoutines, [Finding('a', 5)])], nil);
  Assert.AreEqual(1, Outcome.Unchanged);
  Assert.AreEqual(1, Outcome.Completed);
  Assert.AreEqual(0, Outcome.Added);
  Assert.AreEqual(0, Outcome.Removed);
  Assert.IsTrue(Pos('"routine": "TFoo.A"', Outcome.Json) > 0, Outcome.Json);
  Assert.AreEqual(0, TRuleBaseline.FromJson(Outcome.Json).LegacyCount);
end;

procedure TRuleBaselineTests.UpdateCountsAddedRemovedUnchanged;
var
  Old: IRuleBaseline;
  Outcome: TBaselineUpdate;
begin
  Old := BaselineOf([Source('U.pas', TwoRoutines, [Finding('a', 5), Finding('b', 9)])]);
  Outcome := TRuleBaseline.Update(Old, [Source('U.pas', TwoRoutines, [Finding('a', 5), Finding('c', 9),
    Finding('c', 5)]), Source('V.pas', Original, nil)], nil);
  Assert.AreEqual(3, Outcome.Total);
  Assert.AreEqual(2, Outcome.Files);
  Assert.AreEqual(2, Outcome.Added);
  Assert.AreEqual(1, Outcome.Removed);
  Assert.AreEqual(1, Outcome.Unchanged);
  Assert.AreEqual<NativeInt>(0, Length(Outcome.Orphans));
  Assert.AreEqual(3, TRuleBaseline.FromJson(Outcome.Json).Count);
end;

procedure TRuleBaselineTests.UpdateReportsOrphansOfRenamedFile;
var
  Old: IRuleBaseline;
  Outcome: TBaselineUpdate;
begin
  Old := BaselineOf([Source('Src\U.pas', TwoRoutines, [Finding('a', 5)]),
    Source('Src\Alt.pas', TwoRoutines, [Finding('a', 5), Finding('b', 5)])]);
  // Alt.pas heißt jetzt Neu.pas: Die Einträge von Alt.pas haben keine Datei mehr.
  Outcome := TRuleBaseline.Update(Old, [Source('Src\U.pas', TwoRoutines, [Finding('a', 5)]),
    Source('Src\Neu.pas', TwoRoutines, [Finding('a', 5), Finding('b', 5)])],
    function(const APath: string): Boolean
    begin
      Result := False;
    end);
  Assert.AreEqual<NativeInt>(1, Length(Outcome.Orphans));
  Assert.AreEqual('Src/Alt.pas', Outcome.Orphans[0].Path);
  Assert.AreEqual(2, Outcome.Orphans[0].Count);
  Assert.AreEqual(2, Outcome.OrphanCount);
  Assert.AreEqual(2, Outcome.Removed);
  Assert.AreEqual(2, Outcome.Added);
  // Existiert die Datei noch (nur nicht geprüft), ist sie nicht verwaist.
  Outcome := TRuleBaseline.Update(Old, [Source('Src\U.pas', TwoRoutines, [Finding('a', 5)])],
    function(const APath: string): Boolean
    begin
      Result := True;
    end);
  Assert.AreEqual<NativeInt>(0, Length(Outcome.Orphans));
  Assert.AreEqual(2, Outcome.Removed);
end;

procedure TRuleBaselineTests.UpdateWithoutPreviousBaseline;
var
  Outcome: TBaselineUpdate;
begin
  Outcome := TRuleBaseline.Update(nil, [Source('U.pas', TwoRoutines, [Finding('a', 5), Finding('a', 9)])], nil);
  Assert.AreEqual(2, Outcome.Total);
  Assert.AreEqual(2, Outcome.Added);
  Assert.AreEqual(0, Outcome.Removed);
  Assert.AreEqual(0, Outcome.Unchanged);
end;

procedure TRuleBaselineTests.ClassifyMarksUnchangedAndAbsent;
var
  Baseline: IRuleBaseline;
  Marks: TArray<TBaselineMark>;
begin
  Baseline := BaselineOf([Source('U.pas', TwoRoutines, [Finding('a', 5), Finding('b', 9)])]);
  Marks := Baseline.Classify('U.pas', TwoRoutines, TFindingScopes.FromText(TwoRoutines),
    [Finding('a', 5), Finding('c', 9)]);
  Assert.AreEqual<NativeInt>(3, Length(Marks));
  Assert.IsTrue(Marks[0].State = TBaselineState.Unchanged);
  Assert.IsTrue(Marks[0].Match = TBaselineMatch.Exact);
  Assert.AreEqual('TFoo.A', Marks[0].Routine);
  Assert.IsTrue(Marks[1].State = TBaselineState.New);
  Assert.AreEqual('TFoo.B', Marks[1].Routine);
  Assert.IsTrue(Marks[2].State = TBaselineState.Absent);
  Assert.AreEqual('b', Marks[2].Finding.RuleId);
  Assert.AreEqual('TFoo.B', Marks[2].Routine);
  // Ganze Datei als nicht mehr gefunden.
  Assert.AreEqual<NativeInt>(2, Length(Baseline.AbsentOf('u.pas')));
  Assert.AreEqual(2, Baseline.CountOf('U.pas'));
  Assert.AreEqual<NativeInt>(1, Length(Baseline.Paths));
end;

procedure TRuleBaselineTests.BuildWritesRoutineAndContext;
var
  Json: string;
begin
  Json := TRuleBaseline.Build([Source('U.pas', TwoRoutines, [Finding('a', 5), Finding('a', 1)])]);
  Assert.IsTrue(Pos('"routine": "TFoo.A", "context": "' + TRuleBaseline.ContextFingerprint(TwoRoutines,
    TFindingScopes.FromText(TwoRoutines), 5) + '"', Json) > 0, Json);
  // Außerhalb einer Routine der Abschnitt.
  Assert.IsTrue(Pos('"routine": "interface"', Json) > 0, Json);
end;

procedure TRuleBaselineTests.ContextIgnoresIndentationAndRoutineName;
var
  Changed: string;
begin
  Changed := Swap(Swap(TwoRoutines, '  X.Free;', #9'X.Free;   '), 'procedure TFoo.A;', 'procedure TFoo.Neu;');
  Assert.AreEqual(TRuleBaseline.ContextFingerprint(TwoRoutines, TFindingScopes.FromText(TwoRoutines), 5),
    TRuleBaseline.ContextFingerprint(Changed, TFindingScopes.FromText(Changed), 5));
  Assert.AreNotEqual(TRuleBaseline.ContextFingerprint(TwoRoutines, TFindingScopes.FromText(TwoRoutines), 5),
    TRuleBaseline.ContextFingerprint(TwoRoutines, TFindingScopes.FromText(TwoRoutines), 9));
end;

procedure TRuleBaselineTests.CountersJsonListsOrphans;
var
  Outcome: TBaselineUpdate;
  Orphan: TBaselineOrphan;
begin
  Outcome := Default(TBaselineUpdate);
  Outcome.Total := 4;
  Outcome.Files := 2;
  Outcome.Added := 1;
  Outcome.Removed := 3;
  Outcome.Unchanged := 3;
  Orphan.Path := 'Alt/U.pas';
  Orphan.Count := 2;
  Outcome.Orphans := [Orphan];
  Assert.AreEqual('{"total": 4, "files": 2, "added": 1, "removed": 3, "unchanged": 3, "completed": 0, ' +
    '"orphaned": {"count": 2, "entries": [{"path": "Alt/U.pas", "count": 2}]}}', Outcome.CountersJson);
end;

procedure TRuleBaselineTests.SuppressionOfBaselineFindingIsNotUnused;
const
  Text =
    'unit U;' + #10 +
    'interface' + #10 +
    'implementation' + #10 +
    'procedure P;' + #10 +
    'begin' + #10 +
    '  Marker := 1; // lsp-ignore: marker' + #10 +
    '  Marker := 2;' + #10 +
    'end;' + #10 +
    'end.';
var
  Tree: TSyntaxTree;
  Context: TRuleContext;
  Findings: TArray<TRuleFinding>;
  Baseline: IRuleBaseline;
  Item: TRuleFinding;
  Rule: IRule;
begin
  // Beide Treffer stehen in der Baseline (z. B. erzeugt, bevor der Kommentar dazukam).
  Baseline := BaselineOf([Source('U.pas', Swap(Text, ' // lsp-ignore: marker', ''), [Finding('marker', 5),
    Finding('marker', 6)])]);
  Rule := TMarkerRule.Create;
  Tree := TPascalParser.Parse(Text);
  try
    Context := Default(TRuleContext);
    Context.RelativePath := 'U.pas';
    Context.UnitName := 'U';
    Context.Text := Text;
    Context.Tree := Tree;
    Findings := TRuleEngine.Run([Rule], TServerSettings.Default, Context);
  finally
    Tree.Free;
  end;
  // Die Engine unterdrückt vor der Baseline: Der Kommentar hat gewirkt und wird nicht gemeldet.
  Assert.AreEqual<NativeInt>(1, Length(Findings));
  for Item in Findings do
    Assert.AreNotEqual(UnusedSuppressionRuleId, Item.RuleId);
  // Der übrige Treffer steht in der Baseline (Zeile 6 hat ihren Fingerabdruck behalten).
  Findings := Baseline.Filter('U.pas', Text, Findings);
  Assert.AreEqual<NativeInt>(0, Length(Findings));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleBaselineTests);

end.
