unit Atlas.Common.Editing.Extract;

// Extrahieren (#50, Teil A) als Code-Aktionen, ohne Protokollbezug:
//   - „Methode extrahieren“: Die markierten Anweisungen (vollständig, aus
//     einer Anweisungsliste) werden zu einer neuen Methode der Klasse bzw.
//     zu einer Routine vor der umgebenden. Die Datenflussanalyse im Rumpf
//     entscheidet über die Parameter: nur gelesen → const, geschrieben und
//     danach gelesen → var, bei unbedingtem ersten Schreiben out; geschrieben,
//     aber danach nicht mehr gebraucht → Wertparameter bzw. lokale Variable;
//     nur innen verwendet → lokale Variable der neuen Methode (aus dem alten
//     var-Abschnitt entfernt). Lokale Konstanten werden mitkopiert. Liegt die
//     Auswahl in einer Schleife, gelten Zugriffe in der Schleife vor der
//     Auswahl als „danach“.
//   - „Variable einführen“: Der markierte Ausdruck wird in eine Variable vor
//     der Anweisung ausgelagert; auf Wunsch alle textgleichen Vorkommen im
//     selben Block, solange dazwischen keiner seiner Namen geändert wird.
//   - „Konstante extrahieren“: Das Literal wird zu einer Konstante im
//     const-Abschnitt der Routine bzw. vor der Routine in der Unit.
// Inline-Variable (var X := …) oder Eintrag im var-Abschnitt entscheidet
// TExtractOptions.InlineVar (refactoring.inlineVar und Sprachversion, #109).
// Für einen Eintrag im var-Abschnitt braucht es den Typ: Literale, einfache
// Operatoren und Bezeichner der Datei kennt die Unit selbst, den Rest fragt
// sie über TExtractOptions.Probe (Namensauflösung des Servers).
//
// Nicht angeboten wird: keine vollständige Anweisungsfolge bzw. kein
// vollständiger Ausdruck; Exit, Break, Continue oder goto mit Ziel außerhalb
// der Auswahl; Result (die neue Methode hätte ein zweites Ergebnis); asm;
// with in oder um der Auswahl; verschachtelte Routinen oder lokale Typen der
// umgebenden Routine; eine in der Auswahl deklarierte Inline-Variable, die
// danach noch gebraucht wird; ein unbekannter Typ; eine anonyme Methode, die
// einen künftigen var-Parameter einfängt.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.CodeActions;

const
  /// <summary>Art der Extrahieren-Aktionen (LSP).</summary>
  ExtractKind = 'refactor.extract';

type
  /// <summary>Typ eines Ausdrucks laut Namensauflösung.</summary>
  TProbedType = record
    /// <summary>Typ wie im Quelltext; '' unbekannt.</summary>
    Name: string;
    /// <summary>Unit, die für den Typ ins uses muss; '' wenn er sichtbar ist.</summary>
    UnitName: string;
    /// <summary>Klasse, Interface oder Zeiger: Eine Kopie zeigt auf dasselbe Objekt.</summary>
    IsReference: Boolean;
    /// <summary>Record oder anderer Werttyp: Eine Kopie ist ein eigener Wert.</summary>
    IsValue: Boolean;
    /// <summary>Record (bzw. object): für const-Parameter (#472).</summary>
    IsRecord: Boolean;
    /// <summary>Interface: für const-Parameter und weil es keine Rümpfe hat (#472).</summary>
    IsInterface: Boolean;
    /// <summary>Deklarierende Unit, auch wenn der Typ sichtbar ist; '' bei eingebauten Typen.</summary>
    TypeUnit: string;
  end;

  /// <summary>Typ der Inline-Variablen ohne Typangabe, deren Name in AText an ANamePos steht.</summary>
  TTypeProbe = reference to function(const AText: string; const ANamePos: TTextPosition): TProbedType;

  TExtractOptions = record
    /// <summary>Inline-Variablen erzeugen (Einstellung und Sprachversion).</summary>
    InlineVar: Boolean;
    Style: TFormatStyle;
    /// <summary>Namensauflösung für Typen; nil ohne.</summary>
    Probe: TTypeProbe;
    class function Default: TExtractOptions; static;
  end;

  TExtractRefactoring = class
  public const
    MethodName = 'ExtractedMethod';
    VariableName = 'Value';
    ConstantName = 'NewConstant';
    ProbeName = 'AtlasProbe';
  public
    /// <summary>„Methode extrahieren“ für die Anweisungen in ARange; False mit Grund in AReason.</summary>
    class function ExtractMethod(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AOptions: TExtractOptions; out AAction: TCodeAction; out AReason: string): Boolean; overload; static;
    class function ExtractMethod(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AOptions: TExtractOptions; out AAction: TCodeAction): Boolean; overload; static;
    /// <summary>„Variable einführen“ für den Ausdruck in ARange; mit AAll für alle textgleichen Vorkommen im
    /// selben Block (False, wenn es nur eins gibt).</summary>
    class function IntroduceVariable(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AOptions: TExtractOptions; AAll: Boolean; out AAction: TCodeAction): Boolean; static;
    /// <summary>„Konstante extrahieren“ für das Literal in ARange (oder am Cursor); AUnit: vor der Routine in
    /// der Unit statt im const-Abschnitt der Routine.</summary>
    class function ExtractConstant(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AOptions: TExtractOptions; AUnit: Boolean; out AAction: TCodeAction): Boolean; static;
    /// <summary>Alle passenden Extrahieren-Aktionen für ARange.</summary>
    class function Actions(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AOptions: TExtractOptions): TArray<TCodeAction>; static;
    /// <summary>Typ eines Ausdrucks (Knoten AExpression), der als Inline-Variable vor AStatement stünde:
    /// erst Literal, Operator und Bezeichner der Datei, dann AOptions.Probe. Name '' unbekannt.</summary>
    class function TypeOfExpression(const AText: string; ATree: TSyntaxTree; AExpression,
      AStatement: TSyntaxNode; const AOptions: TExtractOptions): TProbedType; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Editing.DeclareUnknown,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals;

const
  LoopKinds = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
  ExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess, TSyntaxKind.Dereference, TSyntaxKind.AddressOf, TSyntaxKind.SetConstructor,
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.IfExpr];

type
  TLocal = TRoutineLocal;
  TLocalKind = TRoutineLocalKind;
  TAccess = TLocalAccess;

  TOccurrence = record
    Node: TSyntaxNode;
    Local: Integer;
    Access: TAccess;
  end;

  TParameterMode = (None, Const_, Var_, Out_, Value, LocalVar, CopyConst);

{ TExtractOptions }

class function TExtractOptions.Default: TExtractOptions;
begin
  Result.InlineVar := True;
  Result.Style := TFormatStyle.Default;
  Result.Probe := nil;
end;

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

function OffsetRange(const AText: string; const ARange: TTextRange; out AFirst, ALast: Integer): Boolean;
var
  Lines: TLineTable;
begin
  Lines := TLineTable.Build(AText);
  AFirst := Lines.OffsetAt(ARange.StartPos);
  ALast := Lines.OffsetAt(ARange.EndPos);
  Result := AFirst <= ALast;
end;

/// <summary>Auswahl auf Token zuschneiden: Leerraum, Kommentare und ";" am Rand zählen nicht.</summary>
function Trimmed(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer; out AStart, AEnd: Integer): Boolean;
var
  First, Last: Integer;
begin
  First := TRoutineBody.TokenAt(ATokens, AFirst);
  while (First <= High(ATokens)) and (ATokens[First].Offset < ALast) and
    ((ATokens[First].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) or
    ATokens[First].IsSymbol(';')) do
    Inc(First);
  Last := TRoutineBody.TokenAt(ATokens, ALast) - 1;
  while (Last >= First) and ((ATokens[Last].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) or
    ATokens[Last].IsSymbol(';')) do
    Dec(Last);
  Result := (First <= High(ATokens)) and (Last >= First) and (ATokens[Last].Offset < ALast);
  if Result then
  begin
    AStart := ATokens[First].Offset;
    AEnd := ATokens[Last].Offset + Length(ATokens[Last].Text);
  end;
end;

function ArgumentText(AMode: TParameterMode): string;
begin
  case AMode of
    TParameterMode.Const_:
      Result := 'const ';
    TParameterMode.Var_:
      Result := 'var ';
    TParameterMode.Out_:
      Result := 'out ';
  else
    Result := '';
  end;
end;

/// <summary>Reihenfolge der Parameter: 0 Eingaben (const, Wert, lokal, Konstante), 1 var, 2 out.</summary>
function GroupOf(AMode: TParameterMode): Integer;
begin
  case AMode of
    TParameterMode.Var_:
      Result := 1;
    TParameterMode.Out_:
      Result := 2;
  else
    Result := 0;
  end;
end;

/// <summary>Probetext: AText mit "var AtlasProbe := Ausdruck;" vor AStatement; ANamePos ist die Stelle des
/// Namens.</summary>
function ProbeText(const AText, AExpression: string; AStatement: TSyntaxNode; out ANamePos: TTextPosition): string;
begin
  ANamePos := TTextPosition.Create(AStatement.StartPos.Line, AStatement.StartPos.Character + 4);
  Result := Copy(AText, 1, AStatement.StartOffset) + 'var ' + TExtractRefactoring.ProbeName + ' := ' +
    AExpression + '; ' + Copy(AText, AStatement.StartOffset + 1, MaxInt);
end;

class function TExtractRefactoring.TypeOfExpression(const AText: string; ATree: TSyntaxTree; AExpression,
  AStatement: TSyntaxNode; const AOptions: TExtractOptions): TProbedType;
var
  Tokens: TArray<TPascalToken>;
  First, Last, TermFirst, TermLast: Integer;
  Declared: TDeclaredTypes;
  NamePos: TTextPosition;
begin
  Result := Default(TProbedType);
  if Assigned(AOptions.Probe) then
  begin
    Result := AOptions.Probe(ProbeText(AText, TRoutineBody.TextOf(AText, AExpression), AStatement, NamePos), NamePos);
    if Result.Name <> '' then
      Exit;
  end;
  Tokens := ATree.Tokens;
  First := TRoutineBody.TokenAt(Tokens, AExpression.StartOffset);
  Last := TRoutineBody.TokenAt(Tokens, AExpression.EndOffset) - 1;
  if (First > Last) or (Last > High(Tokens)) then
    Exit;
  if First = Last then
    Result.Name := TDeclareUnknown.LiteralType(Tokens[First]);
  if Result.Name = '' then
    Result.Name := TDeclareUnknown.Shape(Tokens, First, Last, TermFirst, TermLast);
  if (Result.Name = '') and (TermFirst >= 0) and (TermFirst = TermLast) then
    if Tokens[TermFirst].Kind = TPascalTokenKind.Identifier then
    begin
      Declared := TDeclaredTypes.Create(ATree, AText);
      try
        Result.Name := Declared.DeclaredType(Tokens[TermFirst].Text, Tokens[TermFirst].StartPos);
      finally
        Declared.Free;
      end;
    end
    else
      Result.Name := TDeclareUnknown.LiteralType(Tokens[TermFirst]);
  Result.IsValue := Result.Name <> '';
end;

/// <summary>uses-Eintrag für den Typ, wenn die Namensauflösung eine fehlende Unit meldet.</summary>
procedure AddUsesFor(ATree: TSyntaxTree; const AText: string; const AType: TProbedType; AOffset: Integer;
  var AEdits: TArray<TTextEdit>);
var
  Edit: TTextEdit;
begin
  if (AType.UnitName <> '') and TUsesClauses.AddUnit(ATree.Tokens, AOffset, AType.UnitName,
    TTextLines.LineBreakOf(AText), Edit) then
    AEdits := AEdits + [Edit];
end;

{ Methode extrahieren }

/// <summary>Oberste Anweisungen der Auswahl AStart..AEnd: alle aus derselben Anweisungsliste, dazwischen nur ";".</summary>
function SelectedStatements(ATree: TSyntaxTree; ABody: TSyntaxNode; AStart, AEnd: Integer;
  out AStatements: TArray<TSyntaxNode>): Boolean;
var
  Container, Child: TSyntaxNode;
  Index, Token, Covered: Integer;
  Tokens: TArray<TPascalToken>;
begin
  AStatements := nil;
  Result := False;
  Container := TRoutineBody.Enclosing(ABody, AStart, AEnd);
  // Eine einzelne ganze Anweisung: der Knoten selbst, sonst die Kinder seiner Liste. Ein Aufruf liegt
  // deckungsgleich unter seiner Anweisung, darum von dort aufwärts suchen.
  Child := Container;
  while (Child <> nil) and (Child <> ABody) and (Child.StartOffset = AStart) and (Child.EndOffset = AEnd) do
  begin
    if TRoutineBody.IsStatement(Child) and TRoutineBody.InList(Child) then
    begin
      AStatements := [Child];
      Exit(True);
    end;
    Child := Child.Parent;
  end;
  for Index := 0 to Container.ChildCount - 1 do
  begin
    Child := Container[Index];
    if (Child.EndOffset <= AStart) or (Child.StartOffset >= AEnd) then
      Continue;
    if (Child.StartOffset < AStart) or (Child.EndOffset > AEnd) or not TRoutineBody.InList(Child) then
      Exit;
    AStatements := AStatements + [Child];
  end;
  if AStatements = nil then
    Exit;
  // Zwischen den Anweisungen nur ";" und Kommentare.
  Tokens := ATree.Tokens;
  Token := TRoutineBody.TokenAt(Tokens, AStart);
  Covered := 0;
  while (Token <= High(Tokens)) and (Tokens[Token].Offset < AEnd) do
  begin
    while (Covered <= High(AStatements)) and (AStatements[Covered].EndOffset <= Tokens[Token].Offset) do
      Inc(Covered);
    if not ((Covered <= High(AStatements)) and (AStatements[Covered].StartOffset <= Tokens[Token].Offset)) and
      not Tokens[Token].IsSymbol(';') and
      not (Tokens[Token].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      Exit;
    Inc(Token);
  end;
  Result := (AStatements[0].StartOffset = AStart) and (AStatements[High(AStatements)].EndOffset = AEnd);
end;

function IsTopStatement(const AStatements: TArray<TSyntaxNode>; ANode: TSyntaxNode): Boolean;
var
  Statement: TSyntaxNode;
begin
  for Statement in AStatements do
    if Statement = ANode then
      Exit(True);
  Result := False;
end;

function InSelection(ANode: TSyntaxNode; AStart, AEnd: Integer): Boolean;
begin
  Result := (ANode.StartOffset >= AStart) and (ANode.EndOffset <= AEnd);
end;

/// <summary>Sprünge prüfen: Exit nie, Break/Continue nur mit Schleife in der Auswahl, goto nur innen.</summary>
function JumpsInside(ABody: TSyntaxNode; const AStatements: TArray<TSyntaxNode>; AStart, AEnd: Integer;
  out AReason: string): Boolean;
var
  Nodes: TList<TSyntaxNode>;
  Node, Loop: TSyntaxNode;
  Statement: TSyntaxNode;
  Labels: TList<TSyntaxNode>;
  Found: Boolean;
begin
  Nodes := TList<TSyntaxNode>.Create;
  Labels := TList<TSyntaxNode>.Create;
  try
    for Statement in AStatements do
    begin
      TRoutineLocals.CollectKind(Statement, TSyntaxKind.Identifier, Nodes);
      if TRoutineLocals.HasKind(Statement, TSyntaxKind.AsmBlock) then
        Exit(Fail('asm in der Auswahl', AReason));
      if TRoutineLocals.HasKind(Statement, TSyntaxKind.WithStatement) then
        Exit(Fail('with in der Auswahl', AReason));
    end;
    for Node in Nodes do
      if SameText(Node.Name, 'Exit') and (Node.Parent <> nil) and
        (Node.Parent.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.Call]) then
        Exit(Fail('Exit in der Auswahl', AReason))
      else if (SameText(Node.Name, 'Break') or SameText(Node.Name, 'Continue')) and (Node.Parent <> nil) and
        (Node.Parent.Kind = TSyntaxKind.CallStatement) then
      begin
        Loop := Node.Parent;
        while (Loop <> nil) and not (Loop.Kind in LoopKinds) and (Loop.Kind <> TSyntaxKind.AnonymousMethod) do
          Loop := Loop.Parent;
        if (Loop = nil) or (Loop.Kind = TSyntaxKind.AnonymousMethod) or not InSelection(Loop, AStart, AEnd) then
          Exit(Fail(Node.Name + ' springt aus der Auswahl', AReason));
      end;
    // goto und Marke müssen beide innen oder beide außen liegen.
    Nodes.Clear;
    TRoutineLocals.CollectKind(ABody, TSyntaxKind.GotoStatement, Nodes);
    TRoutineLocals.CollectKind(ABody, TSyntaxKind.LabeledStatement, Labels);
    for Node in Nodes do
    begin
      Found := False;
      for Statement in Labels do
        if SameText(Statement.Name, Node.Name) then
        begin
          Found := True;
          if InSelection(Statement, AStart, AEnd) <> InSelection(Node, AStart, AEnd) then
            Exit(Fail('goto über den Rand der Auswahl', AReason));
        end;
      if not Found and InSelection(Node, AStart, AEnd) then
        Exit(Fail('goto mit unbekanntem Ziel', AReason));
    end;
    Result := True;
  finally
    Labels.Free;
    Nodes.Free;
  end;
end;

/// <summary>Namen, die nur in der umgebenden Routine sichtbar sind: verschachtelte Routinen, lokale Typen und
/// Marken.</summary>
function RoutineOnlyNames(ARoutine: TSyntaxNode): TArray<string>;
var
  Index, Inner: Integer;
  Name: string;
begin
  Result := nil;
  for Index := 0 to ARoutine.ChildCount - 1 do
    case ARoutine[Index].Kind of
      TSyntaxKind.RoutineDecl:
        begin
          Name := ARoutine[Index].Name;
          Result := Result + [Name.Substring(Name.LastIndexOf('.') + 1)];
        end;
      TSyntaxKind.TypeSection:
        for Inner := 0 to ARoutine[Index].ChildCount - 1 do
          Result := Result + [ARoutine[Index][Inner].Name];
    end;
end;

function IsClassRoutine(const ATokens: TArray<TPascalToken>; ARoutine: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := TRoutineBody.TokenAt(ATokens, ARoutine.StartOffset);
  Result := (Index <= High(ATokens)) and ATokens[Index].IsKeyword('class');
end;

class function TExtractRefactoring.ExtractMethod(const AText: string; ATree: TSyntaxTree;
  const ARange: TTextRange; const AOptions: TExtractOptions; out AAction: TCodeAction): Boolean;
var
  Reason: string;
begin
  Result := ExtractMethod(AText, ATree, ARange, AOptions, AAction, Reason);
end;

class function TExtractRefactoring.ExtractMethod(const AText: string; ATree: TSyntaxTree;
  const ARange: TTextRange; const AOptions: TExtractOptions; out AAction: TCodeAction;
  out AReason: string): Boolean;
var
  First, Last, SelStart, SelEnd, Index, LocalIndex, LoopStart, LoopEnd, Line: Integer;
  Routine, Body, Node, Loop, Statement, TypeBody, Anonymous: TSyntaxNode;
  Statements: TArray<TSyntaxNode>;
  Locals: TArray<TLocal>;
  Occurrences: TList<TOccurrence>;
  Occurrence: TOccurrence;
  Identifiers: TList<TSyntaxNode>;
  Lookup: TFlowSignatureLookup;
  Modes: TArray<TParameterMode>;
  Order, Sorted: TArray<Integer>;
  Group: Integer;
  ReadIn, WriteIn, Before, After, FirstWrite, Seen: TArray<Boolean>;
  FirstNode: TArray<TSyntaxNode>;
  OnlyNames, Removed: TArray<string>;
  Name, Qualifier, MethodText, ShortName, Params, Args, Header, Indent, Unit_, LineBreak, VarLines, ConstLines,
    BodyText, StatementIndent, TypeText, ClassDecl: string;
  Probed: TProbedType;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
  IsMethod, IsClass, IsStatic: Boolean;
  Tokens: TArray<TPascalToken>;
  Token: Integer;
begin
  AAction := Default(TCodeAction);
  AReason := '';
  Result := False;
  if (ATree = nil) or not OffsetRange(AText, ARange, First, Last) or (First = Last) then
    Exit(Fail('keine Auswahl', AReason));
  Tokens := ATree.Tokens;
  if not Trimmed(Tokens, First, Last, SelStart, SelEnd) then
    Exit(Fail('keine Auswahl', AReason));
  Routine := TRoutineBody.RoutineAt(ATree, SelStart);
  if (Routine = nil) or (TRoutineBody.RoutineAt(ATree, SelEnd) <> Routine) then
    Exit(Fail('nicht im Rumpf einer Routine', AReason));
  Body := TRoutineBody.BodyOf(Routine);
  if not SelectedStatements(ATree, Body, SelStart, SelEnd, Statements) then
    Exit(Fail('keine vollständigen Anweisungen', AReason));
  // In einer anonymen Methode oder einem with-Rumpf: Namen hätten außen eine andere Bedeutung.
  Node := Statements[0].Parent;
  while (Node <> nil) and (Node <> Body) do
  begin
    if Node.Kind = TSyntaxKind.AnonymousMethod then
      Exit(Fail('in einer anonymen Methode', AReason));
    if Node.Kind = TSyntaxKind.WithStatement then
      Exit(Fail('in einem with-Rumpf', AReason));
    if Node.Kind = TSyntaxKind.AsmBlock then
      Exit(Fail('asm', AReason));
    Node := Node.Parent;
  end;
  if not JumpsInside(Body, Statements, SelStart, SelEnd, AReason) then
    Exit;
  Locals := TRoutineLocals.Collect(AText, ATree, Routine);
  OnlyNames := RoutineOnlyNames(Routine);
  Lookup := TFlowSignatures.FromTree(ATree.Root);
  // Schleife um die Auswahl: Zugriffe darin vor der Auswahl laufen auch danach.
  LoopStart := SelStart;
  LoopEnd := SelEnd;
  Loop := Statements[0].Parent;
  while (Loop <> nil) and (Loop <> Body) do
  begin
    if Loop.Kind in LoopKinds then
    begin
      LoopStart := Loop.StartOffset;
      LoopEnd := Loop.EndOffset;
    end;
    Loop := Loop.Parent;
  end;
  SetLength(ReadIn, Length(Locals));
  SetLength(WriteIn, Length(Locals));
  SetLength(Before, Length(Locals));
  SetLength(After, Length(Locals));
  SetLength(FirstWrite, Length(Locals));
  SetLength(Modes, Length(Locals));
  SetLength(Seen, Length(Locals));
  SetLength(FirstNode, Length(Locals));
  for Index := 0 to High(Locals) do
  begin
    ReadIn[Index] := False;
    WriteIn[Index] := False;
    Before[Index] := Locals[Index].Kind = TLocalKind.Parameter;
    After[Index] := False;
    FirstWrite[Index] := False;
    Seen[Index] := False;
    FirstNode[Index] := nil;
    Modes[Index] := TParameterMode.None;
  end;
  Order := nil;
  Occurrences := TList<TOccurrence>.Create;
  Identifiers := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Body, TSyntaxKind.Identifier, Identifiers);
    for Node in Identifiers do
    begin
      LocalIndex := TRoutineLocals.IndexOf(Locals, Node.Name, Node.StartOffset);
      if InSelection(Node, SelStart, SelEnd) then
      begin
        if SameText(Node.Name, 'Result') and (LocalIndex < 0) then
          Exit(Fail('Result in der Auswahl', AReason));
        if (LocalIndex < 0) and (IndexText(Node.Name, OnlyNames) >= 0) then
          Exit(Fail(Node.Name + ' ist nur in der Routine sichtbar', AReason));
      end;
      if LocalIndex < 0 then
        Continue;
      Occurrence.Node := Node;
      Occurrence.Local := LocalIndex;
      Occurrence.Access := TRoutineLocals.AccessOf(Node, Lookup);
      Occurrences.Add(Occurrence);
    end;
    // Laufvariablen klassischer for-Schleifen werden geschrieben.
    Identifiers.Clear;
    TRoutineLocals.CollectKind(Body, TSyntaxKind.ForStatement, Identifiers);
    for Node in Identifiers do
      if not TRoutineLocals.IsInlineFor(Tokens, Node) then
      begin
        LocalIndex := TRoutineLocals.IndexOf(Locals, Node.Name, Node.StartOffset);
        if LocalIndex < 0 then
          Continue;
        if InSelection(Node, SelStart, SelEnd) then
          WriteIn[LocalIndex] := True
        else if Node.StartOffset < SelStart then
          Before[LocalIndex] := True
        else
          After[LocalIndex] := True;
      end;
    for Occurrence in Occurrences do
    begin
      LocalIndex := Occurrence.Local;
      Node := Occurrence.Node;
      if InSelection(Node, SelStart, SelEnd) then
      begin
        if not Seen[LocalIndex] then
        begin
          Seen[LocalIndex] := True;
          Order := Order + [LocalIndex];
          // Erstes Vorkommen: unbedingt geschrieben, wenn es Ziel einer obersten Zuweisung ist.
          FirstWrite[LocalIndex] := (Occurrence.Access = TAccess.Write) and IsTopStatement(Statements, Node.Parent);
          FirstNode[LocalIndex] := Node;
        end
        else if FirstWrite[LocalIndex] and (Occurrence.Access <> TAccess.Write) and
          TRoutineBody.Within(Node, FirstNode[LocalIndex].Parent) then
          // Die rechte Seite derselben Zuweisung liest vor dem Schreiben.
          FirstWrite[LocalIndex] := False;
        if Occurrence.Access in [TAccess.Read, TAccess.ReadWrite] then
          ReadIn[LocalIndex] := True;
        if Occurrence.Access in [TAccess.Write, TAccess.ReadWrite] then
          WriteIn[LocalIndex] := True;
      end
      else if Node.StartOffset < SelStart then
      begin
        Before[LocalIndex] := True;
        if (Node.StartOffset >= LoopStart) and (Node.EndOffset <= LoopEnd) and (LoopStart < SelStart) then
          After[LocalIndex] := True;
      end
      else
        After[LocalIndex] := True;
    end;
    // Modus je Name, der in der Auswahl vorkommt.
    Removed := nil;
    for LocalIndex in Order do
    begin
      case Locals[LocalIndex].Kind of
        TLocalKind.Constant:
          begin
            Modes[LocalIndex] := TParameterMode.CopyConst;
            Continue;
          end;
        TLocalKind.InlineVariable, TLocalKind.LoopVariable:
          if InSelection(Locals[LocalIndex].Decl, SelStart, SelEnd) then
          begin
            if After[LocalIndex] then
              Exit(Fail(Locals[LocalIndex].Name + ' wird nach der Auswahl noch gebraucht', AReason));
            Continue;
          end;
      end;
      if not WriteIn[LocalIndex] then
      begin
        if (Locals[LocalIndex].Kind = TLocalKind.Variable) and not Before[LocalIndex] and not After[LocalIndex] then
          Modes[LocalIndex] := TParameterMode.LocalVar
        else
          Modes[LocalIndex] := TParameterMode.Const_;
      end
      else if After[LocalIndex] then
      begin
        if FirstWrite[LocalIndex] then
          Modes[LocalIndex] := TParameterMode.Out_
        else
          Modes[LocalIndex] := TParameterMode.Var_;
      end
      else if ReadIn[LocalIndex] and not FirstWrite[LocalIndex] and Before[LocalIndex] then
        Modes[LocalIndex] := TParameterMode.Value
      else
        Modes[LocalIndex] := TParameterMode.LocalVar;
      if (Modes[LocalIndex] = TParameterMode.LocalVar) and (Locals[LocalIndex].Kind = TLocalKind.Variable) and
        not Before[LocalIndex] and not After[LocalIndex] then
        Removed := Removed + [Locals[LocalIndex].Name];
    end;
    // Anonyme Methoden dürfen var- und out-Parameter nicht einfangen.
    Identifiers.Clear;
    for Statement in Statements do
      TRoutineLocals.CollectKind(Statement, TSyntaxKind.AnonymousMethod, Identifiers);
    for Anonymous in Identifiers do
      for Occurrence in Occurrences do
        if TRoutineBody.Within(Occurrence.Node, Anonymous) and
          (Modes[Occurrence.Local] in [TParameterMode.Var_, TParameterMode.Out_]) then
          Exit(Fail('eine anonyme Methode fängt ' + Locals[Occurrence.Local].Name + ' ein', AReason));
  finally
    Identifiers.Free;
    Occurrences.Free;
  end;
  // Typen der Parameter und lokalen Variablen.
  Edits := nil;
  Params := '';
  Args := '';
  VarLines := '';
  ConstLines := '';
  LineBreak := TTextLines.LineBreakOf(AText);
  Unit_ := TRoutineBody.IndentUnit(AOptions.Style);
  Indent := TTextLines.IndentOf(AText, Routine.StartPos.Line);
  // Eingaben zuerst, dann var, dann out; sonst in der Reihenfolge des ersten Vorkommens.
  Sorted := nil;
  for Group := 0 to 2 do
    for LocalIndex in Order do
      if GroupOf(Modes[LocalIndex]) = Group then
        Sorted := Sorted + [LocalIndex];
  for LocalIndex in Sorted do
  begin
    if Modes[LocalIndex] = TParameterMode.None then
      Continue;
    if Modes[LocalIndex] = TParameterMode.CopyConst then
    begin
      ConstLines := ConstLines + Indent + Unit_ + TRoutineBody.TextOf(AText, Locals[LocalIndex].Decl) + LineBreak;
      Continue;
    end;
    TypeText := Locals[LocalIndex].TypeText;
    if (TypeText = '') and (Locals[LocalIndex].Initializer <> nil) then
    begin
      Probed := TypeOfExpression(AText, ATree, Locals[LocalIndex].Initializer, Locals[LocalIndex].Statement,
        AOptions);
      TypeText := Probed.Name;
      AddUsesFor(ATree, AText, Probed, Routine.StartOffset, Edits);
    end;
    if TypeText = '' then
      Exit(Fail('Typ von ' + Locals[LocalIndex].Name + ' unbekannt', AReason));
    if Modes[LocalIndex] = TParameterMode.LocalVar then
      VarLines := VarLines + Indent + Unit_ + Locals[LocalIndex].Name + ': ' + TypeText + ';' + LineBreak
    else
    begin
      if Params <> '' then
      begin
        Params := Params + '; ';
        Args := Args + ', ';
      end;
      Params := Params + ArgumentText(Modes[LocalIndex]) + Locals[LocalIndex].Name + ': ' + TypeText;
      Args := Args + Locals[LocalIndex].Name;
    end;
  end;
  // Kopf: Methode der Klasse oder Routine vor der umgebenden.
  Name := Routine.Name;
  Qualifier := '';
  if Name.LastIndexOf('.') > 0 then
    Qualifier := Name.Substring(0, Name.LastIndexOf('.'));
  IsMethod := (Qualifier <> '') and (Routine.Parent <> nil) and (Routine.Parent.Kind <> TSyntaxKind.RoutineDecl);
  IsClass := IsClassRoutine(Tokens, Routine);
  ShortName := TRoutineBody.UniqueName(Tokens, MethodName);
  if Params <> '' then
    Params := '(' + Params + ')';
  if Args <> '' then
    Args := '(' + Args + ')';
  Header := 'procedure ';
  if IsClass then
    Header := 'class ' + Header;
  if IsMethod then
  begin
    ShortName := TRoutineBody.UniqueName(Tokens, MethodName);
    Name := Qualifier.Substring(Qualifier.LastIndexOf('.') + 1);
    if Pos('<', Name) > 0 then
      Name := Copy(Name, 1, Pos('<', Name) - 1);
    TypeBody := TRoutineBody.TypeBody(ATree.Root, Name);
    if TypeBody = nil then
      Exit(Fail('Klasse ' + Name + ' nicht in der Datei', AReason));
    IsStatic := False;
    Token := TRoutineBody.TokenAt(Tokens, Routine.StartOffset);
    while (Token <= High(Tokens)) and (Tokens[Token].Offset < Body.StartOffset) do
    begin
      if (Tokens[Token].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Token].Text, 'static') then
        IsStatic := True;
      Inc(Token);
    end;
    ClassDecl := Header + ShortName + Params + ';';
    if IsStatic then
      ClassDecl := ClassDecl + ' static;';
    if not TRoutineBody.MemberDeclaration(AText, ATree, TypeBody, 'private', ClassDecl, AOptions.Style, Edit) then
      Exit(Fail('Klassendeklaration nicht erweiterbar', AReason));
    Edits := Edits + [Edit];
    MethodText := Indent + Header + Qualifier + '.' + ShortName + Params + ';' + LineBreak;
  end
  else
    MethodText := Indent + Header + ShortName + Params + ';' + LineBreak;
  if VarLines <> '' then
    MethodText := MethodText + Indent + 'var' + LineBreak + VarLines;
  if ConstLines <> '' then
    MethodText := MethodText + Indent + 'const' + LineBreak + ConstLines;
  // Rumpf: die Anweisungen eine Ebene unter begin.
  StatementIndent := TTextLines.IndentOf(AText, Statements[0].StartPos.Line);
  BodyText := Copy(AText, SelStart + 1, SelEnd - SelStart);
  if not EndsStr(';', BodyText) then
    BodyText := BodyText + ';';
  MethodText := MethodText + Indent + 'begin' + LineBreak + TRoutineBody.Reindent(BodyText, StatementIndent,
    Indent + Unit_, LineBreak) + LineBreak + Indent + 'end;' + LineBreak + LineBreak;
  Line := TRoutineBody.RoutineInsertLine(AText, Routine);
  Edits := Edits + [TTextEdit.Create(TTextRange.Create(Line, 0, Line, 0), MethodText)];
  // Lokale Variablen, die nur noch die neue Methode braucht.
  if Removed <> nil then
    for Index := 0 to Routine.ChildCount - 1 do
      if Routine[Index].Kind = TSyntaxKind.VarSection then
      begin
        Statement := Routine[Index];
        for LocalIndex := 0 to Statement.ChildCount - 1 do
          TRoutineLocals.RemoveVariables(AText, ATree, Statement[LocalIndex], Removed, Edits);
      end;
  Edits := Edits + [TTextEdit.Create(TTextRange.Create(Statements[0].StartPos, Statements[High(Statements)].EndPos),
    ShortName + Args)];
  AAction.Title := 'Methode extrahieren';
  AAction.Kind := ExtractKind;
  AAction.Edits := Edits;
  Result := True;
end;

{ Variable einführen }

/// <summary>Normalform eines Ausdrucks für den Vergleich: Token ohne Kommentare, Groß-/Kleinschreibung egal.</summary>
function NormalText(ATree: TSyntaxTree; ANode: TSyntaxNode): string;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
begin
  Tokens := ATree.Tokens;
  Result := '';
  Index := TRoutineBody.TokenAt(Tokens, ANode.StartOffset);
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < ANode.EndOffset) do
  begin
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      if Tokens[Index].Kind = TPascalTokenKind.StringLiteral then
        Result := Result + Tokens[Index].Text + ' '
      else
        Result := Result + LowerCase(Tokens[Index].Text) + ' ';
    Inc(Index);
  end;
end;

/// <summary>Name für die Variable aus dem Ausdruck: letzter Name einer Kette ohne "Get", sonst Value.</summary>
function NameFor(ANode: TSyntaxNode): string;
begin
  Result := '';
  case ANode.Kind of
    TSyntaxKind.Identifier, TSyntaxKind.MemberAccess:
      Result := ANode.Name;
    TSyntaxKind.Call:
      Result := ANode.Name;
  end;
  if StartsText('Get', Result) and (Length(Result) > 3) then
    Result := Copy(Result, 4, MaxInt);
  if (Result = '') or not CharInSet(Result[1], ['A'..'Z', 'a'..'z']) or (Pos('<', Result) > 0) then
    Result := TExtractRefactoring.VariableName
  else
    Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
end;

/// <summary>Namen, die im Ausdruck vorkommen.</summary>
function NamesIn(ANode: TSyntaxNode): TArray<string>;
var
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
begin
  Result := nil;
  Nodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(ANode, TSyntaxKind.Identifier, Nodes);
    for Node in Nodes do
      Result := Result + [Node.Name];
  finally
    Nodes.Free;
  end;
end;

/// <summary>Wird zwischen AFrom und ATo (Offsets) einer der Namen geändert oder etwas aufgerufen, das ihn
/// ändern könnte?</summary>
function ChangedBetween(ABody: TSyntaxNode; const ANames: TArray<string>; AFrom, ATo: Integer): Boolean;
var
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
begin
  Result := False;
  Nodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(ABody, TSyntaxKind.Identifier, Nodes);
    for Node in Nodes do
      if (Node.StartOffset > AFrom) and (Node.StartOffset < ATo) and (IndexText(Node.Name, ANames) >= 0) and
        (TRoutineLocals.AccessOf(Node, nil) <> TAccess.Read) then
        Exit(True);
  finally
    Nodes.Free;
  end;
end;

class function TExtractRefactoring.IntroduceVariable(const AText: string; ATree: TSyntaxTree;
  const ARange: TTextRange; const AOptions: TExtractOptions; AAll: Boolean; out AAction: TCodeAction): Boolean;
var
  First, Last, SelStart, SelEnd: Integer;
  Routine, Body, Expression, Host, Node, Block: TSyntaxNode;
  Nodes: TList<TSyntaxNode>;
  Targets: TArray<TSyntaxNode>;
  Normal, Name, Expr: string;
  Probed: TProbedType;
  Edits: TArray<TTextEdit>;
begin
  AAction := Default(TCodeAction);
  Result := False;
  if (ATree = nil) or not OffsetRange(AText, ARange, First, Last) or (First = Last) or
    not Trimmed(ATree.Tokens, First, Last, SelStart, SelEnd) then
    Exit;
  Routine := TRoutineBody.RoutineAt(ATree, SelStart);
  if Routine = nil then
    Exit;
  Body := TRoutineBody.BodyOf(Routine);
  Expression := TRoutineBody.Enclosing(Body, SelStart, SelEnd);
  if (Expression.StartOffset <> SelStart) or (Expression.EndOffset <> SelEnd) or
    not (Expression.Kind in ExpressionKinds) then
    Exit;
  // Klammern um den ganzen Ausdruck gehören nicht in die Variable.
  if (Expression.Kind = TSyntaxKind.ParenExpr) and (Expression.ChildCount = 1) then
    Expression := Expression[0];
  Host := TRoutineBody.HostStatement(Expression, Body);
  if Host = nil then
    Exit;
  Targets := [Expression];
  if AAll then
  begin
    // Textgleiche Vorkommen im selben Block ab der Anweisung, solange sich ihre Namen nicht ändern.
    Normal := NormalText(ATree, Expression);
    Block := Host.Parent;
    Targets := nil;
    Nodes := TList<TSyntaxNode>.Create;
    try
      TRoutineLocals.CollectKind(Block, Expression.Kind, Nodes);
      for Node in Nodes do
        if (Node.StartOffset >= Host.StartOffset) and (NormalText(ATree, Node) = Normal) and
          (TRoutineBody.HostStatement(Node, Body) <> nil) and ((Targets = nil) or
          (Node.StartOffset >= Targets[High(Targets)].EndOffset)) then
          Targets := Targets + [Node];
    finally
      Nodes.Free;
    end;
    if (Length(Targets) < 2) or ChangedBetween(Body, NamesIn(Expression), Targets[0].StartOffset,
      Targets[High(Targets)].EndOffset) then
      Exit;
    Host := TRoutineBody.HostStatement(Targets[0], Body);
  end;
  Name := TRoutineBody.UniqueName(ATree.Tokens, NameFor(Expression));
  Expr := TRoutineBody.TextOf(AText, Expression);
  Edits := nil;
  if AOptions.InlineVar then
    Edits := Edits + [TRoutineBody.InsertBefore(AText, Host, 'var ' + Name + ' := ' + Expr + ';')]
  else
  begin
    Probed := TypeOfExpression(AText, ATree, Expression, Host, AOptions);
    if Probed.Name = '' then
      Exit;
    Edits := Edits + [TRoutineBody.AddVariable(AText, Routine, Name, Probed.Name, AOptions.Style),
      TRoutineBody.InsertBefore(AText, Host, Name + ' := ' + Expr + ';')];
    AddUsesFor(ATree, AText, Probed, Routine.StartOffset, Edits);
  end;
  for Node in Targets do
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Node.StartPos, Node.EndPos), Name)];
  if AAll then
    AAction.Title := Format('Variable einführen (alle %d Vorkommen)', [Length(Targets)])
  else
    AAction.Title := 'Variable einführen';
  AAction.Kind := ExtractKind;
  AAction.Edits := Edits;
  Result := True;
end;

{ Konstante extrahieren }

class function TExtractRefactoring.ExtractConstant(const AText: string; ATree: TSyntaxTree;
  const ARange: TTextRange; const AOptions: TExtractOptions; AUnit: Boolean; out AAction: TCodeAction): Boolean;
var
  First, Last, SelStart, SelEnd, Line: Integer;
  Routine, Body, Literal, Node, Outer: TSyntaxNode;
  Name, Value, Indent, LineBreak: string;
  Edits: TArray<TTextEdit>;
begin
  AAction := Default(TCodeAction);
  Result := False;
  if (ATree = nil) or not OffsetRange(AText, ARange, First, Last) then
    Exit;
  if First = Last then
  begin
    SelStart := First;
    SelEnd := First;
  end
  else if not Trimmed(ATree.Tokens, First, Last, SelStart, SelEnd) then
    Exit;
  Routine := TRoutineBody.RoutineAt(ATree, SelStart);
  if Routine = nil then
    Exit;
  Body := TRoutineBody.BodyOf(Routine);
  Literal := TRoutineBody.Enclosing(Body, SelStart, SelEnd);
  // Negative Zahl: das Vorzeichen gehört dazu.
  if (Literal.Kind = TSyntaxKind.Literal) and (Literal.Parent <> nil) and
    (Literal.Parent.Kind = TSyntaxKind.UnaryExpr) and (Literal.Parent.Name = '-') and (First <> Last) and
    (Literal.Parent.StartOffset = SelStart) then
    Literal := Literal.Parent;
  if not ((Literal.Kind = TSyntaxKind.Literal) or ((Literal.Kind = TSyntaxKind.UnaryExpr) and
    (Literal.ChildCount = 1) and (Literal[0].Kind = TSyntaxKind.Literal))) then
    Exit;
  if (First <> Last) and ((Literal.StartOffset <> SelStart) or (Literal.EndOffset <> SelEnd)) then
    Exit;
  // Nicht in asm und nicht als Ziel einer Zuweisung (das kann ein Literal nicht sein); True/False/nil sind
  // Bezeichner und keine Literale.
  Node := Literal.Parent;
  while (Node <> nil) and (Node <> Body) do
  begin
    if Node.Kind in [TSyntaxKind.AsmBlock, TSyntaxKind.InlineConst] then
      Exit;
    Node := Node.Parent;
  end;
  Name := TRoutineBody.UniqueName(ATree.Tokens, ConstantName);
  Value := TRoutineBody.TextOf(AText, Literal);
  LineBreak := TTextLines.LineBreakOf(AText);
  if AUnit then
  begin
    // Vor die äußerste Routine, in der das Literal steht.
    Outer := Routine;
    while (Outer.Parent <> nil) and (Outer.Parent.Kind = TSyntaxKind.RoutineDecl) do
      Outer := Outer.Parent;
    Line := TRoutineBody.RoutineInsertLine(AText, Outer);
    Indent := TTextLines.IndentOf(AText, Outer.StartPos.Line);
    Edits := [TTextEdit.Create(TTextRange.Create(Line, 0, Line, 0), Indent + 'const' + LineBreak + Indent +
      TRoutineBody.IndentUnit(AOptions.Style) + Name + ' = ' + Value + ';' + LineBreak + LineBreak)];
    AAction.Title := 'Konstante in der Unit extrahieren';
  end
  else
  begin
    Edits := [TRoutineBody.AddConstant(AText, Routine, Name, Value, AOptions.Style)];
    AAction.Title := 'Konstante extrahieren';
  end;
  Edits := Edits + [TTextEdit.Create(TTextRange.Create(Literal.StartPos, Literal.EndPos), Name)];
  AAction.Kind := ExtractKind;
  AAction.Edits := Edits;
  Result := True;
end;

class function TExtractRefactoring.Actions(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
  const AOptions: TExtractOptions): TArray<TCodeAction>;
var
  Action: TCodeAction;
begin
  Result := nil;
  if ExtractMethod(AText, ATree, ARange, AOptions, Action) then
    Result := Result + [Action];
  if IntroduceVariable(AText, ATree, ARange, AOptions, False, Action) then
    Result := Result + [Action];
  if IntroduceVariable(AText, ATree, ARange, AOptions, True, Action) then
    Result := Result + [Action];
  if ExtractConstant(AText, ATree, ARange, AOptions, False, Action) then
    Result := Result + [Action];
  if ExtractConstant(AText, ATree, ARange, AOptions, True, Action) then
    Result := Result + [Action];
end;

end.
