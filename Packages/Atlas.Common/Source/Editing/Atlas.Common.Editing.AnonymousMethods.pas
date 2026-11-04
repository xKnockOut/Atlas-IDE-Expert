unit Atlas.Common.Editing.AnonymousMethods;

// Anonyme Methode und Methode ineinander umwandeln (#680):
//   In Methode umwandeln (auf dem Kopf einer anonymen Methode in einer
//     Methode): Der Rumpf wird private Methode der Klasse, die Deklaration
//     steht im private-Abschnitt (legt ihn an, wenn er fehlt), der Rumpf
//     hinter der äußeren Methode. In einer freien Routine wird er eine Routine
//     der Unit vor ihr („In Routine umwandeln“); eine lokale Routine ginge
//     nicht, weil Delphi lokale Routinen nicht als Wert annimmt (E2094).
//     Der Name kommt aus dem Zusammenhang (OnClick := … → HandleClick,
//     TComparer<T>.Construct(function(const A, B: T) … A.Name …) →
//     CompareByName, ForEach → ProcessItem, TParallel.For → ProcessIndex) und
//     ist im Client änderbar.
//     Ohne erfasste Variablen steht an der Stelle der Methodenname; das passt
//     auf Methodenzeiger (of object) wie auf reference to.
//     Erfasste Variablen (Parameter, Variablen und Inline-Variablen der
//     äußeren Routine) werden Parameter der Methode: var, wenn die anonyme
//     Methode sie schreibt (auch als var-Argument), const bei Strings,
//     Records und Interfaces. An der Stelle bleibt eine kurze anonyme
//     Methode, die die Methode mit ihren Parametern und den Variablen aufruft.
//     Bei synchronen Aufrufen (Sort, ForEach, TParallel.For, Synchronize …)
//     ist das die übliche Form. Läuft die anonyme Methode später (Queue,
//     TTask.Run, Zuweisung an Ereignis oder Variable), kann eine benannte
//     Methode die Variablen nicht erfassen: Die Weiterleitung hält sie weiter
//     fest, das Verhalten bleibt gleich. Mit refactoring.anonymousMethod-
//     DeferredCapture = fields kopiert Atlas die Werte stattdessen vor der
//     Anweisung in Felder und setzt den Methodennamen ein; das ändert die
//     Bedeutung (spätere Änderungen sieht die Methode nicht, gleichzeitig
//     wartende Aufrufe teilen die Felder) und geht nur in Methoden ohne
//     geschriebene Variablen, sonst bleibt es bei der Weiterleitung.
//     Konstanten der äußeren Routine wandern als Konstanten mit. Die
//     Vorschau nennt die Form und warum.
//   Als anonyme Methode einbetten (auf einer privaten Methode, die genau
//     einmal als Wert an ein reference to übergeben oder zugewiesen und nie
//     aufgerufen wird, im Rumpf einer Methode derselben Klasse; nicht für
//     Methoden, die in der Formulardatei stehen): Der Rumpf steht an der
//     Stelle als anonyme Methode, die Methode entfällt.
// Nicht angeboten wird, wenn sich die Bedeutung eines Namens ändern könnte:
// Result der äußeren Routine, lokale Routinen oder Typen der äußeren, with,
// inherited, eine verschachtelte anonyme Methode, die eine künftige
// var-Variable erfasst; beim Einbetten ein Name des Aufrufers, der einen
// Namen des Rumpfs verdeckt. Jede Umwandlung ist ein Rückgängig-Schritt.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.NestedRoutines,
  Atlas.Common.Editing.PromoteVariable;

type
{$SCOPEDENUMS ON}
  /// <summary>Später laufende anonyme Methode mit erfassten Variablen: Weiterleitung oder Felder.</summary>
  TDeferredCapture = (Forward, Fields);
  /// <summary>Art eines prozeduralen Zieltyps.</summary>
  TProcTypeKind = (Unknown, Reference, MethodPointer, Plain);
  /// <summary>Form an der Stelle: Methodenname, kurze Weiterleitung, Methodenname mit Werten in Feldern.</summary>
  TAnonymousForm = (Direct, Forwarding, Fields);
{$SCOPEDENUMS OFF}

  /// <summary>Art des Typs, an den der Wert AValue geht (Argument, rechte Seite einer Zuweisung, Startwert).
  /// </summary>
  TProcTypeFunc = reference to function(AValue: TSyntaxNode): TProcTypeKind;

  TAnonymousLookup = record
    /// <summary>Typ einer Inline-Variablen ohne Typangabe.</summary>
    InlineType: TPromoteInlineTypeFunc;
    /// <summary>Mitglieder samt Vorfahren (vergebene Namen).</summary>
    MemberExists: TPromoteMemberFunc;
    /// <summary>Steht der Name in der Formulardatei?</summary>
    InForm: TPromoteInFormFunc;
    /// <summary>Record oder Interface (const beim reinen Lesen).</summary>
    ConstType: TConstTypeFunc;
    /// <summary>Zieltyp beim Einbetten; ohne ist er unbekannt.</summary>
    TargetType: TProcTypeFunc;
    /// <summary>Art der Argumente bekannter Aufrufe (Schreiben über var-Argumente).</summary>
    Flow: TFlowSignatureLookup;
    /// <summary>Ohne Namensauflösung: Aufrufe aus der Datei, Zieltypen und Typen ohne Angabe unbekannt.</summary>
    class function FromTree(ATree: TSyntaxTree): TAnonymousLookup; static;
  end;

  TAnonymousTarget = record
    /// <summary>Methode der Klasse; sonst Routine der Unit.</summary>
    IsMethod: Boolean;
    Suggested: string;
    Form: TAnonymousForm;
    /// <summary>Titel der Code-Aktion, z. B. „In Methode umwandeln (HandleClick)“.</summary>
    function Title: string;
  end;

  TAnonymousResult = record
    Edits: TArray<TTextEdit>;
    Warnings: TArray<string>;
    /// <summary>Neuer Kopf und Erklärung der Form.</summary>
    Preview: string;
    Form: TAnonymousForm;
  end;

  TAnonymousMethods = class
  public const
    ToMethodTitle = 'In Methode umwandeln';
    ToRoutineTitle = 'In Routine umwandeln';
    EmbedTitle = 'Als anonyme Methode einbetten';
  public
    /// <summary>Geht „In Methode umwandeln“ an APosition (Kopf einer anonymen Methode), ohne Prüfung des Namens?
    /// ATarget nennt Ziel, Vorschlag und Form, sonst AReason den Grund.</summary>
    class function Target(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TAnonymousLookup; ACapture: TDeferredCapture; out ATarget: TAnonymousTarget;
      out AReason: string): Boolean; static;
    /// <summary>„In Methode umwandeln“ an APosition mit dem Namen AName.</summary>
    class function Execute(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TAnonymousLookup; ACapture: TDeferredCapture; const AStyle: TFormatStyle;
      const AName: string; out AResult: TAnonymousResult; out AReason: string): Boolean; static;
    /// <summary>„Als anonyme Methode einbetten“ für die Methode, deren Kopf (Implementierung oder Klasse)
    /// APosition enthält; AReason nennt, warum es nicht geht.</summary>
    class function Embed(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TAnonymousLookup; const AStyle: TFormatStyle; out AAction: TCodeAction;
      out AReason: string): Boolean; static;
    /// <summary>Art des Typtexts ohne Namensauflösung: reference to, of object, procedure, bekannte Typen der RTL
    /// (TProc, TFunc&lt;T&gt;, TComparison&lt;T&gt;, TNotifyEvent …); sonst Unknown.</summary>
    class function KindOfTypeText(const ATypeText: string): TProcTypeKind; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.RoutineParts,
  Atlas.Common.Editing.CreateMethod;

const
  // Rufen die anonyme Methode, solange der Aufruf läuft.
  SyncCalls: array[0..5] of string = ('Sort', 'ForEach', 'For', 'Synchronize', 'BinarySearch', 'TryFind');
  MainThreadCalls: array[0..2] of string = ('Synchronize', 'Queue', 'ForceQueue');
  BackgroundCalls: array[0..4] of string = ('Run', 'Future', 'CreateAnonymousThread', 'Start', 'StartFuture');
  ReferenceTypes: array[0..7] of string = ('TProc', 'TFunc', 'TPredicate', 'TComparison', 'TThreadProcedure',
    'TEqualityComparison', 'THasher', 'TListSortCompareFunc');
  MethodPointerTypes: array[0..9] of string = ('TNotifyEvent', 'TThreadMethod', 'TKeyEvent', 'TKeyPressEvent',
    'TMouseEvent', 'TMouseMoveEvent', 'TCloseEvent', 'TCloseQueryEvent', 'TGetStrProc', 'THelpEvent');

type
  /// <summary>Name der äußeren Routine, den die anonyme Methode nutzt.</summary>
  TAnonymousCaptured = record
    Local: TRoutineLocal;
    TypeText: string;
    Written: Boolean;
    /// <summary>In einer verschachtelten anonymen Methode benutzt (darf kein var-Parameter werden).</summary>
    InNested: Boolean;
    /// <summary>Feldname bei der Form Fields.</summary>
    Field: string;
  end;

  /// <summary>Was an der Stelle umgewandelt wird.</summary>
  TAnonymousPlan = class
  public
    Text: string;
    Tree: TSyntaxTree;
    Lookup: TAnonymousLookup;
    Capture: TDeferredCapture;
    Lines: TLineTable;
    Tokens: TArray<TPascalToken>;
    Cache: TLocalsCache;
    Anonymous: TSyntaxNode;
    Outer: TSyntaxNode;
    ClassName: string;
    TypeBody: TSyntaxNode;
    IsMethod: Boolean;
    IsClass: Boolean;
    IsStatic: Boolean;
    Parameters: TArray<TParameterText>;
    Captured: TArray<TAnonymousCaptured>;
    ConstLines: TArray<string>;
    /// <summary>Wird die anonyme Methode synchron aufgerufen? CallName: Name des Aufrufs ('' ohne).</summary>
    Synchronous: Boolean;
    CallName: string;
    Form: TAnonymousForm;
    /// <summary>Warum Fields nicht ging, obwohl eingestellt; '' sonst.</summary>
    FieldsReason: string;
    Suggested: string;
    destructor Destroy; override;
    function Analyze(const APosition: TTextPosition; out AReason: string): Boolean;
    function CollectCaptured(out AReason: string): Boolean;
    procedure ClassifyUse;
    function ChooseForm(out AReason: string): Boolean;
    function Taken: TArray<string>;
    function NameTaken(const AName: string): Boolean;
    function SuggestName: string;
    function BodyStart: Integer;
    function MethodText(const AName: string; const AStyle: TFormatStyle; const AParameters: TArray<TParameterText>;
      out AText: string; out AReason: string): Boolean;
    function CallSite(const AName: string; const AStyle: TFormatStyle): string;
    function Build(const AName: string; const AStyle: TFormatStyle; ACheckName: Boolean;
      out AResult: TAnonymousResult; out AReason: string): Boolean;
  end;

{ Hilfen }

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

/// <summary>Gültiger Bezeichner, kein reserviertes Wort?</summary>
function IsValidName(const AName: string): Boolean;
begin
  Result := IsValidIdent(AName) and not TPascalLexer.IsReservedWord(AName);
end;

function Capitalized(const AName: string): string;
begin
  Result := AName;
  if Result <> '' then
  begin
    Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
  end;
end;

/// <summary>Handler-Name zu einem Ziel: OnClick → HandleClick, FCallback → HandleCallback.</summary>
function HandlerName(const ATarget: string): string;
begin
  Result := ATarget;
  if (Length(Result) > 2) and StartsText('On', Result) and CharInSet(Result[3], ['A'..'Z']) then
  begin
    Result := Copy(Result, 3, MaxInt);
  end
  else if (Length(Result) > 1) and CharInSet(Result[1], ['F', 'L']) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
  Result := 'Handle' + Capitalized(Result);
end;

/// <summary>Innerste anonyme Methode, deren Kopf (bis vor var, const oder begin) AOffset enthält; nil ohne.</summary>
function AnonymousAt(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
  Offset: Integer;
begin
  Found := nil;
  Offset := AOffset;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Index, Stop: Integer;
    begin
      Result := TRoutineParts.Encloses(ANode, Offset);
      if Result and (ANode.Kind = TSyntaxKind.AnonymousMethod) then
      begin
        Stop := ANode.EndOffset;
        for Index := 0 to ANode.ChildCount - 1 do
        begin
          if ANode[Index].Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.Block] then
          begin
            Stop := ANode[Index].StartOffset;
            Break;
          end;
        end;
        if Offset < Stop then
        begin
          Found := ANode;
        end;
      end;
    end);
  Result := Found;
end;

/// <summary>Innerste Routine um ANode; nil ohne.</summary>
function RoutineOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Äußerste Routine um ANode; nil ohne.</summary>
function TopRoutineOf(ANode: TSyntaxNode): TSyntaxNode;
var
  Node: TSyntaxNode;
begin
  Result := nil;
  Node := ANode.Parent;
  while Node <> nil do
  begin
    if Node.Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := Node;
    end;
    Node := Node.Parent;
  end;
end;

/// <summary>Liegt ANode (ausschließlich) bis AStop in einer Anweisung der Art AKind?</summary>
function Inside(ANode, AStop: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := ANode.Parent;
  while (Node <> nil) and (Node <> AStop) do
  begin
    if Node.Kind = AKind then
    begin
      Exit(True);
    end;
    Node := Node.Parent;
  end;
  Result := False;
end;

/// <summary>Steht im Bereich von ANode das Schlüsselwort inherited?</summary>
function HasInherited(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := TRoutineBody.TokenAt(ATokens, ANode.StartOffset);
  while (Index <= High(ATokens)) and (ATokens[Index].Offset < ANode.EndOffset) do
  begin
    if ATokens[Index].IsKeyword('inherited') then
    begin
      Exit(True);
    end;
    Inc(Index);
  end;
  Result := False;
end;

/// <summary>Kurzer Name des Aufgerufenen: Sort aus FList.Sort, For aus TParallel.For.</summary>
function CalleeName(ACall: TSyntaxNode): string;
begin
  Result := '';
  if (ACall <> nil) and (ACall.Kind = TSyntaxKind.Call) and (ACall.ChildCount > 0) then
  begin
    Result := ACall[0].Name;
  end;
end;

/// <summary>Ist ANode ein Argument (nicht der Aufgerufene) des Aufrufs AParent?</summary>
function IsArgument(ANode, AParent: TSyntaxNode): Boolean;
begin
  Result := (AParent <> nil) and (AParent.Kind = TSyntaxKind.Call) and (AParent.ChildCount > 0) and
    (AParent[0] <> ANode);
end;

/// <summary>Wird der Wert ANode an der Stelle übergeben oder gespeichert (Argument, rechte Seite, Startwert)?
/// </summary>
function IsValueUse(ANode: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Parent := ANode.Parent;
  Result := (Parent <> nil) and (IsArgument(ANode, Parent) or ((Parent.Kind = TSyntaxKind.AssignStatement) and
    (Parent.ChildCount > 1) and (Parent[1] = ANode)) or ((Parent.Kind = TSyntaxKind.InlineVar) and
    (Parent[Parent.ChildCount - 1] = ANode)));
end;

{ TAnonymousLookup }

class function TAnonymousLookup.FromTree(ATree: TSyntaxTree): TAnonymousLookup;
begin
  Result := Default(TAnonymousLookup);
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    Result.Flow := TFlowSignatures.FromTree(ATree.Root);
  end;
end;

{ TAnonymousTarget }

function TAnonymousTarget.Title: string;
begin
  if IsMethod then
  begin
    Result := TAnonymousMethods.ToMethodTitle;
  end
  else
  begin
    Result := TAnonymousMethods.ToRoutineTitle;
  end;
  Result := Format('%s (%s)', [Result, Suggested]);
end;

{ TAnonymousPlan }

destructor TAnonymousPlan.Destroy;
begin
  Cache.Free;
  inherited;
end;

function TAnonymousPlan.Analyze(const APosition: TTextPosition; out AReason: string): Boolean;
var
  Header, Node, ParameterList: TSyntaxNode;
  Index: Integer;
begin
  AReason := '';
  if (Tree = nil) or (Tree.Root = nil) then
  begin
    Exit(Fail('kein Baum', AReason));
  end;
  Lines := TLineTable.Build(Text);
  Tokens := Tree.Tokens;
  Anonymous := AnonymousAt(Tree, Lines.OffsetAt(APosition));
  if (Anonymous = nil) or (TRoutineBody.BodyOf(Anonymous) = nil) then
  begin
    Exit(Fail('keine anonyme Methode', AReason));
  end;
  Outer := RoutineOf(Anonymous);
  if (Outer = nil) or (TRoutineBody.BodyOf(Outer) = nil) then
  begin
    Exit(Fail('nicht in einer Routine', AReason));
  end;
  if Outer <> TopRoutineOf(Anonymous) then
  begin
    Exit(Fail('liegt in einer lokalen Routine', AReason));
  end;
  if TRoutineParts.InAnonymous(Anonymous, Outer) then
  begin
    Exit(Fail('liegt in einer anderen anonymen Methode', AReason));
  end;
  if Inside(Anonymous, Outer, TSyntaxKind.WithStatement) or TRoutineLocals.HasKind(Anonymous,
    TSyntaxKind.WithStatement) then
  begin
    Exit(Fail('with', AReason));
  end;
  if HasInherited(Tokens, Anonymous) then
  begin
    Exit(Fail('inherited', AReason));
  end;
  ClassName := TRoutineBody.QualifierOf(Outer.Name);
  IsMethod := ClassName <> '';
  if (Pos('<', ClassName) > 0) or (Pos('.', ClassName) > 0) then
  begin
    Exit(Fail('nicht unterstützte Klasse', AReason));
  end;
  Header := TRoutineParts.HeaderOf(Outer);
  if Header = nil then
  begin
    Exit(Fail('Routine ohne Kopf', AReason));
  end;
  TypeBody := nil;
  IsClass := False;
  IsStatic := False;
  if IsMethod then
  begin
    TypeBody := TRoutineBody.TypeBody(Tree.Root, ClassName);
    if TypeBody = nil then
    begin
      Exit(Fail('Klasse ' + ClassName + ' nicht in der Datei', AReason));
    end;
    IsClass := TRoutineParts.IsClassHeader(Tokens, Header);
    if IsClass then
    begin
      for Index := 0 to TypeBody.ChildCount - 1 do
      begin
        Node := TypeBody[Index];
        if (Node.Kind = TSyntaxKind.RoutineHeader) and SameText(Node.Name, TRoutineBody.ShortNameOf(Outer.Name)) and
          TRoutineParts.HasWord(Tokens, Node, ['static']) then
        begin
          IsStatic := True;
        end;
      end;
    end;
  end;
  Parameters := TRoutineParts.ParameterTexts(Text, Anonymous);
  ParameterList := Anonymous.FindChild(TSyntaxKind.Parameters);
  if (Parameters = nil) and (ParameterList <> nil) and (ParameterList.ChildCount > 0) then
  begin
    Exit(Fail('nicht unterstützte Parameter', AReason));
  end;
  Cache := TLocalsCache.Create(Text, Tree);
  if not CollectCaptured(AReason) then
  begin
    Exit(False);
  end;
  ClassifyUse;
  Result := ChooseForm(AReason);
  if Result then
  begin
    Suggested := SuggestName;
  end;
end;

function TAnonymousPlan.CollectCaptured(out AReason: string): Boolean;
var
  Identifiers: TList<TSyntaxNode>;
  OuterLocals: TArray<TRoutineLocal>;
  Node, Child: TSyntaxNode;
  Index, Found, Count: Integer;
  Written: Boolean;
begin
  ConstLines := nil;
  OuterLocals := Cache.Locals(Outer);
  // Jede äußere Lokale höchstens einmal: Länge vorab, am Ende auf Count kürzen.
  Captured := nil;
  SetLength(Captured, Length(OuterLocals));
  Count := 0;
  Identifiers := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Anonymous, TSyntaxKind.Identifier, Identifiers);
    for Node in Identifiers do
    begin
      if TRoutineParts.Shadowed(Cache, Node, Anonymous, Node.Name, True) then
      begin
        Continue;
      end;
      if SameText(Node.Name, 'Result') and TRoutineParts.IsFunction(Outer) then
      begin
        Exit(Fail('nutzt Result der äußeren Routine', AReason));
      end;
      Found := TRoutineLocals.IndexOf(OuterLocals, Node.Name, Node.StartOffset);
      if (Found >= 0) and TRoutineBody.Within(OuterLocals[Found].Decl, Anonymous) then
      begin
        Found := -1;
      end;
      if Found < 0 then
      begin
        for Index := 0 to Outer.ChildCount - 1 do
        begin
          Child := Outer[Index];
          if (Child.Kind = TSyntaxKind.RoutineDecl) and SameText(Child.Name, Node.Name) then
          begin
            Exit(Fail('nutzt die lokale Routine ' + Child.Name, AReason));
          end;
          if (Child.Kind = TSyntaxKind.TypeSection) and (IndexText(Node.Name,
            TRoutineParts.ChildNames(Child)) >= 0) then
          begin
            Exit(Fail('nutzt den lokalen Typ ' + Node.Name, AReason));
          end;
        end;
        Continue;
      end;
      Written := TRoutineLocals.AccessOf(Node, Lookup.Flow) <> TLocalAccess.Read;
      if OuterLocals[Found].Kind = TRoutineLocalKind.Constant then
      begin
        if Written then
        begin
          Exit(Fail('schreibt die Konstante ' + Node.Name, AReason));
        end;
        if IndexText(TRoutineBody.TextOf(Text, OuterLocals[Found].Decl), ConstLines) < 0 then
        begin
          ConstLines := ConstLines + [TRoutineBody.TextOf(Text, OuterLocals[Found].Decl)];
        end;
        Continue;
      end;
      Index := 0;
      while (Index < Count) and not ((Captured[Index].Local.Decl = OuterLocals[Found].Decl) and
        SameText(Captured[Index].Local.Name, OuterLocals[Found].Name)) do
      begin
        Inc(Index);
      end;
      if Index = Count then
      begin
        Inc(Count);
        Captured[Index] := Default(TAnonymousCaptured);
        Captured[Index].Local := OuterLocals[Found];
        Captured[Index].TypeText := OuterLocals[Found].TypeText;
        if (Captured[Index].TypeText = '') and Assigned(Lookup.InlineType) then
        begin
          Captured[Index].TypeText := Lookup.InlineType(OuterLocals[Found]);
        end;
      end;
      if Written then
      begin
        Captured[Index].Written := True;
      end;
      if TRoutineParts.InAnonymous(Node, Anonymous) then
      begin
        Captured[Index].InNested := True;
      end;
    end;
    // Lokale Typen der äußeren Routine auch in Typangaben.
    Identifiers.Clear;
    TRoutineLocals.CollectKind(Anonymous, TSyntaxKind.TypeReference, Identifiers);
    for Node in Identifiers do
    begin
      for Index := 0 to Outer.ChildCount - 1 do
      begin
        if (Outer[Index].Kind = TSyntaxKind.TypeSection) and (IndexText(Node.Name,
          TRoutineParts.ChildNames(Outer[Index])) >= 0) then
        begin
          Exit(Fail('nutzt den lokalen Typ ' + Node.Name, AReason));
        end;
      end;
    end;
  finally
    SetLength(Captured, Count);
    Identifiers.Free;
  end;
  Result := True;
end;

procedure TAnonymousPlan.ClassifyUse;
var
  Parent: TSyntaxNode;
begin
  Synchronous := False;
  CallName := '';
  Parent := Anonymous.Parent;
  if not IsArgument(Anonymous, Parent) then
  begin
    Exit;
  end;
  CallName := CalleeName(Parent);
  if MatchText(CallName, SyncCalls) then
  begin
    Synchronous := True;
  end
  else if SameText(CallName, 'Construct') and IsArgument(Parent, Parent.Parent) then
  begin
    // TComparer<T>.Construct(…) direkt als Argument von Sort: läuft mit der Sortierung.
    Synchronous := MatchText(CalleeName(Parent.Parent), SyncCalls);
  end;
end;

function TAnonymousPlan.ChooseForm(out AReason: string): Boolean;
var
  Index: Integer;
  Written: Boolean;
begin
  FieldsReason := '';
  if Captured = nil then
  begin
    Form := TAnonymousForm.Direct;
    Exit(True);
  end;
  for Index := 0 to High(Captured) do
  begin
    if Captured[Index].TypeText = '' then
    begin
      Exit(Fail('Typ von ' + Captured[Index].Local.Name + ' unbekannt', AReason));
    end;
  end;
  Form := TAnonymousForm.Forwarding;
  if not Synchronous and (Capture = TDeferredCapture.Fields) then
  begin
    Written := False;
    for Index := 0 to High(Captured) do
    begin
      if Captured[Index].Written then
      begin
        Written := True;
      end;
    end;
    if not IsMethod or IsClass then
    begin
      FieldsReason := 'nur in Methoden eines Objekts';
    end
    else if Written then
    begin
      FieldsReason := 'die anonyme Methode schreibt erfasste Variablen';
    end
    else if TRoutineBody.HostStatement(Anonymous, TRoutineBody.BodyOf(Outer)) = nil then
    begin
      FieldsReason := 'vor der Anweisung lässt sich nichts einfügen';
    end
    else
    begin
      Form := TAnonymousForm.Fields;
    end;
  end;
  if Form = TAnonymousForm.Forwarding then
  begin
    for Index := 0 to High(Captured) do
    begin
      if Captured[Index].Written and Captured[Index].InNested then
      begin
        Exit(Fail('eine verschachtelte anonyme Methode fängt ' + Captured[Index].Local.Name + ' ein', AReason));
      end;
    end;
  end;
  Result := True;
end;

function TAnonymousPlan.Taken: TArray<string>;
begin
  if IsMethod then
  begin
    Result := TRoutineBody.MemberNames(TypeBody);
  end
  else
  begin
    Result := TRoutineParts.UnitNames(Tree.Root);
  end;
end;

function TAnonymousPlan.NameTaken(const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := (IndexText(AName, Taken) >= 0) or (IsMethod and Assigned(Lookup.MemberExists) and
    Lookup.MemberExists(ClassName, AName, Anonymous.StartOffset)) or
    // An der Stelle verdeckte ein Name der äußeren Routine die neue Methode.
    Cache.Declares(Outer, AName, Anonymous.StartOffset) or SameText(AName, Outer.Name) or
    SameText(AName, TRoutineBody.ShortNameOf(Outer.Name));
  if not Result then
  begin
    for Index := 0 to High(Parameters) do
    begin
      if SameText(Parameters[Index].Name, AName) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

function TAnonymousPlan.SuggestName: string;
var
  Parent, Block: TSyntaxNode;
  Field: string;
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
begin
  Result := '';
  Parent := Anonymous.Parent;
  if (Parent.Kind = TSyntaxKind.AssignStatement) and (Parent.ChildCount > 1) and (Parent[1] = Anonymous) then
  begin
    Result := HandlerName(Parent[0].Name);
  end
  else if Parent.Kind = TSyntaxKind.InlineVar then
  begin
    Result := HandlerName(Trim(Parent.Name.Split([','])[0]));
  end
  else if IsArgument(Anonymous, Parent) then
  begin
    // Vergleich zweier Werte gleichen Typs: CompareBy + erstes verglichenes Feld.
    if TRoutineParts.IsFunction(Anonymous) and (Length(Parameters) = 2) and
      SameText(Parameters[0].Rest, Parameters[1].Rest) then
    begin
      Field := '';
      Block := TRoutineBody.BodyOf(Anonymous);
      Nodes := TList<TSyntaxNode>.Create;
      try
        TRoutineLocals.CollectKind(Block, TSyntaxKind.MemberAccess, Nodes);
        for Node in Nodes do
        begin
          if (Node.ChildCount > 0) and (Node[0].Kind = TSyntaxKind.Identifier) and
            SameText(Node[0].Name, Parameters[0].Name) then
          begin
            Field := Node.Name;
            Break;
          end;
        end;
      finally
        Nodes.Free;
      end;
      Result := 'CompareBy' + Capitalized(Field);
      if Field = '' then
      begin
        Result := 'Compare';
      end;
    end
    else if SameText(CallName, 'ForEach') then
    begin
      Result := 'ProcessItem';
    end
    else if SameText(CallName, 'For') then
    begin
      Result := 'ProcessIndex';
    end
    else if MatchText(CallName, MainThreadCalls) then
    begin
      Result := 'UpdateInMainThread';
    end
    else if MatchText(CallName, BackgroundCalls) then
    begin
      Result := 'RunInBackground';
    end
    else if CallName <> '' then
    begin
      Result := 'Handle' + Capitalized(CallName);
    end;
  end;
  if not IsValidName(Result) then
  begin
    Result := 'HandleAnonymous';
  end;
  Result := TRoutineParts.FreeName(Result, Taken);
  while NameTaken(Result) do
  begin
    Result := TRoutineParts.FreeName(Result, Taken + [Result]);
  end;
end;

function TAnonymousPlan.BodyStart: Integer;
var
  Index: Integer;
begin
  Result := Anonymous.EndOffset;
  for Index := 0 to Anonymous.ChildCount - 1 do
  begin
    if Anonymous[Index].Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.Block] then
    begin
      Exit(Anonymous[Index].StartOffset);
    end;
  end;
end;

function TAnonymousPlan.MethodText(const AName: string; const AStyle: TFormatStyle;
  const AParameters: TArray<TParameterText>; out AText: string; out AReason: string): Boolean;
var
  Block: TSyntaxNode;
  Edits: TArray<TOffsetEdit>;
  Identifiers: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Index, Start, InnerStart, InnerStop, BeginToken, EndToken: Integer;
  LineBreak, Indent, IndentUnit, Head, Body, Before, Inner, Line: string;
  Qualified: string;
begin
  AReason := '';
  LineBreak := TTextLines.LineBreakOf(Text);
  Indent := TTextLines.IndentOf(Text, Outer.StartPos.Line);
  IndentUnit := TRoutineBody.IndentUnit(AStyle);
  Block := TRoutineBody.BodyOf(Anonymous);
  // Felder: erfasste Namen im Rumpf heißen wie die Felder.
  Edits := nil;
  if Form = TAnonymousForm.Fields then
  begin
    Identifiers := TList<TSyntaxNode>.Create;
    try
      TRoutineLocals.CollectKind(Anonymous, TSyntaxKind.Identifier, Identifiers);
      for Node in Identifiers do
      begin
        if not TRoutineParts.Shadowed(Cache, Node, Anonymous, Node.Name, True) then
        begin
          for Index := 0 to High(Captured) do
          begin
            if SameText(Node.Name, Captured[Index].Local.Name) then
            begin
              Edits := Edits + [TOffsetEdit.Create(Node.StartOffset, Node.EndOffset, Captured[Index].Field)];
            end;
          end;
        end;
      end;
    finally
      Identifiers.Free;
    end;
  end;
  Start := BodyStart;
  if Block.StartPos.Line = Block.EndPos.Line then
  begin
    // begin X; end in einer Zeile: in Zeilen zerlegt.
    BeginToken := TRoutineBody.TokenAt(Tokens, Block.StartOffset);
    EndToken := TRoutineBody.PreviousToken(Tokens, TRoutineBody.TokenAt(Tokens, Block.EndOffset));
    if (BeginToken > High(Tokens)) or not Tokens[BeginToken].IsKeyword('begin') or (EndToken < 0) or
      not Tokens[EndToken].IsKeyword('end') then
    begin
      Exit(Fail('Rumpf nicht lesbar', AReason));
    end;
    InnerStart := Tokens[BeginToken].Offset + Length(Tokens[BeginToken].Text);
    InnerStop := Tokens[EndToken].Offset;
    Inner := Trim(TRoutineParts.ApplyEdits(Copy(Text, InnerStart + 1, InnerStop - InnerStart), InnerStart, Edits));
    Before := Trim(Copy(Text, Start + 1, Block.StartOffset - Start));
    Body := '';
    if Before <> '' then
    begin
      Body := TRoutineBody.Reindent(Before, TTextLines.IndentOf(Text, Anonymous.StartPos.Line), Indent,
        LineBreak) + LineBreak;
    end;
    Body := Body + Indent + 'begin' + LineBreak;
    if Inner <> '' then
    begin
      Body := Body + Indent + IndentUnit + Inner + LineBreak;
    end;
    Body := Body + Indent + 'end;';
  end
  else
  begin
    Body := TRoutineParts.ApplyEdits(Copy(Text, Start + 1, Anonymous.EndOffset - Start), Start, Edits);
    Body := TRoutineBody.Reindent(TrimLeft(Body), TTextLines.IndentOf(Text, Block.EndPos.Line), Indent,
      LineBreak) + ';';
  end;
  Qualified := AName;
  if IsMethod then
  begin
    Qualified := ClassName + '.' + AName;
  end;
  Head := TRoutineParts.HeadText(Text, Anonymous, Qualified, AParameters, IsClass);
  AText := Indent + Head + LineBreak;
  if ConstLines <> nil then
  begin
    AText := AText + Indent + 'const' + LineBreak;
    for Line in ConstLines do
    begin
      AText := AText + Indent + IndentUnit + Line + LineBreak;
    end;
  end;
  AText := AText + Body;
  Result := True;
end;

function TAnonymousPlan.CallSite(const AName: string; const AStyle: TFormatStyle): string;
var
  Arguments, Call, Head, LineBreak, Indent: string;
  Index: Integer;
  Block: TSyntaxNode;
begin
  if Form <> TAnonymousForm.Forwarding then
  begin
    Exit(AName);
  end;
  Arguments := '';
  for Index := 0 to High(Parameters) do
  begin
    if Arguments <> '' then
    begin
      Arguments := Arguments + ', ';
    end;
    Arguments := Arguments + Parameters[Index].Name;
  end;
  for Index := 0 to High(Captured) do
  begin
    if Arguments <> '' then
    begin
      Arguments := Arguments + ', ';
    end;
    Arguments := Arguments + Captured[Index].Local.Name;
  end;
  Call := AName + '(' + Arguments + ');';
  if TRoutineParts.IsFunction(Anonymous) then
  begin
    Call := 'Result := ' + Call;
  end;
  Head := TrimRight(Copy(Text, Anonymous.StartOffset + 1, BodyStart - Anonymous.StartOffset));
  Block := TRoutineBody.BodyOf(Anonymous);
  if Anonymous.StartPos.Line = Anonymous.EndPos.Line then
  begin
    Exit(Head + ' begin ' + Call + ' end');
  end;
  LineBreak := TTextLines.LineBreakOf(Text);
  Indent := TTextLines.IndentOf(Text, Block.EndPos.Line);
  Result := Head + LineBreak + Indent + 'begin' + LineBreak + Indent + TRoutineBody.IndentUnit(AStyle) + Call +
    LineBreak + Indent + 'end';
end;

function TAnonymousPlan.Build(const AName: string; const AStyle: TFormatStyle; ACheckName: Boolean;
  out AResult: TAnonymousResult; out AReason: string): Boolean;
var
  NewParameters: TArray<TParameterText>;
  Parameter: TParameterText;
  Index, InsertLine: Integer;
  Moved, Declaration, LineBreak, Head, Assignments, Names, Fields, Qualified: string;
  Edits: TArray<TTextEdit>;
  Edit, FieldEdit: TTextEdit;
  HasPrivate: Boolean;
  Host: TSyntaxNode;
  FieldTaken: TArray<string>;
begin
  AResult := Default(TAnonymousResult);
  AReason := '';
  if ACheckName then
  begin
    if not IsValidName(AName) then
    begin
      Exit(Fail(Format('"%s" ist kein gültiger Name', [AName]), AReason));
    end;
    if NameTaken(AName) then
    begin
      Exit(Fail(Format('"%s" ist schon vergeben', [AName]), AReason));
    end;
  end;
  LineBreak := TTextLines.LineBreakOf(Text);
  // Parameter: die eigenen, bei der Weiterleitung dazu die erfassten.
  NewParameters := Parameters;
  if Form = TAnonymousForm.Forwarding then
  begin
    for Index := 0 to High(Captured) do
    begin
      Parameter.Name := Captured[Index].Local.Name;
      Parameter.Rest := ': ' + Captured[Index].TypeText;
      Parameter.Modifier := '';
      if Captured[Index].Written then
      begin
        Parameter.Modifier := 'var';
      end
      else if TCreateMethod.WantsConst(Captured[Index].TypeText, False, False) or (Assigned(Lookup.ConstType) and
        Lookup.ConstType(Captured[Index].TypeText, Anonymous.StartOffset)) or
        // Ein const-Parameter der äußeren Routine bleibt const.
        ((Captured[Index].Local.Kind = TRoutineLocalKind.Parameter) and StartsText('const ',
        TRoutineBody.TextOf(Text, Captured[Index].Local.Decl))) then
      begin
        Parameter.Modifier := 'const';
      end;
      NewParameters := NewParameters + [Parameter];
    end;
  end;
  // Felder: F + Name ohne L-Präfix, eindeutig in der Klasse.
  if Form = TAnonymousForm.Fields then
  begin
    FieldTaken := Taken + [AName];
    for Index := 0 to High(Captured) do
    begin
      Captured[Index].Field := TRoutineParts.FreeName(TPromoteVariable.FieldName(Captured[Index].Local.Name),
        FieldTaken);
      while (Assigned(Lookup.MemberExists) and Lookup.MemberExists(ClassName, Captured[Index].Field,
        Anonymous.StartOffset)) or Cache.Declares(Anonymous, Captured[Index].Field, MaxInt) do
      begin
        Captured[Index].Field := TRoutineParts.FreeName(Captured[Index].Field, FieldTaken + [Captured[Index].Field]);
      end;
      FieldTaken := FieldTaken + [Captured[Index].Field];
    end;
  end;
  if not MethodText(AName, AStyle, NewParameters, Moved, AReason) then
  begin
    Exit(False);
  end;
  Edits := nil;
  // Felder vor der Anweisung füllen.
  if Form = TAnonymousForm.Fields then
  begin
    Host := TRoutineBody.HostStatement(Anonymous, TRoutineBody.BodyOf(Outer));
    Assignments := '';
    for Index := 0 to High(Captured) do
    begin
      if Assignments <> '' then
      begin
        Assignments := Assignments + LineBreak + TTextLines.IndentOf(Text, Host.StartPos.Line);
      end;
      Assignments := Assignments + Captured[Index].Field + ' := ' + Captured[Index].Local.Name + ';';
    end;
    Edits := Edits + [TRoutineBody.InsertBefore(Text, Host, Assignments)];
  end;
  Edits := Edits + [TTextEdit.Create(TTextRange.Create(Anonymous.StartPos, Anonymous.EndPos),
    CallSite(AName, AStyle))];
  Head := TRoutineParts.HeadText(Text, Anonymous, AName, NewParameters, IsClass);
  if IsMethod then
  begin
    InsertLine := Outer.EndPos.Line + 1;
    // Leerzeile davor und, wenn direkt etwas folgt, auch danach.
    if not TRoutineParts.LineIsBlank(TTextLines.SplitLines(Text), InsertLine) then
    begin
      Moved := Moved + LineBreak;
    end;
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(InsertLine, 0, InsertLine, 0), LineBreak + Moved +
      LineBreak)];
    Declaration := Head;
    if IsStatic then
    begin
      Declaration := Declaration + ' static;';
    end;
    if Form = TAnonymousForm.Fields then
    begin
      HasPrivate := False;
      for Index := 0 to TypeBody.ChildCount - 1 do
      begin
        if (TypeBody[Index].Kind = TSyntaxKind.Visibility) and MatchText(TypeBody[Index].Name, ['private',
          'strict private']) then
        begin
          HasPrivate := True;
        end;
      end;
      Fields := '';
      for Index := 0 to High(Captured) do
      begin
        if Fields <> '' then
        begin
          Fields := Fields + ' ';
        end;
        Fields := Fields + Captured[Index].Field + ': ' + Captured[Index].TypeText + ';';
      end;
      if not HasPrivate then
      begin
        // Neuer Abschnitt: Felder und Methode in einem, Felder zuerst (E2169).
        Declaration := Fields + LineBreak + TTextLines.IndentOf(Text, TypeBody.EndPos.Line) +
          TRoutineBody.IndentUnit(AStyle) + Declaration;
      end
      else
      begin
        if not TRoutineBody.FieldDeclaration(Text, Tree, TypeBody, Fields, AStyle, FieldEdit) then
        begin
          Exit(Fail('Klassendeklaration nicht erweiterbar', AReason));
        end;
        Edits := Edits + [FieldEdit];
      end;
    end;
    if not TRoutineBody.MemberDeclaration(Text, Tree, TypeBody, TMemberEntry.Create('private', Declaration), AStyle,
      Edit) then
    begin
      Exit(Fail('Klassendeklaration nicht erweiterbar', AReason));
    end;
    Edits := Edits + [Edit];
  end
  else
  begin
    InsertLine := TRoutineBody.RoutineInsertLine(Text, Outer);
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(InsertLine, 0, InsertLine, 0), Moved + LineBreak +
      LineBreak)];
  end;
  // Vorschau: Kopf und Form.
  Qualified := AName;
  if IsMethod then
  begin
    Qualified := ClassName + '.' + AName;
  end;
  Names := '';
  for Index := 0 to High(Captured) do
  begin
    if Names <> '' then
    begin
      Names := Names + ', ';
    end;
    Names := Names + Captured[Index].Local.Name;
  end;
  if IsMethod then
  begin
    AResult.Preview := 'Neue Methode: ';
  end
  else
  begin
    AResult.Preview := 'Neue Routine: ';
  end;
  AResult.Preview := AResult.Preview + TRoutineParts.HeadText(Text, Anonymous, Qualified, NewParameters, IsClass) +
    LineBreak;
  case Form of
    TAnonymousForm.Direct:
      AResult.Preview := AResult.Preview + Format('Erfasst keine Variablen: An der Stelle steht jetzt %s.', [AName]);
    TAnonymousForm.Forwarding:
      begin
        if Synchronous then
        begin
          AResult.Preview := AResult.Preview + Format('Läuft während %s: Die erfassten Variablen (%s) werden ' +
            'Parameter, geschriebene als var; an der Stelle ruft eine kurze anonyme Methode %s mit ihnen auf.',
            [CallName, Names, AName]);
        end
        else
        begin
          AResult.Preview := AResult.Preview + Format('Läuft womöglich später: Eine benannte Methode kann %s ' +
            'nicht erfassen. An der Stelle bleibt eine kurze anonyme Weiterleitung, die die Variablen weiter ' +
            'festhält und %s mit ihnen aufruft; das Verhalten bleibt gleich.', [Names, AName]);
        end;
        if FieldsReason <> '' then
        begin
          AResult.Preview := AResult.Preview + LineBreak + Format('Als Felder geht hier nicht: %s.', [FieldsReason]);
        end;
      end;
    TAnonymousForm.Fields:
      begin
        AResult.Preview := AResult.Preview + Format('Läuft später: Die Werte von %s kommen vor der Anweisung in ' +
          'Felder, an der Stelle steht %s.', [Names, AName]);
        AResult.Warnings := AResult.Warnings + [Format('%s liest die Werte aus Feldern: Spätere Änderungen von %s ' +
          'sieht es nicht, und gleichzeitig wartende Aufrufe teilen sich die Felder.', [AName, Names])];
      end;
  end;
  AResult.Edits := Edits;
  AResult.Form := Form;
  Result := True;
end;

{ Einbetten }

function EmbedCore(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TAnonymousLookup; const AStyle: TFormatStyle; out AAction: TCodeAction;
  out AReason: string): Boolean;
var
  Lines: TLineTable;
  TextLines: TArray<string>;
  Tokens: TArray<TPascalToken>;
  Routine, Declaration, Header, TypeBody, Node, Reference, Caller, Scope, Body, Child: TSyntaxNode;
  Collected: TList<TSyntaxNode>;
  References: TArray<TSyntaxNode>;
  Cache: TLocalsCache;
  Parameters: TArray<TParameterText>;
  Short, ClassName, LineBreak, Indent, Inserted, Moved: string;
  Index, FirstLine, RemoveEnd, Start: Integer;
  Edits: TArray<TTextEdit>;
  Kind: TProcTypeKind;
begin
  AAction := Default(TCodeAction);
  AReason := '';
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit(Fail('kein Baum', AReason));
  end;
  Lines := TLineTable.Build(AText);
  Tokens := ATree.Tokens;
  Routine := TRoutineParts.TopRoutineAt(ATree, Lines.OffsetAt(APosition), Declaration);
  if (Routine = nil) or (Routine.Parent = nil) or (Routine.Parent.Kind <> TSyntaxKind.ImplementationSection) then
  begin
    Exit(Fail('keine Methode der Implementierung', AReason));
  end;
  Header := TRoutineParts.HeaderOf(Routine);
  Body := TRoutineBody.BodyOf(Routine);
  if (Header = nil) or (Body = nil) then
  begin
    Exit(Fail('Methode ohne Rumpf', AReason));
  end;
  Short := TRoutineBody.ShortNameOf(Routine.Name);
  ClassName := TRoutineBody.QualifierOf(Routine.Name);
  if (ClassName = '') or (Pos('<', ClassName) > 0) or (Pos('.', ClassName) > 0) then
  begin
    Exit(Fail('keine Methode', AReason));
  end;
  if TRoutineParts.IsClassHeader(Tokens, Header) then
  begin
    Exit(Fail('Klassenmethode', AReason));
  end;
  if TRoutineParts.HasWord(Tokens, Header, ['overload', 'forward', 'external', 'assembler']) then
  begin
    Exit(Fail('nicht unterstützte Form', AReason));
  end;
  TypeBody := TRoutineBody.TypeBody(ATree.Root, ClassName);
  if TypeBody = nil then
  begin
    Exit(Fail('Klasse ' + ClassName + ' nicht in der Datei', AReason));
  end;
  Declaration := nil;
  for Index := 0 to TypeBody.ChildCount - 1 do
  begin
    if (TypeBody[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(TypeBody[Index].Name, Short) then
    begin
      if Declaration <> nil then
      begin
        Exit(Fail('überladen', AReason));
      end;
      Declaration := TypeBody[Index];
    end;
  end;
  if Declaration = nil then
  begin
    Exit(Fail('Deklaration fehlt', AReason));
  end;
  if not MatchText(TRoutineBody.VisibilityOf(TypeBody, Declaration), ['private', 'strict private']) then
  begin
    Exit(Fail('nicht privat', AReason));
  end;
  if TRoutineParts.HasWord(Tokens, Declaration, ['virtual', 'dynamic', 'override', 'abstract', 'message',
    'overload', 'reintroduce', 'final', 'static']) then
  begin
    Exit(Fail('virtuell, Botschaft oder überladen', AReason));
  end;
  if Assigned(ALookup.InForm) and ALookup.InForm(Short) then
  begin
    Exit(Fail(Short + ' steht in der Formulardatei', AReason));
  end;
  // Anonyme Methoden haben keine lokalen Routinen, Typen oder Marken; inherited bedeutete dort etwas anderes.
  for Index := 0 to Routine.ChildCount - 1 do
  begin
    if Routine[Index].Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.TypeSection, TSyntaxKind.LabelSection] then
    begin
      Exit(Fail('lokale Routinen, Typen oder Marken', AReason));
    end;
  end;
  if HasInherited(Tokens, Body) or TRoutineLocals.HasKind(Body, TSyntaxKind.WithStatement) then
  begin
    Exit(Fail('inherited oder with', AReason));
  end;
  Parameters := TRoutineParts.ParameterTexts(AText, Header);
  if (Parameters = nil) and (Header.FindChild(TSyntaxKind.Parameters) <> nil) and
    (Header.FindChild(TSyntaxKind.Parameters).ChildCount > 0) then
  begin
    Exit(Fail('nicht unterstützte Parameter', AReason));
  end;
  for Index := 0 to High(Parameters) do
  begin
    if Pos('=', Parameters[Index].Rest) > 0 then
    begin
      Exit(Fail('Parameter mit Vorgabewert', AReason));
    end;
  end;
  Cache := TLocalsCache.Create(AText, ATree);
  Collected := TList<TSyntaxNode>.Create;
  try
    // Bezüge: genau einer außerhalb der Methode, als Wert.
    References := nil;
    TRoutineLocals.CollectKind(ATree.Root, TSyntaxKind.Identifier, Collected);
    TRoutineLocals.CollectKind(ATree.Root, TSyntaxKind.MemberAccess, Collected);
    for Node in Collected do
    begin
      if not SameText(Node.Name, Short) then
      begin
        Continue;
      end;
      if Node.Kind = TSyntaxKind.MemberAccess then
      begin
        if (Node[0].Kind <> TSyntaxKind.Identifier) or not SameText(Node[0].Name, 'Self') then
        begin
          Exit(Fail('über ein anderes Objekt benutzt', AReason));
        end;
      end
      else if (Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.MemberAccess) and (Node.Parent[0] = Node) and
        SameText(Node.Parent.Name, Short) then
      begin
        Continue;
      end
      else if TRoutineParts.Shadowed(Cache, Node, nil, Short, False) then
      begin
        Continue;
      end;
      if TRoutineBody.Within(Node, Routine) then
      begin
        Exit(Fail('rekursiv', AReason));
      end;
      References := References + [Node];
    end;
    if Length(References) <> 1 then
    begin
      Exit(Fail('nicht genau eine Übergabe', AReason));
    end;
    Reference := References[0];
    if not IsValueUse(Reference) then
    begin
      Exit(Fail('wird aufgerufen, nicht als Wert übergeben', AReason));
    end;
    Kind := TProcTypeKind.Unknown;
    if Assigned(ALookup.TargetType) then
    begin
      Kind := ALookup.TargetType(Reference);
    end;
    case Kind of
      TProcTypeKind.MethodPointer:
        Exit(Fail('das Ziel ist ein Methodenzeiger (of object); dort passt keine anonyme Methode', AReason));
      TProcTypeKind.Plain:
        Exit(Fail('das Ziel ist ein prozeduraler Typ ohne reference to', AReason));
      TProcTypeKind.Unknown:
        Exit(Fail('Zieltyp unbekannt', AReason));
      TProcTypeKind.Reference: ;
    end;
    Caller := TopRoutineOf(Reference);
    if (Caller = nil) or not SameText(TRoutineBody.QualifierOf(Caller.Name), ClassName) or
      TRoutineParts.IsClassHeader(Tokens, TRoutineParts.HeaderOf(Caller)) then
    begin
      Exit(Fail('Übergabe nicht in einer Methode derselben Klasse', AReason));
    end;
    if Inside(Reference, Caller, TSyntaxKind.WithStatement) then
    begin
      Exit(Fail('Übergabe in with', AReason));
    end;
    // Namen des Rumpfs, die an der Übergabe etwas anderes bedeuten.
    Collected.Clear;
    TRoutineLocals.CollectKind(Routine, TSyntaxKind.Identifier, Collected);
    TRoutineLocals.CollectKind(Routine, TSyntaxKind.TypeReference, Collected);
    for Node in Collected do
    begin
      if TRoutineParts.Shadowed(Cache, Node, Routine, Node.Name, True) then
      begin
        Continue;
      end;
      Scope := Reference.Parent;
      while Scope <> nil do
      begin
        if (Scope.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) and Cache.Declares(Scope, Node.Name,
          Reference.StartOffset) then
        begin
          Exit(Fail(Scope.Name + ' verdeckt ' + Node.Name, AReason));
        end;
        Scope := Scope.Parent;
      end;
    end;
    // Rumpf ab var, const bzw. begin, eingerückt unter die Zeile der Übergabe.
    LineBreak := TTextLines.LineBreakOf(AText);
    TextLines := TTextLines.SplitLines(AText);
    Start := Body.StartOffset;
    for Index := 0 to Routine.ChildCount - 1 do
    begin
      Child := Routine[Index];
      if (Child.Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection]) and (Child.StartOffset < Start) then
      begin
        Start := Child.StartOffset;
      end;
    end;
    Indent := TTextLines.IndentOf(AText, Reference.StartPos.Line) + TRoutineBody.IndentUnit(AStyle);
    Moved := TRoutineBody.Reindent(Copy(AText, Start + 1, Body.EndOffset - Start),
      TTextLines.IndentOf(AText, Routine.StartPos.Line), Indent, LineBreak);
    Inserted := TRoutineParts.AnonymousHead(AText, Header, Parameters) + LineBreak + Moved;
    Edits := nil;
    FirstLine := TRoutineBody.RoutineInsertLine(AText, Routine);
    RemoveEnd := Routine.EndPos.Line + 1;
    if TRoutineParts.LineIsBlank(TextLines, FirstLine - 1) and TRoutineParts.LineIsBlank(TextLines, RemoveEnd) then
    begin
      Inc(RemoveEnd);
    end;
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(FirstLine, 0, RemoveEnd, 0), '')];
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Declaration.StartPos.Line, 0,
      Declaration.EndPos.Line + 1, 0), '')];
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Reference.StartPos, Reference.EndPos), Inserted)];
    AAction.Title := TAnonymousMethods.EmbedTitle;
    AAction.Kind := RewriteKind;
    AAction.Edits := Edits;
    AAction.Preview := Format('%s steht an der Übergabe in %s als anonyme Methode; die Methode entfällt.',
      [Short, Caller.Name]) + LineBreak + TRoutineParts.AnonymousHead(AText, Header, Parameters);
    Result := True;
  finally
    Collected.Free;
    Cache.Free;
  end;
end;

{ TAnonymousMethods }

class function TAnonymousMethods.KindOfTypeText(const ATypeText: string): TProcTypeKind;
var
  Name: string;
begin
  Name := Trim(ATypeText);
  if StartsText('reference ', Name) then
  begin
    Exit(TProcTypeKind.Reference);
  end;
  if ContainsText(Name, ' of object') then
  begin
    Exit(TProcTypeKind.MethodPointer);
  end;
  if StartsText('procedure', Name) or StartsText('function', Name) then
  begin
    Exit(TProcTypeKind.Plain);
  end;
  if Pos('<', Name) > 0 then
  begin
    Name := Copy(Name, 1, Pos('<', Name) - 1);
  end;
  Name := Trim(Copy(Name, LastDelimiter('.', Name) + 1, MaxInt));
  if MatchText(Name, ReferenceTypes) then
  begin
    Exit(TProcTypeKind.Reference);
  end;
  if MatchText(Name, MethodPointerTypes) then
  begin
    Exit(TProcTypeKind.MethodPointer);
  end;
  Result := TProcTypeKind.Unknown;
end;

class function TAnonymousMethods.Target(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TAnonymousLookup; ACapture: TDeferredCapture; out ATarget: TAnonymousTarget;
  out AReason: string): Boolean;
var
  Plan: TAnonymousPlan;
  Probe: TAnonymousResult;
begin
  ATarget := Default(TAnonymousTarget);
  Plan := TAnonymousPlan.Create;
  try
    Plan.Text := AText;
    Plan.Tree := ATree;
    Plan.Lookup := ALookup;
    Plan.Capture := ACapture;
    Result := Plan.Analyze(APosition, AReason) and Plan.Build(Plan.Suggested, TFormatStyle.Default, False, Probe,
      AReason);
    if not Result then
    begin
      Exit;
    end;
    ATarget.IsMethod := Plan.IsMethod;
    ATarget.Suggested := Plan.Suggested;
    ATarget.Form := Plan.Form;
  finally
    Plan.Free;
  end;
end;

class function TAnonymousMethods.Execute(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TAnonymousLookup; ACapture: TDeferredCapture; const AStyle: TFormatStyle; const AName: string;
  out AResult: TAnonymousResult; out AReason: string): Boolean;
var
  Plan: TAnonymousPlan;
begin
  AResult := Default(TAnonymousResult);
  Plan := TAnonymousPlan.Create;
  try
    Plan.Text := AText;
    Plan.Tree := ATree;
    Plan.Lookup := ALookup;
    Plan.Capture := ACapture;
    Result := Plan.Analyze(APosition, AReason) and Plan.Build(Trim(AName), AStyle, True, AResult, AReason);
  finally
    Plan.Free;
  end;
end;

class function TAnonymousMethods.Embed(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TAnonymousLookup; const AStyle: TFormatStyle; out AAction: TCodeAction;
  out AReason: string): Boolean;
begin
  Result := EmbedCore(AText, ATree, APosition, ALookup, AStyle, AAction, AReason);
end;

end.
