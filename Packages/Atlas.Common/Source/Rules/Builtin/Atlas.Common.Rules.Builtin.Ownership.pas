unit Atlas.Common.Rules.Builtin.Ownership;

// Regeln für Besitz von Objekten:
//   owned-item-freed  Element einer besitzenden Liste zusätzlich freigegeben (#947): Liste[I].Free,
//                     FreeAndNil(Liste[I]) oder Element.Free für ein Element aus Liste[I], Liste.First/Last bzw.
//                     "for Element in Liste do", während TObjectList/TObjectList<T> (OwnsObjects, Vorgabe True)
//                     bzw. TObjectDictionary mit doOwnsValues das Element selbst freigibt: bei Delete, Remove,
//                     Clear, einer Zuweisung an Liste[I] oder spätestens beim Freigeben der Liste. Besitzend ist
//                     eine Liste, wenn sie in der Unit so erzeugt wird (TObjectList ohne False, TObjectDictionary
//                     mit doOwnsValues) bzw. ohne Erzeugung als TObjectList deklariert ist, und kein
//                     "OwnsObjects := False" folgt. Extract in derselben Routine lässt die Regel schweigen.
//                     Korrekturen: Free entfernen, Delete bzw. Remove statt Free, Extract statt Remove.
//   create-without-assignment  "TStringList.Create;" als eigene Anweisung (#948): Das Objekt wird erzeugt, aber
//                     nirgends gespeichert und nie freigegeben. Still bleiben Komponenten mit Owner (erstes Argument
//                     Self, Owner, AOwner, Application bzw. ein Nachfahr von TComponent mit Argument ungleich nil),
//                     Threads (geben sich mit FreeOnTerminate selbst frei), unbekannte Klassen mit Argumenten und
//                     Klassen aus "selfRegistering". Korrektur: Zuweisung an eine neue lokale Variable, die
//                     folgenden Anweisungen des Blocks in try/finally mit Free.
//   self-as-interface-in-constructor  Self als Interface weitergegeben, während die Referenzzählung das Objekt
//                     freigeben kann (#950). Nur zwei echte Fehlerfälle: (1) Klassen mit eigener Referenzzählung
//                     (_Release in der Kette gibt das Objekt frei, kein NewInstance-Schutz, Kette bis TObject
//                     bekannt) im Konstruktor oder in AfterConstruction; (2) Nachfahren von TInterfacedObject in
//                     AfterConstruction nach inherited, das den Schutzzähler aus NewInstance schon abgebaut hat.
//                     Im Konstruktor von TInterfacedObject-Nachfahren ist Self geschützt und bleibt still. Als
//                     Weitergabe zählen Self as IX, IX(Self), ein Argument, dessen Parameter in allen bekannten
//                     Überladungen ein Interface ist, und die Zuweisung an eine Interface-Variable. Korrektur in
//                     Fall 2: die Anweisung vor inherited verschieben.
//   raw-memory-leak   lokaler Zeiger aus GetMem, AllocMem, ReallocMem, GetMemory, New, StrAlloc oder StrNew, den
//                     die Routine nie freigibt und der sie nicht verlässt (#1047): Jedes Vorkommen wird im
//                     Syntaxbaum nach oben eingeordnet (Belegung, Freigabe, Zugriff, Weitergabe als Ergebnis,
//                     Zuweisung, @P, Add/Insert…, anonyme Methode, lokale Routine). Lesen und Füllen über ein
//                     Argument ist erlaubt; Routinen mit Free, Frei, Release, Dispose, Destroy oder Dealloc im Namen
//                     gelten als Freigabe. Korrektur: try … finally mit FreeMem, Dispose bzw. StrDispose.
//   stringlist-objects-leak  AddObject/InsertObject mit einem neu erzeugten Objekt (T.Create(…) direkt oder über
//                     eine lokale Variable, die sonst nur gelesen wird) in eine TStringList der Unit ohne
//                     OwnsObjects bzw. in Items einer ListBox oder ComboBox (#1048). Still, wenn eine Routine
//                     Liste.Objects[…] liest und etwas freigibt, die Liste weitergegeben wird oder das Objekt
//                     einen Owner hat. Korrektur: TStringList.Create(True) bzw. OwnsObjects := True.
//   component-interface-dangling  Ein Nachfahr von TComponent (Option componentClasses) wird als Interface in
//                     einem Feld, einer globalen Variablen oder einer Liste gespeichert (#1090): FAnsicht as IFoo als
//                     Argument von Bus.Anmelden, FListe.Add …, die Zuweisung an ein Ziel außerhalb der Routine bzw.
//                     an ein Interface-Feld, Add/Insert in TList<IFoo>/TInterfaceList. TComponent zählt keine
//                     Referenzen; gibt die Datei dasselbe Objekt frei (Free, Release, DisposeOf, FreeAndNil), zeigt
//                     das Interface danach ins Leere. Still bei einer Abmeldung irgendwo in der Datei
//                     (FreeNotification, anderer Aufruf am selben Empfänger mit dem Objekt, Clear, weitere Zuweisung
//                     an dasselbe Ziel), bei Klassen mit eigenem _Release und wenn die Kette der Vorfahren abbricht.
//                     Korrektur: Empfänger.Abmelden(…) bzw. Ziel := nil vor der ersten Freigabe; Abmelden nur, wenn
//                     der Typ des Empfängers das Gegenstück hat. Ebenso gemeldet (ohne Korrektur): Nachfahren von
//                     TInterfacedObject, die so gespeichert und zusätzlich mit Free freigegeben werden.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TOwnedItemFreedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Besitzt eine Liste, die mit ATypeName und den Argumenten AArguments von Create erzeugt wird,
    /// ihre Elemente? AIsDictionary meldet ein TObjectDictionary (besitzt nur mit doOwnsValues).</summary>
    class function CreatesOwning(const ATypeName, AArguments: string; out AIsDictionary: Boolean): Boolean; static;
  end;

  TCreateWithoutAssignmentRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Folgt AName der Namensregel für Typen (TName, EName)?</summary>
    class function LooksLikeType(const AName: string): Boolean; static;
    /// <summary>Name der lokalen Variablen für die Korrektur: TImportProtokoll → ImportProtokoll.</summary>
    class function VariableName(const ATypeName: string): string; static;
  end;

  TSelfAsInterfaceInConstructorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ist ATypeName ein Interface nach der Namensregel (IName, auch Unit.IName, IList&lt;T&gt;)?</summary>
    class function IsInterfaceType(const AType: string): Boolean; static;
  end;

  TRawMemoryLeakRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Passende Freigabe zur Belegung AAllocator (GetMem → FreeMem, New → Dispose, StrAlloc →
    /// StrDispose); '' für eine unbekannte Belegung.</summary>
    class function ReleaseFor(const AAllocator: string): string; static;
  end;

  TStringListObjectsLeakRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vergleichsschlüssel eines Ausdrucks: Kleinschreibung, ohne Leerraum und führendes Self.
    /// </summary>
    class function KeyOf(const AText: string): string; static;
  end;

  TComponentInterfaceDanglingRule = class(TInterfacedObject, IRule)
  public const
    /// <summary>Aufrufe, die ein Interface am Empfänger speichern, und ihr Gegenstück ('' = keins).</summary>
    StoreMethods: array[0..14] of string = ('Add', 'Insert', 'AddOrSetValue', 'Push', 'Enqueue', 'Attach',
      'Subscribe', 'Register', 'RegisterObserver', 'AddObserver', 'AddListener', 'Anmelden', 'Registrieren',
      'Hinzufuegen', 'AddHandler');
    RemoveCounterparts: array[0..14] of string = ('Remove', 'Remove', '', '', '', 'Detach', 'Unsubscribe',
      'Unregister', 'UnregisterObserver', 'RemoveObserver', 'RemoveListener', 'Abmelden', 'Abmelden', 'Entfernen',
      'RemoveHandler');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Gegenstück zum speichernden Aufruf AMethod (Anmelden → Abmelden); '' ohne.</summary>
    class function Counterpart(const AMethod: string): string; static;
  end;

procedure RegisterOwnershipRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.Inheritance;

const
  OwnedItemFreedRuleId = 'owned-item-freed';
  CreateWithoutAssignmentRuleId = 'create-without-assignment';
  SelfAsInterfaceInConstructorRuleId = 'self-as-interface-in-constructor';
  RawMemoryLeakRuleId = 'raw-memory-leak';
  StringListObjectsLeakRuleId = 'stringlist-objects-leak';
  ComponentInterfaceDanglingRuleId = 'component-interface-dangling';
  RemoveMethods: array[0..4] of string = ('Delete', 'Remove', 'RemoveItem', 'Clear', 'DeleteRange');
  ExtractMethods: array[0..3] of string = ('Extract', 'ExtractAt', 'ExtractItem', 'ExtractPair');

type
  /// <summary>Eine besitzende Liste der Unit.</summary>
  TOwningList = record
    Name: string;
    IsDictionary: Boolean;
  end;

  /// <summary>Art einer erzeugten Klasse für create-without-assignment.</summary>
{$SCOPEDENUMS ON}
  TCreatedKind = (Unknown, Plain, Component, Thread);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Freigabe eines Listenelements in einer Routine.</summary>
  TItemFree = record
    List: TOwningList;
    /// <summary>Code-Position des ersten und letzten Tokens des freigegebenen Ausdrucks.</summary>
    First, Last: Integer;
    /// <summary>Indexausdruck bei Liste[Index].Free, sonst leer.</summary>
    IndexText: string;
    /// <summary>Name der Elementvariablen bei Element.Free, sonst leer.</summary>
    Alias: string;
  end;

/// <summary>Setzt die Anweisung AStatement (eine Zeile, allein in ihrer Zeile, mit APrefix davor) vor ein
/// try, rückt die folgenden Anweisungen ihres Blocks ein und gibt im finally mit AFree frei (#948, #1047).
/// False, wenn der Block sich so nicht umschließen lässt.</summary>
function WrapFollowingInTryFinally(const ALines: TArray<string>; const ALineBreak: string; AStatement: TSyntaxNode;
  const APrefix, AFree: string; const AStyle: TFormatStyle; out AEdit: TTextEdit): Boolean;
var
  Parent, LastSibling: TSyntaxNode;
  Index, Line, LastLine: Integer;
  Indent, UnitIndent, Rest, NewText: string;
begin
  Result := False;
  Parent := AStatement.Parent;
  if (Parent = nil) or not (Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock,
    TSyntaxKind.ExceptBlock]) or (AStatement.StartPos.Line <> AStatement.EndPos.Line) or
    (AStatement.EndPos.Line > High(ALines)) or
    (Trim(Copy(ALines[AStatement.StartPos.Line], 1, AStatement.StartPos.Character)) <> '') then
    Exit;
  Rest := Trim(Copy(ALines[AStatement.EndPos.Line], AStatement.EndPos.Character + 1, MaxInt));
  if (Rest <> '') and (Rest <> ';') then
    Exit;
  // Letzte folgende Anweisung desselben Blocks; sie muss ihre Zeile allein beenden.
  LastSibling := AStatement;
  for Index := 0 to Parent.ChildCount - 1 do
    if Parent[Index].StartOffset > AStatement.StartOffset then
      LastSibling := Parent[Index];
  LastLine := LastSibling.EndPos.Line;
  if LastLine > High(ALines) then
    Exit;
  Rest := Trim(Copy(ALines[LastLine], LastSibling.EndPos.Character + 1, MaxInt));
  if (Rest <> '') and (Rest <> ';') then
    Exit;
  Indent := Copy(ALines[AStatement.StartPos.Line], 1, AStatement.StartPos.Character);
  UnitIndent := TRoutineBody.IndentUnit(AStyle);
  NewText := Indent + APrefix + TrimLeft(ALines[AStatement.StartPos.Line]) + ALineBreak + Indent + 'try' +
    ALineBreak;
  for Line := AStatement.StartPos.Line + 1 to LastLine do
    if Trim(ALines[Line]) = '' then
      NewText := NewText + ALineBreak
    else
      NewText := NewText + UnitIndent + ALines[Line] + ALineBreak;
  NewText := NewText + Indent + 'finally' + ALineBreak + Indent + UnitIndent + AFree + ALineBreak + Indent +
    'end;' + ALineBreak;
  AEdit := TTextEdit.Create(TTextRange.Create(AStatement.StartPos.Line, 0, LastLine + 1, 0), NewText);
  Result := True;
end;

{ TOwnedItemFreedRule }

function TOwnedItemFreedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OwnedItemFreedRuleId, TRuleSeverity.Error,
    'Element einer besitzenden Liste zusätzlich freigegeben');
end;

class function TOwnedItemFreedRule.CreatesOwning(const ATypeName, AArguments: string;
  out AIsDictionary: Boolean): Boolean;
begin
  AIsDictionary := ContainsText(ATypeName, 'TObjectDictionary');
  if AIsDictionary then
    Result := ContainsText(AArguments, 'doOwnsValues')
  else
    Result := not TRegEx.IsMatch(AArguments, '\bFalse\b', [roIgnoreCase]);
end;

procedure TOwnedItemFreedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Lines: TArray<string>;
  LineBreak: string;
  Lists: TArray<TOwningList>;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsWord(APosition: Integer): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier);
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := IsWord(APosition) and SameText(Token(APosition).Text, AName);
  end;

  // Passende schließende Klammer zu AOpen ("(" oder "["), sonst -1.
  function Closing(AOpen: Integer): Integer;
  var
    Depth: Integer;
  begin
    Depth := 0;
    for Result := AOpen to High(Code) do
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
        Inc(Depth)
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Dec(Depth);
        if Depth = 0 then
          Exit;
      end;
    Result := -1;
  end;

  function TextBetween(AFirst, ALast: Integer): string;
  begin
    Result := Copy(AContext.Text, Token(AFirst).Offset + 1,
      Token(ALast).Offset + Length(Token(ALast).Text) - Token(AFirst).Offset);
  end;

  function NodeAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    Index: Integer;
    Next: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): je Ebene in das erste Kind, das AOffset enthält.
    Result := ANode;
    repeat
      Next := nil;
      for Index := 0 to Result.ChildCount - 1 do
        if (AOffset >= Result[Index].StartOffset) and (AOffset < Result[Index].EndOffset) then
        begin
          Next := Result[Index];
          Break;
        end;
      if Next <> nil then
        Result := Next;
    until Next = nil;
  end;

  procedure AddList(const AName: string; AIsDictionary: Boolean);
  var
    Item: TOwningList;
  begin
    for Item in Lists do
      if SameText(Item.Name, AName) then
        Exit;
    Item.Name := AName;
    Item.IsDictionary := AIsDictionary;
    Lists := Lists + [Item];
  end;

  // Position des Typnamens nach "Unit.Unit." ab APosition.
  function SkipUnitPrefix(APosition: Integer): Integer;
  begin
    Result := APosition;
    while IsWord(Result) and IsSym(Result + 1, '.') and IsWord(Result + 2) and
      not SameText(Token(Result).Text, 'TObjectList') and not SameText(Token(Result).Text, 'TObjectDictionary') do
      Inc(Result, 2);
  end;

  // Position nach den generischen Argumenten "<…>" ab APosition.
  function SkipGenericArgs(APosition: Integer): Integer;
  var
    Depth: Integer;
  begin
    Result := APosition;
    if not IsSym(Result, '<') then
      Exit;
    Depth := 0;
    while Result <= High(Code) do
    begin
      if Token(Result).IsSymbol('<') then
        Inc(Depth)
      else if Token(Result).IsSymbol('>') then
        Dec(Depth)
      else if Token(Result).IsSymbol('>>') then
        Dec(Depth, 2)
      else if Token(Result).IsSymbol(';') then
        Exit;
      Inc(Result);
      if Depth <= 0 then
        Exit;
    end;
  end;

  // Besitzende Listen der Unit: Erzeugungen, sonst Deklarationen als TObjectList; ohne OwnsObjects := False.
  procedure CollectLists;
  var
    Position, TypePosition, After, Close, Names: Integer;
    Arguments: string;
    Owning, IsDictionary: Boolean;
    Created, NotOwning, Declared: TArray<string>;
    Index: Integer;
  begin
    Lists := nil;
    Created := nil;
    NotOwning := nil;
    Declared := nil;
    for Position := 0 to High(Code) - 2 do
    begin
      if not IsWord(Position) then
        Continue;
      // Name := TObjectList<T>.Create(…);
      if IsSym(Position + 1, ':=') then
      begin
        TypePosition := SkipUnitPrefix(Position + 2);
        if not IsName(TypePosition, 'TObjectList') and not IsName(TypePosition, 'TObjectDictionary') then
          Continue;
        After := SkipGenericArgs(TypePosition + 1);
        if not IsSym(After, '.') or not IsName(After + 1, 'Create') then
          Continue;
        Arguments := '';
        if IsSym(After + 2, '(') then
        begin
          Close := Closing(After + 2);
          if Close > After + 3 then
            Arguments := TextBetween(After + 3, Close - 1);
        end;
        Created := Created + [Token(Position).Text];
        Owning := CreatesOwning(Token(TypePosition).Text, Arguments, IsDictionary);
        if Owning then
          AddList(Token(Position).Text, IsDictionary)
        else
          NotOwning := NotOwning + [Token(Position).Text];
        Continue;
      end;
      // Name.OwnsObjects := False;
      if IsSym(Position + 1, '.') and IsName(Position + 2, 'OwnsObjects') and IsSym(Position + 3, ':=') and
        IsName(Position + 4, 'False') then
      begin
        NotOwning := NotOwning + [Token(Position).Text];
        Continue;
      end;
      // A, B: TObjectList;
      if IsSym(Position + 1, ':') and IsName(SkipUnitPrefix(Position + 2), 'TObjectList') then
      begin
        Names := Position;
        while IsWord(Names) do
        begin
          Declared := Declared + [Token(Names).Text];
          if not IsSym(Names - 1, ',') then
            Break;
          Dec(Names, 2);
        end;
      end;
    end;
    for Index := 0 to High(Declared) do
      if IndexText(Declared[Index], Created) < 0 then
        AddList(Declared[Index], False);
    for Index := High(Lists) downto 0 do
      if IndexText(Lists[Index].Name, NotOwning) >= 0 then
        Delete(Lists, Index, 1);
  end;

  function ListAt(APosition: Integer; out AList: TOwningList): Boolean;
  var
    Item: TOwningList;
  begin
    Result := False;
    if not IsWord(APosition) then
      Exit;
    // Nur der Name selbst oder Self.Name, keine fremden Objekte.
    if IsSym(APosition - 1, '.') and not IsName(APosition - 2, 'Self') then
      Exit;
    for Item in Lists do
      if SameText(Item.Name, Token(APosition).Text) then
      begin
        AList := Item;
        Exit(True);
      end;
  end;

  // Liste[Index] bzw. Liste.Items[Index] ab APosition; liefert die Position nach "]" und den Indextext.
  function ElementAccess(APosition: Integer; out AAfter: Integer; out AIndex: string): Boolean;
  var
    Open, Close: Integer;
  begin
    Result := False;
    Open := APosition + 1;
    if IsSym(Open, '.') and IsName(Open + 1, 'Items') then
      Inc(Open, 2);
    if not IsSym(Open, '[') then
      Exit;
    Close := Closing(Open);
    if Close < 0 then
      Exit;
    AIndex := Trim(TextBetween(Open + 1, Close - 1));
    AAfter := Close + 1;
    Result := True;
  end;

  // Steht bei APosition eine Freigabe "X.Free", "X.Destroy", "X.DisposeOf" (AExprLast = letztes Token von X)?
  function FreeAfter(AExprLast: Integer): Boolean;
  begin
    Result := IsSym(AExprLast + 1, '.') and (IsName(AExprLast + 2, 'Free') or IsName(AExprLast + 2, 'Destroy') or
      IsName(AExprLast + 2, 'DisposeOf'));
  end;

  // Elementvariablen der Routine: V := L[I], V := L.Items[I], L.First/Last, for V in L / L.Values.
  function AliasList(ABlock: TSyntaxNode; AFreePosition: Integer; const AName: string;
    out AList: TOwningList): Boolean;
  var
    Position, After: Integer;
    Index: string;
    Node: TSyntaxNode;
  begin
    Result := False;
    for Position := 0 to AFreePosition - 1 do
    begin
      if (Token(Position).Offset < ABlock.StartOffset) or not IsName(Position, AName) then
        Continue;
      // V := Liste[I]; V := Liste.Items[I]; V := Liste.First
      if IsSym(Position + 1, ':=') and ListAt(Position + 2, AList) then
      begin
        if ElementAccess(Position + 2, After, Index) and IsSym(After, ';') then
          Result := True
        else if IsSym(Position + 3, '.') and (IsName(Position + 4, 'First') or IsName(Position + 4, 'Last')) and
          IsSym(Position + 5, ';') then
          Result := True;
        Continue;
      end;
      // for V in Liste do / for V in Dictionary.Values do: nur, wenn die Freigabe in der Schleife steht.
      if (Position > 1) and (Token(Position - 1).IsKeyword('for') or (Token(Position - 1).IsKeyword('var') and
        Token(Position - 2).IsKeyword('for'))) and Token(Position + 1).IsKeyword('in') and
        ListAt(Position + 2, AList) and ((Token(Position + 3).IsKeyword('do') and not AList.IsDictionary) or
        (IsSym(Position + 3, '.') and IsName(Position + 4, 'Values') and AList.IsDictionary)) then
      begin
        Node := NodeAt(AContext.Tree.Root, Token(Position).Offset);
        while (Node <> nil) and (Node.Kind <> TSyntaxKind.ForInStatement) do
          Node := Node.Parent;
        if (Node <> nil) and (Token(AFreePosition).Offset < Node.EndOffset) then
          Result := True;
      end;
    end;
  end;

  // Anweisung (CallStatement) um APosition, wenn sie allein in ihren Zeilen in einem Block steht. Ist sie der
  // einzige Rumpf einer for-in-Schleife, die ganze Schleife.
  function OwnStatement(APosition: Integer; out ANode: TSyntaxNode): Boolean;
  var
    Node: TSyntaxNode;
  begin
    Result := False;
    Node := NodeAt(AContext.Tree.Root, Token(APosition).Offset);
    while (Node <> nil) and (Node.Kind <> TSyntaxKind.CallStatement) do
      Node := Node.Parent;
    if (Node = nil) or (Node.Parent = nil) then
      Exit;
    if (Node.Parent.Kind = TSyntaxKind.ForInStatement) and (Node.Parent[Node.Parent.ChildCount - 1] = Node) then
      Node := Node.Parent;
    if (Node.Parent = nil) or not (Node.Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement,
      TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement]) then
      Exit;
    if (Node.StartPos.Line > High(Lines)) or (Node.EndPos.Line > High(Lines)) or
      (Trim(Copy(Lines[Node.StartPos.Line], 1, Node.StartPos.Character)) <> '') or
      ((Trim(Copy(Lines[Node.EndPos.Line], Node.EndPos.Character + 1, MaxInt)) <> '') and
      (Trim(Copy(Lines[Node.EndPos.Line], Node.EndPos.Character + 1, MaxInt)) <> ';')) then
      Exit;
    ANode := Node;
    Result := True;
  end;

  function RemoveFreeFix(APosition: Integer; out AFix: TRuleFix): Boolean;
  var
    Node: TSyntaxNode;
  begin
    Result := OwnStatement(APosition, Node);
    if Result then
      AFix := TRuleFix.Create('Free entfernen',
        [TTextEdit.Create(TTextRange.Create(Node.StartPos.Line, 0, Node.EndPos.Line + 1, 0), '')]);
  end;

  // Liste[I].Free → Liste.Delete(I) bzw. Dictionary.Remove(Key).
  function DeleteFix(const AFree: TItemFree; out AFix: TRuleFix): Boolean;
  var
    Node: TSyntaxNode;
    Method, Prefix: string;
  begin
    Result := (AFree.IndexText <> '') and OwnStatement(AFree.First, Node) and (Node.Kind = TSyntaxKind.CallStatement);
    if not Result then
      Exit;
    Method := 'Delete';
    if AFree.List.IsDictionary then
      Method := 'Remove';
    // "Self.Liste[I].Free": Self. bleibt stehen.
    Prefix := '';
    if IsSym(AFree.First - 1, '.') then
      Prefix := 'Self.';
    AFix := TRuleFix.Create(Format('%s statt Free', [Method]),
      [TTextEdit.Create(TTextRange.Create(Node.StartPos, Node.EndPos),
      Format('%s%s.%s(%s)', [Prefix, Token(AFree.First).Text, Method, AFree.IndexText]))]);
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    Block: TSyntaxNode;
    Position, After, Start, Last, RemovePosition: Integer;
    Frees: TArray<TItemFree>;
    Item: TItemFree;
    List: TOwningList;
    Index, Removal, Message, Owns: string;
    Extracted: Boolean;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    Block := ARoutine.FindChild(TSyntaxKind.Block);
    if Block = nil then
      Exit;
    // Freigaben sammeln.
    Frees := nil;
    for Position := 0 to High(Code) do
    begin
      if (Token(Position).Offset < Block.StartOffset) or (Token(Position).Offset >= Block.EndOffset) then
        Continue;
      Item := Default(TItemFree);
      // FreeAndNil(Liste[I]) bzw. FreeAndNil(V)
      if IsName(Position, 'FreeAndNil') and IsSym(Position + 1, '(') then
      begin
        Start := Position + 2;
        if IsName(Start, 'Self') and IsSym(Start + 1, '.') then
          Inc(Start, 2);
        if ListAt(Start, List) and ElementAccess(Start, After, Index) and IsSym(After, ')') then
        begin
          Item.List := List;
          Item.First := Start;
          Item.Last := After;
          Item.IndexText := Index;
          Frees := Frees + [Item];
        end
        else if IsWord(Start) and IsSym(Start + 1, ')') and AliasList(Block, Position, Token(Start).Text, List) then
        begin
          Item.List := List;
          Item.First := Position;
          Item.Last := Start + 1;
          Item.Alias := Token(Start).Text;
          Frees := Frees + [Item];
        end;
        Continue;
      end;
      // Liste[I].Free
      if ListAt(Position, List) and ElementAccess(Position, After, Index) and FreeAfter(After - 1) then
      begin
        Item.List := List;
        Item.First := Position;
        Item.Last := After + 1;
        Item.IndexText := Index;
        Frees := Frees + [Item];
        Continue;
      end;
      // V.Free
      if IsWord(Position) and not IsSym(Position - 1, '.') and FreeAfter(Position) and
        AliasList(Block, Position, Token(Position).Text, List) then
      begin
        Item.List := List;
        Item.First := Position;
        Item.Last := Position + 2;
        Item.Alias := Token(Position).Text;
        Frees := Frees + [Item];
      end;
    end;
    for Item in Frees do
    begin
      // Entfernen bzw. Extract derselben Liste in der Routine.
      Removal := '';
      RemovePosition := -1;
      Extracted := False;
      for Position := 0 to High(Code) - 2 do
      begin
        if (Token(Position).Offset < Block.StartOffset) or (Token(Position).Offset >= Block.EndOffset) or
          not ListAt(Position, List) or not SameText(List.Name, Item.List.Name) then
          Continue;
        if IsSym(Position + 1, '.') and (IndexText(Token(Position + 2).Text, ExtractMethods) >= 0) then
          Extracted := True
        else if (Removal = '') and IsSym(Position + 1, '.') and
          (IndexText(Token(Position + 2).Text, RemoveMethods) >= 0) then
        begin
          Removal := Token(Position + 2).Text;
          RemovePosition := Position + 2;
        end
        else if (Removal = '') and ElementAccess(Position, After, Index) and IsSym(After, ':=') then
          Removal := 'die Zuweisung an ' + Token(Position).Text + '[…]';
      end;
      if Extracted then
        Continue;
      Owns := 'seine Elemente (OwnsObjects)';
      if Item.List.IsDictionary then
        Owns := 'seine Werte (doOwnsValues)';
      Fixes := nil;
      if Removal <> '' then
      begin
        Message := Format('%s besitzt %s; %s gibt das Element ein zweites Mal frei.', [Item.List.Name, Owns,
          Removal]);
        if RemoveFreeFix(Item.First, Fix) then
          Fixes := Fixes + [Fix];
        // Remove(V) vor V.Free: Extract nimmt das Element heraus, ohne es freizugeben.
        if (RemovePosition >= 0) and SameText(Token(RemovePosition).Text, 'Remove') and (Item.Alias <> '') then
        begin
          if Item.List.IsDictionary then
            Fix := TRuleFix.Create('ExtractPair statt Remove', [TTextEdit.Create(TTextRange.Create(
              Token(RemovePosition).StartPos, Token(RemovePosition).EndPos), 'ExtractPair')])
          else
            Fix := TRuleFix.Create('Extract statt Remove', [TTextEdit.Create(TTextRange.Create(
              Token(RemovePosition).StartPos, Token(RemovePosition).EndPos), 'Extract')]);
          Fix.Alternative := Fixes <> nil;
          Fixes := Fixes + [Fix];
        end;
      end
      else
      begin
        Message := Format('%s besitzt %s; die Liste gibt das Element beim Freigeben ein zweites Mal frei.',
          [Item.List.Name, Owns]);
        if DeleteFix(Item, Fix) then
          Fixes := Fixes + [Fix]
        else if (Item.Alias <> '') and RemoveFreeFix(Item.First, Fix) then
          Fixes := Fixes + [Fix];
      end;
      Last := Item.Last;
      AReport.Add(TTextRange.Create(Token(Item.First).StartPos, Token(Last).EndPos), Message, Fixes);
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          CheckRoutine(Node);
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Index: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  if not ContainsText(AContext.Text, 'TObjectList') and not ContainsText(AContext.Text, 'TObjectDictionary') then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      Code := Code + [Index];
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  CollectLists;
  if Lists = nil then
    Exit;
  Visit(AContext.Tree.Root);
end;

{ TCreateWithoutAssignmentRule }

function TCreateWithoutAssignmentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(CreateWithoutAssignmentRuleId, TRuleSeverity.Warning,
    'Objekt erzeugt und sofort verloren');
end;

class function TCreateWithoutAssignmentRule.LooksLikeType(const AName: string): Boolean;
begin
  Result := (Length(AName) >= 2) and CharInSet(AName[1], ['T', 'E']) and CharInSet(AName[2], ['A'..'Z']);
end;

class function TCreateWithoutAssignmentRule.VariableName(const ATypeName: string): string;
begin
  Result := ATypeName;
  if Pos('<', Result) > 0 then
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  if LooksLikeType(Result) then
    Result := Copy(Result, 2, MaxInt);
  if Result = '' then
    Result := 'Objekt';
end;

procedure TCreateWithoutAssignmentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Lines: TArray<string>;
  LineBreak: string;
  SelfRegistering: TArray<string>;
  Ancestry: TAncestry;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsWord(APosition: Integer): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier);
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function CodeAt(AOffset: Integer): Integer;
  begin
    for Result := 0 to High(Code) do
      if Token(Result).Offset >= AOffset then
        Exit;
    Result := Length(Code);
  end;

  function Closing(AOpen: Integer): Integer;
  var
    Depth: Integer;
  begin
    Depth := 0;
    for Result := AOpen to High(Code) do
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
        Inc(Depth)
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Dec(Depth);
        if Depth = 0 then
          Exit;
      end;
    Result := -1;
  end;

  function SkipGenericArgs(APosition: Integer): Integer;
  var
    Depth: Integer;
  begin
    Result := APosition;
    if not IsSym(Result, '<') then
      Exit;
    Depth := 0;
    while Result <= High(Code) do
    begin
      if Token(Result).IsSymbol('<') then
        Inc(Depth)
      else if Token(Result).IsSymbol('>') then
        Dec(Depth)
      else if Token(Result).IsSymbol('>>') then
        Dec(Depth, 2)
      else if Token(Result).IsSymbol(';') then
        Exit;
      Inc(Result);
      if Depth <= 0 then
        Exit;
    end;
  end;

  function TextBetween(AFirst, ALast: Integer): string;
  begin
    Result := Copy(AContext.Text, Token(AFirst).Offset + 1,
      Token(ALast).Offset + Length(Token(ALast).Text) - Token(AFirst).Offset);
  end;

  function IsSelfRegistering(const AClassName: string): Boolean;
  var
    Pattern: string;
  begin
    for Pattern in SelfRegistering do
      if MatchesGlob(Pattern, AClassName) then
        Exit(True);
    Result := False;
  end;

  // Art der Klasse über die Vorfahren in Datei und Index; Unknown, wenn die Kette vor TObject abbricht.
  function KindOf(const AClassName: string): TCreatedKind;
  var
    Name: string;
    Depth: Integer;
    Body: TSyntaxNode;
  begin
    // Records (TPoint.Create(1, 2)) belegen keinen Heap.
    Body := TRoutineBody.TypeBody(AContext.Tree.Root, AClassName);
    if (Body <> nil) and (Body.Kind = TSyntaxKind.RecordType) then
      Exit(TCreatedKind.Unknown);
    Name := AClassName;
    for Depth := 0 to 63 do
    begin
      if SameText(Name, 'TComponent') then
        Exit(TCreatedKind.Component);
      if SameText(Name, 'TThread') then
        Exit(TCreatedKind.Thread);
      if SameText(Name, 'TObject') then
        Exit(TCreatedKind.Plain);
      Name := Ancestry.ParentOf(Name);
      if Name = '' then
        Break;
    end;
    Result := TCreatedKind.Unknown;
  end;

  // "Name := T.Create(…);" mit try/finally um die folgenden Anweisungen des Blocks.
  function AssignFix(ARoutine, AStatement: TSyntaxNode; const ATypeText: string; out AFix: TRuleFix): Boolean;
  var
    Name: string;
    Edit: TTextEdit;
  begin
    Name := TRoutineBody.UniqueName(Tokens, VariableName(ATypeText));
    Result := WrapFollowingInTryFinally(Lines, LineBreak, AStatement, Name + ' := ', Name + '.Free;',
      AContext.Formatting, Edit);
    if Result then
      AFix := TRuleFix.Create(Format('An %s zuweisen und in try/finally freigeben', [Name]),
        [TRoutineBody.AddVariable(AContext.Text, ARoutine, Name, ATypeText, AContext.Formatting), Edit]);
  end;

  procedure CheckStatement(ARoutine, AStatement: TSyntaxNode);
  var
    Position, ClassPosition, After, Close, Next: Integer;
    ClassName, TypeText, FirstArgument: string;
    HasArguments: Boolean;
    Kind: TCreatedKind;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    Position := CodeAt(AStatement.StartOffset);
    if not IsWord(Position) then
      Exit;
    // Unit.TKlasse<T>.Create(…)
    ClassPosition := Position;
    After := SkipGenericArgs(Position + 1);
    while IsSym(After, '.') and IsWord(After + 1) and not SameText(Token(After + 1).Text, 'Create') do
    begin
      ClassPosition := After + 1;
      After := SkipGenericArgs(After + 2);
    end;
    if not IsSym(After, '.') or not IsWord(After + 1) or not SameText(Token(After + 1).Text, 'Create') then
      Exit;
    Next := After + 2;
    HasArguments := False;
    FirstArgument := '';
    if IsSym(Next, '(') then
    begin
      Close := Closing(Next);
      if Close < 0 then
        Exit;
      HasArguments := Close > Next + 1;
      if HasArguments and (IsWord(Next + 1) or Token(Next + 1).IsKeyword('nil')) and
        (IsSym(Next + 2, ',') or IsSym(Next + 2, ')')) then
        FirstArgument := Token(Next + 1).Text;
      Next := Close + 1;
    end;
    // Die Anweisung endet mit Create(…): nichts wird weitergegeben oder gespeichert.
    if (Next <= High(Code)) and (Token(Next).Offset < AStatement.EndOffset) then
      Exit;
    ClassName := Token(ClassPosition).Text;
    Kind := KindOf(ClassName);
    if (not LooksLikeType(ClassName) and (Kind = TCreatedKind.Unknown)) or IsSelfRegistering(ClassName) or
      (Kind = TCreatedKind.Thread) then
      Exit;
    // Komponenten mit Owner gibt der Owner frei; unbekannte Klassen mit Argumenten tragen sich oft selbst ein.
    // Gemeldet werden mit Argumenten nur bekannte Klassen ohne TComponent und Aufrufe mit nil als Owner.
    if HasArguments and not SameText(FirstArgument, 'nil') and
      ((Kind <> TCreatedKind.Plain) or MatchText(FirstArgument, ['Self', 'Owner', 'AOwner', 'Application'])) then
      Exit;
    TypeText := TextBetween(Position, After - 1);
    Fixes := nil;
    if AssignFix(ARoutine, AStatement, TypeText, Fix) then
      Fixes := [Fix];
    AReport.Add(TTextRange.Create(Token(Position).StartPos, Token(Next - 1).EndPos),
      Format('Das erzeugte %s wird nirgends gespeichert und nie freigegeben (Speicherleck).', [TypeText]), Fixes);
  end;

  procedure VisitStatements(ARoutine, ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.CallStatement then
          CheckStatement(ARoutine, Node);
        // Lokale Routinen prüft Visit für sich.
        if (Node <> ARoutine) and (Node.Kind = TSyntaxKind.RoutineDecl) then
          Continue;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
          VisitStatements(Node, Node);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Index: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Create') then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      Code := Code + [Index];
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  SelfRegistering := TRuleOptions.Strings(AContext.Options, 'selfRegistering', nil);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  try
    Visit(AContext.Tree.Root);
  finally
    Ancestry.Free;
  end;
end;

{ TSelfAsInterfaceInConstructorRule }

function TSelfAsInterfaceInConstructorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(SelfAsInterfaceInConstructorRuleId, TRuleSeverity.Warning,
    'Self als Interface im Konstruktor weitergegeben');
end;

class function TSelfAsInterfaceInConstructorRule.IsInterfaceType(const AType: string): Boolean;
var
  Name: string;
begin
  Name := Trim(AType);
  if Pos('<', Name) > 0 then
    Name := Copy(Name, 1, Pos('<', Name) - 1);
  Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  Result := (Length(Name) >= 2) and (Name[1] = 'I') and CharInSet(Name[2], ['A'..'Z']);
end;

procedure TSelfAsInterfaceInConstructorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Lines: TArray<string>;
  LineBreak: string;
  Ancestry: TAncestry;
  Types: TDeclaredTypes;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsWord(APosition: Integer): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := IsWord(APosition) and SameText(Token(APosition).Text, AName);
  end;

  function IsKey(APosition: Integer; const AKeyword: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsKeyword(AKeyword);
  end;

  function CodeAt(AOffset: Integer): Integer;
  begin
    for Result := 0 to High(Code) do
      if Token(Result).Offset >= AOffset then
        Exit;
    Result := Length(Code);
  end;

  // Symbole der Datei und des Index mit dem Namen AName.
  function SymbolsNamed(const AName: string): TArray<TIndexSymbol>;
  var
    Symbol: TIndexSymbol;
    Location: TSymbolLocation;
  begin
    Result := nil;
    for Symbol in Ancestry.Local.Symbols do
      if SameText(Symbol.Name, AName) then
        Result := Result + [Symbol];
    if AContext.Index <> nil then
      for Location in AContext.Index.FindSymbols(AName) do
        Result := Result + [Location.Symbol];
  end;

  // Methode AMethod (z. B. _Release) als Rumpf in der Datei: 'TKlasse._Release'.
  function MethodBody(const AClassName, AMethod: string): TSyntaxNode;
  var
    Found: TSyntaxNode;
  begin
    Found := nil;
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (Found = nil) and (ANode.Kind = TSyntaxKind.RoutineDecl) and
          SameText(ANode.Name, AClassName + '.' + AMethod) and (TRoutineBody.BodyOf(ANode) <> nil) then
          Found := ANode;
        Result := Found = nil;
      end);
    Result := Found;
  end;

  function Declares(const AClassName, AMethod: string): Boolean;
  var
    Symbol: TIndexSymbol;
  begin
    for Symbol in Ancestry.Local.Symbols do
      if SameText(Symbol.Container, AClassName) and SameText(Symbol.Name, AMethod) and
        (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) then
        Exit(True);
    Result := False;
  end;

  // Gibt _Release der Klasse das Objekt selbst frei (Destroy oder Free im Rumpf)?
  function ReleaseFrees(const AClassName: string): Boolean;
  var
    Routine: TSyntaxNode;
    Position: Integer;
  begin
    Routine := MethodBody(AClassName, '_Release');
    if Routine = nil then
      Exit(False);
    for Position := CodeAt(Routine.StartOffset) to High(Code) do
    begin
      if Token(Position).Offset >= Routine.EndOffset then
        Break;
      if IsName(Position, 'Destroy') or IsName(Position, 'Free') or IsName(Position, 'FreeInstance') then
        Exit(True);
    end;
    Result := False;
  end;

  // Eigene Referenzzählung ohne Schutz in NewInstance: Eine Klasse der Kette gibt sich in _Release frei,
  // keine überschreibt NewInstance, die Kette reicht bis TObject.
  function OwnCounting(const AClassName: string): Boolean;
  var
    Current: string;
    Steps: Integer;
  begin
    Result := False;
    Current := AClassName;
    for Steps := 1 to 32 do
    begin
      if SameText(Current, 'TObject') then
        Exit;
      if (Current = '') or SameText(Current, 'TInterfacedObject') or Declares(Current, 'NewInstance') then
      begin
        Result := False;
        Exit;
      end;
      if Declares(Current, '_Release') and ReleaseFrees(Current) then
        Result := True;
      Current := Ancestry.ParentOf(Current);
    end;
    Result := False;
  end;

  // Parametertyp an Stelle AIndex aller Routinen namens AName: True, wenn alle bekannten ein Interface
  // erwarten (Überladungen mit TObject an der Stelle machen den Fall unsicher).
  function ExpectsInterface(const AName: string; AIndex: Integer): Boolean;
  var
    Symbol: TIndexSymbol;
    Known: Boolean;
  begin
    Known := False;
    for Symbol in SymbolsNamed(AName) do
    begin
      if not (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine]) or
        (Length(Symbol.ParamTypes) <= AIndex) then
        Continue;
      if not IsInterfaceType(Symbol.ParamTypes[AIndex]) then
        Exit(False);
      Known := True;
    end;
    Result := Known;
  end;

  // Typ einer Variablen oder eines Feldes vor ":= Self".
  function TargetIsInterface(APosition: Integer): Boolean;
  var
    Target: Integer;
    Symbol: TIndexSymbol;
    TypeName: string;
  begin
    Target := APosition - 2;
    if not IsWord(Target) or (IsSym(Target - 1, '.') and not IsName(Target - 2, 'Self')) then
      Exit(False);
    TypeName := Types.DeclaredType(Token(Target).Text, Token(Target).StartPos);
    if TypeName = '' then
      for Symbol in Ancestry.Local.Symbols do
        if (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Variable]) and
          SameText(Symbol.Name, Token(Target).Text) then
          TypeName := Symbol.TypeName;
    Result := IsInterfaceType(TypeName);
  end;

  // Wird Self an APosition als Interface weitergegeben? Self as IX, IX(Self), Aufruf mit Interface-Parameter
  // oder Zuweisung an eine Interface-Variable.
  function PassesAsInterface(APosition: Integer): Boolean;
  var
    Position, Depth, Argument: Integer;
  begin
    Result := False;
    if IsSym(APosition - 1, '.') or IsSym(APosition + 1, '.') then
      Exit;
    if IsKey(APosition + 1, 'as') and IsWord(APosition + 2) and IsInterfaceType(Token(APosition + 2).Text) then
      Exit(True);
    if IsSym(APosition - 1, '(') and IsSym(APosition + 1, ')') and IsWord(APosition - 2) and
      IsInterfaceType(Token(APosition - 2).Text) then
      Exit(True);
    if IsSym(APosition - 1, ':=') and (IsSym(APosition + 1, ';') or IsKey(APosition + 1, 'end') or
      IsKey(APosition + 1, 'else')) then
      Exit(TargetIsInterface(APosition));
    if not (IsSym(APosition - 1, '(') or IsSym(APosition - 1, ',')) or
      not (IsSym(APosition + 1, ')') or IsSym(APosition + 1, ',')) then
      Exit;
    // Öffnende Klammer des Aufrufs und Stelle des Arguments.
    Depth := 0;
    Argument := 0;
    Position := APosition - 1;
    while Position >= 0 do
    begin
      if Token(Position).IsSymbol(')') or Token(Position).IsSymbol(']') then
        Inc(Depth)
      else if Token(Position).IsSymbol('[') then
      begin
        if Depth = 0 then
          Exit;
        Dec(Depth);
      end
      else if Token(Position).IsSymbol('(') then
      begin
        if Depth = 0 then
          Break;
        Dec(Depth);
      end
      else if (Depth = 0) and Token(Position).IsSymbol(',') then
        Inc(Argument)
      else if (Depth = 0) and Token(Position).IsSymbol(';') then
        Exit;
      Dec(Position);
    end;
    if (Position < 1) or not IsWord(Position - 1) then
      Exit;
    Result := ExpectsInterface(Token(Position - 1).Text, Argument);
  end;

  // Anweisung direkt im Rumpf ABlock, die AOffset enthält; nil sonst.
  function TopStatement(ABlock: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    Index: Integer;
  begin
    for Index := 0 to ABlock.ChildCount - 1 do
      if (AOffset >= ABlock[Index].StartOffset) and (AOffset < ABlock[Index].EndOffset) then
        Exit(ABlock[Index]);
    Result := nil;
  end;

  // Steht die Anweisung allein auf ihren Zeilen (davor nur Einrückung, danach nur ";")?
  function OwnLines(AStatement: TSyntaxNode): Boolean;
  var
    Rest: string;
  begin
    Rest := Trim(Copy(Lines[AStatement.EndPos.Line], AStatement.EndPos.Character + 1, MaxInt));
    Result := (Trim(Copy(Lines[AStatement.StartPos.Line], 1, AStatement.StartPos.Character)) = '') and
      ((Rest = '') or (Rest = ';')) and (AStatement.EndPos.Line < High(Lines));
  end;

  // Korrektur: die Anweisung mit Self vor die Zeile mit inherited verschieben.
  function MoveFix(ABlock: TSyntaxNode; AInherited, AOffset: Integer): TArray<TRuleFix>;
  var
    Before, Moved: TSyntaxNode;
    Line: Integer;
    Text: string;
  begin
    Result := nil;
    Before := TopStatement(ABlock, AInherited);
    Moved := TopStatement(ABlock, AOffset);
    if (Before = nil) or (Moved = nil) or (Before = Moved) or not OwnLines(Before) or not OwnLines(Moved) then
      Exit;
    Text := '';
    for Line := Moved.StartPos.Line to Moved.EndPos.Line do
      Text := Text + Lines[Line] + LineBreak;
    Result := [TRuleFix.Create('Vor inherited verschieben', [
      TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(Before.StartPos.Line, 0),
        TTextPosition.Create(Before.StartPos.Line, 0)), Text),
      TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(Moved.StartPos.Line, 0),
        TTextPosition.Create(Moved.EndPos.Line + 1, 0)), '')])];
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    First, Position, InheritedAt: Integer;
    TypeName, Method, Where: string;
    Block: TSyntaxNode;
    IsAfterConstruction, Counting: Boolean;
  begin
    First := CodeAt(ARoutine.StartOffset);
    if (Pos('.', ARoutine.Name) = 0) or IsKey(First, 'class') then
      Exit;
    TypeName := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
    Method := Copy(ARoutine.Name, LastDelimiter('.', ARoutine.Name) + 1, MaxInt);
    IsAfterConstruction := SameText(Method, 'AfterConstruction');
    if not IsKey(First, 'constructor') and not IsAfterConstruction then
      Exit;
    Block := TRoutineBody.BodyOf(ARoutine);
    if Block = nil then
      Exit;
    Counting := OwnCounting(TypeName);
    // Nachfahren von TInterfacedObject: nur AfterConstruction nach inherited (der Schutz ist dann aufgehoben).
    if not Counting and not (IsAfterConstruction and Ancestry.DescendsFrom(TypeName, 'TInterfacedObject')) then
      Exit;
    if IsKey(First, 'constructor') then
      Where := 'im Konstruktor'
    else
      Where := 'in AfterConstruction';
    InheritedAt := -1;
    for Position := CodeAt(Block.StartOffset) to High(Code) do
    begin
      if Token(Position).Offset >= Block.EndOffset then
        Break;
      if (InheritedAt < 0) and IsKey(Position, 'inherited') then
        InheritedAt := Position;
      if not IsName(Position, 'Self') or not PassesAsInterface(Position) or
        (TRoutineBody.RoutineAt(AContext.Tree, Token(Position).Offset) <> ARoutine) then
        Continue;
      if Counting then
        AReport.Add(TTextRange.Create(Token(Position).StartPos, Token(Position).EndPos),
          Format('Self wird %s als Interface übergeben; die eigene Referenzzählung von %s gibt das Objekt ' +
          'frei, sobald der Zähler danach auf 0 fällt.', [Where, TypeName]))
      else if InheritedAt >= 0 then
        AReport.Add(TTextRange.Create(Token(Position).StartPos, Token(Position).EndPos),
          'Self wird nach inherited AfterConstruction als Interface übergeben; fällt der Zähler danach auf 0, ' +
          'ist das Objekt schon freigegeben.',
          MoveFix(Block, Token(InheritedAt).Offset, Token(Position).Offset));
    end;
  end;

var
  Index: Integer;
  Routines: TArray<TSyntaxNode>;
  Routine: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Self') then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      Code := Code + [Index];
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Routines := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
        Routines := Routines + [ANode];
      Result := True;
    end);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Routine in Routines do
      CheckRoutine(Routine);
  finally
    Types.Free;
    Ancestry.Free;
  end;
end;

{ TRawMemoryLeakRule }

type
  /// <summary>Wie eine lokale Variable an einer Stelle vorkommt (raw-memory-leak, #1047).</summary>
{$SCOPEDENUMS ON}
  TRawMemoryUse = (Use, Alloc, Release, Escape);
{$SCOPEDENUMS OFF}

const
  // Belegungen mit der Variablen als erstem Argument bzw. als Ziel der Zuweisung.
  RawAllocCalls: array[0..2] of string = ('GetMem', 'New', 'ReallocMem');
  RawAllocFunctions: array[0..4] of string = ('AllocMem', 'GetMemory', 'StrAlloc', 'StrNew', 'AnsiStrAlloc');
  RawReleaseCalls: array[0..4] of string = ('FreeMem', 'Dispose', 'StrDispose', 'FreeMemory', 'FreeMemAndNil');
  // Methoden, die den Zeiger übernehmen (in Listen, Felder anderer Objekte).
  RawStorePrefixes: array[0..11] of string = ('Add', 'Insert', 'Push', 'Enqueue', 'Put', 'Store', 'Register',
    'Attach', 'Append', 'Set', 'Assign', 'TryAdd');
  // Teile eines Routinennamens, die auf eine eigene Freigaberoutine schließen lassen.
  RawReleaseWords: array[0..5] of string = ('Free', 'Frei', 'Release', 'Dispose', 'Destroy', 'Dealloc');

function TRawMemoryLeakRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(RawMemoryLeakRuleId, TRuleSeverity.Warning,
    'GetMem oder New ohne Freigabe');
end;

class function TRawMemoryLeakRule.ReleaseFor(const AAllocator: string): string;
begin
  if MatchText(AAllocator, ['GetMem', 'AllocMem', 'ReallocMem']) then
    Result := 'FreeMem'
  else if SameText(AAllocator, 'GetMemory') then
    Result := 'FreeMemory'
  else if SameText(AAllocator, 'New') then
    Result := 'Dispose'
  else if MatchText(AAllocator, ['StrAlloc', 'StrNew', 'AnsiStrAlloc']) then
    Result := 'StrDispose'
  else
    Result := '';
end;

procedure TRawMemoryLeakRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<string>;
  LineBreak: string;

  function StartsWithAny(const AName: string; const APrefixes: array of string): Boolean;
  var
    Prefix: string;
  begin
    for Prefix in APrefixes do
      if StartsText(Prefix, AName) then
        Exit(True);
    Result := False;
  end;

  function ContainsAny(const AName: string; const AWords: array of string): Boolean;
  var
    Word: string;
  begin
    for Word in AWords do
      if ContainsText(AName, Word) then
        Exit(True);
    Result := False;
  end;

  // Typumwandlung wie PByte(P), PChar(P), Pointer(P): ein Argument, Aufruf über einen Typnamen.
  function IsTypeCast(ACall: TSyntaxNode): Boolean;
  var
    Name: string;
  begin
    Result := False;
    if (ACall.ChildCount <> 2) or (ACall[0].Kind <> TSyntaxKind.Identifier) then
      Exit;
    Name := ACall[0].Name;
    Result := MatchText(Name, ['Pointer', 'NativeInt', 'NativeUInt', 'IntPtr', 'UIntPtr', 'PChar', 'PAnsiChar',
      'PWideChar', 'PByte', 'Integer', 'Cardinal', 'Int64', 'UInt64', 'LongInt', 'LongWord']) or
      ((Length(Name) > 1) and CharInSet(Name[1], ['P', 'T']) and CharInSet(Name[2], ['A'..'Z']));
  end;

  // Art des Vorkommens ANode (Bezeichner der Variablen) vom Knoten aus nach oben bis zur Anweisung.
  function Classify(ANode: TSyntaxNode): TRawMemoryUse;
  var
    Current, Parent, Value: TSyntaxNode;
    Direct: Boolean;
  begin
    Current := ANode;
    Direct := True;
    while Current.Parent <> nil do
    begin
      Parent := Current.Parent;
      case Parent.Kind of
        // P^, P.Feld, P[I]: Zugriff auf den Speicher.
        TSyntaxKind.Dereference, TSyntaxKind.IndexAccess, TSyntaxKind.MemberAccess:
          Exit(TRawMemoryUse.Use);
        TSyntaxKind.AddressOf, TSyntaxKind.InlineVar, TSyntaxKind.VarDecl, TSyntaxKind.AnonymousMethod:
          Exit(TRawMemoryUse.Escape);
        TSyntaxKind.Call:
          begin
            if Parent[0] = Current then
              Exit(TRawMemoryUse.Use);
            if Direct and (Parent[1] = Current) and MatchText(Parent.Name, RawAllocCalls) then
            begin
              // ReallocMem(P, 0) gibt frei.
              if SameText(Parent.Name, 'ReallocMem') and (Parent.ChildCount = 3) and
                (Parent[2].Kind = TSyntaxKind.Literal) and (Parent[2].Name = '0') then
                Exit(TRawMemoryUse.Release);
              Exit(TRawMemoryUse.Alloc);
            end;
            if MatchText(Parent.Name, RawReleaseCalls) or ContainsAny(Parent.Name, RawReleaseWords) then
              Exit(TRawMemoryUse.Release);
            if SameText(Parent.Name, 'Exit') then
              Exit(TRawMemoryUse.Escape);
            if IsTypeCast(Parent) then
            begin
              Current := Parent;
              Direct := False;
              Continue;
            end;
            if (Parent[0].Kind = TSyntaxKind.MemberAccess) and StartsWithAny(Parent.Name, RawStorePrefixes) then
              Exit(TRawMemoryUse.Escape);
            // Als Argument zum Lesen oder Füllen weitergegeben (Pruefsumme(P, N), Stream.ReadBuffer(P^, N)).
            Exit(TRawMemoryUse.Use);
          end;
        TSyntaxKind.ParenExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.IfExpr:
          begin
            Current := Parent;
            Direct := False;
          end;
        TSyntaxKind.BinaryExpr:
          begin
            // Vergleiche lesen nur; P + N rechnet mit dem Zeiger weiter.
            if not MatchText(Parent.Name, ['+', '-']) then
              Exit(TRawMemoryUse.Use);
            Current := Parent;
            Direct := False;
          end;
        TSyntaxKind.AssignStatement:
          begin
            if Parent[0] <> Current then
              Exit(TRawMemoryUse.Escape);
            if not Direct then
              Exit(TRawMemoryUse.Use);
            Value := nil;
            if Parent.ChildCount > 1 then
              Value := Parent[1];
            if (Value <> nil) and (Value.Kind = TSyntaxKind.Call) and MatchText(Value.Name, RawAllocFunctions) then
              Exit(TRawMemoryUse.Alloc);
            // Neue Zuweisung (P := Q, P := nil): Herkunft unklar.
            Exit(TRawMemoryUse.Escape);
          end;
      else
        Exit(TRawMemoryUse.Use);
      end;
    end;
    Result := TRawMemoryUse.Use;
  end;

  // Name der Belegung an der Anweisung des Vorkommens ANode.
  function AllocatorOf(ANode: TSyntaxNode): string;
  begin
    if ANode.Parent.Kind = TSyntaxKind.Call then
      Result := ANode.Parent.Name
    else
      Result := ANode.Parent[1].Name;
  end;

  procedure Occurrences(ANode: TSyntaxNode; const AName: string; var AFound: TArray<TSyntaxNode>);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, AName) and
          not ((Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.MemberAccess) and (Node.Parent[0] <> Node))
          then
          AFound := AFound + [Node];
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  function HasAsm(ANode: TSyntaxNode): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.AsmBlock then
          Exit(True);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Steht ANode in einer anonymen Methode der Routine (die Variable wird eingefangen)?
  function InsideAnonymous(ANode, ARoutine: TSyntaxNode): Boolean;
  var
    Current: TSyntaxNode;
  begin
    Current := ANode.Parent;
    while (Current <> nil) and (Current <> ARoutine) do
    begin
      if Current.Kind = TSyntaxKind.AnonymousMethod then
        Exit(True);
      Current := Current.Parent;
    end;
    Result := False;
  end;

  // Die Anweisung, die das Vorkommen ANode enthält.
  function StatementOf(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode;
    while (Result <> nil) and not (Result.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.AssignStatement]) do
      Result := Result.Parent;
  end;

  procedure CheckVariable(ARoutine: TSyntaxNode; const AName: string);
  var
    Found: TArray<TSyntaxNode>;
    Node, First, Statement: TSyntaxNode;
    Index: Integer;
    Use: TRawMemoryUse;
    Allocator, Release: string;
    Edit: TTextEdit;
    Fixes: TArray<TRuleFix>;
  begin
    Found := nil;
    Occurrences(ARoutine, AName, Found);
    First := nil;
    for Node in Found do
    begin
      Use := Classify(Node);
      if InsideAnonymous(Node, ARoutine) then
        Use := TRawMemoryUse.Escape;
      if Use in [TRawMemoryUse.Release, TRawMemoryUse.Escape] then
        Exit;
      if (Use = TRawMemoryUse.Alloc) and (First = nil) then
        First := Node;
    end;
    // Lokale Routinen sehen die Variable ebenfalls: dort könnte sie freigegeben werden.
    for Index := 0 to ARoutine.ChildCount - 1 do
      if ARoutine[Index].Kind = TSyntaxKind.RoutineDecl then
      begin
        Found := nil;
        Occurrences(ARoutine[Index], AName, Found);
        if Found <> nil then
          Exit;
      end;
    if First = nil then
      Exit;
    Allocator := AllocatorOf(First);
    Release := ReleaseFor(Allocator);
    Statement := StatementOf(First);
    Fixes := nil;
    if (Release <> '') and (Statement <> nil) and WrapFollowingInTryFinally(Lines, LineBreak, Statement, '',
      Release + '(' + AName + ');', AContext.Formatting, Edit) then
      Fixes := [TRuleFix.Create(Format('try … finally %s(%s) end einfügen', [Release, AName]), [Edit])];
    AReport.Add(TTextRange.Create(Statement.StartPos, Statement.EndPos),
      Format('%s wird mit %s angelegt, aber nie freigegeben.', [AName, Allocator]), TRuleConfidence.Medium,
      Fixes);
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    Index, Inner: Integer;
    Section, Decl: TSyntaxNode;
    Name: string;
  begin
    if HasAsm(ARoutine) then
      Exit;
    for Index := 0 to ARoutine.ChildCount - 1 do
    begin
      Section := ARoutine[Index];
      if Section.Kind <> TSyntaxKind.VarSection then
        Continue;
      for Inner := 0 to Section.ChildCount - 1 do
      begin
        Decl := Section[Inner];
        if Decl.Kind <> TSyntaxKind.VarDecl then
          Continue;
        for Name in Decl.Name.Split([',']) do
          if Trim(Name) <> '' then
            CheckVariable(ARoutine, Trim(Name));
      end;
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
          CheckRoutine(Node);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Word: string;
  Any: Boolean;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Any := False;
  for Word in RawAllocCalls do
    Any := Any or ContainsText(AContext.Text, Word);
  for Word in RawAllocFunctions do
    Any := Any or ContainsText(AContext.Text, Word);
  if not Any then
    Exit;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Visit(AContext.Tree.Root);
end;

{ TStringListObjectsLeakRule }

type
  /// <summary>Eine TStringList der Unit bzw. die Items einer ListBox oder ComboBox (#1048).</summary>
  TObjectsHost = record
    /// <summary>Ausdruck in Kleinschreibung ohne Self. und Leerraum, z. B. fkunden bzw. lbkunden.items.</summary>
    Key: string;
    /// <summary>Wie im Quelltext, für die Meldung.</summary>
    Text: string;
    /// <summary>Erzeugung X := TStringList.Create(…); nil bei Items eines Steuerelements.</summary>
    Creation: TSyntaxNode;
    Owning: Boolean;
    /// <summary>Gibt die Unit Objects frei oder gibt sie die Liste weiter? Dann schweigt die Regel.</summary>
    Handled: Boolean;
  end;

const
  // Klassen, deren OwnsObjects die Objekte freigibt.
  StringListClasses: array[0..1] of string = ('TStringList', 'THashedStringList');
  // Steuerelemente, deren Items Objekte halten, aber nie freigeben.
  ObjectItemControls: array[0..4] of string = ('TListBox', 'TComboBox', 'TCheckListBox', 'TComboBoxEx',
    'TColorListBox');
  FreeWords: array[0..3] of string = ('Free', 'FreeAndNil', 'DisposeOf', 'Destroy');

function TStringListObjectsLeakRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(StringListObjectsLeakRuleId, TRuleSeverity.Warning,
    'Objekte in einer TStringList ohne Besitz');
end;

class function TStringListObjectsLeakRule.KeyOf(const AText: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 1 to Length(AText) do
    if not CharInSet(AText[Index], [' ', #9, #10, #13]) then
      Result := Result + AText[Index];
  Result := LowerCase(Result);
  if StartsStr('self.', Result) then
    Result := Copy(Result, 6, MaxInt);
end;

procedure TStringListObjectsLeakRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Hosts: TArray<TObjectsHost>;
  Ancestry: TAncestry;
  Lines: TArray<string>;
  LineBreak: string;

  function TextOf(ANode: TSyntaxNode): string;
  begin
    Result := TRoutineBody.TextOf(AContext.Text, ANode);
  end;

  function HostIndex(const AKey: string): Integer;
  begin
    for Result := 0 to High(Hosts) do
      if Hosts[Result].Key = AKey then
        Exit;
    Result := -1;
  end;

  // TStringList.Create bzw. TStringList.Create(…) (auch mit Unit-Präfix): der Create-Knoten, sonst nil.
  function StringListCreate(ANode: TSyntaxNode; const AClasses: array of string): TSyntaxNode;
  var
    Access: TSyntaxNode;
  begin
    Result := nil;
    Access := ANode;
    if (Access.Kind = TSyntaxKind.Call) and (Access.ChildCount > 0) then
      Access := Access[0];
    if (Access.Kind = TSyntaxKind.MemberAccess) and SameText(Access.Name, 'Create') and (Access.ChildCount = 1) and
      (Access[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and MatchText(Access[0].Name, AClasses)
      then
      Result := ANode;
  end;

  // Erzeugtes Objekt T.Create(…) ohne Owner: Name der Klasse, sonst ''.
  function CreatedClass(ANode: TSyntaxNode): string;
  var
    Access: TSyntaxNode;
    Name, First: string;
  begin
    Result := '';
    Access := ANode;
    First := '';
    if (Access.Kind = TSyntaxKind.Call) and (Access.ChildCount > 0) then
    begin
      if Access.ChildCount > 1 then
        First := TextOf(Access[1]);
      Access := Access[0];
    end;
    if (Access.Kind <> TSyntaxKind.MemberAccess) or not SameText(Access.Name, 'Create') or (Access.ChildCount <> 1) or
      not (Access[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
      Exit;
    Name := Access[0].Name;
    // Komponenten mit Owner gibt der Owner frei (wie create-without-assignment).
    if (First <> '') and not SameText(First, 'nil') and (MatchText(First, ['Self', 'Owner', 'AOwner',
      'Application']) or Ancestry.DescendsFrom(Name, 'TComponent')) then
      Exit;
    if TCreateWithoutAssignmentRule.LooksLikeType(Name) then
      Result := Name;
  end;

  procedure AddHost(const AText: string; ACreation: TSyntaxNode);
  var
    Host: TObjectsHost;
    Index: Integer;
  begin
    Host.Key := KeyOf(AText);
    Host.Text := AText;
    Host.Creation := ACreation;
    Host.Owning := False;
    Host.Handled := False;
    if ACreation <> nil then
      // Create(True) besitzt; andere Konstruktoren (QuoteChar, Duplicates) nicht.
      Host.Owning := (ACreation.Kind = TSyntaxKind.Call) and (ACreation.ChildCount = 2) and
        SameText(TextOf(ACreation[1]), 'True');
    Index := HostIndex(Host.Key);
    if Index < 0 then
      Hosts := Hosts + [Host]
    else if ACreation <> nil then
    begin
      // Mehrfach erzeugt: besitzend, sobald eine Erzeugung besitzt; die erste bleibt Ziel der Korrektur.
      Hosts[Index].Owning := Hosts[Index].Owning or Host.Owning;
      if Hosts[Index].Creation = nil then
        Hosts[Index].Creation := ACreation;
    end;
  end;

  // Erzeugungen, OwnsObjects := True und Felder vom Typ eines Steuerelements.
  procedure CollectHosts(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
    Name: string;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and
          (StringListCreate(Node[1], StringListClasses) <> nil) then
          AddHost(TextOf(Node[0]), Node[1]);
        if (Node.Kind = TSyntaxKind.Field) and (Node.ChildCount > 0) and
          (Node[0].Kind = TSyntaxKind.TypeReference) and MatchText(Node[0].Name, ObjectItemControls) then
          for Name in Node.Name.Split([',']) do
            AddHost(Trim(Name) + '.Items', nil);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure CollectOwning(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index, Host: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and
          (Node[0].Kind = TSyntaxKind.MemberAccess) and SameText(Node[0].Name, 'OwnsObjects') and
          (Node[0].ChildCount = 1) and SameText(TextOf(Node[1]), 'True') then
        begin
          Host := HostIndex(KeyOf(TextOf(Node[0][0])));
          if Host >= 0 then
            Hosts[Host].Owning := True;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  function ContainsFree(ANode: TSyntaxNode): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call]) and
          MatchText(Node.Name, FreeWords) then
          Exit(True);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Liest die Routine X.Objects[…] und gibt sie etwas frei, gilt die Freigabe als erledigt.
  procedure MarkReleases(ARoutine, ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index, Host: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.MemberAccess) and SameText(Node.Name, 'Objects') and (Node.ChildCount = 1) then
        begin
          Host := HostIndex(KeyOf(TextOf(Node[0])));
          if (Host >= 0) and ContainsFree(ARoutine) then
            Hosts[Host].Handled := True;
        end;
        // Die Liste als Argument (FreeObjects(Liste)) oder auf der rechten Seite einer Zuweisung: weitergegeben.
        if (Node.Parent <> nil) and (((Node.Parent.Kind = TSyntaxKind.Call) and (Node.Parent[0] <> Node) and
          not MatchText(Node.Parent.Name, ['FreeAndNil', 'Assigned'])) or
          ((Node.Parent.Kind = TSyntaxKind.AssignStatement) and (Node.Parent[0] <> Node)) or
          (Node.Parent.Kind = TSyntaxKind.AddressOf)) and
          (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
        begin
          Host := HostIndex(KeyOf(TextOf(Node)));
          if Host >= 0 then
            Hosts[Host].Handled := True;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure VisitRoutines(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
          MarkReleases(Node, Node);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  function EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode.Parent;
    while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
      Result := Result.Parent;
  end;

  // Lokale Variable AName, in der Routine aus T.Create(…) erzeugt und sonst nur gelesen (V.Name) oder an
  // AddObject übergeben: Name der Klasse, sonst ''.
  function LocalCreatedClass(ARoutine: TSyntaxNode; const AName: string; AAdd: TSyntaxNode): string;
  var
    Found: string;
    Other: Boolean;

    procedure Scan(ANode: TSyntaxNode);
    var
      Pending: TStack<TSyntaxNode>;
      Node: TSyntaxNode;
      Index: Integer;
      Parent: TSyntaxNode;
    begin
      // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion (die erste Erzeugung zählt).
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ANode);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          if (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, AName) and (Node.Parent <> nil) then
          begin
            Parent := Node.Parent;
            if (Parent.Kind = TSyntaxKind.AssignStatement) and (Parent[0] = Node) and (Parent.ChildCount = 2) and
              (CreatedClass(Parent[1]) <> '') and (Found = '') then
              Found := CreatedClass(Parent[1])
            // V.Name liest nur; alles andere außer dem AddObject-Argument gibt V weiter oder frei.
            else if not ((Parent.Kind = TSyntaxKind.MemberAccess) and (Parent[0] = Node) and
              not MatchText(Parent.Name, FreeWords)) and (Parent <> AAdd) then
              Other := True;
          end;
          for Index := Node.ChildCount - 1 downto 0 do
            Pending.Push(Node[Index]);
        end;
      finally
        Pending.Free;
      end;
    end;

  var
    Index, Inner: Integer;
    Local: Boolean;
    Name: string;
  begin
    Result := '';
    Local := False;
    for Index := 0 to ARoutine.ChildCount - 1 do
      if ARoutine[Index].Kind = TSyntaxKind.VarSection then
        for Inner := 0 to ARoutine[Index].ChildCount - 1 do
          for Name in ARoutine[Index][Inner].Name.Split([',']) do
            if SameText(Trim(Name), AName) then
              Local := True;
    if not Local then
      Exit;
    Found := '';
    Other := False;
    Scan(ARoutine);
    if not Other then
      Result := Found;
  end;

  function OwnsFix(const AHost: TObjectsHost; out AFix: TRuleFix): Boolean;
  var
    Creation, Access: TSyntaxNode;
    Statement: TSyntaxNode;
    ClassText: string;
  begin
    Result := False;
    Creation := AHost.Creation;
    if Creation = nil then
      Exit;
    Access := Creation;
    if Creation.Kind = TSyntaxKind.Call then
      Access := Creation[0];
    ClassText := TextOf(Access[0]);
    if (Creation.Kind = TSyntaxKind.MemberAccess) or (Creation.ChildCount = 1) then
    begin
      // TStringList.Create bzw. TStringList.Create() → TStringList.Create(True)
      AFix := TRuleFix.Create(Format('%s.Create(True) setzen', [ClassText]),
        [TTextEdit.Create(TTextRange.Create(Creation.StartPos, Creation.EndPos), ClassText + '.Create(True)')]);
      Exit(True);
    end;
    if (Creation.ChildCount = 2) and SameText(TextOf(Creation[1]), 'False') then
    begin
      AFix := TRuleFix.Create(Format('%s.Create(True) setzen', [ClassText]),
        [TTextEdit.Create(TTextRange.Create(Creation[1].StartPos, Creation[1].EndPos), 'True')]);
      Exit(True);
    end;
    // Andere Konstruktoren: OwnsObjects nach der Erzeugung setzen.
    Statement := Creation.Parent;
    if (Statement = nil) or (Statement.Kind <> TSyntaxKind.AssignStatement) or
      (Statement.StartPos.Line <> Statement.EndPos.Line) or (Statement.EndPos.Line > High(Lines)) then
      Exit;
    // Die Zeile muss mit der Anweisung enden.
    if Trim(Copy(Lines[Statement.EndPos.Line], Statement.EndPos.Character + 1, MaxInt)) <> ';' then
      Exit;
    AFix := TRuleFix.Create('OwnsObjects := True setzen',
      [TTextEdit.Create(TTextRange.Create(Statement.EndPos.Line + 1, 0, Statement.EndPos.Line + 1, 0),
      Copy(Lines[Statement.StartPos.Line], 1, Statement.StartPos.Character) + TextOf(Statement[0]) +
      '.OwnsObjects := True;' + LineBreak)]);
    Result := True;
  end;

  procedure CheckAdd(ANode: TSyntaxNode);
  var
    Host, ObjectArg: Integer;
    Access, Argument, Routine: TSyntaxNode;
    ClassName: string;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    if (ANode.Kind <> TSyntaxKind.Call) or (ANode.ChildCount < 1) or (ANode[0].Kind <> TSyntaxKind.MemberAccess) then
      Exit;
    if SameText(ANode.Name, 'AddObject') then
      ObjectArg := 2
    else if SameText(ANode.Name, 'InsertObject') then
      ObjectArg := 3
    else
      Exit;
    Access := ANode[0];
    if (ANode.ChildCount <> ObjectArg + 1) or (Access.ChildCount <> 1) then
      Exit;
    Host := HostIndex(KeyOf(TextOf(Access[0])));
    if (Host < 0) or Hosts[Host].Owning or Hosts[Host].Handled then
      Exit;
    Argument := ANode[ObjectArg];
    ClassName := CreatedClass(Argument);
    if (ClassName = '') and (Argument.Kind = TSyntaxKind.Identifier) then
    begin
      Routine := EnclosingRoutine(ANode);
      if Routine <> nil then
        ClassName := LocalCreatedClass(Routine, Argument.Name, ANode);
    end;
    if ClassName = '' then
      Exit;
    Fixes := nil;
    if OwnsFix(Hosts[Host], Fix) then
      Fixes := [Fix];
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
      Format('%s besitzt die Objekte nicht; die %s-Objekte werden nie freigegeben.',
      [TextOf(Access[0]), ClassName]), TRuleConfidence.Medium, Fixes);
  end;

  // Prüft jeden Knoten nach seinen Kindern (Nachordnung) mit CheckAdd.
  procedure CheckAdds(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxPostOrderEntry>;
    Entry: TSyntaxPostOrderEntry;
    Index: Integer;
  begin
    // Iterativ (Bericht M1): Done = die Kinder sind schon geprüft.
    Pending := TStack<TSyntaxPostOrderEntry>.Create;
    try
      Pending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
      while Pending.Count > 0 do
      begin
        Entry := Pending.Pop;
        if Entry.Done then
        begin
          CheckAdd(Entry.Node);
          Continue;
        end;
        Pending.Push(TSyntaxPostOrderEntry.Create(Entry.Node, True));
        for Index := Entry.Node.ChildCount - 1 downto 0 do
          Pending.Push(TSyntaxPostOrderEntry.Create(Entry.Node[Index], False));
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not (ContainsText(AContext.Text, 'AddObject') or
    ContainsText(AContext.Text, 'InsertObject')) then
    Exit;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Hosts := nil;
  CollectHosts(AContext.Tree.Root);
  if Hosts = nil then
    Exit;
  CollectOwning(AContext.Tree.Root);
  VisitRoutines(AContext.Tree.Root);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  try
    CheckAdds(AContext.Tree.Root);
  finally
    Ancestry.Free;
  end;
end;

{ TComponentInterfaceDanglingRule }

function TComponentInterfaceDanglingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ComponentInterfaceDanglingRuleId, TRuleSeverity.Warning,
    'Interface auf eine Komponente ohne Referenzzählung bleibt nach der Freigabe gespeichert');
end;

class function TComponentInterfaceDanglingRule.Counterpart(const AMethod: string): string;
var
  Index: Integer;
begin
  for Index := 0 to High(StoreMethods) do
    if SameText(StoreMethods[Index], AMethod) then
      Exit(RemoveCounterparts[Index]);
  Result := '';
end;

procedure TComponentInterfaceDanglingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  // VCL- und FMX-Klassen, die von TComponent erben: Ohne Index endet die Kette der Vorfahren oft bei ihnen.
  KnownComponents: array[0..16] of string = ('TComponent', 'TControl', 'TWinControl', 'TCustomControl',
    'TGraphicControl', 'TScrollingWinControl', 'TCustomForm', 'TForm', 'TCustomFrame', 'TFrame', 'TDataModule',
    'TCommonCustomForm', 'TCustomPanel', 'TPanel', 'TStyledControl', 'TFmxObject', 'TCustomDataModule');
  FreeMethods: array[0..3] of string = ('Free', 'Release', 'DisposeOf', 'Destroy');
type
  /// <summary>Eine Freigabe in der Datei: Anweisung und freigegebener Ausdruck.</summary>
  TRelease = record
    Statement: TSyntaxNode;
    Target: TSyntaxNode;
  end;
var
  Resolver: TNameResolver;
  Ancestry: TAncestry;
  FileName: string;
  Bases: TArray<string>;
  Releases: TArray<TRelease>;
  Calls, Assignments, Clears: TArray<TSyntaxNode>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  /// <summary>Text eines Ausdrucks ohne führendes "Self." und ohne Leerraum, zum Vergleichen.</summary>
  function Normalized(ANode: TSyntaxNode): string;
  begin
    Result := StringReplace(UpperCase(NodeText(ANode)), ' ', '', [rfReplaceAll]);
    if StartsStr('SELF.', Result) then
      Result := Copy(Result, 6, MaxInt);
  end;

  function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode;
    while (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
      Result := Result[0];
  end;

  /// <summary>Äußerster Knoten um ANode, der nur aus Klammern besteht.</summary>
  function Outer(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode;
    while (Result.Parent <> nil) and (Result.Parent.Kind = TSyntaxKind.ParenExpr) do
      Result := Result.Parent;
  end;

  /// <summary>Ein einfacher Name (X oder Self.X), außer Self selbst.</summary>
  function IsObjectName(ANode: TSyntaxNode): Boolean;
  begin
    case ANode.Kind of
      TSyntaxKind.Identifier:
        Result := not SameText(ANode.Name, 'Self');
      TSyntaxKind.MemberAccess:
        Result := (ANode.ChildCount = 1) and (ANode[0].Kind = TSyntaxKind.Identifier) and
          SameText(ANode[0].Name, 'Self');
    else
      Result := False;
    end;
  end;

  function Resolve(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
  var
    TypeFound: Boolean;
  begin
    Result := Resolver.NodeType(AContext.Tree, FileName, ANode, ASymbol, AType, TypeFound) and TypeFound;
  end;

  function SameSymbol(const A, B: TResolvedSymbol): Boolean;
  begin
    Result := SameText(A.Name, B.Name) and SameText(A.FileName, B.FileName) and
      (A.Range.StartPos.Line = B.Range.StartPos.Line) and (A.Range.StartPos.Character = B.Range.StartPos.Character);
  end;

  /// <summary>Lokale Variable oder Parameter (auch als Empfänger einer Kette L.X)?</summary>
  function IsLocal(ANode: TSyntaxNode): Boolean;
  var
    First: TSyntaxNode;
  begin
    First := ANode;
    while (First.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Call]) and
      (First.ChildCount > 0) do
      First := First[0];
    if First.Kind <> TSyntaxKind.Identifier then
      Exit(True);
    if SameText(First.Name, 'Self') then
      Exit(False);
    Result := Resolver.ResolveChain(AContext.Tree, FileName, [First.Name], First.StartOffset).Kind =
      TResolvedKind.Local;
  end;

  /// <summary>Basisklasse ohne Referenzzählung, von der AClass erbt (Option componentClasses), bzw.
  /// TInterfacedObject; '' wenn nichts davon oder wenn die Kette abbricht. Deklariert eine Klasse darunter _Release,
  /// zählt sie selbst und gilt nicht.</summary>
  function ComponentBase(const AClass: string): string;
  var
    Name: string;
    Depth: Integer;
    Found: TSymbolLocation;
    Method: TIndexSymbol;
  begin
    Result := '';
    Name := AClass;
    for Depth := 0 to 63 do
    begin
      if MatchText(Name, Bases) then
        Exit(Name);
      if MatchText('TComponent', Bases) and MatchText(Name, KnownComponents) then
        Exit('TComponent');
      if SameText(Name, 'TInterfacedObject') then
        Exit(Name);
      if MatchText(Name, ['TObject', 'TInterfacedPersistent']) then
        Exit;
      if Ancestry.FindClass(Name, Found) then
        for Method in Ancestry.Methods(Found) do
          if SameText(Method.Name, '_Release') then
            Exit;
      Name := Ancestry.ParentOf(Name);
      if Name = '' then
        Exit;
    end;
  end;

  /// <summary>Kommt das Objekt AObject in ANode vor (X, X as IFoo, Self.X)?</summary>
  function Mentions(ANode: TSyntaxNode; const AObject: TResolvedSymbol): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Child: Integer;
    Symbol, TypeInfo: TResolvedSymbol;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if IsObjectName(Node) and SameText(Normalized(Node), AObject.Name) and Resolve(Node, Symbol, TypeInfo) and
          SameSymbol(Symbol, AObject) then
          Exit(True);
        for Child := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Child]);
      end;
    finally
      Pending.Free;
    end;
  end;

  /// <summary>Gibt es eine Abmeldung? FreeNotification auf dem Objekt, ein anderer Aufruf am selben Empfänger mit
  /// dem Objekt als Argument bzw. Clear, eine weitere Zuweisung an dieselbe Stelle.</summary>
  function Unregistered(const AObject: TResolvedSymbol; AStore, AHolder: TSyntaxNode; AIsCall: Boolean): Boolean;
  var
    Call, Callee, Assignment: TSyntaxNode;
    Symbol, TypeInfo: TResolvedSymbol;
    Holder: string;
    Argument: Integer;
  begin
    Holder := Normalized(AHolder);
    for Call in Calls do
    begin
      Callee := Call[0];
      if (Callee.Kind <> TSyntaxKind.MemberAccess) or (Callee.ChildCount = 0) then
        Continue;
      if SameText(Callee.Name, 'FreeNotification') and Resolve(Callee[0], Symbol, TypeInfo) and
        SameSymbol(Symbol, AObject) then
        Exit(True);
      if not AIsCall or (Call = AStore) or (Normalized(Callee[0]) <> Holder) then
        Continue;
      if SameText(Callee.Name, 'Clear') then
        Exit(True);
      for Argument := 1 to Call.ChildCount - 1 do
        if Mentions(Call[Argument], AObject) then
          Exit(True);
    end;
    // Clear ohne Klammern ist eine Anweisung aus MemberAccess.
    for Callee in Clears do
      if AIsCall and (Normalized(Callee[0]) = Holder) then
        Exit(True);
    if not AIsCall then
      for Assignment in Assignments do
        if (Assignment <> AStore) and (Normalized(Assignment[0]) = Holder) then
          Exit(True);
    Result := False;
  end;

  /// <summary>Abmeldung vor der Freigabe einfügen: Empfänger.Gegenstück(Argument); bzw. Ziel := nil;.</summary>
  function UnregisterFix(AStore, AHolder, AArgument: TSyntaxNode; AIsCall: Boolean; const ARelease: TRelease;
    out AFix: TRuleFix): Boolean;
  var
    Method, Line: string;
    Symbol, TypeInfo, Member: TResolvedSymbol;
  begin
    Result := False;
    if not TRoutineBody.InList(ARelease.Statement) or
      (ARelease.Statement.StartPos.Line <> ARelease.Statement.EndPos.Line) then
      Exit;
    if AIsCall then
    begin
      Method := Counterpart(AStore[0].Name);
      // Das Gegenstück muss es am Typ des Empfängers geben.
      if (Method = '') or not Resolve(AHolder, Symbol, TypeInfo) or not Resolver.FindMember(TypeInfo, Method, Member)
        then
        Exit;
      Line := NodeText(AHolder) + '.' + Method + '(' + NodeText(AArgument) + ');';
    end
    else
      Line := NodeText(AHolder) + ' := nil;';
    AFix := TRuleFix.Create('Abmeldung vor der Freigabe einfügen',
      [TRoutineBody.InsertBefore(AContext.Text, ARelease.Statement, Line)]);
    Result := True;
  end;

  /// <summary>Wird das Objekt hier als Interface gespeichert? AValue ist "X as IFoo" oder X selbst.</summary>
  procedure Inspect(AValue: TSyntaxNode);
  var
    Value, Parent, ObjectNode, Holder, Argument: TSyntaxNode;
    InterfaceName, Base, HolderText, ListType: string;
    IsCall: Boolean;
    ObjectSymbol, ObjectType, Symbol, TypeInfo: TResolvedSymbol;
    Release: TRelease;
    Fixes: TArray<TRuleFix>;
    Fix: TRuleFix;
    Found, Index: Integer;
  begin
    Value := Outer(AValue);
    Parent := Value.Parent;
    if Parent = nil then
      Exit;
    if (AValue.Kind = TSyntaxKind.BinaryExpr) then
    begin
      ObjectNode := Unwrapped(AValue[0]);
      if (AValue[1].Kind <> TSyntaxKind.Identifier) or
        not TSelfAsInterfaceInConstructorRule.IsInterfaceType(AValue[1].Name) then
        Exit;
      InterfaceName := AValue[1].Name;
    end
    else
    begin
      ObjectNode := AValue;
      InterfaceName := '';
    end;
    if not IsObjectName(ObjectNode) then
      Exit;
    // Ziel der Speicherung: Feld, globale Variable oder Liste, kein lokaler Name.
    if (Parent.Kind = TSyntaxKind.AssignStatement) and (Parent.ChildCount = 2) and (Parent[1] = Value) then
    begin
      IsCall := False;
      Holder := Parent[0];
      if InterfaceName = '' then
      begin
        if not Resolve(Holder, Symbol, TypeInfo) or (TypeInfo.SymbolKind <> TIndexSymbolKind.InterfaceType) then
          Exit;
        InterfaceName := TypeInfo.Name;
      end;
    end
    else if (Parent.Kind = TSyntaxKind.Call) and (Parent.ChildCount >= 2) and (Parent[0] <> Value) and
      (Parent[0].Kind = TSyntaxKind.MemberAccess) and (Parent[0].ChildCount = 1) and
      MatchText(Parent[0].Name, StoreMethods) then
    begin
      IsCall := True;
      Holder := Parent[0][0];
      if InterfaceName = '' then
      begin
        // Ohne "as" nur Listen von Interfaces: TList<IFoo>, TInterfaceList.
        if not MatchText(Parent[0].Name, ['Add', 'Insert']) or not IsObjectName(Holder) then
          Exit;
        // Der deklarierte Typ genügt; TList<T> selbst muss nicht im Index stehen.
        if Holder.Kind = TSyntaxKind.Identifier then
          Symbol := Resolver.ResolveChain(AContext.Tree, FileName, [Holder.Name], Holder.StartOffset)
        else
          Symbol := Resolver.ResolveChain(AContext.Tree, FileName, ['Self', Holder.Name], Holder.StartOffset);
        ListType := Symbol.TypeName;
        if (Symbol.TypeArgs <> '') and (Pos('<', ListType) = 0) then
          ListType := ListType + '<' + Symbol.TypeArgs + '>';
        if MatchText(ListType, ['TInterfaceList', 'System.Classes.TInterfaceList', 'Classes.TInterfaceList']) then
          InterfaceName := 'IInterface'
        else if StartsText('TList<', ListType) and EndsText('>', ListType) and
          TSelfAsInterfaceInConstructorRule.IsInterfaceType(Copy(ListType, 7, Length(ListType) - 7)) then
          InterfaceName := Copy(ListType, 7, Length(ListType) - 7)
        else
          Exit;
      end;
    end
    else
      Exit;
    if IsLocal(Holder) then
      Exit;
    if not Resolve(ObjectNode, ObjectSymbol, ObjectType) or
      not (ObjectSymbol.SymbolKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Variable]) or
      (ObjectType.SymbolKind <> TIndexSymbolKind.ClassType) then
      Exit;
    Base := ComponentBase(ObjectType.Name);
    if Base = '' then
      Exit;
    // Erste Freigabe desselben Objekts in der Datei.
    Found := -1;
    for Index := 0 to High(Releases) do
      if Resolve(Releases[Index].Target, Symbol, TypeInfo) and SameSymbol(Symbol, ObjectSymbol) then
      begin
        Found := Index;
        Break;
      end;
    if Found < 0 then
      Exit;
    Release := Releases[Found];
    HolderText := NodeText(Holder);
    // Referenzgezählt: Free gibt das Objekt frei, obwohl das gespeicherte Interface es noch hält; eine Abmeldung
    // davor gäbe es schon frei (Zähler 0), Free wäre dann die zweite Freigabe.
    if SameText(Base, 'TInterfacedObject') then
    begin
      AReport.Add(TTextRange.Create(Parent.StartPos, Parent.EndPos), Format('%s ist referenzgezählt ' +
        '(TInterfacedObject); %s gibt es frei, obwohl %s noch ein %s darauf hält.', [ObjectType.Name,
        NodeText(Release.Statement), HolderText, InterfaceName]), TRuleConfidence.Medium);
      Exit;
    end;
    if Unregistered(ObjectSymbol, Parent, Holder, IsCall) then
      Exit;
    Argument := Value;
    Fixes := nil;
    if UnregisterFix(Parent, Holder, Argument, IsCall, Release, Fix) then
      Fixes := [Fix];
    AReport.Add(TTextRange.Create(Parent.StartPos, Parent.EndPos), Format('%s ist ein %s ohne Referenzzählung; ' +
      'nach %s hält %s ein ungültiges %s.', [ObjectType.Name, Base, NodeText(Release.Statement), HolderText,
      InterfaceName]), TRuleConfidence.Medium, Fixes);
  end;

  procedure Collect(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Child: Integer;
    Release: TRelease;
    Expression: TSyntaxNode;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.Call:
            Calls := Calls + [Node];
          TSyntaxKind.AssignStatement:
            if Node.ChildCount = 2 then
              Assignments := Assignments + [Node];
          TSyntaxKind.CallStatement:
            if Node.ChildCount > 0 then
            begin
              // X.Free, X.Release …, FreeAndNil(X)
              Expression := Node[0];
              if (Expression.Kind = TSyntaxKind.Call) and (Expression.ChildCount > 0) and
                (Expression[0].Kind = TSyntaxKind.MemberAccess) then
                Expression := Expression[0];
              Release.Statement := Node;
              Release.Target := nil;
              if (Expression.Kind = TSyntaxKind.MemberAccess) and (Expression.ChildCount = 1) and
                MatchText(Expression.Name, FreeMethods) then
                Release.Target := Expression[0]
              else if (Expression.Kind = TSyntaxKind.Call) and SameText(Expression.Name, 'FreeAndNil') and
                (Expression.ChildCount = 2) then
                Release.Target := Expression[1];
              if (Release.Target <> nil) and IsObjectName(Release.Target) then
                Releases := Releases + [Release];
              if (Expression.Kind = TSyntaxKind.MemberAccess) and (Expression.ChildCount = 1) and
                SameText(Expression.Name, 'Clear') then
                Clears := Clears + [Expression];
            end;
        end;
        for Child := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Child]);
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Child: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.BinaryExpr) and SameText(Node.Name, 'as') and (Node.ChildCount = 2) then
          Inspect(Node)
        else if IsObjectName(Node) and (Outer(Node).Parent <> nil) and
          (Outer(Node).Parent.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.Call]) then
          Inspect(Node);
        for Child := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Child]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Bases := TRuleOptions.Strings(AContext.Options, 'componentClasses', ['TComponent']);
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Releases := nil;
  Calls := nil;
  Assignments := nil;
  Clears := nil;
  Collect(AContext.Tree.Root);
  if Releases = nil then
    Exit;
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  try
    Resolver.Namespaces := AContext.Namespaces;
    Visit(AContext.Tree.Root);
  finally
    Ancestry.Free;
    Resolver.Free;
  end;
end;

procedure RegisterOwnershipRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOwnedItemFreedRule.Create);
  ARegistry.Register(TCreateWithoutAssignmentRule.Create);
  ARegistry.Register(TSelfAsInterfaceInConstructorRule.Create);
  ARegistry.Register(TRawMemoryLeakRule.Create);
  ARegistry.Register(TStringListObjectsLeakRule.Create);
  ARegistry.Register(TComponentInterfaceDanglingRule.Create);
end;

end.
