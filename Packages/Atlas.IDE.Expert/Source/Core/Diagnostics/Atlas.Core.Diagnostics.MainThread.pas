unit Atlas.Core.Diagnostics.MainThread;

// Einreihen in den Hauptthread der IDE, ohne dass ein Eintrag das Entladen des
// Packages überlebt (Code-Review A-02). TThread.Queue(nil, …) und
// ForceQueue(nil, …) gehören keinem Thread: Nichts räumt sie beim Entladen
// weg, und CheckSynchronize ruft sie danach in nicht mehr geladenem Code auf.
// Hier gehört jeder Eintrag einem eigenen, ruhenden Besitzer-Thread. Stop (die
// Komposition ruft es direkt nach TAtlasShutdown.Signal) entfernt alle noch
// wartenden Einträge und nimmt keine neuen mehr an.
// Nicht an den aufrufenden Arbeiter gebunden: Hover und Vervollständigung geben
// fertige Arbeiter frei (ReapWorkers), bevor CheckSynchronize ihre Einträge
// ausführt; TThread.Destroy würde die Ergebnisse dann entfernen.
// Jeder Eintrag läuft unter der Sicherung (#493): Eine Ausnahme zählt für das
// angegebene Feature und erreicht nie TApplication.HandleException (S-05).
// Queue führt im Hauptthread sofort aus (wie TThread.Queue), ForceQueue reiht
// immer ein. Beide sind aus jedem Thread aufrufbar.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Core.Diagnostics.Guard;

type
  TAtlasMainThread = class
  private type
    /// <summary>Besitzer der Einträge; schläft, bis Stop ihn beendet.</summary>
    TOwner = class(TThread)
    private
      FWake: TEvent;
    protected
      procedure Execute; override;
      procedure TerminatedSet; override;
    public
      constructor Create;
      destructor Destroy; override;
    end;
  private class var
    FLock: TCriticalSection;
    FOwner: TOwner;
    FStopped: Boolean;
    class function Guarded(AFeature: TAtlasFeature; const AProc: TThreadProcedure): TThreadProcedure; static;
    class procedure Post(AFeature: TAtlasFeature; const AProc: TThreadProcedure; AForce: Boolean); static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Im Hauptthread sofort, aus anderen Threads eingereiht. Ausnahmen zählen für AFeature.</summary>
    class procedure Queue(AFeature: TAtlasFeature; const AProc: TThreadProcedure); static;
    /// <summary>Immer eingereiht, auch aus dem Hauptthread (läuft nach dem laufenden Ereignis).
    /// Nach Stop verworfen.</summary>
    class procedure ForceQueue(AFeature: TAtlasFeature; const AProc: TThreadProcedure); static;
    /// <summary>Nach dem Laden (Register): Einträge wieder annehmen.</summary>
    class procedure Start; static;
    /// <summary>Beim Entladen, nur im Hauptthread: wartende Einträge verwerfen, keine neuen annehmen.</summary>
    class procedure Stop; static;
    /// <summary>Läuft der Aufrufer im Hauptthread?</summary>
    class function IsMain: Boolean; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Shutdown;

{ TAtlasMainThread.TOwner }

constructor TAtlasMainThread.TOwner.Create;
begin
  FWake := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TAtlasMainThread.TOwner.Destroy;
begin
  inherited Destroy;
  FWake.Free;
end;

procedure TAtlasMainThread.TOwner.Execute;
begin
  NameThreadForDebugging('Atlas.MainThread');
  // Der Thread führt nichts aus; er besitzt nur die Einträge (RemoveQueuedEvents in Stop).
  while not Terminated do
    FWake.WaitFor(1000);
end;

procedure TAtlasMainThread.TOwner.TerminatedSet;
begin
  inherited;
  FWake.SetEvent;
end;

{ TAtlasMainThread }

class constructor TAtlasMainThread.Create;
begin
  FLock := TCriticalSection.Create;
  // Gleich beim Laden: Ein späteres Anlegen zählte im ersten Test, der einreiht, als Leck.
  FOwner := TOwner.Create;
  FStopped := False;
end;

class destructor TAtlasMainThread.Destroy;
begin
  Stop;
  FreeAndNil(FLock);
end;

class function TAtlasMainThread.IsMain: Boolean;
begin
  Result := TThread.CurrentThread.ThreadID = MainThreadID;
end;

class function TAtlasMainThread.Guarded(AFeature: TAtlasFeature; const AProc: TThreadProcedure): TThreadProcedure;
var
  Feature: TAtlasFeature;
  Proc: TThreadProcedure;
begin
  Feature := AFeature;
  Proc := AProc;
  Result :=
    procedure
    begin
      try
        Proc();
      except
        on EAbort do
          ;
        on E: Exception do
          TAtlasGuard.Report(Feature, E);
      end;
    end;
end;

class procedure TAtlasMainThread.Post(AFeature: TAtlasFeature; const AProc: TThreadProcedure; AForce: Boolean);
var
  Proc: TThreadProcedure;
begin
  if FLock = nil then
    Exit;
  Proc := Guarded(AFeature, AProc);
  // Unter FLock nur einreihen, nie ausführen (AForce oder Arbeiter-Thread): Kein fremder Code hält die Sperre,
  // ein Hauptthread in Stop kann nicht auf einen Arbeiter warten, der hier wartet.
  FLock.Enter;
  try
    // Nach Stop (Entladen): verwerfen; der Code dahinter ist gleich nicht mehr geladen.
    if FStopped or (FOwner = nil) then
      Exit;
    if AForce then
      TThread.ForceQueue(FOwner, Proc)
    else
      TThread.Queue(FOwner, Proc);
  finally
    FLock.Leave;
  end;
end;

class procedure TAtlasMainThread.Queue(AFeature: TAtlasFeature; const AProc: TThreadProcedure);
var
  Proc: TThreadProcedure;
begin
  // Wie TThread.Queue: im Hauptthread sofort, auch nach Stop (das Entladen ruft noch Code im Hauptthread).
  if IsMain then
  begin
    Proc := Guarded(AFeature, AProc);
    Proc();
  end
  else
    Post(AFeature, AProc, False);
end;

class procedure TAtlasMainThread.ForceQueue(AFeature: TAtlasFeature; const AProc: TThreadProcedure);
begin
  Post(AFeature, AProc, True);
end;

class procedure TAtlasMainThread.Start;
begin
  if FLock = nil then
    Exit;
  FLock.Enter;
  try
    FStopped := False;
    if FOwner = nil then
      FOwner := TOwner.Create;
  finally
    FLock.Leave;
  end;
end;

class procedure TAtlasMainThread.Stop;
var
  Owner: TOwner;
begin
  if FLock = nil then
    Exit;
  FLock.Enter;
  try
    FStopped := True;
    Owner := FOwner;
    FOwner := nil;
  finally
    FLock.Leave;
  end;
  if Owner = nil then
    Exit;
  // Ab hier kommt kein Eintrag mehr dazu (Post prüft unter FLock); alle wartenden verwerfen.
  TThread.RemoveQueuedEvents(Owner);
  Owner.Terminate;
  // Nicht Owner.WaitFor (arbeitet im Hauptthread die Warteschlange ab) und nicht das Handle (braucht beim
  // Prozessende die Ladersperre): auf Finished warten wie TAtlasTimeLimit.StopAll.
  if TAtlasShutdown.WaitForThreads([TThread(Owner)], TAtlasShutdown.StopMs) then
    Owner.Free
  else
  begin
    TAtlasGuard.Log('Atlas: Besitzer der Hauptthread-Einträge endet nicht; er gibt sich bei Rückkehr selbst frei');
    Owner.FreeOnTerminate := True;
  end;
end;

end.
