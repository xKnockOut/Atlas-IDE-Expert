unit Atlas.Core.Hover.DebugValue;

// Variablenwert im Hover beim Debuggen (#891), ohne VCL und Open Tools API:
//   - Ausdruck unter der Maus wie in der IDE: der Bezeichner samt
//     Qualifizierern links davon (Self.FList.Count, Kunden[I].Name, P^.Wert).
//     Kein Ausdruck in Strings und Kommentaren, auf reservierten Wörtern und
//     Zahlen; keiner mit Klammer vor dem Punkt (Get(X).Name) und keiner mit
//     Klammer im Index, damit die Auswertung nie etwas im Programm ausführt.
//   - Zustand des Werts im Tooltip: ausstehend (der Debugger antwortet
//     verzögert, Win64/LLDB), Wert, Fehler. Fehler zeigt der Tooltip nicht;
//     die Erklärung folgt mit #840.
//   - Lange Werte werden für den Tooltip gekürzt.

interface

type
  {$SCOPEDENUMS ON}
  TAtlasDebugValueState = (None, Pending, Value, Failed);
  {$SCOPEDENUMS OFF}

  /// <summary>Wert eines Ausdrucks im angehaltenen Debugger.</summary>
  TAtlasDebugValue = record
    State: TAtlasDebugValueState;
    Expression: string;
    Text: string;
    class function Pending(const AExpression: string): TAtlasDebugValue; static;
    /// <summary>Ausgewerteter Wert, auf TAtlasDebugExpression.MaxValueLength gekürzt.</summary>
    class function Evaluated(const AExpression, AText: string): TAtlasDebugValue; static;
    class function Failed(const AExpression, AText: string): TAtlasDebugValue; static;
    /// <summary>Zeigt der Tooltip den Abschnitt (ausstehend oder Wert)?</summary>
    function Visible: Boolean;
    /// <summary>„Ausdruck = Wert“ als Klartext für den Tooltip der IDE; '' ohne Wert.</summary>
    function PlainText: string;
  end;

  TAtlasDebugExpression = record
  public const
    MaxValueLength = 2000;
  public
    /// <summary>Ausdruck zum Bezeichner [AStart, AStop) der Zeile (0-basiert, AStop exklusiv); '' wenn dort
    /// nichts ausgewertet werden soll.</summary>
    class function At(const ALine: string; AStart, AStop: Integer): string; static;
    /// <summary>Ausdruck zum Bezeichner, in dem das Zeichen AIndex (0-basiert) steht; '' außerhalb.</summary>
    class function AtCharacter(const ALine: string; AIndex: Integer): string; static;
    class function IsReserved(const AWord: string): Boolean; static;
    /// <summary>Steht die Stelle AIndex (0-basiert) in einem String oder Kommentar der Zeile?</summary>
    class function InStringOrComment(const ALine: string; AIndex: Integer): Boolean; static;
    /// <summary>Höchstens AMaxLength Zeichen, gekürzt mit „…“.</summary>
    class function Shorten(const AText: string; AMaxLength: Integer): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  // Reservierte Wörter von Delphi; Direktiven (override, virtual …) wertet der Debugger ohnehin nicht aus.
  ReservedWords: array[0..65] of string = ('and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const',
    'constructor', 'destructor', 'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except', 'exports',
    'file', 'finalization', 'finally', 'for', 'function', 'goto', 'if', 'implementation', 'in', 'inherited',
    'initialization', 'inline', 'interface', 'is', 'label', 'library', 'mod', 'nil', 'not', 'object', 'of',
    'or', 'packed', 'procedure', 'program', 'property', 'raise', 'record', 'repeat', 'resourcestring', 'set',
    'shl', 'shr', 'string', 'then', 'threadvar', 'to', 'try', 'type', 'unit', 'until', 'uses', 'var',
    'while', 'with', 'xor', 'out', 'operator');

function IsIdentifierChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

{ TAtlasDebugValue }

class function TAtlasDebugValue.Pending(const AExpression: string): TAtlasDebugValue;
begin
  Result := Default(TAtlasDebugValue);
  Result.State := TAtlasDebugValueState.Pending;
  Result.Expression := AExpression;
end;

class function TAtlasDebugValue.Evaluated(const AExpression, AText: string): TAtlasDebugValue;
begin
  Result := Default(TAtlasDebugValue);
  Result.State := TAtlasDebugValueState.Value;
  Result.Expression := AExpression;
  Result.Text := TAtlasDebugExpression.Shorten(AText, TAtlasDebugExpression.MaxValueLength);
end;

class function TAtlasDebugValue.Failed(const AExpression, AText: string): TAtlasDebugValue;
begin
  Result := Default(TAtlasDebugValue);
  Result.State := TAtlasDebugValueState.Failed;
  Result.Expression := AExpression;
  Result.Text := AText;
end;

function TAtlasDebugValue.Visible: Boolean;
begin
  Result := (Expression <> '') and (State in [TAtlasDebugValueState.Pending, TAtlasDebugValueState.Value]);
end;

function TAtlasDebugValue.PlainText: string;
begin
  Result := '';
  if (State = TAtlasDebugValueState.Value) and (Expression <> '') then
    Result := Expression + ' = ' + Text;
end;

{ TAtlasDebugExpression }

class function TAtlasDebugExpression.IsReserved(const AWord: string): Boolean;
begin
  Result := MatchText(AWord, ReservedWords);
end;

class function TAtlasDebugExpression.InStringOrComment(const ALine: string; AIndex: Integer): Boolean;
var
  Index: Integer;
  InString, InBrace, InParen: Boolean;
begin
  // Zustand am Anfang der Zeile: außerhalb; mehrzeilige Kommentare davor kennt die Zeile nicht.
  InString := False;
  InBrace := False;
  InParen := False;
  Index := 1;
  while (Index <= AIndex) and (Index <= Length(ALine)) do
  begin
    if InString then
      InString := ALine[Index] <> ''''
    else if InBrace then
      InBrace := ALine[Index] <> '}'
    else if InParen then
    begin
      if (ALine[Index] = '*') and (Index < Length(ALine)) and (ALine[Index + 1] = ')') then
      begin
        InParen := False;
        Inc(Index);
      end;
    end
    else
      case ALine[Index] of
        '''':
          InString := True;
        '{':
          InBrace := True;
        '(':
          if (Index < Length(ALine)) and (ALine[Index + 1] = '*') then
          begin
            InParen := True;
            Inc(Index);
          end;
        '/':
          if (Index < Length(ALine)) and (ALine[Index + 1] = '/') then
            Exit(True);
      end;
    Inc(Index);
  end;
  Result := InString or InBrace or InParen;
end;

class function TAtlasDebugExpression.At(const ALine: string; AStart, AStop: Integer): string;
var
  Word, Name: string;
  Start, Pos, Depth, NameStart: Integer;
begin
  Result := '';
  if (AStart < 0) or (AStop <= AStart) or (AStop > Length(ALine)) then
    Exit;
  Word := Copy(ALine, AStart + 1, AStop - AStart);
  // Escapter Bezeichner (&Type) zählt mit dem & und ist kein reserviertes Wort.
  Start := AStart;
  if (Start > 0) and (ALine[Start] = '&') then
    Dec(Start);
  if CharInSet(Word[1], ['0'..'9']) or ((Start = AStart) and IsReserved(Word)) or
    InStringOrComment(ALine, AStart) then
    Exit;
  // Qualifizierer links davon: „Name.“, „Name[…].“, „Name^.“; Pos ist der 1-basierte Index vor Start.
  while (Start > 0) and (ALine[Start] = '.') do
  begin
    Pos := Start - 1;
    // Bereich „0..Count“: kein Qualifizierer.
    if (Pos > 0) and (ALine[Pos] = '.') then
      Break;
    while (Pos > 0) and CharInSet(ALine[Pos], ['^', ']']) do
      if ALine[Pos] = '^' then
        Dec(Pos)
      else
      begin
        // Passende öffnende Klammer; Klammern darin hießen Aufruf.
        Depth := 0;
        repeat
          case ALine[Pos] of
            ']':
              Inc(Depth);
            '[':
              Dec(Depth);
            '(', ')', '''':
              Exit('');
          end;
          Dec(Pos);
        until (Depth = 0) or (Pos = 0);
        if Depth <> 0 then
          Exit('');
      end;
    // Klammer vor dem Punkt: Aufruf oder Typumwandlung, nicht auswerten (auch nicht nur den Rest).
    if (Pos = 0) or not IsIdentifierChar(ALine[Pos]) then
      Exit('');
    NameStart := Pos;
    while (NameStart > 1) and IsIdentifierChar(ALine[NameStart - 1]) do
      Dec(NameStart);
    Name := Copy(ALine, NameStart, Pos - NameStart + 1);
    Start := NameStart - 1;
    if (Start > 0) and (ALine[Start] = '&') then
      Dec(Start)
    else if IsReserved(Name) then
      Exit('');
    if CharInSet(Name[1], ['0'..'9']) then
      Exit('');
  end;
  Result := Copy(ALine, Start + 1, AStop - Start);
end;

class function TAtlasDebugExpression.AtCharacter(const ALine: string; AIndex: Integer): string;
var
  Start, Stop: Integer;
begin
  Result := '';
  if (AIndex < 0) or (AIndex >= Length(ALine)) or not IsIdentifierChar(ALine[AIndex + 1]) then
    Exit;
  Start := AIndex;
  while (Start > 0) and IsIdentifierChar(ALine[Start]) do
    Dec(Start);
  Stop := AIndex + 1;
  while (Stop < Length(ALine)) and IsIdentifierChar(ALine[Stop + 1]) do
    Inc(Stop);
  Result := At(ALine, Start, Stop);
end;

class function TAtlasDebugExpression.Shorten(const AText: string; AMaxLength: Integer): string;
begin
  Result := AText;
  if (AMaxLength > 0) and (Length(Result) > AMaxLength) then
    Result := Copy(Result, 1, AMaxLength) + ' …';
end;

end.
