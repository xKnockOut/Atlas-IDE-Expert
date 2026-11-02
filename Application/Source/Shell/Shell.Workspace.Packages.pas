unit Shell.Workspace.Packages;

// Internals-Rolle Shell: Packages und Unit-Suche eines Arbeitsbereichs. Der Package-Locator lebt in einem Halter
// (#1220), damit Prüfungen in Anfrage-Threads ihn über einen Projektwechsel hinaus nutzen können; die Unit-Suche
// wie beim Compiler (#1016) bekommt Packages, Gruppe, Bibliothek und Index als Rückrufe.

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.PackageLocator,
  Atlas.Common.Projects.DprojReader,
  Atlas.Common.Projects.UnitLookup,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Hält einen TPackageLocator (#1220); der Locator wird mit dem letzten Halter frei.</summary>
  IPackageLocatorHold = interface
    ['{5B6F7C1E-2A9D-4E83-9F04-3C1D8A7B6E21}']
    function Locator: TPackageLocator;
  end;

  TPackageLocatorHold = class(TInterfacedObject, IPackageLocatorHold)
  private
    FLocator: TPackageLocator;
  public
    /// <summary>Übernimmt ALocator.</summary>
    constructor Create(ALocator: TPackageLocator);
    destructor Destroy; override;
    function Locator: TPackageLocator;
  end;

  /// <summary>Was die Unit-Suche eines Projekts braucht (#1016): Projekt, Installation und ihre Bibliothekspfade,
  /// Packages, Index und die Ausgaben der anderen Projekte der Gruppe.</summary>
  TShellUnitLookupSource = record
    Project: TProjectInfo;
    /// <summary>nil ohne Installation.</summary>
    Installation: ILibraryPathProvider;
    LibraryPaths: TArray<string>;
    /// <summary>nil ohne Package-Locator.</summary>
    Packages: IPackageLocatorHold;
    /// <summary>nil ohne Index.</summary>
    Index: ISymbolIndex;
    /// <summary>nil ohne Projektgruppe.</summary>
    GroupOutputsOf: TFunc<TArray<TUnitLookupGroupOutput>>;
  end;

  /// <summary>Rückrufe über Package-Locator, Gruppe und Index; die anonymen Methoden fangen den Halter ein, nicht
  /// den rohen Locator (#1220): Er bleibt, solange sie leben.</summary>
  TShellPackageLookups = class
  public
    /// <summary>Enthält das Package die Unit? Nicht gefundene Packages sind unbekannt, damit Regeln still bleiben
    /// statt falsch zu melden.</summary>
    class function Provides(const AHold: IPackageLocatorHold): TRulePackageProvides; static;
    /// <summary>Packages, die ein Package verlangt: dcc sieht auch deren Units (Atlas.Windows → Atlas.Common →
    /// Atlas.Text).</summary>
    class function Requires(const AHold: IPackageLocatorHold): TFunc<string, TArray<string>>; static;
    /// <summary>Wie Requires, als Typ der Prüfregeln.</summary>
    class function RuleRequires(const AHold: IPackageLocatorHold): TRulePackageRequires; static;
    class function Exists(const AHold: IPackageLocatorHold): TFunc<string, Boolean>; static;
    /// <summary>DCU-Ausgabe und Units der anderen Projekte der Gruppe (uses-unit-not-found, 3a): bei jeder Anfrage
    /// die aktuelle Liste AFiles, gelesen werden die .dproj nur, wenn sie sich geändert hat. Die IDE meldet die
    /// Projekte einzeln und nach dem ersten an.</summary>
    class function GroupOutputsOf(const AFiles: TFunc<TArray<string>>; const AOwnFile: string;
      const AOptions: TDprojOptions; const ALogger: ILogger): TFunc<TArray<TUnitLookupGroupOutput>>; static;
    /// <summary>DCU-Ausgabe und Units der Projekte AFiles außer AOwnFile, mit derselben Plattform und Konfiguration
    /// gelesen. Nicht lesbare Projekte fehlen nur.</summary>
    class function GroupOutputsFor(const AOwnFile: string; const AFiles: TArray<string>;
      const AOptions: TDprojOptions; const ALogger: ILogger): TArray<TUnitLookupGroupOutput>; static;
    /// <summary>Unit-Suche wie beim Compiler (#1016) über die geteilten Ordnerlisten. Ohne Installation (und ohne
    /// Bibliothekspfade aus der IDE) gilt keine Unit als sicher fehlend.</summary>
    class function UnitLookupFor(const ASource: TShellUnitLookupSource): IRuleUnitLookup; static;
  end;

implementation

uses
  System.Classes,
  System.StrUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Projects.PackageReader,
  Shell.Workspace.Listings;

{ TPackageLocatorHold }

constructor TPackageLocatorHold.Create(ALocator: TPackageLocator);
begin
  inherited Create;
  FLocator := ALocator;
end;

destructor TPackageLocatorHold.Destroy;
begin
  FLocator.Free;
  inherited;
end;

function TPackageLocatorHold.Locator: TPackageLocator;
begin
  Result := FLocator;
end;

type
  /// <summary>Gelesene Ausgaben der Gruppe (TShellPackageLookups.GroupOutputsOf).</summary>
  TGroupOutputCache = class
  private
    FLock: TObject;
    FKey: string;
    // Zuletzt nach der Projektliste gefragt (TThread.GetTickCount64); 0 = nie.
    FCheckedAt: UInt64;
    FOutputs: TArray<TUnitLookupGroupOutput>;
    FFiles: TFunc<TArray<string>>;
    FOwnFile: string;
    FOptions: TDprojOptions;
    FLogger: ILogger;
    function Recent(out AOutputs: TArray<TUnitLookupGroupOutput>): Boolean;
  public
    constructor Create(const AFiles: TFunc<TArray<string>>; const AOwnFile: string; const AOptions: TDprojOptions;
      const ALogger: ILogger);
    destructor Destroy; override;
    function Current: TArray<TUnitLookupGroupOutput>;
  end;

  IGroupOutputCacheHold = interface
    ['{6B1F4E2A-93C7-4D5B-A8E1-2F7C9D0B3A64}']
    function Cache: TGroupOutputCache;
  end;

  TGroupOutputCacheHold = class(TInterfacedObject, IGroupOutputCacheHold)
  private
    FCache: TGroupOutputCache;
  public
    constructor Create(ACache: TGroupOutputCache);
    destructor Destroy; override;
    function Cache: TGroupOutputCache;
  end;

constructor TGroupOutputCache.Create(const AFiles: TFunc<TArray<string>>; const AOwnFile: string;
  const AOptions: TDprojOptions; const ALogger: ILogger);
begin
  inherited Create;
  FLock := TObject.Create;
  FFiles := AFiles;
  FOwnFile := AOwnFile;
  FOptions := AOptions;
  FLogger := ALogger;
end;

destructor TGroupOutputCache.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TGroupOutputCache.Recent(out AOutputs: TArray<TUnitLookupGroupOutput>): Boolean;
const
  // Die Liste fragt die Komposition unter ihrer Sperre ab: nicht bei jeder fehlenden Unit.
  cRecheckMs = 2000;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := (FCheckedAt <> 0) and (TThread.GetTickCount64 - FCheckedAt < cRecheckMs);
    AOutputs := FOutputs;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TGroupOutputCache.Current: TArray<TUnitLookupGroupOutput>;
var
  mFiles: TArray<string>;
  mKey: string;
begin
  if Recent(Result) then
  begin
    Exit;
  end;
  mFiles := FFiles();
  mKey := AnsiUpperCase(string.Join(';', mFiles));
  System.TMonitor.Enter(FLock);
  try
    if mKey <> FKey then
    begin
      FOutputs := TShellPackageLookups.GroupOutputsFor(FOwnFile, mFiles, FOptions, FLogger);
      FKey := mKey;
    end;
    FCheckedAt := TThread.GetTickCount64;
    Result := FOutputs;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

constructor TGroupOutputCacheHold.Create(ACache: TGroupOutputCache);
begin
  inherited Create;
  FCache := ACache;
end;

destructor TGroupOutputCacheHold.Destroy;
begin
  FCache.Free;
  inherited;
end;

function TGroupOutputCacheHold.Cache: TGroupOutputCache;
begin
  Result := FCache;
end;

/// <summary>Rückruf für TUnitLookupSetup.GroupOutputsOf; fängt nur den Halter ein.</summary>
function GroupOutputsOfHold(const AHold: IGroupOutputCacheHold): TFunc<TArray<TUnitLookupGroupOutput>>;
begin
  Result :=
    function: TArray<TUnitLookupGroupOutput>
    begin
      Result := AHold.Cache.Current;
    end;
end;

/// <summary>Ausgabe eines Gruppenprojekts; False, wenn die .dproj nicht lesbar ist.</summary>
function GroupOutputOf(const AFile: string; const AOptions: TDprojOptions; const ALogger: ILogger;
  out AOutput: TUnitLookupGroupOutput): Boolean;
var
  mProject: TProjectInfo;
  mUnit: TProjectUnit;
begin
  AOutput := Default(TUnitLookupGroupOutput);
  try
    mProject := TDprojReader.Load(AFile, AOptions);
  except
    on E: Exception do
    begin
      ALogger.Debug(Format('Gruppenprojekt %s für die Unit-Suche nicht lesbar: %s', [AFile, E.Message]));
      Exit(False);
    end;
  end;
  AOutput.DcuFolder := TUnitLookup.DcuOutputOf(mProject);
  for mUnit in mProject.Units do
  begin
    AOutput.Units := AOutput.Units + [mUnit.Name];
  end;
  Result := AOutput.DcuFolder <> '';
end;

/// <summary>requires der .dpk: deren Units findet der Compiler über die .dcp. Nicht lesbar: '?', dann bleibt die
/// Suche bei Packages unsicher.</summary>
function RequiredPackagesOf(const AMainSource: string): TArray<string>;
var
  mText: string;
  mFormat: TFileFormat;
  mEntry: TPackageEntry;
begin
  Result := nil;
  if not SameText(ExtractFileExt(AMainSource), '.dpk') then
  begin
    Exit;
  end;
  try
    mText := TFileEncoding.LoadFromFile(AMainSource, mFormat);
    for mEntry in TPackageReader.Read(mText).Requires do
    begin
      Result := Result + [mEntry.Name];
    end;
  except
    on Exception do
      Result := TArray<string>.Create('?');
  end;
end;

function IndexKnowsOf(const AIndex: ISymbolIndex): TFunc<string, Boolean>;
begin
  Result :=
    function(AName: string): Boolean
    var
      mFound: TUnitIndex;
    begin
      Result := AIndex.FindUnit(AName, mFound);
    end;
end;

function IndexUnitsOf(const AIndex: ISymbolIndex): TFunc<TArray<string>>;
begin
  Result :=
    function: TArray<string>
    var
      mItem: TUnitIndex;
    begin
      Result := nil;
      for mItem in AIndex.Units do
      begin
        Result := Result + [mItem.UnitName];
      end;
    end;
end;

{ TShellPackageLookups }

class function TShellPackageLookups.Provides(const AHold: IPackageLocatorHold): TRulePackageProvides;
begin
  Result :=
    function(const APackage, AUnitName: string): TRulePackageAnswer
    var
      mContains: Boolean;
    begin
      Result := TRulePackageAnswer.Unknown;
      if AHold.Locator.Provides(APackage, AUnitName, mContains) then
      begin
        Result := TRulePackageAnswer.No;
        if mContains then
        begin
          Result := TRulePackageAnswer.Yes;
        end;
      end;
    end;
end;

class function TShellPackageLookups.Requires(const AHold: IPackageLocatorHold): TFunc<string, TArray<string>>;
begin
  Result :=
    function(APackage: string): TArray<string>
    begin
      Result := AHold.Locator.Requires(APackage);
    end;
end;

class function TShellPackageLookups.RuleRequires(const AHold: IPackageLocatorHold): TRulePackageRequires;
begin
  Result :=
    function(const APackage: string): TArray<string>
    begin
      Result := AHold.Locator.Requires(APackage);
    end;
end;

class function TShellPackageLookups.Exists(const AHold: IPackageLocatorHold): TFunc<string, Boolean>;
begin
  Result :=
    function(APackage: string): Boolean
    var
      mContains: Boolean;
    begin
      Result := AHold.Locator.Provides(APackage, APackage, mContains);
    end;
end;

class function TShellPackageLookups.GroupOutputsFor(const AOwnFile: string; const AFiles: TArray<string>;
  const AOptions: TDprojOptions; const ALogger: ILogger): TArray<TUnitLookupGroupOutput>;
var
  mFile: string;
  mSeen: TArray<string>;
  mOutput: TUnitLookupGroupOutput;
begin
  Result := nil;
  mSeen := nil;
  for mFile in AFiles do
  begin
    if SameText(mFile, AOwnFile) or (IndexText(mFile, mSeen) >= 0) then
    begin
      Continue;
    end;
    mSeen := mSeen + [mFile];
    if GroupOutputOf(mFile, AOptions, ALogger, mOutput) then
    begin
      Result := Result + [mOutput];
    end;
  end;
end;

class function TShellPackageLookups.GroupOutputsOf(const AFiles: TFunc<TArray<string>>; const AOwnFile: string;
  const AOptions: TDprojOptions; const ALogger: ILogger): TFunc<TArray<TUnitLookupGroupOutput>>;
var
  mHold: IGroupOutputCacheHold;
begin
  mHold := TGroupOutputCacheHold.Create(TGroupOutputCache.Create(AFiles, AOwnFile, AOptions, ALogger));
  Result := GroupOutputsOfHold(mHold);
end;

class function TShellPackageLookups.UnitLookupFor(const ASource: TShellUnitLookupSource): IRuleUnitLookup;
var
  mSetup: TUnitLookupSetup;
begin
  mSetup := Default(TUnitLookupSetup);
  mSetup.Project := ASource.Project;
  mSetup.LibraryPaths := ASource.LibraryPaths;
  mSetup.LibraryKnown := Length(ASource.LibraryPaths) > 0;
  mSetup.GroupOutputsOf := ASource.GroupOutputsOf;
  if ASource.Installation <> nil then
  begin
    mSetup.BrowsingPaths := ASource.Installation.BrowsingPaths(ASource.Project.Platform);
  end;
  mSetup.RequiredPackages := RequiredPackagesOf(ASource.Project.MainSource);
  mSetup.ListFiles := TSharedUnitListings.ListUnitFilesFunc();
  mSetup.ListFolders := TShellFileAccess.FoldersFunc();
  mSetup.FileExists := TShellFileAccess.ExistsFunc();
  mSetup.ReadText := TShellFileAccess.ReadTextFunc();
  if ASource.Packages <> nil then
  begin
    mSetup.PackageProvides := Provides(ASource.Packages);
    mSetup.PackageExists := Exists(ASource.Packages);
    mSetup.PackageRequires := Requires(ASource.Packages);
  end;
  if ASource.Index <> nil then
  begin
    mSetup.IndexKnows := IndexKnowsOf(ASource.Index);
    mSetup.IndexUnits := IndexUnitsOf(ASource.Index);
  end;
  Result := TUnitLookup.Create(mSetup);
end;

end.
