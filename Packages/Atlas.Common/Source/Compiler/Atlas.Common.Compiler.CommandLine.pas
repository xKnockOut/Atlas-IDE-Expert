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
  mItem: string;
begin
  Result := '';
  for mItem in AItems do
  begin
    if mItem <> '' then
    begin
      if Result <> '' then
      begin
        Result := Result + ';';
      end;
      Result := Result + mItem;
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
  mVariable: TPair<string, string>;
begin
  Result := '';
  for mVariable in AVariables do
  begin
    if SameText(mVariable.Key, 'BDS') then
    begin
      Exit(mVariable.Value);
    end;
  end;
end;

class function TCompilerCommandLine.Build(const AProject: TProjectInfo; const ALibraryPaths: TArray<string>;
  const ABdsRoot, AOutputDir: string): TCompilerRequest;
var
  mPaths: string;
  mArguments: TList<string>;
begin
  if AProject.MainSource = '' then
  begin
    raise ECompilerError.CreateFmt(cTexts[TCommandLineText.ProjectHasNoMainFile].Text, [AProject.FileName]);
  end;
  Result := Default(TCompilerRequest);
  Result.Executable := ExecutableFor(ABdsRoot, AProject.Platform);
  Result.WorkingDir := TProjectPaths.DirectoryOf(AProject.FileName);
  mPaths := JoinList(AProject.SearchPaths + ALibraryPaths);
  mArguments := TList<string>.Create;
  try
    // Kurze Ausgabe, Make (nur Geändertes), Hinweise und Warnungen an.
    mArguments.AddRange(['-Q', '-M', '-H+', '-W+']);
    mArguments.Add('-NU' + AOutputDir);
    mArguments.Add('-E' + AOutputDir);
    // Packages: BPL und DCP ebenfalls in den eigenen Ordner, sonst landen sie im
    // gemeinsamen Bpl-Ordner und überschreiben die installierten Packages.
    mArguments.Add('-LE' + AOutputDir);
    mArguments.Add('-LN' + AOutputDir);
    if mPaths <> '' then
    begin
      mArguments.Add('-U' + mPaths);
      mArguments.Add('-I' + mPaths);
      mArguments.Add('-R' + mPaths);
      mArguments.Add('-O' + mPaths);
    end;
    if Length(AProject.Defines) > 0 then
    begin
      mArguments.Add('-D' + JoinList(AProject.Defines));
    end;
    if Length(AProject.Namespaces) > 0 then
    begin
      mArguments.Add('-NS' + JoinList(AProject.Namespaces));
    end;
    mArguments.Add(AProject.MainSource);
    Result.Arguments := mArguments.ToArray;
  finally
    mArguments.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Compiler.CommandLine', cTexts);

end.
