unit Atlas.Common.Rules.Builtin.Testing;

// Regeln für DUnitX-Tests:
//   dunitx-test-without-assert  [Test]- bzw. [TestCase]-Methode, die weder selbst noch über Methoden derselben
//                               Klasse oder Routinen der Unit eine Prüfung aufruft (#945): Sie ist immer grün.
//                               Freie Routinen anderer Units (AssertTextPair aus einer gemeinsamen Testunit) löst
//                               der Symbolindex auf; ihr Rumpf wird gelesen und ebenso durchsucht.
//                               Als Prüfung zählen Aufrufe nach "assertPatterns" (Vorgabe Assert.*, WillRaise*,
//                               Check*), System.Assert und Aufrufe an Klassen mit Assert im Namen
//                               (TRuleAssert.Reports). Tests mit [WillRaise] oder [Ignore] bleiben still.
//                               Korrekturen: Assert.Pass als Platzhalter oder Sprung zur Methode.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TDUnitXTestWithoutAssertRule = class(TInterfacedObject, IRule)
  public
    /// <summary>Vorgabe von "assertPatterns": Assert.*, WillRaise*, Check*.</summary>
    class function DefaultPatterns: TArray<string>; static;
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Zählt der Aufruf AChain (z. B. Assert.AreEqual, TRuleAssert.Reports) als Prüfung?</summary>
    class function IsAssertion(const AChain: string; const APatterns: TArray<string>): Boolean; static;
  end;

procedure RegisterTestingRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.Attributes,
  Atlas.Common.Rules.Options,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTestingText = (Title, InsertPass, JumpToMethod, ChecksNothing);

const
  cTexts: array[TTestingText] of TAtlasText = (
    (De: 'DUnitX-Test ohne Assert'; En: 'DUnitX test without Assert'),
    (De: 'Assert.Pass; als Platzhalter einfügen'; En: 'Insert Assert.Pass; as placeholder'),
    (De: 'Zur Methode springen'; En: 'Go to method'),
    (De: 'Der Test prüft nichts; er ist immer grün.'; En: 'The test checks nothing; it is always green.'));

{$SCOPEDENUMS OFF}

const
  DUnitXTestWithoutAssertRuleId = 'dunitx-test-without-assert';

type
  /// <summary>Prüft die freie Routine AName einer anderen Unit etwas? False, wenn sie unbekannt ist.</summary>
  TAssertsElsewhere = function(const AName: string): Boolean of object;

  /// <summary>Sucht in den Routinen einer Unit nach Prüfungen: Code-Tokens ohne Kommentare und alle Routinen,
  /// auch lokale (ein Test prüft oft in einer eigenen Hilfsroutine).</summary>
  TAssertSearch = class
  private
    FTokens: TArray<TPascalToken>;
    FCode: TArray<Integer>;
    FRoutines: TArray<TSyntaxNode>;
    FPatterns: TArray<string>;
    FElsewhere: TAssertsElsewhere;
    procedure CollectRoutines(ARoot: TSyntaxNode);
    function Token(APosition: Integer): TPascalToken;
    function IsWord(APosition: Integer): Boolean;
    /// <summary>Beginnt an APosition innerhalb von ABlock eine Punktkette (Bezeichner, nicht hinter einem Punkt)?
    /// </summary>
    function ChainStart(APosition: Integer; ABlock: TSyntaxNode): Boolean;
    /// <summary>Punktkette ab APosition: Assert.AreEqual, Self.Pruefen, TRuleAssert.Reports.</summary>
    function ChainAt(APosition: Integer): string;
    /// <summary>Zählt der Aufruf AChain als Prüfung, selbst oder über die aufgerufene Routine?</summary>
    function ChainAsserts(const AChain, AClassName: string; var AVisited: TArray<TSyntaxNode>): Boolean;
    class function Visited(ARoutine: TSyntaxNode; const AVisited: TArray<TSyntaxNode>): Boolean; static;
  public
    /// <summary>AElsewhere = nil: Aufrufe in andere Units zählen nicht.</summary>
    constructor Create(ATree: TSyntaxTree; const APatterns: TArray<string>; const AElsewhere: TAssertsElsewhere);
    function FindRoutine(const AName: string): TSyntaxNode;
    /// <summary>Prüft ARoutine etwas, selbst oder über eine aufgerufene Methode von AClassName, eine Routine
    /// der Unit oder (über AElsewhere) eine freie Routine einer anderen Unit?</summary>
    function Asserts(ARoutine: TSyntaxNode; const AClassName: string; var AVisited: TArray<TSyntaxNode>): Boolean;
  end;

  /// <summary>Freie Routinen anderer Units über den Symbolindex: Datei lesen, Rumpf durchsuchen. Je Name nur
  /// einmal; von dort aus zählen nur Routinen derselben Unit (keine Kette über weitere Units).</summary>
  TAssertsInOtherUnits = class
  private
    FIndex: ISymbolIndex;
    FReadFile: TRuleFileReader;
    FFileName: string;
    FUnitName: string;
    FPatterns: TArray<string>;
    FKnown: TDictionary<string, Boolean>;
    function Search(const AName: string): Boolean;
    function SearchIn(const ALocation: TSymbolLocation): Boolean;
    /// <summary>Freie Routine aus dem interface-Teil einer anderen Unit?</summary>
    function IsCandidate(const ALocation: TSymbolLocation): Boolean;
  public
    constructor Create(const AContext: TRuleContext; const APatterns: TArray<string>);
    destructor Destroy; override;
    function Asserts(const AName: string): Boolean;
  end;

{ TAssertSearch }

constructor TAssertSearch.Create(ATree: TSyntaxTree; const APatterns: TArray<string>;
  const AElsewhere: TAssertsElsewhere);
var
  mIndex: Integer;
begin
  inherited Create;
  FTokens := ATree.Tokens;
  FCode := nil;
  for mIndex := 0 to High(FTokens) do
  begin
    if not (FTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      FCode := FCode + [mIndex];
    end;
  end;
  FPatterns := APatterns;
  FElsewhere := AElsewhere;
  FRoutines := nil;
  if ATree.Root <> nil then
  begin
    CollectRoutines(ATree.Root);
  end;
end;

// Iterativ (Bericht M1).
procedure TAssertSearch.CollectRoutines(ARoot: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.RoutineDecl then
      begin
        FRoutines := FRoutines + [mNode];
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

function TAssertSearch.Token(APosition: Integer): TPascalToken;
begin
  Result := FTokens[FCode[APosition]];
end;

function TAssertSearch.IsWord(APosition: Integer): Boolean;
begin
  Result := (APosition >= 0) and (APosition <= High(FCode)) and
    (Token(APosition).Kind = TPascalTokenKind.Identifier);
end;

function TAssertSearch.FindRoutine(const AName: string): TSyntaxNode;
var
  mRoutine: TSyntaxNode;
begin
  // Nur Routinen mit Rumpf: Die Deklaration im interface-Teil (procedure PruefePaar;) hat keinen.
  for mRoutine in FRoutines do
  begin
    if SameText(mRoutine.Name, AName) and (mRoutine.FindChild(TSyntaxKind.Block) <> nil) then
    begin
      Exit(mRoutine);
    end;
  end;
  Result := nil;
end;

function TAssertSearch.ChainStart(APosition: Integer; ABlock: TSyntaxNode): Boolean;
begin
  Result := (Token(APosition).Offset >= ABlock.StartOffset) and (Token(APosition).Offset < ABlock.EndOffset) and
    IsWord(APosition) and not ((APosition > 0) and Token(APosition - 1).IsSymbol('.'));
end;

function TAssertSearch.ChainAt(APosition: Integer): string;
var
  mLast: Integer;
begin
  Result := Token(APosition).Text;
  mLast := APosition;
  while (mLast + 2 <= High(FCode)) and Token(mLast + 1).IsSymbol('.') and IsWord(mLast + 2) do
  begin
    Inc(mLast, 2);
    Result := Result + '.' + Token(mLast).Text;
  end;
end;

function TAssertSearch.ChainAsserts(const AChain, AClassName: string; var AVisited: TArray<TSyntaxNode>): Boolean;
var
  mName: string;
  mCallee: TSyntaxNode;
begin
  if TDUnitXTestWithoutAssertRule.IsAssertion(AChain, FPatterns) then
  begin
    Exit(True);
  end;
  mName := AChain;
  if StartsText('Self.', mName) then
  begin
    mName := Copy(mName, 6, MaxInt);
  end;
  // Aufrufe an andere Objekte (FImport.Laden) verfolgt die Regel nicht.
  if Pos('.', mName) > 0 then
  begin
    Exit(False);
  end;
  mCallee := FindRoutine(AClassName + '.' + mName);
  if mCallee = nil then
  begin
    mCallee := FindRoutine(mName);
  end;
  if mCallee <> nil then
  begin
    Result := Asserts(mCallee, AClassName, AVisited);
  end
  else
  begin
    Result := Assigned(FElsewhere) and FElsewhere(mName);
  end;
end;

class function TAssertSearch.Visited(ARoutine: TSyntaxNode; const AVisited: TArray<TSyntaxNode>): Boolean;
var
  mVisited: TSyntaxNode;
begin
  Result := False;
  for mVisited in AVisited do
  begin
    if mVisited = ARoutine then
    begin
      Exit(True);
    end;
  end;
end;

function TAssertSearch.Asserts(ARoutine: TSyntaxNode; const AClassName: string;
  var AVisited: TArray<TSyntaxNode>): Boolean;
var
  mBlock: TSyntaxNode;
  mPosition: Integer;
begin
  Result := False;
  if Visited(ARoutine, AVisited) then
  begin
    Exit;
  end;
  AVisited := AVisited + [ARoutine];
  mBlock := ARoutine.FindChild(TSyntaxKind.Block);
  if mBlock = nil then
  begin
    Exit;
  end;
  for mPosition := 0 to High(FCode) do
  begin
    if ChainStart(mPosition, mBlock) and ChainAsserts(ChainAt(mPosition), AClassName, AVisited) then
    begin
      Exit(True);
    end;
  end;
end;

{ TAssertsInOtherUnits }

constructor TAssertsInOtherUnits.Create(const AContext: TRuleContext; const APatterns: TArray<string>);
begin
  inherited Create;
  FIndex := AContext.Index;
  FReadFile := AContext.ReadFile;
  FFileName := AContext.FileName;
  FUnitName := AContext.UnitName;
  FPatterns := APatterns;
  FKnown := TDictionary<string, Boolean>.Create;
end;

destructor TAssertsInOtherUnits.Destroy;
begin
  FKnown.Free;
  inherited Destroy;
end;

function TAssertsInOtherUnits.Asserts(const AName: string): Boolean;
var
  mKey: string;
begin
  if (FIndex = nil) or not Assigned(FReadFile) then
  begin
    Exit(False);
  end;
  mKey := UpperCase(AName);
  if FKnown.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result := Search(AName);
  FKnown.Add(mKey, Result);
end;

function TAssertsInOtherUnits.Search(const AName: string): Boolean;
var
  mLocation: TSymbolLocation;
begin
  Result := False;
  for mLocation in FIndex.FindSymbols(AName) do
  begin
    if IsCandidate(mLocation) and SearchIn(mLocation) then
    begin
      Exit(True);
    end;
  end;
end;

function TAssertsInOtherUnits.IsCandidate(const ALocation: TSymbolLocation): Boolean;
begin
  Result := (ALocation.Symbol.Kind = TIndexSymbolKind.Routine) and (ALocation.Symbol.Container = '') and
    ALocation.Symbol.InInterface and not SameText(ALocation.UnitName, FUnitName) and
    not SameText(ALocation.FileName, FFileName);
end;

function TAssertsInOtherUnits.SearchIn(const ALocation: TSymbolLocation): Boolean;
var
  mData: TBytes;
  mFormat: TFileFormat;
  mTree: TSyntaxTree;
  mSearch: TAssertSearch;
  mRoutine: TSyntaxNode;
  mVisited: TArray<TSyntaxNode>;
begin
  Result := False;
  if not FReadFile(ALocation.FileName, mData) then
  begin
    Exit;
  end;
  mTree := TSyntaxTreeCache.Parse(TFileEncoding.Decode(mData, mFormat));
  try
    mSearch := TAssertSearch.Create(mTree, FPatterns, nil);
    try
      mRoutine := mSearch.FindRoutine(ALocation.Symbol.Name);
      mVisited := nil;
      Result := (mRoutine <> nil) and mSearch.Asserts(mRoutine, '', mVisited);
    finally
      mSearch.Free;
    end;
  finally
    mTree.Free;
  end;
end;

{ TDUnitXTestWithoutAssertRule }

class function TDUnitXTestWithoutAssertRule.DefaultPatterns: TArray<string>;
begin
  Result := ['Assert.*', 'WillRaise*', 'Check*'];
end;

function TDUnitXTestWithoutAssertRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DUnitXTestWithoutAssertRuleId, TRuleSeverity.Hint, cTexts[TTestingText.Title].Text);
end;

class function TDUnitXTestWithoutAssertRule.IsAssertion(const AChain: string;
  const APatterns: TArray<string>): Boolean;
var
  Pattern: string;
  Parts: TArray<string>;
  Index: Integer;
begin
  // System.Assert(Bedingung) löst EAssertionFailed aus und lässt den Test scheitern.
  if SameText(AChain, 'Assert') or SameText(AChain, 'System.Assert') then
  begin
    Exit(True);
  end;
  for Pattern in APatterns do
  begin
    if MatchesGlob(Pattern, AChain) then
    begin
      Exit(True);
    end;
  end;
  // Eigene Prüfklassen: TRuleAssert.Reports, TJsonAssert.Equal.
  Parts := AChain.Split(['.']);
  for Index := 0 to High(Parts) - 1 do
  begin
    if ContainsText(Parts[Index], 'Assert') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TDUnitXTestWithoutAssertRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mLines: TArray<string>;
  mLineBreak: string;
  mSearch: TAssertSearch;
  mOtherUnits: TAssertsInOtherUnits;

  function NameRange(AHeader: TSyntaxNode): TTextRange;
  var
    mToken: TPascalToken;
  begin
    Result := TTextRange.Create(AHeader.StartPos, AHeader.EndPos);
    for mToken in AContext.Tree.Tokens do
    begin
      if (mToken.Offset >= AHeader.StartOffset) and (mToken.Offset < AHeader.EndOffset) and
        (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, AHeader.Name) then
      begin
        Exit(TTextRange.Create(mToken.StartPos, mToken.EndPos));
      end;
    end;
  end;

  // "Assert.Pass;" vor das "end" des Rumpfs, wenn es allein in seiner Zeile steht.
  function PassEdit(ABlock: TSyntaxNode; out AEdit: TTextEdit): Boolean;
  var
    mLine: Integer;
    mIndent: string;
  begin
    Result := False;
    mLine := ABlock.EndPos.Line;
    if (mLine > High(mLines)) or (ABlock.EndPos.Line = ABlock.StartPos.Line) or
      (Trim(Copy(mLines[mLine], 1, ABlock.EndPos.Character - 3)) <> '') then
    begin
      Exit;
    end;
    mIndent := TTextLines.IndentOf(mLines[mLine]);
    AEdit := TTextEdit.Create(TTextRange.Create(mLine, 0, mLine, 0), mIndent + '  Assert.Pass;' + mLineBreak);
    Result := True;
  end;

  procedure CheckMethod(const AClassName: string; AHeader: TSyntaxNode);
  var
    mBody, mBlock: TSyntaxNode;
    mVisited: TArray<TSyntaxNode>;
    mFixes: TArray<TRuleFix>;
    mEdit: TTextEdit;
    mFix: TRuleFix;
  begin
    mBody := mSearch.FindRoutine(AClassName + '.' + AHeader.Name);
    if mBody = nil then
    begin
      Exit;
    end;
    mVisited := nil;
    if mSearch.Asserts(mBody, AClassName, mVisited) then
    begin
      Exit;
    end;
    mFixes := nil;
    mBlock := mBody.FindChild(TSyntaxKind.Block);
    if (mBlock <> nil) and PassEdit(mBlock, mEdit) then
    begin
      mFix := TRuleFix.Create(cTexts[TTestingText.InsertPass].Text, [mEdit]);
      mFix.Alternative := True;
      mFixes := mFixes + [mFix];
    end;
    mFix := TRuleFix.Jump(cTexts[TTestingText.JumpToMethod].Text, mBody.StartPos);
    mFix.Alternative := True;
    mFixes := mFixes + [mFix];
    AReport.Add(NameRange(AHeader), cTexts[TTestingText.ChecksNothing].Text, mFixes);
  end;

  // [Test] oder [TestCase], aber nicht [Ignore], [WillRaise] oder [WillRaiseAny].
  function IsCheckedTest(const ANames: TArray<string>): Boolean;
  var
    mName: string;
  begin
    Result := False;
    for mName in ANames do
    begin
      if MatchText(mName, ['Ignore', 'WillRaise', 'WillRaiseAny']) then
      begin
        Exit(False);
      end;
      if MatchText(mName, ['Test', 'TestCase']) then
      begin
        Result := True;
      end;
    end;
  end;

  procedure CheckClass(const AClassName: string; AClass: TSyntaxNode);
  var
    mIndex: Integer;
    mChild: TSyntaxNode;
    mNames: TArray<string>;
  begin
    mNames := nil;
    for mIndex := 0 to AClass.ChildCount - 1 do
    begin
      mChild := AClass[mIndex];
      if mChild.Kind = TSyntaxKind.Attribute then
      begin
        mNames := mNames + TAttributes.Names(mChild);
        Continue;
      end;
      if (mChild.Kind = TSyntaxKind.RoutineHeader) and IsCheckedTest(mNames) then
      begin
        CheckMethod(AClassName, mChild);
      end;
      mNames := nil;
    end;
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
    mBody: TSyntaxNode;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.TypeDecl then
        begin
          mBody := mNode.FindChild(TSyntaxKind.ClassType);
          if mBody <> nil then
          begin
            CheckClass(mNode.Name, mBody);
          end;
          Continue;
        end;
        if mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.RoutineDecl] then
        begin
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

var
  mPatterns: TArray<string>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  // Ohne Attribut Test schweigt die Regel sofort.
  if not ContainsText(AContext.Text, 'Test') then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
  mPatterns := TRuleOptions.Strings(AContext.Options, 'assertPatterns', DefaultPatterns);
  mOtherUnits := TAssertsInOtherUnits.Create(AContext, mPatterns);
  try
    mSearch := TAssertSearch.Create(AContext.Tree, mPatterns, mOtherUnits.Asserts);
    try
      Visit(AContext.Tree.Root);
    finally
      mSearch.Free;
    end;
  finally
    mOtherUnits.Free;
  end;
end;

procedure RegisterTestingRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDUnitXTestWithoutAssertRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Testing', cTexts);

end.
