unit Atlas.Common.Editing.Formatter.Layout;

// Zeilenaufbau beim Formatieren (#43): begin und else in eigene Zeilen
// setzen bzw. hochziehen, untereinander stehende Zuweisungen, Deklarationen
// und Kommentare am Zeilenende ausrichten und lange Zeilen umbrechen. Jede
// Ausgabezeile merkt sich ihre Ursprungszeile, damit der Formatierer daraus
// Änderungen je Zeile bzw. Zeilenbereich macht und bei "Auswahl formatieren"
// nur Zeilen im Bereich anfasst. Mehrzeilige Tokens und asm-Blöcke bleiben.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract;

type
  TFormatLine = record
    Text: string;
    /// <summary>Zeile im ursprünglichen Text, aus der diese Zeile stammt.</summary>
    Origin: Integer;
  end;

  TFormatAlignment = (Assignments, Declarations, Constants, Comments);

  TFormatLayout = class
  public
    /// <summary>Zeilen, die in einem mehrzeiligen Token oder einem asm-Block liegen.</summary>
    class function FrozenLines(const ATokens: TArray<TPascalToken>; ACount: Integer): TArray<Boolean>; static;
    /// <summary>Stellung von begin und else nach AStyle; AJoined[L]: Zeile L wurde an die vorige gehängt.</summary>
    class function Place(const ALines: TArray<string>; const ATokens: TArray<TPascalToken>;
      const AStyle: TFormatStyle; AFirst, ALast: Integer; out AJoined: TArray<Boolean>): TArray<TFormatLine>; static;
    /// <summary>Richtet AKind in Gruppen untereinander stehender Zeilen aus; ATokens gehören zu ALines.</summary>
    class procedure Align(var ALines: TArray<TFormatLine>; const ATokens: TArray<TPascalToken>;
      AKind: TFormatAlignment; AFirst, ALast: Integer); static;
    /// <summary>Bricht Zeilen über AStyle.MaxLineLength einmal um; True, wenn sich etwas geändert hat.</summary>
    class function Wrap(var ALines: TArray<TFormatLine>; const ATokens: TArray<TPascalToken>;
      const AStyle: TFormatStyle; AFirst, ALast: Integer): Boolean; static;
    /// <summary>Text einer Einrückungsebene nach AStyle.</summary>
    class function IndentUnit(const AStyle: TFormatStyle): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines;

type
  TSplit = record
    Column: Integer;
    /// <summary>Die neue Zeile rückt eine Ebene tiefer ein (Anweisung hinter begin).</summary>
    Deeper: Boolean;
  end;

function IsCode(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

/// <summary>Tokens je Zeile (Zeile des Anfangs).</summary>
function TokensByLine(const ATokens: TArray<TPascalToken>; ACount: Integer): TArray<TArray<Integer>>;
var
  Index, Line: Integer;
begin
  SetLength(Result, ACount);
  for Index := 0 to High(ATokens) do
  begin
    Line := ATokens[Index].StartPos.Line;
    if (Line >= 0) and (Line < ACount) then
      Result[Line] := Result[Line] + [Index];
  end;
end;

{ TFormatLayout }

class function TFormatLayout.IndentUnit(const AStyle: TFormatStyle): string;
begin
  if AStyle.UseTabs then
    Result := #9
  else
    Result := StringOfChar(' ', Max(AStyle.IndentSize, 1));
end;

class function TFormatLayout.FrozenLines(const ATokens: TArray<TPascalToken>; ACount: Integer): TArray<Boolean>;
var
  Index, Line, AsmDepth: Integer;
  Token: TPascalToken;
begin
  SetLength(Result, ACount);
  AsmDepth := 0;
  for Index := 0 to High(ATokens) do
  begin
    Token := ATokens[Index];
    for Line := Token.StartPos.Line + 1 to Min(Token.EndPos.Line, ACount - 1) do
      Result[Line] := True;
    if (Token.Kind = TPascalTokenKind.Keyword) and Token.IsKeyword('asm') then
      Inc(AsmDepth)
    else if (AsmDepth > 0) and (Token.Kind = TPascalTokenKind.Keyword) and Token.IsKeyword('end') then
      Dec(AsmDepth)
    else if (AsmDepth > 0) and (Token.StartPos.Line < ACount) then
      Result[Token.StartPos.Line] := True;
  end;
end;

class function TFormatLayout.Place(const ALines: TArray<string>; const ATokens: TArray<TPascalToken>;
  const AStyle: TFormatStyle; AFirst, ALast: Integer; out AJoined: TArray<Boolean>): TArray<TFormatLine>;
var
  Frozen: TArray<Boolean>;
  Splits: TArray<TArray<TSplit>>;
  Code: TArray<Integer>;
  Index, K, Line, Column, Part: Integer;
  Token, Before: TPascalToken;
  Word, Previous, Text, Indent: string;
  Split: TSplit;
  Output: TList<TFormatLine>;
  Item: TFormatLine;

  function InRange(ALine: Integer): Boolean;
  begin
    Result := (ALine >= AFirst) and (ALine <= ALast) and not Frozen[ALine];
  end;

  /// <summary>Ist Index das letzte Token seiner Zeile (auch ohne Kommentar dahinter)?</summary>
  function LastOnLine(AIndex: Integer): Boolean;
  begin
    Result := (AIndex = High(ATokens)) or (ATokens[AIndex + 1].StartPos.Line > ATokens[AIndex].EndPos.Line);
  end;

  function FirstOnLine(AIndex: Integer): Boolean;
  begin
    Result := (AIndex = 0) or (ATokens[AIndex - 1].EndPos.Line < ATokens[AIndex].StartPos.Line);
  end;

  procedure AddSplit(ALine, AColumn: Integer; ADeeper: Boolean);
  begin
    Split.Column := AColumn;
    Split.Deeper := ADeeper;
    Splits[ALine] := Splits[ALine] + [Split];
  end;

begin
  SetLength(AJoined, Length(ALines));
  SetLength(Splits, Length(ALines));
  Frozen := FrozenLines(ATokens, Length(ALines));
  Code := nil;
  for Index := 0 to High(ATokens) do
    if IsCode(ATokens[Index]) then
      Code := Code + [Index];
  for K := 1 to High(Code) do
  begin
    Token := ATokens[Code[K]];
    Before := ATokens[Code[K - 1]];
    if Token.Kind <> TPascalTokenKind.Keyword then
      Continue;
    Word := LowerCase(Token.Text);
    Line := Token.StartPos.Line;
    Previous := LowerCase(Before.Text);
    if (Word = 'begin') and MatchStr(Previous, ['then', 'else', 'do']) and (Before.Kind = TPascalTokenKind.Keyword) then
    begin
      if (AStyle.BeginPlacement = TBlockPlacement.NewLine) and (Before.EndPos.Line = Line) and InRange(Line) and
        (Code[K - 1] = Code[K] - 1) then
      begin
        AddSplit(Line, Token.StartPos.Character, False);
        // Was hinter begin steht, kommt in eine eigene Zeile.
        if (Code[K] < High(ATokens)) and (ATokens[Code[K] + 1].StartPos.Line = Line) and
          IsCode(ATokens[Code[K] + 1]) then
          AddSplit(Line, ATokens[Code[K] + 1].StartPos.Character, True);
      end
      else if (AStyle.BeginPlacement = TBlockPlacement.SameLine) and (Before.EndPos.Line = Line - 1) and
        FirstOnLine(Code[K]) and LastOnLine(Code[K - 1]) and InRange(Line) and InRange(Line - 1) and
        (Splits[Line] = nil) then
        // Auch an eine schon angehängte Zeile: "end" + "else" + "begin" werden in einem Lauf eine Zeile, sonst
        // erst im zweiten (#1358, Stabilität).
        AJoined[Line] := True;
    end
    else if (Word = 'else') and (Previous = 'end') and (Before.Kind = TPascalTokenKind.Keyword) then
    begin
      if (AStyle.ElsePlacement = TBlockPlacement.NewLine) and (Before.EndPos.Line = Line) and InRange(Line) and
        (Code[K - 1] = Code[K] - 1) then
        AddSplit(Line, Token.StartPos.Character, False)
      else if (AStyle.ElsePlacement = TBlockPlacement.SameLine) and (Before.EndPos.Line = Line - 1) and
        FirstOnLine(Code[K]) and LastOnLine(Code[K - 1]) and InRange(Line) and InRange(Line - 1) and
        (Splits[Line] = nil) then
        AJoined[Line] := True;
    end;
  end;
  Output := TList<TFormatLine>.Create;
  try
    for Line := 0 to High(ALines) do
    begin
      if AJoined[Line] and (Output.Count > 0) then
      begin
        Item := Output[Output.Count - 1];
        Item.Text := TrimRight(Item.Text) + ' ' + TrimLeft(ALines[Line]);
        Output[Output.Count - 1] := Item;
        Continue;
      end;
      Text := ALines[Line];
      Indent := TTextLines.IndentOf(Text);
      Item.Origin := Line;
      if Splits[Line] = nil then
      begin
        Item.Text := Text;
        Output.Add(Item);
        Continue;
      end;
      Column := 0;
      for Part := 0 to High(Splits[Line]) do
      begin
        Item.Text := TrimRight(Copy(Text, Column + 1, Splits[Line][Part].Column - Column));
        if Part > 0 then
        begin
          Item.Text := Indent + TrimLeft(Item.Text);
          if Splits[Line][Part - 1].Deeper then
            Item.Text := IndentUnit(AStyle) + Item.Text;
        end;
        if Trim(Item.Text) <> '' then
          Output.Add(Item);
        Column := Splits[Line][Part].Column;
      end;
      Item.Text := Indent + TrimLeft(Copy(Text, Column + 1, MaxInt));
      if Splits[Line][High(Splits[Line])].Deeper then
        Item.Text := IndentUnit(AStyle) + Item.Text;
      Output.Add(Item);
    end;
    Result := Output.ToArray;
  finally
    Output.Free;
  end;
end;

class procedure TFormatLayout.Align(var ALines: TArray<TFormatLine>; const ATokens: TArray<TPascalToken>;
  AKind: TFormatAlignment; AFirst, ALast: Integer);
var
  Frozen: TArray<Boolean>;
  ByLine: TArray<TArray<Integer>>;
  GapStart, GapEnd: TArray<Integer>;
  Line, GroupStart, Target: Integer;

  /// <summary>Lücke vor dem auszurichtenden Token der Zeile; False, wenn die Zeile nicht passt.</summary>
  function GapOf(ALine: Integer; out AStart, AEnd: Integer): Boolean;
  var
    Items: TArray<Integer>;
    Position, Depth: Integer;
    Token: TPascalToken;
  begin
    Result := False;
    AStart := 0;
    AEnd := 0;
    if (ALine > High(ByLine)) or (ALines[ALine].Origin < AFirst) or (ALines[ALine].Origin > ALast) or
      Frozen[ALine] then
      Exit;
    Items := ByLine[ALine];
    if Items = nil then
      Exit;
    if AKind = TFormatAlignment.Comments then
    begin
      // Kommentar mit // am Ende einer Codezeile.
      Position := High(Items);
      Token := ATokens[Items[Position]];
      if (Position = 0) or (Token.Kind <> TPascalTokenKind.Comment) or not StartsStr('//', Token.Text) then
        Exit;
      AStart := ATokens[Items[Position - 1]].EndPos.Character;
      AEnd := Token.StartPos.Character;
      Exit(ATokens[Items[Position - 1]].EndPos.Line = ALine);
    end;
    if ATokens[Items[0]].Kind <> TPascalTokenKind.Identifier then
      Exit;
    Depth := 0;
    for Position := 1 to High(Items) do
    begin
      Token := ATokens[Items[Position]];
      if Token.Kind = TPascalTokenKind.Comment then
        Exit;
      if Token.IsSymbol('(') or Token.IsSymbol('[') then
        Inc(Depth)
      else if Token.IsSymbol(')') or Token.IsSymbol(']') then
        Dec(Depth);
      if Depth > 0 then
        Continue;
      case AKind of
        TFormatAlignment.Assignments:
          if Token.IsSymbol(':=') then
          begin
            AStart := ATokens[Items[Position - 1]].EndPos.Character;
            AEnd := Token.StartPos.Character;
            Exit(True);
          end
          else if not (Token.IsSymbol('.') or Token.IsSymbol(']') or Token.IsSymbol('^') or
            (Token.Kind = TPascalTokenKind.Identifier)) then
            Exit;
        TFormatAlignment.Declarations:
          if Token.IsSymbol(':') and (Position < High(Items)) then
          begin
            // Ausgerichtet wird der Typ hinter dem Doppelpunkt; nur ganze Deklarationen mit ;.
            if not ATokens[Items[High(Items)]].IsSymbol(';') then
              Exit;
            AStart := Token.EndPos.Character;
            AEnd := ATokens[Items[Position + 1]].StartPos.Character;
            Exit(True);
          end
          else if not (Token.IsSymbol(',') or (Token.Kind = TPascalTokenKind.Identifier)) then
            Exit;
        TFormatAlignment.Constants:
          if (Position = 1) and Token.IsSymbol('=') then
          begin
            if not ATokens[Items[High(Items)]].IsSymbol(';') then
              Exit;
            AStart := ATokens[Items[0]].EndPos.Character;
            AEnd := Token.StartPos.Character;
            Exit(True);
          end
          else
            Exit;
        TFormatAlignment.Comments: ;
      end;
    end;
  end;

  function IndentOfLine(ALine: Integer): string;
  begin
    Result := TTextLines.IndentOf(ALines[ALine].Text);
  end;

  procedure Flush(AFrom, ATo: Integer);
  var
    Item: Integer;
  begin
    if ATo - AFrom < 1 then
      Exit;
    Target := 0;
    for Item := AFrom to ATo do
      Target := Max(Target, GapStart[Item] + 1);
    for Item := AFrom to ATo do
      ALines[Item].Text := Copy(ALines[Item].Text, 1, GapStart[Item]) +
        StringOfChar(' ', Target - GapStart[Item]) + Copy(ALines[Item].Text, GapEnd[Item] + 1, MaxInt);
  end;

var
  Fits: Boolean;
begin
  Frozen := FrozenLines(ATokens, Length(ALines));
  ByLine := TokensByLine(ATokens, Length(ALines));
  SetLength(GapStart, Length(ALines));
  SetLength(GapEnd, Length(ALines));
  GroupStart := -1;
  for Line := 0 to High(ALines) + 1 do
  begin
    Fits := (Line <= High(ALines)) and GapOf(Line, GapStart[Min(Line, High(ALines))],
      GapEnd[Min(Line, High(ALines))]);
    // Eine Gruppe: aufeinanderfolgende passende Zeilen gleicher Einrückung (Kommentare: beliebige).
    if Fits and (GroupStart >= 0) and ((AKind = TFormatAlignment.Comments) or
      (IndentOfLine(Line) = IndentOfLine(GroupStart))) then
      Continue;
    if GroupStart >= 0 then
      Flush(GroupStart, Line - 1);
    GroupStart := -1;
    if Fits then
      GroupStart := Line;
  end;
end;

class function TFormatLayout.Wrap(var ALines: TArray<TFormatLine>; const ATokens: TArray<TPascalToken>;
  const AStyle: TFormatStyle; AFirst, ALast: Integer): Boolean;
const
  Operators: array[0..11] of string = ('+', '-', '*', '/', 'and', 'or', 'xor', 'div', 'mod', 'shl', 'shr', '<>');
var
  Frozen: TArray<Boolean>;
  ByLine: TArray<TArray<Integer>>;
  Output: TList<TFormatLine>;
  Line, Position, Best: Integer;
  Items: TArray<Integer>;
  Token, Previous: TPascalToken;
  Item: TFormatLine;
  Left: string;
begin
  Result := False;
  if AStyle.MaxLineLength <= 0 then
    Exit;
  Frozen := FrozenLines(ATokens, Length(ALines));
  ByLine := TokensByLine(ATokens, Length(ALines));
  Output := TList<TFormatLine>.Create;
  try
    for Line := 0 to High(ALines) do
    begin
      Item := ALines[Line];
      Items := ByLine[Line];
      Best := -1;
      if (Length(Item.Text) > AStyle.MaxLineLength) and (Item.Origin >= AFirst) and (Item.Origin <= ALast) and
        not Frozen[Line] and (Length(Items) > 1) and IsCode(ATokens[Items[0]]) then
        for Position := 1 to High(Items) do
        begin
          Token := ATokens[Items[Position]];
          Previous := ATokens[Items[Position - 1]];
          if Token.EndPos.Line <> Line then
            Break;
          Left := TrimRight(Copy(Item.Text, 1, Token.StartPos.Character));
          if Length(Left) > AStyle.MaxLineLength then
            Break;
          if Token.Kind = TPascalTokenKind.Comment then
            Continue;
          // Hinter einem Komma oder vor einem zweistelligen Operator.
          if Previous.IsSymbol(',') or (MatchText(Token.Text, Operators) and
            ((Previous.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number,
            TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]) or Previous.IsSymbol(')') or
            Previous.IsSymbol(']'))) then
            if Trim(Left) <> '' then
              Best := Position;
        end;
      if Best < 0 then
      begin
        Output.Add(Item);
        Continue;
      end;
      Token := ATokens[Items[Best]];
      Item.Text := TrimRight(Copy(ALines[Line].Text, 1, Token.StartPos.Character));
      Output.Add(Item);
      Item.Text := TTextLines.IndentOf(ALines[Line].Text) + IndentUnit(AStyle) +
        TrimLeft(Copy(ALines[Line].Text, Token.StartPos.Character + 1, MaxInt));
      Output.Add(Item);
      Result := True;
    end;
    if Result then
      ALines := Output.ToArray;
  finally
    Output.Free;
  end;
end;

end.
