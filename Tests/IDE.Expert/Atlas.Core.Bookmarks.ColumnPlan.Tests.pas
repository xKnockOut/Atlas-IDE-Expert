unit Atlas.Core.Bookmarks.ColumnPlan.Tests;

// Tests für die Entscheidungen der Spalte der schnellen Lesezeichen (#1104):
// Tipp-Pause im oberen Editor, Gültigkeit der Marker, gleiche Zeile, Stufe
// der Zeilennummern, Farbe der Ziffer und die Zeitpunkte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Bookmarks')]
  TAtlasQuickColumnPlanTests = class
  public
    /// <summary>Neue Datei gleich, geänderter Text erst nach der Pause, danach nichts mehr.</summary>
    [Test]
    procedure TrackWaitsForTypingPause;
    /// <summary>Kein Editor ändert nichts; Reset vergisst die Datei.</summary>
    [Test]
    procedure TrackWithoutEditorAndReset;
    /// <summary>Marker gelten ohne Zeilentext oder bei passendem Anker (Leerraum zählt nicht).</summary>
    [Test]
    procedure MarksNeedMatchingAnchor;
    /// <summary>Gleiche Zeile nur bei gleichem Fenster, gleicher Zeile und Datei (Groß/klein egal).</summary>
    [Test]
    procedure SameRowComparesWindowLineAndFile;
    /// <summary>Stufe der Zeilennummern grenzt rechts an die Spalte; die erste Stufe nie.</summary>
    [Test]
    procedure LineNumberStageBordersColumn;
    /// <summary>Weiße Ziffer auf dunklem, schwarze auf hellem Marker.</summary>
    [Test]
    procedure DigitColorContrasts;
    /// <summary>Tooltip, Protokoll und Klick über den Editor nach ihren Zeiten.</summary>
    [Test]
    procedure TimesForTipReportAndClick;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Color,
  Atlas.Core.Bookmarks.ColumnPlan;

{ TAtlasQuickColumnPlanTests }

procedure TAtlasQuickColumnPlanTests.TrackWaitsForTypingPause;
var
  mTrack: TAtlasQuickTrack;
begin
  mTrack := Default(TAtlasQuickTrack);
  Assert.AreEqual(Ord(TAtlasQuickTrackStep.NewFile), Ord(mTrack.Step('C:\P\A.pas', 'a', 1000, 600)));
  Assert.AreEqual(Ord(TAtlasQuickTrackStep.Idle), Ord(mTrack.Step('C:\P\A.pas', 'a', 1100, 600)), 'erledigt');
  Assert.AreEqual(Ord(TAtlasQuickTrackStep.Changed), Ord(mTrack.Step('c:\p\a.pas', 'ab', 2000, 600)),
    'gleiche Datei, Groß/klein egal');
  Assert.AreEqual(Ord(TAtlasQuickTrackStep.Idle), Ord(mTrack.Step('C:\P\A.pas', 'ab', 2599, 600)), 'Pause läuft');
  Assert.AreEqual(Ord(TAtlasQuickTrackStep.Settled), Ord(mTrack.Step('C:\P\A.pas', 'ab', 2600, 600)));
  Assert.AreEqual(Ord(TAtlasQuickTrackStep.Idle), Ord(mTrack.Step('C:\P\A.pas', 'ab', 5000, 600)), 'nur einmal');
  Assert.AreEqual(Ord(TAtlasQuickTrackStep.NewFile), Ord(mTrack.Step('C:\P\B.pas', 'b', 5100, 600)));
  Assert.AreEqual('C:\P\B.pas', mTrack.FileName);
  Assert.AreEqual('b', mTrack.Text);
  mTrack := Default(TAtlasQuickTrack);
end;

procedure TAtlasQuickColumnPlanTests.TrackWithoutEditorAndReset;
var
  mTrack: TAtlasQuickTrack;
begin
  mTrack := Default(TAtlasQuickTrack);
  Assert.AreEqual(Ord(TAtlasQuickTrackStep.NewFile), Ord(mTrack.Step('C:\P\A.pas', 'a', 1000, 600)));
  Assert.AreEqual(Ord(TAtlasQuickTrackStep.Idle), Ord(mTrack.Step('', '', 2000, 600)));
  Assert.AreEqual('C:\P\A.pas', mTrack.FileName, 'ohne Editor bleibt die Datei');
  mTrack.Reset;
  Assert.AreEqual('', mTrack.FileName);
  Assert.AreEqual(Ord(TAtlasQuickTrackStep.NewFile), Ord(mTrack.Step('C:\P\A.pas', 'a', 3000, 600)),
    'nach Reset wieder neu');
  mTrack := Default(TAtlasQuickTrack);
end;

procedure TAtlasQuickColumnPlanTests.MarksNeedMatchingAnchor;
begin
  Assert.IsTrue(TAtlasQuickColumnPlan.KeepsMarks(False, 'anders', 'x := 1;'), 'ohne Zeilentext');
  Assert.IsTrue(TAtlasQuickColumnPlan.KeepsMarks(True, 'x := 1;', 'x := 1;'));
  Assert.IsTrue(TAtlasQuickColumnPlan.KeepsMarks(True, '    x := 1;   ', 'x := 1;'), 'Einrückung zählt nicht');
  Assert.IsFalse(TAtlasQuickColumnPlan.KeepsMarks(True, 'y := 2;', 'x := 1;'));
end;

procedure TAtlasQuickColumnPlanTests.SameRowComparesWindowLineAndFile;
begin
  Assert.IsTrue(TAtlasQuickColumnPlan.SameRow(10, 5, 'C:\P\A.pas', 10, 5, 'c:\p\a.pas'));
  Assert.IsFalse(TAtlasQuickColumnPlan.SameRow(10, 5, 'C:\P\A.pas', 11, 5, 'C:\P\A.pas'), 'anderes Fenster');
  Assert.IsFalse(TAtlasQuickColumnPlan.SameRow(10, 5, 'C:\P\A.pas', 10, 6, 'C:\P\A.pas'), 'andere Zeile');
  Assert.IsFalse(TAtlasQuickColumnPlan.SameRow(10, 5, 'C:\P\A.pas', 10, 5, 'C:\P\B.pas'), 'andere Datei');
end;

procedure TAtlasQuickColumnPlanTests.LineNumberStageBordersColumn;
begin
  Assert.IsTrue(TAtlasQuickColumnPlan.IsLineNumberStage(False, 40, 30, 40));
  Assert.IsTrue(TAtlasQuickColumnPlan.IsLineNumberStage(False, 39, 30, 40), 'ein Pixel davor');
  Assert.IsTrue(TAtlasQuickColumnPlan.IsLineNumberStage(False, 42, 30, 40), 'zwei Pixel dahinter');
  Assert.IsFalse(TAtlasQuickColumnPlan.IsLineNumberStage(False, 43, 30, 40));
  Assert.IsFalse(TAtlasQuickColumnPlan.IsLineNumberStage(False, 38, 30, 40));
  Assert.IsFalse(TAtlasQuickColumnPlan.IsLineNumberStage(True, 40, 30, 40), 'erste Stufe');
  Assert.IsFalse(TAtlasQuickColumnPlan.IsLineNumberStage(False, 40, 0, 40), 'ohne Breite');
end;

procedure TAtlasQuickColumnPlanTests.DigitColorContrasts;
begin
  Assert.AreEqual(Integer($FFFFFF), Integer(TAtlasQuickColumnPlan.DigitColor(TAtlasColor($202020))));
  Assert.AreEqual(Integer($000000), Integer(TAtlasQuickColumnPlan.DigitColor(TAtlasColor($C0E0F0))));
end;

procedure TAtlasQuickColumnPlanTests.TimesForTipReportAndClick;
begin
  Assert.IsFalse(TAtlasQuickColumnPlan.TipDue(False, 1000, 1399, 400));
  Assert.IsTrue(TAtlasQuickColumnPlan.TipDue(False, 1000, 1400, 400));
  Assert.IsFalse(TAtlasQuickColumnPlan.TipDue(True, 1000, 9000, 400), 'schon sichtbar');
  Assert.IsTrue(TAtlasQuickColumnPlan.ReportNotPainted(2, False, 'C:\P\A.pas', 1000, 6000, 5000));
  Assert.IsFalse(TAtlasQuickColumnPlan.ReportNotPainted(2, False, 'C:\P\A.pas', 1000, 5999, 5000), 'zu früh');
  Assert.IsFalse(TAtlasQuickColumnPlan.ReportNotPainted(-1, False, 'C:\P\A.pas', 1000, 9000, 5000), 'keine Spalte');
  Assert.IsFalse(TAtlasQuickColumnPlan.ReportNotPainted(2, True, 'C:\P\A.pas', 1000, 9000, 5000), 'gemeldet');
  Assert.IsFalse(TAtlasQuickColumnPlan.ReportNotPainted(2, False, '', 1000, 9000, 5000), 'keine Datei');
  Assert.IsTrue(TAtlasQuickColumnPlan.RecentlyTaken(1000, 1499));
  Assert.IsFalse(TAtlasQuickColumnPlan.RecentlyTaken(1000, 1500));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuickColumnPlanTests);

end.
