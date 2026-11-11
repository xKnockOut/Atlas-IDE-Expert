unit Atlas.UI.Completion.PopupState;

// Vervollständigungs-Popup (#410), unterste Stufe: Typen, Zustand und gemessene Höhen. Die Klasse ist nach
// Aufgaben in eine Kette geteilt, damit jede Stufe überschaubar bleibt:
//   TAtlasCompletionPopupState (Zustand, Höhen) → TAtlasCompletionPopupLayout (Lage von Liste, Panel und
//   Fenster, Panel-Schnittstelle) → TAtlasCompletionPopupPainter (Zeichnen, Tooltip) → TAtlasCompletionPopup
//   (Atlas.UI.Completion.Popup: Maus, Anzeige der Liste, Barrierefreiheit).
// Aufrufer verwenden nur TAtlasCompletionPopup; Beschreibung des Aussehens dort.

interface

uses
  Vcl.Controls,
  Winapi.Messages,
  System.Classes,
  System.Types,
  Vcl.ExtCtrls,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Width,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Documentation.Layout,
  Atlas.UI.Popup.Window,
  Atlas.UI.Popup.Tip,
  Atlas.UI.Completion.Details;

type
  TAtlasPositionEvent = reference to procedure(APosition: Integer);
  /// <summary>Gezogene Breiten in logischen Pixeln; AListWidth 0 = automatisch.</summary>
  TAtlasWidthsEvent = reference to procedure(AListWidth, APanelWidth: Integer);
  TAtlasPanelEvent = reference to procedure(ACollapsed: Boolean);
  /// <summary>Klick auf die Zeilenangabe der Warnleiste (#457); 0-basiert.</summary>
  TAtlasSyntaxLineEvent = reference to procedure(ALine, ACharacter: Integer);

{$SCOPEDENUMS ON}
  TAtlasChipEvent = reference to procedure(AChip: TAtlasChip);
  TAtlasOverloadEvent = reference to procedure(ADelta: Integer);
  /// <summary>Klick auf einen Verweis bzw. Link der XMLDoc im Panel (#654); AControl bei Strg+Klick.</summary>
  TAtlasDocLinkEvent = reference to procedure(const ALink: TAtlasDocLink; AControl: Boolean);
  TAtlasDragKind = (None, ListWidth, PanelWidth);
  TAtlasHitArea = (None, Splitter, Edge, Grip, PanelBar);
{$SCOPEDENUMS OFF}

  /// <summary>Zeilen-, Chip- und Fußzeilenhöhe: einmal gemessen, neu nach Schrift- oder Dichtewechsel.
  /// </summary>
  TAtlasPopupMetrics = record
    RowHeight: Integer;
    ChipsHeight: Integer;
    FooterHeight: Integer;
    /// <summary>Dichte bei der Messung; Scale hängt an PPI, auch wenn die Schrift gleich bleibt.</summary>
    PPI: Integer;
    Valid: Boolean;
  end;

  /// <summary>Detailpanel (#424): Bereich, Seite, eingeklappt (#428) und Breite (#416).</summary>
  TAtlasPopupPanel = record
    /// <summary>Panelbereich in dieser Sitzung belegt.</summary>
    Shown: Boolean;
    /// <summary>Panel links der Liste (rechts kein Platz).</summary>
    Left: Boolean;
    /// <summary>Vom Benutzer eingeklappt (Strg+Q, Klick auf die Leiste).</summary>
    Collapsed: Boolean;
    /// <summary>Weder rechts noch links Platz: für diese Lage eingeklappt.</summary>
    AutoCollapsed: Boolean;
    /// <summary>Breite in logischen Pixeln.</summary>
    Width: Integer;
  end;

  /// <summary>Filter-Chips (#422): Anzahlen, aktiver Chip und die zuletzt gezeichneten Flächen.</summary>
  TAtlasPopupChips = record
    Counts: TAtlasChipCounts;
    Active: TAtlasChip;
    Visible: Boolean;
    Rects: TArray<TRect>;
    Kinds: TArray<TAtlasChip>;
  end;

  /// <summary>Leerer Zustand (#423): Präfix ohne Treffer und Gesamtzahl.</summary>
  TAtlasPopupEmpty = record
    Showing: Boolean;
    Prefix: string;
    Total: Integer;
  end;

  /// <summary>Ziehen einer Breite (#416) in Bildschirmkoordinaten.</summary>
  TAtlasPopupDrag = record
    Kind: TAtlasDragKind;
    StartX: Integer;
    StartWidth: Integer;
    /// <summary>-1, wenn Ziehen nach links verbreitert (Panel links der Liste).</summary>
    Sign: Integer;
  end;

  /// <summary>Ereignisse des Popups.</summary>
  TAtlasPopupEvents = record
    OnSelect: TAtlasPositionEvent;
    OnAccept: TAtlasPositionEvent;
    OnWidthsChanged: TAtlasWidthsEvent;
    OnPanelToggled: TAtlasPanelEvent;
    OnChip: TAtlasChipEvent;
    OnOverload: TAtlasOverloadEvent;
    OnDocLink: TAtlasDocLinkEvent;
    OnFavorite: TAtlasPositionEvent;
    OnSyntaxLine: TAtlasSyntaxLineEvent;
  end;

  /// <summary>Einstellungen der Darstellung (Beschreibung an den Eigenschaften von TAtlasCompletionPopup).</summary>
  TAtlasPopupOptions = record
    DimInherited: Boolean;
    ShowVariantBranch: Boolean;
    Limited: Boolean;
    Target: string;
    FavoritesEnabled: Boolean;
    SelectionMarker: Boolean;
  end;

  TAtlasCompletionPopupState = class(TAtlasPopupWindow)
  public const
    cDefaultVisibleRows = 9;
    cMinWidth = TAtlasPopupWidth.cMinListWidth;
    cMaxWidth = TAtlasPopupWidth.cMaxListWidth;
    cDefaultPanelWidth = 320;
    cCollapsedPanelWidth = 22;
  protected const
    /// <summary>Platz für das Kontrollkästchen im Mengenmodus (#448): Rand 7, Kästchen 13, Abstand 6.</summary>
    cCheckWidth = 19;
    /// <summary>Sternspalte der Favoriten (#458): Rand 4, Stern 12; das Badge rückt um so viel nach rechts.</summary>
    cStarWidth = 14;
  protected
    FItems: TAtlasCompletionItems;
    FOrder: TArray<Integer>;
    FSelected: Integer;
    FTop: Integer;
    FVisibleRows: Integer;
    FAnchor: TRect;
    FPattern: string;
    /// <summary>Position der Überschrift „Weitere Einträge“ (#497); -1 ohne.</summary>
    FRestFrom: Integer;
    FSessionWidth: Integer;
    FSessionHeight: Integer;
    FEmpty: TAtlasPopupEmpty;
    FDetailView: TAtlasDetailView;
    FPanel: TAtlasPopupPanel;
    /// <summary>Gezogene Breite der Liste in logischen Pixeln, 0 = automatisch (#416).</summary>
    FManualListWidth: Integer;
    FMetrics: TAtlasPopupMetrics;
    FChips: TAtlasPopupChips;
    // Unvollständiger Code (#457): Hinweis und Fläche der Zeilenangabe.
    FSyntax: TAtlasSyntaxNotice;
    FSyntaxLink: TRect;
    // Hinweis in der Fußzeile (#458).
    FNotice: string;
    // Tooltip für gekürzte Zeilen (#420): je sichtbarer Zeile gekürzt ja/nein, Zeile unter der Maus.
    FTip: TAtlasTextTip;
    FTipTimer: TTimer;
    FTruncated: TArray<Boolean>;
    FHoverPosition: Integer;
    FDrag: TAtlasPopupDrag;
    FEvents: TAtlasPopupEvents;
    FOptions: TAtlasPopupOptions;
    // Gerade gezeichnete Zeile: gedämpft (#419, #476, #497) bzw. Aktion in Akzentfarbe (#444).
    FDimRow: Boolean;
    FActionRow: Boolean;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
    procedure InvalidateMetrics;
    procedure EnsureMetrics;
    function Pad: Integer;
    function RowHeight: Integer;
    function FooterHeight: Integer;
    function ScrollReserve: Integer;
    function RowCount: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

uses
  System.Math,
  Atlas.UI.Popup.Accessibility,
  Atlas.UI.Strings;

const
  /// <summary>Verweilen auf einer gekürzten Zeile, bis der volle Text erscheint (#420).</summary>
  cTipDelayMs = 600;

{ TAtlasCompletionPopupState }

constructor TAtlasCompletionPopupState.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  SetAccessible(cUiaListControlType, TAtlasStrings.Text(TAtlasTextId.AccessCompletion));
  FVisibleRows := cDefaultVisibleRows;
  FSelected := -1;
  FRestFrom := -1;
  FDetailView := TAtlasDetailView.Create;
  FHoverPosition := -1;
  FTip := TAtlasTextTip.Create(Self);
  FTipTimer := TTimer.Create(Self);
  FTipTimer.Enabled := False;
  FTipTimer.Interval := cTipDelayMs;
  FPanel.Width := cDefaultPanelWidth;
  FOptions.SelectionMarker := True;
  FOptions.ShowVariantBranch := True;
end;

destructor TAtlasCompletionPopupState.Destroy;
begin
  FDetailView.Free;
  inherited Destroy;
end;

procedure TAtlasCompletionPopupState.CMFontChanged(var Message: TMessage);
begin
  // Erst die Basis: sie leitet die UI-Schrift aus der Editorschrift ab.
  inherited;
  InvalidateMetrics;
end;

procedure TAtlasCompletionPopupState.InvalidateMetrics;
begin
  FMetrics.Valid := False;
end;

procedure TAtlasCompletionPopupState.EnsureMetrics;
var
  mUIHeight: Integer;
begin
  // Dichte zusätzlich prüfen: Scale hängt an PPI, auch wenn die Schrift gleich bleibt.
  if FMetrics.Valid and (FMetrics.PPI = PPI) then
  begin
    Exit;
  end;
  Canvas.Font := UIFont;
  mUIHeight := Canvas.TextHeight('Wg');
  Canvas.Font := Font;
  FMetrics.RowHeight := Max(Canvas.TextHeight('Wg') + Scale(9), Scale(24));
  FMetrics.ChipsHeight := mUIHeight + Scale(12);
  FMetrics.FooterHeight := mUIHeight + Scale(10);
  FMetrics.PPI := PPI;
  FMetrics.Valid := True;
end;

function TAtlasCompletionPopupState.Pad: Integer;
begin
  Result := Scale(4);
end;

function TAtlasCompletionPopupState.RowHeight: Integer;
begin
  EnsureMetrics;
  Result := FMetrics.RowHeight;
end;

function TAtlasCompletionPopupState.FooterHeight: Integer;
begin
  EnsureMetrics;
  Result := FMetrics.FooterHeight;
end;

function TAtlasCompletionPopupState.ScrollReserve: Integer;
begin
  Result := Scale(8);
end;

function TAtlasCompletionPopupState.RowCount: Integer;
begin
  Result := Min(FVisibleRows, Length(FOrder));
end;

end.
