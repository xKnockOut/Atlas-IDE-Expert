unit Atlas.UI.Tracker.Notify;

// Texte der Meldungen zu meinen Issues (#1271) für die
// Benachrichtigungszentrale, ohne VCL:
//   ATL-123: neuer Kommentar von Anna Muster
//   ATL-123: 3 neue Kommentare (Anna Muster, Ben) · Zustand → Fertig
//   ATL-123 dir zugewiesen · neuer Kommentar von Ben
//   #812 geändert
//   4 weitere Issues geändert
//   ATL-2052 ist wieder offen: „Die Lesezeichen fehlen.“ (Jana)   (#2127)
//   ATL-2052 ist wieder offen · Zustand → In Bearbeitung          (#2127)
// Text der Meldung ist der Titel des Issues. Fehler nennen den Server, nie
// das Token.

interface

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Notify,
  Atlas.Core.Tracker.Reopened;

type
  TAtlasTrackerNoticeText = class
  public const
    /// <summary>Trenner zwischen den Teilen einer Meldung.</summary>
    cSeparator = ' · ';
  public
    /// <summary>Titel der Meldung zu einem Issue: Kennung und was neu ist (Zuweisung, Kommentare, Zustand).
    /// </summary>
    class function Title(const ANotice: TAtlasTrackerNotice): string; static;
    /// <summary>Titel der Meldung „wieder offen“ (#2127): mit dem neuesten Kommentar als Grund, sonst mit dem
    /// neuen Zustand.</summary>
    class function ReopenedTitle(const AReopen: TAtlasTrackerReopen): string; static;
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
  Atlas.UI.Tracker.MyIssues.Strings;

class function TAtlasTrackerNoticeText.StateText(const AState: string): string;
begin
  if SameText(AState, 'open') then
  begin
    Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.IssueNotifyStateOpen);
  end
  else if SameText(AState, 'closed') then
  begin
    Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.IssueNotifyStateClosed);
  end
  else
  begin
    Result := AState;
  end;
end;

class function TAtlasTrackerNoticeText.Title(const ANotice: TAtlasTrackerNotice): string;
var
  mParts: TArray<string>;
  mPlain: Boolean;
begin
  mParts := nil;
  if ANotice.AssignedToMe then
  begin
    mParts := mParts + [TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.IssueNotifyAssignedMe)];
  end
  else if ANotice.AssignedTo <> '' then
  begin
    mParts := mParts + [TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.IssueNotifyAssignedOther, [ANotice.AssignedTo])];
  end;
  if ANotice.Comments = 1 then
  begin
    mParts := mParts + [TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.IssueNotifyComment, [string.Join(', ',
      ANotice.CommentAuthors)])];
  end
  else if ANotice.Comments > 1 then
  begin
    mParts := mParts + [TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.IssueNotifyComments, [ANotice.Comments,
      string.Join(', ', ANotice.CommentAuthors)])];
  end;
  if ANotice.State <> '' then
  begin
    mParts := mParts + [TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.IssueNotifyState, [StateText(ANotice.State)])];
  end;
  // „ATL-123 dir zugewiesen“, „ATL-123 geändert“ lesen sich ohne Doppelpunkt.
  mPlain := ANotice.AssignedToMe;
  if Length(mParts) = 0 then
  begin
    mParts := [TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.IssueNotifyChanged)];
    mPlain := True;
  end;
  if mPlain then
  begin
    Result := ANotice.Key + ' ' + string.Join(cSeparator, mParts);
  end
  else
  begin
    Result := ANotice.Key + ': ' + string.Join(cSeparator, mParts);
  end;
end;

class function TAtlasTrackerNoticeText.ReopenedTitle(const AReopen: TAtlasTrackerReopen): string;
begin
  if AReopen.Comment <> '' then
  begin
    Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.IssueReopenedNotice, [AReopen.Key, AReopen.Comment,
      AReopen.CommentBy]);
  end
  else
  begin
    Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.IssueReopenedNoticePlain, [AReopen.Key,
      StateText(AReopen.State)]);
  end;
end;

class function TAtlasTrackerNoticeText.MoreTitle(ACount: Integer): string;
begin
  Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.IssueNotifyMore, [ACount]);
end;

class function TAtlasTrackerNoticeText.ErrorTitle(AError: TAtlasCiFetchError; const AServer: string): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.IssueNotifyErrorToken, [AServer]);
    TAtlasCiFetchError.Network, TAtlasCiFetchError.Timeout:
      Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.IssueNotifyErrorNetwork, [AServer]);
  else
    Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.IssueNotifyErrorOther, [AServer]);
  end;
end;

end.
