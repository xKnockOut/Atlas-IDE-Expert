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
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Tokens,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TRtlTypePatternsCollectionsText = (UnsortedTitle, AddSorted, UseIndexOf, FindUnsorted, DuplicatesUnsorted,
    DictionaryTitle, ToTryGetValue, KeyNotChecked, DelimiterTitle, InsertStrict, Delimiter);

const
  cTexts: array[TRtlTypePatternsCollectionsText] of TAtlasText = (
    (De: 'Find oder Duplicates auf einer unsortierten TStringList';
     En: 'Find or Duplicates on an unsorted TStringList'),
    (De: 'Sorted := True nach dem Erzeugen ergänzen'; En: 'Add Sorted := True after creation'),
    (De: 'IndexOf statt Find verwenden'; En: 'Use IndexOf instead of Find'),
    (De: 'Find setzt eine sortierte Liste voraus; %s ist nicht sortiert.';
     En: 'Find requires a sorted list; %s is not sorted.'),
    (De: 'Duplicates wirkt nur bei sortierten Listen; %s ist nicht sortiert.';
     En: 'Duplicates works only on sorted lists; %s is not sorted.'),
    (De: 'Dictionary-Zugriff ohne Prüfung des Schlüssels'; En: 'Dictionary access without checking the key'),
    (De: 'In TryGetValue umschreiben'; En: 'Rewrite as TryGetValue'),
    (De: 'Schlüssel wird nicht geprüft; fehlt er, löst der Zugriff EListError aus.';
     En: 'Key is not checked; if it is missing, the access raises EListError.'),
    (De: 'DelimitedText ohne StrictDelimiter'; En: 'DelimitedText without StrictDelimiter'),
    (De: 'StrictDelimiter := True; einfügen'; En: 'Insert StrictDelimiter := True;'),
    (De: 'Ohne StrictDelimiter trennt DelimitedText auch an Leerzeichen: ''Max Muster'' wird zu zwei Einträgen.';
     En: 'Without StrictDelimiter, DelimitedText also splits at spaces: ''John Doe'' becomes two entries.'));

{$SCOPEDENUMS OFF}

{ TStringListUnsortedRule }

const
  cStringListClasses: array[0..1] of string = ('TStringList', 'THashedStringList');
  // Aufrufe, die eine Liste nicht weitergeben: sie bleibt in der Hand der Routine.
  cNonEscapingCalls: array[0..2] of string = ('FreeAndNil', 'Assigned', 'Free');
  // Methoden, die mit Sorted := True eine Ausnahme auslösen: dann keine Korrektur mit Sorted.
  cUnsortedOnlyMethods: array[0..2] of string = ('Insert', 'Move', 'Exchange');

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
    cTexts[TRtlTypePatternsCollectionsText.UnsortedTitle].Text);
end;

procedure TStringListUnsortedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mKeys: TArray<string>;
  mFacts: TArray<TStringListFacts>;
  mRoutines: TArray<TSyntaxNode>;
  mLineBreak: string;

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
    mIndex: Integer;
    mRoutine: TSyntaxNode;
  begin
    // Routines ist nach Start sortiert; die innerste umgebende Routine liegt hinten.
    for mIndex := High(mRoutines) downto 0 do
    begin
      mRoutine := mRoutines[mIndex];
      if (mRoutine.StartOffset <= ANode.StartOffset) and (mRoutine.EndOffset >= ANode.EndOffset) and
        RoutineDeclares(mRoutine, AName, [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar]) then
      begin
        Exit(IntToStr(mRoutine.StartOffset) + ':' + LowerCase(AName));
      end;
    end;
    Result := 'F:' + LowerCase(AName);
  end;

  function FactIndex(const AKey: string): Integer;
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to High(mKeys) do
    begin
      if mKeys[mIndex] = AKey then
      begin
        Exit(mIndex);
      end;
    end;
    Result := Length(mKeys);
    SetLength(mKeys, Result + 1);
    SetLength(mFacts, Result + 1);
    mKeys[Result] := AKey;
    mFacts[Result].Creation := nil;
    mFacts[Result].Sorted := False;
    mFacts[Result].UnsortedOnly := False;
    mFacts[Result].Hits := nil;
  end;

  // Index der Liste, auf die ANode (X oder Self.X) zeigt; -1 ohne Namen.
  function ListOf(ANode: TSyntaxNode): Integer;
  var
    mName: string;
  begin
    mName := BaseName(ANode);
    if mName = '' then
    begin
      Exit(-1);
    end;
    Result := FactIndex(KeyOf(ANode, mName));
  end;

  function IsFalse(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'False');
  end;

  // TStringList.Create(...); ASorted, wenn Create(Duplicates, Sorted, CaseSensitive) sortiert.
  function IsCreation(AValue: TSyntaxNode; out ASorted: Boolean): Boolean;
  var
    mCallee: TSyntaxNode;
  begin
    ASorted := False;
    mCallee := AValue;
    if (AValue <> nil) and (AValue.Kind = TSyntaxKind.Call) and (AValue.ChildCount > 0) then
    begin
      mCallee := AValue[0];
    end;
    Result := (mCallee <> nil) and (mCallee.Kind = TSyntaxKind.MemberAccess) and SameText(mCallee.Name, 'Create') and
      (mCallee.ChildCount = 1) and (mCallee[0].Kind = TSyntaxKind.Identifier) and
      MatchText(mCallee[0].Name, cStringListClasses);
    if Result and (AValue.Kind = TSyntaxKind.Call) and (AValue.ChildCount = 4) then
    begin
      ASorted := not IsFalse(AValue[2]);
    end;
  end;

  procedure NoteCreation(AStatement: TSyntaxNode; AList: Integer; AValue: TSyntaxNode);
  var
    mConstructorSorted: Boolean;
  begin
    if (AList < 0) or not IsCreation(AValue, mConstructorSorted) then
    begin
      Exit;
    end;
    if mFacts[AList].Creation = nil then
    begin
      mFacts[AList].Creation := AStatement;
    end;
    if mConstructorSorted then
    begin
      mFacts[AList].Sorted := True;
    end;
  end;

  // Die Liste wird weitergegeben: was der Empfänger damit macht, ist unbekannt.
  procedure NoteEscape(ANode: TSyntaxNode);
  var
    mList: Integer;
  begin
    mList := ListOf(ANode);
    if mList >= 0 then
    begin
      mFacts[mList].Sorted := True;
    end;
  end;

  procedure VisitAssign(AStatement: TSyntaxNode);
  var
    mTarget, mValue: TSyntaxNode;
    mList: Integer;
  begin
    mTarget := AStatement[0];
    mValue := AStatement[1];
    NoteCreation(AStatement, ListOf(mTarget), mValue);
    NoteEscape(mValue);
    if (mTarget.Kind <> TSyntaxKind.MemberAccess) or (mTarget.ChildCount <> 1) then
    begin
      Exit;
    end;
    mList := ListOf(mTarget[0]);
    if mList < 0 then
    begin
      Exit;
    end;
    if SameText(mTarget.Name, 'Sorted') and not IsFalse(mValue) then
    begin
      mFacts[mList].Sorted := True;
    end
    else if SameText(mTarget.Name, 'Duplicates') and (mValue.Kind = TSyntaxKind.Identifier) and
      MatchText(mValue.Name, ['dupIgnore', 'dupError']) then
    begin
      mFacts[mList].Hits := mFacts[mList].Hits + [AStatement];
    end;
  end;

  // X.Methode oder X.Methode(...): Sortieren, Find und Methoden, die nur unsortiert gehen.
  procedure VisitMember(AMember, ACall: TSyntaxNode);
  var
    mList: Integer;
  begin
    if AMember.ChildCount <> 1 then
    begin
      Exit;
    end;
    mList := ListOf(AMember[0]);
    if mList < 0 then
    begin
      Exit;
    end;
    if SameText(AMember.Name, 'Sort') or SameText(AMember.Name, 'CustomSort') then
    begin
      mFacts[mList].Sorted := True;
    end;
    if MatchText(AMember.Name, cUnsortedOnlyMethods) then
    begin
      mFacts[mList].UnsortedOnly := True;
    end;
    if SameText(AMember.Name, 'Find') and (ACall <> nil) and (ACall.ChildCount = 3) then
    begin
      mFacts[mList].Hits := mFacts[mList].Hits + [ACall];
    end;
  end;

  procedure VisitInlineVar(ANode: TSyntaxNode);
  var
    mValue: TSyntaxNode;
  begin
    if (ANode.ChildCount > 0) and (Pos(',', ANode.Name) = 0) then
    begin
      mValue := ANode[ANode.ChildCount - 1];
      NoteEscape(mValue);
      NoteCreation(ANode, FactIndex(KeyOf(ANode, Trim(ANode.Name))), mValue);
    end;
  end;

  procedure VisitCall(ANode: TSyntaxNode);
  var
    mIndex: Integer;
  begin
    if (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.MemberAccess) then
    begin
      VisitMember(ANode[0], ANode);
    end;
    // Als Argument übergeben: der Aufgerufene kann sortieren.
    if not MatchText(ANode.Name, cNonEscapingCalls) then
    begin
      for mIndex := 1 to ANode.ChildCount - 1 do
      begin
        NoteEscape(ANode[mIndex]);
      end;
    end;
  end;

  // with X do Sorted := True ist nicht nachvollziehbar: als sortiert betrachten.
  procedure VisitWith(ANode: TSyntaxNode);
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to ANode.ChildCount - 2 do
    begin
      NoteEscape(ANode[mIndex]);
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
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        VisitNode(mNode);
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  procedure CollectRoutines(ANode: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion (nach Start sortiert).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.RoutineDecl then
        begin
          mRoutines := mRoutines + [mNode];
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
    mCreation: TSyntaxNode;
  begin
    Result := nil;
    mCreation := AFacts.Creation;
    if AFacts.UnsortedOnly or (mCreation.Parent = nil) or (mCreation.Parent.Kind <> TSyntaxKind.Block) then
    begin
      Exit;
    end;
    Result := [TRuleFix.Create(cTexts[TRtlTypePatternsCollectionsText.AddSorted].Text,
      [TRuleEdit.Create(TTextRange.Create(mCreation.EndPos, mCreation.EndPos),
      ';' + mLineBreak + Indent(mCreation) + ListName(AFacts) + '.Sorted := True')])];
  end;

  // if X.Find(S, I) then: vorher I := X.IndexOf(S), im if I >= 0.
  function IndexOfFix(AFind: TSyntaxNode): TArray<TRuleFix>;
  var
    mStatement: TSyntaxNode;
    mIndexText: string;
  begin
    Result := nil;
    mStatement := AFind.Parent;
    if not IsIfInBlock(mStatement, AFind) then
    begin
      Exit;
    end;
    mIndexText := Text(AFind[2]);
    Result := [TRuleFix.Create(cTexts[TRtlTypePatternsCollectionsText.UseIndexOf].Text,
      [TRuleEdit.Create(TTextRange.Create(mStatement.StartPos, mStatement.StartPos),
      Format('%s := %s.IndexOf(%s);', [mIndexText, Text(AFind[0][0]), Text(AFind[1])]) + mLineBreak +
      Indent(mStatement)),
      TRuleEdit.Create(TTextRange.Create(AFind.StartPos, AFind.EndPos), mIndexText + ' >= 0')])];
  end;

  procedure ReportUses(const AFacts: TStringListFacts);
  var
    mUse: TSyntaxNode;
    mName: string;
    mFixes: TArray<TRuleFix>;
  begin
    mName := ListName(AFacts);
    for mUse in AFacts.Hits do
    begin
      if mUse.Kind = TSyntaxKind.Call then
      begin
        mFixes := SortedFix(AFacts);
        mFixes := mFixes + IndexOfFix(mUse);
        AReport.Add(TTextRange.Create(mUse.StartPos, mUse.EndPos),
          cTexts[TRtlTypePatternsCollectionsText.FindUnsorted].Fmt([mName]), TRuleConfidence.Medium, mFixes);
      end
      else
      begin
        AReport.Add(TTextRange.Create(mUse.StartPos, mUse.EndPos),
          cTexts[TRtlTypePatternsCollectionsText.DuplicatesUnsorted].Fmt([mName]), TRuleConfidence.Medium,
          SortedFix(AFacts));
      end;
    end;
  end;

var
  mIndex: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mLineBreak := TTextLines.LineBreakOf(AContext.Text);
  mKeys := nil;
  mFacts := nil;
  mRoutines := nil;
  CollectRoutines(AContext.Tree.Root);
  Visit(AContext.Tree.Root);
  for mIndex := 0 to High(mFacts) do
  begin
    if (mFacts[mIndex].Creation <> nil) and not mFacts[mIndex].Sorted then
    begin
      ReportUses(mFacts[mIndex]);
    end;
  end;
end;

{ TDictionaryGetWithoutCheckRule }

const
  // Aufrufe, die den Schlüssel prüfen.
  cDictionaryKeyChecks: array[0..1] of string = ('ContainsKey', 'TryGetValue');
  // Aufrufe, mit denen die Routine das Dictionary selbst füllt.
  cDictionaryFills: array[0..2] of string = ('Add', 'AddOrSetValue', 'TryAdd');

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
    cTexts[TRtlTypePatternsCollectionsText.DictionaryTitle].Text);
end;

procedure TDictionaryGetWithoutCheckRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTypes: TDeclaredTypes;
  mLineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Vergleichsschlüssel: Quelltext ohne Leerraum, klein.
  function Key(ANode: TSyntaxNode): string;
  var
    mIndex: Integer;
    mSource: string;
  begin
    mSource := Text(ANode);
    Result := '';
    for mIndex := 1 to Length(mSource) do
    begin
      if not CharInSet(mSource[mIndex], [' ', #9, #10, #13]) then
      begin
        Result := Result + mSource[mIndex];
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
    mPending: TStack<TSyntaxNode>;
    mNode, mReference: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1), Vorordnung wie die frühere Rekursion: der erste passende Typ mit Verweis zählt.
    Result := '';
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.TypeDecl) and SameText(mNode.Name, AName) then
        begin
          mReference := mNode.FindChild(TSyntaxKind.TypeReference);
          if mReference <> nil then
          begin
            Result := Text(mReference);
          end;
          if Result <> '' then
          begin
            Exit;
          end;
          Continue;
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
    mTypeName := mTypes.DeclaredType(mName, ADict.StartPos);
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
    mParent: TSyntaxNode;
  begin
    Result := AContext.Tree.Root;
    mParent := ANode.Parent;
    while mParent <> nil do
    begin
      if mParent.Kind = TSyntaxKind.RoutineDecl then
      begin
        Result := mParent;
      end;
      mParent := mParent.Parent;
    end;
  end;

  function MentionsKeys(ANode: TSyntaxNode): Boolean;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.MemberAccess) and SameText(mNode.Name, 'Keys') then
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

  function MentionsAny(ANode: TSyntaxNode; const ANames: TArray<string>): Boolean;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.Identifier) and MatchText(mNode.Name, ANames) then
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

  // Namen, deren Wert aus Keys eines Dictionarys stammt: for K in D.Keys, Namen := D.Keys.ToArray,
  // for N in Namen, for Pair in D mit K := Pair.Key. Bis zum Fixpunkt, weil Ketten über mehrere
  // Variablen gehen.
  function KeyNames(AScope: TSyntaxNode): TArray<string>;
  var
    mNames: TArray<string>;
    mChanged: Boolean;

    // Stammt ASource (bei ANode) aus Keys, aus einem schon bekannten Namen oder als for-in aus einem Dictionary?
    function DerivesFromKeys(ANode, ASource: TSyntaxNode): Boolean;
    begin
      Result := MentionsKeys(ASource) or MentionsAny(ASource, mNames) or
        ((ANode.Kind = TSyntaxKind.ForInStatement) and (ValueType(ASource) <> ''));
    end;

    procedure Collect(ANode: TSyntaxNode);
    var
      mPending: TStack<TSyntaxNode>;
      mNode: TSyntaxNode;
      mIndex: Integer;
      mSource: TSyntaxNode;
      mName: string;
    begin
      // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
      mPending := TStack<TSyntaxNode>.Create;
      try
        mPending.Push(ANode);
        while mPending.Count > 0 do
        begin
          mNode := mPending.Pop;
          mName := '';
          mSource := nil;
          if (mNode.Kind = TSyntaxKind.ForInStatement) and (mNode.ChildCount >= 2) then
          begin
            mName := mNode.Name;
            mSource := mNode[mNode.ChildCount - 2];
          end
          else if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode.ChildCount = 2) and
            (mNode[0].Kind = TSyntaxKind.Identifier) then
          begin
            mName := mNode[0].Name;
            mSource := mNode[1];
          end;
          if (mSource <> nil) and not MatchText(mName, mNames) and DerivesFromKeys(mNode, mSource) then
          begin
            mNames := mNames + [mName];
            mChanged := True;
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

  begin
    mNames := nil;
    repeat
      mChanged := False;
      Collect(AScope);
    until not mChanged;
    Result := mNames;
  end;

  // Add, AddOrSetValue oder TryAdd auf ADict?
  function IsFillCall(ANode: TSyntaxNode; const ADict: string): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount >= 2) and
      (ANode[0].Kind = TSyntaxKind.MemberAccess) and (ANode[0].ChildCount = 1);
    Result := Result and (Key(ANode[0][0]) = ADict) and MatchText(ANode.Name, cDictionaryFills);
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
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
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
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AContext.Tree.Root);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if Fills(mNode, AAccess, ADict) then
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

  // ContainsKey oder TryGetValue auf ADict mit dem Schlüssel AKey?
  function ChecksKey(ANode: TSyntaxNode; const ADict, AKey: string): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount >= 2) and
      (ANode[0].Kind = TSyntaxKind.MemberAccess) and (ANode[0].ChildCount = 1);
    Result := Result and (Key(ANode[0][0]) = ADict) and MatchText(ANode.Name, cDictionaryKeyChecks) and
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
    mStatement, mTarget: TSyntaxNode;
    mIndent: string;
  begin
    Result := nil;
    mStatement := AAccess.Parent;
    if not IsListedAssignment(mStatement, AAccess) then
    begin
      Exit;
    end;
    mTarget := mStatement[0];
    if (mTarget.Kind <> TSyntaxKind.Identifier) or
      not SameText(mTypes.DeclaredType(mTarget.Name, mTarget.StartPos), AValueType) then
    begin
      Exit;
    end;
    mIndent := StringOfChar(' ', mStatement.StartPos.Character);
    Result := [TRuleFix.Create(cTexts[TRtlTypePatternsCollectionsText.ToTryGetValue].Text,
      [TRuleEdit.Create(TTextRange.Create(mStatement.StartPos,
      mStatement.EndPos), 'if not ' + Text(ADictNode) + '.TryGetValue(' + Text(AAccess[AAccess.ChildCount - 1]) +
      ', ' + mTarget.Name + ') then' + mLineBreak + mIndent + '  ' + mTarget.Name + ' := ' + DefaultValue(AValueType))])];
  end;

  procedure CheckAccess(AAccess: TSyntaxNode);
  var
    mDictNode, mScope: TSyntaxNode;
    mValue: string;
  begin
    if AAccess.ChildCount <> 2 then
    begin
      Exit;
    end;
    mDictNode := AAccess[0];
    // Dict.Items[K]
    if (mDictNode.Kind = TSyntaxKind.MemberAccess) and SameText(mDictNode.Name, 'Items') and (mDictNode.ChildCount = 1) then
    begin
      mDictNode := mDictNode[0];
    end;
    // Schreiben: Dict[K] := V legt an bzw. überschreibt.
    if (AAccess.Parent <> nil) and (AAccess.Parent.Kind = TSyntaxKind.AssignStatement) and
      (AAccess.Parent[0] = AAccess) then
    begin
      Exit;
    end;
    mValue := ValueType(mDictNode);
    if mValue = '' then
    begin
      Exit;
    end;
    mScope := Routine(AAccess);
    if Checked(mScope, AAccess, Key(mDictNode), Key(AAccess[1])) or MentionsAny(AAccess[1], KeyNames(mScope)) or
      FieldFilledInUnit(mScope, AAccess, mDictNode, Key(mDictNode)) then
    begin
      Exit;
    end;
    AReport.Add(TTextRange.Create(AAccess.StartPos, AAccess.EndPos),
      cTexts[TRtlTypePatternsCollectionsText.KeyNotChecked].Text, TRuleConfidence.Medium, Fixes(AAccess, mDictNode,
      mValue));
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.IndexAccess then
        begin
          CheckAccess(mNode);
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

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mLineBreak := TTextLines.LineBreakOf(AContext.Text);
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root);
  finally
    mTypes.Free;
  end;
end;

{ TDelimitedTextWithoutStrictRule }

function TDelimitedTextWithoutStrictRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('delimited-text-without-strict', TRuleSeverity.Warning,
    cTexts[TRtlTypePatternsCollectionsText.DelimiterTitle].Text);
end;

procedure TDelimitedTextWithoutStrictRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mCode: TArray<Integer>;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := mTokens[mCode[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and
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
    mPosition: Integer;
  begin
    for mPosition := 0 to High(mCode) - 2 do
    begin
      if (Token(mPosition).Offset >= AFrom) and (Token(mPosition).Offset < ATo) and
        IsName(mPosition, AProperty) and IsSym(mPosition + 1, ':=') and SameText(ListBefore(mPosition), AList) then
      begin
        AValue := Token(mPosition + 2).Text;
        Exit(True);
      end;
    end;
    AValue := '';
    Result := False;
  end;

  // Erstes Kind von ANode, das AOffset enthält; nil ohne.
  function ChildAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      if (AOffset >= ANode[mIndex].StartOffset) and (AOffset < ANode[mIndex].EndOffset) then
      begin
        Exit(ANode[mIndex]);
      end;
    end;
    Result := nil;
  end;

  function RoutineAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    mNode: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): je Ebene in das Kind, das AOffset enthält.
    Result := nil;
    mNode := ChildAt(ANode, AOffset);
    while mNode <> nil do
    begin
      if mNode.Kind = TSyntaxKind.RoutineDecl then
      begin
        Result := mNode;
      end;
      mNode := ChildAt(mNode, AOffset);
    end;
  end;

  // Innerste Zuweisung unter ANode, die AOffset enthält.
  function StatementAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    mNode: TSyntaxNode;
  begin
    // Iterativ (Bericht M1) wie RoutineAt.
    Result := nil;
    mNode := ChildAt(ANode, AOffset);
    while mNode <> nil do
    begin
      if mNode.Kind = TSyntaxKind.AssignStatement then
      begin
        Result := mNode;
      end;
      mNode := ChildAt(mNode, AOffset);
    end;
  end;

  procedure CheckAt(APosition: Integer);
  var
    mList, mValue, mPrefix: string;
    mRoutine, mStatement: TSyntaxNode;
    mFrom, mTill: Integer;
    mFixes: TArray<TRuleFix>;
  begin
    mList := ListBefore(APosition);
    mRoutine := RoutineAt(AContext.Tree.Root, Token(APosition).Offset);
    if (mList = '') or (mRoutine = nil) then
    begin
      Exit;
    end;
    // Lokal: die Routine; Feld: die ganze Unit (StrictDelimiter oft im Konstruktor).
    mFrom := mRoutine.StartOffset;
    mTill := mRoutine.EndOffset;
    if not DeclaredLocally(mRoutine, mList) then
    begin
      mFrom := 0;
      mTill := MaxInt;
    end;
    // Ohne eigenen Delimiter bleibt die Regel still; StrictDelimiter := False ist bewusst.
    if not Assigns(mRoutine.StartOffset, mRoutine.EndOffset, mList, 'Delimiter', mValue) or
      Assigns(mFrom, mTill, mList, 'StrictDelimiter', mValue) then
    begin
      Exit;
    end;
    mFixes := nil;
    mStatement := StatementAt(mRoutine, Token(APosition).Offset);
    if (mStatement <> nil) and (mStatement.Parent <> nil) and (mStatement.Parent.Kind in [TSyntaxKind.Block,
      TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement]) then
    begin
      mPrefix := '';
      if IsSym(APosition - 3, '.') then
      begin
        mPrefix := 'Self.';
      end;
      mFixes := [TRuleFix.Create(cTexts[TRtlTypePatternsCollectionsText.InsertStrict].Text,
        [TRoutineBody.InsertBefore(AContext.Text, mStatement, mPrefix + mList + '.StrictDelimiter := True;')])];
    end;
    AReport.Add(TTextRange.Create(Token(APosition).StartPos, Token(APosition).EndPos),
      cTexts[TRtlTypePatternsCollectionsText.Delimiter].Text,
      mFixes);
  end;

var
  mIndex, mPosition: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'DelimitedText') then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mCode := nil;
  for mIndex := 0 to High(mTokens) do
  begin
    if not IsTrivia(mTokens[mIndex]) then
    begin
      mCode := mCode + [mIndex];
    end;
  end;
  for mPosition := 0 to High(mCode) - 1 do
  begin
    if IsName(mPosition, 'DelimitedText') and IsSym(mPosition + 1, ':=') then
    begin
      CheckAt(mPosition);
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.RtlTypePatterns.Collections', cTexts);

end.
