unit Atlas.UI.Tracker.IssueTip;

// Texte rund um eine Issue-Kennung ohne Fenster (#1265): der Hover über einer
// Kennung im Editor (Kennung oben, darunter Titel, Zustand, Zuständig,
// Aktualisiert und die Fußzeile mit Strg+Klick), dazu Zeitabstand („vor 3
// Std.“) und Fehlertext, die auch die Issue-Vorschau (#1264) nutzt.
// - Lädt: „Wird geladen …“; nicht gefunden (404): „Issue ATL-7 nicht
//   gefunden.“; andere Fehler: Grund wie in der Vorschau.
// - Fußzeile mit issues.preview: „Strg+Klick: Vorschau · Strg+Umschalt+Klick:
//   Browser“, ohne: „Strg+Klick: im Browser öffnen“.

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

end.
