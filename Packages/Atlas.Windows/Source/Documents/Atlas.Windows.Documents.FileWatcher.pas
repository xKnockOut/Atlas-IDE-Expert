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

constructor TFileWatcher.Create(const AOnChanged: TFileWatcherChanged);
var
  Tracker: TFileChangeTracker;
  Stop, Reconfigure: THandle;
  OnChanged: TFileWatcherChanged;
begin
  inherited Create;
  FTracker := TFileChangeTracker.Create(
    function(const AFileName: string): string
    begin
      Result := TFileWatcher.Stamp(AFileName);
    end);
  FStop := CreateEvent(nil, True, False, nil);
  FReconfigure := CreateEvent(nil, False, False, nil);
  Tracker := FTracker;
  Stop := FStop;
  Reconfigure := FReconfigure;
  OnChanged := AOnChanged;
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      Handles: TArray<THandle>;
      Dir: string;
      Notify: THandle;
      Index: Integer;
      Wait: Cardinal;
      Changed: TArray<string>;
    begin
      repeat
        // Handles[0] Stop, [1] neue Dateiliste, dahinter je Ordner eine Änderungsmeldung.
        Handles := [Stop, Reconfigure];
        for Dir in Tracker.Directories do
        begin
          if Length(Handles) >= MAXIMUM_WAIT_OBJECTS then
          begin
            Break;
          end;
          Notify := FindFirstChangeNotification(PChar(Dir), False, FILE_NOTIFY_CHANGE_FILE_NAME or
            FILE_NOTIFY_CHANGE_LAST_WRITE or FILE_NOTIFY_CHANGE_SIZE);
          if Notify <> INVALID_HANDLE_VALUE then
          begin
            Handles := Handles + [Notify];
          end;
        end;
        try
          repeat
            Wait := WaitForMultipleObjects(Length(Handles), @Handles[0], False, PollMs);
            if Wait = WAIT_OBJECT_0 then
            begin
              Exit;
            end;
            if Wait = WAIT_OBJECT_0 + 1 then
            begin
              Break;
            end;
            if (Wait > WAIT_OBJECT_0 + 1) and (Wait < WAIT_OBJECT_0 + Cardinal(Length(Handles))) then
            begin
              // Mehrere Meldungen eines Speichervorgangs zusammenfassen.
              if WaitForSingleObject(Stop, SettleMs) = WAIT_OBJECT_0 then
              begin
                Exit;
              end;
              FindNextChangeNotification(Handles[Wait - WAIT_OBJECT_0]);
            end;
            Changed := Tracker.Poll;
            if Length(Changed) > 0 then
            begin
              OnChanged(Changed);
            end;
          until False;
        finally
          for Index := 2 to High(Handles) do
          begin
            FindCloseChangeNotification(Handles[Index]);
          end;
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
