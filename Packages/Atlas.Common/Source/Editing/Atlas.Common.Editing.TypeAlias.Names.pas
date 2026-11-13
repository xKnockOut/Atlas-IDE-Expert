unit Atlas.Common.Editing.TypeAlias.Names;

// Namen für „Typ-Alias einführen“ (#681): Vorschlag aus dem Zusammenhang (Feld FGroups mit TList<TKunde> ->
// TKundeGroups, Element-, Array-, Mengen- und Methodenreferenz-Namen) und welche Knoten Typausdrücke sind.
// Einführen und Auflösen stehen in Atlas.Common.Editing.TypeAlias.

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Namensvorschlag für einen Alias und die Typknoten, für die er gilt.</summary>
  TTypeAliasNames = class
  public const
    /// <summary>Knoten, die einen Typausdruck tragen.</summary>
    cTypeKinds = [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.SetType, TSyntaxKind.ProcedureType,
      TSyntaxKind.PointerType, TSyntaxKind.ClassOfType, TSyntaxKind.SubrangeType, TSyntaxKind.FileType];
    /// <summary>Deklarationen, deren Typ einen Alias bekommen kann.</summary>
    cDeclarationContexts = [TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.ConstDecl,
      TSyntaxKind.InlineConst, TSyntaxKind.Parameter, TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl];
  public
    class function LastPart(const AName: string): string; static;
    class function IsTypeNode(ANode: TSyntaxNode): Boolean; static;
    class function Suggest(ANode: TSyntaxNode): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

class function TTypeAliasNames.LastPart(const AName: string): string;
begin
  Result := AName;
  if Pos('.', Result) > 0 then
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

function Capitalized(const AName: string): string;
begin
  Result := AName;
  if Result <> '' then
  begin
    Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
  end;
end;

function IsUpper(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z']);
end;

/// <summary>TKunde -> Kunde, FGroups -> Groups; eingebaute Namen groß geschrieben.</summary>
function Bare(const AName: string): string;
begin
  Result := TTypeAliasNames.LastPart(Trim(AName));
  if (Length(Result) >= 2) and CharInSet(Result[1], ['T', 'F', 'L', 'A', 'G', 'I']) and IsUpper(Result[2]) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
  Result := Capitalized(Result);
end;

class function TTypeAliasNames.IsTypeNode(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in TTypeAliasNames.cTypeKinds);
end;

/// <summary>Innerster benannter Typ: letztes Typargument bzw. Element, sonst der Name selbst.</summary>
function ElementName(ANode: TSyntaxNode): string;
var
  mArgs: TSyntaxNode;
  mIndex: Integer;
begin
  Result := '';
  case ANode.Kind of
    TSyntaxKind.TypeReference:
      begin
        mArgs := ANode.FindChild(TSyntaxKind.GenericArgs);
        if (mArgs <> nil) and (mArgs.ChildCount > 0) then
        begin
          Exit(ElementName(mArgs[mArgs.ChildCount - 1]));
        end;
        Result := Bare(ANode.Name);
      end;
    TSyntaxKind.ArrayType, TSyntaxKind.SetType:
      for mIndex := ANode.ChildCount - 1 downto 0 do
      begin
        if TTypeAliasNames.IsTypeNode(ANode[mIndex]) and (ANode[mIndex].Kind <> TSyntaxKind.SubrangeType) then
        begin
          Exit(ElementName(ANode[mIndex]));
        end;
      end;
  else
    // Übrige Arten: nichts zu tun.
  end;
end;

function ArrayDepth(ANode: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  while (ANode <> nil) and (ANode.Kind = TSyntaxKind.ArrayType) do
  begin
    Inc(Result);
    mIndex := ANode.ChildCount - 1;
    if mIndex < 0 then
    begin
      Break;
    end;
    ANode := ANode[mIndex];
  end;
end;

/// <summary>Name aus der Deklaration um ANode: Feld, Variable, Parameter, Property, Routine; '' ohne.</summary>
function ContextName(ANode: TSyntaxNode): string;
var
  mOwner: TSyntaxNode;
begin
  Result := '';
  mOwner := ANode.Parent;
  if (mOwner = nil) or not (mOwner.Kind in TTypeAliasNames.cDeclarationContexts) then
  begin
    Exit;
  end;
  Result := Trim(mOwner.Name);
  if Pos(',', Result) > 0 then
  begin
    Result := Trim(Copy(Result, 1, Pos(',', Result) - 1));
  end;
  Result := Bare(Result);
  // Kurze Namen (A, I, LX) sagen nichts über den Typ.
  if Length(Result) < 3 then
  begin
    Result := '';
  end;
end;

/// <summary>Name für einen prozeduralen Typ: TBaseFunc bzw. TBaseProc, ohne Base TCallback….</summary>
function ProcedureTypeName(const ABase: string; ANode: TSyntaxNode): string;
var
  mBase: string;
begin
  mBase := ABase;
  if mBase = '' then
  begin
    mBase := 'Callback';
  end;
  if ANode.FindChild(TSyntaxKind.TypeReference) <> nil then
  begin
    Result := 'T' + mBase + 'Func';
  end
  else
  begin
    Result := 'T' + mBase + 'Proc';
  end;
  if EndsText('FuncFunc', Result) or EndsText('ProcProc', Result) then
  begin
    Result := Copy(Result, 1, Length(Result) - 4);
  end;
end;

/// <summary>Name für einen generischen Typ: aus Element und Kontext bzw. eigenem Namen.</summary>
function ReferenceTypeName(const ABase, AElement: string; ANode: TSyntaxNode): string;
begin
  if ABase = '' then
  begin
    Result := 'T' + AElement + Bare(ANode.Name);
  end
  else if ContainsText(ABase, AElement) then
  begin
    Result := 'T' + ABase;
  end
  else
  begin
    Result := 'T' + AElement + ABase;
  end;
end;

/// <summary>Name für ein Array: aus dem Kontext, sonst Element mit Array, Matrix oder ArraynD.</summary>
function ArrayTypeName(const ABase, AElement: string; ANode: TSyntaxNode): string;
var
  mDepth: Integer;
begin
  if ABase <> '' then
  begin
    Exit('T' + ABase);
  end;
  mDepth := ArrayDepth(ANode);
  if mDepth = 2 then
  begin
    Result := 'T' + AElement + 'Matrix';
  end
  else if mDepth > 2 then
  begin
    Result := Format('T%sArray%dD', [AElement, mDepth]);
  end
  else
  begin
    Result := 'T' + AElement + 'Array';
  end;
end;

class function TTypeAliasNames.Suggest(ANode: TSyntaxNode): string;
var
  mBase, mElement: string;
begin
  mBase := ContextName(ANode);
  mElement := ElementName(ANode);
  case ANode.Kind of
    TSyntaxKind.ProcedureType:
      Result := ProcedureTypeName(mBase, ANode);
    TSyntaxKind.TypeReference:
      Result := ReferenceTypeName(mBase, mElement, ANode);
    TSyntaxKind.ArrayType:
      Result := ArrayTypeName(mBase, mElement, ANode);
  else
    if mBase <> '' then
    begin
      Result := 'T' + mBase;
    end
    else
    begin
      Result := 'T' + mElement + 'Set';
    end;
  end;
end;

end.
