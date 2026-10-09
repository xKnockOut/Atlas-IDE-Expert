unit Argus.UI.Signature.Hint;

// Parameter-Hint (#436, #437, #440): Fenster ohne Fokus mit der Signatur des
// Aufrufs. Der aktive Parameter steht halbfett auf einer Akzentfläche; darunter
// seine Beschreibung aus XMLDoc (sonst entfällt die Zeile). Bei Überladungen
// rechts in der ersten Zeile "‹ 1 / 3 ›", die Pfeile sind klickbar. Platz: unter
// der Zeile an der öffnenden Klammer; über der Zeile, wenn unten kein Platz ist
// oder das Vervollständigungs-Popup offen ist. Breite höchstens 520 px
// (logisch); längere Signaturen brechen nach einem "; " um, Folgezeilen eingerückt.

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
    /// <summary>Zeilen der Signatur als Bereiche im Label (0-basiert, Stop exklusiv).</summary>
    FLines: TArray<TPoint>;
    function LineHeight: Integer;
    function Gap: Integer;
    function Indent: Integer;
    function OverloadText: string;
    function ParameterText: string;
    function ActiveRange(out AStart, AStop: Integer): Boolean;
    /// <summary>Breite eines Teils des Labels; der aktive Parameter zählt halbfett.</summary>
    function PartWidth(const ALabel: string; AStart, AStop: Integer): Integer;
    procedure Layout(AAvailable: Integer);
    procedure Place;
    procedure DrawLine(const ARow: TRect; const ALabel: string; AStart, AStop: Integer);
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

function TArgusSignatureHint.Indent: Integer;
begin
  Result := MulDiv(24, CurrentPPI, 96);
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

function TArgusSignatureHint.ActiveRange(out AStart, AStop: Integer): Boolean;
var
  Signature: TArgusSignature;
begin
  AStart := -1;
  AStop := -1;
  Result := False;
  if (FSignature < 0) or (FSignature > High(FHelp.Signatures)) then
    Exit;
  Signature := FHelp.Signatures[FSignature];
  if (FParameter < 0) or (FParameter > High(Signature.Parameters)) then
    Exit;
  AStart := Signature.Parameters[FParameter].Start;
  AStop := Signature.Parameters[FParameter].Stop;
  Result := (AStart >= 0) and (AStop > AStart);
end;

function TArgusSignatureHint.PartWidth(const ALabel: string; AStart, AStop: Integer): Integer;
var
  ActiveStart, ActiveStop, From, Till: Integer;
begin
  Canvas.Font := Font;
  if not ActiveRange(ActiveStart, ActiveStop) or (ActiveStop <= AStart) or (ActiveStart >= AStop) then
    Exit(Canvas.TextWidth(Copy(ALabel, AStart + 1, AStop - AStart)));
  From := Max(AStart, ActiveStart);
  Till := Min(AStop, ActiveStop);
  Result := Canvas.TextWidth(Copy(ALabel, AStart + 1, From - AStart)) +
    Canvas.TextWidth(Copy(ALabel, Till + 1, AStop - Till));
  Canvas.Font.Style := [fsBold];
  Inc(Result, Canvas.TextWidth(Copy(ALabel, From + 1, Till - From)));
  Canvas.Font.Style := [];
end;

procedure TArgusSignatureHint.Layout(AAvailable: Integer);
var
  Label_: string;
  Breaks: TArray<Integer>;
  Index, LineStart, Candidate, Last, Limit: Integer;
begin
  Label_ := FHelp.Signatures[FSignature].Label_;
  // Mögliche Umbrüche: hinter "; " (zwischen Parametern) und vor dem Rückgabetyp.
  Breaks := nil;
  for Index := 1 to Length(Label_) - 1 do
    if (Label_[Index] = ';') and (Label_[Index + 1] = ' ') then
      Breaks := Breaks + [Index + 1];
  Breaks := Breaks + [Length(Label_)];
  FLines := nil;
  LineStart := 0;
  Last := -1;
  for Candidate in Breaks do
  begin
    // Die erste Zeile teilt sich den Platz mit "‹ 1 / 3 ›", Folgezeilen sind eingerückt.
    if Length(FLines) = 0 then
      Limit := AAvailable
    else
      Limit := AAvailable - Indent;
    if (Last >= 0) and (PartWidth(Label_, LineStart, Candidate) > Limit) then
    begin
      FLines := FLines + [Point(LineStart, Last)];
      LineStart := Last;
    end;
    Last := Candidate;
  end;
  FLines := FLines + [Point(LineStart, Length(Label_))];
end;

procedure TArgusSignatureHint.Place;
var
  Width, Height, Lines, Widest, Available, Overload, Index: Integer;
  Bounds, Area: TRect;
  Label_: string;
begin
  Canvas.Font := Font;
  Label_ := FHelp.Signatures[FSignature].Label_;
  Overload := 0;
  if OverloadText <> '' then
    Overload := Canvas.TextWidth(OverloadText) + 3 * Gap;
  Available := MulDiv(MaxWidth, CurrentPPI, 96) - 2 * Gap - 2 - Overload;
  Layout(Available);
  Widest := 0;
  for Index := 0 to High(FLines) do
    Widest := Max(Widest, PartWidth(Label_, FLines[Index].X, FLines[Index].Y) + IfThen(Index > 0, Indent));
  Inc(Widest, Overload);
  if ParameterText <> '' then
    Widest := Max(Widest, Min(Canvas.TextWidth(ParameterText), MulDiv(MaxWidth, CurrentPPI, 96)));
  Width := Min(Widest + 2 * Gap + 2, MulDiv(MaxWidth, CurrentPPI, 96));
  Lines := Length(FLines);
  if ParameterText <> '' then
    Inc(Lines);
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
  FLines := nil;
end;

procedure TArgusSignatureHint.DrawLine(const ARow: TRect; const ALabel: string; AStart, AStop: Integer);
const
  Flags = DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX;
var
  ActiveStart, ActiveStop, From, Till, X: Integer;
  Part: TRect;

  procedure Plain(AFrom, ATill: Integer);
  var
    Text: string;
  begin
    if ATill <= AFrom then
      Exit;
    Text := Copy(ALabel, AFrom + 1, ATill - AFrom);
    Canvas.Font.Style := [];
    Canvas.Font.Color := Colors.Text;
    Part := Rect(X, ARow.Top, ARow.Right, ARow.Bottom);
    DrawText(Canvas.Handle, PChar(Text), -1, Part, Flags or DT_END_ELLIPSIS);
    Inc(X, Canvas.TextWidth(Text));
  end;

begin
  X := ARow.Left;
  Canvas.Brush.Style := bsClear;
  if not ActiveRange(ActiveStart, ActiveStop) or (ActiveStop <= AStart) or (ActiveStart >= AStop) then
  begin
    Plain(AStart, AStop);
    Exit;
  end;
  From := Max(AStart, ActiveStart);
  Till := Min(AStop, ActiveStop);
  Plain(AStart, From);
  // Aktiver Parameter: halbfett auf Akzentfläche.
  Canvas.Font.Style := [fsBold];
  Part := Rect(X, ARow.Top + 2, Min(ARow.Right, X + Canvas.TextWidth(Copy(ALabel, From + 1, Till - From))),
    ARow.Bottom - 2);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Colors.SelectionBackground;
  Canvas.FillRect(Part);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := Colors.SelectionText;
  DrawText(Canvas.Handle, PChar(Copy(ALabel, From + 1, Till - From)), -1, Part, Flags or DT_END_ELLIPSIS);
  Inc(X, Part.Width);
  Plain(Till, AStop);
end;

procedure TArgusSignatureHint.Paint;
var
  Signature: TArgusSignature;
  Row, Part: TRect;
  Height, Index, Right: Integer;
  Overload, Doc: string;
begin
  Canvas.Font := Font;
  Canvas.Brush.Color := Colors.Background;
  Canvas.FillRect(ClientRect);
  PaintBorder;
  if (FSignature < 0) or (FSignature > High(FHelp.Signatures)) or (Length(FLines) = 0) then
    Exit;
  Signature := FHelp.Signatures[FSignature];
  Height := LineHeight;
  Right := ClientWidth - 1 - Gap;
  // Überladungen rechts in der ersten Zeile.
  Overload := OverloadText;
  FPreviousRect := TRect.Empty;
  FNextRect := TRect.Empty;
  if Overload <> '' then
  begin
    Part := Rect(Right - Canvas.TextWidth(Overload), 1, Right, 1 + Height);
    Canvas.Font.Color := Colors.SecondaryText;
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(Overload), -1, Part, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    FPreviousRect := Rect(Part.Left - Gap, Part.Top, Part.Left + Canvas.TextWidth('‹ ') + Gap, Part.Bottom);
    FNextRect := Rect(Part.Right - Canvas.TextWidth(' ›') - Gap, Part.Top, Part.Right + Gap, Part.Bottom);
  end;
  for Index := 0 to High(FLines) do
  begin
    Row := Rect(1 + Gap, 1 + Index * Height, Right, 1 + (Index + 1) * Height);
    if Index = 0 then
    begin
      if Overload <> '' then
        Row.Right := FPreviousRect.Left - Gap;
    end
    else
      Inc(Row.Left, Indent);
    DrawLine(Row, Signature.Label_, FLines[Index].X, FLines[Index].Y);
  end;
  // Beschreibung des aktiven Parameters.
  Doc := ParameterText;
  if Doc <> '' then
  begin
    Canvas.Font.Style := [];
    Canvas.Font.Color := Colors.SecondaryText;
    Part := Rect(1 + Gap, 1 + Length(FLines) * Height, Right, 1 + (Length(FLines) + 1) * Height);
    DrawText(Canvas.Handle, PChar(Doc), -1, Part, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
      DT_END_ELLIPSIS);
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
