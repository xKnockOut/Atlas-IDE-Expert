unit Atlas.Core.Debug.MethodGroupFlow.Tests;

// Tests für die Entscheidungen der Methodenhaltepunkte außerhalb von Suche und Speicher (#855, #1967): Gruppe beim
// Öffnen, gesehene Treffer übernehmen, Umschalten, Namen in der Meldung; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasMethodGroupFlowTests = class
  public
    [Test]
    procedure StartKeepsLastGroup;
    [Test]
    procedure StartNewForOtherPattern;
    [Test]
    procedure MergeKnownSkipsDuplicates;
    [Test]
    procedure ToggleOffOnlyWhenAllOn;
    [Test]
    procedure HitNamesStopAfterFive;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.MethodBreakpoints,
  Atlas.Core.Debug.MethodGroupFlow;

function Group(const APattern: string): TAtlasMethodGroup;
begin
  Result := Default(TAtlasMethodGroup);
  Result.Pattern := APattern;
  Result.Grow := True;
  Result.Condition := 'X > 0';
  Result.Known := ['a', 'b'];
end;

function Hits(ACount: Integer): TAtlasMethodHits;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    Result[mIndex] := Default(TAtlasMethodHit);
    Result[mIndex].Container := 'TKunde';
    Result[mIndex].Name := 'M' + IntToStr(mIndex);
  end;
end;

{ TAtlasMethodGroupFlowTests }

procedure TAtlasMethodGroupFlowTests.StartKeepsLastGroup;
var
  mGroup: TAtlasMethodGroup;
begin
  mGroup := TAtlasMethodGroupFlow.StartGroup(Group('TKunde.*'), '');
  Assert.AreEqual('TKunde.*', mGroup.Pattern);
  Assert.AreEqual('X > 0', mGroup.Condition);
  Assert.IsTrue(mGroup.Grow);
  Assert.AreEqual(0, Integer(Length(mGroup.Known)));
  mGroup := TAtlasMethodGroupFlow.StartGroup(Group('TKunde.*'), 'tkunde.*');
  Assert.AreEqual('X > 0', mGroup.Condition);
end;

procedure TAtlasMethodGroupFlowTests.StartNewForOtherPattern;
var
  mGroup: TAtlasMethodGroup;
begin
  mGroup := TAtlasMethodGroupFlow.StartGroup(Group('TKunde.*'), 'TLager.Buche');
  Assert.AreEqual('TLager.Buche', mGroup.Pattern);
  Assert.AreEqual('', mGroup.Condition);
  Assert.IsFalse(mGroup.Grow);
  Assert.IsTrue(mGroup.Overrides);
  Assert.IsTrue(mGroup.Overloads);
  // Noch keine Gruppe: neu, auch ohne Muster an der Schreibmarke.
  mGroup := TAtlasMethodGroupFlow.StartGroup(Default(TAtlasMethodGroup), '');
  Assert.AreEqual('', mGroup.Pattern);
  Assert.IsTrue(mGroup.Overrides);
end;

procedure TAtlasMethodGroupFlowTests.MergeKnownSkipsDuplicates;
var
  mGroup: TAtlasMethodGroup;
begin
  mGroup := Group('TKunde.*');
  TAtlasMethodGroupFlow.MergeKnown(mGroup, ['b', 'c', 'c']);
  Assert.AreEqual(3, Integer(Length(mGroup.Known)));
  Assert.AreEqual('c', mGroup.Known[2]);
  mGroup.Known := nil;
end;

procedure TAtlasMethodGroupFlowTests.ToggleOffOnlyWhenAllOn;
begin
  Assert.IsFalse(TAtlasMethodGroupFlow.ToggleTo([True, True]));
  Assert.IsTrue(TAtlasMethodGroupFlow.ToggleTo([True, False]));
  Assert.IsFalse(TAtlasMethodGroupFlow.ToggleTo(nil));
end;

procedure TAtlasMethodGroupFlowTests.HitNamesStopAfterFive;
begin
  Assert.AreEqual('', TAtlasMethodGroupFlow.HitNames(nil));
  Assert.AreEqual('TKunde.M0, TKunde.M1', TAtlasMethodGroupFlow.HitNames(Hits(2)));
  Assert.AreEqual('TKunde.M0, TKunde.M1, TKunde.M2, TKunde.M3, TKunde.M4, …',
    TAtlasMethodGroupFlow.HitNames(Hits(7)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMethodGroupFlowTests);

end.
