unit Atlas.UI.Completion.Details;

// Detailpanel der Vervollständigung (#424, #426, #427): kein eigenes Fenster,
// sondern der rechte (bzw. linke) Bereich des Popups, wie im Entwurf ein
// Rahmen mit Trennlinie. Inhalt von oben nach unten:
//   1. Tags: Sichtbarkeit und Direktiven als umrandete Marken, deprecated in Warnfarbe
//   2. Deklaration in der Editorschrift, eingefärbt, umbrechend
//   3. Unit · Klasse, gedämpft
//   4. Trennlinie
//   5. bei deprecated "Veraltet: …" in Warnfarbe
//   6. XMLDoc vollständig und formatiert (#654) wie im Hover-Tooltip:
//      Beschreibung, Parameter (Name in Akzentfarbe), Typparameter, Rückgabe
//      (→), Wert, Exceptions (!), Bemerkungen, Beispiel, Siehe auch. Ist das
//      Panel höher als das Popup, scrollt nur die Doku mit dem Mausrad. Text
//      lässt sich markieren; Verweise mit Strg+Klick und Links sind anklickbar.
//      Kurzform (hints.xmlDocFull aus): Beschreibung vier, Bemerkungen drei Zeilen.
// Bei Überladungen (#425) steht oben "Überladung ‹ 2 / 3 ›"; die Pfeile sind
// klickbar. Leere Abschnitte entfallen. Ohne Details (z. B. Schlüsselwort) steht
// ein gedämpfter Hinweis, damit das Popup beim Blättern nicht schmaler wird.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Documentation.Contract,
  Atlas.UI.Documentation.View,
  Atlas.UI.Popup.Styled;

type
  TAtlasDetailView = class
  public const
    DefaultWidth = 320;
  private
    FDetails: TAtlasItemDetails;
    FOverloadIndex: Integer;
    FOverloadCount: Integer;
    FPreviousRect: TRect;
    FNextRect: TRect;
    FDoc: TAtlasDocView;
    /// <summary>Doku für diese Breite gesetzt (0 = neu setzen).</summary>
    FDocWidth: Integer;
    FDocLeft: Integer;
    FDocTop: Integer;
    FMaxHeight: Integer;
    // Je Details einmal (P-15): Doku und eingefärbte Deklaration; Umbruch nur bei anderer Breite oder Schrift.
    FDocData: TAtlasDoc;
    FDecl: TAtlasStyledText;
    FDeclLines: TArray<TPoint>;
    FDeclKey: string;
    procedure SetDetails(const AValue: TAtlasItemDetails);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Doku der Details; bei fremden Servern aus Summary, Params, Returns, Exceptions, Remarks.</summary>
    class function DocOf(const ADetails: TAtlasItemDetails): TAtlasDoc; static;
    /// <summary>Doku in Fensterkoordinaten unter (AX, AY)?</summary>
    function InDoc(AX, AY: Integer): Boolean;
    /// <summary>Link der Doku unter (AX, AY) in Fensterkoordinaten; -1 ohne.</summary>
    function DocLinkAt(AX, AY: Integer): Integer;
    function ScrollDoc(ASteps: Integer): Boolean;
    property Doc: TAtlasDocView read FDoc;
    property DocLeft: Integer read FDocLeft;
    property DocTop: Integer read FDocTop;
    /// <summary>Höchste Höhe des Panels; darüber scrollt die Doku (0 = unbegrenzt).</summary>
    property MaxHeight: Integer read FMaxHeight write FMaxHeight;
    /// <summary>Zeichnet (ADraw) bzw. misst den Inhalt in ABounds; liefert die benötigte Höhe.
    /// APPI: Pixel je Zoll des Fensters; AFont: Editorschrift; AUIFont: Beschriftungen.</summary>
    function Render(ACanvas: TCanvas; const AColors: TAtlasColors; AFont, AUIFont: TFont; const ABounds: TRect;
      APPI: Integer; ADraw: Boolean): Integer;
    property Details: TAtlasItemDetails read FDetails write SetDetails;
    /// <summary>Gezeigte Überladung (0-basiert) und Anzahl; Anzahl 1 = keine Kopfzeile.</summary>
    property OverloadIndex: Integer read FOverloadIndex write FOverloadIndex;
    property OverloadCount: Integer read FOverloadCount write FOverloadCount;
    /// <summary>Klickflächen der Pfeile nach dem letzten Zeichnen (Fensterkoordinaten).</summary>
    property PreviousRect: TRect read FPreviousRect;
    property NextRect: TRect read FNextRect;
  end;

implementation

uses
  System.Math,
  Atlas.UI.Popup.Window,
  Atlas.UI.Popup.Draw,
  Atlas.Core.Documentation.Layout,
  Atlas.UI.Strings;

{ TAtlasDetailView }

constructor TAtlasDetailView.Create;
begin
  inherited Create;
  FDoc := TAtlasDocView.Create;
end;

destructor TAtlasDetailView.Destroy;
begin
  FDoc.Free;
  inherited Destroy;
end;

procedure TAtlasDetailView.SetDetails(const AValue: TAtlasItemDetails);
begin
  FDetails := AValue;
  FDocWidth := 0;
  FDocData := DocOf(AValue);
  FDecl := TAtlasStyledText.Create(AValue.Declaration);
  FDeclLines := nil;
  FDeclKey := '';
end;

class function TAtlasDetailView.DocOf(const ADetails: TAtlasItemDetails): TAtlasDoc;

  procedure Add(AKind: TAtlasDocSectionKind; const AName, AText: string);
  var
    Section: TAtlasDocSection;
  begin
    if Trim(AText) = '' then
      Exit;
    Section := Default(TAtlasDocSection);
    Section.Kind := AKind;
    Section.Name := AName;
    Section.Runs := TAtlasDoc.FromText(AText).Sections[0].Runs;
    Result.Sections := Result.Sections + [Section];
  end;

var
  Entry: TAtlasDocEntry;
begin
  Result := ADetails.Doc;
  if not Result.IsEmpty then
    Exit;
  Add(TAtlasDocSectionKind.Summary, '', ADetails.Summary);
  for Entry in ADetails.Params do
    Add(TAtlasDocSectionKind.Param, Entry.Name, Entry.Text);
  Add(TAtlasDocSectionKind.Returns, '', ADetails.Returns);
  for Entry in ADetails.Exceptions do
    Add(TAtlasDocSectionKind.Exception, Entry.Name, Entry.Text);
  Add(TAtlasDocSectionKind.Remarks, '', ADetails.Remarks);
end;

function TAtlasDetailView.InDoc(AX, AY: Integer): Boolean;
begin
  Result := not FDoc.IsEmpty and (AX >= FDocLeft) and (AX < FDocLeft + FDoc.Width) and (AY >= FDocTop) and
    (AY < FDocTop + FDoc.Height);
end;

function TAtlasDetailView.DocLinkAt(AX, AY: Integer): Integer;
begin
  Result := -1;
  if InDoc(AX, AY) then
    Result := FDoc.LinkAt(AX - FDocLeft, AY - FDocTop);
end;

function TAtlasDetailView.ScrollDoc(ASteps: Integer): Boolean;
begin
  Result := FDoc.ScrollBy(ASteps * FDoc.WheelStep);
end;

function TAtlasDetailView.Render(ACanvas: TCanvas; const AColors: TAtlasColors; AFont, AUIFont: TFont;
  const ABounds: TRect; APPI: Integer; ADraw: Boolean): Integer;
var
  Left, Y, Right, TagX, TagHeight, LineHeight, Fixed: Integer;
  Text, Tag, Key: string;
  Line, X: Integer;
  Box, Rect_: TRect;

  function Scale(AValue: Integer): Integer;
  begin
    Result := MulDiv(AValue, APPI, 96);
  end;

  procedure Frame(const ARect: TRect; ALine: TAtlasColor);
  begin
    ACanvas.Brush.Style := bsClear;
    ACanvas.Pen.Style := psSolid;
    ACanvas.Pen.Color := ToColor(ALine);
    ACanvas.RoundRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, Scale(2 * TAtlasDraw.ChipRadius),
      Scale(2 * TAtlasDraw.ChipRadius));
  end;

  /// <summary>Text in der UI-Schrift umbrechend ab Y; AMaxLines = 0 ohne Grenze.</summary>
  procedure Block(const AText: string; AColor: TAtlasColor; AStyle: TFontStyles; AMaxLines: Integer = 0);
  var
    Area: TRect;
  begin
    if AText = '' then
      Exit;
    ACanvas.Font := AUIFont;
    ACanvas.Font.Style := AStyle;
    ACanvas.Font.Color := ToColor(AColor);
    ACanvas.Brush.Style := bsClear;
    Area := Rect(Left, Y, Right, Y);
    DrawText(ACanvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
    Area.Right := Right;
    if AMaxLines > 0 then
      Area.Bottom := Min(Area.Bottom, Y + AMaxLines * ACanvas.TextHeight('Wg'));
    if ADraw then
      DrawText(ACanvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_END_ELLIPSIS);
    Y := Area.Bottom + Scale(6);
    ACanvas.Font.Style := [];
  end;

  procedure Separator;
  begin
    if ADraw then
      TAtlasDraw.Separator(ACanvas, Left, Right, Y + Scale(2), AColors.Line);
    Inc(Y, Scale(8));
  end;

begin
  Left := ABounds.Left + Scale(13);
  Right := ABounds.Right - Scale(13);
  Y := ABounds.Top + Scale(11);
  FPreviousRect := TRect.Empty;
  FNextRect := TRect.Empty;
  // Kopfzeile bei Überladungen (#425): "‹ 2 / 3 ›" rechtsbündig.
  if FOverloadCount > 1 then
  begin
    ACanvas.Font := AUIFont;
    LineHeight := ACanvas.TextHeight('Wg');
    Text := Format('%d / %d', [FOverloadIndex + 1, FOverloadCount]);
    X := Right - ACanvas.TextWidth('›') - Scale(4);
    FNextRect := Rect(X - Scale(4), Y - Scale(2), Right, Y + LineHeight + Scale(2));
    Dec(X, ACanvas.TextWidth(Text) + Scale(8));
    Rect_ := Rect(X, Y, X + ACanvas.TextWidth(Text), Y + LineHeight);
    Dec(X, ACanvas.TextWidth('‹') + Scale(8));
    FPreviousRect := Rect(X - Scale(4), Y - Scale(2), X + ACanvas.TextWidth('‹') + Scale(4),
      Y + LineHeight + Scale(2));
    if ADraw then
    begin
      ACanvas.Brush.Style := bsClear;
      ACanvas.Font.Color := ToColor(AColors.Muted);
      ACanvas.TextOut(Left, Y, TAtlasStrings.Text(TAtlasTextId.Overload));
      ACanvas.Font.Color := ToColor(AColors.Text);
      DrawText(ACanvas.Handle, PChar(Text), -1, Rect_, DT_SINGLELINE or DT_NOPREFIX);
      ACanvas.Font.Style := [fsBold];
      ACanvas.Font.Color := ToColor(AColors.Accent);
      ACanvas.TextOut(FPreviousRect.Left + Scale(4), Y, '‹');
      ACanvas.TextOut(FNextRect.Left + Scale(4), Y, '›');
      ACanvas.Font.Style := [];
    end;
    Inc(Y, LineHeight + Scale(8));
  end;
  if FDetails.IsEmpty then
  begin
    Block(TAtlasStrings.Text(TAtlasTextId.NoDetails), AColors.Muted, []);
    Exit(Y - ABounds.Top + Scale(5));
  end;
  // 1. Tags als umrandete Marken.
  if (FDetails.Visibility <> '') or (Length(FDetails.Directives) > 0) then
  begin
    ACanvas.Font := AUIFont;
    TagHeight := ACanvas.TextHeight('Wg') + Scale(2);
    TagX := Left;
    for Tag in [FDetails.Visibility] + FDetails.Directives do
    begin
      if Tag = '' then
        Continue;
      ACanvas.Font := AUIFont;
      Box := Rect(TagX, Y, TagX + ACanvas.TextWidth(Tag) + Scale(TAtlasDraw.ChipPad), Y + TagHeight);
      if ADraw then
      begin
        if Tag = 'deprecated' then
        begin
          Frame(Box, AColors.Warn);
          ACanvas.Font.Color := ToColor(AColors.Warn);
        end
        else
        begin
          Frame(Box, AColors.Line);
          ACanvas.Font.Color := ToColor(AColors.Muted);
        end;
        ACanvas.Brush.Style := bsClear;
        Rect_ := Box;
        DrawText(ACanvas.Handle, PChar(Tag), -1, Rect_, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
      end;
      TagX := Box.Right + Scale(6);
    end;
    Inc(Y, TagHeight + Scale(8));
  end;
  // 2. Deklaration, eingefärbt und an Leerzeichen umbrochen.
  if FDetails.Declaration <> '' then
  begin
    ACanvas.Font := AFont;
    LineHeight := ACanvas.TextHeight('Wg') + Scale(2);
    Key := IntToStr(Right - Left) + '|' + IntToStr(APPI) + '|' + AFont.Name + '|' + IntToStr(AFont.Height);
    if Key <> FDeclKey then
    begin
      FDeclLines := FDecl.WrapAtSpaces(ACanvas, Right - Left, Scale(16));
      FDeclKey := Key;
    end;
    for Line := 0 to High(FDeclLines) do
    begin
      X := Left + IfThen(Line > 0, Scale(16));
      if ADraw then
        FDecl.Draw(ACanvas, AColors, FDeclLines[Line].X, FDeclLines[Line].Y, X, Rect(X, Y, Right, Y + LineHeight),
          False, Scale(3));
      Inc(Y, LineHeight);
    end;
    Inc(Y, Scale(3));
  end;
  // 3. Unit · Klasse; bei Helpern „Helper · Unit“ (#456).
  Text := FDetails.UnitName;
  if FDetails.IsHelper and (FDetails.Container <> '') then
  begin
    if Text <> '' then
      Text := FDetails.Container + ' · ' + Text
    else
      Text := FDetails.Container;
  end
  else if FDetails.Container <> '' then
    if Text <> '' then
      Text := Text + ' · ' + FDetails.Container
    else
      Text := FDetails.Container;
  Block(Text, AColors.Muted, []);
  // Helper aus nicht eingebundener Unit (#456): Enter ergänzt die uses.
  if FDetails.AddsUnit <> '' then
    Block(TAtlasStrings.Fmt(TAtlasTextId.HelperAddsUnit, [FDetails.AddsUnit]), AColors.Accent, []);
  // Verdeckte Deklarationen weiter außen (#488).
  for Text in FDetails.Hides do
    Block(TAtlasStrings.Fmt(TAtlasTextId.HidesDeclaration, [Text]), AColors.Muted, [fsItalic]);
  // Gleitkomma für eine Ganzzahl (#490): keine Umwandlung vorgeschlagen, nur der Hinweis.
  if FDetails.LossyFrom <> '' then
    Block(TAtlasStrings.Fmt(TAtlasTextId.CompletionLossyHint, [FDetails.LossyFrom, FDetails.LossyTo]), AColors.Warn,
      []);
  // 4.–6. Veraltung, Verfügbarkeit und XMLDoc; ohne Inhalt keine Trennlinie und keine leeren Abschnitte.
  if FDetails.IsDeprecated or not FDocData.IsEmpty or (FDetails.Availability <> '') then
  begin
    Separator;
    // Im aktiven Ziel nicht deklariert (#476): zuerst, in Warnfarbe.
    if FDetails.Availability <> '' then
      Block(FDetails.Availability, AColors.Warn, []);
    if FDetails.IsDeprecated then
      if FDetails.DeprecatedText <> '' then
        Block(TAtlasStrings.Fmt(TAtlasTextId.DeprecatedWith, [FDetails.DeprecatedText]), AColors.Warn, [])
      else
        Block(TAtlasStrings.Text(TAtlasTextId.DeprecatedPlain), AColors.Warn, []);
    if FDocData.IsEmpty then
      FDoc.Clear
    else
    begin
      if FDocWidth <> Right - Left then
      begin
        FDoc.Build(ACanvas, FDocData, Right - Left, AFont, AUIFont, APPI, FDetails.Display.Full, TAtlasStrings.DocLabels);
        FDocWidth := Right - Left;
      end;
      // Höher als erlaubt: nur die Doku scrollt, Kopf und Deklaration bleiben.
      Fixed := Y - ABounds.Top + Scale(5);
      if FMaxHeight > 0 then
        FDoc.FitHeight(FDetails.Display.MaxLines, FMaxHeight - Fixed)
      else
        FDoc.FitHeight(FDetails.Display.MaxLines, 0);
      FDocLeft := Left;
      FDocTop := Y;
      if ADraw then
        FDoc.Paint(ACanvas, AColors, Left, Y);
      Inc(Y, FDoc.Height);
    end;
  end
  else
    FDoc.Clear;
  ACanvas.Brush.Style := bsSolid;
  Result := Y - ABounds.Top + Scale(5);
end;

end.
