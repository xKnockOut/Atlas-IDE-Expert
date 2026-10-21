unit Atlas.Core.Welcome.IndexFiles;

// Dateien der zuletzt geöffneten Projekte für das Suchfeld der
// Willkommensseite (#760), aus dem Index-Cache des Servers (#16) auf der
// Platte, ohne laufenden Server. Das Plugin bindet Atlas.Common nicht ein,
// deshalb steht hier ein kleiner Leser für Format 16 von
// Atlas.Common.Index.Cache: Kopf mit Prüfsumme, Texttabelle und die Köpfe der
// Units; Symbol- und Verwendungsblöcke werden übersprungen. Andere Version,
// falsche Prüfsumme oder fremder Inhalt ergeben eine leere Liste statt
// Unsinn.
// Ablage: <Cache>\Atlas\Index\<IDE-Version>\<Schlüssel>\index.atlasidx. Der
// Schlüssel ist ein Hash über Projekt, Konfiguration, Suchpfade usw.
// (TIndexProjectFiles.Signature) und lässt sich ohne das Projekt nicht
// nachrechnen. Welches Projekt ein Cache beschreibt, steht deshalb in ihm
// selbst: Die Hauptdatei (.dpr/.dpk) ist eine seiner Units. Der gemeinsame
// Bibliotheks-Cache (Ordner „Bibliothek“) gehört keinem Projekt.
// Der Reiter „Gemerkt“ (#755) sucht die Unit eines Favoriten auch unter den
// Bibliotheks-Units (ReadAll, LibraryCacheFiles, LoadUnits).
// Nur SysUtils und Classes: läuft ohne Windows-Unit und in den Tests.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  TAtlasIndexFile = record
    UnitName: string;
    FileName: string;
  end;

  /// <summary>Ein Projekt-Cache: Hauptdatei, Datei und Alter, Units ohne Bibliothek.</summary>
  TAtlasIndexProject = record
    MainFile: string;
    CacheFile: string;
    /// <summary>Änderungszeit der Cache-Datei; der neueste Cache gewinnt (mehrere Konfigurationen).</summary>
    Stamp: TDateTime;
    Files: TArray<TAtlasIndexFile>;
  end;

  TAtlasWelcomeIndexFiles = class
  public const
    // 21: wie TIndexCache.FormatVersion (asm-Sprungmarke @@End, #861); beim Zusammenführen
    // der Zweige nachgezogen, weil Plugin und Server dasselbe Cache-Format lesen (K-05).
    FormatVersion = 21;
    CacheFileName = 'index.atlasidx';
    IndexFolder = 'Index';
    LibraryFolder = 'Bibliothek';
  private
    class function ReadEntries(const AData: TBytes; AWithLibrary: Boolean;
      out AReason: string): TArray<TAtlasIndexFile>; static;
  public
    /// <summary>Units des Caches ohne die der Bibliothek; leer, wenn AData kein gültiger Cache in Format 15 ist.</summary>
    class function Read(const AData: TBytes): TArray<TAtlasIndexFile>; overload; static;
    /// <summary>Wie oben; AReason nennt bei leerem Ergebnis den Grund ('' = gültig).</summary>
    class function Read(const AData: TBytes; out AReason: string): TArray<TAtlasIndexFile>; overload; static;
    /// <summary>Alle Units des Caches samt Bibliothek (#755); leer bei ungültigem Cache.</summary>
    class function ReadAll(const AData: TBytes): TArray<TAtlasIndexFile>; static;
    /// <summary>Units samt Bibliothek aus der Cache-Datei AFileName; leer, wenn sie fehlt, gesperrt oder ungültig
    /// ist.</summary>
    class function LoadUnits(const AFileName: string): TArray<TAtlasIndexFile>; static;
    /// <summary>Gemeinsame Bibliotheks-Caches unter ARoot\Index\*\Bibliothek\index.atlasidx.</summary>
    class function LibraryCacheFiles(const ARoot: string): TArray<string>; static;
    /// <summary>Hauptdatei (.dpr, .dpk) unter AFiles; '' ohne.</summary>
    class function MainFileOf(const AFiles: TArray<TAtlasIndexFile>): string; static;
    /// <summary>Alle Projekt-Caches unter ARoot\Index\*\*\index.atlasidx, ohne Bibliothek.</summary>
    class function CacheFiles(const ARoot: string): TArray<string>; static;
    /// <summary>AProjectFile (.dproj, .dpr, .dpk) und AMainFile benennen dasselbe Projekt: gleicher Pfad ohne Endung.</summary>
    class function SameProject(const AProjectFile, AMainFile: string): Boolean; static;
    /// <summary>Formular zu einer Unit: .dfm oder .fmx daneben ('' ohne).</summary>
    class function FormOf(const AUnitFile: string): string; static;
  end;

  /// <summary>Hält die gelesenen Caches; Refresh liest nur neue oder geänderte Dateien.</summary>
  TAtlasIndexProjects = class
  private
    FRoot: string;
    FProjects: TDictionary<string, TAtlasIndexProject>;
  public
    constructor Create(const ARoot: string);
    destructor Destroy; override;
    /// <summary>Ordner neu durchsuchen; nicht lesbare oder ungültige Caches fallen weg.</summary>
    procedure Refresh;
    /// <summary>Je Hauptdatei der neueste Cache, neueste zuerst.</summary>
    function Projects: TArray<TAtlasIndexProject>;
    /// <summary>Units des neuesten Caches zu AProjectFile; leer ohne Cache.</summary>
    function FilesOf(const AProjectFile: string): TArray<TAtlasIndexFile>;
    property Root: string read FRoot;
  end;

implementation

uses
  System.Generics.Defaults;

const
  Magic: array[0..7] of Byte = (Ord('A'), Ord('T'), Ord('L'), Ord('A'), Ord('S'), Ord('I'), Ord('D'), Ord('X'));
  ChecksumSize = 4;
  FlagLibrary = 1;

type
  EIndexFormat = class(Exception);

  TReader = record
    Data: TBytes;
    Position: Integer;
    Limit: Integer;
    function ReadByte: Byte;
    function ReadVar: UInt64;
    function ReadCount: Integer;
    procedure Skip(ACount: Integer);
    function ReadString(const AStrings: TArray<string>): string;
    procedure SkipList;
  end;

procedure Fail;
begin
  raise EIndexFormat.Create('Index-Cache beschädigt');
end;

/// <summary>FNV-1a (32 Bit) wie Atlas.Common.Index.Cache.</summary>
function ChecksumOf(const AData: TBytes; AFrom, ATo: Integer): Cardinal;
var
  Index: Integer;
begin
  Result := 2166136261;
  for Index := AFrom to ATo - 1 do
    Result := Cardinal(UInt64(Result xor AData[Index]) * 16777619);
end;

{ TReader }

function TReader.ReadByte: Byte;
begin
  if Position >= Limit then
    Fail;
  Result := Data[Position];
  Inc(Position);
end;

function TReader.ReadVar: UInt64;
var
  Shift: Integer;
  Value: Byte;
begin
  Result := 0;
  Shift := 0;
  repeat
    if Shift > 63 then
      Fail;
    Value := ReadByte;
    Result := Result or (UInt64(Value and $7F) shl Shift);
    Inc(Shift, 7);
  until Value < $80;
end;

function TReader.ReadCount: Integer;
var
  Value: UInt64;
begin
  Value := ReadVar;
  // Mehr Einträge als Bytes kann es nicht geben.
  if Value > UInt64(Limit) then
    Fail;
  Result := Integer(Value);
end;

procedure TReader.Skip(ACount: Integer);
begin
  if (ACount < 0) or (Position + ACount > Limit) then
    Fail;
  Inc(Position, ACount);
end;

function TReader.ReadString(const AStrings: TArray<string>): string;
var
  Index: UInt64;
begin
  Index := ReadVar;
  if Index >= UInt64(Length(AStrings)) then
    Fail;
  Result := AStrings[Integer(Index)];
end;

procedure TReader.SkipList;
var
  Count, Index: Integer;
begin
  Count := ReadCount;
  for Index := 1 to Count do
    ReadVar;
end;

{ TAtlasWelcomeIndexFiles }

class function TAtlasWelcomeIndexFiles.Read(const AData: TBytes): TArray<TAtlasIndexFile>;
var
  Reason: string;
begin
  Result := Read(AData, Reason);
end;

class function TAtlasWelcomeIndexFiles.Read(const AData: TBytes; out AReason: string): TArray<TAtlasIndexFile>;
begin
  Result := ReadEntries(AData, False, AReason);
end;

class function TAtlasWelcomeIndexFiles.ReadAll(const AData: TBytes): TArray<TAtlasIndexFile>;
var
  Reason: string;
begin
  Result := ReadEntries(AData, True, Reason);
end;

class function TAtlasWelcomeIndexFiles.ReadEntries(const AData: TBytes; AWithLibrary: Boolean;
  out AReason: string): TArray<TAtlasIndexFile>;
var
  Reader: TReader;
  Strings: TArray<string>;
  Found: TList<TAtlasIndexFile>;
  Index, Count, Size, Flags, Part: Integer;
  Stored: Cardinal;
  Entry: TAtlasIndexFile;
begin
  Result := nil;
  AReason := 'kein Atlas-Index (Kopf fehlt)';
  if Length(AData) < Length(Magic) then
    Exit;
  for Index := Low(Magic) to High(Magic) do
    if AData[Index] <> Magic[Index] then
      Exit;
  Reader.Data := AData;
  Reader.Position := Length(Magic);
  Reader.Limit := Length(AData);
  Found := TList<TAtlasIndexFile>.Create;
  try
    try
      if Reader.ReadVar <> FormatVersion then
      begin
        AReason := 'andere Formatversion';
        Exit;
      end;
      if Reader.Position + ChecksumSize > Reader.Limit then
        Fail;
      Stored := 0;
      for Index := ChecksumSize - 1 downto 0 do
        Stored := (Stored shl 8) or AData[Reader.Position + Index];
      Inc(Reader.Position, ChecksumSize);
      if Stored <> ChecksumOf(AData, Reader.Position, Length(AData)) then
      begin
        AReason := 'Prüfsumme stimmt nicht';
        Exit;
      end;
      Count := Reader.ReadCount;
      SetLength(Strings, Count);
      for Index := 0 to Count - 1 do
      begin
        Size := Reader.ReadCount;
        if Reader.Position + Size > Reader.Limit then
          Fail;
        Strings[Index] := TEncoding.UTF8.GetString(AData, Reader.Position, Size);
        Inc(Reader.Position, Size);
      end;
      Count := Reader.ReadCount;
      for Index := 0 to Count - 1 do
      begin
        Entry.UnitName := Reader.ReadString(Strings);
        Entry.FileName := Reader.ReadString(Strings);
        Reader.ReadVar; // Zeitstempel
        Reader.ReadVar; // Hash
        Flags := Reader.ReadCount;
        Reader.SkipList; // uses (interface)
        Reader.SkipList; // uses (implementation)
        Reader.SkipList; // Include-Dateien
        Reader.SkipList; // Include-Zeitstempel
        for Part := 1 to 6 do
          Reader.ReadVar; // Präfix-Zählung (#452): je Art Anzahl und mit Präfix
        Reader.ReadVar; // Symbolzahl
        Reader.ReadVar; // nicht verfügbar
        Reader.Skip(Reader.ReadCount); // Symbolblock
        Reader.ReadVar; // Verwendungszahl
        Reader.Skip(Reader.ReadCount); // Verwendungsblock
        if Entry.FileName = '' then
          Fail;
        if AWithLibrary or ((Flags and FlagLibrary) = 0) then
          Found.Add(Entry);
      end;
      if Reader.Position <> Reader.Limit then
        Fail;
      AReason := '';
      Result := Found.ToArray;
    except
      on EIndexFormat do
      begin
        Result := nil;
        AReason := 'Inhalt beschädigt';
      end;
    end;
  finally
    Found.Free;
  end;
end;

class function TAtlasWelcomeIndexFiles.MainFileOf(const AFiles: TArray<TAtlasIndexFile>): string;
var
  Entry: TAtlasIndexFile;
  Extension: string;
begin
  Result := '';
  for Entry in AFiles do
  begin
    Extension := LowerCase(ExtractFileExt(Entry.FileName));
    if (Extension = '.dpr') or (Extension = '.dpk') then
      Exit(Entry.FileName);
  end;
end;

class function TAtlasWelcomeIndexFiles.SameProject(const AProjectFile, AMainFile: string): Boolean;
begin
  Result := (AProjectFile <> '') and (AMainFile <> '') and
    SameText(ChangeFileExt(AProjectFile, ''), ChangeFileExt(AMainFile, ''));
end;

class function TAtlasWelcomeIndexFiles.FormOf(const AUnitFile: string): string;
begin
  Result := ChangeFileExt(AUnitFile, '.dfm');
  if FileExists(Result) then
    Exit;
  Result := ChangeFileExt(AUnitFile, '.fmx');
  if not FileExists(Result) then
    Result := '';
end;

function SubFolders(const AFolder: string): TArray<string>;
var
  Search: TSearchRec;
begin
  Result := nil;
  if FindFirst(IncludeTrailingPathDelimiter(AFolder) + '*', faDirectory, Search) <> 0 then
    Exit;
  try
    repeat
      if ((Search.Attr and faDirectory) <> 0) and (Search.Name <> '.') and (Search.Name <> '..') then
        Result := Result + [IncludeTrailingPathDelimiter(AFolder) + Search.Name];
    until FindNext(Search) <> 0;
  finally
    FindClose(Search);
  end;
end;

class function TAtlasWelcomeIndexFiles.CacheFiles(const ARoot: string): TArray<string>;
var
  Version, Key, FileName: string;
begin
  Result := nil;
  if ARoot = '' then
    Exit;
  for Version in SubFolders(IncludeTrailingPathDelimiter(ARoot) + IndexFolder) do
    for Key in SubFolders(Version) do
    begin
      if SameText(ExtractFileName(Key), LibraryFolder) then
        Continue;
      FileName := IncludeTrailingPathDelimiter(Key) + CacheFileName;
      if FileExists(FileName) then
        Result := Result + [FileName];
    end;
end;

function ReadBytes(const AFileName: string): TBytes;
var
  Stream: TFileStream;
begin
  // Der Server kann die Datei gerade schreiben: nur lesen, Schreiben anderer zulassen.
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, Stream.Size);
    if Length(Result) > 0 then
      Stream.ReadBuffer(Result[0], Length(Result));
  finally
    Stream.Free;
  end;
end;

class function TAtlasWelcomeIndexFiles.LibraryCacheFiles(const ARoot: string): TArray<string>;
var
  Version, FileName: string;
begin
  Result := nil;
  if ARoot = '' then
    Exit;
  for Version in SubFolders(IncludeTrailingPathDelimiter(ARoot) + IndexFolder) do
  begin
    FileName := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(Version) + LibraryFolder) + CacheFileName;
    if FileExists(FileName) then
      Result := Result + [FileName];
  end;
end;

class function TAtlasWelcomeIndexFiles.LoadUnits(const AFileName: string): TArray<TAtlasIndexFile>;
begin
  Result := nil;
  if not FileExists(AFileName) then
    Exit;
  try
    Result := ReadAll(ReadBytes(AFileName));
  except
    // Gesperrt oder gerade verschwunden: wie ohne Cache.
    on EStreamError do
      Result := nil;
    on EInOutError do
      Result := nil;
  end;
end;

{ TAtlasIndexProjects }

constructor TAtlasIndexProjects.Create(const ARoot: string);
begin
  inherited Create;
  FRoot := ARoot;
  FProjects := TDictionary<string, TAtlasIndexProject>.Create;
end;

destructor TAtlasIndexProjects.Destroy;
begin
  FProjects.Free;
  inherited;
end;

procedure TAtlasIndexProjects.Refresh;
var
  FileName, Key: string;
  Seen: TDictionary<string, Boolean>;
  Known: TAtlasIndexProject;
  Project: TAtlasIndexProject;
  Stamp: TDateTime;
  Keys: TArray<string>;
begin
  Seen := TDictionary<string, Boolean>.Create;
  try
    for FileName in TAtlasWelcomeIndexFiles.CacheFiles(FRoot) do
    begin
      Key := AnsiUpperCase(FileName);
      Seen.AddOrSetValue(Key, True);
      if not FileAge(FileName, Stamp) then
        Continue;
      if FProjects.TryGetValue(Key, Known) and (Known.Stamp = Stamp) then
        Continue;
      Project := Default(TAtlasIndexProject);
      Project.CacheFile := FileName;
      Project.Stamp := Stamp;
      try
        Project.Files := TAtlasWelcomeIndexFiles.Read(ReadBytes(FileName));
      except
        // Gesperrt oder verschwunden: beim nächsten Mal erneut versuchen.
        on EStreamError do
          Project.Files := nil;
        on EInOutError do
          Project.Files := nil;
      end;
      Project.MainFile := TAtlasWelcomeIndexFiles.MainFileOf(Project.Files);
      if Project.MainFile = '' then
        FProjects.Remove(Key)
      else
        FProjects.AddOrSetValue(Key, Project);
    end;
    Keys := FProjects.Keys.ToArray;
    for Key in Keys do
      if not Seen.ContainsKey(Key) then
        FProjects.Remove(Key);
  finally
    Seen.Free;
  end;
end;

function TAtlasIndexProjects.Projects: TArray<TAtlasIndexProject>;
var
  Newest: TDictionary<string, TAtlasIndexProject>;
  Project, Known: TAtlasIndexProject;
  Key: string;
  List: TList<TAtlasIndexProject>;
begin
  Newest := TDictionary<string, TAtlasIndexProject>.Create;
  List := TList<TAtlasIndexProject>.Create;
  try
    for Project in FProjects.Values do
    begin
      Key := AnsiUpperCase(ChangeFileExt(Project.MainFile, ''));
      if not Newest.TryGetValue(Key, Known) or (Project.Stamp > Known.Stamp) then
        Newest.AddOrSetValue(Key, Project);
    end;
    for Project in Newest.Values do
      List.Add(Project);
    List.Sort(TComparer<TAtlasIndexProject>.Construct(
      function(const A, B: TAtlasIndexProject): Integer
      begin
        if A.Stamp > B.Stamp then
          Result := -1
        else if A.Stamp < B.Stamp then
          Result := 1
        else
          Result := CompareText(A.MainFile, B.MainFile);
      end));
    Result := List.ToArray;
  finally
    List.Free;
    Newest.Free;
  end;
end;

function TAtlasIndexProjects.FilesOf(const AProjectFile: string): TArray<TAtlasIndexFile>;
var
  Project: TAtlasIndexProject;
begin
  Result := nil;
  for Project in Projects do
    if TAtlasWelcomeIndexFiles.SameProject(AProjectFile, Project.MainFile) then
      Exit(Project.Files);
end;

end.
