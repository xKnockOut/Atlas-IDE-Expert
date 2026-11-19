unit Atlas.Core.Debug.ObjectMarks;

// Objekte beim Debuggen markieren (#839), Kern ohne IDE:
// - Tabelle Adresse → Etikett für die laufende Debug-Sitzung: Klasse beim Markieren, Farbe (eine von
//   cColorCount, die erste freie, änderbar), zuletzt gesehen (Ausdruck und Datei:Zeile).
// - „Vermutlich freigegeben“: Steht an der Adresse beim Halt eine andere Klasse, gilt die Markierung als frei;
//   ihr Etikett erscheint dann nirgends mehr, das Fenster zeigt den Zustand.
// - Klassenname aus dem Speicher des Programms (VMT), ohne Auswertung im Programm: Zeiger auf die VMT am Anfang des
//   Objekts, dort bei vmtClassName der Zeiger auf den ShortString. Lesen übernimmt ein Rückruf.
// - Vorschlag fürs Etikett aus Klasse und Namensfeld („TKunde“, „Meier“ → „Kunde Meier“).

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.InstanceBreakpoint;

type
  /// <summary>ACount Bytes ab AAddress aus dem angehaltenen Programm; False, wenn die Adresse nicht lesbar ist.
  /// </summary>
  TAtlasMemoryReader = reference to function(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean;

  TAtlasObjectMark = record
    Address: UInt64;
    Caption: string;
    /// <summary>Klasse beim Markieren; '' wenn sie sich nicht lesen ließ.</summary>
    TypeName: string;
    /// <summary>Farbe 0 bis TAtlasObjectMarks.cColorCount - 1.</summary>
    Color: Integer;
    /// <summary>Ausdruck, unter dem das Objekt zuletzt zu sehen war.</summary>
    LastExpression: string;
    /// <summary>„Kunden.pas:42“ des Halts, an dem es zuletzt zu sehen war.</summary>
    LastPlace: string;
    /// <summary>An der Adresse steht inzwischen eine andere Klasse.</summary>
    Freed: Boolean;
  end;

  TAtlasObjectMarks = class
  public const
    cColorCount = 8;
    /// <summary>Zeigergröße eines Win32- bzw. Win64-Programms.</summary>
    cPointerSize32 = 4;
    cPointerSize64 = 8;
    /// <summary>Eintrag vmtClassName der VMT in Zeigern vor ihrem Anfang.</summary>
    cClassNameSlot = -14;
    /// <summary>Ausdruck für die Adresse eines Objekts (%s: der Ausdruck).</summary>
    cAddressExpression = 'Pointer(%s)';
  private
    FItems: TArray<TAtlasObjectMark>;
    function IndexOf(AAddress: UInt64): Integer;
    function FreeColor: Integer;
  public
    /// <summary>AAddress mit ACaption markieren; schon markiert: Etikett und Klasse neu, Farbe bleibt.
    /// False für Adresse 0 oder leeres Etikett.</summary>
    function Mark(AAddress: UInt64; const ACaption, ATypeName, AExpression, APlace: string): Boolean;
    /// <summary>True, wenn es die Markierung gab.</summary>
    function Remove(AAddress: UInt64): Boolean;
    /// <summary>Farbe wechseln: AColor modulo cColorCount. True, wenn es die Markierung gibt.</summary>
    function SetColor(AAddress: UInt64; AColor: Integer): Boolean;
    /// <summary>Nicht freigegebene Markierung zu AAddress.</summary>
    function Find(AAddress: UInt64; out AMark: TAtlasObjectMark): Boolean;
    /// <summary>Etikett zu AAddress; '' ohne Markierung oder vermutlich freigegeben.</summary>
    function CaptionOf(AAddress: UInt64): string;
    /// <summary>Objekt unter AExpression an APlace gesehen. True, wenn sich etwas geändert hat.</summary>
    function Seen(AAddress: UInt64; const AExpression, APlace: string): Boolean;
    /// <summary>Beim Halt: An AAddress steht ATypeName ('' = nicht lesbar, dann bleibt alles). Eine andere Klasse
    /// als beim Markieren macht die Markierung zu „vermutlich freigegeben“. True, wenn sich das geändert hat.
    /// </summary>
    function Check(AAddress: UInt64; const ATypeName: string): Boolean;
    /// <summary>Alle Markierungen in der Reihenfolge des Markierens.</summary>
    function Items: TArray<TAtlasObjectMark>;
    /// <summary>Etiketten für die Anzeige der Haltepunkte nur für ein Objekt (#857), ohne freigegebene.</summary>
    function Labels: TArray<TAtlasObjectLabel>;
    function Count: Integer;
    procedure Clear;
    /// <summary>Etikett zum Vorschlagen: Klasse ohne Unit und ohne führendes T vor einem Großbuchstaben, dahinter
    /// ANameValue ohne Anführungszeichen („TKunde“, „'Meier'“ → „Kunde Meier“).</summary>
    class function Suggest(const ATypeName, ANameValue: string): string; static;
    /// <summary>Sieht der Wert aus wie ein Objekt, dessen Adresse sich lohnt? Felder in Klammern („(FNr: 4; …)“)
    /// oder eine Adresse; nicht nil, Zahlen, Strings, Mengen.</summary>
    class function LooksLikeObject(const AValueText: string): Boolean; static;
    /// <summary>AValue mit dem Etikett nach AFormat (%0:s Wert, %1:s Etikett); ohne Etikett AValue.</summary>
    class function Decorate(const AValue, ACaption, AFormat: string): string; static;
    /// <summary>Klassenname des Objekts an AAddress aus seiner VMT; APointerSize 4 (Win32) oder 8 (Win64). '' wenn
    /// nicht lesbar oder kein gültiger Name.</summary>
    class function ReadClassName(AAddress: UInt64; APointerSize: Integer;
      const ARead: TAtlasMemoryReader): string; static;
    /// <summary>Abstand von vmtClassName zum Anfang der VMT.</summary>
    class function ClassNameOffset(APointerSize: Integer): Int64; static;
    /// <summary>„Kunden.pas:42“ (ALine ab 1); ohne Datei ''.</summary>
    class function PlaceText(const AFileName: string; ALine: Integer): string; static;
  end;

implementation

uses
  System.StrUtils;

{ TAtlasObjectMarks }

function TAtlasObjectMarks.IndexOf(AAddress: UInt64): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FItems) do
  begin
    if FItems[mIndex].Address = AAddress then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasObjectMarks.FreeColor: Integer;
var
  mUsed: array[0..cColorCount - 1] of Boolean;
  mMark: TAtlasObjectMark;
  mColor: Integer;
begin
  for mColor := 0 to cColorCount - 1 do
  begin
    mUsed[mColor] := False;
  end;
  for mMark in FItems do
  begin
    if not mMark.Freed then
    begin
      mUsed[mMark.Color] := True;
    end;
  end;
  for mColor := 0 to cColorCount - 1 do
  begin
    if not mUsed[mColor] then
    begin
      Exit(mColor);
    end;
  end;
  // Alle vergeben: reihum weiter.
  Result := Length(FItems) mod cColorCount;
end;

function TAtlasObjectMarks.Mark(AAddress: UInt64; const ACaption, ATypeName, AExpression, APlace: string): Boolean;
var
  mIndex: Integer;
  mMark: TAtlasObjectMark;
begin
  Result := (AAddress <> 0) and (Trim(ACaption) <> '');
  if not Result then
  begin
    Exit;
  end;
  mIndex := IndexOf(AAddress);
  if mIndex >= 0 then
  begin
    FItems[mIndex].Caption := Trim(ACaption);
    FItems[mIndex].TypeName := Trim(ATypeName);
    FItems[mIndex].Freed := False;
    Seen(AAddress, AExpression, APlace);
    Exit;
  end;
  mMark := Default(TAtlasObjectMark);
  mMark.Address := AAddress;
  mMark.Caption := Trim(ACaption);
  mMark.TypeName := Trim(ATypeName);
  mMark.Color := FreeColor;
  mMark.LastExpression := Trim(AExpression);
  mMark.LastPlace := APlace;
  FItems := FItems + [mMark];
end;

function TAtlasObjectMarks.Remove(AAddress: UInt64): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AAddress);
  Result := mIndex >= 0;
  if Result then
  begin
    Delete(FItems, mIndex, 1);
  end;
end;

function TAtlasObjectMarks.SetColor(AAddress: UInt64; AColor: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AAddress);
  Result := mIndex >= 0;
  if Result then
  begin
    AColor := AColor mod cColorCount;
    if AColor < 0 then
    begin
      Inc(AColor, cColorCount);
    end;
    FItems[mIndex].Color := AColor;
  end;
end;

function TAtlasObjectMarks.Find(AAddress: UInt64; out AMark: TAtlasObjectMark): Boolean;
var
  mIndex: Integer;
begin
  AMark := Default(TAtlasObjectMark);
  mIndex := IndexOf(AAddress);
  Result := (mIndex >= 0) and not FItems[mIndex].Freed;
  if Result then
  begin
    AMark := FItems[mIndex];
  end;
end;

function TAtlasObjectMarks.CaptionOf(AAddress: UInt64): string;
var
  mMark: TAtlasObjectMark;
begin
  Result := '';
  if Find(AAddress, mMark) then
  begin
    Result := mMark.Caption;
  end;
end;

function TAtlasObjectMarks.Seen(AAddress: UInt64; const AExpression, APlace: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AAddress);
  Result := (mIndex >= 0) and not FItems[mIndex].Freed and (Trim(AExpression) <> '') and
    ((FItems[mIndex].LastExpression <> Trim(AExpression)) or (FItems[mIndex].LastPlace <> APlace));
  if Result then
  begin
    FItems[mIndex].LastExpression := Trim(AExpression);
    FItems[mIndex].LastPlace := APlace;
  end;
end;

function TAtlasObjectMarks.Check(AAddress: UInt64; const ATypeName: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AAddress);
  // Unbekannte Klasse beim Markieren oder jetzt nicht lesbar: keine Aussage.
  Result := (mIndex >= 0) and not FItems[mIndex].Freed and (Trim(ATypeName) <> '') and
    (FItems[mIndex].TypeName <> '') and not SameText(FItems[mIndex].TypeName, Trim(ATypeName));
  if Result then
  begin
    FItems[mIndex].Freed := True;
  end;
end;

function TAtlasObjectMarks.Items: TArray<TAtlasObjectMark>;
begin
  Result := Copy(FItems);
end;

function TAtlasObjectMarks.Labels: TArray<TAtlasObjectLabel>;
var
  mMark: TAtlasObjectMark;
  mLabel: TAtlasObjectLabel;
begin
  Result := nil;
  for mMark in FItems do
  begin
    if not mMark.Freed then
    begin
      mLabel := Default(TAtlasObjectLabel);
      mLabel.Address := mMark.Address;
      mLabel.Caption := mMark.Caption;
      Result := Result + [mLabel];
    end;
  end;
end;

function TAtlasObjectMarks.Count: Integer;
begin
  Result := Length(FItems);
end;

procedure TAtlasObjectMarks.Clear;
begin
  FItems := nil;
end;

class function TAtlasObjectMarks.Suggest(const ATypeName, ANameValue: string): string;
var
  mType, mName: string;
  mDot: Integer;
begin
  mType := Trim(ATypeName);
  mDot := LastDelimiter('.', mType);
  if mDot > 0 then
  begin
    mType := Copy(mType, mDot + 1, MaxInt);
  end;
  if (Length(mType) > 1) and (mType[1] = 'T') and CharInSet(mType[2], ['A'..'Z']) then
  begin
    mType := Copy(mType, 2, MaxInt);
  end;
  mName := Trim(ANameValue);
  if (Length(mName) >= 2) and (mName[1] = '''') and (mName[Length(mName)] = '''') then
  begin
    mName := Copy(mName, 2, Length(mName) - 2).Replace('''''', '''');
  end;
  Result := Trim(mType + ' ' + Trim(mName));
end;

class function TAtlasObjectMarks.LooksLikeObject(const AValueText: string): Boolean;
var
  mText: string;
  mAddress: UInt64;
begin
  mText := Trim(AValueText);
  if mText = '' then
  begin
    Exit(False);
  end;
  // Zahlen stehen dezimal da: Eine Adresse erkennt Atlas nur an ihrem Präfix.
  Result := (mText[1] = '(') or ((CharInSet(mText[1], ['$', ':']) or StartsText('0x', mText) or
    StartsText('Pointer(', mText)) and TAtlasInstanceBreakpoint.TryParseAddress(mText, mAddress));
end;

class function TAtlasObjectMarks.Decorate(const AValue, ACaption, AFormat: string): string;
begin
  Result := AValue;
  if ACaption <> '' then
  begin
    Result := Format(AFormat, [AValue, ACaption]);
  end;
end;

class function TAtlasObjectMarks.ClassNameOffset(APointerSize: Integer): Int64;
begin
  // vmtClassName: -56 unter Win32, unter Win64 doppelt so weit (alle Einträge davor sind Zeiger).
  Result := cClassNameSlot * Int64(APointerSize);
end;

/// <summary>Zeiger der Größe APointerSize aus ABytes ab 0.</summary>
function PointerOf(const ABytes: TBytes; APointerSize: Integer): UInt64;
const
  cBitsPerByte = 8;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := APointerSize - 1 downto 0 do
  begin
    Result := (Result shl cBitsPerByte) or ABytes[mIndex];
  end;
end;

/// <summary>Gültige Zeichen eines Klassennamens: Buchstaben, Ziffern, _ und . sowie &lt; &gt; , für Generics.
/// </summary>
function IsNameChar(AByte: Byte): Boolean;
begin
  Result := AByte in [Ord('A')..Ord('Z'), Ord('a')..Ord('z'), Ord('0')..Ord('9'), Ord('_'), Ord('.'), Ord('<'),
    Ord('>'), Ord(',')];
end;

/// <summary>Zeiger der Größe APointerSize an AAddress; False, wenn nicht lesbar.</summary>
function ReadPointer(const ARead: TAtlasMemoryReader; AAddress: UInt64; APointerSize: Integer;
  out AValue: UInt64): Boolean;
var
  mBytes: TBytes;
begin
  AValue := 0;
  Result := ARead(AAddress, APointerSize, mBytes) and (Length(mBytes) >= APointerSize);
  if Result then
  begin
    AValue := PointerOf(mBytes, APointerSize);
  end;
end;

/// <summary>ShortString an AAddress: Länge, dann die Zeichen; '' wenn nicht lesbar, leer oder mit Zeichen, die in
/// keinem Klassennamen vorkommen (dann steht dort kein Objekt mehr).</summary>
function ReadName(const ARead: TAtlasMemoryReader; AAddress: UInt64): string;
var
  mBytes: TBytes;
  mLength, mIndex: Integer;
begin
  Result := '';
  mLength := 0;
  if (AAddress <> 0) and ARead(AAddress, 1, mBytes) and (Length(mBytes) = 1) then
  begin
    mLength := mBytes[0];
  end;
  if (mLength = 0) or not ARead(AAddress + 1, mLength, mBytes) or (Length(mBytes) < mLength) then
  begin
    Exit;
  end;
  SetLength(Result, mLength);
  for mIndex := 0 to mLength - 1 do
  begin
    if not IsNameChar(mBytes[mIndex]) then
    begin
      Exit('');
    end;
    Result[mIndex + 1] := Char(mBytes[mIndex]);
  end;
end;

class function TAtlasObjectMarks.ReadClassName(AAddress: UInt64; APointerSize: Integer;
  const ARead: TAtlasMemoryReader): string;
var
  mVmt, mNameAt, mOffset: UInt64;
begin
  Result := '';
  if (AAddress = 0) or not (APointerSize in [cPointerSize32, cPointerSize64]) or not Assigned(ARead) then
  begin
    Exit;
  end;
  mOffset := UInt64(-ClassNameOffset(APointerSize));
  // Objekt → VMT → Zeiger auf den Namen bei vmtClassName.
  if ReadPointer(ARead, AAddress, APointerSize, mVmt) and (mVmt >= mOffset) and
    ReadPointer(ARead, mVmt - mOffset, APointerSize, mNameAt) then
  begin
    Result := ReadName(ARead, mNameAt);
  end;
end;

class function TAtlasObjectMarks.PlaceText(const AFileName: string; ALine: Integer): string;
begin
  Result := '';
  if AFileName <> '' then
  begin
    // Der Debugger liefert Windows-Pfade; unter Linux (Tests) trennt ExtractFileName nur an /.
    Result := Format('%s:%d', [Copy(AFileName, LastDelimiter('\/', AFileName) + 1, MaxInt), ALine]);
  end;
end;

end.
