unit Atlas.Common.Projects.PackageLocator;

// Findet ein Package aus requires und beantwortet, ob es eine Unit liefert
// (#46). Zuerst die Quelle <Name>.dpk in den bekannten Ordnern (Projekte der
// Gruppe, Suchpfade): Ihr contains ist die Antwort. Sonst das übersetzte
// <Name>.dcp in den Bibliothekspfaden: Es enthält die Namen seiner Units als
// Zeichenketten, die Suche danach ist eine Näherung ohne das DCP-Format.
// Ergebnisse bleiben je Package im Speicher; der Zugriff ist threadsicher.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.PackageReader;

type
  /// <summary>Liest eine Datei; False, wenn sie fehlt oder nicht lesbar ist.</summary>
  TPackageReadFile = reference to function(const AFileName: string; out AData: TBytes): Boolean;

  TPackageLocator = class
  private type
    TFound = record
      Known: Boolean;
      FileName: string;
      Source: TPackageSource;
      Compiled: TBytes;
    end;
  private
    FFolders: TArray<string>;
    FReadFile: TPackageReadFile;
    FCache: TDictionary<string, TFound>;
    FLock: TObject;
    function Find(const APackage: string): TFound;
  public
    /// <summary>AFolders in Suchreihenfolge; Dateien vom Dateisystem.</summary>
    constructor Create(const AFolders: TArray<string>); overload;
    constructor Create(const AFolders: TArray<string>; const AReadFile: TPackageReadFile); overload;
    destructor Destroy; override;
    /// <summary>True, wenn das Package gefunden wurde; AContains sagt dann, ob es AUnitName liefert.</summary>
    function Provides(const APackage, AUnitName: string; out AContains: Boolean): Boolean;
    /// <summary>Quelle &lt;APackage&gt;.dpk; False, wenn es keine gibt (auch, wenn nur ein .dcp da ist).</summary>
    function FindSource(const APackage: string; out AFileName: string; out ASource: TPackageSource): Boolean;
    /// <summary>Namen aus requires der Quelle &lt;APackage&gt;.dpk; leer ohne Quelle (ein .dcp nennt sie nicht).
    /// </summary>
    function Requires(const APackage: string): TArray<string>;
    /// <summary>Kommt AUnitName als ganzer Name in den Bytes eines .dcp vor (ohne Groß-/Kleinschreibung)?</summary>
    class function CompiledContains(const AData: TBytes; const AUnitName: string): Boolean; static;
    /// <summary>Dateien aus contains mit in '…', vollständig zum Ordner von AFileName (der .dpk).</summary>
    class function ContainedFiles(const AFileName: string; const ASource: TPackageSource): TArray<string>; static;
    /// <summary>contains-Dateien der requires-Packages von ASource mit Quelltext, auch über deren requires;
    /// ohne Doppelte, in Suchreihenfolge.</summary>
    function RequiredFiles(const ASource: TPackageSource): TArray<string>;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding;

function DiskReadFile: TPackageReadFile;
begin
  Result :=
    function(const AFileName: string; out AData: TBytes): Boolean
    begin
      AData := nil;
      Result := TFile.Exists(AFileName);
      if Result then
      try
        AData := TFile.ReadAllBytes(AFileName);
      except
        // Gesperrte oder nicht lesbare Dateien zählen als fehlend.
        on Exception do
          Result := False;
      end;
    end;
end;

function IsNameByte(AByte: Byte): Boolean;
begin
  Result := (AByte in [Ord('A')..Ord('Z'), Ord('a')..Ord('z'), Ord('0')..Ord('9'), Ord('_'), Ord('.')]) or
    (AByte >= $80);
end;

function UpperByte(AByte: Byte): Byte;
begin
  Result := AByte;
  if AByte in [Ord('a')..Ord('z')] then
    Result := AByte - 32;
end;

{ TPackageLocator }

constructor TPackageLocator.Create(const AFolders: TArray<string>);
begin
  Create(AFolders, DiskReadFile());
end;

constructor TPackageLocator.Create(const AFolders: TArray<string>; const AReadFile: TPackageReadFile);
begin
  inherited Create;
  FFolders := AFolders;
  FReadFile := AReadFile;
  FCache := TDictionary<string, TFound>.Create;
  FLock := TObject.Create;
end;

destructor TPackageLocator.Destroy;
begin
  FLock.Free;
  FCache.Free;
  inherited;
end;

class function TPackageLocator.CompiledContains(const AData: TBytes; const AUnitName: string): Boolean;
var
  Name: TBytes;
  Start, Offset: Integer;
  Matches: Boolean;
begin
  Result := False;
  Name := TEncoding.ASCII.GetBytes(UpperCase(AUnitName));
  if Length(Name) = 0 then
    Exit;
  for Start := 0 to Length(AData) - Length(Name) do
  begin
    if (Start > 0) and IsNameByte(AData[Start - 1]) then
      Continue;
    Matches := True;
    for Offset := 0 to High(Name) do
      if UpperByte(AData[Start + Offset]) <> Name[Offset] then
      begin
        Matches := False;
        Break;
      end;
    if Matches and ((Start + Length(Name) >= Length(AData)) or not IsNameByte(AData[Start + Length(Name)])) then
      Exit(True);
  end;
end;

function TPackageLocator.Find(const APackage: string): TFound;
var
  Key, Folder, FileName: string;
  Data: TBytes;
  FileFormat: TFileFormat;
begin
  Key := UpperCase(APackage);
  TMonitor.Enter(FLock);
  try
    if FCache.TryGetValue(Key, Result) then
      Exit;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := Default(TFound);
  for Folder in FFolders do
  begin
    FileName := TPath.Combine(Folder, APackage + '.dpk');
    if FReadFile(FileName, Data) then
    begin
      Result.Source := TPackageReader.Read(TFileEncoding.Decode(Data, FileFormat));
      if Result.Source.IsPackage then
      begin
        Result.Known := True;
        Result.FileName := FileName;
        Break;
      end;
    end;
  end;
  if not Result.Known then
    for Folder in FFolders do
    begin
      FileName := TPath.Combine(Folder, APackage + '.dcp');
      if FReadFile(FileName, Data) then
      begin
        Result.Known := True;
        Result.FileName := FileName;
        Result.Compiled := Data;
        Break;
      end;
    end;
  TMonitor.Enter(FLock);
  try
    FCache.AddOrSetValue(Key, Result);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TPackageLocator.Provides(const APackage, AUnitName: string; out AContains: Boolean): Boolean;
var
  Found: TFound;
begin
  Found := Find(APackage);
  Result := Found.Known;
  if Found.Source.IsPackage then
    AContains := Found.Source.ContainsIndex(AUnitName) >= 0
  else
    AContains := Result and CompiledContains(Found.Compiled, AUnitName);
end;

class function TPackageLocator.ContainedFiles(const AFileName: string;
  const ASource: TPackageSource): TArray<string>;
var
  Entry: TPackageEntry;
  Folder: string;
begin
  Result := nil;
  Folder := ExtractFilePath(AFileName);
  for Entry in ASource.Contains do
    if Entry.Path <> '' then
      Result := Result + [ExpandFileName(TPath.Combine(Folder, Entry.Path))];
end;

function TPackageLocator.RequiredFiles(const ASource: TPackageSource): TArray<string>;
var
  Seen, Files: TDictionary<string, Boolean>;
  Pending: TQueue<TPackageSource>;
  Current, Required: TPackageSource;
  Entry: TPackageEntry;
  FileName, Item: string;
begin
  Result := nil;
  Seen := TDictionary<string, Boolean>.Create;
  Files := TDictionary<string, Boolean>.Create;
  Pending := TQueue<TPackageSource>.Create;
  try
    Seen.Add(UpperCase(ASource.Name), True);
    Pending.Enqueue(ASource);
    while Pending.Count > 0 do
    begin
      Current := Pending.Dequeue;
      for Entry in Current.Requires do
      begin
        if Seen.ContainsKey(UpperCase(Entry.Name)) then
          Continue;
        Seen.Add(UpperCase(Entry.Name), True);
        if not FindSource(Entry.Name, FileName, Required) then
          Continue;
        for Item in ContainedFiles(FileName, Required) do
          if not Files.ContainsKey(UpperCase(Item)) then
          begin
            Files.Add(UpperCase(Item), True);
            Result := Result + [Item];
          end;
        Pending.Enqueue(Required);
      end;
    end;
  finally
    Pending.Free;
    Files.Free;
    Seen.Free;
  end;
end;

function TPackageLocator.FindSource(const APackage: string; out AFileName: string;
  out ASource: TPackageSource): Boolean;
var
  Found: TFound;
begin
  Found := Find(APackage);
  Result := Found.Known and Found.Source.IsPackage;
  AFileName := Found.FileName;
  ASource := Found.Source;
end;

function TPackageLocator.Requires(const APackage: string): TArray<string>;
var
  mFileName: string;
  mSource: TPackageSource;
  mEntry: TPackageEntry;
begin
  Result := nil;
  if FindSource(APackage, mFileName, mSource) then
    for mEntry in mSource.Requires do
      Result := Result + [mEntry.Name];
end;

end.
