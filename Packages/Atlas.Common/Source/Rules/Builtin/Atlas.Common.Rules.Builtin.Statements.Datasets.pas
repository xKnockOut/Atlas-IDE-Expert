unit Atlas.Common.Rules.Builtin.Statements.Datasets;

// Datenmengen und Transaktionen, die offen bleiben (#909):
//   dataset-loop-without-next
//                     while not Q.Eof do ohne Q.Next auf jedem Weg durch den
//                     Rumpf, der die Schleife fortsetzt (#963); Delete, MoveBy,
//                     Last, Close und FindNext zählen mit. Wird Q im Rumpf
//                     weitergegeben, bleibt die Regel still.
//   dataset-edit-without-post
//                     Q.Edit, Q.Append bzw. Q.Insert ohne folgendes Post, Cancel
//                     oder CheckBrowseMode in der Routine (#964); still, wenn
//                     eine andere Routine der Unit Q postet oder Q weitergegeben wird,
//                     und wenn Q sicher nicht von TDataSet abstammt (#1326: Insert
//                     und Edit eines ActiveRecord, eines Records oder einer Liste).
//   transaction-without-rollback
//                     StartTransaction (BeginTransaction, BeginTrans) ohne Rollback
//                     im except des unmittelbar folgenden try (#965); Paare aus der
//                     Option pairs (start, commit, rollback) ersetzen die eingebauten.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract;

type
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

implementation

uses
  Atlas.Common.Rules.Derived,
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
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.AccessorCreation,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.Statements.Tokens,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TStatementsDatasetsText = (NextTitle, InsertNext, NextMissing, NextNotAlways, PostTitle, AddPost, PostMissing,
    RollbackTitle, CreateTry, Rollback);

const
  cTexts: array[TStatementsDatasetsText] of TAtlasText = (
    (De: 'Datenmengen-Schleife ohne Next'; En: 'Dataset loop without Next'),
    (De: '%s.Next; am Ende des Rumpfs einfügen'; En: 'Insert %s.Next; at the end of the body'),
    (De: 'Im Rumpf fehlt %s.Next; die Schleife läuft endlos.'; En: 'The body lacks %s.Next; the loop runs endlessly.'),
    (De: 'Nicht jeder Weg durch den Rumpf ruft %s.Next auf; dort läuft die Schleife endlos.';
     En: 'Not every path through the body calls %s.Next; there the loop runs endlessly.'),
    (De: 'Edit oder Append ohne Post'; En: 'Edit or Append without Post'),
    (De: '%s.Post mit try … except Cancel ergänzen'; En: 'Add %s.Post with try … except Cancel'),
    (De: 'Nach %s fehlt Post oder Cancel; die Änderung bleibt offen.';
     En: 'After %s, Post or Cancel is missing; the change stays open.'),
    (De: 'Transaktion ohne Rollback'; En: 'Transaction without rollback'),
    (De: 'try … except %s.%s; raise; end erzeugen'; En: 'Create try … except %s.%s; raise; end'),
    (De: 'Kein Rollback bei einer Exception; die Transaktion bleibt offen und hält Sperren.';
     En: 'No rollback on an exception; the transaction stays open and holds locks.'));

{$SCOPEDENUMS OFF}

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
  begin
    Exit;
  end;
  Target := ANode[0];
  if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount > 0) then
  begin
    AArguments := Target.ChildCount - 1;
    Target := Target[0];
  end;
  if Target.Kind = TSyntaxKind.MemberAccess then
  begin
    if Target.ChildCount > 0 then
    begin
      AReceiver := Copy(AText, Target[0].StartOffset + 1, Target[0].EndOffset - Target[0].StartOffset);
    end;
    Result := Target.Name;
  end
  else if Target.Kind = TSyntaxKind.Identifier then
  begin
    Result := Target.Name;
  end;
end;

{ TDatasetLoopWithoutNextRule }

const
  // Methoden, die den Datensatzzeiger weiterbewegen oder die Schleife über Eof beenden.
  DatasetAdvancing: array[0..6] of string = ('Next', 'Delete', 'MoveBy', 'Last', 'Close', 'FindNext', 'Free');

function TDatasetLoopWithoutNextRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dataset-loop-without-next', TRuleSeverity.Error,
    cTexts[TStatementsDatasetsText.NextTitle].Text);
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
        begin
          Continue;
        end;
        if SameText(StatementName(Node, Receiver), 'Continue') and (Receiver = '') then
        begin
          Exit(True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Kinder AFrom..ATo von ANode, ohne except-Teile.
  function ChildRange(ANode: TSyntaxNode; AFrom, ATo: Integer): TArray<TSyntaxNode>;
  var
    mIndex: Integer;
  begin
    Result := nil;
    for mIndex := AFrom to ATo do
    begin
      if ANode[mIndex].Kind <> TSyntaxKind.ExceptBlock then
      begin
        Result := Result + [ANode[mIndex]];
      end;
    end;
  end;

  // Zweige einer case-Anweisung: Anweisung jedes Zweigs und else.
  function CaseParts(ANode: TSyntaxNode): TArray<TSyntaxNode>;
  var
    mIndex: Integer;
  begin
    Result := nil;
    for mIndex := 1 to ANode.ChildCount - 1 do
    begin
      if ANode[mIndex].Kind = TSyntaxKind.CaseItem then
      begin
        Result := Result + [ANode[mIndex][ANode[mIndex].ChildCount - 1]];
      end
      else if ANode[mIndex].Kind = TSyntaxKind.CaseElse then
      begin
        Result := Result + [ANode[mIndex]];
      end;
    end;
  end;

  // Teile von ANode, von deren Advances das Ergebnis für ANode abhängt (in Quelltextreihenfolge).
  function AdvanceParts(ANode: TSyntaxNode): TArray<TSyntaxNode>;
  begin
    Result := nil;
    case ANode.Kind of
      TSyntaxKind.Block, TSyntaxKind.FinallyBlock, TSyntaxKind.CaseElse, TSyntaxKind.TryStatement:
        Result := ChildRange(ANode, 0, ANode.ChildCount - 1);
      TSyntaxKind.IfStatement:
        if ANode.ChildCount = 3 then
        begin
          Result := [ANode[1], ANode[2]];
        end;
      TSyntaxKind.CaseStatement:
        Result := CaseParts(ANode);
      TSyntaxKind.WithStatement:
        Result := [ANode[ANode.ChildCount - 1]];
      // repeat läuft mindestens einmal; while und for vielleicht nie.
      TSyntaxKind.RepeatStatement:
        Result := ChildRange(ANode, 0, ANode.ChildCount - 2);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  // Bewegt die Anweisung ANode weiter oder verlässt sie die Schleife?
  function CallAdvances(ANode: TSyntaxNode): Boolean;
  var
    mReceiver, mName: string;
  begin
    mName := StatementName(ANode, mReceiver);
    // Break, Exit und Halt verlassen die Schleife; Continue setzt sie ohne Weiterbewegen fort.
    Result := IsAdvance(ANode) or ((mReceiver = '') and MatchText(mName, ['Break', 'Exit', 'Halt', 'Abort']));
  end;

  // Bewegt ein Teil eines Blocks weiter, bevor ein Continue die Schleife auf demselben Datensatz fortsetzt?
  function BlockAdvances(const AParts: TArray<TSyntaxNode>; AValues: TDictionary<TSyntaxNode, Boolean>): Boolean;
  var
    mIndex: Integer;
  begin
    Result := False;
    mIndex := 0;
    while (mIndex <= High(AParts)) and not Result do
    begin
      Result := AValues[AParts[mIndex]];
      if not Result and HasContinue(AParts[mIndex]) then
      begin
        Break;
      end;
      Inc(mIndex);
    end;
  end;

  function AnyAdvances(const AParts: TArray<TSyntaxNode>; AValues: TDictionary<TSyntaxNode, Boolean>): Boolean;
  var
    mPart: TSyntaxNode;
  begin
    Result := False;
    for mPart in AParts do
    begin
      Result := Result or AValues[mPart];
    end;
  end;

  function AllAdvance(const AParts: TArray<TSyntaxNode>; AValues: TDictionary<TSyntaxNode, Boolean>): Boolean;
  var
    mPart: TSyntaxNode;
  begin
    Result := True;
    for mPart in AParts do
    begin
      Result := Result and AValues[mPart];
    end;
  end;

  // Ergebnis für ANode aus den Ergebnissen seiner Teile AParts.
  function NodeAdvances(ANode: TSyntaxNode; const AParts: TArray<TSyntaxNode>;
    AValues: TDictionary<TSyntaxNode, Boolean>): Boolean;
  begin
    Result := False;
    case ANode.Kind of
      TSyntaxKind.CallStatement:
        Result := CallAdvances(ANode);
      TSyntaxKind.RaiseStatement:
        Result := True;
      TSyntaxKind.Block, TSyntaxKind.FinallyBlock, TSyntaxKind.CaseElse:
        Result := BlockAdvances(AParts, AValues);
      TSyntaxKind.IfStatement:
        Result := (Length(AParts) = 2) and AllAdvance(AParts, AValues);
      TSyntaxKind.CaseStatement:
        Result := (ANode.FindChild(TSyntaxKind.CaseElse) <> nil) and AllAdvance(AParts, AValues);
      TSyntaxKind.TryStatement, TSyntaxKind.WithStatement, TSyntaxKind.RepeatStatement:
        Result := AnyAdvances(AParts, AValues);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  // Endet jeder Weg durch ANode, der die Schleife fortsetzt, mit einem Weiterbewegen?
  function Advances(ANode: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
    mParts: TArray<TSyntaxNode>;
    mEntry: TSyntaxPostOrderEntry;
    mPending: TStack<TSyntaxPostOrderEntry>;
    mValues: TDictionary<TSyntaxNode, Boolean>;
  begin
    // Iterativ (Bericht M1): Nachordnung, die Teile zuerst; lange else-if-Ketten ergeben sehr tiefe Bäume.
    Result := False;
    if ANode = nil then
    begin
      Exit;
    end;
    mPending := TStack<TSyntaxPostOrderEntry>.Create;
    mValues := TDictionary<TSyntaxNode, Boolean>.Create;
    try
      mPending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
      while mPending.Count > 0 do
      begin
        mEntry := mPending.Pop;
        mParts := AdvanceParts(mEntry.Node);
        if mEntry.Done then
        begin
          mValues.AddOrSetValue(mEntry.Node, NodeAdvances(mEntry.Node, mParts, mValues));
          Continue;
        end;
        mPending.Push(TSyntaxPostOrderEntry.Create(mEntry.Node, True));
        for mIndex := High(mParts) downto 0 do
        begin
          mPending.Push(TSyntaxPostOrderEntry.Create(mParts[mIndex], False));
        end;
      end;
      Result := mValues[ANode];
    finally
      mValues.Free;
      mPending.Free;
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
        begin
          Continue;
        end;
        if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
          SameText(NodeText(Node), DataSet) and
          not ((Parent <> nil) and (Parent.Kind = TSyntaxKind.MemberAccess) and (Parent[0] = Node)) then
        begin
          Exit(True);
        end;
        if Node.Kind = TSyntaxKind.WithStatement then
        begin
          Exit(True);
        end;
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
        begin
          Exit(True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
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
    begin
      Exit;
    end;
    EndLine := ABody.EndPos.Line;
    if (EndLine <= ABody.StartPos.Line) or (Trim(Copy(Lines[EndLine], 1, ABody.EndPos.Character - Length('end'))) <> '') then
    begin
      Exit;
    end;
    Result := [TRuleFix.Create(cTexts[TStatementsDatasetsText.InsertNext].Fmt([DataSet]), [TRuleEdit.Create(
      TTextRange.Create(EndLine, 0, EndLine, 0), TTextLines.IndentOf(Lines[EndLine]) +
      TRoutineBody.IndentUnit(AContext.Formatting) + DataSet + '.Next;' + LineBreak)])];
  end;

  // not Q.Eof
  function IsNotEof(ACondition: TSyntaxNode): Boolean;
  begin
    Result := (ACondition.Kind = TSyntaxKind.UnaryExpr) and SameText(ACondition.Name, 'not') and
      (ACondition.ChildCount = 1);
    Result := Result and (ACondition[0].Kind = TSyntaxKind.MemberAccess) and SameText(ACondition[0].Name, 'Eof') and
      (ACondition[0].ChildCount = 1);
  end;

  procedure InspectLoop(ACondition, ABody: TSyntaxNode);
  begin
    DataSet := NodeText(ACondition[0][0]);
    if Escapes(ABody) or Advances(ABody) then
    begin
      Exit;
    end;
    if not MentionsAdvance(ABody) then
    begin
      AReport.Add(TTextRange.Create(ACondition.StartPos, ACondition.EndPos),
        cTexts[TStatementsDatasetsText.NextMissing].Fmt([DataSet]), TRuleConfidence.High,
        NextFix(ABody));
    end
    else
    begin
      AReport.Add(TTextRange.Create(ACondition.StartPos, ACondition.EndPos),
        cTexts[TStatementsDatasetsText.NextNotAlways].Fmt([DataSet]), TRuleConfidence.Medium);
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
        // while not Q.Eof do …
        if (Node.Kind = TSyntaxKind.WhileStatement) and (Node.ChildCount = 2) and IsNotEof(Node[0]) then
        begin
          InspectLoop(Node[0], Node[1]);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Eof') then
  begin
    Exit;
  end;
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
  Result := TRuleDescriptor.Create('dataset-edit-without-post', TRuleSeverity.Warning,
    cTexts[TStatementsDatasetsText.PostTitle].Text);
end;

procedure TDatasetEditWithoutPostRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<string>;
  LineBreak: string;
  Routines: TArray<TSyntaxNode>;
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;

  /// <summary>Kann der Empfänger des Aufrufs AStatement eine Datenmenge sein (#1326)? Nein, wenn sein Typ bekannt
  /// ist und die Vorfahrenkette ohne TDataSet vollständig endet oder er keine Klasse ist; bei unbekanntem Typ
  /// oder abgebrochener Kette ja, wie bisher.</summary>
  function MayBeDataSet(AStatement: TSyntaxNode): Boolean;
  var
    mTarget: TSyntaxNode;
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound, mComplete: Boolean;
    mNames: TArray<string>;
  begin
    Result := True;
    mTarget := AStatement[0];
    if (mTarget.Kind = TSyntaxKind.Call) and (mTarget.ChildCount > 0) then
    begin
      mTarget := mTarget[0];
    end;
    if (mTarget.Kind <> TSyntaxKind.MemberAccess) or (mTarget.ChildCount = 0) then
    begin
      Exit;
    end;
    if mResolver = nil then
    begin
      // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
      mCache := TRuleDerived.Open(AContext);
      mResolver := TRuleDerived.Resolver(mCache, AContext);
      mResolver.PinTree(AContext.Tree, mFileName);
    end;
    if not mResolver.NodeType(AContext.Tree, mFileName, mTarget[0], mSymbol, mTypeInfo, mTypeFound) or
      not mTypeFound then
    begin
      Exit;
    end;
    if mTypeInfo.Builtin or (mTypeInfo.SymbolKind in [TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType,
      TIndexSymbolKind.EnumType]) then
    begin
      Exit(False);
    end;
    if mTypeInfo.SymbolKind <> TIndexSymbolKind.ClassType then
    begin
      Exit;
    end;
    mNames := mResolver.Queries.AncestorNames(mTypeInfo, mComplete);
    Result := (IndexText('TDataSet', mNames) >= 0) or not mComplete;
  end;

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
          begin
            Exit(True);
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          if Node[Index].EndOffset > AFrom then
          begin
            Pending.Push(Node[Index]);
          end;
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Steht ANode als Empfänger links in seinem Elternknoten (Q.X, Q['X'])?
  function IsReceiver(ANode, AParent: TSyntaxNode): Boolean;
  begin
    Result := (AParent <> nil) and (AParent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) and
      (AParent[0] = ANode);
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
          Result := not IsReceiver(Node, Parent);
          if Result then
          begin
            Exit;
          end;
          Continue;
        end;
        if (Node.StartOffset >= AFrom) and (Node.Kind = TSyntaxKind.WithStatement) then
        begin
          Exit(True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          if Node[Index].EndOffset > AFrom then
          begin
            Pending.Push(Node[Index]);
            Parents.Push(Node);
          end;
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
        begin
          Exit(True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
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
    begin
      Exit;
    end;
    Position := -1;
    for Index := 0 to List.ChildCount - 1 do
    begin
      if List[Index] = AStatement then
      begin
        Position := Index;
      end;
    end;
    Last := Position;
    while (Last + 1 < List.ChildCount) and (List[Last + 1].Kind in [TSyntaxKind.AssignStatement,
      TSyntaxKind.CallStatement]) and UsesDataSet(List[Last + 1], ADataSet) and OwnLine(List[Last + 1]) do
    begin
      Inc(Last);
    end;
    if (Position < 0) or (Last = Position) then
    begin
      Exit;
    end;
    Indent := TTextLines.IndentOf(Lines[AStatement.StartPos.Line]);
    Step := TRoutineBody.IndentUnit(AContext.Formatting);
    Text := Indent + 'try' + LineBreak;
    for Line := List[Position + 1].StartPos.Line to List[Last].EndPos.Line do
    begin
      Text := Text + Step + Lines[Line] + LineBreak;
    end;
    Text := Text + Indent + Step + ADataSet + '.Post;' + LineBreak + Indent + 'except' + LineBreak + Indent + Step +
      ADataSet + '.Cancel;' + LineBreak + Indent + Step + 'raise;' + LineBreak + Indent + 'end;' + LineBreak;
    Result := [TRuleFix.Create(cTexts[TStatementsDatasetsText.AddPost].Fmt([ADataSet]), [TRuleEdit.Create(
      TTextRange.Create(List[Position + 1].StartPos.Line, 0, List[Last].EndPos.Line + 1, 0), Text)])];
  end;

  // Beendet eine andere Routine der Unit den Bearbeitungsmodus (Bearbeiten-/Speichern-Knopf)?
  function EndedElsewhere(ARoutine: TSyntaxNode; const ADataSet: string): Boolean;
  var
    Other: TSyntaxNode;
  begin
    for Other in Routines do
    begin
      if (Other <> ARoutine) and Ends(Other, ADataSet, 0) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Q.Edit, Q.Append bzw. Q.Insert ohne Argumente, das in ARoutine offen bleibt?
  function IsOpenEdit(ANode, ARoutine: TSyntaxNode; out AName, AReceiver: string): Boolean;
  var
    mArguments: Integer;
  begin
    AName := StatementCall(AContext.Text, ANode, AReceiver, mArguments);
    Result := (AReceiver <> '') and (mArguments = 0) and MatchText(AName, DatasetEditMethods);
    Result := Result and not Ends(ARoutine, AReceiver, ANode.EndOffset) and
      not Escapes(ARoutine, AReceiver, ANode.EndOffset);
    Result := Result and not EndedElsewhere(ARoutine, AReceiver) and MayBeDataSet(ANode);
  end;

  procedure CheckCall(ANode, ARoutine: TSyntaxNode);
  var
    mName, mReceiver: string;
  begin
    if IsOpenEdit(ANode, ARoutine, mName, mReceiver) then
    begin
      AReport.Add(TTextRange.Create(ANode[0].EndPos.Line, ANode[0].EndPos.Character - Length(mName),
        ANode[0].EndPos.Line, ANode[0].EndPos.Character), cTexts[TStatementsDatasetsText.PostMissing].Fmt([mName]),
          TRuleConfidence.Medium, PostFix(ANode, mReceiver));
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
        begin
          Routine := Node;
        end;
        if (Routine <> nil) and (Node.Kind = TSyntaxKind.CallStatement) then
        begin
          CheckCall(Node, Routine);
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
  begin
    Exit;
  end;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Routines := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
      begin
        Routines := Routines + [ANode];
      end;
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
    end);
  mFileName := ContextFileName(AContext);
  mResolver := nil;
  try
    Visit(AContext.Tree.Root);
  finally
    if mResolver <> nil then
    begin
      mResolver.UnpinTree;
    end;
  end;
end;

{ TTransactionWithoutRollbackRule }

const
  // FireDAC, IBX und dbExpress (StartTransaction), dbExpress ab XE (BeginTransaction), ADO (BeginTrans).
  BuiltinTransactionPairs: array[0..2, 0..2] of string = (('StartTransaction', 'Commit', 'Rollback'),
    ('BeginTransaction', 'CommitFreeAndNil', 'RollbackFreeAndNil'), ('BeginTrans', 'CommitTrans', 'RollbackTrans'));

function TTransactionWithoutRollbackRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('transaction-without-rollback', TRuleSeverity.Warning,
    cTexts[TStatementsDatasetsText.RollbackTitle].Text);
end;

/// <summary>Paar aus einem Eintrag von "pairs"; False ohne start oder rollback.</summary>
function PairFromJson(AItem: TJSONValue; out APair: TTransactionPair): Boolean;
var
  mObject: TJSONObject;
begin
  APair := Default(TTransactionPair);
  if not (AItem is TJSONObject) then
  begin
    Exit(False);
  end;
  mObject := TJSONObject(AItem);
  Result := mObject.TryGetValue<string>('start', APair.Start) and mObject.TryGetValue<string>('commit', APair.Commit);
  Result := Result and mObject.TryGetValue<string>('rollback', APair.Rollback);
  Result := Result and (Trim(APair.Start) <> '') and (Trim(APair.Rollback) <> '');
  APair.Start := Trim(APair.Start);
  APair.Commit := Trim(APair.Commit);
  APair.Rollback := Trim(APair.Rollback);
end;

/// <summary>Eigene Paare aus der Option "pairs"; False ohne Liste.</summary>
function PairsFromOptions(const AOptions: string; out APairs: TArray<TTransactionPair>): Boolean;
var
  mValue, mList, mItem: TJSONValue;
  mPair: TTransactionPair;
begin
  Result := False;
  APairs := nil;
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AOptions);
  try
    mList := nil;
    if mValue is TJSONObject then
    begin
      mList := TJSONObject(mValue).GetValue('pairs');
    end;
    Result := mList is TJSONArray;
    if not Result then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mList) do
    begin
      if PairFromJson(mItem, mPair) then
      begin
        APairs := APairs + [mPair];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TTransactionWithoutRollbackRule.Pairs(const AOptions: string): TArray<TTransactionPair>;
var
  Index: Integer;
  Pair: TTransactionPair;
begin
  // Eine eigene Liste ersetzt die eingebauten Paare.
  if PairsFromOptions(AOptions, Result) then
  begin
    Exit;
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
    begin
      Target := ANode[0];
    end
    else if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) then
    begin
      Target := ANode[1];
    end
    else if (ANode.Kind = TSyntaxKind.InlineVar) and (ANode.ChildCount > 0) then
    begin
      Target := ANode[ANode.ChildCount - 1];
    end
    else
    begin
      Exit;
    end;
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
        begin
          Continue;
        end;
        if Node.Kind = TSyntaxKind.ExceptBlock then
        begin
          Inside := True;
        end;
        if (Inside or not AInExcept) and SameText(CallIn(Node, Receiver, Call, Member), AMethod) and
          SameText(Receiver, AReceiver) then
        begin
          Exit(True);
        end;
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
    begin
      if SameText(CallIn(AList[Index], Receiver, Call, Member), APair.Commit) and SameText(Receiver, AReceiver) then
      begin
        Last := Index;
        // Commit(TD) bzw. CommitFreeAndNil(T): dieselben Argumente für Rollback.
        if (Call <> nil) and (Call.ChildCount > 1) then
        begin
          Arguments := Copy(NodeText(Call), Length(NodeText(Call[0])) + 1, MaxInt);
        end;
        Break;
      end;
    end;
    if (Last < 0) or not OwnLine(AList[APosition]) then
    begin
      Exit;
    end;
    for Index := APosition + 1 to Last do
    begin
      if not OwnLine(AList[Index]) then
      begin
        Exit;
      end;
    end;
    Indent := TTextLines.IndentOf(Lines[AList[APosition].StartPos.Line]);
    Step := TRoutineBody.IndentUnit(AContext.Formatting);
    Text := Indent + 'try' + LineBreak;
    for Line := AList[APosition + 1].StartPos.Line to AList[Last].EndPos.Line do
    begin
      Text := Text + Step + Lines[Line] + LineBreak;
    end;
    Text := Text + Indent + 'except' + LineBreak + Indent + Step + AReceiver + '.' + APair.Rollback + Arguments +
      ';' + LineBreak + Indent + Step + 'raise;' + LineBreak + Indent + 'end;' + LineBreak;
    Result := [TRuleFix.Create(cTexts[TStatementsDatasetsText.CreateTry].Fmt([AReceiver, APair.Rollback]),
      [TRuleEdit.Create(TTextRange.Create(AList[APosition + 1].StartPos.Line, 0, AList[Last].EndPos.Line + 1, 0),
      Text)])];
  end;

  // Stelle von AStatement in der Anweisungsliste darüber; -1 ohne.
  function PositionInList(AStatement: TSyntaxNode): Integer;
  var
    mIndex: Integer;
  begin
    Result := -1;
    if AStatement.Parent = nil then
    begin
      Exit;
    end;
    for mIndex := 0 to AStatement.Parent.ChildCount - 1 do
    begin
      if AStatement.Parent[mIndex] = AStatement then
      begin
        Result := mIndex;
      end;
    end;
  end;

  // Commit und Rollback in einer anderen Routine der Unit (Transaktion über mehrere Ereignisse).
  function RolledBackElsewhere(ARoutine: TSyntaxNode; const AReceiver, ARollback: string): Boolean;
  var
    mOther: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := False;
    for mOther in Routines do
    begin
      if mOther = ARoutine then
      begin
        Continue;
      end;
      for mIndex := 0 to mOther.ChildCount - 1 do
      begin
        Result := Result or Calls(mOther[mIndex], AReceiver, ARollback, False);
      end;
    end;
  end;

  // Rollback im except des unmittelbar folgenden try (auch in einem try … finally darum).
  function RolledBackAfter(AList: TSyntaxNode; APosition: Integer; const AReceiver, ARollback: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition + 1 < AList.ChildCount);
    Result := Result and (AList[APosition + 1].Kind = TSyntaxKind.TryStatement) and
      Calls(AList[APosition + 1], AReceiver, ARollback, True);
  end;

  procedure CheckStart(AStatement, ARoutine, AMember: TSyntaxNode; const AReceiver: string;
    const APair: TTransactionPair);
  var
    mList: TSyntaxNode;
    mPosition: Integer;
  begin
    mList := AStatement.Parent;
    mPosition := PositionInList(AStatement);
    if RolledBackAfter(mList, mPosition, AReceiver, APair.Rollback) or
      RolledBackElsewhere(ARoutine, AReceiver, APair.Rollback) then
    begin
      Exit;
    end;
    AReport.Add(TTextRange.Create(AMember.EndPos.Line, AMember.EndPos.Character - Length(AMember.Name),
      AMember.EndPos.Line, AMember.EndPos.Character), cTexts[TStatementsDatasetsText.Rollback].Text,
        TRuleConfidence.High, RollbackFix(mList, mPosition, AReceiver, APair));
  end;

  procedure CheckStatement(AStatement, ARoutine: TSyntaxNode);
  var
    mPair: TTransactionPair;
    mReceiver, mName: string;
    mCall, mMember: TSyntaxNode;
  begin
    mName := CallIn(AStatement, mReceiver, mCall, mMember);
    if mReceiver = '' then
    begin
      Exit;
    end;
    for mPair in Known do
    begin
      if SameText(mName, mPair.Start) then
      begin
        CheckStart(AStatement, ARoutine, mMember, mReceiver, mPair);
        Exit;
      end;
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
        begin
          Routine := Node;
        end;
        if (Routine <> nil) and (Node.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.AssignStatement,
          TSyntaxKind.InlineVar]) then
        begin
          CheckStatement(Node, Routine);
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
  begin
    Exit;
  end;
  Known := Pairs(AContext.Options);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Routines := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
      begin
        Routines := Routines + [ANode];
      end;
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
    end);
  Visit(AContext.Tree.Root);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Statements.Datasets', cTexts);

end.
