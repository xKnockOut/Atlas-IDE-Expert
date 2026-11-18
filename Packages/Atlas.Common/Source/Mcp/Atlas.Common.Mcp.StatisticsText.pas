unit Atlas.Common.Mcp.StatisticsText;

// Anzeige der MCP-Aufrufstatistik (#2611) als Markdown für die Ressource delphi://stats und den Abschnitt in
// get_server_status, in Deutsch und Englisch: je Art (Werkzeuge, Ressourcen, Prompts) eine Tabelle mit Aufrufen,
// Fehlern, Dauer und Antwortgröße, darunter auffällige Fehlerquoten mit dem letzten fehlgeschlagenen Aufruf und
// der Verlauf der letzten Tage (nie aufgerufene Werkzeuge). Gekennzeichnete Werte (TLogMarks) erscheinen im
// Klartext; die Anzeige ist lokal. Die Zellen kommen aus TMcpCallSummary.Cells wie in AtlasMonitor und im Fenster
// „Atlas-Server“.

interface

uses
  System.SysUtils,
  Atlas.Text.McpStatistics;

type
  TMcpStatisticsText = record
  public
    /// <summary>Trennzeichen für Nachkommastellen in der Sprache der Texte.</summary>
    class function Decimal: Char; static;
    /// <summary>Platzhalter in Zahlenspalten ohne Aufruf („–“).</summary>
    class function None: string; static;
    /// <summary>Kopfzeile der Sitzung: Client, Beginn, Aufrufe und Fehler.</summary>
    class function SessionTitle(const AStats: TMcpSessionStatistics): string; static;
    /// <summary>Tabellen der Sitzung und auffällige Werkzeuge als Markdown.</summary>
    class function Markdown(const AStats: TMcpSessionStatistics): string; static;
    /// <summary>Verlauf als Markdown: Sitzungen, nie aufgerufene Werkzeuge, auffällige Fehlerquoten; '' ohne
    /// Zeilen.</summary>
    class function HistoryMarkdown(const ALines: TArray<string>): string; static;
    /// <summary>Hinweis, dass die Statistik abgeschaltet ist (mcp.statistics).</summary>
    class function SwitchedOff: string; static;
  end;

implementation

uses
  Atlas.Common.Mcp.StatisticsHistory,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TStatisticsText = (Title, NoClient, Tools, Resources, Prompts, Header, Separator, Conspicuous, None, Decimal,
    HistoryTitle, NeverCalled, OftenFailed, Off, NoCalls);

const
  cTexts: array[TStatisticsText] of TAtlasText = (
    (De: 'KI-Assistent „%s“ · Sitzung seit %s · %d Aufrufe, %d Fehler';
     En: 'AI assistant "%s" · session since %s · %d calls, %d errors'),
    (De: 'unbekannt'; En: 'unknown'),
    (De: 'Werkzeuge'; En: 'Tools'),
    (De: 'Ressourcen'; En: 'Resources'),
    (De: 'Prompts'; En: 'Prompts'),
    (De: '| Name | Aufrufe | Fehler | Median | Längste | Antwort (Median) | Größte |';
     En: '| Name | Calls | Errors | Median | Longest | Response (median) | Largest |'),
    (De: '| --- | ---: | ---: | ---: | ---: | ---: | ---: |'; En: '| --- | ---: | ---: | ---: | ---: | ---: | ---: |'),
    (De: 'Auffällig: %s, %d %% Fehler, letzter Aufruf %s'; En: 'Conspicuous: %s, %d %% errors, last call %s'),
    (De: '–'; En: '–'),
    (De: ','; En: '.'),
    (De: 'Verlauf der letzten %d Tage: %d Sitzungen'; En: 'History of the last %d days: %d sessions'),
    (De: 'Nie aufgerufen: %s'; En: 'Never called: %s'),
    (De: 'Häufig fehlgeschlagen: %s'; En: 'Often failed: %s'),
    (De: 'Die Aufrufstatistik ist abgeschaltet (mcp.statistics in atlas.json).';
     En: 'Call statistics are switched off (mcp.statistics in atlas.json).'),
    (De: 'Noch keine Aufrufe.'; En: 'No calls yet.'));

{$SCOPEDENUMS OFF}

const
  cKindTitles: array[TMcpCallKind] of TStatisticsText = (TStatisticsText.Tools, TStatisticsText.Resources,
    TStatisticsText.Prompts);

/// <summary>Markdown-Zelle: senkrechte Striche und Zeilenumbrüche entschärft.</summary>
function Cell(const AText: string): string;
begin
  Result := StringReplace(AText, '|', '\|', [rfReplaceAll]);
  Result := StringReplace(StringReplace(Result, #13#10, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
end;

function Row(const ACall: TMcpCallSummary): string;
var
  mCells: TArray<string>;
  mColumn: TMcpCallColumn;
begin
  mCells := ACall.Cells(TMcpStatisticsText.Decimal, TMcpStatisticsText.None);
  Result := '|';
  // Ohne die letzte Spalte: Der letzte Fehler steht unter der Tabelle bei den auffälligen Werkzeugen.
  for mColumn := Low(TMcpCallColumn) to Pred(TMcpCallColumn.LastFailed) do
  begin
    Result := Result + ' ' + Cell(mCells[Ord(mColumn)]) + ' |';
  end;
end;

/// <summary>Tabelle der Art AKind; '' ohne Einträge.</summary>
function KindTable(const AStats: TMcpSessionStatistics; AKind: TMcpCallKind): string;
var
  mCall: TMcpCallSummary;
begin
  Result := '';
  for mCall in AStats.Calls do
  begin
    if mCall.Kind = AKind then
    begin
      Result := Result + Row(mCall) + #10;
    end;
  end;
  if Result <> '' then
  begin
    Result := '### ' + cTexts[cKindTitles[AKind]].Text + #10 + #10 + cTexts[TStatisticsText.Header].Text + #10 +
      cTexts[TStatisticsText.Separator].Text + #10 + Result + #10;
  end;
end;

function Conspicuous(const AStats: TMcpSessionStatistics): string;
var
  mCall: TMcpCallSummary;
begin
  Result := '';
  for mCall in AStats.Calls do
  begin
    if mCall.Conspicuous then
    begin
      Result := Result + '- ' + cTexts[TStatisticsText.Conspicuous].Fmt([mCall.Name, mCall.ErrorPercent,
        mCall.LastFailedText]) + #10;
    end;
  end;
end;

/// <summary>Namen als Aufzählung mit Komma.</summary>
function NameList(const ANames: TArray<string>): string;
begin
  Result := string.Join(', ', ANames);
end;

{ TMcpStatisticsText }

class function TMcpStatisticsText.Decimal: Char;
begin
  Result := cTexts[TStatisticsText.Decimal].Text[1];
end;

class function TMcpStatisticsText.None: string;
begin
  Result := cTexts[TStatisticsText.None].Text;
end;

class function TMcpStatisticsText.SessionTitle(const AStats: TMcpSessionStatistics): string;
var
  mClient: string;
begin
  mClient := AStats.Client;
  if mClient = '' then
  begin
    mClient := cTexts[TStatisticsText.NoClient].Text;
  end;
  Result := cTexts[TStatisticsText.Title].Fmt([mClient, FormatDateTime('hh":"nn', AStats.Started),
    AStats.TotalCalls, AStats.TotalErrors]);
end;

class function TMcpStatisticsText.Markdown(const AStats: TMcpSessionStatistics): string;
var
  mKind: TMcpCallKind;
  mConspicuous: string;
begin
  Result := '## ' + SessionTitle(AStats) + #10 + #10;
  if Length(AStats.Calls) = 0 then
  begin
    Exit(Result + cTexts[TStatisticsText.NoCalls].Text + #10);
  end;
  for mKind := Low(TMcpCallKind) to High(TMcpCallKind) do
  begin
    Result := Result + KindTable(AStats, mKind);
  end;
  mConspicuous := Conspicuous(AStats);
  if mConspicuous <> '' then
  begin
    Result := Result + mConspicuous + #10;
  end;
end;

class function TMcpStatisticsText.HistoryMarkdown(const ALines: TArray<string>): string;
var
  mTotal: TMcpHistoryTotal;
  mNever, mFailed: TArray<string>;
  mCall: TMcpCallSummary;
begin
  Result := '';
  if Length(ALines) = 0 then
  begin
    Exit;
  end;
  mNever := nil;
  mFailed := nil;
  for mTotal in TMcpStatisticsHistory.Totals(ALines) do
  begin
    if (mTotal.Kind = TMcpCallKind.Tool) and (mTotal.Calls = 0) then
    begin
      mNever := mNever + [mTotal.Name];
    end;
    mCall := Default(TMcpCallSummary);
    mCall.Calls := mTotal.Calls;
    mCall.Errors := mTotal.Errors;
    if mCall.Conspicuous then
    begin
      mFailed := mFailed + [Format('%s (%d/%d)', [mTotal.Name, mTotal.Errors, mTotal.Calls])];
    end;
  end;
  Result := '### ' + cTexts[TStatisticsText.HistoryTitle].Fmt([TMcpStatisticsHistory.cKeepDays,
    TMcpStatisticsHistory.SessionCount(ALines)]) + #10 + #10;
  if mNever <> nil then
  begin
    Result := Result + '- ' + cTexts[TStatisticsText.NeverCalled].Fmt([NameList(mNever)]) + #10;
  end;
  if mFailed <> nil then
  begin
    Result := Result + '- ' + cTexts[TStatisticsText.OftenFailed].Fmt([NameList(mFailed)]) + #10;
  end;
end;

class function TMcpStatisticsText.SwitchedOff: string;
begin
  Result := cTexts[TStatisticsText.Off].Text;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.StatisticsText', cTexts);

end.
