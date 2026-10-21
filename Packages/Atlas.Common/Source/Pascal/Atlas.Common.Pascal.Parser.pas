unit Atlas.Common.Pascal.Parser;

// Fehlertoleranter, rekursiv absteigender Parser für Object Pascal.
//
// Entscheidung (#7): eigener Parser statt DelphiAST. DelphiAST bricht bei
// Syntaxfehlern ab, bringt einen eigenen Lexer mit und hängt nicht am
// Rollenkonzept. Ein eigener Parser auf dem vorhandenen Lexer liefert auch für
// halb getippten Code einen Baum und lässt sich gezielt erweitern.
//
// Fehlerbehandlung: Fehlt ein erwartetes Token, wird eine Diagnose erzeugt und
// so weitergemacht, als wäre es da. Unpassende Token werden in Error-Knoten
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
    class function Parse(const AText: string; const ACancellation: IPascalCancellation = nil): TSyntaxTree; static;
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
    /// Syntaxfehler nur aus den aktiven Zweigen von $IFDEF/$IF/$ELSE unter ADefines; leer = Vordefinitionen
    /// von Delphi (Win32, aktuelle Version). False, wenn AText keine inaktiven Zweige hat; dann gelten die
    /// Diagnosen von Parse.
    /// </summary>
    class function ActiveDiagnostics(const AText: string; const ADefines: TArray<string>;
      out ADiagnostics: TArray<TSyntaxDiagnostic>): Boolean; static;
    /// <summary>Steht ein {$I datei.inc} hinter APrevious (letztes Token ohne Kommentare und Direktiven) an
    /// der Stelle eines Werts, z. B. "V = {$I commit.inc};" (#849)? Dann gehört es als Ausdruck in den Baum.
    /// </summary>
    class function IncludeAsValue(const APrevious: TPascalToken): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Lexer;

type
  /// <summary>Wo der Parser nach einem Fehler wieder aufsetzt.</summary>
  TRecovery = (Declarations, Members, Statements);

  TParser = class
  private
    FAllTokens: TArray<TPascalToken>;
    /// <summary>Nur bedeutungstragende Token, ohne Kommentare und Direktiven.</summary>
    FTokens: TArray<TPascalToken>;
    FIndex: Integer;
    /// <summary>Aktuelle Verschachtelungstiefe von Anweisungen, Typen und Ausdrücken.</summary>
    FDepth: Integer;
    FCancellation: IPascalCancellation;
    FAdvances: Integer;
    FDiagnostics: TList<TSyntaxDiagnostic>;
    FEndPos: TTextPosition;
    FEndOffset: Integer;
    FInImplementation: Boolean;
    /// <summary>Endwörter der innersten Anweisungsliste, für die Fehlerbehandlung.</summary>
    FTerminators: TArray<string>;

    // Token
    function AtEnd: Boolean; inline;
    function Current: TPascalToken;
    function PeekToken(ADelta: Integer): TPascalToken;
    function IsKw(const AWord: string): Boolean; overload;
    function IsKw(const AWords: array of string): Boolean; overload;
    function IsSym(const ASymbol: string): Boolean;
    function IsIdent: Boolean;
    function IsIdentText(const AText: string): Boolean;
    function PeekIsSym(ADelta: Integer; const ASymbol: string): Boolean;
    function PeekIsKw(ADelta: Integer; const AWord: string): Boolean;
    procedure Advance;
    function AcceptKw(const AWord: string): Boolean;
    function AcceptSym(const ASymbol: string): Boolean;
    procedure ExpectKw(const AWord: string);
    procedure ExpectSym(const ASymbol: string);
    function ExpectIdent: string;

    // Knoten und Diagnosen
    procedure Diagnose(const AMessage: string);
    procedure DiagnoseMissingSemicolon;
    procedure DiagnoseAt(const AMessage: string; const AStartPos, AEndPos: TTextPosition);
    procedure DiagnoseUnexpected(const AExpected: string);
    function StartNode(AKind: TSyntaxKind): TSyntaxNode;
    procedure FinishNode(ANode: TSyntaxNode; AStartIndex: Integer);
    function NodeStart: Integer; inline;
    function Leaf(AKind: TSyntaxKind; const AName: string): TSyntaxNode;
    function IsRecoveryPoint(ARecovery: TRecovery): Boolean;
    procedure SkipError(AParent: TSyntaxNode; ARecovery: TRecovery);

    // Datei und Abschnitte
    function ParseFile: TSyntaxNode;
    procedure ParseUnit(ANode: TSyntaxNode);
    procedure ParseProgram(ANode: TSyntaxNode);
    function ParseQualifiedName: string;
    procedure ParseUses(AParent: TSyntaxNode);
    procedure ParseInterfaceSection(AParent: TSyntaxNode);
    procedure ParseImplementationSection(AParent: TSyntaxNode);
    procedure ParseStatementSection(AParent: TSyntaxNode; AKind: TSyntaxKind);
    function IsSectionEnd: Boolean;
    function IsDeclarationStart: Boolean;
    procedure ParseDeclarations(AParent: TSyntaxNode);
    function ParseDeclaration(AParent: TSyntaxNode): Boolean;

    // Deklarationen
    procedure ParseAttributes(AParent: TSyntaxNode);
    procedure ParseTypeSection(AParent: TSyntaxNode);
    procedure ParseTypeDecl(AParent: TSyntaxNode);
    function ParseGenericParams(AParent: TSyntaxNode): Boolean;
    procedure ParseConstSection(AParent: TSyntaxNode);
    procedure ParseConstDecl(AParent: TSyntaxNode);
    function IsDeclStart: Boolean;
    /// <summary>Steht auf "["; folgt den Attributen ein Deklarationsname (#849)? Sonst gehören sie zur
    /// nächsten Methode oder Property und beenden den Abschnitt.</summary>
    function AttributesBeforeName: Boolean;
    function IsDirectiveStart: Boolean;
    procedure ParseVarSection(AParent: TSyntaxNode);
    procedure ParseVarDecl(AParent: TSyntaxNode);
    procedure ParseLabelSection(AParent: TSyntaxNode);
    procedure ParseExports(AParent: TSyntaxNode);
    function IsRoutineStart: Boolean;
    procedure ParseRoutine(AParent: TSyntaxNode; AWithBody: Boolean);
    procedure ParseRoutineBody(AParent: TSyntaxNode; AWithBody: Boolean);
    function ParseRoutineHeader(AParent: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
    procedure ParseParameters(AParent: TSyntaxNode);
    procedure ParseDirectives(AParent: TSyntaxNode);
    procedure ParseHints;

    // Typen
    function ParseType(AParent: TSyntaxNode): TSyntaxNode;
    function ParseTypeBody(AParent: TSyntaxNode): TSyntaxNode;
    function ParseTypeReference(AParent: TSyntaxNode): TSyntaxNode;
    function ParseTypeReferenceBody(AParent: TSyntaxNode): TSyntaxNode;
    procedure ParseClassBody(ANode: TSyntaxNode; AKind: TSyntaxKind);
    procedure ParseMembers(AParent: TSyntaxNode);
    procedure ParseProperty(AParent: TSyntaxNode);
    procedure ParseFieldDecl(AParent: TSyntaxNode); overload;
    /// <summary>AInVariant: Feld in der Klammer eines varianten Zweigs; vor ")" fehlt das ";".</summary>
    procedure ParseFieldDecl(AParent: TSyntaxNode; AInVariant: Boolean); overload;
    procedure ParseVariantPart(AParent: TSyntaxNode);
    procedure ParseVariantBody(ANode: TSyntaxNode);
    procedure ParseVariantFields(AParent: TSyntaxNode);
    procedure ParseProcedureType(ANode: TSyntaxNode);

    // Anweisungen
    procedure ParseBlock(AParent: TSyntaxNode);
    procedure ParseAsm(AParent: TSyntaxNode);
    procedure ParseStatementList(AParent: TSyntaxNode; const ATerminators: array of string);
    procedure ParseStatementsUntil(AParent: TSyntaxNode);
    procedure ParseStatement(AParent: TSyntaxNode);
    procedure ParseStatementBody(AParent: TSyntaxNode);
    procedure ParseIf(AParent: TSyntaxNode);
    procedure ParseCase(AParent: TSyntaxNode);
    procedure ParseFor(AParent: TSyntaxNode);
    procedure ParseWhile(AParent: TSyntaxNode);
    procedure ParseRepeat(AParent: TSyntaxNode);
    procedure ParseWith(AParent: TSyntaxNode);
    procedure ParseTry(AParent: TSyntaxNode);
    procedure ParseRaise(AParent: TSyntaxNode);
    procedure ParseInlineDecl(AParent: TSyntaxNode);

    // Ausdrücke
    function ParseExpression(AParent: TSyntaxNode): TSyntaxNode;
    function ParseSimpleExpression: TSyntaxNode;
    function ParseTerm: TSyntaxNode;
    function ParseFactor: TSyntaxNode;
    function ParseFactorBody: TSyntaxNode;
    function EnterNesting: Boolean;
    function TooDeep: TSyntaxNode;
    function ParsePrimary: TSyntaxNode;
    function ParseAnonymousMethod: TSyntaxNode;
    function LooksLikeGenericArgs: Boolean;
    procedure ParseGenericArgs(AParent: TSyntaxNode);
    procedure ParseArguments(AParent: TSyntaxNode; const ACloser: string);
    function Binary(const AOperator: string; ALeft, ARight: TSyntaxNode; AStartIndex: Integer): TSyntaxNode;
  public
    constructor Create(const AText: string; const ACancellation: IPascalCancellation;
      const ASkip: TArray<TTextRange> = nil);
    destructor Destroy; override;
    function Run: TSyntaxTree;
  end;

const
  RelationalOperators: array[0..5] of string = ('=', '<>', '<', '>', '<=', '>=');
  AdditiveSymbols: array[0..1] of string = ('+', '-');
  MultiplicativeSymbols: array[0..1] of string = ('*', '/');
  // Direktiven nach Routinenköpfen, ohne Groß-/Kleinschreibung.
  RoutineDirectives: array[0..31] of string = (
    'abstract', 'assembler', 'cdecl', 'deprecated', 'dispid', 'dynamic', 'experimental',
    'export', 'external', 'far', 'final', 'forward', 'inline', 'library', 'local',
    'message', 'near', 'noreturn', 'overload', 'override', 'pascal', 'platform',
    'register', 'reintroduce', 'safecall', 'static', 'stdcall', 'unsafe', 'varargs',
    'virtual', 'winapi', 'delayed');
  /// <summary>Höchste Verschachtelungstiefe; schützt vor Stapelüberlauf bei kaputtem Code.</summary>
  MaxNesting = 256;
  CallingConventions: array[0..6] of string = ('stdcall', 'cdecl', 'pascal', 'register', 'safecall', 'winapi',
    'varargs');
  VisibilityWords: array[0..5] of string = ('private', 'protected', 'public', 'published', 'automated', 'strict');
  HintWords: array[0..3] of string = ('deprecated', 'platform', 'library', 'experimental');

function SameWord(const A, B: string): Boolean; inline;
begin
  Result := SameText(A, B);
end;

function InWords(const AText: string; const AWords: array of string): Boolean;
var
  Word: string;
begin
  for Word in AWords do
    if SameText(AText, Word) then
      Exit(True);
  Result := False;
end;

{ TParser }

function Before(const A, B: TTextPosition): Boolean; inline;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function InRanges(const APos: TTextPosition; const ARanges: TArray<TTextRange>): Boolean;
var
  Range: TTextRange;
begin
  for Range in ARanges do
    if not Before(APos, Range.StartPos) and Before(APos, Range.EndPos) then
      Exit(True);
  Result := False;
end;

constructor TParser.Create(const AText: string; const ACancellation: IPascalCancellation;
  const ASkip: TArray<TTextRange>);
var
  Token: TPascalToken;
  Significant: TList<TPascalToken>;
  IncludeName: string;
begin
  inherited Create;
  FCancellation := ACancellation;
  FDiagnostics := TList<TSyntaxDiagnostic>.Create;
  FAllTokens := TPascalLexer.Tokenize(AText);
  Significant := TList<TPascalToken>.Create;
  try
    for Token in FAllTokens do
      if ((ASkip = nil) or not InRanges(Token.StartPos, ASkip)) and
        (not (Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) or
        ((Token.Kind = TPascalTokenKind.Directive) and (Significant.Count > 0) and
        TPascalPreprocessor.IncludeFileOf(Token.Text, IncludeName) and
        TPascalParser.IncludeAsValue(Significant[Significant.Count - 1]))) then
        Significant.Add(Token);
    FTokens := Significant.ToArray;
  finally
    Significant.Free;
  end;
  if Length(FAllTokens) > 0 then
  begin
    FEndPos := FAllTokens[High(FAllTokens)].EndPos;
    FEndOffset := FAllTokens[High(FAllTokens)].Offset + Length(FAllTokens[High(FAllTokens)].Text);
  end;
end;

destructor TParser.Destroy;
begin
  FDiagnostics.Free;
  inherited;
end;

function TParser.Run: TSyntaxTree;
var
  Root: TSyntaxNode;
begin
  Root := ParseFile;
  Result := TSyntaxTree.Create(Root, FAllTokens, FDiagnostics.ToArray);
end;

{ Token }

function TParser.AtEnd: Boolean;
begin
  Result := FIndex >= Length(FTokens);
end;

function TParser.Current: TPascalToken;
begin
  Result := PeekToken(0);
end;

function TParser.PeekToken(ADelta: Integer): TPascalToken;
begin
  if (FIndex + ADelta >= 0) and (FIndex + ADelta < Length(FTokens)) then
    Result := FTokens[FIndex + ADelta]
  else
  begin
    // Platzhalter hinter dem letzten Token.
    Result := Default(TPascalToken);
    Result.Kind := TPascalTokenKind.Unknown;
    Result.Offset := FEndOffset;
    Result.StartPos := FEndPos;
    Result.EndPos := FEndPos;
  end;
end;

function TParser.IsKw(const AWord: string): Boolean;
begin
  Result := not AtEnd and FTokens[FIndex].IsKeyword(AWord);
end;

function TParser.IsKw(const AWords: array of string): Boolean;
begin
  Result := not AtEnd and (FTokens[FIndex].Kind = TPascalTokenKind.Keyword) and InWords(FTokens[FIndex].Text, AWords);
end;

function TParser.IsSym(const ASymbol: string): Boolean;
begin
  Result := not AtEnd and FTokens[FIndex].IsSymbol(ASymbol);
end;

function TParser.IsIdent: Boolean;
begin
  Result := not AtEnd and (FTokens[FIndex].Kind = TPascalTokenKind.Identifier);
end;

function TParser.IsIdentText(const AText: string): Boolean;
begin
  Result := IsIdent and SameWord(FTokens[FIndex].Text, AText);
end;

function TParser.PeekIsSym(ADelta: Integer; const ASymbol: string): Boolean;
begin
  Result := PeekToken(ADelta).IsSymbol(ASymbol);
end;

function TParser.PeekIsKw(ADelta: Integer; const AWord: string): Boolean;
begin
  Result := PeekToken(ADelta).IsKeyword(AWord);
end;

procedure TParser.Advance;
begin
  if AtEnd then
    Exit;
  Inc(FIndex);
  // Abbruch nur gelegentlich abfragen; danach gilt der Rest als gelesen.
  Inc(FAdvances);
  if ((FAdvances and 4095) = 0) and (FCancellation <> nil) and FCancellation.IsCancelled then
    FIndex := Length(FTokens);
end;

function TParser.AcceptKw(const AWord: string): Boolean;
begin
  Result := IsKw(AWord);
  if Result then
    Advance;
end;

function TParser.AcceptSym(const ASymbol: string): Boolean;
begin
  Result := IsSym(ASymbol);
  if Result then
    Advance;
end;

procedure TParser.ExpectKw(const AWord: string);
begin
  if not AcceptKw(AWord) then
    DiagnoseUnexpected('"' + AWord + '"');
end;

procedure TParser.ExpectSym(const ASymbol: string);
begin
  if AcceptSym(ASymbol) then
    Exit;
  if ASymbol = ';' then
    DiagnoseMissingSemicolon
  else
    DiagnoseUnexpected('"' + ASymbol + '"');
end;

procedure TParser.DiagnoseMissingSemicolon;
var
  Previous: TPascalToken;
begin
  // Folgefehler: An dieser Stelle wurde schon etwas gemeldet.
  if (FDiagnostics.Count > 0) and (FDiagnostics.Last.StartPos = Current.StartPos) then
    Exit;
  Previous := PeekToken(-1);
  // Am Zeilenende dort melden, wo es fehlt, nicht erst in der nächsten Zeile.
  if (FIndex > 0) and (AtEnd or (Current.StartPos.Line > Previous.EndPos.Line)) then
    DiagnoseAt('";" fehlt', Previous.EndPos, Previous.EndPos)
  else
    DiagnoseUnexpected('";"');
end;

function TParser.ExpectIdent: string;
begin
  if IsIdent then
  begin
    Result := Current.Text;
    Advance;
  end
  else
  begin
    DiagnoseUnexpected('Bezeichner');
    Result := '';
  end;
end;

{ Knoten und Diagnosen }

procedure TParser.Diagnose(const AMessage: string);
begin
  DiagnoseAt(AMessage, Current.StartPos, Current.EndPos);
end;

procedure TParser.DiagnoseAt(const AMessage: string; const AStartPos, AEndPos: TTextPosition);
var
  Diagnostic: TSyntaxDiagnostic;
begin
  Diagnostic.Message := AMessage;
  Diagnostic.StartPos := AStartPos;
  Diagnostic.EndPos := AEndPos;
  // Mehrere Folgefehler an derselben Stelle melden wir nur einmal.
  if (FDiagnostics.Count > 0) and (FDiagnostics.Last.StartPos = Diagnostic.StartPos) then
    Exit;
  FDiagnostics.Add(Diagnostic);
end;

procedure TParser.DiagnoseUnexpected(const AExpected: string);
begin
  if AtEnd then
    Diagnose(AExpected + ' erwartet, Dateiende gefunden')
  else
    Diagnose(AExpected + ' erwartet, "' + Current.Text + '" gefunden');
end;

function TParser.NodeStart: Integer;
begin
  Result := FIndex;
end;

function TParser.StartNode(AKind: TSyntaxKind): TSyntaxNode;
begin
  Result := TSyntaxNode.Create(AKind);
end;

procedure TParser.FinishNode(ANode: TSyntaxNode; AStartIndex: Integer);
var
  First: TPascalToken;
  Last: TPascalToken;
begin
  if FIndex > AStartIndex then
  begin
    First := FTokens[AStartIndex];
    Last := FTokens[FIndex - 1];
    ANode.SetRange(First.StartPos, Last.EndPos, First.Offset, Last.Offset + Length(Last.Text));
  end
  else
  begin
    // Leerer Knoten, z. B. bei fehlendem Ausdruck: Position des nächsten Tokens.
    First := Current;
    ANode.SetRange(First.StartPos, First.StartPos, First.Offset, First.Offset);
  end;
end;

function TParser.Leaf(AKind: TSyntaxKind; const AName: string): TSyntaxNode;
var
  Start: Integer;
begin
  Start := NodeStart;
  Result := StartNode(AKind);
  Result.Name := AName;
  Advance;
  FinishNode(Result, Start);
end;

function TParser.IsRecoveryPoint(ARecovery: TRecovery): Boolean;
begin
  case ARecovery of
    TRecovery.Declarations:
      Result := IsSectionEnd or IsDeclarationStart;
    TRecovery.Members:
      Result := IsKw('end') or IsSym(';') or IsIdent or IsRoutineStart or IsKw('property');
  else
    Result := IsSym(';') or IsKw(FTerminators) or
      IsKw(['begin', 'if', 'case', 'for', 'while', 'repeat', 'with', 'try', 'raise']);
  end;
end;

procedure TParser.SkipError(AParent: TSyntaxNode; ARecovery: TRecovery);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  // Mindestens ein Token überspringen, damit der Aufrufer weiterkommt.
  if AtEnd then
    Exit;
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.Error);
  Diagnose('Unerwartetes "' + Current.Text + '"');
  repeat
    Advance;
  until AtEnd or IsRecoveryPoint(ARecovery);
  FinishNode(Node, Start);
  AParent.Add(Node);
end;

{ Datei und Abschnitte }

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
      Result := StartNode(TSyntaxKind.LibraryFile)
    else if IsIdentText('package') then
      Result := StartNode(TSyntaxKind.PackageFile)
    else
      Result := StartNode(TSyntaxKind.ProgramFile);
    ParseProgram(Result);
  end;
  // Alles nach dem abschließenden Punkt ignoriert der Compiler.
  FIndex := Length(FTokens);
  FinishNode(Result, Start);
end;

function TParser.ParseQualifiedName: string;
begin
  Result := ExpectIdent;
  while IsSym('.') and (PeekToken(1).Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) do
  begin
    Advance;
    Result := Result + '.' + Current.Text;
    Advance;
  end;
end;

procedure TParser.ParseUnit(ANode: TSyntaxNode);
begin
  ExpectKw('unit');
  ANode.Name := ParseQualifiedName;
  ParseHints;
  ExpectSym(';');

  ParseInterfaceSection(ANode);
  ParseImplementationSection(ANode);

  if IsKw('initialization') then
  begin
    ParseStatementSection(ANode, TSyntaxKind.InitializationSection);
    if IsKw('finalization') then
      ParseStatementSection(ANode, TSyntaxKind.FinalizationSection);
  end
  else if IsKw('begin') then
    ParseStatementSection(ANode, TSyntaxKind.InitializationSection);
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
        Advance;
      AcceptSym(')');
    end;
    ExpectSym(';');
  end;
  FInImplementation := True;
  while IsKw('uses') or IsIdentText('contains') or IsIdentText('requires') do
    ParseUses(ANode);
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
    DiagnoseUnexpected('"begin"');
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
        Advance
      else
        DiagnoseUnexpected('Dateiname');
    end;
    FinishNode(Item, ItemStart);
    Node.Add(Item);
    if Item.Name = '' then
      Break;
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
    ParseUses(Node);
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
    ParseUses(Node);
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

function TParser.IsSectionEnd: Boolean;
begin
  Result := AtEnd or IsKw(['implementation', 'initialization', 'finalization', 'begin', 'end', 'asm']);
end;

function TParser.IsDeclarationStart: Boolean;
begin
  Result := IsKw(['type', 'const', 'resourcestring', 'var', 'threadvar', 'label', 'exports']) or
    IsRoutineStart or IsSym('[');
end;

procedure TParser.ParseDeclarations(AParent: TSyntaxNode);
begin
  while not IsSectionEnd do
    if not ParseDeclaration(AParent) then
      SkipError(AParent, TRecovery.Declarations);
end;

function TParser.ParseDeclaration(AParent: TSyntaxNode): Boolean;
begin
  Result := True;
  if IsKw('type') then
    ParseTypeSection(AParent)
  else if IsKw(['const', 'resourcestring']) then
    ParseConstSection(AParent)
  else if IsKw(['var', 'threadvar']) then
    ParseVarSection(AParent)
  else if IsKw('label') then
    ParseLabelSection(AParent)
  else if IsKw('exports') then
    ParseExports(AParent)
  else if IsSym('[') then
    ParseAttributes(AParent)
  else if IsRoutineStart then
    ParseRoutine(AParent, FInImplementation)
  else
    Result := False;
end;

{ Deklarationen }

procedure TParser.ParseAttributes(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  // [Attr], [Attr(1, 'x')], [A, B]
  while IsSym('[') do
  begin
    Start := NodeStart;
    Node := StartNode(TSyntaxKind.Attribute);
    AParent.Add(Node);
    Advance;
    if not IsSym(']') then
      ParseArguments(Node, ']')
    else
      Advance;
    if Node.ChildCount > 0 then
      Node.Name := Node.Children[0].Name;
    FinishNode(Node, Start);
  end;
end;

procedure TParser.ParseTypeSection(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.TypeSection);
  AParent.Add(Node);
  Advance; // type
  while IsDeclStart do
  begin
    if IsSym('[') then
      ParseAttributes(Node)
    else
      ParseTypeDecl(Node);
  end;
  FinishNode(Node, Start);
end;

procedure TParser.ParseTypeDecl(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.TypeDecl);
  AParent.Add(Node);
  Node.Name := ExpectIdent;
  if not (IsSym('<') and ParseGenericParams(Node)) then
    ExpectSym('=');
  AcceptKw('type'); // type TNeu = type Integer;
  ParseType(Node);
  ParseHints;
  ExpectSym(';');
  FinishNode(Node, Start);
end;

function TParser.ParseGenericParams(AParent: TSyntaxNode): Boolean;
var
  Start: Integer;
  Node: TSyntaxNode;
  Depth: Integer;
  InConstraint: Boolean;
begin
  // <T>, <K, V>, <T: class, constructor>, <T: IFoo, IBar; U>. Liefert True, wenn
  // der Lexer ">=" gelesen hat (TFoo<T>=class), das "=" also schon verbraucht ist.
  // Nach ":" gehören Kommas zur Liste der Einschränkungen, bis ";" kommt (#849).
  Result := False;
  InConstraint := False;
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.GenericParams);
  AParent.Add(Node);
  Advance; // <
  Depth := 1;
  while not AtEnd and (Depth > 0) do
  begin
    if IsSym('<') then
    begin
      Inc(Depth);
      Advance;
    end
    else if IsSym('>') or IsSym('>=') then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Result := IsSym('>=');
        Advance;
      end
      else
        Advance;
    end
    else if IsSym('=') or IsSym('(') or IsSym(')') or IsKw(['begin', 'end']) then
      Break
    else if (Depth = 1) and (IsSym(':') or IsSym(';')) then
    begin
      InConstraint := IsSym(':');
      Advance;
    end
    else if IsIdent and (Depth = 1) and not InConstraint and
      (PeekIsSym(-1, '<') or PeekIsSym(-1, ',') or PeekIsSym(-1, ';')) then
      Node.Add(Leaf(TSyntaxKind.Identifier, Current.Text))
    else
      Advance;
  end;
  if Depth > 0 then
    DiagnoseUnexpected('">"');
  FinishNode(Node, Start);
end;

function TParser.AttributesBeforeName: Boolean;
var
  Delta, Depth: Integer;
  Token: TPascalToken;
begin
  Delta := 0;
  while PeekIsSym(Delta, '[') do
  begin
    Depth := 0;
    repeat
      if FIndex + Delta >= Length(FTokens) then
        Exit(False);
      Token := PeekToken(Delta);
      if Token.IsSymbol('[') then
        Inc(Depth)
      else if Token.IsSymbol(']') then
        Dec(Depth);
      Inc(Delta);
    until Depth = 0;
  end;
  Token := PeekToken(Delta);
  Result := (Token.Kind = TPascalTokenKind.Identifier) and not InWords(Token.Text, VisibilityWords);
end;

function TParser.IsDeclStart: Boolean;
begin
  // Sichtbarkeit beendet einen var- oder const-Abschnitt in Klassen, ebenso ein Attribut vor einer Methode.
  Result := (IsSym('[') and AttributesBeforeName) or (IsIdent and not (InWords(Current.Text, VisibilityWords) and
    not PeekIsSym(1, ':') and not PeekIsSym(1, ',') and not PeekIsSym(1, '=')));
end;

procedure TParser.ParseConstSection(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.ConstSection);
  Node.Name := LowerCase(Current.Text); // const oder resourcestring
  AParent.Add(Node);
  Advance;
  while IsDeclStart do
    if IsSym('[') then
      ParseAttributes(Node)
    else
      ParseConstDecl(Node);
  FinishNode(Node, Start);
end;

procedure TParser.ParseConstDecl(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  // Name = Wert; Name: Typ = Wert;
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.ConstDecl);
  AParent.Add(Node);
  Node.Name := ExpectIdent;
  if AcceptSym(':') then
    ParseType(Node);
  ExpectSym('=');
  ParseExpression(Node);
  ParseHints;
  ExpectSym(';');
  FinishNode(Node, Start);
end;

procedure TParser.ParseVarSection(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.VarSection);
  Node.Name := LowerCase(Current.Text); // var oder threadvar
  AParent.Add(Node);
  Advance;
  while IsDeclStart do
    if IsSym('[') then
      ParseAttributes(Node)
    else
      ParseVarDecl(Node);
  FinishNode(Node, Start);
end;

procedure TParser.ParseVarDecl(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
  Names: string;
begin
  // A, B: Typ; X: Typ = Wert; Y: Typ absolute Z;
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.VarDecl);
  AParent.Add(Node);
  Names := ExpectIdent;
  while AcceptSym(',') do
    Names := Names + ',' + ExpectIdent;
  Node.Name := Names;
  ExpectSym(':');
  ParseType(Node);
  if IsIdentText('absolute') then
  begin
    Advance;
    ParseExpression(Node);
  end
  else if AcceptSym('=') then
    ParseExpression(Node);
  ParseHints;
  ExpectSym(';');
  FinishNode(Node, Start);
end;

procedure TParser.ParseLabelSection(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.LabelSection);
  AParent.Add(Node);
  Advance; // label
  while not AtEnd and not IsSym(';') and not IsSectionEnd do
    Advance;
  ExpectSym(';');
  FinishNode(Node, Start);
end;

procedure TParser.ParseExports(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.ExportsClause);
  AParent.Add(Node);
  Advance; // exports
  while not AtEnd and not IsSym(';') and not IsSectionEnd do
    Advance;
  ExpectSym(';');
  FinishNode(Node, Start);
end;

function TParser.IsRoutineStart: Boolean;
begin
  // Ein Feld namens Operator (Operator: string;) ist kein Routinenkopf (#849).
  Result := IsKw(['procedure', 'function', 'constructor', 'destructor']) or
    (IsIdentText('operator') and not PeekIsSym(1, ':') and not PeekIsSym(1, ',')) or
    (IsKw('class') and (PeekIsKw(1, 'procedure') or PeekIsKw(1, 'function') or PeekIsKw(1, 'constructor') or
      PeekIsKw(1, 'destructor') or PeekToken(1).IsKeyword('operator') or
      ((PeekToken(1).Kind = TPascalTokenKind.Identifier) and SameWord(PeekToken(1).Text, 'operator'))));
end;

function TParser.ParseRoutineHeader(AParent: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  Start, ClauseStart: Integer;
  Name: string;
  Clause: TSyntaxNode;
begin
  // [class] procedure|function|constructor|destructor|operator Name[<T>][.Name[<T>]] [(Params)] [: Typ];
  Start := NodeStart;
  Result := StartNode(AKind);
  AParent.Add(Result);
  AcceptKw('class');
  Advance; // procedure, function, constructor, destructor, operator
  Name := ExpectIdent;
  repeat
    if IsSym('<') then
      ParseGenericParams(Result);
    if IsSym('.') and (PeekToken(1).Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
    begin
      Advance;
      Name := Name + '.' + Current.Text;
      Advance;
    end
    else
      Break;
  until False;
  Result.Name := Name;
  if IsSym('(') then
    ParseParameters(Result);
  if AcceptSym(':') then
  begin
    ParseAttributes(Result);
    ParseTypeReference(Result);
  end;
  if IsSym('=') then
  begin
    // Methodenzuordnung: procedure IFoo.Bar = MyBar; als Direktive "resolution" mit dem Ziel (#849).
    ClauseStart := NodeStart;
    Clause := StartNode(TSyntaxKind.Directive);
    Clause.Name := 'resolution';
    Result.Add(Clause);
    Advance;
    if IsIdent then
      Clause.Add(Leaf(TSyntaxKind.Identifier, Current.Text))
    else
      ExpectIdent;
    FinishNode(Clause, ClauseStart);
  end;
  // Aufrufkonvention oder Direktive ohne Semikolon davor: function F: Integer stdcall; (#849)
  if IsDirectiveStart then
    ParseDirectives(Result)
  else
  begin
    if not IsSym(';') and not IsSym(')') and not IsSym(']') then
      DiagnoseMissingSemicolon
    else
      AcceptSym(';');
    ParseDirectives(Result);
  end;
  FinishNode(Result, Start);
end;

procedure TParser.ParseParameters(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
  ParamStart: Integer;
  Param: TSyntaxNode;
  Names: string;
  Closer: string;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.Parameters);
  AParent.Add(Node);
  if IsSym('[') then
    Closer := ']'
  else
    Closer := ')';
  Advance; // ( oder [
  while not AtEnd and not IsSym(Closer) do
  begin
    ParamStart := NodeStart;
    Param := StartNode(TSyntaxKind.Parameter);
    Node.Add(Param);
    ParseAttributes(Param);
    // Modifizierer: const, var, out, constref
    if IsKw(['const', 'var']) or ((IsIdentText('out') or IsIdentText('constref')) and
      (PeekToken(1).Kind = TPascalTokenKind.Identifier)) then
    begin
      if IsKw('const') then
        Param.Modifier := TParameterModifier.ConstParam
      else if IsKw('var') then
        Param.Modifier := TParameterModifier.VarParam
      else if IsIdentText('out') then
        Param.Modifier := TParameterModifier.OutParam
      else
        Param.Modifier := TParameterModifier.ConstRefParam;
      Advance;
    end;
    ParseAttributes(Param);
    Names := ExpectIdent;
    while AcceptSym(',') do
      Names := Names + ',' + ExpectIdent;
    Param.Name := Names;
    if AcceptSym(':') then
    begin
      if IsKw('array') then
        ParseType(Param)
      else
        ParseTypeReference(Param);
    end;
    if AcceptSym('=') then
      ParseExpression(Param);
    FinishNode(Param, ParamStart);
    if not AcceptSym(';') then
      Break;
  end;
  ExpectSym(Closer);
  FinishNode(Node, Start);
end;

function TParser.IsDirectiveStart: Boolean;
begin
  Result := IsIdent and InWords(Current.Text, RoutineDirectives) or IsKw(['inline', 'library']);
end;

procedure TParser.ParseDirectives(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
  Word: string;
begin
  // overload; virtual; abstract; external 'dll' name 'x'; message WM_X; ...
  while IsDirectiveStart do
  begin
    Start := NodeStart;
    Word := LowerCase(Current.Text);
    Node := StartNode(TSyntaxKind.Directive);
    Node.Name := Word;
    AParent.Add(Node);
    Advance;
    // Argumente der Direktive bis zum Semikolon; "assembler asm" ohne Semikolon (#849).
    while not AtEnd and not IsSym(';') and not IsKw(['begin', 'asm', 'var', 'const', 'type', 'end', 'label']) and
      not IsRoutineStart and not IsDirectiveStart do
      Advance;
    FinishNode(Node, Start);
    AcceptSym(';');
  end;
end;

procedure TParser.ParseHints;
begin
  // deprecated 'Grund', platform, library, experimental
  while (IsIdent and InWords(Current.Text, HintWords)) or IsKw('library') do
  begin
    Advance;
    if Current.Kind = TPascalTokenKind.StringLiteral then
      Advance;
  end;
end;

procedure TParser.ParseRoutine(AParent: TSyntaxNode; AWithBody: Boolean);
begin
  if not EnterNesting then
  begin
    AParent.Add(TooDeep);
    Exit;
  end;
  try
    ParseRoutineBody(AParent, AWithBody);
  finally
    Dec(FDepth);
  end;
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
    if (Header.Children[Index].Kind = TSyntaxKind.Directive) and
      ((Header.Children[Index].Name = 'forward') or (Header.Children[Index].Name = 'external')) then
      NoBody := True;
  if AWithBody and not NoBody then
  begin
    // Lokale Deklarationen, dann der Rumpf.
    while not AtEnd and (IsKw(['type', 'const', 'resourcestring', 'var', 'threadvar', 'label']) or
      IsRoutineStart or IsSym('[')) do
      ParseDeclaration(Node);
    if IsKw('asm') then
      ParseAsm(Node)
    else if IsKw('begin') then
      ParseBlock(Node)
    else
      DiagnoseUnexpected('"begin"');
    ExpectSym(';');
  end;
  FinishNode(Node, Start);
end;

{ Typen }

function TParser.ParseTypeReference(AParent: TSyntaxNode): TSyntaxNode;
begin
  if not EnterNesting then
  begin
    Result := TooDeep;
    AParent.Add(Result);
    Exit;
  end;
  try
    Result := ParseTypeReferenceBody(AParent);
  finally
    Dec(FDepth);
  end;
end;

function TParser.ParseTypeReferenceBody(AParent: TSyntaxNode): TSyntaxNode;
var
  Start: Integer;
  Name: string;
begin
  // Name, Unit.Name, TList<Integer>, string, string[20], file, array of const
  Start := NodeStart;
  Result := StartNode(TSyntaxKind.TypeReference);
  AParent.Add(Result);
  if IsKw(['string', 'file']) or IsIdent then
  begin
    Name := Current.Text;
    Advance;
  end
  else if IsKw('const') then
  begin
    Name := 'const';
    Advance;
  end
  else
    DiagnoseUnexpected('Typ');
  repeat
    if IsSym('<') and LooksLikeGenericArgs then
      ParseGenericArgs(Result);
    if IsSym('.') and (PeekToken(1).Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
    begin
      Advance;
      Name := Name + '.' + Current.Text;
      Advance;
    end
    else
      Break;
  until False;
  if SameWord(Name, 'string') and IsSym('[') then
  begin
    // ShortString-Länge: string[20]
    Advance;
    ParseExpression(Result);
    ExpectSym(']');
  end;
  Result.Name := Name;
  FinishNode(Result, Start);
end;

function TParser.ParseType(AParent: TSyntaxNode): TSyntaxNode;
begin
  if not EnterNesting then
  begin
    Result := TooDeep;
    AParent.Add(Result);
    Exit;
  end;
  try
    Result := ParseTypeBody(AParent);
  finally
    Dec(FDepth);
  end;
end;

function TParser.ParseTypeBody(AParent: TSyntaxNode): TSyntaxNode;
var
  Start: Integer;
  Expr: TSyntaxNode;
  Holder: TSyntaxNode;
begin
  Start := NodeStart;
  AcceptKw('packed');
  if IsKw('class') then
  begin
    if PeekIsSym(1, ';') then
    begin
      Result := StartNode(TSyntaxKind.ForwardType);
      Result.Name := 'class';
      Advance;
    end
    // class helper [(TBaseHelper)] for T (#848)
    else if SameWord(PeekToken(1).Text, 'helper') and (PeekIsKw(2, 'for') or PeekIsSym(2, '(')) then
    begin
      Result := StartNode(TSyntaxKind.HelperType);
      Result.Name := 'class';
      Advance; // class
      Advance; // helper
      ParseClassBody(Result, TSyntaxKind.HelperType);
    end
    else if PeekIsKw(1, 'of') then
    begin
      Result := StartNode(TSyntaxKind.ClassOfType);
      Advance;
      Advance;
      ParseTypeReference(Result);
    end
    else
    begin
      Result := StartNode(TSyntaxKind.ClassType);
      Advance;
      // abstract, sealed
      while IsIdentText('abstract') or IsIdentText('sealed') do
        Advance;
      ParseClassBody(Result, TSyntaxKind.ClassType);
    end;
  end
  else if IsKw('object') then
  begin
    Result := StartNode(TSyntaxKind.ObjectType);
    Advance;
    ParseClassBody(Result, TSyntaxKind.ObjectType);
  end
  else if IsKw('record') then
  begin
    if SameWord(PeekToken(1).Text, 'helper') and (PeekIsKw(2, 'for') or PeekIsSym(2, '(')) then
    begin
      Result := StartNode(TSyntaxKind.HelperType);
      Result.Name := 'record';
      Advance;
      Advance;
      ParseClassBody(Result, TSyntaxKind.HelperType);
    end
    else
    begin
      Result := StartNode(TSyntaxKind.RecordType);
      Advance;
      ParseMembers(Result);
      ExpectKw('end');
    end;
  end
  else if IsKw(['interface', 'dispinterface']) then
  begin
    if PeekIsSym(1, ';') then
    begin
      Result := StartNode(TSyntaxKind.ForwardType);
      Result.Name := LowerCase(Current.Text);
      Advance;
    end
    else
    begin
      Result := StartNode(TSyntaxKind.InterfaceType);
      Advance;
      ParseClassBody(Result, TSyntaxKind.InterfaceType);
    end;
  end
  else if IsSym('(') then
  begin
    // Aufzählung: (rot, gruen = 2, blau)
    Result := StartNode(TSyntaxKind.EnumType);
    Advance;
    while not AtEnd and not IsSym(')') do
    begin
      if IsIdent then
        Result.Add(Leaf(TSyntaxKind.Identifier, Current.Text))
      else
        DiagnoseUnexpected('Bezeichner');
      if AcceptSym('=') then
        ParseExpression(Result);
      if not AcceptSym(',') then
        Break;
    end;
    ExpectSym(')');
  end
  else if IsKw('set') then
  begin
    Result := StartNode(TSyntaxKind.SetType);
    Advance;
    ExpectKw('of');
    ParseType(Result);
  end
  else if IsKw('array') then
  begin
    Result := StartNode(TSyntaxKind.ArrayType);
    Advance;
    if AcceptSym('[') then
    begin
      repeat
        ParseType(Result);
      until not AcceptSym(',');
      ExpectSym(']');
    end;
    ExpectKw('of');
    if IsKw('const') then
      ParseTypeReference(Result)
    else
      ParseType(Result);
  end
  else if IsSym('^') then
  begin
    Result := StartNode(TSyntaxKind.PointerType);
    Advance;
    ParseTypeReference(Result);
  end
  else if IsKw(['procedure', 'function']) then
  begin
    Result := StartNode(TSyntaxKind.ProcedureType);
    ParseProcedureType(Result);
  end
  else if IsIdentText('reference') and PeekIsKw(1, 'to') then
  begin
    Result := StartNode(TSyntaxKind.ProcedureType);
    Result.Name := 'reference';
    Advance;
    Advance;
    ParseProcedureType(Result);
  end
  else if IsKw('file') and PeekIsKw(1, 'of') then
  begin
    Result := StartNode(TSyntaxKind.FileType);
    Advance;
    Advance;
    ParseTypeReference(Result);
  end
  else if IsKw(['string', 'file', 'const']) or
    (IsIdent and not PeekIsSym(1, '..') and not PeekIsSym(1, '(')) then
  begin
    // Benannter Typ, ggf. doch ein Teilbereich wie Low(X)..High(X) oder A.B..C.
    Result := ParseTypeReference(AParent);
    if IsSym('..') then
    begin
      // Der Name war der Anfang eines Teilbereichs.
      AParent.Extract(Result);
      Holder := StartNode(TSyntaxKind.SubrangeType);
      Holder.Add(Result);
      Advance;
      // Ohne Vergleich: in "X: 1..3 = 2" gehört "= 2" nicht zur Obergrenze (#849).
      Holder.Add(ParseSimpleExpression);
      FinishNode(Holder, Start);
      AParent.Add(Holder);
      Exit(Holder);
    end;
    Exit;
  end
  else
  begin
    // Teilbereich: 1..10, 'a'..'z', Low(X)..High(X)
    Result := StartNode(TSyntaxKind.SubrangeType);
    Expr := ParseExpression(Result);
    if AcceptSym('..') then
      Result.Add(ParseSimpleExpression)
    else if Expr.Kind = TSyntaxKind.Identifier then
      Result.Kind := TSyntaxKind.TypeReference
    else
      DiagnoseUnexpected('Typ');
  end;
  FinishNode(Result, Start);
  AParent.Add(Result);
end;

procedure TParser.ParseProcedureType(ANode: TSyntaxNode);
begin
  // procedure(A: Integer) of object; function: Boolean; reference to procedure
  if IsKw(['procedure', 'function']) then
    Advance
  else
    DiagnoseUnexpected('"procedure"');
  if IsSym('(') then
    ParseParameters(ANode);
  if AcceptSym(':') then
    ParseTypeReference(ANode);
  if IsKw('of') and SameWord(PeekToken(1).Text, 'object') then
  begin
    Advance;
    Advance;
  end;
  // Aufrufkonventionen mit oder ohne Semikolon davor: procedure stdcall; procedure; cdecl
  while True do
    if IsIdent and InWords(Current.Text, CallingConventions) then
      Advance
    else if IsSym(';') and (PeekToken(1).Kind = TPascalTokenKind.Identifier) and
      InWords(PeekToken(1).Text, CallingConventions) then
      Advance
    else
      Break;
end;

procedure TParser.ParseClassBody(ANode: TSyntaxNode; AKind: TSyntaxKind);
begin
  // Nach class, object, interface oder helper: (Vorfahren), [GUID], Mitglieder, end.
  if IsSym('(') then
  begin
    Advance;
    while not AtEnd and not IsSym(')') do
    begin
      ParseTypeReference(ANode);
      if not AcceptSym(',') then
        Break;
    end;
    ExpectSym(')');
  end;
  if AKind = TSyntaxKind.HelperType then
  begin
    ExpectKw('for');
    ParseTypeReference(ANode);
  end;
  // Kurzform ohne Rumpf: TFehler = class(Exception);
  if IsSym(';') then
    Exit;
  if (AKind = TSyntaxKind.InterfaceType) and IsSym('[') then
  begin
    // GUID
    Advance;
    ParseExpression(ANode);
    ExpectSym(']');
  end;
  ParseMembers(ANode);
  ExpectKw('end');
end;

procedure TParser.ParseMembers(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
  Before: Integer;
begin
  while not AtEnd and not IsKw('end') do
  begin
    Before := FIndex;
    if IsIdent and InWords(Current.Text, VisibilityWords) and
      not PeekIsSym(1, ':') and not PeekIsSym(1, ',') then
    begin
      Start := NodeStart;
      Node := StartNode(TSyntaxKind.Visibility);
      Node.Name := LowerCase(Current.Text);
      Advance;
      if (Node.Name = 'strict') and IsIdent then
      begin
        Node.Name := 'strict ' + LowerCase(Current.Text);
        Advance;
      end;
      FinishNode(Node, Start);
      AParent.Add(Node);
    end
    else if IsSym('[') then
      ParseAttributes(AParent)
    else if IsKw('class') and PeekIsKw(1, 'var') then
    begin
      Advance;
      ParseVarSection(AParent);
    end
    else if IsKw('class') and PeekIsKw(1, 'property') then
    begin
      Advance;
      ParseProperty(AParent);
    end
    else if IsKw(['var', 'threadvar']) then
      ParseVarSection(AParent)
    else if IsKw(['const', 'resourcestring']) then
      ParseConstSection(AParent)
    else if IsKw('type') then
      ParseTypeSection(AParent)
    else if IsKw('property') then
      ParseProperty(AParent)
    else if IsRoutineStart then
      ParseRoutineHeader(AParent, TSyntaxKind.RoutineHeader)
    else if IsKw('case') then
      ParseVariantPart(AParent)
    else if IsIdent then
      ParseFieldDecl(AParent)
    else if IsKw(['begin', 'implementation', 'initialization', 'finalization']) or
      (IsKw(['type', 'var', 'const']) and FInImplementation) then
    begin
      // Fehlendes end: Mitgliederliste hier beenden.
      DiagnoseUnexpected('"end"');
      Exit;
    end
    else
      SkipError(AParent, TRecovery.Members);
    AcceptSym(';');
    if FIndex = Before then
      Advance;
  end;
end;

procedure TParser.ParseFieldDecl(AParent: TSyntaxNode);
begin
  ParseFieldDecl(AParent, False);
end;

procedure TParser.ParseFieldDecl(AParent: TSyntaxNode; AInVariant: Boolean);
var
  Start: Integer;
  Node: TSyntaxNode;
  Names: string;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.Field);
  AParent.Add(Node);
  Names := ExpectIdent;
  while AcceptSym(',') do
    Names := Names + ',' + ExpectIdent;
  Node.Name := Names;
  ExpectSym(':');
  ParseType(Node);
  ParseHints;
  // Das letzte Feld darf vor end bzw. vor der ")" eines varianten Zweigs ohne Semikolon stehen (#849).
  if not IsKw('end') and (not AInVariant or not IsSym(')')) then
    ExpectSym(';');
  FinishNode(Node, Start);
end;

procedure TParser.ParseProperty(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  // property Name[Index: Integer]: Typ read GetX write SetX default 0; default;
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.PropertyDecl);
  AParent.Add(Node);
  Advance; // property
  Node.Name := ExpectIdent;
  if IsSym('[') then
    ParseParameters(Node);
  if AcceptSym(':') then
    ParseTypeReference(Node);
  // Spezifizierer (read, write, index, default, stored, implements ...) bis ;
  while not AtEnd and not IsSym(';') and not IsKw('end') do
    Advance;
  ExpectSym(';');
  if IsIdentText('default') and PeekIsSym(1, ';') then
  begin
    Advance;
    Advance;
  end;
  FinishNode(Node, Start);
end;

procedure TParser.ParseVariantPart(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  // case [Tag:] Typ of Marken: (Felder); … (#846). Endet vor dem end des Records bzw. vor der ")" des
  // umschließenden Zweigs. VariantPart: Selektorfeld (Field) oder Selektortyp (TypeReference), dann je
  // Zweig ein CaseItem mit den Marken als Name und den Feldern (auch einem weiteren VariantPart).
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.VariantPart);
  AParent.Add(Node);
  if not EnterNesting then
  begin
    Node.Add(TooDeep);
    FinishNode(Node, Start);
    Exit;
  end;
  try
    ParseVariantBody(Node);
  finally
    Dec(FDepth);
  end;
  FinishNode(Node, Start);
end;

procedure TParser.ParseVariantBody(ANode: TSyntaxNode);
var
  FieldStart, ItemStart, Before: Integer;
  Selector, Item: TSyntaxNode;
  Labels: string;
begin
  Advance; // case
  if IsIdent and PeekIsSym(1, ':') then
  begin
    FieldStart := NodeStart;
    Selector := StartNode(TSyntaxKind.Field);
    ANode.Add(Selector);
    Selector.Name := ExpectIdent;
    ExpectSym(':');
    ParseTypeReference(Selector);
    FinishNode(Selector, FieldStart);
    ANode.Name := Selector.Name;
  end
  else
    ParseTypeReference(ANode);
  ExpectKw('of');
  while not AtEnd and not IsKw('end') and not IsSym(')') do
  begin
    Before := FIndex;
    ItemStart := NodeStart;
    Item := StartNode(TSyntaxKind.CaseItem);
    ANode.Add(Item);
    // Marken: Konstanten, Bereiche und Listen ("0", "1..3", "mkA, mkB").
    Labels := '';
    while not AtEnd and not IsSym(':') and not IsSym('(') and not IsSym(';') and not IsSym(')') and
      not IsKw('end') do
    begin
      if IsSym(',') then
        Labels := Labels + ', '
      else
        Labels := Labels + Current.Text;
      Advance;
    end;
    Item.Name := Labels;
    ExpectSym(':');
    if AcceptSym('(') then
    begin
      ParseVariantFields(Item);
      ExpectSym(')');
    end
    else
      DiagnoseUnexpected('"("');
    FinishNode(Item, ItemStart);
    AcceptSym(';');
    if FIndex = Before then
      Advance;
  end;
end;

procedure TParser.ParseVariantFields(AParent: TSyntaxNode);
var
  Before: Integer;
begin
  while not AtEnd and not IsSym(')') and not IsKw('end') do
  begin
    Before := FIndex;
    if IsKw('case') then
      ParseVariantPart(AParent)
    else if IsIdent then
      ParseFieldDecl(AParent, True)
    else
      DiagnoseUnexpected('Feldname');
    AcceptSym(';');
    if FIndex = Before then
      Advance;
  end;
end;

{ Anweisungen }

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
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.AsmBlock);
  AParent.Add(Node);
  Advance; // asm
  while not AtEnd and not IsKw('end') do
    Advance;
  ExpectKw('end');
  FinishNode(Node, Start);
end;

procedure TParser.ParseStatementList(AParent: TSyntaxNode; const ATerminators: array of string);
var
  Saved: TArray<string>;
  Index: Integer;
begin
  Saved := FTerminators;
  SetLength(FTerminators, Length(ATerminators));
  for Index := 0 to High(ATerminators) do
    FTerminators[Index] := ATerminators[Index];
  try
    ParseStatementsUntil(AParent);
  finally
    FTerminators := Saved;
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
      Continue;
    if AtEnd or IsKw(FTerminators) then
      Break;
    if FIndex = Before then
      // Die Anweisung hat nichts verbraucht: Token überspringen.
      SkipError(AParent, TRecovery.Statements)
    else if IsKw(['implementation', 'initialization', 'finalization']) or IsRoutineStart then
      // Fehlendes end: Der Rest gehört nicht mehr zu diesem Block.
      Break
    else
      DiagnoseMissingSemicolon;
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
var
  Start: Integer;
  Node: TSyntaxNode;
  Target: TSyntaxNode;
begin
  if AtEnd or IsSym(';') or IsKw(['end', 'until', 'except', 'finally', 'else']) then
    Exit; // leere Anweisung
  // Sprungmarke: Name: Anweisung
  if ((Current.Kind = TPascalTokenKind.Identifier) or (Current.Kind = TPascalTokenKind.Number)) and
    PeekIsSym(1, ':') then
  begin
    Start := NodeStart;
    Node := StartNode(TSyntaxKind.LabeledStatement);
    Node.Name := Current.Text;
    AParent.Add(Node);
    Advance;
    Advance;
    ParseStatement(Node);
    FinishNode(Node, Start);
    Exit;
  end;

  if IsKw('begin') then
    ParseBlock(AParent)
  else if IsKw('asm') then
    ParseAsm(AParent)
  else if IsKw('if') then
    ParseIf(AParent)
  else if IsKw('case') then
    ParseCase(AParent)
  else if IsKw('for') then
    ParseFor(AParent)
  else if IsKw('while') then
    ParseWhile(AParent)
  else if IsKw('repeat') then
    ParseRepeat(AParent)
  else if IsKw('with') then
    ParseWith(AParent)
  else if IsKw('try') then
    ParseTry(AParent)
  else if IsKw('raise') then
    ParseRaise(AParent)
  else if IsKw(['var', 'const']) then
    ParseInlineDecl(AParent)
  else if IsKw('goto') then
  begin
    Start := NodeStart;
    Node := StartNode(TSyntaxKind.GotoStatement);
    AParent.Add(Node);
    Advance;
    if not AtEnd and not IsSym(';') then
    begin
      Node.Name := Current.Text;
      Advance;
    end;
    FinishNode(Node, Start);
  end
  else if IsKw(['inherited', 'nil', 'string', 'not', 'procedure', 'function']) or
    not (Current.Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Unknown]) then
  begin
    // Zuweisung oder Aufruf
    Start := NodeStart;
    Node := StartNode(TSyntaxKind.CallStatement);
    Target := ParseExpression(Node);
    if AcceptSym(':=') then
    begin
      Node.Kind := TSyntaxKind.AssignStatement;
      ParseExpression(Node);
    end;
    Node.Name := Target.Name;
    FinishNode(Node, Start);
    AParent.Add(Node);
  end;
  // Andere Schlüsselwörter: Der Aufrufer überspringt sie.
end;

procedure TParser.ParseIf(AParent: TSyntaxNode);
var
  Parent: TSyntaxNode;
  Nodes: TList<TSyntaxNode>;
  Starts: TList<Integer>;
  Index: Integer;
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
      ParseStatement(Nodes.Last);
      if not AcceptKw('else') then
        Break;
      if not IsKw('if') then
      begin
        ParseStatement(Nodes.Last);
        Break;
      end;
      Parent := Nodes.Last;
    until False;
    for Index := Nodes.Count - 1 downto 0 do
      FinishNode(Nodes[Index], Starts[Index]);
  finally
    Starts.Free;
    Nodes.Free;
  end;
end;

procedure TParser.ParseCase(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
  ItemStart: Integer;
  Item: TSyntaxNode;
  Before: Integer;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.CaseStatement);
  AParent.Add(Node);
  Advance; // case
  ParseExpression(Node);
  ExpectKw('of');
  while not AtEnd and not IsKw(['end', 'else']) do
  begin
    Before := FIndex;
    ItemStart := NodeStart;
    Item := StartNode(TSyntaxKind.CaseItem);
    Node.Add(Item);
    // Marken: 1, 2..5, 'a':
    repeat
      ParseExpression(Item);
      if AcceptSym('..') then
        ParseExpression(Item);
    until not AcceptSym(',');
    ExpectSym(':');
    ParseStatement(Item);
    FinishNode(Item, ItemStart);
    if not AcceptSym(';') and not IsKw(['end', 'else']) then
    begin
      DiagnoseMissingSemicolon;
      if FIndex = Before then
        Advance;
      if IsKw(['implementation', 'initialization', 'finalization']) or IsRoutineStart then
        Break;
    end;
  end;
  if IsKw('else') then
  begin
    ItemStart := NodeStart;
    Item := StartNode(TSyntaxKind.CaseElse);
    Node.Add(Item);
    Advance;
    ParseStatementList(Item, ['end']);
    FinishNode(Item, ItemStart);
  end;
  ExpectKw('end');
  FinishNode(Node, Start);
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
  Node.Name := ExpectIdent;
  if AcceptSym(':') then
    ParseTypeReference(Node);
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
      ExpectKw('downto');
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
  HandlerStart: Integer;
  Handler: TSyntaxNode;
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
        HandlerStart := NodeStart;
        Handler := StartNode(TSyntaxKind.ExceptionHandler);
        Part.Add(Handler);
        Advance; // on
        if PeekIsSym(1, ':') then
        begin
          Handler.Name := Current.Text;
          Advance;
          Advance;
        end;
        ParseTypeReference(Handler);
        ExpectKw('do');
        ParseStatement(Handler);
        FinishNode(Handler, HandlerStart);
        AcceptSym(';');
      end;
      if AcceptKw('else') then
        ParseStatementList(Part, ['end']);
    end
    else
      ParseStatementList(Part, ['end']);
    FinishNode(Part, PartStart);
  end
  else
    DiagnoseUnexpected('"except" oder "finally"');
  ExpectKw('end');
  FinishNode(Node, Start);
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
  Node: TSyntaxNode;
  Names: string;
begin
  // var X: Integer := 1; var A, B: string; const C = 5; var Y := Ausdruck;
  Start := NodeStart;
  if IsKw('const') then
    Node := StartNode(TSyntaxKind.InlineConst)
  else
    Node := StartNode(TSyntaxKind.InlineVar);
  AParent.Add(Node);
  Advance;
  Names := ExpectIdent;
  while AcceptSym(',') do
    Names := Names + ',' + ExpectIdent;
  Node.Name := Names;
  if AcceptSym(':') then
    ParseType(Node);
  if AcceptSym(':=') or AcceptSym('=') then
    ParseExpression(Node);
  FinishNode(Node, Start);
end;

{ Ausdrücke }

function TParser.Binary(const AOperator: string; ALeft, ARight: TSyntaxNode; AStartIndex: Integer): TSyntaxNode;
begin
  Result := StartNode(TSyntaxKind.BinaryExpr);
  Result.Name := AOperator;
  Result.Add(ALeft);
  Result.Add(ARight);
  FinishNode(Result, AStartIndex);
end;

function TParser.ParseExpression(AParent: TSyntaxNode): TSyntaxNode;
var
  Start: Integer;
  Op: string;
begin
  // Vergleich: = <> < > <= >= in is, ab Delphi 13 auch "is not" und "not in" (#109)
  Start := NodeStart;
  Result := ParseSimpleExpression;
  while (not AtEnd and (Current.Kind = TPascalTokenKind.Symbol) and InWords(Current.Text, RelationalOperators)) or
    IsKw(['in', 'is']) or (IsKw('not') and PeekIsKw(1, 'in')) do
  begin
    Op := LowerCase(Current.Text);
    Advance;
    if (Op = 'is') and IsKw('not') then
    begin
      Op := 'is not';
      Advance;
    end
    else if Op = 'not' then
    begin
      Op := 'not in';
      Advance;
    end;
    Result := Binary(Op, Result, ParseSimpleExpression, Start);
  end;
  if AParent <> nil then
    AParent.Add(Result);
end;

function TParser.ParseSimpleExpression: TSyntaxNode;
var
  Start: Integer;
  Op: string;
begin
  // + - or xor
  Start := NodeStart;
  Result := ParseTerm;
  while (not AtEnd and (Current.Kind = TPascalTokenKind.Symbol) and InWords(Current.Text, AdditiveSymbols)) or
    IsKw(['or', 'xor']) do
  begin
    Op := LowerCase(Current.Text);
    Advance;
    Result := Binary(Op, Result, ParseTerm, Start);
  end;
end;

function TParser.ParseTerm: TSyntaxNode;
var
  Start: Integer;
  Op: string;
begin
  // * / div mod and shl shr as
  Start := NodeStart;
  Result := ParseFactor;
  while (not AtEnd and (Current.Kind = TPascalTokenKind.Symbol) and InWords(Current.Text, MultiplicativeSymbols)) or
    IsKw(['div', 'mod', 'and', 'shl', 'shr', 'as']) do
  begin
    Op := LowerCase(Current.Text);
    Advance;
    Result := Binary(Op, Result, ParseFactor, Start);
  end;
end;

function TParser.EnterNesting: Boolean;
begin
  Result := FDepth < MaxNesting;
  if Result then
    Inc(FDepth);
end;

function TParser.TooDeep: TSyntaxNode;
var
  Start: Integer;
begin
  // Schutz vor Stapelüberlauf: Der Rest der Datei wird nicht mehr ausgewertet.
  Diagnose(Format('Zu tief verschachtelt (mehr als %d Ebenen); Rest der Datei nicht ausgewertet', [MaxNesting]));
  Start := NodeStart;
  Result := StartNode(TSyntaxKind.Error);
  FIndex := Length(FTokens);
  FinishNode(Result, Start);
end;

function TParser.ParseFactor: TSyntaxNode;
begin
  if not EnterNesting then
    Exit(TooDeep);
  try
    Result := ParseFactorBody;
  finally
    Dec(FDepth);
  end;
end;

function TParser.ParseFactorBody: TSyntaxNode;
var
  Start: Integer;
begin
  Start := NodeStart;
  if IsKw('not') or IsSym('-') or IsSym('+') then
  begin
    Result := StartNode(TSyntaxKind.UnaryExpr);
    Result.Name := LowerCase(Current.Text);
    Advance;
    Result.Add(ParseFactor);
    FinishNode(Result, Start);
  end
  else if IsSym('@') then
  begin
    Result := StartNode(TSyntaxKind.AddressOf);
    Advance;
    Result.Add(ParseFactor);
    FinishNode(Result, Start);
  end
  else if IsKw('if') then
  begin
    // Bedingter Ausdruck: if Bedingung then A else B
    Result := StartNode(TSyntaxKind.IfExpr);
    Advance;
    ParseExpression(Result);
    ExpectKw('then');
    ParseExpression(Result);
    ExpectKw('else');
    ParseExpression(Result);
    FinishNode(Result, Start);
  end
  else
    Result := ParsePrimary;
end;

function TParser.LooksLikeGenericArgs: Boolean;
var
  Delta: Integer;
  Depth: Integer;
  Token: TPascalToken;
begin
  // Steht auf "<". Generische Argumente bestehen nur aus Bezeichnern, Punkten,
  // Kommas, string und verschachtelten <>; danach folgt kein Operand.
  Delta := 0;
  Depth := 0;
  repeat
    Token := PeekToken(Delta);
    if Token.IsSymbol('<') then
      Inc(Depth)
    else if Token.IsSymbol('>') then
      Dec(Depth)
    else if not ((Token.Kind = TPascalTokenKind.Identifier) or Token.IsSymbol('.') or Token.IsSymbol(',') or
      Token.IsKeyword('string')) then
      Exit(False);
    Inc(Delta);
  until (Depth = 0) or (FIndex + Delta >= Length(FTokens));
  if Depth <> 0 then
    Exit(False);
  Token := PeekToken(Delta);
  Result := not (Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number,
    TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]);
end;

procedure TParser.ParseGenericArgs(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.GenericArgs);
  AParent.Add(Node);
  Advance; // <
  while not AtEnd and not IsSym('>') do
  begin
    ParseTypeReference(Node);
    if not AcceptSym(',') then
      Break;
  end;
  ExpectSym('>');
  FinishNode(Node, Start);
end;

procedure TParser.ParseArguments(AParent: TSyntaxNode; const ACloser: string);
begin
  // Steht hinter ( oder [. Write(X:10:2) erlaubt Formatangaben.
  while not AtEnd and not IsSym(ACloser) do
  begin
    // Benanntes Argument der OLE-Automation: Open(FileName := 'a.docx') (#849); der Name gehört zur
    // Schnittstelle des Servers und wird nicht aufgelöst.
    if IsIdent and PeekIsSym(1, ':=') then
    begin
      Advance;
      Advance;
    end;
    ParseExpression(AParent);
    while AcceptSym(':') do
      ParseExpression(AParent);
    if not AcceptSym(',') then
      Break;
  end;
  ExpectSym(ACloser);
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
    ParseParameters(Result);
  if AcceptSym(':') then
    ParseTypeReference(Result);
  // Lokale Abschnitte und Routinen vor dem begin (#849).
  while IsKw(['var', 'const', 'type', 'label']) or IsRoutineStart do
    if IsRoutineStart then
      ParseRoutine(Result, True)
    else
      ParseDeclaration(Result);
  ParseBlock(Result);
  FinishNode(Result, Start);
end;

function TParser.ParsePrimary: TSyntaxNode;
var
  Start: Integer;
  Node: TSyntaxNode;
  ElementStart: Integer;
  Text: string;
begin
  Start := NodeStart;
  if AtEnd then
  begin
    DiagnoseUnexpected('Ausdruck');
    Result := StartNode(TSyntaxKind.Error);
    FinishNode(Result, Start);
    Exit;
  end;

  case Current.Kind of
    TPascalTokenKind.Identifier:
      Result := Leaf(TSyntaxKind.Identifier, Current.Text);
    TPascalTokenKind.Number:
      Result := Leaf(TSyntaxKind.Literal, Current.Text);
    // {$I datei.inc} als Wert (#849): Literal mit dem Text der Direktive.
    TPascalTokenKind.Directive:
      Result := Leaf(TSyntaxKind.Literal, Current.Text);
    TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral:
      begin
        // 'a'#13'b' ist ein einziges Literal.
        Text := '';
        while not AtEnd and (Current.Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]) do
        begin
          Text := Text + Current.Text;
          Advance;
        end;
        Result := StartNode(TSyntaxKind.Literal);
        Result.Name := Text;
        FinishNode(Result, Start);
      end;
  else
    if IsKw('nil') then
      Result := Leaf(TSyntaxKind.Literal, 'nil')
    else if IsKw('inherited') then
    begin
      Result := StartNode(TSyntaxKind.InheritedExpr);
      Advance;
      if IsIdent then
        Result.Name := Current.Text;
      if IsIdent then
        Advance;
      FinishNode(Result, Start);
    end
    else if IsKw('string') then
      Result := Leaf(TSyntaxKind.Identifier, Current.Text)
    else if IsKw(['procedure', 'function']) then
      Result := ParseAnonymousMethod
    else if IsSym('(') then
    begin
      Result := StartNode(TSyntaxKind.ParenExpr);
      Advance;
      ParseExpression(Result);
      // Record-Konstanten: (X: 1; Y: 2) und Array-Konstanten: (1, 2, 3)
      while AcceptSym(',') or AcceptSym(';') or AcceptSym(':') do
        if not IsSym(')') then
          ParseExpression(Result);
      ExpectSym(')');
      FinishNode(Result, Start);
    end
    else if IsSym('[') then
    begin
      Result := StartNode(TSyntaxKind.SetConstructor);
      Advance;
      while not AtEnd and not IsSym(']') do
      begin
        ElementStart := NodeStart;
        Node := ParseExpression(Result);
        if AcceptSym('..') then
        begin
          // Bereich a..b
          Result.Extract(Node);
          Node := Binary('..', Node, ParseExpression(nil), ElementStart);
          Node.Kind := TSyntaxKind.RangeExpr;
          Result.Add(Node);
        end;
        if not AcceptSym(',') then
          Break;
      end;
      ExpectSym(']');
      FinishNode(Result, Start);
    end
    else
    begin
      DiagnoseUnexpected('Ausdruck');
      Result := StartNode(TSyntaxKind.Error);
      FinishNode(Result, Start);
      Exit;
    end;
  end;

  // Nachgestellte Teile: .Name, (Argumente), [Index], ^, <Typen>
  while not AtEnd do
  begin
    if IsSym('.') and (PeekToken(1).Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
    begin
      Node := StartNode(TSyntaxKind.MemberAccess);
      Node.Add(Result);
      Advance;
      Node.Name := Current.Text;
      Advance;
    end
    else if IsSym('(') then
    begin
      Node := StartNode(TSyntaxKind.Call);
      Node.Name := Result.Name;
      Node.Add(Result);
      Advance;
      ParseArguments(Node, ')');
    end
    else if IsSym('[') then
    begin
      Node := StartNode(TSyntaxKind.IndexAccess);
      Node.Name := Result.Name;
      Node.Add(Result);
      Advance;
      ParseArguments(Node, ']');
    end
    else if IsSym('^') then
    begin
      Node := StartNode(TSyntaxKind.Dereference);
      Node.Add(Result);
      Advance;
    end
    else if IsSym('<') and (Result.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
      LooksLikeGenericArgs then
    begin
      Node := StartNode(TSyntaxKind.MemberAccess);
      Node.Name := Result.Name;
      Node.Add(Result);
      ParseGenericArgs(Node);
    end
    else
      Break;
    FinishNode(Node, Start);
    Result := Node;
  end;
end;

{ TPascalParser }

class function TPascalParser.IncludeAsValue(const APrevious: TPascalToken): Boolean;
const
  ValueStarts: array[0..8] of string = ('=', ':=', '(', ',', '[', '+', '-', '*', '/');
begin
  Result := (APrevious.Kind = TPascalTokenKind.Symbol) and InWords(APrevious.Text, ValueStarts);
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
  Parser: TParser;
begin
  AConditionals := nil;
  // Schnell: ohne bedingte Direktive gibt es nichts zu überspringen.
  if not TPascalPreprocessor.HasConditionals(AText) then
    Exit(Parse(AText, ACancellation));
  Processed := TPascalPreprocessor.Process(AText, TPascalPreprocessor.EditorOptions(ADefines));
  AConditionals := TPascalPreprocessor.MainConditionals(Processed);
  Parser := TParser.Create(AText, ACancellation, TPascalPreprocessor.MainInactive(Processed));
  try
    Result := Parser.Run;
  finally
    Parser.Free;
  end;
end;

class function TPascalParser.ParseActive(const AText: string; const ADefines: TArray<string>): TSyntaxTree;
var
  Conditionals: TArray<TConditionalRange>;
begin
  Result := ParseActive(AText, ADefines, nil, Conditionals);
end;

class function TPascalParser.ActiveDiagnostics(const AText: string; const ADefines: TArray<string>;
  out ADiagnostics: TArray<TSyntaxDiagnostic>): Boolean;
var
  Skip: TArray<TTextRange>;
  Parser: TParser;
  Tree: TSyntaxTree;
begin
  ADiagnostics := nil;
  if not TPascalPreprocessor.HasConditionals(AText) then
    Exit(False);
  Skip := TPascalPreprocessor.MainInactive(TPascalPreprocessor.Process(AText,
    TPascalPreprocessor.EditorOptions(ADefines)));
  if Skip = nil then
    Exit(False);
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
