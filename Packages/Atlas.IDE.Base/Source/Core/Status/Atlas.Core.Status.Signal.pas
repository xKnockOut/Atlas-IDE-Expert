unit Atlas.Core.Status.Signal;

// Signalfarbe zum Zustand einer Statuszeile (#1255): Grün ist in Ordnung, Gelb Warnung bzw. läuft, Rot Fehler,
// alles andere ohne Aussage. Die Zuordnung gehört zum Status; die Signalfarben selbst kennen keine Statuszeilen.

interface

uses
  Atlas.Plugin.Style.Signal,
  Atlas.Core.Status.Contract;

type
  TAtlasStatusSignal = record
    /// <summary>Bedeutung der Signalfarbe zu einem Zustand.</summary>
    class function KindOf(AState: TAtlasStatusState): TAtlasSignalKind; static;
    /// <summary>Signal aus ASignals zum Zustand einer Statuszeile.</summary>
    class function ForState(const ASignals: TAtlasSignals; AState: TAtlasStatusState): TAtlasSignal; static;
  end;

implementation

class function TAtlasStatusSignal.KindOf(AState: TAtlasStatusState): TAtlasSignalKind;
begin
  case AState of
    TAtlasStatusState.Green:
      Result := TAtlasSignalKind.Ok;
    TAtlasStatusState.Yellow:
      Result := TAtlasSignalKind.Warn;
    TAtlasStatusState.Red:
      Result := TAtlasSignalKind.Error;
  else
    Result := TAtlasSignalKind.Idle;
  end;
end;

class function TAtlasStatusSignal.ForState(const ASignals: TAtlasSignals; AState: TAtlasStatusState): TAtlasSignal;
begin
  Result := ASignals.Get(KindOf(AState));
end;

end.
