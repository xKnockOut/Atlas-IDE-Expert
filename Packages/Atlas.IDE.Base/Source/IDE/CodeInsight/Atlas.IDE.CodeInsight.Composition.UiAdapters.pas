unit Atlas.IDE.CodeInsight.Composition.UiAdapters;

// Fenster der UI-Features von Base als Ansichten der Controller für die Kompositionswurzel: Popup der
// Vervollständigung, Parameter-Hint und Messung des Tooltips. Nur diese Unit erzeugt die Adapter; die Fenster
// bekommen sie über die Fabriken TAtlasCompletionViews, TAtlasSignatureViews und TAtlasHoverMeasures.

interface

/// <summary>Fabriken der Fenster-Adapter einsetzen; ab der Unit-Initialisierung.</summary>
procedure InstallUiAdapters;

implementation

uses
  Vcl.Graphics,
  Atlas.UI.Popup.Styled,
  Atlas.UI.Completion.Popup,
  Atlas.UI.Completion.Adapters.PopupView,
  Atlas.UI.Signature.Hint,
  Atlas.UI.Signature.Adapters.HintView,
  Atlas.UI.Hover.Tip,
  Atlas.UI.Hover.Adapters.TipMeasure,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Signature.Contract,
  Atlas.Core.Hover.Contract;

procedure InstallUiAdapters;
begin
  TAtlasCompletionViews.Factory :=
    function(APopup: TAtlasCompletionPopup): IAtlasCompletionView
    begin
      Result := TAtlasCompletionPopupView.Create(APopup);
    end;
  TAtlasSignatureViews.Factory :=
    function(AHint: TAtlasSignatureHint): IAtlasSignatureView
    begin
      Result := TAtlasSignatureHintView.Create(AHint);
    end;
  TAtlasHoverMeasures.Factory :=
    function(ACanvas: TCanvas; AFont, AUIFont: TFont; const ADeclaration: TAtlasStyledText): IAtlasHoverMeasure
    begin
      Result := TAtlasHoverTipMeasure.Create(ACanvas, AFont, AUIFont, ADeclaration);
    end;
end;

end.
