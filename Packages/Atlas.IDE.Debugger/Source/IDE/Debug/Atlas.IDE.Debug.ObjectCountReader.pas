unit Atlas.IDE.Debug.ObjectCountReader;

// Speicher des debuggten Programms für die Objektzählung (#858, experimentell), dünner Adapter auf Windows:
// Bereiche über VirtualQueryEx, Inhalt über ReadProcessMemory, geöffnet mit PROCESS_QUERY_INFORMATION und
// PROCESS_VM_READ. Gelesen wird nur, nichts geschrieben.
// Eine 32-Bit-IDE erreicht den Speicher eines 64-Bit-Programms oberhalb von 4 GB nicht über diese Aufrufe; dann
// nimmt der Adapter die 64-Bit-Fassungen NtWow64QueryVirtualMemory64 und NtWow64ReadVirtualMemory64 aus der
// ntdll der WOW64-Schicht. Fehlen sie, meldet Open den Grund.

interface

uses
  Atlas.Core.Debug.ObjectCount;

type
  TAtlasIdeProcessMemory = class(TInterfacedObject, IAtlasProcessMemory)
  private
    FProcess: THandle;
    FPointerSize: Integer;
    /// <summary>64-Bit-Programm aus der 32-Bit-IDE: über die NtWow64-Aufrufe.</summary>
    FWide: Boolean;
    function NarrowRegions: TArray<TAtlasMemoryRegion>;
    function WideRegions: TArray<TAtlasMemoryRegion>;
  public
    destructor Destroy; override;
    /// <summary>Prozess APid zum Lesen öffnen; False mit AError (Text von Windows), wenn es nicht geht.</summary>
    class function Open(APid: Cardinal; out AMemory: IAtlasProcessMemory; out AError: string): Boolean; static;
    function PointerSize: Integer;
    function Regions: TArray<TAtlasMemoryRegion>;
    function Read(AAddress: UInt64; var ABuffer; ASize: Integer): Integer;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Generics.Collections;

type
  /// <summary>MEMORY_BASIC_INFORMATION in der Breite der IDE (Typ heißt in Winapi.Windows je Version anders).
  /// </summary>
  TRegionInfo = record
    BaseAddress: NativeUInt;
    AllocationBase: NativeUInt;
    AllocationProtect: DWORD;
    RegionSize: NativeUInt;
    State: DWORD;
    Protect: DWORD;
    Kind: DWORD;
  end;

  /// <summary>MEMORY_BASIC_INFORMATION64 für NtWow64QueryVirtualMemory64.</summary>
  TRegionInfo64 = record
    BaseAddress: UInt64;
    AllocationBase: UInt64;
    AllocationProtect: DWORD;
    Alignment1: DWORD;
    RegionSize: UInt64;
    State: DWORD;
    Protect: DWORD;
    Kind: DWORD;
    Alignment2: DWORD;
  end;

  TNtWow64QueryVirtualMemory64 = function(AProcess: THandle; AAddress: UInt64; AInfoClass: DWORD;
    var AInfo: TRegionInfo64; ALength: UInt64; AReturned: PUInt64): Integer; stdcall;
  TNtWow64ReadVirtualMemory64 = function(AProcess: THandle; AAddress: UInt64; ABuffer: Pointer; ASize: UInt64;
    ARead: PUInt64): Integer; stdcall;

const
  cPointerSize32 = 4;
  cPointerSize64 = 8;
  cFirstAddress = $10000;
  cLimit32 = UInt64($FFFF0000);
  cLimit64 = UInt64($7FFFFFFF0000);
  cReadable = PAGE_READWRITE or PAGE_EXECUTE_READWRITE;

var
  GNtQuery: TNtWow64QueryVirtualMemory64;
  GNtRead: TNtWow64ReadVirtualMemory64;

function AtlasVirtualQueryEx(AProcess: THandle; AAddress: Pointer; var AInfo: TRegionInfo;
  ALength: NativeUInt): NativeUInt; stdcall; external kernel32 name 'VirtualQueryEx';

function AtlasIsWow64Process(AProcess: THandle; var AWow64: BOOL): BOOL; stdcall;
  external kernel32 name 'IsWow64Process';

function IsWow64(AProcess: THandle): Boolean;
var
  mWow64: BOOL;
begin
  mWow64 := False;
  Result := AtlasIsWow64Process(AProcess, mWow64) and mWow64;
end;

/// <summary>NtWow64-Aufrufe einmal suchen; False, wenn die ntdll sie nicht hat.</summary>
function LoadWideCalls: Boolean;
var
  mNtDll: HMODULE;
begin
  if not Assigned(GNtQuery) then
  begin
    mNtDll := GetModuleHandle('ntdll.dll');
    if mNtDll <> 0 then
    begin
      @GNtQuery := GetProcAddress(mNtDll, 'NtWow64QueryVirtualMemory64');
      @GNtRead := GetProcAddress(mNtDll, 'NtWow64ReadVirtualMemory64');
    end;
  end;
  Result := Assigned(GNtQuery) and Assigned(GNtRead);
end;

/// <summary>Art eines Bereichs; False, wenn er nicht gelesen werden soll.</summary>
function KindOf(AState, AProtect, AType: DWORD; out AKind: TAtlasMemoryRegionKind): Boolean;
begin
  AKind := TAtlasMemoryRegionKind.Data;
  Result := (AState = MEM_COMMIT) and (AProtect and (PAGE_GUARD or PAGE_NOACCESS) = 0);
  if not Result then
  begin
    Exit;
  end;
  if AType = MEM_IMAGE then
  begin
    AKind := TAtlasMemoryRegionKind.Image;
    Exit;
  end;
  Result := (AType = MEM_PRIVATE) and (AProtect and cReadable <> 0);
end;

{ TAtlasIdeProcessMemory }

class function TAtlasIdeProcessMemory.Open(APid: Cardinal; out AMemory: IAtlasProcessMemory;
  out AError: string): Boolean;
var
  mReader: TAtlasIdeProcessMemory;
  mProcess: THandle;
begin
  AMemory := nil;
  AError := '';
  mProcess := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, APid);
  if mProcess = 0 then
  begin
    AError := SysErrorMessage(GetLastError);
    Exit(False);
  end;
  mReader := TAtlasIdeProcessMemory.Create;
  AMemory := mReader;
  mReader.FProcess := mProcess;
  mReader.FPointerSize := SizeOf(Pointer);
  if IsWow64(mProcess) then
  begin
    mReader.FPointerSize := cPointerSize32;
  end
  else if (SizeOf(Pointer) = cPointerSize32) and IsWow64(GetCurrentProcess) then
  begin
    // 32-Bit-IDE auf 64-Bit-Windows, Programm ohne WOW64: ein 64-Bit-Programm.
    mReader.FPointerSize := cPointerSize64;
    mReader.FWide := True;
    if not LoadWideCalls then
    begin
      AError := SysErrorMessage(ERROR_PROC_NOT_FOUND);
      AMemory := nil;
      Exit(False);
    end;
  end;
  Result := True;
end;

destructor TAtlasIdeProcessMemory.Destroy;
begin
  if FProcess <> 0 then
  begin
    CloseHandle(FProcess);
  end;
  inherited Destroy;
end;

function TAtlasIdeProcessMemory.PointerSize: Integer;
begin
  Result := FPointerSize;
end;

function TAtlasIdeProcessMemory.Regions: TArray<TAtlasMemoryRegion>;
begin
  if FWide then
  begin
    Result := WideRegions;
  end
  else
  begin
    Result := NarrowRegions;
  end;
end;

function TAtlasIdeProcessMemory.NarrowRegions: TArray<TAtlasMemoryRegion>;
var
  mList: TList<TAtlasMemoryRegion>;
  mInfo: TRegionInfo;
  mAddress: UInt64;
  mLimit: UInt64;
  mKind: TAtlasMemoryRegionKind;
begin
  mLimit := cLimit64;
  if FPointerSize = cPointerSize32 then
  begin
    mLimit := cLimit32;
  end;
  mList := TList<TAtlasMemoryRegion>.Create;
  try
    mAddress := cFirstAddress;
    while (mAddress < mLimit) and
      (AtlasVirtualQueryEx(FProcess, Pointer(NativeUInt(mAddress)), mInfo, SizeOf(mInfo)) = SizeOf(mInfo)) and
      (mInfo.RegionSize > 0) do
    begin
      if KindOf(mInfo.State, mInfo.Protect, mInfo.Kind, mKind) then
      begin
        mList.Add(TAtlasMemoryRegion.Make(mInfo.BaseAddress, mInfo.RegionSize, mKind));
      end;
      mAddress := UInt64(mInfo.BaseAddress) + UInt64(mInfo.RegionSize);
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TAtlasIdeProcessMemory.WideRegions: TArray<TAtlasMemoryRegion>;
var
  mList: TList<TAtlasMemoryRegion>;
  mInfo: TRegionInfo64;
  mAddress: UInt64;
  mKind: TAtlasMemoryRegionKind;
begin
  mList := TList<TAtlasMemoryRegion>.Create;
  try
    mAddress := cFirstAddress;
    mInfo := Default(TRegionInfo64);
    // Informationsklasse 0: MemoryBasicInformation; Ergebnis 0 = STATUS_SUCCESS.
    while (mAddress < cLimit64) and (GNtQuery(FProcess, mAddress, 0, mInfo, SizeOf(mInfo), nil) = 0) and
      (mInfo.RegionSize > 0) do
    begin
      if KindOf(mInfo.State, mInfo.Protect, mInfo.Kind, mKind) then
      begin
        mList.Add(TAtlasMemoryRegion.Make(mInfo.BaseAddress, mInfo.RegionSize, mKind));
      end;
      mAddress := mInfo.BaseAddress + mInfo.RegionSize;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TAtlasIdeProcessMemory.Read(AAddress: UInt64; var ABuffer; ASize: Integer): Integer;
var
  mRead: SIZE_T;
  mWideRead: UInt64;
begin
  Result := 0;
  if ASize <= 0 then
  begin
    Exit;
  end;
  if FWide then
  begin
    mWideRead := 0;
    if GNtRead(FProcess, AAddress, @ABuffer, UInt64(ASize), @mWideRead) = 0 then
    begin
      Result := Integer(mWideRead);
    end;
    Exit;
  end;
  {$IFDEF CPU32BITS}
  // Ohne die NtWow64-Aufrufe reicht die 32-Bit-IDE nur bis 4 GB.
  if AAddress > $FFFFFFFF then
  begin
    Exit;
  end;
  {$ENDIF}
  mRead := 0;
  // Ein Teil eines Bereichs kann inzwischen freigegeben sein: Dann zählt, was gelesen wurde.
  if ReadProcessMemory(FProcess, Pointer(NativeUInt(AAddress)), @ABuffer, SIZE_T(ASize), mRead) or (mRead > 0) then
  begin
    Result := Integer(mRead);
  end;
end;

end.
