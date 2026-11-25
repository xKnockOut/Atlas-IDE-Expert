unit Atlas.Text.PascalScan;

// Wörter und Zeichen in Delphi-Quelltext außerhalb von Kommentaren,
// Compileranweisungen und Zeichenketten finden (gemeinsam für Server und
// Plugin). Für Stellen, die in kleinen Texten wie Projektdateien nur einzelne
// Wörter suchen und dafür keinen Lexer haben.
// Jede Suche läuft nur vorwärts: Ein Kommentar oder eine Anweisung ohne
// Abschluss reicht bis zum Textende, die Suche endet dann mit „nicht
// gefunden“; eine einzeilige Zeichenkette ohne Abschluss endet am
// Zeilenende, gesucht wird in der nächsten Zeile weiter. Ob ein Text solche
// offenen Stellen hat, sagt IsClosed; wer einen Text umschreiben will, prüft
// das vorher, weil der Compiler ihn ohnehin nicht übersetzt.
// Kein Schritt legt Teilkopien des Texts an: Die Arbeit wächst linear mit der
// Länge, auch bei ganzen Units mit vielen Zeichenketten.
// Erkannt werden {…}, (*…*), //… bis zum Zeilenende, '…' bis zum nächsten
// Hochkomma in derselben Zeile ('' darin sind zwei Zeichenketten hintereinander)
// und mehrzeilige Zeichenketten ab Delphi 12 (''' am Zeilenende bis zum
// nächsten ''').

interface

type
  TPascalScan = class
  public
    /// <summary>Position (ab 1) hinter dem Kommentar oder der Zeichenkette, die bei AIndex beginnt; AIndex selbst,
    /// wenn dort keins beginnt. Fehlt der Abschluss, Length(AText) + 1, bei einer einzeiligen Zeichenkette die
    /// Position des Zeilenendes. Beginnt bei AIndex etwas, ist das Ergebnis immer größer als AIndex.</summary>
    class function SkipNoise(const AText: string; AIndex: Integer): Integer; static;
    /// <summary>Sind alle Kommentare, Anweisungen und Zeichenketten in AText abgeschlossen?</summary>
    class function IsClosed(const AText: string): Boolean; static;
    /// <summary>Position (ab 1) des ersten Kommentars, der ersten Anweisung oder Zeichenkette ohne Abschluss; 0, wenn
    /// alle abgeschlossen sind.</summary>
    class function FirstOpen(const AText: string): Integer; static;
    /// <summary>Position (ab 1) des Worts AWord ab AFrom außerhalb von Kommentaren und Zeichenketten, ohne Rücksicht
    /// auf Groß-/Kleinschreibung; 0 ohne. Teil eines längeren oder qualifizierten Namens (X.uses, &amp;in) zählt
    /// nicht.</summary>
    class function FindWord(const AText, AWord: string; AFrom: Integer): Integer; static;
    /// <summary>Position (ab 1) des Zeichens AChar ab AFrom außerhalb von Kommentaren und Zeichenketten; 0 ohne.
    /// </summary>
    class function FindChar(const AText: string; AChar: Char; AFrom: Integer): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Chars;

const
  cMultiQuote = '''''''';

/// <summary>Folgt AText ab AIndex die Zeichenfolge APart? Vergleicht zeichenweise, ohne Teilkopie.</summary>
function At(const AText: string; AIndex: Integer; const APart: string): Boolean;
var
  mOffset: Integer;
begin
  Result := (AIndex >= 1) and (AIndex + Length(APart) - 1 <= Length(AText));
  mOffset := 0;
  while Result and (mOffset < Length(APart)) do
  begin
    Result := AText[AIndex + mOffset] = APart[mOffset + 1];
    Inc(mOffset);
  end;
end;

/// <summary>Folgt AText ab AIndex das Wort AWord, ohne Rücksicht auf Groß-/Kleinschreibung der ASCII-Buchstaben
/// (wie SameText)? Vergleicht zeichenweise, ohne Teilkopie.</summary>
function AtIgnoringCase(const AText: string; AIndex: Integer; const AWord: string): Boolean;
var
  mOffset: Integer;
begin
  Result := (AIndex >= 1) and (AIndex + Length(AWord) - 1 <= Length(AText));
  mOffset := 0;
  while Result and (mOffset < Length(AWord)) do
  begin
    Result := UpCase(AText[AIndex + mOffset]) = UpCase(AWord[mOffset + 1]);
    Inc(mOffset);
  end;
end;

/// <summary>Position des ersten Zeilenendes (#13 oder #10) ab AIndex; Length(AText) + 1 ohne.</summary>
function LineEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and not CharInSet(AText[Result], [#13, #10]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Steht ab AIndex bis zum Zeilenende nur Leerraum?</summary>
function OnlyBlanksToLineEnd(const AText: string; AIndex: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := AIndex;
  while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], [' ', #9]) do
  begin
    Inc(mIndex);
  end;
  Result := (mIndex > Length(AText)) or CharInSet(AText[mIndex], [#13, #10]);
end;

/// <summary>Position hinter ACloser ab AFrom; Length(AText) + 1 und AClosed False ohne.</summary>
function After(const AText, ACloser: string; AFrom: Integer; out AClosed: Boolean): Integer;
var
  mFound: Integer;
begin
  mFound := PosEx(ACloser, AText, AFrom);
  AClosed := mFound > 0;
  Result := Length(AText) + 1;
  if AClosed then
  begin
    Result := mFound + Length(ACloser);
  end;
end;

/// <summary>Ende der Zeichenkette ab AIndex (auf dem Hochkomma).</summary>
function StringEnd(const AText: string; AIndex: Integer; out AClosed: Boolean): Integer;
begin
  if At(AText, AIndex, cMultiQuote) and OnlyBlanksToLineEnd(AText, AIndex + Length(cMultiQuote)) then
  begin
    Exit(After(AText, cMultiQuote, AIndex + Length(cMultiQuote), AClosed));
  end;
  // Bis zum nächsten Hochkomma oder Zeilenende, was zuerst kommt; ohne Hochkomma in derselben Zeile endet die
  // Zeichenkette offen am Zeilenende. Die Suche geht nie über die Zeile hinaus.
  Result := AIndex + 1;
  while (Result <= Length(AText)) and not CharInSet(AText[Result], ['''', #13, #10]) do
  begin
    Inc(Result);
  end;
  AClosed := (Result <= Length(AText)) and (AText[Result] = '''');
  if AClosed then
  begin
    Inc(Result);
  end;
end;

/// <summary>Wie SkipNoise; AClosed sagt, ob das Übersprungene einen Abschluss hat.</summary>
function NoiseEnd(const AText: string; AIndex: Integer; out AClosed: Boolean): Integer;
begin
  AClosed := True;
  Result := AIndex;
  if (AIndex < 1) or (AIndex > Length(AText)) then
  begin
    Exit;
  end;
  if AText[AIndex] = '{' then
  begin
    Result := After(AText, '}', AIndex + 1, AClosed);
  end
  else if At(AText, AIndex, '(*') then
  begin
    // Ab dem Zeichen hinter "(*" suchen: "(*)" ist kein abgeschlossener Kommentar.
    Result := After(AText, '*)', AIndex + 2, AClosed);
  end
  else if At(AText, AIndex, '//') then
  begin
    Result := LineEnd(AText, AIndex + 2);
  end
  else if AText[AIndex] = '''' then
  begin
    Result := StringEnd(AText, AIndex, AClosed);
  end;
end;

/// <summary>Steht AWord bei AIndex als ganzes Wort?</summary>
function IsWordAt(const AText, AWord: string; AIndex: Integer): Boolean;
var
  mAfter: Integer;
begin
  mAfter := AIndex + Length(AWord);
  Result := AtIgnoringCase(AText, AIndex, AWord) and
    ((AIndex = 1) or not (TTextChars.IsIdentChar(AText[AIndex - 1]) or CharInSet(AText[AIndex - 1], ['.', '&']))) and
    ((mAfter > Length(AText)) or not TTextChars.IsIdentChar(AText[mAfter]));
end;

type
  TCodeMatch = reference to function(AIndex: Integer): Boolean;

/// <summary>Erste Position ab AFrom außerhalb von Kommentaren und Zeichenketten, an der AMatch zutrifft; 0 ohne.
/// Der Index wächst in jedem Schritt, die Suche endet also auch bei offenen Kommentaren.</summary>
function FindCode(const AText: string; AFrom: Integer; const AMatch: TCodeMatch): Integer;
var
  mIndex, mNext: Integer;
begin
  mIndex := AFrom;
  if mIndex < 1 then
  begin
    mIndex := 1;
  end;
  while mIndex <= Length(AText) do
  begin
    mNext := TPascalScan.SkipNoise(AText, mIndex);
    if mNext > mIndex then
    begin
      mIndex := mNext;
    end
    else if AMatch(mIndex) then
    begin
      Exit(mIndex);
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
  Result := 0;
end;

{ TPascalScan }

class function TPascalScan.SkipNoise(const AText: string; AIndex: Integer): Integer;
var
  mClosed: Boolean;
begin
  Result := NoiseEnd(AText, AIndex, mClosed);
end;

class function TPascalScan.IsClosed(const AText: string): Boolean;
begin
  Result := FirstOpen(AText) = 0;
end;

class function TPascalScan.FirstOpen(const AText: string): Integer;
var
  mIndex, mNext: Integer;
  mClosed: Boolean;
begin
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    mNext := NoiseEnd(AText, mIndex, mClosed);
    if not mClosed then
    begin
      Exit(mIndex);
    end;
    if mNext > mIndex then
    begin
      mIndex := mNext;
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
  Result := 0;
end;

class function TPascalScan.FindWord(const AText, AWord: string; AFrom: Integer): Integer;
var
  mText, mWord: string;
begin
  mText := AText;
  mWord := AWord;
  Result := FindCode(AText, AFrom,
    function(AIndex: Integer): Boolean
    begin
      Result := IsWordAt(mText, mWord, AIndex);
    end);
end;

class function TPascalScan.FindChar(const AText: string; AChar: Char; AFrom: Integer): Integer;
var
  mText: string;
  mChar: Char;
begin
  mText := AText;
  mChar := AChar;
  Result := FindCode(AText, AFrom,
    function(AIndex: Integer): Boolean
    begin
      Result := mText[AIndex] = mChar;
    end);
end;

end.
