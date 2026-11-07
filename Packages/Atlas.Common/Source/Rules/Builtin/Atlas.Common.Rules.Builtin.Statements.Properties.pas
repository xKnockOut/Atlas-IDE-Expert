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
//                     Vorfahr nicht im Index steht, gilt nicht als sicher (#1326). Vorab gefiltert über die Namen
//                     solcher
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
  cAssignToPropertyMemberRuleId = 'assign-to-property-member';
  cReadonlyPropertyAssignedRuleId = 'readonly-property-assigned';

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
  Result := TRuleDescriptor.Create(cAssignToPropertyMemberRuleId, TRuleSeverity.Error,
    cTexts[TStatementsPropertiesText.RecordTitle].Text);
end;

procedure TAssignToPropertyMemberRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  // Anweisungen, die in einer Folge stehen: Dort passen drei Zeilen statt einer.
  cSequenceParents = [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock,
    TSyntaxKind.RepeatStatement];
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;
  mTokens: TTokens;
  mLines: TArray<string>;
  mLineBreak: string;

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
    mRoutine: TSyntaxNode;
    mName, mTypeName, mIndent, mReceiver, mNewText: string;
    mUsesEdit: TTextEdit;
    mEdits: TArray<TTextEdit>;
  begin
    Result := False;
    mRoutine := EnclosingRoutine(AStatement);
    if (mRoutine = nil) or (AStatement.Parent = nil) or not (AStatement.Parent.Kind in cSequenceParents) or
      (AStatement.StartPos.Line <> AStatement.EndPos.Line) or (AStatement.StartPos.Line > High(mLines)) then
    begin
      Exit;
    end;
    mTypeName := AType.Name;
    mName := mTypeName;
    if (Length(mName) > 1) and CharInSet(mName[1], ['T', 't']) then
    begin
      mName := Copy(mName, 2, MaxInt);
    end;
    mName := TRoutineBody.UniqueName(mTokens, UpperCase(Copy(mName, 1, 1)));
    mIndent := TTextLines.IndentOf(mLines[AStatement.StartPos.Line]);
    mReceiver := NodeText(AReceiver);
    mNewText := mName + ' := ' + mReceiver + ';' + mLineBreak + mIndent + mName +
      Copy(AContext.Text, AReceiver.EndOffset + 1, AStatement.EndOffset - AReceiver.EndOffset) + ';' + mLineBreak +
      mIndent + mReceiver + ' := ' + mName;
    mEdits := [TRoutineBody.AddVariable(AContext.Text, mRoutine, mName, mTypeName, AContext.Formatting),
      TTextEdit.Create(TTextRange.Create(AStatement.StartPos, AStatement.EndPos), mNewText)];
    // Der Typ stammt oft aus einer Unit, die die Datei nicht einbindet (TRect aus System.Types).
    if (AType.UnitName <> '') and not SameText(AType.UnitName, 'System') and
      not SameText(AType.UnitName, TUsesClauses.OwnName(mTokens)) and
      not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(mTokens), AType.UnitName, AContext.Namespaces) then
    begin
      if not TUsesClauses.AddUnit(mTokens, AStatement.StartOffset, AType.UnitName, mLineBreak, mUsesEdit) then
      begin
        Exit;
      end;
      mEdits := mEdits + [mUsesEdit];
    end;
    AFix := TRuleFix.Create(cTexts[TStatementsPropertiesText.AssignVia].Fmt([mName]), mEdits);
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
      TSyntaxKind.Call]) and mResolver.NodeType(AContext.Tree, mFileName, AReceiver, ASymbol, ATypeInfo, mTypeFound);
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
      if not mResolver.PropertyReadsField(ASymbol, mReadsField) then
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
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    // Typisierte Konstanten sind mit {$J+} beschreibbar; untypisierte nie.
    if mResolver.NodeType(AContext.Tree, mFileName, ATarget, mSymbol, mTypeInfo, mTypeFound) and
      (mSymbol.SymbolKind = TIndexSymbolKind.Constant) and (mSymbol.TypeName = '') then
    begin
      AReport.Add(TTextRange.Create(ATarget.StartPos, ATarget.EndPos),
        cTexts[TStatementsPropertiesText.ConstantTarget].Fmt([mSymbol.Name]), TRuleConfidence.High);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode.ChildCount > 0) then
        begin
          if mNode[0].Kind = TSyntaxKind.Identifier then
          begin
            CheckConstant(mNode[0]);
          end
          else
          begin
            CheckMember(mNode, mNode[0]);
          end;
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
  mFileName := ContextFileName(AContext);
  mTokens := AContext.Tree.Tokens;
  mLines := TTextLines.SplitLines(AContext.Text);
  mLineBreak := TTextLines.LineBreakOf(AContext.Text);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mResolver.PinTree(AContext.Tree, mFileName);
  try
    Visit(AContext.Tree.Root);
  finally
    mResolver.UnpinTree;
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
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;
  mTokens: TTokens;

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
    Result := PreviousCode(mTokens, AIndex);
    while (Result >= 0) and mTokens[Result].IsSymbol(']') do
    begin
      mOpen := Result;
      while (mOpen >= 0) and not mTokens[mOpen].IsSymbol('[') do
      begin
        AMarked := AMarked or MatchText(mTokens[mOpen].Text, ['weak', 'unsafe', 'WeakAttribute', 'UnsafeAttribute']);
        Dec(mOpen);
      end;
      Result := PreviousCode(mTokens, mOpen);
    end;
  end;

  // Token an der Stelle der Deklaration von ASymbol; -1 ohne.
  function DeclarationToken(const ASymbol: TResolvedSymbol): Integer;
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to High(mTokens) do
    begin
      if (mTokens[mIndex].StartPos.Line = ASymbol.SelectionRange.StartPos.Line) and
        (mTokens[mIndex].StartPos.Character = ASymbol.SelectionRange.StartPos.Character) then
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
    if (ASymbol.SymbolKind = TIndexSymbolKind.Field) and SameText(ASymbol.FileName, mFileName) then
    begin
      Result := DeclarationToken(ASymbol);
    end;
    if Result < 0 then
    begin
      Exit;
    end;
    mBefore := BeforeAttributes(Result, AMarked);
    mAfter := NextCode(mTokens, Result + 1);
    if ((mBefore >= 0) and mTokens[mBefore].IsSymbol(',')) or (mAfter > High(mTokens)) or
      not mTokens[mAfter].IsSymbol(':') then
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
      [TRuleEdit.Create(TTextRange.Create(mTokens[AField].StartPos, mTokens[AField].StartPos), '[' + AAttribute + '] '),
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
    Result := Result and mResolver.NodeType(AContext.Tree, mFileName, ATarget, ASymbol, ATypeInfo, ATypeFound) and
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
    for mIndex := 0 to High(mTokens) - 1 do
    begin
      if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mIndex].Text, 'Pointer') and
        mTokens[mIndex + 1].IsSymbol('(') then
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
  mTokens := AContext.Tree.Tokens;
  if not HasPointerCall then
  begin
    Exit;
  end;
  mFileName := ContextFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mResolver.PinTree(AContext.Tree, mFileName);
  try
    Visit(AContext.Tree.Root);
  finally
    mResolver.UnpinTree;
  end;
end;

{ TReadonlyPropertyAssignedRule }

function TReadonlyPropertyAssignedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cReadonlyPropertyAssignedRuleId, TRuleSeverity.Error,
    cTexts[TStatementsPropertiesText.NoWriteTitle].Text);
end;

class function TReadonlyPropertyAssignedRule.Accessors(const ASignature: string; out AHasRead,
  AHasWrite: Boolean): Boolean;
var
  mText, mWord: string;
  mIndex, mDepth: Integer;
begin
  // Indexparameter ausblenden: [read: Integer] wäre kein Zugriff.
  mText := '';
  mDepth := 0;
  for mIndex := 1 to Length(ASignature) do
  begin
    if ASignature[mIndex] = '[' then
    begin
      Inc(mDepth);
    end
    else if ASignature[mIndex] = ']' then
    begin
      Dec(mDepth);
    end
    else if mDepth = 0 then
    begin
      mText := mText + ASignature[mIndex];
    end;
  end;
  AHasRead := False;
  AHasWrite := False;
  for mWord in mText.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    if SameText(mWord, 'read') then
    begin
      AHasRead := True;
    end
    else if SameText(mWord, 'write') then
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
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;
  mLines: TArray<string>;
  mLocal: TUnitIndex;
  // Name -> gibt es eine Property ohne write (Bit 1) bzw. ohne read (Bit 2) mit diesem Namen?
  mSuspects: TDictionary<string, Integer>;
  // Signaturen der Properties der eigenen Unit je Name (klein); erst bei Bedarf.
  mLocalProperties: TObjectDictionary<string, TList<string>>;
  mActions: TClassActionContext;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function SuspectFlags(const AName: string): Integer;
  var
    mSymbol: TIndexSymbol;
    mSignatures: TList<string>;
    mSignature: string;
  begin
    if mSuspects.TryGetValue(LowerCase(AName), Result) then
    begin
      Exit;
    end;
    Result := 0;
    // Properties der eigenen Unit einmal nach Namen ordnen statt je Name über alle Symbole (große Units).
    if mLocalProperties = nil then
    begin
      mLocalProperties := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
      for mSymbol in mLocal.Symbols do
      begin
        if mSymbol.Kind = TIndexSymbolKind.Property_ then
        begin
          if not mLocalProperties.TryGetValue(LowerCase(mSymbol.Name), mSignatures) then
          begin
            mSignatures := TList<string>.Create;
            mLocalProperties.Add(LowerCase(mSymbol.Name), mSignatures);
          end;
          mSignatures.Add(mSymbol.Signature);
        end;
      end;
    end;
    if mLocalProperties.TryGetValue(LowerCase(AName), mSignatures) then
    begin
      for mSignature in mSignatures do
      begin
        Result := Result or AccessFlags(mSignature);
      end;
    end;
    // Der Teil aus dem Index hängt nur vom Namen ab: über alle Units des Laufs gemerkt (häufige Namen wie Count
    // haben Tausende Treffer und kamen sonst in jeder Unit neu).
    Result := Result or IndexPropertyFlags(AContext.NameFacts, AContext.Index, AName);
    mSuspects.Add(LowerCase(AName), Result);
  end;

  /// <summary>Wort hinter read in der Signatur ('' ohne); bei read FPunkt.X das ganze FPunkt.X.</summary>
  function ReadAccessor(const ASignature: string): string;
  var
    mWords: TArray<string>;
    mIndex: Integer;
  begin
    Result := '';
    mWords := ASignature.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty);
    for mIndex := 0 to High(mWords) - 1 do
    begin
      if SameText(mWords[mIndex], 'read') then
      begin
        Exit(mWords[mIndex + 1]);
      end;
    end;
  end;

  /// <summary>Klasse der Methode, in der ANode steht (TKunde bei TKunde.Laden); '' außerhalb.</summary>
  function MethodClass(ANode: TSyntaxNode): string;
  var
    mNode: TSyntaxNode;
  begin
    Result := '';
    mNode := ANode.Parent;
    while (mNode <> nil) and (mNode.Kind <> TSyntaxKind.RoutineDecl) do
    begin
      mNode := mNode.Parent;
    end;
    if (mNode <> nil) and (Pos('.', mNode.Name) > 0) then
    begin
      Result := Copy(mNode.Name, 1, LastDelimiter('.', mNode.Name) - 1);
    end;
  end;

  function SetterFix(const AProperty: TResolvedSymbol; out AFix: TRuleFix): Boolean;
  var
    mPlan: TAccessorPlan;
    mAction: TCodeAction;
    mLine, mColumn: Integer;
    mAccessor, mText: string;
  begin
    Result := False;
    mLine := AProperty.Range.StartPos.Line;
    if not SameText(AProperty.UnitName, mLocal.UnitName) or (AProperty.MaxArgs > 0) or
      (AProperty.Range.EndPos.Line <> mLine) or (mLine > High(mLines)) or StartsText('class ', AProperty.Signature) then
    begin
      Exit;
    end;
    mAccessor := ReadAccessor(AProperty.Signature);
    mText := LowerCase(mLines[mLine]);
    mColumn := Pos('read ' + LowerCase(mAccessor), mText);
    if (mAccessor = '') or (mColumn = 0) then
    begin
      Exit;
    end;
    mColumn := mColumn - 1 + Length('read ' + mAccessor);
    mPlan := Default(TAccessorPlan);
    mPlan.Kind := TAccessorKind.Setter;
    mPlan.PropertyName := AProperty.Name;
    mPlan.PropertyType := AProperty.TypeName;
    if AProperty.TypeArgs <> '' then
    begin
      mPlan.PropertyType := mPlan.PropertyType + '<' + AProperty.TypeArgs + '>';
    end;
    mPlan.MethodSection := 'private';
    if AContext.AccessorsProtected then
    begin
      mPlan.MethodSection := 'protected';
    end;
    if not TClassActions.CreateAccessor(AContext.Text, mLine, mPlan, mActions, mAction) then
    begin
      Exit;
    end;
    AFix := TRuleFix.Create(cTexts[TStatementsPropertiesText.CreateWrite].Fmt([mPlan.Name]), mAction.Edits +
      [TTextEdit.Create(TTextRange.Create(mLine, mColumn, mLine, mColumn), ' write ' + mPlan.Name)]);
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
    Result := mResolver.NodeType(AContext.Tree, mFileName, ATarget, ASymbol, mTypeInfo, mTypeFound) and
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
    Result := Result and mResolver.NodeType(AContext.Tree, mFileName, ATarget[0], mOwner, mOwnerType, mTypeFound) and
      mTypeFound;
    Result := Result and mResolver.FindMember(mOwnerType, 'Clear', mClear) and
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
    if InOwnMethod(AStatement, ATarget, ASymbol) and mResolver.PropertyReadsField(ASymbol, mReadsField) and
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
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound, mHasRead, mHasWrite: Boolean;
  begin
    if SuspectFlags(ANode.Name) and 2 = 0 then
    begin
      Exit;
    end;
    if mResolver.NodeType(AContext.Tree, mFileName, ANode, mSymbol, mTypeInfo, mTypeFound) and
      (mSymbol.SymbolKind = TIndexSymbolKind.Property_) and (mSymbol.TypeName <> '') and
      Accessors(mSymbol.Signature, mHasRead, mHasWrite) and not mHasRead then
    begin
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), cTexts[TStatementsPropertiesText.NoRead].Fmt(
        [mSymbol.Container, mSymbol.Name]), TRuleConfidence.High);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode, mTarget: TSyntaxNode;
    mWritten: Boolean;
    mPending: TStack<TSyntaxNode>;
    mPendingWritten: TStack<Boolean>;
  begin
    // Iterativ (Bericht M1): zu jedem Knoten auf dem Stapel, ob er geschrieben wird.
    mPending := TStack<TSyntaxNode>.Create;
    mPendingWritten := TStack<Boolean>.Create;
    try
      mPending.Push(ARoot);
      mPendingWritten.Push(False);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mWritten := mPendingWritten.Pop;
        if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode.ChildCount > 0) then
        begin
          mTarget := mNode[0];
          CheckWrite(mNode, mTarget);
          // Erst die Kinder des Ziels, dann die übrigen Kinder der Zuweisung (umgekehrt auf den Stapel).
          for mIndex := mNode.ChildCount - 1 downto 1 do
          begin
            mPending.Push(mNode[mIndex]);
            mPendingWritten.Push(False);
          end;
          // Das Ziel selbst wird geschrieben, bei Liste.Items[I] auch die Property davor.
          for mIndex := mTarget.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mTarget[mIndex]);
            mPendingWritten.Push((mTarget.Kind = TSyntaxKind.IndexAccess) and (mIndex = 0));
          end;
          Continue;
        end;
        if not mWritten and (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
        begin
          CheckRead(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
          mPendingWritten.Push(False);
        end;
      end;
    finally
      mPendingWritten.Free;
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mFileName := ContextFileName(AContext);
  mLines := TTextLines.SplitLines(AContext.Text);
  mActions := TClassActionContext.Default;
  mActions.Index := AContext.Index;
  mActions.Namespaces := AContext.Namespaces;
  mActions.DelphiVersion := AContext.DelphiVersion;
  mActions.Style := AContext.Formatting;
  mSuspects := TDictionary<string, Integer>.Create;
  mLocalProperties := nil;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  try
    mResolver.PinTree(AContext.Tree, mFileName);
    try
      mLocal := mResolver.ExtractedUnit(AContext.Tree, mFileName);
      Visit(AContext.Tree.Root);
    finally
      mResolver.UnpinTree;
    end;
  finally
    mLocalProperties.Free;
    mSuspects.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Statements.Properties', cTexts);

end.
