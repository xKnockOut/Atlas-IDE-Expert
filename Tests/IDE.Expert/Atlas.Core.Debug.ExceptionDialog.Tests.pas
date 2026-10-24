unit Atlas.Core.Debug.ExceptionDialog.Tests;

// Tests der Erkennung des Exception-Dialogs der IDE (#517, #783): Text mit
// Klasse und „raised“/„aufgetreten“, Knöpfe „Anhalten“ und „Fortsetzen“
// (mit „&“ und „(F9)“), andere Dialoge, Dialog ohne „Fortsetzen“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
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
  Scan: TAtlasDebugDialogScan;
begin
  Scan := TAtlasDebugExceptionDialog.Recognize(TArray<string>.Create('Debugger Exception Notification',
    'Project Project1.exe raised exception class EConvertError with message ''''abc'' is not a valid integer ' +
    'value''.', 'Ignore this exception type'), TArray<string>.Create('&Break', '&Continue', '&Help'));
  Assert.IsTrue(Scan.HasException);
  Assert.AreEqual('EConvertError', Scan.ExceptionClass);
  Assert.AreEqual('''abc'' is not a valid integer value', Scan.Message);
  Assert.AreEqual(0, Scan.BreakIndex);
  Assert.AreEqual(1, Scan.ContinueIndex);
  Assert.IsTrue(Scan.CanContinue);
end;

procedure TAtlasDebugExceptionDialogTests.RecognizesGermanDialog;
var
  Scan: TAtlasDebugDialogScan;
begin
  Scan := TAtlasDebugExceptionDialog.Recognize(TArray<string>.Create('Im Projekt Project1.exe ist eine Exception ' +
    'der Klasse EAccessViolation mit der Meldung ''Zugriffsverletzung'' aufgetreten.'),
    TArray<string>.Create('&Hilfe', 'Fortsetzen', '&Anhalten'));
  Assert.AreEqual('EAccessViolation', Scan.ExceptionClass);
  Assert.AreEqual('Zugriffsverletzung', Scan.Message);
  Assert.AreEqual(2, Scan.BreakIndex);
  Assert.AreEqual(1, Scan.ContinueIndex);
  Assert.IsTrue(Scan.CanContinue);
end;

procedure TAtlasDebugExceptionDialogTests.OtherDialogIsNoException;
var
  Scan: TAtlasDebugDialogScan;
begin
  // Klasse im Text, aber kein Bericht der IDE über eine Exception.
  Scan := TAtlasDebugExceptionDialog.Recognize(TArray<string>.Create('Neue class TForm2 anlegen?'),
    TArray<string>.Create('OK', 'Abbrechen'));
  Assert.IsFalse(Scan.HasException);
  Assert.IsFalse(Scan.CanContinue);
  Assert.AreEqual(-1, Scan.BreakIndex);
  Assert.AreEqual(-1, Scan.ContinueIndex);
  Scan := TAtlasDebugExceptionDialog.Recognize(nil, nil);
  Assert.IsFalse(Scan.HasException);
end;

procedure TAtlasDebugExceptionDialogTests.WithoutContinueCannotContinue;
var
  Scan: TAtlasDebugDialogScan;
begin
  Scan := TAtlasDebugExceptionDialog.Recognize(TArray<string>.Create('Project X.exe raised exception class ' +
    'EAbort.'), TArray<string>.Create('OK'));
  Assert.IsTrue(Scan.HasException);
  Assert.IsFalse(Scan.CanContinue, 'ohne beide Knöpfe schließt Atlas den Dialog nie');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugExceptionDialogTests);

end.
