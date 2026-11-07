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
    cStopMs = 1000;
    /// <summary>Takt, in dem Warten auf ein anderes Ereignis das Signal prüft.</summary>
    cSliceMs = 20;
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
    class function WaitForThreads(const AThreads: TArray<TThread>; AMs: Cardinal): Boolean; overload; static;
    /// <summary>Wie oben mit AMs = StopMs.</summary>
    class function WaitForThreads(const AThreads: TArray<TThread>): Boolean; overload; static;
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
  begin
    FEvent.SetEvent;
  end;
end;

class procedure TAtlasShutdown.Reset;
begin
  if FEvent <> nil then
  begin
    FEvent.ResetEvent;
  end;
end;

class function TAtlasShutdown.Signalled: Boolean;
begin
  Result := (FEvent <> nil) and (FEvent.WaitFor(0) = wrSignaled);
end;

class function TAtlasShutdown.Wait(AMs: Cardinal): Boolean;
begin
  if FEvent = nil then
  begin
    Exit(True);
  end;
  Result := FEvent.WaitFor(AMs) = wrSignaled;
end;

class function TAtlasShutdown.WaitFor(AEvent: TEvent; ATimeoutMs: Cardinal): TWaitResult;
var
  mWatch: TStopwatch;
  mLeft: Int64;
  mSlice: Cardinal;
begin
  mWatch := TStopwatch.StartNew;
  repeat
    if Signalled then
    begin
      Exit(wrAbandoned);
    end;
    mLeft := Int64(ATimeoutMs) - mWatch.ElapsedMilliseconds;
    if mLeft <= 0 then
    begin
      mSlice := 0;
    end
    else if mLeft < cSliceMs then
    begin
      mSlice := Cardinal(mLeft);
    end
    else
    begin
      mSlice := cSliceMs;
    end;
    Result := AEvent.WaitFor(mSlice);
    if Result <> wrTimeout then
    begin
      Exit;
    end;
  until mWatch.ElapsedMilliseconds >= ATimeoutMs;
  Result := wrTimeout;
end;

class function TAtlasShutdown.WaitForThreads(const AThreads: TArray<TThread>): Boolean;
begin
  Result := WaitForThreads(AThreads, cStopMs);
end;

class function TAtlasShutdown.WaitForThreads(const AThreads: TArray<TThread>; AMs: Cardinal): Boolean;
var
  mWatch: TStopwatch;
  mThread: TThread;
begin
  mWatch := TStopwatch.StartNew;
  repeat
    Result := True;
    for mThread in AThreads do
    begin
      if (mThread <> nil) and not mThread.Finished then
      begin
        Result := False;
      end;
    end;
    if Result then
    begin
      Exit;
    end;
    // Bewusst Finished statt Thread-Handle: Das Handle wird erst nach DLL_THREAD_DETACH signalisiert, und das braucht
    // beim Prozessende die Ladersperre, die das Entladen unter Umständen hält (Code-Review A-13).
    Sleep(5);
  until mWatch.ElapsedMilliseconds >= AMs;
end;

end.
