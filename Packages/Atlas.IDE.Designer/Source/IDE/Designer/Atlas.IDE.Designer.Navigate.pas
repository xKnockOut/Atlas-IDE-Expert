unit Atlas.IDE.Designer.Navigate;

// Räumliche Navigation im Designer (#745) in der IDE, solange der Designer den
// Fokus hat (TAtlasKeyHook, angemeldet nur, solange ein Designer gezeigt wird):
// - Alt+Pfeil wählt den Nachbarn in dieser Richtung, Alt+Umschalt+Pfeil fügt
//   ihn hinzu (vom zuletzt hinzugefügten aus).
// - Alt+Pos1 wählt das Elternelement (auf dem Formular das Formular),
//   Alt+Ende das Kind oben links eines Containers.
// - Alt+Bild auf/ab wechselt in den vorherigen bzw. nächsten Container
//   derselben Ebene.
// Die Lage kommt aus dem Designer (Steuerelemente im Client des Formulars,
// nichtvisuelle über DesignInfo), die Suche aus TAtlasNeighbours. Nach dem
// Sprung rollt der Designer das Ziel in den sichtbaren Bereich, ein kurzer
// Rahmen (TAtlasDesignerFlash) zeigt es. Ohne designer.spatialNavigation
// sind die Tasten frei. Nur im Hauptthread.

interface

uses
  System.Classes,
  Atlas.Core.Designer.Neighbours,
  Atlas.UI.Designer.Flash,
  Atlas.IDE.Foundation.KeyHook;

type
  TAtlasIdeDesignerNavigate = class;

  /// <summary>Tasten der räumlichen Navigation, solange der Designer den Fokus hat.</summary>
  TAtlasDesignerNavigateKeys = class(TAtlasKeyClient)
  private
    FOwner: TAtlasIdeDesignerNavigate;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  end;

  TAtlasIdeDesignerNavigate = class
  private
    FKeys: TAtlasDesignerNavigateKeys;
    FFlash: TAtlasDesignerFlash;
    /// <summary>Zuletzt mit Alt+Umschalt+Pfeil hinzugefügt: Ausgang des nächsten Schritts.</summary>
    FLast: string;
    function Target(const AItems: TArray<TAtlasNeighbourItem>; AFrom: Integer; AKey: Word): Integer;
    procedure Show(AComponent: TComponent; ARoot: TComponent);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Tasten an- oder abmelden (Designer gezeigt).</summary>
    procedure UpdateKeys(AWanted: Boolean);
    procedure ApplyTheme;
    /// <summary>Taste AKey mit Alt (und AShift) im aktiven Designer ausführen.</summary>
    procedure Navigate(AKey: Word; AShift: TShiftState);
    /// <summary>Komponenten des Formulars mit Lage im Client von ARoot.</summary>
    class function ItemsOf(ARoot: TComponent): TArray<TAtlasNeighbourItem>; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

const
  cKeyPriority = 50;
  /// <summary>Größe des Symbols einer nichtvisuellen Komponente im Designer.</summary>
  cIconSize = 28;

function IsArrow(AKey: Word): Boolean;
begin
  Result := (AKey = VK_LEFT) or (AKey = VK_RIGHT) or (AKey = VK_UP) or (AKey = VK_DOWN);
end;

function IsJump(AKey: Word): Boolean;
begin
  Result := (AKey = VK_HOME) or (AKey = VK_END) or (AKey = VK_PRIOR) or (AKey = VK_NEXT);
end;

function DirectionOf(AKey: Word): TAtlasNeighbourDirection;
begin
  case AKey of
    VK_LEFT:
      Result := TAtlasNeighbourDirection.Left;
    VK_RIGHT:
      Result := TAtlasNeighbourDirection.Right;
    VK_UP:
      Result := TAtlasNeighbourDirection.Up;
  else
    Result := TAtlasNeighbourDirection.Down;
  end;
end;

{ TAtlasDesignerNavigateKeys }

function TAtlasDesignerNavigateKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := TAtlasIdeSettings.Current.DesignerSpatialNavigation and
    (((AShift = [ssAlt]) and (IsArrow(AKey) or IsJump(AKey))) or ((AShift = [ssAlt, ssShift]) and IsArrow(AKey))) and
    TAtlasDesignerAccess.Focused;
end;

procedure TAtlasDesignerNavigateKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  mOwner: TAtlasIdeDesignerNavigate;
  mKey: Word;
  mShift: TShiftState;
begin
  mOwner := FOwner;
  mKey := AKey;
  mShift := AShift;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      mOwner.Navigate(mKey, mShift);
    end);
end;

{ TAtlasIdeDesignerNavigate }

constructor TAtlasIdeDesignerNavigate.Create;
begin
  inherited Create;
  FKeys := TAtlasDesignerNavigateKeys.Create(cKeyPriority);
  FKeys.FOwner := Self;
end;

destructor TAtlasIdeDesignerNavigate.Destroy;
begin
  TAtlasKeyHook.Remove(FKeys);
  FKeys.Free;
  FFlash.Free;
  inherited Destroy;
end;

procedure TAtlasIdeDesignerNavigate.UpdateKeys(AWanted: Boolean);
begin
  if AWanted and TAtlasIdeSettings.Current.DesignerSpatialNavigation then
  begin
    TAtlasKeyHook.Add(FKeys);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
end;

procedure TAtlasIdeDesignerNavigate.ApplyTheme;
begin
  if FFlash <> nil then
  begin
    FFlash.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

class function TAtlasIdeDesignerNavigate.ItemsOf(ARoot: TComponent): TArray<TAtlasNeighbourItem>;
var
  mIndex: Integer;
  mComponent: TComponent;
  mControl: TControl;
  mBounds: TRect;
  mInfo: LongRec;
begin
  Result := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    mComponent := ARoot.Components[mIndex];
    if mComponent.Name = '' then
    begin
      Continue;
    end;
    if not (mComponent is TControl) then
    begin
      mInfo := LongRec(mComponent.DesignInfo);
      Result := Result + [TAtlasNeighbourItem.Create(mComponent.Name, '', Rect(SmallInt(mInfo.Lo),
        SmallInt(mInfo.Hi), SmallInt(mInfo.Lo) + cIconSize, SmallInt(mInfo.Hi) + cIconSize), False, False)];
      Continue;
    end;
    mControl := TControl(mComponent);
    if not (ARoot is TWinControl) then
    begin
      Continue;
    end;
    mBounds := TAtlasDesignerAccess.BoundsInRoot(mControl, TWinControl(ARoot));
    if not mBounds.IsEmpty then
    begin
      Result := Result + [TAtlasNeighbourItem.Create(mControl.Name, TAtlasDesignerAccess.ParentNameOf(mControl, ARoot),
        mBounds, True, (mControl is TWinControl) and (csAcceptsControls in mControl.ControlStyle))];
    end;
  end;
end;

function TAtlasIdeDesignerNavigate.Target(const AItems: TArray<TAtlasNeighbourItem>; AFrom: Integer;
  AKey: Word): Integer;
begin
  case AKey of
    VK_HOME:
      Result := TAtlasNeighbours.ParentOf(AItems, AFrom);
    VK_END:
      Result := TAtlasNeighbours.FirstChild(AItems, AFrom);
    VK_PRIOR, VK_NEXT:
      Result := TAtlasNeighbours.NextContainer(AItems, AFrom, AKey = VK_NEXT);
  else
    Result := TAtlasNeighbours.Find(AItems, AFrom, DirectionOf(AKey),
      TAtlasIdeSettings.Current.DesignerSpatialCrossContainers);
  end;
end;

function Contains(const AList: TArray<TComponent>; AComponent: TComponent): Boolean;
var
  mItem: TComponent;
begin
  for mItem in AList do
  begin
    if mItem = AComponent then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Bezug: beim Hinzufügen das zuletzt hinzugefügte, sonst die erste gewählte Komponente.</summary>
function FromOf(const AItems: TArray<TAtlasNeighbourItem>; const ASelected: TArray<TComponent>;
  const ALast: string; AExtend: Boolean): Integer;
var
  mComponent: TComponent;
begin
  if AExtend and (ALast <> '') then
  begin
    for mComponent in ASelected do
    begin
      if SameText(mComponent.Name, ALast) then
      begin
        Exit(TAtlasNeighbours.IndexOf(AItems, ALast));
      end;
    end;
  end;
  Result := TAtlasNeighbours.IndexOf(AItems, ASelected[0].Name);
end;

procedure TAtlasIdeDesignerNavigate.Navigate(AKey: Word; AShift: TShiftState);
var
  mEditor: IOTAFormEditor;
  mRoot, mTarget: TComponent;
  mDesigner: IDesigner;
  mItems: TArray<TAtlasNeighbourItem>;
  mSelected: TArray<TComponent>;
  mExtend: Boolean;
  mIndex: Integer;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  mSelected := TAtlasDesignerAccess.Selection(mEditor, mRoot);
  mItems := ItemsOf(mRoot);
  mExtend := ssShift in AShift;
  if (mDesigner = nil) or (Length(mSelected) = 0) then
  begin
    Exit;
  end;
  mIndex := Target(mItems, FromOf(mItems, mSelected, FLast, mExtend), AKey);
  if (mIndex < 0) and (AKey = VK_HOME) then
  begin
    // Auf dem Formular: das Formular selbst.
    TAtlasDesignerAccess.Select(mDesigner, mRoot, nil);
    Exit;
  end;
  mTarget := nil;
  if mIndex >= 0 then
  begin
    mTarget := mRoot.FindComponent(mItems[mIndex].Name);
  end;
  if mTarget = nil then
  begin
    Exit;
  end;
  if not mExtend then
  begin
    mSelected := nil;
  end;
  if not Contains(mSelected, mTarget) then
  begin
    mSelected := mSelected + [mTarget];
  end;
  TAtlasDesignerAccess.Select(mDesigner, mRoot, mSelected);
  FLast := mTarget.Name;
  Show(mTarget, mRoot);
end;

/// <summary>Ziel in den sichtbaren Bereich rollen und kurz umrahmen.</summary>
procedure TAtlasIdeDesignerNavigate.Show(AComponent: TComponent; ARoot: TComponent);
var
  mControl: TControl;
  mScroller: TWinControl;
begin
  if not (AComponent is TControl) or not (ARoot is TWinControl) then
  begin
    Exit;
  end;
  mControl := TControl(AComponent);
  // Rollen übernimmt die Fläche des Designers um das Formular, nie das Formular selbst (das änderte die .dfm).
  mScroller := TWinControl(ARoot).Parent;
  while (mScroller <> nil) and not (mScroller is TScrollingWinControl) do
  begin
    mScroller := mScroller.Parent;
  end;
  if mScroller <> nil then
  begin
    TScrollingWinControl(mScroller).ScrollInView(mControl);
  end;
  if FFlash = nil then
  begin
    FFlash := TAtlasDesignerFlash.CreateFlash(nil, Application.MainFormHandle, TAtlasIdeStyle.Colors);
  end;
  FFlash.FlashAt(Rect(mControl.ClientToScreen(Point(0, 0)), mControl.ClientToScreen(Point(mControl.Width,
    mControl.Height))));
end;

end.
