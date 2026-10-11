unit Atlas.Common.Mcp.Paths;

// Pfadregeln der MCP-Werkzeuge (#99): Jeder Pfadparameter wird aufgelöst
// (relativ zum Arbeitsordner), normalisiert ("..", "." und Trenner) und – mit
// dem hereingereichten Kanonisierer – von Junctions, Symlinks und subst-
// Laufwerken befreit. Lesen ist erlaubt im Arbeitsordner und in den
// Include-Pfaden des Arbeitsbereichs (Suchpfade des Projekts, Bibliothekspfade
// des Compilers). Alles andere ergibt einen Werkzeugfehler mit Begründung.
// Ohne Windows-Abhängigkeit: den Kanonisierer liefert die Shell.

interface

uses
  System.SysUtils;

type
  TMcpPathGuard = class
  private
    FRoot: string;
    FExtraRoots: TFunc<TArray<string>>;
    FCanonicalize: TFunc<string, string>;
    function Normalize(const APath: string): string;
  public
    /// <summary>ARoot: Arbeitsordner; AExtraRoots: weitere erlaubte Ordner (zur Laufzeit, z. B. erst nach dem
    /// Laden des Projekts bekannt); ACanonicalize: optional, löst Verknüpfungen auf.</summary>
    constructor Create(const ARoot: string; const AExtraRoots: TFunc<TArray<string>> = nil;
      const ACanonicalize: TFunc<string, string> = nil);
    /// <summary>Absoluter, geprüfter Pfad zu APath; EMcpToolError außerhalb der erlaubten Ordner.</summary>
    function Resolve(const APath: string): string;
    /// <summary>APath (absolut, normalisiert) liegt in AFolder oder ist AFolder.</summary>
    class function IsInside(const AFolder, APath: string): Boolean; static;
    property Root: string read FRoot;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  Atlas.Common.Mcp.Server;

{ TMcpPathGuard }

constructor TMcpPathGuard.Create(const ARoot: string; const AExtraRoots: TFunc<TArray<string>>;
  const ACanonicalize: TFunc<string, string>);
begin
  inherited Create;
  FExtraRoots := AExtraRoots;
  FCanonicalize := ACanonicalize;
  FRoot := Normalize(ARoot);
end;

function TMcpPathGuard.Normalize(const APath: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(APath.Replace('/', '\')));
  if Assigned(FCanonicalize) then
    Result := ExcludeTrailingPathDelimiter(FCanonicalize(Result));
end;

class function TMcpPathGuard.IsInside(const AFolder, APath: string): Boolean;
begin
  Result := (AFolder <> '') and (SameText(APath, AFolder) or StartsText(IncludeTrailingPathDelimiter(AFolder), APath));
end;

function TMcpPathGuard.Resolve(const APath: string): string;
var
  Folder: string;
begin
  if Trim(APath) = '' then
    raise EMcpToolError.Create('Pfad fehlt');
  if TPath.IsRelativePath(APath) then
    Result := Normalize(TPath.Combine(FRoot, APath))
  else
    Result := Normalize(APath);
  if IsInside(FRoot, Result) then
    Exit;
  if Assigned(FExtraRoots) then
    for Folder in FExtraRoots() do
      if (Trim(Folder) <> '') and IsInside(Normalize(Folder), Result) then
        Exit;
  raise EMcpToolError.CreateFmt('"%s" liegt außerhalb des Arbeitsbereichs (%s) und seiner Bibliothekspfade; ' +
    'MCP-Werkzeuge lesen nur dort (#99).', [Result, FRoot]);
end;

end.