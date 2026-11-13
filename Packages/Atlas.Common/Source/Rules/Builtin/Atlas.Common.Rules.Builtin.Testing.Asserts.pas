unit Atlas.Common.Rules.Builtin.Testing.Asserts;

// Regeln aus Atlas.Common.Rules.Builtin.Testing (#1780); angemeldet werden sie dort. Nur in Testunits
// (uses DUnitX.TestFramework …):
//   dunitx-istrue-equality   Assert.IsTrue(A = B), Assert.IsFalse(A <> B), Assert.IsTrue(X = nil),
//                            Assert.IsTrue(Assigned(X)) und dasselbe mit not: Beim Fehlschlag meldet DUnitX nur,
//                            dass die Bedingung nicht gilt, ohne die Werte. Korrektur zu AreEqual bzw. AreNotEqual
//                            (Konstante vorn als erwarteter Wert) oder IsNull bzw. IsNotNull, die Meldung bleibt
//                            als weiteres Argument. Angeboten nur, wenn eine Überladung sicher passt: beide Seiten
//                            string, Boolean oder Ganzzahl bis Integer, bei nil und Assigned eine Klasse, ein
//                            Interface oder ein Zeiger. Sonst (Gleitkomma braucht ein Delta, Mengen, Records,
//                            unbekannte Typen) nur der Hinweis.
//   dunitx-swapped-expected  Assert.AreEqual, AreNotEqual, AreSame oder AreNotSame, deren erstes Argument kein
//                            Literal und keine Konstante ist, das zweite aber schon: erwartet und erhalten sind
//                            vertauscht, die Meldung beim Fehlschlag führt in die Irre. Korrektur tauscht die beiden
//                            Argumente.

interface

uses
  Atlas.Common.Rules.Contract;

const
  cDUnitXIsTrueEqualityRuleId = 'dunitx-istrue-equality';
  cDUnitXSwappedExpectedRuleId = 'dunitx-swapped-expected';

type
  TDUnitXIsTrueEqualityRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDUnitXSwappedExpectedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ExpressionTypes,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TAssertsText = (TitleEquality, TitleSwapped, Equality, Swapped, UseMethod, SwapArguments);

  /// <summary>Art eines Werts für die Wahl der Überladung von AreEqual.</summary>
  TValueKind = (Unknown, Integer_, String_, Boolean_);

const
  cTexts: array[TAssertsText] of TAtlasText = (
    (De: 'Assert.IsTrue mit Vergleich statt AreEqual'; En: 'Assert.IsTrue with a comparison instead of AreEqual'),
    (De: 'Erwarteter und erhaltener Wert vertauscht'; En: 'Expected and actual value swapped'),
    (De: '%s nennt beim Fehlschlag die verglichenen Werte nicht: %s zeigt erwartet und erhalten.';
     En: '%s does not report the compared values on failure: %s shows expected and actual.'),
    (De: '%s erwartet den erwarteten Wert zuerst: %s ist eine Konstante, %s nicht. Beim Fehlschlag vertauscht die ' +
      'Meldung erwartet und erhalten.';
     En: '%s takes the expected value first: %s is a constant, %s is not. On failure the message swaps expected ' +
      'and actual.'),
    (De: '%s verwenden'; En: 'Use %s'),
    (De: 'Argumente tauschen'; En: 'Swap the arguments'));

{$SCOPEDENUMS OFF}

const
  cOrderMethods: array[0..3] of string = ('AreEqual', 'AreNotEqual', 'AreSame', 'AreNotSame');
  // Ganzzahlen, für die die Überladung AreEqual(Integer) sicher passt (nicht Cardinal, Int64, NativeInt).
  cIntegerTypes: array[0..7] of string = ('Integer', 'LongInt', 'SmallInt', 'ShortInt', 'Byte', 'Word',
    'System.Integer', 'System.LongInt');
  cStringTypes: array[0..3] of string = ('string', 'UnicodeString', 'System.string', 'System.UnicodeString');
  cBooleanTypes: array[0..1] of string = ('Boolean', 'System.Boolean');
  cNullableTypes: array[0..3] of string = ('Pointer', 'TObject', 'IInterface', 'IUnknown');

type
  /// <summary>Vorschlag für die Bedingung in Assert.IsTrue bzw. Assert.IsFalse.</summary>
  TSuggestion = record
    /// <summary>AreEqual, AreNotEqual, IsNull oder IsNotNull.</summary>
    Method: string;
    /// <summary>Argumente ohne die Meldung, wie im Quelltext.</summary>
    Arguments: string;
    /// <summary>Passt eine Überladung sicher (Korrektur anbieten)?</summary>
    Safe: Boolean;
  end;

  /// <summary>Eine Prüfung einer Datei für eine der beiden Regeln.</summary>
  TAssertsCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FScope: TTypedScope;
    FTypes: TExpressionTypes;
    function Source(ANode: TSyntaxNode): string;
    function Range(ANode: TSyntaxNode): TTextRange;
    function MethodOf(ACall: TSyntaxNode; out APrefix: string): string;
    function NamePosition(ANode: TSyntaxNode): TTextPosition;
    function IsDeclaredConstant(ANode: TSyntaxNode): Boolean;
    function IsConstant(ANode: TSyntaxNode): Boolean;
    function TypeOf(ANode: TSyntaxNode): string;
    function KindOf(ANode: TSyntaxNode): TValueKind;
    function IsNullable(ANode: TSyntaxNode): Boolean;
    function SuggestNull(AValue: TSyntaxNode; AIsNull: Boolean): TSuggestion;
    function SuggestEqual(ACompare: TSyntaxNode; AEqual: Boolean): TSuggestion;
    function Suggest(ACondition: TSyntaxNode; APositive: Boolean; out ASuggestion: TSuggestion): Boolean;
    function Rest(ACall: TSyntaxNode; AFrom: Integer): string;
    procedure CheckCondition(ACall: TSyntaxNode; const APrefix, AMethod: string);
    procedure CheckOrder(ACall: TSyntaxNode; const APrefix, AMethod: string);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    /// <summary>AOrder: dunitx-swapped-expected, sonst dunitx-istrue-equality.</summary>
    procedure Run(AOrder: Boolean);
  end;

/// <summary>Assigned(X) mit genau einem Argument?</summary>
function IsAssignedCall(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Assigned');
end;

function IsNil(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind in [TSyntaxKind.Literal, TSyntaxKind.Identifier]) and SameText(ANode.Name, 'nil');
end;

/// <summary>Soll die Regel die Datei überhaupt ansehen?</summary>
function Applies(const AContext: TRuleContext): Boolean;
begin
  Result := (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) and ContainsText(AContext.Text, 'Assert.') and
    TUsesClauses.IsTestUnit(AContext.Tree.Tokens);
end;

procedure RunCheck(const AContext: TRuleContext; const AReport: IRuleReport; AOrder: Boolean);
var
  mCheck: TAssertsCheck;
begin
  if not Applies(AContext) then
  begin
    Exit;
  end;
  mCheck := TAssertsCheck.Create(AContext, AReport);
  try
    mCheck.Run(AOrder);
  finally
    mCheck.Free;
  end;
end;

{ TAssertsCheck }

constructor TAssertsCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mOptions: TExpressionTypeOptions;
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FScope := TTypedScope.Create(AContext);
  mOptions := TExpressionTypeOptions.Default;
  mOptions.Conversions := False;
  mOptions.ConstValue := False;
  FTypes := TExpressionTypes.Create(FScope.Resolver, AContext.Tree, FScope.FileName, AContext.Text, AContext.Index,
    mOptions);
end;

destructor TAssertsCheck.Destroy;
begin
  FTypes.Free;
  FScope.Free;
  inherited;
end;

function TAssertsCheck.Source(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TAssertsCheck.Range(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function TAssertsCheck.MethodOf(ACall: TSyntaxNode; out APrefix: string): string;
var
  mText: string;
  mDot: Integer;
begin
  // Assert.IsTrue → IsTrue mit APrefix 'Assert.'; DUnitX.TestFramework.Assert.IsTrue ebenso.
  Result := '';
  APrefix := '';
  if (ACall.ChildCount < 2) or (ACall[0].Kind <> TSyntaxKind.MemberAccess) or
    (ACall[0].FindChild(TSyntaxKind.GenericArgs) <> nil) then
  begin
    Exit;
  end;
  mText := StringReplace(FScope.Text(ACall[0]), ' ', '', [rfReplaceAll]);
  mDot := LastDelimiter('.', mText);
  if SameText(Copy(mText, 1, mDot), 'Assert.') or EndsText('.Assert.', Copy(mText, 1, mDot)) then
  begin
    APrefix := Copy(mText, 1, mDot);
    Result := Copy(mText, mDot + 1, MaxInt);
  end;
end;

function TAssertsCheck.NamePosition(ANode: TSyntaxNode): TTextPosition;
begin
  // Bei TFoo.cWert steht der Name am Ende des Knotens.
  Result := ANode.StartPos;
  if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.EndPos.Line = ANode.StartPos.Line) then
  begin
    Result := TTextPosition.Create(ANode.EndPos.Line, ANode.EndPos.Character - Length(ANode.Name));
  end;
end;

function TAssertsCheck.IsDeclaredConstant(ANode: TSyntaxNode): Boolean;
var
  mSymbol: TResolvedSymbol;
begin
  mSymbol := FScope.Resolver.Resolve(FContext.Tree, FScope.FileName, NamePosition(ANode));
  Result := (mSymbol.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and
    (mSymbol.SymbolKind in [TIndexSymbolKind.Constant, TIndexSymbolKind.EnumMember]);
end;

function TAssertsCheck.IsConstant(ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := Unwrapped(ANode);
  case mNode.Kind of
    TSyntaxKind.Literal:
      Result := True;
    TSyntaxKind.Identifier:
      Result := MatchText(mNode.Name, ['True', 'False', 'nil']) or IsDeclaredConstant(mNode);
    TSyntaxKind.MemberAccess:
      Result := IsDeclaredConstant(mNode);
    TSyntaxKind.UnaryExpr:
      Result := (mNode.ChildCount = 1) and IsConstant(mNode[0]);
    TSyntaxKind.BinaryExpr:
      Result := (mNode.ChildCount = 2) and IsConstant(mNode[0]) and IsConstant(mNode[1]);
  else
    Result := False;
  end;
end;

function TAssertsCheck.TypeOf(ANode: TSyntaxNode): string;
var
  mInfo: TExpressionTypeInfo;
begin
  mInfo := FTypes.Describe(ANode);
  Result := '';
  if mInfo.Found then
  begin
    Result := mInfo.TypeName;
    if mInfo.BaseName <> '' then
    begin
      Result := mInfo.BaseName;
    end;
  end;
end;

function TAssertsCheck.KindOf(ANode: TSyntaxNode): TValueKind;
var
  mNode: TSyntaxNode;
  mType: string;
begin
  mNode := Unwrapped(ANode);
  Result := TValueKind.Unknown;
  if (mNode.Kind = TSyntaxKind.Literal) and (mNode.Name <> '') and CharInSet(mNode.Name[1], ['''', '#']) then
  begin
    Exit(TValueKind.String_);
  end;
  // Length, High und Low eines dynamischen Arrays sind ab Delphi 12 NativeInt (wie dunitx-areequal-length).
  if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount = 2) and (mNode[0].Kind = TSyntaxKind.Identifier) and
    MatchText(mNode[0].Name, ['Length', 'High', 'Low']) and (KindOf(mNode[1]) <> TValueKind.String_) then
  begin
    Exit;
  end;
  mType := TypeOf(mNode);
  if MatchText(mType, cIntegerTypes) then
  begin
    Result := TValueKind.Integer_;
  end
  else if MatchText(mType, cStringTypes) then
  begin
    Result := TValueKind.String_;
  end
  else if MatchText(mType, cBooleanTypes) then
  begin
    Result := TValueKind.Boolean_;
  end;
end;

function TAssertsCheck.IsNullable(ANode: TSyntaxNode): Boolean;
var
  mSymbol, mType: TResolvedSymbol;
begin
  if FScope.SureType(Unwrapped(ANode), mSymbol, mType) and (mType.Kind <> TResolvedKind.None) and
    (mType.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType]) then
  begin
    Exit(True);
  end;
  Result := MatchText(TypeOf(Unwrapped(ANode)), cNullableTypes);
end;

function TAssertsCheck.SuggestNull(AValue: TSyntaxNode; AIsNull: Boolean): TSuggestion;
begin
  Result.Method := 'IsNotNull';
  if AIsNull then
  begin
    Result.Method := 'IsNull';
  end;
  Result.Arguments := Source(AValue);
  Result.Safe := IsNullable(AValue);
end;

function TAssertsCheck.SuggestEqual(ACompare: TSyntaxNode; AEqual: Boolean): TSuggestion;
var
  mExpected, mActual: TSyntaxNode;
  mKind: TValueKind;
begin
  // Die Konstante gehört als erwarteter Wert nach vorn; ohne Konstante links bleibt rechts der erwartete Wert.
  mExpected := ACompare[1];
  mActual := ACompare[0];
  if IsConstant(mActual) and not IsConstant(mExpected) then
  begin
    mExpected := ACompare[0];
    mActual := ACompare[1];
  end;
  Result.Method := 'AreNotEqual';
  if AEqual then
  begin
    Result.Method := 'AreEqual';
  end;
  Result.Arguments := Source(mExpected) + ', ' + Source(mActual);
  mKind := KindOf(mExpected);
  Result.Safe := (mKind <> TValueKind.Unknown) and (mKind = KindOf(mActual));
end;

function TAssertsCheck.Suggest(ACondition: TSyntaxNode; APositive: Boolean; out ASuggestion: TSuggestion): Boolean;
var
  mNode: TSyntaxNode;
  mPositive, mEqual: Boolean;
begin
  mNode := Unwrapped(ACondition);
  mPositive := APositive;
  while (mNode.Kind = TSyntaxKind.UnaryExpr) and SameText(mNode.Name, 'not') and (mNode.ChildCount = 1) do
  begin
    mPositive := not mPositive;
    mNode := Unwrapped(mNode[0]);
  end;
  Result := True;
  if IsAssignedCall(mNode) then
  begin
    ASuggestion := SuggestNull(mNode[1], not mPositive);
    Exit;
  end;
  Result := (mNode.Kind = TSyntaxKind.BinaryExpr) and MatchStr(mNode.Name, ['=', '<>']) and
    (mNode.ChildCount = 2);
  if not Result then
  begin
    Exit;
  end;
  mEqual := (mNode.Name = '=') = mPositive;
  if IsNil(mNode[1]) then
  begin
    ASuggestion := SuggestNull(mNode[0], mEqual);
  end
  else if IsNil(mNode[0]) then
  begin
    ASuggestion := SuggestNull(mNode[1], mEqual);
  end
  else
  begin
    ASuggestion := SuggestEqual(mNode, mEqual);
  end;
end;

function TAssertsCheck.Rest(ACall: TSyntaxNode; AFrom: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := AFrom to ACall.ChildCount - 1 do
  begin
    Result := Result + ', ' + Source(ACall[mIndex]);
  end;
end;

procedure TAssertsCheck.CheckCondition(ACall: TSyntaxNode; const APrefix, AMethod: string);
var
  mSuggestion: TSuggestion;
  mFixes: TArray<TRuleFix>;
begin
  if not Suggest(ACall[1], SameText(AMethod, 'IsTrue'), mSuggestion) then
  begin
    Exit;
  end;
  mFixes := nil;
  if mSuggestion.Safe then
  begin
    mFixes := [TRuleFix.Create(cTexts[TAssertsText.UseMethod].Fmt([APrefix + mSuggestion.Method]),
      [TTextEdit.Create(Range(ACall), APrefix + mSuggestion.Method + '(' + mSuggestion.Arguments + Rest(ACall, 2) +
      ')')], True)];
  end;
  FReport.Add(Range(ACall[0]), cTexts[TAssertsText.Equality].Fmt([APrefix + AMethod, APrefix + mSuggestion.Method]),
    TRuleConfidence.High, mFixes);
end;

procedure TAssertsCheck.CheckOrder(ACall: TSyntaxNode; const APrefix, AMethod: string);
var
  mFix: TRuleFix;
begin
  if (ACall.ChildCount < 3) or IsConstant(ACall[1]) or not IsConstant(ACall[2]) then
  begin
    Exit;
  end;
  mFix := TRuleFix.Create(cTexts[TAssertsText.SwapArguments].Text, [TTextEdit.Create(Range(ACall[1]),
    Source(ACall[2])), TTextEdit.Create(Range(ACall[2]), Source(ACall[1]))], True);
  FReport.Add(Range(ACall[0]), cTexts[TAssertsText.Swapped].Fmt([APrefix + AMethod, Source(ACall[2]),
    Source(ACall[1])]), TRuleConfidence.High, [mFix]);
end;

procedure TAssertsCheck.Run(AOrder: Boolean);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
  mPrefix, mMethod: string;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(FContext.Tree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.Call then
      begin
        mMethod := MethodOf(mNode, mPrefix);
        if AOrder and MatchText(mMethod, cOrderMethods) then
        begin
          CheckOrder(mNode, mPrefix, mMethod);
        end
        else if not AOrder and MatchText(mMethod, ['IsTrue', 'IsFalse']) then
        begin
          CheckCondition(mNode, mPrefix, mMethod);
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

{ TDUnitXIsTrueEqualityRule }

function TDUnitXIsTrueEqualityRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDUnitXIsTrueEqualityRuleId, TRuleSeverity.Hint,
    cTexts[TAssertsText.TitleEquality].Text);
end;

procedure TDUnitXIsTrueEqualityRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  RunCheck(AContext, AReport, False);
end;

{ TDUnitXSwappedExpectedRule }

function TDUnitXSwappedExpectedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDUnitXSwappedExpectedRuleId, TRuleSeverity.Hint,
    cTexts[TAssertsText.TitleSwapped].Text);
end;

procedure TDUnitXSwappedExpectedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  RunCheck(AContext, AReport, True);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Testing.Asserts', cTexts);

end.
