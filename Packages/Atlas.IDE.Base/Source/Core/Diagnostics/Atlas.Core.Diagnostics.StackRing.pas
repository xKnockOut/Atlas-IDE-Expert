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
    MaxFrames = 40;
    MaxParams = 4;
  public
    /// <summary>Laufende Nummer; 0 = leer oder gerade in Arbeit.</summary>
    Sequence: Int64;
    ThreadId: Cardinal;
    Code: Cardinal;
    Address: NativeUInt;
    ParamCount: Integer;
    Params: array[0..MaxParams - 1] of NativeUInt;
    Count: Integer;
    Frames: array[0..MaxFrames - 1] of NativeUInt;
    /// <summary>Passt AKey zur Fehleradresse oder zu einem der Parameter?</summary>
    function Matches(AKey: NativeUInt): Boolean;
    /// <summary>Rahmen als Liste, die Fehleradresse vorn (unter Win32 fehlt die fehlerhafte Routine sonst).</summary>
    function Addresses: TArray<UInt64>;
  end;

  TAtlasStackRing = class
  public const
    SlotCount = 32;
  private
    FSlots: array[0..SlotCount - 1] of TAtlasStackRecord;
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
  Index: Integer;
begin
  if AKey = 0 then
    Exit(False);
  if Address = AKey then
    Exit(True);
  for Index := 0 to ParamCount - 1 do
    if (Index < MaxParams) and (Params[Index] = AKey) then
      Exit(True);
  Result := False;
end;

function TAtlasStackRecord.Addresses: TArray<UInt64>;
var
  Index: Integer;
begin
  Result := nil;
  if Address <> 0 then
    Result := Result + [UInt64(Address)];
  for Index := 0 to Count - 1 do
    if (Index < MaxFrames) and (Frames[Index] <> 0) then
      Result := Result + [UInt64(Frames[Index])];
end;

{ TAtlasStackRing }

procedure TAtlasStackRing.Add(const ARecord: TAtlasStackRecord);
var
  Sequence: Int64;
  Slot: ^TAtlasStackRecord;
begin
  Sequence := TInterlocked.Increment(FNext);
  Slot := @FSlots[Sequence mod SlotCount];
  // Erst als „in Arbeit“ markieren, dann füllen, zuletzt die Nummer: Find übergeht halbe Einträge.
  TInterlocked.Exchange(Slot^.Sequence, 0);
  Slot^.ThreadId := ARecord.ThreadId;
  Slot^.Code := ARecord.Code;
  Slot^.Address := ARecord.Address;
  Slot^.ParamCount := ARecord.ParamCount;
  Slot^.Params := ARecord.Params;
  Slot^.Count := ARecord.Count;
  Slot^.Frames := ARecord.Frames;
  TInterlocked.Exchange(Slot^.Sequence, Sequence);
end;

function TAtlasStackRing.Find(AThreadId: Cardinal; const AKeys: array of NativeUInt;
  out ARecord: TAtlasStackRecord): Boolean;
var
  Index: Integer;
  Key: NativeUInt;
  Item: TAtlasStackRecord;
  Best: Int64;
begin
  Result := False;
  ARecord := Default(TAtlasStackRecord);
  Best := 0;
  for Index := 0 to SlotCount - 1 do
  begin
    Item := FSlots[Index];
    // Während des Kopierens neu beschrieben: auslassen.
    if (Item.Sequence = 0) or (TInterlocked.Read(FSlots[Index].Sequence) <> Item.Sequence) then
      Continue;
    if (Item.ThreadId <> AThreadId) or (Item.Sequence <= Best) then
      Continue;
    for Key in AKeys do
      if Item.Matches(Key) then
      begin
        ARecord := Item;
        Best := Item.Sequence;
        Result := True;
        Break;
      end;
  end;
end;

procedure TAtlasStackRing.Clear;
var
  Index: Integer;
begin
  for Index := 0 to SlotCount - 1 do
    TInterlocked.Exchange(FSlots[Index].Sequence, 0);
end;

{ TAtlasStackFrames }

class function TAtlasStackFrames.Symbolize(const AFrame: string; const AMap: TMapFile;
  const AMapModule: string): string;
var
  Plus: Integer;
  Offset: Int64;
  Location: TMapLocation;
  Hex: string;
begin
  Result := AFrame;
  if (AMap = nil) or (AMapModule = '') then
    Exit;
  Plus := Pos('+', AFrame);
  if (Plus = 0) or not SameText(Copy(AFrame, 1, Plus - 1), AMapModule) then
    Exit;
  Hex := Copy(AFrame, Plus + 1, MaxInt);
  if Hex.StartsWith('$') then
    Hex := Copy(Hex, 2, MaxInt);
  if not TryStrToInt64('$' + Hex, Offset) then
    Exit;
  Location := AMap.Resolve(UInt64(Offset));
  if Location.Found then
    Result := AFrame + ' ' + Location.ToString;
end;

class function TAtlasStackFrames.Describe(const AAddresses: TArray<UInt64>;
  const AModules: TArray<TAtlasModuleRange>; const AMap: TMapFile; const AMapModule: string; AMax: Integer): string;
var
  Address: UInt64;
  Module: TAtlasModuleRange;
  Frame: string;
  Lines: Integer;
begin
  Result := '';
  Lines := 0;
  for Address in AAddresses do
  begin
    if Lines >= AMax then
      Break;
    Frame := Format('$%x', [Address]);
    for Module in AModules do
      if (Address >= Module.Base) and (Address < Module.Base + Module.Size) then
      begin
        Frame := Symbolize(Format('%s+$%x', [Module.Name, Address - Module.Base]), AMap, AMapModule);
        Break;
      end;
    if Result <> '' then
      Result := Result + sLineBreak;
    Result := Result + Frame;
    Inc(Lines);
  end;
end;

end.
