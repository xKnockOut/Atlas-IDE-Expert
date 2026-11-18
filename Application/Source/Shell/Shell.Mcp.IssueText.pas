unit Shell.Mcp.IssueText;

// Ausgabe von get_current_issue (#2051) als Text wie im Mockup oder als JSON des
// gewählten Abschnitts. Die Datei selbst (Atlas.Core.Tracker.CurrentIssue) liegt
// im Tracker-Modul; die zweisprachigen Texte hier, weil das Modul ohne
// Atlas.Common auskommen muss.

interface

uses
  Atlas.Core.Tracker.CurrentIssue;

type
  /// <summary>Ausgabe von get_current_issue.</summary>
  TMcpCurrentIssueText = class
  public
    /// <summary>summary, checklist, body, comments, all; '' = summary. False bei anderem Text.</summary>
    class function ParseSection(const AText: string; out ASection: TAtlasCurrentIssueSection): Boolean; static;
    /// <summary>Text wie im Mockup von #2051; ANow (UTC) für „vor 5 Min.“.</summary>
    class function Text(const AIssue: TAtlasCurrentIssue; ASection: TAtlasCurrentIssueSection;
      ANow: TDateTime): string; static;
    /// <summary>JSON mit den Feldern des Abschnitts, eingerückt.</summary>
    class function Json(const AIssue: TAtlasCurrentIssue; ASection: TAtlasCurrentIssueSection): string; static;
    /// <summary>„vor 5 Min.“ bzw. „5 min ago“; '' bei unbekannter Zeit.</summary>
    class function Ago(AThen, ANow: TDateTime): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.JSON,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TCurrentIssueText = (Started, Fetched, NotFetched, ChecklistHead, CodeRefsHead, DescriptionHead,
    DescriptionLength, NoDescription, CommentsHead, NoComments, CommentHead, Minutes, Hours, Days, JustNow);

{$SCOPEDENUMS OFF}

const
  cTexts: array[TCurrentIssueText] of TAtlasText = (
    (De: 'begonnen %s'; En: 'started %s'),
    (De: 'Stand %s'; En: 'fetched %s'),
    (De: 'noch kein Stand aus dem Tracker (Issue-Vorschau öffnen)';
     En: 'no data from the tracker yet (open the issue preview)'),
    (De: 'Checkliste %d/%d'; En: 'Checklist %d/%d'),
    (De: 'Codestellen (aus Codeverweisen)'; En: 'Code locations (from code references)'),
    (De: 'Beschreibung'; En: 'Description'),
    (De: '%d Zeichen (section "body")'; En: '%d characters (section "body")'),
    (De: 'keine'; En: 'none'),
    (De: 'Kommentare (die letzten %d von %d)'; En: 'Comments (the last %d of %d)'),
    (De: 'keine Kommentare geladen'; En: 'no comments loaded'),
    (De: '%s, %s:'; En: '%s, %s:'),
    (De: 'vor %d Min.'; En: '%d min ago'),
    (De: 'vor %d Std.'; En: '%d h ago'),
    (De: 'vor %d Tagen'; En: '%d days ago'),
    (De: 'gerade eben'; En: 'just now'));


  cSectionNames: array[TAtlasCurrentIssueSection] of string = ('summary', 'checklist', 'body', 'comments', 'all');
  cIndent = '  ';
  cLf = #10;

{ Text }

function TrackerName(const ATracker: string): string;
begin
  Result := ATracker;
  if SameText(ATracker, 'github') then
  begin
    Result := 'GitHub';
  end
  else if SameText(ATracker, 'youtrack') then
  begin
    Result := 'YouTrack';
  end;
end;

/// <summary>Teile ohne leere, mit „ · “ verbunden.</summary>
function Joined(const AParts: array of string): string;
var
  mPart: string;
begin
  Result := '';
  for mPart in AParts do
  begin
    if mPart = '' then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + ' · ';
    end;
    Result := Result + mPart;
  end;
end;

/// <summary>Jede Zeile von AText eingerückt.</summary>
function Indented(const AText: string): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in AText.Replace(#13#10, cLf).Replace(#13, cLf).Split([cLf]) do
  begin
    Result := Result + cIndent + mLine + cLf;
  end;
end;

function HeadText(const AIssue: TAtlasCurrentIssue; ANow: TDateTime): string;
var
  mStarted, mFetched, mBranch: string;
begin
  Result := Trim(AIssue.Key + ' ' + AIssue.Title) + cLf;
  Result := Result + Joined([Trim(TrackerName(AIssue.Tracker) + ' ' + AIssue.Project), AIssue.State,
    AIssue.Milestone]) + cLf;
  mStarted := '';
  if AIssue.Started > 0 then
  begin
    mStarted := cTexts[TCurrentIssueText.Started].Fmt([TMcpCurrentIssueText.Ago(AIssue.Started, ANow)]);
  end;
  mFetched := cTexts[TCurrentIssueText.NotFetched].Text;
  if AIssue.Fetched > 0 then
  begin
    mFetched := cTexts[TCurrentIssueText.Fetched].Fmt([TMcpCurrentIssueText.Ago(AIssue.Fetched, ANow)]);
  end;
  mBranch := '';
  if AIssue.Branch <> '' then
  begin
    mBranch := 'Branch ' + AIssue.Branch;
  end;
  Result := Result + Joined([mBranch, mStarted, mFetched]) + cLf;
  if AIssue.Page <> '' then
  begin
    Result := Result + AIssue.Page + cLf;
  end;
end;

function ChecklistText(const AIssue: TAtlasCurrentIssue): string;
var
  mTask: TAtlasCurrentIssueTask;
  mMark: string;
begin
  Result := cLf + cTexts[TCurrentIssueText.ChecklistHead].Fmt([AIssue.DoneCount, Length(AIssue.Checklist)]) + cLf;
  for mTask in AIssue.Checklist do
  begin
    mMark := '[ ] ';
    if mTask.Done then
    begin
      mMark := '[x] ';
    end;
    Result := Result + StringOfChar(' ', 2 * mTask.Level) + mMark + mTask.Text.Replace(cLf, ' ') + cLf;
  end;
end;

function CodeRefsText(const AIssue: TAtlasCurrentIssue): string;
var
  mRef: TAtlasCurrentIssueCodeRef;
  mLine: string;
begin
  Result := '';
  if Length(AIssue.CodeRefs) = 0 then
  begin
    Exit;
  end;
  Result := cLf + cTexts[TCurrentIssueText.CodeRefsHead].Text + cLf;
  for mRef in AIssue.CodeRefs do
  begin
    mLine := mRef.FileName;
    if mRef.Line > 0 then
    begin
      mLine := mLine + ':' + IntToStr(mRef.Line);
    end;
    if mRef.Symbol <> '' then
    begin
      mLine := mLine + '  ' + mRef.Symbol;
    end;
    Result := Result + cIndent + mLine + cLf;
  end;
end;

function DescriptionText(const AIssue: TAtlasCurrentIssue; AFull: Boolean): string;
begin
  Result := cLf + cTexts[TCurrentIssueText.DescriptionHead].Text + cLf;
  if Trim(AIssue.Description) = '' then
  begin
    Result := Result + cIndent + cTexts[TCurrentIssueText.NoDescription].Text + cLf;
  end
  else if AFull then
  begin
    Result := Result + Indented(TrimRight(AIssue.Description));
  end
  else
  begin
    Result := Result + cIndent + cTexts[TCurrentIssueText.DescriptionLength].Fmt([Length(AIssue.Description)]) + cLf;
  end;
end;

function CommentsText(const AIssue: TAtlasCurrentIssue; ANow: TDateTime): string;
var
  mComment: TAtlasCurrentIssueComment;
begin
  if AIssue.CommentCount < 0 then
  begin
    Exit(cLf + cTexts[TCurrentIssueText.NoComments].Text + cLf);
  end;
  Result := cLf + cTexts[TCurrentIssueText.CommentsHead].Fmt([Length(AIssue.Comments), AIssue.CommentCount]) + cLf;
  for mComment in AIssue.Comments do
  begin
    Result := Result + cIndent + cTexts[TCurrentIssueText.CommentHead].Fmt([mComment.Author,
      TMcpCurrentIssueText.Ago(mComment.Created, ANow)]) + cLf;
    Result := Result + Indented(cIndent + TrimRight(mComment.Text).Replace(cLf, cLf + cIndent));
  end;
end;

{ TMcpCurrentIssueText }

class function TMcpCurrentIssueText.ParseSection(const AText: string;
  out ASection: TAtlasCurrentIssueSection): Boolean;
var
  mSection: TAtlasCurrentIssueSection;
begin
  ASection := TAtlasCurrentIssueSection.Summary;
  if Trim(AText) = '' then
  begin
    Exit(True);
  end;
  for mSection := Low(TAtlasCurrentIssueSection) to High(TAtlasCurrentIssueSection) do
  begin
    if SameText(Trim(AText), cSectionNames[mSection]) then
    begin
      ASection := mSection;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TMcpCurrentIssueText.Text(const AIssue: TAtlasCurrentIssue; ASection: TAtlasCurrentIssueSection;
  ANow: TDateTime): string;
begin
  Result := HeadText(AIssue, ANow);
  case ASection of
    TAtlasCurrentIssueSection.Summary:
      Result := Result + ChecklistText(AIssue) + CodeRefsText(AIssue) + DescriptionText(AIssue, False);
    TAtlasCurrentIssueSection.Checklist:
      Result := Result + ChecklistText(AIssue);
    TAtlasCurrentIssueSection.Body:
      Result := Result + DescriptionText(AIssue, True);
    TAtlasCurrentIssueSection.Comments:
      Result := Result + CommentsText(AIssue, ANow);
    TAtlasCurrentIssueSection.All:
      Result := Result + ChecklistText(AIssue) + CodeRefsText(AIssue) + DescriptionText(AIssue, True) +
        CommentsText(AIssue, ANow);
  end;
  Result := TrimRight(Result);
end;

class function TMcpCurrentIssueText.Json(const AIssue: TAtlasCurrentIssue;
  ASection: TAtlasCurrentIssueSection): string;
var
  mObject: TJSONObject;
begin
  mObject := AIssue.ToJsonObject(ASection);
  try
    Result := mObject.Format(2);
  finally
    mObject.Free;
  end;
end;

class function TMcpCurrentIssueText.Ago(AThen, ANow: TDateTime): string;
var
  mMinutes: Int64;
begin
  if AThen <= 0 then
  begin
    Exit('');
  end;
  mMinutes := MinutesBetween(ANow, AThen);
  if mMinutes < 1 then
  begin
    Result := cTexts[TCurrentIssueText.JustNow].Text;
  end
  else if mMinutes < 60 then
  begin
    Result := cTexts[TCurrentIssueText.Minutes].Fmt([mMinutes]);
  end
  else if mMinutes < 48 * 60 then
  begin
    Result := cTexts[TCurrentIssueText.Hours].Fmt([mMinutes div 60]);
  end
  else
  begin
    Result := cTexts[TCurrentIssueText.Days].Fmt([mMinutes div (24 * 60)]);
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.IssueText', cTexts);

end.
