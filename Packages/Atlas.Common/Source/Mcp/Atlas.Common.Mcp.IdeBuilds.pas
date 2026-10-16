unit Atlas.Common.Mcp.IdeBuilds;

// Bauen für Claude Code über die laufende IDE (#261, Werkzeug build_project).
// Ohne Kommandozeilen-Compiler (Starter Edition) baut das IDE-Plugin über
// IOTAProjectBuilder und antwortet mit Ergebnis und Compilermeldungen (#527,
// #528). Austausch über Dateien wie bei den schreibenden Werkzeugen (#397):
//   %LOCALAPPDATA%\Atlas\ide-builds\<pid>\<id>.json
//   {"project": Pfad der .dproj, "mode": "make"|"build"|"check",
//    "configuration": "", "platform": ""}          ('' = wie in der IDE)
// Das Plugin übernimmt den Auftrag durch Umbenennen in <id>.taken und
// antwortet mit <id>.result.json
//   {"ok": true, "build": {project, kind, configuration, platform, success,
//    durationMs, finishedAt, messages[]}}  bzw. {"ok": false, "reason": "…"}
// "build" hat das Format von TMcpBuildTools.ToFileText. Nimmt das Plugin den
// Auftrag nicht innerhalb von TakeMs an, zieht der MCP-Server ihn zurück.
// Welche IDE welche Projekte offen hat, steht unter "projects" und
// "activeProject" in editor-dirty-<pid>.json (TAtlasDirtyExport im Plugin).
// Gegenstück im Plugin: Atlas.Core.Build.Inbox und Atlas.IDE.Build.Inbox.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils;

type
  /// <summary>Eine laufende IDE mit Atlas-Plugin laut editor-dirty-&lt;pid&gt;.json.</summary>
  TMcpIdeEntry = record
    Pid: Cardinal;
    Projects: TArray<string>;
    ActiveProject: string;
  end;

  TMcpIdeBuildRequest = record
    Project: string;
    /// <summary>"make", "build" oder "check".</summary>
    Mode: string;
    /// <summary>'' = aktive Konfiguration bzw. Plattform der IDE.</summary>
    Configuration: string;
    Platform: string;
  end;

  TMcpIdeBuildOutcome = (Done, NotTaken, Refused, TimedOut);

  TMcpIdeBuilds = class
  public const
    /// <summary>So lange darf das Plugin bis zur Übernahme brauchen.</summary>
    TakeMs = 5000;
    /// <summary>Höchstdauer eines Builds nach der Übernahme.</summary>
    BuildMs = 30 * 60 * 1000;
    PollMs = 100;
  public
    /// <summary>Eingang des IDE-Prozesses APid unter ABase (%LOCALAPPDATA%\Atlas).</summary>
    class function InboxOf(const ABase: string; APid: Cardinal): string; static;
    /// <summary>"make", "build", "check" (Groß- und Kleinschreibung egal).</summary>
    class function ModeValid(const AMode: string): Boolean; static;
    /// <summary>Liest editor-dirty-&lt;pid&gt;.json; False ohne pid.</summary>
    class function ParseEntry(const AText: string; out AEntry: TMcpIdeEntry): Boolean; static;
    /// <summary>
    /// Wählt IDE und Projekt. AProject ('' = aktives Projekt einer IDE) passt auf vollen Pfad, Dateinamen oder
    /// Namen ohne Endung. Ohne AProject zählt nur ein aktives Projekt unter ARoot. False mit Grund in AReason.
    /// </summary>
    class function Pick(const AEntries: TArray<TMcpIdeEntry>; const ARoot, AProject: string; out APid: Cardinal;
      out AProjectFile, AReason: string): Boolean; static;
    class function RequestText(const ARequest: TMcpIdeBuildRequest): string; static;
    /// <summary>Liest die Antwort des Plugins; ABuildText = Objekt "build" als JSON-Text.</summary>
    class function ParseAnswer(const AText: string; out AOk: Boolean; out ABuildText, AReason: string): Boolean;
      static;
    /// <summary>
    /// Legt den Auftrag in AInbox und wartet auf das Plugin. AWait schläft kurz (Tests übernehmen darin die Rolle
    /// des Plugins), AClock liefert Millisekunden. Done: ABuildText enthält das Ergebnis. Sonst Grund in AReason.
    /// </summary>
    class function Send(const AInbox: string; const ARequest: TMcpIdeBuildRequest; const AWait: TProc;
      const AClock: TFunc<Int64>; out ABuildText, AReason: string): TMcpIdeBuildOutcome; overload; static;
    /// <summary>Wie oben mit eigenen Fristen (Tests).</summary>
    class function Send(const AInbox: string; const ARequest: TMcpIdeBuildRequest; const AWait: TProc;
      const AClock: TFunc<Int64>; ATakeMs, ABuildMs: Int64; out ABuildText, AReason: string): TMcpIdeBuildOutcome;
      overload; static;
  end;

implementation

uses
  System.IOUtils,
  System.JSON,
  Atlas.Common.Projects.Paths;

class function TMcpIdeBuilds.InboxOf(const ABase: string; APid: Cardinal): string;
begin
  Result := TPath.Combine(TPath.Combine(ABase, 'ide-builds'), IntToStr(APid));
end;

class function TMcpIdeBuilds.ModeValid(const AMode: string): Boolean;
begin
  Result := SameText(AMode, 'make') or SameText(AMode, 'build') or SameText(AMode, 'check');
end;

class function TMcpIdeBuilds.ParseEntry(const AText: string; out AEntry: TMcpIdeEntry): Boolean;
var
  Value, Item: TJSONValue;
  Root: TJSONObject;
  Items: TJSONArray;
  Pid: Int64;
begin
  AEntry := Default(TMcpIdeEntry);
  Value := TJSONObject.ParseJSONValue(AText);
  try
    Result := (Value is TJSONObject) and TJSONObject(Value).TryGetValue<Int64>('pid', Pid) and (Pid > 0);
    if not Result then
      Exit;
    Root := TJSONObject(Value);
    AEntry.Pid := Cardinal(Pid);
    AEntry.ActiveProject := Root.GetValue<string>('activeProject', '');
    if Root.TryGetValue<TJSONArray>('projects', Items) then
      for Item in Items do
        if Item is TJSONString then
          AEntry.Projects := AEntry.Projects + [TJSONString(Item).Value];
  finally
    Value.Free;
  end;
end;

function Matches(const AProjectFile, AWanted: string): Boolean;
var
  Name: string;
begin
  Name := Copy(AProjectFile, Length(TProjectPaths.DirectoryOf(AProjectFile)) + 1, MaxInt);
  if (Name <> '') and CharInSet(Name[1], ['\', '/']) then
    Delete(Name, 1, 1);
  Result := SameText(TProjectPaths.Normalize(AProjectFile), TProjectPaths.Normalize(AWanted)) or
    SameText(Name, AWanted) or SameText(TProjectPaths.BaseName(AProjectFile), AWanted) or
    SameText(TProjectPaths.BaseName(AProjectFile), TProjectPaths.BaseName(AWanted));
end;

function Inside(const ARoot, AFileName: string): Boolean;
var
  Root: string;
begin
  if ARoot = '' then
    Exit(True);
  Root := TProjectPaths.Normalize(ARoot);
  Result := SameText(Copy(TProjectPaths.Normalize(AFileName), 1, Length(Root) + 1), Root + '\') or
    SameText(Copy(TProjectPaths.Normalize(AFileName), 1, Length(Root) + 1), Root + '/');
end;

class function TMcpIdeBuilds.Pick(const AEntries: TArray<TMcpIdeEntry>; const ARoot, AProject: string;
  out APid: Cardinal; out AProjectFile, AReason: string): Boolean;
var
  Entry: TMcpIdeEntry;
  Project: string;
  Candidates: TArray<string>;
begin
  APid := 0;
  AProjectFile := '';
  AReason := '';
  if Length(AEntries) = 0 then
  begin
    AReason := 'Keine RAD-Studio-IDE mit Atlas-Plugin läuft. Ohne Kommandozeilen-Compiler baut Atlas über die ' +
      'IDE: das Projekt dort öffnen und erneut aufrufen.';
    Exit(False);
  end;
  for Entry in AEntries do
  begin
    if AProject = '' then
    begin
      if (Entry.ActiveProject <> '') and Inside(ARoot, Entry.ActiveProject) then
      begin
        APid := Entry.Pid;
        AProjectFile := Entry.ActiveProject;
        Exit(True);
      end;
      Continue;
    end;
    Candidates := Entry.Projects + [Entry.ActiveProject];
    for Project in Candidates do
      if (Project <> '') and Matches(Project, AProject) and
        (TProjectPaths.IsAbsolute(AProject) or Inside(ARoot, Project)) then
      begin
        APid := Entry.Pid;
        AProjectFile := Project;
        Exit(True);
      end;
  end;
  if AProject = '' then
    AReason := 'Keine laufende IDE mit Atlas-Plugin hat ein Projekt unter dem Arbeitsordner als aktives Projekt. ' +
      'Projekt in der IDE öffnen oder "project" angeben.'
  else
    AReason := Format('Keine laufende IDE mit Atlas-Plugin hat das Projekt %s offen. Projekt in der IDE öffnen ' +
      'und erneut aufrufen.', [AProject]);
  Result := False;
end;

class function TMcpIdeBuilds.RequestText(const ARequest: TMcpIdeBuildRequest): string;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('project', ARequest.Project);
    Json.AddPair('mode', LowerCase(ARequest.Mode));
    Json.AddPair('configuration', ARequest.Configuration);
    Json.AddPair('platform', ARequest.Platform);
    Result := Json.ToJSON;
  finally
    Json.Free;
  end;
end;

class function TMcpIdeBuilds.ParseAnswer(const AText: string; out AOk: Boolean;
  out ABuildText, AReason: string): Boolean;
var
  Value, Build: TJSONValue;
begin
  AOk := False;
  ABuildText := '';
  AReason := '';
  Value := TJSONObject.ParseJSONValue(AText);
  try
    Result := Value is TJSONObject;
    if not Result then
      Exit;
    AOk := TJSONObject(Value).GetValue<Boolean>('ok', False);
    AReason := TJSONObject(Value).GetValue<string>('reason', '');
    Build := TJSONObject(Value).GetValue('build');
    if Build is TJSONObject then
      ABuildText := Build.ToJSON;
    // Ohne Ergebnis gilt der Auftrag als abgelehnt.
    if AOk and (ABuildText = '') then
    begin
      AOk := False;
      if AReason = '' then
        AReason := 'Die IDE hat kein Ergebnis geliefert.';
    end;
  finally
    Value.Free;
  end;
end;

procedure DeleteQuietly(const AFileName: string);
begin
  try
    if FileExists(AFileName) then
      TFile.Delete(AFileName);
  except
    on Exception do
      ;
  end;
end;

class function TMcpIdeBuilds.Send(const AInbox: string; const ARequest: TMcpIdeBuildRequest; const AWait: TProc;
  const AClock: TFunc<Int64>; out ABuildText, AReason: string): TMcpIdeBuildOutcome;
begin
  Result := Send(AInbox, ARequest, AWait, AClock, TakeMs, BuildMs, ABuildText, AReason);
end;

class function TMcpIdeBuilds.Send(const AInbox: string; const ARequest: TMcpIdeBuildRequest; const AWait: TProc;
  const AClock: TFunc<Int64>; ATakeMs, ABuildMs: Int64; out ABuildText, AReason: string): TMcpIdeBuildOutcome;
var
  Id, Request, Answer, Text: string;
  Started: Int64;
  Ok: Boolean;
begin
  ABuildText := '';
  AReason := '';
  Id := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '');
  Request := TPath.Combine(AInbox, Id + '.json');
  Answer := TPath.Combine(AInbox, Id + '.result.json');
  ForceDirectories(AInbox);
  TFile.WriteAllText(Request + '.tmp', RequestText(ARequest), TEncoding.UTF8);
  TFile.Move(Request + '.tmp', Request);
  Started := AClock();
  // Warten, bis das Plugin den Auftrag übernimmt (die .json verschwindet) oder schon antwortet.
  while (AClock() - Started < ATakeMs) and FileExists(Request) and not FileExists(Answer) do
    AWait();
  if FileExists(Request) and not FileExists(Answer) and DeleteFile(Request) then
  begin
    AReason := 'Die IDE hat den Build nicht angenommen (Plugin beschäftigt, abgeschaltet oder zu alt).';
    Exit(TMcpIdeBuildOutcome.NotTaken);
  end;
  Started := AClock();
  while (AClock() - Started < ABuildMs) and not FileExists(Answer) do
    AWait();
  if not FileExists(Answer) then
  begin
    AReason := 'Die IDE hat den Build angenommen, aber nicht rechtzeitig gemeldet.';
    Exit(TMcpIdeBuildOutcome.TimedOut);
  end;
  try
    Text := TFile.ReadAllText(Answer, TEncoding.UTF8);
  except
    on Exception do
      Text := '';
  end;
  DeleteQuietly(Answer);
  if not ParseAnswer(Text, Ok, ABuildText, AReason) then
  begin
    AReason := 'Antwort der IDE nicht lesbar.';
    Exit(TMcpIdeBuildOutcome.Refused);
  end;
  if Ok then
    Result := TMcpIdeBuildOutcome.Done
  else
    Result := TMcpIdeBuildOutcome.Refused;
end;

end.
