unit Shell.Linter.Index;

// Internals-Rolle Shell: Symbolindex des Linter-Modus (#1112). Wie im Server und im MCP-Modus baut --check den
// Index des Projekts (Ordner, .dproj oder Ordner der Datei, mit index.projectGroup die ganze Gruppe) und liest
// dabei den gemeinsamen Index-Cache (--index-cache, sonst der Ordner des Servers).

interface

uses
  Atlas.Common.Projects.PackageReader,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Diagnostics.CheckProfile,
  Shell.CommandLine,
  Shell.WorkspaceGroup;

type
  TLinterIndex = class
  public
    const
      /// <summary>Höchstens so lange auf den Index warten; danach mit dem bis dahin aufgebauten prüfen.</summary>
      cTimeoutMs = 30 * 60 * 1000;
    /// <summary>Arbeitsbereiche mit Symbolindex, wie im MCP-Modus; wartet auf den Index und trägt Aufbauzeit und
    /// Speicher in ATimings ein (#1356).</summary>
    class function Load(const AOptions: TCommandLineOptions; const AConfigRoot: string;
      var ATimings: TCheckTimings): TShellWorkspaceGroup; static;
    /// <summary>Projekt einer geprüften Datei: Package aus APackages, Formulare der Programme, Formulardatei
    /// daneben und mit AGroup Index und Projektdienste (#1112) wie im Server.</summary>
    class function ProjectOf(const AFileName: string; const APackages: TArray<TPackageSource>;
      const APrograms: TArray<string>; AGroup: TShellWorkspaceGroup): TCheckProject; static;
    /// <summary>Hält AGroup an und gibt sie frei; nil erlaubt.</summary>
    class procedure Release(AGroup: TShellWorkspaceGroup); static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Diagnostics,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.FormFields,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Processes,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Logging.Providers.StreamSink,
  Shell.Platform,
  Shell.Bootstrap,
  Shell.Linter.Output,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TLinterIndexText = (NotReady, NoProject, Ready);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TLinterIndexText] of TAtlasText = (
    (De: 'Symbolindex nach %d Minuten nicht fertig; Prüfung mit dem bisher aufgebauten Index';
    En: 'Symbol index not ready after %d minutes; checking with the index built so far'),
    (De: 'Kein Projekt gefunden; Prüfung ohne Symbolindex'; En: 'No project found; checking without symbol index'),
    (De: 'Symbolindex: %d Units in %.1f s'; En: 'Symbol index: %d units in %.1f s'));

/// <summary>Logger nur für Warnungen und Fehler auf stderr; stdout gehört dem Ergebnis.</summary>
function ErrorLogger: ILogger;
var
  mLogger: TLogger;
begin
  mLogger := TLogger.Create;
  Result := mLogger;
  mLogger.AddSink(TStreamLogSink.Create(TStdStreams.CreateError, True), TLogLevel.Warning);
end;

/// <summary>Gruppe über AConfigRoot mit AIndex. Als anonyme Methode statt TShellBootstrap.ReadSourceText: Free
/// Pascal (Linux-Bau) bricht an der Umwandlung einer Klassenmethode in eine Methodenreferenz intern ab.</summary>
function NewGroup(const AConfigRoot: string; const AIndex: ISymbolIndex): TShellWorkspaceGroup;
var
  mStore: IDocumentStore;
begin
  mStore := TDocumentStore.Create(
    function(const APath: string): string
    begin
      Result := TShellPlatform.CanonicalizePath(APath);
    end);
  Result := TShellWorkspaceGroup.Create(ExcludeTrailingPathDelimiter(AConfigRoot), mStore, ErrorLogger, AIndex,
    'atlas-check-index',
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TShellBootstrap.ReadSourceText(AFileName, AText);
    end);
end;

/// <summary>Projektdatei, Cache-Ordner und Anmeldung am Index-Cache für „Prozesse am Projekt“ (#62).</summary>
procedure Configure(AGroup: TShellWorkspaceGroup; const AOptions: TCommandLineOptions);
var
  mIdentity: TIndexProcessInfo;
begin
  if SameText(ExtractFileExt(AOptions.CheckTarget), '.dproj') then
  begin
    AGroup.Main.Setup.ProjectFile := TPath.GetFullPath(AOptions.CheckTarget);
  end;
  if AOptions.IndexCacheFolder <> '' then
  begin
    AGroup.CacheRoot := ExcludeTrailingPathDelimiter(TPath.GetFullPath(AOptions.IndexCacheFolder));
  end;
  mIdentity := Default(TIndexProcessInfo);
  mIdentity.Pid := TShellPlatform.CurrentProcessId;
  mIdentity.Kind := TIndexProcessInfo.cKindCheck;
  mIdentity.Client := 'atlas --check';
  AGroup.ProcessIdentity := mIdentity;
end;

/// <summary>Lädt AGroup, wartet auf den Index und meldet das Ergebnis auf stderr.</summary>
procedure LoadAndWait(AGroup: TShellWorkspaceGroup; const AIndex: ISymbolIndex; const AWatch: TStopwatch);
begin
  AGroup.Load(TShellBootstrap.LoadGlobalSettings(nil));
  if not AGroup.WaitForIndex(TLinterIndex.cTimeoutMs) then
  begin
    TLinterOutput.Error(cTexts[TLinterIndexText.NotReady].Fmt([TLinterIndex.cTimeoutMs div 60000]));
  end
  else if AIndex.UnitCount = 0 then
  begin
    TLinterOutput.Error(cTexts[TLinterIndexText.NoProject].Text);
  end
  else
  begin
    // Anzeige für Menschen auf stderr: Dezimaltrenner des Gebietsschemas.
    TLinterOutput.Error(Format(cTexts[TLinterIndexText.Ready].Text, [AIndex.UnitCount,
      AWatch.ElapsedMilliseconds / 1000], FormatSettings));
  end;
end;

/// <summary>Zeitprofil (#1356): Aufbau und Speicher des Index.</summary>
procedure RecordTimings(const AIndex: ISymbolIndex; const AWatch: TStopwatch; var ATimings: TCheckTimings);
begin
  ATimings.IndexMs := AWatch.ElapsedMilliseconds;
  ATimings.IndexUnits := AIndex.UnitCount;
  ATimings.ProjectBytes := AIndex.MemoryParts.ProjectBytes;
  ATimings.LibraryBytes := AIndex.MemoryParts.LibraryBytes;
  ATimings.UsageBytes := AIndex.MemoryParts.UsageBytes;
end;

class function TLinterIndex.Load(const AOptions: TCommandLineOptions; const AConfigRoot: string;
  var ATimings: TCheckTimings): TShellWorkspaceGroup;
var
  mIndex: ISymbolIndex;
  mWatch: TStopwatch;
begin
  mIndex := TSymbolIndex.Create;
  Result := NewGroup(AConfigRoot, mIndex);
  try
    Configure(Result, AOptions);
    mWatch := TStopwatch.StartNew;
    LoadAndWait(Result, mIndex, mWatch);
    RecordTimings(mIndex, mWatch, ATimings);
  except
    Result.Free;
    raise;
  end;
end;

class function TLinterIndex.ProjectOf(const AFileName: string; const APackages: TArray<TPackageSource>;
  const APrograms: TArray<string>; AGroup: TShellWorkspaceGroup): TCheckProject;
var
  mIndexed: TCheckProject;
begin
  Result := TFileChecker.PackageOf(APackages, ChangeFileExt(ExtractFileName(AFileName), ''));
  if Result.Name = '' then
  begin
    Result.AutoCreateForms := TFormAccessBeforeCreateRule.FormsOfProgram(APrograms,
      ChangeFileExt(ExtractFileName(AFileName), ''));
  end;
  // Formulardatei und Dateien neben der Unit wie im Server (form-resource-missing, #1054).
  Result.FileName := TPath.GetFullPath(AFileName);
  if AGroup = nil then
  begin
    Exit;
  end;
  // Index, Nachladen und Projekte der Gruppe auf demselben Weg wie Server und MCP (#1112); gehört die
  // Datei zu einem geladenen Projekt, gelten dessen Anwendungsart und Formulare.
  mIndexed := AGroup.RuleProject(Result.FileName);
  Result.Services := mIndexed.Services;
  if mIndexed.Application <> TRuleApplicationKind.Unknown then
  begin
    Result.Application := mIndexed.Application;
    Result.Name := mIndexed.Name;
    Result.AutoCreateForms := mIndexed.AutoCreateForms;
    Result.ProjectMainSource := mIndexed.ProjectMainSource;
  end;
end;

class procedure TLinterIndex.Release(AGroup: TShellWorkspaceGroup);
begin
  if AGroup <> nil then
  begin
    AGroup.Stop;
  end;
  AGroup.Free;
end;

initialization
  TAtlasTextTables.Add('Shell.Linter.Index', cTexts);

end.
