unit Atlas.Linux.Documents.FileWatcher;

// Platform-Feature "Documents" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Documents.FileWatcher (#227). Ein Hintergrund-Thread wartet
// über inotify auf Änderungen in den Ordnern der Dateien und sieht spätestens
// alle cPollMs nach (Ordner, die es noch nicht gibt). Welche Dateien sich
// geändert haben, entscheidet wie unter Windows TFileChangeTracker über
// Änderungszeit und Größe; OnChanged läuft im Beobachter-Thread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Common.Documents.ChangeTracker;

type
  TFileWatcherChanged = reference to procedure(const AFiles: TArray<string>);

  TFileWatcher = class
  public const
    cPollMs = 2000;
    cSettleMs = 100;
    /// <summary>So oft sieht der Thread nach Stop und neuer Dateiliste.</summary>
    cSliceMs = 100;
  private
    FTracker: TFileChangeTracker;
    FStop: TEvent;
    FReconfigure: TEvent;
    FThread: TThread;
  public
    constructor Create(const AOnChanged: TFileWatcherChanged);
    destructor Destroy; override;
    /// <summary>Ersetzt die beobachteten Dateien.</summary>
    procedure SetFiles(const AFiles: TArray<string>);
    /// <summary>Änderungszeit und Größe als Text; '' für fehlende Dateien und Ordner.</summary>
    class function Stamp(const AFileName: string): string; static;
  end;

implementation

uses
  BaseUnix,
  Linux;

type
  /// <summary>Beobachter-Thread: inotify auf die Ordner des Trackers, Abgleich spätestens alle cPollMs.</summary>
  TWatchThread = class(TThread)
  private
    FTracker: TFileChangeTracker;
    FStop: TEvent;
    FReconfigure: TEvent;
    FOnChanged: TFileWatcherChanged;
    /// <summary>Seit dem letzten Abgleich gewartete Zeit.</summary>
    FWaited: Integer;
    function OpenInotify: cint;
    /// <summary>Wartet eine Scheibe von cSliceMs auf Meldungen; False, wenn dabei Stop kam.</summary>
    function WaitSlice(AInotify: cint): Boolean;
    procedure PollIfDue;
    /// <summary>Beobachtet bis zur neuen Dateiliste (True) oder bis Stop bzw. Terminate (False).</summary>
    function Watch(AInotify: cint): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(ATracker: TFileChangeTracker; AStop, AReconfigure: TEvent;
      const AOnChanged: TFileWatcherChanged);
  end;

{ TFileWatcher }

class function TFileWatcher.Stamp(const AFileName: string): string;
var
  mInfo: Stat;
begin
  if FpStat(RawByteString(UTF8String(AFileName)), mInfo) <> 0 then
  begin
    Exit('');
  end;
  if FpS_ISDIR(mInfo.st_mode) then
  begin
    Exit('');
  end;
  Result := Format('%d.%d.%d', [Int64(mInfo.st_mtime), Int64(mInfo.st_mtime_nsec), Int64(mInfo.st_size)]);
end;

/// <summary>Wartet bis zu ATimeoutMs auf Ereignisse von inotify und liest sie ab; True, wenn welche kamen.</summary>
function WaitForEvents(AInotify: cint; ATimeoutMs: Integer): Boolean;
var
  mPoll: pollfd;
  mBuffer: array[0..4095] of Byte;
begin
  Result := False;
  if AInotify < 0 then
  begin
    Sleep(ATimeoutMs);
    Exit;
  end;
  mPoll.fd := AInotify;
  mPoll.events := POLLIN;
  mPoll.revents := 0;
  if FpPoll(@mPoll, 1, ATimeoutMs) <= 0 then
  begin
    Exit;
  end;
  while FpRead(AInotify, mBuffer, SizeOf(mBuffer)) > 0 do
  begin
    Result := True;
  end;
end;

{ TWatchThread }

constructor TWatchThread.Create(ATracker: TFileChangeTracker; AStop, AReconfigure: TEvent;
  const AOnChanged: TFileWatcherChanged);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FTracker := ATracker;
  FStop := AStop;
  FReconfigure := AReconfigure;
  FOnChanged := AOnChanged;
end;

function TWatchThread.OpenInotify: cint;
var
  mDir: string;
begin
  Result := inotify_init1(IN_NONBLOCK or IN_CLOEXEC);
  if Result < 0 then
  begin
    Exit;
  end;
  for mDir in FTracker.Directories do
  begin
    inotify_add_watch(Result, PAnsiChar(UTF8String(mDir)),
      IN_MODIFY or IN_CLOSE_WRITE or IN_MOVED_TO or IN_MOVED_FROM or IN_CREATE or IN_DELETE);
  end;
end;

function TWatchThread.WaitSlice(AInotify: cint): Boolean;
begin
  Result := True;
  if not WaitForEvents(AInotify, TFileWatcher.cSliceMs) then
  begin
    Inc(FWaited, TFileWatcher.cSliceMs);
    Exit;
  end;
  // Mehrere Meldungen eines Speichervorgangs zusammenfassen.
  if FStop.WaitFor(TFileWatcher.cSettleMs) = wrSignaled then
  begin
    Exit(False);
  end;
  WaitForEvents(AInotify, 0);
  FWaited := TFileWatcher.cPollMs;
end;

procedure TWatchThread.PollIfDue;
var
  mChanged: TArray<string>;
begin
  if FWaited < TFileWatcher.cPollMs then
  begin
    Exit;
  end;
  FWaited := 0;
  mChanged := FTracker.Poll;
  if Length(mChanged) > 0 then
  begin
    FOnChanged(mChanged);
  end;
end;

function TWatchThread.Watch(AInotify: cint): Boolean;
begin
  FWaited := 0;
  repeat
    if FStop.WaitFor(0) = wrSignaled then
    begin
      Exit(False);
    end;
    if FReconfigure.WaitFor(0) = wrSignaled then
    begin
      Exit(True);
    end;
    if not WaitSlice(AInotify) then
    begin
      Exit(False);
    end;
    PollIfDue;
  until Terminated;
  Result := False;
end;

procedure TWatchThread.Execute;
var
  mInotify: cint;
  mGoOn: Boolean;
begin
  repeat
    mInotify := OpenInotify;
    try
      mGoOn := Watch(mInotify);
    finally
      if mInotify >= 0 then
      begin
        FpClose(mInotify);
      end;
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
  FStop := TEvent.Create(nil, True, False, '');
  FReconfigure := TEvent.Create(nil, False, False, '');
  FThread := TWatchThread.Create(FTracker, FStop, FReconfigure, AOnChanged);
  FThread.Start;
end;

destructor TFileWatcher.Destroy;
begin
  if FThread <> nil then
  begin
    FThread.Terminate;
    FStop.SetEvent;
    FThread.WaitFor;
    FThread.Free;
  end;
  FReconfigure.Free;
  FStop.Free;
  FTracker.Free;
  inherited;
end;

procedure TFileWatcher.SetFiles(const AFiles: TArray<string>);
begin
  FTracker.SetFiles(AFiles);
  FReconfigure.SetEvent;
end;

end.
