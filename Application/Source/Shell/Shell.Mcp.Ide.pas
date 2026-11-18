unit Shell.Mcp.Ide;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Verbindung zur laufenden IDE über die Dateien des Plugins:
// ungespeicherte Dateien (editor-dirty-<pid>.json), Schreiben am Editor vorbei, Builds und Debuggen über das Plugin.

interface

uses
  System.JSON,
  Atlas.Common.Mcp.IdeDebug,
  Atlas.Common.Lsp.IdeBuild;

/// <summary>Im Editor der IDE ungespeichert geänderte Dateien: editor-dirty-&lt;pid&gt;.json je laufender
/// IDE.</summary>
function EditorDirtyFiles: TArray<string>;
/// <summary>
/// Schreibt AText mit Kodierung und Zeilenenden der vorhandenen Datei (#121). Ist die Datei in einer IDE
/// mit Atlas-Plugin offen, ändert das Plugin den Puffer und speichert (#397); sonst die Platte.
/// </summary>
procedure WriteSourceText(const AFileName, AText: string);
/// <summary>Baut AProject ('' = aktives Projekt) in der laufenden IDE über das Atlas-Plugin (#261) und wartet
/// auf das Ende. EMcpToolError mit dem Grund, wenn keine IDE mit Atlas-Plugin das Projekt offen hat oder sie
/// den Auftrag nicht annimmt.</summary>
function BuildInIde(const ARoot, AProject, AMode, AConfiguration, APlatform: string): TIdeBuild;
/// <summary>Debug-Werkzeug ATool (#1874) in der laufenden IDE: debug_start wählt die IDE wie build_project nach
/// AProject, die übrigen Werkzeuge gehen an die IDE des letzten debug_start (sonst an die mit dem aktiven Projekt
/// unter ARoot). Liefert das Ergebnis des Plugins als JSON-Text; EMcpToolError mit dem Grund.</summary>
function DebugInIde(const ARoot, ATool, AClient, AProject: string; const AArguments: TJSONObject;
  const AResolve: TMcpIdeDebugResolve): string;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.BuildTools,
  Atlas.Common.Mcp.IdeEdits,
  Atlas.Common.Mcp.IdeInbox,
  Atlas.Common.Mcp.IdeBuilds,
  Shell.Platform,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Json;

type
{$SCOPEDENUMS ON}
  TMcpIdeText = (ModeInvalid, ResultUnreadable);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpIdeText] of TAtlasText = (
    (De: 'Argument "mode": erlaubt sind "make", "build" und "check"';
    En: 'Argument "mode": allowed are "make", "build" and "check"'),
    (De: 'Ergebnis der IDE nicht lesbar.'; En: 'Result of the IDE not readable.'));

  /// <summary>Sicherheitsnetz beim Warten auf die Antwort des Plugins: Das Plugin legt sie per Umbenennen an, das
  /// Ordnersignal weckt sofort; ohne Signal (verpasst, Netzlaufwerk) wird spätestens so oft nachgesehen.</summary>
  cAnswerSafetyMs = 500;

var
  /// <summary>IDE des letzten erfolgreichen debug_start; dorthin gehen die übrigen Debug-Werkzeuge (#1874).</summary>
  GDebugPid: Cardinal;

/// <summary>Datei des Plugins (editor-dirty-&lt;pid&gt;.json), UTF-8 mit oder ohne BOM. Über TFileEncoding: teilt
/// Löschen, damit das Plugin sie währenddessen atomar ersetzen kann (N3).</summary>
function ReadPluginFile(const AFileName: string): string;
var
  mFileFormat: TFileFormat;
begin
  Result := TFileEncoding.LoadFromFile(AFileName, mFileFormat);
end;

/// <summary>Prozess der IDE, in der AFileName offen ist ("open" in editor-dirty-&lt;pid&gt;.json, #397); 0
/// ohne.</summary>
function IdeWithOpenFile(const AFileName: string): Cardinal;
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
    try
      mText := ReadPluginFile(mFileName);
    except
      on Exception do
        Continue;
    end;
    mJson := TJSONObject.ParseJSONValue(mText);
    try
      if not (mJson is TJSONObject) or not TJSONObject(mJson).TryGetValue<Integer>('pid', mPid) or
        not TProcessInstances.Running(Cardinal(mPid)) or not (TJSONObject(mJson).GetValue('open') is TJSONArray) then
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
function RunningIdes: TArray<TMcpIdeEntry>;
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
    try
      mText := ReadPluginFile(mFileName);
    except
      on Exception do
        Continue;
    end;
    if TMcpIdeBuilds.ParseEntry(mText, mEntry) and TProcessInstances.Running(mEntry.Pid) then
    begin
      Result := Result + [mEntry];
    end;
  end;
end;

/// <summary>Im Editor der IDE ungespeichert geänderte Dateien: editor-dirty-&lt;pid&gt;.json je laufender
/// IDE.</summary>
function EditorDirtyFiles: TArray<string>;
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
    try
      mText := ReadPluginFile(mFileName);
    except
      on Exception do
        Continue;
    end;
    mJson := TJSONObject.ParseJSONValue(mText);
    try
      if not (mJson is TJSONObject) or not TJSONObject(mJson).TryGetValue<Integer>('pid', mPid) or
        not TProcessInstances.Running(Cardinal(mPid)) then
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
procedure WriteSourceText(const AFileName, AText: string);
var
  mFileFormat: TFileFormat;
  mExpected, mReason, mInbox: string;
  mPid: Cardinal;
begin
  mExpected := TFileEncoding.LoadFromFile(AFileName, mFileFormat);
  mPid := IdeWithOpenFile(AFileName);
  if mPid <> 0 then
  begin
    mInbox := TMcpIdeEdits.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), mPid);
    case TMcpIdeEdits.Send(mInbox, TMcpIdeEdit.Make(AFileName, mExpected, AText),
      TShellPlatform.FolderWait(mInbox, TMcpIdeEdits.cPollMs, cAnswerSafetyMs),
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
function BuildInIde(const ARoot, AProject, AMode, AConfiguration, APlatform: string): TIdeBuild;
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
  mWanted := WantedProject(ARoot, AProject);
  if not TMcpIdeBuilds.Pick(RunningIdes, ARoot, mWanted, mPid, mRequest.Project, mReason) then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  mInbox := TMcpIdeBuilds.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), mPid);
  if TMcpIdeBuilds.Send(mInbox, mRequest, TShellPlatform.FolderWait(mInbox, TMcpIdeBuilds.cPollMs, cAnswerSafetyMs),
    TickClock(), mBuildText, mReason) <> TMcpIdeBuildOutcome.Done then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  if not TMcpBuildTools.FromFileText(mBuildText, Result) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpIdeText.ResultUnreadable].Text);
  end;
end;

/// <summary>IDE für ein Debug-Werkzeug: für debug_start nach AProject (AProjectFile = gewähltes Projekt), sonst die
/// des letzten debug_start, solange sie läuft, ersatzweise die mit dem aktiven Projekt unter ARoot.</summary>
function DebugIde(const ARoot, ATool, AProject: string; out AProjectFile: string): Cardinal;
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
  if not TMcpIdeBuilds.Pick(mEntries, ARoot, WantedProject(ARoot, AProject), Result, AProjectFile, mReason) then
  begin
    raise EMcpToolError.Create(mReason);
  end;
end;

function DebugInIde(const ARoot, ATool, AClient, AProject: string; const AArguments: TJSONObject;
  const AResolve: TMcpIdeDebugResolve): string;
var
  mPid: Cardinal;
  mProjectFile, mRequest, mReason, mInbox: string;
begin
  // Erst die Argumente prüfen: Fehler darin meldet das Werkzeug auch ohne laufende IDE.
  if not TMcpIdeDebug.RequestText(TMcpIdeDebugCall.Make(ATool, AClient, ''), AArguments, AResolve, mRequest,
    mReason) then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  mPid := DebugIde(ARoot, ATool, AProject, mProjectFile);
  if not TMcpIdeDebug.RequestText(TMcpIdeDebugCall.Make(ATool, AClient, mProjectFile), AArguments, AResolve,
    mRequest, mReason) then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  mInbox := TMcpIdeDebug.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), mPid);
  if TMcpIdeDebug.Send(mInbox, mRequest, TMcpIdeWaiting.Make(TShellPlatform.FolderWait(mInbox, TMcpIdeDebug.cPollMs,
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
  TAtlasTextTables.Add('Shell.Mcp.Ide', cTexts);

end.
