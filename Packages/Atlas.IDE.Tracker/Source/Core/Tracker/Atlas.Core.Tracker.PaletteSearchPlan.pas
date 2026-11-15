unit Atlas.Core.Tracker.PaletteSearchPlan;

// Entscheidungen der Issue-Suche in der Befehlspalette (#1270) ohne IDE prüfbar (#1967); die IDE
// (Atlas.IDE.Tracker.PaletteSearch) ruft nur noch Zeitgeber, Transport, Hooks und Zwischenablage:
// - was mit einer Antwort geschieht (zeigen, still verwerfen, Fehler) und welcher Fehlertext passt;
// - das anonyme Protokoll der Antwort (Anbieter, Anzahl, Fehlerart; nie Suchtext oder Kennung);
// - welches Issue eine Zeile meint, der Schlüssel der Entprellung, der Hinweis ohne Tracker und welche Tasten
//   einen Übergang des aktuellen Issues ausführen.

interface

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.PaletteSearch;

type
{$SCOPEDENUMS ON}
  /// <summary>Was mit einer Antwort geschieht: Treffer zeigen, still verwerfen (abgebrochen), Fehler zeigen.
  /// </summary>
  TAtlasIssueSearchAnswer = (Show, Ignore, Error);
  /// <summary>Fehlertext der Gruppe „Issues“.</summary>
  TAtlasIssueSearchError = (Config, Token, KeyNotFound, NoneFound, Timeout, Network, Invalid);
{$SCOPEDENUMS OFF}

  TAtlasIssuePaletteSearchPlan = class
  public
    class function AnswerOf(ASucceeded: Boolean; AError: TAtlasCiFetchError): TAtlasIssueSearchAnswer; static;
    /// <summary>Fehlertext zu AError: „nicht gefunden“ nennt bei einer Kennung (AKind Key) die Kennung, sonst
    /// „keine Treffer“.</summary>
    class function ErrorOf(AError: TAtlasCiFetchError; AKind: TAtlasIssueSearchKind): TAtlasIssueSearchError;
      static;
    /// <summary>Protokollzeile der Antwort, anonym: Anbieter AProvider, Anzahl oder Fehlerart.</summary>
    class function AnswerLog(const AProvider: string; ASucceeded: Boolean; ACount: Integer;
      AError: TAtlasCiFetchError): string; static;
    /// <summary>Issue zur Zeile AItem: aus AIssues (Kennung ohne Groß-/Kleinschreibung), sonst aus Id und
    /// Beschreibung der Zeile; False ohne Id.</summary>
    class function IssueOf(const AIssues: TArray<TAtlasTrackerIssue>; const AItem: TAtlasCommand;
      out AIssue: TAtlasTrackerIssue): Boolean; static;
    /// <summary>Schlüssel der Entprellung zu AQuery.</summary>
    class function InputKey(const AQuery: TAtlasIssueSearchQuery): string; static;
    /// <summary>Gehört APattern ohne Tracker trotzdem zur Issue-Suche ("#…")? Dann ein Hinweis statt der Befehle.
    /// </summary>
    class function IsIssueInput(const APattern: string): Boolean; static;
    /// <summary>Führt AAction einen Übergang des aktuellen Issues aus (Enter und Strg+Enter)?</summary>
    class function RunsState(AAction: TAtlasPaletteAction): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  // Protokoll anonym: Anbieter, Anzahl und Fehlerart, nie Suchtext, Kennung oder Adresse.
  cLogAnswer = 'Palettensuche: %s, %s';
  cLogHits = '%d Treffer';
  cLogNoAnswer = 'keine Antwort (%s)'; // german-ok: Protokollzeile, unverändert aus der Palettensuche übernommen

class function TAtlasIssuePaletteSearchPlan.AnswerOf(ASucceeded: Boolean;
  AError: TAtlasCiFetchError): TAtlasIssueSearchAnswer;
begin
  if ASucceeded then
  begin
    Result := TAtlasIssueSearchAnswer.Show;
  end
  else if AError = TAtlasCiFetchError.Cancelled then
  begin
    Result := TAtlasIssueSearchAnswer.Ignore;
  end
  else
  begin
    Result := TAtlasIssueSearchAnswer.Error;
  end;
end;

class function TAtlasIssuePaletteSearchPlan.ErrorOf(AError: TAtlasCiFetchError;
  AKind: TAtlasIssueSearchKind): TAtlasIssueSearchError;
begin
  case AError of
    TAtlasCiFetchError.NotConfigured:
      Result := TAtlasIssueSearchError.Config;
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasIssueSearchError.Token;
    TAtlasCiFetchError.NotFound:
      if AKind = TAtlasIssueSearchKind.Key then
      begin
        Result := TAtlasIssueSearchError.KeyNotFound;
      end
      else
      begin
        Result := TAtlasIssueSearchError.NoneFound;
      end;
    TAtlasCiFetchError.Timeout:
      Result := TAtlasIssueSearchError.Timeout;
    TAtlasCiFetchError.Network:
      Result := TAtlasIssueSearchError.Network;
  else
    Result := TAtlasIssueSearchError.Invalid;
  end;
end;

class function TAtlasIssuePaletteSearchPlan.AnswerLog(const AProvider: string; ASucceeded: Boolean;
  ACount: Integer; AError: TAtlasCiFetchError): string;
var
  mState: string;
begin
  if ASucceeded then
  begin
    mState := Format(cLogHits, [ACount]);
  end
  else
  begin
    mState := Format(cLogNoAnswer, [TAtlasCiBuild.ErrorKey(AError)]);
  end;
  Result := Format(cLogAnswer, [AProvider, mState]);
end;

class function TAtlasIssuePaletteSearchPlan.IssueOf(const AIssues: TArray<TAtlasTrackerIssue>;
  const AItem: TAtlasCommand; out AIssue: TAtlasTrackerIssue): Boolean;
var
  mIssue: TAtlasTrackerIssue;
begin
  for mIssue in AIssues do
  begin
    if SameText(mIssue.Key, AItem.Id) then
    begin
      AIssue := mIssue;
      Exit(True);
    end;
  end;
  AIssue := TAtlasTrackerIssue.Empty;
  AIssue.Key := AItem.Id;
  AIssue.Title := AItem.Description;
  Result := AItem.Id <> '';
end;

class function TAtlasIssuePaletteSearchPlan.InputKey(const AQuery: TAtlasIssueSearchQuery): string;
begin
  Result := AQuery.Key + '|' + AQuery.Text;
end;

class function TAtlasIssuePaletteSearchPlan.IsIssueInput(const APattern: string): Boolean;
begin
  Result := StartsStr('#', TrimLeft(APattern));
end;

class function TAtlasIssuePaletteSearchPlan.RunsState(AAction: TAtlasPaletteAction): Boolean;
begin
  Result := AAction in [TAtlasPaletteAction.Open, TAtlasPaletteAction.Start];
end;

end.
