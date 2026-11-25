unit Core.Workspace.Parts.Tests;

// Teile des Arbeitsbereichs: Ordnerlisten, Vorgaben und Ereignisse, Projektwahl (#46, #615), Stand des Projekts,
// Index-Cache (#49, #62), Indexauftrag (#648), Regelprojekte (#1112, #1378), Aufträge (#40, #550), Packages und
// Gruppe (#1016), Laden (#648) und Indexaufbau.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreWorkspacePartsTests = class
  private
    FFolder: string;
  public
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
    /// <summary>Präfixe aus dem Projektkontext der IDE für die Prüfregeln (#1111), mit Konstanten.</summary>
    [Test]
    procedure RuleProjectsNamingFromIdeContext;
    [Test]
    procedure JobsWithoutInstallation;
    /// <summary>Das eigene Projekt und nicht lesbare Gruppenprojekte tragen keine Ausgabe bei.</summary>
    [Test]
    procedure GroupOutputsSkipOwnAndUnreadable;
    /// <summary>Ohne Vorgabe die einzige .dproj im Ordner; eine fehlende feste Projektdatei ergibt keine.</summary>
    [Test]
    procedure LoaderFindsProjectFile;
    /// <summary>"project" aus einer atlas.json über der Wurzel gilt relativ zu deren Ordner, nicht zur Wurzel.
    /// </summary>
    [Test]
    procedure LoaderResolvesProjectAgainstConfigFolder;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.DprojReader,
  Atlas.Common.Projects.MissingUnit,
  Atlas.Common.Projects.Contract.UnitLookup,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Processes,
  System.JSON,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Core.Compiler,
  Core.Workspace.Listings,
  Core.Workspace.Setup,
  Core.Workspace.Build,
  Core.Workspace.State,
  Core.Workspace.Cache,
  Core.Workspace.Requests,
  Core.Workspace.RuleProjects,
  Core.Workspace.Jobs,
  Core.Workspace.Packages,
  Core.Workspace.Loader;

function ProjectWith(const AConfigs, APlatforms: TArray<string>): TProjectInfo;
begin
  Result := Default(TProjectInfo);
  Result.FileName := 'P.dproj';
  Result.MainSource := 'P.dpr';
  Result.Configs := AConfigs;
  Result.Platforms := APlatforms;
end;

{ TCoreWorkspacePartsTests }

procedure TCoreWorkspacePartsTests.SetUp;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'atlas-ws-parts-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FFolder);
end;

procedure TCoreWorkspacePartsTests.TearDown;
begin
  TSharedUnitListings.Clear;
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure TCoreWorkspacePartsTests.ListingsAndFileAccess;
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
  Assert.AreEqual(1, Integer(Length(TCoreFileAccess.Folders(FFolder))), 'Unterordner');
  Assert.AreEqual(1, Integer(Length(TCoreFileAccess.PasFilesFunc()(FFolder))));
  Assert.IsTrue(TCoreFileAccess.ExistsFunc()(TPath.Combine(FFolder, 'A.pas')));
  Assert.IsTrue(TCoreFileAccess.ReadTextFunc()(TPath.Combine(FFolder, 'A.pas'), mText));
  Assert.AreEqual('unit A;', mText);
  Assert.IsFalse(TCoreFileAccess.ReadText(TPath.Combine(FFolder, 'Fehlt.pas'), mText));
  Assert.AreEqual('', mText);
end;

procedure TCoreWorkspacePartsTests.SetupDefaultsAndEvents;
var
  mSetup: TCoreWorkspaceSetup;
  mEvents: TCoreWorkspaceEvents;
  mContext: TIdeProjectContext;
  mSeen: string;
begin
  mSetup := nil;
  mEvents := nil;
  try
    mSetup := TCoreWorkspaceSetup.Create;
    mEvents := TCoreWorkspaceEvents.Create;
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

procedure TCoreWorkspacePartsTests.BuildChoiceSelectsAndDrops;
var
  mSetup: TCoreWorkspaceSetup;
  mBuild: TCoreBuildChoice;
  mLogger: ILogger;
  mOptions: TDprojOptions;
  mError: string;
begin
  mSetup := nil;
  mBuild := nil;
  try
    mSetup := TCoreWorkspaceSetup.Create;
    mLogger := TLogger.Create;
    mBuild := TCoreBuildChoice.Create('Test', mLogger, mSetup);
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

procedure TCoreWorkspacePartsTests.BuildChoiceNormalizesDefines;
var
  mSetup: TCoreWorkspaceSetup;
  mBuild: TCoreBuildChoice;
  mLogger: ILogger;
  mProject: TProjectInfo;
  mError: string;
begin
  mSetup := nil;
  mBuild := nil;
  try
    mSetup := TCoreWorkspaceSetup.Create;
    mLogger := TLogger.Create;
    mBuild := TCoreBuildChoice.Create('Test', mLogger, mSetup);
    Assert.AreEqual('DEBUG;TRACE', string.Join(';', TCoreBuildChoice.NormalizedDefines([' debug', 'TRACE', '',
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

procedure TCoreWorkspacePartsTests.StateKnowsFilesAndProject;
var
  mSetup: TCoreWorkspaceSetup;
  mState: TCoreProjectState;
  mFiles: TCoreIndexedFiles;
  mInstall: TCoreInstallInfo;
  mProject: TProjectInfo;
  mDefines: TArray<string>;
begin
  mSetup := nil;
  mState := nil;
  try
    mSetup := TCoreWorkspaceSetup.Create;
    mState := TCoreProjectState.Create(mSetup);
    Assert.IsFalse(mState.Project(mProject), 'Vor dem Laden kein Projekt');
    Assert.IsFalse(mState.Defines(mDefines));
    Assert.AreEqual(Int64(-1), mState.Stats.LastIndexMs, 'Noch kein Lauf');
    mSetup.ProjectFile := 'Fest.dproj';
    Assert.AreEqual('Fest.dproj', mState.ProjectFileName, 'Feste Projektdatei vor dem Laden');
    mSetup.ProjectFile := '';
    mInstall := Default(TCoreInstallInfo);
    mInstall.LibraryPaths := TArray<string>.Create('Lib');
    mState.SetProject(ProjectWith(nil, nil), mInstall);
    Assert.AreEqual('P.dproj', mState.ProjectFileName);
    mFiles := Default(TCoreIndexedFiles);
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

procedure TCoreWorkspacePartsTests.CacheDiscardsFiles;
var
  mFiles: TCoreCacheFiles;
  mLogger: ILogger;
  mSetup: TCoreWorkspaceSetup;
  mEvents: TCoreWorkspaceEvents;
  mCache: TCoreWorkspaceCache;
  mCacheFile: string;
  mProcesses: TArray<TIndexProcessInfo>;
begin
  mFiles := TCoreCacheFiles.Create(TPath.Combine(FFolder, 'p.idx'), TPath.Combine(FFolder, 'l.idx'),
    TPath.Combine(FFolder, 's.idx'));
  TFile.WriteAllText(mFiles.ProjectFile, 'x');
  TFile.WriteAllText(mFiles.LibraryFile, 'x');
  TFile.WriteAllText(mFiles.SearchFile, 'x');
  mLogger := TLogger.Create;
  TCoreWorkspaceCache.DiscardFiles(mFiles, mLogger)();
  Assert.IsFalse(TFile.Exists(mFiles.ProjectFile));
  Assert.IsFalse(TFile.Exists(mFiles.LibraryFile));
  Assert.IsFalse(TFile.Exists(mFiles.SearchFile));
  mSetup := nil;
  mEvents := nil;
  mCache := nil;
  try
    mSetup := TCoreWorkspaceSetup.Create;
    mEvents := TCoreWorkspaceEvents.Create;
    mCache := TCoreWorkspaceCache.Create('Test', mLogger, mSetup, mEvents);
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

procedure TCoreWorkspacePartsTests.RequestsKeyAndExclude;
var
  mFiles: TCoreIndexFiles;
  mKey: string;
  mProject: TProjectInfo;
begin
  Assert.IsTrue(TCoreIndexRequests.ExcludedOf(['**/Gen/**'])('C:/P/Gen/A.pas'), 'Muster trifft');
  Assert.IsFalse(TCoreIndexRequests.ExcludedOf(['**/Gen/**'])('C:/P/Src/A.pas'));
  Assert.IsFalse(TCoreIndexRequests.ExcludedOf(nil)('C:/P/Src/A.pas'), 'Ohne Muster nichts ausgeschlossen');
  mFiles := Default(TCoreIndexFiles);
  mFiles.Files := TArray<string>.Create('a.pas');
  mKey := mFiles.Key('sig');
  mFiles.SearchFiles := TArray<string>.Create('b.pas');
  Assert.AreNotEqual(mKey, mFiles.Key('sig'), 'Neue Suchpfad-Unit ändert den Schlüssel');
  mProject := Default(TProjectInfo);
  Assert.AreEqual('C:\Ordner', TCoreIndexRequests.CacheOriginOf(mProject, 'C:\Ordner'), 'Ohne Projekt der Ordner');
  mProject.FileName := 'P.dproj';
  Assert.AreEqual('P.dproj', TCoreIndexRequests.CacheOriginOf(mProject, 'C:\Ordner'));
end;

procedure TCoreWorkspacePartsTests.RuleProjectsMembersAndWarnings;
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
  Assert.IsTrue(TCoreRuleProjects.IsMember(mProject, 'u.pas'));
  Assert.IsTrue(TCoreRuleProjects.IsMember(mProject, 'P.dpr'), 'Hauptquelltext gehört dazu');
  Assert.IsFalse(TCoreRuleProjects.IsMember(mProject, 'V.pas'));
  Assert.AreEqual('true', TCoreRuleProjects.ConsoleTargetOf(mProject));
  Assert.AreEqual('WARNINGS=true', string.Join(';', TCoreRuleProjects.ProjectWarningsOf(mProject)));
end;

procedure TCoreWorkspacePartsTests.RuleProjectsNamingFromIdeContext;
var
  mValue: TJSONValue;
  mContext: TIdeProjectContext;
  mNaming: TRuleNaming;
begin
  mValue := TJSONObject.ParseJSONValue(
    '{"project":"C:\\P\\A.dproj","naming":{"field":"F","local":"m","constant":"c"}}');
  try
    mContext := TIdeProjectContext.FromJson(mValue);
  finally
    mValue.Free;
  end;
  mNaming := TCoreRuleProjects.NamingOf(mContext);
  Assert.IsTrue(mNaming.Known[TRuleNamingKind.Field]);
  Assert.AreEqual('F', mNaming.Prefixes[TRuleNamingKind.Field]);
  Assert.AreEqual('m', mNaming.Prefixes[TRuleNamingKind.Local]);
  Assert.AreEqual('c', mNaming.Prefixes[TRuleNamingKind.Constant]);
  Assert.IsFalse(mNaming.Known[TRuleNamingKind.Parameter]);
end;

procedure TCoreWorkspacePartsTests.JobsWithoutInstallation;
var
  mJob: TCoreCompileJob;
  mError: string;
  mSetup: TMissingUnitSetup;
begin
  Assert.IsFalse(TCoreWorkspaceJobs.CompileJobOf(ProjectWith(nil, nil), Default(TCoreInstallInfo),
    Default(TCompilerSettings), mJob, mError));
  Assert.AreEqual('Delphi-Installation nicht gefunden', mError);
  mSetup := TCoreWorkspaceJobs.MissingUnitSetupOf(ProjectWith(nil, nil), Default(TCoreInstallInfo),
    Default(TCoreWorkspaceFactories));
  Assert.AreEqual('P.dproj', mSetup.Project.FileName);
  Assert.AreEqual(0, Integer(Length(mSetup.Platforms)), 'Ohne Installation keine Plattformen');
  Assert.AreEqual(0, Integer(Length(mSetup.Targets)), 'Ohne Konfigurationen keine Ziele');
end;

procedure TCoreWorkspacePartsTests.GroupOutputsSkipOwnAndUnreadable;
var
  mLogger: ILogger;
  mOutputs: TArray<TUnitLookupGroupOutput>;
begin
  mLogger := TLogger.Create;
  Assert.AreEqual(0, Integer(Length(TCorePackageLookups.GroupOutputsFor('Eigen.dproj', ['Eigen.dproj',
    TPath.Combine(FFolder, 'Fehlt.dproj')], Default(TDprojOptions), mLogger))));
  // Package der Gruppe ohne Ausgabeordner: zählt mit seinem Namen für requires.
  TFile.WriteAllText(TPath.Combine(FFolder, 'Atlas.Text.dproj'), '<Project/>', TEncoding.UTF8);
  mOutputs := TCorePackageLookups.GroupOutputsFor('Eigen.dproj', [TPath.Combine(FFolder, 'Atlas.Text.dproj')],
    Default(TDprojOptions), mLogger);
  Assert.AreEqual(1, Integer(Length(mOutputs)));
  Assert.AreEqual('Atlas.Text', mOutputs[0].ProjectName);
  Assert.AreEqual('', mOutputs[0].DcuFolder);
end;

procedure TCoreWorkspacePartsTests.LoaderFindsProjectFile;
var
  mSetup: TCoreWorkspaceSetup;
  mBuild: TCoreBuildChoice;
  mLoader: TCoreProjectLoader;
  mLogger: ILogger;
  mSettings: TServerSettings;
begin
  TFile.WriteAllText(TPath.Combine(FFolder, 'Einzig.dproj'), '<Project/>');
  mSetup := nil;
  mBuild := nil;
  mLoader := nil;
  try
    mSetup := TCoreWorkspaceSetup.Create;
    mLogger := TLogger.Create;
    mBuild := TCoreBuildChoice.Create('Test', mLogger, mSetup);
    mLoader := TCoreProjectLoader.Create('Test', FFolder, '', mLogger, mSetup, mBuild);
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

procedure TCoreWorkspacePartsTests.LoaderResolvesProjectAgainstConfigFolder;
var
  mSetup: TCoreWorkspaceSetup;
  mBuild: TCoreBuildChoice;
  mLoader: TCoreProjectLoader;
  mLogger: ILogger;
  mSettings: TServerSettings;
  mSub: string;
begin
  mSub := TPath.Combine(FFolder, 'Teil');
  TDirectory.CreateDirectory(mSub);
  TFile.WriteAllText(TPath.Combine(FFolder, 'Gruppe.dproj'), '<Project/>');
  mSetup := nil;
  mBuild := nil;
  mLoader := nil;
  try
    mSetup := TCoreWorkspaceSetup.Create;
    mLogger := TLogger.Create;
    mBuild := TCoreBuildChoice.Create('Test', mLogger, mSetup);
    mLoader := TCoreProjectLoader.Create('Test', mSub, IncludeTrailingPathDelimiter(FFolder), mLogger, mSetup,
      mBuild);
    mSettings := Default(TServerSettings);
    mSettings.Project := 'Gruppe.dproj';
    Assert.AreEqual(TPath.Combine(FFolder, 'Gruppe.dproj'), mLoader.FindProjectFile(mSettings));
  finally
    mLoader.Free;
    mBuild.Free;
    mSetup.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCoreWorkspacePartsTests);

end.
