unit Atlas.IDE.Debug.MemoryCounters;

// Speicherwerte eines fremden Prozesses für den Speicherverlauf (#858), dünner
// Adapter auf Windows: privater Speicher und Arbeitssatz
// (GetProcessMemoryInfo), Handles (GetProcessHandleCount), GDI- und
// USER-Objekte (GetGuiResources). Geöffnet wird mit
// PROCESS_QUERY_INFORMATION und PROCESS_VM_READ (verlangt GetProcessMemoryInfo
// vor Windows 8.1), sonst mit PROCESS_QUERY_LIMITED_INFORMATION; Atlas liest
// nichts aus dem Speicher des Prozesses. Jeder Aufruf dauert wenige Mikrosekunden,
// deshalb misst der Zeitgeber im Hauptthread.
// Grenze: Die IDE ist ein 32-Bit-Prozess. Werte über 4 GB eines 64-Bit-Programms
// liefert Windows ihr gekappt.

interface

uses
  Winapi.Windows,
  Atlas.Core.Debug.MemoryTimeline;

type
  TAtlasIdeMemoryCounters = class
  private
    FProcess: THandle;
    FProcessId: Cardinal;
    FLastError: Cardinal;
  public
    destructor Destroy; override;
    /// <summary>Prozess AProcessId öffnen (ein offener wird vorher geschlossen); False, wenn Windows ihn nicht
    /// herausgibt (LastError nennt den Grund).</summary>
    function Open(AProcessId: Cardinal): Boolean;
    procedure Close;
    /// <summary>Aktuelle Werte; False, wenn kein Prozess offen ist oder er schon beendet ist.</summary>
    function Read(out AValues: TAtlasMemoryValues): Boolean;
    function IsOpen: Boolean;
    property ProcessId: Cardinal read FProcessId;
    property LastError: Cardinal read FLastError;
  end;

implementation

const
  // Fehlen in Delphis Winapi.Windows bzw. Winapi.PsAPI nicht überall in derselben Form; selbst deklariert.
  cProcessQueryLimitedInformation = $1000;
  cGrGdiObjects = 0;
  cGrUserObjects = 1;

type
  /// <summary>PROCESS_MEMORY_COUNTERS_EX: PrivateUsage gibt es nur in der erweiterten Form.</summary>
  TProcessMemoryCountersEx = record
    Cb: DWORD;
    PageFaultCount: DWORD;
    PeakWorkingSetSize: SIZE_T;
    WorkingSetSize: SIZE_T;
    QuotaPeakPagedPoolUsage: SIZE_T;
    QuotaPagedPoolUsage: SIZE_T;
    QuotaPeakNonPagedPoolUsage: SIZE_T;
    QuotaNonPagedPoolUsage: SIZE_T;
    PagefileUsage: SIZE_T;
    PeakPagefileUsage: SIZE_T;
    PrivateUsage: SIZE_T;
  end;

function AtlasGetProcessMemoryInfo(AProcess: THandle; var ACounters: TProcessMemoryCountersEx;
  ASize: DWORD): BOOL; stdcall; external kernel32 name 'K32GetProcessMemoryInfo';

function AtlasGetProcessHandleCount(AProcess: THandle; var ACount: DWORD): BOOL; stdcall;
  external kernel32 name 'GetProcessHandleCount';

function AtlasGetGuiResources(AProcess: THandle; AFlags: DWORD): DWORD; stdcall;
  external user32 name 'GetGuiResources';

{ TAtlasIdeMemoryCounters }

destructor TAtlasIdeMemoryCounters.Destroy;
begin
  Close;
  inherited Destroy;
end;

function TAtlasIdeMemoryCounters.Open(AProcessId: Cardinal): Boolean;
begin
  Close;
  FLastError := 0;
  FProcess := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, AProcessId);
  if FProcess = 0 then
  begin
    FProcess := OpenProcess(cProcessQueryLimitedInformation, False, AProcessId);
  end;
  if FProcess = 0 then
  begin
    FLastError := GetLastError;
    Exit(False);
  end;
  FProcessId := AProcessId;
  Result := True;
end;

procedure TAtlasIdeMemoryCounters.Close;
begin
  if FProcess <> 0 then
  begin
    CloseHandle(FProcess);
  end;
  FProcess := 0;
  FProcessId := 0;
end;

function TAtlasIdeMemoryCounters.IsOpen: Boolean;
begin
  Result := FProcess <> 0;
end;

function TAtlasIdeMemoryCounters.Read(out AValues: TAtlasMemoryValues): Boolean;
var
  mCounters: TProcessMemoryCountersEx;
  mHandles: DWORD;
  mExit: DWORD;
begin
  AValues := Default(TAtlasMemoryValues);
  if FProcess = 0 then
  begin
    Exit(False);
  end;
  // Beendet: Die Werte eines toten Prozesses wären 0 und verfälschten den Verlauf.
  if GetExitCodeProcess(FProcess, mExit) and (mExit <> STILL_ACTIVE) then
  begin
    Exit(False);
  end;
  mCounters := Default(TProcessMemoryCountersEx);
  mCounters.Cb := SizeOf(mCounters);
  if not AtlasGetProcessMemoryInfo(FProcess, mCounters, SizeOf(mCounters)) then
  begin
    FLastError := GetLastError;
    Exit(False);
  end;
  AValues[TAtlasMemorySeries.PrivateBytes] := mCounters.PrivateUsage;
  AValues[TAtlasMemorySeries.WorkingSet] := mCounters.WorkingSetSize;
  mHandles := 0;
  if AtlasGetProcessHandleCount(FProcess, mHandles) then
  begin
    AValues[TAtlasMemorySeries.Handles] := mHandles;
  end;
  AValues[TAtlasMemorySeries.GdiObjects] := AtlasGetGuiResources(FProcess, cGrGdiObjects);
  AValues[TAtlasMemorySeries.UserObjects] := AtlasGetGuiResources(FProcess, cGrUserObjects);
  Result := True;
end;

end.
