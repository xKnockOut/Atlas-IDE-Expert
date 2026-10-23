unit Atlas.Linux.Documents.FileWatcher;

// Platform-Feature "Documents" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Documents.FileWatcher (#227). Ein Hintergrund-Thread wartet
// über inotify auf Änderungen in den Ordnern der Dateien und sieht spätestens
// alle PollMs nach (Ordner, die es noch nicht gibt). Welche Dateien sich
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
    PollMs = 2000;
    SettleMs = 100;
    /// <summary>So oft sieht der Thread nach Stop und neuer Dateiliste.</summary>
    SliceMs = 100;
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

{ TFileWatcher }

class function TFileWatcher.Stamp(const AFileName: string): string;
var
  Info: Stat;
begin
  if FpStat(RawByteString(UTF8String(AFileName)), Info) <> 0 then
    Exit('');
  if FpS_ISDIR(Info.st_mode) then
    Exit('');
  Result := Format('%d.%d.%d', [Int64(Info.st_mtime), Int64(Info.st_mtime_nsec), Int64(Info.st_size)]);
end;

/// <summary>Wartet bis zu ATimeoutMs auf Ereignisse von inotify und liest sie ab; True, wenn welche kamen.</summary>
function WaitForEvents(AInotify: cint; ATimeoutMs: Integer): Boolean;
var
  Poll: pollfd;
  Buffer: array[0..4095] of Byte;
begin
  Result := False;
  if AInotify < 0 then
  begin
    Sleep(ATimeoutMs);
    Exit;
  end;
  Poll.fd := AInotify;
  Poll.events := POLLIN;
  Poll.revents := 0;
  if FpPoll(@Poll, 1, ATimeoutMs) <= 0 then
    Exit;
  while FpRead(AInotify, Buffer, SizeOf(Buffer)) > 0 do
    Result := True;
end;

constructor TFileWatcher.Create(const AOnChanged: TFileWatcherChanged);
var
  Tracker: TFileChangeTracker;
  Stop, Reconfigure: TEvent;
  OnChanged: TFileWatcherChanged;
begin
  inherited Create;
  FTracker := TFileChangeTracker.Create(
    function(const AFileName: string): string
    begin
      Result := TFileWatcher.Stamp(AFileName);
    end);
  FStop := TEvent.Create(nil, True, False, '');
  FReconfigure := TEvent.Create(nil, False, False, '');
  Tracker := FTracker;
  Stop := FStop;
  Reconfigure := FReconfigure;
  OnChanged := AOnChanged;
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      Inotify: cint;
      Dir: string;
      Waited: Integer;
      Changed: TArray<string>;
    begin
      repeat
        Inotify := inotify_init1(IN_NONBLOCK or IN_CLOEXEC);
        try
          if Inotify >= 0 then
            for Dir in Tracker.Directories do
              inotify_add_watch(Inotify, PAnsiChar(UTF8String(Dir)),
                IN_MODIFY or IN_CLOSE_WRITE or IN_MOVED_TO or IN_MOVED_FROM or IN_CREATE or IN_DELETE);
          Waited := 0;
          repeat
            if Stop.WaitFor(0) = wrSignaled then
              Exit;
            if Reconfigure.WaitFor(0) = wrSignaled then
              Break;
            if WaitForEvents(Inotify, SliceMs) then
            begin
              // Mehrere Meldungen eines Speichervorgangs zusammenfassen.
              if Stop.WaitFor(SettleMs) = wrSignaled then
                Exit;
              WaitForEvents(Inotify, 0);
              Waited := PollMs;
            end
            else
              Inc(Waited, SliceMs);
            if Waited >= PollMs then
            begin
              Waited := 0;
              Changed := Tracker.Poll;
              if Length(Changed) > 0 then
                OnChanged(Changed);
            end;
          until False;
        finally
          if Inotify >= 0 then
            FpClose(Inotify);
        end;
      until False;
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

destructor TFileWatcher.Destroy;
begin
  if FThread <> nil then
  begin
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
