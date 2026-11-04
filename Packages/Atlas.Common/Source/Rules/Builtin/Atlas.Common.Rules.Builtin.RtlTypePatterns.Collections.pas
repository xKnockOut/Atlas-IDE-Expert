unit Atlas.Common.Rules.Builtin.RtlTypePatterns.Collections;

// Regeln für Listen und Dictionaries aus Atlas.Common.Rules.Builtin.RtlTypePatterns (Stufe 2 aus #153, angemeldet in
// RegisterRtlTypePatternRules):
//   stringlist-unsorted      Find oder Duplicates := dupIgnore/dupError auf einer TStringList, die in der
//                            Datei erzeugt, aber nie sortiert wird (#925)
//   dictionary-get-without-check
//                            Dict[Key] bzw. Dict.Items[Key] gelesen, ohne dass ContainsKey oder TryGetValue
//                            denselben Schlüssel vorher in der Routine geprüft hat (#933). Still bleibt die
//                            Regel, wenn die Routine das Dictionary vorher selbst füllt (Add, AddOrSetValue,
//                            Dict[K] := …) oder der Schlüssel aus Keys stammt (for K in Dict.Keys,
//                            Namen := Dict.Keys.ToArray). Felder, die die Unit an anderer Stelle füllt, sichert
//                            die Klasse selbst (#1109). Korrektur: TryGetValue mit Vorgabewert
//   delimited-text-without-strict
//                            Liste.DelimitedText := … nach Liste.Delimiter := … in derselben Routine, ohne dass
//                            StrictDelimiter gesetzt wird (#952; bei Feldern in der ganzen Unit): DelimitedText
//                            trennt dann auch an Leerzeichen. Korrektur: StrictDelimiter := True; davor

interface

uses
  Atlas.Common.Rules.Contract;

type
  TStringListUnsortedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDictionaryGetWithoutCheckRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDelimitedTextWithoutStrictRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Pascal.FormatStrings,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Tokens;

{ TStringListUnsortedRule }

const
  StringListClasses: array[0..1] of string = ('TStringList', 'THashedStringList');
  // Aufrufe, die eine Liste nicht weitergeben: sie bleibt in der Hand der Routine.
  NonEscapingCalls: array[0..2] of string = ('FreeAndNil', 'Assigned', 'Free');
  // Methoden, die mit Sorted := True eine Ausnahme auslösen: dann keine Korrektur mit Sorted.
  UnsortedOnlyMethods: array[0..2] of string = ('Insert', 'Move', 'Exchange');

type
  // Was die Regel über eine Liste (lokal je Routine, sonst Feld) gesammelt hat.
  TStringListFacts = record
    Creation: TSyntaxNode;
    Sorted: Boolean;
    UnsortedOnly: Boolean;
    Hits: TArray<TSyntaxNode>;
  end;

  TDeclarationKinds = set of TSyntaxKind;

/// <summary>Deklariert ARoutine (ohne eingebettete Routinen, die eigene Variablen haben) AName als eines der
/// Elemente AKinds?</summary>
function RoutineDeclares(ARoutine: TSyntaxNode; const AName: string; const AKinds: TDeclarationKinds): Boolean;
var
  mPending: TStack<TSyntaxNode>;
  mNode, mChild: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (Bericht M1); mPending hält die Knoten, deren Kinder noch zu prüfen sind.
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoutine);
    while not Result and (mPending.Count > 0) do
    begin
      mNode := mPending.Pop;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mChild := mNode[mIndex];
        if mChild.Kind <> TSyntaxKind.RoutineDecl then
        begin
          Result := Result or ((mChild.Kind in AKinds) and ListsName(mChild.Name, AName));
          mPending.Push(mChild);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Ist AStatement ein if in einem Anweisungsblock mit der Bedingung ACondition?</summary>
function IsIfInBlock(AStatement, ACondition: TSyntaxNode): Boolean;
begin
  Result := (AStatement <> nil) and (AStatement.Kind = TSyntaxKind.IfStatement) and (AStatement.ChildCount > 0);
  Result := Result and (AStatement[0] = ACondition) and (AStatement.Parent <> nil) and
    (AStatement.Parent.Kind = TSyntaxKind.Block);
end;

function TStringListUnsortedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('stringlist-unsorted', TRuleSeverity.Warning,
    'Find oder Duplicates auf einer unsortierten TStringList');
end;

procedure TStringListUnsortedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Keys: TArray<string>;
  Facts: TArray<TStringListFacts>;
  Routines: TArray<TSyntaxNode>;
  LineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Name der Liste: X oder Self.X; sonst leer.
  function BaseName(ANode: TSyntaxNode): string;
  begin
    Result := '';
    if ANode = nil then
    begin
      Exit;
    end;
    if ANode.Kind = TSyntaxKind.Identifier then
    begin
      Result := ANode.Name;
    end
    else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
      (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
    begin
      Result := ANode.Name;
    end;
  end;

  // Schlüssel der Liste an ANode: Routine und Name für lokale Variablen, sonst der Feldname.
  function KeyOf(ANode: TSyntaxNode; const AName: string): string;
  var
    Index: Integer;
    Routine: TSyntaxNode;
  begin
    // Routines ist nach Start sortiert; die innerste umgebende Routine liegt hinten.
    for Index := High(Routines) downto 0 do
    begin
      Routine := Routines[Index];
      if (Routine.StartOffset <= ANode.StartOffset) and (Routine.EndOffset >= ANode.EndOffset) and
        RoutineDeclares(Routine, AName, [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar]) then
      begin
        Exit(IntToStr(Routine.StartOffset) + ':' + LowerCase(AName));
      end;
    end;
    Result := 'F:' + LowerCase(AName);
  end;

  function FactIndex(const AKey: string): Integer;
  var
    Index: Integer;
  begin
    for Index := 0 to High(Keys) do
    begin
      if Keys[Index] = AKey then
      begin
        Exit(Index);
      end;
    end;
    Result := Length(Keys);
    SetLength(Keys, Result + 1);
    SetLength(Facts, Result + 1);
    Keys[Result] := AKey;
    Facts[Result].Creation := nil;
    Facts[Result].Sorted := False;
    Facts[Result].UnsortedOnly := False;
    Facts[Result].Hits := nil;
  end;

  // Index der Liste, auf die ANode (X oder Self.X) zeigt; -1 ohne Namen.
  function ListOf(ANode: TSyntaxNode): Integer;
  var
    Name: string;
  begin
    Name := BaseName(ANode);
    if Name = '' then
    begin
      Exit(-1);
    end;
    Result := FactIndex(KeyOf(ANode, Name));
  end;

  function IsFalse(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'False');
  end;

  // TStringList.Create(...); ASorted, wenn Create(Duplicates, Sorted, CaseSensitive) sortiert.
  function IsCreation(AValue: TSyntaxNode; out ASorted: Boolean): Boolean;
  var
    Callee: TSyntaxNode;
  begin
    ASorted := False;
    Callee := AValue;
    if (AValue <> nil) and (AValue.Kind = TSyntaxKind.Call) and (AValue.ChildCount > 0) then
    begin
      Callee := AValue[0];
    end;
    Result := (Callee <> nil) and (Callee.Kind = TSyntaxKind.MemberAccess) and SameText(Callee.Name, 'Create') and
      (Callee.ChildCount = 1) and (Callee[0].Kind = TSyntaxKind.Identifier) and
      MatchText(Callee[0].Name, StringListClasses);
    if Result and (AValue.Kind = TSyntaxKind.Call) and (AValue.ChildCount = 4) then
    begin
      ASorted := not IsFalse(AValue[2]);
    end;
  end;

  procedure NoteCreation(AStatement: TSyntaxNode; AList: Integer; AValue: TSyntaxNode);
  var
    ConstructorSorted: Boolean;
  begin
    if (AList < 0) or not IsCreation(AValue, ConstructorSorted) then
    begin
      Exit;
    end;
    if Facts[AList].Creation = nil then
    begin
      Facts[AList].Creation := AStatement;
    end;
    if ConstructorSorted then
    begin
      Facts[AList].Sorted := True;
    end;
  end;

  // Die Liste wird weitergegeben: was der Empfänger damit macht, ist unbekannt.
  procedure NoteEscape(ANode: TSyntaxNode);
  var
    List: Integer;
  begin
    List := ListOf(ANode);
    if List >= 0 then
    begin
      Facts[List].Sorted := True;
    end;
  end;

  procedure VisitAssign(AStatement: TSyntaxNode);
  var
    Target, Value: TSyntaxNode;
    List: Integer;
  begin
    Target := AStatement[0];
    Value := AStatement[1];
    NoteCreation(AStatement, ListOf(Target), Value);
    NoteEscape(Value);
    if (Target.Kind <> TSyntaxKind.MemberAccess) or (Target.ChildCount <> 1) then
    begin
      Exit;
    end;
    List := ListOf(Target[0]);
    if List < 0 then
    begin
      Exit;
    end;
    if SameText(Target.Name, 'Sorted') and not IsFalse(Value) then
    begin
      Facts[List].Sorted := True;
    end
    else if SameText(Target.Name, 'Duplicates') and (Value.Kind = TSyntaxKind.Identifier) and
      MatchText(Value.Name, ['dupIgnore', 'dupError']) then
    begin
      Facts[List].Hits := Facts[List].Hits + [AStatement];
    end;
  end;

  // X.Methode oder X.Methode(...): Sortieren, Find und Methoden, die nur unsortiert gehen.
  procedure VisitMember(AMember, ACall: TSyntaxNode);
  var
    List: Integer;
  begin
    if AMember.ChildCount <> 1 then
    begin
      Exit;
    end;
    List := ListOf(AMember[0]);
    if List < 0 then
    begin
      Exit;
    end;
    if SameText(AMember.Name, 'Sort') or SameText(AMember.Name, 'CustomSort') then
    begin
      Facts[List].Sorted := True;
    end;
    if MatchText(AMember.Name, UnsortedOnlyMethods) then
    begin
      Facts[List].UnsortedOnly := True;
    end;
    if SameText(AMember.Name, 'Find') and (ACall <> nil) and (ACall.ChildCount = 3) then
    begin
      Facts[List].Hits := Facts[List].Hits + [ACall];
    end;
  end;

  procedure VisitInlineVar(ANode: TSyntaxNode);
  var
    Value: TSyntaxNode;
  begin
    if (ANode.ChildCount > 0) and (Pos(',', ANode.Name) = 0) then
    begin
      Value := ANode[ANode.ChildCount - 1];
      NoteEscape(Value);
      NoteCreation(ANode, FactIndex(KeyOf(ANode, Trim(ANode.Name))), Value);
    end;
  end;

  procedure VisitCall(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.MemberAccess) then
    begin
      VisitMember(ANode[0], ANode);
    end;
    // Als Argument übergeben: der Aufgerufene kann sortieren.
    if not MatchText(ANode.Name, NonEscapingCalls) then
    begin
      for Index := 1 to ANode.ChildCount - 1 do
      begin
        NoteEscape(ANode[Index]);
      end;
    end;
  end;

  // with X do Sorted := True ist nicht nachvollziehbar: als sortiert betrachten.
  procedure VisitWith(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    for Index := 0 to ANode.ChildCount - 2 do
    begin
      NoteEscape(ANode[Index]);
    end;
  end;

  procedure VisitNode(ANode: TSyntaxNode);
  begin
    case ANode.Kind of
      TSyntaxKind.AssignStatement:
        if ANode.ChildCount = 2 then
        begin
          VisitAssign(ANode);
        end;
      TSyntaxKind.InlineVar:
        VisitInlineVar(ANode);
      TSyntaxKind.Call:
        VisitCall(ANode);
      TSyntaxKind.CallStatement:
        if (ANode.ChildCount = 1) and (ANode[0].Kind = TSyntaxKind.MemberAccess) then
        begin
          VisitMember(ANode[0], nil);
        end;
      TSyntaxKind.WithStatement:
        VisitWith(ANode);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
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
        VisitNode(Node);
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure CollectRoutines(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion (nach Start sortiert).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          Routines := Routines + [Node];
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

  function Indent(ANode: TSyntaxNode): string;
  begin
    Result := StringOfChar(' ', ANode.StartPos.Character);
  end;

  function ListName(const AFacts: TStringListFacts): string;
  begin
    if AFacts.Creation.Kind = TSyntaxKind.InlineVar then
    begin
      Result := Trim(AFacts.Creation.Name);
    end
    else
    begin
      Result := Text(AFacts.Creation[0]);
    end;
  end;

  // Sorted := True direkt nach dem Erzeugen; nur in einem Anweisungsblock.
  function SortedFix(const AFacts: TStringListFacts): TArray<TRuleFix>;
  var
    Creation: TSyntaxNode;
  begin
    Result := nil;
    Creation := AFacts.Creation;
    if AFacts.UnsortedOnly or (Creation.Parent = nil) or (Creation.Parent.Kind <> TSyntaxKind.Block) then
    begin
      Exit;
    end;
    Result := [TRuleFix.Create('Sorted := True nach dem Erzeugen ergänzen',
      [TRuleEdit.Create(TTextRange.Create(Creation.EndPos, Creation.EndPos),
      ';' + LineBreak + Indent(Creation) + ListName(AFacts) + '.Sorted := True')])];
  end;

  // if X.Find(S, I) then: vorher I := X.IndexOf(S), im if I >= 0.
  function IndexOfFix(AFind: TSyntaxNode): TArray<TRuleFix>;
  var
    Statement: TSyntaxNode;
    IndexText: string;
  begin
    Result := nil;
    Statement := AFind.Parent;
    if not IsIfInBlock(Statement, AFind) then
    begin
      Exit;
    end;
    IndexText := Text(AFind[2]);
    Result := [TRuleFix.Create('IndexOf statt Find verwenden',
      [TRuleEdit.Create(TTextRange.Create(Statement.StartPos, Statement.StartPos),
      Format('%s := %s.IndexOf(%s);', [IndexText, Text(AFind[0][0]), Text(AFind[1])]) + LineBreak +
      Indent(Statement)),
      TRuleEdit.Create(TTextRange.Create(AFind.StartPos, AFind.EndPos), IndexText + ' >= 0')])];
  end;

  procedure ReportUses(const AFacts: TStringListFacts);
  var
    Use: TSyntaxNode;
    Name: string;
    Fixes: TArray<TRuleFix>;
  begin
    Name := ListName(AFacts);
    for Use in AFacts.Hits do
    begin
      if Use.Kind = TSyntaxKind.Call then
      begin
        Fixes := SortedFix(AFacts);
        Fixes := Fixes + IndexOfFix(Use);
        AReport.Add(TTextRange.Create(Use.StartPos, Use.EndPos), Format('Find setzt eine sortierte Liste voraus; ' +
          '%s ist nicht sortiert.', [Name]), TRuleConfidence.Medium, Fixes);
      end
      else
      begin
        AReport.Add(TTextRange.Create(Use.StartPos, Use.EndPos), Format('Duplicates wirkt nur bei sortierten ' +
          'Listen; %s ist nicht sortiert.', [Name]), TRuleConfidence.Medium, SortedFix(AFacts));
      end;
    end;
  end;

var
  Index: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Keys := nil;
  Facts := nil;
  Routines := nil;
  CollectRoutines(AContext.Tree.Root);
  Visit(AContext.Tree.Root);
  for Index := 0 to High(Facts) do
  begin
    if (Facts[Index].Creation <> nil) and not Facts[Index].Sorted then
    begin
      ReportUses(Facts[Index]);
    end;
  end;
end;

{ TDictionaryGetWithoutCheckRule }

const
  // Aufrufe, die den Schlüssel prüfen.
  DictionaryKeyChecks: array[0..1] of string = ('ContainsKey', 'TryGetValue');
  // Aufrufe, mit denen die Routine das Dictionary selbst füllt.
  DictionaryFills: array[0..2] of string = ('Add', 'AddOrSetValue', 'TryAdd');

/// <summary>Deklariert die Routine ARoutine AName lokal (Variable, Parameter)? Sonst ist es ein Feld der Klasse
/// oder global.</summary>
function DeclaredLocally(ARoutine: TSyntaxNode; const AName: string): Boolean;
begin
  Result := RoutineDeclares(ARoutine, AName, [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.Parameter]);
end;

/// <summary>Name des Dictionarys: X oder Self.X; sonst ''.</summary>
function DictionaryName(ADict: TSyntaxNode): string;
begin
  Result := '';
  if ADict.Kind = TSyntaxKind.Identifier then
  begin
    Result := ADict.Name;
  end
  else if (ADict.Kind = TSyntaxKind.MemberAccess) and (ADict.ChildCount = 1) and
    (ADict[0].Kind = TSyntaxKind.Identifier) and SameText(ADict[0].Name, 'Self') then
  begin
    Result := ADict.Name;
  end;
end;

/// <summary>TDictionary&lt;K, V&gt; bzw. TObjectDictionary&lt;K, V&gt;? AOpen ist die Stelle von "&lt;".</summary>
function IsDictionaryType(const ATypeName: string; out AOpen: Integer): Boolean;
begin
  AOpen := Pos('<', ATypeName);
  Result := (AOpen > 0) and MatchText(Trim(Copy(ATypeName, 1, AOpen - 1)), ['TDictionary', 'TObjectDictionary',
    'System.Generics.Collections.TDictionary', 'System.Generics.Collections.TObjectDictionary']);
end;

/// <summary>Zweites Typargument von T&lt;K, V&gt; ab dem "&lt;" bei AOpen; '' ohne zweites Argument oder ohne
/// "&gt;".</summary>
function SecondTypeArgument(const ATypeName: string; AOpen: Integer): string;
var
  mIndex, mDepth, mComma: Integer;
begin
  Result := '';
  mDepth := 0;
  mComma := 0;
  mIndex := AOpen + 1;
  while (mIndex <= Length(ATypeName)) and (mDepth >= 0) do
  begin
    case ATypeName[mIndex] of
      '<':
        Inc(mDepth);
      '>':
        Dec(mDepth);
      ',':
        if mDepth = 0 then
        begin
          mComma := mIndex;
        end;
    else
      // Übrige Zeichen bewusst ohne Wirkung.
    end;
    Inc(mIndex);
  end;
  // mIndex steht hinter dem schließenden ">".
  if (mDepth < 0) and (mComma > 0) then
  begin
    Result := Trim(Copy(ATypeName, mComma + 1, mIndex - mComma - 2));
  end;
end;

/// <summary>Legt die Kinder von ANode, die vor AOffset beginnen, rückwärts auf APending.</summary>
procedure PushChildrenBefore(APending: TStack<TSyntaxNode>; ANode: TSyntaxNode; AOffset: Integer);
var
  mIndex: Integer;
begin
  for mIndex := ANode.ChildCount - 1 downto 0 do
  begin
    if ANode[mIndex].StartOffset < AOffset then
    begin
      APending.Push(ANode[mIndex]);
    end;
  end;
end;

function TDictionaryGetWithoutCheckRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dictionary-get-without-check', TRuleSeverity.Hint,
    'Dictionary-Zugriff ohne Prüfung des Schlüssels');
end;

procedure TDictionaryGetWithoutCheckRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Types: TDeclaredTypes;
  LineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Vergleichsschlüssel: Quelltext ohne Leerraum, klein.
  function Key(ANode: TSyntaxNode): string;
  var
    Index: Integer;
    Source: string;
  begin
    Source := Text(ANode);
    Result := '';
    for Index := 1 to Length(Source) do
    begin
      if not CharInSet(Source[Index], [' ', #9, #10, #13]) then
      begin
        Result := Result + Source[Index];
      end;
    end;
    Result := LowerCase(Result);
    if StartsText('self.', Result) then
    begin
      Delete(Result, 1, 5);
    end;
  end;

  // Typtext einer Typdeklaration der Datei (TPreise = TDictionary<string, Double>), sonst ''.
  function AliasOf(ANode: TSyntaxNode; const AName: string): string;
  var
    Pending: TStack<TSyntaxNode>;
    Node, Reference: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1), Vorordnung wie die frühere Rekursion: der erste passende Typ mit Verweis zählt.
    Result := '';
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.TypeDecl) and SameText(Node.Name, AName) then
        begin
          Reference := Node.FindChild(TSyntaxKind.TypeReference);
          if Reference <> nil then
          begin
            Result := Text(Reference);
          end;
          if Result <> '' then
          begin
            Exit;
          end;
          Continue;
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

  // Wertetyp V aus TDictionary<K, V> bzw. TObjectDictionary<K, V>; '' wenn ADict kein Dictionary ist.
  function ValueType(ADict: TSyntaxNode): string;
  var
    mName, mTypeName: string;
    mOpen: Integer;
  begin
    Result := '';
    mName := DictionaryName(ADict);
    if mName = '' then
    begin
      Exit;
    end;
    mTypeName := Types.DeclaredType(mName, ADict.StartPos);
    if (mTypeName <> '') and (Pos('<', mTypeName) = 0) then
    begin
      mTypeName := AliasOf(AContext.Tree.Root, mTypeName);
    end;
    if IsDictionaryType(mTypeName, mOpen) then
    begin
      Result := SecondTypeArgument(mTypeName, mOpen);
    end;
  end;

  // Äußerste Routine: anonyme Methoden (Vergleicher, Aufgaben) sehen die Anweisungen davor.
  function Routine(ANode: TSyntaxNode): TSyntaxNode;
  var
    Parent: TSyntaxNode;
  begin
    Result := AContext.Tree.Root;
    Parent := ANode.Parent;
    while Parent <> nil do
    begin
      if Parent.Kind = TSyntaxKind.RoutineDecl then
      begin
        Result := Parent;
      end;
      Parent := Parent.Parent;
    end;
  end;

  function MentionsKeys(ANode: TSyntaxNode): Boolean;
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
        if (Node.Kind = TSyntaxKind.MemberAccess) and SameText(Node.Name, 'Keys') then
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

  function MentionsAny(ANode: TSyntaxNode; const ANames: TArray<string>): Boolean;
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
        if (Node.Kind = TSyntaxKind.Identifier) and MatchText(Node.Name, ANames) then
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

  // Namen, deren Wert aus Keys eines Dictionarys stammt: for K in D.Keys, Namen := D.Keys.ToArray,
  // for N in Namen, for Pair in D mit K := Pair.Key. Bis zum Fixpunkt, weil Ketten über mehrere
  // Variablen gehen.
  function KeyNames(AScope: TSyntaxNode): TArray<string>;
  var
    Names: TArray<string>;
    Changed: Boolean;

    // Stammt ASource (bei ANode) aus Keys, aus einem schon bekannten Namen oder als for-in aus einem Dictionary?
    function DerivesFromKeys(ANode, ASource: TSyntaxNode): Boolean;
    begin
      Result := MentionsKeys(ASource) or MentionsAny(ASource, Names) or
        ((ANode.Kind = TSyntaxKind.ForInStatement) and (ValueType(ASource) <> ''));
    end;

    procedure Collect(ANode: TSyntaxNode);
    var
      Pending: TStack<TSyntaxNode>;
      Node: TSyntaxNode;
      Index: Integer;
      Source: TSyntaxNode;
      Name: string;
    begin
      // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ANode);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          Name := '';
          Source := nil;
          if (Node.Kind = TSyntaxKind.ForInStatement) and (Node.ChildCount >= 2) then
          begin
            Name := Node.Name;
            Source := Node[Node.ChildCount - 2];
          end
          else if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and
            (Node[0].Kind = TSyntaxKind.Identifier) then
          begin
            Name := Node[0].Name;
            Source := Node[1];
          end;
          if (Source <> nil) and not MatchText(Name, Names) and DerivesFromKeys(Node, Source) then
          begin
            Names := Names + [Name];
            Changed := True;
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
    Names := nil;
    repeat
      Changed := False;
      Collect(AScope);
    until not Changed;
    Result := Names;
  end;

  // Add, AddOrSetValue oder TryAdd auf ADict?
  function IsFillCall(ANode: TSyntaxNode; const ADict: string): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount >= 2) and
      (ANode[0].Kind = TSyntaxKind.MemberAccess) and (ANode[0].ChildCount = 1);
    Result := Result and (Key(ANode[0][0]) = ADict) and MatchText(ANode.Name, DictionaryFills);
  end;

  // ADict[K] := …, aber nicht der geprüfte Zugriff AAccess selbst?
  function IsIndexWrite(ANode, AAccess: TSyntaxNode; const ADict: string): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and (ANode[0] <> AAccess) and
      (ANode[0].Kind = TSyntaxKind.IndexAccess);
    Result := Result and (ANode[0].ChildCount = 2) and (Key(ANode[0][0]) = ADict);
  end;

  // Übergibt der Aufruf ANode das Dictionary ADict als Argument?
  function PassesAsArgument(ANode: TSyntaxNode; const ADict: string): Boolean;
  var
    mIndex: Integer;
  begin
    Result := False;
    mIndex := 1;
    while not Result and (ANode.Kind = TSyntaxKind.Call) and (mIndex < ANode.ChildCount) do
    begin
      Result := Key(ANode[mIndex]) = ADict;
      Inc(mIndex);
    end;
  end;

  // Füllt ANode das Dictionary ADict (Add, AddOrSetValue, Dict[K] := …) oder übergibt es einer Routine, die es
  // füllen kann (ReadProperties(…, Infos), #1109)?
  function Fills(ANode, AAccess: TSyntaxNode; const ADict: string): Boolean;
  begin
    Result := IsFillCall(ANode, ADict) or IsIndexWrite(ANode, AAccess, ADict) or PassesAsArgument(ANode, ADict);
  end;

  // Füllt ein Knoten in ALoop hinter AAccess das Dictionary ADict?
  function FillsAfter(ALoop, AAccess: TSyntaxNode; const ADict: string): Boolean;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ALoop);
      while not Result and (mPending.Count > 0) do
      begin
        mNode := mPending.Pop;
        Result := (mNode.StartOffset > AAccess.EndOffset) and Fills(mNode, AAccess, ADict);
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  // Füllt eine Schleife um AAccess ADict, auch hinter dem Zugriff? Dann füllt ein früherer Durchlauf
  // (die Kinder vor dem Knoten, auch über eine innere for-Schleife, #1109).
  function FilledInLoop(AScope, AAccess: TSyntaxNode; const ADict: string): Boolean;
  var
    mLoop: TSyntaxNode;
  begin
    Result := False;
    mLoop := AAccess.Parent;
    while not Result and (mLoop <> nil) and (mLoop <> AScope) do
    begin
      Result := (mLoop.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.ForStatement,
        TSyntaxKind.ForInStatement]) and FillsAfter(mLoop, AAccess, ADict);
      mLoop := mLoop.Parent;
    end;
  end;

  // Ein Feld (oder eine globale Variable), das die Unit an anderer Stelle füllt: Welche Schlüssel drin sind,
  // sichert die Klasse über ihre Methoden hinweg (FOrder und FPending im Gleichschritt, Tabelle je Control beim
  // Aufbau); das sieht die Prüfung einer einzelnen Routine nicht (#1109).
  function FieldFilledInUnit(AScope, AAccess, ADictNode: TSyntaxNode; const ADict: string): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Result := False;
    if (ADictNode.Kind = TSyntaxKind.Identifier) and DeclaredLocally(AScope, ADictNode.Name) then
    begin
      Exit;
    end;
    if not (ADictNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
    begin
      Exit;
    end;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(AContext.Tree.Root);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Fills(Node, AAccess, ADict) then
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

  // ContainsKey oder TryGetValue auf ADict mit dem Schlüssel AKey?
  function ChecksKey(ANode: TSyntaxNode; const ADict, AKey: string): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount >= 2) and
      (ANode[0].Kind = TSyntaxKind.MemberAccess) and (ANode[0].ChildCount = 1);
    Result := Result and (Key(ANode[0][0]) = ADict) and MatchText(ANode.Name, DictionaryKeyChecks) and
      (Key(ANode[1]) = AKey);
  end;

  // ContainsKey/TryGetValue mit demselben Schlüssel oder Add, AddOrSetValue, Dict[K] := … vor AAccess.
  function Checked(AScope, AAccess: TSyntaxNode; const ADict, AKey: string): Boolean;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
  begin
    Result := FilledInLoop(AScope, AAccess, ADict);
    // Iterativ (Bericht M1); Kinder ab dem Ende des Zugriffs bleiben wie zuvor aus.
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AScope);
      while not Result and (mPending.Count > 0) do
      begin
        mNode := mPending.Pop;
        Result := (mNode.StartOffset < AAccess.StartOffset) and (ChecksKey(mNode, ADict, AKey) or
          Fills(mNode, AAccess, ADict));
        PushChildrenBefore(mPending, mNode, AAccess.EndOffset);
      end;
    finally
      mPending.Free;
    end;
  end;

  function DefaultValue(const AType: string): string;
  begin
    if TDeclaredTypes.IsInt32(AType) or TDeclaredTypes.IsInt64(AType) or TDeclaredTypes.IsFloat(AType) or
      SameText(AType, 'Currency') then
    begin
      Result := '0';
    end
    else if MatchText(AType, ['string', 'UnicodeString', 'AnsiString', 'WideString']) then
    begin
      Result := '''''';
    end
    else if SameText(AType, 'Boolean') then
    begin
      Result := 'False';
    end
    else
    begin
      Result := 'Default(' + AType + ')';
    end;
  end;

  // X := Dict[K]; für sich, X eine Variable vom Wertetyp: if not Dict.TryGetValue(K, X) then X := 0.
  function Fixes(AAccess, ADictNode: TSyntaxNode; const AValueType: string): TArray<TRuleFix>;
  var
    Statement, Target: TSyntaxNode;
    Indent: string;
  begin
    Result := nil;
    Statement := AAccess.Parent;
    if not IsListedAssignment(Statement, AAccess) then
    begin
      Exit;
    end;
    Target := Statement[0];
    if (Target.Kind <> TSyntaxKind.Identifier) or
      not SameText(Types.DeclaredType(Target.Name, Target.StartPos), AValueType) then
    begin
      Exit;
    end;
    Indent := StringOfChar(' ', Statement.StartPos.Character);
    Result := [TRuleFix.Create('In TryGetValue umschreiben', [TRuleEdit.Create(TTextRange.Create(Statement.StartPos,
      Statement.EndPos), 'if not ' + Text(ADictNode) + '.TryGetValue(' + Text(AAccess[AAccess.ChildCount - 1]) +
      ', ' + Target.Name + ') then' + LineBreak + Indent + '  ' + Target.Name + ' := ' + DefaultValue(AValueType))])];
  end;

  procedure CheckAccess(AAccess: TSyntaxNode);
  var
    DictNode, Scope: TSyntaxNode;
    Value: string;
  begin
    if AAccess.ChildCount <> 2 then
    begin
      Exit;
    end;
    DictNode := AAccess[0];
    // Dict.Items[K]
    if (DictNode.Kind = TSyntaxKind.MemberAccess) and SameText(DictNode.Name, 'Items') and (DictNode.ChildCount = 1) then
    begin
      DictNode := DictNode[0];
    end;
    // Schreiben: Dict[K] := V legt an bzw. überschreibt.
    if (AAccess.Parent <> nil) and (AAccess.Parent.Kind = TSyntaxKind.AssignStatement) and
      (AAccess.Parent[0] = AAccess) then
    begin
      Exit;
    end;
    Value := ValueType(DictNode);
    if Value = '' then
    begin
      Exit;
    end;
    Scope := Routine(AAccess);
    if Checked(Scope, AAccess, Key(DictNode), Key(AAccess[1])) or MentionsAny(AAccess[1], KeyNames(Scope)) or
      FieldFilledInUnit(Scope, AAccess, DictNode, Key(DictNode)) then
    begin
      Exit;
    end;
    AReport.Add(TTextRange.Create(AAccess.StartPos, AAccess.EndPos), 'Schlüssel wird nicht geprüft; fehlt er, löst ' +
      'der Zugriff EListError aus.', TRuleConfidence.Medium, Fixes(AAccess, DictNode, Value));
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
        if Node.Kind = TSyntaxKind.IndexAccess then
        begin
          CheckAccess(Node);
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
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root);
  finally
    Types.Free;
  end;
end;

{ TDelimitedTextWithoutStrictRule }

function TDelimitedTextWithoutStrictRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('delimited-text-without-strict', TRuleSeverity.Warning,
    'DelimitedText ohne StrictDelimiter');
end;

procedure TDelimitedTextWithoutStrictRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Code: TArray<Integer>;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier) and SameText(Token(APosition).Text, AName);
  end;

  // Liste vor ".Eigenschaft" bei APosition (X bzw. Self.X); '' bei anderen Ausdrücken.
  function ListBefore(APosition: Integer): string;
  begin
    Result := '';
    if not IsSym(APosition - 1, '.') or (APosition < 2) or
      (Token(APosition - 2).Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit;
    end;
    if IsSym(APosition - 3, '.') and not IsName(APosition - 4, 'Self') then
    begin
      Exit;
    end;
    Result := Token(APosition - 2).Text;
  end;

  // Wird in [AFrom, ATo) "Liste.AProperty := …" gesetzt? AValue liefert das erste Token des Werts.
  function Assigns(AFrom, ATo: Integer; const AList, AProperty: string; out AValue: string): Boolean;
  var
    Position: Integer;
  begin
    for Position := 0 to High(Code) - 2 do
    begin
      if (Token(Position).Offset >= AFrom) and (Token(Position).Offset < ATo) and
        IsName(Position, AProperty) and IsSym(Position + 1, ':=') and SameText(ListBefore(Position), AList) then
      begin
        AValue := Token(Position + 2).Text;
        Exit(True);
      end;
    end;
    AValue := '';
    Result := False;
  end;

  // Erstes Kind von ANode, das AOffset enthält; nil ohne.
  function ChildAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    Index: Integer;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      if (AOffset >= ANode[Index].StartOffset) and (AOffset < ANode[Index].EndOffset) then
      begin
        Exit(ANode[Index]);
      end;
    end;
    Result := nil;
  end;

  function RoutineAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    Node: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): je Ebene in das Kind, das AOffset enthält.
    Result := nil;
    Node := ChildAt(ANode, AOffset);
    while Node <> nil do
    begin
      if Node.Kind = TSyntaxKind.RoutineDecl then
      begin
        Result := Node;
      end;
      Node := ChildAt(Node, AOffset);
    end;
  end;

  // Innerste Zuweisung unter ANode, die AOffset enthält.
  function StatementAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    Node: TSyntaxNode;
  begin
    // Iterativ (Bericht M1) wie RoutineAt.
    Result := nil;
    Node := ChildAt(ANode, AOffset);
    while Node <> nil do
    begin
      if Node.Kind = TSyntaxKind.AssignStatement then
      begin
        Result := Node;
      end;
      Node := ChildAt(Node, AOffset);
    end;
  end;

  procedure CheckAt(APosition: Integer);
  var
    List, Value, Prefix: string;
    Routine, Statement: TSyntaxNode;
    From, Till: Integer;
    Fixes: TArray<TRuleFix>;
  begin
    List := ListBefore(APosition);
    Routine := RoutineAt(AContext.Tree.Root, Token(APosition).Offset);
    if (List = '') or (Routine = nil) then
    begin
      Exit;
    end;
    // Lokal: die Routine; Feld: die ganze Unit (StrictDelimiter oft im Konstruktor).
    From := Routine.StartOffset;
    Till := Routine.EndOffset;
    if not DeclaredLocally(Routine, List) then
    begin
      From := 0;
      Till := MaxInt;
    end;
    // Ohne eigenen Delimiter bleibt die Regel still; StrictDelimiter := False ist bewusst.
    if not Assigns(Routine.StartOffset, Routine.EndOffset, List, 'Delimiter', Value) or
      Assigns(From, Till, List, 'StrictDelimiter', Value) then
    begin
      Exit;
    end;
    Fixes := nil;
    Statement := StatementAt(Routine, Token(APosition).Offset);
    if (Statement <> nil) and (Statement.Parent <> nil) and (Statement.Parent.Kind in [TSyntaxKind.Block,
      TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement]) then
    begin
      Prefix := '';
      if IsSym(APosition - 3, '.') then
      begin
        Prefix := 'Self.';
      end;
      Fixes := [TRuleFix.Create('StrictDelimiter := True; einfügen',
        [TRoutineBody.InsertBefore(AContext.Text, Statement, Prefix + List + '.StrictDelimiter := True;')])];
    end;
    AReport.Add(TTextRange.Create(Token(APosition).StartPos, Token(APosition).EndPos),
      'Ohne StrictDelimiter trennt DelimitedText auch an Leerzeichen: ''Max Muster'' wird zu zwei Einträgen.',
      Fixes);
  end;

var
  Index, Position: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'DelimitedText') then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
  begin
    if not IsTrivia(Tokens[Index]) then
    begin
      Code := Code + [Index];
    end;
  end;
  for Position := 0 to High(Code) - 1 do
  begin
    if IsName(Position, 'DelimitedText') and IsSym(Position + 1, ':=') then
    begin
      CheckAt(Position);
    end;
  end;
end;

end.
