unit Atlas.Core.Tracker.BoardLayout.TestSupport;

// Gemeinsames der Board-Tests: ein Board mit drei Spalten (Offen, In Arbeit,
// Erledigt) und vier Karten, zwei davon für „marco“.

interface

uses
  Atlas.Core.Tracker.Board;

/// <summary>Karte AKey im Zustand AState, zugewiesen an ALogin ('' = niemand).</summary>
function SampleCard(const AKey, AState, ALogin: string): TAtlasBoardCard;
/// <summary>Agiles Board: ATL-1 Open (marco), ATL-2 Submitted (anna), ATL-3 In Progress (marco), ATL-4 Done.</summary>
function SampleBoard: TAtlasBoardSnapshot;

implementation

function SampleCard(const AKey, AState, ALogin: string): TAtlasBoardCard;
begin
  Result := Default(TAtlasBoardCard);
  Result.Key := AKey;
  Result.Title := 'Titel ' + AKey;
  Result.State := AState;
  if ALogin <> '' then
  begin
    Result.Logins := TArray<string>.Create(ALogin);
  end;
end;

function SampleBoard: TAtlasBoardSnapshot;
begin
  Result := TAtlasBoardSnapshot.Empty;
  Result.Kind := TAtlasBoardKind.Agile;
  Result.Field := 'State';
  Result.Me := 'marco';
  Result.Columns := [TAtlasBoardColumn.Create('Offen', TArray<string>.Create('Open', 'Submitted'), '', False),
    TAtlasBoardColumn.Create('In Arbeit', TArray<string>.Create('In Progress'), '', False),
    TAtlasBoardColumn.Create('Erledigt', TArray<string>.Create('Done'), '', True)];
  Result.Cards := [SampleCard('ATL-1', 'Open', 'marco'), SampleCard('ATL-2', 'Submitted', 'anna'),
    SampleCard('ATL-3', 'In Progress', 'marco'), SampleCard('ATL-4', 'Done', '')];
end;

end.
