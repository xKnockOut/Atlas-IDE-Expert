unit Shell.Mcp.Ide;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Verbindung zur laufenden IDE über die Dateien des Plugins:
// ungespeicherte Dateien (editor-dirty-<pid>.json), Schreiben am Editor vorbei, Builds über das Plugin.

interface

uses
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

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.BuildTools,
  Atlas.Common.Mcp.IdeEdits,
  Atlas.Common.Mcp.IdeBuilds,
  Shell.Platform,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TMcpIdeText = (ModeInvalid, ResultUnreadable);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpIdeText] of TAtlasText = (
    (De: 'Argument "mode": erlaubt sind "make", "build" und "check"';
    En: 'Argument "mode": allowed are "make", "build" and "check"'),
    (De: 'Ergebnis der IDE nicht lesbar.'; En: 'Result of the IDE not readable.'));

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
  mItem: TJSONValue;
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
      if TJSONObject(mJson).GetValue('files') is TJSONArray then
      begin
        for mItem in TJSONArray(TJSONObject(mJson).GetValue('files')) do
        begin
          Result := Result + [mItem.Value];
        end;
      end;
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
  mExpected, mReason: string;
  mPid: Cardinal;
begin
  mExpected := TFileEncoding.LoadFromFile(AFileName, mFileFormat);
  mPid := IdeWithOpenFile(AFileName);
  if mPid <> 0 then
    case TMcpIdeEdits.Send(TMcpIdeEdits.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), mPid),
      TMcpIdeEdit.Make(AFileName, mExpected, AText),
      procedure
      begin
        Sleep(TMcpIdeEdits.cPollMs);
      end,
      function: Int64
      begin
        Result := TThread.GetTickCount64;
      end, mReason) of
      TMcpIdeEditOutcome.Applied:
        Exit;
      TMcpIdeEditOutcome.Failed:
        raise EMcpToolError.CreateFmt('IDE: %s', [mReason]);
    end;
  TFileEncoding.SaveToFile(AFileName, AText, mFileFormat);
end;

/// <summary>Baut AProject ('' = aktives Projekt) in der laufenden IDE über das Atlas-Plugin (#261) und wartet
/// auf das Ende. EMcpToolError mit dem Grund, wenn keine IDE mit Atlas-Plugin das Projekt offen hat oder sie
/// den Auftrag nicht annimmt.</summary>
function BuildInIde(const ARoot, AProject, AMode, AConfiguration, APlatform: string): TIdeBuild;
var
  mRequest: TMcpIdeBuildRequest;
  mPid: Cardinal;
  mWanted, mBuildText, mReason: string;
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
  // Relativer Pfad: relativ zum Arbeitsordner.
  mWanted := AProject;
  if (mWanted <> '') and ((Pos('\', mWanted) > 0) or (Pos('/', mWanted) > 0)) and not TPath.IsPathRooted(mWanted) then
  begin
    mWanted := TPath.GetFullPath(TPath.Combine(ARoot, mWanted));
  end;
  if not TMcpIdeBuilds.Pick(RunningIdes, ARoot, mWanted, mPid, mRequest.Project, mReason) then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  if TMcpIdeBuilds.Send(TMcpIdeBuilds.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    mPid), mRequest,
    procedure
    begin
      Sleep(TMcpIdeBuilds.cPollMs);
    end,
    function: Int64
    begin
      Result := TThread.GetTickCount64;
    end, mBuildText, mReason) <> TMcpIdeBuildOutcome.Done then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  if not TMcpBuildTools.FromFileText(mBuildText, Result) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpIdeText.ResultUnreadable].Text);
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.Ide', cTexts);

end.
