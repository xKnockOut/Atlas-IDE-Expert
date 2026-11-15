unit Atlas.Core.Debug.AsyncOriginFlow;

// Entscheidungen der Herkunft eingereihter Methoden (#859) außerhalb von Aufrufstellen und Ablage, ohne IDE prüfbar
// (#1967): welche Dateien Atlas nach Aufrufstellen durchsucht, wann ein Halt neu zugeordnet wird, wie die Herkunft
// gemeldet wird und welcher Rahmen sich öffnen lässt. Atlas.IDE.Debug.AsyncOrigin fragt Debugger, Projekt und Fenster.

interface

type
  {$SCOPEDENUMS ON}
  /// <summary>Meldung der Herkunft: keine gefunden, nur der Titel (das Fenster Atlas-Aufrufstapel zeigt den Stapel),
  /// Stapel im Ergebnisfenster.</summary>
  TAtlasOriginReport = (None, Title, Results);
  {$SCOPEDENUMS OFF}

  TAtlasAsyncOriginFlow = class
  public
    /// <summary>Quelltext des Projekts, in dem Aufrufstellen stehen können (.pas, .dpr)?</summary>
    class function IsSource(const AFileName: string): Boolean; static;
    /// <summary>Neu zuordnen? Weitere Halte desselben Threads (AThreadId) an derselben Stelle (ASite) behalten die
    /// Zuordnung (AHas, AShownThread, AShownSite).</summary>
    class function Reassigns(AHas: Boolean; AShownThread: Cardinal; AShownSite: Integer; AThreadId: Cardinal;
      ASite: Integer): Boolean; static;
    class function ReportOf(AFound, ACallStackShown: Boolean): TAtlasOriginReport; static;
    /// <summary>Rahmen zur Zeile AItemId des Ergebnisfensters; -1 ohne Herkunft (AFound) oder außerhalb von ACount.
    /// </summary>
    class function FrameOf(AFound: Boolean; const AItemId: string; ACount: Integer): Integer; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasAsyncOriginFlow }

class function TAtlasAsyncOriginFlow.IsSource(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.pas') or SameText(ExtractFileExt(AFileName), '.dpr');
end;

class function TAtlasAsyncOriginFlow.Reassigns(AHas: Boolean; AShownThread: Cardinal; AShownSite: Integer;
  AThreadId: Cardinal; ASite: Integer): Boolean;
begin
  Result := not (AHas and (AShownThread = AThreadId) and (AShownSite = ASite));
end;

class function TAtlasAsyncOriginFlow.ReportOf(AFound, ACallStackShown: Boolean): TAtlasOriginReport;
begin
  if not AFound then
  begin
    Result := TAtlasOriginReport.None;
  end
  else if ACallStackShown then
  begin
    Result := TAtlasOriginReport.Title;
  end
  else
  begin
    Result := TAtlasOriginReport.Results;
  end;
end;

class function TAtlasAsyncOriginFlow.FrameOf(AFound: Boolean; const AItemId: string; ACount: Integer): Integer;
begin
  Result := StrToIntDef(AItemId, -1);
  if not AFound or (Result < 0) or (Result >= ACount) then
  begin
    Result := -1;
  end;
end;

end.
