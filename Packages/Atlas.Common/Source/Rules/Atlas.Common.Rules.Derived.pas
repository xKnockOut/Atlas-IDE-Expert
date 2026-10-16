unit Atlas.Common.Rules.Derived;

// Ableitungscache einer Prüfung (Review P-03): Index der Datei, Routinen,
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
  KeyUnitIndex = 'rules.unitIndex';
  KeyRoutines = 'rules.routines';
  KeyFlowSignatures = 'rules.flowSignatures';
  KeyGraph = 'rules.graph:';
  KeyCodeTokens = 'rules.codeTokens';
  KeyLines = 'rules.lines';

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
    Result := TRuleDerivedCache.Create;
end;

class function TRuleDerived.Get<T>(const ACache: IRuleDerivedCache; const AKey: string;
  const AFactory: TFunc<T>): T;
var
  Value: TObject;
begin
  if ACache.TryGet(AKey, Value) then
    Exit(T(Value));
  Result := AFactory();
  ACache.Put(AKey, Result);
end;

class function TRuleDerived.UnitIndex(const ACache: IRuleDerivedCache; const AContext: TRuleContext): TUnitIndex;
var
  Value: TObject;
  Index: TUnitIndex;
begin
  if ACache.TryGet(KeyUnitIndex, Value) then
    Exit(TRuleDerivedValue<TUnitIndex>(Value).Value);
  Index := Default(TUnitIndex);
  if AContext.Tree <> nil then
    Index := TIndexExtractor.Extract(AContext.Tree, '');
  ACache.Put(KeyUnitIndex, TRuleDerivedValue<TUnitIndex>.Create(Index));
  Result := Index;
end;

class function TRuleDerived.Routines(const ACache: IRuleDerivedCache; const AContext: TRuleContext): TArray<TSyntaxNode>;
var
  Value: TObject;
  Found: TList<TSyntaxNode>;
begin
  if ACache.TryGet(KeyRoutines, Value) then
    Exit(TRuleDerivedValue<TArray<TSyntaxNode>>(Value).Value);
  Result := nil;
  if AContext.Tree <> nil then
  begin
    Found := TList<TSyntaxNode>.Create;
    try
      AContext.Tree.Root.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.Block) <> nil) then
            Found.Add(ANode);
          Result := True;
        end);
      Result := Found.ToArray;
    finally
      Found.Free;
    end;
  end;
  ACache.Put(KeyRoutines, TRuleDerivedValue<TArray<TSyntaxNode>>.Create(Result));
end;

class function TRuleDerived.FlowSignatures(const ACache: IRuleDerivedCache;
  const AContext: TRuleContext): TFlowSignatureLookup;
var
  Value: TObject;
begin
  if ACache.TryGet(KeyFlowSignatures, Value) then
    Exit(TRuleDerivedValue<TFlowSignatureLookup>(Value).Value);
  Result := nil;
  if AContext.Tree <> nil then
    Result := TFlowSignatures.FromTree(AContext.Tree.Root);
  ACache.Put(KeyFlowSignatures, TRuleDerivedValue<TFlowSignatureLookup>.Create(Result));
end;

class function TRuleDerived.Graph(const ACache: IRuleDerivedCache; const AContext: TRuleContext;
  ARoutine: TSyntaxNode): TControlFlowGraph;
var
  Key: string;
  Value: TObject;
  Lookup: TFlowSignatureLookup;
begin
  Key := KeyGraph + IntToStr(ARoutine.StartOffset);
  if ACache.TryGet(Key, Value) then
    Exit(TControlFlowGraph(Value));
  Lookup := FlowSignatures(ACache, AContext);
  Result := TControlFlowGraph.Build(ARoutine, Lookup);
  ACache.Put(Key, Result);
end;

class function TRuleDerived.CodeTokens(const ACache: IRuleDerivedCache;
  const AContext: TRuleContext): TArray<TPascalToken>;
var
  Value: TObject;
  Tokens: TArray<TPascalToken>;
  Token: TPascalToken;
  Count: Integer;
begin
  if ACache.TryGet(KeyCodeTokens, Value) then
    Exit(TRuleDerivedValue<TArray<TPascalToken>>(Value).Value);
  Result := nil;
  if AContext.Tree <> nil then
  begin
    Tokens := AContext.Tree.Tokens;
    SetLength(Result, Length(Tokens));
    Count := 0;
    for Token in Tokens do
      if not (Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      begin
        Result[Count] := Token;
        Inc(Count);
      end;
    SetLength(Result, Count);
  end;
  ACache.Put(KeyCodeTokens, TRuleDerivedValue<TArray<TPascalToken>>.Create(Result));
end;

class function TRuleDerived.PositionAt(const ACache: IRuleDerivedCache; const AContext: TRuleContext;
  AOffset: Integer): TTextPosition;
var
  Value: TObject;
  Lines: ITextDocument;
begin
  if ACache.TryGet(KeyLines, Value) then
    Lines := TRuleDerivedValue<ITextDocument>(Value).Value
  else
  begin
    Lines := TTextDocument.Create('', 'objectpascal', 0, AContext.Text);
    ACache.Put(KeyLines, TRuleDerivedValue<ITextDocument>.Create(Lines));
  end;
  Result := Lines.PositionAt(AOffset);
end;

class function TRuleDerived.OffsetRange(const ACache: IRuleDerivedCache; const AContext: TRuleContext;
  AStart, AEnd: Integer): TTextRange;
begin
  Result := TTextRange.Create(PositionAt(ACache, AContext, AStart), PositionAt(ACache, AContext, AEnd));
end;

end.
