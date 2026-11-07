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
    /// <summary>ABdsVersion wie in der Registry, z. B. '23.0' für Delphi 12 (ergibt VER360); '' = ohne
    /// VERxxx.</summary>
    class function Defines(const AProject: TProjectInfo; const ABdsVersion: string): TArray<string>; static;
    /// <summary>Schlüssel für Projekt, Konfiguration, Plattform, Version, Symbole, Suchpfade und Namespaces;
    /// gleicher Schlüssel, gleicher Index. Ändert sich einer davon, gilt der Cache nicht mehr.</summary>
    class function Signature(const AProject: TProjectInfo; const ACompilerVersion: string): string; static;
    /// <summary>Symbole für die Units der Installation (#647): nur Plattform und Compilerversion. RTL, VCL
    /// und FMX kommen als fertige DCUs; die Defines des Projekts wirken auf sie nicht.</summary>
    class function LibraryDefines(const AProject: TProjectInfo; const ABdsVersion: string): TArray<string>; static;
    /// <summary>Schlüssel des Bibliotheks-Caches (#492): Compilerversion und Plattform, ohne Projekt und
    /// ohne dessen Defines (#647). Alle Projekte und Konfigurationen teilen sich RTL/VCL/FMX.</summary>
    class function LibrarySignature(const AProject: TProjectInfo; const ACompilerVersion: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.Preprocessor;

/// <summary>Symbole in Großschreibung, sortiert: Reihenfolge und Schreibweise ändern den Index nicht.</summary>
function SortedKey(const AItems: TArray<string>): string;
var
  mItems: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mItems, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    mItems[mIndex] := UpperCase(Trim(AItems[mIndex]));
  end;
  TArray.Sort<string>(mItems);
  Result := String.Join(';', mItems);
end;

{ TIndexProjectFiles }

class function TIndexProjectFiles.Files(const AProject: TProjectInfo): TArray<string>;
var
  mFound: TList<string>;
  mSeen: TDictionary<string, Boolean>;
  mProjectUnit: TProjectUnit;

  procedure AddFile(const AFileName: string);
  begin
    if (AFileName <> '') and not mSeen.ContainsKey(AnsiUpperCase(AFileName)) then
    begin
      mSeen.Add(AnsiUpperCase(AFileName), True);
      mFound.Add(AFileName);
    end;
  end;

begin
  mFound := TList<string>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    AddFile(AProject.MainSource);
    for mProjectUnit in AProject.Units do
    begin
      AddFile(mProjectUnit.FileName);
    end;
    Result := mFound.ToArray;
  finally
    mSeen.Free;
    mFound.Free;
  end;
end;

class function TIndexProjectFiles.PathFiles(const APaths: TArray<string>; const AListUnits: TIndexListUnits;
  const AExcluded: TIndexExcluded; const ASkip: TArray<string>): TArray<string>;
var
  mFound: TList<string>;
  mSeen, mFolders: TDictionary<string, Boolean>;
  mFolder, mKey, mFileName: string;
  mUnits: TArray<string>;
begin
  mFound := TList<string>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  mFolders := TDictionary<string, Boolean>.Create;
  try
    for mFileName in ASkip do
    begin
      mSeen.AddOrSetValue(AnsiUpperCase(mFileName), True);
    end;
    for mFolder in APaths do
    begin
      mKey := AnsiUpperCase(ExcludeTrailingPathDelimiter(Trim(mFolder)));
      if (mKey = '') or mFolders.ContainsKey(mKey) then
      begin
        Continue;
      end;
      mFolders.Add(mKey, True);
      mUnits := AListUnits(ExcludeTrailingPathDelimiter(Trim(mFolder)));
      TArray.Sort<string>(mUnits);
      for mFileName in mUnits do
      begin
        mKey := AnsiUpperCase(mFileName);
        if mSeen.ContainsKey(mKey) then
        begin
          Continue;
        end;
        mSeen.Add(mKey, True);
        if Assigned(AExcluded) and AExcluded(mFileName) then
        begin
          Continue;
        end;
        mFound.Add(mFileName);
      end;
    end;
    Result := mFound.ToArray;
  finally
    mFolders.Free;
    mSeen.Free;
    mFound.Free;
  end;
end;

class function TIndexProjectFiles.Defines(const AProject: TProjectInfo; const ABdsVersion: string): TArray<string>;
var
  mVersion: Double;
begin
  if not TryStrToFloat(ABdsVersion, mVersion, TFormatSettings.Invariant) then
  begin
    mVersion := 0;
  end;
  // Dazu die Schalterstände für $IFOPT ("$R+", #847).
  Result := AProject.Defines + TPascalPreprocessor.PredefinedSymbols(AProject.Platform,
    TPascalPreprocessor.CompilerVersionOfBds(mVersion)) + TPascalPreprocessor.ProjectSwitches(AProject.Properties);
end;

class function TIndexProjectFiles.LibraryDefines(const AProject: TProjectInfo;
  const ABdsVersion: string): TArray<string>;
var
  mVersion: Double;
begin
  if not TryStrToFloat(ABdsVersion, mVersion, TFormatSettings.Invariant) then
  begin
    mVersion := 0;
  end;
  Result := TPascalPreprocessor.PredefinedSymbols(AProject.Platform,
    TPascalPreprocessor.CompilerVersionOfBds(mVersion));
end;

class function TIndexProjectFiles.LibrarySignature(const AProject: TProjectInfo;
  const ACompilerVersion: string): string;
begin
  // "2": Ältere Caches enthielten Units, die mit den Defines des Projekts gelesen wurden.
  Result := 'LIBRARY2|' + UpperCase(AProject.Platform) + '|' + ACompilerVersion;
end;

class function TIndexProjectFiles.Signature(const AProject: TProjectInfo; const ACompilerVersion: string): string;
begin
  Result := AnsiUpperCase(AProject.FileName) + '|' + UpperCase(AProject.Config) + '|' +
    UpperCase(AProject.Platform) + '|' + ACompilerVersion + '|' + SortedKey(AProject.Defines) + '|' +
    AnsiUpperCase(String.Join(';', AProject.SearchPaths)) + '|' + UpperCase(String.Join(';', AProject.Namespaces)) +
    '|' + String.Join(';', TPascalPreprocessor.ProjectSwitches(AProject.Properties));
end;

end.
