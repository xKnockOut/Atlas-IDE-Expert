unit Atlas.Core.Editor.MultiCursorKeys.Tests;

// Tasten und Klicks bei mehreren Einfügemarken (#589): Tabelle, Strg+K-Folge, Surrogate.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasMultiCursorKeysTests = class
  public
    [Test]
    procedure ArrowsMoveAndShiftExtends;
    [Test]
    procedure CtrlArrowsMoveByWord;
    [Test]
    procedure ExactRulesNeedExactModifiers;
    [Test]
    procedure ClipboardKeys;
    [Test]
    procedure OtherKeysStayWithTheIde;
    [Test]
    procedure ChordThenSkipKeySkips;
    [Test]
    procedure ChordWithoutSkipKeyIsOff;
    [Test]
    procedure ShortCutAddsModifierBits;
    [Test]
    procedure SurrogatePairsAreComposed;
    [Test]
    procedure ControlCharsInsertNothing;
    [Test]
    procedure ClickNeedsExactlyTheChosenModifier;
  end;

implementation

uses
  System.Classes,
  Atlas.Core.Editor.MultiCursor,
  Atlas.Core.Editor.MultiCursorKeys;

function ActionOf(AKey: Word; AShift: TShiftState): Integer;
begin
  Result := Ord(TAtlasMultiCursorKeys.Command(AKey, AShift).Action);
end;

{ TAtlasMultiCursorKeysTests }

procedure TAtlasMultiCursorKeysTests.ArrowsMoveAndShiftExtends;
var
  mCommand: TAtlasMultiCursorKeyCommand;
begin
  mCommand := TAtlasMultiCursorKeys.Command(TAtlasMultiCursorKeys.cKeyLeft, []);
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.Move), Ord(mCommand.Action));
  Assert.AreEqual(Ord(TAtlasCaretMove.Left), Ord(mCommand.Move));
  Assert.IsFalse(mCommand.Extend);
  mCommand := TAtlasMultiCursorKeys.Command(TAtlasMultiCursorKeys.cKeyEnd, [ssShift]);
  Assert.AreEqual(Ord(TAtlasCaretMove.LineEnd), Ord(mCommand.Move));
  Assert.IsTrue(mCommand.Extend, 'Umschalt erweitert die Markierung');
  mCommand := TAtlasMultiCursorKeys.Command(TAtlasMultiCursorKeys.cKeyBack, [ssShift]);
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.Backspace), Ord(mCommand.Action));
end;

procedure TAtlasMultiCursorKeysTests.CtrlArrowsMoveByWord;
var
  mCommand: TAtlasMultiCursorKeyCommand;
begin
  mCommand := TAtlasMultiCursorKeys.Command(TAtlasMultiCursorKeys.cKeyRight, [ssCtrl, ssShift]);
  Assert.AreEqual(Ord(TAtlasCaretMove.WordRight), Ord(mCommand.Move));
  Assert.IsTrue(mCommand.Extend);
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.None), ActionOf(TAtlasMultiCursorKeys.cKeyUp, [ssCtrl]),
    'Strg+↑ bleibt der IDE');
end;

procedure TAtlasMultiCursorKeysTests.ExactRulesNeedExactModifiers;
begin
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.Finish), ActionOf(TAtlasMultiCursorKeys.cKeyEscape, []));
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.None), ActionOf(TAtlasMultiCursorKeys.cKeyEscape, [ssShift]));
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.Delete), ActionOf(TAtlasMultiCursorKeys.cKeyDelete, []));
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.Cut), ActionOf(TAtlasMultiCursorKeys.cKeyDelete, [ssShift]));
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.None), ActionOf(TAtlasMultiCursorKeys.cKeyDelete, [ssCtrl]));
end;

procedure TAtlasMultiCursorKeysTests.ClipboardKeys;
begin
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.Copy), ActionOf(Ord('C'), [ssCtrl]));
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.Cut), ActionOf(Ord('X'), [ssCtrl]));
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.Paste), ActionOf(Ord('V'), [ssCtrl]));
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.Copy), ActionOf(TAtlasMultiCursorKeys.cKeyInsert, [ssCtrl]));
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.Paste), ActionOf(TAtlasMultiCursorKeys.cKeyInsert, [ssShift]));
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.None), ActionOf(Ord('V'), [ssCtrl, ssShift]));
end;

procedure TAtlasMultiCursorKeysTests.OtherKeysStayWithTheIde;
begin
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.None), ActionOf(Ord('A'), []));
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.None), ActionOf($09, []), 'Tab übernimmt die IDE');
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.None), ActionOf(TAtlasMultiCursorKeys.cKeyLeft, [ssAlt]));
end;

procedure TAtlasMultiCursorKeysTests.ChordThenSkipKeySkips;
var
  mChord: Boolean;
  mSkip: Integer;
begin
  mChord := False;
  mSkip := TAtlasMultiCursorKeys.ShortCutOf(Ord('D'), [ssCtrl]);
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.Chord), Ord(TAtlasMultiCursorKeys.Chord(mChord, Ord('K'),
    [ssCtrl], mSkip)));
  Assert.IsTrue(mChord);
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.Skip), Ord(TAtlasMultiCursorKeys.Chord(mChord, Ord('D'),
    [ssCtrl], mSkip)));
  Assert.IsFalse(mChord, 'nach dem Überspringen wieder von vorn');
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.None), Ord(TAtlasMultiCursorKeys.Chord(mChord, Ord('D'),
    [ssCtrl], mSkip)), 'ohne Strg+K davor nichts');
  TAtlasMultiCursorKeys.Chord(mChord, Ord('K'), [ssCtrl], mSkip);
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.None), Ord(TAtlasMultiCursorKeys.Chord(mChord, Ord('E'),
    [ssCtrl], mSkip)), 'andere Taste nach Strg+K wirkt normal');
  Assert.IsFalse(mChord);
end;

procedure TAtlasMultiCursorKeysTests.ChordWithoutSkipKeyIsOff;
var
  mChord: Boolean;
begin
  mChord := True;
  Assert.AreEqual(Ord(TAtlasMultiCursorKeyAction.None), Ord(TAtlasMultiCursorKeys.Chord(mChord, Ord('K'),
    [ssCtrl], 0)));
  Assert.IsFalse(mChord);
end;

procedure TAtlasMultiCursorKeysTests.ShortCutAddsModifierBits;
begin
  Assert.AreEqual($4044, TAtlasMultiCursorKeys.ShortCutOf(Ord('D'), [ssCtrl]));
  Assert.AreEqual($E041, TAtlasMultiCursorKeys.ShortCutOf(Ord('A'), [ssShift, ssCtrl, ssAlt]));
  Assert.AreEqual(0, TAtlasMultiCursorKeys.ShortCutOf($0141, []), 'Tasten über 255 haben kein Kürzel');
end;

procedure TAtlasMultiCursorKeysTests.SurrogatePairsAreComposed;
var
  mHigh: Char;
  mText: string;
begin
  mHigh := #0;
  Assert.IsFalse(TAtlasMultiCursorKeys.Compose(mHigh, #$D83D, mText), 'hohes Surrogat wartet');
  Assert.AreEqual(Ord(#$D83D), Ord(mHigh));
  Assert.IsTrue(TAtlasMultiCursorKeys.Compose(mHigh, #$DE00, mText));
  Assert.AreEqual(#$D83D#$DE00, mText);
  Assert.AreEqual(0, Ord(mHigh));
  Assert.IsTrue(TAtlasMultiCursorKeys.Compose(mHigh, 'a', mText));
  Assert.AreEqual('a', mText);
  Assert.IsTrue(TAtlasMultiCursorKeys.Compose(mHigh, #$DE00, mText), 'tiefes ohne hohes kommt allein');
  Assert.AreEqual(1, Length(mText));
end;

procedure TAtlasMultiCursorKeysTests.ControlCharsInsertNothing;
begin
  Assert.IsTrue(TAtlasMultiCursorKeys.IsControlChar(#9));
  Assert.IsTrue(TAtlasMultiCursorKeys.IsControlChar(#127));
  Assert.IsFalse(TAtlasMultiCursorKeys.IsControlChar(' '));
  Assert.IsFalse(TAtlasMultiCursorKeys.IsControlChar(#$E4));
end;

procedure TAtlasMultiCursorKeysTests.ClickNeedsExactlyTheChosenModifier;
begin
  Assert.IsTrue(TAtlasMultiCursorKeys.ClickWanted([ssAlt], False, True));
  Assert.IsFalse(TAtlasMultiCursorKeys.ClickWanted([ssAlt, ssShift], False, True));
  Assert.IsFalse(TAtlasMultiCursorKeys.ClickWanted([ssCtrl], False, True));
  Assert.IsTrue(TAtlasMultiCursorKeys.ClickWanted([ssCtrl], True, True));
  Assert.IsFalse(TAtlasMultiCursorKeys.ClickWanted([ssAlt], True, True));
  Assert.IsFalse(TAtlasMultiCursorKeys.ClickWanted([ssAlt], False, False), 'abgeschaltet');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMultiCursorKeysTests);

end.
