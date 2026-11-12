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
  Atlas.Core.BuildPipeline.ReleaseGuard;

type
  TAtlasIdeReleaseGuard = class
  public const
    cMessageGroup = 'Atlas';
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
  Atlas.Core.Build.Events,
  Atlas.Core.Build.PipelineSettings,
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
  AGroup := AMessages.GetGroup(TAtlasIdeReleaseGuard.cMessageGroup);
  if AGroup = nil then
  begin
    AGroup := AMessages.AddMessageGroup(TAtlasIdeReleaseGuard.cMessageGroup);
  end;
end;

procedure Say(const AText: string);
var
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
begin
  if not MessageServices(mMessages, mGroup) then
  begin
    Exit;
  end;
  mMessages.AddTitleMessage(AText, mGroup);
  mMessages.ShowMessageView(mGroup);
end;

function ProjectOf(const AFileName: string): IOTAProject;
var
  mModules: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Supports(mModules.FindModule(AFileName), IOTAProject, Result);
  end;
end;

/// <summary>.dpr bzw. .dpk des Projekts: aus den Moduldateien, sonst neben der .dproj.</summary>
function ProjectSourceOf(const AProject: IOTAProject): string;
var
  mIndex: Integer;
  mName: string;
begin
  Result := '';
  try
    for mIndex := 0 to AProject.ModuleFileCount - 1 do
    begin
      mName := AProject.ModuleFileEditors[mIndex].FileName;
      if TAtlasIdeFiles.IsProjectSource(mName) then
      begin
        Exit(mName);
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
  mBuffer: IOTAEditBuffer;
begin
  Result := '';
  if AFileName = '' then
  begin
    Exit;
  end;
  mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
  if mBuffer <> nil then
  begin
    Exit(TAtlasEditorBuffer.Text(mBuffer));
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
  mSummary: TAtlasProjectSummary;
begin
  Result := '';
  if (AFolder <> '') and TAtlasProjectSummaries.Load(AFolder, AProject, mSummary) then
  begin
    Result := mSummary.Release.VersionOf(AConfiguration, APlatform);
  end;
end;

{ TAtlasIdeReleaseGuard }

class function TAtlasIdeReleaseGuard.CreateParticipant(const AFolder: string;
  const ASettings: TAtlasReleaseSettingsFunc): TAtlasReleaseGuardParticipant;
var
  mFolder: string;
begin
  mFolder := AFolder;
  Result := TAtlasReleaseGuardParticipant.Create(ASettings,
    function(const AProject: TAtlasCompileProject; out AOptions: TAtlasReleaseOptions): Boolean
    begin
      AOptions := Default(TAtlasReleaseOptions);
      Result := False;
      try
        Result := ReadOptions(ProjectOf(AProject.FileName), AProject.Configuration, AProject.Platform, mFolder,
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
      Result := Report(mFolder, AOptions, AFindings, AOutcome);
    end,
    procedure(const AOptions: TAtlasReleaseOptions; const AVersion: string)
    begin
      Remember(mFolder, AOptions, AVersion);
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
    TAtlasReleaseGuard.cDebugConfiguration);
  if AOptions.HasDebugConfiguration then
  begin
    AOptions.DebugOutputFolder := Trim(TAtlasIdeProjectContext.ConfigurationValue(AProject,
      TAtlasReleaseGuard.cDebugConfiguration, APlatform, 'DCC_ExeOutput'));
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
  cIds: array[TAtlasReleaseIssue] of TAtlasBuildPipelineTextId = (
    TAtlasBuildPipelineTextId.ReleaseIssueDebugDefine, TAtlasBuildPipelineTextId.ReleaseIssueDebugInfo,
    TAtlasBuildPipelineTextId.ReleaseIssueDebugInfoInExe, TAtlasBuildPipelineTextId.ReleaseIssueStackFrames,
    TAtlasBuildPipelineTextId.ReleaseIssueAssertions, TAtlasBuildPipelineTextId.ReleaseIssueRangeChecks,
    TAtlasBuildPipelineTextId.ReleaseIssueOverflowChecks, TAtlasBuildPipelineTextId.ReleaseIssueMemoryLeaks,
    TAtlasBuildPipelineTextId.ReleaseIssueVersionMissing, TAtlasBuildPipelineTextId.ReleaseIssueVersionUnchanged,
    TAtlasBuildPipelineTextId.ReleaseIssueOutputFolder);
  cStates: array[Boolean] of TAtlasBuildPipelineTextId = (TAtlasBuildPipelineTextId.ReleaseOff,
    TAtlasBuildPipelineTextId.ReleaseOn);
var
  mId: TAtlasBuildPipelineTextId;
  mConfiguration, mPlatform, mText: string;
begin
  mId := cIds[AFinding.Issue];
  mConfiguration := AOptions.Configuration;
  mPlatform := AOptions.Platform;
  case AFinding.Issue of
    TAtlasReleaseIssue.DebugInfo, TAtlasReleaseIssue.StackFrames, TAtlasReleaseIssue.Assertions,
    TAtlasReleaseIssue.RangeChecks, TAtlasReleaseIssue.OverflowChecks:
      mText := TAtlasBuildPipelineStrings.Fmt(mId, [TAtlasBuildPipelineStrings.Text(cStates[not AFinding.Expected]),
        TAtlasBuildPipelineStrings.Text(cStates[AFinding.Expected]), mConfiguration, mPlatform]);
    TAtlasReleaseIssue.MemoryLeaks:
      mText := TAtlasBuildPipelineStrings.Text(mId);
    TAtlasReleaseIssue.VersionUnchanged, TAtlasReleaseIssue.OutputFolder:
      mText := TAtlasBuildPipelineStrings.Fmt(mId, [AFinding.Value, mConfiguration, mPlatform]);
  else
    mText := TAtlasBuildPipelineStrings.Fmt(mId, [mConfiguration, mPlatform]);
  end;
  Result := '[' + TAtlasReleaseGuard.cRuleIds[AFinding.Check] + '] ' + mText;
end;

class function TAtlasIdeReleaseGuard.RulesOf(const AFindings: TAtlasReleaseFindings): TArray<string>;
var
  mFinding: TAtlasReleaseFinding;
  mRule, mKnown: string;
  mSeen: Boolean;
begin
  Result := nil;
  for mFinding in AFindings do
  begin
    mRule := TAtlasReleaseGuard.cRuleIds[mFinding.Check];
    mSeen := False;
    for mKnown in Result do
    begin
      if mKnown = mRule then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      Result := Result + [mRule];
    end;
  end;
end;

/// <summary>Projekt-Zusammenfassung (#592): letzte Prüfung, auch ohne Befund.</summary>
procedure RecordSummary(const AFolder: string; const AOptions: TAtlasReleaseOptions; ACount: Integer;
  ABlocked: Boolean; const ARules: TArray<string>);
var
  mOptions: TAtlasReleaseOptions;
  mStamp: TDateTime;
begin
  mOptions := AOptions;
  mStamp := NowUtc;
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    begin
      TAtlasProjectSummaries.Update(AFolder, mOptions.Project,
        procedure(var ASummary: TAtlasProjectSummary)
        begin
          ASummary.Release.Known := True;
          ASummary.Release.CheckedAt := mStamp;
          ASummary.Release.Configuration := mOptions.Configuration;
          ASummary.Release.Platform := mOptions.Platform;
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
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
  mLineRef: Pointer;
  mFinding: TAtlasReleaseFinding;
begin
  if (Length(AFindings) = 0) or not MessageServices(mMessages, mGroup) then
  begin
    Exit;
  end;
  mMessages.AddTitleMessage(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.ReleaseFindings,
    [Length(AFindings), ExtractFileName(AOptions.Project), AOptions.Configuration, AOptions.Platform]), mGroup);
  for mFinding in AFindings do
  begin
    if (mFinding.FileName <> '') and (mFinding.Line > 0) then
    begin
      mMessages.AddToolMessage(mFinding.FileName, TAtlasIdeReleaseGuard.FindingText(AOptions, mFinding), 'Atlas',
        mFinding.Line, 1, nil, mLineRef, mGroup);
    end
    else
    begin
      mMessages.AddTitleMessage('  ' + TAtlasIdeReleaseGuard.FindingText(AOptions, mFinding), mGroup);
    end;
  end;
  case AOutcome of
    TAtlasReleaseOutcome.Blocked:
      mMessages.AddTitleMessage(TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.ReleaseBlocked), mGroup);
    TAtlasReleaseOutcome.Overridden:
      mMessages.AddTitleMessage(TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.ReleaseOverridden), mGroup);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  mMessages.ShowMessageView(mGroup);
end;

class function TAtlasIdeReleaseGuard.Report(const AFolder: string; const AOptions: TAtlasReleaseOptions;
  const AFindings: TAtlasReleaseFindings; AOutcome: TAtlasReleaseOutcome): string;
var
  mRules: TArray<string>;
  mBlocked: Boolean;
begin
  Result := '';
  mRules := RulesOf(AFindings);
  mBlocked := AOutcome = TAtlasReleaseOutcome.Blocked;
  if mBlocked then
  begin
    Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.ReleaseBlockReason,
      [Length(AFindings)]) + ': ' + string.Join(', ', mRules);
  end;
  if AFolder <> '' then
  begin
    RecordSummary(AFolder, AOptions, Length(AFindings), mBlocked, mRules);
  end;
  ShowFindings(AOptions, AFindings, AOutcome);
end;

class procedure TAtlasIdeReleaseGuard.Remember(const AFolder: string; const AOptions: TAtlasReleaseOptions;
  const AVersion: string);
var
  mOptions: TAtlasReleaseOptions;
  mVersion: string;
  mStamp: TDateTime;
begin
  if (AFolder = '') or (AVersion = '') then
  begin
    Exit;
  end;
  mOptions := AOptions;
  mVersion := AVersion;
  mStamp := NowUtc;
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    begin
      TAtlasProjectSummaries.Update(AFolder, mOptions.Project,
        procedure(var ASummary: TAtlasProjectSummary)
        begin
          ASummary.Release.Remember(mOptions.Configuration, mOptions.Platform, mVersion, mStamp);
        end);
    end);
end;

/// <summary>Konfiguration für den Befehl: aktive, wenn Release; sonst „Release“ bzw. die erste aus
/// build.releaseConfigs, die das Projekt hat; '' ohne.</summary>
function CheckConfiguration(const AProject: IOTAProject; const ASettings: TAtlasReleaseSettings): string;
var
  mName: string;
begin
  Result := AProject.CurrentConfiguration;
  if ASettings.IsRelease(Result) then
  begin
    Exit;
  end;
  for mName in TAtlasIdeProjectContext.Configurations(AProject) do
  begin
    if SameText(mName, TAtlasBuildPipelineSettings.cReleaseConfiguration) then
    begin
      Exit(mName);
    end;
  end;
  for mName in TAtlasIdeProjectContext.Configurations(AProject) do
  begin
    if ASettings.IsRelease(mName) then
    begin
      Exit(mName);
    end;
  end;
  Result := '';
end;

class procedure TAtlasIdeReleaseGuard.CheckActive(const AFolder: string; const ASettings: TAtlasReleaseSettings);
var
  mModules: IOTAModuleServices;
  mProject: IOTAProject;
  mConfiguration: string;
  mOptions: TAtlasReleaseOptions;
  mFindings: TAtlasReleaseFindings;
begin
  mProject := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    mProject := mModules.GetActiveProject;
  end;
  if mProject = nil then
  begin
    Say(TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.ReleaseNoProject));
    Exit;
  end;
  mConfiguration := CheckConfiguration(mProject, ASettings);
  if mConfiguration = '' then
  begin
    Say(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.ReleaseNoConfiguration,
      [ExtractFileName(mProject.FileName)]));
    Exit;
  end;
  if not ReadOptions(mProject, mConfiguration, mProject.CurrentPlatform, AFolder, mOptions) then
  begin
    Say(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.ReleaseUnreadable,
      [ExtractFileName(mProject.FileName)]));
    Exit;
  end;
  mFindings := TAtlasReleaseGuard.Evaluate(ASettings, mOptions);
  if Length(mFindings) = 0 then
  begin
    Say(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.ReleaseClean,
      [ExtractFileName(mOptions.Project), mOptions.Configuration,
      mOptions.Platform]));
  end;
  Report(AFolder, mOptions, mFindings, TAtlasReleaseOutcome.Reported);
end;

end.
