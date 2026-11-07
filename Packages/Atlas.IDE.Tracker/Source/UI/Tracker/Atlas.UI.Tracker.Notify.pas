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
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Notify;

type
  TAtlasTrackerNoticeText = class
  public const
    /// <summary>Trenner zwischen den Teilen einer Meldung.</summary>
    cSeparator = ' · ';
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
  Atlas.UI.Tracker.Strings;

class function TAtlasTrackerNoticeText.StateText(const AState: string): string;
begin
  if SameText(AState, 'open') then
  begin
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueNotifyStateOpen);
  end
  else if SameText(AState, 'closed') then
  begin
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueNotifyStateClosed);
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
    mParts := mParts + [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueNotifyAssignedMe)];
  end
  else if ANotice.AssignedTo <> '' then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueNotifyAssignedOther, [ANotice.AssignedTo])];
  end;
  if ANotice.Comments = 1 then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueNotifyComment, [string.Join(', ',
      ANotice.CommentAuthors)])];
  end
  else if ANotice.Comments > 1 then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueNotifyComments, [ANotice.Comments,
      string.Join(', ', ANotice.CommentAuthors)])];
  end;
  if ANotice.State <> '' then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueNotifyState, [StateText(ANotice.State)])];
  end;
  // „ATL-123 dir zugewiesen“, „ATL-123 geändert“ lesen sich ohne Doppelpunkt.
  mPlain := ANotice.AssignedToMe;
  if Length(mParts) = 0 then
  begin
    mParts := [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueNotifyChanged)];
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

class function TAtlasTrackerNoticeText.MoreTitle(ACount: Integer): string;
begin
  Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueNotifyMore, [ACount]);
end;

class function TAtlasTrackerNoticeText.ErrorTitle(AError: TAtlasCiFetchError; const AServer: string): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueNotifyErrorToken, [AServer]);
    TAtlasCiFetchError.Network, TAtlasCiFetchError.Timeout:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueNotifyErrorNetwork, [AServer]);
  else
    Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueNotifyErrorOther, [AServer]);
  end;
end;

end.
