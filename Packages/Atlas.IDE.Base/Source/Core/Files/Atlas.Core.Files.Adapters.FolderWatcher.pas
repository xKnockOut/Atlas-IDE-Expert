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
  TAtlasFolderWatcher = class(TInterfacedObject, IAtlasFolderWatcher)
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

type
  // FILE_NOTIFY_INFORMATION; Winapi.Windows deklariert den Satz nicht.
  PFileNotifyInformation = ^TFileNotifyInformation;
  TFileNotifyInformation = record
    NextEntryOffset: DWORD;
    Action: DWORD;
    FileNameLength: DWORD;
    FileName: array[0..0] of WideChar;
  end;

const
  cBufferBytes = 65536;
  cNotifyFilter = FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_LAST_WRITE or FILE_NOTIFY_CHANGE_SIZE;

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
  begin
    Exit;
  end;
  Terminate;
  SetEvent(FStopEvent);
  WaitFor;
end;

procedure TAtlasFolderWatcher.TWatchThread.Report(ABuffer: PByte);
var
  mEntry: PFileNotifyInformation;
  mName: string;
  mStamp: Cardinal;
begin
  mStamp := GetTickCount;
  mEntry := PFileNotifyInformation(ABuffer);
  while True do
  begin
    SetString(mName, PWideChar(@mEntry^.FileName[0]), mEntry^.FileNameLength div SizeOf(WideChar));
    FChanges.Add(FRoot + PathDelim + mName, mEntry^.Action, mStamp);
    if mEntry^.NextEntryOffset = 0 then
    begin
      Break;
    end;
    mEntry := PFileNotifyInformation(PByte(mEntry) + mEntry^.NextEntryOffset);
  end;
end;

procedure TAtlasFolderWatcher.TWatchThread.Execute;
var
  mDirectory: THandle;
  mOverlapped: TOverlapped;
  mBuffer: TBytes;
  mHandles: array[0..1] of THandle;
  mBytes: DWORD;
begin
  NameThreadForDebugging('Atlas.FolderWatcher');
  mDirectory := CreateFile(PChar(FRoot), FILE_LIST_DIRECTORY,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED, 0);
  if mDirectory = INVALID_HANDLE_VALUE then
  begin
    Exit;
  end;
  try
    SetLength(mBuffer, cBufferBytes);
    FillChar(mOverlapped, SizeOf(mOverlapped), 0);
    mOverlapped.hEvent := CreateEvent(nil, True, False, nil);
    try
      mHandles[0] := mOverlapped.hEvent;
      mHandles[1] := FStopEvent;
      while not Terminated do
      begin
        ResetEvent(mOverlapped.hEvent);
        if not ReadDirectoryChangesW(mDirectory, @mBuffer[0], cBufferBytes, True, cNotifyFilter, nil,
          @mOverlapped, nil) then
        begin
          Break;
        end;
        if WaitForMultipleObjects(2, @mHandles[0], False, INFINITE) <> WAIT_OBJECT_0 then
        begin
          // Stop: laufendes Lesen abbrechen und dessen Ende abwarten, bevor der Puffer frei wird.
          CancelIo(mDirectory);
          GetOverlappedResult(mDirectory, mOverlapped, mBytes, True);
          Break;
        end;
        if GetOverlappedResult(mDirectory, mOverlapped, mBytes, False) and (mBytes > 0) then
        begin
          Report(@mBuffer[0]);
        end;
      end;
    finally
      CloseHandle(mOverlapped.hEvent);
    end;
  finally
    CloseHandle(mDirectory);
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
  mThread: TWatchThread;
begin
  Result := nil;
  for mThread in FThreads do
  begin
    Result := Result + [mThread.Root];
  end;
end;

procedure TAtlasFolderWatcher.SetRoots(const ARoots: TArray<string>);
var
  mIndex: Integer;
  mRoot: string;
  mKnown: Boolean;

  function Wanted(const APath: string): Boolean;
  var
    mCandidate: string;
  begin
    for mCandidate in ARoots do
    begin
      if SameText(ExcludeTrailingPathDelimiter(mCandidate), APath) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

begin
  for mIndex := FThreads.Count - 1 downto 0 do
  begin
    if not Wanted(FThreads[mIndex].Root) then
    begin
      FThreads.Delete(mIndex);
    end;
  end;
  for mRoot in ARoots do
  begin
    mKnown := False;
    for mIndex := 0 to FThreads.Count - 1 do
    begin
      if SameText(FThreads[mIndex].Root, ExcludeTrailingPathDelimiter(mRoot)) then
      begin
        mKnown := True;
        Break;
      end;
    end;
    if not mKnown and DirectoryExists(mRoot) then
    begin
      FThreads.Add(TWatchThread.Create(mRoot, FChanges));
    end;
  end;
end;

end.
