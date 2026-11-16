unit Atlas.Core.Commands.KeyFallback.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Eine Atlas-Taste ohne Treffer erreicht die Aktion der IDE mit derselben Taste (F9 Fortsetzen,
  /// Strg+F2 Programm beenden), nie eine eigene Aktion von Atlas.</summary>
  [TestFixture]
  TAtlasKeyFallbackTests = class
  public
    [Test]
    procedure RunActionOfIdeIsFound;
    [Test]
    procedure SecondaryShortCutCounts;
    [Test]
    procedure AtlasActionsAreSkipped;
    [Test]
    procedure OrderOfActionListIsKept;
    [Test]
    procedure NoActionWithoutMatch;
    [Test]
    procedure KeyZeroFindsNothing;
  end;

implementation

uses
  Atlas.Core.Commands.KeyFallback;

const
  cF9 = $78;
  cCtrlF2 = $4000 or $71;
  cF8 = $77;

function Action(const ACategory: string; const AShortCuts: TArray<Integer>): TAtlasFallbackAction;
begin
  Result := Default(TAtlasFallbackAction);
  Result.Category := ACategory;
  Result.ShortCuts := AShortCuts;
end;

{ TAtlasKeyFallbackTests }

procedure TAtlasKeyFallbackTests.RunActionOfIdeIsFound;
var
  mFound: TArray<Integer>;
begin
  mFound := TAtlasKeyFallback.Candidates(TArray<TAtlasFallbackAction>.Create(Action('Run', [cF8]),
    Action('Run', [cF9]), Action('Run', [cCtrlF2])), cF9);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(1, mFound[0], 'Start > Ausführen');
  mFound := TAtlasKeyFallback.Candidates(TArray<TAtlasFallbackAction>.Create(Action('Run', [cF8]),
    Action('Run', [cF9]), Action('Run', [cCtrlF2])), cCtrlF2);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(2, mFound[0], 'Programm zurücksetzen');
end;

procedure TAtlasKeyFallbackTests.SecondaryShortCutCounts;
var
  mFound: TArray<Integer>;
begin
  mFound := TAtlasKeyFallback.Candidates(TArray<TAtlasFallbackAction>.Create(Action('Run', [cF8, cF9])), cF9);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(0, mFound[0]);
end;

procedure TAtlasKeyFallbackTests.AtlasActionsAreSkipped;
var
  mFound: TArray<Integer>;
begin
  mFound := TAtlasKeyFallback.Candidates(TArray<TAtlasFallbackAction>.Create(Action('Atlas', [cF9]),
    Action('Atlas.Debuggen', [cF9]), Action('Run', [cF9])), cF9);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(2, mFound[0]);
end;

procedure TAtlasKeyFallbackTests.OrderOfActionListIsKept;
var
  mFound: TArray<Integer>;
begin
  mFound := TAtlasKeyFallback.Candidates(TArray<TAtlasFallbackAction>.Create(Action('Run', [cF9]),
    Action('View', [cF8]), Action('Search', [cF9])), cF9);
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(0, mFound[0]);
  Assert.AreEqual(2, mFound[1]);
end;

procedure TAtlasKeyFallbackTests.NoActionWithoutMatch;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasKeyFallback.Candidates(
    TArray<TAtlasFallbackAction>.Create(Action('Run', [cF8]), Action('Atlas', [cF9])), cF9))));
  Assert.AreEqual(0, Integer(Length(TAtlasKeyFallback.Candidates(nil, cF9))));
end;

procedure TAtlasKeyFallbackTests.KeyZeroFindsNothing;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasKeyFallback.Candidates(
    TArray<TAtlasFallbackAction>.Create(Action('Run', [0])), 0))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasKeyFallbackTests);

end.
