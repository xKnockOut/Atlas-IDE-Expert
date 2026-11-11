unit Atlas.Common.Rules.Builtin.Inlining;

// Regel inline-not-expanded (#1017, Gruppe Compiler vorab): Aufruf einer
// inline-Routine, die der Compiler hier nicht einbettet.
//   H2443  Der Rumpf braucht eine Unit, die hier nicht in uses steht (typisch
//          System.Generics.Collections bei TJSONObject.Count).
//   (H2444 nicht: Auf strict private- und private-Mitglieder aus einer
//          anderen Unit bettet Delphi 13 ohne Meldung ein, #1383.)
//   Alle Fälle gibt es nur unitübergreifend.
//   H2445  Die aufrufende Routine ist selbst inline, und die Unit der
//          gerufenen steht nur im uses des implementation-Teils.
//   H2456  Die Unit der Routine verwendet die übersetzte Unit (Zyklus).
//   H2457  Ebenso über andere Units (indirekter Zyklus).
//          Beide nur, wenn der Rumpf auf etwas außerhalb seiner Unit
//          verweist: Sonst schweigt Delphi 13 je nach Reihenfolge der
//          Übersetzung (Cm.H2456, Cm.H2457; #1381, #1383).
//
// Was der Rumpf braucht, merkt sich der Index je inline-Routine
// (TIndexSymbol.InlineRefs); die Regel löst die Verweise im Bereich der
// deklarierenden Unit auf (TInlineCallees, geteilt mit unused-uses: Eine Unit,
// die nur ein solcher Rumpf braucht, gilt dort als benutzt). Gemeldet wird nur, was sicher aufgelöst ist:
// Verweise, die der Index nicht kennt, und geerbte Mitglieder aus fremden
// Units bleiben stumm. Erfasst werden Aufrufe, Properties mit inline-Getter
// bzw. -Setter und for-in über einen Typ mit inline-GetEnumerator, MoveNext
// oder Current. Mit {$INLINE OFF} in der Datei schweigt die Regel, ebenso
// ohne Projektindex (inline-Routinen der Datei selbst meldet sie nicht).
//
// Ein Verweis auf einen Alias einer Deklaration aus System (System.TypInfo:
// TTypeKind = System.TTypeKind, tkRecord = System.TTypeKind.tkRecord) braucht
// die Unit des Alias nicht: dcc löst ihn auf System auf. Sonst meldete die
// Regel bei jedem TList<T>.Add und TStack<T>.Push „System.TypInfo fehlt“.
// Für H2456/H2457 zählen eingebaute Typen, Intrinsics und System nicht als
// Verweis (THashFNV1a32.GetHashValue mit Integer(...) in
// System.Generics.Defaults).
//
// Kennt der Index einen Namen einer Zeile nicht (RTL unter Linux ohne
// Delphi), kann die Regel dort nicht entscheiden (IRuleLineCertainty): Ein
// lsp-ignore für sie in dieser Zeile gilt dann nicht als unused-suppression
// (RenameFile braucht unter Windows Winapi.Windows, H2443).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cInlineNotExpandedRuleId = 'inline-not-expanded';

type
  TInlineNotExpandedRule = class(TInterfacedObject, IRule, IRuleLineCertainty)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>False, wenn ein Bezeichner in ALine (-1 = in der Datei) sich nicht auflösen lässt.</summary>
    function Decides(const AContext: TRuleContext; ALine: Integer): Boolean;
  end;

procedure RegisterInliningRules(ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.InlineCallees,
  Atlas.Common.Semantics.UnresolvedNames,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TInliningText = (ImplUses, AddUses, MissingUnit, MissingUnits, CompiledUnit, CompiledUnitIndirect, Title);

const
  cTexts: array[TInliningText] of TAtlasText = (
    (De: 'Inline-Funktion %s wird nicht eingebettet: %s steht nur im uses des implementation-Teils, und die ' +
      'aufrufende Routine ist selbst inline (wie H2445).';
     En: 'Inline function %s is not expanded: %s is only in the uses of the implementation section, and the calling ' +
      'routine is itself inline (like H2445).'),
    (De: 'uses %s ergänzen'; En: 'Add uses %s'),
    (De: 'Inline-Funktion %s wird nicht eingebettet: %s fehlt in uses (wie H2443).';
     En: 'Inline function %s is not expanded: %s is missing in uses (like H2443).'),
    (De: 'Inline-Funktion %s wird nicht eingebettet: %s fehlen in uses (wie H2443).';
     En: 'Inline function %s is not expanded: %s are missing in uses (like H2443).'),
    (De: 'Inline-Funktion %s wird nicht eingebettet: %s verwendet die übersetzte Unit %s (wie H2456).';
     En: 'Inline function %s is not expanded: %s uses the compiled unit %s (like H2456).'),
    (De: 'Inline-Funktion %s wird nicht eingebettet: %s verwendet die übersetzte Unit %s indirekt über %s (wie H2457).';
     En: 'Inline function %s is not expanded: %s uses the compiled unit %s indirectly via %s (like H2457).'),
    (De: 'Inline-Funktion wird nicht eingebettet (wie H2443, H2445, H2456, H2457)';
     En: 'Inline function is not expanded (like H2443, H2445, H2456, H2457)'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Zyklen zwischen gerufenen Units und der eigenen über die uses-Listen im Index.</summary>
  TInlineCycles = class
  private
    FIndex: ISymbolIndex;
    FNamespaces: TArray<string>;
    FOwnName: string;
    // Zyklus je gerufener Unit (#1220): '' ohne, CycleDirect für H2456, sonst die Unit für H2457. Die Breitensuche
    // lief vorher bei jedem Aufruf neu und machte die Regel auf Units mit vielen inline-Aufrufen sekundenlang.
    FCycles: TDictionary<string, string>;
    /// <summary>Unit aus dem Index, auch über die Namespaces; ohne Nachladen.</summary>
    function FindIndexedUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
    function UsesOwnUnit(const AUnit: TUnitIndex): Boolean;
    /// <summary>Unit, über die AUnit die eigene Unit indirekt verwendet; '' ohne Zyklus.</summary>
    function IndirectVia(const AUnit: TUnitIndex): string;
  public
    constructor Create(const AIndex: ISymbolIndex; const ANamespaces: TArray<string>);
    destructor Destroy; override;
    function IsOwnUnit(const AName: string): Boolean;
    /// <summary>Zyklus zwischen AUnit und der eigenen Unit, je Unit nur einmal gesucht.</summary>
    function CycleOf(const AUnit: TUnitIndex): string;
    /// <summary>Name der geprüften Unit.</summary>
    property OwnName: string read FOwnName write FOwnName;
  end;

  TInlineCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    // Projektindex oder, ohne ihn, ein leerer: Dann kennt die Prüfung nur die Datei selbst.
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    FCallees: TInlineCallees;
    FReported: TDictionary<Integer, Boolean>;
    FCycles: TInlineCycles;
    FOwn: TUnitIndex;
    FOwnName: string;
    FUsed: TArray<string>;
    FLineBreak: string;
    function EnclosingRoutines(AOffset: Integer): TArray<TSyntaxNode>;
    function CallerIsInline(const ARoutines: TArray<TSyntaxNode>): Boolean;
    function OnlyInImplementationUses(const AUnitName: string): Boolean;
    /// <summary>Meldung zu ACallee an ARange, wenn der Compiler ihn nicht einbettet; True bei Treffer.</summary>
    function Report(const ACallee: TInlineCallee; const ARange: TTextRange; AOffset: Integer): Boolean;
    /// <summary>Meldet, warum ACallee nicht eingebettet wird; False, wenn nichts dagegen spricht.</summary>
    function Explain(const ACallee: TInlineCallee; const ARange: TTextRange; AOffset: Integer): Boolean;
    /// <summary>H2456/H2457: Zyklus zwischen der Unit von ACallee und der eigenen; True bei Meldung.</summary>
    function ReportedCycle(const ACallee: TInlineCallee; const ANeeds: TInlineNeeds;
      const ARange: TTextRange): Boolean;
    procedure CheckToken(ATokenIndex: Integer);
    procedure CheckForIn(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

const
  /// <summary>Höchstzahl der Units, die die Suche nach einem indirekten Zyklus besucht.</summary>
  cMaxCycleUnits = 400;
  /// <summary>Ergebnis von CycleOf, wenn die Unit die eigene direkt verwendet; kein gültiger Unit-Name.</summary>
  cCycleDirect = '=';

function SplitName(const AQualified: string; out AContainer: string): string;
var
  mDot: Integer;
begin
  mDot := AQualified.LastIndexOf('.');
  if mDot < 0 then
  begin
    AContainer := '';
    Exit(AQualified);
  end;
  AContainer := AQualified.Substring(0, mDot);
  Result := AQualified.Substring(mDot + 1);
end;

constructor TInlineCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FIndex := AContext.Index;
  if FIndex = nil then
  begin
    FIndex := TSymbolIndex.Create;
  end;
  FResolver := TNameResolver.Create(FIndex, AContext.EnsureUnit, AContext.TreeUnits);
  FResolver.Namespaces := AContext.Namespaces;
  FCallees := TInlineCallees.Create(FIndex, AContext.EnsureUnit, AContext.TreeUnits, AContext.Namespaces,
    AContext.NameFacts, FResolver);
  FReported := TDictionary<Integer, Boolean>.Create;
  FCycles := TInlineCycles.Create(FIndex, AContext.Namespaces);
end;

destructor TInlineCheck.Destroy;
begin
  FCycles.Free;
  FReported.Free;
  FCallees.Free;
  FResolver.Free;
  inherited;
end;

{ TInlineCycles }

constructor TInlineCycles.Create(const AIndex: ISymbolIndex; const ANamespaces: TArray<string>);
begin
  inherited Create;
  FIndex := AIndex;
  FNamespaces := ANamespaces;
  FCycles := TDictionary<string, string>.Create;
end;

destructor TInlineCycles.Destroy;
begin
  FCycles.Free;
  inherited;
end;

function TInlineCycles.IsOwnUnit(const AName: string): Boolean;
begin
  Result := TInlineCallees.SameUnit(AName, FOwnName, FNamespaces);
end;

function TInlineCycles.FindIndexedUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
var
  mNamespace: string;
begin
  if FIndex.FindUnit(AName, AUnit) then
  begin
    Exit(True);
  end;
  for mNamespace in FNamespaces do
  begin
    if FIndex.FindUnit(mNamespace + '.' + AName, AUnit) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TInlineCycles.UsesOwnUnit(const AUnit: TUnitIndex): Boolean;
var
  mName: string;
begin
  for mName in AUnit.InterfaceUses + AUnit.ImplementationUses do
  begin
    if IsOwnUnit(mName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TInlineCycles.IndirectVia(const AUnit: TUnitIndex): string;
var
  mNames, mVias: TQueue<string>;
  mSeen: TDictionary<string, Boolean>;
  mCurrent: TUnitIndex;
  mName, mVia: string;
begin
  // Breitensuche über die uses-Listen der Units im Index; Vias hält zu jedem Namen den direkten Nachbarn von
  // AUnit, über den der Weg läuft. Nur Units, die der Index schon kennt: Nachladen wäre zu teuer, und ohne sie
  // gibt es keine sichere Aussage (dann keine Meldung).
  Result := '';
  mNames := TQueue<string>.Create;
  mVias := TQueue<string>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mSeen.Add(UpperCase(AUnit.UnitName), True);
    for mName in AUnit.InterfaceUses + AUnit.ImplementationUses do
    begin
      mNames.Enqueue(mName);
      mVias.Enqueue(mName);
    end;
    while (mNames.Count > 0) and (mSeen.Count < cMaxCycleUnits) do
    begin
      mName := mNames.Dequeue;
      mVia := mVias.Dequeue;
      if IsOwnUnit(mName) or not FindIndexedUnit(mName, mCurrent) or
        mSeen.ContainsKey(UpperCase(mCurrent.UnitName)) then
      begin
        Continue;
      end;
      mSeen.Add(UpperCase(mCurrent.UnitName), True);
      for mName in mCurrent.InterfaceUses + mCurrent.ImplementationUses do
      begin
        if IsOwnUnit(mName) then
        begin
          Exit(mVia);
        end;
        mNames.Enqueue(mName);
        mVias.Enqueue(mVia);
      end;
    end;
  finally
    mSeen.Free;
    mVias.Free;
    mNames.Free;
  end;
end;

function TInlineCycles.CycleOf(const AUnit: TUnitIndex): string;
var
  mKey: string;
begin
  mKey := UpperCase(AUnit.UnitName);
  if FCycles.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  if UsesOwnUnit(AUnit) then
  begin
    Result := cCycleDirect;
  end
  else
  begin
    Result := IndirectVia(AUnit);
  end;
  FCycles.Add(mKey, Result);
end;

{ TInlineCheck }

function TInlineCheck.EnclosingRoutines(AOffset: Integer): TArray<TSyntaxNode>;
var
  mNode: TSyntaxNode;
  mIndex: Integer;
  mFound: Boolean;
begin
  // Von außen nach innen: Methode, dann ihre lokalen Routinen.
  Result := nil;
  mNode := FContext.Tree.Root;
  repeat
    mFound := False;
    for mIndex := 0 to mNode.ChildCount - 1 do
    begin
      if (mNode[mIndex].StartOffset <= AOffset) and (AOffset < mNode[mIndex].EndOffset) then
      begin
        mNode := mNode[mIndex];
        if mNode.Kind = TSyntaxKind.RoutineDecl then
        begin
          Result := Result + [mNode];
        end;
        mFound := True;
        Break;
      end;
    end;
  until not mFound;
end;

function TInlineCheck.CallerIsInline(const ARoutines: TArray<TSyntaxNode>): Boolean;
var
  mRoutine, mHeader: TSyntaxNode;
  mIndex: Integer;
  mName, mContainer: string;
  mSymbol: TIndexSymbol;
begin
  Result := False;
  if Length(ARoutines) = 0 then
  begin
    Exit;
  end;
  mRoutine := ARoutines[High(ARoutines)];
  mHeader := mRoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader <> nil then
  begin
    for mIndex := 0 to mHeader.ChildCount - 1 do
    begin
      if (mHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(mHeader[mIndex].Name, 'inline') then
      begin
        Exit(True);
      end;
    end;
  end;
  // inline steht oft nur an der Deklaration.
  mName := SplitName(mRoutine.Name, mContainer);
  for mSymbol in FOwn.Symbols do
  begin
    if SameText(mSymbol.Name, mName) and SameText(mSymbol.Container, mContainer) and mSymbol.HasDirective('inline') then
    begin
      Exit(True);
    end;
  end;
end;

function TInlineCheck.OnlyInImplementationUses(const AUnitName: string): Boolean;
begin
  Result := TUsesClauses.IsUsed(FOwn.ImplementationUses, AUnitName, FContext.Namespaces) and
    not TUsesClauses.IsUsed(FOwn.InterfaceUses, AUnitName, FContext.Namespaces);
end;

function TInlineCheck.Report(const ACallee: TInlineCallee; const ARange: TTextRange; AOffset: Integer): Boolean;
begin
  Result := False;
  if (ACallee.Symbol.InlineRefs = nil) or FReported.ContainsKey(AOffset) then
  begin
    Exit;
  end;
  Result := Explain(ACallee, ARange, AOffset);
  if Result then
  begin
    FReported.Add(AOffset, True);
  end;
end;

function TInlineCheck.Explain(const ACallee: TInlineCallee; const ARange: TTextRange; AOffset: Integer): Boolean;
var
  mNeeds: TInlineNeeds;
  mName, mMissing: string;
  mRoutines: TArray<TSyntaxNode>;
  mMissings: TArray<string>;
  mUnitName: string;
  mEdit: TTextEdit;
  mFixes: TArray<TRuleFix>;
begin
  Result := False;
  mName := ACallee.Symbol.QualifiedName;
  mRoutines := EnclosingRoutines(AOffset);
  mNeeds := FCallees.NeedsOf(ACallee);
  // In derselben Unit sind uses, Zyklen und der implementation-Teil dieselben.
  if FCycles.IsOwnUnit(ACallee.OwnerUnit.UnitName) then
  begin
    Exit;
  end;
  // Zyklen zuerst: Dann bettet der Compiler gar nicht ein, gleich was in uses steht.
  if ReportedCycle(ACallee, mNeeds, ARange) then
  begin
    Exit(True);
  end;
  // Die billige Frage nach dem uses zuerst: CallerIsInline durchsucht die Symbole der Datei.
  if OnlyInImplementationUses(ACallee.OwnerUnit.UnitName) and CallerIsInline(mRoutines) then
  begin
    FReport.Add(ARange, cTexts[TInliningText.ImplUses].Fmt([mName, ACallee.OwnerUnit.UnitName]));
    Exit(True);
  end;
  mMissings := nil;
  for mUnitName in mNeeds.Units do
  begin
    if not FCycles.IsOwnUnit(mUnitName) and not TUsesClauses.IsUsed(FUsed, mUnitName, FContext.Namespaces) then
    begin
      mMissings := mMissings + [mUnitName];
    end;
  end;
  if Length(mMissings) = 0 then
  begin
    Exit;
  end;
  mMissing := String.Join(', ', mMissings);
  mFixes := nil;
  if TUsesClauses.AddUnit(FContext.Tree.Tokens, AOffset, mMissing, FLineBreak, mEdit) then
  begin
    mFixes := [TRuleFix.Create(cTexts[TInliningText.AddUses].Fmt([mMissing]), [mEdit], True)];
  end;
  if Length(mMissings) = 1 then
  begin
    FReport.Add(ARange, cTexts[TInliningText.MissingUnit].Fmt([mName, mMissing]), mFixes);
  end
  else
  begin
    FReport.Add(ARange, cTexts[TInliningText.MissingUnits].Fmt([mName, mMissing]), mFixes);
  end;
  Result := True;
end;

function TInlineCheck.ReportedCycle(const ACallee: TInlineCallee; const ANeeds: TInlineNeeds;
  const ARange: TTextRange): Boolean;
var
  mCycle, mName: string;
begin
  // Nur bei Rümpfen mit Verweisen wie vor #1381: Ob dcc H2456/H2457 meldet, hängt von der Reihenfolge der
  // Übersetzung ab; bei Cm.H2456 und Cm.H2457 (Rumpf ohne Verweise, die Unit des Falls zuerst übersetzt) schweigt
  // Delphi 13 (#1383). Eingebaute Typen und System zählen nicht als Verweis (Integer(...) in
  // THashFNV1a32.GetHashValue).
  mCycle := '';
  if not TInlineCallees.IsWithoutRefs(ACallee.Symbol) and ANeeds.External then
  begin
    mCycle := FCycles.CycleOf(ACallee.OwnerUnit);
  end;
  mName := ACallee.Symbol.QualifiedName;
  Result := mCycle <> '';
  if mCycle = cCycleDirect then
  begin
    FReport.Add(ARange, cTexts[TInliningText.CompiledUnit].Fmt([mName, ACallee.OwnerUnit.UnitName, FOwnName]));
  end
  else if Result then
  begin
    FReport.Add(ARange, cTexts[TInliningText.CompiledUnitIndirect].Fmt([mName, ACallee.OwnerUnit.UnitName, FOwnName,
      mCycle]));
  end;
end;

procedure TInlineCheck.CheckToken(ATokenIndex: Integer);
var
  mToken: TPascalToken;
  mCallee: TInlineCallee;
begin
  mToken := FContext.Tree.Tokens[ATokenIndex];
  if FCallees.IsCandidate(mToken.Text) and FCallees.CalleeAt(FResolver.Resolve(FContext.Tree, FContext.RelativePath,
    mToken.StartPos), FContext.Tree.Tokens, ATokenIndex, mCallee) then
  begin
    Report(mCallee, TTextRange.Create(mToken.StartPos, mToken.EndPos), mToken.Offset);
  end;
end;

procedure TInlineCheck.CheckForIn(ANode: TSyntaxNode);
var
  mExpr: TSyntaxNode;
  mCallee: TInlineCallee;
begin
  // GetEnumerator, dann MoveNext und der Getter von Current des Enumerators: gemeldet wird der erste Treffer.
  for mCallee in FCallees.ForInCallees(FContext.Tree, FContext.RelativePath, ANode, mExpr) do
  begin
    if Report(mCallee, TTextRange.Create(mExpr.StartPos, mExpr.EndPos), mExpr.StartOffset) then
    begin
      Exit;
    end;
  end;
end;

procedure TInlineCheck.Run;
var
  mIndex: Integer;
  mForIns: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  FOwnName := TUsesClauses.OwnName(FContext.Tree.Tokens);
  if FOwnName = '' then
  begin
    FOwnName := FContext.UnitName;
  end;
  FCycles.OwnName := FOwnName;
  FUsed := TUsesClauses.UsedUnits(FContext.Tree.Tokens);
  FLineBreak := TTextLines.LineBreakOf(FContext.Text);
  FResolver.PinTree(FContext.Tree, FContext.RelativePath);
  try
    FOwn := FResolver.ExtractedUnit(FContext.Tree, FContext.RelativePath);
    FCallees.Prepare(FOwn, FOwnName);
    for mIndex := 0 to High(FContext.Tree.Tokens) do
    begin
      if FContext.Tree.Tokens[mIndex].Kind = TPascalTokenKind.Identifier then
      begin
        CheckToken(mIndex);
      end;
    end;
    mForIns := TList<TSyntaxNode>.Create;
    try
      FContext.Tree.Root.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          Result := True;
          if ANode.Kind = TSyntaxKind.ForInStatement then
          begin
            mForIns.Add(ANode);
          end;
        end);
      for mNode in mForIns do
      begin
        CheckForIn(mNode);
      end;
    finally
      mForIns.Free;
    end;
  finally
    FResolver.UnpinTree;
  end;
end;

{ TInlineNotExpandedRule }

function TInlineNotExpandedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cInlineNotExpandedRuleId, TRuleSeverity.Hint,
    cTexts[TInliningText.Title].Text);
end;

procedure TInlineNotExpandedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TInlineCheck;
begin
  if (AContext.Tree = nil) or ContainsText(AContext.Text, '{$INLINE OFF}') then
  begin
    Exit;
  end;
  mCheck := TInlineCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

/// <summary>Bezeichner in ALine (-1 = überall), den AResolver nicht auflösen kann und der kein Intrinsic ist?
/// </summary>
function IsUnknownName(AResolver: TNameResolver; const AContext: TRuleContext; const AToken: TPascalToken;
  ALine: Integer): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Identifier) and ((ALine < 0) or (AToken.StartPos.Line = ALine));
  Result := Result and not TUnresolvedNames.IsIntrinsic(AToken.Text) and
    not AResolver.Resolve(AContext.Tree, AContext.RelativePath, AToken.StartPos).Found;
end;

function TInlineNotExpandedRule.Decides(const AContext: TRuleContext; ALine: Integer): Boolean;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mToken: TPascalToken;
begin
  Result := True;
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mIndex := AContext.Index;
  if mIndex = nil then
  begin
    mIndex := TSymbolIndex.Create;
  end;
  mResolver := TNameResolver.Create(mIndex, AContext.EnsureUnit, AContext.TreeUnits);
  try
    mResolver.Namespaces := AContext.Namespaces;
    mResolver.PinTree(AContext.Tree, AContext.RelativePath);
    try
      for mToken in AContext.Tree.Tokens do
      begin
        if IsUnknownName(mResolver, AContext, mToken, ALine) then
        begin
          Exit(False);
        end;
      end;
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
end;

procedure RegisterInliningRules(ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TInlineNotExpandedRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inlining', cTexts);

end.
