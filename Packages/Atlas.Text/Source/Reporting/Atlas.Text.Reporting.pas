unit Atlas.Text.Reporting;

// Melder aufrufen, deren eigener Fehler keinen Empfänger mehr hat (gemeinsam für Server und Plugin): Protokoll-
// senken, Warnungen an die Oberfläche, Beobachter des Diagnoselogs, Rückrufe beim Fehlschlag. Scheitert so ein
// Aufruf, darf das die eigentliche Arbeit (Antwort, Entladen, nächste Senke) nicht aufhalten, und melden ließe
// sich der Fehler nur über denselben Weg, der gerade gescheitert ist.
// Das ist die eine benannte Stelle, an der eine Ausnahme ohne Meldung endet; Aufrufer brauchen dafür kein eigenes
// pauschales except mehr. Die Zahl der verlorenen Meldungen bleibt über Lost sichtbar (Diagnose, Tests).
// Failed gibt Fehler von Bausteinen unterhalb der Fehlergrenze (Beobachterlisten) an die Senke, die die
// Fehlergrenze beim Start einträgt; ohne Senke zählen sie in Lost.

interface

uses
  System.SysUtils;

type
  /// <summary>Empfänger für Failed: AWhere sagt, wo der Fehler auftrat.</summary>
  TReportingSink = reference to procedure(const AWhere: string; AE: Exception);

  TReporting = record
  private
    class var FLost: Integer;
    class var FSink: TReportingSink;
    class function Sink: TReportingSink; static;
  public
    /// <summary>Ruft AReport auf; eine Ausnahme daraus endet hier und zählt in Lost.</summary>
    class procedure Quietly(const AReport: TProc); static;
    /// <summary>Meldungen, die seit dem Start an einer Ausnahme gescheitert sind.</summary>
    class function Lost: Integer; static;
    /// <summary>Gibt AE an die eingetragene Senke; ohne Senke oder wenn sie scheitert, zählt es in Lost.</summary>
    class procedure Failed(const AWhere: string; AE: Exception); static;
    /// <summary>Trägt die Senke für Failed ein (nil trägt sie aus) und liefert die bisherige.</summary>
    class function ReplaceSink(const ASink: TReportingSink): TReportingSink; static;
  end;

implementation

uses
  System.SyncObjs,
  Atlas.Text.Locked;

var
  GSinkLock: TObject;

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

class function TReporting.Sink: TReportingSink;
begin
  System.TMonitor.Enter(GSinkLock);
  try
    Result := FSink;
  finally
    System.TMonitor.Exit(GSinkLock);
  end;
end;

class function TReporting.ReplaceSink(const ASink: TReportingSink): TReportingSink;
begin
  System.TMonitor.Enter(GSinkLock);
  try
    Result := FSink;
    FSink := ASink;
  finally
    System.TMonitor.Exit(GSinkLock);
  end;
end;

class procedure TReporting.Failed(const AWhere: string; AE: Exception);
var
  mSink: TReportingSink;
begin
  mSink := Sink;
  if not Assigned(mSink) then
  begin
    TInterlocked.Increment(FLost);
    Exit;
  end;
  Quietly(
    procedure
    begin
      mSink(AWhere, AE);
    end);
end;

initialization
  GSinkLock := TAtlasSharedLock.New;

finalization
  TReporting.ReplaceSink(nil);
  GSinkLock.Free;

end.
