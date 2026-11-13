unit Atlas.UI.Tracker.IssueTip;

// Texte rund um eine Issue-Kennung ohne Fenster (#1265): der Hover über einer
// Kennung im Editor (Kennung oben, darunter Titel, Zustand, Zuständig,
// Aktualisiert und die Fußzeile mit Strg+Klick), dazu Zeitabstand („vor 3
// Std.“) und Fehlertext, die auch die Issue-Vorschau (#1264) nutzt.
// - Lädt: „Wird geladen …“; nicht gefunden (404): „Issue ATL-7 nicht
//   gefunden.“; andere Fehler: Grund wie in der Vorschau.
// - Fußzeile mit issues.preview: „Strg+Klick: Vorschau · Strg+Umschalt+Klick:
//   Browser“, ohne: „Strg+Klick: im Browser öffnen“.
// Für die Zeilenhistorie (#1275): je Kennung eine Zeile „ATL-97 · Titel ·
// Zustand“ im Hover, der Link „Issues zu dieser Methode (3)“ und die Zeilen
// des Ergebnisfensters („ATL-97 · Titel · Zustand · vor 3 Tagen · 4 Commits“,
// darunter je Commit „abc1234 · anna · 12.10.2026 · Betreff“).

interface

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract;

type
  /// <summary>Stand der Kurzvorschau einer Kennung.</summary>
  TAtlasIssueTipState = (Loading, Found, NotFound, Failed);

  TAtlasIssueTip = class
  public
    /// <summary>Zeitabstand von ATime bis ANow (beide UTC) wie „vor 3 Std.“.</summary>
    class function AgeText(ATime, ANow: TDateTime): string; static;
    /// <summary>Grund, warum das Issue AKey nicht geladen wurde.</summary>
    class function ErrorText(AError: TAtlasCiFetchError; const AKey: string): string; static;
    /// <summary>Text des Hovers über AKey (sein Titel ist AKey). ADetails gilt nur bei Found; AError nur bei
    /// Failed; APreview: issues.preview an (Strg+Klick öffnet die Vorschau).</summary>
    class function Compose(const AKey: string; AState: TAtlasIssueTipState; const ADetails: TAtlasTrackerDetails;
      AError: TAtlasCiFetchError; ANow: TDateTime; APreview: Boolean): string; static;
    /// <summary>Zeile einer Kennung im Hover der Zeilenhistorie (#1275): "ATL-97 · Titel · Zustand", sonst
    /// "ATL-97 · Wird geladen …" bzw. "ATL-97 · " und der Grund.</summary>
    class function KeyLine(const AKey: string; AState: TAtlasIssueTipState; const ADetails: TAtlasTrackerDetails;
      AError: TAtlasCiFetchError): string; static;
    /// <summary>Fußzeile im Hover der Zeilenhistorie; APreview wie bei Compose.</summary>
    class function BlameFooter(APreview: Boolean): string; static;
    /// <summary>Link "Issues zu dieser Methode (3)" bzw. "… Unit (3)"; ACount &lt; 0: ohne Zahl (wird gesucht).
    /// </summary>
    class function ScopeLink(AMethod: Boolean; ACount: Integer): string; static;
    /// <summary>"3 Commits" bzw. "1 Commit".</summary>
    class function CommitCount(ACount: Integer): string; static;
    /// <summary>Issue im Ergebnisfenster: "ATL-97 · Titel · Zustand · vor 3 Tagen · 4 Commits"; ohne AKnown nur
    /// Kennung, Zeit und Anzahl. ALastDate und ANow in UTC.</summary>
    class function IssueRow(const AKey: string; AKnown: Boolean; const ADetails: TAtlasTrackerDetails;
      ALastDate, ANow: TDateTime; ACommits: Integer): string; static;
    /// <summary>Commit darunter: "abc1234 · anna · 12.10.2026 · Betreff"; ALocalDate in Ortszeit.</summary>
    class function CommitRow(const ARevision, AAuthor: string; ALocalDate: TDateTime; const ASubject: string): string;
      static;
    /// <summary>Titel des Ergebnisfensters: "Issues zu TKunde.Laden · 3 Issues aus 7 Commits · 2 ohne Kennung".
    /// </summary>
    class function ScopeTitle(const AName: string; AIssues, ACommits, AUnlinked: Integer): string; static;
  end;

implementation

uses
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.Issue.Strings;

class function TAtlasIssueTip.AgeText(ATime, ANow: TDateTime): string;
var
  mAge: TAtlasIssueAge;
begin
  mAge := TAtlasIssuePreview.Age(ATime, ANow);
  case mAge.UnitKind of
    TAtlasIssueAgeUnit.Minutes:
      Result := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewMinutes, [mAge.Count]);
    TAtlasIssueAgeUnit.Hours:
      Result := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewHours, [mAge.Count]);
    TAtlasIssueAgeUnit.Days:
      Result := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewDays, [mAge.Count]);
    TAtlasIssueAgeUnit.Months:
      Result := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewMonths, [mAge.Count]);
    TAtlasIssueAgeUnit.Years:
      Result := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewYears, [mAge.Count]);
  else
    Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewJustNow);
  end;
end;

class function TAtlasIssueTip.ErrorText(AError: TAtlasCiFetchError; const AKey: string): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorToken);
    TAtlasCiFetchError.NotFound:
      Result := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewErrorNotFound, [AKey]);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorTimeout);
    TAtlasCiFetchError.NotConfigured, TAtlasCiFetchError.UnknownProvider:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorConfig);
    TAtlasCiFetchError.Invalid, TAtlasCiFetchError.Server:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorInvalid);
  else
    Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorNetwork);
  end;
end;

/// <summary>Titel, darunter Zustand, Zuständig und Alter, soweit bekannt.</summary>
function FoundText(const ADetails: TAtlasTrackerDetails; ANow: TDateTime): string;
var
  mFields: TArray<string>;
begin
  Result := ADetails.Title;
  mFields := nil;
  if ADetails.State <> '' then
  begin
    mFields := mFields
      + [TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewFieldState) + ': ' + ADetails.State];
  end;
  if ADetails.Assignee <> '' then
  begin
    mFields := mFields + [TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewFieldAssignee) + ': ' +
      ADetails.Assignee];
  end;
  if ADetails.Updated > 0 then
  begin
    mFields := mFields + [TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewBadgeUpdated,
      [TAtlasIssueTip.AgeText(ADetails.Updated, ANow)])];
  end;
  if Length(mFields) > 0 then
  begin
    Result := Result + #10 + string.Join(' · ', mFields);
  end;
end;

class function TAtlasIssueTip.Compose(const AKey: string; AState: TAtlasIssueTipState;
  const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError; ANow: TDateTime; APreview: Boolean): string;
begin
  case AState of
    TAtlasIssueTipState.Found:
      Result := FoundText(ADetails, ANow);
    TAtlasIssueTipState.NotFound:
      Result := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewErrorNotFound, [AKey]);
    TAtlasIssueTipState.Failed:
      Result := ErrorText(AError, AKey);
  else
    Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewLoading);
  end;
  if APreview then
  begin
    Result := Result + #10#10 + TAtlasIssueStrings.Text(TAtlasIssueTextId.IssueLinkTipFooter);
  end
  else
  begin
    Result := Result + #10#10 + TAtlasIssueStrings.Text(TAtlasIssueTextId.IssueLinkTipFooterBrowser);
  end;
end;

class function TAtlasIssueTip.KeyLine(const AKey: string; AState: TAtlasIssueTipState;
  const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError): string;
begin
  case AState of
    TAtlasIssueTipState.Found:
      begin
        Result := AKey;
        if ADetails.Title <> '' then
        begin
          Result := Result + ' · ' + ADetails.Title;
        end;
        if ADetails.State <> '' then
        begin
          Result := Result + ' · ' + ADetails.State;
        end;
      end;
    TAtlasIssueTipState.NotFound:
      Result := AKey + ' · ' + TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewErrorNotFound, [AKey]);
    TAtlasIssueTipState.Failed:
      Result := AKey + ' · ' + ErrorText(AError, AKey);
  else
    Result := AKey + ' · ' + TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewLoading);
  end;
end;

class function TAtlasIssueTip.BlameFooter(APreview: Boolean): string;
begin
  if APreview then
  begin
    Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.BlameIssueFooter);
  end
  else
  begin
    Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.BlameIssueFooterBrowser);
  end;
end;

class function TAtlasIssueTip.ScopeLink(AMethod: Boolean; ACount: Integer): string;
begin
  if AMethod and (ACount >= 0) then
  begin
    Result := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.BlameIssuesMethodLink, [ACount]);
  end
  else if AMethod then
  begin
    Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.BlameIssuesMethodLinkOpen);
  end
  else if ACount >= 0 then
  begin
    Result := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.BlameIssuesUnitLink, [ACount]);
  end
  else
  begin
    Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.BlameIssuesUnitLinkOpen);
  end;
end;

class function TAtlasIssueTip.CommitCount(ACount: Integer): string;
begin
  if ACount = 1 then
  begin
    Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.BlameIssuesCommit);
  end
  else
  begin
    Result := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.BlameIssuesCommits, [ACount]);
  end;
end;

class function TAtlasIssueTip.IssueRow(const AKey: string; AKnown: Boolean; const ADetails: TAtlasTrackerDetails;
  ALastDate, ANow: TDateTime; ACommits: Integer): string;
begin
  Result := AKey;
  if AKnown and (ADetails.Title <> '') then
  begin
    Result := Result + ' · ' + ADetails.Title;
  end;
  if AKnown and (ADetails.State <> '') then
  begin
    Result := Result + ' · ' + ADetails.State;
  end;
  if ALastDate > 0 then
  begin
    Result := Result + ' · ' + AgeText(ALastDate, ANow);
  end;
  Result := Result + ' · ' + CommitCount(ACommits);
end;

class function TAtlasIssueTip.CommitRow(const ARevision, AAuthor: string; ALocalDate: TDateTime;
  const ASubject: string): string;
begin
  Result := ARevision;
  if AAuthor <> '' then
  begin
    Result := Result + ' · ' + AAuthor;
  end;
  if ALocalDate > 0 then
  begin
    Result := Result + ' · ' + FormatDateTime('dd"."mm"."yyyy', ALocalDate);
  end;
  if ASubject <> '' then
  begin
    Result := Result + ' · ' + ASubject;
  end;
end;

class function TAtlasIssueTip.ScopeTitle(const AName: string; AIssues, ACommits, AUnlinked: Integer): string;
begin
  Result := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.BlameIssuesTitle, [AName, AIssues, ACommits]);
  if AUnlinked > 0 then
  begin
    Result := Result + ' · ' + TAtlasIssueStrings.Fmt(TAtlasIssueTextId.BlameIssuesUnlinked, [AUnlinked]);
  end;
end;

end.
