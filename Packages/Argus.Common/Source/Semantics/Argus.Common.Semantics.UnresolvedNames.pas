unit Argus.Common.Semantics.UnresolvedNames;

// Bezeichner, die sich nicht auflösen lassen (#178), für das MCP-Werkzeug
// check_code. Bewusst vorsichtig, weil die Namensauflösung nur die
// Grundstufe kennt:
// - geprüft wird nur der erste Name einer Kette (A in A.B.C) in
//   Anweisungen, nicht in Deklarationen;
// - with-Blöcke, asm und anonyme Methoden werden übersprungen;
// - Compiler-Intrinsics (Length, Inc, Exit, …) gelten als bekannt;
// - ohne Unit System im Index wird gar nichts gemeldet, weil dann jeder
//   RTL-Name fehlen würde.

interface

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Index.Contract,
  Argus.Common.Semantics.NameResolver;

type
  TUnresolvedName = record
    Name: string;
    Range: TTextRange;
  end;

  TUnresolvedNames = class
  public const
    MaxNames = 100;
  public
    /// <summary>True, wenn der Index die Unit System kennt und die Prüfung damit aussagekräftig ist.</summary>
    class function Available(const AIndex: ISymbolIndex): Boolean; static;
    /// <summary>Nicht auflösbare Namen in ATree, höchstens MaxNames.</summary>
    class function Find(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string): TArray<TUnresolvedName>; static;
    /// <summary>Vom Compiler eingebaute Routinen und Konstanten ohne Deklaration in System.pas.</summary>
    class function IsIntrinsic(const AName: string): Boolean; static;
  end;

implementation

const
  Intrinsics: array[0..55] of string = (
    'Abs', 'Addr', 'Assert', 'Assigned', 'Break', 'Chr', 'Concat', 'Continue', 'Copy', 'Dec', 'Default',
    'Delete', 'Dispose', 'Exclude', 'Exit', 'False', 'FillChar', 'Finalize', 'GetTypeKind', 'Halt', 'HasWeakRef',
    'Hi', 'High', 'Inc', 'Include', 'Initialize', 'Insert', 'IsConstValue', 'IsManagedType', 'Length', 'Lo', 'Low',
    'Move', 'New', 'nil', 'Odd', 'Ord', 'Pred', 'Ptr', 'Read', 'ReadLn', 'Result', 'Round', 'Self', 'SetLength',
    'SetString', 'SizeOf', 'Slice', 'Str', 'Succ', 'Swap', 'True', 'Trunc', 'TypeInfo', 'Write', 'WriteLn');

class function TUnresolvedNames.IsIntrinsic(const AName: string): Boolean;
var
  Name: string;
begin
  for Name in Intrinsics do
    if SameText(Name, AName) then
      Exit(True);
  Result := False;
end;

class function TUnresolvedNames.Available(const AIndex: ISymbolIndex): Boolean;
var
  SystemUnit: TUnitIndex;
begin
  Result := (AIndex <> nil) and AIndex.FindUnit('System', SystemUnit);
end;

class function TUnresolvedNames.Find(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TArray<TUnresolvedName>;
var
  Declared: TArray<string>;

  function IsDeclared(const AName: string): Boolean;
  var
    Name: string;
  begin
    for Name in Declared do
      if SameText(Name, AName) then
        Exit(True);
    Result := False;
  end;

  // Namen, die die Grundstufe nicht sicher als lokal kennt: Ausnahmevariablen und Inline-Variablen.
  procedure CollectDeclared(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if (ANode.Kind in [TSyntaxKind.ExceptionHandler, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst,
      TSyntaxKind.LabeledStatement, TSyntaxKind.GotoStatement]) and (ANode.Name <> '') then
      Declared := Declared + [ANode.Name];
    for Index := 0 to ANode.ChildCount - 1 do
      CollectDeclared(ANode[Index]);
  end;

  procedure Visit(ANode: TSyntaxNode; AInStatements: Boolean);
  var
    Index: Integer;
    Resolved: TResolvedSymbol;
    Item: TUnresolvedName;
  begin
    if Length(Result) >= MaxNames then
      Exit;
    if ANode.Kind in [TSyntaxKind.WithStatement, TSyntaxKind.AsmBlock, TSyntaxKind.AnonymousMethod,
      TSyntaxKind.Error] then
      Exit;
    // Anweisungen stehen in Blöcken von Routinen und in initialization/finalization.
    if ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection] then
      AInStatements := True
    else if ANode.Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection,
      TSyntaxKind.RoutineHeader, TSyntaxKind.Parameters, TSyntaxKind.GenericArgs] then
      AInStatements := False;
    if AInStatements and (ANode.Kind = TSyntaxKind.Identifier) and (ANode.Name <> '') and
      not IsIntrinsic(ANode.Name) and not IsDeclared(ANode.Name) then
    begin
      Resolved := AResolver.ResolveChain(ATree, AFileName, [ANode.Name], ANode.StartOffset);
      if not Resolved.Found then
      begin
        Item.Name := ANode.Name;
        Item.Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
        Result := Result + [Item];
      end;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index], AInStatements);
  end;

begin
  Result := nil;
  Declared := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  CollectDeclared(ATree.Root);
  AResolver.PinTree(ATree, AFileName);
  try
    Visit(ATree.Root, False);
  finally
    AResolver.UnpinTree;
  end;
end;

end.
