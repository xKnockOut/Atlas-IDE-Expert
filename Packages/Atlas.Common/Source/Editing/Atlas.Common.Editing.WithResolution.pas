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

  /// <summary>Ergebnis von TWithResolution.Resolve mit Grund.</summary>
  TWithResolved = record
    Action: TCodeAction;
    /// <summary>Warum es die Aktion nicht gibt; '' bei Erfolg.</summary>
    Reason: string;
  end;

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
    /// <summary>„with auflösen“ für AWith; False mit Grund in AResolved.Reason.</summary>
    class function Resolve(const AText: string; ATree: TSyntaxTree; AWith: TSyntaxNode;
      const ALookup: TWithOwnerLookup; const AOptions: TExtractOptions; out AResolved: TWithResolved): Boolean;
      overload; static;
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

function Compare(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
  begin
    Result := A.Character - B.Character;
  end;
end;

class function TWithResolution.WithAt(ATree: TSyntaxTree; const APosition: TTextPosition): TSyntaxNode;
var
  Node: TSyntaxNode;
  Index: Integer;
  Descended: Boolean;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  Node := ATree.Root;
  repeat
    Descended := False;
    for Index := 0 to Node.ChildCount - 1 do
    begin
      if (Compare(Node[Index].StartPos, APosition) <= 0) and (Compare(APosition, Node[Index].EndPos) <= 0) then
      begin
        Node := Node[Index];
        if Node.Kind = TSyntaxKind.WithStatement then
        begin
          Result := Node;
        end;
        Descended := True;
        Break;
      end;
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
    begin
      Inc(Depth);
    end
    else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
    begin
      Dec(Depth);
    end
    else if (Depth = 0) and Tokens[Index].IsKeyword('do') then
    begin
      Exit(Tokens[Index].Offset);
    end;
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
  begin
    Exit;
  end;
  for Index := 0 to AWith.ChildCount - 1 do
  begin
    if AWith[Index].EndOffset <= Offset then
    begin
      Result := Result + [AWith[Index]];
    end;
  end;
end;

class function TWithResolution.BodyOf(ATree: TSyntaxTree; AWith: TSyntaxNode): TSyntaxNode;
var
  Offset: Integer;
begin
  Result := nil;
  Offset := DoOffset(ATree, AWith);
  if (Offset >= 0) and (AWith.ChildCount > 0) and (AWith[AWith.ChildCount - 1].StartOffset > Offset) then
  begin
    Result := AWith[AWith.ChildCount - 1];
  end;
end;

procedure CollectIdentifiers(ANode: TSyntaxNode; AList: TList<TSyntaxNode>);
var
  List: TList<TSyntaxNode>;
begin
  List := AList;
  // Walk statt Rekursion (Bericht M1).
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      if AChild.Kind = TSyntaxKind.Identifier then
      begin
        List.Add(AChild);
      end;
      Result := True;
    end);
end;

/// <summary>Kette aus Namen und Indizes (A, A.B, A[I], Self): wird unverändert vorangestellt.</summary>
function IsSimple(ANode: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  // Schleife statt Rekursion (Bericht M1).
  Node := ANode;
  while (Node.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Dereference, TSyntaxKind.IndexAccess]) and
    (Node.ChildCount > 0) do
  begin
    Node := Node[0];
  end;
  Result := Node.Kind = TSyntaxKind.Identifier;
end;

/// <summary>Name der Variablen für einen Typ: TKunde → Kunde, sonst Item.</summary>
function VariableFor(const ATypeName: string): string;
begin
  Result := ATypeName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := Result.Substring(Result.LastIndexOf('.') + 1);
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 'I']) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
  if (Result = '') or not CharInSet(Result[1], ['A'..'Z', 'a'..'z', '_']) then
  begin
    Result := TWithResolution.ItemName;
  end;
end;

type
  TQualified = record
    Offset: Integer;
    Element: Integer;
  end;

  /// <summary>Ablauf von „with auflösen“ für eine with-Anweisung.</summary>
  TWithResolver = class
  private
    FText: string;
    FTree: TSyntaxTree;
    FWith: TSyntaxNode;
    FLookup: TWithOwnerLookup;
    FOptions: TExtractOptions;
    FItems: TArray<TSyntaxNode>;
    FBody: TSyntaxNode;
    FRoutine: TSyntaxNode;
    FPrefixes: TArray<string>;
    FUsed: TArray<Boolean>;
    FQualified: TList<TQualified>;
    FLineBreak: string;
    FWithIndent: string;
    FInList: Boolean;
    FTaken: TArray<string>;
    FDeclarations: string;
    FEdits: TArray<TTextEdit>;
    FReason: string;
    function Fail(const AReason: string): Boolean;
    /// <summary>Elemente, Rumpf und Routine bestimmen; False mit Grund.</summary>
    function Prepare: Boolean;
    /// <summary>Bezeichner im Rumpf, die einem Element gehören, merken; False bei nicht auflösbarem.</summary>
    function CollectQualified: Boolean;
    /// <summary>Vorangestellter Text für Element AIndex; aufwendige Ausdrücke in eine Variable.</summary>
    function PrefixElement(AIndex: Integer): Boolean;
    /// <summary>Variable für das aufwendige Element AIndex vom Typ AProbed anlegen und belegen.</summary>
    procedure DeclareVariable(AIndex: Integer; const AProbed: TProbedType);
    /// <summary>Rumpftext mit vorangestellten Ausdrücken, von hinten nach vorn qualifiziert.</summary>
    function QualifiedBody: string;
    /// <summary>begin … end in einer Liste: begin und end entfallen, die Anweisungen rücken auf die Höhe von with.
    /// </summary>
    function UnwrappedBlock(const ABodyText: string): string;
    /// <summary>Einzelne Anweisung bzw. begin … end außerhalb einer Liste: auf die Höhe von with.</summary>
    function AlignedStatement(const ABodyText: string): string;
  public
    constructor Create(const AText: string; ATree: TSyntaxTree; AWith: TSyntaxNode; const ALookup: TWithOwnerLookup;
      const AOptions: TExtractOptions);
    destructor Destroy; override;
    /// <summary>Führt die Auflösung aus; False mit Grund in AResolved.Reason.</summary>
    function Run(out AResolved: TWithResolved): Boolean;
  end;

constructor TWithResolver.Create(const AText: string; ATree: TSyntaxTree; AWith: TSyntaxNode;
  const ALookup: TWithOwnerLookup; const AOptions: TExtractOptions);
begin
  inherited Create;
  FText := AText;
  FTree := ATree;
  FWith := AWith;
  FLookup := ALookup;
  FOptions := AOptions;
  FQualified := TList<TQualified>.Create;
end;

destructor TWithResolver.Destroy;
begin
  FQualified.Free;
  inherited;
end;

function TWithResolver.Fail(const AReason: string): Boolean;
begin
  FReason := AReason;
  Result := False;
end;

function TWithResolver.Prepare: Boolean;
begin
  if (FTree = nil) or (FWith = nil) or not Assigned(FLookup) then
  begin
    Exit(Fail('keine with-Anweisung'));
  end;
  FItems := TWithResolution.Elements(FTree, FWith);
  FBody := TWithResolution.BodyOf(FTree, FWith);
  if (FItems = nil) or (FBody = nil) then
  begin
    Exit(Fail('with ohne Rumpf'));
  end;
  FRoutine := TRoutineBody.RoutineAt(FTree, FWith.StartOffset);
  if FRoutine = nil then
  begin
    Exit(Fail('nicht in einer Routine'));
  end;
  // SetLength füllt mit '' bzw. False.
  SetLength(FPrefixes, Length(FItems));
  SetLength(FUsed, Length(FItems));
  Result := True;
end;

function TWithResolver.CollectQualified: Boolean;
var
  mIdentifiers: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mElement: Integer;
  mEntry: TQualified;
begin
  Result := True;
  mIdentifiers := TList<TSyntaxNode>.Create;
  try
    CollectIdentifiers(FBody, mIdentifiers);
    for mNode in mIdentifiers do
    begin
      case FLookup(FWith, mNode, mElement) of
        TWithOwner.Unknown:
          Exit(Fail(mNode.Name + ' ist nicht eindeutig auflösbar'));
        TWithOwner.Element:
          if (mElement >= 0) and (mElement <= High(FItems)) then
          begin
            FUsed[mElement] := True;
            mEntry.Offset := mNode.StartOffset - FBody.StartOffset;
            mEntry.Element := mElement;
            FQualified.Add(mEntry);
          end;
      else
        // Other: bleibt, wie es ist.
      end;
    end;
  finally
    mIdentifiers.Free;
  end;
end;

procedure TWithResolver.DeclareVariable(AIndex: Integer; const AProbed: TProbedType);
var
  mName: string;
  mNode: TSyntaxNode;
  mUsesEdit: TTextEdit;
begin
  mName := TRoutineBody.UniqueName(FTree.Tokens, FOptions.Names.Local(VariableFor(AProbed.Name)));
  while IndexText(mName, FTaken) >= 0 do
  begin
    mName := mName + '_';
  end;
  FTaken := FTaken + [mName];
  FPrefixes[AIndex] := mName;
  // Klammern um eine Typumwandlung braucht die Zuweisung nicht.
  mNode := FItems[AIndex];
  if (mNode.Kind = TSyntaxKind.ParenExpr) and (mNode.ChildCount = 1) then
  begin
    mNode := mNode[0];
  end;
  if FOptions.InlineVar then
  begin
    FDeclarations := FDeclarations + 'var ';
  end
  else
  begin
    FEdits := FEdits + [TRoutineBody.AddVariable(FText, FRoutine, mName, AProbed.Name, FOptions.Style)];
  end;
  FDeclarations := FDeclarations + mName + ' := ' + TRoutineBody.TextOf(FText, mNode) + ';' + FLineBreak +
    FWithIndent;
  if (AProbed.UnitName <> '') and TUsesClauses.AddUnit(FTree.Tokens, FWith.StartOffset, AProbed.UnitName,
    FLineBreak, mUsesEdit) then
  begin
    FEdits := FEdits + [mUsesEdit];
  end;
end;

function TWithResolver.PrefixElement(AIndex: Integer): Boolean;
var
  mProbed: TProbedType;
begin
  Result := True;
  if IsSimple(FItems[AIndex]) then
  begin
    FPrefixes[AIndex] := TRoutineBody.TextOf(FText, FItems[AIndex]);
    Exit;
  end;
  mProbed := TExtractRefactoring.TypeOfExpression(FText, FTree, FItems[AIndex], FWith, FOptions);
  if not mProbed.IsReference then
  begin
    Exit(Fail('Typ von ' + TRoutineBody.TextOf(FText, FItems[AIndex]) + ' ist kein Klassentyp'));
  end;
  if not FInList then
  begin
    Exit(Fail('with steht nicht in einer Anweisungsliste'));
  end;
  DeclareVariable(AIndex, mProbed);
end;

function TWithResolver.QualifiedBody: string;
var
  mEntry: TQualified;
begin
  FQualified.Sort(TComparer<TQualified>.Construct(
    function(const A, B: TQualified): Integer
    begin
      Result := B.Offset - A.Offset;
    end));
  Result := TRoutineBody.TextOf(FText, FBody);
  for mEntry in FQualified do
  begin
    Result := Copy(Result, 1, mEntry.Offset) + FPrefixes[mEntry.Element] + '.' + Copy(Result, mEntry.Offset + 1,
      MaxInt);
  end;
end;

/// <summary>ALine ohne die Einrückung AIndent (sonst ohne führende Leerzeichen).</summary>
function Outdented(const ALine, AIndent: string): string;
begin
  if StartsStr(AIndent, ALine) then
  begin
    Result := Copy(ALine, Length(AIndent) + 1, MaxInt);
  end
  else
  begin
    Result := TrimLeft(ALine);
  end;
end;

function TWithResolver.UnwrappedBlock(const ABodyText: string): string;
var
  mLines: TArray<string>;
  mFirst, mLast, mIndex: Integer;
  mBodyIndent: string;
begin
  Result := '';
  mLines := TTextLines.SplitLines(Copy(ABodyText, 6, Length(ABodyText) - 8));
  mFirst := 0;
  while (mFirst <= High(mLines)) and (Trim(mLines[mFirst]) = '') do
  begin
    Inc(mFirst);
  end;
  mLast := High(mLines);
  while (mLast >= mFirst) and (Trim(mLines[mLast]) = '') do
  begin
    Dec(mLast);
  end;
  if mFirst > mLast then
  begin
    Exit;
  end;
  // Das ";" hinter der letzten Anweisung steht schon hinter der with-Anweisung.
  if EndsStr(';', TrimRight(mLines[mLast])) then
  begin
    mLines[mLast] := TrimRight(mLines[mLast]);
    mLines[mLast] := Copy(mLines[mLast], 1, Length(mLines[mLast]) - 1);
  end;
  mBodyIndent := TTextLines.IndentOf(mLines[mFirst]);
  for mIndex := mFirst to mLast do
  begin
    if mIndex > mFirst then
    begin
      Result := Result + FLineBreak + FWithIndent;
    end;
    Result := Result + Outdented(mLines[mIndex], mBodyIndent);
  end;
end;

function TWithResolver.AlignedStatement(const ABodyText: string): string;
var
  mLines: TArray<string>;
  mIndex: Integer;
  mBodyIndent: string;
begin
  mBodyIndent := FWithIndent;
  if FBody.StartPos.Line > FWith.StartPos.Line then
  begin
    mBodyIndent := TTextLines.IndentOf(FText, FBody.StartPos.Line);
  end;
  mLines := TTextLines.SplitLines(TRoutineBody.Reindent(ABodyText, mBodyIndent, '', FLineBreak));
  Result := '';
  for mIndex := 0 to High(mLines) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + FLineBreak + FWithIndent;
    end;
    Result := Result + mLines[mIndex];
  end;
end;

function TWithResolver.Run(out AResolved: TWithResolved): Boolean;
var
  mIndex: Integer;
  mBodyText, mNewText: string;
begin
  AResolved := Default(TWithResolved);
  Result := Prepare and CollectQualified;
  if Result then
  begin
    FLineBreak := TTextLines.LineBreakOf(FText);
    FWithIndent := TTextLines.IndentOf(FText, FWith.StartPos.Line);
    FInList := TRoutineBody.InList(FWith);
    mIndex := 0;
    while Result and (mIndex <= High(FItems)) do
    begin
      Result := not FUsed[mIndex] or PrefixElement(mIndex);
      Inc(mIndex);
    end;
  end;
  if not Result then
  begin
    AResolved.Reason := FReason;
    Exit;
  end;
  mBodyText := QualifiedBody;
  if (FBody.Kind = TSyntaxKind.Block) and FInList and StartsText('begin', mBodyText) and
    EndsText('end', mBodyText) then
  begin
    mNewText := UnwrappedBlock(mBodyText);
  end
  else
  begin
    mNewText := AlignedStatement(mBodyText);
  end;
  AResolved.Action.Title := 'with auflösen';
  AResolved.Action.Kind := RewriteKind;
  AResolved.Action.Edits := FEdits + [TTextEdit.Create(TTextRange.Create(FWith.StartPos, FWith.EndPos),
    FDeclarations + mNewText)];
end;

class function TWithResolution.Resolve(const AText: string; ATree: TSyntaxTree; AWith: TSyntaxNode;
  const ALookup: TWithOwnerLookup; const AOptions: TExtractOptions; out AAction: TCodeAction): Boolean;
var
  mResolved: TWithResolved;
begin
  Result := Resolve(AText, ATree, AWith, ALookup, AOptions, mResolved);
  AAction := mResolved.Action;
end;

class function TWithResolution.Resolve(const AText: string; ATree: TSyntaxTree; AWith: TSyntaxNode;
  const ALookup: TWithOwnerLookup; const AOptions: TExtractOptions; out AResolved: TWithResolved): Boolean;
var
  mResolver: TWithResolver;
begin
  mResolver := TWithResolver.Create(AText, ATree, AWith, ALookup, AOptions);
  try
    Result := mResolver.Run(AResolved);
  finally
    mResolver.Free;
  end;
end;

end.
