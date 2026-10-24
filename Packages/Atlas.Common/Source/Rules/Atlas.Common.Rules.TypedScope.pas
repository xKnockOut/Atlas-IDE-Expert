unit Atlas.Common.Rules.TypedScope;

// Gemeinsamer Rahmen der Regeln, die Typen von Ausdrücken brauchen (#1024,
// #1129): Namensauflösung über den gepinnten Baum, Konstantenwerte und die
// Prüfung, ob eine Deklaration immer mit einer Stelle übersetzt wird. Gemeldet
// wird nur, was sicher bekannt ist.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ConstantValues;

type
  /// <summary>Namensauflösung und Konstantenwerte für eine Prüfung; pinnt den Baum des Kontexts bis Destroy.
  /// </summary>
  TTypedScope = class
  private
    FContext: TRuleContext;
    FFileName: string;
    FResolver: TNameResolver;
    FValues: TConstantValues;
    FPaths: TArray<string>;
    FTokens: TArray<TPascalToken>;
  public
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    /// <summary>Quelltext von ANode, Leerraum zu einem Leerzeichen zusammengefasst.</summary>
    function Text(ANode: TSyntaxNode): string;
    /// <summary>Index des ersten Tokens, das bei APosition oder dahinter beginnt.</summary>
    function TokenAtPosition(const APosition: TTextPosition): Integer;
    /// <summary>Wird die Deklaration ASymbol immer übersetzt, wenn ANode übersetzt wird?</summary>
    function DeclarationSure(const ASymbol: TResolvedSymbol; ANode: TSyntaxNode): Boolean;
    /// <summary>Deklaration und Typ von ANode wie TNameResolver.NodeType, aber nur bei sicher bekanntem Typ und
    /// einer Deklaration, die immer mit ANode übersetzt wird.</summary>
    function SureType(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
    property Resolver: TNameResolver read FResolver;
    property Values: TConstantValues read FValues;
    property FileName: string read FFileName;
    property Tokens: TArray<TPascalToken> read FTokens;
  end;

/// <summary>Ausdruck ohne umschließende Klammern.</summary>
function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.ConditionalBranches;

function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
    Result := Result[0];
end;

{ TTypedScope }

constructor TTypedScope.Create(const AContext: TRuleContext);
begin
  inherited Create;
  FContext := AContext;
  FFileName := AContext.FileName;
  if FFileName = '' then
    FFileName := AContext.RelativePath;
  if FFileName = '' then
    FFileName := AContext.UnitName + '.pas';
  FTokens := AContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(FTokens);
  FResolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  FResolver.Namespaces := AContext.Namespaces;
  FResolver.PinTree(AContext.Tree, FFileName);
  FValues := TConstantValues.Create(AContext.Tree, FFileName, AContext.Index, FResolver);
end;

destructor TTypedScope.Destroy;
begin
  FValues.Free;
  if FResolver <> nil then
    FResolver.UnpinTree;
  FResolver.Free;
  inherited;
end;

function TTypedScope.Text(ANode: TSyntaxNode): string;
var
  Index: Integer;
  Space: Boolean;
  Raw: string;
begin
  Raw := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  Result := '';
  Space := False;
  for Index := 1 to Length(Raw) do
    if CharInSet(Raw[Index], [' ', #9, #10, #13]) then
      Space := True
    else
    begin
      if Space and (Result <> '') then
        Result := Result + ' ';
      Space := False;
      Result := Result + Raw[Index];
    end;
end;

function TTypedScope.TokenAtPosition(const APosition: TTextPosition): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(FTokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if (FTokens[Middle].StartPos.Line < APosition.Line) or ((FTokens[Middle].StartPos.Line = APosition.Line) and
      (FTokens[Middle].StartPos.Character < APosition.Character)) then
      Low := Middle + 1
    else
      High := Middle;
  end;
  Result := Low;
end;

function TTypedScope.DeclarationSure(const ASymbol: TResolvedSymbol; ANode: TSyntaxNode): Boolean;
var
  Use: Integer;
begin
  if ASymbol.Condition <> '' then
    Exit(False);
  if (ASymbol.Kind <> TResolvedKind.Local) and (ASymbol.FileName <> '') and not SameText(ASymbol.FileName,
    FFileName) then
    Exit(True);
  // Deklaration in dieser Datei: Der Baum enthält beide Zweige von {$IFDEF} … {$ELSE}.
  if FPaths = nil then
    Exit(True);
  Use := TConstantValues.TokenFrom(FTokens, ANode.StartOffset);
  Result := TConditionalBranches.Implies(TConditionalBranches.PathAt(FPaths, Use),
    TConditionalBranches.PathAt(FPaths, TokenAtPosition(ASymbol.Range.StartPos)));
end;

function TTypedScope.SureType(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
var
  TypeFound: Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess]) and FResolver.NodeType(FContext.Tree, FFileName, ANode, ASymbol, AType, TypeFound) and
    TypeFound and (ASymbol.Kind <> TResolvedKind.UnitName) and DeclarationSure(ASymbol, ANode);
end;

end.
