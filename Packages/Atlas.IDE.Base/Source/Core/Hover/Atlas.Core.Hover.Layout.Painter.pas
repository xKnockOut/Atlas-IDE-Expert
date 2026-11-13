unit Atlas.Core.Hover.Layout.Painter;

// Grundlage des Hover-Satzes ohne VCL: Zeichenbausteine und Klickflächen sammeln, Schriften und Maße über den
// Mess-Rückruf, Linien, Balken, umbrochener Block und Fließtext mit Verweisen und Hervorhebung unter der Maus.
// Die Abschnitte setzt Atlas.Core.Hover.Layout, die published-Mitglieder Atlas.Core.Hover.Layout.Members.

interface

uses
  System.Types,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.Layout.Contract;

type
  /// <summary>Klickfläche und Hervorhebung eines Stücks Fließtext: Index >= 0 legt eine Klickfläche an,
  /// HotIndex >= 0 färbt das Stück unter der Maus in HotColor und unterstreicht es.</summary>
  TAtlasHoverHotSpot = record
    Kind: TAtlasHoverHitKind;
    Index: Integer;
    HotIndex: Integer;
    HotColor: TAtlasColor;
  end;

  /// <summary>Zeichenelemente und Klickflächen sammeln: Grundformen, Fließtext und Kästchen.</summary>
  TAtlasHoverPainter = class
  protected
    FInput: TAtlasHoverInput;
    FMeasure: IAtlasHoverMeasure;
    FData: TAtlasHoverData;
    FColors: TAtlasColors;
    FItems: TArray<TAtlasHoverItem>;
    FItemCount: Integer;
    FHits: TArray<TAtlasHoverHit>;
    FHitCount: Integer;
    FLeft, FRight, FY, FX, FRowHeight, FLineHeight: Integer;
    FFlowFont: TAtlasHoverFont;
    FNoWrap: Boolean;
    function Scale(AValue: Integer): Integer;
    function Height(const AFace: TAtlasHoverFace): Integer;
    function Width(const AFace: TAtlasHoverFace; const AText: string): Integer;
    class function NewItem(AKind: TAtlasHoverItemKind; const ARect: TRect; AColor: TAtlasColor): TAtlasHoverItem;
      static;
    procedure Add(const AItem: TAtlasHoverItem);
    procedure Insert(AAt: Integer; const AItem: TAtlasHoverItem);
    procedure AddHit(AKind: TAtlasHoverHitKind; AIndex: Integer; const ARect: TRect);
    procedure AddText(AX, AY: Integer; const AText: string; const AFace: TAtlasHoverFace; AColor: TAtlasColor);
    /// <summary>Text in kleiner UI-Schrift eine Zeile tiefer; '' ohne Wirkung.</summary>
    procedure AddSmallLine(const AText: string);
    procedure AddLine(ALeft, ATop, ARight: Integer; AColor: TAtlasColor);
    procedure HorizontalLine(ATop: Integer);
    /// <summary>Senkrechter Farbbalken links neben einem Abschnitt ab ATop.</summary>
    procedure SideBar(ATop: Integer; AColor: TAtlasColor);
    procedure Block(const AText: string; AColor: TAtlasColor; AMaxLines: Integer);
    procedure Flow(const AText: string; AColor: TAtlasColor; ABold: Boolean; const AHot: TAtlasHoverHotSpot); overload;
    procedure Flow(const AText: string; AColor: TAtlasColor; ABold: Boolean); overload;
    /// <summary>Fließtext als Verweis mit Klickfläche ACode in AColor.</summary>
    procedure FlowLink(const AText: string; AColor: TAtlasColor; AKind: TAtlasHoverHitKind; ACode: Integer);
    procedure EndFlow;
    /// <summary>Zeile mit kleinen Verweisen beginnen; liefert die bisherige Schrift für EndLinkRow.</summary>
    function BeginLinkRow: TAtlasHoverFont;
    procedure EndLinkRow(AOldFont: TAtlasHoverFont);
    /// <summary>AText, auf AMax Pixel gekürzt (mit „…“); '' ohne Platz.</summary>
    function Clipped(const AFace: TAtlasHoverFace; const AText: string; AMax: Integer): string;
    /// <summary>Keine Klickfläche, keine Hervorhebung.</summary>
    class function NoHot: TAtlasHoverHotSpot; static;
    /// <summary>Hervorhebung unter der Maus ohne eigene Klickfläche (die legt der Aufrufer über mehrere Stücke).
    /// </summary>
    class function HoverHot(AKind: TAtlasHoverHitKind; AHotIndex: Integer; AColor: TAtlasColor): TAtlasHoverHotSpot;
      static;
    /// <summary>Baustein AItem färbt sich unter der Maus über der Klickfläche AKind/AIndex in AColor.</summary>
    class procedure MakeHot(var AItem: TAtlasHoverItem; AKind: TAtlasHoverHitKind; AIndex: Integer;
      AColor: TAtlasColor); static;
  public
    constructor Create(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure);
  end;

implementation

uses
  Atlas.Core.Hover.View,
  System.SysUtils,
  System.Math;

{ TAtlasHoverPainter }

class function TAtlasHoverPainter.NoHot: TAtlasHoverHotSpot;
begin
  Result.Kind := TAtlasHoverHitKind.Action;
  Result.Index := -1;
  Result.HotIndex := -1;
  Result.HotColor := 0;
end;

class function TAtlasHoverPainter.HoverHot(AKind: TAtlasHoverHitKind; AHotIndex: Integer;
  AColor: TAtlasColor): TAtlasHoverHotSpot;
begin
  Result.Kind := AKind;
  Result.Index := -1;
  Result.HotIndex := AHotIndex;
  Result.HotColor := AColor;
end;

class procedure TAtlasHoverPainter.MakeHot(var AItem: TAtlasHoverItem; AKind: TAtlasHoverHitKind; AIndex: Integer;
  AColor: TAtlasColor);
begin
  AItem.HotKind := AKind;
  AItem.HotIndex := AIndex;
  AItem.HotColor := AColor;
end;

constructor TAtlasHoverPainter.Create(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure);
begin
  inherited Create;
  FInput := AInput;
  FMeasure := AMeasure;
  FData := AInput.View.Data;
  FColors := AInput.Colors;
  FItems := nil;
  FHits := nil;
end;

function TAtlasHoverPainter.Scale(AValue: Integer): Integer;
begin
  // Wie MulDiv(AValue, PPI, 96): auf ganze Pixel gerundet.
  Result := (AValue * FInput.PPI + 48) div 96;
end;

function TAtlasHoverPainter.Height(const AFace: TAtlasHoverFace): Integer;
begin
  Result := FMeasure.TextHeight(AFace);
end;

function TAtlasHoverPainter.Width(const AFace: TAtlasHoverFace; const AText: string): Integer;
begin
  Result := FMeasure.TextWidth(AFace, AText);
end;

class function TAtlasHoverPainter.NewItem(AKind: TAtlasHoverItemKind; const ARect: TRect;
  AColor: TAtlasColor): TAtlasHoverItem;
begin
  Result := Default(TAtlasHoverItem);
  Result.Kind := AKind;
  Result.Rect := ARect;
  Result.Color := AColor;
  Result.HotColor := AColor;
  Result.PenWidth := 1;
  Result.HotPenWidth := 1;
  Result.HotIndex := -1;
  Result.Face := TAtlasHoverFace.Create(TAtlasHoverFont.Ui, False, False);
end;

procedure TAtlasHoverPainter.Add(const AItem: TAtlasHoverItem);
begin
  if FItemCount = Length(FItems) then
  begin
    SetLength(FItems, 2 * FItemCount + 16);
  end;
  FItems[FItemCount] := AItem;
  Inc(FItemCount);
end;

procedure TAtlasHoverPainter.Insert(AAt: Integer; const AItem: TAtlasHoverItem);
var
  mIndex: Integer;
begin
  Add(AItem);
  for mIndex := FItemCount - 1 downto AAt + 1 do
  begin
    FItems[mIndex] := FItems[mIndex - 1];
  end;
  FItems[AAt] := AItem;
end;

procedure TAtlasHoverPainter.AddHit(AKind: TAtlasHoverHitKind; AIndex: Integer; const ARect: TRect);
begin
  if FHitCount = Length(FHits) then
  begin
    SetLength(FHits, 2 * FHitCount + 8);
  end;
  FHits[FHitCount].Kind := AKind;
  FHits[FHitCount].Index := AIndex;
  FHits[FHitCount].Rect := ARect;
  Inc(FHitCount);
end;

procedure TAtlasHoverPainter.AddText(AX, AY: Integer; const AText: string; const AFace: TAtlasHoverFace;
  AColor: TAtlasColor);
var
  mItem: TAtlasHoverItem;
begin
  mItem := NewItem(TAtlasHoverItemKind.Text, Rect(AX, AY, AX, AY), AColor);
  mItem.Text := AText;
  mItem.Face := AFace;
  Add(mItem);
end;

procedure TAtlasHoverPainter.AddSmallLine(const AText: string);
var
  mSmallFace: TAtlasHoverFace;
begin
  if AText = '' then
  begin
    Exit;
  end;
  mSmallFace := TAtlasHoverFace.Create(TAtlasHoverFont.SmallUi, False, False);
  Inc(FY, Height(mSmallFace) + Scale(2));
  AddText(FLeft, FY, AText, mSmallFace, FColors.Muted);
end;

procedure TAtlasHoverPainter.AddLine(ALeft, ATop, ARight: Integer; AColor: TAtlasColor);
begin
  Add(NewItem(TAtlasHoverItemKind.Line, Rect(ALeft, ATop, ARight, ATop), AColor));
end;

procedure TAtlasHoverPainter.HorizontalLine(ATop: Integer);
begin
  AddLine(0, ATop, FInput.Width, FColors.Line);
end;

procedure TAtlasHoverPainter.SideBar(ATop: Integer; AColor: TAtlasColor);
var
  mBar: TAtlasHoverItem;
begin
  FLeft := Scale(11);
  mBar := NewItem(TAtlasHoverItemKind.RoundFill, Rect(FLeft, ATop + Scale(1), FLeft + Scale(3), FY - Scale(7)),
    AColor);
  mBar.Radius := 1;
  Add(mBar);
end;

procedure TAtlasHoverPainter.Block(const AText: string; AColor: TAtlasColor; AMaxLines: Integer);
var
  mBottom: Integer;
  mItem: TAtlasHoverItem;
begin
  if AText = '' then
  begin
    Exit;
  end;
  mBottom := FY + FMeasure.BlockHeight(AText, FRight - FLeft);
  if AMaxLines > 0 then
  begin
    mBottom := Min(mBottom, FY + AMaxLines * Height(TAtlasHoverFace.Create(TAtlasHoverFont.Ui, False, False)));
  end;
  mItem := NewItem(TAtlasHoverItemKind.Block, Rect(FLeft, FY, FRight, mBottom), AColor);
  mItem.Text := AText;
  Add(mItem);
  FY := mBottom + Scale(6);
end;

procedure TAtlasHoverPainter.Flow(const AText: string; AColor: TAtlasColor; ABold: Boolean;
  const AHot: TAtlasHoverHotSpot);
var
  mTextFace: TAtlasHoverFace;
  mTextWidth, mTextHeight: Integer;
  mCell: TRect;
  mItem: TAtlasHoverItem;
begin
  // Fließtext mit Umbruch.
  mTextFace := TAtlasHoverFace.Create(FFlowFont, ABold, False);
  mTextWidth := Width(mTextFace, AText);
  mTextHeight := Height(mTextFace);
  if not FNoWrap and (FX + mTextWidth > FRight) and (FX > FLeft) then
  begin
    FX := FLeft;
    Inc(FY, FRowHeight + Scale(4));
    FRowHeight := 0;
  end;
  mCell := Rect(FX, FY, FX + mTextWidth, FY + mTextHeight);
  mItem := NewItem(TAtlasHoverItemKind.Text, mCell, AColor);
  mItem.Text := AText;
  mItem.Face := mTextFace;
  if AHot.HotIndex >= 0 then
  begin
    MakeHot(mItem, AHot.Kind, AHot.HotIndex, AHot.HotColor);
    mItem.HotUnderline := True;
  end;
  Add(mItem);
  if AHot.Index >= 0 then
  begin
    AddHit(AHot.Kind, AHot.Index, mCell);
  end;
  Inc(FX, mTextWidth);
  FRowHeight := Max(FRowHeight, mTextHeight);
end;

procedure TAtlasHoverPainter.Flow(const AText: string; AColor: TAtlasColor; ABold: Boolean);
begin
  Flow(AText, AColor, ABold, NoHot);
end;

procedure TAtlasHoverPainter.FlowLink(const AText: string; AColor: TAtlasColor; AKind: TAtlasHoverHitKind;
  ACode: Integer);
var
  mHot: TAtlasHoverHotSpot;
begin
  mHot := HoverHot(AKind, ACode, AColor);
  mHot.Index := ACode;
  Flow(AText, AColor, False, mHot);
end;

procedure TAtlasHoverPainter.EndFlow;
begin
  Inc(FY, FRowHeight);
  FRowHeight := 0;
  FX := FLeft;
end;

function TAtlasHoverPainter.BeginLinkRow: TAtlasHoverFont;
begin
  Result := FFlowFont;
  FFlowFont := TAtlasHoverFont.SmallUi;
  FX := FLeft;
  FRowHeight := 0;
end;

procedure TAtlasHoverPainter.EndLinkRow(AOldFont: TAtlasHoverFont);
begin
  EndFlow;
  Inc(FY, Scale(6));
  FFlowFont := AOldFont;
end;

function TAtlasHoverPainter.Clipped(const AFace: TAtlasHoverFace; const AText: string; AMax: Integer): string;
var
  mLength: Integer;
begin
  Result := AText;
  if Width(AFace, Result) <= AMax then
  begin
    Exit;
  end;
  mLength := Length(AText);
  while mLength > 0 do
  begin
    Dec(mLength);
    Result := Copy(AText, 1, mLength) + '…';
    if Width(AFace, Result) <= AMax then
    begin
      Exit;
    end;
  end;
  Result := '';
end;

end.
