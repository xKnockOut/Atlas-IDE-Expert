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
  Body =
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
  Position: TTextPosition;
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
    Result := Result + '()';
  if ASite.Assigned then
    Result := Result + ':=';
  if not TStepCalls.NamePosition(ASite.Callee, Position) then
    Result := Result + '?';
end;

function TSemanticsStepCallsTests.SitesAt(const AText: string; ALine: Integer; out AStatement: TStepStatement): string;
var
  Site: TStepCallSite;
  Names: TArray<string>;
begin
  FreeAndNil(FTree);
  FTree := TPascalParser.Parse(AText, nil);
  Assert.IsTrue(TStepCalls.Find(FTree, ALine, AStatement), 'keine Anweisung');
  Names := nil;
  for Site in AStatement.Sites do
    Names := Names + [NameOf(Site)];
  Result := string.Join(' ', Names);
end;

procedure TSemanticsStepCallsTests.NestedCallsArgumentsFirst;
var
  Statement: TStepStatement;
begin
  Assert.AreEqual('Kunde Name N Format() Wert Pruefe() Speichere()',
    SitesAt(Body +
    '  Speichere(Kunde.Name, Format(''%d'', [N]), Pruefe(Wert));'#10 +   // 5
    'end;'#10 +
    'end.', 5, Statement));
  Assert.AreEqual(5, Statement.Node.StartPos.Line);
  // Empfänger vor dem Aufruf, Kette von links.
  Assert.AreEqual('A GetB() C() X D()',
    SitesAt(Body + '  A.GetB().C().D(X);'#10 + 'end;'#10 + 'end.', 5, Statement));
end;

procedure TSemanticsStepCallsTests.AssignmentRightSideThenSetter;
var
  Statement: TStepStatement;
begin
  Assert.AreEqual('Quelle Wert Ziel Name:=',
    SitesAt(Body + '  Ziel.Name := Quelle.Wert;'#10 + 'end;'#10 + 'end.', 5, Statement));
  Assert.IsTrue(Statement.Sites[3].Receiver <> nil);
  Assert.AreEqual('Ziel', Statement.Sites[3].Receiver.Name);
  Assert.AreEqual('I Liste[]:=', SitesAt(Body + '  Liste[I] := 0;'#10 + 'end;'#10 + 'end.', 5, Statement));
end;

procedure TSemanticsStepCallsTests.MultiLineStatement;
var
  Statement: TStepStatement;
begin
  // Ausführungspunkt in der Folgezeile einer mehrzeiligen Anweisung: die ganze Anweisung.
  Assert.AreEqual('A() B() C()',
    SitesAt(Body + '  C(A(),'#10 + '    B());'#10 + 'end;'#10 + 'end.', 6, Statement));
  Assert.AreEqual(5, Statement.Node.StartPos.Line);
end;

procedure TSemanticsStepCallsTests.IfOnOneLineIncludesBranch;
var
  Statement: TStepStatement;
begin
  Assert.AreEqual('Bereit() Tu() Lass()',
    SitesAt(Body + '  if Bereit() then Tu() else Lass();'#10 + 'end;'#10 + 'end.', 5, Statement));
  Assert.AreEqual(Ord(TSyntaxKind.IfStatement), Ord(Statement.Node.Kind));
end;

procedure TSemanticsStepCallsTests.IfBranchOnOwnLineIsSeparate;
var
  Statement: TStepStatement;
begin
  Assert.AreEqual('Bereit()',
    SitesAt(Body + '  if Bereit() then'#10 + '    Tu();'#10 + 'end;'#10 + 'end.', 5, Statement));
  Assert.AreEqual('Tu()',
    SitesAt(Body + '  if Bereit() then'#10 + '    Tu();'#10 + 'end;'#10 + 'end.', 6, Statement));
end;

procedure TSemanticsStepCallsTests.UntilLineOnlyCondition;
var
  Statement: TStepStatement;
begin
  Assert.AreEqual('Fertig()',
    SitesAt(Body + '  repeat'#10 + '    Tu();'#10 + '  until Fertig();'#10 + 'end;'#10 + 'end.', 7, Statement));
  Assert.AreEqual(Ord(TSyntaxKind.RepeatStatement), Ord(Statement.Node.Kind));
end;

procedure TSemanticsStepCallsTests.WithExpressionAndIndexAccess;
var
  Statement: TStepStatement;
begin
  Assert.AreEqual('TKunde Create',
    SitesAt(Body + '  with TKunde.Create do'#10 + '    Free;'#10 + 'end;'#10 + 'end.', 5, Statement));
  Assert.AreEqual('Free',
    SitesAt(Body + '  with TKunde.Create do'#10 + '    Free;'#10 + 'end;'#10 + 'end.', 6, Statement));
  Assert.AreEqual('Liste I Items[] Name Zeige()',
    SitesAt(Body + '  Zeige(Liste.Items[I].Name);'#10 + 'end;'#10 + 'end.', 5, Statement));
end;

procedure TSemanticsStepCallsTests.AddressOfAndAnonymousMethodSkipped;
var
  Statement: TStepStatement;
begin
  Assert.AreEqual('Starte()',
    SitesAt(Body + '  Starte(@Rueckruf, procedure begin Tu(); end);'#10 + 'end;'#10 + 'end.', 5, Statement));
  Assert.AreEqual('inherited Create',
    SitesAt(Body + '  inherited Create;'#10 + 'end;'#10 + 'end.', 5, Statement));
end;

procedure TSemanticsStepCallsTests.FollowLineNextStatement;
var
  Statement: TStepStatement;
begin
  SitesAt(Body + '  if A then B;'#10 + '  C;'#10 + 'end;'#10 + 'end.', 5, Statement);
  Assert.AreEqual(6, Statement.FollowLine);
  // Letzte Anweisung eines then-Blocks: die Anweisung nach dem if.
  SitesAt(Body + '  if A then'#10 + '  begin'#10 + '    B;'#10 + '  end;'#10 + '  C;'#10 + 'end;'#10 + 'end.', 7,
    Statement);
  Assert.AreEqual(9, Statement.FollowLine);
end;

procedure TSemanticsStepCallsTests.FollowLineLoopAndRoutineEnd;
var
  Statement: TStepStatement;
begin
  SitesAt(Body + '  while A do'#10 + '  begin'#10 + '    B;'#10 + '  end;'#10 + 'end;'#10 + 'end.', 7, Statement);
  Assert.AreEqual(5, Statement.FollowLine);
  SitesAt(Body + '  repeat'#10 + '    B;'#10 + '  until C;'#10 + 'end;'#10 + 'end.', 6, Statement);
  Assert.AreEqual(7, Statement.FollowLine);
  // Letzte Anweisung der Routine: ihr end.
  SitesAt(Body + '  B;'#10 + 'end;'#10 + 'end.', 5, Statement);
  Assert.AreEqual(6, Statement.FollowLine);
end;

procedure TSemanticsStepCallsTests.FollowLineFinally;
var
  Statement: TStepStatement;
begin
  SitesAt(Body + '  try'#10 + '    B;'#10 + '  finally'#10 + '    C;'#10 + '  end;'#10 + '  D;'#10 + 'end;'#10 +
    'end.', 6, Statement);
  Assert.AreEqual(8, Statement.FollowLine);
  SitesAt(Body + '  try'#10 + '    B;'#10 + '  finally'#10 + '    C;'#10 + '  end;'#10 + '  D;'#10 + 'end;'#10 +
    'end.', 8, Statement);
  Assert.AreEqual(10, Statement.FollowLine);
end;

procedure TSemanticsStepCallsTests.NamePositionOfMember;
var
  Statement: TStepStatement;
  Position: TTextPosition;
begin
  SitesAt(Body + '  Kunde.Speichere(1);'#10 + 'end;'#10 + 'end.', 5, Statement);
  Assert.IsTrue(TStepCalls.NamePosition(Statement.Sites[1].Callee, Position));
  Assert.AreEqual(5, Position.Line);
  Assert.AreEqual(8, Position.Character);
end;

initialization
  TDUnitX.RegisterTestFixture(TSemanticsStepCallsTests);

end.
