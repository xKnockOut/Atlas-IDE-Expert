unit Atlas.IDE.Tracker.Adapters.Sprint;

// Quelle der Sprint-Kachel (#1277), Rolle Adapters: TAtlasSprintSourceAdapter
// erfüllt IAtlasSprintSource aus Atlas.UI.Tracker.Contract.Sprint und reicht
// an TAtlasIdeSprint (Atlas.IDE.Tracker.SprintTile) weiter; hält die Quelle,
// solange eine Ansicht den Adapter hält. Anlegen nur in der Komposition des
// Moduls. Hauptthread.

interface

uses
  Atlas.UI.Tracker.Contract.Sprint,
  Atlas.IDE.Tracker.SprintTile;

type
  /// <summary>Quelle der Sprint-Kachel über ASprint.</summary>
  TAtlasSprintSourceAdapter = class(TInterfacedObject, IAtlasSprintSource)
  private
    FSprint: TAtlasIdeSprint;
    FSprintRef: IInterface;
  public
    constructor Create(ASprint: TAtlasIdeSprint);
    function View: TAtlasSprintTile;
    procedure Shown;
    procedure OpenBoard;
    procedure BrowseBoard;
    procedure FilterIssues(ADone: Boolean);
    procedure AssignProject;
  end;

implementation

{ TAtlasSprintSourceAdapter }

constructor TAtlasSprintSourceAdapter.Create(ASprint: TAtlasIdeSprint);
begin
  inherited Create;
  FSprint := ASprint;
  FSprintRef := ASprint;
end;

function TAtlasSprintSourceAdapter.View: TAtlasSprintTile;
begin
  Result := FSprint.View;
end;

procedure TAtlasSprintSourceAdapter.Shown;
begin
  FSprint.Shown;
end;

procedure TAtlasSprintSourceAdapter.OpenBoard;
begin
  FSprint.OpenBoard;
end;

procedure TAtlasSprintSourceAdapter.BrowseBoard;
begin
  FSprint.BrowseBoard;
end;

procedure TAtlasSprintSourceAdapter.FilterIssues(ADone: Boolean);
begin
  FSprint.FilterIssues(ADone);
end;

procedure TAtlasSprintSourceAdapter.AssignProject;
begin
  FSprint.AssignProject;
end;

end.
