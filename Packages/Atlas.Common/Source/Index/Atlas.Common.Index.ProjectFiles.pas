unit Atlas.Common.Index.ProjectFiles;

// Was aus einem Projekt in den Index gehört: Hauptdatei und eingetragene
// Units in Projektreihenfolge (ohne Duplikate), dazu die aktiven Symbole
// aus Projekt, Plattform und Compilerversion.
// PathFiles listet alle Units von Suchpfaden (#648), damit auch Units in den
// Index kommen, die noch keine Unit einbindet.

interface

uses
  System.SysUtils,
  Atlas.Common.Projects.Contract;

type
  /// <summary>Pascal-Units (*.pas) direkt in AFolder, ohne Unterordner; leer, wenn der Ordner fehlt.</summary>
  TIndexListUnits = reference to function(const AFolder: string): TArray<string>;
  /// <summary>True, wenn die Datei nicht in den Index soll (index.exclude).</summary>
  TIndexExcluded = reference to function(const AFileName: string): Boolean;

  TIndexProjectFiles = class
  public
    class function Files(const AProject: TProjectInfo): TArray<string>; static;
    /// <summary>Alle Units der Ordner APaths in deren Reihenfolge, je Ordner sortiert, ohne Duplikate,
    /// ohne die Dateien aus ASkip und ohne ausgeschlossene (#648). Suchpfade sind wie beim Compiler
    /// nicht rekursiv.</summary>
    class function PathFiles(const APaths: TArray<string>; const AListUnits: TIndexListUnits;
      const AExcluded: TIndexExcluded; const ASkip: TArray<string>): TArray<string>; static;
    /// <summary>ABdsVersion wie in der Registry, z. B. '23.0' für Delphi 12 (ergibt VER360); '' = ohne VERxxx.</summary>
    class function Defines(const AProject: TProjectInfo; const ABdsVersion: string): TArray<string>; static;
    /// <summary>Schlüssel für Projekt, Konfiguration, Plattform, Version, Symbole, Suchpfade und Namespaces;
    /// gleicher Schlüssel, gleicher Index. Ändert sich einer davon, gilt der Cache nicht mehr.</summary>
    class function Signature(const AProject: TProjectInfo; const ACompilerVersion: string): string; static;
    /// <summary>Schlüssel des Bibliotheks-Caches (#492): Compilerversion, Plattform und Defines, ohne Projekt.
    /// Projekte mit gleichem Stand teilen sich RTL/VCL; andere Defines ergeben andere {$IFDEF}-Zweige.</summary>
    class function LibrarySignature(const AProject: TProjectInfo; const ACompilerVersion: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.Preprocessor;

/// <summary>Symbole in Großschreibung, sortiert: Reihenfolge und Schreibweise ändern den Index nicht.</summary>
function SortedKey(const AItems: TArray<string>): string;
var
  Items: TArray<string>;
  Index: Integer;
begin
  SetLength(Items, Length(AItems));
  for Index := 0 to High(AItems) do
    Items[Index] := UpperCase(Trim(AItems[Index]));
  TArray.Sort<string>(Items);
  Result := String.Join(';', Items);
end;

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

class function TIndexProjectFiles.PathFiles(const APaths: TArray<string>; const AListUnits: TIndexListUnits;
  const AExcluded: TIndexExcluded; const ASkip: TArray<string>): TArray<string>;
var
  Found: TList<string>;
  Seen, Folders: TDictionary<string, Boolean>;
  Folder, Key, FileName: string;
  Units: TArray<string>;
begin
  Found := TList<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  Folders := TDictionary<string, Boolean>.Create;
  try
    for FileName in ASkip do
      Seen.AddOrSetValue(AnsiUpperCase(FileName), True);
    for Folder in APaths do
    begin
      Key := AnsiUpperCase(ExcludeTrailingPathDelimiter(Trim(Folder)));
      if (Key = '') or Folders.ContainsKey(Key) then
        Continue;
      Folders.Add(Key, True);
      Units := AListUnits(ExcludeTrailingPathDelimiter(Trim(Folder)));
      TArray.Sort<string>(Units);
      for FileName in Units do
      begin
        Key := AnsiUpperCase(FileName);
        if Seen.ContainsKey(Key) then
          Continue;
        Seen.Add(Key, True);
        if Assigned(AExcluded) and AExcluded(FileName) then
          Continue;
        Found.Add(FileName);
      end;
    end;
    Result := Found.ToArray;
  finally
    Folders.Free;
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

class function TIndexProjectFiles.LibrarySignature(const AProject: TProjectInfo;
  const ACompilerVersion: string): string;
begin
  Result := 'LIBRARY|' + UpperCase(AProject.Platform) + '|' + ACompilerVersion + '|' + SortedKey(AProject.Defines);
end;

class function TIndexProjectFiles.Signature(const AProject: TProjectInfo; const ACompilerVersion: string): string;
begin
  Result := AnsiUpperCase(AProject.FileName) + '|' + UpperCase(AProject.Config) + '|' +
    UpperCase(AProject.Platform) + '|' + ACompilerVersion + '|' + SortedKey(AProject.Defines) + '|' +
    AnsiUpperCase(String.Join(';', AProject.SearchPaths)) + '|' + UpperCase(String.Join(';', AProject.Namespaces));
end;

end.
