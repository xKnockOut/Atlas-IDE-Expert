unit Shell.Workspace.Requests;

// Internals-Rolle Shell: Dateien und Indexauftrag eines geladenen Projekts. Projektdateien, alle Units der Such-
// und Bibliothekspfade (#648), Packages aus contains und requires (#46), Symbole, Include-Pfade (#264) und die
// Cache-Dateien je Projekt, Bibliothek und Suchpfaden (#492, #647).

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.PackageLocator,
  Atlas.Common.Index.ProjectFiles,
  Atlas.Common.Index.Service,
  Shell.Workspace.Loader;

type
  /// <summary>Dateien eines Indexaufbaus.</summary>
  TShellIndexFiles = record
    Files: TArray<string>;
    SearchFiles: TArray<string>;
    LibraryFiles: TArray<string>;
    /// <summary>Neu indexieren, wenn sich ASignature oder die Unit-Listen ändern; der Cache hängt nur an
    /// ASignature.</summary>
    function Key(const ASignature: string): string;
  end;

  /// <summary>Wohin und wie ein Aufbau schreibt.</summary>
  TShellRequestTarget = record
    CacheRoot: string;
    Priority: Integer;
    Usages: Boolean;
  end;

  TShellIndexRequests = class
  public
    /// <summary>Trifft ein Muster aus APatterns (index.exclude) den Dateinamen?</summary>
    class function ExcludedOf(const APatterns: TArray<string>): TIndexExcluded; static;
    /// <summary>Projektdateien; mit index.searchPaths die Units der Suchpfade, mit index.libraryPaths die der
    /// Bibliothekspfade, jeweils alle, nicht nur die über uses erreichbaren (#648).</summary>
    class function FilesOf(const ALoaded: TShellLoadedProject; const ASettings: TServerSettings): TShellIndexFiles;
      static;
    /// <summary>Packages (#46): contains der .dpk gehört zum Projekt, auch ohne DCCReference; die Units der
    /// requires-Packages mit Quelltext kommen zu den Suchpfad-Units. Meldet die Anzahlen an ALogger.</summary>
    class procedure AddPackageFiles(const AProject: TProjectInfo; ALocator: TPackageLocator;
      var AFiles: TShellIndexFiles; const ALogger: ILogger; const AName: string); static;
    /// <summary>Auftrag für den Aufbau ohne Unit-Suche, Sperre und Vorbereitung.</summary>
    class function RequestOf(const ALoaded: TShellLoadedProject; const AFiles: TShellIndexFiles;
      const ATarget: TShellRequestTarget): TIndexRequest; static;
    /// <summary>Herkunft für das Aufräumen (#905): die Projektdatei, ohne sie ARoot.</summary>
    class function CacheOriginOf(const AProject: TProjectInfo; const ARoot: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Compiler.CommandLine,
  Atlas.Common.Projects.PackageReader,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Shell.Bootstrap,
  Shell.Workspace.Listings,
  Atlas.Text.LogMarks;

{ TShellIndexFiles }

function TShellIndexFiles.Key(const ASignature: string): string;
begin
  Result := ASignature + '#' + AnsiUpperCase(String.Join(';', Files)) + '#' +
    AnsiUpperCase(String.Join(';', SearchFiles)) + '#' + AnsiUpperCase(String.Join(';', LibraryFiles));
end;

{ TShellIndexRequests }

class function TShellIndexRequests.ExcludedOf(const APatterns: TArray<string>): TIndexExcluded;
var
  mPatterns: TArray<string>;
begin
  mPatterns := APatterns;
  Result :=
    function(const AFileName: string): Boolean
    var
      mPattern: string;
    begin
      Result := False;
      for mPattern in mPatterns do
      begin
        Result := Result or MatchesGlob(mPattern, AFileName);
      end;
    end;
end;

class function TShellIndexRequests.FilesOf(const ALoaded: TShellLoadedProject;
  const ASettings: TServerSettings): TShellIndexFiles;
var
  mExcluded: TIndexExcluded;
begin
  mExcluded := ExcludedOf(ASettings.IndexExclude);
  Result := Default(TShellIndexFiles);
  Result.Files := TIndexProjectFiles.Files(ALoaded.Project);
  if ASettings.IndexSearchPaths then
  begin
    Result.SearchFiles := TIndexProjectFiles.PathFiles(ALoaded.Project.SearchPaths, TShellFileAccess.PasFilesFunc(),
      mExcluded, Result.Files);
  end;
  if ASettings.IndexLibraryPaths then
  begin
    Result.LibraryFiles := TIndexProjectFiles.PathFiles(ALoaded.LibraryPaths, TShellFileAccess.PasFilesFunc(),
      mExcluded, Result.Files + Result.SearchFiles);
  end;
end;

/// <summary>Hängt die vorhandenen, noch nicht bekannten Dateien aus ACandidates an ATarget; Anzahl.</summary>
function AddNew(const ACandidates: TArray<string>; AKnown: TDictionary<string, Boolean>;
  var ATarget: TArray<string>): Integer;
var
  mFileName: string;
begin
  Result := 0;
  for mFileName in ACandidates do
  begin
    if not AKnown.ContainsKey(AnsiUpperCase(mFileName)) and FileExists(mFileName) then
    begin
      AKnown.Add(AnsiUpperCase(mFileName), True);
      ATarget := ATarget + [mFileName];
      Inc(Result);
    end;
  end;
end;

/// <summary>Quelltext der .dpk von AProject; False, wenn es kein lesbares Package ist.</summary>
function PackageSourceOf(const AProject: TProjectInfo; out ASource: TPackageSource): Boolean;
var
  mText: string;
begin
  Result := SameText(ExtractFileExt(AProject.MainSource), '.dpk') and
    TShellBootstrap.ReadSourceText(AProject.MainSource, mText);
  if Result then
  begin
    ASource := TPackageReader.Read(mText);
    Result := ASource.IsPackage;
  end;
end;

class procedure TShellIndexRequests.AddPackageFiles(const AProject: TProjectInfo; ALocator: TPackageLocator;
  var AFiles: TShellIndexFiles; const ALogger: ILogger; const AName: string);
var
  mSource: TPackageSource;
  mKnown: TDictionary<string, Boolean>;
  mFileName: string;
  mAdded, mRequired: Integer;
begin
  if not PackageSourceOf(AProject, mSource) then
  begin
    Exit;
  end;
  mKnown := TDictionary<string, Boolean>.Create;
  try
    for mFileName in AFiles.Files + AFiles.SearchFiles do
    begin
      mKnown.AddOrSetValue(AnsiUpperCase(mFileName), True);
    end;
    mAdded := AddNew(TPackageLocator.ContainedFiles(AProject.MainSource, mSource), mKnown, AFiles.Files);
    mRequired := AddNew(ALocator.RequiredFiles(mSource), mKnown, AFiles.SearchFiles);
  finally
    mKnown.Free;
  end;
  if (mAdded > 0) or (mRequired > 0) then
  begin
    ALogger.Info(Format('%s: Package mit %d Units aus contains ohne DCCReference und %d aus requires-Packages',
      [TLogMarks.Name(AName), mAdded, mRequired]));
  end;
end;

/// <summary>Schlüssel des Suchpfad-Caches: Suchpfad-Units einmal für alle Projekte mit denselben Suchpfaden,
/// Defines und Include-Pfaden (Speicher, Rückmeldung 01.11.2026); sie werden mit den Defines des Projekts gelesen,
/// die gehören in den Schlüssel.</summary>
function SearchCacheKey(const ARequest: TIndexRequest; const AProject: TProjectInfo): string;
begin
  Result := AnsiUpperCase('search|' + String.Join(';', ARequest.Defines) + '|' +
    String.Join(';', AProject.SearchPaths) + '|' + String.Join(';', ARequest.IncludePaths) + '|' +
    String.Join(';', AProject.Namespaces));
end;

/// <summary>Bibliothek des Auftrags: RTL, VCL und FMX einmal je Compiler und Plattform, unabhängig von Projekt und
/// Konfiguration (#647). Nur der Ordner der Installation: Eigener Code im Bibliothekspfad wird oft mit dem Projekt
/// übersetzt. $I-Dateien wie beim Compiler: Projekt-Suchpfade, dann Bibliothekspfade (#264).</summary>
procedure SetLibrary(const ALoaded: TShellLoadedProject; var ARequest: TIndexRequest);
begin
  ARequest.IncludePaths := ALoaded.Project.SearchPaths;
  if ALoaded.Installation = nil then
  begin
    Exit;
  end;
  ARequest.LibraryRoots := TArray<string>.Create(TCompilerCommandLine.BdsRoot(ALoaded.Installation.Variables));
  ARequest.LibraryDefines := TIndexProjectFiles.LibraryDefines(ALoaded.Project, ALoaded.Version);
  ARequest.IncludePaths := ALoaded.Project.SearchPaths + ALoaded.CompilerLibraryPaths;
end;

class function TShellIndexRequests.RequestOf(const ALoaded: TShellLoadedProject; const AFiles: TShellIndexFiles;
  const ATarget: TShellRequestTarget): TIndexRequest;
begin
  Result := Default(TIndexRequest);
  Result.Files := AFiles.Files;
  Result.SearchFiles := AFiles.SearchFiles;
  Result.LibraryFiles := AFiles.LibraryFiles;
  Result.Priority := ATarget.Priority;
  Result.Defines := TIndexProjectFiles.Defines(ALoaded.Project, ALoaded.Version);
  SetLibrary(ALoaded, Result);
  // Ablage je IDE-Version und Projekt (#492): %LOCALAPPDATA%\Atlas\Index\<Version>\<Projekt-Hash>.
  Result.CacheFile := TIndexCacheDirectory.FileFor(ATarget.CacheRoot, ALoaded.Version,
    TIndexProjectFiles.Signature(ALoaded.Project, ALoaded.Version));
  // RTL/VCL/FMX einmal je Compilerversion und Plattform, geteilt mit allen Projekten (#492, #647).
  Result.LibraryCacheFile := TIndexCacheDirectory.LibraryFileFor(ATarget.CacheRoot, ALoaded.Version,
    TIndexProjectFiles.LibrarySignature(ALoaded.Project, ALoaded.Version));
  if Length(AFiles.SearchFiles) > 0 then
  begin
    Result.SearchCacheFile := TIndexCacheDirectory.SearchFileFor(ATarget.CacheRoot, ALoaded.Version,
      SearchCacheKey(Result, ALoaded.Project));
  end;
  Result.Usages := ATarget.Usages;
end;

class function TShellIndexRequests.CacheOriginOf(const AProject: TProjectInfo; const ARoot: string): string;
begin
  Result := AProject.FileName;
  if Result = '' then
  begin
    Result := ARoot;
  end;
end;

end.
