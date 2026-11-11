unit Atlas.UI.Completion.Popup;

// Vervollständigungs-Popup (#410, #413): virtuelle Liste ohne Fokus. Gezeichnet
// werden nur die sichtbaren Zeilen; Filtern liefert nur ein neues Index-Array
// (AOrder), die Einträge selbst werden nicht kopiert.
// Aussehen nach dem Entwurf (#411, #420, #421):
//   - Zeile: farbiges Badge mit Kürzel (fn, pr, pp, ...), Name in der
//     Editorschrift mit den getippten Zeichen in Akzentfarbe, rechtsbündig
//     gedämpft das Detail und Tags ("+ Unit", deprecated). Zu lang: erst das
//     Detail kürzen, dann den Namen.
//   - Gewählte Zeile auf einer abgerundeten Akzentfläche, Text bleibt lesbar.
//   - Fußzeile mit Tasten und "n von m"; schmale Scrollleiste.
//   - Gekürzte Zeilen zeigen nach 600 ms Verweilen mit der Maus den vollen Text (#420).
//   - Detailpanel (#424) im selben Fenster, durch eine Linie abgetrennt auf
//     abgesetzter Fläche; rechts der Liste, ohne Platz dort links davon. Ist
//     es einmal offen, bleibt sein Bereich bis zum Schließen stehen. Strg+Q bzw.
//     Klick auf die Leiste klappt es auf eine schmale Leiste ein und wieder auf
//     (#428); passt es weder rechts noch links, ist es automatisch eingeklappt.
//   - Breiten (#416): Splitter zwischen Liste und Panel, rechter Rand und Griff
//     unten rechts mit der Maus ziehbar; Doppelklick auf den Griff stellt die
//     automatische Breite wieder her. Ohne gezogene Breite wächst die Liste mit
//     dem breitesten Eintrag. Gezogen wird ohne Aktivierung, der Editor behält
//     den Fokus.
// Die Position ergibt sich aus dem Anker (Caret-Rechteck in Bildschirm-
// koordinaten): darunter, sonst darüber; nie über den Monitorrand hinaus.
// Ohne Treffer zeigt es den leeren Zustand (#423). Breite und Höhe wachsen bei
// Bedarf, schrumpfen während einer Sitzung aber nicht (#416), damit es beim
// Filtern und Blättern nicht springt.
// Mengenmodus (#448): Kontrollkästchen vor dem Badge, Überschrift „TAnchors ·
// Menge von TAnchorKind“, Fußzeile mit Leertaste und „n gewählt“.
// Diagnosemodus (#479): Ist die Messung an, meldet Paint seine Dauer an
// TAtlasQueryTimings (Schritt „Zeichnen“); aus kein Zeitstempel.
// Favoriten (#458, FavoritesEnabled): Spalte vor dem Badge; angeheftete Einträge tragen dort einen gefüllten
// Stern, beim Überfahren einer Zeile erscheint ein leerer. Klick auf den Stern meldet OnFavorite, ohne die
// Auswahl zu ändern. ShowNotice zeigt einen Hinweis links in der Fußzeile („Schon 5 Favoriten bei TDataSet …“)
// bis zum nächsten getippten Zeichen bzw. Schließen.
// Rest der Liste (#497): Einträge unter der Überschrift „Weitere Einträge“ (TAtlasRanking.cRestHeader) sind
// gedämpft; die Fußzeile nennt „n Treffer · m weitere“ bzw. „Keine Treffer“, wenn nur der Rest steht.
// Barrierefreiheit (#447): Die Einträge sind für UI Automation Listeneinträge (IAtlasAccessibleItems) mit
// Zustand aus den Tags; die gewählte Zeile trägt mit SelectionMarker zusätzlich Rahmen und Marke ▸, damit sie
// nicht nur an der Farbe erkennbar ist.
// Unvollständiger Code (#457, IAtlasCompletionSyntaxView): Unter den Chips steht eine Leiste in Warnfarbe
// „Ergebnisse möglicherweise unvollständig · Syntaxfehler in Zeile n“ (unbekannt: „Kontext unklar · …“), auch im
// leeren Zustand, der dann den Fehlertext nennt. Klick auf die unterstrichene Zeilenangabe meldet OnSyntaxLine.
// Aufbau: Die Klasse erbt ihre Teile über die Kette TAtlasCompletionPopupState (Zustand, Höhen) →
// TAtlasCompletionPopupLayout (Lage, Panel) → TAtlasCompletionPopupPainter (Zeichnen, Tooltip); hier stehen Maus,
// Anzeige der Liste und Barrierefreiheit. Texte in Atlas.UI.Completion.PopupTexts.

interface

uses
  System.Classes,
  System.Types,
  Vcl.Controls,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Completion.Ranking,
  Atlas.UI.Popup.Accessibility,
  Atlas.UI.Completion.PopupState,
  Atlas.UI.Completion.PopupPainter;

type
  TAtlasCompletionPopup = class(TAtlasCompletionPopupPainter, IAtlasCompletionView, IAtlasCompletionSyntaxView,
    IAtlasAccessibleItems)
  private
    /// <summary>Breite ziehen (#416): Bildschirmkoordinaten, weil das Fenster beim Ziehen mitwächst.</summary>
    procedure DragTo;
    /// <summary>Mauszeiger über Splitter, Rand, Leiste, Verweis, Stern, Warnleiste oder Doku.</summary>
    procedure UpdateCursor(AX, AY: Integer);
    procedure AnnounceSelected;
    { IAtlasAccessibleItems }
    function AccessibleCount: Integer;
    function AccessibleSelected: Integer;
    function AccessibleId(APosition: Integer): Integer;
    function AccessibleName(APosition: Integer): string;
    function AccessibleStatus(APosition: Integer): string;
    function AccessibleHelp(APosition: Integer): string;
    function AccessibleIsHeader(APosition: Integer): Boolean;
    function AccessibleBounds(APosition: Integer; out ARect: TRect): Boolean;
    procedure AccessibleSelect(APosition: Integer);
    /// <summary>Liste für UI Automation, sofern schon angefragt.</summary>
    function AccessibleList: TAtlasAccessibleList;
  protected
    function CreateAccessible(ARole: Integer; const AName: string): TAtlasAccessibleElement; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    /// <summary>Hinweis links in der Fußzeile (#458), auch für die Sprachausgabe; gilt bis zum nächsten
    /// getippten Zeichen bzw. Schließen.</summary>
    procedure ShowNotice(const AText: string);
    { IAtlasCompletionView }
    procedure ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    procedure ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip; AVisible: Boolean);
    { IAtlasCompletionSyntaxView }
    procedure ShowSyntax(const ANotice: TAtlasSyntaxNotice);
    property OnSelect: TAtlasPositionEvent read FEvents.OnSelect write FEvents.OnSelect;
    property OnAccept: TAtlasPositionEvent read FEvents.OnAccept write FEvents.OnAccept;
    property OnChip: TAtlasChipEvent read FEvents.OnChip write FEvents.OnChip;
    /// <summary>Klick auf ‹ bzw. › im Panel (#425).</summary>
    property OnOverload: TAtlasOverloadEvent read FEvents.OnOverload write FEvents.OnOverload;
    property OnDocLink: TAtlasDocLinkEvent read FEvents.OnDocLink write FEvents.OnDocLink;
    /// <summary>Klick auf den Stern einer Zeile (#458); APosition in der Anzeigereihenfolge.</summary>
    property OnFavorite: TAtlasPositionEvent read FEvents.OnFavorite write FEvents.OnFavorite;
    /// <summary>Klick auf die Zeilenangabe der Warnleiste (#457).</summary>
    property OnSyntaxLine: TAtlasSyntaxLineEvent read FEvents.OnSyntaxLine write FEvents.OnSyntaxLine;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Math,
  Atlas.Core.Completion.Width,
  Atlas.Core.Completion.Presentation,
  Atlas.Core.Documentation.Layout,
  Atlas.UI.Completion.Strings,
  Atlas.UI.Completion.PopupTexts;

type
  /// <summary>Linksklick ins Popup (MouseDown): Die Teile, die ihn abnehmen, kommen in fester Reihenfolge dran;
  /// nimmt ihn keiner ab, wählt er die Zeile.</summary>
  TPopupClick = record
    Popup: TAtlasCompletionPopup;
    X: Integer;
    Y: Integer;
    Shift: TShiftState;
    /// <summary>Zeilenangabe der Warnleiste (#457).</summary>
    function Syntax: Boolean;
    /// <summary>Leiste des eingeklappten Panels (#428), Splitter, Rand und Griff (#416).</summary>
    function Area: Boolean;
    procedure StartDrag(AKind: TAtlasDragKind; AWidth, ASign: Integer);
    /// <summary>Pfeile der Überladungen im Panel (#425).</summary>
    function Overload: Boolean;
    /// <summary>XMLDoc im Panel (#654): Verweis bzw. Link, sonst Beginn einer Markierung.</summary>
    function Doc: Boolean;
    procedure OpenDocLink(AIndex: Integer);
    /// <summary>Filter-Chip (#422).</summary>
    function Chip: Boolean;
    /// <summary>Stern einer Zeile (#458): anheften bzw. lösen, die Auswahl bleibt.</summary>
    function Star: Boolean;
    procedure Run;
  end;

{ TPopupClick }

function TPopupClick.Syntax: Boolean;
begin
  Result := PtInRect(Popup.FSyntaxLink, Point(X, Y)) and Assigned(Popup.FEvents.OnSyntaxLine);
  if Result then
  begin
    Popup.FEvents.OnSyntaxLine(Popup.FSyntax.Line, Popup.FSyntax.Character);
  end;
end;

procedure TPopupClick.StartDrag(AKind: TAtlasDragKind; AWidth, ASign: Integer);
begin
  Popup.HideTip;
  Popup.FDrag.Kind := AKind;
  Popup.FDrag.StartWidth := AWidth;
  Popup.FDrag.Sign := ASign;
  Popup.FDrag.StartX := Mouse.CursorPos.X;
end;

function TPopupClick.Area: Boolean;
begin
  Result := True;
  case Popup.HitArea(X, Y) of
    TAtlasHitArea.PanelBar:
      begin
        Popup.TogglePanel;
      end;
    TAtlasHitArea.Splitter:
      begin
        // Splitter: rechts liegendes Panel → Breite der Liste; links liegendes → Breite des Panels. Die Liste
        // bleibt am Wortanfang; ein links liegendes Panel wächst nach links.
        if Popup.FPanel.Left then
        begin
          StartDrag(TAtlasDragKind.PanelWidth, Popup.PanelWidth, -1);
        end
        else
        begin
          StartDrag(TAtlasDragKind.ListWidth, Popup.ListWidth, 1);
        end;
      end;
    TAtlasHitArea.Edge, TAtlasHitArea.Grip:
      begin
        // Rechter Rand: Panel rechts und offen → dessen Breite, sonst die der Liste.
        if Popup.FPanel.Shown and not Popup.FPanel.Left and not Popup.Collapsed then
        begin
          StartDrag(TAtlasDragKind.PanelWidth, Popup.PanelWidth, 1);
        end
        else
        begin
          StartDrag(TAtlasDragKind.ListWidth, Popup.ListWidth, 1);
        end;
      end;
  else
    Result := False;
  end;
end;

function TPopupClick.Overload: Boolean;
begin
  Result := False;
  if not Popup.FPanel.Shown or Popup.Collapsed or not Assigned(Popup.FEvents.OnOverload) then
  begin
    Exit;
  end;
  if PtInRect(Popup.FDetailView.PreviousRect, Point(X, Y)) then
  begin
    Popup.FEvents.OnOverload(-1);
    Result := True;
  end
  else if PtInRect(Popup.FDetailView.NextRect, Point(X, Y)) then
  begin
    Popup.FEvents.OnOverload(1);
    Result := True;
  end;
end;

procedure TPopupClick.OpenDocLink(AIndex: Integer);
begin
  // „Mehr/Weniger anzeigen“ (#770): Zugeklappt darf das Popup wieder schrumpfen.
  if Popup.FDetailView.Doc.Link(AIndex).Kind = TAtlasDocLinkKind.Toggle then
  begin
    if not Popup.FDetailView.ToggleDoc(Popup.Canvas) then
    begin
      Popup.FSessionHeight := 0;
    end;
    Popup.Relayout;
    Popup.Invalidate;
  end
  else if Assigned(Popup.FEvents.OnDocLink) then
  begin
    Popup.FEvents.OnDocLink(Popup.FDetailView.Doc.Link(AIndex), ssCtrl in Shift);
  end;
end;

function TPopupClick.Doc: Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if not Popup.DocActive then
  begin
    Exit;
  end;
  mIndex := Popup.FDetailView.DocLinkAt(X, Y);
  if mIndex >= 0 then
  begin
    OpenDocLink(mIndex);
    Result := True;
  end
  else if Popup.FDetailView.InDoc(X, Y) then
  begin
    Popup.FDetailView.Doc.StartSelection(Popup.Canvas, X - Popup.FDetailView.DocLeft, Y - Popup.FDetailView.DocTop);
    Popup.Invalidate;
    Result := True;
  end
  else if Popup.FDetailView.Doc.HasSelection then
  begin
    Popup.FDetailView.Doc.ClearSelection;
    Popup.Invalidate;
  end;
end;

function TPopupClick.Chip: Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to High(Popup.FChips.Rects) do
  begin
    if PtInRect(Popup.FChips.Rects[mIndex], Point(X, Y)) then
    begin
      if Assigned(Popup.FEvents.OnChip) then
      begin
        Popup.FEvents.OnChip(Popup.FChips.Kinds[mIndex]);
      end;
      Exit(True);
    end;
  end;
end;

function TPopupClick.Star: Boolean;
var
  mPosition: Integer;
begin
  mPosition := Popup.StarAt(X, Y);
  Result := mPosition >= 0;
  if Result and Assigned(Popup.FEvents.OnFavorite) then
  begin
    Popup.FEvents.OnFavorite(mPosition);
  end;
end;

procedure TPopupClick.Run;
var
  mHandled: Boolean;
  mPosition: Integer;
begin
  mHandled := Syntax or Area or Overload;
  if not mHandled then
  begin
    mHandled := Doc or Chip or Star;
  end;
  if not mHandled then
  begin
    mPosition := Popup.RowAt(X, Y);
    if (mPosition >= 0) and Assigned(Popup.FEvents.OnSelect) then
    begin
      Popup.FEvents.OnSelect(mPosition);
    end;
  end;
end;

{ TAtlasCompletionPopup }

procedure TAtlasCompletionPopup.ShowSyntax(const ANotice: TAtlasSyntaxNotice);
begin
  FSyntax := ANotice;
  FSyntaxLink := Rect(0, 0, 0, 0);
  if FSyntax.Trust <> TAtlasSyntaxTrust.Sure then
  begin
    // Die Leiste soll ganz lesbar sein: Breite wächst wie beim leeren Zustand.
    Canvas.Font := UIFont;
    FSessionWidth := Max(FSessionWidth, Canvas.TextWidth(TAtlasCompletionTexts.SyntaxLead(FSyntax.Trust) +
      TAtlasCompletionTexts.SyntaxLineText(FSyntax.Line)) + Scale(40));
    Canvas.Font := Font;
  end;
  if IsShown then
  begin
    Relayout;
  end;
  Invalidate;
end;

procedure TAtlasCompletionPopup.ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip; AVisible: Boolean);
var
  mShown: Integer;
  mChip: TAtlasChip;
begin
  FChips.Counts := ACounts;
  FChips.Active := AActive;
  // Nur sinnvoll, wenn es mehr als eine Art gibt.
  mShown := 0;
  for mChip := Succ(TAtlasChip.All) to High(TAtlasChip) do
  begin
    if ACounts[mChip] > 0 then
    begin
      Inc(mShown);
    end;
  end;
  FChips.Visible := AVisible and (mShown >= 2);
end;

procedure TAtlasCompletionPopup.ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
var
  mSameList: Boolean;
  mIndex: Integer;
begin
  // Nur die Auswahl bewegt (Pfeiltasten): dieselben Arrays, Breite nicht neu messen (#616).
  mSameList := not FEmpty.Showing and (Pointer(AItems) = Pointer(FItems)) and (Pointer(AOrder) = Pointer(FOrder)) and
    (APattern = FPattern) and IsShown;
  // Weitertippen verwirft den Hinweis der Fußzeile (#458).
  if APattern <> FPattern then
  begin
    FNotice := '';
  end;
  FEmpty.Showing := False;
  FItems := AItems;
  FOrder := AOrder;
  FSelected := ASelected;
  FPattern := APattern;
  FRestFrom := -1;
  for mIndex := 0 to High(FOrder) do
  begin
    if FOrder[mIndex] = TAtlasRanking.cRestHeader then
    begin
      FRestFrom := mIndex;
      Break;
    end;
  end;
  EnsureSelectedVisible;
  if mSameList then
  begin
    Relayout;
  end
  else
  begin
    PlaceAndShow;
  end;
  AnnounceSelected;
  // UI Automation (#447): neue Einträge melden, dann den gewählten.
  if AccessibleList <> nil then
  begin
    if not mSameList then
    begin
      AccessibleList.ItemsChanged;
    end;
    AccessibleList.SelectionChanged;
  end;
end;

procedure TAtlasCompletionPopup.AnnounceSelected;
var
  mKind: string;
begin
  if (FSelected < 0) or (FSelected > High(FOrder)) or TAtlasRanking.IsHeader(FOrder[FSelected]) then
  begin
    Exit;
  end;
  mKind := TAtlasCompletionTexts.KindText(FItems[FOrder[FSelected]].Kind);
  // Angeheftet (#458) mit ansagen.
  if FItems[FOrder[FSelected]].Favorite then
  begin
    if mKind <> '' then
    begin
      mKind := mKind + ', ';
    end;
    mKind := mKind + TAtlasCompletionStrings.Text(TAtlasCompletionTextId.AccessFavorite);
  end;
  Announce(TAtlasItemPresentation.Announcement(FItems[FOrder[FSelected]], mKind,
    TAtlasCompletionStrings.Text(TAtlasCompletionTextId.AccessPosition), FSelected + 1, Length(FOrder)));
end;

procedure TAtlasCompletionPopup.ShowNotice(const AText: string);
begin
  FNotice := AText;
  if AText <> '' then
  begin
    Announce(AText);
  end;
  Invalidate;
end;

procedure TAtlasCompletionPopup.HideList;
begin
  HideTip;
  HidePopup;
  FNotice := '';
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FTop := 0;
  FSessionWidth := 0;
  FSessionHeight := 0;
  FEmpty.Showing := False;
  FPanel.Shown := False;
  FPanel.AutoCollapsed := False;
  FDrag.Kind := TAtlasDragKind.None;
  FDetailView.Details := Default(TAtlasItemDetails);
  FDetailView.OverloadIndex := 0;
  FDetailView.OverloadCount := 0;
  FSyntax := Default(TAtlasSyntaxNotice);
  FSyntaxLink := Rect(0, 0, 0, 0);
end;

procedure TAtlasCompletionPopup.ShowEmpty(const APrefix: string; ATotal: Integer);
begin
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FRestFrom := -1;
  FTop := 0;
  FEmpty.Prefix := APrefix;
  FEmpty.Total := ATotal;
  FEmpty.Showing := True;
  if AccessibleList <> nil then
  begin
    AccessibleList.ItemsChanged;
  end;
  Canvas.Font := UIFont;
  FSessionWidth := Max(FSessionWidth, Max(Scale(cMinWidth),
    Canvas.TextWidth(TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.NoMatchesFor, [APrefix])) + Scale(32)));
  Canvas.Font := Font;
  Relayout;
end;

function TAtlasCompletionPopup.CreateAccessible(ARole: Integer; const AName: string): TAtlasAccessibleElement;
begin
  Result := TAtlasAccessibleList.Create(Handle, AName, Self);
end;

function TAtlasCompletionPopup.AccessibleList: TAtlasAccessibleList;
begin
  Result := nil;
  if AccessibleObject is TAtlasAccessibleList then
  begin
    Result := TAtlasAccessibleList(AccessibleObject);
  end;
end;

function TAtlasCompletionPopup.AccessibleCount: Integer;
begin
  Result := 0;
  if not FEmpty.Showing and IsShown then
  begin
    Result := Length(FOrder);
  end;
end;

function TAtlasCompletionPopup.AccessibleSelected: Integer;
begin
  Result := FSelected;
end;

function TAtlasCompletionPopup.AccessibleId(APosition: Integer): Integer;
begin
  // Index in FItems bleibt beim Filtern gleich; Überschriften sind negativ und kommen je Liste einmal vor.
  Result := FOrder[APosition];
end;

function TAtlasCompletionPopup.AccessibleName(APosition: Integer): string;
begin
  if TAtlasRanking.IsHeader(FOrder[APosition]) then
  begin
    Result := TAtlasCompletionTexts.HeaderText(FItems, FOrder, APosition);
  end
  else
  begin
    Result := FItems[FOrder[APosition]].Name;
  end;
end;

function TAtlasCompletionPopup.AccessibleStatus(APosition: Integer): string;
var
  mStatus: string;
  mTag: TAtlasTag;
begin
  Result := '';
  if TAtlasRanking.IsHeader(FOrder[APosition]) then
  begin
    Exit;
  end;
  // Dieselben Angaben wie die Tags der Zeile; nicht nur Farbe (#447).
  for mTag in ItemTags(FItems[FOrder[APosition]]) do
  begin
    if Result = '' then
    begin
      Result := mTag.Text;
    end
    else
    begin
      Result := Result + ', ' + mTag.Text;
    end;
  end;
  if FItems[FOrder[APosition]].Favorite then
  begin
    mStatus := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.AccessFavorite);
    if Result <> '' then
    begin
      Result := mStatus + ', ' + Result;
    end
    else
    begin
      Result := mStatus;
    end;
  end;
end;

function TAtlasCompletionPopup.AccessibleHelp(APosition: Integer): string;
begin
  Result := '';
  if not TAtlasRanking.IsHeader(FOrder[APosition]) then
  begin
    Result := TAtlasCompletionTexts.DetailText(FItems[FOrder[APosition]]);
  end;
end;

function TAtlasCompletionPopup.AccessibleIsHeader(APosition: Integer): Boolean;
begin
  Result := TAtlasRanking.IsHeader(FOrder[APosition]);
end;

function TAtlasCompletionPopup.AccessibleBounds(APosition: Integer; out ARect: TRect): Boolean;
begin
  Result := IsShown and (APosition >= FTop) and (APosition < FTop + RowCount) and (APosition <= High(FOrder));
  if not Result then
  begin
    ARect := TRect.Empty;
    Exit;
  end;
  ARect := RowRect(APosition - FTop);
  ARect.TopLeft := ClientToScreen(ARect.TopLeft);
  ARect.BottomRight := ClientToScreen(ARect.BottomRight);
end;

procedure TAtlasCompletionPopup.AccessibleSelect(APosition: Integer);
begin
  // Wie ein Klick auf die Zeile: Der Controller wählt und zeigt die Liste neu.
  if Assigned(FEvents.OnSelect) then
  begin
    FEvents.OnSelect(APosition);
  end;
end;

procedure TAtlasCompletionPopup.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mClick: TPopupClick;
begin
  inherited;
  if Button = mbLeft then
  begin
    mClick.Popup := Self;
    mClick.X := X;
    mClick.Y := Y;
    mClick.Shift := Shift;
    mClick.Run;
  end;
end;

procedure TAtlasCompletionPopup.DblClick;
var
  mPoint_: TPoint;
begin
  inherited;
  // Doppelklick auf den Griff: automatische Breiten (#416).
  mPoint_ := ScreenToClient(Mouse.CursorPos);
  if HitArea(mPoint_.X, mPoint_.Y) = TAtlasHitArea.Grip then
  begin
    FManualListWidth := 0;
    FPanel.Width := cDefaultPanelWidth;
    FDrag.Kind := TAtlasDragKind.None;
    Relayout;
    Invalidate;
    WidthsChanged;
    Exit;
  end;
  if (FSelected >= 0) and Assigned(FEvents.OnAccept) then
  begin
    FEvents.OnAccept(FSelected);
  end;
end;

procedure TAtlasCompletionPopup.DragTo;
var
  mWidth: Integer;
begin
  mWidth := Logical(FDrag.StartWidth + FDrag.Sign * (Mouse.CursorPos.X - FDrag.StartX));
  if FDrag.Kind = TAtlasDragKind.ListWidth then
  begin
    FManualListWidth := TAtlasPopupWidth.Fit(mWidth, cMinWidth, cMaxWidth);
  end
  else
  begin
    FPanel.Width := TAtlasPopupWidth.Fit(mWidth, TAtlasPopupWidth.cMinPanelWidth, TAtlasPopupWidth.cMaxPanelWidth);
  end;
  Relayout;
  Invalidate;
end;

procedure TAtlasCompletionPopup.UpdateCursor(AX, AY: Integer);
begin
  case HitArea(AX, AY) of
    TAtlasHitArea.Splitter: Cursor := crHSplit;
    TAtlasHitArea.Edge, TAtlasHitArea.Grip: Cursor := crSizeWE;
    TAtlasHitArea.PanelBar: Cursor := crHandPoint;
  else
    if (DocActive and (FDetailView.DocLinkAt(AX, AY) >= 0)) or (StarAt(AX, AY) >= 0) or
      PtInRect(FSyntaxLink, Point(AX, AY)) then
    begin
      Cursor := crHandPoint;
    end
    else if DocActive and FDetailView.InDoc(AX, AY) then
    begin
      Cursor := crIBeam;
    end
    else
    begin
      Cursor := crDefault;
    end;
  end;
end;

procedure TAtlasCompletionPopup.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mPosition: Integer;
begin
  inherited;
  if FDrag.Kind <> TAtlasDragKind.None then
  begin
    DragTo;
    Exit;
  end;
  // Markieren in der Doku (#654).
  if FDetailView.Doc.Selecting and (ssLeft in Shift) then
  begin
    FDetailView.Doc.ExtendSelection(Canvas, X - FDetailView.DocLeft, Y - FDetailView.DocTop);
    Invalidate;
    Exit;
  end;
  UpdateCursor(X, Y);
  if DocActive and (FDetailView.DocLinkAt(X, Y) <> FDetailView.Doc.HotLink) then
  begin
    FDetailView.Doc.HotLink := FDetailView.DocLinkAt(X, Y);
    Invalidate;
  end;
  mPosition := RowAt(X, Y);
  if mPosition = FHoverPosition then
  begin
    Exit;
  end;
  HideTip;
  FHoverPosition := mPosition;
  FTipTimer.Enabled := mPosition >= 0;
  // Der leere Stern (#458) folgt der Maus.
  if FOptions.FavoritesEnabled then
  begin
    Invalidate;
  end;
end;

procedure TAtlasCompletionPopup.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if FDetailView.Doc.Selecting then
  begin
    FDetailView.Doc.EndSelection;
    Invalidate;
  end;
  if FDrag.Kind = TAtlasDragKind.None then
  begin
    Exit;
  end;
  FDrag.Kind := TAtlasDragKind.None;
  WidthsChanged;
end;

function TAtlasCompletionPopup.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  HideTip;
  // Über dem Panel scrollt die Doku, wenn sie höher als das Popup ist (#654).
  if DocActive and FDetailView.Doc.CanScroll and PtInRect(PanelRect, ScreenToClient(MousePos)) then
  begin
    if WheelDelta > 0 then
    begin
      FDetailView.ScrollDoc(-Max(1, WheelDelta div WHEEL_DELTA));
    end
    else
    begin
      FDetailView.ScrollDoc(Max(1, -WheelDelta div WHEEL_DELTA));
    end;
    Invalidate;
    Exit;
  end;
  if WheelDelta > 0 then
  begin
    FTop := Max(0, FTop - 3);
  end
  else
  begin
    FTop := Min(Max(0, Length(FOrder) - FVisibleRows), FTop + 3);
  end;
  Invalidate;
end;

end.
