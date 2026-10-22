unit Atlas.Common.Semantics.Attributes;

// Attribute im Quelltext (#119): [TestFixture], [DUnitX.Attributes.TestFixture],
// [TestCase('A', '1,2')]. Liefert zur Position den geschriebenen Namen und die
// Zahl der Argumente; die Namensauflösung sucht damit zuerst NameAttribute,
// dann Name. Names liefert die Namen eines Attribut-Knotens ohne Endung
// Attribute und ohne Unit, z. B. für die DUnitX-Regeln (#945).

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TAttributeUse = record
    /// <summary>Name wie geschrieben, ggf. qualifiziert (DUnitX.Attributes.TestFixture).</summary>
    Name: string;
    /// <summary>Bereich des Namens (alle Teile).</summary>
    NameRange: TTextRange;
    /// <summary>Zahl der Argumente, 0 ohne Klammern.</summary>
    ArgCount: Integer;
  end;

  TAttributes = class
  public
    /// <summary>Steht APosition auf dem Namen eines Attributs?</summary>
    class function At(ATree: TSyntaxTree; const APosition: TTextPosition; out AUse: TAttributeUse): Boolean; static;
    /// <summary>Klassennamen in Suchreihenfolge: NameAttribute, dann Name.</summary>
    class function ClassNames(const AName: string): TArray<string>; static;
    /// <summary>Namen der Attribute im Knoten AAttribute ([Test, TestCase('a', '1')] → Test, TestCase): letzter
    /// Teil eines qualifizierten Namens, ohne Endung Attribute.</summary>
    class function Names(AAttribute: TSyntaxNode): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character <= B.Character));
end;

function Contains(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := Before(ANode.StartPos, APosition) and Before(APosition, ANode.EndPos);
end;

/// <summary>Name einer Bezeichner- bzw. Punktkette; '' bei anderen Ausdrücken.</summary>
function DottedName(ANode: TSyntaxNode): string;
var
  Suffix: string;
begin
  // Iterativ (Bericht M1): von rechts nach links an der Kette entlang.
  Suffix := '';
  while (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) do
  begin
    Suffix := '.' + ANode.Name + Suffix;
    ANode := ANode[0];
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
    Result := ANode.Name + Suffix
  else
    Result := '';
end;

function FindAttribute(ANode: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Iterativ mit eigenem Stapel (Bericht M1), Reihenfolge wie die frühere Rekursion.
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if Node.Kind = TSyntaxKind.Attribute then
        Exit(Node);
      for Index := Node.ChildCount - 1 downto 0 do
        if Contains(Node[Index], APosition) then
          Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
  Result := nil;
end;

class function TAttributes.At(ATree: TSyntaxTree; const APosition: TTextPosition; out AUse: TAttributeUse): Boolean;
var
  Attribute, Item, NameNode: TSyntaxNode;
  Index: Integer;
begin
  AUse := Default(TAttributeUse);
  if (ATree = nil) or (ATree.Root = nil) then
    Exit(False);
  Attribute := FindAttribute(ATree.Root, APosition);
  if Attribute = nil then
    Exit(False);
  for Index := 0 to Attribute.ChildCount - 1 do
  begin
    Item := Attribute[Index];
    NameNode := Item;
    if (Item.Kind = TSyntaxKind.Call) and (Item.ChildCount > 0) then
      NameNode := Item[0];
    if not Contains(NameNode, APosition) then
      Continue;
    AUse.Name := DottedName(NameNode);
    if AUse.Name = '' then
      Exit(False);
    AUse.NameRange := TTextRange.Create(NameNode.StartPos, NameNode.EndPos);
    if Item <> NameNode then
      AUse.ArgCount := Item.ChildCount - 1;
    Exit(True);
  end;
  Result := False;
end;

class function TAttributes.Names(AAttribute: TSyntaxNode): TArray<string>;
var
  Index, Dot: Integer;
  Item: TSyntaxNode;
  Name: string;
begin
  Result := nil;
  if (AAttribute = nil) or (AAttribute.Kind <> TSyntaxKind.Attribute) then
    Exit;
  for Index := 0 to AAttribute.ChildCount - 1 do
  begin
    Item := AAttribute[Index];
    if (Item.Kind = TSyntaxKind.Call) and (Item.ChildCount > 0) then
      Item := Item[0];
    Name := DottedName(Item);
    if Name = '' then
      Continue;
    Dot := LastDelimiter('.', Name);
    Name := Copy(Name, Dot + 1, MaxInt);
    if EndsText('Attribute', Name) and (Length(Name) > Length('Attribute')) then
      Name := Copy(Name, 1, Length(Name) - Length('Attribute'));
    Result := Result + [Name];
  end;
end;

class function TAttributes.ClassNames(const AName: string): TArray<string>;
begin
  if EndsText('Attribute', AName) then
    Result := [AName]
  else
    Result := [AName + 'Attribute', AName];
end;

end.
