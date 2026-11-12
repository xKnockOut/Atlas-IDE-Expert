unit Atlas.Core.Welcome.IndexFiles;

// Dateien der zuletzt geöffneten Projekte für das Suchfeld der
// Willkommensseite (#760), aus dem Index-Cache des Servers (#16) auf der
// Platte, ohne laufenden Server. Das Plugin bindet Atlas.Common nicht ein,
// deshalb steht hier ein kleiner Leser für Format 16 von
// Atlas.Common.Index.Cache: Kopf mit Prüfsumme, Texttabelle und die Köpfe der
// Units; Symbol- und Verwendungsblöcke werden übersprungen. Andere Version,
// falsche Prüfsumme oder fremder Inhalt ergeben eine leere Liste statt
// Unsinn.
// Ablage: <Cache>\Atlas\Index\<IDE-Version>\<Schlüssel>\index-<Format>.atlasidx
// (Formatversion im Namen wie TIndexCacheDirectory.CacheFileName). Der
// Schlüssel ist ein Hash über Projekt, Konfiguration, Suchpfade usw.
// (TIndexProjectFiles.Signature) und lässt sich ohne das Projekt nicht
// nachrechnen. Welches Projekt ein Cache beschreibt, steht deshalb in ihm
// selbst: Die Hauptdatei (.dpr/.dpk) ist eine seiner Units. Der gemeinsame
// Bibliotheks-Cache (Ordner „Bibliothek\<Schlüssel>“) gehört keinem Projekt.
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
    // Immer wie TIndexCache.cFormatVersion, weil Plugin und Server dasselbe Cache-Format lesen (Test
    // FormatVersionMatchesServer). 20: Verweise der inline-Rümpfe (#1017), 21: Hinweise im Unit-Kopf (#1018),
    // 22: Typparameter ohne Einschränkungstypen (#1029), 23: Unit-Name kein Hinweis (#1018), 24: Parser-Lücken
    // #848, #849, #861, #862, 25: Methodenzuordnungen je Klasse, 26: Namen ohne Escape-& (#1137), 27: Codepage-
    // Strings (#1140), 28: Begründungen (#1123), 29: Prozedurtypen vollständig (#1326). 19 (#1001) fehlte hier,
    // die Willkommensseite fand deshalb keinen Cache. 30: inline-Routinen ohne Verweise (#1381).
    // 31: Typargumente je Vorfahr.
    cFormatVersion = 32;
    cIndexFolder = 'Index';
    cLibraryFolder = 'Bibliothek';
  private
    class function ReadEntries(const AData: TBytes; AWithLibrary: Boolean;
      out AReason: string): TArray<TAtlasIndexFile>; static;
  public
    /// <summary>Name der Cache-Datei mit der Formatversion wie beim Server (index-29.atlasidx).</summary>
    class function CacheFileName: string; static;
    /// <summary>Units des Caches ohne die der Bibliothek; leer, wenn AData kein gültiger Cache in Format 15
    /// ist.</summary>
    class function Read(const AData: TBytes): TArray<TAtlasIndexFile>; overload; static;
    /// <summary>Wie oben; AReason nennt bei leerem Ergebnis den Grund ('' = gültig).</summary>
    class function Read(const AData: TBytes; out AReason: string): TArray<TAtlasIndexFile>; overload; static;
    /// <summary>Alle Units des Caches samt Bibliothek (#755); leer bei ungültigem Cache.</summary>
    class function ReadAll(const AData: TBytes): TArray<TAtlasIndexFile>; static;
    /// <summary>Units samt Bibliothek aus der Cache-Datei AFileName; leer, wenn sie fehlt, gesperrt oder ungültig
    /// ist.</summary>
    class function LoadUnits(const AFileName: string): TArray<TAtlasIndexFile>; static;
    /// <summary>Gemeinsame Bibliotheks-Caches unter ARoot\Index\*\Bibliothek\*\CacheFileName.</summary>
    class function LibraryCacheFiles(const ARoot: string): TArray<string>; static;
    /// <summary>Hauptdatei (.dpr, .dpk) unter AFiles; '' ohne.</summary>
    class function MainFileOf(const AFiles: TArray<TAtlasIndexFile>): string; static;
    /// <summary>Alle Projekt-Caches unter ARoot\Index\*\*\CacheFileName, ohne Bibliothek.</summary>
    class function CacheFiles(const ARoot: string): TArray<string>; static;
    /// <summary>AProjectFile (.dproj, .dpr, .dpk) und AMainFile benennen dasselbe Projekt: gleicher Pfad ohne
    /// Endung.</summary>
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
  cMagic: array[0..7] of Byte = (Ord('A'), Ord('T'), Ord('L'), Ord('A'), Ord('S'), Ord('I'), Ord('D'), Ord('X'));
  cChecksumSize = 4;
  cFlagLibrary = 1;

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
  mIndex: Integer;
begin
  Result := 2166136261;
  for mIndex := AFrom to ATo - 1 do
  begin
    Result := Cardinal(UInt64(Result xor AData[mIndex]) * 16777619);
  end;
end;

{ TReader }

function TReader.ReadByte: Byte;
begin
  if Position >= Limit then
  begin
    Fail;
  end;
  Result := Data[Position];
  Inc(Position);
end;

function TReader.ReadVar: UInt64;
var
  mShift: Integer;
  mValue: Byte;
begin
  Result := 0;
  mShift := 0;
  repeat
    if mShift > 63 then
    begin
      Fail;
    end;
    mValue := ReadByte;
    Result := Result or (UInt64(mValue and $7F) shl mShift);
    Inc(mShift, 7);
  until mValue < $80;
end;

function TReader.ReadCount: Integer;
var
  mValue: UInt64;
begin
  mValue := ReadVar;
  // Mehr Einträge als Bytes kann es nicht geben.
  if mValue > UInt64(Limit) then
  begin
    Fail;
  end;
  Result := Integer(mValue);
end;

procedure TReader.Skip(ACount: Integer);
begin
  if (ACount < 0) or (Position + ACount > Limit) then
  begin
    Fail;
  end;
  Inc(Position, ACount);
end;

function TReader.ReadString(const AStrings: TArray<string>): string;
var
  mIndex: UInt64;
begin
  mIndex := ReadVar;
  if mIndex >= UInt64(Length(AStrings)) then
  begin
    Fail;
  end;
  Result := AStrings[Integer(mIndex)];
end;

procedure TReader.SkipList;
var
  mCount, mIndex: Integer;
begin
  mCount := ReadCount;
  for mIndex := 1 to mCount do
  begin
    ReadVar;
  end;
end;

{ TAtlasWelcomeIndexFiles }

class function TAtlasWelcomeIndexFiles.CacheFileName: string;
begin
  Result := Format('index-%d.atlasidx', [cFormatVersion]);
end;

class function TAtlasWelcomeIndexFiles.Read(const AData: TBytes): TArray<TAtlasIndexFile>;
var
  mReason: string;
begin
  Result := Read(AData, mReason);
end;

class function TAtlasWelcomeIndexFiles.Read(const AData: TBytes; out AReason: string): TArray<TAtlasIndexFile>;
begin
  Result := ReadEntries(AData, False, AReason);
end;

class function TAtlasWelcomeIndexFiles.ReadAll(const AData: TBytes): TArray<TAtlasIndexFile>;
var
  mReason: string;
begin
  Result := ReadEntries(AData, True, mReason);
end;

function HasMagic(const AData: TBytes): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(AData) >= Length(cMagic);
  mIndex := Low(cMagic);
  while Result and (mIndex <= High(cMagic)) do
  begin
    Result := AData[mIndex] = cMagic[mIndex];
    Inc(mIndex);
  end;
end;

/// <summary>Liest die gespeicherte Prüfsumme und vergleicht sie mit der des Rests.</summary>
function ChecksumMatches(var AReader: TReader): Boolean;
var
  mIndex: Integer;
  mStored: Cardinal;
begin
  if AReader.Position + cChecksumSize > AReader.Limit then
  begin
    Fail;
  end;
  mStored := 0;
  for mIndex := cChecksumSize - 1 downto 0 do
  begin
    mStored := (mStored shl 8) or AReader.Data[AReader.Position + mIndex];
  end;
  Inc(AReader.Position, cChecksumSize);
  Result := mStored = ChecksumOf(AReader.Data, AReader.Position, Length(AReader.Data));
end;

function ReadStrings(var AReader: TReader): TArray<string>;
var
  mIndex, mSize: Integer;
begin
  SetLength(Result, AReader.ReadCount);
  for mIndex := 0 to High(Result) do
  begin
    mSize := AReader.ReadCount;
    if AReader.Position + mSize > AReader.Limit then
    begin
      Fail;
    end;
    Result[mIndex] := TEncoding.UTF8.GetString(AReader.Data, AReader.Position, mSize);
    Inc(AReader.Position, mSize);
  end;
end;

/// <summary>Ein Unit-Eintrag; liefert seine Flags. Alles außer Name und Datei wird übersprungen.</summary>
function ReadEntry(var AReader: TReader; const AStrings: TArray<string>; out AEntry: TAtlasIndexFile): Integer;
var
  mPart: Integer;
begin
  AEntry.UnitName := AReader.ReadString(AStrings);
  AEntry.FileName := AReader.ReadString(AStrings);
  AReader.ReadVar; // Zeitstempel
  AReader.ReadVar; // Hash
  Result := AReader.ReadCount;
  AReader.SkipList; // uses (interface)
  AReader.SkipList; // uses (implementation)
  AReader.SkipList; // Include-Dateien
  AReader.SkipList; // Include-Zeitstempel
  for mPart := 1 to 6 do
  begin
    AReader.ReadVar; // Präfix-Zählung (#452): je Art Anzahl und mit Präfix
  end;
  AReader.SkipList; // Hinweise im Unit-Kopf (#1018)
  AReader.ReadVar; // Grund hinter deprecated
  AReader.SkipList; // Begründungen der Unit (#1123)
  AReader.ReadVar; // Symbolzahl
  AReader.ReadVar; // nicht verfügbar
  AReader.Skip(AReader.ReadCount); // Symbolblock
  AReader.ReadVar; // Verwendungszahl
  AReader.Skip(AReader.ReadCount); // Verwendungsblock
  if AEntry.FileName = '' then
  begin
    Fail;
  end;
end;

/// <summary>Einträge nach Prüfsumme; wirft EIndexFormat bei kaputtem Inhalt.</summary>
function ReadUnits(var AReader: TReader; AWithLibrary: Boolean): TArray<TAtlasIndexFile>;
var
  mStrings: TArray<string>;
  mFound: TList<TAtlasIndexFile>;
  mIndex: Integer;
  mEntry: TAtlasIndexFile;
begin
  mStrings := ReadStrings(AReader);
  mFound := TList<TAtlasIndexFile>.Create;
  try
    for mIndex := 1 to AReader.ReadCount do
    begin
      if ((ReadEntry(AReader, mStrings, mEntry) and cFlagLibrary) = 0) or AWithLibrary then
      begin
        mFound.Add(mEntry);
      end;
    end;
    if AReader.Position <> AReader.Limit then
    begin
      Fail;
    end;
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

class function TAtlasWelcomeIndexFiles.ReadEntries(const AData: TBytes; AWithLibrary: Boolean;
  out AReason: string): TArray<TAtlasIndexFile>;
var
  mReader: TReader;
begin
  Result := nil;
  AReason := 'kein Atlas-Index (Kopf fehlt)';
  if not HasMagic(AData) then
  begin
    Exit;
  end;
  mReader.Data := AData;
  mReader.Position := Length(cMagic);
  mReader.Limit := Length(AData);
  try
    if mReader.ReadVar <> cFormatVersion then
    begin
      AReason := 'andere Formatversion';
    end
    else if not ChecksumMatches(mReader) then
    begin
      AReason := 'Prüfsumme stimmt nicht';
    end
    else
    begin
      Result := ReadUnits(mReader, AWithLibrary);
      AReason := '';
    end;
  except
    on EIndexFormat do
    begin
      Result := nil;
      AReason := 'Inhalt beschädigt';
    end;
  end;
end;

class function TAtlasWelcomeIndexFiles.MainFileOf(const AFiles: TArray<TAtlasIndexFile>): string;
var
  mEntry: TAtlasIndexFile;
  mExtension: string;
begin
  Result := '';
  for mEntry in AFiles do
  begin
    mExtension := LowerCase(ExtractFileExt(mEntry.FileName));
    if (mExtension = '.dpr') or (mExtension = '.dpk') then
    begin
      Exit(mEntry.FileName);
    end;
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
  begin
    Exit;
  end;
  Result := ChangeFileExt(AUnitFile, '.fmx');
  if not FileExists(Result) then
  begin
    Result := '';
  end;
end;

function SubFolders(const AFolder: string): TArray<string>;
var
  mSearch: TSearchRec;
begin
  Result := nil;
  if FindFirst(IncludeTrailingPathDelimiter(AFolder) + '*', faDirectory, mSearch) <> 0 then
  begin
    Exit;
  end;
  try
    repeat
      if ((mSearch.Attr and faDirectory) <> 0) and (mSearch.Name <> '.') and (mSearch.Name <> '..') then
      begin
        Result := Result + [IncludeTrailingPathDelimiter(AFolder) + mSearch.Name];
      end;
    until FindNext(mSearch) <> 0;
  finally
    FindClose(mSearch);
  end;
end;

class function TAtlasWelcomeIndexFiles.CacheFiles(const ARoot: string): TArray<string>;
var
  mVersion, mKey, mFileName: string;
begin
  Result := nil;
  if ARoot = '' then
  begin
    Exit;
  end;
  for mVersion in SubFolders(IncludeTrailingPathDelimiter(ARoot) + cIndexFolder) do
  begin
    for mKey in SubFolders(mVersion) do
    begin
      if SameText(ExtractFileName(mKey), cLibraryFolder) then
      begin
        Continue;
      end;
      mFileName := IncludeTrailingPathDelimiter(mKey) + CacheFileName;
      if FileExists(mFileName) then
      begin
        Result := Result + [mFileName];
      end;
    end;
  end;
end;

function ReadBytes(const AFileName: string): TBytes;
var
  mStream: TFileStream;
begin
  // Der Server kann die Datei gerade schreiben: nur lesen, Schreiben anderer zulassen.
  mStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, mStream.Size);
    if Length(Result) > 0 then
    begin
      mStream.ReadBuffer(Result[0], Length(Result));
    end;
  finally
    mStream.Free;
  end;
end;

class function TAtlasWelcomeIndexFiles.LibraryCacheFiles(const ARoot: string): TArray<string>;
var
  mVersion, mKey, mFileName: string;
begin
  Result := nil;
  if ARoot = '' then
  begin
    Exit;
  end;
  // Der Server legt je Bibliotheks-Schlüssel (Plattform, Suchpfade) einen Ordner unter „Bibliothek“ an.
  for mVersion in SubFolders(IncludeTrailingPathDelimiter(ARoot) + cIndexFolder) do
  begin
    for mKey in SubFolders(IncludeTrailingPathDelimiter(mVersion) + cLibraryFolder) do
    begin
      mFileName := IncludeTrailingPathDelimiter(mKey) + CacheFileName;
      if FileExists(mFileName) then
      begin
        Result := Result + [mFileName];
      end;
    end;
  end;
end;

class function TAtlasWelcomeIndexFiles.LoadUnits(const AFileName: string): TArray<TAtlasIndexFile>;
begin
  Result := nil;
  if not FileExists(AFileName) then
  begin
    Exit;
  end;
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

/// <summary>Cache AFileName mit Zeitstempel AStamp lesen; gesperrt oder verschwunden ergibt keine Units.</summary>
function LoadProject(const AFileName: string; AStamp: TDateTime): TAtlasIndexProject;
begin
  Result := Default(TAtlasIndexProject);
  Result.CacheFile := AFileName;
  Result.Stamp := AStamp;
  try
    Result.Files := TAtlasWelcomeIndexFiles.Read(ReadBytes(AFileName));
  except
    // Gesperrt oder verschwunden: beim nächsten Mal erneut versuchen.
    on EStreamError do
      Result.Files := nil;
    on EInOutError do
      Result.Files := nil;
  end;
  Result.MainFile := TAtlasWelcomeIndexFiles.MainFileOf(Result.Files);
end;

procedure TAtlasIndexProjects.Refresh;
var
  mFileName, mKey: string;
  mSeen: TDictionary<string, Boolean>;
  mKnown, mProject: TAtlasIndexProject;
  mStamp: TDateTime;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mFileName in TAtlasWelcomeIndexFiles.CacheFiles(FRoot) do
    begin
      mKey := AnsiUpperCase(mFileName);
      mSeen.AddOrSetValue(mKey, True);
      if not FileAge(mFileName, mStamp) or (FProjects.TryGetValue(mKey, mKnown) and (mKnown.Stamp = mStamp)) then
      begin
        Continue;
      end;
      mProject := LoadProject(mFileName, mStamp);
      if mProject.MainFile = '' then
      begin
        FProjects.Remove(mKey);
      end
      else
      begin
        FProjects.AddOrSetValue(mKey, mProject);
      end;
    end;
    for mKey in FProjects.Keys.ToArray do
    begin
      if not mSeen.ContainsKey(mKey) then
      begin
        FProjects.Remove(mKey);
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

function TAtlasIndexProjects.Projects: TArray<TAtlasIndexProject>;
var
  mNewest: TDictionary<string, TAtlasIndexProject>;
  mProject, mKnown: TAtlasIndexProject;
  mKey: string;
  mList: TList<TAtlasIndexProject>;
begin
  mNewest := TDictionary<string, TAtlasIndexProject>.Create;
  mList := TList<TAtlasIndexProject>.Create;
  try
    for mProject in FProjects.Values do
    begin
      mKey := AnsiUpperCase(ChangeFileExt(mProject.MainFile, ''));
      if not mNewest.TryGetValue(mKey, mKnown) or (mProject.Stamp > mKnown.Stamp) then
      begin
        mNewest.AddOrSetValue(mKey, mProject);
      end;
    end;
    for mProject in mNewest.Values do
    begin
      mList.Add(mProject);
    end;
    mList.Sort(TComparer<TAtlasIndexProject>.Construct(
      function(const A, B: TAtlasIndexProject): Integer
      begin
        if A.Stamp > B.Stamp then
        begin
          Result := -1;
        end
        else if A.Stamp < B.Stamp then
        begin
          Result := 1;
        end
        else
        begin
          Result := CompareText(A.MainFile, B.MainFile);
        end;
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
    mNewest.Free;
  end;
end;

function TAtlasIndexProjects.FilesOf(const AProjectFile: string): TArray<TAtlasIndexFile>;
var
  mProject: TAtlasIndexProject;
begin
  Result := nil;
  for mProject in Projects do
  begin
    if TAtlasWelcomeIndexFiles.SameProject(AProjectFile, mProject.MainFile) then
    begin
      Exit(mProject.Files);
    end;
  end;
end;

end.
