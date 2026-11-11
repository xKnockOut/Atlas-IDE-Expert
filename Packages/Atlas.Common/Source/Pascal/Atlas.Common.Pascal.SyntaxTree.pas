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
//; Läufer sollen Walk nutzen statt eigener Rekursion.

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

  /// <summary>Eintrag eines eigenen Stapels für Läufe, die einen Knoten nach seinen Kindern prüfen
  /// (Post-Order): Done = die Kinder sind schon durchlaufen.</summary>
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
    // Ebenso in den Auffüllbytes.
    FDescending: Boolean;
    FName: string;
    FParent: TSyntaxNode;
    FChildren: TObjectList<TSyntaxNode>;
    FStartPos: TTextPosition;
    FEndPos: TTextPosition;
    FStartOffset: Integer;
    FEndOffset: Integer;
    function GetChild(AIndex: Integer): TSyntaxNode;
    function GetChildCount: Integer;
    /// <summary>Legt alle Kinder auf APending und löst sie vom Knoten, ohne sie freizugeben.</summary>
    procedure DetachChildren(APending: TStack<TSyntaxNode>);
  public
    constructor Create(AKind: TSyntaxKind);
    destructor Destroy; override;
    /// <summary>Hängt ANode als letztes Kind an und übernimmt es.</summary>
    procedure Add(ANode: TSyntaxNode);
    /// <summary>Nimmt ANode aus den Kindern, ohne es freizugeben.</summary>
    procedure Extract(ANode: TSyntaxNode);
    /// <summary>Erstes Kind der Art, sonst nil.</summary>
    function FindChild(AKind: TSyntaxKind): TSyntaxNode;
    /// <summary>Routinenkopf einer Methodenzuordnung "procedure IFoo.Bar = MyBar;" (#849): kein eigenes
    /// Mitglied; das Ziel steht als Identifier unter der Direktive "resolution".</summary>
    function IsMethodResolution: Boolean;
    /// <summary>Ziel einer Methodenzuordnung (MyBar bei "procedure IFoo.Bar = MyBar;"); '' sonst oder ohne Ziel.
    /// </summary>
    function ResolutionTarget: string;
    /// <summary>Qualifizierter Name der Typdeklarationen über diesem Knoten (TAussen.TInnen), Self
    /// eingeschlossen; '' außerhalb eines Typs.</summary>
    function EnclosingTypeName: string;
    /// <summary>Setzt den Bereich im Quelltext.</summary>
    procedure SetRange(const AStartPos, AEndPos: TTextPosition; AStartOffset, AEndOffset: Integer);
    /// <summary>Besucht diesen Knoten und, wenn AVisit True liefert, alle Kinder in Baumreihenfolge
    ///. Iterativ: auch für sehr tiefe Bäume ohne Stapelbedarf.</summary>
    procedure Walk(const AVisit: TSyntaxNodeVisit);
    /// <summary>Wie Walk, hört aber beim ersten Knoten auf, für den AVisit Found liefert, und gibt ihn zurück;
    /// nil ohne Treffer. Iterativ wie Walk.</summary>
    function Search(const AVisit: TSyntaxNodeSearch): TSyntaxNode;
    property Kind: TSyntaxKind read FKind write FKind;
    /// <summary>Nur bei Parameter: const, var, out oder constref.</summary>
    property Modifier: TParameterModifier read FModifier write FModifier;
    /// <summary>Nur bei ForStatement: downto statt to.</summary>
    property Descending: Boolean read FDescending write FDescending;
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

  /// <summary>Syntaxfehler. Message endet mit „(wie Code).“, wenn der Compiler denselben Fehler meldet
  /// (#1022).</summary>
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
    FPlatform: string;
    // 0 = noch nicht bestimmt.
    FDepth: Integer;
    FDeepest: TSyntaxNode;
    /// <summary>Abgeleitete Daten anderer Schichten (Derived); unter System.TMonitor(Self).</summary>
    FDerived: IInterface;
    procedure Measure;
  public
    constructor Create(ARoot: TSyntaxNode; const ATokens: TArray<TPascalToken>;
      const ADiagnostics: TArray<TSyntaxDiagnostic>);
    destructor Destroy; override;
    /// <summary>Größte Zahl von Knoten auf einem Weg von der Wurzel zu einem Blatt (Wurzel allein = 1).
    /// Iterativ bestimmt und gemerkt; auch für sehr tiefe Bäume sicher.</summary>
    function Depth: Integer;
    /// <summary>Der erste Knoten in Baumreihenfolge, der so tief liegt wie Depth; nil ohne Wurzel. Bei einer
    /// langen Kette wie 1 - 1 - … - 1 ist das ihr erstes Glied.</summary>
    function Deepest: TSyntaxNode;
    /// <summary>Steht das Token ATokenIndex in einem Steuerzeichen wie ^C (#862)? Dann ist der Bezeichner C
    /// kein Name, sondern Teil eines Literals.</summary>
    function IsControlCharPart(ATokenIndex: Integer): Boolean;
    /// <summary>Erstes Token mit Offset >= AOffset, binär gesucht; Length(Tokens), wenn es keines gibt.</summary>
    function FirstTokenFrom(AOffset: Integer): Integer;
    /// <summary>Erstes Token in ATokens (nach Offset sortiert, z. B. Tokens oder nur die Code-Token) mit
    /// Offset >= AOffset, binär gesucht; Length(ATokens), wenn es keines gibt (#1342).</summary>
    class function FirstTokenOf(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer; static;
    /// <summary>Bezeichner, auf dem APosition steht oder direkt hinter dem sie steht (Cursor am Wortende); -1 ohne
    /// Bezeichner und für C in ^C (#862). Binär gesucht (#1323).</summary>
    function IdentifierAt(const APosition: TTextPosition): Integer;
    /// <summary>Einmal je Baum abgeleitete Daten, etwa die extrahierte Unit der Namensauflösung (#1761): Der erste
    /// Aufruf legt sie mit AFactory an, alle weiteren teilen sie; sie leben so lange wie der Baum. Threadsicher.
    /// Vorher extrahierte jeder Anbieter einer Code-Aktion die ganze Unit neu.</summary>
    function Derived(const AFactory: TFunc<IInterface>): IInterface;
    property Root: TSyntaxNode read FRoot;
    /// <summary>Alle Token einschließlich Kommentaren und Direktiven.</summary>
    property Tokens: TArray<TPascalToken> read FTokens;
    property Diagnostics: TArray<TSyntaxDiagnostic> read FDiagnostics;
    /// <summary>Zielplattform, für die der Baum gelesen wurde ("Win32", "Win64" …, #1380); setzt
    /// ParseActive des Parsers aus den Symbolen. '' = unbekannt (Parse ohne Symbole, Baum aller Zweige):
    /// Regeln, die nur auf einer Plattform gelten, schweigen dann.</summary>
    property Platform: string read FPlatform write FPlatform;
  end;

/// <summary>Name einer Knotenart, z. B. für Tests und Protokolle.</summary>
function SyntaxKindName(AKind: TSyntaxKind): string;

implementation

uses
  System.TypInfo,
  Atlas.Common.Pascal.TokenCursor;

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

procedure TSyntaxNode.DetachChildren(APending: TStack<TSyntaxNode>);
var
  mIndex: Integer;
begin
  if FChildren = nil then
  begin
    Exit;
  end;
  FChildren.OwnsObjects := False;
  for mIndex := 0 to FChildren.Count - 1 do
  begin
    APending.Push(FChildren[mIndex]);
  end;
  FChildren.Clear;
end;

destructor TSyntaxNode.Destroy;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  // Iterativ statt rekursiv: Lange Ketten wie 1+1+...+1 ergeben sehr tiefe
  // Bäume, die rekursiv den Stapel sprengen würden.
  if (FChildren <> nil) and (FChildren.Count > 0) then
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      DetachChildren(mPending);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mNode.DetachChildren(mPending);
        mNode.Free;
      end;
    finally
      mPending.Free;
    end;
  end;
  FChildren.Free;
  inherited;
end;

procedure TSyntaxNode.Add(ANode: TSyntaxNode);
begin
  if FChildren = nil then
  begin
    FChildren := TObjectList<TSyntaxNode>.Create(True);
  end;
  ANode.FParent := Self;
  FChildren.Add(ANode);
end;

procedure TSyntaxNode.Extract(ANode: TSyntaxNode);
begin
  if FChildren <> nil then
  begin
    FChildren.Extract(ANode);
  end;
  ANode.FParent := nil;
end;

function TSyntaxNode.FindChild(AKind: TSyntaxKind): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ChildCount - 1 do
  begin
    if Children[mIndex].Kind = AKind then
    begin
      Exit(Children[mIndex]);
    end;
  end;
  Result := nil;
end;

function TSyntaxNode.IsMethodResolution: Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ChildCount - 1 do
  begin
    if (Children[mIndex].Kind = TSyntaxKind.Directive) and (Children[mIndex].Name = 'resolution') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSyntaxNode.ResolutionTarget: string;
var
  mIndex: Integer;
  mClause: TSyntaxNode;
begin
  for mIndex := 0 to ChildCount - 1 do
  begin
    mClause := Children[mIndex];
    if (mClause.Kind = TSyntaxKind.Directive) and (mClause.Name = 'resolution') then
    begin
      if (mClause.ChildCount > 0) and (mClause[0].Kind = TSyntaxKind.Identifier) then
      begin
        Exit(mClause[0].Name);
      end;
      Break;
    end;
  end;
  Result := '';
end;

function TSyntaxNode.EnclosingTypeName: string;
var
  mNode: TSyntaxNode;
begin
  Result := '';
  mNode := Self;
  while mNode <> nil do
  begin
    if mNode.Kind = TSyntaxKind.TypeDecl then
    begin
      if Result = '' then
      begin
        Result := mNode.Name;
      end
      else
      begin
        Result := mNode.Name + '.' + Result;
      end;
    end;
    mNode := mNode.Parent;
  end;
end;

function TSyntaxNode.GetChild(AIndex: Integer): TSyntaxNode;
begin
  Result := FChildren[AIndex];
end;

function TSyntaxNode.GetChildCount: Integer;
begin
  if FChildren = nil then
  begin
    Result := 0;
  end
  else
  begin
    Result := FChildren.Count;
  end;
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
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  case AVisit(Self) of
    TSyntaxSearchStep.Found:
      Exit(Self);
    TSyntaxSearchStep.Skip:
      Exit;
  end;
  if ChildCount = 0 then
  begin
    Exit;
  end;
  mPending := TStack<TSyntaxNode>.Create;
  try
    for mIndex := ChildCount - 1 downto 0 do
    begin
      mPending.Push(Children[mIndex]);
    end;
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      case AVisit(mNode) of
        TSyntaxSearchStep.Found:
          Exit(mNode);
        TSyntaxSearchStep.Descend:
          for mIndex := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode.Children[mIndex]);
          end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TSyntaxNode.Walk(const AVisit: TSyntaxNodeVisit);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht): Ketten wie 1 - 1 - … - 1 ergeben Bäume, die so tief sind wie die Kette lang; rekursiv
  // kostete jede Ebene einen Stapelrahmen je Läufer. Die Kinder kommen in umgekehrter Reihenfolge auf den Stapel,
  // damit die Reihenfolge der Besuche die der Rekursion bleibt.
  if not AVisit(Self) or (ChildCount = 0) then
  begin
    Exit;
  end;
  mPending := TStack<TSyntaxNode>.Create;
  try
    for mIndex := ChildCount - 1 downto 0 do
    begin
      mPending.Push(Children[mIndex]);
    end;
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if not AVisit(mNode) then
      begin
        Continue;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode.Children[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

{ TSyntaxTree }

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
  begin
    Result := A.Line - B.Line;
  end
  else
  begin
    Result := A.Character - B.Character;
  end;
end;

function TSyntaxTree.FirstTokenFrom(AOffset: Integer): Integer;
begin
  Result := FirstTokenOf(FTokens, AOffset);
end;

class function TSyntaxTree.FirstTokenOf(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
begin
  Result := TokenFrom(ATokens, AOffset);
end;

function TSyntaxTree.IdentifierAt(const APosition: TTextPosition): Integer;
var
  mLow, mHigh, mMiddle: Integer;
begin
  // Die Token folgen ohne Überlappung aufeinander, ihre Enden steigen also mit: Vor dem ersten Token, das nicht vor
  // APosition endet, berührt keines APosition. Früher lief die Suche ab Dateianfang und kopierte jedes Token, und
  // Regeln, die für jedes Element großer Konstanten-Arrays fragen, wurden quadratisch (#1323).
  mLow := 0;
  mHigh := Length(FTokens);
  while mLow < mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if ComparePositions(FTokens[mMiddle].EndPos, APosition) < 0 then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
  // Höchstens zwei Kandidaten: das Token, das vor APosition endet, und das, das dort beginnt; der frühere gewinnt.
  while (mLow <= High(FTokens)) and (ComparePositions(FTokens[mLow].StartPos, APosition) <= 0) do
  begin
    if FTokens[mLow].Kind = TPascalTokenKind.Identifier then
    begin
      if IsControlCharPart(mLow) then
      begin
        Exit(-1);
      end;
      Exit(mLow);
    end;
    Inc(mLow);
  end;
  Result := -1;
end;

function TSyntaxTree.IsControlCharPart(ATokenIndex: Integer): Boolean;
var
  mNode: TSyntaxNode;
  mOffset, mIndex: Integer;
  mFound: Boolean;
begin
  Result := False;
  if (ATokenIndex < 1) or (ATokenIndex > High(FTokens)) or not FTokens[ATokenIndex - 1].IsSymbol('^') or
    (FTokens[ATokenIndex].Offset <> FTokens[ATokenIndex - 1].Offset + 1) then
  begin
    Exit;
  end;
  // Innerster Knoten über dem Token: ein Literal nur bei ^C, ein Zeigertyp ^T bleibt TypeReference.
  mOffset := FTokens[ATokenIndex].Offset;
  mNode := FRoot;
  repeat
    if mNode.Kind = TSyntaxKind.Literal then
    begin
      Exit(True);
    end;
    mFound := False;
    for mIndex := 0 to mNode.ChildCount - 1 do
    begin
      if (mNode[mIndex].StartOffset <= mOffset) and (mOffset < mNode[mIndex].EndOffset) then
      begin
        mNode := mNode[mIndex];
        mFound := True;
        Break;
      end;
    end;
  until not mFound;
end;

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
  FDerived := nil;
  FRoot.Free;
  inherited;
end;

function TSyntaxTree.Derived(const AFactory: TFunc<IInterface>): IInterface;
begin
  System.TMonitor.Enter(Self);
  try
    if FDerived = nil then
    begin
      FDerived := AFactory();
    end;
    Result := FDerived;
  finally
    System.TMonitor.Exit(Self);
  end;
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
  mPending: TStack<TDepthEntry>;
  mItem: TDepthEntry;
  mIndex, mFound: Integer;
  mBottom: TSyntaxNode;
begin
  mFound := 0;
  mBottom := nil;
  mPending := TStack<TDepthEntry>.Create;
  try
    mPending.Push(DepthEntry(FRoot, 1));
    while mPending.Count > 0 do
    begin
      mItem := mPending.Pop;
      if mItem.Depth > mFound then
      begin
        mFound := mItem.Depth;
        mBottom := mItem.Node;
      end;
      // Rückwärts auf den Stapel: Bei gleicher Tiefe gewinnt der erste Knoten in Baumreihenfolge.
      for mIndex := mItem.Node.ChildCount - 1 downto 0 do
      begin
        mPending.Push(DepthEntry(mItem.Node[mIndex], mItem.Depth + 1));
      end;
    end;
  finally
    mPending.Free;
  end;
  // Gleichzeitige Aufrufe aus mehreren Threads rechnen dieselben Werte; das Merken ist unkritisch. FDepth zuletzt,
  // weil es anzeigt, dass gemessen ist.
  FDeepest := mBottom;
  FDepth := mFound;
end;

function TSyntaxTree.Depth: Integer;
begin
  if (FDepth = 0) and (FRoot <> nil) then
  begin
    Measure;
  end;
  Result := FDepth;
end;

function TSyntaxTree.Deepest: TSyntaxNode;
begin
  if (FDepth = 0) and (FRoot <> nil) then
  begin
    Measure;
  end;
  Result := FDeepest;
end;

end.
