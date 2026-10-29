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
//   redundant-cast    TStringList(FZeilen) bzw. FZeilen as TStringList, wenn
//                     FZeilen schon als TStringList deklariert ist (#1139),
//                     sowie TObject(FStrom).Free (Option checkFree): Free ruft
//                     den virtuellen Destruktor und braucht keine Umwandlung.
//                     Gleich heißt: derselbe aufgelöste Typ und derselbe Name in
//                     der Deklaration der Quelle; Aliase (TFarbe = Integer)
//                     bleiben stumm, ebenso Konstanten, Routinen ohne Aufruf,
//                     überladene Routinen als Quelle, Argumente von Aufrufen,
//                     deren Ziel nicht genau eine bekannte Routine ist (die
//                     Umwandlung kann die Überladung wählen), Interfaces bei
//                     as (QueryInterface) und Free, das eine Klasse der Kette
//                     neu deklariert. Korrektur: die Umwandlung entfernen.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  UnrelatedClassCastRuleId = 'unrelated-class-cast';
  RedundantCastRuleId = 'redundant-cast';

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

  TRedundantCastRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
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

/// <summary>Kette von AType bis TObject (AType zuerst); False, wenn ein Vorfahr unbekannt ist.</summary>
function ClassChain(AResolver: TNameResolver; const AType: TResolvedSymbol;
  out AChain: TArray<TResolvedSymbol>): Boolean;
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
    if not AResolver.AncestorOf(mCurrent, mNext) or not IsPlainClass(mNext) then
      Exit(False);
    mCurrent := mNext;
  end;
  Result := False;
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
    if not ClassChain(mScope.Resolver, mTargetType, mTargetChain) or
      not ClassChain(mScope.Resolver, mSourceType, mSourceChain) then
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

{ TRedundantCastRule }

function TRedundantCastRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(RedundantCastRuleId, TRuleSeverity.Hint, 'Überflüssige Typumwandlung');
end;

procedure TRedundantCastRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;
  mCheckFree: Boolean;

  /// <summary>Letzter Teil eines qualifizierten Namens ("System.Classes.TStringList" → "TStringList").</summary>
  function LastName(const AName: string): string;
  var
    mDot: Integer;
  begin
    Result := Trim(AName);
    mDot := LastDelimiter('.', Result);
    if mDot > 0 then
      Result := Copy(Result, mDot + 1, MaxInt);
  end;

  /// <summary>Zieltyp der Umwandlung ANode: T(X) als Aufruf oder X as T; ATypeNode ist der Typname im Text,
  /// ASource der umgewandelte Ausdruck.</summary>
  function CastParts(ANode: TSyntaxNode; out ATypeNode, ASource: TSyntaxNode; out AIsAs: Boolean): Boolean;
  begin
    ATypeNode := nil;
    ASource := nil;
    AIsAs := (ANode.Kind = TSyntaxKind.BinaryExpr) and SameText(ANode.Name, 'as') and (ANode.ChildCount = 2);
    if AIsAs then
    begin
      ATypeNode := ANode[1];
      ASource := Unwrapped(ANode[0]);
    end
    else if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) then
    begin
      ATypeNode := ANode[0];
      ASource := Unwrapped(ANode[1]);
    end;
    Result := (ATypeNode <> nil) and (ASource <> nil) and
      (ATypeNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
      (ATypeNode.FindChild(TSyntaxKind.GenericArgs) = nil);
  end;

  /// <summary>Zieltyp ATypeNode der Umwandlung. Eingebaute Typen (Integer, string) und TObject ohne Index findet
  /// die Auflösung nicht; sie gelten nur, wenn der Name auf nichts anderes zeigt.</summary>
  function TargetOf(ATypeNode: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
  var
    mSymbol: TResolvedSymbol;
    mFound: Boolean;
  begin
    if mScope.SureType(ATypeNode, mSymbol, AType) then
      Exit(mSymbol.IsType);
    if (ATypeNode.Kind <> TSyntaxKind.Identifier) or mScope.Resolver.NodeType(AContext.Tree, mScope.FileName,
      ATypeNode, mSymbol, AType, mFound) then
      Exit(False);
    AType := Default(TResolvedSymbol);
    AType.Kind := TResolvedKind.Symbol;
    AType.Name := ATypeNode.Name;
    AType.UnitName := 'System';
    AType.Builtin := True;
    AType.SymbolKind := TIndexSymbolKind.RecordType;
    if SameText(ATypeNode.Name, 'TObject') then
      AType.SymbolKind := TIndexSymbolKind.ClassType;
    Result := SameText(ATypeNode.Name, 'TObject') or TNameResolver.IsBuiltinTypeName(ATypeNode.Name);
  end;

  /// <summary>Typ der Quelle sicher bekannt und als Wert verwendbar: keine Typen, keine Konstanten (untypisierte
  /// Konstanten ändern mit der Umwandlung ihren Typ), keine überladenen Routinen, Routinen nur als Aufruf.
  /// </summary>
  function SureSource(ASource: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
  begin
    Result := mScope.SureType(ASource, ASymbol, AType) and not ASymbol.IsType and
      not (ASymbol.SymbolKind in [TIndexSymbolKind.Constant, TIndexSymbolKind.EnumMember]);
    if Result and (ASymbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine,
      TIndexSymbolKind.Constructor_]) then
      Result := (ASource.Kind = TSyntaxKind.Call) and (ASymbol.Overloads = nil) and
        (Length(ASymbol.VariantParams) <= 1);
  end;

  /// <summary>Steht ANode als Argument in einem Aufruf, dessen Ziel nicht genau eine Routine ist? Bei
  /// Überladungen kann die Umwandlung die Auswahl steuern; bei unbekanntem Ziel (Assert.AreEqual aus einer
  /// Bibliothek ohne Index) ist das nicht auszuschließen.</summary>
  function InOverloadedCall(ANode: TSyntaxNode): Boolean;
  var
    mParent: TSyntaxNode;
  begin
    mParent := ANode.Parent;
    while (mParent <> nil) and (mParent.Kind = TSyntaxKind.ParenExpr) do
    begin
      ANode := mParent;
      mParent := mParent.Parent;
    end;
    Result := (mParent <> nil) and (mParent.Kind = TSyntaxKind.Call) and (mParent.ChildCount > 0) and
      (mParent[0] <> ANode) and
      (Length(mScope.Resolver.CallCandidates(AContext.Tree, mScope.FileName, mParent[0])) <> 1);
  end;

  /// <summary>Zu ersetzender Bereich: bei "(X as T)" samt Klammern, das Ergebnis ist ein einfacher Ausdruck.
  /// </summary>
  function ReplacedNode(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode;
    while (Result.Parent <> nil) and (Result.Parent.Kind = TSyntaxKind.ParenExpr) and
      (Result.Parent.ChildCount = 1) do
      Result := Result.Parent;
  end;

  procedure Report(ANode, ASource: TSyntaxNode; const AMessage: string);
  var
    mRange: TTextRange;
    mReplaced: TSyntaxNode;
  begin
    mReplaced := ReplacedNode(ANode);
    mRange := TTextRange.Create(mReplaced.StartPos, mReplaced.EndPos);
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), AMessage, TRuleConfidence.High,
      [TRuleFix.Create('Umwandlung entfernen', [TTextEdit.Create(mRange, mScope.Text(ASource))])]);
  end;

  /// <summary>Deklariert eine Klasse der Kette außer TObject ein eigenes Free?</summary>
  function DeclaresFree(const AChain: TArray<TResolvedSymbol>): Boolean;
  var
    mItem: TResolvedSymbol;
    mUnit: TUnitIndex;
    mSymbol: TIndexSymbol;
  begin
    for mItem in AChain do
    begin
      if IsTObject(mItem) then
        Continue;
      if not mScope.Resolver.DeclaringUnit(mItem, mUnit) then
        Exit(True);
      for mSymbol in mUnit.Symbols do
        if SameText(mSymbol.Container, mItem.QualifiedName) and SameText(mSymbol.Name, 'Free') then
          Exit(True);
    end;
    Result := False;
  end;

  /// <summary>Gleicher Typ: derselbe aufgelöste Typ und derselbe Name wie in der Deklaration der Quelle.
  /// </summary>
  function SameDeclared(const ASourceSymbol, ASourceType, ATargetType: TResolvedSymbol;
    ATypeNode: TSyntaxNode): Boolean;
  begin
    Result := SameType(ASourceType, ATargetType) and (ASourceSymbol.TypeName <> '') and
      SameText(LastName(ASourceSymbol.TypeName), LastName(mScope.Text(ATypeNode)));
  end;

  /// <summary>Gleichheit für Typen ohne Deklaration im Index (Integer, string): nur der Name.</summary>
  function SameBuiltin(const ASourceSymbol, ASourceType, ATargetType: TResolvedSymbol;
    ATypeNode: TSyntaxNode): Boolean;
  begin
    Result := ASourceType.Builtin and ATargetType.Builtin and (ASourceSymbol.TypeName <> '') and
      SameText(LastName(ASourceSymbol.TypeName), LastName(mScope.Text(ATypeNode))) and
      SameText(ASourceType.Name, ATargetType.Name);
  end;

  procedure CheckCast(ANode: TSyntaxNode);
  var
    mTypeNode, mSource: TSyntaxNode;
    mIsAs: Boolean;
    mTargetType, mSourceSymbol, mSourceType: TResolvedSymbol;
  begin
    if not CastParts(ANode, mTypeNode, mSource, mIsAs) then
      Exit;
    if not TargetOf(mTypeNode, mTargetType) then
      Exit;
    // as mit Interface ruft QueryInterface und kann ein anderes Objekt liefern.
    if mIsAs and not IsPlainClass(mTargetType) then
      Exit;
    if not SureSource(mSource, mSourceSymbol, mSourceType) then
      Exit;
    if not SameDeclared(mSourceSymbol, mSourceType, mTargetType, mTypeNode) and
      not SameBuiltin(mSourceSymbol, mSourceType, mTargetType, mTypeNode) then
      Exit;
    if InOverloadedCall(ReplacedNode(ANode)) then
      Exit;
    Report(ANode, mSource, Format('%s ist schon %s: Die Umwandlung ist überflüssig.',
      [mScope.Text(mSource), mScope.Text(mTypeNode)]));
  end;

  /// <summary>TObject(FStrom).Free: Umwandlung einer Klasse in eine Klasse nur für Free.</summary>
  procedure CheckFree(ANode: TSyntaxNode);
  var
    mCast, mTypeNode, mSource: TSyntaxNode;
    mIsAs: Boolean;
    mTargetType, mSourceSymbol, mSourceType: TResolvedSymbol;
    mTargetChain, mSourceChain: TArray<TResolvedSymbol>;
  begin
    if not SameText(ANode.Name, 'Free') or (ANode.ChildCount = 0) then
      Exit;
    // Free(…) mit Argumenten ist nicht TObject.Free.
    if (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.Call) and (ANode.Parent[0] = ANode) and
      (ANode.Parent.ChildCount > 1) then
      Exit;
    mCast := Unwrapped(ANode[0]);
    if not CastParts(mCast, mTypeNode, mSource, mIsAs) then
      Exit;
    if not TargetOf(mTypeNode, mTargetType) or not (IsPlainClass(mTargetType) or IsTObject(mTargetType)) then
      Exit;
    if not SureSource(mSource, mSourceSymbol, mSourceType) or not IsPlainClass(mSourceType) then
      Exit;
    // Gleicher Typ meldet CheckCast.
    if SameDeclared(mSourceSymbol, mSourceType, mTargetType, mTypeNode) then
      Exit;
    if not ClassChain(mScope.Resolver, mSourceType, mSourceChain) or DeclaresFree(mSourceChain) then
      Exit;
    if not IsTObject(mTargetType) and (not ClassChain(mScope.Resolver, mTargetType, mTargetChain) or
      DeclaresFree(mTargetChain)) then
      Exit;
    Report(mCast, mSource, Format('Free ruft den virtuellen Destruktor: Die Umwandlung von %s nach %s ist ' +
      'überflüssig.', [mScope.Text(mSource), mScope.Text(mTypeNode)]));
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
        if mNode.Kind in [TSyntaxKind.Call, TSyntaxKind.BinaryExpr] then
          CheckCast(mNode)
        else if mCheckFree and (mNode.Kind = TSyntaxKind.MemberAccess) then
          CheckFree(mNode);
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
  mCheckFree := TRuleOptions.Bool(AContext.Options, 'checkFree', True);
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
  ARegistry.Register(TRedundantCastRule.Create);
end;

end.
