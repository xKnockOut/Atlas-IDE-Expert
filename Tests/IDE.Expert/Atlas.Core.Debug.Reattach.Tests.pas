unit Atlas.Core.Debug.Reattach.Tests;

// Tests für „Erneut anhängen“ (#2171): Auswahl des Prozesses nach Pfad und Name, Warten, Zeile der Auswahl.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasReattachTests = class
  public
    /// <summary>Genau ein Prozess mit gleichem Pfad: sofort anhängen.</summary>
    [Test]
    procedure AttachesSamePath;
    /// <summary>Zwei mit gleichem Pfad: Auswahl nur aus diesen.</summary>
    [Test]
    procedure ChoosesAmongSamePath;
    /// <summary>Gleicher Name, anderer Pfad: Auswahl statt Anhängen.</summary>
    [Test]
    procedure ChoosesOtherVersion;
    /// <summary>Keiner läuft: Warten anbieten.</summary>
    [Test]
    procedure OffersWait;
    /// <summary>Nur Name gemerkt: Name zählt wie der Pfad.</summary>
    [Test]
    procedure NameOnlyTarget;
    /// <summary>Beim Warten zählt nur ein neuer Prozess.</summary>
    [Test]
    procedure FindsArrival;
    /// <summary>Zeile mit Kennung, Startzeit und Befehlszeile.</summary>
    [Test]
    procedure WritesRow;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.Reattach;

const
  cPath = 'C:\Bin\Kunden.exe';

function Running: TAtlasReattachProcesses;
begin
  Result := [TAtlasReattachProcess.Create(10, 'C:\Windows\explorer.exe', 'explorer.exe'),
    TAtlasReattachProcess.Create(20, 'c:\bin\KUNDEN.exe', 'KUNDEN.exe'),
    TAtlasReattachProcess.Create(30, 'C:\Alt\Kunden.exe', 'Kunden.exe')];
end;

procedure TAtlasReattachTests.AttachesSamePath;
var
  mCandidates: TAtlasReattachProcesses;
begin
  Assert.AreEqual(Ord(TAtlasReattachDecision.Attach), Ord(TAtlasReattach.Decide(cPath, Running, mCandidates)));
  Assert.AreEqual(Integer(1), Integer(Length(mCandidates)));
  Assert.AreEqual(Int64(20), Int64(mCandidates[0].Pid));
end;

procedure TAtlasReattachTests.ChoosesAmongSamePath;
var
  mCandidates: TAtlasReattachProcesses;
begin
  Assert.AreEqual(Ord(TAtlasReattachDecision.Choose),
    Ord(TAtlasReattach.Decide(cPath, Running + [TAtlasReattachProcess.Create(40, cPath, 'Kunden.exe')],
    mCandidates)));
  Assert.AreEqual(Integer(2), Integer(Length(mCandidates)));
  Assert.AreEqual(Int64(20), Int64(mCandidates[0].Pid));
  Assert.AreEqual(Int64(40), Int64(mCandidates[1].Pid));
end;

procedure TAtlasReattachTests.ChoosesOtherVersion;
var
  mCandidates: TAtlasReattachProcesses;
begin
  Assert.AreEqual(Ord(TAtlasReattachDecision.Choose),
    Ord(TAtlasReattach.Decide('D:\Neu\Kunden.exe', Running, mCandidates)));
  Assert.AreEqual(Integer(2), Integer(Length(mCandidates)));
end;

procedure TAtlasReattachTests.OffersWait;
var
  mCandidates: TAtlasReattachProcesses;
begin
  Assert.AreEqual(Ord(TAtlasReattachDecision.Wait),
    Ord(TAtlasReattach.Decide('C:\Bin\Lager.exe', Running, mCandidates)));
  Assert.AreEqual(Integer(0), Integer(Length(mCandidates)));
  Assert.AreEqual(Ord(TAtlasReattachDecision.Wait), Ord(TAtlasReattach.Decide('', Running, mCandidates)));
end;

procedure TAtlasReattachTests.NameOnlyTarget;
var
  mCandidates: TAtlasReattachProcesses;
begin
  Assert.AreEqual('Kunden.exe', TAtlasReattach.NameOf(cPath));
  Assert.AreEqual(Ord(TAtlasReattachDecision.Attach),
    Ord(TAtlasReattach.Decide('explorer.exe', Running, mCandidates)));
  Assert.AreEqual(Ord(TAtlasReattachDecision.Choose),
    Ord(TAtlasReattach.Decide('kunden.exe', Running, mCandidates)));
end;

procedure TAtlasReattachTests.FindsArrival;
var
  mKnown: TArray<Cardinal>;
  mProcess: TAtlasReattachProcess;
begin
  mKnown := TAtlasReattach.Pids(Running);
  Assert.IsFalse(TAtlasReattach.Arrival(cPath, Running, mKnown, mProcess), 'lief schon beim Beginn');
  Assert.IsTrue(TAtlasReattach.Arrival(cPath, Running + [TAtlasReattachProcess.Create(50, cPath, 'Kunden.exe')],
    mKnown, mProcess));
  Assert.AreEqual(Int64(50), Int64(mProcess.Pid));
  Assert.IsFalse(TAtlasReattach.Arrival(cPath, [TAtlasReattachProcess.Create(60, 'C:\Alt\Kunden.exe',
    'Kunden.exe')], mKnown, mProcess), 'anderer Pfad');
end;

procedure TAtlasReattachTests.WritesRow;
var
  mProcess: TAtlasReattachProcess;
  mFormat: TFormatSettings;
begin
  mFormat := TFormatSettings.Create;
  mFormat.DateSeparator := '.';
  mFormat.TimeSeparator := ':';
  mFormat.ShortDateFormat := 'dd.mm.yyyy';
  mFormat.LongTimeFormat := 'hh:nn:ss';
  mProcess := TAtlasReattachProcess.Create(4711, cPath, 'Kunden.exe');
  Assert.AreEqual('4711 · C:\Bin\Kunden.exe', TAtlasReattach.Row(mProcess, mFormat));
  mProcess.StartedAt := EncodeDate(2026, 11, 13) + EncodeTime(10, 15, 2, 0);
  mProcess.CommandLine := '"C:\Bin\Kunden.exe" -demo';
  Assert.AreEqual('4711 · 13.11.2026 10:15:02 · "C:\Bin\Kunden.exe" -demo', TAtlasReattach.Row(mProcess, mFormat));
end;

end.
