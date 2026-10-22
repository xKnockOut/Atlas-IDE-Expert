unit Atlas.Common.Pascal.SyntaxTree;

// Syntaxbaum des Parsers. Jeder Knoten kennt Art, Namen (bei Deklarationen,
// Bezeichnern und Literalen), Bereich im Quelltext und seine Kinder.
// Der Baum ist auch für fehlerhaften Code vollständig; übersprungene Token
// stehen in Knoten der Art Error, Fehler in Diagnostics.
// Parameter tragen ihren Modifizierer (const, var, out, constref) in
// Modifier; die Datenflussanalyse braucht ihn für Aufrufe (#143).
// Depth liefert die größte Tiefe des Baums; rekursive Auswertungen wie die
// Prüfregeln prüfen damit, ob der Stapel reicht (#1094). Walk, Depth und das
// Freigeben laufen iterativ und brauchen auch bei tiefen Bäumen keinen Stapel
// (Bericht M1); Läufer sollen Walk nutzen statt eigener Rekursion.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  TSyntaxKind = (
    // Datei und Abschnitte
    UnitFile, ProgramFile, LibraryFile, PackageFile,
    InterfaceSection, ImplementationSection, InitializationSection, FinalizationSection,
    UsesClause, UsedUnit,
    // Deklarationsabschnitte
    TypeSection, TypeDecl, ConstSection, ConstDecl, VarSection, VarDecl, LabelSection, ExportsClause,
    GenericParams, Attribute,
    // Typen
    ClassType, ObjectType, RecordType, InterfaceType, HelperType, ClassOfType, ForwardType,
    EnumType, SetType, ArrayType, PointerType, ProcedureType, FileType, SubrangeType, TypeReference,
    VariantPart,
    // Mitglieder
    Visibility, Field, PropertyDecl, RoutineHeader,
    // Routinen
    RoutineDecl, Parameters, Parameter, Directive,
    // Anweisungen
    Block, AsmBlock, AssignStatement, CallStatement, IfStatement, CaseStatement, CaseItem, CaseElse,
    ForStatement, ForInStatement, WhileStatement, RepeatStatement, WithStatement,
    TryStatement, ExceptBlock, ExceptionHandler, FinallyBlock, RaiseStatement, GotoStatement,
    LabeledStatement, InlineVar, InlineConst, EmptyStatement,
    // Ausdrücke
    Identifier, Literal, MemberAccess, Call, IndexAccess, Dereference, AddressOf, GenericArgs,
    SetConstructor, BinaryExpr, UnaryExpr, ParenExpr, InheritedExpr, AnonymousMethod, RangeExpr,
    /// <summary>Bedingter Ausdruck if A then B else C (ab Delphi 13).</summary>
    IfExpr,
    // Fehlerbehandlung
    Error);

  /// <summary>Modifizierer eines Parameters; None ohne Angabe (Wertparameter).</summary>
  TParameterModifier = (None, ConstParam, VarParam, OutParam, ConstRefParam);

  TSyntaxNode = class;

  /// <summary>Besuch eines Knotens für TSyntaxNode.Walk; False = Kinder nicht besuchen.</summary>
  TSyntaxNodeVisit = reference to function(ANode: TSyntaxNode): Boolean;

  /// <summary>Antwort eines Besuchs in TSyntaxNode.Search: in die Kinder gehen, sie auslassen oder mit diesem
  /// Knoten als Treffer aufhören.</summary>
  TSyntaxSearchStep = (Descend, Skip, Found);

  /// <summary>Besuch eines Knotens für TSyntaxNode.Search.</summary>
  TSyntaxNodeSearch = reference to function(ANode: TSyntaxNode): TSyntaxSearchStep;

  /// <summary>Eintrag eines eigenen Stapels für Läufe, die einen Knoten nach seinen Kindern prüfen (Post-Order,
  /// Bericht M1): Done = die Kinder sind schon durchlaufen.</summary>
  TSyntaxPostOrderEntry = record
    Node: TSyntaxNode;
    Done: Boolean;
    class function Create(ANode: TSyntaxNode; ADone: Boolean): TSyntaxPostOrderEntry; static;
  end;

  TSyntaxNode = class
  private
    FKind: TSyntaxKind;
    // Steht hinter FKind in dessen Auffüllbytes und vergrößert den Knoten nicht.
    FModifier: TParameterModifier;
    FName: string;
    FParent: TSyntaxNode;
    FChildren: TObjectList<TSyntaxNode>;
    FStartPos: TTextPosition;
    FEndPos: TTextPosition;
    FStartOffset: Integer;
    FEndOffset: Integer;
    function GetChild(AIndex: Integer): TSyntaxNode;
    function GetChildCount: Integer;
  public
    constructor Create(AKind: TSyntaxKind);
    destructor Destroy; override;
    /// <summary>Hängt ANode als letztes Kind an und übernimmt es.</summary>
    procedure Add(ANode: TSyntaxNode);
    /// <summary>Nimmt ANode aus den Kindern, ohne es freizugeben.</summary>
    procedure Extract(ANode: TSyntaxNode);
    /// <summary>Erstes Kind der Art, sonst nil.</summary>
    function FindChild(AKind: TSyntaxKind): TSyntaxNode;
    /// <summary>Setzt den Bereich im Quelltext.</summary>
    procedure SetRange(const AStartPos, AEndPos: TTextPosition; AStartOffset, AEndOffset: Integer);
    /// <summary>Besucht diesen Knoten und, wenn AVisit True liefert, alle Kinder in Baumreihenfolge
    /// (Review P-03). Iterativ: auch für sehr tiefe Bäume ohne Stapelbedarf (Bericht M1).</summary>
    procedure Walk(const AVisit: TSyntaxNodeVisit);
    /// <summary>Wie Walk, hört aber beim ersten Knoten auf, für den AVisit Found liefert, und gibt ihn zurück;
    /// nil ohne Treffer. Iterativ wie Walk (Bericht M1).</summary>
    function Search(const AVisit: TSyntaxNodeSearch): TSyntaxNode;
    property Kind: TSyntaxKind read FKind write FKind;
    /// <summary>Nur bei Parameter: const, var, out oder constref.</summary>
    property Modifier: TParameterModifier read FModifier write FModifier;
    /// <summary>Name bei Deklarationen, Text bei Bezeichnern, Literalen und Operatoren.</summary>
    property Name: string read FName write FName;
    property Parent: TSyntaxNode read FParent;
    property ChildCount: Integer read GetChildCount;
    property Children[AIndex: Integer]: TSyntaxNode read GetChild; default;
    property StartPos: TTextPosition read FStartPos;
    property EndPos: TTextPosition read FEndPos;
    property StartOffset: Integer read FStartOffset;
    property EndOffset: Integer read FEndOffset;
  end;

  /// <summary>Syntaxfehler. Message endet mit „(wie Code).“, wenn der Compiler denselben Fehler meldet (#1022).</summary>
  TSyntaxDiagnostic = record
    Message: string;
    StartPos: TTextPosition;
    EndPos: TTextPosition;
    /// <summary>Code der Compilermeldung (E2029 …); '' ohne.</summary>
    Code: string;
    /// <summary>Titel der Korrektur; '' = keine.</summary>
    FixTitle: string;
    FixEdits: TArray<TTextEdit>;
    /// <summary>Korrektur ohne Rückfrage anwendbar (source.fixAll).</summary>
    FixSafe: Boolean;
    /// <summary>Meldung der Prüfungen am fertigen Baum (Pascal.SyntaxChecks): Der Baum ist an der Stelle
    /// vollständig, Regeln dürfen ihm dort trauen.</summary>
    TreeIntact: Boolean;
  end;

  /// <summary>Ergebnis des Parsers. Besitzt alle Knoten.</summary>
  TSyntaxTree = class
  private
    FRoot: TSyntaxNode;
    FTokens: TArray<TPascalToken>;
    FDiagnostics: TArray<TSyntaxDiagnostic>;
    // 0 = noch nicht bestimmt.
    FDepth: Integer;
    FDeepest: TSyntaxNode;
    procedure Measure;
  public
    constructor Create(ARoot: TSyntaxNode; const ATokens: TArray<TPascalToken>;
      const ADiagnostics: TArray<TSyntaxDiagnostic>);
    destructor Destroy; override;
    /// <summary>Größte Zahl von Knoten auf einem Weg von der Wurzel zu einem Blatt (Wurzel allein = 1).
    /// Iterativ bestimmt und gemerkt; auch für sehr tiefe Bäume sicher.</summary>
    function Depth: Integer;
    /// <summary>Der erste Knoten in Baumreihenfolge, der so tief liegt wie Depth; nil ohne Wurzel. Bei einer
    /// langen Kette wie 1 - 1 - … - 1 ist das ihr erstes Glied (Bericht M1).</summary>
    function Deepest: TSyntaxNode;
    property Root: TSyntaxNode read FRoot;
    /// <summary>Alle Token einschließlich Kommentaren und Direktiven.</summary>
    property Tokens: TArray<TPascalToken> read FTokens;
    property Diagnostics: TArray<TSyntaxDiagnostic> read FDiagnostics;
  end;

/// <summary>Name einer Knotenart, z. B. für Tests und Protokolle.</summary>
function SyntaxKindName(AKind: TSyntaxKind): string;

implementation

uses
  System.TypInfo;

function SyntaxKindName(AKind: TSyntaxKind): string;
begin
  Result := GetEnumName(TypeInfo(TSyntaxKind), Ord(AKind));
end;

{ TSyntaxPostOrderEntry }

class function TSyntaxPostOrderEntry.Create(ANode: TSyntaxNode; ADone: Boolean): TSyntaxPostOrderEntry;
begin
  Result.Node := ANode;
  Result.Done := ADone;
end;

{ TSyntaxNode }

constructor TSyntaxNode.Create(AKind: TSyntaxKind);
begin
  inherited Create;
  FKind := AKind;
end;

destructor TSyntaxNode.Destroy;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Iterativ statt rekursiv: Lange Ketten wie 1+1+...+1 ergeben sehr tiefe
  // Bäume, die rekursiv den Stapel sprengen würden.
  if (FChildren <> nil) and (FChildren.Count > 0) then
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      FChildren.OwnsObjects := False;
      for Index := 0 to FChildren.Count - 1 do
        Pending.Push(FChildren[Index]);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.FChildren <> nil then
        begin
          Node.FChildren.OwnsObjects := False;
          for Index := 0 to Node.FChildren.Count - 1 do
            Pending.Push(Node.FChildren[Index]);
          Node.FChildren.Clear;
        end;
        Node.Free;
      end;
    finally
      Pending.Free;
    end;
  end;
  FChildren.Free;
  inherited;
end;

procedure TSyntaxNode.Add(ANode: TSyntaxNode);
begin
  if FChildren = nil then
    FChildren := TObjectList<TSyntaxNode>.Create(True);
  ANode.FParent := Self;
  FChildren.Add(ANode);
end;

procedure TSyntaxNode.Extract(ANode: TSyntaxNode);
begin
  if FChildren <> nil then
    FChildren.Extract(ANode);
  ANode.FParent := nil;
end;

function TSyntaxNode.FindChild(AKind: TSyntaxKind): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ChildCount - 1 do
    if Children[Index].Kind = AKind then
      Exit(Children[Index]);
  Result := nil;
end;

function TSyntaxNode.GetChild(AIndex: Integer): TSyntaxNode;
begin
  Result := FChildren[AIndex];
end;

function TSyntaxNode.GetChildCount: Integer;
begin
  if FChildren = nil then
    Result := 0
  else
    Result := FChildren.Count;
end;

procedure TSyntaxNode.SetRange(const AStartPos, AEndPos: TTextPosition; AStartOffset, AEndOffset: Integer);
begin
  FStartPos := AStartPos;
  FEndPos := AEndPos;
  FStartOffset := AStartOffset;
  FEndOffset := AEndOffset;
end;

function TSyntaxNode.Search(const AVisit: TSyntaxNodeSearch): TSyntaxNode;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  case AVisit(Self) of
    TSyntaxSearchStep.Found:
      Exit(Self);
    TSyntaxSearchStep.Skip:
      Exit;
  end;
  if ChildCount = 0 then
    Exit;
  Pending := TStack<TSyntaxNode>.Create;
  try
    for Index := ChildCount - 1 downto 0 do
      Pending.Push(Children[Index]);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      case AVisit(Node) of
        TSyntaxSearchStep.Found:
          Exit(Node);
        TSyntaxSearchStep.Descend:
          for Index := Node.ChildCount - 1 downto 0 do
            Pending.Push(Node.Children[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

procedure TSyntaxNode.Walk(const AVisit: TSyntaxNodeVisit);
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Iterativ (Bericht M1): Ketten wie 1 - 1 - … - 1 ergeben Bäume, die so tief sind wie die Kette lang; rekursiv
  // kostete jede Ebene einen Stapelrahmen je Läufer. Die Kinder kommen in umgekehrter Reihenfolge auf den Stapel,
  // damit die Reihenfolge der Besuche die der Rekursion bleibt.
  if not AVisit(Self) or (ChildCount = 0) then
    Exit;
  Pending := TStack<TSyntaxNode>.Create;
  try
    for Index := ChildCount - 1 downto 0 do
      Pending.Push(Children[Index]);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if not AVisit(Node) then
        Continue;
      for Index := Node.ChildCount - 1 downto 0 do
        Pending.Push(Node.Children[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

{ TSyntaxTree }

constructor TSyntaxTree.Create(ARoot: TSyntaxNode; const ATokens: TArray<TPascalToken>;
  const ADiagnostics: TArray<TSyntaxDiagnostic>);
begin
  inherited Create;
  FRoot := ARoot;
  FTokens := ATokens;
  FDiagnostics := ADiagnostics;
end;

destructor TSyntaxTree.Destroy;
begin
  FRoot.Free;
  inherited;
end;

type
  TDepthEntry = record
    Node: TSyntaxNode;
    Depth: Integer;
  end;

function DepthEntry(ANode: TSyntaxNode; ADepth: Integer): TDepthEntry;
begin
  Result.Node := ANode;
  Result.Depth := ADepth;
end;

procedure TSyntaxTree.Measure;
var
  Pending: TStack<TDepthEntry>;
  Item: TDepthEntry;
  Index, Found: Integer;
  Bottom: TSyntaxNode;
begin
  Found := 0;
  Bottom := nil;
  Pending := TStack<TDepthEntry>.Create;
  try
    Pending.Push(DepthEntry(FRoot, 1));
    while Pending.Count > 0 do
    begin
      Item := Pending.Pop;
      if Item.Depth > Found then
      begin
        Found := Item.Depth;
        Bottom := Item.Node;
      end;
      // Rückwärts auf den Stapel: Bei gleicher Tiefe gewinnt der erste Knoten in Baumreihenfolge.
      for Index := Item.Node.ChildCount - 1 downto 0 do
        Pending.Push(DepthEntry(Item.Node[Index], Item.Depth + 1));
    end;
  finally
    Pending.Free;
  end;
  // Gleichzeitige Aufrufe aus mehreren Threads rechnen dieselben Werte; das Merken ist unkritisch. FDepth zuletzt,
  // weil es anzeigt, dass gemessen ist.
  FDeepest := Bottom;
  FDepth := Found;
end;

function TSyntaxTree.Depth: Integer;
begin
  if (FDepth = 0) and (FRoot <> nil) then
    Measure;
  Result := FDepth;
end;

function TSyntaxTree.Deepest: TSyntaxNode;
begin
  if (FDepth = 0) and (FRoot <> nil) then
    Measure;
  Result := FDeepest;
end;

end.
