unit Atlas.Common.Index.Adapters.DiskFileSystem;

// IIndexFileSystem auf der echten Platte. Lesen erkennt die Kodierung wie
// beim Öffnen im Editor; der binäre Index-Cache (#617) geht über ReadBytes und
// WriteBytes. Schreiben (Cache) geht über eine temporäre Datei,
// die die alte in einem Schritt ersetzt (TFile.Replace). So sieht ein Leser
// nie einen halben Cache, auch nicht nach einem Abbruch (#184).
//
// Ein Schreiber je Cache (Bericht N1): Den Projekt-Cache schreibt nur die
// Instanz, die seine Sperre hält (TShellWorkspace.LockCache), den gemeinsamen
// Bibliotheks-Cache nur, wer TryLockWrite erhalten hat. WriteBytes muss darum
// keine Wettläufe zweier Schreiber mehr ausgleichen; scheitert es, meldet es
// den Grund, statt ihn zu verschlucken.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract;

type
  TDiskIndexFileSystem = class(TInterfacedObject, IIndexFileSystem)
  public
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
    function ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
    function WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
    function TryLockWrite(const AFileName: string): IInterface;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding;

type
  /// <summary>Hält die Sperrdatei offen, solange jemand die Schnittstelle hält.</summary>
  TWriteLock = class(TInterfacedObject)
  private
    FStream: TStream;
  public
    constructor Create(AStream: TStream);
    destructor Destroy; override;
  end;

constructor TWriteLock.Create(AStream: TStream);
begin
  inherited Create;
  FStream := AStream;
end;

destructor TWriteLock.Destroy;
begin
  FStream.Free;
  inherited;
end;

/// <summary>Grund ohne Pfad: Klasse, bei Ein-/Ausgabe- und Systemfehlern mit Fehlercode.</summary>
function ErrorReason(E: Exception): string;
begin
  Result := E.ClassName;
  if E is EInOutError then
    Result := Format('%s %d', [Result, EInOutError(E).ErrorCode])
  else if E is EOSError then
    Result := Format('%s %d', [Result, EOSError(E).ErrorCode]);
end;

{ TDiskIndexFileSystem }

function TDiskIndexFileSystem.FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
var
  Age: TDateTime;
begin
  Result := FileAge(AFileName, Age);
  if Result then
    AStamp := Round(Age * MSecsPerDay)
  else
    AStamp := 0;
end;

function TDiskIndexFileSystem.ReadText(const AFileName: string; out AText: string): Boolean;
var
  Format: TFileFormat;
begin
  try
    AText := TFileEncoding.LoadFromFile(AFileName, Format);
    Result := True;
  except
    on EInOutError do
      Result := False;
    on EFOpenError do
      Result := False;
  end;
  if not Result then
    AText := '';
end;

function TDiskIndexFileSystem.ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
begin
  // Ohne Datei keine Ausnahme: Der erste Start hat noch keinen Cache.
  if not FileExists(AFileName) then
  begin
    ABytes := nil;
    Exit(False);
  end;
  try
    // Über TFileEncoding: teilt Löschen, damit ein zweiter Server den Cache währenddessen ersetzen kann
    // (Bericht M5).
    ABytes := TFileEncoding.ReadAllBytes(AFileName);
    Result := True;
  except
    on EInOutError do
      Result := False;
    on EFOpenError do
      Result := False;
  end;
  if not Result then
    ABytes := nil;
end;

function TDiskIndexFileSystem.WriteText(const AFileName, AText: string): Boolean;
var
  Error: string;
begin
  Result := WriteBytes(AFileName, TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(AText), Error);
end;

function TDiskIndexFileSystem.WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
var
  Temp, Backup: string;
  Written: Boolean;
begin
  AError := '';
  // Name je Thread: Auch ein Schreiber ohne Sperre (Tests, Aufräumen) überschreibt keine fremde Zwischendatei.
  Temp := Format('%s.%d.tmp', [AFileName, TThread.CurrentThread.ThreadID]);
  // TFile.Replace braucht eine Sicherungsdatei: Mit '' scheitert es an
  // TPath.GetFullPath('') ("Pfad ist leer"), sobald die Zieldatei existiert.
  Backup := Format('%s.%d.bak', [AFileName, TThread.CurrentThread.ThreadID]);
  Written := False;
  try
    ForceDirectories(ExtractFileDir(AFileName));
    TFile.WriteAllBytes(Temp, ABytes);
    Written := True;
    if FileExists(AFileName) then
      TFile.Replace(Temp, AFileName, Backup)
    else
      RenameFile(Temp, AFileName);
  except
    // Gemeldet, nicht verschluckt: Der Aufrufer schreibt den Grund ins Log.
    on E: Exception do
      AError := ErrorReason(E);
  end;
  // TFile.Replace wertet das Ergebnis von ReplaceFile nicht aus und wirft bei einem Fehler
  // nichts (etwa ein Ziel, das ein fremdes Programm ohne FILE_SHARE_DELETE offen hält).
  // Gelungen ist das Schreiben genau dann, wenn die temporäre Datei an die Stelle des Ziels
  // getreten ist.
  Result := Written and not FileExists(Temp);
  // ReplaceFile kann das alte Ziel schon zur Sicherung umbenannt haben, ohne die neue Datei
  // nachzuschieben (ERROR_UNABLE_TO_MOVE_REPLACEMENT_2). Die temporäre Datei ist vollständig
  // geschrieben, also an ihre Stelle setzen.
  if Written and not Result and not FileExists(AFileName) then
    Result := RenameFile(Temp, AFileName);
  if not Result and (AError = '') then
    AError := 'Ziel nicht ersetzt';
  // Keine Reste, weder bei Erfolg noch bei Fehler (Test FailedReplaceLeavesNoRemains).
  if FileExists(Temp) then
    System.SysUtils.DeleteFile(Temp);
  if FileExists(Backup) then
    System.SysUtils.DeleteFile(Backup);
end;

function TDiskIndexFileSystem.TryLockWrite(const AFileName: string): IInterface;
begin
  // Dieselbe Sperrdatei wie TIndexCacheDirectory.TryLock (LockExtension), die TShellWorkspace.LockCache hält:
  // Aufräumen und Leeren lassen den Cache dann in Ruhe. Der Test DiskWriteLockIsExclusive prüft, dass beide
  // übereinstimmen; ein Adapter importiert den anderen nicht (Rollenmatrix).
  try
    ForceDirectories(ExtractFileDir(AFileName));
    Result := TWriteLock.Create(TFileStream.Create(AFileName + '.lock', fmCreate or fmShareExclusive));
  except
    // Gesperrt: Ein anderer schreibt gerade. Das ist das erwartete Ergebnis, kein Fehler.
    on EStreamError do
      Result := nil;
    on EInOutError do
      Result := nil;
  end;
end;

end.
