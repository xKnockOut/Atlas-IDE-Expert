unit Atlas.Core.Editor.ExitPointAsk.Tests;

// Wann Atlas nach Austrittspunkten fragt (#698): je Wort einmal nach einigen ruhigen Takten; Argumente.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Editor.ExitPointAsk;

type
  [TestFixture]
  TAtlasExitPointAskTests = class
  private
    FAsk: TAtlasExitPointAsk;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure AsksOnceAfterQuietTicks;
    [Test]
    procedure NewWordStartsOver;
    [Test]
    procedure ResetAllowsTheSameWordAgain;
    [Test]
    procedure KeyIgnoresTheCaretInsideTheWord;
    [Test]
    procedure ArgumentsCarryPositionAndSwitches;
  end;

implementation

{ TAtlasExitPointAskTests }

procedure TAtlasExitPointAskTests.Setup;
begin
  FAsk.Reset;
end;

procedure TAtlasExitPointAskTests.TearDown;
begin
  FAsk.Reset;
end;

procedure TAtlasExitPointAskTests.AsksOnceAfterQuietTicks;
begin
  Assert.IsFalse(FAsk.Due('a', 2), 'erster Takt merkt sich das Wort');
  Assert.IsFalse(FAsk.Due('a', 2));
  Assert.IsTrue(FAsk.Due('a', 2));
  Assert.IsFalse(FAsk.Due('a', 2), 'nur einmal je Wort');
end;

procedure TAtlasExitPointAskTests.NewWordStartsOver;
begin
  FAsk.Due('a', 1);
  Assert.IsTrue(FAsk.Due('a', 1));
  Assert.IsFalse(FAsk.Due('b', 1));
  Assert.IsTrue(FAsk.Due('b', 1));
  FAsk.Due('a', 1);
  Assert.IsTrue(FAsk.Due('a', 1), 'zurück auf ein früheres Wort fragt wieder');
end;

procedure TAtlasExitPointAskTests.ResetAllowsTheSameWordAgain;
begin
  FAsk.Due('a', 1);
  FAsk.Due('a', 1);
  FAsk.Reset;
  FAsk.Due('a', 1);
  Assert.IsTrue(FAsk.Due('a', 1));
end;

procedure TAtlasExitPointAskTests.KeyIgnoresTheCaretInsideTheWord;
begin
  Assert.AreEqual('C:\a.pas|3|10|4|1|0', TAtlasExitPointAsk.KeyOf('C:\a.pas', 3, 10, 4, True, False));
  Assert.AreNotEqual(TAtlasExitPointAsk.KeyOf('a.pas', 3, 10, 4, True, False),
    TAtlasExitPointAsk.KeyOf('a.pas', 4, 10, 4, True, False), 'neue Fassung');
end;

procedure TAtlasExitPointAskTests.ArgumentsCarryPositionAndSwitches;
begin
  Assert.AreEqual('["urn:a",{"line":3,"character":7},{"exceptions":true,"loops":false}]',
    TAtlasExitPointAsk.Arguments('urn:a', 3, 7, True, False));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExitPointAskTests);

end.
