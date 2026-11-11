unit Shell.Linter.AffectedTests;

// Internals-Rolle Shell: --affected-tests (#1353). Statt der Prüfung die DUnitX-Tests, die eine Änderung gegenüber
// der Basis betrifft; Ziel ist das Testprojekt (.dproj), die Projektgruppe (.groupproj) oder ein Ordner.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.References,
  Shell.CommandLine,
  Shell.WorkspaceGroup;

type
  TLinterAffectedTests = class
  public
    const
      /// <summary>Alle Tests nötig (eine Datei nicht zuzuordnen, Testprogramm geändert, Analyse unvollständig).
      /// </summary>
      cExitAllTests = 2;
    /// <summary>Betroffene Tests als text, json oder dunitx (--format) auf stdout bzw. in --output. Exit-Code 0;
    /// 2, wenn alle Tests nötig sind; 3 bei Fehlern oder mit tests.affected = false.</summary>
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>Testprogramme: das Ziel bzw. die Projekte der Gruppe, sonst testUnits.project, sonst alle
    /// DUnitX-Programme unter AAllFiles.</summary>
    class function ProgramsOf(const ATarget, AConfigRoot: string; const ASettings: TServerSettings;
      const AAllFiles: TArray<string>; const AReadText: TReferenceReadText): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Diagnostics.CheckProfile,
  Atlas.Common.Rules.Output,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.AffectedTests,
  Shell.Platform,
  Shell.Bootstrap,
  Shell.AffectedTests,
  Shell.Linter.Output,
  Shell.Linter.Settings,
  Shell.Linter.Files,
  Shell.Linter.Index,
  Atlas.Common.Localization.Texts;

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
  for mProject in TShellBootstrap.LoadGroup(TPath.GetFullPath(AGroupFile), nil) do
  begin
    Result := Result + [TLinterFiles.MainSourceOf(mProject, ASettings)];
  end;
end;

class function TLinterAffectedTests.ProgramsOf(const ATarget, AConfigRoot: string; const ASettings: TServerSettings;
  const AAllFiles: TArray<string>; const AReadText: TReferenceReadText): TArray<string>;
begin
  if SameText(ExtractFileExt(ATarget), '.dproj') then
  begin
    Result := TArray<string>.Create(TLinterFiles.MainSourceOf(ATarget, ASettings));
  end
  else if SameText(ExtractFileExt(ATarget), '.groupproj') then
  begin
    Result := TShellAffectedTests.TestPrograms(GroupPrograms(ATarget, ASettings), AReadText);
  end
  else if ASettings.TestUnits.Project <> '' then
  begin
    Result := TArray<string>.Create(ChangeFileExt(TPath.GetFullPath(TPath.Combine(AConfigRoot,
      ASettings.TestUnits.Project)), '.dpr'));
  end
  else
  begin
    Result := TShellAffectedTests.TestPrograms(AAllFiles, AReadText);
  end;
end;

function ReadTextFunc(): TReferenceReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TShellBootstrap.ReadSourceText(AFileName, AText);
    end;
end;

/// <summary>Typisierte Variable: TNameResolver.Create ist überladen.</summary>
function EnsureUnitFunc(AGroup: TShellWorkspaceGroup): TEnsureUnitFunc;
begin
  Result :=
    function(const AUnitName: string): Boolean
    begin
      Result := AGroup.EnsureUnit(AUnitName);
    end;
end;

/// <summary>Auftrag der Analyse: Dateien der Gruppe, Testprogramme und der Testbereich.</summary>
function RequestOf(AGroup: TShellWorkspaceGroup; const ASettings: TServerSettings; const APrograms: TArray<string>;
  const AReadText: TReferenceReadText): TAffectedRequest;
begin
  Result := Default(TAffectedRequest);
  Result.Files := AGroup.AllFiles;
  Result.TestPrograms := APrograms;
  Result.Options := TImpactOptions.Default;
  Result.Options.References := ASettings.References;
  Result.Options.Tests := TShellAffectedTests.TestScope(ASettings.TestUnits.Pattern, APrograms, AReadText);
end;

/// <summary>Analyse über den Index von AGroup gegenüber --affected-base.</summary>
function Analyze(const AOptions: TCommandLineOptions; const ATarget: TLinterTarget; const ASettings: TServerSettings;
  AGroup: TShellWorkspaceGroup): TAffectedResult;
var
  mReadText: TReferenceReadText;
  mQuery: TShellAffectedQuery;
  mProcess: ICompilerProcess;
  mResolver: TNameResolver;
  mRequest: TAffectedRequest;
begin
  mReadText := ReadTextFunc();
  mRequest := RequestOf(AGroup, ASettings, TLinterAffectedTests.ProgramsOf(ATarget.Target, ATarget.ConfigRoot,
    ASettings, AGroup.AllFiles, mReadText), mReadText);
  mQuery := Default(TShellAffectedQuery);
  mQuery.WorkingDir := ATarget.ConfigRoot;
  mQuery.Base := AOptions.AffectedBase;
  mQuery.IncludeUncommitted := AOptions.IncludeUncommitted;
  // Über eine Variable halten: Detect gibt einen Probelauf frei, bevor es den nächsten startet.
  mProcess := TProcessRunner.Create;
  mResolver := TNameResolver.Create(AGroup.Index, EnsureUnitFunc(AGroup));
  try
    mResolver.Namespaces := AGroup.Main.State.Namespaces;
    Result := TShellAffectedTests.Run(mProcess, ASettings, mQuery,
      TShellAffectedSources.New(mResolver, AGroup.Index, mReadText), mRequest, nil);
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
  if (AFormat = TAffectedFormat.DUnitX) and not TAffectedTests.DUnitXArgument(AFound, mArgument) then
  begin
    // Zu viele Namen für eine Befehlszeile: dann ohne --run alle.
    AFound.All := True;
    AFound.AllReason := TShellAffectedTests.TooManyForRun;
  end;
  mOutput := TAffectedTests.Render(AFound, AFormat);
  if AFormat = TAffectedFormat.DUnitX then
  begin
    TLinterOutput.Error(TrimRight(TAffectedTests.ToText(AFound)));
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
function Report(const AOptions: TCommandLineOptions; const ATarget: TLinterTarget; AFormat: TAffectedFormat):
  Integer;
var
  mSettings: TServerSettings;
  mGroup: TShellWorkspaceGroup;
  mTimings: TCheckTimings;
  mFound: TAffectedResult;
begin
  mSettings := TLinterSettings.Load(ATarget.ConfigRoot);
  if not mSettings.Tests.Affected then
  begin
    TLinterOutput.Error(cTexts[TLinterAffectedText.TurnOn].Fmt([TShellAffectedTests.OffMessage]));
    Exit(TFindingsOutput.cExitFailure);
  end;
  TFileEncodingDefaults.SetFolder(ATarget.ConfigRoot, mSettings.DefaultEncoding);
  // Zeiten nur für --timings beim Prüfen; hier unbenutzt.
  mTimings := Default(TCheckTimings);
  mGroup := TLinterIndex.Load(AOptions, ATarget.ConfigRoot, mTimings);
  try
    mFound := Analyze(AOptions, ATarget, mSettings, mGroup);
    Result := Finish(AOptions, mFound, AFormat);
  finally
    TLinterIndex.Release(mGroup);
  end;
end;

class function TLinterAffectedTests.Run(const AOptions: TCommandLineOptions): Integer;
var
  mFormat: TAffectedFormat;
  mTarget: TLinterTarget;
begin
  TLinterOutput.Warnings(AOptions);
  if not TAffectedTests.TryParseFormat(AOptions.FormatText, mFormat) then
  begin
    TLinterOutput.Error(cTexts[TLinterAffectedText.FormatInvalid].Fmt([AOptions.FormatText]));
    Exit(TFindingsOutput.cExitFailure);
  end;
  if not TLinterTarget.ResolveOrCurrent(AOptions.CheckTarget, mTarget) then
  begin
    Exit(TFindingsOutput.cExitFailure);
  end;
  try
    Result := Report(AOptions, mTarget, mFormat);
  except
    on E: Exception do
    begin
      TLinterOutput.Error(E.Message);
      Result := TFindingsOutput.cExitFailure;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Linter.AffectedTests', cTexts);

end.
