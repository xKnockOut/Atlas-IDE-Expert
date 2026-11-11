unit Atlas.Common.Rules.Derived;

// Ableitungscache einer Prüfung: Index der Datei, Routinen,
// Signaturen, Kontrollflussgraphen, Code-Token und Zeilentabelle werden je
// Lauf einmal berechnet und von allen Regeln geteilt. Die Engine legt den
// Cache an; ruft jemand Check direkt auf, liefert Open einen eigenen, der mit
// der Interface-Variablen der Regel endet.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Cache eines Laufs; besitzt die abgelegten Objekte.</summary>
  TRuleDerivedCache = class(TInterfacedObject, IRuleDerivedCache)
  private
    FValues: TObjectDictionary<string, TObject>;
  public
    constructor Create;
    destructor Destroy; override;
    function TryGet(const AKey: string; out AValue: TObject): Boolean;
    procedure Put(const AKey: string; AValue: TObject);
    procedure Clear;
  end;

  /// <summary>Hülle für Werte ohne eigenes Objekt (Records, Arrays, Methodenreferenzen, Interfaces).</summary>
  TRuleDerivedValue<T> = class
  public
    Value: T;
    constructor Create(const AValue: T);
  end;

  /// <summary>Typisierte Zugriffe auf den Ableitungscache.</summary>
  TRuleDerived = class
  public
    /// <summary>Cache des Laufs, sonst ein neuer nur für den Aufrufer. Ergebnis in einer lokalen
    /// Interface-Variablen halten, solange abgeleitete Objekte benutzt werden.</summary>
    class function Open(const AContext: TRuleContext): IRuleDerivedCache; static;
    /// <summary>Objekt unter AKey; beim ersten Zugriff aus AFactory. Der Cache besitzt es.</summary>
    class function Get<T: class>(const ACache: IRuleDerivedCache; const AKey: string;
      const AFactory: TFunc<T>): T; static;
    /// <summary>TIndexExtractor.Extract(Tree, '') einmal je Lauf; leer ohne Baum.</summary>
    class function UnitIndex(const ACache: IRuleDerivedCache; const AContext: TRuleContext): TUnitIndex; static;
    /// <summary>Namensauflöser für alle Regeln des Laufs: Seine Antworten zu Units, Vorfahren und Helfern
    /// gelten für die ganze Datei, statt dass jede Regel sie neu sucht. Gehört dem Cache, nie freigeben.
    /// PinTree/UnpinTree paarweise wie bei einem eigenen; NameFilter nach Gebrauch zurücksetzen. Wer
    /// gleichzeitig einen zweiten Resolver braucht (ResolveNameFrom setzt den Zustand zurück), legt den
    /// zweiten selbst an.</summary>
    class function Resolver(const ACache: IRuleDerivedCache; const AContext: TRuleContext): TNameResolver; static;
    /// <summary>Alle RoutineDecl mit Rumpf, auch lokale, in Baumreihenfolge.</summary>
    class function Routines(const ACache: IRuleDerivedCache; const AContext: TRuleContext): TArray<TSyntaxNode>; static;
    /// <summary>TFlowSignatures.FromTree der Datei; nil ohne Baum.</summary>
    class function FlowSignatures(const ACache: IRuleDerivedCache;
      const AContext: TRuleContext): TFlowSignatureLookup; static;
    /// <summary>Kontrollflussgraph der Routine mit FlowSignatures; gehört dem Cache, nie freigeben.</summary>
    class function Graph(const ACache: IRuleDerivedCache; const AContext: TRuleContext;
      ARoutine: TSyntaxNode): TControlFlowGraph; static;
    /// <summary>Token ohne Kommentare und Direktiven.</summary>
    class function CodeTokens(const ACache: IRuleDerivedCache;
      const AContext: TRuleContext): TArray<TPascalToken>; static;
    /// <summary>Zeile/Zeichen zu einem Offset ab 0 über die Zeilentabelle von TTextDocument
    /// (binäre Suche; CR, LF und CRLF sind Zeilenenden).</summary>
    class function PositionAt(const ACache: IRuleDerivedCache; const AContext: TRuleContext;
      AOffset: Integer): TTextPosition; static;
    /// <summary>Bereich [AStart, AEnd) als Zeilen/Zeichen.</summary>
    class function OffsetRange(const ACache: IRuleDerivedCache; const AContext: TRuleContext;
      AStart, AEnd: Integer): TTextRange; static;
  end;

implementation

uses
  Atlas.Common.Documents.TextDocument,
  Atlas.Common.Index.Extractor;

const
  cKeyUnitIndex = 'rules.unitIndex';
  cKeyRoutines = 'rules.routines';
  cKeyFlowSignatures = 'rules.flowSignatures';
  cKeyGraph = 'rules.graph:';
  cKeyCodeTokens = 'rules.codeTokens';
  cKeyLines = 'rules.lines';
  cKeyResolver = 'rules.resolver';

{ TRuleDerivedCache }

constructor TRuleDerivedCache.Create;
begin
  inherited Create;
  FValues := TObjectDictionary<string, TObject>.Create([doOwnsValues]);
end;

destructor TRuleDerivedCache.Destroy;
begin
  FValues.Free;
  inherited Destroy;
end;

function TRuleDerivedCache.TryGet(const AKey: string; out AValue: TObject): Boolean;
begin
  Result := FValues.TryGetValue(AKey, AValue);
end;

procedure TRuleDerivedCache.Put(const AKey: string; AValue: TObject);
begin
  // doOwnsValues gibt einen ersetzten Wert frei.
  FValues.AddOrSetValue(AKey, AValue);
end;

procedure TRuleDerivedCache.Clear;
begin
  FValues.Clear;
end;

{ TRuleDerivedValue<T> }

constructor TRuleDerivedValue<T>.Create(const AValue: T);
begin
  inherited Create;
  Value := AValue;
end;

{ TRuleDerived }

class function TRuleDerived.Open(const AContext: TRuleContext): IRuleDerivedCache;
begin
  Result := AContext.Derived;
  if Result = nil then
  begin
    Result := TRuleDerivedCache.Create;
  end;
end;

class function TRuleDerived.Get<T>(const ACache: IRuleDerivedCache; const AKey: string;
  const AFactory: TFunc<T>): T;
var
  mValue: TObject;
begin
  if ACache.TryGet(AKey, mValue) then
  begin
    Exit(T(mValue));
  end;
  Result := AFactory();
  ACache.Put(AKey, Result);
end;

class function TRuleDerived.UnitIndex(const ACache: IRuleDerivedCache; const AContext: TRuleContext): TUnitIndex;
var
  mValue: TObject;
  mIndex: TUnitIndex;
begin
  if ACache.TryGet(cKeyUnitIndex, mValue) then
  begin
    Exit(TRuleDerivedValue<TUnitIndex>(mValue).Value);
  end;
  mIndex := Default(TUnitIndex);
  if AContext.Tree <> nil then
  begin
    mIndex := TIndexExtractor.Extract(AContext.Tree, '');
  end;
  ACache.Put(cKeyUnitIndex, TRuleDerivedValue<TUnitIndex>.Create(mIndex));
  Result := mIndex;
end;

class function TRuleDerived.Resolver(const ACache: IRuleDerivedCache; const AContext: TRuleContext): TNameResolver;
var
  mValue: TObject;
begin
  if ACache.TryGet(cKeyResolver, mValue) then
  begin
    Exit(TNameResolver(mValue));
  end;
  Result := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
  Result.Namespaces := AContext.Namespaces;
  ACache.Put(cKeyResolver, Result);
end;

class function TRuleDerived.Routines(const ACache: IRuleDerivedCache;
  const AContext: TRuleContext): TArray<TSyntaxNode>;
var
  mValue: TObject;
  mFound: TList<TSyntaxNode>;
begin
  if ACache.TryGet(cKeyRoutines, mValue) then
  begin
    Exit(TRuleDerivedValue<TArray<TSyntaxNode>>(mValue).Value);
  end;
  Result := nil;
  if AContext.Tree <> nil then
  begin
    mFound := TList<TSyntaxNode>.Create;
    try
      AContext.Tree.Root.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.Block) <> nil) then
          begin
            mFound.Add(ANode);
          end;
          Result := True;
        end);
      Result := mFound.ToArray;
    finally
      mFound.Free;
    end;
  end;
  ACache.Put(cKeyRoutines, TRuleDerivedValue<TArray<TSyntaxNode>>.Create(Result));
end;

class function TRuleDerived.FlowSignatures(const ACache: IRuleDerivedCache;
  const AContext: TRuleContext): TFlowSignatureLookup;
var
  mValue: TObject;
begin
  if ACache.TryGet(cKeyFlowSignatures, mValue) then
  begin
    Exit(TRuleDerivedValue<TFlowSignatureLookup>(mValue).Value);
  end;
  Result := nil;
  if AContext.Tree <> nil then
  begin
    Result := TFlowSignatures.FromTree(AContext.Tree.Root);
  end;
  ACache.Put(cKeyFlowSignatures, TRuleDerivedValue<TFlowSignatureLookup>.Create(Result));
end;

class function TRuleDerived.Graph(const ACache: IRuleDerivedCache; const AContext: TRuleContext;
  ARoutine: TSyntaxNode): TControlFlowGraph;
var
  mKey: string;
  mValue: TObject;
  mLookup: TFlowSignatureLookup;
begin
  mKey := cKeyGraph + IntToStr(ARoutine.StartOffset);
  if ACache.TryGet(mKey, mValue) then
  begin
    Exit(TControlFlowGraph(mValue));
  end;
  mLookup := FlowSignatures(ACache, AContext);
  Result := TControlFlowGraph.Build(ARoutine, mLookup);
  ACache.Put(mKey, Result);
end;

class function TRuleDerived.CodeTokens(const ACache: IRuleDerivedCache;
  const AContext: TRuleContext): TArray<TPascalToken>;
var
  mValue: TObject;
  mTokens: TArray<TPascalToken>;
  mToken: TPascalToken;
  mCount: Integer;
begin
  if ACache.TryGet(cKeyCodeTokens, mValue) then
  begin
    Exit(TRuleDerivedValue<TArray<TPascalToken>>(mValue).Value);
  end;
  Result := nil;
  if AContext.Tree <> nil then
  begin
    mTokens := AContext.Tree.Tokens;
    SetLength(Result, Length(mTokens));
    mCount := 0;
    for mToken in mTokens do
    begin
      if not (mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      begin
        Result[mCount] := mToken;
        Inc(mCount);
      end;
    end;
    SetLength(Result, mCount);
  end;
  ACache.Put(cKeyCodeTokens, TRuleDerivedValue<TArray<TPascalToken>>.Create(Result));
end;

class function TRuleDerived.PositionAt(const ACache: IRuleDerivedCache; const AContext: TRuleContext;
  AOffset: Integer): TTextPosition;
var
  mValue: TObject;
  mLines: ITextDocument;
begin
  if ACache.TryGet(cKeyLines, mValue) then
  begin
    mLines := TRuleDerivedValue<ITextDocument>(mValue).Value;
  end
  else
  begin
    mLines := TTextDocument.Create('', 'objectpascal', 0, AContext.Text);
    ACache.Put(cKeyLines, TRuleDerivedValue<ITextDocument>.Create(mLines));
  end;
  Result := mLines.PositionAt(AOffset);
end;

class function TRuleDerived.OffsetRange(const ACache: IRuleDerivedCache; const AContext: TRuleContext;
  AStart, AEnd: Integer): TTextRange;
begin
  Result := TTextRange.Create(PositionAt(ACache, AContext, AStart), PositionAt(ACache, AContext, AEnd));
end;

end.
