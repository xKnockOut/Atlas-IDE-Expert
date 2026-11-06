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
  Atlas.Common.Pascal.Parser.Types,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TPascalParserText = (StatementsAreNotAllowedIn, BeforeElseIsNotAllowed, ExceptOrFinally, FileName, Remove,
    VariableName);

const
  cTexts: array[TPascalParserText] of TAtlasText = (
    (De: 'Anweisungen sind im interface-Teil nicht erlaubt'; En: 'Statements are not allowed in the interface part'),
    (De: ''';'' vor ''else'' ist nicht erlaubt'; En: ''';'' before ''else'' is not allowed'),
    (De: '"except" oder "finally"'; En: '"except" or "finally"'),
    (De: 'Dateiname'; En: 'file name'),
    (De: ''';'' entfernen'; En: 'Remove '';'''),
    (De: 'Variablenname'; En: 'variable name'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Ganze Datei, Abschnitte und Anweisungen; Spitze der Kette Cursor, Ausdrücke, Deklarationen,
  /// Typen.</summary>
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
  mRoot: TSyntaxNode;
begin
  mRoot := ParseFile;
  CheckTokensAndTree(mRoot);
  Result := TSyntaxTree.Create(mRoot, FAllTokens, FDiagnostics.ToArray);
end;

function TParser.ParseFile: TSyntaxNode;
var
  mStart: Integer;
begin
  mStart := NodeStart;
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
  FinishNode(Result, mStart);
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
    DiagnoseCode('E2050', cTexts[TPascalParserText.StatementsAreNotAllowedIn].Text, Current.StartPos, Current.EndPos);
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
  mStart: Integer;
  mItemStart: Integer;
  mNode: TSyntaxNode;
  mItem: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.UsesClause);
  AParent.Add(mNode);
  Advance; // uses, contains oder requires
  repeat
    mItemStart := NodeStart;
    mItem := StartNode(TSyntaxKind.UsedUnit);
    mItem.Name := ParseQualifiedName;
    if AcceptKw('in') then
    begin
      if Current.Kind = TPascalTokenKind.StringLiteral then
      begin
        Advance;
      end
      else
      begin
        DiagnoseUnexpected(cTexts[TPascalParserText.FileName].Text);
      end;
    end;
    FinishNode(mItem, mItemStart);
    mNode.Add(mItem);
    if mItem.Name = '' then
    begin
      Break;
    end;
  until not AcceptSym(',');
  ExpectSym(';');
  FinishNode(mNode, mStart);
end;

procedure TParser.ParseInterfaceSection(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.InterfaceSection);
  AParent.Add(mNode);
  ExpectKw('interface');
  FInImplementation := False;
  if IsKw('uses') then
  begin
    ParseUses(mNode);
  end;
  ParseDeclarations(mNode);
  FinishNode(mNode, mStart);
end;

procedure TParser.ParseImplementationSection(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.ImplementationSection);
  AParent.Add(mNode);
  ExpectKw('implementation');
  FInImplementation := True;
  if IsKw('uses') then
  begin
    ParseUses(mNode);
  end;
  ParseDeclarations(mNode);
  FinishNode(mNode, mStart);
end;

procedure TParser.ParseStatementSection(AParent: TSyntaxNode; AKind: TSyntaxKind);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(AKind);
  AParent.Add(mNode);
  Advance; // initialization, finalization oder begin
  ParseStatementList(mNode, ['finalization', 'end']);
  FinishNode(mNode, mStart);
end;

procedure TParser.ParseRoutineBody(AParent: TSyntaxNode; AWithBody: Boolean);
var
  mStart: Integer;
  mNode: TSyntaxNode;
  mHeader: TSyntaxNode;
  mIndex: Integer;
  mNoBody: Boolean;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.RoutineDecl);
  AParent.Add(mNode);
  mHeader := ParseRoutineHeader(mNode, TSyntaxKind.RoutineHeader);
  mNode.Name := mHeader.Name;
  mNoBody := False;
  for mIndex := 0 to mHeader.ChildCount - 1 do
  begin
    if (mHeader.Children[mIndex].Kind = TSyntaxKind.Directive) and
      ((mHeader.Children[mIndex].Name = 'forward') or (mHeader.Children[mIndex].Name = 'external')) then
    begin
      mNoBody := True;
    end;
  end;
  if AWithBody and not mNoBody then
  begin
    // Lokale Deklarationen, dann der Rumpf. exports ist hier ein Fehler des Compilers (E2191), aber kein
    // Syntaxfehler: Der Baum behält die Klausel, damit exports-invalid sie melden kann.
    while not AtEnd and (IsKw(['type', 'const', 'resourcestring', 'var', 'threadvar', 'label', 'exports']) or
      IsRoutineStart or IsSym('[')) do
    begin
      ParseDeclaration(mNode);
    end;
    if IsKw('asm') then
    begin
      ParseAsm(mNode);
    end
    else if IsKw('begin') then
    begin
      ParseBlock(mNode);
    end
    else
    begin
      DiagnoseUnexpected('"begin"');
    end;
    ExpectSym(';');
  end;
  FinishNode(mNode, mStart);
end;

procedure TParser.ParseBlock(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  if IsKw('asm') then
  begin
    ParseAsm(AParent);
    Exit;
  end;
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.Block);
  AParent.Add(mNode);
  ExpectKw('begin');
  ParseStatementList(mNode, ['end']);
  ExpectKw('end');
  FinishNode(mNode, mStart);
end;

procedure TParser.ParseAsm(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  // Assembler wird nicht ausgewertet: bis zum nächsten end überspringen.
  // Sprungmarken wie @@End liefert der Lexer als Bezeichner (#861).
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.AsmBlock);
  AParent.Add(mNode);
  Advance; // asm
  while not AtEnd and not IsKw('end') do
  begin
    Advance;
  end;
  ExpectKw('end');
  FinishNode(mNode, mStart);
end;

procedure TParser.ParseStatementList(AParent: TSyntaxNode; const ATerminators: array of string);
var
  mSaved: TArray<string>;
  mIndex: Integer;
  mSavedInCase: Boolean;
begin
  mSaved := FTerminators;
  mSavedInCase := FInCaseItem;
  FInCaseItem := False;
  SetLength(FTerminators, Length(ATerminators));
  for mIndex := 0 to High(ATerminators) do
  begin
    FTerminators[mIndex] := ATerminators[mIndex];
  end;
  try
    ParseStatementsUntil(AParent);
  finally
    FTerminators := mSaved;
    FInCaseItem := mSavedInCase;
  end;
end;

procedure TParser.ParseStatementsUntil(AParent: TSyntaxNode);
var
  mBefore: Integer;
begin
  while not AtEnd and not IsKw(FTerminators) do
  begin
    mBefore := FIndex;
    ParseStatement(AParent);
    if AcceptSym(';') then
    begin
      Continue;
    end;
    if AtEnd or IsKw(FTerminators) then
    begin
      Break;
    end;
    if FIndex = mBefore then
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
  mParent: TSyntaxNode;
  mNodes: TList<TSyntaxNode>;
  mStarts: TList<Integer>;
  mIndex, mBefore: Integer;
  mEmpty: TSyntaxNode;
begin
  // else if-Ketten in einer Schleife statt rekursiv (#849): Jedes "else if" wird wie bisher ein
  // IfStatement im else-Zweig des vorigen, zählt aber nicht als weitere Ebene für MaxNesting.
  mNodes := TList<TSyntaxNode>.Create;
  mStarts := TList<Integer>.Create;
  try
    mParent := AParent;
    repeat
      mStarts.Add(NodeStart);
      mNodes.Add(StartNode(TSyntaxKind.IfStatement));
      mParent.Add(mNodes.Last);
      Advance; // if
      ParseExpression(mNodes.Last);
      ExpectKw('then');
      mBefore := mNodes.Last.ChildCount;
      ParseStatement(mNodes.Last);
      // if A then B; else C – außer in case- und on-Zweigen, wo "; else" deren else-Teil beginnt (#1022).
      if IsSym(';') and PeekIsKw(1, 'else') and not FInCaseItem then
      begin
        DiagnoseCode('E2153', cTexts[TPascalParserText.BeforeElseIsNotAllowed].Text, Current.StartPos, Current.EndPos,
          TParserFix.Create(cTexts[TPascalParserText.Remove].Text, Current.StartPos, Current.EndPos, '', True));
        Advance;
      end;
      // Leerer then-Zweig vor else (if A then else B): eine leere Anweisung hält seinen Platz, sonst stünde der
      // else-Zweig als then-Zweig im Baum.
      if IsKw('else') and (mNodes.Last.ChildCount = mBefore) then
      begin
        mEmpty := StartNode(TSyntaxKind.EmptyStatement);
        mNodes.Last.Add(mEmpty);
        FinishNode(mEmpty, FIndex);
      end;
      if not AcceptKw('else') then
      begin
        Break;
      end;
      if not IsKw('if') then
      begin
        ParseStatement(mNodes.Last);
        Break;
      end;
      mParent := mNodes.Last;
    until False;
    for mIndex := mNodes.Count - 1 downto 0 do
    begin
      FinishNode(mNodes[mIndex], mStarts[mIndex]);
    end;
  finally
    mStarts.Free;
    mNodes.Free;
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
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  // for [var] I [: Typ] := A to|downto B do ...; for [var] X in Liste do ...
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.ForStatement);
  AParent.Add(mNode);
  Advance; // for
  AcceptKw('var');
  if IsIdent then
  begin
    mNode.Name := ExpectIdent;
  end
  else
  begin
    DiagnoseUnexpected('E2088', cTexts[TPascalParserText.VariableName].Text);
  end;
  if AcceptSym(':') then
  begin
    ParseTypeReference(mNode);
  end;
  if AcceptKw('in') then
  begin
    mNode.Kind := TSyntaxKind.ForInStatement;
    ParseExpression(mNode);
  end
  else
  begin
    ExpectSym(':=');
    ParseExpression(mNode);
    if not AcceptKw('to') then
    begin
      ExpectKw('downto');
      mNode.Descending := True;
    end;
    ParseExpression(mNode);
  end;
  ExpectKw('do');
  ParseStatement(mNode);
  FinishNode(mNode, mStart);
end;

procedure TParser.ParseWhile(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.WhileStatement);
  AParent.Add(mNode);
  Advance; // while
  ParseExpression(mNode);
  ExpectKw('do');
  ParseStatement(mNode);
  FinishNode(mNode, mStart);
end;

procedure TParser.ParseRepeat(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.RepeatStatement);
  AParent.Add(mNode);
  Advance; // repeat
  ParseStatementList(mNode, ['until', 'end']);
  ExpectKw('until');
  ParseExpression(mNode);
  FinishNode(mNode, mStart);
end;

procedure TParser.ParseWith(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.WithStatement);
  AParent.Add(mNode);
  Advance; // with
  repeat
    ParseExpression(mNode);
  until not AcceptSym(',');
  ExpectKw('do');
  ParseStatement(mNode);
  FinishNode(mNode, mStart);
end;

procedure TParser.ParseTry(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
  mPartStart: Integer;
  mPart: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.TryStatement);
  AParent.Add(mNode);
  Advance; // try
  ParseStatementList(mNode, ['except', 'finally', 'end']);
  mPartStart := NodeStart;
  if AcceptKw('finally') then
  begin
    mPart := StartNode(TSyntaxKind.FinallyBlock);
    mNode.Add(mPart);
    ParseStatementList(mPart, ['end']);
    FinishNode(mPart, mPartStart);
  end
  else if AcceptKw('except') then
  begin
    mPart := StartNode(TSyntaxKind.ExceptBlock);
    mNode.Add(mPart);
    if IsIdentText('on') then
    begin
      // on E: Exception do ...; on EFoo do ...; else ...
      while IsIdentText('on') do
      begin
        ParseExceptionHandler(mPart);
      end;
      if AcceptKw('else') then
      begin
        ParseStatementList(mPart, ['end']);
      end;
    end
    else
    begin
      ParseStatementList(mPart, ['end']);
    end;
    FinishNode(mPart, mPartStart);
  end
  else
  begin
    DiagnoseUnexpected('E2125', cTexts[TPascalParserText.ExceptOrFinally].Text);
  end;
  ExpectKw('end');
  FinishNode(mNode, mStart);
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
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.RaiseStatement);
  AParent.Add(mNode);
  Advance; // raise
  if not AtEnd and not IsSym(';') and not IsKw(['end', 'else', 'until', 'except', 'finally']) then
  begin
    ParseExpression(mNode);
    if IsIdentText('at') then
    begin
      Advance;
      ParseExpression(mNode);
    end;
  end;
  FinishNode(mNode, mStart);
end;

procedure TParser.ParseInlineDecl(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode, mAttributes: TSyntaxNode;
  mNames: string;
begin
  // var X: Integer := 1; var A, B: string; const C = 5; var Y := Ausdruck;
  mStart := NodeStart;
  if IsKw('const') then
  begin
    mNode := StartNode(TSyntaxKind.InlineConst);
  end
  else
  begin
    mNode := StartNode(TSyntaxKind.InlineVar);
  end;
  AParent.Add(mNode);
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
  mNames := ExpectIdent;
  while AcceptSym(',') do
  begin
    mNames := mNames + ',' + ExpectIdent;
  end;
  mNode.Name := mNames;
  if AcceptSym(':') then
  begin
    ParseType(mNode);
  end;
  if AcceptSym(':=') or AcceptSym('=') then
  begin
    ParseExpression(mNode);
  end;
  FinishNode(mNode, mStart);
end;

function TParser.ParseAnonymousMethod: TSyntaxNode;
var
  mStart: Integer;
begin
  // procedure(A: Integer) begin ... end; function: Integer begin ... end
  mStart := NodeStart;
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
  while IsIdent and InWords(Current.Text, cCallingConventions) do
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
  FinishNode(Result, mStart);
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
  mParser: TParser;
begin
  mParser := TParser.Create(AText, ACancellation);
  try
    Result := mParser.Run;
  finally
    mParser.Free;
  end;
end;


class function TPascalParser.ParseActive(const AText: string; const ADefines: TArray<string>;
  const ACancellation: IPascalCancellation; out AConditionals: TArray<TConditionalRange>): TSyntaxTree;
var
  mProcessed: TPreprocessorResult;
begin
  Result := ParseActive(AText, TPascalPreprocessor.EditorOptions(ADefines), ACancellation, mProcessed);
  AConditionals := TPascalPreprocessor.MainConditionals(mProcessed);
end;

class function TPascalParser.ParseActive(const AText: string; const AOptions: TPreprocessorOptions;
  const ACancellation: IPascalCancellation; out AProcessed: TPreprocessorResult): TSyntaxTree;
var
  mParser: TParser;
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
    mParser := TParser.Create(AText, ACancellation, TPascalPreprocessor.MainInactive(AProcessed));
    try
      Result := mParser.Run;
    finally
      mParser.Free;
    end;
  end;
  Result.Platform := TPascalPreprocessor.PlatformOf(AOptions.Defines);
end;

class function TPascalParser.ParseActive(const AText: string; const ADefines: TArray<string>): TSyntaxTree;
var
  mConditionals: TArray<TConditionalRange>;
begin
  Result := ParseActive(AText, ADefines, nil, mConditionals);
end;

class function TPascalParser.ActiveDiagnostics(const AText: string; const ADefines: TArray<string>;
  out ADiagnostics: TArray<TSyntaxDiagnostic>): Boolean;
begin
  Result := ActiveDiagnostics(AText, TPascalPreprocessor.EditorOptions(ADefines), ADiagnostics);
end;

class function TPascalParser.ActiveDiagnostics(const AText: string; const AOptions: TPreprocessorOptions;
  out ADiagnostics: TArray<TSyntaxDiagnostic>): Boolean;
var
  mSkip: TArray<TTextRange>;
  mParser: TParser;
  mTree: TSyntaxTree;
begin
  ADiagnostics := nil;
  if not TPascalPreprocessor.HasConditionals(AText) then
  begin
    Exit(False);
  end;
  mSkip := TPascalPreprocessor.MainInactive(TPascalPreprocessor.Process(AText, AOptions));
  if mSkip = nil then
  begin
    Exit(False);
  end;
  mParser := TParser.Create(AText, nil, mSkip);
  try
    mTree := mParser.Run;
    try
      ADiagnostics := mTree.Diagnostics;
    finally
      mTree.Free;
    end;
  finally
    mParser.Free;
  end;
  Result := True;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Pascal.Parser', cTexts);

end.
