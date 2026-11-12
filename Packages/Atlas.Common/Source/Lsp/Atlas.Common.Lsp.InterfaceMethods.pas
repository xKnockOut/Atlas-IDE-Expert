unit Atlas.Common.Lsp.InterfaceMethods;

// Befehl atlas.server.interfaceMethods (#1785): welche Interface-Methoden die
// Methoden der Klassen einer Datei erfüllen, für die Marke an der
// Brotkrumenleiste des IDE-Plugins.
// Argumente: [uri]
// Antwort (Zeilen und Zeichen ab 0 wie im Protokoll), je Deklaration einer
// Methode in der Klasse (nicht der Rumpf):
//   {"methods": [{"line": 6, "name": "TKunde.Speichern",
//                 "interfaces": [{"name": "IKunde.Speichern", "unit": "KundenApi", "uri": "file:///…",
//                                 "line": 30, "character": 14}]}]}
// - Interfaces aus der Vorfahrenliste der Klasse samt ihrer Vorfahren
//   (IKunde = interface(IBasis)).
// - Zuordnungen „procedure IKunde.Speichern = Sichern;“ gelten: Dann erfüllt
//   Sichern die Methode, nicht Speichern.
// - Interfaces der Vorfahrklassen erfüllt eine Methode nur mit override
//   (sonst verdeckt sie die Methode des Vorfahren bloß).
// - Überladungen: zuerst nach Parametertypen (ohne Unit-Präfix, mit
//   eingesetzten Typargumenten), sonst, wenn es auf beiden Seiten nur eine
//   Methode des Namens gibt, nach dem Namen.
// Methoden ohne Interface fehlen. Ist das Dokument nicht geöffnet, ist die
// Liste leer.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  TInterfaceMethodTarget = record
    /// <summary>Interface und Methode, z. B. "IKunde.Speichern".</summary>
    Name: string;
    UnitName: string;
    FileName: string;
    /// <summary>Name der Methode im Interface.</summary>
    Range: TTextRange;
  end;

  TInterfaceMethodMark = record
    /// <summary>Zeile der Deklaration in der Klasse, 0-basiert.</summary>
    Line: Integer;
    /// <summary>Klasse und Methode, z. B. "TKunde.Speichern".</summary>
    Name: string;
    Targets: TArray<TInterfaceMethodTarget>;
  end;

  TLspInterfaceMethods = class
  public const
    cCommand = 'atlas.server.interfaceMethods';
  public
    /// <summary>Marken der Datei AFileName mit dem Baum ATree, nach Zeilen sortiert.</summary>
    class function Marks(AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName: string): TArray<TInterfaceMethodMark>; static;
    /// <summary>Antwort für AMarks (siehe Kopf der Unit); der Aufrufer übernimmt das Objekt.</summary>
    class function Json(const AMarks: TArray<TInterfaceMethodMark>): TJSONObject; static;
    /// <summary>Befehl atlas.server.interfaceMethods; der Aufrufer übernimmt das Ergebnis.</summary>
    class function Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AArguments: TJSONArray): TJSONValue;
      static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver.Symbols;

const
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  /// <summary>Höchstens so viele Stufen Vorfahren (Klassen bzw. Interfaces).</summary>
  cMaxDepth = 32;

type
  /// <summary>Methode eines Interfaces, das die Klasse erfüllt.</summary>
  TInterfaceMember = record
    Owner: TResolvedSymbol;
    Symbol: TIndexSymbol;
    /// <summary>Kommt über eine Vorfahrklasse: nur override-Methoden erfüllen es.</summary>
    Inherited_: Boolean;
    /// <summary>Name der Methode, die sie erfüllt: der eigene oder der aus einer Zuordnung.</summary>
    Implementer: string;
  end;

  /// <summary>Marken einer Datei: je Methodendeklaration die erfüllten Interface-Methoden.</summary>
  TInterfaceScan = class
  private
    FResolver: TNameResolver;
    FCurrent: TUnitIndex;
    FMembers: TList<TInterfaceMember>;
    FSeen: TDictionary<string, Boolean>;
    FMarks: TDictionary<Integer, TInterfaceMethodMark>;
    function UnitOf(const AResolved: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
    /// <summary>Die Methoden des Interfaces AIntf aus AUnit, ohne seine Vorfahren.</summary>
    procedure AddMembers(const AIntf: TResolvedSymbol; const AUnit: TUnitIndex; AInherited: Boolean;
      AResolutions: TDictionary<string, string>);
    procedure AddInterface(const AText: string; const AFromUnit: TUnitIndex; AInherited: Boolean;
      AResolutions: TDictionary<string, string>);
    procedure AddInterfacesOf(const AType: TResolvedSymbol; const AUnit: TUnitIndex; AInherited: Boolean);
    function Declarations(const AClass: TIndexSymbol): TArray<TIndexSymbol>;
    function OverloadCount(const AMember: TInterfaceMember): Integer;
    function Resolutions(const AType: TResolvedSymbol; const AUnit: TUnitIndex): TDictionary<string, string>;
    procedure Match(const AClass: TIndexSymbol; const AMember: TInterfaceMember;
      const ADeclarations: TArray<TIndexSymbol>);
    procedure AddMark(const AClass, ADeclaration: TIndexSymbol; const AMember: TInterfaceMember);
    procedure ScanClass(const AClass: TIndexSymbol);
  public
    constructor Create(AResolver: TNameResolver; const ACurrent: TUnitIndex);
    destructor Destroy; override;
    procedure Run;
    function Sorted: TArray<TInterfaceMethodMark>;
  end;

/// <summary>Typtext ohne Unit-Präfix und ohne Leerraum, groß: "System.Classes.TStrings" → "TSTRINGS".</summary>
function TypeKey(const AText: string): string;
begin
  Result := AText.Replace(' ', '');
  if Pos('<', Result) = 0 then
  begin
    Result := TResolverText.LastPart(Result);
  end;
  Result := UpperCase(Result);
end;

/// <summary>Gleiche Parameter: gleiche Zahl, gleiche Typen ohne Unit-Präfix (Typargumente eingesetzt).</summary>
function SameParams(const AMember: TInterfaceMember; const ADeclaration: TIndexSymbol): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(AMember.Symbol.ParamTypes) = Length(ADeclaration.ParamTypes);
  mIndex := 0;
  while Result and (mIndex <= High(ADeclaration.ParamTypes)) do
  begin
    Result := TypeKey(TResolverText.Substitute(AMember.Symbol.ParamTypes[mIndex], AMember.Owner.Bindings)) =
      TypeKey(ADeclaration.ParamTypes[mIndex]);
    Inc(mIndex);
  end;
end;

{ TInterfaceScan }

constructor TInterfaceScan.Create(AResolver: TNameResolver; const ACurrent: TUnitIndex);
begin
  inherited Create;
  FResolver := AResolver;
  FCurrent := ACurrent;
  FMembers := TList<TInterfaceMember>.Create;
  FSeen := TDictionary<string, Boolean>.Create;
  FMarks := TDictionary<Integer, TInterfaceMethodMark>.Create;
end;

destructor TInterfaceScan.Destroy;
begin
  FMarks.Free;
  FSeen.Free;
  FMembers.Free;
  inherited;
end;

function TInterfaceScan.UnitOf(const AResolved: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  // Die eigene Datei aus dem Editor, nicht aus dem Index.
  if SameText(AResolved.FileName, FCurrent.FileName) then
  begin
    AUnit := FCurrent;
    Exit(True);
  end;
  Result := FResolver.DeclaringUnit(AResolved, AUnit);
end;

procedure TInterfaceScan.AddMembers(const AIntf: TResolvedSymbol; const AUnit: TUnitIndex; AInherited: Boolean;
  AResolutions: TDictionary<string, string>);
var
  mSymbol: TIndexSymbol;
  mMember: TInterfaceMember;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Container, AIntf.QualifiedName) then
    begin
      mMember.Owner := AIntf;
      mMember.Symbol := mSymbol;
      mMember.Inherited_ := AInherited;
      if not AResolutions.TryGetValue(LowerCase(TResolverText.BareTypeName(AIntf.Name) + '.' + mSymbol.Name),
        mMember.Implementer) then
      begin
        mMember.Implementer := mSymbol.Name;
      end;
      FMembers.Add(mMember);
    end;
  end;
end;

procedure TInterfaceScan.AddInterface(const AText: string; const AFromUnit: TUnitIndex; AInherited: Boolean;
  AResolutions: TDictionary<string, string>);
var
  mIntf, mParent: TResolvedSymbol;
  mUnit: TUnitIndex;
  mDepth: Integer;
begin
  if not FResolver.ResolveTypeTextFrom(AFromUnit, AText, mIntf) or
    (mIntf.SymbolKind <> TIndexSymbolKind.InterfaceType) then
  begin
    Exit;
  end;
  // Das Interface mit seinen Vorfahren, jedes nur einmal je Klasse.
  for mDepth := 0 to cMaxDepth do
  begin
    if FSeen.ContainsKey(UpperCase(mIntf.QualifiedName)) or not UnitOf(mIntf, mUnit) then
    begin
      Exit;
    end;
    FSeen.Add(UpperCase(mIntf.QualifiedName), True);
    AddMembers(mIntf, mUnit, AInherited, AResolutions);
    if not FResolver.AncestorOf(mIntf, mParent) or (mParent.SymbolKind <> TIndexSymbolKind.InterfaceType) then
    begin
      Exit;
    end;
    mIntf := mParent;
  end;
end;

procedure TInterfaceScan.AddInterfacesOf(const AType: TResolvedSymbol; const AUnit: TUnitIndex; AInherited: Boolean);
var
  mIndex: Integer;
  mResolutions: TDictionary<string, string>;
begin
  mResolutions := Resolutions(AType, AUnit);
  try
    for mIndex := 0 to High(AType.Ancestors) do
    begin
      AddInterface(AType.AncestorText(mIndex), AUnit, AInherited, mResolutions);
    end;
  finally
    mResolutions.Free;
  end;
end;

function TInterfaceScan.Declarations(const AClass: TIndexSymbol): TArray<TIndexSymbol>;
var
  mSymbol: TIndexSymbol;
begin
  // Nur die Deklarationen im Typ, nicht die Rümpfe im implementation-Teil.
  Result := nil;
  for mSymbol in FCurrent.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Container, AClass.QualifiedName) and
      (mSymbol.SelectionRange.StartPos.Line >= AClass.Range.StartPos.Line) and
      (mSymbol.SelectionRange.StartPos.Line <= AClass.Range.EndPos.Line) then
    begin
      Result := Result + [mSymbol];
    end;
  end;
end;

function TInterfaceScan.OverloadCount(const AMember: TInterfaceMember): Integer;
var
  mOther: TInterfaceMember;
begin
  // Methoden desselben Interfaces mit demselben Namen.
  Result := 0;
  for mOther in FMembers do
  begin
    if SameText(mOther.Owner.QualifiedName, AMember.Owner.QualifiedName) and
      SameText(mOther.Symbol.Name, AMember.Symbol.Name) then
    begin
      Inc(Result);
    end;
  end;
end;

function TInterfaceScan.Resolutions(const AType: TResolvedSymbol;
  const AUnit: TUnitIndex): TDictionary<string, string>;
var
  mSymbol: TIndexSymbol;
  mText, mKey: string;
  mEqual, mDot: Integer;
begin
  // "IKunde.Speichern=Sichern" → ikunde.speichern = Sichern (ohne Unit-Präfix vor dem Interface).
  Result := TDictionary<string, string>.Create;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind <> TIndexSymbolKind.ClassType) or not SameText(mSymbol.QualifiedName, AType.QualifiedName) then
    begin
      Continue;
    end;
    for mText in mSymbol.Resolutions do
    begin
      mEqual := Pos('=', mText);
      mKey := Trim(Copy(mText, 1, mEqual - 1));
      mDot := LastDelimiter('.', mKey);
      Result.AddOrSetValue(LowerCase(TResolverText.BareTypeName(Copy(mKey, 1, mDot - 1)) +
        Copy(mKey, mDot, MaxInt)), Trim(Copy(mText, mEqual + 1, MaxInt)));
    end;
  end;
end;

procedure TInterfaceScan.AddMark(const AClass, ADeclaration: TIndexSymbol; const AMember: TInterfaceMember);
var
  mMark: TInterfaceMethodMark;
  mTarget: TInterfaceMethodTarget;
  mLine: Integer;
begin
  mLine := ADeclaration.SelectionRange.StartPos.Line;
  if not FMarks.TryGetValue(mLine, mMark) then
  begin
    mMark := Default(TInterfaceMethodMark);
    mMark.Line := mLine;
    mMark.Name := AClass.Name + '.' + ADeclaration.Name;
  end;
  mTarget.Name := TResolverText.BareTypeName(AMember.Owner.Name) + '.' + AMember.Symbol.Name;
  mTarget.UnitName := AMember.Owner.UnitName;
  mTarget.FileName := AMember.Owner.FileName;
  mTarget.Range := AMember.Symbol.SelectionRange;
  mMark.Targets := mMark.Targets + [mTarget];
  FMarks.AddOrSetValue(mLine, mMark);
end;

procedure TInterfaceScan.Match(const AClass: TIndexSymbol; const AMember: TInterfaceMember;
  const ADeclarations: TArray<TIndexSymbol>);
var
  mDeclaration, mOnly: TIndexSymbol;
  mCount: Integer;
begin
  mCount := 0;
  for mDeclaration in ADeclarations do
  begin
    if not SameText(mDeclaration.Name, AMember.Implementer) or
      (AMember.Inherited_ and not mDeclaration.HasDirective('override')) then
    begin
      Continue;
    end;
    if SameParams(AMember, mDeclaration) then
    begin
      AddMark(AClass, mDeclaration, AMember);
      Exit;
    end;
    mOnly := mDeclaration;
    Inc(mCount);
  end;
  // Abweichende Typtexte (Aliase): bei genau einer Methode des Namens auf beiden Seiten nach dem Namen.
  if mCount <> 1 then
  begin
    Exit;
  end;
  if OverloadCount(AMember) = 1 then
  begin
    AddMark(AClass, mOnly, AMember);
  end;
end;

procedure TInterfaceScan.ScanClass(const AClass: TIndexSymbol);
var
  mOwn, mCurrent, mAncestor: TResolvedSymbol;
  mUnit: TUnitIndex;
  mDepth: Integer;
  mDeclarations: TArray<TIndexSymbol>;
  mMember: TInterfaceMember;
begin
  mDeclarations := Declarations(AClass);
  if mDeclarations = nil then
  begin
    Exit;
  end;
  FMembers.Clear;
  FSeen.Clear;
  mOwn := TResolvedSymbol.FromIndex(FCurrent, AClass);
  AddInterfacesOf(mOwn, FCurrent, False);
  // Interfaces der Vorfahrklassen: erfüllt nur, wer die Methode überschreibt.
  mCurrent := mOwn;
  for mDepth := 0 to cMaxDepth do
  begin
    if not FResolver.AncestorOf(mCurrent, mAncestor) or (mAncestor.SymbolKind <> TIndexSymbolKind.ClassType) or
      not UnitOf(mAncestor, mUnit) then
    begin
      Break;
    end;
    AddInterfacesOf(mAncestor, mUnit, True);
    mCurrent := mAncestor;
  end;
  for mMember in FMembers.ToArray do
  begin
    Match(AClass, mMember, mDeclarations);
  end;
end;

procedure TInterfaceScan.Run;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FCurrent.Symbols do
  begin
    if mSymbol.Kind = TIndexSymbolKind.ClassType then
    begin
      ScanClass(mSymbol);
    end;
  end;
end;

function TInterfaceScan.Sorted: TArray<TInterfaceMethodMark>;
var
  mSorted: TList<TInterfaceMethodMark>;
begin
  mSorted := TList<TInterfaceMethodMark>.Create(TComparer<TInterfaceMethodMark>.Construct(
    function(const ALeft, ARight: TInterfaceMethodMark): Integer
    begin
      Result := ALeft.Line - ARight.Line;
    end));
  try
    mSorted.AddRange(FMarks.Values);
    mSorted.Sort;
    Result := mSorted.ToArray;
  finally
    mSorted.Free;
  end;
end;

{ TLspInterfaceMethods }

class function TLspInterfaceMethods.Marks(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TArray<TInterfaceMethodMark>;
var
  mScan: TInterfaceScan;
begin
  Result := nil;
  if ATree = nil then
  begin
    Exit;
  end;
  mScan := TInterfaceScan.Create(AResolver, TIndexExtractor.Extract(ATree, AFileName));
  try
    mScan.Run;
    Result := mScan.Sorted;
  finally
    mScan.Free;
  end;
end;

class function TLspInterfaceMethods.Json(const AMarks: TArray<TInterfaceMethodMark>): TJSONObject;
var
  mMethods, mTargets: TJSONArray;
  mItem, mTargetItem: TJSONObject;
  mMark: TInterfaceMethodMark;
  mTarget: TInterfaceMethodTarget;
begin
  Result := TJSONObject.Create;
  mMethods := TJSONArray.Create;
  Result.AddPair('methods', mMethods);
  for mMark in AMarks do
  begin
    mItem := TJSONObject.Create;
    mMethods.AddElement(mItem);
    mItem.AddPair('line', TJSONNumber.Create(mMark.Line));
    mItem.AddPair('name', mMark.Name);
    mTargets := TJSONArray.Create;
    mItem.AddPair('interfaces', mTargets);
    for mTarget in mMark.Targets do
    begin
      mTargetItem := TJSONObject.Create;
      mTargets.AddElement(mTargetItem);
      mTargetItem.AddPair('name', mTarget.Name);
      mTargetItem.AddPair('unit', mTarget.UnitName);
      mTargetItem.AddPair('uri', TDocumentUris.FromPath(mTarget.FileName));
      mTargetItem.AddPair('line', TJSONNumber.Create(mTarget.Range.StartPos.Line));
      mTargetItem.AddPair('character', TJSONNumber.Create(mTarget.Range.StartPos.Character));
    end;
  end;
end;

class function TLspInterfaceMethods.Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
begin
  if (AArguments = nil) or (AArguments.Count < 1) or not (AArguments.Items[0] is TJSONString) then
  begin
    Exit(Json(nil));
  end;
  mUri := AArguments.Items[0].Value;
  if not AStore.TryGet(mUri, mDocument) then
  begin
    Exit(Json(nil));
  end;
  mShared := TSyntaxTreeCache.Get(mDocument);
  mResolver := TNameResolver.Create(AIndex, AEnsureUnit);
  try
    mResolver.Namespaces := ANamespaces;
    Result := Json(Marks(mResolver, mShared.Tree, TDocumentUris.ToPath(mUri)));
  finally
    mResolver.Free;
  end;
end;

end.
