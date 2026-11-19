unit Atlas.UI.Designer.Overlay;

// Gemeinsame Basis der Fenster über dem Formular-Designer (Umrisse, Griffe,
// Marken, Maße, Aufblitzen, Auswahlleiste, Lupe), reine VCL. Jedes Fenster
// gehört dem Hauptfenster der IDE und nimmt nie den Fokus, damit Auswahl und
// Tastatur im Designer bleiben. Je nach Art ist es rahmenlos (Popup), an der
// Schlüsselfarbe durchsichtig und lässt alle Klicks durch. Damit steht das
// nicht wortgleich in jedem Fenster.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.Core.Style.Palette;

type
{$SCOPEDENUMS ON}
  TAtlasOverlayOption = (
    /// <summary>Rahmenloses Popup statt Werkzeugfenster mit Rahmen.</summary>
    Popup,
    /// <summary>Flächen in TAtlasDesignerOverlay.cKeyColor sind durchsichtig.</summary>
    KeyColor,
    /// <summary>Alle Klicks gehen durch das Fenster hindurch (WS_EX_TRANSPARENT).</summary>
    ClickThrough);
{$SCOPEDENUMS OFF}
  TAtlasOverlayOptions = set of TAtlasOverlayOption;

  TAtlasDesignerOverlay = class(TForm) // window-ok: Basis der Überlagerungen, kein Dialog
  protected const
    /// <summary>Schlüsselfarbe der durchsichtigen Flächen (Option KeyColor).</summary>
    cKeyColor = TColor($00FF00FF);
    /// <summary>Abstand einer Beschriftung zum Rand ihres Rahmens, logische Pixel.</summary>
    cTextInset = 3;
  private
    FColors: TAtlasColors;
    FOwnerWindow: HWND;
    FOptions: TAtlasOverlayOptions;
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    /// <summary>Farben nach dem IDE-Thema.</summary>
    property Colors: TAtlasColors read FColors;
  public
    /// <summary>AOwnerWindow: Hauptfenster der IDE; AOptions: Art des Fensters.</summary>
    constructor CreateOverlayWindow(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors;
      AOptions: TAtlasOverlayOptions);
    /// <summary>AValue (logische Pixel) in Pixeln des Bildschirms.</summary>
    function ScalePx(AValue: Integer): Integer;
    /// <summary>Neue Farben übernehmen und neu zeichnen.</summary>
    procedure ApplyColors(const AColors: TAtlasColors);
  end;

implementation

const
  /// <summary>Logische Auflösung, auf die sich ScalePx bezieht.</summary>
  cBasePpi = 96;
  /// <summary>Schrift der Beschriftungen in den Überlagerungen (Namen, Maße, Marken).</summary>
  cFontName = 'Segoe UI'; // window-ok: Überlagerung zeichnet selbst, keine Dialogschrift
  cFontSize = 8;

{ TAtlasDesignerOverlay }

constructor TAtlasDesignerOverlay.CreateOverlayWindow(AOwner: TComponent; AOwnerWindow: HWND;
  const AColors: TAtlasColors; AOptions: TAtlasOverlayOptions);
begin
  // Vor CreateNew: CreateParams braucht beides schon beim Anlegen des Fensters.
  FOwnerWindow := AOwnerWindow;
  FOptions := AOptions;
  inherited CreateNew(AOwner); // window-ok: Überlagerung, kein Dialog
  FColors := AColors;
  DoubleBuffered := True;
  Font.Name := cFontName;
  Font.Size := cFontSize;
  if TAtlasOverlayOption.Popup in AOptions then
  begin
    BorderStyle := bsNone;
  end;
  if TAtlasOverlayOption.KeyColor in AOptions then
  begin
    Color := cKeyColor;
    TransparentColor := True;
    TransparentColorValue := cKeyColor;
  end;
end;

procedure TAtlasDesignerOverlay.CreateParams(var Params: TCreateParams);
begin
  inherited;
  if TAtlasOverlayOption.Popup in FOptions then
  begin
    Params.Style := WS_POPUP;
  end;
  Params.ExStyle := Params.ExStyle or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW;
  if TAtlasOverlayOption.ClickThrough in FOptions then
  begin
    Params.ExStyle := Params.ExStyle or WS_EX_TRANSPARENT;
  end;
  if FOwnerWindow <> 0 then
  begin
    Params.WndParent := FOwnerWindow;
  end;
end;

procedure TAtlasDesignerOverlay.WMMouseActivate(var Message: TWMMouseActivate);
begin
  // Klick in das Fenster: Fokus und Auswahl bleiben im Designer.
  Message.Result := MA_NOACTIVATE;
end;

function TAtlasDesignerOverlay.ScalePx(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, cBasePpi);
end;

procedure TAtlasDesignerOverlay.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

end.
