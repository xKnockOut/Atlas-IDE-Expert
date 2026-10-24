unit Atlas.Core.Hover.Layout;

// Satz des Hover-Tooltips ohne VCL (P-09): Build rechnet aus dem Inhalt
// (TAtlasHoverView), der Breite und einem Mess-Rückruf alle Positionen,
// Klickflächen und Zeichenbausteine aus; das Fenster (Atlas.UI.Hover.Tip)
// zeichnet nur noch die Bausteine in Reihenfolge. Gebaut wird je Inhalt,
// Breite und Doku-Höhe, nicht je Paint oder Mausbewegung. Der Hot-Zustand
// (Maus über Link, Kette, Pfad, Aktion) ändert nur Farben, Unterstreichung und
// Linienstärke; dafür trägt ein Baustein Art und Index der Klickfläche.
// Aufbau wie bisher: Pfadzeile (angeheftet), Wert im Debugger (#891), Probleme, Kopfzeile, Deklaration
// mit Verweisen, Beschreibung mit Platz für die XMLDoc, Vererbung bzw.
// Zieltyp und Aktionsleiste auf Randflächen; die letzte Randfläche sitzt beim
// Zeichnen am unteren Fensterrand (Anchor).
// Unter einem Hinweis zu einem uses-Eintrag (#621) stehen seine Aktionen als
// Links: Entfernen, Alle ungenutzten entfernen (ab zwei), In implementation-uses
// verschieben; ihre Klickfläche trägt Problem und Aktion (ProblemActionCode).
// Befund-Hover (#909): Fehler zuerst, je Befund eine Schweregrad-Pille (Error,
// Warnung, Info) vor der Meldung, darunter klein „Atlas · Regel-ID“ bzw.
// „dcc · W1036“, die Konfidenz, wenn sie nicht hoch ist, und mit
// Input.ProblemActions die Aktionszeile „Alt+Enter: <Korrektur>“ (nur mit
// Korrektur), „Für diese Zeile unterdrücken“, „Regel einstellen…“.
// Weitere Stellen eines Befunds (relatedInformation, #896) stehen darunter als
// Links, beim Unit-Zyklus als Pfad „uC → uA → uB → uC“ und mit „Graph
// zeigen“; ihre Klickfläche trägt Problem, Aktion Related und die Stelle.
// Bei Komponentenklassen (#110) folgt unter der Beschreibung „published: n
// Properties · m Ereignisse“ mit den Schaltern „geerbte“ und „nur mit
// default“, dann die Tabellen PROPERTIES (Name, Typ, Vorgabe, deklariert in)
// und EREIGNISSE, je auf- und zuklappbar und auf die ersten Zeilen gekürzt
// („+ n weitere …“ zeigt alle), und die Standard-Property einer Array-Property.
// Die Schalter tragen die Klickfläche Published mit Ord(TAtlasHoverPublishedToggle);
// TAtlasHoverView.Toggle schaltet um. Strg+C heißt dann „Liste kopieren“.

interface

uses
  System.Types,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.History,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Hover.DebugValue;

type
  {$SCOPEDENUMS ON}
  TAtlasHoverAction = (Navigate, Usages, Copy, Help);
  /// <summary>Schriften des Tooltips: UI, Editorschrift, beide verkleinert, Badge.</summary>
  TAtlasHoverFont = (Ui, Mono, SmallUi, SmallMono, Badge);
  /// <summary>DebugFix: Korrektur unter „kein Zugriff“ (#840), Index in View.DebugValue.Note.Fixes.</summary>
  TAtlasHoverHitKind = (Link, Ancestor, Path, Back, Action, ProblemAction, Published, DebugFix);
  /// <summary>Schalter der published-Mitglieder (#110): geerbte zeigen, nur mit Vorgabe, Abschnitte zu- bzw.
  /// aufklappen, alle Zeilen zeigen.</summary>
  TAtlasHoverPublishedToggle = (ShowInherited, OnlyDefaults, Properties, Events, MoreProperties, MoreEvents);
  /// <summary>Aktion unter einem Problem im Tooltip (#621). Related: Sprung zu einer weiteren Stelle (#896),
  /// ShowGraph: Unit-Beziehungen zeigen (#896).</summary>
  TAtlasHoverProblemAction = (RemoveUses, RemoveAllUses, MoveUses, Fix, SuppressLine, Configure, Related, ShowGraph);
  /// <summary>Fill: Fläche; Line: waagrechte Linie; Text: Text ab Rect.TopLeft; CenterText: zentriert in
  /// Rect; Frame: umrandetes Rechteck mit Fläche Back; RoundFill: gefülltes Rechteck mit Radius; Block:
  /// umbrechender Text in Rect (UI-Schrift, Ellipse); Styled: eingefärbte Deklaration From..Till; Doc: XMLDoc
  /// ab Rect.TopLeft.</summary>
  TAtlasHoverItemKind = (Fill, Line, Text, CenterText, Frame, RoundFill, Block, Styled, Doc);
  {$SCOPEDENUMS OFF}

  /// <summary>Was der Tooltip zeigt: Inhalt, Pfad und Zustand.</summary>
  TAtlasHoverView = record
    Data: TAtlasHoverData;
    Path: TArray<TAtlasHoverPathItem>;
    Pinned: Boolean;
    CanGoBack: Boolean;
    /// <summary>Anzahl der Verwendungen, wenn bekannt; sonst -1.</summary>
    UsagesCount: Integer;
    /// <summary>Probleme an der Mausposition (#398).</summary>
    Problems: TArray<TAtlasProblem>;
    /// <summary>Wert des Ausdrucks unter der Maus im angehaltenen Debugger (#891).</summary>
    DebugValue: TAtlasDebugValue;
    /// <summary>Anzeige der XMLDoc (#654): Angabe des Servers bzw. Einstellungen des Plugins.</summary>
    Display: TAtlasDocDisplay;
    /// <summary>published-Mitglieder (#110): geerbte ausblenden, nur Properties mit Vorgabe, Abschnitte
    /// zugeklappt, alle Zeilen statt der ersten.</summary>
    HideInherited: Boolean;
    OnlyDefaults: Boolean;
    PropertiesCollapsed: Boolean;
    EventsCollapsed: Boolean;
    AllProperties: Boolean;
    AllEvents: Boolean;
    class function Create(const AData: TAtlasHoverData): TAtlasHoverView; static;
    /// <summary>Schaltet den Schalter AToggle der published-Mitglieder um (#110).</summary>
    procedure Toggle(AToggle: TAtlasHoverPublishedToggle);
  end;

  TAtlasHoverFace = record
    Font: TAtlasHoverFont;
    Bold: Boolean;
    Underline: Boolean;
    class function Create(AFont: TAtlasHoverFont; ABold, AUnderline: Boolean): TAtlasHoverFace; static;
  end;

  /// <summary>Messen in der Oberfläche; Build ruft nur diese Funktionen.</summary>
  IAtlasHoverMeasure = interface
    function TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
    /// <summary>Zeilenhöhe der Schrift (Höhe von „Wg“).</summary>
    function TextHeight(const AFace: TAtlasHoverFace): Integer;
    /// <summary>Höhe von AText in der UI-Schrift, umbrochen an Wortgrenzen auf AWidth.</summary>
    function BlockHeight(const AText: string; AWidth: Integer): Integer;
    /// <summary>Breite der eingefärbten Deklaration [AFrom, ATill) in der Editorschrift.</summary>
    function DeclarationWidth(AFrom, ATill: Integer): Integer;
    /// <summary>Zeilen der eingefärbten Deklaration bei Umbruch an Leerzeichen.</summary>
    function DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
  end;

  /// <summary>Texte der Oberfläche in ihrer Sprache (Core kennt Atlas.UI.Strings nicht).</summary>
  TAtlasHoverTexts = record
    /// <summary>Art zu View.Data.Kind (Klasse, Methode …); '' wenn unbekannt.</summary>
    KindCaption: string;
    Pinned: string;
    Inheritance: string;
    /// <summary>Format mit %s für den Typ der Kette.</summary>
    TargetType: string;
    /// <summary>Format mit %s für den Titel.</summary>
    Navigate: string;
    Usages: string;
    /// <summary>Format mit %d für die Anzahl.</summary>
    UsagesCount: string;
    Copy: string;
    CopySelection: string;
    Help: string;
    KeyUsages: string;
    KeyCopy: string;
    SourceAtlas: string;
    SourceCompiler: string;
    SourceInactive: string;
    /// <summary>Herkunft eines uses-Hinweises und seine Aktionen (#621).</summary>
    SourceUses: string;
    UsesRemove: string;
    UsesRemoveAll: string;
    UsesMove: string;
    /// <summary>„Graph zeigen“ unter einem Unit-Zyklus (#896); '' = kein Link.</summary>
    ShowGraph: string;
    /// <summary>Befund-Hover (#909): Pillen je Art und die Aktionen unterdrücken und einstellen.</summary>
    KindError: string;
    KindWarning: string;
    KindInfo: string;
    Suppress: string;
    Configure: string;
    Stale: string;
    /// <summary>Zusatz eines vom Build bestätigten Befunds (#1024): „vom Compiler bestätigt“; mit Code
    /// „vom Compiler bestätigt (%s)“.</summary>
    Confirmed: string;
    ConfirmedCode: string;
    /// <summary>Statt des Werts, solange der Debugger noch auswertet (#891).</summary>
    DebugPending: string;
    /// <summary>„kein Zugriff“ (#840): solange die Ursache ermittelt wird, Überschrift der geprüften Punkte.
    /// </summary>
    DebugExplaining: string;
    DebugChecked: string;
    /// <summary>published-Mitglieder (#110): Format mit %d, %d für Properties und Ereignisse; Schalter,
    /// Abschnitte, Spaltenköpfe, Formate „+ %d weitere …“, Hinweise und „Liste kopieren“.</summary>
    PublishedSummary: string;
    PublishedInherited: string;
    PublishedOnlyDefaults: string;
    PublishedProperties: string;
    PublishedEvents: string;
    PublishedName: string;
    PublishedType: string;
    PublishedDefault: string;
    PublishedDeclared: string;
    PublishedImplicit: string;
    PublishedMoreProperties: string;
    PublishedMoreEvents: string;
    PublishedEventsNote: string;
    PublishedArrayProperty: string;
    PublishedDefaultProperty: string;
    PublishedDefaultPropertyNote: string;
    PublishedCopyList: string;
    PublishedVclNote: string;
    /// <summary>Zeile „Konfidenz: …“ je Problem in der Reihenfolge von View.Problems; '' ohne (auch bei hoher
    /// Konfidenz, #909).</summary>
    Confidences: TArray<string>;
  end;

  TAtlasHoverItem = record
    Kind: TAtlasHoverItemKind;
    Rect: TRect;
    Text: string;
    Face: TAtlasHoverFace;
    Color: TAtlasColor;
    /// <summary>Farbe, solange die Klickfläche HotKind/HotIndex unter der Maus ist.</summary>
    HotColor: TAtlasColor;
    /// <summary>Fläche von Frame.</summary>
    Back: TAtlasColor;
    /// <summary>Radius von Frame und RoundFill in logischen Pixeln.</summary>
    Radius: Integer;
    PenWidth: Integer;
    HotPenWidth: Integer;
    HotUnderline: Boolean;
    HotKind: TAtlasHoverHitKind;
    /// <summary>-1: hängt an keiner Klickfläche.</summary>
    HotIndex: Integer;
    From: Integer;
    Till: Integer;
  end;

  TAtlasHoverHit = record
    Kind: TAtlasHoverHitKind;
    Index: Integer;
    Rect: TRect;
  end;

  TAtlasHoverInput = record
    View: TAtlasHoverView;
    Width: Integer;
    PPI: Integer;
    Colors: TAtlasColors;
    Texts: TAtlasHoverTexts;
    /// <summary>XMLDoc vorhanden und ihre (begrenzte) Höhe.</summary>
    HasDoc: Boolean;
    DocHeight: Integer;
    /// <summary>Markierung in der Doku: Aktion „Auswahl kopieren“ statt „Deklaration kopieren“.</summary>
    HasSelection: Boolean;
    /// <summary>Aktionszeile unter Regelbefunden (hover.problemActions, #909).</summary>
    ProblemActions: Boolean;
    /// <summary>problems.showCompilerCode aus (#1024): Meldungen ohne „(wie E2035)“, Bestätigung ohne Code.</summary>
    HideCompilerCode: Boolean;
  end;

  TAtlasHoverLayout = record
    Items: TArray<TAtlasHoverItem>;
    Hits: TArray<TAtlasHoverHit>;
    Height: Integer;
    DocLeft: Integer;
    DocTop: Integer;
    /// <summary>Letzte Randfläche: erster Baustein und erste Klickfläche (-1 ohne), Lage und Verschiebung.</summary>
    AnchorItem: Integer;
    AnchorHit: Integer;
    AnchorTop: Integer;
    AnchorHeight: Integer;
    AnchorShift: Integer;
    /// <summary>Erstes Problem (Index in View.Problems) mit „Alt+Enter: …“ im Hover, -1 ohne (#909).</summary>
    FixProblem: Integer;
    class function Build(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure): TAtlasHoverLayout;
      static;
    /// <summary>Index der Klickfläche ProblemAction: Problem in View.Problems und Aktion (#621).</summary>
    class function ProblemActionCode(AProblem: Integer; AAction: TAtlasHoverProblemAction): Integer; overload;
      static;
    /// <summary>Wie oben mit der Stelle AItem in Problem.Related (Aktion Related, #896); 0 bis MaxRelated - 1.
    /// </summary>
    class function ProblemActionCode(AProblem: Integer; AAction: TAtlasHoverProblemAction; AItem: Integer): Integer;
      overload; static;
    class procedure DecodeProblemAction(ACode: Integer; out AProblem: Integer;
      out AAction: TAtlasHoverProblemAction); overload; static;
    class procedure DecodeProblemAction(ACode: Integer; out AProblem: Integer;
      out AAction: TAtlasHoverProblemAction; out AItem: Integer); overload; static;
    /// <summary>Reihenfolge der Probleme im Hover: Fehler zuerst, sonst wie geliefert (#909).</summary>
    class function ProblemOrder(const AProblems: TArray<TAtlasProblem>): TArray<Integer>; static;
    /// <summary>Nächste (AForward) bzw. vorige Klickfläche ProblemAction nach AHot (Index in Hits, -1 vor der
    /// ersten), reihum; -1 ohne solche Klickfläche. Für Tab im Hover (#909).</summary>
    function NextProblemHit(AHot: Integer; AForward: Boolean): Integer;
    /// <summary>Index der Klickfläche unter APoint; -1 ohne.</summary>
    function HitAt(const APoint: TPoint): Integer;
    /// <summary>Ist die Klickfläche AHot (Index in Hits) von Art AKind und Index AIndex?</summary>
    function IsHot(AHot: Integer; AKind: TAtlasHoverHitKind; AIndex: Integer): Boolean;
    /// <summary>Letzte Randfläche an den unteren Rand eines Fensters der Höhe AClientHeight schieben (nie
    /// nach oben über ihre Lage hinaus); wiederholbar.</summary>
    procedure Anchor(AClientHeight: Integer);
  end;

/// <summary>Badge-Art zum Kürzel aus TAtlasHoverData.Badge.</summary>
function HoverBadgeKind(const ACode: string): TAtlasBadgeKind;

implementation

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  Atlas.Core.Problems.Colors;

const
  BandChain = 0;
  BandActions = 1;
  /// <summary>So viele Zeilen zeigen die Tabellen der published-Mitglieder, bis „+ n weitere“ geklickt ist.
  /// </summary>
  PropertyRows = 7;
  EventRows = 4;
  /// <summary>Höchstens so viele weitere Stellen je Problem im Hover (#896).</summary>
  MaxRelated = 64;

type
  TBuilder = class
  private
    FInput: TAtlasHoverInput;
    FMeasure: IAtlasHoverMeasure;
    FData: TAtlasHoverData;
    FColors: TAtlasColors;
    FItems: TArray<TAtlasHoverItem>;
    FItemCount: Integer;
    FHits: TArray<TAtlasHoverHit>;
    FHitCount: Integer;
    FLeft, FRight, FY, FX, FRowHeight, FLineHeight: Integer;
    FFlowFont: TAtlasHoverFont;
    FNoWrap: Boolean;
    FLayout: TAtlasHoverLayout;
    function Scale(AValue: Integer): Integer;
    function Face(AFont: TAtlasHoverFont; ABold: Boolean): TAtlasHoverFace;
    function Height(const AFace: TAtlasHoverFace): Integer;
    function Width(const AFace: TAtlasHoverFace; const AText: string): Integer;
    function NewItem(AKind: TAtlasHoverItemKind; const ARect: TRect; AColor: TAtlasColor): TAtlasHoverItem;
    procedure Add(const AItem: TAtlasHoverItem);
    procedure Insert(AAt: Integer; const AItem: TAtlasHoverItem);
    procedure AddHit(AKind: TAtlasHoverHitKind; AIndex: Integer; const ARect: TRect);
    procedure AddText(AX, AY: Integer; const AText: string; const AFace: TAtlasHoverFace; AColor: TAtlasColor);
    procedure AddLine(ALeft, ATop, ARight: Integer; AColor: TAtlasColor);
    procedure HorizontalLine(ATop: Integer);
    procedure Block(const AText: string; AColor: TAtlasColor; AMaxLines: Integer);
    /// <summary>Fließtext mit Umbruch; AIndex >= 0 legt eine Klickfläche an. AHotIndex >= 0: bei Hot
    /// AHotColor und unterstrichen.</summary>
    procedure Flow(const AText: string; AColor: TAtlasColor; ABold: Boolean; AKind: TAtlasHoverHitKind;
      AIndex, AHotIndex: Integer; AHotColor: TAtlasColor);
    procedure EndFlow;
    procedure Chip(const AText: string; ACurrent: Boolean; AIndex: Integer);
    procedure ActionItem(const AKey, ACaption: string; AAction: TAtlasHoverAction; AEnabled: Boolean);
    procedure ProblemLink(const ACaption: string; AProblem: Integer; AAction: TAtlasHoverProblemAction);
    /// <summary>Weitere Stellen eines Problems als Links (#896), beim Unit-Zyklus als Pfad mit „Graph zeigen“.
    /// </summary>
    procedure RelatedLinks(const AProblem: TAtlasProblem; AIndex: Integer);
    /// <summary>Pille mit der Art des Befunds (#909); setzt FLeft hinter die Pille für die Meldung.</summary>
    procedure SeverityPill(const AProblem: TAtlasProblem);
    procedure RuleActions(const AProblem: TAtlasProblem; AIndex: Integer);
    procedure BandContent(AKind: Integer);
    procedure Band(AKind: Integer; ALast: Boolean);
    procedure DrawPart(AFrom, ATill: Integer);
    procedure Navigation;
    procedure DebugValue;
    procedure DebugNote(const ANote: TAtlasDebugValueNote);
    procedure Problems;
    procedure Header;
    procedure Declaration;
    procedure Description;
    procedure ToggleChip(const ACaption: string; AOn: Boolean; AToggle: TAtlasHoverPublishedToggle; AX: Integer);
    procedure MemberSection(AEvents: Boolean);
    procedure PublishedMembers;
    procedure Run;
  public
    constructor Create(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure);
    function Layout: TAtlasHoverLayout;
  end;

function HoverBadgeKind(const ACode: string): TAtlasBadgeKind;
begin
  case IndexStr(ACode, ['ty', 'fn', 'pp', 'fd', 'va', 'co', 'un']) of
    0: Result := TAtlasBadgeKind.Type_;
    1: Result := TAtlasBadgeKind.Function_;
    2: Result := TAtlasBadgeKind.Property_;
    3: Result := TAtlasBadgeKind.Field;
    4: Result := TAtlasBadgeKind.Variable;
    5: Result := TAtlasBadgeKind.Constant;
    6: Result := TAtlasBadgeKind.Unit_;
  else
    Result := TAtlasBadgeKind.Keyword;
  end;
end;

{ TAtlasHoverView }

class function TAtlasHoverView.Create(const AData: TAtlasHoverData): TAtlasHoverView;
begin
  Result := Default(TAtlasHoverView);
  Result.Data := AData;
  Result.UsagesCount := -1;
  Result.Display := TAtlasDocDisplay.Create(TAtlasDocExpand.Last, 0);
end;

procedure TAtlasHoverView.Toggle(AToggle: TAtlasHoverPublishedToggle);
begin
  case AToggle of
    TAtlasHoverPublishedToggle.ShowInherited: HideInherited := not HideInherited;
    TAtlasHoverPublishedToggle.OnlyDefaults: OnlyDefaults := not OnlyDefaults;
    TAtlasHoverPublishedToggle.Properties: PropertiesCollapsed := not PropertiesCollapsed;
    TAtlasHoverPublishedToggle.Events: EventsCollapsed := not EventsCollapsed;
    TAtlasHoverPublishedToggle.MoreProperties: AllProperties := not AllProperties;
    TAtlasHoverPublishedToggle.MoreEvents: AllEvents := not AllEvents;
  end;
end;

{ TAtlasHoverFace }

class function TAtlasHoverFace.Create(AFont: TAtlasHoverFont; ABold, AUnderline: Boolean): TAtlasHoverFace;
begin
  Result.Font := AFont;
  Result.Bold := ABold;
  Result.Underline := AUnderline;
end;

{ TBuilder }

constructor TBuilder.Create(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure);
begin
  inherited Create;
  FInput := AInput;
  FMeasure := AMeasure;
  FData := AInput.View.Data;
  FColors := AInput.Colors;
  FItems := nil;
  FHits := nil;
  FLayout := Default(TAtlasHoverLayout);
  FLayout.AnchorItem := -1;
  FLayout.AnchorHit := -1;
  FLayout.FixProblem := -1;
end;

function TBuilder.Scale(AValue: Integer): Integer;
begin
  // Wie MulDiv(AValue, PPI, 96): auf ganze Pixel gerundet.
  Result := (AValue * FInput.PPI + 48) div 96;
end;

function TBuilder.Face(AFont: TAtlasHoverFont; ABold: Boolean): TAtlasHoverFace;
begin
  Result := TAtlasHoverFace.Create(AFont, ABold, False);
end;

function TBuilder.Height(const AFace: TAtlasHoverFace): Integer;
begin
  Result := FMeasure.TextHeight(AFace);
end;

function TBuilder.Width(const AFace: TAtlasHoverFace; const AText: string): Integer;
begin
  Result := FMeasure.TextWidth(AFace, AText);
end;

function TBuilder.NewItem(AKind: TAtlasHoverItemKind; const ARect: TRect; AColor: TAtlasColor): TAtlasHoverItem;
begin
  Result := Default(TAtlasHoverItem);
  Result.Kind := AKind;
  Result.Rect := ARect;
  Result.Color := AColor;
  Result.HotColor := AColor;
  Result.PenWidth := 1;
  Result.HotPenWidth := 1;
  Result.HotIndex := -1;
  Result.Face := Face(TAtlasHoverFont.Ui, False);
end;

procedure TBuilder.Add(const AItem: TAtlasHoverItem);
begin
  if FItemCount = Length(FItems) then
    SetLength(FItems, 2 * FItemCount + 16);
  FItems[FItemCount] := AItem;
  Inc(FItemCount);
end;

procedure TBuilder.Insert(AAt: Integer; const AItem: TAtlasHoverItem);
var
  Index: Integer;
begin
  Add(AItem);
  for Index := FItemCount - 1 downto AAt + 1 do
    FItems[Index] := FItems[Index - 1];
  FItems[AAt] := AItem;
end;

procedure TBuilder.AddHit(AKind: TAtlasHoverHitKind; AIndex: Integer; const ARect: TRect);
begin
  if FHitCount = Length(FHits) then
    SetLength(FHits, 2 * FHitCount + 8);
  FHits[FHitCount].Kind := AKind;
  FHits[FHitCount].Index := AIndex;
  FHits[FHitCount].Rect := ARect;
  Inc(FHitCount);
end;

procedure TBuilder.AddText(AX, AY: Integer; const AText: string; const AFace: TAtlasHoverFace;
  AColor: TAtlasColor);
var
  Item: TAtlasHoverItem;
begin
  Item := NewItem(TAtlasHoverItemKind.Text, Rect(AX, AY, AX, AY), AColor);
  Item.Text := AText;
  Item.Face := AFace;
  Add(Item);
end;

procedure TBuilder.AddLine(ALeft, ATop, ARight: Integer; AColor: TAtlasColor);
begin
  Add(NewItem(TAtlasHoverItemKind.Line, Rect(ALeft, ATop, ARight, ATop), AColor));
end;

procedure TBuilder.HorizontalLine(ATop: Integer);
begin
  AddLine(0, ATop, FInput.Width, FColors.Line);
end;

procedure TBuilder.Block(const AText: string; AColor: TAtlasColor; AMaxLines: Integer);
var
  Bottom: Integer;
  Item: TAtlasHoverItem;
begin
  if AText = '' then
    Exit;
  Bottom := FY + FMeasure.BlockHeight(AText, FRight - FLeft);
  if AMaxLines > 0 then
    Bottom := Min(Bottom, FY + AMaxLines * Height(Face(TAtlasHoverFont.Ui, False)));
  Item := NewItem(TAtlasHoverItemKind.Block, Rect(FLeft, FY, FRight, Bottom), AColor);
  Item.Text := AText;
  Add(Item);
  FY := Bottom + Scale(6);
end;

procedure TBuilder.Flow(const AText: string; AColor: TAtlasColor; ABold: Boolean; AKind: TAtlasHoverHitKind;
  AIndex, AHotIndex: Integer; AHotColor: TAtlasColor);
var
  TextFace: TAtlasHoverFace;
  TextWidth, TextHeight: Integer;
  Cell: TRect;
  Item: TAtlasHoverItem;
begin
  TextFace := Face(FFlowFont, ABold);
  TextWidth := Width(TextFace, AText);
  TextHeight := Height(TextFace);
  if not FNoWrap and (FX + TextWidth > FRight) and (FX > FLeft) then
  begin
    FX := FLeft;
    Inc(FY, FRowHeight + Scale(4));
    FRowHeight := 0;
  end;
  Cell := Rect(FX, FY, FX + TextWidth, FY + TextHeight);
  Item := NewItem(TAtlasHoverItemKind.Text, Cell, AColor);
  Item.Text := AText;
  Item.Face := TextFace;
  if AHotIndex >= 0 then
  begin
    Item.HotKind := AKind;
    Item.HotIndex := AHotIndex;
    Item.HotColor := AHotColor;
    Item.HotUnderline := True;
  end;
  Add(Item);
  if AIndex >= 0 then
    AddHit(AKind, AIndex, Cell);
  Inc(FX, TextWidth);
  FRowHeight := Max(FRowHeight, TextHeight);
end;

procedure TBuilder.EndFlow;
begin
  Inc(FY, FRowHeight);
  FRowHeight := 0;
  FX := FLeft;
end;

procedure TBuilder.Chip(const AText: string; ACurrent: Boolean; AIndex: Integer);
var
  TextFace: TAtlasHoverFace;
  TextWidth, TextHeight: Integer;
  Cell: TRect;
  Item: TAtlasHoverItem;
begin
  // Glied der Vererbungskette als umrandetes Kästchen; das angezeigte in Akzentfarbe.
  TextFace := Face(TAtlasHoverFont.Mono, ACurrent);
  TextWidth := Width(TextFace, AText);
  TextHeight := Height(TextFace) + Scale(2);
  if (FX + TextWidth + Scale(AtlasChipPad) > FRight) and (FX > FLeft) then
  begin
    FX := FLeft;
    Inc(FY, FRowHeight + Scale(4));
    FRowHeight := 0;
  end;
  Cell := Rect(FX, FY, FX + TextWidth + Scale(AtlasChipPad), FY + TextHeight);
  if ACurrent then
    Item := NewItem(TAtlasHoverItemKind.Frame, Cell, FColors.Accent)
  else
  begin
    Item := NewItem(TAtlasHoverItemKind.Frame, Cell, FColors.Line);
    Item.HotKind := TAtlasHoverHitKind.Ancestor;
    Item.HotIndex := AIndex;
    Item.HotColor := FColors.Accent;
  end;
  Item.Back := FColors.Surface;
  Item.Radius := AtlasChipRadius;
  Add(Item);
  if ACurrent then
    Item := NewItem(TAtlasHoverItemKind.Text, Rect(Cell.Left + Scale(AtlasChipPad div 2), Cell.Top + Scale(1),
      Cell.Left + Scale(AtlasChipPad div 2), Cell.Top + Scale(1)), FColors.Accent)
  else
  begin
    Item := NewItem(TAtlasHoverItemKind.Text, Rect(Cell.Left + Scale(AtlasChipPad div 2), Cell.Top + Scale(1),
      Cell.Left + Scale(AtlasChipPad div 2), Cell.Top + Scale(1)), FColors.Text);
    Item.HotKind := TAtlasHoverHitKind.Ancestor;
    Item.HotIndex := AIndex;
    Item.HotColor := FColors.Accent;
  end;
  Item.Text := AText;
  Item.Face := TextFace;
  Add(Item);
  if not ACurrent then
    AddHit(TAtlasHoverHitKind.Ancestor, AIndex, Cell);
  FX := Cell.Right;
  FRowHeight := Max(FRowHeight, TextHeight);
end;

procedure TBuilder.ActionItem(const AKey, ACaption: string; AAction: TAtlasHoverAction; AEnabled: Boolean);
var
  KeyColor: TAtlasColor;
  Total, Start, HotIndex: Integer;
begin
  // Taste in Akzentfarbe, Beschriftung gedämpft; bleibt in einer Zeile.
  if FX > FLeft then
    Inc(FX, Scale(14));
  Total := Width(Face(TAtlasHoverFont.SmallUi, True), AKey + ' ') +
    Width(Face(TAtlasHoverFont.SmallUi, False), ACaption);
  if (FX + Total > FRight) and (FX > FLeft) then
  begin
    FX := FLeft;
    Inc(FY, FRowHeight + Scale(3));
    FRowHeight := 0;
  end;
  if AEnabled then
    KeyColor := FColors.Accent
  else
    KeyColor := FColors.Muted;
  HotIndex := -1;
  if AEnabled then
    HotIndex := Ord(AAction);
  Start := FX;
  Flow(AKey + ' ', KeyColor, True, TAtlasHoverHitKind.Action, -1, -1, KeyColor);
  Flow(ACaption, FColors.Muted, False, TAtlasHoverHitKind.Action, -1, HotIndex, FColors.Text);
  if AEnabled then
    AddHit(TAtlasHoverHitKind.Action, Ord(AAction), Rect(Start, FY, FX, FY + FRowHeight));
end;

procedure TBuilder.ProblemLink(const ACaption: string; AProblem: Integer; AAction: TAtlasHoverProblemAction);
var
  Code: Integer;
begin
  if FX > FLeft then
    Inc(FX, Scale(12));
  Code := TAtlasHoverLayout.ProblemActionCode(AProblem, AAction);
  Flow(ACaption, FColors.Accent, False, TAtlasHoverHitKind.ProblemAction, Code, Code, FColors.Accent);
end;

procedure TBuilder.RelatedLinks(const AProblem: TAtlasProblem; AIndex: Integer);
var
  OldFont: TAtlasHoverFont;
  Item, Code: Integer;
  Cycle: Boolean;
begin
  Cycle := AProblem.Code = TAtlasProblem.UsesCycleCode;
  if (AProblem.Related = nil) and not Cycle then
    Exit;
  OldFont := FFlowFont;
  FFlowFont := TAtlasHoverFont.SmallUi;
  FX := FLeft;
  FRowHeight := 0;
  for Item := 0 to Min(High(AProblem.Related), MaxRelated - 1) do
  begin
    if (Item > 0) and Cycle then
      Flow(' → ', FColors.Muted, False, TAtlasHoverHitKind.ProblemAction, -1, -1, FColors.Muted)
    else if Item > 0 then
      Flow(' · ', FColors.Muted, False, TAtlasHoverHitKind.ProblemAction, -1, -1, FColors.Muted);
    Code := TAtlasHoverLayout.ProblemActionCode(AIndex, TAtlasHoverProblemAction.Related, Item);
    Flow(AProblem.Related[Item].Message, FColors.Accent, False, TAtlasHoverHitKind.ProblemAction, Code, Code,
      FColors.Accent);
  end;
  if Cycle and (FInput.Texts.ShowGraph <> '') then
    ProblemLink(FInput.Texts.ShowGraph, AIndex, TAtlasHoverProblemAction.ShowGraph);
  EndFlow;
  Inc(FY, Scale(6));
  FFlowFont := OldFont;
end;

procedure TBuilder.BandContent(AKind: Integer);
var
  Chain: TArray<Integer>;
  Item: Integer;
  Caption: string;
  CaptionFace: TAtlasHoverFace;
begin
  FX := FLeft;
  FRowHeight := 0;
  case AKind of
    BandChain:
      begin
        Inc(FY, Scale(8));
        if FData.Kind = TAtlasHoverData.KindClassRef then
          Caption := Format(FInput.Texts.TargetType, [FData.ChainOf])
        else
          Caption := FInput.Texts.Inheritance;
        CaptionFace := Face(TAtlasHoverFont.SmallMono, True);
        AddText(FLeft, FY, AnsiUpperCase(Caption), CaptionFace, FColors.Muted);
        Inc(FY, Height(CaptionFace) + Scale(6));
        FFlowFont := TAtlasHoverFont.Mono;
        Chain := FData.VisibleChain;
        for Item := 0 to High(Chain) do
        begin
          if Item > 0 then
            Flow(' › ', FColors.Muted, False, TAtlasHoverHitKind.Ancestor, -1, -1, FColors.Muted);
          if Chain[Item] < 0 then
            Flow('…', FColors.Muted, False, TAtlasHoverHitKind.Ancestor, -1, -1, FColors.Muted)
          else
            Chip(FData.Ancestors[Chain[Item]].Name, FData.Ancestors[Chain[Item]].Key = FData.Location.Key,
              Chain[Item]);
        end;
        EndFlow;
        Inc(FY, Scale(8));
      end;
    BandActions:
      begin
        Inc(FY, Scale(6));
        FFlowFont := TAtlasHoverFont.SmallUi;
        ActionItem('F12', Format(FInput.Texts.Navigate, [FData.Title]), TAtlasHoverAction.Navigate, True);
        if FInput.View.UsagesCount >= 0 then
          Caption := Format(FInput.Texts.UsagesCount, [FInput.View.UsagesCount])
        else
          Caption := FInput.Texts.Usages;
        ActionItem(FInput.Texts.KeyUsages, Caption, TAtlasHoverAction.Usages, True);
        // Mit Markierung in der Doku kopiert Strg+C diese, bei Komponentenklassen die Liste (#110), sonst die
        // Deklaration.
        if FInput.HasSelection then
          Caption := FInput.Texts.CopySelection
        else if Length(FData.Members) > 0 then
          Caption := FInput.Texts.PublishedCopyList
        else
          Caption := FInput.Texts.Copy;
        ActionItem(FInput.Texts.KeyCopy, Caption, TAtlasHoverAction.Copy, True);
        ActionItem('F1', FInput.Texts.Help, TAtlasHoverAction.Help, FData.DocWiki <> '');
        // Geerbte VCL-Mitglieder kennt der Server nur mit den VCL-Quellen im Index (#110).
        if (Length(FData.Members) > 0) and (FInput.Texts.PublishedVclNote <> '') then
        begin
          Inc(FX, Scale(14));
          Flow(FInput.Texts.PublishedVclNote, FColors.Muted, False, TAtlasHoverHitKind.Action, -1, -1,
            FColors.Muted);
        end;
        EndFlow;
        Inc(FY, Scale(6));
      end;
  end;
  FFlowFont := TAtlasHoverFont.Ui;
end;

procedure TBuilder.Band(AKind: Integer; ALast: Boolean);
var
  Top, BandHeight, FirstItem, FirstHit: Integer;
begin
  // Abschnitt auf Randfläche mit Linie oben; Fläche und Linie vor den Inhalt, Höhe aus dem Inhalt.
  Top := FY;
  FirstItem := FItemCount;
  FirstHit := FHitCount;
  BandContent(AKind);
  BandHeight := FY - Top;
  Insert(FirstItem, NewItem(TAtlasHoverItemKind.Line, Rect(0, Top, FInput.Width, Top), FColors.Line));
  Insert(FirstItem, NewItem(TAtlasHoverItemKind.Fill, Rect(0, Top, FInput.Width, Top + BandHeight),
    FColors.Gutter));
  if ALast then
  begin
    FLayout.AnchorItem := FirstItem;
    FLayout.AnchorHit := FirstHit;
    FLayout.AnchorTop := Top;
    FLayout.AnchorHeight := BandHeight;
  end;
end;

procedure TBuilder.DrawPart(AFrom, ATill: Integer);
var
  Item: TAtlasHoverItem;
begin
  Item := NewItem(TAtlasHoverItemKind.Styled, Rect(FX, FY, FRight, FY + FLineHeight), FColors.Text);
  Item.From := AFrom;
  Item.Till := ATill;
  Add(Item);
  Inc(FX, FMeasure.DeclarationWidth(AFrom, ATill));
end;

procedure TBuilder.Navigation;
var
  NavHeight, Index, CaptionWidth: Integer;
  Box: TRect;
  Item: TAtlasHoverItem;
  Caption: string;
  Path: TArray<TAtlasHoverPathItem>;
  SmallFace: TAtlasHoverFace;
begin
  // Pfadzeile (nur angeheftet) auf Randfläche: Zurück-Knopf, besuchte Typen, rechts „angeheftet“.
  NavHeight := Scale(30);
  Add(NewItem(TAtlasHoverItemKind.Fill, Rect(0, 0, FInput.Width, NavHeight), FColors.Gutter));
  HorizontalLine(NavHeight - 1);
  Box := Rect(Scale(8), (NavHeight - Scale(20)) div 2, Scale(30), (NavHeight - Scale(20)) div 2 + Scale(20));
  Item := NewItem(TAtlasHoverItemKind.Frame, Box, FColors.Line);
  Item.Back := FColors.Surface;
  Item.Radius := 4;
  if FInput.View.CanGoBack then
  begin
    Item.HotKind := TAtlasHoverHitKind.Back;
    Item.HotIndex := 0;
    Item.HotColor := FColors.Accent;
  end;
  Add(Item);
  if FInput.View.CanGoBack then
    Item := NewItem(TAtlasHoverItemKind.CenterText, Box, FColors.Text)
  else
    Item := NewItem(TAtlasHoverItemKind.CenterText, Box, FColors.Muted);
  Item.Text := '‹';
  Item.Face := Face(TAtlasHoverFont.Mono, True);
  Add(Item);
  if FInput.View.CanGoBack then
    AddHit(TAtlasHoverHitKind.Back, 0, Box);
  FFlowFont := TAtlasHoverFont.Mono;
  FNoWrap := True;
  FY := (NavHeight - Height(Face(TAtlasHoverFont.Mono, False))) div 2;
  FX := Box.Right + Scale(6);
  Path := FInput.View.Path;
  for Index := 0 to High(Path) do
  begin
    if Index > 0 then
      Flow(' › ', FColors.Muted, False, TAtlasHoverHitKind.Path, -1, -1, FColors.Muted);
    if Index = High(Path) then
      Flow(Path[Index].Caption, FColors.Text, True, TAtlasHoverHitKind.Path, -1, -1, FColors.Text)
    else if Path[Index].Index < 0 then
      Flow(Path[Index].Caption, FColors.Muted, False, TAtlasHoverHitKind.Path, -1, -1, FColors.Muted)
    else
      Flow(Path[Index].Caption, FColors.Muted, False, TAtlasHoverHitKind.Path, Path[Index].Index,
        Path[Index].Index, FColors.Muted);
  end;
  SmallFace := Face(TAtlasHoverFont.SmallUi, False);
  Caption := FInput.Texts.Pinned;
  CaptionWidth := Width(SmallFace, Caption);
  if FX + CaptionWidth + Scale(12) < FRight then
    AddText(FRight - CaptionWidth, (NavHeight - Height(SmallFace)) div 2, Caption, SmallFace, FColors.Muted);
  FNoWrap := False;
  FFlowFont := TAtlasHoverFont.Ui;
  FRowHeight := 0;
  FY := NavHeight + Scale(8);
  FX := FLeft;
end;

procedure TBuilder.DebugValue;
var
  Value: TAtlasDebugValue;
  Start: Integer;
  MonoFace: TAtlasHoverFace;
  Bar: TAtlasHoverItem;
begin
  // Wert im angehaltenen Debugger (#891): Akzentbalken, Ausdruck in der Editorschrift, darunter der Wert
  // (höchstens sechs Zeilen) bzw. „wird ausgewertet …“.
  Value := FInput.View.DebugValue;
  Start := FY;
  FLeft := Scale(20);
  MonoFace := Face(TAtlasHoverFont.Mono, True);
  AddText(FLeft, FY, Value.Expression, MonoFace, FColors.Accent);
  Inc(FY, Height(MonoFace) + Scale(3));
  if Value.State = TAtlasDebugValueState.Pending then
    Block(FInput.Texts.DebugPending, FColors.Muted, 1)
  else if Value.Explained then
    DebugNote(Value.Note)
  else
    Block(Value.Text, FColors.Text, 6);
  FLeft := Scale(11);
  Bar := NewItem(TAtlasHoverItemKind.RoundFill, Rect(FLeft, Start + Scale(1), FLeft + Scale(3), FY - Scale(7)),
    FColors.Accent);
  Bar.Radius := 1;
  Add(Bar);
end;

procedure TBuilder.DebugNote(const ANote: TAtlasDebugValueNote);
var
  Line: string;
  Index: Integer;
  OldFont: TAtlasHoverFont;
begin
  // „kein Zugriff“ (#840): Kennzeichen, Ursache, Herkunft des Schalters, geprüfte Punkte, Korrekturen.
  Block(ANote.Caption, FColors.Warn, 1);
  if ANote.Pending then
  begin
    Block(FInput.Texts.DebugExplaining, FColors.Muted, 1);
    Exit;
  end;
  Block(ANote.Reason, FColors.Text, 6);
  Block(ANote.Origin, FColors.Muted, 2);
  if Length(ANote.Checked) > 0 then
  begin
    Block(FInput.Texts.DebugChecked, FColors.Muted, 1);
    for Line in ANote.Checked do
      Block('• ' + Line, FColors.Muted, 2);
  end;
  if Length(ANote.Fixes) = 0 then
    Exit;
  OldFont := FFlowFont;
  FFlowFont := TAtlasHoverFont.SmallUi;
  FX := FLeft;
  FRowHeight := 0;
  for Index := 0 to High(ANote.Fixes) do
  begin
    if FX > FLeft then
      Inc(FX, Scale(12));
    Flow(ANote.Fixes[Index].Caption, FColors.Accent, False, TAtlasHoverHitKind.DebugFix, Index, Index,
      FColors.Accent);
  end;
  EndFlow;
  Inc(FY, Scale(6));
  FFlowFont := OldFont;
end;

procedure TBuilder.SeverityPill(const AProblem: TAtlasProblem);
var
  PillFace: TAtlasHoverFace;
  Caption: string;
  Color: TAtlasColor;
  Box: TRect;
  Item: TAtlasHoverItem;
begin
  // Farbe und Text wie die Spalten Icon und Art im Fenster „Atlas-Prüfung“: information und hint sind Info.
  case AProblem.Severity of
    TAtlasProblemSeverity.Error:
      begin
        Caption := FInput.Texts.KindError;
        Color := FColors.Error;
      end;
    TAtlasProblemSeverity.Warning:
      begin
        Caption := FInput.Texts.KindWarning;
        Color := FColors.Warn;
      end;
  else
    Caption := FInput.Texts.KindInfo;
    Color := FColors.Accent;
  end;
  if Caption = '' then
    Exit;
  if AProblem.Stale then
    Color := TAtlasColorMath.Mix(Color, FColors.Surface, AtlasMixFaded);
  // Kleine UI-Schrift statt Badge: Die Badge-Schrift richtet sich beim Zeichnen nach der Höhe des Kästchens, das
  // Kästchen hier nach der gemessenen Schrift; gemessen wurde sie ohne Kästchen (Windows-Standardschrift), das
  // Kästchen geriet zu groß und der Text darin kleiner.
  PillFace := Face(TAtlasHoverFont.SmallUi, True);
  Box := Rect(FLeft, FY + Scale(1), FLeft + Width(PillFace, Caption) + Scale(12), FY + Scale(1) +
    Max(Height(PillFace) + Scale(2), Scale(15)));
  Item := NewItem(TAtlasHoverItemKind.RoundFill, Box, TAtlasColorMath.Mix(Color, FColors.Surface, 0.16));
  Item.Radius := 7;
  Add(Item);
  Item := NewItem(TAtlasHoverItemKind.CenterText, Box, Color);
  Item.Text := Caption;
  Item.Face := PillFace;
  Add(Item);
  FLeft := Box.Right + Scale(6);
end;

procedure TBuilder.RuleActions(const AProblem: TAtlasProblem; AIndex: Integer);
var
  OldFont: TAtlasHoverFont;
  Start: Integer;
  Code: Integer;
begin
  // Aktionszeile eines Regelbefunds (#909): Korrektur (nur, wenn die Regel eine hat), unterdrücken, einstellen.
  OldFont := FFlowFont;
  FFlowFont := TAtlasHoverFont.SmallUi;
  FX := FLeft;
  FRowHeight := 0;
  if AProblem.FixTitle <> '' then
  begin
    Start := FX;
    Code := TAtlasHoverLayout.ProblemActionCode(AIndex, TAtlasHoverProblemAction.Fix);
    Flow('Alt+Enter: ', FColors.Accent, True, TAtlasHoverHitKind.ProblemAction, -1, Code, FColors.Accent);
    Flow(AProblem.FixTitle, FColors.Accent, True, TAtlasHoverHitKind.ProblemAction, -1, Code, FColors.Accent);
    AddHit(TAtlasHoverHitKind.ProblemAction, Code, Rect(Start, FY, FX, FY + FRowHeight));
    if FLayout.FixProblem < 0 then
      FLayout.FixProblem := AIndex;
  end;
  // Syntaxfehler (#1022) lassen sich nicht unterdrücken, nur beheben oder einstellen.
  if AProblem.CanSuppress then
    ProblemLink(FInput.Texts.Suppress, AIndex, TAtlasHoverProblemAction.SuppressLine);
  ProblemLink(FInput.Texts.Configure, AIndex, TAtlasHoverProblemAction.Configure);
  EndFlow;
  Inc(FY, Scale(6));
  FFlowFont := OldFont;
end;

procedure TBuilder.Problems;
var
  Index, Start: Integer;
  Problem: TAtlasProblem;
  Caption: string;
  SmallFace: TAtlasHoverFace;
  Bar: TAtlasHoverItem;
  OldFont: TAtlasHoverFont;
  IsRule: Boolean;
begin
  // Probleme an der Mausposition, Fehler zuerst (#909): Farbbalken, Pille mit der Art und Meldung, darunter
  // Herkunft und Regel, bei Regeltreffern die Konfidenz und die Aktionszeile. Klickflächen tragen den Index
  // in View.Problems, nicht die Position im Hover.
  SmallFace := Face(TAtlasHoverFont.SmallUi, False);
  for Index in TAtlasHoverLayout.ProblemOrder(FInput.View.Problems) do
  begin
    Problem := FInput.View.Problems[Index];
    Start := FY;
    FLeft := Scale(20);
    // uses-Hinweise (#621) und inaktive Zweige (#615) sind keine Befunde: ohne Pille, Meldung mit Code.
    IsRule := not Problem.IsUses and not Problem.Unnecessary;
    if IsRule then
    begin
      SeverityPill(Problem);
      if FInput.HideCompilerCode then
        Block(TAtlasProblem.WithoutCompilerCode(Problem.Message), FColors.Text, 3)
      else
        Block(Problem.Message, FColors.Text, 3);
      FLeft := Scale(20);
    end
    else
      Block(Problem.Caption, FColors.Text, 3);
    Dec(FY, Scale(4));
    if Problem.IsUses then
      Caption := FInput.Texts.SourceUses
    else if Problem.Unnecessary then
      Caption := FInput.Texts.SourceInactive
    else
    begin
      // „Atlas · loop-off-by-one“, „dcc · W1036“, „Atlas · syntax“ (#1022). Vom Build bestätigt (#1024):
      // „Atlas + dcc · argument-count-mismatch · vom Compiler bestätigt (E2035)“.
      Caption := Problem.Source;
      if Caption = '' then
        Caption := FInput.Texts.SourceAtlas;
      if Problem.Confirmed then
        Caption := TAtlasProblem.ConfirmedSource;
      if Problem.Code <> '' then
        Caption := Caption + ' · ' + Problem.Code;
      if Problem.Confirmed and (FInput.HideCompilerCode or (Problem.ConfirmedCode = '')) then
        Caption := Caption + ' · ' + FInput.Texts.Confirmed
      else if Problem.Confirmed then
        Caption := Caption + ' · ' + Format(FInput.Texts.ConfirmedCode, [Problem.ConfirmedCode]);
    end;
    if Problem.Stale then
      Caption := Caption + ' · ' + FInput.Texts.Stale;
    AddText(FLeft, FY, Caption, SmallFace, FColors.Muted);
    // Konfidenz eines Regeltreffers als eigene Zeile (#144).
    Caption := '';
    if Index <= High(FInput.Texts.Confidences) then
      Caption := FInput.Texts.Confidences[Index];
    if Caption <> '' then
    begin
      Inc(FY, Height(SmallFace) + Scale(2));
      AddText(FLeft, FY, Caption, SmallFace, FColors.Muted);
    end;
    // Zusatz der Regel, z. B. der durchsuchte Bereich projektweiter Regeln (#1102).
    if Problem.Details <> '' then
    begin
      Inc(FY, Height(SmallFace) + Scale(2));
      AddText(FLeft, FY, Problem.Details, SmallFace, FColors.Muted);
    end;
    Inc(FY, Height(SmallFace) + Scale(6));
    // Weitere Stellen (#896), z. B. die Units eines Zyklus mit Sprung an ihren uses-Eintrag.
    RelatedLinks(Problem, Index);
    // Aktionen zum uses-Eintrag (#621).
    if (Problem.UsesState = TAtlasProblem.UsesUnused) or (Problem.UsesState = TAtlasProblem.UsesImplementation) then
    begin
      OldFont := FFlowFont;
      FFlowFont := TAtlasHoverFont.SmallUi;
      FX := FLeft;
      FRowHeight := 0;
      if Problem.UsesState = TAtlasProblem.UsesUnused then
      begin
        ProblemLink(FInput.Texts.UsesRemove, Index, TAtlasHoverProblemAction.RemoveUses);
        if Problem.UsesUnusedCount > 1 then
          ProblemLink(FInput.Texts.UsesRemoveAll, Index, TAtlasHoverProblemAction.RemoveAllUses);
      end
      else
        ProblemLink(FInput.Texts.UsesMove, Index, TAtlasHoverProblemAction.MoveUses);
      EndFlow;
      Inc(FY, Scale(6));
      FFlowFont := OldFont;
    end
    // Aktionszeile nur an Regelbefunden: Compilermeldungen und Syntaxfehler haben keine Regel.
    else if FInput.ProblemActions and IsRule and not Problem.IsCompiler and (Problem.Code <> '') then
      RuleActions(Problem, Index);
    FLeft := Scale(11);
    Bar := NewItem(TAtlasHoverItemKind.RoundFill, Rect(FLeft, Start + Scale(1), FLeft + Scale(3), FY - Scale(7)),
      ProblemColor(FColors, Problem));
    Bar.Radius := 1;
    Add(Bar);
  end;
end;

procedure TBuilder.Header;
var
  Caption, Location: string;
  Badge: TAtlasBadgeKind;
  Box: TRect;
  Item: TAtlasHoverItem;
  SmallFace, LocationFace: TAtlasHoverFace;
  Start: Integer;
begin
  // Kopfzeile: Badge, Art · Herkunft, rechts der Fundort.
  Caption := FInput.Texts.KindCaption;
  if (Caption <> '') and (FData.Origin <> '') then
    Caption := Caption + ' · ' + FData.Origin;
  Location := FData.LocationText;
  if (Caption = '') and (Location = '') then
    Exit;
  FLineHeight := Max(Height(Face(TAtlasHoverFont.Ui, False)), Scale(17));
  FX := FLeft;
  if FData.Kind <> '' then
  begin
    Badge := HoverBadgeKind(FData.Badge);
    Box := Rect(FLeft, FY, FLeft + Scale(24), FY + Scale(17));
    Item := NewItem(TAtlasHoverItemKind.RoundFill, Box, FColors.Badges[Badge].Background);
    Item.Radius := 4;
    Add(Item);
    Item := NewItem(TAtlasHoverItemKind.CenterText, Box, FColors.Badges[Badge].Text);
    Item.Text := FData.Badge;
    Item.Face := Face(TAtlasHoverFont.Badge, True);
    Add(Item);
    FX := Box.Right + Scale(7);
  end;
  SmallFace := Face(TAtlasHoverFont.SmallUi, False);
  AddText(FX, FY + (FLineHeight - Height(SmallFace)) div 2, Caption, SmallFace, FColors.Muted);
  if Location <> '' then
  begin
    Start := FX + Width(SmallFace, Caption) + Scale(12);
    LocationFace := Face(TAtlasHoverFont.SmallMono, False);
    AddText(Max(Start, FRight - Width(LocationFace, Location)), FY + (FLineHeight - Height(LocationFace)) div 2,
      Location, LocationFace, FColors.Muted);
  end;
  Inc(FY, FLineHeight + Scale(5));
  FX := FLeft;
end;

procedure TBuilder.Declaration;
var
  Lines: TArray<TPoint>;
  Line, Index, From, Till, Pos, Next, LinkFrom, LinkTill, Start: Integer;
  Links: TArray<TAtlasHoverLink>;
  Area: TRect;
  Item: TAtlasHoverItem;
  MonoFace: TAtlasHoverFace;
begin
  // Deklaration eingefärbt, an Leerzeichen umbrochen; Typnamen als Verweise in Akzentfarbe, unterstrichen.
  MonoFace := Face(TAtlasHoverFont.Mono, False);
  FLineHeight := Height(MonoFace) + Scale(2);
  Lines := FMeasure.DeclarationLines(FRight - FLeft, Scale(16));
  Links := FData.Links;
  for Line := 0 to High(Lines) do
  begin
    FX := FLeft;
    if Line > 0 then
      FX := FLeft + Scale(16);
    From := Lines[Line].X;
    Till := Lines[Line].Y;
    Pos := From;
    while Pos < Till do
    begin
      // Nächster Verweis, der in [Pos, Till) hineinreicht.
      Next := -1;
      for Index := 0 to High(Links) do
        if (Links[Index].Start + Links[Index].Length > Pos) and (Links[Index].Start < Till) and
          ((Next < 0) or (Links[Index].Start < Links[Next].Start)) then
          Next := Index;
      if Next < 0 then
      begin
        DrawPart(Pos, Till);
        Pos := Till;
        Continue;
      end;
      LinkFrom := Max(Pos, Links[Next].Start);
      LinkTill := Min(Till, Links[Next].Start + Links[Next].Length);
      if LinkFrom > Pos then
        DrawPart(Pos, LinkFrom);
      Start := FX;
      Inc(FX, FMeasure.DeclarationWidth(LinkFrom, LinkTill));
      Area := Rect(Start, FY, FX, FY + FLineHeight);
      AddHit(TAtlasHoverHitKind.Link, Next, Area);
      AddText(Start, FY + (FLineHeight - Height(MonoFace)) div 2,
        Copy(FData.Declaration, LinkFrom + 1, LinkTill - LinkFrom), MonoFace, FColors.Accent);
      Item := NewItem(TAtlasHoverItemKind.Line, Rect(Area.Left, Area.Bottom - Scale(2), Area.Right,
        Area.Bottom - Scale(2)), FColors.Accent);
      Item.HotKind := TAtlasHoverHitKind.Link;
      Item.HotIndex := Next;
      Item.HotPenWidth := Scale(2);
      Add(Item);
      Pos := LinkTill;
    end;
    Inc(FY, FLineHeight);
  end;
  Inc(FY, Scale(6));
  FX := FLeft;
end;

procedure TBuilder.Description;
begin
  // Beschreibung unter einer Linie; nur die XMLDoc scrollt.
  if not (((FData.LocationText = '') and (FData.UnitName <> '')) or (FData.Value <> '') or
    (FData.Deprecation <> '') or FInput.HasDoc) then
    Exit;
  HorizontalLine(FY);
  Inc(FY, Scale(7));
  if FData.LocationText = '' then
    Block(FData.UnitName, FColors.Muted, 0);
  if FData.Value <> '' then
    Block('= ' + FData.Value, FColors.Muted, 0);
  Block(FData.Deprecation, FColors.Warn, 0);
  FLayout.DocLeft := FLeft;
  FLayout.DocTop := FY;
  if FInput.HasDoc then
  begin
    Add(NewItem(TAtlasHoverItemKind.Doc, Rect(FLeft, FY, FLeft, FY), FColors.Text));
    Inc(FY, FInput.DocHeight + Scale(6));
  end;
  Inc(FY, Scale(1));
end;

procedure TBuilder.ToggleChip(const ACaption: string; AOn: Boolean; AToggle: TAtlasHoverPublishedToggle;
  AX: Integer);
var
  TextFace: TAtlasHoverFace;
  Cell: TRect;
  Item: TAtlasHoverItem;
  LineColor, TextColor: TAtlasColor;
begin
  // Schalter als umrandetes Kästchen: an in Akzentfarbe, aus gedämpft.
  TextFace := Face(TAtlasHoverFont.SmallUi, False);
  Cell := Rect(AX, FY, AX + Width(TextFace, ACaption) + Scale(AtlasChipPad), FY + Height(TextFace) + Scale(2));
  if AOn then
  begin
    LineColor := FColors.Accent;
    TextColor := FColors.Accent;
  end
  else
  begin
    LineColor := FColors.Line;
    TextColor := FColors.Muted;
  end;
  Item := NewItem(TAtlasHoverItemKind.Frame, Cell, LineColor);
  Item.Back := FColors.Surface;
  Item.Radius := AtlasChipRadius;
  Item.HotKind := TAtlasHoverHitKind.Published;
  Item.HotIndex := Ord(AToggle);
  Item.HotColor := FColors.Accent;
  Add(Item);
  Item := NewItem(TAtlasHoverItemKind.CenterText, Cell, TextColor);
  Item.Text := ACaption;
  Item.Face := TextFace;
  Item.HotKind := TAtlasHoverHitKind.Published;
  Item.HotIndex := Ord(AToggle);
  Item.HotColor := FColors.Accent;
  Add(Item);
  AddHit(TAtlasHoverHitKind.Published, Ord(AToggle), Cell);
end;

procedure TBuilder.MemberSection(AEvents: Boolean);
var
  Rows: TArray<Integer>;
  Row, Shown, Limit, NameX, TypeX, DefaultX, RowHeight, Gap, TagWidth: Integer;
  Collapsed, ShowAll: Boolean;
  Caption, TypeText, Declared: string;
  Toggle, More: TAtlasHoverPublishedToggle;
  MonoFace, SmallFace, SmallMonoFace, HeadFace: TAtlasHoverFace;
  Member: TAtlasHoverMember;
  Item: TAtlasHoverItem;
  Cell: TRect;
begin
  Rows := FData.VisibleMembers(AEvents, not FInput.View.HideInherited, FInput.View.OnlyDefaults);
  if Length(Rows) = 0 then
    Exit;
  if AEvents then
  begin
    Caption := FInput.Texts.PublishedEvents;
    Collapsed := FInput.View.EventsCollapsed;
    ShowAll := FInput.View.AllEvents;
    Toggle := TAtlasHoverPublishedToggle.Events;
    More := TAtlasHoverPublishedToggle.MoreEvents;
    Limit := EventRows;
  end
  else
  begin
    Caption := FInput.Texts.PublishedProperties;
    Collapsed := FInput.View.PropertiesCollapsed;
    ShowAll := FInput.View.AllProperties;
    Toggle := TAtlasHoverPublishedToggle.Properties;
    More := TAtlasHoverPublishedToggle.MoreProperties;
    Limit := PropertyRows;
  end;
  MonoFace := Face(TAtlasHoverFont.Mono, False);
  SmallFace := Face(TAtlasHoverFont.SmallUi, False);
  SmallMonoFace := Face(TAtlasHoverFont.SmallMono, False);
  HeadFace := Face(TAtlasHoverFont.SmallMono, True);
  Gap := Scale(12);
  // Abschnittstitel mit ▾ (offen) bzw. ▸ (zu); Klick klappt um.
  if Collapsed then
    Caption := AnsiUpperCase(Caption) + ' ▸'
  else
    Caption := AnsiUpperCase(Caption) + ' ▾';
  Cell := Rect(FLeft, FY, FLeft + Width(HeadFace, Caption), FY + Height(HeadFace));
  Item := NewItem(TAtlasHoverItemKind.Text, Cell, FColors.Muted);
  Item.Text := Caption;
  Item.Face := HeadFace;
  Item.HotKind := TAtlasHoverHitKind.Published;
  Item.HotIndex := Ord(Toggle);
  Item.HotColor := FColors.Accent;
  Add(Item);
  AddHit(TAtlasHoverHitKind.Published, Ord(Toggle), Cell);
  Inc(FY, Height(HeadFace) + Scale(5));
  if Collapsed then
    Exit;
  Shown := Length(Rows);
  if not ShowAll then
    Shown := Min(Shown, Limit);
  // Spalten nach den breitesten gezeigten Werten; „deklariert in“ rechtsbündig.
  NameX := FLeft;
  TypeX := NameX + Width(SmallFace, FInput.Texts.PublishedName);
  for Row := 0 to Shown - 1 do
    TypeX := Max(TypeX, NameX + Width(MonoFace, FData.Members[Rows[Row]].Name));
  Inc(TypeX, Gap);
  DefaultX := TypeX + Width(SmallFace, FInput.Texts.PublishedType);
  for Row := 0 to Shown - 1 do
  begin
    TypeText := FData.Members[Rows[Row]].TypeName;
    DefaultX := Max(DefaultX, TypeX + Width(MonoFace, TypeText));
  end;
  Inc(DefaultX, Gap);
  RowHeight := Height(MonoFace) + Scale(3);
  if not AEvents then
  begin
    AddText(NameX, FY, FInput.Texts.PublishedName, SmallFace, FColors.Muted);
    AddText(TypeX, FY, FInput.Texts.PublishedType, SmallFace, FColors.Muted);
    AddText(DefaultX, FY, FInput.Texts.PublishedDefault, SmallFace, FColors.Muted);
    AddText(FRight - Width(SmallFace, FInput.Texts.PublishedDeclared), FY, FInput.Texts.PublishedDeclared,
      SmallFace, FColors.Muted);
    Inc(FY, Height(SmallFace) + Scale(4));
  end;
  for Row := 0 to Shown - 1 do
  begin
    Member := FData.Members[Rows[Row]];
    AddText(NameX, FY, Member.Name, MonoFace, FColors.Text);
    AddText(TypeX, FY, Member.TypeName, MonoFace, FColors.Accent);
    if AEvents then
    begin
      // Am Methodenzeiger-Typ erkannt, nicht am Namen: fremde Typnamen kenntlich machen.
      if not EndsText('Event', Member.TypeName) then
        AddText(TypeX + Width(MonoFace, Member.TypeName + ' '), FY + (Height(MonoFace) - Height(SmallFace)) div 2,
          '(of object)', SmallFace, FColors.Muted);
    end
    else
    begin
      FX := DefaultX;
      case Member.DefaultKind of
        hdExplicit:
          begin
            AddText(FX, FY, Member.DefaultValue, MonoFace, FColors.Text);
            Inc(FX, Width(MonoFace, Member.DefaultValue + ' '));
          end;
        hdImplicit:
          begin
            AddText(FX, FY, Member.DefaultValue, MonoFace, FColors.Text);
            Inc(FX, Width(MonoFace, Member.DefaultValue + ' '));
            // Implizit als gedämpfte Marke.
            TagWidth := Width(SmallFace, FInput.Texts.PublishedImplicit) + Scale(AtlasChipPad);
            Cell := Rect(FX, FY + Scale(1), FX + TagWidth, FY + Height(SmallFace) + Scale(3));
            Item := NewItem(TAtlasHoverItemKind.Frame, Cell, FColors.Line);
            Item.Back := FColors.Surface;
            Item.Radius := AtlasChipRadius;
            Add(Item);
            Item := NewItem(TAtlasHoverItemKind.CenterText, Cell, FColors.Muted);
            Item.Text := FInput.Texts.PublishedImplicit;
            Item.Face := SmallFace;
            Add(Item);
            Inc(FX, TagWidth + Scale(4));
          end;
        hdNoDefault:
          begin
            AddText(FX, FY, 'nodefault', MonoFace, FColors.Muted);
            Inc(FX, Width(MonoFace, 'nodefault '));
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      if Member.Stored <> '' then
        AddText(FX, FY, 'stored ' + Member.Stored, MonoFace, FColors.Muted);
    end;
    Declared := Member.DeclaringClass;
    AddText(FRight - Width(SmallMonoFace, Declared), FY + (Height(MonoFace) - Height(SmallMonoFace)) div 2,
      Declared, SmallMonoFace, FColors.Muted);
    Inc(FY, RowHeight);
  end;
  // „+ n weitere …“ zeigt alle; bei Ereignissen der Hinweis, woran sie erkannt sind.
  FX := FLeft;
  FRowHeight := 0;
  FFlowFont := TAtlasHoverFont.SmallUi;
  if Shown < Length(Rows) then
  begin
    if AEvents then
      Caption := Format(FInput.Texts.PublishedMoreEvents, [Length(Rows) - Shown])
    else
      Caption := Format(FInput.Texts.PublishedMoreProperties, [Length(Rows) - Shown]);
    Flow(Caption, FColors.Accent, False, TAtlasHoverHitKind.Published, Ord(More), Ord(More), FColors.Accent);
  end;
  if AEvents then
  begin
    if FX > FLeft then
      Flow(' · ', FColors.Muted, False, TAtlasHoverHitKind.Published, -1, -1, FColors.Muted);
    Flow(FInput.Texts.PublishedEventsNote, FColors.Muted, False, TAtlasHoverHitKind.Published, -1, -1,
      FColors.Muted);
  end;
  if FX > FLeft then
  begin
    Inc(FY, Scale(2));
    EndFlow;
  end;
  FFlowFont := TAtlasHoverFont.Ui;
  Inc(FY, Scale(8));
end;

procedure TBuilder.PublishedMembers;
var
  Summary, Name, Note: string;
  SmallFace, MonoFace, HeadFace: TAtlasHoverFace;
  ChipsWidth, InheritedWidth, Bracket, TagWidth: Integer;
  Cell: TRect;
  Item: TAtlasHoverItem;
begin
  // published-Mitglieder einer Komponentenklasse (#110).
  if (Length(FData.Members) = 0) and (FData.DefaultProperty = '') then
    Exit;
  HorizontalLine(FY);
  Inc(FY, Scale(7));
  SmallFace := Face(TAtlasHoverFont.SmallUi, False);
  MonoFace := Face(TAtlasHoverFont.Mono, False);
  HeadFace := Face(TAtlasHoverFont.SmallMono, True);
  if Length(FData.Members) > 0 then
  begin
    // „published: 38 Properties · 24 Ereignisse“, rechts die Schalter; ohne Platz darunter.
    Summary := Format(FInput.Texts.PublishedSummary, [FData.MemberCount(False), FData.MemberCount(True)]);
    InheritedWidth := Width(SmallFace, FInput.Texts.PublishedInherited) + Scale(AtlasChipPad);
    ChipsWidth := InheritedWidth + Scale(6) + Width(SmallFace, FInput.Texts.PublishedOnlyDefaults) +
      Scale(AtlasChipPad);
    AddText(FLeft, FY + Scale(1), Summary, SmallFace, FColors.Muted);
    if FLeft + Width(SmallFace, Summary) + Scale(12) + ChipsWidth > FRight then
      Inc(FY, Height(SmallFace) + Scale(6));
    ToggleChip(FInput.Texts.PublishedInherited, not FInput.View.HideInherited,
      TAtlasHoverPublishedToggle.ShowInherited, FRight - ChipsWidth);
    ToggleChip(FInput.Texts.PublishedOnlyDefaults, FInput.View.OnlyDefaults, TAtlasHoverPublishedToggle.OnlyDefaults,
      FRight - ChipsWidth + InheritedWidth + Scale(6));
    Inc(FY, Height(SmallFace) + Scale(10));
    MemberSection(False);
    MemberSection(True);
  end;
  // Standard-Property: „default“ heißt an einer Array-Property nicht Vorgabewert.
  if FData.DefaultProperty <> '' then
  begin
    AddText(FLeft, FY, AnsiUpperCase(FInput.Texts.PublishedArrayProperty), HeadFace, FColors.Muted);
    Inc(FY, Height(HeadFace) + Scale(5));
    Name := FData.DefaultProperty;
    Bracket := Pos(']', Name);
    if Bracket > 0 then
      Name := Copy(Name, 1, Bracket);
    AddText(FLeft, FY, Name, MonoFace, FColors.Text);
    FX := FLeft + Width(MonoFace, Name + ' ');
    TagWidth := Width(SmallFace, FInput.Texts.PublishedDefaultProperty) + Scale(AtlasChipPad);
    Cell := Rect(FX, FY + Scale(1), FX + TagWidth, FY + Height(SmallFace) + Scale(3));
    Item := NewItem(TAtlasHoverItemKind.Frame, Cell, FColors.Accent);
    Item.Back := FColors.Surface;
    Item.Radius := AtlasChipRadius;
    Add(Item);
    Item := NewItem(TAtlasHoverItemKind.CenterText, Cell, FColors.Accent);
    Item.Text := FInput.Texts.PublishedDefaultProperty;
    Item.Face := SmallFace;
    Add(Item);
    Note := FInput.Texts.PublishedDefaultPropertyNote;
    if Cell.Right + Scale(8) + Width(SmallFace, Note) <= FRight then
      AddText(Cell.Right + Scale(8), FY + Scale(1), Note, SmallFace, FColors.Muted)
    else
    begin
      Inc(FY, Height(MonoFace) + Scale(3));
      AddText(FLeft, FY, Note, SmallFace, FColors.Muted);
    end;
    Inc(FY, Height(MonoFace) + Scale(8));
  end;
  FX := FLeft;
end;

procedure TBuilder.Run;
begin
  FFlowFont := TAtlasHoverFont.Ui;
  FNoWrap := False;
  FRowHeight := 0;
  FLeft := Scale(11);
  FRight := FInput.Width - Scale(11);
  FY := Scale(8);
  FX := FLeft;
  if FInput.View.Pinned then
    Navigation;
  if FInput.View.DebugValue.Visible then
  begin
    DebugValue;
    // Kennt der Server den Bezeichner nicht, zeigt der Tooltip nur den Wert (und Probleme).
    if (FData.Declaration = '') and (Length(FInput.View.Problems) = 0) then
    begin
      FY := FY + Scale(2);
      Exit;
    end;
    HorizontalLine(FY);
    Inc(FY, Scale(8));
  end;
  if Length(FInput.View.Problems) > 0 then
  begin
    Problems;
    // Ohne Bezeichner zeigt der Tooltip nur die Probleme.
    if FData.Declaration = '' then
    begin
      FY := FY + Scale(2);
      Exit;
    end;
    HorizontalLine(FY);
    Inc(FY, Scale(8));
  end;
  Header;
  Declaration;
  Description;
  PublishedMembers;
  // Vererbung bzw. Zieltyp und Aktionsleiste auf eigener Randfläche.
  if Length(FData.Ancestors) > 0 then
    Band(BandChain, not FData.Location.HasLocation);
  if FData.Location.HasLocation then
    Band(BandActions, True);
end;

function TBuilder.Layout: TAtlasHoverLayout;
begin
  Run;
  SetLength(FItems, FItemCount);
  SetLength(FHits, FHitCount);
  Result := FLayout;
  Result.Items := FItems;
  Result.Hits := FHits;
  Result.Height := FY;
end;

{ TAtlasHoverLayout }

class function TAtlasHoverLayout.Build(const AInput: TAtlasHoverInput;
  const AMeasure: IAtlasHoverMeasure): TAtlasHoverLayout;
var
  Builder: TBuilder;
begin
  Builder := TBuilder.Create(AInput, AMeasure);
  try
    Result := Builder.Layout;
  finally
    Builder.Free;
  end;
end;

function TAtlasHoverLayout.HitAt(const APoint: TPoint): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Hits) do
    if Hits[Index].Rect.Contains(APoint) then
      Exit(Index);
  Result := -1;
end;

class function TAtlasHoverLayout.ProblemActionCode(AProblem: Integer; AAction: TAtlasHoverProblemAction): Integer;
begin
  Result := ProblemActionCode(AProblem, AAction, 0);
end;

class function TAtlasHoverLayout.ProblemActionCode(AProblem: Integer; AAction: TAtlasHoverProblemAction;
  AItem: Integer): Integer;
begin
  Result := (AProblem * MaxRelated + AItem) * (Ord(High(TAtlasHoverProblemAction)) + 1) + Ord(AAction);
end;

class procedure TAtlasHoverLayout.DecodeProblemAction(ACode: Integer; out AProblem: Integer;
  out AAction: TAtlasHoverProblemAction);
var
  Item: Integer;
begin
  DecodeProblemAction(ACode, AProblem, AAction, Item);
end;

class procedure TAtlasHoverLayout.DecodeProblemAction(ACode: Integer; out AProblem: Integer;
  out AAction: TAtlasHoverProblemAction; out AItem: Integer);
var
  Rest: Integer;
begin
  AAction := TAtlasHoverProblemAction(ACode mod (Ord(High(TAtlasHoverProblemAction)) + 1));
  Rest := ACode div (Ord(High(TAtlasHoverProblemAction)) + 1);
  AProblem := Rest div MaxRelated;
  AItem := Rest mod MaxRelated;
end;

class function TAtlasHoverLayout.ProblemOrder(const AProblems: TArray<TAtlasProblem>): TArray<Integer>;
var
  Index, Count: Integer;
begin
  // Fehler zuerst, die übrigen in ihrer Reihenfolge (stabil).
  Result := nil;
  SetLength(Result, Length(AProblems));
  Count := 0;
  for Index := 0 to High(AProblems) do
    if AProblems[Index].Severity = TAtlasProblemSeverity.Error then
    begin
      Result[Count] := Index;
      Inc(Count);
    end;
  for Index := 0 to High(AProblems) do
    if AProblems[Index].Severity <> TAtlasProblemSeverity.Error then
    begin
      Result[Count] := Index;
      Inc(Count);
    end;
end;

function TAtlasHoverLayout.NextProblemHit(AHot: Integer; AForward: Boolean): Integer;
var
  Step, Index, Tries: Integer;
begin
  Result := -1;
  if Length(Hits) = 0 then
    Exit;
  Step := 1;
  if not AForward then
    Step := -1;
  Index := AHot;
  if (Index < 0) and not AForward then
    Index := 0;
  for Tries := 1 to Length(Hits) do
  begin
    Index := (Index + Step + Length(Hits)) mod Length(Hits);
    if Hits[Index].Kind = TAtlasHoverHitKind.ProblemAction then
      Exit(Index);
  end;
end;

function TAtlasHoverLayout.IsHot(AHot: Integer; AKind: TAtlasHoverHitKind; AIndex: Integer): Boolean;
begin
  Result := (AHot >= 0) and (AHot <= High(Hits)) and (Hits[AHot].Kind = AKind) and (Hits[AHot].Index = AIndex);
end;

procedure TAtlasHoverLayout.Anchor(AClientHeight: Integer);
var
  Wanted, Delta, Index: Integer;
begin
  if AnchorItem < 0 then
    Exit;
  Wanted := Max(0, AClientHeight - AnchorHeight - AnchorTop);
  Delta := Wanted - AnchorShift;
  if Delta = 0 then
    Exit;
  for Index := AnchorItem to High(Items) do
    Items[Index].Rect.Offset(0, Delta);
  for Index := AnchorHit to High(Hits) do
    Hits[Index].Rect.Offset(0, Delta);
  AnchorShift := Wanted;
end;

end.
