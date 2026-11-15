unit Atlas.Core.Editor.LinkedKeys.Tests;

// Tasten beim Mitziehen eines Bezeichners (#658): Esc, Enter, Rücktaste, Entf und Zeichen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasLinkedKeysTests = class
  public
    [Test]
    procedure EscapeFinishesAndRestoresOnConflict;
    [Test]
    procedure ReturnFinishesOnlyARunningSession;
    [Test]
    procedure BackspaceAndDeleteEditTheName;
    [Test]
    procedure ModifiersLeaveTheKeyToTheIde;
    [Test]
    procedure IdentifierCharsAreInserted;
    [Test]
    procedure OtherCharsFinish;
    [Test]
    procedure SurrogatesWaitForTheirPair;
  end;

implementation

uses
  Atlas.Core.Editor.LinkedKeys;

function KeyStep(AKey: Word; AModified, AActive, AProblem: Boolean): Integer;
begin
  Result := Ord(TAtlasLinkedKeys.KeyStep(AKey, AModified, AActive, AProblem));
end;

function CharStep(ATyped: Char; AHighPending: Boolean): Integer;
begin
  Result := Ord(TAtlasLinkedKeys.CharStep(ATyped, AHighPending));
end;

{ TAtlasLinkedKeysTests }

procedure TAtlasLinkedKeysTests.EscapeFinishesAndRestoresOnConflict;
begin
  Assert.AreEqual(Ord(TAtlasLinkedKeyStep.Finish), KeyStep(TAtlasLinkedKeys.cKeyEscape, False, True, False));
  Assert.AreEqual(Ord(TAtlasLinkedKeyStep.RestoreAndFinish), KeyStep(TAtlasLinkedKeys.cKeyEscape, False, True,
    True));
  Assert.AreEqual(Ord(TAtlasLinkedKeyStep.Pass), KeyStep(TAtlasLinkedKeys.cKeyEscape, False, False, True),
    'ohne Sitzung gehört Esc der IDE');
end;

procedure TAtlasLinkedKeysTests.ReturnFinishesOnlyARunningSession;
begin
  Assert.AreEqual(Ord(TAtlasLinkedKeyStep.Finish), KeyStep(TAtlasLinkedKeys.cKeyReturn, False, True, True));
  Assert.AreEqual(Ord(TAtlasLinkedKeyStep.Pass), KeyStep(TAtlasLinkedKeys.cKeyReturn, False, False, False));
end;

procedure TAtlasLinkedKeysTests.BackspaceAndDeleteEditTheName;
begin
  Assert.AreEqual(Ord(TAtlasLinkedKeyStep.Backspace), KeyStep(TAtlasLinkedKeys.cKeyBack, False, False, False),
    'die Rücktaste kann die Sitzung beginnen');
  Assert.AreEqual(Ord(TAtlasLinkedKeyStep.Delete), KeyStep(TAtlasLinkedKeys.cKeyDelete, False, True, False));
  Assert.AreEqual(Ord(TAtlasLinkedKeyStep.Pass), KeyStep($41, False, True, False), 'Buchstaben kommen als Zeichen');
end;

procedure TAtlasLinkedKeysTests.ModifiersLeaveTheKeyToTheIde;
begin
  Assert.AreEqual(Ord(TAtlasLinkedKeyStep.Pass), KeyStep(TAtlasLinkedKeys.cKeyBack, True, True, False));
  Assert.AreEqual(Ord(TAtlasLinkedKeyStep.Pass), KeyStep(TAtlasLinkedKeys.cKeyEscape, True, True, True));
  Assert.AreEqual(Ord(TAtlasLinkedKeyStep.Pass), KeyStep(TAtlasLinkedKeys.cKeyControl, False, True, False));
  Assert.AreEqual(Ord(TAtlasLinkedKeyStep.Pass), KeyStep(TAtlasLinkedKeys.cKeyShift, False, True, False));
end;

procedure TAtlasLinkedKeysTests.IdentifierCharsAreInserted;
begin
  Assert.AreEqual(Ord(TAtlasLinkedCharStep.Insert), CharStep('a', False));
  Assert.AreEqual(Ord(TAtlasLinkedCharStep.Insert), CharStep('_', False));
  Assert.AreEqual(Ord(TAtlasLinkedCharStep.Insert), CharStep('7', False));
  Assert.AreEqual(Ord(TAtlasLinkedCharStep.Insert), CharStep(#$E4, False), 'Umlaute gehören zum Bezeichner');
end;

procedure TAtlasLinkedKeysTests.OtherCharsFinish;
begin
  Assert.AreEqual(Ord(TAtlasLinkedCharStep.Finish), CharStep(' ', False));
  Assert.AreEqual(Ord(TAtlasLinkedCharStep.Finish), CharStep('.', False));
  Assert.AreEqual(Ord(TAtlasLinkedCharStep.Finish), CharStep('(', False));
  Assert.AreEqual(Ord(TAtlasLinkedCharStep.Ignore), CharStep(#8, False));
  Assert.AreEqual(Ord(TAtlasLinkedCharStep.Ignore), CharStep(#127, True));
end;

procedure TAtlasLinkedKeysTests.SurrogatesWaitForTheirPair;
begin
  Assert.AreEqual(Ord(TAtlasLinkedCharStep.HighSurrogate), CharStep(#$D835, False));
  Assert.AreEqual(Ord(TAtlasLinkedCharStep.HighSurrogate), CharStep(#$D835, True));
  Assert.AreEqual(Ord(TAtlasLinkedCharStep.LowSurrogate), CharStep(#$DC00, True));
  Assert.AreNotEqual(Ord(TAtlasLinkedCharStep.LowSurrogate), CharStep(#$DC00, False), 'tiefes ohne hohes');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLinkedKeysTests);

end.
