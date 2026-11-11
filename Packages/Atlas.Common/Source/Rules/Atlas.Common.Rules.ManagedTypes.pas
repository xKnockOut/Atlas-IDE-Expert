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
  System.Generics.Collections,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TManagedTypesText = (MethodReferences, DynamicArrays);

const
  cTexts: array[TManagedTypesText] of TAtlasText = (
    (De: 'Methodenreferenzen'; En: 'method references'),
    (De: 'dynamische Arrays'; En: 'dynamic arrays'));

{$SCOPEDENUMS OFF}

const
  // RTL-Records mit verwalteten Feldern, auch ohne Index.
  cManagedStringRecords: array[0..2] of string = ('TFormatSettings', 'TSearchRec', 'TWin32FindData');
  cManagedInterfaceRecords: array[0..1] of string = ('TValue', 'TRttiContext');
  cDynamicArrayNames: array[0..5] of string = ('TBytes', 'TStringDynArray', 'TIntegerDynArray', 'TStringArray',
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
  mFound: TSyntaxNode;
  mName: string;
begin
  mFound := nil;
  mName := AName;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := mFound = nil;
      if Result and (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, mName) then
      begin
        mFound := ANode;
      end;
    end);
  Result := mFound;
end;

function TManagedTypes.NodeTypeText(ANode: TSyntaxNode): string;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := '';
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mChild := ANode[mIndex];
    if mChild.Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.PointerType,
      TSyntaxKind.RecordType, TSyntaxKind.ClassType, TSyntaxKind.InterfaceType, TSyntaxKind.ClassOfType,
      TSyntaxKind.SetType, TSyntaxKind.EnumType, TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType] then
    begin
      Exit(Trim(Copy(FText, mChild.StartOffset + 1, mChild.EndOffset - mChild.StartOffset)));
    end;
  end;
end;

// Iterativ (tiefe Bäume sprengen den Stapel nicht).
function TManagedTypes.FieldsManaged(ARecord: TSyntaxNode; ADepth: Integer): string;
var
  mPending: TStack<TSyntaxNode>;
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := '';
  mPending := TStack<TSyntaxNode>.Create;
  try
    for mIndex := ARecord.ChildCount - 1 downto 0 do
    begin
      mPending.Push(ARecord[mIndex]);
    end;
    while mPending.Count > 0 do
    begin
      mChild := mPending.Pop;
      // Verschachtelte Typdeklarationen sind keine Felder.
      if mChild.Kind = TSyntaxKind.TypeDecl then
      begin
        Continue;
      end;
      if mChild.Kind = TSyntaxKind.Field then
      begin
        Result := Managed(NodeTypeText(mChild), ADepth + 1);
        if Result <> '' then
        begin
          Exit;
        end;
      end
      else if not (mChild.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl]) then
      begin
        for mIndex := mChild.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mChild[mIndex]);
        end;
      end;
    end;
  finally
    mPending.Free;
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
        Result := cTexts[TManagedTypesText.MethodReferences].Text;
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
  mName: string;
begin
  mName := Trim(ATypeName);
  Result := MatchText(mName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'UTF8String',
    'Variant', 'OleVariant', 'IInterface', 'IUnknown', 'IDispatch']) or MatchText(mName, cDynamicArrayNames) or
    StartsText('array of', mName) or StartsText('TArray<', mName);
end;

/// <summary>Art verwalteter Daten, die schon der Name verrät (Strings, Variants, Interfaces, Methodenreferenzen,
/// dynamische Arrays und bekannte RTL-Records); '' sonst.</summary>
function NamedKind(const AName: string): string;
begin
  Result := '';
  if MatchText(AName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'UTF8String']) or
    MatchText(AName, cManagedStringRecords) then
  begin
    Result := 'Strings';
  end
  else if MatchText(AName, ['Variant', 'OleVariant']) then
  begin
    Result := 'Variants';
  end
  else if MatchText(AName, ['IInterface', 'IUnknown', 'IDispatch']) or MatchText(AName, cManagedInterfaceRecords) then
  begin
    Result := 'Interfaces';
  end
  else if StartsText('reference to', AName) then
  begin
    Result := cTexts[TManagedTypesText.MethodReferences].Text;
  end
  else if StartsText('array of', AName) or StartsText('TArray<', AName) or MatchText(AName, cDynamicArrayNames) then
  begin
    Result := cTexts[TManagedTypesText.DynamicArrays].Text;
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
    Result := cTexts[TManagedTypesText.MethodReferences].Text;
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
  mName: string;
  mDecl: TSyntaxNode;
begin
  Result := '';
  mName := Trim(ATypeName);
  if StartsText('^', mName) then
  begin
    Exit(Trim(Copy(mName, 2, MaxInt)));
  end;
  if (mName = '') or (Pos('<', mName) > 0) then
  begin
    Exit;
  end;
  mDecl := TypeDecl(mName);
  if (mDecl <> nil) and (mDecl.FindChild(TSyntaxKind.PointerType) <> nil) then
  begin
    Result := NodeTypeText(mDecl);
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

// Iterativ (tiefe Bäume sprengen den Stapel nicht).
function TManagedTypes.FieldsCustomManaged(ARecord: TSyntaxNode; ADepth: Integer): Boolean;
var
  mPending: TStack<TSyntaxNode>;
  mIndex: Integer;
  mChild: TSyntaxNode;
  mHead: string;
begin
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    for mIndex := ARecord.ChildCount - 1 downto 0 do
    begin
      mPending.Push(ARecord[mIndex]);
    end;
    while mPending.Count > 0 do
    begin
      mChild := mPending.Pop;
      if mChild.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.PropertyDecl] then
      begin
        Continue;
      end;
      if mChild.Kind = TSyntaxKind.RoutineHeader then
      begin
        mHead := Copy(FText, mChild.StartOffset + 1, mChild.EndOffset - mChild.StartOffset);
        Result := MatchText(mChild.Name, ['Initialize', 'Finalize']) and ContainsText(mHead, 'operator');
      end
      else if mChild.Kind = TSyntaxKind.Field then
      begin
        Result := CustomManaged(NodeTypeText(mChild), ADepth + 1);
      end
      else
      begin
        for mIndex := mChild.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mChild[mIndex]);
        end;
      end;
      if Result then
      begin
        Exit;
      end;
    end;
  finally
    mPending.Free;
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
  mName: string;
  mDecl, mBody: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mName := Trim(ATypeName);
  if (mName = '') or (ADepth > 16) or (Pos('<', mName) > 0) or StartsText('array of', mName) then
  begin
    Exit;
  end;
  if StartsText('array', mName) then
  begin
    mIndex := Pos(' of ', LowerCase(mName));
    if mIndex > 0 then
    begin
      Result := CustomManaged(Copy(mName, mIndex + 4, MaxInt), ADepth + 1);
    end;
    Exit;
  end;
  mDecl := TypeDecl(mName);
  if mDecl = nil then
  begin
    Exit(IndexCustomManaged(mName, ADepth));
  end;
  mBody := mDecl.FindChild(TSyntaxKind.RecordType);
  if mBody <> nil then
  begin
    Exit(FieldsCustomManaged(mBody, ADepth));
  end;
  if (mDecl.FindChild(TSyntaxKind.TypeReference) <> nil) or (mDecl.FindChild(TSyntaxKind.ArrayType) <> nil) then
  begin
    Result := CustomManaged(NodeTypeText(mDecl), ADepth + 1);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.ManagedTypes', cTexts);

end.
