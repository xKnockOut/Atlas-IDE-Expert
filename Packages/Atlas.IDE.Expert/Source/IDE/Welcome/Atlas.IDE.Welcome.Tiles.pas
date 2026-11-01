unit Atlas.IDE.Welcome.Tiles;

// Kacheln anderer Module auf der Willkommensseite (#1455, ADR 0017 Regel 2,
// 3 und 4; Vertrag Atlas.IDE.Contracts.WelcomeTiles): TAtlasIdeWelcomeTiles
// beobachtet die Registry auf IAtlasWelcomeTile und meldet jede Kachel als
// Bereich (TAtlasWelcomeSections) mit Fabrik (TAtlasWelcomeViews) an. Die
// Fabrik baut einen Bereichsrahmen mit Titelzeile und legt die Ansicht der
// Kachel in dessen Inhaltsfläche. Zieht ein Modul seine Kachel zurück, gibt
// TAtlasIdeWelcomeTiles sofort alle Steuerelemente der Kachel frei und meldet
// den Bereich ab: Danach ruft die Seite keinen Code des Moduls mehr auf
// (Regel 3), auch wenn sie ihre Rahmen erst später neu ordnet.
// Umgekehrt stellt es IAtlasWelcomeBoard und IAtlasWelcomeProjects bereit.
// Alles im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Watch,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Contracts.WelcomeTiles;

type
  TAtlasIdeWelcomeTiles = class;

  /// <summary>Projekte des Bereichs „Projekte“; ohne Bereich (nil) leer.</summary>
  TAtlasWelcomeProjectsQuery = reference to function: TArray<TAtlasWelcomeProject>;

  /// <summary>Was IAtlasWelcomeProjects über den Bereich „Projekte“ erreicht; jedes Feld darf fehlen.</summary>
  TAtlasWelcomeProjectsAccess = record
    Projects: TAtlasWelcomeProjectsQuery;
    Selected: TFunc<string>;
    Open: TProc<string>;
    Refresh: TProc<string>;
  end;

  /// <summary>Stellt ein Objekt bereit: über den Scope des Moduls, in Tests über die Registry.</summary>
  TAtlasWelcomeProvide = reference to function(const AIID: TGUID; const AObject: IInterface): IAtlasRegistration;

  /// <summary>Bereichsrahmen einer Kachel: Titelzeile von der Seite, Inhalt von der Kachel.</summary>
  TAtlasWelcomeTileFrame = class(TAtlasWelcomeSectionFrame)
  private type
    THost = class(TInterfacedObject, IAtlasWelcomeTileHost)
    private
      FFrame: TAtlasWelcomeTileFrame;
    public
      procedure HeightChanged;
    end;
  private
    FTiles: TAtlasIdeWelcomeTiles;
    FHost: THost;
    FHostRef: IAtlasWelcomeTileHost;
    FView: IAtlasWelcomeTileView;
    procedure Attach(const AView: IAtlasWelcomeTileView);
  protected
    function BodyHeight: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure UpdateContent; override;
    /// <summary>Steuerelement der Kachel freigeben und die Ansicht vergessen; der Rahmen bleibt leer.</summary>
    procedure Detach;
    function HasView: Boolean;
  end;

  TAtlasIdeWelcomeTiles = class
  private type
    TBoard = class(TInterfacedObject, IAtlasWelcomeBoard)
    private
      FOwner: TAtlasIdeWelcomeTiles;
    public
      procedure TileChanged(const AId: string);
      procedure TileInfoChanged(const AId: string);
    end;

    TProjects = class(TInterfacedObject, IAtlasWelcomeProjects)
    private
      FAccess: TAtlasWelcomeProjectsAccess;
      FStopped: Boolean;
    public
      function Projects: TArray<TAtlasWelcomeProject>;
      function Selected: string;
      procedure Open(const AProject: string);
      procedure Refresh(const AProject: string);
    end;
  private
    FRegistry: IAtlasModuleRegistry;
    FProvide: TAtlasWelcomeProvide;
    FSections: TAtlasWelcomeSections;
    FWatch: TAtlasProvidedWatch;
    FTiles: TDictionary<string, IAtlasWelcomeTile>;
    FFrames: TList<TAtlasWelcomeTileFrame>;
    FBoard: TBoard;
    FBoardRef: IAtlasWelcomeBoard;
    FProjects: TProjects;
    FProjectsRef: IAtlasWelcomeProjects;
    FProvided: TArray<IAtlasRegistration>;
    procedure Sync;
    function Current: TDictionary<string, IAtlasWelcomeTile>;
    procedure Withdraw(const AId: string);
    procedure Announce(const AId: string; const ATile: IAtlasWelcomeTile);
    function CreateFrame(const AId: string; AOwner: TComponent): TAtlasWelcomeSectionFrame;
    procedure FrameGone(AFrame: TAtlasWelcomeTileFrame);
    procedure ProvideServices(const AProjects: TAtlasWelcomeProjectsAccess);
    procedure RevokeServices;
  public
    /// <summary>ARegistry darf nil sein (dann keine Kacheln); ASections: Bereiche, in Tests eigene.</summary>
    constructor Create(const ARegistry: IAtlasModuleRegistry; ASections: TAtlasWelcomeSections); overload;
    /// <summary>Wie oben; Board und Projekte stellt AProvide bereit (Scope des Moduls, Regel 4).</summary>
    constructor Create(const ARegistry: IAtlasModuleRegistry; const AProvide: TAtlasWelcomeProvide;
      ASections: TAtlasWelcomeSections); overload;
    destructor Destroy; override;
    /// <summary>Kacheln anmelden, auf die Registry hören, Board und Projekte bereitstellen.</summary>
    procedure Start(const AProjects: TAtlasWelcomeProjectsAccess);
    /// <summary>Alle Kacheln samt Ansichten abmelden, Dienste zurückziehen; danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Kennungen der angemeldeten Kacheln.</summary>
    function TileIds: TArray<string>;
    /// <summary>Lebende Rahmen der Kachel AId (mit oder ohne Ansicht).</summary>
    function FramesOf(const AId: string): TArray<TAtlasWelcomeTileFrame>;
    /// <summary>Bereich zur Kachel ATile.</summary>
    class function SectionOf(const ATile: IAtlasWelcomeTile): TAtlasWelcomeSection; static;
  end;

implementation

uses
  Vcl.Controls;

{ TAtlasWelcomeTileFrame.THost }

procedure TAtlasWelcomeTileFrame.THost.HeightChanged;
begin
  if FFrame <> nil then
  begin
    FFrame.HeightChanged;
  end;
end;

{ TAtlasWelcomeTileFrame }

constructor TAtlasWelcomeTileFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHost := THost.Create;
  FHost.FFrame := Self;
  FHostRef := FHost;
end;

destructor TAtlasWelcomeTileFrame.Destroy;
begin
  FHost.FFrame := nil;
  FHostRef := nil;
  FView := nil;
  if FTiles <> nil then
  begin
    FTiles.FrameGone(Self);
  end;
  inherited Destroy;
end;

procedure TAtlasWelcomeTileFrame.Attach(const AView: IAtlasWelcomeTileView);
var
  mControl: TWinControl;
begin
  FView := AView;
  if FView = nil then
  begin
    Exit;
  end;
  mControl := FView.Control;
  if mControl <> nil then
  begin
    mControl.Parent := Body;
    mControl.Align := alClient;
  end;
end;

procedure TAtlasWelcomeTileFrame.Detach;
var
  mControl: TWinControl;
begin
  if FView = nil then
  begin
    Exit;
  end;
  mControl := FView.Control;
  // Erst die Ansicht vergessen: Ist sie das Steuerelement selbst, zählt sie keine Referenzen.
  FView := nil;
  mControl.Free;
  Invalidate;
end;

function TAtlasWelcomeTileFrame.HasView: Boolean;
begin
  Result := FView <> nil;
end;

function TAtlasWelcomeTileFrame.BodyHeight: Integer;
begin
  Result := 0;
  if FView <> nil then
  begin
    Result := FView.BodyHeight;
  end;
end;

procedure TAtlasWelcomeTileFrame.UpdateContent;
begin
  if FView <> nil then
  begin
    FView.UpdateContent;
  end;
  inherited UpdateContent;
end;

{ TAtlasIdeWelcomeTiles.TBoard }

procedure TAtlasIdeWelcomeTiles.TBoard.TileChanged(const AId: string);
begin
  if (FOwner <> nil) and FOwner.FTiles.ContainsKey(AId) then
  begin
    FOwner.FSections.Changed(AId);
  end;
end;

procedure TAtlasIdeWelcomeTiles.TBoard.TileInfoChanged(const AId: string);
var
  mTile: IAtlasWelcomeTile;
begin
  if (FOwner <> nil) and FOwner.FTiles.TryGetValue(AId, mTile) then
  begin
    FOwner.FSections.Add(SectionOf(mTile));
  end;
end;

{ TAtlasIdeWelcomeTiles.TProjects }

function TAtlasIdeWelcomeTiles.TProjects.Projects: TArray<TAtlasWelcomeProject>;
begin
  Result := nil;
  if not FStopped and Assigned(FAccess.Projects) then
  begin
    Result := FAccess.Projects();
  end;
end;

function TAtlasIdeWelcomeTiles.TProjects.Selected: string;
begin
  Result := '';
  if not FStopped and Assigned(FAccess.Selected) then
  begin
    Result := FAccess.Selected();
  end;
end;

procedure TAtlasIdeWelcomeTiles.TProjects.Open(const AProject: string);
begin
  if not FStopped and Assigned(FAccess.Open) then
  begin
    FAccess.Open(AProject);
  end;
end;

procedure TAtlasIdeWelcomeTiles.TProjects.Refresh(const AProject: string);
begin
  if not FStopped and Assigned(FAccess.Refresh) then
  begin
    FAccess.Refresh(AProject);
  end;
end;

{ TAtlasIdeWelcomeTiles }

constructor TAtlasIdeWelcomeTiles.Create(const ARegistry: IAtlasModuleRegistry; ASections: TAtlasWelcomeSections);
var
  mRegistry: IAtlasModuleRegistry;
begin
  mRegistry := ARegistry;
  Create(ARegistry,
    function(const AIID: TGUID; const AObject: IInterface): IAtlasRegistration
    begin
      Result := mRegistry.Provide(AIID, AObject);
    end, ASections);
end;

constructor TAtlasIdeWelcomeTiles.Create(const ARegistry: IAtlasModuleRegistry; const AProvide: TAtlasWelcomeProvide;
  ASections: TAtlasWelcomeSections);
begin
  inherited Create;
  FRegistry := ARegistry;
  FProvide := AProvide;
  FSections := ASections;
  FTiles := TDictionary<string, IAtlasWelcomeTile>.Create;
  FFrames := TList<TAtlasWelcomeTileFrame>.Create;
end;

destructor TAtlasIdeWelcomeTiles.Destroy;
begin
  Stop;
  FFrames.Free;
  FTiles.Free;
  FProvide := nil;
  inherited Destroy;
end;

procedure TAtlasIdeWelcomeTiles.Start(const AProjects: TAtlasWelcomeProjectsAccess);
begin
  if FWatch <> nil then
  begin
    Exit;
  end;
  FWatch := TAtlasProvidedWatch.Create(FRegistry, IAtlasWelcomeTile);
  FWatch.OnChanged := Sync;
  Sync;
  ProvideServices(AProjects);
end;

procedure TAtlasIdeWelcomeTiles.Stop;
var
  mId: string;
  mFrame: TAtlasWelcomeTileFrame;
begin
  if FWatch = nil then
  begin
    Exit;
  end;
  RevokeServices;
  FreeAndNil(FWatch);
  for mId in FTiles.Keys.ToArray do
  begin
    Withdraw(mId);
  end;
  // Die Rahmen gehören der Seite und leben weiter; sie melden sich nicht mehr hier ab.
  for mFrame in FFrames do
  begin
    mFrame.FTiles := nil;
  end;
  FFrames.Clear;
end;

procedure TAtlasIdeWelcomeTiles.ProvideServices(const AProjects: TAtlasWelcomeProjectsAccess);
begin
  if (FRegistry = nil) or not Assigned(FProvide) then
  begin
    Exit;
  end;
  FBoard := TBoard.Create;
  FBoard.FOwner := Self;
  FBoardRef := FBoard;
  FProjects := TProjects.Create;
  FProjects.FAccess := AProjects;
  FProjectsRef := FProjects;
  FProvided := [FProvide(IAtlasWelcomeBoard, FBoardRef), FProvide(IAtlasWelcomeProjects, FProjectsRef)];
end;

procedure TAtlasIdeWelcomeTiles.RevokeServices;
var
  mIndex: Integer;
begin
  // Zuerst kappen: Wer Board oder Projekte noch hält, erreicht nichts mehr.
  if FBoard <> nil then
  begin
    FBoard.FOwner := nil;
  end;
  if FProjects <> nil then
  begin
    FProjects.FStopped := True;
    FProjects.FAccess := Default(TAtlasWelcomeProjectsAccess);
  end;
  for mIndex := High(FProvided) downto 0 do
  begin
    FProvided[mIndex].Revoke;
  end;
  FProvided := nil;
  FBoard := nil;
  FBoardRef := nil;
  FProjects := nil;
  FProjectsRef := nil;
end;

function TAtlasIdeWelcomeTiles.Current: TDictionary<string, IAtlasWelcomeTile>;
var
  mItem: IInterface;
  mTile: IAtlasWelcomeTile;
begin
  Result := TDictionary<string, IAtlasWelcomeTile>.Create;
  for mItem in FWatch.Items do
  begin
    if Supports(mItem, IAtlasWelcomeTile, mTile) then
    begin
      Result.AddOrSetValue(mTile.Info.Id, mTile);
    end;
  end;
end;

procedure TAtlasIdeWelcomeTiles.Sync;
var
  mNow: TDictionary<string, IAtlasWelcomeTile>;
  mId: string;
  mKnown: IAtlasWelcomeTile;
begin
  if FWatch = nil then
  begin
    Exit;
  end;
  mNow := Current;
  try
    for mId in FTiles.Keys.ToArray do
    begin
      if not mNow.TryGetValue(mId, mKnown) or (mKnown <> FTiles[mId]) then
      begin
        Withdraw(mId);
      end;
    end;
    for mId in mNow.Keys do
    begin
      if not FTiles.ContainsKey(mId) then
      begin
        Announce(mId, mNow[mId]);
      end;
    end;
  finally
    mNow.Free;
  end;
end;

procedure TAtlasIdeWelcomeTiles.Withdraw(const AId: string);
var
  mFrame: TAtlasWelcomeTileFrame;
begin
  // Zuerst die Steuerelemente: Nach dem Zurückziehen läuft kein Code des Moduls mehr (Regel 3).
  for mFrame in FramesOf(AId) do
  begin
    mFrame.Detach;
  end;
  TAtlasWelcomeViews.Unregister(AId);
  FTiles.Remove(AId);
  FSections.Remove(AId);
end;

procedure TAtlasIdeWelcomeTiles.Announce(const AId: string; const ATile: IAtlasWelcomeTile);
var
  mId: string;
begin
  mId := AId;
  FTiles.Add(mId, ATile);
  TAtlasWelcomeViews.Register(mId,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    begin
      Result := CreateFrame(mId, AOwner);
    end);
  FSections.Add(SectionOf(ATile));
end;

function TAtlasIdeWelcomeTiles.CreateFrame(const AId: string; AOwner: TComponent): TAtlasWelcomeSectionFrame;
var
  mTile: IAtlasWelcomeTile;
  mFrame: TAtlasWelcomeTileFrame;
begin
  Result := nil;
  if not FTiles.TryGetValue(AId, mTile) then
  begin
    Exit;
  end;
  mFrame := TAtlasWelcomeTileFrame.Create(AOwner);
  mFrame.SectionId := AId;
  mFrame.FTiles := Self;
  FFrames.Add(mFrame);
  mFrame.Attach(mTile.CreateView(mFrame, mFrame.FHostRef));
  Result := mFrame;
end;

procedure TAtlasIdeWelcomeTiles.FrameGone(AFrame: TAtlasWelcomeTileFrame);
begin
  FFrames.Remove(AFrame);
end;

function TAtlasIdeWelcomeTiles.FramesOf(const AId: string): TArray<TAtlasWelcomeTileFrame>;
var
  mFrame: TAtlasWelcomeTileFrame;
begin
  Result := nil;
  for mFrame in FFrames do
  begin
    if SameText(mFrame.SectionId, AId) then
    begin
      Result := Result + [mFrame];
    end;
  end;
end;

function TAtlasIdeWelcomeTiles.TileIds: TArray<string>;
begin
  Result := FTiles.Keys.ToArray;
  TArray.Sort<string>(Result);
end;

class function TAtlasIdeWelcomeTiles.SectionOf(const ATile: IAtlasWelcomeTile): TAtlasWelcomeSection;
var
  mInfo: TAtlasWelcomeTileInfo;
  mTile: IAtlasWelcomeTile;
  mColumn: TAtlasWelcomeColumn;
begin
  mInfo := ATile.Info;
  mTile := ATile;
  mColumn := TAtlasWelcomeColumn.Left;
  if mInfo.Column = TAtlasWelcomeTileColumn.Right then
  begin
    mColumn := TAtlasWelcomeColumn.Right;
  end;
  Result := TAtlasWelcomeSection.Create(mInfo.Id, mInfo.Title, mInfo.Order, mColumn,
    function: Boolean
    begin
      Result := mTile.Enabled;
    end);
  Result.Description := mInfo.Description;
end;

end.
