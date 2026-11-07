unit Atlas.Core.Editor.PatternContinuation;

// Muster fortsetzen (#671), ohne Open Tools API und ohne Server: Haben die
// letzten Zeilen derselben Einrückung dieselbe Token-Folge und unterscheiden
// sie sich nur an einzelnen Stellen, deren Werte eine Folge bilden, schlägt
// Suggest die nächste Zeile vor. Rein lokal und tokenbasiert.
// - Verglichen wird der längste Lauf von höchstens MaxLines Zeilen direkt über
//   der Cursorzeile, der dieselbe Form hat; er muss mindestens AMinLines lang
//   sein.
// - Folgen: Ganzzahlen mit fester Schrittweite (auch negativ und hexadezimal,
//   "$0A" behält Stellen und Schreibweise), Zeichen ('A', 'B' → 'C'),
//   Bezeichner mit hochzählender Nummer (Edit1, Edit2 → Edit3; nur wenn es den
//   neuen Namen gibt oder die Zeile ihn deklariert) und Werte eines
//   Aufzählungstyps in Deklarationsreihenfolge (über AEnums; am Ende des Typs
//   kein Vorschlag).
// - Strings, die sich ohne Folge unterscheiden, werden leer ('') und sind
//   freie Felder; der erste ist der Tab-Stopp.
// - Unterscheiden sich Bezeichner ohne erkennbare Folge, gibt es keinen
//   Vorschlag (mehrdeutig).
// LocalEnumValues findet Aufzählungstypen im Text selbst; was dort fehlt,
// fragt die IDE beim Server nach.

interface

uses
  System.SysUtils;

type
  /// <summary>Werte des Aufzählungstyps, zu dem AMember gehört (in Deklarationsreihenfolge); nil, wenn unbekannt.
  /// ALine, ACharacter: Stelle des Werts im Text (0-basiert).</summary>
  TAtlasEnumLookup = reference to function(const AMember: string; ALine, ACharacter: Integer): TArray<string>;
  /// <summary>Gibt es den Bezeichner AName im Text bzw. Projekt?</summary>
  TAtlasNameExists = reference to function(const AName: string): Boolean;

  TAtlasPatternSuggestion = record
    /// <summary>Die neue Zeile ohne Einzug.</summary>
    Text: string;
    /// <summary>Einzug der Musterzeilen.</summary>
    Indent: string;
    /// <summary>Freie Felder: Zeichen in Text vor der Stelle zwischen den Hochkommas eines leeren Strings.</summary>
    Fields: TArray<Integer>;
  end;

  TAtlasPatternContinuation = class
  public const
    cMinLines = 2;
    cMaxLines = 5;
  public
    /// <summary>Vorschlag für die leere Zeile ALine (0-basiert) aus den Zeilen darüber; False ohne Muster.
    /// AEnums und AExists dürfen nil sein.</summary>
    class function Suggest(const ALines: TArray<string>; ALine, AMinLines: Integer; const AEnums: TAtlasEnumLookup;
      const AExists: TAtlasNameExists; out ASuggestion: TAtlasPatternSuggestion): Boolean; static;
    /// <summary>Werte eines Aufzählungstyps aus AText, der AMember enthält ("TState = (stA, stB);"); nil ohne.
    /// </summary>
    class function LocalEnumValues(const AText, AMember: string): TArray<string>; static;
    /// <summary>Kommt AName in AText als ganzes Wort vor (Groß-/Kleinschreibung egal)?</summary>
    class function ContainsWord(const AText, AName: string): Boolean; static;
  end;

implementation

uses
  Atlas.Text.Chars;

type
  {$SCOPEDENUMS ON}
  TTokenKind = (Ident, Number, Str, Symbol, Comment);
  {$SCOPEDENUMS OFF}

  TToken = record
    Kind: TTokenKind;
    Text: string;
    /// <summary>1-basiert in der Zeile.</summary>
    Start: Integer;
    /// <summary>Leerraum davor.</summary>
    Space: string;
  end;

  TTokens = TArray<TToken>;

  /// <summary>Eine Spalte über die Musterzeilen und alles, was zur Folge gehört.</summary>
  TColumnInput = record
    Tokens: TArray<TTokens>;
    LineIndexes: TArray<Integer>;
    Column: Integer;
    Indent: Integer;
    Texts: TArray<string>;
    Enums: TAtlasEnumLookup;
    Exists: TAtlasNameExists;
  end;

function LeadingSpace(const ALine: string): string;
var
  mIndex: Integer;
begin
  mIndex := 1;
  while (mIndex <= Length(ALine)) and CharInSet(ALine[mIndex], [' ', #9]) do
  begin
    Inc(mIndex);
  end;
  Result := Copy(ALine, 1, mIndex - 1);
end;

function IsOperand(const AToken: TToken): Boolean;
begin
  Result := (AToken.Kind in [TTokenKind.Ident, TTokenKind.Number, TTokenKind.Str]) or
    ((AToken.Kind = TTokenKind.Symbol) and ((AToken.Text = ')') or (AToken.Text = ']')));
end;

function CharAt(const ALine: string; AIndex: Integer): Char;
begin
  Result := #0;
  if (AIndex >= 1) and (AIndex <= Length(ALine)) then
  begin
    Result := ALine[AIndex];
  end;
end;

procedure SkipChars(const ALine: string; var AIndex: Integer; const AChars: TSysCharSet);
begin
  while (AIndex <= Length(ALine)) and CharInSet(ALine[AIndex], AChars) do
  begin
    Inc(AIndex);
  end;
end;

/// <summary>Vorzeichen nur, wo kein Operand davorsteht ("A - 1" bleibt eine Rechnung).</summary>
function IsSignStart(const ALine: string; AIndex: Integer; const APrevious: TTokens): Boolean;
begin
  Result := (CharAt(ALine, AIndex) = '-') and CharInSet(CharAt(ALine, AIndex + 1), ['0'..'9', '$']) and
    ((Length(APrevious) = 0) or not IsOperand(APrevious[High(APrevious)]));
end;

function IsNumberStart(const ALine: string; AIndex: Integer; const APrevious: TTokens): Boolean;
begin
  Result := CharInSet(CharAt(ALine, AIndex), ['0'..'9']) or ((CharAt(ALine, AIndex) = '$') and
    CharInSet(CharAt(ALine, AIndex + 1), ['0'..'9', 'A'..'F', 'a'..'f'])) or IsSignStart(ALine, AIndex, APrevious);
end;

function ScanNumber(const ALine: string; var AIndex: Integer): TTokenKind;
begin
  if CharAt(ALine, AIndex) = '-' then
  begin
    Inc(AIndex);
  end;
  if CharAt(ALine, AIndex) = '$' then
  begin
    Inc(AIndex);
    SkipChars(ALine, AIndex, ['0'..'9', 'A'..'F', 'a'..'f']);
  end
  else
  begin
    SkipChars(ALine, AIndex, ['0'..'9']);
  end;
  Result := TTokenKind.Number;
  // Gleitkommazahlen und Bereiche: nur Ganzzahlen bilden Folgen.
  if (CharAt(ALine, AIndex) = '.') and CharInSet(CharAt(ALine, AIndex + 1), ['0'..'9']) then
  begin
    Inc(AIndex);
    SkipChars(ALine, AIndex, ['0'..'9', 'e', 'E']);
    Result := TTokenKind.Symbol;
  end;
end;

procedure ScanString(const ALine: string; var AIndex: Integer);
var
  mDone: Boolean;
begin
  Inc(AIndex);
  mDone := False;
  while not mDone and (AIndex <= Length(ALine)) do
  begin
    if (ALine[AIndex] = '''') and (CharAt(ALine, AIndex + 1) = '''') then
    begin
      Inc(AIndex, 2);
    end
    else if ALine[AIndex] = '''' then
    begin
      mDone := True;
    end
    else
    begin
      Inc(AIndex);
    end;
  end;
  Inc(AIndex);
end;

function IsBlockCommentStart(const ALine: string; AIndex: Integer): Boolean;
begin
  Result := (CharAt(ALine, AIndex) = '{') or ((CharAt(ALine, AIndex) = '(') and (CharAt(ALine, AIndex + 1) = '*'));
end;

procedure ScanBlockComment(const ALine: string; var AIndex: Integer);
begin
  if ALine[AIndex] = '{' then
  begin
    AIndex := Pos('}', ALine, AIndex);
  end
  else
  begin
    AIndex := Pos('*)', ALine, AIndex + 2);
    if AIndex > 0 then
    begin
      Inc(AIndex);
    end;
  end;
  if AIndex = 0 then
  begin
    AIndex := Length(ALine);
  end;
  Inc(AIndex);
end;

function IsTwoCharOperator(const APair: string): Boolean;
begin
  Result := (APair = ':=') or (APair = '..') or (APair = '<=') or (APair = '>=') or (APair = '<>');
end;

procedure ScanSymbol(const ALine: string; var AIndex: Integer);
begin
  // Zweizeichige Operatoren als ein Token.
  if IsTwoCharOperator(Copy(ALine, AIndex, 2)) then
  begin
    Inc(AIndex);
  end;
  Inc(AIndex);
end;

/// <summary>Liest das Token ab AIndex und liefert seine Art; AIndex steht danach dahinter.</summary>
function ScanToken(const ALine: string; var AIndex: Integer; const APrevious: TTokens): TTokenKind;
begin
  if TTextChars.IsIdentStart(ALine[AIndex]) then
  begin
    while (AIndex <= Length(ALine)) and TTextChars.IsIdentChar(ALine[AIndex]) do
    begin
      Inc(AIndex);
    end;
    Result := TTokenKind.Ident;
  end
  else if IsNumberStart(ALine, AIndex, APrevious) then
  begin
    Result := ScanNumber(ALine, AIndex);
  end
  else if ALine[AIndex] = '''' then
  begin
    ScanString(ALine, AIndex);
    Result := TTokenKind.Str;
  end
  else if (ALine[AIndex] = '/') and (CharAt(ALine, AIndex + 1) = '/') then
  begin
    AIndex := Length(ALine) + 1;
    Result := TTokenKind.Comment;
  end
  else if IsBlockCommentStart(ALine, AIndex) then
  begin
    ScanBlockComment(ALine, AIndex);
    Result := TTokenKind.Comment;
  end
  else
  begin
    ScanSymbol(ALine, AIndex);
    Result := TTokenKind.Symbol;
  end;
end;

function Tokenize(const ALine: string): TTokens;
var
  mIndex, mSpaceStart: Integer;
  mToken: TToken;
begin
  Result := nil;
  mIndex := 1;
  while mIndex <= Length(ALine) do
  begin
    mSpaceStart := mIndex;
    SkipChars(ALine, mIndex, [' ', #9]);
    if mIndex <= Length(ALine) then
    begin
      mToken := Default(TToken);
      mToken.Space := Copy(ALine, mSpaceStart, mIndex - mSpaceStart);
      mToken.Start := mIndex;
      mToken.Kind := ScanToken(ALine, mIndex, Result);
      mToken.Text := Copy(ALine, mToken.Start, mIndex - mToken.Start);
      Result := Result + [mToken];
    end;
  end;
end;

/// <summary>Gleiche Form: gleiche Länge, gleiche Arten, gleiche Symbole und Kommentare.</summary>
function SameShape(const A, B: TTokens): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if Length(A) <> Length(B) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(A) do
  begin
    if A[mIndex].Kind <> B[mIndex].Kind then
    begin
      Exit;
    end;
    if (A[mIndex].Kind in [TTokenKind.Symbol, TTokenKind.Comment]) and (A[mIndex].Text <> B[mIndex].Text) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

function TryNumber(const AText: string; out AValue: Int64; out AHex: Boolean; out ADigits: Integer): Boolean;
var
  mBody: string;
  mNegative: Boolean;
begin
  mBody := AText;
  mNegative := mBody.StartsWith('-');
  if mNegative then
  begin
    Delete(mBody, 1, 1);
  end;
  AHex := mBody.StartsWith('$');
  if AHex then
  begin
    Delete(mBody, 1, 1);
  end;
  ADigits := Length(mBody);
  if AHex then
  begin
    Result := TryStrToInt64('$' + mBody, AValue);
  end
  else
  begin
    Result := TryStrToInt64(mBody, AValue);
  end;
  if Result and mNegative then
  begin
    AValue := -AValue;
  end;
end;

/// <summary>Gleiche Abstände zwischen AValues? ASStep: der Abstand.</summary>
function ConstantStep(const AValues: TArray<Int64>; out AStep: Int64): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  AStep := 0;
  if Length(AValues) < 2 then
  begin
    Exit;
  end;
  AStep := AValues[1] - AValues[0];
  if AStep = 0 then
  begin
    Exit;
  end;
  for mIndex := 2 to High(AValues) do
  begin
    if AValues[mIndex] - AValues[mIndex - 1] <> AStep then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

/// <summary>Zahl wie das Vorbild ATemplate geschrieben: hexadezimal mit gleicher Stellenzahl und Schreibweise.
/// </summary>
function FormatNumber(AValue: Int64; const ATemplate: string; AHex: Boolean; ADigits: Integer): string;
var
  mDigits: string;
  mLower: Boolean;
begin
  if not AHex then
  begin
    Exit(IntToStr(AValue));
  end;
  mDigits := IntToHex(Abs(AValue), ADigits);
  mLower := ATemplate <> UpperCase(ATemplate);
  if mLower then
  begin
    mDigits := LowerCase(mDigits);
  end;
  Result := '$' + mDigits;
  if AValue < 0 then
  begin
    Result := '-' + Result;
  end;
end;

/// <summary>Bezeichner mit Nummer am Ende: Präfix und Zahl ("Edit12" → "Edit", 12).</summary>
function SplitNumbered(const AName: string; out APrefix: string; out ANumber: Int64; out ADigits: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := Length(AName);
  while (mIndex > 0) and CharInSet(AName[mIndex], ['0'..'9']) do
  begin
    Dec(mIndex);
  end;
  APrefix := Copy(AName, 1, mIndex);
  ADigits := Length(AName) - mIndex;
  Result := (mIndex > 0) and (ADigits > 0) and TryStrToInt64(Copy(AName, mIndex + 1, MaxInt), ANumber);
end;

function ColumnTexts(const ATokens: TArray<TTokens>; AColumn: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ATokens));
  for mIndex := 0 to High(ATokens) do
  begin
    Result[mIndex] := ATokens[mIndex][AColumn].Text;
  end;
end;

function NumberNext(const AInput: TColumnInput; out AValue: string): Boolean;
var
  mValues: TArray<Int64>;
  mValue, mStep: Int64;
  mIndex, mDigits, mFirstDigits: Integer;
  mHex, mFirstHex: Boolean;
begin
  Result := False;
  AValue := '';
  mFirstHex := False;
  mFirstDigits := 0;
  SetLength(mValues, Length(AInput.Texts));
  for mIndex := 0 to High(AInput.Texts) do
  begin
    if not TryNumber(AInput.Texts[mIndex], mValue, mHex, mDigits) or ((mIndex > 0) and (mHex <> mFirstHex)) then
    begin
      Exit;
    end;
    if mIndex = 0 then
    begin
      mFirstHex := mHex;
      mFirstDigits := mDigits;
    end;
    mValues[mIndex] := mValue;
  end;
  if ConstantStep(mValues, mStep) then
  begin
    AValue := FormatNumber(mValues[High(mValues)] + mStep, AInput.Texts[High(AInput.Texts)], mFirstHex, mFirstDigits);
    Result := True;
  end;
end;

function IsPlainChar(AValue: Int64): Boolean;
begin
  Result := (AValue >= 32) and (AValue < $FFFF) and (AValue <> Ord(''''));
end;

/// <summary>Einzelne Zeichen mit fester Schrittweite bilden eine Folge, alles andere wird ein freies Feld.</summary>
function StringNext(const AInput: TColumnInput; out AValue: string; out AFree: Boolean): Boolean;
var
  mValues: TArray<Int64>;
  mStep: Int64;
  mIndex: Integer;
  mChars: Boolean;
begin
  mChars := True;
  SetLength(mValues, Length(AInput.Texts));
  for mIndex := 0 to High(AInput.Texts) do
  begin
    if (Length(AInput.Texts[mIndex]) = 3) and (AInput.Texts[mIndex][2] <> '''') then
    begin
      mValues[mIndex] := Ord(AInput.Texts[mIndex][2]);
    end
    else
    begin
      mChars := False;
    end;
  end;
  AFree := not (mChars and ConstantStep(mValues, mStep) and IsPlainChar(mValues[High(mValues)] + mStep));
  if AFree then
  begin
    AValue := '''''';
  end
  else
  begin
    AValue := '''' + Char(Integer(mValues[High(mValues)] + mStep)) + '''';
  end;
  Result := True;
end;

/// <summary>Alle Texte sind Bezeichner mit Nummer und gleichem Präfix; AValues: die Nummern.</summary>
function NumberedValues(const ATexts: TArray<string>; out AValues: TArray<Int64>): Boolean;
var
  mFirstPrefix, mPrefix: string;
  mValue: Int64;
  mDigits, mIndex: Integer;
begin
  SetLength(AValues, Length(ATexts));
  Result := SplitNumbered(ATexts[0], mFirstPrefix, mValue, mDigits);
  mIndex := 0;
  while Result and (mIndex <= High(ATexts)) do
  begin
    Result := SplitNumbered(ATexts[mIndex], mPrefix, mValue, mDigits) and SameText(mPrefix, mFirstPrefix);
    AValues[mIndex] := mValue;
    Inc(mIndex);
  end;
end;

/// <summary>Deklariert die Zeile den Namen (Name: Typ; Name, …), darf er neu sein.</summary>
function DeclaresName(const AInput: TColumnInput): Boolean;
begin
  Result := (AInput.Column = 0) and (Length(AInput.Tokens[0]) > 1) and
    ((AInput.Tokens[0][1].Text = ':') or (AInput.Tokens[0][1].Text = ','));
end;

/// <summary>Nummerierte Bezeichner; ADecided: Die Spalte ist eine solche Folge (dann gilt das Ergebnis).</summary>
function NumberedNext(const AInput: TColumnInput; out AValue: string; out ADecided: Boolean): Boolean;
var
  mValues: TArray<Int64>;
  mStep, mValue: Int64;
  mPrefix, mLast: string;
  mDigits: Integer;
begin
  Result := False;
  AValue := '';
  ADecided := NumberedValues(AInput.Texts, mValues) and ConstantStep(mValues, mStep) and
    (mValues[High(mValues)] + mStep >= 0);
  if not ADecided then
  begin
    Exit;
  end;
  mLast := AInput.Texts[High(AInput.Texts)];
  SplitNumbered(mLast, mPrefix, mValue, mDigits);
  AValue := IntToStr(mValues[High(mValues)] + mStep);
  // Führende Nullen wie im Vorbild ("Spalte01").
  if (Length(AValue) < mDigits) and (Copy(mLast, Length(mPrefix) + 1, 1) = '0') then
  begin
    AValue := StringOfChar('0', mDigits - Length(AValue)) + AValue;
  end;
  AValue := mPrefix + AValue;
  Result := DeclaresName(AInput) or (Assigned(AInput.Exists) and AInput.Exists(AValue));
end;

function IndexOfText(const AItems: TArray<string>; const AName: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := High(AItems) downto 0 do
  begin
    if SameText(AItems[mIndex], AName) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Stellen der Texte unter AMembers; False, wenn einer fehlt oder AMembers leer ist.</summary>
function MemberIndexes(const AMembers, ATexts: TArray<string>; out AValues: TArray<Int64>): Boolean;
var
  mIndex: Integer;
begin
  SetLength(AValues, Length(ATexts));
  Result := Length(AMembers) > 0;
  mIndex := 0;
  while Result and (mIndex <= High(ATexts)) do
  begin
    AValues[mIndex] := IndexOfText(AMembers, ATexts[mIndex]);
    Result := AValues[mIndex] >= 0;
    Inc(mIndex);
  end;
end;

/// <summary>Werte eines Aufzählungstyps in Deklarationsreihenfolge.</summary>
function EnumNext(const AInput: TColumnInput; out AValue: string): Boolean;
var
  mMembers: TArray<string>;
  mValues: TArray<Int64>;
  mStep, mNext: Int64;
  mPosition: Integer;
begin
  Result := False;
  AValue := '';
  if not Assigned(AInput.Enums) then
  begin
    Exit;
  end;
  mPosition := AInput.Indent + AInput.Tokens[High(AInput.Tokens)][AInput.Column].Start - 1;
  mMembers := AInput.Enums(AInput.Texts[High(AInput.Texts)], AInput.LineIndexes[High(AInput.LineIndexes)], mPosition);
  if not MemberIndexes(mMembers, AInput.Texts, mValues) or not ConstantStep(mValues, mStep) then
  begin
    Exit;
  end;
  mNext := mValues[High(mValues)] + mStep;
  if (mNext >= 0) and (mNext <= High(mMembers)) then
  begin
    AValue := mMembers[mNext];
    Result := True;
  end;
end;

function IdentNext(const AInput: TColumnInput; out AValue: string): Boolean;
var
  mDecided: Boolean;
begin
  Result := NumberedNext(AInput, AValue, mDecided);
  if not mDecided then
  begin
    Result := EnumNext(AInput, AValue);
  end;
end;

/// <summary>Nächster Wert der Spalte AInput.Column über die Zeilen AInput.Tokens; False, wenn keine Folge.</summary>
function NextValue(const AInput: TColumnInput; out AValue: string; out AFree: Boolean): Boolean;
begin
  Result := False;
  AValue := '';
  AFree := False;
  case AInput.Tokens[0][AInput.Column].Kind of
    TTokenKind.Number:
      begin
        Result := NumberNext(AInput, AValue);
      end;
    TTokenKind.Str:
      begin
        Result := StringNext(AInput, AValue, AFree);
      end;
    TTokenKind.Ident:
      begin
        Result := IdentNext(AInput, AValue);
      end;
  end;
end;

function ColumnVaries(const ARun: TArray<TTokens>; AColumn: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 1 to High(ARun) do
  begin
    Result := Result or (ARun[mIndex][AColumn].Text <> ARun[0][AColumn].Text);
  end;
end;

/// <summary>Wert der Spalte AColumn in der neuen Zeile; False, wenn sie sich ohne Folge ändert.</summary>
function ColumnValue(var AInput: TColumnInput; AColumn: Integer; out AValue: string; out AFree: Boolean;
  var AAnyVaries: Boolean): Boolean;
begin
  AValue := AInput.Tokens[High(AInput.Tokens)][AColumn].Text;
  AFree := False;
  Result := True;
  if not ColumnVaries(AInput.Tokens, AColumn) then
  begin
    Exit;
  end;
  AInput.Column := AColumn;
  AInput.Texts := ColumnTexts(AInput.Tokens, AColumn);
  Result := NextValue(AInput, AValue, AFree);
  AAnyVaries := AAnyVaries or (Result and not AFree);
end;

function BuildSuggestion(var AInput: TColumnInput; var ASuggestion: TAtlasPatternSuggestion): Boolean;
var
  mTemplate: TTokens;
  mBuilder: TStringBuilder;
  mColumn: Integer;
  mValue: string;
  mFree, mAnyVaries: Boolean;
begin
  Result := False;
  mAnyVaries := False;
  mTemplate := AInput.Tokens[High(AInput.Tokens)];
  mBuilder := TStringBuilder.Create;
  try
    for mColumn := 0 to High(mTemplate) do
    begin
      if not ColumnValue(AInput, mColumn, mValue, mFree, mAnyVaries) then
      begin
        Exit;
      end;
      mBuilder.Append(mTemplate[mColumn].Space);
      if mFree then
      begin
        ASuggestion.Fields := ASuggestion.Fields + [mBuilder.Length + 1];
      end;
      mBuilder.Append(mValue);
    end;
    // Nur freie Strings oder lauter gleiche Zeilen sind kein Muster.
    Result := mAnyVaries;
    if Result then
    begin
      ASuggestion.Text := mBuilder.ToString;
    end;
  finally
    mBuilder.Free;
  end;
end;

function IsPatternLine(const ALine, AIndent: string): Boolean;
begin
  Result := (LeadingSpace(ALine) = AIndent) and (Trim(ALine) <> '');
end;

/// <summary>Längster Lauf gleicher Form wie ATemplate direkt über ALine, neueste Zeile zuletzt.</summary>
function CollectRun(const ALines: TArray<string>; ALine: Integer; const AIndent: string; const ATemplate: TTokens;
  out ALineIndexes: TArray<Integer>): TArray<TTokens>;
var
  mLine: Integer;
  mTokens: TTokens;
begin
  Result := [ATemplate];
  ALineIndexes := [ALine - 1];
  mLine := ALine - 2;
  while (mLine >= 0) and (Length(Result) < TAtlasPatternContinuation.cMaxLines) and
    IsPatternLine(ALines[mLine], AIndent) do
  begin
    mTokens := Tokenize(Copy(ALines[mLine], Length(AIndent) + 1, MaxInt));
    if not SameShape(mTokens, ATemplate) then
    begin
      Break;
    end;
    Result := [mTokens] + Result;
    ALineIndexes := [mLine] + ALineIndexes;
    Dec(mLine);
  end;
end;

function ClampMinLines(AMinLines: Integer): Integer;
begin
  Result := AMinLines;
  if Result < TAtlasPatternContinuation.cMinLines then
  begin
    Result := TAtlasPatternContinuation.cMinLines;
  end;
  if Result > TAtlasPatternContinuation.cMaxLines then
  begin
    Result := TAtlasPatternContinuation.cMaxLines;
  end;
end;

{ TAtlasPatternContinuation }

class function TAtlasPatternContinuation.Suggest(const ALines: TArray<string>; ALine, AMinLines: Integer;
  const AEnums: TAtlasEnumLookup; const AExists: TAtlasNameExists; out ASuggestion: TAtlasPatternSuggestion): Boolean;
var
  mMinLines: Integer;
  mIndent: string;
  mTemplate: TTokens;
  mInput: TColumnInput;
begin
  ASuggestion := Default(TAtlasPatternSuggestion);
  Result := False;
  mMinLines := ClampMinLines(AMinLines);
  if (ALine < mMinLines) or (ALine > High(ALines)) or (Trim(ALines[ALine]) <> '') then
  begin
    Exit;
  end;
  mIndent := LeadingSpace(ALines[ALine - 1]);
  mTemplate := Tokenize(Copy(ALines[ALine - 1], Length(mIndent) + 1, MaxInt));
  if Length(mTemplate) = 0 then
  begin
    Exit;
  end;
  mInput := Default(TColumnInput);
  mInput.Tokens := CollectRun(ALines, ALine, mIndent, mTemplate, mInput.LineIndexes);
  mInput.Indent := Length(mIndent);
  mInput.Enums := AEnums;
  mInput.Exists := AExists;
  Result := (Length(mInput.Tokens) >= mMinLines) and BuildSuggestion(mInput, ASuggestion);
  if Result then
  begin
    ASuggestion.Indent := mIndent;
  end;
end;

class function TAtlasPatternContinuation.ContainsWord(const AText, AName: string): Boolean;
var
  mText, mName: string;
  mAt: Integer;
begin
  Result := False;
  if AName = '' then
  begin
    Exit;
  end;
  mText := LowerCase(AText);
  mName := LowerCase(AName);
  mAt := Pos(mName, mText);
  while mAt > 0 do
  begin
    if ((mAt = 1) or not TTextChars.IsIdentChar(mText[mAt - 1])) and
      ((mAt + Length(mName) > Length(mText)) or not TTextChars.IsIdentChar(mText[mAt + Length(mName)])) then
    begin
      Exit(True);
    end;
    mAt := Pos(mName, mText, mAt + 1);
  end;
end;

/// <summary>Beginnt hinter dem "=" an AAt eine Liste "( … )"? AOpen: Stelle der Klammer.</summary>
function EnumListAt(const AText: string; AAt: Integer; out AOpen: Integer): Boolean;
begin
  AOpen := AAt + 1;
  SkipChars(AText, AOpen, [' ', #9, #13, #10]);
  Result := (CharAt(AText, AOpen) = '(') and (CharAt(AText, AOpen + 1) <> '*');
end;

/// <summary>Name eines Werts ohne Zuweisung ("stA = 1" → "stA").</summary>
function MemberName(const APart: string): string;
var
  mEqual: Integer;
begin
  Result := Trim(APart);
  mEqual := Pos('=', Result);
  if mEqual > 0 then
  begin
    Result := Trim(Copy(Result, 1, mEqual - 1));
  end;
end;

function IsMemberName(const AName: string): Boolean;
begin
  Result := (AName <> '') and TTextChars.IsIdentStart(AName[1]) and (Pos(' ', AName) = 0) and (Pos(':', AName) = 0);
end;

/// <summary>Werte der Liste AInner, wenn sie nur aus Bezeichnern besteht und ALowerName enthält.</summary>
function EnumMembers(const AInner, ALowerName: string; out AParts: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  AParts := AInner.Split([',']);
  for mIndex := 0 to High(AParts) do
  begin
    AParts[mIndex] := MemberName(AParts[mIndex]);
    if not IsMemberName(AParts[mIndex]) then
    begin
      AParts := nil;
      Exit(False);
    end;
    Result := Result or (LowerCase(AParts[mIndex]) = ALowerName);
  end;
end;

class function TAtlasPatternContinuation.LocalEnumValues(const AText, AMember: string): TArray<string>;
var
  mName: string;
  mAt, mOpen, mClose: Integer;
  mParts: TArray<string>;
begin
  Result := nil;
  mName := LowerCase(AMember);
  // Jede "= ( … )"-Liste aus Bezeichnern ist ein Aufzählungstyp; die mit AMember gewinnt.
  mAt := Pos('=', AText);
  while mAt > 0 do
  begin
    if EnumListAt(AText, mAt, mOpen) then
    begin
      mClose := Pos(')', AText, mOpen);
      if mClose = 0 then
      begin
        Exit;
      end;
      if EnumMembers(Copy(AText, mOpen + 1, mClose - mOpen - 1), mName, mParts) then
      begin
        Exit(mParts);
      end;
    end;
    mAt := Pos('=', AText, mAt + 1);
  end;
end;

end.
