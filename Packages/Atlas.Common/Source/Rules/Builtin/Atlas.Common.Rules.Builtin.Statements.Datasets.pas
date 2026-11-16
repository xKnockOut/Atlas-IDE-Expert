unit Atlas.Common.Rules.Builtin.Statements.Datasets;

// Datenmengen und Transaktionen, die offen bleiben (#909):
//   dataset-loop-without-next
//                     while not Q.Eof do ohne Q.Next auf jedem Weg durch den
//                     Rumpf, der die Schleife fortsetzt (#963); Delete, MoveBy,
//                     Last, Close und FindNext zählen mit. Wird Q im Rumpf
//                     weitergegeben oder stammt Q sicher nicht von TDataSet ab
//                     (Stream mit ReadLine), bleibt die Regel still.
//   dataset-edit-without-post
//                     Q.Edit, Q.Append bzw. Q.Insert ohne folgendes Post, Cancel
//                     oder CheckBrowseMode in der Routine (#964); still, wenn
//                     eine andere Routine der Unit Q postet oder Q weitergegeben wird,
//                     und wenn Q sicher nicht von TDataSet abstammt (#1326: Insert
//                     und Edit eines ActiveRecord, eines Records oder einer Liste); ein
//                     Typparameter hat den Typ seiner Klassen-Einschränkung
//                     (TMVCRepository<T: TMVCActiveRecord>).
//   transaction-without-rollback
//                     StartTransaction (BeginTransaction, BeginTrans) ohne Rollback
//                     im except des unmittelbar folgenden try (#965); Paare aus der
//                     Option pairs (start, commit, rollback) ersetzen die eingebauten.

interface

uses
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
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.Generics,
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
  mTarget: TSyntaxNode;
begin
  Result := '';
  AReceiver := '';
  AArguments := 0;
  if (ANode.Kind <> TSyntaxKind.CallStatement) or (ANode.ChildCount = 0) then
  begin
    Exit;
  end;
  mTarget := ANode[0];
  if (mTarget.Kind = TSyntaxKind.Call) and (mTarget.ChildCount > 0) then
  begin
    AArguments := mTarget.ChildCount - 1;
    mTarget := mTarget[0];
  end;
  if mTarget.Kind = TSyntaxKind.MemberAccess then
  begin
    if mTarget.ChildCount > 0 then
    begin
      AReceiver := Copy(AText, mTarget[0].StartOffset + 1, mTarget[0].EndOffset - mTarget[0].StartOffset);
    end;
    Result := mTarget.Name;
  end
  else if mTarget.Kind = TSyntaxKind.Identifier then
  begin
    Result := mTarget.Name;
  end;
end;

type
  /// <summary>Kann ein Empfänger eine Datenmenge sein (#1326)? Fragt den Resolver des Laufs, den sie beim ersten
  /// Bedarf öffnet und an den Baum heftet.</summary>
  TDataSetReceivers = class
  private
    FContext: TRuleContext;
    FFileName: string;
    FCache: IRuleDerivedCache;
    FResolver: TNameResolver;
    function ConstraintType(ARoutine: TSyntaxNode; const ATypeName: string; out AType: TResolvedSymbol): Boolean;
  public
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    /// <summary>Nein, wenn der Typ von AReceiver bekannt ist und die Vorfahrenkette ohne TDataSet vollständig endet
    /// oder er keine Klasse ist; bei unbekanntem Typ oder abgebrochener Kette ja.</summary>
    function MayBeDataSet(AReceiver: TSyntaxNode): Boolean;
    /// <summary>Wie MayBeDataSet; ein Typparameter der Klasse von ARoutine hat den Typ seiner Klassen-Einschränkung
    /// (TMVCRepository&lt;T: TMVCActiveRecord&gt;).</summary>
    function MayBeDataSetIn(AReceiver, ARoutine: TSyntaxNode): Boolean;
  end;

constructor TDataSetReceivers.Create(const AContext: TRuleContext);
begin
  inherited Create;
  FContext := AContext;
  FFileName := AContext.ResolverFileName;
end;

destructor TDataSetReceivers.Destroy;
begin
  if FResolver <> nil then
  begin
    FResolver.UnpinTree;
  end;
  inherited;
end;

/// <summary>Typ, den der Typparameter ATypeName der Klasse von ARoutine mindestens hat: bei
/// TAblage&lt;T: TSatz&gt; ist ein T ein TSatz. False ohne genau eine Typ-Einschränkung.</summary>
function TDataSetReceivers.ConstraintType(ARoutine: TSyntaxNode; const ATypeName: string;
  out AType: TResolvedSymbol): Boolean;
var
  mOwner: string;
  mUnit: TUnitIndex;
  mHeader, mParams: TSyntaxNode;
  mGeneric: TResolvedSymbol;
  mParam: TGenericParam;
  mConstraints: TArray<string>;
begin
  Result := False;
  if ARoutine = nil then
  begin
    Exit;
  end;
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  mParams := nil;
  if mHeader <> nil then
  begin
    mParams := mHeader.FindChild(TSyntaxKind.GenericParams);
  end;
  // Der Name trägt keine Typparameter (TAblage.Neu); die erste Gruppe gehört zur Klasse. Gehört sie zur Methode,
  // passt die Zahl der Typparameter nicht und der Typ bleibt unbekannt.
  if (ATypeName = '') or (mParams = nil) or (LastDelimiter('.', ARoutine.Name) = 0) then
  begin
    Exit;
  end;
  mOwner := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1) +
    Copy(FContext.Text, mParams.StartOffset + 1, mParams.EndOffset - mParams.StartOffset);
  mUnit := FResolver.ExtractedUnit(FContext.Tree, FFileName);
  if not FResolver.ResolveTypeTextFrom(mUnit, mOwner, mGeneric) then
  begin
    Exit;
  end;
  for mParam in TGenericConstraintViolatedRule.ParseParams(mGeneric.Signature) do
  begin
    if SameText(mParam.Name, ATypeName) then
    begin
      mConstraints := mParam.TypeConstraints;
      Exit((Length(mConstraints) = 1) and FResolver.ResolveTypeTextFrom(mUnit, mConstraints[0], AType));
    end;
  end;
end;

function TDataSetReceivers.MayBeDataSet(AReceiver: TSyntaxNode): Boolean;
begin
  Result := MayBeDataSetIn(AReceiver, nil);
end;

function TDataSetReceivers.MayBeDataSetIn(AReceiver, ARoutine: TSyntaxNode): Boolean;
var
  mSymbol, mTypeInfo: TResolvedSymbol;
  mTypeFound, mComplete: Boolean;
  mNames: TArray<string>;
begin
  Result := True;
  if FResolver = nil then
  begin
    // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
    FCache := TRuleDerived.Open(FContext);
    FResolver := TRuleDerived.Resolver(FCache, FContext);
    FResolver.PinTree(FContext.Tree, FFileName);
  end;
  if not FResolver.NodeType(FContext.Tree, FFileName, AReceiver, mSymbol, mTypeInfo, mTypeFound) then
  begin
    Exit;
  end;
  if not mTypeFound and not ConstraintType(ARoutine, mSymbol.TypeName, mTypeInfo) then
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
  mNames := FResolver.Queries.AncestorNames(mTypeInfo, mComplete);
  // Eine Kette, die bei TObject abbricht (System fehlt im Index), endet an der Wurzel ohne TDataSet.
  Result := (IndexText('TDataSet', mNames) >= 0) or
    (not mComplete and not SameText(mNames[High(mNames)], 'TObject'));
end;

{ TDatasetLoopWithoutNextRule }

const
  // Methoden, die den Datensatzzeiger weiterbewegen oder die Schleife über Eof beenden.
  cDatasetAdvancing: array[0..6] of string = ('Next', 'Delete', 'MoveBy', 'Last', 'Close', 'FindNext', 'Free');

{ TDatasetLoopWithoutNextRule }

function TDatasetLoopWithoutNextRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dataset-loop-without-next', TRuleSeverity.Error,
    cTexts[TStatementsDatasetsText.NextTitle].Text);
end;

type
  /// <summary>Ein Lauf von TDatasetLoopWithoutNextRule über eine Unit: Kontext, Bericht und der gemeinsame
  /// Zustand der Prüfschritte. Check legt ihn an und ruft Run.</summary>
  TDatasetLoopWithoutNextScan = record
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FLines: TArray<string>;
    FLineBreak: string;
    FDataSet: string;
    FReceivers: TDataSetReceivers;
    function NodeText(ANode: TSyntaxNode): string;
    function StatementName(ANode: TSyntaxNode; out AReceiver: string): string;
    function IsAdvance(ANode: TSyntaxNode): Boolean;
    function HasContinue(ANode: TSyntaxNode): Boolean;
    function ChildRange(ANode: TSyntaxNode; AFrom, ATo: Integer): TArray<TSyntaxNode>;
    function CaseParts(ANode: TSyntaxNode): TArray<TSyntaxNode>;
    function AdvanceParts(ANode: TSyntaxNode): TArray<TSyntaxNode>;
    function CallAdvances(ANode: TSyntaxNode): Boolean;
    function PartAdvances(AValues: TDictionary<TSyntaxNode, Boolean>; APart: TSyntaxNode): Boolean;
    function BlockAdvances(const AParts: TArray<TSyntaxNode>; AValues: TDictionary<TSyntaxNode, Boolean>): Boolean;
    function AnyAdvances(const AParts: TArray<TSyntaxNode>; AValues: TDictionary<TSyntaxNode, Boolean>): Boolean;
    function AllAdvance(const AParts: TArray<TSyntaxNode>; AValues: TDictionary<TSyntaxNode, Boolean>): Boolean;
    function NodeAdvances(ANode: TSyntaxNode; const AParts: TArray<TSyntaxNode>;
      AValues: TDictionary<TSyntaxNode, Boolean>): Boolean;
    function Advances(ANode: TSyntaxNode): Boolean;
    function Escapes(ANode: TSyntaxNode): Boolean;
    function MentionsAdvance(ANode: TSyntaxNode): Boolean;
    function NextFix(ABody: TSyntaxNode): TArray<TRuleFix>;
    function IsNotEof(ACondition: TSyntaxNode): Boolean;
    procedure InspectLoop(ACondition, ABody: TSyntaxNode);
    procedure Visit(ARoot: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TDatasetLoopWithoutNextScan }

constructor TDatasetLoopWithoutNextScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  FContext := AContext;
  FReport := AReport;
end;

function TDatasetLoopWithoutNextScan.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TDatasetLoopWithoutNextScan.StatementName(ANode: TSyntaxNode; out AReceiver: string): string;
var
  mArguments: Integer;
begin
  Result := StatementCall(FContext.Text, ANode, AReceiver, mArguments);
end;

function TDatasetLoopWithoutNextScan.IsAdvance(ANode: TSyntaxNode): Boolean;
var
  mReceiver, mName: string;
begin
  mName := StatementName(ANode, mReceiver);
  Result := SameText(mReceiver, FDataSet) and MatchText(mName, cDatasetAdvancing);
end;

// Continue in ANode, außer in inneren Schleifen?
function TDatasetLoopWithoutNextScan.HasContinue(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
  mReceiver: string;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.ForStatement,
        TSyntaxKind.ForInStatement, TSyntaxKind.AnonymousMethod] then
      begin
        Continue;
      end;
      if SameText(StatementName(mNode, mReceiver), 'Continue') and (mReceiver = '') then
      begin
        Exit(True);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

// Kinder AFrom..ATo von ANode, ohne except-Teile.
function TDatasetLoopWithoutNextScan.ChildRange(ANode: TSyntaxNode; AFrom, ATo: Integer): TArray<TSyntaxNode>;
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
function TDatasetLoopWithoutNextScan.CaseParts(ANode: TSyntaxNode): TArray<TSyntaxNode>;
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
function TDatasetLoopWithoutNextScan.AdvanceParts(ANode: TSyntaxNode): TArray<TSyntaxNode>;
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
function TDatasetLoopWithoutNextScan.CallAdvances(ANode: TSyntaxNode): Boolean;
var
  mReceiver, mName: string;
begin
  mName := StatementName(ANode, mReceiver);
  // Break, Exit und Halt verlassen die Schleife; Continue setzt sie ohne Weiterbewegen fort.
  Result := IsAdvance(ANode) or ((mReceiver = '') and MatchText(mName, ['Break', 'Exit', 'Halt', 'Abort']));
end;

/// <summary>Ergebnis des Teils APart; jeder Teil steht in AValues, bevor sein Knoten zusammengefasst wird.</summary>
function TDatasetLoopWithoutNextScan.PartAdvances(AValues: TDictionary<TSyntaxNode, Boolean>;
  APart: TSyntaxNode): Boolean;
begin
  if not AValues.TryGetValue(APart, Result) then
  begin
    Result := False;
  end;
end;

// Bewegt ein Teil eines Blocks weiter, bevor ein Continue die Schleife auf demselben Datensatz fortsetzt?
function TDatasetLoopWithoutNextScan.BlockAdvances(const AParts: TArray<TSyntaxNode>;
  AValues: TDictionary<TSyntaxNode, Boolean>): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  mIndex := 0;
  while (mIndex <= High(AParts)) and not Result do
  begin
    Result := PartAdvances(AValues, AParts[mIndex]);
    if not Result and HasContinue(AParts[mIndex]) then
    begin
      Break;
    end;
    Inc(mIndex);
  end;
end;

function TDatasetLoopWithoutNextScan.AnyAdvances(const AParts: TArray<TSyntaxNode>;
  AValues: TDictionary<TSyntaxNode, Boolean>): Boolean;
var
  mPart: TSyntaxNode;
begin
  Result := False;
  for mPart in AParts do
  begin
    Result := Result or PartAdvances(AValues, mPart);
  end;
end;

function TDatasetLoopWithoutNextScan.AllAdvance(const AParts: TArray<TSyntaxNode>;
  AValues: TDictionary<TSyntaxNode, Boolean>): Boolean;
var
  mPart: TSyntaxNode;
begin
  Result := True;
  for mPart in AParts do
  begin
    Result := Result and PartAdvances(AValues, mPart);
  end;
end;

// Ergebnis für ANode aus den Ergebnissen seiner Teile AParts.
function TDatasetLoopWithoutNextScan.NodeAdvances(ANode: TSyntaxNode; const AParts: TArray<TSyntaxNode>;
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
function TDatasetLoopWithoutNextScan.Advances(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
  mParts: TArray<TSyntaxNode>;
  mEntry: TSyntaxPostOrderEntry;
  mPending: TStack<TSyntaxPostOrderEntry>;
  mValues: TDictionary<TSyntaxNode, Boolean>;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht): Nachordnung, die Teile zuerst; lange else-if-Ketten ergeben
  // sehr tiefe Bäume.
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
function TDatasetLoopWithoutNextScan.Escapes(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
  mNode, mParent: TSyntaxNode;
  mPending, mParents: TStack<TSyntaxNode>;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht): zu jedem Knoten auf dem Stapel sein Elternknoten (nil an der
  // Wurzel).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  mParents := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    mParents.Push(nil);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mParent := mParents.Pop;
      if mNode.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Continue;
      end;
      if (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
        SameText(NodeText(mNode), FDataSet) and
        not ((mParent <> nil) and (mParent.Kind = TSyntaxKind.MemberAccess) and (mParent[0] = mNode)) then
      begin
        Exit(True);
      end;
      if mNode.Kind = TSyntaxKind.WithStatement then
      begin
        Exit(True);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
        mParents.Push(mNode);
      end;
    end;
  finally
    mParents.Free;
    mPending.Free;
  end;
end;

function TDatasetLoopWithoutNextScan.MentionsAdvance(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if IsAdvance(mNode) then
      begin
        Exit(True);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

// Korrektur: Q.Next; vor dem end des Rumpfs.
function TDatasetLoopWithoutNextScan.NextFix(ABody: TSyntaxNode): TArray<TRuleFix>;
var
  mEndLine: Integer;
begin
  Result := nil;
  if ABody.Kind <> TSyntaxKind.Block then
  begin
    Exit;
  end;
  mEndLine := ABody.EndPos.Line;
  if (mEndLine <= ABody.StartPos.Line) or (Trim(Copy(FLines[mEndLine], 1, ABody.EndPos.Character -
    Length('end'))) <> '') then
  begin
    Exit;
  end;
  Result := [TRuleFix.Create(cTexts[TStatementsDatasetsText.InsertNext].Fmt([FDataSet]), [TRuleEdit.Create(
    TTextRange.Create(mEndLine, 0, mEndLine, 0), TTextLines.IndentOf(FLines[mEndLine]) +
    TRoutineBody.IndentUnit(FContext.Formatting) + FDataSet + '.Next;' + FLineBreak)])];
end;

// not Q.Eof
function TDatasetLoopWithoutNextScan.IsNotEof(ACondition: TSyntaxNode): Boolean;
begin
  Result := (ACondition.Kind = TSyntaxKind.UnaryExpr) and SameText(ACondition.Name, 'not') and
    (ACondition.ChildCount = 1);
  Result := Result and (ACondition[0].Kind = TSyntaxKind.MemberAccess) and SameText(ACondition[0].Name, 'Eof') and
    (ACondition[0].ChildCount = 1);
end;

procedure TDatasetLoopWithoutNextScan.InspectLoop(ACondition, ABody: TSyntaxNode);
begin
  FDataSet := NodeText(ACondition[0][0]);
  // Eof eines Lesers, der kein TDataSet ist (Stream mit ReadLine), rückt anders vor.
  if Escapes(ABody) or Advances(ABody) or not FReceivers.MayBeDataSet(ACondition[0][0]) then
  begin
    Exit;
  end;
  if not MentionsAdvance(ABody) then
  begin
    FReport.Add(TTextRange.Create(ACondition.StartPos, ACondition.EndPos),
      cTexts[TStatementsDatasetsText.NextMissing].Fmt([FDataSet]), TRuleConfidence.High,
      NextFix(ABody));
  end
  else
  begin
    FReport.Add(TTextRange.Create(ACondition.StartPos, ACondition.EndPos),
      cTexts[TStatementsDatasetsText.NextNotAlways].Fmt([FDataSet]), TRuleConfidence.Medium);
  end;
end;

procedure TDatasetLoopWithoutNextScan.Visit(ARoot: TSyntaxNode);
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      // while not Q.Eof do …
      if (mNode.Kind = TSyntaxKind.WhileStatement) and (mNode.ChildCount = 2) and IsNotEof(mNode[0]) then
      begin
        InspectLoop(mNode[0], mNode[1]);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TDatasetLoopWithoutNextScan.Run;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) or not ContainsText(FContext.Text, 'Eof') then
  begin
    Exit;
  end;
  FLines := TTextLines.SplitLines(FContext.Text, FLineBreak);
  FReceivers := TDataSetReceivers.Create(FContext);
  try
    Visit(FContext.Tree.Root);
  finally
    FReceivers.Free;
  end;
end;

procedure TDatasetLoopWithoutNextRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TDatasetLoopWithoutNextScan;
begin
  mScan := TDatasetLoopWithoutNextScan.Create(AContext, AReport);
  mScan.Run;
end;

{ TDatasetEditWithoutPostRule }

const
  cDatasetEditMethods: array[0..2] of string = ('Edit', 'Append', 'Insert');
  // Methoden, die den Bearbeitungsmodus beenden.
  cDatasetPostMethods: array[0..2] of string = ('Post', 'Cancel', 'CheckBrowseMode');

{ TDatasetEditWithoutPostRule }

function TDatasetEditWithoutPostRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dataset-edit-without-post', TRuleSeverity.Warning,
    cTexts[TStatementsDatasetsText.PostTitle].Text);
end;

type
  /// <summary>Ein Lauf von TDatasetEditWithoutPostRule über eine Unit: Kontext, Bericht und der gemeinsame
  /// Zustand der Prüfschritte. Check legt ihn an und ruft Run.</summary>
  TDatasetEditWithoutPostScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FLines: TArray<string>;
    FLineBreak: string;
    FRoutines: TArray<TSyntaxNode>;
    FReceivers: TDataSetReceivers;
    function MayBeDataSet(AStatement, ARoutine: TSyntaxNode): Boolean;
    function NodeText(ANode: TSyntaxNode): string;
    function Ends(ANode: TSyntaxNode; const ADataSet: string; AFrom: Integer): Boolean;
    function IsReceiver(ANode, AParent: TSyntaxNode): Boolean;
    function Escapes(ANode: TSyntaxNode; const ADataSet: string; AFrom: Integer): Boolean;
    function UsesDataSet(ANode: TSyntaxNode; const ADataSet: string): Boolean;
    function OwnLine(ANode: TSyntaxNode): Boolean;
    function PostFix(AStatement: TSyntaxNode; const ADataSet: string): TArray<TRuleFix>;
    function EndedElsewhere(ARoutine: TSyntaxNode; const ADataSet: string): Boolean;
    function IsOpenEdit(ANode, ARoutine: TSyntaxNode; out AName, AReceiver: string): Boolean;
    procedure CheckCall(ANode, ARoutine: TSyntaxNode);
    procedure Visit(ARoot: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TDatasetEditWithoutPostScan }

constructor TDatasetEditWithoutPostScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

/// <summary>Kann der Empfänger des Aufrufs AStatement eine Datenmenge sein (TDataSetReceivers.MayBeDataSet)?
/// </summary>
function TDatasetEditWithoutPostScan.MayBeDataSet(AStatement, ARoutine: TSyntaxNode): Boolean;
var
  mTarget: TSyntaxNode;
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
  Result := FReceivers.MayBeDataSetIn(mTarget[0], ARoutine);
end;

function TDatasetEditWithoutPostScan.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

// Beendet ANode (oder ein Nachfahr ab AFrom) den Bearbeitungsmodus von ADataSet?
function TDatasetEditWithoutPostScan.Ends(ANode: TSyntaxNode; const ADataSet: string; AFrom: Integer): Boolean;
var
  mIndex, mArguments: Integer;
  mReceiver, mName: string;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.StartOffset >= AFrom then
      begin
        mName := StatementCall(FContext.Text, mNode, mReceiver, mArguments);
        if SameText(mReceiver, ADataSet) and MatchText(mName, cDatasetPostMethods) then
        begin
          Exit(True);
        end;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        if mNode[mIndex].EndOffset > AFrom then
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

// Steht ANode als Empfänger links in seinem Elternknoten (Q.X, Q['X'])?
function TDatasetEditWithoutPostScan.IsReceiver(ANode, AParent: TSyntaxNode): Boolean;
begin
  Result := (AParent <> nil) and (AParent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) and
    (AParent[0] = ANode);
end;

// Kommt ADataSet ab AFrom als Wert vor (Argument, Zuweisung), nicht nur als Empfänger (Q.X, Q['X'])?
function TDatasetEditWithoutPostScan.Escapes(ANode: TSyntaxNode; const ADataSet: string; AFrom: Integer): Boolean;
var
  mIndex: Integer;
  mNode, mParent: TSyntaxNode;
  mPending, mParents: TStack<TSyntaxNode>;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht): zu jedem Knoten auf dem Stapel sein Elternknoten (nil an der
  // Wurzel). Eine Nennung der Datenmenge als Empfänger beendet nur ihren Zweig, wie in der Rekursion.
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  mParents := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    mParents.Push(nil);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mParent := mParents.Pop;
      if (mNode.StartOffset >= AFrom) and (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
        SameText(NodeText(mNode), ADataSet) then
      begin
        Result := not IsReceiver(mNode, mParent);
        if Result then
        begin
          Exit;
        end;
        Continue;
      end;
      if (mNode.StartOffset >= AFrom) and (mNode.Kind = TSyntaxKind.WithStatement) then
      begin
        Exit(True);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        if mNode[mIndex].EndOffset > AFrom then
        begin
          mPending.Push(mNode[mIndex]);
          mParents.Push(mNode);
        end;
      end;
    end;
  finally
    mParents.Free;
    mPending.Free;
  end;
end;

function TDatasetEditWithoutPostScan.UsesDataSet(ANode: TSyntaxNode; const ADataSet: string): Boolean;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
        SameText(NodeText(mNode), ADataSet) then
      begin
        Exit(True);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function TDatasetEditWithoutPostScan.OwnLine(ANode: TSyntaxNode): Boolean;
var
  mRest: string;
begin
  mRest := Trim(Copy(FLines[ANode.EndPos.Line], ANode.EndPos.Character + 1, MaxInt));
  Result := (Trim(Copy(FLines[ANode.StartPos.Line], 1, ANode.StartPos.Character)) = '') and
    ((mRest = '') or (mRest = ';')) and (ANode.EndPos.Line < High(FLines));
end;

// Korrektur: die folgenden Anweisungen, die die Datenmenge benutzen, in try … Post … except Cancel; raise; end.
function TDatasetEditWithoutPostScan.PostFix(AStatement: TSyntaxNode; const ADataSet: string): TArray<TRuleFix>;
var
  mList: TSyntaxNode;
  mIndex, mPosition, mLast, mLine: Integer;
  mIndent, mStep, mText: string;
begin
  Result := nil;
  mList := AStatement.Parent;
  if (mList = nil) or not OwnLine(AStatement) then
  begin
    Exit;
  end;
  mPosition := -1;
  for mIndex := 0 to mList.ChildCount - 1 do
  begin
    if mList[mIndex] = AStatement then
    begin
      mPosition := mIndex;
    end;
  end;
  mLast := mPosition;
  while (mLast + 1 < mList.ChildCount) and (mList[mLast + 1].Kind in [TSyntaxKind.AssignStatement,
    TSyntaxKind.CallStatement]) and UsesDataSet(mList[mLast + 1], ADataSet) and OwnLine(mList[mLast + 1]) do
  begin
    Inc(mLast);
  end;
  if (mPosition < 0) or (mLast = mPosition) then
  begin
    Exit;
  end;
  mIndent := TTextLines.IndentOf(FLines[AStatement.StartPos.Line]);
  mStep := TRoutineBody.IndentUnit(FContext.Formatting);
  mText := mIndent + 'try' + FLineBreak;
  for mLine := mList[mPosition + 1].StartPos.Line to mList[mLast].EndPos.Line do
  begin
    mText := mText + mStep + FLines[mLine] + FLineBreak;
  end;
  mText := mText + mIndent + mStep + ADataSet + '.Post;' + FLineBreak + mIndent + 'except' + FLineBreak + mIndent + mStep +
    ADataSet + '.Cancel;' + FLineBreak + mIndent + mStep + 'raise;' + FLineBreak + mIndent + 'end;' + FLineBreak;
  Result := [TRuleFix.Create(cTexts[TStatementsDatasetsText.AddPost].Fmt([ADataSet]), [TRuleEdit.Create(
    TTextRange.Create(mList[mPosition + 1].StartPos.Line, 0, mList[mLast].EndPos.Line + 1, 0), mText)])];
end;

// Beendet eine andere Routine der Unit den Bearbeitungsmodus (Bearbeiten-/Speichern-Knopf)?
function TDatasetEditWithoutPostScan.EndedElsewhere(ARoutine: TSyntaxNode; const ADataSet: string): Boolean;
var
  mOther: TSyntaxNode;
begin
  for mOther in FRoutines do
  begin
    if (mOther <> ARoutine) and Ends(mOther, ADataSet, 0) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

// Q.Edit, Q.Append bzw. Q.Insert ohne Argumente, das in ARoutine offen bleibt?
function TDatasetEditWithoutPostScan.IsOpenEdit(ANode, ARoutine: TSyntaxNode; out AName, AReceiver: string): Boolean;
var
  mArguments: Integer;
begin
  AName := StatementCall(FContext.Text, ANode, AReceiver, mArguments);
  Result := (AReceiver <> '') and (mArguments = 0) and MatchText(AName, cDatasetEditMethods);
  Result := Result and not Ends(ARoutine, AReceiver, ANode.EndOffset) and
    not Escapes(ARoutine, AReceiver, ANode.EndOffset);
  Result := Result and not EndedElsewhere(ARoutine, AReceiver) and MayBeDataSet(ANode, ARoutine);
end;

procedure TDatasetEditWithoutPostScan.CheckCall(ANode, ARoutine: TSyntaxNode);
var
  mName, mReceiver: string;
begin
  if IsOpenEdit(ANode, ARoutine, mName, mReceiver) then
  begin
    FReport.Add(TTextRange.Create(ANode[0].EndPos.Line, ANode[0].EndPos.Character - Length(mName),
      ANode[0].EndPos.Line, ANode[0].EndPos.Character), cTexts[TStatementsDatasetsText.PostMissing].Fmt([mName]),
        TRuleConfidence.Medium, PostFix(ANode, mReceiver));
  end;
end;

procedure TDatasetEditWithoutPostScan.Visit(ARoot: TSyntaxNode);
var
  mIndex: Integer;
  mNode, mRoutine: TSyntaxNode;
  mPending, mPendingRoutines: TStack<TSyntaxNode>;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht): zu jedem Knoten auf dem Stapel die umgebende Routine.
  mPending := TStack<TSyntaxNode>.Create;
  mPendingRoutines := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    mPendingRoutines.Push(nil);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mRoutine := mPendingRoutines.Pop;
      if mNode.Kind = TSyntaxKind.RoutineDecl then
      begin
        mRoutine := mNode;
      end;
      if (mRoutine <> nil) and (mNode.Kind = TSyntaxKind.CallStatement) then
      begin
        CheckCall(mNode, mRoutine);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
        mPendingRoutines.Push(mRoutine);
      end;
    end;
  finally
    mPendingRoutines.Free;
    mPending.Free;
  end;
end;

procedure TDatasetEditWithoutPostScan.Run;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FLines := TTextLines.SplitLines(FContext.Text, FLineBreak);
  FRoutines := nil;
  FContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
      begin
        FRoutines := FRoutines + [ANode];
      end;
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
    end);
  FReceivers := TDataSetReceivers.Create(FContext);
  try
    Visit(FContext.Tree.Root);
  finally
    FReceivers.Free;
  end;
end;

procedure TDatasetEditWithoutPostRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TDatasetEditWithoutPostScan;
begin
  mScan := TDatasetEditWithoutPostScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

{ TTransactionWithoutRollbackRule }

const
  // FireDAC, IBX und dbExpress (StartTransaction), dbExpress ab XE (BeginTransaction), ADO (BeginTrans).
  cBuiltinTransactionPairs: array[0..2, 0..2] of string = (('StartTransaction', 'Commit', 'Rollback'),
    ('BeginTransaction', 'CommitFreeAndNil', 'RollbackFreeAndNil'), ('BeginTrans', 'CommitTrans', 'RollbackTrans'));

{ TTransactionWithoutRollbackRule }

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

type
  /// <summary>Ein Lauf von TTransactionWithoutRollbackRule über eine Unit: Kontext, Bericht und der gemeinsame
  /// Zustand der Prüfschritte. Check legt ihn an und ruft Run.</summary>
  TTransactionWithoutRollbackScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FLines: TArray<string>;
    FLineBreak: string;
    FRoutines: TArray<TSyntaxNode>;
    FKnown: TArray<TTransactionPair>;
    function NodeText(ANode: TSyntaxNode): string;
    function CallIn(ANode: TSyntaxNode; out AReceiver: string; out ACall, AMember: TSyntaxNode): string;
    function Calls(ANode: TSyntaxNode; const AReceiver, AMethod: string; AInExcept: Boolean): Boolean;
    function OwnLine(ANode: TSyntaxNode): Boolean;
    function RollbackFix(AList: TSyntaxNode; APosition: Integer; const AReceiver: string;
      const APair: TTransactionPair): TArray<TRuleFix>;
    function PositionInList(AStatement: TSyntaxNode): Integer;
    function RolledBackElsewhere(ARoutine: TSyntaxNode; const AReceiver, ARollback: string): Boolean;
    function RolledBackAfter(AList: TSyntaxNode; APosition: Integer; const AReceiver, ARollback: string): Boolean;
    procedure CheckStart(AStatement, ARoutine, AMember: TSyntaxNode; const AReceiver: string;
      const APair: TTransactionPair);
    procedure CheckStatement(AStatement, ARoutine: TSyntaxNode);
    procedure Visit(ARoot: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TTransactionWithoutRollbackScan }

constructor TTransactionWithoutRollbackScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

function TTransactionWithoutRollbackScan.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

// Aufruf X.M bzw. X.M(…) in ANode selbst (Anweisung oder rechte Seite einer Zuweisung).
function TTransactionWithoutRollbackScan.CallIn(ANode: TSyntaxNode; out AReceiver: string; out ACall,
  AMember: TSyntaxNode): string;
var
  mTarget: TSyntaxNode;
begin
  Result := '';
  AReceiver := '';
  ACall := nil;
  AMember := nil;
  if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount > 0) then
  begin
    mTarget := ANode[0];
  end
  else if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) then
  begin
    mTarget := ANode[1];
  end
  else if (ANode.Kind = TSyntaxKind.InlineVar) and (ANode.ChildCount > 0) then
  begin
    mTarget := ANode[ANode.ChildCount - 1];
  end
  else
  begin
    Exit;
  end;
  if (mTarget.Kind = TSyntaxKind.Call) and (mTarget.ChildCount > 0) then
  begin
    ACall := mTarget;
    mTarget := mTarget[0];
  end;
  if (mTarget.Kind = TSyntaxKind.MemberAccess) and (mTarget.ChildCount > 0) then
  begin
    AReceiver := NodeText(mTarget[0]);
    AMember := mTarget;
    Result := mTarget.Name;
  end;
end;

// Ruft ANode (auch verschachtelt) AReceiver.AMethod auf? Nur in except-Teilen, wenn AInExcept.
function TTransactionWithoutRollbackScan.Calls(ANode: TSyntaxNode; const AReceiver, AMethod: string;
  AInExcept: Boolean): Boolean;
var
  mIndex: Integer;
  mReceiver: string;
  mNode, mCall, mMember: TSyntaxNode;
  mInside: Boolean;
  mPending: TStack<TSyntaxNode>;
  mPendingInside: TStack<Boolean>;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht): zu jedem Knoten auf dem Stapel, ob er in einem except-Teil
  // liegt.
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  mPendingInside := TStack<Boolean>.Create;
  try
    mPending.Push(ANode);
    mPendingInside.Push(False);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mInside := mPendingInside.Pop;
      if mNode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
      begin
        Continue;
      end;
      if mNode.Kind = TSyntaxKind.ExceptBlock then
      begin
        mInside := True;
      end;
      if (mInside or not AInExcept) and SameText(CallIn(mNode, mReceiver, mCall, mMember), AMethod) and
        SameText(mReceiver, AReceiver) then
      begin
        Exit(True);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
        mPendingInside.Push(mInside);
      end;
    end;
  finally
    mPendingInside.Free;
    mPending.Free;
  end;
end;

function TTransactionWithoutRollbackScan.OwnLine(ANode: TSyntaxNode): Boolean;
var
  mRest: string;
begin
  mRest := Trim(Copy(FLines[ANode.EndPos.Line], ANode.EndPos.Character + 1, MaxInt));
  Result := (Trim(Copy(FLines[ANode.StartPos.Line], 1, ANode.StartPos.Character)) = '') and
    ((mRest = '') or (mRest = ';')) and (ANode.EndPos.Line < High(FLines));
end;

// Korrektur: Anweisungen bis zum Commit in try … except Rollback; raise; end.
function TTransactionWithoutRollbackScan.RollbackFix(AList: TSyntaxNode; APosition: Integer; const AReceiver: string;
  const APair: TTransactionPair): TArray<TRuleFix>;
var
  mIndex, mLast, mLine: Integer;
  mReceiver, mIndent, mStep, mText, mArguments: string;
  mCall, mMember: TSyntaxNode;
begin
  Result := nil;
  mLast := -1;
  mArguments := '';
  for mIndex := APosition + 1 to AList.ChildCount - 1 do
  begin
    if SameText(CallIn(AList[mIndex], mReceiver, mCall, mMember), APair.Commit) and
      SameText(mReceiver, AReceiver) then
    begin
      mLast := mIndex;
      // Commit(TD) bzw. CommitFreeAndNil(T): dieselben Argumente für Rollback.
      if (mCall <> nil) and (mCall.ChildCount > 1) then
      begin
        mArguments := Copy(NodeText(mCall), Length(NodeText(mCall[0])) + 1, MaxInt);
      end;
      Break;
    end;
  end;
  if (mLast < 0) or not OwnLine(AList[APosition]) then
  begin
    Exit;
  end;
  for mIndex := APosition + 1 to mLast do
  begin
    if not OwnLine(AList[mIndex]) then
    begin
      Exit;
    end;
  end;
  mIndent := TTextLines.IndentOf(FLines[AList[APosition].StartPos.Line]);
  mStep := TRoutineBody.IndentUnit(FContext.Formatting);
  mText := mIndent + 'try' + FLineBreak;
  for mLine := AList[APosition + 1].StartPos.Line to AList[mLast].EndPos.Line do
  begin
    mText := mText + mStep + FLines[mLine] + FLineBreak;
  end;
  mText := mText + mIndent + 'except' + FLineBreak + mIndent + mStep + AReceiver + '.' + APair.Rollback + mArguments +
    ';' + FLineBreak + mIndent + mStep + 'raise;' + FLineBreak + mIndent + 'end;' + FLineBreak;
  Result := [TRuleFix.Create(cTexts[TStatementsDatasetsText.CreateTry].Fmt([AReceiver, APair.Rollback]),
    [TRuleEdit.Create(TTextRange.Create(AList[APosition + 1].StartPos.Line, 0, AList[mLast].EndPos.Line + 1, 0),
    mText)])];
end;

// Stelle von AStatement in der Anweisungsliste darüber; -1 ohne.
function TTransactionWithoutRollbackScan.PositionInList(AStatement: TSyntaxNode): Integer;
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
function TTransactionWithoutRollbackScan.RolledBackElsewhere(ARoutine: TSyntaxNode; const AReceiver,
  ARollback: string): Boolean;
var
  mOther: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  for mOther in FRoutines do
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
function TTransactionWithoutRollbackScan.RolledBackAfter(AList: TSyntaxNode; APosition: Integer; const AReceiver,
  ARollback: string): Boolean;
begin
  Result := (APosition >= 0) and (APosition + 1 < AList.ChildCount);
  Result := Result and (AList[APosition + 1].Kind = TSyntaxKind.TryStatement) and
    Calls(AList[APosition + 1], AReceiver, ARollback, True);
end;

procedure TTransactionWithoutRollbackScan.CheckStart(AStatement, ARoutine, AMember: TSyntaxNode;
  const AReceiver: string;
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
  FReport.Add(TTextRange.Create(AMember.EndPos.Line, AMember.EndPos.Character - Length(AMember.Name),
    AMember.EndPos.Line, AMember.EndPos.Character), cTexts[TStatementsDatasetsText.Rollback].Text,
      TRuleConfidence.High, RollbackFix(mList, mPosition, AReceiver, APair));
end;

procedure TTransactionWithoutRollbackScan.CheckStatement(AStatement, ARoutine: TSyntaxNode);
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
  for mPair in FKnown do
  begin
    if SameText(mName, mPair.Start) then
    begin
      CheckStart(AStatement, ARoutine, mMember, mReceiver, mPair);
      Exit;
    end;
  end;
end;

procedure TTransactionWithoutRollbackScan.Visit(ARoot: TSyntaxNode);
var
  mIndex: Integer;
  mNode, mRoutine: TSyntaxNode;
  mPending, mPendingRoutines: TStack<TSyntaxNode>;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht): zu jedem Knoten auf dem Stapel die umgebende Routine.
  mPending := TStack<TSyntaxNode>.Create;
  mPendingRoutines := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    mPendingRoutines.Push(nil);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mRoutine := mPendingRoutines.Pop;
      if mNode.Kind = TSyntaxKind.RoutineDecl then
      begin
        mRoutine := mNode;
      end;
      if (mRoutine <> nil) and (mNode.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.AssignStatement,
        TSyntaxKind.InlineVar]) then
      begin
        CheckStatement(mNode, mRoutine);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
        mPendingRoutines.Push(mRoutine);
      end;
    end;
  finally
    mPendingRoutines.Free;
    mPending.Free;
  end;
end;

procedure TTransactionWithoutRollbackScan.Run;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FKnown := TTransactionWithoutRollbackRule.Pairs(FContext.Options);
  FLines := TTextLines.SplitLines(FContext.Text, FLineBreak);
  FRoutines := nil;
  FContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
      begin
        FRoutines := FRoutines + [ANode];
      end;
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
    end);
  Visit(FContext.Tree.Root);
end;

procedure TTransactionWithoutRollbackRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TTransactionWithoutRollbackScan;
begin
  mScan := TTransactionWithoutRollbackScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

class function TTransactionWithoutRollbackRule.Pairs(const AOptions: string): TArray<TTransactionPair>;
var
  mIndex: Integer;
  mPair: TTransactionPair;
begin
  // Eine eigene Liste ersetzt die eingebauten Paare.
  if PairsFromOptions(AOptions, Result) then
  begin
    Exit;
  end;
  for mIndex := Low(cBuiltinTransactionPairs) to High(cBuiltinTransactionPairs) do
  begin
    mPair.Start := cBuiltinTransactionPairs[mIndex, 0];
    mPair.Commit := cBuiltinTransactionPairs[mIndex, 1];
    mPair.Rollback := cBuiltinTransactionPairs[mIndex, 2];
    Result := Result + [mPair];
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Statements.Datasets', cTexts);

end.
