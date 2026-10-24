unit Atlas.Core.UnitRelations.Model.Tests;

// Tests des Kerns des Fensters „Unit-Beziehungen“ (#593): Antwort von
// atlas.unitRelations lesen, filtern samt Vorfahren, Bibliothek abtrennen,
// Argumente der Befehle, Zwischenspeicher je Datei und Tiefe; Verwender nach
// Abschnitt und verschiebbare interface-Einträge (#554).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasUnitRelationsModelTests = class
  public
    [Test]
    procedure ParsesServerAnswer;
    [Test]
    procedure RejectsEmptyOrBrokenAnswer;
    [Test]
    procedure FilterKeepsAncestors;
    [Test]
    procedure SplitsLibraryUnits;
    [Test]
    procedure BuildsCommandArguments;
    [Test]
    procedure CacheKeepsLatestAnswers;
    [Test]
    procedure SplitsUsersBySection;
    [Test]
    procedure CountsMovableEntries;
  end;

/// <summary>Antwort von atlas.unitRelations für A: B (Zyklus), System (Bibliothek, ungenutzt), C → Daten;
/// verwendet von E (interface) und F (implementation).</summary>
function SampleAnswer: string;

implementation

uses
  System.SysUtils,
  Atlas.Core.UnitRelations.Model;

const
  Answer = '{"found":true,"unit":"A","file":"C:\\P\\A.pas","recompileCount":4,"dependencies":3,"dependents":5,' +
    '"inCycle":true,"cyclePath":"A - B - A","uses":[' +
    '{"name":"B","file":"C:\\P\\B.pas","section":"interface","cycle":true,"cyclePath":"A - B - A",' +
    '"location":{"file":"C:\\P\\A.pas","line":3,"character":2},"children":[{"name":"A","section":"interface",' +
    '"repeated":true}]},' +
    '{"name":"System","section":"interface","library":true,"unused":true,' +
    '"location":{"file":"C:\\P\\A.pas","line":3,"character":5}},' +
    '{"name":"C","file":"C:\\P\\C.pas","section":"implementation","children":[{"name":"Daten",' +
    '"file":"C:\\P\\Daten.pas","section":"interface"}]}],' +
    '"usedBy":[{"name":"E","file":"C:\\P\\E.pas","section":"interface"},' +
    '{"name":"F","file":"C:\\P\\F.pas","section":"implementation"}],"generation":17,"depth":0}';

function SampleAnswer: string;
begin
  Result := Answer;
end;

function Names(const AItems: TAtlasUnitRelationList): string;
var
  Item: TAtlasUnitRelation;
begin
  Result := '';
  for Item in AItems do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + Item.Name;
    if Item.Children <> nil then
      Result := Result + '(' + Names(Item.Children) + ')';
  end;
end;

procedure TAtlasUnitRelationsModelTests.ParsesServerAnswer;
var
  Relations: TAtlasUnitRelations;
begin
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(Answer, Relations));
  Assert.IsTrue(Relations.Found);
  Assert.AreEqual('A', Relations.UnitName);
  Assert.AreEqual('C:\P\A.pas', Relations.FileName);
  Assert.AreEqual(4, Relations.RecompileCount);
  Assert.AreEqual(3, Relations.DependencyCount);
  Assert.AreEqual(5, Relations.DependentCount);
  Assert.IsTrue(Relations.InCycle);
  Assert.AreEqual('A - B - A', Relations.CyclePath);
  Assert.AreEqual(Int64(17), Relations.Generation);
  Assert.AreEqual(0, Relations.Depth);
  Assert.AreEqual('B(A),System,C(Daten)', Names(Relations.Uses_));
  Assert.IsTrue(Relations.Uses_[0].InInterface);
  Assert.IsTrue(Relations.Uses_[0].Cycle);
  Assert.AreEqual(3, Relations.Uses_[0].Line);
  Assert.AreEqual(2, Relations.Uses_[0].Character);
  Assert.AreEqual('C:\P\A.pas', Relations.Uses_[0].LocationFile);
  Assert.IsTrue(Relations.Uses_[0].Children[0].Repeated);
  Assert.IsTrue(Relations.Uses_[1].Library_);
  Assert.IsTrue(Relations.Uses_[1].Unused);
  Assert.AreEqual('', Relations.Uses_[1].FileName);
  Assert.IsFalse(Relations.Uses_[2].InInterface);
  Assert.AreEqual(-1, Relations.Uses_[2].Line, 'ohne Fundstelle');
  Assert.AreEqual('E,F', Names(Relations.UsedBy));
  Assert.IsFalse(Relations.UsedBy[1].InInterface);
end;

procedure TAtlasUnitRelationsModelTests.RejectsEmptyOrBrokenAnswer;
var
  Relations: TAtlasUnitRelations;
begin
  Assert.IsFalse(TAtlasUnitRelationsModel.Parse('', Relations));
  Assert.IsFalse(TAtlasUnitRelationsModel.Parse('{"found":true}', Relations), 'ohne "uses"');
  Assert.IsFalse(TAtlasUnitRelationsModel.Parse('[1]', Relations));
  Assert.IsFalse(TAtlasUnitRelationsModel.Parse('{kaputt', Relations));
  Assert.AreEqual(1, Relations.Depth, 'Vorgabe direkt');
end;

procedure TAtlasUnitRelationsModelTests.FilterKeepsAncestors;
var
  Relations: TAtlasUnitRelations;
begin
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(Answer, Relations));
  Assert.AreEqual('C(Daten)', Names(TAtlasUnitRelationsModel.Filter(Relations.Uses_, 'dat')),
    'C bleibt als Vorfahre von Daten');
  Assert.AreEqual('System', Names(TAtlasUnitRelationsModel.Filter(Relations.Uses_, ' SYS ')));
  Assert.AreEqual('B(A),System,C(Daten)', Names(TAtlasUnitRelationsModel.Filter(Relations.Uses_, '')));
  Assert.AreEqual('', Names(TAtlasUnitRelationsModel.Filter(Relations.Uses_, 'xyz')));
  // Das Original bleibt unverändert.
  Assert.AreEqual('B(A),System,C(Daten)', Names(Relations.Uses_));
end;

procedure TAtlasUnitRelationsModelTests.SplitsLibraryUnits;
var
  Relations: TAtlasUnitRelations;
  Project, Library_: TAtlasUnitRelationList;
begin
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(Answer, Relations));
  TAtlasUnitRelationsModel.SplitLibrary(Relations.Uses_, Project, Library_);
  Assert.AreEqual('B(A),C(Daten)', Names(Project));
  Assert.AreEqual('System', Names(Library_));
end;

procedure TAtlasUnitRelationsModelTests.BuildsCommandArguments;
begin
  Assert.AreEqual('["file:///C:/P/A.pas",{"depth":1}]',
    TAtlasUnitRelationsCommands.Arguments('file:///C:/P/A.pas', False));
  Assert.AreEqual('["u",{"depth":0}]', TAtlasUnitRelationsCommands.Arguments('u', True));
  Assert.AreEqual('["u","B","implementation"]', TAtlasUnitRelationsCommands.MoveArguments('u', 'B', False));
  Assert.AreEqual('["u","B","interface"]', TAtlasUnitRelationsCommands.MoveArguments('u', 'B', True));
  Assert.AreEqual('["u","System"]', TAtlasUnitRelationsCommands.RemoveArguments('u', 'System'));
end;

procedure TAtlasUnitRelationsModelTests.CacheKeepsLatestAnswers;
var
  Cache: TAtlasUnitRelationsCache;
  Json: string;
  Index: Integer;
begin
  Cache := TAtlasUnitRelationsCache.Create;
  try
    Cache.Put('C:\P\A.pas', False, 'direkt');
    Cache.Put('C:\P\A.pas', True, 'alle');
    Assert.IsTrue(Cache.TryGet('c:\p\a.PAS', False, Json), 'Groß-/Kleinschreibung zählt nicht');
    Assert.AreEqual('direkt', Json);
    Assert.IsTrue(Cache.TryGet('C:\P\A.pas', True, Json));
    Assert.AreEqual('alle', Json);
    Assert.IsFalse(Cache.TryGet('C:\P\B.pas', False, Json));
    Cache.Put('', False, 'x');
    Cache.Put('C:\P\B.pas', False, '');
    Assert.AreEqual(2, Cache.Count, 'leere Werte nicht merken');
    // A (direkt) wieder anfassen, dann bis über die Grenze füllen: A bleibt, A (alle) fällt heraus.
    Cache.Put('C:\P\A.pas', False, 'neu');
    for Index := 1 to TAtlasUnitRelationsCache.Capacity - 1 do
      Cache.Put('C:\P\U' + IntToStr(Index) + '.pas', False, 'u');
    Assert.AreEqual(TAtlasUnitRelationsCache.Capacity, Cache.Count);
    Assert.IsFalse(Cache.TryGet('C:\P\A.pas', True, Json));
    Assert.IsTrue(Cache.TryGet('C:\P\A.pas', False, Json));
    Assert.AreEqual('neu', Json);
    Cache.Clear;
    Assert.AreEqual(0, Cache.Count);
  finally
    Cache.Free;
  end;
end;

procedure TAtlasUnitRelationsModelTests.SplitsUsersBySection;
var
  Relations: TAtlasUnitRelations;
  Interface_, Implementation_: TAtlasUnitRelationList;
begin
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(Answer, Relations));
  TAtlasUnitRelationsModel.SplitUsedBy(Relations.UsedBy, Interface_, Implementation_);
  Assert.AreEqual('E', Names(Interface_));
  Assert.AreEqual('F', Names(Implementation_));
  TAtlasUnitRelationsModel.SplitUsedBy(nil, Interface_, Implementation_);
  Assert.IsNull(Interface_);
  Assert.IsNull(Implementation_);
end;

procedure TAtlasUnitRelationsModelTests.CountsMovableEntries;
var
  Relations: TAtlasUnitRelations;
begin
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse('{"found":true,"unit":"A","uses":[' +
    '{"name":"B","section":"interface","onlyImplementation":true},' +
    '{"name":"C","section":"interface"},' +
    '{"name":"D","section":"implementation","onlyImplementation":true}],"usedBy":[]}', Relations));
  Assert.IsTrue(Relations.Uses_[0].OnlyImplementation);
  Assert.IsFalse(Relations.Uses_[1].OnlyImplementation);
  Assert.AreEqual(1, TAtlasUnitRelationsModel.Movable(Relations.Uses_), 'nur interface-Einträge');
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(Answer, Relations));
  Assert.AreEqual(0, TAtlasUnitRelationsModel.Movable(Relations.Uses_));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnitRelationsModelTests);

end.
