unit Atlas.Core.Tests.Coverage.Tests;

// Tests des Zustands der Testabdeckung (#275): Bericht laden, Zeilen im
// Editor (ab 0) nachschlagen, Summen, ungültiger Bericht behält den alten,
// Neuladen nach Änderung und nach Löschen, Quelle neuer als der Bericht,
// Kodierung (DelphiCodeCoverage 1.0.15 schreibt ANSI ohne Kopf).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasCoverageStateTests = class
  private
    FFolder: string;
    function WriteFile(const AName, AText: string; AAge: TDateTime): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LoadsAndLooksUpLines;
    [Test]
    procedure TotalsAndPercent;
    [Test]
    procedure InvalidReportKeepsOld;
    [Test]
    procedure ReloadsChangedAndForgetsDeleted;
    [Test]
    procedure SourceNewerThanReport;
    [Test]
    procedure DecodesUtf8AndAnsi;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  Atlas.Text.Coverage,
  Atlas.Core.Tests.Coverage;

const
  cReport = '<report><data><linehits><file name="Rechner.pas">3=2;4=0;6=1</file>' +
    '<file name="Hilfen.pas">1=0</file></linehits></data></report>';

{ TAtlasCoverageStateTests }

procedure TAtlasCoverageStateTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasCoverage' + IntToStr(Random(1000000)));
  ForceDirectories(FFolder);
end;

procedure TAtlasCoverageStateTests.TearDown;
begin
  if DirectoryExists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

function TAtlasCoverageStateTests.WriteFile(const AName, AText: string; AAge: TDateTime): string;
begin
  Result := TPath.Combine(FFolder, AName);
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
  FileSetDate(Result, DateTimeToFileDate(AAge));
end;

procedure TAtlasCoverageStateTests.LoadsAndLooksUpLines;
var
  mState: TAtlasCoverageState;
  mProblem: TCoverageProblem;
  mPath: string;
begin
  mState := TAtlasCoverageState.Create;
  try
    Assert.IsFalse(mState.Loaded);
    Assert.AreEqual(-1, mState.HitsAt('C:\P\Rechner.pas', 2));
    mPath := WriteFile('CodeCoverage_Summary.xml', cReport, Now);
    Assert.IsTrue(mState.Load(mPath, mProblem));
    Assert.IsTrue(mState.Loaded);
    Assert.AreEqual(mPath, mState.Path);
    Assert.IsTrue(mState.HasFile('C:\P\Source\Rechner.pas'));
    Assert.IsFalse(mState.HasFile('C:\P\Fehlt.pas'));
    // Editorzeile 2 ist Zeile 3 im Bericht.
    Assert.AreEqual(2, mState.HitsAt('C:\P\Source\Rechner.pas', 2));
    Assert.AreEqual(0, mState.HitsAt('C:\P\Source\Rechner.pas', 3));
    Assert.AreEqual(-1, mState.HitsAt('C:\P\Source\Rechner.pas', 4));
    Assert.AreEqual(0, mState.HitsAt('C:\P\Hilfen.pas', 0));
    mState.Clear;
    Assert.IsFalse(mState.Loaded);
    Assert.IsFalse(mState.HasFile('C:\P\Source\Rechner.pas'));
  finally
    mState.Free;
  end;
end;

procedure TAtlasCoverageStateTests.TotalsAndPercent;
var
  mState: TAtlasCoverageState;
  mProblem: TCoverageProblem;
  mTotals: TAtlasCoverageTotals;
  mCovered, mLines: Integer;
begin
  mState := TAtlasCoverageState.Create;
  try
    Assert.IsTrue(mState.Accept('R.xml', cReport, Now, mProblem));
    mTotals := mState.Totals;
    Assert.AreEqual(2, mTotals.Files);
    Assert.AreEqual(4, mTotals.Lines);
    Assert.AreEqual(2, mTotals.Covered);
    Assert.AreEqual(50, mTotals.Percent);
    Assert.IsTrue(mState.FileTotals('X\Rechner.pas', mCovered, mLines));
    Assert.AreEqual(2, mCovered);
    Assert.AreEqual(3, mLines);
    Assert.IsFalse(mState.FileTotals('X\Fehlt.pas', mCovered, mLines));
    Assert.AreEqual(0, Default(TAtlasCoverageTotals).Percent);
  finally
    mState.Free;
  end;
end;

procedure TAtlasCoverageStateTests.InvalidReportKeepsOld;
var
  mState: TAtlasCoverageState;
  mProblem: TCoverageProblem;
begin
  mState := TAtlasCoverageState.Create;
  try
    Assert.IsTrue(mState.Accept('R.xml', cReport, Now, mProblem));
    Assert.IsFalse(mState.Accept('S.xml', '<report><stats/><data/></report>', Now, mProblem));
    Assert.AreEqual<TCoverageProblem>(TCoverageProblem.NoLines, mProblem);
    Assert.IsFalse(mState.Load(TPath.Combine(FFolder, 'fehlt.xml'), mProblem));
    Assert.AreEqual<TCoverageProblem>(TCoverageProblem.NotAReport, mProblem);
    Assert.AreEqual('R.xml', mState.Path);
    Assert.AreEqual(2, mState.HitsAt('Rechner.pas', 2));
  finally
    mState.Free;
  end;
end;

procedure TAtlasCoverageStateTests.ReloadsChangedAndForgetsDeleted;
var
  mState: TAtlasCoverageState;
  mProblem: TCoverageProblem;
  mPath: string;
begin
  mState := TAtlasCoverageState.Create;
  try
    mPath := WriteFile('jacoco.xml', cReport, IncHour(Now, -2));
    Assert.IsTrue(mState.Load(mPath, mProblem));
    Assert.IsFalse(mState.Reload, 'unverändert');
    WriteFile('jacoco.xml', '<report><data><linehits><file name="Rechner.pas">3=7</file></linehits></data></report>',
      IncHour(Now, -1));
    Assert.IsTrue(mState.Reload, 'neuer Lauf');
    Assert.AreEqual(7, mState.HitsAt('Rechner.pas', 2));
    Assert.IsFalse(mState.HasFile('Hilfen.pas'));
    TFile.Delete(mPath);
    Assert.IsTrue(mState.Reload, 'gelöscht');
    Assert.IsFalse(mState.Loaded);
  finally
    mState.Free;
  end;
end;

procedure TAtlasCoverageStateTests.SourceNewerThanReport;
var
  mState: TAtlasCoverageState;
  mProblem: TCoverageProblem;
  mOld, mNew: string;
begin
  mState := TAtlasCoverageState.Create;
  try
    mOld := WriteFile('Alt.pas', 'unit Alt;', IncHour(Now, -3));
    mNew := WriteFile('Neu.pas', 'unit Neu;', IncHour(Now, -1));
    Assert.IsTrue(mState.Load(WriteFile('R.xml', cReport, IncHour(Now, -2)), mProblem));
    Assert.IsFalse(mState.SourceNewer(mOld));
    Assert.IsTrue(mState.SourceNewer(mNew));
    Assert.IsFalse(mState.SourceNewer(TPath.Combine(FFolder, 'Fehlt.pas')));
  finally
    mState.Free;
  end;
end;

procedure TAtlasCoverageStateTests.DecodesUtf8AndAnsi;
var
  mUmlaut: string;
begin
  mUmlaut := Char($E4);
  Assert.AreEqual('<a>' + mUmlaut + '</a>', TAtlasCoverageState.DecodeReport(
    TBytes.Create($EF, $BB, $BF, Ord('<'), Ord('a'), Ord('>'), $C3, $A4, Ord('<'), Ord('/'), Ord('a'), Ord('>'))));
  Assert.AreEqual('<?xml encoding=''utf-8''?>' + mUmlaut, TAtlasCoverageState.DecodeReport(
    TEncoding.UTF8.GetBytes('<?xml encoding=''utf-8''?>' + mUmlaut)));
  Assert.AreEqual('<report/>', TAtlasCoverageState.DecodeReport(TEncoding.ANSI.GetBytes('<report/>')));
  Assert.AreEqual('', TAtlasCoverageState.DecodeReport(nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCoverageStateTests);

end.
