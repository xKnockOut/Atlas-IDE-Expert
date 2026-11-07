unit Atlas.Core.Debug.ExceptionDialog.Tests;

// Tests der Erkennung des Exception-Dialogs der IDE (#517, #783): Text mit
// Klasse und „raised“/„aufgetreten“, Knöpfe „Anhalten“ und „Fortsetzen“
// (mit „&“ und „(F9)“), andere Dialoge, Dialog ohne „Fortsetzen“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugExceptionDialogTests = class
  public
    [Test]
    procedure ButtonKinds;
    [Test]
    procedure RecognizesEnglishDialog;
    [Test]
    procedure RecognizesGermanDialog;
    [Test]
    procedure OtherDialogIsNoException;
    [Test]
    procedure WithoutContinueCannotContinue;
  end;

implementation

uses
  Atlas.Core.Debug.ExceptionDialog;

{ TAtlasDebugExceptionDialogTests }

procedure TAtlasDebugExceptionDialogTests.ButtonKinds;
begin
  Assert.AreEqual(Ord(TAtlasDebugDialogButton.BreakButton), Ord(TAtlasDebugExceptionDialog.ButtonKind('&Break')));
  Assert.AreEqual(Ord(TAtlasDebugDialogButton.BreakButton), Ord(TAtlasDebugExceptionDialog.ButtonKind('Anhalten')));
  Assert.AreEqual(Ord(TAtlasDebugDialogButton.BreakButton),
    Ord(TAtlasDebugExceptionDialog.ButtonKind('Unter&brechen')));
  Assert.AreEqual(Ord(TAtlasDebugDialogButton.ContinueButton),
    Ord(TAtlasDebugExceptionDialog.ButtonKind('&Continue')));
  Assert.AreEqual(Ord(TAtlasDebugDialogButton.ContinueButton),
    Ord(TAtlasDebugExceptionDialog.ButtonKind(' Fortsetzen (F9) ')));
  Assert.AreEqual(Ord(TAtlasDebugDialogButton.Other), Ord(TAtlasDebugExceptionDialog.ButtonKind('&Hilfe')));
  Assert.AreEqual(Ord(TAtlasDebugDialogButton.Other), Ord(TAtlasDebugExceptionDialog.ButtonKind('')));
end;

procedure TAtlasDebugExceptionDialogTests.RecognizesEnglishDialog;
var
  mScan: TAtlasDebugDialogScan;
begin
  mScan := TAtlasDebugExceptionDialog.Recognize(TArray<string>.Create('Debugger Exception Notification',
    'Project Project1.exe raised exception class EConvertError with message ''''abc'' is not a valid integer ' +
    'value''.', 'Ignore this exception type'), TArray<string>.Create('&Break', '&Continue', '&Help'));
  Assert.IsTrue(mScan.HasException);
  Assert.AreEqual('EConvertError', mScan.ExceptionClass);
  Assert.AreEqual('''abc'' is not a valid integer value', mScan.Message);
  Assert.AreEqual(0, mScan.BreakIndex);
  Assert.AreEqual(1, mScan.ContinueIndex);
  Assert.IsTrue(mScan.CanContinue);
end;

procedure TAtlasDebugExceptionDialogTests.RecognizesGermanDialog;
var
  mScan: TAtlasDebugDialogScan;
begin
  mScan := TAtlasDebugExceptionDialog.Recognize(TArray<string>.Create('Im Projekt Project1.exe ist eine Exception ' +
    'der Klasse EAccessViolation mit der Meldung ''Zugriffsverletzung'' aufgetreten.'),
    TArray<string>.Create('&Hilfe', 'Fortsetzen', '&Anhalten'));
  Assert.AreEqual('EAccessViolation', mScan.ExceptionClass);
  Assert.AreEqual('Zugriffsverletzung', mScan.Message);
  Assert.AreEqual(2, mScan.BreakIndex);
  Assert.AreEqual(1, mScan.ContinueIndex);
  Assert.IsTrue(mScan.CanContinue);
end;

procedure TAtlasDebugExceptionDialogTests.OtherDialogIsNoException;
var
  mScan: TAtlasDebugDialogScan;
begin
  // Klasse im Text, aber kein Bericht der IDE über eine Exception.
  mScan := TAtlasDebugExceptionDialog.Recognize(TArray<string>.Create('Neue class TForm2 anlegen?'),
    TArray<string>.Create('OK', 'Abbrechen'));
  Assert.IsFalse(mScan.HasException);
  Assert.IsFalse(mScan.CanContinue);
  Assert.AreEqual(-1, mScan.BreakIndex);
  Assert.AreEqual(-1, mScan.ContinueIndex);
  mScan := TAtlasDebugExceptionDialog.Recognize(nil, nil);
  Assert.IsFalse(mScan.HasException);
end;

procedure TAtlasDebugExceptionDialogTests.WithoutContinueCannotContinue;
var
  mScan: TAtlasDebugDialogScan;
begin
  mScan := TAtlasDebugExceptionDialog.Recognize(TArray<string>.Create('Project X.exe raised exception class ' +
    'EAbort.'), TArray<string>.Create('OK'));
  Assert.IsTrue(mScan.HasException);
  Assert.IsFalse(mScan.CanContinue, 'ohne beide Knöpfe schließt Atlas den Dialog nie');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugExceptionDialogTests);

end.
