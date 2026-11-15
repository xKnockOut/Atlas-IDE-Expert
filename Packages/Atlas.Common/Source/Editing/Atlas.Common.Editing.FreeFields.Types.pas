unit Atlas.Common.Editing.FreeFields.Types;

// Typauflösung für „Felder im Destruktor freigeben“ (#666): Art eines Typs
// (Klasse, Record, Interface, anderes) und Vorfahrenkette aus der Datei und dem
// Index, ob eine Klasse eine Komponente ist, welche Feldtypen eine Klasse hat
// und welchen Typ ein Feld eines Records hat.
// Aliase (TPos = Werk.Lage.TLage) gelten in der Datei und im Index; der
// Namensraum vor dem Ziel zählt nicht (TLage).
// Ohne Deklaration helfen bekannte Records der RTL und die Namensregel IFoo.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TTypeGuess = (tgUnknown, tgClass, tgRecord, tgInterface, tgOther);

  /// <summary>Art und Vorfahren von Typen aus Datei und Index.</summary>
  TFreeFieldTypes = class
  strict private
    FTree: TSyntaxTree;
    FText: string;
    FIndex: ISymbolIndex;
    // Typdeklarationen der Datei je Name (klein) in Vorordnung, beim ersten Bedarf in einem Lauf gesammelt: Je
    // Feld den ganzen Baum zu durchsuchen war quadratisch (große Header-Units).
    FDecls: TDictionary<string, TArray<TSyntaxNode>>;
    function DeclsNamed(const AName: string): TArray<TSyntaxNode>;
    function FromFile(const AName: string; out AAlias: string): TTypeGuess;
    function IndexGuess(const ABase: string; AGeneric: Boolean; out AAlias: string): TTypeGuess;
    function FileAncestor(const AName: string; out ANext: string): Boolean;
    function IndexAncestor(const AName: string; out ANext: string): Boolean;
    function FileFieldTypes(const AClassName: string; out ADeclared: Boolean): TArray<string>;
    function IndexFieldTypes(const AClassName: string): TArray<string>;
    function FileMemberType(const ATypeName, AMember: string): string;
    function IndexMemberType(const ATypeName, AMember: string): string;
  public
    /// <summary>Quelltext eines Knotens.</summary>
    class function NodeText(const AText: string; ANode: TSyntaxNode): string; static;
    /// <summary>Leerraum zu je einem Leerzeichen zusammenfassen.</summary>
    class function Collapse(const AText: string): string; static;
    /// <summary>Name ohne generische Argumente: TObjectList&lt;TOrder&gt; → TObjectList.</summary>
    class function BaseName(const ATypeName: string): string; static;
    /// <summary>Quelltext eines Knotens mit zusammengefasstem Leerraum.</summary>
    class function CodeOf(const AText: string; ANode: TSyntaxNode): string; static;
    constructor Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex);
    destructor Destroy; override;
    function TypeGuess(const ATypeName: string): TTypeGuess;
    function ComponentChain(const ATypeName: string; out AEndsKnown: Boolean): TArray<string>;
    function IsComponent(const ATypeName: string): Boolean;
    /// <summary>True, wenn die Vorfahrenkette von ATypeName sicher endet: bei einer Komponente, bei
    /// einer Klasse ohne Vorfahren oder bei einer bekannten Nicht-Komponente (#918).</summary>
    function ComponentKnown(const ATypeName: string): Boolean;
    /// <summary>Gibt der Owner AArgument (ungleich nil) die erzeugte Komponente frei?</summary>
    function OwnedByArgument(const ATypeName: string; AArgument: TSyntaxNode): Boolean;
    /// <summary>Typen der Felder der Klasse AClassName aus Datei oder Index, samt Typargumenten.</summary>
    function ClassFieldTypes(const AClassName: string): TArray<string>;
    /// <summary>Typ des Felds AMember von Record oder Klasse ATypeName aus Datei oder Index; '' unbekannt.
    /// </summary>
    function MemberType(const ATypeName, AMember: string): string;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Editing.ClassMembers;

const
  cOwnerNames: array[0..3] of string = ('Self', 'AOwner', 'Owner', 'Application');
  // Records der RTL mit Create; ohne Index sähen sie wie Klassen aus.
  cKnownRecords: array[0..14] of string = ('TStopwatch', 'TTimeSpan', 'TRect', 'TRectF', 'TPoint', 'TPointF',
    'TSize', 'TSizeF', 'TGUID', 'TFormatSettings', 'TValue', 'TEncodingHelper', 'TRegEx', 'TMatch', 'TRttiContext');
  /// <summary>Häufige VCL-Komponenten ohne einen der ComponentRoots im Namen (#918).</summary>
  cKnownComponents: array[0..21] of string = ('TMenuItem', 'TMenu', 'TPopupMenu', 'TMainMenu', 'TTimer',
    'TActionList', 'TAction', 'TBasicAction', 'TImageList', 'TCustomImageList', 'TCommonDialog', 'TOpenDialog',
    'TSaveDialog', 'TApplicationEvents', 'TComboBox', 'TEdit', 'TButton', 'TLabel', 'TListBox', 'TMemo',
    'TCheckBox', 'TScrollBox');
  /// <summary>Häufige Klassen, die sicher keine Komponenten sind.</summary>
  cKnownNonComponents: array[0..9] of string = ('TObject', 'TInterfacedObject', 'TPersistent', 'TThread',
    'TStream', 'TStrings', 'TStringList', 'TList', 'TObjectList', 'TDictionary');

{ TFreeFieldTypes }

constructor TFreeFieldTypes.Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FIndex := AIndex;
end;

destructor TFreeFieldTypes.Destroy;
begin
  FDecls.Free;
  inherited;
end;

function TFreeFieldTypes.DeclsNamed(const AName: string): TArray<TSyntaxNode>;
var
  mDecls: TDictionary<string, TArray<TSyntaxNode>>;
begin
  if FDecls = nil then
  begin
    mDecls := TDictionary<string, TArray<TSyntaxNode>>.Create;
    FDecls := mDecls;
    FTree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        mKey: string;
        mList: TArray<TSyntaxNode>;
      begin
        Result := True;
        if ANode.Kind = TSyntaxKind.TypeDecl then
        begin
          mKey := LowerCase(ANode.Name);
          if not mDecls.TryGetValue(mKey, mList) then
          begin
            mList := nil;
          end;
          SetLength(mList, Length(mList) + 1);
          mList[High(mList)] := ANode;
          mDecls.AddOrSetValue(mKey, mList);
        end;
      end);
  end;
  if not FDecls.TryGetValue(LowerCase(AName), Result) then
  begin
    Result := nil;
  end;
end;

function TFreeFieldTypes.IndexAncestor(const AName: string; out ANext: string): Boolean;
var
  mLocation: TSymbolLocation;
begin
  ANext := '';
  if FIndex = nil then
  begin
    Exit(False);
  end;
  for mLocation in FIndex.FindSymbols(AName) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) and (mLocation.Symbol.Container = '') then
    begin
      if Length(mLocation.Symbol.Ancestors) > 0 then
      begin
        ANext := TFreeFieldTypes.BaseName(mLocation.Symbol.Ancestors[0]);
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TFreeFieldTypes.NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

class function TFreeFieldTypes.Collapse(const AText: string): string;
var
  mIndex: Integer;
  mSpace: Boolean;
begin
  Result := '';
  mSpace := False;
  for mIndex := 1 to Length(AText) do
  begin
    if CharInSet(AText[mIndex], [' ', #9, #10, #13]) then
    begin
      mSpace := True;
    end
    else
    begin
      if mSpace and (Result <> '') then
      begin
        Result := Result + ' ';
      end;
      mSpace := False;
      Result := Result + AText[mIndex];
    end;
  end;
end;

/// <summary>Art eines Typknotens; tgUnknown für Verweise und Unbekanntes.</summary>
function KindGuess(AKind: TSyntaxKind): TTypeGuess;
begin
  case AKind of
    TSyntaxKind.ClassType:
      Result := tgClass;
    TSyntaxKind.RecordType:
      Result := tgRecord;
    TSyntaxKind.InterfaceType:
      Result := tgInterface;
    TSyntaxKind.ObjectType, TSyntaxKind.ClassOfType, TSyntaxKind.EnumType, TSyntaxKind.SetType,
    TSyntaxKind.ArrayType, TSyntaxKind.PointerType, TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType,
    TSyntaxKind.HelperType:
      Result := tgOther;
  else
    Result := tgUnknown;
  end;
end;

/// <summary>Art eines Symbols aus dem Index; tgUnknown für übrige Arten.</summary>
function IndexKindGuess(AKind: TIndexSymbolKind): TTypeGuess;
begin
  case AKind of
    TIndexSymbolKind.ClassType:
      Result := tgClass;
    TIndexSymbolKind.RecordType:
      Result := tgRecord;
    TIndexSymbolKind.InterfaceType:
      Result := tgInterface;
    TIndexSymbolKind.ObjectType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType:
      Result := tgOther;
  else
    Result := tgUnknown;
  end;
end;

/// <summary>Ohne Deklaration: bekannte Records der RTL und Namen wie IFoo.</summary>
function FallbackGuess(const ABase: string): TTypeGuess;
begin
  Result := tgUnknown;
  if MatchText(ABase, cKnownRecords) then
  begin
    Result := tgRecord;
  end
  else if TRegEx.IsMatch(ABase, '^I[A-Z]') then
  begin
    Result := tgInterface;
  end;
end;

/// <summary>Erster Vorfahr einer Klassendeklaration; '' ohne.</summary>
function FirstAncestor(AClassNode: TSyntaxNode): string;
begin
  Result := '';
  if (AClassNode.ChildCount > 0) and (AClassNode[0].Kind = TSyntaxKind.TypeReference) then
  begin
    Result := AClassNode[0].Name;
  end;
end;

/// <summary>Typen der Felder einer Klassendeklaration.</summary>
function FieldTypesOf(AClassNode: TSyntaxNode; const AText: string): TArray<string>;
var
  mIndex: Integer;
  mTypeRef: TSyntaxNode;
begin
  Result := nil;
  for mIndex := 0 to AClassNode.ChildCount - 1 do
  begin
    if AClassNode[mIndex].Kind = TSyntaxKind.Field then
    begin
      mTypeRef := AClassNode[mIndex].FindChild(TSyntaxKind.TypeReference);
      if mTypeRef <> nil then
      begin
        Result := Result + [TFreeFieldTypes.CodeOf(AText, mTypeRef)];
      end;
    end;
  end;
end;

/// <summary>Typ des Felds AMember unter den Feldern von ATypeNode (Record oder Klasse); '' sonst.</summary>
function MemberTypeOf(ATypeNode: TSyntaxNode; const AText, AMember: string): string;
var
  mIndex: Integer;
  mName: string;
  mTypeRef: TSyntaxNode;
begin
  Result := '';
  for mIndex := 0 to ATypeNode.ChildCount - 1 do
  begin
    mTypeRef := ATypeNode[mIndex].FindChild(TSyntaxKind.TypeReference);
    if (ATypeNode[mIndex].Kind <> TSyntaxKind.Field) or (mTypeRef = nil) then
    begin
      Continue;
    end;
    for mName in ATypeNode[mIndex].Name.Split([',']) do
    begin
      if SameText(Trim(mName), AMember) then
      begin
        Exit(TFreeFieldTypes.CodeOf(AText, mTypeRef));
      end;
    end;
  end;
end;

/// <summary>Typ eines Felds aus dem Index samt Typargumenten.</summary>
function IndexTypeName(const ASymbol: TIndexSymbol): string;
begin
  Result := TFreeFieldTypes.BaseName(ASymbol.TypeName);
  if ASymbol.TypeArgs <> '' then
  begin
    Result := Result + '<' + ASymbol.TypeArgs + '>';
  end;
end;

/// <summary>Typen der Felder der Klasse AClassName in einer Unit des Index.</summary>
function UnitFieldTypes(const AUnit: TUnitIndex; const AClassName: string): TArray<string>;
var
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, AClassName) then
    begin
      Result := Result + [IndexTypeName(mSymbol)];
    end;
  end;
end;

{ TFreeFieldTypes }

function TFreeFieldTypes.FromFile(const AName: string; out AAlias: string): TTypeGuess;
var
  mDecl: TSyntaxNode;
  mIndex: Integer;
begin
  // Gleichnamige Deklarationen der Reihe nach, bis eine die Art verrät; Alias ist der erste Verweis.
  Result := tgUnknown;
  AAlias := '';
  for mDecl in DeclsNamed(AName) do
  begin
    for mIndex := 0 to mDecl.ChildCount - 1 do
    begin
      if KindGuess(mDecl[mIndex].Kind) <> tgUnknown then
      begin
        Result := KindGuess(mDecl[mIndex].Kind);
      end
      else if (mDecl[mIndex].Kind = TSyntaxKind.TypeReference) and (AAlias = '') then
      begin
        AAlias := mDecl[mIndex].Name;
      end;
    end;
    if Result <> tgUnknown then
    begin
      Exit;
    end;
  end;
end;

function TFreeFieldTypes.FileAncestor(const AName: string; out ANext: string): Boolean;
var
  mDecl, mKind: TSyntaxNode;
begin
  ANext := '';
  for mDecl in DeclsNamed(AName) do
  begin
    mKind := mDecl.FindChild(TSyntaxKind.ClassType);
    if mKind <> nil then
    begin
      ANext := FirstAncestor(mKind);
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Alias der obersten Ebene mit Ziel (TPos = Werk.Lage.TLage)?</summary>
function IsIndexAlias(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Kind = TIndexSymbolKind.TypeAlias) and (ASymbol.Container = '') and (ASymbol.TypeName <> '');
end;

function TFreeFieldTypes.IndexGuess(const ABase: string; AGeneric: Boolean; out AAlias: string): TTypeGuess;
var
  mLocation: TSymbolLocation;
begin
  AAlias := '';
  Result := tgUnknown;
  if FIndex = nil then
  begin
    Exit;
  end;
  // Eine Deklaration gleichen Namens geht vor; sonst das Ziel des ersten Alias.
  for mLocation in FIndex.FindSymbols(ABase) do
  begin
    if IsIndexAlias(mLocation.Symbol) and (AAlias = '') then
    begin
      AAlias := mLocation.Symbol.TypeName;
    end
    // Mit Typargumenten zählen nur generische Typen gleichen Namens.
    else if (mLocation.Symbol.Container = '') and not (AGeneric and (mLocation.Symbol.TypeParams = '')) then
    begin
      Result := IndexKindGuess(mLocation.Symbol.Kind);
      if Result <> tgUnknown then
      begin
        Exit;
      end;
    end;
  end;
end;

/// <summary>Letzter Teil eines Typnamens ohne Typargumente: TLage aus Werk.Lage.TLage&lt;T&gt;.</summary>
function UnqualifiedBase(const ATypeName: string): string;
begin
  Result := TFreeFieldTypes.BaseName(ATypeName);
  if Pos('.', Result) > 0 then
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

function TFreeFieldTypes.FileFieldTypes(const AClassName: string; out ADeclared: Boolean): TArray<string>;
var
  mDecl, mClassNode: TSyntaxNode;
begin
  Result := nil;
  ADeclared := False;
  for mDecl in DeclsNamed(AClassName) do
  begin
    mClassNode := mDecl.FindChild(TSyntaxKind.ClassType);
    if mClassNode <> nil then
    begin
      ADeclared := True;
      Result := FieldTypesOf(mClassNode, FText);
      Exit;
    end;
  end;
end;

function TFreeFieldTypes.IndexFieldTypes(const AClassName: string): TArray<string>;
var
  mLocation: TSymbolLocation;
  mUnit: TUnitIndex;
begin
  Result := nil;
  if FIndex = nil then
  begin
    Exit;
  end;
  for mLocation in FIndex.FindSymbols(AClassName) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) and (mLocation.Symbol.Container = '') and
      FIndex.FindUnit(mLocation.UnitName, mUnit) then
    begin
      Exit(UnitFieldTypes(mUnit, AClassName));
    end;
  end;
end;

function TFreeFieldTypes.FileMemberType(const ATypeName, AMember: string): string;
var
  mDecl, mTypeNode: TSyntaxNode;
begin
  Result := '';
  for mDecl in DeclsNamed(ATypeName) do
  begin
    mTypeNode := mDecl.FindChild(TSyntaxKind.RecordType);
    if mTypeNode = nil then
    begin
      mTypeNode := mDecl.FindChild(TSyntaxKind.ClassType);
    end;
    if mTypeNode <> nil then
    begin
      Result := MemberTypeOf(mTypeNode, FText, AMember);
      if Result <> '' then
      begin
        Exit;
      end;
    end;
  end;
end;

function TFreeFieldTypes.IndexMemberType(const ATypeName, AMember: string): string;
var
  mLocation: TSymbolLocation;
begin
  Result := '';
  if FIndex = nil then
  begin
    Exit;
  end;
  for mLocation in FIndex.FindSymbols(AMember) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.Field) and SameText(mLocation.Symbol.Container, ATypeName) then
    begin
      Exit(IndexTypeName(mLocation.Symbol));
    end;
  end;
end;

class function TFreeFieldTypes.BaseName(const ATypeName: string): string;
var
  mAngle: Integer;
begin
  Result := Trim(ATypeName);
  mAngle := Pos('<', Result);
  if mAngle > 0 then
  begin
    Result := Trim(Copy(Result, 1, mAngle - 1));
  end;
end;

class function TFreeFieldTypes.CodeOf(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Collapse(NodeText(AText, ANode));
end;

function TFreeFieldTypes.TypeGuess(const ATypeName: string): TTypeGuess;
var
  mBase, mAlias: string;
  mDepth: Integer;
  mGeneric: Boolean;
begin
  Result := tgUnknown;
  mBase := TFreeFieldTypes.BaseName(ATypeName);
  // TArray<T> ist ein dynamisches Array aus System; die Klasse TArray (System.Generics.Collections) trägt
  // keine Typparameter.
  mGeneric := Pos('<', ATypeName) > 0;
  if mGeneric and SameText(mBase, 'TArray') then
  begin
    Exit(tgOther);
  end;
  for mDepth := 1 to 8 do
  begin
    if mBase = '' then
    begin
      Break;
    end;
    Result := FromFile(mBase, mAlias);
    // Ohne Deklaration oder mit Alias gleichen Namens (TLage = Werk.Lage.TLage): Der Index kennt das Ziel.
    if (Result = tgUnknown) and ((mAlias = '') or SameText(UnqualifiedBase(mAlias), mBase)) then
    begin
      Result := IndexGuess(mBase, mGeneric, mAlias);
    end;
    if (Result <> tgUnknown) or (mAlias = '') or SameText(UnqualifiedBase(mAlias), mBase) then
    begin
      Break;
    end;
    // Alias in der Datei oder im Index (TFoo = TBar, TFoo = Werk.TBar): weiter mit TBar.
    mBase := UnqualifiedBase(mAlias);
    mGeneric := Pos('<', mAlias) > 0;
  end;
  if Result <> tgUnknown then
  begin
    Exit;
  end;
  Result := FallbackGuess(mBase);
end;

function TFreeFieldTypes.ComponentChain(const ATypeName: string; out AEndsKnown: Boolean): TArray<string>;
var
  mName, mNext: string;
  mDepth: Integer;
  mDeclared: Boolean;
begin
  mName := TFreeFieldTypes.BaseName(ATypeName);
  Result := TArray<string>.Create(mName);
  AEndsKnown := False;
  for mDepth := 1 to 32 do
  begin
    mDeclared := FileAncestor(mName, mNext) or IndexAncestor(mName, mNext);
    // Klasse ohne Vorfahren stammt von TObject ab: das Ende ist bekannt.
    if mDeclared and (mNext = '') then
    begin
      AEndsKnown := True;
    end;
    if (mNext = '') or (IndexText(mNext, Result) >= 0) then
    begin
      Break;
    end;
    Result := Result + [mNext];
    mName := mNext;
  end;
  AEndsKnown := AEndsKnown or DescendsFrom(Result, cComponentRoots) or DescendsFrom(Result, cKnownComponents) or
    DescendsFrom(Result, cKnownNonComponents);
end;

function TFreeFieldTypes.IsComponent(const ATypeName: string): Boolean;
var
  mChain: TArray<string>;
  mEndsKnown: Boolean;
begin
  mChain := ComponentChain(ATypeName, mEndsKnown);
  Result := DescendsFrom(mChain, cComponentRoots) or DescendsFrom(mChain, cKnownComponents);
end;

function TFreeFieldTypes.ComponentKnown(const ATypeName: string): Boolean;
begin
  ComponentChain(ATypeName, Result);
end;

function TFreeFieldTypes.OwnedByArgument(const ATypeName: string; AArgument: TSyntaxNode): Boolean;
begin
  if IsComponent(ATypeName) then
  begin
    Exit(True);
  end;
  // Unbekannte Vorfahren (z. B. VCL-Klassen ohne Index): Owner am Argument erkennen.
  Result := not ComponentKnown(ATypeName) and
    (AArgument.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and MatchText(AArgument.Name, cOwnerNames);
end;

function TFreeFieldTypes.ClassFieldTypes(const AClassName: string): TArray<string>;
var
  mDeclared: Boolean;
begin
  Result := FileFieldTypes(AClassName, mDeclared);
  if not mDeclared then
  begin
    Result := IndexFieldTypes(AClassName);
  end;
end;

function TFreeFieldTypes.MemberType(const ATypeName, AMember: string): string;
begin
  Result := FileMemberType(TFreeFieldTypes.BaseName(ATypeName), AMember);
  if Result = '' then
  begin
    Result := IndexMemberType(TFreeFieldTypes.BaseName(ATypeName), AMember);
  end;
end;

end.
