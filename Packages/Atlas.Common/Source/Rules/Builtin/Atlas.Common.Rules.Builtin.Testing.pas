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
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.Attributes,
  Atlas.Common.Rules.Options;

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
    if not (FTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      FCode := FCode + [mIndex];
  FPatterns := APatterns;
  FElsewhere := AElsewhere;
  FRoutines := nil;
  if ATree.Root <> nil then
    CollectRoutines(ATree.Root);
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
        FRoutines := FRoutines + [mNode];
      for mIndex := mNode.ChildCount - 1 downto 0 do
        mPending.Push(mNode[mIndex]);
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
    if SameText(mRoutine.Name, AName) and (mRoutine.FindChild(TSyntaxKind.Block) <> nil) then
      Exit(mRoutine);
  Result := nil;
end;

function TAssertSearch.Asserts(ARoutine: TSyntaxNode; const AClassName: string;
  var AVisited: TArray<TSyntaxNode>): Boolean;
var
  mBlock, mCallee, mVisited: TSyntaxNode;
  mPosition, mLast: Integer;
  mChain: string;
begin
  Result := False;
  for mVisited in AVisited do
    if mVisited = ARoutine then
      Exit;
  AVisited := AVisited + [ARoutine];
  mBlock := ARoutine.FindChild(TSyntaxKind.Block);
  if mBlock = nil then
    Exit;
  for mPosition := 0 to High(FCode) do
  begin
    if (Token(mPosition).Offset < mBlock.StartOffset) or (Token(mPosition).Offset >= mBlock.EndOffset) or
      not IsWord(mPosition) or ((mPosition > 0) and Token(mPosition - 1).IsSymbol('.')) then
      Continue;
    // Punktkette ab hier: Assert.AreEqual, Self.Pruefen, TRuleAssert.Reports.
    mChain := Token(mPosition).Text;
    mLast := mPosition;
    while (mLast + 2 <= High(FCode)) and Token(mLast + 1).IsSymbol('.') and IsWord(mLast + 2) do
    begin
      Inc(mLast, 2);
      mChain := mChain + '.' + Token(mLast).Text;
    end;
    if TDUnitXTestWithoutAssertRule.IsAssertion(mChain, FPatterns) then
      Exit(True);
    if StartsText('Self.', mChain) then
      mChain := Copy(mChain, 6, MaxInt);
    if Pos('.', mChain) > 0 then
      Continue;
    mCallee := FindRoutine(AClassName + '.' + mChain);
    if mCallee = nil then
      mCallee := FindRoutine(mChain);
    if mCallee <> nil then
    begin
      if Asserts(mCallee, AClassName, AVisited) then
        Exit(True);
    end
    else if Assigned(FElsewhere) and FElsewhere(mChain) then
      Exit(True);
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
    Exit(False);
  mKey := UpperCase(AName);
  if FKnown.TryGetValue(mKey, Result) then
    Exit;
  Result := Search(AName);
  FKnown.Add(mKey, Result);
end;

function TAssertsInOtherUnits.Search(const AName: string): Boolean;
var
  mLocation: TSymbolLocation;
begin
  Result := False;
  for mLocation in FIndex.FindSymbols(AName) do
    if (mLocation.Symbol.Kind = TIndexSymbolKind.Routine) and (mLocation.Symbol.Container = '') and
      mLocation.Symbol.InInterface and not SameText(mLocation.UnitName, FUnitName) and
      not SameText(mLocation.FileName, FFileName) and SearchIn(mLocation) then
      Exit(True);
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
    Exit;
  mTree := TPascalParser.Parse(TFileEncoding.Decode(mData, mFormat));
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
  Result := TRuleDescriptor.Create(DUnitXTestWithoutAssertRuleId, TRuleSeverity.Hint, 'DUnitX-Test ohne Assert');
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
    Exit(True);
  for Pattern in APatterns do
    if MatchesGlob(Pattern, AChain) then
      Exit(True);
  // Eigene Prüfklassen: TRuleAssert.Reports, TJsonAssert.Equal.
  Parts := AChain.Split(['.']);
  for Index := 0 to High(Parts) - 1 do
    if ContainsText(Parts[Index], 'Assert') then
      Exit(True);
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
      if (mToken.Offset >= AHeader.StartOffset) and (mToken.Offset < AHeader.EndOffset) and
        (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, AHeader.Name) then
        Exit(TTextRange.Create(mToken.StartPos, mToken.EndPos));
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
      Exit;
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
      Exit;
    mVisited := nil;
    if mSearch.Asserts(mBody, AClassName, mVisited) then
      Exit;
    mFixes := nil;
    mBlock := mBody.FindChild(TSyntaxKind.Block);
    if (mBlock <> nil) and PassEdit(mBlock, mEdit) then
    begin
      mFix := TRuleFix.Create('Assert.Pass; als Platzhalter einfügen', [mEdit]);
      mFix.Alternative := True;
      mFixes := mFixes + [mFix];
    end;
    mFix := TRuleFix.Jump('Zur Methode springen', mBody.StartPos);
    mFix.Alternative := True;
    mFixes := mFixes + [mFix];
    AReport.Add(NameRange(AHeader), 'Der Test prüft nichts; er ist immer grün.', mFixes);
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
      if (mChild.Kind = TSyntaxKind.RoutineHeader) and (MatchText('Test', mNames) or MatchText('TestCase', mNames)) and
        not MatchText('Ignore', mNames) and not MatchText('WillRaise', mNames) and
        not MatchText('WillRaiseAny', mNames) then
        CheckMethod(AClassName, mChild);
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
            CheckClass(mNode.Name, mBody);
          Continue;
        end;
        if mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.RoutineDecl] then
          Continue;
        for mIndex := mNode.ChildCount - 1 downto 0 do
          mPending.Push(mNode[mIndex]);
      end;
    finally
      mPending.Free;
    end;
  end;

var
  mPatterns: TArray<string>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  // Ohne Attribut Test schweigt die Regel sofort.
  if not ContainsText(AContext.Text, 'Test') then
    Exit;
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

end.
