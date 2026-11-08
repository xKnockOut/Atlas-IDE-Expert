unit Atlas.IDE.Tracker.Tiles;

// Kacheln des Trackers auf der Willkommensseite (#1455, Vertrag
// Atlas.IDE.Contracts.WelcomeTiles): „Meine Issues“ (#765), „Sprint“
// (#1277) und „Testergebnisse“ (#763). Die Komposition stellt sie über den Scope des Moduls bereit; die
// Willkommensseite zeigt sie mit Titelzeile, Griff und Spalte und legt die
// Ansicht in ihren Rahmen. Kennungen wie früher als Bereiche (atlas.issues,
// atlas.sprint, atlas.tests), damit gespeicherte Layouts gelten. Hauptthread.

interface

uses
  System.Classes,
  Vcl.Controls,
  Atlas.UI.Tracker.TileView,
  Atlas.IDE.Contracts.WelcomeTiles,
  Atlas.IDE.Tracker.MyIssues,
  Atlas.IDE.Tracker.TestResults;

type
  /// <summary>Ansicht einer Kachel für die Seite; reicht an das Steuerelement weiter. Gibt die Seite das Steuerelement
  /// frei, lässt sie auch diese Ansicht los.</summary>
  TAtlasTrackerTileViewLink = class(TInterfacedObject, IAtlasWelcomeTileView)
  private
    FView: TAtlasTrackerTileView;
  public
    constructor Create(AView: TAtlasTrackerTileView; const AHost: IAtlasWelcomeTileHost);
    function Control: TWinControl;
    function BodyHeight: Integer;
    procedure UpdateContent;
  end;

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

  /// <summary>Kachel „Testergebnisse“; zeigt die Quelle ATests.</summary>
  TAtlasTrackerTestsTile = class(TInterfacedObject, IAtlasWelcomeTile)
  private
    FTests: TAtlasIdeTestResults;
    FTestsRef: IInterface;
  public
    constructor Create(ATests: TAtlasIdeTestResults);
    function Info: TAtlasWelcomeTileInfo;
    function Enabled: Boolean;
    function CreateView(AOwner: TComponent; const AHost: IAtlasWelcomeTileHost): IAtlasWelcomeTileView;
  end;

implementation

uses
  System.SysUtils,
  Atlas.IDE.Tracker.SprintTile,
  Atlas.IDE.Tracker.IssuesServices,
  Atlas.UI.Tracker.MyIssues,
  Atlas.UI.Tracker.SprintTile,
  Atlas.UI.Tracker.TestResults;

/// <summary>Höhe an die Seite melden; eigene Routine, damit die Methodenreferenz nur den Host hält.</summary>
function HeightToHost(const AHost: IAtlasWelcomeTileHost): TProc;
begin
  Result :=
    procedure
    begin
      if AHost <> nil then
      begin
        AHost.HeightChanged;
      end;
    end;
end;

{ TAtlasTrackerTileViewLink }

constructor TAtlasTrackerTileViewLink.Create(AView: TAtlasTrackerTileView; const AHost: IAtlasWelcomeTileHost);
begin
  inherited Create;
  FView := AView;
  FView.OnHeightChanged := HeightToHost(AHost);
end;

function TAtlasTrackerTileViewLink.Control: TWinControl;
begin
  Result := FView;
end;

function TAtlasTrackerTileViewLink.BodyHeight: Integer;
begin
  Result := FView.BodyHeight;
end;

procedure TAtlasTrackerTileViewLink.UpdateContent;
begin
  FView.UpdateContent;
end;

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
  Result.Id := TAtlasIdeIssues.cTileId;
  Result.Title := FIssues.TileTitle;
  Result.Order := TAtlasIdeIssues.cOrder;
  Result.Column := TAtlasWelcomeTileColumn.Right;
  // Schalter und Weg zu den Tracker-Einstellungen im Optionsdialog der Willkommensseite (#1903).
  Result.SwitchKey := 'welcomePage.issues';
  Result.SettingsKey := 'issues.tracker';
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
  Result := TAtlasTrackerTileViewLink.Create(mView, AHost);
  mView.Source := FIssues;
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
  Result.Id := TAtlasIdeSprint.cTileId;
  Result.Title := TAtlasTrackerSprintView.TitleText;
  Result.Order := TAtlasIdeSprint.cOrder;
  Result.Column := TAtlasWelcomeTileColumn.Right;
  Result.SwitchKey := 'welcomePage.sprint';
end;

function TAtlasTrackerSprintTile.Enabled: Boolean;
begin
  Result := TAtlasIdeSprint.Active and (FIssues.Services.Sprint <> nil);
end;

function TAtlasTrackerSprintTile.CreateView(AOwner: TComponent;
  const AHost: IAtlasWelcomeTileHost): IAtlasWelcomeTileView;
var
  mView: TAtlasTrackerSprintView;
begin
  Result := nil;
  if FIssues.Services.Sprint = nil then
  begin
    Exit;
  end;
  mView := TAtlasTrackerSprintView.Create(AOwner);
  Result := TAtlasTrackerTileViewLink.Create(mView, AHost);
  mView.Source := FIssues.Services.Sprint;
end;

{ TAtlasTrackerTestsTile }

constructor TAtlasTrackerTestsTile.Create(ATests: TAtlasIdeTestResults);
begin
  inherited Create;
  FTests := ATests;
  FTestsRef := ATests as IAtlasTestResultsSource;
end;

function TAtlasTrackerTestsTile.Info: TAtlasWelcomeTileInfo;
begin
  Result := Default(TAtlasWelcomeTileInfo);
  Result.Id := TAtlasIdeTestResults.cTileId;
  Result.Title := TAtlasIdeTestResults.Title;
  Result.Order := TAtlasIdeTestResults.cOrder;
  Result.Column := TAtlasWelcomeTileColumn.Left;
end;

function TAtlasTrackerTestsTile.Enabled: Boolean;
begin
  Result := TAtlasIdeTestResults.Active;
end;

function TAtlasTrackerTestsTile.CreateView(AOwner: TComponent;
  const AHost: IAtlasWelcomeTileHost): IAtlasWelcomeTileView;
var
  mView: TAtlasTrackerTestResultsView;
begin
  mView := TAtlasTrackerTestResultsView.Create(AOwner);
  Result := TAtlasTrackerTileViewLink.Create(mView, AHost);
  mView.Source := FTests;
end;

end.
