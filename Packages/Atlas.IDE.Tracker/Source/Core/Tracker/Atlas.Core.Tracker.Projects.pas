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
// - Arbeitskopien (#1926): Eine Zeile kann unter "paths" die Ordner nennen, in
//   denen das Projekt in Git bzw. SVN liegt; der erste ist die
//   Haupt-Arbeitskopie („Beginnen“, Branch, Entwicklung). Ohne "paths" gilt
//   der Ordner der .dproj/.groupproj bzw. der Ordner aus „Gilt für“.
// - Wahl in „Meine Issues“ (#1927): Choices listet je Paar aus Verbindung und
//   Tracker-Projekt die erste Zeile; ChoiceKey „projekt@verbindung“ merkt
//   die Wahl (issues.welcomeProject). Als „Projekt“ gilt dann der Pfad aus
//   „Gilt für“ der Zeile; Resolve nimmt für genau diesen Pfad genau diese Zeile.
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
    /// <summary>Arbeitskopien (#1926), wie eingegeben; die erste ist die Haupt-Arbeitskopie. Leer = Ordner aus
    /// „Gilt für“.</summary>
    Paths: TArray<string>;
    Source: TAtlasTrackerConnectionSource;
    class function Create(const AMatch, AConnection, AProject: string): TAtlasTrackerProjectMapping; static;
    /// <summary>Zeile aus dem Abschnitt tracker der .atlas des Projekts AProjectFile (schreibgeschützt).</summary>
    class function FromTeamFile(const AProjectFile, AConnection, AProject: string): TAtlasTrackerProjectMapping;
      static;
    /// <summary>Project bei .dproj, Group bei .groupproj, sonst Folder; None ohne Pfad.</summary>
    function Kind: TAtlasTrackerMatch;
    function ReadOnly: Boolean;
    /// <summary>Ordner aus „Gilt für“: bei .dproj und .groupproj deren Ordner, sonst der Pfad selbst (wie
    /// eingegeben, ohne „\“ am Ende).</summary>
    function MatchFolder: string;
    /// <summary>Haupt-Arbeitskopie: erster Eintrag aus Paths, sonst MatchFolder.</summary>
    function MainFolder: string;
    /// <summary>Alle Arbeitskopien: Paths, sonst nur MatchFolder.</summary>
    function Folders: TArray<string>;
  end;

  /// <summary>Ein Eintrag der Klappliste „Tracker-Projekt“ (#1927).</summary>
  TAtlasTrackerChoice = record
    /// <summary>„projekt@verbindung“.</summary>
    Key: string;
    Connection: string;
    Project: string;
    /// <summary>„Gilt für“ der ersten Zeile mit diesem Paar; dient als Projekt für Zustand und Auflösung.</summary>
    Match: string;
    /// <summary>Index dieser Zeile in den persönlichen Zeilen.</summary>
    Index: Integer;
    /// <summary>„Verbindung · Projekt“ (ohne Projekt nur die Verbindung).</summary>
    function Caption: string;
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
    /// <summary>issues.welcomeProject für „Alle Tracker-Projekte“ (#1928).</summary>
    cAllKey = '*';
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
    /// <summary>Pfade aus AText, eine je Zeile bzw. getrennt durch „;“: getrimmt, ohne leere und ohne doppelte
    /// (NormalizedPath).</summary>
    class function SplitPaths(const AText: string): TArray<string>; static;
    /// <summary>Haupt-Arbeitskopie für AProjectFile (#1926): erster Pfad der geltenden persönlichen Zeile, sonst
    /// deren Ordner bzw. der Ordner von AProjectFile (bei einem Ordner dieser selbst).</summary>
    class function WorkingFolder(const AMappings: TArray<TAtlasTrackerProjectMapping>;
      const AConnections: TArray<TAtlasTrackerConnection>; const AProjectFile, AGroupFile: string): string; static;
    /// <summary>Einträge der Klappliste „Tracker-Projekt“ (#1927): je Paar aus Verbindung und Tracker-Projekt die
    /// erste persönliche Zeile, deren Verbindung es gibt, in der Reihenfolge der Zeilen.</summary>
    class function Choices(const AMappings: TArray<TAtlasTrackerProjectMapping>;
      const AConnections: TArray<TAtlasTrackerConnection>): TArray<TAtlasTrackerChoice>; static;
    /// <summary>„projekt@verbindung“; '' ohne Verbindung.</summary>
    class function ChoiceKey(const AProject, AConnection: string): string; static;
    /// <summary>Index des Eintrags mit AKey (ohne Groß-/Kleinschreibung); -1 ohne bzw. bei leerem Schlüssel.</summary>
    class function IndexOfChoice(const AChoices: TArray<TAtlasTrackerChoice>; const AKey: string): Integer; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Text.Json;

{ TAtlasTrackerProjectMapping }

class function TAtlasTrackerProjectMapping.Create(const AMatch, AConnection,
  AProject: string): TAtlasTrackerProjectMapping;
begin
  Result.Match := Trim(AMatch);
  Result.Connection := Trim(AConnection);
  Result.Project := Trim(AProject);
  Result.Paths := nil;
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

/// <summary>APath ohne Trenner am Ende (außer bei „C:\“ und „\\“).</summary>
function WithoutTrailingDelimiter(const APath: string): string;
begin
  Result := Trim(APath);
  while (Length(Result) > 3) and CharInSet(Result[Length(Result)], ['\', '/']) do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

/// <summary>Ordner von AFile; Trenner „\“ und „/“ (ExtractFileDir kennt unter Linux nur „/“).</summary>
function FolderOfFile(const AFile: string): string;
begin
  Result := WithoutTrailingDelimiter(Copy(AFile, 1, LastDelimiter('\/', AFile) - 1));
end;

function TAtlasTrackerProjectMapping.MatchFolder: string;
begin
  if Kind in [TAtlasTrackerMatch.Project, TAtlasTrackerMatch.Group] then
  begin
    Result := FolderOfFile(Match);
  end
  else
  begin
    Result := WithoutTrailingDelimiter(Match);
  end;
end;

function TAtlasTrackerProjectMapping.MainFolder: string;
begin
  if Length(Paths) > 0 then
  begin
    Result := WithoutTrailingDelimiter(Paths[0]);
  end
  else
  begin
    Result := MatchFolder;
  end;
end;

function TAtlasTrackerProjectMapping.Folders: TArray<string>;
var
  mIndex: Integer;
begin
  if Length(Paths) = 0 then
  begin
    Result := [MatchFolder];
    Exit;
  end;
  SetLength(Result, Length(Paths));
  for mIndex := 0 to High(Paths) do
  begin
    Result[mIndex] := WithoutTrailingDelimiter(Paths[mIndex]);
  end;
end;

{ TAtlasTrackerChoice }

function TAtlasTrackerChoice.Caption: string;
begin
  Result := Connection;
  if Project <> '' then
  begin
    Result := Result + ' ' + #$00B7 + ' ' + Project;
  end;
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
  begin
    Exit(TAtlasTrackerTarget.Create('', '', '', ''));
  end;
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

/// <summary>Liste von Pfaden aus "paths"; Einträge, die keine Zeichenfolge sind, fallen weg.</summary>
function PathsOf(AObject: TJSONObject): TArray<string>;
var
  mItems: TJSONArray;
  mItem: TJSONValue;
  mTexts: TArray<string>;
begin
  mTexts := nil;
  mItems := TJsonRead.Items(AObject, 'paths');
  if mItems <> nil then
  begin
    for mItem in mItems do
    begin
      if mItem is TJSONString then
      begin
        mTexts := mTexts + [TJSONString(mItem).Value];
      end;
    end;
  end;
  Result := TAtlasTrackerProjects.SplitPaths(string.Join(';', mTexts));
end;

class function TAtlasTrackerProjects.Read(const AJson: string): TArray<TAtlasTrackerProjectMapping>;
var
  mRoot: TJSONValue;
  mItem: TJSONValue;
  mMapping: TAtlasTrackerProjectMapping;
begin
  Result := nil;
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mRoot is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mRoot) do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mMapping := TAtlasTrackerProjectMapping.Create(TJsonRead.Text(TJSONObject(mItem), 'match'),
        TJsonRead.Text(TJSONObject(mItem), 'connection'), TJsonRead.Text(TJSONObject(mItem), 'project'));
      mMapping.Paths := PathsOf(TJSONObject(mItem));
      if (mMapping.Match = '') or (mMapping.Connection = '') or (IndexOfMatch(Result, mMapping.Match) >= 0) then
      begin
        Continue;
      end;
      Result := Result + [mMapping];
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTrackerProjects.ToJson(const AItems: TArray<TAtlasTrackerProjectMapping>): string;
var
  mItem: TAtlasTrackerProjectMapping;
  mParts, mPaths: TArray<string>;
  mPath, mText: string;
begin
  mParts := nil;
  for mItem in AItems do
  begin
    if not mItem.ReadOnly then
    begin
      mText := '{"match": ' + Quoted(mItem.Match) + ', "connection": ' + Quoted(mItem.Connection) +
        ', "project": ' + Quoted(mItem.Project);
      // "paths" nur, wenn gesetzt: Zeilen ohne Arbeitskopien bleiben wie vor #1926.
      if Length(mItem.Paths) > 0 then
      begin
        mPaths := nil;
        for mPath in mItem.Paths do
        begin
          mPaths := mPaths + [Quoted(mPath)];
        end;
        mText := mText + ', "paths": [' + string.Join(', ', mPaths) + ']';
      end;
      mParts := mParts + [mText + '}'];
    end;
  end;
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
  // Gewähltes Tracker-Projekt (#1927): Das „Projekt“ ist genau der Pfad einer Zeile, auch .groupproj und Ordner.
  mIndex := IndexOfMatch(AMappings, AProjectFile);
  if (mIndex < 0) or AMappings[mIndex].ReadOnly or
    (TAtlasTrackerConnections.IndexOfName(AConnections, AMappings[mIndex].Connection) < 0) then
  begin
    // 2.–4. Persönliche Zuordnung.
    mIndex := Find(AMappings, AConnections, AProjectFile, AGroupFile);
  end;
  if mIndex < 0 then
  begin
    Exit;
  end;
  Result.Match := Matches(AMappings[mIndex], AProjectFile, AGroupFile);
  if Result.Match = TAtlasTrackerMatch.None then
  begin
    // Gleicher Pfad wie „Gilt für“ (.groupproj oder Ordner als gewähltes Tracker-Projekt).
    Result.Match := AMappings[mIndex].Kind;
  end;
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
  begin
    mMatches[mIndex] := AItems[mIndex].Match;
  end;
  Result := TAtlasProjectMatching.IndexOfMatch(mMatches, AMatch);
end;

class function TAtlasTrackerProjects.SplitPaths(const AText: string): TArray<string>;
var
  mPart, mPath: string;
  mSeen: TArray<string>;
begin
  Result := nil;
  mSeen := nil;
  for mPart in AText.Replace(#13, #10).Split([#10, ';']) do
  begin
    mPath := WithoutTrailingDelimiter(mPart);
    if (mPath = '') or (TAtlasProjectMatching.IndexOfMatch(mSeen, mPath) >= 0) then
    begin
      Continue;
    end;
    mSeen := mSeen + [mPath];
    Result := Result + [mPath];
  end;
end;

class function TAtlasTrackerProjects.WorkingFolder(const AMappings: TArray<TAtlasTrackerProjectMapping>;
  const AConnections: TArray<TAtlasTrackerConnection>; const AProjectFile, AGroupFile: string): string;
var
  mResolution: TAtlasTrackerResolution;
begin
  Result := '';
  if Trim(AProjectFile) = '' then
  begin
    Exit;
  end;
  // Ohne .atlas: Die .atlas kennt keine Arbeitskopien, ihr Projekt liegt in seinem Ordner.
  mResolution := Resolve(TAtlasTrackerTarget.Create('', '', '', ''), AMappings, AConnections, AProjectFile,
    AGroupFile);
  if mResolution.Found and (mResolution.Index >= 0) and (Length(AMappings[mResolution.Index].Paths) > 0) then
  begin
    Exit(AMappings[mResolution.Index].MainFolder);
  end;
  if TAtlasProjectMatching.KindOf(AProjectFile) = TAtlasTrackerMatch.Folder then
  begin
    Result := WithoutTrailingDelimiter(AProjectFile);
  end
  else
  begin
    Result := FolderOfFile(AProjectFile);
  end;
end;

class function TAtlasTrackerProjects.ChoiceKey(const AProject, AConnection: string): string;
begin
  Result := '';
  if Trim(AConnection) <> '' then
  begin
    Result := Trim(AProject) + '@' + Trim(AConnection);
  end;
end;

class function TAtlasTrackerProjects.Choices(const AMappings: TArray<TAtlasTrackerProjectMapping>;
  const AConnections: TArray<TAtlasTrackerConnection>): TArray<TAtlasTrackerChoice>;
var
  mIndex: Integer;
  mChoice: TAtlasTrackerChoice;
begin
  Result := nil;
  for mIndex := 0 to High(AMappings) do
  begin
    if AMappings[mIndex].ReadOnly or
      (TAtlasTrackerConnections.IndexOfName(AConnections, AMappings[mIndex].Connection) < 0) then
    begin
      Continue;
    end;
    mChoice.Key := ChoiceKey(AMappings[mIndex].Project, AMappings[mIndex].Connection);
    if IndexOfChoice(Result, mChoice.Key) >= 0 then
    begin
      Continue;
    end;
    mChoice.Connection := AMappings[mIndex].Connection;
    mChoice.Project := AMappings[mIndex].Project;
    mChoice.Match := AMappings[mIndex].Match;
    mChoice.Index := mIndex;
    Result := Result + [mChoice];
  end;
end;

class function TAtlasTrackerProjects.IndexOfChoice(const AChoices: TArray<TAtlasTrackerChoice>;
  const AKey: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if Trim(AKey) = '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AChoices) do
  begin
    if SameText(AChoices[mIndex].Key, Trim(AKey)) then
    begin
      Exit(mIndex);
    end;
  end;
end;

end.
