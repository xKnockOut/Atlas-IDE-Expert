unit Atlas.Core.Projects.Vcs;

// Versionsverwaltung und Hauptbranch je Projekt (#1286), ohne VCL, Open Tools
// API und Prozess.
// - TAtlasVcsProjectMapping: „Gilt für“ (Pfad einer .dproj, einer .groupproj
//   oder eines Ordners), Art (auto, git, svn, off) und Hauptbranch ('' = raten
//   wie bisher: Git main, sonst master; SVN trunk). Persönliche Zeilen stehen
//   in %APPDATA%\Atlas\settings.json unter vcs.projects
//   (TAtlasPluginSettings.VcsProjects, JSON-Text); der Abschnitt vcs der
//   .atlas (#486) kommt schreibgeschützt dazu.
// - Resolve (für ein Projekt) und ResolveFolder (für einen Ordner, z. B. die
//   Änderungsmarken einer Unit): 1. Abschnitt vcs der .atlas (je Feld: was
//   die Datei setzt, gilt), 2.–4. persönliche Zeile über die gemeinsame
//   Auflösung Atlas.Core.Projects.Matching (dieselbe wie die
//   Tracker-Zuordnung #1261), 5. globales vcs.provider.
// - Covered: persönliche Zeile, die für ein Projekt mit Abschnitt vcs in der
//   .atlas gälte („von .atlas überdeckt“).

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Matching,
  Atlas.Core.Vcs.Contract;

type
  TAtlasVcsProjectMapping = record
    /// <summary>Pfad einer .dproj, einer .groupproj oder eines Ordners, wie eingegeben.</summary>
    Match: string;
    /// <summary>"auto", "git", "svn" oder "off".</summary>
    Provider: string;
    /// <summary>Hauptbranch; '' = raten.</summary>
    MainBranch: string;
    /// <summary>Zeile aus dem Abschnitt vcs der .atlas (schreibgeschützt).</summary>
    Team: Boolean;
    class function Create(const AMatch, AProvider, AMainBranch: string): TAtlasVcsProjectMapping; static;
    /// <summary>Zeile aus dem Abschnitt vcs der .atlas des Projekts AProjectFile; AProvider '' = auto.</summary>
    class function FromTeamFile(const AProjectFile, AProvider, AMainBranch: string): TAtlasVcsProjectMapping;
      static;
    function Kind: TAtlasProjectMatch;
    function ReadOnly: Boolean;
  end;

  /// <summary>Was für ein Projekt bzw. einen Ordner gilt.</summary>
  TAtlasVcsProjectResolution = record
    Provider: TAtlasVcsProvider;
    /// <summary>Woher die Art kommt.</summary>
    Source: TAtlasVcsProviderSource;
    /// <summary>Hauptbranch aus .atlas oder Zeile; '' = raten.</summary>
    MainBranch: string;
    /// <summary>Wodurch die persönliche Zeile gilt (bzw. TeamFile); None ohne Zeile und ohne .atlas.</summary>
    Match: TAtlasProjectMatch;
    /// <summary>Index der persönlichen Zeile; -1 ohne.</summary>
    Index: Integer;
    /// <summary>„Gilt für“ der persönlichen Zeile; '' ohne.</summary>
    SourceMatch: string;
    class function Global(AProvider: TAtlasVcsProvider): TAtlasVcsProjectResolution; static;
  end;

  /// <summary>Was die Seite Versionsverwaltung zur Tabelle Projekte braucht: aktives Projekt, geöffnete .groupproj
  /// (wenn das Projekt darin ist) und die Zeile aus dessen .atlas.</summary>
  TAtlasVcsProjectContext = record
    ProjectFile: string;
    GroupFile: string;
    /// <summary>Zeile aus dem Abschnitt vcs der .atlas (schreibgeschützt); leer ohne vcs.</summary>
    Team: TArray<TAtlasVcsProjectMapping>;
    class function Empty: TAtlasVcsProjectContext; static;
    function HasTeam: Boolean;
  end;

  TAtlasVcsProjects = class
  public const
    /// <summary>Pfad in settings.json.</summary>
    Path = 'vcs.projects';
  public
    /// <summary>"auto", "git", "svn" oder "off" aus AText (klein, ohne Leerraum); sonst "auto".</summary>
    class function ProviderText(const AText: string): string; static;
    /// <summary>Persönliche Zeilen aus dem JSON-Text der Liste; Zeilen ohne „Gilt für“ entfallen, ebenso eine
    /// zweite Zeile für denselben Pfad (der Server meldet sie in settings.json).</summary>
    class function Read(const AJson: string): TArray<TAtlasVcsProjectMapping>; static;
    /// <summary>Persönliche Zeilen als JSON-Liste; Zeilen aus der .atlas entfallen, ein leerer Hauptbranch
    /// ebenso.</summary>
    class function ToJson(const AItems: TArray<TAtlasVcsProjectMapping>): string; static;
    /// <summary>Was für AProjectFile gilt: ATeamProvider/ATeamMainBranch aus der .atlas ('' = nicht gesetzt),
    /// sonst die beste persönliche Zeile (.dproj vor .groupproj AGroupFile vor längstem Ordner), sonst
    /// AGlobal.</summary>
    class function Resolve(const ATeamProvider, ATeamMainBranch: string;
      const AMappings: TArray<TAtlasVcsProjectMapping>; AGlobal: TAtlasVcsProvider; const AProjectFile,
      AGroupFile: string): TAtlasVcsProjectResolution; static;
    /// <summary>Wie Resolve für einen Ordner: .dproj- und .groupproj-Zeilen gelten für ihren Ordner, der längste
    /// passende Ordner gewinnt.</summary>
    class function ResolveFolder(const ATeamProvider, ATeamMainBranch: string;
      const AMappings: TArray<TAtlasVcsProjectMapping>; AGlobal: TAtlasVcsProvider;
      const AFolder: string): TAtlasVcsProjectResolution; static;
    /// <summary>Persönliche Zeile AMapping gälte für AProjectFile, das aber eine .atlas mit Abschnitt vcs hat
    /// (AHasTeam).</summary>
    class function Covered(const AMapping: TAtlasVcsProjectMapping; AHasTeam: Boolean; const AProjectFile,
      AGroupFile: string): Boolean; static;
    /// <summary>Index der Zeile für denselben Pfad; -1 ohne.</summary>
    class function IndexOfMatch(const AItems: TArray<TAtlasVcsProjectMapping>; const AMatch: string): Integer;
      static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON;

{ TAtlasVcsProjectMapping }

class function TAtlasVcsProjectMapping.Create(const AMatch, AProvider,
  AMainBranch: string): TAtlasVcsProjectMapping;
begin
  Result.Match := Trim(AMatch);
  Result.Provider := TAtlasVcsProjects.ProviderText(AProvider);
  Result.MainBranch := Trim(AMainBranch);
  Result.Team := False;
end;

class function TAtlasVcsProjectMapping.FromTeamFile(const AProjectFile, AProvider,
  AMainBranch: string): TAtlasVcsProjectMapping;
begin
  Result := Create(AProjectFile, AProvider, AMainBranch);
  Result.Team := True;
end;

function TAtlasVcsProjectMapping.Kind: TAtlasProjectMatch;
begin
  Result := TAtlasProjectMatching.KindOf(Match);
end;

function TAtlasVcsProjectMapping.ReadOnly: Boolean;
begin
  Result := Team;
end;

{ TAtlasVcsProjectResolution }

class function TAtlasVcsProjectResolution.Global(AProvider: TAtlasVcsProvider): TAtlasVcsProjectResolution;
begin
  Result.Provider := AProvider;
  Result.Source := TAtlasVcsProviderSource.Setting;
  Result.MainBranch := '';
  Result.Match := TAtlasProjectMatch.None;
  Result.Index := -1;
  Result.SourceMatch := '';
end;

{ TAtlasVcsProjectContext }

class function TAtlasVcsProjectContext.Empty: TAtlasVcsProjectContext;
begin
  Result := Default(TAtlasVcsProjectContext);
  Result.Team := nil;
end;

function TAtlasVcsProjectContext.HasTeam: Boolean;
begin
  Result := Length(Team) > 0;
end;

{ TAtlasVcsProjects }

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
  // TJSONNumber erbt von TJSONString: Zahlen zählen nicht als Text.
  if (mValue is TJSONString) and not (mValue is TJSONNumber) then
    Result := TJSONString(mValue).Value;
end;

function MatchesOf(const AItems: TArray<TAtlasVcsProjectMapping>): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AItems));
  for mIndex := 0 to High(AItems) do
    Result[mIndex] := AItems[mIndex].Match;
end;

function PersonalOf(const AItems: TArray<TAtlasVcsProjectMapping>): TArray<Boolean>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AItems));
  for mIndex := 0 to High(AItems) do
    Result[mIndex] := not AItems[mIndex].ReadOnly;
end;

/// <summary>Ergebnis aus .atlas, gefundener Zeile und globalem Wert.</summary>
function Combine(const ATeamProvider, ATeamMainBranch: string; const AMappings: TArray<TAtlasVcsProjectMapping>;
  AGlobal: TAtlasVcsProvider; const AFound: TAtlasProjectMatchResult): TAtlasVcsProjectResolution;
var
  mTeamProvider, mTeamMain: string;
begin
  Result := TAtlasVcsProjectResolution.Global(AGlobal);
  if AFound.Found then
  begin
    Result.Provider := AtlasVcsProviderOf(AMappings[AFound.Index].Provider);
    Result.Source := TAtlasVcsProviderSource.Project;
    Result.MainBranch := AMappings[AFound.Index].MainBranch;
    Result.Match := AFound.Match;
    Result.Index := AFound.Index;
    Result.SourceMatch := AMappings[AFound.Index].Match;
  end;
  // Die .atlas des Teams hat je Feld Vorrang.
  mTeamProvider := Trim(ATeamProvider);
  mTeamMain := Trim(ATeamMainBranch);
  if (mTeamProvider = '') and (mTeamMain = '') then
    Exit;
  Result.Match := TAtlasProjectMatch.TeamFile;
  Result.Index := -1;
  Result.SourceMatch := '';
  if mTeamProvider <> '' then
  begin
    Result.Provider := AtlasVcsProviderOf(mTeamProvider);
    Result.Source := TAtlasVcsProviderSource.TeamFile;
  end;
  if mTeamMain <> '' then
    Result.MainBranch := mTeamMain;
end;

class function TAtlasVcsProjects.ProviderText(const AText: string): string;
begin
  Result := LowerCase(Trim(AText));
  if (Result <> 'git') and (Result <> 'svn') and (Result <> 'off') then
    Result := 'auto';
end;

class function TAtlasVcsProjects.Read(const AJson: string): TArray<TAtlasVcsProjectMapping>;
var
  mRoot: TJSONValue;
  mItem: TJSONValue;
  mMapping: TAtlasVcsProjectMapping;
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
      mMapping := TAtlasVcsProjectMapping.Create(TextOf(TJSONObject(mItem), 'match'),
        TextOf(TJSONObject(mItem), 'provider'), TextOf(TJSONObject(mItem), 'mainBranch'));
      if (mMapping.Match = '') or (IndexOfMatch(Result, mMapping.Match) >= 0) then
        Continue;
      Result := Result + [mMapping];
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasVcsProjects.ToJson(const AItems: TArray<TAtlasVcsProjectMapping>): string;
var
  mItem: TAtlasVcsProjectMapping;
  mParts: TArray<string>;
  mText: string;
begin
  mParts := nil;
  for mItem in AItems do
  begin
    if mItem.ReadOnly or (mItem.Match = '') then
      Continue;
    mText := '{"match": ' + Quoted(mItem.Match) + ', "provider": ' + Quoted(ProviderText(mItem.Provider));
    if mItem.MainBranch <> '' then
      mText := mText + ', "mainBranch": ' + Quoted(mItem.MainBranch);
    mParts := mParts + [mText + '}'];
  end;
  Result := '[' + string.Join(', ', mParts) + ']';
end;

class function TAtlasVcsProjects.Resolve(const ATeamProvider, ATeamMainBranch: string;
  const AMappings: TArray<TAtlasVcsProjectMapping>; AGlobal: TAtlasVcsProvider; const AProjectFile,
  AGroupFile: string): TAtlasVcsProjectResolution;
begin
  Result := Combine(ATeamProvider, ATeamMainBranch, AMappings, AGlobal,
    TAtlasProjectMatching.Find(MatchesOf(AMappings), PersonalOf(AMappings), AProjectFile, AGroupFile));
end;

class function TAtlasVcsProjects.ResolveFolder(const ATeamProvider, ATeamMainBranch: string;
  const AMappings: TArray<TAtlasVcsProjectMapping>; AGlobal: TAtlasVcsProvider;
  const AFolder: string): TAtlasVcsProjectResolution;
begin
  Result := Combine(ATeamProvider, ATeamMainBranch, AMappings, AGlobal,
    TAtlasProjectMatching.FindForFolder(MatchesOf(AMappings), PersonalOf(AMappings), AFolder));
end;

class function TAtlasVcsProjects.Covered(const AMapping: TAtlasVcsProjectMapping; AHasTeam: Boolean;
  const AProjectFile, AGroupFile: string): Boolean;
begin
  Result := AHasTeam and not AMapping.ReadOnly and
    (TAtlasProjectMatching.Matches(AMapping.Match, AProjectFile, AGroupFile) <> TAtlasProjectMatch.None);
end;

class function TAtlasVcsProjects.IndexOfMatch(const AItems: TArray<TAtlasVcsProjectMapping>;
  const AMatch: string): Integer;
begin
  Result := TAtlasProjectMatching.IndexOfMatch(MatchesOf(AItems), AMatch);
end;

end.
