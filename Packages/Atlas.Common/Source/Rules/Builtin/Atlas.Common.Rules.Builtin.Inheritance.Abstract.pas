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
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TInheritanceAbstractText = (AndMore, AbstractInstanceTitle, OverrideIn, InheritedAbstractTitle, RemoveCall,
    InheritedAbstract, AbstractMany, AbstractOne);

const
  cTexts: array[TInheritanceAbstractText] of TAtlasText = (
    (De: ' und %d weitere'; En: ' and %d more'),
    (De: 'Instanz einer Klasse mit abstrakten Methoden'; En: 'Instance of a class with abstract methods'),
    (De: '%s in %s überschreiben'; En: 'Override %s in %s'),
    (De: 'inherited ruft eine abstrakte Methode auf'; En: 'inherited calls an abstract method'),
    (De: 'Aufruf entfernen'; En: 'Remove call'),
    (De: '%s.%s ist abstrakt; der Aufruf über inherited löst zur Laufzeit EAbstractError aus.';
     En: '%s.%s is abstract; the call via inherited raises EAbstractError at run time.'),
    (De: '%s hat die abstrakten Methoden %s; ihr Aufruf löst EAbstractError aus (wie W1020).';
     En: '%s has the abstract methods %s; calling them raises EAbstractError (like W1020).'),
    (De: '%s hat die abstrakte Methode %s; der Aufruf löst EAbstractError aus (wie W1020).';
     En: '%s has the abstract method %s; calling it raises EAbstractError (like W1020).'));

{$SCOPEDENUMS OFF}

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
  mDepth: Integer;
begin
  Result := AIndex;
  if (Result < 0) or (ATokens[Result].Text <> '>') then
  begin
    Exit;
  end;
  mDepth := 0;
  repeat
    if ATokens[Result].Text = '>' then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].Text = '<' then
    begin
      Dec(mDepth);
    end;
    Dec(Result);
  until (Result < 0) or (mDepth = 0);
end;

/// <summary>Namen der offenen Methoden für die Meldung, höchstens cMaxNamed, geerbte mit Klasse davor.</summary>
function OpenNames(const ALocation: TSymbolLocation; const AOpen: TArray<TIndexSymbol>;
  const AOwners: TArray<string>): string;
var
  mNames: TArray<string>;
  mIndex: Integer;
begin
  mNames := nil;
  for mIndex := 0 to High(AOpen) do
  begin
    if Length(mNames) >= cMaxNamed then
    begin
      Break;
    end;
    if SameText(AOwners[mIndex], ALocation.Symbol.Name) then
    begin
      mNames := mNames + [AOpen[mIndex].Name];
    end
    else
    begin
      mNames := mNames + [AOwners[mIndex] + '.' + AOpen[mIndex].Name];
    end;
  end;
  Result := string.Join(', ', mNames);
  if Length(AOpen) > cMaxNamed then
  begin
    Result := Result + cTexts[TInheritanceAbstractText.AndMore].Fmt([Length(AOpen) - cMaxNamed]);
  end;
end;

{ TAbstractClassInstantiatedRule }

function TAbstractClassInstantiatedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('abstract-class-instantiated', TRuleSeverity.Warning,
    cTexts[TInheritanceAbstractText.AbstractInstanceTitle].Text);
end;

procedure TAbstractClassInstantiatedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TAbstractInstanceCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mCheck := TAbstractInstanceCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
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
  mIndex: Integer;
begin
  // TListe<T>.Create
  mIndex := SkipTypeArgs(FTokens, ADot - 1);
  Result := -1;
  if (mIndex < 0) or (FTokens[mIndex].Kind <> TPascalTokenKind.Identifier) then
  begin
    Exit;
  end;
  // constructor TForm.Create: der Kopf eines Rumpfs.
  if (mIndex > 0) and (FTokens[mIndex - 1].Kind = TPascalTokenKind.Keyword) and MatchText(FTokens[mIndex - 1].Text,
    ['constructor', 'procedure', 'function', 'destructor']) then
  begin
    Exit;
  end;
  Result := mIndex;
end;

/// <summary>Create als Klassenfunktion (THTTPClient.Create liefert eine Instanz einer passenden Unterklasse): keine
/// Instanz der abstrakten Klasse selbst.</summary>
function TAbstractInstanceCheck.CreatesSubclass(const ALocation: TSymbolLocation): Boolean;
var
  mMember: TIndexSymbol;
begin
  Result := False;
  for mMember in FAncestry.Members(ALocation) do
  begin
    Result := Result or (SameText(mMember.Name, 'Create') and (mMember.Kind <> TIndexSymbolKind.Constructor_));
  end;
end;

/// <summary>Geerbte abstrakte Methoden einer Klasse dieser Datei: dort überschreiben; ab der zweiten als
/// Alternative.</summary>
function TAbstractInstanceCheck.OverrideFixes(const ALocation: TSymbolLocation; const AOpen: TArray<TIndexSymbol>;
  const AOwners: TArray<string>): TArray<TRuleFix>;
var
  mIndex: Integer;
  mAction: TCodeAction;
begin
  Result := nil;
  if ALocation.FileName <> '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AOpen) do
  begin
    if not SameText(AOwners[mIndex], ALocation.Symbol.Name) and TClassActions.OverrideMethod(FContext.Text,
      ALocation.Symbol.Range.StartPos.Line, AOpen[mIndex].Name, FActions, mAction) then
    begin
      Result := Result + [TRuleFix.Create(cTexts[TInheritanceAbstractText.OverrideIn].Fmt([AOpen[mIndex].Name,
        ALocation.Symbol.Name]), mAction.Edits)];
      Result[High(Result)].Alternative := Length(Result) > 1;
    end;
  end;
end;

procedure TAbstractInstanceCheck.CheckCall(AName, ACreate: Integer);
const
  cMessage: array[Boolean] of TInheritanceAbstractText = (TInheritanceAbstractText.AbstractMany,
    TInheritanceAbstractText.AbstractOne);
var
  mLocation: TSymbolLocation;
  mOpen: TArray<TIndexSymbol>;
  mOwners: TArray<string>;
begin
  if not FAncestry.FindClass(FTokens[AName].Text, mLocation) or CreatesSubclass(mLocation) then
  begin
    Exit;
  end;
  mOpen := FAncestry.OpenAbstractMethods(mLocation, mOwners);
  if mOpen <> nil then
  begin
    FReport.Add(TTextRange.Create(FTokens[AName].StartPos, FTokens[ACreate].EndPos),
      cTexts[cMessage[Length(mOpen) = 1]].Fmt([mLocation.Symbol.Name, OpenNames(mLocation, mOpen, mOwners)]),
      TRuleConfidence.High, OverrideFixes(mLocation, mOpen, mOwners));
  end;
end;

procedure TAbstractInstanceCheck.Run;
var
  mIndex, mName: Integer;
begin
  for mIndex := 1 to High(FTokens) do
  begin
    if (FTokens[mIndex].Kind <> TPascalTokenKind.Identifier) or not SameText(FTokens[mIndex].Text, 'Create') or
      (FTokens[mIndex - 1].Text <> '.') then
    begin
      Continue;
    end;
    mName := ClassBefore(mIndex - 1);
    if mName >= 0 then
    begin
      CheckCall(mName, mIndex);
    end;
  end;
end;

{ TInheritedAbstractCallRule }

function TInheritedAbstractCallRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('inherited-abstract-call', TRuleSeverity.Warning,
    cTexts[TInheritanceAbstractText.InheritedAbstractTitle].Text);
end;

/// <summary>ASignature ohne Parameterliste: ein Parameter "abstract: Boolean" wäre keine Direktive.</summary>
function WithoutParameters(const ASignature: string): string;
var
  mDepth, mPosition: Integer;
begin
  Result := '';
  mDepth := 0;
  for mPosition := 1 to Length(ASignature) do
  begin
    if ASignature[mPosition] = '(' then
    begin
      Inc(mDepth);
    end
    else if ASignature[mPosition] = ')' then
    begin
      Dec(mDepth);
    end
    else if mDepth = 0 then
    begin
      Result := Result + ASignature[mPosition];
    end;
  end;
end;

class function TInheritedAbstractCallRule.IsAbstractSignature(const ASignature: string): Boolean;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  mParts := WithoutParameters(ASignature).Split([';']);
  // Der erste Teil ist der Kopf selbst, die Direktiven folgen hinter Semikolons.
  Result := False;
  for mIndex := 1 to High(mParts) do
  begin
    Result := Result or SameText(Trim(mParts[mIndex]), 'abstract');
  end;
end;

procedure TInheritedAbstractCallRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TInheritedAbstractCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mCheck := TInheritedAbstractCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

/// <summary>Anweisung, die nur aus dem inherited-Aufruf AExpr besteht und in einem begin…end steht; sonst nil.
/// </summary>
function OwnStatement(AExpr: TSyntaxNode): TSyntaxNode;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  mNode := AExpr.Parent;
  if (mNode <> nil) and (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount > 0) and (mNode[0] = AExpr) then
  begin
    mNode := mNode.Parent;
  end;
  if (mNode <> nil) and (mNode.Kind = TSyntaxKind.CallStatement) and (mNode.Parent <> nil) and
    (mNode.Parent.Kind = TSyntaxKind.Block) then
  begin
    Result := mNode;
  end;
end;

/// <summary>Jede passende Überladung ist abstrakt; sonst wählt der Compiler womöglich eine andere.</summary>
function AllAbstract(const ACandidates: TArray<TResolvedSymbol>): Boolean;
var
  mCandidate: TResolvedSymbol;
begin
  Result := ACandidates <> nil;
  for mCandidate in ACandidates do
  begin
    Result := Result and (mCandidate.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and
      (mCandidate.Condition = '') and TInheritedAbstractCallRule.IsAbstractSignature(mCandidate.Signature);
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
  mCalls: TDictionary<Integer, TSyntaxNode>;
begin
  mCalls := FCalls;
  FContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.InheritedExpr) and (ANode.Name <> '') then
      begin
        mCalls.AddOrSetValue(ANode.StartOffset, ANode);
      end;
      Result := True;
    end);
end;

procedure TInheritedAbstractCheck.CheckCall(AExpr: TSyntaxNode; ANameToken: Integer);
var
  mCandidates: TArray<TResolvedSymbol>;
  mStatement: TSyntaxNode;
  mFixes: TArray<TRuleFix>;
begin
  mCandidates := FResolver.ResolveAll(FContext.Tree, FFileName, FTokens[ANameToken].StartPos);
  if not AllAbstract(mCandidates) then
  begin
    Exit;
  end;
  mFixes := nil;
  mStatement := OwnStatement(AExpr);
  if mStatement <> nil then
  begin
    mFixes := [RemoveStatementFix(FCache, FContext, mStatement, cTexts[TInheritanceAbstractText.RemoveCall].Text)];
  end;
  FReport.Add(TTextRange.Create(AExpr.StartPos, AExpr.EndPos),
    cTexts[TInheritanceAbstractText.InheritedAbstract].Fmt([mCandidates[0].Container, mCandidates[0].Name]),
    TRuleConfidence.High, mFixes);
end;

procedure TInheritedAbstractCheck.CheckCalls;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
begin
  for mIndex := 0 to High(FTokens) - 1 do
  begin
    if FCalls.TryGetValue(FTokens[mIndex].Offset, mNode) and
      (FTokens[mIndex + 1].Kind = TPascalTokenKind.Identifier) then
    begin
      CheckCall(mNode, mIndex + 1);
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inheritance.Abstract', cTexts);

end.
