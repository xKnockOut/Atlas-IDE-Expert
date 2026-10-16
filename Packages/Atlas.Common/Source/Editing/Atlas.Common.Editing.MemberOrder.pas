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
  System.Generics.Collections,
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

/// <summary>{$A-}, {$A1}, {$ALIGN OFF} oder {$ALIGN 1} irgendwo in der Datei.</summary>
function HasPackedAlignment(const AText: string): Boolean;
var
  Upper: string;
begin
  Upper := UpperCase(AText);
  Result := ContainsStr(Upper, '{$A-}') or ContainsStr(Upper, '{$A1}') or ContainsStr(Upper, '{$ALIGN OFF}') or
    ContainsStr(Upper, '{$ALIGN 1}');
end;

/// <summary>Abschnitte über die Schlüsselwortzeilen zwischen AHeader und AStop.</summary>
function CollectSections(const ALines: TArray<string>; AHeader, AStop: Integer): TArray<TSection>;
var
  Sections: TList<TSection>;
  Section: TSection;
  Line: Integer;
  Words: string;
begin
  Result := nil;
  Sections := TList<TSection>.Create;
  try
    Section := Default(TSection);
    Section.Header := -1;
    Section.First := AHeader + 1;
    for Line := AHeader + 1 to AStop - 1 do
    begin
      Words := NormalizedWords(ALines[Line]);
      if IndexText(Words, Visibilities) >= 0 then
      begin
        Section.Last := Line - 1;
        Sections.Add(Section);
        Section := Default(TSection);
        Section.Keyword := Words;
        Section.Header := Line;
        Section.First := Line + 1;
      end
      else if MatchText(Words, ['type', 'const', 'var', 'class var', 'threadvar', 'resourcestring']) or
        StartsText('class var ', Words) then
        Section.Nested := True;
    end;
    Section.Last := AStop - 1;
    Sections.Add(Section);
    Result := Sections.ToArray;
  finally
    Sections.Free;
  end;
end;

/// <summary>Markiert Abschnitte mit {$IF…}; False, wenn ein Block quer zu Abschnitten liegt.</summary>
function MarkDirectives(var ASections: TArray<TSection>; const ALines: TArray<string>): Boolean;
var
  SectionIndex, Line, Depth, Step: Integer;
  Other: Boolean;
begin
  Result := False;
  for SectionIndex := 0 to High(ASections) do
  begin
    Depth := 0;
    for Line := ASections[SectionIndex].First to ASections[SectionIndex].Last do
    begin
      Step := DirectiveStep(ALines[Line], Other);
      if (Step <> 0) or Other then
        ASections[SectionIndex].Directives := True;
      Inc(Depth, -Step);
      if Depth < 0 then
        Exit;
    end;
    if Depth <> 0 then
      Exit;
  end;
  Result := True;
end;

/// <summary>Ordnet die Kindknoten den Abschnitten zu (Nested, HasFields); Unbekanntes gilt als verschachtelte
/// Deklaration. False, wenn ein Mitglied über mehrere Abschnitte reicht.</summary>
function ClassifyMembers(var ASections: TArray<TSection>; AClass: TSyntaxNode; AHeader: Integer): Boolean;
var
  Index, SectionIndex: Integer;
  Child: TSyntaxNode;
begin
  Result := False;
  for Index := 0 to AClass.ChildCount - 1 do
  begin
    Child := AClass[Index];
    if (Child.Kind in IgnoredKinds) or (Child.StartPos.Line <= AHeader) then
      Continue;
    for SectionIndex := 0 to High(ASections) do
      if (Child.StartPos.Line >= ASections[SectionIndex].First) and
        (Child.StartPos.Line <= ASections[SectionIndex].Last) then
      begin
        if not (Child.Kind in MemberKinds) then
          ASections[SectionIndex].Nested := True
        else if Child.Kind = TSyntaxKind.Field then
          ASections[SectionIndex].HasFields := True;
        if Child.EndPos.Line > ASections[SectionIndex].Last then
          Exit;
      end;
  end;
  Result := True;
end;

/// <summary>Dürfen Abschnitte verschoben werden? Nein bei verschachtelten Deklarationen oder bei Feldern in
/// mehreren Abschnitten ohne sortFields (sonst änderte sich das Speicherlayout).</summary>
function CanMoveSections(const ASections: TArray<TSection>; const ASettings: TMemberOrderSettings): Boolean;
var
  Section: TSection;
  FieldSections: Integer;
begin
  Result := True;
  FieldSections := 0;
  for Section in ASections do
  begin
    if Section.Nested then
      Result := False;
    if Section.HasFields then
      Inc(FieldSections);
  end;
  if (FieldSections > 1) and not ASettings.SortFields then
    Result := False;
end;

/// <summary>Position je Abschnitt setzen und stabil sortieren; der Abschnitt ohne Schlüsselwort bleibt vorn.</summary>
procedure OrderSections(var ASections: TArray<TSection>; const ASettings: TMemberOrderSettings);
var
  SectionIndex, Rank: Integer;
  MayMove: Boolean;
begin
  MayMove := CanMoveSections(ASections, ASettings);
  for SectionIndex := 0 to High(ASections) do
  begin
    Rank := IndexText(ASections[SectionIndex].Keyword, ASettings.Sections);
    if Rank < 0 then
      Rank := Length(ASettings.Sections);
    if ASections[SectionIndex].Header < 0 then
      ASections[SectionIndex].Position := -1
    else if MayMove then
      ASections[SectionIndex].Position := Rank * 1000 + SectionIndex
    else
      ASections[SectionIndex].Position := SectionIndex;
  end;
  SortSections(ASections);
end;

/// <summary>Werden die Mitglieder dieses Abschnitts umsortiert?</summary>
function SectionSortable(const ASection: TSection; const ASettings: TMemberOrderSettings): Boolean;
begin
  Result := not ASection.Nested and not ASection.Directives and (ASection.Header >= 0) and
    ((ASection.Keyword <> 'published') or ASettings.SortPublished);
end;

/// <summary>Mitglieder des Abschnitts samt der Zeilen darüber; ANext = erste Zeile nach dem letzten.</summary>
function CollectItems(const ASection: TSection; AClass: TSyntaxNode; const ALines: TArray<string>;
  const AOrder: TArray<string>; out ANext: Integer): TArray<TItem>;
var
  Items: TList<TItem>;
  Item: TItem;
  Child: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  ANext := ASection.First;
  Items := TList<TItem>.Create;
  try
    for Index := 0 to AClass.ChildCount - 1 do
    begin
      Child := AClass[Index];
      if not (Child.Kind in MemberKinds) or (Child.StartPos.Line < ASection.First) or
        (Child.StartPos.Line > ASection.Last) then
        Continue;
      // Mehrere Knoten in einer Zeile (A, B: Integer) gehören zusammen.
      if (Items.Count > 0) and (Child.StartPos.Line <= Items[Items.Count - 1].Last) then
      begin
        if Child.EndPos.Line > Items[Items.Count - 1].Last then
        begin
          Item := Items[Items.Count - 1];
          Item.Last := Child.EndPos.Line;
          Items[Items.Count - 1] := Item;
          ANext := Item.Last + 1;
        end;
        Continue;
      end;
      Item := Default(TItem);
      Item.First := ANext;
      Item.Last := Child.EndPos.Line;
      Item.Rank := KindRank(ALines[Child.StartPos.Line], Child.Kind, AOrder);
      Item.Position := Items.Count;
      Items.Add(Item);
      ANext := Item.Last + 1;
    end;
    Result := Items.ToArray;
  finally
    Items.Free;
  end;
end;

/// <summary>Neue Zeilen zwischen Kopf und end.</summary>
procedure EmitSections(const ALines: TArray<string>; const ASections: TArray<TSection>; AClass: TSyntaxNode;
  const ASettings: TMemberOrderSettings; AOutput: TList<string>);
var
  Section: TSection;
  Items: TArray<TItem>;
  Item: TItem;
  Line, Next: Integer;
begin
  for Section in ASections do
  begin
    if Section.Header >= 0 then
      AOutput.Add(ALines[Section.Header]);
    if not SectionSortable(Section, ASettings) then
    begin
      for Line := Section.First to Section.Last do
        AOutput.Add(ALines[Line]);
      Continue;
    end;
    Items := CollectItems(Section, AClass, ALines, ASettings.Members, Next);
    SortItems(Items);
    for Item in Items do
      for Line := Item.First to Item.Last do
        AOutput.Add(ALines[Line]);
    // Was nach dem letzten Mitglied kommt, bleibt am Ende.
    for Line := Next to Section.Last do
      AOutput.Add(ALines[Line]);
  end;
end;

/// <summary>Weicht AOutput von den Zeilen AHeader+1..AStop-1 ab?</summary>
function Changed(const ALines: TArray<string>; AOutput: TList<string>; AHeader, AStop: Integer): Boolean;
var
  Line: Integer;
begin
  if AOutput.Count <> AStop - AHeader - 1 then
    Exit(True);
  for Line := AHeader + 1 to AStop - 1 do
    if ALines[Line] <> AOutput[Line - AHeader - 1] then
      Exit(True);
  Result := False;
end;

function JoinLines(AOutput: TList<string>; const ALineBreak: string): string;
var
  Builder: TStringBuilder;
  Line: string;
begin
  Builder := TStringBuilder.Create;
  try
    for Line in AOutput do
      Builder.Append(Line).Append(ALineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TMemberOrder.Sort(const AText: string; ATree: TSyntaxTree; ALine: Integer;
  const ASettings: TMemberOrderSettings; out AEdit: TRuleEdit): Boolean;
var
  Lines: TArray<string>;
  ClassNode: TSyntaxNode;
  Header, Stop: Integer;
  Sections: TArray<TSection>;
  Output: TList<string>;
begin
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) or HasPackedAlignment(AText) then
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
  Sections := CollectSections(Lines, Header, Stop);
  // {$IF…}: innerhalb eines Abschnitts nur Einheit, quer dazu keine Aktion.
  if not MarkDirectives(Sections, Lines) or not ClassifyMembers(Sections, ClassNode, Header) then
    Exit;
  OrderSections(Sections, ASettings);
  Output := TList<string>.Create;
  try
    EmitSections(Lines, Sections, ClassNode, ASettings, Output);
    // Unverändert: keine Aktion.
    if not Changed(Lines, Output, Header, Stop) then
      Exit;
    AEdit := TRuleEdit.Create(TTextRange.Create(Header + 1, 0, Stop, 0),
      JoinLines(Output, TTextLines.LineBreakOf(AText)));
    Result := True;
  finally
    Output.Free;
  end;
end;

end.
