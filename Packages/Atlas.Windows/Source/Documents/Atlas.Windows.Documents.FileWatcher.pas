unit Atlas.Windows.Documents.FileWatcher;

// Beobachtet einzelne Dateien selbst (#227): Die RAD-Studio-IDE schickt kein
// workspace/didChangeWatchedFiles für atlas.json und die globale
// Benutzerdatei. Ein Hintergrund-Thread wartet über
// FindFirstChangeNotification auf Änderungen in den Ordnern der Dateien und
// sieht spätestens alle PollMs nach (Ordner, die es noch nicht gibt, mehr als
// 63 Ordner). Welche Dateien sich geändert haben, entscheidet
// TFileChangeTracker über Änderungszeit und Größe; OnChanged läuft im
// Beobachter-Thread.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Documents.ChangeTracker;

type
  TFileWatcherChanged = reference to procedure(const AFiles: TArray<string>);

  TFileWatcher = class
  public const
    PollMs = 2000;
    /// <summary>Wartezeit nach einer Meldung, bis der Schreibvorgang fertig ist.</summary>
    SettleMs = 100;
  private
    FTracker: TFileChangeTracker;
    FStop: THandle;
    FReconfigure: THandle;
    FThread: TThread;
  public
    constructor Create(const AOnChanged: TFileWatcherChanged);
    destructor Destroy; override;
    /// <summary>Beobachtet genau AFiles; threadsicher.</summary>
    procedure SetFiles(const AFiles: TArray<string>);
    /// <summary>Änderungszeit und Größe als Stempel; '' ohne Datei.</summary>
    class function Stamp(const AFileName: string): string; static;
  end;

implementation

uses
  Winapi.Windows;

type
  /// <summary>Beobachter-Thread: Änderungsmeldungen der Ordner des Trackers, Abgleich spätestens alle PollMs.
  /// </summary>
  TWatchThread = class(TThread)
  private
    FTracker: TFileChangeTracker;
    FStop: THandle;
    FReconfigure: THandle;
    FOnChanged: TFileWatcherChanged;
    /// <summary>[0] Stop, [1] neue Dateiliste, dahinter je Ordner eine Änderungsmeldung.</summary>
    function OpenHandles: TArray<THandle>;
    procedure CloseHandles(const AHandles: TArray<THandle>);
    /// <summary>Wartet, bis der Schreibvorgang fertig ist, und meldet ANotify wieder an; False, wenn dabei Stop
    /// kam.</summary>
    function Settle(ANotify: THandle): Boolean;
    procedure PollChanges;
    /// <summary>Beobachtet bis zur neuen Dateiliste (True) oder bis Stop bzw. Terminate (False).</summary>
    function Watch(const AHandles: TArray<THandle>): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(ATracker: TFileChangeTracker; AStop, AReconfigure: THandle;
      const AOnChanged: TFileWatcherChanged);
  end;

{ TFileWatcher }

class function TFileWatcher.Stamp(const AFileName: string): string;
var
  Data: TWin32FileAttributeData;
begin
  if not GetFileAttributesEx(PChar(AFileName), GetFileExInfoStandard, @Data) then
  begin
    Exit('');
  end;
  if (Data.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
  begin
    Exit('');
  end;
  Result := Format('%u.%u.%u.%u', [Data.ftLastWriteTime.dwHighDateTime, Data.ftLastWriteTime.dwLowDateTime,
    Data.nFileSizeHigh, Data.nFileSizeLow]);
end;

// Meldung eines Ordners (nicht Stop, nicht neue Dateiliste, kein Zeitablauf)?
function IsDirectoryNotice(AWait: Cardinal; ACount: Integer): Boolean;
begin
  Result := (AWait > WAIT_OBJECT_0 + 1) and (AWait < WAIT_OBJECT_0 + Cardinal(ACount));
end;

{ TWatchThread }

constructor TWatchThread.Create(ATracker: TFileChangeTracker; AStop, AReconfigure: THandle;
  const AOnChanged: TFileWatcherChanged);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FTracker := ATracker;
  FStop := AStop;
  FReconfigure := AReconfigure;
  FOnChanged := AOnChanged;
end;

function TWatchThread.OpenHandles: TArray<THandle>;
var
  mDir: string;
  mNotify: THandle;
begin
  Result := TArray<THandle>.Create(FStop, FReconfigure);
  for mDir in FTracker.Directories do
  begin
    if Length(Result) >= MAXIMUM_WAIT_OBJECTS then
    begin
      Break;
    end;
    mNotify := FindFirstChangeNotification(PChar(mDir), False, FILE_NOTIFY_CHANGE_FILE_NAME or
      FILE_NOTIFY_CHANGE_LAST_WRITE or FILE_NOTIFY_CHANGE_SIZE);
    if mNotify <> INVALID_HANDLE_VALUE then
    begin
      Result := Result + [mNotify];
    end;
  end;
end;

procedure TWatchThread.CloseHandles(const AHandles: TArray<THandle>);
var
  mIndex: Integer;
begin
  for mIndex := 2 to High(AHandles) do
  begin
    FindCloseChangeNotification(AHandles[mIndex]);
  end;
end;

function TWatchThread.Settle(ANotify: THandle): Boolean;
begin
  // Mehrere Meldungen eines Speichervorgangs zusammenfassen.
  Result := WaitForSingleObject(FStop, TFileWatcher.SettleMs) <> WAIT_OBJECT_0;
  if Result then
  begin
    FindNextChangeNotification(ANotify);
  end;
end;

procedure TWatchThread.PollChanges;
var
  mChanged: TArray<string>;
begin
  mChanged := FTracker.Poll;
  if Length(mChanged) > 0 then
  begin
    FOnChanged(mChanged);
  end;
end;

function TWatchThread.Watch(const AHandles: TArray<THandle>): Boolean;
var
  mWait: Cardinal;
begin
  repeat
    mWait := WaitForMultipleObjects(Length(AHandles), @AHandles[0], False, TFileWatcher.PollMs);
    if mWait = WAIT_OBJECT_0 then
    begin
      Exit(False);
    end;
    if mWait = WAIT_OBJECT_0 + 1 then
    begin
      Exit(True);
    end;
    if IsDirectoryNotice(mWait, Length(AHandles)) and not Settle(AHandles[mWait - WAIT_OBJECT_0]) then
    begin
      Exit(False);
    end;
    PollChanges;
  until Terminated;
  Result := False;
end;

procedure TWatchThread.Execute;
var
  mHandles: TArray<THandle>;
  mGoOn: Boolean;
begin
  repeat
    mHandles := OpenHandles;
    try
      mGoOn := Watch(mHandles);
    finally
      CloseHandles(mHandles);
    end;
  until Terminated or not mGoOn;
end;

{ TFileWatcher }

constructor TFileWatcher.Create(const AOnChanged: TFileWatcherChanged);
begin
  inherited Create;
  FTracker := TFileChangeTracker.Create(
    function(const AFileName: string): string
    begin
      Result := TFileWatcher.Stamp(AFileName);
    end);
  FStop := CreateEvent(nil, True, False, nil);
  FReconfigure := CreateEvent(nil, False, False, nil);
  FThread := TWatchThread.Create(FTracker, FStop, FReconfigure, AOnChanged);
  FThread.Start;
end;

destructor TFileWatcher.Destroy;
begin
  if FThread <> nil then
  begin
    FThread.Terminate;
    SetEvent(FStop);
    FThread.WaitFor;
    FThread.Free;
  end;
  if FReconfigure <> 0 then
  begin
    CloseHandle(FReconfigure);
  end;
  if FStop <> 0 then
  begin
    CloseHandle(FStop);
  end;
  FTracker.Free;
  inherited;
end;

procedure TFileWatcher.SetFiles(const AFiles: TArray<string>);
begin
  FTracker.SetFiles(AFiles);
  SetEvent(FReconfigure);
end;

end.
