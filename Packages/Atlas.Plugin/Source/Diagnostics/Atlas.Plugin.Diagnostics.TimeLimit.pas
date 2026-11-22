unit Atlas.Plugin.Diagnostics.TimeLimit;

// Blockierschutz (#493): Aufrufe von Datenquellen, die der Hauptthread der IDE
// auslöst, laufen in einem Arbeiter-Thread; der Hauptthread wartet höchstens
// LimitMs (Standard 200 ms) auf das Ende. Dauert es länger, kehrt Run mit
// TimedOut zurück, der Aufrufer bricht ab und zählt es wie einen Fehler. Der
// Arbeiter läuft dann zu Ende und kehrt erst danach in den Vorrat zurück;
// für den nächsten Aufruf startet bei Bedarf ein weiterer. Exceptions im
// Aufruf kommen als Failed mit Klasse und Meldung zurück, nie in die IDE.
// Die Arbeiter warten über TAtlasShutdown und enden beim Entladen (StopAll).
// Hängende Arbeiter: Wer beim Entladen noch in einem Aufruf steckt, gehört
// nicht mehr zum Vorrat und geht an TAtlasOverdueThreads, zusammen mit dem
// Package, in dem der Code des Aufrufs liegt (Run mit AModule, sonst dieses).
// SettleBeforeUnload wartet dann beim Abmelden dieses Packages nach und hält
// es fest, solange der Arbeiter läuft. Meldet sich ein Modul ab, während Base
// geladen bleibt, übergibt ReleaseModule seine hängenden Arbeiter ebenso
// (TAtlasModuleHost.ConnectRegistry); sonst kehrte der Aufruf nach dem
// Entladen des Modul-Packages in nicht mehr geladenen Code zurück.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections;

type
{$SCOPEDENUMS ON}
  TAtlasTimedOutcome = (Done, Failed, TimedOut);
{$SCOPEDENUMS OFF}

  TAtlasTimeLimit = class
  public const
    cDefaultMs = 200;
    cMinMs = 50;
    cMaxMs = 5000;
  private type
    TWorker = class(TThread)
    private
      FStart: TEvent;
      FDone: TEvent;
      FProc: TProc;
      FError: string;
      // Unter FLock: fertig mit dem aktuellen Aufruf bzw. vom Aufrufer aufgegeben.
      FFinished: Boolean;
      FAbandoned: Boolean;
      // Unter FLock: Package des Codes im aktuellen Aufruf (0 = das von TAtlasTimeLimit); sein Modul hat sich
      // abgemeldet, während ein Aufrufer noch wartet: übergeben, sobald dieser aufgibt.
      FModule: HMODULE;
      FHandOver: Boolean;
      /// <summary>Wartet auf den nächsten Auftrag; False bei Ende oder Herunterfahren.</summary>
      function WaitForStart: Boolean;
      /// <summary>Führt FProc aus; Fehlertext oder ''.</summary>
      function RunCurrent: string;
      /// <summary>Meldet den Aufruf fertig; True, wenn der Aufrufer aufgegeben hatte.</summary>
      function Finish(const AError: string): Boolean;
    protected
      procedure Execute; override;
    public
      constructor Create;
      destructor Destroy; override;
    end;
  private class var
    FLock: TCriticalSection;
    FIdle: TList<TWorker>;
    FAll: TList<TWorker>;
    FLimitMs: Integer;
    /// <summary>Auto-Reset; gesetzt, sobald ein Arbeiter frei wird (WaitIdle).</summary>
    FReleased: TEvent;
    class function Take(AModule: HMODULE): TWorker; static;
    class procedure Release(AWorker: TWorker); static;
    /// <summary>Unter FLock: AWorker gehört nicht mehr zum Vorrat und endet nach seinem Aufruf, ohne den Vorrat
    /// noch anzufassen.</summary>
    class procedure Detach(AWorker: TWorker); static;
    /// <summary>Package, das für einen hängenden AWorker festzuhalten ist.</summary>
    class function PackageOf(AWorker: TWorker): HMODULE; static;
    /// <summary>Nach dem Warten in Run: True mit AError, wenn AWorker fertig ist; sonst gibt der Aufrufer ihn auf
    /// (oder übergibt ihn, falls sein Modul sich inzwischen abgemeldet hat).</summary>
    class function Collect(AWorker: TWorker; out AError: string): Boolean; static;
    class procedure SetLimitMs(AValue: Integer); static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>AProc mit Zeitlimit ausführen (ALimitMs &lt; 0: LimitMs). AError: Klasse und Meldung bei
    /// Failed.</summary>
    class function Run(const AProc: TProc; out AError: string; ALimitMs: Integer): TAtlasTimedOutcome;
      overload; static;
    /// <summary>Wie oben; AModule ist das Package, in dem der Code liegt, den AProc ruft (eine Quelle aus einem
    /// Modul-Package), 0 = das von TAtlasTimeLimit. Hängt der Aufruf beim Abmelden dieses Packages noch, hält
    /// TAtlasOverdueThreads es fest.</summary>
    class function Run(const AProc: TProc; out AError: string; ALimitMs: Integer;
      AModule: HMODULE): TAtlasTimedOutcome; overload; static;
    /// <summary>Wie oben mit ALimitMs = -1 (LimitMs).</summary>
    class function Run(const AProc: TProc; out AError: string): TAtlasTimedOutcome; overload; static;
    /// <summary>Alle Arbeiter beenden (nach TAtlasShutdown.Signal); True, wenn alle innerhalb von AMs enden.
    /// Hängende gehen an TAtlasOverdueThreads; der Aufrufer ruft danach SettleBeforeUnload für sein Package.
    /// </summary>
    class function StopAll(AMs: Cardinal): Boolean; overload; static;
    /// <summary>Wie oben mit AMs = 1000.</summary>
    class function StopAll: Boolean; overload; static;
    /// <summary>Das Modul im Package AModule meldet sich ab: Arbeiter, die gerade Code daraus ausführen und deren
    /// Aufrufer aufgegeben hat, gehören nicht mehr zum Vorrat und gehen an TAtlasOverdueThreads (Package AModule).
    /// Wartet ein Aufrufer noch (höchstens sein Zeitlimit), geht der Arbeiter über, sobald dieser aufgibt.
    /// Ergebnis: Zahl der übergebenen Arbeiter; 0 wird übergangen.</summary>
    class function ReleaseModule(AModule: HMODULE): Integer; static;
    /// <summary>Arbeiter, die gerade einen Aufruf ausführen (auch aufgegebene).</summary>
    class function BusyCount: Integer; static;
    /// <summary>Bis zu AMs warten, bis kein Arbeiter mehr einen Aufruf ausführt (auch aufgegebene); True, wenn
    /// alle frei sind. Vor dem Freigeben einer Sitzung, die aufgegebene Aufrufe noch nutzen könnten.</summary>
    class function WaitIdle(AMs: Cardinal): Boolean; static;
    /// <summary>Zeitlimit für Aufrufe aus dem Hauptthread, MinMs bis MaxMs.</summary>
    class property LimitMs: Integer read FLimitMs write SetLimitMs;
  end;

implementation

uses
  System.Diagnostics,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Plugin.Diagnostics.Shutdown,
  Atlas.Plugin.Diagnostics.WorkerSlot,
  Atlas.Plugin.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TTimeLimitText = (AtlasIsShuttingDown);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TTimeLimitText] of string = (
    ('Atlas wird beendet'),
    ('Atlas is shutting down'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TTimeLimitText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

{ TAtlasTimeLimit.TWorker }

constructor TAtlasTimeLimit.TWorker.Create;
begin
  FStart := TEvent.Create(nil, False, False, '');
  FDone := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TAtlasTimeLimit.TWorker.Destroy;
begin
  inherited Destroy;
  FDone.Free;
  FStart.Free;
end;

procedure TAtlasTimeLimit.TWorker.Execute;
var
  mError: string;
begin
  try
    while WaitForStart do
    begin
      mError := RunCurrent;
      // Nicht mehr im Vorrat (StopAll beim Entladen, ReleaseModule): nichts mehr anfassen, was ihm gehört;
      // TAtlasOverdueThreads gibt den Arbeiter frei.
      if Terminated then
      begin
        Exit;
      end;
      // Der Aufrufer hat aufgegeben: Erst jetzt ist der Arbeiter wieder frei.
      if Finish(mError) then
      begin
        TAtlasTimeLimit.Release(Self);
      end;
    end;
  except
    on E: Exception do
    begin
      TAtlasGuard.Log('TAtlasTimeLimit: ' + TAtlasGuard.ErrorText(E));
    end;
  end;
end;

function TAtlasTimeLimit.TWorker.WaitForStart: Boolean;
const
  // Wartet in Schritten, damit Terminated geprüft wird.
  cWaitStepMs = 1000;
begin
  Result := False;
  while not Terminated do
  begin
    if TAtlasShutdown.WaitFor(FStart, cWaitStepMs) = wrSignaled then
    begin
      Exit(not Terminated);
    end;
    if TAtlasShutdown.Signalled then
    begin
      Exit;
    end;
  end;
end;

function TAtlasTimeLimit.TWorker.RunCurrent: string;
var
  mProc: TProc;
begin
  Result := '';
  mProc := FProc;
  try
    if Assigned(mProc) then
    begin
      mProc();
    end;
  except
    on E: Exception do
    begin
      Result := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

function TAtlasTimeLimit.TWorker.Finish(const AError: string): Boolean;
begin
  TAtlasTimeLimit.FLock.Enter;
  try
    FProc := nil;
    FError := AError;
    FFinished := True;
    Result := FAbandoned;
    FAbandoned := False;
    FDone.SetEvent;
  finally
    TAtlasTimeLimit.FLock.Leave;
  end;
end;

{ TAtlasTimeLimit }

class constructor TAtlasTimeLimit.Create;
begin
  FLock := TCriticalSection.Create;
  FIdle := TList<TWorker>.Create;
  FAll := TList<TWorker>.Create;
  FLimitMs := cDefaultMs;
  FReleased := TEvent.Create(nil, False, False, '');
end;

class destructor TAtlasTimeLimit.Destroy;
begin
  StopAll;
  FreeAndNil(FReleased);
  FreeAndNil(FAll);
  FreeAndNil(FIdle);
  FreeAndNil(FLock);
end;

class procedure TAtlasTimeLimit.SetLimitMs(AValue: Integer);
begin
  if AValue < cMinMs then
  begin
    AValue := cMinMs;
  end;
  if AValue > cMaxMs then
  begin
    AValue := cMaxMs;
  end;
  FLimitMs := AValue;
end;

class function TAtlasTimeLimit.Take(AModule: HMODULE): TWorker;
begin
  FLock.Enter;
  try
    Result := nil;
    while (Result = nil) and (FIdle.Count > 0) do
    begin
      Result := FIdle.Last;
      FIdle.Delete(FIdle.Count - 1);
      // Nach einem Abbruchsignal beendet: verwerfen.
      if Result.Finished then
      begin
        FAll.Remove(Result);
        Result.Free;
        Result := nil;
      end;
    end;
    if Result = nil then
    begin
      Result := TWorker.Create;
      FAll.Add(Result);
    end;
    Result.FFinished := False;
    Result.FAbandoned := False;
    Result.FModule := AModule;
    Result.FHandOver := False;
    Result.FError := '';
    Result.FDone.ResetEvent;
  finally
    FLock.Leave;
  end;
end;

class procedure TAtlasTimeLimit.Release(AWorker: TWorker);
begin
  FLock.Enter;
  try
    if FAll.Contains(AWorker) and not FIdle.Contains(AWorker) then
    begin
      FIdle.Add(AWorker);
      FReleased.SetEvent;
    end;
  finally
    FLock.Leave;
  end;
end;

class procedure TAtlasTimeLimit.Detach(AWorker: TWorker);
begin
  FAll.Remove(AWorker);
  FIdle.Remove(AWorker);
  AWorker.Terminate;
  // WaitIdle zählt ihn nicht mehr mit.
  FReleased.SetEvent;
end;

class function TAtlasTimeLimit.PackageOf(AWorker: TWorker): HMODULE;
begin
  Result := AWorker.FModule;
  if Result = 0 then
  begin
    // Der Aufruf liegt in diesem Package (im Package HInstance), ebenso Execute des Arbeiters.
    Result := HInstance;
  end;
end;

class function TAtlasTimeLimit.Collect(AWorker: TWorker; out AError: string): Boolean;
var
  mHandOver: Boolean;
begin
  AError := '';
  mHandOver := False;
  FLock.Enter;
  try
    Result := AWorker.FFinished;
    if Result then
    begin
      AError := AWorker.FError;
    end
    else if AWorker.FHandOver then
    begin
      // Sein Modul hat sich abgemeldet, während hier gewartet wurde (ReleaseModule).
      Detach(AWorker);
      mHandOver := True;
    end
    else
    begin
      AWorker.FAbandoned := True;
    end;
  finally
    FLock.Leave;
  end;
  if mHandOver then
  begin
    TAtlasOverdueThreads.Adopt(AWorker, PackageOf(AWorker));
  end;
end;

class function TAtlasTimeLimit.Run(const AProc: TProc; out AError: string; ALimitMs: Integer): TAtlasTimedOutcome;
begin
  Result := Run(AProc, AError, ALimitMs, 0);
end;

class function TAtlasTimeLimit.Run(const AProc: TProc; out AError: string; ALimitMs: Integer;
  AModule: HMODULE): TAtlasTimedOutcome;
var
  mWorker: TWorker;
  mLimit: Cardinal;
begin
  AError := '';
  if TAtlasShutdown.Signalled then
  begin
    AError := UiText(TTimeLimitText.AtlasIsShuttingDown);
    Exit(TAtlasTimedOutcome.Failed);
  end;
  if ALimitMs < 0 then
  begin
    mLimit := FLimitMs;
  end
  else
  begin
    mLimit := ALimitMs;
  end;
  mWorker := Take(AModule);
  mWorker.FProc := AProc;
  mWorker.FStart.SetEvent;
  mWorker.FDone.WaitFor(mLimit);
  if not Collect(mWorker, AError) then
  begin
    Exit(TAtlasTimedOutcome.TimedOut);
  end;
  Release(mWorker);
  if AError <> '' then
  begin
    Result := TAtlasTimedOutcome.Failed;
  end
  else
  begin
    Result := TAtlasTimedOutcome.Done;
  end;
end;

class function TAtlasTimeLimit.Run(const AProc: TProc; out AError: string): TAtlasTimedOutcome;
begin
  Result := Run(AProc, AError, -1);
end;

class function TAtlasTimeLimit.StopAll(AMs: Cardinal): Boolean;
var
  mWorkers: TArray<TWorker>;
  mWorker: TWorker;
  mThreads: TArray<TThread>;
begin
  if FLock = nil then
  begin
    Exit(True);
  end;
  FLock.Enter;
  try
    mWorkers := FAll.ToArray;
    FAll.Clear;
    FIdle.Clear;
  finally
    FLock.Leave;
  end;
  mThreads := nil;
  for mWorker in mWorkers do
  begin
    mWorker.Terminate;
    mWorker.FStart.SetEvent;
    mThreads := mThreads + [TThread(mWorker)];
  end;
  Result := TAtlasShutdown.WaitForThreads(mThreads, AMs);
  for mWorker in mWorkers do
  begin
    if mWorker.Finished then
    begin
      mWorker.Free;
    end
    else
    begin
      // Ein Aufruf steckt in nicht abbrechbarem Code. Das Nachwarten und Festhalten des Packages übernimmt
      // TAtlasOverdueThreads.SettleBeforeUnload beim Abmelden; danach gibt die Liste den Arbeiter frei.
      TAtlasOverdueThreads.Adopt(mWorker, PackageOf(mWorker));
    end;
  end;
  // WaitIdle nicht länger warten lassen: Die Arbeiter gehören nicht mehr zum Vorrat.
  if FReleased <> nil then
  begin
    FReleased.SetEvent;
  end;
end;

class function TAtlasTimeLimit.StopAll: Boolean;
const
  cStopMs = 1000;
begin
  Result := StopAll(cStopMs);
end;

class function TAtlasTimeLimit.ReleaseModule(AModule: HMODULE): Integer;
var
  mWorker: TWorker;
  mHanded: TArray<TWorker>;
begin
  Result := 0;
  if (AModule = 0) or (FLock = nil) then
  begin
    Exit;
  end;
  mHanded := nil;
  FLock.Enter;
  try
    for mWorker in FAll.ToArray do
    begin
      if (mWorker.FModule <> AModule) or mWorker.FFinished then
      begin
        Continue;
      end;
      if mWorker.FAbandoned then
      begin
        Detach(mWorker);
        mHanded := mHanded + [mWorker];
      end
      else
      begin
        // Ein Aufrufer wartet noch auf FDone: Erst wenn er aufgibt, darf die Liste den Arbeiter freigeben.
        mWorker.FHandOver := True;
      end;
    end;
  finally
    FLock.Leave;
  end;
  for mWorker in mHanded do
  begin
    TAtlasOverdueThreads.Adopt(mWorker, AModule);
  end;
  Result := Length(mHanded);
end;

class function TAtlasTimeLimit.BusyCount: Integer;
begin
  FLock.Enter;
  try
    Result := FAll.Count - FIdle.Count;
  finally
    FLock.Leave;
  end;
end;

class function TAtlasTimeLimit.WaitIdle(AMs: Cardinal): Boolean;
var
  mWatch: TStopwatch;
  mLeft: Int64;
begin
  if (FLock = nil) or (FReleased = nil) then
  begin
    Exit(True);
  end;
  mWatch := TStopwatch.StartNew;
  Result := BusyCount = 0;
  while not Result do
  begin
    mLeft := Int64(AMs) - mWatch.ElapsedMilliseconds;
    if mLeft <= 0 then
    begin
      Exit;
    end;
    // Auto-Reset: Ein Release zwischen Prüfung und Warten bleibt gesetzt und weckt sofort.
    FReleased.WaitFor(Cardinal(mLeft));
    Result := BusyCount = 0;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Plugin.Diagnostics.TimeLimit', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
