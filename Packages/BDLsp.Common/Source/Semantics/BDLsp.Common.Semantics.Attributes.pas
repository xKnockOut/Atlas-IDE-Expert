unit BDLsp.Common.Semantics.Attributes;

// Attribute im Quelltext (#119): [TestFixture], [DUnitX.Attributes.TestFixture],
// [TestCase('A', '1,2')]. Liefert zur Position den geschriebenen Namen und die
// Zahl der Argumente; die Namensauflösung sucht damit zuerst NameAttribute,
// dann Name.

interface

uses
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.SyntaxTree;

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
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

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
  Left: string;
begin
  if ANode.Kind = TSyntaxKind.Identifier then
    Exit(ANode.Name);
  if (ANode.Kind <> TSyntaxKind.MemberAccess) or (ANode.ChildCount <> 1) then
    Exit('');
  Left := DottedName(ANode[0]);
  if Left = '' then
    Result := ''
  else
    Result := Left + '.' + ANode.Name;
end;

function FindAttribute(ANode: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
var
  Index: Integer;
begin
  if ANode.Kind = TSyntaxKind.Attribute then
    Exit(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
    if Contains(ANode[Index], APosition) then
    begin
      Result := FindAttribute(ANode[Index], APosition);
      if Result <> nil then
        Exit;
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

class function TAttributes.ClassNames(const AName: string): TArray<string>;
begin
  if EndsText('Attribute', AName) then
    Result := [AName]
  else
    Result := [AName + 'Attribute', AName];
end;

end.
