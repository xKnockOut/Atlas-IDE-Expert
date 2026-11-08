unit Atlas.Core.VersionControl.Detection;

// Arbeitskopie erkennen (#571), ohne Prozess: Vom Ordner aufwärts gilt die
// nächstliegende Verwaltungsablage, .git (Ordner, in Worktrees und Submodulen
// eine Datei) oder .svn (Ordner, seit SVN 1.7 nur in der Wurzel). Liegen
// beide im selben Ordner, gewinnt Git. vcs.provider = git bzw. svn sucht nur
// diese Art, off sucht nicht.

interface

uses
  System.SysUtils,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Tools;

type
  TAtlasVcsDetection = class
  public
    /// <summary>Arbeitskopie für AFolder (Ordner, kein Dateiname); Kind None ohne. ADirExists und AFileExists
    /// prüfen einen vollständigen Pfad.</summary>
    class function Find(const AFolder: string; AProvider: TAtlasVcsProvider;
      const ADirExists, AFileExists: TAtlasVcsPathExists): TAtlasVcsWorkingCopy; overload; static;
    /// <summary>Wie oben mit dem Dateisystem; ein relativer Ordner gilt zum aktuellen Verzeichnis.</summary>
    class function Find(const AFolder: string; AProvider: TAtlasVcsProvider): TAtlasVcsWorkingCopy; overload;
      static;
    /// <summary>AFileName relativ zur Wurzel ARoot der Arbeitskopie; False, wenn die Datei nicht darunter liegt.
    /// Für den Host, der Internals nicht importieren darf (Rollenmatrix, Code-Review A-12).</summary>
    class function RelativePath(const ARoot, AFileName: string; out ARelative: string): Boolean; static;
  end;

implementation

uses
  Atlas.Core.VersionControl.Internals.Text;

class function TAtlasVcsDetection.Find(const AFolder: string; AProvider: TAtlasVcsProvider;
  const ADirExists, AFileExists: TAtlasVcsPathExists): TAtlasVcsWorkingCopy;
var
  mDir, mParent, mCandidate: string;
  mWantGit, mWantSvn: Boolean;
begin
  Result := TAtlasVcsWorkingCopy.Empty;
  mWantGit := (AProvider = TAtlasVcsProvider.Auto) or (AProvider = TAtlasVcsProvider.Git);
  mWantSvn := (AProvider = TAtlasVcsProvider.Auto) or (AProvider = TAtlasVcsProvider.Svn);
  mDir := VcsNormalizeDir(AFolder);
  while (mDir <> '') and (mWantGit or mWantSvn) do
  begin
    mCandidate := IncludeTrailingPathDelimiter(mDir);
    if mWantGit and (ADirExists(mCandidate + '.git') or AFileExists(mCandidate + '.git')) then
    begin
      Result.Kind := TAtlasVcsKind.Git;
      Result.Root := mDir;
      Exit;
    end;
    if mWantSvn and ADirExists(mCandidate + '.svn') then
    begin
      Result.Kind := TAtlasVcsKind.Svn;
      Result.Root := mDir;
      Exit;
    end;
    mParent := VcsNormalizeDir(ExtractFileDir(mDir));
    if (mParent = mDir) or (Length(mParent) >= Length(mDir)) then
    begin
      Break;
    end;
    mDir := mParent;
  end;
end;

class function TAtlasVcsDetection.RelativePath(const ARoot, AFileName: string; out ARelative: string): Boolean;
begin
  Result := VcsRelativePath(ARoot, AFileName, ARelative);
end;

class function TAtlasVcsDetection.Find(const AFolder: string; AProvider: TAtlasVcsProvider): TAtlasVcsWorkingCopy;
begin
  if Trim(AFolder) = '' then
  begin
    Exit(TAtlasVcsWorkingCopy.Empty);
  end;
  Result := Find(ExpandFileName(AFolder), AProvider,
    function(const APath: string): Boolean
    begin
      Result := DirectoryExists(APath);
    end,
    function(const APath: string): Boolean
    begin
      Result := FileExists(APath);
    end);
end;

end.
