unit Atlas.Core.Tracker.Adapters.LocalFiles;

// Dateizugriff des Trackers auf der lokalen Platte (#1455 Paket 2d), ohne VCL
// und Open Tools API: IAtlasTrackerFiles über System.IOUtils und TFileStream.
// Jede Methode fängt die Ausnahmen der RTL (gesperrt, keine Rechte, kein
// Platz) und meldet sie als False, leeres Ergebnis bzw. nil. Ersetzt wird
// über TAtlasTextFile.Replace (erst daneben schreiben, dann in einem Schritt
// ersetzen). Erzeugt nur Atlas.IDE.Tracker.Composition (und die Tests).

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract.Files;

type
  TAtlasTrackerLocalFiles = class(TInterfacedObject, IAtlasTrackerFiles)
  public const
    /// <summary>So lange wartet Lock zwischen zwei Versuchen.</summary>
    cLockStepMs = 25;
  public
    function FileExists(const AFileName: string): Boolean;
    function FolderExists(const AFolder: string): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function ReadHead(const AFileName: string; AMaxBytes: Integer; out AData: TBytes): Boolean;
    function ReadTail(const AFileName: string; AMaxBytes: Integer; out AData: TBytes; out ACut: Boolean): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
    function ReplaceText(const AFileName, AText: string): Boolean;
    function WriteBytes(const AFileName: string; const AData: TBytes): Boolean;
    function DeleteFile(const AFileName: string): Boolean;
    function DeleteFolder(const AFolder: string): Boolean;
    function RemoveEmptyFolder(const AFolder: string): Boolean;
    function ForceFolder(const AFolder: string): Boolean;
    function Files(const AFolder, AMask: string): TArray<string>;
    function Folders(const AFolder: string): TArray<string>;
    function WriteTime(const APath: string): TDateTime;
    function Lock(const AFileName: string; AWaitMs: Integer): IInterface;
    function Environment(const AName: string): string;
    function TempFolder: string;
  end;

implementation

uses
  System.Types,
  System.Classes,
  System.IOUtils,
  Atlas.Core.Files.TextFile;

type
  /// <summary>Hält die Sperrdatei offen, bis der letzte Verweis fällt.</summary>
  TAtlasTrackerFileLock = class(TInterfacedObject)
  private
    FStream: TStream;
  public
    constructor Create(AStream: TStream);
    destructor Destroy; override;
  end;

constructor TAtlasTrackerFileLock.Create(AStream: TStream);
begin
  inherited Create;
  FStream := AStream;
end;

destructor TAtlasTrackerFileLock.Destroy;
begin
  FStream.Free;
  inherited;
end;

/// <summary>Höchstens AMaxBytes vom Anfang bzw. Ende lesen; ein anderes Programm darf die Datei offen halten und
/// hineinschreiben.</summary>
function ReadRange(const AFileName: string; AMaxBytes: Integer; AFromEnd: Boolean; out AData: TBytes;
  out ACut: Boolean): Boolean;
var
  mStream: TFileStream;
  mSize, mStart, mCount: Int64;
begin
  AData := nil;
  ACut := False;
  try
    mStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      mSize := mStream.Size;
      mCount := mSize;
      if (AMaxBytes > 0) and (mSize > AMaxBytes) then
      begin
        mCount := AMaxBytes;
      end;
      mStart := 0;
      if AFromEnd then
      begin
        mStart := mSize - mCount;
      end;
      ACut := mCount < mSize;
      SetLength(AData, mCount);
      mStream.Position := mStart;
      if mCount > 0 then
      begin
        mStream.ReadBuffer(AData[0], mCount);
      end;
    finally
      mStream.Free;
    end;
    Result := True;
  except
    on Exception do
    begin
      AData := nil;
      Result := False;
    end;
  end;
end;

/// <summary>DeleteFile der RTL; in den Methoden verdeckt TAtlasTrackerLocalFiles.DeleteFile den Namen.</summary>
function RemoveFile(const AFileName: string): Boolean;
begin
  Result := DeleteFile(AFileName);
end;

/// <summary>Namen der RTL als TArray&lt;string&gt;, Element für Element (unter FPC ist TStringDynArray ein Feld
/// anderer Zeichenketten).</summary>
function ToArray(const ANames: TStringDynArray): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ANames));
  for mIndex := 0 to High(ANames) do
  begin
    Result[mIndex] := ANames[mIndex];
  end;
end;

{ TAtlasTrackerLocalFiles }

function TAtlasTrackerLocalFiles.FileExists(const AFileName: string): Boolean;
begin
  Result := (AFileName <> '') and TFile.Exists(AFileName);
end;

function TAtlasTrackerLocalFiles.FolderExists(const AFolder: string): Boolean;
begin
  Result := (AFolder <> '') and TDirectory.Exists(AFolder);
end;

function TAtlasTrackerLocalFiles.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
  if not FileExists(AFileName) then
  begin
    Exit;
  end;
  try
    AText := TFile.ReadAllText(AFileName, TEncoding.UTF8);
    Result := True;
  except
    on Exception do
    begin
      AText := '';
    end;
  end;
end;

function TAtlasTrackerLocalFiles.ReadHead(const AFileName: string; AMaxBytes: Integer; out AData: TBytes): Boolean;
var
  mCut: Boolean;
begin
  Result := ReadRange(AFileName, AMaxBytes, False, AData, mCut);
end;

function TAtlasTrackerLocalFiles.ReadTail(const AFileName: string; AMaxBytes: Integer; out AData: TBytes;
  out ACut: Boolean): Boolean;
begin
  Result := ReadRange(AFileName, AMaxBytes, True, AData, ACut);
end;

function TAtlasTrackerLocalFiles.WriteText(const AFileName, AText: string): Boolean;
begin
  // BOM ausdrücklich: Die Dateien sehen auf jeder Plattform gleich aus wie bisher mit TFile.WriteAllText.
  Result := WriteBytes(AFileName, TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(AText));
end;

function TAtlasTrackerLocalFiles.ReplaceText(const AFileName, AText: string): Boolean;
begin
  Result := False;
  if (AFileName = '') or not ForceFolder(ExtractFileDir(AFileName)) then
  begin
    Exit;
  end;
  try
    TAtlasTextFile.Replace(AFileName, TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(AText));
    Result := True;
  except
    on Exception do
    begin
      Result := False;
    end;
  end;
end;

function TAtlasTrackerLocalFiles.WriteBytes(const AFileName: string; const AData: TBytes): Boolean;
begin
  Result := False;
  if (AFileName = '') or not ForceFolder(ExtractFileDir(AFileName)) then
  begin
    Exit;
  end;
  try
    TFile.WriteAllBytes(AFileName, AData);
    Result := True;
  except
    on Exception do
    begin
      Result := False;
    end;
  end;
end;

function TAtlasTrackerLocalFiles.DeleteFile(const AFileName: string): Boolean;
begin
  Result := not FileExists(AFileName) or RemoveFile(AFileName);
end;

function TAtlasTrackerLocalFiles.DeleteFolder(const AFolder: string): Boolean;
begin
  Result := not FolderExists(AFolder);
  if Result then
  begin
    Exit;
  end;
  try
    TDirectory.Delete(AFolder, True);
  except
    // Eine Datei ist noch offen (z. B. im Bildbetrachter): Der Ordner bleibt.
    on Exception do
    begin
      Exit(False);
    end;
  end;
  Result := not FolderExists(AFolder);
end;

function TAtlasTrackerLocalFiles.RemoveEmptyFolder(const AFolder: string): Boolean;
begin
  Result := FolderExists(AFolder) and RemoveDir(AFolder);
end;

function TAtlasTrackerLocalFiles.ForceFolder(const AFolder: string): Boolean;
begin
  Result := (AFolder <> '') and (FolderExists(AFolder) or ForceDirectories(AFolder));
end;

function TAtlasTrackerLocalFiles.Files(const AFolder, AMask: string): TArray<string>;
begin
  Result := nil;
  if not FolderExists(AFolder) then
  begin
    Exit;
  end;
  try
    Result := ToArray(TDirectory.GetFiles(AFolder, AMask));
  except
    on Exception do
    begin
      Result := nil;
    end;
  end;
end;

function TAtlasTrackerLocalFiles.Folders(const AFolder: string): TArray<string>;
begin
  Result := nil;
  if not FolderExists(AFolder) then
  begin
    Exit;
  end;
  try
    Result := ToArray(TDirectory.GetDirectories(AFolder));
  except
    on Exception do
    begin
      Result := nil;
    end;
  end;
end;

function TAtlasTrackerLocalFiles.WriteTime(const APath: string): TDateTime;
begin
  Result := 0;
  try
    if FileExists(APath) then
    begin
      Result := TFile.GetLastWriteTime(APath);
    end
    else if FolderExists(APath) then
    begin
      Result := TDirectory.GetLastWriteTime(APath);
    end;
  except
    on Exception do
    begin
      Result := 0;
    end;
  end;
end;

function TAtlasTrackerLocalFiles.Lock(const AFileName: string; AWaitMs: Integer): IInterface;
var
  mWaited: Integer;
begin
  Result := nil;
  if (AFileName = '') or not ForceFolder(ExtractFileDir(AFileName)) then
  begin
    Exit;
  end;
  mWaited := 0;
  repeat
    try
      Result := TAtlasTrackerFileLock.Create(TFileStream.Create(AFileName, fmCreate or fmShareExclusive));
    except
      // Ein anderer Prozess hält die Sperre: kurz warten und neu versuchen.
      on Exception do
      begin
        Result := nil;
      end;
    end;
    if (Result <> nil) or (mWaited >= AWaitMs) then
    begin
      Break;
    end;
    Sleep(cLockStepMs);
    Inc(mWaited, cLockStepMs);
  until False;
end;

function TAtlasTrackerLocalFiles.Environment(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
end;

function TAtlasTrackerLocalFiles.TempFolder: string;
begin
  Result := TPath.GetTempPath;
end;

end.
