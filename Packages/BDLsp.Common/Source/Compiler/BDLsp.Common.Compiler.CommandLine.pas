unit BDLsp.Common.Compiler.CommandLine;

// Aufruf von dcc32/dcc64 für ein Projekt (#40). Geprüft wird in einen eigenen
// Ausgabeordner (DCUs und EXE), damit der Build des Entwicklers unberührt
// bleibt; nach dem ersten Lauf übersetzt der Compiler dort nur Geändertes.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  BDLsp.Common.Projects.Contract,
  BDLsp.Common.Compiler.Contract;

type
  TCompilerCommandLine = class
  public
    /// <summary>Pfad von dcc32.exe bzw. dcc64.exe unter ABdsRoot; ECompilerError bei anderen Plattformen.</summary>
    class function ExecutableFor(const ABdsRoot, APlatform: string): string; static;
    /// <summary>Wurzel der Installation aus $(BDS); '' wenn unbekannt.</summary>
    class function BdsRoot(const AVariables: TArray<TPair<string, string>>): string; static;
    /// <summary>Aufruf für AProject mit den Bibliothekspfaden ALibraryPaths; Ausgabe nach AOutputDir.</summary>
    class function Build(const AProject: TProjectInfo; const ALibraryPaths: TArray<string>;
      const ABdsRoot, AOutputDir: string): TCompilerRequest; static;
  end;

implementation

uses
  BDLsp.Common.Projects.Paths;

function JoinList(const AItems: TArray<string>): string;
var
  Item: string;
begin
  Result := '';
  for Item in AItems do
    if Item <> '' then
    begin
      if Result <> '' then
        Result := Result + ';';
      Result := Result + Item;
    end;
end;

{ TCompilerCommandLine }

class function TCompilerCommandLine.ExecutableFor(const ABdsRoot, APlatform: string): string;
begin
  if SameText(APlatform, 'Win32') then
    Result := TProjectPaths.Combine(ABdsRoot, 'bin\dcc32.exe')
  else if SameText(APlatform, 'Win64') then
    Result := TProjectPaths.Combine(ABdsRoot, 'bin\dcc64.exe')
  else
    raise ECompilerError.CreateFmt('Plattform %s wird beim Kompilieren noch nicht unterstützt', [APlatform]);
end;

class function TCompilerCommandLine.BdsRoot(const AVariables: TArray<TPair<string, string>>): string;
var
  Variable: TPair<string, string>;
begin
  Result := '';
  for Variable in AVariables do
    if SameText(Variable.Key, 'BDS') then
      Exit(Variable.Value);
end;

class function TCompilerCommandLine.Build(const AProject: TProjectInfo; const ALibraryPaths: TArray<string>;
  const ABdsRoot, AOutputDir: string): TCompilerRequest;
var
  Paths: string;
  Arguments: TList<string>;
begin
  if AProject.MainSource = '' then
    raise ECompilerError.CreateFmt('Projekt %s hat keine Hauptdatei', [AProject.FileName]);
  Result := Default(TCompilerRequest);
  Result.Executable := ExecutableFor(ABdsRoot, AProject.Platform);
  Result.WorkingDir := TProjectPaths.DirectoryOf(AProject.FileName);
  Paths := JoinList(AProject.SearchPaths + ALibraryPaths);
  Arguments := TList<string>.Create;
  try
    // Kurze Ausgabe, Make (nur Geändertes), Hinweise und Warnungen an.
    Arguments.AddRange(['-Q', '-M', '-H+', '-W+']);
    Arguments.Add('-NU' + AOutputDir);
    Arguments.Add('-E' + AOutputDir);
    // Packages: BPL und DCP ebenfalls in den eigenen Ordner, sonst landen sie im
    // gemeinsamen Bpl-Ordner und überschreiben die installierten Packages.
    Arguments.Add('-LE' + AOutputDir);
    Arguments.Add('-LN' + AOutputDir);
    if Paths <> '' then
    begin
      Arguments.Add('-U' + Paths);
      Arguments.Add('-I' + Paths);
      Arguments.Add('-R' + Paths);
      Arguments.Add('-O' + Paths);
    end;
    if Length(AProject.Defines) > 0 then
      Arguments.Add('-D' + JoinList(AProject.Defines));
    if Length(AProject.Namespaces) > 0 then
      Arguments.Add('-NS' + JoinList(AProject.Namespaces));
    Arguments.Add(AProject.MainSource);
    Result.Arguments := Arguments.ToArray;
  finally
    Arguments.Free;
  end;
end;

end.
