unit Atlas.Windows.Diagnostics.StackGuard.Tests;

// Tests für TWindowsStackGuard (#1094): Nach einem abgefangenen Stapelüberlauf
// setzt die Wiederherstellung die Schutzseite neu, und ein zweiter Überlauf im
// selben Thread kommt wieder als EStackOverflow an. Ohne Wiederherstellung
// beendet Windows beim zweiten Überlauf den Prozess; genau das trat im Server
// nach einigen Läufen von workspace/diagnostic auf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TWindowsStackGuardTests = class
  public
    [TearDown]
    procedure RemoveGuard;
    [Test]
    procedure InstallSetsRestore;
    [Test]
    procedure SecondOverflowInSameThreadIsCaughtAgain;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Diagnostics.StackGuard,
  Atlas.Windows.Diagnostics.StackGuard,
  Atlas.Tests.SmallStack;

/// <summary>Verbraucht Stapel, bis er überläuft; ADepth verhindert, dass der Compiler die Rekursion
/// wegoptimiert.</summary>
function Exhaust(ADepth: Integer): Integer; // lsp-ignore: unconditional-recursion -- absichtlicher Stapelüberlauf
var
  mFiller: array[0..255] of Integer;
begin
  mFiller[ADepth mod 256] := ADepth;
  Result := Exhaust(ADepth + 1) + mFiller[ADepth mod 256];
end;

procedure TWindowsStackGuardTests.RemoveGuard;
begin
  TWindowsStackGuard.Uninstall;
end;

procedure TWindowsStackGuardTests.InstallSetsRestore;
begin
  TWindowsStackGuard.Install;
  Assert.IsTrue(Assigned(TStackGuard.Restore));
  TWindowsStackGuard.Uninstall;
  Assert.IsFalse(Assigned(TStackGuard.Restore));
end;

procedure TWindowsStackGuardTests.SecondOverflowInSameThreadIsCaughtAgain;
var
  mCaught: Integer;
  mFailure: string;
begin
  TWindowsStackGuard.Install;
  mCaught := 0;
  mFailure := TSmallStack.Run(256,
    procedure
    var
      Round: Integer;
    begin
      for Round := 1 to 3 do
        try
          Exhaust(0);
        except
          on E: Exception do
          begin
            // Nicht „on E: EStackOverflow“: In Delphi 13 veraltet (W1000).
            if not TStackGuard.IsOverflow(E) then
            begin
              raise;
            end;
            Inc(mCaught);
            TStackGuard.AfterError(E);
          end;
        end;
    end);
  Assert.AreEqual('', mFailure);
  Assert.AreEqual(3, mCaught);
end;

initialization
  TDUnitX.RegisterTestFixture(TWindowsStackGuardTests);

end.
