unit Atlas.UI.Debug.ViewerImage;

// Bild im Ansichtsfenster der Visualisierer (#835), reine VCL: zeigt die
// Pixel eines TAtlasVisualizerView in Originalgröße, mit Rollbalken, vor einem
// Schachbrett, damit Transparenz und Weiß erkennbar sind. Das Bitmap gehört
// dem Bild und wird bei jedem neuen Inhalt ersetzt.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.Graphics;

type
  TAtlasDebugViewerImage = class(TScrollBox)
  private
    FPaintBox: TPaintBox;
    FBitmap: TBitmap;
    procedure BoxPaint(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Pixel als $AARRGGBB zeilenweise; passen Größe und Anzahl nicht zusammen, bleibt das Bild leer.
    /// </summary>
    procedure ShowPixels(AWidth, AHeight: Integer; const APixels: TArray<Cardinal>);
    /// <summary>Gezeigtes Bild; nil ohne Bild.</summary>
    property Bitmap: TBitmap read FBitmap;
  end;

implementation

uses
  System.SysUtils,
  System.Types;

const
  /// <summary>Kantenlänge eines Schachbrettfelds in Pixeln des Bildes.</summary>
  cCell = 8;
  /// <summary>Dunkles Feld des Schachbretts.</summary>
  cCheckerDark = TColor($00E0E0E0);

{ TAtlasDebugViewerImage }

constructor TAtlasDebugViewerImage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BorderStyle := bsNone;
  FPaintBox := TPaintBox.Create(Self);
  FPaintBox.Parent := Self;
  FPaintBox.OnPaint := BoxPaint;
end;

destructor TAtlasDebugViewerImage.Destroy;
begin
  FreeAndNil(FBitmap);
  inherited Destroy;
end;

procedure TAtlasDebugViewerImage.BoxPaint(Sender: TObject);
var
  X, Y: Integer;
begin
  if FBitmap = nil then
  begin
    Exit;
  end;
  // Schachbrett hinter dem Bild, damit Transparenz und Weiß erkennbar sind.
  for Y := 0 to (FPaintBox.Height - 1) div cCell do
  begin
    for X := 0 to (FPaintBox.Width - 1) div cCell do
    begin
      if Odd(X + Y) then
      begin
        FPaintBox.Canvas.Brush.Color := cCheckerDark;
      end
      else
      begin
        FPaintBox.Canvas.Brush.Color := clWhite;
      end;
      FPaintBox.Canvas.FillRect(Rect(X * cCell, Y * cCell, (X + 1) * cCell, (Y + 1) * cCell));
    end;
  end;
  FPaintBox.Canvas.Draw(0, 0, FBitmap);
end;

procedure TAtlasDebugViewerImage.ShowPixels(AWidth, AHeight: Integer; const APixels: TArray<Cardinal>);
var
  mRow: Integer;
begin
  FreeAndNil(FBitmap);
  if (AWidth > 0) and (AHeight > 0) and (Length(APixels) = AWidth * AHeight) then
  begin
    FBitmap := TBitmap.Create;
    FBitmap.PixelFormat := pf32bit;
    FBitmap.SetSize(AWidth, AHeight);
    // $AARRGGBB liegt im Speicher als B, G, R, A: genau die Zeile eines 32-Bit-DIB.
    for mRow := 0 to AHeight - 1 do
    begin
      Move(APixels[mRow * AWidth], FBitmap.ScanLine[mRow]^, AWidth * SizeOf(Cardinal));
    end;
    FPaintBox.SetBounds(0, 0, AWidth, AHeight);
  end
  else
  begin
    FPaintBox.SetBounds(0, 0, 0, 0);
  end;
  FPaintBox.Invalidate;
end;

end.
