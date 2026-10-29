unit Atlas.Core.Projects.Matching;

// Zuordnung „Gilt für“ (#1261, #1286): welche Zeile einer persönlichen Liste
// für ein Delphi-Projekt oder einen Ordner gilt. Gemeinsame Auflösung für die
// Tracker-Zuordnung (issues.projects, Atlas.Core.Tracker.Projects) und die
// Versionsverwaltung je Projekt (vcs.projects, Atlas.Core.Projects.Vcs); die
// Nutzlast einer Zeile (Verbindung, Art, Hauptbranch) kennt diese Unit nicht.
// Eingabe: die Pfade „Gilt für“ der Zeilen und je Zeile, ob sie zählen darf;
// Ausgabe: die gewinnende Zeile samt Grund (Project, Group, Folder).
// - Für ein Projekt (Find): 1. Zeile für genau diese .dproj, 2. Zeile für die
//   geöffnete .groupproj, 3. längster passender Ordner. Die .atlas des Teams
//   (TeamFile) prüft der Aufrufer vorher, weil nur er ihren Inhalt kennt.
// - Für einen Ordner (FindForFolder, z. B. Änderungsmarken einer Unit): Eine
//   .dproj- bzw. .groupproj-Zeile gilt für ihren Ordner und alles darunter;
//   es gewinnt der längste passende Ordner, bei Gleichstand .dproj vor
//   .groupproj vor Ordner. So gilt eine genauere Ordnerzeile (Fremd\Lib)
//   innerhalb eines Projekts.
// - Pfade: ohne Groß-/Kleinschreibung, „/“ wie „\“, mit Laufwerk (C:\) und UNC
//   (\\server\freigabe); nur ganze Ordner (C:\Projekte\Kasse gilt nicht für
//   C:\Projekte\Kassenbuch).
// Ohne Dateizugriff, ohne VCL und Open Tools API.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Wodurch eine Zeile gilt; zugleich die Art einer Zeile (Project, Group, Folder). TeamFile: Wert aus
  /// der .atlas (setzt der Aufrufer).</summary>
  TAtlasProjectMatch = (None, TeamFile, Project, Group, Folder);
{$SCOPEDENUMS OFF}

  /// <summary>Gewinnende Zeile samt Grund.</summary>
  TAtlasProjectMatchResult = record
    /// <summary>Index der Zeile; -1 ohne.</summary>
    Index: Integer;
    Match: TAtlasProjectMatch;
    class function Empty: TAtlasProjectMatchResult; static;
    function Found: Boolean;
  end;

  TAtlasProjectMatching = class
  public
    /// <summary>Pfad zum Vergleichen: klein, „\“ statt „/“, ohne „\“ am Ende, doppelte „\“ nur am Anfang
    /// (UNC); '' ohne Pfad.</summary>
    class function NormalizedPath(const APath: string): string; static;
    /// <summary>Project bei .dproj, Group bei .groupproj, sonst Folder; None ohne Pfad.</summary>
    class function KindOf(const AMatch: string): TAtlasProjectMatch; static;
    /// <summary>Zeile AMatch gilt für AProjectFile: gleiche .dproj (Project), geöffnete .groupproj AGroupFile
    /// (Group) bzw. Ordner darüber (Folder); sonst None.</summary>
    class function Matches(const AMatch, AProjectFile, AGroupFile: string): TAtlasProjectMatch; static;
    /// <summary>Ordner, für den eine Zeile bei FindForFolder gilt: bei .dproj und .groupproj deren Ordner, sonst
    /// der Pfad selbst (normalisiert).</summary>
    class function FolderOf(const AMatch: string): string; static;
    /// <summary>Beste Zeile für AProjectFile (.dproj vor .groupproj vor längstem Ordner). AUsable: je Zeile, ob
    /// sie zählen darf (z. B. Verbindung vorhanden); kürzer als AMatches = übrige Zeilen zählen.</summary>
    class function Find(const AMatches: TArray<string>; const AUsable: TArray<Boolean>; const AProjectFile,
      AGroupFile: string): TAtlasProjectMatchResult; static;
    /// <summary>Beste Zeile für den Ordner AFolder (längster passender Ordner, bei Gleichstand .dproj vor
    /// .groupproj vor Ordner).</summary>
    class function FindForFolder(const AMatches: TArray<string>; const AUsable: TArray<Boolean>;
      const AFolder: string): TAtlasProjectMatchResult; static;
    /// <summary>Index der Zeile für denselben Pfad; -1 ohne.</summary>
    class function IndexOfMatch(const AMatches: TArray<string>; const AMatch: string): Integer; static;
    /// <summary>„Gilt für“ für „Aktuelles Projekt hinzufügen“: die geöffnete .groupproj, sonst die .dproj.</summary>
    class function CurrentMatch(const AProjectFile, AGroupFile: string): string; static;
  end;

implementation

const
  cProjectExt = '.dproj';
  cGroupExt = '.groupproj';

{ TAtlasProjectMatchResult }

class function TAtlasProjectMatchResult.Empty: TAtlasProjectMatchResult;
begin
  Result.Index := -1;
  Result.Match := TAtlasProjectMatch.None;
end;

function TAtlasProjectMatchResult.Found: Boolean;
begin
  Result := Match <> TAtlasProjectMatch.None;
end;

{ TAtlasProjectMatching }

function Usable(const AUsable: TArray<Boolean>; AIndex: Integer): Boolean;
begin
  Result := (AIndex > High(AUsable)) or AUsable[AIndex];
end;

class function TAtlasProjectMatching.NormalizedPath(const APath: string): string;
var
  mUnc: Boolean;
begin
  Result := LowerCase(Trim(APath)).Replace('/', '\');
  if Result = '' then
    Exit;
  // \\server\freigabe bleibt am Anfang doppelt; sonst fallen doppelte Trenner weg (C:\\Projekte).
  mUnc := Result.StartsWith('\\');
  if mUnc then
    Delete(Result, 1, 2);
  while Result.Contains('\\') do
    Result := Result.Replace('\\', '\');
  if mUnc then
    Result := '\\' + Result;
  while Result.EndsWith('\') and (Length(Result) > 2) do
    Delete(Result, Length(Result), 1);
end;

class function TAtlasProjectMatching.KindOf(const AMatch: string): TAtlasProjectMatch;
var
  mExt: string;
begin
  if Trim(AMatch) = '' then
    Exit(TAtlasProjectMatch.None);
  mExt := ExtractFileExt(NormalizedPath(AMatch));
  if mExt = cProjectExt then
    Result := TAtlasProjectMatch.Project
  else if mExt = cGroupExt then
    Result := TAtlasProjectMatch.Group
  else
    Result := TAtlasProjectMatch.Folder;
end;

class function TAtlasProjectMatching.Matches(const AMatch, AProjectFile, AGroupFile: string): TAtlasProjectMatch;
var
  mMatch, mProject: string;
begin
  Result := TAtlasProjectMatch.None;
  mMatch := NormalizedPath(AMatch);
  mProject := NormalizedPath(AProjectFile);
  if (mMatch = '') or (mProject = '') then
    Exit;
  case KindOf(AMatch) of
    TAtlasProjectMatch.Project:
      if mMatch = mProject then
        Result := TAtlasProjectMatch.Project;
    TAtlasProjectMatch.Group:
      if mMatch = NormalizedPath(AGroupFile) then
        Result := TAtlasProjectMatch.Group;
    TAtlasProjectMatch.Folder:
      // Nur ganze Ordner: C:\Projekte\Kasse gilt nicht für C:\Projekte\Kassenbuch\X.dproj.
      if mProject.StartsWith(mMatch + '\') then
        Result := TAtlasProjectMatch.Folder;
  else
    // Ohne Pfad gilt die Zeile nirgends.
  end;
end;

class function TAtlasProjectMatching.FolderOf(const AMatch: string): string;
begin
  Result := NormalizedPath(AMatch);
  // Trenner selbst suchen: ExtractFileDir kennt unter Linux nur „/“.
  if KindOf(AMatch) in [TAtlasProjectMatch.Project, TAtlasProjectMatch.Group] then
    Result := NormalizedPath(Copy(Result, 1, LastDelimiter('\', Result) - 1));
end;

class function TAtlasProjectMatching.Find(const AMatches: TArray<string>; const AUsable: TArray<Boolean>;
  const AProjectFile, AGroupFile: string): TAtlasProjectMatchResult;
var
  mIndex, mFolderLength: Integer;
  mProject, mGroup, mFolder: Integer;
begin
  Result := TAtlasProjectMatchResult.Empty;
  mProject := -1;
  mGroup := -1;
  mFolder := -1;
  mFolderLength := -1;
  for mIndex := 0 to High(AMatches) do
  begin
    if not Usable(AUsable, mIndex) then
      Continue;
    case Matches(AMatches[mIndex], AProjectFile, AGroupFile) of
      TAtlasProjectMatch.Project:
        if mProject < 0 then
          mProject := mIndex;
      TAtlasProjectMatch.Group:
        if mGroup < 0 then
          mGroup := mIndex;
      TAtlasProjectMatch.Folder:
        if Length(NormalizedPath(AMatches[mIndex])) > mFolderLength then
        begin
          mFolder := mIndex;
          mFolderLength := Length(NormalizedPath(AMatches[mIndex]));
        end;
    else
      // Gilt nicht für dieses Projekt.
    end;
  end;
  if mProject >= 0 then
  begin
    Result.Index := mProject;
    Result.Match := TAtlasProjectMatch.Project;
  end
  else if mGroup >= 0 then
  begin
    Result.Index := mGroup;
    Result.Match := TAtlasProjectMatch.Group;
  end
  else if mFolder >= 0 then
  begin
    Result.Index := mFolder;
    Result.Match := TAtlasProjectMatch.Folder;
  end;
end;

class function TAtlasProjectMatching.FindForFolder(const AMatches: TArray<string>; const AUsable: TArray<Boolean>;
  const AFolder: string): TAtlasProjectMatchResult;
var
  mIndex, mLength, mBestLength: Integer;
  mFolder, mRowFolder: string;
  mKind: TAtlasProjectMatch;
begin
  Result := TAtlasProjectMatchResult.Empty;
  mFolder := NormalizedPath(AFolder);
  if mFolder = '' then
    Exit;
  mBestLength := -1;
  for mIndex := 0 to High(AMatches) do
  begin
    if not Usable(AUsable, mIndex) then
      Continue;
    mKind := KindOf(AMatches[mIndex]);
    mRowFolder := FolderOf(AMatches[mIndex]);
    if (mKind = TAtlasProjectMatch.None) or (mRowFolder = '') then
      Continue;
    if (mFolder <> mRowFolder) and not mFolder.StartsWith(mRowFolder + '\') then
      Continue;
    mLength := Length(mRowFolder);
    // Längster Ordner; bei Gleichstand .dproj vor .groupproj vor Ordner (Reihenfolge der Aufzählung).
    if (mLength > mBestLength) or ((mLength = mBestLength) and (Ord(mKind) < Ord(Result.Match))) then
    begin
      mBestLength := mLength;
      Result.Index := mIndex;
      Result.Match := mKind;
    end;
  end;
end;

class function TAtlasProjectMatching.IndexOfMatch(const AMatches: TArray<string>; const AMatch: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AMatches) do
    if NormalizedPath(AMatches[mIndex]) = NormalizedPath(AMatch) then
      Exit(mIndex);
  Result := -1;
end;

class function TAtlasProjectMatching.CurrentMatch(const AProjectFile, AGroupFile: string): string;
begin
  if Trim(AGroupFile) <> '' then
    Result := Trim(AGroupFile)
  else
    Result := Trim(AProjectFile);
end;

end.
