unit Atlas.Core.VersionControl.LineChangesPlan.Tests;

// Tests für die Entscheidungen der Änderungsmarken und der Zeilenhistorie
// (#507): Schalter, Vergleich nach der Tipp-Pause, Eintrag von blame,
// Maße in der Rinne, Klick, Cursorzeile und Überfahren.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.VersionControl')]
  TAtlasLineChangesPlanTests = class
  public
    /// <summary>Marken laufen mit Rinne oder Historie, nicht abgeschaltet.</summary>
    [Test]
    procedure ActiveNeedsOneSwitch;
    /// <summary>Vergleich erst nach der Tipp-Pause; aktuell nur zum selben Text mit Zeilen.</summary>
    [Test]
    procedure CompareWaitsForPause;
    /// <summary>blame neu für die Nachrichten nur, wenn sie fehlen und jetzt gewollt sind.</summary>
    [Test]
    procedure ReloadForMessages;
    /// <summary>Eintrag direkt an der Stelle, sonst gesucht, sonst -1.</summary>
    [Test]
    procedure EntryOfFindsLine;
    /// <summary>Balken 3/16 der Zeilenhöhe (gerundet, mindestens 3), Dreieck ein Drittel (mindestens 4).</summary>
    [Test]
    procedure GutterSizes;
    /// <summary>Marke gilt nur ohne Scrollen, in derselben Datei und mit vorhandener Änderung.</summary>
    [Test]
    procedure MarkStillThereChecksAll;
    /// <summary>Klick öffnet nur mit linker Taste ohne Zusatztasten; Historie nur auf der Cursorzeile.</summary>
    [Test]
    procedure ClickAndBlameLine;
    /// <summary>Fenster „alter Stand“ schließt nach Betreten und Verlassen; Hover nach der Wartezeit.</summary>
    [Test]
    procedure HoverSteps;
  end;

implementation

uses
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.LineChangesPlan;

function BlameLine(ALine: Integer): TAtlasVcsBlameLine;
begin
  Result := Default(TAtlasVcsBlameLine);
  Result.Line := ALine;
  Result.Revision := 'abc';
end;

{ TAtlasLineChangesPlanTests }

procedure TAtlasLineChangesPlanTests.ActiveNeedsOneSwitch;
begin
  Assert.IsTrue(TAtlasLineChangesPlan.Active(True, False, False));
  Assert.IsTrue(TAtlasLineChangesPlan.Active(False, True, False));
  Assert.IsFalse(TAtlasLineChangesPlan.Active(False, False, False));
  Assert.IsFalse(TAtlasLineChangesPlan.Active(True, True, True), 'abgeschaltet');
end;

procedure TAtlasLineChangesPlanTests.CompareWaitsForPause;
begin
  Assert.IsTrue(TAtlasLineChangesPlan.ComparesNow(True, False, 'ab', 'a', 1000, 1300));
  Assert.IsFalse(TAtlasLineChangesPlan.ComparesNow(True, False, 'ab', 'a', 1000, 1299), 'Pause läuft');
  Assert.IsFalse(TAtlasLineChangesPlan.ComparesNow(True, False, 'a', 'a', 1000, 9000), 'schon verglichen');
  Assert.IsFalse(TAtlasLineChangesPlan.ComparesNow(True, True, 'ab', 'a', 1000, 9000), 'unterwegs');
  Assert.IsFalse(TAtlasLineChangesPlan.ComparesNow(False, False, 'ab', 'a', 1000, 9000), 'ohne Stand');
  Assert.IsTrue(TAtlasLineChangesPlan.Fresh(True, 'a', 'a', True));
  Assert.IsFalse(TAtlasLineChangesPlan.Fresh(True, 'a', 'ab', True));
  Assert.IsFalse(TAtlasLineChangesPlan.Fresh(True, 'a', 'a', False), 'ohne Zeilen');
  Assert.IsFalse(TAtlasLineChangesPlan.Fresh(False, 'a', 'a', True));
end;

procedure TAtlasLineChangesPlanTests.ReloadForMessages;
begin
  Assert.IsTrue(TAtlasLineChangesPlan.ReloadsForMessages(True, False, True));
  Assert.IsFalse(TAtlasLineChangesPlan.ReloadsForMessages(True, True, True), 'schon geladen');
  Assert.IsFalse(TAtlasLineChangesPlan.ReloadsForMessages(True, False, False));
  Assert.IsFalse(TAtlasLineChangesPlan.ReloadsForMessages(False, False, True), 'ohne blame');
end;

procedure TAtlasLineChangesPlanTests.EntryOfFindsLine;
var
  mLines: TArray<TAtlasVcsBlameLine>;
begin
  mLines := TArray<TAtlasVcsBlameLine>.Create(BlameLine(1), BlameLine(2), BlameLine(3));
  Assert.AreEqual(1, TAtlasLineChangesPlan.EntryOf(mLines, 1), 'der Reihe nach');
  mLines := TArray<TAtlasVcsBlameLine>.Create(BlameLine(3), BlameLine(1), BlameLine(2));
  Assert.AreEqual(0, TAtlasLineChangesPlan.EntryOf(mLines, 2), 'gesucht');
  Assert.AreEqual(-1, TAtlasLineChangesPlan.EntryOf(mLines, 7));
  Assert.AreEqual(-1, TAtlasLineChangesPlan.EntryOf(nil, 0));
  mLines := nil;
end;

procedure TAtlasLineChangesPlanTests.GutterSizes;
begin
  Assert.AreEqual(3, TAtlasLineChangesPlan.BarWidth(16));
  Assert.AreEqual(4, TAtlasLineChangesPlan.BarWidth(19), 'aufgerundet wie MulDiv');
  Assert.AreEqual(3, TAtlasLineChangesPlan.BarWidth(8), 'mindestens 3');
  Assert.AreEqual(6, TAtlasLineChangesPlan.BarWidth(32));
  Assert.AreEqual(4, TAtlasLineChangesPlan.DeletedSize(9), 'mindestens 4');
  Assert.AreEqual(8, TAtlasLineChangesPlan.DeletedSize(24));
end;

procedure TAtlasLineChangesPlanTests.MarkStillThereChecksAll;
begin
  Assert.IsTrue(TAtlasLineChangesPlan.MarkStillThere('C:\P\A.pas', 'c:\p\a.pas', 5, 5, 0, 2));
  Assert.IsFalse(TAtlasLineChangesPlan.MarkStillThere('C:\P\A.pas', 'C:\P\B.pas', 5, 5, 0, 2), 'andere Datei');
  Assert.IsFalse(TAtlasLineChangesPlan.MarkStillThere('C:\P\A.pas', 'C:\P\A.pas', 5, 6, 0, 2), 'gescrollt');
  Assert.IsFalse(TAtlasLineChangesPlan.MarkStillThere('C:\P\A.pas', 'C:\P\A.pas', 5, 5, 3, 2), 'nicht mehr da');
  Assert.IsFalse(TAtlasLineChangesPlan.MarkStillThere('C:\P\A.pas', 'C:\P\A.pas', 5, 5, -1, 2), 'ohne Änderung');
end;

procedure TAtlasLineChangesPlanTests.ClickAndBlameLine;
begin
  Assert.IsTrue(TAtlasLineChangesPlan.OpensChange(True, False, True, True));
  Assert.IsFalse(TAtlasLineChangesPlan.OpensChange(False, False, True, True), 'rechte Taste');
  Assert.IsFalse(TAtlasLineChangesPlan.OpensChange(True, True, True, True), 'mit Strg');
  Assert.IsFalse(TAtlasLineChangesPlan.OpensChange(True, False, False, True), 'Rinne aus');
  Assert.IsFalse(TAtlasLineChangesPlan.OpensChange(True, False, True, False), 'veraltet');
  Assert.IsTrue(TAtlasLineChangesPlan.BlameOnLine(True, True, True, True, 7, 7));
  Assert.IsFalse(TAtlasLineChangesPlan.BlameOnLine(True, True, True, True, 7, 8), 'andere Zeile');
  Assert.IsFalse(TAtlasLineChangesPlan.BlameOnLine(True, False, True, True, 7, 7), 'ohne blame');
  Assert.IsFalse(TAtlasLineChangesPlan.BlameOnLine(True, True, False, True, 7, 7), 'andere Datei');
  Assert.IsFalse(TAtlasLineChangesPlan.BlameOnLine(True, True, True, False, 7, 7), 'veraltet');
  Assert.IsFalse(TAtlasLineChangesPlan.BlameOnLine(False, True, True, True, 7, 7), 'aus oder abgeschaltet');
  Assert.IsTrue(TAtlasLineChangesPlan.CommitShown(False, True, False));
  Assert.IsFalse(TAtlasLineChangesPlan.CommitShown(True, True, False), 'nicht gespeichert');
  Assert.IsFalse(TAtlasLineChangesPlan.CommitShown(False, False, False), 'ohne Eintrag');
  Assert.IsFalse(TAtlasLineChangesPlan.CommitShown(False, True, True), 'nicht übernommen');
end;

procedure TAtlasLineChangesPlanTests.HoverSteps;
begin
  Assert.AreEqual(Ord(TAtlasChangeTipStep.Entered), Ord(TAtlasLineChangesPlan.ChangeTipStep(True, False)));
  Assert.AreEqual(Ord(TAtlasChangeTipStep.Stay), Ord(TAtlasLineChangesPlan.ChangeTipStep(False, False)),
    'noch nicht betreten');
  Assert.AreEqual(Ord(TAtlasChangeTipStep.Close), Ord(TAtlasLineChangesPlan.ChangeTipStep(False, True)));
  Assert.AreEqual(Ord(TAtlasBlameHoverStep.Close), Ord(TAtlasLineChangesPlan.BlameHoverStep(False, True, 0, 0)));
  Assert.AreEqual(Ord(TAtlasBlameHoverStep.Stay), Ord(TAtlasLineChangesPlan.BlameHoverStep(True, False, 1000, 1399)));
  Assert.AreEqual(Ord(TAtlasBlameHoverStep.Show), Ord(TAtlasLineChangesPlan.BlameHoverStep(True, False, 1000, 1400)));
  Assert.AreEqual(Ord(TAtlasBlameHoverStep.Stay), Ord(TAtlasLineChangesPlan.BlameHoverStep(True, True, 1000, 9000)),
    'schon sichtbar');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLineChangesPlanTests);

end.
