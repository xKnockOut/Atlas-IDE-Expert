unit Atlas.Core.Debug.StepFilterEdit.Tests;

// Tests für die Entscheidungen des Schrittfilters außerhalb von Urteil und Ablauf (#850, #1967): Art des Schritts,
// Halt des Laufs, Haltepunkt an der neuen Routine, Routine überspringen bzw. nicht mehr überspringen; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasStepFilterEditTests = class
  public
    [Test]
    procedure TraceKinds;
    [Test]
    procedure OnlyNextStopBelongsToRun;
    [Test]
    procedure BreakpointMatchesFileOrResolved;
    [Test]
    procedure SkipAddsPatternOnce;
    [Test]
    procedure UnskipRemovesPattern;
    [Test]
    procedure UnskipNamesWhatStillFilters;
  end;

implementation

uses
  Atlas.Text.StepFilter,
  Atlas.Core.Debug.StepFilter,
  Atlas.Core.Debug.StepFilterEdit;

const
  cName = 'Kunden.TKunde.GetName';

function Routine(AKinds: TStepFilterKinds): TAtlasStepRoutine;
begin
  Result := Default(TAtlasStepRoutine);
  Result.Found := True;
  Result.Name := cName;
  Result.Kinds := AKinds;
end;

function Options(AKinds: TStepFilterKinds; const APatterns: TArray<string>): TAtlasStepFilterOptions;
begin
  Result := Default(TAtlasStepFilterOptions);
  Result.Enabled := True;
  Result.Kinds := AKinds;
  Result.Patterns := APatterns;
end;

{ TAtlasStepFilterEditTests }

procedure TAtlasStepFilterEditTests.TraceKinds;
begin
  Assert.AreEqual<TAtlasStepTrace>(TAtlasStepTrace.Bypass, TAtlasStepFilterEdit.Trace(True, False, True));
  Assert.AreEqual<TAtlasStepTrace>(TAtlasStepTrace.Bypass, TAtlasStepFilterEdit.Trace(False, True, False));
  Assert.AreEqual<TAtlasStepTrace>(TAtlasStepTrace.OwnStep, TAtlasStepFilterEdit.Trace(False, False, True));
  Assert.AreEqual<TAtlasStepTrace>(TAtlasStepTrace.UserStep, TAtlasStepFilterEdit.Trace(False, False, False));
end;

procedure TAtlasStepFilterEditTests.OnlyNextStopBelongsToRun;
begin
  Assert.IsTrue(TAtlasStepFilterEdit.BelongsToRun(8, 7));
  Assert.IsFalse(TAtlasStepFilterEdit.BelongsToRun(9, 7));
  Assert.IsFalse(TAtlasStepFilterEdit.BelongsToRun(7, 7));
end;

procedure TAtlasStepFilterEditTests.BreakpointMatchesFileOrResolved;
var
  mBreakpoints: TArray<TAtlasStepBreakpoint>;
begin
  mBreakpoints := [TAtlasStepBreakpoint.Create('Kunden.pas', 12, True),
    TAtlasStepBreakpoint.Create('C:\P\Lager.pas', 30, False)];
  // Zeile 0-basiert, Haltepunkte 1-basiert.
  Assert.IsTrue(TAtlasStepFilterEdit.BreakpointAt(mBreakpoints, 'KUNDEN.PAS', 'C:\P\Kunden.pas', 11));
  Assert.IsTrue(TAtlasStepFilterEdit.BreakpointAt(mBreakpoints, 'X.pas', 'kunden.pas', 11));
  Assert.IsFalse(TAtlasStepFilterEdit.BreakpointAt(mBreakpoints, 'Kunden.pas', '', 12));
  // Ausgeschaltet zählt nicht.
  Assert.IsFalse(TAtlasStepFilterEdit.BreakpointAt(mBreakpoints, 'Lager.pas', 'C:\P\Lager.pas', 29));
end;

procedure TAtlasStepFilterEditTests.SkipAddsPatternOnce;
var
  mEdit: TAtlasStepSkipEdit;
begin
  mEdit := TAtlasStepFilterEdit.Skip(Options([], nil), Routine([]));
  Assert.AreEqual<TAtlasStepSkipOutcome>(TAtlasStepSkipOutcome.Added, mEdit.Outcome);
  Assert.IsTrue(mEdit.Changed);
  Assert.AreEqual(1, Integer(Length(mEdit.Patterns)));
  Assert.AreEqual(cName, mEdit.Patterns[0]);
  mEdit := TAtlasStepFilterEdit.Skip(Options([TStepFilterKind.Getters], nil), Routine([TStepFilterKind.Getters]));
  Assert.AreEqual<TAtlasStepSkipOutcome>(TAtlasStepSkipOutcome.Already, mEdit.Outcome);
  Assert.IsFalse(mEdit.Changed);
  Assert.AreEqual<TAtlasStepVerdictKind>(TAtlasStepVerdictKind.Kind, mEdit.Verdict.Kind);
end;

procedure TAtlasStepFilterEditTests.UnskipRemovesPattern;
var
  mEdit: TAtlasStepUnskipEdit;
begin
  mEdit := TAtlasStepFilterEdit.Unskip(Options([], [cName, 'Lager.*']), Routine([]));
  Assert.AreEqual<TAtlasStepUnskipOutcome>(TAtlasStepUnskipOutcome.Removed, mEdit.Outcome);
  Assert.IsTrue(mEdit.Changed);
  Assert.AreEqual(1, Integer(Length(mEdit.Patterns)));
  Assert.AreEqual('Lager.*', mEdit.Patterns[0]);
  mEdit := TAtlasStepFilterEdit.Unskip(Options([], nil), Routine([]));
  Assert.AreEqual<TAtlasStepUnskipOutcome>(TAtlasStepUnskipOutcome.NotSkipped, mEdit.Outcome);
  Assert.IsFalse(mEdit.Changed);
end;

procedure TAtlasStepFilterEditTests.UnskipNamesWhatStillFilters;
var
  mEdit: TAtlasStepUnskipEdit;
begin
  mEdit := TAtlasStepFilterEdit.Unskip(Options([], [cName, 'Kunden.*']), Routine([]));
  Assert.AreEqual<TAtlasStepUnskipOutcome>(TAtlasStepUnskipOutcome.StillByPattern, mEdit.Outcome);
  Assert.AreEqual('Kunden.*', mEdit.Verdict.Pattern);
  mEdit := TAtlasStepFilterEdit.Unskip(Options([TStepFilterKind.Getters], [cName]),
    Routine([TStepFilterKind.Getters]));
  Assert.AreEqual<TAtlasStepUnskipOutcome>(TAtlasStepUnskipOutcome.StillByKind, mEdit.Outcome);
  Assert.IsTrue(mEdit.Changed);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStepFilterEditTests);

end.
