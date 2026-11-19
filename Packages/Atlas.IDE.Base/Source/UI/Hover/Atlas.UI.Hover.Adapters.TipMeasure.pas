unit Atlas.UI.Hover.Adapters.TipMeasure;

// Die Zeichenfläche des Tooltips (TAtlasHoverTipView) als Messung für den Satz (IAtlasHoverMeasure aus
// Atlas.Core.Hover.Layout.Contract). Reicht nur weiter; der Tooltip hält den Adapter, die Kompositionswurzel setzt
// ihn über TAtlasHoverTipView.MeasureFactory ein.

interface

uses
  System.Types,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.Layout.Contract,
  Atlas.UI.Hover.Tip;

type
  TAtlasHoverTipMeasure = class(TInterfacedObject, IAtlasHoverMeasure)
  private
    FTip: TAtlasHoverTipView;
  public
    /// <summary>ATip lebt länger als der Adapter (er hält ihn).</summary>
    constructor Create(ATip: TAtlasHoverTipView);
    function TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
    function TextHeight(const AFace: TAtlasHoverFace): Integer;
    function BlockHeight(const AText: string; AWidth: Integer): Integer;
    function DeclarationWidth(AFrom, ATill: Integer): Integer;
    function DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
  end;

implementation

{ TAtlasHoverTipMeasure }

constructor TAtlasHoverTipMeasure.Create(ATip: TAtlasHoverTipView);
begin
  inherited Create;
  FTip := ATip;
end;

function TAtlasHoverTipMeasure.TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
begin
  Result := FTip.MeasureTextWidth(AFace, AText);
end;

function TAtlasHoverTipMeasure.TextHeight(const AFace: TAtlasHoverFace): Integer;
begin
  Result := FTip.MeasureTextHeight(AFace);
end;

function TAtlasHoverTipMeasure.BlockHeight(const AText: string; AWidth: Integer): Integer;
begin
  Result := FTip.MeasureBlockHeight(AText, AWidth);
end;

function TAtlasHoverTipMeasure.DeclarationWidth(AFrom, ATill: Integer): Integer;
begin
  Result := FTip.MeasureDeclarationWidth(AFrom, ATill);
end;

function TAtlasHoverTipMeasure.DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
begin
  Result := FTip.MeasureDeclarationLines(AWidth, AIndent);
end;

end.
