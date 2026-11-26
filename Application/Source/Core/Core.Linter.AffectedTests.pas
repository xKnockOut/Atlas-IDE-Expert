unit Core.Linter.AffectedTests;

// Host-Rolle Core: --affected-tests (#1353). Statt der Prüfung die DUnitX-Tests, die eine Änderung gegenüber
// der Basis betrifft; Ziel ist das Testprojekt (.dproj), die Projektgruppe (.groupproj) oder ein Ordner.

interface

uses
  Atlas.Common.Configuration.Contract,
  Core.CommandLine,
  Core.Linter.Host,
  Atlas.Common.Semantics.References;

type
  TLinterAffectedTests = class
  public
    const
      /// <summary>Alle Tests nötig (eine Datei nicht zuzuordnen, Testprogramm geändert, Analyse unvollständig).
      /// </summary>
      cExitAllTests = 2;
    /// <summary>Betroffene Tests als text, json oder dunitx (--format) auf stdout bzw. in --output. Exit-Code 0;
    /// 2, wenn alle Tests nötig sind; 3 bei Fehlern oder mit tests.affected = false.</summary>
    class function Run(const AOptions: TCommandLineOptions; const AHost: TCoreLinterHost): Integer; static;
    /// <summary>Testprogramme: das Ziel bzw. die Projekte der Gruppe, sonst testUnits.project, sonst alle
    /// DUnitX-Programme unter AAllFiles.</summary>
    class function ProgramsOf(const ATarget, AConfigRoot: string; const ASettings: TServerSettings;
      const AAllFiles: TArray<string>; const AReadText: TReferenceReadText): TArray<string>; static;
  end;

implementation

uses
  Core.WorkspaceGroup,
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Diagnostics.CheckProfile,
  Atlas.Common.Findings.Output,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.Impact,
  Atlas.Common.Testing.AffectedTests.Report,
  Atlas.Common.Testing.AffectedTests.Types,
  Core.Bootstrap,
  Core.AffectedTests,
  Core.Linter.Output,
  Core.Linter.Settings,
  Core.Linter.Files,
  Core.Linter.Index,
  Atlas.Common.Localization.Texts,
  Core.VersionControlChanges;

type
{$SCOPEDENUMS ON}
  TLinterAffectedText = (TurnOn, FormatInvalid);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TLinterAffectedText] of TAtlasText = (
    (De: '%s; einschalten mit "tests": {"affected": true}'; En: '%s; turn on with "tests": {"affected": true}'),
    (De: '--affected-tests kennt --format text, json und dunitx, nicht "%s"';
    En: '--affected-tests knows --format text, json and dunitx, not "%s"'));

/// <summary>Hauptdateien der Projekte der Gruppe AGroupFile.</summary>
function GroupPrograms(const AGroupFile: string; const ASettings: TServerSettings): TArray<string>;
var
  mProject: string;
begin
  Result := nil;
  for mProject in TCoreBootstrap.LoadGroup(TPath.GetFullPath(AGroupFile), nil) do
  begin
    Result := Result + [TLinterFiles.MainSourceOf(mProject, ASettings)];
  end;
end;

{ TLinterAffectedTests }

class function TLinterAffectedTests.ProgramsOf(const ATarget, AConfigRoot: string; const ASettings: TServerSettings;
  const AAllFiles: TArray<string>; const AReadText: TReferenceReadText): TArray<string>;
begin
  if SameText(ExtractFileExt(ATarget), '.dproj') then
  begin
    Result := TArray<string>.Create(TLinterFiles.MainSourceOf(ATarget, ASettings));
  end
  else if SameText(ExtractFileExt(ATarget), '.groupproj') then
  begin
    Result := TCoreAffectedTests.TestPrograms(GroupPrograms(ATarget, ASettings), AReadText);
  end
  else if ASettings.TestUnits.Project <> '' then
  begin
    Result := TArray<string>.Create(ChangeFileExt(TPath.GetFullPath(TPath.Combine(AConfigRoot,
      ASettings.TestUnits.Project)), '.dpr'));
  end
  else
  begin
    Result := TCoreAffectedTests.TestPrograms(AAllFiles, AReadText);
  end;
end;

/// <summary>Auftrag der Analyse: Dateien der Gruppe, Testprogramme und der Testbereich.</summary>
function RequestOf(AGroup: TCoreWorkspaceGroup; const ASettings: TServerSettings; const APrograms: TArray<string>;
  const AReadText: TReferenceReadText): TAffectedRequest;
begin
  Result := Default(TAffectedRequest);
  Result.Files := AGroup.AllFiles;
  Result.TestPrograms := APrograms;
  Result.Options := TImpactOptions.Default;
  Result.Options.References := ASettings.References;
  Result.Options.Tests := TCoreAffectedTests.TestScope(ASettings.TestUnits.Pattern, APrograms, AReadText);
end;

/// <summary>Analyse über den Index von AGroup gegenüber --affected-base.</summary>
function Analyze(const AOptions: TCommandLineOptions; const ATarget: TLinterTarget; const ASettings: TServerSettings;
  AGroup: TCoreWorkspaceGroup; const AHost: TCoreLinterHost): TAffectedResult;
var
  mReadText: TReferenceReadText;
  mQuery: TCoreAffectedQuery;
  mAccess: TCoreVcsAccess;
  mResolver: TNameResolver;
  mRequest: TAffectedRequest;
begin
  mReadText := TCoreAffectedTests.FileReader();
  mRequest := RequestOf(AGroup, ASettings, TLinterAffectedTests.ProgramsOf(ATarget.Target, ATarget.ConfigRoot,
    ASettings, AGroup.AllFiles, mReadText), mReadText);
  mQuery := Default(TCoreAffectedQuery);
  mQuery.WorkingDir := ATarget.ConfigRoot;
  mQuery.Base := AOptions.AffectedBase;
  mQuery.IncludeUncommitted := AOptions.IncludeUncommitted;
  // Über eine Variable halten: Detect gibt einen Probelauf frei, bevor es den nächsten startet.
  mAccess := AHost.Vcs();
  mResolver := TNameResolver.Create(AGroup.Index, AGroup.UnitLoader());
  try
    mResolver.Namespaces := AGroup.Main.State.Namespaces;
    Result := TCoreAffectedTests.Run(mAccess, ASettings, mQuery,
      TCoreAffectedSources.New(mResolver, AGroup.Index, mReadText), mRequest, nil);
  finally
    mResolver.Free;
  end;
end;

/// <summary>Ausgabe und Exit-Code. Mit dunitx auf stdout nur das Argument; der Bericht mit Gründen für Menschen
/// auf stderr (pre-commit-Hook, CI-Protokoll).</summary>
function Finish(const AOptions: TCommandLineOptions; var AFound: TAffectedResult; AFormat: TAffectedFormat): Integer;
var
  mOutput, mArgument: string;
begin
  if (AFormat = TAffectedFormat.DUnitX) and not TAffectedReport.DUnitXArgument(AFound, mArgument) then
  begin
    // Zu viele Namen für eine Befehlszeile: dann ohne --run alle.
    AFound.All := True;
    AFound.AllReason := TCoreAffectedTests.TooManyForRun;
  end;
  mOutput := TAffectedReport.Render(AFound, AFormat);
  if AFormat = TAffectedFormat.DUnitX then
  begin
    TLinterOutput.Error(TrimRight(TAffectedReport.ToText(AFound)));
    if mOutput <> '' then
    begin
      mOutput := mOutput + sLineBreak;
    end;
  end;
  TLinterOutput.Write(AOptions, mOutput);
  Result := TFindingsOutput.cExitClean;
  if AFound.All then
  begin
    Result := TLinterAffectedTests.cExitAllTests;
  end;
end;

/// <summary>Einstellungen, Index und Analyse; Exit-Code.</summary>
function Report(const AOptions: TCommandLineOptions; const ATarget: TLinterTarget; AFormat: TAffectedFormat;
  const AHost: TCoreLinterHost): Integer;
var
  mSettings: TServerSettings;
  mGroup: TCoreWorkspaceGroup;
  mTimings: TCheckTimings;
  mFound: TAffectedResult;
begin
  mSettings := TLinterSettings.Load(ATarget.ConfigRoot);
  if not mSettings.Tests.Affected then
  begin
    TLinterOutput.Error(cTexts[TLinterAffectedText.TurnOn].Fmt([TCoreAffectedTests.OffMessage]));
    Exit(TFindingsOutput.cExitFailure);
  end;
  TFileEncodingDefaults.SetFolder(ATarget.ConfigRoot, mSettings.DefaultEncoding);
  // Zeiten nur für --timings beim Prüfen; hier unbenutzt.
  mTimings := Default(TCheckTimings);
  mGroup := TLinterIndex.Load(AOptions, ATarget.ConfigRoot, mTimings, nil, AHost);
  try
    mFound := Analyze(AOptions, ATarget, mSettings, mGroup, AHost);
    Result := Finish(AOptions, mFound, AFormat);
  finally
    TLinterIndex.Release(mGroup);
  end;
end;

class function TLinterAffectedTests.Run(const AOptions: TCommandLineOptions; const AHost: TCoreLinterHost):
  Integer;
var
  mFormat: TAffectedFormat;
  mTarget: TLinterTarget;
begin
  TLinterOutput.Warnings(AOptions);
  if not TAffectedReport.TryParseFormat(AOptions.FormatText, mFormat) then
  begin
    TLinterOutput.Error(cTexts[TLinterAffectedText.FormatInvalid].Fmt([AOptions.FormatText]));
    Exit(TFindingsOutput.cExitFailure);
  end;
  if not TLinterTarget.ResolveOrCurrent(AOptions.CheckTarget, mTarget) then
  begin
    Exit(TFindingsOutput.cExitFailure);
  end;
  try
    Result := Report(AOptions, mTarget, mFormat, AHost);
  except
    on E: Exception do
    begin
      TLinterOutput.Error(E.Message);
      Result := TFindingsOutput.cExitFailure;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Core.Linter.AffectedTests', cTexts);

end.
