unit Atlas.Common.Editing.GenericLists.Syntax;

// Abfragen am Syntaxbaum, die die Umwandlung ungenerischer Listen (#1105, #1106) braucht: Namen, nil, Klammern,
// Zuweisungsziele, umgebende Routine und Abschnitt, Sichtbarkeit, Wörter hinter read/write und for var.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Zustandslose Abfragen am Syntaxbaum für die Listenumwandlung.</summary>
  TGenericListSyntax = record
    /// <summary>Letzter Namensteil, z. B. TPosition aus Unit.TPosition.</summary>
    class function LastName(const AText: string): string; static;
    /// <summary>ANode ist nil (Literal oder Bezeichner).</summary>
    class function IsNil(ANode: TSyntaxNode): Boolean; static;
    /// <summary>ANode ist der Bezeichner AName.</summary>
    class function IsIdentifierNamed(ANode: TSyntaxNode; const AName: string): Boolean; static;
    /// <summary>Ungeklammerter Ausdruck: steigt aus ParenExpr mit genau einem Kind auf.</summary>
    class function Unparen(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Inneres eines geklammerten Ausdrucks: steigt in ParenExpr mit genau einem Kind ab.</summary>
    class function Inner(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Kommagetrennte Namen ANames enthalten AName.</summary>
    class function ContainsName(const ANames, AName: string): Boolean; static;
    /// <summary>ANode ist das linke Ende einer Zuweisung (ANode := …).</summary>
    class function IsAssignTarget(ANode: TSyntaxNode): Boolean; static;
    /// <summary>Gegenüber von AOperand in einem Vergleich = oder &lt;&gt;; nil, wenn ACompare keiner ist.</summary>
    class function CompareOperand(ACompare, AOperand: TSyntaxNode): TSyntaxNode; static;
    /// <summary>ANode ist ein Aufruf mit Aufgerufenem und genau einem Argument.</summary>
    class function IsSingleArgumentCall(ANode: TSyntaxNode): Boolean; static;
    /// <summary>ANode ist X as T.</summary>
    class function IsAsCast(ANode: TSyntaxNode): Boolean; static;
    /// <summary>ANode ist ein Name (Bezeichner oder Unit.Name ohne Typargumente).</summary>
    class function IsPlainName(ANode: TSyntaxNode): Boolean; static;
    /// <summary>interface- bzw. implementation-Abschnitt an AOffset; nil außerhalb.</summary>
    class function SectionOf(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode; static;
    /// <summary>AOffset liegt im interface-Abschnitt.</summary>
    class function InInterface(ATree: TSyntaxTree; AOffset: Integer): Boolean; static;
    /// <summary>Kommentar oder Compiler-Direktive.</summary>
    class function IsTrivia(const AToken: TPascalToken): Boolean; static;
    /// <summary>Nächste Routine um ANode; nil außerhalb.</summary>
    class function EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>VarDecl im var-Abschnitt der Routine selbst; Parameter, Felder und globale Variablen zählen
    /// nicht.</summary>
    class function LocalDeclaration(ARoutine: TSyntaxNode; const AName: string): TSyntaxNode; static;
    /// <summary>Letzter Sichtbarkeitsabschnitt vor AMember in Kleinbuchstaben; ohne Angabe public.</summary>
    class function VisibilityOf(AMember: TSyntaxNode): string; static;
    /// <summary>AMember steht in einem privaten Abschnitt (private oder strict private).</summary>
    class function IsPrivate(AMember: TSyntaxNode): Boolean; static;
    /// <summary>Bezeichner hinter dem Wort AWord in den Token von ANode, z. B. das Feld hinter read; '' ohne.</summary>
    class function IdentifierAfter(ATree: TSyntaxTree; ANode: TSyntaxNode; const AWord: string): string; static;
    /// <summary>for var V in …: das Wort hinter for ist var.</summary>
    class function HasInlineVar(ATree: TSyntaxTree; ALoop: TSyntaxNode): Boolean; static;
    /// <summary>Liegt AFirst vor ASecond (oder darauf)?</summary>
    class function NotAfter(const AFirst, ASecond: TTextPosition): Boolean; static;
    /// <summary>ANode umfasst APosition.</summary>
    class function Covers(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean; static;
    /// <summary>Innerste Deklaration (Field, VarDecl, InlineVar, Parameter, PropertyDecl) in ANode, die APosition
    /// umfasst; nil ohne.</summary>
    class function DeclarationNodeAt(ANode: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

class function TGenericListSyntax.LastName(const AText: string): string;
var
  mDot: Integer;
begin
  Result := Trim(AText);
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
end;

class function TGenericListSyntax.IsNil(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in [TSyntaxKind.Literal, TSyntaxKind.Identifier]) and
    SameText(ANode.Name, 'nil');
end;

class function TGenericListSyntax.IsIdentifierNamed(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName);
end;

class function TGenericListSyntax.Unparen(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Parent <> nil) and (Result.Parent.Kind = TSyntaxKind.ParenExpr) and
    (Result.Parent.ChildCount = 1) do
  begin
    Result := Result.Parent;
  end;
end;

class function TGenericListSyntax.Inner(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
  begin
    Result := Result[0];
  end;
end;

class function TGenericListSyntax.ContainsName(const ANames, AName: string): Boolean;
var
  mName: string;
begin
  for mName in SplitString(ANames, ',') do
  begin
    if SameText(Trim(mName), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TGenericListSyntax.IsAssignTarget(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  Result := (mParent <> nil) and (mParent.Kind = TSyntaxKind.AssignStatement) and (mParent.ChildCount = 2) and
    (mParent[0] = ANode);
end;

class function TGenericListSyntax.CompareOperand(ACompare, AOperand: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ACompare.Kind <> TSyntaxKind.BinaryExpr) or not MatchText(ACompare.Name, ['=', '<>']) or
    (ACompare.ChildCount <> 2) then
  begin
    Exit;
  end;
  Result := ACompare[0];
  if Result = AOperand then
  begin
    Result := ACompare[1];
  end;
end;

class function TGenericListSyntax.IsSingleArgumentCall(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2);
end;

class function TGenericListSyntax.IsAsCast(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.BinaryExpr) and SameText(ANode.Name, 'as') and (ANode.ChildCount = 2);
end;

class function TGenericListSyntax.IsPlainName(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]);
end;

class function TGenericListSyntax.SectionOf(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := nil;
  for mIndex := 0 to ATree.Root.ChildCount - 1 do
  begin
    mChild := ATree.Root[mIndex];
    if (mChild.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]) and
      (mChild.StartOffset <= AOffset) and (mChild.EndOffset >= AOffset) then
    begin
      Exit(mChild);
    end;
  end;
end;

class function TGenericListSyntax.InInterface(ATree: TSyntaxTree; AOffset: Integer): Boolean;
var
  mSection: TSyntaxNode;
begin
  mSection := SectionOf(ATree, AOffset);
  Result := (mSection <> nil) and (mSection.Kind = TSyntaxKind.InterfaceSection);
end;

class function TGenericListSyntax.IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

class function TGenericListSyntax.EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    Result := Result.Parent;
  end;
end;

class function TGenericListSyntax.LocalDeclaration(ARoutine: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mIndex, mInner: Integer;
  mSection: TSyntaxNode;
begin
  Result := nil;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    mSection := ARoutine[mIndex];
    if mSection.Kind <> TSyntaxKind.VarSection then
    begin
      Continue;
    end;
    for mInner := 0 to mSection.ChildCount - 1 do
    begin
      if (mSection[mInner].Kind = TSyntaxKind.VarDecl) and ContainsName(mSection[mInner].Name, AName) then
      begin
        Exit(mSection[mInner]);
      end;
    end;
  end;
end;

class function TGenericListSyntax.VisibilityOf(AMember: TSyntaxNode): string;
var
  mParent: TSyntaxNode;
  mIndex: Integer;
begin
  Result := 'public';
  mParent := AMember.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParent.ChildCount - 1 do
  begin
    if mParent[mIndex] = AMember then
    begin
      Break;
    end;
    if mParent[mIndex].Kind = TSyntaxKind.Visibility then
    begin
      Result := LowerCase(mParent[mIndex].Name);
    end;
  end;
end;

class function TGenericListSyntax.IsPrivate(AMember: TSyntaxNode): Boolean;
begin
  Result := Pos('private', VisibilityOf(AMember)) > 0;
end;

class function TGenericListSyntax.IdentifierAfter(ATree: TSyntaxTree; ANode: TSyntaxNode;
  const AWord: string): string;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  Result := '';
  mTokens := ATree.Tokens;
  for mIndex := TSyntaxTree.FirstTokenOf(mTokens, ANode.StartOffset) to High(mTokens) - 1 do
  begin
    if (mTokens[mIndex].Offset >= ANode.StartOffset) and (mTokens[mIndex].Offset < ANode.EndOffset) and
      (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mIndex].Text, AWord) and
      (mTokens[mIndex + 1].Kind = TPascalTokenKind.Identifier) then
    begin
      Exit(mTokens[mIndex + 1].Text);
    end;
  end;
end;

class function TGenericListSyntax.HasInlineVar(ATree: TSyntaxTree; ALoop: TSyntaxNode): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mSeen: Integer;
begin
  mTokens := ATree.Tokens;
  mSeen := 0;
  for mIndex := TSyntaxTree.FirstTokenOf(mTokens, ALoop.StartOffset) to High(mTokens) do
  begin
    if (mTokens[mIndex].Offset < ALoop.StartOffset) or IsTrivia(mTokens[mIndex]) then
    begin
      Continue;
    end;
    Inc(mSeen);
    if mSeen = 2 then
    begin
      Exit(mTokens[mIndex].IsKeyword('var'));
    end;
  end;
  Result := False;
end;

class function TGenericListSyntax.NotAfter(const AFirst, ASecond: TTextPosition): Boolean;
begin
  Result := (AFirst.Line < ASecond.Line) or ((AFirst.Line = ASecond.Line) and (AFirst.Character <= ASecond.Character));
end;

class function TGenericListSyntax.Covers(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := NotAfter(ANode.StartPos, APosition) and NotAfter(APosition, ANode.EndPos);
end;

class function TGenericListSyntax.DeclarationNodeAt(ANode: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
var
  mChild: Integer;
  mFound: TSyntaxNode;
begin
  Result := nil;
  if not Covers(ANode, APosition) then
  begin
    Exit;
  end;
  if ANode.Kind in [TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.Parameter,
    TSyntaxKind.PropertyDecl] then
  begin
    Result := ANode;
  end;
  for mChild := 0 to ANode.ChildCount - 1 do
  begin
    mFound := DeclarationNodeAt(ANode[mChild], APosition);
    if mFound <> nil then
    begin
      Result := mFound;
    end;
  end;
end;

end.
