unit Atlas.Core.Editor.MouseButtons.Tests;

// Zurück-/Vor-Taste der Maus (#1889): Nachricht → Richtung im Verlauf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasMouseButtonsTests = class
  public
    [Test]
    procedure XButtonsMapToDirections;
    [Test]
    procedure AppCommandsMapToDirections;
    [Test]
    procedure OtherMessagesAreNone;
  end;

implementation

uses
  Atlas.Core.Editor.MouseButtons;

function Dir(AMessage: Cardinal; AWParam, ALParam: NativeInt): Integer;
begin
  Result := Ord(TAtlasMouseButtons.DirectionOf(AMessage, AWParam, ALParam));
end;

procedure TAtlasMouseButtonsTests.XButtonsMapToDirections;
begin
  Assert.AreEqual(Ord(TAtlasNavDirection.Back), Dir($020C, $00010000, 0));
  Assert.AreEqual(Ord(TAtlasNavDirection.Forward), Dir($020C, $00020000 or $0008, 0));
end;

procedure TAtlasMouseButtonsTests.AppCommandsMapToDirections;
begin
  // Gerätebit FAPPKEY_MOUSE (0x8000) im oberen Wort fällt weg.
  Assert.AreEqual(Ord(TAtlasNavDirection.Back), Dir($0319, 0, NativeInt($80010000)));
  Assert.AreEqual(Ord(TAtlasNavDirection.Forward), Dir($0319, 0, $00020000));
end;

procedure TAtlasMouseButtonsTests.OtherMessagesAreNone;
begin
  Assert.AreEqual(Ord(TAtlasNavDirection.None), Dir($020C, $00030000, 0));
  Assert.AreEqual(Ord(TAtlasNavDirection.None), Dir($020B, $00010000, 0), 'Drücken zählt nicht');
  Assert.AreEqual(Ord(TAtlasNavDirection.None), Dir($0319, 0, $00080000), 'anderer Befehl');
  Assert.AreEqual(Ord(TAtlasNavDirection.None), Dir($0201, 0, 0));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMouseButtonsTests);

end.
