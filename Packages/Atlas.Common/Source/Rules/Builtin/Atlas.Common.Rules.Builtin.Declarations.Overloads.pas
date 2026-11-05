unit Atlas.Common.Rules.Builtin.Declarations.Overloads;

// Regel overload-directive-missing aus Atlas.Common.Rules.Builtin.Declarations (#987): gleichnamige Routinen
// bzw. Methoden eines Bereichs ohne overload (wie E2254, E2267) oder mit gleichen Parametern (E2252, E2301);
// Korrektur: overload; anhängen.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TOverloadDirectiveMissingRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  OverloadDirectiveMissingRuleId = 'overload-directive-missing';

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Pascal.RoutineSignatures,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Rules.Builtin.Declarations.Shared,
  Atlas.Text.Lines;

{ TOverloadDirectiveMissingRule }

function TOverloadDirectiveMissingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OverloadDirectiveMissingRuleId, TRuleSeverity.Error,
    'Überladung ohne overload oder mit gleicher Signatur');
end;

type
  /// <summary>Eine Deklaration in einem Gültigkeitsbereich für overload-directive-missing (#987).</summary>
  TOverloadEntry = record
    Header: TSyntaxNode;
    Name: string;
    HasOverload: Boolean;
    /// <summary>Parameterarten und -typen samt Zahl der Typparameter, kleingeschrieben.</summary>
    Parameters: string;
    ResultType: string;
    Path: string;
  end;

procedure TOverloadDirectiveMissingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;

  function FirstToken(ANode: TSyntaxNode): Integer;
  begin
    Result := TokenAtOffset(Tokens, ANode.StartOffset);
  end;

  function NodeKey(ANode: TSyntaxNode): string;
  var
    Index: Integer;
  begin
    // Quelltext ohne Leerraum und Kommentare, kleingeschrieben.
    Result := '';
    for Index := FirstToken(ANode) to High(Tokens) do
    begin
      if Tokens[Index].Offset >= ANode.EndOffset then
      begin
        Break;
      end;
      if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      begin
        Result := Result + LowerCase(Tokens[Index].Text);
      end;
    end;
  end;

  // class operator Implicit … darf ohne overload mehrfach stehen.
  function IsOperator(AHeader: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    Index := FirstToken(AHeader);
    while (Index <= High(Tokens)) and (Tokens[Index].Offset < AHeader.EndOffset) and
      (Tokens[Index].Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Identifier, TPascalTokenKind.Comment]) and
      not SameText(Tokens[Index].Text, AHeader.Name) do
    begin
      if SameText(Tokens[Index].Text, 'operator') then
      begin
        Exit(True);
      end;
      Inc(Index);
    end;
    Result := False;
  end;

  // Parameterarten und -typen der Parameterliste AParams; A, B: Integer zählt als zwei Parameter.
  function ParameterKey(AParams: TSyntaxNode): string;
  const
    Modifiers: array[TParameterModifier] of string = ('', 'const ', 'var ', 'out ', 'constref ');
  var
    Inner, Count: Integer;
    Parameter, TypeNode: TSyntaxNode;
    TypeText: string;
  begin
    Result := '';
    for Inner := 0 to AParams.ChildCount - 1 do
    begin
      Parameter := AParams[Inner];
      if Parameter.Kind <> TSyntaxKind.Parameter then
      begin
        Continue;
      end;
      // Auch offene Arrays: array of PTypeInfo ist nicht array of TValue (#1325).
      TypeNode := TRoutineSignatures.ParameterType(Parameter);
      TypeText := '?';
      if TypeNode <> nil then
      begin
        TypeText := NodeKey(TypeNode);
      end;
      for Count := 1 to Length(Parameter.Name.Split([','])) do
      begin
        Result := Result + Modifiers[Parameter.Modifier] + TypeText + ';';
      end;
    end;
  end;

  function EntryOf(AHeader: TSyntaxNode): TOverloadEntry;
  var
    Index: Integer;
    Child: TSyntaxNode;
  begin
    Result := Default(TOverloadEntry);
    Result.Header := AHeader;
    Result.Name := AHeader.Name;
    Result.Path := TConditionalBranches.PathAt(Paths, FirstToken(AHeader));
    for Index := 0 to AHeader.ChildCount - 1 do
    begin
      Child := AHeader[Index];
      case Child.Kind of
        TSyntaxKind.Directive:
          // override braucht kein overload: Delphi übernimmt es von der überschriebenen Methode (mORMot2,
          // Graphics32, #1325).
          if MatchText(Child.Name, ['overload', 'override']) then
          begin
            Result.HasOverload := True;
          end;
        TSyntaxKind.GenericParams:
          Result.Parameters := Result.Parameters + '<' + IntToStr(Child.ChildCount) + '>';
        TSyntaxKind.Parameters:
          Result.Parameters := Result.Parameters + ParameterKey(Child);
        TSyntaxKind.TypeReference:
          Result.ResultType := NodeKey(Child);
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
  end;

  // Wird AEarlier immer mit übersetzt, wenn ALater übersetzt wird?
  function Together(const ALater, AEarlier: TOverloadEntry): Boolean;
  begin
    Result := TConditionalBranches.Implies(ALater.Path, AEarlier.Path);
  end;

  // " overload;" hinter dem ersten Semikolon des Kopfs, also vor den übrigen Direktiven.
  function OverloadEdit(const AEntry: TOverloadEntry; out AEdit: TRuleEdit): Boolean;
  var
    Index, Depth: Integer;
  begin
    Depth := 0;
    for Index := FirstToken(AEntry.Header) to High(Tokens) do
    begin
      if Tokens[Index].Offset >= AEntry.Header.EndOffset then
      begin
        Break;
      end;
      if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol('[') then
      begin
        Inc(Depth);
      end
      else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
      begin
        Dec(Depth);
      end
      else if (Depth = 0) and Tokens[Index].IsSymbol(';') then
      begin
        AEdit := TRuleEdit.Create(TTextRange.Create(Tokens[Index].EndPos, Tokens[Index].EndPos), ' overload;');
        Exit(True);
      end;
    end;
    AEdit := Default(TRuleEdit);
    Result := False;
  end;

  function NameRange(const AEntry: TOverloadEntry): TTextRange;
  var
    Index: Integer;
  begin
    for Index := FirstToken(AEntry.Header) to High(Tokens) do
    begin
      if Tokens[Index].Offset >= AEntry.Header.EndOffset then
      begin
        Break;
      end;
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AEntry.Name) then
      begin
        Exit(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos));
      end;
    end;
    Result := TTextRange.Create(AEntry.Header.StartPos, AEntry.Header.EndPos);
  end;

  // " overload;" an allen Deklarationen ohne overload.
  function MissingEdits(const AEntries: TArray<TOverloadEntry>): TArray<TRuleEdit>;
  var
    Edit: TRuleEdit;
    Entry: TOverloadEntry;
  begin
    Result := nil;
    for Entry in AEntries do
    begin
      if not Entry.HasOverload and OverloadEdit(Entry, Edit) then
      begin
        Result := Result + [Edit];
      end;
    end;
  end;

  // E2254/E2267 für ALater gegen AEarlier, mit einer Korrektur für alle Deklarationen ohne overload.
  procedure ReportMissing(const AEntries: TArray<TOverloadEntry>; const ALater, AEarlier: TOverloadEntry);
  var
    Edits: TArray<TRuleEdit>;
    Message: string;
    Fixes: TArray<TRuleFix>;
  begin
    if not ALater.HasOverload then
    begin
      Message := Format('%s ist überladen, aber nicht mit overload markiert (wie E2254).', [ALater.Name]);
    end
    else
    begin
      Message := Format('%s ist überladen, die frühere Deklaration in Zeile %d trägt kein overload (wie E2267).',
        [ALater.Name, AEarlier.Header.StartPos.Line + 1]);
    end;
    Edits := MissingEdits(AEntries);
    Fixes := nil;
    if Edits <> nil then
    begin
      Fixes := [TRuleFix.Create('overload; an alle Deklarationen anhängen', Edits, True)];
    end;
    AReport.Add(NameRange(ALater), Message, TRuleConfidence.High, Fixes);
  end;

  // E2301/E2252: ALater hat dieselben Parameter wie AEarlier.
  procedure ReportSame(const ALater, AEarlier: TOverloadEntry);
  var
    Message: string;
  begin
    if (ALater.ResultType <> '') and (ALater.ResultType = AEarlier.ResultType) then
    begin
      Message := Format('%s mit denselben Parametern und demselben Ergebnistyp gibt es schon in Zeile %d ' +
        '(wie E2301).', [ALater.Name, AEarlier.Header.StartPos.Line + 1]);
    end
    else
    begin
      Message := Format('%s mit denselben Parametern gibt es schon in Zeile %d (wie E2252).',
        [ALater.Name, AEarlier.Header.StartPos.Line + 1]);
    end;
    AReport.Add(NameRange(ALater), Message, TRuleConfidence.High);
  end;

  procedure CheckGroup(const AEntries: TArray<TOverloadEntry>);
  var
    Later, Earlier: Integer;
    Reported: Boolean;
  begin
    Reported := False;
    for Later := 1 to High(AEntries) do
    begin
      for Earlier := 0 to Later - 1 do
      begin
        if not Together(AEntries[Later], AEntries[Earlier]) then
        begin
          Continue;
        end;
        // E2254/E2267 einmal je Name.
        if not Reported and (not AEntries[Later].HasOverload or not AEntries[Earlier].HasOverload) then
        begin
          Reported := True;
          ReportMissing(AEntries, AEntries[Later], AEntries[Earlier]);
        end;
        if AEntries[Later].Parameters = AEntries[Earlier].Parameters then
        begin
          ReportSame(AEntries[Later], AEntries[Earlier]);
          Break;
        end;
      end;
    end;
  end;

  // Ist AEntry eine Deklaration ohne eigene Implementierung (interface-Teil, forward)?
  function Open(const AEntry: TOverloadEntry): Boolean;
  begin
    Result := not TRoutineSignatures.HasImplementation(AEntry.Header.Parent);
  end;

  // Gehört die Implementierung AEntry zu einer früheren Deklaration ohne Implementierung? Mit gleichen Parametern
  // oder in Kurzform (function Foo;) zur einzigen gleichen Namens (#1325).
  function ImplementsEarlier(const AEntries: TArray<TOverloadEntry>; const AEntry: TOverloadEntry): Boolean;
  var
    mOther: TOverloadEntry;
    mCount: Integer;
  begin
    mCount := 0;
    for mOther in AEntries do
    begin
      if SameText(mOther.Name, AEntry.Name) and Open(mOther) then
      begin
        if mOther.Parameters = AEntry.Parameters then
        begin
          Exit(True);
        end;
        Inc(mCount);
      end;
    end;
    Result := (mCount = 1) and TRoutineSignatures.IsShortForm(AEntry.Header);
  end;

  // Zählt AHeader nicht mit: Methodenrumpf TFoo.Bar, ohne Namen, Operator, class constructor/destructor?
  function Skipped(AHeader: TSyntaxNode): Boolean;
  begin
    Result := (Pos('.', AHeader.Name) > 0) or (AHeader.Name = '') or IsOperator(AHeader) or
      TRoutineSignatures.IsClassConstructor(Tokens, AHeader);
  end;

  // Deklarationen eines Bereichs nach Namen (Schlüssel in Großbuchstaben, Reihenfolge des ersten Auftretens in
  // AOrder); eine Implementierung (begin, asm oder external) zu einer früheren Deklaration (interface, forward)
  // zählt nicht. class constructor und class destructor sind keine Überladungen der Instanzmethoden (#1325).
  // Gruppiert über ein Dictionary: Je Kopf über alle früheren zu suchen war in Klassen mit vielen Methoden
  // quadratisch.
  procedure ScopeGroups(const AHeaders: TArray<TSyntaxNode>; ABodiesFollow: Boolean; AOrder: TList<string>;
    AGroups: TDictionary<string, TArray<TOverloadEntry>>);
  var
    mEntry: TOverloadEntry;
    mHeader: TSyntaxNode;
    mKey: string;
    mGroup: TArray<TOverloadEntry>;
    mIsBody: Boolean;
  begin
    for mHeader in AHeaders do
    begin
      if Skipped(mHeader) then
      begin
        Continue;
      end;
      mEntry := EntryOf(mHeader);
      mKey := UpperCase(mEntry.Name);
      if not AGroups.TryGetValue(mKey, mGroup) then
      begin
        mGroup := nil;
      end;
      mIsBody := ABodiesFollow and (mHeader.Parent <> nil) and
        TRoutineSignatures.HasImplementation(mHeader.Parent) and ImplementsEarlier(mGroup, mEntry);
      if not mIsBody then
      begin
        if mGroup = nil then
        begin
          AOrder.Add(mKey);
        end;
        AGroups.AddOrSetValue(mKey, mGroup + [mEntry]);
      end;
    end;
  end;

  // Deklarationen eines Bereichs nach Namen prüfen.
  procedure CheckScope(const AHeaders: TArray<TSyntaxNode>; ABodiesFollow: Boolean);
  var
    mOrder: TList<string>;
    mGroups: TDictionary<string, TArray<TOverloadEntry>>;
    mKey: string;
  begin
    mOrder := TList<string>.Create;
    mGroups := TDictionary<string, TArray<TOverloadEntry>>.Create;
    try
      ScopeGroups(AHeaders, ABodiesFollow, mOrder, mGroups);
      for mKey in mOrder do
      begin
        if Length(mGroups[mKey]) > 1 then
        begin
          CheckGroup(mGroups[mKey]);
        end;
      end;
    finally
      mGroups.Free;
      mOrder.Free;
    end;
  end;

  // Köpfe der Routinen direkt unter ANode (RoutineDecl mit RoutineHeader).
  procedure AddRoutines(ANode: TSyntaxNode; var AHeaders: TArray<TSyntaxNode>);
  var
    Index: Integer;
    Header: TSyntaxNode;
  begin
    if ANode = nil then
    begin
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[Index].Kind = TSyntaxKind.RoutineDecl then
      begin
        Header := ANode[Index].FindChild(TSyntaxKind.RoutineHeader);
        if Header <> nil then
        begin
          AHeaders := AHeaders + [Header];
        end;
      end;
    end;
  end;

  // Methodenköpfe eines Typs.
  function TypeHeaders(AType: TSyntaxNode): TArray<TSyntaxNode>;
  var
    Index: Integer;
  begin
    Result := nil;
    for Index := 0 to AType.ChildCount - 1 do
    begin
      if AType[Index].Kind = TSyntaxKind.RoutineHeader then
      begin
        Result := Result + [AType[Index]];
      end;
    end;
  end;

  // Prüft den Bereich ANode, wenn er einer ist (Typ, Unit, Programm, Bibliothek, Routine).
  procedure CheckNode(ANode: TSyntaxNode);
  var
    Headers: TArray<TSyntaxNode>;
  begin
    Headers := nil;
    case ANode.Kind of
      TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.InterfaceType,
      TSyntaxKind.HelperType:
        CheckScope(TypeHeaders(ANode), False);
      TSyntaxKind.UnitFile:
        begin
          AddRoutines(ANode.FindChild(TSyntaxKind.InterfaceSection), Headers);
          AddRoutines(ANode.FindChild(TSyntaxKind.ImplementationSection), Headers);
          CheckScope(Headers, True);
        end;
      TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile, TSyntaxKind.RoutineDecl:
        begin
          AddRoutines(ANode, Headers);
          CheckScope(Headers, True);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        CheckNode(Node);
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
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  Visit(AContext.Tree.Root);
end;

end.
