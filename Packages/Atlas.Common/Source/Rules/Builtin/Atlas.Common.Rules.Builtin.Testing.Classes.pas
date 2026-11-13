unit Atlas.Common.Rules.Builtin.Testing.Classes;

// Klassen einer DUnitX-Testunit für die Testregeln (#1882): Jede Klassendeklaration der Datei (interface und
// implementation, nicht in Routinen) mit den Attributen davor ([TestFixture], [TestFixture('Name')]) und ihren
// Mitgliedern samt deren Attributen ([Test], [TestCase('A', '1,2')], [Setup] …). Attribute stehen im
// Syntaxbaum als Geschwister vor dem Knoten, zu dem sie gehören; hier werden sie ihm zugeordnet. Namen der
// Attribute ohne Unit und ohne Endung Attribute (DUnitX.TestFramework.TestCaseAttribute → TestCase).

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Mitglied einer Klasse mit den Einträgen der Attribute davor.</summary>
  TDUnitXMember = record
    /// <summary>RoutineHeader, Field, PropertyDecl …</summary>
    Node: TSyntaxNode;
    /// <summary>Einträge der Attributklammern davor: Identifier, MemberAccess oder Call mit Argumenten.</summary>
    Attributes: TArray<TSyntaxNode>;
  end;

  /// <summary>Eine Klassendeklaration mit Attributen und Mitgliedern.</summary>
  TDUnitXClass = record
    /// <summary>Der TypeDecl-Knoten.</summary>
    Decl: TSyntaxNode;
    /// <summary>Der ClassType-Knoten.</summary>
    Body: TSyntaxNode;
    /// <summary>Einträge der Attribute vor der Deklaration.</summary>
    Attributes: TArray<TSyntaxNode>;
    Members: TArray<TDUnitXMember>;
    /// <summary>Name ohne generische Parameter.</summary>
    function Name: string;
    /// <summary>Erster Name in class(...); '' ohne.</summary>
    function Ancestor: string;
    /// <summary>Generische Klasse (TListe&lt;T&gt;)?</summary>
    function IsGeneric: Boolean;
    /// <summary>Hat die Klasse selbst ein Attribut AName ([TestFixture])?</summary>
    function HasAttribute(const AName: string): Boolean;
    /// <summary>Hat ein Mitglied ein Attribut aus ANames?</summary>
    function HasMemberWith(const ANames: array of string): Boolean;
  end;

  TDUnitXClasses = class
  public
    /// <summary>Alle Klassendeklarationen unter ARoot, in der Reihenfolge der Datei.</summary>
    class function Collect(ARoot: TSyntaxNode): TArray<TDUnitXClass>; static;
    /// <summary>Kurzname eines Attribut-Eintrags: TestCase für TestCase('A', '1'),
    /// DUnitX.TestFramework.TestCaseAttribute(…) und TestCase; '' für anderes.</summary>
    class function ItemName(AItem: TSyntaxNode): string; static;
    /// <summary>Enthält AItems einen Eintrag mit dem Kurznamen AName?</summary>
    class function HasItem(const AItems: TArray<TSyntaxNode>; const AName: string): Boolean; static;
    /// <summary>Argumente eines Eintrags (ohne den Namen); nil ohne Klammern.</summary>
    class function Arguments(AItem: TSyntaxNode): TArray<TSyntaxNode>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Semantics.Attributes;

/// <summary>Einträge eines Attribut-Knotens ([Test, TestCase('a', '1')] → zwei).</summary>
function ItemsOf(AAttribute: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, AAttribute.ChildCount);
  for mIndex := 0 to AAttribute.ChildCount - 1 do
  begin
    Result[mIndex] := AAttribute[mIndex];
  end;
end;

function MembersOf(ABody: TSyntaxNode): TArray<TDUnitXMember>;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
  mPending: TArray<TSyntaxNode>;
  mMember: TDUnitXMember;
begin
  Result := nil;
  mPending := nil;
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    mChild := ABody[mIndex];
    if mChild.Kind = TSyntaxKind.Attribute then
    begin
      mPending := mPending + ItemsOf(mChild);
      Continue;
    end;
    if mChild.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.Field, TSyntaxKind.PropertyDecl] then
    begin
      mMember.Node := mChild;
      mMember.Attributes := mPending;
      Result := Result + [mMember];
    end;
    mPending := nil;
  end;
end;

{ TDUnitXClass }

function TDUnitXClass.Name: string;
begin
  Result := Decl.Name;
end;

function TDUnitXClass.Ancestor: string;
var
  mFirst: TSyntaxNode;
begin
  Result := '';
  if Body.ChildCount = 0 then
  begin
    Exit;
  end;
  mFirst := Body[0];
  if mFirst.Kind = TSyntaxKind.TypeReference then
  begin
    Result := mFirst.Name;
  end;
end;

function TDUnitXClass.IsGeneric: Boolean;
begin
  Result := Decl.FindChild(TSyntaxKind.GenericParams) <> nil;
end;

function TDUnitXClass.HasAttribute(const AName: string): Boolean;
begin
  Result := TDUnitXClasses.HasItem(Attributes, AName);
end;

function TDUnitXClass.HasMemberWith(const ANames: array of string): Boolean;
var
  mMember: TDUnitXMember;
  mName: string;
begin
  for mMember in Members do
  begin
    for mName in ANames do
    begin
      if TDUnitXClasses.HasItem(mMember.Attributes, mName) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

{ TDUnitXClasses }

class function TDUnitXClasses.ItemName(AItem: TSyntaxNode): string;
var
  mNameNode: TSyntaxNode;
begin
  mNameNode := AItem;
  if (AItem.Kind = TSyntaxKind.Call) and (AItem.ChildCount > 0) then
  begin
    mNameNode := AItem[0];
  end;
  if mNameNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
  begin
    Result := TAttributes.ShortName(mNameNode.Name);
  end
  else
  begin
    Result := '';
  end;
end;

class function TDUnitXClasses.HasItem(const AItems: TArray<TSyntaxNode>; const AName: string): Boolean;
var
  mItem: TSyntaxNode;
begin
  for mItem in AItems do
  begin
    if SameText(ItemName(mItem), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TDUnitXClasses.Arguments(AItem: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  if AItem.Kind <> TSyntaxKind.Call then
  begin
    Exit;
  end;
  SetLength(Result, AItem.ChildCount - 1);
  for mIndex := 1 to AItem.ChildCount - 1 do
  begin
    Result[mIndex - 1] := AItem[mIndex];
  end;
end;

/// <summary>Klassen eines Typabschnitts mit den Attributen davor an AResult anhängen.</summary>
procedure CollectSection(ASection: TSyntaxNode; var AResult: TArray<TDUnitXClass>);
var
  mIndex: Integer;
  mChild, mBody: TSyntaxNode;
  mAttributes: TArray<TSyntaxNode>;
  mClass: TDUnitXClass;
begin
  mAttributes := nil;
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    mChild := ASection[mIndex];
    if mChild.Kind = TSyntaxKind.Attribute then
    begin
      mAttributes := mAttributes + ItemsOf(mChild);
      Continue;
    end;
    mBody := nil;
    if mChild.Kind = TSyntaxKind.TypeDecl then
    begin
      mBody := mChild.FindChild(TSyntaxKind.ClassType);
    end;
    if mBody <> nil then
    begin
      mClass.Decl := mChild;
      mClass.Body := mBody;
      mClass.Attributes := mAttributes;
      mClass.Members := MembersOf(mBody);
      AResult := AResult + [mClass];
    end;
    mAttributes := nil;
  end;
end;

class function TDUnitXClasses.Collect(ARoot: TSyntaxNode): TArray<TDUnitXClass>;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  if ARoot = nil then
  begin
    Exit;
  end;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht); Typabschnitte in Routinen zählen nicht.
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.TypeSection then
      begin
        CollectSection(mNode, Result);
      end
      else if not (mNode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.Block]) then
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

end.
