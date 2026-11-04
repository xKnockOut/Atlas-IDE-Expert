unit Atlas.UI.Completion.Details;

// Detailpanel der Vervollständigung (#424, #426, #427): kein eigenes Fenster,
// sondern der rechte (bzw. linke) Bereich des Popups, wie im Entwurf ein
// Rahmen mit Trennlinie. Inhalt von oben nach unten:
//   1. Tags: Sichtbarkeit und Direktiven als umrandete Marken, deprecated in Warnfarbe
//   2. Deklaration in der Editorschrift, eingefärbt, umbrechend
//   3. Unit · Klasse, gedämpft; bei Units im uses-Abschnitt (#469) Pfad, exportierte Typen, Zirkelbezug in
//      Fehlerfarbe und der Abschnitt, in dem die Unit schon steht
//   4. Trennlinie
//   5. bei deprecated "Veraltet: …" in Warnfarbe
//   6. XMLDoc formatiert (#654, #770) wie im Hover-Tooltip: Beschreibung, dann
//      unter Überschriften Parameter in der Reihenfolge der Signatur,
//      Typparameter, Rückgabe, Wert, Ausnahmen, Hinweise, Beispiel, Siehe auch.
//      Zugeklappt (hints.xmlDocExpand) nur die Beschreibung mit „Mehr anzeigen ▾“;
//      der Klick klappt auf, „wie zuletzt“ gilt getrennt vom Tooltip. Ist das
//      Panel höher als das Popup, scrollt nur die Doku mit dem Mausrad. Text
//      lässt sich markieren; Verweise mit Strg+Klick und Links sind anklickbar.
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
    /// <summary>„Mehr/Weniger anzeigen“ (#770): klappt um und merkt den Zustand; True = aufgeklappt.</summary>
    function ToggleDoc(ACanvas: TCanvas): Boolean;
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
    begin
      Exit;
    end;
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
  begin
    Exit;
  end;
  Add(TAtlasDocSectionKind.Summary, '', ADetails.Summary);
  for Entry in ADetails.Params do
  begin
    Add(TAtlasDocSectionKind.Param, Entry.Name, Entry.Text);
  end;
  Add(TAtlasDocSectionKind.Returns, '', ADetails.Returns);
  for Entry in ADetails.Exceptions do
  begin
    Add(TAtlasDocSectionKind.Exception, Entry.Name, Entry.Text);
  end;
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
  begin
    Result := FDoc.LinkAt(AX - FDocLeft, AY - FDocTop);
  end;
end;

function TAtlasDetailView.ScrollDoc(ASteps: Integer): Boolean;
begin
  Result := FDoc.ScrollBy(ASteps * FDoc.WheelStep);
end;

function TAtlasDetailView.ToggleDoc(ACanvas: TCanvas): Boolean;
begin
  Result := FDoc.Toggle(ACanvas);
  FDoc.ClearSelection;
  FDoc.HotLink := -1;
  TAtlasDocExpandState.Remember(TAtlasDocSurface.Details, Result);
end;

function TAtlasDetailView.Render(ACanvas: TCanvas; const AColors: TAtlasColors; AFont, AUIFont: TFont;
  const ABounds: TRect; APPI: Integer; ADraw: Boolean): Integer;
var
  Left, Y, Right, TagX, TagHeight, LineHeight, Fixed: Integer;
  Text, Tag, Key: string;
  Line, X, Index: Integer;
  Box, Rect_: TRect;
  Expanded: Boolean;

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
  procedure Block(const AText: string; AColor: TAtlasColor; AStyle: TFontStyles; AMaxLines: Integer); overload;
  var
    Area: TRect;
  begin
    if AText = '' then
    begin
      Exit;
    end;
    ACanvas.Font := AUIFont;
    ACanvas.Font.Style := AStyle;
    ACanvas.Font.Color := ToColor(AColor);
    ACanvas.Brush.Style := bsClear;
    Area := Rect(Left, Y, Right, Y);
    DrawText(ACanvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
    Area.Right := Right;
    if AMaxLines > 0 then
    begin
      Area.Bottom := Min(Area.Bottom, Y + AMaxLines * ACanvas.TextHeight('Wg'));
    end;
    if ADraw then
    begin
      DrawText(ACanvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_END_ELLIPSIS);
    end;
    Y := Area.Bottom + Scale(6);
    ACanvas.Font.Style := [];
  end;

  /// <summary>Wie oben ohne Grenze (AMaxLines = 0).</summary>
  procedure Block(const AText: string; AColor: TAtlasColor; AStyle: TFontStyles); overload;
  begin
    Block(AText, AColor, AStyle, 0);
  end;

  /// <summary>Text in der Editorschrift umbrechend ab Y (Pfad und Typen einer Unit, #469).</summary>
  procedure Mono(const AText: string; AColor: TAtlasColor);
  var
    Area: TRect;
  begin
    ACanvas.Font := AFont;
    ACanvas.Font.Color := ToColor(AColor);
    ACanvas.Brush.Style := bsClear;
    Area := Rect(Left, Y, Right, Y);
    DrawText(ACanvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
    Area.Right := Right;
    if ADraw then
    begin
      DrawText(ACanvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX);
    end;
    Y := Area.Bottom + Scale(6);
  end;

  procedure Separator;
  begin
    if ADraw then
    begin
      TAtlasDraw.Separator(ACanvas, Left, Right, Y + Scale(2), AColors.Line);
    end;
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
      begin
        Continue;
      end;
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
      begin
        FDecl.Draw(TAtlasStyledTarget.Create(ACanvas, AColors, Scale(3)), FDeclLines[Line], X,
          Rect(X, Y, Right, Y + LineHeight), False);
      end;
      Inc(Y, LineHeight);
    end;
    Inc(Y, Scale(3));
  end;
  // 3. Unit · Klasse; bei Helpern „Helper · Unit“ (#456).
  Text := FDetails.UnitName;
  if FDetails.IsHelper and (FDetails.Container <> '') then
  begin
    if Text <> '' then
    begin
      Text := FDetails.Container + ' · ' + Text;
    end
    else
    begin
      Text := FDetails.Container;
    end;
  end
  else if FDetails.Container <> '' then
  begin
    if Text <> '' then
    begin
      Text := Text + ' · ' + FDetails.Container;
    end
    else
    begin
      Text := FDetails.Container;
    end;
  end;
  Block(Text, AColors.Muted, []);
  // Unit im uses-Abschnitt (#469): Pfad, die ersten exportierten Typen, Zirkelbezug und anderer Abschnitt.
  if FDetails.UnitPath <> '' then
  begin
    Mono(FDetails.UnitPath, AColors.Muted);
  end;
  if Length(FDetails.UnitTypes) > 0 then
  begin
    Separator;
    Block(UpperCase(TAtlasStrings.Text(TAtlasTextId.UsesTypesHeading)), AColors.Muted, [fsBold]);
    Text := string.Join(' · ', FDetails.UnitTypes);
    if FDetails.UnitTypeCount > Length(FDetails.UnitTypes) then
    begin
      Text := Text + ' · …';
    end;
    Mono(Text, AColors.Text);
  end;
  if FDetails.UsesCycle <> '' then
  begin
    Block(TAtlasStrings.UsesCycle(FDetails.UsesCycle), AColors.Error, []);
  end;
  if FDetails.UsesElsewhere = 'interface' then
  begin
    Block(TAtlasStrings.Text(TAtlasTextId.UsesInInterface), AColors.Muted, [fsItalic]);
  end
  else if FDetails.UsesElsewhere = 'implementation' then
  begin
    Block(TAtlasStrings.Text(TAtlasTextId.UsesInImplementation), AColors.Muted, [fsItalic]);
  end;
  // Helper aus nicht eingebundener Unit (#456): Enter ergänzt die uses.
  if FDetails.AddsUnit <> '' then
  begin
    Block(TAtlasStrings.Fmt(TAtlasTextId.HelperAddsUnit, [FDetails.AddsUnit]), AColors.Accent, []);
  end;
  // Gleichnamige Bezeichner (#475): alle Units, die den Namen deklarieren, und was Enter tut.
  if Length(FDetails.SameNameUnits) > 0 then
  begin
    Separator;
    Block(UpperCase(TAtlasStrings.Text(TAtlasTextId.SameNameDeclaredIn)), AColors.Muted, [fsBold]);
    for Index := 0 to High(FDetails.SameNameUnits) do
    begin
      Text := FDetails.SameNameUnits[Index];
      if Index = 0 then
      begin
        Text := Text + ' · ' + TAtlasStrings.Text(TAtlasTextId.SameNameRoleActive);
      end
      else if SameText(Text, FDetails.SameNameThis) then
      begin
        Text := Text + ' · ' + TAtlasStrings.Text(TAtlasTextId.SameNameRoleThis);
      end;
      if SameText(FDetails.SameNameUnits[Index], FDetails.SameNameThis) then
      begin
        Block(Text, AColors.Text, [fsBold]);
      end
      else
      begin
        Block(Text, AColors.Text, []);
      end;
    end;
    for Text in FDetails.SameNameHidden do
    begin
      Block(Text + ' · ' + TAtlasStrings.Text(TAtlasTextId.SameNameRoleHidden), AColors.Muted, [fsItalic]);
    end;
    if FDetails.SameNameInsert = 'prefix' then
    begin
      Block(TAtlasStrings.Text(TAtlasTextId.SameNameNotActive) + ' · ' +
        TAtlasStrings.Text(TAtlasTextId.SameNameInsertPrefix), AColors.Muted, []);
    end
    else if FDetails.SameNameInsert = 'prefixAdd' then
    begin
      Block(TAtlasStrings.Text(TAtlasTextId.SameNameNotActive) + ' · ' +
        TAtlasStrings.Fmt(TAtlasTextId.SameNameInsertPrefixAdd, [FDetails.SameNameThis]), AColors.Warn, []);
    end
    else if FDetails.SameNameInsert = 'move' then
    begin
      Block(TAtlasStrings.Text(TAtlasTextId.SameNameNotActive) + ' · ' +
        TAtlasStrings.Fmt(TAtlasTextId.SameNameInsertMove, [FDetails.SameNameThis]), AColors.Warn, []);
    end
    else if FDetails.SameNameInsert = 'add' then
    begin
      Block(TAtlasStrings.Text(TAtlasTextId.SameNameNotActive) + ' · ' +
        TAtlasStrings.Fmt(TAtlasTextId.SameNameInsertAdd, [FDetails.SameNameThis]), AColors.Warn, []);
    end;
  end;
  // with-Objekt (#481): Zusammen mit „Verdeckt: …“ nennt das Panel beide Bedeutungen.
  if FDetails.WithOrigin <> '' then
  begin
    Block(TAtlasStrings.Fmt(TAtlasTextId.WithMemberOrigin, [FDetails.WithOrigin]), AColors.Accent, []);
  end;
  // Verdeckte Deklarationen weiter außen (#488).
  for Text in FDetails.Hides do
  begin
    Block(TAtlasStrings.Fmt(TAtlasTextId.HidesDeclaration, [Text]), AColors.Muted, [fsItalic]);
  end;
  // Gleitkomma für eine Ganzzahl (#490): keine Umwandlung vorgeschlagen, nur der Hinweis.
  if FDetails.LossyFrom <> '' then
  begin
    Block(TAtlasStrings.Fmt(TAtlasTextId.CompletionLossyHint, [FDetails.LossyFrom, FDetails.LossyTo]), AColors.Warn,
      []);
  end;
  // 4.–6. Veraltung, Verfügbarkeit und XMLDoc; ohne Inhalt keine Trennlinie und keine leeren Abschnitte.
  if FDetails.IsDeprecated or not FDocData.IsEmpty or (FDetails.Availability <> '') then
  begin
    Separator;
    // Im aktiven Ziel nicht deklariert (#476): zuerst, in Warnfarbe.
    if FDetails.Availability <> '' then
    begin
      Block(FDetails.Availability, AColors.Warn, []);
    end;
    if FDetails.IsDeprecated then
    begin
      if FDetails.DeprecatedText <> '' then
      begin
        Block(TAtlasStrings.Fmt(TAtlasTextId.DeprecatedWith, [FDetails.DeprecatedText]), AColors.Warn, []);
      end
      else
      begin
        Block(TAtlasStrings.Text(TAtlasTextId.DeprecatedPlain), AColors.Warn, []);
      end;
    end;
    if FDocData.IsEmpty then
    begin
      FDoc.Clear;
    end
    else
    begin
      if FDocWidth <> Right - Left then
      begin
        // Neue Details: Zustand nach Einstellung; nur andere Breite: Zustand bleibt.
        if FDocWidth = 0 then
        begin
          Expanded := TAtlasDocExpandState.Initial(FDetails.Display.Expand, TAtlasDocSurface.Details);
        end
        else
        begin
          Expanded := FDoc.Expanded;
        end;
        FDoc.Build(ACanvas, FDocData, Right - Left, AFont, AUIFont, APPI, TAtlasStrings.DocLabels,
          TAtlasDocSignature.Parse(FDetails.Declaration), Expanded);
        FDocWidth := Right - Left;
      end;
      // Höher als erlaubt: nur die Doku scrollt, Kopf und Deklaration bleiben.
      Fixed := Y - ABounds.Top + Scale(5);
      if FMaxHeight > 0 then
      begin
        FDoc.FitHeight(FDetails.Display.MaxLines, FMaxHeight - Fixed);
      end
      else
      begin
        FDoc.FitHeight(FDetails.Display.MaxLines, 0);
      end;
      FDocLeft := Left;
      FDocTop := Y;
      if ADraw then
      begin
        FDoc.Paint(ACanvas, AColors, Left, Y);
      end;
      Inc(Y, FDoc.Height);
    end;
  end
  else
  begin
    FDoc.Clear;
  end;
  ACanvas.Brush.Style := bsSolid;
  Result := Y - ABounds.Top + Scale(5);
end;

end.
