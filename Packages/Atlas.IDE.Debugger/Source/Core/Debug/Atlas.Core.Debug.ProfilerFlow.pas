unit Atlas.Core.Debug.ProfilerFlow;

// Entscheidungen des Profilers (#2057) außerhalb von Protokoll und Tabelle, ohne IDE prüfbar (#1967): was der
// Knopf „Messen“ gerade tut, welche Messung nach dem Neuladen gewählt ist, welche Datei eine beendete Messung
// liefert und wann eine Messung schon geladen ist. Atlas.IDE.Debug.Profiler fragt Debugger, Server und Fenster.

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Knopf „Messen“: nichts (Anfrage läuft), Messung beenden, kein Prozess zum Messen, Messung starten.
  /// </summary>
  TAtlasProfilerToggle = (Ignore, Stop, NoProcess, Start);

  TAtlasProfilerFlow = class
  public
    class function Toggle(ABusy, ARunning: Boolean; AProcessId: Cardinal): TAtlasProfilerToggle; static;
    /// <summary>„Mit Profil starten“ wirkt wie der Knopf, solange eine Messung läuft oder angefragt ist.</summary>
    class function ActsAsToggle(ABusy, ARunning: Boolean): Boolean; static;
    /// <summary>Gewählte Messung nach dem Neuladen: die mit dem Dateinamen von ASelect, sonst die erste (-1 ohne).
    /// </summary>
    class function SelectedRun(const ARuns: TArray<string>; const ASelect: string): Integer; static;
    /// <summary>Datei der beendeten Messung: der volle Pfad, sonst der Name.</summary>
    class function ResultFile(const APath, AFileName: string): string; static;
    /// <summary>APath ist schon geladen (ALoadedPath).</summary>
    class function IsLoaded(const ALoadedPath, APath: string): Boolean; static;
    /// <summary>Zeile im Editor (ab 0) zur Zeile der Tabelle (ab 1, 0 = unbekannt).</summary>
    class function EditorLine(ALine: Integer): Integer; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasProfilerFlow }

class function TAtlasProfilerFlow.Toggle(ABusy, ARunning: Boolean; AProcessId: Cardinal): TAtlasProfilerToggle;
begin
  if ABusy then
  begin
    Result := TAtlasProfilerToggle.Ignore;
  end
  else if ARunning then
  begin
    Result := TAtlasProfilerToggle.Stop;
  end
  else if AProcessId = 0 then
  begin
    Result := TAtlasProfilerToggle.NoProcess;
  end
  else
  begin
    Result := TAtlasProfilerToggle.Start;
  end;
end;

class function TAtlasProfilerFlow.ActsAsToggle(ABusy, ARunning: Boolean): Boolean;
begin
  Result := ABusy or ARunning;
end;

class function TAtlasProfilerFlow.SelectedRun(const ARuns: TArray<string>; const ASelect: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if ARuns <> nil then
  begin
    Result := 0;
  end;
  if ASelect = '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ARuns) do
  begin
    if SameText(ExtractFileName(ARuns[mIndex]), ExtractFileName(ASelect)) then
    begin
      Result := mIndex;
    end;
  end;
end;

class function TAtlasProfilerFlow.ResultFile(const APath, AFileName: string): string;
begin
  Result := APath;
  if Result = '' then
  begin
    Result := AFileName;
  end;
end;

class function TAtlasProfilerFlow.IsLoaded(const ALoadedPath, APath: string): Boolean;
begin
  Result := (APath <> '') and SameText(ALoadedPath, APath);
end;

class function TAtlasProfilerFlow.EditorLine(ALine: Integer): Integer;
begin
  Result := ALine - 1;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

end.
