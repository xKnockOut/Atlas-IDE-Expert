unit Atlas.Common.Rules.Builtin.Collections;

// Regeln für Listen und andere Sammlungen (#909, Gruppe Stil und Metriken):
//   legacy-tlist  Ungenerische TList (System.Classes) bzw. TObjectList
//                 (System.Contnrs) mit Cast beim Lesen (#981, Standard aus).
//
// TLegacyCollections.Reads sucht Casts T(Liste[I]), T(Liste.Items[I]),
// T(Liste.First), Liste[I] as T usw. im Syntaxbaum und löst Sammlung und
// Zieltyp über TNameResolver auf. Gemeldet wird nur, wenn der Typ der
// Sammlung sicher die ungenerische Klasse aus der RTL ist und der Zieltyp ein
// bekannter Typ (kein Pointer). Je Sammlung gibt es einen Treffer: an der
// Deklaration, wenn sie in der Datei steht, sonst am ersten Cast. Die
// Schnellkorrektur folgt in #1105, Stapel und Warteschlangen in #1106.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  LegacyTListRuleId = 'legacy-tlist';

type
  /// <summary>Ungenerische Sammlung der RTL: Unit (mit und ohne Namespace) und Klassenname.</summary>
  TLegacyCollectionType = record
    UnitName: string;
    ShortUnitName: string;
    TypeName: string;
    constructor Create(const AUnitName, AShortUnitName, ATypeName: string);
  end;

  /// <summary>Ein Lesezugriff mit Cast auf eine ungenerische Sammlung.</summary>
  TLegacyCollectionRead = record
    /// <summary>Der ganze Cast: T(Liste[I]) bzw. Liste[I] as T.</summary>
    Cast: TSyntaxNode;
    /// <summary>Ausdruck der Sammlung, z. B. FPositionen oder Self.FPositionen.</summary>
    Collection: TSyntaxNode;
    /// <summary>Deklaration der Sammlung (Variable, Feld, Property, Parameter).</summary>
    Symbol: TResolvedSymbol;
    /// <summary>Klasse der Sammlung, z. B. System.Classes.TList.</summary>
    CollectionType: TResolvedSymbol;
    /// <summary>Zieltyp des Casts.</summary>
    CastType: TResolvedSymbol;
    /// <summary>Schlüssel der Deklaration: gleiche Sammlung, gleicher Schlüssel.</summary>
    function Key: string;
  end;

  TLegacyCollections = class
  public
    /// <summary>Alle Lesezugriffe mit Cast auf Sammlungen der Typen ATypes. AMembers sind die Methoden und
    /// Properties, die ein Element liefern (First, Last, Pop …); AIndexed: auch Liste[I] und Liste.Items[I].
    /// AResolver muss auf ATree gepinnt sein.</summary>
    class function Reads(ATree: TSyntaxTree; const AFileName: string; AResolver: TNameResolver;
      const ATypes: TArray<TLegacyCollectionType>; const AMembers: TArray<string>;
      AIndexed: Boolean): TArray<TLegacyCollectionRead>; static;
    /// <summary>Steht die Deklaration ASymbol in der Datei AFileName?</summary>
    class function DeclaredIn(const ASymbol: TResolvedSymbol; const AFileName: string): Boolean; static;
  end;

  TLegacyTListRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterCollectionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract;

{ TLegacyCollectionType }

constructor TLegacyCollectionType.Create(const AUnitName, AShortUnitName, ATypeName: string);
begin
  UnitName := AUnitName;
  ShortUnitName := AShortUnitName;
  TypeName := ATypeName;
end;

{ TLegacyCollectionRead }

function TLegacyCollectionRead.Key: string;
begin
  Result := LowerCase(Symbol.UnitName + '|' + Symbol.FileName + '|' + Symbol.Container + '|' + Symbol.Name) + '|' +
    IntToStr(Symbol.SelectionRange.StartPos.Line) + ':' + IntToStr(Symbol.SelectionRange.StartPos.Character);
end;

{ TLegacyCollections }

/// <summary>Ausdruck ohne umschließende Klammern.</summary>
function Unparenthesized(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
    Result := Result[0];
end;

function IsMember(const AName: string; const AMembers: TArray<string>): Boolean;
var
  Member: string;
begin
  Result := False;
  for Member in AMembers do
    if SameText(Member, AName) then
      Exit(True);
end;

class function TLegacyCollections.DeclaredIn(const ASymbol: TResolvedSymbol; const AFileName: string): Boolean;
begin
  Result := (ASymbol.Kind = TResolvedKind.Local) or
    ((ASymbol.Kind = TResolvedKind.Symbol) and SameText(ASymbol.FileName, AFileName));
end;

class function TLegacyCollections.Reads(ATree: TSyntaxTree; const AFileName: string; AResolver: TNameResolver;
  const ATypes: TArray<TLegacyCollectionType>; const AMembers: TArray<string>;
  AIndexed: Boolean): TArray<TLegacyCollectionRead>;
var
  Found: TList<TLegacyCollectionRead>;

  /// <summary>Ist ANode sicher eine Sammlung der gesuchten Typen? Dann Deklaration und Typ.</summary>
  function IsLegacyCollection(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
  var
    TypeFound: Boolean;
    Wanted: TLegacyCollectionType;
  begin
    Result := False;
    if (ANode = nil) or not (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess,
      TSyntaxKind.IndexAccess, TSyntaxKind.Call]) then
      Exit;
    if not AResolver.NodeType(ATree, AFileName, ANode, ASymbol, AType, TypeFound) or not TypeFound or
      ASymbol.IsType or not AType.IsType or (AType.TypeParams <> '') or (Pos('<', ASymbol.TypeName) > 0) then
      Exit;
    for Wanted in ATypes do
      if SameText(AType.Name, Wanted.TypeName) and (SameText(AType.UnitName, Wanted.UnitName) or
        SameText(AType.UnitName, Wanted.ShortUnitName)) then
        Exit(True);
  end;

  /// <summary>Liest AValue ein Element einer gesuchten Sammlung? Dann deren Ausdruck, Deklaration und Typ.
  /// </summary>
  function ElementRead(AValue: TSyntaxNode; out ACollection: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
  var
    Base: TSyntaxNode;
  begin
    Result := False;
    ACollection := nil;
    AValue := Unparenthesized(AValue);
    if AValue = nil then
      Exit;
    case AValue.Kind of
      TSyntaxKind.IndexAccess:
        begin
          // Liste[I], Liste.Items[I], Objekt.Liste[I]
          if not AIndexed or (AValue.ChildCount <> 2) then
            Exit;
          Base := AValue[0];
          if (Base.Kind = TSyntaxKind.MemberAccess) and SameText(Base.Name, 'Items') and (Base.ChildCount = 1) and
            IsLegacyCollection(Base[0], ASymbol, AType) then
          begin
            ACollection := Base[0];
            Exit(True);
          end;
          if IsLegacyCollection(Base, ASymbol, AType) then
          begin
            ACollection := Base;
            Exit(True);
          end;
        end;
      TSyntaxKind.MemberAccess:
        // Liste.First, Stapel.Pop
        if (AValue.ChildCount = 1) and IsMember(AValue.Name, AMembers) and
          IsLegacyCollection(AValue[0], ASymbol, AType) then
        begin
          ACollection := AValue[0];
          Exit(True);
        end;
      TSyntaxKind.Call:
        // Liste.First(), Liste.Extract(Element)
        if (AValue.ChildCount >= 1) and (AValue[0].Kind = TSyntaxKind.MemberAccess) and
          (AValue[0].ChildCount = 1) and IsMember(AValue[0].Name, AMembers) and
          IsLegacyCollection(AValue[0][0], ASymbol, AType) then
        begin
          ACollection := AValue[0][0];
          Exit(True);
        end;
    end;
  end;

  /// <summary>Bezeichnet ANode sicher einen Typ, der als Element taugt?</summary>
  function IsCastType(ANode: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
  var
    Symbol: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    Result := False;
    if (ANode = nil) or (ANode.Kind <> TSyntaxKind.Identifier) or SameText(ANode.Name, 'Pointer') then
      Exit;
    if not AResolver.NodeType(ATree, AFileName, ANode, Symbol, AType, TypeFound) or not Symbol.IsType then
      Exit;
    AType := Symbol;
    Result := not SameText(Symbol.Name, 'Pointer');
  end;

  procedure Add(ACast, AValue, ATypeNode: TSyntaxNode);
  var
    Read: TLegacyCollectionRead;
  begin
    if not ElementRead(AValue, Read.Collection, Read.Symbol, Read.CollectionType) or
      not IsCastType(ATypeNode, Read.CastType) then
      Exit;
    Read.Cast := ACast;
    Found.Add(Read);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    // T(Wert): Aufruf mit einem Argument, dessen Name ein Typ ist.
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and (ANode[0].Kind = TSyntaxKind.Identifier) then
      Add(ANode, ANode[1], ANode[0])
    // Wert as T
    else if (ANode.Kind = TSyntaxKind.BinaryExpr) and SameText(ANode.Name, 'as') and (ANode.ChildCount = 2) then
      Add(ANode, ANode[0], Unparenthesized(ANode[1]));
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Found := TList<TLegacyCollectionRead>.Create;
  try
    Visit(ATree.Root);
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

{ TLegacyTListRule }

function TLegacyTListRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(LegacyTListRuleId, TRuleSeverity.Information, 'Ungenerische Liste mit Cast',
    True);
end;

procedure TLegacyTListRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  FileName, Key, Message: string;
  Reads: TArray<TLegacyCollectionRead>;
  Read, First: TLegacyCollectionRead;
  Keys: TList<string>;
  CastTypes: TList<string>;
  Range: TTextRange;
  Index: Integer;
begin
  // Kein Vorfilter über den Text: Die Liste kann in einer anderen Unit deklariert sein (Objekt.Liste[I]).
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.Index = nil) then
    Exit;
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Keys := nil;
  CastTypes := nil;
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Reads := TLegacyCollections.Reads(AContext.Tree, FileName, Resolver,
        [TLegacyCollectionType.Create('System.Classes', 'Classes', 'TList'),
        TLegacyCollectionType.Create('System.Contnrs', 'Contnrs', 'TObjectList')], ['First', 'Last', 'Extract'],
        True);
    finally
      Resolver.UnpinTree;
    end;
    Keys := TList<string>.Create;
    CastTypes := TList<string>.Create;
    // Je Sammlung ein Treffer mit allen Zieltypen ihrer Casts.
    for Read in Reads do
    begin
      Key := Read.Key;
      if Keys.Contains(Key) then
        Continue;
      Keys.Add(Key);
      First := Read;
      CastTypes.Clear;
      for Index := 0 to High(Reads) do
        if (Reads[Index].Key = Key) and not CastTypes.Contains(Reads[Index].CastType.Name) then
          CastTypes.Add(Reads[Index].CastType.Name);
      if CastTypes.Count = 1 then
        Message := Format('Ungenerische %s mit Cast beim Lesen; %s<%s> prüft den Typ beim Übersetzen.',
          [First.CollectionType.Name, First.CollectionType.Name, CastTypes[0]])
      else
        Message := Format('Ungenerische %s mit Casts auf %s beim Lesen; eine generische Liste prüft den Typ ' +
          'beim Übersetzen.', [First.CollectionType.Name, string.Join(', ', CastTypes.ToArray)]);
      if TLegacyCollections.DeclaredIn(First.Symbol, FileName) then
        Range := First.Symbol.SelectionRange
      else
        Range := TTextRange.Create(First.Cast.StartPos, First.Cast.EndPos);
      AReport.Add(Range, Message, TRuleConfidence.High);
    end;
  finally
    CastTypes.Free;
    Keys.Free;
    Resolver.Free;
  end;
end;

procedure RegisterCollectionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TLegacyTListRule.Create);
end;

end.
