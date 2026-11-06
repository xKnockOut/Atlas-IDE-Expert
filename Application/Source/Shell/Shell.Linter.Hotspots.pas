unit Shell.Linter.Hotspots;

// Internals-Rolle Shell: --hotspots (#1354). Hotspots des Ziels aus --check (sonst des aktuellen Ordners) samt
// Methoden und Änderungskopplung als Markdown, HTML oder JSON nach der Endung der Datei.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Analysis,
  Shell.CommandLine,
  Shell.Linter.Settings;

type
  TLinterHotspots = class
  public
    /// <summary>Exit-Code 0; 3 ohne Versionsverwaltung, mit hotspots.enabled = false und bei Fehlern.</summary>
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>Analyse der Dateien des Ziels wie --check; der Index enthält nur das Projekt.</summary>
    class function Analyze(const ATarget: TLinterTarget; const ASettings: TServerSettings;
      const AVcs: IHotspotVcs): THotspotResult; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Index.Contract,
  Atlas.Common.Metrics.Collector,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Output,
  Atlas.Common.Hotspots.Service,
  Atlas.Common.Hotspots.Report,
  Shell.Hotspots,
  Shell.Linter.Output,
  Shell.Linter.Files,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TLinterHotspotsText = (Report, Off, NoVcs, FileKind);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TLinterHotspotsText] of TAtlasText = (
    (De: 'Hotspot-Bericht %s: %s, %d Units, %d Methoden, %d Kopplungen';
    En: 'Hotspot report %s: %s, %d units, %d methods, %d couplings'),
    (De: 'Hotspots sind ausgeschaltet (hotspots.enabled in settings.json)';
    En: 'Hotspots are turned off (hotspots.enabled in settings.json)'),
    (De: 'Hotspots brauchen eine Versionsverwaltung: %s'; En: 'Hotspots need version control: %s'),
    (De: '--hotspots erwartet eine .md-, .html- oder .json-Datei';
    En: '--hotspots expects a .md, .html or .json file'));

function ReaderFunc(): TMetricsReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TLinterFiles.ReadText(AFileName, AText);
    end;
end;

class function TLinterHotspots.Analyze(const ATarget: TLinterTarget; const ASettings: TServerSettings;
  const AVcs: IHotspotVcs): THotspotResult;
var
  mRoot: string;
  mSources: TCheckSourceFunc;
  mIndex: ISymbolIndex;
  mService: THotspotService;
  mRequest: THotspotRequest;
begin
  mIndex := TLinterFiles.IndexOf(TLinterFiles.Collect(ATarget.Target, ASettings, mRoot, mSources), mSources);
  mService := THotspotService.Create(mIndex, ReaderFunc());
  try
    mRequest := THotspotRequest.FromSettings(ASettings);
    // Der Bericht zeigt beide Tabellen: Units und die Methoden der obersten Kandidaten.
    mRequest.Level := THotspotLevel.Methods;
    mRequest.Root := mRoot;
    mRequest.Title := ATarget.Title;
    Result := mService.Analyze(mRequest, AVcs);
  finally
    mService.Free;
  end;
end;

/// <summary>Schreibt den Bericht nach --hotspots und meldet ihn auf stderr.</summary>
procedure WriteReport(const AOptions: TCommandLineOptions; const AResult: THotspotResult);
begin
  ForceDirectories(ExtractFileDir(TPath.GetFullPath(AOptions.HotspotsFile)));
  TFile.WriteAllBytes(AOptions.HotspotsFile, TEncoding.UTF8.GetBytes(THotspotReport.ForFile(AResult,
    AOptions.HotspotsFile)));
  TLinterOutput.Error(cTexts[TLinterHotspotsText.Report].Fmt([AOptions.HotspotsFile,
    THotspotReport.RangeText(AResult), Length(AResult.Units), Length(AResult.Methods), Length(AResult.Coupling)]));
end;

/// <summary>Einstellungen und Versionsverwaltung prüfen, analysieren und schreiben; Exit-Code.</summary>
function Report(const AOptions: TCommandLineOptions; const ATarget: TLinterTarget): Integer;
var
  mSettings: TServerSettings;
  mVcs: IHotspotVcs;
  mError: string;
begin
  mSettings := TLinterSettings.Load(ATarget.ConfigRoot);
  if not mSettings.HotspotsEnabled then
  begin
    TLinterOutput.Error(cTexts[TLinterHotspotsText.Off].Text);
    Exit(TFindingsOutput.ExitFailure);
  end;
  if not TShellHotspotVcs.Detect(ATarget.ConfigRoot, mSettings, mVcs, mError) then
  begin
    TLinterOutput.Error(cTexts[TLinterHotspotsText.NoVcs].Fmt([mError]));
    Exit(TFindingsOutput.ExitFailure);
  end;
  TFileEncodingDefaults.SetFolder(ATarget.ConfigRoot, mSettings.DefaultEncoding);
  WriteReport(AOptions, TLinterHotspots.Analyze(ATarget, mSettings, mVcs));
  Result := TFindingsOutput.ExitClean;
end;

class function TLinterHotspots.Run(const AOptions: TCommandLineOptions): Integer;
var
  mTarget: TLinterTarget;
begin
  TLinterOutput.Warnings(AOptions);
  if not TLinterFiles.IsReportFile(AOptions.HotspotsFile) then
  begin
    TLinterOutput.Error(cTexts[TLinterHotspotsText.FileKind].Text);
    Exit(TFindingsOutput.ExitFailure);
  end;
  if not TLinterTarget.ResolveOrCurrent(AOptions.CheckTarget, mTarget) then
  begin
    Exit(TFindingsOutput.ExitFailure);
  end;
  try
    Result := Report(AOptions, mTarget);
  except
    on E: Exception do
    begin
      TLinterOutput.Error(E.Message);
      Result := TFindingsOutput.ExitFailure;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Linter.Hotspots', cTexts);

end.
