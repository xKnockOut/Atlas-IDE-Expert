unit Atlas.Text.Reporting;

// Melder aufrufen, deren eigener Fehler keinen Empfänger mehr hat (gemeinsam für Server und Plugin): Protokoll-
// senken, Warnungen an die Oberfläche, Beobachter des Diagnoselogs, Rückrufe beim Fehlschlag. Scheitert so ein
// Aufruf, darf das die eigentliche Arbeit (Antwort, Entladen, nächste Senke) nicht aufhalten, und melden ließe
// sich der Fehler nur über denselben Weg, der gerade gescheitert ist.
// Das ist die eine benannte Stelle, an der eine Ausnahme ohne Meldung endet; Aufrufer brauchen dafür kein eigenes
// pauschales except mehr. Die Zahl der verlorenen Meldungen bleibt über Lost sichtbar (Diagnose, Tests).

interface

uses
  System.SysUtils;

type
  TReporting = record
  private
    class var FLost: Integer;
  public
    /// <summary>Ruft AReport auf; eine Ausnahme daraus endet hier und zählt in Lost.</summary>
    class procedure Quietly(const AReport: TProc); static;
    /// <summary>Meldungen, die seit dem Start an einer Ausnahme gescheitert sind.</summary>
    class function Lost: Integer; static;
  end;

implementation

uses
  System.SyncObjs;

{ TReporting }

class procedure TReporting.Quietly(const AReport: TProc);
begin
  if not Assigned(AReport) then
  begin
    Exit;
  end;
  try
    AReport();
  except
    // lsp-ignore: catch-all-without-raise -- Fehler des Melders selbst; ein anderer Empfänger fehlt
    on Exception do
      TInterlocked.Increment(FLost);
  end;
end;

class function TReporting.Lost: Integer;
begin
  Result := TInterlocked.CompareExchange(FLost, 0, 0);
end;

end.
