unit Shell.Linter.Files;

// Internals-Rolle Shell: Dateien des Linter-Modus (#95). Ziel ist eine .dproj (Hauptdatei und Units des Projekts,
// mit deren Symbolen und Suchpfaden für $I, #860), ein Ordner (alle .pas, .dpr, .dpk darunter) oder eine Datei.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.DprojReader,
  Atlas.Common.Projects.PackageReader,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Checker;

type
  TLinterFiles = class
  public
    /// <summary>.pas, .dpr oder .dpk?</summary>
    class function IsSourceFile(const AFileName: string): Boolean; static;
    /// <summary>Endung einer Berichtsdatei erlaubt (.md, .html, .htm, .json)?</summary>
    class function IsReportFile(const AFileName: string): Boolean; static;
    /// <summary>Symbole und Include-Dateien der Prüfung (#860): ADefines und die Suchpfade des Projekts.</summary>
    class function SourcesOf(const ADefines, AIncludePaths: TArray<string>): TCheckSourceFunc; static;
    /// <summary>Dateien von ATarget; ARoot ist der Ordner, zu dem die Pfade relativ sind.</summary>
    class function Collect(const ATarget: string; const ASettings: TServerSettings; out ARoot: string;
      out ASources: TCheckSourceFunc): TArray<string>; static;
    /// <summary>Lesbares Projekt mit Konfiguration und Plattform aus ASettings.</summary>
    class function DprojOptionsOf(const ASettings: TServerSettings): TDprojOptions; static;
    /// <summary>Hauptdatei (.dpr) der .dproj AProject; '' ohne.</summary>
    class function MainSourceOf(const AProject: string; const ASettings: TServerSettings): string; static;
    /// <summary>Die .dpk unter AFiles, damit Regeln wissen, welche Unit zu einem Package gehört (#943).</summary>
    class function Packages(const AFiles: TArray<string>): TArray<TPackageSource>; static;
    /// <summary>Quelltexte der Programme (.dpr) für die CreateForm-Reihenfolge (form-access-before-create, #956).
    /// </summary>
    class function Programs(const AFiles: TArray<string>): TArray<string>; static;
    /// <summary>Text von AFileName in seiner Kodierung; False, wenn er nicht lesbar ist.</summary>
    class function ReadText(const AFileName: string; out AText: string): Boolean; static;
    /// <summary>Index nur aus AFiles (keine Bibliothek), mit ihren Symbolen; Fehler je Datei auf stderr.</summary>
    class function IndexOf(const AFiles: TArray<string>; const ASources: TCheckSourceFunc): ISymbolIndex; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Projects.DelphiVersions,
  Atlas.Common.Index.ProjectFiles,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.IncludeFiles,
  Shell.Platform,
  Shell.Linter.Output;

class function TLinterFiles.IsSourceFile(const AFileName: string): Boolean;
var
  mExt: string;
begin
  mExt := LowerCase(ExtractFileExt(AFileName));
  Result := (mExt = '.pas') or (mExt = '.dpr') or (mExt = '.dpk');
end;

class function TLinterFiles.IsReportFile(const AFileName: string): Boolean;
var
  mExt: string;
begin
  mExt := LowerCase(ExtractFileExt(AFileName));
  Result := (mExt = '.md') or (mExt = '.html') or (mExt = '.htm') or (mExt = '.json');
end;

class function TLinterFiles.SourcesOf(const ADefines, AIncludePaths: TArray<string>): TCheckSourceFunc;
var
  mResolver: TIncludeResolver;
  mDefines: TArray<string>;
begin
  mResolver := TIncludeFiles.Resolver(AIncludePaths);
  mDefines := ADefines;
  Result :=
    function(const AFileName: string): TCheckSource
    begin
      Result := TCheckSource.Create(AFileName, mDefines, mResolver);
    end;
end;

class function TLinterFiles.DprojOptionsOf(const ASettings: TServerSettings): TDprojOptions;
begin
  Result := Default(TDprojOptions);
  Result.Config := ASettings.Config;
  Result.Platform := ASettings.Platform;
  Result.FileExists :=
    function(APath: string): Boolean
    begin
      Result := TFile.Exists(APath) or TDirectory.Exists(APath);
    end;
end;

/// <summary>Alle Quelltexte unter AFolder.</summary>
procedure AddFolderFiles(const AFolder: string; AFiles: TList<string>);
var
  mFileName: string;
begin
  for mFileName in TDirectory.GetFiles(AFolder, '*.*', TSearchOption.soAllDirectories) do
  begin
    if TLinterFiles.IsSourceFile(mFileName) then
    begin
      AFiles.Add(mFileName);
    end;
  end;
end;

/// <summary>Hauptdatei und vorhandene Units von AProject.</summary>
procedure AddProjectFiles(const AProject: TProjectInfo; AFiles: TList<string>);
var
  mUnit: TProjectUnit;
begin
  if (AProject.MainSource <> '') and TFile.Exists(AProject.MainSource) then
  begin
    AFiles.Add(AProject.MainSource);
  end;
  for mUnit in AProject.Units do
  begin
    if TLinterFiles.IsSourceFile(mUnit.FileName) and TFile.Exists(mUnit.FileName) and
      not AFiles.Contains(mUnit.FileName) then
    begin
      AFiles.Add(mUnit.FileName);
    end;
  end;
end;

/// <summary>Dateien der .dproj AFileName. Symbole wie im Editor: .dproj, Plattform, Compilerversion und Schalter
/// (#860); ohne installiertes Delphi die Version, die das Projekt erwartet (#1321).</summary>
function ProjectSources(const AFileName: string; const ASettings: TServerSettings; AFiles: TList<string>):
  TCheckSourceFunc;
var
  mProject: TProjectInfo;
  mVersion: string;
begin
  mProject := TDprojReader.Load(AFileName, TLinterFiles.DprojOptionsOf(ASettings));
  mVersion := TDelphiVersions.Choose(ASettings.DelphiVersion,
    TDelphiVersions.ProjectVersionOf(TFileEncoding.LoadText(AFileName)), TDelphiInstallation.Versions);
  AddProjectFiles(mProject, AFiles);
  Result := TLinterFiles.SourcesOf(TIndexProjectFiles.Defines(mProject, mVersion), mProject.SearchPaths);
end;

class function TLinterFiles.Collect(const ATarget: string; const ASettings: TServerSettings; out ARoot: string;
  out ASources: TCheckSourceFunc): TArray<string>;
var
  mFiles: TList<string>;
  mFullPath: string;
begin
  ASources := SourcesOf(nil, nil);
  mFullPath := TPath.GetFullPath(ATarget);
  ARoot := ExtractFileDir(mFullPath);
  mFiles := TList<string>.Create;
  try
    if TDirectory.Exists(ATarget) then
    begin
      ARoot := ExcludeTrailingPathDelimiter(mFullPath);
      AddFolderFiles(ARoot, mFiles);
    end
    else if SameText(ExtractFileExt(ATarget), '.dproj') then
    begin
      ASources := ProjectSources(mFullPath, ASettings, mFiles);
    end
    else
    begin
      mFiles.Add(mFullPath);
    end;
    Result := mFiles.ToArray;
  finally
    mFiles.Free;
  end;
end;

class function TLinterFiles.MainSourceOf(const AProject: string; const ASettings: TServerSettings): string;
begin
  Result := TDprojReader.Load(TPath.GetFullPath(AProject), DprojOptionsOf(ASettings)).MainSource;
  if (Result = '') and TFile.Exists(ChangeFileExt(AProject, '.dpr')) then
  begin
    Result := TPath.GetFullPath(ChangeFileExt(AProject, '.dpr'));
  end;
end;

/// <summary>Texte der Dateien aus AFiles mit der Endung AExt; nicht lesbare mit Meldung auf stderr.</summary>
function TextsWithExt(const AFiles: TArray<string>; const AExt: string): TArray<string>;
var
  mFileName: string;
  mFormat: TFileFormat;
begin
  Result := nil;
  for mFileName in AFiles do
  begin
    if SameText(ExtractFileExt(mFileName), AExt) then
      try
        Result := Result + [TFileEncoding.LoadFromFile(mFileName, mFormat)];
      except
        on E: Exception do
          TLinterOutput.Error(Format('%s: %s', [mFileName, E.Message]));
      end;
  end;
end;

class function TLinterFiles.Packages(const AFiles: TArray<string>): TArray<TPackageSource>;
var
  mText: string;
begin
  Result := nil;
  for mText in TextsWithExt(AFiles, '.dpk') do
  begin
    Result := Result + [TPackageReader.Read(mText)];
  end;
end;

class function TLinterFiles.Programs(const AFiles: TArray<string>): TArray<string>;
begin
  Result := TextsWithExt(AFiles, '.dpr');
end;

class function TLinterFiles.ReadText(const AFileName: string; out AText: string): Boolean;
var
  mFormat: TFileFormat;
begin
  try
    AText := TFileEncoding.LoadFromFile(AFileName, mFormat);
    Result := True;
  except
    AText := '';
    Result := False;
  end;
end;

class function TLinterFiles.IndexOf(const AFiles: TArray<string>; const ASources: TCheckSourceFunc): ISymbolIndex;
var
  mFileName, mText: string;
  mFormat: TFileFormat;
  mSource: TCheckSource;
begin
  Result := TSymbolIndex.Create;
  for mFileName in AFiles do
    try
      mText := TFileEncoding.LoadFromFile(mFileName, mFormat);
      mSource := ASources(mFileName);
      Result.AddUnit(TIndexExtractor.ExtractText(mText, mFileName, mSource.Defines, mSource.ResolveInclude));
    except
      on E: Exception do
        TLinterOutput.Error(Format('%s: %s', [mFileName, E.Message]));
    end;
end;

end.
