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
    /// <summary>Zeile des Kopfs danach; bei stehen bleibenden Rümpfen -1.</summary>
    NewLine: Integer;
    /// <summary>Zeilen vom Kopf bis zum abschließenden end.</summary>
    Size: Integer;
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
  begin
    Exit(A.TypeOrder < B.TypeOrder);
  end;
  if APlacement = TMethodPlacement.Alphabetical then
  begin
    Compared := CompareText(A.Name, B.Name);
    if Compared <> 0 then
    begin
      Exit(Compared < 0);
    end;
  end;
  if A.DeclarationOrder <> B.DeclarationOrder then
  begin
    Exit(A.DeclarationOrder < B.DeclarationOrder);
  end;
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
  begin
    if ABlocks[Index].Header = ABlock.Header then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function IsRoutineHeader(const ALine: string): Boolean;
var
  Word: string;
  Lower: string;
begin
  Lower := LowerCase(Trim(ALine));
  for Word in RoutineWords do
  begin
    if StartsStr(Word, Lower) then
    begin
      Exit(True);
    end;
  end;
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
    begin
      Continue;
    end;
    for Line := Token.StartPos.Line to Token.EndPos.Line do
    begin
      if Token.Kind = TPascalTokenKind.Comment then
      begin
        Comment[Line] := True;
      end
      else
      begin
        Code[Line] := True;
      end;
    end;
    if Token.Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    Directive := TPascalLexer.DirectiveName(Token.Text);
    if (Directive = 'IF') or (Directive = 'IFDEF') or (Directive = 'IFNDEF') or (Directive = 'IFOPT') then
    begin
      Inc(CondDelta[Token.StartPos.Line]);
    end
    else if (Directive = 'ENDIF') or (Directive = 'IFEND') then
    begin
      Dec(CondDelta[Token.StartPos.Line]);
    end
    else if Directive = 'REGION' then
    begin
      Inc(RegionDelta[Token.StartPos.Line]);
    end
    else if Directive = 'ENDREGION' then
    begin
      Dec(RegionDelta[Token.StartPos.Line]);
    end;
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
    begin
      Continue;
    end;
    Block := Default(TBlock);
    Block.TypeName := Method.TypeName;
    Block.Name := Method.Declaration.Name;
    Block.TypeOrder := Method.TypeOrder;
    Block.DeclarationOrder := Method.DeclarationOrder;
    Block.Header := Method.Body.Range.StartPos.Line;
    Block.Last := Method.Body.Range.EndPos.Line;
    Block.First := Block.Header;
    while (Block.First > 0) and Comment[Block.First - 1] and not Code[Block.First - 1] do
    begin
      Dec(Block.First);
    end;
    // Vor dem Kopf darf höchstens "class" stehen, hinter "end;" höchstens ein Kommentar.
    Rest := LowerCase(Trim(Copy(ALines[Block.Header], 1, Method.Body.Range.StartPos.Character)));
    if (Rest <> '') and (Rest <> 'class') then
    begin
      Block.Reason := TMethodStayReason.SharedLine;
    end;
    Rest := Trim(Copy(ALines[Block.Last], Method.Body.Range.EndPos.Character + 1, MaxInt));
    if StartsStr(';', Rest) then
    begin
      Rest := Trim(Copy(Rest, 2, MaxInt));
    end;
    if (Rest <> '') and not StartsStr('//', Rest) then
    begin
      Block.Reason := TMethodStayReason.SharedLine;
    end;
    if (RegionAt[Block.First] > 0) or (RegionAt[Block.Last + 1] <> RegionAt[Block.First]) then
    begin
      Block.Reason := TMethodStayReason.Region;
    end
    else if (CondAt[Block.First] > 0) or (CondAt[Block.Last + 1] <> CondAt[Block.First]) or
      (Method.Body.Condition <> '') then
    begin
      Block.Reason := TMethodStayReason.Conditional;
    end;
    Block.Fixed := Block.Reason <> TMethodStayReason.None;
    Result := Result + [Block];
  end;
  // Rümpfe, die sich Zeilen teilen, bleiben beide stehen.
  Ordered := ByLine(Result);
  for Index := 1 to High(Ordered) do
  begin
    if Ordered[Index].First <= Ordered[Index - 1].Last then
    begin
      Ordered[Index].First := Ordered[Index].Header;
      if Ordered[Index].First <= Ordered[Index - 1].Last then
      begin
        Ordered[Index].Fixed := True;
        Ordered[Index - 1].Fixed := True;
        if Ordered[Index].Reason = TMethodStayReason.None then
        begin
          Ordered[Index].Reason := TMethodStayReason.SharedLine;
        end;
        if Ordered[Index - 1].Reason = TMethodStayReason.None then
        begin
          Ordered[Index - 1].Reason := TMethodStayReason.SharedLine;
        end;
      end;
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
  begin
    Inc(Prefix);
  end;
  if (Prefix = Length(AOld)) and (Prefix = Length(ANew)) then
  begin
    Exit(False);
  end;
  Suffix := 0;
  while (Suffix < Length(AOld) - Prefix) and (Suffix < Length(ANew) - Prefix) and
    (AOld[High(AOld) - Suffix] = ANew[High(ANew) - Suffix]) do
  begin
    Inc(Suffix);
  end;
  if Suffix > 0 then
  begin
    Text := '';
    for Index := Prefix to High(ANew) - Suffix do
    begin
      Text := Text + ANew[Index] + ALineBreak;
    end;
    AEdit := TTextEdit.Create(TTextRange.Create(Prefix, 0, Length(AOld) - Suffix, 0), Text);
  end
  else
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(0, 0, High(AOld), Length(AOld[High(AOld)])),
      TTextLines.JoinLines(ANew, ALineBreak));
  end;
  Result := True;
end;

function MoveOf(const ABlock: TBlock; ADelta, ANewLine: Integer): TMethodMove;
begin
  Result := Default(TMethodMove);
  Result.TypeName := ABlock.TypeName;
  Result.Name := ABlock.Name;
  Result.Line := ABlock.Header;
  Result.NewLine := ANewLine;
  Result.Size := ABlock.Last - ABlock.Header + 1;
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
  begin
    Result := TMethodPlacement.Off;
  end
  else if SameText(AName, 'alphabetical') then
  begin
    Result := TMethodPlacement.Alphabetical;
  end
  else
  begin
    Result := TMethodPlacement.Declaration;
  end;
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
  TargetLines: TArray<Integer>;
  Block: TBlock;
  Line, Slot, Index: Integer;
  Edit: TTextEdit;
begin
  Result := Default(TMethodOrderResult);
  if (ATree = nil) or (APlacement = TMethodPlacement.Off) then
  begin
    Exit;
  end;
  Lines := TTextLines.SplitLines(AText);
  Blocks := CollectBlocks(ATree, AText, Lines);
  Slots := nil;
  for Block in Blocks do
  begin
    if not Block.Fixed then
    begin
      Slots := Slots + [Block];
    end;
  end;
  Target := Sorted(Slots, APlacement);
  // Jeder Platz bekommt den Rumpf, der in der Ordnung an seiner Stelle steht.
  NewLines := nil;
  SetLength(TargetLines, Length(Target));
  Line := 0;
  Slot := 0;
  while Line < Length(Lines) do
  begin
    if (Slot < Length(Slots)) and (Line = Slots[Slot].First) then
    begin
      TargetLines[Slot] := Length(NewLines) + Target[Slot].Header - Target[Slot].First;
      NewLines := NewLines + BlockLines(Lines, Target[Slot]);
      Line := Slots[Slot].Last + 1;
      Inc(Slot);
    end
    else
    begin
      NewLines := NewLines + [Lines[Line]];
      Inc(Line);
    end;
  end;
  if not LinesEdit(Lines, NewLines, TTextLines.LineBreakOf(AText), Edit) then
  begin
    Exit;
  end;
  Result.Edits := [Edit];
  for Index := 0 to High(Target) do
  begin
    if IndexOfBlock(Slots, Target[Index]) <> Index then
    begin
      Result.Moves := Result.Moves + [MoveOf(Target[Index], Index - IndexOfBlock(Slots, Target[Index]),
        TargetLines[Index])];
    end;
  end;
  for Block in Blocks do
  begin
    if Block.Fixed then
    begin
      Result.Moves := Result.Moves + [MoveOf(Block, 0, -1)];
    end;
  end;
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
  begin
    Exit;
  end;
  Lines := TTextLines.SplitLines(AText);
  Blocks := CollectBlocks(ATree, AText, Lines);
  Known := TDictionary<string, Boolean>.Create;
  try
    Insert := TTextLines.SplitLines(ABefore);
    for Line := 0 to High(Insert) do
    begin
      Known.AddOrSetValue(Trim(Insert[Line]), True);
    end;
    Existing := nil;
    News := nil;
    for Block in Blocks do
    begin
      if Block.Fixed then
      begin
        Continue;
      end;
      Fresh := not Known.ContainsKey(Trim(Lines[Block.Header])) and
        StartsText('end', Trim(Lines[Block.Last]));
      for Line := Block.Header + 1 to Block.Last do
      begin
        if Fresh and IsRoutineHeader(Lines[Line]) and Known.ContainsKey(Trim(Lines[Line])) then
        begin
          Fresh := False;
        end;
      end;
      Item := Block;
      Item.New := Fresh;
      if Fresh then
      begin
        News := News + [Item];
      end
      else
      begin
        Existing := Existing + [Item];
      end;
    end;
  finally
    Known.Free;
  end;
  if (News = nil) or (Existing = nil) then
  begin
    Exit;
  end;
  News := Sorted(News, APlacement);
  // Ziel je neuem Rumpf.
  SetLength(Anchors, Length(News));
  for Index := 0 to High(News) do
  begin
    Anchors[Index].Block := -1;
    // Hinter den nächstliegenden davor desselben Typs, sonst vor den nächsten danach.
    Best := -1;
    for Candidate := 0 to High(Existing) do
    begin
      if (Existing[Candidate].TypeOrder = News[Index].TypeOrder) and
        Before(Existing[Candidate], News[Index], APlacement) and
        ((Best < 0) or Before(Existing[Best], Existing[Candidate], APlacement)) then
      begin
        Best := Candidate;
      end;
    end;
    if Best >= 0 then
    begin
      Anchors[Index].Block := Best;
      Anchors[Index].After := True;
      Continue;
    end;
    for Candidate := 0 to High(Existing) do
    begin
      if (Existing[Candidate].TypeOrder = News[Index].TypeOrder) and
        Before(News[Index], Existing[Candidate], APlacement) and
        ((Best < 0) or Before(Existing[Candidate], Existing[Best], APlacement)) then
      begin
        Best := Candidate;
      end;
    end;
    if Best >= 0 then
    begin
      Anchors[Index].Block := Best;
      Continue;
    end;
    // Typ ohne bisherige Rümpfe: hinter den letzten eines früheren, sonst vor den ersten eines späteren Typs.
    for Candidate := 0 to High(Existing) do
    begin
      if (Existing[Candidate].TypeOrder < News[Index].TypeOrder) and
        ((Best < 0) or Before(Existing[Best], Existing[Candidate], APlacement)) then
      begin
        Best := Candidate;
      end;
    end;
    if Best >= 0 then
    begin
      Anchors[Index].Block := Best;
      Anchors[Index].After := True;
      Continue;
    end;
    for Candidate := 0 to High(Existing) do
    begin
      if (Existing[Candidate].TypeOrder > News[Index].TypeOrder) and
        ((Best < 0) or Before(Existing[Candidate], Existing[Best], APlacement)) then
      begin
        Best := Candidate;
      end;
    end;
    Anchors[Index].Block := Best;
  end;
  // Gruppen je Ziel; eine Gruppe, die schon direkt am Ziel steht, bleibt.
  Movable := ByLine(Existing + News);
  SetLength(Moved, Length(News));
  for Index := 0 to High(News) do
  begin
    if (Anchors[Index].Block < 0) or Moved[Index] then
    begin
      Continue;
    end;
    Group := nil;
    for Member := Index to High(News) do
    begin
      if (Anchors[Member].Block = Anchors[Index].Block) and (Anchors[Member].After = Anchors[Index].After) then
      begin
        Group := Group + [News[Member]];
      end;
    end;
    Position := IndexOfBlock(Movable, Existing[Anchors[Index].Block]);
    InPlace := True;
    for Member := 0 to High(Group) do
    begin
      if Anchors[Index].After then
      begin
        Candidate := Position + 1 + Member;
      end
      else
      begin
        Candidate := Position - Length(Group) + Member;
      end;
      if (Candidate < 0) or (Candidate > High(Movable)) or (Movable[Candidate].Header <> Group[Member].Header) then
      begin
        InPlace := False;
      end;
    end;
    for Member := Index to High(News) do
    begin
      if (Anchors[Member].Block = Anchors[Index].Block) and (Anchors[Member].After = Anchors[Index].After) then
      begin
        Moved[Member] := not InPlace;
        if InPlace then
        begin
          Anchors[Member].Block := -1;
        end;
      end;
    end;
  end;
  // Neuen Text bauen: verschobene Rümpfe samt folgender Leerzeilen heraus, am Ziel mit Leerzeile hinein.
  SetLength(Removed, Length(Lines));
  SetLength(InsertBefore, Length(Lines));
  SetLength(InsertAfter, Length(Lines));
  for Index := 0 to High(News) do
  begin
    if not Moved[Index] then
    begin
      Continue;
    end;
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
    begin
      InsertAfter[Block.Last] := InsertAfter[Block.Last] + [''] + BlockLines(Lines, News[Index]);
    end
    else
    begin
      InsertBefore[Block.First] := InsertBefore[Block.First] + BlockLines(Lines, News[Index]) + [''];
    end;
  end;
  NewLines := nil;
  for Line := 0 to High(Lines) do
  begin
    NewLines := NewLines + InsertBefore[Line];
    if not Removed[Line] then
    begin
      NewLines := NewLines + [Lines[Line]];
    end;
    NewLines := NewLines + InsertAfter[Line];
  end;
  if not LinesEdit(Lines, NewLines, TTextLines.LineBreakOf(AText), Edit) then
  begin
    Exit;
  end;
  Result.Edits := [Edit];
  // Reihenfolge danach: die übrigen Rümpfe, die verschobenen an ihrem Ziel.
  Final := nil;
  for Block in Movable do
  begin
    Index := IndexOfBlock(News, Block);
    if (Index >= 0) and Moved[Index] then
    begin
      Continue;
    end;
    for Member := 0 to High(News) do
    begin
      if Moved[Member] and not Anchors[Member].After and (Existing[Anchors[Member].Block].Header = Block.Header) then
      begin
        Final := Final + [News[Member]];
      end;
    end;
    Final := Final + [Block];
    for Member := 0 to High(News) do
    begin
      if Moved[Member] and Anchors[Member].After and (Existing[Anchors[Member].Block].Header = Block.Header) then
      begin
        Final := Final + [News[Member]];
      end;
    end;
  end;
  for Index := 0 to High(Final) do
  begin
    if Final[Index].New and Moved[IndexOfBlock(News, Final[Index])] then
    begin
      // Der Kopf eines neuen Rumpfs kam vorher nicht vor: seine erste Fundstelle ist die neue Zeile.
      Line := 0;
      while (Line < High(NewLines)) and (NewLines[Line] <> Lines[Final[Index].Header]) do
      begin
        Inc(Line);
      end;
      Result.Moves := Result.Moves + [MoveOf(Final[Index], Index - IndexOfBlock(Movable, Final[Index]), Line)];
    end;
  end;
end;

end.
