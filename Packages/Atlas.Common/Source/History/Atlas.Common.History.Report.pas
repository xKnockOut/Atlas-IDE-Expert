unit Atlas.Common.History.Report;

// Antwort von get_symbol_history (#2641): Markdown mit einer Zeile je Commit (Datum, Kennung, was geschah, Zeilen,
// Autor, erste Zeile der Nachricht), den Issues und der erreichten Grenze; JSON mit denselben Angaben.

interface

uses
  System.SysUtils,
  Atlas.Common.History.Contract;

type
  TSymbolHistoryReport = class
  public const
    /// <summary>Länge der Kennung eines Git-Commits in der Markdown-Antwort.</summary>
    cShortRevision = 8;
  public
    class function Markdown(const AResult: TSymbolHistoryResult; ALimit, ATimeoutMs: Integer): string; static;
    class function Json(const AResult: TSymbolHistoryResult; ALimit: Integer): string; static;
    /// <summary>Satz zur Grenze AResult.Stop; '' bei None.</summary>
    class function StopText(const AResult: TSymbolHistoryResult; ALimit, ATimeoutMs: Integer): string; static;
    /// <summary>Unit-Name aus einem Pfad mit "/": Src/Foo.Bar.pas → Foo.Bar.</summary>
    class function UnitOfPath(const APath: string): string; static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.History.Service,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  THistoryReportText = (Header, HeaderOne, Changed, Introduced, Renamed, Moved, MovedRenamed, Issues, StopLimit,
    StopTime, StopCancelled, StopHops, StopNoHistory, StopFailed, NoMoves, Cached);

{$SCOPEDENUMS OFF}

const
  cTexts: array[THistoryReportText] of TAtlasText = (
    (De: '%s – %d Änderungen (%s, Stand %s)'; En: '%s – %d changes (%s, state %s)'),
    (De: '%s – 1 Änderung (%s, Stand %s)'; En: '%s – 1 change (%s, state %s)'),
    (De: 'geändert'; En: 'changed'),
    (De: 'eingeführt'; En: 'introduced'),
    (De: 'umbenannt aus %s'; En: 'renamed from %s'),
    (De: 'verschoben aus %s nach %s'; En: 'moved from %s to %s'),
    (De: 'verschoben aus %s nach %s (vorher %s)'; En: 'moved from %s to %s (was %s)'),
    (De: 'Issues: %s'; En: 'Issues: %s'),
    (De: 'Grenze erreicht: höchstens %d Einträge (limit); ältere Änderungen fehlen.';
     En: 'Limit reached: at most %d entries (limit); older changes are missing.'),
    (De: 'Zeitlimit von %d ms erreicht (requestTimeoutMs); ältere Änderungen fehlen.';
     En: 'Time limit of %d ms reached (requestTimeoutMs); older changes are missing.'),
    (De: 'Abgebrochen; ältere Änderungen fehlen.'; En: 'Cancelled; older changes are missing.'),
    (De: 'Nach %d Umbenennungen bzw. Verschiebungen nicht weiter verfolgt.';
     En: 'Not followed further after %d renames or moves.'),
    (De: 'Keine Commits für den Bereich: Die Datei ist noch nicht übernommen oder der Verlauf reicht nicht so weit.';
     En: 'No commits for the range: the file is not committed yet or the history does not reach that far.'),
    (De: 'Die Versionsverwaltung ist gescheitert; ältere Änderungen fehlen.';
     En: 'Version control failed; older changes are missing.'),
    (De: 'Umbenennen und Verschieben werden nur mit Git verfolgt.'; En: 'Renames and moves are followed with Git only.'),
    (De: '(aus dem Zwischenspeicher)'; En: '(from the cache)'));

class function TSymbolHistoryReport.UnitOfPath(const APath: string): string;
begin
  Result := Copy(APath, LastDelimiter('/\', APath) + 1, MaxInt);
  Result := ChangeFileExt(Result, '');
end;

class function TSymbolHistoryReport.StopText(const AResult: TSymbolHistoryResult; ALimit, ATimeoutMs: Integer): string;
begin
  case AResult.Stop of
    TSymbolHistoryStop.Limit:
      Result := cTexts[THistoryReportText.StopLimit].Fmt([ALimit]);
    TSymbolHistoryStop.TimeLimit:
      Result := cTexts[THistoryReportText.StopTime].Fmt([ATimeoutMs]);
    TSymbolHistoryStop.Cancelled:
      Result := cTexts[THistoryReportText.StopCancelled].Text;
    TSymbolHistoryStop.Hops:
      Result := cTexts[THistoryReportText.StopHops].Fmt([TSymbolHistoryService.cMaxHops]);
    TSymbolHistoryStop.NoHistory:
      Result := cTexts[THistoryReportText.StopNoHistory].Text;
    TSymbolHistoryStop.Failed:
      Result := cTexts[THistoryReportText.StopFailed].Text;
  else
    Result := '';
  end;
end;

function ShortRevision(const ARevision: string): string;
begin
  Result := Copy(ARevision, 1, TSymbolHistoryReport.cShortRevision);
end;

/// <summary>Was der Commit mit dem Symbol gemacht hat, als Text.</summary>
function EventText(const AEvent: TSymbolEvent): string;
begin
  case AEvent.Kind of
    TSymbolEventKind.Introduced:
      Result := cTexts[THistoryReportText.Introduced].Text;
    TSymbolEventKind.Renamed:
      Result := cTexts[THistoryReportText.Renamed].Fmt([AEvent.FromSymbol]);
    TSymbolEventKind.Moved:
      if SameText(AEvent.FromSymbol, AEvent.Symbol) then
      begin
        Result := cTexts[THistoryReportText.Moved].Fmt([TSymbolHistoryReport.UnitOfPath(AEvent.FromPath),
          TSymbolHistoryReport.UnitOfPath(AEvent.Path)]);
      end
      else
      begin
        Result := cTexts[THistoryReportText.MovedRenamed].Fmt([TSymbolHistoryReport.UnitOfPath(AEvent.FromPath),
          TSymbolHistoryReport.UnitOfPath(AEvent.Path), AEvent.FromSymbol]);
      end;
  else
    Result := cTexts[THistoryReportText.Changed].Text;
  end;
  if AEvent.Added >= 0 then
  begin
    Result := Result + ' (+' + IntToStr(AEvent.Added) + ' −' + IntToStr(AEvent.Deleted) + ')';
  end;
end;

/// <summary>Alle Kennungen der Ereignisse ohne Doppelte, neueste zuerst.</summary>
function AllIssues(const AEvents: TArray<TSymbolEvent>): TArray<string>;
var
  mSeen: TDictionary<string, Boolean>;
  mEvent: TSymbolEvent;
  mKey: string;
begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mEvent in AEvents do
    begin
      for mKey in mEvent.Issues do
      begin
        if not mSeen.ContainsKey(UpperCase(mKey)) then
        begin
          mSeen.Add(UpperCase(mKey), True);
          Result := Result + [mKey];
        end;
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

/// <summary>Kopfzeile: Symbol, Anzahl, Versionsverwaltung und Stand.</summary>
function HeaderText(const AResult: TSymbolHistoryResult): string;
begin
  if Length(AResult.Events) = 1 then
  begin
    Result := cTexts[THistoryReportText.HeaderOne].Fmt([AResult.Symbol, THotspots.KindName(AResult.Kind),
      ShortRevision(AResult.Head)]);
  end
  else
  begin
    Result := cTexts[THistoryReportText.Header].Fmt([AResult.Symbol, Length(AResult.Events),
      THotspots.KindName(AResult.Kind), ShortRevision(AResult.Head)]);
  end;
  if AResult.Cached then
  begin
    Result := Result + ' ' + cTexts[THistoryReportText.Cached].Text;
  end;
end;

class function TSymbolHistoryReport.Markdown(const AResult: TSymbolHistoryResult; ALimit, ATimeoutMs: Integer): string;
var
  mBuilder: TStringBuilder;
  mEvent: TSymbolEvent;
  mIssues: TArray<string>;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append(HeaderText(AResult));
    for mEvent in AResult.Events do
    begin
      // Verkettet statt Format: Free Pascal verliert in %s-Argumenten Zeichen wie "−" und "→".
      mBuilder.Append(#10).Append((FormatDateTime('yyyy-mm-dd', mEvent.Date, TFormatSettings.Invariant) + '  ' +
        ShortRevision(mEvent.Revision) + '  ' + EventText(mEvent) + '  ' + mEvent.Author + '  ' +
        mEvent.Summary).TrimRight);
    end;
    mIssues := AllIssues(AResult.Events);
    if Length(mIssues) > 0 then
    begin
      mBuilder.Append(#10#10).Append(cTexts[THistoryReportText.Issues].Fmt([string.Join(', ', mIssues)]));
    end;
    if AResult.Stop <> TSymbolHistoryStop.None then
    begin
      mBuilder.Append(#10#10).Append(StopText(AResult, ALimit, ATimeoutMs));
    end;
    if (AResult.Kind = THotspotVcsKind.Svn) and not AResult.FollowedMoves then
    begin
      mBuilder.Append(#10).Append(cTexts[THistoryReportText.NoMoves].Text);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function EventJson(const AEvent: TSymbolEvent): TJSONObject;
var
  mIssues: TJSONArray;
  mKey: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', TSymbolHistory.EventKey(AEvent.Kind));
  Result.AddPair('revision', AEvent.Revision);
  Result.AddPair('date', FormatDateTime('yyyy-mm-dd"T"hh":"nn":"ss"Z"', AEvent.Date, TFormatSettings.Invariant));
  Result.AddPair('author', AEvent.Author);
  Result.AddPair('summary', AEvent.Summary);
  Result.AddPair('added', TJSONNumber.Create(AEvent.Added));
  Result.AddPair('deleted', TJSONNumber.Create(AEvent.Deleted));
  mIssues := TJSONArray.Create;
  Result.AddPair('issues', mIssues);
  for mKey in AEvent.Issues do
  begin
    mIssues.Add(mKey);
  end;
  Result.AddPair('symbol', AEvent.Symbol);
  Result.AddPair('path', AEvent.Path);
  if AEvent.Kind in [TSymbolEventKind.Renamed, TSymbolEventKind.Moved] then
  begin
    Result.AddPair('fromSymbol', AEvent.FromSymbol);
    Result.AddPair('fromPath', AEvent.FromPath);
    Result.AddPair('similarity', TJSONNumber.Create(Round(AEvent.Similarity * 100) / 100));
  end;
end;

class function TSymbolHistoryReport.Json(const AResult: TSymbolHistoryResult; ALimit: Integer): string;
var
  mRoot: TJSONObject;
  mEvents: TJSONArray;
  mEvent: TSymbolEvent;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', 'json');
    mRoot.AddPair('symbol', AResult.Symbol);
    mRoot.AddPair('path', AResult.Path);
    mRoot.AddPair('vcs', THotspots.KindName(AResult.Kind));
    mRoot.AddPair('head', AResult.Head);
    mRoot.AddPair('count', TJSONNumber.Create(Length(AResult.Events)));
    mRoot.AddPair('limit', TJSONNumber.Create(ALimit));
    mRoot.AddPair('complete', TJSONBool.Create(AResult.Stop = TSymbolHistoryStop.None));
    mRoot.AddPair('stop', TSymbolHistory.StopKey(AResult.Stop));
    mRoot.AddPair('followMoves', TJSONBool.Create(AResult.FollowedMoves));
    mRoot.AddPair('cached', TJSONBool.Create(AResult.Cached));
    mEvents := TJSONArray.Create;
    mRoot.AddPair('events', mEvents);
    for mEvent in AResult.Events do
    begin
      mEvents.AddElement(EventJson(mEvent));
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.History.Report', cTexts);

end.
