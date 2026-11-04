unit Atlas.IDE.BuildPipeline.ReleaseGuard;

// Release-Build-Wächter in der IDE (#533); Entscheidung und Prüfungen in
// Atlas.Core.BuildPipeline.ReleaseGuard.
// - Optionen: aus der laufenden IDE (#396) über TAtlasIdeProjectContext für
//   die Konfiguration und Plattform des Builds, mit geerbten Werten und
//   ungespeicherten Änderungen, nicht aus der .dproj auf der Platte. Der
//   Projektquelltext (.dpr) kommt aus dem Editorpuffer, sonst von der Platte.
// - Meldungen: Atlas-Gruppe des Meldungsfensters, eine Kopfzeile, je Verstoß
//   eine Zeile „[Regel-ID] Text mit Hinweis, wo die Option zu ändern ist“;
//   ReportMemoryLeaksOnShutdown als Zeile mit Datei und Zeile (Doppelklick
//   springt hin). Bei block bricht TAtlasIdeCompileEvents den Build ab und
//   schreibt den Grund dazu.
// - Projekt-Zusammenfassung (#592, Abschnitt "release"): letzte Prüfung mit
//   Zahl der Befunde, Regel-IDs und Abbruch; Version jedes erfolgreichen
//   Release-Builds je Konfiguration und Plattform (Grundlage von
//   „unveränderte Version“, auch über Neustarts).
// - Befehl Atlas.CheckRelease: prüft das aktive Projekt ohne Build, in der
//   aktiven Konfiguration, wenn sie Release ist, sonst in „Release“ bzw. der
//   ersten Konfiguration aus build.releaseConfigs.
// Nur im Hauptthread; alles ohne Zustand, damit der Teilnehmer (gehört den
// Compile-Ereignissen) kein Objekt dieser Unit überleben muss.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Build.Events,
  Atlas.Core.BuildPipeline.ReleaseGuard;

type
  TAtlasIdeReleaseGuard = class
  public const
    MessageGroup = 'Atlas';
  public
    /// <summary>Teilnehmer für TAtlasCompileEvents.Add; AFolder ist der Ordner der Projekt-Zusammenfassungen.
    /// </summary>
    class function CreateParticipant(const AFolder: string;
      const ASettings: TAtlasReleaseSettingsFunc): TAtlasReleaseGuardParticipant; static;
    /// <summary>Optionen von AProject für AConfiguration/APlatform aus der IDE; False, wenn nicht lesbar.</summary>
    class function ReadOptions(const AProject: IOTAProject; const AConfiguration, APlatform, AFolder: string;
      out AOptions: TAtlasReleaseOptions): Boolean; static;
    /// <summary>Text eines Verstoßes mit Regel-ID und Hinweis, wo die Option zu ändern ist.</summary>
    class function FindingText(const AOptions: TAtlasReleaseOptions;
      const AFinding: TAtlasReleaseFinding): string; static;
    /// <summary>Regel-IDs der Verstöße ohne Doppelte.</summary>
    class function RulesOf(const AFindings: TAtlasReleaseFindings): TArray<string>; static;
    /// <summary>Meldungsfenster und Projekt-Zusammenfassung; liefert bei Blocked den Grund für den Abbruch.</summary>
    class function Report(const AFolder: string; const AOptions: TAtlasReleaseOptions;
      const AFindings: TAtlasReleaseFindings; AOutcome: TAtlasReleaseOutcome): string; static;
    /// <summary>Version eines erfolgreichen Release-Builds in der Projekt-Zusammenfassung merken.</summary>
    class procedure Remember(const AFolder: string; const AOptions: TAtlasReleaseOptions;
      const AVersion: string); static;
    /// <summary>Befehl Atlas.CheckRelease: aktives Projekt ohne Build prüfen.</summary>
    class procedure CheckActive(const AFolder: string; const ASettings: TAtlasReleaseSettings); static;
  end;

implementation

uses
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Projects.Contract,
  Atlas.Core.Projects.Summary,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Projects.Context,
  Atlas.UI.Strings,
  Atlas.UI.BuildPipeline.Strings;

function NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

function MessageServices(out AMessages: IOTAMessageServices; out AGroup: IOTAMessageGroup): Boolean;
begin
  AGroup := nil;
  Result := Supports(BorlandIDEServices, IOTAMessageServices, AMessages);
  if not Result then
  begin
    Exit;
  end;
  // Gruppe nicht dauerhaft halten (Hinweis in ToolsAPI); bei Bedarf neu anlegen.
  AGroup := AMessages.GetGroup(TAtlasIdeReleaseGuard.MessageGroup);
  if AGroup = nil then
  begin
    AGroup := AMessages.AddMessageGroup(TAtlasIdeReleaseGuard.MessageGroup);
  end;
end;

procedure Say(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not MessageServices(Messages, Group) then
  begin
    Exit;
  end;
  Messages.AddTitleMessage(AText, Group);
  Messages.ShowMessageView(Group);
end;

function ProjectOf(const AFileName: string): IOTAProject;
var
  Modules: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
  begin
    Supports(Modules.FindModule(AFileName), IOTAProject, Result);
  end;
end;

/// <summary>.dpr bzw. .dpk des Projekts: aus den Moduldateien, sonst neben der .dproj.</summary>
function ProjectSourceOf(const AProject: IOTAProject): string;
var
  Index: Integer;
  Name: string;
begin
  Result := '';
  try
    for Index := 0 to AProject.ModuleFileCount - 1 do
    begin
      Name := AProject.ModuleFileEditors[Index].FileName;
      if TAtlasIdeFiles.IsProjectSource(Name) then
      begin
        Exit(Name);
      end;
    end;
  except
    on Exception do
      ; // Rückfall unten.
  end;
  if FileExists(ChangeFileExt(AProject.FileName, '.dpk')) then
  begin
    Result := ChangeFileExt(AProject.FileName, '.dpk');
  end
  else if FileExists(ChangeFileExt(AProject.FileName, '.dpr')) then
  begin
    Result := ChangeFileExt(AProject.FileName, '.dpr');
  end;
end;

function SourceText(const AFileName: string): string;
var
  Buffer: IOTAEditBuffer;
begin
  Result := '';
  if AFileName = '' then
  begin
    Exit;
  end;
  Buffer := TAtlasIdeFiles.BufferOf(AFileName);
  if Buffer <> nil then
  begin
    Exit(TAtlasEditorBuffer.Text(Buffer));
  end;
  try
    if FileExists(AFileName) then
    begin
      Result := TAtlasTextFile.Load(AFileName).Text;
    end;
  except
    on Exception do
      Result := '';
  end;
end;

function LastVersion(const AFolder, AProject, AConfiguration, APlatform: string): string;
var
  Summary: TAtlasProjectSummary;
begin
  Result := '';
  if (AFolder <> '') and TAtlasProjectSummaries.Load(AFolder, AProject, Summary) then
  begin
    Result := Summary.Release.VersionOf(AConfiguration, APlatform);
  end;
end;

{ TAtlasIdeReleaseGuard }

class function TAtlasIdeReleaseGuard.CreateParticipant(const AFolder: string;
  const ASettings: TAtlasReleaseSettingsFunc): TAtlasReleaseGuardParticipant;
var
  Folder: string;
begin
  Folder := AFolder;
  Result := TAtlasReleaseGuardParticipant.Create(ASettings,
    function(const AProject: TAtlasCompileProject; out AOptions: TAtlasReleaseOptions): Boolean
    begin
      AOptions := Default(TAtlasReleaseOptions);
      Result := False;
      try
        Result := ReadOptions(ProjectOf(AProject.FileName), AProject.Configuration, AProject.Platform, Folder,
          AOptions);
      except
        // Nicht lesbar: keine Prüfung, der Build läuft (#493).
        on E: Exception do
          TAtlasGuard.Report(TAtlasFeature.Build, E);
      end;
      if not Result then
      begin
        Say(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.ReleaseUnreadable,
          [ExtractFileName(AProject.FileName)]));
      end;
    end,
    function(const AOptions: TAtlasReleaseOptions; const AFindings: TAtlasReleaseFindings;
      AOutcome: TAtlasReleaseOutcome): string
    begin
      Result := Report(Folder, AOptions, AFindings, AOutcome);
    end,
    procedure(const AOptions: TAtlasReleaseOptions; const AVersion: string)
    begin
      Remember(Folder, AOptions, AVersion);
    end, nil);
end;

class function TAtlasIdeReleaseGuard.ReadOptions(const AProject: IOTAProject; const AConfiguration, APlatform,
  AFolder: string; out AOptions: TAtlasReleaseOptions): Boolean;

  function Value(const AName: string): string;
  begin
    Result := Trim(TAtlasIdeProjectContext.ConfigurationValue(AProject, AConfiguration, APlatform, AName));
  end;

begin
  AOptions := Default(TAtlasReleaseOptions);
  Result := False;
  if (AProject = nil) or (AProject.ProjectOptions = nil) then
  begin
    Exit;
  end;
  AOptions.Project := AProject.FileName;
  AOptions.Configuration := AConfiguration;
  AOptions.Platform := APlatform;
  AOptions.Defines := TAtlasProjectContext.List(Value('DCC_Define'));
  AOptions.DebugInformation := Value('DCC_DebugInformation');
  AOptions.DebugInfoInExe := Value('DCC_DebugInfoInExe');
  AOptions.StackFrames := Value('DCC_GenerateStackFrames');
  AOptions.Assertions := Value('DCC_AssertionsAtRuntime');
  AOptions.RangeChecks := Value('DCC_RangeChecking');
  AOptions.OverflowChecks := Value('DCC_IntegerOverflowCheck');
  AOptions.IncludeVersionInfo := Value('VerInfo_IncludeVerInfo');
  AOptions.AutoIncrementVersion := Value('VerInfo_AutoGenVersion');
  if AOptions.AutoIncrementVersion = '' then
  begin
    AOptions.AutoIncrementVersion := Value('VerInfo_AutoIncVersion');
  end;
  AOptions.VersionKeys := Value('VerInfo_Keys');
  AOptions.MajorVersion := Value('VerInfo_MajorVer');
  AOptions.MinorVersion := Value('VerInfo_MinorVer');
  AOptions.ReleaseVersion := Value('VerInfo_Release');
  AOptions.BuildVersion := Value('VerInfo_Build');
  AOptions.OutputFolder := Value('DCC_ExeOutput');
  AOptions.HasDebugConfiguration := TAtlasIdeProjectContext.HasConfiguration(AProject,
    TAtlasReleaseGuard.DebugConfiguration);
  if AOptions.HasDebugConfiguration then
  begin
    AOptions.DebugOutputFolder := Trim(TAtlasIdeProjectContext.ConfigurationValue(AProject,
      TAtlasReleaseGuard.DebugConfiguration, APlatform, 'DCC_ExeOutput'));
  end;
  AOptions.SourceFile := ProjectSourceOf(AProject);
  AOptions.IsPackage := SameText(ExtractFileExt(AOptions.SourceFile), '.dpk');
  AOptions.Source := SourceText(AOptions.SourceFile);
  AOptions.LastVersion := LastVersion(AFolder, AOptions.Project, AConfiguration, APlatform);
  Result := True;
end;

class function TAtlasIdeReleaseGuard.FindingText(const AOptions: TAtlasReleaseOptions;
  const AFinding: TAtlasReleaseFinding): string;
const
  Ids: array[TAtlasReleaseIssue] of TAtlasBuildPipelineTextId = (
    TAtlasBuildPipelineTextId.ReleaseIssueDebugDefine, TAtlasBuildPipelineTextId.ReleaseIssueDebugInfo,
    TAtlasBuildPipelineTextId.ReleaseIssueDebugInfoInExe, TAtlasBuildPipelineTextId.ReleaseIssueStackFrames,
    TAtlasBuildPipelineTextId.ReleaseIssueAssertions, TAtlasBuildPipelineTextId.ReleaseIssueRangeChecks,
    TAtlasBuildPipelineTextId.ReleaseIssueOverflowChecks, TAtlasBuildPipelineTextId.ReleaseIssueMemoryLeaks,
    TAtlasBuildPipelineTextId.ReleaseIssueVersionMissing, TAtlasBuildPipelineTextId.ReleaseIssueVersionUnchanged,
    TAtlasBuildPipelineTextId.ReleaseIssueOutputFolder);
  States: array[Boolean] of TAtlasBuildPipelineTextId = (TAtlasBuildPipelineTextId.ReleaseOff,
    TAtlasBuildPipelineTextId.ReleaseOn);
var
  Id: TAtlasBuildPipelineTextId;
  Configuration, Platform, Text: string;
begin
  Id := Ids[AFinding.Issue];
  Configuration := AOptions.Configuration;
  Platform := AOptions.Platform;
  case AFinding.Issue of
    TAtlasReleaseIssue.DebugInfo, TAtlasReleaseIssue.StackFrames, TAtlasReleaseIssue.Assertions,
    TAtlasReleaseIssue.RangeChecks, TAtlasReleaseIssue.OverflowChecks:
      Text := TAtlasBuildPipelineStrings.Fmt(Id, [TAtlasBuildPipelineStrings.Text(States[not AFinding.Expected]),
        TAtlasBuildPipelineStrings.Text(States[AFinding.Expected]), Configuration, Platform]);
    TAtlasReleaseIssue.MemoryLeaks:
      Text := TAtlasBuildPipelineStrings.Text(Id);
    TAtlasReleaseIssue.VersionUnchanged, TAtlasReleaseIssue.OutputFolder:
      Text := TAtlasBuildPipelineStrings.Fmt(Id, [AFinding.Value, Configuration, Platform]);
  else
    Text := TAtlasBuildPipelineStrings.Fmt(Id, [Configuration, Platform]);
  end;
  Result := '[' + TAtlasReleaseGuard.RuleIds[AFinding.Check] + '] ' + Text;
end;

class function TAtlasIdeReleaseGuard.RulesOf(const AFindings: TAtlasReleaseFindings): TArray<string>;
var
  Finding: TAtlasReleaseFinding;
  Rule, Known: string;
  Seen: Boolean;
begin
  Result := nil;
  for Finding in AFindings do
  begin
    Rule := TAtlasReleaseGuard.RuleIds[Finding.Check];
    Seen := False;
    for Known in Result do
    begin
      if Known = Rule then
      begin
        Seen := True;
      end;
    end;
    if not Seen then
    begin
      Result := Result + [Rule];
    end;
  end;
end;

/// <summary>Projekt-Zusammenfassung (#592): letzte Prüfung, auch ohne Befund.</summary>
procedure RecordSummary(const AFolder: string; const AOptions: TAtlasReleaseOptions; ACount: Integer;
  ABlocked: Boolean; const ARules: TArray<string>);
var
  Options: TAtlasReleaseOptions;
  Stamp: TDateTime;
begin
  Options := AOptions;
  Stamp := NowUtc;
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    begin
      TAtlasProjectSummaries.Update(AFolder, Options.Project,
        procedure(var ASummary: TAtlasProjectSummary)
        begin
          ASummary.Release.Known := True;
          ASummary.Release.CheckedAt := Stamp;
          ASummary.Release.Configuration := Options.Configuration;
          ASummary.Release.Platform := Options.Platform;
          ASummary.Release.Findings := ACount;
          ASummary.Release.Blocked := ABlocked;
          ASummary.Release.Rules := ARules;
        end);
    end);
end;

/// <summary>Befunde in der Meldungsansicht; ohne Befund nichts.</summary>
procedure ShowFindings(const AOptions: TAtlasReleaseOptions; const AFindings: TAtlasReleaseFindings;
  AOutcome: TAtlasReleaseOutcome);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
  LineRef: Pointer;
  Finding: TAtlasReleaseFinding;
begin
  if (Length(AFindings) = 0) or not MessageServices(Messages, Group) then
  begin
    Exit;
  end;
  Messages.AddTitleMessage(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.ReleaseFindings,
    [Length(AFindings), ExtractFileName(AOptions.Project), AOptions.Configuration, AOptions.Platform]), Group);
  for Finding in AFindings do
  begin
    if (Finding.FileName <> '') and (Finding.Line > 0) then
    begin
      Messages.AddToolMessage(Finding.FileName, TAtlasIdeReleaseGuard.FindingText(AOptions, Finding), 'Atlas',
        Finding.Line, 1, nil, LineRef, Group);
    end
    else
    begin
      Messages.AddTitleMessage('  ' + TAtlasIdeReleaseGuard.FindingText(AOptions, Finding), Group);
    end;
  end;
  case AOutcome of
    TAtlasReleaseOutcome.Blocked:
      Messages.AddTitleMessage(TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.ReleaseBlocked), Group);
    TAtlasReleaseOutcome.Overridden:
      Messages.AddTitleMessage(TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.ReleaseOverridden), Group);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  Messages.ShowMessageView(Group);
end;

class function TAtlasIdeReleaseGuard.Report(const AFolder: string; const AOptions: TAtlasReleaseOptions;
  const AFindings: TAtlasReleaseFindings; AOutcome: TAtlasReleaseOutcome): string;
var
  Rules: TArray<string>;
  Blocked: Boolean;
begin
  Result := '';
  Rules := RulesOf(AFindings);
  Blocked := AOutcome = TAtlasReleaseOutcome.Blocked;
  if Blocked then
  begin
    Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.ReleaseBlockReason,
      [Length(AFindings)]) + ': ' + string.Join(', ', Rules);
  end;
  if AFolder <> '' then
  begin
    RecordSummary(AFolder, AOptions, Length(AFindings), Blocked, Rules);
  end;
  ShowFindings(AOptions, AFindings, AOutcome);
end;

class procedure TAtlasIdeReleaseGuard.Remember(const AFolder: string; const AOptions: TAtlasReleaseOptions;
  const AVersion: string);
var
  Options: TAtlasReleaseOptions;
  Version: string;
  Stamp: TDateTime;
begin
  if (AFolder = '') or (AVersion = '') then
  begin
    Exit;
  end;
  Options := AOptions;
  Version := AVersion;
  Stamp := NowUtc;
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    begin
      TAtlasProjectSummaries.Update(AFolder, Options.Project,
        procedure(var ASummary: TAtlasProjectSummary)
        begin
          ASummary.Release.Remember(Options.Configuration, Options.Platform, Version, Stamp);
        end);
    end);
end;

/// <summary>Konfiguration für den Befehl: aktive, wenn Release; sonst „Release“ bzw. die erste aus
/// build.releaseConfigs, die das Projekt hat; '' ohne.</summary>
function CheckConfiguration(const AProject: IOTAProject; const ASettings: TAtlasReleaseSettings): string;
var
  Name: string;
begin
  Result := AProject.CurrentConfiguration;
  if ASettings.IsRelease(Result) then
  begin
    Exit;
  end;
  for Name in TAtlasIdeProjectContext.Configurations(AProject) do
  begin
    if SameText(Name, TAtlasBuildPipelineSettings.ReleaseConfiguration) then
    begin
      Exit(Name);
    end;
  end;
  for Name in TAtlasIdeProjectContext.Configurations(AProject) do
  begin
    if ASettings.IsRelease(Name) then
    begin
      Exit(Name);
    end;
  end;
  Result := '';
end;

class procedure TAtlasIdeReleaseGuard.CheckActive(const AFolder: string; const ASettings: TAtlasReleaseSettings);
var
  Modules: IOTAModuleServices;
  Project: IOTAProject;
  Configuration: string;
  Options: TAtlasReleaseOptions;
  Findings: TAtlasReleaseFindings;
begin
  Project := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
  begin
    Project := Modules.GetActiveProject;
  end;
  if Project = nil then
  begin
    Say(TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.ReleaseNoProject));
    Exit;
  end;
  Configuration := CheckConfiguration(Project, ASettings);
  if Configuration = '' then
  begin
    Say(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.ReleaseNoConfiguration,
      [ExtractFileName(Project.FileName)]));
    Exit;
  end;
  if not ReadOptions(Project, Configuration, Project.CurrentPlatform, AFolder, Options) then
  begin
    Say(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.ReleaseUnreadable,
      [ExtractFileName(Project.FileName)]));
    Exit;
  end;
  Findings := TAtlasReleaseGuard.Evaluate(ASettings, Options);
  if Length(Findings) = 0 then
  begin
    Say(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.ReleaseClean,
      [ExtractFileName(Options.Project), Options.Configuration,
      Options.Platform]));
  end;
  Report(AFolder, Options, Findings, TAtlasReleaseOutcome.Reported);
end;

end.
