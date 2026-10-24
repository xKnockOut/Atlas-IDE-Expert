unit Atlas.Common.Projects.MissingUnit;

// „Unit nicht gefunden“ (F2613, F1026) nach dem Compilerlauf (#550): wo liegt
// die Unit, die der Compiler nicht fand? Gesucht wird in dieser Reihenfolge:
//   1. Projektordner und Unterordner (bis zur Tiefe 4)
//   2. Ordner und Suchpfade der anderen Projekte der Gruppe
//   3. Suchpfade der anderen Konfigurationen und Plattformen des Projekts
//   4. Bibliothekspfade anderer Plattformen der Installation
//   5. Index (#16)
// Je Ordner zählt Name.pas oder Name.dcu, auch mit einem Unit-Namespace davor.
// Treffer aus 1–3 und 5 ergeben einen Ordner für den Suchpfad (relativ zur
// .dproj, RelativePath); Treffer nur aus 4 heißen: Die Unit gibt es für die
// Plattform des Projekts nicht. Ohne Treffer nennt Searched die durchsuchten
// Orte. Dateizugriffe kommen von außen (Tests ohne Platte).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Common.Projects.Contract;

type
  TMissingUnitPlace = (ProjectFolder, GroupProject, OtherTarget, OtherPlatformLibrary, Index);

  TMissingUnitHit = record
    Place: TMissingUnitPlace;
    /// <summary>Gefundene Datei (.pas oder .dcu), absolut.</summary>
    FileName: string;
    /// <summary>Ordner der Datei, absolut.</summary>
    Folder: string;
    /// <summary>Woher: Projektname, „Debug, Win32“, Plattform der Bibliothek.</summary>
    Detail: string;
  end;

  /// <summary>Konfiguration und Plattform eines Projekts mit ihren Suchpfaden.</summary>
  TMissingUnitTarget = record
    Config: string;
    Platform: string;
    SearchPaths: TArray<string>;
  end;

  /// <summary>Anderes Projekt der Gruppe.</summary>
  TMissingUnitProject = record
    FileName: string;
    SearchPaths: TArray<string>;
  end;

  TMissingUnitSetup = record
    UnitName: string;
    /// <summary>Aktives Projekt (Konfiguration, Plattform, Suchpfade).</summary>
    Project: TProjectInfo;
    /// <summary>Alle Konfigurationen und Plattformen des Projekts; die aktive darf dabei sein.</summary>
    Targets: TArray<TMissingUnitTarget>;
    GroupProjects: TArray<TMissingUnitProject>;
    /// <summary>Plattformen, deren Bibliothekspfade durchsucht werden (ohne die aktive).</summary>
    Platforms: TArray<string>;
    /// <summary>Bibliothekspfade der aktiven Plattform: Die hat der Compiler schon durchsucht.</summary>
    ActiveLibraryPaths: TArray<string>;
    /// <summary>Bibliothekspfade einer Plattform; nil = keine.</summary>
    LibraryPaths: TFunc<string, TArray<string>>;
    /// <summary>Datei der Unit laut Index; nil oder '' = unbekannt.</summary>
    IndexFile: TFunc<string, string>;
    /// <summary>Dateien eines Ordners (vollständige Pfade); leer ohne Ordner.</summary>
    ListFiles: TFunc<string, TArray<string>>;
    /// <summary>Unterordner (vollständige Pfade); nil = keine Unterordner.</summary>
    ListFolders: TFunc<string, TArray<string>>;
    Namespaces: TArray<string>;
  end;

  TMissingUnitSearch = class
  public const
    MaxDepth = 4;
  public
    /// <summary>Plattformen, deren Bibliotheken durchsucht werden.</summary>
    class function KnownPlatforms: TArray<string>; static;
    /// <summary>Unit-Name aus einer Meldung F2613 („Unit 'X' not found“) bzw. F1026 („File not found:
    /// 'X.dcu'“); '' ohne.</summary>
    class function UnitOfMessage(const ACode, AText: string): string; static;
    /// <summary>Treffer in Suchreihenfolge, je Ordner einer; ASearched nennt die durchsuchten Orte.</summary>
    class function Search(const ASetup: TMissingUnitSetup; out ASearched: TArray<string>): TArray<TMissingUnitHit>;
      static;
    /// <summary>AFolder relativ zum Ordner von AProjectFile („Source\Common“, „..\Lib“); absolut auf einem
    /// anderen Laufwerk; „.“ für den Projektordner selbst.</summary>
    class function RelativePath(const AProjectFile, AFolder: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Projects.Paths;

const
  // .pas vor .dcu: Eine Quelle lässt sich auch ins Projekt aufnehmen.
  Extensions: array[0..1] of string = ('.pas', '.dcu');

/// <summary>Dateiname hinter dem letzten \ oder /, unabhängig vom Betriebssystem.</summary>
function NameOf(const APath: string): string;
var
  Index: Integer;
begin
  Index := Length(APath);
  while (Index > 0) and not CharInSet(APath[Index], ['\', '/']) do
    Dec(Index);
  Result := Copy(APath, Index + 1, MaxInt);
end;

/// <summary>Ohne Trenner am Ende.</summary>
function WithoutSeparator(const AFolder: string): string;
begin
  Result := AFolder;
  while (Length(Result) > 1) and CharInSet(Result[Length(Result)], ['\', '/']) do
    Delete(Result, Length(Result), 1);
end;

function FolderKey(const AFolder: string): string;
begin
  Result := LowerCase(StringReplace(AFolder, '/', '\', [rfReplaceAll]));
  while (Length(Result) > 1) and (Result[Length(Result)] = '\') do
    Delete(Result, Length(Result), 1);
end;

class function TMissingUnitSearch.KnownPlatforms: TArray<string>;
begin
  Result := TArray<string>.Create('Win32', 'Win64', 'Linux64', 'OSX64', 'OSXARM64', 'Android', 'Android64',
    'iOSDevice64', 'iOSSimARM64');
end;

class function TMissingUnitSearch.UnitOfMessage(const ACode, AText: string): string;
var
  First, Last: Integer;
begin
  Result := '';
  First := Pos('''', AText);
  if First = 0 then
    Exit;
  Last := Pos('''', AText, First + 1);
  if Last = 0 then
    Exit;
  Result := Trim(Copy(AText, First + 1, Last - First - 1));
  // F1026 nennt die Datei (Foo.dcu, Foo.pas): ohne Endung, ohne Ordner.
  if SameText(Trim(ACode), 'F1026') then
  begin
    Result := NameOf(Result);
    if MatchText(ExtractFileExt(Result), ['.dcu', '.pas', '.dcp', '.o']) then
      Result := ChangeFileExt(Result, '');
  end;
end;

type
  TSearch = class
  private
    FSetup: TMissingUnitSetup;
    FSeen: TArray<string>;
    FHits: TArray<TMissingUnitHit>;
    FSearched: TArray<string>;
    function FileIn(const AFolder: string): string;
    procedure Look(const AFolder: string; APlace: TMissingUnitPlace; const ADetail: string);
  public
    constructor Create(const ASetup: TMissingUnitSetup);
    procedure Run;
  end;

constructor TSearch.Create(const ASetup: TMissingUnitSetup);
begin
  inherited Create;
  FSetup := ASetup;
end;

function TSearch.FileIn(const AFolder: string): string;
var
  Files: TArray<string>;
  FileName, Name, Wanted: string;
  Candidates: TArray<string>;
  Namespace: string;
begin
  Result := '';
  if not Assigned(FSetup.ListFiles) then
    Exit;
  Candidates := [FSetup.UnitName];
  for Namespace in FSetup.Namespaces do
    Candidates := Candidates + [Namespace + '.' + FSetup.UnitName];
  Files := FSetup.ListFiles(AFolder);
  for Wanted in Extensions do
    for Name in Candidates do
      for FileName in Files do
        if SameText(NameOf(FileName), Name + Wanted) then
          Exit(FileName);
end;

procedure TSearch.Look(const AFolder: string; APlace: TMissingUnitPlace; const ADetail: string);
var
  Key, FileName: string;
  Hit: TMissingUnitHit;
begin
  if (AFolder = '') or (Pos('$(', AFolder) > 0) then
    Exit;
  Key := FolderKey(AFolder);
  if IndexStr(Key, FSeen) >= 0 then
    Exit;
  FSeen := FSeen + [Key];
  FileName := FileIn(AFolder);
  if FileName = '' then
    Exit;
  Hit.Place := APlace;
  Hit.FileName := FileName;
  Hit.Folder := TProjectPaths.DirectoryOf(FileName);
  if Hit.Folder = '' then
    Hit.Folder := AFolder;
  Hit.Detail := ADetail;
  FHits := FHits + [Hit];
end;

procedure TSearch.Run;
var
  Root, Folder, IndexFile, Platform: string;
  Queue: TArray<string>;
  Depths: TArray<Integer>;
  Position: Integer;
  Target: TMissingUnitTarget;
  Project: TMissingUnitProject;
  ActiveSearch: TArray<string>;
begin
  // Was der Compiler schon durchsucht hat, zählt nicht als Fund.
  ActiveSearch := FSetup.Project.SearchPaths + FSetup.ActiveLibraryPaths;
  for Folder in ActiveSearch do
    FSeen := FSeen + [FolderKey(Folder)];
  // 1. Projektordner und Unterordner, Breitensuche.
  Root := TProjectPaths.DirectoryOf(FSetup.Project.FileName);
  if Root <> '' then
  begin
    FSearched := FSearched + [Format('Projektordner %s und Unterordner', [Root])];
    // Der Projektordner selbst steht immer im Suchweg des Compilers.
    FSeen := FSeen + [FolderKey(Root)];
    Queue := [Root];
    Depths := [0];
    Position := 0;
    while Position < Length(Queue) do
    begin
      if Depths[Position] > 0 then
        Look(Queue[Position], TMissingUnitPlace.ProjectFolder, NameOf(FSetup.Project.FileName));
      if (Depths[Position] < TMissingUnitSearch.MaxDepth) and Assigned(FSetup.ListFolders) then
        for Folder in FSetup.ListFolders(Queue[Position]) do
        begin
          Queue := Queue + [Folder];
          Depths := Depths + [Depths[Position] + 1];
        end;
      Inc(Position);
    end;
  end;
  // 2. Andere Projekte der Gruppe: ihr Ordner und ihre Suchpfade.
  for Project in FSetup.GroupProjects do
  begin
    FSearched := FSearched + [Format('Projekt %s', [NameOf(Project.FileName)])];
    Look(TProjectPaths.DirectoryOf(Project.FileName), TMissingUnitPlace.GroupProject,
      NameOf(Project.FileName));
    for Folder in Project.SearchPaths do
      Look(Folder, TMissingUnitPlace.GroupProject, NameOf(Project.FileName));
  end;
  // 3. Suchpfade der anderen Konfigurationen und Plattformen.
  for Target in FSetup.Targets do
  begin
    if SameText(Target.Config, FSetup.Project.Config) and SameText(Target.Platform, FSetup.Project.Platform) then
      Continue;
    FSearched := FSearched + [Format('Suchpfade von %s, %s', [Target.Config, Target.Platform])];
    for Folder in Target.SearchPaths do
      Look(Folder, TMissingUnitPlace.OtherTarget, Target.Config + ', ' + Target.Platform);
  end;
  // 4. Bibliothekspfade anderer Plattformen.
  if Assigned(FSetup.LibraryPaths) then
    for Platform in FSetup.Platforms do
    begin
      if SameText(Platform, FSetup.Project.Platform) then
        Continue;
      FSearched := FSearched + [Format('Bibliothek %s', [Platform])];
      for Folder in FSetup.LibraryPaths(Platform) do
        Look(Folder, TMissingUnitPlace.OtherPlatformLibrary, Platform);
    end;
  // 5. Index.
  if Assigned(FSetup.IndexFile) then
  begin
    FSearched := FSearched + ['Index'];
    IndexFile := FSetup.IndexFile(FSetup.UnitName);
    if IndexFile <> '' then
      Look(TProjectPaths.DirectoryOf(IndexFile), TMissingUnitPlace.Index, 'Index');
  end;
end;

class function TMissingUnitSearch.Search(const ASetup: TMissingUnitSetup;
  out ASearched: TArray<string>): TArray<TMissingUnitHit>;
var
  Search: TSearch;
begin
  ASearched := nil;
  Result := nil;
  if Trim(ASetup.UnitName) = '' then
    Exit;
  Search := TSearch.Create(ASetup);
  try
    Search.Run;
    Result := Search.FHits;
    ASearched := Search.FSearched;
  finally
    Search.Free;
  end;
end;

class function TMissingUnitSearch.RelativePath(const AProjectFile, AFolder: string): string;
var
  Base, Target: TArray<string>;
  Common, Index: Integer;
begin
  Base := FolderKey(TProjectPaths.DirectoryOf(AProjectFile)).Split(['\']);
  Target := StringReplace(WithoutSeparator(AFolder), '/', '\', [rfReplaceAll]).Split(['\']);
  // Anderes Laufwerk bzw. andere Wurzel: absolut lassen.
  if (Length(Base) = 0) or (Length(Target) = 0) or not SameText(Base[0], Target[0]) then
    Exit(StringReplace(WithoutSeparator(AFolder), '/', '\', [rfReplaceAll]));
  Common := 0;
  while (Common < Length(Base)) and (Common < Length(Target)) and SameText(Base[Common], Target[Common]) do
    Inc(Common);
  Result := '';
  for Index := Common to High(Base) do
    Result := Result + '..\';
  for Index := Common to High(Target) do
    Result := Result + Target[Index] + '\';
  if Result = '' then
    Result := '.'
  else
    Delete(Result, Length(Result), 1);
end;

end.
