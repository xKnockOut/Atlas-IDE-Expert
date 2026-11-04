unit Atlas.Common.Rules.Builtin.Inheritance.Abstract;

// Regeln abstract-class-instantiated (#999) und inherited-abstract-call (#1026) aus
// Atlas.Common.Rules.Builtin.Inheritance: Create auf einer Klasse mit offenen abstrakten Methoden (W1020) bzw.
// inherited Name(…) auf eine im Vorfahren abstrakte Methode; beides läuft in EAbstractError.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TAbstractClassInstantiatedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInheritedAbstractCallRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Trägt der Methodenkopf ASignature die Direktive abstract ("procedure A; virtual; abstract;")?
    /// </summary>
    class function IsAbstractSignature(const ASignature: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry;

const
  /// <summary>So viele offene Methoden nennt die Meldung, der Rest wird gezählt.</summary>
  cMaxNamed = 5;

type
  /// <summary>Prüfung einer Unit für abstract-class-instantiated.</summary>
  TAbstractInstanceCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FAncestry: TAncestry;
    FTokens: TArray<TPascalToken>;
    FActions: TClassActionContext;
    function ClassBefore(ADot: Integer): Integer;
    function CreatesSubclass(const ALocation: TSymbolLocation): Boolean;
    function OverrideFixes(const ALocation: TSymbolLocation; const AOpen: TArray<TIndexSymbol>;
      const AOwners: TArray<string>): TArray<TRuleFix>;
    procedure CheckCall(AName, ACreate: Integer);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

  /// <summary>Prüfung einer Unit für inherited-abstract-call.</summary>
  TInheritedAbstractCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FTokens: TArray<TPascalToken>;
    FResolver: TNameResolver;
    FFileName: string;
    FCalls: TDictionary<Integer, TSyntaxNode>;
    procedure CollectCalls;
    procedure CheckCall(AExpr: TSyntaxNode; ANameToken: Integer);
    procedure CheckCalls;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

/// <summary>Steht bei AIndex das Ende einer Typargumentliste ("TListe&lt;T&gt;"), das Token vor ihrem "&lt;";
/// sonst AIndex.</summary>
function SkipTypeArgs(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  Depth: Integer;
begin
  Result := AIndex;
  if (Result < 0) or (ATokens[Result].Text <> '>') then
  begin
    Exit;
  end;
  Depth := 0;
  repeat
    if ATokens[Result].Text = '>' then
    begin
      Inc(Depth);
    end
    else if ATokens[Result].Text = '<' then
    begin
      Dec(Depth);
    end;
    Dec(Result);
  until (Result < 0) or (Depth = 0);
end;

/// <summary>Namen der offenen Methoden für die Meldung, höchstens cMaxNamed, geerbte mit Klasse davor.</summary>
function OpenNames(const ALocation: TSymbolLocation; const AOpen: TArray<TIndexSymbol>;
  const AOwners: TArray<string>): string;
var
  Names: TArray<string>;
  Index: Integer;
begin
  Names := nil;
  for Index := 0 to High(AOpen) do
  begin
    if Length(Names) >= cMaxNamed then
    begin
      Break;
    end;
    if SameText(AOwners[Index], ALocation.Symbol.Name) then
    begin
      Names := Names + [AOpen[Index].Name];
    end
    else
    begin
      Names := Names + [AOwners[Index] + '.' + AOpen[Index].Name];
    end;
  end;
  Result := string.Join(', ', Names);
  if Length(AOpen) > cMaxNamed then
  begin
    Result := Result + Format(' und %d weitere', [Length(AOpen) - cMaxNamed]);
  end;
end;

{ TAbstractClassInstantiatedRule }

function TAbstractClassInstantiatedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('abstract-class-instantiated', TRuleSeverity.Warning,
    'Instanz einer Klasse mit abstrakten Methoden');
end;

procedure TAbstractClassInstantiatedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TAbstractInstanceCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Check := TAbstractInstanceCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
  end;
end;

{ TAbstractInstanceCheck }

constructor TAbstractInstanceCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FCache := TRuleDerived.Open(AContext);
  FTokens := TRuleDerived.CodeTokens(FCache, AContext);
  FAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(FCache, AContext));
  FActions := TClassActionContext.Default;
  FActions.Index := AContext.Index;
  FActions.Namespaces := AContext.Namespaces;
  FActions.DelphiVersion := AContext.DelphiVersion;
  FActions.Style := AContext.Formatting;
end;

destructor TAbstractInstanceCheck.Destroy;
begin
  FAncestry.Free;
  inherited Destroy;
end;

/// <summary>Klassenname vor ".Create" an Token ADot (dem Punkt); -1 ohne.</summary>
function TAbstractInstanceCheck.ClassBefore(ADot: Integer): Integer;
var
  Index: Integer;
begin
  // TListe<T>.Create
  Index := SkipTypeArgs(FTokens, ADot - 1);
  Result := -1;
  if (Index < 0) or (FTokens[Index].Kind <> TPascalTokenKind.Identifier) then
  begin
    Exit;
  end;
  // constructor TForm.Create: der Kopf eines Rumpfs.
  if (Index > 0) and (FTokens[Index - 1].Kind = TPascalTokenKind.Keyword) and MatchText(FTokens[Index - 1].Text,
    ['constructor', 'procedure', 'function', 'destructor']) then
  begin
    Exit;
  end;
  Result := Index;
end;

/// <summary>Create als Klassenfunktion (THTTPClient.Create liefert eine Instanz einer passenden Unterklasse): keine
/// Instanz der abstrakten Klasse selbst.</summary>
function TAbstractInstanceCheck.CreatesSubclass(const ALocation: TSymbolLocation): Boolean;
var
  Member: TIndexSymbol;
begin
  Result := False;
  for Member in FAncestry.Members(ALocation) do
  begin
    Result := Result or (SameText(Member.Name, 'Create') and (Member.Kind <> TIndexSymbolKind.Constructor_));
  end;
end;

/// <summary>Geerbte abstrakte Methoden einer Klasse dieser Datei: dort überschreiben; ab der zweiten als
/// Alternative.</summary>
function TAbstractInstanceCheck.OverrideFixes(const ALocation: TSymbolLocation; const AOpen: TArray<TIndexSymbol>;
  const AOwners: TArray<string>): TArray<TRuleFix>;
var
  Index: Integer;
  Action: TCodeAction;
begin
  Result := nil;
  if ALocation.FileName <> '' then
  begin
    Exit;
  end;
  for Index := 0 to High(AOpen) do
  begin
    if not SameText(AOwners[Index], ALocation.Symbol.Name) and TClassActions.OverrideMethod(FContext.Text,
      ALocation.Symbol.Range.StartPos.Line, AOpen[Index].Name, FActions, Action) then
    begin
      Result := Result + [TRuleFix.Create(Format('%s in %s überschreiben', [AOpen[Index].Name,
        ALocation.Symbol.Name]), Action.Edits)];
      Result[High(Result)].Alternative := Length(Result) > 1;
    end;
  end;
end;

procedure TAbstractInstanceCheck.CheckCall(AName, ACreate: Integer);
const
  cMessage: array[Boolean] of string = ('%s hat die abstrakten Methoden %s; ihr Aufruf löst EAbstractError aus ' +
    '(wie W1020).', '%s hat die abstrakte Methode %s; der Aufruf löst EAbstractError aus (wie W1020).');
var
  Location: TSymbolLocation;
  Open: TArray<TIndexSymbol>;
  Owners: TArray<string>;
begin
  if not FAncestry.FindClass(FTokens[AName].Text, Location) or CreatesSubclass(Location) then
  begin
    Exit;
  end;
  Open := FAncestry.OpenAbstractMethods(Location, Owners);
  if Open <> nil then
  begin
    FReport.Add(TTextRange.Create(FTokens[AName].StartPos, FTokens[ACreate].EndPos),
      Format(cMessage[Length(Open) = 1], [Location.Symbol.Name, OpenNames(Location, Open, Owners)]),
      TRuleConfidence.High, OverrideFixes(Location, Open, Owners));
  end;
end;

procedure TAbstractInstanceCheck.Run;
var
  Index, Name: Integer;
begin
  for Index := 1 to High(FTokens) do
  begin
    if (FTokens[Index].Kind <> TPascalTokenKind.Identifier) or not SameText(FTokens[Index].Text, 'Create') or
      (FTokens[Index - 1].Text <> '.') then
    begin
      Continue;
    end;
    Name := ClassBefore(Index - 1);
    if Name >= 0 then
    begin
      CheckCall(Name, Index);
    end;
  end;
end;

{ TInheritedAbstractCallRule }

function TInheritedAbstractCallRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('inherited-abstract-call', TRuleSeverity.Warning,
    'inherited ruft eine abstrakte Methode auf');
end;

/// <summary>ASignature ohne Parameterliste: ein Parameter "abstract: Boolean" wäre keine Direktive.</summary>
function WithoutParameters(const ASignature: string): string;
var
  Depth, Position: Integer;
begin
  Result := '';
  Depth := 0;
  for Position := 1 to Length(ASignature) do
  begin
    if ASignature[Position] = '(' then
    begin
      Inc(Depth);
    end
    else if ASignature[Position] = ')' then
    begin
      Dec(Depth);
    end
    else if Depth = 0 then
    begin
      Result := Result + ASignature[Position];
    end;
  end;
end;

class function TInheritedAbstractCallRule.IsAbstractSignature(const ASignature: string): Boolean;
var
  Parts: TArray<string>;
  Index: Integer;
begin
  Parts := WithoutParameters(ASignature).Split([';']);
  // Der erste Teil ist der Kopf selbst, die Direktiven folgen hinter Semikolons.
  Result := False;
  for Index := 1 to High(Parts) do
  begin
    Result := Result or SameText(Trim(Parts[Index]), 'abstract');
  end;
end;

procedure TInheritedAbstractCallRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TInheritedAbstractCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Check := TInheritedAbstractCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
  end;
end;

/// <summary>Anweisung, die nur aus dem inherited-Aufruf AExpr besteht und in einem begin…end steht; sonst nil.
/// </summary>
function OwnStatement(AExpr: TSyntaxNode): TSyntaxNode;
var
  Node: TSyntaxNode;
begin
  Result := nil;
  Node := AExpr.Parent;
  if (Node <> nil) and (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 0) and (Node[0] = AExpr) then
  begin
    Node := Node.Parent;
  end;
  if (Node <> nil) and (Node.Kind = TSyntaxKind.CallStatement) and (Node.Parent <> nil) and
    (Node.Parent.Kind = TSyntaxKind.Block) then
  begin
    Result := Node;
  end;
end;

/// <summary>Jede passende Überladung ist abstrakt; sonst wählt der Compiler womöglich eine andere.</summary>
function AllAbstract(const ACandidates: TArray<TResolvedSymbol>): Boolean;
var
  Candidate: TResolvedSymbol;
begin
  Result := ACandidates <> nil;
  for Candidate in ACandidates do
  begin
    Result := Result and (Candidate.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and
      (Candidate.Condition = '') and TInheritedAbstractCallRule.IsAbstractSignature(Candidate.Signature);
  end;
end;

{ TInheritedAbstractCheck }

constructor TInheritedAbstractCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FCache := TRuleDerived.Open(AContext);
  FTokens := TRuleDerived.CodeTokens(FCache, AContext);
  FCalls := TDictionary<Integer, TSyntaxNode>.Create;
end;

destructor TInheritedAbstractCheck.Destroy;
begin
  FCalls.Free;
  inherited Destroy;
end;

/// <summary>inherited mit Namen; ein bloßes inherited; übergeht der Compiler bei abstrakten Methoden still.
/// </summary>
procedure TInheritedAbstractCheck.CollectCalls;
var
  Calls: TDictionary<Integer, TSyntaxNode>;
begin
  Calls := FCalls;
  FContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.InheritedExpr) and (ANode.Name <> '') then
      begin
        Calls.AddOrSetValue(ANode.StartOffset, ANode);
      end;
      Result := True;
    end);
end;

procedure TInheritedAbstractCheck.CheckCall(AExpr: TSyntaxNode; ANameToken: Integer);
var
  Candidates: TArray<TResolvedSymbol>;
  Statement: TSyntaxNode;
  Fixes: TArray<TRuleFix>;
begin
  Candidates := FResolver.ResolveAll(FContext.Tree, FFileName, FTokens[ANameToken].StartPos);
  if not AllAbstract(Candidates) then
  begin
    Exit;
  end;
  Fixes := nil;
  Statement := OwnStatement(AExpr);
  if Statement <> nil then
  begin
    Fixes := [RemoveStatementFix(FCache, FContext, Statement, 'Aufruf entfernen')];
  end;
  FReport.Add(TTextRange.Create(AExpr.StartPos, AExpr.EndPos), Format('%s.%s ist abstrakt; der Aufruf über ' +
    'inherited löst zur Laufzeit EAbstractError aus.', [Candidates[0].Container, Candidates[0].Name]),
    TRuleConfidence.High, Fixes);
end;

procedure TInheritedAbstractCheck.CheckCalls;
var
  Index: Integer;
  Node: TSyntaxNode;
begin
  for Index := 0 to High(FTokens) - 1 do
  begin
    if FCalls.TryGetValue(FTokens[Index].Offset, Node) and
      (FTokens[Index + 1].Kind = TPascalTokenKind.Identifier) then
    begin
      CheckCall(Node, Index + 1);
    end;
  end;
end;

procedure TInheritedAbstractCheck.Run;
begin
  CollectCalls;
  if FCalls.Count = 0 then
  begin
    Exit;
  end;
  FFileName := ResolverFileName(FContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  FResolver := TRuleDerived.Resolver(FCache, FContext);
  FResolver.PinTree(FContext.Tree, FFileName);
  try
    CheckCalls;
  finally
    FResolver.UnpinTree;
  end;
end;

end.
