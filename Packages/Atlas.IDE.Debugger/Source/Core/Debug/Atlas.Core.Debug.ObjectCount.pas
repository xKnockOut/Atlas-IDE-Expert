unit Atlas.Core.Debug.ObjectCount;

// Objektzählung beim Debuggen (#858, experimentell), Kern ohne VCL und ohne Windows:
// - TAtlasObjectCounter liest den privaten beschreibbaren Speicher des Programms (IAtlasProcessMemory) und sucht
//   darin Zeiger auf gültige VMTs. Gültig ist eine Adresse in einem Abbild (EXE, DLL, BPL), deren Selbstzeiger
//   auf sie selbst zeigt und deren Klassenname lesbar ist. Jeder Treffer zählt als lebendes Objekt seiner Klasse.
//   Das hängt nicht vom Speichermanager ab, ist aber eine Näherung: Klassenverweise in Feldern und auf dem Stapel
//   zählen mit, freigegebene Blöcke nur, solange ihr erstes Wort nicht überschrieben ist (FastMM überschreibt es).
// - Die Versätze der VMT hängen von der Plattform und der Delphi-Version ab; TAtlasVmtLayout nennt die bekannten,
//   je VMT gilt der erste, dessen Selbstzeiger passt.
// - TAtlasObjectCountCompare stellt zwei Zählungen gegenüber: Zuwächse oben, Filter nach Teil des Namens.
// Gelesen wird in Atlas.IDE.Debug.ObjectCountReader, gezeigt in Atlas.UI.Debug.ObjectCountPanel.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  {$SCOPEDENUMS ON}
  TAtlasMemoryRegionKind = (Data, Image);
  {$SCOPEDENUMS OFF}

  TAtlasMemoryRegion = record
    Base: UInt64;
    Size: UInt64;
    Kind: TAtlasMemoryRegionKind;
    class function Make(ABase, ASize: UInt64; AKind: TAtlasMemoryRegionKind): TAtlasMemoryRegion; static;
  end;

  /// <summary>Lesender Zugriff auf den Speicher eines Prozesses.</summary>
  IAtlasProcessMemory = interface
    ['{6C0E2B7A-3D51-4F1E-9A8C-5B2D7E41C903}']
    /// <summary>4 (32-Bit-Programm) oder 8 (64-Bit-Programm).</summary>
    function PointerSize: Integer;
    /// <summary>Belegte Bereiche: privater beschreibbarer Speicher (Data) und Abbilder (Image), aufsteigend.
    /// </summary>
    function Regions: TArray<TAtlasMemoryRegion>;
    /// <summary>Bis zu ASize Bytes ab AAddress nach ABuffer; Ergebnis = gelesene Bytes (0 bei Fehler).</summary>
    function Read(AAddress: UInt64; var ABuffer; ASize: Integer): Integer;
  end;

  /// <summary>Abstände unterhalb der VMT in Bytes: Selbstzeiger, Zeiger auf den Klassennamen, Instanzgröße.
  /// </summary>
  TAtlasVmtLayout = record
    SelfBelow: Integer;
    NameBelow: Integer;
    SizeBelow: Integer;
    class function Make(ASelfBelow, ANameBelow, ASizeBelow: Integer): TAtlasVmtLayout; static;
    /// <summary>Bekannte Anordnungen für die Zeigergröße, die häufigste zuerst.</summary>
    class function ForPointerSize(APointerSize: Integer): TArray<TAtlasVmtLayout>; static;
  end;

  TAtlasClassCount = record
    Name: string;
    Count: Integer;
    InstanceSize: Integer;
  end;

  /// <summary>Ergebnis einer Zählung; Klassen nach Namen sortiert, jeder Name einmal.</summary>
  TAtlasObjectCount = record
    Classes: TArray<TAtlasClassCount>;
    ScannedBytes: UInt64;
    function Total: Integer;
    function IndexOf(const AName: string): Integer;
  end;

  TAtlasObjectCountRow = record
    Name: string;
    Count: Integer;
    /// <summary>Zuwachs gegenüber der Basis; ohne Basis 0.</summary>
    Delta: Integer;
    /// <summary>Anzahl mal Instanzgröße (ohne Strings, Arrays und andere Blöcke, auf die das Objekt zeigt).
    /// </summary>
    Bytes: Int64;
  end;

  TAtlasObjectCounter = class
  public const
    /// <summary>So viel wird je Lesezugriff geholt.</summary>
    cChunkSize = 4 * 1024 * 1024;
    /// <summary>Objekte liegen mindestens so ausgerichtet (FastMM: 8 bzw. 16).</summary>
    cAlignment = 8;
    cMaxInstanceSize = 64 * 1024 * 1024;
  private type
    TClassInfo = record
      Name: string;
      InstanceSize: Integer;
    end;
  private
    FMemory: IAtlasProcessMemory;
    FPointerSize: Integer;
    FLayouts: TArray<TAtlasVmtLayout>;
    FImages: TArray<TAtlasMemoryRegion>;
    FImageLow: UInt64;
    FImageHigh: UInt64;
    FKnown: TDictionary<UInt64, Integer>;
    FClasses: TList<TClassInfo>;
    FCounts: TList<Integer>;
    function ReadPointer(AAddress: UInt64; out AValue: UInt64): Boolean;
    function InImage(AAddress: UInt64): Boolean;
    function ReadClassName(AAddress: UInt64; out AName: string): Boolean;
    function ReadClass(AVmt: UInt64; const ALayout: TAtlasVmtLayout; out AInfo: TClassInfo): Boolean;
    /// <summary>Index der Klasse zur VMT AVmt; -1, wenn AVmt keine VMT ist.</summary>
    function ClassOf(AVmt: UInt64): Integer;
    procedure ScanBuffer(const ABuffer: TBytes; ALength: Integer);
    procedure ScanRegion(const ARegion: TAtlasMemoryRegion; var ABuffer: TBytes; var AScanned: UInt64);
    function Collect: TArray<TAtlasClassCount>;
  public
    constructor Create(const AMemory: IAtlasProcessMemory);
    destructor Destroy; override;
    function Run: TAtlasObjectCount;
    /// <summary>Lesbarer Klassenname (Bezeichner, auch mit Punkt und spitzen Klammern generischer Typen)?</summary>
    class function IsClassName(const AName: string): Boolean; static;
  end;

  TAtlasObjectCountCompare = record
  public
    /// <summary>Zeilen der Zählung ACurrent; mit AHasBase der Zuwachs gegenüber ABase (auch Klassen, die ganz
    /// verschwunden sind, mit Anzahl 0). AFilter: Teil des Klassennamens, ohne Groß-/Kleinschreibung; '' = alle.
    /// Sortiert nach Zuwachs absteigend, dann Anzahl absteigend, dann Name.</summary>
    class function Rows(const ABase, ACurrent: TAtlasObjectCount; AHasBase: Boolean;
      const AFilter: string): TArray<TAtlasObjectCountRow>; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults;

const
  cPointerSize32 = 4;
  /// <summary>vmtSelfPtr, vmtClassName, vmtInstanceSize unter Win32 (als Abstand unter der VMT).</summary>
  cWin32SelfBelow = 88;
  cWin32NameBelow = 56;
  cWin32SizeBelow = 52;
  /// <summary>Dieselben unter Win64, in der Probe mit Delphi 13 gemessen.</summary>
  cWin64SelfBelow = 200;
  cWin64NameBelow = 136;
  cWin64SizeBelow = 128;
  /// <summary>Dieselben unter Win64 nach der Rechnung „Win32 mal zwei“.</summary>
  cWin64DoubledSelfBelow = 176;
  cWin64DoubledNameBelow = 112;
  cWin64DoubledSizeBelow = 104;
  cLastAscii = 127;

{ TAtlasMemoryRegion }

class function TAtlasMemoryRegion.Make(ABase, ASize: UInt64; AKind: TAtlasMemoryRegionKind): TAtlasMemoryRegion;
begin
  Result.Base := ABase;
  Result.Size := ASize;
  Result.Kind := AKind;
end;

{ TAtlasVmtLayout }

class function TAtlasVmtLayout.Make(ASelfBelow, ANameBelow, ASizeBelow: Integer): TAtlasVmtLayout;
begin
  Result.SelfBelow := ASelfBelow;
  Result.NameBelow := ANameBelow;
  Result.SizeBelow := ASizeBelow;
end;

class function TAtlasVmtLayout.ForPointerSize(APointerSize: Integer): TArray<TAtlasVmtLayout>;
begin
  // Win32: vmtSelfPtr -88, vmtClassName -56, vmtInstanceSize -52. Win64: in der Probe mit Delphi 13
  // -200/-136/-128, nach der Rechnung „Win32 mal zwei“ -176/-112/-104; beide werden versucht.
  if APointerSize = cPointerSize32 then
  begin
    SetLength(Result, 1);
    Result[0] := Make(cWin32SelfBelow, cWin32NameBelow, cWin32SizeBelow);
    Exit;
  end;
  SetLength(Result, 2);
  Result[0] := Make(cWin64SelfBelow, cWin64NameBelow, cWin64SizeBelow);
  Result[1] := Make(cWin64DoubledSelfBelow, cWin64DoubledNameBelow, cWin64DoubledSizeBelow);
end;

{ TAtlasObjectCount }

function TAtlasObjectCount.Total: Integer;
var
  mClass: TAtlasClassCount;
begin
  Result := 0;
  for mClass in Classes do
  begin
    Inc(Result, mClass.Count);
  end;
end;

function TAtlasObjectCount.IndexOf(const AName: string): Integer;
var
  mLow: Integer;
  mHigh: Integer;
  mMiddle: Integer;
  mCompare: Integer;
begin
  mLow := 0;
  mHigh := High(Classes);
  while mLow <= mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    mCompare := CompareStr(Classes[mMiddle].Name, AName);
    if mCompare = 0 then
    begin
      Exit(mMiddle);
    end;
    if mCompare < 0 then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle - 1;
    end;
  end;
  Result := -1;
end;

{ TAtlasObjectCounter }

constructor TAtlasObjectCounter.Create(const AMemory: IAtlasProcessMemory);
begin
  inherited Create;
  FMemory := AMemory;
  FPointerSize := AMemory.PointerSize;
  FLayouts := TAtlasVmtLayout.ForPointerSize(FPointerSize);
  FKnown := TDictionary<UInt64, Integer>.Create;
  FClasses := TList<TClassInfo>.Create;
  FCounts := TList<Integer>.Create;
end;

destructor TAtlasObjectCounter.Destroy;
begin
  FCounts.Free;
  FClasses.Free;
  FKnown.Free;
  inherited Destroy;
end;

class function TAtlasObjectCounter.IsClassName(const AName: string): Boolean;
var
  mChar: Char;
  mIndex: Integer;
begin
  Result := False;
  if AName = '' then
  begin
    Exit;
  end;
  for mIndex := 1 to Length(AName) do
  begin
    mChar := AName[mIndex];
    if CharInSet(mChar, ['A'..'Z', 'a'..'z', '_']) or (Ord(mChar) > cLastAscii) then
    begin
      Continue;
    end;
    // Ziffern, Punkte und die Zeichen generischer Typen nicht am Anfang.
    if (mIndex = 1) or not CharInSet(mChar, ['0'..'9', '.', '<', '>', ',']) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

function TAtlasObjectCounter.ReadPointer(AAddress: UInt64; out AValue: UInt64): Boolean;
begin
  AValue := 0;
  Result := FMemory.Read(AAddress, AValue, FPointerSize) = FPointerSize;
end;

function TAtlasObjectCounter.InImage(AAddress: UInt64): Boolean;
var
  mLow: Integer;
  mHigh: Integer;
  mMiddle: Integer;
begin
  Result := False;
  if (AAddress < FImageLow) or (AAddress >= FImageHigh) then
  begin
    Exit;
  end;
  mLow := 0;
  mHigh := High(FImages);
  while mLow <= mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if AAddress < FImages[mMiddle].Base then
    begin
      mHigh := mMiddle - 1;
    end
    else if AAddress - FImages[mMiddle].Base >= FImages[mMiddle].Size then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasObjectCounter.ReadClassName(AAddress: UInt64; out AName: string): Boolean;
var
  mLength: Byte;
  mBytes: TBytes;
begin
  // ShortString: Längenbyte, dann der Name in UTF-8.
  AName := '';
  mLength := 0;
  Result := InImage(AAddress) and (FMemory.Read(AAddress, mLength, 1) = 1) and (mLength > 0);
  if not Result then
  begin
    Exit;
  end;
  SetLength(mBytes, mLength);
  Result := FMemory.Read(AAddress + 1, mBytes[0], mLength) = mLength;
  if Result then
  begin
    AName := TEncoding.UTF8.GetString(mBytes);
    Result := IsClassName(AName);
  end;
end;

function TAtlasObjectCounter.ReadClass(AVmt: UInt64; const ALayout: TAtlasVmtLayout;
  out AInfo: TClassInfo): Boolean;
var
  mSelf: UInt64;
  mName: UInt64;
  mSize: Integer;
begin
  AInfo := Default(TClassInfo);
  mSize := 0;
  Result := (AVmt > UInt64(ALayout.SelfBelow)) and ReadPointer(AVmt - UInt64(ALayout.SelfBelow), mSelf) and
    (mSelf = AVmt) and ReadPointer(AVmt - UInt64(ALayout.NameBelow), mName) and ReadClassName(mName, AInfo.Name) and
    (FMemory.Read(AVmt - UInt64(ALayout.SizeBelow), mSize, SizeOf(mSize)) = SizeOf(mSize)) and
    (mSize >= FPointerSize) and (mSize <= cMaxInstanceSize);
  AInfo.InstanceSize := mSize;
end;

function TAtlasObjectCounter.ClassOf(AVmt: UInt64): Integer;
var
  mLayout: TAtlasVmtLayout;
  mInfo: TClassInfo;
begin
  if FKnown.TryGetValue(AVmt, Result) then
  begin
    Exit;
  end;
  Result := -1;
  if (AVmt mod UInt64(FPointerSize) = 0) and InImage(AVmt) then
  begin
    for mLayout in FLayouts do
    begin
      if ReadClass(AVmt, mLayout, mInfo) then
      begin
        Result := FClasses.Add(mInfo);
        FCounts.Add(0);
        Break;
      end;
    end;
  end;
  FKnown.Add(AVmt, Result);
end;

procedure TAtlasObjectCounter.ScanBuffer(const ABuffer: TBytes; ALength: Integer);
var
  mOffset: Integer;
  mValue: UInt64;
  mClass: Integer;
begin
  mOffset := 0;
  while mOffset + FPointerSize <= ALength do
  begin
    mValue := 0;
    Move(ABuffer[mOffset], mValue, FPointerSize);
    if (mValue >= FImageLow) and (mValue < FImageHigh) then
    begin
      mClass := ClassOf(mValue);
      if mClass >= 0 then
      begin
        FCounts[mClass] := FCounts[mClass] + 1;
      end;
    end;
    Inc(mOffset, cAlignment);
  end;
end;

procedure TAtlasObjectCounter.ScanRegion(const ARegion: TAtlasMemoryRegion; var ABuffer: TBytes;
  var AScanned: UInt64);
var
  mAddress: UInt64;
  mEnd: UInt64;
  mPart: Integer;
  mRead: Integer;
begin
  mAddress := ARegion.Base;
  mEnd := ARegion.Base + ARegion.Size;
  while mAddress < mEnd do
  begin
    mPart := Integer(Min(UInt64(cChunkSize), mEnd - mAddress));
    mRead := FMemory.Read(mAddress, ABuffer[0], mPart);
    if mRead > 0 then
    begin
      ScanBuffer(ABuffer, mRead);
      Inc(AScanned, UInt64(mRead));
    end;
    Inc(mAddress, UInt64(mPart));
  end;
end;

function TAtlasObjectCounter.Collect: TArray<TAtlasClassCount>;
var
  mByName: TDictionary<string, Integer>;
  mList: TList<TAtlasClassCount>;
  mItem: TAtlasClassCount;
  mIndex: Integer;
  mAt: Integer;
begin
  // Gleichnamige Klassen (etwa in EXE und BPL) zusammenfassen.
  mByName := TDictionary<string, Integer>.Create;
  mList := TList<TAtlasClassCount>.Create;
  try
    for mIndex := 0 to FClasses.Count - 1 do
    begin
      if FCounts[mIndex] = 0 then
      begin
        Continue;
      end;
      if mByName.TryGetValue(FClasses[mIndex].Name, mAt) then
      begin
        mItem := mList[mAt];
        Inc(mItem.Count, FCounts[mIndex]);
        mList[mAt] := mItem;
        Continue;
      end;
      mItem := Default(TAtlasClassCount);
      mItem.Name := FClasses[mIndex].Name;
      mItem.Count := FCounts[mIndex];
      mItem.InstanceSize := FClasses[mIndex].InstanceSize;
      mByName.Add(mItem.Name, mList.Add(mItem));
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mByName.Free;
  end;
  TArray.Sort<TAtlasClassCount>(Result, TComparer<TAtlasClassCount>.Construct(
    function(const ALeft, ARight: TAtlasClassCount): Integer
    begin
      Result := CompareStr(ALeft.Name, ARight.Name);
    end));
end;

function TAtlasObjectCounter.Run: TAtlasObjectCount;
var
  mRegions: TArray<TAtlasMemoryRegion>;
  mRegion: TAtlasMemoryRegion;
  mImages: TList<TAtlasMemoryRegion>;
  mBuffer: TBytes;
begin
  Result := Default(TAtlasObjectCount);
  mRegions := FMemory.Regions;
  mImages := TList<TAtlasMemoryRegion>.Create;
  try
    FImageLow := High(UInt64);
    FImageHigh := 0;
    for mRegion in mRegions do
    begin
      if mRegion.Kind = TAtlasMemoryRegionKind.Image then
      begin
        mImages.Add(mRegion);
        FImageLow := Min(FImageLow, mRegion.Base);
        FImageHigh := Max(FImageHigh, mRegion.Base + mRegion.Size);
      end;
    end;
    mImages.Sort(TComparer<TAtlasMemoryRegion>.Construct(
      function(const ALeft, ARight: TAtlasMemoryRegion): Integer
      begin
        Result := Ord(ALeft.Base > ARight.Base) - Ord(ALeft.Base < ARight.Base);
      end));
    FImages := mImages.ToArray;
  finally
    mImages.Free;
  end;
  SetLength(mBuffer, cChunkSize);
  for mRegion in mRegions do
  begin
    if mRegion.Kind = TAtlasMemoryRegionKind.Data then
    begin
      ScanRegion(mRegion, mBuffer, Result.ScannedBytes);
    end;
  end;
  Result.Classes := Collect;
end;

{ TAtlasObjectCountCompare }

function RowOf(const AName: string; ACount, ABefore, AInstanceSize: Integer): TAtlasObjectCountRow;
begin
  Result.Name := AName;
  Result.Count := ACount;
  Result.Delta := ACount - ABefore;
  Result.Bytes := Int64(ACount) * AInstanceSize;
end;

function Matches(const AName, AFilter: string): Boolean;
begin
  Result := (AFilter = '') or (Pos(AFilter.ToLower, AName.ToLower) > 0);
end;

/// <summary>Anzahl von AName in ABase; 0, wenn die Klasse dort fehlt.</summary>
function CountIn(const ABase: TAtlasObjectCount; const AName: string): Integer;
var
  mAt: Integer;
begin
  Result := 0;
  mAt := ABase.IndexOf(AName);
  if mAt >= 0 then
  begin
    Result := ABase.Classes[mAt].Count;
  end;
end;

/// <summary>Klassen der Basis, die in ACurrent ganz fehlen, mit Anzahl 0.</summary>
procedure AddVanished(AList: TList<TAtlasObjectCountRow>; const ABase, ACurrent: TAtlasObjectCount;
  const AFilter: string);
var
  mClass: TAtlasClassCount;
begin
  for mClass in ABase.Classes do
  begin
    if (ACurrent.IndexOf(mClass.Name) < 0) and Matches(mClass.Name, AFilter) then
    begin
      AList.Add(RowOf(mClass.Name, 0, mClass.Count, mClass.InstanceSize));
    end;
  end;
end;

function CompareRows(const ALeft, ARight: TAtlasObjectCountRow): Integer;
begin
  Result := ARight.Delta - ALeft.Delta;
  if Result = 0 then
  begin
    Result := ARight.Count - ALeft.Count;
  end;
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.Name, ARight.Name);
  end;
end;

class function TAtlasObjectCountCompare.Rows(const ABase, ACurrent: TAtlasObjectCount; AHasBase: Boolean;
  const AFilter: string): TArray<TAtlasObjectCountRow>;
var
  mList: TList<TAtlasObjectCountRow>;
  mClass: TAtlasClassCount;
  mBefore: Integer;
  mFilter: string;
begin
  mFilter := Trim(AFilter);
  mList := TList<TAtlasObjectCountRow>.Create;
  try
    for mClass in ACurrent.Classes do
    begin
      if not Matches(mClass.Name, mFilter) then
      begin
        Continue;
      end;
      // Ohne Basis kein Zuwachs.
      mBefore := mClass.Count;
      if AHasBase then
      begin
        mBefore := CountIn(ABase, mClass.Name);
      end;
      mList.Add(RowOf(mClass.Name, mClass.Count, mBefore, mClass.InstanceSize));
    end;
    if AHasBase then
    begin
      AddVanished(mList, ABase, ACurrent, mFilter);
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
  TArray.Sort<TAtlasObjectCountRow>(Result, TComparer<TAtlasObjectCountRow>.Construct(CompareRows));
end;

end.
