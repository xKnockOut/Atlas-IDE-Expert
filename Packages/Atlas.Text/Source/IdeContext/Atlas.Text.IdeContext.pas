unit Atlas.Text.IdeContext;

// Zustand der IDE für KI-Assistenten (#2050, MCP-Werkzeug get_ide_context), gemeinsam für Plugin und Server. Das
// Modul KI-Assistenten schreibt verzögert, sobald Reiter, Methode unter dem Cursor, Auswahl, aktives Projekt oder
// letzter Build wechseln (ChangeKey; Tippen innerhalb einer Methode schreibt nicht):
//   %LOCALAPPDATA%\Atlas\ide-context-<pid>.json   (UTF-8, atomar ersetzt, beim Beenden gelöscht)
//   {"format": 1, "pid": …, "at": ISO 8601 in UTC,
//    "editor": {"file", "line", "column" (ab 1), "modified", "method"},
//    "selection": {"startLine", "startColumn", "endLine", "endColumn" (ab 1), "length" (Zeichen der ganzen
//                  Auswahl), "text" (gekürzt auf assistants.context.selectionMax), "truncated", "textOmitted"},
//    "project": {"file" (.dproj), "configuration", "platform", "group" (.groupproj)},
//    "build": {"project", "kind", "success", "errors", "warnings", "hints", "finishedAt",
//              "messages": [{"file", "line", "column" (ab 1), "severity", "code", "text"}]},
//    "tabs": [Dateien in der Reihenfolge der Reiter]}
// Fehlende Abschnitte: kein Editor, keine Auswahl, kein Projekt bzw. noch kein Build.

interface

type
  TIdeContextMessage = record
    FileName: string;
    /// <summary>Ab 1; 0 = ohne.</summary>
    Line: Integer;
    Column: Integer;
    /// <summary>"error", "warning", "hint" oder "fatal".</summary>
    Severity: string;
    Code: string;
    Text: string;
  end;

  TIdeContextEditor = record
    Known: Boolean;
    FileName: string;
    /// <summary>Ab 1.</summary>
    Line: Integer;
    Column: Integer;
    Modified: Boolean;
    /// <summary>Qualifizierter Name der Methode am Cursor aus der Gliederung; '' ohne.</summary>
    Method: string;
  end;

  TIdeContextSelection = record
    Known: Boolean;
    /// <summary>Ab 1.</summary>
    StartLine: Integer;
    StartColumn: Integer;
    EndLine: Integer;
    EndColumn: Integer;
    /// <summary>Zeichen der ganzen Auswahl.</summary>
    Length: Integer;
    Text: string;
    Truncated: Boolean;
    /// <summary>Text abgeschaltet (assistants.context.selection aus).</summary>
    TextOmitted: Boolean;
  end;

  TIdeContextProject = record
    FileName: string;
    Configuration: string;
    Platform: string;
    Group: string;
  end;

  TIdeContextBuild = record
    Known: Boolean;
    Project: string;
    Kind: string;
    Success: Boolean;
    Errors: Integer;
    Warnings: Integer;
    Hints: Integer;
    FinishedAtUtc: TDateTime;
    /// <summary>Nur beim Lesen gesetzt: FinishedAtUtc in Ortszeit.</summary>
    FinishedAtLocal: TDateTime;
    Messages: TArray<TIdeContextMessage>;
  end;

  TIdeContext = record
    Pid: Cardinal;
    AtUtc: TDateTime;
    /// <summary>Nur beim Lesen gesetzt: AtUtc in Ortszeit.</summary>
    AtLocal: TDateTime;
    Editor: TIdeContextEditor;
    Selection: TIdeContextSelection;
    Project: TIdeContextProject;
    Build: TIdeContextBuild;
    Tabs: TArray<string>;
  end;

  TIdeContexts = class
  public const
    cFormat = 1;
    cPrefix = 'ide-context-';
    cSuffix = '.json';
    /// <summary>So viele Meldungen des letzten Builds (Fehler zuerst) stehen in der Datei.</summary>
    cMaxMessages = 50;
  public
    /// <summary>Datei des Prozesses APid unter ABase (%LOCALAPPDATA%\Atlas).</summary>
    class function FileName(const ABase: string; APid: Cardinal): string; static;
    /// <summary>AText gekürzt auf AMax Zeichen (0 = kein Text); ATruncated, wenn etwas fehlt. Trennt kein
    /// Ersatzzeichenpaar.</summary>
    class function Shorten(const AText: string; AMax: Integer; out ATruncated: Boolean): string; static;
    /// <summary>Fehler und schwere Fehler zuerst, dann Warnungen, höchstens cMaxMessages; Hinweise fallen weg.
    /// </summary>
    class function Relevant(const AMessages: TArray<TIdeContextMessage>): TArray<TIdeContextMessage>; static;
    /// <summary>Schlüssel der Wechsel, nach denen das Plugin neu schreibt: Datei, Methode, Auswahl, Projekt, Build,
    /// Reiter. Zeile und Spalte zählen nicht: Tippen und Bewegen innerhalb einer Methode ändern ihn nicht.
    /// </summary>
    class function ChangeKey(const AContext: TIdeContext): string; static;
    /// <summary>Inhalt der Datei (kompaktes JSON).</summary>
    class function ToJson(const AContext: TIdeContext): string; static;
    /// <summary>Liest ToJson; False bei kaputtem Inhalt, höherem Format oder ohne pid.</summary>
    class function Parse(const AText: string; out AContext: TIdeContext): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.JSON,
  System.DateUtils,
  Atlas.Text.Encoding,
  Atlas.Text.Json,
  Atlas.Text.Timestamps;

{ Schreiben }

function EditorJson(const AEditor: TIdeContextEditor): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', AEditor.FileName);
  Result.AddPair('line', TJSONNumber.Create(AEditor.Line));
  Result.AddPair('column', TJSONNumber.Create(AEditor.Column));
  Result.AddPair('modified', TJSONBool.Create(AEditor.Modified));
  TJsonBuild.AddText(Result, 'method', AEditor.Method);
end;

function SelectionJson(const ASelection: TIdeContextSelection): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('startLine', TJSONNumber.Create(ASelection.StartLine));
  Result.AddPair('startColumn', TJSONNumber.Create(ASelection.StartColumn));
  Result.AddPair('endLine', TJSONNumber.Create(ASelection.EndLine));
  Result.AddPair('endColumn', TJSONNumber.Create(ASelection.EndColumn));
  Result.AddPair('length', TJSONNumber.Create(ASelection.Length));
  TJsonBuild.AddText(Result, 'text', ASelection.Text);
  Result.AddPair('truncated', TJSONBool.Create(ASelection.Truncated));
  Result.AddPair('textOmitted', TJSONBool.Create(ASelection.TextOmitted));
end;

function ProjectJson(const AProject: TIdeContextProject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', AProject.FileName);
  TJsonBuild.AddText(Result, 'configuration', AProject.Configuration);
  TJsonBuild.AddText(Result, 'platform', AProject.Platform);
  TJsonBuild.AddText(Result, 'group', AProject.Group);
end;

function MessageJson(const AMessage: TIdeContextMessage): TJSONObject;
begin
  Result := TJSONObject.Create;
  TJsonBuild.AddText(Result, 'file', AMessage.FileName);
  Result.AddPair('line', TJSONNumber.Create(AMessage.Line));
  Result.AddPair('column', TJSONNumber.Create(AMessage.Column));
  Result.AddPair('severity', AMessage.Severity);
  TJsonBuild.AddText(Result, 'code', AMessage.Code);
  Result.AddPair('text', AMessage.Text);
end;

function BuildJson(const ABuild: TIdeContextBuild): TJSONObject;
var
  mMessages: TJSONArray;
  mMessage: TIdeContextMessage;
begin
  Result := TJSONObject.Create;
  Result.AddPair('project', ABuild.Project);
  TJsonBuild.AddText(Result, 'kind', ABuild.Kind);
  Result.AddPair('success', TJSONBool.Create(ABuild.Success));
  Result.AddPair('errors', TJSONNumber.Create(ABuild.Errors));
  Result.AddPair('warnings', TJSONNumber.Create(ABuild.Warnings));
  Result.AddPair('hints', TJSONNumber.Create(ABuild.Hints));
  Result.AddPair('finishedAt', DateToISO8601(ABuild.FinishedAtUtc, True));
  mMessages := TJSONArray.Create;
  for mMessage in ABuild.Messages do
  begin
    mMessages.AddElement(MessageJson(mMessage));
  end;
  Result.AddPair('messages', mMessages);
end;

{ Lesen }

function EditorOf(AObject: TJSONObject): TIdeContextEditor;
begin
  Result := Default(TIdeContextEditor);
  Result.Known := (AObject <> nil) and (TJsonRead.Text(AObject, 'file') <> '');
  if Result.Known then
  begin
    Result.FileName := TJsonRead.Text(AObject, 'file');
    Result.Line := TJsonRead.IntOr(AObject, 'line', 0);
    Result.Column := TJsonRead.IntOr(AObject, 'column', 0);
    Result.Modified := TJsonRead.Flag(AObject, 'modified');
    Result.Method := TJsonRead.Text(AObject, 'method');
  end;
end;

function SelectionOf(AObject: TJSONObject): TIdeContextSelection;
begin
  Result := Default(TIdeContextSelection);
  Result.Known := AObject <> nil;
  if Result.Known then
  begin
    Result.StartLine := TJsonRead.IntOr(AObject, 'startLine', 0);
    Result.StartColumn := TJsonRead.IntOr(AObject, 'startColumn', 0);
    Result.EndLine := TJsonRead.IntOr(AObject, 'endLine', 0);
    Result.EndColumn := TJsonRead.IntOr(AObject, 'endColumn', 0);
    Result.Length := TJsonRead.IntOr(AObject, 'length', 0);
    Result.Text := TJsonRead.Text(AObject, 'text');
    Result.Truncated := TJsonRead.Flag(AObject, 'truncated');
    Result.TextOmitted := TJsonRead.Flag(AObject, 'textOmitted');
  end;
end;

function ProjectOf(AObject: TJSONObject): TIdeContextProject;
begin
  Result := Default(TIdeContextProject);
  if AObject <> nil then
  begin
    Result.FileName := TJsonRead.Text(AObject, 'file');
    Result.Configuration := TJsonRead.Text(AObject, 'configuration');
    Result.Platform := TJsonRead.Text(AObject, 'platform');
    Result.Group := TJsonRead.Text(AObject, 'group');
  end;
end;

function MessagesOf(AItems: TJSONArray): TArray<TIdeContextMessage>;
var
  mItem: TJSONValue;
  mMessage: TIdeContextMessage;
begin
  Result := nil;
  if AItems = nil then
  begin
    Exit;
  end;
  for mItem in AItems do
  begin
    if mItem is TJSONObject then
    begin
      mMessage.FileName := TJsonRead.Text(TJSONObject(mItem), 'file');
      mMessage.Line := TJsonRead.IntOr(TJSONObject(mItem), 'line', 0);
      mMessage.Column := TJsonRead.IntOr(TJSONObject(mItem), 'column', 0);
      mMessage.Severity := TJsonRead.Text(TJSONObject(mItem), 'severity');
      mMessage.Code := TJsonRead.Text(TJSONObject(mItem), 'code');
      mMessage.Text := TJsonRead.Text(TJSONObject(mItem), 'text');
      Result := Result + [mMessage];
    end;
  end;
end;

function BuildOf(AObject: TJSONObject): TIdeContextBuild;
begin
  Result := Default(TIdeContextBuild);
  Result.Known := AObject <> nil;
  if Result.Known then
  begin
    Result.Project := TJsonRead.Text(AObject, 'project');
    Result.Kind := TJsonRead.Text(AObject, 'kind');
    Result.Success := TJsonRead.Flag(AObject, 'success');
    Result.Errors := TJsonRead.IntOr(AObject, 'errors', 0);
    Result.Warnings := TJsonRead.IntOr(AObject, 'warnings', 0);
    Result.Hints := TJsonRead.IntOr(AObject, 'hints', 0);
    Result.FinishedAtUtc := TTextTimestamp.IsoOrZero(TJsonRead.Text(AObject, 'finishedAt'), True);
    Result.FinishedAtLocal := TTextTimestamp.IsoOrZero(TJsonRead.Text(AObject, 'finishedAt'), False);
    Result.Messages := MessagesOf(TJsonRead.Items(AObject, 'messages'));
  end;
end;

{ TIdeContexts }

class function TIdeContexts.FileName(const ABase: string; APid: Cardinal): string;
begin
  Result := IncludeTrailingPathDelimiter(ABase) + cPrefix + UIntToStr(APid) + cSuffix;
end;

class function TIdeContexts.Shorten(const AText: string; AMax: Integer; out ATruncated: Boolean): string;
var
  mLength: Integer;
begin
  ATruncated := Length(AText) > AMax;
  if not ATruncated then
  begin
    Exit(AText);
  end;
  mLength := AMax;
  if mLength < 0 then
  begin
    mLength := 0;
  end;
  // Hohes Ersatzzeichen am Ende: ohne sein Gegenstück wäre der Text kein gültiges UTF-16.
  if (mLength > 0) and (Ord(AText[mLength]) >= TTextEncodingProbe.cHighSurrogateFirst) and
    (Ord(AText[mLength]) < TTextEncodingProbe.cLowSurrogateFirst) then
  begin
    Dec(mLength);
  end;
  Result := Copy(AText, 1, mLength);
end;

class function TIdeContexts.Relevant(const AMessages: TArray<TIdeContextMessage>): TArray<TIdeContextMessage>;
var
  mMessage: TIdeContextMessage;
  mWarnings: TArray<TIdeContextMessage>;
begin
  Result := nil;
  mWarnings := nil;
  for mMessage in AMessages do
  begin
    if SameText(mMessage.Severity, 'error') or SameText(mMessage.Severity, 'fatal') then
    begin
      Result := Result + [mMessage];
    end
    else if SameText(mMessage.Severity, 'warning') then
    begin
      mWarnings := mWarnings + [mMessage];
    end;
  end;
  Result := Result + mWarnings;
  if Length(Result) > cMaxMessages then
  begin
    SetLength(Result, cMaxMessages);
  end;
end;

class function TIdeContexts.ChangeKey(const AContext: TIdeContext): string;
var
  mTab: string;
begin
  // Außerhalb einer Methode zählt nur die Datei; Zeile und Spalte gehen erst mit dem nächsten Wechsel mit.
  Result := AContext.Editor.FileName + '|' + AContext.Editor.Method + #1 + Format('%d:%d-%d:%d|%d|%s', [AContext.Selection.StartLine,
    AContext.Selection.StartColumn, AContext.Selection.EndLine, AContext.Selection.EndColumn,
    AContext.Selection.Length, AContext.Selection.Text]) + #1 + AContext.Project.FileName + '|' +
    AContext.Project.Configuration + '|' + AContext.Project.Platform + '|' + AContext.Project.Group + #1 +
    DateToISO8601(AContext.Build.FinishedAtUtc, True) + '|' + AContext.Build.Project + #1;
  for mTab in AContext.Tabs do
  begin
    Result := Result + mTab + '|';
  end;
end;

class function TIdeContexts.ToJson(const AContext: TIdeContext): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormat));
    mRoot.AddPair('pid', TJSONNumber.Create(AContext.Pid));
    mRoot.AddPair('at', DateToISO8601(AContext.AtUtc, True));
    if AContext.Editor.Known then
    begin
      mRoot.AddPair('editor', EditorJson(AContext.Editor));
    end;
    if AContext.Selection.Known then
    begin
      mRoot.AddPair('selection', SelectionJson(AContext.Selection));
    end;
    if AContext.Project.FileName <> '' then
    begin
      mRoot.AddPair('project', ProjectJson(AContext.Project));
    end;
    if AContext.Build.Known then
    begin
      mRoot.AddPair('build', BuildJson(AContext.Build));
    end;
    mRoot.AddPair('tabs', TJsonBuild.Strings(AContext.Tabs));
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

class function TIdeContexts.Parse(const AText: string; out AContext: TIdeContext): Boolean;
var
  mRoot: TJSONObject;
  mFormat: Integer;
  mPid: Int64;
begin
  AContext := Default(TIdeContext);
  mRoot := TJsonRead.ParseObject(AText);
  if mRoot = nil then
  begin
    Exit(False);
  end;
  try
    mFormat := TJsonRead.IntOr(mRoot, 'format', 0);
    mPid := TJsonRead.Int64Or(mRoot, 'pid', 0);
    Result := (mFormat >= 1) and (mFormat <= cFormat) and (mPid > 0);
    if not Result then
    begin
      Exit;
    end;
    AContext.Pid := Cardinal(mPid);
    AContext.AtUtc := TTextTimestamp.IsoOrZero(TJsonRead.Text(mRoot, 'at'), True);
    AContext.AtLocal := TTextTimestamp.IsoOrZero(TJsonRead.Text(mRoot, 'at'), False);
    AContext.Editor := EditorOf(TJsonRead.Obj(mRoot, 'editor'));
    AContext.Selection := SelectionOf(TJsonRead.Obj(mRoot, 'selection'));
    AContext.Project := ProjectOf(TJsonRead.Obj(mRoot, 'project'));
    AContext.Build := BuildOf(TJsonRead.Obj(mRoot, 'build'));
    AContext.Tabs := TJsonRead.Strings(mRoot, 'tabs');
  finally
    mRoot.Free;
  end;
end;

end.
