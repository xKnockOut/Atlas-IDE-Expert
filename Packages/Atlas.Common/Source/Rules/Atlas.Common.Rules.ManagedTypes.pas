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
    /// <summary>Das erste Symbol AName der obersten Ebene im Index; False ohne Index oder Symbol.</summary>
    function TopLevelSymbol(const AName: string; out ALocation: TSymbolLocation): Boolean;
    function RecordFieldsManaged(const ALocation: TSymbolLocation; const AName: string; ADepth: Integer): string;
    function DeclManaged(ADecl: TSyntaxNode; ADepth: Integer): string;
    function SymbolCustomManaged(const ASymbol: TIndexSymbol; ADepth: Integer): Boolean;
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

function TManagedTypes.TopLevelSymbol(const AName: string; out ALocation: TSymbolLocation): Boolean;
var
  mLocation: TSymbolLocation;
begin
  Result := False;
  if FIndex = nil then
  begin
    Exit;
  end;
  for mLocation in FIndex.FindSymbols(AName) do
  begin
    if mLocation.Symbol.Container = '' then
    begin
      ALocation := mLocation;
      Exit(True);
    end;
  end;
end;

function TManagedTypes.RecordFieldsManaged(const ALocation: TSymbolLocation; const AName: string;
  ADepth: Integer): string;
var
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  Result := '';
  if not FIndex.FindFile(ALocation.FileName, mUnit) then
  begin
    Exit;
  end;
  for mSymbol in mUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, AName) then
    begin
      Result := Managed(mSymbol.TypeName, ADepth + 1);
      if Result <> '' then
      begin
        Exit;
      end;
    end;
  end;
end;

function TManagedTypes.IndexManaged(const AName: string; ADepth: Integer): string;
var
  mLocation: TSymbolLocation;
begin
  Result := '';
  // Es zählt das erste Symbol der obersten Ebene.
  if not TopLevelSymbol(AName, mLocation) then
  begin
    Exit;
  end;
  case mLocation.Symbol.Kind of
    TIndexSymbolKind.InterfaceType:
      Result := 'Interfaces';
    TIndexSymbolKind.TypeAlias:
      // reference to … ist ein Interface mit Referenzzähler.
      if IndexText('reference to', mLocation.Symbol.Directives) >= 0 then
      begin
        Result := 'Methodenreferenzen';
      end
      else
      begin
        Result := Managed(mLocation.Symbol.TypeName, ADepth + 1);
      end;
    TIndexSymbolKind.RecordType:
      Result := RecordFieldsManaged(mLocation, AName, ADepth);
  else
    // Klassen, Konstanten usw. machen den Typ nicht verwaltet.
    Result := '';
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

/// <summary>Art verwalteter Daten, die schon der Name verrät (Strings, Variants, Interfaces, Methodenreferenzen,
/// dynamische Arrays und bekannte RTL-Records); '' sonst.</summary>
function NamedKind(const AName: string): string;
begin
  Result := '';
  if MatchText(AName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'UTF8String']) or
    MatchText(AName, ManagedStringRecords) then
  begin
    Result := 'Strings';
  end
  else if MatchText(AName, ['Variant', 'OleVariant']) then
  begin
    Result := 'Variants';
  end
  else if MatchText(AName, ['IInterface', 'IUnknown', 'IDispatch']) or MatchText(AName, ManagedInterfaceRecords) then
  begin
    Result := 'Interfaces';
  end
  else if StartsText('reference to', AName) then
  begin
    Result := 'Methodenreferenzen';
  end
  else if StartsText('array of', AName) or StartsText('TArray<', AName) or MatchText(AName, DynamicArrayNames) then
  begin
    Result := 'dynamische Arrays';
  end;
end;

function TManagedTypes.DeclManaged(ADecl: TSyntaxNode; ADepth: Integer): string;
var
  mBody: TSyntaxNode;
begin
  Result := '';
  mBody := ADecl.FindChild(TSyntaxKind.ProcedureType);
  if ADecl.FindChild(TSyntaxKind.RecordType) <> nil then
  begin
    Result := FieldsManaged(ADecl.FindChild(TSyntaxKind.RecordType), ADepth);
  end
  else if ADecl.FindChild(TSyntaxKind.InterfaceType) <> nil then
  begin
    Result := 'Interfaces';
  end
  else if (mBody <> nil) and SameText(mBody.Name, 'reference') then
  begin
    Result := 'Methodenreferenzen';
  end
  else if (ADecl.FindChild(TSyntaxKind.TypeReference) <> nil) or (ADecl.FindChild(TSyntaxKind.ArrayType) <> nil) then
  begin
    Result := Managed(NodeTypeText(ADecl), ADepth + 1);
  end;
end;

function TManagedTypes.Managed(const ATypeName: string; ADepth: Integer): string;
var
  mName: string;
  mDecl: TSyntaxNode;
  mIndex: Integer;
begin
  Result := '';
  mName := Trim(ATypeName);
  if (mName = '') or (ADepth > 16) then
  begin
    Exit;
  end;
  Result := NamedKind(mName);
  if Result <> '' then
  begin
    Exit;
  end;
  // Statisches Array: verwaltet, wenn die Elemente es sind.
  mIndex := Pos(' of ', LowerCase(mName));
  if StartsText('array', mName) and (mIndex > 0) then
  begin
    Result := Managed(Copy(mName, mIndex + 4, MaxInt), ADepth + 1);
  end
  else if not StartsText('array', mName) and (Pos('<', mName) = 0) then
  begin
    mDecl := TypeDecl(mName);
    if mDecl = nil then
    begin
      Result := IndexManaged(mName, ADepth);
    end
    else
    begin
      Result := DeclManaged(mDecl, ADepth);
    end;
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

function TManagedTypes.SymbolCustomManaged(const ASymbol: TIndexSymbol; ADepth: Integer): Boolean;
begin
  if ASymbol.Kind = TIndexSymbolKind.Method then
  begin
    Result := MatchText(ASymbol.Name, ['Initialize', 'Finalize']) and ContainsText(ASymbol.Signature, 'operator');
  end
  else
  begin
    Result := (ASymbol.Kind = TIndexSymbolKind.Field) and CustomManaged(ASymbol.TypeName, ADepth + 1);
  end;
end;

function TManagedTypes.IndexCustomManaged(const AName: string; ADepth: Integer): Boolean;
var
  mLocation: TSymbolLocation;
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  Result := False;
  // Es zählt das erste Symbol der obersten Ebene.
  if not TopLevelSymbol(AName, mLocation) then
  begin
    Exit;
  end;
  if mLocation.Symbol.Kind = TIndexSymbolKind.TypeAlias then
  begin
    Exit(CustomManaged(mLocation.Symbol.TypeName, ADepth + 1));
  end;
  if (mLocation.Symbol.Kind <> TIndexSymbolKind.RecordType) or not FIndex.FindFile(mLocation.FileName, mUnit) then
  begin
    Exit;
  end;
  for mSymbol in mUnit.Symbols do
  begin
    if SameText(mSymbol.Container, AName) and SymbolCustomManaged(mSymbol, ADepth) then
    begin
      Exit(True);
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
