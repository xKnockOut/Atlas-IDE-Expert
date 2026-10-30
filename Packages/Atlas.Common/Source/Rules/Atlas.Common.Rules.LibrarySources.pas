unit Atlas.Common.Rules.LibrarySources;

// Fremde Quellen im Editor (diagnostics.librarySources): Units der Delphi-Installation
// ($(BDS), also RTL und VCL) und der Bibliothekspfade, die zu keinem Projekt gehören,
// prüft der Server nicht. Wer mit Strg+Klick in System.Net.HttpClient.pas springt,
// bekam sonst Stilhinweise zu Embarcadero Code, die er weder ändern soll noch kann.
//   IsLibraryFile  liegt unter einem Bibliotheksordner und unter keinem Projektordner.
// Ein Bibliotheksordner, der einen Projektordner enthält (Suchpfad "C:\Projekte"),
// zählt nicht: Sonst wären alle Nachbarprojekte fremd. Dass eine Datei zu einem
// Projekt gehört (DCCReference, Suchpfad-Unit), prüft der Aufrufer vorher.

interface

type
  TLibrarySources = record
  private
    FRoots: TArray<string>;
    FProjectRoots: TArray<string>;
    class function Normalized(const APath: string): string; static;
    class function IsFolder(const APath: string): Boolean; static;
  public
    /// <summary>ARoots: Installation und Bibliothekspfade (absolut, ohne Makros); AProjectRoots: Ordner der
    /// Projekte. Relative Pfade und Pfade mit $(…) fallen weg.</summary>
    class function Create(const ARoots, AProjectRoots: TArray<string>): TLibrarySources; static;
    /// <summary>AFileName liegt in AFolder oder darunter; beide Trenner, ohne Groß-/Kleinschreibung.</summary>
    class function IsUnder(const AFileName, AFolder: string): Boolean; static;
    /// <summary>AFileName liegt unter einem Bibliotheksordner und unter keinem Projektordner.</summary>
    function IsLibraryFile(const AFileName: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

{ TLibrarySources }

class function TLibrarySources.Normalized(const APath: string): string;
begin
  Result := Trim(APath).Replace('\', '/');
  if (Result <> '') and not EndsStr('/', Result) then
    Result := Result + '/';
end;

class function TLibrarySources.IsFolder(const APath: string): Boolean;
var
  mPath: string;
begin
  mPath := Trim(APath);
  // Absolut: Laufwerk, UNC oder Wurzel; Makros wie $(BDSCOMMONDIR) sind nicht aufgelöst.
  Result := (mPath <> '') and (Pos('$(', mPath) = 0) and (((Length(mPath) >= 3) and (mPath[2] = ':') and
    CharInSet(mPath[3], ['\', '/'])) or StartsStr('\\', mPath) or StartsStr('/', mPath));
end;

class function TLibrarySources.Create(const ARoots, AProjectRoots: TArray<string>): TLibrarySources;
var
  mRoot, mProject: string;
  mContainsProject: Boolean;
begin
  Result.FRoots := nil;
  Result.FProjectRoots := nil;
  for mProject in AProjectRoots do
    if IsFolder(mProject) then
      Result.FProjectRoots := Result.FProjectRoots + [mProject];
  for mRoot in ARoots do
  begin
    if not IsFolder(mRoot) then
      Continue;
    mContainsProject := False;
    for mProject in Result.FProjectRoots do
      if IsUnder(mProject, mRoot) then
        mContainsProject := True;
    if not mContainsProject then
      Result.FRoots := Result.FRoots + [mRoot];
  end;
end;

class function TLibrarySources.IsUnder(const AFileName, AFolder: string): Boolean;
var
  mFolder: string;
begin
  mFolder := Normalized(AFolder);
  Result := (mFolder <> '') and StartsText(mFolder, Normalized(AFileName));
end;

function TLibrarySources.IsLibraryFile(const AFileName: string): Boolean;
var
  mFolder: string;
begin
  Result := False;
  for mFolder in FProjectRoots do
    if IsUnder(AFileName, mFolder) then
      Exit;
  for mFolder in FRoots do
    if IsUnder(AFileName, mFolder) then
      Exit(True);
end;

end.
