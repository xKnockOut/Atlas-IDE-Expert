unit Atlas.Common.Semantics.StepCalls.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.StepCalls;

type
  [TestFixture]
  TSemanticsStepCallsTests = class
  private
    FTree: TSyntaxTree;
    function SitesAt(const AText: string; ALine: Integer; out AStatement: TStepStatement): string;
    function NameOf(const ASite: TStepCallSite): string;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure NestedCallsArgumentsFirst;
    [Test]
    procedure AssignmentRightSideThenSetter;
    [Test]
    procedure MultiLineStatement;
    [Test]
    procedure IfOnOneLineIncludesBranch;
    [Test]
    procedure IfBranchOnOwnLineIsSeparate;
    [Test]
    procedure UntilLineOnlyCondition;
    [Test]
    procedure WithExpressionAndIndexAccess;
    [Test]
    procedure AddressOfAndAnonymousMethodSkipped;
    [Test]
    procedure FollowLineNextStatement;
    [Test]
    procedure FollowLineLoopAndRoutineEnd;
    [Test]
    procedure FollowLineFinally;
    [Test]
    procedure NamePositionOfMember;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Parser;

const
  cBody =
    'unit U;'#10 +                                              // 0
    'interface'#10 +                                            // 1
    'implementation'#10 +                                       // 2
    'procedure P;'#10 +                                         // 3
    'begin'#10;                                                 // 4

procedure TSemanticsStepCallsTests.TearDown;
begin
  FreeAndNil(FTree);
end;

function TSemanticsStepCallsTests.NameOf(const ASite: TStepCallSite): string;
var
  mPosition: TTextPosition;
begin
  case ASite.Node.Kind of
    TSyntaxKind.IndexAccess:
      Result := ASite.Callee.Name + '[]';
    TSyntaxKind.InheritedExpr:
      Result := 'inherited ' + ASite.Node.Name;
  else
    Result := ASite.Callee.Name;
  end;
  if ASite.Explicit then
  begin
    Result := Result + '()';
  end;
  if ASite.Assigned then
  begin
    Result := Result + ':=';
  end;
  if not TStepCalls.NamePosition(ASite.Callee, mPosition) then
  begin
    Result := Result + '?';
  end;
end;

function TSemanticsStepCallsTests.SitesAt(const AText: string; ALine: Integer; out AStatement: TStepStatement): string;
var
  mSite: TStepCallSite;
  mNames: TArray<string>;
begin
  FreeAndNil(FTree);
  FTree := TPascalParser.Parse(AText, nil);
  Assert.IsTrue(TStepCalls.Find(FTree, ALine, AStatement), 'keine Anweisung');
  mNames := nil;
  for mSite in AStatement.Sites do
  begin
    mNames := mNames + [NameOf(mSite)];
  end;
  Result := string.Join(' ', mNames);
end;

procedure TSemanticsStepCallsTests.NestedCallsArgumentsFirst;
var
  mStatement: TStepStatement;
begin
  Assert.AreEqual('Kunde Name N Format() Wert Pruefe() Speichere()',
    SitesAt(cBody +
    '  Speichere(Kunde.Name, Format(''%d'', [N]), Pruefe(Wert));'#10 +   // 5
    'end;'#10 +
    'end.', 5, mStatement));
  Assert.AreEqual(5, mStatement.Node.StartPos.Line);
  // Empfänger vor dem Aufruf, Kette von links.
  Assert.AreEqual('A GetB() C() X D()',
    SitesAt(cBody + '  A.GetB().C().D(X);'#10 + 'end;'#10 + 'end.', 5, mStatement));
end;

procedure TSemanticsStepCallsTests.AssignmentRightSideThenSetter;
var
  mStatement: TStepStatement;
begin
  Assert.AreEqual('Quelle Wert Ziel Name:=',
    SitesAt(cBody + '  Ziel.Name := Quelle.Wert;'#10 + 'end;'#10 + 'end.', 5, mStatement));
  Assert.IsNotNull(mStatement.Sites[3].Receiver);
  Assert.AreEqual('Ziel', mStatement.Sites[3].Receiver.Name);
  Assert.AreEqual('I Liste[]:=', SitesAt(cBody + '  Liste[I] := 0;'#10 + 'end;'#10 + 'end.', 5, mStatement));
end;

procedure TSemanticsStepCallsTests.MultiLineStatement;
var
  mStatement: TStepStatement;
begin
  // Ausführungspunkt in der Folgezeile einer mehrzeiligen Anweisung: die ganze Anweisung.
  Assert.AreEqual('A() B() C()',
    SitesAt(cBody + '  C(A(),'#10 + '    B());'#10 + 'end;'#10 + 'end.', 6, mStatement));
  Assert.AreEqual(5, mStatement.Node.StartPos.Line);
end;

procedure TSemanticsStepCallsTests.IfOnOneLineIncludesBranch;
var
  mStatement: TStepStatement;
begin
  Assert.AreEqual('Bereit() Tu() Lass()',
    SitesAt(cBody + '  if Bereit() then Tu() else Lass();'#10 + 'end;'#10 + 'end.', 5, mStatement));
  Assert.AreEqual(Ord(TSyntaxKind.IfStatement), Ord(mStatement.Node.Kind));
end;

procedure TSemanticsStepCallsTests.IfBranchOnOwnLineIsSeparate;
var
  mStatement: TStepStatement;
begin
  Assert.AreEqual('Bereit()',
    SitesAt(cBody + '  if Bereit() then'#10 + '    Tu();'#10 + 'end;'#10 + 'end.', 5, mStatement));
  Assert.AreEqual('Tu()',
    SitesAt(cBody + '  if Bereit() then'#10 + '    Tu();'#10 + 'end;'#10 + 'end.', 6, mStatement));
end;

procedure TSemanticsStepCallsTests.UntilLineOnlyCondition;
var
  mStatement: TStepStatement;
begin
  Assert.AreEqual('Fertig()',
    SitesAt(cBody + '  repeat'#10 + '    Tu();'#10 + '  until Fertig();'#10 + 'end;'#10 + 'end.', 7, mStatement));
  Assert.AreEqual(Ord(TSyntaxKind.RepeatStatement), Ord(mStatement.Node.Kind));
end;

procedure TSemanticsStepCallsTests.WithExpressionAndIndexAccess;
var
  mStatement: TStepStatement;
begin
  Assert.AreEqual('TKunde Create',
    SitesAt(cBody + '  with TKunde.Create do'#10 + '    Free;'#10 + 'end;'#10 + 'end.', 5, mStatement));
  Assert.AreEqual('Free',
    SitesAt(cBody + '  with TKunde.Create do'#10 + '    Free;'#10 + 'end;'#10 + 'end.', 6, mStatement));
  Assert.AreEqual('Liste I Items[] Name Zeige()',
    SitesAt(cBody + '  Zeige(Liste.Items[I].Name);'#10 + 'end;'#10 + 'end.', 5, mStatement));
end;

procedure TSemanticsStepCallsTests.AddressOfAndAnonymousMethodSkipped;
var
  mStatement: TStepStatement;
begin
  Assert.AreEqual('Starte()',
    SitesAt(cBody + '  Starte(@Rueckruf, procedure begin Tu(); end);'#10 + 'end;'#10 + 'end.', 5, mStatement));
  Assert.AreEqual('inherited Create',
    SitesAt(cBody + '  inherited Create;'#10 + 'end;'#10 + 'end.', 5, mStatement));
end;

procedure TSemanticsStepCallsTests.FollowLineNextStatement;
var
  mStatement: TStepStatement;
begin
  SitesAt(cBody + '  if A then B;'#10 + '  C;'#10 + 'end;'#10 + 'end.', 5, mStatement);
  Assert.AreEqual(6, mStatement.FollowLine);
  // Letzte Anweisung eines then-Blocks: die Anweisung nach dem if.
  SitesAt(cBody + '  if A then'#10 + '  begin'#10 + '    B;'#10 + '  end;'#10 + '  C;'#10 + 'end;'#10 + 'end.', 7,
    mStatement);
  Assert.AreEqual(9, mStatement.FollowLine);
end;

procedure TSemanticsStepCallsTests.FollowLineLoopAndRoutineEnd;
var
  mStatement: TStepStatement;
begin
  SitesAt(cBody + '  while A do'#10 + '  begin'#10 + '    B;'#10 + '  end;'#10 + 'end;'#10 + 'end.', 7, mStatement);
  Assert.AreEqual(5, mStatement.FollowLine);
  SitesAt(cBody + '  repeat'#10 + '    B;'#10 + '  until C;'#10 + 'end;'#10 + 'end.', 6, mStatement);
  Assert.AreEqual(7, mStatement.FollowLine);
  // Letzte Anweisung der Routine: ihr end.
  SitesAt(cBody + '  B;'#10 + 'end;'#10 + 'end.', 5, mStatement);
  Assert.AreEqual(6, mStatement.FollowLine);
end;

procedure TSemanticsStepCallsTests.FollowLineFinally;
var
  mStatement: TStepStatement;
begin
  SitesAt(cBody + '  try'#10 + '    B;'#10 + '  finally'#10 + '    C;'#10 + '  end;'#10 + '  D;'#10 + 'end;'#10 +
    'end.', 6, mStatement);
  Assert.AreEqual(8, mStatement.FollowLine);
  SitesAt(cBody + '  try'#10 + '    B;'#10 + '  finally'#10 + '    C;'#10 + '  end;'#10 + '  D;'#10 + 'end;'#10 +
    'end.', 8, mStatement);
  Assert.AreEqual(10, mStatement.FollowLine);
end;

procedure TSemanticsStepCallsTests.NamePositionOfMember;
var
  mStatement: TStepStatement;
  mPosition: TTextPosition;
begin
  SitesAt(cBody + '  Kunde.Speichere(1);'#10 + 'end;'#10 + 'end.', 5, mStatement);
  Assert.IsTrue(TStepCalls.NamePosition(mStatement.Sites[1].Callee, mPosition));
  Assert.AreEqual(5, mPosition.Line);
  Assert.AreEqual(8, mPosition.Character);
end;

initialization
  TDUnitX.RegisterTestFixture(TSemanticsStepCallsTests);

end.
