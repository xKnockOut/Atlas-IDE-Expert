unit Atlas.UI.Foundation.WrapLabel;

// Umbrechende Beschriftung, die ihre Höhe bei jeder neuen Breite anpasst.
// TLabel berechnet mit AutoSize und WordWrap die Höhe nur, wenn Text, Schrift
// oder AutoSize sich ändern, nicht wenn Ausrichtung oder Anker die Breite
// ändern. Im Code gebaute Fenster legen Labels mit alTop an, solange das
// Ausrichten ausgesetzt ist: Die Höhe entsteht dann bei der Anfangsbreite
// (65 Pixel) und bleibt, wenn das Label danach die volle Breite bekommt. Ein
// Issue-Titel stand so mit Platz für sieben Zeilen in einer Zeile.
// - Resize rechnet die Höhe neu, sobald sich die Breite geändert hat.
// - AdjustBounds behält die Breite und rechnet nur die Höhe: Die VCL schrumpft
//   bei WordWrap die Breite auf die längste Zeile (bei leerem Text auf ein
//   Leerzeichen), danach bräche jeder spätere Text an dieser Breite um.
// - Die neue Höhe ändert die Breite nicht, daher kein zweiter Durchlauf.

interface

uses
  System.Classes,
  Vcl.StdCtrls;

type
  TAtlasWrapLabel = class(TLabel)
  private
    FFitWidth: Integer;
  protected
    procedure Resize; override;
    procedure AdjustBounds; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

uses
  Winapi.Windows,
  System.Types,
  Vcl.Graphics;

{ TAtlasWrapLabel }

constructor TAtlasWrapLabel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ShowAccelChar := False;
  WordWrap := True;
  FFitWidth := Width;
end;

procedure TAtlasWrapLabel.AdjustBounds;
var
  mText: string;
  mRect: TRect;
  mDC: HDC;
begin
  if not (WordWrap and AutoSize) or (Width <= 0) or (csReading in ComponentState) or
    (csLoading in ComponentState) then
  begin
    inherited AdjustBounds;
    Exit;
  end;
  mText := Caption;
  if mText = '' then
  begin
    // Wie die VCL: Ein leerer Text ist eine Zeile hoch.
    mText := ' ';
  end;
  mRect := TRect.Create(0, 0, Width, 0);
  mDC := GetDC(0);
  try
    Canvas.Handle := mDC;
    try
      Canvas.Font := Font;
      DrawText(Canvas.Handle, PChar(mText), Length(mText), mRect, DT_CALCRECT or DT_WORDBREAK or DT_EXPANDTABS or
        DT_NOPREFIX);
    finally
      Canvas.Handle := 0;
    end;
  finally
    ReleaseDC(0, mDC);
  end;
  SetBounds(Left, Top, Width, mRect.Bottom);
end;

procedure TAtlasWrapLabel.Resize;
begin
  inherited Resize;
  if (Width <> FFitWidth) and WordWrap and AutoSize then
  begin
    FFitWidth := Width;
    AdjustBounds;
  end;
end;

end.
