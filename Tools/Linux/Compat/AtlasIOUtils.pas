{$mode delphi}{$H+}{$modeswitch unicodestrings}{$modeswitch advancedrecords}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}{$modeswitch typehelpers}
unit AtlasIOUtils;

// Ersatz für Delphis System.IOUtils im Linux-Bau (#1109). Convert-ForFpc.py
// leitet System.IOUtils hierher um. Die Fassung aus vcl-compat von FPC
// arbeitet mit AnsiString-Feldern (TStringDynArray) und kennt TFile.GetSize und
// TFile.SetLastWriteTime nicht. Diese Unit bietet genau die Teile, die Atlas
// benutzt, mit den Signaturen und dem Verhalten von Delphi: Pfade als
// UnicodeString, TArray<string> als Ergebnis, Ausnahmen bei fehlenden Dateien.

interface

uses
  SysUtils, Classes, DelphiCompat;

type
{$SCOPEDENUMS ON}
  TSearchOption = (soTopDirectoryOnly, soAllDirectories);
{$SCOPEDENUMS OFF}

  TPath = record
  public
    class function Combine(const APath1, APath2: string): string; overload; static;
    class function Combine(const APath1, APath2, APath3: string): string; overload; static;
    class function GetFullPath(const APath: string): string; static;
    class function GetDirectoryName(const AFileName: string): string; static;
    class function GetFileName(const AFileName: string): string; static;
    class function GetFileNameWithoutExtension(const AFileName: string): string; static;
    class function GetExtension(const AFileName: string): string; static;
    class function ChangeExtension(const APath, AExtension: string): string; static;
    class function IsPathRooted(const APath: string): Boolean; static;
    class function IsRelativePath(const APath: string): Boolean; static;
    class function GetTempPath: string; static;
    class function GetTempFileName: string; static;
    class function GetHomePath: string; static;
    class function GetDocumentsPath: string; static;
    class function GetCachePath: string; static;
    class function DirectorySeparatorChar: Char; static;
  end;

  TFile = record
  public
    class function Exists(const AFileName: string): Boolean; static;
    class function ReadAllBytes(const AFileName: string): TBytes; static;
    class function ReadAllText(const AFileName: string): string; overload; static;
    class function ReadAllText(const AFileName: string; const AEncoding: TEncoding): string; overload; static;
    class function ReadAllLines(const AFileName: string): TArray<string>; overload; static;
    class function ReadAllLines(const AFileName: string; const AEncoding: TEncoding): TArray<string>; overload; static;
    class procedure WriteAllBytes(const AFileName: string; const ABytes: TBytes); static;
    class procedure WriteAllText(const AFileName, AContents: string); overload; static;
    class procedure WriteAllText(const AFileName, AContents: string; const AEncoding: TEncoding); overload; static;
    class procedure WriteAllLines(const AFileName: string; const AContents: TArray<string>); overload; static;
    class procedure WriteAllLines(const AFileName: string; const AContents: TArray<string>;
      const AEncoding: TEncoding); overload; static;
    class procedure AppendAllText(const AFileName, AContents: string); overload; static;
    class procedure Delete(const AFileName: string); static;
    class procedure Move(const ASourceFileName, ADestFileName: string); static;
    class procedure Copy(const ASourceFileName, ADestFileName: string; AOverwrite: Boolean); overload; static;
    class procedure Copy(const ASourceFileName, ADestFileName: string); overload; static;
    class procedure Replace(const ASourceFileName, ADestinationFileName, ADestinationBackupFileName: string); static;
    class function GetSize(const AFileName: string): Int64; static;
    class function GetLastWriteTime(const AFileName: string): TDateTime; static;
    class function GetLastWriteTimeUtc(const AFileName: string): TDateTime; static;
    class procedure SetLastWriteTime(const AFileName: string; const ADateTime: TDateTime); static;
  end;

  TDirectory = record
  public
    class function Exists(const APath: string): Boolean; overload; static;
    class function Exists(const APath: string; AFollowLink: Boolean): Boolean; overload; static;
    class procedure CreateDirectory(const APath: string); static;
    class procedure Delete(const APath: string); overload; static;
    class procedure Delete(const APath: string; const ARecursive: Boolean); overload; static;
    class function IsEmpty(const APath: string): Boolean; static;
    class function GetParent(const APath: string): string; static;
    class function GetCurrentDirectory: string; static;
    class function GetLastWriteTime(const APath: string): TDateTime; static;
    class function GetFiles(const APath: string): TArray<string>; overload; static;
    class function GetFiles(const APath, ASearchPattern: string): TArray<string>; overload; static;
    class function GetFiles(const APath, ASearchPattern: string; ASearchOption: TSearchOption): TArray<string>;
      overload; static;
    class function GetFiles(const APath: string; ASearchOption: TSearchOption): TArray<string>; overload; static;
    class function GetDirectories(const APath: string): TArray<string>; overload; static;
    class function GetDirectories(const APath, ASearchPattern: string): TArray<string>; overload; static;
    class function GetDirectories(const APath, ASearchPattern: string;
      ASearchOption: TSearchOption): TArray<string>; overload; static;
  end;

implementation

uses
  BaseUnix, DateUtils;

{ TPath }

class function TPath.Combine(const APath1, APath2: string): string;
begin
  if APath1 = '' then
    Exit(APath2);
  if APath2 = '' then
    Exit(APath1);
  if IsPathRooted(APath2) then
    Exit(APath2);
  Result := IncludeTrailingPathDelimiter(APath1) + APath2;
end;

class function TPath.Combine(const APath1, APath2, APath3: string): string;
begin
  Result := Combine(Combine(APath1, APath2), APath3);
end;

class function TPath.GetFullPath(const APath: string): string;
begin
  Result := ExpandFileName(APath);
end;

class function TPath.GetDirectoryName(const AFileName: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(ExtractFilePath(AFileName));
  if (Result = '') and (AFileName <> '') and (AFileName[1] = PathDelim) then
    Result := PathDelim;
end;

class function TPath.GetFileName(const AFileName: string): string;
begin
  Result := ExtractFileName(AFileName);
end;

class function TPath.GetFileNameWithoutExtension(const AFileName: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AFileName), '');
end;

class function TPath.GetExtension(const AFileName: string): string;
begin
  Result := ExtractFileExt(AFileName);
end;

class function TPath.ChangeExtension(const APath, AExtension: string): string;
begin
  if (AExtension <> '') and (AExtension[1] <> '.') then
    Result := ChangeFileExt(APath, '.' + AExtension)
  else
    Result := ChangeFileExt(APath, AExtension);
end;

class function TPath.IsPathRooted(const APath: string): Boolean;
begin
  Result := (APath <> '') and (APath[1] = PathDelim);
end;

class function TPath.IsRelativePath(const APath: string): Boolean;
begin
  Result := not IsPathRooted(APath);
end;

class function TPath.GetTempPath: string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir(False));
end;

class function TPath.GetTempFileName: string;
begin
  Result := SysUtils.GetTempFileName(GetTempDir(False), 'atlas');
  FileClose(FileCreate(Result));
end;

class function TPath.GetHomePath: string;
begin
  Result := ExcludeTrailingPathDelimiter(GetUserDir);
end;

class function TPath.GetDocumentsPath: string;
begin
  Result := GetHomePath;
end;

class function TPath.GetCachePath: string;
begin
  Result := GetEnvironmentVariable('XDG_CACHE_HOME');
  if Result = '' then
    Result := Combine(GetHomePath, '.cache');
end;

class function TPath.DirectorySeparatorChar: Char;
begin
  Result := PathDelim;
end;

{ TFile }

class function TFile.Exists(const AFileName: string): Boolean;
begin
  Result := FileExists(AFileName) and not DirectoryExists(AFileName);
end;

class function TFile.ReadAllBytes(const AFileName: string): TBytes;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, Stream.Size);
    if Length(Result) > 0 then
      Stream.ReadBuffer(Result[0], Length(Result));
  finally
    Stream.Free;
  end;
end;

/// <summary>Wie Delphi: eine Präambel (BOM) bestimmt die Kodierung, sonst gilt ADefault.</summary>
function DecodeText(const ABytes: TBytes; ADefault: TEncoding): string;
var
  Encoding: TEncoding;
  Skip: Integer;
begin
  Encoding := nil;
  Skip := TEncoding.GetBufferEncoding(ABytes, Encoding, ADefault);
  Result := Encoding.GetString(ABytes, Skip, Length(ABytes) - Skip);
end;

class function TFile.ReadAllText(const AFileName: string): string;
begin
  Result := DecodeText(ReadAllBytes(AFileName), TEncoding.UTF8);
end;

class function TFile.ReadAllText(const AFileName: string; const AEncoding: TEncoding): string;
begin
  Result := DecodeText(ReadAllBytes(AFileName), AEncoding);
end;

function SplitText(const AText: string): TArray<string>;
var
  Lines: TStringList;
  Index: Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    SetLength(Result, Lines.Count);
    for Index := 0 to Lines.Count - 1 do
      Result[Index] := Lines[Index];
  finally
    Lines.Free;
  end;
end;

class function TFile.ReadAllLines(const AFileName: string): TArray<string>;
begin
  Result := SplitText(ReadAllText(AFileName));
end;

class function TFile.ReadAllLines(const AFileName: string; const AEncoding: TEncoding): TArray<string>;
begin
  Result := SplitText(ReadAllText(AFileName, AEncoding));
end;

class procedure TFile.WriteAllBytes(const AFileName: string; const ABytes: TBytes);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(ABytes) > 0 then
      Stream.WriteBuffer(ABytes[0], Length(ABytes));
  finally
    Stream.Free;
  end;
end;

class procedure TFile.WriteAllText(const AFileName, AContents: string);
begin
  // Delphi schreibt ohne Kodierung UTF-8 ohne BOM.
  WriteAllBytes(AFileName, TEncoding.UTF8.GetBytes(AContents));
end;

class procedure TFile.WriteAllText(const AFileName, AContents: string; const AEncoding: TEncoding);
begin
  WriteAllBytes(AFileName, Concat(AEncoding.GetPreamble, AEncoding.GetBytes(AContents)));
end;

function JoinLines(const AContents: TArray<string>): string;
var
  Line: string;
begin
  Result := '';
  for Line in AContents do
    Result := Result + Line + sLineBreak;
end;

class procedure TFile.WriteAllLines(const AFileName: string; const AContents: TArray<string>);
begin
  WriteAllText(AFileName, JoinLines(AContents));
end;

class procedure TFile.WriteAllLines(const AFileName: string; const AContents: TArray<string>;
  const AEncoding: TEncoding);
begin
  WriteAllText(AFileName, JoinLines(AContents), AEncoding);
end;

class procedure TFile.AppendAllText(const AFileName, AContents: string);
var
  Stream: TFileStream;
  Bytes: TBytes;
begin
  if FileExists(AFileName) then
    Stream := TFileStream.Create(AFileName, fmOpenReadWrite)
  else
    Stream := TFileStream.Create(AFileName, fmCreate);
  try
    Stream.Seek(0, soEnd);
    Bytes := TEncoding.UTF8.GetBytes(AContents);
    if Length(Bytes) > 0 then
      Stream.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    Stream.Free;
  end;
end;

class procedure TFile.Delete(const AFileName: string);
begin
  if FileExists(AFileName) and not DeleteFile(AFileName) then
    raise EInOutError.CreateFmt('Datei "%s" lässt sich nicht löschen', [AFileName]);
end;

class procedure TFile.Move(const ASourceFileName, ADestFileName: string);
begin
  if not RenameFile(ASourceFileName, ADestFileName) then
    raise EInOutError.CreateFmt('Datei "%s" lässt sich nicht nach "%s" verschieben', [ASourceFileName, ADestFileName]);
end;

class procedure TFile.Copy(const ASourceFileName, ADestFileName: string; AOverwrite: Boolean);
begin
  if not AOverwrite and FileExists(ADestFileName) then
    raise EInOutError.CreateFmt('Datei "%s" gibt es schon', [ADestFileName]);
  WriteAllBytes(ADestFileName, ReadAllBytes(ASourceFileName));
end;

class procedure TFile.Copy(const ASourceFileName, ADestFileName: string);
begin
  Copy(ASourceFileName, ADestFileName, False);
end;

class procedure TFile.Replace(const ASourceFileName, ADestinationFileName, ADestinationBackupFileName: string);
begin
  // rename(2) ersetzt das Ziel atomar; die Sicherung entsteht vorher als Kopie.
  if (ADestinationBackupFileName <> '') and FileExists(ADestinationFileName) then
    Copy(ADestinationFileName, ADestinationBackupFileName, True);
  if FpRename(UTF8String(ASourceFileName), UTF8String(ADestinationFileName)) <> 0 then
    raise EInOutError.CreateFmt('Datei "%s" lässt sich nicht durch "%s" ersetzen',
      [ADestinationFileName, ASourceFileName]);
end;

function StatOf(const AFileName: string; out AInfo: Stat): Boolean;
begin
  Result := FpStat(UTF8String(AFileName), AInfo) = 0;
end;

class function TFile.GetSize(const AFileName: string): Int64;
var
  Info: Stat;
begin
  if not StatOf(AFileName, Info) then
    raise EInOutError.CreateFmt('Datei "%s" fehlt', [AFileName]);
  Result := Info.st_size;
end;

class function TFile.GetLastWriteTimeUtc(const AFileName: string): TDateTime;
var
  Info: Stat;
begin
  if not StatOf(AFileName, Info) then
    raise EInOutError.CreateFmt('Datei "%s" fehlt', [AFileName]);
  Result := UnixToDateTime(Info.st_mtime, True) + Info.st_mtime_nsec / (Int64(1000000000) * SecsPerDay);
end;

class function TFile.GetLastWriteTime(const AFileName: string): TDateTime;
begin
  Result := UniversalTimeToLocal(GetLastWriteTimeUtc(AFileName));
end;

class procedure TFile.SetLastWriteTime(const AFileName: string; const ADateTime: TDateTime);
begin
  if FileSetDate(AFileName, DateTimeToFileDate(ADateTime)) <> 0 then
    raise EInOutError.CreateFmt('Zeit von "%s" lässt sich nicht setzen', [AFileName]);
end;

{ TDirectory }

class function TDirectory.Exists(const APath: string): Boolean;
begin
  Result := DirectoryExists(APath);
end;

class function TDirectory.Exists(const APath: string; AFollowLink: Boolean): Boolean;
begin
  Result := DirectoryExists(APath, AFollowLink);
end;

class procedure TDirectory.CreateDirectory(const APath: string);
begin
  if not ForceDirectories(APath) then
    raise EInOutError.CreateFmt('Ordner "%s" lässt sich nicht anlegen', [APath]);
end;

procedure DeleteTree(const APath: string);
var
  Search: TSearchRec;
  Child: string;
begin
  if FindFirst(IncludeTrailingPathDelimiter(APath) + '*', faAnyFile or faSymLink, Search) = 0 then
    try
      repeat
        if (Search.Name = '.') or (Search.Name = '..') then
          Continue;
        Child := IncludeTrailingPathDelimiter(APath) + Search.Name;
        if (Search.Attr and faDirectory <> 0) and (Search.Attr and faSymLink = 0) then
          DeleteTree(Child)
        else
          DeleteFile(Child);
      until FindNext(Search) <> 0;
    finally
      FindClose(Search);
    end;
  RemoveDir(APath);
end;

class procedure TDirectory.Delete(const APath: string);
begin
  if not RemoveDir(APath) then
    raise EInOutError.CreateFmt('Ordner "%s" lässt sich nicht löschen', [APath]);
end;

class procedure TDirectory.Delete(const APath: string; const ARecursive: Boolean);
begin
  if ARecursive then
    DeleteTree(APath)
  else
    Delete(APath);
end;

procedure Collect(const APath, APattern: string; AFiles: Boolean; ARecursive: Boolean; var AResult: TArray<string>);
var
  Search: TSearchRec;
  Base: string;
  IsDir: Boolean;
begin
  Base := IncludeTrailingPathDelimiter(APath);
  if FindFirst(Base + APattern, faAnyFile, Search) = 0 then
    try
      repeat
        if (Search.Name = '.') or (Search.Name = '..') then
          Continue;
        IsDir := Search.Attr and faDirectory <> 0;
        if IsDir <> AFiles then
          AResult := AResult + [Base + Search.Name];
      until FindNext(Search) <> 0;
    finally
      FindClose(Search);
    end;
  if not ARecursive then
    Exit;
  if FindFirst(Base + '*', faDirectory, Search) = 0 then
    try
      repeat
        if (Search.Name <> '.') and (Search.Name <> '..') and (Search.Attr and faDirectory <> 0) and
          (Search.Attr and faSymLink = 0) then
          Collect(Base + Search.Name, APattern, AFiles, True, AResult);
      until FindNext(Search) <> 0;
    finally
      FindClose(Search);
    end;
end;

function Pattern(const ASearchPattern: string): string;
begin
  // Delphi: "*.*" trifft auch Dateien ohne Punkt.
  if (ASearchPattern = '') or (ASearchPattern = '*.*') then
    Result := '*'
  else
    Result := ASearchPattern;
end;

function Listing(const APath, ASearchPattern: string; AFiles: Boolean; ASearchOption: TSearchOption): TArray<string>;
begin
  if not DirectoryExists(APath) then
    raise EInOutError.CreateFmt('Ordner "%s" fehlt', [APath]);
  Result := nil;
  Collect(ExcludeTrailingPathDelimiter(APath), Pattern(ASearchPattern), AFiles,
    ASearchOption = TSearchOption.soAllDirectories, Result);
end;

class function TDirectory.IsEmpty(const APath: string): Boolean;
var
  Search: TSearchRec;
begin
  Result := True;
  if FindFirst(IncludeTrailingPathDelimiter(APath) + '*', faAnyFile, Search) = 0 then
    try
      repeat
        if (Search.Name <> '.') and (Search.Name <> '..') then
          Exit(False);
      until FindNext(Search) <> 0;
    finally
      FindClose(Search);
    end;
end;

class function TDirectory.GetParent(const APath: string): string;
begin
  Result := TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(APath));
end;

class function TDirectory.GetCurrentDirectory: string;
begin
  Result := GetCurrentDir;
end;

class function TDirectory.GetLastWriteTime(const APath: string): TDateTime;
begin
  Result := TFile.GetLastWriteTime(APath);
end;

class function TDirectory.GetFiles(const APath: string): TArray<string>;
begin
  Result := Listing(APath, '*', True, TSearchOption.soTopDirectoryOnly);
end;

class function TDirectory.GetFiles(const APath, ASearchPattern: string): TArray<string>;
begin
  Result := Listing(APath, ASearchPattern, True, TSearchOption.soTopDirectoryOnly);
end;

class function TDirectory.GetFiles(const APath, ASearchPattern: string; ASearchOption: TSearchOption): TArray<string>;
begin
  Result := Listing(APath, ASearchPattern, True, ASearchOption);
end;

class function TDirectory.GetFiles(const APath: string; ASearchOption: TSearchOption): TArray<string>;
begin
  Result := Listing(APath, '*', True, ASearchOption);
end;

class function TDirectory.GetDirectories(const APath: string): TArray<string>;
begin
  Result := Listing(APath, '*', False, TSearchOption.soTopDirectoryOnly);
end;

class function TDirectory.GetDirectories(const APath, ASearchPattern: string): TArray<string>;
begin
  Result := Listing(APath, ASearchPattern, False, TSearchOption.soTopDirectoryOnly);
end;

class function TDirectory.GetDirectories(const APath, ASearchPattern: string;
  ASearchOption: TSearchOption): TArray<string>;
begin
  Result := Listing(APath, ASearchPattern, False, ASearchOption);
end;

end.
