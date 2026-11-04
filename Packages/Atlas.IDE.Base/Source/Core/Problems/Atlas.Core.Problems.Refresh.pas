unit Atlas.Core.Problems.Refresh;

// Wann der Controller die offene Datei prüfen lässt (problems.update,
// problems.liveDelayMs), ohne VCL und Open Tools API:
// - live: beim Tippen, sobald seit der letzten Änderung die Verzögerung
//   (problems.liveDelayMs, 100 bis 10000 ms) vergangen ist.
// - save: erst, wenn der Puffer wieder ungeändert ist (nach dem Speichern).
// - manual: nur auf Anforderung (Befehl „Datei jetzt prüfen“, Knopf im
//   Fenster „Atlas-Prüfung“, Klick auf die Live-Prüfung der Statusleiste);
//   eine ungeändert geöffnete Datei wird einmal geprüft, damit sie nicht leer
//   bleibt.
// Eine Anforderung (TAtlasProblemsCheckRequest) gilt in jeder Art sofort. Die Bitte des Servers um neues
// Holen (workspace/diagnostic/refresh) entscheidet der Controller selbst.
// Vor problems.update gab es nur problems.live (an = live, aus = save).

interface

type
  {$SCOPEDENUMS ON}
  TAtlasProblemsUpdate = (Live, Save, Manual);
  {$SCOPEDENUMS OFF}

  /// <summary>Stand der offenen Datei für die Entscheidung, ob jetzt geprüft wird.</summary>
  TAtlasProblemsRefreshState = record
    /// <summary>Der Text weicht vom zuletzt geprüften ab (oder die Datei wurde noch nie geprüft).</summary>
    Changed: Boolean;
    /// <summary>Die Datei wurde in dieser Sitzung schon einmal geprüft.</summary>
    CheckedBefore: Boolean;
    /// <summary>Der Puffer hat ungespeicherte Änderungen.</summary>
    Modified: Boolean;
    /// <summary>Zeit seit der letzten Änderung des Puffers in ms.</summary>
    QuietMs: Cardinal;
    /// <summary>Eine Prüfung wurde angefordert.</summary>
    Requested: Boolean;
  end;

  TAtlasProblemsRefresh = record
  public const
    DefaultDelayMs = 400;
    MinDelayMs = 100;
    MaxDelayMs = 10000;
    /// <summary>Takt, in dem der Controller den Editor liest, höchstens so lang (ms).</summary>
    MaxTickMs = 250;
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
    /// <summary>Takt des Controllers zur Verzögerung: höchstens 250 ms, sonst die Verzögerung selbst.</summary>
    class function TickMs(ADelayMs: Integer): Integer; static;
    /// <summary>Jetzt prüfen? ADelayMs gilt für live und save.</summary>
    class function Due(AMode: TAtlasProblemsUpdate; const AState: TAtlasProblemsRefreshState;
      ADelayMs: Integer): Boolean; static;
  end;

  /// <summary>Angeforderte Prüfung der offenen Datei („Datei jetzt prüfen“); nur im Hauptthread. Der Controller
  /// holt sie im nächsten Takt ab.</summary>
  TAtlasProblemsCheckRequest = record
  private class var
    FPending: Boolean;
  public
    /// <summary>Prüfung anfordern.</summary>
    class procedure Request; static;
    /// <summary>Angefordert? Setzt die Anforderung zurück.</summary>
    class function Take: Boolean; static;
    /// <summary>Steht eine Anforderung aus (ohne zurückzusetzen)?</summary>
    class function Pending: Boolean; static;
    /// <summary>Anforderung verwerfen (Ende der Sitzung, Tests).</summary>
    class procedure Clear; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TAtlasProblemsRefresh }

class function TAtlasProblemsRefresh.Parse(const AValue: string): TAtlasProblemsUpdate;
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

class function TAtlasProblemsRefresh.Name(AMode: TAtlasProblemsUpdate): string;
begin
  Result := cValues[AMode];
end;

class function TAtlasProblemsRefresh.Normalize(const AValue: string): string;
begin
  Result := Name(Parse(AValue));
end;

class function TAtlasProblemsRefresh.FromLive(ALive: Boolean): string;
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

class function TAtlasProblemsRefresh.ClampDelay(ADelayMs: Integer): Integer;
begin
  Result := EnsureRange(ADelayMs, MinDelayMs, MaxDelayMs);
end;

class function TAtlasProblemsRefresh.TickMs(ADelayMs: Integer): Integer;
begin
  Result := Min(MaxTickMs, ClampDelay(ADelayMs));
end;

class function TAtlasProblemsRefresh.Due(AMode: TAtlasProblemsUpdate; const AState: TAtlasProblemsRefreshState;
  ADelayMs: Integer): Boolean;
var
  mQuiet: Boolean;
begin
  if AState.Requested then
  begin
    Exit(True);
  end;
  if not AState.Changed then
  begin
    Exit(False);
  end;
  mQuiet := AState.QuietMs >= Cardinal(ClampDelay(ADelayMs));
  case AMode of
    TAtlasProblemsUpdate.Save:
      Result := mQuiet and not AState.Modified;
    TAtlasProblemsUpdate.Manual:
      Result := not AState.CheckedBefore and not AState.Modified;
  else
    Result := mQuiet;
  end;
end;

{ TAtlasProblemsCheckRequest }

class procedure TAtlasProblemsCheckRequest.Request;
begin
  FPending := True;
end;

class function TAtlasProblemsCheckRequest.Take: Boolean;
begin
  Result := FPending;
  FPending := False;
end;

class function TAtlasProblemsCheckRequest.Pending: Boolean;
begin
  Result := FPending;
end;

class procedure TAtlasProblemsCheckRequest.Clear;
begin
  FPending := False;
end;

end.
