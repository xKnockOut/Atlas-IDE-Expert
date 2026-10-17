unit Atlas.Common.Editing.WithResolution;

// „with auflösen“ (#50, Teil C) ohne Protokollbezug: Jeder Bezeichner im
// Rumpf, der zu einem Mitglied eines with-Ausdrucks gehört, bekommt diesen
// Ausdruck vorangestellt; danach entfällt der with-Kopf. Steht der Rumpf als
// begin … end in einer Anweisungsliste, entfallen auch begin und end, und
// die Anweisungen rücken eine Ebene nach links.
//
// Wem ein Bezeichner gehört, sagt TWithOwnerLookup (Namensauflösung des
// Servers: innerstes Element zuerst, bei with A, B also B vor A, dann der
// umgebende Gültigkeitsbereich). Ist ein Bezeichner nicht eindeutig
// auflösbar, gibt es die Aktion nicht. Einfache Ketten (A, A.B, A[I]) werden
// so vorangestellt; ein aufwendiger Ausdruck (Aufruf, Typumwandlung) kommt
// vorher in eine lokale Variable, wenn sein Typ eine Klasse oder ein
// Interface ist. Bei Records würde die Kopie die Bedeutung ändern: dann gibt
// es die Aktion nicht.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.Extract;

type
  {$SCOPEDENUMS ON}
  /// <summary>Herkunft eines Bezeichners im with-Rumpf.</summary>
  TWithOwner = (
    /// <summary>Mitglied des Elements AElement der with-Anweisung.</summary>
    Element,
    /// <summary>Kein Mitglied der with-Anweisung (lokal, Feld, global oder ein inneres with).</summary>
    Other,
    /// <summary>Nicht auflösbar, z. B. weil der Typ eines Elements unbekannt ist.</summary>
    Unknown);
  {$SCOPEDENUMS OFF}

  /// <summary>Herkunft des Bezeichners AIdentifier im Rumpf von AWith; AElement ist der Index des Elements
  /// (0 = erstes nach with).</summary>
  TWithOwnerLookup = reference to function(AWith, AIdentifier: TSyntaxNode; out AElement: Integer): TWithOwner;

  TWithResolution = class
  public const
    ItemName = 'Item';
  public
    /// <summary>Innerste with-Anweisung, in der APosition liegt; nil ohne.</summary>
    class function WithAt(ATree: TSyntaxTree; const APosition: TTextPosition): TSyntaxNode; static;
    /// <summary>Elemente der with-Anweisung (Ausdrücke vor do).</summary>
    class function Elements(ATree: TSyntaxTree; AWith: TSyntaxNode): TArray<TSyntaxNode>; static;
    /// <summary>Rumpf der with-Anweisung; nil bei leerem Rumpf.</summary>
    class function BodyOf(ATree: TSyntaxTree; AWith: TSyntaxNode): TSyntaxNode; static;
    /// <summary>„with auflösen“ für AWith; False mit Grund in AReason.</summary>
    class function Resolve(const AText: string; ATree: TSyntaxTree; AWith: TSyntaxNode;
      const ALookup: TWithOwnerLookup; const AOptions: TExtractOptions; out AAction: TCodeAction;
      out AReason: string): Boolean; overload; static;
    class function Resolve(const AText: string; ATree: TSyntaxTree; AWith: TSyntaxNode;
      const ALookup: TWithOwnerLookup; const AOptions: TExtractOptions; out AAction: TCodeAction): Boolean;
      overload; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.RoutineBody;

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

function Compare(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
    Result := A.Character - B.Character;
end;

class function TWithResolution.WithAt(ATree: TSyntaxTree; const APosition: TTextPosition): TSyntaxNode;
var
  Node: TSyntaxNode;
  Index: Integer;
  Descended: Boolean;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Node := ATree.Root;
  repeat
    Descended := False;
    for Index := 0 to Node.ChildCount - 1 do
      if (Compare(Node[Index].StartPos, APosition) <= 0) and (Compare(APosition, Node[Index].EndPos) <= 0) then
      begin
        Node := Node[Index];
        if Node.Kind = TSyntaxKind.WithStatement then
          Result := Node;
        Descended := True;
        Break;
      end;
  until not Descended;
end;

/// <summary>Offset des "do" der with-Anweisung; -1 ohne.</summary>
function DoOffset(ATree: TSyntaxTree; AWith: TSyntaxNode): Integer;
var
  Tokens: TArray<TPascalToken>;
  Index, Depth: Integer;
begin
  Result := -1;
  Tokens := ATree.Tokens;
  Index := TRoutineBody.TokenAt(Tokens, AWith.StartOffset);
  Depth := 0;
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < AWith.EndOffset) do
  begin
    if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol('[') then
      Inc(Depth)
    else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
      Dec(Depth)
    else if (Depth = 0) and Tokens[Index].IsKeyword('do') then
      Exit(Tokens[Index].Offset);
    Inc(Index);
  end;
end;

class function TWithResolution.Elements(ATree: TSyntaxTree; AWith: TSyntaxNode): TArray<TSyntaxNode>;
var
  Offset, Index: Integer;
begin
  Result := nil;
  Offset := DoOffset(ATree, AWith);
  if Offset < 0 then
    Exit;
  for Index := 0 to AWith.ChildCount - 1 do
    if AWith[Index].EndOffset <= Offset then
      Result := Result + [AWith[Index]];
end;

class function TWithResolution.BodyOf(ATree: TSyntaxTree; AWith: TSyntaxNode): TSyntaxNode;
var
  Offset: Integer;
begin
  Result := nil;
  Offset := DoOffset(ATree, AWith);
  if (Offset >= 0) and (AWith.ChildCount > 0) and (AWith[AWith.ChildCount - 1].StartOffset > Offset) then
    Result := AWith[AWith.ChildCount - 1];
end;

procedure CollectIdentifiers(ANode: TSyntaxNode; AList: TList<TSyntaxNode>);
var
  Index: Integer;
begin
  if ANode.Kind = TSyntaxKind.Identifier then
    AList.Add(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
    CollectIdentifiers(ANode[Index], AList);
end;

/// <summary>Kette aus Namen und Indizes (A, A.B, A[I], Self): wird unverändert vorangestellt.</summary>
function IsSimple(ANode: TSyntaxNode): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.Identifier:
      Result := True;
    TSyntaxKind.MemberAccess, TSyntaxKind.Dereference, TSyntaxKind.IndexAccess:
      Result := (ANode.ChildCount > 0) and IsSimple(ANode[0]);
  else
    Result := False;
  end;
end;

/// <summary>Name der Variablen für einen Typ: TKunde → Kunde, sonst Item.</summary>
function VariableFor(const ATypeName: string): string;
begin
  Result := ATypeName;
  if Pos('<', Result) > 0 then
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  Result := Result.Substring(Result.LastIndexOf('.') + 1);
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 'I']) and CharInSet(Result[2], ['A'..'Z']) then
    Result := Copy(Result, 2, MaxInt);
  if (Result = '') or not CharInSet(Result[1], ['A'..'Z', 'a'..'z', '_']) then
    Result := TWithResolution.ItemName;
end;

type
  TQualified = record
    Offset: Integer;
    Element: Integer;
  end;

class function TWithResolution.Resolve(const AText: string; ATree: TSyntaxTree; AWith: TSyntaxNode;
  const ALookup: TWithOwnerLookup; const AOptions: TExtractOptions; out AAction: TCodeAction): Boolean;
var
  Reason: string;
begin
  Result := Resolve(AText, ATree, AWith, ALookup, AOptions, AAction, Reason);
end;

class function TWithResolution.Resolve(const AText: string; ATree: TSyntaxTree; AWith: TSyntaxNode;
  const ALookup: TWithOwnerLookup; const AOptions: TExtractOptions; out AAction: TCodeAction;
  out AReason: string): Boolean;
var
  Items: TArray<TSyntaxNode>;
  Body, Node, Routine: TSyntaxNode;
  Identifiers: TList<TSyntaxNode>;
  Qualified: TList<TQualified>;
  Entry: TQualified;
  Prefixes: TArray<string>;
  Used: TArray<Boolean>;
  Element, Index: Integer;
  Probed: TProbedType;
  Name, Declarations, LineBreak, WithIndent, BodyText, Content, NewText, BodyIndent: string;
  Lines: TArray<string>;
  First, Last: Integer;
  Edits: TArray<TTextEdit>;
  UsesEdit: TTextEdit;
  InList: Boolean;
  Tokens: TArray<TPascalToken>;
  Taken: TArray<string>;
begin
  AAction := Default(TCodeAction);
  AReason := '';
  Result := False;
  if (ATree = nil) or (AWith = nil) or not Assigned(ALookup) then
    Exit(Fail('keine with-Anweisung', AReason));
  Items := Elements(ATree, AWith);
  Body := BodyOf(ATree, AWith);
  if (Items = nil) or (Body = nil) then
    Exit(Fail('with ohne Rumpf', AReason));
  Routine := TRoutineBody.RoutineAt(ATree, AWith.StartOffset);
  if Routine = nil then
    Exit(Fail('nicht in einer Routine', AReason));
  SetLength(Prefixes, Length(Items));
  SetLength(Used, Length(Items));
  for Index := 0 to High(Items) do
  begin
    Prefixes[Index] := '';
    Used[Index] := False;
  end;
  Qualified := TList<TQualified>.Create;
  Identifiers := TList<TSyntaxNode>.Create;
  try
    CollectIdentifiers(Body, Identifiers);
    for Node in Identifiers do
      case ALookup(AWith, Node, Element) of
        TWithOwner.Unknown:
          Exit(Fail(Node.Name + ' ist nicht eindeutig auflösbar', AReason));
        TWithOwner.Element:
          if (Element >= 0) and (Element <= High(Items)) then
          begin
            Used[Element] := True;
            Entry.Offset := Node.StartOffset - Body.StartOffset;
            Entry.Element := Element;
            Qualified.Add(Entry);
          end;
      end;
    LineBreak := TTextLines.LineBreakOf(AText);
    WithIndent := TTextLines.IndentOf(AText, AWith.StartPos.Line);
    InList := TRoutineBody.InList(AWith);
    Tokens := ATree.Tokens;
    Taken := nil;
    Declarations := '';
    Edits := nil;
    // Vorangestellter Text je Element; aufwendige Ausdrücke in eine Variable.
    for Index := 0 to High(Items) do
    begin
      if not Used[Index] then
        Continue;
      if IsSimple(Items[Index]) then
      begin
        Prefixes[Index] := TRoutineBody.TextOf(AText, Items[Index]);
        Continue;
      end;
      Probed := TExtractRefactoring.TypeOfExpression(AText, ATree, Items[Index], AWith, AOptions);
      if not Probed.IsReference then
        Exit(Fail('Typ von ' + TRoutineBody.TextOf(AText, Items[Index]) + ' ist kein Klassentyp', AReason));
      if not InList then
        Exit(Fail('with steht nicht in einer Anweisungsliste', AReason));
      Name := TRoutineBody.UniqueName(Tokens, VariableFor(Probed.Name));
      while IndexText(Name, Taken) >= 0 do
        Name := Name + '_';
      Taken := Taken + [Name];
      Prefixes[Index] := Name;
      // Klammern um eine Typumwandlung braucht die Zuweisung nicht.
      Node := Items[Index];
      if (Node.Kind = TSyntaxKind.ParenExpr) and (Node.ChildCount = 1) then
        Node := Node[0];
      if AOptions.InlineVar then
        Declarations := Declarations + 'var ' + Name + ' := ' + TRoutineBody.TextOf(AText, Node) + ';' + LineBreak +
          WithIndent
      else
      begin
        Edits := Edits + [TRoutineBody.AddVariable(AText, Routine, Name, Probed.Name, AOptions.Style)];
        Declarations := Declarations + Name + ' := ' + TRoutineBody.TextOf(AText, Node) + ';' + LineBreak +
          WithIndent;
      end;
      if (Probed.UnitName <> '') and TUsesClauses.AddUnit(Tokens, AWith.StartOffset, Probed.UnitName, LineBreak,
        UsesEdit) then
        Edits := Edits + [UsesEdit];
    end;
    // Bezeichner von hinten nach vorn qualifizieren.
    Qualified.Sort(TComparer<TQualified>.Construct(
      function(const A, B: TQualified): Integer
      begin
        Result := B.Offset - A.Offset;
      end));
    BodyText := TRoutineBody.TextOf(AText, Body);
    for Entry in Qualified do
      BodyText := Copy(BodyText, 1, Entry.Offset) + Prefixes[Entry.Element] + '.' +
        Copy(BodyText, Entry.Offset + 1, MaxInt);
  finally
    Identifiers.Free;
    Qualified.Free;
  end;
  if (Body.Kind = TSyntaxKind.Block) and InList and StartsText('begin', BodyText) and EndsText('end', BodyText) then
  begin
    // begin … end entfallen; die Anweisungen rücken auf die Höhe von with.
    Content := Copy(BodyText, 6, Length(BodyText) - 8);
    Lines := TTextLines.SplitLines(Content);
    First := 0;
    while (First <= High(Lines)) and (Trim(Lines[First]) = '') do
      Inc(First);
    Last := High(Lines);
    while (Last >= First) and (Trim(Lines[Last]) = '') do
      Dec(Last);
    NewText := '';
    // Das ";" hinter der letzten Anweisung steht schon hinter der with-Anweisung.
    if (Last >= First) and EndsStr(';', TrimRight(Lines[Last])) then
    begin
      Lines[Last] := TrimRight(Lines[Last]);
      Lines[Last] := Copy(Lines[Last], 1, Length(Lines[Last]) - 1);
    end;
    if First <= Last then
    begin
      BodyIndent := TTextLines.IndentOf(Lines[First]);
      for Index := First to Last do
      begin
        if Index > First then
          NewText := NewText + LineBreak + WithIndent;
        if StartsStr(BodyIndent, Lines[Index]) then
          NewText := NewText + Copy(Lines[Index], Length(BodyIndent) + 1, MaxInt)
        else
          NewText := NewText + TrimLeft(Lines[Index]);
      end;
    end;
  end
  else
  begin
    // Einzelne Anweisung bzw. begin … end außerhalb einer Liste: auf die Höhe von with.
    if Body.StartPos.Line > AWith.StartPos.Line then
      BodyIndent := TTextLines.IndentOf(AText, Body.StartPos.Line)
    else
      BodyIndent := WithIndent;
    NewText := TRoutineBody.Reindent(BodyText, BodyIndent, '', LineBreak);
    Lines := TTextLines.SplitLines(NewText);
    NewText := '';
    for Index := 0 to High(Lines) do
    begin
      if Index > 0 then
        NewText := NewText + LineBreak + WithIndent;
      NewText := NewText + Lines[Index];
    end;
  end;
  Edits := Edits + [TTextEdit.Create(TTextRange.Create(AWith.StartPos, AWith.EndPos), Declarations + NewText)];
  AAction.Title := 'with auflösen';
  AAction.Kind := RewriteKind;
  AAction.Edits := Edits;
  Result := True;
end;

end.
