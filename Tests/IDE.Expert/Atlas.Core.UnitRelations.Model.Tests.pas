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
  [Category('Atlas.IDE.Analysis')]
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
  cAnswer = '{"found":true,"unit":"A","file":"C:\\P\\A.pas","recompileCount":4,"dependencies":3,"dependents":5,' +
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
  Result := cAnswer;
end;

function Names(const AItems: TAtlasUnitRelationList): string;
var
  mItem: TAtlasUnitRelation;
begin
  Result := '';
  for mItem in AItems do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mItem.Name;
    if mItem.Children <> nil then
    begin
      Result := Result + '(' + Names(mItem.Children) + ')';
    end;
  end;
end;

procedure TAtlasUnitRelationsModelTests.ParsesServerAnswer;
var
  mRelations: TAtlasUnitRelations;
begin
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(cAnswer, mRelations));
  Assert.IsTrue(mRelations.Found);
  Assert.AreEqual('A', mRelations.UnitName);
  Assert.AreEqual('C:\P\A.pas', mRelations.FileName);
  Assert.AreEqual(4, mRelations.RecompileCount);
  Assert.AreEqual(3, mRelations.DependencyCount);
  Assert.AreEqual(5, mRelations.DependentCount);
  Assert.IsTrue(mRelations.InCycle);
  Assert.AreEqual('A - B - A', mRelations.CyclePath);
  Assert.AreEqual(Int64(17), mRelations.Generation);
  Assert.AreEqual(0, mRelations.Depth);
  Assert.AreEqual('B(A),System,C(Daten)', Names(mRelations.Uses_));
  Assert.IsTrue(mRelations.Uses_[0].InInterface);
  Assert.IsTrue(mRelations.Uses_[0].Cycle);
  Assert.AreEqual(3, mRelations.Uses_[0].Line);
  Assert.AreEqual(2, mRelations.Uses_[0].Character);
  Assert.AreEqual('C:\P\A.pas', mRelations.Uses_[0].LocationFile);
  Assert.IsTrue(mRelations.Uses_[0].Children[0].Repeated);
  Assert.IsTrue(mRelations.Uses_[1].Library_);
  Assert.IsTrue(mRelations.Uses_[1].Unused);
  Assert.AreEqual('', mRelations.Uses_[1].FileName);
  Assert.IsFalse(mRelations.Uses_[2].InInterface);
  Assert.AreEqual(-1, mRelations.Uses_[2].Line, 'ohne Fundstelle');
  Assert.AreEqual('E,F', Names(mRelations.UsedBy));
  Assert.IsFalse(mRelations.UsedBy[1].InInterface);
end;

procedure TAtlasUnitRelationsModelTests.RejectsEmptyOrBrokenAnswer;
var
  mRelations: TAtlasUnitRelations;
begin
  Assert.IsFalse(TAtlasUnitRelationsModel.Parse('', mRelations));
  Assert.IsFalse(TAtlasUnitRelationsModel.Parse('{"found":true}', mRelations), 'ohne "uses"');
  Assert.IsFalse(TAtlasUnitRelationsModel.Parse('[1]', mRelations));
  Assert.IsFalse(TAtlasUnitRelationsModel.Parse('{kaputt', mRelations));
  Assert.AreEqual(1, mRelations.Depth, 'Vorgabe direkt');
end;

procedure TAtlasUnitRelationsModelTests.FilterKeepsAncestors;
var
  mRelations: TAtlasUnitRelations;
begin
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(cAnswer, mRelations));
  Assert.AreEqual('C(Daten)', Names(TAtlasUnitRelationsModel.Filter(mRelations.Uses_, 'dat')),
    'C bleibt als Vorfahre von Daten');
  Assert.AreEqual('System', Names(TAtlasUnitRelationsModel.Filter(mRelations.Uses_, ' SYS ')));
  Assert.AreEqual('B(A),System,C(Daten)', Names(TAtlasUnitRelationsModel.Filter(mRelations.Uses_, '')));
  Assert.AreEqual('', Names(TAtlasUnitRelationsModel.Filter(mRelations.Uses_, 'xyz')));
  // Das Original bleibt unverändert.
  Assert.AreEqual('B(A),System,C(Daten)', Names(mRelations.Uses_));
end;

procedure TAtlasUnitRelationsModelTests.SplitsLibraryUnits;
var
  mRelations: TAtlasUnitRelations;
  mProject, mLibrary_: TAtlasUnitRelationList;
begin
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(cAnswer, mRelations));
  TAtlasUnitRelationsModel.SplitLibrary(mRelations.Uses_, mProject, mLibrary_);
  Assert.AreEqual('B(A),C(Daten)', Names(mProject));
  Assert.AreEqual('System', Names(mLibrary_));
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
  mCache: TAtlasUnitRelationsCache;
  mJson: string;
  mIndex: Integer;
begin
  mCache := TAtlasUnitRelationsCache.Create;
  try
    mCache.Put('C:\P\A.pas', False, 'direkt');
    mCache.Put('C:\P\A.pas', True, 'alle');
    Assert.IsTrue(mCache.TryGet('c:\p\a.PAS', False, mJson), 'Groß-/Kleinschreibung zählt nicht');
    Assert.AreEqual('direkt', mJson);
    Assert.IsTrue(mCache.TryGet('C:\P\A.pas', True, mJson));
    Assert.AreEqual('alle', mJson);
    Assert.IsFalse(mCache.TryGet('C:\P\B.pas', False, mJson));
    mCache.Put('', False, 'x');
    mCache.Put('C:\P\B.pas', False, '');
    Assert.AreEqual(2, mCache.Count, 'leere Werte nicht merken');
    // A (direkt) wieder anfassen, dann bis über die Grenze füllen: A bleibt, A (alle) fällt heraus.
    mCache.Put('C:\P\A.pas', False, 'neu');
    for mIndex := 1 to TAtlasUnitRelationsCache.cCapacity - 1 do
    begin
      mCache.Put('C:\P\U' + IntToStr(mIndex) + '.pas', False, 'u');
    end;
    Assert.AreEqual(TAtlasUnitRelationsCache.cCapacity, mCache.Count);
    Assert.IsFalse(mCache.TryGet('C:\P\A.pas', True, mJson));
    Assert.IsTrue(mCache.TryGet('C:\P\A.pas', False, mJson));
    Assert.AreEqual('neu', mJson);
    mCache.Clear;
    Assert.AreEqual(0, mCache.Count);
  finally
    mCache.Free;
  end;
end;

procedure TAtlasUnitRelationsModelTests.SplitsUsersBySection;
var
  mRelations: TAtlasUnitRelations;
  mInterface_, mImplementation_: TAtlasUnitRelationList;
begin
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(cAnswer, mRelations));
  TAtlasUnitRelationsModel.SplitUsedBy(mRelations.UsedBy, mInterface_, mImplementation_);
  Assert.AreEqual('E', Names(mInterface_));
  Assert.AreEqual('F', Names(mImplementation_));
  TAtlasUnitRelationsModel.SplitUsedBy(nil, mInterface_, mImplementation_);
  Assert.IsNull(mInterface_);
  Assert.IsNull(mImplementation_);
end;

procedure TAtlasUnitRelationsModelTests.CountsMovableEntries;
var
  mRelations: TAtlasUnitRelations;
begin
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse('{"found":true,"unit":"A","uses":[' +
    '{"name":"B","section":"interface","onlyImplementation":true},' +
    '{"name":"C","section":"interface"},' +
    '{"name":"D","section":"implementation","onlyImplementation":true}],"usedBy":[]}', mRelations));
  Assert.IsTrue(mRelations.Uses_[0].OnlyImplementation);
  Assert.IsFalse(mRelations.Uses_[1].OnlyImplementation);
  Assert.AreEqual(1, TAtlasUnitRelationsModel.Movable(mRelations.Uses_), 'nur interface-Einträge');
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(cAnswer, mRelations));
  Assert.AreEqual(0, TAtlasUnitRelationsModel.Movable(mRelations.Uses_));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnitRelationsModelTests);

end.
