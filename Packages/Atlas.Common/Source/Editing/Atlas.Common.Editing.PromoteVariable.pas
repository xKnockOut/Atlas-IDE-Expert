unit Atlas.Common.Editing.PromoteVariable;

// Lokale Variable und Feld ineinander umwandeln (#668):
//   In Feld umwandeln (auf einer lokalen Variablen oder Inline-Variablen einer
//     Methode, auch in Records): Vorschlag F + Name ohne L- bzw. m-Präfix
//     (LLineNo → FLineNo). Das Feld steht hinter dem letzten Feld des
//     private-Abschnitts (legt ihn an, wenn er fehlt), die Verwendungen in der
//     Methode werden umbenannt, die Deklaration entfällt; eine Initialisierung
//     (var X := 0) bleibt als Zuweisung. Der Typ einer Inline-Variablen ohne
//     Typangabe kommt aus TPromoteLookup.InlineType (#453). Wird die Variable
//     in der Methode erzeugt und freigegeben oder ruft die Methode sich selbst
//     auf, gibt es eine Warnung.
//   In lokale Variable umwandeln (auf einem privaten Feld, in der Klasse oder
//     an einer Verwendung): nur, wenn das Feld ausschließlich in einer Methode
//     benutzt wird, dort nicht in einer lokalen Routine, und die Methode es
//     auf jedem Weg zuerst schreibt (Kontrollfluss #143, am umgewandelten
//     Text geprüft). Nicht für Felder mit Property, published-Felder, class
//     var, Felder in der Formulardatei und rekursive Methoden.
// Ein Name, der schon ein Mitglied ist oder in den Methoden der Klasse etwas
// anderes bedeutet, wird mit Grund abgelehnt. Das Ergebnis muss parsen.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Editing.RoutineLocals;

type
  /// <summary>Typ der Inline-Variablen ALocal ohne Typangabe; '' unbekannt.</summary>
  TPromoteInlineTypeFunc = reference to function(const ALocal: TRoutineLocal): string;
  /// <summary>Hat die Klasse AClassName (samt Vorfahren) ein Mitglied AName?</summary>
  TPromoteMemberFunc = reference to function(const AClassName, AName: string; AOffset: Integer): Boolean;
  /// <summary>Kommt AName in der Formulardatei der Unit vor?</summary>
  TPromoteInFormFunc = reference to function(const AName: string): Boolean;

  TPromoteLookup = record
    InlineType: TPromoteInlineTypeFunc;
    MemberExists: TPromoteMemberFunc;
    InForm: TPromoteInFormFunc;
    /// <summary>Art der Argumente bekannter Aufrufe (Schreiben über var-Argumente).</summary>
    Flow: TFlowSignatureLookup;
    /// <summary>Ohne Namensauflösung: Aufrufe aus der Datei, Typen ohne Angabe und Vorfahren unbekannt.</summary>
    class function FromTree(ATree: TSyntaxTree): TPromoteLookup; static;
  end;

{$SCOPEDENUMS ON}
  TPromoteDirection = (ToField, ToLocal);
{$SCOPEDENUMS OFF}

  TPromoteTarget = record
    Direction: TPromoteDirection;
    Name: string;
    Suggested: string;
    /// <summary>Titel der Code-Aktion, z. B. „In Feld umwandeln (LLineNo → FLineNo)“.</summary>
    function Title: string;
  end;

  TPromoteResult = record
    Edits: TArray<TTextEdit>;
    Warnings: TArray<string>;
    /// <summary>Geänderte Stellen: Verwendungen und die beiden Deklarationen.</summary>
    Places: Integer;
  end;

  /// <summary>Stelle, Namensauflösung, Format und neuer Name einer Umwandlung.</summary>
  TPromoteRequest = record
    Position: TTextPosition;
    Lookup: TPromoteLookup;
    Style: TFormatStyle;
    Name: string;
    class function Create(const APosition: TTextPosition; const ALookup: TPromoteLookup; const AStyle: TFormatStyle;
      const AName: string): TPromoteRequest; static;
  end;

  TPromoteVariable = class
  public
    class function ToFieldTitle: string; static;
    class function ToLocalTitle: string; static;
    /// <summary>F + Name ohne L- bzw. m-Präfix: LLineNo → FLineNo, mCount → FCount, Total → FTotal.</summary>
    class function FieldName(const ALocal: string): string; static;
    /// <summary>L + Name ohne F-Präfix: FLineNo → LLineNo.</summary>
    class function LocalName(const AField: string): string; static;
    /// <summary>Geht eine Umwandlung an APosition (ohne Prüfung des Namens)? ATarget nennt Richtung und
    /// Vorschlag, sonst AReason den Grund.</summary>
    class function Target(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TPromoteLookup; out ATarget: TPromoteTarget; out AReason: string): Boolean; static;
    /// <summary>Umwandlung an ARequest.Position mit dem Namen ARequest.Name.</summary>
    class function Execute(const AText: string; ATree: TSyntaxTree; const ARequest: TPromoteRequest;
      out AResult: TPromoteResult; out AReason: string): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Pascal.TreeCache,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditingPromoteVariableText = (IsCreatedAndFreedIn, CallsItselfAfterwardsAllCalls, IsNotUsedAnywhere,
    IsUsedInSeveralMethods, TheLocalRoutineAlreadyDeclares, NoTree, NoName, NotInARoutine, VariableOfALocalRoutine,
    ClassNotInTheFile, TypeOfUnknown, SeveralNamesInOneInline, UnsupportedForm, NoLocalVariable, NoMethod,
    NoFieldOfAClass, IsNotAFieldOf, NotPrivate, TypeUnknown, ThePropertyUses, IsInTheFormFile, IsAlsoUsedIn,
    IsUsedOutsideAMethod, IsUsedViaAnotherObject, IsUsedInALocal, ClassDeclarationCannotBeExtended,
    MethodNotFoundAfterThe, IsNotWrittenFirstOn, IsNotAValidName, ResultDoesNotParse, CallsItself, AlreadyDeclares,
    AlreadyMeansSomethingDifferentIn, RoutineWithoutBody, NeitherVariableNorInlineVariable,
    NeitherFieldNorLocalVariable, IsInAWith, AlreadyHasAMember, AlreadyInheritsAMember, ClassMethod, ConvertToField,
    ConvertToLocalVariable);

const
  cTexts: array[TEditingPromoteVariableText] of TAtlasText = (
    (De: '%s wird in %s erzeugt und freigegeben; als Feld überdauert der Verweis die Methode (nach der Freigabe auf ' +
      'nil setzen, z. B. mit FreeAndNil).';
     En: '%s is created and freed in %s; as a field the reference outlives the method (set it to nil after freeing, ' +
      'e.g. with FreeAndNil).'),
    (De: '%s ruft sich selbst auf; alle Aufrufe teilen sich danach das Feld.';
     En: '%s calls itself; afterwards all calls share the field.'),
    (De: ' wird nirgends benutzt'; En: ' is not used anywhere'),
    (De: ' wird in mehreren Methoden benutzt: '; En: ' is used in several methods: '),
    (De: 'die lokale Routine %s deklariert schon %s'; En: 'the local routine %s already declares %s'),
    (De: 'kein Baum'; En: 'no tree'),
    (De: 'kein Name'; En: 'no name'),
    (De: 'nicht in einer Routine'; En: 'not in a routine'),
    (De: 'Variable einer lokalen Routine'; En: 'variable of a local routine'),
    (De: 'Klasse %s nicht in der Datei'; En: 'Class %s not in the file'),
    (De: 'Typ von %s unbekannt'; En: 'Type of %s unknown'),
    (De: 'mehrere Namen in einer Inline-Deklaration'; En: 'several names in one inline declaration'),
    (De: 'nicht unterstützte Form'; En: 'unsupported form'),
    (De: 'keine lokale Variable'; En: 'no local variable'),
    (De: 'keine Methode'; En: 'no method'),
    (De: 'kein Feld einer Klasse'; En: 'no field of a class'),
    (De: ' ist kein Feld von '; En: ' is not a field of '),
    (De: 'nicht privat'; En: 'not private'),
    (De: 'Typ unbekannt'; En: 'type unknown'),
    (De: 'die Property %s nutzt '; En: 'the property %s uses '),
    (De: ' steht in der Formulardatei'; En: ' is in the form file'),
    (De: ' wird auch in %s benutzt'; En: ' is also used in %s'),
    (De: ' wird außerhalb einer Methode benutzt'; En: ' is used outside a method'),
    (De: ' wird über ein anderes Objekt benutzt'; En: ' is used via another object'),
    (De: ' wird in einer lokalen Routine benutzt'; En: ' is used in a local routine'),
    (De: 'Klassendeklaration nicht erweiterbar'; En: 'class declaration cannot be extended'),
    (De: 'Methode nach der Umwandlung nicht gefunden'; En: 'Method not found after the conversion'),
    (De: '%s wird in %s nicht auf jedem Weg zuerst geschrieben'; En: '%s is not written first on every path in %s'),
    (De: '"%s" ist kein gültiger Name'; En: '"%s" is not a valid name'),
    (De: 'Ergebnis parst nicht'; En: 'Result does not parse'),
    (De: ' ruft sich selbst auf'; En: ' calls itself'),
    (De: '%s deklariert schon %s'; En: '%s already declares %s'),
    (De: '%s bedeutet in %s schon etwas anderes'; En: '%s already means something different in %s'),
    (De: 'Routine ohne Rumpf'; En: 'routine without body'),
    (De: 'weder Variable noch Inline-Variable'; En: 'neither variable nor inline variable'),
    (De: 'weder Feld noch lokale Variable'; En: 'neither field nor local variable'),
    (De: ' steht in einem with'; En: ' is in a with'),
    (De: '%s hat schon ein Mitglied %s'; En: '%s already has a member %s'),
    (De: '%s erbt schon ein Mitglied %s'; En: '%s already inherits a member %s'),
    (De: 'Klassenmethode'; En: 'class method'),
    (De: 'In Feld umwandeln'; En: 'Convert to field'),
    (De: 'In lokale Variable umwandeln'; En: 'Convert to local variable'));

{$SCOPEDENUMS OFF}

class function TPromoteVariable.ToFieldTitle: string;
begin
  Result := cTexts[TEditingPromoteVariableText.ConvertToField].Text;
end;

class function TPromoteVariable.ToLocalTitle: string;
begin
  Result := cTexts[TEditingPromoteVariableText.ConvertToLocalVariable].Text;
end;

type
  /// <summary>Was an der Stelle umgewandelt wird.</summary>
  TPromotePlan = class
  public
    Text: string;
    Tree: TSyntaxTree;
    Lookup: TPromoteLookup;
    Lines: TLineTable;
    Tokens: TArray<TPascalToken>;
    Direction: TPromoteDirection;
    Name: string;
    TypeText: string;
    ClassName: string;
    Method: TSyntaxNode;
    TypeBody: TSyntaxNode;
    /// <summary>In Feld: die lokale Variable.</summary>
    Local: TRoutineLocal;
    /// <summary>In lokale Variable: die Felddeklaration.</summary>
    Field: TSyntaxNode;
    /// <summary>Verwendungen: Bezeichner bzw. Self.X (MemberAccess).</summary>
    References: TArray<TSyntaxNode>;
    Warnings: TArray<string>;
    function Fail(const AReason: string; out AOut: string): Boolean;
    function Analyze(const APosition: TTextPosition; out AReason: string): Boolean;
    function AnalyzeLocal(AOffset: Integer; out AReason: string): Boolean;
    /// <summary>Methode um AOffset (setzt Method und ClassName); '' = geht.</summary>
    function MethodIssue(AOffset: Integer): string;
    /// <summary>Art, Klasse und Typ der lokalen Variablen; '' = geht.</summary>
    function LocalIssue: string;
    function LocalTypeIssue: string;
    /// <summary>Meint der Bezeichner ANode die lokale Variable?</summary>
    function IsLocalReference(ANode: TSyntaxNode; const ALocals: TArray<TRoutineLocal>): Boolean;
    /// <summary>Verwendungen sammeln; erzeugt bzw. gibt die Methode die Variable frei?</summary>
    procedure CollectLocalReferences(const ALocals: TArray<TRoutineLocal>; out ACreated, AFreed: Boolean);
    function AnalyzeField(AOffset: Integer; out AReason: string): Boolean;
    /// <summary>Cursor auf der Felddeklaration in der Klasse.</summary>
    function DeclaredFieldIssue: string;
    /// <summary>Cursor auf einer Verwendung in einer Methode: das Feld der Klasse dieser Methode.</summary>
    function UsedFieldIssue(AOffset: Integer): string;
    /// <summary>Sichtbarkeit, class var, Typ, Property und Formulardatei.</summary>
    function FieldIssue: string;
    /// <summary>Verwendungen: nur in einer Methode der Klasse (setzt References und Method).</summary>
    function FieldUseIssue: string;
    function UseIssue(ANode, ATop: TSyntaxNode; out ASkip: Boolean): string;
    /// <summary>Verwendung in einer Methode einer anderen Klasse bzw. einer freien Routine.</summary>
    function ForeignUseIssue(ATop: TSyntaxNode; out ASkip: Boolean): string;
    function Build(const ANewName: string; const AStyle: TFormatStyle; ACheckName: Boolean;
      out AResult: TPromoteResult; out AReason: string): Boolean;
    function BuildField(const ANewName: string; const AStyle: TFormatStyle; ACheckName: Boolean;
      out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
    function FieldNameIssue(const ANewName: string): string;
    /// <summary>Deklaration der lokalen Variablen entfernen; ein Startwert bleibt als Zuweisung.</summary>
    procedure RemoveLocalDeclaration(const ANewName: string; var AEdits: TArray<TTextEdit>);
    function BuildLocal(const ANewName: string; const AStyle: TFormatStyle; ACheckName: Boolean;
      out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
    function WrittenFirst(const AResultText, ANewName: string; out AReason: string): Boolean;
  end;

{ Hilfen }

function Encloses(ANode: TSyntaxNode; AOffset: Integer): Boolean;
begin
  Result := (ANode <> nil) and (ANode.StartOffset <= AOffset) and (AOffset <= ANode.EndOffset);
end;

/// <summary>Nächste Routine über ANode; nil außerhalb.</summary>
function RoutineOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Äußerste Routine über ANode (die der Unit); nil außerhalb.</summary>
function TopRoutineOf(ANode: TSyntaxNode): TSyntaxNode;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  mNode := ANode;
  while mNode <> nil do
  begin
    if mNode.Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := mNode;
    end;
    mNode := mNode.Parent;
  end;
end;

/// <summary>Innerste Routine, die AOffset enthält; nil außerhalb.</summary>
function RoutineAtOffset(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  mFound: TSyntaxNode;
  mOffset: Integer;
begin
  mFound := nil;
  mOffset := AOffset;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := Encloses(ANode, mOffset);
      if Result and (ANode.Kind = TSyntaxKind.RoutineDecl) then
      begin
        mFound := ANode;
      end;
    end);
  Result := mFound;
end;

/// <summary>Innerster Knoten der Art AKind, der AOffset enthält; nil ohne.</summary>
function NodeAtOffset(ATree: TSyntaxTree; AOffset: Integer; AKind: TSyntaxKind): TSyntaxNode;
var
  mFound: TSyntaxNode;
  mOffset: Integer;
  mKind: TSyntaxKind;
begin
  mFound := nil;
  mOffset := AOffset;
  mKind := AKind;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := Encloses(ANode, mOffset);
      if Result and (ANode.Kind = mKind) then
      begin
        mFound := ANode;
      end;
    end);
  Result := mFound;
end;

/// <summary>Bezeichner-Token an AOffset (auch direkt dahinter); '' ohne.</summary>
function WordAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): string;
var
  mToken: TPascalToken;
begin
  Result := '';
  for mToken in ATokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Identifier) and (mToken.Offset <= AOffset) and
      (AOffset <= mToken.Offset + Length(mToken.Text)) then
    begin
      Exit(mToken.Text);
    end;
  end;
end;

/// <summary>Lokale Variable AName der Routine, deren Deklaration AOffset enthält oder die dort gilt; -1 ohne.
/// </summary>
function LocalAt(const ALocals: TArray<TRoutineLocal>; const AName: string; AOffset: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ALocals) do
  begin
    if SameText(ALocals[mIndex].Name, AName) and Encloses(ALocals[mIndex].Decl, AOffset) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := TRoutineLocals.IndexOf(ALocals, AName, AOffset);
end;

/// <summary>Deklariert ARoutine (Parameter, Variable, Konstante, lokale Routine) den Namen irgendwo?</summary>
function DeclaresAnywhere(const AText: string; ATree: TSyntaxTree; ARoutine: TSyntaxNode;
  const AName: string): Boolean;
var
  mLocal: TRoutineLocal;
  mIndex: Integer;
begin
  if TRoutineBody.BodyOf(ARoutine) <> nil then
  begin
    for mLocal in TRoutineLocals.Collect(AText, ATree, ARoutine) do
    begin
      if SameText(mLocal.Name, AName) then
      begin
        Exit(True);
      end;
    end;
  end;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if (ARoutine[mIndex].Kind = TSyntaxKind.RoutineDecl) and SameText(ARoutine[mIndex].Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Deklariert eine Routine zwischen ANode (ausschließlich) und AStop (ausschließlich) den Namen, der
/// an ANode gilt?</summary>
function ShadowedBelow(const AText: string; ATree: TSyntaxTree; ANode, AStop: TSyntaxNode;
  const AName: string): Boolean;
var
  mRoutine: TSyntaxNode;
begin
  mRoutine := RoutineOf(ANode);
  while (mRoutine <> nil) and (mRoutine <> AStop) do
  begin
    if (TRoutineBody.BodyOf(mRoutine) <> nil) and (LocalAt(TRoutineLocals.Collect(AText, ATree, mRoutine), AName,
      ANode.StartOffset) >= 0) then
    begin
      Exit(True);
    end;
    mRoutine := RoutineOf(mRoutine);
  end;
  Result := False;
end;

/// <summary>Alle Knoten der Art AKind unter ANode.</summary>
function NodesOf(ANode: TSyntaxNode; AKind: TSyntaxKind): TArray<TSyntaxNode>;
var
  mList: TList<TSyntaxNode>;
begin
  mList := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(ANode, AKind, mList);
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

/// <summary>Klassenmethode (class procedure, class function)?</summary>
function IsClassMethod(const ATokens: TArray<TPascalToken>; AMethod: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TRoutineBody.TokenAt(ATokens, AMethod.StartOffset);
  Result := (mIndex <= High(ATokens)) and ATokens[mIndex].IsKeyword('class');
end;

/// <summary>Ruft die Methode sich selbst auf (Bezeichner mit ihrem Namen im Rumpf)?</summary>
function IsRecursive(AMethod: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
  mShort: string;
begin
  mShort := TRoutineBody.ShortNameOf(AMethod.Name);
  for mNode in NodesOf(TRoutineBody.BodyOf(AMethod), TSyntaxKind.Identifier) do
  begin
    if SameText(mNode.Name, mShort) then
    begin
      Exit(True);
    end;
  end;
  for mNode in NodesOf(TRoutineBody.BodyOf(AMethod), TSyntaxKind.MemberAccess) do
  begin
    if SameText(mNode.Name, mShort) and (mNode[0].Kind = TSyntaxKind.Identifier) and SameText(mNode[0].Name, 'Self') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Startwert einer Inline-Variablen (letztes Kind, wenn es kein Typ ist); nil ohne.</summary>
function InitializerOf(ADecl: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ADecl.Kind = TSyntaxKind.InlineVar) and (ADecl.ChildCount > 0) and
    not (ADecl[ADecl.ChildCount - 1].Kind in TRoutineLocals.cTypeKinds) then
  begin
    Result := ADecl[ADecl.ChildCount - 1];
  end;
end;

/// <summary>Erzeugt AExpression ein Objekt (X.Create bzw. X.Create(…))?</summary>
function IsCreate(AExpression: TSyntaxNode): Boolean;
begin
  Result := (AExpression <> nil) and (((AExpression.Kind = TSyntaxKind.MemberAccess) and
    SameText(AExpression.Name, 'Create')) or ((AExpression.Kind = TSyntaxKind.Call) and
    (AExpression[0].Kind = TSyntaxKind.MemberAccess) and SameText(AExpression[0].Name, 'Create')));
end;

/// <summary>Gültiger Bezeichner, kein reserviertes Wort?</summary>
function IsValidName(const AName: string): Boolean;
begin
  Result := IsValidIdent(AName) and not TPascalLexer.IsReservedWord(AName);
end;

/// <summary>Variable bzw. Inline-Variable mit eigener Deklaration?</summary>
function IsPromotable(const ALocal: TRoutineLocal): Boolean;
begin
  Result := (ALocal.Kind = TRoutineLocalKind.Variable) or ((ALocal.Kind = TRoutineLocalKind.InlineVariable) and
    (ALocal.Decl.Kind = TSyntaxKind.InlineVar));
end;

/// <summary>Deklariert eine lokale Routine zwischen ARoutine und AMethod den Namen, der an AOffset gilt?</summary>
function InLocalRoutine(const AText: string; ATree: TSyntaxTree; ARoutine, AMethod: TSyntaxNode;
  const AName: string; AOffset: Integer): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := ARoutine;
  while mNode <> AMethod do
  begin
    if (TRoutineBody.BodyOf(mNode) <> nil) and (LocalAt(TRoutineLocals.Collect(AText, ATree, mNode), AName,
      AOffset) >= 0) then
    begin
      Exit(True);
    end;
    mNode := RoutineOf(mNode);
  end;
  Result := False;
end;

/// <summary>Bekommt der Bezeichner ANode ein neues Objekt zugewiesen (X := T.Create)?</summary>
function IsCreation(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  Result := (mParent.Kind = TSyntaxKind.AssignStatement) and (mParent[0] = ANode) and (mParent.ChildCount > 1) and
    IsCreate(mParent[1]);
end;

/// <summary>Wird der Bezeichner ANode freigegeben (X.Free, X.DisposeOf, FreeAndNil(X))?</summary>
function IsFreeing(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  Result := ((mParent.Kind = TSyntaxKind.MemberAccess) and MatchText(mParent.Name, ['Free', 'DisposeOf'])) or
    ((mParent.Kind = TSyntaxKind.Call) and (mParent[0] <> ANode) and SameText(mParent[0].Name, 'FreeAndNil'));
end;

function LocalWarnings(const ALocal: TRoutineLocal; AMethod: TSyntaxNode; ACreated, AFreed: Boolean):
  TArray<string>;
begin
  Result := nil;
  if ACreated and AFreed then
  begin
    Result := Result + [cTexts[TEditingPromoteVariableText.IsCreatedAndFreedIn].Fmt([ALocal.Name, AMethod.Name])];
  end;
  if IsRecursive(AMethod) then
  begin
    Result := Result + [cTexts[TEditingPromoteVariableText.CallsItselfAfterwardsAllCalls].Fmt([AMethod.Name])];
  end;
end;

/// <summary>Rumpf einer Klasse bzw. eines Records in einer Typdeklaration?</summary>
function IsClassTypeBody(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]) and
    (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.TypeDecl);
end;

/// <summary>Felddeklaration in ATypeBody, die AName enthält (die letzte); nil ohne.</summary>
function FieldNamed(ATypeBody: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ATypeBody.ChildCount - 1 do
  begin
    if (ATypeBody[mIndex].Kind = TSyntaxKind.Field) and
      (IndexText(AName, ATypeBody[mIndex].Name.Split([','])) >= 0) then
    begin
      Result := ATypeBody[mIndex];
    end;
  end;
end;

/// <summary>AName in der Schreibweise der Deklaration AField.</summary>
function NameInGroup(AField: TSyntaxNode; const AName: string): string;
var
  mName: string;
begin
  Result := AName;
  for mName in AField.Name.Split([',']) do
  begin
    if SameText(Trim(mName), AName) then
    begin
      Result := Trim(mName);
    end;
  end;
end;

/// <summary>Steht vor dem Feld AField "var" (class var)?</summary>
function IsClassVar(const ATokens: TArray<TPascalToken>; AField: TSyntaxNode): Boolean;
var
  mPrevious: Integer;
begin
  mPrevious := TRoutineBody.PreviousToken(ATokens, TRoutineBody.TokenAt(ATokens, AField.StartOffset));
  Result := (mPrevious >= 0) and ATokens[mPrevious].IsKeyword('var');
end;

/// <summary>Steht der Bezeichner AName unter den Tokens von ANode?</summary>
function MentionsName(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TRoutineBody.TokenAt(ATokens, ANode.StartOffset);
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ANode.EndOffset) do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[mIndex].Text, AName) then
    begin
      Exit(True);
    end;
    Inc(mIndex);
  end;
  Result := False;
end;

/// <summary>Property, die das Feld AName liest oder schreibt (auch in Nachfahren der Unit); nil ohne.</summary>
function PropertyUsing(ATree: TSyntaxTree; const ATokens: TArray<TPascalToken>; const AName: string): TSyntaxNode;
var
  mProperty: TSyntaxNode;
begin
  for mProperty in NodesOf(ATree.Root, TSyntaxKind.PropertyDecl) do
  begin
    if MentionsName(ATokens, mProperty, AName) then
    begin
      Exit(mProperty);
    end;
  end;
  Result := nil;
end;

function IsSelfAccess(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self');
end;

procedure AddOnce(var ANodes: TArray<TSyntaxNode>; ANode: TSyntaxNode);
var
  mNode: TSyntaxNode;
begin
  for mNode in ANodes do
  begin
    if mNode = ANode then
    begin
      Exit;
    end;
  end;
  ANodes := ANodes + [ANode];
end;

/// <summary>Genau eine Methode benutzt das Feld (AMethod); sonst der Grund.</summary>
function TopsIssue(const AName: string; const ATops: TArray<TSyntaxNode>; out AMethod: TSyntaxNode): string;
var
  mNames: TArray<string>;
  mTop: TSyntaxNode;
begin
  AMethod := nil;
  Result := '';
  if Length(ATops) = 0 then
  begin
    Result := AName + cTexts[TEditingPromoteVariableText.IsNotUsedAnywhere].Text;
  end
  else if Length(ATops) > 1 then
  begin
    mNames := nil;
    for mTop in ATops do
    begin
      mNames := mNames + [mTop.Name];
    end;
    Result := AName + cTexts[TEditingPromoteVariableText.IsUsedInSeveralMethods].Text + string.Join(', ', mNames);
  end
  else
  begin
    AMethod := ATops[0];
  end;
end;

/// <summary>Klassenmethode, with oder Rekursion in AMethod; '' = geht.</summary>
function FieldMethodIssue(const ATokens: TArray<TPascalToken>; AMethod: TSyntaxNode): string;
begin
  Result := '';
  if IsClassMethod(ATokens, AMethod) then
  begin
    Result := cTexts[TEditingPromoteVariableText.ClassMethod].Text;
  end
  else if TRoutineLocals.HasKind(AMethod, TSyntaxKind.WithStatement) then
  begin
    Result := 'with in ' + AMethod.Name;
  end
  else if IsRecursive(AMethod) then
  begin
    Result := AMethod.Name + cTexts[TEditingPromoteVariableText.CallsItself].Text;
  end;
end;

/// <summary>Lokale Routine in AMethod, die AName deklariert; nil ohne.</summary>
function NestedDeclarer(const AText: string; ATree: TSyntaxTree; AMethod: TSyntaxNode;
  const AName: string): TSyntaxNode;
var
  mRoutine: TSyntaxNode;
begin
  for mRoutine in NodesOf(AMethod, TSyntaxKind.RoutineDecl) do
  begin
    if (mRoutine <> AMethod) and DeclaresAnywhere(AText, ATree, mRoutine, AName) then
    begin
      Exit(mRoutine);
    end;
  end;
  Result := nil;
end;

/// <summary>Methode der Klasse AClassName, in der ein Bezeichner AName vorkommt; nil ohne.</summary>
function ClassUser(ATree: TSyntaxTree; const AClassName, AName: string): TSyntaxNode;
var
  mNode: TSyntaxNode;
begin
  for mNode in NodesOf(ATree.Root, TSyntaxKind.Identifier) do
  begin
    if SameText(mNode.Name, AName) and (TopRoutineOf(mNode) <> nil) and
      SameText(TRoutineBody.QualifierOf(TopRoutineOf(mNode).Name), AClassName) then
    begin
      Exit(TopRoutineOf(mNode));
    end;
  end;
  Result := nil;
end;

/// <summary>Hat AMethod eine lokale Variable bzw. einen Parameter AName?</summary>
function HasLocal(const AText: string; ATree: TSyntaxTree; AMethod: TSyntaxNode; const AName: string): Boolean;
var
  mLocal: TRoutineLocal;
begin
  for mLocal in TRoutineLocals.Collect(AText, ATree, AMethod) do
  begin
    if SameText(mLocal.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Umbenennen in ein Feld AName: Konflikte in AMethod und den Methoden der Klasse; '' = geht.</summary>
function FieldRenameIssue(const AText: string; ATree: TSyntaxTree; AMethod: TSyntaxNode;
  const AClassName, AName: string): string;
var
  mNested, mUser: TSyntaxNode;
begin
  Result := '';
  if HasLocal(AText, ATree, AMethod, AName) then
  begin
    Exit(cTexts[TEditingPromoteVariableText.AlreadyDeclares].Fmt([AMethod.Name, AName]));
  end;
  mNested := NestedDeclarer(AText, ATree, AMethod, AName);
  if mNested <> nil then
  begin
    Exit(cTexts[TEditingPromoteVariableText.TheLocalRoutineAlreadyDeclares].Fmt([mNested.Name, AName]));
  end;
  // In allen Methoden der Klasse meinte ein gleichnamiger Bezeichner danach das Feld.
  mUser := ClassUser(ATree, AClassName, AName);
  if mUser <> nil then
  begin
    Result := cTexts[TEditingPromoteVariableText.AlreadyMeansSomethingDifferentIn].Fmt([AName, mUser.Name]);
  end;
end;

/// <summary>Umbenennen in eine lokale Variable AName von AMethod; '' = geht.</summary>
function LocalRenameIssue(const AText: string; ATree: TSyntaxTree; AMethod: TSyntaxNode;
  const AName: string): string;
var
  mNested, mNode: TSyntaxNode;
begin
  if DeclaresAnywhere(AText, ATree, AMethod, AName) then
  begin
    Exit(cTexts[TEditingPromoteVariableText.AlreadyDeclares].Fmt([AMethod.Name, AName]));
  end;
  mNested := NestedDeclarer(AText, ATree, AMethod, AName);
  if mNested <> nil then
  begin
    Exit(cTexts[TEditingPromoteVariableText.TheLocalRoutineAlreadyDeclares].Fmt([mNested.Name, AName]));
  end;
  Result := '';
  for mNode in NodesOf(AMethod, TSyntaxKind.Identifier) do
  begin
    if SameText(mNode.Name, AName) then
    begin
      Exit(cTexts[TEditingPromoteVariableText.AlreadyMeansSomethingDifferentIn].Fmt([AName, AMethod.Name]));
    end;
  end;
end;

/// <summary>Inline-Deklaration ohne Startwert entfernen: die ganzen Zeilen, wenn sie allein darauf steht.
/// </summary>
function InlineRemoval(const AText: string; const ATokens: TArray<TPascalToken>; const ALines: TLineTable;
  ADecl: TSyntaxNode): TTextEdit;
var
  mStop, mLineStart, mLineEnd: Integer;
begin
  mStop := TRoutineBody.TokenAt(ATokens, ADecl.EndOffset);
  if (mStop <= High(ATokens)) and ATokens[mStop].IsSymbol(';') then
  begin
    mStop := ATokens[mStop].Offset + 1;
  end
  else
  begin
    mStop := ADecl.EndOffset;
  end;
  mLineStart := ALines.OffsetAt(TTextPosition.Create(ADecl.StartPos.Line, 0));
  mLineEnd := ALines.OffsetAt(TTextPosition.Create(ALines.PositionAt(mStop).Line + 1, 0));
  if (Trim(Copy(AText, mLineStart + 1, ADecl.StartOffset - mLineStart)) = '') and
    (Trim(Copy(AText, mStop + 1, mLineEnd - mStop)) = '') then
  begin
    Result := TTextEdit.Create(TTextRange.Create(ALines.PositionAt(mLineStart), ALines.PositionAt(mLineEnd)), '');
  end
  else
  begin
    Result := TTextEdit.Create(TTextRange.Create(ADecl.StartPos, ALines.PositionAt(mStop)), '');
  end;
end;

/// <summary>Steht AField allein in einem Sichtbarkeitsabschnitt, dessen Kopf eine eigene Zeile hat?</summary>
function AloneInSection(ATypeBody, AField: TSyntaxNode; AIndex: Integer): Boolean;
var
  mLastInSection: Boolean;
begin
  mLastInSection := (AIndex = ATypeBody.ChildCount - 1) or (ATypeBody[AIndex + 1].Kind = TSyntaxKind.Visibility);
  Result := (Pos(',', AField.Name) = 0) and (AIndex > 0) and mLastInSection and
    (ATypeBody[AIndex - 1].Kind = TSyntaxKind.Visibility) and
    (ATypeBody[AIndex - 1].EndPos.Line < AField.StartPos.Line);
end;

{ TPromoteLookup }

class function TPromoteLookup.FromTree(ATree: TSyntaxTree): TPromoteLookup;
begin
  Result := Default(TPromoteLookup);
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    Result.Flow := TFlowSignatures.FromTree(ATree.Root);
  end;
end;

{ TPromoteRequest }

class function TPromoteRequest.Create(const APosition: TTextPosition; const ALookup: TPromoteLookup;
  const AStyle: TFormatStyle; const AName: string): TPromoteRequest;
begin
  Result.Position := APosition;
  Result.Lookup := ALookup;
  Result.Style := AStyle;
  Result.Name := AName;
end;

{ TPromoteTarget }

function TPromoteTarget.Title: string;
begin
  if Direction = TPromoteDirection.ToField then
  begin
    Result := TPromoteVariable.ToFieldTitle;
  end
  else
  begin
    Result := TPromoteVariable.ToLocalTitle;
  end;
  Result := Format('%s (%s → %s)', [Result, Name, Suggested]);
end;

{ TPromotePlan }

function TPromotePlan.Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

function TPromotePlan.Analyze(const APosition: TTextPosition; out AReason: string): Boolean;
var
  mOffset: Integer;
begin
  AReason := '';
  if (Tree = nil) or (Tree.Root = nil) then
  begin
    Exit(Fail(cTexts[TEditingPromoteVariableText.NoTree].Text, AReason));
  end;
  Lines := TLineTable.Build(Text);
  Tokens := Tree.Tokens;
  mOffset := Lines.OffsetAt(APosition);
  Name := WordAt(Tokens, mOffset);
  if Name = '' then
  begin
    Exit(Fail(cTexts[TEditingPromoteVariableText.NoName].Text, AReason));
  end;
  // Feld in der Klasse oder lokale Variable bzw. Feld in einer Methode.
  if NodeAtOffset(Tree, mOffset, TSyntaxKind.Field) <> nil then
  begin
    Direction := TPromoteDirection.ToLocal;
    Exit(AnalyzeField(mOffset, AReason));
  end;
  Result := AnalyzeLocal(mOffset, AReason);
  if not Result and (Direction = TPromoteDirection.ToLocal) then
  begin
    Result := AnalyzeField(mOffset, AReason);
  end;
end;

function TPromotePlan.MethodIssue(AOffset: Integer): string;
var
  mRoutine: TSyntaxNode;
begin
  mRoutine := RoutineAtOffset(Tree, AOffset);
  if mRoutine = nil then
  begin
    Exit(cTexts[TEditingPromoteVariableText.NotInARoutine].Text);
  end;
  Method := TopRoutineOf(mRoutine);
  ClassName := TRoutineBody.QualifierOf(Method.Name);
  Result := '';
  // Lokal in einer lokalen Routine: kein Feld der Klasse.
  if InLocalRoutine(Text, Tree, mRoutine, Method, Name, AOffset) then
  begin
    Result := cTexts[TEditingPromoteVariableText.VariableOfALocalRoutine].Text;
  end
  else if TRoutineBody.BodyOf(Method) = nil then
  begin
    Result := cTexts[TEditingPromoteVariableText.RoutineWithoutBody].Text;
  end;
end;

function TPromotePlan.LocalTypeIssue: string;
begin
  TypeBody := TRoutineBody.TypeBody(Tree.Root, ClassName);
  if TypeBody = nil then
  begin
    Exit(cTexts[TEditingPromoteVariableText.ClassNotInTheFile].Fmt([ClassName]));
  end;
  TypeText := Local.TypeText;
  if (TypeText = '') and Assigned(Lookup.InlineType) then
  begin
    TypeText := Lookup.InlineType(Local);
  end;
  Result := '';
  if TypeText = '' then
  begin
    Result := cTexts[TEditingPromoteVariableText.TypeOfUnknown].Fmt([Local.Name]);
  end;
end;

function TPromotePlan.LocalIssue: string;
begin
  if not IsPromotable(Local) then
  begin
    Result := cTexts[TEditingPromoteVariableText.NeitherVariableNorInlineVariable].Text;
  end
  else if (Local.Kind = TRoutineLocalKind.InlineVariable) and (Pos(',', Local.Decl.Name) > 0) then
  begin
    Result := cTexts[TEditingPromoteVariableText.SeveralNamesInOneInline].Text;
  end
  else if IsClassMethod(Tokens, Method) then
  begin
    Result := cTexts[TEditingPromoteVariableText.ClassMethod].Text;
  end
  else if (Pos('<', ClassName) > 0) or TRoutineLocals.HasKind(Method, TSyntaxKind.WithStatement) then
  begin
    Result := cTexts[TEditingPromoteVariableText.UnsupportedForm].Text;
  end
  else
  begin
    Result := LocalTypeIssue;
  end;
end;

function TPromotePlan.IsLocalReference(ANode: TSyntaxNode; const ALocals: TArray<TRoutineLocal>): Boolean;
var
  mFound: Integer;
begin
  Result := SameText(ANode.Name, Local.Name) and not ShadowedBelow(Text, Tree, ANode, Method, Local.Name);
  if Result then
  begin
    mFound := TRoutineLocals.IndexOf(ALocals, Local.Name, ANode.StartOffset);
    Result := (mFound >= 0) and (ALocals[mFound].Decl = Local.Decl);
  end;
end;

procedure TPromotePlan.CollectLocalReferences(const ALocals: TArray<TRoutineLocal>; out ACreated, AFreed: Boolean);
var
  mNode: TSyntaxNode;
begin
  // Verwendungen: Bezeichner, die diese Variable meinen.
  References := nil;
  ACreated := False;
  AFreed := False;
  for mNode in NodesOf(Method, TSyntaxKind.Identifier) do
  begin
    if IsLocalReference(mNode, ALocals) then
    begin
      References := References + [mNode];
      ACreated := ACreated or IsCreation(mNode);
      AFreed := AFreed or IsFreeing(mNode);
    end;
  end;
  ACreated := ACreated or IsCreate(InitializerOf(Local.Decl));
end;

function TPromotePlan.AnalyzeLocal(AOffset: Integer; out AReason: string): Boolean;
var
  mLocals: TArray<TRoutineLocal>;
  mFound: Integer;
  mCreated, mFreed: Boolean;
begin
  Direction := TPromoteDirection.ToField;
  AReason := MethodIssue(AOffset);
  if AReason <> '' then
  begin
    Exit(False);
  end;
  mLocals := TRoutineLocals.Collect(Text, Tree, Method);
  mFound := LocalAt(mLocals, Name, AOffset);
  if mFound < 0 then
  begin
    // Kein lokaler Name: vielleicht ein Feld.
    Direction := TPromoteDirection.ToLocal;
    Exit(Fail(cTexts[TEditingPromoteVariableText.NoLocalVariable].Text, AReason));
  end;
  if ClassName = '' then
  begin
    Exit(Fail(cTexts[TEditingPromoteVariableText.NoMethod].Text, AReason));
  end;
  Local := mLocals[mFound];
  AReason := LocalIssue;
  Result := AReason = '';
  if Result then
  begin
    CollectLocalReferences(mLocals, mCreated, mFreed);
    Warnings := LocalWarnings(Local, Method, mCreated, mFreed);
  end;
end;

function TPromotePlan.DeclaredFieldIssue: string;
begin
  Result := '';
  TypeBody := Field.Parent;
  if IsClassTypeBody(TypeBody) then
  begin
    ClassName := TypeBody.Parent.Name;
  end
  else
  begin
    Result := cTexts[TEditingPromoteVariableText.NoFieldOfAClass].Text;
  end;
end;

function TPromotePlan.UsedFieldIssue(AOffset: Integer): string;
var
  mRoutine: TSyntaxNode;
begin
  mRoutine := RoutineAtOffset(Tree, AOffset);
  if mRoutine = nil then
  begin
    Exit(cTexts[TEditingPromoteVariableText.NeitherFieldNorLocalVariable].Text);
  end;
  ClassName := TRoutineBody.QualifierOf(TopRoutineOf(mRoutine).Name);
  if ClassName = '' then
  begin
    Exit(cTexts[TEditingPromoteVariableText.NoMethod].Text);
  end;
  TypeBody := TRoutineBody.TypeBody(Tree.Root, ClassName);
  Result := '';
  if TypeBody = nil then
  begin
    Result := cTexts[TEditingPromoteVariableText.ClassNotInTheFile].Fmt([ClassName]);
  end
  else
  begin
    Field := FieldNamed(TypeBody, Name);
    if Field = nil then
    begin
      Result := Name + cTexts[TEditingPromoteVariableText.IsNotAFieldOf].Text + ClassName;
    end;
  end;
end;

function TPromotePlan.FieldIssue: string;
var
  mProperty: TSyntaxNode;
begin
  Name := NameInGroup(Field, Name);
  Result := '';
  if Pos('<', ClassName) > 0 then
  begin
    Exit(cTexts[TEditingPromoteVariableText.UnsupportedForm].Text);
  end;
  if not MatchText(TRoutineBody.VisibilityOf(TypeBody, Field), ['private', 'strict private']) then
  begin
    Exit(cTexts[TEditingPromoteVariableText.NotPrivate].Text);
  end;
  if IsClassVar(Tokens, Field) then
  begin
    Exit('class var');
  end;
  TypeText := TRoutineLocals.TypeChildText(Text, Field);
  mProperty := PropertyUsing(Tree, Tokens, Name);
  if TypeText = '' then
  begin
    Result := cTexts[TEditingPromoteVariableText.TypeUnknown].Text;
  end
  else if mProperty <> nil then
  begin
    Result := cTexts[TEditingPromoteVariableText.ThePropertyUses].Fmt([mProperty.Name]) + Name;
  end
  else if Assigned(Lookup.InForm) and Lookup.InForm(Name) then
  begin
    Result := Name + cTexts[TEditingPromoteVariableText.IsInTheFormFile].Text;
  end;
end;

function TPromotePlan.ForeignUseIssue(ATop: TSyntaxNode; out ASkip: Boolean): string;
var
  mQualifier: string;
  mOther: TSyntaxNode;
begin
  // Methode einer anderen Klasse mit eigenem Feld gleichen Namens bzw. freie Routine ohne with: anderer Name.
  ASkip := True;
  Result := '';
  mQualifier := TRoutineBody.QualifierOf(ATop.Name);
  if mQualifier = '' then
  begin
    if TRoutineLocals.HasKind(ATop, TSyntaxKind.WithStatement) then
    begin
      Result := Name + cTexts[TEditingPromoteVariableText.IsInAWith].Text;
    end;
    Exit;
  end;
  mOther := TRoutineBody.TypeBody(Tree.Root, mQualifier);
  if (mOther = nil) or (IndexText(Name, TRoutineBody.MemberNames(mOther)) < 0) then
  begin
    Result := Name + cTexts[TEditingPromoteVariableText.IsAlsoUsedIn].Fmt([ATop.Name]);
  end;
end;

function TPromotePlan.UseIssue(ANode, ATop: TSyntaxNode; out ASkip: Boolean): string;
begin
  ASkip := False;
  Result := '';
  if ATop = nil then
  begin
    Result := Name + cTexts[TEditingPromoteVariableText.IsUsedOutsideAMethod].Text;
  end
  else if ANode.Kind = TSyntaxKind.MemberAccess then
  begin
    if not IsSelfAccess(ANode) or not SameText(TRoutineBody.QualifierOf(ATop.Name), ClassName) then
    begin
      Result := Name + cTexts[TEditingPromoteVariableText.IsUsedViaAnotherObject].Text;
    end;
  end
  else if ShadowedBelow(Text, Tree, ANode, nil, Name) then
  begin
    ASkip := True;
  end
  else if not SameText(TRoutineBody.QualifierOf(ATop.Name), ClassName) then
  begin
    Result := ForeignUseIssue(ATop, ASkip);
  end;
end;

function TPromotePlan.FieldUseIssue: string;
var
  mNode, mTop: TSyntaxNode;
  mTops: TArray<TSyntaxNode>;
  mSkip: Boolean;
begin
  References := nil;
  mTops := nil;
  for mNode in NodesOf(Tree.Root, TSyntaxKind.Identifier) + NodesOf(Tree.Root, TSyntaxKind.MemberAccess) do
  begin
    if not SameText(mNode.Name, Name) then
    begin
      Continue;
    end;
    mTop := TopRoutineOf(mNode);
    Result := UseIssue(mNode, mTop, mSkip);
    if (Result = '') and not mSkip and (RoutineOf(mNode) <> mTop) then
    begin
      Result := Name + cTexts[TEditingPromoteVariableText.IsUsedInALocal].Text;
    end;
    if Result <> '' then
    begin
      Exit;
    end;
    if not mSkip then
    begin
      References := References + [mNode];
      AddOnce(mTops, mTop);
    end;
  end;
  Result := TopsIssue(Name, mTops, Method);
end;

function TPromotePlan.AnalyzeField(AOffset: Integer; out AReason: string): Boolean;
begin
  Direction := TPromoteDirection.ToLocal;
  Field := NodeAtOffset(Tree, AOffset, TSyntaxKind.Field);
  if Field <> nil then
  begin
    AReason := DeclaredFieldIssue;
  end
  else
  begin
    AReason := UsedFieldIssue(AOffset);
  end;
  if AReason = '' then
  begin
    AReason := FieldIssue;
  end;
  if AReason = '' then
  begin
    AReason := FieldUseIssue;
  end;
  if AReason = '' then
  begin
    AReason := FieldMethodIssue(Tokens, Method);
  end;
  Result := AReason = '';
  if Result then
  begin
    Warnings := nil;
  end;
end;

function TPromotePlan.FieldNameIssue(const ANewName: string): string;
begin
  Result := '';
  if IndexText(ANewName, TRoutineBody.MemberNames(TypeBody)) >= 0 then
  begin
    Result := cTexts[TEditingPromoteVariableText.AlreadyHasAMember].Fmt([ClassName, ANewName]);
  end
  else if Assigned(Lookup.MemberExists) and Lookup.MemberExists(ClassName, ANewName, TypeBody.StartOffset) then
  begin
    Result := cTexts[TEditingPromoteVariableText.AlreadyInheritsAMember].Fmt([ClassName, ANewName]);
  end
  else if not SameText(ANewName, Local.Name) then
  begin
    Result := FieldRenameIssue(Text, Tree, Method, ClassName, ANewName);
  end;
end;

procedure TPromotePlan.RemoveLocalDeclaration(const ANewName: string; var AEdits: TArray<TTextEdit>);
var
  mInitializer: TSyntaxNode;
begin
  if Local.Kind = TRoutineLocalKind.Variable then
  begin
    TRoutineLocals.RemoveVariables(Tree, Local.Decl, [Local.Name], AEdits);
    Exit;
  end;
  // Inline: mit Startwert bleibt die Zuweisung, sonst entfällt die Anweisung.
  mInitializer := InitializerOf(Local.Decl);
  if mInitializer <> nil then
  begin
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(Local.Decl.StartPos, mInitializer.StartPos),
      ANewName + ' := ')];
  end
  else
  begin
    AEdits := AEdits + [InlineRemoval(Text, Tokens, Lines, Local.Decl)];
  end;
end;

function TPromotePlan.BuildField(const ANewName: string; const AStyle: TFormatStyle; ACheckName: Boolean;
  out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mNode: TSyntaxNode;
  mEdit: TTextEdit;
begin
  AEdits := nil;
  AReason := '';
  if ACheckName then
  begin
    AReason := FieldNameIssue(ANewName);
  end;
  if AReason <> '' then
  begin
    Exit(False);
  end;
  if not TRoutineBody.FieldDeclaration(Text, Tree, TypeBody, ANewName + ': ' + TypeText + ';', AStyle, mEdit) then
  begin
    Exit(Fail(cTexts[TEditingPromoteVariableText.ClassDeclarationCannotBeExtended].Text, AReason));
  end;
  AEdits := AEdits + [mEdit];
  RemoveLocalDeclaration(ANewName, AEdits);
  if not SameStr(ANewName, Local.Name) then
  begin
    for mNode in References do
    begin
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(mNode.StartPos, mNode.EndPos), ANewName)];
    end;
  end;
  Result := True;
end;

function TPromotePlan.BuildLocal(const ANewName: string; const AStyle: TFormatStyle; ACheckName: Boolean;
  out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  AEdits := nil;
  AReason := '';
  if ACheckName and not SameText(ANewName, Name) then
  begin
    AReason := LocalRenameIssue(Text, Tree, Method, ANewName);
  end;
  if AReason <> '' then
  begin
    Exit(False);
  end;
  TRoutineLocals.RemoveVariables(Tree, Field, [Name], AEdits);
  // War es das einzige Mitglied des Abschnitts, entfällt auch die Sichtbarkeit.
  mIndex := 0;
  while TypeBody[mIndex] <> Field do
  begin
    Inc(mIndex);
  end;
  if AloneInSection(TypeBody, Field, mIndex) then
  begin
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(TypeBody[mIndex - 1].StartPos.Line, 0,
      TypeBody[mIndex - 1].EndPos.Line + 1, 0), '')];
  end;
  AEdits := AEdits + [TRoutineBody.AddVariable(Text, Method, ANewName, TypeText, AStyle)];
  for mNode in References do
  begin
    if (mNode.Kind = TSyntaxKind.MemberAccess) or not SameStr(mNode.Name, ANewName) then
    begin
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(mNode.StartPos, mNode.EndPos), ANewName)];
    end;
  end;
  Result := True;
end;

function TPromotePlan.WrittenFirst(const AResultText, ANewName: string; out AReason: string): Boolean;
var
  mCheck: TSyntaxTree;
  mIndex: Integer;
  mSection, mRoutine: TSyntaxNode;
  mGraph: TControlFlowGraph;
  mAnswer: TFlowAnswer;
begin
  // Am umgewandelten Text: Die lokale Variable muss auf jedem Weg geschrieben werden, bevor sie gelesen wird.
  mCheck := TSyntaxTreeCache.Parse(AResultText);
  try
    mSection := mCheck.Root.FindChild(TSyntaxKind.ImplementationSection);
    mRoutine := nil;
    if mSection <> nil then
    begin
      for mIndex := 0 to mSection.ChildCount - 1 do
      begin
        if (mSection[mIndex].Kind = TSyntaxKind.RoutineDecl) and SameText(mSection[mIndex].Name, Method.Name) then
        begin
          mRoutine := mSection[mIndex];
        end;
      end;
    end;
    if mRoutine = nil then
    begin
      Exit(Fail(cTexts[TEditingPromoteVariableText.MethodNotFoundAfterThe].Text, AReason));
    end;
    mGraph := TControlFlowGraph.Build(mRoutine, TFlowSignatures.FromTree(mCheck.Root));
    try
      mAnswer := TFlowAnswer.Unknown;
      if mGraph.Complete then
      begin
        mAnswer := mGraph.MayReadBeforeWrite(ANewName);
      end;
    finally
      mGraph.Free;
    end;
    if mAnswer <> TFlowAnswer.No then
    begin
      Exit(Fail(cTexts[TEditingPromoteVariableText.IsNotWrittenFirstOn].Fmt([Name, Method.Name]), AReason));
    end;
    Result := True;
  finally
    mCheck.Free;
  end;
end;

function TPromotePlan.Build(const ANewName: string; const AStyle: TFormatStyle; ACheckName: Boolean;
  out AResult: TPromoteResult; out AReason: string): Boolean;
var
  mEdits: TArray<TTextEdit>;
  mDone: string;
  mCheck: TSyntaxTree;
begin
  AResult := Default(TPromoteResult);
  if not IsValidName(ANewName) then
  begin
    Exit(Fail(cTexts[TEditingPromoteVariableText.IsNotAValidName].Fmt([ANewName]), AReason));
  end;
  if Direction = TPromoteDirection.ToField then
  begin
    Result := BuildField(ANewName, AStyle, ACheckName, mEdits, AReason);
  end
  else
  begin
    Result := BuildLocal(ANewName, AStyle, ACheckName, mEdits, AReason);
  end;
  if not Result then
  begin
    Exit;
  end;
  mDone := TChangeSignature.ApplyEdits(Text, mEdits);
  mCheck := TSyntaxTreeCache.Parse(mDone);
  try
    if Length(mCheck.Diagnostics) > 0 then
    begin
      Exit(Fail(cTexts[TEditingPromoteVariableText.ResultDoesNotParse].Text, AReason));
    end;
  finally
    mCheck.Free;
  end;
  if (Direction = TPromoteDirection.ToLocal) and not WrittenFirst(mDone, ANewName, AReason) then
  begin
    Exit(False);
  end;
  AResult.Edits := mEdits;
  AResult.Warnings := Warnings;
  AResult.Places := Length(References) + 2;
end;

{ TPromoteVariable }

class function TPromoteVariable.FieldName(const ALocal: string): string;
begin
  Result := ALocal;
  if (Length(Result) > 1) and CharInSet(Result[1], ['L', 'm']) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
  if Result <> '' then
  begin
    Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
  end;
  Result := 'F' + Result;
end;

class function TPromoteVariable.LocalName(const AField: string): string;
begin
  Result := AField;
  if (Length(Result) > 1) and (Result[1] = 'F') and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
  if Result <> '' then
  begin
    Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
  end;
  Result := 'L' + Result;
end;

class function TPromoteVariable.Target(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TPromoteLookup; out ATarget: TPromoteTarget; out AReason: string): Boolean;
var
  mPlan: TPromotePlan;
  mProbe: TPromoteResult;
begin
  ATarget := Default(TPromoteTarget);
  mPlan := TPromotePlan.Create;
  try
    mPlan.Text := AText;
    mPlan.Tree := ATree;
    mPlan.Lookup := ALookup;
    Result := mPlan.Analyze(APosition, AReason);
    if not Result then
    begin
      Exit;
    end;
    ATarget.Direction := mPlan.Direction;
    ATarget.Name := mPlan.Name;
    if mPlan.Direction = TPromoteDirection.ToField then
    begin
      ATarget.Suggested := FieldName(mPlan.Name);
    end
    else
    begin
      ATarget.Suggested := LocalName(mPlan.Name);
      // Datenfluss mit einem Namen, den es sicher nicht gibt.
      Result := mPlan.Build(TRoutineBody.UniqueName(mPlan.Tokens, 'AtlasPromoteProbe'), TFormatStyle.Default, False,
        mProbe, AReason);
    end;
  finally
    mPlan.Free;
  end;
end;

class function TPromoteVariable.Execute(const AText: string; ATree: TSyntaxTree; const ARequest: TPromoteRequest;
  out AResult: TPromoteResult; out AReason: string): Boolean;
var
  mPlan: TPromotePlan;
begin
  AResult := Default(TPromoteResult);
  mPlan := TPromotePlan.Create;
  try
    mPlan.Text := AText;
    mPlan.Tree := ATree;
    mPlan.Lookup := ARequest.Lookup;
    Result := mPlan.Analyze(ARequest.Position, AReason) and mPlan.Build(Trim(ARequest.Name), ARequest.Style, True,
      AResult, AReason);
  finally
    mPlan.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.PromoteVariable', cTexts);

end.
