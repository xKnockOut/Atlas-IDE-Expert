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
    /// <summary>Compilermeldungen (#530): ReplaceCompiler ersetzt je Datei, Regeln und andere Dateien bleiben.
    /// </summary>
    [Test]
    procedure ReplaceCompilerReplacesPerFile;
    /// <summary>Update (Regeln neu schreiben) behält Compilermeldungen, Classify meldet sie nie als Absent.
    /// </summary>
    [Test]
    procedure UpdateKeepsCompilerEntries;
    [Test]
    procedure RecognizesCompilerCodes;
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
  cOriginal = 'unit U;' + #10 + 'begin' + #10 + '  X := 1;' + #10 + 'end.';
  // Zeile 5 in TFoo.A, Zeile 9 in TFoo.B.
  cTwoRoutines =
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
  mToken: TPascalToken;
begin
  for mToken in AContext.Tree.Tokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, 'Marker') then
    begin
      AReport.Add(TTextRange.Create(mToken.StartPos, mToken.EndPos), 'Marker gefunden');
    end;
  end;
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
  mRaised: Boolean;
begin
  mRaised := False;
  try
    TRuleBaseline.FromJson(AJson);
  except
    on ERuleBaseline do
      mRaised := True;
  end;
  Assert.IsTrue(mRaised, AJson);
end;

{ TRuleBaselineTests }

procedure TRuleBaselineTests.HidesKnownFindings;
var
  mBaseline: IRuleBaseline;
begin
  mBaseline := BaselineOf([Source('Src\U.pas', cOriginal, [Finding('a', 2)])]);
  Assert.AreEqual(1, Integer(mBaseline.Count));
  Assert.AreEqual<NativeInt>(0, Length(mBaseline.Filter('Src\U.pas', cOriginal, [Finding('a', 2)])));
  // Andere Regel in derselben Zeile ist neu.
  Assert.AreEqual<NativeInt>(1, Length(mBaseline.Filter('Src\U.pas', cOriginal, [Finding('b', 2)])));
  // Andere Datei ebenso.
  Assert.AreEqual<NativeInt>(1, Length(mBaseline.Filter('Src\V.pas', cOriginal, [Finding('a', 2)])));
end;

procedure TRuleBaselineTests.SurvivesShiftedLines;
var
  mBaseline: IRuleBaseline;
  mShifted: string;
begin
  mBaseline := BaselineOf([Source('U.pas', cOriginal, [Finding('a', 2)])]);
  mShifted := 'unit U;' + #10 + '// neu' + #10 + '// neu' + #10 + 'begin' + #10 + '  X := 1;' + #10 + 'end.';
  Assert.AreEqual<NativeInt>(0, Length(mBaseline.Filter('U.pas', mShifted, [Finding('a', 4)])));
end;

procedure TRuleBaselineTests.ReportsChangedLine;
var
  mBaseline: IRuleBaseline;
begin
  mBaseline := BaselineOf([Source('U.pas', cOriginal, [Finding('a', 2)])]);
  Assert.AreEqual<NativeInt>(1, Length(mBaseline.Filter('U.pas', StringReplace(cOriginal, 'X := 1', 'X := 2', []),
    [Finding('a', 2)])));
end;

procedure TRuleBaselineTests.ReportsAdditionalIdenticalFinding;
var
  mBaseline: IRuleBaseline;
  mTwice: string;
  mRemaining: TArray<TRuleFinding>;
begin
  mBaseline := BaselineOf([Source('U.pas', cOriginal, [Finding('a', 2)])]);
  mTwice := 'unit U;' + #10 + 'begin' + #10 + '  X := 1;' + #10 + '  X := 1;' + #10 + 'end.';
  mRemaining := mBaseline.Filter('U.pas', mTwice, [Finding('a', 2), Finding('a', 3)]);
  Assert.AreEqual<NativeInt>(1, Length(mRemaining));
  Assert.AreEqual(3, mRemaining[0].Range.StartPos.Line);
end;

procedure TRuleBaselineTests.MatchesPathsWithEitherSeparator;
var
  mBaseline: IRuleBaseline;
begin
  mBaseline := BaselineOf([Source('Src\Sub\U.pas', cOriginal, [Finding('a', 2)])]);
  Assert.AreEqual<NativeInt>(0, Length(mBaseline.Filter('src/sub/u.pas', cOriginal, [Finding('A', 2)])));
end;

procedure TRuleBaselineTests.IgnoresIndentation;
var
  mBaseline: IRuleBaseline;
begin
  mBaseline := BaselineOf([Source('U.pas', cOriginal, [Finding('a', 2)])]);
  Assert.AreEqual<NativeInt>(0, Length(mBaseline.Filter('U.pas',
    StringReplace(cOriginal, '  X := 1;', #9'X  :=   1;'#13, []), [Finding('a', 2)])));
end;

procedure TRuleBaselineTests.BuildDropsVanishedFindings;
var
  mBaseline: IRuleBaseline;
begin
  // Neu geschrieben enthält die Baseline nur, was aktuell gefunden wird.
  mBaseline := BaselineOf([Source('U.pas', cOriginal, [Finding('a', 2)]), Source('V.pas', cOriginal, nil)]);
  Assert.AreEqual(1, Integer(mBaseline.Count));
  mBaseline := BaselineOf([Source('U.pas', cOriginal, nil)]);
  Assert.AreEqual(0, Integer(mBaseline.Count));
  Assert.AreEqual<NativeInt>(1, Length(mBaseline.Filter('U.pas', cOriginal, [Finding('a', 2)])));
end;

procedure TRuleBaselineTests.BuildIsSortedAndCounts;
var
  mJson: string;
begin
  mJson := TRuleBaseline.Build([Source('B.pas', cOriginal, [Finding('z', 2)]),
    Source('A.pas', cOriginal, [Finding('a', 2), Finding('a', 2)])]);
  Assert.IsTrue(Pos('"version": 1', mJson) > 0, mJson);
  Assert.IsTrue(Pos('"path": "A.pas"', mJson) < Pos('"path": "B.pas"', mJson), mJson);
  Assert.IsTrue(Pos('"rule": "a", "fingerprint": "' + TRuleBaseline.Fingerprint(cOriginal, Finding('a', 2)) +
    '", "count": 2', mJson) > 0, mJson);
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
  mBaseline: IRuleBaseline;
begin
  mBaseline := BaselineOf([Source('U.pas', cOriginal, [Finding('a', 2)])]);
  Assert.AreEqual<NativeInt>(0, Length(mBaseline.Filter('U.pas', cOriginal, [Finding('a', 2)])));
  Assert.AreEqual<NativeInt>(0, Length(mBaseline.Filter('U.pas', cOriginal, [Finding('a', 2)])));
end;

procedure TRuleBaselineTests.SameLineInOtherRoutineIsNew;
var
  mBaseline: IRuleBaseline;
  mText: string;
  mRemaining: TArray<TRuleFinding>;
begin
  // Beide Routinen enthalten X.Free; in der Baseline steht nur der Treffer in TFoo.A.
  mText := Swap(cTwoRoutines, '  Y := 1;', '  X.Free;');
  mBaseline := BaselineOf([Source('U.pas', mText, [Finding('a', 5)])]);
  mRemaining := mBaseline.Filter('U.pas', mText, [Finding('a', 5), Finding('a', 9)]);
  Assert.AreEqual<NativeInt>(1, Length(mRemaining));
  Assert.AreEqual(9, mRemaining[0].Range.StartPos.Line);
  // Steht nur TFoo.B in der Baseline, bleibt TFoo.A gemeldet.
  mBaseline := BaselineOf([Source('U.pas', mText, [Finding('a', 9)])]);
  mRemaining := mBaseline.Filter('U.pas', mText, [Finding('a', 5), Finding('a', 9)]);
  Assert.AreEqual<NativeInt>(1, Length(mRemaining));
  Assert.AreEqual(5, mRemaining[0].Range.StartPos.Line);
end;

procedure TRuleBaselineTests.MovedToOtherRoutineIsReported;
var
  mBaseline: IRuleBaseline;
  mMoved: string;
begin
  mBaseline := BaselineOf([Source('U.pas', cTwoRoutines, [Finding('a', 5)])]);
  // X.Free wandert von TFoo.A nach TFoo.B; TFoo.A gibt es weiter.
  mMoved := Swap(Swap(cTwoRoutines, '  X.Free;', '  Z := 2;'), '  Y := 1;', '  X.Free;');
  Assert.AreEqual<NativeInt>(1, Length(mBaseline.Filter('U.pas', mMoved, [Finding('a', 9)])));
end;

procedure TRuleBaselineTests.RenamedRoutineKeepsEntry;
var
  mBaseline: IRuleBaseline;
  mRenamed: string;
  mMarks: TArray<TBaselineMark>;
begin
  mBaseline := BaselineOf([Source('U.pas', cTwoRoutines, [Finding('a', 5)])]);
  mRenamed := Swap(cTwoRoutines, 'procedure TFoo.A;', 'procedure TFoo.Umbenannt;');
  mMarks := mBaseline.Classify('U.pas', mRenamed, TFindingScopes.FromText(mRenamed), [Finding('a', 5)]);
  Assert.AreEqual<NativeInt>(1, Length(mMarks));
  Assert.AreEqual<TBaselineState>(TBaselineState.Unchanged, mMarks[0].State);
  Assert.AreEqual<TBaselineMatch>(TBaselineMatch.Renamed, mMarks[0].Match);
  Assert.AreEqual('TFoo.Umbenannt', mMarks[0].Routine);
  // Anderer Code in der umbenannten Routine bleibt neu.
  mRenamed := Swap(mRenamed, '  X.Free;', '  W.Free;');
  Assert.AreEqual<NativeInt>(1, Length(mBaseline.Filter('U.pas', mRenamed, [Finding('a', 5)])));
end;

procedure TRuleBaselineTests.LegacyEntryWithoutRoutineStillHides;
var
  mBaseline: IRuleBaseline;
  mText: string;
begin
  mText := Swap(cTwoRoutines, '  Y := 1;', '  X.Free;');
  // Datei vor #97: ohne "routine" und "context".
  mBaseline := TRuleBaseline.FromJson('{"version": 1, "findings": [{"path": "U.pas", "rule": "a", "fingerprint": "' +
    TRuleBaseline.Fingerprint(mText, Finding('a', 5)) + '", "count": 1}]}');
  Assert.AreEqual(1, mBaseline.LegacyCount);
  Assert.AreEqual<NativeInt>(0, Length(mBaseline.Filter('U.pas', mText, [Finding('a', 5)])));
  // Wie bisher gilt der Eintrag für jede Routine, aber nur einmal.
  Assert.AreEqual<NativeInt>(0, Length(mBaseline.Filter('U.pas', mText, [Finding('a', 9)])));
  Assert.AreEqual<NativeInt>(1, Length(mBaseline.Filter('U.pas', mText, [Finding('a', 5), Finding('a', 9)])));
end;

procedure TRuleBaselineTests.UpdateCompletesLegacyEntries;
var
  mOld: IRuleBaseline;
  mOutcome: TBaselineUpdate;
begin
  mOld := TRuleBaseline.FromJson('{"version": 1, "findings": [{"path": "U.pas", "rule": "a", "fingerprint": "' +
    TRuleBaseline.Fingerprint(cTwoRoutines, Finding('a', 5)) + '"}]}');
  mOutcome := TRuleBaseline.Update(mOld, [Source('U.pas', cTwoRoutines, [Finding('a', 5)])], nil);
  Assert.AreEqual(1, mOutcome.Unchanged);
  Assert.AreEqual(1, mOutcome.Completed);
  Assert.AreEqual(0, mOutcome.Added);
  Assert.AreEqual(0, mOutcome.Removed);
  Assert.IsTrue(Pos('"routine": "TFoo.A"', mOutcome.Json) > 0, mOutcome.Json);
  Assert.AreEqual(0, TRuleBaseline.FromJson(mOutcome.Json).LegacyCount);
end;

procedure TRuleBaselineTests.UpdateCountsAddedRemovedUnchanged;
var
  mOld: IRuleBaseline;
  mOutcome: TBaselineUpdate;
begin
  mOld := BaselineOf([Source('U.pas', cTwoRoutines, [Finding('a', 5), Finding('b', 9)])]);
  mOutcome := TRuleBaseline.Update(mOld, [Source('U.pas', cTwoRoutines, [Finding('a', 5), Finding('c', 9),
    Finding('c', 5)]), Source('V.pas', cOriginal, nil)], nil);
  Assert.AreEqual(3, mOutcome.Total);
  Assert.AreEqual(2, mOutcome.Files);
  Assert.AreEqual(2, mOutcome.Added);
  Assert.AreEqual(1, mOutcome.Removed);
  Assert.AreEqual(1, mOutcome.Unchanged);
  Assert.AreEqual<NativeInt>(0, Length(mOutcome.Orphans));
  Assert.AreEqual(3, Integer(TRuleBaseline.FromJson(mOutcome.Json).Count));
end;

procedure TRuleBaselineTests.UpdateReportsOrphansOfRenamedFile;
var
  mOld: IRuleBaseline;
  mOutcome: TBaselineUpdate;
begin
  mOld := BaselineOf([Source('Src\U.pas', cTwoRoutines, [Finding('a', 5)]),
    Source('Src\Alt.pas', cTwoRoutines, [Finding('a', 5), Finding('b', 5)])]);
  // Alt.pas heißt jetzt Neu.pas: Die Einträge von Alt.pas haben keine Datei mehr.
  mOutcome := TRuleBaseline.Update(mOld, [Source('Src\U.pas', cTwoRoutines, [Finding('a', 5)]),
    Source('Src\Neu.pas', cTwoRoutines, [Finding('a', 5), Finding('b', 5)])],
    function(const APath: string): Boolean
    begin
      Result := False;
    end);
  Assert.AreEqual<NativeInt>(1, Length(mOutcome.Orphans));
  Assert.AreEqual('Src/Alt.pas', mOutcome.Orphans[0].Path);
  Assert.AreEqual(2, Integer(mOutcome.Orphans[0].Count));
  Assert.AreEqual(2, mOutcome.OrphanCount);
  Assert.AreEqual(2, mOutcome.Removed);
  Assert.AreEqual(2, mOutcome.Added);
  // Existiert die Datei noch (nur nicht geprüft), ist sie nicht verwaist.
  mOutcome := TRuleBaseline.Update(mOld, [Source('Src\U.pas', cTwoRoutines, [Finding('a', 5)])],
    function(const APath: string): Boolean
    begin
      Result := True;
    end);
  Assert.AreEqual<NativeInt>(0, Length(mOutcome.Orphans));
  Assert.AreEqual(2, mOutcome.Removed);
end;

procedure TRuleBaselineTests.UpdateWithoutPreviousBaseline;
var
  mOutcome: TBaselineUpdate;
begin
  mOutcome := TRuleBaseline.Update(nil, [Source('U.pas', cTwoRoutines, [Finding('a', 5), Finding('a', 9)])], nil);
  Assert.AreEqual(2, mOutcome.Total);
  Assert.AreEqual(2, mOutcome.Added);
  Assert.AreEqual(0, mOutcome.Removed);
  Assert.AreEqual(0, mOutcome.Unchanged);
end;

procedure TRuleBaselineTests.ClassifyMarksUnchangedAndAbsent;
var
  mBaseline: IRuleBaseline;
  mMarks: TArray<TBaselineMark>;
begin
  mBaseline := BaselineOf([Source('U.pas', cTwoRoutines, [Finding('a', 5), Finding('b', 9)])]);
  mMarks := mBaseline.Classify('U.pas', cTwoRoutines, TFindingScopes.FromText(cTwoRoutines),
    [Finding('a', 5), Finding('c', 9)]);
  Assert.AreEqual<NativeInt>(3, Length(mMarks));
  Assert.AreEqual<TBaselineState>(TBaselineState.Unchanged, mMarks[0].State);
  Assert.AreEqual<TBaselineMatch>(TBaselineMatch.Exact, mMarks[0].Match);
  Assert.AreEqual('TFoo.A', mMarks[0].Routine);
  Assert.AreEqual<TBaselineState>(TBaselineState.New, mMarks[1].State);
  Assert.AreEqual('TFoo.B', mMarks[1].Routine);
  Assert.AreEqual<TBaselineState>(TBaselineState.Absent, mMarks[2].State);
  Assert.AreEqual('b', mMarks[2].Finding.RuleId);
  Assert.AreEqual('TFoo.B', mMarks[2].Routine);
  // Ganze Datei als nicht mehr gefunden.
  Assert.AreEqual<NativeInt>(2, Length(mBaseline.AbsentOf('u.pas')));
  Assert.AreEqual(2, mBaseline.CountOf('U.pas'));
  Assert.AreEqual<NativeInt>(1, Length(mBaseline.Paths));
end;

procedure TRuleBaselineTests.BuildWritesRoutineAndContext;
var
  mJson: string;
begin
  mJson := TRuleBaseline.Build([Source('U.pas', cTwoRoutines, [Finding('a', 5), Finding('a', 1)])]);
  Assert.IsTrue(Pos('"routine": "TFoo.A", "context": "' + TRuleBaseline.ContextFingerprint(cTwoRoutines,
    TFindingScopes.FromText(cTwoRoutines), 5) + '"', mJson) > 0, mJson);
  // Außerhalb einer Routine der Abschnitt.
  Assert.IsTrue(Pos('"routine": "interface"', mJson) > 0, mJson);
end;

procedure TRuleBaselineTests.ContextIgnoresIndentationAndRoutineName;
var
  mChanged: string;
begin
  mChanged := Swap(Swap(cTwoRoutines, '  X.Free;', #9'X.Free;   '), 'procedure TFoo.A;', 'procedure TFoo.Neu;');
  Assert.AreEqual(TRuleBaseline.ContextFingerprint(cTwoRoutines, TFindingScopes.FromText(cTwoRoutines), 5),
    TRuleBaseline.ContextFingerprint(mChanged, TFindingScopes.FromText(mChanged), 5));
  Assert.AreNotEqual(TRuleBaseline.ContextFingerprint(cTwoRoutines, TFindingScopes.FromText(cTwoRoutines), 5),
    TRuleBaseline.ContextFingerprint(cTwoRoutines, TFindingScopes.FromText(cTwoRoutines), 9));
end;

procedure TRuleBaselineTests.CountersJsonListsOrphans;
var
  mOutcome: TBaselineUpdate;
  mOrphan: TBaselineOrphan;
begin
  mOutcome := Default(TBaselineUpdate);
  mOutcome.Total := 4;
  mOutcome.Files := 2;
  mOutcome.Added := 1;
  mOutcome.Removed := 3;
  mOutcome.Unchanged := 3;
  mOrphan.Path := 'Alt/U.pas';
  mOrphan.Count := 2;
  mOutcome.Orphans := [mOrphan];
  Assert.AreEqual('{"total": 4, "files": 2, "added": 1, "removed": 3, "unchanged": 3, "completed": 0, ' +
    '"compiler": 0, "orphaned": {"count": 2, "entries": [{"path": "Alt/U.pas", "count": 2}]}}', mOutcome.CountersJson);
end;

procedure TRuleBaselineTests.ReplaceCompilerReplacesPerFile;
var
  mOld, mNext: IRuleBaseline;
  mOutcome: TBaselineUpdate;
begin
  mOld := BaselineOf([Source('U.pas', cTwoRoutines, [Finding('a', 5)])]);
  mOutcome := TRuleBaseline.ReplaceCompiler(mOld, [Source('U.pas', cTwoRoutines, [Finding('w1035', 5)]),
    Source('V.pas', cTwoRoutines, [Finding('h2164', 9)])]);
  Assert.AreEqual(2, mOutcome.Total);
  Assert.AreEqual(2, mOutcome.Added);
  mOld := TRuleBaseline.FromJson(mOutcome.Json);
  Assert.AreEqual(3, mOld.Count, 'Regeltreffer bleibt');
  // Neuer Build von U.pas: W1035 ist weg, H2164 neu; V.pas wurde nicht übersetzt und bleibt.
  mOutcome := TRuleBaseline.ReplaceCompiler(mOld, [Source('U.pas', cTwoRoutines, [Finding('h2164', 9)])]);
  Assert.AreEqual(2, mOutcome.Total, 'U: H2164, V: H2164');
  Assert.AreEqual(1, mOutcome.Added);
  Assert.AreEqual(1, mOutcome.Removed);
  Assert.AreEqual(0, mOutcome.Unchanged);
  mNext := TRuleBaseline.FromJson(mOutcome.Json);
  Assert.AreEqual(3, mNext.Count);
  Assert.AreEqual<NativeInt>(0, Length(mNext.Filter('U.pas', cTwoRoutines, [Finding('a', 5), Finding('h2164', 9)])),
    'Regel und Compilermeldung bekannt');
  Assert.AreEqual<NativeInt>(1, Length(mNext.Filter('U.pas', cTwoRoutines, [Finding('w1035', 5)])), 'W1035 wieder neu');
  // Gleiche Meldung noch einmal: unverändert.
  mOutcome := TRuleBaseline.ReplaceCompiler(mNext, [Source('U.pas', cTwoRoutines, [Finding('h2164', 9)])]);
  Assert.AreEqual(1, mOutcome.Unchanged);
  Assert.AreEqual(0, mOutcome.Added);
  Assert.AreEqual(0, mOutcome.Removed);
end;

procedure TRuleBaselineTests.UpdateKeepsCompilerEntries;
var
  mOld: IRuleBaseline;
  mOutcome: TBaselineUpdate;
  mMark: TBaselineMark;
begin
  mOld := TRuleBaseline.FromJson(TRuleBaseline.ReplaceCompiler(BaselineOf([Source('U.pas', cTwoRoutines,
    [Finding('a', 5)])]), [Source('U.pas', cTwoRoutines, [Finding('w1035', 5)]), Source('Alt.pas', cTwoRoutines,
    [Finding('h2164', 9)])]).Json);
  for mMark in mOld.Classify('U.pas', cTwoRoutines, TFindingScopes.FromText(cTwoRoutines), [Finding('a', 5)]) do
  begin
    Assert.AreNotEqual<TBaselineState>(TBaselineState.Absent,
      mMark.State, 'Compilermeldung ist für die Regeln nicht verschwunden');
  end;
  Assert.AreEqual<NativeInt>(0, Length(mOld.AbsentOf('Alt.pas')));
  // Alt.pas gibt es nicht mehr: dessen Compilermeldung fällt heraus, die von U.pas bleibt.
  mOutcome := TRuleBaseline.Update(mOld, [Source('U.pas', cTwoRoutines, [Finding('a', 5)])],
    function(const APath: string): Boolean
    begin
      Result := SameText(APath, 'U.pas');
    end);
  Assert.AreEqual(1, mOutcome.Total);
  Assert.AreEqual(1, mOutcome.Unchanged);
  Assert.AreEqual(1, mOutcome.Compiler);
  Assert.AreEqual(1, mOutcome.Removed, 'nur die Meldung der verschwundenen Datei');
  Assert.AreEqual(1, mOutcome.OrphanCount);
  mOld := TRuleBaseline.FromJson(mOutcome.Json);
  Assert.AreEqual(2, mOld.Count);
  Assert.AreEqual<NativeInt>(0, Length(mOld.Filter('U.pas', cTwoRoutines, [Finding('w1035', 5)])));
end;

procedure TRuleBaselineTests.RecognizesCompilerCodes;
begin
  Assert.IsTrue(TRuleBaseline.IsCompilerCode('W1035'));
  Assert.IsTrue(TRuleBaseline.IsCompilerCode('h2164'));
  Assert.IsTrue(TRuleBaseline.IsCompilerCode('E2003'));
  Assert.IsFalse(TRuleBaseline.IsCompilerCode('empty-except'));
  Assert.IsFalse(TRuleBaseline.IsCompilerCode('W103'));
  Assert.IsFalse(TRuleBaseline.IsCompilerCode('X1035'));
end;

procedure TRuleBaselineTests.SuppressionOfBaselineFindingIsNotUnused;
const
  cText =
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
  mTree: TSyntaxTree;
  mContext: TRuleContext;
  mFindings: TArray<TRuleFinding>;
  mBaseline: IRuleBaseline;
  mItem: TRuleFinding;
  mRule: IRule;
begin
  // Beide Treffer stehen in der Baseline (z. B. erzeugt, bevor der Kommentar dazukam).
  mBaseline := BaselineOf([Source('U.pas', Swap(cText, ' // lsp-ignore: marker', ''), [Finding('marker', 5),
    Finding('marker', 6)])]);
  mRule := TMarkerRule.Create;
  mTree := TPascalParser.Parse(cText);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := 'U.pas';
    mContext.UnitName := 'U';
    mContext.Text := cText;
    mContext.Tree := mTree;
    mFindings := TRuleEngine.Run([mRule], TServerSettings.Default, mContext);
  finally
    mTree.Free;
  end;
  // Die Engine unterdrückt vor der Baseline: Der Kommentar hat gewirkt und wird nicht gemeldet.
  Assert.AreEqual<NativeInt>(1, Length(mFindings));
  for mItem in mFindings do
  begin
    Assert.AreNotEqual(cUnusedSuppressionRuleId, mItem.RuleId);
  end;
  // Der übrige Treffer steht in der Baseline (Zeile 6 hat ihren Fingerabdruck behalten).
  mFindings := mBaseline.Filter('U.pas', cText, mFindings);
  Assert.AreEqual<NativeInt>(0, Length(mFindings));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleBaselineTests);

end.
