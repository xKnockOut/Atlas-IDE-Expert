unit Mcp.Tools.Ide;

// Host-Rolle Core: MCP-Modus (--mcp, #48), Verbindung zur laufenden IDE über die Dateien des Plugins:
// ungespeicherte Dateien (editor-dirty-<pid>.json), Schreiben am Editor vorbei, Builds und Debuggen über das Plugin,
// Zustand der IDE (ide-context-<pid>.json, #2050), Änderungen an ungespeicherten Dateien zurückhalten (#2605) und
// Rückfragen an den Menschen in der IDE (ask_user, #2620). Jeder Auftrag an die IDE trägt die Herkunft (Client und
// Sitzung, #2616), die der Aufrufer über Create mitgibt.

interface

uses
  System.SysUtils,
  System.JSON,
  Mcp.EditTools,
  Mcp.IdeDebug,
  Mcp.IdeQuestions,
  Atlas.Text.IdeContext,
  Mcp.IdeBuilds,
  Atlas.Common.Compiler.IdeBuild,
  Atlas.Text.AssistantOrigin,
  Mcp.Contract.Workspace,
  Mcp.Contract.Process;

type
  /// <summary>Projekt öffnen, das in keiner IDE offen ist (#2895): Projektdateien unter dem Arbeitsordner (erst bei
  /// Bedarf gelesen) und Zustimmung nach mcp.openProjects. Default = nie öffnen.</summary>
  TMcpIdeOpen = record
    Candidates: TFunc<TArray<string>>;
    MayOpen: TMcpMayOpenFunc;
  end;

  /// <summary>Herkunft der Aufträge an die IDE beim Aufruf (#2616).</summary>
  TMcpIdeOriginFunc = reference to function: TAtlasAssistantOrigin;

  /// <summary>Verbindung zur laufenden IDE über die Dateien des Plugins; ob eine IDE läuft und das Warten auf ihre
  /// Antwort fragt sie den Host über Process.</summary>
  TMcpIde = record
  private
    FProcess: IMcpProcessHost;
    FOrigin: TMcpIdeOriginFunc;
    function Origin: TAtlasAssistantOrigin;
    function IdeWithOpenFile(const AFileName: string): Cardinal;
    function RunningIdes: TArray<TMcpIdeEntry>;
    function DebugIde(const ARoot, ATool, AProject: string; const AOpen: TMcpIdeOpen;
      out AProjectFile: string): Cardinal;
  public
    /// <summary>Ohne Herkunft: Aufträge kommen vom unbekannten Assistenten.</summary>
    class function Create(const AProcess: IMcpProcessHost): TMcpIde; overload; static;
    /// <summary>Aufträge mit der Herkunft aus AOrigin.</summary>
    class function Create(const AProcess: IMcpProcessHost; const AOrigin: TMcpIdeOriginFunc): TMcpIde; overload;
      static;
    /// <summary>Aufträge mit Client und Sitzung von AWorkspace (MCP-Werkzeuge).</summary>
    class function ForWorkspace(const AProcess: IMcpProcessHost; const AWorkspace: IMcpWorkspace): TMcpIde; static;
    /// <summary>Im Editor der IDE ungespeichert geänderte Dateien: editor-dirty-&lt;pid&gt;.json je laufender
    /// IDE.</summary>
    function EditorDirtyFiles: TArray<string>;
    /// <summary>Prozesse der laufenden IDEs mit Atlas-Plugin (editor-dirty-&lt;pid&gt;.json).</summary>
    function RunningIdePids: TArray<Cardinal>;
    /// <summary>Zustand je laufender IDE, deren Modul KI-Assistenten ihn bereitstellt (ide-context-&lt;pid&gt;.json,
    /// #2050); unlesbare Dateien und Dateien beendeter Prozesse fallen weg.</summary>
    function IdeContexts: TArray<TIdeContext>;
    /// <summary>
    /// Schreibt AText mit Kodierung und Zeilenenden der vorhandenen Datei (#121). Ist die Datei in einer IDE
    /// mit Atlas-Plugin offen, ändert das Plugin den Puffer und speichert (#397); sonst die Platte.
    /// </summary>
    procedure WriteSourceText(const AFileName, AText: string);
    /// <summary>Änderung an einer im Editor ungespeichert geänderten Datei (#2605): Das Plugin der IDE, in der sie offen
    /// ist, hält sie zurück, bis der Benutzer entscheidet (Held), oder wendet sie gleich an (Applied). Refused mit Grund,
    /// wenn keine IDE sie annimmt; der MCP-Server schreibt eine solche Datei nie selbst.</summary>
    function HoldSourceText(const AFileName, AExpected, AText: string; out AReason: string): TMcpHoldResult;
    /// <summary>ask_user (#2620): stellt die Frage aus AArguments in der IDE mit dem aktiven Projekt unter ARoot (sonst
    /// der ersten mit Atlas) und wartet auf die Antwort. Liefert den Text für den Assistenten; EMcpToolError bei
    /// ungültigen Argumenten.</summary>
    function AskInIde(const ARoot: string; const AArguments: TJSONObject): string;
    /// <summary>Stellt AQuestion in der IDE mit dem aktiven Projekt unter ARoot (sonst der ersten mit Atlas) und wartet
    /// auf die Antwort (#2620, auch für Rückfragen der schreibenden Werkzeuge); AAnswer bei Answered.</summary>
    function AskQuestionInIde(const ARoot: string; const AQuestion: TMcpIdeQuestion;
      out AAnswer: string): TMcpQuestionOutcome;
    /// <summary>Baut AProject ('' = aktives Projekt) in der laufenden IDE über das Atlas-Plugin (#261) und wartet
    /// auf das Ende. Ist AProject in keiner IDE offen, öffnet es die IDE nach AOpen (#2895). EMcpToolError mit dem
    /// Grund, wenn keine IDE mit Atlas-Plugin das Projekt offen hat (und es nicht öffnen darf) oder sie den Auftrag
    /// nicht annimmt.</summary>
    function BuildInIde(const ARoot, AProject, AMode, AConfiguration, APlatform: string;
      const AOpen: TMcpIdeOpen): TIdeBuild;
    /// <summary>Debug-Werkzeug ATool (#1874) in der laufenden IDE: debug_start wählt die IDE wie build_project nach
    /// AProject (nicht offen: nach AOpen öffnen, #2895), die übrigen Werkzeuge gehen an die IDE des letzten
    /// debug_start (sonst an die mit dem aktiven Projekt unter ARoot). Liefert das Ergebnis des Plugins als JSON-Text;
    /// EMcpToolError mit dem Grund.</summary>
    function DebugInIde(const ARoot, ATool, AProject: string; const AArguments: TJSONObject;
      const AResolve: TMcpIdeDebugResolve; const AOpen: TMcpIdeOpen): string;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.Classes,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Mcp.Server,
  Mcp.BuildTools,
  Mcp.IdeEdits,
  Mcp.IdeInbox,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Json,
  Atlas.Text.Files;

type
{$SCOPEDENUMS ON}
  TMcpIdeText = (ModeInvalid, ResultUnreadable, UnsavedNotTaken);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpIdeText] of TAtlasText = (
    (De: 'Argument "mode": erlaubt sind "make", "build" und "check"';
    En: 'Argument "mode": allowed are "make", "build" and "check"'),
    (De: 'Ergebnis der IDE nicht lesbar.'; En: 'Result of the IDE not readable.'),
    (De: '%s hat ungespeicherte Änderungen im Editor, und die IDE hält Änderungen nicht zurück ' +
      '(„Änderungen an ungespeicherten Dateien zurückhalten“ aus); nichts geändert. Erst in der IDE speichern.';
     En: '%s has unsaved changes in the editor, and the IDE does not hold changes back ("Hold back changes to ' +
      'unsaved files" off); nothing changed. Save in the IDE first.'));

  /// <summary>Sicherheitsnetz beim Warten auf die Antwort des Plugins: Das Plugin legt sie per Umbenennen an, das
  /// Ordnersignal weckt sofort; ohne Signal (verpasst, Netzlaufwerk) wird spätestens so oft nachgesehen.</summary>
  cAnswerSafetyMs = 500;

var
  /// <summary>IDE des letzten erfolgreichen debug_start; dorthin gehen die übrigen Debug-Werkzeuge (#1874).</summary>
  GDebugPid: Cardinal;

/// <summary>Datei des Plugins (editor-dirty-&lt;pid&gt;.json), UTF-8 mit oder ohne BOM. Über TFileEncoding: teilt
/// Löschen, damit das Plugin sie währenddessen atomar ersetzen kann. False, wenn sie gerade ersetzt, gelöscht oder
/// nicht lesbar ist: zählt wie nicht vorhanden.</summary>
function TryReadPluginFile(const AFileName: string; out AText: string): Boolean;
var
  mFileFormat: TFileFormat;
begin
  AText := '';
  try
    AText := TFileEncoding.LoadFromFile(AFileName, mFileFormat);
    Result := True;
  except
    on E: Exception do
    begin
      if not (TTextFiles.IsFileError(E) or (E is EFileEncodingError)) then
      begin
        raise;
      end;
      Result := False;
    end;
  end;
end;

class function TMcpIde.Create(const AProcess: IMcpProcessHost): TMcpIde;
begin
  Result := Default(TMcpIde);
  Result.FProcess := AProcess;
end;

class function TMcpIde.Create(const AProcess: IMcpProcessHost; const AOrigin: TMcpIdeOriginFunc): TMcpIde;
begin
  Result := Create(AProcess);
  Result.FOrigin := AOrigin;
end;

/// <summary>Herkunft aus AWorkspace beim Aufruf; in eigener Routine, damit die anonyme Methode nur AWorkspace
/// einfängt.</summary>
function WorkspaceOrigin(const AWorkspace: IMcpWorkspace): TMcpIdeOriginFunc;
begin
  Result :=
    function: TAtlasAssistantOrigin
    begin
      Result := Default(TAtlasAssistantOrigin);
      if AWorkspace <> nil then
      begin
        Result := TAtlasAssistantOrigin.Make(AWorkspace.Client, AWorkspace.Session);
      end;
    end;
end;

class function TMcpIde.ForWorkspace(const AProcess: IMcpProcessHost; const AWorkspace: IMcpWorkspace): TMcpIde;
begin
  Result := Create(AProcess, WorkspaceOrigin(AWorkspace));
end;

function TMcpIde.Origin: TAtlasAssistantOrigin;
begin
  Result := Default(TAtlasAssistantOrigin);
  if Assigned(FOrigin) then
  begin
    Result := FOrigin();
  end;
end;

/// <summary>Prozess der IDE, in der AFileName offen ist ("open" in editor-dirty-&lt;pid&gt;.json, #397); 0
/// ohne.</summary>
function TMcpIde.IdeWithOpenFile(const AFileName: string): Cardinal;
var
  mFileName, mText: string;
  mJson: TJSONValue;
  mItem: TJSONValue;
  mPid: Integer;
begin
  Result := 0;
  if not TDirectory.Exists(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas')) then
  begin
    Exit;
  end;
  for mFileName in TDirectory.GetFiles(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    'editor-dirty-*.json') do
  begin
    if not TryReadPluginFile(mFileName, mText) then
    begin
      Continue;
    end;
    mJson := TJSONObject.ParseJSONValue(mText);
    try
      if not (mJson is TJSONObject) or not TJSONObject(mJson).TryGetValue<Integer>('pid', mPid) or
        not FProcess.Running(Cardinal(mPid)) or not (TJSONObject(mJson).GetValue('open') is TJSONArray) then
      begin
        Continue;
      end;
      for mItem in TJSONArray(TJSONObject(mJson).GetValue('open')) do
      begin
        if SameText(mItem.Value, AFileName) then
        begin
          Exit(Cardinal(mPid));
        end;
      end;
    finally
      mJson.Free;
    end;
  end;
end;

/// <summary>Laufende IDEs mit Atlas-Plugin samt offenen Projekten (editor-dirty-&lt;pid&gt;.json, #261).</summary>
function TMcpIde.RunningIdes: TArray<TMcpIdeEntry>;
var
  mFileName, mText: string;
  mEntry: TMcpIdeEntry;
begin
  Result := nil;
  if not TDirectory.Exists(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas')) then
  begin
    Exit;
  end;
  for mFileName in TDirectory.GetFiles(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    'editor-dirty-*.json') do
  begin
    if not TryReadPluginFile(mFileName, mText) then
    begin
      Continue;
    end;
    if TMcpIdeBuilds.ParseEntry(mText, mEntry) and FProcess.Running(mEntry.Pid) then
    begin
      Result := Result + [mEntry];
    end;
  end;
end;

function TMcpIde.RunningIdePids: TArray<Cardinal>;
var
  mEntry: TMcpIdeEntry;
begin
  Result := nil;
  for mEntry in RunningIdes do
  begin
    Result := Result + [mEntry.Pid];
  end;
end;

function TMcpIde.IdeContexts: TArray<TIdeContext>;
var
  mFolder, mFileName, mText: string;
  mContext: TIdeContext;
begin
  Result := nil;
  mFolder := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas');
  if not TDirectory.Exists(mFolder) then
  begin
    Exit;
  end;
  for mFileName in TDirectory.GetFiles(mFolder, TIdeContexts.cPrefix + '*' + TIdeContexts.cSuffix) do
  begin
    if not TryReadPluginFile(mFileName, mText) then
    begin
      Continue;
    end;
    if TIdeContexts.Parse(mText, mContext) and FProcess.Running(mContext.Pid) then
    begin
      Result := Result + [mContext];
    end;
  end;
end;

/// <summary>Im Editor der IDE ungespeichert geänderte Dateien: editor-dirty-&lt;pid&gt;.json je laufender
/// IDE.</summary>
function TMcpIde.EditorDirtyFiles: TArray<string>;
var
  mFileName, mText: string;
  mJson: TJSONValue;
  mPid: Integer;
begin
  Result := nil;
  if not TDirectory.Exists(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas')) then
  begin
    Exit;
  end;
  for mFileName in TDirectory.GetFiles(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    'editor-dirty-*.json') do
  begin
    if not TryReadPluginFile(mFileName, mText) then
    begin
      Continue;
    end;
    mJson := TJSONObject.ParseJSONValue(mText);
    try
      if not (mJson is TJSONObject) or not TJSONObject(mJson).TryGetValue<Integer>('pid', mPid) or
        not FProcess.Running(Cardinal(mPid)) then
      begin
        Continue;
      end;
      Result := Result + TJsonRead.Strings(TJSONObject(mJson), 'files');
    finally
      mJson.Free;
    end;
  end;
end;

/// <summary>
/// Schreibt AText mit Kodierung und Zeilenenden der vorhandenen Datei (#121). Ist die Datei in einer IDE
/// mit Atlas-Plugin offen, ändert das Plugin den Puffer und speichert (#397); sonst die Platte.
/// </summary>
procedure TMcpIde.WriteSourceText(const AFileName, AText: string);
var
  mFileFormat: TFileFormat;
  mExpected, mReason, mInbox: string;
  mPid: Cardinal;
  mEdit: TMcpIdeEdit;
begin
  mExpected := TFileEncoding.LoadFromFile(AFileName, mFileFormat);
  mPid := IdeWithOpenFile(AFileName);
  if mPid <> 0 then
  begin
    mInbox := TMcpIdeEdits.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), mPid);
    mEdit := TMcpIdeEdit.Make(AFileName, mExpected, AText);
    mEdit.Origin := Origin;
    case TMcpIdeEdits.Send(mInbox, mEdit,
      FProcess.FolderWait(mInbox, TMcpIdeEdits.cPollMs, cAnswerSafetyMs),
      function: Int64
      begin
        Result := TThread.GetTickCount64;
      end, mReason) of
      TMcpIdeEditOutcome.Applied:
        Exit;
      TMcpIdeEditOutcome.Failed:
        raise EMcpToolError.CreateFmt('IDE: %s', [mReason]);
    end;
  end;
  TFileEncoding.SaveToFile(AFileName, AText, mFileFormat);
end;

function TMcpIde.HoldSourceText(const AFileName, AExpected, AText: string; out AReason: string): TMcpHoldResult;
var
  mPid: Cardinal;
  mInbox: string;
  mEdit: TMcpIdeEdit;
begin
  AReason := cTexts[TMcpIdeText.UnsavedNotTaken].Fmt([AFileName]);
  mPid := IdeWithOpenFile(AFileName);
  if mPid = 0 then
  begin
    Exit(TMcpHoldResult.Refused);
  end;
  mInbox := TMcpIdeEdits.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), mPid);
  mEdit := TMcpIdeEdit.Make(AFileName, AExpected, AText);
  mEdit.Hold := True;
  mEdit.Origin := Origin;
  case TMcpIdeEdits.Send(mInbox, mEdit, FProcess.FolderWait(mInbox, TMcpIdeEdits.cPollMs, cAnswerSafetyMs),
    function: Int64
    begin
      Result := TThread.GetTickCount64;
    end, AReason) of
    TMcpIdeEditOutcome.Applied:
      Result := TMcpHoldResult.Applied;
    TMcpIdeEditOutcome.Held:
      Result := TMcpHoldResult.Held;
    TMcpIdeEditOutcome.Failed:
      begin
        AReason := Format('IDE: %s', [AReason]);
        Result := TMcpHoldResult.Refused;
      end;
  else
    // Nicht angenommen oder nicht mehr offen: Die Datei ist im Editor geändert, also nicht selbst schreiben.
    AReason := cTexts[TMcpIdeText.UnsavedNotTaken].Fmt([AFileName]);
    Result := TMcpHoldResult.Refused;
  end;
end;

/// <summary>Projekt aus dem Argument project: ein relativer Pfad gilt relativ zum Arbeitsordner, Namen bleiben.
/// </summary>
function WantedProject(const ARoot, AProject: string): string;
begin
  Result := AProject;
  if (Result <> '') and ((Pos('\', Result) > 0) or (Pos('/', Result) > 0)) and not TPath.IsPathRooted(Result) then
  begin
    Result := TPath.GetFullPath(TPath.Combine(ARoot, Result));
  end;
end;

/// <summary>Uhr in Millisekunden für das Warten auf das Plugin.</summary>
function TickClock: TFunc<Int64>;
begin
  Result :=
    function: Int64
    begin
      Result := TThread.GetTickCount64;
    end;
end;

/// <summary>Baut AProject ('' = aktives Projekt) in der laufenden IDE über das Atlas-Plugin (#261) und wartet
/// auf das Ende. EMcpToolError mit dem Grund, wenn keine IDE mit Atlas-Plugin das Projekt offen hat oder sie
/// den Auftrag nicht annimmt.</summary>
function TMcpIde.BuildInIde(const ARoot, AProject, AMode, AConfiguration, APlatform: string;
  const AOpen: TMcpIdeOpen): TIdeBuild;
var
  mRequest: TMcpIdeBuildRequest;
  mPid: Cardinal;
  mWanted, mBuildText, mReason, mInbox: string;
begin
  mRequest := Default(TMcpIdeBuildRequest);
  mRequest.Mode := AMode;
  if mRequest.Mode = '' then
  begin
    mRequest.Mode := 'make';
  end;
  if not TMcpIdeBuilds.ModeValid(mRequest.Mode) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpIdeText.ModeInvalid].Text);
  end;
  mRequest.Configuration := AConfiguration;
  mRequest.Platform := APlatform;
  mRequest.Origin := Origin;
  mWanted := WantedProject(ARoot, AProject);
  if not TMcpIdeBuilds.PickOrOpen(RunningIdes, ARoot, mWanted, AOpen.Candidates, AOpen.MayOpen, mPid,
    mRequest.Project, mReason) then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  mInbox := TMcpIdeBuilds.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), mPid);
  if TMcpIdeBuilds.Send(mInbox, mRequest, FProcess.FolderWait(mInbox, TMcpIdeBuilds.cPollMs, cAnswerSafetyMs),
    TickClock(), mBuildText, mReason) <> TMcpIdeBuildOutcome.Done then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  if not TMcpBuildTools.FromFileText(mBuildText, Result) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpIdeText.ResultUnreadable].Text);
  end;
end;

function TMcpIde.AskQuestionInIde(const ARoot: string; const AQuestion: TMcpIdeQuestion;
  out AAnswer: string): TMcpQuestionOutcome;
var
  mEntries: TArray<TMcpIdeEntry>;
  mPid: Cardinal;
  mReason, mProject, mInbox, mAnswerText: string;
begin
  AAnswer := '';
  mEntries := RunningIdes;
  if Length(mEntries) = 0 then
  begin
    Exit(TMcpQuestionOutcome.NoIde);
  end;
  // Die IDE mit dem aktiven Projekt unter dem Arbeitsordner, sonst die erste mit Atlas.
  if not TMcpIdeBuilds.Pick(mEntries, ARoot, '', mPid, mProject, mReason) then
  begin
    mPid := mEntries[0].Pid;
  end;
  mInbox := TMcpIdeQuestions.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), mPid);
  case TMcpIdeInbox.Exchange(mInbox, TMcpIdeQuestions.RequestText(AQuestion),
    TMcpIdeWaiting.Make(FProcess.FolderWait(mInbox, TMcpIdeQuestions.cPollMs, cAnswerSafetyMs), TickClock(),
    TMcpIdeQuestions.cTakeMs, TMcpIdeQuestions.AnswerMs(AQuestion)), mAnswerText) of
    TMcpIdeExchangeOutcome.NotTaken:
      Result := TMcpQuestionOutcome.NotTaken;
    TMcpIdeExchangeOutcome.TimedOut:
      Result := TMcpQuestionOutcome.TimedOut;
  else
    Result := TMcpIdeQuestions.ParseAnswer(mAnswerText, AAnswer);
  end;
end;

function TMcpIde.AskInIde(const ARoot: string; const AArguments: TJSONObject): string;
var
  mQuestion: TMcpIdeQuestion;
  mReason, mAnswer: string;
  mOutcome: TMcpQuestionOutcome;
begin
  if not TMcpIdeQuestions.FromArguments(AArguments, Origin, mQuestion, mReason) then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  mOutcome := AskQuestionInIde(ARoot, mQuestion, mAnswer);
  Result := TMcpIdeQuestions.ResultText(mOutcome, mAnswer, mQuestion);
end;

/// <summary>IDE für ein Debug-Werkzeug: für debug_start nach AProject (AProjectFile = gewähltes Projekt), sonst die
/// des letzten debug_start, solange sie läuft, ersatzweise die mit dem aktiven Projekt unter ARoot.</summary>
function TMcpIde.DebugIde(const ARoot, ATool, AProject: string; const AOpen: TMcpIdeOpen; out AProjectFile: string): Cardinal;
var
  mEntries: TArray<TMcpIdeEntry>;
  mEntry: TMcpIdeEntry;
  mReason: string;
begin
  mEntries := RunningIdes;
  AProjectFile := '';
  if Length(mEntries) = 0 then
  begin
    raise EMcpToolError.Create(TMcpIdeDebug.NoIdeReason);
  end;
  if ATool <> TMcpIdeDebug.cStart then
  begin
    for mEntry in mEntries do
    begin
      if (GDebugPid <> 0) and (mEntry.Pid = GDebugPid) then
      begin
        Exit(GDebugPid);
      end;
    end;
  end;
  if not TMcpIdeBuilds.PickOrOpen(mEntries, ARoot, WantedProject(ARoot, AProject), AOpen.Candidates, AOpen.MayOpen,
    Result, AProjectFile, mReason) then
  begin
    raise EMcpToolError.Create(mReason);
  end;
end;

function TMcpIde.DebugInIde(const ARoot, ATool, AProject: string; const AArguments: TJSONObject;
  const AResolve: TMcpIdeDebugResolve; const AOpen: TMcpIdeOpen): string;
var
  mPid: Cardinal;
  mOpen: TMcpIdeOpen;
  mProjectFile, mRequest, mReason, mInbox: string;
begin
  // Erst die Argumente prüfen: Fehler darin meldet das Werkzeug auch ohne laufende IDE.
  if not TMcpIdeDebug.RequestText(TMcpIdeDebugCall.Make(ATool, Origin, ''), AArguments, AResolve, mRequest,
    mReason) then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  // Öffnen nur für den Start; die übrigen Werkzeuge gehen an eine IDE, die schon läuft.
  mOpen := Default(TMcpIdeOpen);
  if ATool = TMcpIdeDebug.cStart then
  begin
    mOpen := AOpen;
  end;
  mPid := DebugIde(ARoot, ATool, AProject, mOpen, mProjectFile);
  if not TMcpIdeDebug.RequestText(TMcpIdeDebugCall.Make(ATool, Origin, mProjectFile), AArguments, AResolve,
    mRequest, mReason) then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  mInbox := TMcpIdeDebug.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), mPid);
  if TMcpIdeDebug.Send(mInbox, mRequest, TMcpIdeWaiting.Make(FProcess.FolderWait(mInbox, TMcpIdeDebug.cPollMs,
    cAnswerSafetyMs), TickClock(), TMcpIdeDebug.cTakeMs, TMcpIdeDebug.AnswerMs(AArguments)), Result,
    mReason) <> TMcpIdeDebugOutcome.Done then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  if ATool = TMcpIdeDebug.cStart then
  begin
    GDebugPid := mPid;
  end;
end;

initialization
  TAtlasTextTables.Add('Mcp.Tools.Ide', cTexts);

end.
