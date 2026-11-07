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
// Die Werte der Einstellungen stehen in Atlas.Core.Settings.ProblemsUpdate.

interface

uses
  Atlas.Core.Settings.ProblemsUpdate;

type
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
    /// <summary>Takt, in dem der Controller den Editor liest, höchstens so lang (ms).</summary>
    cMaxTickMs = 250;
  public
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

class function TAtlasProblemsRefresh.TickMs(ADelayMs: Integer): Integer;
begin
  Result := Min(cMaxTickMs, TAtlasProblemsUpdateSetting.ClampDelay(ADelayMs));
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
  mQuiet := AState.QuietMs >= Cardinal(TAtlasProblemsUpdateSetting.ClampDelay(ADelayMs));
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
