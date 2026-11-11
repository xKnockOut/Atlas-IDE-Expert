unit Atlas.Core.Diagnostics.WorkerSlot;

// Arbeiter-Threads eines Objekts und was mit überfälligen geschieht (Code-
// Review T-101). Vorher setzten acht Kopien bei überschrittener Zeitgrenze
// FreeOnTerminate und vergaßen den Thread: Endete er zwischen der Prüfung auf
// Finished und dem Setzen, blieb das Objekt liegen, und wurde das Package
// seines Codes bei laufender IDE entladen, lief er in nicht mehr geladenem
// Code weiter.
// - TAtlasWorkerSlot hält die Threads eines Objekts (FreeOnTerminate aus),
//   gibt beendete frei und wartet in Stop bis zur Zeitgrenze. Wer dann noch
//   läuft, geht an TAtlasOverdueThreads, zusammen mit dem Package seines
//   Codes (im Package: HInstance).
// - TAtlasOverdueThreads gibt überfällige Threads frei, sobald sie enden.
//   Wird ein Package entladen (AddModuleUnloadProc, sein Code ist dann noch
//   geladen), wartet es auf dessen überfällige Threads noch bis
//   cUnloadGraceMs; läuft dann noch einer, hält TAtlasUnloadSafety das
//   Package im Speicher und bittet um einen Neustart.
// Gewartet wird auf Finished wie in TAtlasShutdown.WaitForThreads.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections;

type
  TAtlasOverdueThreads = class
  public const
    /// <summary>Nachwarten beim Entladen eines Packages mit überfälligen Threads.</summary>
    cUnloadGraceMs = 3000;
  private type
    TEntry = record
      Thread: TThread;
      Module: HMODULE;
    end;
  private class var
    FLock: TCriticalSection;
    FEntries: TList<TEntry>;
    /// <summary>Beendete Threads (nur von AModule, 0 = alle) aus der Liste nehmen und freigeben.</summary>
    class procedure Prune(AModule: HMODULE); static;
    class function ThreadsOf(AModule: HMODULE): TArray<TThread>; static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>AThread (FreeOnTerminate aus) hat seine Zeitgrenze überschritten; sein Code liegt in AModule.
    /// Die Liste gibt ihn frei, sobald er endet.</summary>
    class procedure Adopt(AThread: TThread; AModule: HMODULE); static;
    /// <summary>Überfällige Threads von AModule, die noch laufen.</summary>
    class function Pending(AModule: HMODULE): Integer; static;
    /// <summary>Bis AMs auf die überfälligen Threads von AModule warten und beendete freigeben; True, wenn keiner
    /// mehr läuft. Sonst ist AModule als unsicher gekennzeichnet (TAtlasUnloadSafety).</summary>
    class function Settle(AModule: HMODULE; AMs: Cardinal): Boolean; static;
  end;

  /// <summary>Hält die Arbeiter-Threads eines Objekts; Stop wartet bis zur Zeitgrenze und übergibt überfällige an
  /// TAtlasOverdueThreads.</summary>
  TAtlasWorkerSlot = class
  public const
    /// <summary>Für Stop: ohne Zeitgrenze warten (Threads mit eigener Zeitgrenze, die Objekte des Aufrufers
    /// roh halten).</summary>
    cWaitForever = High(Cardinal);
  private
    FModule: HMODULE;
    FThreads: TList<TThread>;
  public
    /// <summary>AModule: Package, in dem der Code der Threads liegt (im Package HInstance).</summary>
    constructor Create(AModule: HMODULE);
    /// <summary>Wie Stop(TAtlasShutdown.cStopMs).</summary>
    destructor Destroy; override;
    /// <summary>AThread (angehalten erzeugt) übernehmen und starten; gibt vorher beendete frei.</summary>
    procedure Start(AThread: TThread);
    /// <summary>Schon laufenden AThread (FreeOnTerminate aus) übernehmen, etwa einen abgelösten Vorgänger; nil wird
    /// ignoriert.</summary>
    procedure Keep(AThread: TThread);
    /// <summary>Läuft noch ein Thread?</summary>
    function Busy: Boolean;
    /// <summary>Threads, auch beendete, die noch nicht freigegeben sind.</summary>
    function Count: Integer;
    /// <summary>Beendete Threads freigeben, ohne zu warten.</summary>
    procedure Prune;
    /// <summary>Bis AWaitMs auf alle warten und sie freigeben; True, wenn alle beendet waren. Überfällige gehen an
    /// TAtlasOverdueThreads; der Slot ist danach leer.</summary>
    function Stop(AWaitMs: Cardinal): Boolean;
    /// <summary>AWait: Stop(TAtlasShutdown.cStopMs), sonst Prune.</summary>
    procedure Release(AWait: Boolean);
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Diagnostics.UnloadSafety,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit: der Grund erscheint im Hinweis von TAtlasUnloadSafety.</summary>
  TWorkerSlotText = (OverdueThreads);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TWorkerSlotText] of string = (
    ('%d Arbeiter-Thread(s) über ihrer Zeitgrenze'),
    ('%d worker thread(s) past their time limit'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TWorkerSlotText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

/// <summary>Beim Entladen jedes Packages (AddModuleUnloadProc), solange sein Code noch geladen ist.</summary>
procedure AtlasOverdueModuleUnload(AInstance: NativeInt);
begin
  if TAtlasOverdueThreads.Pending(HMODULE(AInstance)) > 0 then
  begin
    TAtlasOverdueThreads.Settle(HMODULE(AInstance), TAtlasOverdueThreads.cUnloadGraceMs);
  end;
end;

{ TAtlasOverdueThreads }

class constructor TAtlasOverdueThreads.Create;
begin
  FLock := TCriticalSection.Create;
  FEntries := TList<TEntry>.Create;
  // Platz für die üblichen wenigen Einträge gleich anlegen: Wüchse die Liste erst beim ersten Adopt, bliebe der
  // Speicher bis zum Entladen belegt und der Leckmonitor der Tests zählte ihn dem ersten Test zu.
  FEntries.Capacity := 4;
  AddModuleUnloadProc(AtlasOverdueModuleUnload);
end;

class destructor TAtlasOverdueThreads.Destroy;
begin
  RemoveModuleUnloadProc(AtlasOverdueModuleUnload);
  Prune(0);
  // Was jetzt noch läuft, hat beim Entladen von Base AtlasOverdueModuleUnload schon festgehalten; die Objekte
  // bleiben bewusst liegen (ein Freigeben beendet den Thread nicht).
  FreeAndNil(FEntries);
  FreeAndNil(FLock);
end;

class procedure TAtlasOverdueThreads.Adopt(AThread: TThread; AModule: HMODULE);
var
  mEntry: TEntry;
begin
  if AThread = nil then
  begin
    Exit;
  end;
  if FLock = nil then
  begin
    // Nach dem Abbau: letzter Ausweg wie früher.
    AThread.FreeOnTerminate := True;
    Exit;
  end;
  mEntry.Thread := AThread;
  mEntry.Module := AModule;
  FLock.Enter;
  try
    FEntries.Add(mEntry);
  finally
    FLock.Leave;
  end;
  TAtlasGuard.Log(Format('Atlas: worker thread %d exceeded its time limit, freed once it ends',
    [AThread.ThreadID]));
  Prune(0);
end;

class procedure TAtlasOverdueThreads.Prune(AModule: HMODULE);
var
  mDone: TArray<TThread>;
  mThread: TThread;
  mIndex: Integer;
begin
  if FLock = nil then
  begin
    Exit;
  end;
  mDone := nil;
  FLock.Enter;
  try
    for mIndex := FEntries.Count - 1 downto 0 do
    begin
      if ((AModule = 0) or (FEntries[mIndex].Module = AModule)) and FEntries[mIndex].Thread.Finished then
      begin
        mDone := mDone + [FEntries[mIndex].Thread];
        FEntries.Delete(mIndex);
      end;
    end;
  finally
    FLock.Leave;
  end;
  for mThread in mDone do
  begin
    mThread.Free;
  end;
end;

class function TAtlasOverdueThreads.ThreadsOf(AModule: HMODULE): TArray<TThread>;
var
  mEntry: TEntry;
begin
  Result := nil;
  if FLock = nil then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    for mEntry in FEntries do
    begin
      if mEntry.Module = AModule then
      begin
        Result := Result + [mEntry.Thread];
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

class function TAtlasOverdueThreads.Pending(AModule: HMODULE): Integer;
begin
  Prune(AModule);
  Result := Length(ThreadsOf(AModule));
end;

class function TAtlasOverdueThreads.Settle(AModule: HMODULE; AMs: Cardinal): Boolean;
var
  mThreads: TArray<TThread>;
begin
  mThreads := ThreadsOf(AModule);
  Result := TAtlasShutdown.WaitForThreads(mThreads, AMs);
  Prune(AModule);
  if not Result then
  begin
    TAtlasUnloadSafety.MarkUnsafe(AModule, Format(UiText(TWorkerSlotText.OverdueThreads),
      [Length(ThreadsOf(AModule))]));
  end;
end;

{ TAtlasWorkerSlot }

constructor TAtlasWorkerSlot.Create(AModule: HMODULE);
begin
  inherited Create;
  FModule := AModule;
  FThreads := TList<TThread>.Create;
end;

destructor TAtlasWorkerSlot.Destroy;
begin
  if FThreads <> nil then
  begin
    Stop(TAtlasShutdown.cStopMs);
  end;
  FThreads.Free;
  inherited;
end;

procedure TAtlasWorkerSlot.Start(AThread: TThread);
begin
  Prune;
  AThread.FreeOnTerminate := False;
  FThreads.Add(AThread);
  AThread.Start;
end;

procedure TAtlasWorkerSlot.Keep(AThread: TThread);
begin
  if AThread <> nil then
  begin
    AThread.FreeOnTerminate := False;
    FThreads.Add(AThread);
  end;
end;

function TAtlasWorkerSlot.Busy: Boolean;
var
  mThread: TThread;
begin
  Result := False;
  for mThread in FThreads do
  begin
    if not mThread.Finished then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasWorkerSlot.Count: Integer;
begin
  Result := FThreads.Count;
end;

procedure TAtlasWorkerSlot.Prune;
var
  mIndex: Integer;
begin
  for mIndex := FThreads.Count - 1 downto 0 do
  begin
    if FThreads[mIndex].Finished then
    begin
      FThreads[mIndex].Free;
      FThreads.Delete(mIndex);
    end;
  end;
end;

function TAtlasWorkerSlot.Stop(AWaitMs: Cardinal): Boolean;
var
  mThreads: TArray<TThread>;
  mThread: TThread;
begin
  // Kein Terminate: Ein Thread, der noch nicht angelaufen ist, übersprünge sonst Execute ganz. Abbrechen ist
  // Sache des Aufrufers (Abbruchsignal, Transport).
  mThreads := FThreads.ToArray;
  FThreads.Clear;
  Result := TAtlasShutdown.WaitForThreads(mThreads, AWaitMs);
  for mThread in mThreads do
  begin
    if mThread.Finished then
    begin
      mThread.Free;
    end
    else
    begin
      TAtlasOverdueThreads.Adopt(mThread, FModule);
    end;
  end;
end;

procedure TAtlasWorkerSlot.Release(AWait: Boolean);
begin
  if AWait then
  begin
    Stop(TAtlasShutdown.cStopMs);
  end
  else
  begin
    Prune;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Diagnostics.WorkerSlot', cTexts[TAtlasLanguage.German],
    cTexts[TAtlasLanguage.English]);

end.
