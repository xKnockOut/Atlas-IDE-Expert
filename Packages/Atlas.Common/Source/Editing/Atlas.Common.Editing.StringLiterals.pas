unit Atlas.Common.Editing.StringLiterals;

// Klartext und String-Literal umwandeln (#312), z. B. für SQL, HTML, JSON
// oder Meldungstexte:
//   - ToLiteral: Klartext wird zum Pascal-Literal, Hochkommas verdoppelt,
//     Steuerzeichen als #9 usw. Die Zeilen werden verkettet (Trenner nach
//     stringLiteral.lineBreak) oder als mehrzeiliger String ''' geschrieben
//     (ab Delphi 12, #109).
//   - PlainText: ein (auch verkettetes) Literal wird zum reinen Text ohne
//     Hochkommas, "+", sLineBreak und #13#10.
//   - LiteralAt: Bereich des verketteten Literals unter dem Cursor.
// Platzhalter wie :Nr oder %s bleiben unverändert. Dieselbe Zerlegung nutzen
// später /multiline (#303) und /sql (#302).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract;

type
  TStringLiterals = class
  public const
    /// <summary>Zeilenende im Klartext (Zwischenablage unter Windows).</summary>
    cPlainLineBreak = #13#10;
  public
    /// <summary>Mehrzeiliger String? Auto nur, wenn AVersion bekannt ist und ihn kennt.</summary>
    class function UseMultiline(AStyle: TStringLiteralStyle; const AVersion: string): Boolean; static;
    /// <summary>Eine Zeile als Literal: 'Kunde''s'#9'Wert'.</summary>
    class function Quote(const ALine: string): string; static;
    /// <summary>APlainText als Literal. Jede Ausgabezeile beginnt mit AIndent, die erste nur mit
    /// AIndentFirst. ALineEnd trennt die Ausgabezeilen.</summary>
    /// ASettings.LineBreak trennt die Textzeilen, ASettings.MaxLineLength bricht lange Zeilen um (0 = nicht).
    class function ToLiteral(const APlainText, AIndent: string; AIndentFirst, AMultiline: Boolean;
      const ASettings: TStringLiteralSettings; const ALineEnd: string): string; static;
    /// <summary>Text eines Literal-Ausdrucks; False, wenn er etwas anderes als Literale,
    /// Zeichenkonstanten, sLineBreak und + enthält.</summary>
    class function PlainText(const AExpression: string; out AText: string): Boolean; static;
    /// <summary>Bereich des (verketteten) Literals an APosition; False ohne.</summary>
    class function LiteralAt(const AText: string; const APosition: TTextPosition; out ARange: TTextRange): Boolean;
      overload; static;
    /// <summary>Wie oben mit den fertigen Token des Texts (aus dem Syntaxbaum).</summary>
    class function LiteralAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
      out ARange: TTextRange): Boolean; overload; static;
    /// <summary>Text in ARange, Zeilen mit #10 getrennt.</summary>
    class function TextOf(const AText: string; const ARange: TTextRange): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Text.Lines;

{ TStringLiterals }

class function TStringLiterals.UseMultiline(AStyle: TStringLiteralStyle; const AVersion: string): Boolean;
begin
  case AStyle of
    TStringLiteralStyle.Multiline:
      Result := True;
    TStringLiteralStyle.Concat:
      Result := False;
  else
    Result := (TLanguageFeatures.ParseVersion(AVersion) > 0) and
      TLanguageFeatures.IsAvailable(TLanguageFeature.MultilineString, AVersion);
  end;
end;

/// <summary>Hängt AText an AResult an; vor das erste Zeichen außerhalb eines Literals kommt das öffnende ',
/// vor ein Steuerzeichen innerhalb das schließende.</summary>
procedure AppendQuoted(var AResult: string; var AInQuote: Boolean; AChar: Char);
begin
  if Ord(AChar) < 32 then
  begin
    if AInQuote then
    begin
      AResult := AResult + '''';
    end;
    AInQuote := False;
    AResult := AResult + '#' + IntToStr(Ord(AChar));
    Exit;
  end;
  if not AInQuote then
  begin
    AResult := AResult + '''';
  end;
  AInQuote := True;
  if AChar = '''' then
  begin
    AResult := AResult + '''''';
  end
  else
  begin
    AResult := AResult + AChar;
  end;
end;

class function TStringLiterals.Quote(const ALine: string): string;
var
  mChar: Char;
  mInQuote: Boolean;
begin
  Result := '';
  mInQuote := False;
  for mChar in ALine do
  begin
    AppendQuoted(Result, mInQuote, mChar);
  end;
  if mInQuote then
  begin
    Result := Result + '''';
  end
  else if Result = '' then
  begin
    Result := '''''';
  end;
end;

/// <summary>Mehrzeiliger String geht nur ohne ''' und ohne Steuerzeichen außer Tab.</summary>
function FitsMultiline(const ALines: TArray<string>): Boolean;
var
  mLine: string;
  C: Char;
begin
  for mLine in ALines do
  begin
    if Pos('''''''', mLine) > 0 then
    begin
      Exit(False);
    end;
    for C in mLine do
    begin
      if (Ord(C) < 32) and (C <> #9) then
      begin
        Exit(False);
      end;
    end;
  end;
  Result := True;
end;

/// <summary>ALine in Stücke, deren Literal höchstens AWidth Zeichen hat (mindestens 10 Zeichen
/// Text je Stück); getrennt wird möglichst hinter einem Leerzeichen.</summary>
function Chunks(const ALine: string; AWidth: Integer): TArray<string>;
var
  mRest: string;
  mSize: Integer;
begin
  Result := nil;
  mRest := ALine;
  while (Length(mRest) > 10) and (Length(TStringLiterals.Quote(mRest)) > AWidth) do
  begin
    mSize := Length(mRest) - 1;
    while (mSize > 10) and (Length(TStringLiterals.Quote(Copy(mRest, 1, mSize))) > AWidth) do
    begin
      Dec(mSize);
    end;
    if LastDelimiter(' ', Copy(mRest, 1, mSize)) > mSize div 2 then
    begin
      mSize := LastDelimiter(' ', Copy(mRest, 1, mSize));
    end;
    Result := Result + [Copy(mRest, 1, mSize)];
    mRest := Copy(mRest, mSize + 1, MaxInt);
  end;
  Result := Result + [mRest];
end;

/// <summary>Ausgabezeilen eines mehrzeiligen Strings; der Compiler entfernt die Einrückung der schließenden '''
/// aus allen Zeilen.</summary>
function MultilineOutput(const ALines: TArray<string>; const AIndent: string): TArray<string>;
var
  mLine: string;
begin
  Result := [''''''''];
  for mLine in ALines do
  begin
    if mLine = '' then
    begin
      Result := Result + [''];
    end
    else
    begin
      Result := Result + [AIndent + '  ' + mLine];
    end;
  end;
  Result := Result + [AIndent + '  ' + ''''''''];
end;

/// <summary>Trenner hinter einer Textzeile, die nicht die letzte ist; bei Space hängt ein Leerzeichen an ALine.
/// </summary>
function LineSeparator(ABreak: TStringLiteralBreak; var ALine: string): string;
begin
  Result := '';
  case ABreak of
    TStringLiteralBreak.SLineBreak:
      Result := ' + sLineBreak';
    TStringLiteralBreak.CrLf:
      Result := '#13#10';
    TStringLiteralBreak.Lf:
      Result := '#10';
    TStringLiteralBreak.Space:
      ALine := ALine + ' ';
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Ausgabezeilen einer Textzeile als verkettete Literale; ALast: letzte Textzeile.</summary>
function ConcatLine(const ALine, AIndent: string; const ASettings: TStringLiteralSettings; ALast: Boolean):
  TArray<string>;
var
  mLine, mSeparator, mPiece: string;
  mParts: TArray<string>;
  mPart: Integer;
begin
  mLine := ALine;
  mSeparator := '';
  if not ALast then
  begin
    mSeparator := LineSeparator(ASettings.LineBreak, mLine);
  end;
  mParts := [mLine];
  if ASettings.MaxLineLength > 0 then
  begin
    mParts := Chunks(mLine, ASettings.MaxLineLength - Length(AIndent) - Length(mSeparator) - 2);
  end;
  Result := nil;
  for mPart := 0 to High(mParts) do
  begin
    mPiece := AIndent + TStringLiterals.Quote(mParts[mPart]);
    if mPart = High(mParts) then
    begin
      mPiece := mPiece + mSeparator;
    end;
    if (mPart < High(mParts)) or not ALast then
    begin
      mPiece := mPiece + ' +';
    end;
    Result := Result + [mPiece];
  end;
end;

class function TStringLiterals.ToLiteral(const APlainText, AIndent: string; AIndentFirst, AMultiline: Boolean;
  const ASettings: TStringLiteralSettings; const ALineEnd: string): string;
var
  mLines, mOutput: TArray<string>;
  mIndex: Integer;
  mMultiline: Boolean;
begin
  mLines := TTextLines.SplitLines(APlainText);
  mOutput := nil;
  mMultiline := AMultiline and FitsMultiline(mLines);
  if mMultiline then
  begin
    mOutput := MultilineOutput(mLines, AIndent);
  end
  else
  begin
    for mIndex := 0 to High(mLines) do
    begin
      mOutput := mOutput + ConcatLine(mLines[mIndex], AIndent, ASettings, mIndex = High(mLines));
    end;
  end;
  // Die erste Zeile steht hinter dem Text davor, z. B. hinter "SQL.Text := ".
  if AIndentFirst and mMultiline then
  begin
    mOutput[0] := AIndent + mOutput[0];
  end
  else if not AIndentFirst and not mMultiline then
  begin
    mOutput[0] := Copy(mOutput[0], Length(AIndent) + 1, MaxInt);
  end;
  Result := string.Join(ALineEnd, mOutput);
end;

/// <summary>Inhalt eines mehrzeiligen Strings: Einrückung der schließenden ''' entfernt.</summary>
function MultilineText(const AToken: string): string;
var
  mLines: TArray<string>;
  mIndent: Integer;
  mIndex: Integer;
begin
  mLines := TTextLines.SplitLines(AToken);
  Result := '';
  if Length(mLines) < 2 then
  begin
    Exit;
  end;
  mIndent := Length(mLines[High(mLines)]) - Length(TrimLeft(mLines[High(mLines)]));
  for mIndex := 1 to High(mLines) - 1 do
  begin
    if mIndex > 1 then
    begin
      Result := Result + TStringLiterals.cPlainLineBreak;
    end;
    Result := Result + Copy(mLines[mIndex], mIndent + 1, MaxInt);
  end;
end;

/// <summary>Wert von #13, #$0D oder #13#10.</summary>
function CharValue(const AToken: string): string;
var
  mPart: string;
  mCode: Integer;
begin
  Result := '';
  for mPart in SplitString(Copy(AToken, 2, MaxInt), '#') do
  begin
    if TryStrToInt(mPart, mCode) then
    begin
      Result := Result + Char(mCode);
    end;
  end;
end;

function IsLiteralToken(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]) or
    ((AToken.Kind = TPascalTokenKind.Identifier) and SameText(AToken.Text, 'sLineBreak'));
end;

class function TStringLiterals.PlainText(const AExpression: string; out AText: string): Boolean;
var
  mToken: TPascalToken;
  mHasString: Boolean;
begin
  AText := '';
  mHasString := False;
  for mToken in TPascalLexer.Tokenize(AExpression) do
    case mToken.Kind of
      TPascalTokenKind.StringLiteral:
        begin
          mHasString := True;
          if StartsStr('''''''', mToken.Text) then
          begin
            AText := AText + MultilineText(mToken.Text);
          end
          else
          begin
            AText := AText + StringReplace(Copy(mToken.Text, 2, Length(mToken.Text) - 2), '''''', '''',
              [rfReplaceAll]);
          end;
        end;
      TPascalTokenKind.CharLiteral:
        AText := AText + CharValue(mToken.Text);
      TPascalTokenKind.Comment:
        ;
      TPascalTokenKind.Identifier:
        if SameText(mToken.Text, 'sLineBreak') then
        begin
          AText := AText + cPlainLineBreak;
        end
        else
        begin
          Exit(False);
        end;
      TPascalTokenKind.Symbol:
        if mToken.Text <> '+' then
        begin
          Exit(False);
        end;
    else
      Exit(False);
    end;
  Result := mHasString;
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function Joins(const AToken: TPascalToken): Boolean;
begin
  Result := IsLiteralToken(AToken) or AToken.IsSymbol('+') or (AToken.Kind = TPascalTokenKind.Comment);
end;

/// <summary>Literal (oder +) an APosition; ein Literal hat Vorrang vor einem + daneben. -1 ohne.</summary>
function HitToken(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ATokens) do
  begin
    if not Before(APosition, ATokens[mIndex].StartPos) and not Before(ATokens[mIndex].EndPos, APosition) and
      (IsLiteralToken(ATokens[mIndex]) or ATokens[mIndex].IsSymbol('+')) then
    begin
      Result := mIndex;
      if IsLiteralToken(ATokens[mIndex]) then
      begin
        Exit;
      end;
    end;
  end;
end;

/// <summary>Steht zwischen AFirst und ALast ein String-Literal?</summary>
function HasStringToken(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := AFirst to ALast do
  begin
    if ATokens[mIndex].Kind = TPascalTokenKind.StringLiteral then
    begin
      Exit(True);
    end;
  end;
end;

class function TStringLiterals.LiteralAt(const AText: string; const APosition: TTextPosition;
  out ARange: TTextRange): Boolean;
begin
  Result := LiteralAt(TPascalLexer.Tokenize(AText), APosition, ARange);
end;

class function TStringLiterals.LiteralAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
  out ARange: TTextRange): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mFirst, mLast, mHit: Integer;
begin
  mTokens := ATokens;
  mHit := HitToken(mTokens, APosition);
  if mHit < 0 then
  begin
    Exit(False);
  end;
  // Nach beiden Seiten über Literale, sLineBreak, + und Kommentare ausdehnen.
  mFirst := mHit;
  while (mFirst > 0) and Joins(mTokens[mFirst - 1]) do
  begin
    Dec(mFirst);
  end;
  mLast := mHit;
  while (mLast < High(mTokens)) and Joins(mTokens[mLast + 1]) do
  begin
    Inc(mLast);
  end;
  while (mFirst <= mLast) and not IsLiteralToken(mTokens[mFirst]) do
  begin
    Inc(mFirst);
  end;
  while (mLast >= mFirst) and not IsLiteralToken(mTokens[mLast]) do
  begin
    Dec(mLast);
  end;
  Result := HasStringToken(mTokens, mFirst, mLast);
  if Result then
  begin
    ARange := TTextRange.Create(mTokens[mFirst].StartPos.Line, mTokens[mFirst].StartPos.Character,
      mTokens[mLast].EndPos.Line, mTokens[mLast].EndPos.Character);
  end;
end;

class function TStringLiterals.TextOf(const AText: string; const ARange: TTextRange): string;
var
  mLines: TArray<string>;
  mLine: Integer;
begin
  mLines := TTextLines.SplitLines(AText);
  Result := '';
  for mLine := ARange.StartPos.Line to ARange.EndPos.Line do
  begin
    if (mLine < 0) or (mLine > High(mLines)) then
    begin
      Continue;
    end;
    if mLine > ARange.StartPos.Line then
    begin
      Result := Result + #10;
    end;
    if (mLine = ARange.StartPos.Line) and (mLine = ARange.EndPos.Line) then
    begin
      Result := Result + Copy(mLines[mLine], ARange.StartPos.Character + 1, ARange.EndPos.Character -
        ARange.StartPos.Character);
    end
    else if mLine = ARange.StartPos.Line then
    begin
      Result := Result + Copy(mLines[mLine], ARange.StartPos.Character + 1, MaxInt);
    end
    else if mLine = ARange.EndPos.Line then
    begin
      Result := Result + Copy(mLines[mLine], 1, ARange.EndPos.Character);
    end
    else
    begin
      Result := Result + mLines[mLine];
    end;
  end;
end;

end.
