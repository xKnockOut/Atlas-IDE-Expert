unit Atlas.Common.Pascal.SyntaxTree.Tests;

// Tests für den Besucher TSyntaxNode.Walk, die Suche
// TSyntaxNode.Search, die Baumtiefe TSyntaxTree.Depth/Deepest (#1094)
// und die Token-Suche FirstTokenFrom/IdentifierAt (#1323).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSyntaxTreeTests = class
  public
    [Test]
    procedure WalkVisitsAllNodesInTreeOrder;
    [Test]
    procedure WalkSkipsChildrenWhenVisitReturnsFalse;
    [Test]
    procedure DepthCountsLongestPath;
    /// <summary>Depth arbeitet ohne Rekursion und reicht mit wenig Stapel auch für sehr tiefe Bäume.</summary>
    [Test]
    procedure DepthOfDeepTreeNeedsLittleStack;
    [Test]
    procedure SearchFindsFirstMatchInTreeOrder;
    [Test]
    procedure SearchSkipLeavesOutChildren;
    /// <summary>Walk und Search arbeiten ohne Rekursion.</summary>
    [Test]
    procedure WalkAndSearchOfDeepTreeNeedLittleStack;
    [Test]
    procedure DeepestIsFirstNodeAtGreatestDepth;
    /// <summary>#1323: Anfang, Mitte und Ende eines Bezeichners, Leerraum dazwischen, hinter dem letzten Token.
    /// </summary>
    [Test]
    procedure IdentifierAtCases;
    /// <summary>#1323: Die binäre Suche liefert an jeder Position dasselbe wie die frühere lineare.</summary>
    [Test]
    procedure IdentifierAtMatchesLinearSearch;
    [Test]
    procedure FirstTokenFromMatchesLinearSearch;
    [Test]
    procedure FirstTokenOfMatchesLinearSearchOnCodeTokens;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Tests.SmallStack;

const
  cSource = 'unit A;'#10'interface'#10'implementation'#10 +
    'procedure P;'#10'var X: Integer;'#10'begin'#10'  X := 1;'#10'  if X > 0 then X := 2;'#10'end;'#10 +
    'procedure Q;'#10'begin'#10'end;'#10'end.';

procedure CollectRecursive(ANode: TSyntaxNode; AList: TList<TSyntaxNode>);
var
  mIndex: Integer;
begin
  AList.Add(ANode);
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    CollectRecursive(ANode.Children[mIndex], AList);
  end;
end;

function CountKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  if ANode.Kind = AKind then
  begin
    Inc(Result);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Inc(Result, CountKind(ANode.Children[mIndex], AKind));
  end;
end;

procedure TSyntaxTreeTests.WalkVisitsAllNodesInTreeOrder;
var
  mTree: TSyntaxTree;
  mExpected, mVisited: TList<TSyntaxNode>;
  mIndex: Integer;
begin
  mTree := TPascalParser.Parse(cSource);
  mExpected := TList<TSyntaxNode>.Create;
  mVisited := TList<TSyntaxNode>.Create;
  try
    CollectRecursive(mTree.Root, mExpected);
    mTree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        mVisited.Add(ANode);
        Result := True;
      end);
    Assert.IsTrue(mExpected.Count > 10, 'Baum zu klein');
    Assert.AreEqual(mExpected.Count, mVisited.Count, 'Anzahl Knoten');
    Assert.AreSame(mTree.Root, mVisited[0], 'erster Knoten ist die Wurzel');
    for mIndex := 0 to mExpected.Count - 1 do
    begin
      Assert.AreSame(mExpected[mIndex], mVisited[mIndex], 'Reihenfolge an Stelle ' + IntToStr(mIndex));
    end;
  finally
    mVisited.Free;
    mExpected.Free;
    mTree.Free;
  end;
end;

procedure TSyntaxTreeTests.WalkSkipsChildrenWhenVisitReturnsFalse;
var
  mTree: TSyntaxTree;
  mRoutines, mBlocks: Integer;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.IsTrue(CountKind(mTree.Root, TSyntaxKind.Block) > 0, 'Blöcke vorhanden');
    mRoutines := 0;
    mBlocks := 0;
    mTree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if ANode.Kind = TSyntaxKind.RoutineDecl then
        begin
          Inc(mRoutines);
        end;
        if ANode.Kind = TSyntaxKind.Block then
        begin
          Inc(mBlocks);
        end;
        Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      end);
    Assert.AreEqual(2, mRoutines, 'Routinen besucht');
    Assert.AreEqual(0, mBlocks, 'keine Blöcke unter übersprungenen Routinen');
  finally
    mTree.Free;
  end;
end;

function RecursiveDepth(ANode: TSyntaxNode): Integer;
var
  mIndex, mChild: Integer;
begin
  Result := 1;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mChild := RecursiveDepth(ANode.Children[mIndex]) + 1;
    if mChild > Result then
    begin
      Result := mChild;
    end;
  end;
end;

procedure TSyntaxTreeTests.DepthCountsLongestPath;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.AreEqual(RecursiveDepth(mTree.Root), mTree.Depth);
    // Gemerkt: der zweite Aufruf liefert dasselbe.
    Assert.AreEqual(RecursiveDepth(mTree.Root), mTree.Depth);
  finally
    mTree.Free;
  end;
end;

procedure TSyntaxTreeTests.DepthOfDeepTreeNeedsLittleStack;
var
  mBuilder: TStringBuilder;
  mIndex, mDepth: Integer;
  mTree: TSyntaxTree;
  mFailure: string;
begin
  // Subtraktion bleibt linkslastig: 100000 Glieder ergeben über 100000 Ebenen.
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('program P; begin X := 1');
    for mIndex := 1 to 100000 do
    begin
      mBuilder.Append('-1');
    end;
    mBuilder.Append('; end.');
    mTree := TPascalParser.Parse(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
  try
    mDepth := 0;
    mFailure := TSmallStack.Run(128,
      procedure
      begin
        mDepth := mTree.Depth;
      end);
    Assert.AreEqual('', mFailure);
    Assert.IsTrue(mDepth > 100000, 'Tiefe ' + IntToStr(mDepth));
  finally
    mTree.Free;
  end;
end;

procedure TSyntaxTreeTests.SearchFindsFirstMatchInTreeOrder;
var
  mTree: TSyntaxTree;
  mAll: TList<TSyntaxNode>;
  mExpected, mFound: TSyntaxNode;
  mIndex, mVisits: Integer;
begin
  mTree := TPascalParser.Parse(cSource);
  mAll := TList<TSyntaxNode>.Create;
  try
    CollectRecursive(mTree.Root, mAll);
    mExpected := nil;
    for mIndex := mAll.Count - 1 downto 0 do
    begin
      if mAll[mIndex].Kind = TSyntaxKind.AssignStatement then
      begin
        mExpected := mAll[mIndex];
      end;
    end;
    Assert.IsNotNull(mExpected, 'Zuweisung vorhanden');
    mVisits := 0;
    mFound := mTree.Root.Search(
      function(ANode: TSyntaxNode): TSyntaxSearchStep
      begin
        Inc(mVisits);
        if ANode.Kind = TSyntaxKind.AssignStatement then
        begin
          Exit(TSyntaxSearchStep.Found);
        end;
        Result := TSyntaxSearchStep.Descend;
      end);
    Assert.AreSame(mExpected, mFound, 'erste Zuweisung in Baumreihenfolge');
    // Bis zum Treffer jeder Knoten genau einmal, danach keiner mehr.
    Assert.AreEqual(Integer(mAll.IndexOf(mExpected)) + 1, mVisits);
    Assert.IsNull(mTree.Root.Search(
      function(ANode: TSyntaxNode): TSyntaxSearchStep
      begin
        Result := TSyntaxSearchStep.Descend;
      end), 'ohne Treffer nil');
  finally
    mAll.Free;
    mTree.Free;
  end;
end;

procedure TSyntaxTreeTests.SearchSkipLeavesOutChildren;
var
  mTree: TSyntaxTree;
  mFound: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mFound := mTree.Root.Search(
      function(ANode: TSyntaxNode): TSyntaxSearchStep
      begin
        if ANode.Kind = TSyntaxKind.RoutineDecl then
        begin
          Exit(TSyntaxSearchStep.Skip);
        end;
        if ANode.Kind = TSyntaxKind.Block then
        begin
          Exit(TSyntaxSearchStep.Found);
        end;
        Result := TSyntaxSearchStep.Descend;
      end);
    Assert.IsNull(mFound, 'alle Blöcke liegen in übersprungenen Routinen');
    // Auch die Wurzel selbst kann übersprungen werden.
    Assert.IsNull(mTree.Root.Search(
      function(ANode: TSyntaxNode): TSyntaxSearchStep
      begin
        Result := TSyntaxSearchStep.Skip;
      end));
  finally
    mTree.Free;
  end;
end;

procedure TSyntaxTreeTests.WalkAndSearchOfDeepTreeNeedLittleStack;
var
  mBuilder: TStringBuilder;
  mIndex, mCount: Integer;
  mTree: TSyntaxTree;
  mFound: TSyntaxNode;
  mFailure: string;
begin
  // Wie DepthOfDeepTreeNeedsLittleStack: über 100000 Ebenen.
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('program P; begin X := 1');
    for mIndex := 1 to 100000 do
    begin
      mBuilder.Append('-2');
    end;
    mBuilder.Append('; end.');
    mTree := TPascalParser.Parse(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
  try
    mCount := 0;
    mFound := nil;
    mFailure := TSmallStack.Run(128,
      procedure
      begin
        mTree.Root.Walk(
          function(ANode: TSyntaxNode): Boolean
          begin
            if ANode.Kind = TSyntaxKind.Literal then
            begin
              Inc(mCount);
            end;
            Result := True;
          end);
        // Das erste Glied liegt ganz unten in der linkslastigen Kette.
        mFound := mTree.Root.Search(
          function(ANode: TSyntaxNode): TSyntaxSearchStep
          begin
            if (ANode.Kind = TSyntaxKind.Literal) and (ANode.Name = '1') then
            begin
              Exit(TSyntaxSearchStep.Found);
            end;
            Result := TSyntaxSearchStep.Descend;
          end);
      end);
    Assert.AreEqual('', mFailure);
    Assert.AreEqual(100001, mCount);
    Assert.IsNotNull(mFound, 'erstes Glied gefunden');
  finally
    mTree.Free;
  end;
end;

/// <summary>Zahl der Knoten von der Wurzel bis ANode (Wurzel = 1).</summary>
function LevelOf(ANode: TSyntaxNode): Integer;
var
  mNode: TSyntaxNode;
begin
  Result := 1;
  mNode := ANode;
  while mNode.Parent <> nil do
  begin
    Inc(Result);
    mNode := mNode.Parent;
  end;
end;

procedure TSyntaxTreeTests.DeepestIsFirstNodeAtGreatestDepth;
var
  mTree: TSyntaxTree;
  mAll: TList<TSyntaxNode>;
  mNode, mExpected: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  mAll := TList<TSyntaxNode>.Create;
  try
    CollectRecursive(mTree.Root, mAll);
    mExpected := nil;
    for mNode in mAll do
    begin
      if (mExpected = nil) and (LevelOf(mNode) = mTree.Depth) then
      begin
        mExpected := mNode;
      end;
    end;
    Assert.IsNotNull(mExpected, 'Knoten in größter Tiefe');
    Assert.AreSame(mExpected, mTree.Deepest, 'erster in Baumreihenfolge');
  finally
    mAll.Free;
    mTree.Free;
  end;
  // In einer linkslastigen Kette liegen die ersten beiden Glieder am tiefsten; gemeldet wird das erste.
  mTree := TPascalParser.Parse('program P; begin X := 1 - 2 - 3 - 4; end.');
  try
    Assert.AreEqual('1', mTree.Deepest.Name);
    Assert.AreEqual(LevelOf(mTree.Deepest), mTree.Depth);
  finally
    mTree.Free;
  end;
end;

const
  cTokenSource =
    'unit Probe;'#10 +
    'interface'#10 +
    'implementation'#10 +
    '{ Kommentar'#10 +
    '  über zwei Zeilen }'#10 +
    'procedure Lauf(AWert: Integer);'#10 +
    'const'#10 +
    '  cTab = ^C;'#10 +
    'var'#10 +
    '  mZeiger: ^Integer;'#10 +
    'begin'#10 +
    '  {$IFDEF DEBUG} Writeln(''Text mit Lauf''); {$ENDIF}'#10 +
    '  mZeiger^:=AWert+Ord(cTab);   // Ende'#10 +
    '  &begin.Foo(1).Bar[2] := Self.X;'#10 +
    'end;'#10 +
    'end.'#10;

/// <summary>Die frühere Suche von TNameResolver.TokenIndexAt: linear ab Dateianfang.</summary>
function LinearIdentifierAt(ATree: TSyntaxTree; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
  mToken: TPascalToken;
  function Compare(const A, B: TTextPosition): Integer;
  begin
    if A.Line <> B.Line then
    begin
      Result := A.Line - B.Line;
    end
    else
    begin
      Result := A.Character - B.Character;
    end;
  end;

begin
  for mIndex := 0 to High(ATree.Tokens) do
  begin
    mToken := ATree.Tokens[mIndex];
    if Compare(mToken.StartPos, APosition) > 0 then
    begin
      Break;
    end;
    if (mToken.Kind = TPascalTokenKind.Identifier) and (Compare(APosition, mToken.EndPos) <= 0) then
    begin
      if ATree.IsControlCharPart(mIndex) then
      begin
        Exit(-1);
      end;
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Index des Tokens mit dem Text AText, das als AOccurrence-tes vorkommt (ab 1).</summary>
function TokenNamed(ATree: TSyntaxTree; const AText: string; AOccurrence: Integer): Integer;
var
  mCount, mIndex: Integer;
begin
  mCount := 0;
  for mIndex := 0 to High(ATree.Tokens) do
  begin
    if ATree.Tokens[mIndex].Text = AText then
    begin
      Inc(mCount);
      if mCount = AOccurrence then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := -1;
end;

procedure TSyntaxTreeTests.IdentifierAtCases;
var
  mTree: TSyntaxTree;
  mLauf, mWert: Integer;
  mStart, mEnd: TTextPosition;
begin
  mTree := TPascalParser.Parse(cTokenSource);
  try
    mLauf := TokenNamed(mTree, 'Lauf', 1);
    mStart := mTree.Tokens[mLauf].StartPos;
    mEnd := mTree.Tokens[mLauf].EndPos;
    Assert.AreEqual(mLauf, mTree.IdentifierAt(mStart), 'Anfang');
    Assert.AreEqual(mLauf, mTree.IdentifierAt(TTextPosition.Create(mStart.Line, mStart.Character + 2)), 'Mitte');
    Assert.AreEqual(mLauf, mTree.IdentifierAt(mEnd), 'direkt hinter dem Bezeichner');
    // "Lauf(AWert": Hinter Lauf steht die Klammer, AWert folgt danach.
    mWert := TokenNamed(mTree, 'AWert', 1);
    Assert.AreEqual(mWert, mTree.IdentifierAt(mTree.Tokens[mWert].StartPos));
    // "procedure Lauf": im Leerraum vor dem Bezeichner, direkt hinter einem Schlüsselwort.
    Assert.AreEqual(-1, mTree.IdentifierAt(TTextPosition.Create(mStart.Line, mStart.Character - 1)), 'Leerraum');
    // "AWert+Ord": Am Operator zwischen zwei Bezeichnern gewinnt der vordere.
    mWert := TokenNamed(mTree, 'AWert', 2);
    Assert.AreEqual(mWert, mTree.IdentifierAt(mTree.Tokens[mWert].EndPos));
    // C in ^C ist ein Zeichen, kein Name (#862).
    Assert.AreEqual(-1, mTree.IdentifierAt(mTree.Tokens[TokenNamed(mTree, 'C', 1)].StartPos), '^C');
    Assert.AreEqual(-1, mTree.IdentifierAt(TTextPosition.Create(40, 0)), 'hinter dem letzten Token');
  finally
    mTree.Free;
  end;
  mTree := TPascalParser.Parse('');
  try
    Assert.AreEqual(-1, mTree.IdentifierAt(TTextPosition.Create(0, 0)), 'leere Datei');
  finally
    mTree.Free;
  end;
end;

procedure TSyntaxTreeTests.IdentifierAtMatchesLinearSearch;
var
  mTree: TSyntaxTree;
  mLines: TArray<string>;
  mLine, mCharacter, mChecked: Integer;
  mPosition: TTextPosition;
begin
  mTree := TPascalParser.Parse(cTokenSource);
  try
    mLines := cTokenSource.Split([#10]);
    mChecked := 0;
    // Jede Position jeder Zeile, zwei Zeichen über das Zeilenende hinaus, und zwei Zeilen hinter dem Ende.
    for mLine := 0 to Length(mLines) + 1 do
    begin
      for mCharacter := 0 to 42 do
      begin
        mPosition := TTextPosition.Create(mLine, mCharacter);
        Assert.AreEqual(LinearIdentifierAt(mTree, mPosition), mTree.IdentifierAt(mPosition),
          Format('Zeile %d, Zeichen %d', [mLine, mCharacter]));
        Inc(mChecked);
      end;
    end;
    Assert.IsTrue(mChecked > 500);
  finally
    mTree.Free;
  end;
  mLines := nil;
end;

procedure TSyntaxTreeTests.FirstTokenFromMatchesLinearSearch;
var
  mTree: TSyntaxTree;
  mOffset, mExpected: Integer;
begin
  mTree := TPascalParser.Parse(cTokenSource);
  try
    for mOffset := -1 to Length(cTokenSource) + 1 do
    begin
      mExpected := 0;
      while (mExpected <= High(mTree.Tokens)) and (mTree.Tokens[mExpected].Offset < mOffset) do
      begin
        Inc(mExpected);
      end;
      Assert.AreEqual(mExpected, mTree.FirstTokenFrom(mOffset), Format('Offset %d', [mOffset]));
    end;
  finally
    mTree.Free;
  end;
end;

procedure TSyntaxTreeTests.FirstTokenOfMatchesLinearSearchOnCodeTokens;
var
  mTree: TSyntaxTree;
  mCode: TArray<TPascalToken>;
  mOffset, mExpected, mIndex: Integer;
begin
  // Auch auf einer Auswahl der Token (nur Code, ohne Kommentare und Direktiven) wie die lineare Suche (#1342).
  mTree := TPascalParser.Parse(cTokenSource);
  try
    mCode := nil;
    for mIndex := 0 to High(mTree.Tokens) do
    begin
      if not (mTree.Tokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      begin
        mCode := mCode + [mTree.Tokens[mIndex]];
      end;
    end;
    Assert.IsTrue(Length(mCode) < Length(mTree.Tokens), 'Quelltext mit Kommentaren');
    Assert.AreEqual(0, TSyntaxTree.FirstTokenOf(nil, 5), 'leere Liste');
    for mOffset := -1 to Length(cTokenSource) + 1 do
    begin
      mExpected := 0;
      while (mExpected <= High(mCode)) and (mCode[mExpected].Offset < mOffset) do
      begin
        Inc(mExpected);
      end;
      Assert.AreEqual(mExpected, TSyntaxTree.FirstTokenOf(mCode, mOffset), Format('Offset %d', [mOffset]));
    end;
  finally
    mTree.Free;
  end;
  mCode := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TSyntaxTreeTests);

end.
