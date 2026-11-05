unit Atlas.Core.Commands.KeyStroke.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Ein Tastendruck löst einen Befehl nur einmal aus, auch wenn Kontextmenü und Tastaturbindung ihn
  /// beide erhalten.</summary>
  [TestFixture]
  TAtlasKeyStrokeTests = class
  public
    [Setup]
    procedure Setup;
    [Test]
    procedure SecondReceiverOfSameStrokeSkips;
    [Test]
    procedure RepeatedKeyHasNewTime;
    [Test]
    procedure OtherKeyAtSameTimeRuns;
    [Test]
    procedure WithoutShortCutAlwaysRuns;
  end;

implementation

uses
  Atlas.Core.Commands.KeyStroke;

const
  cCtrlAltL = $6000 or Ord('L');
  cCtrlAltK = $6000 or Ord('K');

procedure TAtlasKeyStrokeTests.Setup;
begin
  TAtlasKeyStroke.Reset;
end;

procedure TAtlasKeyStrokeTests.SecondReceiverOfSameStrokeSkips;
begin
  Assert.IsTrue(TAtlasKeyStroke.Claim(cCtrlAltL, 1000), 'Tastaturbindung zuerst');
  Assert.IsFalse(TAtlasKeyStroke.Claim(cCtrlAltL, 1000), 'Menü bei demselben Tastendruck');
end;

procedure TAtlasKeyStrokeTests.RepeatedKeyHasNewTime;
begin
  Assert.IsTrue(TAtlasKeyStroke.Claim(cCtrlAltL, 1000));
  Assert.IsTrue(TAtlasKeyStroke.Claim(cCtrlAltL, 1033), 'Wiederholung der gehaltenen Taste');
  Assert.IsFalse(TAtlasKeyStroke.Claim(cCtrlAltL, 1033));
end;

procedure TAtlasKeyStrokeTests.OtherKeyAtSameTimeRuns;
begin
  Assert.IsTrue(TAtlasKeyStroke.Claim(cCtrlAltL, 1000));
  Assert.IsTrue(TAtlasKeyStroke.Claim(cCtrlAltK, 1000));
end;

procedure TAtlasKeyStrokeTests.WithoutShortCutAlwaysRuns;
begin
  Assert.IsTrue(TAtlasKeyStroke.Claim(0, 1000));
  Assert.IsTrue(TAtlasKeyStroke.Claim(0, 1000));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasKeyStrokeTests);

end.
