unit Shell.Workspace.Parts.Tests;

// Teile des Arbeitsbereichs: Ordnerlisten, Vorgaben und Ereignisse, Projektwahl (#46, #615), Stand des Projekts,
// Index-Cache (#49, #62), Indexauftrag (#648), Regelprojekte (#1112, #1378), Aufträge (#40, #550), Packages und
// Gruppe (#1016), Laden (#648) und Indexaufbau.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellWorkspacePartsTests = class
  private
    FFolder: string;
  public
    /// <summary>Einmal-Belegungen vorwegnehmen; sie gehören nicht in die Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    /// <summary>Geteilte Listen trennen .pas und .dcu; nicht vorhandene Ordner und Dateien liefern nichts.</summary>
    [Test]
    procedure ListingsAndFileAccess;
    [Test]
    procedure SetupDefaultsAndEvents;
    /// <summary>Wahl nur, wenn das Projekt sie kennt; verschwindet sie aus dem Projekt, gelten die Vorgaben.</summary>
    [Test]
    procedure BuildChoiceSelectsAndDrops;
    [Test]
    procedure BuildChoiceNormalizesDefines;
    [Test]
    procedure StateKnowsFilesAndProject;
    /// <summary>Verwerfen löscht Projekt-, Bibliotheks- und Suchpfad-Cache (#49).</summary>
    [Test]
    procedure CacheDiscardsFiles;
    [Test]
    procedure RequestsKeyAndExclude;
    [Test]
    procedure RuleProjectsMembersAndWarnings;
    [Test]
    procedure JobsWithoutInstallation;
    /// <summary>Das eigene Projekt und nicht lesbare Gruppenprojekte tragen keine Ausgabe bei.</summary>
    [Test]
    procedure GroupOutputsSkipOwnAndUnreadable;
    /// <summary>Ohne Vorgabe die einzige .dproj im Ordner; eine fehlende feste Projektdatei ergibt keine.</summary>
    [Test]
    procedure LoaderFindsProjectFile;
    /// <summary>Ein neuer Aufbau läuft noch nicht; Kodierungen ohne Dateien melden nichts.</summary>
    [Test]
    procedure IndexingStartsIdle;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.JsonRpc.StreamTransport,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.DprojReader,
  Atlas.Common.Projects.MissingUnit,
  Atlas.Common.Projects.UnitLookup,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Processes,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Rules.Checker,
  Shell.Compiler,
  Shell.Workspace.Listings,
  Shell.Workspace.Setup,
  Shell.Workspace.Build,
  Shell.Workspace.State,
  Shell.Workspace.Cache,
  Shell.Workspace.Requests,
  Shell.Workspace.RuleProjects,
  Shell.Workspace.Jobs,
  Shell.Workspace.Packages,
  Shell.Workspace.Loader,
  Shell.Workspace.Encodings,
  Shell.Workspace.Indexing;

function ProjectWith(const AConfigs, APlatforms: TArray<string>): TProjectInfo;
begin
  Result := Default(TProjectInfo);
  Result.FileName := 'P.dproj';
  Result.MainSource := 'P.dpr';
  Result.Configs := AConfigs;
  Result.Platforms := APlatforms;
end;

procedure TShellWorkspacePartsTests.WarmUpFirstUse;
begin
  SetUp;
  try
    ListingsAndFileAccess;
  finally
    TearDown;
  end;
end;

procedure TShellWorkspacePartsTests.SetUp;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'atlas-ws-parts-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FFolder);
end;

procedure TShellWorkspacePartsTests.TearDown;
begin
  TSharedUnitListings.Clear;
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure TShellWorkspacePartsTests.ListingsAndFileAccess;
var
  mText: string;
begin
  TFile.WriteAllText(TPath.Combine(FFolder, 'A.pas'), 'unit A;', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'B.dcu'), 'x', TEncoding.UTF8);
  TDirectory.CreateDirectory(TPath.Combine(FFolder, 'Sub'));
  Assert.AreEqual(1, Integer(Length(TSharedUnitListings.List(FFolder))), '.pas');
  Assert.AreEqual(2, Integer(Length(TSharedUnitListings.ListUnitFiles(FFolder))), '.pas und .dcu');
  Assert.AreEqual(2, Integer(Length(TSharedUnitListings.ListUnitFilesFunc()(FFolder))), 'als Rückruf');
  Assert.AreEqual(0, Integer(Length(TSharedUnitListings.List(TPath.Combine(FFolder, 'Fehlt')))));
  Assert.AreEqual(1, Integer(Length(TShellFileAccess.Folders(FFolder))), 'Unterordner');
  Assert.AreEqual(1, Integer(Length(TShellFileAccess.PasFilesFunc()(FFolder))));
  Assert.IsTrue(TShellFileAccess.ExistsFunc()(TPath.Combine(FFolder, 'A.pas')));
  Assert.IsTrue(TShellFileAccess.ReadTextFunc()(TPath.Combine(FFolder, 'A.pas'), mText));
  Assert.AreEqual('unit A;', mText);
  Assert.IsFalse(TShellFileAccess.ReadText(TPath.Combine(FFolder, 'Fehlt.pas'), mText));
  Assert.AreEqual('', mText);
end;

procedure TShellWorkspacePartsTests.SetupDefaultsAndEvents;
var
  mSetup: TShellWorkspaceSetup;
  mEvents: TShellWorkspaceEvents;
  mContext: TIdeProjectContext;
  mSeen: string;
begin
  mSetup := TShellWorkspaceSetup.Create;
  mEvents := TShellWorkspaceEvents.Create;
  try
    Assert.AreNotEqual('', mSetup.CacheRoot, 'Vorgabe-Ordner der Caches');
    Assert.AreEqual(0, Integer(Length(mSetup.PackageFolders)), 'Ohne Rückruf keine Ordner');
    Assert.IsFalse(mSetup.IdeContext('P.dproj', mContext), 'Ohne IDE-Projekte kein Kontext');
    mEvents.IndexEvent('ohne Empfänger');
    mEvents.ProjectLoaded;
    mSeen := '';
    mEvents.OnIndexEvent :=
      procedure(AText: string)
      begin
        mSeen := AText;
      end;
    mEvents.IndexEvent('index start');
    Assert.AreEqual('index start', mSeen);
  finally
    mEvents.Free;
    mSetup.Free;
  end;
end;

procedure TShellWorkspacePartsTests.BuildChoiceSelectsAndDrops;
var
  mSetup: TShellWorkspaceSetup;
  mBuild: TShellBuildChoice;
  mLogger: ILogger;
  mOptions: TDprojOptions;
  mError: string;
begin
  mSetup := TShellWorkspaceSetup.Create;
  mLogger := TLogger.Create;
  mBuild := TShellBuildChoice.Create('Test', mLogger, mSetup);
  try
    Assert.IsFalse(mBuild.Chosen);
    Assert.IsFalse(mBuild.Select(ProjectWith(['Debug'], ['Win32']), 'Release', '', nil, False, mError));
    Assert.AreNotEqual('', mError, 'Grund für die unbekannte Konfiguration');
    Assert.IsTrue(mBuild.Select(ProjectWith(['Debug', 'Release'], ['Win32']), 'Release', '', nil, False, mError),
      mError);
    Assert.IsTrue(mBuild.Chosen);
    mOptions := Default(TDprojOptions);
    mOptions.Config := 'Debug';
    mOptions.Platform := 'Win64';
    mBuild.ApplyTo(mOptions);
    Assert.AreEqual('Release', mOptions.Config, 'Gewählte Konfiguration gilt');
    Assert.AreEqual('Win64', mOptions.Platform, 'Ungewählte Plattform bleibt');
    Assert.IsFalse(mBuild.DropUnknown(ProjectWith(['Debug', 'Release'], ['Win32'])), 'Projekt kennt die Wahl');
    Assert.IsTrue(mBuild.DropUnknown(ProjectWith(['Debug'], ['Win32'])), 'Wahl gibt es nicht mehr');
    Assert.IsFalse(mBuild.Chosen, 'Danach gelten die Vorgaben');
  finally
    mBuild.Free;
    mSetup.Free;
  end;
end;

procedure TShellWorkspacePartsTests.BuildChoiceNormalizesDefines;
var
  mSetup: TShellWorkspaceSetup;
  mBuild: TShellBuildChoice;
  mLogger: ILogger;
  mProject: TProjectInfo;
  mError: string;
begin
  mSetup := TShellWorkspaceSetup.Create;
  mLogger := TLogger.Create;
  mBuild := TShellBuildChoice.Create('Test', mLogger, mSetup);
  try
    Assert.AreEqual('DEBUG;TRACE', string.Join(';', TShellBuildChoice.NormalizedDefines([' debug', 'TRACE', '',
      'Debug '])));
    mProject := ProjectWith(nil, nil);
    mProject.Defines := TArray<string>.Create('ALT');
    mBuild.ApplyDefines(mProject);
    Assert.AreEqual('ALT', string.Join(';', mProject.Defines), 'Ohne Symbole der IDE bleiben die der Datei');
    Assert.IsTrue(mBuild.Select(mProject, '', '', ['ide'], True, mError), mError);
    mBuild.ApplyDefines(mProject);
    Assert.AreEqual('IDE', string.Join(';', mProject.Defines), 'Symbole der IDE gelten vor denen der Datei');
  finally
    mBuild.Free;
    mSetup.Free;
  end;
end;

procedure TShellWorkspacePartsTests.StateKnowsFilesAndProject;
var
  mSetup: TShellWorkspaceSetup;
  mState: TShellProjectState;
  mFiles: TShellIndexedFiles;
  mInstall: TShellInstallInfo;
  mProject: TProjectInfo;
  mDefines: TArray<string>;
begin
  mSetup := TShellWorkspaceSetup.Create;
  mState := TShellProjectState.Create(mSetup);
  try
    Assert.IsFalse(mState.Project(mProject), 'Vor dem Laden kein Projekt');
    Assert.IsFalse(mState.Defines(mDefines));
    Assert.AreEqual(Int64(-1), mState.Stats.LastIndexMs, 'Noch kein Lauf');
    mSetup.ProjectFile := 'Fest.dproj';
    Assert.AreEqual('Fest.dproj', mState.ProjectFileName, 'Feste Projektdatei vor dem Laden');
    mSetup.ProjectFile := '';
    mInstall := Default(TShellInstallInfo);
    mInstall.LibraryPaths := TArray<string>.Create('Lib');
    mState.SetProject(ProjectWith(nil, nil), mInstall);
    Assert.AreEqual('P.dproj', mState.ProjectFileName);
    mFiles := Default(TShellIndexedFiles);
    mFiles.Defines := TArray<string>.Create('X');
    mFiles.SearchPaths := TArray<string>.Create('Such');
    mFiles.ProjectFiles := TArray<string>.Create('C:\P\Haupt.pas');
    mFiles.SearchFiles := TArray<string>.Create('C:\P\Such.pas');
    mState.SetIndexedFiles(mFiles);
    Assert.IsTrue(mState.ContainsFile('c:\p\haupt.pas'), 'Ohne Groß-/Kleinschreibung');
    Assert.IsTrue(mState.ContainsFile('C:\P\Such.pas'), 'Suchpfad-Unit gehört dazu');
    Assert.IsFalse(mState.ContainsFile('C:\P\Fremd.pas'));
    Assert.AreEqual('Such;Lib', string.Join(';', mState.IncludePaths), 'Suchpfade, dann Bibliothek');
    Assert.IsTrue(mState.Defines(mDefines));
    Assert.AreEqual('X', string.Join(';', mDefines));
  finally
    mState.Free;
    mSetup.Free;
  end;
end;

procedure TShellWorkspacePartsTests.CacheDiscardsFiles;
var
  mFiles: TShellCacheFiles;
  mLogger: ILogger;
  mSetup: TShellWorkspaceSetup;
  mEvents: TShellWorkspaceEvents;
  mCache: TShellWorkspaceCache;
  mCacheFile: string;
  mProcesses: TArray<TIndexProcessInfo>;
begin
  mFiles := TShellCacheFiles.Create(TPath.Combine(FFolder, 'p.idx'), TPath.Combine(FFolder, 'l.idx'),
    TPath.Combine(FFolder, 's.idx'));
  TFile.WriteAllText(mFiles.ProjectFile, 'x');
  TFile.WriteAllText(mFiles.LibraryFile, 'x');
  TFile.WriteAllText(mFiles.SearchFile, 'x');
  mLogger := TLogger.Create;
  TShellWorkspaceCache.DiscardFiles(mFiles, mLogger)();
  Assert.IsFalse(TFile.Exists(mFiles.ProjectFile));
  Assert.IsFalse(TFile.Exists(mFiles.LibraryFile));
  Assert.IsFalse(TFile.Exists(mFiles.SearchFile));
  mSetup := TShellWorkspaceSetup.Create;
  mEvents := TShellWorkspaceEvents.Create;
  mCache := TShellWorkspaceCache.Create('Test', mLogger, mSetup, mEvents);
  try
    Assert.IsFalse(mCache.Processes(mCacheFile, mProcesses), 'Ohne Cache keine Prozesse');
    Assert.IsFalse(mCache.Writes);
    mCache.SetFiles(mFiles);
    Assert.AreEqual(mFiles.LibraryFile, mCache.Files.LibraryFile);
  finally
    mCache.Free;
    mEvents.Free;
    mSetup.Free;
  end;
end;

procedure TShellWorkspacePartsTests.RequestsKeyAndExclude;
var
  mFiles: TShellIndexFiles;
  mKey: string;
  mProject: TProjectInfo;
begin
  Assert.IsTrue(TShellIndexRequests.ExcludedOf(['**/Gen/**'])('C:/P/Gen/A.pas'), 'Muster trifft');
  Assert.IsFalse(TShellIndexRequests.ExcludedOf(['**/Gen/**'])('C:/P/Src/A.pas'));
  Assert.IsFalse(TShellIndexRequests.ExcludedOf(nil)('C:/P/Src/A.pas'), 'Ohne Muster nichts ausgeschlossen');
  mFiles := Default(TShellIndexFiles);
  mFiles.Files := TArray<string>.Create('a.pas');
  mKey := mFiles.Key('sig');
  mFiles.SearchFiles := TArray<string>.Create('b.pas');
  Assert.AreNotEqual(mKey, mFiles.Key('sig'), 'Neue Suchpfad-Unit ändert den Schlüssel');
  mProject := Default(TProjectInfo);
  Assert.AreEqual('C:\Ordner', TShellIndexRequests.CacheOriginOf(mProject, 'C:\Ordner'), 'Ohne Projekt der Ordner');
  mProject.FileName := 'P.dproj';
  Assert.AreEqual('P.dproj', TShellIndexRequests.CacheOriginOf(mProject, 'C:\Ordner'));
end;

procedure TShellWorkspacePartsTests.RuleProjectsMembersAndWarnings;
var
  mProject: TProjectInfo;
  mUnit: TProjectUnit;
begin
  mProject := ProjectWith(nil, nil);
  mUnit.Name := 'U';
  mUnit.FileName := 'U.pas';
  mProject.Units := [mUnit];
  mProject.Properties := [TPair<string, string>.Create('DCC_ConsoleTarget', 'true'),
    TPair<string, string>.Create('DCC_WARNINGS', ' TRUE '), TPair<string, string>.Create('Sonst', 'x')];
  Assert.IsTrue(TShellRuleProjects.IsMember(mProject, 'u.pas'));
  Assert.IsTrue(TShellRuleProjects.IsMember(mProject, 'P.dpr'), 'Hauptquelltext gehört dazu');
  Assert.IsFalse(TShellRuleProjects.IsMember(mProject, 'V.pas'));
  Assert.AreEqual('true', TShellRuleProjects.ConsoleTargetOf(mProject));
  Assert.AreEqual('WARNINGS=true', string.Join(';', TShellRuleProjects.ProjectWarningsOf(mProject)));
end;

procedure TShellWorkspacePartsTests.JobsWithoutInstallation;
var
  mJob: TShellCompileJob;
  mError: string;
  mSetup: TMissingUnitSetup;
begin
  Assert.IsFalse(TShellWorkspaceJobs.CompileJobOf(ProjectWith(nil, nil), Default(TShellInstallInfo),
    Default(TCompilerSettings), mJob, mError));
  Assert.AreEqual('Delphi-Installation nicht gefunden', mError);
  mSetup := TShellWorkspaceJobs.MissingUnitSetupOf(ProjectWith(nil, nil), Default(TShellInstallInfo));
  Assert.AreEqual('P.dproj', mSetup.Project.FileName);
  Assert.AreEqual(0, Integer(Length(mSetup.Platforms)), 'Ohne Installation keine Plattformen');
  Assert.AreEqual(0, Integer(Length(mSetup.Targets)), 'Ohne Konfigurationen keine Ziele');
end;

procedure TShellWorkspacePartsTests.GroupOutputsSkipOwnAndUnreadable;
var
  mLogger: ILogger;
  mOutputs: TArray<TUnitLookupGroupOutput>;
begin
  mLogger := TLogger.Create;
  Assert.AreEqual(0, Integer(Length(TShellPackageLookups.GroupOutputsFor('Eigen.dproj', ['Eigen.dproj',
    TPath.Combine(FFolder, 'Fehlt.dproj')], Default(TDprojOptions), mLogger))));
  // Package der Gruppe ohne Ausgabeordner: zählt mit seinem Namen für requires.
  TFile.WriteAllText(TPath.Combine(FFolder, 'Atlas.Text.dproj'), '<Project/>', TEncoding.UTF8);
  mOutputs := TShellPackageLookups.GroupOutputsFor('Eigen.dproj', [TPath.Combine(FFolder, 'Atlas.Text.dproj')],
    Default(TDprojOptions), mLogger);
  Assert.AreEqual(1, Integer(Length(mOutputs)));
  Assert.AreEqual('Atlas.Text', mOutputs[0].ProjectName);
  Assert.AreEqual('', mOutputs[0].DcuFolder);
end;

procedure TShellWorkspacePartsTests.LoaderFindsProjectFile;
var
  mSetup: TShellWorkspaceSetup;
  mBuild: TShellBuildChoice;
  mLoader: TShellProjectLoader;
  mLogger: ILogger;
  mSettings: TServerSettings;
begin
  TFile.WriteAllText(TPath.Combine(FFolder, 'Einzig.dproj'), '<Project/>');
  mSetup := TShellWorkspaceSetup.Create;
  mLogger := TLogger.Create;
  mBuild := TShellBuildChoice.Create('Test', mLogger, mSetup);
  mLoader := TShellProjectLoader.Create('Test', FFolder, mLogger, mSetup, mBuild);
  try
    mSettings := Default(TServerSettings);
    Assert.AreEqual(TPath.Combine(FFolder, 'Einzig.dproj'), mLoader.FindProjectFile(mSettings));
    mSetup.ProjectFile := TPath.Combine(FFolder, 'Fehlt.dproj');
    Assert.AreEqual('', mLoader.FindProjectFile(mSettings), 'Feste, fehlende Projektdatei');
  finally
    mLoader.Free;
    mBuild.Free;
    mSetup.Free;
  end;
end;

procedure TShellWorkspacePartsTests.IndexingStartsIdle;
var
  mParts: TShellIndexingParts;
  mIndexing: TShellWorkspaceIndexing;
  mReport: TShellEncodingReport;
  mIndex: ISymbolIndex;
  mLogger: ILogger;
begin
  mIndex := TSymbolIndex.Create;
  mLogger := TLogger.Create;
  mParts := Default(TShellIndexingParts);
  mParts.Name := 'Test';
  mParts.Logger := mLogger;
  mParts.Transport := TJsonRpcStreamTransport.Create(nil, TBytesStream.Create, True);
  mParts.Index := mIndex;
  mParts.ProgressToken := 'atlas-test-index';
  mParts.Setup := TShellWorkspaceSetup.Create;
  mParts.Events := TShellWorkspaceEvents.Create;
  mParts.State := TShellProjectState.Create(mParts.Setup);
  mParts.Cache := TShellWorkspaceCache.Create('Test', mLogger, mParts.Setup, mParts.Events);
  mIndexing := TShellWorkspaceIndexing.Create(mParts);
  mReport := TShellEncodingReport.Create('Test', FFolder, mLogger, nil, mIndex);
  try
    Assert.AreEqual(-1, mIndexing.Loading, 'Kein Aufbau läuft');
    Assert.AreSame(mIndex, mIndexing.Index);
    mReport.Report(nil);
  finally
    mReport.Free;
    mIndexing.Free;
    mParts.Cache.Free;
    mParts.State.Free;
    mParts.Events.Free;
    mParts.Setup.Free;
    mParts := Default(TShellIndexingParts);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellWorkspacePartsTests);

end.
