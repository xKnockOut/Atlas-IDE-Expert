unit Atlas.Common.Editing.TestFromDebug;

// Test aus dem Debug-Halt (#1873): Das Plugin liest beim Halt die Werte der
// Parameter und einfachen Felder (Text, wie der Debugger ihn zeigt) und
// schickt sie mit der gewünschten Art (soll funktionieren, soll diese
// Exception werfen). Hier entstehen daraus:
//   - Delphi-Literale: Zahlen (Dezimalkomma wird Punkt), Strings mit '' und
//     #nn, Boolean, Aufzählungswerte, Mengen, dynamische Arrays bis zu einer
//     Länge. Objekte, Zeiger, Interfaces, Records und alles Unklare werden
//     nicht geraten: Der Test bekommt dort ein TODO.
//   - ein Name aus Methode und Hauptargument (ParseMit12_5Kg).
//   - der fertige Entwurf aus Atlas.Common.Editing.TestDrafts.
// Reine Textfunktionen ohne Dateien und Protokoll.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.TestDrafts;

type
  /// <summary>Wert aus dem Debugger: Name des Parameters bzw. Felds und Text, wie der Debugger ihn zeigt.</summary>
  TDebugStopValue = record
    Name: string;
    Text: string;
    class function Create(const AName, AText: string): TDebugStopValue; static;
  end;

  TDebugStopValues = TArray<TDebugStopValue>;

  /// <summary>Was das Plugin vom Halt mitbringt und im Dialog gewählt wurde.</summary>
  TDebugStopRequest = record
    Parameters: TDebugStopValues;
    Fields: TDebugStopValues;
    Kind: TTestDraftKind;
    /// <summary>Erwartetes Ergebnis (Text des Debuggers oder eingetippt); '' = Platzhalter.</summary>
    Expected: string;
    /// <summary>Klasse der Exception beim Halt; '' ohne.</summary>
    ExceptionClass: string;
    /// <summary>Name aus dem Dialog; '' = Vorschlag.</summary>
    TestName: string;
    /// <summary>Elemente je Array höchstens (tests.fromDebugStop.maxArray); 0 = keine Arrays.</summary>
    MaxArray: Integer;
    /// <summary>Zeitpunkt des Halts für die Kommentarzeile, als Text.</summary>
    StoppedAt: string;
    class function Empty: TDebugStopRequest; static;
  end;

  TTestFromDebug = class
  public const
    cMaxNameWords = 3;
    cMaxNameLength = 60;
    cDefaultMaxArray = 20;
  public
    /// <summary>Delphi-Literal aus dem Text des Debuggers für einen Wert des Typs ATypeName ('' = unbekannt);
    /// False, wenn der Wert nicht übernommen wird (Objekt, Zeiger, Record, zu langes Array, Unklares).</summary>
    class function Literal(const AText, ATypeName: string; AMaxArray: Integer; out ALiteral: string): Boolean;
      static;
    /// <summary>Testname aus Methode und Hauptargument (erster String, sonst erster Wert), bei Raises mit der
    /// Exception: ParseMit12_5Kg, ParseMit12_5KgWirftConvertError.</summary>
    class function SuggestName(const AMethodName: string; const AValues: TDebugStopValues;
      AKind: TTestDraftKind; const AExceptionClass: string): string; static;
    /// <summary>Felder der Klasse AClassName in AUnit (ohne geerbte); Accessible bei public und published.
    /// </summary>
    class function FieldsOf(const AUnit: TUnitIndex; const AClassName: string): TArray<TTestDraftValue>; static;
    /// <summary>Kommentarzeile „Aus Debug-Halt …, EKlasse“ (ohne //).</summary>
    class function CommentText(const AStoppedAt, AExceptionClass: string): string; static;
    /// <summary>Werte und Art aus ARequest in den Entwurf ADraft übernehmen; AFields sind die Felder der Klasse
    /// (FieldsOf). Werte ohne Literal werden TODO.</summary>
    class procedure Apply(const ARequest: TDebugStopRequest; const AFields: TArray<TTestDraftValue>;
      var ADraft: TTestDraft); static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Chars,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TTestFromDebugText = (With_, Raises, FromDebugStop);

const
  cTexts: array[TTestFromDebugText] of TAtlasText = (
    (De: 'Mit'; En: 'With'),
    (De: 'Wirft'; En: 'Raises'),
    (De: 'Aus Debug-Halt %s'; En: 'From debug stop %s'));

{$SCOPEDENUMS OFF}

{ TDebugStopValue }

class function TDebugStopValue.Create(const AName, AText: string): TDebugStopValue;
begin
  Result.Name := AName;
  Result.Text := AText;
end;

{ TDebugStopRequest }

class function TDebugStopRequest.Empty: TDebugStopRequest;
begin
  Result := Default(TDebugStopRequest);
  Result.Kind := TTestDraftKind.Works;
  Result.MaxArray := TTestFromDebug.cDefaultMaxArray;
end;

{ Literale }

/// <summary>Bezeichner, auch qualifiziert (TState.Error).</summary>
function IsIdentifier(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (AText <> '') and TTextChars.IsIdentStart(AText[1]) and not EndsStr('.', AText);
  for mIndex := 2 to Length(AText) do
  begin
    if Result and not (TTextChars.IsIdentChar(AText[mIndex]) or
      ((AText[mIndex] = '.') and (AText[mIndex - 1] <> '.'))) then
    begin
      Result := False;
    end;
  end;
end;

/// <summary>Ganzzahl mit optionalem Vorzeichen.</summary>
function IsInteger(const AText: string): Boolean;
var
  mIndex, mStart: Integer;
begin
  mStart := 1;
  if StartsStr('-', AText) then
  begin
    mStart := 2;
  end;
  Result := Length(AText) >= mStart;
  for mIndex := mStart to Length(AText) do
  begin
    if not CharInSet(AText[mIndex], ['0'..'9']) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Gleitkommazahl als Delphi-Literal (Punkt, Exponent); '' wenn AText keine ist.</summary>
function FloatLiteral(const AText: string): string;
var
  mText, mMantissa, mExponent: string;
  mParts: TArray<string>;
  mE: Integer;
begin
  Result := '';
  mText := StringReplace(AText, ',', '.', []);
  mE := Pos('E', UpperCase(mText));
  mMantissa := mText;
  mExponent := '';
  if mE > 0 then
  begin
    mMantissa := Copy(mText, 1, mE - 1);
    mExponent := Copy(mText, mE + 1, MaxInt);
    if StartsStr('+', mExponent) then
    begin
      mExponent := Copy(mExponent, 2, MaxInt);
    end;
    if not IsInteger(mExponent) then
    begin
      Exit;
    end;
  end;
  mParts := mMantissa.Split(['.']);
  if (Length(mParts) = 1) and IsInteger(mParts[0]) then
  begin
    Result := mText;
  end
  else if (Length(mParts) = 2) and IsInteger(mParts[0]) and (mParts[1] <> '') and IsInteger(mParts[1]) and
    not StartsStr('-', mParts[1]) then
  begin
    Result := mText;
  end;
end;

/// <summary>Überspringt 'Text' ab AIndex (auf dem Anführungszeichen), '' zählt als Zeichen; False bei offenem
/// String.</summary>
function SkipQuoted(const AText: string; var AIndex: Integer): Boolean;
begin
  Inc(AIndex);
  while AIndex <= Length(AText) do
  begin
    if AText[AIndex] <> '''' then
    begin
      Inc(AIndex);
    end
    else if (AIndex < Length(AText)) and (AText[AIndex + 1] = '''') then
    begin
      Inc(AIndex, 2);
    end
    else
    begin
      Inc(AIndex);
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Überspringt #13 bzw. #$0D ab AIndex (auf dem #); False ohne Zahl dahinter.</summary>
function SkipCharCode(const AText: string; var AIndex: Integer): Boolean;
begin
  Inc(AIndex);
  Result := (AIndex <= Length(AText)) and CharInSet(AText[AIndex], ['0'..'9', '$']);
  while (AIndex <= Length(AText)) and CharInSet(AText[AIndex], ['0'..'9', '$', 'A'..'F', 'a'..'f']) do
  begin
    Inc(AIndex);
  end;
end;

/// <summary>String-Ausdruck aus 'Teilen' und #nn wie ihn der Debugger zeigt (auch 'a'#13#10'b').</summary>
function IsStringLiteral(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(AText) >= 2;
  mIndex := 1;
  while Result and (mIndex <= Length(AText)) do
  begin
    case AText[mIndex] of
      '''':
        Result := SkipQuoted(AText, mIndex);
      '#':
        Result := SkipCharCode(AText, mIndex);
    else
      Result := False;
    end;
  end;
end;

/// <summary>Elemente einer Liste in Klammern, getrennt durch Komma außerhalb von Strings.</summary>
function SplitItems(const AInner: string): TArray<string>;
var
  mIndex, mStart: Integer;
  mInString: Boolean;
begin
  Result := nil;
  if Trim(AInner) = '' then
  begin
    Exit;
  end;
  mInString := False;
  mStart := 1;
  for mIndex := 1 to Length(AInner) do
  begin
    if AInner[mIndex] = '''' then
    begin
      mInString := not mInString;
    end
    else if (AInner[mIndex] = ',') and not mInString then
    begin
      Result := Result + [Trim(Copy(AInner, mStart, mIndex - mStart))];
      mStart := mIndex + 1;
    end;
  end;
  Result := Result + [Trim(Copy(AInner, mStart, MaxInt))];
end;

/// <summary>Einfacher Wert ohne Klammern: Zahl, String, Boolean, Aufzählungswert.</summary>
function ScalarLiteral(const AText: string; out ALiteral: string): Boolean;
begin
  ALiteral := '';
  if IsStringLiteral(AText) or IsInteger(AText) then
  begin
    ALiteral := AText;
  end
  else if SameText(AText, 'nil') or StartsStr('$', AText) then
  begin
    Exit(False);
  end
  else if IsIdentifier(AText) then
  begin
    ALiteral := AText;
  end
  else
  begin
    ALiteral := FloatLiteral(AText);
  end;
  Result := ALiteral <> '';
end;

/// <summary>Menge [a, b] bzw. dynamisches Array (1, 2) als [..]; AMaxItems begrenzt die Elemente.</summary>
function ListLiteral(const AInner: string; AMaxItems: Integer; out ALiteral: string): Boolean;
var
  mItems, mLiterals: TArray<string>;
  mItem, mLiteral: string;
begin
  ALiteral := '';
  mItems := SplitItems(AInner);
  Result := Length(mItems) <= AMaxItems;
  mLiterals := nil;
  for mItem in mItems do
  begin
    if Result and ScalarLiteral(mItem, mLiteral) then
    begin
      mLiterals := mLiterals + [mLiteral];
    end
    else
    begin
      Result := False;
    end;
  end;
  if Result then
  begin
    ALiteral := '[' + string.Join(', ', mLiterals) + ']';
  end;
end;

function IsArrayType(const ATypeName: string): Boolean;
begin
  Result := StartsText('TArray<', ATypeName) or StartsText('array of', ATypeName) or
    EndsText('Array', ATypeName);
end;

class function TTestFromDebug.Literal(const AText, ATypeName: string; AMaxArray: Integer;
  out ALiteral: string): Boolean;
var
  mText: string;
begin
  ALiteral := '';
  mText := Trim(AText);
  if StartsStr('[', mText) and EndsStr(']', mText) then
  begin
    // Menge: Elemente sind Aufzählungswerte oder Zahlen, keine Grenze.
    Result := ListLiteral(Copy(mText, 2, Length(mText) - 2), MaxInt, ALiteral);
  end
  else if StartsStr('(', mText) and EndsStr(')', mText) then
  begin
    // Dynamisches Array bis zur Grenze; Records und Objekte zeigt der Debugger ebenso in Klammern.
    Result := IsArrayType(ATypeName) and (Pos(':', mText) = 0) and
      ListLiteral(Copy(mText, 2, Length(mText) - 2), AMaxArray, ALiteral);
  end
  else
  begin
    Result := ScalarLiteral(mText, ALiteral);
  end;
end;

{ Name }

/// <summary>Wörter aus Buchstaben bzw. Ziffern, Wörter groß beginnend, Ziffernfolgen mit _ getrennt.</summary>
function NameWords(const AText: string): string;
var
  mWords: TArray<string>;
  mWord: string;
  mIndex: Integer;
  mChar: Char;
begin
  mWords := nil;
  mWord := '';
  for mIndex := 1 to Length(AText) + 1 do
  begin
    mChar := ' ';
    if mIndex <= Length(AText) then
    begin
      mChar := AText[mIndex];
    end;
    if CharInSet(mChar, ['A'..'Z', 'a'..'z', '0'..'9']) then
    begin
      mWord := mWord + mChar;
    end
    else if mWord <> '' then
    begin
      mWords := mWords + [UpperCase(Copy(mWord, 1, 1)) + Copy(mWord, 2, MaxInt)];
      mWord := '';
    end;
  end;
  Result := '';
  for mIndex := 0 to High(mWords) do
  begin
    if mIndex >= TTestFromDebug.cMaxNameWords then
    begin
      Break;
    end;
    if (Result <> '') and CharInSet(Result[Length(Result)], ['0'..'9']) and CharInSet(mWords[mIndex][1], ['0'..'9'])
    then
    begin
      Result := Result + '_';
    end;
    Result := Result + mWords[mIndex];
  end;
end;

/// <summary>Hauptargument: erster String, sonst erster übernehmbare Wert; Objekte und Zeiger nie.</summary>
function MainValue(const AValues: TDebugStopValues): string;
var
  mValue: TDebugStopValue;
  mLiteral: string;
begin
  Result := '';
  for mValue in AValues do
  begin
    if IsStringLiteral(Trim(mValue.Text)) then
    begin
      Exit(mValue.Text);
    end;
    if (Result = '') and ScalarLiteral(Trim(mValue.Text), mLiteral) then
    begin
      Result := mLiteral;
    end;
  end;
end;

class function TTestFromDebug.SuggestName(const AMethodName: string; const AValues: TDebugStopValues;
  AKind: TTestDraftKind; const AExceptionClass: string): string;
var
  mWords, mException: string;
begin
  Result := AMethodName;
  mWords := NameWords(MainValue(AValues));
  if mWords <> '' then
  begin
    Result := Result + cTexts[TTestFromDebugText.With_].Text + mWords;
  end;
  if (AKind = TTestDraftKind.Raises) and (AExceptionClass <> '') then
  begin
    mException := AExceptionClass;
    if (Length(mException) > 1) and (mException[1] = 'E') and CharInSet(mException[2], ['A'..'Z']) then
    begin
      mException := Copy(mException, 2, MaxInt);
    end;
    Result := Result + cTexts[TTestFromDebugText.Raises].Text + NameWords(mException);
  end;
  Result := Copy(Result, 1, cMaxNameLength);
end;

{ Felder und Entwurf }

class function TTestFromDebug.FieldsOf(const AUnit: TUnitIndex; const AClassName: string): TArray<TTestDraftValue>;
var
  mSymbol: TIndexSymbol;
  mValue: TTestDraftValue;
begin
  Result := nil;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, AClassName) then
    begin
      mValue := TTestDraftValue.Create(mSymbol.Name, mSymbol.TypeName, '', '');
      mValue.Accessible := mSymbol.Visibility in [TIndexVisibility.Public, TIndexVisibility.Published];
      Result := Result + [mValue];
    end;
  end;
end;

class function TTestFromDebug.CommentText(const AStoppedAt, AExceptionClass: string): string;
var
  mParts: TArray<string>;
begin
  mParts := nil;
  if Trim(AStoppedAt) <> '' then
  begin
    mParts := mParts + [Trim(AStoppedAt)];
  end;
  if Trim(AExceptionClass) <> '' then
  begin
    mParts := mParts + [Trim(AExceptionClass)];
  end;
  Result := TrimRight(cTexts[TTestFromDebugText.FromDebugStop].Fmt([string.Join(', ', mParts)]));
end;

/// <summary>Text des Werts ANamen in AValues; False, wenn er fehlt (nicht übernommen).</summary>
function FindValue(const AValues: TDebugStopValues; const AName: string; out AText: string): Boolean;
var
  mValue: TDebugStopValue;
begin
  AText := '';
  for mValue in AValues do
  begin
    if SameText(mValue.Name, AName) then
    begin
      AText := mValue.Text;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Wert aus dem Debugger in AValue übernehmen: Literal oder TODO.</summary>
procedure TakeValue(var AValue: TTestDraftValue; const AText: string; AMaxArray: Integer);
var
  mLiteral: string;
begin
  if TTestFromDebug.Literal(AText, AValue.TypeName, AMaxArray, mLiteral) then
  begin
    AValue.Value := mLiteral;
    AValue.Todo := False;
  end
  else
  begin
    AValue.Value := '';
    AValue.Todo := True;
  end;
end;

/// <summary>Hat der Entwurf var- oder out-Parameter, deren Prüfung Platzhalter braucht?</summary>
function HasOutputs(const ADraft: TTestDraft): Boolean;
var
  mValue: TTestDraftValue;
begin
  Result := False;
  for mValue in ADraft.Parameters do
  begin
    if MatchText(mValue.Modifier, ['var', 'out']) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Erwartetes Ergebnis: Literal aus dem Debugger, sonst der eingetippte Text.</summary>
function ExpectedText(const ARequest: TDebugStopRequest; const AResultType: string): string;
begin
  Result := '';
  if (Trim(ARequest.Expected) <> '') and
    not TTestFromDebug.Literal(ARequest.Expected, AResultType, ARequest.MaxArray, Result) then
  begin
    Result := Trim(ARequest.Expected);
  end;
end;

class procedure TTestFromDebug.Apply(const ARequest: TDebugStopRequest; const AFields: TArray<TTestDraftValue>;
  var ADraft: TTestDraft);
var
  mIndex: Integer;
  mText: string;
  mField: TTestDraftValue;
begin
  for mIndex := 0 to High(ADraft.Parameters) do
  begin
    if FindValue(ARequest.Parameters, ADraft.Parameters[mIndex].Name, mText) then
    begin
      TakeValue(ADraft.Parameters[mIndex], mText, ARequest.MaxArray);
    end;
  end;
  ADraft.Fields := nil;
  if not ADraft.ClassMethod then
  begin
    for mField in AFields do
    begin
      if FindValue(ARequest.Fields, mField.Name, mText) then
      begin
        ADraft.Fields := ADraft.Fields + [mField];
        TakeValue(ADraft.Fields[High(ADraft.Fields)], mText, ARequest.MaxArray);
      end;
    end;
  end;
  ADraft.Kind := ARequest.Kind;
  ADraft.ExceptionClass := ARequest.ExceptionClass;
  ADraft.Expected := ExpectedText(ARequest, ADraft.ResultType);
  ADraft.Comment := CommentText(ARequest.StoppedAt, ARequest.ExceptionClass);
  ADraft.TestName := Trim(ARequest.TestName);
  if ADraft.TestName = '' then
  begin
    ADraft.TestName := SuggestName(ADraft.MethodName, ARequest.Parameters, ARequest.Kind, ARequest.ExceptionClass);
  end;
  // Entwurf bleibt rot, solange erwartete Werte fehlen; WillRaise ist vollständig.
  ADraft.Draft := (ADraft.Kind = TTestDraftKind.Works) and
    (((ADraft.ResultType <> '') and (ADraft.Expected = '')) or HasOutputs(ADraft));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.TestFromDebug', cTexts);

end.
