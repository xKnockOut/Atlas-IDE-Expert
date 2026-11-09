unit Atlas.Core.Outline.TypeText;

// Text einer Typdeklaration als Folge von Wörtern und Zeichen (#1759, #1767),
// Kern ohne VCL und OTA: Kommentare, Direktiven und Strings fallen weg, der
// Text verschachtelter Typen zählt nicht (sie haben ihre eigenen Abschnitte
// und Blöcke). Grundlage für Sichtbarkeitsabschnitte und Unterblöcke der
// Brotkrumenleiste.

interface

uses
  Atlas.Core.Outline.Model;

type
  TAtlasTypeToken = record
    /// <summary>Wort klein bzw. das Zeichen.</summary>
    Text: string;
    Line: Integer;
    Character: Integer;
    /// <summary>Wort (Bezeichner oder Schlüsselwort), sonst Zeichen.</summary>
    Word: Boolean;
    /// <summary>Mit &amp; markierter Bezeichner (&amp;private).</summary>
    Escaped: Boolean;
  end;

  TAtlasTypeTokens = TArray<TAtlasTypeToken>;

  TAtlasTypeText = class
  public
    /// <summary>Wörter und Zeichen der Deklaration des Typs AType ohne verschachtelte Typen.</summary>
    class function Tokens(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      AType: Integer): TAtlasTypeTokens; static;
    /// <summary>Liegt ALine/ACharacter vor AOtherLine/AOtherCharacter?</summary>
    class function Before(ALine, ACharacter, AOtherLine, AOtherCharacter: Integer): Boolean; static;
    /// <summary>Ist AText eines der Wörter AWords?</summary>
    class function IsOneOf(const AText: string; const AWords: array of string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Chars;

type
  /// <summary>Bereich eines verschachtelten Typs, dessen Text nicht zählt.</summary>
  TRange = record
    StartLine: Integer;
    StartCharacter: Integer;
    EndLine: Integer;
    EndCharacter: Integer;
  end;

class function TAtlasTypeText.Before(ALine, ACharacter, AOtherLine, AOtherCharacter: Integer): Boolean;
begin
  Result := (ALine < AOtherLine) or ((ALine = AOtherLine) and (ACharacter < AOtherCharacter));
end;

function InRange(const ARange: TRange; ALine, ACharacter: Integer): Boolean;
begin
  Result := not TAtlasTypeText.Before(ALine, ACharacter, ARange.StartLine, ARange.StartCharacter) and
    TAtlasTypeText.Before(ALine, ACharacter, ARange.EndLine, ARange.EndCharacter);
end;

function RangeOf(const ANode: TAtlasOutlineNode): TRange;
begin
  Result.StartLine := ANode.StartLine;
  Result.StartCharacter := ANode.StartCharacter;
  Result.EndLine := ANode.EndLine;
  Result.EndCharacter := ANode.EndCharacter;
end;

function IsDescendant(const ANodes: TAtlasOutlineNodes; ANode, AAncestor: Integer): Boolean;
var
  mParent: Integer;
begin
  mParent := ANodes[ANode].Parent;
  while mParent >= 0 do
  begin
    if mParent = AAncestor then
    begin
      Exit(True);
    end;
    mParent := ANodes[mParent].Parent;
  end;
  Result := False;
end;

/// <summary>Bereiche der in AType verschachtelten Typen.</summary>
function NestedTypes(const ANodes: TAtlasOutlineNodes; AType: Integer): TArray<TRange>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ANodes) do
  begin
    if (ANodes[mIndex].Category = TAtlasOutlineCategory.TypeDecl) and IsDescendant(ANodes, mIndex, AType) then
    begin
      Result := Result + [RangeOf(ANodes[mIndex])];
    end;
  end;
end;

function Skipped(const ARanges: TArray<TRange>; ALine, ACharacter: Integer): Boolean;
var
  mRange: TRange;
begin
  for mRange in ARanges do
  begin
    if InRange(mRange, ALine, ACharacter) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function NextIs(const ALine: string; APos: Integer; AChar: Char): Boolean;
begin
  Result := (APos < Length(ALine)) and (ALine[APos + 1] = AChar);
end;

type
  /// <summary>Zerlegt Text in Wörter und Zeichen; Kommentare, Direktiven und Strings fallen weg.</summary>
  TTokenizer = class
  private
    FTokens: TAtlasTypeTokens;
    FSkip: TArray<TRange>;
    FRange: TRange;
    /// <summary>Offener Kommentar: '{', '(' für (* *), #0 = keiner.</summary>
    FComment: Char;
    FInString: Boolean;
    FEscaped: Boolean;
    procedure Add(const AText: string; ALine, ACharacter: Integer; AWord: Boolean);
    function InComment(const AText: string; var APos: Integer): Boolean;
    function OpensComment(const AText: string; var APos: Integer): Boolean;
    function ReadWord(const AText: string; ALine: Integer; var APos: Integer): Boolean;
    procedure ScanLine(const AText: string; ALine, AFirst, ALast: Integer);
  public
    constructor Create(const ARange: TRange; const ASkip: TArray<TRange>);
    function Run(const ALines: TArray<string>): TAtlasTypeTokens;
  end;

constructor TTokenizer.Create(const ARange: TRange; const ASkip: TArray<TRange>);
begin
  inherited Create;
  FRange := ARange;
  FSkip := ASkip;
end;

procedure TTokenizer.Add(const AText: string; ALine, ACharacter: Integer; AWord: Boolean);
var
  mToken: TAtlasTypeToken;
begin
  if Skipped(FSkip, ALine, ACharacter) then
  begin
    FEscaped := False;
    Exit;
  end;
  mToken.Text := LowerCase(AText);
  mToken.Line := ALine;
  mToken.Character := ACharacter;
  mToken.Word := AWord;
  mToken.Escaped := FEscaped and AWord;
  FEscaped := False;
  FTokens := FTokens + [mToken];
end;

/// <summary>Im Kommentar oder String: True, solange er an APos (1-basiert) noch offen ist.</summary>
function TTokenizer.InComment(const AText: string; var APos: Integer): Boolean;
begin
  Result := True;
  if FInString then
  begin
    FInString := AText[APos] <> '''';
  end
  else if (FComment = '{') and (AText[APos] = '}') then
  begin
    FComment := #0;
  end
  else if (FComment = '(') and (AText[APos] = '*') and NextIs(AText, APos, ')') then
  begin
    FComment := #0;
    Inc(APos);
  end
  else
  begin
    Result := (FComment <> #0);
  end;
end;

/// <summary>Öffnet an APos ein Kommentar oder String? Bei // wird APos hinter das Zeilenende gesetzt.</summary>
function TTokenizer.OpensComment(const AText: string; var APos: Integer): Boolean;
begin
  Result := True;
  case AText[APos] of
    '''':
      FInString := True;
    '{':
      FComment := '{';
    '/':
      if NextIs(AText, APos, '/') then
      begin
        APos := Length(AText);
      end
      else
      begin
        Result := False;
      end;
    '(':
      if NextIs(AText, APos, '*') then
      begin
        FComment := '(';
        Inc(APos);
      end
      else
      begin
        Result := False;
      end;
  else
    Result := False;
  end;
end;

function TTokenizer.ReadWord(const AText: string; ALine: Integer; var APos: Integer): Boolean;
var
  mStart: Integer;
begin
  Result := TTextChars.IsIdentStart(AText[APos]);
  if not Result then
  begin
    Exit;
  end;
  mStart := APos;
  while (APos < Length(AText)) and TTextChars.IsIdentChar(AText[APos + 1]) do
  begin
    Inc(APos);
  end;
  Add(Copy(AText, mStart, APos - mStart + 1), ALine, mStart - 1, True);
end;

/// <summary>Zeile ALine von Zeichen AFirst bis vor ALast (0-basiert).</summary>
procedure TTokenizer.ScanLine(const AText: string; ALine, AFirst, ALast: Integer);
var
  mPos: Integer;
begin
  // Ein String endet spätestens am Zeilenende.
  FInString := False;
  mPos := AFirst + 1;
  while mPos <= ALast do
  begin
    if InComment(AText, mPos) or OpensComment(AText, mPos) or ReadWord(AText, ALine, mPos) then
    begin
      Inc(mPos);
      Continue;
    end;
    if AText[mPos] = '&' then
    begin
      FEscaped := True;
    end
    else if AText[mPos] > ' ' then
    begin
      Add(AText[mPos], ALine, mPos - 1, False);
    end;
    Inc(mPos);
  end;
end;

function TTokenizer.Run(const ALines: TArray<string>): TAtlasTypeTokens;
var
  mLine, mFirst, mLast: Integer;
begin
  FTokens := nil;
  FComment := #0;
  for mLine := FRange.StartLine to FRange.EndLine do
  begin
    if (mLine < 0) or (mLine > High(ALines)) then
    begin
      Continue;
    end;
    mFirst := 0;
    if mLine = FRange.StartLine then
    begin
      mFirst := FRange.StartCharacter;
    end;
    mLast := Length(ALines[mLine]);
    if (mLine = FRange.EndLine) and (FRange.EndCharacter < mLast) then
    begin
      mLast := FRange.EndCharacter;
    end;
    ScanLine(ALines[mLine], mLine, mFirst, mLast);
  end;
  Result := FTokens;
end;

class function TAtlasTypeText.Tokens(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  AType: Integer): TAtlasTypeTokens;
var
  mTokenizer: TTokenizer;
begin
  mTokenizer := TTokenizer.Create(RangeOf(ANodes[AType]), NestedTypes(ANodes, AType));
  try
    Result := mTokenizer.Run(ALines);
  finally
    mTokenizer.Free;
  end;
end;

class function TAtlasTypeText.IsOneOf(const AText: string; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  for mWord in AWords do
  begin
    if AText = mWord then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
