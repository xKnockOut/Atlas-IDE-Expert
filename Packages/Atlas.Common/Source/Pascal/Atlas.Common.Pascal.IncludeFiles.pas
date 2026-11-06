unit Atlas.Common.Pascal.IncludeFiles;

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
  Atlas.Common.Pascal.Preprocessor;

type
  TIncludeFileExists = reference to function(const AFileName: string): Boolean;
  TIncludeReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  TIncludeFiles = class
  public
    /// <summary>Datei zu AName (z. B. aus $R oder $I) ohne Endungsergänzung; ABaseDir ist der Ordner der einbindenden
    /// Datei.</summary>
    class function FindFile(const AName, ABaseDir: string; const ASearchPaths: TArray<string>;
      const AFileExists: TIncludeFileExists; out AFileName: string): Boolean; static;
    /// <summary>Include-Datei zu AName aus $I/$INCLUDE in AFromFile, mit ".inc"/".pas" bei fehlender Endung.</summary>
    class function FindInclude(const AName, AFromFile: string; const ASearchPaths: TArray<string>;
      const AFileExists: TIncludeFileExists; out AFileName: string): Boolean; static;
    /// <summary>Resolver für den Präprozessor. Ohne AFileExists/AReadText gilt das Dateisystem.</summary>
    class function Resolver(const ASearchPaths: TArray<string>; const AFileExists: TIncludeFileExists;
      const AReadText: TIncludeReadText): TIncludeResolver; overload; static;
    /// <summary>Wie oben mit AReadText = nil.</summary>
    class function Resolver(const ASearchPaths: TArray<string>;
      const AFileExists: TIncludeFileExists): TIncludeResolver; overload; static;
    /// <summary>Wie oben über das Dateisystem (AFileExists = nil, AReadText = nil).</summary>
    class function Resolver(const ASearchPaths: TArray<string>): TIncludeResolver; overload; static;
    /// <summary>Liest eine Datei über TFileEncoding; False, wenn sie fehlt oder nicht lesbar ist.</summary>
    class function ReadFile(const AFileName: string; out AText: string): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding;

function Unquote(const AName: string): string;
begin
  Result := Trim(AName);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end;
end;

{ TIncludeFiles }

class function TIncludeFiles.FindFile(const AName, ABaseDir: string; const ASearchPaths: TArray<string>;
  const AFileExists: TIncludeFileExists; out AFileName: string): Boolean;
var
  mName, mDir: string;
begin
  AFileName := '';
  mName := Unquote(AName);
  if mName = '' then
  begin
    Exit(False);
  end;
  if (ExtractFileDrive(mName) <> '') or mName.StartsWith('\') or mName.StartsWith('/') then
  begin
    AFileName := mName;
    Exit(AFileExists(AFileName));
  end;
  if ABaseDir <> '' then
  begin
    AFileName := ExpandFileName(IncludeTrailingPathDelimiter(ABaseDir) + mName);
    if AFileExists(AFileName) then
    begin
      Exit(True);
    end;
  end;
  for mDir in ASearchPaths do
  begin
    if mDir <> '' then
    begin
      AFileName := ExpandFileName(IncludeTrailingPathDelimiter(mDir) + mName);
      if AFileExists(AFileName) then
      begin
        Exit(True);
      end;
    end;
  end;
  AFileName := '';
  Result := False;
end;

class function TIncludeFiles.FindInclude(const AName, AFromFile: string; const ASearchPaths: TArray<string>;
  const AFileExists: TIncludeFileExists; out AFileName: string): Boolean;
var
  mName, mBaseDir: string;
begin
  mName := Unquote(AName);
  mBaseDir := ExtractFileDir(AFromFile);
  if FindFile(mName, mBaseDir, ASearchPaths, AFileExists, AFileName) then
  begin
    Exit(True);
  end;
  Result := (ExtractFileExt(mName) = '') and
    (FindFile(mName + '.inc', mBaseDir, ASearchPaths, AFileExists, AFileName) or
     FindFile(mName + '.pas', mBaseDir, ASearchPaths, AFileExists, AFileName));
end;

class function TIncludeFiles.ReadFile(const AFileName: string; out AText: string): Boolean;
var
  mFileFormat: TFileFormat;
begin
  AText := '';
  try
    AText := TFileEncoding.LoadFromFile(AFileName, mFileFormat);
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

// Die Vorgaben stehen in eigenen Routinen: Im selben Rahmen wie der Resolver hielte
// dieser sich über die eingefangenen Variablen selbst fest (Referenzzyklus, Leck).
function DiskExists: TIncludeFileExists;
begin
  Result :=
    function(const AFileName: string): Boolean
    begin
      Result := TFile.Exists(AFileName);
    end;
end;

function DiskReadText: TIncludeReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TIncludeFiles.ReadFile(AFileName, AText);
    end;
end;

class function TIncludeFiles.Resolver(const ASearchPaths: TArray<string>;
  const AFileExists: TIncludeFileExists): TIncludeResolver;
begin
  Result := Resolver(ASearchPaths, AFileExists, nil);
end;

class function TIncludeFiles.Resolver(const ASearchPaths: TArray<string>): TIncludeResolver;
begin
  Result := Resolver(ASearchPaths, nil, nil);
end;

class function TIncludeFiles.Resolver(const ASearchPaths: TArray<string>; const AFileExists: TIncludeFileExists;
  const AReadText: TIncludeReadText): TIncludeResolver;
var
  mPaths: TArray<string>;
  mExists: TIncludeFileExists;
  mRead: TIncludeReadText;
begin
  mPaths := ASearchPaths;
  mExists := AFileExists;
  if not Assigned(mExists) then
  begin
    mExists := DiskExists();
  end;
  mRead := AReadText;
  if not Assigned(mRead) then
  begin
    mRead := DiskReadText();
  end;
  Result :=
    function(const AName, AFromFile: string; out AFileName, AText: string): Boolean
    begin
      AText := '';
      Result := TIncludeFiles.FindInclude(AName, AFromFile, mPaths, mExists, AFileName) and mRead(AFileName, AText);
    end;
end;

end.
