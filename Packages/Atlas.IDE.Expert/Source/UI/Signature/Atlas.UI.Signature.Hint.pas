unit Atlas.UI.Signature.Hint;

// Parameter-Hint (#436, #437, #439, #440): Fenster ohne Fokus mit allen
// Überladungen des Aufrufs untereinander (Wunsch aus dem Test in der IDE, statt "‹ 1 / 3 ›").
//   - Signaturen in der Editorschrift, eingefärbt wie im Entwurf (#411).
//   - Die gewählte Überladung hat links einen Akzentbalken; ihr aktiver Parameter
//     steht halbfett in Akzentfarbe auf einer Akzentfläche.
//   - In den übrigen passenden Überladungen ist der aktive Parameter halbfett;
//     Überladungen mit zu wenigen Parametern sind gedämpft.
//   - Darunter auf abgesetzter Fläche (#770) unter der Überschrift PARAMETER Name
//     und Beschreibung des aktiven Parameters, ohne <param> „nicht dokumentiert“
//     (kursiv, gedämpft), dann gedämpft die Beschreibung der Methode; Standardwerte
//     (#441) gedämpft, die Pille endet davor, dahinter "optional, Standard 1".
//   - Erlaubt keine Überladung so viele Argumente: Rahmen und untere Zeile in
//     Fehlerfarbe, "Keine Überladung mit n Parametern." (#439).
//   - Verschachtelte Aufrufe (#438): Pfadzeile oben mit den äußeren Aufrufen,
//     "ShowMessage › Format"; höchstens drei Ebenen, darüber "… ›".
//   - Klick auf eine Überladung wählt sie; Alt+↑/↓ über die Tastatur (Atlas.IDE).
//   - Formatroutinen (#451): Oben in der Doku-Fläche eine Zeile zum Platzhalter des
//     Arguments am Cursor („Platzhalter 2 von 2 erwartet ganzzahlig“) in Akzentfarbe,
//     ein Problem (überzähliges Argument, Typkonflikt, ungültiger Platzhalter) in
//     Fehlerfarbe. Abschaltbar mit completion.formatPlaceholders (FormatPlaceholders).
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
  Atlas.Core.Signature.Contract,
  Atlas.Core.Signature.Controller,
  Atlas.Core.Signature.Format,
  Atlas.UI.Popup.Window,
  Atlas.UI.Popup.Styled;

type
  TAtlasIndexEvent = reference to procedure(AIndex: Integer);

  TAtlasSignatureHint = class(TAtlasPopupWindow, IAtlasSignatureView)
  public const
    MaxWidth = 520;
    /// <summary>Mehr Überladungen werden nicht gezeigt; eine Zeile nennt den Rest.</summary>
    MaxSignatures = 12;
  private
    FHelp: TAtlasSignatureHelp;
    FSignature: Integer;
    FParameter: Integer;
    FAnchor: TRect;
    FAbove: Boolean;
    FOnSelect: TAtlasIndexEvent;
    /// <summary>Je gezeigter Überladung ihr eingefärbtes Label.</summary>
    FStyled: TArray<TAtlasStyledText>;
    /// <summary>Je gezeigter Überladung ihre Zeilen als Bereiche im Label (0-basiert, Stop exklusiv).</summary>
    FLayouts: TArray<TArray<TPoint>>;
    /// <summary>Erste Zeile jeder gezeigten Überladung (für Mausklicks).</summary>
    FFirstRows: TArray<Integer>;
    FOuter: TArray<string>;
    FCallName: string;
    FFormatPlaceholders: Boolean;
    /// <summary>Zeile der Platzhalter (#451), Kind = None ohne.</summary>
    FFormatLine: TAtlasFormatLine;
    function FormatText: string;
    function CrumbHeight: Integer;
    function CrumbParts: TArray<string>;
    procedure PaintCrumb;
    function LineHeight: Integer;
    function Pad: Integer;
    function Gap: Integer;
    function Indent: Integer;
    function Bar: Integer;
    function Shown: Integer;
    function Fits(AIndex: Integer): Boolean;
    /// <summary>Keine Überladung hat so viele Parameter (#439).</summary>
    function TooMany: Boolean;
    /// <summary>Name und Beschreibung des aktiven Parameters der gewählten Überladung; ADocumented = False
    /// ohne &lt;param&gt; (AText ist dann „nicht dokumentiert“). False ohne aktiven Parameter.</summary>
    function ParameterDoc(out AName, AText: string; out ADocumented: Boolean): Boolean;
    /// <summary>Beschreibung der gewählten Überladung in einer Zeile; '' ohne.</summary>
    function SummaryText: string;
    function DocRowHeight: Integer;
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
    { IAtlasSignatureView }
    procedure ShowSignature(const AHelp: TAtlasSignatureHelp; ASignature, AParameter: Integer);
    procedure HideSignature;
    /// <summary>Neue Lage der Zeile (z. B. nach dem Scrollen, #414); ein offener Hint wandert mit.</summary>
    procedure MoveTo(const AAnchor: TRect);
    /// <summary>Rechteck der Zeile an der öffnenden Klammer in Bildschirmkoordinaten.</summary>
    property Anchor: TRect read FAnchor write FAnchor;
    /// <summary>Über der Zeile statt darunter (Vervollständigung offen, #440).</summary>
    property Above: Boolean read FAbove write FAbove;
    /// <summary>Pfad für verschachtelte Aufrufe (#438): äußere Aufrufe (äußerster zuerst) und der Name des
    /// gezeigten Aufrufs; vor ShowSignature setzen.</summary>
    procedure SetPath(const AOuter: TArray<string>; const ACallName: string);
    /// <summary>Klick auf eine Überladung.</summary>
    property OnSelect: TAtlasIndexEvent read FOnSelect write FOnSelect;
    /// <summary>Zeile der Platzhalter von Format zeigen (#451); vor ShowSignature setzen.</summary>
    property FormatPlaceholders: Boolean read FFormatPlaceholders write FFormatPlaceholders;
    /// <summary>Zum Testen: die gezeigte Zeile der Platzhalter.</summary>
    property FormatLine: TAtlasFormatLine read FFormatLine;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  Atlas.Core.Style.Color,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Accessibility;

const
  TextFlags = DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX;

{ TAtlasSignatureHint }

function TAtlasSignatureHint.LineHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg') + Scale(6);
end;

function TAtlasSignatureHint.Pad: Integer;
begin
  Result := Scale(4);
end;

function TAtlasSignatureHint.Gap: Integer;
begin
  Result := Scale(10);
end;

function TAtlasSignatureHint.Indent: Integer;
begin
  Result := Scale(24);
end;

function TAtlasSignatureHint.Bar: Integer;
begin
  Result := Scale(3);
end;

function TAtlasSignatureHint.Shown: Integer;
begin
  Result := Min(Length(FHelp.Signatures), MaxSignatures);
end;

function TAtlasSignatureHint.Fits(AIndex: Integer): Boolean;
begin
  // Wie im Controller nach der Anzahl.
  Result := TAtlasSignatureController.CountFits(FHelp.Signatures[AIndex], FParameter);
end;

function TAtlasSignatureHint.TooMany: Boolean;
begin
  Result := TAtlasSignatureController.TooManyArguments(FHelp, FParameter);
end;

function TAtlasSignatureHint.ParameterDoc(out AName, AText: string; out ADocumented: Boolean): Boolean;
var
  Signature: TAtlasSignature;
  Parameter: TAtlasSignatureParameter;
  Default: string;
begin
  AName := '';
  AText := '';
  ADocumented := False;
  Result := False;
  if (FSignature < 0) or (FSignature > High(FHelp.Signatures)) then
    Exit;
  Signature := FHelp.Signatures[FSignature];
  if (FParameter < 0) or (FParameter > High(Signature.Parameters)) then
    Exit;
  Parameter := Signature.Parameters[FParameter];
  Default := Parameter.Text(Signature.Label_);
  if Pos('=', Default) > 0 then
    Default := Trim(Copy(Default, Pos('=', Default) + 1, MaxInt))
  else
    Default := '';
  AName := Trim(Parameter.Text(Signature.Label_));
  if Pos('=', AName) > 0 then
    AName := Trim(Copy(AName, 1, Pos('=', AName) - 1));
  if Pos(':', AName) > 0 then
    AName := Trim(Copy(AName, 1, Pos(':', AName) - 1));
  // "const S" → "S"
  if LastDelimiter(' ', AName) > 0 then
    AName := Copy(AName, LastDelimiter(' ', AName) + 1, MaxInt);
  AText := Trim(StringReplace(StringReplace(Parameter.Documentation, #13, '', [rfReplaceAll]), #10, ' ',
    [rfReplaceAll]));
  ADocumented := AText <> '';
  if not ADocumented then
    AText := TAtlasStrings.Text(TAtlasTextId.DocUndocumented);
  if Default <> '' then
    if AText <> '' then
      AText := AText + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.OptionalDefault, [Default])
    else
      AText := TAtlasStrings.Fmt(TAtlasTextId.OptionalDefault, [Default]);
  Result := True;
end;

function TAtlasSignatureHint.SummaryText: string;
var
  Text: string;
begin
  Result := '';
  if (FSignature < 0) or (FSignature > High(FHelp.Signatures)) then
    Exit;
  Text := StringReplace(FHelp.Signatures[FSignature].Documentation, #13, '', [rfReplaceAll]);
  // Nur der erste Absatz: Die Zeile soll die Methode kurz nennen.
  if Pos(#10#10, Text) > 0 then
    Text := Copy(Text, 1, Pos(#10#10, Text) - 1);
  Result := Trim(StringReplace(Text, #10, ' ', [rfReplaceAll]));
end;

function TAtlasSignatureHint.FormatText: string;
begin
  Result := TAtlasStrings.SignatureFormatLine(FFormatLine);
end;

function TAtlasSignatureHint.HasDocLine: Boolean;
var
  Name, Text: string;
  Documented: Boolean;
begin
  Result := TooMany or ParameterDoc(Name, Text, Documented) or (FormatText <> '');
end;

function TAtlasSignatureHint.DocRowHeight: Integer;
begin
  Canvas.Font := UIFont;
  Result := Canvas.TextHeight('Wg') + Scale(4);
  Canvas.Font := Font;
end;

function TAtlasSignatureHint.DocHeight: Integer;
var
  Rows: Integer;
  Name, Text: string;
  Documented: Boolean;
begin
  // Fehlerzeile allein; sonst Überschrift, Parameter und ggf. die Beschreibung der Methode.
  Rows := 1;
  if not TooMany then
  begin
    Rows := 2;
    if SummaryText <> '' then
      Inc(Rows);
  end;
  // Platzhalter-Zeile (#451) oben; ohne Parameter-Doku steht sie allein.
  if FormatText <> '' then
  begin
    Inc(Rows);
    if not TooMany and not ParameterDoc(Name, Text, Documented) then
      Rows := 1;
  end;
  Result := Rows * DocRowHeight + Scale(8);
end;

function TAtlasSignatureHint.Layout(AIndex, AAvailable: Integer): TArray<TPoint>;
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

function TAtlasSignatureHint.TotalRows: Integer;
var
  Lines: TArray<TPoint>;
begin
  Result := 0;
  for Lines in FLayouts do
    Inc(Result, Length(Lines));
  if Length(FHelp.Signatures) > MaxSignatures then
    Inc(Result);
end;

procedure TAtlasSignatureHint.Prepare;
var
  Index: Integer;
  Signature: TAtlasSignature;
  Range: TPoint;
begin
  // Eingefärbte Labels; aktiver Parameter nur in passenden Überladungen, Fläche nur in der gewählten.
  SetLength(FStyled, Shown);
  for Index := 0 to Shown - 1 do
  begin
    Signature := FHelp.Signatures[Index];
    FStyled[Index] := TAtlasStyledText.Create(Signature.Label_);
    FStyled[Index].ActiveFill := Index = FSignature;
    if Fits(Index) and (FParameter >= 0) and (FParameter <= High(Signature.Parameters)) and
      (Signature.Parameters[FParameter].Start >= 0) and
      (Signature.Parameters[FParameter].Stop > Signature.Parameters[FParameter].Start) then
    begin
      FStyled[Index].ActiveStart := Signature.Parameters[FParameter].Start;
      FStyled[Index].ActiveStop := Signature.Parameters[FParameter].Stop;
      // Der Standardwert steht gedämpft hinter der Pille (#441).
      for Range in FStyled[Index].MutedRanges do
        if (Range.X >= FStyled[Index].ActiveStart) and (Range.X < FStyled[Index].ActiveStop) then
          FStyled[Index].ActiveStop := Range.X;
    end;
  end;
end;

procedure TAtlasSignatureHint.MoveTo(const AAnchor: TRect);
begin
  FAnchor := AAnchor;
  if IsShown then
    Place;
end;

procedure TAtlasSignatureHint.Place;
var
  Width, Height, Widest, Available, Index, Line, Row: Integer;
  Bounds, Area: TRect;
  Name, Text: string;
  Documented: Boolean;
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
  if ParameterDoc(Name, Text, Documented) then
  begin
    Canvas.Font := Font;
    Canvas.Font.Style := [fsBold];
    Width := Canvas.TextWidth(Name) + Scale(8);
    Canvas.Font := UIFont;
    Widest := Max(Widest, Min(Width + Canvas.TextWidth(Text), Available));
    Widest := Max(Widest, Min(Canvas.TextWidth(SummaryText), Available));
  end;
  if CrumbHeight > 0 then
  begin
    Canvas.Font := Font;
    Widest := Max(Widest, Min(Canvas.TextWidth(String.Join(' › ', CrumbParts)), Available));
  end;
  if FormatText <> '' then
  begin
    Canvas.Font := UIFont;
    Widest := Max(Widest, Min(Canvas.TextWidth(FormatText), Available));
  end;
  Canvas.Font := Font;
  Width := Min(Widest + 2 * Gap + Bar + 2, Scale(MaxWidth));
  Height := CrumbHeight + 2 * Pad + TotalRows * LineHeight;
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

procedure TAtlasSignatureHint.ShowSignature(const AHelp: TAtlasSignatureHelp; ASignature, AParameter: Integer);
var
  Spoken: string;
begin
  if (ASignature < 0) or (ASignature > High(AHelp.Signatures)) then
  begin
    HideSignature;
    Exit;
  end;
  FHelp := AHelp;
  FSignature := ASignature;
  FParameter := AParameter;
  // Platzhalter (#451): Eintrag am Cursor nur, solange der Cursor in der Liste steht.
  FFormatLine := Default(TAtlasFormatLine);
  if FFormatPlaceholders then
  begin
    if AParameter = AHelp.Format.ListParameter then
      FFormatLine := TAtlasSignatureFormats.Line(AHelp.Format, AHelp.Format.ActiveArgument)
    else
      FFormatLine := TAtlasSignatureFormats.Line(AHelp.Format, -1);
  end;
  Place;
  // Sprachausgabe (#447): Signatur und aktueller Parameter.
  SetAccessible(UiaToolTipControlType, TAtlasStrings.Text(TAtlasTextId.AccessSignature));
  GuardFeature := TAtlasFeature.Signature;
  Spoken := AHelp.Signatures[ASignature].Label_;
  if (AParameter >= 0) and (AParameter <= High(AHelp.Signatures[ASignature].Parameters)) then
    Spoken := Spoken + '. ' + TAtlasStrings.Fmt(TAtlasTextId.AccessParameter, [AParameter + 1,
      AHelp.Signatures[ASignature].Parameters[AParameter].Text(AHelp.Signatures[ASignature].Label_)]);
  if FormatText <> '' then
    Spoken := Spoken + '. ' + FormatText;
  Announce(Spoken);
end;

procedure TAtlasSignatureHint.SetPath(const AOuter: TArray<string>; const ACallName: string);
begin
  FOuter := AOuter;
  FCallName := ACallName;
end;

function TAtlasSignatureHint.CrumbParts: TArray<string>;
var
  Index: Integer;
begin
  // Höchstens drei Ebenen samt dem gezeigten Aufruf; darüber "…".
  Result := nil;
  if Length(FOuter) > 2 then
    Result := ['…'];
  for Index := Max(0, Length(FOuter) - 2) to High(FOuter) do
    if FOuter[Index] <> '' then
      Result := Result + [FOuter[Index]]
    else
      Result := Result + ['…'];
  if FCallName <> '' then
    Result := Result + [FCallName]
  else
    Result := Result + ['…'];
end;

function TAtlasSignatureHint.CrumbHeight: Integer;
begin
  if Length(FOuter) = 0 then
    Exit(0);
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg') + Scale(8);
end;

procedure TAtlasSignatureHint.PaintCrumb;
var
  Band, Part: TRect;
  Parts: TArray<string>;
  Index, X: Integer;
  Text: string;
begin
  if CrumbHeight = 0 then
    Exit;
  Band := Rect(0, 0, ClientWidth, CrumbHeight);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Gutter);
  Canvas.FillRect(Band);
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(0, Band.Bottom - 1);
  Canvas.LineTo(ClientWidth, Band.Bottom - 1);
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  Parts := CrumbParts;
  X := Gap + Bar;
  for Index := 0 to High(Parts) do
  begin
    // Äußere Aufrufe gedämpft, der gezeigte in Textfarbe.
    if Index = High(Parts) then
      Canvas.Font.Color := ToColor(Colors.Text)
    else
      Canvas.Font.Color := ToColor(Colors.Muted);
    Text := Parts[Index];
    if Index < High(Parts) then
      Text := Text + ' › ';
    Part := Rect(X, Band.Top, ClientWidth - Gap, Band.Bottom - 1);
    DrawText(Canvas.Handle, PChar(Text), -1, Part, TextFlags or DT_END_ELLIPSIS);
    Inc(X, Canvas.TextWidth(Text));
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasSignatureHint.HideSignature;
begin
  HidePopup;
  FHelp := Default(TAtlasSignatureHelp);
  FStyled := nil;
  FOuter := nil;
  FCallName := '';
  FLayouts := nil;
  FFirstRows := nil;
  FFormatLine := Default(TAtlasFormatLine);
end;

procedure TAtlasSignatureHint.PaintDocLine(ATop: Integer);
var
  Band, Part: TRect;
  Name, Text, Summary, Heading: string;
  X, Row, RuleY: Integer;
  Back, Fore: TAtlasColor;
  Documented: Boolean;
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
  Row := DocRowHeight;
  Part := Rect(X, ATop + Scale(4), ClientWidth - Gap, ATop + Scale(4) + Row);
  // Platzhalter (#451) zuerst: Problem in Fehlerfarbe, sonst Akzent.
  if FormatText <> '' then
  begin
    Canvas.Font := UIFont;
    if FFormatLine.IsError then
      Canvas.Font.Color := ToColor(Colors.Error)
    else
      Canvas.Font.Color := ToColor(Colors.Accent);
    DrawText(Canvas.Handle, PChar(FormatText), -1, Part, TextFlags or DT_END_ELLIPSIS);
    OffsetRect(Part, 0, Row);
  end;
  if TooMany then
  begin
    Canvas.Font := UIFont;
    Canvas.Font.Color := ToColor(Fore);
    DrawText(Canvas.Handle, PChar(TAtlasStrings.Fmt(TAtlasTextId.NoOverloadWith, [FParameter + 1])), -1, Part,
      TextFlags or DT_END_ELLIPSIS);
  end
  else if ParameterDoc(Name, Text, Documented) then
  begin
    // Überschrift in Kapitälchen mit Linie bis zum Rand, wie in Tooltip und Detailpanel.
    Heading := TAtlasStrings.Text(TAtlasTextId.DocParams);
    Canvas.Font := UIFont;
    Canvas.Font.Height := MulDiv(UIFont.Height, 85, 100);
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := ToColor(Colors.Muted);
    DrawText(Canvas.Handle, PChar(Heading), -1, Part, TextFlags or DT_END_ELLIPSIS);
    RuleY := (Part.Top + Part.Bottom) div 2;
    Canvas.Pen.Color := ToColor(Colors.Line);
    Canvas.MoveTo(Part.Left + Canvas.TextWidth(Heading) + Scale(8), RuleY);
    Canvas.LineTo(Part.Right, RuleY);
    OffsetRect(Part, 0, Row);
    Canvas.Font := Font;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := ToColor(Colors.Accent);
    DrawText(Canvas.Handle, PChar(Name), -1, Part, TextFlags or DT_END_ELLIPSIS);
    Part.Left := Part.Left + Canvas.TextWidth(Name) + Scale(8);
    Canvas.Font := UIFont;
    if Documented then
      Canvas.Font.Color := ToColor(Colors.Text)
    else
    begin
      Canvas.Font.Style := [fsItalic];
      Canvas.Font.Color := ToColor(Colors.Muted);
    end;
    DrawText(Canvas.Handle, PChar(Text), -1, Part, TextFlags or DT_END_ELLIPSIS);
    Summary := SummaryText;
    if Summary <> '' then
    begin
      Part.Left := X;
      OffsetRect(Part, 0, Row);
      Canvas.Font := UIFont;
      Canvas.Font.Color := ToColor(Fore);
      DrawText(Canvas.Handle, PChar(Summary), -1, Part, TextFlags or DT_END_ELLIPSIS);
    end;
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
end;

procedure TAtlasSignatureHint.Paint;
var
  Row, Part: TRect;
  Height, Index, Line, RowIndex, Left, Right, X, Top: Integer;
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
  PaintCrumb;
  Top := CrumbHeight + Pad;
  for Index := 0 to High(FLayouts) do
  begin
    // Akzentbalken links neben der gewählten Überladung.
    if Index = FSignature then
      FillRounded(Rect(Scale(3), Top + RowIndex * Height + Scale(3), Scale(3) + Bar,
        Top + (RowIndex + Length(FLayouts[Index])) * Height - Scale(3)), Colors.Accent, 1);
    for Line := 0 to High(FLayouts[Index]) do
    begin
      Row := Rect(Left, Top + RowIndex * Height, Right, Top + (RowIndex + 1) * Height);
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
    Part := Rect(Left, Top + RowIndex * Height, Right, Top + (RowIndex + 1) * Height);
    DrawText(Canvas.Handle, PChar(TAtlasStrings.Fmt(TAtlasTextId.MoreOverloads, [Length(FHelp.Signatures) - MaxSignatures])), -1, Part,
      TextFlags);
    Inc(RowIndex);
  end;
  if HasDocLine then
    PaintDocLine(Top + RowIndex * Height + Pad);
  PaintBorder;
end;

procedure TAtlasSignatureHint.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row, Index: Integer;
begin
  inherited;
  if (Button <> mbLeft) or not Assigned(FOnSelect) or (Y < CrumbHeight + Pad) then
    Exit;
  Row := (Y - CrumbHeight - Pad) div LineHeight;
  for Index := High(FFirstRows) downto 0 do
    if Row >= FFirstRows[Index] then
    begin
      if Row < FFirstRows[Index] + Length(FLayouts[Index]) then
        FOnSelect(Index);
      Exit;
    end;
end;

end.
