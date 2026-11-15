unit Atlas.Core.Debug.StopProgress;

// Ablauf je Halt für Anzeigen im Editor, die Werte des Halts auswerten (Werte im Editor #508, „Warum bin ich
// hier?“ #1878), ohne IDE prüfbar (#1967): Phase, Nachfragen bis Aufrufstapel und Editor da sind, nur die jüngste
// Antwort des Servers und ob derselbe Halt noch besteht.

interface

{$SCOPEDENUMS ON}

type
  TAtlasStopPhase = (Idle, Location, Request, Evaluate);

  /// <summary>Ausführungspunkt lesen: aufgeben, später noch einmal, Datei und Zeile da.</summary>
  TAtlasStopLocation = (GiveUp, Retry, Ready);

  TAtlasStopProgress = record
    Phase: TAtlasStopPhase;
    /// <summary>Halt Nummer, für den die Anzeige gilt.</summary>
    Stop: Integer;
    /// <summary>Nummer der jüngsten Anfrage an den Server.</summary>
    Request: Integer;
    Retries: Integer;
    /// <summary>Neuer Halt AStop: zuerst Datei und Zeile lesen.</summary>
    procedure Restart(AStop: Integer);
    /// <summary>Laufende Anfragen verwerfen, nichts mehr tun.</summary>
    procedure Discard;
    /// <summary>Nummer der nächsten Anfrage.</summary>
    function NextRequest: Integer;
    /// <summary>Ausführungspunkt: Ohne Stapel (AStackGone) oder ohne Quelltext (AWithoutSource) gibt Atlas auf;
    /// fehlt der Editor der Datei (oder der Stapel kommt verzögert), fragt Atlas höchstens AMaxRetries-mal nach.
    /// Ready setzt die Phase auf Request, GiveUp auf Idle.</summary>
    function Locate(AStackGone, AWithoutSource, AHasBuffer: Boolean; AMaxRetries: Integer): TAtlasStopLocation;
    /// <summary>Antwort ARequest ist die jüngste.</summary>
    function IsNewest(ARequest: Integer): Boolean;
    /// <summary>Antwort ARequest ist die jüngste, und Atlas wartet auf sie.</summary>
    function Accepts(ARequest: Integer): Boolean;
    /// <summary>Besteht derselbe Halt noch (AStopCount der Session, angehaltener Thread da)?</summary>
    function StillAt(AStopCount: Integer; AHasThread: Boolean): Boolean;
  end;

implementation

{ TAtlasStopProgress }

procedure TAtlasStopProgress.Restart(AStop: Integer);
begin
  Stop := AStop;
  Retries := 0;
  Phase := TAtlasStopPhase.Location;
end;

procedure TAtlasStopProgress.Discard;
begin
  Inc(Request);
  Phase := TAtlasStopPhase.Idle;
end;

function TAtlasStopProgress.NextRequest: Integer;
begin
  Inc(Request);
  Result := Request;
end;

function TAtlasStopProgress.Locate(AStackGone, AWithoutSource, AHasBuffer: Boolean;
  AMaxRetries: Integer): TAtlasStopLocation;
begin
  if AStackGone or AWithoutSource then
  begin
    Result := TAtlasStopLocation.GiveUp;
  end
  else if AHasBuffer then
  begin
    Result := TAtlasStopLocation.Ready;
    Phase := TAtlasStopPhase.Request;
    Exit;
  end
  else
  begin
    Inc(Retries);
    if Retries <= AMaxRetries then
    begin
      Exit(TAtlasStopLocation.Retry);
    end;
    Result := TAtlasStopLocation.GiveUp;
  end;
  Phase := TAtlasStopPhase.Idle;
end;

function TAtlasStopProgress.IsNewest(ARequest: Integer): Boolean;
begin
  Result := ARequest = Request;
end;

function TAtlasStopProgress.Accepts(ARequest: Integer): Boolean;
begin
  Result := IsNewest(ARequest) and (Phase = TAtlasStopPhase.Request);
end;

function TAtlasStopProgress.StillAt(AStopCount: Integer; AHasThread: Boolean): Boolean;
begin
  Result := (AStopCount = Stop) and AHasThread;
end;

end.
