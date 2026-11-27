unit Rules.Ownership;

// Wer gibt das frei? (#1877) Je Erzeugung „TKlasse.Create…“ einer Unit die
// Art der Freigabe für die Marke im Editor (atlas.server.ownership):
//   InDestroy   Feld, das der Destruktor der Klasse freigibt (Zeile)
//   InFinally   lokale Variable, frei im finally derselben Routine (Zeile)
//   Freed       freigegeben, aber nicht im Destruktor bzw. nicht im finally (Zeile)
//   Owner       Komponente mit Owner (Self, AOwner, Application …)
//   OwnedList   gehört einer Liste, die ihre Elemente besitzt (Liste.Add(…))
//   RefCounted  Interface-Variable bzw. -Feld: Referenzzählung
//   Returned    an den Aufrufer zurückgegeben (Result, Exit, out-Parameter)
//   Passed      weitergegeben (Argument, Zuweisung an etwas anderes); was der Empfänger tut, ist unklar
//   FreedBy     an eine Routine übergeben, die es freigibt (Rumpf laut Index, auch in einer anderen Unit)
//   TakenBy     an eine Routine übergeben, die es übernimmt (Feld, Liste, Rückgabe …)
//   Lent        an eine Routine übergeben, die es nur liest bzw. füllt; freigeben muss weiter diese Routine
//   Unknown     unklar (Unit-Variable, Ausdruck, Feld ohne Free außerhalb des Konstruktors …)
//   Never       nie freigegeben: genau die Stellen, die eine der Regeln aus cRuleIds meldet
// Zusatz bei Containern: TObjectList, TObjectDictionary mit doOwnsValues usw. „besitzt Elemente“; eine Liste ohne
// Besitz mit demselben Elementtyp wie eine besitzende Liste der Klasse „Elemente gehören FListe“.
//
// Gleichlauf mit den Regeln: „nie freigegeben“ kommt nur aus den Befunden der Regeln (field-not-freed,
// create-without-assignment, local-object-not-freed, created-result-not-freed), die der Aufrufer für denselben
// Text mitgibt; Felder klärt dieselbe Analyse wie field-not-freed (TOwnedFields.Analyze), Owner und Typen dieselbe
// Typauflösung (TFreeFieldTypes). So zeigen Marke und Regeln nie Verschiedenes.
//
// Über Unit-Grenzen: Geht das Objekt als Argument an eine Routine, fragt die Analyse dieselbe Zusammenfassung je
// Parameter wie local-object-not-freed (Rules.CallOwnership); Detail nennt dann die Routine, bei
// Weitergaben „Routine › Routine, die freigibt bzw. übernimmt“.

interface

uses
  Atlas.Common.Documents.Contract,
  Rules.Contract,
  Atlas.Common.Findings.Contract;

type
{$SCOPEDENUMS ON}
  TOwnershipKind = (InDestroy, InFinally, Freed, Owner, OwnedList, RefCounted, Returned, Passed, Unknown, Never,
    FreedBy, TakenBy, Lent);
  TOwnershipContainer = (None, OwnsElements, ElementsOwned);
{$SCOPEDENUMS OFF}

  TOwnershipSite = record
    /// <summary>Der Ausdruck T.Create(…), Zeilen und Zeichen ab 0.</summary>
    Range: TTextRange;
    /// <summary>Erzeugte Klasse wie im Quelltext, z. B. TObjectList&lt;TAuftrag&gt;.</summary>
    ClassName: string;
    /// <summary>Variable oder Feld, das das Objekt erhält; '' ohne.</summary>
    Target: string;
    Kind: TOwnershipKind;
    /// <summary>Zeile der Freigabe (InDestroy, InFinally, Freed), ab 0; -1 sonst.</summary>
    FreeLine: Integer;
    /// <summary>Owner, besitzende Liste, Empfänger bzw. Grund; '' ohne.</summary>
    Detail: string;
    Container: TOwnershipContainer;
    /// <summary>Bei ElementsOwned die besitzende Liste.</summary>
    ContainerOwner: string;
    /// <summary>Regel, die die Stelle meldet (Never); '' sonst.</summary>
    Rule: string;
    /// <summary>Meldung dieser Regel bzw. Grund aus der Feldanalyse; '' ohne.</summary>
    Message: string;
  end;

  TOwnershipSites = class
  public const
    cKindNames: array[TOwnershipKind] of string = ('destroy', 'finally', 'freed', 'owner', 'ownedList', 'interface',
      'returned', 'passed', 'unknown', 'never', 'freedBy', 'takenBy', 'lent');
    cContainerNames: array[TOwnershipContainer] of string = ('', 'ownsElements', 'elementsOwned');
    /// <summary>Regeln, deren Befunde „nie freigegeben“ bedeuten.</summary>
    cRuleIds: array[0..3] of string = ('field-not-freed', 'create-without-assignment', 'local-object-not-freed',
      'created-result-not-freed');
  public
    /// <summary>Alle Erzeugungen in AContext.Tree (Text AContext.Text) in Reihenfolge des Texts. AContext.Index
    /// (auch nil) klärt Typen und gerufene Routinen aus anderen Units; AFindings sind die Befunde der Regeln für
    /// denselben Text (andere Regeln stören nicht).</summary>
    class function Analyze(const AContext: TRuleContext; const AFindings: TArray<TRuleFinding>):
      TArray<TOwnershipSite>; static;
    /// <summary>Ist ARuleId eine der Regeln aus cRuleIds?</summary>
    class function IsOwnershipRule(const ARuleId: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Semantics.OwnedFields,
  Atlas.Common.Semantics.OwnedFields.Types,
  Rules.Builtin.Ownership,
  Rules.Internals.OwnershipTree,
  Rules.CallOwnership,
  Atlas.Text.Names,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.SyntaxNodes,
  Atlas.Common.Pascal.ObjectUses,
  Atlas.Common.Pascal.ParamOwnership,
  Atlas.Common.Semantics.CallOwnership,
  Rules.Trees;

const
  /// <summary>Listen, die ihre Elemente besitzen können (TObjectList ohne False usw.).</summary>
  cOwningLists: array[0..4] of string = ('TObjectList', 'TObjectDictionary', 'TObjectStack', 'TObjectQueue',
    'TComponentList');
  /// <summary>Listen, die Elemente nur verweisen (oder mit False erzeugt).</summary>
  cLists: array[0..6] of string = ('TList', 'TObjectList', 'TStack', 'TQueue', 'TObjectStack', 'TObjectQueue',
    'TComponentList');
  /// <summary>Methoden einer Liste, die ein Element aufnehmen.</summary>
  cTakingMembers: array[0..3] of string = ('Add', 'Insert', 'Push', 'Enqueue');

type
{$SCOPEDENUMS ON}
  /// <summary>Wohin das neue Objekt geht.</summary>
  TOwnershipPlace = (Expression, Assigned, InlineVar, Argument, Statement, AsInterface);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Erzeugung vor der Einstufung.</summary>
  TOwnershipRaw = record
    Node: TSyntaxNode;
    Routine: TSyntaxNode;
    ClassName: string;
    TypeName: string;
    /// <summary>Erstes Argument des Konstruktors; nil ohne.</summary>
    Argument: TSyntaxNode;
    Place: TOwnershipPlace;
    /// <summary>Ziel der Zuweisung (Assigned) bzw. Aufruf (Argument); nil sonst.</summary>
    Other: TSyntaxNode;
    /// <summary>Zeile der Anweisung, die die Erzeugung enthält.</summary>
    StatementLine: Integer;
  end;

  TOwnershipScan = class
  private
    FTree: TSyntaxTree;
    FText: string;
    FFindings: TArray<TRuleFinding>;
    FTypes: TFreeFieldTypes;
    FFields: TArray<TOwnedField>;
    FRaw: TArray<TOwnershipRaw>;
    FSites: TArray<TOwnershipSite>;
    FCalls: TRuleCallOwnership;
    function Creation(ANode: TSyntaxNode; out ARaw: TOwnershipRaw): Boolean;
    procedure Locate(var ARaw: TOwnershipRaw);
    procedure Collect;
    function FindingAt(ALine: Integer; out AFinding: TRuleFinding): Boolean;
    function IsOwned(const ARaw: TOwnershipRaw): Boolean;
    function IsInterfaceType(const ATypeName: string): Boolean;
    function OwningList(const AClassName, AName: string): Boolean;
    procedure SetContainer(AIndex: Integer);
    procedure Handover(const AClassName: string; ACall, AArgument: TSyntaxNode; var ASite: TOwnershipSite);
    procedure CalleeVerdict(ACall, AArgument: TSyntaxNode; var ASite: TOwnershipSite);
    function FieldVerdict(const ARaw: TOwnershipRaw; const AField: string; var ASite: TOwnershipSite): Boolean;
    procedure FieldRelease(const ARaw: TOwnershipRaw; const AField: string; var ASite: TOwnershipSite);
    procedure ClassifyField(const ARaw: TOwnershipRaw; const AField: string; var ASite: TOwnershipSite);
    procedure ClassifyLocal(const ARaw: TOwnershipRaw; const AName: string; var ASite: TOwnershipSite);
    procedure UseOfLocal(const ARaw: TOwnershipRaw; AOccurrence: TSyntaxNode; var ASite: TOwnershipSite);
    procedure ClassifyTarget(const ARaw: TOwnershipRaw; var ASite: TOwnershipSite);
    procedure Classify(AIndex: Integer);
  public
    constructor Create(const AContext: TRuleContext; const AFindings: TArray<TRuleFinding>);
    destructor Destroy; override;
    function Run: TArray<TOwnershipSite>;
  end;

{ Hilfen }

function NewSite(const ARaw: TOwnershipRaw): TOwnershipSite;
begin
  Result := Default(TOwnershipSite);
  Result.Range := TTextRange.Create(ARaw.Node.StartPos, ARaw.Node.EndPos);
  Result.ClassName := ARaw.TypeName;
  Result.Kind := TOwnershipKind.Unknown;
  Result.FreeLine := -1;
end;

/// <summary>Stufe der Freigabe: Höhere ersetzen niedrigere (finally vor anderer Freigabe vor Weitergabe vor
/// Leihgabe).</summary>
function Rank(AKind: TOwnershipKind): Integer;
begin
  case AKind of
    TOwnershipKind.InFinally:
      Result := 7;
    TOwnershipKind.InDestroy, TOwnershipKind.Freed, TOwnershipKind.FreedBy:
      Result := 6;
    TOwnershipKind.OwnedList:
      Result := 5;
    TOwnershipKind.Returned:
      Result := 4;
    TOwnershipKind.TakenBy:
      Result := 3;
    TOwnershipKind.Passed:
      Result := 2;
    TOwnershipKind.Lent:
      Result := 1;
  else
    Result := 0;
  end;
end;

procedure Take(var ASite: TOwnershipSite; AKind: TOwnershipKind; ALine: Integer; const ADetail: string);
begin
  if Rank(AKind) > Rank(ASite.Kind) then
  begin
    ASite.Kind := AKind;
    ASite.FreeLine := ALine;
    ASite.Detail := ADetail;
  end;
end;

/// <summary>Zeile der Anweisung um ANode.</summary>
function StatementLine(ANode: TSyntaxNode): Integer;
var
  mCurrent: TSyntaxNode;
begin
  mCurrent := ANode;
  while (mCurrent.Parent <> nil) and not (mCurrent.Kind in [TSyntaxKind.AssignStatement,
    TSyntaxKind.CallStatement, TSyntaxKind.InlineVar, TSyntaxKind.RaiseStatement]) do
  begin
    mCurrent := mCurrent.Parent;
  end;
  Result := mCurrent.StartPos.Line;
end;

/// <summary>Das Argument, als das die Erzeugung an ihren Aufruf geht: der Ausdruck samt umgebender Klammern.
/// </summary>
function ArgumentNode(const ARaw: TOwnershipRaw): TSyntaxNode;
begin
  Result := ARaw.Node;
  while (Result.Parent <> nil) and (Result.Parent <> ARaw.Other) do
  begin
    Result := Result.Parent;
  end;
end;

function LooksLikeType(const AName: string): Boolean;
begin
  Result := (Length(AName) > 1) and CharInSet(AName[1], ['T']) and CharInSet(AName[2], ['A'..'Z']);
end;

{ TOwnershipScan }

constructor TOwnershipScan.Create(const AContext: TRuleContext; const AFindings: TArray<TRuleFinding>);
begin
  inherited Create;
  FTree := AContext.Tree;
  FText := AContext.Text;
  FFindings := AFindings;
  FTypes := TFreeFieldTypes.Create(FTree, FText, AContext.Index);
  FFields := TOwnedFields.Analyze(FTree, FText, AContext.Index);
  FCalls := TRuleCallOwnership.Create(AContext);
end;

destructor TOwnershipScan.Destroy;
begin
  FCalls.Free;
  FTypes.Free;
  inherited Destroy;
end;

/// <summary>Ist ANode eine Erzeugung T.Create… einer Klasse? Füllt Typ, Argument und Routine.</summary>
function TOwnershipScan.Creation(ANode: TSyntaxNode; out ARaw: TOwnershipRaw): Boolean;
var
  mAccess, mReceiver: TSyntaxNode;
begin
  ARaw := Default(TOwnershipRaw);
  mAccess := ANode;
  if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) then
  begin
    mAccess := ANode[0];
    if ANode.ChildCount > 1 then
    begin
      ARaw.Argument := ANode[1];
    end;
  end
  else if (ANode.Kind <> TSyntaxKind.MemberAccess) or ((ANode.Parent <> nil) and
    (ANode.Parent.Kind = TSyntaxKind.Call) and (ANode.Parent[0] = ANode)) then
  begin
    // Der Aufruf T.Create(…) zählt am Call-Knoten, nicht an seinem Zugriff.
    Exit(False);
  end;
  Result := (mAccess.Kind = TSyntaxKind.MemberAccess) and StartsText('Create', mAccess.Name) and
    (mAccess.ChildCount > 0);
  if not Result then
  begin
    Exit;
  end;
  mReceiver := mAccess[0];
  if mReceiver.Kind = TSyntaxKind.Identifier then
  begin
    ARaw.TypeName := mReceiver.Name;
  end
  else if (mReceiver.Kind = TSyntaxKind.MemberAccess) and (mReceiver.ChildCount >= 2) and
    (mReceiver[1].Kind = TSyntaxKind.GenericArgs) then
  begin
    ARaw.TypeName := TFreeFieldTypes.CodeOf(FText, mReceiver);
  end;
  Result := LooksLikeType(TTextNames.WithoutGenerics(ARaw.TypeName)) and
    not (FTypes.TypeGuess(ARaw.TypeName) in [tgRecord, tgInterface, tgOther]) and not TOwnershipTree.InRaise(ANode);
  ARaw.Node := ANode;
  ARaw.Routine := TOwnershipTree.RoutineOf(ANode);
  ARaw.ClassName := TOwnershipTree.ClassOf(ARaw.Routine);
  ARaw.StatementLine := StatementLine(ANode);
end;

/// <summary>Wohin das Objekt geht: Klammern und Typumwandlungen zählen nicht.</summary>
procedure TOwnershipScan.Locate(var ARaw: TOwnershipRaw);
var
  mCurrent, mParent: TSyntaxNode;
begin
  mCurrent := ARaw.Node;
  mParent := mCurrent.Parent;
  while (mParent <> nil) and (mParent.Kind = TSyntaxKind.ParenExpr) do
  begin
    mCurrent := mParent;
    mParent := mCurrent.Parent;
  end;
  ARaw.Place := TOwnershipPlace.Expression;
  if mParent = nil then
  begin
    Exit;
  end;
  case mParent.Kind of
    TSyntaxKind.AssignStatement:
      if (mParent.ChildCount > 1) and (mParent[1] = mCurrent) then
      begin
        ARaw.Place := TOwnershipPlace.Assigned;
        ARaw.Other := mParent[0];
      end;
    TSyntaxKind.InlineVar:
      begin
        ARaw.Place := TOwnershipPlace.InlineVar;
        ARaw.Other := mParent;
      end;
    TSyntaxKind.Call:
      if mParent[0] <> mCurrent then
      begin
        ARaw.Place := TOwnershipPlace.Argument;
        ARaw.Other := mParent;
      end;
    TSyntaxKind.CallStatement:
      ARaw.Place := TOwnershipPlace.Statement;
    TSyntaxKind.BinaryExpr:
      if SameText(mParent.Name, 'as') then
      begin
        ARaw.Place := TOwnershipPlace.AsInterface;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TOwnershipScan.Collect;
var
  mFound: TArray<TOwnershipRaw>;
begin
  mFound := nil;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mRaw: TOwnershipRaw;
    begin
      Result := True;
      if (ANode.Kind in [TSyntaxKind.Call, TSyntaxKind.MemberAccess]) and Creation(ANode, mRaw) then
      begin
        Locate(mRaw);
        mFound := mFound + [mRaw];
      end;
    end);
  FRaw := mFound;
end;

function TOwnershipScan.FindingAt(ALine: Integer; out AFinding: TRuleFinding): Boolean;
var
  mFinding: TRuleFinding;
begin
  for mFinding in FFindings do
  begin
    if (mFinding.Range.StartPos.Line = ALine) and TOwnershipSites.IsOwnershipRule(mFinding.RuleId) then
    begin
      AFinding := mFinding;
      Exit(True);
    end;
  end;
  AFinding := Default(TRuleFinding);
  Result := False;
end;

/// <summary>Komponente mit Owner ungleich nil (auch ein Komponentenfeld der Klasse als Owner).</summary>
function TOwnershipScan.IsOwned(const ARaw: TOwnershipRaw): Boolean;
var
  mFieldType: string;
begin
  Result := False;
  if (ARaw.Argument = nil) or ((ARaw.Argument.Kind = TSyntaxKind.Literal) and
    SameText(ARaw.Argument.Name, 'nil')) then
  begin
    Exit;
  end;
  Result := FTypes.OwnedByArgument(ARaw.TypeName, ARaw.Argument) or
    (TOwnershipTree.FieldType(FTree.Root, ARaw.ClassName, TSyntaxNodes.FieldName(ARaw.Argument),
    mFieldType) and FTypes.IsComponent(mFieldType));
end;

function TOwnershipScan.IsInterfaceType(const ATypeName: string): Boolean;
begin
  Result := (ATypeName <> '') and (TOwnershipTree.LooksLikeInterface(ATypeName) or
    (FTypes.TypeGuess(ATypeName) = tgInterface));
end;

/// <summary>Besitzt AName (Feld der Klasse AClassName bzw. Variable) seine Elemente? Erzeugung in der Unit, sonst
/// der deklarierte Typ des Felds (OwnsObjects ist dann True).</summary>
function TOwnershipScan.OwningList(const AClassName, AName: string): Boolean;
var
  mIndex: Integer;
  mType: string;
begin
  for mIndex := 0 to High(FSites) do
  begin
    if SameText(FSites[mIndex].Target, AName) and SameText(FRaw[mIndex].ClassName, AClassName) then
    begin
      Exit(FSites[mIndex].Container = TOwnershipContainer.OwnsElements);
    end;
  end;
  Result := TOwnershipTree.FieldType(FTree.Root, AClassName, AName, mType) and
    MatchText(TTextNames.WithoutGenerics(mType), cOwningLists);
end;

procedure TOwnershipScan.SetContainer(AIndex: Integer);
var
  mBase, mElement: string;
  mIsDictionary: Boolean;
  mOther: Integer;
begin
  mBase := TTextNames.WithoutGenerics(FSites[AIndex].ClassName);
  if MatchText(mBase, cOwningLists) and TOwnedItemFreedRule.CreatesOwning(mBase,
    TFreeFieldTypes.CodeOf(FText, FRaw[AIndex].Node), mIsDictionary) then
  begin
    FSites[AIndex].Container := TOwnershipContainer.OwnsElements;
    Exit;
  end;
  mElement := TOwnershipTree.ElementType(FSites[AIndex].ClassName);
  if not MatchText(mBase, cLists) or (mElement = '') then
  begin
    Exit;
  end;
  for mOther := 0 to High(FSites) do
  begin
    if (mOther <> AIndex) and (FSites[mOther].Container = TOwnershipContainer.OwnsElements) and
      (FSites[mOther].Target <> '') and SameText(FRaw[mOther].ClassName, FRaw[AIndex].ClassName) and
      SameText(TOwnershipTree.ElementType(FSites[mOther].ClassName), mElement) then
    begin
      FSites[AIndex].Container := TOwnershipContainer.ElementsOwned;
      FSites[AIndex].ContainerOwner := FSites[mOther].Target;
      Exit;
    end;
  end;
end;

/// <summary>Was die gerufene Routine laut Index mit dem Argument AArgument von ACall macht, auch in einer anderen
/// Unit: freigeben, übernehmen, nur leihen; unklar bleibt weitergegeben. Lesende Routinen wie Assign zählen nur,
/// wenn der Index nichts weiß: Eine eigene Methode Assign, die das Objekt behält, geht vor.</summary>
procedure TOwnershipScan.CalleeVerdict(ACall, AArgument: TSyntaxNode; var ASite: TOwnershipSite);
var
  mEffect: TCallEffect;
  mDetail: string;
begin
  mEffect := FCalls.EffectOf(ACall, TSyntaxNodes.IndexOf(ACall, AArgument) - 1);
  if (mEffect.Effect in [TParamEffect.Unknown, TParamEffect.NoObject]) and
    MatchText(ACall[0].Name, TObjectUses.cReadingCalls) then
  begin
    Exit;
  end;
  mDetail := mEffect.Callee;
  if mDetail = '' then
  begin
    mDetail := TFreeFieldTypes.CodeOf(FText, ACall[0]);
  end;
  if mEffect.Via <> '' then
  begin
    mDetail := mDetail + ' › ' + mEffect.Via;
  end;
  case mEffect.Effect of
    TParamEffect.Frees:
      Take(ASite, TOwnershipKind.FreedBy, -1, mDetail);
    TParamEffect.Keeps:
      Take(ASite, TOwnershipKind.TakenBy, -1, mDetail);
    TParamEffect.Borrows:
      Take(ASite, TOwnershipKind.Lent, -1, mDetail);
  else
    Take(ASite, TOwnershipKind.Passed, -1, TFreeFieldTypes.CodeOf(FText, ACall[0]));
  end;
end;

/// <summary>Das Objekt geht als Argument AArgument an ACall: Exit gibt zurück, Add… einer besitzenden Liste übergibt
/// den Besitz, sonst entscheidet die gerufene Routine (CalleeVerdict).</summary>
procedure TOwnershipScan.Handover(const AClassName: string; ACall, AArgument: TSyntaxNode;
  var ASite: TOwnershipSite);
var
  mCallee: TSyntaxNode;
  mReceiver: string;
begin
  mCallee := ACall[0];
  if (mCallee.Kind = TSyntaxKind.Identifier) and SameText(mCallee.Name, 'Exit') then
  begin
    Take(ASite, TOwnershipKind.Returned, -1, '');
    Exit;
  end;
  if (mCallee.Kind = TSyntaxKind.MemberAccess) and (mCallee.ChildCount = 1) and
    MatchText(mCallee.Name, cTakingMembers) then
  begin
    mReceiver := TSyntaxNodes.FieldName(mCallee[0]);
    if (mReceiver <> '') and OwningList(AClassName, mReceiver) then
    begin
      Take(ASite, TOwnershipKind.OwnedList, -1, mReceiver);
      Exit;
    end;
  end;
  CalleeVerdict(ACall, AArgument, ASite);
end;

/// <summary>Urteil der Analyse wie field-not-freed über das Feld: nie freigegeben (mit Befund) oder unklar; False,
/// wenn sie nichts dazu sagt.</summary>
function TOwnershipScan.FieldVerdict(const ARaw: TOwnershipRaw; const AField: string;
  var ASite: TOwnershipSite): Boolean;
var
  mField: TOwnedField;
  mFinding: TRuleFinding;
  mShort: string;
begin
  Result := False;
  // TFreeFields kennt die Klasse unter ihrem Namen ohne äußere Klassen.
  mShort := Copy(ARaw.ClassName, LastDelimiter('.', ARaw.ClassName) + 1, MaxInt);
  for mField in FFields do
  begin
    if not SameText(mField.Name, AField) or not SameText(mField.ClassName, mShort) then
    begin
      Continue;
    end;
    if (mField.State = TOwnedFieldState.NotFreed) and FindingAt(mField.Range.StartPos.Line, mFinding) then
    begin
      ASite.Kind := TOwnershipKind.Never;
      ASite.Rule := mFinding.RuleId;
      ASite.Message := mFinding.Message;
      Exit(True);
    end;
    if mField.State = TOwnedFieldState.Unclear then
    begin
      ASite.Message := mField.Reason;
      Exit(True);
    end;
  end;
end;

/// <summary>Freigabe des Felds in einer Methode der Klasse; die im Destruktor geht vor.</summary>
procedure TOwnershipScan.FieldRelease(const ARaw: TOwnershipRaw; const AField: string; var ASite: TOwnershipSite);
var
  mMethod, mNode: TSyntaxNode;
  mKind: TOwnershipKind;
begin
  for mMethod in TOwnershipTree.MethodsOf(FTree.Root, ARaw.ClassName) do
  begin
    mKind := TOwnershipKind.Freed;
    if EndsText('.Destroy', mMethod.Name) then
    begin
      mKind := TOwnershipKind.InDestroy;
    end;
    for mNode in TOwnershipTree.UsesWithSelf(mMethod, AField) do
    begin
      if TOwnershipTree.IsRelease(mNode) and ((ASite.Kind <> TOwnershipKind.InDestroy) or
        (mKind = TOwnershipKind.InDestroy)) then
      begin
        ASite.Kind := mKind;
        ASite.FreeLine := mNode.StartPos.Line;
        ASite.Detail := Copy(mMethod.Name, Length(ARaw.ClassName) + 2, MaxInt);
      end;
    end;
  end;
end;

/// <summary>Feld der Klasse: Analyse wie field-not-freed, sonst Free im Destruktor bzw. in einer anderen Methode.
/// </summary>
procedure TOwnershipScan.ClassifyField(const ARaw: TOwnershipRaw; const AField: string; var ASite: TOwnershipSite);
begin
  if not FieldVerdict(ARaw, AField, ASite) then
  begin
    FieldRelease(ARaw, AField, ASite);
  end;
end;

/// <summary>Lokale Variable: Befund der Regeln, sonst Freigabe, Rückgabe oder Weitergabe in der Routine.</summary>
procedure TOwnershipScan.ClassifyLocal(const ARaw: TOwnershipRaw; const AName: string; var ASite: TOwnershipSite);
var
  mFinding: TRuleFinding;
  mNode: TSyntaxNode;
begin
  if FindingAt(ARaw.StatementLine, mFinding) then
  begin
    ASite.Kind := TOwnershipKind.Never;
    ASite.Rule := mFinding.RuleId;
    ASite.Message := mFinding.Message;
    Exit;
  end;
  for mNode in TOwnershipTree.UsesWithSelf(ARaw.Routine, AName) do
  begin
    UseOfLocal(ARaw, mNode, ASite);
  end;
end;

/// <summary>Ein Vorkommen AOccurrence der lokalen Variablen: Freigabe, Rückgabe oder Weitergabe.</summary>
procedure TOwnershipScan.UseOfLocal(const ARaw: TOwnershipRaw; AOccurrence: TSyntaxNode;
  var ASite: TOwnershipSite);
var
  mParent: TSyntaxNode;
begin
  if TOwnershipTree.IsRelease(AOccurrence) then
  begin
    if TOwnershipTree.InFinally(AOccurrence, ARaw.Routine) then
    begin
      Take(ASite, TOwnershipKind.InFinally, AOccurrence.StartPos.Line, '');
    end
    else
    begin
      Take(ASite, TOwnershipKind.Freed, AOccurrence.StartPos.Line, '');
    end;
    Exit;
  end;
  mParent := AOccurrence.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  if (mParent.Kind = TSyntaxKind.AssignStatement) and (mParent.ChildCount > 1) and (mParent[1] = AOccurrence) then
  begin
    if SameText(TSyntaxNodes.FieldName(mParent[0]), 'Result') then
    begin
      Take(ASite, TOwnershipKind.Returned, -1, '');
    end
    else
    begin
      Take(ASite, TOwnershipKind.Passed, -1, TFreeFieldTypes.CodeOf(FText, mParent[0]));
    end;
  end
  else if (mParent.Kind = TSyntaxKind.Call) and (mParent[0] <> AOccurrence) then
  begin
    Handover(ARaw.ClassName, mParent, AOccurrence, ASite);
  end;
end;

/// <summary>Zuweisung an ein Ziel: Result, out-Parameter, lokale Variable, Feld oder etwas anderes.</summary>
procedure TOwnershipScan.ClassifyTarget(const ARaw: TOwnershipRaw; var ASite: TOwnershipSite);
var
  mName, mType: string;
begin
  if ARaw.Place = TOwnershipPlace.InlineVar then
  begin
    mName := ARaw.Other.Name;
  end
  else
  begin
    mName := TSyntaxNodes.FieldName(ARaw.Other);
  end;
  ASite.Target := mName;
  if mName = '' then
  begin
    ASite.Target := TFreeFieldTypes.CodeOf(FText, ARaw.Other);
    Take(ASite, TOwnershipKind.Passed, -1, ASite.Target);
    Exit;
  end;
  case TOwnershipTree.NameKind(FTree.Root, ARaw.Routine, mName, mType) of
    TOwnershipNameKind.ResultValue, TOwnershipNameKind.OutParameter:
      Take(ASite, TOwnershipKind.Returned, -1, mName);
    TOwnershipNameKind.Local:
      if IsInterfaceType(mType) then
      begin
        ASite.Kind := TOwnershipKind.RefCounted;
      end
      else
      begin
        ClassifyLocal(ARaw, mName, ASite);
      end;
    TOwnershipNameKind.Field:
      if IsInterfaceType(mType) then
      begin
        ASite.Kind := TOwnershipKind.RefCounted;
      end
      else
      begin
        ClassifyField(ARaw, mName, ASite);
      end;
  end;
end;

procedure TOwnershipScan.Classify(AIndex: Integer);
var
  mRaw: TOwnershipRaw;
  mFinding: TRuleFinding;
begin
  mRaw := FRaw[AIndex];
  if IsOwned(mRaw) then
  begin
    FSites[AIndex].Kind := TOwnershipKind.Owner;
    FSites[AIndex].Detail := TFreeFieldTypes.CodeOf(FText, mRaw.Argument);
    Exit;
  end;
  case mRaw.Place of
    TOwnershipPlace.Assigned, TOwnershipPlace.InlineVar:
      ClassifyTarget(mRaw, FSites[AIndex]);
    TOwnershipPlace.Argument:
      Handover(mRaw.ClassName, mRaw.Other, ArgumentNode(mRaw), FSites[AIndex]);
    TOwnershipPlace.AsInterface:
      FSites[AIndex].Kind := TOwnershipKind.RefCounted;
    TOwnershipPlace.Statement:
      if FindingAt(mRaw.StatementLine, mFinding) then
      begin
        FSites[AIndex].Kind := TOwnershipKind.Never;
        FSites[AIndex].Rule := mFinding.RuleId;
        FSites[AIndex].Message := mFinding.Message;
      end;
    TOwnershipPlace.Expression:
      // Teil eines größeren Ausdrucks (Methodenaufruf auf dem neuen Objekt, Operand): Wohin es geht, bleibt offen.
      FSites[AIndex].Kind := TOwnershipKind.Unknown;
  end;
end;

function TOwnershipScan.Run: TArray<TOwnershipSite>;
var
  mIndex: Integer;
begin
  Collect;
  SetLength(FSites, Length(FRaw));
  // Erst alle Ziele, dann Behälter, dann die Einstufung: Add an eine Liste fragt deren Behälter.
  for mIndex := 0 to High(FRaw) do
  begin
    FSites[mIndex] := NewSite(FRaw[mIndex]);
    if FRaw[mIndex].Place = TOwnershipPlace.InlineVar then
    begin
      FSites[mIndex].Target := FRaw[mIndex].Other.Name;
    end
    else if FRaw[mIndex].Place = TOwnershipPlace.Assigned then
    begin
      FSites[mIndex].Target := TSyntaxNodes.FieldName(FRaw[mIndex].Other);
    end;
  end;
  for mIndex := 0 to High(FSites) do
  begin
    SetContainer(mIndex);
  end;
  for mIndex := 0 to High(FSites) do
  begin
    Classify(mIndex);
  end;
  Result := FSites;
end;

{ TOwnershipSites }

class function TOwnershipSites.Analyze(const AContext: TRuleContext;
  const AFindings: TArray<TRuleFinding>): TArray<TOwnershipSite>;
var
  mScan: TOwnershipScan;
begin
  Result := nil;
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Create') then
  begin
    Exit;
  end;
  mScan := TOwnershipScan.Create(AContext, AFindings);
  try
    Result := mScan.Run;
  finally
    mScan.Free;
  end;
end;

class function TOwnershipSites.IsOwnershipRule(const ARuleId: string): Boolean;
begin
  Result := MatchText(ARuleId, cRuleIds);
end;

end.
