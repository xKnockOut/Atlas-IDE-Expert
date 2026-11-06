unit Atlas.Common.Compiler.CommandLine;

// Aufruf von dcc32/dcc64 für ein Projekt (#40). Geprüft wird in einen eigenen
// Ausgabeordner (DCUs und EXE), damit der Build des Entwicklers unberührt
// bleibt; nach dem ersten Lauf übersetzt der Compiler dort nur Geändertes.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Compiler.Contract;

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
  Atlas.Common.Projects.Paths,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TCommandLineText = (PlatformIsNotSupportedFor, ProjectHasNoMainFile);

const
  cTexts: array[TCommandLineText] of TAtlasText = (
    (De: 'Plattform %s wird beim Kompilieren noch nicht unterstützt';
     En: 'Platform %s is not supported for compiling yet'),
    (De: 'Projekt %s hat keine Hauptdatei'; En: 'Project %s has no main file'));

{$SCOPEDENUMS OFF}

function JoinList(const AItems: TArray<string>): string;
var
  Item: string;
begin
  Result := '';
  for Item in AItems do
  begin
    if Item <> '' then
    begin
      if Result <> '' then
      begin
        Result := Result + ';';
      end;
      Result := Result + Item;
    end;
  end;
end;

{ TCompilerCommandLine }

class function TCompilerCommandLine.ExecutableFor(const ABdsRoot, APlatform: string): string;
begin
  if SameText(APlatform, 'Win32') then
  begin
    Result := TProjectPaths.Combine(ABdsRoot, 'bin\dcc32.exe');
  end
  else if SameText(APlatform, 'Win64') then
  begin
    Result := TProjectPaths.Combine(ABdsRoot, 'bin\dcc64.exe');
  end
  else
  begin
    raise ECompilerError.CreateFmt(cTexts[TCommandLineText.PlatformIsNotSupportedFor].Text, [APlatform]);
  end;
end;

class function TCompilerCommandLine.BdsRoot(const AVariables: TArray<TPair<string, string>>): string;
var
  Variable: TPair<string, string>;
begin
  Result := '';
  for Variable in AVariables do
  begin
    if SameText(Variable.Key, 'BDS') then
    begin
      Exit(Variable.Value);
    end;
  end;
end;

class function TCompilerCommandLine.Build(const AProject: TProjectInfo; const ALibraryPaths: TArray<string>;
  const ABdsRoot, AOutputDir: string): TCompilerRequest;
var
  Paths: string;
  Arguments: TList<string>;
begin
  if AProject.MainSource = '' then
  begin
    raise ECompilerError.CreateFmt(cTexts[TCommandLineText.ProjectHasNoMainFile].Text, [AProject.FileName]);
  end;
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
    begin
      Arguments.Add('-D' + JoinList(AProject.Defines));
    end;
    if Length(AProject.Namespaces) > 0 then
    begin
      Arguments.Add('-NS' + JoinList(AProject.Namespaces));
    end;
    Arguments.Add(AProject.MainSource);
    Result.Arguments := Arguments.ToArray;
  finally
    Arguments.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Compiler.CommandLine', cTexts);

end.
