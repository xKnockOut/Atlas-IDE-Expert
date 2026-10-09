unit Argus.Windows.Process.ParentWatcher;

// Überwacht den Editor-Prozess (#283): Endet er, ohne den Server sauber zu
// beenden (Absturz, Task-Manager), meldet ein Hintergrund-Thread das über
// OnExited, damit der Server nicht verwaist weiterläuft.

interface

uses
  System.SysUtils,
  System.Classes;

type
  TParentWatcher = class
  private
    FProcess: THandle;
    FStop: THandle;
    FThread: TThread;
  public
    /// <summary>Beginnt die Überwachung von AProcessId. AOnExited läuft im Überwachungs-
    /// Thread. Gibt es den Prozess nicht (mehr), wird AOnExited sofort aufgerufen.</summary>
    constructor Create(AProcessId: Cardinal; const AOnExited: TProc);
    destructor Destroy; override;
    /// <summary>True, wenn der Prozess beim Start überwacht werden konnte.</summary>
    function Watching: Boolean;
    /// <summary>Nummer des eigenen Prozesses, z. B. für Ausweich-Dateinamen.</summary>
    class function CurrentProcessId: Cardinal; static;
  end;

implementation

uses
  Winapi.Windows;

constructor TParentWatcher.Create(AProcessId: Cardinal; const AOnExited: TProc);
var
  Process, Stop: THandle;
  OnExited: TProc;
begin
  inherited Create;
  FProcess := OpenProcess(SYNCHRONIZE, False, AProcessId);
  if FProcess = 0 then
  begin
    // Ohne Zugriffsrecht nicht beenden; nur ein fehlender Prozess zählt als beendet.
    if GetLastError = ERROR_INVALID_PARAMETER then
      AOnExited();
    Exit;
  end;
  FStop := CreateEvent(nil, True, False, nil);
  Process := FProcess;
  Stop := FStop;
  OnExited := AOnExited;
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      Handles: array[0..1] of THandle;
    begin
      Handles[0] := Process;
      Handles[1] := Stop;
      if WaitForMultipleObjects(2, @Handles[0], False, INFINITE) = WAIT_OBJECT_0 then
        OnExited();
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

destructor TParentWatcher.Destroy;
begin
  if FThread <> nil then
  begin
    SetEvent(FStop);
    FThread.WaitFor;
    FThread.Free;
  end;
  if FStop <> 0 then
    CloseHandle(FStop);
  if FProcess <> 0 then
    CloseHandle(FProcess);
  inherited;
end;

class function TParentWatcher.CurrentProcessId: Cardinal;
begin
  Result := GetCurrentProcessId;
end;

function TParentWatcher.Watching: Boolean;
begin
  Result := FThread <> nil;
end;

end.
