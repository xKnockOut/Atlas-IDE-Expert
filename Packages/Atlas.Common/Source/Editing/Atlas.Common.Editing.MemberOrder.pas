unit Atlas.Common.Editing.MemberOrder;

// Klassenmitglieder ordnen (#89): Sichtbarkeitsabschnitte und darin die
// Mitglieder nach der Reihenfolge aus "memberOrder". Kommentare, Attribute und
// Leerzeilen über einem Mitglied wandern mit ihm. Nicht umsortiert wird, was
// die Bedeutung ändern könnte:
//   - Records, packed-Klassen und Dateien mit {$A-}/{$ALIGN OFF} gar nicht,
//   - Abschnitte mit verschachtelten Typen, Konstanten oder class var
//     (dann auch keine Abschnitte verschieben) und mit {$IF…}-Blöcken,
//   - published-Abschnitte nur mit sortPublished,
//   - Felder in mehreren Abschnitten: Abschnitte nur mit sortFields verschieben,
//     sonst änderte sich das Speicherlayout.
// Ein {$IF…} quer zu Abschnitten verhindert die Aktion ganz. Die Mitglieder
// eines Abschnitts behalten innerhalb ihrer Art die Reihenfolge, so dass
// zweimal Anwenden dasselbe ergibt wie einmal.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Configuration.Contract;

type
  TMemberOrder = class
  public
    /// <summary>Ordnet die Klasse um Zeile ALine; False, wenn es nichts zu tun gibt oder sie nicht sicher sortierbar
    /// ist.</summary>
    class function Sort(const AText: string; ATree: TSyntaxTree; ALine: Integer;
      const ASettings: TMemberOrderSettings; out AEdit: TRuleEdit): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Text.Lines;

type
  TItem = record
    First, Last: Integer;
    Rank, Position: Integer;
  end;

  TSection = record
    Keyword: string;
    /// <summary>Zeile des Schlüsselworts; -1 beim Abschnitt vor dem ersten Schlüsselwort.</summary>
    Header: Integer;
    First, Last: Integer;
    Nested, Directives, HasFields: Boolean;
    Position: Integer;
  end;

const
  Visibilities: array[0..6] of string = ('strict private', 'private', 'strict protected', 'protected', 'public',
    'published', 'automated');
  MemberKinds = [TSyntaxKind.Field, TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl, TSyntaxKind.PropertyDecl];
  IgnoredKinds = [TSyntaxKind.Visibility, TSyntaxKind.Attribute, TSyntaxKind.TypeReference,
    TSyntaxKind.GenericParams];

function SplitText(const AText: string): TArray<string>;
var
  Index, Start: Integer;
begin
  Result := nil;
  Start := 1;
  for Index := 1 to Length(AText) + 1 do
    if (Index > Length(AText)) or (AText[Index] = #10) then
    begin
      Result := Result + [Copy(AText, Start, Index - Start)];
      Start := Index + 1;
    end;
  for Index := 0 to High(Result) do
    if EndsStr(#13, Result[Index]) then
      Result[Index] := Copy(Result[Index], 1, Length(Result[Index]) - 1);
end;

function NormalizedWords(const ALine: string): string;
begin
  Result := LowerCase(Trim(ALine));
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
end;

function FindClass(ANode: TSyntaxNode; ALine: Integer): TSyntaxNode;
var
  Index: Integer;
begin
  Result := nil;
  if (ANode.StartPos.Line > ALine) or (ANode.EndPos.Line < ALine) then
    Exit;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindClass(ANode[Index], ALine);
    if Result <> nil then
      Exit;
  end;
  if ANode.Kind = TSyntaxKind.ClassType then
    Result := ANode;
end;

/// <summary>-1 öffnet, +1 schließt, 0 sonst; AOther bei {$ELSE}.</summary>
function DirectiveStep(const ALine: string; out AOther: Boolean): Integer;
var
  Text: string;
begin
  Text := UpperCase(TrimLeft(ALine));
  AOther := StartsStr('{$ELSE', Text);
  if StartsStr('{$IFDEF', Text) or StartsStr('{$IFNDEF', Text) or StartsStr('{$IFOPT', Text) or
    StartsStr('{$IF ', Text) or StartsStr('{$IF(', Text) then
    Result := -1
  else if StartsStr('{$ENDIF', Text) or StartsStr('{$IFEND', Text) then
    Result := 1
  else
    Result := 0;
end;

function KindRank(const ALine: string; ANodeKind: TSyntaxKind; const AOrder: TArray<string>): Integer;
var
  Text, Kind: string;
begin
  Text := NormalizedWords(ALine);
  if StartsStr('class ', Text) then
    Text := Copy(Text, 7, MaxInt);
  if StartsStr('constructor', Text) then
    Kind := 'constructor'
  else if StartsStr('destructor', Text) then
    Kind := 'destructor'
  else if StartsStr('property', Text) then
    Kind := 'property'
  else if ANodeKind = TSyntaxKind.Field then
    Kind := 'field'
  else
    Kind := 'method';
  Result := IndexText(Kind, AOrder);
  if Result < 0 then
    Result := Length(AOrder);
end;

procedure SortItems(var AItems: TArray<TItem>);
var
  I, J: Integer;
  Item: TItem;
begin
  // Einfügesortierung: stabil, die Listen sind kurz.
  for I := 1 to High(AItems) do
  begin
    Item := AItems[I];
    J := I - 1;
    while (J >= 0) and ((AItems[J].Rank > Item.Rank) or
      ((AItems[J].Rank = Item.Rank) and (AItems[J].Position > Item.Position))) do
    begin
      AItems[J + 1] := AItems[J];
      Dec(J);
    end;
    AItems[J + 1] := Item;
  end;
end;

procedure SortSections(var ASections: TArray<TSection>);
var
  I, J: Integer;
  Section: TSection;
begin
  for I := 1 to High(ASections) do
  begin
    Section := ASections[I];
    J := I - 1;
    while (J >= 0) and (ASections[J].Position > Section.Position) do
    begin
      ASections[J + 1] := ASections[J];
      Dec(J);
    end;
    ASections[J + 1] := Section;
  end;
end;

class function TMemberOrder.Sort(const AText: string; ATree: TSyntaxTree; ALine: Integer;
  const ASettings: TMemberOrderSettings; out AEdit: TRuleEdit): Boolean;
var
  Lines, Output: TArray<string>;
  ClassNode, Child: TSyntaxNode;
  Header, Stop, Line, Index, Depth, Step, SectionIndex, Next, FieldSections, Rank: Integer;
  Sections: TArray<TSection>;
  Section: TSection;
  Items: TArray<TItem>;
  Item: TItem;
  Text, LB, Words: string;
  Other, MayMoveSections, IsVisibility: Boolean;
  Upper: string;
begin
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Upper := UpperCase(AText);
  if ContainsStr(Upper, '{$A-}') or ContainsStr(Upper, '{$A1}') or ContainsStr(Upper, '{$ALIGN OFF}') or
    ContainsStr(Upper, '{$ALIGN 1}') then
    Exit;
  ClassNode := FindClass(ATree.Root, ALine);
  if ClassNode = nil then
    Exit;
  Lines := SplitText(AText);
  Header := ClassNode.StartPos.Line;
  Stop := ClassNode.EndPos.Line;
  if (Stop - Header < 2) or (Stop > High(Lines)) or ContainsText(Lines[Header], 'packed') or
    not StartsText('end', TrimLeft(Lines[Stop])) then
    Exit;
  // Abschnitte über die Schlüsselwortzeilen.
  Sections := nil;
  Section := Default(TSection);
  Section.Header := -1;
  Section.First := Header + 1;
  for Line := Header + 1 to Stop - 1 do
  begin
    Words := NormalizedWords(Lines[Line]);
    IsVisibility := IndexText(Words, Visibilities) >= 0;
    if IsVisibility then
    begin
      Section.Last := Line - 1;
      Sections := Sections + [Section];
      Section := Default(TSection);
      Section.Keyword := Words;
      Section.Header := Line;
      Section.First := Line + 1;
    end
    else if MatchText(Words, ['type', 'const', 'var', 'class var', 'threadvar', 'resourcestring']) or
      StartsText('class var ', Words) then
      Section.Nested := True;
  end;
  Section.Last := Stop - 1;
  Sections := Sections + [Section];
  // {$IF…}: innerhalb eines Abschnitts nur Einheit, quer dazu keine Aktion.
  for SectionIndex := 0 to High(Sections) do
  begin
    Depth := 0;
    for Line := Sections[SectionIndex].First to Sections[SectionIndex].Last do
    begin
      Step := DirectiveStep(Lines[Line], Other);
      if (Step <> 0) or Other then
        Sections[SectionIndex].Directives := True;
      Inc(Depth, -Step);
      if Depth < 0 then
        Exit;
    end;
    if Depth <> 0 then
      Exit;
  end;
  // Mitglieder den Abschnitten zuordnen; Unbekanntes gilt als verschachtelte Deklaration.
  for Index := 0 to ClassNode.ChildCount - 1 do
  begin
    Child := ClassNode[Index];
    if (Child.Kind in IgnoredKinds) or (Child.StartPos.Line <= Header) then
      Continue;
    for SectionIndex := 0 to High(Sections) do
      if (Child.StartPos.Line >= Sections[SectionIndex].First) and
        (Child.StartPos.Line <= Sections[SectionIndex].Last) then
      begin
        if not (Child.Kind in MemberKinds) then
          Sections[SectionIndex].Nested := True
        else if Child.Kind = TSyntaxKind.Field then
          Sections[SectionIndex].HasFields := True;
        // Mitglied über mehrere Abschnitte: nicht anfassen.
        if Child.EndPos.Line > Sections[SectionIndex].Last then
          Exit;
      end;
  end;
  MayMoveSections := True;
  FieldSections := 0;
  for Section in Sections do
  begin
    if Section.Nested then
      MayMoveSections := False;
    if Section.HasFields then
      Inc(FieldSections);
  end;
  if (FieldSections > 1) and not ASettings.SortFields then
    MayMoveSections := False;
  for SectionIndex := 0 to High(Sections) do
  begin
    Rank := IndexText(Sections[SectionIndex].Keyword, ASettings.Sections);
    if Rank < 0 then
      Rank := Length(ASettings.Sections);
    // Der Abschnitt ohne Schlüsselwort bleibt vorn.
    if Sections[SectionIndex].Header < 0 then
      Sections[SectionIndex].Position := -1
    else if MayMoveSections then
      Sections[SectionIndex].Position := Rank * 1000 + SectionIndex
    else
      Sections[SectionIndex].Position := SectionIndex;
  end;
  SortSections(Sections);
  Output := nil;
  for Section in Sections do
  begin
    if Section.Header >= 0 then
      Output := Output + [Lines[Section.Header]];
    if Section.Nested or Section.Directives or (Section.Header < 0) or
      ((Section.Keyword = 'published') and not ASettings.SortPublished) then
    begin
      for Line := Section.First to Section.Last do
        Output := Output + [Lines[Line]];
      Continue;
    end;
    // Mitglieder samt der Zeilen darüber; was nach dem letzten kommt, bleibt am Ende.
    Items := nil;
    Next := Section.First;
    for Index := 0 to ClassNode.ChildCount - 1 do
    begin
      Child := ClassNode[Index];
      if not (Child.Kind in MemberKinds) or (Child.StartPos.Line < Section.First) or
        (Child.StartPos.Line > Section.Last) then
        Continue;
      // Mehrere Knoten in einer Zeile (A, B: Integer) gehören zusammen.
      if (Length(Items) > 0) and (Child.StartPos.Line <= Items[High(Items)].Last) then
      begin
        if Child.EndPos.Line > Items[High(Items)].Last then
          Items[High(Items)].Last := Child.EndPos.Line;
        Continue;
      end;
      Item.First := Next;
      Item.Last := Child.EndPos.Line;
      Item.Rank := KindRank(Lines[Child.StartPos.Line], Child.Kind, ASettings.Members);
      Item.Position := Length(Items);
      Items := Items + [Item];
      Next := Item.Last + 1;
    end;
    SortItems(Items);
    for Item in Items do
      for Line := Item.First to Item.Last do
        Output := Output + [Lines[Line]];
    for Line := Next to Section.Last do
      Output := Output + [Lines[Line]];
  end;
  // Unverändert: keine Aktion.
  Index := 0;
  Other := False;
  for Line := Header + 1 to Stop - 1 do
  begin
    if Lines[Line] <> Output[Index] then
      Other := True;
    Inc(Index);
  end;
  if not Other then
    Exit;
  LB := TTextLines.LineBreakOf(AText);
  Text := '';
  for Line := 0 to High(Output) do
    Text := Text + Output[Line] + LB;
  AEdit := TRuleEdit.Create(TTextRange.Create(Header + 1, 0, Stop, 0), Text);
  Result := True;
end;

end.
