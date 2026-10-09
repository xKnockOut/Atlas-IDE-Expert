unit Argus.Core.Signature.CallScanner;

// Findet den Aufruf, in dem der Caret steht, und zählt den aktiven Parameter
// (#436) lokal, damit der Wechsel beim Tippen ohne Serveranfrage geht. Gelesen
// wird vorwärts ab höchstens MaxLookBack Zeichen vor dem Caret (Anfang einer
// Zeile). Strings ('' als Anführungszeichen), Kommentare ({ }, (* *), //) und
// Kommas in eckigen Klammern oder inneren Klammern zählen nicht. Eine Klammer
// gilt als Aufruf, wenn davor ein Bezeichner, ")" oder "]" steht; "if (a" nicht.

interface

uses
  System.SysUtils;

type
  TArgusCallSite = record
    Found: Boolean;
    /// <summary>0-basierter Zeichenoffset der öffnenden Klammer im Text.</summary>
    OpenParen: Integer;
    /// <summary>0-basiert: Zahl der Kommas auf der Ebene des Aufrufs vor dem Caret.</summary>
    ActiveParameter: Integer;
  end;

  TArgusCallScanner = class
  public const
    MaxLookBack = 8000;
  public
    /// <summary>Innerster offener Aufruf vor ACaret (0-basierter Zeichenoffset in AText).</summary>
    class function Scan(const AText: string; ACaret: Integer): TArgusCallSite; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Generics.Collections;

type
  TFrame = record
    Position: Integer;
    IsParen: Boolean;
    IsCall: Boolean;
    Commas: Integer;
  end;

function IsIdentifierChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

/// <summary>Steht vor AIndex (1-basiert, Position der Klammer) ein Bezeichner, ")" oder "]"?</summary>
function FollowsCallee(const AText: string; AFrom, AIndex: Integer): Boolean;
const
  // Schlüsselwörter vor einer Klammer: "if (", "and (" usw. sind keine Aufrufe.
  Keywords: array[0..19] of string = ('if', 'while', 'until', 'and', 'or', 'not', 'xor', 'case', 'of',
    'then', 'else', 'do', 'to', 'downto', 'in', 'is', 'as', 'div', 'mod', 'repeat');
var
  Index, Stop: Integer;
begin
  Index := AIndex - 1;
  while (Index >= AFrom) and CharInSet(AText[Index], [' ', #9, #13, #10]) do
    Dec(Index);
  if Index < AFrom then
    Exit(False);
  if CharInSet(AText[Index], [')', ']']) then
    Exit(True);
  if not IsIdentifierChar(AText[Index]) then
    Exit(False);
  Stop := Index;
  while (Index >= AFrom) and IsIdentifierChar(AText[Index]) do
    Dec(Index);
  Result := not MatchText(Copy(AText, Index + 1, Stop - Index), Keywords);
end;

class function TArgusCallScanner.Scan(const AText: string; ACaret: Integer): TArgusCallSite;
var
  Stack: TList<TFrame>;
  Frame: TFrame;
  Index, Stop, Start, Level: Integer;
begin
  Result := Default(TArgusCallSite);
  Result.OpenParen := -1;
  Stop := Min(ACaret, Length(AText));
  // 1-basiert; Anfang einer Zeile höchstens MaxLookBack Zeichen vor dem Caret.
  Start := Max(1, Stop - MaxLookBack);
  if Start > 1 then
  begin
    while (Start <= Stop) and (AText[Start - 1] <> #10) do
      Inc(Start);
  end;
  Stack := TList<TFrame>.Create;
  try
    Index := Start;
    while Index <= Stop do
    begin
      case AText[Index] of
        '''':
          begin
            // String bis zum schließenden Anführungszeichen; '' ist ein Zeichen im String.
            Inc(Index);
            while (Index <= Stop) and not CharInSet(AText[Index], [#13, #10]) do
            begin
              if AText[Index] = '''' then
              begin
                if (Index < Stop) and (AText[Index + 1] = '''') then
                  Inc(Index)
                else
                  Break;
              end;
              Inc(Index);
            end;
          end;
        '{':
          while (Index <= Stop) and (AText[Index] <> '}') do
            Inc(Index);
        '/':
          if (Index < Stop) and (AText[Index + 1] = '/') then
            while (Index <= Stop) and not CharInSet(AText[Index], [#13, #10]) do
              Inc(Index);
        '(':
          if (Index < Stop) and (AText[Index + 1] = '*') then
          begin
            Inc(Index, 2);
            while (Index < Stop) and not ((AText[Index] = '*') and (AText[Index + 1] = ')')) do
              Inc(Index);
            Inc(Index);
          end
          else
          begin
            Frame := Default(TFrame);
            Frame.Position := Index - 1;
            Frame.IsParen := True;
            Frame.IsCall := FollowsCallee(AText, Start, Index);
            Stack.Add(Frame);
          end;
        '[':
          begin
            Frame := Default(TFrame);
            Frame.Position := Index - 1;
            Stack.Add(Frame);
          end;
        ')', ']':
          begin
            // Bis zur passenden Klammer abbauen; fehlt sie, ist der Text unvollständig.
            for Level := Stack.Count - 1 downto 0 do
              if Stack[Level].IsParen = (AText[Index] = ')') then
              begin
                Stack.Count := Level;
                Break;
              end;
          end;
        ',':
          if Stack.Count > 0 then
          begin
            Frame := Stack.Last;
            Inc(Frame.Commas);
            Stack[Stack.Count - 1] := Frame;
          end;
      end;
      Inc(Index);
    end;
    // Innerster offener Aufruf; Klammern zur Gruppierung und [...] darüber gehören zu ihm.
    for Level := Stack.Count - 1 downto 0 do
      if Stack[Level].IsParen and Stack[Level].IsCall then
      begin
        Result.Found := True;
        Result.OpenParen := Stack[Level].Position;
        Result.ActiveParameter := Stack[Level].Commas;
        Break;
      end;
  finally
    Stack.Free;
  end;
end;

end.
