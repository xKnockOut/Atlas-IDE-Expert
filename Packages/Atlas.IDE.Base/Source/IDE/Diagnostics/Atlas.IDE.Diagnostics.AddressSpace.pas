unit Atlas.IDE.Diagnostics.AddressSpace;

// Adressraum der IDE im Protokoll (atlas.log): Zu Beginn und am Ende jedes
// Gruppenlaufs schreibt Atlas eine Zeile mit belegtem und gesamtem
// Adressraum sowie dem größten freien Block. Die 32-Bit-IDE hat höchstens
// 4 GB; läuft der Adressraum beim Bauen voll, meldet dcc keinen
// Speicherfehler, sondern wechselnde interne Fehler (F2084 AV, GPF, URW),
// und Atlas selbst scheitert mit EOutOfMemory oder EThread. Die Zeilen
// zeigen, ob es daran liegt, ohne dass jemand während des Builds messen muss.
// Die Messung liest nur (GlobalMemoryStatusEx, VirtualQuery) und dauert
// wenige Millisekunden. Nur im Hauptthread.

interface

uses
  Atlas.Core.Build.Events;

type
  TAtlasAddressSpace = record
  public
    UsedMb: Int64;
    TotalMb: Int64;
    LargestFreeMb: Int64;
    /// <summary>Adressraum des eigenen Prozesses; alle Werte 0, wenn die Abfrage scheitert.</summary>
    class function Measure: TAtlasAddressSpace; static;
    /// <summary>„used 2900 of 4096 MB, largest free block 120 MB“.</summary>
    function Text: string;
  end;

  /// <summary>Schreibt den Adressraum zu Beginn und am Ende jedes Gruppenlaufs ins Protokoll.</summary>
  TAtlasAddressSpaceLog = class(TAtlasCompileParticipant)
  public
    procedure GroupStarted(AKind: TAtlasCompileKind); override;
    procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); override;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard;

const
  cMb = 1024 * 1024;

{ TAtlasAddressSpace }

class function TAtlasAddressSpace.Measure: TAtlasAddressSpace;
var
  mStatus: TMemoryStatusEx;
  mSystem: TSystemInfo;
  mInfo: TMemoryBasicInformation;
  mAddress, mEnd: NativeUInt;
  mLargest: NativeUInt;
begin
  Result := Default(TAtlasAddressSpace);
  FillChar(mStatus, SizeOf(mStatus), 0);
  mStatus.dwLength := SizeOf(mStatus);
  if not GlobalMemoryStatusEx(mStatus) then
  begin
    Exit;
  end;
  Result.TotalMb := Int64(mStatus.ullTotalVirtual div cMb);
  Result.UsedMb := Int64((mStatus.ullTotalVirtual - mStatus.ullAvailVirtual) div cMb);
  GetSystemInfo(mSystem);
  mAddress := NativeUInt(mSystem.lpMinimumApplicationAddress);
  mEnd := NativeUInt(mSystem.lpMaximumApplicationAddress);
  mLargest := 0;
  while (mAddress < mEnd) and (VirtualQuery(Pointer(mAddress), mInfo, SizeOf(mInfo)) = SizeOf(mInfo)) do
  begin
    if (mInfo.State = MEM_FREE) and (mInfo.RegionSize > mLargest) then
    begin
      mLargest := mInfo.RegionSize;
    end;
    if mInfo.RegionSize = 0 then
    begin
      Break;
    end;
    mAddress := NativeUInt(mInfo.BaseAddress) + mInfo.RegionSize;
  end;
  Result.LargestFreeMb := Int64(mLargest div cMb);
end;

function TAtlasAddressSpace.Text: string;
begin
  Result := Format('used %d of %d MB, largest free block %d MB', [UsedMb, TotalMb, LargestFreeMb]);
end;

{ TAtlasAddressSpaceLog }

procedure TAtlasAddressSpaceLog.GroupStarted(AKind: TAtlasCompileKind);
begin
  TAtlasGuard.Log('Address space before build: ' + TAtlasAddressSpace.Measure.Text);
end;

procedure TAtlasAddressSpaceLog.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
  TAtlasGuard.Log('Address space after build: ' + TAtlasAddressSpace.Measure.Text);
end;

end.
