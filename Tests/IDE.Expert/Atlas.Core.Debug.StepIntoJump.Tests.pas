unit Atlas.Core.Debug.StepIntoJump.Tests;

// Tests für den Ablauf von „Gezielt hineinspringen“ nach der Liste (#836, #1967): Angebot, Tasten, Auswahl,
// Haltepunkt auf der Folgeanweisung, Halt nach dem Sprung, Debug-DCUs; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasStepIntoJumpTests = class
  public
    [Test]
    procedure OfferFollowsRows;
    [Test]
    procedure KeysOfList;
    [Test]
    procedure AcceptOnlyAvailable;
    [Test]
    procedure FollowBreakUnlessTarget;
    [Test]
    procedure ArrivalKinds;
    [Test]
    procedure DebugDcusValue;
  end;

implementation

uses
  Atlas.Core.Debug.StepInto,
  Atlas.Core.Debug.StepIntoJump;

const
  cStart = 'C:\P\Main.pas';
  cTarget = 'C:\P\Kunden.pas';

function Row(AAvailable: Boolean): TAtlasStepRow;
begin
  Result := Default(TAtlasStepRow);
  Result.HasTarget := AAvailable;
  Result.Caption := 'TKunde.GetName';
  Result.Unavailable := TAtlasStepUnavailable.None;
end;

function Jump: TAtlasStepJump;
begin
  Result := Default(TAtlasStepJump);
  Result.StartFile := cStart;
  Result.StartLine := 10;
  Result.Target.FileName := cTarget;
  Result.Target.Line := 42;
  Result.FollowLine := 11;
end;

{ TAtlasStepIntoJumpTests }

procedure TAtlasStepIntoJumpTests.OfferFollowsRows;
begin
  Assert.AreEqual<TAtlasStepOffer>(TAtlasStepOffer.StepInto, TAtlasStepIntoJump.Offer(nil));
  Assert.AreEqual<TAtlasStepOffer>(TAtlasStepOffer.StepInto, TAtlasStepIntoJump.Offer([Row(True)]));
  Assert.AreEqual<TAtlasStepOffer>(TAtlasStepOffer.Nothing, TAtlasStepIntoJump.Offer([Row(False), Row(False)]));
  Assert.AreEqual<TAtlasStepOffer>(TAtlasStepOffer.List, TAtlasStepIntoJump.Offer([Row(False), Row(True)]));
end;

procedure TAtlasStepIntoJumpTests.KeysOfList;
var
  mDigit: Integer;
begin
  Assert.AreEqual<TAtlasStepKey>(TAtlasStepKey.Accept,
    TAtlasStepIntoJump.KeyOf(TAtlasStepIntoJump.cKeyReturn, mDigit));
  Assert.AreEqual<TAtlasStepKey>(TAtlasStepKey.Cancel,
    TAtlasStepIntoJump.KeyOf(TAtlasStepIntoJump.cKeyEscape, mDigit));
  Assert.AreEqual<TAtlasStepKey>(TAtlasStepKey.Up, TAtlasStepIntoJump.KeyOf(TAtlasStepIntoJump.cKeyUp, mDigit));
  Assert.AreEqual<TAtlasStepKey>(TAtlasStepKey.Down, TAtlasStepIntoJump.KeyOf(TAtlasStepIntoJump.cKeyDown, mDigit));
  Assert.AreEqual<TAtlasStepKey>(TAtlasStepKey.Digit, TAtlasStepIntoJump.KeyOf(Ord('3'), mDigit));
  Assert.AreEqual(3, mDigit);
  Assert.AreEqual<TAtlasStepKey>(TAtlasStepKey.Digit, TAtlasStepIntoJump.KeyOf(TAtlasStepIntoJump.cKeyNumpad9,
    mDigit));
  Assert.AreEqual(9, mDigit);
  Assert.AreEqual<TAtlasStepKey>(TAtlasStepKey.None, TAtlasStepIntoJump.KeyOf(Ord('0'), mDigit));
  Assert.AreEqual<TAtlasStepKey>(TAtlasStepKey.None, TAtlasStepIntoJump.KeyOf(Ord('A'), mDigit));
end;

procedure TAtlasStepIntoJumpTests.AcceptOnlyAvailable;
var
  mRows: TArray<TAtlasStepRow>;
begin
  mRows := [Row(True), Row(False)];
  Assert.IsTrue(TAtlasStepIntoJump.CanAccept(mRows, 0));
  Assert.IsFalse(TAtlasStepIntoJump.CanAccept(mRows, 1));
  Assert.IsFalse(TAtlasStepIntoJump.CanAccept(mRows, 2));
  Assert.IsFalse(TAtlasStepIntoJump.CanAccept(mRows, -1));
end;

procedure TAtlasStepIntoJumpTests.FollowBreakUnlessTarget;
var
  mJump: TAtlasStepJump;
begin
  mJump := Jump;
  Assert.IsTrue(mJump.NeedsFollowBreak(cStart));
  // Ziel ist selbst die Folgeanweisung (rekursiver Aufruf in der nächsten Zeile).
  mJump.Target.FileName := cStart;
  mJump.Target.Line := 11;
  Assert.IsFalse(mJump.NeedsFollowBreak(cStart));
  mJump := Jump;
  mJump.FollowLine := -1;
  Assert.IsFalse(mJump.NeedsFollowBreak(cStart));
end;

procedure TAtlasStepIntoJumpTests.ArrivalKinds;
var
  mJump: TAtlasStepJump;
begin
  mJump := Jump;
  Assert.AreEqual<TAtlasStepArrival>(TAtlasStepArrival.NotYet, mJump.Arrival('c:\p\main.pas', 10, cStart, True));
  Assert.AreEqual<TAtlasStepArrival>(TAtlasStepArrival.AtTarget, mJump.Arrival(cTarget, 42, cStart, True));
  Assert.AreEqual<TAtlasStepArrival>(TAtlasStepArrival.NotCalled, mJump.Arrival(cStart, 11, cStart, True));
  Assert.AreEqual<TAtlasStepArrival>(TAtlasStepArrival.Elsewhere, mJump.Arrival(cTarget, 50, cStart, True));
  Assert.AreEqual<TAtlasStepArrival>(TAtlasStepArrival.Other, mJump.Arrival(cTarget, 50, cStart, False));
  // Gelaufen und wieder am Start (Schleife): ein neuer Halt.
  mJump.SeenRunning := True;
  Assert.AreEqual<TAtlasStepArrival>(TAtlasStepArrival.Elsewhere, mJump.Arrival(cStart, 10, cStart, True));
end;

procedure TAtlasStepIntoJumpTests.DebugDcusValue;
begin
  Assert.IsTrue(TAtlasStepIntoJump.DebugDcus(' True '));
  Assert.IsFalse(TAtlasStepIntoJump.DebugDcus('false'));
  Assert.IsFalse(TAtlasStepIntoJump.DebugDcus(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStepIntoJumpTests);

end.
