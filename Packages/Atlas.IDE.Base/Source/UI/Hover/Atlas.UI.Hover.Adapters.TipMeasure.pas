unit Atlas.UI.Hover.Adapters.TipMeasure;

// Die Zeichenfläche des Tooltips als Messung für den Satz (IAtlasHoverMeasure aus
// Atlas.Core.Hover.Layout.Contract): Textbreiten und -höhen in den Schriften des Tooltips, Absatzhöhe in der
// UI-Schrift, Breite und Umbruch der eingefärbten Deklaration in der Editorschrift. Die Kompositionswurzel setzt
// ihn über TAtlasHoverMeasures.Factory ein; der Tooltip legt ihn je Satz an.

interface

uses
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.Layout.Contract,
  Atlas.UI.Popup.Styled;

type
  TAtlasHoverTipMeasure = class(TInterfacedObject, IAtlasHoverMeasure)
  private
    FCanvas: TCanvas;
    FFont: TFont;
    FUIFont: TFont;
    FDeclaration: TAtlasStyledText;
  public
    /// <summary>ACanvas und die Schriften gehören dem Tooltip und leben länger als der Satz.</summary>
    constructor Create(ACanvas: TCanvas; AFont, AUIFont: TFont; const ADeclaration: TAtlasStyledText);
    function TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
    function TextHeight(const AFace: TAtlasHoverFace): Integer;
    function BlockHeight(const AText: string; AWidth: Integer): Integer;
    function DeclarationWidth(AFrom, ATill: Integer): Integer;
    function DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Hover.Tip;

{ TAtlasHoverTipMeasure }

constructor TAtlasHoverTipMeasure.Create(ACanvas: TCanvas; AFont, AUIFont: TFont;
  const ADeclaration: TAtlasStyledText);
begin
  inherited Create;
  FCanvas := ACanvas;
  FFont := AFont;
  FUIFont := AUIFont;
  FDeclaration := ADeclaration;
end;

function TAtlasHoverTipMeasure.TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
begin
  ApplyHoverFace(FCanvas, FFont, FUIFont, AFace, 0);
  Result := FCanvas.TextWidth(AText);
end;

function TAtlasHoverTipMeasure.TextHeight(const AFace: TAtlasHoverFace): Integer;
begin
  ApplyHoverFace(FCanvas, FFont, FUIFont, AFace, 0);
  Result := FCanvas.TextHeight('Wg');
end;

function TAtlasHoverTipMeasure.BlockHeight(const AText: string; AWidth: Integer): Integer;
var
  mArea: TRect;
begin
  FCanvas.Font := FUIFont;
  mArea := Rect(0, 0, AWidth, 0);
  DrawText(FCanvas.Handle, PChar(AText), -1, mArea, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
  Result := mArea.Bottom;
end;

function TAtlasHoverTipMeasure.DeclarationWidth(AFrom, ATill: Integer): Integer;
begin
  FCanvas.Font := FFont;
  Result := FDeclaration.Width(FCanvas, AFrom, ATill);
end;

function TAtlasHoverTipMeasure.DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
begin
  FCanvas.Font := FFont;
  Result := FDeclaration.WrapAtSpaces(FCanvas, AWidth, AIndent);
end;

end.
