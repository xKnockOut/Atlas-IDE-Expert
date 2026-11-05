unit Atlas.Common.Logging.EntryText.Tests;

// Tests des Klartexts eines Logeintrags (#1478).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLogEntryTextTests = class
  public
    [Test]
    procedure PlainRemovesMarks;
    [Test]
    procedure PlainLineKeepsTimestampAndLevel;
    [Test]
    procedure EntryKeepsMarks;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.EntryText,
  Atlas.Text.LogMarks;

function Sample: TLogEntry;
begin
  Result := TLogEntry.Create(EncodeDateTime(2026, 11, 5, 9, 30, 0, 123), TLogLevel.Warning,
    'Datei ' + TLogMarks.Path('Kunden.pas') + ' von ' + TLogMarks.Name('Kasse'));
end;

{ TLogEntryTextTests }

procedure TLogEntryTextTests.PlainRemovesMarks;
begin
  Assert.AreEqual('Datei Kunden.pas von Kasse', TLogEntryText.Plain(Sample));
end;

procedure TLogEntryTextTests.PlainLineKeepsTimestampAndLevel;
begin
  Assert.AreEqual('2026-11-05 09:30:00.123 [WARNING] Datei Kunden.pas von Kasse', TLogEntryText.PlainLine(Sample));
end;

procedure TLogEntryTextTests.EntryKeepsMarks;
begin
  // Der Eintrag selbst behält die Kennzeichen, damit anonym schreibende Senken ersetzen können.
  Assert.IsTrue(TLogMarks.HasMarks(Sample.Text));
  Assert.IsTrue(TLogMarks.HasMarks(Sample.ToText));
end;

initialization
  TDUnitX.RegisterTestFixture(TLogEntryTextTests);

end.
