unit Atlas.IDE.Tracker.Tiles;

// Kacheln des Trackers auf der Willkommensseite (#1455, Vertrag
// Atlas.IDE.Contracts.WelcomeTiles): „Meine Issues“ (#765) und „Sprint“
// (#1277). Die Komposition stellt sie über den Scope des Moduls bereit; die
// Willkommensseite zeigt sie mit Titelzeile, Griff und Spalte und legt die
// Ansicht in ihren Rahmen. Kennungen wie früher als Bereiche (atlas.issues,
// atlas.sprint), damit gespeicherte Layouts gelten. Hauptthread.

interface

uses
  System.Classes,
  Atlas.IDE.Contracts.WelcomeTiles,
  Atlas.IDE.Tracker.MyIssues;

type
  /// <summary>Kachel „Meine Issues“; zeigt die Quelle AIssues.</summary>
  TAtlasTrackerIssuesTile = class(TInterfacedObject, IAtlasWelcomeTile)
  private
    FIssues: TAtlasIdeIssues;
    FIssuesRef: IInterface;
  public
    constructor Create(AIssues: TAtlasIdeIssues);
    function Info: TAtlasWelcomeTileInfo;
    function Enabled: Boolean;
    function CreateView(AOwner: TComponent; const AHost: IAtlasWelcomeTileHost): IAtlasWelcomeTileView;
  end;

  /// <summary>Kachel „Sprint“; Quelle ist die Sprint-Steuerung von AIssues (nil vor Start bzw. nach Stop).</summary>
  TAtlasTrackerSprintTile = class(TInterfacedObject, IAtlasWelcomeTile)
  private
    FIssues: TAtlasIdeIssues;
    FIssuesRef: IInterface;
  public
    constructor Create(AIssues: TAtlasIdeIssues);
    function Info: TAtlasWelcomeTileInfo;
    function Enabled: Boolean;
    function CreateView(AOwner: TComponent; const AHost: IAtlasWelcomeTileHost): IAtlasWelcomeTileView;
  end;

implementation

uses
  Atlas.IDE.Tracker.SprintTile,
  Atlas.UI.Tracker.MyIssues,
  Atlas.UI.Tracker.SprintTile;

{ TAtlasTrackerIssuesTile }

constructor TAtlasTrackerIssuesTile.Create(AIssues: TAtlasIdeIssues);
begin
  inherited Create;
  FIssues := AIssues;
  FIssuesRef := AIssues as IAtlasIssuesSource;
end;

function TAtlasTrackerIssuesTile.Info: TAtlasWelcomeTileInfo;
begin
  Result := Default(TAtlasWelcomeTileInfo);
  Result.Id := TAtlasIdeIssues.TileId;
  Result.Title := FIssues.TileTitle;
  Result.Order := TAtlasIdeIssues.Order;
  Result.Column := TAtlasWelcomeTileColumn.Right;
end;

function TAtlasTrackerIssuesTile.Enabled: Boolean;
begin
  Result := TAtlasIdeIssues.Active;
end;

function TAtlasTrackerIssuesTile.CreateView(AOwner: TComponent;
  const AHost: IAtlasWelcomeTileHost): IAtlasWelcomeTileView;
var
  mView: TAtlasTrackerIssuesView;
begin
  mView := TAtlasTrackerIssuesView.Create(AOwner);
  mView.Host := AHost;
  mView.Source := FIssues;
  Result := mView;
end;

{ TAtlasTrackerSprintTile }

constructor TAtlasTrackerSprintTile.Create(AIssues: TAtlasIdeIssues);
begin
  inherited Create;
  FIssues := AIssues;
  FIssuesRef := AIssues as IAtlasIssuesSource;
end;

function TAtlasTrackerSprintTile.Info: TAtlasWelcomeTileInfo;
begin
  Result := Default(TAtlasWelcomeTileInfo);
  Result.Id := TAtlasIdeSprint.TileId;
  Result.Title := TAtlasTrackerSprintView.TitleText;
  Result.Order := TAtlasIdeSprint.Order;
  Result.Column := TAtlasWelcomeTileColumn.Right;
end;

function TAtlasTrackerSprintTile.Enabled: Boolean;
begin
  Result := TAtlasIdeSprint.Active and (FIssues.Sprint <> nil);
end;

function TAtlasTrackerSprintTile.CreateView(AOwner: TComponent;
  const AHost: IAtlasWelcomeTileHost): IAtlasWelcomeTileView;
var
  mView: TAtlasTrackerSprintView;
begin
  Result := nil;
  if FIssues.Sprint = nil then
  begin
    Exit;
  end;
  mView := TAtlasTrackerSprintView.Create(AOwner);
  mView.Host := AHost;
  mView.Source := FIssues.Sprint;
  Result := mView;
end;

end.
