unit Atlas.Tests.Wait;

// Warten in Tests auf einen Zustand, für den der Prüfling kein Ereignis anbietet (Zähler, Verbindungsstatus):
// an einer Stelle statt als Sleep-Schleife in jedem Test.

interface

uses
  System.SysUtils;

type
  TTestWait = record
  public const
    // Übliche Wartezeit von Synchronized.
    cSynchronizedMs = 3000;
  public
    /// <summary>Wartet, bis ACondition True liefert, höchstens ATimeoutMs; liefert das letzte Ergebnis.</summary>
    class function Reached(const ACondition: TFunc<Boolean>; ATimeoutMs: Integer): Boolean; static;
    /// <summary>
    ///   Arbeitet in den Hauptthread eingereihte Aufrufe ab (CheckSynchronize), bis ACondition True liefert,
    ///   höchstens ATimeoutMs (üblich drei Sekunden).
    /// </summary>
    class function Synchronized(const ACondition: TFunc<Boolean>; ATimeoutMs: Cardinal = cSynchronizedMs): Boolean;
      static;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics;

const
  // Abstand der Abfragen.
  cStepMs = 10;
  // Wartezeit je CheckSynchronize in Synchronized.
  cSynchronizeMs = 5;

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

class function TTestWait.Synchronized(const ACondition: TFunc<Boolean>; ATimeoutMs: Cardinal): Boolean;
var
  mStart: UInt64;
begin
  mStart := TThread.GetTickCount64;
  repeat
    CheckSynchronize(cSynchronizeMs);
    if ACondition() then
    begin
      Exit(True);
    end;
  until TThread.GetTickCount64 - mStart > ATimeoutMs;
  Result := False;
end;

end.
