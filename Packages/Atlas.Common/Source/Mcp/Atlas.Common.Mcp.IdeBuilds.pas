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
// Gegenstück im Plugin: Atlas.Core.BuildPipeline.Inbox und Atlas.IDE.BuildPipeline.Inbox.

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

  /// <summary>Warten auf das Plugin: AWait schläft kurz, Clock liefert Millisekunden, dazu die Fristen bis zur
  /// Übernahme und für den Build.</summary>
  TMcpIdeBuildWaiting = record
    Wait: TProc;
    Clock: TFunc<Int64>;
    TakeMs: Int64;
    BuildMs: Int64;
    class function Make(const AWait: TProc; const AClock: TFunc<Int64>; ATakeMs, ABuildMs: Int64):
      TMcpIdeBuildWaiting; static;
  end;

  TMcpIdeBuilds = class
  public const
    /// <summary>So lange darf das Plugin bis zur Übernahme brauchen.</summary>
    cTakeMs = 5000;
    /// <summary>Höchstdauer eines Builds nach der Übernahme.</summary>
    cBuildMs = 30 * 60 * 1000;
    cPollMs = 100;
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
    class function Send(const AInbox: string; const ARequest: TMcpIdeBuildRequest;
      const AWaiting: TMcpIdeBuildWaiting; out ABuildText, AReason: string): TMcpIdeBuildOutcome; overload; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TIdeBuildsText = (NoRADStudioIDEWith, NoRunningIDEWithThe, NoRunningIDEWithThe2, TheIDEDeliveredNoResult,
    TheIDEDidNotAccept, TheIDEAcceptedTheBuild, AnswerOfTheIDENot);

const
  cTexts: array[TIdeBuildsText] of TAtlasText = (
    (De: 'Keine RAD-Studio-IDE mit Atlas-Plugin läuft. Ohne Kommandozeilen-Compiler baut Atlas über die IDE: das ' +
      'Projekt dort öffnen und erneut aufrufen.';
     En: 'No RAD Studio IDE with the Atlas plugin is running. Without a command-line compiler Atlas builds via the ' +
      'IDE: open the project there and call again.'),
    (De: 'Keine laufende IDE mit Atlas-Plugin hat ein Projekt unter dem Arbeitsordner als aktives Projekt. Projekt ' +
      'in der IDE öffnen oder "project" angeben.';
     En: 'No running IDE with the Atlas plugin has a project below the working folder as active project. Open the ' +
      'project in the IDE or give "project".'),
    (De: 'Keine laufende IDE mit Atlas-Plugin hat das Projekt %s offen. Projekt in der IDE öffnen und erneut ' +
      'aufrufen.';
     En: 'No running IDE with the Atlas plugin has the project %s open. Open the project in the IDE and call again.'),
    (De: 'Die IDE hat kein Ergebnis geliefert.'; En: 'The IDE delivered no result.'),
    (De: 'Die IDE hat den Build nicht angenommen (Plugin beschäftigt, abgeschaltet oder zu alt).';
     En: 'The IDE did not accept the build (plugin busy, switched off or too old).'),
    (De: 'Die IDE hat den Build angenommen, aber nicht rechtzeitig gemeldet.';
     En: 'The IDE accepted the build but did not report in time.'),
    (De: 'Antwort der IDE nicht lesbar.'; En: 'Answer of the IDE not readable.'));

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
  mValue, mItem: TJSONValue;
  mRoot: TJSONObject;
  mItems: TJSONArray;
  mPid: Int64;
begin
  AEntry := Default(TMcpIdeEntry);
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    Result := (mValue is TJSONObject) and TJSONObject(mValue).TryGetValue<Int64>('pid', mPid) and (mPid > 0);
    if not Result then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    AEntry.Pid := Cardinal(mPid);
    AEntry.ActiveProject := mRoot.GetValue<string>('activeProject', '');
    if mRoot.TryGetValue<TJSONArray>('projects', mItems) then
    begin
      for mItem in mItems do
      begin
        if mItem is TJSONString then
        begin
          AEntry.Projects := AEntry.Projects + [TJSONString(mItem).Value];
        end;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

function Matches(const AProjectFile, AWanted: string): Boolean;
var
  mName: string;
begin
  mName := Copy(AProjectFile, Length(TProjectPaths.DirectoryOf(AProjectFile)) + 1, MaxInt);
  if (mName <> '') and CharInSet(mName[1], ['\', '/']) then
  begin
    Delete(mName, 1, 1);
  end;
  Result := SameText(TProjectPaths.Normalize(AProjectFile), TProjectPaths.Normalize(AWanted)) or
    SameText(mName, AWanted) or SameText(TProjectPaths.BaseName(AProjectFile), AWanted) or
    SameText(TProjectPaths.BaseName(AProjectFile), TProjectPaths.BaseName(AWanted));
end;

function Inside(const ARoot, AFileName: string): Boolean;
var
  mRoot: string;
begin
  if ARoot = '' then
  begin
    Exit(True);
  end;
  mRoot := TProjectPaths.Normalize(ARoot);
  Result := SameText(Copy(TProjectPaths.Normalize(AFileName), 1, Length(mRoot) + 1), mRoot + '\') or
    SameText(Copy(TProjectPaths.Normalize(AFileName), 1, Length(mRoot) + 1), mRoot + '/');
end;

/// <summary>Projekt aus AEntry, das zu AProject passt ('' = aktives Projekt unter ARoot); '' ohne Treffer.</summary>
function ProjectOf(const AEntry: TMcpIdeEntry; const ARoot, AProject: string): string;
var
  mProject: string;
begin
  Result := '';
  if AProject = '' then
  begin
    if (AEntry.ActiveProject <> '') and Inside(ARoot, AEntry.ActiveProject) then
    begin
      Result := AEntry.ActiveProject;
    end;
    Exit;
  end;
  for mProject in AEntry.Projects + [AEntry.ActiveProject] do
  begin
    if (mProject <> '') and Matches(mProject, AProject) and
      (TProjectPaths.IsAbsolute(AProject) or Inside(ARoot, mProject)) then
    begin
      Exit(mProject);
    end;
  end;
end;

class function TMcpIdeBuilds.Pick(const AEntries: TArray<TMcpIdeEntry>; const ARoot, AProject: string;
  out APid: Cardinal; out AProjectFile, AReason: string): Boolean;
var
  mEntry: TMcpIdeEntry;
begin
  APid := 0;
  AProjectFile := '';
  AReason := '';
  for mEntry in AEntries do
  begin
    AProjectFile := ProjectOf(mEntry, ARoot, AProject);
    if AProjectFile <> '' then
    begin
      APid := mEntry.Pid;
      Exit(True);
    end;
  end;
  if Length(AEntries) = 0 then
  begin
    AReason := cTexts[TIdeBuildsText.NoRADStudioIDEWith].Text;
  end
  else if AProject = '' then
  begin
    AReason := cTexts[TIdeBuildsText.NoRunningIDEWithThe].Text;
  end
  else
  begin
    AReason := cTexts[TIdeBuildsText.NoRunningIDEWithThe2].Fmt([AProject]);
  end;
  Result := False;
end;

class function TMcpIdeBuilds.RequestText(const ARequest: TMcpIdeBuildRequest): string;
var
  mJson: TJSONObject;
begin
  mJson := TJSONObject.Create;
  try
    mJson.AddPair('project', ARequest.Project);
    mJson.AddPair('mode', LowerCase(ARequest.Mode));
    mJson.AddPair('configuration', ARequest.Configuration);
    mJson.AddPair('platform', ARequest.Platform);
    Result := mJson.ToJSON;
  finally
    mJson.Free;
  end;
end;

class function TMcpIdeBuilds.ParseAnswer(const AText: string; out AOk: Boolean;
  out ABuildText, AReason: string): Boolean;
var
  mValue, mBuild: TJSONValue;
begin
  AOk := False;
  ABuildText := '';
  AReason := '';
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    Result := mValue is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    AOk := TJSONObject(mValue).GetValue<Boolean>('ok', False);
    AReason := TJSONObject(mValue).GetValue<string>('reason', '');
    mBuild := TJSONObject(mValue).GetValue('build');
    if mBuild is TJSONObject then
    begin
      ABuildText := mBuild.ToJSON;
    end;
    // Ohne Ergebnis gilt der Auftrag als abgelehnt.
    if AOk and (ABuildText = '') then
    begin
      AOk := False;
      if AReason = '' then
      begin
        AReason := cTexts[TIdeBuildsText.TheIDEDeliveredNoResult].Text;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

procedure DeleteQuietly(const AFileName: string);
begin
  try
    if FileExists(AFileName) then
    begin
      TFile.Delete(AFileName);
    end;
  except
    on Exception do
      ;
  end;
end;

class function TMcpIdeBuildWaiting.Make(const AWait: TProc; const AClock: TFunc<Int64>; ATakeMs,
  ABuildMs: Int64): TMcpIdeBuildWaiting;
begin
  Result.Wait := AWait;
  Result.Clock := AClock;
  Result.TakeMs := ATakeMs;
  Result.BuildMs := ABuildMs;
end;

class function TMcpIdeBuilds.Send(const AInbox: string; const ARequest: TMcpIdeBuildRequest; const AWait: TProc;
  const AClock: TFunc<Int64>; out ABuildText, AReason: string): TMcpIdeBuildOutcome;
begin
  Result := Send(AInbox, ARequest, TMcpIdeBuildWaiting.Make(AWait, AClock, cTakeMs, cBuildMs), ABuildText, AReason);
end;

class function TMcpIdeBuilds.Send(const AInbox: string; const ARequest: TMcpIdeBuildRequest;
  const AWaiting: TMcpIdeBuildWaiting; out ABuildText, AReason: string): TMcpIdeBuildOutcome;
var
  mId, mRequest, mAnswer, mText: string;
  mStarted: Int64;
  mOk: Boolean;
begin
  ABuildText := '';
  AReason := '';
  mId := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '');
  mRequest := TPath.Combine(AInbox, mId + '.json');
  mAnswer := TPath.Combine(AInbox, mId + '.result.json');
  ForceDirectories(AInbox);
  TFile.WriteAllText(mRequest + '.tmp', RequestText(ARequest), TEncoding.UTF8);
  TFile.Move(mRequest + '.tmp', mRequest);
  mStarted := AWaiting.Clock();
  // Warten, bis das Plugin den Auftrag übernimmt (die .json verschwindet) oder schon antwortet.
  while (AWaiting.Clock() - mStarted < AWaiting.TakeMs) and FileExists(mRequest) and not FileExists(mAnswer) do
  begin
    AWaiting.Wait();
  end;
  if FileExists(mRequest) and not FileExists(mAnswer) and DeleteFile(mRequest) then
  begin
    AReason := cTexts[TIdeBuildsText.TheIDEDidNotAccept].Text;
    Exit(TMcpIdeBuildOutcome.NotTaken);
  end;
  mStarted := AWaiting.Clock();
  while (AWaiting.Clock() - mStarted < AWaiting.BuildMs) and not FileExists(mAnswer) do
  begin
    AWaiting.Wait();
  end;
  if not FileExists(mAnswer) then
  begin
    AReason := cTexts[TIdeBuildsText.TheIDEAcceptedTheBuild].Text;
    Exit(TMcpIdeBuildOutcome.TimedOut);
  end;
  try
    mText := TFile.ReadAllText(mAnswer, TEncoding.UTF8);
  except
    on Exception do
      mText := '';
  end;
  DeleteQuietly(mAnswer);
  if not ParseAnswer(mText, mOk, ABuildText, AReason) then
  begin
    AReason := cTexts[TIdeBuildsText.AnswerOfTheIDENot].Text;
    Exit(TMcpIdeBuildOutcome.Refused);
  end;
  if mOk then
  begin
    Result := TMcpIdeBuildOutcome.Done;
  end
  else
  begin
    Result := TMcpIdeBuildOutcome.Refused;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.IdeBuilds', cTexts);

end.
