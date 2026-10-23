unit Atlas.Common.Rules.Builtin.Casts;

// Regeln für harte Typumwandlungen T(X) (Gruppe „Fehler finden“, Runde 69).
// Den Typ von X liefert TNameResolver.NodeType über TTypedScope; gemeldet wird
// nur, wenn beide Typen sicher bekannt sind und ihre Deklarationen immer mit
// der Stelle übersetzt werden:
//   unrelated-class-cast
//                     TButton(mEdit) mit einer Klasse als Ziel und einer Klasse
//                     als statischem Typ von mEdit, die weder Vorfahr noch
//                     Nachfahr voneinander sind (#1129). Die Umwandlung prüft
//                     nichts; der Zugriff zeigt auf ein Objekt mit anderem
//                     Aufbau. Gemeldet wird nur, wenn beide Vererbungsketten bis
//                     TObject bekannt sind. Still bleiben Interfaces, Zeiger,
//                     Klassenreferenzen (class of), TObject als Quelle sowie der
//                     Zugriffsklassen-Trick: Das Ziel und seine Vorfahren bis zu
//                     einem gemeinsamen Vorfahren deklarieren weder Felder noch
//                     neue virtuelle Methoden (THackControl = class(TControl)),
//                     der Aufbau ist also derselbe. Option allowTypes erlaubt
//                     weitere Typen bzw. Paare "Quelle=Ziel". Korrektur:
//                     (mEdit as TButton).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  UnrelatedClassCastRuleId = 'unrelated-class-cast';

type
  TUnrelatedClassCastRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Erlaubt die Option allowTypes die Umwandlung von ASource nach ATarget? Einträge sind Typnamen
    /// (Quelle oder Ziel) oder Paare "Quelle=Ziel", ohne Groß-/Kleinschreibung, mit oder ohne Unit-Präfix.
    /// </summary>
    class function Allowed(const AAllowTypes: TArray<string>; const ASource, ATarget: string): Boolean; static;
  end;

procedure RegisterCastRules(const ARegistry: TRuleRegistry);

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
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.TypedScope;

const
  // Längste Vererbungskette, die die Regel verfolgt.
  cMaxChain = 64;

/// <summary>Ist ASymbol eine Klassenreferenz (class of)? Der Index führt sie als ClassType ohne Vorfahren.
/// </summary>
function IsClassReference(const ASymbol: TResolvedSymbol): Boolean;
var
  mText: string;
  mEqual: Integer;
begin
  mText := LowerCase(ASymbol.Signature);
  mEqual := Pos('=', mText);
  Result := (mEqual > 0) and StartsStr('class of', Trim(Copy(mText, mEqual + 1, MaxInt)));
end;

/// <summary>Echte Klasse (kein Interface, keine Klassenreferenz, kein generischer Parameter).</summary>
function IsPlainClass(const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := not ASymbol.Builtin and (ASymbol.SymbolKind = TIndexSymbolKind.ClassType) and
    not IsClassReference(ASymbol) and (ASymbol.TypeParams = '');
end;

function SameType(const A, B: TResolvedSymbol): Boolean;
begin
  Result := SameText(A.QualifiedName, B.QualifiedName) and SameText(A.UnitName, B.UnitName);
end;

function IsTObject(const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := SameText(ASymbol.Name, 'TObject') and ((ASymbol.UnitName = '') or SameText(ASymbol.UnitName, 'System'));
end;

{ TUnrelatedClassCastRule }

function TUnrelatedClassCastRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UnrelatedClassCastRuleId, TRuleSeverity.Warning,
    'Harte Umwandlung zwischen nicht verwandten Klassen');
end;

class function TUnrelatedClassCastRule.Allowed(const AAllowTypes: TArray<string>; const ASource,
  ATarget: string): Boolean;

  function SameName(const AEntry, AName: string): Boolean;
  begin
    // "Vcl.StdCtrls.TButton" passt zu "TButton" und umgekehrt.
    Result := SameText(AEntry, AName) or EndsText('.' + AEntry, AName) or EndsText('.' + AName, AEntry);
  end;

var
  mEntry, mSource, mTarget: string;
  mEqual: Integer;
begin
  for mEntry in AAllowTypes do
  begin
    mEqual := Pos('=', mEntry);
    if mEqual = 0 then
    begin
      if SameName(Trim(mEntry), ASource) or SameName(Trim(mEntry), ATarget) then
        Exit(True);
      Continue;
    end;
    mSource := Trim(Copy(mEntry, 1, mEqual - 1));
    mTarget := Trim(Copy(mEntry, mEqual + 1, MaxInt));
    if SameName(mSource, ASource) and SameName(mTarget, ATarget) then
      Exit(True);
  end;
  Result := False;
end;

procedure TUnrelatedClassCastRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;
  mAllowTypes: TArray<string>;

  /// <summary>Kette von AType bis TObject (AType zuerst); False, wenn ein Vorfahr unbekannt ist.</summary>
  function Chain(const AType: TResolvedSymbol; out AChain: TArray<TResolvedSymbol>): Boolean;
  var
    mCurrent, mNext: TResolvedSymbol;
    mDepth: Integer;
  begin
    AChain := nil;
    mCurrent := AType;
    for mDepth := 0 to cMaxChain do
    begin
      AChain := AChain + [mCurrent];
      // Ohne Vorfahr erbt eine Klasse von TObject; TObject selbst steht ohne Index nicht im Baum.
      if IsTObject(mCurrent) or (Length(mCurrent.Ancestors) = 0) then
        Exit(True);
      if not mScope.Resolver.AncestorOf(mCurrent, mNext) or not IsPlainClass(mNext) then
        Exit(False);
      mCurrent := mNext;
    end;
    Result := False;
  end;

  function Contains(const AChain: TArray<TResolvedSymbol>; const AType: TResolvedSymbol): Boolean;
  var
    mItem: TResolvedSymbol;
  begin
    for mItem in AChain do
      if SameType(mItem, AType) then
        Exit(True);
    Result := False;
  end;

  /// <summary>Deklariert AType Felder oder neue virtuelle Methoden (ändert also den Aufbau des Objekts)?
  /// True auch, wenn die Mitglieder nicht lesbar sind.</summary>
  function ChangesLayout(const AType: TResolvedSymbol): Boolean;
  var
    mUnit: TUnitIndex;
    mSymbol: TIndexSymbol;
  begin
    if not mScope.Resolver.DeclaringUnit(AType, mUnit) then
      Exit(True);
    for mSymbol in mUnit.Symbols do
      if SameText(mSymbol.Container, AType.QualifiedName) and ((mSymbol.Kind = TIndexSymbolKind.Field) or
        ((mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and
        (mSymbol.HasDirective('virtual') or mSymbol.HasDirective('dynamic')))) then
        Exit(True);
    Result := False;
  end;

  /// <summary>Zugriffsklassen-Trick: Das Ziel und seine Vorfahren bis zu einem Vorfahren der Quelle ändern den
  /// Aufbau nicht.</summary>
  function SameLayout(const ATargetChain, ASourceChain: TArray<TResolvedSymbol>): Boolean;
  var
    mItem: TResolvedSymbol;
  begin
    for mItem in ATargetChain do
    begin
      if Contains(ASourceChain, mItem) then
        Exit(True);
      if ChangesLayout(mItem) then
        Exit(False);
    end;
    Result := False;
  end;

  /// <summary>Braucht der Ersatz "(X as T)" Klammern? Nur, wenn danach ein Zugriff folgt.</summary>
  function NeedsParens(ANode: TSyntaxNode): Boolean;
  var
    mParent: TSyntaxNode;
  begin
    mParent := ANode.Parent;
    Result := (mParent <> nil) and (mParent.ChildCount > 0) and (mParent[0] = ANode) and
      (mParent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Call,
      TSyntaxKind.Dereference]);
  end;

  procedure CheckCast(ANode: TSyntaxNode);
  var
    mArgument: TSyntaxNode;
    mTargetSymbol, mTargetType, mSourceSymbol, mSourceType: TResolvedSymbol;
    mTargetChain, mSourceChain: TArray<TResolvedSymbol>;
    mReplacement: string;
  begin
    // T(X): Bezeichner bzw. qualifizierter Name ohne Typargumente und genau ein Argument.
    if (ANode.ChildCount <> 2) or not (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      (ANode[0].FindChild(TSyntaxKind.GenericArgs) <> nil) then
      Exit;
    if not mScope.SureType(ANode, mTargetSymbol, mTargetType) or not mTargetSymbol.IsType or
      not IsPlainClass(mTargetType) then
      Exit;
    mArgument := Unwrapped(ANode[1]);
    if not mScope.SureType(mArgument, mSourceSymbol, mSourceType) or mSourceSymbol.IsType or
      not IsPlainClass(mSourceType) or IsTObject(mSourceType) or SameType(mSourceType, mTargetType) then
      Exit;
    if not Chain(mTargetType, mTargetChain) or not Chain(mSourceType, mSourceChain) then
      Exit;
    if Contains(mTargetChain, mSourceType) or Contains(mSourceChain, mTargetType) then
      Exit;
    if SameLayout(mTargetChain, mSourceChain) then
      Exit;
    if Allowed(mAllowTypes, mSourceType.QualifiedName, mTargetType.QualifiedName) then
      Exit;
    mReplacement := Format('%s as %s', [mScope.Text(mArgument), mScope.Text(ANode[0])]);
    if NeedsParens(ANode) then
      mReplacement := '(' + mReplacement + ')';
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
      Format('%s und %s sind nicht verwandt: Die Umwandlung zeigt auf ein Objekt mit anderem Aufbau.',
      [mSourceType.Name, mTargetType.Name]), TRuleConfidence.High,
      [TRuleFix.Create(Format('In %s umwandeln', [mReplacement]),
      [TTextEdit.Create(TTextRange.Create(ANode.StartPos, ANode.EndPos), mReplacement)])]);
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
        if mNode.Kind = TSyntaxKind.Call then
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
  mAllowTypes := TRuleOptions.Strings(AContext.Options, 'allowTypes', nil);
  mScope := TTypedScope.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    mScope.Free;
  end;
end;

procedure RegisterCastRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUnrelatedClassCastRule.Create);
end;

end.
