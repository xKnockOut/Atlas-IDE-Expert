unit Atlas.Core.Debug.EventLogFlow;

// Entscheidungen des Ereignisprotokolls (#579) außerhalb von Einordnung und Ablage, ohne IDE prüfbar (#1967): welche
// Zeilen des Fensters der Notifier schon meldet, wann ein Logpunkt zusammengeführt wird, welches Symbol ein Eintrag
// meint, Zeit seit dem Start und Dateiname beim Speichern. Atlas.IDE.Debug.EventLog fragt IDE, Server und Fenster.

interface

uses
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Debug.EventLog,
  Atlas.Core.Debug.Logpoint;

type
  /// <summary>Was mit einer Zeile beim Zusammenführen der Logpunkte geschieht: so eintragen, als Logpunkt
  /// eintragen (Text ersetzt), weglassen (wartet auf ihren Wert bzw. gehört zu einem Logpunkt).</summary>
  TAtlasLogpointStep = (Keep, Merged, Drop);

  TAtlasEventLogFlow = class
  public
    /// <summary>Module, Threads und Prozess meldet der Notifier (AWatching); aus dem Fenster dann nicht.</summary>
    class function SkipFromWindow(AWatching: Boolean; AKind: TAtlasEventKind): Boolean; static;
    /// <summary>Braucht es einen neuen Zusammenführer für das Präfix APrefix?</summary>
    class function NeedsMerger(const AMerger: TAtlasLogpointMerger; const APrefix: string): Boolean; static;
    /// <summary>Zeile AText der Art AKind an AMerger geben; nur Haltepunktzeilen, außer eine Meldung wartet auf
    /// ihren Wert. Bei Merged steht der Logpunkt in AOutput.</summary>
    class function LogpointStep(const AMerger: TAtlasLogpointMerger; AKind: TAtlasEventKind; const AText: string;
      out AOutput: string): TAtlasLogpointStep; static;
    /// <summary>Symbol zu ASymbol ("Unit.Routine", "Klasse.Methode") unter ACandidates: gleicher Name mit Datei;
    /// passt der ganze Name am Ende, gewinnt der letzte solche, sonst der erste.</summary>
    class function FindSymbol(const ACandidates: TArray<TAtlasSymbol>; const ASymbol: string;
      out AFound: TAtlasSymbol): Boolean; static;
    /// <summary>Kurzname, nach dem der Server gefragt wird: alles nach dem letzten Punkt.</summary>
    class function SymbolName(const ASymbol: string): string; static;
    /// <summary>Millisekunden seit AStartTick; 0 ohne Start.</summary>
    class function Elapsed(AStartTick, ANow: UInt64): Int64; static;
    /// <summary>Vorschlag beim Speichern: Projektname ohne Endung, dann „-events.txt“.</summary>
    class function SaveName(const AProject: string): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasEventLogFlow }

class function TAtlasEventLogFlow.SkipFromWindow(AWatching: Boolean; AKind: TAtlasEventKind): Boolean;
begin
  Result := AWatching and (AKind in [TAtlasEventKind.Module, TAtlasEventKind.Thread, TAtlasEventKind.Process]);
end;

class function TAtlasEventLogFlow.NeedsMerger(const AMerger: TAtlasLogpointMerger; const APrefix: string): Boolean;
begin
  Result := (AMerger = nil) or (AMerger.Prefix <> APrefix);
end;

class function TAtlasEventLogFlow.LogpointStep(const AMerger: TAtlasLogpointMerger; AKind: TAtlasEventKind;
  const AText: string; out AOutput: string): TAtlasLogpointStep;
var
  mIsLogpoint: Boolean;
begin
  AOutput := '';
  Result := TAtlasLogpointStep.Keep;
  // Logpunkte (#583): Meldung mit „{0}“ wartet auf die Zeile mit dem Wert.
  if (AKind <> TAtlasEventKind.Breakpoint) and not AMerger.Pending then
  begin
    Exit;
  end;
  if AMerger.Feed(AText, AOutput, mIsLogpoint) then
  begin
    Result := TAtlasLogpointStep.Merged;
  end
  else if mIsLogpoint then
  begin
    Result := TAtlasLogpointStep.Drop;
  end;
end;

class function TAtlasEventLogFlow.SymbolName(const ASymbol: string): string;
begin
  Result := ASymbol.Substring(ASymbol.LastIndexOf('.') + 1);
end;

class function TAtlasEventLogFlow.FindSymbol(const ACandidates: TArray<TAtlasSymbol>; const ASymbol: string;
  out AFound: TAtlasSymbol): Boolean;
var
  mName: string;
  mCandidate: TAtlasSymbol;
begin
  Result := False;
  AFound := Default(TAtlasSymbol);
  mName := SymbolName(ASymbol);
  for mCandidate in ACandidates do
  begin
    if SameText(mCandidate.Name, mName) and (mCandidate.FileName <> '') then
    begin
      // Ganzer Name gleich am Ende ("TForm1.Button1Click" passt zu "Main.TForm1.Button1Click") gewinnt.
      if ASymbol.ToUpper.EndsWith((mCandidate.Container + '.' + mCandidate.Name).ToUpper) or not Result then
      begin
        AFound := mCandidate;
        Result := True;
      end;
    end;
  end;
end;

class function TAtlasEventLogFlow.Elapsed(AStartTick, ANow: UInt64): Int64;
begin
  Result := 0;
  if AStartTick > 0 then
  begin
    Result := Int64(ANow - AStartTick);
  end;
end;

class function TAtlasEventLogFlow.SaveName(const AProject: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AProject), '') + '-events.txt';
end;

end.
