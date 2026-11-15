unit Atlas.Core.Debug.RunToColumnFlow.Tests;

// Tests für die Entscheidungen der Spalte „Bis hier ausführen“ außerhalb der Codezeilen (#851, #1967): Spalte, Lesen
// des Texts, Zeile unter der Maus, Tooltip und ▶; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasRunToColumnFlowTests = class
  public
    [Test]
    procedure ColumnAndReadTiming;
    [Test]
    procedure RowStillThereAndHover;
    [Test]
    procedure TipAfterDelay;
    [Test]
    procedure ArrowCenteredWithMinimum;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Debug.RunToColumnFlow;

function Row(const AFileName: string; ALine, ATopRow: Integer): TAtlasRunToRow;
begin
  Result := Default(TAtlasRunToRow);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.TopRow := ATopRow;
end;

{ TAtlasRunToColumnFlowTests }

procedure TAtlasRunToColumnFlowTests.ColumnAndReadTiming;
begin
  Assert.IsTrue(TAtlasRunToColumnFlow.NeedsColumn(-1, 16, 16));
  Assert.IsTrue(TAtlasRunToColumnFlow.NeedsColumn(2, 16, 20));
  Assert.IsFalse(TAtlasRunToColumnFlow.NeedsColumn(2, 16, 16));
  Assert.IsTrue(TAtlasRunToColumnFlow.ReadDue(False, 100, 90, 500));
  Assert.IsFalse(TAtlasRunToColumnFlow.ReadDue(True, 100, 90, 500));
  Assert.IsTrue(TAtlasRunToColumnFlow.ReadDue(True, 600, 100, 500));
end;

procedure TAtlasRunToColumnFlowTests.RowStillThereAndHover;
begin
  Assert.IsTrue(TAtlasRunToColumnFlow.StillThere(Row('Kunden.pas', 4, 10), 'KUNDEN.PAS', 10));
  Assert.IsFalse(TAtlasRunToColumnFlow.StillThere(Row('Kunden.pas', 4, 10), 'Kunden.pas', 11));
  Assert.IsFalse(TAtlasRunToColumnFlow.StillThere(Row('Kunden.pas', 4, 10), 'Lager.pas', 10));
  Assert.IsTrue(TAtlasRunToColumnFlow.SameHover(True, Row('Kunden.pas', 4, 10), Row('kunden.pas', 4, 12)));
  Assert.IsFalse(TAtlasRunToColumnFlow.SameHover(False, Row('Kunden.pas', 4, 10), Row('Kunden.pas', 4, 10)));
  Assert.IsFalse(TAtlasRunToColumnFlow.SameHover(True, Row('Kunden.pas', 4, 10), Row('Kunden.pas', 5, 10)));
end;

procedure TAtlasRunToColumnFlowTests.TipAfterDelay;
begin
  Assert.IsFalse(TAtlasRunToColumnFlow.TipDue(False, 1399, 1000, 400));
  Assert.IsTrue(TAtlasRunToColumnFlow.TipDue(False, 1400, 1000, 400));
  Assert.IsFalse(TAtlasRunToColumnFlow.TipDue(True, 5000, 1000, 400));
end;

procedure TAtlasRunToColumnFlowTests.ArrowCenteredWithMinimum;
var
  mPoints: TArray<TPoint>;
begin
  mPoints := TAtlasRunToColumnFlow.Arrow(TRect.Create(0, 0, 20, 14), 6, 4);
  // Kante 14 - 4 = 10, mittig in 20 x 14.
  Assert.AreEqual(3, Integer(Length(mPoints)));
  Assert.AreEqual(5, mPoints[0].X);
  Assert.AreEqual(2, mPoints[0].Y);
  Assert.AreEqual(14, mPoints[1].X);
  Assert.AreEqual(7, mPoints[1].Y);
  Assert.AreEqual(11, mPoints[2].Y);
  // Zu kleine Zelle: Mindestgröße.
  mPoints := TAtlasRunToColumnFlow.Arrow(TRect.Create(0, 0, 8, 8), 6, 4);
  Assert.AreEqual(1, mPoints[0].X);
  Assert.AreEqual(6, mPoints[2].Y);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRunToColumnFlowTests);

end.
