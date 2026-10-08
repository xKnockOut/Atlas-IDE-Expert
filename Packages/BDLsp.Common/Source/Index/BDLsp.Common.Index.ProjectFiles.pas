unit BDLsp.Common.Index.ProjectFiles;

// Was aus einem Projekt in den Index gehört: Hauptdatei und eingetragene
// Units in Projektreihenfolge (ohne Duplikate), dazu die aktiven Symbole
// aus Projekt, Plattform und Compilerversion.

interface

uses
  System.SysUtils,
  BDLsp.Common.Projects.Contract;

type
  TIndexProjectFiles = class
  public
    class function Files(const AProject: TProjectInfo): TArray<string>; static;
    /// <summary>ABdsVersion wie in der Registry, z. B. '23.0' für Delphi 12 (ergibt VER360); '' = ohne VERxxx.</summary>
    class function Defines(const AProject: TProjectInfo; const ABdsVersion: string): TArray<string>; static;
    /// <summary>Schlüssel für Projekt, Konfiguration, Plattform und Version; gleicher Schlüssel, gleicher Index.</summary>
    class function Signature(const AProject: TProjectInfo; const ACompilerVersion: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  BDLsp.Common.Pascal.Preprocessor;

{ TIndexProjectFiles }

class function TIndexProjectFiles.Files(const AProject: TProjectInfo): TArray<string>;
var
  Found: TList<string>;
  Seen: TDictionary<string, Boolean>;
  ProjectUnit: TProjectUnit;

  procedure AddFile(const AFileName: string);
  begin
    if (AFileName <> '') and not Seen.ContainsKey(AnsiUpperCase(AFileName)) then
    begin
      Seen.Add(AnsiUpperCase(AFileName), True);
      Found.Add(AFileName);
    end;
  end;

begin
  Found := TList<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    AddFile(AProject.MainSource);
    for ProjectUnit in AProject.Units do
      AddFile(ProjectUnit.FileName);
    Result := Found.ToArray;
  finally
    Seen.Free;
    Found.Free;
  end;
end;

class function TIndexProjectFiles.Defines(const AProject: TProjectInfo; const ABdsVersion: string): TArray<string>;
var
  Version: Double;
begin
  if not TryStrToFloat(ABdsVersion, Version, TFormatSettings.Invariant) then
    Version := 0;
  Result := AProject.Defines + TPascalPreprocessor.PredefinedSymbols(AProject.Platform,
    TPascalPreprocessor.CompilerVersionOfBds(Version));
end;

class function TIndexProjectFiles.Signature(const AProject: TProjectInfo; const ACompilerVersion: string): string;
begin
  Result := AnsiUpperCase(AProject.FileName) + '|' + UpperCase(AProject.Config) + '|' +
    UpperCase(AProject.Platform) + '|' + ACompilerVersion;
end;

end.
