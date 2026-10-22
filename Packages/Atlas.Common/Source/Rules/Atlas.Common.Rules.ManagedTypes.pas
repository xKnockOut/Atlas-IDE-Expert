unit Atlas.Common.Rules.ManagedTypes;

// Verwaltete Typen für Prüfregeln: Strings, Interfaces, dynamische Arrays und Variants, auch als Feld
// eines Records, Element eines statischen Arrays oder hinter einem Alias, aufgelöst über die Datei und den
// Index (#921, #922); dazu verwaltete Records mit class operator Initialize oder Finalize (#1071).
// Unbekannte Typen gelten als nicht verwaltet, damit Regeln nur sichere Fälle melden.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Löst Typnamen der Datei und des Index auf und sagt, ob sie verwaltete Teile enthalten.</summary>
  TManagedTypes = class
  private
    FTree: TSyntaxTree;
    FText: string;
    FIndex: ISymbolIndex;
    function TypeDecl(const AName: string): TSyntaxNode;
    function FieldsManaged(ARecord: TSyntaxNode; ADepth: Integer): string;
    function IndexManaged(const AName: string; ADepth: Integer): string;
    function FieldsCustomManaged(ARecord: TSyntaxNode; ADepth: Integer): Boolean;
    function IndexCustomManaged(const AName: string; ADepth: Integer): Boolean;
  public
    constructor Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex);
    /// <summary>'Strings', 'Interfaces', 'dynamische Arrays' oder 'Variants', wenn ATypeName solche Teile
    /// hat; '' sonst oder wenn der Typ unbekannt ist.</summary>
    function Managed(const ATypeName: string; ADepth: Integer): string;
    /// <summary>Zieltyp eines Zeigertyps (^TRec oder PRec = ^TRec in der Datei); '' sonst.</summary>
    function Pointee(const ATypeName: string): string;
    /// <summary>Ist ATypeName selbst ein String, Interface, dynamisches Array oder Variant?</summary>
    function IsPrimitive(const ATypeName: string): Boolean;
    /// <summary>Verwalteter Record mit class operator Initialize oder Finalize (ab Delphi 10.4), auch als Feld
    /// eines Records oder Element eines statischen Arrays; False, wenn der Typ unbekannt ist (#1071).</summary>
    function CustomManaged(const ATypeName: string; ADepth: Integer): Boolean;
    /// <summary>Typtext des ersten Typknotens unter ANode (Feld, Variable, Typdeklaration).</summary>
    function NodeTypeText(ANode: TSyntaxNode): string;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections;

const
  // RTL-Records mit verwalteten Feldern, auch ohne Index.
  ManagedStringRecords: array[0..2] of string = ('TFormatSettings', 'TSearchRec', 'TWin32FindData');
  ManagedInterfaceRecords: array[0..1] of string = ('TValue', 'TRttiContext');
  DynamicArrayNames: array[0..5] of string = ('TBytes', 'TStringDynArray', 'TIntegerDynArray', 'TStringArray',
    'TArray', 'TObjectDynArray');


constructor TManagedTypes.Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FIndex := AIndex;
end;

function TManagedTypes.TypeDecl(const AName: string): TSyntaxNode;
var
  Found: TSyntaxNode;
  Name: string;
begin
  Found := nil;
  Name := AName;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := Found = nil;
      if Result and (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, Name) then
        Found := ANode;
    end);
  Result := Found;
end;

function TManagedTypes.NodeTypeText(ANode: TSyntaxNode): string;
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  Result := '';
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Child.Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.PointerType,
      TSyntaxKind.RecordType, TSyntaxKind.ClassType, TSyntaxKind.InterfaceType, TSyntaxKind.ClassOfType,
      TSyntaxKind.SetType, TSyntaxKind.EnumType, TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType] then
      Exit(Trim(Copy(FText, Child.StartOffset + 1, Child.EndOffset - Child.StartOffset)));
  end;
end;

// Iterativ (Bericht M1).
function TManagedTypes.FieldsManaged(ARecord: TSyntaxNode; ADepth: Integer): string;
var
  Pending: TStack<TSyntaxNode>;
  Index: Integer;
  Child: TSyntaxNode;
begin
  Result := '';
  Pending := TStack<TSyntaxNode>.Create;
  try
    for Index := ARecord.ChildCount - 1 downto 0 do
      Pending.Push(ARecord[Index]);
    while Pending.Count > 0 do
    begin
      Child := Pending.Pop;
      // Verschachtelte Typdeklarationen sind keine Felder.
      if Child.Kind = TSyntaxKind.TypeDecl then
        Continue;
      if Child.Kind = TSyntaxKind.Field then
      begin
        Result := Managed(NodeTypeText(Child), ADepth + 1);
        if Result <> '' then
          Exit;
      end
      else if not (Child.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl]) then
        for Index := Child.ChildCount - 1 downto 0 do
          Pending.Push(Child[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

function TManagedTypes.IndexManaged(const AName: string; ADepth: Integer): string;
var
  Location: TSymbolLocation;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
begin
  Result := '';
  if FIndex = nil then
    Exit;
  for Location in FIndex.FindSymbols(AName) do
  begin
    if Location.Symbol.Container <> '' then
      Continue;
    case Location.Symbol.Kind of
      TIndexSymbolKind.InterfaceType:
        Exit('Interfaces');
      TIndexSymbolKind.TypeAlias:
        Exit(Managed(Location.Symbol.TypeName, ADepth + 1));
      TIndexSymbolKind.RecordType:
        begin
          if not FIndex.FindFile(Location.FileName, UnitIndex) then
            Exit;
          for Symbol in UnitIndex.Symbols do
            if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, AName) then
            begin
              Result := Managed(Symbol.TypeName, ADepth + 1);
              if Result <> '' then
                Exit;
            end;
          Exit;
        end;
    else
      Exit;
    end;
  end;
end;

function TManagedTypes.IsPrimitive(const ATypeName: string): Boolean;
var
  Name: string;
begin
  Name := Trim(ATypeName);
  Result := MatchText(Name, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'UTF8String',
    'Variant', 'OleVariant', 'IInterface', 'IUnknown', 'IDispatch']) or MatchText(Name, DynamicArrayNames) or
    StartsText('array of', Name) or StartsText('TArray<', Name);
end;

function TManagedTypes.Managed(const ATypeName: string; ADepth: Integer): string;
var
  Name, Element: string;
  Decl, Body: TSyntaxNode;
  Index: Integer;
begin
  Result := '';
  Name := Trim(ATypeName);
  if (Name = '') or (ADepth > 16) then
    Exit;
  if MatchText(Name, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'UTF8String']) then
    Exit('Strings');
  if MatchText(Name, ['Variant', 'OleVariant']) then
    Exit('Variants');
  if MatchText(Name, ['IInterface', 'IUnknown', 'IDispatch']) then
    Exit('Interfaces');
  if StartsText('array of', Name) or StartsText('TArray<', Name) or MatchText(Name, DynamicArrayNames) then
    Exit('dynamische Arrays');
  // Statisches Array: verwaltet, wenn die Elemente es sind.
  if StartsText('array', Name) then
  begin
    Index := Pos(' of ', LowerCase(Name));
    if Index = 0 then
      Exit;
    Element := Copy(Name, Index + 4, MaxInt);
    Exit(Managed(Element, ADepth + 1));
  end;
  if MatchText(Name, ManagedStringRecords) then
    Exit('Strings');
  if MatchText(Name, ManagedInterfaceRecords) then
    Exit('Interfaces');
  if Pos('<', Name) > 0 then
    Exit;
  Decl := TypeDecl(Name);
  if Decl = nil then
    Exit(IndexManaged(Name, ADepth));
  Body := Decl.FindChild(TSyntaxKind.RecordType);
  if Body <> nil then
    Exit(FieldsManaged(Body, ADepth));
  if Decl.FindChild(TSyntaxKind.InterfaceType) <> nil then
    Exit('Interfaces');
  if (Decl.FindChild(TSyntaxKind.TypeReference) <> nil) or (Decl.FindChild(TSyntaxKind.ArrayType) <> nil) then
    Result := Managed(NodeTypeText(Decl), ADepth + 1);
end;

function TManagedTypes.Pointee(const ATypeName: string): string;
var
  Name: string;
  Decl: TSyntaxNode;
begin
  Result := '';
  Name := Trim(ATypeName);
  if StartsText('^', Name) then
    Exit(Trim(Copy(Name, 2, MaxInt)));
  if (Name = '') or (Pos('<', Name) > 0) then
    Exit;
  Decl := TypeDecl(Name);
  if (Decl <> nil) and (Decl.FindChild(TSyntaxKind.PointerType) <> nil) then
  begin
    Result := NodeTypeText(Decl);
    if StartsText('^', Result) then
      Result := Trim(Copy(Result, 2, MaxInt))
    else
      Result := '';
  end;
end;

// Iterativ (Bericht M1).
function TManagedTypes.FieldsCustomManaged(ARecord: TSyntaxNode; ADepth: Integer): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Index: Integer;
  Child: TSyntaxNode;
  Head: string;
begin
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    for Index := ARecord.ChildCount - 1 downto 0 do
      Pending.Push(ARecord[Index]);
    while Pending.Count > 0 do
    begin
      Child := Pending.Pop;
      if Child.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.PropertyDecl] then
        Continue;
      if Child.Kind = TSyntaxKind.RoutineHeader then
      begin
        Head := Copy(FText, Child.StartOffset + 1, Child.EndOffset - Child.StartOffset);
        Result := MatchText(Child.Name, ['Initialize', 'Finalize']) and ContainsText(Head, 'operator');
      end
      else if Child.Kind = TSyntaxKind.Field then
        Result := CustomManaged(NodeTypeText(Child), ADepth + 1)
      else
        for Index := Child.ChildCount - 1 downto 0 do
          Pending.Push(Child[Index]);
      if Result then
        Exit;
    end;
  finally
    Pending.Free;
  end;
end;

function TManagedTypes.IndexCustomManaged(const AName: string; ADepth: Integer): Boolean;
var
  Location: TSymbolLocation;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
begin
  Result := False;
  if FIndex = nil then
    Exit;
  for Location in FIndex.FindSymbols(AName) do
  begin
    if Location.Symbol.Container <> '' then
      Continue;
    case Location.Symbol.Kind of
      TIndexSymbolKind.TypeAlias:
        Exit(CustomManaged(Location.Symbol.TypeName, ADepth + 1));
      TIndexSymbolKind.RecordType:
        begin
          if not FIndex.FindFile(Location.FileName, UnitIndex) then
            Exit;
          for Symbol in UnitIndex.Symbols do
            if SameText(Symbol.Container, AName) and (((Symbol.Kind = TIndexSymbolKind.Method) and
              MatchText(Symbol.Name, ['Initialize', 'Finalize']) and ContainsText(Symbol.Signature, 'operator')) or
              ((Symbol.Kind = TIndexSymbolKind.Field) and CustomManaged(Symbol.TypeName, ADepth + 1))) then
              Exit(True);
          Exit;
        end;
    else
      Exit;
    end;
  end;
end;

function TManagedTypes.CustomManaged(const ATypeName: string; ADepth: Integer): Boolean;
var
  Name: string;
  Decl, Body: TSyntaxNode;
  Index: Integer;
begin
  Result := False;
  Name := Trim(ATypeName);
  if (Name = '') or (ADepth > 16) or (Pos('<', Name) > 0) or StartsText('array of', Name) then
    Exit;
  if StartsText('array', Name) then
  begin
    Index := Pos(' of ', LowerCase(Name));
    if Index > 0 then
      Result := CustomManaged(Copy(Name, Index + 4, MaxInt), ADepth + 1);
    Exit;
  end;
  Decl := TypeDecl(Name);
  if Decl = nil then
    Exit(IndexCustomManaged(Name, ADepth));
  Body := Decl.FindChild(TSyntaxKind.RecordType);
  if Body <> nil then
    Exit(FieldsCustomManaged(Body, ADepth));
  if (Decl.FindChild(TSyntaxKind.TypeReference) <> nil) or (Decl.FindChild(TSyntaxKind.ArrayType) <> nil) then
    Result := CustomManaged(NodeTypeText(Decl), ADepth + 1);
end;

end.
