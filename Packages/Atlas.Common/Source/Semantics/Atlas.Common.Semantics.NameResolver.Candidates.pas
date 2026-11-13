unit Atlas.Common.Semantics.NameResolver.Candidates;

// Kandidaten der Namensauflösung für die Vervollständigung: alle Namen, die an einer Stelle sichtbar sind, vom
// innersten Gültigkeitsbereich nach außen (with, lokal, Parameter, Self, eigene Unit, uses, System), dazu die
// Mitglieder hinter einem Punkt und die Methoden für inherited. Gleichnamige weiter außen verdeckt der nähere
// Eintrag; er nennt sie aber (#488). Auf Wunsch merkt MemberCandidates die Mitglieder, die nur wegen ihrer
// Sichtbarkeit fehlen (#2108).

interface

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.NameResolver.Expressions,
  Atlas.Common.Semantics.NameResolver.Chains;

type
  /// <summary>Gültigkeitsbereich, aus dem gerade gesammelt wird (für Warnungen zu verdeckenden with-Mitgliedern).
  /// </summary>
  TCandidateStage = (Other, Local, OwnClass);

  /// <summary>Mitglied, das an der Stelle nur wegen seiner Sichtbarkeit fehlt (#2108).</summary>
  THiddenMember = record
    Symbol: TResolvedSymbol;
    /// <summary>Die deklarierende Unit gehört nicht zum Projekt (RTL, VCL, Drittanbieter).</summary>
    External: Boolean;
  end;

  /// <summary>Gesammelte Kandidaten: je Name ein Eintrag, Überladungen und verdeckte Namen daran vermerkt.</summary>
  TResolverCandidateList = class
  private
    FList: TList<TResolvedSymbol>;
    FSeen: TDictionary<string, Boolean>;
    FOwnedSeen: TDictionary<string, Boolean>;
    FStage: TCandidateStage;
    FHidden: TList<THiddenMember>;
    // Namen, die nur MarkSeen vermerkt hat (unsichtbare Deklaration, kein Eintrag).
    FMarked: TDictionary<string, Boolean>;
    function IndexOfName(const AName: string): Integer;
    procedure Merge(AIndex: Integer; const ASymbol: TResolvedSymbol);
  public
    /// <summary>Liste mit eigener Menge gesehener Namen.</summary>
    constructor Create; overload;
    /// <summary>Liste, die gesehene Namen in ASeen vermerkt (geteilt über mehrere Sammlungen).</summary>
    constructor Create(ASeen: TDictionary<string, Boolean>); overload;
    destructor Destroy; override;
    /// <summary>Nimmt ASymbol auf; ist der Name schon da, als Überladung oder verdeckte Deklaration.</summary>
    procedure Add(const ASymbol: TResolvedSymbol);
    /// <summary>Hängt ASymbol ohne Vergleich an und vermerkt den Namen.</summary>
    procedure Append(const ASymbol: TResolvedSymbol);
    /// <summary>Vermerkt AName als gesehen, ohne Eintrag (unsichtbare Deklaration).</summary>
    procedure MarkSeen(const AName: string);
    /// <summary>Wie Add für eine Deklaration im Typ: Hat MarkSeen den Namen nur wegen einer unsichtbaren
    /// Deklaration vermerkt (andere Überladung, verdecktes Mitglied eines Nachfahren), kommt die sichtbare doch
    /// in die Liste. Rümpfe gehen weiter über Add und bleiben verborgen.</summary>
    procedure AddDeclared(const ASymbol: TResolvedSymbol);
    function IsSeen(const AName: string): Boolean;
    /// <summary>Ist der letzte Eintrag das eingebaute AName, steigt seine Höchstzahl an Argumenten auf AMaxArgs.
    /// </summary>
    procedure WidenLast(const AName: string; AMaxArgs: Integer);
    function ToArray: TArray<TResolvedSymbol>;
    /// <summary>Ab jetzt auch nicht sichtbare Mitglieder über AddHidden merken.</summary>
    procedure KeepHidden;
    function KeepsHidden: Boolean;
    procedure AddHidden(const AMember: THiddenMember);
    /// <summary>Gemerkte nicht sichtbare Mitglieder, je Name einmal, ohne Namen, die sichtbar in der Liste stehen
    /// (sichtbare Überladung oder Vorfahr).</summary>
    function HiddenToArray: TArray<THiddenMember>;
    property Stage: TCandidateStage read FStage write FStage;
  end;

  TResolverCandidates = class
  private
    FParts: TResolverParts;
    FExpressions: TResolverExpressions;
    FChains: TResolverChains;
    FNameFilter: TCandidateNameFilter;
    // Zwischen OwnScopeCandidates und UsedScopeCandidates: gesehene Namen und die Stelle des ersten Teils.
    FScopeSeen: TDictionary<string, Boolean>;
    FScopeUnit: TUnitIndex;
    FScopeInImplementation: Boolean;
    FScopeOpen: Boolean;
    FKeepHidden: Boolean;
    FHidden: TArray<THiddenMember>;
    function NameWanted(const AName: string): Boolean;
    procedure NoteHidden(const AUnit: TUnitIndex; APosition, ADepth: Integer; AList: TResolverCandidateList);
    procedure CollectNames(ANode: TSyntaxNode; AKind: TIndexSymbolKind; AIsParameter: Boolean;
      AList: TResolverCandidateList);
    procedure CollectHelperLevel(const AHelper: TResolvedSymbol; ADepth: Integer; AList: TResolverCandidateList);
    procedure CollectHelperMembers(const AType: TResolvedSymbol; ADepth: Integer; AList: TResolverCandidateList);
    procedure CollectOwnMembers(const AType: TResolvedSymbol; const AUnit: TUnitIndex; ADepth: Integer;
      ALocalChain: Boolean; AList: TResolverCandidateList);
    procedure CollectMembers(const AType: TResolvedSymbol; AList: TResolverCandidateList);
    procedure CollectUnit(const AUnit: TUnitIndex; AOnlyInterface: Boolean; AList: TResolverCandidateList);
    procedure CollectUsedUnits(AList: TResolverCandidateList);
    procedure CollectDeclarations(ANode: TSyntaxNode; AList: TResolverCandidateList);
    procedure CollectInlineVars(ANode: TSyntaxNode; AList: TResolverCandidateList);
    procedure CollectWithMembers(AList: TResolverCandidateList);
    procedure CollectRoutineScope(ARoutine: TSyntaxNode; AList: TResolverCandidateList);
    procedure CollectSelf(AList: TResolverCandidateList);
    procedure CollectIntrinsics(AList: TResolverCandidateList);
  public
    constructor Create(const AParts: TResolverParts; AExpressions: TResolverExpressions; AChains: TResolverChains);
    destructor Destroy; override;
    /// <summary>OwnScopeCandidates und UsedScopeCandidates zusammen.</summary>
    function ScopeCandidates(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer): TArray<TResolvedSymbol>;
    /// <summary>Namen aus with, Routinen, eigener Klasse und eigener Unit an AOffset; öffnet den zweiten Teil.
    /// </summary>
    function OwnScopeCandidates(ATree: TSyntaxTree; const AFileName: string;
      AOffset: Integer): TArray<TResolvedSymbol>;
    /// <summary>Deklarationen aus den Units in uses, die NameFilter durchlässt; verdeckte erscheinen nicht.
    /// </summary>
    function UsedScopeCandidates: TArray<TResolvedSymbol>; overload;
    /// <summary>Wie oben; AWithIntrinsics: zuletzt die Bezeichner von System ohne Quelltext (#880).</summary>
    function UsedScopeCandidates(AWithIntrinsics: Boolean): TArray<TResolvedSymbol>; overload;
    /// <summary>Deklarationen aus den Units in uses, auch die von OwnScopeCandidates verdeckten.</summary>
    function UsedScopeShadows: TArray<TResolvedSymbol>;
    /// <summary>Mitglieder hinter der Kette ANames (Unit oder Typ).</summary>
    function MemberCandidates(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer): TArray<TResolvedSymbol>;
    /// <summary>Typ der Kette ANames und seine Vorfahren, nächster zuerst.</summary>
    function ReceiverTypes(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer): TArray<TResolvedSymbol>;
    /// <summary>Methoden des Vorfahren der Methodenklasse an AOffset, für inherited.</summary>
    function InheritedCandidates(ATree: TSyntaxTree; const AFileName: string;
      AOffset: Integer): TArray<TResolvedSymbol>;
    /// <summary>Überladungen der lokalen Routine ASymbol in ihrer umgebenden Routine (#881).</summary>
    function LocalOverloads(const ASymbol: TResolvedSymbol): TArray<TResolvedSymbol>;
    property NameFilter: TCandidateNameFilter read FNameFilter write FNameFilter;
    /// <summary>MemberCandidates merkt auch die Mitglieder, die nur wegen der Sichtbarkeit fehlen und NameFilter
    /// durchlässt (#2108); sie stehen danach in Hidden.</summary>
    property KeepHidden: Boolean read FKeepHidden write FKeepHidden;
    /// <summary>Die nicht sichtbaren Mitglieder des letzten MemberCandidates mit KeepHidden; sonst leer.</summary>
    property Hidden: TArray<THiddenMember> read FHidden;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Semantics.SystemIntrinsics;

/// <summary>Bezeichner von System ohne Quelltext als Kandidat (#880); Überladungen erscheinen einmal.</summary>
function IntrinsicSymbol(const AIntrinsic: TSystemIntrinsic): TResolvedSymbol;
begin
  Result := TResolvedSymbol.Empty;
  Result.Kind := TResolvedKind.Symbol;
  Result.Name := AIntrinsic.Name;
  Result.UnitName := 'System';
  Result.SymbolKind := AIntrinsic.Kind;
  Result.MinArgs := AIntrinsic.MinArgs;
  Result.MaxArgs := AIntrinsic.MaxArgs;
  Result.InInterface := True;
  Result.Builtin := True;
end;

/// <summary>ASymbol gehört zur selben Überladungsgruppe wie AExisting: gleiche Klasse und Datei, gleicher Abschnitt
/// (Rümpfe in implementation zählen nicht), eine Routine.</summary>
function SameOverloadGroup(const AExisting, ASymbol: TResolvedSymbol): Boolean;
begin
  Result := SameText(AExisting.Container, ASymbol.Container) and SameText(AExisting.FileName, ASymbol.FileName) and
    (AExisting.SymbolKind in cRoutineKinds) and (AExisting.InInterface = ASymbol.InInterface);
end;

/// <summary>Warnung, wenn ein with-Mitglied ASymbol aus dem Gültigkeitsbereich AStage verdeckt (#481); '' sonst.
/// </summary>
function WithShadowText(AStage: TCandidateStage; const ASymbol: TResolvedSymbol): string;
begin
  case AStage of
    TCandidateStage.Local:
      Result := ASymbol.ShadowText;
    TCandidateStage.OwnClass:
      Result := 'Self.' + ASymbol.Name;
  else
    Result := '';
  end;
end;

/// <summary>Hängt AText an AList, wenn es dort noch nicht steht.</summary>
procedure AddText(var AList: TArray<string>; const AText: string);
begin
  if (AText <> '') and not MatchText(AText, AList) then
  begin
    AList := AList + [AText];
  end;
end;

{ TResolverCandidateList }

constructor TResolverCandidateList.Create;
begin
  FOwnedSeen := TDictionary<string, Boolean>.Create;
  Create(FOwnedSeen);
end;

constructor TResolverCandidateList.Create(ASeen: TDictionary<string, Boolean>);
begin
  inherited Create;
  FList := TList<TResolvedSymbol>.Create;
  FMarked := TDictionary<string, Boolean>.Create;
  FSeen := ASeen;
end;

destructor TResolverCandidateList.Destroy;
begin
  FHidden.Free;
  FMarked.Free;
  FList.Free;
  FOwnedSeen.Free;
  inherited;
end;

function TResolverCandidateList.IndexOfName(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := FList.Count - 1 downto 0 do
  begin
    if SameText(FList[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TResolverCandidateList.Merge(AIndex: Integer; const ASymbol: TResolvedSymbol);
var
  mExisting: TResolvedSymbol;
  mParams: string;
begin
  mExisting := FList[AIndex];
  // Andere Parametertypen als jede bisherige Variante: eine Überladung (Rümpfe überladener Methoden wiederholen
  // sie).
  mParams := string.Join(';', ASymbol.ParamTypes);
  if SameOverloadGroup(mExisting, ASymbol) and not MatchText(mParams, mExisting.VariantParams) then
  begin
    mExisting.Overloads := mExisting.Overloads + [ASymbol.SelectionRange];
    mExisting.VariantParams := mExisting.VariantParams + [mParams];
  end
  else if mExisting.IsOtherDeclaration(ASymbol) then
  begin
    // Verdeckt (#488): Das Detailpanel nennt die Deklaration weiter außen.
    AddText(mExisting.Hides, ASymbol.ShadowText);
    // with-Mitglied über einem lokalen Namen oder einem Mitglied von Self (#481): Warnung in der Liste.
    if mExisting.WithOrigin <> '' then
    begin
      AddText(mExisting.WithShadows, WithShadowText(FStage, ASymbol));
    end;
  end
  else
  begin
    Exit;
  end;
  FList[AIndex] := mExisting;
end;

procedure TResolverCandidateList.Add(const ASymbol: TResolvedSymbol);
var
  mKey: string;
  mIndex: Integer;
begin
  // Der nächste Gültigkeitsbereich verdeckt gleichnamige weiter außen; Überladungen erscheinen einmal,
  // ihre Positionen merkt sich der erste Eintrag (#425).
  mKey := UpperCase(ASymbol.Name);
  if mKey = '' then
  begin
    Exit;
  end;
  if not FSeen.ContainsKey(mKey) then
  begin
    FSeen.Add(mKey, True);
    FList.Add(ASymbol);
    Exit;
  end;
  mIndex := IndexOfName(ASymbol.Name);
  if mIndex >= 0 then
  begin
    Merge(mIndex, ASymbol);
  end;
end;

procedure TResolverCandidateList.Append(const ASymbol: TResolvedSymbol);
begin
  FSeen.Add(UpperCase(ASymbol.Name), True);
  FList.Add(ASymbol);
end;

procedure TResolverCandidateList.MarkSeen(const AName: string);
begin
  if IndexOfName(AName) < 0 then
  begin
    FMarked.AddOrSetValue(UpperCase(AName), True);
  end;
  FSeen.AddOrSetValue(UpperCase(AName), True);
end;

procedure TResolverCandidateList.AddDeclared(const ASymbol: TResolvedSymbol);
begin
  if FMarked.ContainsKey(UpperCase(ASymbol.Name)) and (IndexOfName(ASymbol.Name) < 0) then
  begin
    FMarked.Remove(UpperCase(ASymbol.Name));
    FList.Add(ASymbol);
    Exit;
  end;
  Add(ASymbol);
end;

function TResolverCandidateList.IsSeen(const AName: string): Boolean;
begin
  Result := FSeen.ContainsKey(UpperCase(AName));
end;

procedure TResolverCandidateList.KeepHidden;
begin
  if FHidden = nil then
  begin
    FHidden := TList<THiddenMember>.Create;
  end;
end;

function TResolverCandidateList.KeepsHidden: Boolean;
begin
  Result := FHidden <> nil;
end;

procedure TResolverCandidateList.AddHidden(const AMember: THiddenMember);
begin
  if FHidden <> nil then
  begin
    FHidden.Add(AMember);
  end;
end;

function TResolverCandidateList.HiddenToArray: TArray<THiddenMember>;
var
  mNames: TDictionary<string, Boolean>;
  mMember: THiddenMember;
begin
  Result := nil;
  if FHidden = nil then
  begin
    Exit;
  end;
  mNames := TDictionary<string, Boolean>.Create;
  try
    for mMember in FHidden do
    begin
      if not mNames.ContainsKey(UpperCase(mMember.Symbol.Name)) and (IndexOfName(mMember.Symbol.Name) < 0) then
      begin
        mNames.Add(UpperCase(mMember.Symbol.Name), True);
        Result := Result + [mMember];
      end;
    end;
  finally
    mNames.Free;
  end;
end;

procedure TResolverCandidateList.WidenLast(const AName: string; AMaxArgs: Integer);
var
  mLast: TResolvedSymbol;
begin
  if FList.Count = 0 then
  begin
    Exit;
  end;
  mLast := FList[FList.Count - 1];
  if SameText(mLast.Name, AName) and mLast.Builtin and (AMaxArgs > mLast.MaxArgs) then
  begin
    mLast.MaxArgs := AMaxArgs;
    FList[FList.Count - 1] := mLast;
  end;
end;

function TResolverCandidateList.ToArray: TArray<TResolvedSymbol>;
begin
  Result := FList.ToArray;
end;

{ TResolverCandidates }

constructor TResolverCandidates.Create(const AParts: TResolverParts; AExpressions: TResolverExpressions;
  AChains: TResolverChains);
begin
  inherited Create;
  FParts := AParts;
  FExpressions := AExpressions;
  FChains := AChains;
  FScopeSeen := TDictionary<string, Boolean>.Create;
end;

destructor TResolverCandidates.Destroy;
begin
  FScopeSeen.Free;
  inherited;
end;

function TResolverCandidates.NameWanted(const AName: string): Boolean;
begin
  // Vor FromIndex prüfen: Das Aufbauen der Records kostet bei großen Units die meiste Zeit (#616).
  Result := not Assigned(FNameFilter) or FNameFilter(AName);
end;

procedure TResolverCandidates.CollectNames(ANode: TSyntaxNode; AKind: TIndexSymbolKind; AIsParameter: Boolean;
  AList: TResolverCandidateList);
var
  mName: string;
begin
  for mName in ANode.Name.Split([',']) do
  begin
    AList.Add(FParts.Locals.FromNode(ANode, mName.Trim, AKind, AIsParameter));
  end;
end;

procedure TResolverCandidates.CollectHelperLevel(const AHelper: TResolvedSymbol; ADepth: Integer;
  AList: TResolverCandidateList);
var
  mUnit: TUnitIndex;
  mPosition: Integer;
begin
  if not FParts.Units.UnitOf(AHelper, mUnit) then
  begin
    Exit;
  end;
  // Über den Index statt for-in: keine Kopie des Symbol-Records je geprüftem Symbol.
  for mPosition := 0 to High(mUnit.Symbols) do
  begin
    if SameText(mUnit.Symbols[mPosition].Container, AHelper.QualifiedName) and
      FParts.Typing.IsVisible(mUnit.Symbols[mPosition], mUnit, AHelper, False) and
      NameWanted(mUnit.Symbols[mPosition].Name) then
    begin
      AList.Add(TResolvedSymbol.FromIndex(mUnit, mUnit.Symbols[mPosition]).AsMember(ADepth, True));
    end;
  end;
end;

procedure TResolverCandidates.CollectHelperMembers(const AType: TResolvedSymbol; ADepth: Integer;
  AList: TResolverCandidateList);
var
  mHelper, mParent: TResolvedSymbol;
  mHelperDepth: Integer;
begin
  // Mitglieder des Helfers zuerst (#263), auch für eingebaute Typen. Vorfahr-Helfer danach (#848); gleichnamige
  // verdeckt der abgeleitete.
  if not FParts.Typing.HelperFor(AType, mHelper) then
  begin
    Exit;
  end;
  for mHelperDepth := 0 to cMaxDepth do
  begin
    CollectHelperLevel(mHelper, ADepth, AList);
    if not FParts.Typing.HelperParent(mHelper, mParent) then
    begin
      Break;
    end;
    mHelper := mParent;
  end;
end;

/// <summary>Liegt A vor B oder an derselben Stelle?</summary>
function NotAfter(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character <= B.Character));
end;

/// <summary>Steht ASymbol in der Deklaration des Typs AType (kein Rumpf aus implementation)?</summary>
function DeclaredIn(const AType: TResolvedSymbol; const ASymbol: TIndexSymbol): Boolean;
begin
  Result := not NotAfter(AType.Range.EndPos, AType.Range.StartPos) and NotAfter(AType.Range.StartPos,
    ASymbol.Range.StartPos) and NotAfter(ASymbol.Range.EndPos, AType.Range.EndPos);
end;

procedure TResolverCandidates.CollectOwnMembers(const AType: TResolvedSymbol; const AUnit: TUnitIndex;
  ADepth: Integer; ALocalChain: Boolean; AList: TResolverCandidateList);
var
  mTypeName: string;
  mPosition: Integer;
  mMember: TResolvedSymbol;
begin
  mTypeName := AType.QualifiedName;
  for mPosition := 0 to High(AUnit.Symbols) do
  begin
    if not SameText(AUnit.Symbols[mPosition].Container, mTypeName) then
    begin
      Continue;
    end;
    if not FParts.Typing.IsVisible(AUnit.Symbols[mPosition], AUnit, AType, ALocalChain) then
    begin
      // Unsichtbare Deklaration: auch ihren Rumpf aus implementation nicht anbieten.
      AList.MarkSeen(AUnit.Symbols[mPosition].Name);
      NoteHidden(AUnit, mPosition, ADepth, AList);
    end
    else if NameWanted(AUnit.Symbols[mPosition].Name) then
    begin
      // Gebundene Typparameter des Typs (#450): Mitglieder von TObjectList<TKunde> kennen T=TKunde.
      mMember := TResolvedSymbol.FromIndex(AUnit, AUnit.Symbols[mPosition]).AsMember(ADepth, False);
      mMember.Bindings := AType.Bindings;
      if DeclaredIn(AType, AUnit.Symbols[mPosition]) then
      begin
        AList.AddDeclared(mMember);
      end
      else
      begin
        AList.Add(mMember);
      end;
    end;
  end;
end;

procedure TResolverCandidates.NoteHidden(const AUnit: TUnitIndex; APosition, ADepth: Integer;
  AList: TResolverCandidateList);
var
  mMember: THiddenMember;
begin
  // Rümpfe aus dem implementation-Teil fremder Units sind keine verdeckten Mitglieder (#2108).
  if not AList.KeepsHidden or not (AUnit.Symbols[APosition].InInterface or
    FParts.Place.IsCurrentFile(AUnit.FileName)) or not NameWanted(AUnit.Symbols[APosition].Name) then
  begin
    Exit;
  end;
  mMember.Symbol := TResolvedSymbol.FromIndex(AUnit, AUnit.Symbols[APosition]).AsMember(ADepth, False);
  mMember.External := AUnit.Library_;
  AList.AddHidden(mMember);
end;

procedure TResolverCandidates.CollectMembers(const AType: TResolvedSymbol; AList: TResolverCandidateList);
var
  mCurrent, mAncestor: TResolvedSymbol;
  mOwnerUnit: TUnitIndex;
  mDepth: Integer;
  mLocalChain: Boolean;
begin
  mCurrent := AType;
  mLocalChain := False;
  for mDepth := 0 to cMaxDepth do
  begin
    CollectHelperMembers(mCurrent, mDepth, AList);
    if mCurrent.Builtin or not FParts.Units.UnitOf(mCurrent, mOwnerUnit) then
    begin
      Exit;
    end;
    mLocalChain := mLocalChain or FParts.Place.IsCurrentFile(mOwnerUnit.FileName);
    CollectOwnMembers(mCurrent, mOwnerUnit, mDepth, mLocalChain, AList);
    if not FParts.Typing.AncestorOf(mCurrent, mAncestor) then
    begin
      Exit;
    end;
    mCurrent := mAncestor;
  end;
end;

procedure TResolverCandidates.CollectUnit(const AUnit: TUnitIndex; AOnlyInterface: Boolean;
  AList: TResolverCandidateList);
var
  mPosition: Integer;
begin
  // Über den Index statt for-in: keine Kopie des Symbol-Records je übersprungenem Symbol.
  for mPosition := 0 to High(AUnit.Symbols) do
  begin
    if AOnlyInterface and not AUnit.Symbols[mPosition].InInterface then
    begin
      Continue;
    end;
    if (AUnit.Symbols[mPosition].Container <> '') and
      ((AUnit.Symbols[mPosition].Kind <> TIndexSymbolKind.EnumMember) or AUnit.Symbols[mPosition].ScopedEnum) then
    begin
      Continue;
    end;
    if NameWanted(AUnit.Symbols[mPosition].Name) then
    begin
      AList.Add(TResolvedSymbol.FromIndex(AUnit, AUnit.Symbols[mPosition]));
    end;
  end;
end;

procedure TResolverCandidates.CollectUsedUnits(AList: TResolverCandidateList);
var
  mUnitName: string;
  mUsed: PUnitIndex;
begin
  for mUnitName in FParts.Units.ScopeUnits(FScopeUnit, FScopeInImplementation) do
  begin
    if FParts.Units.FindUnitRef(mUnitName, mUsed) then
    begin
      CollectUnit(mUsed^, True, AList);
    end;
  end;
end;

procedure TResolverCandidates.CollectDeclarations(ANode: TSyntaxNode; AList: TResolverCandidateList);
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mChild := ANode[mIndex];
    case mChild.Kind of
      TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
        CollectDeclarations(mChild, AList);
      TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl:
        CollectNames(mChild, TResolverNodes.DeclarationKind(mChild), False, AList);
      TSyntaxKind.TypeDecl:
        AList.Add(FParts.Locals.FromNode(mChild, mChild.Name, TIndexSymbolKind.TypeAlias, False));
      TSyntaxKind.RoutineDecl:
        AList.Add(FParts.Locals.FromNode(mChild, mChild.Name, TIndexSymbolKind.Routine, False));
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

procedure TResolverCandidates.CollectInlineVars(ANode: TSyntaxNode; AList: TResolverCandidateList);
var
  mPending: TStack<TSyntaxNode>;
  mChild: TSyntaxNode;
  mOffset: Integer;
begin
  // Wie LookupInlineVars: nur bis zum Cursor, nicht in verschachtelte Routinen; iterativ.
  mOffset := FParts.Place.Offset;
  mPending := TStack<TSyntaxNode>.Create;
  try
    TResolverNodes.PushChildrenBefore(mPending, ANode, mOffset);
    while mPending.Count > 0 do
    begin
      mChild := mPending.Pop;
      if mChild.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
      begin
        if mChild.EndOffset <= mOffset then
        begin
          CollectNames(mChild, TIndexSymbolKind.Variable, False, AList);
        end;
      end
      else if (mChild.Kind <> TSyntaxKind.RoutineDecl) and TResolverNodes.Contains(mChild, mOffset) then
      begin
        TResolverNodes.PushChildrenBefore(mPending, mChild, mOffset);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TResolverCandidates.CollectWithMembers(AList: TResolverCandidateList);
var
  mWith: TSyntaxNode;
  mIndex: Integer;
  mType, mMember: TResolvedSymbol;
  mMembers: TResolverCandidateList;
  mOrigin: string;
begin
  for mWith in FParts.Place.EnclosingWiths do
  begin
    for mIndex := mWith.ChildCount - 2 downto 0 do
    begin
      // Unbekannter Typ: keine Mitglieder; Namen weiter außen bleiben dann ohne Hinweis.
      if not FExpressions.WithElementType(mWith, mIndex, mType) then
      begin
        Continue;
      end;
      // Eigene Sammlung: Unsichtbare Mitglieder des with-Typs dürfen äußere Namen nicht ausblenden.
      mMembers := TResolverCandidateList.Create;
      try
        CollectMembers(mType, mMembers);
        mOrigin := TResolverNodes.NodeSource(FParts.Place.Tree, mWith[mIndex]);
        for mMember in mMembers.ToArray do
        begin
          mType := mMember;
          mType.WithOrigin := mOrigin;
          AList.Add(mType);
        end;
      finally
        mMembers.Free;
      end;
    end;
  end;
end;

procedure TResolverCandidates.CollectRoutineScope(ARoutine: TSyntaxNode; AList: TResolverCandidateList);
var
  mHeader, mParams: TSyntaxNode;
  mIndex: Integer;
begin
  // Lokale Namen vor den Parametern (#488): Stufe 1 vor Stufe 2.
  CollectInlineVars(ARoutine, AList);
  CollectDeclarations(ARoutine, AList);
  mHeader := TResolverNodes.RoutineHeaderOf(ARoutine);
  if mHeader = nil then
  begin
    Exit;
  end;
  mParams := mHeader.FindChild(TSyntaxKind.Parameters);
  if mParams <> nil then
  begin
    for mIndex := 0 to mParams.ChildCount - 1 do
    begin
      if mParams[mIndex].Kind = TSyntaxKind.Parameter then
      begin
        CollectNames(mParams[mIndex], TIndexSymbolKind.Variable, True, AList);
      end;
    end;
  end;
  if mHeader.FindChild(TSyntaxKind.TypeReference) <> nil then
  begin
    AList.Add(FParts.Locals.FromNode(mHeader, 'Result', TIndexSymbolKind.Variable, False));
  end;
end;

procedure TResolverCandidates.CollectSelf(AList: TResolverCandidateList);
var
  mClass, mSelf: TResolvedSymbol;
begin
  if not FParts.Typing.MethodClass(mClass) then
  begin
    Exit;
  end;
  mSelf := mClass;
  mSelf.Name := 'Self';
  mSelf.Kind := TResolvedKind.Local;
  mSelf.SymbolKind := TIndexSymbolKind.Variable;
  mSelf.TypeName := mClass.QualifiedName;
  AList.Add(mSelf);
  AList.Stage := TCandidateStage.OwnClass;
  CollectMembers(mClass, AList);
end;

procedure TResolverCandidates.CollectIntrinsics(AList: TResolverCandidateList);
var
  mIntrinsic: TSystemIntrinsic;
begin
  // Zuletzt, was System ohne Quelltext mitbringt: Indexiertes und Eigenes verdeckt gleichnamige Einträge.
  for mIntrinsic in TSystemIntrinsics.All do
  begin
    if not AList.IsSeen(mIntrinsic.Name) and NameWanted(mIntrinsic.Name) then
    begin
      AList.Append(IntrinsicSymbol(mIntrinsic));
    end
    else
    begin
      // Weitere Überladung: Parameter zeigt der Eintrag schon an, wenn eine Variante welche hat.
      AList.WidenLast(mIntrinsic.Name, mIntrinsic.MaxArgs);
    end;
  end;
end;

function TResolverCandidates.ScopeCandidates(ATree: TSyntaxTree; const AFileName: string;
  AOffset: Integer): TArray<TResolvedSymbol>;
begin
  Result := OwnScopeCandidates(ATree, AFileName, AOffset);
  Result := Result + UsedScopeCandidates;
end;

function TResolverCandidates.OwnScopeCandidates(ATree: TSyntaxTree; const AFileName: string;
  AOffset: Integer): TArray<TResolvedSymbol>;
var
  mList: TResolverCandidateList;
  mRoutine: TSyntaxNode;
begin
  Result := nil;
  FScopeOpen := False;
  FScopeSeen.Clear;
  if ATree = nil then
  begin
    Exit;
  end;
  FParts.Place.MoveTo(ATree, AFileName, AOffset);
  mList := TResolverCandidateList.Create(FScopeSeen);
  try
    // with-Objekte verdecken alles weiter außen (#481); innerstes zuerst.
    mList.Stage := TCandidateStage.Other;
    CollectWithMembers(mList);
    mList.Stage := TCandidateStage.Local;
    for mRoutine in FParts.Place.EnclosingRoutines do
    begin
      CollectRoutineScope(mRoutine, mList);
    end;
    CollectSelf(mList);
    mList.Stage := TCandidateStage.Other;
    CollectUnit(FParts.Place.Current, not FParts.Place.InImplementation, mList);
    // Für den zweiten Teil merken: Andere Aufrufe dazwischen (z. B. Typprüfungen) bereiten den Zustand neu vor.
    FScopeUnit := FParts.Place.Current;
    FScopeInImplementation := FParts.Place.InImplementation;
    FScopeOpen := True;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TResolverCandidates.UsedScopeCandidates: TArray<TResolvedSymbol>;
begin
  Result := UsedScopeCandidates(False);
end;

function TResolverCandidates.UsedScopeCandidates(AWithIntrinsics: Boolean): TArray<TResolvedSymbol>;
var
  mList: TResolverCandidateList;
begin
  Result := nil;
  if not FScopeOpen then
  begin
    Exit;
  end;
  FScopeOpen := False;
  mList := TResolverCandidateList.Create(FScopeSeen);
  try
    CollectUsedUnits(mList);
    if AWithIntrinsics then
    begin
      CollectIntrinsics(mList);
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    FScopeSeen.Clear;
  end;
end;

function TResolverCandidates.UsedScopeShadows: TArray<TResolvedSymbol>;
var
  mList: TResolverCandidateList;
begin
  Result := nil;
  if not FScopeOpen then
  begin
    Exit;
  end;
  mList := TResolverCandidateList.Create;
  try
    CollectUsedUnits(mList);
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TResolverCandidates.MemberCandidates(ATree: TSyntaxTree; const AFileName: string;
  const ANames: TArray<string>; AOffset: Integer): TArray<TResolvedSymbol>;
var
  mOwner, mType: TResolvedSymbol;
  mOwnerUnit: TUnitIndex;
  mList: TResolverCandidateList;
begin
  Result := nil;
  FHidden := nil;
  // ResolveChain bereitet die Stelle (aktuelle Unit, Abschnitt) vor.
  mOwner := FChains.ResolveChain(ATree, AFileName, ANames, AOffset, False);
  if not mOwner.Found then
  begin
    Exit;
  end;
  mList := TResolverCandidateList.Create;
  try
    if mOwner.Kind <> TResolvedKind.UnitName then
    begin
      if FKeepHidden then
      begin
        mList.KeepHidden;
      end;
      if FParts.Typing.TypeOf(mOwner, mType) then
      begin
        CollectMembers(mType, mList);
      end;
    end
    else if FParts.Units.FindUnit(mOwner.UnitName, mOwnerUnit) then
    begin
      CollectUnit(mOwnerUnit, not FParts.Place.IsCurrentFile(mOwnerUnit.FileName), mList);
    end;
    Result := mList.ToArray;
    FHidden := mList.HiddenToArray;
  finally
    mList.Free;
  end;
end;

function TResolverCandidates.ReceiverTypes(ATree: TSyntaxTree; const AFileName: string;
  const ANames: TArray<string>; AOffset: Integer): TArray<TResolvedSymbol>;
var
  mChain: TResolvedChainType;
  mCurrent, mAncestor: TResolvedSymbol;
  mDepth: Integer;
begin
  Result := nil;
  if not FChains.ChainType(ATree, AFileName, ANames, AOffset, mChain) or not mChain.TypeFound then
  begin
    Exit;
  end;
  mCurrent := mChain.TypeInfo;
  for mDepth := 0 to cMaxDepth do
  begin
    Result := Result + [mCurrent];
    if mCurrent.Builtin or not FParts.Typing.AncestorOf(mCurrent, mAncestor) then
    begin
      Break;
    end;
    mCurrent := mAncestor;
  end;
end;

function TResolverCandidates.InheritedCandidates(ATree: TSyntaxTree; const AFileName: string;
  AOffset: Integer): TArray<TResolvedSymbol>;
var
  mClass, mAncestor, mCandidate: TResolvedSymbol;
  mList: TResolverCandidateList;
begin
  Result := nil;
  if ATree = nil then
  begin
    Exit;
  end;
  FParts.Place.MoveTo(ATree, AFileName, AOffset);
  if not FParts.Typing.MethodClass(mClass) or not FParts.Typing.AncestorOf(mClass, mAncestor) then
  begin
    Exit;
  end;
  mList := TResolverCandidateList.Create;
  try
    // Wie Mitglieder des Vorfahren, gesehen aus der eigenen Methode (protected sichtbar).
    CollectMembers(mAncestor, mList);
    for mCandidate in mList.ToArray do
    begin
      if mCandidate.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_] then
      begin
        Result := Result + [mCandidate.AsMember(mCandidate.Depth + 1, mCandidate.IsHelper)];
      end;
    end;
  finally
    mList.Free;
  end;
end;

function TResolverCandidates.LocalOverloads(const ASymbol: TResolvedSymbol): TArray<TResolvedSymbol>;
begin
  Result := FParts.Locals.LocalOverloads(ASymbol);
end;

end.
