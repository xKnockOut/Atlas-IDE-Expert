unit Atlas.Tests.Wait;

// Warten in Tests auf einen Zustand, für den der Prüfling kein Ereignis anbietet (Zähler, Verbindungsstatus):
// an einer Stelle statt als Sleep-Schleife in jedem Test.

interface

uses
  System.SysUtils;

type
  TTestWait = record
  public
    /// <summary>Wartet, bis ACondition True liefert, höchstens ATimeoutMs; liefert das letzte Ergebnis.</summary>
    class function Reached(const ACondition: TFunc<Boolean>; ATimeoutMs: Integer): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics;

const
  // Abstand der Abfragen.
  cStepMs = 10;

class function TTestWait.Reached(const ACondition: TFunc<Boolean>; ATimeoutMs: Integer): Boolean;
var
  mWatch: TStopwatch;
begin
  mWatch := TStopwatch.StartNew;
  Result := ACondition();
  while not Result and (mWatch.ElapsedMilliseconds < ATimeoutMs) do
  begin
    TThread.Sleep(cStepMs);
    Result := ACondition();
  end;
end;

end.
