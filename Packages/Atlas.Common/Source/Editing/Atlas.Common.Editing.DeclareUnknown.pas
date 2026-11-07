unit Atlas.Common.Editing.DeclareUnknown;

// Unbekannten Bezeichner deklarieren (#471), Teil ohne Namensauflösung:
//   - Slot: getippter Name am Cursor, der eine Variable, ein Feld oder eine Konstante sein kann (kein Punkt
//     davor, kein "(" oder "." dahinter, keine Inline-Deklaration). Ist er Ziel einer Zuweisung, gehört die
//     rechte Seite dazu.
//   - Shape: Form eines Ausdrucks. Vergleiche ergeben Boolean, "/" Extended, div und mod Integer, "as T" den
//     Typ T; sonst entscheidet der erste Operand (TermFirst..TermLast), den der Aufrufer auflöst.
//   - Namen und Platzhalter: Feldname mit F-Konvention, Vorgabewert für Konstanten, "$0" für den Cursor.
// Die Vervollständigung (TCompletionValues.DeclareItems) baut daraus die Einträge; /var aus #294 ist derselbe
// Vorgang als Befehl.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  TUnknownSlot = record
    Name: string;
    NameIndex: Integer;
    NameRange: TTextRange;
    /// <summary>Cursor im Namen: Zeichen ab Namensanfang.</summary>
    CursorOffset: Integer;
    /// <summary>"Name := …"; ValueFirst..ValueLast ist dann die rechte Seite (-1, wenn sie fehlt).</summary>
    AssignTarget: Boolean;
    ValueFirst: Integer;
    ValueLast: Integer;
    /// <summary>Der Name beginnt eine Anweisung in einem Block: "var Name := …" ist dort erlaubt.</summary>
    InlineAllowed: Boolean;
  end;

  TDeclareUnknown = class
  public const
    /// <summary>Platzhalter, wenn sich der Typ nicht ableiten lässt; als Kommentar meldet ihn der Compiler.</summary>
    cTypePlaceholder = '{Typ}';
    cValuePlaceholder = '{Wert}';
  public
    /// <summary>Name am Cursor, der deklariert werden könnte; False sonst.</summary>
    class function Slot(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
      out ASlot: TUnknownSlot): Boolean; static;
    /// <summary>Typ aus der Form des Ausdrucks AFirst..ALast; '' heißt: Typ von ATermFirst..ATermLast.</summary>
    class function Shape(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
      out ATermFirst, ATermLast: Integer): string; static;
    /// <summary>Typ eines Literals (Zahl, String, Zeichen, True/False); '' sonst.</summary>
    class function LiteralType(const AToken: TPascalToken): string; static;
    /// <summary>Bezeichner, dessen Typ der Term AFirst..ALast hat ("A.B(1).C" → C, "F(x)" → F); -1, wenn er mit
    /// einem Index endet oder keiner ist.</summary>
    class function TermName(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Integer; static;
    /// <summary>Folgen die Felder der Klasse der F-Konvention? Ohne Felder ja (Delphi-Stil).</summary>
    class function UsesFieldPrefix(const AFieldNames: TArray<string>): Boolean; static;
    /// <summary>"TotalCount" → "FTotalCount"; ohne APrefix oder mit schon vorhandenem F unverändert.</summary>
    class function FieldName(const AName: string; APrefix: Boolean): string; static;
    /// <summary>Vorgabewert einer Konstanten vom Typ ATypeName; ValuePlaceholder, wenn unbekannt.</summary>
    class function DefaultValue(const ATypeName: string): string; static;
    /// <summary>AText mit "$0" nach AOffset Zeichen.</summary>
    class function WithCaret(const AText: string; AOffset: Integer): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Math;

function Compare(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
  begin
    Result := A.Character - B.Character;
  end;
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function Prev(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function Next(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function IsKeywordIn(const AToken: TPascalToken; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  Result := False;
  if AToken.Kind <> TPascalTokenKind.Keyword then
  begin
    Exit;
  end;
  for mWord in AWords do
  begin
    if AToken.IsKeyword(mWord) then
    begin
      Exit(True);
    end;
  end;
end;

function IsSymbolIn(const AToken: TPascalToken; const ASymbols: array of string): Boolean;
var
  mSymbol: string;
begin
  Result := False;
  for mSymbol in ASymbols do
  begin
    if AToken.IsSymbol(mSymbol) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Ende einer Anweisung auf Klammertiefe 0.</summary>
function EndsStatement(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(';') or IsKeywordIn(AToken, ['end', 'else', 'until', 'except', 'finally']);
end;

/// <summary>Letztes Token vor APosition ohne Kommentare und Direktiven; -1 ohne.</summary>
function LastTokenBefore(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  mIndex := 0;
  while (mIndex <= High(ATokens)) and (Compare(ATokens[mIndex].StartPos, APosition) < 0) do
  begin
    if not IsTrivia(ATokens[mIndex]) then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Bezeichner an AIndex, in oder direkt hinter dem der Cursor steht.</summary>
function IsNameAt(const ATokens: TArray<TPascalToken>; AIndex: Integer; const APosition: TTextPosition): Boolean;
begin
  Result := (AIndex >= 0) and (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    (Compare(APosition, ATokens[AIndex].EndPos) <= 0);
end;

/// <summary>Mitglied ("X.Name"), Aufruf ("Name(" ist #472), Kette ("Name.X") oder generischer Typ.</summary>
function IsLinked(const ATokens: TArray<TPascalToken>; ABefore, AAfter: Integer): Boolean;
begin
  Result := ((ABefore >= 0) and ATokens[ABefore].IsSymbol('.')) or
    ((AAfter <= High(ATokens)) and IsSymbolIn(ATokens[AAfter], ['(', '.', '<', '^']));
end;

/// <summary>Inline-Deklaration ("var Name", "var X: Name", "const Name = …") vor dem Namen in derselben
/// Anweisung.</summary>
function InDeclaration(const ATokens: TArray<TPascalToken>; ABefore: Integer): Boolean;
var
  mScan: Integer;
begin
  Result := False;
  mScan := ABefore;
  while not Result and (mScan >= 0) and not EndsStatement(ATokens[mScan]) and
    not IsKeywordIn(ATokens[mScan], ['begin', 'then', 'do', 'try', 'repeat', 'of']) do
  begin
    Result := IsKeywordIn(ATokens[mScan], ['var', 'const', 'type', 'procedure', 'function', 'property', 'threadvar']);
    mScan := Prev(ATokens, mScan);
  end;
end;

/// <summary>Cursor im Namen: Zeichen ab Namensanfang; auf einer anderen Zeile das Namensende.</summary>
function CursorOffset(const AName: TPascalToken; const APosition: TTextPosition): Integer;
begin
  Result := Length(AName.Text);
  if APosition.Line = AName.StartPos.Line then
  begin
    Result := Max(0, Min(Result, APosition.Character - AName.StartPos.Character));
  end;
end;

/// <summary>Ende der rechten Seite: schließende Klammer auf Tiefe 0 oder Ende der Anweisung; führt ADepth
/// nach.</summary>
function EndsValue(const AToken: TPascalToken; var ADepth: Integer): Boolean;
begin
  Result := False;
  if IsSymbolIn(AToken, ['(', '[']) then
  begin
    Inc(ADepth);
  end
  else if IsSymbolIn(AToken, [')', ']']) then
  begin
    Result := ADepth = 0;
    Dec(ADepth);
  end
  else
  begin
    Result := (ADepth = 0) and EndsStatement(AToken);
  end;
end;

/// <summary>Rechte Seite ab AFrom bis zum Ende der Anweisung in ValueFirst..ValueLast.</summary>
procedure ReadValue(const ATokens: TArray<TPascalToken>; AFrom: Integer; var ASlot: TUnknownSlot);
var
  mScan, mDepth: Integer;
begin
  mDepth := 0;
  mScan := AFrom;
  while (mScan <= High(ATokens)) and not EndsValue(ATokens[mScan], mDepth) do
  begin
    if ASlot.ValueFirst < 0 then
    begin
      ASlot.ValueFirst := mScan;
    end;
    ASlot.ValueLast := mScan;
    mScan := Next(ATokens, mScan);
  end;
end;

{ TDeclareUnknown }

class function TDeclareUnknown.Slot(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
  out ASlot: TUnknownSlot): Boolean;
var
  mBefore, mAfter: Integer;
  mName: TPascalToken;
begin
  ASlot := Default(TUnknownSlot);
  ASlot.ValueFirst := -1;
  ASlot.ValueLast := -1;
  ASlot.NameIndex := LastTokenBefore(ATokens, APosition);
  Result := IsNameAt(ATokens, ASlot.NameIndex, APosition);
  if not Result then
  begin
    Exit;
  end;
  mName := ATokens[ASlot.NameIndex];
  mBefore := Prev(ATokens, ASlot.NameIndex);
  mAfter := Next(ATokens, ASlot.NameIndex);
  Result := not IsLinked(ATokens, mBefore, mAfter) and not InDeclaration(ATokens, mBefore) and
    not StartsText('&', mName.Text);
  if not Result then
  begin
    Exit;
  end;
  ASlot.Name := mName.Text;
  ASlot.NameRange := TTextRange.Create(mName.StartPos, mName.EndPos);
  ASlot.CursorOffset := CursorOffset(mName, APosition);
  ASlot.AssignTarget := (mAfter <= High(ATokens)) and ATokens[mAfter].IsSymbol(':=');
  ASlot.InlineAllowed := ASlot.AssignTarget and (mBefore >= 0) and (ATokens[mBefore].IsSymbol(';') or
    IsKeywordIn(ATokens[mBefore], ['begin', 'try', 'finally', 'except', 'repeat']));
  if ASlot.AssignTarget then
  begin
    ReadValue(ATokens, Next(ATokens, mAfter), ASlot);
  end;
end;

/// <summary>Index der schließenden Klammer zu AIndex ("(" oder "["); ALast, wenn sie fehlt.</summary>
function Closing(const ATokens: TArray<TPascalToken>; AIndex, ALast: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := AIndex;
  while Result <= ALast do
  begin
    if IsSymbolIn(ATokens[Result], ['(', '[']) then
    begin
      Inc(mDepth);
    end
    else if IsSymbolIn(ATokens[Result], [')', ']']) then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end;
    Result := Next(ATokens, Result);
  end;
  Result := ALast;
end;

/// <summary>Binärer Operator.</summary>
function IsOperator(const AToken: TPascalToken): Boolean;
begin
  Result := IsSymbolIn(AToken, ['+', '-', '*', '/', '=', '<>', '<', '>', '<=', '>=']) or
    IsKeywordIn(AToken, ['and', 'or', 'xor', 'div', 'mod', 'shl', 'shr', 'in', 'is', 'as']);
end;

/// <summary>"(" einer Klammergruppe, kein Aufruf ("F(A = B)") und kein Index.</summary>
function IsGroupOpen(const ATokens: TArray<TPascalToken>; AFirst, AIndex: Integer): Boolean;
var
  mBefore: Integer;
begin
  Result := ATokens[AIndex].IsSymbol('(');
  if Result and (AIndex <> AFirst) then
  begin
    mBefore := Prev(ATokens, AIndex);
    Result := not ((ATokens[mBefore].Kind = TPascalTokenKind.Identifier) or IsSymbolIn(ATokens[mBefore], [')', ']']));
  end;
end;

/// <summary>Geklammerter Vergleich ab AIndex ("(A > 1) and B").</summary>
function IsGroupedComparison(const ATokens: TArray<TPascalToken>; AFirst, AIndex, ALast: Integer): Boolean;
var
  mTermFirst, mTermLast: Integer;
begin
  Result := IsGroupOpen(ATokens, AFirst, AIndex) and (TDeclareUnknown.Shape(ATokens, Next(ATokens, AIndex),
    Prev(ATokens, Closing(ATokens, AIndex, ALast)), mTermFirst, mTermLast) = 'Boolean');
end;

type
  /// <summary>Operatoren auf oberster Ebene eines Ausdrucks, die seinen Typ festlegen.</summary>
  TExpressionShape = record
    Comparison: Boolean;
    Divides: Boolean;
    IntegerDivides: Boolean;
    /// <summary>Token hinter "as"; -1 ohne.</summary>
    AsType: Integer;
    procedure Scan(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer);
    procedure Note(const ATokens: TArray<TPascalToken>; AIndex: Integer);
    /// <summary>Boolean, Typ hinter "as" am Ende, Extended oder Integer; '' ohne solchen Operator.</summary>
    function TypeName(const ATokens: TArray<TPascalToken>; ALast: Integer): string;
  end;

procedure TExpressionShape.Scan(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer);
var
  mIndex: Integer;
begin
  Comparison := False;
  Divides := False;
  IntegerDivides := False;
  AsType := -1;
  mIndex := AFirst;
  while mIndex <= ALast do
  begin
    Comparison := Comparison or IsGroupedComparison(ATokens, AFirst, mIndex, ALast);
    if IsSymbolIn(ATokens[mIndex], ['(', '[']) then
    begin
      mIndex := Closing(ATokens, mIndex, ALast);
    end
    else
    begin
      Note(ATokens, mIndex);
    end;
    mIndex := Next(ATokens, mIndex);
  end;
end;

procedure TExpressionShape.Note(const ATokens: TArray<TPascalToken>; AIndex: Integer);
begin
  if IsSymbolIn(ATokens[AIndex], ['=', '<>', '<', '>', '<=', '>=']) or IsKeywordIn(ATokens[AIndex], ['in', 'is']) then
  begin
    Comparison := True;
  end
  else if ATokens[AIndex].IsSymbol('/') then
  begin
    Divides := True;
  end
  else if IsKeywordIn(ATokens[AIndex], ['div', 'mod']) then
  begin
    IntegerDivides := True;
  end
  else if ATokens[AIndex].IsKeyword('as') then
  begin
    AsType := Next(ATokens, AIndex);
  end;
end;

function TExpressionShape.TypeName(const ATokens: TArray<TPascalToken>; ALast: Integer): string;
begin
  Result := '';
  if Comparison then
  begin
    Result := 'Boolean';
  end
  else if (AsType >= 0) and (AsType = ALast) and (ATokens[AsType].Kind = TPascalTokenKind.Identifier) then
  begin
    Result := ATokens[AsType].Text;
  end
  else if Divides then
  begin
    Result := 'Extended';
  end
  else if IntegerDivides then
  begin
    Result := 'Integer';
  end;
end;

/// <summary>Erster Operand ohne Vorzeichen und not in ATermFirst..ATermLast; 'Pointer' für "@X", sonst ''.</summary>
function FirstTerm(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  out ATermFirst, ATermLast: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  ATermFirst := AFirst;
  while (ATermFirst < ALast) and (IsSymbolIn(ATokens[ATermFirst], ['-', '+']) or ATokens[ATermFirst].IsKeyword('not')) do
  begin
    ATermFirst := Next(ATokens, ATermFirst);
  end;
  ATermLast := -1;
  if ATokens[ATermFirst].IsSymbol('@') then
  begin
    ATermFirst := -1;
    Exit('Pointer');
  end;
  ATermLast := ATermFirst;
  mIndex := ATermFirst;
  while (mIndex <= ALast) and ((mIndex = ATermFirst) or not IsOperator(ATokens[mIndex])) do
  begin
    if IsSymbolIn(ATokens[mIndex], ['(', '[']) then
    begin
      mIndex := Closing(ATokens, mIndex, ALast);
    end;
    ATermLast := mIndex;
    mIndex := Next(ATokens, mIndex);
  end;
end;

class function TDeclareUnknown.Shape(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  out ATermFirst, ATermLast: Integer): string;
var
  mShape: TExpressionShape;
begin
  Result := '';
  ATermFirst := -1;
  ATermLast := -1;
  if (AFirst < 0) or (ALast < AFirst) then
  begin
    Exit;
  end;
  mShape.Scan(ATokens, AFirst, ALast);
  Result := mShape.TypeName(ATokens, ALast);
  if Result = '' then
  begin
    Result := FirstTerm(ATokens, AFirst, ALast, ATermFirst, ATermLast);
  end;
end;

class function TDeclareUnknown.LiteralType(const AToken: TPascalToken): string;
begin
  Result := '';
  case AToken.Kind of
    TPascalTokenKind.Number:
      if (AToken.Text[1] <> '$') and (AToken.Text[1] <> '%') and
        ((Pos('.', AToken.Text) > 0) or (Pos('e', LowerCase(AToken.Text)) > 0)) then
      begin
        Result := 'Extended';
      end
      else
      begin
        Result := 'Integer';
      end;
    TPascalTokenKind.StringLiteral:
      if (Length(AToken.Text) = 3) or (AToken.Text = '''''''''') then
      begin
        Result := 'Char';
      end
      else
      begin
        Result := 'string';
      end;
    TPascalTokenKind.CharLiteral:
      Result := 'Char';
    TPascalTokenKind.Identifier:
      if SameText(AToken.Text, 'True') or SameText(AToken.Text, 'False') then
      begin
        Result := 'Boolean';
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TDeclareUnknown.TermName(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Integer;
var
  mDepth: Integer;
begin
  Result := -1;
  if (AFirst < 0) or (ALast < AFirst) then
  begin
    Exit;
  end;
  // Aufruf am Ende überspringen: "F(x)" hat den Typ von F.
  if ATokens[ALast].IsSymbol(')') then
  begin
    mDepth := 0;
    while ALast >= AFirst do
    begin
      if ATokens[ALast].IsSymbol(')') then
      begin
        Inc(mDepth);
      end
      else if ATokens[ALast].IsSymbol('(') then
      begin
        Dec(mDepth);
        if mDepth = 0 then
        begin
          Break;
        end;
      end;
      ALast := Prev(ATokens, ALast);
    end;
    ALast := Prev(ATokens, ALast);
  end;
  if (ALast >= AFirst) and (ATokens[ALast].Kind = TPascalTokenKind.Identifier) then
  begin
    Result := ALast;
  end;
end;

class function TDeclareUnknown.UsesFieldPrefix(const AFieldNames: TArray<string>): Boolean;
var
  mName: string;
  mPrefixed: Integer;
begin
  mPrefixed := 0;
  for mName in AFieldNames do
  begin
    if (Length(mName) >= 2) and (mName[1] = 'F') and CharInSet(mName[2], ['A'..'Z']) then
    begin
      Inc(mPrefixed);
    end;
  end;
  Result := 2 * mPrefixed >= Length(AFieldNames);
end;

class function TDeclareUnknown.FieldName(const AName: string; APrefix: Boolean): string;
begin
  Result := AName;
  if not APrefix or (AName = '') then
  begin
    Exit;
  end;
  if (Length(AName) >= 2) and (AName[1] = 'F') and CharInSet(AName[2], ['A'..'Z']) then
  begin
    Exit;
  end;
  Result := 'F' + UpperCase(Copy(AName, 1, 1)) + Copy(AName, 2, MaxInt);
end;

class function TDeclareUnknown.DefaultValue(const ATypeName: string): string;
const
  cIntegers: array[0..12] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'LongInt', 'LongWord', 'ShortInt', 'SmallInt', 'Int32');
  cFloats: array[0..4] of string = ('Extended', 'Double', 'Single', 'Currency', 'Real');
var
  mName: string;
begin
  for mName in cIntegers do
  begin
    if SameText(mName, ATypeName) then
    begin
      Exit('0');
    end;
  end;
  for mName in cFloats do
  begin
    if SameText(mName, ATypeName) then
    begin
      Exit('0.0');
    end;
  end;
  if SameText(ATypeName, 'string') or SameText(ATypeName, 'UnicodeString') then
  begin
    Exit('''''');
  end;
  if SameText(ATypeName, 'Boolean') then
  begin
    Exit('False');
  end;
  Result := cValuePlaceholder;
end;

class function TDeclareUnknown.WithCaret(const AText: string; AOffset: Integer): string;
begin
  AOffset := Max(0, Min(AOffset, Length(AText)));
  Result := Copy(AText, 1, AOffset) + '$0' + Copy(AText, AOffset + 1, MaxInt);
end;

end.
