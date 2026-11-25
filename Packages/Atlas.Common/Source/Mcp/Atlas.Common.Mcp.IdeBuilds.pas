unit Atlas.Common.Mcp.IdeBuilds;

// Bauen für KI-Assistenten (MCP) über die laufende IDE (#261, Werkzeug build_project).
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
// Auftrag nicht innerhalb von TakeMs an, zieht der MCP-Server ihn zurück (Austausch in Atlas.Common.Mcp.IdeInbox).
// Welche IDE welche Projekte offen hat, steht unter "projects" und
// "activeProject" in editor-dirty-<pid>.json (TAtlasDirtyExport im Plugin).
// Gegenstück im Plugin: Atlas.Core.Assistants.BuildInbox und Atlas.IDE.Assistants.BuildInbox.
// Projekt, das in keiner IDE offen ist (#2895, auch für debug_start): PickOrOpen sucht die Projektdatei unter dem
// Arbeitsordner und lässt nach mcp.openProjects (MayOpen: fragen, immer, nie) die IDE mit dem aktiven Projekt
// unter dem Arbeitsordner (sonst die erste) sie öffnen; das Plugin öffnet sie dann zur Projektgruppe hinzu.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Common.Mcp.Confirm,
  Atlas.Common.Mcp.IdeInbox;

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

  /// <summary>mcp.openProjects (#2895): Projekt, das in keiner IDE offen ist, öffnen nach Rückfrage, immer oder nie.
  /// </summary>
  TMcpOpenProjects = (Ask, Always, Never);

  /// <summary>Darf die IDE AProjectFile öffnen? False mit Grund.</summary>
  TMcpMayOpenFunc = reference to function(const AProjectFile: string; out AReason: string): Boolean;

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
    /// <summary>Projektdatei zu AProject (voller Pfad, Dateiname oder Name ohne Endung) unter ACandidates; ein
    /// vorhandener voller Pfad gilt auch ohne Eintrag. '' ohne Treffer.</summary>
    class function ProjectOnDisk(const ACandidates: TArray<string>; const AProject: string): string; static;
    /// <summary>Wie Pick; ist AProject in keiner IDE offen, aber als Datei da (ProjectOnDisk über ACandidates, erst
    /// dann gelesen), die IDE mit dem aktiven Projekt unter ARoot (sonst die erste) und die Datei, wenn AMayOpen
    /// zustimmt (#2895). AMayOpen nil: nur Pick.</summary>
    class function PickOrOpen(const AEntries: TArray<TMcpIdeEntry>; const ARoot, AProject: string;
      const ACandidates: TFunc<TArray<string>>; const AMayOpen: TMcpMayOpenFunc; out APid: Cardinal;
      out AProjectFile, AReason: string): Boolean; static;
    /// <summary>Wert von mcp.openProjects; Unbekanntes gilt als Ask.</summary>
    class function OpenPolicyOf(const AValue: string): TMcpOpenProjects; static;
    /// <summary>Entscheidet nach APolicy, ob AProjectFile geöffnet werden darf; Ask fragt über AChoose (nil = kein
    /// Weg zum Menschen: nein). False mit Grund.</summary>
    class function MayOpen(APolicy: TMcpOpenProjects; const AProjectFile: string; const AChoose: TMcpChooseFunc;
      out AReason: string): Boolean; static;
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
      const AWaiting: TMcpIdeWaiting; out ABuildText, AReason: string): TMcpIdeBuildOutcome; overload; static;
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
    TheIDEDidNotAccept, TheIDEAcceptedTheBuild, AnswerOfTheIDENot, OpenQuestion, OpenYes, OpenNo, OpenNever,
    OpenDeclined, OpenNotAsked);

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
    (De: 'Antwort der IDE nicht lesbar.'; En: 'Answer of the IDE not readable.'),
    (De: 'Ein KI-Assistent möchte das Projekt %s in der IDE öffnen (zur Projektgruppe hinzu). Öffnen?';
     En: 'An AI assistant wants to open the project %s in the IDE (added to the project group). Open it?'),
    (De: 'Öffnen'; En: 'Open'),
    (De: 'Nicht öffnen'; En: 'Do not open'),
    (De: 'Das Projekt %s ist in keiner laufenden IDE offen, und mcp.openProjects ist "never". Projekt in der IDE ' +
      'öffnen und erneut aufrufen.';
     En: 'The project %s is not open in any running IDE, and mcp.openProjects is "never". Open the project in the ' +
      'IDE and call again.'),
    (De: 'Der Benutzer möchte das Projekt %s nicht öffnen lassen.'; En: 'The user does not want the project %s opened.'),
    (De: 'Das Projekt %s ist in keiner laufenden IDE offen, und niemand konnte gefragt werden, ob es geöffnet ' +
      'werden darf. Projekt in der IDE öffnen oder mcp.openProjects auf "always" setzen.';
     En: 'The project %s is not open in any running IDE, and nobody could be asked whether it may be opened. Open ' +
      'the project in the IDE or set mcp.openProjects to "always".'));

{ TMcpIdeBuilds }

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

class function TMcpIdeBuilds.ProjectOnDisk(const ACandidates: TArray<string>; const AProject: string): string;
var
  mCandidate: string;
begin
  Result := '';
  if AProject = '' then
  begin
    Exit;
  end;
  if TProjectPaths.IsAbsolute(AProject) and FileExists(AProject) then
  begin
    Exit(AProject);
  end;
  for mCandidate in ACandidates do
  begin
    if Matches(mCandidate, AProject) then
    begin
      Exit(mCandidate);
    end;
  end;
end;

class function TMcpIdeBuilds.PickOrOpen(const AEntries: TArray<TMcpIdeEntry>; const ARoot, AProject: string;
  const ACandidates: TFunc<TArray<string>>; const AMayOpen: TMcpMayOpenFunc; out APid: Cardinal;
  out AProjectFile, AReason: string): Boolean;
var
  mFile, mActive, mIgnored: string;
begin
  Result := Pick(AEntries, ARoot, AProject, APid, AProjectFile, AReason);
  if Result or (AProject = '') or (Length(AEntries) = 0) or not Assigned(AMayOpen) then
  begin
    Exit;
  end;
  mFile := ProjectOnDisk(ACandidates(), AProject);
  if (mFile = '') or not AMayOpen(mFile, AReason) then
  begin
    Exit(False);
  end;
  // Die IDE, in der der Benutzer unter dem Arbeitsordner arbeitet; sonst die erste.
  if not Pick(AEntries, ARoot, '', APid, mActive, mIgnored) then
  begin
    APid := AEntries[0].Pid;
  end;
  AProjectFile := mFile;
  AReason := '';
  Result := True;
end;

class function TMcpIdeBuilds.OpenPolicyOf(const AValue: string): TMcpOpenProjects;
begin
  if SameText(AValue, 'always') then
  begin
    Exit(TMcpOpenProjects.Always);
  end;
  if SameText(AValue, 'never') then
  begin
    Exit(TMcpOpenProjects.Never);
  end;
  Result := TMcpOpenProjects.Ask;
end;

class function TMcpIdeBuilds.MayOpen(APolicy: TMcpOpenProjects; const AProjectFile: string;
  const AChoose: TMcpChooseFunc; out AReason: string): Boolean;
var
  mName: string;
  mChoice: Integer;
begin
  AReason := '';
  mName := ExtractFileName(AProjectFile.Replace('/', PathDelim));
  case APolicy of
    TMcpOpenProjects.Always:
      Exit(True);
    TMcpOpenProjects.Never:
      begin
        AReason := cTexts[TIdeBuildsText.OpenNever].Fmt([mName]);
        Exit(False);
      end;
  end;
  mChoice := TMcpConfirm.cNotAsked;
  if Assigned(AChoose) then
  begin
    mChoice := AChoose(cTexts[TIdeBuildsText.OpenQuestion].Fmt([mName]),
      TArray<string>.Create(cTexts[TIdeBuildsText.OpenYes].Text, cTexts[TIdeBuildsText.OpenNo].Text));
  end;
  Result := mChoice = 0;
  if Result then
  begin
    Exit;
  end;
  if mChoice = TMcpConfirm.cNotAsked then
  begin
    AReason := cTexts[TIdeBuildsText.OpenNotAsked].Fmt([mName]);
  end
  else
  begin
    AReason := cTexts[TIdeBuildsText.OpenDeclined].Fmt([mName]);
  end;
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

class function TMcpIdeBuilds.Send(const AInbox: string; const ARequest: TMcpIdeBuildRequest; const AWait: TProc;
  const AClock: TFunc<Int64>; out ABuildText, AReason: string): TMcpIdeBuildOutcome;
begin
  Result := Send(AInbox, ARequest, TMcpIdeWaiting.Make(AWait, AClock, cTakeMs, cBuildMs), ABuildText, AReason);
end;

class function TMcpIdeBuilds.Send(const AInbox: string; const ARequest: TMcpIdeBuildRequest;
  const AWaiting: TMcpIdeWaiting; out ABuildText, AReason: string): TMcpIdeBuildOutcome;
var
  mText: string;
  mOk: Boolean;
begin
  ABuildText := '';
  AReason := '';
  case TMcpIdeInbox.Exchange(AInbox, RequestText(ARequest), AWaiting, mText) of
    TMcpIdeExchangeOutcome.NotTaken:
      begin
        AReason := cTexts[TIdeBuildsText.TheIDEDidNotAccept].Text;
        Exit(TMcpIdeBuildOutcome.NotTaken);
      end;
    TMcpIdeExchangeOutcome.TimedOut:
      begin
        AReason := cTexts[TIdeBuildsText.TheIDEAcceptedTheBuild].Text;
        Exit(TMcpIdeBuildOutcome.TimedOut);
      end;
  end;
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
