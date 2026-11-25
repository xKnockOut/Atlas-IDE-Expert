unit Atlas.IDE.Tracker.Adapters.Tiles;

// Kacheln des Trackers auf der Willkommensseite (#1455), Rolle Adapters für
// den Vertrag Atlas.IDE.Base.Foundation.WelcomeTiles: „Meine Issues“ (#765),
// „Sprint“ (#1277) und „Testergebnisse“ (#763). Die Komposition stellt sie
// über den Scope des Moduls bereit und reicht die Quellen der Ansichten als
// Adapter herein; die Willkommensseite zeigt sie mit Titelzeile, Griff und
// Spalte und legt die Ansicht in ihren Rahmen. Kennungen wie früher als Bereiche (atlas.issues,
// atlas.sprint, atlas.tests), damit gespeicherte Layouts gelten. Hauptthread.

interface

uses
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Atlas.UI.Tracker.TileView,
  Atlas.UI.Tracker.Contract.MyIssues,
  Atlas.UI.Tracker.Contract.Sprint,
  Atlas.IDE.Base.Foundation.WelcomeTiles,
  Atlas.IDE.Tracker.MyIssues,
  Atlas.UI.Tracker.Contract.TestResults;

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

  /// <summary>Kachel „Meine Issues“; Titel von AIssues, die Ansicht zeigt ASource.</summary>
  TAtlasTrackerIssuesTile = class(TInterfacedObject, IAtlasWelcomeTile)
  private
    FIssues: TAtlasIdeIssues;
    FSource: IAtlasIssuesSource;
  public
    constructor Create(AIssues: TAtlasIdeIssues; const ASource: IAtlasIssuesSource);
    function Info: TAtlasWelcomeTileInfo;
    function Enabled: Boolean;
    function CreateView(AOwner: TComponent; const AHost: IAtlasWelcomeTileHost): IAtlasWelcomeTileView;
  end;

  /// <summary>Kachel „Sprint“; ASource liefert die Quelle zur Sprint-Steuerung von AIssues (nil vor Start bzw.
  /// nach Stop).</summary>
  TAtlasTrackerSprintTile = class(TInterfacedObject, IAtlasWelcomeTile)
  private
    FIssues: TAtlasIdeIssues;
    FIssuesRef: IInterface;
    FSource: TFunc<IAtlasSprintSource>;
  public
    constructor Create(AIssues: TAtlasIdeIssues; const ASource: TFunc<IAtlasSprintSource>);
    function Info: TAtlasWelcomeTileInfo;
    function Enabled: Boolean;
    function CreateView(AOwner: TComponent; const AHost: IAtlasWelcomeTileHost): IAtlasWelcomeTileView;
  end;

  /// <summary>Kachel „Testergebnisse“; die Ansicht zeigt ASource.</summary>
  TAtlasTrackerTestsTile = class(TInterfacedObject, IAtlasWelcomeTile)
  private
    FSource: IAtlasTestResultsSource;
  public
    constructor Create(const ASource: IAtlasTestResultsSource);
    function Info: TAtlasWelcomeTileInfo;
    function Enabled: Boolean;
    function CreateView(AOwner: TComponent; const AHost: IAtlasWelcomeTileHost): IAtlasWelcomeTileView;
  end;

implementation

uses
  Atlas.IDE.Tracker.SprintTile,
  Atlas.UI.Tracker.MyIssues,
  Atlas.UI.Tracker.SprintTile,
  Atlas.IDE.Tracker.TestResults,
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

constructor TAtlasTrackerIssuesTile.Create(AIssues: TAtlasIdeIssues; const ASource: IAtlasIssuesSource);
begin
  inherited Create;
  FIssues := AIssues;
  // Die Quelle hält AIssues am Leben.
  FSource := ASource;
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
  mView.Source := FSource;
end;

{ TAtlasTrackerSprintTile }

constructor TAtlasTrackerSprintTile.Create(AIssues: TAtlasIdeIssues; const ASource: TFunc<IAtlasSprintSource>);
begin
  inherited Create;
  FIssues := AIssues;
  FIssuesRef := AIssues;
  FSource := ASource;
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
  mSource: IAtlasSprintSource;
begin
  Result := nil;
  mSource := nil;
  if Assigned(FSource) then
  begin
    mSource := FSource();
  end;
  if mSource = nil then
  begin
    Exit;
  end;
  mView := TAtlasTrackerSprintView.Create(AOwner);
  Result := TAtlasTrackerTileViewLink.Create(mView, AHost);
  mView.Source := mSource;
end;

{ TAtlasTrackerTestsTile }

constructor TAtlasTrackerTestsTile.Create(const ASource: IAtlasTestResultsSource);
begin
  inherited Create;
  FSource := ASource;
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
  mView.Source := FSource;
end;

end.
