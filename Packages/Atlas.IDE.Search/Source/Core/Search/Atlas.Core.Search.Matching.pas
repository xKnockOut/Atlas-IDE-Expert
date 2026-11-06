unit Atlas.Core.Search.Matching;

// Atlas-Suche (#877, #878), Teil ohne VCL und Open Tools API: Treffer in
// Zeilen eines Textes suchen und zum nächsten bzw. vorigen springen.
// - Textmodus: Teilstring je Zeile, ohne Überlappung; wahlweise mit Groß- und
//   Kleinschreibung und nur ganze Wörter (davor und dahinter kein Buchstabe,
//   keine Ziffer, kein „_“).
// - Bezeichner-Modus: ein kleiner Lexer überspringt Kommentare ({ }, (* *),
//   //), Direktiven, Strings (auch mehrzeilige ''' … ''' ab Delphi 12),
//   Zeichenkonstanten (#13) und Zahlen ($FF); Treffer sind nur Bezeichner mit
//   dem Namen, ohne Rücksicht auf Groß-/Kleinschreibung wie in Pascal.
//   Reservierte Wörter zählen nur escapt (&begin). Mitglieder gleichen Namens
//   hinter "." zählen mit: Der Lexer kennt keine Symbole.
// - Regex (#893): Ausdruck nach System.RegularExpressions (PCRE) je Zeile;
//   leere Treffer zählen nicht. Mit „ganzes Wort“ muss der Treffer an
//   Wortgrenzen stehen, mit „Bezeichner statt Text“ ganz außerhalb von
//   Kommentaren und Strings liegen (CodeOnly, derselbe Lexer wie der
//   Bezeichner-Modus). Ein ungültiger Ausdruck findet nichts; den Fehlertext
//   liefert TAtlasSearchRegex.Check.
// - Bereich: Nur Treffer, die ganz im Bereich liegen (Routine, Unit, Auswahl;
//   siehe Atlas.Core.Search.Scopes).
// - Weitersuchen (F3/Umschalt+F3): vorwärts der erste Treffer ab der
//   Position, rückwärts der letzte davor; am Ende bzw. Anfang geht es von der
//   anderen Seite weiter (Umlauf).
// Zeilen und Zeichen sind 0-basiert; ein #13 am Zeilenende zählt nicht.

interface

uses
  System.SysUtils,
  System.RegularExpressions;

type
  {$SCOPEDENUMS ON}
  /// <summary>Suchbereich: ganze Unit (Vorgabe, auch für Default()), Routine am Cursor (mit lokalen
  /// Deklarationen), Auswahl; über Dateien (#893): offene Dateien, aktives Projekt, Projektgruppe. Die
  /// Reihenfolge ist die der Bereichsliste in der Suchleiste.</summary>
  TAtlasSearchScope = (UnitFile, Method, Selection, OpenFiles, Project, ProjectGroup);
  {$SCOPEDENUMS OFF}

  TAtlasSearchOptions = record
    CaseSensitive: Boolean;
    WholeWord: Boolean;
    /// <summary>Nur Bezeichner, keine Kommentare und Strings (Groß-/Kleinschreibung egal wie in Pascal).</summary>
    Identifier: Boolean;
    /// <summary>Suchtext ist ein regulärer Ausdruck (#893, search.regex).</summary>
    Regex: Boolean;
    class function Create(ACaseSensitive, AWholeWord, AIdentifier: Boolean): TAtlasSearchOptions; overload; static;
    class function Create(ACaseSensitive, AWholeWord, AIdentifier, ARegex: Boolean): TAtlasSearchOptions; overload;
      static;
  end;

  /// <summary>Position im Text, 0-basiert.</summary>
  TAtlasSearchPos = record
    Line: Integer;
    Character: Integer;
    class function Create(ALine, ACharacter: Integer): TAtlasSearchPos; static;
    /// <summary>-1, 0 oder 1 wie CompareValue.</summary>
    class function Compare(const A, B: TAtlasSearchPos): Integer; static;
  end;

  /// <summary>Bereich von Start (einschließlich) bis Stop (ausschließlich).</summary>
  TAtlasSearchArea = record
    Start: TAtlasSearchPos;
    Stop: TAtlasSearchPos;
    class function Create(AStartLine, AStartCharacter, AStopLine, AStopCharacter: Integer): TAtlasSearchArea; static;
    /// <summary>Ganzer Text der Zeilen.</summary>
    class function Whole(const ALines: TArray<string>): TAtlasSearchArea; static;
    function IsEmpty: Boolean;
    /// <summary>Liegt der Abschnitt [AFrom, ATo) ganz im Bereich?</summary>
    function Covers(const AFrom, ATo: TAtlasSearchPos): Boolean;
    function Contains(const APos: TAtlasSearchPos): Boolean;
  end;

  TAtlasSearchHit = record
    Line: Integer;
    Character: Integer;
    Length: Integer;
    class function Create(ALine, ACharacter, ALength: Integer): TAtlasSearchHit; static;
    function StartPos: TAtlasSearchPos;
    function StopPos: TAtlasSearchPos;
  end;

  /// <summary>Die zuletzt benutzte Suche (F3/Umschalt+F3 machen damit weiter).</summary>
  TAtlasSearchQuery = record
    Text: string;
    Options: TAtlasSearchOptions;
    Scope: TAtlasSearchScope;
    /// <summary>Stufe der Routine bei Scope Method: 0 = innerste.</summary>
    Level: Integer;
    /// <summary>Bereich beim Suchen; bei Scope Selection maßgeblich (die Auswahl wandert mit den Treffern).</summary>
    Area: TAtlasSearchArea;
    FileName: string;
    function IsEmpty: Boolean;
  end;

  TAtlasTextSearch = class
  public
    /// <summary>„12: Zeilentext“ für die Trefferliste (Zeile 1-basiert, Text ohne Einzug, höchstens 200 Zeichen).
    /// </summary>
    class function HitCaption(const ALines: TArray<string>; const AHit: TAtlasSearchHit): string; static;
    /// <summary>Zeilentext des Treffers ohne Einzug, Tabs als Leerzeichen, höchstens 200 Zeichen.</summary>
    class function HitText(const ALines: TArray<string>; const AHit: TAtlasSearchHit): string; static;
    /// <summary>Alle Treffer von ANeedle im Bereich, in Textreihenfolge; leerer Suchtext = keine.</summary>
    class function FindAll(const ALines: TArray<string>; const ANeedle: string; const AOptions: TAtlasSearchOptions;
      const AArea: TAtlasSearchArea): TArray<TAtlasSearchHit>; static;
    /// <summary>Index des nächsten (ABackward: vorigen) Treffers ab AFrom; vorwärts zählt ein Treffer, der an
    /// AFrom beginnt, rückwärts nur einer, der davor beginnt. AWrapped: von der anderen Seite weiter. -1 ohne
    /// Treffer.</summary>
    class function Next(const AHits: TArray<TAtlasSearchHit>; const AFrom: TAtlasSearchPos; ABackward: Boolean;
      out AWrapped: Boolean): Integer; static;
    /// <summary>Bezeichner an bzw. direkt vor der Position (für den Vorschlag im Suchfeld); '' ohne.</summary>
    class function WordAt(const ALine: string; ACharacter: Integer): string; static;
    /// <summary>Reserviertes Wort von Delphi (begin, end, if …), klein oder groß.</summary>
    class function IsReserved(const AWord: string): Boolean; static;
    /// <summary>Zeilen ohne #13 am Ende, in denen Kommentare, Direktiven und Strings (auch mehrzeilige) durch
    /// CodeMask ersetzt sind; Länge und Spalten bleiben gleich.</summary>
    class function CodeOnly(const ALines: TArray<string>): TArray<string>; static;
  public const
    /// <summary>Ersatzzeichen in CodeOnly.</summary>
    CodeMask = #0;
  end;

  TAtlasSearchRegex = class
  public
    /// <summary>Gültiger Ausdruck? Sonst False mit dem Fehlertext der Regex-Engine. Leer ist gültig.</summary>
    class function Check(const APattern: string; out AError: string): Boolean; static;
    /// <summary>Optionen der Engine zur Suche (Groß-/Kleinschreibung).</summary>
    class function Options(const AOptions: TAtlasSearchOptions): TRegExOptions; static;
  end;

implementation

uses
  System.Character,
  System.Generics.Collections,
  System.Math,
  Atlas.Text.Chars;

{ TAtlasSearchOptions }

class function TAtlasSearchOptions.Create(ACaseSensitive, AWholeWord, AIdentifier: Boolean): TAtlasSearchOptions;
begin
  Result.CaseSensitive := ACaseSensitive;
  Result.WholeWord := AWholeWord;
  Result.Identifier := AIdentifier;
  Result.Regex := False;
end;

class function TAtlasSearchOptions.Create(ACaseSensitive, AWholeWord, AIdentifier,
  ARegex: Boolean): TAtlasSearchOptions;
begin
  Result := Create(ACaseSensitive, AWholeWord, AIdentifier);
  Result.Regex := ARegex;
end;

{ TAtlasSearchPos }

class function TAtlasSearchPos.Create(ALine, ACharacter: Integer): TAtlasSearchPos;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

class function TAtlasSearchPos.Compare(const A, B: TAtlasSearchPos): Integer;
begin
  if A.Line < B.Line then
  begin
    Result := -1;
  end
  else if A.Line > B.Line then
  begin
    Result := 1;
  end
  else if A.Character < B.Character then
  begin
    Result := -1;
  end
  else if A.Character > B.Character then
  begin
    Result := 1;
  end
  else
  begin
    Result := 0;
  end;
end;

{ TAtlasSearchArea }

class function TAtlasSearchArea.Create(AStartLine, AStartCharacter, AStopLine,
  AStopCharacter: Integer): TAtlasSearchArea;
begin
  Result.Start := TAtlasSearchPos.Create(AStartLine, AStartCharacter);
  Result.Stop := TAtlasSearchPos.Create(AStopLine, AStopCharacter);
end;

class function TAtlasSearchArea.Whole(const ALines: TArray<string>): TAtlasSearchArea;
begin
  if Length(ALines) = 0 then
  begin
    Result := Create(0, 0, 0, 0);
  end
  else
  begin
    Result := Create(0, 0, High(ALines), Length(ALines[High(ALines)]));
  end;
end;

function TAtlasSearchArea.IsEmpty: Boolean;
begin
  Result := TAtlasSearchPos.Compare(Start, Stop) >= 0;
end;

function TAtlasSearchArea.Covers(const AFrom, ATo: TAtlasSearchPos): Boolean;
begin
  Result := (TAtlasSearchPos.Compare(Start, AFrom) <= 0) and (TAtlasSearchPos.Compare(ATo, Stop) <= 0);
end;

function TAtlasSearchArea.Contains(const APos: TAtlasSearchPos): Boolean;
begin
  Result := (TAtlasSearchPos.Compare(Start, APos) <= 0) and (TAtlasSearchPos.Compare(APos, Stop) <= 0);
end;

{ TAtlasSearchHit }

class function TAtlasSearchHit.Create(ALine, ACharacter, ALength: Integer): TAtlasSearchHit;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.Length := ALength;
end;

function TAtlasSearchHit.StartPos: TAtlasSearchPos;
begin
  Result := TAtlasSearchPos.Create(Line, Character);
end;

function TAtlasSearchHit.StopPos: TAtlasSearchPos;
begin
  Result := TAtlasSearchPos.Create(Line, Character + Length);
end;

{ TAtlasSearchQuery }

function TAtlasSearchQuery.IsEmpty: Boolean;
begin
  Result := Text = '';
end;

{ TAtlasTextSearch }

/// <summary>Zeile ohne #13 am Ende.</summary>
function CleanLine(const ALine: string): string;
begin
  Result := ALine;
  if (Result <> '') and (Result[Length(Result)] = #13) then
  begin
    SetLength(Result, Length(Result) - 1);
  end;
end;

class function TAtlasTextSearch.HitText(const ALines: TArray<string>; const AHit: TAtlasSearchHit): string;
const
  MaxText = 200;
begin
  Result := '';
  if (AHit.Line >= 0) and (AHit.Line <= High(ALines)) then
  begin
    Result := Trim(CleanLine(ALines[AHit.Line]).Replace(#9, ' '));
  end;
  if Length(Result) > MaxText then
  begin
    Result := Copy(Result, 1, MaxText) + '…';
  end;
end;

class function TAtlasTextSearch.HitCaption(const ALines: TArray<string>; const AHit: TAtlasSearchHit): string;
begin
  Result := IntToStr(AHit.Line + 1) + ': ' + HitText(ALines, AHit);
end;

class function TAtlasTextSearch.IsReserved(const AWord: string): Boolean;
const
  Words: array[0..64] of string = ('and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor',
    'destructor', 'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except', 'exports', 'file',
    'finalization', 'finally', 'for', 'function', 'goto', 'if', 'implementation', 'in', 'inherited',
    'initialization', 'inline', 'interface', 'is', 'label', 'library', 'mod', 'nil', 'not', 'object', 'of', 'or',
    'packed', 'procedure', 'program', 'property', 'raise', 'record', 'repeat', 'resourcestring', 'set', 'shl', 'shr',
    'string', 'then', 'threadvar', 'to', 'try', 'type', 'unit', 'until', 'uses', 'var', 'while', 'with', 'xor',
    'operator');
var
  Lower, Word: string;
begin
  Lower := LowerCase(AWord);
  for Word in Words do
  begin
    if Word = Lower then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasTextSearch.WordAt(const ALine: string; ACharacter: Integer): string;
var
  Line: string;
  First, Last: Integer;
begin
  Result := '';
  Line := CleanLine(ALine);
  // 0-basiert → 1-basiert; steht der Cursor direkt hinter dem Wort, zählt es auch.
  First := ACharacter + 1;
  if (First > Length(Line)) or ((First >= 1) and not TTextChars.IsIdentChar(Line[First])) then
  begin
    Dec(First);
  end;
  if (First < 1) or (First > Length(Line)) or not TTextChars.IsIdentChar(Line[First]) then
  begin
    Exit;
  end;
  Last := First;
  while (First > 1) and TTextChars.IsIdentChar(Line[First - 1]) do
  begin
    Dec(First);
  end;
  while (Last < Length(Line)) and TTextChars.IsIdentChar(Line[Last + 1]) do
  begin
    Inc(Last);
  end;
  Result := Copy(Line, First, Last - First + 1);
end;

/// <summary>Steht der Abschnitt [AAt, AStop) (1-basiert) an Wortgrenzen der Zeile?</summary>
function IsWholeWordAt(const ALine: string; AAt, AStop: Integer): Boolean;
begin
  Result := ((AAt = 1) or not TTextChars.IsIdentChar(ALine[AAt - 1])) and
    ((AStop > Length(ALine)) or not TTextChars.IsIdentChar(ALine[AStop]));
end;

/// <summary>Treffer anhängen, wenn er ganz im Bereich liegt.</summary>
procedure AddCovered(AHits: TList<TAtlasSearchHit>; const AArea: TAtlasSearchArea; ALine, ACharacter,
  ALength: Integer);
var
  mHit: TAtlasSearchHit;
begin
  mHit := TAtlasSearchHit.Create(ALine, ACharacter, ALength);
  if AArea.Covers(mHit.StartPos, mHit.StopPos) then
  begin
    AHits.Add(mHit);
  end;
end;

/// <summary>Textmodus: Treffer einer Zeile.</summary>
procedure FindInLine(const ALine: string; ALineIndex: Integer; const ANeedle: string;
  const AOptions: TAtlasSearchOptions; const AArea: TAtlasSearchArea; AHits: TList<TAtlasSearchHit>);
var
  Line, Haystack, Needle: string;
  At, Stop: Integer;
  Hit: TAtlasSearchHit;
  Whole: Boolean;
begin
  Line := CleanLine(ALine);
  if AOptions.CaseSensitive then
  begin
    Haystack := Line;
    Needle := ANeedle;
  end
  else
  begin
    Haystack := LowerCase(Line, loUserLocale);
    Needle := LowerCase(ANeedle, loUserLocale);
  end;
  // Kleinschreibung darf die Länge nicht ändern, sonst stimmten die Spalten nicht mehr.
  if (Length(Haystack) <> Length(Line)) or (Length(Needle) <> Length(ANeedle)) then
  begin
    Haystack := Line;
    Needle := ANeedle;
  end;
  At := Pos(Needle, Haystack);
  while At > 0 do
  begin
    Stop := At + Length(Needle);
    Whole := not AOptions.WholeWord or IsWholeWordAt(Line, At, Stop);
    Hit := TAtlasSearchHit.Create(ALineIndex, At - 1, Length(Needle));
    if Whole and AArea.Covers(Hit.StartPos, Hit.StopPos) then
    begin
      AHits.Add(Hit);
      At := Pos(Needle, Haystack, Stop);
    end
    else
    begin
      At := Pos(Needle, Haystack, At + 1);
    end;
  end;
end;

{$SCOPEDENUMS ON}
type
  /// <summary>Zustand des Lexers in CodeOnly; reicht über Zeilengrenzen.</summary>
  TCodeState = (Code, Brace, Paren, MultiString);
{$SCOPEDENUMS OFF}

type
  /// <summary>Lexer von CodeOnly: ersetzt in einer Zeile Kommentare, Direktiven und Strings durch CodeMask. Der
  /// Zustand bleibt für die nächste Zeile stehen (mehrzeilige Kommentare und Strings).</summary>
  TCodeMasker = record
  private
    FState: TCodeState;
    FLine: string;
    FCount: Integer;
    FAt: Integer;
    procedure Mask(AFrom, ATo: Integer);
    function NextIs(AChar: Char): Boolean;
    function RestIsBlank(AFrom: Integer): Boolean;
    procedure SkipQuoted;
    procedure StepComment;
    /// <summary>False: Rest der Zeile gehört zum String.</summary>
    function StepMultiString: Boolean;
    /// <summary>False: Rest der Zeile ist erledigt (Kommentar bis Zeilenende, mehrzeiliger String).</summary>
    function StepString: Boolean;
    function StepCode: Boolean;
  public
    function MaskLine(const ALine: string): string;
  end;

{ TCodeMasker }

procedure TCodeMasker.Mask(AFrom, ATo: Integer);
var
  mIndex: Integer;
begin
  for mIndex := AFrom to ATo do
  begin
    if (mIndex >= 1) and (mIndex <= FCount) then
    begin
      FLine[mIndex] := TAtlasTextSearch.CodeMask;
    end;
  end;
end;

function TCodeMasker.NextIs(AChar: Char): Boolean;
begin
  Result := (FAt < FCount) and (FLine[FAt + 1] = AChar);
end;

function TCodeMasker.RestIsBlank(AFrom: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := True;
  for mIndex := AFrom to FCount do
  begin
    if not FLine[mIndex].IsWhiteSpace then
    begin
      Exit(False);
    end;
  end;
end;

procedure TCodeMasker.SkipQuoted;
var
  mClosed: Boolean;
begin
  mClosed := False;
  while not mClosed and (FAt <= FCount) do
  begin
    if FLine[FAt] <> '''' then
    begin
      Inc(FAt);
    end
    else if NextIs('''') then
    begin
      Inc(FAt, 2);
    end
    else
    begin
      Inc(FAt);
      mClosed := True;
    end;
  end;
end;

procedure TCodeMasker.StepComment;
begin
  if FState = TCodeState.Brace then
  begin
    if FLine[FAt] = '}' then
    begin
      FState := TCodeState.Code;
    end;
    Mask(FAt, FAt);
    Inc(FAt);
  end
  else if (FLine[FAt] = '*') and NextIs(')') then
  begin
    FState := TCodeState.Code;
    Mask(FAt, FAt + 1);
    Inc(FAt, 2);
  end
  else
  begin
    Mask(FAt, FAt);
    Inc(FAt);
  end;
end;

function TCodeMasker.StepMultiString: Boolean;
var
  mStart: Integer;
begin
  // Ende: Zeile, die (nach Einzug) mit ''' beginnt.
  Result := Copy(TrimLeft(FLine), 1, 3) = '''''''';
  if Result then
  begin
    FState := TCodeState.Code;
    mStart := Pos('''''''', FLine) + 3;
    Mask(1, mStart - 1);
    FAt := mStart;
  end
  else
  begin
    Mask(1, FCount);
  end;
end;

function TCodeMasker.StepString: Boolean;
var
  mStart: Integer;
begin
  // Mehrzeiliger String: ''' und dahinter nichts mehr in der Zeile.
  Result := not ((Copy(FLine, FAt, 3) = '''''''') and RestIsBlank(FAt + 3));
  if Result then
  begin
    mStart := FAt;
    Inc(FAt);
    SkipQuoted;
    Mask(mStart, FAt - 1);
  end
  else
  begin
    FState := TCodeState.MultiString;
    Mask(FAt, FCount);
  end;
end;

function TCodeMasker.StepCode: Boolean;
begin
  Result := True;
  case FLine[FAt] of
    '{':
      begin
        FState := TCodeState.Brace;
        Mask(FAt, FAt);
        Inc(FAt);
      end;
    '(':
      if NextIs('*') then
      begin
        FState := TCodeState.Paren;
        Mask(FAt, FAt + 1);
        Inc(FAt, 2);
      end
      else
      begin
        Inc(FAt);
      end;
    '/':
      if NextIs('/') then
      begin
        Mask(FAt, FCount);
        Result := False;
      end
      else
      begin
        Inc(FAt);
      end;
    '''':
      Result := StepString;
  else
    Inc(FAt);
  end;
end;

function TCodeMasker.MaskLine(const ALine: string): string;
var
  mGoOn: Boolean;
begin
  FLine := CleanLine(ALine);
  FCount := Length(FLine);
  FAt := 1;
  mGoOn := True;
  while mGoOn and (FAt <= FCount) do
  begin
    case FState of
      TCodeState.Brace, TCodeState.Paren:
        StepComment;
      TCodeState.MultiString:
        mGoOn := StepMultiString;
    else
      mGoOn := StepCode;
    end;
  end;
  Result := FLine;
end;

class function TAtlasTextSearch.CodeOnly(const ALines: TArray<string>): TArray<string>;
var
  mMasker: TCodeMasker;
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ALines));
  mMasker := Default(TCodeMasker);
  for mIndex := 0 to High(ALines) do
  begin
    Result[mIndex] := mMasker.MaskLine(ALines[mIndex]);
  end;
end;

/// <summary>Suchtext des Bezeichner-Modus ohne führendes &amp;; '' wenn er kein Bezeichner ist.</summary>
function IdentifierNeedle(const ANeedle: string): string;
var
  mIndex: Integer;
begin
  Result := ANeedle;
  if (Result <> '') and (Result[1] = '&') then
  begin
    Delete(Result, 1, 1);
  end;
  if (Result = '') or Result[1].IsDigit then
  begin
    Exit('');
  end;
  for mIndex := 1 to Length(Result) do
  begin
    if not TTextChars.IsIdentChar(Result[mIndex]) then
    begin
      Exit('');
    end;
  end;
end;

/// <summary>Erste Stelle ab AFrom, die kein Bezeichnerzeichen ist (Length + 1 am Zeilenende).</summary>
function SkipWord(const ALine: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= Length(ALine)) and TTextChars.IsIdentChar(ALine[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Bezeichner-Modus: Treffer einer Zeile aus CodeOnly.</summary>
procedure FindIdentifiersInLine(const ALine: string; ALineIndex: Integer; const ANeedle: string;
  const AArea: TAtlasSearchArea; AHits: TList<TAtlasSearchHit>);
var
  mAt, mFirst: Integer;
  mEscaped: Boolean;
begin
  mAt := 1;
  while mAt <= Length(ALine) do
  begin
    if CharInSet(ALine[mAt], ['#', '$', '%', '0'..'9']) then
    begin
      // Zeichenkonstante, Hex-, Binärzahl oder Zahl: Ziffern und Buchstaben gehören dazu ($FF, 1E5).
      mAt := SkipWord(ALine, mAt + 1);
    end
    else if (ALine[mAt] = '&') or TTextChars.IsIdentChar(ALine[mAt]) then
    begin
      mEscaped := ALine[mAt] = '&';
      mFirst := mAt + Ord(mEscaped);
      mAt := SkipWord(ALine, mFirst);
      if (mAt > mFirst) and SameText(Copy(ALine, mFirst, mAt - mFirst), ANeedle) and
        (mEscaped or not TAtlasTextSearch.IsReserved(ANeedle)) then
      begin
        AddCovered(AHits, AArea, ALineIndex, mFirst - 1, mAt - mFirst);
      end;
    end
    else
    begin
      Inc(mAt);
    end;
  end;
end;

/// <summary>Bezeichner-Modus: Bezeichner im Code (CodeOnly); Kommentare und Strings dürfen Zeilen überspannen.
/// </summary>
procedure FindIdentifiers(const ALines: TArray<string>; const ANeedle: string; const AArea: TAtlasSearchArea;
  AHits: TList<TAtlasSearchHit>);
var
  mCode: TArray<string>;
  mNeedle: string;
  mLineIndex: Integer;
begin
  mNeedle := IdentifierNeedle(ANeedle);
  if mNeedle = '' then
  begin
    Exit;
  end;
  mCode := TAtlasTextSearch.CodeOnly(ALines);
  for mLineIndex := Max(AArea.Start.Line, 0) to Min(AArea.Stop.Line, High(mCode)) do
  begin
    FindIdentifiersInLine(mCode[mLineIndex], mLineIndex, mNeedle, AArea, AHits);
  end;
end;

/// <summary>Zählt ein Regex-Treffer? Leere Treffer (^, x*) lassen sich weder markieren noch sinnvoll ersetzen;
/// ACode ist die Zeile aus CodeOnly oder '' außerhalb des Bezeichner-Modus.</summary>
function KeepMatch(const AFound: TMatch; const ALine, ACode: string; AWholeWord: Boolean): Boolean;
begin
  Result := AFound.Length > 0;
  if Result and AWholeWord then
  begin
    Result := IsWholeWordAt(ALine, AFound.Index, AFound.Index + AFound.Length);
  end;
  if Result and (ACode <> '') then
  begin
    Result := Pos(TAtlasTextSearch.CodeMask, Copy(ACode, AFound.Index, AFound.Length)) = 0;
  end;
end;

/// <summary>Regex-Modus: Treffer je Zeile; ACode (CodeOnly) nur im Bezeichner-Modus, sonst nil.</summary>
procedure FindPattern(const ALines, ACode: TArray<string>; const APattern: string;
  const AOptions: TAtlasSearchOptions; const AArea: TAtlasSearchArea; AHits: TList<TAtlasSearchHit>);
var
  mExpression: TRegEx;
  mFound: TMatch;
  mLineIndex: Integer;
  mLine, mCodeLine: string;
begin
  mExpression := TRegEx.Create(APattern, TAtlasSearchRegex.Options(AOptions));
  for mLineIndex := Max(AArea.Start.Line, 0) to Min(AArea.Stop.Line, High(ALines)) do
  begin
    mLine := CleanLine(ALines[mLineIndex]);
    mCodeLine := '';
    if ACode <> nil then
    begin
      mCodeLine := ACode[mLineIndex];
    end;
    mFound := mExpression.Match(mLine);
    while mFound.Success do
    begin
      if KeepMatch(mFound, mLine, mCodeLine, AOptions.WholeWord) then
      begin
        AddCovered(AHits, AArea, mLineIndex, mFound.Index - 1, mFound.Length);
      end;
      mFound := mFound.NextMatch;
    end;
  end;
end;

class function TAtlasTextSearch.FindAll(const ALines: TArray<string>; const ANeedle: string;
  const AOptions: TAtlasSearchOptions; const AArea: TAtlasSearchArea): TArray<TAtlasSearchHit>;
var
  LineIndex: Integer;
  Error: string;
  Code: TArray<string>;
  Hits: TList<TAtlasSearchHit>;
begin
  Result := nil;
  if (ANeedle = '') or AArea.IsEmpty then
  begin
    Exit;
  end;
  // Liste statt Array + [Hit] (#1227): Das Anhängen kopierte jedes Mal alle Treffer; ein Buchstabe in einer großen
  // Unit (Zehntausende Treffer) kostete so Sekunden je Tastendruck.
  Hits := TList<TAtlasSearchHit>.Create;
  try
    if AOptions.Regex then
    begin
      if not TAtlasSearchRegex.Check(ANeedle, Error) then
      begin
        Exit;
      end;
      Code := nil;
      if AOptions.Identifier then
      begin
        Code := CodeOnly(ALines);
      end;
      FindPattern(ALines, Code, ANeedle, AOptions, AArea, Hits);
    end
    else if AOptions.Identifier then
    begin
      FindIdentifiers(ALines, Trim(ANeedle), AArea, Hits);
    end
    else
    begin
      for LineIndex := AArea.Start.Line to AArea.Stop.Line do
      begin
        if (LineIndex >= 0) and (LineIndex <= High(ALines)) then
        begin
          FindInLine(ALines[LineIndex], LineIndex, ANeedle, AOptions, AArea, Hits);
        end;
      end;
    end;
    Result := Hits.ToArray;
  finally
    Hits.Free;
  end;
end;

class function TAtlasTextSearch.Next(const AHits: TArray<TAtlasSearchHit>; const AFrom: TAtlasSearchPos;
  ABackward: Boolean; out AWrapped: Boolean): Integer;
var
  Index: Integer;
begin
  AWrapped := False;
  Result := -1;
  if Length(AHits) = 0 then
  begin
    Exit;
  end;
  if ABackward then
  begin
    for Index := High(AHits) downto 0 do
    begin
      if TAtlasSearchPos.Compare(AHits[Index].StartPos, AFrom) < 0 then
      begin
        Exit(Index);
      end;
    end;
    AWrapped := True;
    Result := High(AHits);
  end
  else
  begin
    for Index := 0 to High(AHits) do
    begin
      if TAtlasSearchPos.Compare(AHits[Index].StartPos, AFrom) >= 0 then
      begin
        Exit(Index);
      end;
    end;
    AWrapped := True;
    Result := 0;
  end;
end;

{ TAtlasSearchRegex }

class function TAtlasSearchRegex.Options(const AOptions: TAtlasSearchOptions): TRegExOptions;
begin
  Result := [];
  if not AOptions.CaseSensitive then
  begin
    Include(Result, roIgnoreCase);
  end;
end;

class function TAtlasSearchRegex.Check(const APattern: string; out AError: string): Boolean;
var
  Expression: TRegEx;
begin
  AError := '';
  if APattern = '' then
  begin
    Exit(True);
  end;
  try
    // Übersetzt wird beim ersten Vergleich; erst dann meldet die Engine einen Fehler.
    Expression := TRegEx.Create(APattern);
    Expression.IsMatch('');
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

end.
