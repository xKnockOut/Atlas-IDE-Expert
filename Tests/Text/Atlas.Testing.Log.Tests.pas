unit Atlas.Testing.Log.Tests;

// Test der mitgelieferten Unit Atlas.Testing.Log (#2168): Zeilen der
// Seitendatei, wie sie der Logger schreibt, liest Atlas.Core.Tests.Log genau so
// zurück; Seitendatei und Konsolenmarken stimmen auf beiden Seiten überein.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTestingLogTests = class
  public
    [Test]
    procedure MultilineMessageBecomesSeveralLines;
    [Test]
    procedure LevelsAsKinds;
    [Test]
    procedure SameNamesAsAtlas;
    [Test]
    procedure WrittenLinesReadBackPerTest;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Testing.Log,
  Atlas.Core.Tests.Log;

/// <summary>Zeilen mit LF verbunden, wie sie in der Seitendatei stehen.</summary>
function Joined(const ALines: TArray<string>): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in ALines do
  begin
    Result := Result + mLine + #10;
  end;
end;

procedure TAtlasTestingLogTests.MultilineMessageBecomesSeveralLines;
var
  mLines: TArray<string>;
begin
  mLines := TAtlasTestLogger.Lines(42, 'I', 'erste' + #13#10 + 'zweite' + #9 + 'Spalte');
  Assert.AreEqual(2, Integer(Length(mLines)));
  Assert.AreEqual('42' + #9 + 'I' + #9 + 'erste', mLines[0]);
  Assert.AreEqual('42' + #9 + 'I' + #9 + 'zweite Spalte', mLines[1], 'Tabulator im Text als Leerzeichen');
  Assert.AreEqual(1, Integer(Length(TAtlasTestLogger.Lines(0, 'T-', ''))), 'leerer Text gibt eine Zeile');
end;

procedure TAtlasTestingLogTests.LevelsAsKinds;
begin
  Assert.AreEqual('I', TAtlasTestLogger.KindOf(TLogLevel.Information));
  Assert.AreEqual('W', TAtlasTestLogger.KindOf(TLogLevel.Warning));
  Assert.AreEqual('E', TAtlasTestLogger.KindOf(TLogLevel.Error));
end;

procedure TAtlasTestingLogTests.SameNamesAsAtlas;
begin
  Assert.AreEqual(TAtlasTestLog.SideFileOf('C:\Temp\bericht.xml'), TAtlasTestLogger.SideFileOf('C:\Temp\bericht.xml'));
  Assert.AreEqual(TAtlasTestLog.cFormat, TAtlasTestLogger.cFormat);
  Assert.AreEqual(TAtlasTestLog.cConsoleBegin, TAtlasTestLogger.cConsoleBegin);
  Assert.AreEqual(TAtlasTestLog.cConsoleEnd, TAtlasTestLogger.cConsoleEnd);
  Assert.AreEqual(TAtlasTestLog.cConsoleLog, TAtlasTestLogger.cConsoleLog);
end;

procedure TAtlasTestingLogTests.WrittenLinesReadBackPerTest;
const
  cTest = 'Kunden.Tests.TKundenTests.Laedt';
var
  mSide: string;
  mRun: TAtlasTestLogRun;
begin
  mSide := Joined(TAtlasTestLogger.Lines(0, 'A', TAtlasTestLogger.cFormat)) +
    Joined(TAtlasTestLogger.Lines(1, 'F+', 'Kunden.Tests.TKundenTests')) +
    Joined(TAtlasTestLogger.Lines(2, 'T+', cTest)) +
    Joined(TAtlasTestLogger.Lines(3, TAtlasTestLogger.KindOf(TLogLevel.Warning), 'Zeile 1' + #10 + 'Zeile 2')) +
    Joined(TAtlasTestLogger.Lines(4, 'T-', '')) + Joined(TAtlasTestLogger.Lines(5, 'F-', ''));
  mRun := TAtlasTestLog.Parse(mSide, '', 2000);
  Assert.IsTrue(mRun.HasLogger);
  Assert.AreEqual(2, TAtlasTestLog.CountOf(mRun, cTest));
  Assert.AreEqual<TAtlasTestLogLevel>(TAtlasTestLogLevel.Warning, mRun.Entries[mRun.IndexOf(cTest)].Lines[1].Level);
end;

end.
