unit Atlas.Core.Tracker.Projects;

// Delphi-Projekte einem Tracker-Projekt zuordnen (#1261), ohne VCL und Open
// Tools API.
// - TAtlasTrackerProjectMapping: „Gilt für“ (Pfad einer .dproj, einer
//   .groupproj oder eines Ordners), Verbindung (Name aus issues.connections,
//   #1260) und Tracker-Projekt (YouTrack "KASSE", GitHub "owner/repo").
//   Persönliche Zeilen stehen in %APPDATA%\Atlas\settings.json unter
//   issues.projects (TAtlasPluginSettings.IssuesProjects, JSON-Text); die
//   Zeile aus dem Abschnitt tracker der .atlas (#486) kommt schreibgeschützt
//   dazu.
// - Resolve: welcher Tracker für ein Projekt gilt (Auflösung gemeinsam mit
//   der Versionsverwaltung je Projekt in Atlas.Core.Projects.Matching, #1286),
//   in dieser Reihenfolge:
//   1. tracker aus der .atlas (Team, Vorrang),
//   2. Zeile für genau diese .dproj,
//   3. Zeile für die geöffnete .groupproj (wenn das Projekt darin ist),
//   4. längster passender Ordner.
//   Pfade vergleicht NormalizedPath ohne Groß-/Kleinschreibung, mit „/“ wie
//   „\“, mit Laufwerk (C:\) und UNC (\\server\freigabe). Eine Zeile, deren
//   Verbindung es nicht (mehr) gibt, zählt nicht; die nächste passende gilt.
// - Covered: Eine persönliche Zeile, die für das Projekt gälte, das schon
//   eine .atlas mit tracker hat, ist „von .atlas überdeckt“.
// Ohne Netz, ohne Dateizugriff.

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Matching,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections;

type
  /// <summary>Wodurch ein Tracker für ein Projekt gilt; zugleich die Art einer Zeile (Project, Group, Folder).
  /// Dieselbe Aufzählung wie bei der Versionsverwaltung je Projekt (#1286).</summary>
  TAtlasTrackerMatch = TAtlasProjectMatch;

  TAtlasTrackerProjectMapping = record
    /// <summary>Pfad einer .dproj, einer .groupproj oder eines Ordners, wie eingegeben.</summary>
    Match: string;
    /// <summary>Name der Verbindung aus issues.connections.</summary>
    Connection: string;
    /// <summary>YouTrack-Projekt-ID ("KASSE"), GitHub "owner/repo".</summary>
    Project: string;
    Source: TAtlasTrackerConnectionSource;
    class function Create(const AMatch, AConnection, AProject: string): TAtlasTrackerProjectMapping; static;
    /// <summary>Zeile aus dem Abschnitt tracker der .atlas des Projekts AProjectFile (schreibgeschützt).</summary>
    class function FromTeamFile(const AProjectFile, AConnection, AProject: string): TAtlasTrackerProjectMapping;
      static;
    /// <summary>Project bei .dproj, Group bei .groupproj, sonst Folder; None ohne Pfad.</summary>
    function Kind: TAtlasTrackerMatch;
    function ReadOnly: Boolean;
  end;

  /// <summary>Welche Zeile bzw. welcher Tracker für ein Projekt gilt.</summary>
  TAtlasTrackerResolution = record
    Match: TAtlasTrackerMatch;
    /// <summary>Index der persönlichen Zeile; -1 bei .atlas oder ohne.</summary>
    Index: Integer;
    Connection: TAtlasTrackerConnection;
    Project: string;
    class function Empty: TAtlasTrackerResolution; static;
    function Found: Boolean;
    /// <summary>Ziel mit Anbieter und Adresse der Verbindung; leer ohne Treffer.</summary>
    function Target(const AQuery: string): TAtlasTrackerTarget;
  end;

  /// <summary>Was die Seite Issue-Tracker zur Tabelle Projekte braucht: aktives Projekt, geöffnete .groupproj
  /// (wenn das Projekt darin ist) und die Zeile aus dessen .atlas.</summary>
  TAtlasTrackerProjectContext = record
    ProjectFile: string;
    GroupFile: string;
    /// <summary>Zeilen aus der .atlas (schreibgeschützt); leer ohne tracker.</summary>
    Team: TArray<TAtlasTrackerProjectMapping>;
    class function Empty: TAtlasTrackerProjectContext; static;
    function HasTeam: Boolean;
  end;

  TAtlasTrackerProjects = class
  public const
    /// <summary>Pfad in settings.json.</summary>
    Path = 'issues.projects';
  public
    /// <summary>Persönliche Zeilen aus dem JSON-Text der Liste; Zeilen ohne „Gilt für“ oder Verbindung entfallen,
    /// ebenso eine zweite Zeile für denselben Pfad (der Server meldet sie in settings.json).</summary>
    class function Read(const AJson: string): TArray<TAtlasTrackerProjectMapping>; static;
    /// <summary>Persönliche Zeilen als JSON-Liste; Zeilen aus der .atlas entfallen.</summary>
    class function ToJson(const AItems: TArray<TAtlasTrackerProjectMapping>): string; static;
    /// <summary>Pfad zum Vergleichen: klein, „\“ statt „/“, ohne „\“ am Ende, doppelte „\“ nur am Anfang
    /// (UNC); '' ohne Pfad.</summary>
    class function NormalizedPath(const APath: string): string; static;
    /// <summary>Zeile gilt für AProjectFile: gleiche .dproj (Project), geöffnete .groupproj AGroupFile (Group)
    /// bzw. Ordner darüber (Folder); sonst None.</summary>
    class function Matches(const AMapping: TAtlasTrackerProjectMapping; const AProjectFile,
      AGroupFile: string): TAtlasTrackerMatch; static;
    /// <summary>Beste persönliche Zeile für AProjectFile (.dproj vor .groupproj vor längstem Ordner); nur Zeilen,
    /// deren Verbindung in AConnections steht. -1 ohne.</summary>
    class function Find(const AMappings: TArray<TAtlasTrackerProjectMapping>;
      const AConnections: TArray<TAtlasTrackerConnection>; const AProjectFile, AGroupFile: string): Integer; static;
    /// <summary>Tracker für AProjectFile: ATeam aus der .atlas (Anbieter und Server bekannt) vor den persönlichen
    /// Zeilen. AGroupFile: geöffnete .groupproj, wenn das Projekt darin ist, sonst ''.</summary>
    class function Resolve(const ATeam: TAtlasTrackerTarget; const AMappings: TArray<TAtlasTrackerProjectMapping>;
      const AConnections: TArray<TAtlasTrackerConnection>; const AProjectFile,
      AGroupFile: string): TAtlasTrackerResolution; static;
    /// <summary>Persönliche Zeile AMapping gälte für AProjectFile, das aber eine .atlas mit tracker hat
    /// (AHasTeam).</summary>
    class function Covered(const AMapping: TAtlasTrackerProjectMapping; AHasTeam: Boolean; const AProjectFile,
      AGroupFile: string): Boolean; static;
    /// <summary>„Gilt für“ für „Aktuelles Projekt hinzufügen“: die geöffnete .groupproj, sonst die .dproj.</summary>
    class function CurrentMatch(const AProjectFile, AGroupFile: string): string; static;
    /// <summary>Index der Zeile für denselben Pfad (NormalizedPath); -1 ohne.</summary>
    class function IndexOfMatch(const AItems: TArray<TAtlasTrackerProjectMapping>; const AMatch: string): Integer;
      static;
  end;

implementation

uses
  System.JSON;

{ TAtlasTrackerProjectMapping }

class function TAtlasTrackerProjectMapping.Create(const AMatch, AConnection,
  AProject: string): TAtlasTrackerProjectMapping;
begin
  Result.Match := Trim(AMatch);
  Result.Connection := Trim(AConnection);
  Result.Project := Trim(AProject);
  Result.Source := TAtlasTrackerConnectionSource.Personal;
end;

class function TAtlasTrackerProjectMapping.FromTeamFile(const AProjectFile, AConnection,
  AProject: string): TAtlasTrackerProjectMapping;
begin
  Result := Create(AProjectFile, AConnection, AProject);
  Result.Source := TAtlasTrackerConnectionSource.TeamFile;
end;

function TAtlasTrackerProjectMapping.Kind: TAtlasTrackerMatch;
begin
  Result := TAtlasProjectMatching.KindOf(Match);
end;

function TAtlasTrackerProjectMapping.ReadOnly: Boolean;
begin
  Result := Source = TAtlasTrackerConnectionSource.TeamFile;
end;

{ TAtlasTrackerProjectContext }

class function TAtlasTrackerProjectContext.Empty: TAtlasTrackerProjectContext;
begin
  Result := Default(TAtlasTrackerProjectContext);
  Result.Team := nil;
end;

function TAtlasTrackerProjectContext.HasTeam: Boolean;
begin
  Result := Length(Team) > 0;
end;

{ TAtlasTrackerResolution }

class function TAtlasTrackerResolution.Empty: TAtlasTrackerResolution;
begin
  Result := Default(TAtlasTrackerResolution);
  Result.Index := -1;
end;

function TAtlasTrackerResolution.Found: Boolean;
begin
  Result := Match <> TAtlasTrackerMatch.None;
end;

function TAtlasTrackerResolution.Target(const AQuery: string): TAtlasTrackerTarget;
begin
  if not Found then
    Exit(TAtlasTrackerTarget.Create('', '', '', ''));
  Result := TAtlasTrackerTarget.Create(Connection.Provider, Connection.Url, Project, AQuery);
end;

{ TAtlasTrackerProjects }

function Quoted(const AText: string): string;
var
  mValue: TJSONString;
begin
  mValue := TJSONString.Create(AText);
  try
    Result := mValue.ToJSON;
  finally
    mValue.Free;
  end;
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
    Result := TJSONString(mValue).Value;
end;

class function TAtlasTrackerProjects.Read(const AJson: string): TArray<TAtlasTrackerProjectMapping>;
var
  mRoot: TJSONValue;
  mItem: TJSONValue;
  mMapping: TAtlasTrackerProjectMapping;
begin
  Result := nil;
  if Trim(AJson) = '' then
    Exit;
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mRoot is TJSONArray) then
      Exit;
    for mItem in TJSONArray(mRoot) do
    begin
      if not (mItem is TJSONObject) then
        Continue;
      mMapping := TAtlasTrackerProjectMapping.Create(TextOf(TJSONObject(mItem), 'match'),
        TextOf(TJSONObject(mItem), 'connection'), TextOf(TJSONObject(mItem), 'project'));
      if (mMapping.Match = '') or (mMapping.Connection = '') or (IndexOfMatch(Result, mMapping.Match) >= 0) then
        Continue;
      Result := Result + [mMapping];
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTrackerProjects.ToJson(const AItems: TArray<TAtlasTrackerProjectMapping>): string;
var
  mItem: TAtlasTrackerProjectMapping;
  mParts: TArray<string>;
begin
  mParts := nil;
  for mItem in AItems do
    if not mItem.ReadOnly then
      mParts := mParts + ['{"match": ' + Quoted(mItem.Match) + ', "connection": ' + Quoted(mItem.Connection) +
        ', "project": ' + Quoted(mItem.Project) + '}'];
  Result := '[' + string.Join(', ', mParts) + ']';
end;

class function TAtlasTrackerProjects.NormalizedPath(const APath: string): string;
begin
  Result := TAtlasProjectMatching.NormalizedPath(APath);
end;

class function TAtlasTrackerProjects.Matches(const AMapping: TAtlasTrackerProjectMapping; const AProjectFile,
  AGroupFile: string): TAtlasTrackerMatch;
begin
  Result := TAtlasProjectMatching.Matches(AMapping.Match, AProjectFile, AGroupFile);
end;

class function TAtlasTrackerProjects.Find(const AMappings: TArray<TAtlasTrackerProjectMapping>;
  const AConnections: TArray<TAtlasTrackerConnection>; const AProjectFile, AGroupFile: string): Integer;
var
  mIndex: Integer;
  mMatches: TArray<string>;
  mUsable: TArray<Boolean>;
begin
  SetLength(mMatches, Length(AMappings));
  SetLength(mUsable, Length(AMappings));
  for mIndex := 0 to High(AMappings) do
  begin
    mMatches[mIndex] := AMappings[mIndex].Match;
    // Ohne Verbindung (gelöscht, umbenannt) kann die Zeile keinen Tracker liefern.
    mUsable[mIndex] := not AMappings[mIndex].ReadOnly and
      (TAtlasTrackerConnections.IndexOfName(AConnections, AMappings[mIndex].Connection) >= 0);
  end;
  Result := TAtlasProjectMatching.Find(mMatches, mUsable, AProjectFile, AGroupFile).Index;
end;

class function TAtlasTrackerProjects.Resolve(const ATeam: TAtlasTrackerTarget;
  const AMappings: TArray<TAtlasTrackerProjectMapping>; const AConnections: TArray<TAtlasTrackerConnection>;
  const AProjectFile, AGroupFile: string): TAtlasTrackerResolution;
var
  mIndex: Integer;
begin
  Result := TAtlasTrackerResolution.Empty;
  // 1. Die .atlas des Teams hat Vorrang.
  if (ATeam.Provider <> '') and (ATeam.Server <> '') then
  begin
    Result.Match := TAtlasTrackerMatch.TeamFile;
    Result.Connection := TAtlasTrackerConnection.FromTeamFile(ChangeFileExt(ExtractFileName(AProjectFile), ''), ATeam);
    Result.Project := ATeam.Project;
    Exit;
  end;
  // 2.–4. Persönliche Zuordnung.
  mIndex := Find(AMappings, AConnections, AProjectFile, AGroupFile);
  if mIndex < 0 then
    Exit;
  Result.Match := Matches(AMappings[mIndex], AProjectFile, AGroupFile);
  Result.Index := mIndex;
  Result.Connection := AConnections[TAtlasTrackerConnections.IndexOfName(AConnections, AMappings[mIndex].Connection)];
  Result.Project := AMappings[mIndex].Project;
end;

class function TAtlasTrackerProjects.Covered(const AMapping: TAtlasTrackerProjectMapping; AHasTeam: Boolean;
  const AProjectFile, AGroupFile: string): Boolean;
begin
  Result := AHasTeam and not AMapping.ReadOnly and
    (Matches(AMapping, AProjectFile, AGroupFile) <> TAtlasTrackerMatch.None);
end;

class function TAtlasTrackerProjects.CurrentMatch(const AProjectFile, AGroupFile: string): string;
begin
  Result := TAtlasProjectMatching.CurrentMatch(AProjectFile, AGroupFile);
end;

class function TAtlasTrackerProjects.IndexOfMatch(const AItems: TArray<TAtlasTrackerProjectMapping>;
  const AMatch: string): Integer;
var
  mIndex: Integer;
  mMatches: TArray<string>;
begin
  SetLength(mMatches, Length(AItems));
  for mIndex := 0 to High(AItems) do
    mMatches[mIndex] := AItems[mIndex].Match;
  Result := TAtlasProjectMatching.IndexOfMatch(mMatches, AMatch);
end;

end.
