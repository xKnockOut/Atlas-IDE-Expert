unit Atlas.Core.Files.Adapters.FolderWatcher;

// Beobachtet Ordner samt Unterordnern mit ReadDirectoryChangesW (#395) und
// gibt jedes Ereignis an TAtlasWatchedChanges weiter. Je Wurzel ein Thread;
// gelesen wird überlappend, damit Stop den Thread sofort beenden kann.
// Läuft der Puffer über (sehr viele Änderungen auf einmal), gehen die
// Ereignisse dieses Durchgangs verloren; der Server liest die Dateien dann
// spätestens beim nächsten Öffnen oder Indexlauf.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Winapi.Windows,
  Atlas.Core.Files.WatchedChanges;

type
  TAtlasFolderWatcher = class
  private type
    TWatchThread = class(TThread)
    private
      FRoot: string;
      FChanges: TAtlasWatchedChanges;
      FStopEvent: THandle;
      procedure Report(ABuffer: PByte);
    protected
      procedure Execute; override;
    public
      constructor Create(const ARoot: string; AChanges: TAtlasWatchedChanges);
      destructor Destroy; override;
      /// <summary>Beendet den Thread und wartet auf ihn.</summary>
      procedure Stop;
      property Root: string read FRoot;
    end;
  private
    FChanges: TAtlasWatchedChanges;
    FThreads: TObjectList<TWatchThread>;
  public
    /// <summary>AChanges gehört weiter dem Aufrufer und muss den Beobachter überleben.</summary>
    constructor Create(AChanges: TAtlasWatchedChanges);
    destructor Destroy; override;
    /// <summary>Beobachtet genau diese Ordner; neue starten, weggefallene enden.</summary>
    procedure SetRoots(const ARoots: TArray<string>);
    function Roots: TArray<string>;
  end;

implementation

const
  BufferBytes = 65536;
  NotifyFilter = FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_LAST_WRITE or FILE_NOTIFY_CHANGE_SIZE;

{ TAtlasFolderWatcher.TWatchThread }

constructor TAtlasFolderWatcher.TWatchThread.Create(const ARoot: string; AChanges: TAtlasWatchedChanges);
begin
  FRoot := ExcludeTrailingPathDelimiter(ARoot);
  FChanges := AChanges;
  FStopEvent := CreateEvent(nil, True, False, nil);
  inherited Create(False);
end;

destructor TAtlasFolderWatcher.TWatchThread.Destroy;
begin
  Stop;
  inherited;
  CloseHandle(FStopEvent);
end;

procedure TAtlasFolderWatcher.TWatchThread.Stop;
begin
  if Finished then
    Exit;
  Terminate;
  SetEvent(FStopEvent);
  WaitFor;
end;

procedure TAtlasFolderWatcher.TWatchThread.Report(ABuffer: PByte);
var
  Entry: PFileNotifyInformation;
  Name: string;
  Stamp: Cardinal;
begin
  Stamp := GetTickCount;
  Entry := PFileNotifyInformation(ABuffer);
  while True do
  begin
    SetString(Name, PWideChar(@Entry^.FileName[0]), Entry^.FileNameLength div SizeOf(WideChar));
    FChanges.Add(FRoot + PathDelim + Name, Entry^.Action, Stamp);
    if Entry^.NextEntryOffset = 0 then
      Break;
    Entry := PFileNotifyInformation(PByte(Entry) + Entry^.NextEntryOffset);
  end;
end;

procedure TAtlasFolderWatcher.TWatchThread.Execute;
var
  Directory: THandle;
  Overlapped: TOverlapped;
  Buffer: TBytes;
  Handles: array[0..1] of THandle;
  Bytes: DWORD;
begin
  NameThreadForDebugging('Atlas.FolderWatcher');
  Directory := CreateFile(PChar(FRoot), FILE_LIST_DIRECTORY,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED, 0);
  if Directory = INVALID_HANDLE_VALUE then
    Exit;
  try
    SetLength(Buffer, BufferBytes);
    FillChar(Overlapped, SizeOf(Overlapped), 0);
    Overlapped.hEvent := CreateEvent(nil, True, False, nil);
    try
      Handles[0] := Overlapped.hEvent;
      Handles[1] := FStopEvent;
      while not Terminated do
      begin
        ResetEvent(Overlapped.hEvent);
        if not ReadDirectoryChangesW(Directory, @Buffer[0], BufferBytes, True, NotifyFilter, nil,
          @Overlapped, nil) then
          Break;
        if WaitForMultipleObjects(2, @Handles[0], False, INFINITE) <> WAIT_OBJECT_0 then
        begin
          // Stop: laufendes Lesen abbrechen und dessen Ende abwarten, bevor der Puffer frei wird.
          CancelIo(Directory);
          GetOverlappedResult(Directory, Overlapped, Bytes, True);
          Break;
        end;
        if GetOverlappedResult(Directory, Overlapped, Bytes, False) and (Bytes > 0) then
          Report(@Buffer[0]);
      end;
    finally
      CloseHandle(Overlapped.hEvent);
    end;
  finally
    CloseHandle(Directory);
  end;
end;

{ TAtlasFolderWatcher }

constructor TAtlasFolderWatcher.Create(AChanges: TAtlasWatchedChanges);
begin
  inherited Create;
  FChanges := AChanges;
  FThreads := TObjectList<TWatchThread>.Create(True);
end;

destructor TAtlasFolderWatcher.Destroy;
begin
  // Freigeben hält jeden Thread an (Stop im Destruktor).
  FThreads.Free;
  inherited;
end;

function TAtlasFolderWatcher.Roots: TArray<string>;
var
  Thread: TWatchThread;
begin
  Result := nil;
  for Thread in FThreads do
    Result := Result + [Thread.Root];
end;

procedure TAtlasFolderWatcher.SetRoots(const ARoots: TArray<string>);
var
  Index: Integer;
  Root: string;
  Known: Boolean;

  function Wanted(const APath: string): Boolean;
  var
    Candidate: string;
  begin
    for Candidate in ARoots do
      if SameText(ExcludeTrailingPathDelimiter(Candidate), APath) then
        Exit(True);
    Result := False;
  end;

begin
  for Index := FThreads.Count - 1 downto 0 do
    if not Wanted(FThreads[Index].Root) then
      FThreads.Delete(Index);
  for Root in ARoots do
  begin
    Known := False;
    for Index := 0 to FThreads.Count - 1 do
      if SameText(FThreads[Index].Root, ExcludeTrailingPathDelimiter(Root)) then
      begin
        Known := True;
        Break;
      end;
    if not Known and DirectoryExists(Root) then
      FThreads.Add(TWatchThread.Create(Root, FChanges));
  end;
end;

end.
