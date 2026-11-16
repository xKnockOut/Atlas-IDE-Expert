unit Atlas.Common.Metrics.DuplicateBodies.Tests;

// Tests der wortgleichen Rümpfe: Normalisierung (Kommentare, Groß-/Kleinschreibung, Leerraum), Grenzfälle (Kopien in
// derselben Unit, Rümpfe unter der Mindestlänge, erzeugte Units, lokale Routinen) und Reihenfolge der Gruppen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDuplicateBodiesTests = class
  public
    [Test]
    procedure CommentsCaseAndWhitespaceDoNotCount;
    [Test]
    procedure LiteralsAndIdentifiersCount;
    [Test]
    procedure NameAndParametersDoNotCount;
    [Test]
    procedure BodyLinesStartBehindHeader;
    [Test]
    procedure GroupNeedsTwoUnits;
    [Test]
    procedure ShortBodiesDoNotCount;
    [Test]
    procedure GeneratedUnitsAreSkipped;
    [Test]
    procedure LocalRoutineInCopiedOuterIsNoOwnGroup;
    [Test]
    procedure CopiedLocalRoutineAloneIsReported;
    [Test]
    procedure GroupsLongestFirstMembersByPath;
    [Test]
    procedure AsmAndForwardHaveNoBody;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Metrics.DuplicateBodies;

const
  cBody = 'begin'#10'  if A > 0 then'#10'  begin'#10'    Inc(B);'#10'    Writeln(''x'');'#10'  end;'#10'end;'#10;

function UnitText(const AName, ARoutines: string): string;
begin
  Result := 'unit ' + AName + ';'#10'interface'#10'implementation'#10 + ARoutines + 'end.'#10;
end;

function OnlyBody(const AText: string): TRoutineBody;
var
  mBodies: TArray<TRoutineBody>;
begin
  mBodies := TDuplicateBodies.ForText(AText);
  Assert.AreEqual(1, Integer(Length(mBodies)), 'genau eine Routine');
  Result := mBodies[0];
end;

function UnitsOf(const APaths, ATexts: array of string): TArray<TDuplicateBodyUnit>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(APaths));
  for mIndex := 0 to High(APaths) do
  begin
    Result[mIndex] := TDuplicateBodyUnit.Create(APaths[mIndex], TDuplicateBodies.ForText(ATexts[mIndex]));
  end;
end;

{ TDuplicateBodiesTests }

procedure TDuplicateBodiesTests.CommentsCaseAndWhitespaceDoNotCount;
var
  mPlain, mNoisy: TRoutineBody;
begin
  mPlain := OnlyBody(UnitText('A', 'procedure P;'#10 + cBody));
  mNoisy := OnlyBody(UnitText('B', 'procedure P;'#10'// Kopf'#10'BEGIN { Kommentar }'#10'  IF a>0 THEN BEGIN'#10 +
    '    inc(b); (* x *)'#10#10'    WRITELN(''x'')'#10'    ;'#10'  END;'#10'End;'#10));
  Assert.AreEqual(mPlain.Hash, mNoisy.Hash);
end;

procedure TDuplicateBodiesTests.LiteralsAndIdentifiersCount;
var
  mPlain: TRoutineBody;
begin
  mPlain := OnlyBody(UnitText('A', 'procedure P;'#10 + cBody));
  Assert.AreNotEqual(mPlain.Hash, OnlyBody(UnitText('A', 'procedure P;'#10 +
    StringReplace(cBody, '''x''', '''X''', []))).Hash, 'String-Literal');
  Assert.AreNotEqual(mPlain.Hash, OnlyBody(UnitText('A', 'procedure P;'#10 +
    StringReplace(cBody, 'Inc(B)', 'Inc(C)', []))).Hash, 'Bezeichner');
  Assert.AreNotEqual(mPlain.Hash, OnlyBody(UnitText('A', 'procedure P;'#10 +
    StringReplace(cBody, 'A > 0', 'A > 1', []))).Hash, 'Zahl');
end;

procedure TDuplicateBodiesTests.NameAndParametersDoNotCount;
begin
  Assert.AreEqual(OnlyBody(UnitText('A', 'procedure TA.Show;'#10 + cBody)).Hash,
    OnlyBody(UnitText('B', 'function TB.Zeige(const AWert: Integer): Boolean;'#10 + cBody)).Hash);
end;

procedure TDuplicateBodiesTests.BodyLinesStartBehindHeader;
var
  mBody: TRoutineBody;
begin
  mBody := OnlyBody(UnitText('A', 'procedure P(A,'#10'  B: Integer);'#10 + cBody));
  Assert.AreEqual(7, mBody.BodyLines);
  Assert.AreEqual(4, mBody.Line);
  Assert.AreEqual('P', mBody.Name);
end;

procedure TDuplicateBodiesTests.GroupNeedsTwoUnits;
var
  mGroups: TArray<TDuplicateBodyGroup>;
begin
  mGroups := TDuplicateBodies.Find(UnitsOf(['A.pas'], [UnitText('A', 'procedure P;'#10 + cBody +
    'procedure Q;'#10 + cBody)]), 6);
  Assert.AreEqual(0, Integer(Length(mGroups)), 'nur in einer Unit');
  mGroups := TDuplicateBodies.Find(UnitsOf(['A.pas', 'B.pas'], [UnitText('A', 'procedure P;'#10 + cBody +
    'procedure Q;'#10 + cBody), UnitText('B', 'procedure R;'#10 + cBody)]), 6);
  Assert.AreEqual(1, Integer(Length(mGroups)));
  Assert.AreEqual(3, Integer(Length(mGroups[0].Members)), 'alle Fassungen, auch die zweite in A');
  Assert.AreEqual('A.pas:P', mGroups[0].Members[0].Key);
  Assert.AreEqual('A.pas:Q', mGroups[0].Members[1].Key);
  Assert.AreEqual('B.pas:R', mGroups[0].Members[2].Key);
  Assert.AreEqual(7, mGroups[0].BodyLines);
end;

procedure TDuplicateBodiesTests.ShortBodiesDoNotCount;
var
  mUnits: TArray<TDuplicateBodyUnit>;
begin
  mUnits := UnitsOf(['A.pas', 'B.pas'], [UnitText('A', 'procedure P;'#10 + cBody),
    UnitText('B', 'procedure P;'#10 + cBody)]);
  Assert.AreEqual(0, Integer(Length(TDuplicateBodies.Find(mUnits, 8))), 'Mindestlänge 8');
  Assert.AreEqual(1, Integer(Length(TDuplicateBodies.Find(mUnits, 7))), 'Mindestlänge 7');
end;

procedure TDuplicateBodiesTests.GeneratedUnitsAreSkipped;
const
  cHead = 'unit G;'#10#10'// Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json;'#10 +
    '// nicht von Hand ändern.'#10;
begin
  Assert.IsTrue(TDuplicateBodies.IsGenerated(cHead));
  Assert.IsTrue(TDuplicateBodies.IsGenerated('unit G;'#10'// Generated file. DO NOT EDIT.'#10));
  Assert.IsFalse(TDuplicateBodies.IsGenerated(UnitText('A', 'procedure P;'#10 + cBody)));
  Assert.AreEqual(0, Integer(Length(TDuplicateBodies.ForText(cHead + 'interface'#10'implementation'#10 +
    'procedure P;'#10 + cBody + 'end.'))));
end;

procedure TDuplicateBodiesTests.LocalRoutineInCopiedOuterIsNoOwnGroup;
const
  cOuter = 'procedure P;'#10'  procedure Inner;'#10 + cBody + 'begin'#10'  Inner;'#10'end;'#10;
var
  mGroups: TArray<TDuplicateBodyGroup>;
begin
  mGroups := TDuplicateBodies.Find(UnitsOf(['A.pas', 'B.pas'], [UnitText('A', cOuter), UnitText('B', cOuter)]), 6);
  Assert.AreEqual(1, Integer(Length(mGroups)));
  Assert.AreEqual('A.pas:P', mGroups[0].Members[0].Key);
end;

procedure TDuplicateBodiesTests.CopiedLocalRoutineAloneIsReported;
var
  mGroups: TArray<TDuplicateBodyGroup>;
begin
  mGroups := TDuplicateBodies.Find(UnitsOf(['A.pas', 'B.pas'], [
    UnitText('A', 'procedure P;'#10'  procedure Inner;'#10 + cBody + 'begin'#10'  Inner;'#10'end;'#10),
    UnitText('B', 'procedure Q;'#10'  procedure Inner;'#10 + cBody + 'begin'#10'  Inner;'#10'  Inner;'#10'end;'#10)]),
    6);
  Assert.AreEqual(1, Integer(Length(mGroups)));
  Assert.AreEqual('A.pas:P.Inner', mGroups[0].Members[0].Key);
  Assert.AreEqual('B.pas:Q.Inner', mGroups[0].Members[1].Key);
end;

procedure TDuplicateBodiesTests.GroupsLongestFirstMembersByPath;
const
  cLong = 'begin'#10'  A;'#10'  B;'#10'  C;'#10'  D;'#10'  E;'#10'  F;'#10'  G;'#10'end;'#10;
var
  mGroups: TArray<TDuplicateBodyGroup>;
begin
  mGroups := TDuplicateBodies.Find(UnitsOf(['Z.pas', 'b.pas', 'A.pas'], [
    UnitText('Z', 'procedure P;'#10 + cBody + 'procedure L;'#10 + cLong),
    UnitText('B', 'procedure P;'#10 + cBody + 'procedure L;'#10 + cLong),
    UnitText('A', 'procedure P;'#10 + cBody)]), 6);
  Assert.AreEqual(2, Integer(Length(mGroups)));
  Assert.AreEqual(9, mGroups[0].BodyLines, 'längste zuerst');
  Assert.AreEqual('b.pas:L', mGroups[0].Members[0].Key);
  Assert.AreEqual('Z.pas:L', mGroups[0].Members[1].Key);
  Assert.AreEqual('A.pas:P', mGroups[1].Members[0].Key, 'Pfade ohne Groß-/Kleinschreibung sortiert');
end;

procedure TDuplicateBodiesTests.AsmAndForwardHaveNoBody;
begin
  Assert.AreEqual(0, Integer(Length(TDuplicateBodies.ForText(UnitText('A',
    'procedure F; forward;'#10'procedure X; external ''x.dll'';'#10)))));
end;

end.
