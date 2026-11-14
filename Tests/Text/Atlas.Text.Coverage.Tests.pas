unit Atlas.Text.Coverage.Tests;

// Tests des Lesens der Testabdeckung (#275): CodeCoverage_Summary.xml mit
// linehits, jacoco.xml, doppelte Dateien, Bericht ohne Zeilen, kein Bericht,
// Zeilen nachschlagen und Dateien zum Pfad finden.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoverageTests = class
  public
    [Test]
    procedure ReadsLineHits;
    [Test]
    procedure MergesRepeatedFiles;
    [Test]
    procedure ReadsJaCoCo;
    [Test]
    procedure SummaryWithoutLines;
    [Test]
    procedure NotAReport;
    [Test]
    procedure ParsesLineHitText;
    [Test]
    procedure FindsFileForPath;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Coverage;

const
  cSummary =
    '<?xml version="1.0" encoding="UTF-8"?>'#13#10 +
    '<report>'#13#10 +
    '  <stats><packages value="1"/><totallines value="5"/></stats>'#13#10 +
    '  <data>'#13#10 +
    '    <all name="all classes"><package name="Rechner"/></all>'#13#10 +
    '    <linehits>'#13#10 +
    '      <file name="Rechner.pas">12=3;13=0;15=1</file>'#13#10 +
    '      <file name="Hilfen.pas">7=0</file>'#13#10 +
    '    </linehits>'#13#10 +
    '  </data>'#13#10 +
    '</report>';

  cJaCoCo =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'#13#10 +
    '<!DOCTYPE report PUBLIC "-//JACOCO//DTD Report 1.0//EN" "report.dtd">'#13#10 +
    '<report name="debug">'#13#10 +
    '  <sessioninfo id="x" start="1" dump="1"/>'#13#10 +
    '  <package name="Rechner/Tests">'#13#10 +
    '    <class name="TRechner"><method name="Summe" line="12"/></class>'#13#10 +
    '    <sourcefile name="Rechner.pas">'#13#10 +
    '      <line nr="13" mi="1" ci="0" mb="0" cb="0"/>'#13#10 +
    '      <line nr="12" mi="0" ci="1" mb="0" cb="0"/>'#13#10 +
    '      <counter type="LINE" missed="1" covered="1"/>'#13#10 +
    '    </sourcefile>'#13#10 +
    '  </package>'#13#10 +
    '</report>';

{ TCoverageTests }

procedure TCoverageTests.ReadsLineHits;
var
  mReport: TCoverageReport;
begin
  mReport := TCoverage.Parse(cSummary);
  Assert.IsTrue(mReport.Valid);
  Assert.AreEqual<TCoverageFormat>(TCoverageFormat.DelphiCodeCoverage, mReport.Format);
  Assert.AreEqual(2, Integer(Length(mReport.Files)));
  Assert.AreEqual('Rechner.pas', mReport.Files[0].Name);
  Assert.AreEqual(3, mReport.Files[0].LineCount);
  Assert.AreEqual(2, mReport.Files[0].CoveredCount);
  Assert.AreEqual(3, mReport.Files[0].HitsAt(12));
  Assert.AreEqual(0, mReport.Files[0].HitsAt(13));
  Assert.AreEqual(-1, mReport.Files[0].HitsAt(14));
  Assert.AreEqual(1, mReport.Files[0].HitsAt(15));
  Assert.AreEqual(0, mReport.Files[1].CoveredCount);
end;

procedure TCoverageTests.MergesRepeatedFiles;
var
  mReport: TCoverageReport;
begin
  mReport := TCoverage.Parse('<report><data><linehits><file name="A.pas">3=1;4=0</file>' +
    '<file name="a.PAS">4=2;5=0</file></linehits></data></report>');
  Assert.AreEqual(1, Integer(Length(mReport.Files)));
  Assert.AreEqual(3, mReport.Files[0].LineCount);
  Assert.AreEqual(2, mReport.Files[0].HitsAt(4));
end;

procedure TCoverageTests.ReadsJaCoCo;
var
  mReport: TCoverageReport;
begin
  mReport := TCoverage.Parse(cJaCoCo);
  Assert.IsTrue(mReport.Valid);
  Assert.AreEqual<TCoverageFormat>(TCoverageFormat.JaCoCo, mReport.Format);
  Assert.AreEqual(1, Integer(Length(mReport.Files)));
  Assert.AreEqual(12, mReport.Files[0].Lines[0].Line);
  Assert.AreEqual(1, mReport.Files[0].HitsAt(12));
  Assert.AreEqual(0, mReport.Files[0].HitsAt(13));
end;

procedure TCoverageTests.SummaryWithoutLines;
var
  mReport: TCoverageReport;
begin
  mReport := TCoverage.Parse('<report><stats><totallines value="5"/></stats><data><all name="all classes"/>' +
    '</data></report>');
  Assert.IsFalse(mReport.Valid);
  Assert.AreEqual<TCoverageProblem>(TCoverageProblem.NoLines, mReport.Problem);
  Assert.AreEqual<TCoverageFormat>(TCoverageFormat.DelphiCodeCoverage, mReport.Format);
end;

procedure TCoverageTests.NotAReport;
begin
  Assert.AreEqual<TCoverageProblem>(TCoverageProblem.NotAReport, TCoverage.Parse('<test-results/>').Problem);
  Assert.AreEqual<TCoverageProblem>(TCoverageProblem.NotAReport, TCoverage.Parse('').Problem);
  Assert.AreEqual<TCoverageProblem>(TCoverageProblem.NotAReport, TCoverage.Parse('kein XML').Problem);
end;

procedure TCoverageTests.ParsesLineHitText;
var
  mLines: TArray<TCoverageLine>;
begin
  mLines := TCoverage.ParseLineHits(' 9=2 ;x=1;3=0;;4=-1;0=5;9=1;2=7');
  Assert.AreEqual(3, Integer(Length(mLines)));
  Assert.AreEqual(2, mLines[0].Line);
  Assert.AreEqual(7, mLines[0].Hits);
  Assert.AreEqual(3, mLines[1].Line);
  Assert.AreEqual(9, mLines[2].Line);
  Assert.AreEqual(3, mLines[2].Hits);
  Assert.AreEqual(0, Integer(Length(TCoverage.ParseLineHits(''))));
end;

procedure TCoverageTests.FindsFileForPath;
var
  mReport: TCoverageReport;
begin
  mReport := Default(TCoverageReport);
  SetLength(mReport.Files, 4);
  mReport.Files[0].Name := 'Rechner.pas';
  mReport.Files[1].Name := 'Source\Kern\Hilfen.pas';
  mReport.Files[2].Name := 'Kern/Hilfen.pas';
  mReport.Files[3].Name := 'Alt\Hilfen.pas';
  Assert.AreEqual(0, mReport.IndexOf('C:\Projekt\Source\rechner.PAS'));
  Assert.AreEqual(1, mReport.IndexOf('C:/Projekt/Source/Kern/Hilfen.pas'));
  Assert.AreEqual(1, mReport.IndexOf('Source/Kern/Hilfen.pas'));
  Assert.AreEqual(-1, mReport.IndexOf('D:\Anders\Hilfen.pas'));
  Assert.AreEqual(-1, mReport.IndexOf('C:\Projekt\Fehlt.pas'));
  SetLength(mReport.Files, 2);
  Assert.AreEqual(1, mReport.IndexOf('D:\Anders\Hilfen.pas'));
end;

initialization
  TDUnitX.RegisterTestFixture(TCoverageTests);

end.
