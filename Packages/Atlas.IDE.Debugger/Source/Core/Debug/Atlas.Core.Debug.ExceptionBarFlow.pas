unit Atlas.Core.Debug.ExceptionBarFlow;

// Ablauf der Exception-Leiste (#783) ohne IDE prüfbar (#1967): wann die Leiste nach dem Halt erscheint (erst,
// wenn kein Dialog mehr offen ist, nach ruhigen Takten), welche Taste sie bedient, ob sie einen Halt schon
// abdeckt und wann „Nur an dieser Stelle ignorieren“ angeboten wird. Das Warten nutzt auch „Zugriffsverletzung
// erklären“ (#841). Atlas.IDE.Debug.ExceptionBar fragt Debugger, Fenster und Tastatur.

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Nach einem Takt: aufgeben (Halt vorbei oder zu lange), weiter warten, jetzt zeigen.</summary>
  TAtlasBarWait = (Drop, Wait, Go);

  /// <summary>Taste bei sichtbarer Leiste: keine, Fortsetzen (F9), hier anhalten (Esc, F8).</summary>
  TAtlasBarKey = (None, Continue, BreakHere);

  TAtlasExceptionBarFlow = class
  public const
    /// <summary>So viele Takte ohne modalen Dialog, bevor die Leiste erscheint.</summary>
    cQuietTicks = 2;
    // Tasten wie in Winapi.Windows (VK_*), hier ohne Windows.
    cKeyEscape = $1B;
    cKeyF8 = $77;
    cKeyF9 = $78;
  public
    /// <summary>Takt beim Warten auf die Anzeige: AStillStopped derselbe Halt, AModal ein modaler Dialog offen
    /// (setzt AQuiet zurück); nach cQuietTicks ruhigen Takten Go.</summary>
    class function WaitStep(AStillStopped: Boolean; AElapsedMs, ALimitMs: UInt64; AModal: Boolean;
      var AQuiet: Integer): TAtlasBarWait; static;
    /// <summary>Taste AKey ohne Umschalttasten.</summary>
    class function KeyOf(AKey: Word): TAtlasBarKey; static;
    /// <summary>Deckt die Leiste den Halt AStop ab: sichtbar für ihn oder wartend auf ihn?</summary>
    class function Covers(AVisible: Boolean; AShownStop: Integer; APending: Boolean; APendingStop,
      AStop: Integer): Boolean; static;
    /// <summary>Knopf „Nur an dieser Stelle ignorieren“: Einstellung an, Projekt und Ort bekannt.</summary>
    class function CanIgnoreLocation(AEnabled: Boolean; const AProject: string; AHasLocation: Boolean): Boolean;
      static;
  end;

implementation

{ TAtlasExceptionBarFlow }

class function TAtlasExceptionBarFlow.WaitStep(AStillStopped: Boolean; AElapsedMs, ALimitMs: UInt64;
  AModal: Boolean; var AQuiet: Integer): TAtlasBarWait;
begin
  if not AStillStopped or (AElapsedMs > ALimitMs) then
  begin
    Exit(TAtlasBarWait.Drop);
  end;
  // Solange ein Dialog offen ist, könnte der Benutzer noch fortsetzen.
  if AModal then
  begin
    AQuiet := 0;
    Exit(TAtlasBarWait.Wait);
  end;
  Inc(AQuiet);
  if AQuiet < cQuietTicks then
  begin
    Exit(TAtlasBarWait.Wait);
  end;
  Result := TAtlasBarWait.Go;
end;

class function TAtlasExceptionBarFlow.KeyOf(AKey: Word): TAtlasBarKey;
begin
  case AKey of
    cKeyF9:
      Result := TAtlasBarKey.Continue;
    cKeyEscape, cKeyF8:
      Result := TAtlasBarKey.BreakHere;
  else
    Result := TAtlasBarKey.None;
  end;
end;

class function TAtlasExceptionBarFlow.Covers(AVisible: Boolean; AShownStop: Integer; APending: Boolean;
  APendingStop, AStop: Integer): Boolean;
begin
  Result := (AVisible and (AShownStop = AStop)) or (APending and (APendingStop = AStop));
end;

class function TAtlasExceptionBarFlow.CanIgnoreLocation(AEnabled: Boolean; const AProject: string;
  AHasLocation: Boolean): Boolean;
begin
  Result := AEnabled and (AProject <> '') and AHasLocation;
end;

end.
