unit Atlas.Core.Debug.AccessViolation.Stop.Tests;

// Tests für den Ablauf von „Zugriffsverletzung erklären“ am Halt (#865, #1967): Ort und Kopfzeile, nur das Modul,
// Warten auf den Dialog der IDE, Fehlschlag der Zerlegung, unterstrichener Bereich; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasAvStopTests = class
  public
    [Test]
    procedure PlaceAndHeader;
    [Test]
    procedure ModuleOnlyWithoutOwnSource;
    [Test]
    procedure WaitsForQuietTicks;
    [Test]
    procedure DropsWhenResumedOrTooLate;
    [Test]
    procedure FailureOfChains;
    [Test]
    procedure UnderlinesCulprit;
  end;

implementation

uses
  Atlas.Core.Lsp.AccessChains,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.AccessViolation;

function Culprit(AStartLine, AStart, AEndLine, AEnd: Integer): TAtlasAvVerdict;
begin
  Result := Default(TAtlasAvVerdict);
  Result.HasCulprit := True;
  Result.Culprit.StartLine := AStartLine;
  Result.Culprit.StartCharacter := AStart;
  Result.Culprit.EndLine := AEndLine;
  Result.Culprit.EndCharacter := AEnd;
end;

{ TAtlasAvStopTests }

procedure TAtlasAvStopTests.PlaceAndHeader;
var
  mException: TAtlasDebugException;
begin
  Assert.AreEqual('Kunden.pas:12', TAtlasAvStop.Place('Kunden.pas', 11));
  Assert.AreEqual('vcl290.bpl', TAtlasAvStop.Place('vcl290.bpl', -1));
  mException := Default(TAtlasDebugException);
  mException.ExceptionClass := 'EAccessViolation';
  mException.Message := 'Zugriffsverletzung';
  Assert.AreEqual('EAccessViolation: Zugriffsverletzung (Kunden.pas:12)', TAtlasAvStop.Header(mException,
    'Kunden.pas:12'));
  mException.Message := '';
  Assert.AreEqual('EAccessViolation (Kunden.pas:12)', TAtlasAvStop.Header(mException, 'Kunden.pas:12'));
end;

procedure TAtlasAvStopTests.ModuleOnlyWithoutOwnSource;
var
  mFrame: TAtlasDebugFrame;
begin
  Assert.IsTrue(TAtlasAvStop.ModuleOnly(nil));
  mFrame := TAtlasDebugFrame.Create('Kunden.TKunde.Laden', 'Kunden.pas', 12);
  Assert.IsTrue(TAtlasAvStop.ModuleOnly([mFrame]));
  mFrame.Own := True;
  Assert.IsFalse(TAtlasAvStop.ModuleOnly([mFrame]));
  Assert.IsTrue(TAtlasAvStop.ModuleOnly([TAtlasDebugFrame.Create('System.Move', '', 0)]));
end;

procedure TAtlasAvStopTests.WaitsForQuietTicks;
var
  mQuiet: Integer;
begin
  mQuiet := 0;
  Assert.AreEqual<TAtlasAvWaitStep>(TAtlasAvWaitStep.Wait, TAtlasAvStop.WaitStep(True, 10, 1000, False, mQuiet));
  Assert.AreEqual(1, mQuiet);
  // Ein Dialog dazwischen setzt die ruhigen Takte zurück.
  Assert.AreEqual<TAtlasAvWaitStep>(TAtlasAvWaitStep.Wait, TAtlasAvStop.WaitStep(True, 20, 1000, True, mQuiet));
  Assert.AreEqual(0, mQuiet);
  Assert.AreEqual<TAtlasAvWaitStep>(TAtlasAvWaitStep.Wait, TAtlasAvStop.WaitStep(True, 30, 1000, False, mQuiet));
  Assert.AreEqual<TAtlasAvWaitStep>(TAtlasAvWaitStep.Go, TAtlasAvStop.WaitStep(True, 40, 1000, False, mQuiet));
end;

procedure TAtlasAvStopTests.DropsWhenResumedOrTooLate;
var
  mQuiet: Integer;
begin
  mQuiet := 5;
  Assert.AreEqual<TAtlasAvWaitStep>(TAtlasAvWaitStep.Drop, TAtlasAvStop.WaitStep(False, 10, 1000, False, mQuiet));
  Assert.AreEqual<TAtlasAvWaitStep>(TAtlasAvWaitStep.Drop, TAtlasAvStop.WaitStep(True, 1001, 1000, False, mQuiet));
  Assert.AreEqual<TAtlasAvWaitStep>(TAtlasAvWaitStep.Go, TAtlasAvStop.WaitStep(True, 1000, 1000, False, mQuiet));
end;

procedure TAtlasAvStopTests.FailureOfChains;
var
  mChains: TAtlasAvChains;
begin
  mChains := Default(TAtlasAvChains);
  Assert.AreEqual<TAtlasAvFailure>(TAtlasAvFailure.NoServer, TAtlasAvStop.Failure(mChains));
  mChains.Found := True;
  Assert.AreEqual<TAtlasAvFailure>(TAtlasAvFailure.NoChains, TAtlasAvStop.Failure(mChains));
  SetLength(mChains.Chains, 1);
  Assert.AreEqual<TAtlasAvFailure>(TAtlasAvFailure.None, TAtlasAvStop.Failure(mChains));
end;

procedure TAtlasAvStopTests.UnderlinesCulprit;
var
  mRange: TAtlasAvUnderlineRange;
  mLines: TArray<string>;
begin
  mLines := TArray<string>.Create('  Kunde.Adresse.Ort := ''x'';   ', '  Liste[I]');
  Assert.IsTrue(TAtlasAvStop.Underline(Culprit(0, 2, 0, 15), mLines, mRange));
  Assert.AreEqual(0, mRange.Line);
  Assert.AreEqual(2, mRange.StartCharacter);
  Assert.AreEqual(15, mRange.EndCharacter);
  // Über mehrere Zeilen: bis zum Ende der ersten ohne Leerzeichen.
  Assert.IsTrue(TAtlasAvStop.Underline(Culprit(0, 2, 1, 4), mLines, mRange));
  Assert.AreEqual(27, mRange.EndCharacter);
  Assert.IsFalse(TAtlasAvStop.Underline(Culprit(2, 0, 2, 1), mLines, mRange));
  Assert.IsFalse(TAtlasAvStop.Underline(Culprit(0, 0, 0, 1), nil, mRange));
  Assert.IsFalse(TAtlasAvStop.Underline(Default(TAtlasAvVerdict), mLines, mRange));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAvStopTests);

end.
