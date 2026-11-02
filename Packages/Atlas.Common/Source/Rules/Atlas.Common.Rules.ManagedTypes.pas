unit Atlas.Common.Rules.ManagedTypes;

// Verwaltete Typen für Prüfregeln: Strings, Interfaces, Methodenreferenzen, dynamische Arrays und Variants,
// auch als Feld eines Records, Element eines statischen Arrays oder hinter einem Alias, aufgelöst über die Datei
// und den Index (#921, #922); dazu verwaltete Records mit class operator Initialize oder Finalize (#1071).
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
    /// <summary>'Strings', 'Interfaces', 'Methodenreferenzen', 'dynamische Arrays' oder 'Variants', wenn
    /// ATypeName solche Teile hat; '' sonst oder wenn der Typ unbekannt ist.</summary>
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
      begin
        Found := ANode;
      end;
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
    begin
      Exit(Trim(Copy(FText, Child.StartOffset + 1, Child.EndOffset - Child.StartOffset)));
    end;
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
    begin
      Pending.Push(ARecord[Index]);
    end;
    while Pending.Count > 0 do
    begin
      Child := Pending.Pop;
      // Verschachtelte Typdeklarationen sind keine Felder.
      if Child.Kind = TSyntaxKind.TypeDecl then
      begin
        Continue;
      end;
      if Child.Kind = TSyntaxKind.Field then
      begin
        Result := Managed(NodeTypeText(Child), ADepth + 1);
        if Result <> '' then
        begin
          Exit;
        end;
      end
      else if not (Child.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl]) then
      begin
        for Index := Child.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Child[Index]);
        end;
      end;
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
  begin
    Exit;
  end;
  for Location in FIndex.FindSymbols(AName) do
  begin
    if Location.Symbol.Container <> '' then
    begin
      Continue;
    end;
    case Location.Symbol.Kind of
      TIndexSymbolKind.InterfaceType:
        Exit('Interfaces');
      TIndexSymbolKind.TypeAlias:
        begin
          // reference to … ist ein Interface mit Referenzzähler.
          if IndexText('reference to', Location.Symbol.Directives) >= 0 then
          begin
            Exit('Methodenreferenzen');
          end;
          Exit(Managed(Location.Symbol.TypeName, ADepth + 1));
        end;
      TIndexSymbolKind.RecordType:
        begin
          if not FIndex.FindFile(Location.FileName, UnitIndex) then
          begin
            Exit;
          end;
          for Symbol in UnitIndex.Symbols do
          begin
            if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, AName) then
            begin
              Result := Managed(Symbol.TypeName, ADepth + 1);
              if Result <> '' then
              begin
                Exit;
              end;
            end;
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
  begin
    Exit;
  end;
  if MatchText(Name, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'UTF8String']) then
  begin
    Exit('Strings');
  end;
  if MatchText(Name, ['Variant', 'OleVariant']) then
  begin
    Exit('Variants');
  end;
  if MatchText(Name, ['IInterface', 'IUnknown', 'IDispatch']) then
  begin
    Exit('Interfaces');
  end;
  if StartsText('reference to', Name) then
  begin
    Exit('Methodenreferenzen');
  end;
  if StartsText('array of', Name) or StartsText('TArray<', Name) or MatchText(Name, DynamicArrayNames) then
  begin
    Exit('dynamische Arrays');
  end;
  // Statisches Array: verwaltet, wenn die Elemente es sind.
  if StartsText('array', Name) then
  begin
    Index := Pos(' of ', LowerCase(Name));
    if Index = 0 then
    begin
      Exit;
    end;
    Element := Copy(Name, Index + 4, MaxInt);
    Exit(Managed(Element, ADepth + 1));
  end;
  if MatchText(Name, ManagedStringRecords) then
  begin
    Exit('Strings');
  end;
  if MatchText(Name, ManagedInterfaceRecords) then
  begin
    Exit('Interfaces');
  end;
  if Pos('<', Name) > 0 then
  begin
    Exit;
  end;
  Decl := TypeDecl(Name);
  if Decl = nil then
  begin
    Exit(IndexManaged(Name, ADepth));
  end;
  Body := Decl.FindChild(TSyntaxKind.RecordType);
  if Body <> nil then
  begin
    Exit(FieldsManaged(Body, ADepth));
  end;
  if Decl.FindChild(TSyntaxKind.InterfaceType) <> nil then
  begin
    Exit('Interfaces');
  end;
  Body := Decl.FindChild(TSyntaxKind.ProcedureType);
  if (Body <> nil) and SameText(Body.Name, 'reference') then
  begin
    Exit('Methodenreferenzen');
  end;
  if (Decl.FindChild(TSyntaxKind.TypeReference) <> nil) or (Decl.FindChild(TSyntaxKind.ArrayType) <> nil) then
  begin
    Result := Managed(NodeTypeText(Decl), ADepth + 1);
  end;
end;

function TManagedTypes.Pointee(const ATypeName: string): string;
var
  Name: string;
  Decl: TSyntaxNode;
begin
  Result := '';
  Name := Trim(ATypeName);
  if StartsText('^', Name) then
  begin
    Exit(Trim(Copy(Name, 2, MaxInt)));
  end;
  if (Name = '') or (Pos('<', Name) > 0) then
  begin
    Exit;
  end;
  Decl := TypeDecl(Name);
  if (Decl <> nil) and (Decl.FindChild(TSyntaxKind.PointerType) <> nil) then
  begin
    Result := NodeTypeText(Decl);
    if StartsText('^', Result) then
    begin
      Result := Trim(Copy(Result, 2, MaxInt));
    end
    else
    begin
      Result := '';
    end;
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
    begin
      Pending.Push(ARecord[Index]);
    end;
    while Pending.Count > 0 do
    begin
      Child := Pending.Pop;
      if Child.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.PropertyDecl] then
      begin
        Continue;
      end;
      if Child.Kind = TSyntaxKind.RoutineHeader then
      begin
        Head := Copy(FText, Child.StartOffset + 1, Child.EndOffset - Child.StartOffset);
        Result := MatchText(Child.Name, ['Initialize', 'Finalize']) and ContainsText(Head, 'operator');
      end
      else if Child.Kind = TSyntaxKind.Field then
      begin
        Result := CustomManaged(NodeTypeText(Child), ADepth + 1);
      end
      else
      begin
        for Index := Child.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Child[Index]);
        end;
      end;
      if Result then
      begin
        Exit;
      end;
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
  begin
    Exit;
  end;
  for Location in FIndex.FindSymbols(AName) do
  begin
    if Location.Symbol.Container <> '' then
    begin
      Continue;
    end;
    case Location.Symbol.Kind of
      TIndexSymbolKind.TypeAlias:
        Exit(CustomManaged(Location.Symbol.TypeName, ADepth + 1));
      TIndexSymbolKind.RecordType:
        begin
          if not FIndex.FindFile(Location.FileName, UnitIndex) then
          begin
            Exit;
          end;
          for Symbol in UnitIndex.Symbols do
          begin
            if SameText(Symbol.Container, AName) and (((Symbol.Kind = TIndexSymbolKind.Method) and
              MatchText(Symbol.Name, ['Initialize', 'Finalize']) and ContainsText(Symbol.Signature, 'operator')) or
              ((Symbol.Kind = TIndexSymbolKind.Field) and CustomManaged(Symbol.TypeName, ADepth + 1))) then
            begin
              Exit(True);
            end;
          end;
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
  begin
    Exit;
  end;
  if StartsText('array', Name) then
  begin
    Index := Pos(' of ', LowerCase(Name));
    if Index > 0 then
    begin
      Result := CustomManaged(Copy(Name, Index + 4, MaxInt), ADepth + 1);
    end;
    Exit;
  end;
  Decl := TypeDecl(Name);
  if Decl = nil then
  begin
    Exit(IndexCustomManaged(Name, ADepth));
  end;
  Body := Decl.FindChild(TSyntaxKind.RecordType);
  if Body <> nil then
  begin
    Exit(FieldsCustomManaged(Body, ADepth));
  end;
  if (Decl.FindChild(TSyntaxKind.TypeReference) <> nil) or (Decl.FindChild(TSyntaxKind.ArrayType) <> nil) then
  begin
    Result := CustomManaged(NodeTypeText(Decl), ADepth + 1);
  end;
end;

end.
