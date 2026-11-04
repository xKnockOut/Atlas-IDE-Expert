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
  Atlas.Core.Style.Color,
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
    procedure PaintCrumb;
    function LineHeight: Integer;
    function Fits(AIndex: Integer): Boolean;
    /// <summary>Keine Überladung hat so viele Parameter (#439).</summary>
    function TooMany: Boolean;
    function DocRowHeight: Integer;
    function HasDocLine: Boolean;
    function DocHeight: Integer;
    function Layout(AIndex, AAvailable: Integer): TArray<TPoint>;
    function TotalRows: Integer;
    procedure Prepare;
    /// <summary>Breite des Inhalts ohne Ränder, höchstens AAvailable für Doku-, Pfad- und Platzhalterzeile.
    /// </summary>
    function ContentWidth(AAvailable: Integer): Integer;
    procedure Place;
    /// <summary>Überschrift PARAMETER, Name und Beschreibung des aktiven Parameters und die Beschreibung der
    /// Methode ab APart; APart steht danach auf der letzten gezeichneten Zeile.</summary>
    procedure PaintParameterDoc(var APart: TRect; ARow: Integer; AFore: TAtlasColor);
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
  Atlas.UI.Strings,
  Atlas.UI.Popup.Accessibility;

const
  TextFlags = DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX;
  /// <summary>Logische Bildpunkte bei 96 dpi: Rand oben und unten, Abstand links und rechts, Einzug der
  /// Folgezeilen, Breite des Akzentbalkens.</summary>
  cPad = 4;
  cGap = 10;
  cIndent = 24;
  cBar = 3;

/// <summary>Gezeigte Überladungen: höchstens MaxSignatures.</summary>
function ShownCount(const AHelp: TAtlasSignatureHelp): Integer;
begin
  Result := Min(Length(AHelp.Signatures), TAtlasSignatureHint.MaxSignatures);
end;

/// <summary>Standardwert hinter „=“ im Parametertext, '' ohne.</summary>
function DefaultValueOf(const AText: string): string;
begin
  Result := '';
  if Pos('=', AText) > 0 then
  begin
    Result := Trim(Copy(AText, Pos('=', AText) + 1, MaxInt));
  end;
end;

/// <summary>Name aus dem Parametertext: ohne Standardwert, Typ und Modifizierer („const S: string = ''“ → „S“).
/// </summary>
function ParameterNameOf(const AText: string): string;
begin
  Result := Trim(AText);
  if Pos('=', Result) > 0 then
  begin
    Result := Trim(Copy(Result, 1, Pos('=', Result) - 1));
  end;
  if Pos(':', Result) > 0 then
  begin
    Result := Trim(Copy(Result, 1, Pos(':', Result) - 1));
  end;
  if LastDelimiter(' ', Result) > 0 then
  begin
    Result := Copy(Result, LastDelimiter(' ', Result) + 1, MaxInt);
  end;
end;

/// <summary>Beschreibung eines Parameters mit „optional, Standard …“; ADocumented = False ohne &lt;param&gt;
/// (der Text ist dann „nicht dokumentiert“).</summary>
function ParameterTextOf(const ADocumentation, ADefault: string; out ADocumented: Boolean): string;
begin
  Result := Trim(StringReplace(StringReplace(ADocumentation, #13, '', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  ADocumented := Result <> '';
  if not ADocumented then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.DocUndocumented);
  end;
  if ADefault <> '' then
  begin
    Result := Result + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.OptionalDefault, [ADefault]);
  end;
end;

/// <summary>Name und Beschreibung des aktiven Parameters AParameter der Überladung ASignature; False ohne
/// aktiven Parameter.</summary>
function ParameterDocOf(const AHelp: TAtlasSignatureHelp; ASignature, AParameter: Integer;
  out AName, AText: string; out ADocumented: Boolean): Boolean;
var
  mSignature: TAtlasSignature;
  mText: string;
begin
  AName := '';
  AText := '';
  ADocumented := False;
  Result := (ASignature >= 0) and (ASignature <= High(AHelp.Signatures));
  if not Result then
  begin
    Exit;
  end;
  mSignature := AHelp.Signatures[ASignature];
  Result := (AParameter >= 0) and (AParameter <= High(mSignature.Parameters));
  if not Result then
  begin
    Exit;
  end;
  mText := mSignature.Parameters[AParameter].Text(mSignature.Label_);
  AName := ParameterNameOf(mText);
  AText := ParameterTextOf(mSignature.Parameters[AParameter].Documentation, DefaultValueOf(mText), ADocumented);
end;

/// <summary>Beschreibung der Überladung ASignature in einer Zeile (nur der erste Absatz); '' ohne.</summary>
function SummaryOf(const AHelp: TAtlasSignatureHelp; ASignature: Integer): string;
var
  mText: string;
begin
  Result := '';
  if (ASignature < 0) or (ASignature > High(AHelp.Signatures)) then
  begin
    Exit;
  end;
  mText := StringReplace(AHelp.Signatures[ASignature].Documentation, #13, '', [rfReplaceAll]);
  // Nur der erste Absatz: Die Zeile soll die Methode kurz nennen.
  if Pos(#10#10, mText) > 0 then
  begin
    mText := Copy(mText, 1, Pos(#10#10, mText) - 1);
  end;
  Result := Trim(StringReplace(mText, #10, ' ', [rfReplaceAll]));
end;

/// <summary>Teile der Pfadzeile (#438): höchstens drei Ebenen samt dem gezeigten Aufruf, darüber „…“.</summary>
function CrumbPartsOf(const AOuter: TArray<string>; const ACallName: string): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  if Length(AOuter) > 2 then
  begin
    Result := Result + ['…'];
  end;
  for mIndex := Max(0, Length(AOuter) - 2) to High(AOuter) do
  begin
    if AOuter[mIndex] <> '' then
    begin
      Result := Result + [AOuter[mIndex]];
    end
    else
    begin
      Result := Result + ['…'];
    end;
  end;
  if ACallName <> '' then
  begin
    Result := Result + [ACallName];
  end
  else
  begin
    Result := Result + ['…'];
  end;
end;

/// <summary>Lage des Hints: unter (bzw. mit AAbove über) der Zeile AAnchor, passt er dort nicht in AArea, auf
/// der anderen Seite; rechts nicht über den Rand.</summary>
function PopupBounds(const AAnchor, AArea: TRect; AAbove: Boolean; AWidth, AHeight: Integer): TRect;
begin
  if AAbove then
  begin
    Result := TRect.Create(Point(AAnchor.Left, AAnchor.Top - AHeight - 2), AWidth, AHeight);
  end
  else
  begin
    Result := TRect.Create(Point(AAnchor.Left, AAnchor.Bottom + 2), AWidth, AHeight);
  end;
  if Result.Bottom > AArea.Bottom then
  begin
    Result.SetLocation(Result.Left, AAnchor.Top - AHeight - 2);
  end;
  if Result.Top < AArea.Top then
  begin
    Result.SetLocation(Result.Left, AAnchor.Bottom + 2);
  end;
  if Result.Right > AArea.Right then
  begin
    Result.SetLocation(Max(AArea.Left, AArea.Right - AWidth), Result.Top);
  end;
end;

{ TAtlasSignatureHint }

function TAtlasSignatureHint.LineHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg') + Scale(6);
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

function TAtlasSignatureHint.FormatText: string;
begin
  Result := TAtlasStrings.SignatureFormatLine(FFormatLine);
end;

function TAtlasSignatureHint.HasDocLine: Boolean;
var
  mName, mText: string;
  Documented: Boolean;
begin
  Result := TooMany or ParameterDocOf(FHelp, FSignature, FParameter, mName, mText, Documented) or
    (FormatText <> '');
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
    if SummaryOf(FHelp, FSignature) <> '' then
    begin
      Inc(Rows);
    end;
  end;
  // Platzhalter-Zeile (#451) oben; ohne Parameter-Doku steht sie allein.
  if FormatText <> '' then
  begin
    Inc(Rows);
    if not TooMany and not ParameterDocOf(FHelp, FSignature, FParameter, Name, Text, Documented) then
    begin
      Rows := 1;
    end;
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
  begin
    if (Label_[Index] = ';') and (Label_[Index + 1] = ' ') then
    begin
      Breaks := Breaks + [Index + 1];
    end;
  end;
  Breaks := Breaks + [Length(Label_)];
  Result := nil;
  LineStart := 0;
  Last := -1;
  Canvas.Font := Font;
  for Candidate in Breaks do
  begin
    if Length(Result) = 0 then
    begin
      Limit := AAvailable;
    end
    else
    begin
      Limit := AAvailable - Scale(cIndent);
    end;
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
  begin
    Inc(Result, Length(Lines));
  end;
  if Length(FHelp.Signatures) > MaxSignatures then
  begin
    Inc(Result);
  end;
end;

procedure TAtlasSignatureHint.Prepare;
var
  Index: Integer;
  Signature: TAtlasSignature;
  Range: TPoint;
begin
  // Eingefärbte Labels; aktiver Parameter nur in passenden Überladungen, Fläche nur in der gewählten.
  SetLength(FStyled, ShownCount(FHelp));
  for Index := 0 to ShownCount(FHelp) - 1 do
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
      begin
        if (Range.X >= FStyled[Index].ActiveStart) and (Range.X < FStyled[Index].ActiveStop) then
        begin
          FStyled[Index].ActiveStop := Range.X;
        end;
      end;
    end;
  end;
end;

procedure TAtlasSignatureHint.MoveTo(const AAnchor: TRect);
begin
  FAnchor := AAnchor;
  if IsShown then
  begin
    Place;
  end;
end;

function TAtlasSignatureHint.ContentWidth(AAvailable: Integer): Integer;
var
  mIndex, mLine, mRow, mNameWidth: Integer;
  mName, mText: string;
  mDocumented: Boolean;
begin
  Canvas.Font := Font;
  Result := 0;
  mRow := 0;
  for mIndex := 0 to ShownCount(FHelp) - 1 do
  begin
    FLayouts[mIndex] := Layout(mIndex, AAvailable);
    FFirstRows[mIndex] := mRow;
    for mLine := 0 to High(FLayouts[mIndex]) do
    begin
      Result := Max(Result, FStyled[mIndex].Width(Canvas, FLayouts[mIndex][mLine].X, FLayouts[mIndex][mLine].Y) +
        IfThen(mLine > 0, Scale(cIndent)));
    end;
    Inc(mRow, Length(FLayouts[mIndex]));
  end;
  // Die Doku-Zeile verbreitert den Hint höchstens bis zur Maximalbreite.
  if ParameterDocOf(FHelp, FSignature, FParameter, mName, mText, mDocumented) then
  begin
    Canvas.Font := Font;
    Canvas.Font.Style := [fsBold];
    mNameWidth := Canvas.TextWidth(mName) + Scale(8);
    Canvas.Font := UIFont;
    Result := Max(Result, Min(mNameWidth + Canvas.TextWidth(mText), AAvailable));
    Result := Max(Result, Min(Canvas.TextWidth(SummaryOf(FHelp, FSignature)), AAvailable));
  end;
  if CrumbHeight > 0 then
  begin
    Canvas.Font := Font;
    Result := Max(Result, Min(Canvas.TextWidth(String.Join(' › ', CrumbPartsOf(FOuter, FCallName))), AAvailable));
  end;
  if FormatText <> '' then
  begin
    Canvas.Font := UIFont;
    Result := Max(Result, Min(Canvas.TextWidth(FormatText), AAvailable));
  end;
  Canvas.Font := Font;
end;

procedure TAtlasSignatureHint.Place;
var
  mWidth, mHeight, mAvailable: Integer;
begin
  Prepare;
  mAvailable := Scale(MaxWidth) - 2 * Scale(cGap) - Scale(cBar) - 2;
  SetLength(FLayouts, ShownCount(FHelp));
  SetLength(FFirstRows, ShownCount(FHelp));
  mWidth := Min(ContentWidth(mAvailable) + 2 * Scale(cGap) + Scale(cBar) + 2, Scale(MaxWidth));
  mHeight := CrumbHeight + 2 * Scale(cPad) + TotalRows * LineHeight;
  if HasDocLine then
  begin
    Inc(mHeight, DocHeight);
  end;
  if TooMany then
  begin
    BorderColor := Colors.Error;
  end
  else
  begin
    BorderColor := Colors.Accent;
  end;
  ShowAt(PopupBounds(FAnchor, WorkAreaAt(FAnchor.TopLeft), FAbove, mWidth, mHeight));
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
    begin
      FFormatLine := TAtlasSignatureFormats.Line(AHelp.Format, AHelp.Format.ActiveArgument);
    end
    else
    begin
      FFormatLine := TAtlasSignatureFormats.Line(AHelp.Format, -1);
    end;
  end;
  Place;
  // Sprachausgabe (#447): Signatur und aktueller Parameter.
  SetAccessible(UiaToolTipControlType, TAtlasStrings.Text(TAtlasTextId.AccessSignature));
  GuardFeature := TAtlasFeature.Signature;
  Spoken := AHelp.Signatures[ASignature].Label_;
  if (AParameter >= 0) and (AParameter <= High(AHelp.Signatures[ASignature].Parameters)) then
  begin
    Spoken := Spoken + '. ' + TAtlasStrings.Fmt(TAtlasTextId.AccessParameter, [AParameter + 1,
      AHelp.Signatures[ASignature].Parameters[AParameter].Text(AHelp.Signatures[ASignature].Label_)]);
  end;
  if FormatText <> '' then
  begin
    Spoken := Spoken + '. ' + FormatText;
  end;
  Announce(Spoken);
end;

procedure TAtlasSignatureHint.SetPath(const AOuter: TArray<string>; const ACallName: string);
begin
  FOuter := AOuter;
  FCallName := ACallName;
end;

function TAtlasSignatureHint.CrumbHeight: Integer;
begin
  if Length(FOuter) = 0 then
  begin
    Exit(0);
  end;
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg') + Scale(8);
end;

procedure TAtlasSignatureHint.PaintCrumb;
var
  Band, Part: TRect;
  Parts: TArray<string>;
  Index, X: Integer;
  mText: string;
begin
  if CrumbHeight = 0 then
  begin
    Exit;
  end;
  Band := Rect(0, 0, ClientWidth, CrumbHeight);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Gutter);
  Canvas.FillRect(Band);
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(0, Band.Bottom - 1);
  Canvas.LineTo(ClientWidth, Band.Bottom - 1);
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  Parts := CrumbPartsOf(FOuter, FCallName);
  X := Scale(cGap) + Scale(cBar);
  for Index := 0 to High(Parts) do
  begin
    // Äußere Aufrufe gedämpft, der gezeigte in Textfarbe.
    if Index = High(Parts) then
    begin
      Canvas.Font.Color := ToColor(Colors.Text);
    end
    else
    begin
      Canvas.Font.Color := ToColor(Colors.Muted);
    end;
    mText := Parts[Index];
    if Index < High(Parts) then
    begin
      mText := mText + ' › ';
    end;
    Part := Rect(X, Band.Top, ClientWidth - Scale(cGap), Band.Bottom - 1);
    DrawText(Canvas.Handle, PChar(mText), -1, Part, TextFlags or DT_END_ELLIPSIS);
    Inc(X, Canvas.TextWidth(mText));
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

procedure TAtlasSignatureHint.PaintParameterDoc(var APart: TRect; ARow: Integer; AFore: TAtlasColor);
var
  mName, mText, mSummary, mHeading: string;
  mLeft, mRuleY: Integer;
  mDocumented: Boolean;
begin
  if not ParameterDocOf(FHelp, FSignature, FParameter, mName, mText, mDocumented) then
  begin
    Exit;
  end;
  mLeft := APart.Left;
  // Überschrift in Kapitälchen mit Linie bis zum Rand, wie in Tooltip und Detailpanel.
  mHeading := TAtlasStrings.Text(TAtlasTextId.DocParams);
  Canvas.Font := UIFont;
  Canvas.Font.Height := MulDiv(UIFont.Height, 85, 100);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(Colors.Muted);
  DrawText(Canvas.Handle, PChar(mHeading), -1, APart, TextFlags or DT_END_ELLIPSIS);
  mRuleY := (APart.Top + APart.Bottom) div 2;
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(APart.Left + Canvas.TextWidth(mHeading) + Scale(8), mRuleY);
  Canvas.LineTo(APart.Right, mRuleY);
  OffsetRect(APart, 0, ARow);
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(Colors.Accent);
  DrawText(Canvas.Handle, PChar(mName), -1, APart, TextFlags or DT_END_ELLIPSIS);
  APart.Left := APart.Left + Canvas.TextWidth(mName) + Scale(8);
  Canvas.Font := UIFont;
  if mDocumented then
  begin
    Canvas.Font.Color := ToColor(Colors.Text);
  end
  else
  begin
    Canvas.Font.Style := [fsItalic];
    Canvas.Font.Color := ToColor(Colors.Muted);
  end;
  DrawText(Canvas.Handle, PChar(mText), -1, APart, TextFlags or DT_END_ELLIPSIS);
  mSummary := SummaryOf(FHelp, FSignature);
  if mSummary <> '' then
  begin
    APart.Left := mLeft;
    OffsetRect(APart, 0, ARow);
    Canvas.Font := UIFont;
    Canvas.Font.Color := ToColor(AFore);
    DrawText(Canvas.Handle, PChar(mSummary), -1, APart, TextFlags or DT_END_ELLIPSIS);
  end;
end;

procedure TAtlasSignatureHint.PaintDocLine(ATop: Integer);
var
  Band, Part: TRect;
  X, Row: Integer;
  Back, Fore: TAtlasColor;
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
  X := Scale(cGap) + Scale(cBar);
  Row := DocRowHeight;
  Part := Rect(X, ATop + Scale(4), ClientWidth - Scale(cGap), ATop + Scale(4) + Row);
  // Platzhalter (#451) zuerst: Problem in Fehlerfarbe, sonst Akzent.
  if FormatText <> '' then
  begin
    Canvas.Font := UIFont;
    if FFormatLine.IsError then
    begin
      Canvas.Font.Color := ToColor(Colors.Error);
    end
    else
    begin
      Canvas.Font.Color := ToColor(Colors.Accent);
    end;
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
  else
  begin
    PaintParameterDoc(Part, Row, Fore);
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
end;

procedure TAtlasSignatureHint.Paint;
var
  Row, Part: TRect;
  mHeight, Index, Line, RowIndex, mLeft, Right, X, mTop: Integer;
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
  mHeight := LineHeight;
  mLeft := Scale(cBar) + Scale(cGap);
  Right := ClientWidth - Scale(cGap);
  RowIndex := 0;
  PaintCrumb;
  mTop := CrumbHeight + Scale(cPad);
  for Index := 0 to High(FLayouts) do
  begin
    // Akzentbalken links neben der gewählten Überladung.
    if Index = FSignature then
    begin
      FillRounded(Rect(Scale(3), mTop + RowIndex * mHeight + Scale(3), Scale(3) + Scale(cBar),
        mTop + (RowIndex + Length(FLayouts[Index])) * mHeight - Scale(3)), Colors.Accent, 1);
    end;
    for Line := 0 to High(FLayouts[Index]) do
    begin
      Row := Rect(mLeft, mTop + RowIndex * mHeight, Right, mTop + (RowIndex + 1) * mHeight);
      if Line > 0 then
      begin
        Inc(Row.Left, Scale(cIndent));
      end;
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
    Part := Rect(mLeft, mTop + RowIndex * mHeight, Right, mTop + (RowIndex + 1) * mHeight);
    DrawText(Canvas.Handle, PChar(TAtlasStrings.Fmt(TAtlasTextId.MoreOverloads, [Length(FHelp.Signatures) - MaxSignatures])), -1, Part,
      TextFlags);
    Inc(RowIndex);
  end;
  if HasDocLine then
  begin
    PaintDocLine(mTop + RowIndex * mHeight + Scale(cPad));
  end;
  PaintBorder;
end;

procedure TAtlasSignatureHint.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row, Index: Integer;
begin
  inherited;
  if (Button <> mbLeft) or not Assigned(FOnSelect) or (Y < CrumbHeight + Scale(cPad)) then
  begin
    Exit;
  end;
  Row := (Y - CrumbHeight - Scale(cPad)) div LineHeight;
  for Index := High(FFirstRows) downto 0 do
  begin
    if Row >= FFirstRows[Index] then
    begin
      if Row < FFirstRows[Index] + Length(FLayouts[Index]) then
      begin
        FOnSelect(Index);
      end;
      Exit;
    end;
  end;
end;

end.
