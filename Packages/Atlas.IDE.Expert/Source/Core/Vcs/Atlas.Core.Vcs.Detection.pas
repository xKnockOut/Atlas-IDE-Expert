unit Atlas.Core.Vcs.Detection;

// Arbeitskopie erkennen (#571), ohne Prozess: Vom Ordner aufwärts gilt die
// nächstliegende Verwaltungsablage, .git (Ordner, in Worktrees und Submodulen
// eine Datei) oder .svn (Ordner, seit SVN 1.7 nur in der Wurzel). Liegen
// beide im selben Ordner, gewinnt Git. vcs.provider = git bzw. svn sucht nur
// diese Art, off sucht nicht.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools;

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
  end;

implementation

uses
  Atlas.Core.Vcs.Internals.Text;

class function TAtlasVcsDetection.Find(const AFolder: string; AProvider: TAtlasVcsProvider;
  const ADirExists, AFileExists: TAtlasVcsPathExists): TAtlasVcsWorkingCopy;
var
  Dir, Parent, Candidate: string;
  WantGit, WantSvn: Boolean;
begin
  Result := TAtlasVcsWorkingCopy.Empty;
  WantGit := (AProvider = TAtlasVcsProvider.Auto) or (AProvider = TAtlasVcsProvider.Git);
  WantSvn := (AProvider = TAtlasVcsProvider.Auto) or (AProvider = TAtlasVcsProvider.Svn);
  Dir := VcsNormalizeDir(AFolder);
  while (Dir <> '') and (WantGit or WantSvn) do
  begin
    Candidate := IncludeTrailingPathDelimiter(Dir);
    if WantGit and (ADirExists(Candidate + '.git') or AFileExists(Candidate + '.git')) then
    begin
      Result.Kind := TAtlasVcsKind.Git;
      Result.Root := Dir;
      Exit;
    end;
    if WantSvn and ADirExists(Candidate + '.svn') then
    begin
      Result.Kind := TAtlasVcsKind.Svn;
      Result.Root := Dir;
      Exit;
    end;
    Parent := VcsNormalizeDir(ExtractFileDir(Dir));
    if (Parent = Dir) or (Length(Parent) >= Length(Dir)) then
      Break;
    Dir := Parent;
  end;
end;

class function TAtlasVcsDetection.Find(const AFolder: string; AProvider: TAtlasVcsProvider): TAtlasVcsWorkingCopy;
begin
  if Trim(AFolder) = '' then
    Exit(TAtlasVcsWorkingCopy.Empty);
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
