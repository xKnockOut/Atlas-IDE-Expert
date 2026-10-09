unit Argus.UI.Signature.Hint;

// Parameter-Hint (#436, #437, #440): Fenster ohne Fokus mit allen Überladungen
// des Aufrufs untereinander (Wunsch aus dem Test in der IDE, statt "‹ 1 / 3 ›").
//   - Die gewählte Überladung hat links einen Akzentbalken; ihr aktiver Parameter
//     steht halbfett auf einer Akzentfläche.
//   - In den übrigen passenden Überladungen ist der aktive Parameter halbfett;
//     Überladungen mit zu wenigen Parametern sind gedämpft.
//   - Darunter die Beschreibung des aktiven Parameters der gewählten Überladung.
//   - Klick auf eine Überladung wählt sie; Alt+↑/↓ über die Tastatur (Argus.IDE).
// Platz: unter der Zeile an der öffnenden Klammer; über der Zeile, wenn unten
// kein Platz ist oder das Vervollständigungs-Popup offen ist. Breite höchstens
// 520 px (logisch); lange Signaturen brechen nach "; " um, Folgezeilen eingerückt.

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
  TArgusIndexEvent = reference to procedure(AIndex: Integer);

  TArgusSignatureHint = class(TArgusPopupWindow, IArgusSignatureView)
  public const
    MaxWidth = 520;
    /// <summary>Mehr Überladungen werden nicht gezeigt; eine Zeile nennt den Rest.</summary>
    MaxSignatures = 12;
  private
    FHelp: TArgusSignatureHelp;
    FSignature: Integer;
    FParameter: Integer;
    FAnchor: TRect;
    FAbove: Boolean;
    FOnSelect: TArgusIndexEvent;
    /// <summary>Je gezeigter Überladung ihre Zeilen als Bereiche im Label (0-basiert, Stop exklusiv).</summary>
    FLayouts: TArray<TArray<TPoint>>;
    /// <summary>Erste Zeile jeder gezeigten Überladung (für Mausklicks).</summary>
    FFirstRows: TArray<Integer>;
    function LineHeight: Integer;
    function Gap: Integer;
    function Indent: Integer;
    function Bar: Integer;
    function Shown: Integer;
    function Fits(AIndex: Integer): Boolean;
    function ParameterText: string;
    function ActiveRange(AIndex: Integer; out AStart, AStop: Integer): Boolean;
    /// <summary>Breite eines Teils des Labels von AIndex; der aktive Parameter zählt halbfett.</summary>
    function PartWidth(AIndex: Integer; AStart, AStop: Integer): Integer;
    function Layout(AIndex, AAvailable: Integer): TArray<TPoint>;
    function TotalRows: Integer;
    procedure Place;
    procedure DrawLine(AIndex: Integer; const ARow: TRect; AStart, AStop: Integer);
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
    /// <summary>Klick auf eine Überladung.</summary>
    property OnSelect: TArgusIndexEvent read FOnSelect write FOnSelect;
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

function TArgusSignatureHint.Bar: Integer;
begin
  Result := MulDiv(3, CurrentPPI, 96);
end;

function TArgusSignatureHint.Shown: Integer;
begin
  Result := Min(Length(FHelp.Signatures), MaxSignatures);
end;

function TArgusSignatureHint.Fits(AIndex: Integer): Boolean;
begin
  // Wie im Controller: Der erste Parameter passt immer.
  Result := (FParameter = 0) or (FParameter < Length(FHelp.Signatures[AIndex].Parameters));
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

function TArgusSignatureHint.ActiveRange(AIndex: Integer; out AStart, AStop: Integer): Boolean;
var
  Signature: TArgusSignature;
begin
  AStart := -1;
  AStop := -1;
  Result := False;
  Signature := FHelp.Signatures[AIndex];
  if (FParameter < 0) or (FParameter > High(Signature.Parameters)) then
    Exit;
  AStart := Signature.Parameters[FParameter].Start;
  AStop := Signature.Parameters[FParameter].Stop;
  Result := (AStart >= 0) and (AStop > AStart);
end;

function TArgusSignatureHint.PartWidth(AIndex: Integer; AStart, AStop: Integer): Integer;
var
  Label_: string;
  ActiveStart, ActiveStop, From, Till: Integer;
begin
  Canvas.Font := Font;
  Label_ := FHelp.Signatures[AIndex].Label_;
  if not ActiveRange(AIndex, ActiveStart, ActiveStop) or (ActiveStop <= AStart) or (ActiveStart >= AStop) then
    Exit(Canvas.TextWidth(Copy(Label_, AStart + 1, AStop - AStart)));
  From := Max(AStart, ActiveStart);
  Till := Min(AStop, ActiveStop);
  Result := Canvas.TextWidth(Copy(Label_, AStart + 1, From - AStart)) +
    Canvas.TextWidth(Copy(Label_, Till + 1, AStop - Till));
  Canvas.Font.Style := [fsBold];
  Inc(Result, Canvas.TextWidth(Copy(Label_, From + 1, Till - From)));
  Canvas.Font.Style := [];
end;

function TArgusSignatureHint.Layout(AIndex, AAvailable: Integer): TArray<TPoint>;
var
  Label_: string;
  Breaks: TArray<Integer>;
  Index, LineStart, Candidate, Last, Limit: Integer;
begin
  Label_ := FHelp.Signatures[AIndex].Label_;
  // Mögliche Umbrüche: hinter "; " (zwischen Parametern).
  Breaks := nil;
  for Index := 1 to Length(Label_) - 1 do
    if (Label_[Index] = ';') and (Label_[Index + 1] = ' ') then
      Breaks := Breaks + [Index + 1];
  Breaks := Breaks + [Length(Label_)];
  Result := nil;
  LineStart := 0;
  Last := -1;
  for Candidate in Breaks do
  begin
    if Length(Result) = 0 then
      Limit := AAvailable
    else
      Limit := AAvailable - Indent;
    if (Last >= 0) and (PartWidth(AIndex, LineStart, Candidate) > Limit) then
    begin
      Result := Result + [Point(LineStart, Last)];
      LineStart := Last;
    end;
    Last := Candidate;
  end;
  Result := Result + [Point(LineStart, Length(Label_))];
end;

function TArgusSignatureHint.TotalRows: Integer;
var
  Lines: TArray<TPoint>;
begin
  Result := 0;
  for Lines in FLayouts do
    Inc(Result, Length(Lines));
  if Length(FHelp.Signatures) > MaxSignatures then
    Inc(Result);
  if ParameterText <> '' then
    Inc(Result);
end;

procedure TArgusSignatureHint.Place;
var
  Width, Height, Widest, Available, Index, Line, Row: Integer;
  Bounds, Area: TRect;
begin
  Canvas.Font := Font;
  Available := MulDiv(MaxWidth, CurrentPPI, 96) - 2 * Gap - Bar - 2;
  SetLength(FLayouts, Shown);
  SetLength(FFirstRows, Shown);
  Widest := 0;
  Row := 0;
  for Index := 0 to Shown - 1 do
  begin
    FLayouts[Index] := Layout(Index, Available);
    FFirstRows[Index] := Row;
    for Line := 0 to High(FLayouts[Index]) do
      Widest := Max(Widest, PartWidth(Index, FLayouts[Index][Line].X, FLayouts[Index][Line].Y) +
        IfThen(Line > 0, Indent));
    Inc(Row, Length(FLayouts[Index]));
  end;
  if ParameterText <> '' then
    Widest := Max(Widest, Min(Canvas.TextWidth(ParameterText), Available));
  Width := Min(Widest + 2 * Gap + Bar + 2, MulDiv(MaxWidth, CurrentPPI, 96));
  Height := TotalRows * LineHeight + 2;
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
  FLayouts := nil;
  FFirstRows := nil;
end;

procedure TArgusSignatureHint.DrawLine(AIndex: Integer; const ARow: TRect; AStart, AStop: Integer);
const
  Flags = DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX;
var
  Label_: string;
  ActiveStart, ActiveStop, From, Till, X: Integer;
  Selected, Fitting: Boolean;
  BaseColor: TColor;
  Part: TRect;

  procedure Plain(AFrom, ATill: Integer);
  var
    Text: string;
  begin
    if ATill <= AFrom then
      Exit;
    Text := Copy(Label_, AFrom + 1, ATill - AFrom);
    Canvas.Font.Style := [];
    Canvas.Font.Color := BaseColor;
    Part := Rect(X, ARow.Top, ARow.Right, ARow.Bottom);
    DrawText(Canvas.Handle, PChar(Text), -1, Part, Flags or DT_END_ELLIPSIS);
    Inc(X, Canvas.TextWidth(Text));
  end;

begin
  Label_ := FHelp.Signatures[AIndex].Label_;
  Selected := AIndex = FSignature;
  Fitting := Fits(AIndex);
  if Fitting then
    BaseColor := Colors.Text
  else
    BaseColor := Colors.SecondaryText;
  X := ARow.Left;
  Canvas.Brush.Style := bsClear;
  if not Fitting or not ActiveRange(AIndex, ActiveStart, ActiveStop) or (ActiveStop <= AStart) or
    (ActiveStart >= AStop) then
  begin
    Plain(AStart, AStop);
    Exit;
  end;
  From := Max(AStart, ActiveStart);
  Till := Min(AStop, ActiveStop);
  Plain(AStart, From);
  Canvas.Font.Style := [fsBold];
  Part := Rect(X, ARow.Top + 2, Min(ARow.Right, X + Canvas.TextWidth(Copy(Label_, From + 1, Till - From))),
    ARow.Bottom - 2);
  if Selected then
  begin
    // Gewählte Überladung: aktiver Parameter auf Akzentfläche.
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Colors.SelectionBackground;
    Canvas.FillRect(Part);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := Colors.SelectionText;
  end
  else
    Canvas.Font.Color := BaseColor;
  DrawText(Canvas.Handle, PChar(Copy(Label_, From + 1, Till - From)), -1, Part, Flags or DT_END_ELLIPSIS);
  Inc(X, Part.Width);
  Plain(Till, AStop);
end;

procedure TArgusSignatureHint.Paint;
var
  Row, Part: TRect;
  Height, Index, Line, RowIndex, Left, Right: Integer;
  Doc: string;
begin
  Canvas.Font := Font;
  Canvas.Brush.Color := Colors.Background;
  Canvas.FillRect(ClientRect);
  PaintBorder;
  if Length(FLayouts) = 0 then
    Exit;
  Height := LineHeight;
  Left := 1 + Bar + Gap;
  Right := ClientWidth - 1 - Gap;
  RowIndex := 0;
  for Index := 0 to High(FLayouts) do
  begin
    // Akzentbalken links neben der gewählten Überladung.
    if Index = FSignature then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := Colors.Accent;
      Canvas.FillRect(Rect(1, 1 + RowIndex * Height + 2, 1 + Bar, 1 + (RowIndex + Length(FLayouts[Index])) * Height - 2));
    end;
    for Line := 0 to High(FLayouts[Index]) do
    begin
      Row := Rect(Left, 1 + RowIndex * Height, Right, 1 + (RowIndex + 1) * Height);
      if Line > 0 then
        Inc(Row.Left, Indent);
      DrawLine(Index, Row, FLayouts[Index][Line].X, FLayouts[Index][Line].Y);
      Inc(RowIndex);
    end;
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [];
  if Length(FHelp.Signatures) > MaxSignatures then
  begin
    Canvas.Font.Color := Colors.SecondaryText;
    Part := Rect(Left, 1 + RowIndex * Height, Right, 1 + (RowIndex + 1) * Height);
    DrawText(Canvas.Handle, PChar(Format('… %d weitere', [Length(FHelp.Signatures) - MaxSignatures])), -1, Part,
      DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    Inc(RowIndex);
  end;
  // Beschreibung des aktiven Parameters der gewählten Überladung.
  Doc := ParameterText;
  if Doc <> '' then
  begin
    Canvas.Font.Color := Colors.SecondaryText;
    Part := Rect(Left, 1 + RowIndex * Height, Right, 1 + (RowIndex + 1) * Height);
    DrawText(Canvas.Handle, PChar(Doc), -1, Part, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
      DT_END_ELLIPSIS);
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TArgusSignatureHint.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row, Index: Integer;
begin
  inherited;
  if (Button <> mbLeft) or not Assigned(FOnSelect) then
    Exit;
  Row := (Y - 1) div LineHeight;
  for Index := High(FFirstRows) downto 0 do
    if Row >= FFirstRows[Index] then
    begin
      if Row < FFirstRows[Index] + Length(FLayouts[Index]) then
        FOnSelect(Index);
      Exit;
    end;
end;

end.
