unit Atlas.Common.Semantics.TypeImports;

// uses-Eintrag für einen Typnamen, der an einer Stelle nicht sichtbar ist (#180, #294): Kennt der Index den Typ
// in einer anderen Unit, die der Baum noch nicht einbindet, kommt deren Name in die passende uses-Klausel. Für
// Vervollständigung (Deklarieren) und Schnellbefehle mit Typ-Argumenten.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver;

type
  TTypeImports = class
  public
    /// <summary>uses-Eintrag für ATypeName, wenn der Typ an AOffset in ATree nicht sichtbar ist und AIndex ihn in
    /// einer anderen Unit kennt; sonst leer. Nur schlichte Namen (nicht generisch, nicht qualifiziert, nicht
    /// eingebaut).</summary>
    class function Edits(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName, ATypeName, ALineBreak: string; AOffset: Integer): TArray<TTextEdit>; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.UsesEdits,
  Atlas.Common.Pascal.UsesClauses;

/// <summary>Ein schlichter Typname, der einen uses-Eintrag brauchen kann: nicht generisch, nicht qualifiziert,
/// kein Platzhalter, nicht eingebaut.</summary>
function IsImportableName(const ATypeName: string): Boolean;
begin
  Result := (ATypeName <> '') and (Pos('<', ATypeName) = 0) and (Pos('.', ATypeName) = 0) and
    (Pos('{', ATypeName) = 0) and not TResolverText.IsBuiltinTypeName(ATypeName);
end;

/// <summary>Ein Typ aus einer anderen Unit, die ATree noch nicht einbindet.</summary>
function IsForeignType(AResolver: TNameResolver; ATree: TSyntaxTree; const ALocation: TSymbolLocation): Boolean;
begin
  Result := (ALocation.Symbol.Container = '') and (ALocation.Symbol.Kind in [TIndexSymbolKind.ClassType,
    TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType,
    TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias]) and not SameText(ALocation.UnitName, 'System') and
    not SameText(ALocation.UnitName, TPascalUses.OwnName(ATree.Tokens));
  Result := Result and not TPascalUses.IsUsed(TPascalUses.UsedUnits(ATree.Tokens), ALocation.UnitName,
    AResolver.Namespaces);
end;

{ TTypeImports }

class function TTypeImports.Edits(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName, ATypeName, ALineBreak: string; AOffset: Integer): TArray<TTextEdit>;
var
  mLocation: TSymbolLocation;
  mEdit: TTextEdit;
begin
  Result := nil;
  if (AIndex = nil) or not IsImportableName(ATypeName) or AResolver.ResolveChain(ATree, AFileName, [ATypeName],
    AOffset).Found then
  begin
    Exit;
  end;
  for mLocation in AIndex.FindSymbols(ATypeName) do
  begin
    if IsForeignType(AResolver, ATree, mLocation) and TPascalUsesEdits.AddUnit(ATree.Tokens, AOffset,
      mLocation.UnitName, ALineBreak, mEdit) then
    begin
      Result := [mEdit];
      Exit;
    end;
  end;
end;

end.
