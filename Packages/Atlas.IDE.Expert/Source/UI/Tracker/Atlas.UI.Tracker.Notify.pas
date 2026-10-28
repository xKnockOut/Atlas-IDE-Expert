unit Atlas.UI.Tracker.Notify;

// Texte der Meldungen zu meinen Issues (#1271) für die
// Benachrichtigungszentrale, ohne VCL:
//   ATL-123: neuer Kommentar von Anna Muster
//   ATL-123: 3 neue Kommentare (Anna Muster, Ben) · Zustand → Fertig
//   ATL-123 dir zugewiesen · neuer Kommentar von Ben
//   #812 geändert
//   4 weitere Issues geändert
// Text der Meldung ist der Titel des Issues. Fehler nennen den Server, nie
// das Token.

interface

uses
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Notify;

type
  TAtlasTrackerNoticeText = class
  public const
    /// <summary>Trenner zwischen den Teilen einer Meldung.</summary>
    Separator = ' · ';
  public
    /// <summary>Titel der Meldung zu einem Issue: Kennung und was neu ist (Zuweisung, Kommentare, Zustand).
    /// </summary>
    class function Title(const ANotice: TAtlasTrackerNotice): string; static;
    /// <summary>Zustand zur Anzeige: GitHub "open"/"closed" übersetzt, sonst wie vom Tracker.</summary>
    class function StateText(const AState: string): string; static;
    /// <summary>Sammelmeldung „n weitere Issues geändert“.</summary>
    class function MoreTitle(ACount: Integer): string; static;
    /// <summary>Titel der Fehlermeldung: Token abgelehnt, nicht erreichbar oder unerwartete Antwort von AServer.
    /// </summary>
    class function ErrorTitle(AError: TAtlasCiFetchError; const AServer: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

class function TAtlasTrackerNoticeText.StateText(const AState: string): string;
begin
  if SameText(AState, 'open') then
    Result := TAtlasStrings.Text(TAtlasTextId.IssueNotifyStateOpen)
  else if SameText(AState, 'closed') then
    Result := TAtlasStrings.Text(TAtlasTextId.IssueNotifyStateClosed)
  else
    Result := AState;
end;

class function TAtlasTrackerNoticeText.Title(const ANotice: TAtlasTrackerNotice): string;
var
  mParts: TArray<string>;
  mPlain: Boolean;
begin
  mParts := nil;
  if ANotice.AssignedToMe then
    mParts := mParts + [TAtlasStrings.Text(TAtlasTextId.IssueNotifyAssignedMe)]
  else if ANotice.AssignedTo <> '' then
    mParts := mParts + [TAtlasStrings.Fmt(TAtlasTextId.IssueNotifyAssignedOther, [ANotice.AssignedTo])];
  if ANotice.Comments = 1 then
    mParts := mParts + [TAtlasStrings.Fmt(TAtlasTextId.IssueNotifyComment, [string.Join(', ',
      ANotice.CommentAuthors)])]
  else if ANotice.Comments > 1 then
    mParts := mParts + [TAtlasStrings.Fmt(TAtlasTextId.IssueNotifyComments, [ANotice.Comments,
      string.Join(', ', ANotice.CommentAuthors)])];
  if ANotice.State <> '' then
    mParts := mParts + [TAtlasStrings.Fmt(TAtlasTextId.IssueNotifyState, [StateText(ANotice.State)])];
  // „ATL-123 dir zugewiesen“, „ATL-123 geändert“ lesen sich ohne Doppelpunkt.
  mPlain := ANotice.AssignedToMe;
  if Length(mParts) = 0 then
  begin
    mParts := [TAtlasStrings.Text(TAtlasTextId.IssueNotifyChanged)];
    mPlain := True;
  end;
  if mPlain then
    Result := ANotice.Key + ' ' + string.Join(Separator, mParts)
  else
    Result := ANotice.Key + ': ' + string.Join(Separator, mParts);
end;

class function TAtlasTrackerNoticeText.MoreTitle(ACount: Integer): string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.IssueNotifyMore, [ACount]);
end;

class function TAtlasTrackerNoticeText.ErrorTitle(AError: TAtlasCiFetchError; const AServer: string): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssueNotifyErrorToken, [AServer]);
    TAtlasCiFetchError.Network, TAtlasCiFetchError.Timeout:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssueNotifyErrorNetwork, [AServer]);
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.IssueNotifyErrorOther, [AServer]);
  end;
end;

end.
