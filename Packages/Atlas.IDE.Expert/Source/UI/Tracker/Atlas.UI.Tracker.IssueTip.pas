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
  Atlas.Core.Ci.Contract,
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
    /// <summary>Titel und Text des Hovers über AKey. ADetails gilt nur bei Found; AError nur bei Failed;
    /// APreview: issues.preview an (Strg+Klick öffnet die Vorschau).</summary>
    class procedure Compose(const AKey: string; AState: TAtlasIssueTipState; const ADetails: TAtlasTrackerDetails;
      AError: TAtlasCiFetchError; ANow: TDateTime; APreview: Boolean; out ATitle, AText: string); static;
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
  Atlas.UI.Strings;

class function TAtlasIssueTip.AgeText(ATime, ANow: TDateTime): string;
var
  mAge: TAtlasIssueAge;
begin
  mAge := TAtlasIssuePreview.Age(ATime, ANow);
  case mAge.UnitKind of
    TAtlasIssueAgeUnit.Minutes:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewMinutes, [mAge.Count]);
    TAtlasIssueAgeUnit.Hours:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewHours, [mAge.Count]);
    TAtlasIssueAgeUnit.Days:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewDays, [mAge.Count]);
    TAtlasIssueAgeUnit.Months:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewMonths, [mAge.Count]);
    TAtlasIssueAgeUnit.Years:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewYears, [mAge.Count]);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewJustNow);
  end;
end;

class function TAtlasIssueTip.ErrorText(AError: TAtlasCiFetchError; const AKey: string): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorToken);
    TAtlasCiFetchError.NotFound:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewErrorNotFound, [AKey]);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorTimeout);
    TAtlasCiFetchError.NotConfigured, TAtlasCiFetchError.UnknownProvider:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorConfig);
    TAtlasCiFetchError.Invalid, TAtlasCiFetchError.Server:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorInvalid);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorNetwork);
  end;
end;

class procedure TAtlasIssueTip.Compose(const AKey: string; AState: TAtlasIssueTipState;
  const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError; ANow: TDateTime; APreview: Boolean;
  out ATitle, AText: string);
var
  mFields: TArray<string>;
  mFooter: string;
begin
  ATitle := AKey;
  case AState of
    TAtlasIssueTipState.Found:
      begin
        AText := ADetails.Title;
        mFields := nil;
        if ADetails.State <> '' then
          mFields := mFields + [TAtlasStrings.Text(TAtlasTextId.IssuePreviewFieldState) + ': ' + ADetails.State];
        if ADetails.Assignee <> '' then
          mFields := mFields + [TAtlasStrings.Text(TAtlasTextId.IssuePreviewFieldAssignee) + ': ' +
            ADetails.Assignee];
        if ADetails.Updated > 0 then
          mFields := mFields + [TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewBadgeUpdated,
            [AgeText(ADetails.Updated, ANow)])];
        if Length(mFields) > 0 then
          AText := AText + #10 + string.Join(' · ', mFields);
      end;
    TAtlasIssueTipState.NotFound:
      AText := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewErrorNotFound, [AKey]);
    TAtlasIssueTipState.Failed:
      AText := ErrorText(AError, AKey);
  else
    AText := TAtlasStrings.Text(TAtlasTextId.IssuePreviewLoading);
  end;
  if APreview then
    mFooter := TAtlasStrings.Text(TAtlasTextId.IssueLinkTipFooter)
  else
    mFooter := TAtlasStrings.Text(TAtlasTextId.IssueLinkTipFooterBrowser);
  AText := AText + #10#10 + mFooter;
end;

class function TAtlasIssueTip.KeyLine(const AKey: string; AState: TAtlasIssueTipState;
  const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError): string;
begin
  case AState of
    TAtlasIssueTipState.Found:
      begin
        Result := AKey;
        if ADetails.Title <> '' then
          Result := Result + ' · ' + ADetails.Title;
        if ADetails.State <> '' then
          Result := Result + ' · ' + ADetails.State;
      end;
    TAtlasIssueTipState.NotFound:
      Result := AKey + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewErrorNotFound, [AKey]);
    TAtlasIssueTipState.Failed:
      Result := AKey + ' · ' + ErrorText(AError, AKey);
  else
    Result := AKey + ' · ' + TAtlasStrings.Text(TAtlasTextId.IssuePreviewLoading);
  end;
end;

class function TAtlasIssueTip.BlameFooter(APreview: Boolean): string;
begin
  if APreview then
    Result := TAtlasStrings.Text(TAtlasTextId.BlameIssueFooter)
  else
    Result := TAtlasStrings.Text(TAtlasTextId.BlameIssueFooterBrowser);
end;

class function TAtlasIssueTip.ScopeLink(AMethod: Boolean; ACount: Integer): string;
begin
  if AMethod and (ACount >= 0) then
    Result := TAtlasStrings.Fmt(TAtlasTextId.BlameIssuesMethodLink, [ACount])
  else if AMethod then
    Result := TAtlasStrings.Text(TAtlasTextId.BlameIssuesMethodLinkOpen)
  else if ACount >= 0 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.BlameIssuesUnitLink, [ACount])
  else
    Result := TAtlasStrings.Text(TAtlasTextId.BlameIssuesUnitLinkOpen);
end;

class function TAtlasIssueTip.CommitCount(ACount: Integer): string;
begin
  if ACount = 1 then
    Result := TAtlasStrings.Text(TAtlasTextId.BlameIssuesCommit)
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.BlameIssuesCommits, [ACount]);
end;

class function TAtlasIssueTip.IssueRow(const AKey: string; AKnown: Boolean; const ADetails: TAtlasTrackerDetails;
  ALastDate, ANow: TDateTime; ACommits: Integer): string;
begin
  Result := AKey;
  if AKnown and (ADetails.Title <> '') then
    Result := Result + ' · ' + ADetails.Title;
  if AKnown and (ADetails.State <> '') then
    Result := Result + ' · ' + ADetails.State;
  if ALastDate > 0 then
    Result := Result + ' · ' + AgeText(ALastDate, ANow);
  Result := Result + ' · ' + CommitCount(ACommits);
end;

class function TAtlasIssueTip.CommitRow(const ARevision, AAuthor: string; ALocalDate: TDateTime;
  const ASubject: string): string;
begin
  Result := ARevision;
  if AAuthor <> '' then
    Result := Result + ' · ' + AAuthor;
  if ALocalDate > 0 then
    Result := Result + ' · ' + FormatDateTime('dd"."mm"."yyyy', ALocalDate);
  if ASubject <> '' then
    Result := Result + ' · ' + ASubject;
end;

class function TAtlasIssueTip.ScopeTitle(const AName: string; AIssues, ACommits, AUnlinked: Integer): string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.BlameIssuesTitle, [AName, AIssues, ACommits]);
  if AUnlinked > 0 then
    Result := Result + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.BlameIssuesUnlinked, [AUnlinked]);
end;

end.
