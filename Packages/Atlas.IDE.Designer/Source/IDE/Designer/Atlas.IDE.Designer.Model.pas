unit Atlas.IDE.Designer.Model;

// Formular im Designer als Daten für die Rechnungen im Kern (#605 ff.):
// - TAtlasDesignScale rechnet zwischen den Bildschirmpixeln des Designers und
//   den Pixeln der DFM um (PixelsPerInch des Formulars zu seiner aktuellen
//   DPI); bei 100 % ist beides gleich.
// - TAtlasDesignerModel.LayoutNodes liest Lage, Align, Anchors, Margins,
//   Padding, Rand des Clients und Constraints aller Steuerelemente des
//   Formulars für TAtlasFormLayout (Probegröße #606), Eltern vor Kindern.
// Nur im Hauptthread.

interface

uses
  System.Types,
  Vcl.Controls,
  Atlas.Core.Designer.Layout;

type
  TAtlasDesignScale = record
    Design: Integer;
    Current: Integer;
    class function ForRoot(ARoot: TWinControl): TAtlasDesignScale; static;
    function ToDesign(AValue: Integer): Integer; overload;
    function ToDesign(const ARect: TRect): TRect; overload;
    function ToScreen(const APoint: TPoint): TPoint;
  end;

  TAtlasDesignerModel = class
  public
    /// <summary>Alle Steuerelemente unter ARoot (Eltern vor Kindern) in AControls, ihre Daten in Pixeln der DFM.
    /// Teile fremder Komponenten (Owner nicht ARoot, etwa in Frames) zählen mit, unsichtbare auch (Visible = False).
    /// </summary>
    class function LayoutNodes(ARoot: TWinControl; out AControls: TArray<TControl>): TArray<TAtlasLayoutNode>;
      static;
    /// <summary>Client des Formulars in Pixeln der DFM.</summary>
    class function ClientOf(ARoot: TWinControl): TSize; static;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Forms;

{ TAtlasDesignScale }

class function TAtlasDesignScale.ForRoot(ARoot: TWinControl): TAtlasDesignScale;
begin
  Result.Design := 96;
  Result.Current := 96;
  if ARoot is TCustomForm then
  begin
    Result.Design := TCustomForm(ARoot).PixelsPerInch;
    Result.Current := ARoot.CurrentPPI;
  end;
  if (Result.Design <= 0) or (Result.Current <= 0) then
  begin
    Result.Design := 96;
    Result.Current := 96;
  end;
end;

function TAtlasDesignScale.ToDesign(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Design, Current);
end;

function TAtlasDesignScale.ToDesign(const ARect: TRect): TRect;
begin
  Result := Rect(ToDesign(ARect.Left), ToDesign(ARect.Top), ToDesign(ARect.Right), ToDesign(ARect.Bottom));
end;

function TAtlasDesignScale.ToScreen(const APoint: TPoint): TPoint;
begin
  Result := Point(MulDiv(APoint.X, Current, Design), MulDiv(APoint.Y, Current, Design));
end;

function AlignOf(AControl: TControl): TAtlasLayoutAlign;
begin
  case AControl.Align of
    alTop: Result := TAtlasLayoutAlign.Top;
    alBottom: Result := TAtlasLayoutAlign.Bottom;
    alLeft: Result := TAtlasLayoutAlign.Left;
    alRight: Result := TAtlasLayoutAlign.Right;
    alClient: Result := TAtlasLayoutAlign.Client;
    alCustom: Result := TAtlasLayoutAlign.Custom;
  else
    Result := TAtlasLayoutAlign.None;
  end;
end;

function AnchorsOf(AControl: TControl): TAtlasLayoutAnchors;
begin
  Result := [];
  if akLeft in AControl.Anchors then
  begin
    Include(Result, TAtlasLayoutAnchor.Left);
  end;
  if akTop in AControl.Anchors then
  begin
    Include(Result, TAtlasLayoutAnchor.Top);
  end;
  if akRight in AControl.Anchors then
  begin
    Include(Result, TAtlasLayoutAnchor.Right);
  end;
  if akBottom in AControl.Anchors then
  begin
    Include(Result, TAtlasLayoutAnchor.Bottom);
  end;
end;

/// <summary>Rand zwischen Lage und Client eines Containers (Rahmen, Beschriftung) in Bildschirmpixeln.</summary>
function InsetOf(AControl: TWinControl): TRect;
var
  mBounds, mClient: TPoint;
begin
  Result := TRect.Empty;
  if not AControl.HandleAllocated or (AControl.Parent = nil) then
  begin
    Exit;
  end;
  mBounds := AControl.Parent.ClientToScreen(AControl.BoundsRect.TopLeft);
  mClient := AControl.ClientToScreen(Point(0, 0));
  Result.Left := mClient.X - mBounds.X;
  Result.Top := mClient.Y - mBounds.Y;
  Result.Right := AControl.Width - AControl.ClientWidth - Result.Left;
  Result.Bottom := AControl.Height - AControl.ClientHeight - Result.Top;
end;

function ScaledRect(const AScale: TAtlasDesignScale; ALeft, ATop, ARight, ABottom: Integer): TRect;
begin
  Result := Rect(AScale.ToDesign(ALeft), AScale.ToDesign(ATop), AScale.ToDesign(ARight), AScale.ToDesign(ABottom));
end;

function NodeOf(AControl: TControl; AParent: Integer; const AScale: TAtlasDesignScale): TAtlasLayoutNode;
var
  mName: string;
begin
  mName := AControl.Name;
  if mName = '' then
  begin
    mName := AControl.ClassName;
  end;
  Result := TAtlasLayoutNode.Create(mName, AControl.ClassName, AParent, AScale.ToDesign(AControl.BoundsRect));
  Result.Align := AlignOf(AControl);
  Result.Anchors := AnchorsOf(AControl);
  Result.AlignWithMargins := AControl.AlignWithMargins;
  Result.Margins := ScaledRect(AScale, AControl.Margins.Left, AControl.Margins.Top, AControl.Margins.Right,
    AControl.Margins.Bottom);
  Result.MinWidth := AScale.ToDesign(AControl.Constraints.MinWidth);
  Result.MinHeight := AScale.ToDesign(AControl.Constraints.MinHeight);
  Result.MaxWidth := AScale.ToDesign(AControl.Constraints.MaxWidth);
  Result.MaxHeight := AScale.ToDesign(AControl.Constraints.MaxHeight);
  Result.Visible := AControl.Visible;
  if AControl is TWinControl then
  begin
    Result.Padding := ScaledRect(AScale, TWinControl(AControl).Padding.Left, TWinControl(AControl).Padding.Top,
      TWinControl(AControl).Padding.Right, TWinControl(AControl).Padding.Bottom);
    Result.Inset := AScale.ToDesign(InsetOf(TWinControl(AControl)));
  end;
end;

{ TAtlasDesignerModel }

class function TAtlasDesignerModel.LayoutNodes(ARoot: TWinControl;
  out AControls: TArray<TControl>): TArray<TAtlasLayoutNode>;
var
  mScale: TAtlasDesignScale;
  mDone: Integer;
  mParent: TWinControl;
  mParentIndex, mIndex: Integer;
begin
  mScale := TAtlasDesignScale.ForRoot(ARoot);
  Result := nil;
  AControls := nil;
  // Breitensuche: Jeder Parent steht vor seinen Kindern.
  mDone := -1;
  while mDone < Length(AControls) do
  begin
    if mDone < 0 then
    begin
      mParent := ARoot;
    end
    else if AControls[mDone] is TWinControl then
    begin
      mParent := TWinControl(AControls[mDone]);
    end
    else
    begin
      Inc(mDone);
      Continue;
    end;
    mParentIndex := mDone;
    for mIndex := 0 to mParent.ControlCount - 1 do
    begin
      AControls := AControls + [mParent.Controls[mIndex]];
      Result := Result + [NodeOf(mParent.Controls[mIndex], mParentIndex, mScale)];
    end;
    Inc(mDone);
  end;
end;

class function TAtlasDesignerModel.ClientOf(ARoot: TWinControl): TSize;
var
  mScale: TAtlasDesignScale;
begin
  mScale := TAtlasDesignScale.ForRoot(ARoot);
  Result := TSize.Create(mScale.ToDesign(ARoot.ClientWidth), mScale.ToDesign(ARoot.ClientHeight));
end;

end.
