unit Atlas.Core.Assistants.InboxPace;

// Wann ein Auftragseingang seinen Ordner auflistet (#1984): nur, wenn das
// Änderungssignal des Ordners kam, wenn beim letzten Mal Aufträge liegen
// blieben (Läufer belegt, nur einer je Takt) oder als Sicherheitsnetz nach
// cSafetyMs, falls ein Signal verloren ging oder der Ordner nicht beobachtet
// werden kann. Ohne MCP-Client kostet ein Takt so nur die Abfrage des Signals.
// Ohne Windows und VCL, die Zeit kommt vom Aufrufer. Default(TAtlasInboxPace)
// ist ein Takt ohne bisherige Auflistung: Die erste Abfrage listet immer.

interface

type
  TAtlasInboxPace = record
  public const
    /// <summary>Spätestens nach dieser Zeit wird auch ohne Signal aufgelistet.</summary>
    cSafetyMs = 2000;
  private
    FListedAt: UInt64;
    FListed: Boolean;
    FBacklog: Boolean;
  public
    /// <summary>Jetzt auflisten? AChanged: Signal des Ordners seit dem letzten Takt; ANowMs: Tickzähler.</summary>
    function Due(AChanged: Boolean; ANowMs: UInt64): Boolean;
    /// <summary>Nach dem Auflisten: ABacklog, wenn Aufträge liegen geblieben sind (nächster Takt listet wieder).
    /// </summary>
    procedure Listed(ANowMs: UInt64; ABacklog: Boolean);
  end;

implementation

function TAtlasInboxPace.Due(AChanged: Boolean; ANowMs: UInt64): Boolean;
begin
  Result := AChanged or FBacklog or not FListed or (ANowMs < FListedAt) or
    (ANowMs - FListedAt >= cSafetyMs);
end;

procedure TAtlasInboxPace.Listed(ANowMs: UInt64; ABacklog: Boolean);
begin
  FListed := True;
  FListedAt := ANowMs;
  FBacklog := ABacklog;
end;

end.
