unit Atlas.Core.Diagnostics.Shutdown;

// Gemeinsames Abbruchsignal aller Hintergrund-Threads des Plugins (#493).
// Beim Schließen der IDE und beim Entladen des Packages setzt die Komposition
// das Signal als Erstes; jedes Warten in einem Hintergrund-Thread (Antwort
// des Servers, Takt eines Wächters, Zeitlimit-Arbeiter) wartet über WaitFor
// bzw. Wait und kehrt dann sofort zurück. So enden alle Threads innerhalb von
// StopMs, auch wenn eine Anfrage an den Server noch Sekunden Zeitlimit hätte.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs;

type
  TAtlasShutdown = class
  public const
    /// <summary>So lange dürfen alle Threads zusammen nach dem Signal brauchen.</summary>
    StopMs = 1000;
    /// <summary>Takt, in dem Warten auf ein anderes Ereignis das Signal prüft.</summary>
    SliceMs = 20;
  private class var
    FEvent: TEvent;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Abbruch für alle Threads auslösen (Entladen, IDE schließen).</summary>
    class procedure Signal; static;
    /// <summary>Nach dem Laden: Signal zurücknehmen.</summary>
    class procedure Reset; static;
    class function Signalled: Boolean; static;
    /// <summary>Bis zu AMs warten; True, wenn dabei das Abbruchsignal kam.</summary>
    class function Wait(AMs: Cardinal): Boolean; static;
    /// <summary>Auf AEvent bis zu ATimeoutMs warten; wrAbandoned, wenn vorher das Abbruchsignal kam.</summary>
    class function WaitFor(AEvent: TEvent; ATimeoutMs: Cardinal): TWaitResult; static;
    /// <summary>Auf das Ende von AThreads warten, zusammen höchstens AMs; True, wenn alle beendet sind.</summary>
    class function WaitForThreads(const AThreads: TArray<TThread>; AMs: Cardinal = StopMs): Boolean; static;
  end;

implementation

uses
  System.Diagnostics;

{ TAtlasShutdown }

class constructor TAtlasShutdown.Create;
begin
  FEvent := TEvent.Create(nil, True, False, '');
end;

class destructor TAtlasShutdown.Destroy;
begin
  FreeAndNil(FEvent);
end;

class procedure TAtlasShutdown.Signal;
begin
  if FEvent <> nil then
    FEvent.SetEvent;
end;

class procedure TAtlasShutdown.Reset;
begin
  if FEvent <> nil then
    FEvent.ResetEvent;
end;

class function TAtlasShutdown.Signalled: Boolean;
begin
  Result := (FEvent <> nil) and (FEvent.WaitFor(0) = wrSignaled);
end;

class function TAtlasShutdown.Wait(AMs: Cardinal): Boolean;
begin
  if FEvent = nil then
    Exit(True);
  Result := FEvent.WaitFor(AMs) = wrSignaled;
end;

class function TAtlasShutdown.WaitFor(AEvent: TEvent; ATimeoutMs: Cardinal): TWaitResult;
var
  Watch: TStopwatch;
  Left: Int64;
  Slice: Cardinal;
begin
  Watch := TStopwatch.StartNew;
  repeat
    if Signalled then
      Exit(wrAbandoned);
    Left := Int64(ATimeoutMs) - Watch.ElapsedMilliseconds;
    if Left <= 0 then
      Slice := 0
    else if Left < SliceMs then
      Slice := Cardinal(Left)
    else
      Slice := SliceMs;
    Result := AEvent.WaitFor(Slice);
    if Result <> wrTimeout then
      Exit;
  until Watch.ElapsedMilliseconds >= ATimeoutMs;
  Result := wrTimeout;
end;

class function TAtlasShutdown.WaitForThreads(const AThreads: TArray<TThread>; AMs: Cardinal): Boolean;
var
  Watch: TStopwatch;
  Thread: TThread;
begin
  Watch := TStopwatch.StartNew;
  repeat
    Result := True;
    for Thread in AThreads do
      if (Thread <> nil) and not Thread.Finished then
        Result := False;
    if Result then
      Exit;
    Sleep(5);
  until Watch.ElapsedMilliseconds >= AMs;
end;

end.
