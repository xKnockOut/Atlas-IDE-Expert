unit Argus.UI.Signature.Hint;

// Parameter-Hint (#436, #437, #439, #440): Fenster ohne Fokus mit allen
// Überladungen des Aufrufs untereinander (Wunsch aus dem Test in der IDE, statt "‹ 1 / 3 ›").
//   - Signaturen in der Editorschrift, eingefärbt wie im Entwurf (#411).
//   - Die gewählte Überladung hat links einen Akzentbalken; ihr aktiver Parameter
//     steht halbfett in Akzentfarbe auf einer Akzentfläche.
//   - In den übrigen passenden Überladungen ist der aktive Parameter halbfett;
//     Überladungen mit zu wenigen Parametern sind gedämpft.
//   - Darunter auf abgesetzter Fläche Name und Beschreibung des aktiven Parameters.
//   - Erlaubt keine Überladung so viele Argumente: Rahmen und untere Zeile in
//     Fehlerfarbe, "Keine Überladung mit n Parametern." (#439).
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
  Argus.UI.Popup.Window,
  Argus.UI.Popup.Styled;

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
    /// <summary>Je gezeigter Überladung ihr eingefärbtes Label.</summary>
    FStyled: TArray<TArgusStyledText>;
    /// <summary>Je gezeigter Überladung ihre Zeilen als Bereiche im Label (0-basiert, Stop exklusiv).</summary>
    FLayouts: TArray<TArray<TPoint>>;
    /// <summary>Erste Zeile jeder gezeigten Überladung (für Mausklicks).</summary>
    FFirstRows: TArray<Integer>;
    function LineHeight: Integer;
    function Pad: Integer;
    function Gap: Integer;
    function Indent: Integer;
    function Bar: Integer;
    function Shown: Integer;
    function Fits(AIndex: Integer): Boolean;
    /// <summary>Keine Überladung hat so viele Parameter (#439).</summary>
    function TooMany: Boolean;
    /// <summary>Name und Beschreibung des aktiven Parameters der gewählten Überladung.</summary>
    function ParameterDoc(out AName, AText: string): Boolean;
    function HasDocLine: Boolean;
    function DocHeight: Integer;
    function Layout(AIndex, AAvailable: Integer): TArray<TPoint>;
    function TotalRows: Integer;
    procedure Prepare;
    procedure Place;
    procedure PaintDocLine(ATop: Integer);
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
  System.Math,
  Argus.Core.Style.Color;

const
  TextFlags = DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX;

{ TArgusSignatureHint }

function TArgusSignatureHint.LineHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg') + Scale(6);
end;

function TArgusSignatureHint.Pad: Integer;
begin
  Result := Scale(4);
end;

function TArgusSignatureHint.Gap: Integer;
begin
  Result := Scale(10);
end;

function TArgusSignatureHint.Indent: Integer;
begin
  Result := Scale(24);
end;

function TArgusSignatureHint.Bar: Integer;
begin
  Result := Scale(3);
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

function TArgusSignatureHint.TooMany: Boolean;
var
  Index: Integer;
begin
  Result := Length(FHelp.Signatures) > 0;
  for Index := 0 to High(FHelp.Signatures) do
    if Fits(Index) then
      Exit(False);
end;

function TArgusSignatureHint.ParameterDoc(out AName, AText: string): Boolean;
var
  Signature: TArgusSignature;
  Parameter: TArgusSignatureParameter;
begin
  AName := '';
  AText := '';
  Result := False;
  if (FSignature < 0) or (FSignature > High(FHelp.Signatures)) then
    Exit;
  Signature := FHelp.Signatures[FSignature];
  if (FParameter < 0) or (FParameter > High(Signature.Parameters)) then
    Exit;
  Parameter := Signature.Parameters[FParameter];
  if Parameter.Documentation = '' then
    Exit;
  AName := Trim(Parameter.Text(Signature.Label_));
  if Pos(':', AName) > 0 then
    AName := Trim(Copy(AName, 1, Pos(':', AName) - 1));
  // "const S" → "S"
  if LastDelimiter(' ', AName) > 0 then
    AName := Copy(AName, LastDelimiter(' ', AName) + 1, MaxInt);
  AText := StringReplace(Parameter.Documentation, sLineBreak, ' ', [rfReplaceAll]);
  Result := True;
end;

function TArgusSignatureHint.HasDocLine: Boolean;
var
  Name, Text: string;
begin
  Result := TooMany or ParameterDoc(Name, Text);
end;

function TArgusSignatureHint.DocHeight: Integer;
begin
  Canvas.Font := UIFont;
  Result := Canvas.TextHeight('Wg') + Scale(12);
  Canvas.Font := Font;
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
  Canvas.Font := Font;
  for Candidate in Breaks do
  begin
    if Length(Result) = 0 then
      Limit := AAvailable
    else
      Limit := AAvailable - Indent;
    if (Last >= 0) and (FStyled[AIndex].Width(Canvas, LineStart, Candidate) > Limit) then
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
end;

procedure TArgusSignatureHint.Prepare;
var
  Index: Integer;
  Signature: TArgusSignature;
begin
  // Eingefärbte Labels; aktiver Parameter nur in passenden Überladungen, Fläche nur in der gewählten.
  SetLength(FStyled, Shown);
  for Index := 0 to Shown - 1 do
  begin
    Signature := FHelp.Signatures[Index];
    FStyled[Index] := TArgusStyledText.Create(Signature.Label_);
    FStyled[Index].ActiveFill := Index = FSignature;
    if Fits(Index) and (FParameter >= 0) and (FParameter <= High(Signature.Parameters)) and
      (Signature.Parameters[FParameter].Start >= 0) and
      (Signature.Parameters[FParameter].Stop > Signature.Parameters[FParameter].Start) then
    begin
      FStyled[Index].ActiveStart := Signature.Parameters[FParameter].Start;
      FStyled[Index].ActiveStop := Signature.Parameters[FParameter].Stop;
    end;
  end;
end;

procedure TArgusSignatureHint.Place;
var
  Width, Height, Widest, Available, Index, Line, Row: Integer;
  Bounds, Area: TRect;
  Name, Text: string;
begin
  Prepare;
  Canvas.Font := Font;
  Available := Scale(MaxWidth) - 2 * Gap - Bar - 2;
  SetLength(FLayouts, Shown);
  SetLength(FFirstRows, Shown);
  Widest := 0;
  Row := 0;
  for Index := 0 to Shown - 1 do
  begin
    FLayouts[Index] := Layout(Index, Available);
    FFirstRows[Index] := Row;
    for Line := 0 to High(FLayouts[Index]) do
      Widest := Max(Widest, FStyled[Index].Width(Canvas, FLayouts[Index][Line].X, FLayouts[Index][Line].Y) +
        IfThen(Line > 0, Indent));
    Inc(Row, Length(FLayouts[Index]));
  end;
  // Die Doku-Zeile verbreitert den Hint höchstens bis zur Maximalbreite.
  if ParameterDoc(Name, Text) then
  begin
    Canvas.Font := Font;
    Canvas.Font.Style := [fsBold];
    Width := Canvas.TextWidth(Name) + Scale(8);
    Canvas.Font := UIFont;
    Widest := Max(Widest, Min(Width + Canvas.TextWidth(Text), Available));
  end;
  Canvas.Font := Font;
  Width := Min(Widest + 2 * Gap + Bar + 2, Scale(MaxWidth));
  Height := 2 * Pad + TotalRows * LineHeight;
  if HasDocLine then
    Inc(Height, DocHeight);
  if TooMany then
    BorderColor := Colors.Error
  else
    BorderColor := Colors.Accent;
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
  FStyled := nil;
  FLayouts := nil;
  FFirstRows := nil;
end;

procedure TArgusSignatureHint.PaintDocLine(ATop: Integer);
var
  Band, Part: TRect;
  Name, Text: string;
  X: Integer;
  Back, Fore: TArgusColor;
begin
  if TooMany then
  begin
    Back := Colors.ErrorSoft;
    Fore := Colors.Error;
  end
  else
  begin
    Back := Colors.Gutter;
    Fore := Colors.Muted;
  end;
  Band := Rect(0, ATop, ClientWidth, ClientHeight);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Back);
  Canvas.FillRect(Band);
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(0, ATop);
  Canvas.LineTo(ClientWidth, ATop);
  Canvas.Brush.Style := bsClear;
  X := Gap + Bar;
  Part := Rect(X, ATop + 1, ClientWidth - Gap, ClientHeight);
  if TooMany then
  begin
    Canvas.Font := UIFont;
    Canvas.Font.Color := ToColor(Fore);
    DrawText(Canvas.Handle, PChar(Format('Keine Überladung mit %d Parametern.', [FParameter + 1])), -1, Part,
      TextFlags or DT_END_ELLIPSIS);
  end
  else if ParameterDoc(Name, Text) then
  begin
    Canvas.Font := Font;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := ToColor(Colors.Accent);
    DrawText(Canvas.Handle, PChar(Name), -1, Part, TextFlags or DT_END_ELLIPSIS);
    Part.Left := Part.Left + Canvas.TextWidth(Name) + Scale(8);
    Canvas.Font := UIFont;
    Canvas.Font.Color := ToColor(Fore);
    DrawText(Canvas.Handle, PChar(Text), -1, Part, TextFlags or DT_END_ELLIPSIS);
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
end;

procedure TArgusSignatureHint.Paint;
var
  Row, Part: TRect;
  Height, Index, Line, RowIndex, Left, Right, X: Integer;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  if Length(FLayouts) = 0 then
  begin
    PaintBorder;
    Exit;
  end;
  Height := LineHeight;
  Left := Bar + Gap;
  Right := ClientWidth - Gap;
  RowIndex := 0;
  for Index := 0 to High(FLayouts) do
  begin
    // Akzentbalken links neben der gewählten Überladung.
    if Index = FSignature then
      FillRounded(Rect(Scale(3), Pad + RowIndex * Height + Scale(3), Scale(3) + Bar,
        Pad + (RowIndex + Length(FLayouts[Index])) * Height - Scale(3)), Colors.Accent, 1);
    for Line := 0 to High(FLayouts[Index]) do
    begin
      Row := Rect(Left, Pad + RowIndex * Height, Right, Pad + (RowIndex + 1) * Height);
      if Line > 0 then
        Inc(Row.Left, Indent);
      X := Row.Left;
      Canvas.Font := Font;
      FStyled[Index].Draw(Canvas, Colors, FLayouts[Index][Line].X, FLayouts[Index][Line].Y, X,
        Rect(Row.Left, Row.Top + Scale(2), Row.Right, Row.Bottom - Scale(2)), not Fits(Index), Scale(3));
      Inc(RowIndex);
    end;
  end;
  if Length(FHelp.Signatures) > MaxSignatures then
  begin
    Canvas.Font := UIFont;
    Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.Brush.Style := bsClear;
    Part := Rect(Left, Pad + RowIndex * Height, Right, Pad + (RowIndex + 1) * Height);
    DrawText(Canvas.Handle, PChar(Format('… %d weitere', [Length(FHelp.Signatures) - MaxSignatures])), -1, Part,
      TextFlags);
    Inc(RowIndex);
  end;
  if HasDocLine then
    PaintDocLine(Pad + RowIndex * Height + Pad);
  PaintBorder;
end;

procedure TArgusSignatureHint.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row, Index: Integer;
begin
  inherited;
  if (Button <> mbLeft) or not Assigned(FOnSelect) or (Y < Pad) then
    Exit;
  Row := (Y - Pad) div LineHeight;
  for Index := High(FFirstRows) downto 0 do
    if Row >= FFirstRows[Index] then
    begin
      if Row < FFirstRows[Index] + Length(FLayouts[Index]) then
        FOnSelect(Index);
      Exit;
    end;
end;

end.
