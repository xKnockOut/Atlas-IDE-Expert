unit Atlas.Core.Diagnostics.Deadline;

// Zeitpunkte und Fristen auf dem 64-Bit-Tickzähler. Der 32-Bit-Zähler
// (GetTickCount, TThread.GetTickCount) läuft nach 49,7 Tagen Betriebszeit des
// Rechners über. Eine Differenz übersteht das, ein absoluter Vergleich wie
// "Jetzt >= Frist" nicht: Wird die Frist kurz vor dem Überlauf gesetzt, ist sie
// danach 49 Tage lang nicht erreicht. TThread.GetTickCount64 läuft praktisch
// nie über. Der Zähler lässt sich für Tests ersetzen (SetClock).

interface

uses
  System.SysUtils;

type
  /// <summary>Millisekunden seit dem Systemstart, 64 Bit.</summary>
  TAtlasTicks = record
  private class var
    FClock: TFunc<UInt64>;
  public
    /// <summary>Aktueller Stand des Zählers.</summary>
    class function Now: UInt64; static;
    /// <summary>Millisekunden seit AStart (Stand von Now); 0, wenn AStart in der Zukunft liegt.</summary>
    class function Since(AStart: UInt64): UInt64; static;
    /// <summary>Wie Since, auf High(Cardinal) begrenzt (für Felder in Millisekunden mit 32 Bit).</summary>
    class function SinceMs(AStart: UInt64): Cardinal; static;
    /// <summary>Nur für Tests: Zähler ersetzen; nil stellt TThread.GetTickCount64 wieder her.</summary>
    class procedure SetClock(const AClock: TFunc<UInt64>); static;
  end;

  /// <summary>Frist auf dem 64-Bit-Tickzähler; läuft nicht über. Der Standardwert (Default) ist schon
  /// abgelaufen.</summary>
  TAtlasDeadline = record
  private
    FAt: UInt64;
  public
    /// <summary>Frist in AMs Millisekunden.</summary>
    class function After(AMs: Cardinal): TAtlasDeadline; static;
    /// <summary>Schon abgelaufene Frist.</summary>
    class function Passed: TAtlasDeadline; static;
    /// <summary>Ist die Frist erreicht?</summary>
    function Reached: Boolean;
    /// <summary>Millisekunden bis zur Frist; 0, wenn sie erreicht ist.</summary>
    function RemainingMs: UInt64;
  end;

implementation

uses
  System.Classes;

{ TAtlasTicks }

class function TAtlasTicks.Now: UInt64;
begin
  if Assigned(FClock) then
  begin
    Result := FClock();
  end
  else
  begin
    Result := TThread.GetTickCount64;
  end;
end;

class function TAtlasTicks.Since(AStart: UInt64): UInt64;
var
  mNow: UInt64;
begin
  mNow := Now;
  if mNow <= AStart then
  begin
    Exit(0);
  end;
  Result := mNow - AStart;
end;

class function TAtlasTicks.SinceMs(AStart: UInt64): Cardinal;
var
  mSince: UInt64;
begin
  mSince := Since(AStart);
  if mSince > High(Cardinal) then
  begin
    Exit(High(Cardinal));
  end;
  Result := Cardinal(mSince);
end;

class procedure TAtlasTicks.SetClock(const AClock: TFunc<UInt64>);
begin
  FClock := AClock;
end;

{ TAtlasDeadline }

class function TAtlasDeadline.After(AMs: Cardinal): TAtlasDeadline;
begin
  Result.FAt := TAtlasTicks.Now + AMs;
end;

class function TAtlasDeadline.Passed: TAtlasDeadline;
begin
  Result.FAt := 0;
end;

function TAtlasDeadline.Reached: Boolean;
begin
  Result := TAtlasTicks.Now >= FAt;
end;

function TAtlasDeadline.RemainingMs: UInt64;
var
  mNow: UInt64;
begin
  mNow := TAtlasTicks.Now;
  if mNow >= FAt then
  begin
    Exit(0);
  end;
  Result := FAt - mNow;
end;

end.
