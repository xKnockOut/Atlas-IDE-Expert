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
//     Auf Wunsch (#2054) eine zweite Aktion, die auch textgleiche Stellen
//     der Unit mit derselben neuen Methode durch den Aufruf ersetzt
//     (Atlas.Common.Editing.Extract.Duplicates).
//   - „Variable einführen“: Der markierte Ausdruck wird in eine Variable vor
//     der Anweisung ausgelagert; auf Wunsch alle textgleichen Vorkommen im
//     selben Block, solange dazwischen keiner seiner Namen geändert wird.
//   - „Konstante extrahieren“: Das Literal wird zu einer Konstante im
//     const-Abschnitt der Routine bzw. vor der Routine in der Unit.
//   - „Bedingung in Funktion auslagern“ (#980, Korrektur von
//     metric-boolean-operands): Die ganze Bedingung eines if, while, until
//     oder Bedingungsausdrucks wird zu einer Funktion mit Ergebnis Boolean
//     (Methode der Klasse bzw. Routine vor der umgebenden); gelesene lokale
//     Namen werden const-Parameter, lokale Konstanten mitkopiert. Nicht
//     angeboten, wenn die Bedingung etwas ändert (Zuweisung, var-Argument),
//     Result, nur in der Routine sichtbare Namen oder eine anonyme Methode
//     enthält oder ein Typ unbekannt ist.
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

// Aufbau: gemeinsame Teile (Optionen, Typprobe, Kopf und Signatur der neuen Routine) in
// Atlas.Common.Editing.Extract.Shared, „Methode extrahieren“ in Atlas.Common.Editing.Extract.Method; diese Unit
// ist die Fassade und enthält die übrigen Aktionen.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.Extract.Shared;

const
  /// <summary>Art der Extrahieren-Aktionen (LSP).</summary>
  cExtractKind = cExtractKind;

type
  /// <summary>Typ eines Ausdrucks laut Namensauflösung (Typ aus Extract.Shared).</summary>
  TProbedType = Atlas.Common.Editing.Extract.Shared.TProbedType;
  TTypeProbe = Atlas.Common.Editing.Extract.Shared.TTypeProbe;
  TExtractOptions = Atlas.Common.Editing.Extract.Shared.TExtractOptions;

  TExtractRefactoring = class
  public const
    cMethodName = cExtractedMethodName;
    cVariableName = 'Value';
    cConstantName = 'NewConstant';
    cConditionName = 'ExtractedCondition';
    cProbeName = cExtractProbeName;
  public
    /// <summary>„Methode extrahieren“ für die Anweisungen in ARange; False mit Grund in AReason.</summary>
    class function ExtractMethod(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AOptions: TExtractOptions; out AAction: TCodeAction; out AReason: string): Boolean; overload; static;
    class function ExtractMethod(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AOptions: TExtractOptions; out AAction: TCodeAction): Boolean; overload; static;
    /// <summary>„Methode extrahieren“ samt textgleicher Stellen der Unit (#2054), die derselbe Aufruf ersetzt;
    /// je Stelle ein abwählbarer Teil (TCodeAction.Choices). False ohne gleiche Stelle, Grund in AReason.</summary>
    class function ExtractMethodWithDuplicates(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AOptions: TExtractOptions; out AAction: TCodeAction; out AReason: string): Boolean; static;
    /// <summary>„Variable einführen“ für den Ausdruck in ARange; mit AAll für alle textgleichen Vorkommen im
    /// selben Block (False, wenn es nur eins gibt).</summary>
    class function IntroduceVariable(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AOptions: TExtractOptions; AAll: Boolean; out AAction: TCodeAction): Boolean; static;
    /// <summary>„Konstante extrahieren“ für das Literal in ARange (oder am Cursor); AUnit: vor der Routine in
    /// der Unit statt im const-Abschnitt der Routine.</summary>
    class function ExtractConstant(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AOptions: TExtractOptions; AUnit: Boolean; out AAction: TCodeAction): Boolean; static;
    /// <summary>„Bedingung in Funktion auslagern“ für die ganze Bedingung in ARange (#980); False mit Grund in
    /// AReason.</summary>
    class function ExtractCondition(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AOptions: TExtractOptions; out AAction: TCodeAction; out AReason: string): Boolean; overload; static;
    class function ExtractCondition(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AOptions: TExtractOptions; out AAction: TCodeAction): Boolean; overload; static;
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
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.Extract.Method,
  Atlas.Common.Editing.Extract.Duplicates,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TExtractText = (IntroduceVariable, IntroduceVariableAllOccurrences, ExtractConstantInTheUnit, NoSelection,
    NotInTheBodyOf, NotAWholeCondition, AnonymousMethodInTheCondition, ResultInTheCondition, IsOnlyVisibleInThe,
    TheConditionChanges, TypeOfUnknown, MoveConditionIntoAFunction);

const
  cTexts: array[TExtractText] of TAtlasText = (
    (De: 'Variable einführen'; En: 'Introduce variable'),
    (De: 'Variable einführen (alle %d Vorkommen)'; En: 'Introduce variable (all %d occurrences)'),
    (De: 'Konstante in der Unit extrahieren'; En: 'Extract constant in the unit'),
    (De: 'keine Auswahl'; En: 'no selection'),
    (De: 'nicht im Rumpf einer Routine'; En: 'not in the body of a routine'),
    (De: 'keine ganze Bedingung'; En: 'not a whole condition'),
    (De: 'anonyme Methode in der Bedingung'; En: 'anonymous method in the condition'),
    (De: 'Result in der Bedingung'; En: 'Result in the condition'),
    (De: ' ist nur in der Routine sichtbar'; En: ' is only visible in the routine'),
    (De: 'die Bedingung ändert '; En: 'the condition changes '),
    (De: 'Typ von %s unbekannt'; En: 'Type of %s unknown'),
    (De: 'Bedingung in Funktion auslagern'; En: 'Move condition into a function'));

{$SCOPEDENUMS OFF}

const
  cExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess, TSyntaxKind.Dereference, TSyntaxKind.AddressOf, TSyntaxKind.SetConstructor,
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.IfExpr];

class function TExtractRefactoring.TypeOfExpression(const AText: string; ATree: TSyntaxTree; AExpression,
  AStatement: TSyntaxNode; const AOptions: TExtractOptions): TProbedType;
begin
  Result := TExtractSupport.TypeOfExpression(AText, ATree, AExpression, AStatement, AOptions);
end;

{ Methode extrahieren }

class function TExtractRefactoring.ExtractMethod(const AText: string; ATree: TSyntaxTree;
  const ARange: TTextRange; const AOptions: TExtractOptions; out AAction: TCodeAction): Boolean;
var
  mReason: string;
begin
  Result := ExtractMethod(AText, ATree, ARange, AOptions, AAction, mReason);
end;

class function TExtractRefactoring.ExtractMethod(const AText: string; ATree: TSyntaxTree;
  const ARange: TTextRange; const AOptions: TExtractOptions; out AAction: TCodeAction;
  out AReason: string): Boolean;
var
  mExtraction: TMethodExtraction;
begin
  mExtraction := TMethodExtraction.Create(AText, ATree, AOptions);
  try
    Result := mExtraction.Run(ARange, AAction, AReason);
  finally
    mExtraction.Free;
  end;
end;

class function TExtractRefactoring.ExtractMethodWithDuplicates(const AText: string; ATree: TSyntaxTree;
  const ARange: TTextRange; const AOptions: TExtractOptions; out AAction: TCodeAction; out AReason: string): Boolean;
var
  mDuplicates: TExtractDuplicates;
begin
  mDuplicates := TExtractDuplicates.Create(AText, ATree, AOptions);
  try
    Result := mDuplicates.Run(ARange, AAction, AReason);
  finally
    mDuplicates.Free;
  end;
end;

{ Variable einführen }

/// <summary>Name für die Variable aus dem Ausdruck: letzter Name einer Kette ohne "Get", sonst Value.</summary>
function NameFor(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call] then
  begin
    Result := ANode.Name;
  end;
  if StartsText('Get', Result) and (Length(Result) > 3) then
  begin
    Result := Copy(Result, 4, MaxInt);
  end;
  if (Result = '') or not CharInSet(Result[1], ['A'..'Z', 'a'..'z']) or (Pos('<', Result) > 0) then
  begin
    Result := TExtractRefactoring.cVariableName;
  end
  else
  begin
    Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
  end;
end;

/// <summary>Namen, die im Ausdruck vorkommen.</summary>
function NamesIn(ANode: TSyntaxNode): TArray<string>;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Result := nil;
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(ANode, TSyntaxKind.Identifier, mNodes);
    for mNode in mNodes do
    begin
      Result := Result + [mNode.Name];
    end;
  finally
    mNodes.Free;
  end;
end;

/// <summary>Wird zwischen AFrom und ATo (Offsets) einer der Namen geändert oder etwas aufgerufen, das ihn
/// ändern könnte?</summary>
function ChangedBetween(ABody: TSyntaxNode; const ANames: TArray<string>; AFrom, ATo: Integer): Boolean;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Result := False;
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(ABody, TSyntaxKind.Identifier, mNodes);
    for mNode in mNodes do
    begin
      Result := Result or ((mNode.StartOffset > AFrom) and (mNode.StartOffset < ATo) and
        (IndexText(mNode.Name, ANames) >= 0) and (TRoutineLocals.AccessOf(mNode, nil) <> TLocalAccess.Read));
    end;
  finally
    mNodes.Free;
  end;
end;

/// <summary>Ausdruck genau in der Auswahl, ohne Klammern um das Ganze; nil sonst.</summary>
function SelectedExpression(ABody: TSyntaxNode; AStart, AEnd: Integer): TSyntaxNode;
begin
  Result := TRoutineBody.Enclosing(ABody, AStart, AEnd);
  if (Result.StartOffset <> AStart) or (Result.EndOffset <> AEnd) or not (Result.Kind in cExpressionKinds) then
  begin
    Exit(nil);
  end;
  // Klammern um den ganzen Ausdruck gehören nicht in die Variable.
  if (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) then
  begin
    Result := Result[0];
  end;
end;

type
  /// <summary>Plant „Variable einführen“.</summary>
  TVariableIntroduction = class
  private
    FText: string;
    FTree: TSyntaxTree;
    FOptions: TExtractOptions;
    FRoutine: TSyntaxNode;
    FBody: TSyntaxNode;
    FExpression: TSyntaxNode;
    FHost: TSyntaxNode;
    FTargets: TArray<TSyntaxNode>;
    function Find(const ARange: TTextRange; AAll: Boolean): Boolean;
    /// <summary>Textgleiche Vorkommen im selben Block ab AHost, ohne Überlappung.</summary>
    function SameExpressions(AHost: TSyntaxNode): TArray<TSyntaxNode>;
    /// <summary>Vorkommen, die die Variable ersetzt; nil, wenn es mit AAll keine zwei gibt oder sich ein Name
    /// dazwischen ändert.</summary>
    function Targets(AHost: TSyntaxNode; AAll: Boolean): TArray<TSyntaxNode>;
    /// <summary>Deklaration und Zuweisung vor der Anweisung; False bei unbekanntem Typ.</summary>
    function DeclarationEdits(const AName: string; out AEdits: TArray<TTextEdit>): Boolean;
  public
    constructor Create(const AText: string; ATree: TSyntaxTree; const AOptions: TExtractOptions);
    function Run(const ARange: TTextRange; AAll: Boolean; out AAction: TCodeAction): Boolean;
  end;

constructor TVariableIntroduction.Create(const AText: string; ATree: TSyntaxTree; const AOptions: TExtractOptions);
begin
  inherited Create;
  FText := AText;
  FTree := ATree;
  FOptions := AOptions;
end;

function TVariableIntroduction.SameExpressions(AHost: TSyntaxNode): TArray<TSyntaxNode>;
var
  mNormal: string;
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Result := nil;
  mNormal := TExtractSupport.NormalText(FTree, FExpression);
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(AHost.Parent, FExpression.Kind, mNodes);
    for mNode in mNodes do
    begin
      if (mNode.StartOffset >= AHost.StartOffset) and (TExtractSupport.NormalText(FTree, mNode) = mNormal) and
        (TRoutineBody.HostStatement(mNode, FBody) <> nil) and
        ((Result = nil) or (mNode.StartOffset >= Result[High(Result)].EndOffset)) then
      begin
        Result := Result + [mNode];
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

function TVariableIntroduction.Targets(AHost: TSyntaxNode; AAll: Boolean): TArray<TSyntaxNode>;
begin
  if not AAll then
  begin
    Result := [FExpression];
    Exit;
  end;
  // Textgleiche Vorkommen im selben Block ab der Anweisung, solange sich ihre Namen nicht ändern.
  Result := SameExpressions(AHost);
  if (Length(Result) < 2) or ChangedBetween(FBody, NamesIn(FExpression), Result[0].StartOffset,
    Result[High(Result)].EndOffset) then
  begin
    Result := nil;
  end;
end;

function TVariableIntroduction.Find(const ARange: TTextRange; AAll: Boolean): Boolean;
var
  mStart, mEnd: Integer;
begin
  Result := TExtractSupport.Selection(FText, FTree, ARange, mStart, mEnd);
  if Result then
  begin
    FRoutine := TRoutineBody.RoutineAt(FTree, mStart);
    Result := FRoutine <> nil;
  end;
  if Result then
  begin
    FBody := TRoutineBody.BodyOf(FRoutine);
    FExpression := SelectedExpression(FBody, mStart, mEnd);
    FHost := nil;
    if FExpression <> nil then
    begin
      FHost := TRoutineBody.HostStatement(FExpression, FBody);
    end;
    Result := FHost <> nil;
  end;
  if Result then
  begin
    FTargets := Targets(FHost, AAll);
    Result := FTargets <> nil;
  end;
  if Result then
  begin
    FHost := TRoutineBody.HostStatement(FTargets[0], FBody);
  end;
end;

function TVariableIntroduction.DeclarationEdits(const AName: string; out AEdits: TArray<TTextEdit>): Boolean;
var
  mProbed: TProbedType;
  mExpression: string;
begin
  AEdits := nil;
  mExpression := TRoutineBody.TextOf(FText, FExpression);
  Result := True;
  if FOptions.InlineVar then
  begin
    AEdits := [TRoutineBody.InsertBefore(FText, FHost, 'var ' + AName + ' := ' + mExpression + ';')];
    Exit;
  end;
  mProbed := TExtractSupport.TypeOfExpression(FText, FTree, FExpression, FHost, FOptions);
  Result := mProbed.Name <> '';
  if Result then
  begin
    AEdits := [TRoutineBody.AddVariable(FText, FRoutine, AName, mProbed.Name, FOptions.Style),
      TRoutineBody.InsertBefore(FText, FHost, AName + ' := ' + mExpression + ';')];
    TExtractSupport.AddUsesFor(FTree, FText, mProbed, FRoutine.StartOffset, AEdits);
  end;
end;

function TVariableIntroduction.Run(const ARange: TTextRange; AAll: Boolean; out AAction: TCodeAction): Boolean;
var
  mName: string;
  mEdits: TArray<TTextEdit>;
  mNode: TSyntaxNode;
begin
  AAction := Default(TCodeAction);
  Result := Find(ARange, AAll);
  if Result then
  begin
    mName := TRoutineBody.UniqueName(FTree.Tokens, FOptions.Names.Local(NameFor(FExpression)));
    Result := DeclarationEdits(mName, mEdits);
  end;
  if not Result then
  begin
    Exit;
  end;
  for mNode in FTargets do
  begin
    mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(mNode.StartPos, mNode.EndPos), mName)];
  end;
  AAction.Title := cTexts[TExtractText.IntroduceVariable].Text;
  if AAll then
  begin
    AAction.Title := cTexts[TExtractText.IntroduceVariableAllOccurrences].Fmt([Length(FTargets)]);
  end;
  AAction.Kind := cExtractKind;
  AAction.Edits := mEdits;
end;

class function TExtractRefactoring.IntroduceVariable(const AText: string; ATree: TSyntaxTree;
  const ARange: TTextRange; const AOptions: TExtractOptions; AAll: Boolean; out AAction: TCodeAction): Boolean;
var
  mIntroduction: TVariableIntroduction;
begin
  mIntroduction := TVariableIntroduction.Create(AText, ATree, AOptions);
  try
    Result := mIntroduction.Run(ARange, AAll, AAction);
  finally
    mIntroduction.Free;
  end;
end;

{ Konstante extrahieren }

/// <summary>Literal direkt hinter einem unären Minus, das am Anfang der Auswahl steht.</summary>
function IsNegatedLiteral(ANode: TSyntaxNode; AStart: Integer): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and (ANode.Parent <> nil) and
    (ANode.Parent.Kind = TSyntaxKind.UnaryExpr) and (ANode.Parent.Name = '-') and
    (ANode.Parent.StartOffset = AStart);
end;

/// <summary>Literal oder Literal mit Vorzeichen.</summary>
function IsLiteralValue(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) or ((ANode.Kind = TSyntaxKind.UnaryExpr) and
    (ANode.ChildCount = 1) and (ANode[0].Kind = TSyntaxKind.Literal));
end;

/// <summary>In asm oder einer Inline-Konstanten innerhalb von ABody. True/False/nil sind Bezeichner und keine
/// Literale.</summary>
function InAsmOrInlineConst(ANode, ABody: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  Result := False;
  mNode := ANode.Parent;
  while not Result and (mNode <> nil) and (mNode <> ABody) do
  begin
    Result := mNode.Kind in [TSyntaxKind.AsmBlock, TSyntaxKind.InlineConst];
    mNode := mNode.Parent;
  end;
end;

/// <summary>Literal in AStart..AEnd; mit ASelection muss es die Auswahl genau decken. nil ohne.</summary>
function LiteralNode(ABody: TSyntaxNode; AStart, AEnd: Integer; ASelection: Boolean): TSyntaxNode;
begin
  Result := TRoutineBody.Enclosing(ABody, AStart, AEnd);
  // Negative Zahl: das Vorzeichen gehört dazu.
  if ASelection and IsNegatedLiteral(Result, AStart) then
  begin
    Result := Result.Parent;
  end;
  if not IsLiteralValue(Result) or (ASelection and ((Result.StartOffset <> AStart) or
    (Result.EndOffset <> AEnd))) or InAsmOrInlineConst(Result, ABody) then
  begin
    Result := nil;
  end;
end;

type
  /// <summary>Plant „Konstante extrahieren“.</summary>
  TConstantExtraction = class
  private
    FText: string;
    FTree: TSyntaxTree;
    FOptions: TExtractOptions;
    FRoutine: TSyntaxNode;
    FLiteral: TSyntaxNode;
    function Find(const ARange: TTextRange): Boolean;
    /// <summary>const-Abschnitt vor der äußersten Routine, in der das Literal steht.</summary>
    function UnitConstant(const AName, AValue: string): TTextEdit;
  public
    constructor Create(const AText: string; ATree: TSyntaxTree; const AOptions: TExtractOptions);
    function Run(const ARange: TTextRange; AUnit: Boolean; out AAction: TCodeAction): Boolean;
  end;

constructor TConstantExtraction.Create(const AText: string; ATree: TSyntaxTree; const AOptions: TExtractOptions);
begin
  inherited Create;
  FText := AText;
  FTree := ATree;
  FOptions := AOptions;
end;

function TConstantExtraction.Find(const ARange: TTextRange): Boolean;
var
  mFirst, mLast, mStart, mEnd: Integer;
begin
  if (FTree = nil) or not TExtractSupport.OffsetRange(FText, ARange, mFirst, mLast) then
  begin
    Exit(False);
  end;
  mStart := mFirst;
  mEnd := mFirst;
  if (mFirst <> mLast) and not TExtractSupport.Trimmed(FTree.Tokens, mFirst, mLast, mStart, mEnd) then
  begin
    Exit(False);
  end;
  FRoutine := TRoutineBody.RoutineAt(FTree, mStart);
  FLiteral := nil;
  if FRoutine <> nil then
  begin
    FLiteral := LiteralNode(TRoutineBody.BodyOf(FRoutine), mStart, mEnd, mFirst <> mLast);
  end;
  Result := FLiteral <> nil;
end;

function TConstantExtraction.UnitConstant(const AName, AValue: string): TTextEdit;
var
  mOuter: TSyntaxNode;
  mLine: Integer;
  mIndent, mLineBreak: string;
begin
  mOuter := FRoutine;
  while (mOuter.Parent <> nil) and (mOuter.Parent.Kind = TSyntaxKind.RoutineDecl) do
  begin
    mOuter := mOuter.Parent;
  end;
  mLine := TRoutineBody.RoutineInsertLine(FText, mOuter);
  mIndent := TTextLines.IndentOf(FText, mOuter.StartPos.Line);
  mLineBreak := TTextLines.LineBreakOf(FText);
  Result := TTextEdit.Create(TTextRange.Create(mLine, 0, mLine, 0), mIndent + 'const' + mLineBreak + mIndent +
    TRoutineBody.IndentUnit(FOptions.Style) + AName + ' = ' + AValue + ';' + mLineBreak + mLineBreak);
end;

function TConstantExtraction.Run(const ARange: TTextRange; AUnit: Boolean; out AAction: TCodeAction): Boolean;
var
  mName, mValue: string;
  mEdit: TTextEdit;
begin
  AAction := Default(TCodeAction);
  Result := Find(ARange);
  if not Result then
  begin
    Exit;
  end;
  mName := TRoutineBody.UniqueName(FTree.Tokens, FOptions.Names.Constant(TExtractRefactoring.cConstantName));
  mValue := TRoutineBody.TextOf(FText, FLiteral);
  if AUnit then
  begin
    mEdit := UnitConstant(mName, mValue);
    AAction.Title := cTexts[TExtractText.ExtractConstantInTheUnit].Text;
  end
  else
  begin
    mEdit := TRoutineBody.AddConstant(FText, FRoutine, mName, mValue, FOptions.Style);
    AAction.Title := 'Konstante extrahieren';
  end;
  AAction.Kind := cExtractKind;
  AAction.Edits := [mEdit, TTextEdit.Create(TTextRange.Create(FLiteral.StartPos, FLiteral.EndPos), mName)];
end;

class function TExtractRefactoring.ExtractConstant(const AText: string; ATree: TSyntaxTree;
  const ARange: TTextRange; const AOptions: TExtractOptions; AUnit: Boolean; out AAction: TCodeAction): Boolean;
var
  mExtraction: TConstantExtraction;
begin
  mExtraction := TConstantExtraction.Create(AText, ATree, AOptions);
  try
    Result := mExtraction.Run(ARange, AUnit, AAction);
  finally
    mExtraction.Free;
  end;
end;

{ Bedingung in Funktion auslagern }

/// <summary>Ist ANode die ganze Bedingung eines if, while, until oder Bedingungsausdrucks?</summary>
function IsConditionRoot(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  Result := False;
  mParent := ANode.Parent;
  if (mParent = nil) or (mParent.ChildCount = 0) or not (ANode.Kind in cExpressionKinds) then
  begin
    Exit;
  end;
  case mParent.Kind of
    TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement, TSyntaxKind.IfExpr:
      Result := mParent[0] = ANode;
    TSyntaxKind.RepeatStatement:
      Result := mParent[mParent.ChildCount - 1] = ANode;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Ganze Bedingung genau in AStart..AEnd; deckungsgleiche Knoten von innen nach außen. nil ohne.
/// </summary>
function ConditionAt(ABody: TSyntaxNode; AStart, AEnd: Integer): TSyntaxNode;
begin
  Result := TRoutineBody.Enclosing(ABody, AStart, AEnd);
  while not IsConditionRoot(Result) and (Result.Parent <> nil) and (Result.Parent.StartOffset = AStart) and
    (Result.Parent.EndOffset = AEnd) do
  begin
    Result := Result.Parent;
  end;
  if (Result.StartOffset <> AStart) or (Result.EndOffset <> AEnd) or not IsConditionRoot(Result) then
  begin
    Result := nil;
  end;
end;

function Contains(const AValues: TArray<Integer>; AValue: Integer): Boolean;
var
  mValue: Integer;
begin
  Result := False;
  for mValue in AValues do
  begin
    Result := Result or (mValue = AValue);
  end;
end;

type
  /// <summary>Plant „Bedingung in Funktion auslagern“ (#980).</summary>
  TConditionExtraction = class
  private
    FText: string;
    FTree: TSyntaxTree;
    FOptions: TExtractOptions;
    FRoutine: TSyntaxNode;
    FBody: TSyntaxNode;
    FCondition: TSyntaxNode;
    FLocals: TArray<TRoutineLocal>;
    FOnlyNames: TArray<string>;
    FLookup: TFlowSignatureLookup;
    FOrder: TArray<Integer>;
    FReason: string;
    function Prepare(const ARange: TTextRange): Boolean;
    /// <summary>Gelesene lokale Namen in der Reihenfolge des ersten Vorkommens.</summary>
    function CollectNames: Boolean;
    function AddName(ANode: TSyntaxNode): Boolean;
    /// <summary>False mit Grund bei Result und bei Namen, die nur in der Routine sichtbar sind.</summary>
    function VisibleOutside(ANode: TSyntaxNode): Boolean;
    function BuildSignature(ASignature: TExtractSignature): Boolean;
    function BuildEdits(ASignature: TExtractSignature; out AEdits: TArray<TTextEdit>): Boolean;
  public
    constructor Create(const AText: string; ATree: TSyntaxTree; const AOptions: TExtractOptions);
    function Run(const ARange: TTextRange; out AAction: TCodeAction; out AReason: string): Boolean;
  end;

constructor TConditionExtraction.Create(const AText: string; ATree: TSyntaxTree; const AOptions: TExtractOptions);
begin
  inherited Create;
  FText := AText;
  FTree := ATree;
  FOptions := AOptions;
end;

function TConditionExtraction.Prepare(const ARange: TTextRange): Boolean;
var
  mStart, mEnd: Integer;
begin
  if not TExtractSupport.Selection(FText, FTree, ARange, mStart, mEnd) then
  begin
    Exit(Fail(cTexts[TExtractText.NoSelection].Text, FReason));
  end;
  FRoutine := TRoutineBody.RoutineAt(FTree, mStart);
  if (FRoutine = nil) or (TRoutineBody.RoutineAt(FTree, mEnd) <> FRoutine) then
  begin
    Exit(Fail(cTexts[TExtractText.NotInTheBodyOf].Text, FReason));
  end;
  FBody := TRoutineBody.BodyOf(FRoutine);
  FCondition := ConditionAt(FBody, mStart, mEnd);
  if FCondition = nil then
  begin
    Exit(Fail(cTexts[TExtractText.NotAWholeCondition].Text, FReason));
  end;
  Result := not TExtractSupport.InsideBlocked(FCondition, FBody, FReason);
  if Result and TRoutineLocals.HasKind(FCondition, TSyntaxKind.AnonymousMethod) then
  begin
    Result := Fail(cTexts[TExtractText.AnonymousMethodInTheCondition].Text, FReason);
  end;
end;

function TConditionExtraction.VisibleOutside(ANode: TSyntaxNode): Boolean;
begin
  Result := True;
  if SameText(ANode.Name, 'Result') then
  begin
    Result := Fail(cTexts[TExtractText.ResultInTheCondition].Text, FReason);
  end
  else if IndexText(ANode.Name, FOnlyNames) >= 0 then
  begin
    Result := Fail(ANode.Name + cTexts[TExtractText.IsOnlyVisibleInThe].Text, FReason);
  end;
end;

function TConditionExtraction.AddName(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TRoutineLocals.IndexOf(FLocals, ANode.Name, ANode.StartOffset);
  if mIndex < 0 then
  begin
    Exit(VisibleOutside(ANode));
  end;
  // Nur lesen: Die Funktion bekommt die Werte als const-Parameter.
  Result := TRoutineLocals.AccessOf(ANode, FLookup) = TLocalAccess.Read;
  if not Result then
  begin
    FReason := cTexts[TExtractText.TheConditionChanges].Text + ANode.Name;
  end
  else if not Contains(FOrder, mIndex) then
  begin
    FOrder := FOrder + [mIndex];
  end;
end;

function TConditionExtraction.CollectNames: Boolean;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  FLocals := TRoutineLocals.Collect(FText, FTree, FRoutine);
  FOnlyNames := TExtractSupport.RoutineOnlyNames(FRoutine);
  FLookup := TFlowSignatures.FromTree(FTree.Root);
  FOrder := nil;
  Result := True;
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(FCondition, TSyntaxKind.Identifier, mNodes);
    for mNode in mNodes do
    begin
      Result := Result and AddName(mNode);
    end;
  finally
    mNodes.Free;
  end;
end;

function TConditionExtraction.BuildSignature(ASignature: TExtractSignature): Boolean;
var
  mPosition, mIndex: Integer;
  mType: string;
begin
  Result := True;
  mPosition := 0;
  while Result and (mPosition <= High(FOrder)) do
  begin
    mIndex := FOrder[mPosition];
    if FLocals[mIndex].Kind = TRoutineLocalKind.Constant then
    begin
      ASignature.AddConstant(FLocals[mIndex]);
    end
    else if ASignature.LocalType(FLocals[mIndex], mType) then
    begin
      ASignature.AddParameter('const ', FLocals[mIndex].Name, mType);
    end
    else
    begin
      Result := Fail(cTexts[TExtractText.TypeOfUnknown].Fmt([FLocals[mIndex].Name]), FReason);
    end;
    Inc(mPosition);
  end;
end;

function TConditionExtraction.BuildEdits(ASignature: TExtractSignature; out AEdits: TArray<TTextEdit>): Boolean;
var
  mRequest: TRoutineHeadRequest;
  mHead: TRoutineHead;
  mInner: TSyntaxNode;
  mLine: Integer;
begin
  AEdits := ASignature.Edits;
  mRequest := Default(TRoutineHeadRequest);
  mRequest.Routine := FRoutine;
  mRequest.Body := FBody;
  mRequest.BaseName := TExtractRefactoring.cConditionName;
  mRequest.Kind := 'function';
  mRequest.Params := ASignature.ParamsText;
  mRequest.ResultType := ': Boolean';
  mRequest.Style := FOptions.Style;
  Result := TExtractSupport.NewRoutineHead(FText, FTree, mRequest, AEdits, mHead);
  if not Result then
  begin
    FReason := mHead.Reason;
    Exit;
  end;
  // Klammern um die ganze Bedingung braucht die Zuweisung nicht.
  mInner := FCondition;
  if (mInner.Kind = TSyntaxKind.ParenExpr) and (mInner.ChildCount = 1) then
  begin
    mInner := mInner[0];
  end;
  mLine := TRoutineBody.RoutineInsertLine(FText, FRoutine);
  AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(mLine, 0, mLine, 0), ASignature.RoutineText(mHead.Text,
    'Result := ' + TRoutineBody.TextOf(FText, mInner) + ';', TTextLines.IndentOf(FText, FCondition.StartPos.Line))),
    TTextEdit.Create(TTextRange.Create(FCondition.StartPos, FCondition.EndPos), mHead.ShortName +
    ASignature.ArgsText)];
end;

function TConditionExtraction.Run(const ARange: TTextRange; out AAction: TCodeAction; out AReason: string): Boolean;
var
  mSignature: TExtractSignature;
  mEdits: TArray<TTextEdit>;
begin
  AAction := Default(TCodeAction);
  FReason := '';
  Result := Prepare(ARange) and CollectNames;
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
    AAction.Title := cTexts[TExtractText.MoveConditionIntoAFunction].Text;
    AAction.Kind := cExtractKind;
    AAction.Edits := mEdits;
  end;
  AReason := FReason;
end;

class function TExtractRefactoring.ExtractCondition(const AText: string; ATree: TSyntaxTree;
  const ARange: TTextRange; const AOptions: TExtractOptions; out AAction: TCodeAction): Boolean;
var
  mReason: string;
begin
  Result := ExtractCondition(AText, ATree, ARange, AOptions, AAction, mReason);
end;

class function TExtractRefactoring.ExtractCondition(const AText: string; ATree: TSyntaxTree;
  const ARange: TTextRange; const AOptions: TExtractOptions; out AAction: TCodeAction;
  out AReason: string): Boolean;
var
  mExtraction: TConditionExtraction;
begin
  mExtraction := TConditionExtraction.Create(AText, ATree, AOptions);
  try
    Result := mExtraction.Run(ARange, AAction, AReason);
  finally
    mExtraction.Free;
  end;
end;

class function TExtractRefactoring.Actions(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
  const AOptions: TExtractOptions): TArray<TCodeAction>;
var
  mAction: TCodeAction;
  mReason: string;
begin
  Result := nil;
  if ExtractMethod(AText, ATree, ARange, AOptions, mAction) then
  begin
    Result := Result + [mAction];
    if AOptions.Duplicates and ExtractMethodWithDuplicates(AText, ATree, ARange, AOptions, mAction, mReason) then
    begin
      Result := Result + [mAction];
    end;
  end;
  if IntroduceVariable(AText, ATree, ARange, AOptions, False, mAction) then
  begin
    Result := Result + [mAction];
  end;
  if IntroduceVariable(AText, ATree, ARange, AOptions, True, mAction) then
  begin
    Result := Result + [mAction];
  end;
  if ExtractConstant(AText, ATree, ARange, AOptions, False, mAction) then
  begin
    Result := Result + [mAction];
  end;
  if ExtractConstant(AText, ATree, ARange, AOptions, True, mAction) then
  begin
    Result := Result + [mAction];
  end;
  if ExtractCondition(AText, ATree, ARange, AOptions, mAction) then
  begin
    Result := Result + [mAction];
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.Extract', cTexts);

end.
