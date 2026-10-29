unit Atlas.Common.Semantics.Attributes;

// Attribute im Quelltext (#119): [TestFixture], [DUnitX.Attributes.TestFixture],
// [TestCase('A', '1,2')]. Liefert zur Position den geschriebenen Namen und die
// Zahl der Argumente; die Namensauflösung sucht damit zuerst NameAttribute,
// dann Name. Names liefert die Namen eines Attribut-Knotens ohne Endung
// Attribute und ohne Unit, z. B. für die DUnitX-Regeln (#945).
// Opens und InBracket (#465) arbeiten nur auf Tokens, auch bei unfertigem Code
// ("[Te" vor einer Methode): Eine "[" eröffnet ein Attribut, wenn davor eine
// Deklaration enden oder beginnen kann (";", type, var, const, class, record,
// ")" hinter class(...) bzw. einer Parameterliste, "(" einer Parameterliste) oder
// sie am Zeilenanfang hinter einer Sichtbarkeit bzw. einem anderen Attribut
// steht. Mengen ("in [", "= ["), Array-Indizes ("A[") und die GUID eines
// Interfaces ("interface [") zählen nicht.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
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
    /// <summary>Eröffnet die "[" an AOpen ein Attribut (siehe oben)?</summary>
    class function Opens(const ATokens: TArray<TPascalToken>; AOpen: Integer): Boolean; static;
    /// <summary>Steht ein Name hinter dem Token ALast ("[" bzw. "," einer Attributklammer) auf der Stelle
    /// eines Attributnamens? Nicht in den Argumenten eines Attributs.</summary>
    class function InBracket(const ATokens: TArray<TPascalToken>; ALast: Integer): Boolean; static;
    /// <summary>Name ohne Endung Attribute ("TestCaseAttribute" → "TestCase"); "Attribute" selbst bleibt.</summary>
    class function ShortName(const AName: string): string; static;
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

const
  /// <summary>Tiefe für Ketten wie [A] [B] [C] am Zeilenanfang.</summary>
  MaxChainedBrackets = 16;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function PreviousIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

/// <summary>Öffnende Klammer zu der schließenden an AClose ("(" zu ")", "[" zu "]"); -1 ohne.</summary>
function OpeningOf(const ATokens: TArray<TPascalToken>; AClose: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  Result := AClose;
  while Result >= 0 do
  begin
    if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
      Inc(Depth)
    else if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit;
    end;
    Dec(Result);
  end;
end;

/// <summary>Steht vor der "(" an AOpen der Kopf einer Routine ("procedure Foo(", "function TFoo.Bar(",
/// "reference to procedure(")?</summary>
function OpensParameters(const ATokens: TArray<TPascalToken>; AOpen: Integer): Boolean;
var
  Index: Integer;
begin
  Index := PreviousIndex(ATokens, AOpen);
  while (Index >= 0) and ((ATokens[Index].Kind = TPascalTokenKind.Identifier) or ATokens[Index].IsSymbol('.')) do
    Index := PreviousIndex(ATokens, Index);
  Result := (Index >= 0) and (ATokens[Index].IsKeyword('procedure') or ATokens[Index].IsKeyword('function') or
    ATokens[Index].IsKeyword('constructor') or ATokens[Index].IsKeyword('destructor') or
    ATokens[Index].IsKeyword('property'));
end;

/// <summary>Steht vor der "(" an AOpen class, record oder object (Vorfahrenliste)?</summary>
function OpensAncestors(const ATokens: TArray<TPascalToken>; AOpen: Integer): Boolean;
var
  Index: Integer;
begin
  Index := PreviousIndex(ATokens, AOpen);
  Result := (Index >= 0) and (ATokens[Index].IsKeyword('class') or ATokens[Index].IsKeyword('object'));
end;

function IsVisibility(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Identifier) and (SameText(AToken.Text, 'private') or
    SameText(AToken.Text, 'protected') or SameText(AToken.Text, 'public') or SameText(AToken.Text, 'published') or
    SameText(AToken.Text, 'automated'));
end;

function OpensAt(const ATokens: TArray<TPascalToken>; AOpen, ADepth: Integer): Boolean;
var
  Prev, Before: Integer;
  LineStart: Boolean;
begin
  Result := False;
  if (AOpen < 0) or (AOpen > High(ATokens)) or not ATokens[AOpen].IsSymbol('[') or (ADepth > MaxChainedBrackets) then
    Exit;
  Prev := PreviousIndex(ATokens, AOpen);
  if Prev < 0 then
    Exit(True);
  LineStart := ATokens[Prev].EndPos.Line < ATokens[AOpen].StartPos.Line;
  if ATokens[Prev].IsSymbol(';') then
    Exit(True);
  if ATokens[Prev].Kind = TPascalTokenKind.Keyword then
  begin
    // "IFoo = interface [" ist die GUID; "interface" als Abschnitt steht hinter "unit X;".
    if ATokens[Prev].IsKeyword('interface') or ATokens[Prev].IsKeyword('dispinterface') then
    begin
      Before := PreviousIndex(ATokens, Prev);
      Exit((Before < 0) or not ATokens[Before].IsSymbol('='));
    end;
    Exit(ATokens[Prev].IsKeyword('type') or ATokens[Prev].IsKeyword('var') or ATokens[Prev].IsKeyword('const') or
      ATokens[Prev].IsKeyword('threadvar') or ATokens[Prev].IsKeyword('class') or
      ATokens[Prev].IsKeyword('record') or ATokens[Prev].IsKeyword('object') or
      ATokens[Prev].IsKeyword('implementation'));
  end;
  // Parameter: "procedure Foo([Ref] const A".
  if ATokens[Prev].IsSymbol('(') then
    Exit(OpensParameters(ATokens, Prev));
  // "TFoo = class(TBasis)" und darunter das Attribut eines Felds.
  if ATokens[Prev].IsSymbol(')') then
  begin
    Before := OpeningOf(ATokens, Prev);
    Exit(LineStart and (Before >= 0) and (OpensAncestors(ATokens, Before) or OpensParameters(ATokens, Before)));
  end;
  // Sichtbarkeit und weitere Attribute nur am Zeilenanfang: "Private[0]" und "A[1][2]" sind Indizes.
  if not LineStart then
    Exit;
  if IsVisibility(ATokens[Prev]) then
    Exit(True);
  if ATokens[Prev].IsSymbol(']') then
    Exit(OpensAt(ATokens, OpeningOf(ATokens, Prev), ADepth + 1));
end;

class function TAttributes.Opens(const ATokens: TArray<TPascalToken>; AOpen: Integer): Boolean;
begin
  Result := OpensAt(ATokens, AOpen, 0);
end;

class function TAttributes.InBracket(const ATokens: TArray<TPascalToken>; ALast: Integer): Boolean;
var
  Index, Depth: Integer;
begin
  Result := False;
  if (ALast < 0) or (ALast > High(ATokens)) then
    Exit;
  if ATokens[ALast].IsSymbol('[') then
    Exit(Opens(ATokens, ALast));
  if not ATokens[ALast].IsSymbol(',') then
    Exit;
  // Zur offenen "[" zurück; eine offene "(" davor heißt: in den Argumenten.
  Depth := 0;
  Index := PreviousIndex(ATokens, ALast);
  while Index >= 0 do
  begin
    if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']') then
      Inc(Depth)
    else if ATokens[Index].IsSymbol('(') then
    begin
      if Depth = 0 then
        Exit;
      Dec(Depth);
    end
    else if ATokens[Index].IsSymbol('[') then
    begin
      if Depth = 0 then
        Exit(Opens(ATokens, Index));
      Dec(Depth);
    end
    else if (Depth = 0) and (ATokens[Index].IsSymbol(';') or (ATokens[Index].Kind = TPascalTokenKind.Keyword)) then
      Exit;
    Index := PreviousIndex(ATokens, Index);
  end;
end;

class function TAttributes.ShortName(const AName: string): string;
begin
  Result := AName;
  if EndsText('Attribute', Result) and (Length(Result) > Length('Attribute')) then
    Result := Copy(Result, 1, Length(Result) - Length('Attribute'));
end;

class function TAttributes.ClassNames(const AName: string): TArray<string>;
begin
  if EndsText('Attribute', AName) then
    Result := [AName]
  else
    Result := [AName + 'Attribute', AName];
end;

end.
