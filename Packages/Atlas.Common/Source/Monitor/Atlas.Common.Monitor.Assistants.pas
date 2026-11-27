unit Atlas.Common.Monitor.Assistants;

// Logik des Reiters „KI-Assistenten“ (AI assistants) von AtlasMonitor (#2611): die Sitzungen der laufenden
// MCP-Prozesse aus ihren Statusdateien (Abschnitt mcp), eine Zeile je Sitzung über der Tabelle, Spalten und
// Zellen der Tabelle (Werkzeuge, Ressourcen, Prompts aller Sitzungen, Zellen aus TMcpCallSummary.Cells wie in
// delphi://stats und im Fenster „Atlas-Server“ der IDE), Einzelheiten der gewählten Zeile mit dem letzten
// fehlgeschlagenen Aufruf. Auffällige Fehlerquoten (über 20 % bei mindestens 5 Aufrufen) hebt die Oberfläche
// hervor. Texte in Deutsch und Englisch; ohne VCL und Windows, damit die Regeln testbar bleiben.

interface

uses
  System.SysUtils,
  Atlas.Text.McpStatistics,
  Atlas.Common.Diagnostics.StatusFile;

type
  TMonitorAssistants = record
  public
    /// <summary>Sitzungen der MCP-Prozesse unter AEntries, nach Beginn und pid.</summary>
    class function Sessions(const AEntries: TArray<TServerStatusEntry>): TArray<TMcpAssistantSession>; static;
    /// <summary>Spaltenköpfe: KI-Assistent, Name, Aufrufe, Fehler, Median, Längste, Antwort (Median), Größte,
    /// letzter fehlgeschlagener Aufruf.</summary>
    class function ColumnTitles: TArray<string>; static;
    /// <summary>Zellen von ARow zu ColumnTitles.</summary>
    class function Columns(const ASessions: TArray<TMcpAssistantSession>; const ARow: TMcpAssistantRow):
      TArray<string>; static;
    /// <summary>Zeile einer Sitzung: Client, Prozess, Beginn, Projekt, Aufrufe und Fehler; bzw. „zählt nicht“.
    /// </summary>
    class function SessionLine(const ASession: TMcpAssistantSession): string; static;
    /// <summary>Zeilen über der Tabelle: je Sitzung SessionLine, dazu die Zahl auffälliger Zeilen; ohne Sitzung
    /// ein Hinweis.</summary>
    class function Summary(const ASessions: TArray<TMcpAssistantSession>): TArray<string>; static;
    /// <summary>Einzelheiten von ARow als Zeilen „Name: Wert“.</summary>
    class function Details(const ASessions: TArray<TMcpAssistantSession>; const ARow: TMcpAssistantRow):
      TArray<string>; static;
    /// <summary>Hinweis ohne gewählte Zeile.</summary>
    class function SelectRow: string; static;
    /// <summary>Beschriftung des Reiters.</summary>
    class function TabCaption: string; static;
  end;

implementation

uses
  Atlas.Text.LogMarks,
  Atlas.Common.Localization.Texts;

type
  {$SCOPEDENUMS ON}
  TMonitorAssistantText = (Tab, ColumnAssistant, ColumnName, ColumnCalls, ColumnErrors, ColumnMedian,
    ColumnLongest, ColumnResponse, ColumnLargest, ColumnLastFailed, Unknown, None, Decimal, Session,
    SessionProject, NotCounting, NoAssistants, Conspicuous, AssistantCell, SelectRow, DetailAssistant, DetailKind,
    DetailCalls, DetailErrors, DetailDuration, DetailResponse, DetailLastFailed, DetailArguments, DetailMessage,
    DetailConspicuous, KindTool, KindResource, KindPrompt);
  {$SCOPEDENUMS OFF}

const
  cTexts: array[TMonitorAssistantText] of TAtlasText = (
    (De: 'KI-Assistenten'; En: 'AI assistants'),
    (De: 'KI-Assistent'; En: 'AI assistant'),
    (De: 'Name'; En: 'Name'),
    (De: 'Aufrufe'; En: 'Calls'),
    (De: 'Fehler'; En: 'Errors'),
    (De: 'Median'; En: 'Median'),
    (De: 'Längste'; En: 'Longest'),
    (De: 'Antwort (Median)'; En: 'Response (median)'),
    (De: 'Größte'; En: 'Largest'),
    (De: 'Letzter fehlgeschlagener Aufruf'; En: 'Last failed call'),
    (De: 'unbekannt'; En: 'unknown'),
    (De: '–'; En: '–'),
    (De: ','; En: '.'),
    (De: 'KI-Assistent „%s“ (Prozess %d) · Sitzung seit %s · %d Aufrufe, %d Fehler';
     En: 'AI assistant "%s" (process %d) · session since %s · %d calls, %d errors'),
    (De: ' · Projekt %s'; En: ' · project %s'),
    (De: 'KI-Assistent (Prozess %d): zählt keine Aufrufe (mcp.statistics aus oder älterer Server)';
     En: 'AI assistant (process %d): does not count calls (mcp.statistics off or older server)'),
    (De: 'Kein KI-Assistent verbunden. Sobald ein KI-Assistent die Atlas-Werkzeuge über MCP nutzt, erscheinen ' +
       'hier seine Aufrufe.';
     En: 'No AI assistant connected. As soon as an AI assistant uses the Atlas tools via MCP, its calls appear ' +
       'here.'),
    (De: 'Auffällige Fehlerquote (über %d %%, rot): %d'; En: 'Conspicuous error rate (over %d %%, red): %d'),
    (De: '%s (%d)'; En: '%s (%d)'),
    (De: 'Eine Zeile wählen, um den letzten fehlgeschlagenen Aufruf zu sehen.';
     En: 'Select a row to see the last failed call.'),
    (De: 'KI-Assistent: %s (Prozess %d)'; En: 'AI assistant: %s (process %d)'),
    (De: '%s: %s'; En: '%s: %s'),
    (De: 'Aufrufe: %d'; En: 'Calls: %d'),
    (De: 'Fehler: %d (%d %%)'; En: 'Errors: %d (%d %%)'),
    (De: 'Dauer: Median %s, längste %s'; En: 'Duration: median %s, longest %s'),
    (De: 'Antwort: Median %s, größte %s'; En: 'Response: median %s, largest %s'),
    (De: 'Letzter fehlgeschlagener Aufruf: %s'; En: 'Last failed call: %s'),
    (De: 'Argumente: %s'; En: 'Arguments: %s'),
    (De: 'Meldung: %s'; En: 'Message: %s'),
    (De: 'Auffällige Fehlerquote: mehr als %d %% bei mindestens %d Aufrufen';
     En: 'Conspicuous error rate: more than %d %% with at least %d calls'),
    (De: 'Werkzeug'; En: 'Tool'),
    (De: 'Ressource'; En: 'Resource'),
    (De: 'Prompt'; En: 'Prompt'));

function Txt(AText: TMonitorAssistantText): string;
begin
  Result := cTexts[AText].Text;
end;

function KindText(AKind: TMcpCallKind): string;
begin
  case AKind of
    TMcpCallKind.Resource:
      Result := Txt(TMonitorAssistantText.KindResource);
    TMcpCallKind.Prompt:
      Result := Txt(TMonitorAssistantText.KindPrompt);
  else
    Result := Txt(TMonitorAssistantText.KindTool);
  end;
end;

/// <summary>Sitzung ASession aus ASessions; leere bei ungültigem Index.</summary>
function SessionAt(const ASessions: TArray<TMcpAssistantSession>; AIndex: Integer): TMcpAssistantSession;
begin
  Result := Default(TMcpAssistantSession);
  if (AIndex >= 0) and (AIndex <= High(ASessions)) then
  begin
    Result := ASessions[AIndex];
  end;
end;

{ TMonitorAssistants }

class function TMonitorAssistants.Sessions(const AEntries: TArray<TServerStatusEntry>):
  TArray<TMcpAssistantSession>;
var
  mEntry: TServerStatusEntry;
begin
  Result := nil;
  for mEntry in AEntries do
  begin
    if mEntry.Kind = TServerStatusEntry.cKindMcp then
    begin
      Result := Result + [TMcpAssistantSessions.FromStatus(mEntry.Pid, mEntry.Written, mEntry.Mcp)];
    end;
  end;
  TMcpAssistantSessions.Sort(Result);
end;

class function TMonitorAssistants.ColumnTitles: TArray<string>;
begin
  Result := TArray<string>.Create(Txt(TMonitorAssistantText.ColumnAssistant), Txt(TMonitorAssistantText.ColumnName),
    Txt(TMonitorAssistantText.ColumnCalls), Txt(TMonitorAssistantText.ColumnErrors),
    Txt(TMonitorAssistantText.ColumnMedian), Txt(TMonitorAssistantText.ColumnLongest),
    Txt(TMonitorAssistantText.ColumnResponse), Txt(TMonitorAssistantText.ColumnLargest),
    Txt(TMonitorAssistantText.ColumnLastFailed));
end;

class function TMonitorAssistants.Columns(const ASessions: TArray<TMcpAssistantSession>;
  const ARow: TMcpAssistantRow): TArray<string>;
var
  mSession: TMcpAssistantSession;
begin
  mSession := SessionAt(ASessions, ARow.Session);
  Result := TArray<string>.Create(cTexts[TMonitorAssistantText.AssistantCell].Fmt([
    mSession.ClientOr(Txt(TMonitorAssistantText.Unknown)), mSession.Pid])) +
    ARow.Call.Cells(Txt(TMonitorAssistantText.Decimal)[1], Txt(TMonitorAssistantText.None));
end;

class function TMonitorAssistants.SessionLine(const ASession: TMcpAssistantSession): string;
begin
  if not ASession.HasStatistics then
  begin
    Exit(cTexts[TMonitorAssistantText.NotCounting].Fmt([ASession.Pid]));
  end;
  Result := cTexts[TMonitorAssistantText.Session].Fmt([ASession.ClientOr(Txt(TMonitorAssistantText.Unknown)),
    ASession.Pid, FormatDateTime('hh":"nn', ASession.Statistics.Started), ASession.Statistics.TotalCalls,
    ASession.Statistics.TotalErrors]);
  if ASession.Statistics.Project <> '' then
  begin
    Result := Result + cTexts[TMonitorAssistantText.SessionProject].Fmt([
      TLogMarks.Plain(ASession.Statistics.Project)]);
  end;
end;

class function TMonitorAssistants.Summary(const ASessions: TArray<TMcpAssistantSession>): TArray<string>;
var
  mSession: TMcpAssistantSession;
  mConspicuous: Integer;
begin
  Result := nil;
  if ASessions = nil then
  begin
    Result := TArray<string>.Create(Txt(TMonitorAssistantText.NoAssistants));
    Exit;
  end;
  for mSession in ASessions do
  begin
    Result := Result + [SessionLine(mSession)];
  end;
  mConspicuous := TMcpAssistantSessions.ConspicuousCount(TMcpAssistantSessions.Rows(ASessions));
  if mConspicuous > 0 then
  begin
    Result := Result + [cTexts[TMonitorAssistantText.Conspicuous].Fmt([TMcpCallSummary.cConspicuousPercent,
      mConspicuous])];
  end;
end;

class function TMonitorAssistants.Details(const ASessions: TArray<TMcpAssistantSession>;
  const ARow: TMcpAssistantRow): TArray<string>;
var
  mSession: TMcpAssistantSession;
  mDecimal: Char;
  mCall: TMcpCallSummary;
begin
  mSession := SessionAt(ASessions, ARow.Session);
  mCall := ARow.Call;
  mDecimal := Txt(TMonitorAssistantText.Decimal)[1];
  Result := TArray<string>.Create(cTexts[TMonitorAssistantText.DetailAssistant].Fmt([
    mSession.ClientOr(Txt(TMonitorAssistantText.Unknown)), mSession.Pid]),
    cTexts[TMonitorAssistantText.DetailKind].Fmt([KindText(mCall.Kind), mCall.Name]),
    cTexts[TMonitorAssistantText.DetailCalls].Fmt([mCall.Calls]),
    cTexts[TMonitorAssistantText.DetailErrors].Fmt([mCall.Errors, mCall.ErrorPercent]));
  if mCall.Calls > 0 then
  begin
    Result := Result + [cTexts[TMonitorAssistantText.DetailDuration].Fmt([
      TMcpStatisticsFormat.DurationText(mCall.MedianMs, mDecimal),
      TMcpStatisticsFormat.DurationText(mCall.MaxMs, mDecimal)]),
      cTexts[TMonitorAssistantText.DetailResponse].Fmt([TMcpStatisticsFormat.SizeText(mCall.MedianBytes, mDecimal),
      TMcpStatisticsFormat.SizeText(mCall.MaxBytes, mDecimal)])];
  end;
  if mCall.Conspicuous then
  begin
    Result := Result + [cTexts[TMonitorAssistantText.DetailConspicuous].Fmt([TMcpCallSummary.cConspicuousPercent,
      TMcpCallSummary.cConspicuousCalls])];
  end;
  if mCall.LastFailed.At <> 0 then
  begin
    Result := Result + [cTexts[TMonitorAssistantText.DetailLastFailed].Fmt([FormatDateTime('yyyy-mm-dd hh:nn:ss',
      mCall.LastFailed.At, TFormatSettings.Invariant)]),
      cTexts[TMonitorAssistantText.DetailArguments].Fmt([TLogMarks.Plain(mCall.LastFailed.Arguments)]),
      cTexts[TMonitorAssistantText.DetailMessage].Fmt([TLogMarks.Plain(mCall.LastFailed.Message)])];
  end;
end;

class function TMonitorAssistants.SelectRow: string;
begin
  Result := Txt(TMonitorAssistantText.SelectRow);
end;

class function TMonitorAssistants.TabCaption: string;
begin
  Result := Txt(TMonitorAssistantText.Tab);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Monitor.Assistants', cTexts);

end.
