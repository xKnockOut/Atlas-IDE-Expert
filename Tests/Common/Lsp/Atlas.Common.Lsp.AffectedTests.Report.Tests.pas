unit Atlas.Common.Lsp.AffectedTests.Report.Tests;

// Ausgabe der betroffenen Tests ohne Bestimmung: Format lesen, Bericht, JSON hin und zurück, --run-Argument;
// dazu Namen und Gründe der Typen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAffectedReportTests = class
  public
    [Test]
    procedure ParsesFormats;
    [Test]
    procedure ReasonTextAndRunNames;
    [Test]
    procedure TextNamesTestsAndReasons;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure RunArgumentOnlyForSomeTests;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.AffectedTests.Contract,
  Atlas.Common.Lsp.AffectedTests.Report;

function Sample: TAffectedResult;
var
  mTest: TAffectedTest;
  mReason: TAffectedReason;
begin
  Result := Default(TAffectedResult);
  Result.Base := 'HEAD';
  Result.Depth := 2;
  mReason := Default(TAffectedReason);
  mReason.Change := 'TBasis.Rechne';
  mReason.Path := TArray<string>.Create('TBasis.Rechne', 'TBasisTests.Rechnet');
  mReason.Inferred := True;
  mTest := Default(TAffectedTest);
  mTest.Name := 'BasisTests.TBasisTests.Rechnet';
  mTest.UnitName := 'BasisTests';
  mTest.Fixture := 'TBasisTests';
  mTest.Method := 'Rechnet';
  mTest.RunNames := TArray<string>.Create('BasisTests.TBasisTests.Rechnet');
  mTest.Line := 7;
  mTest.Reasons := [mReason];
  Result.Tests := [mTest, mTest];
end;

procedure TAffectedReportTests.ParsesFormats;
var
  mFormat: TAffectedFormat;
begin
  Assert.IsTrue(TAffectedReport.TryParseFormat('', mFormat));
  Assert.IsTrue(mFormat = TAffectedFormat.Text);
  Assert.IsTrue(TAffectedReport.TryParseFormat('Json', mFormat));
  Assert.IsTrue(mFormat = TAffectedFormat.Json);
  Assert.IsFalse(TAffectedReport.TryParseFormat('csv', mFormat));
end;

procedure TAffectedReportTests.ReasonTextAndRunNames;
var
  mResult: TAffectedResult;
begin
  mResult := Sample;
  Assert.AreEqual('TBasis.Rechne' + cAffectedArrow + 'TBasisTests.Rechnet',
    mResult.Tests[0].Reasons[0].Text.Substring(0, Length('TBasis.Rechne' + cAffectedArrow + 'TBasisTests.Rechnet')));
  Assert.IsTrue(mResult.Tests[0].Reasons[0].Text.Length > Length('TBasis.Rechne' + cAffectedArrow +
    'TBasisTests.Rechnet'), 'erschlossen wird vermerkt');
  Assert.AreEqual(1, Integer(Length(mResult.RunNames)), 'ohne Doppelte');
end;

procedure TAffectedReportTests.TextNamesTestsAndReasons;
var
  mText: string;
begin
  mText := TAffectedReport.ToText(Sample);
  Assert.IsTrue(mText.Contains('  BasisTests.TBasisTests.Rechnet'));
  Assert.IsTrue(mText.Contains('    ← TBasis.Rechne'));
  Assert.IsTrue(mText.Contains('run_tests tests: BasisTests.TBasisTests.Rechnet'));
end;

procedure TAffectedReportTests.JsonRoundTrip;
var
  mJson: TJSONObject;
  mBack: TAffectedResult;
begin
  mJson := TAffectedReport.ToJson(Sample);
  try
    mBack := TAffectedReport.FromJson(mJson);
  finally
    mJson.Free;
  end;
  Assert.AreEqual('HEAD', mBack.Base);
  Assert.AreEqual(2, mBack.Depth);
  Assert.AreEqual(2, Integer(Length(mBack.Tests)));
  Assert.AreEqual('Rechnet', mBack.Tests[0].Method);
  Assert.AreEqual(7, mBack.Tests[0].Line);
  Assert.IsTrue(mBack.Tests[0].Reasons[0].Inferred);
  Assert.AreEqual(2, Integer(Length(mBack.Tests[0].Reasons[0].Path)));
end;

procedure TAffectedReportTests.RunArgumentOnlyForSomeTests;
var
  mResult: TAffectedResult;
  mArgument: string;
begin
  mResult := Sample;
  Assert.IsTrue(TAffectedReport.DUnitXArgument(mResult, mArgument));
  Assert.AreEqual('--run:BasisTests.TBasisTests.Rechnet', mArgument);
  Assert.AreEqual(mArgument, TAffectedReport.Render(mResult, TAffectedFormat.DUnitX));
  mResult.All := True;
  Assert.IsTrue(TAffectedReport.DUnitXArgument(mResult, mArgument));
  Assert.AreEqual('', mArgument, 'alle Tests: ohne Argument');
end;

initialization
  TDUnitX.RegisterTestFixture(TAffectedReportTests);

end.
