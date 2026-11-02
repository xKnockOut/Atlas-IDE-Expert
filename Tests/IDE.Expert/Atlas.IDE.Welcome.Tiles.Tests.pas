unit Atlas.IDE.Welcome.Tiles.Tests;

// Tests zu TAtlasIdeWelcomeTiles (#1455): Kacheln anderer Module erscheinen als
// Bereich mit Fabrik, sobald ein Modul sie bereitstellt, und verschwinden samt
// Steuerelementen, sobald es sie zurückzieht; Board und Projekte erreichen
// nach dem Stopp nichts mehr.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasIdeWelcomeTilesTests = class
  public
    [Test]
    procedure TileBecomesSection;
    [Test]
    procedure RevokedTileFreesItsControls;
    [Test]
    procedure BoardAndProjectsStopWithTiles;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Contracts.WelcomeTiles,
  Atlas.IDE.Welcome.Tiles;

type
  TFakeView = class(TInterfacedObject, IAtlasWelcomeTileView)
  private
    FControl: TPanel;
  public
    Updates: Integer;
    constructor Create(AOwner: TComponent);
    function Control: TWinControl;
    function BodyHeight: Integer;
    procedure UpdateContent;
  end;

  TFakeTile = class(TInterfacedObject, IAtlasWelcomeTile)
  public
    On_: Boolean;
    LastView: TFakeView;
    LastHost: IAtlasWelcomeTileHost;
    function Info: TAtlasWelcomeTileInfo;
    function Enabled: Boolean;
    function CreateView(AOwner: TComponent; const AHost: IAtlasWelcomeTileHost): IAtlasWelcomeTileView;
  end;

const
  cTileId = 'test.tile';

constructor TFakeView.Create(AOwner: TComponent);
begin
  inherited Create;
  FControl := TPanel.Create(AOwner);
end;

function TFakeView.Control: TWinControl;
begin
  Result := FControl;
end;

function TFakeView.BodyHeight: Integer;
begin
  Result := 77;
end;

procedure TFakeView.UpdateContent;
begin
  Inc(Updates);
end;

function TFakeTile.Info: TAtlasWelcomeTileInfo;
begin
  Result := Default(TAtlasWelcomeTileInfo);
  Result.Id := cTileId;
  Result.Title := 'Kachel';
  Result.Description := 'Zeigt etwas.';
  Result.Order := 42;
  Result.Column := TAtlasWelcomeTileColumn.Right;
end;

function TFakeTile.Enabled: Boolean;
begin
  Result := On_;
end;

function TFakeTile.CreateView(AOwner: TComponent; const AHost: IAtlasWelcomeTileHost): IAtlasWelcomeTileView;
begin
  LastView := TFakeView.Create(AOwner);
  LastHost := AHost;
  Result := LastView;
end;

function NewAccess(const ASelected: string): TAtlasWelcomeProjectsAccess;
begin
  Result := Default(TAtlasWelcomeProjectsAccess);
  Result.Selected :=
    function: string
    begin
      Result := ASelected;
    end;
end;

function FirstOf(const ARegistry: IAtlasModuleRegistry; const AIID: TGUID): IInterface;
var
  mAll: TArray<IInterface>;
begin
  Result := nil;
  mAll := ARegistry.FindAll(AIID);
  if Length(mAll) > 0 then
  begin
    Result := mAll[0];
  end;
end;

procedure TAtlasIdeWelcomeTilesTests.TileBecomesSection;
var
  mRegistry: IAtlasModuleRegistry;
  mSections: TAtlasWelcomeSections;
  mTiles: TAtlasIdeWelcomeTiles;
  mTile: TFakeTile;
  mProvided: IAtlasRegistration;
  mSection: TAtlasWelcomeSection;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mSections := TAtlasWelcomeSections.Create;
  mTiles := TAtlasIdeWelcomeTiles.Create(mRegistry, mSections);
  try
    mTiles.Start(NewAccess(''));
    Assert.AreEqual(0, Integer(Length(mTiles.TileIds)), 'ohne Modul keine Kachel');
    mTile := TFakeTile.Create;
    mProvided := mRegistry.Provide(IAtlasWelcomeTile, mTile as IAtlasWelcomeTile);
    Assert.AreEqual(1, Integer(Length(mTiles.TileIds)), 'Kachel kommt später');
    Assert.IsTrue(mSections.Find(cTileId, mSection));
    Assert.AreEqual('Kachel', mSection.Title);
    Assert.AreEqual('Zeigt etwas.', mSection.Description);
    Assert.AreEqual(42, mSection.Order);
    Assert.IsTrue(mSection.Column = TAtlasWelcomeColumn.Right);
    Assert.IsFalse(mSection.IsEnabled, 'Schalter der Kachel');
    mTile.On_ := True;
    Assert.IsTrue(mSection.IsEnabled);
    Assert.IsTrue(TAtlasWelcomeViews.Exists(cTileId));
    mProvided.Revoke;
    Assert.AreEqual(0, Integer(Length(mTiles.TileIds)));
    Assert.IsFalse(mSections.Find(cTileId, mSection), 'Bereich abgemeldet');
    Assert.IsFalse(TAtlasWelcomeViews.Exists(cTileId), 'Fabrik abgemeldet');
  finally
    mTiles.Free;
    mSections.Free;
  end;
  mSection := Default(TAtlasWelcomeSection);
  mProvided := nil;
  mRegistry := nil;
end;

procedure TAtlasIdeWelcomeTilesTests.RevokedTileFreesItsControls;
var
  mRegistry: IAtlasModuleRegistry;
  mSections: TAtlasWelcomeSections;
  mTiles: TAtlasIdeWelcomeTiles;
  mTile: TFakeTile;
  mKeep: IAtlasWelcomeTile;
  mProvided: IAtlasRegistration;
  mOwner: TComponent;
  mFrame: TAtlasWelcomeSectionFrame;
  mControl: TWinControl;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mSections := TAtlasWelcomeSections.Create;
  mTiles := TAtlasIdeWelcomeTiles.Create(mRegistry, mSections);
  mOwner := TComponent.Create(nil);
  try
    mTiles.Start(NewAccess(''));
    mTile := TFakeTile.Create;
    mKeep := mTile;
    mProvided := mRegistry.Provide(IAtlasWelcomeTile, mKeep);
    mFrame := TAtlasWelcomeViews.CreateView(cTileId, mOwner);
    Assert.IsNotNull(mFrame);
    Assert.AreEqual(cTileId, mFrame.SectionId);
    mControl := mTile.LastView.Control;
    Assert.IsTrue(mControl.Parent = mFrame.Body, 'Inhalt in der Inhaltsfläche');
    mFrame.UpdateContent;
    Assert.AreEqual(1, mTile.LastView.Updates);
    Assert.AreEqual(1, Integer(Length(mTiles.FramesOf(cTileId))));
    mProvided.Revoke;
    Assert.IsFalse((mFrame as TAtlasWelcomeTileFrame).HasView, 'Steuerelement freigegeben');
    Assert.AreEqual(0, mFrame.Body.ControlCount);
    mFrame.UpdateContent;
    Assert.AreEqual(1, mTile.LastView.Updates, 'danach nichts mehr');
    mFrame.Free;
    Assert.AreEqual(0, Integer(Length(mTiles.FramesOf(cTileId))));
  finally
    mOwner.Free;
    mTiles.Free;
    mSections.Free;
  end;
  mTile.LastHost := nil;
  mKeep := nil;
  mProvided := nil;
  mRegistry := nil;
end;

procedure TAtlasIdeWelcomeTilesTests.BoardAndProjectsStopWithTiles;
var
  mRegistry: IAtlasModuleRegistry;
  mSections: TAtlasWelcomeSections;
  mTiles: TAtlasIdeWelcomeTiles;
  mProjects: IAtlasWelcomeProjects;
  mBoard: IAtlasWelcomeBoard;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mSections := TAtlasWelcomeSections.Create;
  mTiles := TAtlasIdeWelcomeTiles.Create(mRegistry, mSections);
  try
    mTiles.Start(NewAccess('C:\P\Kasse.dproj'));
    Assert.IsTrue(Supports(FirstOf(mRegistry, IAtlasWelcomeProjects), IAtlasWelcomeProjects, mProjects));
    Assert.IsTrue(Supports(FirstOf(mRegistry, IAtlasWelcomeBoard), IAtlasWelcomeBoard, mBoard));
    Assert.AreEqual('C:\P\Kasse.dproj', mProjects.Selected);
    Assert.AreEqual(0, Integer(Length(mProjects.Projects)), 'Feld fehlt: leer');
    mTiles.Stop;
    Assert.IsNull(FirstOf(mRegistry, IAtlasWelcomeProjects), 'zurückgezogen');
    Assert.AreEqual('', mProjects.Selected, 'nach dem Stopp nichts mehr');
    mBoard.TileChanged(cTileId);
    mBoard.TileInfoChanged(cTileId);
    Assert.AreEqual(0, Integer(Length(mSections.All)));
  finally
    mTiles.Free;
    mSections.Free;
  end;
  mProjects := nil;
  mBoard := nil;
  mRegistry := nil;
end;

end.
