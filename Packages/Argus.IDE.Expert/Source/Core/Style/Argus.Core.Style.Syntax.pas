unit Argus.Core.Style.Syntax;

// Einfache Syntaxfärbung für Deklarationen und Signaturen in Detailpanel und
// Parameter-Hint: Schlüsselwörter (samt Direktiven wie overload und dem Typ
// string), String-Literale, Kommentare, Zahlen. Kein Parser: Es geht nur um
// die Farbe kurzer Einzeiler, wie im Entwurf.

interface

uses
  System.SysUtils,
  System.Types;

type
  TArgusTokenKind = (Plain, Keyword, StringLiteral, Comment, Number);

  TArgusToken = record
    /// <summary>0-basiert.</summary>
    Start: Integer;
    /// <summary>Exklusiv.</summary>
    Stop: Integer;
    Kind: TArgusTokenKind;
  end;

  TArgusTokens = TArray<TArgusToken>;

  TArgusSyntax = class
  public
    class function IsKeyword(const AWord: string): Boolean; static;
    /// <summary>Lückenlose Zerlegung von AText; benachbarte Plain-Stücke sind zusammengefasst.</summary>
    class function Tokens(const AText: string): TArgusTokens; static;
    /// <summary>Standardwerte der Parameter (#441): je Parameter der Bereich " = Wert" (0-basiert, Stop
    /// exklusiv, X = Start, Y = Stop) innerhalb der äußersten Klammern einer Signatur.</summary>
    class function DefaultRanges(const ASignature: string): TArray<TPoint>; static;
  end;

implementation

const
  Keywords: array of string = [
    'absolute', 'abstract', 'and', 'array', 'as', 'begin', 'case', 'cdecl', 'class', 'const', 'constructor',
    'default', 'deprecated', 'destructor', 'dispinterface', 'div', 'do', 'downto', 'dynamic', 'else', 'end',
    'except', 'experimental', 'export', 'external', 'file', 'final', 'finalization', 'finally', 'for',
    'forward', 'function', 'goto', 'helper', 'if', 'implementation', 'implements', 'in', 'index', 'inherited',
    'initialization', 'inline', 'interface', 'is', 'label', 'library', 'message', 'mod', 'nil', 'nodefault',
    'not', 'object', 'of', 'on', 'or', 'out', 'overload', 'override', 'packed', 'platform', 'private',
    'procedure', 'program', 'property', 'protected', 'public', 'published', 'raise', 'read', 'record',
    'reference', 'reintroduce', 'repeat', 'resourcestring', 'safecall', 'sealed', 'set', 'shl', 'shr',
    'static', 'stdcall', 'stored', 'strict', 'string', 'then', 'threadvar', 'to',
    'try', 'type', 'unit', 'until', 'uses', 'var', 'virtual', 'while', 'with', 'write', 'xor'];

function IsIdentStart(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '_']) or (Ord(AChar) > 127);
end;

function IsIdentChar(AChar: Char): Boolean;
begin
  Result := IsIdentStart(AChar) or CharInSet(AChar, ['0'..'9']);
end;

{ TArgusSyntax }

class function TArgusSyntax.IsKeyword(const AWord: string): Boolean;
var
  Word: string;
begin
  for Word in Keywords do
    if SameText(Word, AWord) then
      Exit(True);
  Result := False;
end;

class function TArgusSyntax.Tokens(const AText: string): TArgusTokens;
var
  Index, Start, Count: Integer;
  Kind: TArgusTokenKind;

  procedure Emit(AStart, AStop: Integer; AKind: TArgusTokenKind);
  begin
    if AStop <= AStart then
      Exit;
    if (AKind = TArgusTokenKind.Plain) and (Count > 0) and (Result[Count - 1].Kind = TArgusTokenKind.Plain) and
      (Result[Count - 1].Stop = AStart) then
    begin
      Result[Count - 1].Stop := AStop;
      Exit;
    end;
    if Count = Length(Result) then
      SetLength(Result, Count * 2 + 4);
    Result[Count].Start := AStart;
    Result[Count].Stop := AStop;
    Result[Count].Kind := AKind;
    Inc(Count);
  end;

begin
  Result := nil;
  Count := 0;
  // Index 1-basiert über den String; Tokens 0-basiert.
  Index := 1;
  while Index <= Length(AText) do
  begin
    Start := Index;
    if AText[Index] = '''' then
    begin
      Inc(Index);
      while (Index <= Length(AText)) and (AText[Index] <> '''') do
        Inc(Index);
      Inc(Index);
      Kind := TArgusTokenKind.StringLiteral;
    end
    else if AText[Index] = '{' then
    begin
      while (Index <= Length(AText)) and (AText[Index] <> '}') do
        Inc(Index);
      Inc(Index);
      Kind := TArgusTokenKind.Comment;
    end
    else if (AText[Index] = '/') and (Index < Length(AText)) and (AText[Index + 1] = '/') then
    begin
      Index := Length(AText) + 1;
      Kind := TArgusTokenKind.Comment;
    end
    else if IsIdentStart(AText[Index]) then
    begin
      while (Index <= Length(AText)) and IsIdentChar(AText[Index]) do
        Inc(Index);
      // Nach einem Punkt ist es ein Name (TFoo.Create, Self.Read), kein Schlüsselwort.
      if ((Start = 1) or (AText[Start - 1] <> '.')) and IsKeyword(Copy(AText, Start, Index - Start)) then
        Kind := TArgusTokenKind.Keyword
      else
        Kind := TArgusTokenKind.Plain;
    end
    else if CharInSet(AText[Index], ['0'..'9', '$']) then
    begin
      Inc(Index);
      while (Index <= Length(AText)) and CharInSet(AText[Index], ['0'..'9', 'A'..'F', 'a'..'f', '.']) do
        Inc(Index);
      Kind := TArgusTokenKind.Number;
    end
    else
    begin
      Inc(Index);
      Kind := TArgusTokenKind.Plain;
    end;
    if Index > Length(AText) + 1 then
      Index := Length(AText) + 1;
    Emit(Start - 1, Index - 1, Kind);
  end;
  SetLength(Result, Count);
end;

class function TArgusSyntax.DefaultRanges(const ASignature: string): TArray<TPoint>;
var
  Index, Depth, Start: Integer;
  InString: Boolean;
begin
  // 1-basiert über den Text; Ergebnis 0-basiert. "=" auf Ebene 1 beginnt einen Standardwert, der bis
  // vor das nächste ";" bzw. die schließende Klammer derselben Ebene reicht.
  Result := nil;
  Depth := 0;
  Start := -1;
  InString := False;
  for Index := 1 to Length(ASignature) do
  begin
    if ASignature[Index] = '''' then
      InString := not InString;
    if InString then
      Continue;
    case ASignature[Index] of
      '(', '[':
        Inc(Depth);
      ')', ']':
        begin
          if (Depth = 1) and (Start >= 0) then
          begin
            Result := Result + [Point(Start, Index - 1)];
            Start := -1;
          end;
          Dec(Depth);
        end;
      ';':
        if (Depth = 1) and (Start >= 0) then
        begin
          Result := Result + [Point(Start, Index - 1)];
          Start := -1;
        end;
      '=':
        if (Depth = 1) and (Start < 0) then
        begin
          // Leerzeichen vor "=" gehören dazu: "Offset: Integer = 1" → " = 1".
          Start := Index - 1;
          while (Start > 0) and (ASignature[Start] = ' ') do
            Dec(Start);
        end;
    end;
  end;
end;

end.