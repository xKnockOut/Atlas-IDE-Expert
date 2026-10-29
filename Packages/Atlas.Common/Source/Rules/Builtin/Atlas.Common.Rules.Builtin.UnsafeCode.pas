unit Atlas.Common.Rules.Builtin.UnsafeCode;

// unsafe-code (#1378, Gruppe „Compiler vorab“): Code, den dcc aus der Zeit von
// Delphi für .NET als unsicher meldet. dcc schaltet diese Warnungen ab Werk
// ab; die Regel meldet nur, wo sie wie bei dcc an sind
// ({$WARN UNSAFE_CODE ON}, DCC_UNSAFE_CODE = true in der .dproj usw., siehe
// Rules.WarnSwitches):
//   @-Operator        @mWert auf eine Variable, ein Feld oder einen Parameter
//                     mit bekanntem Typ (wie W1047, UNSAFE_CODE). @ auf
//                     Routinen und Methoden bleibt still.
//   Umwandlung        TObject(mZeiger) bzw. TKunde(mZeiger) von einem
//                     untypisierten Pointer in eine Klasse (wie W1048,
//                     UNSAFE_CAST). TObject gilt auch ohne System im Index,
//                     solange der Name sich auf nichts anderes auflöst.
//                     Typisierte Zeiger, Umwandlungen als Argument
//                     (TObject(Pointer(I))) und Interfaces bleiben still.
// Gemeldet wird nur, wenn der Typ sicher bekannt ist und seine Deklaration
// immer mit der Stelle übersetzt wird (TTypedScope).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  UnsafeCodeRuleId = 'unsafe-code';

type
  TUnsafeCodeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterUnsafeCodeRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Rules.WarnSwitches;

const
  cUnsafeCode = 'UNSAFE_CODE';
  cUnsafeCast = 'UNSAFE_CAST';

/// <summary>Echte Klasse (kein Interface, keine Klassenreferenz, kein generischer Parameter).</summary>
function IsPlainClass(const ASymbol: TResolvedSymbol): Boolean;
var
  mText: string;
  mEqual: Integer;
begin
  Result := not ASymbol.Builtin and (ASymbol.SymbolKind = TIndexSymbolKind.ClassType) and (ASymbol.TypeParams = '');
  if not Result then
    Exit;
  // Klassenreferenzen (class of) führt der Index als ClassType ohne Vorfahren.
  mText := LowerCase(ASymbol.Signature);
  mEqual := Pos('=', mText);
  Result := not ((mEqual > 0) and StartsStr('class of', Trim(Copy(mText, mEqual + 1, MaxInt))));
end;

{ TUnsafeCodeRule }

function TUnsafeCodeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UnsafeCodeRuleId, TRuleSeverity.Warning,
    'Unsicherer Code: @-Operator oder Umwandlung von Pointer in eine Klasse (wie W1047, W1048)');
end;

procedure TUnsafeCodeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;
  mSwitches: TRuleWarnSwitches;

  /// <summary>Meldet AMessage an ANode, wenn die Warnung AName dort an ist.</summary>
  procedure Report(ANode: TSyntaxNode; const AName, AMessage: string);
  var
    mState: TRuleWarnState;
    mSeverity: TRuleSeverity;
  begin
    mState := mSwitches.StateAt(AName, False, mScope.TokenAtPosition(ANode.StartPos));
    if not TRuleWarnSwitches.Reported(mState) then
      Exit;
    mSeverity := TRuleSeverity.Default;
    if mState = TRuleWarnState.AsError then
      mSeverity := TRuleSeverity.Error;
    AReport.AddWithSeverity(TTextRange.Create(ANode.StartPos, ANode.EndPos), AMessage, mSeverity, nil);
  end;

  procedure CheckAddress(ANode: TSyntaxNode);
  var
    mOperand: TSyntaxNode;
    mSymbol, mType: TResolvedSymbol;
  begin
    if ANode.ChildCount <> 1 then
      Exit;
    mOperand := Unwrapped(ANode[0]);
    if (mOperand = nil) or (mOperand.Kind <> TSyntaxKind.Identifier) then
      Exit;
    if not mScope.SureType(mOperand, mSymbol, mType) or mSymbol.IsType or
      not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) then
      Exit;
    Report(ANode, cUnsafeCode, Format('@%s: Der @-Operator ist unsicherer Code (wie W1047).', [mOperand.Name]));
  end;

  /// <summary>Name der Klasse, in die der Aufruf ANode umwandelt; False, wenn ANode sicher keine Umwandlung in eine
  /// Klasse ist oder das nicht sicher feststeht.</summary>
  function TargetClass(ANode: TSyntaxNode; out AName: string): Boolean;
  var
    mTargetSymbol, mTargetType: TResolvedSymbol;
  begin
    AName := '';
    if mScope.SureType(ANode, mTargetSymbol, mTargetType) then
    begin
      Result := mTargetSymbol.IsType and IsPlainClass(mTargetType);
      if Result then
        AName := mTargetType.Name;
      Exit;
    end;
    // TObject ohne System im Index (Linter ohne RTL): nur, wenn der Name nichts anderes meint.
    Result := (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'TObject') and
      not mScope.Resolver.Resolve(AContext.Tree, mScope.FileName, ANode[0].StartPos).Found;
    if Result then
      AName := 'TObject';
  end;

  procedure CheckCast(ANode: TSyntaxNode);
  var
    mArgument: TSyntaxNode;
    mSourceSymbol, mSourceType: TResolvedSymbol;
    mTarget: string;
  begin
    // T(X): Bezeichner bzw. qualifizierter Name ohne Typargumente und genau ein Argument.
    if (ANode.ChildCount <> 2) or not (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      (ANode[0].FindChild(TSyntaxKind.GenericArgs) <> nil) then
      Exit;
    if not TargetClass(ANode, mTarget) then
      Exit;
    mArgument := Unwrapped(ANode[1]);
    if not mScope.SureType(mArgument, mSourceSymbol, mSourceType) or mSourceSymbol.IsType or
      not mSourceType.Builtin or not SameText(mSourceType.Name, 'Pointer') then
      Exit;
    Report(ANode, cUnsafeCast, Format('Umwandlung von Pointer nach %s ist unsicher (wie W1048).', [mTarget]));
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
        if mNode.Kind = TSyntaxKind.AddressOf then
          CheckAddress(mNode)
        else if mNode.Kind = TSyntaxKind.Call then
          CheckCast(mNode);
        for mIndex := mNode.ChildCount - 1 downto 0 do
          mPending.Push(mNode[mIndex]);
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  mSwitches := TRuleWarnSwitches.Create(AContext);
  try
    // Ohne eingeschaltete Warnung gibt es nichts zu melden; der Baum wird dann gar nicht aufgelöst.
    if not TRuleWarnSwitches.Reported(mSwitches.ProjectState(cUnsafeCode, False)) and
      not TRuleWarnSwitches.Reported(mSwitches.ProjectState(cUnsafeCast, False)) and
      not mSwitches.MentionsAny([cUnsafeCode, cUnsafeCast]) then
      Exit;
    mScope := TTypedScope.Create(AContext);
    try
      Visit(AContext.Tree.Root);
    finally
      mScope.Free;
    end;
  finally
    mSwitches.Free;
  end;
end;

procedure RegisterUnsafeCodeRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUnsafeCodeRule.Create);
end;

end.
