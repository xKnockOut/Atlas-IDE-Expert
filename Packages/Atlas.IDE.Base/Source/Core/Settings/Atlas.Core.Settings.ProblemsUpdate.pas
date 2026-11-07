unit Atlas.Core.Settings.ProblemsUpdate;

// Werte der Einstellungen problems.update (live, save, manual) und
// problems.liveDelayMs (100 bis 10000 ms), ohne VCL und Open Tools API.
// Vor problems.update gab es nur problems.live (an = live, aus = save).
// Wann geprüft wird, entscheidet Atlas.Core.Problems.Refresh.

interface

type
  {$SCOPEDENUMS ON}
  TAtlasProblemsUpdate = (Live, Save, Manual);
  {$SCOPEDENUMS OFF}

  TAtlasProblemsUpdateSetting = record
  public const
    cDefaultDelayMs = 400;
    cMinDelayMs = 100;
    cMaxDelayMs = 10000;
    /// <summary>Werte von problems.update in der Reihenfolge von TAtlasProblemsUpdate.</summary>
    cValues: array[TAtlasProblemsUpdate] of string = ('live', 'save', 'manual');
  public
    /// <summary>Art zu AValue (Groß-/Kleinschreibung egal); Unbekanntes = live.</summary>
    class function Parse(const AValue: string): TAtlasProblemsUpdate; static;
    /// <summary>Text zu AMode, wie er in den Einstellungen steht.</summary>
    class function Name(AMode: TAtlasProblemsUpdate): string; static;
    /// <summary>AValue als gültiger Wert von problems.update; Unbekanntes = live.</summary>
    class function Normalize(const AValue: string): string; static;
    /// <summary>Wert von problems.update aus dem früheren problems.live (#909): an = live, aus = save.</summary>
    class function FromLive(ALive: Boolean): string; static;
    /// <summary>Verzögerung auf 100 bis 10000 ms begrenzt.</summary>
    class function ClampDelay(ADelayMs: Integer): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TAtlasProblemsUpdateSetting }

class function TAtlasProblemsUpdateSetting.Parse(const AValue: string): TAtlasProblemsUpdate;
var
  mMode: TAtlasProblemsUpdate;
begin
  for mMode := Low(TAtlasProblemsUpdate) to High(TAtlasProblemsUpdate) do
  begin
    if SameText(Trim(AValue), cValues[mMode]) then
    begin
      Exit(mMode);
    end;
  end;
  Result := TAtlasProblemsUpdate.Live;
end;

class function TAtlasProblemsUpdateSetting.Name(AMode: TAtlasProblemsUpdate): string;
begin
  Result := cValues[AMode];
end;

class function TAtlasProblemsUpdateSetting.Normalize(const AValue: string): string;
begin
  Result := Name(Parse(AValue));
end;

class function TAtlasProblemsUpdateSetting.FromLive(ALive: Boolean): string;
begin
  if ALive then
  begin
    Result := Name(TAtlasProblemsUpdate.Live);
  end
  else
  begin
    Result := Name(TAtlasProblemsUpdate.Save);
  end;
end;

class function TAtlasProblemsUpdateSetting.ClampDelay(ADelayMs: Integer): Integer;
begin
  Result := EnsureRange(ADelayMs, cMinDelayMs, cMaxDelayMs);
end;

end.
