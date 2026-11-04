unit Atlas.Common.Editing.Inlining.Method;

// „Methode einbetten“ (#103, Teil A): Der Aufruf an der Einfügemarke wird
// durch den Rumpf ersetzt. Lokale Namen der Methode bekommen eindeutige
// Namen; Parameter werden durch die Argumente ersetzt, wenn das die
// Bedeutung nicht ändert, sonst durch Hilfsvariablen; Mitglieder bekommen
// den Empfänger des Aufrufs. Ein Ergebnis aus einer einzigen Zuweisung
// ersetzt den Aufruf direkt, sonst trägt es eine Variable <Name>Result.
// Erlaubt sind ein Exit als letzte Anweisung und ein „if … then Exit“ auf
// oberster Ebene; daraus wird ein if mit else.
//
// Die Prüfungen und Umformungen laufen als Schritte über den Arbeitsstand
// TMethodInliner; jede Prüfung liefert einen Grund oder ''.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.Inlining.Types;

type
  TMethodInlining = class
  public
    /// <summary>„Methode einbetten“ für den Aufruf an APosition in ACaller; ACallee ist der Rumpf (dieselbe
    /// Datei oder eine andere). False mit Grund in AReason.</summary>
    class function Run(const ACaller: TInlineSource; const APosition: TTextPosition; const ACallee: TInlineCallee;
      const AOptions: TInlineOptions; out AAction: TCodeAction; out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.Inlining.Syntax;

type
  TLocal = TRoutineLocal;
  TLocalKind = TRoutineLocalKind;

{$SCOPEDENUMS ON}
  TExitMode = (NoExit, LastExit, GuardExit);
{$SCOPEDENUMS OFF}

  /// <summary>Ersetzung im Text der Methode: Offsets Start..Finish (exklusiv) werden zu Text.</summary>
  TReplacement = record
    Start: Integer;
    Finish: Integer;
    Text: string;
  end;

  TParameterInfo = record
    Name: string;
    Modifier: TParameterModifier;
    TypeText: string;
    TypeNode: TSyntaxNode;
    DefaultValue: TSyntaxNode;
  end;

  /// <summary>Arbeitsstand von „Methode einbetten“.</summary>
  TMethodInliner = record
    Caller: TInlineSource;
    Callee: TInlineSource;
    Routine: TSyntaxNode;
    Options: TInlineOptions;
    Call: TInlineCall;
    CalleeTokens: TArray<TPascalToken>;
    CallerTokens: TArray<TPascalToken>;
    ShortName: string;
    CalleeClass: string;
    CallerClass: string;
    ReceiverText: string;
    ResultName: string;
    ResultType: string;
    LineBreak: string;
    IndentUnit: string;
    Header: TSyntaxNode;
    ReturnType: TSyntaxNode;
    CalleeBody: TSyntaxNode;
    CallerRoutine: TSyntaxNode;
    CallerBody: TSyntaxNode;
    Host: TSyntaxNode;
    IsFunction: Boolean;
    IsMethod: Boolean;
    /// <summary>Kann der Rumpf Speicher außerhalb seiner lokalen Namen ändern?</summary>
    Mutates: Boolean;
    Locals: TArray<TLocal>;
    CallerLocals: TArray<TLocal>;
    CalleeFlow: TFlowSignatureLookup;
    Parameters: TArray<TParameterInfo>;
    NewNames: TArray<string>;
    ParameterText: TArray<string>;
    /// <summary>Erste Namen der Argumente für var- und out-Parameter.</summary>
    ArgumentNames: TArray<string>;
    Statements: TArray<TSyntaxNode>;
    ExitMode: TExitMode;
    ExitStatement: TSyntaxNode;
    ExitValue: TSyntaxNode;
    Guard: TSyntaxNode;
    GuardIndex: Integer;
    SimpleExpression: TSyntaxNode;
    Replacements: TList<TReplacement>;
    Taken: TDictionary<string, Boolean>;
    Lines: TArray<string>;
    VarEntries: TArray<string>;
    ConstEntries: TArray<string>;
    Edits: TArray<TTextEdit>;
    class function Create(const ACaller: TInlineSource; const ACallee: TInlineCallee;
      const AOptions: TInlineOptions): TMethodInliner; static;
    procedure Release;
    function Execute(const APosition: TTextPosition): string;
    function Action: TCodeAction;
    { Prüfungen }
    function StartIssue(const APosition: TTextPosition): string;
    function CalleeIssue: string;
    function KindIssue: string;
    procedure ReadNames;
    function NameIssue: string;
    procedure ReadHeader;
    function BodyIssue: string;
    function NestedIssue: string;
    function ForbiddenIssue: string;
    function CallsItself: Boolean;
    function CallerIssue: string;
    function ReceiverIssue: string;
    function PlaceIssue: string;
    function HostIssue: string;
    function CallsBefore: Boolean;
    function ParametersIssue: string;
    function ParametersOf: TArray<TParameterInfo>;
    function ParameterOf(ADecl: TSyntaxNode; const AName: string): TParameterInfo;
    function FlowIssue: string;
    function GraphIssue: string;
    function ResultSetInLoop: Boolean;
    function ExitIssue: string;
    procedure CollectStatements;
    function FindExit: string;
    function ExitPlaceIssue: string;
    function IsGuard(ANode: TSyntaxNode): Boolean;
    function StatementIndex(ANode: TSyntaxNode): Integer;
    procedure FindSimpleExpression;
    function HasOwnLocals: Boolean;
    { Umformung }
    function RewriteIssue: string;
    procedure CollectTaken;
    procedure CollectOwnIdentifiers(AList: TList<TSyntaxNode>);
    function LocalIndexOf(ANode: TSyntaxNode): Integer;
    function ConstantIndex(const AName: string): Integer;
    function ForeignNamesIssue: string;
    function ForeignNameIssue(ANode: TSyntaxNode): string;
    procedure NoteParameterWrite(ANode: TSyntaxNode; AIndex: Integer);
    function OutsideNameIssue(ANode: TSyntaxNode): string;
    function MeaningIssue(ANode: TSyntaxNode; const AFound: TInlineMeaning): string;
    function MemberIssue(ANode: TSyntaxNode; const AFound, AAtCall: TInlineMeaning): string;
    function Visible(const AMeaning: TInlineMeaning): Boolean;
    procedure NoteMutations;
    function SameType(ATypeNode: TSyntaxNode): Boolean;
    function TypesIssue: string;
    procedure RenameLocals;
    procedure RenameDeclarations;
    procedure RenameInDeclaration(AIndex: Integer);
    procedure ReplaceToken(AIndex: Integer; const AText: string);
    function ArgumentsIssue: string;
    procedure CollectArgumentNames;
    function ArgumentIssue(AIndex: Integer): string;
    function ArgumentOf(AIndex: Integer; out AArgument: TSyntaxNode; out AText: string): string;
    function DefaultValueIssue(AIndex: Integer): string;
    function ParameterOccurrences(const AName: string): TArray<TSyntaxNode>;
    function ReferenceArgumentIssue(AIndex: Integer; AArgument: TSyntaxNode; const AText: string;
      const AOccurrences: TArray<TSyntaxNode>): string;
    function CanSubstitute(AIndex: Integer; AArgument: TSyntaxNode; const AOccurrences: TArray<TSyntaxNode>): Boolean;
    procedure UsageOf(const AOccurrences: TArray<TSyntaxNode>; out AWritten, AInLoop: Boolean);
    function IsStable(AIndex: Integer; AArgument: TSyntaxNode): Boolean;
    function UsesUnstableName(AArgument: TSyntaxNode): Boolean;
    function IsUnstableName(ANode: TSyntaxNode): Boolean;
    procedure Substitute(AIndex: Integer; AArgument: TSyntaxNode; const AText: string;
      const AOccurrences: TArray<TSyntaxNode>);
    function HelperVariableIssue(AIndex: Integer; const AText: string; const AOccurrences: TArray<TSyntaxNode>): string;
    procedure RenameResult;
    procedure SortReplacements;
    procedure DeclareLocals;
    procedure DeclareVariable(const AName, AType: string);
    procedure AddBody;
    procedure AddStatement(ANode: TSyntaxNode);
    procedure AddGuard(AIndex: Integer);
    function GuardWithValue(const ACondition: string; const ARest: TArray<string>): string;
    function PositiveCondition(const ACondition: string): string;
    function BlockOf(const ALines: TArray<string>): string;
    procedure AddCallEdits;
    function StatementText(const AIndent: string): string;
    procedure AddExpressionEdits(const AIndent: string);
    procedure AddSectionEdits;
    { Text }
    procedure Replace(AStart, AFinish: Integer; const AText: string);
    function Unique(const ABase: string): string;
    function Normalized(AStatement: TSyntaxNode): string;
    function RenderNode(ANode: TSyntaxNode): string;
  end;

{ Freie Hilfen }

/// <summary>Text AStart..AFinish von AText mit den (sortierten) Ersetzungen darin.</summary>
function Render(const AText: string; AReplacements: TList<TReplacement>; AStart, AFinish: Integer): string;
var
  mPosition: Integer;
  mReplacement: TReplacement;
begin
  Result := '';
  mPosition := AStart;
  for mReplacement in AReplacements do
  begin
    if (mReplacement.Start >= mPosition) and (mReplacement.Finish <= AFinish) then
    begin
      Result := Result + Copy(AText, mPosition + 1, mReplacement.Start - mPosition) + mReplacement.Text;
      mPosition := mReplacement.Finish;
    end;
  end;
  Result := Result + Copy(AText, mPosition + 1, AFinish - mPosition);
end;

/// <summary>Bedeutet der Typname ATypeNode (TypeReference) am Aufruf (AOffset in ACaller) etwas anderes als in
/// der Methode?</summary>
function DiffersAtCall(ATypeNode: TSyntaxNode; const ALookup: TInlineLookup; const ACallee, ACaller: TInlineSource;
  AOffset: Integer): Boolean;
var
  mName: string;
  mInCallee, mInCaller: TInlineMeaning;
begin
  mName := ATypeNode.Name;
  if Pos('<', mName) > 0 then
  begin
    mName := Copy(mName, 1, Pos('<', mName) - 1);
  end;
  Result := False;
  mInCallee := TInlineSyntax.Meaning(ALookup, ACallee, mName.Split(['.']), ATypeNode.StartOffset);
  if mInCallee.Found then
  begin
    mInCaller := TInlineSyntax.Meaning(ALookup, ACaller, mName.Split(['.']), AOffset);
    Result := not mInCaller.Found or (mInCaller.Key <> mInCallee.Key);
  end;
end;

/// <summary>Erster Typname in ATypeNode (samt ATypeNode), der am Aufruf etwas anderes bedeutet; nil ohne.</summary>
function ForeignType(ATypeNode: TSyntaxNode; const ALookup: TInlineLookup; const ACallee, ACaller: TInlineSource;
  AOffset: Integer): TSyntaxNode;
var
  mLookup: TInlineLookup;
  mCallee, mCaller: TInlineSource;
  mOffset: Integer;
begin
  // Search statt Rekursion; die Kopien fängt die anonyme Methode ein.
  mLookup := ALookup;
  mCallee := ACallee;
  mCaller := ACaller;
  mOffset := AOffset;
  Result := ATypeNode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate.Kind = TSyntaxKind.TypeReference) and DiffersAtCall(ACandidate, mLookup, mCallee, mCaller,
        mOffset) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

/// <summary>Beendet das Token die Namen einer Inline-Deklaration bzw. eines for var?</summary>
function EndsDeclNames(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(':') or AToken.IsSymbol(':=') or AToken.IsSymbol('=') or AToken.IsKeyword('in');
end;

function ExitValueOf(AExit: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (AExit.ChildCount > 0) and (AExit[0].Kind = TSyntaxKind.Call) and (AExit[0].ChildCount > 1) then
  begin
    Result := AExit[0][1];
  end;
end;

{ TMethodInliner: Rahmen }

class function TMethodInliner.Create(const ACaller: TInlineSource; const ACallee: TInlineCallee;
  const AOptions: TInlineOptions): TMethodInliner;
begin
  Result := Default(TMethodInliner);
  Result.Caller := ACaller;
  Result.Callee := ACallee.Source;
  Result.Routine := ACallee.Routine;
  Result.Options := AOptions;
  Result.GuardIndex := -1;
  Result.Replacements := TList<TReplacement>.Create;
  Result.Taken := TDictionary<string, Boolean>.Create;
end;

procedure TMethodInliner.Release;
begin
  FreeAndNil(Taken);
  FreeAndNil(Replacements);
end;

function TMethodInliner.Execute(const APosition: TTextPosition): string;
begin
  Result := StartIssue(APosition);
  if Result = '' then
  begin
    Result := CalleeIssue;
  end;
  if Result = '' then
  begin
    Result := CallerIssue;
  end;
  if Result = '' then
  begin
    Result := ParametersIssue;
  end;
  if Result = '' then
  begin
    Result := FlowIssue;
  end;
  if Result = '' then
  begin
    Result := ExitIssue;
  end;
  if Result = '' then
  begin
    Result := RewriteIssue;
  end;
end;

function TMethodInliner.Action: TCodeAction;
begin
  Result := Default(TCodeAction);
  if IsMethod then
  begin
    Result.Title := Format('Methode %s einbetten', [ShortName]);
  end
  else
  begin
    Result.Title := Format('Routine %s einbetten', [ShortName]);
  end;
  Result.Kind := InlineKind;
  Result.Edits := Edits;
end;

{ TMethodInliner: Prüfungen }

function TMethodInliner.StartIssue(const APosition: TTextPosition): string;
begin
  Result := '';
  if (Caller.Tree = nil) or (Callee.Tree = nil) or (Routine = nil) then
  begin
    Result := 'kein Syntaxbaum';
  end
  else if not TInlineSyntax.CallAt(Caller.Tree, Caller.Text, APosition, Call) then
  begin
    Result := 'kein Aufruf';
  end
  else
  begin
    CalleeTokens := Callee.Tree.Tokens;
    CallerTokens := Caller.Tree.Tokens;
  end;
end;

function TMethodInliner.CalleeIssue: string;
begin
  Result := KindIssue;
  if Result = '' then
  begin
    ReadNames;
    Result := NameIssue;
  end;
  if Result = '' then
  begin
    ReadHeader;
    Result := BodyIssue;
  end;
end;

function TMethodInliner.KindIssue: string;
var
  mKeyword: string;
begin
  Result := '';
  mKeyword := TInlineSyntax.RoutineKeyword(CalleeTokens, Routine);
  if (mKeyword = 'constructor') or (mKeyword = 'destructor') then
  begin
    Result := 'Konstruktoren und Destruktoren';
  end
  else if Pos('<', Routine.Name) > 0 then
  begin
    Result := 'generische Methode';
  end;
end;

procedure TMethodInliner.ReadNames;
begin
  ShortName := Routine.Name;
  CalleeClass := '';
  if ShortName.LastIndexOf('.') > 0 then
  begin
    CalleeClass := ShortName.Substring(0, ShortName.LastIndexOf('.'));
    ShortName := ShortName.Substring(ShortName.LastIndexOf('.') + 1);
  end;
  IsMethod := (CalleeClass <> '') and (Routine.Parent <> nil) and (Routine.Parent.Kind <> TSyntaxKind.RoutineDecl);
end;

function TMethodInliner.NameIssue: string;
begin
  Result := '';
  if not SameText(ShortName, Call.Name) then
  begin
    Result := 'der Rumpf gehört zu einer anderen Routine';
  end
  else
  begin
    CalleeBody := TRoutineBody.BodyOf(Routine);
    if CalleeBody = nil then
    begin
      Result := 'kein Rumpf';
    end;
  end;
end;

procedure TMethodInliner.ReadHeader;
begin
  Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
  ReturnType := nil;
  if Header <> nil then
  begin
    ReturnType := Header.FindChild(TSyntaxKind.TypeReference);
  end;
  IsFunction := ReturnType <> nil;
  ResultType := '';
  if IsFunction then
  begin
    ResultType := TRoutineBody.TextOf(Callee.Text, ReturnType);
  end;
end;

function TMethodInliner.BodyIssue: string;
begin
  Result := NestedIssue;
  if Result = '' then
  begin
    Result := ForbiddenIssue;
  end;
  if (Result = '') and CallsItself then
  begin
    Result := 'rekursiv';
  end;
end;

function TMethodInliner.NestedIssue: string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := 0;
  while (Result = '') and (mIndex < Routine.ChildCount) do
  begin
    case Routine[mIndex].Kind of
      TSyntaxKind.RoutineDecl, TSyntaxKind.TypeSection:
        Result := 'verschachtelte Routinen oder lokale Typen';
      TSyntaxKind.LabelSection:
        Result := 'Marken';
    end;
    Inc(mIndex);
  end;
end;

function TMethodInliner.ForbiddenIssue: string;
begin
  Result := '';
  if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.AsmBlock) then
  begin
    Result := 'asm';
  end
  else if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.InheritedExpr) then
  begin
    Result := 'inherited';
  end
  else if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.GotoStatement) or
    TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.LabeledStatement) then
  begin
    Result := 'goto';
  end
  else if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.WithStatement) then
  begin
    Result := 'with';
  end
  else if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.AnonymousMethod) then
  begin
    Result := 'anonyme Methode im Rumpf';
  end;
end;

/// <summary>Ruft der Rumpf die Methode selbst auf, als Name oder als Mitglied?</summary>
function TMethodInliner.CallsItself: Boolean;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Result := TInlineSyntax.UsesName(CalleeBody, ShortName);
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.MemberAccess, mNodes);
    for mNode in mNodes do
    begin
      if SameText(mNode.Name, ShortName) then
      begin
        Result := True;
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

function TMethodInliner.CallerIssue: string;
begin
  Result := '';
  CallerRoutine := TRoutineBody.RoutineAt(Caller.Tree, Call.NameOffset);
  if (Caller.Tree = Callee.Tree) and (CallerRoutine = Routine) then
  begin
    Exit('rekursiv');
  end;
  CallerBody := TRoutineBody.BodyOf(CallerRoutine);
  CallerClass := '';
  if CallerRoutine.Name.LastIndexOf('.') > 0 then
  begin
    CallerClass := CallerRoutine.Name.Substring(0, CallerRoutine.Name.LastIndexOf('.'));
  end;
  Result := ReceiverIssue;
  if Result = '' then
  begin
    Result := PlaceIssue;
  end;
  if Result = '' then
  begin
    Result := HostIssue;
  end;
end;

function TMethodInliner.ReceiverIssue: string;
begin
  Result := '';
  ReceiverText := '';
  if IsMethod and (Call.Receiver <> nil) then
  begin
    if not TInlineSyntax.IsSimpleChain(Call.Receiver) then
    begin
      Result := 'der Empfänger ist kein einfacher Name';
    end
    else if not SameText(TRoutineBody.TextOf(Caller.Text, Call.Receiver), 'Self') then
    begin
      ReceiverText := TRoutineBody.TextOf(Caller.Text, Call.Receiver);
    end;
  end
  else if IsMethod and (CallerClass = '') then
  begin
    Result := 'Methode ohne Empfänger';
  end;
end;

function TMethodInliner.PlaceIssue: string;
begin
  Result := '';
  if TInlineSyntax.Inside(Call.Node, TSyntaxKind.WithStatement, CallerBody) then
  begin
    Result := 'der Aufruf steht in einem with-Rumpf';
  end
  else if not Options.InlineVar and TInlineSyntax.Inside(Call.Node, TSyntaxKind.AnonymousMethod, CallerBody) then
  begin
    Result := 'der Aufruf steht in einer anonymen Methode';
  end;
end;

function TMethodInliner.HostIssue: string;
begin
  Result := '';
  Host := Call.Statement;
  if Host <> nil then
  begin
    Exit;
  end;
  if not IsFunction then
  begin
    Exit('Prozedur im Ausdruck');
  end;
  Host := TRoutineBody.HostStatement(Call.Node, CallerBody);
  if Host = nil then
  begin
    Result := 'an dieser Stelle nicht einbettbar';
  end
  else if CallsBefore then
  begin
    // Der Rumpf liefe vor allem, was in der Anweisung davor steht.
    Result := 'die Reihenfolge der Aufrufe änderte sich';
  end;
end;

/// <summary>Steht in der Anweisung vor dem Aufruf ein Aufruf mit Seiteneffekten oder inherited?</summary>
function TMethodInliner.CallsBefore: Boolean;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Result := False;
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Host, TSyntaxKind.Call, mNodes);
    TRoutineLocals.CollectKind(Host, TSyntaxKind.InheritedExpr, mNodes);
    for mNode in mNodes do
    begin
      if (mNode.EndOffset <= Call.Node.StartOffset) and ((mNode.Kind = TSyntaxKind.InheritedExpr) or
        not TInlineSyntax.CallIsPure(mNode, Caller, Options.Lookup)) then
      begin
        Result := True;
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

function TMethodInliner.ParametersIssue: string;
var
  mIndex: Integer;
begin
  Result := '';
  Parameters := ParametersOf;
  if Length(Call.Arguments) > Length(Parameters) then
  begin
    Result := 'zu viele Argumente';
  end;
  for mIndex := Length(Call.Arguments) to High(Parameters) do
  begin
    if (Result = '') and (Parameters[mIndex].DefaultValue = nil) then
    begin
      Result := 'zu wenige Argumente';
    end;
  end;
end;

function TMethodInliner.ParametersOf: TArray<TParameterInfo>;
var
  mList: TSyntaxNode;
  mIndex: Integer;
  mName: string;
begin
  Result := nil;
  mList := nil;
  if Header <> nil then
  begin
    mList := Header.FindChild(TSyntaxKind.Parameters);
  end;
  if mList = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mList.ChildCount - 1 do
  begin
    for mName in mList[mIndex].Name.Split([',']) do
    begin
      Result := Result + [ParameterOf(mList[mIndex], Trim(mName))];
    end;
  end;
end;

function TMethodInliner.ParameterOf(ADecl: TSyntaxNode; const AName: string): TParameterInfo;
begin
  Result := Default(TParameterInfo);
  Result.Name := AName;
  Result.Modifier := ADecl.Modifier;
  if (ADecl.ChildCount > 0) and (ADecl[0].Kind in TRoutineLocals.TypeKinds) then
  begin
    Result.TypeNode := ADecl[0];
    Result.TypeText := TRoutineBody.TextOf(Callee.Text, Result.TypeNode);
    if ADecl.ChildCount > 1 then
    begin
      Result.DefaultValue := ADecl[ADecl.ChildCount - 1];
    end;
  end;
end;

function TMethodInliner.FlowIssue: string;
begin
  Locals := TRoutineLocals.Collect(Callee.Text, Callee.Tree, Routine);
  CallerLocals := TRoutineLocals.Collect(Caller.Text, Caller.Tree, CallerRoutine);
  CalleeFlow := TFlowSignatures.FromTree(Callee.Tree.Root);
  Result := GraphIssue;
  // Result-Zuweisungen in Schleifen lassen sich nicht in eine einzelne Ersetzung übersetzen.
  if (Result = '') and IsFunction and ResultSetInLoop then
  begin
    Result := 'Result wird in einer Schleife gesetzt';
  end;
end;

function TMethodInliner.GraphIssue: string;
var
  mGraph: TControlFlowGraph;
begin
  Result := '';
  mGraph := TControlFlowGraph.Build(Routine, CalleeFlow);
  try
    if not mGraph.Complete then
    begin
      Result := 'Syntaxfehler in der Methode';
    end
    else if IsFunction and (mGraph.MayReadBeforeWrite('Result') <> TFlowAnswer.No) then
    begin
      Result := 'Result wird vor dem Setzen gelesen';
    end;
  finally
    mGraph.Free;
  end;
end;

function TMethodInliner.ResultSetInLoop: Boolean;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Result := False;
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.Identifier, mNodes);
    for mNode in mNodes do
    begin
      if SameText(mNode.Name, 'Result') and (TRoutineLocals.AccessOf(mNode, CalleeFlow) <> TLocalAccess.Read) and
        TInlineSyntax.InLoopWithout(mNode, CalleeBody, CalleeBody) then
      begin
        Result := True;
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

/// <summary>Exit: höchstens eins, als letzte Anweisung oder als "if … then Exit" auf oberster Ebene.</summary>
function TMethodInliner.ExitIssue: string;
begin
  CollectStatements;
  Result := FindExit;
  if (Result = '') and (ExitStatement <> nil) then
  begin
    Result := ExitPlaceIssue;
  end;
  if Result = '' then
  begin
    FindSimpleExpression;
  end;
end;

procedure TMethodInliner.CollectStatements;
var
  mIndex: Integer;
begin
  Statements := nil;
  for mIndex := 0 to CalleeBody.ChildCount - 1 do
  begin
    if CalleeBody[mIndex].Kind <> TSyntaxKind.EmptyStatement then
    begin
      Statements := Statements + [CalleeBody[mIndex]];
    end;
  end;
end;

function TMethodInliner.FindExit: string;
var
  mExits: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Result := '';
  ExitMode := TExitMode.NoExit;
  ExitStatement := nil;
  mExits := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.CallStatement, mExits);
    for mNode in mExits do
    begin
      if SameText(mNode.Name, 'Exit') then
      begin
        if ExitStatement <> nil then
        begin
          Result := 'mehrere Exit';
        end;
        ExitStatement := mNode;
      end;
    end;
  finally
    mExits.Free;
  end;
end;

function TMethodInliner.ExitPlaceIssue: string;
begin
  Result := '';
  ExitValue := ExitValueOf(ExitStatement);
  if (ExitStatement.Parent = CalleeBody) and (Statements <> nil) and
    (Statements[High(Statements)] = ExitStatement) then
  begin
    ExitMode := TExitMode.LastExit;
  end
  else if IsGuard(ExitStatement.Parent) then
  begin
    ExitMode := TExitMode.GuardExit;
    Guard := ExitStatement.Parent;
    GuardIndex := StatementIndex(Guard);
  end
  else
  begin
    Result := 'Exit mitten im Rumpf';
  end;
end;

/// <summary>Ist ANode ein "if … then Exit" ohne else auf oberster Ebene?</summary>
function TMethodInliner.IsGuard(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.IfStatement) and (ANode.Parent = CalleeBody) and (ANode.ChildCount = 2) and
    (ANode[1] = ExitStatement);
end;

function TMethodInliner.StatementIndex(ANode: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(Statements) do
  begin
    if Statements[mIndex] = ANode then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Einfache Form: nur "Result := E" bzw. "Exit(E)" ersetzt den Aufruf direkt.</summary>
procedure TMethodInliner.FindSimpleExpression;
var
  mNode: TSyntaxNode;
begin
  SimpleExpression := nil;
  if not IsFunction or (Call.Statement <> nil) or (Length(Statements) <> 1) or
    (ExitMode = TExitMode.GuardExit) then
  begin
    Exit;
  end;
  mNode := Statements[0];
  if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode[0].Kind = TSyntaxKind.Identifier) and
    SameText(mNode[0].Name, 'Result') then
  begin
    SimpleExpression := mNode[1];
  end
  else if (ExitMode = TExitMode.LastExit) and (ExitValue <> nil) then
  begin
    SimpleExpression := ExitValue;
  end;
  if HasOwnLocals or ((SimpleExpression <> nil) and TInlineSyntax.UsesName(SimpleExpression, 'Result')) then
  begin
    SimpleExpression := nil;
  end;
end;

/// <summary>Hat die Methode lokale Namen außer Parametern?</summary>
function TMethodInliner.HasOwnLocals: Boolean;
var
  mLocal: TLocal;
begin
  Result := False;
  for mLocal in Locals do
  begin
    if mLocal.Kind <> TLocalKind.Parameter then
    begin
      Result := True;
    end;
  end;
end;

{ TMethodInliner: Umformung }

function TMethodInliner.RewriteIssue: string;
begin
  LineBreak := TTextLines.LineBreakOf(Caller.Text);
  IndentUnit := TRoutineBody.IndentUnit(Options.Style);
  Edits := nil;
  CollectTaken;
  Mutates := False;
  Result := ForeignNamesIssue;
  if Result = '' then
  begin
    NoteMutations;
    Result := TypesIssue;
  end;
  if Result = '' then
  begin
    RenameLocals;
    Result := ArgumentsIssue;
  end;
  if Result = '' then
  begin
    RenameResult;
    SortReplacements;
    DeclareLocals;
    AddBody;
    AddCallEdits;
    AddSectionEdits;
  end;
end;

/// <summary>Namen der umgebenden Routine (samt äußeren Routinen) sind vergeben.</summary>
procedure TMethodInliner.CollectTaken;
var
  mOuter: TSyntaxNode;
  mIndex: Integer;
begin
  mOuter := CallerRoutine;
  while (mOuter.Parent <> nil) and (mOuter.Parent.Kind = TSyntaxKind.RoutineDecl) do
  begin
    mOuter := mOuter.Parent;
  end;
  for mIndex := TRoutineBody.TokenAt(CallerTokens, mOuter.StartOffset) to High(CallerTokens) do
  begin
    if CallerTokens[mIndex].Offset >= mOuter.EndOffset then
    begin
      Break;
    end;
    if CallerTokens[mIndex].Kind = TPascalTokenKind.Identifier then
    begin
      Taken.AddOrSetValue(LowerCase(CallerTokens[mIndex].Text), True);
    end;
  end;
end;

/// <summary>Bezeichner der Methode außer im Kopf.</summary>
procedure TMethodInliner.CollectOwnIdentifiers(AList: TList<TSyntaxNode>);
var
  mIndex: Integer;
begin
  for mIndex := 0 to Routine.ChildCount - 1 do
  begin
    if Routine[mIndex].Kind <> TSyntaxKind.RoutineHeader then
    begin
      TRoutineLocals.CollectKind(Routine[mIndex], TSyntaxKind.Identifier, AList);
    end;
  end;
end;

/// <summary>Lokaler Name der Methode für ANode; im var- und const-Abschnitt gelten auch ihre Konstanten.</summary>
function TMethodInliner.LocalIndexOf(ANode: TSyntaxNode): Integer;
var
  mConstant: Integer;
begin
  Result := TRoutineLocals.IndexOf(Locals, ANode.Name, ANode.StartOffset);
  if (Result < 0) and (ANode.StartOffset < CalleeBody.StartOffset) then
  begin
    mConstant := ConstantIndex(ANode.Name);
    if mConstant >= 0 then
    begin
      Result := mConstant;
    end;
  end;
end;

function TMethodInliner.ConstantIndex(const AName: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(Locals) do
  begin
    if (Locals[mIndex].Kind = TLocalKind.Constant) and SameText(Locals[mIndex].Name, AName) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Fremde Namen der Methode: gleiche Bedeutung am Aufruf, Mitglieder mit Empfänger.</summary>
function TMethodInliner.ForeignNamesIssue: string;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Result := '';
  mNodes := TList<TSyntaxNode>.Create;
  try
    CollectOwnIdentifiers(mNodes);
    for mNode in mNodes do
    begin
      if Result = '' then
      begin
        Result := ForeignNameIssue(mNode);
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

function TMethodInliner.ForeignNameIssue(ANode: TSyntaxNode): string;
var
  mLocal: Integer;
begin
  Result := '';
  if SameText(ANode.Name, 'Exit') and TInlineSyntax.IsCallee(ANode) then
  begin
    Exit;
  end;
  mLocal := LocalIndexOf(ANode);
  if mLocal >= 0 then
  begin
    NoteParameterWrite(ANode, mLocal);
  end
  else if not (IsFunction and SameText(ANode.Name, 'Result')) then
  begin
    Result := OutsideNameIssue(ANode);
  end;
end;

procedure TMethodInliner.NoteParameterWrite(ANode: TSyntaxNode; AIndex: Integer);
begin
  if (Locals[AIndex].Kind = TLocalKind.Parameter) and
    (Locals[AIndex].Decl.Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam]) and
    (TRoutineLocals.AccessOf(ANode, CalleeFlow) <> TLocalAccess.Read) then
  begin
    Mutates := True;
  end;
end;

/// <summary>Name außerhalb der Methode: Self, Mitglied oder Name der Unit.</summary>
function TMethodInliner.OutsideNameIssue(ANode: TSyntaxNode): string;
var
  mFound: TInlineMeaning;
begin
  Result := '';
  if SameText(ANode.Name, 'Self') then
  begin
    if ReceiverText <> '' then
    begin
      Replace(ANode.StartOffset, ANode.EndOffset, ReceiverText);
    end;
    Exit;
  end;
  if (ANode.Parent.Kind = TSyntaxKind.AssignStatement) and (ANode.Parent[0] = ANode) then
  begin
    Mutates := True;
  end;
  Taken.AddOrSetValue(LowerCase(ANode.Name), True);
  if not Assigned(Options.Lookup) then
  begin
    Exit;
  end;
  mFound := TInlineSyntax.Meaning(Options.Lookup, Callee, [ANode.Name], ANode.StartOffset);
  if not mFound.Found then
  begin
    Exit(ANode.Name + ' unbekannt');
  end;
  if mFound.IsRoutine then
  begin
    Mutates := True;
  end;
  Result := MeaningIssue(ANode, mFound);
end;

function TMethodInliner.MeaningIssue(ANode: TSyntaxNode; const AFound: TInlineMeaning): string;
var
  mAtCall: TInlineMeaning;
begin
  Result := '';
  mAtCall := TInlineSyntax.Meaning(Options.Lookup, Caller, [ANode.Name], Call.NameOffset);
  if AFound.IsMember and IsMethod then
  begin
    Result := MemberIssue(ANode, AFound, mAtCall);
  end
  else if not mAtCall.Found or (mAtCall.Key <> AFound.Key) then
  begin
    Result := ANode.Name + ' bedeutet am Aufruf etwas anderes';
  end;
end;

function TMethodInliner.MemberIssue(ANode: TSyntaxNode; const AFound, AAtCall: TInlineMeaning): string;
begin
  Result := '';
  if ReceiverText <> '' then
  begin
    if not Visible(AFound) then
    begin
      Result := ANode.Name + ' ist am Aufruf nicht sichtbar';
    end
    else
    begin
      Replace(ANode.StartOffset, ANode.EndOffset, ReceiverText + '.' + ANode.Name);
    end;
  end
  else if AAtCall.Key <> AFound.Key then
  begin
    Replace(ANode.StartOffset, ANode.EndOffset, 'Self.' + ANode.Name);
  end;
end;

function TMethodInliner.Visible(const AMeaning: TInlineMeaning): Boolean;
begin
  // Private Mitglieder nur in der eigenen Klasse, auch wenn Delphi sie in der ganzen Unit zuließe.
  case AMeaning.Visibility of
    TInlineVisibility.StrictPrivate, TInlineVisibility.StrictProtected, TInlineVisibility.Private:
      Result := SameText(CallerClass, AMeaning.Container) and SameText(Caller.FileName, Callee.FileName);
    TInlineVisibility.Protected:
      Result := SameText(Caller.FileName, Callee.FileName);
  else
    Result := True;
  end;
end;

/// <summary>Aufrufe mit Seiteneffekten und Zuweisungen an mehr als einen Namen ändern Speicher.</summary>
procedure TMethodInliner.NoteMutations;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.Call, mNodes);
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.CallStatement, mNodes);
    for mNode in mNodes do
    begin
      if not SameText(mNode.Name, 'Exit') and ((mNode.Kind = TSyntaxKind.CallStatement) or
        not TInlineSyntax.CallIsPure(mNode, Callee, Options.Lookup)) then
      begin
        Mutates := True;
      end;
    end;
    mNodes.Clear;
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.AssignStatement, mNodes);
    for mNode in mNodes do
    begin
      if mNode[0].Kind <> TSyntaxKind.Identifier then
      begin
        Mutates := True;
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

/// <summary>Bedeutet der Typ am Aufruf dasselbe wie in der Methode?</summary>
function TMethodInliner.SameType(ATypeNode: TSyntaxNode): Boolean;
begin
  Result := (ATypeNode = nil) or not Assigned(Options.Lookup) or
    (ForeignType(ATypeNode, Options.Lookup, Callee, Caller, Call.NameOffset) = nil);
end;

/// <summary>Typen der neuen Deklarationen.</summary>
function TMethodInliner.TypesIssue: string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(Locals) do
  begin
    if (Result = '') and (Locals[mIndex].Kind <> TLocalKind.Parameter) and not SameType(Locals[mIndex].Decl) then
    begin
      Result := 'ein Typ bedeutet am Aufruf etwas anderes';
    end;
  end;
  if (Result = '') and not SameType(ReturnType) then
  begin
    Result := 'der Ergebnistyp bedeutet am Aufruf etwas anderes';
  end;
end;

/// <summary>Lokale Namen der Methode: eindeutig gegen die Routine am Aufruf.</summary>
procedure TMethodInliner.RenameLocals;
var
  mIndex, mLocal: Integer;
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  SetLength(NewNames, Length(Locals));
  for mIndex := 0 to High(Locals) do
  begin
    if Locals[mIndex].Kind <> TLocalKind.Parameter then
    begin
      NewNames[mIndex] := Unique(Locals[mIndex].Name);
    end;
  end;
  mNodes := TList<TSyntaxNode>.Create;
  try
    CollectOwnIdentifiers(mNodes);
    for mNode in mNodes do
    begin
      mLocal := LocalIndexOf(mNode);
      if (mLocal >= 0) and (Locals[mLocal].Kind <> TLocalKind.Parameter) then
      begin
        Replace(mNode.StartOffset, mNode.EndOffset, NewNames[mLocal]);
      end;
    end;
  finally
    mNodes.Free;
  end;
  RenameDeclarations;
end;

/// <summary>Namen in Inline-Deklarationen, for var und const-Einträgen.</summary>
procedure TMethodInliner.RenameDeclarations;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Locals) do
  begin
    if Locals[mIndex].Kind in [TLocalKind.InlineVariable, TLocalKind.LoopVariable] then
    begin
      RenameInDeclaration(mIndex);
    end
    else if Locals[mIndex].Kind = TLocalKind.Constant then
    begin
      ReplaceToken(TInlineSyntax.NextSignificant(CalleeTokens, TRoutineBody.TokenAt(CalleeTokens,
        Locals[mIndex].Decl.StartOffset)), NewNames[mIndex]);
    end;
  end;
end;

procedure TMethodInliner.RenameInDeclaration(AIndex: Integer);
var
  mToken: Integer;
begin
  mToken := TRoutineBody.TokenAt(CalleeTokens, Locals[AIndex].Decl.StartOffset);
  while (mToken <= High(CalleeTokens)) and (CalleeTokens[mToken].Offset < Locals[AIndex].Decl.EndOffset) and
    not EndsDeclNames(CalleeTokens[mToken]) do
  begin
    if (CalleeTokens[mToken].Kind = TPascalTokenKind.Identifier) and
      SameText(CalleeTokens[mToken].Text, Locals[AIndex].Name) then
    begin
      ReplaceToken(mToken, NewNames[AIndex]);
    end;
    Inc(mToken);
  end;
end;

procedure TMethodInliner.ReplaceToken(AIndex: Integer; const AText: string);
begin
  Replace(CalleeTokens[AIndex].Offset, CalleeTokens[AIndex].Offset + Length(CalleeTokens[AIndex].Text), AText);
end;

/// <summary>Parameter: Argument direkt, sonst Hilfsvariable.</summary>
function TMethodInliner.ArgumentsIssue: string;
var
  mIndex: Integer;
begin
  Lines := nil;
  VarEntries := nil;
  ConstEntries := nil;
  SetLength(ParameterText, Length(Parameters));
  CollectArgumentNames;
  Result := '';
  mIndex := 0;
  while (Result = '') and (mIndex <= High(Parameters)) do
  begin
    Result := ArgumentIssue(mIndex);
    Inc(mIndex);
  end;
end;

procedure TMethodInliner.CollectArgumentNames;
var
  mIndex: Integer;
begin
  ArgumentNames := nil;
  for mIndex := 0 to High(Parameters) do
  begin
    if (Parameters[mIndex].Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam]) and
      (mIndex <= High(Call.Arguments)) and TInlineSyntax.IsSimpleChain(Call.Arguments[mIndex]) then
    begin
      ArgumentNames := ArgumentNames + [TInlineSyntax.ChainNames(Call.Arguments[mIndex])[0]];
    end;
  end;
end;

function TMethodInliner.ArgumentIssue(AIndex: Integer): string;
var
  mArgument: TSyntaxNode;
  mText: string;
  mOccurrences: TArray<TSyntaxNode>;
begin
  Result := ArgumentOf(AIndex, mArgument, mText);
  if Result <> '' then
  begin
    Exit;
  end;
  mOccurrences := ParameterOccurrences(Parameters[AIndex].Name);
  if Parameters[AIndex].Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam] then
  begin
    Result := ReferenceArgumentIssue(AIndex, mArgument, mText, mOccurrences);
  end
  else if CanSubstitute(AIndex, mArgument, mOccurrences) then
  begin
    Substitute(AIndex, mArgument, mText, mOccurrences);
  end
  else
  begin
    Result := HelperVariableIssue(AIndex, mText, mOccurrences);
  end;
end;

/// <summary>Argument am Aufruf oder Vorgabewert des Parameters AIndex mit seinem Text.</summary>
function TMethodInliner.ArgumentOf(AIndex: Integer; out AArgument: TSyntaxNode; out AText: string): string;
begin
  Result := '';
  if AIndex <= High(Call.Arguments) then
  begin
    AArgument := Call.Arguments[AIndex];
    AText := TTextLines.NormalizeLineBreaks(TRoutineBody.TextOf(Caller.Text, AArgument), LineBreak);
  end
  else
  begin
    AArgument := Parameters[AIndex].DefaultValue;
    AText := TRoutineBody.TextOf(Callee.Text, AArgument);
    Result := DefaultValueIssue(AIndex);
  end;
end;

/// <summary>Vorgabewert: seine Namen müssen am Aufruf dasselbe bedeuten.</summary>
function TMethodInliner.DefaultValueIssue(AIndex: Integer): string;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mFound, mAtCall: TInlineMeaning;
begin
  Result := '';
  if not Assigned(Options.Lookup) then
  begin
    Exit;
  end;
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Parameters[AIndex].DefaultValue, TSyntaxKind.Identifier, mNodes);
    for mNode in mNodes do
    begin
      mFound := TInlineSyntax.Meaning(Options.Lookup, Callee, [mNode.Name], mNode.StartOffset);
      mAtCall := TInlineSyntax.Meaning(Options.Lookup, Caller, [mNode.Name], Call.NameOffset);
      if (Result = '') and (not mFound.Found or not mAtCall.Found or (mFound.Key <> mAtCall.Key)) then
      begin
        Result := 'der Vorgabewert von ' + Parameters[AIndex].Name + ' bedeutet am Aufruf etwas anderes';
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

/// <summary>Stellen im Rumpf, an denen der Parameter AName steht.</summary>
function TMethodInliner.ParameterOccurrences(const AName: string): TArray<TSyntaxNode>;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mLocal: Integer;
begin
  Result := nil;
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.Identifier, mNodes);
    for mNode in mNodes do
    begin
      mLocal := TRoutineLocals.IndexOf(Locals, mNode.Name, mNode.StartOffset);
      if SameText(mNode.Name, AName) and (mLocal >= 0) and (Locals[mLocal].Kind = TLocalKind.Parameter) then
      begin
        Result := Result + [mNode];
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

/// <summary>var- und out-Parameter: Das Argument muss eine einfache Variable sein und ersetzt den Namen.</summary>
function TMethodInliner.ReferenceArgumentIssue(AIndex: Integer; AArgument: TSyntaxNode; const AText: string;
  const AOccurrences: TArray<TSyntaxNode>): string;
var
  mNode: TSyntaxNode;
begin
  Result := '';
  if (AIndex > High(Call.Arguments)) or not TRoutineBody.IsVariableChain(AArgument) or
    TRoutineLocals.HasKind(AArgument, TSyntaxKind.Call) then
  begin
    Exit('das Argument für ' + Parameters[AIndex].Name + ' ist keine einfache Variable');
  end;
  ParameterText[AIndex] := AText;
  for mNode in AOccurrences do
  begin
    Replace(mNode.StartOffset, mNode.EndOffset, AText);
  end;
end;

/// <summary>Darf das Argument direkt für den Parameter stehen?</summary>
function TMethodInliner.CanSubstitute(AIndex: Integer; AArgument: TSyntaxNode;
  const AOccurrences: TArray<TSyntaxNode>): Boolean;
var
  mWritten, mInLoop, mSimple: Boolean;
begin
  UsageOf(AOccurrences, mWritten, mInLoop);
  if Parameters[AIndex].Modifier in [TParameterModifier.ConstParam, TParameterModifier.ConstRefParam] then
  begin
    mWritten := False;
  end;
  mSimple := AArgument.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess,
    TSyntaxKind.ParenExpr];
  Result := not mWritten and IsStable(AIndex, AArgument) and (mSimple or
    ((Length(AOccurrences) <= 1) and not mInLoop));
end;

procedure TMethodInliner.UsageOf(const AOccurrences: TArray<TSyntaxNode>; out AWritten, AInLoop: Boolean);
var
  mNode: TSyntaxNode;
begin
  AWritten := False;
  AInLoop := False;
  for mNode in AOccurrences do
  begin
    if TRoutineLocals.AccessOf(mNode, CalleeFlow) <> TLocalAccess.Read then
    begin
      AWritten := True;
    end;
    if TInlineSyntax.InLoopWithout(mNode, CalleeBody, CalleeBody) then
    begin
      AInLoop := True;
    end;
  end;
end;

/// <summary>Stabil: Das Argument ändert sich während des Rumpfs nicht.</summary>
function TMethodInliner.IsStable(AIndex: Integer; AArgument: TSyntaxNode): Boolean;
var
  mPure: Boolean;
begin
  if AIndex <= High(Call.Arguments) then
  begin
    mPure := not TInlineSyntax.HasSideEffects(AArgument, Caller, Options.Lookup);
  end
  else
  begin
    mPure := not TInlineSyntax.HasSideEffects(AArgument, Callee, Options.Lookup);
  end;
  Result := mPure and ((AArgument.Kind = TSyntaxKind.Literal) or not Mutates);
  if mPure and not Result and (AIndex <= High(Call.Arguments)) then
  begin
    Result := not UsesUnstableName(AArgument) and not TRoutineLocals.HasKind(AArgument, TSyntaxKind.Dereference) and
      not TRoutineLocals.HasKind(AArgument, TSyntaxKind.MemberAccess) and
      not TRoutineLocals.HasKind(AArgument, TSyntaxKind.IndexAccess);
  end;
end;

function TMethodInliner.UsesUnstableName(AArgument: TSyntaxNode): Boolean;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Result := False;
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(AArgument, TSyntaxKind.Identifier, mNodes);
    for mNode in mNodes do
    begin
      if IsUnstableName(mNode) then
      begin
        Result := True;
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

/// <summary>Name, den der Rumpf ändern kann: kein lokaler Name am Aufruf und keine Konstante, oder Argument eines
/// var- bzw. out-Parameters.</summary>
function TMethodInliner.IsUnstableName(ANode: TSyntaxNode): Boolean;
begin
  Result := (not TInlineSyntax.IsCallee(ANode) and (TRoutineLocals.IndexOf(CallerLocals, ANode.Name,
    ANode.StartOffset) < 0) and not MatchText(ANode.Name, ConstantNames)) or
    (IndexText(ANode.Name, ArgumentNames) >= 0);
end;

procedure TMethodInliner.Substitute(AIndex: Integer; AArgument: TSyntaxNode; const AText: string;
  const AOccurrences: TArray<TSyntaxNode>);
var
  mNode: TSyntaxNode;
begin
  ParameterText[AIndex] := AText;
  for mNode in AOccurrences do
  begin
    Replace(mNode.StartOffset, mNode.EndOffset, TInlineSyntax.Parenthesized(AText, AArgument, mNode));
  end;
end;

function TMethodInliner.HelperVariableIssue(AIndex: Integer; const AText: string;
  const AOccurrences: TArray<TSyntaxNode>): string;
var
  mParameter: TParameterInfo;
  mNode: TSyntaxNode;
begin
  mParameter := Parameters[AIndex];
  if mParameter.TypeText = '' then
  begin
    Exit('untypisierter Parameter ' + mParameter.Name);
  end;
  if not SameType(mParameter.TypeNode) then
  begin
    Exit('der Typ von ' + mParameter.Name + ' bedeutet am Aufruf etwas anderes');
  end;
  Result := '';
  ParameterText[AIndex] := Unique(mParameter.Name);
  for mNode in AOccurrences do
  begin
    Replace(mNode.StartOffset, mNode.EndOffset, ParameterText[AIndex]);
  end;
  if Options.InlineVar then
  begin
    Lines := Lines + ['var ' + ParameterText[AIndex] + ': ' + mParameter.TypeText + ' := ' + AText];
  end
  else
  begin
    VarEntries := VarEntries + [ParameterText[AIndex] + ': ' + mParameter.TypeText + ';'];
    Lines := Lines + [ParameterText[AIndex] + ' := ' + AText];
  end;
end;

/// <summary>Ergebnis: Ohne einfache Form trägt eine Variable NameResult das Ergebnis.</summary>
procedure TMethodInliner.RenameResult;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  ResultName := '';
  if not IsFunction or (SimpleExpression <> nil) then
  begin
    Exit;
  end;
  ResultName := Unique(ShortName + InlineResultSuffix);
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.Identifier, mNodes);
    for mNode in mNodes do
    begin
      if SameText(mNode.Name, 'Result') then
      begin
        Replace(mNode.StartOffset, mNode.EndOffset, ResultName);
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

procedure TMethodInliner.SortReplacements;
begin
  Replacements.Sort(TComparer<TReplacement>.Construct(
    function(const A, B: TReplacement): Integer
    begin
      Result := A.Start - B.Start;
      if Result = 0 then
      begin
        Result := A.Finish - B.Finish;
      end;
    end));
end;

/// <summary>Lokale Variablen und Konstanten der Methode, dazu die Ergebnisvariable.</summary>
procedure TMethodInliner.DeclareLocals;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Locals) do
  begin
    case Locals[mIndex].Kind of
      TLocalKind.Variable:
        DeclareVariable(NewNames[mIndex], RenderNode(Locals[mIndex].Decl[0]));
      TLocalKind.Constant:
        ConstEntries := ConstEntries + [RenderNode(Locals[mIndex].Decl)];
    end;
  end;
  if ResultName <> '' then
  begin
    DeclareVariable(ResultName, ResultType);
  end;
end;

procedure TMethodInliner.DeclareVariable(const AName, AType: string);
begin
  if Options.InlineVar then
  begin
    Lines := Lines + ['var ' + AName + ': ' + AType];
  end
  else
  begin
    VarEntries := VarEntries + [AName + ': ' + AType + ';'];
  end;
end;

/// <summary>Anweisungen des Rumpfs; ab dem "if … then Exit" ein if mit dem Rest.</summary>
procedure TMethodInliner.AddBody;
var
  mIndex: Integer;
begin
  if SimpleExpression <> nil then
  begin
    Exit;
  end;
  for mIndex := 0 to High(Statements) do
  begin
    if (ExitMode = TExitMode.GuardExit) and (mIndex = GuardIndex) then
    begin
      AddGuard(mIndex);
      Break;
    end;
    AddStatement(Statements[mIndex]);
  end;
end;

procedure TMethodInliner.AddStatement(ANode: TSyntaxNode);
begin
  if (ExitMode <> TExitMode.LastExit) or (ANode <> ExitStatement) then
  begin
    Lines := Lines + [Normalized(ANode)];
  end
  else if (ExitValue <> nil) and (ResultName <> '') then
  begin
    Lines := Lines + [ResultName + ' := ' + RenderNode(ExitValue)];
  end;
end;

procedure TMethodInliner.AddGuard(AIndex: Integer);
var
  mRest: TArray<string>;
  mInner: Integer;
  mCondition: string;
begin
  mRest := nil;
  for mInner := AIndex + 1 to High(Statements) do
  begin
    mRest := mRest + [Normalized(Statements[mInner])];
  end;
  mCondition := RenderNode(Guard[0]);
  if (ExitValue <> nil) and (ResultName <> '') then
  begin
    Lines := Lines + [GuardWithValue(mCondition, mRest)];
  end
  else if mRest <> nil then
  begin
    Lines := Lines + ['if ' + PositiveCondition(mCondition) + ' then' + LineBreak + BlockOf(mRest)];
  end
  else if TInlineSyntax.HasSideEffects(Guard[0], Callee, Options.Lookup) then
  begin
    Lines := Lines + ['if ' + mCondition + ' then' + LineBreak + 'begin' + LineBreak + 'end'];
  end;
end;

function TMethodInliner.GuardWithValue(const ACondition: string; const ARest: TArray<string>): string;
begin
  Result := 'if ' + ACondition + ' then' + LineBreak + IndentUnit + ResultName + ' := ' + RenderNode(ExitValue);
  if ARest <> nil then
  begin
    Result := Result + LineBreak + 'else' + LineBreak + BlockOf(ARest);
  end;
end;

/// <summary>Bedingung, unter der der Rest läuft: die verneinte Bedingung des Exit.</summary>
function TMethodInliner.PositiveCondition(const ACondition: string): string;
begin
  if (Guard[0].Kind = TSyntaxKind.UnaryExpr) and SameText(Guard[0].Name, 'not') then
  begin
    Result := RenderNode(Guard[0][0]);
  end
  else
  begin
    Result := TInlineSyntax.Negated(ACondition, Guard[0]);
  end;
end;

function TMethodInliner.BlockOf(const ALines: TArray<string>): string;
begin
  Result := 'begin' + LineBreak + TInlineSyntax.JoinStatements(ALines, IndentUnit, LineBreak, True) + ';' +
    LineBreak + 'end';
end;

/// <summary>Bearbeitungen am Aufruf.</summary>
procedure TMethodInliner.AddCallEdits;
var
  mIndent: string;
begin
  mIndent := TTextLines.IndentOf(Caller.Text, Host.StartPos.Line);
  if Call.Statement <> nil then
  begin
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Host.StartPos, Host.EndPos), StatementText(mIndent))];
  end
  else
  begin
    AddExpressionEdits(mIndent);
  end;
end;

function TMethodInliner.StatementText(const AIndent: string): string;
begin
  if Lines = nil then
  begin
    Result := '';
  end
  else if TRoutineBody.InList(Host) then
  begin
    Result := TInlineSyntax.JoinStatements(Lines, AIndent, LineBreak, False);
  end
  else
  begin
    Result := 'begin' + LineBreak + TInlineSyntax.JoinStatements(Lines, AIndent + IndentUnit, LineBreak, True) +
      ';' + LineBreak + AIndent + 'end';
  end;
end;

procedure TMethodInliner.AddExpressionEdits(const AIndent: string);
var
  mReplacement, mText: string;
begin
  mReplacement := ResultName;
  if SimpleExpression <> nil then
  begin
    mReplacement := TInlineSyntax.Parenthesized(RenderNode(SimpleExpression), SimpleExpression, Call.Node);
  end;
  mText := '';
  if Lines <> nil then
  begin
    mText := TInlineSyntax.JoinStatements(Lines, AIndent, LineBreak, False) + ';' + LineBreak + AIndent;
  end;
  if Call.Node.StartOffset = Host.StartOffset then
  begin
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Call.Node.StartPos, Call.Node.EndPos),
      mText + mReplacement)];
  end
  else
  begin
    if mText <> '' then
    begin
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Host.StartPos, Host.StartPos), mText)];
    end;
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Call.Node.StartPos, Call.Node.EndPos), mReplacement)];
  end;
end;

procedure TMethodInliner.AddSectionEdits;
var
  mChange: TTextEdit;
begin
  if VarEntries <> nil then
  begin
    mChange := TInlineSyntax.SectionEdit(Caller.Text, CallerRoutine, False, VarEntries, Options.Style);
    Edits := Edits + [mChange];
  end;
  if ConstEntries <> nil then
  begin
    mChange := TInlineSyntax.SectionEdit(Caller.Text, CallerRoutine, True, ConstEntries, Options.Style);
    Edits := Edits + [mChange];
  end;
end;

{ TMethodInliner: Text }

procedure TMethodInliner.Replace(AStart, AFinish: Integer; const AText: string);
var
  mItem: TReplacement;
begin
  mItem.Start := AStart;
  mItem.Finish := AFinish;
  mItem.Text := AText;
  Replacements.Add(mItem);
end;

/// <summary>ABase bzw. ABase2, ABase3 …: der erste freie Name; danach vergeben.</summary>
function TMethodInliner.Unique(const ABase: string): string;
var
  mNumber: Integer;
begin
  Result := ABase;
  mNumber := 2;
  while Taken.ContainsKey(LowerCase(Result)) do
  begin
    Result := ABase + IntToStr(mNumber);
    Inc(mNumber);
  end;
  Taken.AddOrSetValue(LowerCase(Result), True);
end;

function TMethodInliner.Normalized(AStatement: TSyntaxNode): string;
begin
  Result := TRoutineBody.Reindent(Render(Callee.Text, Replacements, AStatement.StartOffset, AStatement.EndOffset),
    TTextLines.IndentOf(Callee.Text, AStatement.StartPos.Line), '', LineBreak);
end;

function TMethodInliner.RenderNode(ANode: TSyntaxNode): string;
begin
  Result := TTextLines.NormalizeLineBreaks(Render(Callee.Text, Replacements, ANode.StartOffset, ANode.EndOffset),
    LineBreak);
end;

{ TMethodInlining }

class function TMethodInlining.Run(const ACaller: TInlineSource; const APosition: TTextPosition;
  const ACallee: TInlineCallee; const AOptions: TInlineOptions; out AAction: TCodeAction;
  out AReason: string): Boolean;
var
  mInliner: TMethodInliner;
begin
  AAction := Default(TCodeAction);
  mInliner := TMethodInliner.Create(ACaller, ACallee, AOptions);
  try
    AReason := mInliner.Execute(APosition);
    Result := AReason = '';
    if Result then
    begin
      AAction := mInliner.Action;
    end;
  finally
    mInliner.Release;
  end;
end;

end.
