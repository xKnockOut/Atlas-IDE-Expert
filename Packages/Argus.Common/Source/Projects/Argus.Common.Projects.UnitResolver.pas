unit Argus.Common.Projects.UnitResolver;

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

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Argus.Common.Projects.Contract;

type
  TUnitResolver = class
  private
    FProject: TProjectInfo;
    FDirectories: TArray<string>;
    FFileExists: TFunc<string, Boolean>;
    FCache: TDictionary<string, string>;
    FLock: TObject;
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
    function Resolve(const AUnitName: string; const AFromDirectory: string = ''): string;
    procedure Invalidate;
  end;

implementation

uses
  Argus.Common.Projects.Paths;

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
  Directories := TList<string>.Create;
  try
    if AProject.FileName <> '' then
      Directories.Add(TProjectPaths.DirectoryOf(AProject.FileName));
    for Directory in AProject.SearchPaths do
      Directories.Add(Directory);
    for Directory in ALibraryPaths do
      Directories.Add(Directory);
    FDirectories := Directories.ToArray;
  finally
    Directories.Free;
  end;
end;

destructor TUnitResolver.Destroy;
begin
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
      Names.Add(Namespace + '.' + AUnitName);
    Result := Names.ToArray;
  finally
    Names.Free;
  end;
end;

function TUnitResolver.Search(const AUnitName, AFromDirectory: string): string;
var
  ProjectUnit: TProjectUnit;
  Names: TArray<string>;
  Name: string;
  Directory: string;
  Candidate: string;
begin
  Names := Candidates(AUnitName);
  for Name in Names do
    for ProjectUnit in FProject.Units do
      if SameText(ProjectUnit.Name, Name) then
        Exit(ProjectUnit.FileName);
  if AFromDirectory <> '' then
    for Name in Names do
    begin
      Candidate := TProjectPaths.Combine(AFromDirectory, Name + '.pas');
      if FFileExists(Candidate) then
        Exit(Candidate);
    end;
  for Directory in FDirectories do
    for Name in Names do
    begin
      Candidate := TProjectPaths.Combine(Directory, Name + '.pas');
      if FFileExists(Candidate) then
        Exit(Candidate);
    end;
  Result := '';
end;

function TUnitResolver.Resolve(const AUnitName, AFromDirectory: string): string;
var
  Key: string;
begin
  if Trim(AUnitName) = '' then
    Exit('');
  Key := LowerCase(AUnitName) + '|' + LowerCase(AFromDirectory);
  TMonitor.Enter(FLock);
  try
    if FCache.TryGetValue(Key, Result) then
      Exit;
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
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
