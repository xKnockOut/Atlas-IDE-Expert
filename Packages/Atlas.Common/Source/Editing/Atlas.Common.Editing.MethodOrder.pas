unit Atlas.Common.Editing.MethodOrder;

// Methodenrümpfe in Deklarationsreihenfolge (#660).
//
// Arrange ordnet alle Rümpfe der Unit: nach ihrem Typ (Reihenfolge der Typen
// in der Datei) und dort nach der Deklarationsreihenfolge, alternativ
// alphabetisch. Die Rümpfe tauschen nur untereinander die Plätze; freie
// Routinen, Rümpfe ohne Deklaration, {$REGION}-Klammern und alles zwischen
// den Rümpfen bleibt stehen. Kommentare direkt über einem Rumpf (ohne
// Leerzeile) wandern mit.
//
// Nicht verschoben ("bleibt") wird ein Rumpf,
//   - der in einer Region oder einem {$IF…}-Zweig liegt oder dessen Bereich
//     eine solche Klammer nur zur Hälfte enthält,
//   - der eine Zeile mit anderem Code teilt.
//
// PlaceNew setzt nur neue Rümpfe an ihre Stelle: hinter den Rumpf der
// zuletzt davor deklarierten Methode desselben Typs, sonst vor den der
// nächsten, sonst hinter den letzten Rumpf eines früheren bzw. vor den ersten
// eines späteren Typs. Neu ist ein Rumpf, dessen Kopfzeile im Text vorher
// (ABefore) nicht vorkam und der keinen dort schon vorhandenen Routinenkopf
// umschließt; so zählt ein halb getippter Rumpf, der den nächsten
// verschluckt, nicht als neu.
//
// Beide liefern eine Textänderung über den betroffenen Zeilenbereich und je
// Rumpf die Verschiebung in Rümpfen (negativ = nach oben).

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  {$SCOPEDENUMS ON}
  /// <summary>Ordnung der Rümpfe; Off schaltet Verschieben und Befehl ab (editor.methodPlacement).</summary>
  TMethodPlacement = (Off, Declaration, Alphabetical);

  /// <summary>Warum ein Rumpf stehen bleibt.</summary>
  TMethodStayReason = (None, Region, Conditional, SharedLine);
  {$SCOPEDENUMS OFF}

  TMethodMove = record
    TypeName: string;
    Name: string;
    /// <summary>Zeile des Kopfs im Text vor der Änderung.</summary>
    Line: Integer;
    /// <summary>Verschiebung in Rümpfen; negativ = nach oben.</summary>
    Delta: Integer;
    /// <summary>Bleibt stehen (Grund in Reason).</summary>
    Fixed: Boolean;
    Reason: TMethodStayReason;
  end;

  TMethodOrderResult = record
    Edits: TArray<TTextEdit>;
    /// <summary>Verschobene Rümpfe in der neuen Reihenfolge, danach die stehen bleibenden.</summary>
    Moves: TArray<TMethodMove>;
  end;

  TMethodOrder = class
  public
    /// <summary>Ordnet alle Rümpfe der Unit; ohne Edits, wenn alles passt oder APlacement Off ist.</summary>
    class function Arrange(ATree: TSyntaxTree; const AText: string;
      APlacement: TMethodPlacement): TMethodOrderResult; static;
    /// <summary>Setzt die gegenüber ABefore neuen Rümpfe an ihre Stelle; ohne Edits, wenn keiner neu ist oder
    /// alle schon passen.</summary>
    class function PlaceNew(ATree: TSyntaxTree; const AText, ABefore: string;
      APlacement: TMethodPlacement): TMethodOrderResult; static;
    /// <summary>off, declaration, alphabetical.</summary>
    class function PlacementName(APlacement: TMethodPlacement): string; static;
    /// <summary>Unbekannt oder leer: Declaration.</summary>
    class function PlacementOf(const AName: string): TMethodPlacement; static;
    /// <summary>'', region, ifdef, line.</summary>
    class function ReasonName(AReason: TMethodStayReason): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.ClassCompletion;

type
  TBlock = record
    TypeName, Name: string;
    TypeOrder, DeclarationOrder: Integer;
    /// <summary>Erste Zeile (mit Kommentaren darüber), Kopfzeile, letzte Zeile.</summary>
    First, Header, Last: Integer;
    Fixed, New: Boolean;
    Reason: TMethodStayReason;
  end;

  TBlocks = TArray<TBlock>;

  /// <summary>Ziel eines neuen Rumpfs.</summary>
  TAnchor = record
    /// <summary>Index in den vorhandenen Rümpfen; -1 = bleibt, wo er ist.</summary>
    Block: Integer;
    After: Boolean;
  end;

const
  RoutineWords: array[0..5] of string = ('procedure ', 'function ', 'constructor ', 'destructor ', 'operator ',
    'class ');

function Before(const A, B: TBlock; APlacement: TMethodPlacement): Boolean;
var
  Compared: Integer;
begin
  if A.TypeOrder <> B.TypeOrder then
    Exit(A.TypeOrder < B.TypeOrder);
  if APlacement = TMethodPlacement.Alphabetical then
  begin
    Compared := CompareText(A.Name, B.Name);
    if Compared <> 0 then
      Exit(Compared < 0);
  end;
  if A.DeclarationOrder <> B.DeclarationOrder then
    Exit(A.DeclarationOrder < B.DeclarationOrder);
  // Eindeutig weiter nach der Stelle im Text.
  Result := A.First < B.First;
end;

/// <summary>Stabil nach Ordnung (Einfügen; die Zahl der Rümpfe bleibt klein).</summary>
function Sorted(const ABlocks: TBlocks; APlacement: TMethodPlacement): TBlocks;
var
  Index, Target: Integer;
  Item: TBlock;
begin
  Result := Copy(ABlocks);
  for Index := 1 to High(Result) do
  begin
    Item := Result[Index];
    Target := Index - 1;
    while (Target >= 0) and Before(Item, Result[Target], APlacement) do
    begin
      Result[Target + 1] := Result[Target];
      Dec(Target);
    end;
    Result[Target + 1] := Item;
  end;
end;

function ByLine(const ABlocks: TBlocks): TBlocks;
var
  Index, Target: Integer;
  Item: TBlock;
begin
  Result := Copy(ABlocks);
  for Index := 1 to High(Result) do
  begin
    Item := Result[Index];
    Target := Index - 1;
    while (Target >= 0) and (Item.First < Result[Target].First) do
    begin
      Result[Target + 1] := Result[Target];
      Dec(Target);
    end;
    Result[Target + 1] := Item;
  end;
end;

function IndexOfBlock(const ABlocks: TBlocks; const ABlock: TBlock): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ABlocks) do
    if ABlocks[Index].Header = ABlock.Header then
      Exit(Index);
  Result := -1;
end;

function IsRoutineHeader(const ALine: string): Boolean;
var
  Word: string;
  Lower: string;
begin
  Lower := LowerCase(Trim(ALine));
  for Word in RoutineWords do
    if StartsStr(Word, Lower) then
      Exit(True);
  Result := False;
end;

/// <summary>Die Rümpfe deklarierter Methoden mit ihrem Bereich; markiert, was stehen bleiben muss.</summary>
function CollectBlocks(ATree: TSyntaxTree; const AText: string; const ALines: TArray<string>): TBlocks;
var
  Code, Comment: TArray<Boolean>;
  CondDelta, RegionDelta, CondAt, RegionAt: TArray<Integer>;
  Token: TPascalToken;
  Directive: string;
  Line, Index: Integer;
  Method: TDeclaredMethod;
  Block: TBlock;
  Rest: string;
  Ordered: TBlocks;
begin
  Result := nil;
  SetLength(Code, Length(ALines));
  SetLength(Comment, Length(ALines));
  SetLength(CondDelta, Length(ALines) + 1);
  SetLength(RegionDelta, Length(ALines) + 1);
  for Token in ATree.Tokens do
  begin
    if (Token.StartPos.Line < 0) or (Token.EndPos.Line > High(ALines)) then
      Continue;
    for Line := Token.StartPos.Line to Token.EndPos.Line do
      if Token.Kind = TPascalTokenKind.Comment then
        Comment[Line] := True
      else
        Code[Line] := True;
    if Token.Kind <> TPascalTokenKind.Directive then
      Continue;
    Directive := TPascalLexer.DirectiveName(Token.Text);
    if (Directive = 'IF') or (Directive = 'IFDEF') or (Directive = 'IFNDEF') or (Directive = 'IFOPT') then
      Inc(CondDelta[Token.StartPos.Line])
    else if (Directive = 'ENDIF') or (Directive = 'IFEND') then
      Dec(CondDelta[Token.StartPos.Line])
    else if Directive = 'REGION' then
      Inc(RegionDelta[Token.StartPos.Line])
    else if Directive = 'ENDREGION' then
      Dec(RegionDelta[Token.StartPos.Line]);
  end;
  // Tiefe am Anfang jeder Zeile; der letzte Eintrag gilt hinter der letzten Zeile.
  SetLength(CondAt, Length(ALines) + 1);
  SetLength(RegionAt, Length(ALines) + 1);
  for Line := 1 to Length(ALines) do
  begin
    CondAt[Line] := CondAt[Line - 1] + CondDelta[Line - 1];
    RegionAt[Line] := RegionAt[Line - 1] + RegionDelta[Line - 1];
  end;
  for Method in TClassCompletion.DeclaredMethods(ATree, AText) do
  begin
    if not Method.HasBody or (Method.Body.Range.EndPos.Line > High(ALines)) then
      Continue;
    Block := Default(TBlock);
    Block.TypeName := Method.TypeName;
    Block.Name := Method.Declaration.Name;
    Block.TypeOrder := Method.TypeOrder;
    Block.DeclarationOrder := Method.DeclarationOrder;
    Block.Header := Method.Body.Range.StartPos.Line;
    Block.Last := Method.Body.Range.EndPos.Line;
    Block.First := Block.Header;
    while (Block.First > 0) and Comment[Block.First - 1] and not Code[Block.First - 1] do
      Dec(Block.First);
    // Vor dem Kopf darf höchstens "class" stehen, hinter "end;" höchstens ein Kommentar.
    Rest := LowerCase(Trim(Copy(ALines[Block.Header], 1, Method.Body.Range.StartPos.Character)));
    if (Rest <> '') and (Rest <> 'class') then
      Block.Reason := TMethodStayReason.SharedLine;
    Rest := Trim(Copy(ALines[Block.Last], Method.Body.Range.EndPos.Character + 1, MaxInt));
    if StartsStr(';', Rest) then
      Rest := Trim(Copy(Rest, 2, MaxInt));
    if (Rest <> '') and not StartsStr('//', Rest) then
      Block.Reason := TMethodStayReason.SharedLine;
    if (RegionAt[Block.First] > 0) or (RegionAt[Block.Last + 1] <> RegionAt[Block.First]) then
      Block.Reason := TMethodStayReason.Region
    else if (CondAt[Block.First] > 0) or (CondAt[Block.Last + 1] <> CondAt[Block.First]) or
      (Method.Body.Condition <> '') then
      Block.Reason := TMethodStayReason.Conditional;
    Block.Fixed := Block.Reason <> TMethodStayReason.None;
    Result := Result + [Block];
  end;
  // Rümpfe, die sich Zeilen teilen, bleiben beide stehen.
  Ordered := ByLine(Result);
  for Index := 1 to High(Ordered) do
    if Ordered[Index].First <= Ordered[Index - 1].Last then
    begin
      Ordered[Index].First := Ordered[Index].Header;
      if Ordered[Index].First <= Ordered[Index - 1].Last then
      begin
        Ordered[Index].Fixed := True;
        Ordered[Index - 1].Fixed := True;
        if Ordered[Index].Reason = TMethodStayReason.None then
          Ordered[Index].Reason := TMethodStayReason.SharedLine;
        if Ordered[Index - 1].Reason = TMethodStayReason.None then
          Ordered[Index - 1].Reason := TMethodStayReason.SharedLine;
      end;
    end;
  Result := Ordered;
end;

function BlockLines(const ALines: TArray<string>; const ABlock: TBlock): TArray<string>;
begin
  Result := Copy(ALines, ABlock.First, ABlock.Last - ABlock.First + 1);
end;

/// <summary>Eine Änderung vom alten zum neuen Zeilenstand über den Bereich, in dem sie sich unterscheiden.
/// </summary>
function LinesEdit(const AOld, ANew: TArray<string>; const ALineBreak: string; out AEdit: TTextEdit): Boolean;
var
  Prefix, Suffix, Index: Integer;
  Text: string;
begin
  AEdit := Default(TTextEdit);
  Prefix := 0;
  while (Prefix < Length(AOld)) and (Prefix < Length(ANew)) and (AOld[Prefix] = ANew[Prefix]) do
    Inc(Prefix);
  if (Prefix = Length(AOld)) and (Prefix = Length(ANew)) then
    Exit(False);
  Suffix := 0;
  while (Suffix < Length(AOld) - Prefix) and (Suffix < Length(ANew) - Prefix) and
    (AOld[High(AOld) - Suffix] = ANew[High(ANew) - Suffix]) do
    Inc(Suffix);
  if Suffix > 0 then
  begin
    Text := '';
    for Index := Prefix to High(ANew) - Suffix do
      Text := Text + ANew[Index] + ALineBreak;
    AEdit := TTextEdit.Create(TTextRange.Create(Prefix, 0, Length(AOld) - Suffix, 0), Text);
  end
  else
    AEdit := TTextEdit.Create(TTextRange.Create(0, 0, High(AOld), Length(AOld[High(AOld)])),
      TTextLines.JoinLines(ANew, ALineBreak));
  Result := True;
end;

function MoveOf(const ABlock: TBlock; ADelta: Integer): TMethodMove;
begin
  Result := Default(TMethodMove);
  Result.TypeName := ABlock.TypeName;
  Result.Name := ABlock.Name;
  Result.Line := ABlock.Header;
  Result.Delta := ADelta;
  Result.Fixed := ABlock.Fixed;
  Result.Reason := ABlock.Reason;
end;

{ TMethodOrder }

class function TMethodOrder.PlacementName(APlacement: TMethodPlacement): string;
begin
  case APlacement of
    TMethodPlacement.Off:
      Result := 'off';
    TMethodPlacement.Alphabetical:
      Result := 'alphabetical';
  else
    Result := 'declaration';
  end;
end;

class function TMethodOrder.PlacementOf(const AName: string): TMethodPlacement;
begin
  if SameText(AName, 'off') then
    Result := TMethodPlacement.Off
  else if SameText(AName, 'alphabetical') then
    Result := TMethodPlacement.Alphabetical
  else
    Result := TMethodPlacement.Declaration;
end;

class function TMethodOrder.ReasonName(AReason: TMethodStayReason): string;
begin
  case AReason of
    TMethodStayReason.Region:
      Result := 'region';
    TMethodStayReason.Conditional:
      Result := 'ifdef';
    TMethodStayReason.SharedLine:
      Result := 'line';
  else
    Result := '';
  end;
end;

class function TMethodOrder.Arrange(ATree: TSyntaxTree; const AText: string;
  APlacement: TMethodPlacement): TMethodOrderResult;
var
  Lines, NewLines: TArray<string>;
  Blocks, Slots, Target: TBlocks;
  Block: TBlock;
  Line, Slot, Index: Integer;
  Edit: TTextEdit;
begin
  Result := Default(TMethodOrderResult);
  if (ATree = nil) or (APlacement = TMethodPlacement.Off) then
    Exit;
  Lines := TTextLines.SplitLines(AText);
  Blocks := CollectBlocks(ATree, AText, Lines);
  Slots := nil;
  for Block in Blocks do
    if not Block.Fixed then
      Slots := Slots + [Block];
  Target := Sorted(Slots, APlacement);
  // Jeder Platz bekommt den Rumpf, der in der Ordnung an seiner Stelle steht.
  NewLines := nil;
  Line := 0;
  Slot := 0;
  while Line < Length(Lines) do
    if (Slot < Length(Slots)) and (Line = Slots[Slot].First) then
    begin
      NewLines := NewLines + BlockLines(Lines, Target[Slot]);
      Line := Slots[Slot].Last + 1;
      Inc(Slot);
    end
    else
    begin
      NewLines := NewLines + [Lines[Line]];
      Inc(Line);
    end;
  if not LinesEdit(Lines, NewLines, TTextLines.LineBreakOf(AText), Edit) then
    Exit;
  Result.Edits := [Edit];
  for Index := 0 to High(Target) do
    if IndexOfBlock(Slots, Target[Index]) <> Index then
      Result.Moves := Result.Moves + [MoveOf(Target[Index], Index - IndexOfBlock(Slots, Target[Index]))];
  for Block in Blocks do
    if Block.Fixed then
      Result.Moves := Result.Moves + [MoveOf(Block, 0)];
end;

class function TMethodOrder.PlaceNew(ATree: TSyntaxTree; const AText, ABefore: string;
  APlacement: TMethodPlacement): TMethodOrderResult;
var
  Lines, NewLines, Insert: TArray<string>;
  Known: TDictionary<string, Boolean>;
  Blocks, Existing, News, Movable, Final, Group: TBlocks;
  Anchors: TArray<TAnchor>;
  Moved, Removed: TArray<Boolean>;
  InsertBefore, InsertAfter: TArray<TArray<string>>;
  Block, Item: TBlock;
  Fresh, InPlace: Boolean;
  Line, Index, Candidate, Position, Member, Best: Integer;
  Edit: TTextEdit;
begin
  Result := Default(TMethodOrderResult);
  if (ATree = nil) or (APlacement = TMethodPlacement.Off) then
    Exit;
  Lines := TTextLines.SplitLines(AText);
  Blocks := CollectBlocks(ATree, AText, Lines);
  Known := TDictionary<string, Boolean>.Create;
  try
    Insert := TTextLines.SplitLines(ABefore);
    for Line := 0 to High(Insert) do
      Known.AddOrSetValue(Trim(Insert[Line]), True);
    Existing := nil;
    News := nil;
    for Block in Blocks do
    begin
      if Block.Fixed then
        Continue;
      Fresh := not Known.ContainsKey(Trim(Lines[Block.Header])) and
        StartsText('end', Trim(Lines[Block.Last]));
      for Line := Block.Header + 1 to Block.Last do
        if Fresh and IsRoutineHeader(Lines[Line]) and Known.ContainsKey(Trim(Lines[Line])) then
          Fresh := False;
      Item := Block;
      Item.New := Fresh;
      if Fresh then
        News := News + [Item]
      else
        Existing := Existing + [Item];
    end;
  finally
    Known.Free;
  end;
  if (News = nil) or (Existing = nil) then
    Exit;
  News := Sorted(News, APlacement);
  // Ziel je neuem Rumpf.
  SetLength(Anchors, Length(News));
  for Index := 0 to High(News) do
  begin
    Anchors[Index].Block := -1;
    // Hinter den nächstliegenden davor desselben Typs, sonst vor den nächsten danach.
    Best := -1;
    for Candidate := 0 to High(Existing) do
      if (Existing[Candidate].TypeOrder = News[Index].TypeOrder) and
        Before(Existing[Candidate], News[Index], APlacement) and
        ((Best < 0) or Before(Existing[Best], Existing[Candidate], APlacement)) then
        Best := Candidate;
    if Best >= 0 then
    begin
      Anchors[Index].Block := Best;
      Anchors[Index].After := True;
      Continue;
    end;
    for Candidate := 0 to High(Existing) do
      if (Existing[Candidate].TypeOrder = News[Index].TypeOrder) and
        Before(News[Index], Existing[Candidate], APlacement) and
        ((Best < 0) or Before(Existing[Candidate], Existing[Best], APlacement)) then
        Best := Candidate;
    if Best >= 0 then
    begin
      Anchors[Index].Block := Best;
      Continue;
    end;
    // Typ ohne bisherige Rümpfe: hinter den letzten eines früheren, sonst vor den ersten eines späteren Typs.
    for Candidate := 0 to High(Existing) do
      if (Existing[Candidate].TypeOrder < News[Index].TypeOrder) and
        ((Best < 0) or Before(Existing[Best], Existing[Candidate], APlacement)) then
        Best := Candidate;
    if Best >= 0 then
    begin
      Anchors[Index].Block := Best;
      Anchors[Index].After := True;
      Continue;
    end;
    for Candidate := 0 to High(Existing) do
      if (Existing[Candidate].TypeOrder > News[Index].TypeOrder) and
        ((Best < 0) or Before(Existing[Candidate], Existing[Best], APlacement)) then
        Best := Candidate;
    Anchors[Index].Block := Best;
  end;
  // Gruppen je Ziel; eine Gruppe, die schon direkt am Ziel steht, bleibt.
  Movable := ByLine(Existing + News);
  SetLength(Moved, Length(News));
  for Index := 0 to High(News) do
  begin
    if (Anchors[Index].Block < 0) or Moved[Index] then
      Continue;
    Group := nil;
    for Member := Index to High(News) do
      if (Anchors[Member].Block = Anchors[Index].Block) and (Anchors[Member].After = Anchors[Index].After) then
        Group := Group + [News[Member]];
    Position := IndexOfBlock(Movable, Existing[Anchors[Index].Block]);
    InPlace := True;
    for Member := 0 to High(Group) do
    begin
      if Anchors[Index].After then
        Candidate := Position + 1 + Member
      else
        Candidate := Position - Length(Group) + Member;
      if (Candidate < 0) or (Candidate > High(Movable)) or (Movable[Candidate].Header <> Group[Member].Header) then
        InPlace := False;
    end;
    for Member := Index to High(News) do
      if (Anchors[Member].Block = Anchors[Index].Block) and (Anchors[Member].After = Anchors[Index].After) then
      begin
        Moved[Member] := not InPlace;
        if InPlace then
          Anchors[Member].Block := -1;
      end;
  end;
  // Neuen Text bauen: verschobene Rümpfe samt folgender Leerzeilen heraus, am Ziel mit Leerzeile hinein.
  SetLength(Removed, Length(Lines));
  SetLength(InsertBefore, Length(Lines));
  SetLength(InsertAfter, Length(Lines));
  for Index := 0 to High(News) do
  begin
    if not Moved[Index] then
      Continue;
    Line := News[Index].First;
    while Line <= News[Index].Last do
    begin
      Removed[Line] := True;
      Inc(Line);
    end;
    while (Line < High(Lines)) and (Trim(Lines[Line]) = '') do
    begin
      Removed[Line] := True;
      Inc(Line);
    end;
    Block := Existing[Anchors[Index].Block];
    if Anchors[Index].After then
      InsertAfter[Block.Last] := InsertAfter[Block.Last] + [''] + BlockLines(Lines, News[Index])
    else
      InsertBefore[Block.First] := InsertBefore[Block.First] + BlockLines(Lines, News[Index]) + [''];
  end;
  NewLines := nil;
  for Line := 0 to High(Lines) do
  begin
    NewLines := NewLines + InsertBefore[Line];
    if not Removed[Line] then
      NewLines := NewLines + [Lines[Line]];
    NewLines := NewLines + InsertAfter[Line];
  end;
  if not LinesEdit(Lines, NewLines, TTextLines.LineBreakOf(AText), Edit) then
    Exit;
  Result.Edits := [Edit];
  // Reihenfolge danach: die übrigen Rümpfe, die verschobenen an ihrem Ziel.
  Final := nil;
  for Block in Movable do
  begin
    Index := IndexOfBlock(News, Block);
    if (Index >= 0) and Moved[Index] then
      Continue;
    for Member := 0 to High(News) do
      if Moved[Member] and not Anchors[Member].After and (Existing[Anchors[Member].Block].Header = Block.Header) then
        Final := Final + [News[Member]];
    Final := Final + [Block];
    for Member := 0 to High(News) do
      if Moved[Member] and Anchors[Member].After and (Existing[Anchors[Member].Block].Header = Block.Header) then
        Final := Final + [News[Member]];
  end;
  for Index := 0 to High(Final) do
    if Final[Index].New and Moved[IndexOfBlock(News, Final[Index])] then
      Result.Moves := Result.Moves + [MoveOf(Final[Index], Index - IndexOfBlock(Movable, Final[Index]))];
end;

end.
