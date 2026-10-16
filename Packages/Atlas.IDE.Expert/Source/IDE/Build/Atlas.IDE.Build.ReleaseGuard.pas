unit Atlas.IDE.Build.ReleaseGuard;

// Release-Build-Wächter in der IDE (#533); Entscheidung und Prüfungen in
// Atlas.Core.Build.ReleaseGuard.
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
  Atlas.Core.Build.ReleaseGuard;

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
  Atlas.UI.Strings;

function NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

function MessageServices(out AMessages: IOTAMessageServices; out AGroup: IOTAMessageGroup): Boolean;
begin
  AGroup := nil;
  Result := Supports(BorlandIDEServices, IOTAMessageServices, AMessages);
  if not Result then
    Exit;
  // Gruppe nicht dauerhaft halten (Hinweis in ToolsAPI); bei Bedarf neu anlegen.
  AGroup := AMessages.GetGroup(TAtlasIdeReleaseGuard.MessageGroup);
  if AGroup = nil then
    AGroup := AMessages.AddMessageGroup(TAtlasIdeReleaseGuard.MessageGroup);
end;

procedure Say(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not MessageServices(Messages, Group) then
    Exit;
  Messages.AddTitleMessage(AText, Group);
  Messages.ShowMessageView(Group);
end;

function ProjectOf(const AFileName: string): IOTAProject;
var
  Modules: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Supports(Modules.FindModule(AFileName), IOTAProject, Result);
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
        Exit(Name);
    end;
  except
    on Exception do
      ; // Rückfall unten.
  end;
  if FileExists(ChangeFileExt(AProject.FileName, '.dpk')) then
    Result := ChangeFileExt(AProject.FileName, '.dpk')
  else if FileExists(ChangeFileExt(AProject.FileName, '.dpr')) then
    Result := ChangeFileExt(AProject.FileName, '.dpr');
end;

function SourceText(const AFileName: string): string;
var
  Buffer: IOTAEditBuffer;
begin
  Result := '';
  if AFileName = '' then
    Exit;
  Buffer := TAtlasIdeFiles.BufferOf(AFileName);
  if Buffer <> nil then
    Exit(TAtlasEditorBuffer.Text(Buffer));
  try
    if FileExists(AFileName) then
      Result := TAtlasTextFile.Load(AFileName).Text;
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
    Result := Summary.Release.VersionOf(AConfiguration, APlatform);
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
        Say(TAtlasStrings.Fmt(TAtlasTextId.ReleaseUnreadable, [ExtractFileName(AProject.FileName)]));
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
    Exit;
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
    AOptions.AutoIncrementVersion := Value('VerInfo_AutoIncVersion');
  AOptions.VersionKeys := Value('VerInfo_Keys');
  AOptions.MajorVersion := Value('VerInfo_MajorVer');
  AOptions.MinorVersion := Value('VerInfo_MinorVer');
  AOptions.ReleaseVersion := Value('VerInfo_Release');
  AOptions.BuildVersion := Value('VerInfo_Build');
  AOptions.OutputFolder := Value('DCC_ExeOutput');
  AOptions.HasDebugConfiguration := TAtlasIdeProjectContext.HasConfiguration(AProject,
    TAtlasReleaseGuard.DebugConfiguration);
  if AOptions.HasDebugConfiguration then
    AOptions.DebugOutputFolder := Trim(TAtlasIdeProjectContext.ConfigurationValue(AProject,
      TAtlasReleaseGuard.DebugConfiguration, APlatform, 'DCC_ExeOutput'));
  AOptions.SourceFile := ProjectSourceOf(AProject);
  AOptions.IsPackage := SameText(ExtractFileExt(AOptions.SourceFile), '.dpk');
  AOptions.Source := SourceText(AOptions.SourceFile);
  AOptions.LastVersion := LastVersion(AFolder, AOptions.Project, AConfiguration, APlatform);
  Result := True;
end;

class function TAtlasIdeReleaseGuard.FindingText(const AOptions: TAtlasReleaseOptions;
  const AFinding: TAtlasReleaseFinding): string;
const
  Ids: array[TAtlasReleaseIssue] of TAtlasTextId = (TAtlasTextId.ReleaseIssueDebugDefine,
    TAtlasTextId.ReleaseIssueDebugInfo, TAtlasTextId.ReleaseIssueDebugInfoInExe, TAtlasTextId.ReleaseIssueStackFrames,
    TAtlasTextId.ReleaseIssueAssertions, TAtlasTextId.ReleaseIssueRangeChecks,
    TAtlasTextId.ReleaseIssueOverflowChecks, TAtlasTextId.ReleaseIssueMemoryLeaks,
    TAtlasTextId.ReleaseIssueVersionMissing, TAtlasTextId.ReleaseIssueVersionUnchanged,
    TAtlasTextId.ReleaseIssueOutputFolder);
  States: array[Boolean] of TAtlasTextId = (TAtlasTextId.ReleaseOff, TAtlasTextId.ReleaseOn);
var
  Id: TAtlasTextId;
  Configuration, Platform, Text: string;
begin
  Id := Ids[AFinding.Issue];
  Configuration := AOptions.Configuration;
  Platform := AOptions.Platform;
  case AFinding.Issue of
    TAtlasReleaseIssue.DebugInfo, TAtlasReleaseIssue.StackFrames, TAtlasReleaseIssue.Assertions,
    TAtlasReleaseIssue.RangeChecks, TAtlasReleaseIssue.OverflowChecks:
      Text := TAtlasStrings.Fmt(Id, [TAtlasStrings.Text(States[not AFinding.Expected]),
        TAtlasStrings.Text(States[AFinding.Expected]), Configuration, Platform]);
    TAtlasReleaseIssue.MemoryLeaks:
      Text := TAtlasStrings.Text(Id);
    TAtlasReleaseIssue.VersionUnchanged, TAtlasReleaseIssue.OutputFolder:
      Text := TAtlasStrings.Fmt(Id, [AFinding.Value, Configuration, Platform]);
  else
    Text := TAtlasStrings.Fmt(Id, [Configuration, Platform]);
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
      if Known = Rule then
        Seen := True;
    if not Seen then
      Result := Result + [Rule];
  end;
end;

class function TAtlasIdeReleaseGuard.Report(const AFolder: string; const AOptions: TAtlasReleaseOptions;
  const AFindings: TAtlasReleaseFindings; AOutcome: TAtlasReleaseOutcome): string;
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
  LineRef: Pointer;
  Finding: TAtlasReleaseFinding;
  Rules: TArray<string>;
  Options: TAtlasReleaseOptions;
  Count: Integer;
  Blocked: Boolean;
  Stamp: TDateTime;
begin
  Result := '';
  Rules := RulesOf(AFindings);
  Count := Length(AFindings);
  Blocked := AOutcome = TAtlasReleaseOutcome.Blocked;
  if Blocked then
    Result := TAtlasStrings.Fmt(TAtlasTextId.ReleaseBlockReason, [Count]) + ': ' + string.Join(', ', Rules);
  // Projekt-Zusammenfassung (#592): letzte Prüfung, auch ohne Befund.
  Options := AOptions;
  Stamp := NowUtc;
  if AFolder <> '' then
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
            ASummary.Release.Findings := Count;
            ASummary.Release.Blocked := Blocked;
            ASummary.Release.Rules := Rules;
          end);
      end);
  if (Count = 0) or not MessageServices(Messages, Group) then
    Exit;
  Messages.AddTitleMessage(TAtlasStrings.Fmt(TAtlasTextId.ReleaseFindings, [Count,
    ExtractFileName(AOptions.Project), AOptions.Configuration, AOptions.Platform]), Group);
  for Finding in AFindings do
    if (Finding.FileName <> '') and (Finding.Line > 0) then
      Messages.AddToolMessage(Finding.FileName, FindingText(AOptions, Finding), 'Atlas', Finding.Line, 1, nil,
        LineRef, Group)
    else
      Messages.AddTitleMessage('  ' + FindingText(AOptions, Finding), Group);
  case AOutcome of
    TAtlasReleaseOutcome.Blocked:
      Messages.AddTitleMessage(TAtlasStrings.Text(TAtlasTextId.ReleaseBlocked), Group);
    TAtlasReleaseOutcome.Overridden:
      Messages.AddTitleMessage(TAtlasStrings.Text(TAtlasTextId.ReleaseOverridden), Group);
  end;
  Messages.ShowMessageView(Group);
end;

class procedure TAtlasIdeReleaseGuard.Remember(const AFolder: string; const AOptions: TAtlasReleaseOptions;
  const AVersion: string);
var
  Options: TAtlasReleaseOptions;
  Version: string;
  Stamp: TDateTime;
begin
  if (AFolder = '') or (AVersion = '') then
    Exit;
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
    Exit;
  for Name in TAtlasIdeProjectContext.Configurations(AProject) do
    if SameText(Name, TAtlasReleaseGuard.ReleaseConfiguration) then
      Exit(Name);
  for Name in TAtlasIdeProjectContext.Configurations(AProject) do
    if ASettings.IsRelease(Name) then
      Exit(Name);
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
    Project := Modules.GetActiveProject;
  if Project = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ReleaseNoProject));
    Exit;
  end;
  Configuration := CheckConfiguration(Project, ASettings);
  if Configuration = '' then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.ReleaseNoConfiguration, [ExtractFileName(Project.FileName)]));
    Exit;
  end;
  if not ReadOptions(Project, Configuration, Project.CurrentPlatform, AFolder, Options) then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.ReleaseUnreadable, [ExtractFileName(Project.FileName)]));
    Exit;
  end;
  Findings := TAtlasReleaseGuard.Evaluate(ASettings, Options);
  if Length(Findings) = 0 then
    Say(TAtlasStrings.Fmt(TAtlasTextId.ReleaseClean, [ExtractFileName(Options.Project), Options.Configuration,
      Options.Platform]));
  Report(AFolder, Options, Findings, TAtlasReleaseOutcome.Reported);
end;

end.
