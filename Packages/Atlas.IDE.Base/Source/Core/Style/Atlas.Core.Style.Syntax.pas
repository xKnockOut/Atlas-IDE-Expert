unit Atlas.Core.Style.Syntax;

// Einfache Syntaxfärbung für Deklarationen und Signaturen in Detailpanel und
// Parameter-Hint: Schlüsselwörter (samt Direktiven wie overload und dem Typ
// string), String-Literale, Kommentare, Zahlen. Kein Parser: Es geht nur um
// die Farbe kurzer Einzeiler, wie im Entwurf. LineTokens färbt mehrere Zeilen
// (Peek, #505) und trägt offene {…}- und (*…*)-Kommentare in die Folgezeilen.

interface

uses
  System.SysUtils,
  System.Types;

type
  TAtlasTokenKind = (Plain, Keyword, StringLiteral, Comment, Number);

  TAtlasToken = record
    /// <summary>0-basiert.</summary>
    Start: Integer;
    /// <summary>Exklusiv.</summary>
    Stop: Integer;
    Kind: TAtlasTokenKind;
  end;

  TAtlasTokens = TArray<TAtlasToken>;

  TAtlasSyntax = class
  public
    class function IsKeyword(const AWord: string): Boolean; static;
    /// <summary>Lückenlose Zerlegung von AText; benachbarte Plain-Stücke sind zusammengefasst.</summary>
    class function Tokens(const AText: string): TAtlasTokens; static;
    /// <summary>Tokens je Zeile; Kommentare über mehrere Zeilen bleiben Kommentar.</summary>
    class function LineTokens(const ALines: TArray<string>): TArray<TAtlasTokens>; static;
    /// <summary>Standardwerte der Parameter (#441): je Parameter der Bereich " = Wert" (0-basiert, Stop
    /// exklusiv, X = Start, Y = Stop) innerhalb der äußersten Klammern einer Signatur.</summary>
    class function DefaultRanges(const ASignature: string): TArray<TPoint>; static;
  end;

implementation

uses
  Atlas.Text.Chars;

const
  cKeywords: array of string = [
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

{ Lesen ab einer 1-basierten Position }

/// <summary>Steht hinter AIndex das Zeichen ANext?</summary>
function IsPairAt(const AText: string; AIndex: Integer; ANext: Char): Boolean;
begin
  Result := (AIndex < Length(AText)) and (AText[AIndex + 1] = ANext);
end;

/// <summary>Position hinter dem schließenden Anführungszeichen des Strings an AIndex.</summary>
function AfterQuote(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= Length(AText)) and (AText[Result] <> '''') do
  begin
    Inc(Result);
  end;
  Inc(Result);
end;

/// <summary>Position hinter „}“ des Kommentars an AIndex; Length + 2, wenn er offen bleibt.</summary>
function AfterBrace(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and (AText[Result] <> '}') do
  begin
    Inc(Result);
  end;
  Inc(Result);
end;

/// <summary>Position hinter „*)“ des Kommentars „(*“ an AIndex; über Length + 1, wenn er offen bleibt.</summary>
function AfterParenStar(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 2;
  while (Result < Length(AText)) and not ((AText[Result] = '*') and (AText[Result + 1] = ')')) do
  begin
    Inc(Result);
  end;
  Inc(Result, 2);
end;

/// <summary>Bezeichner ab AIndex; nach einem Punkt ist es ein Name (TFoo.Create, Self.Read), kein
/// Schlüsselwort.</summary>
function WordAt(const AText: string; var AIndex: Integer): TAtlasTokenKind;
var
  mStart: Integer;
begin
  mStart := AIndex;
  while (AIndex <= Length(AText)) and TTextChars.IsIdentChar(AText[AIndex]) do
  begin
    Inc(AIndex);
  end;
  Result := TAtlasTokenKind.Plain;
  if ((mStart = 1) or (AText[mStart - 1] <> '.')) and
    TAtlasSyntax.IsKeyword(Copy(AText, mStart, AIndex - mStart)) then
  begin
    Result := TAtlasTokenKind.Keyword;
  end;
end;

function NumberEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= Length(AText)) and CharInSet(AText[Result], ['0'..'9', 'A'..'F', 'a'..'f', '.']) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Art des Tokens ab AIndex; AIndex steht danach hinter ihm.</summary>
function TokenAt(const AText: string; var AIndex: Integer): TAtlasTokenKind;
begin
  Result := TAtlasTokenKind.Comment;
  if AText[AIndex] = '''' then
  begin
    AIndex := AfterQuote(AText, AIndex);
    Result := TAtlasTokenKind.StringLiteral;
  end
  else if AText[AIndex] = '{' then
  begin
    AIndex := AfterBrace(AText, AIndex);
  end
  else if (AText[AIndex] = '(') and IsPairAt(AText, AIndex, '*') then
  begin
    AIndex := AfterParenStar(AText, AIndex);
  end
  else if (AText[AIndex] = '/') and IsPairAt(AText, AIndex, '/') then
  begin
    AIndex := Length(AText) + 1;
  end
  else if TTextChars.IsIdentStart(AText[AIndex]) then
  begin
    Result := WordAt(AText, AIndex);
  end
  else if CharInSet(AText[AIndex], ['0'..'9', '$']) then
  begin
    AIndex := NumberEnd(AText, AIndex);
    Result := TAtlasTokenKind.Number;
  end
  else
  begin
    Inc(AIndex);
    Result := TAtlasTokenKind.Plain;
  end;
end;

type
  /// <summary>Wachsende Liste der Tokens; benachbarte Plain-Stücke werden zusammengefasst.</summary>
  TTokenList = record
    Items: TAtlasTokens;
    Count: Integer;
    procedure Emit(AStart, AStop: Integer; AKind: TAtlasTokenKind);
    function Done: TAtlasTokens;
  end;

procedure TTokenList.Emit(AStart, AStop: Integer; AKind: TAtlasTokenKind);
begin
  if AStop <= AStart then
  begin
    Exit;
  end;
  if (AKind = TAtlasTokenKind.Plain) and (Count > 0) and (Items[Count - 1].Kind = TAtlasTokenKind.Plain) and
    (Items[Count - 1].Stop = AStart) then
  begin
    Items[Count - 1].Stop := AStop;
    Exit;
  end;
  if Count = Length(Items) then
  begin
    SetLength(Items, Count * 2 + 4);
  end;
  Items[Count].Start := AStart;
  Items[Count].Stop := AStop;
  Items[Count].Kind := AKind;
  Inc(Count);
end;

function TTokenList.Done: TAtlasTokens;
begin
  SetLength(Items, Count);
  Result := Items;
end;

{ TAtlasSyntax }

class function TAtlasSyntax.IsKeyword(const AWord: string): Boolean;
var
  mWord: string;
begin
  for mWord in cKeywords do
  begin
    if SameText(mWord, AWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasSyntax.Tokens(const AText: string): TAtlasTokens;
var
  mList: TTokenList;
  mIndex, mStart: Integer;
  mKind: TAtlasTokenKind;
begin
  mList := Default(TTokenList);
  // Index 1-basiert über den String; Tokens 0-basiert.
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    mStart := mIndex;
    mKind := TokenAt(AText, mIndex);
    if mIndex > Length(AText) + 1 then
    begin
      mIndex := Length(AText) + 1;
    end;
    mList.Emit(mStart - 1, mIndex - 1, mKind);
  end;
  Result := mList.Done;
end;

type
{$SCOPEDENUMS ON}
  TOpenComment = (None, Brace, ParenStar);
{$SCOPEDENUMS OFF}

/// <summary>Überspringt das Zeichen bzw. den String oder Kommentar an AIndex (danach auf seinem letzten
/// Zeichen). False am Zeilenkommentar oder an einem offenen Kommentar (AOpen).</summary>
function SkipAt(const AText: string; var AIndex: Integer; out AOpen: TOpenComment): Boolean;
var
  mClose: Integer;
begin
  AOpen := TOpenComment.None;
  Result := True;
  mClose := AIndex + 1;
  case AText[AIndex] of
    '''':
      mClose := AfterQuote(AText, AIndex);
    '/':
      Result := not IsPairAt(AText, AIndex, '/');
    '{':
      begin
        mClose := AfterBrace(AText, AIndex);
        AOpen := TOpenComment.Brace;
      end;
    '(':
      if IsPairAt(AText, AIndex, '*') then
      begin
        mClose := AfterParenStar(AText, AIndex);
        AOpen := TOpenComment.ParenStar;
      end;
  end;
  if (AOpen <> TOpenComment.None) and (mClose > Length(AText) + 1) then
  begin
    Result := False;
  end
  else
  begin
    AOpen := TOpenComment.None;
    AIndex := mClose - 1;
  end;
end;

/// <summary>Kommentar, der am Ende von AText (ab dem 1-basierten AFrom) offen bleibt.</summary>
function OpenAtEnd(const AText: string; AFrom: Integer): TOpenComment;
var
  mIndex: Integer;
begin
  Result := TOpenComment.None;
  mIndex := AFrom;
  while (mIndex <= Length(AText)) and SkipAt(AText, mIndex, Result) do
  begin
    Inc(mIndex);
  end;
end;

/// <summary>1-basierte Position hinter dem Ende des offenen Kommentars AState in AText; 0, wenn er weiter offen
/// bleibt.</summary>
function CommentEnd(const AText: string; AState: TOpenComment): Integer;
begin
  Result := 0;
  if AState = TOpenComment.Brace then
  begin
    Result := Pos('}', AText) + 1;
  end
  else if Pos('*)', AText) > 0 then
  begin
    Result := Pos('*)', AText) + 2;
  end;
  if Result = 1 then
  begin
    Result := 0;
  end;
end;

function CommentToken(AStop: Integer): TAtlasTokens;
var
  mHead: TAtlasToken;
begin
  Result := nil;
  if AStop > 0 then
  begin
    mHead.Start := 0;
    mHead.Stop := AStop;
    mHead.Kind := TAtlasTokenKind.Comment;
    Result := [mHead];
  end;
end;

function Shifted(const ATokens: TAtlasTokens; AOffset: Integer): TAtlasTokens;
var
  mIndex: Integer;
begin
  Result := Copy(ATokens);
  for mIndex := 0 to High(Result) do
  begin
    Inc(Result[mIndex].Start, AOffset);
    Inc(Result[mIndex].Stop, AOffset);
  end;
end;

class function TAtlasSyntax.LineTokens(const ALines: TArray<string>): TArray<TAtlasTokens>;
var
  mLine, mClose, mOffset: Integer;
  mState: TOpenComment;
  mText: string;
begin
  Result := nil;
  SetLength(Result, Length(ALines));
  mState := TOpenComment.None;
  for mLine := 0 to High(ALines) do
  begin
    mText := ALines[mLine];
    mOffset := 0;
    Result[mLine] := nil;
    if mState <> TOpenComment.None then
    begin
      mClose := CommentEnd(mText, mState);
      if mClose = 0 then
      begin
        Result[mLine] := CommentToken(Length(mText));
        Continue;
      end;
      Result[mLine] := CommentToken(mClose - 1);
      mOffset := mClose - 1;
    end;
    Result[mLine] := Result[mLine] + Shifted(Tokens(Copy(mText, mOffset + 1, MaxInt)), mOffset);
    mState := OpenAtEnd(mText, mOffset + 1);
  end;
end;

type
  /// <summary>Zustand von DefaultRanges: Klammertiefe und Anfang des offenen Standardwerts (0-basiert, -1 ohne).
  /// </summary>
  TDefaultScan = record
    Depth: Integer;
    Start: Integer;
    Ranges: TArray<TPoint>;
    /// <summary>Offener Standardwert endet vor AIndex.</summary>
    procedure Close(AIndex: Integer);
    procedure Take(const ASignature: string; AIndex: Integer);
  end;

procedure TDefaultScan.Close(AIndex: Integer);
begin
  if (Depth = 1) and (Start >= 0) then
  begin
    Ranges := Ranges + [Point(Start, AIndex - 1)];
    Start := -1;
  end;
end;

procedure TDefaultScan.Take(const ASignature: string; AIndex: Integer);
begin
  case ASignature[AIndex] of
    '(', '[':
      Inc(Depth);
    ')', ']':
      begin
        Close(AIndex);
        Dec(Depth);
      end;
    ';':
      Close(AIndex);
    '=':
      if (Depth = 1) and (Start < 0) then
      begin
        // Leerzeichen vor "=" gehören dazu: "Offset: Integer = 1" → " = 1".
        Start := AIndex - 1;
        while (Start > 0) and (ASignature[Start] = ' ') do
        begin
          Dec(Start);
        end;
      end;
  end;
end;

class function TAtlasSyntax.DefaultRanges(const ASignature: string): TArray<TPoint>;
var
  mIndex: Integer;
  mScan: TDefaultScan;
  mInString: Boolean;
begin
  // 1-basiert über den Text; Ergebnis 0-basiert. "=" auf Ebene 1 beginnt einen Standardwert, der bis
  // vor das nächste ";" bzw. die schließende Klammer derselben Ebene reicht.
  mScan := Default(TDefaultScan);
  mScan.Start := -1;
  mInString := False;
  for mIndex := 1 to Length(ASignature) do
  begin
    if ASignature[mIndex] = '''' then
    begin
      mInString := not mInString;
    end;
    if not mInString then
    begin
      mScan.Take(ASignature, mIndex);
    end;
  end;
  Result := mScan.Ranges;
end;

end.
