unit Atlas.Core.Tracker.PathSuggestions;

// „Vorschlagen …“ für die Arbeitskopien einer Zeile von issues.projects
// (#1929, Mockup Runde 82 TP4), ohne VCL, Open Tools API und Prozesse.
// Gesucht wird nur dort, wo Atlas schon war: Arbeitskopie der Zeile, deren
// svn:externals bzw. Git-Submodule, die Projekte der .groupproj und bei
// GitHub-Projekten die zuletzt geöffneten Projekte, deren origin auf
// owner/repo zeigt (auch Worktrees desselben Repos). Nie ganze Laufwerke.
// Hier liegen nur die Teile, die Texte auswerten (.groupproj, .git/config,
// Datei .git eines Worktrees, Wert der Liste „Wieder öffnen“) und die Funde
// zusammenführen; das Lesen von Platte und Registry macht die IDE-Seite
// (Atlas.IDE.Tracker.PathSuggestions).

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Warum ein Ordner vorgeschlagen wird.</summary>
  TAtlasTrackerPathReason = (Project, External, Submodule, Group, Remote, Worktree);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Fund für die Liste im Dialog.</summary>
  TAtlasTrackerPathSuggestion = record
    /// <summary>Wurzel der Arbeitskopie, ohne „\“ am Ende.</summary>
    Folder: string;
    /// <summary>"git" bzw. "svn".</summary>
    Kind: string;
    Reason: TAtlasTrackerPathReason;
    /// <summary>Was den Fund belegt: Name der .groupproj, Ordner mit svn:externals bzw. die origin-Adresse.
    /// </summary>
    Detail: string;
    /// <summary>Vorbelegung des Hakens: sicher zugehörig (Projekt, External, Submodul, origin) ja, sonst nein.
    /// </summary>
    Checked: Boolean;
    class function Create(const AFolder, AKind: string; AReason: TAtlasTrackerPathReason;
      const ADetail: string): TAtlasTrackerPathSuggestion; static;
  end;

  TAtlasTrackerPathSuggestions = class
  public
    /// <summary>Projekte aus dem Text AText der Gruppe AGroupFile (Projects Include="…"), absolut zu deren Ordner.
    /// </summary>
    class function GroupProjects(const AGroupFile, AText: string): TArray<string>; static;
    /// <summary>Adresse von remote "origin" aus dem Text einer .git/config; '' ohne.</summary>
    class function OriginUrl(const AConfig: string): string; static;
    /// <summary>"owner/repo" aus einer GitHub-Adresse (https, ssh, git@); '' bei einem anderen Host.</summary>
    class function OwnerRepo(const AUrl: string): string; static;
    /// <summary>Ordner des Repositorys aus dem Text der Datei .git eines Worktrees ("gitdir: …"), absolut zu
    /// AFolder; '' ohne.</summary>
    class function WorktreeGitDir(const AFolder, AText: string): string; static;
    /// <summary>Gemeinsamer Ordner .git zu einem gitdir unter „.git/worktrees/NAME“; sonst AGitDir selbst.
    /// </summary>
    class function CommonGitDir(const AGitDir: string): string; static;
    /// <summary>Pfad einer .dproj bzw. .groupproj aus einem Wert der Liste „Wieder öffnen“ der IDE (durch Komma
    /// getrennt, Pfad in Hochkommas); '' ohne.</summary>
    class function RecentProjectOf(const AValue: string): string; static;
    /// <summary>Gilt AProject (Tracker-Projekt der Zeile) als GitHub "owner/repo"?</summary>
    class function IsOwnerRepo(const AProject: string): Boolean; static;
    /// <summary>AItem anhängen, wenn sein Ordner weder schon in AList noch in AKnown (schon hinterlegt) steht.
    /// </summary>
    class procedure Add(var AList: TArray<TAtlasTrackerPathSuggestion>; const AItem: TAtlasTrackerPathSuggestion;
      const AKnown: TArray<string>); static;
  end;

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Core.Projects.Matching,
  Atlas.Core.Tracker.Projects;

const
  cGitHubHost = 'github.com';
  cGitSuffix = '.git';
  cGitDirPrefix = 'gitdir:';
  cWorktrees = '/worktrees/';
  cOwnerRepoParts = 2;
  cIncludePattern = '<Projects\s+Include\s*=\s*"([^"]+)"';
  cRemotePattern = '^\s*\[\s*remote\s+"([^"]*)"\s*\]\s*$';
  cSectionPattern = '^\s*\[';
  cUrlPattern = '^\s*url\s*=\s*(.+?)\s*$';
  cOrigin = 'origin';
  // Länge von „C:\“.
  cDriveRootLength = 3;
  cProjectExtensions: array[0..1] of string = ('.dproj', '.groupproj');

function IsAbsolutePath(const APath: string): Boolean;
begin
  Result := (Length(APath) >= cDriveRootLength) and (APath[2] = ':') or StartsStr('\\', APath) or
    StartsStr('/', APath);
end;

/// <summary>APath absolut zu ABase; ein absoluter Pfad bleibt, „.“ und „..“ werden aufgelöst. Ohne
/// ExpandFileName: Windows-Pfade auch dort, wo die Tests nicht unter Windows laufen.</summary>
function Absolute(const ABase, APath: string): string;
var
  mPath, mPart, mPrefix: string;
  mParts: TArray<string>;
begin
  mPath := Trim(APath).Replace('/', '\');
  if not IsAbsolutePath(mPath) then
  begin
    mPath := ABase.Replace('/', '\') + '\' + mPath;
  end;
  // UNC (\\server) behält „\\“ am Anfang.
  mPrefix := '';
  if StartsStr('\\', mPath) then
  begin
    mPrefix := '\';
    Delete(mPath, 1, 1);
  end;
  mParts := nil;
  for mPart in mPath.Split(['\']) do
  begin
    if (mPart = '.') or ((mPart = '') and (Length(mParts) > 0)) then
    begin
      Continue;
    end;
    if (mPart = '..') and (Length(mParts) > 1) then
    begin
      Delete(mParts, High(mParts), 1);
      Continue;
    end;
    mParts := mParts + [mPart];
  end;
  Result := TAtlasTrackerProjects.WithoutTrailingDelimiter(mPrefix + string.Join('\', mParts));
end;

{ TAtlasTrackerPathSuggestion }

class function TAtlasTrackerPathSuggestion.Create(const AFolder, AKind: string; AReason: TAtlasTrackerPathReason;
  const ADetail: string): TAtlasTrackerPathSuggestion;
begin
  Result.Folder := TAtlasTrackerProjects.WithoutTrailingDelimiter(AFolder);
  Result.Kind := AKind;
  Result.Reason := AReason;
  Result.Detail := ADetail;
  Result.Checked := AReason in [TAtlasTrackerPathReason.Project, TAtlasTrackerPathReason.External,
    TAtlasTrackerPathReason.Submodule, TAtlasTrackerPathReason.Remote];
end;

{ TAtlasTrackerPathSuggestions }

class function TAtlasTrackerPathSuggestions.GroupProjects(const AGroupFile, AText: string): TArray<string>;
var
  mMatch: TMatch;
  mBase: string;
begin
  Result := nil;
  mBase := ExtractFileDir(AGroupFile);
  for mMatch in TRegEx.Matches(AText, cIncludePattern, [roIgnoreCase]) do
  begin
    Result := Result + [Absolute(mBase, mMatch.Groups[1].Value)];
  end;
end;

class function TAtlasTrackerPathSuggestions.OriginUrl(const AConfig: string): string;
var
  mLine: string;
  mInOrigin: Boolean;
  mMatch: TMatch;
begin
  Result := '';
  mInOrigin := False;
  for mLine in AConfig.Replace(#13, '').Split([#10]) do
  begin
    mMatch := TRegEx.Match(mLine, cRemotePattern, [roIgnoreCase]);
    if mMatch.Success then
    begin
      mInOrigin := SameText(mMatch.Groups[1].Value, cOrigin);
      Continue;
    end;
    if TRegEx.IsMatch(mLine, cSectionPattern) then
    begin
      mInOrigin := False;
      Continue;
    end;
    mMatch := TRegEx.Match(mLine, cUrlPattern, [roIgnoreCase]);
    if mInOrigin and mMatch.Success then
    begin
      Result := mMatch.Groups[1].Value;
      Exit;
    end;
  end;
end;

class function TAtlasTrackerPathSuggestions.OwnerRepo(const AUrl: string): string;
var
  mRest: string;
  mPosition: Integer;
  mParts: TArray<string>;
begin
  Result := '';
  mPosition := Pos(cGitHubHost, LowerCase(AUrl));
  if mPosition = 0 then
  begin
    Exit;
  end;
  // Nach dem Host folgt "/" (https, ssh://) bzw. ":" (git@github.com:owner/repo).
  mRest := Copy(AUrl, mPosition + Length(cGitHubHost), MaxInt);
  if (mRest = '') or not CharInSet(mRest[1], ['/', ':']) then
  begin
    Exit;
  end;
  mRest := Copy(mRest, 2, MaxInt);
  while EndsStr('/', mRest) do
  begin
    Delete(mRest, Length(mRest), 1);
  end;
  if EndsText(cGitSuffix, mRest) then
  begin
    Delete(mRest, Length(mRest) - Length(cGitSuffix) + 1, Length(cGitSuffix));
  end;
  mParts := mRest.Split(['/']);
  if (Length(mParts) = cOwnerRepoParts) and (mParts[0] <> '') and (mParts[1] <> '') then
  begin
    Result := mParts[0] + '/' + mParts[1];
  end;
end;

class function TAtlasTrackerPathSuggestions.WorktreeGitDir(const AFolder, AText: string): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in AText.Replace(#13, '').Split([#10]) do
  begin
    if StartsText(cGitDirPrefix, Trim(mLine)) then
    begin
      Result := Absolute(AFolder, Copy(Trim(mLine), Length(cGitDirPrefix) + 1, MaxInt));
      Exit;
    end;
  end;
end;

class function TAtlasTrackerPathSuggestions.CommonGitDir(const AGitDir: string): string;
var
  mPosition: Integer;
begin
  mPosition := Pos(cWorktrees, LowerCase(AGitDir.Replace('\', '/')));
  Result := AGitDir;
  if mPosition > 0 then
  begin
    Result := Copy(AGitDir, 1, mPosition - 1);
  end;
end;

class function TAtlasTrackerPathSuggestions.RecentProjectOf(const AValue: string): string;
var
  mPart, mExtension: string;
begin
  for mPart in AValue.Split([',']) do
  begin
    Result := AnsiDequotedStr(Trim(mPart), '''');
    for mExtension in cProjectExtensions do
    begin
      if SameText(ExtractFileExt(Result), mExtension) and IsAbsolutePath(Result) then
      begin
        Exit;
      end;
    end;
  end;
  Result := '';
end;

class function TAtlasTrackerPathSuggestions.IsOwnerRepo(const AProject: string): Boolean;
var
  mParts: TArray<string>;
begin
  mParts := Trim(AProject).Split(['/']);
  Result := (Length(mParts) = cOwnerRepoParts) and (mParts[0] <> '') and (mParts[1] <> '');
end;

class procedure TAtlasTrackerPathSuggestions.Add(var AList: TArray<TAtlasTrackerPathSuggestion>;
  const AItem: TAtlasTrackerPathSuggestion; const AKnown: TArray<string>);
var
  mFolders: TArray<string>;
  mItem: TAtlasTrackerPathSuggestion;
begin
  if AItem.Folder = '' then
  begin
    Exit;
  end;
  mFolders := Copy(AKnown);
  for mItem in AList do
  begin
    mFolders := mFolders + [mItem.Folder];
  end;
  if TAtlasProjectMatching.IndexOfMatch(mFolders, AItem.Folder) < 0 then
  begin
    AList := AList + [AItem];
  end;
end;

end.
