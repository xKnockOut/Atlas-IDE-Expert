unit Atlas.Common.Editing.Extract.Method;

// „Methode extrahieren“ (#50, Teil A) für Atlas.Common.Editing.Extract: Die markierten Anweisungen (vollständig,
// aus einer Anweisungsliste) werden zu einer neuen Methode der Klasse bzw. zu einer Routine vor der umgebenden.
// Die Datenflussanalyse im Rumpf entscheidet über die Parameter: nur gelesen → const, geschrieben und danach
// gelesen → var, bei unbedingtem ersten Schreiben out; geschrieben, aber danach nicht mehr gebraucht →
// Wertparameter bzw. lokale Variable; nur innen verwendet → lokale Variable der neuen Methode (aus dem alten
// var-Abschnitt entfernt). Lokale Konstanten werden mitkopiert. Liegt die Auswahl in einer Schleife, gelten
// Zugriffe in der Schleife vor der Auswahl als „danach“.
// Für gleiche Stellen (#2054) nimmt TMethodExtraction weitere Stellen derselben Routine entgegen, die später
// ebenfalls durch den Aufruf ersetzt werden: Ihre Vorkommen zählen nicht als Code, sondern als Aufruf mit den
// angenommenen Parameterarten. Der Plan (TMethodPlan) nennt Schlüssel, Parameter, Aufruf und die Edits, die
// lokale Variablen aus dem var-Abschnitt entfernen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.Extract.Shared;

type
  {$SCOPEDENUMS ON}
  /// <summary>Wie ein Name in die neue Methode kommt.</summary>
  TParameterMode = (None, Const_, Var_, Out_, Value, LocalVar, CopyConst);
  {$SCOPEDENUMS OFF}

  /// <summary>Ein Vorkommen eines lokalen Namens im Rumpf.</summary>
  TLocalOccurrence = record
    Node: TSyntaxNode;
    Local: Integer;
    Access: TLocalAccess;
  end;

  /// <summary>Was die Analyse über einen lokalen Namen weiß.</summary>
  TLocalUse = record
    ReadIn: Boolean;
    WriteIn: Boolean;
    /// <summary>Vor der Auswahl verwendet (Parameter immer).</summary>
    Before: Boolean;
    /// <summary>Nach der Auswahl verwendet, in einer Schleife auch davor in der Schleife.</summary>
    After: Boolean;
    /// <summary>Das erste Vorkommen in der Auswahl schreibt unbedingt.</summary>
    FirstWrite: Boolean;
    Seen: Boolean;
    FirstNode: TSyntaxNode;
    Mode: TParameterMode;
  end;

  /// <summary>Parameterart eines Namens der neuen Methode (#2054).</summary>
  TExtractParameter = record
    Name: string;
    Mode: TParameterMode;
  end;

  /// <summary>Anweisungsfolge als Offsets (Anfang, Ende ausgeschlossen).</summary>
  TExtractWindow = record
    Start: Integer;
    Finish: Integer;
    class function Create(AStart, AFinish: Integer): TExtractWindow; static;
  end;

  /// <summary>Weitere Stellen derselben Routine, die ebenfalls durch den Aufruf ersetzt werden (#2054).</summary>
  TExtractContext = record
    /// <summary>Ihre Vorkommen zählen nicht als Code.</summary>
    Others: TArray<TExtractWindow>;
    /// <summary>Stattdessen greift an jeder Stelle ein Aufruf mit diesen Parameterarten zu; nil: gar nicht.
    /// </summary>
    Assumed: TArray<TExtractParameter>;
  end;

  /// <summary>Ergebnis einer geplanten Extraktion (#2054).</summary>
  TMethodPlan = record
    /// <summary>Kopf, var- und const-Abschnitt der neuen Methode: gleicher Schlüssel, gleiche Methode.</summary>
    Key: string;
    Parameters: TArray<TExtractParameter>;
    /// <summary>Ersetzte Anweisungen und der Aufruf an ihrer Stelle.</summary>
    CallRange: TTextRange;
    CallText: string;
    /// <summary>Entfernt lokale Variablen, die nur noch die neue Methode braucht.</summary>
    LocalEdits: TArray<TTextEdit>;
    /// <summary>Umgebende Routine.</summary>
    Routine: TSyntaxNode;
  end;

  /// <summary>Plant „Methode extrahieren“ für eine Auswahl.</summary>
  TMethodExtraction = class
  private
    FContext: TExtractContext;
    FPlan: TMethodPlan;
    FText: string;
    FTree: TSyntaxTree;
    FOptions: TExtractOptions;
    FStart: Integer;
    FEnd: Integer;
    FRoutine: TSyntaxNode;
    FBody: TSyntaxNode;
    FStatements: TArray<TSyntaxNode>;
    FLocals: TArray<TRoutineLocal>;
    FOnlyNames: TArray<string>;
    FLookup: TFlowSignatureLookup;
    FLoopStart: Integer;
    FLoopEnd: Integer;
    FOccurrences: TList<TLocalOccurrence>;
    FUses: TArray<TLocalUse>;
    FOrder: TArray<Integer>;
    FRemoved: TArray<string>;
    FReason: string;
    /// <summary>Auswahl, Routine und oberste Anweisungen; prüft Sperren und Sprünge.</summary>
    function Prepare(const ARange: TTextRange): Boolean;
    /// <summary>Datenfluss und Parameterart je Name.</summary>
    function Analyze: Boolean;
    /// <summary>Schleife um die Auswahl: Zugriffe darin vor der Auswahl laufen auch danach.</summary>
    procedure FindLoop;
    function CollectOccurrences: Boolean;
    /// <summary>Liegt AOffset in einer der weiteren Stellen aus FContext?</summary>
    function InOther(AOffset: Integer): Boolean;
    /// <summary>Zugriff außerhalb der Auswahl an AStart..AEnd: davor bzw. danach.</summary>
    procedure MarkOutside(ALocal, AStart, AEnd: Integer);
    /// <summary>Weitere Stellen als Aufruf mit den angenommenen Parameterarten.</summary>
    procedure MarkAssumed;
    function Parameters: TArray<TExtractParameter>;
    /// <summary>False mit Grund, wenn ANode in der Auswahl auf Result oder nur in der Routine Sichtbares zeigt.
    /// </summary>
    function VisibleOutside(ANode: TSyntaxNode; ALocal: Integer): Boolean;
    /// <summary>Laufvariablen klassischer for-Schleifen werden geschrieben.</summary>
    procedure MarkForLoops;
    procedure MarkOccurrence(const AOccurrence: TLocalOccurrence);
    procedure MarkInside(const AOccurrence: TLocalOccurrence);
    function DeclaredInside(AIndex: Integer): Boolean;
    /// <summary>Lokale Variable, die nur noch die neue Methode braucht.</summary>
    function OnlyInside(AIndex: Integer): Boolean;
    function ChooseModes: Boolean;
    /// <summary>Anonyme Methoden dürfen var- und out-Parameter nicht einfangen.</summary>
    function CheckCaptures: Boolean;
    function CapturedByReference(AAnonymous: TSyntaxNode): Boolean;
    /// <summary>Eingaben zuerst, dann var, dann out; sonst in der Reihenfolge des ersten Vorkommens.</summary>
    function SortedOrder: TArray<Integer>;
    function BuildSignature(ASignature: TExtractSignature): Boolean;
    function AddToSignature(ASignature: TExtractSignature; AIndex: Integer): Boolean;
    function BuildEdits(ASignature: TExtractSignature; out AEdits: TArray<TTextEdit>): Boolean;
    procedure RemoveLocals(var AEdits: TArray<TTextEdit>);
  public
    constructor Create(const AText: string; ATree: TSyntaxTree; const AOptions: TExtractOptions);
    destructor Destroy; override;
    /// <summary>Aktion für die Anweisungen in ARange; False mit Grund in AReason.</summary>
    function Run(const ARange: TTextRange; out AAction: TCodeAction; out AReason: string): Boolean;
    /// <summary>Weitere Stellen derselben Routine (#2054); vor Run setzen.</summary>
    property Context: TExtractContext read FContext write FContext;
    /// <summary>Plan des letzten erfolgreichen Run.</summary>
    property Plan: TMethodPlan read FPlan;
    /// <summary>Oberste Anweisungen der Auswahl nach Run.</summary>
    property Statements: TArray<TSyntaxNode> read FStatements;
  end;

/// <summary>Gleiche Parameter in gleicher Reihenfolge und Art.</summary>
function SameParameters(const ALeft, ARight: TArray<TExtractParameter>): Boolean;

implementation

uses
  Atlas.Common.Pascal.Contract,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TExtractMethodText = (AsmInTheSelection, WithInTheSelection, ExitInTheSelection, JumpsOutOfTheSelection,
    GotoAcrossTheEdgeOf, GotoWithUnknownTarget, NoSelection, NotInTheBodyOf, NoCompleteStatements,
    ResultInTheSelection, IsOnlyVisibleInThe, IsStillNeededAfterThe, AnAnonymousMethodCaptures, TypeOfUnknown,
    ExtractMethod);

const
  cTexts: array[TExtractMethodText] of TAtlasText = (
    (De: 'asm in der Auswahl'; En: 'asm in the selection'),
    (De: 'with in der Auswahl'; En: 'with in the selection'),
    (De: 'Exit in der Auswahl'; En: 'Exit in the selection'),
    (De: ' springt aus der Auswahl'; En: ' jumps out of the selection'),
    (De: 'goto über den Rand der Auswahl'; En: 'goto across the edge of the selection'),
    (De: 'goto mit unbekanntem Ziel'; En: 'goto with unknown target'),
    (De: 'keine Auswahl'; En: 'no selection'),
    (De: 'nicht im Rumpf einer Routine'; En: 'not in the body of a routine'),
    (De: 'keine vollständigen Anweisungen'; En: 'no complete statements'),
    (De: 'Result in der Auswahl'; En: 'Result in the selection'),
    (De: ' ist nur in der Routine sichtbar'; En: ' is only visible in the routine'),
    (De: ' wird nach der Auswahl noch gebraucht'; En: ' is still needed after the selection'),
    (De: 'eine anonyme Methode fängt %s ein'; En: 'an anonymous method captures %s'),
    (De: 'Typ von %s unbekannt'; En: 'Type of %s unknown'),
    (De: 'Methode extrahieren'; En: 'Extract method'));

{$SCOPEDENUMS OFF}

const
  cLoopKinds = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];

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

/// <summary>Parameterart aus dem Datenfluss eines Namens der Art AKind.</summary>
function FlowMode(const AUse: TLocalUse; AKind: TRoutineLocalKind): TParameterMode;
begin
  if not AUse.WriteIn then
  begin
    Result := TParameterMode.Const_;
    if (AKind = TRoutineLocalKind.Variable) and not AUse.Before and not AUse.After then
    begin
      Result := TParameterMode.LocalVar;
    end;
  end
  else if AUse.After then
  begin
    Result := TParameterMode.Var_;
    if AUse.FirstWrite then
    begin
      Result := TParameterMode.Out_;
    end;
  end
  else if AUse.ReadIn and not AUse.FirstWrite and AUse.Before then
  begin
    Result := TParameterMode.Value;
  end
  else
  begin
    Result := TParameterMode.LocalVar;
  end;
end;

{ Auswahl }

/// <summary>Eine einzelne ganze Anweisung: der Knoten selbst. Ein Aufruf liegt deckungsgleich unter seiner
/// Anweisung, darum von dort aufwärts suchen. nil ohne.</summary>
function SingleStatement(AContainer, ABody: TSyntaxNode; AStart, AEnd: Integer): TSyntaxNode;
var
  mChild: TSyntaxNode;
begin
  Result := nil;
  mChild := AContainer;
  while (Result = nil) and (mChild <> nil) and (mChild <> ABody) and (mChild.StartOffset = AStart) and
    (mChild.EndOffset = AEnd) do
  begin
    if TRoutineBody.IsStatement(mChild) and TRoutineBody.InList(mChild) then
    begin
      Result := mChild;
    end;
    mChild := mChild.Parent;
  end;
end;

/// <summary>Kinder von AContainer, die die Auswahl berührt; False, wenn eins hinausragt oder nicht in einer
/// Anweisungsliste steht.</summary>
function ChildrenInside(AContainer: TSyntaxNode; AStart, AEnd: Integer;
  out AStatements: TArray<TSyntaxNode>): Boolean;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  AStatements := nil;
  Result := True;
  for mIndex := 0 to AContainer.ChildCount - 1 do
  begin
    mChild := AContainer[mIndex];
    if (mChild.EndOffset > AStart) and (mChild.StartOffset < AEnd) then
    begin
      Result := Result and TExtractSupport.InSelection(mChild, AStart, AEnd) and TRoutineBody.InList(mChild);
      AStatements := AStatements + [mChild];
    end;
  end;
  Result := Result and (AStatements <> nil);
end;

/// <summary>Zwischen den Anweisungen nur ";" und Kommentare.</summary>
function OnlyFillerBetween(const ATokens: TArray<TPascalToken>; const AStatements: TArray<TSyntaxNode>;
  AStart, AEnd: Integer): Boolean;
var
  mToken, mCovered: Integer;
begin
  Result := True;
  mToken := TRoutineBody.TokenAt(ATokens, AStart);
  mCovered := 0;
  while Result and (mToken <= High(ATokens)) and (ATokens[mToken].Offset < AEnd) do
  begin
    while (mCovered <= High(AStatements)) and (AStatements[mCovered].EndOffset <= ATokens[mToken].Offset) do
    begin
      Inc(mCovered);
    end;
    Result := ((mCovered <= High(AStatements)) and (AStatements[mCovered].StartOffset <= ATokens[mToken].Offset)) or
      TExtractSupport.IsFiller(ATokens[mToken]);
    Inc(mToken);
  end;
end;

/// <summary>Oberste Anweisungen der Auswahl AStart..AEnd: alle aus derselben Anweisungsliste, dazwischen nur ";".
/// </summary>
function SelectedStatements(ATree: TSyntaxTree; ABody: TSyntaxNode; AStart, AEnd: Integer;
  out AStatements: TArray<TSyntaxNode>): Boolean;
var
  mContainer, mSingle: TSyntaxNode;
begin
  mContainer := TRoutineBody.Enclosing(ABody, AStart, AEnd);
  mSingle := SingleStatement(mContainer, ABody, AStart, AEnd);
  if mSingle <> nil then
  begin
    AStatements := [mSingle];
    Exit(True);
  end;
  Result := ChildrenInside(mContainer, AStart, AEnd, AStatements) and
    OnlyFillerBetween(ATree.Tokens, AStatements, AStart, AEnd) and (AStatements[0].StartOffset = AStart) and
    (AStatements[High(AStatements)].EndOffset = AEnd);
end;

function IsTopStatement(const AStatements: TArray<TSyntaxNode>; ANode: TSyntaxNode): Boolean;
var
  mStatement: TSyntaxNode;
begin
  Result := False;
  for mStatement in AStatements do
  begin
    Result := Result or (mStatement = ANode);
  end;
end;

{ Sprünge }

/// <summary>asm oder with in der Auswahl; AReason nennt es.</summary>
function HasBlockedStatement(const AStatements: TArray<TSyntaxNode>; out AReason: string): Boolean;
var
  mStatement: TSyntaxNode;
begin
  AReason := '';
  for mStatement in AStatements do
  begin
    if (AReason = '') and TRoutineLocals.HasKind(mStatement, TSyntaxKind.AsmBlock) then
    begin
      AReason := cTexts[TExtractMethodText.AsmInTheSelection].Text;
    end;
    if (AReason = '') and TRoutineLocals.HasKind(mStatement, TSyntaxKind.WithStatement) then
    begin
      AReason := cTexts[TExtractMethodText.WithInTheSelection].Text;
    end;
  end;
  Result := AReason <> '';
end;

/// <summary>Break oder Continue an ANode verlässt die Auswahl: Die Schleife fehlt, liegt außen oder hinter einer
/// anonymen Methode.</summary>
function LeavesSelection(ANode: TSyntaxNode; AStart, AEnd: Integer): Boolean;
var
  mLoop: TSyntaxNode;
begin
  mLoop := ANode.Parent;
  while (mLoop <> nil) and not (mLoop.Kind in cLoopKinds) and (mLoop.Kind <> TSyntaxKind.AnonymousMethod) do
  begin
    mLoop := mLoop.Parent;
  end;
  Result := (mLoop = nil) or (mLoop.Kind = TSyntaxKind.AnonymousMethod) or
    not TExtractSupport.InSelection(mLoop, AStart, AEnd);
end;

/// <summary>Grund, warum der Bezeichner ANode als Sprung die Auswahl verlässt: Exit nie, Break/Continue nur mit
/// Schleife in der Auswahl. '' sonst.</summary>
function JumpProblem(ANode: TSyntaxNode; AStart, AEnd: Integer): string;
begin
  Result := '';
  if ANode.Parent = nil then
  begin
    Exit;
  end;
  if SameText(ANode.Name, 'Exit') and (ANode.Parent.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.Call]) then
  begin
    Result := cTexts[TExtractMethodText.ExitInTheSelection].Text;
  end
  else if MatchText(ANode.Name, ['Break', 'Continue']) and (ANode.Parent.Kind = TSyntaxKind.CallStatement) and
    LeavesSelection(ANode, AStart, AEnd) then
  begin
    Result := ANode.Name + cTexts[TExtractMethodText.JumpsOutOfTheSelection].Text;
  end;
end;

/// <summary>goto und Marke müssen beide innen oder beide außen liegen; '' wenn das gilt.</summary>
function GotoProblem(AGoto: TSyntaxNode; ALabels: TList<TSyntaxNode>; AStart, AEnd: Integer): string;
var
  mLabel: TSyntaxNode;
  mFound: Boolean;
begin
  Result := '';
  mFound := False;
  for mLabel in ALabels do
  begin
    if SameText(mLabel.Name, AGoto.Name) then
    begin
      mFound := True;
      if TExtractSupport.InSelection(mLabel, AStart, AEnd) <> TExtractSupport.InSelection(AGoto, AStart, AEnd) then
      begin
        Result := cTexts[TExtractMethodText.GotoAcrossTheEdgeOf].Text;
      end;
    end;
  end;
  if (Result = '') and not mFound and TExtractSupport.InSelection(AGoto, AStart, AEnd) then
  begin
    Result := cTexts[TExtractMethodText.GotoWithUnknownTarget].Text;
  end;
end;

function GotosInside(ABody: TSyntaxNode; AStart, AEnd: Integer; out AReason: string): Boolean;
var
  mGotos, mLabels: TList<TSyntaxNode>;
  mGoto: TSyntaxNode;
begin
  AReason := '';
  mGotos := TList<TSyntaxNode>.Create;
  mLabels := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(ABody, TSyntaxKind.GotoStatement, mGotos);
    TRoutineLocals.CollectKind(ABody, TSyntaxKind.LabeledStatement, mLabels);
    for mGoto in mGotos do
    begin
      if AReason = '' then
      begin
        AReason := GotoProblem(mGoto, mLabels, AStart, AEnd);
      end;
    end;
  finally
    mLabels.Free;
    mGotos.Free;
  end;
  Result := AReason = '';
end;

/// <summary>Sprünge prüfen: kein asm und with, Exit nie, Break/Continue nur mit Schleife in der Auswahl, goto
/// nur innen.</summary>
function JumpsInside(ABody: TSyntaxNode; const AStatements: TArray<TSyntaxNode>; AStart, AEnd: Integer;
  out AReason: string): Boolean;
var
  mNodes: TList<TSyntaxNode>;
  mStatement, mNode: TSyntaxNode;
begin
  if HasBlockedStatement(AStatements, AReason) then
  begin
    Exit(False);
  end;
  mNodes := TList<TSyntaxNode>.Create;
  try
    for mStatement in AStatements do
    begin
      TRoutineLocals.CollectKind(mStatement, TSyntaxKind.Identifier, mNodes);
    end;
    for mNode in mNodes do
    begin
      if AReason = '' then
      begin
        AReason := JumpProblem(mNode, AStart, AEnd);
      end;
    end;
  finally
    mNodes.Free;
  end;
  Result := (AReason = '') and GotosInside(ABody, AStart, AEnd, AReason);
end;

function SameParameters(const ALeft, ARight: TArray<TExtractParameter>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(ALeft) = Length(ARight);
  mIndex := 0;
  while Result and (mIndex <= High(ALeft)) do
  begin
    Result := SameText(ALeft[mIndex].Name, ARight[mIndex].Name) and (ALeft[mIndex].Mode = ARight[mIndex].Mode);
    Inc(mIndex);
  end;
end;

/// <summary>Der Aufruf greift mit dieser Parameterart überhaupt auf den Namen zu.</summary>
function Accesses(AMode: TParameterMode): Boolean;
begin
  Result := AMode in [TParameterMode.Const_, TParameterMode.Var_, TParameterMode.Out_, TParameterMode.Value];
end;

{ TExtractWindow }

class function TExtractWindow.Create(AStart, AFinish: Integer): TExtractWindow;
begin
  Result.Start := AStart;
  Result.Finish := AFinish;
end;

{ TMethodExtraction }

constructor TMethodExtraction.Create(const AText: string; ATree: TSyntaxTree; const AOptions: TExtractOptions);
begin
  inherited Create;
  FText := AText;
  FTree := ATree;
  FOptions := AOptions;
  FOccurrences := TList<TLocalOccurrence>.Create;
end;

destructor TMethodExtraction.Destroy;
begin
  FOccurrences.Free;
  inherited;
end;

function TMethodExtraction.Prepare(const ARange: TTextRange): Boolean;
begin
  if not TExtractSupport.Selection(FText, FTree, ARange, FStart, FEnd) then
  begin
    Exit(Fail(cTexts[TExtractMethodText.NoSelection].Text, FReason));
  end;
  FRoutine := TRoutineBody.RoutineAt(FTree, FStart);
  if (FRoutine = nil) or (TRoutineBody.RoutineAt(FTree, FEnd) <> FRoutine) then
  begin
    Exit(Fail(cTexts[TExtractMethodText.NotInTheBodyOf].Text, FReason));
  end;
  FBody := TRoutineBody.BodyOf(FRoutine);
  if not SelectedStatements(FTree, FBody, FStart, FEnd, FStatements) then
  begin
    Exit(Fail(cTexts[TExtractMethodText.NoCompleteStatements].Text, FReason));
  end;
  // In einer anonymen Methode oder einem with-Rumpf: Namen hätten außen eine andere Bedeutung.
  Result := not TExtractSupport.InsideBlocked(FStatements[0], FBody, FReason) and
    JumpsInside(FBody, FStatements, FStart, FEnd, FReason);
end;

procedure TMethodExtraction.FindLoop;
var
  mLoop: TSyntaxNode;
begin
  FLoopStart := FStart;
  FLoopEnd := FEnd;
  mLoop := FStatements[0].Parent;
  while (mLoop <> nil) and (mLoop <> FBody) do
  begin
    if mLoop.Kind in cLoopKinds then
    begin
      FLoopStart := mLoop.StartOffset;
      FLoopEnd := mLoop.EndOffset;
    end;
    mLoop := mLoop.Parent;
  end;
end;

function TMethodExtraction.VisibleOutside(ANode: TSyntaxNode; ALocal: Integer): Boolean;
begin
  Result := True;
  if ALocal >= 0 then
  begin
    Exit;
  end;
  if SameText(ANode.Name, 'Result') then
  begin
    Result := Fail(cTexts[TExtractMethodText.ResultInTheSelection].Text, FReason);
  end
  else if IndexText(ANode.Name, FOnlyNames) >= 0 then
  begin
    Result := Fail(ANode.Name + cTexts[TExtractMethodText.IsOnlyVisibleInThe].Text, FReason);
  end;
end;

function TMethodExtraction.CollectOccurrences: Boolean;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mOccurrence: TLocalOccurrence;
begin
  Result := True;
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(FBody, TSyntaxKind.Identifier, mNodes);
    for mNode in mNodes do
    begin
      if InOther(mNode.StartOffset) then
      begin
        Continue;
      end;
      mOccurrence.Node := mNode;
      mOccurrence.Local := TRoutineLocals.IndexOf(FLocals, mNode.Name, mNode.StartOffset);
      if TExtractSupport.InSelection(mNode, FStart, FEnd) and not VisibleOutside(mNode, mOccurrence.Local) then
      begin
        Exit(False);
      end;
      if mOccurrence.Local >= 0 then
      begin
        mOccurrence.Access := TRoutineLocals.AccessOf(mNode, FLookup);
        FOccurrences.Add(mOccurrence);
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

procedure TMethodExtraction.MarkForLoops;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(FBody, TSyntaxKind.ForStatement, mNodes);
    for mNode in mNodes do
    begin
      mIndex := -1;
      if not TRoutineLocals.IsInlineFor(FTree.Tokens, mNode) then
      begin
        mIndex := TRoutineLocals.IndexOf(FLocals, mNode.Name, mNode.StartOffset);
      end;
      if (mIndex < 0) or InOther(mNode.StartOffset) then
      begin
        Continue;
      end;
      if TExtractSupport.InSelection(mNode, FStart, FEnd) then
      begin
        FUses[mIndex].WriteIn := True;
      end
      else if mNode.StartOffset < FStart then
      begin
        FUses[mIndex].Before := True;
      end
      else
      begin
        FUses[mIndex].After := True;
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

procedure TMethodExtraction.MarkInside(const AOccurrence: TLocalOccurrence);
var
  mIndex: Integer;
begin
  mIndex := AOccurrence.Local;
  if not FUses[mIndex].Seen then
  begin
    FUses[mIndex].Seen := True;
    FOrder := FOrder + [mIndex];
    // Erstes Vorkommen: unbedingt geschrieben, wenn es Ziel einer obersten Zuweisung ist.
    FUses[mIndex].FirstWrite := (AOccurrence.Access = TLocalAccess.Write) and
      IsTopStatement(FStatements, AOccurrence.Node.Parent);
    FUses[mIndex].FirstNode := AOccurrence.Node;
  end
  else if FUses[mIndex].FirstWrite and (AOccurrence.Access <> TLocalAccess.Write) and
    TRoutineBody.Within(AOccurrence.Node, FUses[mIndex].FirstNode.Parent) then
  begin
    // Die rechte Seite derselben Zuweisung liest vor dem Schreiben.
    FUses[mIndex].FirstWrite := False;
  end;
  if AOccurrence.Access in [TLocalAccess.Read, TLocalAccess.ReadWrite] then
  begin
    FUses[mIndex].ReadIn := True;
  end;
  if AOccurrence.Access in [TLocalAccess.Write, TLocalAccess.ReadWrite] then
  begin
    FUses[mIndex].WriteIn := True;
  end;
end;

procedure TMethodExtraction.MarkOccurrence(const AOccurrence: TLocalOccurrence);
var
  mNode: TSyntaxNode;
begin
  mNode := AOccurrence.Node;
  if TExtractSupport.InSelection(mNode, FStart, FEnd) then
  begin
    MarkInside(AOccurrence);
  end
  else
  begin
    MarkOutside(AOccurrence.Local, mNode.StartOffset, mNode.EndOffset);
  end;
end;

procedure TMethodExtraction.MarkOutside(ALocal, AStart, AEnd: Integer);
begin
  if AStart < FStart then
  begin
    FUses[ALocal].Before := True;
    if (AStart >= FLoopStart) and (AEnd <= FLoopEnd) and (FLoopStart < FStart) then
    begin
      FUses[ALocal].After := True;
    end;
  end
  else
  begin
    FUses[ALocal].After := True;
  end;
end;

function TMethodExtraction.InOther(AOffset: Integer): Boolean;
var
  mWindow: TExtractWindow;
begin
  Result := False;
  for mWindow in FContext.Others do
  begin
    Result := Result or ((AOffset >= mWindow.Start) and (AOffset < mWindow.Finish));
  end;
end;

procedure TMethodExtraction.MarkAssumed;
var
  mWindow: TExtractWindow;
  mParameter: TExtractParameter;
  mIndex: Integer;
begin
  for mWindow in FContext.Others do
  begin
    for mParameter in FContext.Assumed do
    begin
      mIndex := -1;
      if Accesses(mParameter.Mode) then
      begin
        mIndex := TRoutineLocals.IndexOf(FLocals, mParameter.Name, mWindow.Start);
      end;
      if mIndex >= 0 then
      begin
        MarkOutside(mIndex, mWindow.Start, mWindow.Finish);
      end;
    end;
  end;
end;

function TMethodExtraction.Parameters: TArray<TExtractParameter>;
var
  mIndex: Integer;
  mParameter: TExtractParameter;
begin
  Result := nil;
  for mIndex in SortedOrder do
  begin
    mParameter.Name := FLocals[mIndex].Name;
    mParameter.Mode := FUses[mIndex].Mode;
    Result := Result + [mParameter];
  end;
end;

function TMethodExtraction.DeclaredInside(AIndex: Integer): Boolean;
begin
  Result := (FLocals[AIndex].Kind in [TRoutineLocalKind.InlineVariable, TRoutineLocalKind.LoopVariable]) and
    TExtractSupport.InSelection(FLocals[AIndex].Decl, FStart, FEnd);
end;

function TMethodExtraction.OnlyInside(AIndex: Integer): Boolean;
begin
  Result := (FUses[AIndex].Mode = TParameterMode.LocalVar) and
    (FLocals[AIndex].Kind = TRoutineLocalKind.Variable) and not FUses[AIndex].Before and not FUses[AIndex].After;
end;

function TMethodExtraction.ChooseModes: Boolean;
var
  mIndex: Integer;
begin
  Result := True;
  FRemoved := nil;
  for mIndex in FOrder do
  begin
    if FLocals[mIndex].Kind = TRoutineLocalKind.Constant then
    begin
      FUses[mIndex].Mode := TParameterMode.CopyConst;
    end
    else if DeclaredInside(mIndex) then
    begin
      if FUses[mIndex].After then
      begin
        Exit(Fail(FLocals[mIndex].Name + cTexts[TExtractMethodText.IsStillNeededAfterThe].Text, FReason));
      end;
    end
    else
    begin
      FUses[mIndex].Mode := FlowMode(FUses[mIndex], FLocals[mIndex].Kind);
      if OnlyInside(mIndex) then
      begin
        FRemoved := FRemoved + [FLocals[mIndex].Name];
      end;
    end;
  end;
end;

function TMethodExtraction.CapturedByReference(AAnonymous: TSyntaxNode): Boolean;
var
  mOccurrence: TLocalOccurrence;
begin
  Result := False;
  for mOccurrence in FOccurrences do
  begin
    if not Result and TRoutineBody.Within(mOccurrence.Node, AAnonymous) and
      (FUses[mOccurrence.Local].Mode in [TParameterMode.Var_, TParameterMode.Out_]) then
    begin
      Result := not Fail(cTexts[TExtractMethodText.AnAnonymousMethodCaptures].Fmt([FLocals[mOccurrence.Local].Name]),
        FReason);
    end;
  end;
end;

function TMethodExtraction.CheckCaptures: Boolean;
var
  mAnonymous: TList<TSyntaxNode>;
  mStatement, mNode: TSyntaxNode;
begin
  Result := True;
  mAnonymous := TList<TSyntaxNode>.Create;
  try
    for mStatement in FStatements do
    begin
      TRoutineLocals.CollectKind(mStatement, TSyntaxKind.AnonymousMethod, mAnonymous);
    end;
    for mNode in mAnonymous do
    begin
      Result := Result and not CapturedByReference(mNode);
    end;
  finally
    mAnonymous.Free;
  end;
end;

function TMethodExtraction.Analyze: Boolean;
var
  mOccurrence: TLocalOccurrence;
  mIndex: Integer;
begin
  FLocals := TRoutineLocals.Collect(FText, FTree, FRoutine);
  FOnlyNames := TExtractSupport.RoutineOnlyNames(FRoutine);
  FLookup := TFlowSignatures.FromTree(FTree.Root);
  FindLoop;
  SetLength(FUses, Length(FLocals));
  for mIndex := 0 to High(FLocals) do
  begin
    FUses[mIndex] := Default(TLocalUse);
    FUses[mIndex].Before := FLocals[mIndex].Kind = TRoutineLocalKind.Parameter;
  end;
  FOrder := nil;
  Result := CollectOccurrences;
  if Result then
  begin
    MarkForLoops;
    for mOccurrence in FOccurrences do
    begin
      MarkOccurrence(mOccurrence);
    end;
    MarkAssumed;
    Result := ChooseModes and CheckCaptures;
  end;
end;

function TMethodExtraction.SortedOrder: TArray<Integer>;
var
  mGroup, mIndex: Integer;
begin
  Result := nil;
  for mGroup := 0 to 2 do
  begin
    for mIndex in FOrder do
    begin
      if GroupOf(FUses[mIndex].Mode) = mGroup then
      begin
        Result := Result + [mIndex];
      end;
    end;
  end;
end;

function TMethodExtraction.AddToSignature(ASignature: TExtractSignature; AIndex: Integer): Boolean;
var
  mType: string;
begin
  Result := ASignature.LocalType(FLocals[AIndex], mType);
  if not Result then
  begin
    Result := Fail(cTexts[TExtractMethodText.TypeOfUnknown].Fmt([FLocals[AIndex].Name]), FReason);
  end
  else if FUses[AIndex].Mode = TParameterMode.LocalVar then
  begin
    ASignature.AddVariable(FLocals[AIndex].Name, mType);
  end
  else
  begin
    ASignature.AddParameter(ArgumentText(FUses[AIndex].Mode), FLocals[AIndex].Name, mType);
  end;
end;

function TMethodExtraction.BuildSignature(ASignature: TExtractSignature): Boolean;
var
  mIndex: Integer;
begin
  Result := True;
  for mIndex in SortedOrder do
  begin
    if FUses[mIndex].Mode = TParameterMode.CopyConst then
    begin
      ASignature.AddConstant(FLocals[mIndex]);
    end
    else if Result and (FUses[mIndex].Mode <> TParameterMode.None) then
    begin
      Result := AddToSignature(ASignature, mIndex);
    end;
  end;
end;

procedure TMethodExtraction.RemoveLocals(var AEdits: TArray<TTextEdit>);
var
  mIndex, mInner: Integer;
begin
  if FRemoved = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to FRoutine.ChildCount - 1 do
  begin
    if FRoutine[mIndex].Kind = TSyntaxKind.VarSection then
    begin
      for mInner := 0 to FRoutine[mIndex].ChildCount - 1 do
      begin
        TRoutineLocals.RemoveVariables(FTree, FRoutine[mIndex][mInner], FRemoved, AEdits);
      end;
    end;
  end;
end;

function TMethodExtraction.BuildEdits(ASignature: TExtractSignature; out AEdits: TArray<TTextEdit>): Boolean;
var
  mRequest: TRoutineHeadRequest;
  mHead: TRoutineHead;
  mBody: string;
  mLine: Integer;
begin
  AEdits := ASignature.Edits;
  // Kopf: Methode der Klasse oder Routine vor der umgebenden.
  mRequest := Default(TRoutineHeadRequest);
  mRequest.Routine := FRoutine;
  mRequest.Body := FBody;
  mRequest.BaseName := cExtractedMethodName;
  if FOptions.MethodName <> '' then
  begin
    mRequest.BaseName := FOptions.MethodName;
  end;
  mRequest.Kind := 'procedure';
  mRequest.Params := ASignature.ParamsText;
  mRequest.Style := FOptions.Style;
  Result := TExtractSupport.NewRoutineHead(FText, FTree, mRequest, AEdits, mHead);
  if not Result then
  begin
    FReason := mHead.Reason;
    Exit;
  end;
  // Rumpf: die Anweisungen eine Ebene unter begin.
  mBody := Copy(FText, FStart + 1, FEnd - FStart);
  if not EndsStr(';', mBody) then
  begin
    mBody := mBody + ';';
  end;
  mLine := TRoutineBody.RoutineInsertLine(FText, FRoutine);
  AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(mLine, 0, mLine, 0), ASignature.RoutineText(mHead.Text,
    mBody, TTextLines.IndentOf(FText, FStatements[0].StartPos.Line)))];
  FPlan.Key := ASignature.Key(mHead.Text);
  FPlan.LocalEdits := nil;
  RemoveLocals(FPlan.LocalEdits);
  FPlan.CallRange := TTextRange.Create(FStatements[0].StartPos, FStatements[High(FStatements)].EndPos);
  FPlan.CallText := mHead.ShortName + ASignature.ArgsText;
  AEdits := AEdits + FPlan.LocalEdits + [TTextEdit.Create(FPlan.CallRange, FPlan.CallText)];
end;

function TMethodExtraction.Run(const ARange: TTextRange; out AAction: TCodeAction; out AReason: string): Boolean;
var
  mSignature: TExtractSignature;
  mEdits: TArray<TTextEdit>;
begin
  AAction := Default(TCodeAction);
  FPlan := Default(TMethodPlan);
  FReason := '';
  Result := Prepare(ARange) and Analyze;
  if Result then
  begin
    mSignature := TExtractSignature.Create(FText, FTree, FRoutine, FOptions);
    try
      Result := BuildSignature(mSignature) and BuildEdits(mSignature, mEdits);
    finally
      mSignature.Free;
    end;
  end;
  if Result then
  begin
    AAction.Title := cTexts[TExtractMethodText.ExtractMethod].Text;
    AAction.Kind := cExtractKind;
    AAction.Edits := mEdits;
    FPlan.Parameters := Parameters;
    FPlan.Routine := FRoutine;
  end;
  AReason := FReason;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.Extract.Method', cTexts);

end.
