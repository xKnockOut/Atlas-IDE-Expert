unit Atlas.Common.Editing.FreeFields.Types;

// Typauflösung für „Felder im Destruktor freigeben“ (#666): Art eines Typs
// (Klasse, Record, Interface, anderes) und Vorfahrenkette aus der Datei und dem
// Index, ob eine Klasse eine Komponente ist, welche Feldtypen eine Klasse hat
// und welchen Typ ein Feld eines Records hat.
// Ohne Deklaration helfen bekannte Records der RTL und die Namensregel IFoo.

interface

uses
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
    function FromFile(const AName: string; out AAlias: string): TTypeGuess;
    function IndexGuess(const ABase: string; AGeneric: Boolean; out AFound: Boolean): TTypeGuess;
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
  OwnerNames: array[0..3] of string = ('Self', 'AOwner', 'Owner', 'Application');
  // Records der RTL mit Create; ohne Index sähen sie wie Klassen aus.
  KnownRecords: array[0..14] of string = ('TStopwatch', 'TTimeSpan', 'TRect', 'TRectF', 'TPoint', 'TPointF',
    'TSize', 'TSizeF', 'TGUID', 'TFormatSettings', 'TValue', 'TEncodingHelper', 'TRegEx', 'TMatch', 'TRttiContext');
  /// <summary>Häufige VCL-Komponenten ohne einen der ComponentRoots im Namen (#918).</summary>
  KnownComponents: array[0..21] of string = ('TMenuItem', 'TMenu', 'TPopupMenu', 'TMainMenu', 'TTimer',
    'TActionList', 'TAction', 'TBasicAction', 'TImageList', 'TCustomImageList', 'TCommonDialog', 'TOpenDialog',
    'TSaveDialog', 'TApplicationEvents', 'TComboBox', 'TEdit', 'TButton', 'TLabel', 'TListBox', 'TMemo',
    'TCheckBox', 'TScrollBox');
  /// <summary>Häufige Klassen, die sicher keine Komponenten sind.</summary>
  KnownNonComponents: array[0..9] of string = ('TObject', 'TInterfacedObject', 'TPersistent', 'TThread',
    'TStream', 'TStrings', 'TStringList', 'TList', 'TObjectList', 'TDictionary');

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

class function TFreeFieldTypes.CodeOf(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Collapse(NodeText(AText, ANode));
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
  if MatchText(ABase, KnownRecords) then
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

constructor TFreeFieldTypes.Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FIndex := AIndex;
end;

function TFreeFieldTypes.FromFile(const AName: string; out AAlias: string): TTypeGuess;
var
  mGuess: TTypeGuess;
  mFound, mName: string;
begin
  // out-Parameter lassen sich nicht in der anonymen Methode verwenden.
  mGuess := tgUnknown;
  mFound := '';
  mName := AName;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mIndex: Integer;
    begin
      Result := mGuess = tgUnknown;
      if not Result or (ANode.Kind <> TSyntaxKind.TypeDecl) or not SameText(ANode.Name, mName) then
      begin
        Exit;
      end;
      for mIndex := 0 to ANode.ChildCount - 1 do
      begin
        if KindGuess(ANode[mIndex].Kind) <> tgUnknown then
        begin
          mGuess := KindGuess(ANode[mIndex].Kind);
        end
        else if (ANode[mIndex].Kind = TSyntaxKind.TypeReference) and (mFound = '') then
        begin
          mFound := ANode[mIndex].Name;
        end;
      end;
    end);
  AAlias := mFound;
  Result := mGuess;
end;

function TFreeFieldTypes.IndexGuess(const ABase: string; AGeneric: Boolean; out AFound: Boolean): TTypeGuess;
var
  mLocation: TSymbolLocation;
begin
  AFound := False;
  Result := tgUnknown;
  if FIndex = nil then
  begin
    Exit;
  end;
  for mLocation in FIndex.FindSymbols(ABase) do
  begin
    // Mit Typargumenten zählen nur generische Typen gleichen Namens.
    if (mLocation.Symbol.Container = '') and not (AGeneric and (mLocation.Symbol.TypeParams = '')) then
    begin
      Result := IndexKindGuess(mLocation.Symbol.Kind);
      if Result <> tgUnknown then
      begin
        AFound := True;
        Exit;
      end;
    end;
  end;
end;

function TFreeFieldTypes.TypeGuess(const ATypeName: string): TTypeGuess;
var
  mBase, mAlias: string;
  mDepth: Integer;
  mGeneric, mFound: Boolean;
begin
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
    if (Result = tgUnknown) and (mAlias = '') then
    begin
      Result := IndexGuess(mBase, mGeneric, mFound);
      if not mFound then
      begin
        Break;
      end;
    end;
    if Result <> tgUnknown then
    begin
      Exit;
    end;
    // Alias in der Datei (TFoo = TBar): weiter mit TBar.
    mBase := TFreeFieldTypes.BaseName(mAlias);
    mGeneric := Pos('<', mAlias) > 0;
  end;
  Result := FallbackGuess(mBase);
end;

function TFreeFieldTypes.FileAncestor(const AName: string; out ANext: string): Boolean;
var
  mName, mNext: string;
  mDeclared: Boolean;
begin
  mName := AName;
  mNext := '';
  mDeclared := False;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mKind: TSyntaxNode;
    begin
      Result := not mDeclared;
      if not Result or (ANode.Kind <> TSyntaxKind.TypeDecl) or not SameText(ANode.Name, mName) then
      begin
        Exit;
      end;
      mKind := ANode.FindChild(TSyntaxKind.ClassType);
      if mKind <> nil then
      begin
        mDeclared := True;
        mNext := FirstAncestor(mKind);
      end;
    end);
  ANext := mNext;
  Result := mDeclared;
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
  AEndsKnown := AEndsKnown or DescendsFrom(Result, ComponentRoots) or DescendsFrom(Result, KnownComponents) or
    DescendsFrom(Result, KnownNonComponents);
end;

function TFreeFieldTypes.IsComponent(const ATypeName: string): Boolean;
var
  mChain: TArray<string>;
  mEndsKnown: Boolean;
begin
  mChain := ComponentChain(ATypeName, mEndsKnown);
  Result := DescendsFrom(mChain, ComponentRoots) or DescendsFrom(mChain, KnownComponents);
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
    (AArgument.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and MatchText(AArgument.Name, OwnerNames);
end;

function TFreeFieldTypes.FileFieldTypes(const AClassName: string; out ADeclared: Boolean): TArray<string>;
var
  mFound: TArray<string>;
  mDeclared: Boolean;
  mName, mText: string;
begin
  // out- und Result-Werte lassen sich nicht in der anonymen Methode füllen.
  mFound := nil;
  mDeclared := False;
  mName := AClassName;
  mText := FText;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mClassNode: TSyntaxNode;
    begin
      Result := not mDeclared;
      if not Result or (ANode.Kind <> TSyntaxKind.TypeDecl) or not SameText(ANode.Name, mName) then
      begin
        Exit;
      end;
      mClassNode := ANode.FindChild(TSyntaxKind.ClassType);
      if mClassNode <> nil then
      begin
        mDeclared := True;
        mFound := FieldTypesOf(mClassNode, mText);
      end;
    end);
  ADeclared := mDeclared;
  Result := mFound;
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
  mFound, mName, mMember, mText: string;
begin
  // Result lässt sich nicht in der anonymen Methode füllen.
  mFound := '';
  mName := ATypeName;
  mMember := AMember;
  mText := FText;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mTypeNode: TSyntaxNode;
    begin
      Result := mFound = '';
      if not Result or (ANode.Kind <> TSyntaxKind.TypeDecl) or not SameText(ANode.Name, mName) then
      begin
        Exit;
      end;
      mTypeNode := ANode.FindChild(TSyntaxKind.RecordType);
      if mTypeNode = nil then
      begin
        mTypeNode := ANode.FindChild(TSyntaxKind.ClassType);
      end;
      if mTypeNode <> nil then
      begin
        mFound := MemberTypeOf(mTypeNode, mText, mMember);
      end;
    end);
  Result := mFound;
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

function TFreeFieldTypes.MemberType(const ATypeName, AMember: string): string;
begin
  Result := FileMemberType(TFreeFieldTypes.BaseName(ATypeName), AMember);
  if Result = '' then
  begin
    Result := IndexMemberType(TFreeFieldTypes.BaseName(ATypeName), AMember);
  end;
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

end.
