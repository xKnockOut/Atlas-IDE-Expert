unit Atlas.Core.Status.Signal;

// Signalfarbe zum Zustand einer Statuszeile (#1255): Grün → Ok, Gelb → Warnung,
// Rot → Fehler, sonst ohne Aussage. Liegt beim Status, nicht bei den Farben:
// Status verwendet Style, Style kennt keine Statuszustände.

interface

uses
  Atlas.Core.Style.Signal,
  Atlas.Core.Status.Contract;

type
  TAtlasStatusSignal = record
    /// <summary>Bedeutung der Signalfarbe für AState.</summary>
    class function KindOf(AState: TAtlasStatusState): TAtlasSignalKind; static;
    /// <summary>Signal aus ASignals zum Zustand AState.</summary>
    class function Pick(const ASignals: TAtlasSignals; AState: TAtlasStatusState): TAtlasSignal; static;
  end;

implementation

{ TAtlasStatusSignal }

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

class function TAtlasStatusSignal.Pick(const ASignals: TAtlasSignals; AState: TAtlasStatusState): TAtlasSignal;
begin
  Result := ASignals.Get(KindOf(AState));
end;

end.
