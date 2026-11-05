unit Atlas.Common.Pascal.Parser;

// Fehlertoleranter, rekursiv absteigender Parser für Object Pascal.
//
// Entscheidung (#7): eigener Parser statt DelphiAST. DelphiAST bricht bei
// Syntaxfehlern ab, bringt einen eigenen Lexer mit und hängt nicht am
// Rollenkonzept. Ein eigener Parser auf dem vorhandenen Lexer liefert auch für
// halb getippten Code einen Baum und lässt sich gezielt erweitern.
//
// Fehlerbehandlung: Fehlt ein erwartetes Token, wird eine Diagnose erzeugt und
// so weitergemacht, als wäre es da. Meldungen und Codes folgen dem Compiler
// (#1022: „';' erwartet, aber 'end' gefunden (wie E2029).“), einige mit
// Korrektur; Prüfungen, die den fertigen Baum brauchen, macht danach
// Pascal.SyntaxChecks. Unpassende Token werden in Error-Knoten
// übersprungen, bis ein Token kommt, an dem der Parser wieder aufsetzen kann.
// Jede Schleife verbraucht pro Durchlauf mindestens ein Token oder endet; der
// Parser terminiert also immer.
//
// Direktiven und Kommentare überspringt der Parser. Parse baut den Baum aus allen
// Zweigen der bedingten Kompilierung (#15). ParseActive liest nur die Token
// aktiver Zweige (#845): Zwei Rümpfe oder Köpfe je Plattform ergeben sonst einen
// kaputten Baum. Die Token der inaktiven Zweige bleiben in Tree.Tokens, Positionen
// stimmen mit dem Text überein. ActiveDiagnostics liefert die Syntaxfehler dieses
// Baums: inaktive Zweige dürfen Code eines anderen Compilers enthalten.
//
// Lange Operatorketten (#1094): a + b + c ist linksassoziativ und wird als
// ((a + b) + c) gebaut. Erzeugte Units verketten aber Tausende Strings mit +;
// der Baum wäre dann so tief wie die Kette lang, und rekursive Auswertungen
// (Prüfregeln, Index) sprengten den Stapel. Ab BalancedRunFrom rechten
// Operanden desselben assoziativen Operators (+, and, or, xor) entsteht
// deshalb A + Ausgeglichen(x1 … xn) mit Tiefe log2(n). Reihenfolge der
// Operanden und Bereiche der Knoten bleiben; kürzere Ketten und - * / div mod
// usw. bleiben linkslastig wie bisher.
// Seit Bericht M1 ist das Ausgleichen nur noch ein Netz: Prüfregeln, LSP und
// Editing laufen iterativ (TSyntaxNode.Walk, Search oder eigener Stapel) und
// vertragen auch linkslastige Ketten aus - und *. Rekursiv bleiben Läufer über
// Deklarationen und Typen, deren Tiefe MaxNesting begrenzt, und das Ausgeben
// in „Boolean umkehren“, das nur Teilausdrücken mit dem Namen folgt.
//
// Mit Dateiname und Include-Resolver in den Optionen (#860) wirken $DEFINE aus
// {$I datei.inc}; der Präprozessor-Lauf geht an den Aufrufer zurück, damit
// Abblenden und Hinweise ihn nicht wiederholen.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.SyntaxTree;

type
  TPascalParser = record
  public
    /// <summary>
    /// Parst den Text. Der Aufrufer gibt den Baum frei. Meldet ACancellation
    /// einen Abbruch, endet der Parser vorzeitig mit einem unvollständigen Baum;
    /// der Aufrufer prüft das Signal danach selbst.
    /// </summary>
    class function Parse(const AText: string; const ACancellation: IPascalCancellation): TSyntaxTree;
      overload; static;
    /// <summary>Wie oben ohne Abbruch (ACancellation = nil).</summary>
    class function Parse(const AText: string): TSyntaxTree; overload; static;
    /// <summary>
    /// Baum nur aus den aktiven Zweigen unter ADefines (leer = Vordefinitionen, siehe
    /// TPascalPreprocessor.EditorOptions; #845). AConditionals erhält die Zweige der Datei.
    /// Der Aufrufer gibt den Baum frei.
    /// </summary>
    class function ParseActive(const AText: string; const ADefines: TArray<string>;
      const ACancellation: IPascalCancellation; out AConditionals: TArray<TConditionalRange>): TSyntaxTree;
      overload; static;
    /// <summary>Wie oben, ohne Abbruch und Zweige.</summary>
    class function ParseActive(const AText: string; const ADefines: TArray<string>): TSyntaxTree; overload; static;
    /// <summary>
    /// Baum aus den aktiven Zweigen unter AOptions (TPascalPreprocessor.EditorOptions mit Dateiname und
    /// Include-Resolver, #860). AProcessed erhält den Präprozessor-Lauf; ohne bedingte Direktive und ohne
    /// auflösbares $I läuft keiner (AProcessed.Files leer). Der Aufrufer gibt den Baum frei.
    /// </summary>
    class function ParseActive(const AText: string; const AOptions: TPreprocessorOptions;
      const ACancellation: IPascalCancellation; out AProcessed: TPreprocessorResult): TSyntaxTree;
      overload; static;
    /// <summary>
    /// Syntaxfehler nur aus den aktiven Zweigen von $IFDEF/$IF/$ELSE unter ADefines; leer = Vordefinitionen
    /// von Delphi (Win32, aktuelle Version). False, wenn AText keine inaktiven Zweige hat; dann gelten die
    /// Diagnosen von Parse.
    /// </summary>
    class function ActiveDiagnostics(const AText: string; const ADefines: TArray<string>;
      out ADiagnostics: TArray<TSyntaxDiagnostic>): Boolean; overload; static;
    /// <summary>Wie oben unter AOptions, etwa mit Include-Resolver und Dateiname (#860).</summary>
    class function ActiveDiagnostics(const AText: string; const AOptions: TPreprocessorOptions;
      out ADiagnostics: TArray<TSyntaxDiagnostic>): Boolean; overload; static;
    /// <summary>Steht ein {$I datei.inc} hinter APrevious (letztes Token ohne Kommentare und Direktiven) an
    /// der Stelle eines Werts, z. B. "V = {$I commit.inc};" (#849)? Dann gehört es als Ausdruck in den Baum.
    /// </summary>
    class function IncludeAsValue(const APrevious: TPascalToken): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Defaults,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Parser.Cursor,
  Atlas.Common.Pascal.Parser.Expressions,
  Atlas.Common.Pascal.Parser.Declarations,
  Atlas.Common.Pascal.Parser.Types;

type
  /// <summary>Ganze Datei, Abschnitte und Anweisungen; Spitze der Kette Cursor, Ausdrücke, Deklarationen, Typen.</summary>
  TParser = class(TTypeParser)
  private
    /// <summary>Die Anweisung gehört direkt zu einem case-Zweig bzw. einem on-Handler: Dort beginnt
    /// "; else" den else-Teil von case bzw. except, kein Fehler wie E2153.</summary>
    FInCaseItem: Boolean;
    function ParseFile: TSyntaxNode;
    procedure ParseUnit(ANode: TSyntaxNode);
    procedure ParseProgram(ANode: TSyntaxNode);
    procedure ParseUses(AParent: TSyntaxNode);
    procedure ParseInterfaceSection(AParent: TSyntaxNode);
    procedure ParseImplementationSection(AParent: TSyntaxNode);
    procedure ParseStatementSection(AParent: TSyntaxNode; AKind: TSyntaxKind);
    procedure ParseRoutineBody(AParent: TSyntaxNode; AWithBody: Boolean); override;
    procedure ParseBlock(AParent: TSyntaxNode);
    procedure ParseAsm(AParent: TSyntaxNode);
    procedure ParseStatementList(AParent: TSyntaxNode; const ATerminators: array of string);
    procedure ParseStatementsUntil(AParent: TSyntaxNode);
    procedure ParseStatement(AParent: TSyntaxNode);
    procedure ParseStatementBody(AParent: TSyntaxNode);
    /// <summary>Sprungmarke mit Anweisung: Name: Anweisung.</summary>
    procedure ParseLabeledStatement(AParent: TSyntaxNode);
    /// <summary>begin, asm, if, case, for, while, repeat, with, try; False bei anderen Anweisungen.</summary>
    function ParseStructuredStatement(AParent: TSyntaxNode): Boolean;
    /// <summary>raise, Inline-Deklaration, goto, Zuweisung oder Aufruf; andere Schlüsselwörter überspringt der
    /// Aufrufer.</summary>
    procedure ParseSimpleStatement(AParent: TSyntaxNode);
    procedure ParseGoto(AParent: TSyntaxNode);
    procedure ParseAssignOrCall(AParent: TSyntaxNode);
    procedure ParseIf(AParent: TSyntaxNode);
    procedure ParseCase(AParent: TSyntaxNode);
    /// <summary>Ein Zweig "Marken: Anweisung"; False, wenn danach die Datei offensichtlich weitergeht (fehlendes
    /// end).</summary>
    function ParseCaseItem(ANode: TSyntaxNode): Boolean;
    procedure ParseCaseLabels(AItem: TSyntaxNode);
    procedure ParseFor(AParent: TSyntaxNode);
    procedure ParseWhile(AParent: TSyntaxNode);
    procedure ParseRepeat(AParent: TSyntaxNode);
    procedure ParseWith(AParent: TSyntaxNode);
    procedure ParseTry(AParent: TSyntaxNode);
    /// <summary>on E: Exception do Anweisung;</summary>
    procedure ParseExceptionHandler(APart: TSyntaxNode);
    procedure ParseRaise(AParent: TSyntaxNode);
    procedure ParseInlineDecl(AParent: TSyntaxNode);
    function ParseAnonymousMethod: TSyntaxNode; override;
  public
    function Run: TSyntaxTree;
  end;

{ TParser }

function TParser.Run: TSyntaxTree;
var
  Root: TSyntaxNode;
begin
  Root := ParseFile;
  CheckTokensAndTree(Root);
  Result := TSyntaxTree.Create(Root, FAllTokens, FDiagnostics.ToArray);
end;

function TParser.ParseFile: TSyntaxNode;
var
  Start: Integer;
begin
  Start := NodeStart;
  if IsKw('unit') then
  begin
    Result := StartNode(TSyntaxKind.UnitFile);
    ParseUnit(Result);
  end
  else
  begin
    if IsKw('library') then
    begin
      Result := StartNode(TSyntaxKind.LibraryFile);
    end
    else if IsIdentText('package') then
    begin
      Result := StartNode(TSyntaxKind.PackageFile);
    end
    else
    begin
      Result := StartNode(TSyntaxKind.ProgramFile);
    end;
    ParseProgram(Result);
  end;
  // Alles nach dem abschließenden Punkt ignoriert der Compiler.
  FIndex := Length(FTokens);
  FinishNode(Result, Start);
end;

procedure TParser.ParseUnit(ANode: TSyntaxNode);
begin
  ExpectKw('unit');
  ANode.Name := ParseQualifiedName;
  ParseHints;
  ExpectSym(';');

  ParseInterfaceSection(ANode);
  if IsKw('begin') then
  begin
    // Anweisungen bis zum implementation-Teil überspringen.
    DiagnoseCode('E2050', 'Anweisungen sind im interface-Teil nicht erlaubt', Current.StartPos, Current.EndPos);
    while not AtEnd and not IsKw('implementation') do
    begin
      Advance;
    end;
  end;
  ParseImplementationSection(ANode);

  if IsKw('initialization') then
  begin
    ParseStatementSection(ANode, TSyntaxKind.InitializationSection);
    if IsKw('finalization') then
    begin
      ParseStatementSection(ANode, TSyntaxKind.FinalizationSection);
    end;
  end
  else if IsKw('begin') then
  begin
    ParseStatementSection(ANode, TSyntaxKind.InitializationSection);
  end;
  ExpectKw('end');
  ExpectSym('.');
end;

procedure TParser.ParseProgram(ANode: TSyntaxNode);
begin
  if IsKw(['program', 'library']) or IsIdentText('package') then
  begin
    Advance;
    ANode.Name := ParseQualifiedName;
    if IsSym('(') then
    begin
      // program Name(Input, Output);
      Advance;
      while not AtEnd and not IsSym(')') and not IsSym(';') do
      begin
        Advance;
      end;
      AcceptSym(')');
    end;
    ExpectSym(';');
  end;
  FInImplementation := True;
  while IsKw('uses') or IsIdentText('contains') or IsIdentText('requires') do
  begin
    ParseUses(ANode);
  end;
  ParseDeclarations(ANode);
  if IsKw('begin') or IsKw('asm') then
  begin
    ParseBlock(ANode);
    ExpectSym('.');
  end
  else if IsKw('end') then
  begin
    // package-Dateien enden mit "end."
    Advance;
    ExpectSym('.');
  end
  else if not AtEnd then
  begin
    DiagnoseUnexpected('"begin"');
  end;
end;

procedure TParser.ParseUses(AParent: TSyntaxNode);
var
  Start: Integer;
  ItemStart: Integer;
  Node: TSyntaxNode;
  Item: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.UsesClause);
  AParent.Add(Node);
  Advance; // uses, contains oder requires
  repeat
    ItemStart := NodeStart;
    Item := StartNode(TSyntaxKind.UsedUnit);
    Item.Name := ParseQualifiedName;
    if AcceptKw('in') then
    begin
      if Current.Kind = TPascalTokenKind.StringLiteral then
      begin
        Advance;
      end
      else
      begin
        DiagnoseUnexpected('Dateiname');
      end;
    end;
    FinishNode(Item, ItemStart);
    Node.Add(Item);
    if Item.Name = '' then
    begin
      Break;
    end;
  until not AcceptSym(',');
  ExpectSym(';');
  FinishNode(Node, Start);
end;

procedure TParser.ParseInterfaceSection(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.InterfaceSection);
  AParent.Add(Node);
  ExpectKw('interface');
  FInImplementation := False;
  if IsKw('uses') then
  begin
    ParseUses(Node);
  end;
  ParseDeclarations(Node);
  FinishNode(Node, Start);
end;

procedure TParser.ParseImplementationSection(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.ImplementationSection);
  AParent.Add(Node);
  ExpectKw('implementation');
  FInImplementation := True;
  if IsKw('uses') then
  begin
    ParseUses(Node);
  end;
  ParseDeclarations(Node);
  FinishNode(Node, Start);
end;

procedure TParser.ParseStatementSection(AParent: TSyntaxNode; AKind: TSyntaxKind);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(AKind);
  AParent.Add(Node);
  Advance; // initialization, finalization oder begin
  ParseStatementList(Node, ['finalization', 'end']);
  FinishNode(Node, Start);
end;

procedure TParser.ParseRoutineBody(AParent: TSyntaxNode; AWithBody: Boolean);
var
  Start: Integer;
  Node: TSyntaxNode;
  Header: TSyntaxNode;
  Index: Integer;
  NoBody: Boolean;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.RoutineDecl);
  AParent.Add(Node);
  Header := ParseRoutineHeader(Node, TSyntaxKind.RoutineHeader);
  Node.Name := Header.Name;
  NoBody := False;
  for Index := 0 to Header.ChildCount - 1 do
  begin
    if (Header.Children[Index].Kind = TSyntaxKind.Directive) and
      ((Header.Children[Index].Name = 'forward') or (Header.Children[Index].Name = 'external')) then
    begin
      NoBody := True;
    end;
  end;
  if AWithBody and not NoBody then
  begin
    // Lokale Deklarationen, dann der Rumpf. exports ist hier ein Fehler des Compilers (E2191), aber kein
    // Syntaxfehler: Der Baum behält die Klausel, damit exports-invalid sie melden kann.
    while not AtEnd and (IsKw(['type', 'const', 'resourcestring', 'var', 'threadvar', 'label', 'exports']) or
      IsRoutineStart or IsSym('[')) do
    begin
      ParseDeclaration(Node);
    end;
    if IsKw('asm') then
    begin
      ParseAsm(Node);
    end
    else if IsKw('begin') then
    begin
      ParseBlock(Node);
    end
    else
    begin
      DiagnoseUnexpected('"begin"');
    end;
    ExpectSym(';');
  end;
  FinishNode(Node, Start);
end;

procedure TParser.ParseBlock(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  if IsKw('asm') then
  begin
    ParseAsm(AParent);
    Exit;
  end;
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.Block);
  AParent.Add(Node);
  ExpectKw('begin');
  ParseStatementList(Node, ['end']);
  ExpectKw('end');
  FinishNode(Node, Start);
end;

procedure TParser.ParseAsm(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  // Assembler wird nicht ausgewertet: bis zum nächsten end überspringen.
  // Sprungmarken wie @@End liefert der Lexer als Bezeichner (#861).
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.AsmBlock);
  AParent.Add(Node);
  Advance; // asm
  while not AtEnd and not IsKw('end') do
  begin
    Advance;
  end;
  ExpectKw('end');
  FinishNode(Node, Start);
end;

procedure TParser.ParseStatementList(AParent: TSyntaxNode; const ATerminators: array of string);
var
  Saved: TArray<string>;
  Index: Integer;
  SavedInCase: Boolean;
begin
  Saved := FTerminators;
  SavedInCase := FInCaseItem;
  FInCaseItem := False;
  SetLength(FTerminators, Length(ATerminators));
  for Index := 0 to High(ATerminators) do
  begin
    FTerminators[Index] := ATerminators[Index];
  end;
  try
    ParseStatementsUntil(AParent);
  finally
    FTerminators := Saved;
    FInCaseItem := SavedInCase;
  end;
end;

procedure TParser.ParseStatementsUntil(AParent: TSyntaxNode);
var
  Before: Integer;
begin
  while not AtEnd and not IsKw(FTerminators) do
  begin
    Before := FIndex;
    ParseStatement(AParent);
    if AcceptSym(';') then
    begin
      Continue;
    end;
    if AtEnd or IsKw(FTerminators) then
    begin
      Break;
    end;
    if FIndex = Before then
    begin
      // Die Anweisung hat nichts verbraucht: Token überspringen.
      SkipError(AParent, TRecovery.Statements);
    end
    else if IsKw(['implementation', 'initialization', 'finalization']) or IsRoutineStart then
    begin
      // Fehlendes end: Der Rest gehört nicht mehr zu diesem Block.
      Break;
    end
    else
    begin
      DiagnoseMissingSemicolon(True);
    end;
  end;
end;

procedure TParser.ParseStatement(AParent: TSyntaxNode);
begin
  if not EnterNesting then
  begin
    AParent.Add(TooDeep);
    Exit;
  end;
  try
    ParseStatementBody(AParent);
  finally
    Dec(FDepth);
  end;
end;

procedure TParser.ParseStatementBody(AParent: TSyntaxNode);
begin
  if AtEnd or IsSym(';') or IsKw(['end', 'until', 'except', 'finally', 'else']) then
  begin
    Exit;
  end; // leere Anweisung
  // Sprungmarke: Name: Anweisung
  if ((Current.Kind = TPascalTokenKind.Identifier) or (Current.Kind = TPascalTokenKind.Number)) and
    PeekIsSym(1, ':') then
  begin
    ParseLabeledStatement(AParent);
  end
  else if not ParseStructuredStatement(AParent) then
  begin
    ParseSimpleStatement(AParent);
  end;
end;

procedure TParser.ParseLabeledStatement(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.LabeledStatement);
  mNode.Name := Current.Text;
  AParent.Add(mNode);
  Advance;
  Advance;
  ParseStatement(mNode);
  FinishNode(mNode, mStart);
end;

function TParser.ParseStructuredStatement(AParent: TSyntaxNode): Boolean;
begin
  Result := True;
  if IsKw('begin') then
  begin
    ParseBlock(AParent);
  end
  else if IsKw('asm') then
  begin
    ParseAsm(AParent);
  end
  else if IsKw('if') then
  begin
    ParseIf(AParent);
  end
  else if IsKw('case') then
  begin
    ParseCase(AParent);
  end
  else if IsKw('for') then
  begin
    ParseFor(AParent);
  end
  else if IsKw('while') then
  begin
    ParseWhile(AParent);
  end
  else if IsKw('repeat') then
  begin
    ParseRepeat(AParent);
  end
  else if IsKw('with') then
  begin
    ParseWith(AParent);
  end
  else if IsKw('try') then
  begin
    ParseTry(AParent);
  end
  else
  begin
    Result := False;
  end;
end;

procedure TParser.ParseSimpleStatement(AParent: TSyntaxNode);
begin
  if IsKw('raise') then
  begin
    ParseRaise(AParent);
  end
  else if IsKw(['var', 'const']) then
  begin
    ParseInlineDecl(AParent);
  end
  else if IsKw('goto') then
  begin
    ParseGoto(AParent);
  end
  else if IsKw(['inherited', 'nil', 'string', 'not', 'procedure', 'function']) or
    not (Current.Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Unknown]) then
  begin
    ParseAssignOrCall(AParent);
  end;
  // Andere Schlüsselwörter: Der Aufrufer überspringt sie.
end;

procedure TParser.ParseGoto(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.GotoStatement);
  AParent.Add(mNode);
  Advance;
  if not AtEnd and not IsSym(';') then
  begin
    mNode.Name := Current.Text;
    Advance;
  end;
  FinishNode(mNode, mStart);
end;

procedure TParser.ParseAssignOrCall(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode, mTarget: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.CallStatement);
  mTarget := ParseExpression(mNode);
  if AcceptSym(':=') then
  begin
    mNode.Kind := TSyntaxKind.AssignStatement;
    ParseExpression(mNode);
  end;
  mNode.Name := mTarget.Name;
  FinishNode(mNode, mStart);
  AParent.Add(mNode);
end;

procedure TParser.ParseIf(AParent: TSyntaxNode);
var
  Parent: TSyntaxNode;
  Nodes: TList<TSyntaxNode>;
  Starts: TList<Integer>;
  Index, Before: Integer;
  Empty: TSyntaxNode;
begin
  // else if-Ketten in einer Schleife statt rekursiv (#849): Jedes "else if" wird wie bisher ein
  // IfStatement im else-Zweig des vorigen, zählt aber nicht als weitere Ebene für MaxNesting.
  Nodes := TList<TSyntaxNode>.Create;
  Starts := TList<Integer>.Create;
  try
    Parent := AParent;
    repeat
      Starts.Add(NodeStart);
      Nodes.Add(StartNode(TSyntaxKind.IfStatement));
      Parent.Add(Nodes.Last);
      Advance; // if
      ParseExpression(Nodes.Last);
      ExpectKw('then');
      Before := Nodes.Last.ChildCount;
      ParseStatement(Nodes.Last);
      // if A then B; else C – außer in case- und on-Zweigen, wo "; else" deren else-Teil beginnt (#1022).
      if IsSym(';') and PeekIsKw(1, 'else') and not FInCaseItem then
      begin
        DiagnoseCode('E2153', ''';'' vor ''else'' ist nicht erlaubt', Current.StartPos, Current.EndPos,
          TParserFix.Create(''';'' entfernen', Current.StartPos, Current.EndPos, '', True));
        Advance;
      end;
      // Leerer then-Zweig vor else (if A then else B): eine leere Anweisung hält seinen Platz, sonst stünde der
      // else-Zweig als then-Zweig im Baum.
      if IsKw('else') and (Nodes.Last.ChildCount = Before) then
      begin
        Empty := StartNode(TSyntaxKind.EmptyStatement);
        Nodes.Last.Add(Empty);
        FinishNode(Empty, FIndex);
      end;
      if not AcceptKw('else') then
      begin
        Break;
      end;
      if not IsKw('if') then
      begin
        ParseStatement(Nodes.Last);
        Break;
      end;
      Parent := Nodes.Last;
    until False;
    for Index := Nodes.Count - 1 downto 0 do
    begin
      FinishNode(Nodes[Index], Starts[Index]);
    end;
  finally
    Starts.Free;
    Nodes.Free;
  end;
end;

procedure TParser.ParseCase(AParent: TSyntaxNode);
var
  mStart, mItemStart: Integer;
  mNode, mItem: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.CaseStatement);
  AParent.Add(mNode);
  Advance; // case
  ParseExpression(mNode);
  ExpectKw('of');
  while not AtEnd and not IsKw(['end', 'else']) do
  begin
    if not ParseCaseItem(mNode) then
    begin
      Break;
    end;
  end;
  if IsKw('else') then
  begin
    mItemStart := NodeStart;
    mItem := StartNode(TSyntaxKind.CaseElse);
    mNode.Add(mItem);
    Advance;
    ParseStatementList(mItem, ['end']);
    FinishNode(mItem, mItemStart);
  end;
  ExpectKw('end');
  FinishNode(mNode, mStart);
end;

function TParser.ParseCaseItem(ANode: TSyntaxNode): Boolean;
var
  mBefore, mStart: Integer;
  mItem: TSyntaxNode;
  mSavedInCase: Boolean;
begin
  Result := True;
  mBefore := FIndex;
  mStart := NodeStart;
  mItem := StartNode(TSyntaxKind.CaseItem);
  ANode.Add(mItem);
  ParseCaseLabels(mItem);
  ExpectSym(':');
  mSavedInCase := FInCaseItem;
  FInCaseItem := True;
  ParseStatement(mItem);
  FInCaseItem := mSavedInCase;
  FinishNode(mItem, mStart);
  if AcceptSym(';') or IsKw(['end', 'else']) then
  begin
    Exit;
  end;
  DiagnoseMissingSemicolon(True);
  if FIndex = mBefore then
  begin
    Advance;
  end;
  Result := not IsKw(['implementation', 'initialization', 'finalization']) and not IsRoutineStart;
end;

procedure TParser.ParseCaseLabels(AItem: TSyntaxNode);
var
  mStart: Integer;
  mElement: TSyntaxNode;
begin
  // Marken: 1, 2..5, 'a': ein Bereich wird ein RangeExpr wie in Mengen (#983).
  repeat
    mStart := NodeStart;
    mElement := ParseExpression(AItem);
    if AcceptSym('..') then
    begin
      AItem.Extract(mElement);
      mElement := Binary('..', mElement, ParseExpression(nil), mStart);
      mElement.Kind := TSyntaxKind.RangeExpr;
      AItem.Add(mElement);
    end;
  until not AcceptSym(',');
end;

procedure TParser.ParseFor(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  // for [var] I [: Typ] := A to|downto B do ...; for [var] X in Liste do ...
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.ForStatement);
  AParent.Add(Node);
  Advance; // for
  AcceptKw('var');
  if IsIdent then
  begin
    Node.Name := ExpectIdent;
  end
  else
  begin
    DiagnoseUnexpected('E2088', 'Variablenname');
  end;
  if AcceptSym(':') then
  begin
    ParseTypeReference(Node);
  end;
  if AcceptKw('in') then
  begin
    Node.Kind := TSyntaxKind.ForInStatement;
    ParseExpression(Node);
  end
  else
  begin
    ExpectSym(':=');
    ParseExpression(Node);
    if not AcceptKw('to') then
    begin
      ExpectKw('downto');
      Node.Descending := True;
    end;
    ParseExpression(Node);
  end;
  ExpectKw('do');
  ParseStatement(Node);
  FinishNode(Node, Start);
end;

procedure TParser.ParseWhile(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.WhileStatement);
  AParent.Add(Node);
  Advance; // while
  ParseExpression(Node);
  ExpectKw('do');
  ParseStatement(Node);
  FinishNode(Node, Start);
end;

procedure TParser.ParseRepeat(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.RepeatStatement);
  AParent.Add(Node);
  Advance; // repeat
  ParseStatementList(Node, ['until', 'end']);
  ExpectKw('until');
  ParseExpression(Node);
  FinishNode(Node, Start);
end;

procedure TParser.ParseWith(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.WithStatement);
  AParent.Add(Node);
  Advance; // with
  repeat
    ParseExpression(Node);
  until not AcceptSym(',');
  ExpectKw('do');
  ParseStatement(Node);
  FinishNode(Node, Start);
end;

procedure TParser.ParseTry(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
  PartStart: Integer;
  Part: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.TryStatement);
  AParent.Add(Node);
  Advance; // try
  ParseStatementList(Node, ['except', 'finally', 'end']);
  PartStart := NodeStart;
  if AcceptKw('finally') then
  begin
    Part := StartNode(TSyntaxKind.FinallyBlock);
    Node.Add(Part);
    ParseStatementList(Part, ['end']);
    FinishNode(Part, PartStart);
  end
  else if AcceptKw('except') then
  begin
    Part := StartNode(TSyntaxKind.ExceptBlock);
    Node.Add(Part);
    if IsIdentText('on') then
    begin
      // on E: Exception do ...; on EFoo do ...; else ...
      while IsIdentText('on') do
      begin
        ParseExceptionHandler(Part);
      end;
      if AcceptKw('else') then
      begin
        ParseStatementList(Part, ['end']);
      end;
    end
    else
    begin
      ParseStatementList(Part, ['end']);
    end;
    FinishNode(Part, PartStart);
  end
  else
  begin
    DiagnoseUnexpected('E2125', '"except" oder "finally"');
  end;
  ExpectKw('end');
  FinishNode(Node, Start);
end;

procedure TParser.ParseExceptionHandler(APart: TSyntaxNode);
var
  mStart: Integer;
  mHandler: TSyntaxNode;
  mSavedInCase: Boolean;
begin
  mStart := NodeStart;
  mHandler := StartNode(TSyntaxKind.ExceptionHandler);
  APart.Add(mHandler);
  Advance; // on
  if PeekIsSym(1, ':') then
  begin
    mHandler.Name := Current.Text;
    Advance;
    Advance;
  end;
  ParseTypeReference(mHandler);
  ExpectKw('do');
  mSavedInCase := FInCaseItem;
  FInCaseItem := True;
  ParseStatement(mHandler);
  FInCaseItem := mSavedInCase;
  FinishNode(mHandler, mStart);
  AcceptSym(';');
end;

procedure TParser.ParseRaise(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.RaiseStatement);
  AParent.Add(Node);
  Advance; // raise
  if not AtEnd and not IsSym(';') and not IsKw(['end', 'else', 'until', 'except', 'finally']) then
  begin
    ParseExpression(Node);
    if IsIdentText('at') then
    begin
      Advance;
      ParseExpression(Node);
    end;
  end;
  FinishNode(Node, Start);
end;

procedure TParser.ParseInlineDecl(AParent: TSyntaxNode);
var
  Start: Integer;
  Node, mAttributes: TSyntaxNode;
  Names: string;
begin
  // var X: Integer := 1; var A, B: string; const C = 5; var Y := Ausdruck;
  Start := NodeStart;
  if IsKw('const') then
  begin
    Node := StartNode(TSyntaxKind.InlineConst);
  end
  else
  begin
    Node := StartNode(TSyntaxKind.InlineVar);
  end;
  AParent.Add(Node);
  Advance;
  // var [Weak] Obj: IInterface := nil; (#1167): Die Kinder der Inline-Variablen bleiben Typ und Wert, die
  // Attribute fallen weg; untyped-pointer-refcount liest [Weak]/[Unsafe] aus den Token.
  if IsSym('[') then
  begin
    mAttributes := StartNode(TSyntaxKind.Attribute);
    try
      ParseAttributes(mAttributes);
    finally
      mAttributes.Free;
    end;
  end;
  Names := ExpectIdent;
  while AcceptSym(',') do
  begin
    Names := Names + ',' + ExpectIdent;
  end;
  Node.Name := Names;
  if AcceptSym(':') then
  begin
    ParseType(Node);
  end;
  if AcceptSym(':=') or AcceptSym('=') then
  begin
    ParseExpression(Node);
  end;
  FinishNode(Node, Start);
end;

function TParser.ParseAnonymousMethod: TSyntaxNode;
var
  Start: Integer;
begin
  // procedure(A: Integer) begin ... end; function: Integer begin ... end
  Start := NodeStart;
  Result := StartNode(TSyntaxKind.AnonymousMethod);
  Result.Name := LowerCase(Current.Text);
  Advance;
  if IsSym('(') then
  begin
    ParseParameters(Result);
  end;
  if AcceptSym(':') then
  begin
    ParseTypeReference(Result);
  end;
  // Aufrufkonvention: function(const S: string): Boolean register begin … end (#1167).
  while IsIdent and InWords(Current.Text, CallingConventions) do
  begin
    Advance;
  end;
  // Lokale Abschnitte und Routinen vor dem begin (#849).
  while IsKw(['var', 'const', 'type', 'label']) or IsRoutineStart do
  begin
    if IsRoutineStart then
    begin
      ParseRoutine(Result, True);
    end
    else
    begin
      ParseDeclaration(Result);
    end;
  end;
  ParseBlock(Result);
  FinishNode(Result, Start);
end;

{ TPascalParser }

class function TPascalParser.IncludeAsValue(const APrevious: TPascalToken): Boolean;
begin
  Result := Atlas.Common.Pascal.Parser.Cursor.IncludeAsValue(APrevious);
end;


class function TPascalParser.Parse(const AText: string): TSyntaxTree;
begin
  Result := Parse(AText, nil);
end;

class function TPascalParser.Parse(const AText: string; const ACancellation: IPascalCancellation): TSyntaxTree;
var
  Parser: TParser;
begin
  Parser := TParser.Create(AText, ACancellation);
  try
    Result := Parser.Run;
  finally
    Parser.Free;
  end;
end;


class function TPascalParser.ParseActive(const AText: string; const ADefines: TArray<string>;
  const ACancellation: IPascalCancellation; out AConditionals: TArray<TConditionalRange>): TSyntaxTree;
var
  Processed: TPreprocessorResult;
begin
  Result := ParseActive(AText, TPascalPreprocessor.EditorOptions(ADefines), ACancellation, Processed);
  AConditionals := TPascalPreprocessor.MainConditionals(Processed);
end;

class function TPascalParser.ParseActive(const AText: string; const AOptions: TPreprocessorOptions;
  const ACancellation: IPascalCancellation; out AProcessed: TPreprocessorResult): TSyntaxTree;
var
  Parser: TParser;
begin
  AProcessed := Default(TPreprocessorResult);
  // Schnell: ohne bedingte Direktive und ohne $I gibt es nichts zu überspringen und zu melden.
  if not TPascalPreprocessor.HasConditionals(AText) and
    not (Assigned(AOptions.ResolveInclude) and TPascalPreprocessor.HasIncludes(AText)) then
  begin
    Result := Parse(AText, ACancellation);
  end
  else
  begin
    AProcessed := TPascalPreprocessor.Process(AText, AOptions);
    Parser := TParser.Create(AText, ACancellation, TPascalPreprocessor.MainInactive(AProcessed));
    try
      Result := Parser.Run;
    finally
      Parser.Free;
    end;
  end;
  Result.Platform := TPascalPreprocessor.PlatformOf(AOptions.Defines);
end;

class function TPascalParser.ParseActive(const AText: string; const ADefines: TArray<string>): TSyntaxTree;
var
  Conditionals: TArray<TConditionalRange>;
begin
  Result := ParseActive(AText, ADefines, nil, Conditionals);
end;

class function TPascalParser.ActiveDiagnostics(const AText: string; const ADefines: TArray<string>;
  out ADiagnostics: TArray<TSyntaxDiagnostic>): Boolean;
begin
  Result := ActiveDiagnostics(AText, TPascalPreprocessor.EditorOptions(ADefines), ADiagnostics);
end;

class function TPascalParser.ActiveDiagnostics(const AText: string; const AOptions: TPreprocessorOptions;
  out ADiagnostics: TArray<TSyntaxDiagnostic>): Boolean;
var
  Skip: TArray<TTextRange>;
  Parser: TParser;
  Tree: TSyntaxTree;
begin
  ADiagnostics := nil;
  if not TPascalPreprocessor.HasConditionals(AText) then
  begin
    Exit(False);
  end;
  Skip := TPascalPreprocessor.MainInactive(TPascalPreprocessor.Process(AText, AOptions));
  if Skip = nil then
  begin
    Exit(False);
  end;
  Parser := TParser.Create(AText, nil, Skip);
  try
    Tree := Parser.Run;
    try
      ADiagnostics := Tree.Diagnostics;
    finally
      Tree.Free;
    end;
  finally
    Parser.Free;
  end;
  Result := True;
end;

end.
