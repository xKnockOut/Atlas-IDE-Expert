unit Atlas.Core.Tracker.CurrentIssue;

// Das begonnene Issue für KI-Assistenten (#2051), ohne VCL und Open Tools API:
// - Das Plugin schreibt <gitdir>/atlas-current-issue.json neben
//   atlas-commit-prefix (bei Worktrees der eigene Ordner des Worktrees), beim
//   Beginnen, beim Wechsel des aktiven Issues und sobald der Zwischenspeicher
//   der Issue-Vorschau einen neueren Stand hat. Ohne aktives Issue oder mit
//   issues.shareWithAssistants aus fehlt die Datei.
// - Inhalt: Kennung, Titel, Tracker und Projekt, Zustand, Meilenstein, Seite,
//   Branch, begonnen am, Beschreibung (Markdown), Checkliste mit Erledigt-Stand,
//   Codeverweise (Datei, Zeile, Symbol), die letzten cMaxComments Kommentare
//   und der Stand der Abfrage. Nie ein Token: Die Daten kommen aus
//   TAtlasTrackerDetails, das keins hat; Anhänge und ihre (signierten)
//   Adressen kommen nicht hinein.
// - Der MCP-Server liest die Datei für get_current_issue und gibt sie als Text
//   oder JSON aus (Shell.Mcp.IssueText).

interface

uses
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  /// <summary>Teil der Ausgabe von get_current_issue.</summary>
  TAtlasCurrentIssueSection = (Summary, Checklist, Body, Comments, All);
{$SCOPEDENUMS OFF}

  /// <summary>Punkt der Checkliste.</summary>
  TAtlasCurrentIssueTask = record
    Text: string;
    Done: Boolean;
    /// <summary>Listenebene ab 1.</summary>
    Level: Integer;
  end;

  /// <summary>Codeverweis aus der Beschreibung: Datei, Zeile (0 = ohne), Symbol ('' ohne).</summary>
  TAtlasCurrentIssueCodeRef = record
    FileName: string;
    Line: Integer;
    Symbol: string;
  end;

  TAtlasCurrentIssueComment = record
    Author: string;
    /// <summary>UTC; 0 = unbekannt.</summary>
    Created: TDateTime;
    Text: string;
  end;

  /// <summary>Inhalt von atlas-current-issue.json.</summary>
  TAtlasCurrentIssue = record
  public const
    cFileName = 'atlas-current-issue.json';
    cVersion = 1;
    /// <summary>So viele Kommentare (die letzten) kommen in die Datei.</summary>
    cMaxComments = 5;
    /// <summary>Höchstens so viele Codeverweise.</summary>
    cMaxCodeRefs = 20;
  public
    Key: string;
    Title: string;
    /// <summary>"github" oder "youtrack".</summary>
    Tracker: string;
    /// <summary>GitHub "owner/repo", YouTrack Projektkürzel.</summary>
    Project: string;
    State: string;
    /// <summary>Meilenstein bzw. Sprint.</summary>
    Milestone: string;
    /// <summary>Seite des Issues im Browser.</summary>
    Page: string;
    Branch: string;
    /// <summary>UTC; 0 = unbekannt (aus dem Branch erkannt).</summary>
    Started: TDateTime;
    /// <summary>Markdown; '' ohne Stand aus dem Tracker.</summary>
    Description: string;
    Checklist: TArray<TAtlasCurrentIssueTask>;
    CodeRefs: TArray<TAtlasCurrentIssueCodeRef>;
    /// <summary>Die letzten Kommentare, älteste zuerst.</summary>
    Comments: TArray<TAtlasCurrentIssueComment>;
    /// <summary>Zahl aller Kommentare im Tracker; -1 = nicht abgefragt.</summary>
    CommentCount: Integer;
    /// <summary>Stand der Abfrage im Tracker (UTC); 0 = nur Kennung und Titel aus „Meine Issues“.</summary>
    Fetched: TDateTime;
    class function Empty: TAtlasCurrentIssue; static;
    /// <summary>Erledigte Punkte der Checkliste.</summary>
    function DoneCount: Integer;
    /// <summary>JSON-Objekt; der Aufrufer gibt es frei. ASection wählt die Felder wie die Ausgabe des Werkzeugs.
    /// </summary>
    function ToJsonObject(ASection: TAtlasCurrentIssueSection): TJSONObject;
    /// <summary>Inhalt der Datei (alle Felder, eine Zeile, Umlaute lesbar).</summary>
    function ToJson: string;
    /// <summary>Datei lesen; False bei kaputtem Text, fremder Version oder ohne Kennung.</summary>
    class function FromJson(const AText: string; out AIssue: TAtlasCurrentIssue): Boolean; static;
    /// <summary>Datei im Ordner AGitDir.</summary>
    class function FileOf(const AGitDir: string): string; static;
  end;


implementation

uses
  System.Generics.Collections,
  Atlas.Text.Json;

{ Hilfen für JSON }

function TasksJson(const ATasks: TArray<TAtlasCurrentIssueTask>): TJSONArray;
var
  mTask: TAtlasCurrentIssueTask;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mTask in ATasks do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('text', mTask.Text);
    mItem.AddPair('done', TJSONBool.Create(mTask.Done));
    mItem.AddPair('level', TJSONNumber.Create(mTask.Level));
    Result.AddElement(mItem);
  end;
end;

function CodeRefsJson(const ARefs: TArray<TAtlasCurrentIssueCodeRef>): TJSONArray;
var
  mRef: TAtlasCurrentIssueCodeRef;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mRef in ARefs do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('file', mRef.FileName);
    if mRef.Line > 0 then
    begin
      mItem.AddPair('line', TJSONNumber.Create(mRef.Line));
    end;
    TJsonBuild.AddText(mItem, 'symbol', mRef.Symbol);
    Result.AddElement(mItem);
  end;
end;

function CommentsJson(const AComments: TArray<TAtlasCurrentIssueComment>): TJSONArray;
var
  mComment: TAtlasCurrentIssueComment;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mComment in AComments do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('author', mComment.Author);
    TJsonBuild.AddText(mItem, 'createdAt', TJsonBuild.IsoTime(mComment.Created));
    mItem.AddPair('text', mComment.Text);
    Result.AddElement(mItem);
  end;
end;

/// <summary>Kopf: Kennung, Titel, Tracker, Zustand, Meilenstein, Branch, Zeiten.</summary>
procedure AddHead(AObject: TJSONObject; const AIssue: TAtlasCurrentIssue);
begin
  AObject.AddPair('version', TJSONNumber.Create(TAtlasCurrentIssue.cVersion));
  AObject.AddPair('key', AIssue.Key);
  TJsonBuild.AddText(AObject, 'title', AIssue.Title);
  TJsonBuild.AddText(AObject, 'tracker', AIssue.Tracker);
  TJsonBuild.AddText(AObject, 'project', AIssue.Project);
  TJsonBuild.AddText(AObject, 'state', AIssue.State);
  TJsonBuild.AddText(AObject, 'milestone', AIssue.Milestone);
  TJsonBuild.AddText(AObject, 'page', AIssue.Page);
  TJsonBuild.AddText(AObject, 'branch', AIssue.Branch);
  TJsonBuild.AddText(AObject, 'startedAt', TJsonBuild.IsoTime(AIssue.Started));
  TJsonBuild.AddText(AObject, 'fetchedAt', TJsonBuild.IsoTime(AIssue.Fetched));
end;

function TasksOf(const AArray: TJSONArray): TArray<TAtlasCurrentIssueTask>;
var
  mValue: TJSONValue;
  mTask: TAtlasCurrentIssueTask;
begin
  Result := nil;
  if AArray = nil then
  begin
    Exit;
  end;
  for mValue in AArray do
  begin
    if mValue is TJSONObject then
    begin
      mTask.Text := TJSONObject(mValue).GetValue<string>('text', '');
      mTask.Done := TJSONObject(mValue).GetValue<Boolean>('done', False);
      mTask.Level := TJSONObject(mValue).GetValue<Integer>('level', 1);
      Result := Result + [mTask];
    end;
  end;
end;

function CodeRefsOf(const AArray: TJSONArray): TArray<TAtlasCurrentIssueCodeRef>;
var
  mValue: TJSONValue;
  mRef: TAtlasCurrentIssueCodeRef;
begin
  Result := nil;
  if AArray = nil then
  begin
    Exit;
  end;
  for mValue in AArray do
  begin
    if mValue is TJSONObject then
    begin
      mRef.FileName := TJSONObject(mValue).GetValue<string>('file', '');
      mRef.Line := TJSONObject(mValue).GetValue<Integer>('line', 0);
      mRef.Symbol := TJSONObject(mValue).GetValue<string>('symbol', '');
      Result := Result + [mRef];
    end;
  end;
end;

function CommentsOf(const AArray: TJSONArray): TArray<TAtlasCurrentIssueComment>;
var
  mValue: TJSONValue;
  mComment: TAtlasCurrentIssueComment;
begin
  Result := nil;
  if AArray = nil then
  begin
    Exit;
  end;
  for mValue in AArray do
  begin
    if mValue is TJSONObject then
    begin
      mComment.Author := TJSONObject(mValue).GetValue<string>('author', '');
      mComment.Created := TJsonRead.IsoTime(TJSONObject(mValue), 'createdAt', True);
      mComment.Text := TJSONObject(mValue).GetValue<string>('text', '');
      Result := Result + [mComment];
    end;
  end;
end;

procedure ReadHead(const AObject: TJSONObject; var AIssue: TAtlasCurrentIssue);
begin
  AIssue.Key := AObject.GetValue<string>('key', '');
  AIssue.Title := AObject.GetValue<string>('title', '');
  AIssue.Tracker := AObject.GetValue<string>('tracker', '');
  AIssue.Project := AObject.GetValue<string>('project', '');
  AIssue.State := AObject.GetValue<string>('state', '');
  AIssue.Milestone := AObject.GetValue<string>('milestone', '');
  AIssue.Page := AObject.GetValue<string>('page', '');
  AIssue.Branch := AObject.GetValue<string>('branch', '');
  AIssue.Started := TJsonRead.IsoTime(AObject, 'startedAt', True);
  AIssue.Fetched := TJsonRead.IsoTime(AObject, 'fetchedAt', True);
end;

{ TAtlasCurrentIssue }

class function TAtlasCurrentIssue.Empty: TAtlasCurrentIssue;
begin
  Result := Default(TAtlasCurrentIssue);
  Result.CommentCount := -1;
end;

function TAtlasCurrentIssue.DoneCount: Integer;
var
  mTask: TAtlasCurrentIssueTask;
begin
  Result := 0;
  for mTask in Checklist do
  begin
    if mTask.Done then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasCurrentIssue.ToJsonObject(ASection: TAtlasCurrentIssueSection): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddHead(Result, Self);
  if ASection in [TAtlasCurrentIssueSection.Summary, TAtlasCurrentIssueSection.All] then
  begin
    Result.AddPair('descriptionLength', TJSONNumber.Create(Length(Description)));
  end;
  if ASection in [TAtlasCurrentIssueSection.Body, TAtlasCurrentIssueSection.All] then
  begin
    Result.AddPair('description', Description);
  end;
  if ASection in [TAtlasCurrentIssueSection.Summary, TAtlasCurrentIssueSection.Checklist,
    TAtlasCurrentIssueSection.All] then
  begin
    Result.AddPair('checklist', TasksJson(Checklist));
  end;
  if ASection in [TAtlasCurrentIssueSection.Summary, TAtlasCurrentIssueSection.All] then
  begin
    Result.AddPair('codeRefs', CodeRefsJson(CodeRefs));
  end;
  if ASection in [TAtlasCurrentIssueSection.Comments, TAtlasCurrentIssueSection.All] then
  begin
    Result.AddPair('commentCount', TJSONNumber.Create(CommentCount));
    Result.AddPair('comments', CommentsJson(Comments));
  end;
end;

function TAtlasCurrentIssue.ToJson: string;
var
  mObject: TJSONObject;
begin
  mObject := ToJsonObject(TAtlasCurrentIssueSection.All);
  try
    Result := mObject.ToJSON([]);
  finally
    mObject.Free;
  end;
end;

class function TAtlasCurrentIssue.FromJson(const AText: string; out AIssue: TAtlasCurrentIssue): Boolean;
var
  mValue: TJSONValue;
  mObject: TJSONObject;
begin
  AIssue := Empty;
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    Result := (mValue is TJSONObject) and (TJSONObject(mValue).GetValue<Integer>('version', 0) = cVersion);
    if not Result then
    begin
      Exit;
    end;
    mObject := TJSONObject(mValue);
    ReadHead(mObject, AIssue);
    AIssue.Description := mObject.GetValue<string>('description', '');
    AIssue.Checklist := TasksOf(TJsonRead.Items(mObject, 'checklist'));
    AIssue.CodeRefs := CodeRefsOf(TJsonRead.Items(mObject, 'codeRefs'));
    AIssue.Comments := CommentsOf(TJsonRead.Items(mObject, 'comments'));
    AIssue.CommentCount := mObject.GetValue<Integer>('commentCount', -1);
    Result := Trim(AIssue.Key) <> '';
  finally
    mValue.Free;
  end;
end;

class function TAtlasCurrentIssue.FileOf(const AGitDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AGitDir) + cFileName;
end;

end.
