unit Atlas.Core.Hover.DebugValue;

// Variablenwert im Hover beim Debuggen (#891), ohne VCL und Open Tools API:
//   - Ausdruck unter der Maus wie in der IDE: der Bezeichner samt
//     Qualifizierern links davon (Self.FList.Count, Kunden[I].Name, P^.Wert).
//     Kein Ausdruck in Strings und Kommentaren, auf reservierten Wörtern und
//     Zahlen; keiner mit Klammer vor dem Punkt (Get(X).Name) und keiner mit
//     Klammer im Index, damit die Auswertung nie etwas im Programm ausführt.
//   - Zustand des Werts im Tooltip (TAtlasDebugValue, Atlas.Core.Hover.Contract.
//     DebugValue): ausstehend (der Debugger antwortet
//     verzögert, Win64/LLDB), Wert, Fehler. Fehler zeigt der Tooltip nur mit
//     Erklärung (#840, Note): „‹kein Zugriff›“, Ursache, Herkunft des
//     Schalters, geprüfte Punkte und Korrekturen als Verweise. Die Erklärung
//     setzt die Debug-Schicht; hier stehen nur die fertigen Texte.
//   - Lange Werte werden für den Tooltip gekürzt.
//   - Aufklappen und Änderungen (#895): Rows sind die sichtbaren Zeilen des
//     aufgeklappten Werts in Anzeigereihenfolge (Tiefe, Name, Wert, alter Wert),
//     OldText der Wert beim vorigen Halt, wenn er sich geändert hat. Beides
//     setzt die Debug-Schicht; der Tooltip zeichnet nur.

interface

uses
  Atlas.Plugin.Hover.Contract.DebugValue;

type
  TAtlasDebugExpression = record
  public const
    cMaxValueLength = TAtlasDebugValue.cMaxTextLength;
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
  System.StrUtils,
  Atlas.Text.Chars;

const
  // Reservierte Wörter von Delphi; Direktiven (override, virtual …) wertet der Debugger ohnehin nicht aus.
  cReservedWords: array[0..65] of string = ('and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const',
    'constructor', 'destructor', 'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except', 'exports',
    'file', 'finalization', 'finally', 'for', 'function', 'goto', 'if', 'implementation', 'in', 'inherited',
    'initialization', 'inline', 'interface', 'is', 'label', 'library', 'mod', 'nil', 'not', 'object', 'of',
    'or', 'packed', 'procedure', 'program', 'property', 'raise', 'record', 'repeat', 'resourcestring', 'set',
    'shl', 'shr', 'string', 'then', 'threadvar', 'to', 'try', 'type', 'unit', 'until', 'uses', 'var',
    'while', 'with', 'xor', 'out', 'operator');

{ TAtlasDebugExpression }

class function TAtlasDebugExpression.AtCharacter(const ALine: string; AIndex: Integer): string;
var
  mStart, mStop: Integer;
begin
  Result := '';
  if (AIndex < 0) or (AIndex >= Length(ALine)) or not TTextChars.IsIdentChar(ALine[AIndex + 1]) then
  begin
    Exit;
  end;
  mStart := AIndex;
  while (mStart > 0) and TTextChars.IsIdentChar(ALine[mStart]) do
  begin
    Dec(mStart);
  end;
  mStop := AIndex + 1;
  while (mStop < Length(ALine)) and TTextChars.IsIdentChar(ALine[mStop + 1]) do
  begin
    Inc(mStop);
  end;
  Result := At(ALine, mStart, mStop);
end;

type
  /// <summary>Lesezustand beim Gang durch eine Zeile.</summary>
  TLineState = (lsCode, lsString, lsBrace, lsParen, lsLineComment);

function NextIs(const ALine: string; AIndex: Integer; AChar: Char): Boolean;
begin
  Result := (AIndex < Length(ALine)) and (ALine[AIndex + 1] = AChar);
end;

/// <summary>Zustand nach dem Zeichen AIndex im Code; überspringt das zweite Zeichen von „(*“.</summary>
function CodeState(const ALine: string; var AIndex: Integer): TLineState;
begin
  Result := lsCode;
  case ALine[AIndex] of
    '''':
      Result := lsString;
    '{':
      Result := lsBrace;
    '(':
      if NextIs(ALine, AIndex, '*') then
      begin
        Result := lsParen;
        Inc(AIndex);
      end;
    '/':
      if NextIs(ALine, AIndex, '/') then
      begin
        Result := lsLineComment;
      end;
  end;
end;

function StepState(const ALine: string; var AIndex: Integer; AState: TLineState): TLineState;
begin
  Result := AState;
  case AState of
    lsCode:
      Result := CodeState(ALine, AIndex);
    lsString:
      if ALine[AIndex] = '''' then
      begin
        Result := lsCode;
      end;
    lsBrace:
      if ALine[AIndex] = '}' then
      begin
        Result := lsCode;
      end;
    lsParen:
      if (ALine[AIndex] = '*') and NextIs(ALine, AIndex, ')') then
      begin
        Result := lsCode;
        Inc(AIndex);
      end;
    lsLineComment:
      Result := lsLineComment;
  end;
end;

class function TAtlasDebugExpression.IsReserved(const AWord: string): Boolean;
begin
  Result := MatchText(AWord, cReservedWords);
end;

/// <summary>Von „]“ an APos (1-basiert) zur passenden öffnenden Klammer und davor; False bei Klammern oder
/// Strings darin (Aufruf) oder ohne passende Klammer.</summary>
function SkipIndexBrackets(const ALine: string; var APos: Integer): Boolean;
var
  mDepth: Integer;
begin
  mDepth := 0;
  repeat
    case ALine[APos] of
      ']':
        Inc(mDepth);
      '[':
        Dec(mDepth);
      '(', ')', '''':
        Exit(False);
    end;
    Dec(APos);
  until (mDepth = 0) or (APos = 0);
  Result := mDepth = 0;
end;

/// <summary>„^“ und „[…]“ links von APos überspringen; False, wenn nicht auszuwerten.</summary>
function SkipDerefAndIndex(const ALine: string; var APos: Integer): Boolean;
begin
  Result := True;
  while Result and (APos > 0) and CharInSet(ALine[APos], ['^', ']']) do
  begin
    if ALine[APos] = '^' then
    begin
      Dec(APos);
    end
    else
    begin
      Result := SkipIndexBrackets(ALine, APos);
    end;
  end;
end;

/// <summary>Name des Qualifizierers, der an APos (1-basiert) endet; AStart ist der Index vor ihm (vor einem &amp;).
/// False: nicht auswerten (Klammer vor dem Punkt, reserviertes Wort, Zahl).</summary>
function QualifierStart(const ALine: string; APos: Integer; out AStart: Integer): Boolean;
var
  mNameStart: Integer;
  mName: string;
begin
  AStart := 0;
  // Klammer vor dem Punkt: Aufruf oder Typumwandlung, nicht auswerten (auch nicht nur den Rest).
  if (APos = 0) or not TTextChars.IsIdentChar(ALine[APos]) then
  begin
    Exit(False);
  end;
  mNameStart := APos;
  while (mNameStart > 1) and TTextChars.IsIdentChar(ALine[mNameStart - 1]) do
  begin
    Dec(mNameStart);
  end;
  mName := Copy(ALine, mNameStart, APos - mNameStart + 1);
  AStart := mNameStart - 1;
  if (AStart > 0) and (ALine[AStart] = '&') then
  begin
    Dec(AStart);
  end
  else if TAtlasDebugExpression.IsReserved(mName) then
  begin
    Exit(False);
  end;
  Result := not CharInSet(mName[1], ['0'..'9']);
end;

/// <summary>Qualifizierer links von AStart: „Name.“, „Name[…].“, „Name^.“; AExpressionStart ist der 1-basierte
/// Index vor dem ganzen Ausdruck. False: nicht auswerten.</summary>
function ExpressionStart(const ALine: string; AStart: Integer; out AExpressionStart: Integer): Boolean;
var
  mPos: Integer;
begin
  AExpressionStart := AStart;
  Result := True;
  while Result and (AExpressionStart > 0) and (ALine[AExpressionStart] = '.') do
  begin
    mPos := AExpressionStart - 1;
    // Bereich „0..Count“: kein Qualifizierer.
    if (mPos > 0) and (ALine[mPos] = '.') then
    begin
      Break;
    end;
    Result := SkipDerefAndIndex(ALine, mPos) and QualifierStart(ALine, mPos, AExpressionStart);
  end;
end;

class function TAtlasDebugExpression.At(const ALine: string; AStart, AStop: Integer): string;
var
  mWord: string;
  mStart, mExpressionStart: Integer;
begin
  Result := '';
  if (AStart < 0) or (AStop <= AStart) or (AStop > Length(ALine)) then
  begin
    Exit;
  end;
  mWord := Copy(ALine, AStart + 1, AStop - AStart);
  // Escapter Bezeichner (&Type) zählt mit dem & und ist kein reserviertes Wort.
  mStart := AStart;
  if (mStart > 0) and (ALine[mStart] = '&') then
  begin
    Dec(mStart);
  end;
  if CharInSet(mWord[1], ['0'..'9']) or ((mStart = AStart) and IsReserved(mWord)) or
    InStringOrComment(ALine, AStart) then
  begin
    Exit;
  end;
  if ExpressionStart(ALine, mStart, mExpressionStart) then
  begin
    Result := Copy(ALine, mExpressionStart + 1, AStop - mExpressionStart);
  end;
end;

class function TAtlasDebugExpression.InStringOrComment(const ALine: string; AIndex: Integer): Boolean;
var
  mIndex: Integer;
  mState: TLineState;
begin
  // Zustand am Anfang der Zeile: außerhalb; mehrzeilige Kommentare davor kennt die Zeile nicht.
  mState := lsCode;
  mIndex := 1;
  while (mIndex <= AIndex) and (mIndex <= Length(ALine)) and (mState <> lsLineComment) do
  begin
    mState := StepState(ALine, mIndex, mState);
    Inc(mIndex);
  end;
  Result := mState <> lsCode;
end;

class function TAtlasDebugExpression.Shorten(const AText: string; AMaxLength: Integer): string;
begin
  Result := TAtlasDebugValue.Shorten(AText, AMaxLength);
end;

end.
