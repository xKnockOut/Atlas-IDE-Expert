unit Atlas.Core.Debug.InstanceBreakpoint;

// Haltepunkt nur für ein bestimmtes Objekt (#857), Kern ohne IDE:
// - Adressbedingung „Pointer(Self) = Pointer($0A3F1C20)“ (für den
//   Win64-Debugger wahlweise „NativeUInt(Self) = $0A3F1C20“) bzw.
//   Feldbedingung „Nr = 4711“ an eine vorhandene Bedingung mit „and“ hängen.
//   Die vorhandene Bedingung bleibt erhalten; jeder Teil steht in Klammern,
//   sobald er mit einem anderen verknüpft ist.
// - Adressbedingungen erkennen, entfernen und durch eine Feldbedingung
//   ersetzen (Adressen gelten nur in einer Sitzung).
// - Anzeige: Adressteile durch das Etikett des Objekts ersetzen.
// - Auswahl der Felder von Self für „Nur wenn …“: einfache Werte aus dem
//   Ergebnis von „Self“, keine Zeiger (die gelten auch nur in einer Sitzung).
// - Hat die Routine an einer Zeile ein Self? Textprüfung am Kopf der
//   umgebenden Routine auf oberster Ebene: qualifizierter Name, keine
//   Klassenmethode.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.Evaluate;

type
  {$SCOPEDENUMS ON}
  /// <summary>Schreibweise der Adressbedingung. Pointer: Vorgabe; NativeUInt: falls ein Debugger den
  /// Zeigervergleich nicht auswertet.</summary>
  TAtlasInstanceStyle = (Pointer, NativeUInt);
  {$SCOPEDENUMS OFF}

  /// <summary>Etikett eines Objekts (#839) zu seiner Adresse.</summary>
  TAtlasObjectLabel = record
    Address: UInt64;
    Caption: string;
  end;

  TAtlasInstanceBreakpoint = class
  public const
    /// <summary>Ausdruck für die Adresse des aktuellen Objekts.</summary>
    cSelfAddressExpression = 'Pointer(Self)';
    /// <summary>Ausdruck für die Felder des aktuellen Objekts (mit Feldnamen).</summary>
    cSelfExpression = 'Self,r';
  public
    /// <summary>Adresse aus dem Ergebnis des Debuggers: „$A3F1C20“, „:0A3F1C20“, „Pointer($A3F1C20)“, „0x…“.
    /// False für nil, 0 und alles andere.</summary>
    class function TryParseAddress(const AValue: string; out AAddress: UInt64): Boolean; static;
    /// <summary>„$0A3F1C20“: mindestens acht Stellen, groß.</summary>
    class function AddressText(AAddress: UInt64): string; static;
    /// <summary>Bedingung „nur dieses Objekt“.</summary>
    class function AddressCondition(AAddress: UInt64; AStyle: TAtlasInstanceStyle): string; static;
    /// <summary>Feldbedingung „Nr = 4711“; '' ohne Feld oder Wert.</summary>
    class function FieldCondition(const AField, AValue: string): string; static;
    /// <summary>Ist ACondition eine Adressbedingung (beide Schreibweisen, Groß/klein und Leerzeichen egal)?
    /// </summary>
    class function IsAddressCondition(const ACondition: string; out AAddress: UInt64): Boolean; static;
    /// <summary>Teile einer Bedingung, die mit „and“ auf oberster Ebene verknüpft sind, ohne äußere Klammern.
    /// Steht auf oberster Ebene „or“ oder „xor“, ist die ganze Bedingung ein Teil.</summary>
    class function Conjuncts(const ACondition: string): TArray<string>; static;
    /// <summary>Teile mit „and“ verbinden; ab zwei Teilen jeder in Klammern, wenn er nicht schon ganz in
    /// Klammern steht oder ein einzelner Bezeichner ist.</summary>
    class function Join(const AParts: TArray<string>): string; static;
    /// <summary>AExisting und AAdded mit „and“; eine gleiche Bedingung kommt nicht doppelt hinein.</summary>
    class function Combine(const AExisting, AAdded: string): string; static;
    /// <summary>AExisting auf das Objekt an AAddress einschränken; eine frühere Adressbedingung wird ersetzt.
    /// </summary>
    class function RestrictToObject(const AExisting: string; AAddress: UInt64;
      AStyle: TAtlasInstanceStyle): string; static;
    /// <summary>Enthält die Bedingung einen Adressteil?</summary>
    class function HasAddressCondition(const ACondition: string): Boolean; static;
    /// <summary>Adressen der Adressteile in ACondition.</summary>
    class function Addresses(const ACondition: string): TArray<UInt64>; static;
    /// <summary>ACondition ohne Adressteile; '' wenn nichts übrig bleibt.</summary>
    class function WithoutAddress(const ACondition: string): string; static;
    /// <summary>Adressteile durch die Feldbedingung ersetzen; ohne Adressteil unverändert.</summary>
    class function ReplaceAddress(const ACondition, AFieldCondition: string): string; static;
    /// <summary>Indizes der Bedingungen mit Adressteil (verwaiste Bedingungen beim nächsten Start).</summary>
    class function Orphans(const AConditions: TArray<string>): TArray<Integer>; static;
    /// <summary>Etikett zu AAddress aus ALabels; sonst die Adresse als Text.</summary>
    class function ObjectCaption(AAddress: UInt64; const ALabels: TArray<TAtlasObjectLabel>): string; static;
    /// <summary>Bedingung zum Anzeigen: Adressteile als AObjectFormat (mit %s für das Etikett), der Rest
    /// unverändert.</summary>
    class function DisplayText(const ACondition, AObjectFormat: string;
      const ALabels: TArray<TAtlasObjectLabel>): string; static;
    /// <summary>Felder mit einfachem Wert aus dem Ergebnis von cSelfExpression, auch aus Vorfahren (Teile ohne
    /// Namen); ohne Zeiger, Objekte und nil, ohne Doppelte.</summary>
    class function FieldChoices(const ASelfValue: string): TAtlasEvalParts; static;
    /// <summary>Hat die Routine, in der Zeile ALine (ab 0) liegt, ein Self? Kopf auf oberster Ebene mit
    /// qualifiziertem Namen und ohne „class“ davor; verschachtelte Routinen sehen das Self ihrer Methode.
    /// </summary>
    class function RoutineHasSelf(const ALines: TArray<string>; ALine: Integer): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Chars;

const
  cHexDigits = ['0'..'9', 'a'..'f', 'A'..'F'];
  cMinAddressDigits = 8;
  cMaxAddressDigits = 16;
  cBitsPerHexDigit = 4;
  // Ausdrücke für den Debugger, keine Texte für Menschen.
  cPointerCondition = 'Pointer(Self) = Pointer(%s)';
  cNativeUIntCondition = 'NativeUInt(Self) = %s';
  cAndWord = 'and';
  cOrWords: array[0..1] of string = ('or', 'xor');
  cRoutineWords: array[0..4] of string = ('procedure', 'function', 'constructor', 'destructor', 'operator');

/// <summary>Index (1-basiert) hinter dem String, der bei AIndex beginnt ('' zählt als Inhalt); hinter dem Text,
/// wenn er nicht endet.</summary>
function SkipQuoted(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while Result <= Length(AText) do
  begin
    if AText[Result] <> '''' then
    begin
      Inc(Result);
      Continue;
    end;
    if (Result < Length(AText)) and (AText[Result + 1] = '''') then
    begin
      Inc(Result, 2);
      Continue;
    end;
    Exit(Result + 1);
  end;
end;

/// <summary>Steht bei AIndex das Wort AWord für sich (nicht Teil eines Bezeichners)?</summary>
function WordAt(const AText: string; AIndex: Integer; const AWord: string): Boolean;
var
  mAfter: Integer;
begin
  mAfter := AIndex + Length(AWord);
  Result := SameText(Copy(AText, AIndex, Length(AWord)), AWord) and
    ((AIndex = 1) or not TTextChars.IsIdentChar(AText[AIndex - 1])) and
    ((mAfter > Length(AText)) or not TTextChars.IsIdentChar(AText[mAfter]));
end;

function IsOrWordAt(const AText: string; AIndex: Integer): Boolean;
var
  mWord: string;
begin
  for mWord in cOrWords do
  begin
    if WordAt(AText, AIndex, mWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Stellen (1-basiert) der „and“ auf oberster Ebene; nil, wenn dort auch „or“/„xor“ steht.</summary>
function TopLevelAnds(const AText: string): TArray<Integer>;
var
  mIndex, mDepth: Integer;
begin
  Result := nil;
  mDepth := 0;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    case AText[mIndex] of
      '''':
        begin
          mIndex := SkipQuoted(AText, mIndex);
          Continue;
        end;
      '(', '[':
        Inc(mDepth);
      ')', ']':
        Dec(mDepth);
    end;
    if (mDepth = 0) and IsOrWordAt(AText, mIndex) then
    begin
      Exit(nil);
    end;
    if (mDepth = 0) and WordAt(AText, mIndex, cAndWord) then
    begin
      Result := Result + [mIndex];
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Schließt die Klammer am Anfang die am Ende?</summary>
function IsWrapped(const AText: string): Boolean;
var
  mIndex, mDepth: Integer;
begin
  Result := (Length(AText) >= 2) and (AText[1] = '(') and (AText[Length(AText)] = ')');
  mDepth := 0;
  mIndex := 1;
  while Result and (mIndex <= Length(AText)) do
  begin
    case AText[mIndex] of
      '''':
        begin
          mIndex := SkipQuoted(AText, mIndex);
          Continue;
        end;
      '(':
        Inc(mDepth);
      ')':
        begin
          Dec(mDepth);
          Result := (mDepth > 0) or (mIndex = Length(AText));
        end;
    end;
    Inc(mIndex);
  end;
end;

function Unwrap(const AText: string): string;
begin
  Result := Trim(AText);
  while IsWrapped(Result) do
  begin
    Result := Trim(Copy(Result, 2, Length(Result) - 2));
  end;
end;

function IsIdentifier(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (AText <> '') and TTextChars.IsIdentStart(AText[1]);
  for mIndex := 2 to Length(AText) do
  begin
    Result := Result and (TTextChars.IsIdentChar(AText[mIndex]) or (AText[mIndex] = '.'));
  end;
end;

/// <summary>Ohne Leerzeichen und klein: Vergleich von Bedingungen unabhängig von der Schreibweise.</summary>
function Compact(const AText: string): string;
var
  C: Char;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    for C in AText do
    begin
      if not CharInSet(C, [' ', #9, #13, #10]) then
      begin
        mBuilder.Append(C);
      end;
    end;
    Result := LowerCase(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

function HexValue(AChar: Char): Integer;
begin
  case AChar of
    '0'..'9':
      Result := Ord(AChar) - Ord('0');
    'a'..'f':
      Result := Ord(AChar) - Ord('a') + 10;
  else
    Result := Ord(AChar) - Ord('A') + 10;
  end;
end;

/// <summary>Hexadezimalzahl am Anfang von AText (mit $ davor, höchstens 16 Stellen), AText dahinter in ARest.
/// </summary>
function TakeHex(const AText: string; out AValue: UInt64; out ARest: string): Boolean;
var
  mIndex: Integer;
begin
  AValue := 0;
  mIndex := 2;
  Result := (AText <> '') and (AText[1] = '$');
  while Result and (mIndex <= Length(AText)) and CharInSet(AText[mIndex], cHexDigits) do
  begin
    AValue := (AValue shl cBitsPerHexDigit) or UInt64(HexValue(AText[mIndex]));
    Inc(mIndex);
  end;
  Result := Result and (mIndex > 2) and (mIndex - 2 <= cMaxAddressDigits);
  ARest := Copy(AText, mIndex, MaxInt);
end;

/// <summary>Rest von AText hinter APrefix; False, wenn AText nicht mit APrefix beginnt.</summary>
function After(const AText, APrefix: string; out ARest: string): Boolean;
begin
  Result := StartsStr(APrefix, AText);
  ARest := Copy(AText, Length(APrefix) + 1, MaxInt);
end;

/// <summary>Kopf einer Routine auf oberster Ebene: Zeile beginnt (ohne Einrückung) mit einem Routinenwort,
/// davor höchstens „class“. AName ist der Name samt Qualifizierung.</summary>
function RoutineHeader(const ALine: string; out AName: string; out AClassMethod: Boolean): Boolean;
var
  mText, mWord: string;
  mEnd: Integer;
begin
  Result := False;
  if (ALine = '') or not TTextChars.IsIdentStart(ALine[1]) then
  begin
    Exit;
  end;
  mText := ALine;
  AClassMethod := WordAt(mText, 1, 'class');
  if AClassMethod then
  begin
    mText := TrimLeft(Copy(mText, Length('class') + 1, MaxInt));
  end;
  for mWord in cRoutineWords do
  begin
    if WordAt(mText, 1, mWord) then
    begin
      mText := TrimLeft(Copy(mText, Length(mWord) + 1, MaxInt));
      mEnd := 1;
      while (mEnd <= Length(mText)) and (TTextChars.IsIdentChar(mText[mEnd]) or (mText[mEnd] = '.')) do
      begin
        Inc(mEnd);
      end;
      AName := Copy(mText, 1, mEnd - 1);
      Exit(AName <> '');
    end;
  end;
end;

/// <summary>Zeile, die eine Routine auf oberster Ebene abschließt oder einen neuen Abschnitt beginnt.</summary>
function EndsRoutines(const ALine: string): Boolean;
begin
  Result := StartsText('end;', ALine) or StartsText('end.', ALine) or WordAt(ALine, 1, 'implementation') or
    WordAt(ALine, 1, 'initialization') or WordAt(ALine, 1, 'finalization') or WordAt(ALine, 1, 'type');
end;

function LooksLikePointer(const AValue: string): Boolean;
var
  mText: string;
begin
  mText := Trim(AValue);
  Result := SameText(mText, 'nil') or StartsStr('$', mText) or StartsStr(':', mText) or
    StartsText('Pointer(', mText) or StartsText('0x', mText) or TAtlasEvalText.IsStructured(mText);
end;

procedure CollectFields(const AValue: string; var AFields: TAtlasEvalParts);
var
  mPart, mKnown: TAtlasEvalPart;
  mDouble: Boolean;
begin
  for mPart in TAtlasEvalText.Parts(AValue) do
  begin
    if mPart.Indexed then
    begin
      CollectFields(mPart.Value, AFields);
      Continue;
    end;
    if LooksLikePointer(mPart.Value) or not TAtlasEvalText.IsSimple(mPart.Value) then
    begin
      Continue;
    end;
    mDouble := False;
    for mKnown in AFields do
    begin
      mDouble := mDouble or SameText(mKnown.Name, mPart.Name);
    end;
    if not mDouble then
    begin
      AFields := AFields + [mPart];
    end;
  end;
end;

{ TAtlasInstanceBreakpoint }

class function TAtlasInstanceBreakpoint.TryParseAddress(const AValue: string; out AAddress: UInt64): Boolean;
var
  mText, mRest: string;
begin
  mText := Trim(AValue);
  if StartsText('Pointer(', mText) and EndsStr(')', mText) then
  begin
    mText := Trim(Copy(mText, Length('Pointer(') + 1, Length(mText) - Length('Pointer(') - 1));
  end;
  if StartsText('0x', mText) then
  begin
    mText := Copy(mText, Length('0x') + 1, MaxInt);
  end
  else if StartsStr(':', mText) or StartsStr('$', mText) then
  begin
    mText := Copy(mText, 2, MaxInt);
  end;
  Result := TakeHex('$' + mText, AAddress, mRest) and (mRest = '') and (AAddress <> 0);
end;

class function TAtlasInstanceBreakpoint.AddressText(AAddress: UInt64): string;
begin
  Result := '$' + IntToHex(AAddress, cMinAddressDigits);
end;

class function TAtlasInstanceBreakpoint.AddressCondition(AAddress: UInt64; AStyle: TAtlasInstanceStyle): string;
begin
  if AStyle = TAtlasInstanceStyle.NativeUInt then
  begin
    Result := Format(cNativeUIntCondition, [AddressText(AAddress)]);
  end
  else
  begin
    Result := Format(cPointerCondition, [AddressText(AAddress)]);
  end;
end;

class function TAtlasInstanceBreakpoint.FieldCondition(const AField, AValue: string): string;
begin
  Result := '';
  if (Trim(AField) <> '') and (Trim(AValue) <> '') then
  begin
    Result := Trim(AField) + ' = ' + Trim(AValue);
  end;
end;

class function TAtlasInstanceBreakpoint.IsAddressCondition(const ACondition: string; out AAddress: UInt64): Boolean;
var
  mText, mNumber, mRest: string;
begin
  mText := Compact(Unwrap(ACondition));
  // Eigene Variable für den Rest: Ein out-Parameter wird beim Aufruf geleert, auch wenn er zugleich die Eingabe
  // ist.
  if After(mText, 'pointer(self)=pointer(', mNumber) then
  begin
    Exit(TakeHex(mNumber, AAddress, mRest) and (mRest = ')'));
  end;
  if After(mText, 'nativeuint(self)=', mNumber) then
  begin
    Exit(TakeHex(mNumber, AAddress, mRest) and (mRest = ''));
  end;
  Result := False;
end;

class function TAtlasInstanceBreakpoint.Conjuncts(const ACondition: string): TArray<string>;
var
  mText, mPart: string;
  mAnds: TArray<Integer>;
  mStart, mAnd: Integer;
begin
  Result := nil;
  mText := Unwrap(ACondition);
  if mText = '' then
  begin
    Exit;
  end;
  mAnds := TopLevelAnds(mText);
  mStart := 1;
  for mAnd in mAnds do
  begin
    mPart := Unwrap(Copy(mText, mStart, mAnd - mStart));
    if mPart <> '' then
    begin
      Result := Result + [mPart];
    end;
    mStart := mAnd + Length(cAndWord);
  end;
  mPart := Unwrap(Copy(mText, mStart, MaxInt));
  if mPart <> '' then
  begin
    Result := Result + [mPart];
  end;
end;

class function TAtlasInstanceBreakpoint.Join(const AParts: TArray<string>): string;
var
  mPart, mText: string;
begin
  Result := '';
  for mPart in AParts do
  begin
    mText := Trim(mPart);
    if mText = '' then
    begin
      Continue;
    end;
    if (Length(AParts) > 1) and not IsWrapped(mText) and not IsIdentifier(mText) then
    begin
      mText := '(' + mText + ')';
    end;
    if Result <> '' then
    begin
      Result := Result + ' ' + cAndWord + ' ';
    end;
    Result := Result + mText;
  end;
end;

class function TAtlasInstanceBreakpoint.Combine(const AExisting, AAdded: string): string;
var
  mParts: TArray<string>;
  mPart, mKnown: string;
  mDouble: Boolean;
begin
  mParts := Conjuncts(AExisting);
  for mPart in Conjuncts(AAdded) do
  begin
    mDouble := False;
    for mKnown in mParts do
    begin
      mDouble := mDouble or (Compact(mKnown) = Compact(mPart));
    end;
    if not mDouble then
    begin
      mParts := mParts + [mPart];
    end;
  end;
  Result := Join(mParts);
end;

class function TAtlasInstanceBreakpoint.RestrictToObject(const AExisting: string; AAddress: UInt64;
  AStyle: TAtlasInstanceStyle): string;
begin
  Result := Combine(WithoutAddress(AExisting), AddressCondition(AAddress, AStyle));
end;

class function TAtlasInstanceBreakpoint.Addresses(const ACondition: string): TArray<UInt64>;
var
  mPart: string;
  mAddress: UInt64;
begin
  Result := nil;
  for mPart in Conjuncts(ACondition) do
  begin
    if IsAddressCondition(mPart, mAddress) then
    begin
      Result := Result + [mAddress];
    end;
  end;
end;

class function TAtlasInstanceBreakpoint.HasAddressCondition(const ACondition: string): Boolean;
begin
  Result := Length(Addresses(ACondition)) > 0;
end;

class function TAtlasInstanceBreakpoint.WithoutAddress(const ACondition: string): string;
var
  mParts, mKept: TArray<string>;
  mPart: string;
  mAddress: UInt64;
begin
  mParts := Conjuncts(ACondition);
  mKept := nil;
  for mPart in mParts do
  begin
    if not IsAddressCondition(mPart, mAddress) then
    begin
      mKept := mKept + [mPart];
    end;
  end;
  if Length(mKept) = Length(mParts) then
  begin
    Exit(Trim(ACondition));
  end;
  Result := Join(mKept);
end;

class function TAtlasInstanceBreakpoint.ReplaceAddress(const ACondition, AFieldCondition: string): string;
begin
  if not HasAddressCondition(ACondition) then
  begin
    Exit(Trim(ACondition));
  end;
  Result := Combine(WithoutAddress(ACondition), AFieldCondition);
end;

class function TAtlasInstanceBreakpoint.Orphans(const AConditions: TArray<string>): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AConditions) do
  begin
    if HasAddressCondition(AConditions[mIndex]) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

class function TAtlasInstanceBreakpoint.ObjectCaption(AAddress: UInt64;
  const ALabels: TArray<TAtlasObjectLabel>): string;
var
  mLabel: TAtlasObjectLabel;
begin
  for mLabel in ALabels do
  begin
    if (mLabel.Address = AAddress) and (Trim(mLabel.Caption) <> '') then
    begin
      Exit(Trim(mLabel.Caption));
    end;
  end;
  Result := AddressText(AAddress);
end;

class function TAtlasInstanceBreakpoint.DisplayText(const ACondition, AObjectFormat: string;
  const ALabels: TArray<TAtlasObjectLabel>): string;
var
  mParts: TArray<string>;
  mIndex: Integer;
  mAddress: UInt64;
begin
  if not HasAddressCondition(ACondition) then
  begin
    Exit(Trim(ACondition));
  end;
  mParts := Conjuncts(ACondition);
  for mIndex := 0 to High(mParts) do
  begin
    if IsAddressCondition(mParts[mIndex], mAddress) then
    begin
      mParts[mIndex] := Format(AObjectFormat, [ObjectCaption(mAddress, ALabels)]);
    end;
  end;
  // Etiketten sind Text, keine Ausdrücke: ohne Klammern verbinden.
  Result := '';
  for mIndex := 0 to High(mParts) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ' ' + cAndWord + ' ';
    end;
    Result := Result + mParts[mIndex];
  end;
end;

class function TAtlasInstanceBreakpoint.FieldChoices(const ASelfValue: string): TAtlasEvalParts;
begin
  Result := nil;
  CollectFields(ASelfValue, Result);
end;

class function TAtlasInstanceBreakpoint.RoutineHasSelf(const ALines: TArray<string>; ALine: Integer): Boolean;
var
  mIndex: Integer;
  mName: string;
  mClassMethod: Boolean;
begin
  Result := False;
  if ALine > High(ALines) then
  begin
    Exit;
  end;
  for mIndex := ALine downto 0 do
  begin
    if RoutineHeader(ALines[mIndex], mName, mClassMethod) then
    begin
      Exit(not mClassMethod and (Pos('.', mName) > 0));
    end;
    if (mIndex < ALine) and EndsRoutines(ALines[mIndex]) then
    begin
      Exit;
    end;
  end;
end;

end.
