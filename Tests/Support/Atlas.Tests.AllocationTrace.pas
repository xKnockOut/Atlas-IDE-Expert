unit Atlas.Tests.AllocationTrace;

// Belegungen eines Tests mit Aufrufstapel nennen. Der Leckmonitor misst nur Bytes; wer ein Leck der ersten
// Benutzung in Atlas.Tests.FirstUse benennen oder an der Ursache beheben will, braucht die Stelle, an der der
// Speicher angelegt wurde. Install hängt sich vor den Speichermanager; zwischen Start und Stop merkt er sich
// jede Belegung mit ihren Rücksprungadressen, eine Freigabe streicht sie wieder. Report nennt, was übrig ist,
// gruppiert nach Stapel, mit Unit und Zeile aus der Map-Datei (TStackTrace).
//
// Wächst ein Block, der vor Start angelegt wurde (Liste, Dictionary, Zwischenspeicher, String), per ReallocMem,
// zählt der Leckmonitor nur den Zuwachs. Die Aufzeichnung kennt die alte Größe nicht; sie merkt sich den Block
// mit seiner neuen Größe und nennt ihn als „vergrößert“. Stapel mit einem Rahmen aus Atlas (Units Atlas.* und
// Shell.*) stehen vorn; Stapel nur aus RTL, VCL und DUnitX (Ergebnisobjekte des Testlaufs) werden nur gezählt.
//
// Die Tabelle liegt in Speicher von VirtualAlloc, außerhalb des Speichermanagers: Sie zählt weder für den
// Leckmonitor noch für den Speicherrest beim Beenden, und die Haken belegen selbst nichts. Ohne Start kostet
// der Haken je Aufruf nur einen Vergleich. Der Leckmonitor startet die Aufzeichnung nur, wenn die Umgebung
// ATLAS_LEAK_TRACE=1 setzt (Stapel holen kostet Zeit).

interface

type
  TAllocationTrace = record
  public
    /// <summary>Haken vor den Speichermanager setzen (einmal, vor dem ersten Test).</summary>
    class procedure Install; static;
    /// <summary>True, wenn die Umgebung ATLAS_LEAK_TRACE=1 setzt.</summary>
    class function Requested: Boolean; static;
    /// <summary>Tabelle leeren und ab jetzt jede Belegung aufzeichnen.</summary>
    class procedure Start; static;
    /// <summary>Keine neuen Belegungen mehr aufzeichnen; Freigaben streichen weiter.</summary>
    class procedure Stop; static;
    /// <summary>Übrige Belegungen seit Start, je Stapel eine Gruppe mit Bytes und Blöcken, die größten zuerst,
    /// höchstens AMaxGroups; '' ohne Rest.</summary>
    class function Report(AMaxGroups: Integer): string; static;
    /// <summary>Bytes der übrigen Belegungen seit Start, ohne vergrößerte ältere Blöcke.</summary>
    class function Bytes: Int64; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Windows.Diagnostics.StackTrace;

const
  cFrames = 12;
  cSlotBits = 17;
  cSlots = 1 shl cSlotBits;
  cMask = cSlots - 1;

type
  PSlot = ^TSlot;
  TSlot = record
    Address: Pointer;
    Size: NativeInt;
    // Vor Start angelegt und seitdem per ReallocMem verändert: Size ist die neue Größe, nicht der Zuwachs.
    Grown: Boolean;
    Count: Integer;
    Frames: array[0..cFrames - 1] of Pointer;
  end;
  PSlots = ^TSlots;
  TSlots = array[0..cSlots - 1] of TSlot;

  TGroup = record
    Bytes: Int64;
    Blocks: Integer;
    Slot: PSlot;
    // Mit Map aufgelöster Stapel und ob ein Rahmen aus Atlas darin liegt.
    Text: string;
    Own: Boolean;
  end;

var
  Previous: TMemoryManagerEx;
  Installed: Boolean;
  Recording: Boolean;
  Used: Integer;
  Overflow: Boolean;
  Slots: PSlots;
  LockFlag: Integer;
  // Markiert gelöschte Plätze, damit die Suche dahinter weitergeht.
  Removed: Byte;

function CaptureStackBackTrace(AFramesToSkip, AFramesToCapture: ULONG; ABackTrace: Pointer;
  ABackTraceHash: PULONG): USHORT; stdcall; external kernel32 name 'RtlCaptureStackBackTrace';

procedure Lock;
begin
  while AtomicCmpExchange(LockFlag, 1, 0) <> 0 do
  begin
    Sleep(0);
  end;
end;

procedure Unlock;
begin
  AtomicExchange(LockFlag, 0);
end;

function SlotIndex(AAddress: Pointer): Integer;
begin
  {$IFOPT Q+}{$DEFINE TRACE_Q}{$Q-}{$ENDIF}
  {$IFOPT R+}{$DEFINE TRACE_R}{$R-}{$ENDIF}
  Result := Integer(((NativeUInt(AAddress) shr 4) * NativeUInt(2654435761)) and cMask);
  {$IFDEF TRACE_R}{$R+}{$UNDEF TRACE_R}{$ENDIF}
  {$IFDEF TRACE_Q}{$Q+}{$UNDEF TRACE_Q}{$ENDIF}
end;

procedure Add(AAddress: Pointer; ASize: NativeInt; AGrown: Boolean);
var
  mIndex: Integer;
  mProbe: Integer;
  mSlot: PSlot;
begin
  if (AAddress = nil) or Overflow then
  begin
    Exit;
  end;
  Lock;
  try
    // Höchstens drei Viertel füllen, sonst wird die Suche lang.
    if Used >= cSlots - cSlots div 4 then
    begin
      Overflow := True;
      Exit;
    end;
    mIndex := SlotIndex(AAddress);
    for mProbe := 0 to cMask do
    begin
      mSlot := @Slots[(mIndex + mProbe) and cMask];
      if (mSlot.Address = nil) or (mSlot.Address = @Removed) then
      begin
        mSlot.Address := AAddress;
        mSlot.Size := ASize;
        mSlot.Grown := AGrown;
        // Ohne diese Routine und den Haken, der sie ruft.
        mSlot.Count := CaptureStackBackTrace(2, cFrames, @mSlot.Frames[0], nil);
        Inc(Used);
        Exit;
      end;
    end;
  finally
    Unlock;
  end;
end;

/// <summary>Streicht AAddress; False, wenn der Block nicht aufgezeichnet war.</summary>
function Remove(AAddress: Pointer): Boolean;
var
  mIndex: Integer;
  mProbe: Integer;
  mSlot: PSlot;
begin
  Result := False;
  if (AAddress = nil) or (Used = 0) then
  begin
    Exit;
  end;
  Lock;
  try
    mIndex := SlotIndex(AAddress);
    for mProbe := 0 to cMask do
    begin
      mSlot := @Slots[(mIndex + mProbe) and cMask];
      if mSlot.Address = nil then
      begin
        Exit;
      end;
      if mSlot.Address = AAddress then
      begin
        mSlot.Address := @Removed;
        Dec(Used);
        Result := True;
        Exit;
      end;
    end;
  finally
    Unlock;
  end;
end;

function TraceGetMem(ASize: NativeInt): Pointer;
begin
  Result := Previous.GetMem(ASize);
  if Recording then
  begin
    Add(Result, ASize, False);
  end;
end;

function TraceAllocMem(ASize: NativeInt): Pointer;
begin
  Result := Previous.AllocMem(ASize);
  if Recording then
  begin
    Add(Result, ASize, False);
  end;
end;

function TraceFreeMem(AAddress: Pointer): Integer;
begin
  Remove(AAddress);
  Result := Previous.FreeMem(AAddress);
end;

function TraceReallocMem(AAddress: Pointer; ASize: NativeInt): Pointer;
var
  mKnown: Boolean;
begin
  mKnown := Remove(AAddress);
  Result := Previous.ReallocMem(AAddress, ASize);
  if Recording then
  begin
    Add(Result, ASize, not mKnown);
  end;
end;

function TraceRegisterLeak(AAddress: Pointer): Boolean;
begin
  Result := Previous.RegisterExpectedMemoryLeak(AAddress);
end;

function TraceUnregisterLeak(AAddress: Pointer): Boolean;
begin
  Result := Previous.UnregisterExpectedMemoryLeak(AAddress);
end;

function SameStack(ALeft, ARight: PSlot): Boolean;
var
  mIndex: Integer;
begin
  Result := (ALeft.Count = ARight.Count) and (ALeft.Grown = ARight.Grown);
  mIndex := 0;
  while Result and (mIndex < ALeft.Count) do
  begin
    Result := ALeft.Frames[mIndex] = ARight.Frames[mIndex];
    Inc(mIndex);
  end;
end;

function StackText(ASlot: PSlot): string;
var
  mFrames: TArray<Pointer>;
  mIndex: Integer;
begin
  SetLength(mFrames, ASlot.Count);
  for mIndex := 0 to ASlot.Count - 1 do
  begin
    mFrames[mIndex] := ASlot.Frames[mIndex];
  end;
  Result := TStackTrace.DescribeFrames(mFrames);
end;

/// <summary>Übrige Belegungen nach Stapel zusammenfassen.</summary>
procedure CollectGroups(AGroups: TList<TGroup>);
var
  mGroup: TGroup;
  mIndex: Integer;
  mFound: Integer;
  mSlot: PSlot;
begin
  for mIndex := 0 to cMask do
  begin
    mSlot := @Slots[mIndex];
    if (mSlot.Address = nil) or (mSlot.Address = @Removed) then
    begin
      Continue;
    end;
    mFound := 0;
    while (mFound < AGroups.Count) and not SameStack(AGroups[mFound].Slot, mSlot) do
    begin
      Inc(mFound);
    end;
    if mFound < AGroups.Count then
    begin
      mGroup := AGroups[mFound];
      Inc(mGroup.Bytes, mSlot.Size);
      Inc(mGroup.Blocks);
      AGroups[mFound] := mGroup;
    end
    else
    begin
      mGroup.Bytes := mSlot.Size;
      mGroup.Blocks := 1;
      mGroup.Slot := mSlot;
      AGroups.Add(mGroup);
    end;
  end;
end;

/// <summary>True, wenn ein aufgelöster Rahmen in einer Unit von Atlas liegt (Atlas.*, Shell.*).</summary>
function HasOwnFrame(const AStack: string): Boolean;
begin
  Result := AStack.Contains(' Atlas.') or AStack.Contains(' Shell.');
end;

/// <summary>Stapel jeder Gruppe auflösen und nach eigenen Rahmen einordnen.</summary>
procedure DescribeGroups(AGroups: TList<TGroup>);
var
  mGroup: TGroup;
  mIndex: Integer;
begin
  for mIndex := 0 to AGroups.Count - 1 do
  begin
    mGroup := AGroups[mIndex];
    mGroup.Text := StackText(mGroup.Slot);
    mGroup.Own := HasOwnFrame(mGroup.Text);
    AGroups[mIndex] := mGroup;
  end;
end;

/// <summary>Gruppen mit Atlas-Rahmen zuerst, dann die größte; bei Gleichstand nach Platz, denn Sort ist nicht
/// stabil.</summary>
function CompareGroups(const ALeft, ARight: TGroup): Integer;
begin
  Result := 0;
  if ALeft.Own <> ARight.Own then
  begin
    Result := Ord(ARight.Own) - Ord(ALeft.Own);
  end
  else if ALeft.Bytes > ARight.Bytes then
  begin
    Result := -1;
  end
  else if ALeft.Bytes < ARight.Bytes then
  begin
    Result := 1;
  end
  else if NativeUInt(ALeft.Slot) < NativeUInt(ARight.Slot) then
  begin
    Result := -1;
  end
  else if NativeUInt(ALeft.Slot) > NativeUInt(ARight.Slot) then
  begin
    Result := 1;
  end;
end;

function GroupHeading(const AGroup: TGroup): string;
begin
  if AGroup.Slot.Grown then
  begin
    Result := Format('%d Bytes in %d Blöcken vergrößert bei (vor dem Test angelegt, alte Größe unbekannt):',
      [AGroup.Bytes, AGroup.Blocks]);
  end
  else
  begin
    Result := Format('%d Bytes in %d Blöcken angelegt bei:', [AGroup.Bytes, AGroup.Blocks]);
  end;
end;

/// <summary>Stapel mit Atlas-Rahmen ausschreiben (höchstens AMaxGroups); die übrigen nur zählen.</summary>
function GroupsText(AGroups: TList<TGroup>; AMaxGroups: Integer): string;
var
  mGroup: TGroup;
  mShown: Integer;
  mOtherGroups: Integer;
  mOtherBytes: Int64;
begin
  Result := '';
  mShown := 0;
  mOtherGroups := 0;
  mOtherBytes := 0;
  for mGroup in AGroups do
  begin
    if mGroup.Own and (mShown < AMaxGroups) then
    begin
      Result := Result + GroupHeading(mGroup) + sLineBreak + mGroup.Text;
      Inc(mShown);
    end
    else
    begin
      Inc(mOtherGroups);
      Inc(mOtherBytes, mGroup.Bytes);
    end;
  end;
  if mOtherGroups > 0 then
  begin
    Result := Result + Format('… und %d weitere Stapel mit %d Bytes (ohne Atlas-Rahmen oder über der Grenze)',
      [mOtherGroups, mOtherBytes]) + sLineBreak;
  end;
  if Overflow then
  begin
    Result := Result + 'Tabelle voll, weitere Belegungen nicht aufgezeichnet' + sLineBreak;
  end;
end;

{ TAllocationTrace }

class procedure TAllocationTrace.Install;
var
  mHooks: TMemoryManagerEx;
begin
  if Installed then
  begin
    Exit;
  end;
  Slots := VirtualAlloc(nil, SizeOf(TSlots), MEM_COMMIT or MEM_RESERVE, PAGE_READWRITE);
  if Slots = nil then
  begin
    Exit;
  end;
  GetMemoryManager(Previous);
  mHooks := Previous;
  mHooks.GetMem := TraceGetMem;
  mHooks.AllocMem := TraceAllocMem;
  mHooks.FreeMem := TraceFreeMem;
  mHooks.ReallocMem := TraceReallocMem;
  mHooks.RegisterExpectedMemoryLeak := TraceRegisterLeak;
  mHooks.UnregisterExpectedMemoryLeak := TraceUnregisterLeak;
  SetMemoryManager(mHooks);
  Installed := True;
end;

class function TAllocationTrace.Requested: Boolean;
begin
  Result := GetEnvironmentVariable('ATLAS_LEAK_TRACE') = '1';
end;

class procedure TAllocationTrace.Start;
begin
  if not Installed then
  begin
    Exit;
  end;
  Lock;
  try
    FillChar(Slots^, SizeOf(TSlots), 0);
    Used := 0;
    Overflow := False;
    Recording := True;
  finally
    Unlock;
  end;
end;

class procedure TAllocationTrace.Stop;
begin
  Recording := False;
end;

class function TAllocationTrace.Bytes: Int64;
var
  mIndex: Integer;
begin
  Result := 0;
  if not Installed then
  begin
    Exit;
  end;
  Lock;
  try
    for mIndex := 0 to cMask do
    begin
      if (Slots[mIndex].Address <> nil) and (Slots[mIndex].Address <> @Removed) and not Slots[mIndex].Grown then
      begin
        Inc(Result, Slots[mIndex].Size);
      end;
    end;
  finally
    Unlock;
  end;
end;

class function TAllocationTrace.Report(AMaxGroups: Integer): string;
var
  mWasRecording: Boolean;
  mGroups: TList<TGroup>;
begin
  Result := '';
  if not Installed then
  begin
    Exit;
  end;
  // Der Bericht belegt selbst Speicher: nicht mit aufzeichnen.
  mWasRecording := Recording;
  Recording := False;
  mGroups := TList<TGroup>.Create;
  try
    CollectGroups(mGroups);
    DescribeGroups(mGroups);
    mGroups.Sort(TComparer<TGroup>.Construct(CompareGroups));
    Result := GroupsText(mGroups, AMaxGroups);
  finally
    mGroups.Free;
    Recording := mWasRecording;
  end;
end;

end.
