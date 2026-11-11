unit Atlas.IDE.Designer.MultiResize;

// Gemeinsame Größengriffe im Designer (#737, designer.multiResize) in der
// IDE: Bei mindestens zwei markierten Steuerelementen zeichnet ein
// durchsichtiges Fenster über dem Formular (TAtlasDesignerHandles) an jedem
// eigene Griffe in der Akzentfarbe: rechte und untere Kante (Mitte) und rechte
// untere Ecke, mit designer.multiResize.leftTopHandles auch linke und obere
// Kante. Steuerelemente mit AutoSize oder Align sind gestrichelt umrandet und
// bleiben unverändert.
// - Ziehen ändert alle markierten Steuerelemente (TAtlasMultiResize): um
//   denselben Betrag (designer.multiResize.mode = delta) oder auf dieselbe
//   Kante wie das gezogene (align). Mindestgröße Constraints.MinWidth/
//   MinHeight, sonst 8 px.
// - Ohne eigene Griffe links und oben wirkt Alt beim Drücken auf die
//   Gegenkante (rechts → links, unten → oben). Die gezogene Kante rastet am
//   Raster des Designers ein; mit Alt während des Ziehens ohne Raster.
// - Mit Umschalt rücken Nachbarn im selben Elternelement mit, ihr Abstand
//   bleibt.
// - Eine Beschriftung zeigt „180 → 260 px (3×)“.
// - Jeder Zug ist ein Schritt für „Größen rückgängig“ (TAtlasIdeHandleTool).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Atlas.Core.Designer.MultiResize,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.UI.Designer.Handles,
  Atlas.IDE.Designer.HandleTool;

type
  TAtlasIdeMultiResize = class(TAtlasIdeHandleTool)
  public const
    cId = 'multiResize';
  private
    FRoot: TWinControl;
    FControls: TArray<TControl>;
    FItems: TArray<TAtlasResizeItem>;
    FParents: TArray<TWinControl>;
    FNeighbours: TArray<TControl>;
    FNeighbourItems: TArray<TAtlasResizeNeighbour>;
    FDragged: Integer;
    FEdge: TAtlasResizeEdge;
    FLabel: string;
    FLabelAt: TPoint;
    FCount: Integer;
    function FindItems: Boolean;
    function GroupOf(AParent: TWinControl): Integer;
    procedure CollectNeighbours;
    function HandlesOf(const AOrigin: TPoint): TArray<TAtlasHandle>;
    function FramesOf(const AOrigin: TPoint): TArray<TAtlasHandleFrame>;
    procedure ShowItems;
    function SizeText(const AOld, ANew: TRect; ACount: Integer): string;
  protected
    procedure Down(AIndex: Integer; AShift: TShiftState); override;
    procedure Drag(const ADelta: TPoint; AShift: TShiftState); override;
    procedure Up; override;
    function ShowCaption: string; override;
    function UndoCaption: string; override;
    function UndoneText: string; override;
  public
    class function Available(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Knopf der Designer-Leiste: gedrückt, solange die Griffe gezeigt werden.</summary>
    function Button: TAtlasDesignerButton;
    procedure Tick; override;
  end;

implementation

uses
  System.Math,
  System.TypInfo,
  System.UITypes,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.UI.Designer.ToolStrings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.Settings;

const
  cHandleSize = 7;
  /// <summary>Rand um das Formular, damit Griffe an seiner Kante sichtbar bleiben.</summary>
  cMargin = 8;
  /// <summary>Tag eines Griffs: Steuerelement × cEdgeSlots + Kante.</summary>
  cEdgeSlots = 8;

{ TAtlasIdeMultiResize }

class function TAtlasIdeMultiResize.Available(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.DesignerMultiResize;
end;

function TAtlasIdeMultiResize.Button: TAtlasDesignerButton;
begin
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.MultiResize,
    TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.ResizeHint));
  Result.Pressed := Active;
  Result.Menu := True;
end;

function TAtlasIdeMultiResize.ShowCaption: string;
begin
  Result := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.ResizeShow);
end;

function TAtlasIdeMultiResize.UndoCaption: string;
begin
  Result := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.ResizeUndo);
end;

function TAtlasIdeMultiResize.UndoneText: string;
begin
  Result := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.ResizeUndone);
end;

function TAtlasIdeMultiResize.GroupOf(AParent: TWinControl): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FParents) do
  begin
    if FParents[mIndex] = AParent then
    begin
      Exit(mIndex);
    end;
  end;
  FParents := FParents + [AParent];
  Result := High(FParents);
end;

/// <summary>AutoSize (veröffentlicht) oder Align: Größe legt nicht der Designer fest.</summary>
function IsFixed(AControl: TControl): Boolean;
begin
  Result := AControl.Align <> alNone;
  if not Result and IsPublishedProp(AControl, 'AutoSize') then
  begin
    Result := GetOrdProp(AControl, 'AutoSize') <> 0;
  end;
end;

/// <summary>Markierte Steuerelemente des aktiven Formulars (Felder FRoot, FControls, FItems, FParents).</summary>
function TAtlasIdeMultiResize.FindItems: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mControl: TControl;
begin
  FRoot := nil;
  FControls := nil;
  FItems := nil;
  FParents := nil;
  if not Application.Active or not TAtlasDesignerAccess.Current(mEditor, mRoot) or not (mRoot is TWinControl) then
  begin
    Exit(False);
  end;
  FRoot := TWinControl(mRoot);
  for mComponent in TAtlasDesignerAccess.Selection(mEditor, mRoot) do
  begin
    if not (mComponent is TControl) or (TControl(mComponent).Parent = nil) then
    begin
      Continue;
    end;
    mControl := TControl(mComponent);
    FControls := FControls + [mControl];
    FItems := FItems + [TAtlasResizeItem.Create(mControl.BoundsRect, mControl.Constraints.MinWidth,
      mControl.Constraints.MinHeight, IsFixed(mControl), GroupOf(mControl.Parent))];
  end;
  Result := Length(FControls) >= 2;
end;

/// <summary>Nicht markierte Steuerelemente in den Elternelementen der Auswahl.</summary>
procedure TAtlasIdeMultiResize.CollectNeighbours;
var
  mGroup, mIndex: Integer;
  mControl: TControl;
  mSelected: Boolean;
  mItem: TControl;
begin
  FNeighbours := nil;
  FNeighbourItems := nil;
  for mGroup := 0 to High(FParents) do
  begin
    for mIndex := 0 to FParents[mGroup].ControlCount - 1 do
    begin
      mControl := FParents[mGroup].Controls[mIndex];
      mSelected := False;
      for mItem in FControls do
      begin
        mSelected := mSelected or (mItem = mControl);
      end;
      if not mSelected and (mControl.Align = alNone) then
      begin
        FNeighbours := FNeighbours + [mControl];
        FNeighbourItems := FNeighbourItems + [TAtlasResizeNeighbour.Create(mControl.BoundsRect, mGroup)];
      end;
    end;
  end;
end;

function TAtlasIdeMultiResize.HandlesOf(const AOrigin: TPoint): TArray<TAtlasHandle>;
var
  mIndex, mHalf: Integer;
  mRect: TRect;
  mEdge: TAtlasResizeEdge;
  mAt: TPoint;
  mCursor: TCursor;
begin
  Result := nil;
  mHalf := Overlay.S(cHandleSize) div 2;
  for mIndex := 0 to High(FControls) do
  begin
    if FItems[mIndex].Fixed then
    begin
      Continue;
    end;
    mRect := TAtlasDesignerAccess.BoundsInRoot(FControls[mIndex], FRoot);
    mRect.Offset(AOrigin.X, AOrigin.Y);
    for mEdge := Low(TAtlasResizeEdge) to High(TAtlasResizeEdge) do
    begin
      if (mEdge in [TAtlasResizeEdge.Left, TAtlasResizeEdge.Top]) and
        not TAtlasIdeSettings.Current.DesignerMultiResizeLeftTopHandles then
      begin
        Continue;
      end;
      case mEdge of
        TAtlasResizeEdge.Right:
          mAt := Point(mRect.Right, (mRect.Top + mRect.Bottom) div 2);
        TAtlasResizeEdge.Bottom:
          mAt := Point((mRect.Left + mRect.Right) div 2, mRect.Bottom);
        TAtlasResizeEdge.Left:
          mAt := Point(mRect.Left, (mRect.Top + mRect.Bottom) div 2);
        TAtlasResizeEdge.Top:
          mAt := Point((mRect.Left + mRect.Right) div 2, mRect.Top);
      else
        mAt := mRect.BottomRight;
      end;
      mCursor := crSizeNWSE;
      if TAtlasMultiResize.Horizontal(mEdge) and not TAtlasMultiResize.Vertical(mEdge) then
      begin
        mCursor := crSizeWE;
      end
      else if TAtlasMultiResize.Vertical(mEdge) and not TAtlasMultiResize.Horizontal(mEdge) then
      begin
        mCursor := crSizeNS;
      end;
      Result := Result + [TAtlasHandle.Create(Rect(mAt.X - mHalf, mAt.Y - mHalf, mAt.X + mHalf + 1, mAt.Y + mHalf + 1),
        TAtlasHandleKind.Square, '', mCursor, mIndex * cEdgeSlots + Ord(mEdge))];
    end;
  end;
end;

function TAtlasIdeMultiResize.FramesOf(const AOrigin: TPoint): TArray<TAtlasHandleFrame>;
var
  mIndex: Integer;
  mRect: TRect;
begin
  Result := nil;
  for mIndex := 0 to High(FControls) do
  begin
    if FItems[mIndex].Fixed then
    begin
      mRect := TAtlasDesignerAccess.BoundsInRoot(FControls[mIndex], FRoot);
      mRect.Offset(AOrigin.X, AOrigin.Y);
      Result := Result + [TAtlasHandleFrame.Create(mRect, TAtlasHandleFrameKind.Dashed)];
    end;
  end;
end;

procedure TAtlasIdeMultiResize.ShowItems;
var
  mOrigin, mLabelAt: TPoint;
  mVisible: TRect;
begin
  EnsureOverlay;
  if not TAtlasDesignerAccess.ClientArea(FRoot, Overlay.S(cMargin), mOrigin, mVisible) then
  begin
    Hide;
    Exit;
  end;
  mLabelAt := Point(FLabelAt.X + mOrigin.X, FLabelAt.Y + mOrigin.Y);
  Overlay.SetContent(HandlesOf(mOrigin), FramesOf(mOrigin), FLabel, mLabelAt);
  Overlay.ShowAt(mVisible);
end;

procedure TAtlasIdeMultiResize.Tick;
begin
  if Dragging then
  begin
    Exit;
  end;
  if not TAtlasIdeSettings.Current.DesignerMultiResize or not Active or not FindItems then
  begin
    Hide;
    Exit;
  end;
  FLabel := '';
  ShowItems;
end;

procedure TAtlasIdeMultiResize.Down(AIndex: Integer; AShift: TShiftState);
var
  mTag: Integer;
begin
  if not FindItems or (AIndex < 0) or (AIndex >= Length(Overlay.Handles)) then
  begin
    Overlay.CancelDrag;
    Exit;
  end;
  mTag := Overlay.Handles[AIndex].Tag;
  FDragged := mTag div cEdgeSlots;
  FEdge := TAtlasResizeEdge(mTag mod cEdgeSlots);
  if FDragged > High(FControls) then
  begin
    Overlay.CancelDrag;
    Exit;
  end;
  // Ohne eigene Griffe links und oben: Alt beim Drücken zieht die Gegenkante.
  if (ssAlt in AShift) and not TAtlasIdeSettings.Current.DesignerMultiResizeLeftTopHandles then
  begin
    FEdge := TAtlasMultiResize.Opposite(FEdge);
  end;
  CollectNeighbours;
  BeginStep;
end;

function TAtlasIdeMultiResize.SizeText(const AOld, ANew: TRect; ACount: Integer): string;
begin
  if FEdge = TAtlasResizeEdge.Corner then
  begin
    Result := TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.ResizeLabelBoth,
      [AOld.Width, AOld.Height, ANew.Width, ANew.Height, ACount]);
  end
  else if TAtlasMultiResize.Horizontal(FEdge) then
  begin
    Result := TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.ResizeLabel, [AOld.Width, ANew.Width, ACount]);
  end
  else
  begin
    Result := TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.ResizeLabel, [AOld.Height, ANew.Height, ACount]);
  end;
end;

procedure TAtlasIdeMultiResize.Drag(const ADelta: TPoint; AShift: TShiftState);
var
  mResult: TAtlasResizeResult;
  mGrid, mIndex: Integer;
  mAt: TRect;
begin
  if not InStep then
  begin
    Exit;
  end;
  mGrid := 0;
  if not (ssAlt in AShift) then
  begin
    mGrid := TAtlasDesignerAccess.GridSize(not TAtlasMultiResize.Horizontal(FEdge));
  end;
  mResult := TAtlasMultiResize.Apply(FItems, FNeighbourItems, FDragged, FEdge, ADelta,
    TAtlasMultiResize.ModeOf(TAtlasIdeSettings.Current.DesignerMultiResizeMode), mGrid, ssShift in AShift);
  for mIndex := 0 to High(FControls) do
  begin
    if FControls[mIndex].BoundsRect <> mResult.Items[mIndex] then
    begin
      FControls[mIndex].BoundsRect := mResult.Items[mIndex];
    end;
  end;
  for mIndex := 0 to High(FNeighbours) do
  begin
    if FNeighbours[mIndex].BoundsRect <> mResult.Neighbours[mIndex] then
    begin
      FNeighbours[mIndex].BoundsRect := mResult.Neighbours[mIndex];
    end;
  end;
  Changed := mResult.Changed > 0;
  FCount := mResult.Changed;
  FLabel := SizeText(FItems[FDragged].Bounds, mResult.Items[FDragged], mResult.Changed);
  mAt := TAtlasDesignerAccess.BoundsInRoot(FControls[FDragged], FRoot);
  FLabelAt := Point(mAt.Right + Overlay.S(cMargin), mAt.Bottom + Overlay.S(cMargin) div 2);
  ShowItems;
end;

procedure TAtlasIdeMultiResize.Up;
begin
  CommitStep(TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.ResizeDone, [FCount]));
  FLabel := '';
  Tick;
end;

end.
