unit Atlas.Common.Projects.PackageLocator;

// Findet ein Package aus requires und beantwortet, ob es eine Unit liefert
// (#46). Zuerst die Quelle <Name>.dpk in den bekannten Ordnern (Projekte der
// Gruppe, Suchpfade): Ihr contains ist die Antwort. Sonst das übersetzte
// <Name>.dcp in den Bibliothekspfaden: Es enthält die Namen seiner Units als
// Zeichenketten, die Suche danach ist eine Näherung ohne das DCP-Format.
// Ergebnisse bleiben je Package im Speicher; der Zugriff ist threadsicher. Die Bytes der .dcp hält
// TPackageCompiledFiles einmal je Prozess für alle Locatoren.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.PackageReader;

type
  /// <summary>Liest eine Datei; False, wenn sie fehlt oder nicht lesbar ist.</summary>
  TPackageReadFile = reference to function(const AFileName: string; out AData: TBytes): Boolean;

  /// <summary>Inhalt der übersetzten Packages (.dcp) einmal je Prozess. Jeder Arbeitsbereich hat seinen
  /// TPackageLocator, und bei jedem Indexstart entsteht ein neuer; mit eigenen Kopien lag jede .dcp (bei
  /// Fremdkomponenten oft zweistellige MB) je Projekt und je Neuladen im Speicher, beim Kunden über 2 GB.
  /// Ein Eintrag gilt, solange Zeitstempel und Größe der Datei gleich sind.</summary>
  TPackageCompiledFiles = record
  private type
    TEntry = record
      Stamp: TDateTime;
      Size: Int64;
      Data: TBytes;
    end;
  private class var
    FLock: TObject;
    FFiles: TDictionary<string, TEntry>;
  public
    /// <summary>Inhalt von AFileName, geteilt; False, wenn die Datei fehlt oder nicht lesbar ist.</summary>
    class function Read(const AFileName: string; out AData: TBytes): Boolean; static;
    /// <summary>Summe der gehaltenen Inhalte in Byte (Fenster „Atlas-Server“).</summary>
    class function Bytes: Int64; static;
    class procedure Clear; static;
  end;

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
    // Antworten aus .dcp je "PACKAGE|UNIT": Die Suche durchläuft alle Bytes, die Projektprüfung fragt je Unit.
    FCompiledAnswers: TDictionary<string, Boolean>;
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

{ TPackageCompiledFiles }

class function TPackageCompiledFiles.Read(const AFileName: string; out AData: TBytes): Boolean;
var
  mKey: string;
  mEntry: TEntry;
  mStamp: TDateTime;
  mSize: Int64;
begin
  AData := nil;
  if not TFile.Exists(AFileName) then
  begin
    Exit(False);
  end;
  try
    mStamp := TFile.GetLastWriteTime(AFileName);
    mSize := TFile.GetSize(AFileName);
  except
    // lsp-ignore: catch-all-without-raise -- Cache nach Kräften; Fehler heißt nicht gefunden
    on Exception do
      Exit(False);
  end;
  mKey := AnsiUpperCase(ExpandFileName(AFileName));
  TMonitor.Enter(FLock);
  try
    if FFiles.TryGetValue(mKey, mEntry) and (mEntry.Stamp = mStamp) and (mEntry.Size = mSize) then
    begin
      AData := mEntry.Data;
      Exit(True);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  // Außerhalb der Sperre lesen; liest ein zweiter Thread dieselbe Datei gleichzeitig, gewinnt der letzte.
  try
    AData := TFile.ReadAllBytes(AFileName);
  except
    // Gesperrte oder nicht lesbare Dateien zählen als fehlend.
    // lsp-ignore: catch-all-without-raise -- Cache nach Kräften; Fehler heißt nicht gefunden
    on Exception do
      Exit(False);
  end;
  mEntry.Stamp := mStamp;
  mEntry.Size := mSize;
  mEntry.Data := AData;
  TMonitor.Enter(FLock);
  try
    FFiles.AddOrSetValue(mKey, mEntry);
  finally
    TMonitor.Exit(FLock);
  end;
  Result := True;
end;

class function TPackageCompiledFiles.Bytes: Int64;
var
  mEntry: TEntry;
begin
  Result := 0;
  TMonitor.Enter(FLock);
  try
    for mEntry in FFiles.Values do
    begin
      Inc(Result, Length(mEntry.Data));
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TPackageCompiledFiles.Clear;
begin
  TMonitor.Enter(FLock);
  try
    // Neu anlegen statt Clear: Clear behält die Bucket-Tabelle (Speicher bleibt belegt).
    FFiles.Free;
    FFiles := TDictionary<string, TEntry>.Create;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function DiskReadFile: TPackageReadFile;
begin
  Result :=
    function(const AFileName: string; out AData: TBytes): Boolean
    begin
      // Übersetzte Packages geteilt über alle Locatoren (Speicher, Rückmeldung 01.11.2026).
      if SameText(ExtractFileExt(AFileName), '.dcp') then
      begin
        Exit(TPackageCompiledFiles.Read(AFileName, AData));
      end;
      AData := nil;
      Result := TFile.Exists(AFileName);
      if Result then
      try
        AData := TFile.ReadAllBytes(AFileName);
      except
        // Gesperrte oder nicht lesbare Dateien zählen als fehlend.
        // lsp-ignore: catch-all-without-raise -- Cache nach Kräften; Fehler heißt nicht gefunden
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
  begin
    Result := AByte - 32;
  end;
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
  FCompiledAnswers := TDictionary<string, Boolean>.Create;
  FLock := TObject.Create;
end;

destructor TPackageLocator.Destroy;
begin
  FLock.Free;
  FCompiledAnswers.Free;
  FCache.Free;
  inherited;
end;

class function TPackageLocator.CompiledContains(const AData: TBytes; const AUnitName: string): Boolean;
var
  mName: TBytes;
  mStart, mOffset: Integer;
  mMatches: Boolean;
begin
  Result := False;
  mName := TEncoding.ASCII.GetBytes(UpperCase(AUnitName));
  if Length(mName) = 0 then
  begin
    Exit;
  end;
  for mStart := 0 to Length(AData) - Length(mName) do
  begin
    if (mStart > 0) and IsNameByte(AData[mStart - 1]) then
    begin
      Continue;
    end;
    mMatches := True;
    for mOffset := 0 to High(mName) do
    begin
      if UpperByte(AData[mStart + mOffset]) <> mName[mOffset] then
      begin
        mMatches := False;
        Break;
      end;
    end;
    if mMatches and ((mStart + Length(mName) >= Length(AData)) or not IsNameByte(AData[mStart + Length(mName)])) then
    begin
      Exit(True);
    end;
  end;
end;

function TPackageLocator.Find(const APackage: string): TFound;
var
  mKey, mFolder, mFileName: string;
  mData: TBytes;
  mFileFormat: TFileFormat;
begin
  mKey := UpperCase(APackage);
  TMonitor.Enter(FLock);
  try
    if FCache.TryGetValue(mKey, Result) then
    begin
      Exit;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := Default(TFound);
  for mFolder in FFolders do
  begin
    mFileName := TPath.Combine(mFolder, APackage + '.dpk');
    if FReadFile(mFileName, mData) then
    begin
      Result.Source := TPackageReader.Read(TFileEncoding.Decode(mData, mFileFormat));
      if Result.Source.IsPackage then
      begin
        Result.Known := True;
        Result.FileName := mFileName;
        Break;
      end;
    end;
  end;
  if not Result.Known then
  begin
    for mFolder in FFolders do
    begin
      mFileName := TPath.Combine(mFolder, APackage + '.dcp');
      if FReadFile(mFileName, mData) then
      begin
        Result.Known := True;
        Result.FileName := mFileName;
        Result.Compiled := mData;
        Break;
      end;
    end;
  end;
  TMonitor.Enter(FLock);
  try
    FCache.AddOrSetValue(mKey, Result);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TPackageLocator.Provides(const APackage, AUnitName: string; out AContains: Boolean): Boolean;
var
  mFound: TFound;
  mKey: string;
begin
  mFound := Find(APackage);
  Result := mFound.Known;
  if mFound.Source.IsPackage then
  begin
    AContains := mFound.Source.ContainsIndex(AUnitName) >= 0;
    Exit;
  end;
  AContains := False;
  if not Result then
  begin
    Exit;
  end;
  // Jede Antwort ist ein Lauf über das ganze .dcp (rtl.dcp hat mehrere MB), die Projektprüfung fragt je Unit:
  // je Paar nur einmal suchen.
  mKey := UpperCase(APackage) + '|' + UpperCase(AUnitName);
  TMonitor.Enter(FLock);
  try
    if FCompiledAnswers.TryGetValue(mKey, AContains) then
    begin
      Exit;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  AContains := CompiledContains(mFound.Compiled, AUnitName);
  TMonitor.Enter(FLock);
  try
    FCompiledAnswers.AddOrSetValue(mKey, AContains);
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TPackageLocator.ContainedFiles(const AFileName: string;
  const ASource: TPackageSource): TArray<string>;
var
  mEntry: TPackageEntry;
  mFolder: string;
begin
  Result := nil;
  mFolder := ExtractFilePath(AFileName);
  for mEntry in ASource.Contains do
  begin
    if mEntry.Path <> '' then
    begin
      Result := Result + [ExpandFileName(TPath.Combine(mFolder, mEntry.Path))];
    end;
  end;
end;

/// <summary>Hängt die Dateien aus AItems an AFiles an, die noch nicht in ASeen stehen (ohne Rücksicht auf
/// Groß-/Kleinschreibung, Reihenfolge bleibt).</summary>
procedure AddNewFiles(const AItems: TArray<string>; ASeen: TDictionary<string, Boolean>; AFiles: TList<string>);
var
  mItem: string;
begin
  for mItem in AItems do
  begin
    if not ASeen.ContainsKey(UpperCase(mItem)) then
    begin
      ASeen.Add(UpperCase(mItem), True);
      AFiles.Add(mItem);
    end;
  end;
end;

function TPackageLocator.RequiredFiles(const ASource: TPackageSource): TArray<string>;
var
  mSeen, mKnown: TDictionary<string, Boolean>;
  mFiles: TList<string>;
  mPending: TQueue<TPackageSource>;
  mCurrent, mRequired: TPackageSource;
  mEntry: TPackageEntry;
  mFileName: string;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  mKnown := TDictionary<string, Boolean>.Create;
  mFiles := TList<string>.Create;
  mPending := TQueue<TPackageSource>.Create;
  try
    mSeen.Add(UpperCase(ASource.Name), True);
    mPending.Enqueue(ASource);
    while mPending.Count > 0 do
    begin
      mCurrent := mPending.Dequeue;
      for mEntry in mCurrent.Requires do
      begin
        // Jedes Package nur einmal, auch wenn es mehrere verlangen.
        if mSeen.ContainsKey(UpperCase(mEntry.Name)) then
        begin
          Continue;
        end;
        mSeen.Add(UpperCase(mEntry.Name), True);
        if FindSource(mEntry.Name, mFileName, mRequired) then
        begin
          AddNewFiles(ContainedFiles(mFileName, mRequired), mKnown, mFiles);
          mPending.Enqueue(mRequired);
        end;
      end;
    end;
    Result := mFiles.ToArray;
  finally
    mPending.Free;
    mFiles.Free;
    mKnown.Free;
    mSeen.Free;
  end;
end;

function TPackageLocator.FindSource(const APackage: string; out AFileName: string;
  out ASource: TPackageSource): Boolean;
var
  mFound: TFound;
begin
  mFound := Find(APackage);
  Result := mFound.Known and mFound.Source.IsPackage;
  AFileName := mFound.FileName;
  ASource := mFound.Source;
end;

function TPackageLocator.Requires(const APackage: string): TArray<string>;
var
  mFileName: string;
  mSource: TPackageSource;
  mEntry: TPackageEntry;
begin
  Result := nil;
  if FindSource(APackage, mFileName, mSource) then
  begin
    for mEntry in mSource.Requires do
    begin
      Result := Result + [mEntry.Name];
    end;
  end;
end;

initialization
  TPackageCompiledFiles.FLock := TObject.Create;
  TPackageCompiledFiles.FFiles := TDictionary<string, TPackageCompiledFiles.TEntry>.Create;

finalization
  FreeAndNil(TPackageCompiledFiles.FFiles);
  FreeAndNil(TPackageCompiledFiles.FLock);

end.
