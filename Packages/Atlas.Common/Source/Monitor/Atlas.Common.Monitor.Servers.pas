unit Atlas.Common.Monitor.Servers;

// Logik des Reiters „Server“ und des Symbols im Infobereich von AtlasMonitor (#1901): Zustand eines Servers aus
// seiner Statusdatei (ruht, arbeitet, hängt), der schlechteste Zustand aller Server für das Symbol, die Texte für
// Liste, Kontextmenü, Hinweis und Einzelheiten in Deutsch und Englisch. Ohne VCL und Windows, damit die Regeln
// testbar bleiben; die Oberfläche zeigt nur an.

interface

uses
  System.SysUtils,
  Atlas.Common.Lsp.StatusFile;

type
  {$SCOPEDENUMS ON}
  /// <summary>Zustand für Punkt und Text: ruht, arbeitet, hängt (meldet sich nicht oder eine Anfrage läuft zu
  /// lange). Die Reihenfolge ist die Schwere.</summary>
  TMonitorHealth = (Idle, Busy, Hanging);
  {$SCOPEDENUMS OFF}

  TMonitorServers = record
  public const
    /// <summary>Schreibt ein Server so lange nicht (Takt 5 s), gilt er als hängend.</summary>
    cSilentSeconds = 20;
    /// <summary>Läuft eine Anfrage länger, gilt der Server als hängend (Zeitlimit der Anfragen: 10 s).</summary>
    cHangingRequestMs = 30000;
  public
    class function HealthOf(const AEntry: TServerStatusEntry; ANow: TDateTime): TMonitorHealth; static;
    /// <summary>Schlechtester Zustand aller Server; Idle ohne Server.</summary>
    class function Overall(const AEntries: TArray<TServerStatusEntry>; ANow: TDateTime): TMonitorHealth; static;
    class function HealthText(AHealth: TMonitorHealth): string; static;
    /// <summary>Art des Servers: IDE-Server, KI-Assistent (MCP), Kommandozeile mit Befehl.</summary>
    class function KindText(const AEntry: TServerStatusEntry): string; static;
    /// <summary>Ziel bzw. erster Ordner; '' ohne.</summary>
    class function PlaceOf(const AEntry: TServerStatusEntry): string; static;
    /// <summary>Zeile im Kontextmenü: Art, Ort, Zustand und pid.</summary>
    class function MenuText(const AEntry: TServerStatusEntry; ANow: TDateTime): string; static;
    /// <summary>Hinweis am Symbol: Zahl der Server und schlechtester Zustand (höchstens 127 Zeichen).</summary>
    class function Hint(const AEntries: TArray<TServerStatusEntry>; ANow: TDateTime): string; static;
    /// <summary>Spaltenköpfe der Liste: Art, Ort, Zustand, Speicher, pid, Version.</summary>
    class function ColumnTitles: TArray<string>; static;
    /// <summary>Zellen einer Zeile zu ColumnTitles.</summary>
    class function Columns(const AEntry: TServerStatusEntry; ANow: TDateTime): TArray<string>; static;
    /// <summary>Einzelheiten als Zeilen „Name: Wert“.</summary>
    class function Details(const AEntry: TServerStatusEntry; ANow: TDateTime): TArray<string>; static;
  end;

implementation

uses
  System.DateUtils,
  Atlas.Common.Localization.Texts;

type
  {$SCOPEDENUMS ON}
  TMonitorServerText = (Idle, Busy, Hanging, KindLsp, KindMcp, KindCli, KindCliCommand, Menu, NoServers, Servers,
    ColumnKind, ColumnPlace, ColumnState, ColumnMemory, ColumnPid, ColumnVersion, Megabytes, Process, Version,
    Started, Memory, State, Running, RunningRequest, MoreRequests, Progress, ProgressValue, Timeouts, Errors, Folders,
    Target, LogFile, LastReport, SecondsAgo);
  {$SCOPEDENUMS OFF}

const
  cTexts: array[TMonitorServerText] of TAtlasText = (
    (De: 'ruht'; En: 'idle'),
    (De: 'arbeitet'; En: 'working'),
    (De: 'hängt'; En: 'not responding'),
    (De: 'IDE-Server'; En: 'IDE server'),
    (De: 'KI-Assistent (MCP)'; En: 'AI assistant (MCP)'),
    (De: 'Kommandozeile'; En: 'Command line'),
    (De: 'Kommandozeile: %s'; En: 'Command line: %s'),
    (De: '%s · %s · %s (%d)'; En: '%s · %s · %s (%d)'),
    (De: 'Atlas: keine Server'; En: 'Atlas: no servers'),
    (De: 'Atlas-Server: %d, %s'; En: 'Atlas servers: %d, %s'),
    (De: 'Art'; En: 'Kind'),
    (De: 'Ordner bzw. Ziel'; En: 'Folder or target'),
    (De: 'Zustand'; En: 'State'),
    (De: 'Speicher'; En: 'Memory'),
    (De: 'Prozess'; En: 'Process'),
    (De: 'Version'; En: 'Version'),
    (De: '%d MB'; En: '%d MB'),
    (De: 'Prozess: %d'; En: 'Process: %d'),
    (De: 'Version: %s'; En: 'Version: %s'),
    (De: 'Gestartet: %s'; En: 'Started: %s'),
    (De: 'Speicher: %d MB'; En: 'Memory: %d MB'),
    (De: 'Zustand: %s (%s)'; En: 'State: %s (%s)'),
    (De: 'Laufende Anfragen: %d'; En: 'Running requests: %d'),
    (De: 'Längste Anfrage: %s seit %d s'; En: 'Longest request: %s for %d s'),
    (De: ' und %d weitere'; En: ' and %d more'),
    (De: 'Fortschritt: %s'; En: 'Progress: %s'),
    (De: '%d von %d'; En: '%d of %d'),
    (De: 'Zeitüberschreitungen: %d'; En: 'Timeouts: %d'),
    (De: 'Fehler: %d'; En: 'Errors: %d'),
    (De: 'Ordner: %s'; En: 'Folders: %s'),
    (De: 'Ziel: %s'; En: 'Target: %s'),
    (De: 'Protokoll: %s'; En: 'Log: %s'),
    (De: 'Letzte Meldung: %s'; En: 'Last report: %s'),
    (De: 'vor %d s'; En: '%d s ago'));

  cMegabyte = 1024 * 1024;
  /// <summary>Windows schneidet den Hinweis eines Symbols im Infobereich nach 127 Zeichen ab.</summary>
  cMaxHint = 127;

/// <summary>Sekunden seit AThen; 0, wenn AThen in der Zukunft liegt (Uhr verstellt).</summary>
function SecondsSince(AThen, ANow: TDateTime): Int64;
begin
  Result := 0;
  if ANow > AThen then
  begin
    Result := SecondsBetween(ANow, AThen);
  end;
end;

class function TMonitorServers.HealthOf(const AEntry: TServerStatusEntry; ANow: TDateTime): TMonitorHealth;
begin
  if (SecondsSince(AEntry.Written, ANow) > cSilentSeconds) or (AEntry.RunningMs > cHangingRequestMs) then
  begin
    Result := TMonitorHealth.Hanging;
  end
  else if (AEntry.Running > 0) or ((AEntry.State <> '') and (AEntry.State <> TServerStatusEntry.cStateReady)) then
  begin
    Result := TMonitorHealth.Busy;
  end
  else
  begin
    Result := TMonitorHealth.Idle;
  end;
end;

class function TMonitorServers.Overall(const AEntries: TArray<TServerStatusEntry>; ANow: TDateTime):
  TMonitorHealth;
var
  mEntry: TServerStatusEntry;
  mHealth: TMonitorHealth;
begin
  Result := TMonitorHealth.Idle;
  for mEntry in AEntries do
  begin
    mHealth := HealthOf(mEntry, ANow);
    if Ord(mHealth) > Ord(Result) then
    begin
      Result := mHealth;
    end;
  end;
end;

class function TMonitorServers.HealthText(AHealth: TMonitorHealth): string;
begin
  case AHealth of
    TMonitorHealth.Busy:
      Result := cTexts[TMonitorServerText.Busy].Text;
    TMonitorHealth.Hanging:
      Result := cTexts[TMonitorServerText.Hanging].Text;
  else
    Result := cTexts[TMonitorServerText.Idle].Text;
  end;
end;

class function TMonitorServers.KindText(const AEntry: TServerStatusEntry): string;
begin
  if AEntry.Kind = TServerStatusEntry.cKindMcp then
  begin
    Result := cTexts[TMonitorServerText.KindMcp].Text;
  end
  else if (AEntry.Kind = TServerStatusEntry.cKindCli) and (AEntry.Command <> '') then
  begin
    Result := cTexts[TMonitorServerText.KindCliCommand].Fmt([AEntry.Command]);
  end
  else if AEntry.Kind = TServerStatusEntry.cKindCli then
  begin
    Result := cTexts[TMonitorServerText.KindCli].Text;
  end
  else
  begin
    Result := cTexts[TMonitorServerText.KindLsp].Text;
  end;
end;

class function TMonitorServers.PlaceOf(const AEntry: TServerStatusEntry): string;
begin
  Result := AEntry.Target;
  if (Result = '') and (AEntry.Roots <> nil) then
  begin
    Result := AEntry.Roots[0];
  end;
end;

class function TMonitorServers.MenuText(const AEntry: TServerStatusEntry; ANow: TDateTime): string;
begin
  Result := cTexts[TMonitorServerText.Menu].Fmt([KindText(AEntry), PlaceOf(AEntry),
    HealthText(HealthOf(AEntry, ANow)), AEntry.Pid]);
end;

class function TMonitorServers.Hint(const AEntries: TArray<TServerStatusEntry>; ANow: TDateTime): string;
begin
  if AEntries = nil then
  begin
    Result := cTexts[TMonitorServerText.NoServers].Text;
  end
  else
  begin
    Result := cTexts[TMonitorServerText.Servers].Fmt([Length(AEntries), HealthText(Overall(AEntries, ANow))]);
  end;
  if Length(Result) > cMaxHint then
  begin
    Result := Copy(Result, 1, cMaxHint);
  end;
end;

class function TMonitorServers.ColumnTitles: TArray<string>;
begin
  Result := TArray<string>.Create(cTexts[TMonitorServerText.ColumnKind].Text,
    cTexts[TMonitorServerText.ColumnPlace].Text, cTexts[TMonitorServerText.ColumnState].Text,
    cTexts[TMonitorServerText.ColumnMemory].Text, cTexts[TMonitorServerText.ColumnPid].Text,
    cTexts[TMonitorServerText.ColumnVersion].Text);
end;

class function TMonitorServers.Columns(const AEntry: TServerStatusEntry; ANow: TDateTime): TArray<string>;
begin
  Result := TArray<string>.Create(KindText(AEntry), PlaceOf(AEntry), HealthText(HealthOf(AEntry, ANow)),
    cTexts[TMonitorServerText.Megabytes].Fmt([AEntry.MemoryBytes div cMegabyte]), IntToStr(AEntry.Pid),
    AEntry.Version);
end;

/// <summary>Zeile zur längsten Anfrage, mit der Zahl der übrigen; '' ohne laufende Anfrage.</summary>
function RunningLine(const AEntry: TServerStatusEntry): string;
begin
  Result := '';
  if AEntry.Running <= 0 then
  begin
    Exit;
  end;
  Result := cTexts[TMonitorServerText.RunningRequest].Fmt([AEntry.RunningMethod, AEntry.RunningMs div 1000]);
  if AEntry.Running > 1 then
  begin
    Result := Result + cTexts[TMonitorServerText.MoreRequests].Fmt([AEntry.Running - 1]);
  end;
end;

/// <summary>Zeilen zu Ziel, Ordnern, Protokoll und Fortschritt; leere fallen weg.</summary>
function PlaceLines(const AEntry: TServerStatusEntry): TArray<string>;
begin
  Result := nil;
  if AEntry.Target <> '' then
  begin
    Result := Result + [cTexts[TMonitorServerText.Target].Fmt([AEntry.Target])];
  end;
  if AEntry.Roots <> nil then
  begin
    Result := Result + [cTexts[TMonitorServerText.Folders].Fmt([string.Join(', ', AEntry.Roots)])];
  end;
  if AEntry.LogFile <> '' then
  begin
    Result := Result + [cTexts[TMonitorServerText.LogFile].Fmt([AEntry.LogFile])];
  end;
  if AEntry.Total > 0 then
  begin
    Result := Result + [cTexts[TMonitorServerText.Progress].Fmt([
      cTexts[TMonitorServerText.ProgressValue].Fmt([AEntry.Done, AEntry.Total])])];
  end;
end;

class function TMonitorServers.Details(const AEntry: TServerStatusEntry; ANow: TDateTime): TArray<string>;
var
  mRunning: string;
begin
  Result := TArray<string>.Create(KindText(AEntry), cTexts[TMonitorServerText.Process].Fmt([AEntry.Pid]),
    cTexts[TMonitorServerText.Version].Fmt([AEntry.Version]),
    cTexts[TMonitorServerText.Started].Fmt([FormatDateTime('yyyy-mm-dd hh:nn:ss', AEntry.Started,
      TFormatSettings.Invariant)]),
    cTexts[TMonitorServerText.Memory].Fmt([AEntry.MemoryBytes div cMegabyte]),
    cTexts[TMonitorServerText.State].Fmt([HealthText(HealthOf(AEntry, ANow)), AEntry.State]),
    cTexts[TMonitorServerText.Running].Fmt([AEntry.Running]));
  mRunning := RunningLine(AEntry);
  if mRunning <> '' then
  begin
    Result := Result + [mRunning];
  end;
  Result := Result + PlaceLines(AEntry);
  Result := Result + [cTexts[TMonitorServerText.Timeouts].Fmt([AEntry.Timeouts]),
    cTexts[TMonitorServerText.Errors].Fmt([AEntry.Errors]),
    cTexts[TMonitorServerText.LastReport].Fmt([cTexts[TMonitorServerText.SecondsAgo].Fmt([
    SecondsSince(AEntry.Written, ANow)])])];
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Monitor.Servers', cTexts);

end.
