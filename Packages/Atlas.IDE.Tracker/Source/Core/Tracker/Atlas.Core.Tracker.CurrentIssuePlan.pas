unit Atlas.Core.Tracker.CurrentIssuePlan;

// Aufbau und Ablage von atlas-current-issue.json (#2051) ohne VCL und Open
// Tools API; die IDE (Atlas.IDE.Tracker.IssuesStatus) ruft nur Sync.
// - Build: aus dem aktiven Issue (Kennung, Titel, Branch, begonnen am), dem
//   Tracker und dem letzten Stand aus dem Zwischenspeicher der Issue-Vorschau.
//   Checkliste über TAtlasTrackerChecklist, die letzten Kommentare,
//   Codeverweise aus der Beschreibung.
// - CodeRefs: „Unit.pas:212 TFoo.Bar“, „Unit.pas:12:5“ (Befunde) und die
//   Fundstelle von „Issue anlegen …“ (#1268: „`Unit.pas`, Zeile 12“ und in der
//   Zeile darauf „Methode: `TFoo.Bar`“).
// - GitDirOf: <gitdir> der Arbeitskopie über dem Ordner (.git als Ordner bzw.
//   bei Worktrees als Datei mit „gitdir: …“), wie der Server für
//   get_current_issue und prepare_commit.
// - Sync schreibt nur, wenn sich der Inhalt geändert hat, und löscht die Datei
//   ohne Issue bzw. mit issues.shareWithAssistants aus.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.CurrentIssue;

type
{$SCOPEDENUMS ON}
  /// <summary>Ergebnis von Sync.</summary>
  TAtlasCurrentIssueSync = (Unchanged, Written, Removed, Failed);
{$SCOPEDENUMS OFF}

  /// <summary>Was die IDE über das aktive Issue weiß.</summary>
  TAtlasCurrentIssueSource = record
    Key: string;
    Title: string;
    Branch: string;
    /// <summary>UTC; 0 = unbekannt.</summary>
    Started: TDateTime;
    Target: TAtlasTrackerTarget;
    /// <summary>Stand aus dem Zwischenspeicher der Vorschau liegt vor.</summary>
    HasDetails: Boolean;
    Details: TAtlasTrackerDetails;
  end;

  TAtlasCurrentIssuePlan = class
  public
    class function Build(const ASource: TAtlasCurrentIssueSource): TAtlasCurrentIssue; static;
    /// <summary>Codeverweise in AText, ohne doppelte; höchstens TAtlasCurrentIssue.cMaxCodeRefs.</summary>
    class function CodeRefs(const AText: string): TArray<TAtlasCurrentIssueCodeRef>; static;
    /// <summary>&lt;gitdir&gt; der Git-Arbeitskopie, in der AFolder liegt; '' ohne.</summary>
    class function GitDirOf(const AFolder: string): string; static;
    /// <summary>Datei in AGitDir auf den Stand bringen: mit AShare und AActive AIssue schreiben (nur bei
    /// geändertem Inhalt), sonst löschen.</summary>
    class function Sync(const AGitDir: string; AShare, AActive: Boolean;
      const AIssue: TAtlasCurrentIssue): TAtlasCurrentIssueSync; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Core.Tracker.Checklist,
  Atlas.Core.Tracker.Files,
  Atlas.Core.Tracker.PathSuggestions,
  Atlas.Text.Chars;

const
  cExtensions: array[0..3] of string = ('.pas', '.dpr', '.dpk', '.inc');
  cGitEntry = '.git';
  /// <summary>So viele Ordner steigt GitDirOf höchstens auf.</summary>
  cMaxDepth = 32;

function IsFileChar(AChar: Char): Boolean;
begin
  Result := TTextChars.IsAsciiIdentChar(AChar) or CharInSet(AChar, ['.', '-', '/', '\']);
end;

function IsDigit(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['0'..'9']);
end;

/// <summary>Zahl ab APos (1-basiert); APos steht danach hinter ihr. 0 ohne Ziffer.</summary>
function NumberAt(const ALine: string; var APos: Integer): Integer;
var
  mStart: Integer;
begin
  mStart := APos;
  while (APos <= Length(ALine)) and IsDigit(ALine[APos]) do
  begin
    Inc(APos);
  end;
  Result := StrToIntDef(Copy(ALine, mStart, APos - mStart), 0);
end;

/// <summary>Bezeichner mit Punkten ab APos ("TFoo.Bar"); '' ohne Buchstaben am Anfang.</summary>
function SymbolAt(const ALine: string; APos: Integer): string;
var
  mStart: Integer;
begin
  Result := '';
  if (APos > Length(ALine)) or not CharInSet(ALine[APos], ['A'..'Z', 'a'..'z', '_']) then
  begin
    Exit;
  end;
  mStart := APos;
  while (APos <= Length(ALine)) and (TTextChars.IsAsciiIdentChar(ALine[APos]) or (ALine[APos] = '.')) do
  begin
    Inc(APos);
  end;
  Result := Copy(ALine, mStart, APos - mStart);
  while EndsStr('.', Result) do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

/// <summary>Leerzeichen und Backticks ab APos überspringen.</summary>
procedure SkipBlanks(const ALine: string; var APos: Integer);
begin
  while (APos <= Length(ALine)) and CharInSet(ALine[APos], [' ', #9, '`']) do
  begin
    Inc(APos);
  end;
end;

/// <summary>Steht an APos ein Doppelpunkt mit Ziffer dahinter?</summary>
function ColonNumberAt(const ALine: string; APos: Integer): Boolean;
begin
  Result := (APos < Length(ALine)) and (ALine[APos] = ':') and IsDigit(ALine[APos + 1]);
end;

/// <summary>":12[:5] [Symbol]" ab APos (auf dem Doppelpunkt).</summary>
procedure ReadColonTail(const ALine: string; APos: Integer; var ARef: TAtlasCurrentIssueCodeRef);
begin
  Inc(APos);
  ARef.Line := NumberAt(ALine, APos);
  if ColonNumberAt(ALine, APos) then
  begin
    Inc(APos);
    NumberAt(ALine, APos);
  end;
  SkipBlanks(ALine, APos);
  ARef.Symbol := SymbolAt(ALine, APos);
end;

/// <summary>Fundstelle von „Issue anlegen …“ ab APos (auf dem Komma): ", Zeile 12".</summary>
procedure ReadWordTail(const ALine: string; APos: Integer; var ARef: TAtlasCurrentIssueCodeRef);
var
  mWord: Integer;
begin
  mWord := APos + 2;
  while (mWord <= Length(ALine)) and TTextChars.IsAsciiIdentChar(ALine[mWord]) and not IsDigit(ALine[mWord]) do
  begin
    Inc(mWord);
  end;
  if (mWord < Length(ALine)) and (ALine[mWord] = ' ') and IsDigit(ALine[mWord + 1]) then
  begin
    Inc(mWord);
    ARef.Line := NumberAt(ALine, mWord);
  end;
end;

/// <summary>Zeile und Symbol hinter dem Dateinamen (APos dahinter): ":12[:5] [Symbol]" oder ", Wort 12".
/// </summary>
procedure ReadTail(const ALine: string; APos: Integer; var ARef: TAtlasCurrentIssueCodeRef);
begin
  if (APos <= Length(ALine)) and (ALine[APos] = '`') then
  begin
    Inc(APos);
  end;
  if ColonNumberAt(ALine, APos) then
  begin
    ReadColonTail(ALine, APos, ARef);
  end
  else if Copy(ALine, APos, 2) = ', ' then
  begin
    ReadWordTail(ALine, APos, ARef);
  end;
end;

/// <summary>Endet ALine an APos (Position hinter dem Punkt) mit einer Pascal-Endung? ALength: Länge der Endung.
/// </summary>
function ExtensionAt(const ALine: string; APos: Integer; out ALength: Integer): Boolean;
var
  mExtension: string;
begin
  for mExtension in cExtensions do
  begin
    ALength := Length(mExtension);
    if SameText(Copy(ALine, APos, ALength), mExtension) and
      ((APos + ALength > Length(ALine)) or not TTextChars.IsAsciiIdentChar(ALine[APos + ALength])) then
    begin
      Exit(True);
    end;
  end;
  ALength := 0;
  Result := False;
end;

/// <summary>Symbol aus einer Zeile „Methode: `TFoo.Bar`“ (Wort, Doppelpunkt, Bezeichner in Backticks).</summary>
function MethodLineSymbol(const ALine: string): string;
var
  mPos: Integer;
begin
  Result := '';
  mPos := Pos(': `', ALine);
  if (mPos > 1) and EndsStr('`', TrimRight(ALine)) then
  begin
    Result := SymbolAt(ALine, mPos + 3);
  end;
end;

procedure AddRef(var ARefs: TArray<TAtlasCurrentIssueCodeRef>; const ARef: TAtlasCurrentIssueCodeRef);
var
  mRef: TAtlasCurrentIssueCodeRef;
begin
  for mRef in ARefs do
  begin
    if SameText(mRef.FileName, ARef.FileName) and (mRef.Line = ARef.Line) then
    begin
      Exit;
    end;
  end;
  if Length(ARefs) < TAtlasCurrentIssue.cMaxCodeRefs then
  begin
    ARefs := ARefs + [ARef];
  end;
end;

/// <summary>Verweise einer Zeile; ANext ist die Zeile darauf (für „Methode: …“).</summary>
procedure LineRefs(const ALine, ANext: string; var ARefs: TArray<TAtlasCurrentIssueCodeRef>);
var
  mPos, mStart, mLength: Integer;
  mRef: TAtlasCurrentIssueCodeRef;
begin
  mPos := 1;
  while mPos <= Length(ALine) do
  begin
    if (ALine[mPos] <> '.') or not ExtensionAt(ALine, mPos, mLength) then
    begin
      Inc(mPos);
      Continue;
    end;
    mStart := mPos;
    while (mStart > 1) and IsFileChar(ALine[mStart - 1]) do
    begin
      Dec(mStart);
    end;
    mRef := Default(TAtlasCurrentIssueCodeRef);
    mRef.FileName := Copy(ALine, mStart, mPos + mLength - mStart);
    ReadTail(ALine, mPos + mLength, mRef);
    if (mRef.Symbol = '') and (mRef.Line > 0) then
    begin
      mRef.Symbol := MethodLineSymbol(ANext);
    end;
    if mStart < mPos then
    begin
      AddRef(ARefs, mRef);
    end;
    mPos := mPos + mLength;
  end;
end;

{ TAtlasCurrentIssuePlan }

class function TAtlasCurrentIssuePlan.CodeRefs(const AText: string): TArray<TAtlasCurrentIssueCodeRef>;
var
  mLines: TArray<string>;
  mIndex: Integer;
  mNext: string;
begin
  Result := nil;
  mLines := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  for mIndex := 0 to High(mLines) do
  begin
    mNext := '';
    if mIndex < High(mLines) then
    begin
      mNext := mLines[mIndex + 1];
    end;
    LineRefs(mLines[mIndex], mNext, Result);
  end;
end;

function TasksOf(const ADescription: string): TArray<TAtlasCurrentIssueTask>;
var
  mItem: TAtlasChecklistItem;
  mTask: TAtlasCurrentIssueTask;
begin
  Result := nil;
  for mItem in TAtlasTrackerChecklist.Items(ADescription) do
  begin
    mTask.Text := mItem.Text;
    mTask.Done := mItem.Checked;
    mTask.Level := mItem.Level;
    Result := Result + [mTask];
  end;
end;

function LastComments(const ADetails: TAtlasTrackerDetails): TArray<TAtlasCurrentIssueComment>;
var
  mIndex: Integer;
  mComment: TAtlasCurrentIssueComment;
begin
  Result := nil;
  for mIndex := Length(ADetails.Comments) - TAtlasCurrentIssue.cMaxComments to High(ADetails.Comments) do
  begin
    if mIndex >= 0 then
    begin
      mComment.Author := ADetails.Comments[mIndex].Author;
      mComment.Created := ADetails.Comments[mIndex].Created;
      mComment.Text := ADetails.Comments[mIndex].Text;
      Result := Result + [mComment];
    end;
  end;
end;

procedure TakeDetails(const ADetails: TAtlasTrackerDetails; var AIssue: TAtlasCurrentIssue);
begin
  if ADetails.Title <> '' then
  begin
    AIssue.Title := ADetails.Title;
  end;
  AIssue.State := ADetails.State;
  AIssue.Milestone := ADetails.Sprint;
  AIssue.Page := ADetails.Page;
  AIssue.Description := ADetails.Description;
  AIssue.Checklist := TasksOf(ADetails.Description);
  AIssue.CodeRefs := TAtlasCurrentIssuePlan.CodeRefs(ADetails.Description);
  AIssue.Fetched := ADetails.Fetched;
  if ADetails.CommentsLoaded then
  begin
    AIssue.CommentCount := Length(ADetails.Comments);
    AIssue.Comments := LastComments(ADetails);
  end;
end;

class function TAtlasCurrentIssuePlan.Build(const ASource: TAtlasCurrentIssueSource): TAtlasCurrentIssue;
begin
  Result := TAtlasCurrentIssue.Empty;
  Result.Key := Trim(ASource.Key);
  Result.Title := ASource.Title;
  Result.Tracker := ASource.Target.Provider;
  Result.Project := ASource.Target.Project;
  Result.Branch := ASource.Branch;
  Result.Started := ASource.Started;
  if ASource.HasDetails then
  begin
    TakeDetails(ASource.Details, Result);
  end;
end;

/// <summary>&lt;gitdir&gt; direkt in AFolder; '' ohne.</summary>
function GitDirIn(const AFolder: string): string;
var
  mEntry, mText: string;
begin
  Result := '';
  mEntry := TAtlasTrackerFiles.Join(AFolder, cGitEntry);
  if TAtlasTrackerFiles.Files.FolderExists(mEntry) then
  begin
    Result := mEntry;
  end
  else if TAtlasTrackerFiles.Files.FileExists(mEntry) and TAtlasTrackerFiles.Files.ReadText(mEntry, mText) then
  begin
    Result := TAtlasTrackerPathSuggestions.WorktreeGitDir(AFolder, mText);
  end;
end;

class function TAtlasCurrentIssuePlan.GitDirOf(const AFolder: string): string;
var
  mFolder, mParent: string;
  mDepth: Integer;
begin
  Result := '';
  mFolder := ExcludeTrailingPathDelimiter(AFolder);
  mDepth := 0;
  while (mFolder <> '') and (mDepth < cMaxDepth) do
  begin
    Result := GitDirIn(mFolder);
    if Result <> '' then
    begin
      Exit;
    end;
    mParent := ExcludeTrailingPathDelimiter(ExtractFileDir(mFolder));
    if SameText(mParent, mFolder) then
    begin
      Exit;
    end;
    mFolder := mParent;
    Inc(mDepth);
  end;
end;

class function TAtlasCurrentIssuePlan.Sync(const AGitDir: string; AShare, AActive: Boolean;
  const AIssue: TAtlasCurrentIssue): TAtlasCurrentIssueSync;
var
  mFile, mOld, mNew: string;
begin
  Result := TAtlasCurrentIssueSync.Unchanged;
  if AGitDir = '' then
  begin
    Exit;
  end;
  mFile := TAtlasCurrentIssue.FileOf(AGitDir);
  if not AShare or not AActive or (Trim(AIssue.Key) = '') then
  begin
    if not TAtlasTrackerFiles.Files.FileExists(mFile) then
    begin
      Exit;
    end;
    Result := TAtlasCurrentIssueSync.Removed;
    if not TAtlasTrackerFiles.Files.DeleteFile(mFile) then
    begin
      Result := TAtlasCurrentIssueSync.Failed;
    end;
    Exit;
  end;
  mNew := AIssue.ToJson;
  if TAtlasTrackerFiles.Files.ReadText(mFile, mOld) and (mOld = mNew) then
  begin
    Exit;
  end;
  Result := TAtlasCurrentIssueSync.Written;
  if not TAtlasTrackerFiles.Files.ReplaceText(mFile, mNew) then
  begin
    Result := TAtlasCurrentIssueSync.Failed;
  end;
end;

end.
