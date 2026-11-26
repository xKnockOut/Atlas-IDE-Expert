unit Atlas.Common.Formatting.Outcome.Tests;

// Tests für die gemeinsamen Typen des Formatierens ohne Editor (#1358): Bereiche, Kennungen der Abweichungen und
// „geändert“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormatOutcomeTests = class
  public
    [Test]
    procedure ScopeAllCoversWholeFile;
    [Test]
    procedure ScopeLinesKeepsSpans;
    [Test]
    procedure KindNamesForJson;
    [Test]
    procedure ChangedComparesTexts;
  end;

implementation

uses
  Atlas.Common.Formatting.Outcome;

{ TFormatOutcomeTests }

procedure TFormatOutcomeTests.ScopeAllCoversWholeFile;
var
  mScope: TFormatScope;
begin
  mScope := TFormatScope.All;
  Assert.IsTrue(mScope.WholeFile);
  Assert.AreEqual(0, Integer(Length(mScope.Spans)));
end;

procedure TFormatOutcomeTests.ScopeLinesKeepsSpans;
var
  mScope: TFormatScope;
begin
  mScope := TFormatScope.Lines([TFormatLineSpan.Create(2, 4), TFormatLineSpan.Create(9, 9)]);
  Assert.IsFalse(mScope.WholeFile);
  Assert.AreEqual(2, Integer(Length(mScope.Spans)));
  Assert.AreEqual(2, mScope.Spans[0].First);
  Assert.AreEqual(4, mScope.Spans[0].Last);
  Assert.AreEqual(9, mScope.Spans[1].First);
  mScope.Spans := nil;
end;

procedure TFormatOutcomeTests.KindNamesForJson;
begin
  Assert.AreEqual('indent', TFormatDeviation.KindName(TFormatDeviationKind.Indent));
  Assert.AreEqual('spaceAroundAssignment', TFormatDeviation.KindName(TFormatDeviationKind.SpaceAssignment));
  Assert.AreEqual('endOfLine', TFormatDeviation.KindName(TFormatDeviationKind.EndOfLine));
  Assert.AreEqual('finalNewline', TFormatDeviation.KindName(TFormatDeviationKind.FinalNewline));
end;

procedure TFormatOutcomeTests.ChangedComparesTexts;
var
  mOutcome: TFormatOutcome;
begin
  mOutcome := Default(TFormatOutcome);
  mOutcome.Original := 'a := 1;';
  mOutcome.Formatted := mOutcome.Original;
  Assert.IsFalse(mOutcome.Changed);
  mOutcome.Formatted := 'a := 2;';
  Assert.IsTrue(mOutcome.Changed);
  mOutcome := Default(TFormatOutcome);
end;

initialization
  TDUnitX.RegisterTestFixture(TFormatOutcomeTests);

end.
