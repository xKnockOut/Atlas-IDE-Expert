unit Atlas.Core.Problems.ScopeProjects;

// Bereichsliste des Fensters „Atlas-Prüfung“ mit einzelnen Projekten (#1843),
// ohne Open Tools API und ohne VCL. Die Liste hat immer die drei festen
// Einträge „Aktuelle Datei“, „Aktuelles Projekt“ und „Projektgruppe“ (in der
// Reihenfolge von TAtlasFindingScope). Ist problems.window.scopeProjects an und
// hat die offene Gruppe mehr als ein Projekt, folgen ein Trennstrich (nicht
// wählbar) und je Projekt der Gruppe ein Eintrag in der Reihenfolge der Gruppe.
// Eine Wahl ist ein Bereich und bei „Projekt“ der Name eines Projekts
// ('' = das jeweils aktive). Ein gewähltes Projekt bleibt, auch wenn ein
// anderes aktiv wird; fehlt es in der Gruppe, gilt wieder das aktive.

interface

uses
  Atlas.Core.Problems.Findings;

type
  /// <summary>Ein Projekt der offenen Gruppe: Name (Dateiname ohne Endung), Projektdatei, aktiv?</summary>
  TAtlasScopeProject = record
    Name: string;
    FileName: string;
    Active: Boolean;
    class function Create(const AFileName: string; AActive: Boolean): TAtlasScopeProject; static;
  end;

  /// <summary>Gewählter Bereich; Project nur bei Scope = Project: Name des Einzelprojekts, '' = aktives Projekt.
  /// </summary>
  TAtlasScopeChoice = record
    Scope: TAtlasFindingScope;
    Project: string;
    class function Create(AScope: TAtlasFindingScope; const AProject: string): TAtlasScopeChoice; static;
    /// <summary>Gleicher Bereich und gleiches Projekt (Groß-/Kleinschreibung egal)?</summary>
    function Same(const AOther: TAtlasScopeChoice): Boolean;
  end;

  /// <summary>Einträge der Bereichsliste: feste Bereiche, Trennstrich, Einzelprojekte.</summary>
  TAtlasScopeList = record
  private
    /// <summary>Alle Projekte der Gruppe bzw. gezeigte Einzelprojekte (leer ohne Einzelprojekte).</summary>
    FAll: TArray<TAtlasScopeProject>;
    FProjects: TArray<TAtlasScopeProject>;
    /// <summary>Index des ersten Projekts, -1 ohne Einzelprojekte.</summary>
    function FirstProject: Integer;
  public
    /// <summary>Liste zu den Projekten der Gruppe; Einzelprojekte nur mit AShowProjects und mehr als einem
    /// Projekt.</summary>
    class function Create(const AProjects: TArray<TAtlasScopeProject>; AShowProjects: Boolean): TAtlasScopeList;
      static;
    /// <summary>Zahl der Einträge samt Trennstrich.</summary>
    function Count: Integer;
    /// <summary>Index des Trennstrichs, -1 ohne Einzelprojekte.</summary>
    function SeparatorIndex: Integer;
    function IsSeparator(AIndex: Integer): Boolean;
    /// <summary>Projekt des Eintrags AIndex; False für feste Einträge, Trennstrich und außerhalb.</summary>
    function ProjectAt(AIndex: Integer; out AProject: TAtlasScopeProject): Boolean;
    /// <summary>Wahl zum Eintrag AIndex; Trennstrich und außerhalb ergeben „Aktuelles Projekt“.</summary>
    function ChoiceAt(AIndex: Integer): TAtlasScopeChoice;
    /// <summary>Eintrag zur Wahl: Einzelprojekt, sonst der feste Eintrag ihres Bereichs.</summary>
    function IndexOf(const AChoice: TAtlasScopeChoice): Integer;
    /// <summary>Wahl, die gilt: Ein Einzelprojekt, das die Gruppe nicht (mehr) hat oder das die Liste nicht zeigt
    /// (Einzelprojekte aus, nur ein Projekt), wird zum aktiven Projekt. Ohne bekannte Projekte (Gruppe noch nicht
    /// geladen) bleibt die Wahl.</summary>
    function Resolve(const AChoice: TAtlasScopeChoice): TAtlasScopeChoice;
    /// <summary>Name des aktiven Projekts, '' ohne.</summary>
    function ActiveName: string;
    /// <summary>Kennung der Einträge (Projekte und aktives); gleich = die Liste muss nicht neu gefüllt werden.
    /// </summary>
    function Key: string;
    property Projects: TArray<TAtlasScopeProject> read FProjects;
  end;

  TAtlasScopeFiles = class
  public
    /// <summary>Alle Dateien der Listen ohne Doppelte (Groß-/Kleinschreibung egal), in der Reihenfolge des ersten
    /// Auftretens.</summary>
    class function Union(const ALists: TArray<TArray<string>>): TArray<string>; static;
    /// <summary>Projekt mit dem Namen AName (Groß-/Kleinschreibung egal); False, wenn keins so heißt.</summary>
    class function Find(const AProjects: TArray<TAtlasScopeProject>; const AName: string;
      out AProject: TAtlasScopeProject): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections;

const
  /// <summary>Feste Einträge: TAtlasFindingScope.</summary>
  cFixedCount = Ord(High(TAtlasFindingScope)) + 1;

{ TAtlasScopeProject }

class function TAtlasScopeProject.Create(const AFileName: string; AActive: Boolean): TAtlasScopeProject;
begin
  Result.FileName := AFileName;
  Result.Name := ChangeFileExt(ExtractFileName(AFileName.Replace('/', PathDelim)), '');
  Result.Active := AActive;
end;

{ TAtlasScopeChoice }

class function TAtlasScopeChoice.Create(AScope: TAtlasFindingScope; const AProject: string): TAtlasScopeChoice;
begin
  Result.Scope := AScope;
  Result.Project := '';
  if AScope = TAtlasFindingScope.Project then
  begin
    Result.Project := Trim(AProject);
  end;
end;

function TAtlasScopeChoice.Same(const AOther: TAtlasScopeChoice): Boolean;
begin
  Result := (Scope = AOther.Scope) and SameText(Project, AOther.Project);
end;

{ TAtlasScopeList }

class function TAtlasScopeList.Create(const AProjects: TArray<TAtlasScopeProject>;
  AShowProjects: Boolean): TAtlasScopeList;
begin
  Result.FAll := Copy(AProjects);
  Result.FProjects := nil;
  if AShowProjects and (Length(AProjects) > 1) then
  begin
    Result.FProjects := Copy(AProjects);
  end;
end;

function TAtlasScopeList.FirstProject: Integer;
begin
  Result := -1;
  if Length(FProjects) > 0 then
  begin
    Result := cFixedCount + 1;
  end;
end;

function TAtlasScopeList.Count: Integer;
begin
  Result := cFixedCount;
  if Length(FProjects) > 0 then
  begin
    Result := cFixedCount + 1 + Length(FProjects);
  end;
end;

function TAtlasScopeList.SeparatorIndex: Integer;
begin
  Result := -1;
  if Length(FProjects) > 0 then
  begin
    Result := cFixedCount;
  end;
end;

function TAtlasScopeList.IsSeparator(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex = SeparatorIndex);
end;

function TAtlasScopeList.ProjectAt(AIndex: Integer; out AProject: TAtlasScopeProject): Boolean;
var
  mOffset: Integer;
begin
  AProject := Default(TAtlasScopeProject);
  mOffset := AIndex - FirstProject;
  Result := (FirstProject >= 0) and (mOffset >= 0) and (mOffset < Length(FProjects));
  if Result then
  begin
    AProject := FProjects[mOffset];
  end;
end;

function TAtlasScopeList.ChoiceAt(AIndex: Integer): TAtlasScopeChoice;
var
  mProject: TAtlasScopeProject;
begin
  if (AIndex >= 0) and (AIndex < cFixedCount) then
  begin
    Exit(TAtlasScopeChoice.Create(TAtlasFindingScope(AIndex), ''));
  end;
  if ProjectAt(AIndex, mProject) then
  begin
    Exit(TAtlasScopeChoice.Create(TAtlasFindingScope.Project, mProject.Name));
  end;
  Result := TAtlasScopeChoice.Create(TAtlasFindingScope.Project, '');
end;

function TAtlasScopeList.IndexOf(const AChoice: TAtlasScopeChoice): Integer;
var
  mIndex: Integer;
begin
  Result := Ord(AChoice.Scope);
  if (AChoice.Scope <> TAtlasFindingScope.Project) or (AChoice.Project = '') then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FProjects) do
  begin
    if SameText(FProjects[mIndex].Name, AChoice.Project) then
    begin
      Exit(FirstProject + mIndex);
    end;
  end;
end;

function TAtlasScopeList.Resolve(const AChoice: TAtlasScopeChoice): TAtlasScopeChoice;
begin
  Result := AChoice;
  if (Length(FAll) > 0) and (Result.Project <> '') and (IndexOf(Result) = Ord(Result.Scope)) then
  begin
    Result.Project := '';
  end;
end;

function TAtlasScopeList.ActiveName: string;
var
  mProject: TAtlasScopeProject;
begin
  Result := '';
  for mProject in FAll do
  begin
    if mProject.Active then
    begin
      Exit(mProject.Name);
    end;
  end;
end;

function TAtlasScopeList.Key: string;
var
  mProject: TAtlasScopeProject;
begin
  Result := Length(FProjects).ToString;
  for mProject in FAll do
  begin
    Result := Result + '|' + mProject.FileName;
    if mProject.Active then
    begin
      Result := Result + '*';
    end;
  end;
end;

{ TAtlasScopeFiles }

class function TAtlasScopeFiles.Union(const ALists: TArray<TArray<string>>): TArray<string>;
var
  mSeen: TDictionary<string, Boolean>;
  mFiles: TList<string>;
  mList: TArray<string>;
  mName: string;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  mFiles := TList<string>.Create;
  try
    for mList in ALists do
    begin
      for mName in mList do
      begin
        if (mName <> '') and mSeen.TryAdd(mName.ToLower, True) then
        begin
          mFiles.Add(mName);
        end;
      end;
    end;
    Result := mFiles.ToArray;
  finally
    mFiles.Free;
    mSeen.Free;
  end;
end;

class function TAtlasScopeFiles.Find(const AProjects: TArray<TAtlasScopeProject>; const AName: string;
  out AProject: TAtlasScopeProject): Boolean;
var
  mProject: TAtlasScopeProject;
begin
  AProject := Default(TAtlasScopeProject);
  for mProject in AProjects do
  begin
    if SameText(mProject.Name, Trim(AName)) then
    begin
      AProject := mProject;
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
