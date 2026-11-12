unit Atlas.Core.Tracker.BoardLanes.Tests;

// Tests der Swimlanes des Boards ohne Server: Reihenfolge (Werte des Boards,
// weitere nach dem Alphabet), Zeile ohne Wert oben, unten oder ausgeblendet,
// Zuordnung über Anmeldename, eigene Zeile, Filter und Zellen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasBoardLanesTests = class
  public
    /// <summary>Ohne Swimlanes am Board keine Zeilen.</summary>
    [Test]
    procedure NoSwimlanesNoLanes;
    /// <summary>Werte des Boards zuerst (mit Anzeige der Karte), weitere nach dem Alphabet, ohne Wert unten.
    /// </summary>
    [Test]
    procedure LanesFollowBoardThenAlphabet;
    [Test]
    procedure OrphansTopOrHidden;
    /// <summary>Mit Filter nur Zeilen mit sichtbaren Karten.</summary>
    [Test]
    procedure FilteredDropsEmptyLanes;
    [Test]
    procedure CellsAndMine;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.BoardLanes;

function NewCard(const AKey, AState, ALane, ALaneId: string): TAtlasBoardCard;
begin
  Result := Default(TAtlasBoardCard);
  Result.Key := AKey;
  Result.State := AState;
  Result.Lane := ALane;
  Result.LaneId := ALaneId;
  if ALaneId <> '' then
  begin
    Result.Logins := TArray<string>.Create(ALaneId);
  end;
end;

function Sample: TAtlasBoardSnapshot;
begin
  Result := TAtlasBoardSnapshot.Empty;
  Result.Field := 'State';
  Result.Me := 'marco';
  Result.Columns := [TAtlasBoardColumn.Create('Offen', TArray<string>.Create('Open'), '', False),
    TAtlasBoardColumn.Create('In Arbeit', TArray<string>.Create('In Progress'), '', False)];
  Result.Swimlanes.Fields := TArray<string>.Create('Assignee');
  Result.Swimlanes.Caption := 'Zugewiesen an';
  // Das Board kennt Marco (über den Anmeldenamen) und Kollege 3 ohne Karten.
  Result.Swimlanes.Values := TArray<string>.Create('marco', 'Kollege 3');
  Result.Cards := [NewCard('ATL-1', 'Open', 'Bähring, Marco', 'marco'), NewCard('ATL-2', 'In Progress', 'Zander, Udo',
    'udo'), NewCard('ATL-3', 'Open', '', ''), NewCard('ATL-4', 'In Progress', 'Albers, Eva', 'eva'),
    NewCard('ATL-5', 'Open', 'Albers, Eva', 'eva')];
end;

function AllCards(const ASnapshot: TAtlasBoardSnapshot): TArray<Integer>;
begin
  Result := TAtlasTrackerBoard.Visible(ASnapshot, False, '');
end;

function LaneNames(const ALanes: TArray<TAtlasBoardLane>): string;
var
  mLane: TAtlasBoardLane;
begin
  Result := '';
  for mLane in ALanes do
  begin
    if mLane.Orphans then
    begin
      Result := Result + '-;';
    end
    else
    begin
      Result := Result + mLane.Name + ';';
    end;
  end;
end;

procedure TAtlasBoardLanesTests.NoSwimlanesNoLanes;
var
  mSnapshot: TAtlasBoardSnapshot;
begin
  mSnapshot := Sample;
  mSnapshot.Swimlanes := Default(TAtlasBoardSwimlanes);
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasBoardLanes.Build(mSnapshot, AllCards(mSnapshot), False))));
end;

procedure TAtlasBoardLanesTests.LanesFollowBoardThenAlphabet;
var
  mSnapshot: TAtlasBoardSnapshot;
  mLanes: TArray<TAtlasBoardLane>;
begin
  mSnapshot := Sample;
  mLanes := TAtlasBoardLanes.Build(mSnapshot, AllCards(mSnapshot), False);
  Assert.AreEqual('Bähring, Marco;Kollege 3;Albers, Eva;Zander, Udo;-;', LaneNames(mLanes));
  Assert.AreEqual(0, TAtlasBoardLanes.LaneOf(mLanes, mSnapshot.Cards[0]));
  Assert.AreEqual(3, TAtlasBoardLanes.LaneOf(mLanes, mSnapshot.Cards[1]));
  Assert.AreEqual(4, TAtlasBoardLanes.LaneOf(mLanes, mSnapshot.Cards[2]));
  Assert.AreEqual(2, TAtlasBoardLanes.LaneOf(mLanes, mSnapshot.Cards[4]));
end;

procedure TAtlasBoardLanesTests.OrphansTopOrHidden;
var
  mSnapshot: TAtlasBoardSnapshot;
  mLanes: TArray<TAtlasBoardLane>;
begin
  mSnapshot := Sample;
  mSnapshot.Swimlanes.OrphansAtTop := True;
  mLanes := TAtlasBoardLanes.Build(mSnapshot, AllCards(mSnapshot), False);
  Assert.AreEqual('-;Bähring, Marco;Kollege 3;Albers, Eva;Zander, Udo;', LaneNames(mLanes));
  mSnapshot.Swimlanes.HideOrphans := True;
  mLanes := TAtlasBoardLanes.Build(mSnapshot, AllCards(mSnapshot), False);
  Assert.AreEqual('Bähring, Marco;Kollege 3;Albers, Eva;Zander, Udo;', LaneNames(mLanes));
  Assert.AreEqual(-1, TAtlasBoardLanes.LaneOf(mLanes, mSnapshot.Cards[2]), 'ohne Wert ausgeblendet');
  // Alle Karten mit Wert: keine Zeile ohne Wert.
  mSnapshot := Sample;
  Delete(mSnapshot.Cards, 2, 1);
  mLanes := TAtlasBoardLanes.Build(mSnapshot, AllCards(mSnapshot), False);
  Assert.AreEqual('Bähring, Marco;Kollege 3;Albers, Eva;Zander, Udo;', LaneNames(mLanes));
end;

procedure TAtlasBoardLanesTests.FilteredDropsEmptyLanes;
var
  mSnapshot: TAtlasBoardSnapshot;
  mLanes: TArray<TAtlasBoardLane>;
begin
  mSnapshot := Sample;
  mLanes := TAtlasBoardLanes.Build(mSnapshot, TAtlasTrackerBoard.Visible(mSnapshot, True, ''), True);
  Assert.AreEqual('Bähring, Marco;', LaneNames(mLanes));
end;

procedure TAtlasBoardLanesTests.CellsAndMine;
var
  mSnapshot: TAtlasBoardSnapshot;
  mLanes: TArray<TAtlasBoardLane>;
begin
  mSnapshot := Sample;
  mLanes := TAtlasBoardLanes.Build(mSnapshot, AllCards(mSnapshot), False);
  Assert.AreEqual(Integer(1), Integer(Length(TAtlasBoardLanes.CellCards(mSnapshot, mLanes, AllCards(mSnapshot), 0,
    2))), 'Eva in „Offen“');
  Assert.AreEqual(Integer(1), Integer(Length(TAtlasBoardLanes.CellCards(mSnapshot, mLanes, AllCards(mSnapshot), 1,
    2))), 'Eva in „In Arbeit“');
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasBoardLanes.CellCards(mSnapshot, mLanes, AllCards(mSnapshot), 0,
    1))), 'Kollege 3 leer');
  Assert.IsTrue(TAtlasBoardLanes.Mine(mLanes[0], 'MARCO'));
  Assert.IsFalse(TAtlasBoardLanes.Mine(mLanes[2], 'marco'));
  Assert.IsFalse(TAtlasBoardLanes.Mine(mLanes[4], ''));
end;

end.
