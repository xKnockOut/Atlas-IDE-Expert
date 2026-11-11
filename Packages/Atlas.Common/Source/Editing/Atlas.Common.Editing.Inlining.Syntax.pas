unit Atlas.Common.Editing.Inlining.Syntax;

// Gemeinsame Hilfen für „Einbetten“ (#103, Teil A): Namen und Aufrufe an
// einer Stelle finden, Ausdrücke klammern, Seiteneffekte erkennen,
// Anweisungen entfernen und neue Anweisungen bzw. Deklarationen schreiben.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.Inlining.Types;

const
  /// <summary>Bezeichner, die wie Literale nie ihren Wert ändern.</summary>
  cConstantNames: array[0..2] of string = ('True', 'False', 'MaxInt');

type
  TInlineSyntax = class
  public
    /// <summary>Bezeichner-Token, in dem oder direkt hinter dem AOffset liegt; -1 ohne.</summary>
    class function TokenContaining(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer; static;
    /// <summary>Identifier bzw. MemberAccess, dessen Name AOffset..AEnd belegt; nil ohne.</summary>
    class function NameNodeAt(ANode: TSyntaxNode; AOffset, AEnd: Integer): TSyntaxNode; static;
    /// <summary>Innerste Routine mit Rumpf, deren Deklaration AOffset enthält (auch var-Abschnitt); nil ohne.
    /// </summary>
    class function RoutineContaining(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode; static;
    class function IsSimpleChain(ANode: TSyntaxNode): Boolean; static;
    /// <summary>A.B.C → [A, B, C].</summary>
    class function ChainNames(ANode: TSyntaxNode): TArray<string>; static;
    /// <summary>Muss ein zusammengesetzter Ausdruck AExpression an der Stelle ATarget in Klammern?</summary>
    class function NeedsParens(AExpression, ATarget: TSyntaxNode): Boolean; static;
    class function Parenthesized(const AText: string; AExpression, ATarget: TSyntaxNode): string; static;
    /// <summary>Bezeichner ist der aufgerufene Name eines Aufrufs.</summary>
    class function IsCallee(ANode: TSyntaxNode): Boolean; static;
    class function Meaning(const ALookup: TInlineLookup; const ASource: TInlineSource; const ANames: TArray<string>;
      AOffset: Integer): TInlineMeaning; static;
    /// <summary>Aufruf ohne Seiteneffekte: Standardroutine der Liste oder Typumwandlung.</summary>
    class function CallIsPure(ACall: TSyntaxNode; const ASource: TInlineSource;
      const ALookup: TInlineLookup): Boolean; static;
    /// <summary>Hat der Ausdruck Seiteneffekte: Aufrufe außer reinen, inherited, Routinen ohne Klammern?</summary>
    class function HasSideEffects(ANode: TSyntaxNode; const ASource: TInlineSource;
      const ALookup: TInlineLookup): Boolean; static;
    class function NextSignificant(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer; static;
    /// <summary>Anweisung samt ";" entfernen; steht sie allein auf ihren Zeilen, die ganzen Zeilen.</summary>
    class function RemoveStatement(const AText: string; ATree: TSyntaxTree; AStatement: TSyntaxNode): TTextEdit;
      static;
    /// <summary>Liegt ANode in einer Schleife (bis ABody), die AOther nicht enthält?</summary>
    class function InLoopWithout(ANode, AOther, ABody: TSyntaxNode): Boolean; static;
    /// <summary>Liegt ANode (bis AStop) in einem Knoten der Art AKind?</summary>
    class function Inside(ANode: TSyntaxNode; AKind: TSyntaxKind; AStop: TSyntaxNode): Boolean; static;
    class function UsesName(ANode: TSyntaxNode; const AName: string): Boolean; static;
    /// <summary>Aufruf, dessen Name an APosition steht; False ohne.</summary>
    class function CallAt(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
      out ACall: TInlineCall): Boolean; static;
    /// <summary>Rümpfe (RoutineDecl mit Block) mit dem Namen AName ("TFoo.Bar" bzw. "Bar"), ohne
    /// verschachtelte Routinen.</summary>
    class function FindRoutines(ATree: TSyntaxTree; const AName: string): TArray<TSyntaxNode>; static;
    /// <summary>Schlüsselwort der Routine (procedure, function, constructor …) in Kleinbuchstaben.</summary>
    class function RoutineKeyword(const ATokens: TArray<TPascalToken>; ARoutine: TSyntaxNode): string; static;
    /// <summary>Anweisungen untereinander mit AIndent; die erste ohne, wenn AFirst False ist.</summary>
    class function JoinStatements(const ALines: TArray<string>; const AIndent, ALineBreak: string;
      AFirst: Boolean): string; static;
    /// <summary>Einträge im var- bzw. const-Abschnitt der Routine als eine Bearbeitung.</summary>
    class function SectionEdit(const AText: string; ARoutine: TSyntaxNode; AConstants: Boolean;
      const AEntries: TArray<string>; const AStyle: TFormatStyle): TTextEdit; static;
    class function Negated(const AText: string; ACondition: TSyntaxNode): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Pascal.PureRoutines;

const
  cLoopKinds = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
  cCompoundKinds = [TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.IfExpr, TSyntaxKind.RangeExpr];

class function TInlineSyntax.TokenContaining(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  mIndex: Integer;
begin
  mIndex := TRoutineBody.TokenAt(ATokens, AOffset);
  if (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset = AOffset) and
    (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) then
  begin
    Exit(mIndex);
  end;
  if (mIndex > 0) and (mIndex - 1 <= High(ATokens)) and
    (ATokens[mIndex - 1].Offset + Length(ATokens[mIndex - 1].Text) >= AOffset) and
    (ATokens[mIndex - 1].Kind = TPascalTokenKind.Identifier) then
  begin
    Exit(mIndex - 1);
  end;
  Result := -1;
end;

/// <summary>Belegt der Name von ANode genau AOffset..AEnd?</summary>
function IsNameNode(ANode: TSyntaxNode; AOffset, AEnd: Integer): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.Identifier:
      Result := (ANode.StartOffset = AOffset) and (ANode.EndOffset = AEnd);
    TSyntaxKind.MemberAccess:
      Result := (ANode.EndOffset = AEnd) and (AEnd - Length(ANode.Name) = AOffset);
  else
    Result := False;
  end;
end;

class function TInlineSyntax.NameNodeAt(ANode: TSyntaxNode; AOffset, AEnd: Integer): TSyntaxNode;
var
  mPending: TStack<TSyntaxPostOrderEntry>;
  mEntry: TSyntaxPostOrderEntry;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Eigener Stapel statt Rekursion; wie früher die Kinder vor dem Knoten selbst.
  Result := nil;
  mPending := TStack<TSyntaxPostOrderEntry>.Create;
  try
    mPending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
    while (mPending.Count > 0) and (Result = nil) do
    begin
      mEntry := mPending.Pop;
      mNode := mEntry.Node;
      if mEntry.Done then
      begin
        if IsNameNode(mNode, AOffset, AEnd) then
        begin
          Result := mNode;
        end;
      end
      else if (mNode.StartOffset <= AOffset) and (mNode.EndOffset >= AEnd) then
      begin
        mPending.Push(TSyntaxPostOrderEntry.Create(mNode, True));
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(TSyntaxPostOrderEntry.Create(mNode[mIndex], False));
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Erstes Kind von ANode, das AOffset enthält; nil ohne.</summary>
function ChildContaining(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if (ANode[mIndex].StartOffset <= AOffset) and (AOffset < ANode[mIndex].EndOffset) then
    begin
      Exit(ANode[mIndex]);
    end;
  end;
  Result := nil;
end;

class function TInlineSyntax.RoutineContaining(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mNode: TSyntaxNode;
begin
  // Schleife statt Rekursion: dem ersten Kind folgen, das AOffset enthält; die letzte Routine
  // auf dem Weg ist die innerste.
  Result := nil;
  mNode := ChildContaining(ANode, AOffset);
  while mNode <> nil do
  begin
    if (mNode.Kind = TSyntaxKind.RoutineDecl) and (TRoutineBody.BodyOf(mNode) <> nil) then
    begin
      Result := mNode;
    end;
    mNode := ChildContaining(mNode, AOffset);
  end;
end;

class function TInlineSyntax.IsSimpleChain(ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := ANode;
  while mNode.Kind = TSyntaxKind.MemberAccess do
  begin
    mNode := mNode[0];
  end;
  Result := mNode.Kind = TSyntaxKind.Identifier;
end;

class function TInlineSyntax.ChainNames(ANode: TSyntaxNode): TArray<string>;
var
  mNode: TSyntaxNode;
  mCount, mIndex: Integer;
begin
  // Schleife statt Rekursion.
  mCount := 0;
  mNode := ANode;
  while mNode.Kind = TSyntaxKind.MemberAccess do
  begin
    Inc(mCount);
    mNode := mNode[0];
  end;
  SetLength(Result, mCount + 1);
  mNode := ANode;
  for mIndex := mCount downto 1 do
  begin
    Result[mIndex] := mNode.Name;
    mNode := mNode[0];
  end;
  Result[0] := mNode.Name;
end;

class function TInlineSyntax.NeedsParens(AExpression, ATarget: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  Result := False;
  mParent := ATarget.Parent;
  if not (AExpression.Kind in cCompoundKinds) or (mParent = nil) then
  begin
    Exit;
  end;
  case mParent.Kind of
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.MemberAccess, TSyntaxKind.Dereference,
    TSyntaxKind.AddressOf:
      Result := True;
    TSyntaxKind.IndexAccess, TSyntaxKind.Call:
      Result := mParent[0] = ATarget;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TInlineSyntax.Parenthesized(const AText: string; AExpression, ATarget: TSyntaxNode): string;
begin
  if NeedsParens(AExpression, ATarget) then
  begin
    Result := '(' + AText + ')';
  end
  else
  begin
    Result := AText;
  end;
end;

class function TInlineSyntax.IsCallee(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Parent <> nil) and (((ANode.Parent.Kind = TSyntaxKind.Call) and (ANode.Parent[0] = ANode)) or
    (ANode.Parent.Kind = TSyntaxKind.CallStatement));
end;

class function TInlineSyntax.Meaning(const ALookup: TInlineLookup; const ASource: TInlineSource;
  const ANames: TArray<string>; AOffset: Integer): TInlineMeaning;
begin
  Result := Default(TInlineMeaning);
  if Assigned(ALookup) then
  begin
    Result := ALookup(ASource.Tree, ASource.FileName, ANames, AOffset);
  end;
end;

class function TInlineSyntax.CallIsPure(ACall: TSyntaxNode; const ASource: TInlineSource;
  const ALookup: TInlineLookup): Boolean;
var
  mCallee: TSyntaxNode;
  mFound: TInlineMeaning;
begin
  mCallee := ACall[0];
  if (mCallee.Kind = TSyntaxKind.Identifier) and TPureRoutines.IsPure(mCallee.Name) then
  begin
    Exit(True);
  end;
  Result := False;
  if Assigned(ALookup) and IsSimpleChain(mCallee) then
  begin
    mFound := Meaning(ALookup, ASource, ChainNames(mCallee), mCallee.StartOffset);
    Result := mFound.Found and mFound.IsType;
  end;
end;

/// <summary>Knoten der Art AKind in ANode.</summary>
function NodesOf(ANode: TSyntaxNode; const AKinds: array of TSyntaxKind): TArray<TSyntaxNode>;
var
  mNodes: TList<TSyntaxNode>;
  mKind: TSyntaxKind;
begin
  mNodes := TList<TSyntaxNode>.Create;
  try
    for mKind in AKinds do
    begin
      TRoutineLocals.CollectKind(ANode, mKind, mNodes);
    end;
    Result := mNodes.ToArray;
  finally
    mNodes.Free;
  end;
end;

/// <summary>Ruft ein Name ohne Klammern bzw. eine Kette (A.Next) eine Routine auf?</summary>
function CallsRoutineByName(ANode: TSyntaxNode; const ASource: TInlineSource; const ALookup: TInlineLookup): Boolean;
var
  mNode: TSyntaxNode;
  mFound: TInlineMeaning;
begin
  for mNode in NodesOf(ANode, [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) do
  begin
    if not TInlineSyntax.IsCallee(mNode) and TInlineSyntax.IsSimpleChain(mNode) then
    begin
      mFound := TInlineSyntax.Meaning(ALookup, ASource, TInlineSyntax.ChainNames(mNode), mNode.StartOffset);
      if mFound.Found and mFound.IsRoutine then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

class function TInlineSyntax.HasSideEffects(ANode: TSyntaxNode; const ASource: TInlineSource;
  const ALookup: TInlineLookup): Boolean;
var
  mNode: TSyntaxNode;
begin
  if TRoutineLocals.HasKind(ANode, TSyntaxKind.InheritedExpr) or
    TRoutineLocals.HasKind(ANode, TSyntaxKind.AnonymousMethod) then
  begin
    Exit(True);
  end;
  for mNode in NodesOf(ANode, [TSyntaxKind.Call]) do
  begin
    if not CallIsPure(mNode, ASource, ALookup) then
    begin
      Exit(True);
    end;
  end;
  Result := Assigned(ALookup) and CallsRoutineByName(ANode, ASource, ALookup);
end;

class function TInlineSyntax.NextSignificant(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and (ATokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(Result);
  end;
end;

class function TInlineSyntax.RemoveStatement(const AText: string; ATree: TSyntaxTree;
  AStatement: TSyntaxNode): TTextEdit;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mEndOffset, mLine: Integer;
  mLines: TLineTable;
  mEndPos: TTextPosition;
  mBefore, mAfter: string;
begin
  mTokens := ATree.Tokens;
  mEndOffset := AStatement.EndOffset;
  mIndex := NextSignificant(mTokens, TRoutineBody.TokenAt(mTokens, AStatement.EndOffset));
  if (mIndex <= High(mTokens)) and mTokens[mIndex].IsSymbol(';') then
  begin
    mEndOffset := mTokens[mIndex].Offset + 1;
  end;
  mLines := TLineTable.Build(AText);
  mEndPos := mLines.PositionAt(mEndOffset);
  mLine := AStatement.StartPos.Line;
  mBefore := Copy(AText, mLines.LineStart(mLine) + 1, AStatement.StartOffset - mLines.LineStart(mLine));
  mAfter := Copy(AText, mEndOffset + 1, mLines.LineContentEnd(mEndPos.Line) - mEndOffset);
  if (Trim(mBefore) = '') and (Trim(mAfter) = '') then
  begin
    Result := TTextEdit.Create(TTextRange.Create(mLine, 0, mEndPos.Line + 1, 0), '');
  end
  else
  begin
    Result := TTextEdit.Create(TTextRange.Create(AStatement.StartPos, mEndPos), '');
  end;
end;

class function TInlineSyntax.InLoopWithout(ANode, AOther, ABody: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := ANode.Parent;
  while (mNode <> nil) and (mNode <> ABody) do
  begin
    if (mNode.Kind in cLoopKinds) and not TRoutineBody.Within(AOther, mNode) then
    begin
      Exit(True);
    end;
    mNode := mNode.Parent;
  end;
  Result := False;
end;

class function TInlineSyntax.Inside(ANode: TSyntaxNode; AKind: TSyntaxKind; AStop: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := ANode.Parent;
  while (mNode <> nil) and (mNode <> AStop) do
  begin
    if mNode.Kind = AKind then
    begin
      Exit(True);
    end;
    mNode := mNode.Parent;
  end;
  Result := False;
end;

class function TInlineSyntax.UsesName(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mName: string;
begin
  mName := AName;
  // Search statt Rekursion.
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate.Kind = TSyntaxKind.Identifier) and SameText(ACandidate.Name, mName) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Name an APosition im Rumpf der Routine dort; nil ohne. AToken: sein Token.</summary>
function CallNameAt(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
  out AToken: TPascalToken): TSyntaxNode;
var
  mTokens: TArray<TPascalToken>;
  mToken: Integer;
  mRoutine: TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := ATree.Tokens;
  mToken := TInlineSyntax.TokenContaining(mTokens, TLineTable.Build(AText).OffsetAt(APosition));
  if mToken < 0 then
  begin
    Exit;
  end;
  AToken := mTokens[mToken];
  mRoutine := TRoutineBody.RoutineAt(ATree, AToken.Offset);
  if mRoutine <> nil then
  begin
    Result := TInlineSyntax.NameNodeAt(TRoutineBody.BodyOf(mRoutine), AToken.Offset,
      AToken.Offset + Length(AToken.Text));
  end;
end;

/// <summary>Qualifizierer (Foo in Foo.Bar), Ziel einer Zuweisung und @Foo sind keine Aufrufe.</summary>
function IsNoCall(AName: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := AName.Parent;
  if mParent = nil then
  begin
    Exit(True);
  end;
  case mParent.Kind of
    TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Dereference, TSyntaxKind.AssignStatement:
      Result := mParent[0] = AName;
    TSyntaxKind.AddressOf:
      Result := True;
  else
    Result := False;
  end;
end;

class function TInlineSyntax.CallAt(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
  out ACall: TInlineCall): Boolean;
var
  mToken: TPascalToken;
  mName, mParent: TSyntaxNode;
  mIndex: Integer;
begin
  ACall := Default(TInlineCall);
  mName := CallNameAt(ATree, AText, APosition, mToken);
  Result := (mName <> nil) and not IsNoCall(mName);
  if not Result then
  begin
    Exit;
  end;
  mParent := mName.Parent;
  ACall.Name := mName.Name;
  ACall.NameOffset := mToken.Offset;
  ACall.NamePos := mToken.StartPos;
  ACall.Callee := mName;
  ACall.Node := mName;
  if mName.Kind = TSyntaxKind.MemberAccess then
  begin
    ACall.Receiver := mName[0];
  end;
  if (mParent.Kind = TSyntaxKind.Call) and (mParent[0] = mName) then
  begin
    ACall.Node := mParent;
    for mIndex := 1 to mParent.ChildCount - 1 do
    begin
      ACall.Arguments := ACall.Arguments + [mParent[mIndex]];
    end;
  end;
  if (ACall.Node.Parent <> nil) and (ACall.Node.Parent.Kind = TSyntaxKind.CallStatement) then
  begin
    ACall.Statement := ACall.Node.Parent;
  end;
end;

/// <summary>Passt die Routine ARoutine zum Namen AName (kurz oder mit Klasse) und hat sie einen Rumpf?</summary>
function IsRoutineNamed(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  mShort: string;
begin
  mShort := ARoutine.Name;
  if (Pos('.', AName) = 0) and (Pos('.', mShort) > 0) then
  begin
    mShort := mShort.Substring(mShort.LastIndexOf('.') + 1);
  end;
  Result := SameText(mShort, AName) and (TRoutineBody.BodyOf(ARoutine) <> nil);
end;

class function TInlineSyntax.FindRoutines(ATree: TSyntaxTree; const AName: string): TArray<TSyntaxNode>;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  // Eigener Stapel statt Rekursion; Reihenfolge wie im Quelltext (Kinder rückwärts auf den Stapel).
  mPending := TStack<TSyntaxNode>.Create;
  try
    for mIndex := ATree.Root.ChildCount - 1 downto 0 do
    begin
      mPending.Push(ATree.Root[mIndex]);
    end;
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.RoutineDecl) and IsRoutineNamed(mNode, AName) then
      begin
        Result := Result + [mNode];
      end
      else if mNode.Kind in [TSyntaxKind.ImplementationSection, TSyntaxKind.InterfaceSection] then
      begin
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

class function TInlineSyntax.RoutineKeyword(const ATokens: TArray<TPascalToken>; ARoutine: TSyntaxNode): string;
var
  mIndex: Integer;
begin
  mIndex := NextSignificant(ATokens, TRoutineBody.TokenAt(ATokens, ARoutine.StartOffset));
  if (mIndex <= High(ATokens)) and ATokens[mIndex].IsKeyword('class') then
  begin
    mIndex := NextSignificant(ATokens, mIndex + 1);
  end;
  Result := '';
  if mIndex <= High(ATokens) then
  begin
    Result := LowerCase(ATokens[mIndex].Text);
  end;
end;

class function TInlineSyntax.JoinStatements(const ALines: TArray<string>; const AIndent, ALineBreak: string;
  AFirst: Boolean): string;
var
  mIndex: Integer;
  mPiece: string;
begin
  Result := '';
  for mIndex := 0 to High(ALines) do
  begin
    mPiece := TRoutineBody.Reindent(ALines[mIndex], '', AIndent, ALineBreak);
    if (mIndex = 0) and not AFirst then
    begin
      mPiece := Copy(mPiece, Length(AIndent) + 1, MaxInt);
    end;
    if mIndex > 0 then
    begin
      Result := Result + ';' + ALineBreak;
    end;
    Result := Result + mPiece;
  end;
end;

class function TInlineSyntax.SectionEdit(const AText: string; ARoutine: TSyntaxNode; AConstants: Boolean;
  const AEntries: TArray<string>; const AStyle: TFormatStyle): TTextEdit;
const
  cMarker = #1;
var
  mPlaceholder, mIndent, mEntries, mLineBreak: string;
  mStart, mIndex: Integer;
begin
  if AConstants then
  begin
    Result := TRoutineBody.AddConstant(AText, ARoutine, cMarker, cMarker, AStyle);
    mPlaceholder := cMarker + ' = ' + cMarker + ';';
  end
  else
  begin
    Result := TRoutineBody.AddVariable(AText, ARoutine, cMarker, cMarker, AStyle);
    mPlaceholder := cMarker + ': ' + cMarker + ';';
  end;
  mLineBreak := TTextLines.LineBreakOf(AText);
  mStart := Pos(mPlaceholder, Result.NewText);
  mIndex := mStart - 1;
  while (mIndex > 0) and (Result.NewText[mIndex] <> #10) do
  begin
    Dec(mIndex);
  end;
  mIndent := Copy(Result.NewText, mIndex + 1, mStart - mIndex - 1);
  mEntries := AEntries[0];
  for mIndex := 1 to High(AEntries) do
  begin
    mEntries := mEntries + mLineBreak + mIndent + AEntries[mIndex];
  end;
  Result.NewText := StringReplace(Result.NewText, mPlaceholder, mEntries, []);
end;

class function TInlineSyntax.Negated(const AText: string; ACondition: TSyntaxNode): string;
begin
  if ACondition.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Call, TSyntaxKind.MemberAccess,
    TSyntaxKind.ParenExpr, TSyntaxKind.IndexAccess, TSyntaxKind.Literal] then
  begin
    Result := 'not ' + AText;
  end
  else
  begin
    Result := 'not (' + AText + ')';
  end;
end;

end.
