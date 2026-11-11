unit Atlas.Core.Designer.Layout;

// Layout eines Formulars bei einer anderen Größe (#606, Probegröße), ohne VCL
// und Windows: rechnet nach den Regeln der VCL, wo die Steuerelemente landen,
// wenn der Client des Formulars eine andere Größe bekommt. Die echten
// Komponenten im Designer werden nicht angefasst.
// - Knoten in Elternreihenfolge (Eltern vor Kindern), Lagen im Client des
//   Parents, Werte in Pixeln der DFM.
// - Align: erst alTop (nach Top), dann alBottom (von unten nach oben), alLeft
//   (nach Left), alRight (von rechts), zuletzt alClient im Rest; mit
//   AlignWithMargins zählen die Margins mit, der Rest ist Client minus
//   Padding.
// - Anchors ohne Align: akLeft+akRight dehnt, nur akRight verschiebt, keiner
//   von beiden verschiebt um die halbe Änderung (Mitte bleibt); senkrecht
//   ebenso. Bezug ist die Änderung des Clients des Parents.
// - Constraints (Min/Max) begrenzen Breite und Höhe, auch des Formulars.
// - Befunde: zu klein (Breite oder Höhe ≤ 0), ragt aus dem Client des Parents
//   (mit Betrag), überlappt ein Geschwister, das vorher frei war, zwei alClient
//   im selben Parent, Anchors auf allen Seiten bei Align.

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  TAtlasLayoutAlign = (None, Top, Bottom, Left, Right, Client, Custom);
  TAtlasLayoutAnchor = (Left, Top, Right, Bottom);
  // Clipped, ScreenWidth und ScreenHeight setzt erst die Vorschau in anderen Skalierungen (#607).
  TAtlasLayoutProblem = (TooSmall, OutRight, OutBottom, OutLeft, OutTop, Overlap, TwoClient, AnchorsWithAlign, Clipped,
    ScreenWidth, ScreenHeight);
{$SCOPEDENUMS OFF}
  TAtlasLayoutAnchors = set of TAtlasLayoutAnchor;

  TAtlasLayoutNode = record
    Name: string;
    ClassName: string;
    /// <summary>Index des Parents in der Liste; -1 = direkt auf dem Formular.</summary>
    Parent: Integer;
    /// <summary>Lage im Client des Parents.</summary>
    Bounds: TRect;
    Align: TAtlasLayoutAlign;
    Anchors: TAtlasLayoutAnchors;
    AlignWithMargins: Boolean;
    /// <summary>Margins als Left, Top, Right, Bottom.</summary>
    Margins: TRect;
    /// <summary>Padding als Left, Top, Right, Bottom (nur Container).</summary>
    Padding: TRect;
    /// <summary>Rand zwischen Lage und Client (Rahmen, Beschriftung einer GroupBox) als Left, Top, Right, Bottom.
    /// </summary>
    Inset: TRect;
    MinWidth: Integer;
    MinHeight: Integer;
    /// <summary>0 = ohne Grenze.</summary>
    MaxWidth: Integer;
    MaxHeight: Integer;
    Visible: Boolean;
    class function Create(const AName, AClassName: string; AParent: Integer; const ABounds: TRect): TAtlasLayoutNode;
      static;
  end;

  TAtlasLayoutFinding = record
    /// <summary>Index des Knotens; -1 = das Formular selbst (Bildschirmgröße).</summary>
    Node: Integer;
    Problem: TAtlasLayoutProblem;
    /// <summary>Pixel, um die es herausragt.</summary>
    Amount: Integer;
    /// <summary>Überlappt: Name des Geschwisters; zwei alClient: Name des anderen.</summary>
    Other: string;
  end;

  TAtlasFormLayout = class
  public
    /// <summary>Neue Lagen aller Knoten, wenn der Client des Formulars von AOldClient auf ANewClient wechselt.
    /// </summary>
    class function Arrange(const ANodes: TArray<TAtlasLayoutNode>; const AOldClient, ANewClient: TSize): TArray<TRect>;
      static;
    /// <summary>Befunde in den neuen Lagen ANew (aus Arrange); Bezug für Überlappung sind die Lagen der Knoten.</summary>
    class function Problems(const ANodes: TArray<TAtlasLayoutNode>; const ANew: TArray<TRect>;
      const ANewClient: TSize): TArray<TAtlasLayoutFinding>; static;
    /// <summary>Client des Formulars nach den Constraints des Formulars (AMin*, AMax*; 0 = ohne Grenze), bezogen auf
    /// den Client: Rahmen und Titel zählt der Aufrufer heraus.</summary>
    class function Constrain(const AClient: TSize; AMinWidth, AMinHeight, AMaxWidth, AMaxHeight: Integer): TSize;
      static;
    /// <summary>Lage von Knoten AIndex im Client des Formulars (Lagen der Parents aufaddiert).</summary>
    class function InForm(const ANodes: TArray<TAtlasLayoutNode>; const ABounds: TArray<TRect>;
      AIndex: Integer): TRect; static;
    /// <summary>Größen aus „1366x768, 1920x1080“ (auch mit ×); Unbrauchbares entfällt.</summary>
    class function ParseSizes(const AText: string): TArray<TSize>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TAtlasLayoutNode }

class function TAtlasLayoutNode.Create(const AName, AClassName: string; AParent: Integer;
  const ABounds: TRect): TAtlasLayoutNode;
begin
  Result := Default(TAtlasLayoutNode);
  Result.Name := AName;
  Result.ClassName := AClassName;
  Result.Parent := AParent;
  Result.Bounds := ABounds;
  Result.Anchors := [TAtlasLayoutAnchor.Left, TAtlasLayoutAnchor.Top];
  Result.Visible := True;
end;

function Limit(AValue, AMin, AMax: Integer): Integer;
begin
  Result := AValue;
  if (AMax > 0) and (Result > AMax) then
  begin
    Result := AMax;
  end;
  if Result < AMin then
  begin
    Result := AMin;
  end;
end;

/// <summary>Client eines Knotens (oder des Formulars bei -1) in eigenen Koordinaten ohne Padding.</summary>
function InnerOf(const ANodes: TArray<TAtlasLayoutNode>; const ABounds: TArray<TRect>; AParent: Integer;
  const AFormClient: TSize): TRect;
var
  mNode: TAtlasLayoutNode;
begin
  if AParent < 0 then
  begin
    Exit(Rect(0, 0, AFormClient.cx, AFormClient.cy));
  end;
  mNode := ANodes[AParent];
  Result := Rect(mNode.Padding.Left, mNode.Padding.Top,
    ABounds[AParent].Width - mNode.Inset.Left - mNode.Inset.Right - mNode.Padding.Right,
    ABounds[AParent].Height - mNode.Inset.Top - mNode.Inset.Bottom - mNode.Padding.Bottom);
end;

/// <summary>Breite und Höhe des Clients eines Knotens bzw. des Formulars (bei -1).</summary>
function ClientSize(const ANodes: TArray<TAtlasLayoutNode>; const ABounds: TArray<TRect>; AParent: Integer;
  const AFormClient: TSize): TSize;
begin
  if AParent < 0 then
  begin
    Exit(AFormClient);
  end;
  Result := TSize.Create(ABounds[AParent].Width - ANodes[AParent].Inset.Left - ANodes[AParent].Inset.Right,
    ABounds[AParent].Height - ANodes[AParent].Inset.Top - ANodes[AParent].Inset.Bottom);
end;

function ExtractBounds(const ANodes: TArray<TAtlasLayoutNode>): TArray<TRect>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ANodes));
  for mIndex := 0 to High(ANodes) do
  begin
    Result[mIndex] := ANodes[mIndex].Bounds;
  end;
end;

/// <summary>Neue Lage eines Knotens ohne Align nach seinen Anchors, ADX/ADY: Änderung des Clients des Parents.
/// </summary>
function Anchored(const ANode: TAtlasLayoutNode; ADX, ADY: Integer): TRect;
var
  mLeft, mTop, mWidth, mHeight: Integer;
begin
  mLeft := ANode.Bounds.Left;
  mTop := ANode.Bounds.Top;
  mWidth := ANode.Bounds.Width;
  mHeight := ANode.Bounds.Height;
  if TAtlasLayoutAnchor.Right in ANode.Anchors then
  begin
    if TAtlasLayoutAnchor.Left in ANode.Anchors then
    begin
      Inc(mWidth, ADX);
    end
    else
    begin
      Inc(mLeft, ADX);
    end;
  end
  else if not (TAtlasLayoutAnchor.Left in ANode.Anchors) then
  begin
    Inc(mLeft, ADX div 2);
  end;
  if TAtlasLayoutAnchor.Bottom in ANode.Anchors then
  begin
    if TAtlasLayoutAnchor.Top in ANode.Anchors then
    begin
      Inc(mHeight, ADY);
    end
    else
    begin
      Inc(mTop, ADY);
    end;
  end
  else if not (TAtlasLayoutAnchor.Top in ANode.Anchors) then
  begin
    Inc(mTop, ADY div 2);
  end;
  mWidth := Limit(mWidth, ANode.MinWidth, ANode.MaxWidth);
  mHeight := Limit(mHeight, ANode.MinHeight, ANode.MaxHeight);
  Result := Bounds(mLeft, mTop, mWidth, mHeight);
end;

/// <summary>Margins des Knotens, wenn AlignWithMargins gilt, sonst 0.</summary>
function MarginsOf(const ANode: TAtlasLayoutNode): TRect;
begin
  Result := TRect.Empty;
  if ANode.AlignWithMargins then
  begin
    Result := ANode.Margins;
  end;
end;

/// <summary>Kinder von AParent mit Align AAlign, sortiert wie die VCL sie anordnet.</summary>
function AlignedChildren(const ANodes: TArray<TAtlasLayoutNode>; AParent: Integer;
  AAlign: TAtlasLayoutAlign): TArray<Integer>;
var
  mIndex, mOuter, mInner, mSwap: Integer;
  mBefore: Boolean;
begin
  Result := nil;
  for mIndex := 0 to High(ANodes) do
  begin
    if (ANodes[mIndex].Parent = AParent) and ANodes[mIndex].Visible and (ANodes[mIndex].Align = AAlign) then
    begin
      Result := Result + [mIndex];
    end;
  end;
  // Einfügesortierung, stabil: Top/Left aufsteigend, Bottom/Right von außen nach innen.
  for mOuter := 1 to High(Result) do
  begin
    mInner := mOuter;
    while mInner > 0 do
    begin
      case AAlign of
        TAtlasLayoutAlign.Top:
          mBefore := ANodes[Result[mInner]].Bounds.Top < ANodes[Result[mInner - 1]].Bounds.Top;
        TAtlasLayoutAlign.Bottom:
          mBefore := ANodes[Result[mInner]].Bounds.Bottom > ANodes[Result[mInner - 1]].Bounds.Bottom;
        TAtlasLayoutAlign.Left:
          mBefore := ANodes[Result[mInner]].Bounds.Left < ANodes[Result[mInner - 1]].Bounds.Left;
        TAtlasLayoutAlign.Right:
          mBefore := ANodes[Result[mInner]].Bounds.Right > ANodes[Result[mInner - 1]].Bounds.Right;
      else
        mBefore := False;
      end;
      if not mBefore then
      begin
        Break;
      end;
      mSwap := Result[mInner];
      Result[mInner] := Result[mInner - 1];
      Result[mInner - 1] := mSwap;
      Dec(mInner);
    end;
  end;
end;

/// <summary>Legt ein ausgerichtetes Kind in den Rest ARest und verkleinert den Rest.</summary>
function PlaceAligned(const ANode: TAtlasLayoutNode; var ARest: TRect): TRect;
var
  mMargin: TRect;
  mWidth, mHeight: Integer;
begin
  mMargin := MarginsOf(ANode);
  mWidth := Limit(ANode.Bounds.Width, ANode.MinWidth, ANode.MaxWidth);
  mHeight := Limit(ANode.Bounds.Height, ANode.MinHeight, ANode.MaxHeight);
  case ANode.Align of
    TAtlasLayoutAlign.Top:
      begin
        Result := Rect(ARest.Left + mMargin.Left, ARest.Top + mMargin.Top, ARest.Right - mMargin.Right,
          ARest.Top + mMargin.Top + mHeight);
        ARest.Top := Result.Bottom + mMargin.Bottom;
      end;
    TAtlasLayoutAlign.Bottom:
      begin
        Result := Rect(ARest.Left + mMargin.Left, ARest.Bottom - mMargin.Bottom - mHeight,
          ARest.Right - mMargin.Right, ARest.Bottom - mMargin.Bottom);
        ARest.Bottom := Result.Top - mMargin.Top;
      end;
    TAtlasLayoutAlign.Left:
      begin
        Result := Rect(ARest.Left + mMargin.Left, ARest.Top + mMargin.Top, ARest.Left + mMargin.Left + mWidth,
          ARest.Bottom - mMargin.Bottom);
        ARest.Left := Result.Right + mMargin.Right;
      end;
    TAtlasLayoutAlign.Right:
      begin
        Result := Rect(ARest.Right - mMargin.Right - mWidth, ARest.Top + mMargin.Top, ARest.Right - mMargin.Right,
          ARest.Bottom - mMargin.Bottom);
        ARest.Right := Result.Left - mMargin.Left;
      end;
  else
    Result := Rect(ARest.Left + mMargin.Left, ARest.Top + mMargin.Top, ARest.Right - mMargin.Right,
      ARest.Bottom - mMargin.Bottom);
  end;
end;

/// <summary>Kinder von AParent in ANew einordnen; der Parent selbst hat seine neue Lage schon.</summary>
procedure ArrangeChildren(const ANodes: TArray<TAtlasLayoutNode>; const AOld: TArray<TRect>; AParent: Integer;
  const AOldClient, ANewClient: TSize; var ANew: TArray<TRect>);
const
  cOrder: array[0..4] of TAtlasLayoutAlign = (TAtlasLayoutAlign.Top, TAtlasLayoutAlign.Bottom,
    TAtlasLayoutAlign.Left, TAtlasLayoutAlign.Right, TAtlasLayoutAlign.Client);
var
  mOld, mNow: TSize;
  mRest: TRect;
  mAlign: TAtlasLayoutAlign;
  mIndex: Integer;
begin
  mOld := ClientSize(ANodes, AOld, AParent, AOldClient);
  mNow := ClientSize(ANodes, ANew, AParent, ANewClient);
  for mIndex := 0 to High(ANodes) do
  begin
    if (ANodes[mIndex].Parent = AParent) and (ANodes[mIndex].Align in [TAtlasLayoutAlign.None,
      TAtlasLayoutAlign.Custom]) then
    begin
      ANew[mIndex] := Anchored(ANodes[mIndex], mNow.cx - mOld.cx, mNow.cy - mOld.cy);
    end;
  end;
  mRest := InnerOf(ANodes, ANew, AParent, ANewClient);
  for mAlign in cOrder do
  begin
    for mIndex in AlignedChildren(ANodes, AParent, mAlign) do
    begin
      ANew[mIndex] := PlaceAligned(ANodes[mIndex], mRest);
    end;
  end;
end;

function Finding(ANode: Integer; AProblem: TAtlasLayoutProblem; AAmount: Integer;
  const AOther: string): TAtlasLayoutFinding;
begin
  Result.Node := ANode;
  Result.Problem := AProblem;
  Result.Amount := AAmount;
  Result.Other := AOther;
end;

/// <summary>Zu klein oder aus dem Client des Parents (ohne Padding: Padding ist Abstand, kein Rand).</summary>
function SizeProblems(const ANodes: TArray<TAtlasLayoutNode>; const ANew: TArray<TRect>;
  const ANewClient: TSize): TArray<TAtlasLayoutFinding>;
var
  mIndex: Integer;
  mClient: TSize;
  mRect: TRect;
begin
  Result := nil;
  for mIndex := 0 to High(ANodes) do
  begin
    if not ANodes[mIndex].Visible then
    begin
      Continue;
    end;
    mRect := ANew[mIndex];
    if (mRect.Width <= 0) or (mRect.Height <= 0) then
    begin
      Result := Result + [Finding(mIndex, TAtlasLayoutProblem.TooSmall, Min(mRect.Width, mRect.Height), '')];
      Continue;
    end;
    mClient := ClientSize(ANodes, ANew, ANodes[mIndex].Parent, ANewClient);
    if mRect.Right > mClient.cx then
    begin
      Result := Result + [Finding(mIndex, TAtlasLayoutProblem.OutRight, mRect.Right - mClient.cx, '')];
    end;
    if mRect.Bottom > mClient.cy then
    begin
      Result := Result + [Finding(mIndex, TAtlasLayoutProblem.OutBottom, mRect.Bottom - mClient.cy, '')];
    end;
    if mRect.Left < 0 then
    begin
      Result := Result + [Finding(mIndex, TAtlasLayoutProblem.OutLeft, -mRect.Left, '')];
    end;
    if mRect.Top < 0 then
    begin
      Result := Result + [Finding(mIndex, TAtlasLayoutProblem.OutTop, -mRect.Top, '')];
    end;
  end;
end;

/// <summary>Geschwister, die sich in den neuen Lagen überlappen, in der Designgröße aber nicht.</summary>
function OverlapProblems(const ANodes: TArray<TAtlasLayoutNode>;
  const ANew: TArray<TRect>): TArray<TAtlasLayoutFinding>;
var
  mFirst, mSecond: Integer;
begin
  Result := nil;
  for mFirst := 0 to High(ANodes) do
  begin
    for mSecond := mFirst + 1 to High(ANodes) do
    begin
      if (ANodes[mFirst].Parent <> ANodes[mSecond].Parent) or not ANodes[mFirst].Visible or
        not ANodes[mSecond].Visible then
      begin
        Continue;
      end;
      if ANew[mFirst].IntersectsWith(ANew[mSecond]) and
        not ANodes[mFirst].Bounds.IntersectsWith(ANodes[mSecond].Bounds) then
      begin
        Result := Result + [Finding(mSecond, TAtlasLayoutProblem.Overlap, 0, ANodes[mFirst].Name)];
      end;
    end;
  end;
end;

/// <summary>Zwei alClient im selben Parent, Anchors auf allen Seiten bei Align.</summary>
function ConflictProblems(const ANodes: TArray<TAtlasLayoutNode>): TArray<TAtlasLayoutFinding>;
var
  mIndex, mOther: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ANodes) do
  begin
    if (ANodes[mIndex].Align <> TAtlasLayoutAlign.None) and (ANodes[mIndex].Align <> TAtlasLayoutAlign.Client) and
      (ANodes[mIndex].Anchors = [TAtlasLayoutAnchor.Left, TAtlasLayoutAnchor.Top, TAtlasLayoutAnchor.Right,
      TAtlasLayoutAnchor.Bottom]) then
    begin
      Result := Result + [Finding(mIndex, TAtlasLayoutProblem.AnchorsWithAlign, 0, '')];
    end;
    if ANodes[mIndex].Align <> TAtlasLayoutAlign.Client then
    begin
      Continue;
    end;
    for mOther := 0 to mIndex - 1 do
    begin
      if (ANodes[mOther].Parent = ANodes[mIndex].Parent) and (ANodes[mOther].Align = TAtlasLayoutAlign.Client) then
      begin
        Result := Result + [Finding(mIndex, TAtlasLayoutProblem.TwoClient, 0, ANodes[mOther].Name)];
        Break;
      end;
    end;
  end;
end;

{ TAtlasFormLayout }

class function TAtlasFormLayout.Arrange(const ANodes: TArray<TAtlasLayoutNode>; const AOldClient,
  ANewClient: TSize): TArray<TRect>;
var
  mIndex: Integer;
  mOld: TArray<TRect>;
begin
  mOld := ExtractBounds(ANodes);
  Result := Copy(mOld);
  ArrangeChildren(ANodes, mOld, -1, AOldClient, ANewClient, Result);
  // Eltern stehen vor ihren Kindern: Jeder Container hat seine neue Lage, bevor seine Kinder dran sind.
  for mIndex := 0 to High(ANodes) do
  begin
    ArrangeChildren(ANodes, mOld, mIndex, AOldClient, ANewClient, Result);
  end;
end;

class function TAtlasFormLayout.Problems(const ANodes: TArray<TAtlasLayoutNode>; const ANew: TArray<TRect>;
  const ANewClient: TSize): TArray<TAtlasLayoutFinding>;
begin
  Result := SizeProblems(ANodes, ANew, ANewClient) + OverlapProblems(ANodes, ANew) + ConflictProblems(ANodes);
end;

class function TAtlasFormLayout.Constrain(const AClient: TSize; AMinWidth, AMinHeight, AMaxWidth,
  AMaxHeight: Integer): TSize;
begin
  Result := TSize.Create(Limit(AClient.cx, AMinWidth, AMaxWidth), Limit(AClient.cy, AMinHeight, AMaxHeight));
end;

class function TAtlasFormLayout.InForm(const ANodes: TArray<TAtlasLayoutNode>; const ABounds: TArray<TRect>;
  AIndex: Integer): TRect;
var
  mParent: Integer;
begin
  Result := ABounds[AIndex];
  mParent := ANodes[AIndex].Parent;
  while mParent >= 0 do
  begin
    Result.Offset(ABounds[mParent].Left + ANodes[mParent].Inset.Left,
      ABounds[mParent].Top + ANodes[mParent].Inset.Top);
    mParent := ANodes[mParent].Parent;
  end;
end;

class function TAtlasFormLayout.ParseSizes(const AText: string): TArray<TSize>;
var
  mPart: string;
  mPair: TArray<string>;
  mWidth, mHeight: Integer;
begin
  Result := nil;
  for mPart in AText.Split([',', ';']) do
  begin
    mPair := mPart.Replace('×', 'x').ToLower.Split(['x']);
    if (Length(mPair) = 2) and TryStrToInt(Trim(mPair[0]), mWidth) and TryStrToInt(Trim(mPair[1]), mHeight) and
      (mWidth > 0) and (mHeight > 0) then
    begin
      Result := Result + [TSize.Create(mWidth, mHeight)];
    end;
  end;
end;

end.
