unit Argus.Common.Pascal.IncludeFiles;

// Gemeinsame Suche nach Include-Dateien (#264) für Präprozessor, Index,
// Abblenden und Verweise. Reihenfolge wie beim Compiler:
//   1. absoluter Pfad, so wie angegeben;
//   2. Ordner der einbindenden Datei;
//   3. die Suchpfade in ihrer Reihenfolge (Projekt-Suchpfade, dann Bibliothekspfade).
// Ohne Endung wird zusätzlich ".inc" und ".pas" probiert. Gelesen wird über
// TFileEncoding, damit ANSI- und UTF-8-Dateien ohne BOM richtig ankommen.

interface

uses
  System.SysUtils,
  Argus.Common.Pascal.Preprocessor;

type
  TIncludeFileExists = reference to function(const AFileName: string): Boolean;
  TIncludeReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  TIncludeFiles = class
  public
    /// <summary>Datei zu AName (z. B. aus $R oder $I) ohne Endungsergänzung; ABaseDir ist der Ordner der einbindenden Datei.</summary>
    class function FindFile(const AName, ABaseDir: string; const ASearchPaths: TArray<string>;
      const AFileExists: TIncludeFileExists; out AFileName: string): Boolean; static;
    /// <summary>Include-Datei zu AName aus $I/$INCLUDE in AFromFile, mit ".inc"/".pas" bei fehlender Endung.</summary>
    class function FindInclude(const AName, AFromFile: string; const ASearchPaths: TArray<string>;
      const AFileExists: TIncludeFileExists; out AFileName: string): Boolean; static;
    /// <summary>Resolver für den Präprozessor. Ohne AFileExists/AReadText gilt das Dateisystem.</summary>
    class function Resolver(const ASearchPaths: TArray<string>; const AFileExists: TIncludeFileExists = nil;
      const AReadText: TIncludeReadText = nil): TIncludeResolver; static;
    /// <summary>Liest eine Datei über TFileEncoding; False, wenn sie fehlt oder nicht lesbar ist.</summary>
    class function ReadFile(const AFileName: string; out AText: string): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  Argus.Common.Documents.FileEncoding;

function Unquote(const AName: string): string;
begin
  Result := Trim(AName);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

{ TIncludeFiles }

class function TIncludeFiles.FindFile(const AName, ABaseDir: string; const ASearchPaths: TArray<string>;
  const AFileExists: TIncludeFileExists; out AFileName: string): Boolean;
var
  Name, Dir: string;
begin
  AFileName := '';
  Name := Unquote(AName);
  if Name = '' then
    Exit(False);
  if (ExtractFileDrive(Name) <> '') or Name.StartsWith('\') or Name.StartsWith('/') then
  begin
    AFileName := Name;
    Exit(AFileExists(AFileName));
  end;
  if ABaseDir <> '' then
  begin
    AFileName := ExpandFileName(IncludeTrailingPathDelimiter(ABaseDir) + Name);
    if AFileExists(AFileName) then
      Exit(True);
  end;
  for Dir in ASearchPaths do
    if Dir <> '' then
    begin
      AFileName := ExpandFileName(IncludeTrailingPathDelimiter(Dir) + Name);
      if AFileExists(AFileName) then
        Exit(True);
    end;
  AFileName := '';
  Result := False;
end;

class function TIncludeFiles.FindInclude(const AName, AFromFile: string; const ASearchPaths: TArray<string>;
  const AFileExists: TIncludeFileExists; out AFileName: string): Boolean;
var
  Name, BaseDir: string;
begin
  Name := Unquote(AName);
  BaseDir := ExtractFileDir(AFromFile);
  if FindFile(Name, BaseDir, ASearchPaths, AFileExists, AFileName) then
    Exit(True);
  Result := (ExtractFileExt(Name) = '') and
    (FindFile(Name + '.inc', BaseDir, ASearchPaths, AFileExists, AFileName) or
     FindFile(Name + '.pas', BaseDir, ASearchPaths, AFileExists, AFileName));
end;

class function TIncludeFiles.ReadFile(const AFileName: string; out AText: string): Boolean;
var
  FileFormat: TFileFormat;
begin
  AText := '';
  try
    AText := TFileEncoding.LoadFromFile(AFileName, FileFormat);
    Result := True;
  except
    // Gesperrt, gelöscht oder nicht lesbar: wie eine fehlende Datei behandeln.
    on EFOpenError do
      Result := False;
    on EReadError do
      Result := False;
    on EInOutError do
      Result := False;
  end;
end;

class function TIncludeFiles.Resolver(const ASearchPaths: TArray<string>; const AFileExists: TIncludeFileExists;
  const AReadText: TIncludeReadText): TIncludeResolver;
var
  Paths: TArray<string>;
  Exists: TIncludeFileExists;
  Read: TIncludeReadText;
begin
  Paths := ASearchPaths;
  Exists := AFileExists;
  if not Assigned(Exists) then
    Exists :=
      function(const AFileName: string): Boolean
      begin
        Result := TFile.Exists(AFileName);
      end;
  Read := AReadText;
  if not Assigned(Read) then
    Read :=
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := TIncludeFiles.ReadFile(AFileName, AText);
      end;
  Result :=
    function(const AName, AFromFile: string; out AFileName, AText: string): Boolean
    begin
      AText := '';
      Result := TIncludeFiles.FindInclude(AName, AFromFile, Paths, Exists, AFileName) and Read(AFileName, AText);
    end;
end;

end.
