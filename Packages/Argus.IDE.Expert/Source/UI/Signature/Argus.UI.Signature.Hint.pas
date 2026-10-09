unit Argus.UI.Signature.Hint;

// Parameter-Hint (#436, #437, #440): Fenster ohne Fokus mit der Signatur des
// Aufrufs. Der aktive Parameter steht halbfett auf einer Akzentfläche; darunter
// seine Beschreibung aus XMLDoc (sonst entfällt die Zeile). Bei Überladungen
// rechts "‹ 1 / 3 ›", die Pfeile sind klickbar. Platz: unter der Zeile an der
// öffnenden Klammer; über der Zeile, wenn unten kein Platz ist oder das
// Vervollständigungs-Popup offen ist. Breite höchstens 520 px (logisch).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Argus.Core.Signature.Contract,
  Argus.Core.Signature.Controller,
  Argus.UI.Popup.Window;

type
  TArgusSignatureHint = class(TArgusPopupWindow, IArgusSignatureView)
  public const
    MaxWidth = 520;
  private
    FHelp: TArgusSignatureHelp;
    FSignature: Integer;
    FParameter: Integer;
    FAnchor: TRect;
    FAbove: Boolean;
    FPreviousRect: TRect;
    FNextRect: TRect;
    FOnPrevious: TProc;
    FOnNext: TProc;
    function LineHeight: Integer;
    function Gap: Integer;
    function OverloadText: string;
    function ParameterText: string;
    procedure Place;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    { IArgusSignatureView }
    procedure ShowSignature(const AHelp: TArgusSignatureHelp; ASignature, AParameter: Integer);
    procedure HideSignature;
    /// <summary>Rechteck der Zeile an der öffnenden Klammer in Bildschirmkoordinaten.</summary>
    property Anchor: TRect read FAnchor write FAnchor;
    /// <summary>Über der Zeile statt darunter (Vervollständigung offen, #440).</summary>
    property Above: Boolean read FAbove write FAbove;
    property OnPrevious: TProc read FOnPrevious write FOnPrevious;
    property OnNext: TProc read FOnNext write FOnNext;
  end;

implementation

uses
  System.Math;

{ TArgusSignatureHint }

function TArgusSignatureHint.LineHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg') + MulDiv(6, CurrentPPI, 96);
end;

function TArgusSignatureHint.Gap: Integer;
begin
  Result := MulDiv(6, CurrentPPI, 96);
end;

function TArgusSignatureHint.OverloadText: string;
begin
  if Length(FHelp.Signatures) > 1 then
    Result := Format('‹ %d / %d ›', [FSignature + 1, Length(FHelp.Signatures)])
  else
    Result := '';
end;

function TArgusSignatureHint.ParameterText: string;
var
  Signature: TArgusSignature;
  Parameter: TArgusSignatureParameter;
  Name: string;
begin
  Result := '';
  if (FSignature < 0) or (FSignature > High(FHelp.Signatures)) then
    Exit;
  Signature := FHelp.Signatures[FSignature];
  if (FParameter < 0) or (FParameter > High(Signature.Parameters)) then
    Exit;
  Parameter := Signature.Parameters[FParameter];
  if Parameter.Documentation = '' then
    Exit;
  Name := Trim(Parameter.Text(Signature.Label_));
  if Pos(':', Name) > 0 then
    Name := Trim(Copy(Name, 1, Pos(':', Name) - 1));
  Result := Name + ': ' + StringReplace(Parameter.Documentation, sLineBreak, ' ', [rfReplaceAll]);
end;

procedure TArgusSignatureHint.Place;
var
  Width, Height, Lines: Integer;
  Bounds, Area: TRect;
  Label_: string;
begin
  Canvas.Font := Font;
  Label_ := FHelp.Signatures[FSignature].Label_;
  Canvas.Font.Style := [fsBold];
  Width := Canvas.TextWidth(Label_);
  Canvas.Font.Style := [];
  if OverloadText <> '' then
    Inc(Width, Canvas.TextWidth(OverloadText) + 3 * Gap);
  if ParameterText <> '' then
    Width := Max(Width, Canvas.TextWidth(ParameterText));
  Width := Min(Width + 2 * Gap + 2, MulDiv(MaxWidth, CurrentPPI, 96));
  Lines := 1;
  if ParameterText <> '' then
    Lines := 2;
  Height := Lines * LineHeight + 2;
  Area := WorkAreaAt(FAnchor.TopLeft);
  if FAbove then
    Bounds := TRect.Create(Point(FAnchor.Left, FAnchor.Top - Height - 2), Width, Height)
  else
    Bounds := TRect.Create(Point(FAnchor.Left, FAnchor.Bottom + 2), Width, Height);
  if Bounds.Bottom > Area.Bottom then
    Bounds.SetLocation(Bounds.Left, FAnchor.Top - Height - 2);
  if Bounds.Top < Area.Top then
    Bounds.SetLocation(Bounds.Left, FAnchor.Bottom + 2);
  if Bounds.Right > Area.Right then
    Bounds.SetLocation(Max(Area.Left, Area.Right - Width), Bounds.Top);
  ShowAt(Bounds);
end;

procedure TArgusSignatureHint.ShowSignature(const AHelp: TArgusSignatureHelp; ASignature, AParameter: Integer);
begin
  if (ASignature < 0) or (ASignature > High(AHelp.Signatures)) then
  begin
    HideSignature;
    Exit;
  end;
  FHelp := AHelp;
  FSignature := ASignature;
  FParameter := AParameter;
  Place;
end;

procedure TArgusSignatureHint.HideSignature;
begin
  HidePopup;
  FHelp := Default(TArgusSignatureHelp);
end;

procedure TArgusSignatureHint.Paint;
var
  Signature: TArgusSignature;
  Parameter: TArgusSignatureParameter;
  Row, Part: TRect;
  X, Height: Integer;
  Before, Active, After, Overload, Doc: string;
  Flags: Cardinal;
begin
  Canvas.Font := Font;
  Canvas.Brush.Color := Colors.Background;
  Canvas.FillRect(ClientRect);
  PaintBorder;
  if (FSignature < 0) or (FSignature > High(FHelp.Signatures)) then
    Exit;
  Signature := FHelp.Signatures[FSignature];
  Height := LineHeight;
  Flags := DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX;
  Row := Rect(1 + Gap, 1, ClientWidth - 1 - Gap, 1 + Height);
  // Überladungen rechts.
  Overload := OverloadText;
  FPreviousRect := TRect.Empty;
  FNextRect := TRect.Empty;
  if Overload <> '' then
  begin
    Part := Rect(Row.Right - Canvas.TextWidth(Overload), Row.Top, Row.Right, Row.Bottom);
    Canvas.Font.Color := Colors.SecondaryText;
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(Overload), -1, Part, Flags);
    FPreviousRect := Rect(Part.Left - Gap, Part.Top, Part.Left + Canvas.TextWidth('‹ ') + Gap, Part.Bottom);
    FNextRect := Rect(Part.Right - Canvas.TextWidth(' ›') - Gap, Part.Top, Part.Right + Gap, Part.Bottom);
    Row.Right := Part.Left - 2 * Gap;
  end;
  // Signatur in drei Teilen; der aktive Parameter halbfett auf Akzentfläche.
  Before := Signature.Label_;
  Active := '';
  After := '';
  if (FParameter >= 0) and (FParameter <= High(Signature.Parameters)) then
  begin
    Parameter := Signature.Parameters[FParameter];
    if (Parameter.Start >= 0) and (Parameter.Stop > Parameter.Start) then
    begin
      Before := Copy(Signature.Label_, 1, Parameter.Start);
      Active := Copy(Signature.Label_, Parameter.Start + 1, Parameter.Stop - Parameter.Start);
      After := Copy(Signature.Label_, Parameter.Stop + 1, MaxInt);
    end;
  end;
  X := Row.Left;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := Colors.Text;
  Part := Rect(X, Row.Top, Row.Right, Row.Bottom);
  DrawText(Canvas.Handle, PChar(Before), -1, Part, Flags or DT_END_ELLIPSIS);
  Inc(X, Canvas.TextWidth(Before));
  if Active <> '' then
  begin
    Canvas.Font.Style := [fsBold];
    Part := Rect(X, Row.Top + 2, Min(Row.Right, X + Canvas.TextWidth(Active)), Row.Bottom - 2);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Colors.SelectionBackground;
    Canvas.FillRect(Part);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := Colors.SelectionText;
    DrawText(Canvas.Handle, PChar(Active), -1, Part, Flags);
    Inc(X, Canvas.TextWidth(Active));
    Canvas.Font.Style := [];
    Canvas.Font.Color := Colors.Text;
    if X < Row.Right then
    begin
      Part := Rect(X, Row.Top, Row.Right, Row.Bottom);
      DrawText(Canvas.Handle, PChar(After), -1, Part, Flags or DT_END_ELLIPSIS);
    end;
  end;
  // Beschreibung des aktiven Parameters.
  Doc := ParameterText;
  if Doc <> '' then
  begin
    Canvas.Font.Color := Colors.SecondaryText;
    Part := Rect(1 + Gap, 1 + Height, ClientWidth - 1 - Gap, 1 + 2 * Height);
    DrawText(Canvas.Handle, PChar(Doc), -1, Part, Flags or DT_END_ELLIPSIS);
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TArgusSignatureHint.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  if FPreviousRect.Contains(Point(X, Y)) and Assigned(FOnPrevious) then
    FOnPrevious()
  else if FNextRect.Contains(Point(X, Y)) and Assigned(FOnNext) then
    FOnNext();
end;

end.
