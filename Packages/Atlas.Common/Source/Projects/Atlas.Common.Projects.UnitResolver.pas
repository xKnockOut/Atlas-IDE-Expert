unit Atlas.Common.Projects.UnitResolver;

// Findet zu einem Unit-Namen die Quelldatei, so wie der Compiler sucht:
//
//   1. Units, die im Projekt mit Pfad eingetragen sind
//   2. Ordner der verwendenden Datei, dann Projektordner
//   3. Suchpfade des Projekts, dann Bibliotheks- und Quellpfade der Installation
//
// In jedem Ordner wird zuerst der Name selbst gesucht, danach mit jedem
// Unit-Namespace als Präfix (SysUtils → System.SysUtils). Ergebnisse werden
// zwischengespeichert; Invalidate leert den Speicher, z. B. nach
// Dateiänderungen. Die Klasse ist threadsicher.
//
// Mit ListUnits wird jeder Ordner einmal aufgelistet statt für jeden Namen und
// Namespace einzeln nach Dateien zu fragen: Bei Hunderten Suchordnern kostete
// das Auflösen beim Start sonst über 10 s je Projekt.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract;

type
  TUnitResolver = class
  private
    FProject: TProjectInfo;
    FDirectories: TArray<string>;
    FFileExists: TFunc<string, Boolean>;
    FCache: TDictionary<string, string>;
    FLock: TObject;
    FListUnits: TFunc<string, TArray<string>>;
    // Ordner (klein) -> Dateiname ohne Endung (klein) -> Pfad. Unter FLock.
    FListings: TObjectDictionary<string, TDictionary<string, string>>;
    /// <summary>Pfad von AName.pas in ADirectory, über die Auflistung oder FFileExists.</summary>
    function FileIn(const ADirectory, AName: string; out APath: string): Boolean;
    function FileInAny(const ADirectory: string; const ANames: TArray<string>; out APath: string): Boolean;
    function Candidates(const AUnitName: string): TArray<string>;
    function Search(const AUnitName, AFromDirectory: string): string;
  public
    /// <summary>
    /// ALibraryPaths: Bibliotheks- und Quellpfade der Installation in Suchreihenfolge.
    /// AFileExists: Prüfung auf vorhandene Dateien (in Tests vorgegeben).
    /// </summary>
    constructor Create(const AProject: TProjectInfo; const ALibraryPaths: TArray<string>;
      const AFileExists: TFunc<string, Boolean>);
    destructor Destroy; override;
    /// <summary>Absoluter Pfad der .pas-Datei oder '' wenn nicht gefunden.</summary>
    function Resolve(const AUnitName, AFromDirectory: string): string; overload;
    /// <summary>Wie oben ohne Ausgangsordner (AFromDirectory = '').</summary>
    function Resolve(const AUnitName: string): string; overload;
    procedure Invalidate;
    /// <summary>Optional: alle .pas-Dateien eines Ordners (vollständige Pfade). Gesetzt, ersetzt es
    /// die Einzelabfragen per FileExists.</summary>
    property ListUnits: TFunc<string, TArray<string>> read FListUnits write FListUnits;
  end;

implementation

uses
  Atlas.Common.Projects.Paths;

{ TUnitResolver }

constructor TUnitResolver.Create(const AProject: TProjectInfo; const ALibraryPaths: TArray<string>;
  const AFileExists: TFunc<string, Boolean>);
var
  Directories: TList<string>;
  Directory: string;
begin
  inherited Create;
  FProject := AProject;
  FFileExists := AFileExists;
  FCache := TDictionary<string, string>.Create;
  FLock := TObject.Create;
  FListings := TObjectDictionary<string, TDictionary<string, string>>.Create([doOwnsValues]);
  Directories := TList<string>.Create;
  try
    if AProject.FileName <> '' then
    begin
      Directories.Add(TProjectPaths.DirectoryOf(AProject.FileName));
    end;
    for Directory in AProject.SearchPaths do
    begin
      Directories.Add(Directory);
    end;
    for Directory in ALibraryPaths do
    begin
      Directories.Add(Directory);
    end;
    FDirectories := Directories.ToArray;
  finally
    Directories.Free;
  end;
end;

destructor TUnitResolver.Destroy;
begin
  FListings.Free;
  FLock.Free;
  FCache.Free;
  inherited;
end;

function TUnitResolver.Candidates(const AUnitName: string): TArray<string>;
var
  Names: TList<string>;
  Namespace: string;
begin
  Names := TList<string>.Create;
  try
    Names.Add(AUnitName);
    for Namespace in FProject.Namespaces do
    begin
      Names.Add(Namespace + '.' + AUnitName);
    end;
    Result := Names.ToArray;
  finally
    Names.Free;
  end;
end;

function TUnitResolver.FileIn(const ADirectory, AName: string; out APath: string): Boolean;
var
  Key, FileName: string;
  Listing: TDictionary<string, string>;
begin
  if not Assigned(FListUnits) then
  begin
    APath := TProjectPaths.Combine(ADirectory, AName + '.pas');
    Exit(FFileExists(APath));
  end;
  Key := LowerCase(ExcludeTrailingPathDelimiter(ADirectory));
  TMonitor.Enter(FLock);
  try
    if not FListings.TryGetValue(Key, Listing) then
    begin
      Listing := TDictionary<string, string>.Create;
      for FileName in FListUnits(ADirectory) do
      begin
        Listing.AddOrSetValue(LowerCase(ChangeFileExt(ExtractFileName(FileName), '')), FileName);
      end;
      FListings.Add(Key, Listing);
    end;
    Result := Listing.TryGetValue(LowerCase(AName), APath);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TUnitResolver.FileInAny(const ADirectory: string; const ANames: TArray<string>; out APath: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in ANames do
  begin
    if FileIn(ADirectory, mName, APath) then
    begin
      Exit(True);
    end;
  end;
end;

function TUnitResolver.Search(const AUnitName, AFromDirectory: string): string;
var
  mUnit: TProjectUnit;
  mNames: TArray<string>;
  mName, mDirectory: string;
begin
  mNames := Candidates(AUnitName);
  for mName in mNames do
  begin
    for mUnit in FProject.Units do
    begin
      if SameText(mUnit.Name, mName) then
      begin
        Exit(mUnit.FileName);
      end;
    end;
  end;
  if (AFromDirectory <> '') and FileInAny(AFromDirectory, mNames, Result) then
  begin
    Exit;
  end;
  for mDirectory in FDirectories do
  begin
    if FileInAny(mDirectory, mNames, Result) then
    begin
      Exit;
    end;
  end;
  Result := '';
end;

function TUnitResolver.Resolve(const AUnitName: string): string;
begin
  Result := Resolve(AUnitName, '');
end;

function TUnitResolver.Resolve(const AUnitName, AFromDirectory: string): string;
var
  Key: string;
begin
  if Trim(AUnitName) = '' then
  begin
    Exit('');
  end;
  Key := LowerCase(AUnitName) + '|' + LowerCase(AFromDirectory);
  TMonitor.Enter(FLock);
  try
    if FCache.TryGetValue(Key, Result) then
    begin
      Exit;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := Search(Trim(AUnitName), AFromDirectory);
  TMonitor.Enter(FLock);
  try
    FCache.AddOrSetValue(Key, Result);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TUnitResolver.Invalidate;
begin
  TMonitor.Enter(FLock);
  try
    FCache.Clear;
    FListings.Clear;
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
