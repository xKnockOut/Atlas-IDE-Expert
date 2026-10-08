unit BDLsp.Common.Editing.BlockCompletion;

// Blockabschluss beim Tippen (#179), ohne Protokollbezug.
//
// Nach Enter hinter begin, try, case … of, record, class/interface (Typ-
// deklaration) oder repeat wird der passende Abschluss in eine eigene Zeile
// unter den Cursor gesetzt: end; bzw. finally/end; bzw. until ;. Eingerückt
// wird er wie die Zeile mit dem öffnenden Wort.
//
// Ob der Block schon geschlossen ist, entscheidet ein Lauf über die Tokens ab
// dem öffnenden Wort mit einem Stapel offener Blöcke: Das end, das den Block
// schließt, gehört nur dann zu ihm, wenn es mindestens so weit eingerückt ist
// wie dessen Zeile. Ein weniger eingerücktes end gehört zum umgebenden Block,
// wie in der Delphi-IDE. Das end. am Ende der Unit schließt keinen Block.

interface

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Rules.Contract;

type
  TBlockCompletion = class
  public
    /// <summary>Edit für den Abschluss nach Enter; APosition ist der Cursor in der neuen Zeile.
    /// False, wenn nichts zu ergänzen ist.</summary>
    class function AfterEnter(const AText: string; const ATokens: TArray<TPascalToken>;
      const APosition: TTextPosition; AKinds: TBlockKinds; out AEdit: TRuleEdit): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function PreviousIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

function NextIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

/// <summary>class, interface oder dispinterface als Beginn einer Typdeklaration mit Rumpf,
/// nicht class of, keine Vorwärtsdeklaration.</summary>
function IsTypeBlockAt(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  Previous, Next, Depth: Integer;
begin
  Result := False;
  if not (ATokens[AIndex].IsKeyword('class') or ATokens[AIndex].IsKeyword('interface') or
    ATokens[AIndex].IsKeyword('dispinterface')) then
    Exit;
  Previous := PreviousIndex(ATokens, AIndex);
  if (Previous >= 0) and ATokens[Previous].IsKeyword('packed') then
    Previous := PreviousIndex(ATokens, Previous);
  if (Previous < 0) or not ATokens[Previous].IsSymbol('=') then
    Exit;
  Next := NextIndex(ATokens, AIndex);
  if Next > High(ATokens) then
    Exit(True);
  if ATokens[Next].IsKeyword('of') then
    Exit;
  if ATokens[Next].IsSymbol('(') then
  begin
    Depth := 0;
    while Next <= High(ATokens) do
    begin
      if ATokens[Next].IsSymbol('(') then
        Inc(Depth)
      else if ATokens[Next].IsSymbol(')') then
      begin
        Dec(Depth);
        if Depth = 0 then
          Break;
      end;
      Inc(Next);
    end;
    Next := NextIndex(ATokens, Next);
    if Next > High(ATokens) then
      Exit(True);
  end;
  Result := not ATokens[Next].IsSymbol(';');
end;

/// <summary>Art des Blocks, den das Token an AIndex als letztes Token einer Zeile öffnet.</summary>
function OpenerAt(const ATokens: TArray<TPascalToken>; AIndex: Integer; out AKind: TBlockKind): Boolean;
var
  Scan: Integer;
begin
  Result := True;
  if ATokens[AIndex].IsKeyword('begin') then
    AKind := TBlockKind.Begin_
  else if ATokens[AIndex].IsKeyword('try') then
    AKind := TBlockKind.Try_
  else if ATokens[AIndex].IsKeyword('repeat') then
    AKind := TBlockKind.Repeat_
  else if ATokens[AIndex].IsKeyword('record') then
    AKind := TBlockKind.Record_
  else if ATokens[AIndex].IsKeyword('of') then
  begin
    // case … of in derselben Anweisung.
    Scan := PreviousIndex(ATokens, AIndex);
    while (Scan >= 0) and not ATokens[Scan].IsSymbol(';') and not ATokens[Scan].IsKeyword('case') and
      not ATokens[Scan].IsKeyword('begin') do
      Scan := PreviousIndex(ATokens, Scan);
    Result := (Scan >= 0) and ATokens[Scan].IsKeyword('case');
    AKind := TBlockKind.Case_;
  end
  else if IsTypeBlockAt(ATokens, AIndex) then
    AKind := TBlockKind.Class_
  else if ATokens[AIndex].IsSymbol(')') then
  begin
    // TFoo = class(TBasis)
    Scan := AIndex;
    while (Scan >= 0) and not ATokens[Scan].IsSymbol('(') do
      Dec(Scan);
    Scan := PreviousIndex(ATokens, Scan);
    Result := (Scan >= 0) and IsTypeBlockAt(ATokens, Scan);
    AKind := TBlockKind.Class_;
  end
  else
    Result := False;
end;

function LineIndent(const ALine: string): string;
var
  Count: Integer;
begin
  Count := 0;
  while (Count < Length(ALine)) and CharInSet(ALine[Count + 1], [' ', #9]) do
    Inc(Count);
  Result := Copy(ALine, 1, Count);
end;

/// <summary>Spalte des ersten Tokens in der Zeile von AIndex.</summary>
function LineStartColumn(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  while (AIndex > 0) and (ATokens[AIndex - 1].StartPos.Line = ATokens[AIndex].StartPos.Line) do
    Dec(AIndex);
  Result := ATokens[AIndex].StartPos.Character;
end;

function IsProgram(const ATokens: TArray<TPascalToken>): Boolean;
var
  First: Integer;
begin
  First := NextIndex(ATokens, -1);
  Result := (First <= High(ATokens)) and (ATokens[First].IsKeyword('program') or ATokens[First].IsKeyword('library'));
end;

/// <summary>True, wenn der Block ab AOpener schon geschlossen ist.</summary>
function IsClosed(const ATokens: TArray<TPascalToken>; AOpener: Integer; AKind: TBlockKind): Boolean;
var
  Stack: TStack<TBlockKind>;
  Index, Index2, Column: Integer;
  Token: TPascalToken;
begin
  Column := LineStartColumn(ATokens, AOpener);
  Stack := TStack<TBlockKind>.Create;
  try
    Stack.Push(AKind);
    for Index := AOpener + 1 to High(ATokens) do
    begin
      Token := ATokens[Index];
      if AKind = TBlockKind.Repeat_ then
      begin
        if Token.IsKeyword('repeat') then
          Stack.Push(TBlockKind.Repeat_)
        else if Token.IsKeyword('until') then
          Stack.Pop;
      end
      else if Token.IsKeyword('begin') or Token.IsKeyword('try') or Token.IsKeyword('asm') then
        Stack.Push(TBlockKind.Begin_)
      else if Token.IsKeyword('record') then
        Stack.Push(TBlockKind.Record_)
      else if Token.IsKeyword('case') then
      begin
        // Der variante Teil eines Records hat kein eigenes end.
        if Stack.Peek <> TBlockKind.Record_ then
          Stack.Push(TBlockKind.Case_);
      end
      else if IsTypeBlockAt(ATokens, Index) then
        Stack.Push(TBlockKind.Class_)
      else if Token.IsKeyword('end') then
      begin
        // "end." schließt in einer Unit keinen offenen Block, in Programmen und
        // Bibliotheken nur den Hauptblock.
        Index2 := NextIndex(ATokens, Index);
        if (Index2 <= High(ATokens)) and ATokens[Index2].IsSymbol('.') then
          Exit((Stack.Count = 1) and (AKind = TBlockKind.Begin_) and IsProgram(ATokens));
        Stack.Pop;
      end
      else
        Continue;
      if Stack.Count = 0 then
        Exit(Token.StartPos.Character >= Column);
    end;
    Result := False;
  finally
    Stack.Free;
  end;
end;

{ TBlockCompletion }

class function TBlockCompletion.AfterEnter(const AText: string; const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition; AKinds: TBlockKinds; out AEdit: TRuleEdit): Boolean;
var
  Lines: TArray<string>;
  LineBreak, Indent, Closing: string;
  Opener, Index: Integer;
  Kind: TBlockKind;
begin
  Result := False;
  if APosition.Line < 1 then
    Exit;
  Lines := AText.Replace(#13#10, #10).Split([#10]);
  if APosition.Line > High(Lines) then
    Exit;
  // Nur in einer sonst leeren neuen Zeile.
  if Trim(Lines[APosition.Line]) <> '' then
    Exit;
  Opener := -1;
  for Index := High(ATokens) downto 0 do
    if not IsTrivia(ATokens[Index]) and (ATokens[Index].EndPos.Line < APosition.Line) then
    begin
      Opener := Index;
      Break;
    end;
  if (Opener < 0) or (ATokens[Opener].EndPos.Line <> APosition.Line - 1) then
    Exit;
  if not OpenerAt(ATokens, Opener, Kind) or not (Kind in AKinds) or IsClosed(ATokens, Opener, Kind) then
    Exit;
  if Pos(#13#10, AText) > 0 then
    LineBreak := #13#10
  else
    LineBreak := #10;
  Indent := LineIndent(Lines[ATokens[Opener].StartPos.Line]);
  case Kind of
    TBlockKind.Try_:
      Closing := 'finally' + LineBreak + Indent + 'end;';
    TBlockKind.Repeat_:
      Closing := 'until ;';
  else
    Closing := 'end;';
  end;
  AEdit := TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(APosition.Line, Length(Lines[APosition.Line])),
    TTextPosition.Create(APosition.Line, Length(Lines[APosition.Line]))), LineBreak + Indent + Closing);
  Result := True;
end;

end.
