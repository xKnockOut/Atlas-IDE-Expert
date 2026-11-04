unit Atlas.Common.Editing.GenericLists.State;

// Gemeinsamer Zustand der Listenumwandlung (#1105, #1106) und unterste Stufe der Klassenkette
// TGenericListState → TGenericListDeclarations (.Declarations) → TGenericListUsages (.Usages) →
// TGenericListConversion (Atlas.Common.Editing.GenericLists): Listenart, Namensauflösung, Dateien, Grund des
// Abbruchs, die umzuwandelnde Liste (TGenericListTarget) und was die Stufen über sie sammeln (Casts, Elemente,
// Properties, Namen für andere Units).

interface

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.GenericLists.Kinds,
  Atlas.Common.Editing.GenericLists.Source;

type
  {$SCOPEDENUMS ON}
  /// <summary>Gehört ein Name zur umzuwandelnden Liste?</summary>
  TGenericListMatch = (No, Yes, Unknown);
  {$SCOPEDENUMS OFF}

  /// <summary>Argument, das als Element in die Liste kommt.</summary>
  TGenericListElement = record
    FileIndex: Integer;
    Node: TSyntaxNode;
    /// <summary>Typ des Arguments; '' = unbekannt, 'nil' für nil.</summary>
    TypeName: string;
  end;

  /// <summary>Cast beim Lesen eines Elements.</summary>
  TGenericListCast = record
    FileIndex: Integer;
    TypeText: string;
    Line: Integer;
  end;

  /// <summary>Die umzuwandelnde Liste: Name, Deklaration und wo sie lebt.</summary>
  TGenericListTarget = record
    Name: string;
    /// <summary>Klasse bzw. Record des Felds; '' sonst.</summary>
    OwnerType: string;
    /// <summary>Unit der Deklaration.</summary>
    UnitName: string;
    Declaration: TSyntaxNode;
    DeclarationLine: Integer;
    /// <summary>Routine einer lokalen Variable; nil sonst.</summary>
    Scope: TSyntaxNode;
    IsField: Boolean;
    IsLocal: Boolean;
    /// <summary>ASymbol (aufgelöst unter AName in der Datei AFileIndex, 0 = eigene) ist die Liste bzw. eine ihrer
    /// Properties.</summary>
    function Accepts(const ASymbol: TResolvedSymbol; AFileIndex: Integer; const AName: string): Boolean;
    /// <summary>ANode liegt in der Routine der lokalen Variable.</summary>
    function InScope(ANode: TSyntaxNode): Boolean;
  private
    function IsOwnUnit(const ASymbol: TResolvedSymbol; AFileIndex: Integer): Boolean;
    function AcceptsLocal(const ASymbol: TResolvedSymbol): Boolean;
    function AcceptsField(const ASymbol: TResolvedSymbol; AFileIndex: Integer; const AName: string): Boolean;
    function AcceptsGlobal(const ASymbol: TResolvedSymbol; AFileIndex: Integer): Boolean;
  end;

  /// <summary>Zustand der Umwandlung, den alle Stufen teilen.</summary>
  TGenericListState = class
  protected
    FKind: TLegacyListKind;
    FResolver: TNameResolver;
    FFiles: TObjectList<TGenericListSource>;
    FReason: string;
    FTarget: TGenericListTarget;
    /// <summary>Die Liste wird hier mit Create erzeugt.</summary>
    FCreated: Boolean;
    /// <summary>Mindestens ein Elementtyp ist unbekannt: nicht Safe.</summary>
    FUnknown: Boolean;
    FProperties: TArray<string>;
    FExternalNames: TArray<string>;
    FCasts: TArray<TGenericListCast>;
    FElements: TArray<TGenericListElement>;
    /// <summary>Merkt den ersten Grund; liefert False.</summary>
    function Fail(const AReason: string): Boolean;
    function Failed: Boolean;
    function LineOf(ANode: TSyntaxNode): string;
    /// <summary>Elementtyp, wie ihn der erste Cast schreibt; '' ohne Cast.</summary>
    function ItemType: string;
    function GenericText: string;
    /// <summary>Datei aufnehmen und für die Namensauflösung pinnen; liefert ihren Index.</summary>
    function AddSource(ATree: TSyntaxTree; AOwnsTree: Boolean; const AText, AFileName: string): Integer;
    /// <summary>Namensauflösung an ANode; ohne Ergebnis wie unbekannt.</summary>
    function Resolves(ASource: TGenericListSource; ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol;
      out ATypeFound: Boolean): Boolean;
    /// <summary>T(X): genau ein Argument, Aufgerufener ist ein Typname (auch Unit.T); ATypeText ist T.</summary>
    function IsTypeCast(ASource: TGenericListSource; ACall: TSyntaxNode; out ATypeText: string): Boolean;
    function IsTypeName(ASource: TGenericListSource; ACallee: TSyntaxNode): Boolean;
  public
    constructor Create(const AKind: TLegacyListKind; AResolver: TNameResolver);
    destructor Destroy; override;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.GenericLists.Syntax;

{ TGenericListTarget }

function TGenericListTarget.IsOwnUnit(const ASymbol: TResolvedSymbol; AFileIndex: Integer): Boolean;
begin
  Result := (AFileIndex = 0) or SameText(ASymbol.UnitName, UnitName);
end;

function TGenericListTarget.AcceptsLocal(const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := (ASymbol.Kind = TResolvedKind.Local) and (ASymbol.Range.StartPos.Line <= DeclarationLine) and
    (ASymbol.Range.EndPos.Line >= DeclarationLine);
end;

function TGenericListTarget.AcceptsField(const ASymbol: TResolvedSymbol; AFileIndex: Integer;
  const AName: string): Boolean;
var
  mIsProperty: Boolean;
begin
  mIsProperty := not SameText(AName, Name);
  Result := (ASymbol.SymbolKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and
    SameText(TGenericListSyntax.LastName(ASymbol.Container), TGenericListSyntax.LastName(OwnerType)) and
    IsOwnUnit(ASymbol, AFileIndex) and ((ASymbol.SymbolKind = TIndexSymbolKind.Property_) = mIsProperty);
end;

function TGenericListTarget.AcceptsGlobal(const ASymbol: TResolvedSymbol; AFileIndex: Integer): Boolean;
begin
  Result := (ASymbol.SymbolKind = TIndexSymbolKind.Variable) and (ASymbol.Container = '') and
    IsOwnUnit(ASymbol, AFileIndex);
end;

function TGenericListTarget.Accepts(const ASymbol: TResolvedSymbol; AFileIndex: Integer;
  const AName: string): Boolean;
begin
  if IsLocal then
  begin
    Result := AcceptsLocal(ASymbol);
  end
  else if IsField then
  begin
    Result := AcceptsField(ASymbol, AFileIndex, AName);
  end
  else
  begin
    Result := AcceptsGlobal(ASymbol, AFileIndex);
  end;
end;

function TGenericListTarget.InScope(ANode: TSyntaxNode): Boolean;
begin
  Result := (Scope <> nil) and (ANode.StartOffset >= Scope.StartOffset) and (ANode.EndOffset <= Scope.EndOffset);
end;

{ TGenericListState }

constructor TGenericListState.Create(const AKind: TLegacyListKind; AResolver: TNameResolver);
begin
  inherited Create;
  FKind := AKind;
  FResolver := AResolver;
  FFiles := TObjectList<TGenericListSource>.Create(True);
end;

destructor TGenericListState.Destroy;
var
  mIndex: Integer;
begin
  // Jede Datei wurde einmal gepinnt; die Bäume erst danach freigeben.
  for mIndex := 0 to FFiles.Count - 1 do
  begin
    FResolver.UnpinTree;
  end;
  FFiles.Free;
  inherited;
end;

function TGenericListState.Fail(const AReason: string): Boolean;
begin
  if FReason = '' then
  begin
    FReason := AReason;
  end;
  Result := False;
end;

function TGenericListState.Failed: Boolean;
begin
  Result := FReason <> '';
end;

function TGenericListState.LineOf(ANode: TSyntaxNode): string;
begin
  Result := Format('Zeile %d', [ANode.StartPos.Line + 1]);
end;

function TGenericListState.ItemType: string;
begin
  Result := '';
  if FCasts <> nil then
  begin
    Result := FCasts[0].TypeText;
  end;
end;

function TGenericListState.GenericText: string;
begin
  Result := FKind.GenericText(ItemType);
end;

function TGenericListState.AddSource(ATree: TSyntaxTree; AOwnsTree: Boolean; const AText,
  AFileName: string): Integer;
begin
  Result := FFiles.Add(TGenericListSource.Create(ATree, AOwnsTree, AText, AFileName));
  FResolver.PinTree(ATree, AFileName);
end;

function TGenericListState.Resolves(ASource: TGenericListSource; ANode: TSyntaxNode;
  out ASymbol, AType: TResolvedSymbol; out ATypeFound: Boolean): Boolean;
begin
  try
    Result := FResolver.NodeType(ASource.Tree, ASource.FileName, ANode, ASymbol, AType, ATypeFound);
  except
    on EAbort do
      raise;
    on Exception do
    begin
      // Namensauflösung ohne Ergebnis: wie unbekannt behandeln.
      ASymbol := Default(TResolvedSymbol);
      AType := Default(TResolvedSymbol);
      ATypeFound := False;
      Result := False;
    end;
  end;
end;

function TGenericListState.IsTypeName(ASource: TGenericListSource; ACallee: TSyntaxNode): Boolean;
var
  mSymbol, mSymbolType: TResolvedSymbol;
  mTypeFound: Boolean;
  mName: string;
begin
  mName := TGenericListSyntax.LastName(ASource.NodeText(ACallee));
  if TGenericListNames.IsScalarType(mName) or MatchText(mName, ['TObject', 'string']) then
  begin
    Result := True;
  end
  else if Resolves(ASource, ACallee, mSymbol, mSymbolType, mTypeFound) and mSymbol.Found then
  begin
    Result := mSymbol.IsType;
  end
  else
  begin
    // Nicht auflösbar (Typ aus einer Unit außerhalb des Index): Delphi-Konvention T… bzw. P… für Typen.
    Result := (Length(mName) >= 2) and CharInSet(mName[1], ['T', 'P']) and CharInSet(mName[2], ['A'..'Z']);
  end;
end;

function TGenericListState.IsTypeCast(ASource: TGenericListSource; ACall: TSyntaxNode;
  out ATypeText: string): Boolean;
begin
  ATypeText := '';
  Result := TGenericListSyntax.IsSingleArgumentCall(ACall) and TGenericListSyntax.IsPlainName(ACall[0]) and
    IsTypeName(ASource, ACall[0]);
  if Result then
  begin
    ATypeText := ASource.NodeText(ACall[0]);
  end;
end;

end.
