unit Atlas.UI.Foundation.WrapLabel;

// Umbrechende Beschriftung, die ihre Höhe bei jeder neuen Breite anpasst.
// TLabel berechnet mit AutoSize und WordWrap die Höhe nur, wenn Text, Schrift
// oder AutoSize sich ändern, nicht wenn Ausrichtung oder Anker die Breite
// ändern. Im Code gebaute Fenster legen Labels mit alTop an, solange das
// Ausrichten ausgesetzt ist: Die Höhe entsteht dann bei der Anfangsbreite
// (65 Pixel) und bleibt, wenn das Label danach die volle Breite bekommt. Ein
// Issue-Titel stand so mit Platz für sieben Zeilen in einer Zeile.
// - Resize rechnet die Höhe neu, sobald sich die Breite geändert hat.
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
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

{ TAtlasWrapLabel }

constructor TAtlasWrapLabel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ShowAccelChar := False;
  WordWrap := True;
  FFitWidth := Width;
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
