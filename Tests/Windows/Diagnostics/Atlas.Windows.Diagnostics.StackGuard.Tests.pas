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
function Exhaust(ADepth: Integer): Integer; // lsp-ignore: unconditional-recursion -- läuft absichtlich in den Stapelüberlauf
var
  Filler: array[0..255] of Integer;
begin
  Filler[ADepth mod 256] := ADepth;
  Result := Exhaust(ADepth + 1) + Filler[ADepth mod 256];
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
  Caught: Integer;
  Failure: string;
begin
  TWindowsStackGuard.Install;
  Caught := 0;
  Failure := TSmallStack.Run(256,
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
              raise;
            Inc(Caught);
            TStackGuard.AfterError(E);
          end;
        end;
    end);
  Assert.AreEqual('', Failure);
  Assert.AreEqual(3, Caught);
end;

initialization
  TDUnitX.RegisterTestFixture(TWindowsStackGuardTests);

end.
