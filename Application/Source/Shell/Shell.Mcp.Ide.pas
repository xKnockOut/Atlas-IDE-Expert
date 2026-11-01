unit Shell.Mcp.Ide;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Verbindung zur laufenden IDE über die Dateien des Plugins:
// ungespeicherte Dateien (editor-dirty-<pid>.json), Schreiben am Editor vorbei, Builds über das Plugin.

interface

uses
  Atlas.Common.Lsp.IdeBuild;

/// <summary>Im Editor der IDE ungespeichert geänderte Dateien: editor-dirty-&lt;pid&gt;.json je laufender IDE.</summary>
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
  System.IOUtils,
  System.JSON,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.BuildTools,
  Atlas.Common.Mcp.IdeEdits,
  Atlas.Common.Mcp.IdeBuilds,
  Shell.Platform;

/// <summary>Datei des Plugins (editor-dirty-&lt;pid&gt;.json), UTF-8 mit oder ohne BOM. Über TFileEncoding: teilt
/// Löschen, damit das Plugin sie währenddessen atomar ersetzen kann (Bericht M5, N3).</summary>
function ReadPluginFile(const AFileName: string): string;
var
  FileFormat: TFileFormat;
begin
  Result := TFileEncoding.LoadFromFile(AFileName, FileFormat);
end;

/// <summary>Prozess der IDE, in der AFileName offen ist ("open" in editor-dirty-&lt;pid&gt;.json, #397); 0 ohne.</summary>
function IdeWithOpenFile(const AFileName: string): Cardinal;
var
  FileName, Text: string;
  Json: TJSONValue;
  Item: TJSONValue;
  Pid: Integer;
begin
  Result := 0;
  if not TDirectory.Exists(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas')) then
  begin
    Exit;
  end;
  for FileName in TDirectory.GetFiles(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    'editor-dirty-*.json') do
  begin
    try
      Text := ReadPluginFile(FileName);
    except
      on Exception do
        Continue;
    end;
    Json := TJSONObject.ParseJSONValue(Text);
    try
      if not (Json is TJSONObject) or not TJSONObject(Json).TryGetValue<Integer>('pid', Pid) or
        not TProcessInstances.Running(Cardinal(Pid)) or not (TJSONObject(Json).GetValue('open') is TJSONArray) then
      begin
        Continue;
      end;
      for Item in TJSONArray(TJSONObject(Json).GetValue('open')) do
      begin
        if SameText(Item.Value, AFileName) then
        begin
          Exit(Cardinal(Pid));
        end;
      end;
    finally
      Json.Free;
    end;
  end;
end;

/// <summary>Laufende IDEs mit Atlas-Plugin samt offenen Projekten (editor-dirty-&lt;pid&gt;.json, #261).</summary>
function RunningIdes: TArray<TMcpIdeEntry>;
var
  FileName, Text: string;
  Entry: TMcpIdeEntry;
begin
  Result := nil;
  if not TDirectory.Exists(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas')) then
  begin
    Exit;
  end;
  for FileName in TDirectory.GetFiles(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    'editor-dirty-*.json') do
  begin
    try
      Text := ReadPluginFile(FileName);
    except
      on Exception do
        Continue;
    end;
    if TMcpIdeBuilds.ParseEntry(Text, Entry) and TProcessInstances.Running(Entry.Pid) then
    begin
      Result := Result + [Entry];
    end;
  end;
end;

/// <summary>Im Editor der IDE ungespeichert geänderte Dateien: editor-dirty-&lt;pid&gt;.json je laufender IDE.</summary>
function EditorDirtyFiles: TArray<string>;
var
  FileName, Text: string;
  Json: TJSONValue;
  Item: TJSONValue;
  Pid: Integer;
begin
  Result := nil;
  if not TDirectory.Exists(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas')) then
  begin
    Exit;
  end;
  for FileName in TDirectory.GetFiles(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    'editor-dirty-*.json') do
  begin
    try
      Text := ReadPluginFile(FileName);
    except
      on Exception do
        Continue;
    end;
    Json := TJSONObject.ParseJSONValue(Text);
    try
      if not (Json is TJSONObject) or not TJSONObject(Json).TryGetValue<Integer>('pid', Pid) or
        not TProcessInstances.Running(Cardinal(Pid)) then
      begin
        Continue;
      end;
      if TJSONObject(Json).GetValue('files') is TJSONArray then
      begin
        for Item in TJSONArray(TJSONObject(Json).GetValue('files')) do
        begin
          Result := Result + [Item.Value];
        end;
      end;
    finally
      Json.Free;
    end;
  end;
end;

/// <summary>
/// Schreibt AText mit Kodierung und Zeilenenden der vorhandenen Datei (#121). Ist die Datei in einer IDE
/// mit Atlas-Plugin offen, ändert das Plugin den Puffer und speichert (#397); sonst die Platte.
/// </summary>
procedure WriteSourceText(const AFileName, AText: string);
var
  FileFormat: TFileFormat;
  Expected, Reason: string;
  Pid: Cardinal;
begin
  Expected := TFileEncoding.LoadFromFile(AFileName, FileFormat);
  Pid := IdeWithOpenFile(AFileName);
  if Pid <> 0 then
    case TMcpIdeEdits.Send(TMcpIdeEdits.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), Pid),
      AFileName, Expected, AText,
      procedure
      begin
        Sleep(TMcpIdeEdits.PollMs);
      end,
      function: Int64
      begin
        Result := GetTickCount64;
      end, Reason) of
      TMcpIdeEditOutcome.Applied:
        Exit;
      TMcpIdeEditOutcome.Failed:
        raise EMcpToolError.CreateFmt('IDE: %s', [Reason]);
    end;
  TFileEncoding.SaveToFile(AFileName, AText, FileFormat);
end;

/// <summary>Baut AProject ('' = aktives Projekt) in der laufenden IDE über das Atlas-Plugin (#261) und wartet
/// auf das Ende. EMcpToolError mit dem Grund, wenn keine IDE mit Atlas-Plugin das Projekt offen hat oder sie
/// den Auftrag nicht annimmt.</summary>
function BuildInIde(const ARoot, AProject, AMode, AConfiguration, APlatform: string): TIdeBuild;
var
  Request: TMcpIdeBuildRequest;
  Pid: Cardinal;
  Wanted, BuildText, Reason: string;
begin
  Request := Default(TMcpIdeBuildRequest);
  Request.Mode := AMode;
  if Request.Mode = '' then
  begin
    Request.Mode := 'make';
  end;
  if not TMcpIdeBuilds.ModeValid(Request.Mode) then
  begin
    raise EMcpToolError.Create('Argument "mode": erlaubt sind "make", "build" und "check"');
  end;
  Request.Configuration := AConfiguration;
  Request.Platform := APlatform;
  // Relativer Pfad: relativ zum Arbeitsordner.
  Wanted := AProject;
  if (Wanted <> '') and ((Pos('\', Wanted) > 0) or (Pos('/', Wanted) > 0)) and not TPath.IsPathRooted(Wanted) then
  begin
    Wanted := TPath.GetFullPath(TPath.Combine(ARoot, Wanted));
  end;
  if not TMcpIdeBuilds.Pick(RunningIdes, ARoot, Wanted, Pid, Request.Project, Reason) then
  begin
    raise EMcpToolError.Create(Reason);
  end;
  if TMcpIdeBuilds.Send(TMcpIdeBuilds.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    Pid), Request,
    procedure
    begin
      Sleep(TMcpIdeBuilds.PollMs);
    end,
    function: Int64
    begin
      Result := GetTickCount64;
    end, BuildText, Reason) <> TMcpIdeBuildOutcome.Done then
  begin
    raise EMcpToolError.Create(Reason);
  end;
  if not TMcpBuildTools.FromFileText(BuildText, Result) then
  begin
    raise EMcpToolError.Create('Ergebnis der IDE nicht lesbar.');
  end;
end;

end.
