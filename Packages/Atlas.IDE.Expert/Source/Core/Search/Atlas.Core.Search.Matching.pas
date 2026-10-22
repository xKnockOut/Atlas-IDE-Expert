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
// - Bereich: Nur Treffer, die ganz im Bereich liegen (Routine, Unit, Auswahl;
//   siehe Atlas.Core.Search.Scopes).
// - Weitersuchen (F3/Umschalt+F3): vorwärts der erste Treffer ab der
//   Position, rückwärts der letzte davor; am Ende bzw. Anfang geht es von der
//   anderen Seite weiter (Umlauf).
// Zeilen und Zeichen sind 0-basiert; ein #13 am Zeilenende zählt nicht.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  /// <summary>Suchbereich: ganze Unit (Vorgabe, auch für Default()), Routine am Cursor (mit lokalen
  /// Deklarationen), Auswahl. Die Reihenfolge ist die der Bereichsliste in der Suchleiste.</summary>
  TAtlasSearchScope = (UnitFile, Method, Selection);
  {$SCOPEDENUMS OFF}

  TAtlasSearchOptions = record
    CaseSensitive: Boolean;
    WholeWord: Boolean;
    /// <summary>Nur Bezeichner, keine Kommentare und Strings (Groß-/Kleinschreibung egal wie in Pascal).</summary>
    Identifier: Boolean;
    class function Create(ACaseSensitive, AWholeWord, AIdentifier: Boolean): TAtlasSearchOptions; static;
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
  end;

implementation

uses
  System.Character,
  Atlas.Text.Chars;

{ TAtlasSearchOptions }

class function TAtlasSearchOptions.Create(ACaseSensitive, AWholeWord, AIdentifier: Boolean): TAtlasSearchOptions;
begin
  Result.CaseSensitive := ACaseSensitive;
  Result.WholeWord := AWholeWord;
  Result.Identifier := AIdentifier;
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
    Result := -1
  else if A.Line > B.Line then
    Result := 1
  else if A.Character < B.Character then
    Result := -1
  else if A.Character > B.Character then
    Result := 1
  else
    Result := 0;
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
    Result := Create(0, 0, 0, 0)
  else
    Result := Create(0, 0, High(ALines), Length(ALines[High(ALines)]));
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
    SetLength(Result, Length(Result) - 1);
end;

class function TAtlasTextSearch.HitText(const ALines: TArray<string>; const AHit: TAtlasSearchHit): string;
const
  MaxText = 200;
begin
  Result := '';
  if (AHit.Line >= 0) and (AHit.Line <= High(ALines)) then
    Result := Trim(CleanLine(ALines[AHit.Line]).Replace(#9, ' '));
  if Length(Result) > MaxText then
    Result := Copy(Result, 1, MaxText) + '…';
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
    if Word = Lower then
      Exit(True);
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
    Dec(First);
  if (First < 1) or (First > Length(Line)) or not TTextChars.IsIdentChar(Line[First]) then
    Exit;
  Last := First;
  while (First > 1) and TTextChars.IsIdentChar(Line[First - 1]) do
    Dec(First);
  while (Last < Length(Line)) and TTextChars.IsIdentChar(Line[Last + 1]) do
    Inc(Last);
  Result := Copy(Line, First, Last - First + 1);
end;

/// <summary>Textmodus: Treffer einer Zeile.</summary>
procedure FindInLine(const ALine: string; ALineIndex: Integer; const ANeedle: string;
  const AOptions: TAtlasSearchOptions; const AArea: TAtlasSearchArea; var AHits: TArray<TAtlasSearchHit>);
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
    Whole := True;
    if AOptions.WholeWord then
      Whole := ((At = 1) or not TTextChars.IsIdentChar(Line[At - 1])) and
        ((Stop > Length(Line)) or not TTextChars.IsIdentChar(Line[Stop]));
    Hit := TAtlasSearchHit.Create(ALineIndex, At - 1, Length(Needle));
    if Whole and AArea.Covers(Hit.StartPos, Hit.StopPos) then
    begin
      AHits := AHits + [Hit];
      At := Pos(Needle, Haystack, Stop);
    end
    else
      At := Pos(Needle, Haystack, At + 1);
  end;
end;

/// <summary>Bezeichner-Modus: Lexer über alle Zeilen; Kommentare und Strings dürfen Zeilen überspannen.</summary>
procedure FindIdentifiers(const ALines: TArray<string>; const ANeedle: string; const AArea: TAtlasSearchArea;
  var AHits: TArray<TAtlasSearchHit>);
type
  TState = (Code, Brace, Paren, MultiString);
var
  State: TState;
  LineIndex, I, First, Count: Integer;
  Line, Name, Needle: string;
  Escaped: Boolean;
  Hit: TAtlasSearchHit;

  function RestIsBlank(AFrom: Integer): Boolean;
  var
    K: Integer;
  begin
    Result := True;
    for K := AFrom to Length(Line) do
      if not Line[K].IsWhiteSpace then
        Exit(False);
  end;

begin
  Needle := ANeedle;
  if (Needle <> '') and (Needle[1] = '&') then
    Delete(Needle, 1, 1);
  if Needle = '' then
    Exit;
  for I := 1 to Length(Needle) do
    if not TTextChars.IsIdentChar(Needle[I]) then
      Exit;
  if Needle[1].IsDigit then
    Exit;
  State := TState.Code;
  for LineIndex := 0 to High(ALines) do
  begin
    Line := CleanLine(ALines[LineIndex]);
    Count := Length(Line);
    I := 1;
    while I <= Count do
    begin
      case State of
        TState.Brace:
          begin
            if Line[I] = '}' then
              State := TState.Code;
            Inc(I);
            Continue;
          end;
        TState.Paren:
          begin
            if (Line[I] = '*') and (I < Count) and (Line[I + 1] = ')') then
            begin
              State := TState.Code;
              Inc(I);
            end;
            Inc(I);
            Continue;
          end;
        TState.MultiString:
          begin
            // Ende: Zeile, die (nach Einzug) mit ''' beginnt.
            if Copy(TrimLeft(Line), 1, 3) = '''''''' then
            begin
              State := TState.Code;
              I := Pos('''''''', Line) + 3;
              Continue;
            end;
            Break;
          end;
      end;
      case Line[I] of
        '{':
          begin
            State := TState.Brace;
            Inc(I);
          end;
        '(':
          if (I < Count) and (Line[I + 1] = '*') then
          begin
            State := TState.Paren;
            Inc(I, 2);
          end
          else
            Inc(I);
        '/':
          if (I < Count) and (Line[I + 1] = '/') then
            Break
          else
            Inc(I);
        '''':
          begin
            // Mehrzeiliger String: ''' und dahinter nichts mehr in der Zeile.
            if (Copy(Line, I, 3) = '''''''') and RestIsBlank(I + 3) then
            begin
              State := TState.MultiString;
              Break;
            end;
            Inc(I);
            while I <= Count do
            begin
              if Line[I] = '''' then
              begin
                if (I < Count) and (Line[I + 1] = '''') then
                  Inc(I, 2)
                else
                begin
                  Inc(I);
                  Break;
                end;
              end
              else
                Inc(I);
            end;
          end;
        '#', '$', '%', '0'..'9':
          begin
            // Zeichenkonstante, Hex-, Binärzahl oder Zahl: Ziffern und Buchstaben gehören dazu ($FF, 1E5).
            Inc(I);
            while (I <= Count) and TTextChars.IsIdentChar(Line[I]) do
              Inc(I);
          end;
      else
        if (Line[I] = '&') or TTextChars.IsIdentChar(Line[I]) then
        begin
          Escaped := Line[I] = '&';
          if Escaped then
            Inc(I);
          First := I;
          while (I <= Count) and TTextChars.IsIdentChar(Line[I]) do
            Inc(I);
          if I = First then
            Continue;
          Name := Copy(Line, First, I - First);
          if SameText(Name, Needle) and (Escaped or not TAtlasTextSearch.IsReserved(Name)) then
          begin
            Hit := TAtlasSearchHit.Create(LineIndex, First - 1, I - First);
            if AArea.Covers(Hit.StartPos, Hit.StopPos) then
              AHits := AHits + [Hit];
          end;
        end
        else
          Inc(I);
      end;
    end;
  end;
end;

class function TAtlasTextSearch.FindAll(const ALines: TArray<string>; const ANeedle: string;
  const AOptions: TAtlasSearchOptions; const AArea: TAtlasSearchArea): TArray<TAtlasSearchHit>;
var
  LineIndex: Integer;
begin
  Result := nil;
  if (ANeedle = '') or AArea.IsEmpty then
    Exit;
  if AOptions.Identifier then
  begin
    FindIdentifiers(ALines, Trim(ANeedle), AArea, Result);
    Exit;
  end;
  for LineIndex := AArea.Start.Line to AArea.Stop.Line do
    if (LineIndex >= 0) and (LineIndex <= High(ALines)) then
      FindInLine(ALines[LineIndex], LineIndex, ANeedle, AOptions, AArea, Result);
end;

class function TAtlasTextSearch.Next(const AHits: TArray<TAtlasSearchHit>; const AFrom: TAtlasSearchPos;
  ABackward: Boolean; out AWrapped: Boolean): Integer;
var
  Index: Integer;
begin
  AWrapped := False;
  Result := -1;
  if Length(AHits) = 0 then
    Exit;
  if ABackward then
  begin
    for Index := High(AHits) downto 0 do
      if TAtlasSearchPos.Compare(AHits[Index].StartPos, AFrom) < 0 then
        Exit(Index);
    AWrapped := True;
    Result := High(AHits);
  end
  else
  begin
    for Index := 0 to High(AHits) do
      if TAtlasSearchPos.Compare(AHits[Index].StartPos, AFrom) >= 0 then
        Exit(Index);
    AWrapped := True;
    Result := 0;
  end;
end;

end.
