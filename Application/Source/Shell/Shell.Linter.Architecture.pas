unit Shell.Linter.Architecture;

// Internals-Rolle Shell: --architecture (#1118). Architekturbericht des Ziels aus --check (sonst des aktuellen
// Ordners) als Markdown oder HTML nach der Endung der Datei, als .json der Stand für den Vergleich (#1121).
// Berichte vergleichen mit --compare, sonst mit architecture.baseline.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Comparison,
  Shell.CommandLine,
  Shell.Linter.Settings;

type
  /// <summary>Vergleich eines Berichts mit einem gespeicherten Stand.</summary>
  TLinterArchitectureComparison = record
    Compared: Boolean;
    Comparison: TArchitectureComparison;
    FailOn: TArchitectureFailKinds;
  end;

  TLinterArchitecture = class
  public
    /// <summary>Exit-Code 1, wenn eine Abweichung aus --fail-on (sonst architecture.failOn) vorkommt, sonst 0; bei
    /// Fehlern 3.</summary>
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>Übersicht über die Dateien des Ziels wie --check; der Index enthält nur das Projekt.</summary>
    class function OverviewOf(const ATarget: TLinterTarget; const ASettings: TServerSettings): TArchitectureOverview;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Output,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.Report,
  Atlas.Common.Architecture.Snapshot,
  Atlas.Common.Architecture.UsesLocator,
  Shell.Linter.Output,
  Shell.Linter.Files,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TLinterArchitectureText = (Report, FileKind, Off);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TLinterArchitectureText] of TAtlasText = (
    (De: 'Architekturbericht %s: %d Units, %d Teilsysteme, %d Zyklen, %d Querverbindungen';
    En: 'Architecture report %s: %d units, %d subsystems, %d cycles, %d cross links'),
    (De: '--architecture erwartet eine .md-, .html- oder .json-Datei';
    En: '--architecture expects a .md, .html or .json file'),
    (De: 'Architekturübersicht ist ausgeschaltet (architecture.enabled in settings.json)';
    En: 'Architecture overview is turned off (architecture.enabled in settings.json)'));

function ReaderFunc(): TUsesTextReader;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TLinterFiles.ReadText(AFileName, AText);
    end;
end;

function DefinesFunc(const ASources: TCheckSourceFunc): TUsesDefinesFunc;
begin
  Result :=
    function(const AFileName: string): TArray<string>
    begin
      Result := ASources(AFileName).Defines;
    end;
end;

class function TLinterArchitecture.OverviewOf(const ATarget: TLinterTarget;
  const ASettings: TServerSettings): TArchitectureOverview;
var
  mRoot: string;
  mSources: TCheckSourceFunc;
  mIndex: ISymbolIndex;
  mService: TArchitectureService;
  mRequest: TArchitectureRequest;
begin
  mIndex := TLinterFiles.IndexOf(TLinterFiles.Collect(ATarget.Target, ASettings, mRoot, mSources), mSources);
  mService := TArchitectureService.Create(mIndex, ReaderFunc(), DefinesFunc(mSources));
  try
    mRequest := TArchitectureRequest.FromSettings(ASettings);
    mRequest.Root := mRoot;
    mRequest.Title := ATarget.Title;
    // Angleichung (#1367) nur an architecture.baseline; ohne PreviousFile liest und schreibt der Lauf keinen
    // zuletzt berechneten Stand, damit CI-Läufe reproduzierbar bleiben.
    mRequest.Baseline := TArchitectureComparer.ResolvePath(ATarget.ConfigRoot, ASettings.ArchitectureBaseline);
    mRequest.PreviousFile := '';
    Result := mService.Overview(mRequest);
  finally
    mService.Free;
  end;
end;

/// <summary>Abweichungen, die zählen: --fail-on nur mit --compare, sonst architecture.failOn, sonst die Vorgabe.
/// AFailOn kommt schon aus --fail-on, wenn beides angegeben ist.</summary>
procedure ApplyFailOn(const AOptions: TCommandLineOptions; const ASettings: TServerSettings;
  var AFailOn: TArchitectureFailKinds);
var
  mError: string;
begin
  if (AOptions.CompareFile <> '') and (AOptions.FailOnText <> '') then
  begin
    Exit;
  end;
  if not TArchitectureComparer.ParseKinds(ASettings.ArchitectureFailOn, AFailOn, mError) then
  begin
    AFailOn := TArchitectureComparer.DefaultFailOn;
  end;
end;

/// <summary>Vergleich (#1121): --compare relativ zum aktuellen Ordner, sonst architecture.baseline relativ zum
/// Projekt. False, wenn --compare keinen lesbaren Stand hat; mit architecture.baseline entsteht der Bericht
/// trotzdem.</summary>
function Compare(const AOptions: TCommandLineOptions; const ATarget: TLinterTarget; const ASettings: TServerSettings;
  const AOverview: TArchitectureOverview; var AResult: TLinterArchitectureComparison): Boolean;
var
  mBaseline, mError: string;
begin
  Result := True;
  if AOptions.CompareFile <> '' then
  begin
    mBaseline := TPath.GetFullPath(AOptions.CompareFile);
  end
  else
  begin
    mBaseline := TArchitectureComparer.ResolvePath(ATarget.ConfigRoot, ASettings.ArchitectureBaseline);
  end;
  ApplyFailOn(AOptions, ASettings, AResult.FailOn);
  if mBaseline = '' then
  begin
    Exit;
  end;
  AResult.Compared := TArchitectureComparer.CompareWithFile(mBaseline, AOverview, AResult.Comparison, mError);
  if not AResult.Compared then
  begin
    TLinterOutput.Error(mError);
    Result := AOptions.CompareFile = '';
  end;
end;

/// <summary>Bericht nach der Endung von --architecture: .json als Stand, sonst Markdown oder HTML.</summary>
procedure WriteReport(const AOptions: TCommandLineOptions; const AOverview: TArchitectureOverview;
  const AComparison: TLinterArchitectureComparison);
var
  mFileName, mText: string;
begin
  mFileName := AOptions.ArchitectureFile;
  if SameText(ExtractFileExt(mFileName), '.json') then
  begin
    TArchitectureSnapshots.Save(mFileName, TArchitectureSnapshots.FromOverview(AOverview));
    Exit;
  end;
  ForceDirectories(ExtractFileDir(TPath.GetFullPath(mFileName)));
  if AComparison.Compared then
  begin
    mText := TArchitectureReport.ForFile(AOverview, mFileName, AComparison.Comparison, AComparison.FailOn);
  end
  else
  begin
    mText := TArchitectureReport.ForFile(AOverview, mFileName);
  end;
  TFile.WriteAllBytes(mFileName, TEncoding.UTF8.GetBytes(mText));
end;

/// <summary>Mit --compare der Text des Vergleichs auf stdout bzw. in --output und der Exit-Code.</summary>
function Finish(const AOptions: TCommandLineOptions; const AOverview: TArchitectureOverview;
  const AComparison: TLinterArchitectureComparison): Integer;
begin
  TLinterOutput.Error(cTexts[TLinterArchitectureText.Report].Fmt([AOptions.ArchitectureFile, Length(AOverview.Units),
    Length(AOverview.Subsystems), Length(AOverview.Cycles),
    Length(AOverview.CrossLinks)]));
  Result := TFindingsOutput.cExitClean;
  if not AComparison.Compared or (AOptions.CompareFile = '') then
  begin
    Exit;
  end;
  TLinterOutput.Write(AOptions, TArchitectureComparer.Text(AComparison.Comparison, AComparison.FailOn, 0) +
    sLineBreak);
  if AComparison.Comparison.Kinds * AComparison.FailOn <> [] then
  begin
    Result := TFindingsOutput.cExitFindings;
  end;
end;

/// <summary>Prüft die Befehlszeile: Endung des Berichts und --fail-on (nur mit --compare).</summary>
function Validate(const AOptions: TCommandLineOptions; var AComparison: TLinterArchitectureComparison): Boolean;
var
  mError: string;
begin
  Result := TLinterFiles.IsReportFile(AOptions.ArchitectureFile);
  if not Result then
  begin
    TLinterOutput.Error(cTexts[TLinterArchitectureText.FileKind].Text);
    Exit;
  end;
  AComparison.FailOn := [];
  Result := (AOptions.CompareFile = '') or (AOptions.FailOnText = '') or
    TArchitectureComparer.ParseKindList(AOptions.FailOnText, AComparison.FailOn, mError);
  if not Result then
  begin
    TLinterOutput.Error('--fail-on: ' + mError);
  end;
end;

/// <summary>Bericht und Vergleich; Exit-Code.</summary>
function Report(const AOptions: TCommandLineOptions; const ATarget: TLinterTarget;
  var AComparison: TLinterArchitectureComparison): Integer;
var
  mSettings: TServerSettings;
  mOverview: TArchitectureOverview;
begin
  mSettings := TLinterSettings.Load(ATarget.ConfigRoot);
  if not mSettings.ArchitectureEnabled then
  begin
    TLinterOutput.Error(cTexts[TLinterArchitectureText.Off].Text);
    Exit(TFindingsOutput.cExitFailure);
  end;
  TFileEncodingDefaults.SetFolder(ATarget.ConfigRoot, mSettings.DefaultEncoding);
  mOverview := TLinterArchitecture.OverviewOf(ATarget, mSettings);
  if not Compare(AOptions, ATarget, mSettings, mOverview, AComparison) then
  begin
    Exit(TFindingsOutput.cExitFailure);
  end;
  WriteReport(AOptions, mOverview, AComparison);
  Result := Finish(AOptions, mOverview, AComparison);
end;

class function TLinterArchitecture.Run(const AOptions: TCommandLineOptions): Integer;
var
  mTarget: TLinterTarget;
  mComparison: TLinterArchitectureComparison;
begin
  TLinterOutput.Warnings(AOptions);
  mComparison := Default(TLinterArchitectureComparison);
  if not Validate(AOptions, mComparison) or not TLinterTarget.ResolveOrCurrent(AOptions.CheckTarget, mTarget) then
  begin
    Exit(TFindingsOutput.cExitFailure);
  end;
  try
    Result := Report(AOptions, mTarget, mComparison);
  except
    on E: Exception do
    begin
      TLinterOutput.Error(E.Message);
      Result := TFindingsOutput.cExitFailure;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Linter.Architecture', cTexts);

end.
