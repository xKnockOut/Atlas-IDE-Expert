unit Atlas.Core.Editor.GutterMarks.Tests;

// Tests für die Entscheidungen der Zeichenschicht der Rinne (#401, #1967): wann die Schichten neu verankern,
// wie lange ein Rechtsklick in die Rinne gilt und wo die Symbole einer Rinnenzeile liegen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasGutterMarksTests = class
  public
    [Test]
    procedure FirstLookIsNewFile;
    [Test]
    procedure SameTextDoesNothing;
    [Test]
    procedure ChangeRetracksAfterQuietPauseOnce;
    [Test]
    procedure TypingRestartsQuietPause;
    [Test]
    procedure OtherFileIsNewFileCaseInsensitive;
    [Test]
    procedure ResetMakesNextLookNewFile;
    [Test]
    procedure ClickLineForSameFileWithinTime;
    [Test]
    procedure ClickLineExpires;
    [Test]
    procedure ClickLineOtherFileIsForgotten;
    [Test]
    procedure ClickLineWithoutClick;
    [Test]
    procedure IconRectFollowsRowHeight;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Editor.GutterMarks;

{ TAtlasGutterMarksTests }

procedure TAtlasGutterMarksTests.FirstLookIsNewFile;
var
  mTracker: TAtlasGutterTracker;
begin
  mTracker := Default(TAtlasGutterTracker);
  Assert.AreEqual(Ord(TAtlasGutterTrackAction.NewFile), Ord(mTracker.Step('C:\a\Unit1.pas', 'x', 1000)));
  Assert.AreEqual('C:\a\Unit1.pas', mTracker.FileName);
  Assert.AreEqual('x', mTracker.Text);
end;

procedure TAtlasGutterMarksTests.SameTextDoesNothing;
var
  mTracker: TAtlasGutterTracker;
begin
  mTracker := Default(TAtlasGutterTracker);
  mTracker.Step('C:\a\Unit1.pas', 'x', 1000);
  Assert.AreEqual(Ord(TAtlasGutterTrackAction.None), Ord(mTracker.Step('C:\a\Unit1.pas', 'x', 5000)));
end;

procedure TAtlasGutterMarksTests.ChangeRetracksAfterQuietPauseOnce;
var
  mTracker: TAtlasGutterTracker;
begin
  mTracker := Default(TAtlasGutterTracker);
  mTracker.Step('C:\a\Unit1.pas', 'x', 1000);
  Assert.AreEqual(Ord(TAtlasGutterTrackAction.None), Ord(mTracker.Step('C:\a\Unit1.pas', 'xy', 2000)));
  Assert.AreEqual(Ord(TAtlasGutterTrackAction.None),
    Ord(mTracker.Step('C:\a\Unit1.pas', 'xy', 2000 + TAtlasGutterTracker.cQuietMs - 1)));
  Assert.AreEqual(Ord(TAtlasGutterTrackAction.Retrack),
    Ord(mTracker.Step('C:\a\Unit1.pas', 'xy', 2000 + TAtlasGutterTracker.cQuietMs)));
  Assert.AreEqual('xy', mTracker.Text);
  Assert.AreEqual(Ord(TAtlasGutterTrackAction.None), Ord(mTracker.Step('C:\a\Unit1.pas', 'xy', 9000)));
end;

procedure TAtlasGutterMarksTests.TypingRestartsQuietPause;
var
  mTracker: TAtlasGutterTracker;
begin
  mTracker := Default(TAtlasGutterTracker);
  mTracker.Step('C:\a\Unit1.pas', 'x', 1000);
  mTracker.Step('C:\a\Unit1.pas', 'xy', 2000);
  mTracker.Step('C:\a\Unit1.pas', 'xyz', 2200);
  Assert.AreEqual(Ord(TAtlasGutterTrackAction.None), Ord(mTracker.Step('C:\a\Unit1.pas', 'xyz', 2400)));
  Assert.AreEqual(Ord(TAtlasGutterTrackAction.Retrack), Ord(mTracker.Step('C:\a\Unit1.pas', 'xyz', 2500)));
end;

procedure TAtlasGutterMarksTests.OtherFileIsNewFileCaseInsensitive;
var
  mTracker: TAtlasGutterTracker;
begin
  mTracker := Default(TAtlasGutterTracker);
  mTracker.Step('C:\a\Unit1.pas', 'x', 1000);
  Assert.AreEqual(Ord(TAtlasGutterTrackAction.None), Ord(mTracker.Step('c:\A\UNIT1.PAS', 'x', 1100)));
  Assert.AreEqual(Ord(TAtlasGutterTrackAction.NewFile), Ord(mTracker.Step('C:\a\Unit2.pas', 'y', 1200)));
  Assert.AreEqual('C:\a\Unit2.pas', mTracker.FileName);
end;

procedure TAtlasGutterMarksTests.ResetMakesNextLookNewFile;
var
  mTracker: TAtlasGutterTracker;
begin
  mTracker := Default(TAtlasGutterTracker);
  mTracker.Step('C:\a\Unit1.pas', 'x', 1000);
  mTracker.Reset;
  Assert.AreEqual('', mTracker.FileName);
  Assert.AreEqual(Ord(TAtlasGutterTrackAction.NewFile), Ord(mTracker.Step('C:\a\Unit1.pas', 'x', 1100)));
end;

procedure TAtlasGutterMarksTests.ClickLineForSameFileWithinTime;
var
  mClick: TAtlasGutterClickLine;
  mLine: Integer;
begin
  mClick := Default(TAtlasGutterClickLine);
  mClick.Remember('C:\a\Unit1.pas', 41, 1000);
  // Schreibweise und / statt \ zählen nicht.
  Assert.IsTrue(mClick.Take('c:/A/UNIT1.pas', 1000 + TAtlasGutterClickLine.cLineMs, mLine));
  Assert.AreEqual(41, mLine);
  // Ein Befehl verbraucht den Klick.
  Assert.IsFalse(mClick.Take('C:\a\Unit1.pas', 1001, mLine));
  Assert.AreEqual(-1, mLine);
end;

procedure TAtlasGutterMarksTests.ClickLineExpires;
var
  mClick: TAtlasGutterClickLine;
  mLine: Integer;
begin
  mClick := Default(TAtlasGutterClickLine);
  mClick.Remember('C:\a\Unit1.pas', 41, 1000);
  Assert.IsFalse(mClick.Take('C:\a\Unit1.pas', 1001 + TAtlasGutterClickLine.cLineMs, mLine));
  Assert.AreEqual(-1, mLine);
end;

procedure TAtlasGutterMarksTests.ClickLineOtherFileIsForgotten;
var
  mClick: TAtlasGutterClickLine;
  mLine: Integer;
begin
  mClick := Default(TAtlasGutterClickLine);
  mClick.Remember('C:\a\Unit1.pas', 7, 1000);
  Assert.IsFalse(mClick.Take('C:\a\Unit2.pas', 1100, mLine));
  Assert.AreEqual(-1, mLine);
  Assert.IsFalse(mClick.Take('C:\a\Unit1.pas', 1200, mLine));
end;

procedure TAtlasGutterMarksTests.ClickLineWithoutClick;
var
  mClick: TAtlasGutterClickLine;
  mLine: Integer;
begin
  mClick := Default(TAtlasGutterClickLine);
  Assert.IsFalse(mClick.Take('', 0, mLine));
  mClick.Remember('C:\a\Unit1.pas', -1, 1000);
  Assert.IsFalse(mClick.Take('C:\a\Unit1.pas', 1000, mLine));
  mClick.Remember('C:\a\Unit1.pas', 3, 1000);
  mClick.Forget;
  Assert.IsFalse(mClick.Take('C:\a\Unit1.pas', 1000, mLine));
end;

procedure TAtlasGutterMarksTests.IconRectFollowsRowHeight;
var
  mRect: TRect;
begin
  // Zeile 18 hoch: Symbol 14 hoch (Obergrenze), 11 breit, mittig.
  mRect := TAtlasGutterLayout.IconRect(TRect.Create(10, 100, 40, 118), 0);
  Assert.AreEqual(12, mRect.Left);
  Assert.AreEqual(102, mRect.Top);
  Assert.AreEqual(11, mRect.Width);
  Assert.AreEqual(14, mRect.Height);
  // Zweites Symbol: Breite plus 2 Punkte weiter rechts.
  Assert.AreEqual(25, TAtlasGutterLayout.IconRect(TRect.Create(10, 100, 40, 118), 1).Left);
  // Sehr niedrige Zeile: mindestens 6 hoch und 5 breit; negativer Platz zählt wie 0.
  mRect := TAtlasGutterLayout.IconRect(TRect.Create(0, 0, 20, 4), -3);
  Assert.AreEqual(2, mRect.Left);
  Assert.AreEqual(5, mRect.Width);
  Assert.AreEqual(6, mRect.Height);
  Assert.AreEqual(-1, mRect.Top);
end;

end.
