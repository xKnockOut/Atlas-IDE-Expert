unit Atlas.Common.Editing.NestedRoutines;

// Lokale Routine und Methode ineinander umwandeln (#663):
//   In private Methode umwandeln (auf dem Kopf einer lokalen Routine in einer
//     Methode): Der Rumpf wandert hinter die äußere Methode als TKlasse.Name,
//     die Deklaration in den private-Abschnitt der Klasse (legt ihn an, wenn
//     er fehlt). Variablen, Konstanten und Parameter der äußeren Routine, die
//     die lokale nutzt, werden Parameter: var, wenn sie geschrieben werden
//     (auch als var-Argument), const bei reinem Lesen von Strings, Records
//     und Interfaces, sonst ohne Modifizierer. Untypisierte Konstanten
//     wandern als Konstanten mit. Die Aufrufe bekommen die neuen Argumente,
//     ein vergebener Name bekommt eine Nummer.
//   Aus Routine herauslösen: dasselbe für eine lokale Routine einer freien
//     Routine; sie steht danach vor ihr in der Unit.
//   Als lokale Routine einbetten (auf einer privaten Methode mit genau einem
//     Aufruf, und zwar im Rumpf einer anderen Methode derselben Klasse; nicht
//     virtual, dynamic, override, abstract, message, overload, nicht als
//     Ereignis oder Methodenzeiger benutzt): Der Rumpf wird lokale Routine des
//     Aufrufers, die Deklaration verschwindet aus der Klasse.
//   In lokale Routine umwandeln: dasselbe für eine freie Routine der
//     Implementierung, die nicht im interface steht.
//   Mit „durchgereichte Parameter entfernen“ fallen Parameter weg, denen der
//     Aufruf nur eine Variable oder einen Parameter des Aufrufers übergibt;
//     der Rumpf nutzt dann diese direkt.
// Nicht angeboten wird, wenn sich die Bedeutung eines Namens ändern könnte:
// die lokale Routine nutzt Result, eine andere lokale Routine oder einen
// lokalen Typ der äußeren, enthält with, fängt einen künftigen var-Parameter
// in einer anonymen Methode ein oder wird anders als aufgerufen benutzt; beim
// Einbetten verdeckt ein Name des Aufrufers einen Namen des Rumpfs. Liegt die
// lokale Routine in einer anderen lokalen Routine, gibt es statt der Aktion
// einen Hinweis. Jede Aktion ist ein Rückgängig-Schritt und trägt eine
// Vorschau mit der neuen Signatur und der Zahl der geänderten Aufrufe.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions;

type
  /// <summary>Ist der Typ ATypeName an AOffset ein Record oder Interface (dann const beim reinen Lesen)?</summary>
  TConstTypeFunc = reference to function(const ATypeName: string; AOffset: Integer): Boolean;

  TNestedRoutineLookup = record
    ConstType: TConstTypeFunc;
    /// <summary>Art der Argumente bekannter Aufrufe (var-Argumente schreiben).</summary>
    Flow: TFlowSignatureLookup;
    /// <summary>Ohne Namensauflösung: Aufrufe aus der Datei, Records und Interfaces unbekannt.</summary>
    class function FromTree(ATree: TSyntaxTree): TNestedRoutineLookup; static;
    /// <summary>Typen über AResolver für ATree der Datei AFileName (Baum festhalten, solange gebraucht).</summary>
    class function FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName: string): TNestedRoutineLookup; static;
  end;

  TNestedRoutines = class
  public const
    ToMethodTitle = 'In private Methode umwandeln';
    ToUnitRoutineTitle = 'Aus Routine herauslösen';
    EmbedMethodTitle = 'Als lokale Routine einbetten';
    EmbedRoutineTitle = 'In lokale Routine umwandeln';
    PassThroughSuffix = ' (durchgereichte Parameter entfernen)';
  public
    /// <summary>„In private Methode umwandeln“ bzw. „Aus Routine herauslösen“ für die lokale Routine, deren Kopf
    /// APosition enthält. Liegt sie in einer anderen lokalen Routine, ist AAction.Disabled der Hinweis.</summary>
    class function Extract(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
      overload; static;
    /// <summary>Wie oben; AReason nennt, warum es nicht geht.</summary>
    class function Extract(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; out AAction: TCodeAction;
      out AReason: string): Boolean; overload; static;
    /// <summary>„Als lokale Routine einbetten“ bzw. „In lokale Routine umwandeln“ für die Routine, deren Kopf
    /// (Implementierung oder Klassendeklaration) APosition enthält; mit ARemovePassThrough ohne die
    /// durchgereichten Parameter (False, wenn es keine gibt).</summary>
    class function Embed(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; ARemovePassThrough: Boolean;
      out AAction: TCodeAction): Boolean; overload; static;
    /// <summary>Wie oben; AReason nennt, warum es nicht geht.</summary>
    class function Embed(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; ARemovePassThrough: Boolean;
      out AAction: TCodeAction; out AReason: string): Boolean; overload; static;
    /// <summary>Alle passenden Aktionen an APosition.</summary>
    class function Actions(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle): TArray<TCodeAction>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.CreateMethod;

type
  /// <summary>Änderung in Offsets des Dokuments.</summary>
  TOffsetEdit = record
    Start: Integer;
    Stop: Integer;
    Text: string;
    class function Create(AStart, AStop: Integer; const AText: string): TOffsetEdit; static;
  end;

  /// <summary>Name der äußeren Routine, den die lokale nutzt.</summary>
  TCaptured = record
    Local: TRoutineLocal;
    Written: Boolean;
    /// <summary>In einer anonymen Methode benutzt (darf kein var-Parameter werden).</summary>
    InAnonymous: Boolean;
  end;

  /// <summary>Ein Parameter einer Deklaration, einzeln auch bei "A, B: Integer".</summary>
  TParameterText = record
    Modifier: string;
    Name: string;
    /// <summary>": Typ" samt Vorgabewert; '' ohne Typ.</summary>
    Rest: string;
    function Text: string;
  end;

  /// <summary>Lokale Namen je Routine, einmal gesammelt.</summary>
  TLocalsCache = class
  private
    FText: string;
    FTree: TSyntaxTree;
    FLocals: TDictionary<TSyntaxNode, TArray<TRoutineLocal>>;
  public
    constructor Create(const AText: string; ATree: TSyntaxTree);
    destructor Destroy; override;
    function Locals(ARoutine: TSyntaxNode): TArray<TRoutineLocal>;
    /// <summary>Deklariert ARoutine den Namen AName (lokal, lokale Routine, lokaler Typ, Result) für AOffset?</summary>
    function Declares(ARoutine: TSyntaxNode; const AName: string; AOffset: Integer): Boolean;
  end;

{ TOffsetEdit }

class function TOffsetEdit.Create(AStart, AStop: Integer; const AText: string): TOffsetEdit;
begin
  Result.Start := AStart;
  Result.Stop := AStop;
  Result.Text := AText;
end;

{ TParameterText }

function TParameterText.Text: string;
begin
  Result := Name + Rest;
  if Modifier <> '' then
    Result := Modifier + ' ' + Result;
end;

{ Hilfen }

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

/// <summary>Kopf einer Routine.</summary>
function HeaderOf(ARoutine: TSyntaxNode): TSyntaxNode;
begin
  Result := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
end;

/// <summary>Ist die Routine eine Funktion (Ergebnistyp im Kopf)?</summary>
function IsFunction(ARoutine: TSyntaxNode): Boolean;
var
  Header: TSyntaxNode;
begin
  Header := HeaderOf(ARoutine);
  Result := (Header <> nil) and (Header.FindChild(TSyntaxKind.TypeReference) <> nil);
end;

function Encloses(ANode: TSyntaxNode; AOffset: Integer): Boolean;
begin
  Result := (ANode <> nil) and (ANode.StartOffset <= AOffset) and (AOffset <= ANode.EndOffset);
end;

/// <summary>Innerste Routine, deren Kopf AOffset enthält; nil ohne.</summary>
function RoutineWithHeaderAt(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
  Offset: Integer;
begin
  Found := nil;
  Offset := AOffset;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Header: TSyntaxNode;
    begin
      Result := Encloses(ANode, Offset);
      if Result and (ANode.Kind = TSyntaxKind.RoutineDecl) then
      begin
        Header := HeaderOf(ANode);
        if Encloses(Header, Offset) then
          Found := ANode;
      end;
    end);
  Result := Found;
end;

function LineIsBlank(const ALines: TArray<string>; ALine: Integer): Boolean;
begin
  Result := (ALine >= 0) and (ALine <= High(ALines)) and (Trim(ALines[ALine]) = '');
end;

/// <summary>Wendet AEdits (Offsets in AText, ab ABase) auf ASource = Copy(AText, ABase + 1, …) an.</summary>
function ApplyEdits(const ASource: string; ABase: Integer; AEdits: TArray<TOffsetEdit>): string;
var
  Index, Inner: Integer;
  Edit: TOffsetEdit;
begin
  // Von hinten nach vorn; nach Start sortiert (einfaches Einfügen, die Listen sind kurz).
  for Index := 1 to High(AEdits) do
  begin
    Edit := AEdits[Index];
    Inner := Index - 1;
    while (Inner >= 0) and (AEdits[Inner].Start > Edit.Start) do
    begin
      AEdits[Inner + 1] := AEdits[Inner];
      Dec(Inner);
    end;
    AEdits[Inner + 1] := Edit;
  end;
  Result := ASource;
  for Index := High(AEdits) downto 0 do
    Result := Copy(Result, 1, AEdits[Index].Start - ABase) + AEdits[Index].Text +
      Copy(Result, AEdits[Index].Stop - ABase + 1, MaxInt);
end;

/// <summary>Token-Bereich des Namens im Kopf (TKunde.Rechne bzw. Rechne).</summary>
function NameTokens(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode; out AFirst, ALast: Integer): Boolean;
var
  Index: Integer;
begin
  Result := False;
  Index := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  while (Index <= High(ATokens)) and (ATokens[Index].Offset < AHeader.EndOffset) and
    (ATokens[Index].IsKeyword('class') or ATokens[Index].IsKeyword('procedure') or
    ATokens[Index].IsKeyword('function') or (ATokens[Index].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive])) do
    Inc(Index);
  if (Index > High(ATokens)) or (ATokens[Index].Kind <> TPascalTokenKind.Identifier) then
    Exit;
  AFirst := Index;
  ALast := Index;
  while (ALast + 2 <= High(ATokens)) and ATokens[ALast + 1].IsSymbol('.') and
    (ATokens[ALast + 2].Kind = TPascalTokenKind.Identifier) do
    Inc(ALast, 2);
  Result := True;
end;

/// <summary>Beginnt der Kopf mit class (Klassenmethode)?</summary>
function IsClassHeader(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  Result := (Index <= High(ATokens)) and ATokens[Index].IsKeyword('class');
end;

/// <summary>Steht im Bereich des Knotens ein Token mit dem Text AWord (Direktive wie static, virtual)?</summary>
function HasWord(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode; const AWords: array of string): Boolean;
var
  Index: Integer;
begin
  Index := TRoutineBody.TokenAt(ATokens, ANode.StartOffset);
  while (Index <= High(ATokens)) and (ATokens[Index].Offset < ANode.EndOffset) do
  begin
    if (ATokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      MatchText(ATokens[Index].Text, AWords) then
      Exit(True);
    Inc(Index);
  end;
  Result := False;
end;

/// <summary>Parameter des Kopfs einzeln, mit Modifizierer und Typ.</summary>
function ParameterTexts(const AText: string; AHeader: TSyntaxNode): TArray<TParameterText>;
var
  Parameters, Node: TSyntaxNode;
  Index, Colon: Integer;
  Source, Head, Modifier, Name: string;
  Item: TParameterText;
begin
  Result := nil;
  Parameters := AHeader.FindChild(TSyntaxKind.Parameters);
  if Parameters = nil then
    Exit;
  for Index := 0 to Parameters.ChildCount - 1 do
  begin
    Node := Parameters[Index];
    Source := Trim(TRoutineBody.TextOf(AText, Node));
    if EndsStr(';', Source) then
      Source := Trim(Copy(Source, 1, Length(Source) - 1));
    Colon := Pos(':', Source);
    if Colon > 0 then
    begin
      Head := Trim(Copy(Source, 1, Colon - 1));
      Item.Rest := ': ' + Trim(Copy(Source, Colon + 1, MaxInt));
    end
    else
    begin
      Head := Source;
      Item.Rest := '';
    end;
    Modifier := '';
    if MatchText(Head.Split([' '])[0], ['const', 'var', 'out', 'constref']) then
    begin
      Modifier := Head.Split([' '])[0];
      Head := Trim(Copy(Head, Length(Modifier) + 1, MaxInt));
    end;
    if StartsText('[ref]', Head) then
      Exit(nil);
    Item.Modifier := Modifier;
    for Name in Head.Split([',']) do
    begin
      Item.Name := Trim(Name);
      Result := Result + [Item];
    end;
  end;
end;

function JoinParameters(const AParameters: TArray<TParameterText>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AParameters) do
  begin
    if Index > 0 then
      Result := Result + '; ';
    Result := Result + AParameters[Index].Text;
  end;
end;

/// <summary>Kopf als Text mit neuem Namen und neuen Parametern (ohne Direktiven, mit ';').</summary>
function HeadText(const AText: string; const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode;
  const AName: string; const AParameters: TArray<TParameterText>; AClass: Boolean): string;
var
  ResultType: TSyntaxNode;
begin
  if IsFunction(AHeader.Parent) then
    Result := 'function '
  else
    Result := 'procedure ';
  if AClass then
    Result := 'class ' + Result;
  Result := Result + AName;
  if AParameters <> nil then
    Result := Result + '(' + JoinParameters(AParameters) + ')';
  ResultType := AHeader.FindChild(TSyntaxKind.TypeReference);
  if ResultType <> nil then
    Result := Result + ': ' + TRoutineBody.TextOf(AText, ResultType);
  Result := Result + ';';
end;

/// <summary>Namen der Kinder von ANode ("A, B" einzeln).</summary>
function ChildNames(ANode: TSyntaxNode): TArray<string>;
var
  Index: Integer;
  Name: string;
begin
  Result := nil;
  for Index := 0 to ANode.ChildCount - 1 do
    for Name in ANode[Index].Name.Split([',']) do
      if Trim(Name) <> '' then
        Result := Result + [Trim(Name)];
end;

/// <summary>Namen auf Unit-Ebene: Routinen, Typen, Variablen und Konstanten beider Teile.</summary>
function UnitNames(ARoot: TSyntaxNode): TArray<string>;
var
  Section, Child: TSyntaxNode;
  Index, Inner: Integer;
  Name: string;
begin
  Result := nil;
  for Index := 0 to ARoot.ChildCount - 1 do
  begin
    Section := ARoot[Index];
    if not (Section.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]) then
      Continue;
    for Inner := 0 to Section.ChildCount - 1 do
    begin
      Child := Section[Inner];
      case Child.Kind of
        TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader:
          if TRoutineBody.QualifierOf(Child.Name) = '' then
            Result := Result + [Child.Name];
        TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
          for Name in ChildNames(Child) do
            Result := Result + [Name];
      end;
    end;
  end;
end;

/// <summary>Freier Name aus ABase: ABase, ABase2, ABase3 …, der in ATaken nicht vorkommt.</summary>
function FreeName(const ABase: string; const ATaken: TArray<string>): string;
var
  Number: Integer;
begin
  Result := ABase;
  Number := 1;
  while IndexText(Result, ATaken) >= 0 do
  begin
    Inc(Number);
    Result := ABase + IntToStr(Number);
  end;
end;

{ TLocalsCache }

constructor TLocalsCache.Create(const AText: string; ATree: TSyntaxTree);
begin
  inherited Create;
  FText := AText;
  FTree := ATree;
  FLocals := TDictionary<TSyntaxNode, TArray<TRoutineLocal>>.Create;
end;

destructor TLocalsCache.Destroy;
begin
  FLocals.Free;
  inherited;
end;

function TLocalsCache.Locals(ARoutine: TSyntaxNode): TArray<TRoutineLocal>;
begin
  if not FLocals.TryGetValue(ARoutine, Result) then
  begin
    Result := nil;
    if TRoutineBody.BodyOf(ARoutine) <> nil then
      Result := TRoutineLocals.Collect(FText, FTree, ARoutine);
    FLocals.Add(ARoutine, Result);
  end;
end;

function TLocalsCache.Declares(ARoutine: TSyntaxNode; const AName: string; AOffset: Integer): Boolean;
var
  Local: TRoutineLocal;
  Index: Integer;
  Child: TSyntaxNode;
  Name: string;
begin
  if SameText(AName, 'Result') and IsFunction(ARoutine) then
    Exit(True);
  for Local in Locals(ARoutine) do
    if SameText(Local.Name, AName) and ((Local.Kind in [TRoutineLocalKind.Parameter, TRoutineLocalKind.Variable,
      TRoutineLocalKind.Constant]) or ((Local.ScopeStart <= AOffset) and (AOffset <= Local.ScopeEnd))) then
      Exit(True);
  for Index := 0 to ARoutine.ChildCount - 1 do
  begin
    Child := ARoutine[Index];
    if (Child.Kind = TSyntaxKind.RoutineDecl) and SameText(Child.Name, AName) then
      Exit(True);
    if Child.Kind = TSyntaxKind.TypeSection then
      for Name in ChildNames(Child) do
        if SameText(Name, AName) then
          Exit(True);
  end;
  Result := False;
end;

{ TNestedRoutineLookup }

class function TNestedRoutineLookup.FromTree(ATree: TSyntaxTree): TNestedRoutineLookup;
begin
  Result.ConstType := nil;
  Result.Flow := nil;
  if (ATree <> nil) and (ATree.Root <> nil) then
    Result.Flow := TFlowSignatures.FromTree(ATree.Root);
end;

class function TNestedRoutineLookup.FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TNestedRoutineLookup;
var
  FileName: string;
begin
  Result := FromTree(ATree);
  FileName := AFileName;
  Result.ConstType :=
    function(const ATypeName: string; AOffset: Integer): Boolean
    var
      Resolved: TResolvedSymbol;
      Base: string;
    begin
      Base := ATypeName;
      if Pos('<', Base) > 0 then
        Base := Copy(Base, 1, Pos('<', Base) - 1);
      Resolved := AResolver.ResolveChain(ATree, FileName, Trim(Base).Split(['.']), AOffset);
      Result := Resolved.Found and Resolved.IsType and (Resolved.SymbolKind in [TIndexSymbolKind.RecordType,
        TIndexSymbolKind.ObjectType, TIndexSymbolKind.InterfaceType]);
    end;
end;

{ Umwandlung: lokale Routine heraus }

/// <summary>Modifizierer des neuen Parameters für den Namen ACaptured.</summary>
function ModeOf(const ACaptured: TCaptured; const ALookup: TNestedRoutineLookup; AOffset: Integer): string;
begin
  Result := '';
  if ACaptured.Written then
    Result := 'var'
  else if TCreateMethod.WantsConst(ACaptured.Local.TypeText, False, False) or
    (Assigned(ALookup.ConstType) and ALookup.ConstType(ACaptured.Local.TypeText, AOffset)) then
    Result := 'const';
end;

/// <summary>Bearbeitung, die AArguments an den Aufruf des Bezeichners ANode anhängt bzw. ihn in ANewName
/// umbenennt; False, wenn die Routine dort nicht aufgerufen, sondern anders benutzt wird.</summary>
function CallEdit(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode; AIsFunction: Boolean;
  const ANewName, AArguments: string; var AEdits: TArray<TOffsetEdit>): Boolean;
var
  Parent: TSyntaxNode;
  Close: Integer;
begin
  Result := True;
  Parent := ANode.Parent;
  if (Parent <> nil) and (Parent.Kind = TSyntaxKind.Call) and (Parent[0] = ANode) then
  begin
    if not SameText(ANode.Name, ANewName) then
      AEdits := AEdits + [TOffsetEdit.Create(ANode.StartOffset, ANode.EndOffset, ANewName)];
    if AArguments = '' then
      Exit;
    if Parent.ChildCount > 1 then
      AEdits := AEdits + [TOffsetEdit.Create(Parent[Parent.ChildCount - 1].EndOffset,
        Parent[Parent.ChildCount - 1].EndOffset, ', ' + AArguments)]
    else
    begin
      Close := TRoutineBody.PreviousToken(ATokens, TRoutineBody.TokenAt(ATokens, Parent.EndOffset));
      if (Close < 0) or not ATokens[Close].IsSymbol(')') then
        Exit(False);
      AEdits := AEdits + [TOffsetEdit.Create(ATokens[Close].Offset, ATokens[Close].Offset, AArguments)];
    end;
    Exit;
  end;
  // Ohne Klammern: als Anweisung, bei Funktionen auch in Ausdrücken; nicht als Wert (@X, Argument, Zuweisung).
  if (Parent = nil) or (Parent.Kind in [TSyntaxKind.AddressOf, TSyntaxKind.Call, TSyntaxKind.MemberAccess]) or
    ((Parent.Kind = TSyntaxKind.AssignStatement) and (Parent[0] = ANode)) or
    ((Parent.Kind <> TSyntaxKind.CallStatement) and not AIsFunction) or
    ((Parent.Kind = TSyntaxKind.AssignStatement) and not AIsFunction) then
    Exit(False);
  if AArguments = '' then
  begin
    if not SameText(ANode.Name, ANewName) then
      AEdits := AEdits + [TOffsetEdit.Create(ANode.StartOffset, ANode.EndOffset, ANewName)];
    Exit;
  end;
  AEdits := AEdits + [TOffsetEdit.Create(ANode.StartOffset, ANode.EndOffset, ANewName + '(' + AArguments + ')')];
end;

/// <summary>Rumpf von ANode bis AStop (ausschließlich): liegt ANode in einer anonymen Methode?</summary>
function InAnonymous(ANode, AStop: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := ANode.Parent;
  while (Node <> nil) and (Node <> AStop) do
  begin
    if Node.Kind = TSyntaxKind.AnonymousMethod then
      Exit(True);
    Node := Node.Parent;
  end;
  Result := False;
end;

/// <summary>Deklariert eine Routine zwischen ANode und AStop (AStop eingeschlossen, wenn AWithStop) den Namen?
/// </summary>
function Shadowed(ACache: TLocalsCache; ANode, AStop: TSyntaxNode; const AName: string; AWithStop: Boolean): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := ANode.Parent;
  while (Node <> nil) and (Node <> AStop) do
  begin
    if (Node.Kind = TSyntaxKind.RoutineDecl) and ACache.Declares(Node, AName, ANode.StartOffset) then
      Exit(True);
    Node := Node.Parent;
  end;
  Result := AWithStop and (Node = AStop) and ACache.Declares(AStop, AName, ANode.StartOffset);
end;

/// <summary>Kommt ein Bezeichner AName unter AIdentifiers vor?</summary>
function UsesName(const AIdentifiers: TArray<TSyntaxNode>; const AName: string): Boolean;
var
  Node: TSyntaxNode;
begin
  for Node in AIdentifiers do
    if SameText(Node.Name, AName) then
      Exit(True);
  Result := False;
end;

/// <summary>Schreibt der Rumpf von ARoutine den eigenen Namen AName (Zuweisung, var-Argument, @)?</summary>
function WritesName(ACache: TLocalsCache; const AIdentifiers: TArray<TSyntaxNode>; ARoutine: TSyntaxNode;
  const AName: string; const AFlow: TFlowSignatureLookup): Boolean;
var
  Node: TSyntaxNode;
begin
  for Node in AIdentifiers do
    if SameText(Node.Name, AName) and not Shadowed(ACache, Node, ARoutine, AName, False) and
      (TRoutineLocals.AccessOf(Node, AFlow) <> TLocalAccess.Read) then
      Exit(True);
  Result := False;
end;

function ExtractCore(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; out AAction: TCodeAction;
  out AReason: string): Boolean;
var
  Lines: TLineTable;
  TextLines: TArray<string>;
  Tokens: TArray<TPascalToken>;
  Inner, Outer, Header, OuterHeader, Node, TypeBody, Child: TSyntaxNode;
  Cache: TLocalsCache;
  OuterLocals: TArray<TRoutineLocal>;
  Local: TRoutineLocal;
  Captured: TArray<TCaptured>;
  Identifiers: TList<TSyntaxNode>;
  Index, Found, Calls, FirstLine, LastLine, RemoveStart, RemoveEnd, InsertLine, NameFirst, NameLast: Integer;
  ClassName, NewName, Name, Arguments, LineBreak, Indent, InnerIndent, Moved, Declaration, ConstLines,
    Mode: string;
  Parameters: TArray<TParameterText>;
  Parameter: TParameterText;
  InnerEdits, OuterEdits: TArray<TOffsetEdit>;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
  Taken: TArray<string>;
  IsMethod, IsClass, InnerIsFunction: Boolean;
begin
  AAction := Default(TCodeAction);
  AReason := '';
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit(Fail('kein Baum', AReason));
  Lines := TLineTable.Build(AText);
  Inner := RoutineWithHeaderAt(ATree, Lines.OffsetAt(APosition));
  if (Inner = nil) or (Inner.Parent = nil) or (Inner.Parent.Kind <> TSyntaxKind.RoutineDecl) then
    Exit(Fail('keine lokale Routine', AReason));
  Outer := Inner.Parent;
  ClassName := TRoutineBody.QualifierOf(Outer.Name);
  IsMethod := ClassName <> '';
  if IsMethod then
    AAction.Title := TNestedRoutines.ToMethodTitle
  else
    AAction.Title := TNestedRoutines.ToUnitRoutineTitle;
  AAction.Kind := RewriteKind;
  if (Outer.Parent <> nil) and (Outer.Parent.Kind = TSyntaxKind.RoutineDecl) then
  begin
    // Hinweis statt Aktion: Die mittlere Routine müsste erst selbst heraus.
    AAction.Disabled := Format('%s liegt in der lokalen Routine %s; erst diese umwandeln', [Inner.Name, Outer.Name]);
    Exit(True);
  end;
  Tokens := ATree.Tokens;
  Header := HeaderOf(Inner);
  OuterHeader := HeaderOf(Outer);
  if (Header = nil) or (OuterHeader = nil) or (TRoutineBody.BodyOf(Inner) = nil) then
    Exit(Fail('Routine ohne Rumpf', AReason));
  if HasWord(Tokens, Header, ['forward', 'external', 'overload', 'assembler']) or
    TRoutineLocals.HasKind(Inner, TSyntaxKind.WithStatement) or (Pos('<', ClassName) > 0) then
    Exit(Fail('nicht unterstützte Form', AReason));
  IsClass := IsClassHeader(Tokens, OuterHeader);
  InnerIsFunction := IsFunction(Inner);
  TypeBody := nil;
  if IsMethod then
  begin
    TypeBody := TRoutineBody.TypeBody(ATree.Root, TRoutineBody.ShortNameOf(ClassName));
    if TypeBody = nil then
      Exit(Fail('Klasse ' + ClassName + ' nicht in der Datei', AReason));
  end;
  Cache := TLocalsCache.Create(AText, ATree);
  Identifiers := TList<TSyntaxNode>.Create;
  try
    OuterLocals := Cache.Locals(Outer);
    Captured := nil;
    InnerEdits := nil;
    OuterEdits := nil;
    // Namen der lokalen Routine, die die äußere deklariert.
    TRoutineLocals.CollectKind(Inner, TSyntaxKind.Identifier, Identifiers);
    for Node in Identifiers do
    begin
      if Shadowed(Cache, Node, Inner, Node.Name, True) then
        Continue;
      if SameText(Node.Name, Inner.Name) then
        Continue;
      if SameText(Node.Name, 'Result') and IsFunction(Outer) then
        Exit(Fail('Result der äußeren Routine', AReason));
      if not IsMethod and SameText(Node.Name, Outer.Name) then
        Exit(Fail('ruft die äußere Routine auf', AReason));
      Found := -1;
      for Index := 0 to High(OuterLocals) do
        if SameText(OuterLocals[Index].Name, Node.Name) and ((OuterLocals[Index].Kind =
          TRoutineLocalKind.Parameter) or ((OuterLocals[Index].Kind in [TRoutineLocalKind.Variable,
          TRoutineLocalKind.Constant]) and (OuterLocals[Index].Decl.StartOffset < Inner.StartOffset))) then
          Found := Index;
      if Found < 0 then
      begin
        for Index := 0 to Outer.ChildCount - 1 do
        begin
          Child := Outer[Index];
          if (Child <> Inner) and (Child.Kind = TSyntaxKind.RoutineDecl) and SameText(Child.Name, Node.Name) and
            (Child.StartOffset < Inner.StartOffset) then
            Exit(Fail('nutzt die lokale Routine ' + Child.Name, AReason));
          if (Child.Kind = TSyntaxKind.TypeSection) and (IndexText(Node.Name, ChildNames(Child)) >= 0) and
            (Child.StartOffset < Inner.StartOffset) then
            Exit(Fail('nutzt den lokalen Typ ' + Node.Name, AReason));
        end;
        Continue;
      end;
      Index := 0;
      while (Index <= High(Captured)) and not SameText(Captured[Index].Local.Name, OuterLocals[Found].Name) do
        Inc(Index);
      if Index > High(Captured) then
      begin
        SetLength(Captured, Length(Captured) + 1);
        Captured[Index].Local := OuterLocals[Found];
        Captured[Index].Written := False;
        Captured[Index].InAnonymous := False;
      end;
      if TRoutineLocals.AccessOf(Node, ALookup.Flow) <> TLocalAccess.Read then
        Captured[Index].Written := True;
      if InAnonymous(Node, Inner) then
        Captured[Index].InAnonymous := True;
    end;
    // Lokale Typen der äußeren Routine auch in Typangaben.
    Identifiers.Clear;
    TRoutineLocals.CollectKind(Inner, TSyntaxKind.TypeReference, Identifiers);
    for Node in Identifiers do
      for Index := 0 to Outer.ChildCount - 1 do
        if (Outer[Index].Kind = TSyntaxKind.TypeSection) and (IndexText(Node.Name, ChildNames(Outer[Index])) >= 0) and
          not Shadowed(Cache, Node, Inner, Node.Name, True) then
          Exit(Fail('nutzt den lokalen Typ ' + Node.Name, AReason));
    // Neue Parameter; untypisierte Konstanten wandern als Konstanten mit.
    Parameters := ParameterTexts(AText, Header);
    if (Parameters = nil) and (Header.FindChild(TSyntaxKind.Parameters) <> nil) and
      (Header.FindChild(TSyntaxKind.Parameters).ChildCount > 0) then
      Exit(Fail('nicht unterstützte Parameter', AReason));
    Arguments := '';
    ConstLines := '';
    LineBreak := TTextLines.LineBreakOf(AText);
    InnerIndent := TTextLines.IndentOf(AText, Inner.StartPos.Line);
    for Index := 0 to High(Captured) do
    begin
      Local := Captured[Index].Local;
      if Local.Kind = TRoutineLocalKind.Constant then
      begin
        if Captured[Index].Written then
          Exit(Fail('schreibt die Konstante ' + Local.Name, AReason));
        if ConstLines = '' then
          ConstLines := LineBreak + InnerIndent + 'const';
        ConstLines := ConstLines + LineBreak + InnerIndent + TRoutineBody.IndentUnit(AStyle) +
          TRoutineBody.TextOf(AText, Local.Decl);
        Continue;
      end;
      if Local.TypeText = '' then
        Exit(Fail(Local.Name + ' hat keinen Typ', AReason));
      Mode := ModeOf(Captured[Index], ALookup, Inner.StartOffset);
      if (Mode = 'var') and Captured[Index].InAnonymous then
        Exit(Fail('eine anonyme Methode fängt ' + Local.Name + ' ein', AReason));
      Parameter.Modifier := Mode;
      Parameter.Name := Local.Name;
      Parameter.Rest := ': ' + Local.TypeText;
      Parameters := Parameters + [Parameter];
      if Arguments <> '' then
        Arguments := Arguments + ', ';
      Arguments := Arguments + Local.Name;
    end;
    // Freier Name.
    if IsMethod then
      Taken := TRoutineBody.MemberNames(TypeBody)
    else
      Taken := UnitNames(ATree.Root);
    NewName := FreeName(Inner.Name, Taken);
    // Aufrufe in der äußeren Routine (auch in den anderen lokalen Routinen) und in der lokalen selbst.
    Calls := 0;
    Identifiers.Clear;
    TRoutineLocals.CollectKind(Outer, TSyntaxKind.Identifier, Identifiers);
    for Node in Identifiers do
    begin
      if not SameText(Node.Name, Inner.Name) then
        Continue;
      if TRoutineBody.Within(Node, Inner) then
      begin
        // Rekursion: Ein innerer Name verdeckt die Routine oder ein neues Argument.
        if Shadowed(Cache, Node, Inner, Node.Name, True) then
          Continue;
        for Index := 0 to High(Captured) do
          if Shadowed(Cache, Node, Inner, Captured[Index].Local.Name, False) then
            Exit(Fail('ein Name verdeckt ' + Captured[Index].Local.Name, AReason));
        if not CallEdit(Tokens, Node, InnerIsFunction, NewName, Arguments, InnerEdits) then
          Exit(Fail(Inner.Name + ' wird nicht nur aufgerufen', AReason));
        Continue;
      end;
      if Shadowed(Cache, Node, Outer, Node.Name, False) then
        Continue;
      // Eine Inline- oder Schleifenvariable gleichen Namens verdeckt die Routine.
      Found := TRoutineLocals.IndexOf(OuterLocals, Node.Name, Node.StartOffset);
      if (Found >= 0) and (OuterLocals[Found].Kind in [TRoutineLocalKind.InlineVariable,
        TRoutineLocalKind.LoopVariable]) then
        Continue;
      for Index := 0 to High(Captured) do
      begin
        if Shadowed(Cache, Node, Outer, Captured[Index].Local.Name, False) then
          Exit(Fail('ein Name verdeckt ' + Captured[Index].Local.Name, AReason));
        Found := TRoutineLocals.IndexOf(OuterLocals, Captured[Index].Local.Name, Node.StartOffset);
        if (Found >= 0) and (OuterLocals[Found].Decl <> Captured[Index].Local.Decl) then
          Exit(Fail('ein Name verdeckt ' + Captured[Index].Local.Name, AReason));
      end;
      if not CallEdit(Tokens, Node, InnerIsFunction, NewName, Arguments, OuterEdits) then
        Exit(Fail(Inner.Name + ' wird nicht nur aufgerufen', AReason));
      Inc(Calls);
    end;
    // Kopf der neuen Routine.
    if not NameTokens(Tokens, Header, NameFirst, NameLast) then
      Exit(Fail('Kopf nicht lesbar', AReason));
    Name := NewName;
    if IsMethod then
      Name := ClassName + '.' + NewName;
    InnerEdits := InnerEdits + [TOffsetEdit.Create(Header.StartOffset, Header.EndOffset,
      HeadText(AText, Tokens, Header, Name, Parameters, IsClass) + ConstLines)];
    Declaration := HeadText(AText, Tokens, Header, NewName, Parameters, IsClass);
    // Eine statische Klassenmethode hat kein Self: die neue auch nicht.
    if IsClass then
      for Index := 0 to TypeBody.ChildCount - 1 do
        if (TypeBody[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(TypeBody[Index].Name,
          TRoutineBody.ShortNameOf(Outer.Name)) and HasWord(Tokens, TypeBody[Index], ['static']) then
        begin
          Declaration := Declaration + ' static;';
          Break;
        end;
    // Text: ganze Zeilen samt Kommentaren darüber, eingerückt wie die äußere Routine.
    FirstLine := TRoutineBody.RoutineInsertLine(AText, Inner);
    LastLine := Inner.EndPos.Line;
    TextLines := TTextLines.SplitLines(AText);
    Indent := TTextLines.IndentOf(AText, Outer.StartPos.Line);
    Moved := ApplyEdits(Copy(AText, Lines.OffsetAt(TTextPosition.Create(FirstLine, 0)) + 1,
      Inner.EndOffset - Lines.OffsetAt(TTextPosition.Create(FirstLine, 0))),
      Lines.OffsetAt(TTextPosition.Create(FirstLine, 0)), InnerEdits);
    Moved := TRoutineBody.Reindent(TrimLeft(Moved), InnerIndent, Indent, LineBreak);
    Edits := nil;
    // Entfernen, mit einer der Leerzeilen um die Routine.
    // Folgt dann begin, auch die Leerzeile davor.
    RemoveStart := FirstLine;
    RemoveEnd := LastLine + 1;
    if LineIsBlank(TextLines, FirstLine - 1) and LineIsBlank(TextLines, RemoveEnd) then
      Inc(RemoveEnd);
    if LineIsBlank(TextLines, RemoveStart - 1) and (RemoveEnd = TRoutineBody.BodyOf(Outer).StartPos.Line) then
      Dec(RemoveStart);
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(RemoveStart, 0, RemoveEnd, 0), '')];
    for Index := 0 to High(OuterEdits) do
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Lines.PositionAt(OuterEdits[Index].Start),
        Lines.PositionAt(OuterEdits[Index].Stop)), OuterEdits[Index].Text)];
    if IsMethod then
    begin
      InsertLine := Outer.EndPos.Line + 1;
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(InsertLine, 0, InsertLine, 0),
        LineBreak + Moved + LineBreak)];
      if not TRoutineBody.MemberDeclaration(AText, ATree, TypeBody, 'private', Declaration, AStyle, Edit) then
        Exit(Fail('Klassendeklaration nicht erweiterbar', AReason));
      Edits := Edits + [Edit];
    end
    else
    begin
      InsertLine := TRoutineBody.RoutineInsertLine(AText, Outer);
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(InsertLine, 0, InsertLine, 0),
        Moved + LineBreak + LineBreak)];
    end;
    AAction.Edits := Edits;
    AAction.Preview := Format('Neue Signatur: %s', [HeadText(AText, Tokens, Header, Name, Parameters, IsClass)]) +
      LineBreak + Format('Geänderte Aufrufe: %d', [Calls]);
    Result := True;
  finally
    Identifiers.Free;
    Cache.Free;
  end;
end;

{ Umwandlung: Routine hinein }

/// <summary>Routine der Implementierung zum Kopf an AOffset, auch über die Deklaration in der Klasse.</summary>
function TopRoutineAt(ATree: TSyntaxTree; AOffset: Integer; out ADeclaration: TSyntaxNode): TSyntaxNode;
var
  Found, Implementation_: TSyntaxNode;
  Offset, Index: Integer;
  Name: string;
begin
  ADeclaration := nil;
  Result := RoutineWithHeaderAt(ATree, AOffset);
  if Result <> nil then
    Exit;
  Found := nil;
  Offset := AOffset;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := Encloses(ANode, Offset);
      if Result and (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]) then
        Found := ANode;
    end);
  if (Found = nil) or (Found.Parent.Parent = nil) then
    Exit;
  ADeclaration := Found;
  Name := Found.Parent.Parent.Name + '.' + Found.Name;
  Implementation_ := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Implementation_ = nil then
    Exit;
  for Index := 0 to Implementation_.ChildCount - 1 do
    if (Implementation_[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(Implementation_[Index].Name, Name) then
      Exit(Implementation_[Index]);
end;

function EmbedCore(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; ARemovePassThrough: Boolean;
  out AAction: TCodeAction; out AReason: string): Boolean;
var
  Lines: TLineTable;
  TextLines: TArray<string>;
  Tokens: TArray<TPascalToken>;
  Routine, Declaration, Header, TypeBody, Node, Reference, Caller, Call, CallerBody, Section, Child: TSyntaxNode;
  References, Identifiers, Arguments, Sections: TArray<TSyntaxNode>;
  Collected: TList<TSyntaxNode>;
  Cache: TLocalsCache;
  CallerLocals: TArray<TRoutineLocal>;
  Parameters, Kept: TArray<TParameterText>;
  Removed: TArray<Boolean>;
  Renamed: TDictionary<string, string>;
  Short, ClassName, LineBreak, Indent, Moved, Target, ArgumentText, ParameterType: string;
  IsMethod, IsClass, Recursive, Any: Boolean;
  Index, Found, FirstLine, RemoveEnd, BeginLine: Integer;
  RoutineEdits: TArray<TOffsetEdit>;
  Edits: TArray<TTextEdit>;
  Members: TArray<string>;
begin
  AAction := Default(TCodeAction);
  AReason := '';
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit(Fail('kein Baum', AReason));
  Lines := TLineTable.Build(AText);
  Tokens := ATree.Tokens;
  Routine := TopRoutineAt(ATree, Lines.OffsetAt(APosition), Declaration);
  if (Routine = nil) or (Routine.Parent = nil) or (Routine.Parent.Kind <> TSyntaxKind.ImplementationSection) then
    Exit(Fail('keine Routine der Implementierung', AReason));
  Header := HeaderOf(Routine);
  if (Header = nil) or (TRoutineBody.BodyOf(Routine) = nil) then
    Exit(Fail('Routine ohne Rumpf', AReason));
  Short := TRoutineBody.ShortNameOf(Routine.Name);
  ClassName := TRoutineBody.QualifierOf(Routine.Name);
  IsMethod := ClassName <> '';
  IsClass := IsClassHeader(Tokens, Header);
  if HasWord(Tokens, Header, ['overload', 'forward', 'external', 'export', 'assembler']) or (Pos('<', ClassName) > 0) or
    (Pos('.', ClassName) > 0) then
    Exit(Fail('nicht unterstützte Form', AReason));
  TypeBody := nil;
  if IsMethod then
  begin
    TypeBody := TRoutineBody.TypeBody(ATree.Root, ClassName);
    if TypeBody = nil then
      Exit(Fail('Klasse ' + ClassName + ' nicht in der Datei', AReason));
    Declaration := nil;
    for Index := 0 to TypeBody.ChildCount - 1 do
      if (TypeBody[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(TypeBody[Index].Name, Short) then
      begin
        if Declaration <> nil then
          Exit(Fail('überladen', AReason));
        Declaration := TypeBody[Index];
      end;
    if Declaration = nil then
      Exit(Fail('Deklaration fehlt', AReason));
    if not MatchText(TRoutineBody.VisibilityOf(TypeBody, Declaration), ['private', 'strict private']) then
      Exit(Fail('nicht privat', AReason));
    if HasWord(Tokens, Declaration, ['virtual', 'dynamic', 'override', 'abstract', 'message', 'overload',
      'reintroduce', 'final', 'static']) then
      Exit(Fail('virtuell, Botschaft oder überladen', AReason));
  end
  else
  begin
    // Im interface oder vorab deklariert: von außen bzw. vor der Implementierung sichtbar.
    Sections := [ATree.Root.FindChild(TSyntaxKind.InterfaceSection), Routine.Parent];
    for Section in Sections do
      if Section <> nil then
        for Index := 0 to Section.ChildCount - 1 do
        begin
          Child := Section[Index];
          if (Child <> Routine) and (Child.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl]) and
            SameText(Child.Name, Short) then
            Exit(Fail('auch anderswo deklariert', AReason));
        end;
  end;
  Cache := TLocalsCache.Create(AText, ATree);
  Collected := TList<TSyntaxNode>.Create;
  Renamed := TDictionary<string, string>.Create;
  try
    // Bezüge: genau ein Aufruf außerhalb der Routine.
    References := nil;
    Recursive := False;
    TRoutineLocals.CollectKind(ATree.Root, TSyntaxKind.Identifier, Collected);
    TRoutineLocals.CollectKind(ATree.Root, TSyntaxKind.MemberAccess, Collected);
    for Node in Collected do
    begin
      if not SameText(Node.Name, Short) then
        Continue;
      if Node.Kind = TSyntaxKind.MemberAccess then
      begin
        if not IsMethod or (Node[0].Kind <> TSyntaxKind.Identifier) or not SameText(Node[0].Name, 'Self') then
          Exit(Fail('über ein anderes Objekt benutzt', AReason));
      end
      else if Shadowed(Cache, Node, nil, Short, False) then
        Continue;
      if TRoutineBody.Within(Node, Routine) then
      begin
        Recursive := True;
        Continue;
      end;
      References := References + [Node];
    end;
    if Length(References) <> 1 then
      Exit(Fail('nicht genau ein Aufruf', AReason));
    Reference := References[0];
    Caller := Reference.Parent;
    while (Caller <> nil) and (Caller.Kind <> TSyntaxKind.RoutineDecl) do
      Caller := Caller.Parent;
    if (Caller = nil) or (Caller = Routine) or (Caller.Parent <> Routine.Parent) or
      not TRoutineBody.Within(Reference, TRoutineBody.BodyOf(Caller)) then
      Exit(Fail('Aufrufer ist keine Routine der Implementierung', AReason));
    if IsMethod and (not SameText(TRoutineBody.QualifierOf(Caller.Name), ClassName) or
      (IsClassHeader(Tokens, HeaderOf(Caller)) <> IsClass)) then
      Exit(Fail('Aufrufer ist keine Methode derselben Art', AReason));
    // Nur Aufrufe, kein Methodenzeiger oder Ereignis.
    Call := nil;
    Node := Reference.Parent;
    if (Node.Kind = TSyntaxKind.Call) and (Node[0] = Reference) then
      Call := Node
    else if (Node.Kind <> TSyntaxKind.CallStatement) and (not IsFunction(Routine) or
      (Node.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.Call, TSyntaxKind.AddressOf])) then
      Exit(Fail('nicht als Aufruf benutzt', AReason));
    Arguments := nil;
    if Call <> nil then
      for Index := 1 to Call.ChildCount - 1 do
        Arguments := Arguments + [Call[Index]];
    Parameters := ParameterTexts(AText, Header);
    if (Parameters = nil) and (Header.FindChild(TSyntaxKind.Parameters) <> nil) and
      (Header.FindChild(TSyntaxKind.Parameters).ChildCount > 0) then
      Exit(Fail('nicht unterstützte Parameter', AReason));
    SetLength(Removed, Length(Parameters));
    for Index := 0 to High(Removed) do
      Removed[Index] := False;
    Identifiers := nil;
    Collected.Clear;
    TRoutineLocals.CollectKind(TRoutineBody.BodyOf(Routine), TSyntaxKind.Identifier, Collected);
    Identifiers := Collected.ToArray;
    CallerLocals := Cache.Locals(Caller);
    // Durchgereichte Parameter: Argument ist eine Variable oder ein Parameter des Aufrufers mit demselben Typ.
    if ARemovePassThrough then
    begin
      if Recursive then
        Exit(Fail('rekursiv', AReason));
      Any := False;
      for Index := 0 to Min(High(Parameters), High(Arguments)) do
      begin
        if Arguments[Index].Kind <> TSyntaxKind.Identifier then
          Continue;
        Found := TRoutineLocals.IndexOf(CallerLocals, Arguments[Index].Name, Arguments[Index].StartOffset);
        if (Found < 0) or not (CallerLocals[Found].Kind in [TRoutineLocalKind.Parameter,
          TRoutineLocalKind.Variable]) then
          Continue;
        ParameterType := Trim(Copy(Parameters[Index].Rest, 2, MaxInt));
        if (ParameterType = '') or not SameText(ParameterType, CallerLocals[Found].TypeText) then
          Continue;
        Target := CallerLocals[Found].Name;
        if not SameText(Target, Parameters[Index].Name) and (Cache.Declares(Routine, Target, MaxInt) or
          UsesName(Identifiers, Target)) then
          Continue;
        if (Parameters[Index].Modifier = '') and WritesName(Cache, Identifiers, Routine, Parameters[Index].Name,
          ALookup.Flow) then
          Continue;
        Removed[Index] := True;
        Renamed.AddOrSetValue(LowerCase(Parameters[Index].Name), Target);
        Any := True;
      end;
      if not Any then
        Exit(Fail('keine durchgereichten Parameter', AReason));
    end;
    // Namen des Rumpfs, die der Aufrufer anders belegt, änderten ihre Bedeutung.
    CallerBody := TRoutineBody.BodyOf(Caller);
    if Cache.Declares(Caller, Short, CallerBody.StartOffset - 1) then
      Exit(Fail(Caller.Name + ' kennt schon ' + Short, AReason));
    Members := nil;
    if not IsMethod and (TRoutineBody.QualifierOf(Caller.Name) <> '') and (TRoutineBody.TypeBody(ATree.Root,
      TRoutineBody.QualifierOf(Caller.Name)) <> nil) then
      Members := TRoutineBody.MemberNames(TRoutineBody.TypeBody(ATree.Root, TRoutineBody.QualifierOf(Caller.Name)));
    for Node in Identifiers do
    begin
      if Shadowed(Cache, Node, Routine, Node.Name, True) then
        Continue;
      if Renamed.ContainsValue(Node.Name) then
        Continue;
      if Cache.Declares(Caller, Node.Name, CallerBody.StartOffset - 1) and not SameText(Node.Name, 'Result') then
        Exit(Fail(Caller.Name + ' verdeckt ' + Node.Name, AReason));
      if IndexText(Node.Name, Members) >= 0 then
        Exit(Fail('ein Mitglied der Klasse verdeckt ' + Node.Name, AReason));
    end;
    // Typangaben samt Kopf: ein lokaler Typ des Aufrufers verdeckte sie.
    Collected.Clear;
    TRoutineLocals.CollectKind(Routine, TSyntaxKind.TypeReference, Collected);
    for Node in Collected do
      if not Shadowed(Cache, Node, Routine, Node.Name, True) and Cache.Declares(Caller, Node.Name,
        CallerBody.StartOffset - 1) then
        Exit(Fail(Caller.Name + ' verdeckt ' + Node.Name, AReason));
    if SameText(Short, 'Result') then
      Exit(Fail('Name Result', AReason));
    // Rumpf: Kopf ohne Klasse, durchgereichte Parameter durch die Namen des Aufrufers ersetzt.
    Kept := nil;
    for Index := 0 to High(Parameters) do
      if not Removed[Index] then
        Kept := Kept + [Parameters[Index]];
    RoutineEdits := [TOffsetEdit.Create(Header.StartOffset, Header.EndOffset,
      HeadText(AText, Tokens, Header, Short, Kept, False))];
    for Node in Identifiers do
      if Renamed.TryGetValue(LowerCase(Node.Name), Target) and not Shadowed(Cache, Node, Routine, Node.Name, False) and
        not SameText(Node.Name, Target) then
        RoutineEdits := RoutineEdits + [TOffsetEdit.Create(Node.StartOffset, Node.EndOffset, Target)];
    LineBreak := TTextLines.LineBreakOf(AText);
    TextLines := TTextLines.SplitLines(AText);
    FirstLine := TRoutineBody.RoutineInsertLine(AText, Routine);
    Moved := ApplyEdits(Copy(AText, Lines.OffsetAt(TTextPosition.Create(FirstLine, 0)) + 1,
      Routine.EndOffset - Lines.OffsetAt(TTextPosition.Create(FirstLine, 0))),
      Lines.OffsetAt(TTextPosition.Create(FirstLine, 0)), RoutineEdits);
    Indent := TTextLines.IndentOf(AText, Caller.StartPos.Line) + TRoutineBody.IndentUnit(AStyle);
    Moved := TRoutineBody.Reindent(TrimLeft(Moved), TTextLines.IndentOf(AText, Routine.StartPos.Line), Indent,
      LineBreak);
    BeginLine := CallerBody.StartPos.Line;
    if CallerBody.StartPos.Character <> Length(TTextLines.IndentOf(AText, BeginLine)) then
      Exit(Fail('begin des Aufrufers steht nicht am Zeilenanfang', AReason));
    Edits := nil;
    RemoveEnd := Routine.EndPos.Line + 1;
    if LineIsBlank(TextLines, FirstLine - 1) and LineIsBlank(TextLines, RemoveEnd) then
      Inc(RemoveEnd);
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(FirstLine, 0, RemoveEnd, 0), '')];
    if Declaration <> nil then
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Declaration.StartPos.Line, 0,
        Declaration.EndPos.Line + 1, 0), '')];
    if LineIsBlank(TextLines, BeginLine - 1) then
      Moved := Moved + LineBreak + LineBreak
    else
      Moved := LineBreak + Moved + LineBreak + LineBreak;
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(BeginLine, 0, BeginLine, 0), Moved)];
    // Aufruf: Self. entfällt, durchgereichte Argumente auch.
    if Reference.Kind = TSyntaxKind.MemberAccess then
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Reference.StartPos, Reference.EndPos), Short)];
    if ARemovePassThrough then
    begin
      ArgumentText := '';
      for Index := 0 to High(Arguments) do
        if (Index > High(Removed)) or not Removed[Index] then
        begin
          if ArgumentText <> '' then
            ArgumentText := ArgumentText + ', ';
          ArgumentText := ArgumentText + TRoutineBody.TextOf(AText, Arguments[Index]);
        end;
      if ArgumentText <> '' then
        ArgumentText := '(' + ArgumentText + ')';
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Call[0].EndPos, Call.EndPos), ArgumentText)];
    end;
    if IsMethod then
      AAction.Title := TNestedRoutines.EmbedMethodTitle
    else
      AAction.Title := TNestedRoutines.EmbedRoutineTitle;
    if ARemovePassThrough then
      AAction.Title := AAction.Title + TNestedRoutines.PassThroughSuffix;
    AAction.Kind := RewriteKind;
    AAction.Edits := Edits;
    AAction.Preview := Format('Neue lokale Routine in %s: %s', [Caller.Name,
      HeadText(AText, Tokens, Header, Short, Kept, False)]) + LineBreak + 'Geänderte Aufrufe: 1';
    Result := True;
  finally
    Renamed.Free;
    Collected.Free;
    Cache.Free;
  end;
end;

{ TNestedRoutines }

class function TNestedRoutines.Extract(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
var
  Reason: string;
begin
  Result := ExtractCore(AText, ATree, APosition, ALookup, AStyle, AAction, Reason);
end;

class function TNestedRoutines.Extract(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; out AAction: TCodeAction;
  out AReason: string): Boolean;
begin
  Result := ExtractCore(AText, ATree, APosition, ALookup, AStyle, AAction, AReason);
end;

class function TNestedRoutines.Embed(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; ARemovePassThrough: Boolean;
  out AAction: TCodeAction; out AReason: string): Boolean;
begin
  Result := EmbedCore(AText, ATree, APosition, ALookup, AStyle, ARemovePassThrough, AAction, AReason);
end;

class function TNestedRoutines.Embed(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; ARemovePassThrough: Boolean;
  out AAction: TCodeAction): Boolean;
var
  Reason: string;
begin
  Result := EmbedCore(AText, ATree, APosition, ALookup, AStyle, ARemovePassThrough, AAction, Reason);
end;

class function TNestedRoutines.Actions(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle): TArray<TCodeAction>;
var
  Action: TCodeAction;
begin
  Result := nil;
  if Extract(AText, ATree, APosition, ALookup, AStyle, Action) then
    Result := Result + [Action];
  if Embed(AText, ATree, APosition, ALookup, AStyle, False, Action) then
  begin
    Result := Result + [Action];
    if Embed(AText, ATree, APosition, ALookup, AStyle, True, Action) then
      Result := Result + [Action];
  end;
end;

end.
