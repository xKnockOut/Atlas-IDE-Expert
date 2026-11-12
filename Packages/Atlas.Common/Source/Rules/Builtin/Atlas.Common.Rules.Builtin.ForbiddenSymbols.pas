unit Atlas.Common.Rules.Builtin.ForbiddenSymbols;

// Projektverbote für Symbole aus atlas.json (#1133, Gruppe „Architektur“):
//   forbidden-symbol  Verwendung einer Routine, eines Typs, einer Konstanten,
//                     eines Felds, einer Property, eines Aufzählungswerts oder
//                     eines Bezeichners aus der Liste "symbols". Verglichen
//                     wird der voll qualifizierte Name aus der Namensauflösung
//                     (Unit.Typ.Mitglied), nicht der Text: FileExists trifft
//                     System.SysUtils.FileExists, eine eigene Methode gleichen
//                     Namens nicht. Ein Eintrag darf den Namen auch ab einer
//                     Punktgrenze kürzen (TThread.Queue) und * enthalten.
//                     Bezeichner aus System ohne Quelltext (Writeln, Halt …)
//                     gelten als System.<Name>. Ist der linke Teil eines
//                     qualifizierten Namens gar nicht auflösbar (Unit nicht
//                     indexiert), vergleicht die Regel den geschriebenen Namen
//                     mit dem Ende des Eintrags (TThread.Queue gegen
//                     System.Classes.TThread.Queue). Ohne Liste ist die Regel
//                     stumm. Je Eintrag: message, replacement (Korrektur),
//                     severity, units (Unit-Muster, "!" schließt aus),
//                     firstArgument (nur mit diesem ersten Argument, z. B. nil)
//                     und allowFirstArgument (erlaubt mit diesem ersten
//                     Argument, z. B. ErrOutput); beide vergleichen den Text
//                     des Arguments oder den Namen seines Typs (TextFile).

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cForbiddenSymbolRuleId = 'forbidden-symbol';

type
  /// <summary>Art eines Eintrags; Any = jede aufgelöste Art.</summary>
  TForbiddenKind = (Any, Routine, Type_, Constant, Field, Property_, EnumValue, Identifier);

  /// <summary>Ein Eintrag der Option symbols.</summary>
  TForbiddenSymbol = record
    Name: string;
    Kind: TForbiddenKind;
    Message: string;
    Replacement: string;
    Severity: TRuleSeverity;
    Units: TArray<string>;
    FirstArgument: TArray<string>;
    AllowFirstArgument: TArray<string>;
    /// <summary>Gilt der Eintrag in der Unit AUnitName?</summary>
    function AppliesTo(const AUnitName: string): Boolean;
    /// <summary>Passt der Eintrag auf den voll qualifizierten Namen AFullName (ganz oder ab einer Punktgrenze)?
    /// </summary>
    function MatchesName(const AFullName: string): Boolean;
    /// <summary>Passt das Ende des Eintrags auf den geschriebenen, nicht auflösbaren Namen AWritten (A.B)?
    /// </summary>
    function MatchesTail(const AWritten: string): Boolean;
    /// <summary>Kann der Eintrag einen Namen treffen, der auf ALastName endet? Vorfilter vor der Auflösung.
    /// </summary>
    function MayMatch(const ALastName: string): Boolean;
  end;

  TForbiddenSymbolRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Einträge der Option symbols; ungültige Einträge (ohne name) fehlen, der Konfigurationsparser meldet
    /// sie.</summary>
    class function ParseSymbols(const AOptions: string): TArray<TForbiddenSymbol>; static;
    /// <summary>Art zum Text von "kind" (routine, type …); False bei unbekanntem Text.</summary>
    class function TryParseKind(const AText: string; out AKind: TForbiddenKind): Boolean; static;
  end;

procedure RegisterForbiddenSymbolRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.SystemIntrinsics,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Json;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TForbiddenSymbolsText = (Title, ForbiddenReason, Forbidden, ReplaceWith);

const
  cTexts: array[TForbiddenSymbolsText] of TAtlasText = (
    (De: 'Verbotenes Symbol aus atlas.json verwendet'; En: 'Forbidden symbol from atlas.json used'),
    (De: '%s ist in diesem Projekt verboten: %s (atlas.json › forbidden-symbol).';
     En: '%s is forbidden in this project: %s (atlas.json › forbidden-symbol).'),
    (De: '%s ist in diesem Projekt verboten (atlas.json › forbidden-symbol).';
     En: '%s is forbidden in this project (atlas.json › forbidden-symbol).'),
    (De: 'Durch %s ersetzen'; En: 'Replace with %s'));

{$SCOPEDENUMS OFF}

const
  cKindNames: array[TForbiddenKind] of string = ('', 'routine', 'type', 'constant', 'field', 'property', 'enumValue',
    'identifier');
  cTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];

type
  /// <summary>Auflösung eines Knotens, einmal je Knoten und nur bei Bedarf.</summary>
  TNodeLookup = record
    Tried: Boolean;
    /// <summary>Symbol bekannt (aufgelöst oder Bezeichner aus System ohne Quelltext).</summary>
    HasSymbol: Boolean;
    Resolved: Boolean;
    /// <summary>Qualifizierter Name, dessen linker Teil nicht auflösbar ist.</summary>
    LeftUnknown: Boolean;
    Symbol: TResolvedSymbol;
    Names: TArray<string>;
  end;

function ReadStrings(const AObject: TJSONObject; const AName: string): TArray<string>;
var
  mList: TJSONArray;
  mItem: TJSONValue;
begin
  Result := nil;
  if not AObject.TryGetValue<TJSONArray>(AName, mList) then
  begin
    Exit;
  end;
  for mItem in mList do
  begin
    if mItem is TJSONString then
    begin
      Result := Result + [TJSONString(mItem).Value];
    end;
  end;
end;

function ParseSeverity(const AText: string): TRuleSeverity;
var
  mText: string;
begin
  mText := LowerCase(Trim(AText));
  if mText = 'off' then
  begin
    Result := TRuleSeverity.Off;
  end
  else if mText = 'hint' then
  begin
    Result := TRuleSeverity.Hint;
  end
  else if (mText = 'info') or (mText = 'information') then
  begin
    Result := TRuleSeverity.Information;
  end
  else if mText = 'warning' then
  begin
    Result := TRuleSeverity.Warning;
  end
  else if mText = 'error' then
  begin
    Result := TRuleSeverity.Error;
  end
  else
  begin
    Result := TRuleSeverity.Default;
  end;
end;

function LastSegment(const AName: string): string;
var
  mDot: Integer;
begin
  mDot := LastDelimiter('.', AName);
  Result := Copy(AName, mDot + 1, MaxInt);
end;

/// <summary>Name ohne Unit-Präfix (System.TextFile → TextFile).</summary>
function WithoutUnit(const AName: string): string;
begin
  Result := LastSegment(AName);
end;

{ TForbiddenSymbol }

function TForbiddenSymbol.AppliesTo(const AUnitName: string): Boolean;
var
  mPattern: string;
  mPositive, mHit: Boolean;
begin
  mPositive := False;
  mHit := False;
  for mPattern in Units do
  begin
    if StartsStr('!', mPattern) then
    begin
      if MatchesGlob(Copy(mPattern, 2, MaxInt), AUnitName) then
      begin
        Exit(False);
      end;
    end
    else
    begin
      mPositive := True;
      if MatchesGlob(mPattern, AUnitName) then
      begin
        mHit := True;
      end;
    end;
  end;
  Result := mHit or not mPositive;
end;

function TForbiddenSymbol.MatchesName(const AFullName: string): Boolean;
var
  mRest: string;
  mDot: Integer;
begin
  mRest := AFullName;
  repeat
    if MatchesGlob(Name, mRest) then
    begin
      Exit(True);
    end;
    mDot := Pos('.', mRest);
    if mDot = 0 then
    begin
      Break;
    end;
    mRest := Copy(mRest, mDot + 1, MaxInt);
  until False;
  Result := False;
end;

function TForbiddenSymbol.MatchesTail(const AWritten: string): Boolean;
var
  mPattern, mWritten: TArray<string>;
  mTail: string;
  mIndex: Integer;
begin
  mPattern := Name.Split(['.']);
  mWritten := AWritten.Split(['.']);
  if (Length(mWritten) < 2) or (Length(mPattern) < Length(mWritten)) then
  begin
    Exit(False);
  end;
  mTail := '';
  for mIndex := Length(mPattern) - Length(mWritten) to High(mPattern) do
  begin
    if mTail <> '' then
    begin
      mTail := mTail + '.';
    end;
    mTail := mTail + mPattern[mIndex];
  end;
  Result := MatchesGlob(mTail, AWritten);
end;

function TForbiddenSymbol.MayMatch(const ALastName: string): Boolean;
begin
  Result := MatchesGlob(LastSegment(Name), ALastName);
end;

{ TForbiddenSymbolRule }

function TForbiddenSymbolRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cForbiddenSymbolRuleId, TRuleSeverity.Warning,
    cTexts[TForbiddenSymbolsText.Title].Text);
end;

class function TForbiddenSymbolRule.TryParseKind(const AText: string; out AKind: TForbiddenKind): Boolean;
var
  mKind: TForbiddenKind;
begin
  for mKind := Low(TForbiddenKind) to High(TForbiddenKind) do
  begin
    if SameText(cKindNames[mKind], AText) then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  AKind := TForbiddenKind.Any;
  Result := False;
end;

class function TForbiddenSymbolRule.ParseSymbols(const AOptions: string): TArray<TForbiddenSymbol>;
var
  mValue: TJSONValue;
  mList: TJSONArray;
  mItem: TJSONValue;
  mEntry: TForbiddenSymbol;
begin
  Result := nil;
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AOptions);
  try
    if not ((mValue is TJSONObject) and TJSONObject(mValue).TryGetValue<TJSONArray>('symbols', mList)) then
    begin
      Exit;
    end;
    for mItem in mList do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mEntry := Default(TForbiddenSymbol);
      mEntry.Name := Trim(TJsonRead.Text(TJSONObject(mItem), 'name'));
      if (mEntry.Name = '') or not TryParseKind(TJsonRead.Text(TJSONObject(mItem), 'kind'), mEntry.Kind) then
      begin
        Continue;
      end;
      mEntry.Message := TJsonRead.Text(TJSONObject(mItem), 'message');
      mEntry.Replacement := TJsonRead.Text(TJSONObject(mItem), 'replacement');
      mEntry.Severity := ParseSeverity(TJsonRead.Text(TJSONObject(mItem), 'severity'));
      mEntry.Units := ReadStrings(TJSONObject(mItem), 'units');
      mEntry.FirstArgument := ReadStrings(TJSONObject(mItem), 'firstArgument');
      mEntry.AllowFirstArgument := ReadStrings(TJSONObject(mItem), 'allowFirstArgument');
      Result := Result + [mEntry];
    end;
  finally
    mValue.Free;
  end;
end;

procedure TForbiddenSymbolRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mEntries: TArray<TForbiddenSymbol>;
  mScope: TTypedScope;

  /// <summary>Deklaration des Ausdrucks ANode (auch Unit-Namen und Typen); False, wenn nicht auflösbar.</summary>
  function Resolved(ANode: TSyntaxNode; out ASymbol: TResolvedSymbol): Boolean;
  var
    mType: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    Result := mScope.Resolver.NodeType(AContext.Tree, mScope.FileName, ANode, ASymbol, mType, mTypeFound);
  end;

  function KindMatches(AKind: TForbiddenKind; const ASymbol: TResolvedSymbol): Boolean;
  begin
    case AKind of
      TForbiddenKind.Any:
        Result := True;
      TForbiddenKind.Routine:
        Result := ASymbol.SymbolKind in [TIndexSymbolKind.Routine, TIndexSymbolKind.Method,
          TIndexSymbolKind.Constructor_];
      TForbiddenKind.Type_:
        Result := ASymbol.SymbolKind in cTypeKinds;
      TForbiddenKind.Constant:
        Result := ASymbol.SymbolKind = TIndexSymbolKind.Constant;
      TForbiddenKind.Field:
        Result := ASymbol.SymbolKind = TIndexSymbolKind.Field;
      TForbiddenKind.Property_:
        Result := ASymbol.SymbolKind = TIndexSymbolKind.Property_;
      TForbiddenKind.EnumValue:
        Result := ASymbol.SymbolKind = TIndexSymbolKind.EnumMember;
    else
      Result := False;
    end;
  end;

  /// <summary>Voll qualifizierte Namen von ASymbol: Unit.Typ.Name; Aufzählungswerte auch Unit.Name.</summary>
  function FullNames(const ASymbol: TResolvedSymbol): TArray<string>;
  begin
    Result := [ASymbol.UnitName + '.' + ASymbol.QualifiedName];
    if (ASymbol.SymbolKind = TIndexSymbolKind.EnumMember) and (ASymbol.Container <> '') then
    begin
      Result := Result + [ASymbol.UnitName + '.' + ASymbol.Name];
    end;
  end;

  /// <summary>Geschriebener Name A.B.C von ANode; '' bei anderen Ausdrücken (Aufruf, Index, Typargumente).
  /// </summary>
  function WrittenName(ANode: TSyntaxNode): string;
  var
    mNode: TSyntaxNode;
  begin
    Result := '';
    mNode := ANode;
    while (mNode.Kind = TSyntaxKind.MemberAccess) and (mNode.ChildCount = 1) do
    begin
      Result := '.' + mNode.Name + Result;
      mNode := mNode[0];
    end;
    if (mNode.Kind = TSyntaxKind.Identifier) and (mNode.ChildCount = 0) then
    begin
      Result := mNode.Name + Result;
    end
    else
    begin
      Result := '';
    end;
  end;

  function Leftmost(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode;
    while (Result.Kind = TSyntaxKind.MemberAccess) and (Result.ChildCount > 0) do
    begin
      Result := Result[0];
    end;
  end;

  /// <summary>Erstes Argument, wenn ANode aufgerufen wird; nil ohne.</summary>
  function FirstArgument(ANode: TSyntaxNode): TSyntaxNode;
  var
    mParent: TSyntaxNode;
  begin
    mParent := ANode.Parent;
    if (mParent <> nil) and (mParent.Kind = TSyntaxKind.Call) and (mParent.ChildCount > 1) and
      (mParent[0] = ANode) then
    begin
      Result := Unwrapped(mParent[1]);
    end
    else
    begin
      Result := nil;
    end;
  end;

  /// <summary>Passt das Argument AArgument auf einen der Einträge (Text oder Typname)?</summary>
  function ArgumentIn(AArgument: TSyntaxNode; const AItems: TArray<string>): Boolean;
  var
    mItem, mText, mTypeName: string;
    mSymbol, mType: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    if AArgument = nil then
    begin
      Exit(False);
    end;
    mText := mScope.Text(AArgument);
    mTypeName := '';
    if mScope.Resolver.NodeType(AContext.Tree, mScope.FileName, AArgument, mSymbol, mType, mTypeFound) then
    begin
      if mTypeFound then
      begin
        mTypeName := mType.Name;
      end
      else
      begin
        mTypeName := WithoutUnit(mSymbol.TypeName);
      end;
    end;
    for mItem in AItems do
    begin
      if SameText(mItem, mText) or ((mTypeName <> '') and SameText(WithoutUnit(mItem), mTypeName)) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  function ArgumentsAllow(const AEntry: TForbiddenSymbol; ANode: TSyntaxNode): Boolean;
  var
    mArgument: TSyntaxNode;
  begin
    if (AEntry.FirstArgument = nil) and (AEntry.AllowFirstArgument = nil) then
    begin
      Exit(True);
    end;
    mArgument := FirstArgument(ANode);
    if (AEntry.FirstArgument <> nil) and not ArgumentIn(mArgument, AEntry.FirstArgument) then
    begin
      Exit(False);
    end;
    Result := not ArgumentIn(mArgument, AEntry.AllowFirstArgument);
  end;

  /// <summary>Bereich des Namens, den der Ersatz ersetzt: der ganze Ausdruck, wenn davor eine Unit oder ein Typ
  /// steht, sonst nur das Mitglied hinter dem letzten Punkt.</summary>
  function ReplacedRange(ANode: TSyntaxNode; out ARange: TTextRange): Boolean;
  var
    mOwner: TResolvedSymbol;
    mStart: TTextPosition;
  begin
    ARange := TTextRange.Create(ANode.StartPos, ANode.EndPos);
    Result := True;
    if ANode.Kind <> TSyntaxKind.MemberAccess then
    begin
      Exit;
    end;
    if Resolved(ANode[0], mOwner) and ((mOwner.Kind = TResolvedKind.UnitName) or mOwner.IsType) then
    begin
      Exit;
    end;
    // Nur das Mitglied: Es steht am Ende des Ausdrucks in derselben Zeile.
    mStart := ANode.EndPos;
    mStart.Character := mStart.Character - Length(ANode.Name);
    Result := (mStart.Character >= 0) and SameText(Copy(AContext.Text, ANode.EndOffset - Length(ANode.Name) + 1,
      Length(ANode.Name)), ANode.Name);
    ARange := TTextRange.Create(mStart, ANode.EndPos);
  end;

  procedure Report(const AEntry: TForbiddenSymbol; ANode: TSyntaxNode; const AShown: string);
  var
    mMessage: string;
    mFixes: TArray<TRuleFix>;
    mRange: TTextRange;
  begin
    if AEntry.Message <> '' then
    begin
      mMessage := cTexts[TForbiddenSymbolsText.ForbiddenReason].Fmt([AShown, AEntry.Message]);
    end
    else
    begin
      mMessage := cTexts[TForbiddenSymbolsText.Forbidden].Fmt([AShown]);
    end;
    mFixes := nil;
    if (AEntry.Replacement <> '') and ReplacedRange(ANode, mRange) then
    begin
      mFixes := [TRuleFix.Create(cTexts[TForbiddenSymbolsText.ReplaceWith].Fmt([AEntry.Replacement]),
        [TTextEdit.Create(mRange, AEntry.Replacement)])];
    end;
    AReport.AddWithSeverity(TTextRange.Create(ANode.StartPos, ANode.EndPos), mMessage, AEntry.Severity, mFixes);
  end;

  /// <summary>Symbol von ANode: aufgelöst, Bezeichner aus System ohne Quelltext oder (AResolved False) nicht
  /// auflösbar.</summary>
  function SymbolOf(ANode: TSyntaxNode; out ASymbol: TResolvedSymbol; out AResolved: Boolean): Boolean;
  var
    mIntrinsics: TArray<TSystemIntrinsic>;
  begin
    AResolved := False;
    if ANode.Kind = TSyntaxKind.TypeReference then
    begin
      ASymbol := mScope.Resolver.ResolveChain(AContext.Tree, mScope.FileName, ANode.Name.Split(['.']),
        ANode.StartOffset);
      AResolved := ASymbol.Kind <> TResolvedKind.None;
    end
    else
    begin
      AResolved := Resolved(ANode, ASymbol);
    end;
    if AResolved then
    begin
      Exit(ASymbol.Kind = TResolvedKind.Symbol);
    end;
    // Writeln, Halt …: in System ohne Deklaration im Quelltext; ein eigener gleichnamiger Name wäre aufgelöst.
    mIntrinsics := TSystemIntrinsics.Find(ANode.Name);
    Result := (ANode.Kind = TSyntaxKind.Identifier) and (Length(mIntrinsics) > 0);
    if Result then
    begin
      ASymbol := Default(TResolvedSymbol);
      ASymbol.Kind := TResolvedKind.Symbol;
      ASymbol.Name := mIntrinsics[0].Name;
      ASymbol.UnitName := 'System';
      ASymbol.SymbolKind := mIntrinsics[0].Kind;
      ASymbol.Builtin := True;
      AResolved := True;
    end;
  end;

  /// <summary>Löst ANode beim ersten Bedarf auf (ALookup.Tried); AWritten ist der geschriebene Name.</summary>
  procedure Lookup(ANode: TSyntaxNode; const AWritten: string; var ALookup: TNodeLookup);
  var
    mLeft: TResolvedSymbol;
  begin
    if ALookup.Tried then
    begin
      Exit;
    end;
    ALookup.Tried := True;
    ALookup.HasSymbol := SymbolOf(ANode, ALookup.Symbol, ALookup.Resolved);
    if ALookup.HasSymbol then
    begin
      ALookup.Names := FullNames(ALookup.Symbol);
    end;
    // Linker Teil gar nicht auflösbar (Unit nicht indexiert): Dann zählt der geschriebene Name.
    ALookup.LeftUnknown := not ALookup.Resolved and (Pos('.', AWritten) > 0) and
      not Resolved(Leftmost(ANode), mLeft);
  end;

  function Hits(const AEntry: TForbiddenSymbol; ANode: TSyntaxNode; const AWritten: string;
    var ALookup: TNodeLookup): Boolean;
  var
    mName: string;
  begin
    if AEntry.Kind = TForbiddenKind.Identifier then
    begin
      Exit(MatchesGlob(AEntry.Name, ANode.Name) or ((AWritten <> '') and AEntry.MatchesName(AWritten)));
    end;
    Lookup(ANode, AWritten, ALookup);
    if ALookup.LeftUnknown then
    begin
      Exit(AEntry.MatchesTail(AWritten));
    end;
    if not ALookup.HasSymbol or not KindMatches(AEntry.Kind, ALookup.Symbol) then
    begin
      Exit(False);
    end;
    for mName in ALookup.Names do
    begin
      if AEntry.MatchesName(mName) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  procedure CheckNode(ANode: TSyntaxNode);
  var
    mEntry: TForbiddenSymbol;
    mWritten, mShown: string;
    mLookup: TNodeLookup;
  begin
    if ANode.Kind = TSyntaxKind.TypeReference then
    begin
      mWritten := ANode.Name;
    end
    else
    begin
      mWritten := WrittenName(ANode);
    end;
    mShown := mWritten;
    if mShown = '' then
    begin
      mShown := ANode.Name;
    end;
    mLookup := Default(TNodeLookup);
    // Vorfilter nach dem letzten Namensteil: aufgelöst wird nur, was ein Eintrag treffen kann.
    for mEntry in mEntries do
    begin
      if mEntry.MayMatch(ANode.Name) and Hits(mEntry, ANode, mWritten, mLookup) and ArgumentsAllow(mEntry, ANode) then
      begin
        Report(mEntry, ANode, mShown);
        Exit;
      end;
    end;
  end;

  /// <summary>Wird ANode geprüft? Bezeichner, Typangaben und qualifizierte Namen ohne Typargumente; Werte einer
  /// Aufzählung (Read, Write) sind Deklarationen, keine Verwendung.</summary>
  function Checked(ANode: TSyntaxNode): Boolean;
  begin
    if ANode.Name = '' then
    begin
      Exit(False);
    end;
    case ANode.Kind of
      TSyntaxKind.Identifier:
        Result := (ANode.Parent = nil) or (ANode.Parent.Kind <> TSyntaxKind.EnumType);
      TSyntaxKind.TypeReference:
        Result := True;
      TSyntaxKind.MemberAccess:
        Result := ANode.FindChild(TSyntaxKind.GenericArgs) = nil;
    else
      Result := False;
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if Checked(mNode) then
        begin
          CheckNode(mNode);
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

var
  mEntry: TForbiddenSymbol;
  mApplying: TArray<TForbiddenSymbol>;
  mUnitName: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  // Name aus dem Quelltext (unit X), sonst aus dem Dateinamen.
  mUnitName := TUsesClauses.OwnName(AContext.Tree.Tokens);
  if mUnitName = '' then
  begin
    mUnitName := AContext.UnitName;
  end;
  mApplying := nil;
  for mEntry in ParseSymbols(AContext.Options) do
  begin
    if (mEntry.Severity <> TRuleSeverity.Off) and mEntry.AppliesTo(mUnitName) then
    begin
      mApplying := mApplying + [mEntry];
    end;
  end;
  if mApplying = nil then
  begin
    Exit;
  end;
  mEntries := mApplying;
  mScope := TTypedScope.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    mScope.Free;
  end;
end;

procedure RegisterForbiddenSymbolRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TForbiddenSymbolRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.ForbiddenSymbols', cTexts);

end.
