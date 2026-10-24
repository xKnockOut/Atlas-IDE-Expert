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

  TPromoteVariable = class
  public const
    ToFieldTitle = 'In Feld umwandeln';
    ToLocalTitle = 'In lokale Variable umwandeln';
  public
    /// <summary>F + Name ohne L- bzw. m-Präfix: LLineNo → FLineNo, mCount → FCount, Total → FTotal.</summary>
    class function FieldName(const ALocal: string): string; static;
    /// <summary>L + Name ohne F-Präfix: FLineNo → LLineNo.</summary>
    class function LocalName(const AField: string): string; static;
    /// <summary>Geht eine Umwandlung an APosition (ohne Prüfung des Namens)? ATarget nennt Richtung und
    /// Vorschlag, sonst AReason den Grund.</summary>
    class function Target(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TPromoteLookup; out ATarget: TPromoteTarget; out AReason: string): Boolean; static;
    /// <summary>Umwandlung an APosition mit dem Namen AName.</summary>
    class function Execute(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TPromoteLookup; const AStyle: TFormatStyle; const AName: string; out AResult: TPromoteResult;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.ChangeSignature;

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
    function AnalyzeField(AOffset: Integer; out AReason: string): Boolean;
    function Build(const ANewName: string; const AStyle: TFormatStyle; ACheckName: Boolean;
      out AResult: TPromoteResult; out AReason: string): Boolean;
    function BuildField(const ANewName: string; const AStyle: TFormatStyle; ACheckName: Boolean;
      out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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
    Result := Result.Parent;
end;

/// <summary>Äußerste Routine über ANode (die der Unit); nil außerhalb.</summary>
function TopRoutineOf(ANode: TSyntaxNode): TSyntaxNode;
var
  Node: TSyntaxNode;
begin
  Result := nil;
  Node := ANode;
  while Node <> nil do
  begin
    if Node.Kind = TSyntaxKind.RoutineDecl then
      Result := Node;
    Node := Node.Parent;
  end;
end;

/// <summary>Innerste Routine, die AOffset enthält; nil außerhalb.</summary>
function RoutineAtOffset(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
  Offset: Integer;
begin
  Found := nil;
  Offset := AOffset;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := Encloses(ANode, Offset);
      if Result and (ANode.Kind = TSyntaxKind.RoutineDecl) then
        Found := ANode;
    end);
  Result := Found;
end;

/// <summary>Innerster Knoten der Art AKind, der AOffset enthält; nil ohne.</summary>
function NodeAtOffset(ATree: TSyntaxTree; AOffset: Integer; AKind: TSyntaxKind): TSyntaxNode;
var
  Found: TSyntaxNode;
  Offset: Integer;
  Kind: TSyntaxKind;
begin
  Found := nil;
  Offset := AOffset;
  Kind := AKind;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := Encloses(ANode, Offset);
      if Result and (ANode.Kind = Kind) then
        Found := ANode;
    end);
  Result := Found;
end;

/// <summary>Bezeichner-Token an AOffset (auch direkt dahinter); '' ohne.</summary>
function WordAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): string;
var
  Token: TPascalToken;
begin
  Result := '';
  for Token in ATokens do
    if (Token.Kind = TPascalTokenKind.Identifier) and (Token.Offset <= AOffset) and
      (AOffset <= Token.Offset + Length(Token.Text)) then
      Exit(Token.Text);
end;

/// <summary>Lokale Variable AName der Routine, deren Deklaration AOffset enthält oder die dort gilt; -1 ohne.
/// </summary>
function LocalAt(const ALocals: TArray<TRoutineLocal>; const AName: string; AOffset: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ALocals) do
    if SameText(ALocals[Index].Name, AName) and Encloses(ALocals[Index].Decl, AOffset) then
      Exit(Index);
  Result := TRoutineLocals.IndexOf(ALocals, AName, AOffset);
end;

/// <summary>Deklariert ARoutine (Parameter, Variable, Konstante, lokale Routine) den Namen irgendwo?</summary>
function DeclaresAnywhere(const AText: string; ATree: TSyntaxTree; ARoutine: TSyntaxNode;
  const AName: string): Boolean;
var
  Local: TRoutineLocal;
  Index: Integer;
begin
  if TRoutineBody.BodyOf(ARoutine) <> nil then
    for Local in TRoutineLocals.Collect(AText, ATree, ARoutine) do
      if SameText(Local.Name, AName) then
        Exit(True);
  for Index := 0 to ARoutine.ChildCount - 1 do
    if (ARoutine[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(ARoutine[Index].Name, AName) then
      Exit(True);
  Result := False;
end;

/// <summary>Deklariert eine Routine zwischen ANode (ausschließlich) und AStop (ausschließlich) den Namen, der
/// an ANode gilt?</summary>
function ShadowedBelow(const AText: string; ATree: TSyntaxTree; ANode, AStop: TSyntaxNode;
  const AName: string): Boolean;
var
  Routine: TSyntaxNode;
begin
  Routine := RoutineOf(ANode);
  while (Routine <> nil) and (Routine <> AStop) do
  begin
    if (TRoutineBody.BodyOf(Routine) <> nil) and (LocalAt(TRoutineLocals.Collect(AText, ATree, Routine), AName,
      ANode.StartOffset) >= 0) then
      Exit(True);
    Routine := RoutineOf(Routine);
  end;
  Result := False;
end;

/// <summary>Alle Knoten der Art AKind unter ANode.</summary>
function NodesOf(ANode: TSyntaxNode; AKind: TSyntaxKind): TArray<TSyntaxNode>;
var
  List: TList<TSyntaxNode>;
begin
  List := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(ANode, AKind, List);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

/// <summary>Klassenmethode (class procedure, class function)?</summary>
function IsClassMethod(const ATokens: TArray<TPascalToken>; AMethod: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := TRoutineBody.TokenAt(ATokens, AMethod.StartOffset);
  Result := (Index <= High(ATokens)) and ATokens[Index].IsKeyword('class');
end;

/// <summary>Ruft die Methode sich selbst auf (Bezeichner mit ihrem Namen im Rumpf)?</summary>
function IsRecursive(AMethod: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
  Short: string;
begin
  Short := TRoutineBody.ShortNameOf(AMethod.Name);
  for Node in NodesOf(TRoutineBody.BodyOf(AMethod), TSyntaxKind.Identifier) do
    if SameText(Node.Name, Short) then
      Exit(True);
  for Node in NodesOf(TRoutineBody.BodyOf(AMethod), TSyntaxKind.MemberAccess) do
    if SameText(Node.Name, Short) and (Node[0].Kind = TSyntaxKind.Identifier) and SameText(Node[0].Name, 'Self') then
      Exit(True);
  Result := False;
end;

/// <summary>Startwert einer Inline-Variablen (letztes Kind, wenn es kein Typ ist); nil ohne.</summary>
function InitializerOf(ADecl: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ADecl.Kind = TSyntaxKind.InlineVar) and (ADecl.ChildCount > 0) and
    not (ADecl[ADecl.ChildCount - 1].Kind in TRoutineLocals.TypeKinds) then
    Result := ADecl[ADecl.ChildCount - 1];
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

{ TPromoteLookup }

class function TPromoteLookup.FromTree(ATree: TSyntaxTree): TPromoteLookup;
begin
  Result := Default(TPromoteLookup);
  if (ATree <> nil) and (ATree.Root <> nil) then
    Result.Flow := TFlowSignatures.FromTree(ATree.Root);
end;

{ TPromoteTarget }

function TPromoteTarget.Title: string;
begin
  if Direction = TPromoteDirection.ToField then
    Result := TPromoteVariable.ToFieldTitle
  else
    Result := TPromoteVariable.ToLocalTitle;
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
  Offset: Integer;
begin
  AReason := '';
  if (Tree = nil) or (Tree.Root = nil) then
    Exit(Fail('kein Baum', AReason));
  Lines := TLineTable.Build(Text);
  Tokens := Tree.Tokens;
  Offset := Lines.OffsetAt(APosition);
  Name := WordAt(Tokens, Offset);
  if Name = '' then
    Exit(Fail('kein Name', AReason));
  // Feld in der Klasse oder lokale Variable bzw. Feld in einer Methode.
  if NodeAtOffset(Tree, Offset, TSyntaxKind.Field) <> nil then
  begin
    Direction := TPromoteDirection.ToLocal;
    Exit(AnalyzeField(Offset, AReason));
  end;
  Result := AnalyzeLocal(Offset, AReason);
  if not Result and (Direction = TPromoteDirection.ToLocal) then
    Result := AnalyzeField(Offset, AReason);
end;

function TPromotePlan.AnalyzeLocal(AOffset: Integer; out AReason: string): Boolean;
var
  Routine, Node, Parent: TSyntaxNode;
  Locals: TArray<TRoutineLocal>;
  Found: Integer;
  Created, Freed: Boolean;
begin
  Direction := TPromoteDirection.ToField;
  Routine := RoutineAtOffset(Tree, AOffset);
  if Routine = nil then
    Exit(Fail('nicht in einer Routine', AReason));
  Method := TopRoutineOf(Routine);
  ClassName := TRoutineBody.QualifierOf(Method.Name);
  // Lokal in einer lokalen Routine: kein Feld der Klasse.
  Node := Routine;
  while Node <> Method do
  begin
    if (TRoutineBody.BodyOf(Node) <> nil) and (LocalAt(TRoutineLocals.Collect(Text, Tree, Node), Name,
      AOffset) >= 0) then
      Exit(Fail('Variable einer lokalen Routine', AReason));
    Node := RoutineOf(Node);
  end;
  if TRoutineBody.BodyOf(Method) = nil then
    Exit(Fail('Routine ohne Rumpf', AReason));
  Locals := TRoutineLocals.Collect(Text, Tree, Method);
  Found := LocalAt(Locals, Name, AOffset);
  if Found < 0 then
  begin
    // Kein lokaler Name: vielleicht ein Feld.
    Direction := TPromoteDirection.ToLocal;
    Exit(Fail('keine lokale Variable', AReason));
  end;
  if ClassName = '' then
    Exit(Fail('keine Methode', AReason));
  Local := Locals[Found];
  if not ((Local.Kind = TRoutineLocalKind.Variable) or ((Local.Kind = TRoutineLocalKind.InlineVariable) and
    (Local.Decl.Kind = TSyntaxKind.InlineVar))) then
    Exit(Fail('weder Variable noch Inline-Variable', AReason));
  if (Local.Kind = TRoutineLocalKind.InlineVariable) and (Pos(',', Local.Decl.Name) > 0) then
    Exit(Fail('mehrere Namen in einer Inline-Deklaration', AReason));
  if IsClassMethod(Tokens, Method) then
    Exit(Fail('Klassenmethode', AReason));
  if (Pos('<', ClassName) > 0) or TRoutineLocals.HasKind(Method, TSyntaxKind.WithStatement) then
    Exit(Fail('nicht unterstützte Form', AReason));
  TypeBody := TRoutineBody.TypeBody(Tree.Root, ClassName);
  if TypeBody = nil then
    Exit(Fail('Klasse ' + ClassName + ' nicht in der Datei', AReason));
  TypeText := Local.TypeText;
  if (TypeText = '') and Assigned(Lookup.InlineType) then
    TypeText := Lookup.InlineType(Local);
  if TypeText = '' then
    Exit(Fail('Typ von ' + Local.Name + ' unbekannt', AReason));
  // Verwendungen: Bezeichner, die diese Variable meinen.
  References := nil;
  Created := False;
  Freed := False;
  for Node in NodesOf(Method, TSyntaxKind.Identifier) do
  begin
    if not SameText(Node.Name, Local.Name) or ShadowedBelow(Text, Tree, Node, Method, Local.Name) then
      Continue;
    Found := TRoutineLocals.IndexOf(Locals, Local.Name, Node.StartOffset);
    if (Found < 0) or (Locals[Found].Decl <> Local.Decl) then
      Continue;
    References := References + [Node];
    Parent := Node.Parent;
    if (Parent.Kind = TSyntaxKind.AssignStatement) and (Parent[0] = Node) and (Parent.ChildCount > 1) and
      IsCreate(Parent[1]) then
      Created := True;
    if ((Parent.Kind = TSyntaxKind.MemberAccess) and MatchText(Parent.Name, ['Free', 'DisposeOf'])) or
      ((Parent.Kind = TSyntaxKind.Call) and (Parent[0] <> Node) and SameText(Parent[0].Name, 'FreeAndNil')) then
      Freed := True;
  end;
  if IsCreate(InitializerOf(Local.Decl)) then
    Created := True;
  Warnings := nil;
  if Created and Freed then
    Warnings := Warnings + [Format('%s wird in %s erzeugt und freigegeben; als Feld überdauert der Verweis die ' +
      'Methode (nach der Freigabe auf nil setzen, z. B. mit FreeAndNil).', [Local.Name, Method.Name])];
  if IsRecursive(Method) then
    Warnings := Warnings + [Format('%s ruft sich selbst auf; alle Aufrufe teilen sich danach das Feld.',
      [Method.Name])];
  Result := True;
end;

function TPromotePlan.AnalyzeField(AOffset: Integer; out AReason: string): Boolean;
var
  Node, Routine, Top, Other, Property_: TSyntaxNode;
  Index, Last: Integer;
  Found, Names: TArray<string>;
  Previous: Integer;
  Tops: TArray<TSyntaxNode>;
begin
  Direction := TPromoteDirection.ToLocal;
  Field := NodeAtOffset(Tree, AOffset, TSyntaxKind.Field);
  if Field <> nil then
  begin
    TypeBody := Field.Parent;
    if (TypeBody = nil) or not (TypeBody.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]) or
      (TypeBody.Parent = nil) or (TypeBody.Parent.Kind <> TSyntaxKind.TypeDecl) then
      Exit(Fail('kein Feld einer Klasse', AReason));
    ClassName := TypeBody.Parent.Name;
  end
  else
  begin
    // Verwendung in einer Methode: das Feld der Klasse dieser Methode.
    Routine := RoutineAtOffset(Tree, AOffset);
    if Routine = nil then
      Exit(Fail('weder Feld noch lokale Variable', AReason));
    ClassName := TRoutineBody.QualifierOf(TopRoutineOf(Routine).Name);
    if ClassName = '' then
      Exit(Fail('keine Methode', AReason));
    TypeBody := TRoutineBody.TypeBody(Tree.Root, ClassName);
    if TypeBody = nil then
      Exit(Fail('Klasse ' + ClassName + ' nicht in der Datei', AReason));
    for Index := 0 to TypeBody.ChildCount - 1 do
      if (TypeBody[Index].Kind = TSyntaxKind.Field) and (IndexText(Name, TypeBody[Index].Name.Split([','])) >= 0) then
        Field := TypeBody[Index];
    if Field = nil then
      Exit(Fail(Name + ' ist kein Feld von ' + ClassName, AReason));
  end;
  Names := Field.Name.Split([',']);
  for Index := 0 to High(Names) do
    if SameText(Trim(Names[Index]), Name) then
      Name := Trim(Names[Index]);
  if (Pos('<', ClassName) > 0) then
    Exit(Fail('nicht unterstützte Form', AReason));
  if not MatchText(TRoutineBody.VisibilityOf(TypeBody, Field), ['private', 'strict private']) then
    Exit(Fail('nicht privat', AReason));
  Previous := TRoutineBody.PreviousToken(Tokens, TRoutineBody.TokenAt(Tokens, Field.StartOffset));
  if (Previous >= 0) and Tokens[Previous].IsKeyword('var') then
    Exit(Fail('class var', AReason));
  TypeText := TRoutineLocals.TypeChildText(Text, Field);
  if TypeText = '' then
    Exit(Fail('Typ unbekannt', AReason));
  // Property, die das Feld liest oder schreibt (auch in Nachfahren der Unit).
  for Property_ in NodesOf(Tree.Root, TSyntaxKind.PropertyDecl) do
  begin
    Index := TRoutineBody.TokenAt(Tokens, Property_.StartOffset);
    while (Index <= High(Tokens)) and (Tokens[Index].Offset < Property_.EndOffset) do
    begin
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, Name) then
        Exit(Fail('die Property ' + Property_.Name + ' nutzt ' + Name, AReason));
      Inc(Index);
    end;
  end;
  if Assigned(Lookup.InForm) and Lookup.InForm(Name) then
    Exit(Fail(Name + ' steht in der Formulardatei', AReason));
  // Verwendungen: nur in einer Methode der Klasse.
  References := nil;
  Tops := nil;
  for Node in NodesOf(Tree.Root, TSyntaxKind.Identifier) + NodesOf(Tree.Root, TSyntaxKind.MemberAccess) do
  begin
    if not SameText(Node.Name, Name) then
      Continue;
    Top := TopRoutineOf(Node);
    if Top = nil then
      Exit(Fail(Name + ' wird außerhalb einer Methode benutzt', AReason));
    if Node.Kind = TSyntaxKind.MemberAccess then
    begin
      if (Node[0].Kind <> TSyntaxKind.Identifier) or not SameText(Node[0].Name, 'Self') or
        not SameText(TRoutineBody.QualifierOf(Top.Name), ClassName) then
        Exit(Fail(Name + ' wird über ein anderes Objekt benutzt', AReason));
    end
    else
    begin
      if ShadowedBelow(Text, Tree, Node, nil, Name) then
        Continue;
      if not SameText(TRoutineBody.QualifierOf(Top.Name), ClassName) then
      begin
        // Methode einer anderen Klasse mit eigenem Feld gleichen Namens bzw. freie Routine ohne with: anderer Name.
        if TRoutineBody.QualifierOf(Top.Name) = '' then
        begin
          if TRoutineLocals.HasKind(Top, TSyntaxKind.WithStatement) then
            Exit(Fail(Name + ' steht in einem with', AReason));
          Continue;
        end;
        Other := TRoutineBody.TypeBody(Tree.Root, TRoutineBody.QualifierOf(Top.Name));
        if (Other <> nil) and (IndexText(Name, TRoutineBody.MemberNames(Other)) >= 0) then
          Continue;
        Exit(Fail(Name + ' wird auch in ' + Top.Name + ' benutzt', AReason));
      end;
    end;
    if RoutineOf(Node) <> Top then
      Exit(Fail(Name + ' wird in einer lokalen Routine benutzt', AReason));
    References := References + [Node];
    Last := High(Tops);
    if (Last < 0) or (Tops[Last] <> Top) then
    begin
      for Index := 0 to Last do
        if Tops[Index] = Top then
          Last := -2;
      if Last <> -2 then
        Tops := Tops + [Top];
    end;
  end;
  if Length(Tops) = 0 then
    Exit(Fail(Name + ' wird nirgends benutzt', AReason));
  if Length(Tops) > 1 then
  begin
    Found := nil;
    for Node in Tops do
      Found := Found + [Node.Name];
    Exit(Fail(Name + ' wird in mehreren Methoden benutzt: ' + string.Join(', ', Found), AReason));
  end;
  Method := Tops[0];
  if IsClassMethod(Tokens, Method) then
    Exit(Fail('Klassenmethode', AReason));
  if TRoutineLocals.HasKind(Method, TSyntaxKind.WithStatement) then
    Exit(Fail('with in ' + Method.Name, AReason));
  if IsRecursive(Method) then
    Exit(Fail(Method.Name + ' ruft sich selbst auf', AReason));
  Warnings := nil;
  Result := True;
end;

function TPromotePlan.BuildField(const ANewName: string; const AStyle: TFormatStyle; ACheckName: Boolean;
  out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Node, Initializer, Routine: TSyntaxNode;
  Edit: TTextEdit;
  Local_: TRoutineLocal;
  Stop, LineStart, LineEnd: Integer;
begin
  AEdits := nil;
  if ACheckName then
  begin
    if IndexText(ANewName, TRoutineBody.MemberNames(TypeBody)) >= 0 then
      Exit(Fail(Format('%s hat schon ein Mitglied %s', [ClassName, ANewName]), AReason));
    if Assigned(Lookup.MemberExists) and Lookup.MemberExists(ClassName, ANewName, TypeBody.StartOffset) then
      Exit(Fail(Format('%s erbt schon ein Mitglied %s', [ClassName, ANewName]), AReason));
    if not SameText(ANewName, Local.Name) then
    begin
      for Local_ in TRoutineLocals.Collect(Text, Tree, Method) do
        if SameText(Local_.Name, ANewName) then
          Exit(Fail(Format('%s deklariert schon %s', [Method.Name, ANewName]), AReason));
      for Routine in NodesOf(Method, TSyntaxKind.RoutineDecl) do
        if (Routine <> Method) and DeclaresAnywhere(Text, Tree, Routine, ANewName) then
          Exit(Fail(Format('die lokale Routine %s deklariert schon %s', [Routine.Name, ANewName]), AReason));
      // In allen Methoden der Klasse meinte ein gleichnamiger Bezeichner danach das Feld.
      for Node in NodesOf(Tree.Root, TSyntaxKind.Identifier) do
        if SameText(Node.Name, ANewName) and (TopRoutineOf(Node) <> nil) and
          SameText(TRoutineBody.QualifierOf(TopRoutineOf(Node).Name), ClassName) then
          Exit(Fail(Format('%s bedeutet in %s schon etwas anderes', [ANewName, TopRoutineOf(Node).Name]),
            AReason));
    end;
  end;
  if not TRoutineBody.FieldDeclaration(Text, Tree, TypeBody, ANewName + ': ' + TypeText + ';', AStyle, Edit) then
    Exit(Fail('Klassendeklaration nicht erweiterbar', AReason));
  AEdits := AEdits + [Edit];
  if Local.Kind = TRoutineLocalKind.Variable then
    TRoutineLocals.RemoveVariables(Tree, Local.Decl, [Local.Name], AEdits)
  else
  begin
    // Inline: mit Startwert bleibt die Zuweisung, sonst entfällt die Anweisung.
    Initializer := InitializerOf(Local.Decl);
    if Initializer <> nil then
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(Local.Decl.StartPos, Initializer.StartPos),
        ANewName + ' := ')]
    else
    begin
      Stop := TRoutineBody.TokenAt(Tokens, Local.Decl.EndOffset);
      if (Stop <= High(Tokens)) and Tokens[Stop].IsSymbol(';') then
        Stop := Tokens[Stop].Offset + 1
      else
        Stop := Local.Decl.EndOffset;
      LineStart := Lines.OffsetAt(TTextPosition.Create(Local.Decl.StartPos.Line, 0));
      LineEnd := Lines.OffsetAt(TTextPosition.Create(Lines.PositionAt(Stop).Line + 1, 0));
      if (Trim(Copy(Text, LineStart + 1, Local.Decl.StartOffset - LineStart)) = '') and
        (Trim(Copy(Text, Stop + 1, LineEnd - Stop)) = '') then
        AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(Lines.PositionAt(LineStart),
          Lines.PositionAt(LineEnd)), '')]
      else
        AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(Local.Decl.StartPos, Lines.PositionAt(Stop)), '')];
    end;
  end;
  if not SameStr(ANewName, Local.Name) then
    for Node in References do
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(Node.StartPos, Node.EndPos), ANewName)];
  Result := True;
end;

function TPromotePlan.BuildLocal(const ANewName: string; const AStyle: TFormatStyle; ACheckName: Boolean;
  out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Node, Routine: TSyntaxNode;
  Index: Integer;
begin
  AEdits := nil;
  if ACheckName and not SameText(ANewName, Name) then
  begin
    if DeclaresAnywhere(Text, Tree, Method, ANewName) then
      Exit(Fail(Format('%s deklariert schon %s', [Method.Name, ANewName]), AReason));
    for Routine in NodesOf(Method, TSyntaxKind.RoutineDecl) do
      if (Routine <> Method) and DeclaresAnywhere(Text, Tree, Routine, ANewName) then
        Exit(Fail(Format('die lokale Routine %s deklariert schon %s', [Routine.Name, ANewName]), AReason));
    for Node in NodesOf(Method, TSyntaxKind.Identifier) do
      if SameText(Node.Name, ANewName) then
        Exit(Fail(Format('%s bedeutet in %s schon etwas anderes', [ANewName, Method.Name]), AReason));
  end;
  TRoutineLocals.RemoveVariables(Tree, Field, [Name], AEdits);
  // War es das einzige Mitglied des Abschnitts, entfällt auch die Sichtbarkeit.
  Index := 0;
  while TypeBody[Index] <> Field do
    Inc(Index);
  if (Pos(',', Field.Name) = 0) and (Index > 0) and (TypeBody[Index - 1].Kind = TSyntaxKind.Visibility) and
    ((Index = TypeBody.ChildCount - 1) or (TypeBody[Index + 1].Kind = TSyntaxKind.Visibility)) and
    (TypeBody[Index - 1].EndPos.Line < Field.StartPos.Line) then
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(TypeBody[Index - 1].StartPos.Line, 0,
      TypeBody[Index - 1].EndPos.Line + 1, 0), '')];
  AEdits := AEdits + [TRoutineBody.AddVariable(Text, Method, ANewName, TypeText, AStyle)];
  for Node in References do
    if (Node.Kind = TSyntaxKind.MemberAccess) or not SameStr(Node.Name, ANewName) then
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(Node.StartPos, Node.EndPos), ANewName)];
  Result := True;
end;

function TPromotePlan.WrittenFirst(const AResultText, ANewName: string; out AReason: string): Boolean;
var
  Check: TSyntaxTree;
  Index: Integer;
  Section, Routine: TSyntaxNode;
  Graph: TControlFlowGraph;
  Answer: TFlowAnswer;
begin
  // Am umgewandelten Text: Die lokale Variable muss auf jedem Weg geschrieben werden, bevor sie gelesen wird.
  Check := TPascalParser.Parse(AResultText);
  try
    Section := Check.Root.FindChild(TSyntaxKind.ImplementationSection);
    Routine := nil;
    if Section <> nil then
      for Index := 0 to Section.ChildCount - 1 do
        if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(Section[Index].Name, Method.Name) then
          Routine := Section[Index];
    if Routine = nil then
      Exit(Fail('Methode nach der Umwandlung nicht gefunden', AReason));
    Graph := TControlFlowGraph.Build(Routine, TFlowSignatures.FromTree(Check.Root));
    try
      Answer := TFlowAnswer.Unknown;
      if Graph.Complete then
        Answer := Graph.MayReadBeforeWrite(ANewName);
    finally
      Graph.Free;
    end;
    if Answer <> TFlowAnswer.No then
      Exit(Fail(Format('%s wird in %s nicht auf jedem Weg zuerst geschrieben', [Name, Method.Name]), AReason));
    Result := True;
  finally
    Check.Free;
  end;
end;

function TPromotePlan.Build(const ANewName: string; const AStyle: TFormatStyle; ACheckName: Boolean;
  out AResult: TPromoteResult; out AReason: string): Boolean;
var
  Edits: TArray<TTextEdit>;
  Done: string;
  Check: TSyntaxTree;
begin
  AResult := Default(TPromoteResult);
  if not IsValidName(ANewName) then
    Exit(Fail('"' + ANewName + '" ist kein gültiger Name', AReason));
  if Direction = TPromoteDirection.ToField then
    Result := BuildField(ANewName, AStyle, ACheckName, Edits, AReason)
  else
    Result := BuildLocal(ANewName, AStyle, ACheckName, Edits, AReason);
  if not Result then
    Exit;
  Done := TChangeSignature.ApplyEdits(Text, Edits);
  Check := TPascalParser.Parse(Done);
  try
    if Length(Check.Diagnostics) > 0 then
      Exit(Fail('Ergebnis parst nicht', AReason));
  finally
    Check.Free;
  end;
  if (Direction = TPromoteDirection.ToLocal) and not WrittenFirst(Done, ANewName, AReason) then
    Exit(False);
  AResult.Edits := Edits;
  AResult.Warnings := Warnings;
  AResult.Places := Length(References) + 2;
end;

{ TPromoteVariable }

class function TPromoteVariable.FieldName(const ALocal: string): string;
begin
  Result := ALocal;
  if (Length(Result) > 1) and CharInSet(Result[1], ['L', 'm']) and CharInSet(Result[2], ['A'..'Z']) then
    Result := Copy(Result, 2, MaxInt);
  if Result <> '' then
    Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
  Result := 'F' + Result;
end;

class function TPromoteVariable.LocalName(const AField: string): string;
begin
  Result := AField;
  if (Length(Result) > 1) and (Result[1] = 'F') and CharInSet(Result[2], ['A'..'Z']) then
    Result := Copy(Result, 2, MaxInt);
  if Result <> '' then
    Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
  Result := 'L' + Result;
end;

class function TPromoteVariable.Target(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TPromoteLookup; out ATarget: TPromoteTarget; out AReason: string): Boolean;
var
  Plan: TPromotePlan;
  Probe: TPromoteResult;
begin
  ATarget := Default(TPromoteTarget);
  Plan := TPromotePlan.Create;
  try
    Plan.Text := AText;
    Plan.Tree := ATree;
    Plan.Lookup := ALookup;
    Result := Plan.Analyze(APosition, AReason);
    if not Result then
      Exit;
    ATarget.Direction := Plan.Direction;
    ATarget.Name := Plan.Name;
    if Plan.Direction = TPromoteDirection.ToField then
      ATarget.Suggested := FieldName(Plan.Name)
    else
    begin
      ATarget.Suggested := LocalName(Plan.Name);
      // Datenfluss mit einem Namen, den es sicher nicht gibt.
      Result := Plan.Build(TRoutineBody.UniqueName(Plan.Tokens, 'AtlasPromoteProbe'), TFormatStyle.Default, False,
        Probe, AReason);
    end;
  finally
    Plan.Free;
  end;
end;

class function TPromoteVariable.Execute(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TPromoteLookup; const AStyle: TFormatStyle; const AName: string; out AResult: TPromoteResult;
  out AReason: string): Boolean;
var
  Plan: TPromotePlan;
begin
  AResult := Default(TPromoteResult);
  Plan := TPromotePlan.Create;
  try
    Plan.Text := AText;
    Plan.Tree := ATree;
    Plan.Lookup := ALookup;
    Result := Plan.Analyze(APosition, AReason) and Plan.Build(Trim(AName), AStyle, True, AResult, AReason);
  finally
    Plan.Free;
  end;
end;

end.
