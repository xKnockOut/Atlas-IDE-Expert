unit Atlas.Common.Semantics.CallOwnership;

// Was eine gerufene Routine mit einem Objekt macht, das als Argument an sie
// geht, auch über Unit-Grenzen: Die Namensauflösung findet die Routine, ihre
// Zusammenfassung je Parameter steht im Index (TIndexSymbol.ParamOwnership,
// Atlas.Common.Pascal.ParamOwnership). Reicht die Routine das Objekt nur weiter,
// folgt die Abfrage den Weitergaben bis zur Tiefe cMaxDepth; ein Kreis zählt als
// geliehen. Gemeinsam für die Leckregel local-object-not-freed und die Marke „Wer
// gibt das frei?“ (Atlas.Common.Rules.Ownership).
//
// Vorsichtig, weil „geliehen“ eine Leckmeldung auslösen kann: Unknown bei
// virtuellen Methoden (ein Nachfahr kann anders handeln), bei Überladungen mit
// verschiedenen Aussagen, ohne Zusammenfassung und wenn eine Weitergabe unklar
// ist. Routinen der RTL, die der Index nicht kennt (ohne Quelltext der RTL),
// kommen aus der kleinen Tabelle cKnownRoutines.
// Abfragen kosten nur Nachschlagen im Index; Ergebnisse je Routine und Stelle
// bleiben für die Lebensdauer des Objekts gemerkt (Hover, Prüflauf einer Datei).

interface

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ParamOwnership,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  /// <summary>Antwort für ein Argument.</summary>
  TCallEffect = record
    /// <summary>Unknown, Borrows, Frees oder Keeps.</summary>
    Effect: TParamEffect;
    /// <summary>Gerufene Routine wie im Index (TFoo.Bar bzw. Bar); '' ohne.</summary>
    Callee: string;
    /// <summary>Unit der gerufenen Routine; '' ohne.</summary>
    UnitName: string;
    /// <summary>Bei Frees und Keeps über Weitergaben: die Routine, die freigibt bzw. übernimmt; sonst ''.</summary>
    Via: string;
  end;

  TCallOwnership = class
  public const
    cMaxDepth = 4;
  private
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    FResolver: TNameResolver;
    FTree: TSyntaxTree;
    FFileName: string;
    // Eigener Resolver für die Seite der gerufenen Units: ResolveNameFrom setzt den Zustand zurück.
    FForwards: TNameResolver;
    FMemo: TDictionary<string, TCallEffect>;
    FPending: TDictionary<string, Boolean>;
    function ForwardResolver: TNameResolver;
    function SymbolEffect(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol; AArgument, ADepth: Integer):
      TCallEffect;
    function ForwardEffect(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol; const AForward: TParamForward;
      ADepth: Integer): TCallEffect;
    function RoutinesEffect(const AUnit: TUnitIndex; const ASymbols: TArray<TIndexSymbol>; AArgument,
      AArgumentCount, ADepth: Integer): TCallEffect;
  public
    /// <summary>AResolver gehört dem Aufrufer und ist auf ATree (Datei AFileName) gepinnt.</summary>
    constructor Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>);
    destructor Destroy; override;
    /// <summary>Was der Aufruf ACall (Call-Knoten) mit seinem Argument AArgument (ab 0) macht.</summary>
    function EffectOf(ACall: TSyntaxNode; AArgument: Integer): TCallEffect;
    /// <summary>Bekannte Routine der RTL (Name ohne Unit) und ihr Argument AArgument; False, wenn die Tabelle
    /// nichts sagt.</summary>
    class function KnownRoutine(const AName: string; AArgument: Integer; out AEffect: TParamEffect): Boolean;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Semantics.NameResolver.Symbols;

type
  TKnownRoutine = record
    Name: string;
    Argument: Integer;
    Effect: TParamEffect;
  end;

const
  /// <summary>Routinen der RTL, deren Rumpf der Index ohne Quelltext der RTL nicht kennt.</summary>
  cKnownRoutines: array[0..2] of TKnownRoutine = (
    (Name: 'ExtractStrings'; Argument: 3; Effect: TParamEffect.Borrows),
    (Name: 'FreeAndNil'; Argument: 0; Effect: TParamEffect.Frees),
    (Name: 'Supports'; Argument: 0; Effect: TParamEffect.Borrows));
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_];

function NewEffect(AEffect: TParamEffect): TCallEffect;
begin
  Result := Default(TCallEffect);
  Result.Effect := AEffect;
end;

/// <summary>Mehrere mögliche Ziele (Überladungen): Nur eine gemeinsame Aussage zählt, sonst Unknown.</summary>
procedure MergeAlternative(var ATotal: TCallEffect; const AEffect: TCallEffect);
begin
  if ATotal.Effect = TParamEffect.NoObject then
  begin
    ATotal := AEffect;
  end
  else if ATotal.Effect <> AEffect.Effect then
  begin
    ATotal.Effect := TParamEffect.Unknown;
  end;
end;

/// <summary>Rang einer Weitergabe: Freigabe vor Übernahme vor unklar vor geliehen. Gibt eine der Routinen frei
/// oder übernimmt, ist das Objekt sicher nicht nur geliehen.</summary>
function ForwardRank(AEffect: TParamEffect): Integer;
begin
  case AEffect of
    TParamEffect.Frees:
      Result := 3;
    TParamEffect.Keeps:
      Result := 2;
    TParamEffect.Unknown:
      Result := 1;
  else
    Result := 0;
  end;
end;

/// <summary>Deklarationen und Rümpfe der Routine AName im Typ AContainer der Unit AUnit.</summary>
function RoutinesIn(const AUnit: TUnitIndex; const AName, AContainer: string): TArray<TIndexSymbol>;
var
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Name, AName) and
      SameText(mSymbol.Container, AContainer) then
    begin
      Result := Result + [mSymbol];
    end;
  end;
end;

/// <summary>Ist eine der Deklarationen virtuell? Dann kann ein Nachfahr das Objekt anders behandeln.</summary>
function AnyVirtual(const ASymbols: TArray<TIndexSymbol>): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  Result := False;
  for mSymbol in ASymbols do
  begin
    Result := Result or mSymbol.IsVirtual;
  end;
end;

function SymbolKey(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol; AArgument: Integer): string;
begin
  Result := LowerCase(AUnit.UnitName + '|' + ASymbol.QualifiedName + '|' + ASymbol.ParamOwnership) + '|' +
    IntToStr(AArgument);
end;

{ TCallOwnership }

constructor TCallOwnership.Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>);
begin
  inherited Create;
  FResolver := AResolver;
  FTree := ATree;
  FFileName := AFileName;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
  FNamespaces := ANamespaces;
  FMemo := TDictionary<string, TCallEffect>.Create;
  FPending := TDictionary<string, Boolean>.Create;
end;

destructor TCallOwnership.Destroy;
begin
  FForwards.Free;
  FPending.Free;
  FMemo.Free;
  inherited Destroy;
end;

class function TCallOwnership.KnownRoutine(const AName: string; AArgument: Integer;
  out AEffect: TParamEffect): Boolean;
var
  mKnown: TKnownRoutine;
begin
  for mKnown in cKnownRoutines do
  begin
    if SameText(mKnown.Name, AName) and (mKnown.Argument = AArgument) then
    begin
      AEffect := mKnown.Effect;
      Exit(True);
    end;
  end;
  AEffect := TParamEffect.Unknown;
  Result := False;
end;

function TCallOwnership.ForwardResolver: TNameResolver;
begin
  if FForwards = nil then
  begin
    FForwards := TNameResolver.Create(FIndex, FEnsureUnit);
    FForwards.Namespaces := FNamespaces;
  end;
  Result := FForwards;
end;

function TCallOwnership.ForwardEffect(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol;
  const AForward: TParamForward; ADepth: Integer): TCallEffect;
var
  mTargets: TArray<TIndexSymbol>;
  mResolved: TResolvedSymbol;
  mUnit: TUnitIndex;
begin
  mUnit := AUnit;
  // Methoden der eigenen Klasse zuerst (Foo bzw. Self.Foo im Rumpf einer Methode), dann von der Unit aus.
  mTargets := nil;
  if ASymbol.Container <> '' then
  begin
    mTargets := RoutinesIn(AUnit, AForward.Callee, ASymbol.Container);
  end;
  if mTargets = nil then
  begin
    if (FIndex = nil) or not ForwardResolver.ResolveNameFrom(AUnit, AForward.Callee, mResolved) or
      not (mResolved.SymbolKind in cRoutineKinds) or not ForwardResolver.DeclaringUnit(mResolved, mUnit) then
    begin
      Exit(NewEffect(TParamEffect.Unknown));
    end;
    mTargets := RoutinesIn(mUnit, mResolved.Name, mResolved.Container);
  end;
  Result := RoutinesEffect(mUnit, mTargets, AForward.Argument, -1, ADepth + 1);
end;

function TCallOwnership.SymbolEffect(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol; AArgument,
  ADepth: Integer): TCallEffect;
var
  mSummary: TParamSummary;
  mForward: TParamForward;
  mOther: TCallEffect;
  mKey: string;
begin
  Result := NewEffect(TParamEffect.Unknown);
  Result.Callee := ASymbol.QualifiedName;
  Result.UnitName := AUnit.UnitName;
  if not TParamOwnership.Decode(ASymbol.ParamOwnership, AArgument, mSummary) or
    (mSummary.Effect = TParamEffect.NoObject) then
  begin
    Exit;
  end;
  Result.Effect := mSummary.Effect;
  if (mSummary.Effect <> TParamEffect.Borrows) or (mSummary.Forwards = nil) then
  begin
    Exit;
  end;
  mKey := SymbolKey(AUnit, ASymbol, AArgument);
  if ADepth >= cMaxDepth then
  begin
    Result.Effect := TParamEffect.Unknown;
    Exit;
  end;
  // Ein Kreis (Rekursion) fügt nichts hinzu: Die übrigen Wege entscheiden.
  FPending.Add(mKey, True);
  try
    for mForward in mSummary.Forwards do
    begin
      mOther := ForwardEffect(AUnit, ASymbol, mForward, ADepth);
      if ForwardRank(mOther.Effect) > ForwardRank(Result.Effect) then
      begin
        Result.Effect := mOther.Effect;
        Result.Via := mOther.Via;
        if Result.Via = '' then
        begin
          Result.Via := mOther.Callee;
        end;
      end;
    end;
  finally
    FPending.Remove(mKey);
  end;
  if Result.Effect in [TParamEffect.Borrows, TParamEffect.Unknown] then
  begin
    Result.Via := '';
  end;
end;

function TCallOwnership.RoutinesEffect(const AUnit: TUnitIndex; const ASymbols: TArray<TIndexSymbol>;
  AArgument, AArgumentCount, ADepth: Integer): TCallEffect;
var
  mSymbol: TIndexSymbol;
  mKey: string;
  mFound: Boolean;
begin
  Result := NewEffect(TParamEffect.NoObject);
  if (ASymbols = nil) or AnyVirtual(ASymbols) then
  begin
    Exit(NewEffect(TParamEffect.Unknown));
  end;
  mFound := False;
  for mSymbol in ASymbols do
  begin
    if (AArgumentCount >= 0) and ((AArgumentCount < mSymbol.MinArgs) or (AArgumentCount > mSymbol.MaxArgs)) then
    begin
      Continue;
    end;
    mFound := True;
    mKey := SymbolKey(AUnit, mSymbol, AArgument);
    if FPending.ContainsKey(mKey) then
    begin
      MergeAlternative(Result, NewEffect(TParamEffect.Borrows));
      Continue;
    end;
    MergeAlternative(Result, SymbolEffect(AUnit, mSymbol, AArgument, ADepth));
    if Result.Effect = TParamEffect.Unknown then
    begin
      Exit;
    end;
  end;
  if not mFound then
  begin
    Result := NewEffect(TParamEffect.Unknown);
  end;
end;

function TCallOwnership.EffectOf(ACall: TSyntaxNode; AArgument: Integer): TCallEffect;
var
  mCandidates: TArray<TResolvedSymbol>;
  mCandidate: TResolvedSymbol;
  mUnit: TUnitIndex;
  mSymbols: TArray<TIndexSymbol>;
  mKnown: TParamEffect;
  mKey: string;
begin
  Result := NewEffect(TParamEffect.Unknown);
  if (ACall = nil) or (ACall.Kind <> TSyntaxKind.Call) or (ACall.ChildCount = 0) or (AArgument < 0) then
  begin
    Exit;
  end;
  mCandidates := nil;
  if FResolver <> nil then
  begin
    mCandidates := FResolver.CallCandidates(FTree, FFileName, ACall[0]);
  end;
  if mCandidates = nil then
  begin
    if (ACall[0].Kind = TSyntaxKind.Identifier) and KnownRoutine(ACall[0].Name, AArgument, mKnown) then
    begin
      Result.Effect := mKnown;
      Result.Callee := ACall[0].Name;
    end;
    Exit;
  end;
  mCandidate := mCandidates[0];
  if not (mCandidate.SymbolKind in cRoutineKinds) or not FResolver.DeclaringUnit(mCandidate, mUnit) then
  begin
    Exit;
  end;
  mKey := LowerCase(mUnit.UnitName + '|' + mCandidate.Container + '.' + mCandidate.Name) + '|' +
    IntToStr(AArgument) + '|' + IntToStr(ACall.ChildCount - 1);
  if FMemo.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  mSymbols := RoutinesIn(mUnit, mCandidate.Name, mCandidate.Container);
  Result := RoutinesEffect(mUnit, mSymbols, AArgument, ACall.ChildCount - 1, 0);
  if Result.Callee = '' then
  begin
    Result.Callee := TIndexSymbol.QualifiedOf(mCandidate.Container, mCandidate.Name);
    Result.UnitName := mUnit.UnitName;
  end;
  FMemo.Add(mKey, Result);
end;

end.
