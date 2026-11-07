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
    constructor Create(const ARoot: string; const AExtraRoots: TFunc<TArray<string>>;
      const ACanonicalize: TFunc<string, string>); overload;
    /// <summary>Wie oben mit ACanonicalize = nil.</summary>
    constructor Create(const ARoot: string; const AExtraRoots: TFunc<TArray<string>>); overload;
    /// <summary>Wie oben nur mit ARoot (AExtraRoots = nil, ACanonicalize = nil).</summary>
    constructor Create(const ARoot: string); overload;
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
  Atlas.Common.Mcp.Server,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TPathsText = (PathMissing, LiesOutsideTheWorkspaceAnd);

const
  cTexts: array[TPathsText] of TAtlasText = (
    (De: 'Pfad fehlt'; En: 'Path missing'),
    (De: '"%s" liegt außerhalb des Arbeitsbereichs (%s) und seiner Bibliothekspfade; MCP-Werkzeuge lesen nur dort ' +
      '(#99).';
     En: '"%s" lies outside the workspace (%s) and its library paths; MCP tools only read there (#99).'));

{$SCOPEDENUMS OFF}

{ TMcpPathGuard }

constructor TMcpPathGuard.Create(const ARoot: string; const AExtraRoots: TFunc<TArray<string>>);
begin
  Create(ARoot, AExtraRoots, nil);
end;

constructor TMcpPathGuard.Create(const ARoot: string);
begin
  Create(ARoot, nil, nil);
end;

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
  begin
    Result := ExcludeTrailingPathDelimiter(FCanonicalize(Result));
  end;
end;

class function TMcpPathGuard.IsInside(const AFolder, APath: string): Boolean;
begin
  Result := (AFolder <> '') and (SameText(APath, AFolder) or StartsText(IncludeTrailingPathDelimiter(AFolder), APath));
end;

function TMcpPathGuard.Resolve(const APath: string): string;
var
  mFolder: string;
begin
  if Trim(APath) = '' then
  begin
    raise EMcpToolError.Create(cTexts[TPathsText.PathMissing].Text);
  end;
  if TPath.IsRelativePath(APath) then
  begin
    Result := Normalize(TPath.Combine(FRoot, APath));
  end
  else
  begin
    Result := Normalize(APath);
  end;
  if IsInside(FRoot, Result) then
  begin
    Exit;
  end;
  if Assigned(FExtraRoots) then
  begin
    for mFolder in FExtraRoots() do
    begin
      if (Trim(mFolder) <> '') and IsInside(Normalize(mFolder), Result) then
      begin
        Exit;
      end;
    end;
  end;
  raise EMcpToolError.CreateFmt(cTexts[TPathsText.LiesOutsideTheWorkspaceAnd].Text, [Result, FRoot]);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.Paths', cTexts);

end.