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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Configuration.Contract;

type
  TMemberOrder = class
  public
    /// <summary>Ordnet die Klasse um Zeile ALine; False, wenn es nichts zu tun gibt oder sie nicht sicher sortierbar
    /// ist.</summary>
    class function Sort(const AText: string; ATree: TSyntaxTree; ALine: Integer;
      const ASettings: TMemberOrderSettings; out AEdit: TTextEdit): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
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
  cVisibilities: array[0..6] of string = ('strict private', 'private', 'strict protected', 'protected', 'public',
    'published', 'automated');
  cMemberKinds = [TSyntaxKind.Field, TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl, TSyntaxKind.PropertyDecl];
  cIgnoredKinds = [TSyntaxKind.Visibility, TSyntaxKind.Attribute, TSyntaxKind.TypeReference,
    TSyntaxKind.GenericParams];

function SplitText(const AText: string): TArray<string>;
var
  mIndex, mStart: Integer;
begin
  Result := nil;
  mStart := 1;
  for mIndex := 1 to Length(AText) + 1 do
  begin
    if (mIndex > Length(AText)) or (AText[mIndex] = #10) then
    begin
      Result := Result + [Copy(AText, mStart, mIndex - mStart)];
      mStart := mIndex + 1;
    end;
  end;
  for mIndex := 0 to High(Result) do
  begin
    if EndsStr(#13, Result[mIndex]) then
    begin
      Result[mIndex] := Copy(Result[mIndex], 1, Length(Result[mIndex]) - 1);
    end;
  end;
end;

function NormalizedWords(const ALine: string): string;
begin
  Result := LowerCase(Trim(ALine));
  while Pos('  ', Result) > 0 do
  begin
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  end;
end;

function FindClass(ANode: TSyntaxNode; ALine: Integer): TSyntaxNode;
var
  mPending: TStack<TSyntaxPostOrderEntry>;
  mEntry: TSyntaxPostOrderEntry;
  mIndex: Integer;
begin
  // Eigener Stapel statt Rekursion; die innerste Klasse gewinnt, also die Kinder vor dem Knoten.
  Result := nil;
  mPending := TStack<TSyntaxPostOrderEntry>.Create;
  try
    mPending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
    while mPending.Count > 0 do
    begin
      mEntry := mPending.Pop;
      if mEntry.Done then
      begin
        if mEntry.Node.Kind = TSyntaxKind.ClassType then
        begin
          Exit(mEntry.Node);
        end;
        Continue;
      end;
      if (mEntry.Node.StartPos.Line > ALine) or (mEntry.Node.EndPos.Line < ALine) then
      begin
        Continue;
      end;
      mPending.Push(TSyntaxPostOrderEntry.Create(mEntry.Node, True));
      for mIndex := mEntry.Node.ChildCount - 1 downto 0 do
      begin
        mPending.Push(TSyntaxPostOrderEntry.Create(mEntry.Node[mIndex], False));
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>-1 öffnet, +1 schließt, 0 sonst; AOther bei {$ELSE}.</summary>
function DirectiveStep(const ALine: string; out AOther: Boolean): Integer;
var
  mText: string;
begin
  mText := UpperCase(TrimLeft(ALine));
  AOther := StartsStr('{$ELSE', mText);
  if StartsStr('{$IFDEF', mText) or StartsStr('{$IFNDEF', mText) or StartsStr('{$IFOPT', mText) or
    StartsStr('{$IF ', mText) or StartsStr('{$IF(', mText) then
  begin
    Result := -1;
  end
  else if StartsStr('{$ENDIF', mText) or StartsStr('{$IFEND', mText) then
  begin
    Result := 1;
  end
  else
  begin
    Result := 0;
  end;
end;

function KindRank(const ALine: string; ANodeKind: TSyntaxKind; const AOrder: TArray<string>): Integer;
var
  mText, mKind: string;
begin
  mText := NormalizedWords(ALine);
  if StartsStr('class ', mText) then
  begin
    mText := Copy(mText, 7, MaxInt);
  end;
  if StartsStr('constructor', mText) then
  begin
    mKind := 'constructor';
  end
  else if StartsStr('destructor', mText) then
  begin
    mKind := 'destructor';
  end
  else if StartsStr('property', mText) then
  begin
    mKind := 'property';
  end
  else if ANodeKind = TSyntaxKind.Field then
  begin
    mKind := 'field';
  end
  else
  begin
    mKind := 'method';
  end;
  Result := IndexText(mKind, AOrder);
  if Result < 0 then
  begin
    Result := Length(AOrder);
  end;
end;

procedure SortItems(var AItems: TArray<TItem>);
var
  I, J: Integer;
  mItem: TItem;
begin
  // Einfügesortierung: stabil, die Listen sind kurz.
  for I := 1 to High(AItems) do
  begin
    mItem := AItems[I];
    J := I - 1;
    while (J >= 0) and ((AItems[J].Rank > mItem.Rank) or
      ((AItems[J].Rank = mItem.Rank) and (AItems[J].Position > mItem.Position))) do
    begin
      AItems[J + 1] := AItems[J];
      Dec(J);
    end;
    AItems[J + 1] := mItem;
  end;
end;

procedure SortSections(var ASections: TArray<TSection>);
var
  I, J: Integer;
  mSection: TSection;
begin
  for I := 1 to High(ASections) do
  begin
    mSection := ASections[I];
    J := I - 1;
    while (J >= 0) and (ASections[J].Position > mSection.Position) do
    begin
      ASections[J + 1] := ASections[J];
      Dec(J);
    end;
    ASections[J + 1] := mSection;
  end;
end;

/// <summary>{$A-}, {$A1}, {$ALIGN OFF} oder {$ALIGN 1} irgendwo in der Datei.</summary>
function HasPackedAlignment(const AText: string): Boolean;
var
  mUpper: string;
begin
  mUpper := UpperCase(AText);
  Result := ContainsStr(mUpper, '{$A-}') or ContainsStr(mUpper, '{$A1}') or ContainsStr(mUpper, '{$ALIGN OFF}') or
    ContainsStr(mUpper, '{$ALIGN 1}');
end;

/// <summary>Abschnitte über die Schlüsselwortzeilen zwischen AHeader und AStop.</summary>
function CollectSections(const ALines: TArray<string>; AHeader, AStop: Integer): TArray<TSection>;
var
  mSections: TList<TSection>;
  mSection: TSection;
  mLine: Integer;
  mWords: string;
begin
  Result := nil;
  mSections := TList<TSection>.Create;
  try
    mSection := Default(TSection);
    mSection.Header := -1;
    mSection.First := AHeader + 1;
    for mLine := AHeader + 1 to AStop - 1 do
    begin
      mWords := NormalizedWords(ALines[mLine]);
      if IndexText(mWords, cVisibilities) >= 0 then
      begin
        mSection.Last := mLine - 1;
        mSections.Add(mSection);
        mSection := Default(TSection);
        mSection.Keyword := mWords;
        mSection.Header := mLine;
        mSection.First := mLine + 1;
      end
      else if MatchText(mWords, ['type', 'const', 'var', 'class var', 'threadvar', 'resourcestring']) or
        StartsText('class var ', mWords) then
      begin
        mSection.Nested := True;
      end;
    end;
    mSection.Last := AStop - 1;
    mSections.Add(mSection);
    Result := mSections.ToArray;
  finally
    mSections.Free;
  end;
end;

/// <summary>Markiert Abschnitte mit {$IF…}; False, wenn ein Block quer zu Abschnitten liegt.</summary>
function MarkDirectives(var ASections: TArray<TSection>; const ALines: TArray<string>): Boolean;
var
  mSectionIndex, mLine, mDepth, mStep: Integer;
  mOther: Boolean;
begin
  Result := False;
  for mSectionIndex := 0 to High(ASections) do
  begin
    mDepth := 0;
    for mLine := ASections[mSectionIndex].First to ASections[mSectionIndex].Last do
    begin
      mStep := DirectiveStep(ALines[mLine], mOther);
      if (mStep <> 0) or mOther then
      begin
        ASections[mSectionIndex].Directives := True;
      end;
      Inc(mDepth, -mStep);
      if mDepth < 0 then
      begin
        Exit;
      end;
    end;
    if mDepth <> 0 then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

/// <summary>Ordnet AChild dem Abschnitt ASection zu, wenn es dort beginnt. False, wenn es darüber hinausreicht.
/// </summary>
function ClassifyMember(var ASection: TSection; AChild: TSyntaxNode): Boolean;
begin
  Result := True;
  if (AChild.StartPos.Line < ASection.First) or (AChild.StartPos.Line > ASection.Last) then
  begin
    Exit;
  end;
  if not (AChild.Kind in cMemberKinds) then
  begin
    ASection.Nested := True;
  end
  else if AChild.Kind = TSyntaxKind.Field then
  begin
    ASection.HasFields := True;
  end;
  Result := AChild.EndPos.Line <= ASection.Last;
end;

/// <summary>Ordnet die Kindknoten den Abschnitten zu (Nested, HasFields); Unbekanntes gilt als verschachtelte
/// Deklaration. False, wenn ein Mitglied über mehrere Abschnitte reicht.</summary>
function ClassifyMembers(var ASections: TArray<TSection>; AClass: TSyntaxNode; AHeader: Integer): Boolean;
var
  mIndex, mSectionIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := True;
  for mIndex := 0 to AClass.ChildCount - 1 do
  begin
    mChild := AClass[mIndex];
    if (mChild.Kind in cIgnoredKinds) or (mChild.StartPos.Line <= AHeader) then
    begin
      Continue;
    end;
    for mSectionIndex := 0 to High(ASections) do
    begin
      if not ClassifyMember(ASections[mSectionIndex], mChild) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

/// <summary>Dürfen Abschnitte verschoben werden? Nein bei verschachtelten Deklarationen oder bei Feldern in
/// mehreren Abschnitten ohne sortFields (sonst änderte sich das Speicherlayout).</summary>
function CanMoveSections(const ASections: TArray<TSection>; const ASettings: TMemberOrderSettings): Boolean;
var
  mSection: TSection;
  mFieldSections: Integer;
begin
  Result := True;
  mFieldSections := 0;
  for mSection in ASections do
  begin
    if mSection.Nested then
    begin
      Result := False;
    end;
    if mSection.HasFields then
    begin
      Inc(mFieldSections);
    end;
  end;
  if (mFieldSections > 1) and not ASettings.SortFields then
  begin
    Result := False;
  end;
end;

/// <summary>Position je Abschnitt setzen und stabil sortieren; der Abschnitt ohne Schlüsselwort bleibt vorn.</summary>
procedure OrderSections(var ASections: TArray<TSection>; const ASettings: TMemberOrderSettings);
var
  mSectionIndex, mRank: Integer;
  mMayMove: Boolean;
begin
  mMayMove := CanMoveSections(ASections, ASettings);
  for mSectionIndex := 0 to High(ASections) do
  begin
    mRank := IndexText(ASections[mSectionIndex].Keyword, ASettings.Sections);
    if mRank < 0 then
    begin
      mRank := Length(ASettings.Sections);
    end;
    if ASections[mSectionIndex].Header < 0 then
    begin
      ASections[mSectionIndex].Position := -1;
    end
    else if mMayMove then
    begin
      ASections[mSectionIndex].Position := mRank * 1000 + mSectionIndex;
    end
    else
    begin
      ASections[mSectionIndex].Position := mSectionIndex;
    end;
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
  mItems: TList<TItem>;
  mItem: TItem;
  mChild: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  ANext := ASection.First;
  mItems := TList<TItem>.Create;
  try
    for mIndex := 0 to AClass.ChildCount - 1 do
    begin
      mChild := AClass[mIndex];
      if not (mChild.Kind in cMemberKinds) or (mChild.StartPos.Line < ASection.First) or
        (mChild.StartPos.Line > ASection.Last) then
      begin
        Continue;
      end;
      // Mehrere Knoten in einer Zeile (A, B: Integer) gehören zusammen.
      if (mItems.Count > 0) and (mChild.StartPos.Line <= mItems[mItems.Count - 1].Last) then
      begin
        if mChild.EndPos.Line > mItems[mItems.Count - 1].Last then
        begin
          mItem := mItems[mItems.Count - 1];
          mItem.Last := mChild.EndPos.Line;
          mItems[mItems.Count - 1] := mItem;
          ANext := mItem.Last + 1;
        end;
        Continue;
      end;
      mItem := Default(TItem);
      mItem.First := ANext;
      mItem.Last := mChild.EndPos.Line;
      mItem.Rank := KindRank(ALines[mChild.StartPos.Line], mChild.Kind, AOrder);
      mItem.Position := mItems.Count;
      mItems.Add(mItem);
      ANext := mItem.Last + 1;
    end;
    Result := mItems.ToArray;
  finally
    mItems.Free;
  end;
end;

/// <summary>Neue Zeilen zwischen Kopf und end.</summary>
procedure EmitSections(const ALines: TArray<string>; const ASections: TArray<TSection>; AClass: TSyntaxNode;
  const ASettings: TMemberOrderSettings; AOutput: TList<string>);
var
  mSection: TSection;
  mItems: TArray<TItem>;
  mItem: TItem;
  mLine, mNext: Integer;
begin
  for mSection in ASections do
  begin
    if mSection.Header >= 0 then
    begin
      AOutput.Add(ALines[mSection.Header]);
    end;
    if not SectionSortable(mSection, ASettings) then
    begin
      for mLine := mSection.First to mSection.Last do
      begin
        AOutput.Add(ALines[mLine]);
      end;
      Continue;
    end;
    mItems := CollectItems(mSection, AClass, ALines, ASettings.Members, mNext);
    SortItems(mItems);
    for mItem in mItems do
    begin
      for mLine := mItem.First to mItem.Last do
      begin
        AOutput.Add(ALines[mLine]);
      end;
    end;
    // Was nach dem letzten Mitglied kommt, bleibt am Ende.
    for mLine := mNext to mSection.Last do
    begin
      AOutput.Add(ALines[mLine]);
    end;
  end;
end;

/// <summary>Weicht AOutput von den Zeilen AHeader+1..AStop-1 ab?</summary>
function Changed(const ALines: TArray<string>; AOutput: TList<string>; AHeader, AStop: Integer): Boolean;
var
  mLine: Integer;
begin
  if AOutput.Count <> AStop - AHeader - 1 then
  begin
    Exit(True);
  end;
  for mLine := AHeader + 1 to AStop - 1 do
  begin
    if ALines[mLine] <> AOutput[mLine - AHeader - 1] then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function JoinLines(AOutput: TList<string>; const ALineBreak: string): string;
var
  mBuilder: TStringBuilder;
  mLine: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mLine in AOutput do
    begin
      mBuilder.Append(mLine).Append(ALineBreak);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Klasse an Zeile ALine, wenn der Text keine packed-Ausrichtung hat; sonst nil.</summary>
function SortableClass(const AText: string; ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
begin
  Result := nil;
  if (ATree <> nil) and (ATree.Root <> nil) and not HasPackedAlignment(AText) then
  begin
    Result := FindClass(ATree.Root, ALine);
  end;
end;

class function TMemberOrder.Sort(const AText: string; ATree: TSyntaxTree; ALine: Integer;
  const ASettings: TMemberOrderSettings; out AEdit: TTextEdit): Boolean;
var
  mLines: TArray<string>;
  mClassNode: TSyntaxNode;
  mHeader, mStop: Integer;
  mSections: TArray<TSection>;
  mOutput: TList<string>;
begin
  Result := False;
  mClassNode := SortableClass(AText, ATree, ALine);
  if mClassNode = nil then
  begin
    Exit;
  end;
  mLines := SplitText(AText);
  mHeader := mClassNode.StartPos.Line;
  mStop := mClassNode.EndPos.Line;
  if (mStop - mHeader < 2) or (mStop > High(mLines)) or ContainsText(mLines[mHeader], 'packed') or
    not StartsText('end', TrimLeft(mLines[mStop])) then
  begin
    Exit;
  end;
  mSections := CollectSections(mLines, mHeader, mStop);
  // {$IF…}: innerhalb eines Abschnitts nur Einheit, quer dazu keine Aktion.
  if not MarkDirectives(mSections, mLines) or not ClassifyMembers(mSections, mClassNode, mHeader) then
  begin
    Exit;
  end;
  OrderSections(mSections, ASettings);
  mOutput := TList<string>.Create;
  try
    EmitSections(mLines, mSections, mClassNode, ASettings, mOutput);
    // Unverändert: keine Aktion.
    if not Changed(mLines, mOutput, mHeader, mStop) then
    begin
      Exit;
    end;
    AEdit := TTextEdit.Create(TTextRange.Create(mHeader + 1, 0, mStop, 0),
      JoinLines(mOutput, TTextLines.LineBreakOf(AText)));
    Result := True;
  finally
    mOutput.Free;
  end;
end;

end.
