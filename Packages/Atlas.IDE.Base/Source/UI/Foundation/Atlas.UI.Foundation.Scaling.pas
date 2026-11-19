unit Atlas.UI.Foundation.Scaling;

// Ränder, Innenabstände und Lage von Steuerelementen in logischen Pixeln (96 dpi) setzen (#2675). Margins.SetBounds,
// Padding.SetBounds und SetBounds nehmen Gerätepixel; feste Werte dort waren über 96 dpi zu klein. Die Routinen
// skalieren über die Pixeldichte des Steuerelements (ScaleValue), richtig vor und nach dem Einhängen.

interface

uses
  Vcl.Controls;

type
  TAtlasControlScaling = class
  public
    /// <summary>Margins von AControl; alle Werte in logischen Pixeln.</summary>
    class procedure SetMargins(AControl: TControl; ALeft, ATop, ARight, ABottom: Integer); static;
    /// <summary>Gleicher Rand AValue (logische Pixel) auf allen vier Seiten.</summary>
    class procedure SetMarginsAll(AControl: TControl; AValue: Integer); static;
    /// <summary>Padding von AControl; alle Werte in logischen Pixeln.</summary>
    class procedure SetPadding(AControl: TWinControl; ALeft, ATop, ARight, ABottom: Integer); static;
    /// <summary>Lage und Größe von AControl; alle Werte in logischen Pixeln.</summary>
    class procedure Place(AControl: TControl; ALeft, ATop, AWidth, AHeight: Integer); static;
  end;

implementation

{ TAtlasControlScaling }

class procedure TAtlasControlScaling.SetMargins(AControl: TControl; ALeft, ATop, ARight, ABottom: Integer);
begin
  AControl.Margins.SetBounds(AControl.ScaleValue(ALeft), AControl.ScaleValue(ATop), AControl.ScaleValue(ARight),
    AControl.ScaleValue(ABottom));
end;

class procedure TAtlasControlScaling.SetMarginsAll(AControl: TControl; AValue: Integer);
begin
  SetMargins(AControl, AValue, AValue, AValue, AValue);
end;

class procedure TAtlasControlScaling.SetPadding(AControl: TWinControl; ALeft, ATop, ARight, ABottom: Integer);
begin
  AControl.Padding.SetBounds(AControl.ScaleValue(ALeft), AControl.ScaleValue(ATop), AControl.ScaleValue(ARight),
    AControl.ScaleValue(ABottom));
end;

class procedure TAtlasControlScaling.Place(AControl: TControl; ALeft, ATop, AWidth, AHeight: Integer);
begin
  AControl.SetBounds(AControl.ScaleValue(ALeft), AControl.ScaleValue(ATop), AControl.ScaleValue(AWidth),
    AControl.ScaleValue(AHeight));
end;

end.
