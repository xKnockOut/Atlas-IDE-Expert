unit Atlas.Core.Debug.PinsFlow.Tests;

// Tests für die Entscheidungen der angehefteten Werte außerhalb der Ablage (#526, #1967): Halt, Grenze, Aktion,
// Felder einer Zeile, Klick und Kreuz; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasPinsFlowTests = class
  public
    [Test]
    procedure StopHoldsUntilNextStop;
    [Test]
    procedure LimitOnlyWhenFull;
    [Test]
    procedure OfferNeedsExpression;
    [Test]
    procedure OnLineKeepsOrder;
    [Test]
    procedure ClickNeedsPlainLeft;
    [Test]
    procedure HitAtPrefersLast;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Debug.Pins,
  Atlas.Core.Debug.PinsFlow;

function Pin(ALine: Integer; const AExpression: string): TAtlasDebugPin;
begin
  Result := TAtlasDebugPin.Create('P.dproj', 'Kunden.pas', ALine, AExpression);
end;

function Hit(const APin: TAtlasDebugPin; ALeft, ARight: Integer): TAtlasPinHit;
begin
  Result := Default(TAtlasPinHit);
  Result.Pin := APin;
  Result.Rect := TRect.Create(ALeft, 0, ARight, 10);
end;

{ TAtlasPinsFlowTests }

procedure TAtlasPinsFlowTests.StopHoldsUntilNextStop;
begin
  Assert.IsTrue(TAtlasPinsFlow.StillStopped(True, 4, 4, True));
  Assert.IsFalse(TAtlasPinsFlow.StillStopped(True, 4, 5, True));
  Assert.IsFalse(TAtlasPinsFlow.StillStopped(True, 4, 4, False));
  Assert.IsFalse(TAtlasPinsFlow.StillStopped(False, 4, 4, True));
end;

procedure TAtlasPinsFlowTests.LimitOnlyWhenFull;
begin
  Assert.IsTrue(TAtlasPinsFlow.ReportLimit(False, TAtlasDebugPins.cLimit));
  // Doppelt angeheftet: still.
  Assert.IsFalse(TAtlasPinsFlow.ReportLimit(False, TAtlasDebugPins.cLimit - 1));
  Assert.IsFalse(TAtlasPinsFlow.ReportLimit(True, TAtlasDebugPins.cLimit));
end;

procedure TAtlasPinsFlowTests.OfferNeedsExpression;
begin
  Assert.IsTrue(TAtlasPinsFlow.CanOffer(True, 'Kunde.Name'));
  Assert.IsFalse(TAtlasPinsFlow.CanOffer(True, ''));
  Assert.IsFalse(TAtlasPinsFlow.CanOffer(False, 'Kunde.Name'));
end;

procedure TAtlasPinsFlowTests.OnLineKeepsOrder;
var
  mPins: TAtlasDebugPinList;
begin
  mPins := TAtlasPinsFlow.OnLine([Pin(3, 'a'), Pin(4, 'b'), Pin(3, 'c')], 3);
  Assert.AreEqual(2, Integer(Length(mPins)));
  Assert.AreEqual('a', mPins[0].Expression);
  Assert.AreEqual('c', mPins[1].Expression);
  Assert.AreEqual(0, Integer(Length(TAtlasPinsFlow.OnLine(nil, 3))));
end;

procedure TAtlasPinsFlowTests.ClickNeedsPlainLeft;
begin
  Assert.IsTrue(TAtlasPinsFlow.WantsClick(True, False, True));
  Assert.IsFalse(TAtlasPinsFlow.WantsClick(False, False, True));
  Assert.IsFalse(TAtlasPinsFlow.WantsClick(True, True, True));
  Assert.IsFalse(TAtlasPinsFlow.WantsClick(True, False, False));
end;

procedure TAtlasPinsFlowTests.HitAtPrefersLast;
var
  mPin: TAtlasDebugPin;
begin
  Assert.IsTrue(TAtlasPinsFlow.HitAt([Hit(Pin(3, 'a'), 0, 20), Hit(Pin(3, 'b'), 10, 30)], Point(15, 5), mPin));
  Assert.AreEqual('b', mPin.Expression);
  Assert.IsFalse(TAtlasPinsFlow.HitAt([Hit(Pin(3, 'a'), 0, 20)], Point(25, 5), mPin));
  Assert.AreEqual('', mPin.Expression);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPinsFlowTests);

end.
