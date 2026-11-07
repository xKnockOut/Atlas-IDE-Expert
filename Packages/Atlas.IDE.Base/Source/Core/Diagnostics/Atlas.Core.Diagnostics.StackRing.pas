unit Atlas.Core.Diagnostics.StackRing;

// Stacktraces für die Sicherung (#493), Teil ohne Windows und Open Tools API:
// - TAtlasStackRing: Ringpuffer der zuletzt mitgeschnittenen Ausnahmen. Der
//   Mitschnitt (Atlas.IDE.Diagnostics.StackCapture) schreibt im
//   Ausnahmebehandler des Systems, bevor der Stapel abgebaut ist; dort darf
//   kein Speicher angelegt werden. Deshalb nur Records mit festen Feldern,
//   Add legt nichts an und sperrt nichts.
// - Find sucht zur gerade behandelten Ausnahme den jüngsten Eintrag desselben
//   Threads, dessen Adresse oder Parameter zur Ausnahme passen (Objekt der
//   Delphi-Ausnahme bzw. Fehleradresse).
// - TAtlasStackFrames.Describe macht daraus Zeilen "Modul+$Offset"; Rahmen im
//   Atlas-Modul bekommen mit Map-Datei Unit, Routine und Zeile dahinter.

interface

uses
  System.SysUtils,
  Atlas.Text.MapFile,
  Atlas.Core.Diagnostics.Hangs;

type
  TAtlasStackRecord = record
  public const
    cMaxFrames = 40;
    cMaxParams = 4;
  public
    /// <summary>Laufende Nummer; 0 = leer oder gerade in Arbeit.</summary>
    Sequence: Int64;
    ThreadId: Cardinal;
    Code: Cardinal;
    Address: NativeUInt;
    ParamCount: Integer;
    Params: array[0..cMaxParams - 1] of NativeUInt;
    Count: Integer;
    Frames: array[0..cMaxFrames - 1] of NativeUInt;
    /// <summary>Passt AKey zur Fehleradresse oder zu einem der Parameter?</summary>
    function Matches(AKey: NativeUInt): Boolean;
    /// <summary>Rahmen als Liste, die Fehleradresse vorn (unter Win32 fehlt die fehlerhafte Routine sonst).</summary>
    function Addresses: TArray<UInt64>;
  end;

  TAtlasStackRing = class
  public const
    cSlotCount = 32;
  private
    FSlots: array[0..cSlotCount - 1] of TAtlasStackRecord;
    FNext: Int64;
  public
    /// <summary>Legt nichts an und sperrt nichts; aus dem Ausnahmebehandler des Systems.</summary>
    procedure Add(const ARecord: TAtlasStackRecord);
    /// <summary>Jüngster Eintrag des Threads AThreadId, der zu einem der Schlüssel passt (0 zählt nicht).</summary>
    function Find(AThreadId: Cardinal; const AKeys: array of NativeUInt; out ARecord: TAtlasStackRecord): Boolean;
    procedure Clear;
  end;

  TAtlasStackFrames = class
  public
    /// <summary>Eine Zeile je Rahmen, höchstens AMax; Rahmen in AMapModule mit Auflösung über AMap (nil = ohne).
    /// Rahmen ohne Modul als "$Adresse".</summary>
    class function Describe(const AAddresses: TArray<UInt64>; const AModules: TArray<TAtlasModuleRange>;
      const AMap: TMapFile; const AMapModule: string; AMax: Integer): string; static;
    /// <summary>Hängt an Zeilen "AMapModule+Offset" (mit oder ohne $) die Stelle aus AMap an.</summary>
    class function Symbolize(const AFrame: string; const AMap: TMapFile; const AMapModule: string): string; static;
  end;

implementation

uses
  System.SyncObjs;

{ TAtlasStackRecord }

function TAtlasStackRecord.Matches(AKey: NativeUInt): Boolean;
var
  mIndex: Integer;
begin
  if AKey = 0 then
  begin
    Exit(False);
  end;
  if Address = AKey then
  begin
    Exit(True);
  end;
  for mIndex := 0 to ParamCount - 1 do
  begin
    if (mIndex < cMaxParams) and (Params[mIndex] = AKey) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasStackRecord.Addresses: TArray<UInt64>;
var
  mIndex: Integer;
begin
  Result := nil;
  if Address <> 0 then
  begin
    Result := Result + [UInt64(Address)];
  end;
  for mIndex := 0 to Count - 1 do
  begin
    if (mIndex < cMaxFrames) and (Frames[mIndex] <> 0) then
    begin
      Result := Result + [UInt64(Frames[mIndex])];
    end;
  end;
end;

{ TAtlasStackRing }

procedure TAtlasStackRing.Add(const ARecord: TAtlasStackRecord);
var
  mSequence: Int64;
  mSlot: ^TAtlasStackRecord;
begin
  mSequence := TInterlocked.Increment(FNext);
  mSlot := @FSlots[mSequence mod cSlotCount];
  // Erst als „in Arbeit“ markieren, dann füllen, zuletzt die Nummer: Find übergeht halbe Einträge.
  TInterlocked.Exchange(mSlot^.Sequence, 0);
  mSlot^.ThreadId := ARecord.ThreadId;
  mSlot^.Code := ARecord.Code;
  mSlot^.Address := ARecord.Address;
  mSlot^.ParamCount := ARecord.ParamCount;
  mSlot^.Params := ARecord.Params;
  mSlot^.Count := ARecord.Count;
  mSlot^.Frames := ARecord.Frames;
  TInterlocked.Exchange(mSlot^.Sequence, mSequence);
end;

function TAtlasStackRing.Find(AThreadId: Cardinal; const AKeys: array of NativeUInt;
  out ARecord: TAtlasStackRecord): Boolean;
var
  mIndex: Integer;
  mKey: NativeUInt;
  mItem: TAtlasStackRecord;
  mBest: Int64;
begin
  Result := False;
  ARecord := Default(TAtlasStackRecord);
  mBest := 0;
  for mIndex := 0 to cSlotCount - 1 do
  begin
    mItem := FSlots[mIndex];
    // Während des Kopierens neu beschrieben: auslassen.
    if (mItem.Sequence = 0) or (TInterlocked.Read(FSlots[mIndex].Sequence) <> mItem.Sequence) then
    begin
      Continue;
    end;
    if (mItem.ThreadId <> AThreadId) or (mItem.Sequence <= mBest) then
    begin
      Continue;
    end;
    for mKey in AKeys do
    begin
      if mItem.Matches(mKey) then
      begin
        ARecord := mItem;
        mBest := mItem.Sequence;
        Result := True;
        Break;
      end;
    end;
  end;
end;

procedure TAtlasStackRing.Clear;
var
  mIndex: Integer;
begin
  for mIndex := 0 to cSlotCount - 1 do
  begin
    TInterlocked.Exchange(FSlots[mIndex].Sequence, 0);
  end;
end;

{ TAtlasStackFrames }

class function TAtlasStackFrames.Symbolize(const AFrame: string; const AMap: TMapFile;
  const AMapModule: string): string;
var
  mPlus: Integer;
  mOffset: Int64;
  mLocation: TMapLocation;
  mHex: string;
begin
  Result := AFrame;
  if (AMap = nil) or (AMapModule = '') then
  begin
    Exit;
  end;
  mPlus := Pos('+', AFrame);
  if (mPlus = 0) or not SameText(Copy(AFrame, 1, mPlus - 1), AMapModule) then
  begin
    Exit;
  end;
  mHex := Copy(AFrame, mPlus + 1, MaxInt);
  if mHex.StartsWith('$') then
  begin
    mHex := Copy(mHex, 2, MaxInt);
  end;
  if not TryStrToInt64('$' + mHex, mOffset) then
  begin
    Exit;
  end;
  mLocation := AMap.Resolve(UInt64(mOffset));
  if mLocation.Found then
  begin
    Result := AFrame + ' ' + mLocation.ToString;
  end;
end;

class function TAtlasStackFrames.Describe(const AAddresses: TArray<UInt64>;
  const AModules: TArray<TAtlasModuleRange>; const AMap: TMapFile; const AMapModule: string; AMax: Integer): string;
var
  mAddress: UInt64;
  mModule: TAtlasModuleRange;
  mFrame: string;
  mLines: Integer;
begin
  Result := '';
  mLines := 0;
  for mAddress in AAddresses do
  begin
    if mLines >= AMax then
    begin
      Break;
    end;
    mFrame := Format('$%x', [mAddress]);
    for mModule in AModules do
    begin
      if (mAddress >= mModule.Base) and (mAddress < mModule.Base + mModule.Size) then
      begin
        mFrame := Symbolize(Format('%s+$%x', [mModule.Name, mAddress - mModule.Base]), AMap, AMapModule);
        Break;
      end;
    end;
    if Result <> '' then
    begin
      Result := Result + sLineBreak;
    end;
    Result := Result + mFrame;
    Inc(mLines);
  end;
end;

end.
