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
  Atlas.Core.Documentation.Typeset,
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

type
  /// <summary>Ein Durchlauf von TAtlasDetailView.Render: Zeichenfläche, Schriften, Spalte von Left bis Right und
  /// die laufende Höhe Y. Jeder Abschnitt rückt Y hinter sich; ohne Draw wird nur gemessen.</summary>
  TDetailRender = record
    View: TAtlasDetailView;
    Canvas: TCanvas;
    Colors: TAtlasColors;
    Font: TFont;
    UIFont: TFont;
    PPI: Integer;
    Draw: Boolean;
    Left: Integer;
    Right: Integer;
    Y: Integer;
    function Scale(AValue: Integer): Integer;
    procedure Frame(const ARect: TRect; ALine: TAtlasColor);
    /// <summary>Text in der UI-Schrift umbrechend ab Y.</summary>
    procedure Block(const AText: string; AColor: TAtlasColor; AStyle: TFontStyles);
    /// <summary>Text in der Editorschrift umbrechend ab Y (Pfad und Typen einer Unit, #469).</summary>
    procedure Mono(const AText: string; AColor: TAtlasColor);
    procedure Separator;
    /// <summary>Kopfzeile bei Überladungen (#425): "‹ 2 / 3 ›" rechtsbündig.</summary>
    procedure Overloads;
    /// <summary>1. Tags als umrandete Marken.</summary>
    procedure Tags;
    procedure Tag(const ATag: string; const ABox: TRect);
    /// <summary>2. Deklaration, eingefärbt und an Leerzeichen umbrochen.</summary>
    procedure Declaration;
    /// <summary>3. Unit · Klasse; bei Helpern „Helper · Unit“ (#456).</summary>
    procedure Origin;
    /// <summary>Unit im uses-Abschnitt (#469): Pfad, die ersten exportierten Typen, Zirkelbezug und anderer
    /// Abschnitt; Helper aus nicht eingebundener Unit (#456).</summary>
    procedure UsesInfo;
    /// <summary>Gleichnamige Bezeichner (#475): alle Units, die den Namen deklarieren, und was Enter tut.</summary>
    procedure SameName;
    procedure SameNameInsert;
    /// <summary>with-Objekt (#481), verdeckte Deklarationen (#488), Gleitkomma für eine Ganzzahl (#490).</summary>
    procedure Notes;
    /// <summary>4.–6. Veraltung, Verfügbarkeit und XMLDoc; ohne Inhalt keine Trennlinie und keine leeren
    /// Abschnitte. ATop: oberer Rand des Panels.</summary>
    procedure Doc(ATop: Integer);
    procedure BuildDoc;
  end;

{ TDetailRender }

function TDetailRender.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, PPI, 96);
end;

procedure TDetailRender.Frame(const ARect: TRect; ALine: TAtlasColor);
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := ToColor(ALine);
  Canvas.RoundRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, Scale(2 * TAtlasDraw.ChipRadius),
    Scale(2 * TAtlasDraw.ChipRadius));
end;

procedure TDetailRender.Block(const AText: string; AColor: TAtlasColor; AStyle: TFontStyles);
var
  mArea: TRect;
begin
  if AText = '' then
  begin
    Exit;
  end;
  Canvas.Font := UIFont;
  Canvas.Font.Style := AStyle;
  Canvas.Font.Color := ToColor(AColor);
  Canvas.Brush.Style := bsClear;
  mArea := Rect(Left, Y, Right, Y);
  DrawText(Canvas.Handle, PChar(AText), -1, mArea, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
  mArea.Right := Right;
  if Draw then
  begin
    DrawText(Canvas.Handle, PChar(AText), -1, mArea, DT_WORDBREAK or DT_NOPREFIX or DT_END_ELLIPSIS);
  end;
  Y := mArea.Bottom + Scale(6);
  Canvas.Font.Style := [];
end;

procedure TDetailRender.Mono(const AText: string; AColor: TAtlasColor);
var
  mArea: TRect;
begin
  Canvas.Font := Font;
  Canvas.Font.Color := ToColor(AColor);
  Canvas.Brush.Style := bsClear;
  mArea := Rect(Left, Y, Right, Y);
  DrawText(Canvas.Handle, PChar(AText), -1, mArea, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
  mArea.Right := Right;
  if Draw then
  begin
    DrawText(Canvas.Handle, PChar(AText), -1, mArea, DT_WORDBREAK or DT_NOPREFIX);
  end;
  Y := mArea.Bottom + Scale(6);
end;

procedure TDetailRender.Separator;
begin
  if Draw then
  begin
    TAtlasDraw.Separator(Canvas, Left, Right, Y + Scale(2), Colors.Line);
  end;
  Inc(Y, Scale(8));
end;

procedure TDetailRender.Overloads;
var
  mLineHeight, mX: Integer;
  mText: string;
  mCount: TRect;
begin
  Canvas.Font := UIFont;
  mLineHeight := Canvas.TextHeight('Wg');
  mText := Format('%d / %d', [View.FOverloadIndex + 1, View.FOverloadCount]);
  mX := Right - Canvas.TextWidth('›') - Scale(4);
  View.FNextRect := Rect(mX - Scale(4), Y - Scale(2), Right, Y + mLineHeight + Scale(2));
  Dec(mX, Canvas.TextWidth(mText) + Scale(8));
  mCount := Rect(mX, Y, mX + Canvas.TextWidth(mText), Y + mLineHeight);
  Dec(mX, Canvas.TextWidth('‹') + Scale(8));
  View.FPreviousRect := Rect(mX - Scale(4), Y - Scale(2), mX + Canvas.TextWidth('‹') + Scale(4),
    Y + mLineHeight + Scale(2));
  if Draw then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.TextOut(Left, Y, TAtlasStrings.Text(TAtlasTextId.Overload));
    Canvas.Font.Color := ToColor(Colors.Text);
    DrawText(Canvas.Handle, PChar(mText), -1, mCount, DT_SINGLELINE or DT_NOPREFIX);
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := ToColor(Colors.Accent);
    Canvas.TextOut(View.FPreviousRect.Left + Scale(4), Y, '‹');
    Canvas.TextOut(View.FNextRect.Left + Scale(4), Y, '›');
    Canvas.Font.Style := [];
  end;
  Inc(Y, mLineHeight + Scale(8));
end;

procedure TDetailRender.Tag(const ATag: string; const ABox: TRect);
var
  mText: TRect;
begin
  if ATag = 'deprecated' then
  begin
    Frame(ABox, Colors.Warn);
    Canvas.Font.Color := ToColor(Colors.Warn);
  end
  else
  begin
    Frame(ABox, Colors.Line);
    Canvas.Font.Color := ToColor(Colors.Muted);
  end;
  Canvas.Brush.Style := bsClear;
  mText := ABox;
  DrawText(Canvas.Handle, PChar(ATag), -1, mText, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

procedure TDetailRender.Tags;
var
  mTag: string;
  mTagX, mTagHeight: Integer;
  mBox: TRect;
begin
  if (View.FDetails.Visibility = '') and (Length(View.FDetails.Directives) = 0) then
  begin
    Exit;
  end;
  Canvas.Font := UIFont;
  mTagHeight := Canvas.TextHeight('Wg') + Scale(2);
  mTagX := Left;
  for mTag in TArray<string>.Create(View.FDetails.Visibility) + View.FDetails.Directives do
  begin
    if mTag = '' then
    begin
      Continue;
    end;
    Canvas.Font := UIFont;
    mBox := Rect(mTagX, Y, mTagX + Canvas.TextWidth(mTag) + Scale(TAtlasDraw.ChipPad), Y + mTagHeight);
    if Draw then
    begin
      Tag(mTag, mBox);
    end;
    mTagX := mBox.Right + Scale(6);
  end;
  Inc(Y, mTagHeight + Scale(8));
end;

procedure TDetailRender.Declaration;
var
  mLineHeight, mLine, mX: Integer;
  mKey: string;
begin
  if View.FDetails.Declaration = '' then
  begin
    Exit;
  end;
  Canvas.Font := Font;
  mLineHeight := Canvas.TextHeight('Wg') + Scale(2);
  mKey := IntToStr(Right - Left) + '|' + IntToStr(PPI) + '|' + Font.Name + '|' + IntToStr(Font.Height);
  if mKey <> View.FDeclKey then
  begin
    View.FDeclLines := View.FDecl.WrapAtSpaces(Canvas, Right - Left, Scale(16));
    View.FDeclKey := mKey;
  end;
  for mLine := 0 to High(View.FDeclLines) do
  begin
    mX := Left + IfThen(mLine > 0, Scale(16));
    if Draw then
    begin
      View.FDecl.Draw(TAtlasStyledTarget.Create(Canvas, Colors, Scale(3)), View.FDeclLines[mLine], mX,
        Rect(mX, Y, Right, Y + mLineHeight), False);
    end;
    Inc(Y, mLineHeight);
  end;
  Inc(Y, Scale(3));
end;

procedure TDetailRender.Origin;
var
  mText: string;
begin
  mText := View.FDetails.UnitName;
  if View.FDetails.Container = '' then
  begin
    // Nur die Unit (bzw. nichts).
  end
  else if mText = '' then
  begin
    mText := View.FDetails.Container;
  end
  else if View.FDetails.IsHelper then
  begin
    mText := View.FDetails.Container + ' · ' + mText;
  end
  else
  begin
    mText := mText + ' · ' + View.FDetails.Container;
  end;
  Block(mText, Colors.Muted, []);
end;

procedure TDetailRender.UsesInfo;
var
  mText: string;
begin
  if View.FDetails.UnitPath <> '' then
  begin
    Mono(View.FDetails.UnitPath, Colors.Muted);
  end;
  if Length(View.FDetails.UnitTypes) > 0 then
  begin
    Separator;
    Block(UpperCase(TAtlasStrings.Text(TAtlasTextId.UsesTypesHeading)), Colors.Muted, [fsBold]);
    mText := string.Join(' · ', View.FDetails.UnitTypes);
    if View.FDetails.UnitTypeCount > Length(View.FDetails.UnitTypes) then
    begin
      mText := mText + ' · …';
    end;
    Mono(mText, Colors.Text);
  end;
  if View.FDetails.UsesCycle <> '' then
  begin
    Block(TAtlasStrings.UsesCycle(View.FDetails.UsesCycle), Colors.Error, []);
  end;
  if View.FDetails.UsesElsewhere = 'interface' then
  begin
    Block(TAtlasStrings.Text(TAtlasTextId.UsesInInterface), Colors.Muted, [fsItalic]);
  end
  else if View.FDetails.UsesElsewhere = 'implementation' then
  begin
    Block(TAtlasStrings.Text(TAtlasTextId.UsesInImplementation), Colors.Muted, [fsItalic]);
  end;
  // Helper aus nicht eingebundener Unit (#456): Enter ergänzt die uses.
  if View.FDetails.AddsUnit <> '' then
  begin
    Block(TAtlasStrings.Fmt(TAtlasTextId.HelperAddsUnit, [View.FDetails.AddsUnit]), Colors.Accent, []);
  end;
end;

procedure TDetailRender.SameName;
var
  mIndex: Integer;
  mText: string;
begin
  if Length(View.FDetails.SameNameUnits) = 0 then
  begin
    Exit;
  end;
  Separator;
  Block(UpperCase(TAtlasStrings.Text(TAtlasTextId.SameNameDeclaredIn)), Colors.Muted, [fsBold]);
  for mIndex := 0 to High(View.FDetails.SameNameUnits) do
  begin
    mText := View.FDetails.SameNameUnits[mIndex];
    if mIndex = 0 then
    begin
      mText := mText + ' · ' + TAtlasStrings.Text(TAtlasTextId.SameNameRoleActive);
    end
    else if SameText(mText, View.FDetails.SameNameThis) then
    begin
      mText := mText + ' · ' + TAtlasStrings.Text(TAtlasTextId.SameNameRoleThis);
    end;
    if SameText(View.FDetails.SameNameUnits[mIndex], View.FDetails.SameNameThis) then
    begin
      Block(mText, Colors.Text, [fsBold]);
    end
    else
    begin
      Block(mText, Colors.Text, []);
    end;
  end;
  for mText in View.FDetails.SameNameHidden do
  begin
    Block(mText + ' · ' + TAtlasStrings.Text(TAtlasTextId.SameNameRoleHidden), Colors.Muted, [fsItalic]);
  end;
  SameNameInsert;
end;

procedure TDetailRender.SameNameInsert;
var
  mLead: string;
begin
  mLead := TAtlasStrings.Text(TAtlasTextId.SameNameNotActive) + ' · ';
  if View.FDetails.SameNameInsert = 'prefix' then
  begin
    Block(mLead + TAtlasStrings.Text(TAtlasTextId.SameNameInsertPrefix), Colors.Muted, []);
  end
  else if View.FDetails.SameNameInsert = 'prefixAdd' then
  begin
    Block(mLead + TAtlasStrings.Fmt(TAtlasTextId.SameNameInsertPrefixAdd, [View.FDetails.SameNameThis]), Colors.Warn,
      []);
  end
  else if View.FDetails.SameNameInsert = 'move' then
  begin
    Block(mLead + TAtlasStrings.Fmt(TAtlasTextId.SameNameInsertMove, [View.FDetails.SameNameThis]), Colors.Warn, []);
  end
  else if View.FDetails.SameNameInsert = 'add' then
  begin
    Block(mLead + TAtlasStrings.Fmt(TAtlasTextId.SameNameInsertAdd, [View.FDetails.SameNameThis]), Colors.Warn, []);
  end;
end;

procedure TDetailRender.Notes;
var
  mText: string;
begin
  // with-Objekt (#481): Zusammen mit „Verdeckt: …“ nennt das Panel beide Bedeutungen.
  if View.FDetails.WithOrigin <> '' then
  begin
    Block(TAtlasStrings.Fmt(TAtlasTextId.WithMemberOrigin, [View.FDetails.WithOrigin]), Colors.Accent, []);
  end;
  // Verdeckte Deklarationen weiter außen (#488).
  for mText in View.FDetails.Hides do
  begin
    Block(TAtlasStrings.Fmt(TAtlasTextId.HidesDeclaration, [mText]), Colors.Muted, [fsItalic]);
  end;
  // Gleitkomma für eine Ganzzahl (#490): keine Umwandlung vorgeschlagen, nur der Hinweis.
  if View.FDetails.LossyFrom <> '' then
  begin
    Block(TAtlasStrings.Fmt(TAtlasTextId.CompletionLossyHint, [View.FDetails.LossyFrom, View.FDetails.LossyTo]),
      Colors.Warn, []);
  end;
end;

procedure TDetailRender.BuildDoc;
var
  mExpanded: Boolean;
begin
  // Neue Details: Zustand nach Einstellung; nur andere Breite: Zustand bleibt.
  if View.FDocWidth = 0 then
  begin
    mExpanded := TAtlasDocExpandState.Initial(View.FDetails.Display.Expand, TAtlasDocSurface.Details);
  end
  else
  begin
    mExpanded := View.FDoc.Expanded;
  end;
  View.FDoc.Build(Canvas, TAtlasDocContent.Create(View.FDocData, TAtlasDocSignature.Parse(View.FDetails.Declaration),
    mExpanded), Right - Left, TAtlasDocFonts.Create(Font, UIFont, PPI), TAtlasStrings.DocLabels);
  View.FDocWidth := Right - Left;
end;

procedure TDetailRender.Doc(ATop: Integer);
var
  mFixed: Integer;
begin
  if not View.FDetails.IsDeprecated and View.FDocData.IsEmpty and (View.FDetails.Availability = '') then
  begin
    View.FDoc.Clear;
    Exit;
  end;
  Separator;
  // Im aktiven Ziel nicht deklariert (#476): zuerst, in Warnfarbe.
  Block(View.FDetails.Availability, Colors.Warn, []);
  if View.FDetails.IsDeprecated and (View.FDetails.DeprecatedText <> '') then
  begin
    Block(TAtlasStrings.Fmt(TAtlasTextId.DeprecatedWith, [View.FDetails.DeprecatedText]), Colors.Warn, []);
  end
  else if View.FDetails.IsDeprecated then
  begin
    Block(TAtlasStrings.Text(TAtlasTextId.DeprecatedPlain), Colors.Warn, []);
  end;
  if View.FDocData.IsEmpty then
  begin
    View.FDoc.Clear;
    Exit;
  end;
  if View.FDocWidth <> Right - Left then
  begin
    BuildDoc;
  end;
  // Höher als erlaubt: nur die Doku scrollt, Kopf und Deklaration bleiben.
  mFixed := Y - ATop + Scale(5);
  if View.FMaxHeight > 0 then
  begin
    View.FDoc.FitHeight(View.FDetails.Display.MaxLines, View.FMaxHeight - mFixed);
  end
  else
  begin
    View.FDoc.FitHeight(View.FDetails.Display.MaxLines, 0);
  end;
  View.FDocLeft := Left;
  View.FDocTop := Y;
  if Draw then
  begin
    View.FDoc.Paint(Canvas, Colors, Left, Y);
  end;
  Inc(Y, View.FDoc.Height);
end;

function TAtlasDetailView.Render(ACanvas: TCanvas; const AColors: TAtlasColors; AFont, AUIFont: TFont;
  const ABounds: TRect; APPI: Integer; ADraw: Boolean): Integer;
var
  mRender: TDetailRender;
begin
  mRender.View := Self;
  mRender.Canvas := ACanvas;
  mRender.Colors := AColors;
  mRender.Font := AFont;
  mRender.UIFont := AUIFont;
  mRender.PPI := APPI;
  mRender.Draw := ADraw;
  mRender.Left := ABounds.Left + mRender.Scale(13);
  mRender.Right := ABounds.Right - mRender.Scale(13);
  mRender.Y := ABounds.Top + mRender.Scale(11);
  FPreviousRect := TRect.Empty;
  FNextRect := TRect.Empty;
  if FOverloadCount > 1 then
  begin
    mRender.Overloads;
  end;
  if FDetails.IsEmpty then
  begin
    mRender.Block(TAtlasStrings.Text(TAtlasTextId.NoDetails), AColors.Muted, []);
  end
  else
  begin
    mRender.Tags;
    mRender.Declaration;
    mRender.Origin;
    mRender.UsesInfo;
    mRender.SameName;
    mRender.Notes;
    mRender.Doc(ABounds.Top);
    ACanvas.Brush.Style := bsSolid;
  end;
  Result := mRender.Y - ABounds.Top + mRender.Scale(5);
end;

end.
