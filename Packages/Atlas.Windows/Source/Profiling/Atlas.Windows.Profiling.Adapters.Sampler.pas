unit Atlas.Windows.Profiling.Adapters.Sampler;

// Stichproben-Profiler (#2057), Prober unter Windows (Vertrag Atlas.Common.Profiling.Contract). Ein eigener Thread
// geht alle intervalMs die Threads des Zielprogramms durch: Hat ein Thread seit der letzten Probe gerechnet
// (QueryThreadCycleTime), wird er kurz angehalten (SuspendThread), sein Kontext gelesen ((Wow64)GetThreadContext)
// und der Aufrufstapel mit StackWalk64 abgelaufen; dann läuft er weiter. Kein Debugger nötig, die IDE darf das
// Programm gleichzeitig debuggen. Nur ein 64-Bit-Prozess kann so 32- und 64-Bit-Programme lesen, deshalb misst der
// Server. Gemessen 13.11.2026: 0,2 bis 0,5 ms je Probe, bei 10 ms Abstand +1,5 % (Win64) bzw. +3 % (Win32).
// Gleiche Stapel fasst TAtlasRawStacks zusammen; aufgelöst wird nach dem Lauf (Atlas.Common.Lsp.Profiler).

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Diagnostics,
  Atlas.Common.Profiling.Contract,
  Atlas.Common.Profiling.Sampling;

type
  TAtlasWindowsProfileSampler = class(TInterfacedObject, IAtlasProfileSampler)
  private type
    TSampledThread = class
    public
      Id: DWORD;
      Handle: THandle;
      LastCycles: UInt64;
      destructor Destroy; override;
    end;

    TWorker = class(TThread)
    private
      FOwner: TAtlasWindowsProfileSampler;
    protected
      procedure Execute; override;
    public
      constructor Create(AOwner: TAtlasWindowsProfileSampler);
    end;
  private
    FProcess: THandle;
    FProcessId: DWORD;
    FIntervalMs: Integer;
    FWow64: Boolean;
    FModules: TArray<TAtlasSampleModule>;
    FMainModule: Integer;
    FThreads: TObjectDictionary<DWORD, TSampledThread>;
    FStacks: TAtlasRawStacks;
    FContext: Pointer;
    FWorker: TWorker;
    FWatch: TStopwatch;
    FSamples: Integer;
    FEnded: Integer;
    FLastRefresh: Int64;
    procedure LoadModules;
    procedure RefreshThreads;
    function Walk(AThread: TSampledThread; out AFrames: TArray<UInt64>): Boolean;
    procedure SampleThread(AThread: TSampledThread);
    /// <summary>Eine Runde über alle Threads; False, sobald das Programm beendet ist.</summary>
    function Round: Boolean;
    procedure Release;
  public
    constructor Create;
    destructor Destroy; override;
    function Start(AProcessId: Cardinal; AIntervalMs: Integer; out AError: string): Boolean;
    function Stop: TAtlasSampleRun;
    function Running: Boolean;
    function Samples: Integer;
    function MainFileName: string;
  end;

implementation

uses
  System.Math,
  Winapi.TlHelp32,
  Winapi.PsAPI,
  Winapi.MMSystem;

const
  cMachineI386 = $014C;
  cMachineAmd64 = $8664;
  cWow64ContextFull = $00010007;
  cAmd64ContextFull = $0010000B;
  cListModulesAll = 3;
  cAddrModeFlat = 3;
  cMaxDepth = 64;
  cMaxModules = 1024;
  /// <summary>Kontext unter Win64 muss auf 16 Byte ausgerichtet sein.</summary>
  cContextAlign = 16;
  /// <summary>Threads neu einlesen (neue und beendete) nach so vielen ms.</summary>
  cRefreshMs = 500;
  /// <summary>Weniger Zyklen seit der letzten Probe gelten als ruhend: Ein schlafender Thread, der nur kurz
  /// aufwacht (Sleep(1), Zeitgeber), soll nicht als rechnend zählen.</summary>
  cIdleCycles = 200000;
  // In Winapi.Windows von Delphi fehlen OpenThread und die Zugriffsrechte für Threads.
  cThreadSuspendResume = $0002;
  cThreadGetContext = $0008;
  cThreadQueryInformation = $0040;
  cSuspendFailed = DWORD(-1);

type
  TSamplerAddress64 = record
    Offset: UInt64;
    Segment: Word;
    Mode: DWORD;
  end;

  TSamplerKdHelp64 = record
    Values: array[0..10] of UInt64;
    Reserved: array[0..4] of UInt64;
  end;

  TSamplerStackFrame64 = record
    AddrPC: TSamplerAddress64;
    AddrReturn: TSamplerAddress64;
    AddrFrame: TSamplerAddress64;
    AddrStack: TSamplerAddress64;
    FuncTableEntry: Pointer;
    Params: array[0..3] of UInt64;
    FarCall: BOOL;
    VirtualCall: BOOL;
    Reserved: array[0..2] of UInt64;
    KdHelp: TSamplerKdHelp64;
    AddrBStore: TSamplerAddress64;
  end;

  TSamplerWow64Context = record
    ContextFlags: DWORD;
    Dr: array[0..5] of DWORD;
    FloatSave: array[0..111] of Byte;
    SegGs, SegFs, SegEs, SegDs: DWORD;
    Edi, Esi, Ebx, Edx, Ecx, Eax: DWORD;
    Ebp, Eip, SegCs, EFlags, Esp, SegSs: DWORD;
    ExtendedRegisters: array[0..511] of Byte;
  end;

function SamplerOpenThread(AAccess: DWORD; AInherit: BOOL; AThreadId: DWORD): THandle; stdcall;
  external kernel32 name 'OpenThread';
function SamplerEnumModulesEx(AProcess: THandle; AModules: Pointer; ASize: DWORD; var ANeeded: DWORD;
  AFilter: DWORD): BOOL; stdcall; external 'psapi.dll' name 'EnumProcessModulesEx';
function SamplerQueryThreadCycleTime(AThread: THandle; var ACycles: UInt64): BOOL; stdcall;
  external kernel32 name 'QueryThreadCycleTime';
function SamplerWow64GetThreadContext(AThread: THandle; var AContext: TSamplerWow64Context): BOOL; stdcall;
  external kernel32 name 'Wow64GetThreadContext';
function SamplerIsWow64Process(AProcess: THandle; var AWow64: BOOL): BOOL; stdcall;
  external kernel32 name 'IsWow64Process';
function SamplerSymInitialize(AProcess: THandle; ASearchPath: PWideChar; AInvade: BOOL): BOOL; stdcall;
  external 'dbghelp.dll' name 'SymInitializeW';
function SamplerSymCleanup(AProcess: THandle): BOOL; stdcall; external 'dbghelp.dll' name 'SymCleanup';
function SamplerSymFunctionTableAccess64(AProcess: THandle; AAddrBase: UInt64): Pointer; stdcall;
  external 'dbghelp.dll' name 'SymFunctionTableAccess64';
function SamplerSymGetModuleBase64(AProcess: THandle; AAddress: UInt64): UInt64; stdcall;
  external 'dbghelp.dll' name 'SymGetModuleBase64';
function SamplerStackWalk64(AMachine: DWORD; AProcess, AThread: THandle; var AFrame: TSamplerStackFrame64;
  AContext: Pointer; AReadMemory, AFunctionTable, AModuleBase, ATranslate: Pointer): BOOL; stdcall;
  external 'dbghelp.dll' name 'StackWalk64';

{ TAtlasWindowsProfileSampler.TSampledThread }

destructor TAtlasWindowsProfileSampler.TSampledThread.Destroy;
begin
  if Handle <> 0 then
  begin
    CloseHandle(Handle);
  end;
  inherited;
end;

{ TAtlasWindowsProfileSampler.TWorker }

constructor TAtlasWindowsProfileSampler.TWorker.Create(AOwner: TAtlasWindowsProfileSampler);
begin
  FOwner := AOwner;
  inherited Create(False);
end;

procedure TAtlasWindowsProfileSampler.TWorker.Execute;
begin
  NameThreadForDebugging('Atlas.Profiler');
  timeBeginPeriod(1);
  try
    FOwner.RefreshThreads;
    while (not Terminated) and FOwner.Round do
    begin
      Sleep(FOwner.FIntervalMs);
    end;
  finally
    timeEndPeriod(1);
  end;
end;

{ TAtlasWindowsProfileSampler }

constructor TAtlasWindowsProfileSampler.Create;
begin
  inherited Create;
  FThreads := TObjectDictionary<DWORD, TSampledThread>.Create([doOwnsValues]);
  FStacks := TAtlasRawStacks.Create;
  GetMem(FContext, SizeOf(TContext) + cContextAlign);
  FMainModule := -1;
end;

destructor TAtlasWindowsProfileSampler.Destroy;
begin
  Release;
  FreeMem(FContext);
  FStacks.Free;
  FThreads.Free;
  inherited;
end;

procedure TAtlasWindowsProfileSampler.Release;
begin
  if FWorker <> nil then
  begin
    FWorker.Terminate;
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  FThreads.Clear;
  if FProcess <> 0 then
  begin
    SamplerSymCleanup(FProcess);
    CloseHandle(FProcess);
    FProcess := 0;
  end;
end;

function TAtlasWindowsProfileSampler.Start(AProcessId: Cardinal; AIntervalMs: Integer; out AError: string): Boolean;
var
  mWow64: BOOL;
begin
  AError := '';
  FProcess := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ or SYNCHRONIZE, False, AProcessId);
  if FProcess = 0 then
  begin
    AError := SysErrorMessage(GetLastError);
    Exit(False);
  end;
  FProcessId := AProcessId;
  FIntervalMs := AIntervalMs;
  mWow64 := False;
  FWow64 := SamplerIsWow64Process(FProcess, mWow64) and mWow64;
  LoadModules;
  if FMainModule < 0 then
  begin
    AError := 'EnumProcessModulesEx: ' + SysErrorMessage(GetLastError);
    Release;
    Exit(False);
  end;
  // dbghelp braucht die Module des Ziels für die Abwicklungstabellen unter Win64 (SymFunctionTableAccess64).
  SamplerSymInitialize(FProcess, nil, True);
  FStacks.Clear;
  FSamples := 0;
  FEnded := 0;
  FLastRefresh := 0;
  FWatch := TStopwatch.StartNew;
  FWorker := TWorker.Create(Self);
  Result := True;
end;

function TAtlasWindowsProfileSampler.Stop: TAtlasSampleRun;
begin
  if FWorker <> nil then
  begin
    FWorker.Terminate;
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  Result := Default(TAtlasSampleRun);
  Result.Modules := FModules;
  Result.MainModule := FMainModule;
  Result.Stacks := FStacks.ToArray;
  Result.DurationMs := FWatch.ElapsedMilliseconds;
  Release;
  FStacks.Clear;
  FModules := nil;
  FMainModule := -1;
end;

function TAtlasWindowsProfileSampler.Running: Boolean;
begin
  Result := (FWorker <> nil) and (AtomicCmpExchange(FEnded, 0, 0) = 0);
end;

function TAtlasWindowsProfileSampler.Samples: Integer;
begin
  Result := AtomicCmpExchange(FSamples, 0, 0);
end;

function TAtlasWindowsProfileSampler.MainFileName: string;
begin
  Result := '';
  if (FMainModule >= 0) and (FMainModule <= High(FModules)) then
  begin
    Result := FModules[FMainModule].FileName;
  end;
end;

procedure TAtlasWindowsProfileSampler.LoadModules;
var
  mHandles: array of HMODULE;
  mNeeded: DWORD;
  mIndex: Integer;
  mInfo: TModuleInfo;
  mName: array[0..MAX_PATH] of Char;
begin
  FModules := nil;
  FMainModule := -1;
  SetLength(mHandles, cMaxModules);
  mNeeded := 0;
  if not SamplerEnumModulesEx(FProcess, @mHandles[0], Length(mHandles) * SizeOf(HMODULE), mNeeded,
    cListModulesAll) then
  begin
    Exit;
  end;
  SetLength(FModules, Integer(mNeeded div SizeOf(HMODULE)));
  if Length(FModules) > Length(mHandles) then
  begin
    SetLength(FModules, Length(mHandles));
  end;
  for mIndex := 0 to High(FModules) do
  begin
    FillChar(mInfo, SizeOf(mInfo), 0);
    GetModuleInformation(FProcess, mHandles[mIndex], @mInfo, SizeOf(mInfo));
    FModules[mIndex].Base := UInt64(mInfo.lpBaseOfDll);
    FModules[mIndex].Size := mInfo.SizeOfImage;
    FillChar(mName, SizeOf(mName), 0);
    GetModuleFileNameEx(FProcess, mHandles[mIndex], mName, MAX_PATH);
    FModules[mIndex].FileName := mName;
    if (FMainModule < 0) and SameText(ExtractFileExt(FModules[mIndex].FileName), '.exe') then
    begin
      FMainModule := mIndex;
    end;
  end;
end;

procedure TAtlasWindowsProfileSampler.RefreshThreads;
var
  mSnapshot: THandle;
  mEntry: TThreadEntry32;
  mThread: TSampledThread;
  mSeen: THashSet<DWORD>;
  mId: DWORD;
begin
  mSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if mSnapshot = INVALID_HANDLE_VALUE then
  begin
    Exit;
  end;
  mSeen := THashSet<DWORD>.Create;
  try
    mEntry.dwSize := SizeOf(mEntry);
    if Thread32First(mSnapshot, mEntry) then
      repeat
        if mEntry.th32OwnerProcessID = FProcessId then
        begin
          mSeen.Add(mEntry.th32ThreadID);
          if not FThreads.ContainsKey(mEntry.th32ThreadID) then
          begin
            mThread := TSampledThread.Create;
            mThread.Id := mEntry.th32ThreadID;
            mThread.Handle := SamplerOpenThread(cThreadSuspendResume or cThreadGetContext or
              cThreadQueryInformation, False, mEntry.th32ThreadID);
            SamplerQueryThreadCycleTime(mThread.Handle, mThread.LastCycles);
            FThreads.Add(mThread.Id, mThread);
          end;
        end;
        mEntry.dwSize := SizeOf(mEntry);
      until not Thread32Next(mSnapshot, mEntry);
    for mId in FThreads.Keys.ToArray do
    begin
      if not mSeen.Contains(mId) then
      begin
        FThreads.Remove(mId);
      end;
    end;
  finally
    mSeen.Free;
    CloseHandle(mSnapshot);
  end;
end;

function TAtlasWindowsProfileSampler.Walk(AThread: TSampledThread; out AFrames: TArray<UInt64>): Boolean;
var
  mFrame: TSamplerStackFrame64;
  mWow64Context: TSamplerWow64Context;
  mContext64: PContext;
  mContext: Pointer;
  mMachine: DWORD;
  mCount: Integer;
begin
  AFrames := nil;
  FillChar(mFrame, SizeOf(mFrame), 0);
  if FWow64 then
  begin
    FillChar(mWow64Context, SizeOf(mWow64Context), 0);
    mWow64Context.ContextFlags := cWow64ContextFull;
    if not SamplerWow64GetThreadContext(AThread.Handle, mWow64Context) then
    begin
      Exit(False);
    end;
    mFrame.AddrPC.Offset := mWow64Context.Eip;
    mFrame.AddrFrame.Offset := mWow64Context.Ebp;
    mFrame.AddrStack.Offset := mWow64Context.Esp;
    mContext := @mWow64Context;
    mMachine := cMachineI386;
  end
  else
  begin
    mContext64 := PContext((NativeUInt(FContext) + cContextAlign - 1) and not NativeUInt(cContextAlign - 1));
    FillChar(mContext64^, SizeOf(TContext), 0);
    mContext64^.ContextFlags := cAmd64ContextFull;
    if not GetThreadContext(AThread.Handle, mContext64^) then
    begin
      Exit(False);
    end;
    {$IFDEF CPUX64}
    mFrame.AddrPC.Offset := mContext64^.Rip;
    mFrame.AddrFrame.Offset := mContext64^.Rbp;
    mFrame.AddrStack.Offset := mContext64^.Rsp;
    {$ENDIF}
    mContext := mContext64;
    mMachine := cMachineAmd64;
  end;
  mFrame.AddrPC.Mode := cAddrModeFlat;
  mFrame.AddrFrame.Mode := cAddrModeFlat;
  mFrame.AddrStack.Mode := cAddrModeFlat;
  SetLength(AFrames, cMaxDepth);
  // Der erste Rahmen ist der Befehlszeiger selbst; StackWalk64 liefert ihn als ersten Schritt.
  AFrames[0] := mFrame.AddrPC.Offset;
  mCount := 0;
  while (mCount < cMaxDepth) and SamplerStackWalk64(mMachine, FProcess, AThread.Handle, mFrame, mContext, nil,
    @SamplerSymFunctionTableAccess64, @SamplerSymGetModuleBase64, nil) and (mFrame.AddrPC.Offset <> 0) do
  begin
    // Rücksprungadressen zeigen hinter den Aufruf: eins abziehen, damit Zeile und Routine des Aufrufs gelten.
    AFrames[mCount] := mFrame.AddrPC.Offset - UInt64(Ord(mCount > 0));
    Inc(mCount);
  end;
  SetLength(AFrames, Max(mCount, 1));
  Result := True;
end;

procedure TAtlasWindowsProfileSampler.SampleThread(AThread: TSampledThread);
var
  mCycles: UInt64;
  mFrames: TArray<UInt64>;
  mOk: Boolean;
begin
  mCycles := 0;
  if (AThread.Handle = 0) or not SamplerQueryThreadCycleTime(AThread.Handle, mCycles) then
  begin
    Exit;
  end;
  // Ruhend (wartet, schläft oder steht im Debugger): keine Probe, der Thread wird nicht angehalten.
  if mCycles - AThread.LastCycles < cIdleCycles then
  begin
    AThread.LastCycles := mCycles;
    Exit;
  end;
  AThread.LastCycles := mCycles;
  if SuspendThread(AThread.Handle) = cSuspendFailed then
  begin
    Exit;
  end;
  try
    mOk := Walk(AThread, mFrames);
  finally
    ResumeThread(AThread.Handle);
  end;
  if mOk then
  begin
    FStacks.Add(mFrames);
    AtomicIncrement(FSamples);
  end;
end;

function TAtlasWindowsProfileSampler.Round: Boolean;
var
  mThread: TSampledThread;
begin
  if WaitForSingleObject(FProcess, 0) = WAIT_OBJECT_0 then
  begin
    AtomicExchange(FEnded, 1);
    Exit(False);
  end;
  if FWatch.ElapsedMilliseconds - FLastRefresh >= cRefreshMs then
  begin
    RefreshThreads;
    FLastRefresh := FWatch.ElapsedMilliseconds;
  end;
  for mThread in FThreads.Values do
  begin
    SampleThread(mThread);
  end;
  Result := True;
end;

end.
