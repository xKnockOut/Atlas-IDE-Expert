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
  begin
    Dec(Index);
  end;
  Result := Copy(APath, Index + 1, MaxInt);
end;

/// <summary>Ohne Trenner am Ende.</summary>
function WithoutSeparator(const AFolder: string): string;
begin
  Result := AFolder;
  while (Length(Result) > 1) and CharInSet(Result[Length(Result)], ['\', '/']) do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

function FolderKey(const AFolder: string): string;
begin
  Result := LowerCase(StringReplace(AFolder, '/', '\', [rfReplaceAll]));
  while (Length(Result) > 1) and (Result[Length(Result)] = '\') do
  begin
    Delete(Result, Length(Result), 1);
  end;
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
  begin
    Exit;
  end;
  Last := Pos('''', AText, First + 1);
  if Last = 0 then
  begin
    Exit;
  end;
  Result := Trim(Copy(AText, First + 1, Last - First - 1));
  // F1026 nennt die Datei (Foo.dcu, Foo.pas): ohne Endung, ohne Ordner.
  if SameText(Trim(ACode), 'F1026') then
  begin
    Result := NameOf(Result);
    if MatchText(ExtractFileExt(Result), ['.dcu', '.pas', '.dcp', '.o']) then
    begin
      Result := ChangeFileExt(Result, '');
    end;
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
    procedure LookInProjectFolder;
    procedure LookInGroup;
    procedure LookInOtherTargets;
    procedure LookInOtherLibraries;
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
  begin
    Exit;
  end;
  Candidates := [FSetup.UnitName];
  for Namespace in FSetup.Namespaces do
  begin
    Candidates := Candidates + [Namespace + '.' + FSetup.UnitName];
  end;
  Files := FSetup.ListFiles(AFolder);
  for Wanted in Extensions do
  begin
    for Name in Candidates do
    begin
      for FileName in Files do
      begin
        if SameText(NameOf(FileName), Name + Wanted) then
        begin
          Exit(FileName);
        end;
      end;
    end;
  end;
end;

procedure TSearch.Look(const AFolder: string; APlace: TMissingUnitPlace; const ADetail: string);
var
  Key, FileName: string;
  Hit: TMissingUnitHit;
begin
  if (AFolder = '') or (Pos('$(', AFolder) > 0) then
  begin
    Exit;
  end;
  Key := FolderKey(AFolder);
  if IndexStr(Key, FSeen) >= 0 then
  begin
    Exit;
  end;
  FSeen := FSeen + [Key];
  FileName := FileIn(AFolder);
  if FileName = '' then
  begin
    Exit;
  end;
  Hit.Place := APlace;
  Hit.FileName := FileName;
  Hit.Folder := TProjectPaths.DirectoryOf(FileName);
  if Hit.Folder = '' then
  begin
    Hit.Folder := AFolder;
  end;
  Hit.Detail := ADetail;
  FHits := FHits + [Hit];
end;

procedure TSearch.LookInProjectFolder;
var
  mRoot, mFolder: string;
  mQueue: TArray<string>;
  mDepths: TArray<Integer>;
  mPosition: Integer;
begin
  mRoot := TProjectPaths.DirectoryOf(FSetup.Project.FileName);
  if mRoot = '' then
  begin
    Exit;
  end;
  FSearched := FSearched + [Format('Projektordner %s und Unterordner', [mRoot])];
  // Der Projektordner selbst steht immer im Suchweg des Compilers.
  FSeen := FSeen + [FolderKey(mRoot)];
  mQueue := [mRoot];
  mDepths := [0];
  mPosition := 0;
  while mPosition < Length(mQueue) do
  begin
    if mDepths[mPosition] > 0 then
    begin
      Look(mQueue[mPosition], TMissingUnitPlace.ProjectFolder, NameOf(FSetup.Project.FileName));
    end;
    if (mDepths[mPosition] < TMissingUnitSearch.MaxDepth) and Assigned(FSetup.ListFolders) then
    begin
      for mFolder in FSetup.ListFolders(mQueue[mPosition]) do
      begin
        mQueue := mQueue + [mFolder];
        mDepths := mDepths + [mDepths[mPosition] + 1];
      end;
    end;
    Inc(mPosition);
  end;
end;

procedure TSearch.LookInGroup;
var
  mProject: TMissingUnitProject;
  mFolder: string;
begin
  for mProject in FSetup.GroupProjects do
  begin
    FSearched := FSearched + [Format('Projekt %s', [NameOf(mProject.FileName)])];
    Look(TProjectPaths.DirectoryOf(mProject.FileName), TMissingUnitPlace.GroupProject, NameOf(mProject.FileName));
    for mFolder in mProject.SearchPaths do
    begin
      Look(mFolder, TMissingUnitPlace.GroupProject, NameOf(mProject.FileName));
    end;
  end;
end;

procedure TSearch.LookInOtherTargets;
var
  mTarget: TMissingUnitTarget;
  mFolder: string;
begin
  for mTarget in FSetup.Targets do
  begin
    if SameText(mTarget.Config, FSetup.Project.Config) and SameText(mTarget.Platform, FSetup.Project.Platform) then
    begin
      Continue;
    end;
    FSearched := FSearched + [Format('Suchpfade von %s, %s', [mTarget.Config, mTarget.Platform])];
    for mFolder in mTarget.SearchPaths do
    begin
      Look(mFolder, TMissingUnitPlace.OtherTarget, mTarget.Config + ', ' + mTarget.Platform);
    end;
  end;
end;

procedure TSearch.LookInOtherLibraries;
var
  mPlatform, mFolder: string;
begin
  if not Assigned(FSetup.LibraryPaths) then
  begin
    Exit;
  end;
  for mPlatform in FSetup.Platforms do
  begin
    if SameText(mPlatform, FSetup.Project.Platform) then
    begin
      Continue;
    end;
    FSearched := FSearched + [Format('Bibliothek %s', [mPlatform])];
    for mFolder in FSetup.LibraryPaths(mPlatform) do
    begin
      Look(mFolder, TMissingUnitPlace.OtherPlatformLibrary, mPlatform);
    end;
  end;
end;

procedure TSearch.Run;
var
  mFolder, mIndexFile: string;
begin
  // Was der Compiler schon durchsucht hat, zählt nicht als Fund.
  for mFolder in FSetup.Project.SearchPaths + FSetup.ActiveLibraryPaths do
  begin
    FSeen := FSeen + [FolderKey(mFolder)];
  end;
  // 1. Projektordner und Unterordner, Breitensuche.
  LookInProjectFolder;
  // 2. Andere Projekte der Gruppe: ihr Ordner und ihre Suchpfade.
  LookInGroup;
  // 3. Suchpfade der anderen Konfigurationen und Plattformen.
  LookInOtherTargets;
  // 4. Bibliothekspfade anderer Plattformen.
  LookInOtherLibraries;
  // 5. Index.
  if Assigned(FSetup.IndexFile) then
  begin
    FSearched := FSearched + ['Index'];
    mIndexFile := FSetup.IndexFile(FSetup.UnitName);
    if mIndexFile <> '' then
    begin
      Look(TProjectPaths.DirectoryOf(mIndexFile), TMissingUnitPlace.Index, 'Index');
    end;
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
  begin
    Exit;
  end;
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
  begin
    Exit(StringReplace(WithoutSeparator(AFolder), '/', '\', [rfReplaceAll]));
  end;
  Common := 0;
  while (Common < Length(Base)) and (Common < Length(Target)) and SameText(Base[Common], Target[Common]) do
  begin
    Inc(Common);
  end;
  Result := '';
  for Index := Common to High(Base) do
  begin
    Result := Result + '..\';
  end;
  for Index := Common to High(Target) do
  begin
    Result := Result + Target[Index] + '\';
  end;
  if Result = '' then
  begin
    Result := '.';
  end
  else
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

end.
