unit Atlas.Core.Signature.CallScanner;

// Findet den Aufruf, in dem der Caret steht, und zählt den aktiven Parameter
// (#436) lokal, damit der Wechsel beim Tippen ohne Serveranfrage geht. Gelesen
// wird vorwärts ab höchstens MaxLookBack Zeichen vor dem Caret (Anfang einer
// Zeile). Strings ('' als Anführungszeichen), Kommentare ({ }, (* *), //) und
// Kommas in eckigen Klammern oder inneren Klammern zählen nicht. Eine Klammer
// gilt als Aufruf, wenn davor ein Bezeichner, ")" oder "]" steht; "if (a" nicht.
// Für die Pfadzeile (#438) liefert er auch die Namen der äußeren Aufrufe.

interface

uses
  System.SysUtils;

type
  TAtlasCallSite = record
    Found: Boolean;
    /// <summary>0-basierter Zeichenoffset der öffnenden Klammer im Text.</summary>
    OpenParen: Integer;
    /// <summary>0-basiert: Zahl der Kommas auf der Ebene des Aufrufs vor dem Caret.</summary>
    ActiveParameter: Integer;
    /// <summary>Name vor der Klammer (letzter Bezeichner, z. B. Create in TStringList.Create); '' nach ")" oder
    /// "]".</summary>
    Name: string;
    /// <summary>Namen der umschließenden Aufrufe, äußerster zuerst (#438).</summary>
    Outer: TArray<string>;
  end;

  TAtlasCallScanner = class
  public const
    MaxLookBack = 8000;
  public
    /// <summary>Innerster offener Aufruf vor ACaret (0-basierter Zeichenoffset in AText).</summary>
    class function Scan(const AText: string; ACaret: Integer): TAtlasCallSite; static;
    /// <summary>ANew ist AOld mit genau einem entfernten ")" (Rücktaste oder Entf). Dann soll der
    /// Hint wieder erscheinen, wenn der Caret danach in einem Aufruf steht.</summary>
    class function RemovedClosingParen(const AOld, ANew: string): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils;

type
  TFrame = record
    Position: Integer;
    IsParen: Boolean;
    IsCall: Boolean;
    Commas: Integer;
    Name: string;
  end;

function IsIdentifierChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

/// <summary>Steht vor AIndex (1-basiert, Position der Klammer) ein Bezeichner, ")" oder "]"?</summary>
function FollowsCallee(const AText: string; AFrom, AIndex: Integer): Boolean;
const
  // Schlüsselwörter vor einer Klammer: "if (", "and (" usw. sind keine Aufrufe.
  cKeywords: array[0..19] of string = ('if', 'while', 'until', 'and', 'or', 'not', 'xor', 'case', 'of',
    'then', 'else', 'do', 'to', 'downto', 'in', 'is', 'as', 'div', 'mod', 'repeat');
var
  mIndex, mStop: Integer;
begin
  mIndex := AIndex - 1;
  while (mIndex >= AFrom) and CharInSet(AText[mIndex], [' ', #9, #13, #10]) do
  begin
    Dec(mIndex);
  end;
  if mIndex < AFrom then
  begin
    Exit(False);
  end;
  if CharInSet(AText[mIndex], [')', ']']) then
  begin
    Exit(True);
  end;
  if not IsIdentifierChar(AText[mIndex]) then
  begin
    Exit(False);
  end;
  mStop := mIndex;
  while (mIndex >= AFrom) and IsIdentifierChar(AText[mIndex]) do
  begin
    Dec(mIndex);
  end;
  Result := not MatchText(Copy(AText, mIndex + 1, mStop - mIndex), cKeywords);
end;

/// <summary>Bezeichner direkt vor der Klammer an AIndex (1-basiert); '' ohne.</summary>
function CalleeName(const AText: string; AFrom, AIndex: Integer): string;
var
  mIndex, mStop: Integer;
begin
  mIndex := AIndex - 1;
  while (mIndex >= AFrom) and CharInSet(AText[mIndex], [' ', #9, #13, #10]) do
  begin
    Dec(mIndex);
  end;
  mStop := mIndex;
  while (mIndex >= AFrom) and IsIdentifierChar(AText[mIndex]) do
  begin
    Dec(mIndex);
  end;
  Result := Copy(AText, mIndex + 1, mStop - mIndex);
end;

type
  /// <summary>Zustand von Scan: Text, Bereich, Leseposition (1-basiert) und offene Klammern.</summary>
  TCallScan = record
    Text: string;
    Start: Integer;
    Stop: Integer;
    Index: Integer;
    Stack: TArray<TFrame>;
    /// <summary>String bis zum schließenden Anführungszeichen; '' ist ein Zeichen im String.</summary>
    procedure SkipString;
    procedure SkipToLineEnd;
    /// <summary>„(*“ bis „*)“ überspringen oder eine runde Klammer öffnen.</summary>
    procedure OpenParen;
    procedure OpenBracket;
    /// <summary>Bis zur passenden Klammer abbauen; fehlt sie, ist der Text unvollständig.</summary>
    procedure Close;
    procedure Comma;
    /// <summary>Zeichen an Index lesen; Index steht danach auf dem letzten gelesenen.</summary>
    procedure Step;
    /// <summary>Innerster offener Aufruf; Klammern zur Gruppierung und [...] darüber gehören zu ihm.</summary>
    function Site: TAtlasCallSite;
  end;

procedure TCallScan.SkipString;
begin
  Inc(Index);
  while (Index <= Stop) and not CharInSet(Text[Index], [#13, #10]) do
  begin
    if Text[Index] = '''' then
    begin
      if (Index < Stop) and (Text[Index + 1] = '''') then
      begin
        Inc(Index);
      end
      else
      begin
        Break;
      end;
    end;
    Inc(Index);
  end;
end;

procedure TCallScan.SkipToLineEnd;
begin
  while (Index <= Stop) and not CharInSet(Text[Index], [#13, #10]) do
  begin
    Inc(Index);
  end;
end;

procedure TCallScan.OpenParen;
var
  mFrame: TFrame;
begin
  if (Index < Stop) and (Text[Index + 1] = '*') then
  begin
    Inc(Index, 2);
    while (Index < Stop) and not ((Text[Index] = '*') and (Text[Index + 1] = ')')) do
    begin
      Inc(Index);
    end;
    Inc(Index);
  end
  else
  begin
    mFrame := Default(TFrame);
    mFrame.Position := Index - 1;
    mFrame.IsParen := True;
    mFrame.IsCall := FollowsCallee(Text, Start, Index);
    if mFrame.IsCall then
    begin
      mFrame.Name := CalleeName(Text, Start, Index);
    end;
    Stack := Stack + [mFrame];
  end;
end;

procedure TCallScan.OpenBracket;
var
  mFrame: TFrame;
begin
  mFrame := Default(TFrame);
  mFrame.Position := Index - 1;
  Stack := Stack + [mFrame];
end;

procedure TCallScan.Close;
var
  mLevel: Integer;
begin
  for mLevel := High(Stack) downto 0 do
  begin
    if Stack[mLevel].IsParen = (Text[Index] = ')') then
    begin
      SetLength(Stack, mLevel);
      Break;
    end;
  end;
end;

procedure TCallScan.Comma;
begin
  if Length(Stack) > 0 then
  begin
    Inc(Stack[High(Stack)].Commas);
  end;
end;

procedure TCallScan.Step;
begin
  case Text[Index] of
    '''':
      SkipString;
    '{':
      while (Index <= Stop) and (Text[Index] <> '}') do
      begin
        Inc(Index);
      end;
    '/':
      if (Index < Stop) and (Text[Index + 1] = '/') then
      begin
        SkipToLineEnd;
      end;
    '(':
      OpenParen;
    '[':
      OpenBracket;
    ')', ']':
      Close;
    ',':
      Comma;
  end;
end;

function TCallScan.Site: TAtlasCallSite;
var
  mLevel, mIndex: Integer;
begin
  Result := Default(TAtlasCallSite);
  Result.OpenParen := -1;
  for mLevel := High(Stack) downto 0 do
  begin
    if Stack[mLevel].IsParen and Stack[mLevel].IsCall then
    begin
      Result.Found := True;
      Result.OpenParen := Stack[mLevel].Position;
      Result.ActiveParameter := Stack[mLevel].Commas;
      Result.Name := Stack[mLevel].Name;
      for mIndex := 0 to mLevel - 1 do
      begin
        if Stack[mIndex].IsParen and Stack[mIndex].IsCall then
        begin
          Result.Outer := Result.Outer + [Stack[mIndex].Name];
        end;
      end;
      Break;
    end;
  end;
end;
class function TAtlasCallScanner.Scan(const AText: string; ACaret: Integer): TAtlasCallSite;
var
  mScan: TCallScan;
begin
  mScan := Default(TCallScan);
  mScan.Text := AText;
  mScan.Stop := Min(ACaret, Length(AText));
  // 1-basiert; Anfang einer Zeile höchstens MaxLookBack Zeichen vor dem Caret.
  mScan.Start := Max(1, mScan.Stop - MaxLookBack);
  if mScan.Start > 1 then
  begin
    while (mScan.Start <= mScan.Stop) and (AText[mScan.Start - 1] <> #10) do
    begin
      Inc(mScan.Start);
    end;
  end;
  mScan.Index := mScan.Start;
  while mScan.Index <= mScan.Stop do
  begin
    mScan.Step;
    Inc(mScan.Index);
  end;
  Result := mScan.Site;
end;

class function TAtlasCallScanner.RemovedClosingParen(const AOld, ANew: string): Boolean;
var
  mIndex: Integer;
begin
  if Length(AOld) <> Length(ANew) + 1 then
  begin
    Exit(False);
  end;
  // Erste Abweichung; dort muss die Klammer gestanden haben, der Rest ist gleich.
  mIndex := 1;
  while (mIndex <= Length(ANew)) and (AOld[mIndex] = ANew[mIndex]) do
  begin
    Inc(mIndex);
  end;
  Result := (AOld[mIndex] = ')') and (Copy(AOld, mIndex + 1, MaxInt) = Copy(ANew, mIndex, MaxInt));
end;

end.
