unit Atlas.Common.Rules.Builtin.Statements.Properties;

// Zuweisungen an Properties und Zeiger, die anders wirken als geschrieben (#909):
//   assign-to-property-member
//                     Zuweisung an ein Feld eines Records, den eine Property mit
//                     Getter, eine Default- bzw. Array-Property oder ein
//                     Funktionsergebnis nur als Kopie liefert (#1005, wie E2064),
//                     und an eine untypisierte Konstante. Typen kommen aus
//                     TNameResolver.NodeType; gemeldet wird nur bei sicher
//                     bekanntem Record-Typ. Liest die Property direkt ein Feld,
//                     schreibt Delphi in das Feld: still. Korrektur bei Properties
//                     mit write: über eine lokale Variable zuweisen und
//                     zurückschreiben (Variable über TRoutineBody.AddVariable, Unit
//                     des Typs über TUsesClauses.AddUnit).
//   untyped-pointer-refcount
//                     Pointer(X) := … mit einem Interface X (#1081, wie W1070):
//                     die Zuweisung umgeht die Referenzzählung. Typ über
//                     TNameResolver.NodeType, gemeldet wird nur bei sicher
//                     bekanntem Interface-Typ. Strings (string, AnsiString …)
//                     meldet Atlas mit „(dcc meldet das nicht)“, weil Delphi
//                     dort nur unter NEXTGEN warnt. Felder mit
//                     [weak] oder [unsafe] bleiben still. Korrekturen für Felder
//                     dieser Datei mit Pointer(Y) oder nil rechts: [weak] bzw.
//                     [unsafe] ans Feld, Zuweisung ohne Pointer.
//   readonly-property-assigned
//                     Zuweisung an eine Property ohne write (#1006, wie E2129) und
//                     Lesen einer Property ohne read (wie E2130), nur bei sicher
//                     aufgelöster Property; eine ohne Typ neu deklarierte, deren
//                     Vorfahr nicht im Index steht, gilt nicht als sicher (#1326). Vorab gefiltert über die Namen solcher
//                     Properties in Datei und Index. Korrekturen: Count := 0 wird
//                     Clear, wenn der Typ Clear hat; in einer Methode der eigenen
//                     Klasse direkt das Feld hinter read; für eine Property dieser
//                     Datei den Setter anlegen und write ergänzen.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract;

const
  AssignToPropertyMemberRuleId = 'assign-to-property-member';
  ReadonlyPropertyAssignedRuleId = 'readonly-property-assigned';

type
  TAssignToPropertyMemberRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUntypedPointerRefcountRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TReadonlyPropertyAssignedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Hat die Property-Signatur ASignature read bzw. write? Ohne beides ist es eine Neudeklaration
    /// (property Caption;), dann False.</summary>
    class function Accessors(const ASignature: string; out AHasRead, AHasWrite: Boolean): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Index.NameFacts,
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.AccessorCreation,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.Statements.Tokens,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TStatementsPropertiesText = (RecordTitle, AssignVia, Copy, ConstantTarget, PointerTitle, UseAttribute,
    PointerString, PointerWeak, NoWriteTitle, CreateWrite, AssignField, NoWriteClear, CallClear, NoWrite, NoRead);

const
  cTexts: array[TStatementsPropertiesText] of TAtlasText = (
    (De: 'Zuweisung an ein Feld eines Property-Records'; En: 'Assignment to a field of a property record'),
    (De: 'Über %s zuweisen und zurückschreiben'; En: 'Assign via %s and write back'),
    (De: '%s liefert eine Kopie; die Zuweisung an %s hat keine Wirkung (wie E2064).';
     En: '%s returns a copy; the assignment to %s has no effect (like E2064).'),
    (De: '%s ist eine Konstante; ihr lässt sich nichts zuweisen (wie E2064).';
     En: '%s is a constant; nothing can be assigned to it (like E2064).'),
    (De: 'Untypisierter Zeiger umgeht die Referenzzählung'; En: 'Untyped pointer bypasses reference counting'),
    (De: '[%s] %s verwenden'; En: 'Use [%s] %s'),
    (De: 'Die Zuweisung über Pointer umgeht die Referenzzählung des Strings %s (dcc meldet das nicht).';
     En: 'The assignment via Pointer bypasses the reference counting of the string %s (dcc does not report this).'),
    (De: 'Die Zuweisung über Pointer umgeht die Referenzzählung (wie W1070); besser [weak] %s.';
     En: 'The assignment via Pointer bypasses reference counting (like W1070); better [weak] %s.'),
    (De: 'Zuweisung an eine Property ohne write'; En: 'Assignment to a property without write'),
    (De: '%s anlegen und write ergänzen'; En: 'Create %s and add write'),
    (De: 'Feld %s zuweisen'; En: 'Assign field %s'),
    (De: '%s.%s hat kein write (wie E2129); zum Leeren Clear aufrufen.';
     En: '%s.%s has no write (like E2129); call Clear to empty it.'),
    (De: 'Clear aufrufen'; En: 'Call Clear'),
    (De: '%s.%s hat kein write (wie E2129).'; En: '%s.%s has no write (like E2129).'),
    (De: '%s.%s hat kein read (wie E2130).'; En: '%s.%s has no read (like E2130).'));

{$SCOPEDENUMS OFF}

{ TAssignToPropertyMemberRule }

type
{$SCOPEDENUMS ON}
  /// <summary>Nächster Schritt an der Kette X.Y.F: aufhören, zum Empfänger weitergehen oder melden.</summary>
  TMemberStep = (Stop, Next, Report);
{$SCOPEDENUMS OFF}

function TAssignToPropertyMemberRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(AssignToPropertyMemberRuleId, TRuleSeverity.Error,
    cTexts[TStatementsPropertiesText.RecordTitle].Text);
end;

procedure TAssignToPropertyMemberRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  // Anweisungen, die in einer Folge stehen: Dort passen drei Zeilen statt einer.
  SequenceParents = [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock,
    TSyntaxKind.RepeatStatement];
var
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  FileName: string;
  Tokens: TTokens;
  Lines: TArray<string>;
  LineBreak: string;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode.Parent;
    while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
    begin
      Result := Result.Parent;
    end;
  end;

  /// <summary>Über eine lokale Variable zuweisen und zurückschreiben: R := X.P; R.F := W; X.P := R.</summary>
  function CopyFix(AStatement, AReceiver: TSyntaxNode; const AType: TResolvedSymbol;
    out AFix: TRuleFix): Boolean;
  var
    Routine: TSyntaxNode;
    Name, TypeName, Indent, Receiver, NewText: string;
    UsesEdit: TTextEdit;
    Edits: TArray<TTextEdit>;
  begin
    Result := False;
    Routine := EnclosingRoutine(AStatement);
    if (Routine = nil) or (AStatement.Parent = nil) or not (AStatement.Parent.Kind in SequenceParents) or
      (AStatement.StartPos.Line <> AStatement.EndPos.Line) or (AStatement.StartPos.Line > High(Lines)) then
    begin
      Exit;
    end;
    TypeName := AType.Name;
    Name := TypeName;
    if (Length(Name) > 1) and CharInSet(Name[1], ['T', 't']) then
    begin
      Name := Copy(Name, 2, MaxInt);
    end;
    Name := TRoutineBody.UniqueName(Tokens, UpperCase(Copy(Name, 1, 1)));
    Indent := TTextLines.IndentOf(Lines[AStatement.StartPos.Line]);
    Receiver := NodeText(AReceiver);
    NewText := Name + ' := ' + Receiver + ';' + LineBreak + Indent + Name +
      Copy(AContext.Text, AReceiver.EndOffset + 1, AStatement.EndOffset - AReceiver.EndOffset) + ';' + LineBreak +
      Indent + Receiver + ' := ' + Name;
    Edits := [TRoutineBody.AddVariable(AContext.Text, Routine, Name, TypeName, AContext.Formatting),
      TTextEdit.Create(TTextRange.Create(AStatement.StartPos, AStatement.EndPos), NewText)];
    // Der Typ stammt oft aus einer Unit, die die Datei nicht einbindet (TRect aus System.Types).
    if (AType.UnitName <> '') and not SameText(AType.UnitName, 'System') and
      not SameText(AType.UnitName, TUsesClauses.OwnName(Tokens)) and
      not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(Tokens), AType.UnitName, AContext.Namespaces) then
    begin
      if not TUsesClauses.AddUnit(Tokens, AStatement.StartOffset, AType.UnitName, LineBreak, UsesEdit) then
      begin
        Exit;
      end;
      Edits := Edits + [UsesEdit];
    end;
    AFix := TRuleFix.Create(cTexts[TStatementsPropertiesText.AssignVia].Fmt([Name]), Edits);
    Result := True;
  end;

  // Empfänger von ATarget (X in X.F), wenn sein Typ sicher ein Record ist; Symbol und Typ des Empfängers.
  function RecordReceiver(ATarget: TSyntaxNode; out AReceiver: TSyntaxNode; out ASymbol,
    ATypeInfo: TResolvedSymbol): Boolean;
  var
    mTypeFound: Boolean;
  begin
    AReceiver := nil;
    Result := (ATarget.Kind = TSyntaxKind.MemberAccess) and (ATarget.ChildCount > 0);
    if not Result then
    begin
      Exit;
    end;
    AReceiver := ATarget[0];
    Result := (AReceiver.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
      TSyntaxKind.Call]) and Resolver.NodeType(AContext.Tree, FileName, AReceiver, ASymbol, ATypeInfo, mTypeFound);
    Result := Result and mTypeFound and (ATypeInfo.SymbolKind = TIndexSymbolKind.RecordType) and not ASymbol.IsType;
  end;

  function PropertyStep(AStatement, AReceiver: TSyntaxNode; const ASymbol, ATypeInfo: TResolvedSymbol;
    var AFixes: TArray<TRuleFix>): TMemberStep;
  var
    mReadsField: Boolean;
    mFix: TRuleFix;
  begin
    // Liest die Property ein Feld, schreibt Delphi in das Feld; weiter oben kann es wieder eine Kopie geben.
    if (ASymbol.MaxArgs = 0) and (AReceiver.Kind <> TSyntaxKind.IndexAccess) then
    begin
      if not Resolver.PropertyReadsField(ASymbol, mReadsField) then
      begin
        Exit(TMemberStep.Stop);
      end;
      if mReadsField then
      begin
        Exit(TMemberStep.Next);
      end;
    end;
    Result := TMemberStep.Report;
    if ContainsText(' ' + ASymbol.Signature.Replace(';', ' ') + ' ', ' write ') and
      CopyFix(AStatement, AReceiver, ATypeInfo, mFix) then
    begin
      AFixes := [mFix];
    end;
  end;

  function MemberStep(AStatement, AReceiver: TSyntaxNode; const ASymbol, ATypeInfo: TResolvedSymbol;
    var AFixes: TArray<TRuleFix>): TMemberStep;
  begin
    case ASymbol.SymbolKind of
      TIndexSymbolKind.Property_:
        Result := PropertyStep(AStatement, AReceiver, ASymbol, ATypeInfo, AFixes);
      // Ohne Ergebnistyp ist es kein Wert; das meldet der Compiler anders.
      TIndexSymbolKind.Method, TIndexSymbolKind.Routine:
        if ASymbol.TypeName = '' then
        begin
          Result := TMemberStep.Stop;
        end
        else
        begin
          Result := TMemberStep.Report;
        end;
      // Feld eines Records in einem Feld: weiter zum Empfänger.
      TIndexSymbolKind.Field, TIndexSymbolKind.Variable:
        if AReceiver.Kind = TSyntaxKind.MemberAccess then
        begin
          Result := TMemberStep.Next;
        end
        else
        begin
          Result := TMemberStep.Stop;
        end;
    else
      Result := TMemberStep.Stop;
    end;
  end;

  /// <summary>Schreibt die Zuweisung an ATarget (ein Feld hinter dem Punkt) in eine Kopie?</summary>
  procedure CheckMember(AStatement, ATarget: TSyntaxNode);
  var
    mTarget, mReceiver: TSyntaxNode;
    mSymbol, mTypeInfo: TResolvedSymbol;
    mStep: TMemberStep;
    mName: string;
    mFixes: TArray<TRuleFix>;
  begin
    // Iterativ (Bericht M1): statt sich mit dem Empfänger erneut aufzurufen, geht die Schleife zum Empfänger weiter.
    mTarget := ATarget;
    mStep := TMemberStep.Next;
    mFixes := nil;
    while mStep = TMemberStep.Next do
    begin
      mFixes := nil;
      mStep := TMemberStep.Stop;
      if RecordReceiver(mTarget, mReceiver, mSymbol, mTypeInfo) then
      begin
        mStep := MemberStep(AStatement, mReceiver, mSymbol, mTypeInfo, mFixes);
      end;
      if mStep = TMemberStep.Next then
      begin
        mTarget := mReceiver;
      end;
    end;
    if mStep <> TMemberStep.Report then
    begin
      Exit;
    end;
    mName := mSymbol.Name;
    if mReceiver.Kind = TSyntaxKind.IndexAccess then
    begin
      mName := NodeText(mReceiver);
    end;
    AReport.Add(TTextRange.Create(mTarget.StartPos, mTarget.EndPos), cTexts[TStatementsPropertiesText.Copy].Fmt([mName,
      mTarget.Name]), TRuleConfidence.High, mFixes);
  end;

  procedure CheckConstant(ATarget: TSyntaxNode);
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    // Typisierte Konstanten sind mit {$J+} beschreibbar; untypisierte nie.
    if Resolver.NodeType(AContext.Tree, FileName, ATarget, Symbol, TypeInfo, TypeFound) and
      (Symbol.SymbolKind = TIndexSymbolKind.Constant) and (Symbol.TypeName = '') then
    begin
      AReport.Add(TTextRange.Create(ATarget.StartPos, ATarget.EndPos),
        cTexts[TStatementsPropertiesText.ConstantTarget].Fmt([Symbol.Name]), TRuleConfidence.High);
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
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount > 0) then
        begin
          if Node[0].Kind = TSyntaxKind.Identifier then
          begin
            CheckConstant(Node[0]);
          end
          else
          begin
            CheckMember(Node, Node[0]);
          end;
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
  FileName := ContextFileName(AContext);
  Tokens := AContext.Tree.Tokens;
  Lines := TTextLines.SplitLines(AContext.Text);
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  Resolver.PinTree(AContext.Tree, FileName);
  try
    Visit(AContext.Tree.Root);
  finally
    Resolver.UnpinTree;
  end;
end;

{ TUntypedPointerRefcountRule }

function TUntypedPointerRefcountRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('untyped-pointer-refcount', TRuleSeverity.Warning,
    cTexts[TStatementsPropertiesText.PointerTitle].Text);
end;

procedure TUntypedPointerRefcountRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  FileName: string;
  Tokens: TTokens;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  // Pointer(X) mit genau einem Argument: X; sonst nil.
  function PointerArgument(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := nil;
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
      (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Pointer') then
    begin
      Result := ANode[1];
    end;
  end;

  // Code-Token vor den Attributen vor AIndex ([weak], [unsafe], auch mehrere); AMarked: eines davon ist weak oder
  // unsafe.
  function BeforeAttributes(AIndex: Integer; out AMarked: Boolean): Integer;
  var
    mOpen: Integer;
  begin
    AMarked := False;
    Result := PreviousCode(Tokens, AIndex);
    while (Result >= 0) and Tokens[Result].IsSymbol(']') do
    begin
      mOpen := Result;
      while (mOpen >= 0) and not Tokens[mOpen].IsSymbol('[') do
      begin
        AMarked := AMarked or MatchText(Tokens[mOpen].Text, ['weak', 'unsafe', 'WeakAttribute', 'UnsafeAttribute']);
        Dec(mOpen);
      end;
      Result := PreviousCode(Tokens, mOpen);
    end;
  end;

  // Token an der Stelle der Deklaration von ASymbol; -1 ohne.
  function DeclarationToken(const ASymbol: TResolvedSymbol): Integer;
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to High(Tokens) do
    begin
      if (Tokens[mIndex].StartPos.Line = ASymbol.SelectionRange.StartPos.Line) and
        (Tokens[mIndex].StartPos.Character = ASymbol.SelectionRange.StartPos.Character) then
      begin
        Exit(mIndex);
      end;
    end;
    Result := -1;
  end;

  // Namenstoken des Felds ASymbol in dieser Datei, wenn es allein deklariert ist (A: IFoo, nicht A, B: IFoo); -1 sonst.
  // AMarked: das Feld trägt schon [weak] oder [unsafe].
  function FieldToken(const ASymbol: TResolvedSymbol; out AMarked: Boolean): Integer;
  var
    mBefore, mAfter: Integer;
  begin
    Result := -1;
    AMarked := False;
    if (ASymbol.SymbolKind = TIndexSymbolKind.Field) and SameText(ASymbol.FileName, FileName) then
    begin
      Result := DeclarationToken(ASymbol);
    end;
    if Result < 0 then
    begin
      Exit;
    end;
    mBefore := BeforeAttributes(Result, AMarked);
    mAfter := NextCode(Tokens, Result + 1);
    if ((mBefore >= 0) and Tokens[mBefore].IsSymbol(',')) or (mAfter > High(Tokens)) or
      not Tokens[mAfter].IsSymbol(':') then
    begin
      Result := -1;
    end;
  end;

  // Neuer Wert ohne Pointer(…): Q aus Pointer(Q) bzw. nil; '' sonst.
  function PlainValue(AValue: TSyntaxNode): string;
  var
    mSource: TSyntaxNode;
  begin
    Result := '';
    if AValue = nil then
    begin
      Exit;
    end;
    mSource := PointerArgument(AValue);
    if mSource <> nil then
    begin
      Result := NodeText(mSource);
    end
    else if SameText(Trim(NodeText(AValue)), 'nil') then
    begin
      Result := 'nil';
    end;
  end;

  // Attribut AAttribute am Feld (Token AField), Zuweisung an AName mit dem Wert ohne Pointer(…).
  function AttributeFix(const AAttribute: string; AStatement: TSyntaxNode; AField: Integer;
    const ASymbolName, AName: string): TRuleFix;
  var
    mValue: TSyntaxNode;
  begin
    mValue := AStatement[1];
    Result := TRuleFix.Create(cTexts[TStatementsPropertiesText.UseAttribute].Fmt([AAttribute, ASymbolName]),
      [TRuleEdit.Create(TTextRange.Create(Tokens[AField].StartPos, Tokens[AField].StartPos), '[' + AAttribute + '] '),
      TRuleEdit.Create(TTextRange.Create(AStatement[0].StartPos, AStatement[0].EndPos), AName),
      TRuleEdit.Create(TTextRange.Create(mValue.StartPos, mValue.EndPos), PlainValue(mValue))]);
  end;

  // Korrekturen [weak] bzw. [unsafe] am Feld (Token AField) samt Zuweisung ohne Pointer(…).
  function WeakFixes(AStatement: TSyntaxNode; AField: Integer; const ASymbol: TResolvedSymbol;
    const AName: string): TArray<TRuleFix>;
  begin
    Result := nil;
    if (AField >= 0) and (AStatement.ChildCount > 1) and (PlainValue(AStatement[1]) <> '') then
    begin
      Result := [AttributeFix('weak', AStatement, AField, ASymbol.Name, AName),
        AttributeFix('unsafe', AStatement, AField, ASymbol.Name, AName)];
    end;
  end;

  // Ziel X von Pointer(X) := …, wenn sein Symbol aufgelöst ist.
  function PointerTarget(AStatement: TSyntaxNode; out ATarget: TSyntaxNode; out ASymbol, ATypeInfo: TResolvedSymbol;
    out ATypeFound: Boolean): Boolean;
  begin
    ATypeFound := False;
    ATarget := PointerArgument(AStatement[0]);
    Result := (ATarget <> nil) and (ATarget.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]);
    Result := Result and Resolver.NodeType(AContext.Tree, FileName, ATarget, ASymbol, ATypeInfo, ATypeFound) and
      not ASymbol.IsType;
  end;

  procedure CheckAssignment(AStatement: TSyntaxNode);
  var
    mTarget: TSyntaxNode;
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound, mMarked: Boolean;
    mName: string;
    mField: Integer;
  begin
    if not PointerTarget(AStatement, mTarget, mSymbol, mTypeInfo, mTypeFound) then
    begin
      Exit;
    end;
    mName := NodeText(mTarget);
    // Strings: ebenso falsch, aber dcc warnt nur unter NEXTGEN; [weak]/[unsafe] gibt es für sie nicht.
    if MatchText(mSymbol.TypeName, ['string', 'UnicodeString', 'AnsiString', 'RawByteString', 'UTF8String']) then
    begin
      AReport.Add(TTextRange.Create(AStatement[0].StartPos, AStatement[0].EndPos),
        cTexts[TStatementsPropertiesText.PointerString].Fmt([mName]),
        TRuleConfidence.Medium);
      Exit;
    end;
    if not ((mTypeFound and (mTypeInfo.SymbolKind = TIndexSymbolKind.InterfaceType)) or
      MatchText(mSymbol.TypeName, ['IInterface', 'IUnknown', 'IDispatch'])) then
    begin
      Exit;
    end;
    mField := FieldToken(mSymbol, mMarked);
    if not mMarked then
    begin
      AReport.Add(TTextRange.Create(AStatement[0].StartPos, AStatement[0].EndPos),
        cTexts[TStatementsPropertiesText.PointerWeak].Fmt([mName]), TRuleConfidence.Medium,
        WeakFixes(AStatement, mField, mSymbol, mName));
    end;
  end;

  // Vorfilter: ohne Pointer( keine Namensauflösung.
  function HasPointerCall: Boolean;
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to High(Tokens) - 1 do
    begin
      if (Tokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[mIndex].Text, 'Pointer') and
        Tokens[mIndex + 1].IsSymbol('(') then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Ohne Rekursion durch den Baum (#1094).
  procedure Visit(ARoot: TSyntaxNode);
  var
    mStack: TArray<TSyntaxNode>;
    mCount, mIndex: Integer;
    mNode: TSyntaxNode;
  begin
    SetLength(mStack, 64);
    mStack[0] := ARoot;
    mCount := 1;
    while mCount > 0 do
    begin
      Dec(mCount);
      mNode := mStack[mCount];
      if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode.ChildCount > 0) then
      begin
        CheckAssignment(mNode);
      end;
      if mCount + mNode.ChildCount > Length(mStack) then
      begin
        SetLength(mStack, 2 * (mCount + mNode.ChildCount));
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mStack[mCount] := mNode[mIndex];
        Inc(mCount);
      end;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  if not HasPointerCall then
  begin
    Exit;
  end;
  FileName := ContextFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  Resolver.PinTree(AContext.Tree, FileName);
  try
    Visit(AContext.Tree.Root);
  finally
    Resolver.UnpinTree;
  end;
end;

{ TReadonlyPropertyAssignedRule }

function TReadonlyPropertyAssignedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ReadonlyPropertyAssignedRuleId, TRuleSeverity.Error,
    cTexts[TStatementsPropertiesText.NoWriteTitle].Text);
end;

class function TReadonlyPropertyAssignedRule.Accessors(const ASignature: string; out AHasRead,
  AHasWrite: Boolean): Boolean;
var
  Text, Word: string;
  Index, Depth: Integer;
begin
  // Indexparameter ausblenden: [read: Integer] wäre kein Zugriff.
  Text := '';
  Depth := 0;
  for Index := 1 to Length(ASignature) do
  begin
    if ASignature[Index] = '[' then
    begin
      Inc(Depth);
    end
    else if ASignature[Index] = ']' then
    begin
      Dec(Depth);
    end
    else if Depth = 0 then
    begin
      Text := Text + ASignature[Index];
    end;
  end;
  AHasRead := False;
  AHasWrite := False;
  for Word in Text.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    if SameText(Word, 'read') then
    begin
      AHasRead := True;
    end
    else if SameText(Word, 'write') then
    begin
      AHasWrite := True;
    end;
  end;
  Result := AHasRead or AHasWrite;
end;

/// <summary>Bit 1, wenn die Property mit ASignature kein write hat, Bit 2, wenn sie kein read hat; 0 ohne
/// Zugriffe.</summary>
function AccessFlags(const ASignature: string): Integer;
var
  mHasRead, mHasWrite: Boolean;
begin
  Result := 0;
  if TReadonlyPropertyAssignedRule.Accessors(ASignature, mHasRead, mHasWrite) then
  begin
    Result := Ord(not mHasWrite) or (2 * Ord(not mHasRead));
  end;
end;

/// <summary>Properties namens AName im Index: Bit 1, wenn eine kein write hat, Bit 2, wenn eine kein read hat.
/// Hängt nur vom Index ab und wird über alle Units des Laufs gemerkt (TIndexNameFacts).</summary>
function IndexPropertyFlags(const AFacts: IIndexNameFacts; const AIndex: ISymbolIndex; const AName: string): Integer;
var
  mFacts: IIndexNameFacts;
  mIndex: ISymbolIndex;
  mName: string;
begin
  mFacts := AFacts;
  mIndex := AIndex;
  mName := AName;
  Result := TIndexNameFacts.Get(mFacts, mIndex, 'propertyAccess:' + UpperCase(mName),
    function: Integer
    var
      mLocations: TArray<TSymbolLocation>;
      mPosition: Integer;
    begin
      Result := 0;
      if mIndex = nil then
      begin
        Exit;
      end;
      mLocations := mIndex.FindSymbols(mName);
      for mPosition := 0 to High(mLocations) do
      begin
        if mLocations[mPosition].Symbol.Kind = TIndexSymbolKind.Property_ then
        begin
          Result := Result or AccessFlags(mLocations[mPosition].Symbol.Signature);
        end;
      end;
    end);
end;

procedure TReadonlyPropertyAssignedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  FileName: string;
  Lines: TArray<string>;
  Local: TUnitIndex;
  // Name -> gibt es eine Property ohne write (Bit 1) bzw. ohne read (Bit 2) mit diesem Namen?
  Suspects: TDictionary<string, Integer>;
  // Signaturen der Properties der eigenen Unit je Name (klein); erst bei Bedarf.
  LocalProperties: TObjectDictionary<string, TList<string>>;
  Actions: TClassActionContext;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function SuspectFlags(const AName: string): Integer;
  var
    Symbol: TIndexSymbol;
    Signatures: TList<string>;
    Signature: string;
  begin
    if Suspects.TryGetValue(LowerCase(AName), Result) then
    begin
      Exit;
    end;
    Result := 0;
    // Properties der eigenen Unit einmal nach Namen ordnen statt je Name über alle Symbole (große Units).
    if LocalProperties = nil then
    begin
      LocalProperties := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
      for Symbol in Local.Symbols do
      begin
        if Symbol.Kind = TIndexSymbolKind.Property_ then
        begin
          if not LocalProperties.TryGetValue(LowerCase(Symbol.Name), Signatures) then
          begin
            Signatures := TList<string>.Create;
            LocalProperties.Add(LowerCase(Symbol.Name), Signatures);
          end;
          Signatures.Add(Symbol.Signature);
        end;
      end;
    end;
    if LocalProperties.TryGetValue(LowerCase(AName), Signatures) then
    begin
      for Signature in Signatures do
      begin
        Result := Result or AccessFlags(Signature);
      end;
    end;
    // Der Teil aus dem Index hängt nur vom Namen ab: über alle Units des Laufs gemerkt (häufige Namen wie Count
    // haben Tausende Treffer und kamen sonst in jeder Unit neu).
    Result := Result or IndexPropertyFlags(AContext.NameFacts, AContext.Index, AName);
    Suspects.Add(LowerCase(AName), Result);
  end;

  /// <summary>Wort hinter read in der Signatur ('' ohne); bei read FPunkt.X das ganze FPunkt.X.</summary>
  function ReadAccessor(const ASignature: string): string;
  var
    Words: TArray<string>;
    Index: Integer;
  begin
    Result := '';
    Words := ASignature.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty);
    for Index := 0 to High(Words) - 1 do
    begin
      if SameText(Words[Index], 'read') then
      begin
        Exit(Words[Index + 1]);
      end;
    end;
  end;

  /// <summary>Klasse der Methode, in der ANode steht (TKunde bei TKunde.Laden); '' außerhalb.</summary>
  function MethodClass(ANode: TSyntaxNode): string;
  var
    Node: TSyntaxNode;
  begin
    Result := '';
    Node := ANode.Parent;
    while (Node <> nil) and (Node.Kind <> TSyntaxKind.RoutineDecl) do
    begin
      Node := Node.Parent;
    end;
    if (Node <> nil) and (Pos('.', Node.Name) > 0) then
    begin
      Result := Copy(Node.Name, 1, LastDelimiter('.', Node.Name) - 1);
    end;
  end;

  function SetterFix(const AProperty: TResolvedSymbol; out AFix: TRuleFix): Boolean;
  var
    Plan: TAccessorPlan;
    Action: TCodeAction;
    Line, Column: Integer;
    Accessor, Text: string;
  begin
    Result := False;
    Line := AProperty.Range.StartPos.Line;
    if not SameText(AProperty.UnitName, Local.UnitName) or (AProperty.MaxArgs > 0) or
      (AProperty.Range.EndPos.Line <> Line) or (Line > High(Lines)) or StartsText('class ', AProperty.Signature) then
    begin
      Exit;
    end;
    Accessor := ReadAccessor(AProperty.Signature);
    Text := LowerCase(Lines[Line]);
    Column := Pos('read ' + LowerCase(Accessor), Text);
    if (Accessor = '') or (Column = 0) then
    begin
      Exit;
    end;
    Column := Column - 1 + Length('read ' + Accessor);
    Plan := Default(TAccessorPlan);
    Plan.Kind := TAccessorKind.Setter;
    Plan.PropertyName := AProperty.Name;
    Plan.PropertyType := AProperty.TypeName;
    if AProperty.TypeArgs <> '' then
    begin
      Plan.PropertyType := Plan.PropertyType + '<' + AProperty.TypeArgs + '>';
    end;
    Plan.MethodSection := 'private';
    if AContext.AccessorsProtected then
    begin
      Plan.MethodSection := 'protected';
    end;
    if not TClassActions.CreateAccessor(AContext.Text, Line, Plan, Actions, Action) then
    begin
      Exit;
    end;
    AFix := TRuleFix.Create(cTexts[TStatementsPropertiesText.CreateWrite].Fmt([Plan.Name]), Action.Edits +
      [TTextEdit.Create(TTextRange.Create(Line, Column, Line, Column), ' write ' + Plan.Name)]);
    Result := True;
  end;

  // Kann ATarget eine Property ohne write sein (Name oder bei Liste[I] die Property davor)?
  function IsSuspectWrite(ATarget: TSyntaxNode): Boolean;
  begin
    Result := ATarget.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess];
    if Result and (SuspectFlags(ATarget.Name) and 1 = 0) then
    begin
      Result := (ATarget.Kind = TSyntaxKind.IndexAccess) and (ATarget.ChildCount > 0) and
        (SuspectFlags(ATarget[0].Name) and 1 <> 0);
    end;
  end;

  // Ist ATarget sicher eine Property mit Typ und ohne write?
  function IsReadonlyProperty(ATarget: TSyntaxNode; out ASymbol: TResolvedSymbol): Boolean;
  var
    mTypeInfo: TResolvedSymbol;
    mTypeFound, mHasRead, mHasWrite: Boolean;
  begin
    Result := Resolver.NodeType(AContext.Tree, FileName, ATarget, ASymbol, mTypeInfo, mTypeFound) and
      (ASymbol.SymbolKind = TIndexSymbolKind.Property_) and (ASymbol.TypeName <> '');
    Result := Result and Accessors(ASymbol.Signature, mHasRead, mHasWrite) and not mHasWrite;
  end;

  // Count := 0 auf einer Liste mit Methode Clear?
  function ClearsList(AStatement, ATarget: TSyntaxNode; const ASymbol: TResolvedSymbol): Boolean;
  var
    mOwner, mOwnerType, mClear: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    Result := SameText(ASymbol.Name, 'Count') and (AStatement.ChildCount > 1) and (NodeText(AStatement[1]) = '0');
    Result := Result and (ATarget.Kind = TSyntaxKind.MemberAccess) and (ATarget.ChildCount > 0);
    Result := Result and Resolver.NodeType(AContext.Tree, FileName, ATarget[0], mOwner, mOwnerType, mTypeFound) and
      mTypeFound;
    Result := Result and Resolver.FindMember(mOwnerType, 'Clear', mClear) and
      (mClear.SymbolKind = TIndexSymbolKind.Method);
  end;

  // Steht die Zuweisung an X bzw. Self.X in einer Methode der Klasse der Property ASymbol?
  function InOwnMethod(AStatement, ATarget: TSyntaxNode; const ASymbol: TResolvedSymbol): Boolean;
  begin
    Result := SameText(MethodClass(AStatement), ASymbol.Container);
    Result := Result and ((ATarget.Kind = TSyntaxKind.Identifier) or ((ATarget.Kind = TSyntaxKind.MemberAccess) and
      (ATarget.ChildCount > 0) and SameText(NodeText(ATarget[0]), 'Self')));
  end;

  // In einer Methode der Klasse selbst: direkt in das Feld hinter read schreiben.
  function FieldFixes(AStatement, ATarget: TSyntaxNode; const ASymbol: TResolvedSymbol): TArray<TRuleFix>;
  var
    mReadsField: Boolean;
    mField: string;
  begin
    Result := nil;
    if InOwnMethod(AStatement, ATarget, ASymbol) and Resolver.PropertyReadsField(ASymbol, mReadsField) and
      mReadsField then
    begin
      mField := ReadAccessor(ASymbol.Signature);
      Result := [TRuleFix.Create(cTexts[TStatementsPropertiesText.AssignField].Fmt([mField]),
        [TTextEdit.Create(TTextRange.Create(
        ATarget.StartPos, ATarget.EndPos), mField)])];
    end;
  end;

  procedure CheckWrite(AStatement, ATarget: TSyntaxNode);
  var
    mSymbol: TResolvedSymbol;
    mMessage: string;
    mFix: TRuleFix;
    mFixes: TArray<TRuleFix>;
  begin
    if not IsSuspectWrite(ATarget) or not IsReadonlyProperty(ATarget, mSymbol) then
    begin
      Exit;
    end;
    // Count := 0 auf einer Liste: Clear leert sie.
    if ClearsList(AStatement, ATarget, mSymbol) then
    begin
      mMessage := cTexts[TStatementsPropertiesText.NoWriteClear].Fmt([mSymbol.Container,
        mSymbol.Name]);
      mFixes := [TRuleFix.Create(cTexts[TStatementsPropertiesText.CallClear].Text,
        [TTextEdit.Create(TTextRange.Create(AStatement.StartPos,
        AStatement.EndPos), NodeText(ATarget[0]) + '.Clear')])];
    end
    else
    begin
      mMessage := cTexts[TStatementsPropertiesText.NoWrite].Fmt([mSymbol.Container, mSymbol.Name]);
      mFixes := FieldFixes(AStatement, ATarget, mSymbol);
    end;
    if SetterFix(mSymbol, mFix) then
    begin
      mFixes := mFixes + [mFix];
    end;
    if Length(mFixes) > 1 then
    begin
      mFixes[1].Alternative := True;
    end;
    AReport.Add(TTextRange.Create(ATarget.StartPos, ATarget.EndPos), mMessage, TRuleConfidence.High, mFixes);
  end;

  procedure CheckRead(ANode: TSyntaxNode);
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound, HasRead, HasWrite: Boolean;
  begin
    if SuspectFlags(ANode.Name) and 2 = 0 then
    begin
      Exit;
    end;
    if Resolver.NodeType(AContext.Tree, FileName, ANode, Symbol, TypeInfo, TypeFound) and
      (Symbol.SymbolKind = TIndexSymbolKind.Property_) and (Symbol.TypeName <> '') and
      Accessors(Symbol.Signature, HasRead, HasWrite) and not HasRead then
    begin
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), cTexts[TStatementsPropertiesText.NoRead].Fmt(
        [Symbol.Container, Symbol.Name]), TRuleConfidence.High);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node, Target: TSyntaxNode;
    Written: Boolean;
    Pending: TStack<TSyntaxNode>;
    PendingWritten: TStack<Boolean>;
  begin
    // Iterativ (Bericht M1): zu jedem Knoten auf dem Stapel, ob er geschrieben wird.
    Pending := TStack<TSyntaxNode>.Create;
    PendingWritten := TStack<Boolean>.Create;
    try
      Pending.Push(ARoot);
      PendingWritten.Push(False);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Written := PendingWritten.Pop;
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount > 0) then
        begin
          Target := Node[0];
          CheckWrite(Node, Target);
          // Erst die Kinder des Ziels, dann die übrigen Kinder der Zuweisung (umgekehrt auf den Stapel).
          for Index := Node.ChildCount - 1 downto 1 do
          begin
            Pending.Push(Node[Index]);
            PendingWritten.Push(False);
          end;
          // Das Ziel selbst wird geschrieben, bei Liste.Items[I] auch die Property davor.
          for Index := Target.ChildCount - 1 downto 0 do
          begin
            Pending.Push(Target[Index]);
            PendingWritten.Push((Target.Kind = TSyntaxKind.IndexAccess) and (Index = 0));
          end;
          Continue;
        end;
        if not Written and (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
        begin
          CheckRead(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          PendingWritten.Push(False);
        end;
      end;
    finally
      PendingWritten.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FileName := ContextFileName(AContext);
  Lines := TTextLines.SplitLines(AContext.Text);
  Actions := TClassActionContext.Default;
  Actions.Index := AContext.Index;
  Actions.Namespaces := AContext.Namespaces;
  Actions.DelphiVersion := AContext.DelphiVersion;
  Actions.Style := AContext.Formatting;
  Suspects := TDictionary<string, Integer>.Create;
  LocalProperties := nil;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  try
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Local := Resolver.ExtractedUnit(AContext.Tree, FileName);
      Visit(AContext.Tree.Root);
    finally
      Resolver.UnpinTree;
    end;
  finally
    LocalProperties.Free;
    Suspects.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Statements.Properties', cTexts);

end.
