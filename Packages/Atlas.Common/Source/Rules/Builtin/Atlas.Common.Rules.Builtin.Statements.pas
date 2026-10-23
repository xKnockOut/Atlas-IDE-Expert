unit Atlas.Common.Rules.Builtin.Statements;

// Regeln für Anweisungen, die anders laufen als geschrieben (#909):
//   empty-statement   Semikolon direkt nach then, do oder else (#912): die
//                     folgende Zeile läuft immer bzw. die Schleife dreht leer.
//                     Leere Blöcke begin … end nach then, do oder else ebenso,
//                     außer mit Kommentar darin (Option allowCommented).
//   loop-off-by-one   for I := 0 to X.Count bzw. to Length(A) über nullbasierte
//                     Listen und Arrays, 0 to Length(S) und S[0] bei einsbasierten
//                     Strings (#913); {$ZEROBASEDSTRINGS ON} macht Strings
//                     nullbasiert. Gemeldet wird eine Schleife nur, wenn ihr
//                     Rumpf X[I] bzw. A[I] liest; die Anzahl erkennt die Option
//                     countNames (Vorgabe Count und Length).
//   collection-modified-in-loop
//                     Delete, Remove, Add … auf der Liste, über die die Schleife
//                     gerade vorwärts per Index oder mit for … in läuft (#914).
//                     Ein Break oder Exit direkt nach dem Aufruf beendet die
//                     Schleife und bleibt still; die Methoden nennt die Option
//                     mutatingMethods.
//   destroy-called-directly
//                     Obj.Destroy als Anweisung statt Obj.Free (#920): bei nil
//                     knallt es. inherited Destroy und Destroy mit Argumenten
//                     (eigener Destruktor) bleiben still; Korrektur Free.
//   case-missing-enum-value
//                     case über einen Aufzählungstyp ohne else, dem Werte fehlen
//                     (#929); mit Option requireElse auch mit else. Den Typ des
//                     Selektors löst die Namensauflösung, die Werte kommen aus
//                     dem Index bzw. der Unit selbst; die Korrektur ergänzt die
//                     fehlenden Zweige über TCaseCompletion (#449).
//   dataset-loop-without-next
//                     while not Q.Eof do ohne Q.Next auf jedem Weg durch den
//                     Rumpf, der die Schleife fortsetzt (#963); Delete, MoveBy,
//                     Last, Close und FindNext zählen mit. Wird Q im Rumpf
//                     weitergegeben, bleibt die Regel still.
//   dataset-edit-without-post
//                     Q.Edit, Q.Append bzw. Q.Insert ohne folgendes Post, Cancel
//                     oder CheckBrowseMode in der Routine (#964); still, wenn
//                     eine andere Routine der Unit Q postet oder Q weitergegeben wird.
//   transaction-without-rollback
//                     StartTransaction (BeginTransaction, BeginTrans) ohne Rollback
//                     im except des unmittelbar folgenden try (#965); Paare aus der
//                     Option pairs (start, commit, rollback) ersetzen die eingebauten.
//   comparison-as-statement
//                     Result = 0; als eigene Anweisung (#982, wie E2014): gemeint
//                     war :=. Bei = mit zuweisbarer linker Seite ersetzt die
//                     Korrektur = durch :=; andere Vergleiche und Ausdrücke wie
//                     A + B; oder not A; meldet die Regel ohne Korrektur.
//   duplicate-case-label
//                     Zwei Marken einer case-Anweisung (wie E2030) bzw. eines
//                     varianten Record-Teils (wie E2027) decken denselben Wert ab,
//                     auch über Bereiche und Konstanten (#983). Die Werte rechnet
//                     Semantics.ConstantValues aus, Namen löst TNameResolver auf;
//                     Unbekanntes vergleicht die Regel nur über den Text. Die
//                     Korrektur entfernt den späteren Wert bzw. dessen Zweig.
//                     Bedingte Zweige über Pascal.ConditionalBranches: gemeldet
//                     wird nur, wenn die frühere Marke immer mit übersetzt wird.
//   assign-to-property-member
//                     Zuweisung an ein Feld eines Records, den eine Property mit
//                     Getter, eine Default- bzw. Array-Property oder ein
//                     Funktionsergebnis nur als Kopie liefert (#1005, wie E2064),
//                     und an eine untypisierte Konstante. Typen kommen aus
//                     TNameResolver.NodeType; gemeldet wird nur bei sicher
//                     bekanntem Record-Typ. Liest die Property direkt ein Feld,
//                     schreibt Delphi in das Feld: still. Korrektur bei Properties
//                     mit write: über eine lokale Variable zuweisen und
//                     zurückschreiben (Variable über TRoutineBody.AddVariable, Unit
//                     des Typs über TUsesClauses.AddUnit).
//   untyped-pointer-refcount
//                     Pointer(X) := … mit einem Interface X (#1081, wie W1070):
//                     die Zuweisung umgeht die Referenzzählung. Typ über
//                     TNameResolver.NodeType, gemeldet wird nur bei sicher
//                     bekanntem Interface-Typ. Strings (string, AnsiString …)
//                     meldet Atlas mit „(dcc meldet das nicht)“, weil Delphi
//                     dort nur unter NEXTGEN warnt. Felder mit
//                     [weak] oder [unsafe] bleiben still. Korrekturen für Felder
//                     dieser Datei mit Pointer(Y) oder nil rechts: [weak] bzw.
//                     [unsafe] ans Feld, Zuweisung ohne Pointer.
//   readonly-property-assigned
//                     Zuweisung an eine Property ohne write (#1006, wie E2129) und
//                     Lesen einer Property ohne read (wie E2130), nur bei sicher
//                     aufgelöster Property. Vorab gefiltert über die Namen solcher
//                     Properties in Datei und Index. Korrekturen: Count := 0 wird
//                     Clear, wenn der Typ Clear hat; in einer Methode der eigenen
//                     Klasse direkt das Feld hinter read; für eine Property dieser
//                     Datei den Setter anlegen und write ergänzen.
// Grundlage ist der Syntaxbaum: if, while, for, for-in und with ohne Rumpf
// bzw. mit leerem Block; das Schlüsselwort davor sucht die Regel in den Token.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  EmptyStatementRuleId = 'empty-statement';
  LoopOffByOneRuleId = 'loop-off-by-one';
  CollectionModifiedInLoopRuleId = 'collection-modified-in-loop';
  DestroyCalledDirectlyRuleId = 'destroy-called-directly';
  CaseMissingEnumValueRuleId = 'case-missing-enum-value';
  ComparisonAsStatementRuleId = 'comparison-as-statement';
  DuplicateCaseLabelRuleId = 'duplicate-case-label';
  AssignToPropertyMemberRuleId = 'assign-to-property-member';
  ReadonlyPropertyAssignedRuleId = 'readonly-property-assigned';

type
  TEmptyStatementRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TLoopOffByOneRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Stehen Strings in AText nullbasiert ({$ZEROBASEDSTRINGS ON} bzw. {$ZEROBASEDSTRINGS+})?</summary>
    class function ZeroBasedStrings(const ATokens: TArray<TPascalToken>): Boolean; static;
  end;

  TCollectionModifiedInLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorgabe der Option mutatingMethods.</summary>
    class function DefaultMutatingMethods: TArray<string>; static;
  end;

  TDestroyCalledDirectlyRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCaseMissingEnumValueRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDatasetLoopWithoutNextRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDatasetEditWithoutPostRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  /// <summary>Methoden einer Transaktion für transaction-without-rollback (#965).</summary>
  TTransactionPair = record
    Start: string;
    Commit: string;
    Rollback: string;
  end;

  TTransactionWithoutRollbackRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Paare aus "pairs" in AOptions, ohne Option die eingebauten (FireDAC, IBX, dbExpress, ADO).</summary>
    class function Pairs(const AOptions: string): TArray<TTransactionPair>; static;
  end;

  TComparisonAsStatementRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ausdruck, den die Aufrufanweisung AStatement als Anweisung stehen lässt (Vergleich, Operator, Literal); nil sonst.</summary>
    class function ExpressionOf(AStatement: TSyntaxNode): TSyntaxNode; static;
  end;

  TDuplicateCaseLabelRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TAssignToPropertyMemberRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUntypedPointerRefcountRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TReadonlyPropertyAssignedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Hat die Property-Signatur ASignature read bzw. write? Ohne beides ist es eine Neudeklaration
    /// (property Caption;), dann False.</summary>
    class function Accessors(const ASignature: string; out AHasRead, AHasWrite: Boolean): Boolean; static;
  end;

procedure RegisterStatementRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Editing.CaseCompletion,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.AccessorCreation,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Options;

type
  TTokens = TArray<TPascalToken>;
  TSyntaxKinds = set of TSyntaxKind;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

/// <summary>Erstes Token ab AOffset (Index), High + 1 ohne.</summary>
function TokenFrom(const ATokens: TTokens; AOffset: Integer): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(ATokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if ATokens[Middle].Offset < AOffset then
      Low := Middle + 1
    else
      High := Middle;
  end;
  Result := Low;
end;

function StatementKinds: TSyntaxKinds;
begin
  Result := [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
    TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement,
    TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar,
    TSyntaxKind.InlineConst, TSyntaxKind.Error];
end;

/// <summary>Erste Anweisung unter ANode, die nach AOffset beginnt; nil ohne.</summary>
function StatementAfter(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
    if (ANode[Index].Kind in StatementKinds) and (ANode[Index].StartOffset >= AOffset) then
      Exit(ANode[Index]);
  Result := nil;
end;

/// <summary>Quelltext der Token AFirst..ALast wie geschrieben.</summary>
function SourceText(const AText: string; const ATokens: TTokens; AFirst, ALast: Integer): string;
begin
  Result := Copy(AText, ATokens[AFirst].Offset + 1,
    ATokens[ALast].Offset + Length(ATokens[ALast].Text) - ATokens[AFirst].Offset);
end;

/// <summary>Code-Token AFirst..ALast ohne Leerraum und Kommentare, kleingeschrieben (zum Vergleichen).</summary>
function CodeKey(const ATokens: TTokens; AFirst, ALast: Integer): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := AFirst to ALast do
    if not IsTrivia(ATokens[Index]) then
      Result := Result + LowerCase(ATokens[Index].Text);
end;

/// <summary>Letztes Code-Token vor AIndex (AIndex selbst ausgeschlossen).</summary>
function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

/// <summary>Index der schließenden Klammer zu AOpen, -1 ohne.</summary>
function Closing(const ATokens: TTokens; AOpen, AStop: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  for Result := AOpen to AStop - 1 do
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
      Inc(Depth)
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit;
    end;
  Result := -1;
end;

/// <summary>Erstes Token AText (Schlüsselwort bzw. Symbol) in AFrom..AStop-1 auf Klammerebene 0; -1 ohne.</summary>
function DepthZero(const ATokens: TTokens; AFrom, AStop: Integer; const AText: string; AKeyword: Boolean): Integer;
var
  Index, Depth: Integer;
begin
  Depth := 0;
  for Index := AFrom to AStop - 1 do
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
      Inc(Depth)
    else if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']') then
      Dec(Depth)
    else if (Depth = 0) and ((AKeyword and ATokens[Index].IsKeyword(AText)) or
      (not AKeyword and ATokens[Index].IsSymbol(AText))) then
      Exit(Index);
  Result := -1;
end;

/// <summary>Bilden die ABaseCount Code-Token vor AIndex die Basis ABaseKey (CodeKey), ohne Punkt davor?</summary>
function BaseBefore(const ATokens: TTokens; AIndex: Integer; const ABaseKey: string; ABaseCount: Integer): Boolean;
var
  Before, Count, Prev: Integer;
  Key: string;
begin
  Key := '';
  Before := AIndex;
  Count := 0;
  while Count < ABaseCount do
  begin
    Before := PreviousCode(ATokens, Before);
    if Before < 0 then
      Exit(False);
    Key := LowerCase(ATokens[Before].Text) + Key;
    Inc(Count);
  end;
  Prev := PreviousCode(ATokens, Before);
  Result := (Key = ABaseKey) and ((Prev < 0) or not ATokens[Prev].IsSymbol('.'));
end;

function IsStringType(const AType: string): Boolean;
begin
  Result := MatchText(AType, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'UTF8String']);
end;

{ TEmptyStatementRule }

function TEmptyStatementRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(EmptyStatementRuleId, TRuleSeverity.Warning,
    'Leere Anweisung nach then, do oder else');
end;

procedure TEmptyStatementRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  AllowCommented: Boolean;
  Report: IRuleReport;

  // AKeyword: Index von then/do/else; ABody: Anweisung danach oder nil.
  procedure Inspect(AKeyword: Integer; ABody: TSyntaxNode; AIsLoop: Boolean);
  var
    Next, After, Index: Integer;
    Word, Message: string;
    HasComment: Boolean;
  begin
    if AKeyword < 0 then
      Exit;
    Word := LowerCase(Tokens[AKeyword].Text);
    Next := NextCode(Tokens, AKeyword + 1);
    if Next > High(Tokens) then
      Exit;
    if Tokens[Next].IsSymbol(';') and ((ABody = nil) or (ABody.StartOffset > Tokens[Next].Offset)) then
    begin
      After := NextCode(Tokens, Next + 1);
      // Am Blockende ändert das Semikolon nichts am Ablauf (z. B. while not Fertig do; als Warteschleife).
      if (After > High(Tokens)) or (Tokens[After].Kind = TPascalTokenKind.Keyword) and
        MatchText(Tokens[After].Text, ['end', 'until', 'except', 'finally', 'else']) then
        Exit;
      if AIsLoop then
        Message := Format('Leere Anweisung nach %s: die Schleife dreht leer.', [Word])
      else
        Message := Format('Leere Anweisung nach %s: die nächste Zeile läuft immer.', [Word]);
      Report.Add(TTextRange.Create(Tokens[AKeyword].StartPos, Tokens[Next].EndPos), Message, TRuleConfidence.High,
        [TRuleFix.Create('Semikolon entfernen', [TRuleEdit.Create(TTextRange.Create(Tokens[Next].StartPos,
        Tokens[Next].EndPos), '')])]);
      Exit;
    end;
    // begin end ohne Anweisung, mit Kommentar darin nur bei allowCommented = false.
    if (ABody <> nil) and (ABody.Kind = TSyntaxKind.Block) and (ABody.ChildCount = 0) and
      (Tokens[Next].IsKeyword('begin')) and (Tokens[Next].Offset = ABody.StartOffset) then
    begin
      HasComment := False;
      Index := Next + 1;
      while (Index <= High(Tokens)) and (Tokens[Index].Offset < ABody.EndOffset) do
      begin
        if Tokens[Index].Kind = TPascalTokenKind.Comment then
          HasComment := True;
        Inc(Index);
      end;
      if HasComment and AllowCommented then
        Exit;
      Report.Add(TTextRange.Create(Tokens[AKeyword].StartPos, Tokens[Index - 1].EndPos),
        Format('Leerer Block nach %s: hier passiert nichts.', [Word]), TRuleConfidence.High);
    end;
  end;

  // Schlüsselwort AWord dieses Knotens: auf Klammerebene 0 und nicht in einer untergeordneten Anweisung.
  function OwnKeyword(ANode: TSyntaxNode; AFrom, AStop: Integer; const AWord: string): Integer;
  var
    Index, Child, Depth: Integer;
    Inside: Boolean;
  begin
    Depth := 0;
    for Index := AFrom to AStop - 1 do
    begin
      if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol('[') then
        Inc(Depth)
      else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
        Dec(Depth)
      else if (Depth = 0) and Tokens[Index].IsKeyword(AWord) then
      begin
        Inside := False;
        for Child := 0 to ANode.ChildCount - 1 do
          if (ANode[Child].Kind in StatementKinds) and (Tokens[Index].Offset >= ANode[Child].StartOffset) and
            (Tokens[Index].Offset < ANode[Child].EndOffset) then
            Inside := True;
        if not Inside then
          Exit(Index);
      end;
    end;
    Result := -1;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index, Stop, ThenIndex, ElseIndex, DoIndex: Integer;
    Node, Body: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1): lange else-if-Ketten ergeben sehr tiefe Bäume.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Stop := TokenFrom(Tokens, Node.EndOffset);
        case Node.Kind of
          TSyntaxKind.IfStatement:
            if Node.ChildCount > 0 then
            begin
              ThenIndex := OwnKeyword(Node, TokenFrom(Tokens, Node[0].EndOffset), Stop, 'then');
              if ThenIndex >= 0 then
              begin
                ElseIndex := OwnKeyword(Node, ThenIndex + 1, Stop, 'else');
                Body := StatementAfter(Node, Tokens[ThenIndex].Offset);
                if (Body <> nil) and (ElseIndex >= 0) and (Body.StartOffset > Tokens[ElseIndex].Offset) then
                  Body := nil;
                Inspect(ThenIndex, Body, False);
                if ElseIndex >= 0 then
                  Inspect(ElseIndex, StatementAfter(Node, Tokens[ElseIndex].Offset), False);
              end;
            end;
          TSyntaxKind.WhileStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
          TSyntaxKind.WithStatement:
            begin
              DoIndex := OwnKeyword(Node, TokenFrom(Tokens, Node.StartOffset), Stop, 'do');
              if DoIndex >= 0 then
                Inspect(DoIndex, StatementAfter(Node, Tokens[DoIndex].Offset),
                  Node.Kind <> TSyntaxKind.WithStatement);
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  AllowCommented := TRuleOptions.Bool(AContext.Options, 'allowCommented', True);
  Report := AReport;
  Visit(AContext.Tree.Root);
end;

{ TLoopOffByOneRule }

function TLoopOffByOneRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(LoopOffByOneRuleId, TRuleSeverity.Warning,
    'Schleife läuft einen Schritt zu weit');
end;

class function TLoopOffByOneRule.ZeroBasedStrings(const ATokens: TArray<TPascalToken>): Boolean;
var
  Token: TPascalToken;
  Text: string;
begin
  Result := False;
  for Token in ATokens do
    if Token.Kind = TPascalTokenKind.Directive then
    begin
      Text := UpperCase(StringReplace(Token.Text, ' ', '', [rfReplaceAll]));
      if Pos('$ZEROBASEDSTRINGS', Text) = 0 then
        Continue;
      Result := (Pos('$ZEROBASEDSTRINGSON', Text) > 0) or (Pos('$ZEROBASEDSTRINGS+', Text) > 0);
    end;
end;

procedure TLoopOffByOneRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  CountNames: TArray<string>;
  ZeroBased: Boolean;
  Blocks: TArray<TSyntaxNode>;

  function InBlock(AOffset: Integer): Boolean;
  var
    Block: TSyntaxNode;
  begin
    for Block in Blocks do
      if (AOffset >= Block.StartOffset) and (AOffset < Block.EndOffset) then
        Exit(True);
    Result := False;
  end;

  procedure CollectBlocks(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.Block) and (Node.Parent <> nil) and
          (Node.Parent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.InitializationSection,
          TSyntaxKind.FinalizationSection, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile]) then
        begin
          Blocks := Blocks + [Node];
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  /// Erstes Code-Token AWord bzw. ASymbol auf Klammerebene 0 in AFrom..AStop-1; -1 ohne.
  function AtDepthZero(AFrom, AStop: Integer; const AText: string; AKeyword: Boolean): Integer;
  var
    Index, Depth: Integer;
  begin
    Depth := 0;
    for Index := AFrom to AStop - 1 do
      if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol('[') then
        Inc(Depth)
      else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
        Dec(Depth)
      else if (Depth = 0) and ((AKeyword and Tokens[Index].IsKeyword(AText)) or
        (not AKeyword and Tokens[Index].IsSymbol(AText))) then
        Exit(Index);
    Result := -1;
  end;

  // Liest der Rumpf ABase[AVar]? ABaseKey '' = Items[AVar] bzw. Self[AVar].
  function BodyIndexes(AFrom, AStop: Integer; const ABaseKey: string; ABaseCount: Integer;
    const AVar: string): Boolean;
  var
    Index, Inner, Close, Before, Count, Prev: Integer;
    Key: string;
  begin
    for Index := AFrom to AStop - 1 do
    begin
      if not Tokens[Index].IsSymbol('[') then
        Continue;
      Inner := NextCode(Tokens, Index + 1);
      Close := NextCode(Tokens, Inner + 1);
      if (Close >= AStop) or not SameText(Tokens[Inner].Text, AVar) or not Tokens[Close].IsSymbol(']') then
        Continue;
      if ABaseKey = '' then
      begin
        Before := PreviousCode(Tokens, Index);
        if (Before >= 0) and MatchText(Tokens[Before].Text, ['Items', 'Self']) then
          Exit(True);
        Continue;
      end;
      // Die ABaseCount Code-Token vor [ müssen die Basis ergeben; Basis.Items[I] zählt mit.
      Key := '';
      Before := Index;
      Prev := PreviousCode(Tokens, Index);
      if (Prev > 0) and SameText(Tokens[Prev].Text, 'Items') and Tokens[PreviousCode(Tokens, Prev)].IsSymbol('.') then
        Before := PreviousCode(Tokens, Prev);
      Count := 0;
      while (Count < ABaseCount) and (Before > 0) do
      begin
        Before := PreviousCode(Tokens, Before);
        if Before < 0 then
          Break;
        Key := LowerCase(Tokens[Before].Text) + Key;
        Inc(Count);
      end;
      if Key <> ABaseKey then
        Continue;
      // Andere.Kunden[I] gehört nicht zu Kunden.
      Prev := PreviousCode(Tokens, Before);
      if (Prev < 0) or not Tokens[Prev].IsSymbol('.') then
        Exit(True);
    end;
    Result := False;
  end;

  function CodeCount(AFirst, ALast: Integer): Integer;
  var
    Index: Integer;
  begin
    Result := 0;
    for Index := AFirst to ALast do
      if not IsTrivia(Tokens[Index]) then
        Inc(Result);
  end;

  procedure Inspect(ANode: TSyntaxNode);
  var
    First, Stop, Assign, ToIndex, DoIndex, LowFirst, LowLast, HighFirst, HighLast, Open, Close, Dot,
      BaseFirst, BaseLast: Integer;
    LowKey, BaseKey, BaseText, HighText, TypeName, Message, Replacement, FixTitle: string;
    IsCall, IsString: Boolean;
    Edit: TRuleEdit;
  begin
    Close := -1;
    FixTitle := '';
    Edit := Default(TRuleEdit);
    First := TokenFrom(Tokens, ANode.StartOffset);
    Stop := TokenFrom(Tokens, ANode.EndOffset);
    Assign := AtDepthZero(First, Stop, ':=', False);
    if Assign < 0 then
      Exit;
    ToIndex := AtDepthZero(Assign + 1, Stop, 'to', True);
    if ToIndex < 0 then
      Exit; // downto: das prüft for-high-to-low
    DoIndex := AtDepthZero(ToIndex + 1, Stop, 'do', True);
    if DoIndex < 0 then
      Exit;
    LowFirst := NextCode(Tokens, Assign + 1);
    LowLast := PreviousCode(Tokens, ToIndex);
    HighFirst := NextCode(Tokens, ToIndex + 1);
    HighLast := PreviousCode(Tokens, DoIndex);
    if (LowLast < LowFirst) or (HighLast < HighFirst) then
      Exit;
    LowKey := CodeKey(Tokens, LowFirst, LowLast);
    HighText := Trim(SourceText(AContext.Text, Tokens, HighFirst, HighLast));
    BaseFirst := -1;
    BaseLast := -1;
    IsCall := False;
    // Length(A): Name aus countNames mit Klammer um die ganze Obergrenze (oder mit - 1 bei Strings).
    Open := NextCode(Tokens, HighFirst + 1);
    if (Tokens[HighFirst].Kind = TPascalTokenKind.Identifier) and (IndexText(Tokens[HighFirst].Text, CountNames) >= 0) and
      (Open <= HighLast) and Tokens[Open].IsSymbol('(') then
    begin
      Close := Closing(Tokens, Open, HighLast + 1);
      if Close > Open + 1 then
      begin
        IsCall := True;
        BaseFirst := NextCode(Tokens, Open + 1);
        BaseLast := PreviousCode(Tokens, Close);
        if Close <> HighLast then
        begin
          // Nur "Length(S) - 1" bei Strings; sonst ist es kein einfacher Fall.
          if CodeKey(Tokens, Close + 1, HighLast) <> '-1' then
            Exit;
        end;
      end;
    end
    // X.Count bzw. Count: letzter Name aus countNames.
    else if (Tokens[HighLast].Kind = TPascalTokenKind.Identifier) and
      (IndexText(Tokens[HighLast].Text, CountNames) >= 0) then
    begin
      Dot := PreviousCode(Tokens, HighLast);
      if HighLast = HighFirst then
      begin
        BaseFirst := HighLast + 1;
        BaseLast := HighLast; // leer: Items[I]
      end
      else if (Dot >= HighFirst) and Tokens[Dot].IsSymbol('.') and (Dot > HighFirst) then
      begin
        BaseFirst := HighFirst;
        BaseLast := PreviousCode(Tokens, Dot);
      end
      else
        Exit;
    end
    else
      Exit;
    if BaseFirst < 0 then
      Exit;
    if BaseLast >= BaseFirst then
    begin
      BaseKey := CodeKey(Tokens, BaseFirst, BaseLast);
      BaseText := Trim(SourceText(AContext.Text, Tokens, BaseFirst, BaseLast));
    end
    else
    begin
      BaseKey := '';
      BaseText := '';
    end;
    TypeName := '';
    if (BaseFirst = BaseLast) and (Tokens[BaseFirst].Kind = TPascalTokenKind.Identifier) then
      TypeName := Types.DeclaredType(Tokens[BaseFirst].Text, Tokens[BaseFirst].StartPos);
    IsString := IsCall and IsStringType(TypeName);
    if not BodyIndexes(DoIndex + 1, Stop, BaseKey, CodeCount(BaseFirst, BaseLast), ANode.Name) then
      Exit;
    Message := '';
    if IsString then
    begin
      Replacement := Format('Low(%s) to High(%s)', [BaseText, BaseText]);
      FixTitle := Format('Low(%s)/High(%s) verwenden', [BaseText, BaseText]);
      Edit := TRuleEdit.Create(TTextRange.Create(Tokens[LowFirst].StartPos, Tokens[HighLast].EndPos), Replacement);
      if not ZeroBased and (LowKey = '0') then
        Message := Format('Strings beginnen bei 1: der erste Durchlauf greift auf %s[0].', [BaseText])
      else if ZeroBased and (LowKey = '0') and (Close = HighLast) then
        Message := Format('Obergrenze %s: der letzte Durchlauf greift hinter das String-Ende ' +
          '(mit {$ZEROBASEDSTRINGS ON} sind Strings nullbasiert).', [HighText])
      else if ZeroBased and (LowKey = '1') and (Close = HighLast) then
        Message := Format('Mit {$ZEROBASEDSTRINGS ON} sind Strings nullbasiert: die Schleife überspringt %s[0] ' +
          'und greift hinter das Ende.', [BaseText]);
    end
    else if (LowKey = '0') and (not IsCall or (Close = HighLast)) then
    begin
      if IsCall then
      begin
        Message := Format('Obergrenze %s: der letzte Durchlauf greift hinter das Array-Ende (Index %s).',
          [HighText, Tokens[HighFirst].Text]);
        FixTitle := Format('High(%s) verwenden', [BaseText]);
        Edit := TRuleEdit.Create(TTextRange.Create(Tokens[HighFirst].StartPos, Tokens[HighLast].EndPos),
          Format('High(%s)', [BaseText]));
      end
      else
      begin
        Message := Format('Obergrenze %s: der letzte Durchlauf greift hinter das Listenende (Index %s).',
          [HighText, Tokens[HighLast].Text]);
        FixTitle := '„- 1“ ergänzen';
        Edit := TRuleEdit.Create(TTextRange.Create(Tokens[HighLast].EndPos, Tokens[HighLast].EndPos), ' - 1');
      end;
    end;
    if Message = '' then
      Exit;
    AReport.Add(TTextRange.Create(Tokens[LowFirst].StartPos, Tokens[HighLast].EndPos), Message, TRuleConfidence.High,
      [TRuleFix.Create(FixTitle, [Edit])]);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.ForStatement then
          Inspect(Node);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // S[0] bei einsbasierten Strings.
  procedure FindZeroIndex;
  var
    Index, Open, Zero, Close, Prev: Integer;
    Name: string;
  begin
    for Index := 0 to High(Tokens) do
    begin
      if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
        Continue;
      Open := NextCode(Tokens, Index + 1);
      if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('[') then
        Continue;
      Zero := NextCode(Tokens, Open + 1);
      Close := NextCode(Tokens, Zero + 1);
      if (Close > High(Tokens)) or not ((Tokens[Zero].Kind = TPascalTokenKind.Number) and (Tokens[Zero].Text = '0')) or
        not Tokens[Close].IsSymbol(']') or not InBlock(Tokens[Index].Offset) then
        Continue;
      Prev := PreviousCode(Tokens, Index);
      if (Prev >= 0) and (Tokens[Prev].IsSymbol('.') or Tokens[Prev].IsSymbol('@')) then
        Continue;
      Name := Tokens[Index].Text;
      if not IsStringType(Types.DeclaredType(Name, Tokens[Index].StartPos)) then
        Continue;
      AReport.Add(TTextRange.Create(Tokens[Index].StartPos, Tokens[Close].EndPos),
        Format('Strings beginnen bei 1: %s[0] liegt vor dem ersten Zeichen.', [Name]), TRuleConfidence.High,
        [TRuleFix.Create(Format('Low(%s) verwenden', [Name]),
        [TRuleEdit.Create(TTextRange.Create(Tokens[Zero].StartPos, Tokens[Zero].EndPos), Format('Low(%s)', [Name]))])]);
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  CountNames := TRuleOptions.Strings(AContext.Options, 'countNames', ['Count', 'Length']);
  ZeroBased := ZeroBasedStrings(Tokens);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Blocks := nil;
    CollectBlocks(AContext.Tree.Root);
    Visit(AContext.Tree.Root);
    if not ZeroBased then
      FindZeroIndex;
  finally
    Types.Free;
  end;
end;

{ TCollectionModifiedInLoopRule }

class function TCollectionModifiedInLoopRule.DefaultMutatingMethods: TArray<string>;
begin
  Result := ['Add', 'Insert', 'Delete', 'Remove', 'Extract', 'Clear'];
end;

function TCollectionModifiedInLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(CollectionModifiedInLoopRuleId, TRuleSeverity.Warning,
    'Liste in der eigenen Schleife verändert');
end;

procedure TCollectionModifiedInLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Methods: TArray<string>;

  function CodeCount(AFirst, ALast: Integer): Integer;
  var
    Index: Integer;
  begin
    Result := 0;
    for Index := AFirst to ALast do
      if not IsTrivia(Tokens[Index]) then
        Inc(Result);
  end;

  // Folgt auf die Anweisung mit dem Aufruf (ab ACall) direkt Break oder Exit?
  function LeavesLoop(ACall, AStop: Integer): Boolean;
  var
    Semicolon, Next: Integer;
  begin
    Semicolon := DepthZero(Tokens, ACall, AStop, ';', False);
    if Semicolon < 0 then
      Exit(False);
    Next := NextCode(Tokens, Semicolon + 1);
    Result := (Next < AStop) and MatchText(Tokens[Next].Text, ['Break', 'Exit']);
  end;

  // Basis der Obergrenze: X in X.Count - 1, X.Count, High(X), Pred(X.Count), Length(X) - 1; sonst False.
  function BaseOfBound(AFirst, ALast: Integer; out ABaseFirst, ABaseLast: Integer): Boolean;
  var
    Last, Open, Close, Dot: Integer;
  begin
    Result := False;
    ABaseFirst := -1;
    ABaseLast := -1;
    Last := ALast;
    // "- 1" am Ende abtrennen.
    if (CodeCount(AFirst, ALast) > 2) and (Tokens[ALast].Kind = TPascalTokenKind.Number) and (Tokens[ALast].Text = '1') and
      Tokens[PreviousCode(Tokens, ALast)].IsSymbol('-') then
      Last := PreviousCode(Tokens, PreviousCode(Tokens, ALast));
    if (Tokens[AFirst].Kind = TPascalTokenKind.Identifier) and MatchText(Tokens[AFirst].Text, ['High', 'Length', 'Pred']) then
    begin
      Open := NextCode(Tokens, AFirst + 1);
      if not Tokens[Open].IsSymbol('(') then
        Exit;
      Close := Closing(Tokens, Open, Last + 1);
      if (Close <> Last) or (Close <= Open + 1) then
        Exit;
      if SameText(Tokens[AFirst].Text, 'Pred') then
        Exit(BaseOfBound(NextCode(Tokens, Open + 1), PreviousCode(Tokens, Close), ABaseFirst, ABaseLast));
      ABaseFirst := NextCode(Tokens, Open + 1);
      ABaseLast := PreviousCode(Tokens, Close);
      Exit(True);
    end;
    if (Tokens[Last].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Last].Text, 'Count') then
    begin
      Dot := PreviousCode(Tokens, Last);
      if (Dot > AFirst) and Tokens[Dot].IsSymbol('.') then
      begin
        ABaseFirst := AFirst;
        ABaseLast := PreviousCode(Tokens, Dot);
        Result := True;
      end;
    end;
  end;

  // Meldet BaseKey.M( im Rumpf AFrom..AStop-1.
  procedure FindCalls(AFrom, AStop: Integer; const ABaseKey, ABaseText: string; ABaseCount: Integer;
    AForIn: Boolean; const AFix: TArray<TRuleFix>);
  var
    Index, Dot, Open: Integer;
    Method, Message: string;
    Fixes: TArray<TRuleFix>;
  begin
    for Index := AFrom to AStop - 1 do
    begin
      if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or (IndexText(Tokens[Index].Text, Methods) < 0) then
        Continue;
      Dot := PreviousCode(Tokens, Index);
      Open := NextCode(Tokens, Index + 1);
      if (Dot < 0) or not Tokens[Dot].IsSymbol('.') or not BaseBefore(Tokens, Dot, ABaseKey, ABaseCount) then
        Continue;
      // Clear ohne Klammern ist auch ein Aufruf; sonst muss "(" folgen.
      if not SameText(Tokens[Index].Text, 'Clear') and ((Open >= AStop) or not Tokens[Open].IsSymbol('(')) then
        Continue;
      if LeavesLoop(Index, AStop) then
        Continue;
      Method := Tokens[Index].Text;
      Fixes := nil;
      if AForIn then
        Message := Format('%s.%s in for … in über %s: die RTL wirft eine Exception, weil sich die Liste ändert. ' +
          'Elemente sammeln und nach der Schleife ändern.', [ABaseText, Method, ABaseText])
      else if MatchText(Method, ['Add']) then
        Message := Format('%s.%s in einer Vorwärtsschleife über %s: die neuen Elemente durchläuft die Schleife ' +
          'nicht, die Obergrenze steht beim Start fest.', [ABaseText, Method, ABaseText])
      else if MatchText(Method, ['Insert']) then
        Message := Format('%s.%s in einer Vorwärtsschleife über %s: die Elemente rücken nach, dasselbe Element ' +
          'kommt noch einmal, am Ende fehlen Elemente.', [ABaseText, Method, ABaseText])
      else
      begin
        Message := Format('%s.%s in einer Vorwärtsschleife über %s: das nächste Element wird übersprungen, ' +
          'am Ende folgt ein Indexfehler.', [ABaseText, Method, ABaseText]);
        Fixes := AFix;
      end;
      AReport.Add(TTextRange.Create(Tokens[PreviousCode(Tokens, Dot)].StartPos, Tokens[Index].EndPos), Message,
        TRuleConfidence.High, Fixes);
    end;
  end;

  procedure Inspect(ANode: TSyntaxNode);
  var
    First, Stop, Assign, ToIndex, InIndex, DoIndex, LowFirst, LowLast, HighFirst, HighLast, BaseFirst,
      BaseLast: Integer;
    BaseKey, BaseText, LowText, HighText: string;
    Fix: TArray<TRuleFix>;
  begin
    First := TokenFrom(Tokens, ANode.StartOffset);
    Stop := TokenFrom(Tokens, ANode.EndOffset);
    if ANode.Kind = TSyntaxKind.ForInStatement then
    begin
      InIndex := DepthZero(Tokens, First, Stop, 'in', True);
      DoIndex := DepthZero(Tokens, First, Stop, 'do', True);
      if (InIndex < 0) or (DoIndex < InIndex) then
        Exit;
      BaseFirst := NextCode(Tokens, InIndex + 1);
      BaseLast := PreviousCode(Tokens, DoIndex);
      if BaseLast < BaseFirst then
        Exit;
      BaseText := Trim(SourceText(AContext.Text, Tokens, BaseFirst, BaseLast));
      FindCalls(DoIndex + 1, Stop, CodeKey(Tokens, BaseFirst, BaseLast), BaseText, CodeCount(BaseFirst, BaseLast),
        True, nil);
      Exit;
    end;
    Assign := DepthZero(Tokens, First, Stop, ':=', False);
    if Assign < 0 then
      Exit;
    ToIndex := DepthZero(Tokens, Assign + 1, Stop, 'to', True);
    if ToIndex < 0 then
      Exit; // downto: rückwärts ist Löschen unbedenklich
    DoIndex := DepthZero(Tokens, ToIndex + 1, Stop, 'do', True);
    if DoIndex < 0 then
      Exit;
    LowFirst := NextCode(Tokens, Assign + 1);
    LowLast := PreviousCode(Tokens, ToIndex);
    HighFirst := NextCode(Tokens, ToIndex + 1);
    HighLast := PreviousCode(Tokens, DoIndex);
    if (LowLast < LowFirst) or (HighLast < HighFirst) or not BaseOfBound(HighFirst, HighLast, BaseFirst, BaseLast) then
      Exit;
    BaseKey := CodeKey(Tokens, BaseFirst, BaseLast);
    BaseText := Trim(SourceText(AContext.Text, Tokens, BaseFirst, BaseLast));
    LowText := Trim(SourceText(AContext.Text, Tokens, LowFirst, LowLast));
    HighText := Trim(SourceText(AContext.Text, Tokens, HighFirst, HighLast));
    Fix := [TRuleFix.Create('Schleife rückwärts (downto) umschreiben',
      [TRuleEdit.Create(TTextRange.Create(Tokens[LowFirst].StartPos, Tokens[HighLast].EndPos),
      HighText + ' downto ' + LowText)])];
    FindCalls(DoIndex + 1, Stop, BaseKey, BaseText, CodeCount(BaseFirst, BaseLast), False, Fix);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
          Inspect(Node);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Methods := TRuleOptions.Strings(AContext.Options, 'mutatingMethods', DefaultMutatingMethods);
  Visit(AContext.Tree.Root);
end;

{ TDestroyCalledDirectlyRule }

function TDestroyCalledDirectlyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DestroyCalledDirectlyRuleId, TRuleSeverity.Warning,
    'Destroy statt Free aufgerufen');
end;

procedure TDestroyCalledDirectlyRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Node, Target: TSyntaxNode;
    Index, Name: Integer;
    Range: TTextRange;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.CallStatement) and (Node.ChildCount > 0) then
        begin
          Target := Node[0];
          // X.Destroy() ohne Argumente zählt wie X.Destroy.
          if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount = 1) then
            Target := Target[0];
          if (Target.Kind = TSyntaxKind.MemberAccess) and (Target.ChildCount = 1) and
            SameText(Target.Name, 'Destroy') then
          begin
            // Name ist das letzte Token "Destroy" im Zugriff.
            Name := -1;
            for Index := TokenFrom(Tokens, Target.StartOffset) to High(Tokens) do
            begin
              if Tokens[Index].Offset >= Target.EndOffset then
                Break;
              if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, 'Destroy') then
                Name := Index;
            end;
            if Name >= 0 then
            begin
              Range := TTextRange.Create(Tokens[Name].StartPos, Tokens[Name].EndPos);
              AReport.Add(Range, 'Destroy direkt aufgerufen; Free prüft vorher auf nil.', TRuleConfidence.High,
                [TRuleFix.Create('Free statt Destroy', [TRuleEdit.Create(Range, 'Free')], True)]);
            end;
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Visit(AContext.Tree.Root);
end;

{ TCaseMissingEnumValueRule }

function TCaseMissingEnumValueRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(CaseMissingEnumValueRuleId, TRuleSeverity.Warning,
    'case über Aufzählung ohne alle Werte');
end;

procedure TCaseMissingEnumValueRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  FileName: string;
  RequireElse: Boolean;

  // Kette A.B.C aus Bezeichnern; False bei Aufrufen, Indizes und Ausdrücken.
  function Chain(ANode: TSyntaxNode; var ANames: TArray<string>): Boolean;
  var
    Node: TSyntaxNode;
    Members: TArray<string>;
    Index: Integer;
  begin
    // Iterativ (Bericht M1): von rechts nach links an der Kette entlang; die Namen der Zugriffe kommen erst nach
    // dem Bezeichner ganz links dazu.
    Members := nil;
    Node := ANode;
    while (Node.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.ParenExpr]) and (Node.ChildCount = 1) do
    begin
      if Node.Kind = TSyntaxKind.MemberAccess then
        Members := Members + [Node.Name];
      Node := Node[0];
    end;
    Result := Node.Kind = TSyntaxKind.Identifier;
    if not Result then
      Exit;
    ANames := ANames + [Node.Name];
    for Index := High(Members) downto 0 do
      ANames := ANames + [Members[Index]];
  end;

  function OwnerUnit(const AType: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
  begin
    if SameText(AType.FileName, FileName) then
    begin
      AUnit := Resolver.ExtractedUnit(AContext.Tree, FileName);
      Exit(True);
    end;
    Result := (AContext.Index <> nil) and AContext.Index.FindFile(AType.FileName, AUnit);
  end;

  // Werte des Aufzählungstyps in Deklarationsreihenfolge; Aliase werden verfolgt.
  function EnumValues(AType: TResolvedSymbol; out ATypeName: string): TArray<string>;
  var
    Owner: TUnitIndex;
    Step: Integer;
    Symbol: TIndexSymbol;
    Container: string;
  begin
    Result := nil;
    ATypeName := '';
    for Step := 1 to 4 do
    begin
      if not AType.Found or not AType.IsType or not OwnerUnit(AType, Owner) then
        Exit;
      if AType.SymbolKind = TIndexSymbolKind.EnumType then
      begin
        ATypeName := AType.Name;
        Container := AType.QualifiedName;
        for Symbol in Owner.Symbols do
          if (Symbol.Kind = TIndexSymbolKind.EnumMember) and SameText(Symbol.Container, Container) then
            Result := Result + [Symbol.Name];
        Exit;
      end;
      if (AType.SymbolKind <> TIndexSymbolKind.TypeAlias) or (AType.TypeName = '') or
        not Resolver.ResolveTypeFrom(Owner, AType.TypeName, AType) then
        Exit;
    end;
  end;

  procedure CheckCase(ACase: TSyntaxNode);
  var
    Names, Values, Absent: TArray<string>;
    Owner, TypeSymbol: TResolvedSymbol;
    TypeFound, HasElse: Boolean;
    OfPos: TTextPosition;
    Slot: TCaseBranchSlot;
    TypeName, Prefix, LabelText: string;
    Edits: TArray<TTextEdit>;
    Count: Integer;
    Fixes: TArray<TRuleFix>;
  begin
    if ACase.ChildCount = 0 then
      Exit;
    HasElse := ACase.FindChild(TSyntaxKind.CaseElse) <> nil;
    if HasElse and not RequireElse then
      Exit;
    Names := nil;
    if not Chain(ACase[0], Names) or not TCaseCompletion.OfPosition(AContext.Tree, ACase, OfPos) or
      not TCaseCompletion.BranchSlot(AContext.Text, AContext.Tree.Tokens, OfPos, Slot) then
      Exit;
    if not Resolver.ChainType(AContext.Tree, FileName, Names, ACase[0].EndOffset, Owner, TypeSymbol, TypeFound) or
      not TypeFound then
      Exit;
    Values := EnumValues(TypeSymbol, TypeName);
    if (Values = nil) or not TCaseCompletion.Missing(Values, Slot.Labels, Absent) or (Absent = nil) then
      Exit;
    // {$SCOPEDENUMS ON}: die vorhandenen Marken tragen den Typnamen.
    Prefix := '';
    for LabelText in Slot.Labels do
      if Pos('.', StringReplace(LabelText, '..', '', [rfReplaceAll])) > 0 then
        Prefix := TypeName + '.';
    Fixes := nil;
    if TCaseCompletion.Complete(AContext.Text, AContext.Tree, ACase, Values, Prefix, Edits, Count, HasElse) then
      Fixes := [TRuleFix.Create(Format('Fehlende Werte ergänzen (%d)', [Count]), Edits)];
    AReport.Add(TTextRange.Create(ACase[0].StartPos, ACase[0].EndPos), Format('Fehlende Werte von %s: %s.',
      [TypeName, string.Join(', ', Absent)]), TRuleConfidence.High, Fixes);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.CaseStatement then
          CheckCase(Node);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  RequireElse := TRuleOptions.Bool(AContext.Options, 'requireElse', False);
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Visit(AContext.Tree.Root);
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

/// <summary>Methode bzw. Routine einer Aufrufanweisung (Break, Q.Next, Q.Insert(…)); AReceiver ist der Text vor
/// dem Punkt, AArguments die Zahl der Argumente. '' bei anderen Anweisungen.</summary>
function StatementCall(const AText: string; ANode: TSyntaxNode; out AReceiver: string;
  out AArguments: Integer): string;
var
  Target: TSyntaxNode;
begin
  Result := '';
  AReceiver := '';
  AArguments := 0;
  if (ANode.Kind <> TSyntaxKind.CallStatement) or (ANode.ChildCount = 0) then
    Exit;
  Target := ANode[0];
  if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount > 0) then
  begin
    AArguments := Target.ChildCount - 1;
    Target := Target[0];
  end;
  if Target.Kind = TSyntaxKind.MemberAccess then
  begin
    if Target.ChildCount > 0 then
      AReceiver := Copy(AText, Target[0].StartOffset + 1, Target[0].EndOffset - Target[0].StartOffset);
    Result := Target.Name;
  end
  else if Target.Kind = TSyntaxKind.Identifier then
    Result := Target.Name;
end;

{ TDatasetLoopWithoutNextRule }

const
  // Methoden, die den Datensatzzeiger weiterbewegen oder die Schleife über Eof beenden.
  DatasetAdvancing: array[0..6] of string = ('Next', 'Delete', 'MoveBy', 'Last', 'Close', 'FindNext', 'Free');

function TDatasetLoopWithoutNextRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dataset-loop-without-next', TRuleSeverity.Error,
    'Datenmengen-Schleife ohne Next');
end;

procedure TDatasetLoopWithoutNextRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<string>;
  LineBreak: string;
  DataSet: string;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function StatementName(ANode: TSyntaxNode; out AReceiver: string): string;
  var
    Arguments: Integer;
  begin
    Result := StatementCall(AContext.Text, ANode, AReceiver, Arguments);
  end;

  function IsAdvance(ANode: TSyntaxNode): Boolean;
  var
    Receiver, Name: string;
  begin
    Name := StatementName(ANode, Receiver);
    Result := SameText(Receiver, DataSet) and MatchText(Name, DatasetAdvancing);
  end;

  // Continue in ANode, außer in inneren Schleifen?
  function HasContinue(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
    Receiver: string;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.ForStatement,
          TSyntaxKind.ForInStatement, TSyntaxKind.AnonymousMethod] then
          Continue;
        if SameText(StatementName(Node, Receiver), 'Continue') and (Receiver = '') then
          Exit(True);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Teile von ANode, von deren Advances das Ergebnis für ANode abhängt (in Quelltextreihenfolge).
  function AdvanceParts(ANode: TSyntaxNode): TArray<TSyntaxNode>;
  var
    Index: Integer;
  begin
    Result := nil;
    case ANode.Kind of
      TSyntaxKind.Block, TSyntaxKind.FinallyBlock, TSyntaxKind.CaseElse:
        for Index := 0 to ANode.ChildCount - 1 do
          Result := Result + [ANode[Index]];
      TSyntaxKind.IfStatement:
        if ANode.ChildCount = 3 then
          Result := [ANode[1], ANode[2]];
      TSyntaxKind.CaseStatement:
        for Index := 1 to ANode.ChildCount - 1 do
          if ANode[Index].Kind = TSyntaxKind.CaseItem then
            Result := Result + [ANode[Index][ANode[Index].ChildCount - 1]]
          else if ANode[Index].Kind = TSyntaxKind.CaseElse then
            Result := Result + [ANode[Index]];
      TSyntaxKind.TryStatement:
        for Index := 0 to ANode.ChildCount - 1 do
          if ANode[Index].Kind <> TSyntaxKind.ExceptBlock then
            Result := Result + [ANode[Index]];
      TSyntaxKind.WithStatement:
        Result := [ANode[ANode.ChildCount - 1]];
      // repeat läuft mindestens einmal; while und for vielleicht nie.
      TSyntaxKind.RepeatStatement:
        for Index := 0 to ANode.ChildCount - 2 do
          Result := Result + [ANode[Index]];
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  // Endet jeder Weg durch ANode, der die Schleife fortsetzt, mit einem Weiterbewegen?
  function Advances(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
    Receiver, Name: string;
    Node: TSyntaxNode;
    Parts: TArray<TSyntaxNode>;
    Entry: TSyntaxPostOrderEntry;
    Value: Boolean;
    Pending: TStack<TSyntaxPostOrderEntry>;
    Values: TDictionary<TSyntaxNode, Boolean>;
  begin
    // Iterativ (Bericht M1): Nachordnung, die Teile zuerst; lange else-if-Ketten ergeben sehr tiefe Bäume.
    Result := False;
    if ANode = nil then
      Exit;
    Pending := TStack<TSyntaxPostOrderEntry>.Create;
    Values := TDictionary<TSyntaxNode, Boolean>.Create;
    try
      Pending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
      while Pending.Count > 0 do
      begin
        Entry := Pending.Pop;
        Node := Entry.Node;
        Parts := AdvanceParts(Node);
        if not Entry.Done then
        begin
          Pending.Push(TSyntaxPostOrderEntry.Create(Node, True));
          for Index := High(Parts) downto 0 do
            Pending.Push(TSyntaxPostOrderEntry.Create(Parts[Index], False));
          Continue;
        end;
        Value := False;
        case Node.Kind of
          TSyntaxKind.CallStatement:
            begin
              Name := StatementName(Node, Receiver);
              // Break, Exit und Halt verlassen die Schleife; Continue setzt sie ohne Weiterbewegen fort.
              Value := IsAdvance(Node) or ((Receiver = '') and MatchText(Name, ['Break', 'Exit', 'Halt', 'Abort']));
            end;
          TSyntaxKind.RaiseStatement:
            Value := True;
          TSyntaxKind.Block, TSyntaxKind.FinallyBlock, TSyntaxKind.CaseElse:
            for Index := 0 to High(Parts) do
            begin
              if Values[Parts[Index]] then
              begin
                Value := True;
                Break;
              end;
              // Ein Continue vor dem Weiterbewegen setzt die Schleife auf demselben Datensatz fort.
              if HasContinue(Parts[Index]) then
                Break;
            end;
          TSyntaxKind.IfStatement:
            Value := (Length(Parts) = 2) and Values[Parts[0]] and Values[Parts[1]];
          TSyntaxKind.CaseStatement:
            begin
              Value := Node.FindChild(TSyntaxKind.CaseElse) <> nil;
              for Index := 0 to High(Parts) do
                Value := Value and Values[Parts[Index]];
            end;
          TSyntaxKind.TryStatement, TSyntaxKind.WithStatement, TSyntaxKind.RepeatStatement:
            for Index := 0 to High(Parts) do
              if Values[Parts[Index]] then
              begin
                Value := True;
                Break;
              end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        Values.AddOrSetValue(Node, Value);
      end;
      Result := Values[ANode];
    finally
      Values.Free;
      Pending.Free;
    end;
  end;

  // Kommt die Datenmenge im Rumpf vor, außer als Empfänger (Argument, Zuweisung, with)?
  // Dann bewegt vielleicht der Aufgerufene den Zeiger.
  function Escapes(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
    Node, Parent: TSyntaxNode;
    Pending, Parents: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1): zu jedem Knoten auf dem Stapel sein Elternknoten (nil an der Wurzel).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    Parents := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      Parents.Push(nil);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Parent := Parents.Pop;
        if Node.Kind = TSyntaxKind.AnonymousMethod then
          Continue;
        if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
          SameText(NodeText(Node), DataSet) and
          not ((Parent <> nil) and (Parent.Kind = TSyntaxKind.MemberAccess) and (Parent[0] = Node)) then
          Exit(True);
        if Node.Kind = TSyntaxKind.WithStatement then
          Exit(True);
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          Parents.Push(Node);
        end;
      end;
    finally
      Parents.Free;
      Pending.Free;
    end;
  end;

  function MentionsAdvance(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if IsAdvance(Node) then
          Exit(True);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Korrektur: Q.Next; vor dem end des Rumpfs.
  function NextFix(ABody: TSyntaxNode): TArray<TRuleFix>;
  var
    EndLine: Integer;
  begin
    Result := nil;
    if ABody.Kind <> TSyntaxKind.Block then
      Exit;
    EndLine := ABody.EndPos.Line;
    if (EndLine <= ABody.StartPos.Line) or (Trim(Copy(Lines[EndLine], 1, ABody.EndPos.Character - Length('end'))) <> '') then
      Exit;
    Result := [TRuleFix.Create(Format('%s.Next; am Ende des Rumpfs einfügen', [DataSet]), [TRuleEdit.Create(
      TTextRange.Create(EndLine, 0, EndLine, 0), TTextLines.IndentOf(Lines[EndLine]) +
      TRoutineBody.IndentUnit(AContext.Formatting) + DataSet + '.Next;' + LineBreak)])];
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node, Condition, Body: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        // while not Q.Eof do …
        if (Node.Kind = TSyntaxKind.WhileStatement) and (Node.ChildCount = 2) then
        begin
          Condition := Node[0];
          Body := Node[1];
          if (Condition.Kind = TSyntaxKind.UnaryExpr) and SameText(Condition.Name, 'not') and
            (Condition.ChildCount = 1) and (Condition[0].Kind = TSyntaxKind.MemberAccess) and
            SameText(Condition[0].Name, 'Eof') and (Condition[0].ChildCount = 1) then
          begin
            DataSet := NodeText(Condition[0][0]);
            if not Escapes(Body) and not Advances(Body) then
              if not MentionsAdvance(Body) then
                AReport.Add(TTextRange.Create(Condition.StartPos, Condition.EndPos),
                  Format('Im Rumpf fehlt %s.Next; die Schleife läuft endlos.', [DataSet]), TRuleConfidence.High,
                  NextFix(Body))
              else
                AReport.Add(TTextRange.Create(Condition.StartPos, Condition.EndPos),
                  Format('Nicht jeder Weg durch den Rumpf ruft %s.Next auf; dort läuft die Schleife endlos.',
                  [DataSet]), TRuleConfidence.Medium);
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Eof') then
    Exit;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Visit(AContext.Tree.Root);
end;

{ TDatasetEditWithoutPostRule }

const
  DatasetEditMethods: array[0..2] of string = ('Edit', 'Append', 'Insert');
  // Methoden, die den Bearbeitungsmodus beenden.
  DatasetPostMethods: array[0..2] of string = ('Post', 'Cancel', 'CheckBrowseMode');

function TDatasetEditWithoutPostRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dataset-edit-without-post', TRuleSeverity.Warning, 'Edit oder Append ohne Post');
end;

procedure TDatasetEditWithoutPostRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<string>;
  LineBreak: string;
  Routines: TArray<TSyntaxNode>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  // Beendet ANode (oder ein Nachfahr ab AFrom) den Bearbeitungsmodus von ADataSet?
  function Ends(ANode: TSyntaxNode; const ADataSet: string; AFrom: Integer): Boolean;
  var
    Index, Arguments: Integer;
    Receiver, Name: string;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.StartOffset >= AFrom then
        begin
          Name := StatementCall(AContext.Text, Node, Receiver, Arguments);
          if SameText(Receiver, ADataSet) and MatchText(Name, DatasetPostMethods) then
            Exit(True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          if Node[Index].EndOffset > AFrom then
            Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Kommt ADataSet ab AFrom als Wert vor (Argument, Zuweisung), nicht nur als Empfänger (Q.X, Q['X'])?
  function Escapes(ANode: TSyntaxNode; const ADataSet: string; AFrom: Integer): Boolean;
  var
    Index: Integer;
    Node, Parent: TSyntaxNode;
    Pending, Parents: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1): zu jedem Knoten auf dem Stapel sein Elternknoten (nil an der Wurzel). Eine Nennung
    // der Datenmenge als Empfänger beendet nur ihren Zweig, wie in der Rekursion.
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    Parents := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      Parents.Push(nil);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Parent := Parents.Pop;
        if (Node.StartOffset >= AFrom) and (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
          SameText(NodeText(Node), ADataSet) then
        begin
          if not ((Parent <> nil) and (Parent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) and
            (Parent[0] = Node)) then
            Exit(True);
          Continue;
        end;
        if (Node.StartOffset >= AFrom) and (Node.Kind = TSyntaxKind.WithStatement) then
          Exit(True);
        for Index := Node.ChildCount - 1 downto 0 do
          if Node[Index].EndOffset > AFrom then
          begin
            Pending.Push(Node[Index]);
            Parents.Push(Node);
          end;
      end;
    finally
      Parents.Free;
      Pending.Free;
    end;
  end;

  function UsesDataSet(ANode: TSyntaxNode; const ADataSet: string): Boolean;
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
          SameText(NodeText(Node), ADataSet) then
          Exit(True);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  function OwnLine(ANode: TSyntaxNode): Boolean;
  var
    Rest: string;
  begin
    Rest := Trim(Copy(Lines[ANode.EndPos.Line], ANode.EndPos.Character + 1, MaxInt));
    Result := (Trim(Copy(Lines[ANode.StartPos.Line], 1, ANode.StartPos.Character)) = '') and
      ((Rest = '') or (Rest = ';')) and (ANode.EndPos.Line < High(Lines));
  end;

  // Korrektur: die folgenden Anweisungen, die die Datenmenge benutzen, in try … Post … except Cancel; raise; end.
  function PostFix(AStatement: TSyntaxNode; const ADataSet: string): TArray<TRuleFix>;
  var
    List: TSyntaxNode;
    Index, Position, Last, Line: Integer;
    Indent, Step, Text: string;
  begin
    Result := nil;
    List := AStatement.Parent;
    if (List = nil) or not OwnLine(AStatement) then
      Exit;
    Position := -1;
    for Index := 0 to List.ChildCount - 1 do
      if List[Index] = AStatement then
        Position := Index;
    Last := Position;
    while (Last + 1 < List.ChildCount) and (List[Last + 1].Kind in [TSyntaxKind.AssignStatement,
      TSyntaxKind.CallStatement]) and UsesDataSet(List[Last + 1], ADataSet) and OwnLine(List[Last + 1]) do
      Inc(Last);
    if (Position < 0) or (Last = Position) then
      Exit;
    Indent := TTextLines.IndentOf(Lines[AStatement.StartPos.Line]);
    Step := TRoutineBody.IndentUnit(AContext.Formatting);
    Text := Indent + 'try' + LineBreak;
    for Line := List[Position + 1].StartPos.Line to List[Last].EndPos.Line do
      Text := Text + Step + Lines[Line] + LineBreak;
    Text := Text + Indent + Step + ADataSet + '.Post;' + LineBreak + Indent + 'except' + LineBreak + Indent + Step +
      ADataSet + '.Cancel;' + LineBreak + Indent + Step + 'raise;' + LineBreak + Indent + 'end;' + LineBreak;
    Result := [TRuleFix.Create(Format('%s.Post mit try … except Cancel ergänzen', [ADataSet]), [TRuleEdit.Create(
      TTextRange.Create(List[Position + 1].StartPos.Line, 0, List[Last].EndPos.Line + 1, 0), Text)])];
  end;

  // Beendet eine andere Routine der Unit den Bearbeitungsmodus (Bearbeiten-/Speichern-Knopf)?
  function EndedElsewhere(ARoutine: TSyntaxNode; const ADataSet: string): Boolean;
  var
    Other: TSyntaxNode;
  begin
    for Other in Routines do
      if (Other <> ARoutine) and Ends(Other, ADataSet, 0) then
        Exit(True);
    Result := False;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index, Arguments: Integer;
    Receiver, Name: string;
    Node, Routine: TSyntaxNode;
    Pending, PendingRoutines: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1): zu jedem Knoten auf dem Stapel die umgebende Routine.
    Pending := TStack<TSyntaxNode>.Create;
    PendingRoutines := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      PendingRoutines.Push(nil);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Routine := PendingRoutines.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
          Routine := Node;
        if (Routine <> nil) and (Node.Kind = TSyntaxKind.CallStatement) then
        begin
          Name := StatementCall(AContext.Text, Node, Receiver, Arguments);
          if (Receiver <> '') and (Arguments = 0) and MatchText(Name, DatasetEditMethods) and
            not Ends(Routine, Receiver, Node.EndOffset) and not Escapes(Routine, Receiver, Node.EndOffset) and
            not EndedElsewhere(Routine, Receiver) then
            AReport.Add(TTextRange.Create(Node[0].EndPos.Line, Node[0].EndPos.Character - Length(Name),
              Node[0].EndPos.Line, Node[0].EndPos.Character), Format('Nach %s fehlt Post oder Cancel; die ' +
              'Änderung bleibt offen.', [Name]), TRuleConfidence.Medium, PostFix(Node, Receiver));
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          PendingRoutines.Push(Routine);
        end;
      end;
    finally
      PendingRoutines.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Routines := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
        Routines := Routines + [ANode];
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
    end);
  Visit(AContext.Tree.Root);
end;

{ TTransactionWithoutRollbackRule }

const
  // FireDAC, IBX und dbExpress (StartTransaction), dbExpress ab XE (BeginTransaction), ADO (BeginTrans).
  BuiltinTransactionPairs: array[0..2, 0..2] of string = (('StartTransaction', 'Commit', 'Rollback'),
    ('BeginTransaction', 'CommitFreeAndNil', 'RollbackFreeAndNil'), ('BeginTrans', 'CommitTrans', 'RollbackTrans'));

function TTransactionWithoutRollbackRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('transaction-without-rollback', TRuleSeverity.Warning,
    'Transaktion ohne Rollback');
end;

class function TTransactionWithoutRollbackRule.Pairs(const AOptions: string): TArray<TTransactionPair>;
var
  Index: Integer;
  Pair: TTransactionPair;
  Value, List, Item: TJSONValue;
begin
  Result := nil;
  if Trim(AOptions) <> '' then
  begin
    Value := TJSONObject.ParseJSONValue(AOptions);
    try
      if Value is TJSONObject then
      begin
        List := TJSONObject(Value).GetValue('pairs');
        // Eine eigene Liste ersetzt die eingebauten Paare.
        if List is TJSONArray then
        begin
          for Item in TJSONArray(List) do
            if (Item is TJSONObject) and TJSONObject(Item).TryGetValue<string>('start', Pair.Start) and
              TJSONObject(Item).TryGetValue<string>('commit', Pair.Commit) and
              TJSONObject(Item).TryGetValue<string>('rollback', Pair.Rollback) and (Trim(Pair.Start) <> '') and
              (Trim(Pair.Rollback) <> '') then
            begin
              Pair.Start := Trim(Pair.Start);
              Pair.Commit := Trim(Pair.Commit);
              Pair.Rollback := Trim(Pair.Rollback);
              Result := Result + [Pair];
            end;
          Exit;
        end;
      end;
    finally
      Value.Free;
    end;
  end;
  for Index := Low(BuiltinTransactionPairs) to High(BuiltinTransactionPairs) do
  begin
    Pair.Start := BuiltinTransactionPairs[Index, 0];
    Pair.Commit := BuiltinTransactionPairs[Index, 1];
    Pair.Rollback := BuiltinTransactionPairs[Index, 2];
    Result := Result + [Pair];
  end;
end;

procedure TTransactionWithoutRollbackRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<string>;
  LineBreak: string;
  Routines: TArray<TSyntaxNode>;
  Known: TArray<TTransactionPair>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  // Aufruf X.M bzw. X.M(…) in ANode selbst (Anweisung oder rechte Seite einer Zuweisung).
  function CallIn(ANode: TSyntaxNode; out AReceiver: string; out ACall, AMember: TSyntaxNode): string;
  var
    Target: TSyntaxNode;
  begin
    Result := '';
    AReceiver := '';
    ACall := nil;
    AMember := nil;
    if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount > 0) then
      Target := ANode[0]
    else if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) then
      Target := ANode[1]
    else if (ANode.Kind = TSyntaxKind.InlineVar) and (ANode.ChildCount > 0) then
      Target := ANode[ANode.ChildCount - 1]
    else
      Exit;
    if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount > 0) then
    begin
      ACall := Target;
      Target := Target[0];
    end;
    if (Target.Kind = TSyntaxKind.MemberAccess) and (Target.ChildCount > 0) then
    begin
      AReceiver := NodeText(Target[0]);
      AMember := Target;
      Result := Target.Name;
    end;
  end;

  // Ruft ANode (auch verschachtelt) AReceiver.AMethod auf? Nur in except-Teilen, wenn AInExcept.
  function Calls(ANode: TSyntaxNode; const AReceiver, AMethod: string; AInExcept: Boolean): Boolean;
  var
    Index: Integer;
    Receiver: string;
    Node, Call, Member: TSyntaxNode;
    Inside: Boolean;
    Pending: TStack<TSyntaxNode>;
    PendingInside: TStack<Boolean>;
  begin
    // Iterativ (Bericht M1): zu jedem Knoten auf dem Stapel, ob er in einem except-Teil liegt.
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    PendingInside := TStack<Boolean>.Create;
    try
      Pending.Push(ANode);
      PendingInside.Push(False);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Inside := PendingInside.Pop;
        if Node.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
          Continue;
        if Node.Kind = TSyntaxKind.ExceptBlock then
          Inside := True;
        if (Inside or not AInExcept) and SameText(CallIn(Node, Receiver, Call, Member), AMethod) and
          SameText(Receiver, AReceiver) then
          Exit(True);
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          PendingInside.Push(Inside);
        end;
      end;
    finally
      PendingInside.Free;
      Pending.Free;
    end;
  end;

  function OwnLine(ANode: TSyntaxNode): Boolean;
  var
    Rest: string;
  begin
    Rest := Trim(Copy(Lines[ANode.EndPos.Line], ANode.EndPos.Character + 1, MaxInt));
    Result := (Trim(Copy(Lines[ANode.StartPos.Line], 1, ANode.StartPos.Character)) = '') and
      ((Rest = '') or (Rest = ';')) and (ANode.EndPos.Line < High(Lines));
  end;

  // Korrektur: Anweisungen bis zum Commit in try … except Rollback; raise; end.
  function RollbackFix(AList: TSyntaxNode; APosition: Integer; const AReceiver: string;
    const APair: TTransactionPair): TArray<TRuleFix>;
  var
    Index, Last, Line: Integer;
    Receiver, Indent, Step, Text, Arguments: string;
    Call, Member: TSyntaxNode;
  begin
    Result := nil;
    Last := -1;
    Arguments := '';
    for Index := APosition + 1 to AList.ChildCount - 1 do
      if SameText(CallIn(AList[Index], Receiver, Call, Member), APair.Commit) and SameText(Receiver, AReceiver) then
      begin
        Last := Index;
        // Commit(TD) bzw. CommitFreeAndNil(T): dieselben Argumente für Rollback.
        if (Call <> nil) and (Call.ChildCount > 1) then
          Arguments := Copy(NodeText(Call), Length(NodeText(Call[0])) + 1, MaxInt);
        Break;
      end;
    if (Last < 0) or not OwnLine(AList[APosition]) then
      Exit;
    for Index := APosition + 1 to Last do
      if not OwnLine(AList[Index]) then
        Exit;
    Indent := TTextLines.IndentOf(Lines[AList[APosition].StartPos.Line]);
    Step := TRoutineBody.IndentUnit(AContext.Formatting);
    Text := Indent + 'try' + LineBreak;
    for Line := AList[APosition + 1].StartPos.Line to AList[Last].EndPos.Line do
      Text := Text + Step + Lines[Line] + LineBreak;
    Text := Text + Indent + 'except' + LineBreak + Indent + Step + AReceiver + '.' + APair.Rollback + Arguments +
      ';' + LineBreak + Indent + Step + 'raise;' + LineBreak + Indent + 'end;' + LineBreak;
    Result := [TRuleFix.Create(Format('try … except %s.%s; raise; end erzeugen', [AReceiver, APair.Rollback]),
      [TRuleEdit.Create(TTextRange.Create(AList[APosition + 1].StartPos.Line, 0, AList[Last].EndPos.Line + 1, 0),
      Text)])];
  end;

  procedure CheckStatement(AStatement, ARoutine: TSyntaxNode);
  var
    Pair: TTransactionPair;
    Receiver, Name: string;
    Call, Member, List, Other: TSyntaxNode;
    Index, Position: Integer;
    Handled: Boolean;
  begin
    Name := CallIn(AStatement, Receiver, Call, Member);
    if Receiver = '' then
      Exit;
    for Pair in Known do
      if SameText(Name, Pair.Start) then
      begin
        List := AStatement.Parent;
        Position := -1;
        if List <> nil then
          for Index := 0 to List.ChildCount - 1 do
            if List[Index] = AStatement then
              Position := Index;
        // Rollback im except des unmittelbar folgenden try (auch in einem try … finally darum).
        Handled := (Position >= 0) and (Position + 1 < List.ChildCount) and
          (List[Position + 1].Kind = TSyntaxKind.TryStatement) and
          Calls(List[Position + 1], Receiver, Pair.Rollback, True);
        // Commit und Rollback in einer anderen Routine der Unit (Transaktion über mehrere Ereignisse).
        for Other in Routines do
          if Other <> ARoutine then
            for Index := 0 to Other.ChildCount - 1 do
              if Calls(Other[Index], Receiver, Pair.Rollback, False) then
                Handled := True;
        if not Handled then
          AReport.Add(TTextRange.Create(Member.EndPos.Line, Member.EndPos.Character - Length(Member.Name),
            Member.EndPos.Line, Member.EndPos.Character), 'Kein Rollback bei einer Exception; die Transaktion bleibt ' +
            'offen und hält Sperren.', TRuleConfidence.High, RollbackFix(List, Position, Receiver, Pair));
        Exit;
      end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node, Routine: TSyntaxNode;
    Pending, PendingRoutines: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1): zu jedem Knoten auf dem Stapel die umgebende Routine.
    Pending := TStack<TSyntaxNode>.Create;
    PendingRoutines := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      PendingRoutines.Push(nil);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Routine := PendingRoutines.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
          Routine := Node;
        if (Routine <> nil) and (Node.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.AssignStatement,
          TSyntaxKind.InlineVar]) then
          CheckStatement(Node, Routine);
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          PendingRoutines.Push(Routine);
        end;
      end;
    finally
      PendingRoutines.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Known := Pairs(AContext.Options);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Routines := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
        Routines := Routines + [ANode];
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
    end);
  Visit(AContext.Tree.Root);
end;

{ TComparisonAsStatementRule }

function TComparisonAsStatementRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ComparisonAsStatementRuleId, TRuleSeverity.Error,
    'Vergleich statt Zuweisung als Anweisung');
end;

class function TComparisonAsStatementRule.ExpressionOf(AStatement: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (AStatement = nil) or (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount <> 1) then
    Exit;
  Result := AStatement[0];
  // (A = 1); zählt wie A = 1;
  while (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
    Result := Result[0];
  if not (Result.Kind in [TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.Literal,
    TSyntaxKind.SetConstructor]) then
    Result := nil;
end;

procedure TComparisonAsStatementRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  Comparisons: array[0..7] of string = ('=', '<>', '<', '>', '<=', '>=', 'in', 'is');
  // Längere Vorschläge kürzt die Meldung nicht, sie lässt sie weg.
  MaxSuggestion = 60;
var
  Tokens: TTokens;

  function IsComparison(const AOperator: string): Boolean;
  var
    Item: string;
  begin
    for Item in Comparisons do
      if SameText(Item, AOperator) then
        Exit(True);
    Result := False;
  end;

  // Quelltext von ANode, Leerraum und Zeilenumbrüche zu einem Leerzeichen.
  function Compact(ANode: TSyntaxNode): string;
  var
    Raw: string;
    Index: Integer;
    Space: Boolean;
  begin
    Raw := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
    Result := '';
    Space := False;
    for Index := 1 to Length(Raw) do
      if CharInSet(Raw[Index], [' ', #9, #10, #13]) then
        Space := True
      else
      begin
        if Space and (Result <> '') then
          Result := Result + ' ';
        Space := False;
        Result := Result + Raw[Index];
      end;
  end;

  // Linke Seite, der man zuweisen kann (Variable, Feld, Element, Ziel eines Zeigers).
  function Assignable(ANode: TSyntaxNode): Boolean;
  begin
    Result := ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
      TSyntaxKind.Dereference];
  end;

  // Token "=" zwischen linker und rechter Seite; -1 ohne.
  function EqualsToken(AExpression: TSyntaxNode): Integer;
  var
    Index: Integer;
  begin
    for Index := TokenFrom(Tokens, AExpression[0].EndOffset) to High(Tokens) do
    begin
      if Tokens[Index].Offset >= AExpression[1].StartOffset then
        Break;
      if Tokens[Index].IsSymbol('=') then
        Exit(Index);
    end;
    Result := -1;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Node, Expression: TSyntaxNode;
    Index, Equals: Integer;
    Range, OperatorRange: TTextRange;
    Suggestion, Message: string;
    Fixes: TArray<TRuleFix>;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Expression := ExpressionOf(Node);
        if Expression <> nil then
        begin
          Range := TTextRange.Create(Expression.StartPos, Expression.EndPos);
          Fixes := nil;
          if (Expression.Kind = TSyntaxKind.BinaryExpr) and IsComparison(Expression.Name) then
          begin
            Message := 'Vergleich als Anweisung (wie E2014); das Ergebnis wird nicht verwendet.';
            Equals := -1;
            if (Expression.Name = '=') and (Expression.ChildCount = 2) and Assignable(Expression[0]) then
              Equals := EqualsToken(Expression);
            if Equals >= 0 then
            begin
              Suggestion := Compact(Expression[0]) + ' := ' + Compact(Expression[1]);
              if Length(Suggestion) <= MaxSuggestion then
                Message := Format('Vergleich als Anweisung (wie E2014); gemeint ist wohl %s.', [Suggestion])
              else
                Message := 'Vergleich als Anweisung (wie E2014); gemeint ist wohl := statt =.';
              OperatorRange := TTextRange.Create(Tokens[Equals].StartPos, Tokens[Equals].EndPos);
              Fixes := [TRuleFix.Create('= durch := ersetzen', [TRuleEdit.Create(OperatorRange, ':=')], True)];
            end;
          end
          else
            Message := 'Ausdruck als Anweisung (wie E2014); das Ergebnis wird nicht verwendet.';
          AReport.Add(Range, Message, TRuleConfidence.High, Fixes);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Visit(AContext.Tree.Root);
end;

{ TDuplicateCaseLabelRule }

type
  /// <summary>Eine Marke: Token AFirst..ALast, ausgewertet als Bereich Low..High (Known) oder nur über den Text.</summary>
  TCaseLabel = record
    Item: TSyntaxNode;
    First: Integer;
    Last: Integer;
    Known: Boolean;
    Lowest: Int64;
    Highest: Int64;
    IsRange: Boolean;
    Key: string;
    /// <summary>Position unter den Marken des Zweigs und deren Zahl.</summary>
    Position: Integer;
    Count: Integer;
  end;

function TDuplicateCaseLabelRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DuplicateCaseLabelRuleId, TRuleSeverity.Error, 'Doppelte case-Marke');
end;

procedure TDuplicateCaseLabelRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Values: TConstantValues;
  Paths: TArray<string>;

  function LabelText(const ALabel: TCaseLabel): string;
  begin
    Result := SourceText(AContext.Text, Tokens, ALabel.First, ALabel.Last);
  end;

  // Vergleichstext: Bezeichner ohne Groß-/Kleinschreibung, Literale wie geschrieben ('a' <> 'A').
  function LabelKey(AFirst, ALast: Integer): string;
  var
    Index: Integer;
  begin
    Result := '';
    for Index := AFirst to ALast do
      if Tokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
        Result := Result + LowerCase(Tokens[Index].Text) + ' '
      else if not IsTrivia(Tokens[Index]) then
        Result := Result + Tokens[Index].Text + ' ';
  end;

  // Marken eines Zweigs: Token vom Anfang bis zum ":" auf Klammerebene 0, getrennt an ",".
  procedure AddLabels(AItem: TSyntaxNode; var ALabels: TArray<TCaseLabel>);
  var
    First, Stop, Colon, Index, Range, Start: Integer;
    Parts: TArray<TCaseLabel>;
    Item: TCaseLabel;
    LowValue, HighValue: Int64;
  begin
    First := NextCode(Tokens, TokenFrom(Tokens, AItem.StartOffset));
    Stop := TokenFrom(Tokens, AItem.EndOffset);
    Colon := DepthZero(Tokens, First, Stop, ':', False);
    if Colon < 0 then
      Exit;
    Parts := nil;
    Start := First;
    Index := First;
    while Index <= Colon do
    begin
      if (Index = Colon) or Tokens[Index].IsSymbol(',') then
      begin
        Item := Default(TCaseLabel);
        Item.Item := AItem;
        Item.First := NextCode(Tokens, Start);
        Item.Last := PreviousCode(Tokens, Index);
        if Item.Last >= Item.First then
          Parts := Parts + [Item];
        Start := Index + 1;
      end
      else if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol('[') then
      begin
        // Klammern überspringen, damit "," darin nicht trennt.
        Range := Closing(Tokens, Index, Colon);
        if Range < 0 then
          Exit;
        Index := Range;
      end;
      Inc(Index);
    end;
    for Index := 0 to High(Parts) do
    begin
      Item := Parts[Index];
      Item.Position := Index;
      Item.Count := Length(Parts);
      Item.Key := LabelKey(Item.First, Item.Last);
      Range := DepthZero(Tokens, Item.First, Item.Last + 1, '..', False);
      Item.IsRange := Range >= 0;
      if Item.IsRange then
        Item.Known := Values.Evaluate(Item.First, Range - 1, LowValue) and
          Values.Evaluate(Range + 1, Item.Last, HighValue) and (LowValue <= HighValue)
      else
      begin
        Item.Known := Values.Evaluate(Item.First, Item.Last, LowValue);
        HighValue := LowValue;
      end;
      Item.Lowest := LowValue;
      Item.Highest := HighValue;
      ALabels := ALabels + [Item];
    end;
  end;

  function Overlaps(const A, B: TCaseLabel): Boolean;
  begin
    // Nur wenn A immer mit übersetzt wird, sobald B übersetzt wird: {$IFDEF X} 1: … {$ELSE} 1: …
    // {$ENDIF} stößt nie zusammen, 1: … {$IFDEF X} 1: … {$ENDIF} dagegen unter X immer.
    if not TConditionalBranches.Implies(TConditionalBranches.PathAt(Paths, B.First),
      TConditionalBranches.PathAt(Paths, A.First)) then
      Exit(False);
    if A.Known and B.Known then
      Result := (A.Lowest <= B.Highest) and (B.Lowest <= A.Highest)
    else
      Result := not A.Known and not B.Known and (A.Key = B.Key);
  end;

  function Covers(const AOuter, AInner: TCaseLabel): Boolean;
  begin
    if AOuter.Known and AInner.Known then
      Result := (AOuter.Lowest <= AInner.Lowest) and (AInner.Highest <= AOuter.Highest)
    else
      Result := AOuter.Key = AInner.Key;
  end;

  // Löscht die Marke ALabel bzw. den ganzen Zweig, wenn sie seine einzige ist.
  function RemovalFix(const ALabels: TArray<TCaseLabel>; ALabel: Integer): TRuleFix;
  var
    Current: TCaseLabel;
    Neighbour, Before, ItemLast, After: Integer;
    Range: TTextRange;
  begin
    Current := ALabels[ALabel];
    if Current.Count > 1 then
    begin
      if Current.Position < Current.Count - 1 then
      begin
        Neighbour := ALabel + 1;
        Range := TTextRange.Create(Tokens[Current.First].StartPos, Tokens[ALabels[Neighbour].First].StartPos);
      end
      else
      begin
        Neighbour := ALabel - 1;
        Range := TTextRange.Create(Tokens[ALabels[Neighbour].Last].EndPos, Tokens[Current.Last].EndPos);
      end;
      Exit(TRuleFix.Create('Doppelten Wert aus dem späteren Zweig entfernen', [TRuleEdit.Create(Range, '')],
        True));
    end;
    // Ganzer Zweig samt Semikolon, ab dem Ende des Codes davor.
    Before := PreviousCode(Tokens, Current.First);
    ItemLast := PreviousCode(Tokens, TokenFrom(Tokens, Current.Item.EndOffset));
    if (Before < 0) or (ItemLast < Current.First) then
      Exit(Default(TRuleFix));
    After := NextCode(Tokens, ItemLast + 1);
    if (After <= High(Tokens)) and Tokens[After].IsSymbol(';') then
      ItemLast := After;
    Range := TTextRange.Create(Tokens[Before].EndPos, Tokens[ItemLast].EndPos);
    Result := TRuleFix.Create('Zweig mit doppeltem Wert entfernen', [TRuleEdit.Create(Range, '')], False);
  end;

  procedure CheckLabels(AOwner: TSyntaxNode; const ACode: string);
  var
    Labels: TArray<TCaseLabel>;
    Index, Earlier, Line: Integer;
    Text, Other, Message: string;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    Labels := nil;
    for Index := 0 to AOwner.ChildCount - 1 do
      if AOwner[Index].Kind = TSyntaxKind.CaseItem then
        AddLabels(AOwner[Index], Labels);
    for Index := 1 to High(Labels) do
      for Earlier := 0 to Index - 1 do
        if Overlaps(Labels[Earlier], Labels[Index]) then
        begin
          Text := LabelText(Labels[Index]);
          Other := LabelText(Labels[Earlier]);
          Line := Tokens[Labels[Earlier].First].StartPos.Line + 1;
          if Labels[Earlier].Key = Labels[Index].Key then
            Message := Format('%s kommt schon in Zeile %d vor (wie %s).', [Text, Line, ACode])
          else if Covers(Labels[Earlier], Labels[Index]) and Labels[Earlier].IsRange then
            Message := Format('%s liegt schon in %s aus Zeile %d (wie %s).', [Text, Other, Line, ACode])
          else if Covers(Labels[Earlier], Labels[Index]) then
            Message := Format('%s hat denselben Wert wie %s aus Zeile %d (wie %s).', [Text, Other, Line, ACode])
          else
            Message := Format('%s überschneidet sich mit %s aus Zeile %d (wie %s).', [Text, Other, Line, ACode]);
          Fixes := nil;
          if Covers(Labels[Earlier], Labels[Index]) then
          begin
            Fix := RemovalFix(Labels, Index);
            if Fix.Title <> '' then
              Fixes := [Fix];
          end;
          AReport.Add(TTextRange.Create(Tokens[Labels[Index].First].StartPos, Tokens[Labels[Index].Last].EndPos),
            Message, TRuleConfidence.High, Fixes);
          Break;
        end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.CaseStatement then
          CheckLabels(Node, 'E2030')
        else if Node.Kind = TSyntaxKind.VariantPart then
          CheckLabels(Node, 'E2027');
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Resolver: TNameResolver;
  FileName: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Values := TConstantValues.Create(AContext.Tree, FileName, AContext.Index, Resolver);
      try
        Visit(AContext.Tree.Root);
      finally
        Values.Free;
      end;
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

{ TAssignToPropertyMemberRule }

function TAssignToPropertyMemberRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(AssignToPropertyMemberRuleId, TRuleSeverity.Error,
    'Zuweisung an ein Feld eines Property-Records');
end;

procedure TAssignToPropertyMemberRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  // Anweisungen, die in einer Folge stehen: Dort passen drei Zeilen statt einer.
  SequenceParents = [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock,
    TSyntaxKind.RepeatStatement];
var
  Resolver: TNameResolver;
  FileName: string;
  Tokens: TTokens;
  Lines: TArray<string>;
  LineBreak: string;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode.Parent;
    while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
      Result := Result.Parent;
  end;

  /// <summary>Über eine lokale Variable zuweisen und zurückschreiben: R := X.P; R.F := W; X.P := R.</summary>
  function CopyFix(AStatement, AReceiver: TSyntaxNode; const AType: TResolvedSymbol;
    out AFix: TRuleFix): Boolean;
  var
    Routine: TSyntaxNode;
    Name, TypeName, Indent, Receiver, NewText: string;
    UsesEdit: TTextEdit;
    Edits: TArray<TTextEdit>;
  begin
    Result := False;
    Routine := EnclosingRoutine(AStatement);
    if (Routine = nil) or (AStatement.Parent = nil) or not (AStatement.Parent.Kind in SequenceParents) or
      (AStatement.StartPos.Line <> AStatement.EndPos.Line) or (AStatement.StartPos.Line > High(Lines)) then
      Exit;
    TypeName := AType.Name;
    Name := TypeName;
    if (Length(Name) > 1) and CharInSet(Name[1], ['T', 't']) then
      Name := Copy(Name, 2, MaxInt);
    Name := TRoutineBody.UniqueName(Tokens, UpperCase(Copy(Name, 1, 1)));
    Indent := TTextLines.IndentOf(Lines[AStatement.StartPos.Line]);
    Receiver := NodeText(AReceiver);
    NewText := Name + ' := ' + Receiver + ';' + LineBreak + Indent + Name +
      Copy(AContext.Text, AReceiver.EndOffset + 1, AStatement.EndOffset - AReceiver.EndOffset) + ';' + LineBreak +
      Indent + Receiver + ' := ' + Name;
    Edits := [TRoutineBody.AddVariable(AContext.Text, Routine, Name, TypeName, AContext.Formatting),
      TTextEdit.Create(TTextRange.Create(AStatement.StartPos, AStatement.EndPos), NewText)];
    // Der Typ stammt oft aus einer Unit, die die Datei nicht einbindet (TRect aus System.Types).
    if (AType.UnitName <> '') and not SameText(AType.UnitName, 'System') and
      not SameText(AType.UnitName, TUsesClauses.OwnName(Tokens)) and
      not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(Tokens), AType.UnitName, AContext.Namespaces) then
    begin
      if not TUsesClauses.AddUnit(Tokens, AStatement.StartOffset, AType.UnitName, LineBreak, UsesEdit) then
        Exit;
      Edits := Edits + [UsesEdit];
    end;
    AFix := TRuleFix.Create(Format('Über %s zuweisen und zurückschreiben', [Name]), Edits);
    Result := True;
  end;

  /// <summary>Schreibt die Zuweisung an ATarget (ein Feld hinter dem Punkt) in eine Kopie?</summary>
  procedure CheckMember(AStatement, ATarget: TSyntaxNode);
  var
    Target, Receiver: TSyntaxNode;
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound, ReadsField: Boolean;
    Name: string;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    // Iterativ (Bericht M1): statt sich mit dem Empfänger erneut aufzurufen, geht die Schleife zum Empfänger weiter.
    Target := ATarget;
    while True do
    begin
      if (Target.Kind <> TSyntaxKind.MemberAccess) or (Target.ChildCount = 0) then
        Exit;
      Receiver := Target[0];
      if not (Receiver.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
        TSyntaxKind.Call]) then
        Exit;
      if not Resolver.NodeType(AContext.Tree, FileName, Receiver, Symbol, TypeInfo, TypeFound) or not TypeFound or
        (TypeInfo.SymbolKind <> TIndexSymbolKind.RecordType) or Symbol.IsType then
        Exit;
      Name := Symbol.Name;
      if Receiver.Kind = TSyntaxKind.IndexAccess then
        Name := NodeText(Receiver);
      Fixes := nil;
      case Symbol.SymbolKind of
        TIndexSymbolKind.Property_:
          begin
            // Liest die Property ein Feld, schreibt Delphi in das Feld; weiter oben kann es wieder eine Kopie geben.
            if (Symbol.MaxArgs = 0) and (Receiver.Kind <> TSyntaxKind.IndexAccess) then
            begin
              if not Resolver.PropertyReadsField(Symbol, ReadsField) then
                Exit;
              if ReadsField then
              begin
                Target := Receiver;
                Continue;
              end;
            end;
            if ContainsText(' ' + Symbol.Signature.Replace(';', ' ') + ' ', ' write ') and
              CopyFix(AStatement, Receiver, TypeInfo, Fix) then
              Fixes := [Fix];
          end;
        TIndexSymbolKind.Method, TIndexSymbolKind.Routine:
          // Ohne Ergebnistyp ist es kein Wert; das meldet der Compiler anders.
          if Symbol.TypeName = '' then
            Exit;
        TIndexSymbolKind.Field, TIndexSymbolKind.Variable:
          begin
            // Feld eines Records in einem Feld: weiter zum Empfänger.
            if Receiver.Kind <> TSyntaxKind.MemberAccess then
              Exit;
            Target := Receiver;
            Continue;
          end;
      else
        Exit;
      end;
      AReport.Add(TTextRange.Create(Target.StartPos, Target.EndPos), Format('%s liefert eine Kopie; die ' +
        'Zuweisung an %s hat keine Wirkung (wie E2064).', [Name, Target.Name]), TRuleConfidence.High, Fixes);
      Exit;
    end;
  end;

  procedure CheckConstant(ATarget: TSyntaxNode);
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    // Typisierte Konstanten sind mit {$J+} beschreibbar; untypisierte nie.
    if Resolver.NodeType(AContext.Tree, FileName, ATarget, Symbol, TypeInfo, TypeFound) and
      (Symbol.SymbolKind = TIndexSymbolKind.Constant) and (Symbol.TypeName = '') then
      AReport.Add(TTextRange.Create(ATarget.StartPos, ATarget.EndPos), Format('%s ist eine Konstante; ihr lässt ' +
        'sich nichts zuweisen (wie E2064).', [Symbol.Name]), TRuleConfidence.High);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount > 0) then
        begin
          if Node[0].Kind = TSyntaxKind.Identifier then
            CheckConstant(Node[0])
          else
            CheckMember(Node, Node[0]);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Tokens := AContext.Tree.Tokens;
  Lines := TTextLines.SplitLines(AContext.Text);
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Visit(AContext.Tree.Root);
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

{ TUntypedPointerRefcountRule }

function TUntypedPointerRefcountRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('untyped-pointer-refcount', TRuleSeverity.Warning,
    'Untypisierter Zeiger umgeht die Referenzzählung');
end;

procedure TUntypedPointerRefcountRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  FileName: string;
  Tokens: TTokens;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  // Pointer(X) mit genau einem Argument: X; sonst nil.
  function PointerArgument(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := nil;
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
      (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Pointer') then
      Result := ANode[1];
  end;

  // Namenstoken des Felds ASymbol in dieser Datei, wenn es allein deklariert ist (A: IFoo, nicht A, B: IFoo); -1 sonst.
  // AMarked: das Feld trägt schon [weak] oder [unsafe].
  function FieldToken(const ASymbol: TResolvedSymbol; out AMarked: Boolean): Integer;
  var
    Index, Before, After, Open: Integer;
  begin
    Result := -1;
    AMarked := False;
    if (ASymbol.SymbolKind <> TIndexSymbolKind.Field) or not SameText(ASymbol.FileName, FileName) then
      Exit;
    for Index := 0 to High(Tokens) do
      if (Tokens[Index].StartPos.Line = ASymbol.SelectionRange.StartPos.Line) and
        (Tokens[Index].StartPos.Character = ASymbol.SelectionRange.StartPos.Character) then
      begin
        Before := PreviousCode(Tokens, Index);
        After := NextCode(Tokens, Index + 1);
        // Attribute davor: [weak], [unsafe], auch mehrere.
        while (Before >= 0) and Tokens[Before].IsSymbol(']') do
        begin
          Open := Before;
          while (Open >= 0) and not Tokens[Open].IsSymbol('[') do
          begin
            if MatchText(Tokens[Open].Text, ['weak', 'unsafe', 'WeakAttribute', 'UnsafeAttribute']) then
              AMarked := True;
            Dec(Open);
          end;
          Before := PreviousCode(Tokens, Open);
        end;
        if ((Before >= 0) and Tokens[Before].IsSymbol(',')) or (After > High(Tokens)) or
          not Tokens[After].IsSymbol(':') then
          Exit;
        Exit(Index);
      end;
  end;

  procedure CheckAssignment(AStatement: TSyntaxNode);
  var
    Target, Value, Source: TSyntaxNode;
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound, Marked: Boolean;
    Name, NewValue: string;
    Field: Integer;
    Fixes: TArray<TRuleFix>;
  begin
    Target := PointerArgument(AStatement[0]);
    if (Target = nil) or not (Target.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
      Exit;
    if not Resolver.NodeType(AContext.Tree, FileName, Target, Symbol, TypeInfo, TypeFound) or Symbol.IsType then
      Exit;
    // Strings: ebenso falsch, aber dcc warnt nur unter NEXTGEN; [weak]/[unsafe] gibt es für sie nicht.
    if MatchText(Symbol.TypeName, ['string', 'UnicodeString', 'AnsiString', 'RawByteString', 'UTF8String']) then
    begin
      AReport.Add(TTextRange.Create(AStatement[0].StartPos, AStatement[0].EndPos), Format('Die Zuweisung über ' +
        'Pointer umgeht die Referenzzählung des Strings %s (dcc meldet das nicht).', [NodeText(Target)]),
        TRuleConfidence.Medium);
      Exit;
    end;
    if not ((TypeFound and (TypeInfo.SymbolKind = TIndexSymbolKind.InterfaceType)) or
      MatchText(Symbol.TypeName, ['IInterface', 'IUnknown', 'IDispatch'])) then
      Exit;
    Field := FieldToken(Symbol, Marked);
    if Marked then
      Exit;
    Name := NodeText(Target);
    Fixes := nil;
    Value := nil;
    if AStatement.ChildCount > 1 then
      Value := AStatement[1];
    NewValue := '';
    if Value <> nil then
    begin
      Source := PointerArgument(Value);
      if Source <> nil then
        NewValue := NodeText(Source)
      else if SameText(Trim(NodeText(Value)), 'nil') then
        NewValue := 'nil';
    end;
    if (Field >= 0) and (NewValue <> '') then
      Fixes := [TRuleFix.Create(Format('[weak] %s verwenden', [Symbol.Name]),
        [TRuleEdit.Create(TTextRange.Create(Tokens[Field].StartPos, Tokens[Field].StartPos), '[weak] '),
        TRuleEdit.Create(TTextRange.Create(AStatement[0].StartPos, AStatement[0].EndPos), Name),
        TRuleEdit.Create(TTextRange.Create(Value.StartPos, Value.EndPos), NewValue)]),
        TRuleFix.Create(Format('[unsafe] %s verwenden', [Symbol.Name]),
        [TRuleEdit.Create(TTextRange.Create(Tokens[Field].StartPos, Tokens[Field].StartPos), '[unsafe] '),
        TRuleEdit.Create(TTextRange.Create(AStatement[0].StartPos, AStatement[0].EndPos), Name),
        TRuleEdit.Create(TTextRange.Create(Value.StartPos, Value.EndPos), NewValue)])];
    AReport.Add(TTextRange.Create(AStatement[0].StartPos, AStatement[0].EndPos), Format('Die Zuweisung über ' +
      'Pointer umgeht die Referenzzählung (wie W1070); besser [weak] %s.', [Name]), TRuleConfidence.Medium, Fixes);
  end;

var
  Stack: TArray<TSyntaxNode>;
  Count, Index: Integer;
  Node: TSyntaxNode;
  Found: Boolean;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  // Vorfilter: ohne Pointer( keine Namensauflösung.
  Found := False;
  for Index := 0 to High(Tokens) - 1 do
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, 'Pointer') and
      Tokens[Index + 1].IsSymbol('(') then
    begin
      Found := True;
      Break;
    end;
  if not Found then
    Exit;
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      // Ohne Rekursion durch den Baum (#1094).
      SetLength(Stack, 64);
      Stack[0] := AContext.Tree.Root;
      Count := 1;
      while Count > 0 do
      begin
        Dec(Count);
        Node := Stack[Count];
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount > 0) then
          CheckAssignment(Node);
        if Count + Node.ChildCount > Length(Stack) then
          SetLength(Stack, 2 * (Count + Node.ChildCount));
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Stack[Count] := Node[Index];
          Inc(Count);
        end;
      end;
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

{ TReadonlyPropertyAssignedRule }

function TReadonlyPropertyAssignedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ReadonlyPropertyAssignedRuleId, TRuleSeverity.Error,
    'Zuweisung an eine Property ohne write');
end;

class function TReadonlyPropertyAssignedRule.Accessors(const ASignature: string; out AHasRead,
  AHasWrite: Boolean): Boolean;
var
  Text, Word: string;
  Index, Depth: Integer;
begin
  // Indexparameter ausblenden: [read: Integer] wäre kein Zugriff.
  Text := '';
  Depth := 0;
  for Index := 1 to Length(ASignature) do
    if ASignature[Index] = '[' then
      Inc(Depth)
    else if ASignature[Index] = ']' then
      Dec(Depth)
    else if Depth = 0 then
      Text := Text + ASignature[Index];
  AHasRead := False;
  AHasWrite := False;
  for Word in Text.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty) do
    if SameText(Word, 'read') then
      AHasRead := True
    else if SameText(Word, 'write') then
      AHasWrite := True;
  Result := AHasRead or AHasWrite;
end;

procedure TReadonlyPropertyAssignedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  FileName: string;
  Lines: TArray<string>;
  Local: TUnitIndex;
  // Name -> gibt es eine Property ohne write (Bit 1) bzw. ohne read (Bit 2) mit diesem Namen?
  Suspects: TDictionary<string, Integer>;
  Actions: TClassActionContext;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function SuspectFlags(const AName: string): Integer;
  var
    Symbol: TIndexSymbol;
    Location: TSymbolLocation;
    HasRead, HasWrite: Boolean;

    procedure Note(const ASignature: string);
    begin
      if Accessors(ASignature, HasRead, HasWrite) then
      begin
        if not HasWrite then
          Result := Result or 1;
        if not HasRead then
          Result := Result or 2;
      end;
    end;

  begin
    if Suspects.TryGetValue(LowerCase(AName), Result) then
      Exit;
    Result := 0;
    for Symbol in Local.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.Property_) and SameText(Symbol.Name, AName) then
        Note(Symbol.Signature);
    if AContext.Index <> nil then
      for Location in AContext.Index.FindSymbols(AName) do
        if Location.Symbol.Kind = TIndexSymbolKind.Property_ then
          Note(Location.Symbol.Signature);
    Suspects.Add(LowerCase(AName), Result);
  end;

  /// <summary>Wort hinter read in der Signatur ('' ohne); bei read FPunkt.X das ganze FPunkt.X.</summary>
  function ReadAccessor(const ASignature: string): string;
  var
    Words: TArray<string>;
    Index: Integer;
  begin
    Result := '';
    Words := ASignature.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty);
    for Index := 0 to High(Words) - 1 do
      if SameText(Words[Index], 'read') then
        Exit(Words[Index + 1]);
  end;

  /// <summary>Klasse der Methode, in der ANode steht (TKunde bei TKunde.Laden); '' außerhalb.</summary>
  function MethodClass(ANode: TSyntaxNode): string;
  var
    Node: TSyntaxNode;
  begin
    Result := '';
    Node := ANode.Parent;
    while (Node <> nil) and (Node.Kind <> TSyntaxKind.RoutineDecl) do
      Node := Node.Parent;
    if (Node <> nil) and (Pos('.', Node.Name) > 0) then
      Result := Copy(Node.Name, 1, LastDelimiter('.', Node.Name) - 1);
  end;

  function SetterFix(const AProperty: TResolvedSymbol; out AFix: TRuleFix): Boolean;
  var
    Plan: TAccessorPlan;
    Action: TCodeAction;
    Line, Column: Integer;
    Accessor, Text: string;
  begin
    Result := False;
    Line := AProperty.Range.StartPos.Line;
    if not SameText(AProperty.UnitName, Local.UnitName) or (AProperty.MaxArgs > 0) or
      (AProperty.Range.EndPos.Line <> Line) or (Line > High(Lines)) or StartsText('class ', AProperty.Signature) then
      Exit;
    Accessor := ReadAccessor(AProperty.Signature);
    Text := LowerCase(Lines[Line]);
    Column := Pos('read ' + LowerCase(Accessor), Text);
    if (Accessor = '') or (Column = 0) then
      Exit;
    Column := Column - 1 + Length('read ' + Accessor);
    Plan := Default(TAccessorPlan);
    Plan.Kind := TAccessorKind.Setter;
    Plan.PropertyName := AProperty.Name;
    Plan.PropertyType := AProperty.TypeName;
    if AProperty.TypeArgs <> '' then
      Plan.PropertyType := Plan.PropertyType + '<' + AProperty.TypeArgs + '>';
    Plan.MethodSection := 'private';
    if AContext.AccessorsProtected then
      Plan.MethodSection := 'protected';
    if not TClassActions.CreateAccessor(AContext.Text, Line, Plan, Actions, Action) then
      Exit;
    AFix := TRuleFix.Create(Format('%s anlegen und write ergänzen', [Plan.Name]), Action.Edits +
      [TTextEdit.Create(TTextRange.Create(Line, Column, Line, Column), ' write ' + Plan.Name)]);
    Result := True;
  end;

  procedure CheckWrite(AStatement, ATarget: TSyntaxNode);
  var
    Symbol, TypeInfo, Owner, OwnerType, Clear: TResolvedSymbol;
    TypeFound, OwnerFound, HasRead, HasWrite, ReadsField: Boolean;
    Message, Field: string;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    if not (ATarget.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) or
      (SuspectFlags(ATarget.Name) and 1 = 0) and ((ATarget.Kind <> TSyntaxKind.IndexAccess) or
      (ATarget.ChildCount = 0) or (SuspectFlags(ATarget[0].Name) and 1 = 0)) then
      Exit;
    if not Resolver.NodeType(AContext.Tree, FileName, ATarget, Symbol, TypeInfo, TypeFound) or
      (Symbol.SymbolKind <> TIndexSymbolKind.Property_) or not Accessors(Symbol.Signature, HasRead, HasWrite) or
      HasWrite then
      Exit;
    Message := Format('%s.%s hat kein write (wie E2129).', [Symbol.Container, Symbol.Name]);
    Fixes := nil;
    // Count := 0 auf einer Liste: Clear leert sie.
    if SameText(Symbol.Name, 'Count') and (AStatement.ChildCount > 1) and (NodeText(AStatement[1]) = '0') and
      (ATarget.Kind = TSyntaxKind.MemberAccess) and (ATarget.ChildCount > 0) then
    begin
      OwnerFound := Resolver.NodeType(AContext.Tree, FileName, ATarget[0], Owner, OwnerType, TypeFound) and
        TypeFound and Resolver.FindMember(OwnerType, 'Clear', Clear) and
        (Clear.SymbolKind = TIndexSymbolKind.Method);
      if OwnerFound then
      begin
        Message := Format('%s.%s hat kein write (wie E2129); zum Leeren Clear aufrufen.', [Symbol.Container,
          Symbol.Name]);
        Fixes := [TRuleFix.Create('Clear aufrufen', [TTextEdit.Create(TTextRange.Create(AStatement.StartPos,
          AStatement.EndPos), NodeText(ATarget[0]) + '.Clear')])];
      end;
    end;
    // In einer Methode der Klasse selbst: direkt in das Feld hinter read schreiben.
    if (Fixes = nil) and SameText(MethodClass(AStatement), Symbol.Container) and
      ((ATarget.Kind = TSyntaxKind.Identifier) or ((ATarget.Kind = TSyntaxKind.MemberAccess) and
      (ATarget.ChildCount > 0) and SameText(NodeText(ATarget[0]), 'Self'))) and
      Resolver.PropertyReadsField(Symbol, ReadsField) and ReadsField then
    begin
      Field := ReadAccessor(Symbol.Signature);
      Fixes := [TRuleFix.Create(Format('Feld %s zuweisen', [Field]), [TTextEdit.Create(TTextRange.Create(
        ATarget.StartPos, ATarget.EndPos), Field)])];
    end;
    if SetterFix(Symbol, Fix) then
      Fixes := Fixes + [Fix];
    if Length(Fixes) > 1 then
      Fixes[1].Alternative := True;
    AReport.Add(TTextRange.Create(ATarget.StartPos, ATarget.EndPos), Message, TRuleConfidence.High, Fixes);
  end;

  procedure CheckRead(ANode: TSyntaxNode);
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound, HasRead, HasWrite: Boolean;
  begin
    if SuspectFlags(ANode.Name) and 2 = 0 then
      Exit;
    if Resolver.NodeType(AContext.Tree, FileName, ANode, Symbol, TypeInfo, TypeFound) and
      (Symbol.SymbolKind = TIndexSymbolKind.Property_) and Accessors(Symbol.Signature, HasRead, HasWrite) and
      not HasRead then
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('%s.%s hat kein read (wie E2130).',
        [Symbol.Container, Symbol.Name]), TRuleConfidence.High);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node, Target: TSyntaxNode;
    Written: Boolean;
    Pending: TStack<TSyntaxNode>;
    PendingWritten: TStack<Boolean>;
  begin
    // Iterativ (Bericht M1): zu jedem Knoten auf dem Stapel, ob er geschrieben wird.
    Pending := TStack<TSyntaxNode>.Create;
    PendingWritten := TStack<Boolean>.Create;
    try
      Pending.Push(ARoot);
      PendingWritten.Push(False);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Written := PendingWritten.Pop;
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount > 0) then
        begin
          Target := Node[0];
          CheckWrite(Node, Target);
          // Erst die Kinder des Ziels, dann die übrigen Kinder der Zuweisung (umgekehrt auf den Stapel).
          for Index := Node.ChildCount - 1 downto 1 do
          begin
            Pending.Push(Node[Index]);
            PendingWritten.Push(False);
          end;
          // Das Ziel selbst wird geschrieben, bei Liste.Items[I] auch die Property davor.
          for Index := Target.ChildCount - 1 downto 0 do
          begin
            Pending.Push(Target[Index]);
            PendingWritten.Push((Target.Kind = TSyntaxKind.IndexAccess) and (Index = 0));
          end;
          Continue;
        end;
        if not Written and (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
          CheckRead(Node);
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          PendingWritten.Push(False);
        end;
      end;
    finally
      PendingWritten.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Lines := TTextLines.SplitLines(AContext.Text);
  Actions := TClassActionContext.Default;
  Actions.Index := AContext.Index;
  Actions.Namespaces := AContext.Namespaces;
  Actions.DelphiVersion := AContext.DelphiVersion;
  Actions.Style := AContext.Formatting;
  Suspects := TDictionary<string, Integer>.Create;
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Local := Resolver.ExtractedUnit(AContext.Tree, FileName);
      Visit(AContext.Tree.Root);
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Suspects.Free;
  end;
end;

procedure RegisterStatementRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TEmptyStatementRule.Create);
  ARegistry.Register(TDestroyCalledDirectlyRule.Create);
  ARegistry.Register(TLoopOffByOneRule.Create);
  ARegistry.Register(TCollectionModifiedInLoopRule.Create);
  ARegistry.Register(TCaseMissingEnumValueRule.Create);
  ARegistry.Register(TDatasetLoopWithoutNextRule.Create);
  ARegistry.Register(TDatasetEditWithoutPostRule.Create);
  ARegistry.Register(TTransactionWithoutRollbackRule.Create);
  ARegistry.Register(TComparisonAsStatementRule.Create);
  ARegistry.Register(TDuplicateCaseLabelRule.Create);
  ARegistry.Register(TAssignToPropertyMemberRule.Create);
  ARegistry.Register(TUntypedPointerRefcountRule.Create);
  ARegistry.Register(TReadonlyPropertyAssignedRule.Create);
end;

end.
