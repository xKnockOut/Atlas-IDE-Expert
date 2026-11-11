unit Atlas.Core.Diagnostics.UserIdle;

// Zeit seit der letzten Eingabe in Windows (Maus oder Tastatur, auch in
// anderen Programmen). LASTINPUTINFO.dwTime ist ein Stand des 32-Bit-
// Tickzählers; deshalb rechnet nur diese Unit mit GetTickCount, über den
// Überlauf nach 49,7 Tagen hinweg. Sonst gilt TAtlasTicks (64 Bit).

interface

type
  TAtlasUserIdle = record
  public
    /// <summary>Millisekunden von ALast bis ANow auf dem 32-Bit-Zähler, auch über den Überlauf hinweg.</summary>
    class function Elapsed(ANow, ALast: Cardinal): Cardinal; static;
    /// <summary>Zählerstand der letzten Eingabe; False, wenn Windows ihn nicht liefert.</summary>
    class function LastInput(out ATick: Cardinal): Boolean; static;
    /// <summary>Millisekunden seit dem Zählerstand ATick (aus LastInput).</summary>
    class function Since(ATick: Cardinal): Cardinal; static;
    /// <summary>Millisekunden seit der letzten Eingabe; False, wenn Windows den Stand nicht liefert.</summary>
    class function IdleMs(out AMs: Cardinal): Boolean; static;
  end;

implementation

uses
  Winapi.Windows;

class function TAtlasUserIdle.Elapsed(ANow, ALast: Cardinal): Cardinal;
begin
  if ANow >= ALast then
  begin
    Result := ANow - ALast;
  end
  else
  begin
    Result := (High(Cardinal) - ALast) + ANow + 1;
  end;
end;

class function TAtlasUserIdle.LastInput(out ATick: Cardinal): Boolean;
var
  mInfo: TLastInputInfo;
begin
  mInfo.cbSize := SizeOf(mInfo);
  mInfo.dwTime := 0;
  Result := GetLastInputInfo(mInfo);
  ATick := mInfo.dwTime;
end;

class function TAtlasUserIdle.Since(ATick: Cardinal): Cardinal;
begin
  Result := Elapsed(GetTickCount, ATick);
end;

class function TAtlasUserIdle.IdleMs(out AMs: Cardinal): Boolean;
var
  mTick: Cardinal;
begin
  AMs := 0;
  Result := LastInput(mTick);
  if Result then
  begin
    AMs := Since(mTick);
  end;
end;

end.
