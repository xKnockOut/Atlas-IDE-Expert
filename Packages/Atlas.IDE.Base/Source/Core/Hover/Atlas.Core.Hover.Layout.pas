unit Atlas.Core.Hover.Layout;

// Satz des Hover-Tooltips ohne VCL: Build rechnet aus dem Inhalt
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
// Erklärungen (#54): Zu einer Compilermeldung mit Katalogeintrag (View.Explanations)
// steht klein „Typische Ursache: …“ unter der Meldung, darunter die Links
// „Erklären“ (Dialog mit Beispiel) und „DocWiki“; Regelbefunde bekommen
// „Erklären“ in ihrer Aktionszeile.
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
// Die Tabellen und die Standard-Property bilden einen Rollbereich: Ist er höher als
// Input.Members.MaxLines Tabellenzeilen (hover.membersMaxLines) bzw. als Input.Members.Limit
// (Platz auf dem Bildschirm), zeigt der Tooltip nur Members.View mit einem Daumen am rechten
// Rand (TAtlasHoverScroll, Atlas.Core.Hover.Items, #1841).

interface

uses
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.Texts,
  Atlas.Core.Hover.View;

type
  /// <summary>Messen in der Oberfläche; Build ruft nur diese Funktionen.</summary>
  IAtlasHoverMeasure = interface
    ['{96C7EBD2-5C83-4DC6-8E88-88DB86BCD6D5}']
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
    /// <summary>Rollbereich der published-Mitglieder: Zeilen, Grenze und gewünschter Versatz (#1841).</summary>
    Members: TAtlasHoverScrollRequest;
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
    /// <summary>Rollbereich der published-Mitglieder (#1841).</summary>
    Members: TAtlasHoverScroll;
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
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.History,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Style.Color,
  System.SysUtils,
  System.Math,
  System.StrUtils,
  Atlas.Core.Problems.Colors;

const
  cBandChain = 0;
  cBandActions = 1;
  /// <summary>So viele Zeilen zeigen die Tabellen der published-Mitglieder, bis „+ n weitere“ geklickt ist.
  /// </summary>
  cPropertyRows = 7;
  cEventRows = 4;
  /// <summary>Höchstens so viele weitere Stellen je Problem im Hover (#896).</summary>
  cMaxRelated = 64;
  /// <summary>Höchstens so viele Zeilen „Typische Ursache“ (#54).</summary>
  cCauseLines = 3;

type
  /// <summary>Klickfläche und Hervorhebung eines Stücks Fließtext: Index >= 0 legt eine Klickfläche an,
  /// HotIndex >= 0 färbt das Stück unter der Maus in HotColor und unterstreicht es.</summary>
  THotSpot = record
    Kind: TAtlasHoverHitKind;
    Index: Integer;
    HotIndex: Integer;
    HotColor: TAtlasColor;
  end;

  /// <summary>Spalten der Tabelle der published-Mitglieder.</summary>
  TMemberColumns = record
    NameX: Integer;
    TypeX: Integer;
    DefaultX: Integer;
  end;

  /// <summary>Abschnitt Properties bzw. Ereignisse der published-Mitglieder.</summary>
  TMemberSection = record
    Events: Boolean;
    Caption: string;
    MoreFormat: string;
    Collapsed: Boolean;
    ShowAll: Boolean;
    Toggle: TAtlasHoverPublishedToggle;
    More: TAtlasHoverPublishedToggle;
    Limit: Integer;
  end;

  /// <summary>Zeichenelemente und Klickflächen sammeln: Grundformen, Fließtext und Kästchen.</summary>
  TPainter = class
  protected
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
    /// <summary>Text in kleiner UI-Schrift eine Zeile tiefer; '' ohne Wirkung.</summary>
    procedure AddSmallLine(const AText: string);
    procedure AddLine(ALeft, ATop, ARight: Integer; AColor: TAtlasColor);
    procedure HorizontalLine(ATop: Integer);
    /// <summary>Senkrechter Farbbalken links neben einem Abschnitt ab ATop.</summary>
    procedure SideBar(ATop: Integer; AColor: TAtlasColor);
    procedure Block(const AText: string; AColor: TAtlasColor; AMaxLines: Integer);
    procedure Flow(const AText: string; AColor: TAtlasColor; ABold: Boolean; const AHot: THotSpot); overload;
    procedure Flow(const AText: string; AColor: TAtlasColor; ABold: Boolean); overload;
    /// <summary>Fließtext als Verweis mit Klickfläche ACode in AColor.</summary>
    procedure FlowLink(const AText: string; AColor: TAtlasColor; AKind: TAtlasHoverHitKind; ACode: Integer);
    procedure EndFlow;
    /// <summary>Zeile mit kleinen Verweisen beginnen; liefert die bisherige Schrift für EndLinkRow.</summary>
    function BeginLinkRow: TAtlasHoverFont;
    procedure EndLinkRow(AOldFont: TAtlasHoverFont);
  public
    constructor Create(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure);
  end;

  /// <summary>published-Mitglieder einer Komponentenklasse (#110).</summary>
  TPublishedPainter = class(TPainter)
  private
    procedure ToggleChip(const ACaption: string; AOn: Boolean; AToggle: TAtlasHoverPublishedToggle; AX: Integer);
    /// <summary>Gerahmte Marke in kleiner Schrift ab FX; liefert ihr Rechteck.</summary>
    function Tag(const ACaption: string; ALineColor, ATextColor: TAtlasColor): TRect;
    function SectionOf(AEvents: Boolean): TMemberSection;
    procedure SectionHead(const ASection: TMemberSection);
    function MemberColumns(const ARows: TArray<Integer>; AShown: Integer): TMemberColumns;
    /// <summary>AText, auf AMax Pixel gekürzt (mit „…“); '' ohne Platz.</summary>
    function Clipped(const AFace: TAtlasHoverFace; const AText: string; AMax: Integer): string;
    /// <summary>Vorgabe ab AX bis höchstens ALimit (dahinter steht „deklariert in“).</summary>
    procedure MemberDefault(const AMember: TAtlasHoverMember; AX, ALimit: Integer);
    procedure MemberRow(const AMember: TAtlasHoverMember; const AColumns: TMemberColumns; AEvents: Boolean);
    procedure MoreLinks(const ASection: TMemberSection; AHidden: Integer);
    procedure MemberSection(AEvents: Boolean);
    procedure PublishedSummary;
    procedure DefaultPropertyRow;
    /// <summary>Rollbereich ab ATop (Bausteine ab AFirstItem, Klickflächen ab AFirstHit) begrenzen.</summary>
    procedure ClipMembers(ATop, AFirstItem, AFirstHit: Integer);
  protected
    procedure PublishedMembers;
  end;

  /// <summary>Abschnitte des Tooltips der Reihe nach.</summary>
  TBuilder = class(TPublishedPainter)
  private
    procedure Chip(const AText: string; ACurrent: Boolean; AIndex: Integer);
    procedure ActionItem(const AKey, ACaption: string; AAction: TAtlasHoverAction; AEnabled: Boolean);
    procedure ProblemLink(const ACaption: string; AProblem: Integer; AAction: TAtlasHoverProblemAction);
    /// <summary>Weitere Stellen eines Problems als Links (#896), beim Unit-Zyklus als Pfad mit „Graph zeigen“.
    /// </summary>
    procedure RelatedLinks(const AProblem: TAtlasProblem; AIndex: Integer);
    /// <summary>Pille mit der Art des Befunds (#909); setzt FLeft hinter die Pille für die Meldung.</summary>
    procedure SeverityPill(const AProblem: TAtlasProblem);
    procedure RuleActions(const AProblem: TAtlasProblem; AIndex: Integer);
    /// <summary>Erklärung von Problem AIndex (#54); False ohne Katalogeintrag.</summary>
    function Explanation(AIndex: Integer; out AExplanation: TAtlasHoverExplanation): Boolean;
    /// <summary>„Typische Ursache: …“ unter einer Compilermeldung (#54).</summary>
    procedure Cause(AIndex: Integer);
    /// <summary>Links „Erklären“ und „DocWiki“ unter einer Compilermeldung (#54).</summary>
    procedure MessageActions(AIndex: Integer);
    /// <summary>Aktionen zum uses-Eintrag (#621).</summary>
    procedure UsesActions(const AProblem: TAtlasProblem; AIndex: Integer);
    /// <summary>Herkunft und Regel eines Regelbefunds.</summary>
    function RuleSource(const AProblem: TAtlasProblem): string;
    function ProblemSource(const AProblem: TAtlasProblem): string;
    procedure ProblemDetails(const AProblem: TAtlasProblem; AIndex: Integer);
    procedure Problem(AIndex: Integer);
    procedure ChainBand;
    procedure ActionsBand;
    procedure BandContent(AKind: Integer);
    procedure Band(AKind: Integer; ALast: Boolean);
    procedure DrawPart(AFrom, ATill: Integer);
    function BackButton(ANavHeight: Integer): TRect;
    procedure PathItems;
    procedure Navigation;
    procedure DebugValue;
    procedure DebugNote(const ANote: TAtlasDebugValueNote);
    procedure Problems;
    procedure Header;
    /// <summary>Index des nächsten Verweises, der in [APos, ATill) hineinreicht; -1 ohne.</summary>
    function NextLink(APos, ATill: Integer): Integer;
    /// <summary>Verweis ALink zwischen AFrom und ATill; liefert das Ende.</summary>
    function LinkPart(ALink, AFrom, ATill: Integer): Integer;
    procedure Declaration;
    function HasDescription(const AReassigned: string): Boolean;
    procedure Description;
    procedure Run;
  public
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

{ THotSpot }

function NoHot: THotSpot;
begin
  Result.Kind := TAtlasHoverHitKind.Action;
  Result.Index := -1;
  Result.HotIndex := -1;
  Result.HotColor := 0;
end;

/// <summary>Hervorhebung unter der Maus ohne eigene Klickfläche (die legt der Aufrufer über mehrere Stücke).
/// </summary>
function HoverHot(AKind: TAtlasHoverHitKind; AHotIndex: Integer; AColor: TAtlasColor): THotSpot;
begin
  Result.Kind := AKind;
  Result.Index := -1;
  Result.HotIndex := AHotIndex;
  Result.HotColor := AColor;
end;

procedure MakeHot(var AItem: TAtlasHoverItem; AKind: TAtlasHoverHitKind; AIndex: Integer; AColor: TAtlasColor);
begin
  AItem.HotKind := AKind;
  AItem.HotIndex := AIndex;
  AItem.HotColor := AColor;
end;

{ TPainter }

constructor TPainter.Create(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure);
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
  FLayout.Members := TAtlasHoverScroll.None;
end;

function TPainter.Scale(AValue: Integer): Integer;
begin
  // Wie MulDiv(AValue, PPI, 96): auf ganze Pixel gerundet.
  Result := (AValue * FInput.PPI + 48) div 96;
end;

function TPainter.Face(AFont: TAtlasHoverFont; ABold: Boolean): TAtlasHoverFace;
begin
  Result := TAtlasHoverFace.Create(AFont, ABold, False);
end;

function TPainter.Height(const AFace: TAtlasHoverFace): Integer;
begin
  Result := FMeasure.TextHeight(AFace);
end;

function TPainter.Width(const AFace: TAtlasHoverFace; const AText: string): Integer;
begin
  Result := FMeasure.TextWidth(AFace, AText);
end;

function TPainter.NewItem(AKind: TAtlasHoverItemKind; const ARect: TRect; AColor: TAtlasColor): TAtlasHoverItem;
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

procedure TPainter.Add(const AItem: TAtlasHoverItem);
begin
  if FItemCount = Length(FItems) then
  begin
    SetLength(FItems, 2 * FItemCount + 16);
  end;
  FItems[FItemCount] := AItem;
  Inc(FItemCount);
end;

procedure TPainter.Insert(AAt: Integer; const AItem: TAtlasHoverItem);
var
  mIndex: Integer;
begin
  Add(AItem);
  for mIndex := FItemCount - 1 downto AAt + 1 do
  begin
    FItems[mIndex] := FItems[mIndex - 1];
  end;
  FItems[AAt] := AItem;
end;

procedure TPainter.AddHit(AKind: TAtlasHoverHitKind; AIndex: Integer; const ARect: TRect);
begin
  if FHitCount = Length(FHits) then
  begin
    SetLength(FHits, 2 * FHitCount + 8);
  end;
  FHits[FHitCount].Kind := AKind;
  FHits[FHitCount].Index := AIndex;
  FHits[FHitCount].Rect := ARect;
  Inc(FHitCount);
end;

procedure TPainter.AddText(AX, AY: Integer; const AText: string; const AFace: TAtlasHoverFace;
  AColor: TAtlasColor);
var
  mItem: TAtlasHoverItem;
begin
  mItem := NewItem(TAtlasHoverItemKind.Text, Rect(AX, AY, AX, AY), AColor);
  mItem.Text := AText;
  mItem.Face := AFace;
  Add(mItem);
end;

procedure TPainter.AddSmallLine(const AText: string);
var
  mSmallFace: TAtlasHoverFace;
begin
  if AText = '' then
  begin
    Exit;
  end;
  mSmallFace := Face(TAtlasHoverFont.SmallUi, False);
  Inc(FY, Height(mSmallFace) + Scale(2));
  AddText(FLeft, FY, AText, mSmallFace, FColors.Muted);
end;

procedure TPainter.AddLine(ALeft, ATop, ARight: Integer; AColor: TAtlasColor);
begin
  Add(NewItem(TAtlasHoverItemKind.Line, Rect(ALeft, ATop, ARight, ATop), AColor));
end;

procedure TPainter.HorizontalLine(ATop: Integer);
begin
  AddLine(0, ATop, FInput.Width, FColors.Line);
end;

procedure TPainter.SideBar(ATop: Integer; AColor: TAtlasColor);
var
  mBar: TAtlasHoverItem;
begin
  FLeft := Scale(11);
  mBar := NewItem(TAtlasHoverItemKind.RoundFill, Rect(FLeft, ATop + Scale(1), FLeft + Scale(3), FY - Scale(7)),
    AColor);
  mBar.Radius := 1;
  Add(mBar);
end;

procedure TPainter.Block(const AText: string; AColor: TAtlasColor; AMaxLines: Integer);
var
  mBottom: Integer;
  mItem: TAtlasHoverItem;
begin
  if AText = '' then
  begin
    Exit;
  end;
  mBottom := FY + FMeasure.BlockHeight(AText, FRight - FLeft);
  if AMaxLines > 0 then
  begin
    mBottom := Min(mBottom, FY + AMaxLines * Height(Face(TAtlasHoverFont.Ui, False)));
  end;
  mItem := NewItem(TAtlasHoverItemKind.Block, Rect(FLeft, FY, FRight, mBottom), AColor);
  mItem.Text := AText;
  Add(mItem);
  FY := mBottom + Scale(6);
end;

procedure TPainter.Flow(const AText: string; AColor: TAtlasColor; ABold: Boolean; const AHot: THotSpot);
var
  mTextFace: TAtlasHoverFace;
  mTextWidth, mTextHeight: Integer;
  mCell: TRect;
  mItem: TAtlasHoverItem;
begin
  // Fließtext mit Umbruch.
  mTextFace := Face(FFlowFont, ABold);
  mTextWidth := Width(mTextFace, AText);
  mTextHeight := Height(mTextFace);
  if not FNoWrap and (FX + mTextWidth > FRight) and (FX > FLeft) then
  begin
    FX := FLeft;
    Inc(FY, FRowHeight + Scale(4));
    FRowHeight := 0;
  end;
  mCell := Rect(FX, FY, FX + mTextWidth, FY + mTextHeight);
  mItem := NewItem(TAtlasHoverItemKind.Text, mCell, AColor);
  mItem.Text := AText;
  mItem.Face := mTextFace;
  if AHot.HotIndex >= 0 then
  begin
    MakeHot(mItem, AHot.Kind, AHot.HotIndex, AHot.HotColor);
    mItem.HotUnderline := True;
  end;
  Add(mItem);
  if AHot.Index >= 0 then
  begin
    AddHit(AHot.Kind, AHot.Index, mCell);
  end;
  Inc(FX, mTextWidth);
  FRowHeight := Max(FRowHeight, mTextHeight);
end;

procedure TPainter.Flow(const AText: string; AColor: TAtlasColor; ABold: Boolean);
begin
  Flow(AText, AColor, ABold, NoHot);
end;

procedure TPainter.FlowLink(const AText: string; AColor: TAtlasColor; AKind: TAtlasHoverHitKind; ACode: Integer);
var
  mHot: THotSpot;
begin
  mHot := HoverHot(AKind, ACode, AColor);
  mHot.Index := ACode;
  Flow(AText, AColor, False, mHot);
end;

procedure TPainter.EndFlow;
begin
  Inc(FY, FRowHeight);
  FRowHeight := 0;
  FX := FLeft;
end;

function TPainter.BeginLinkRow: TAtlasHoverFont;
begin
  Result := FFlowFont;
  FFlowFont := TAtlasHoverFont.SmallUi;
  FX := FLeft;
  FRowHeight := 0;
end;

procedure TPainter.EndLinkRow(AOldFont: TAtlasHoverFont);
begin
  EndFlow;
  Inc(FY, Scale(6));
  FFlowFont := AOldFont;
end;

{ TPublishedPainter }

procedure TPublishedPainter.ToggleChip(const ACaption: string; AOn: Boolean; AToggle: TAtlasHoverPublishedToggle;
  AX: Integer);
var
  mTextFace: TAtlasHoverFace;
  mCell: TRect;
  mItem: TAtlasHoverItem;
  mLineColor, mTextColor: TAtlasColor;
begin
  // Schalter als umrandetes Kästchen: an in Akzentfarbe, aus gedämpft.
  mTextFace := Face(TAtlasHoverFont.SmallUi, False);
  mCell := Rect(AX, FY, AX + Width(mTextFace, ACaption) + Scale(cAtlasChipPad), FY + Height(mTextFace) + Scale(2));
  if AOn then
  begin
    mLineColor := FColors.Accent;
    mTextColor := FColors.Accent;
  end
  else
  begin
    mLineColor := FColors.Line;
    mTextColor := FColors.Muted;
  end;
  mItem := NewItem(TAtlasHoverItemKind.Frame, mCell, mLineColor);
  mItem.Back := FColors.Surface;
  mItem.Radius := cAtlasChipRadius;
  MakeHot(mItem, TAtlasHoverHitKind.Published, Ord(AToggle), FColors.Accent);
  Add(mItem);
  mItem := NewItem(TAtlasHoverItemKind.CenterText, mCell, mTextColor);
  mItem.Text := ACaption;
  mItem.Face := mTextFace;
  MakeHot(mItem, TAtlasHoverHitKind.Published, Ord(AToggle), FColors.Accent);
  Add(mItem);
  AddHit(TAtlasHoverHitKind.Published, Ord(AToggle), mCell);
end;

function TPublishedPainter.Tag(const ACaption: string; ALineColor, ATextColor: TAtlasColor): TRect;
var
  mSmallFace: TAtlasHoverFace;
  mItem: TAtlasHoverItem;
begin
  mSmallFace := Face(TAtlasHoverFont.SmallUi, False);
  Result := Rect(FX, FY + Scale(1), FX + Width(mSmallFace, ACaption) + Scale(cAtlasChipPad),
    FY + Height(mSmallFace) + Scale(3));
  mItem := NewItem(TAtlasHoverItemKind.Frame, Result, ALineColor);
  mItem.Back := FColors.Surface;
  mItem.Radius := cAtlasChipRadius;
  Add(mItem);
  mItem := NewItem(TAtlasHoverItemKind.CenterText, Result, ATextColor);
  mItem.Text := ACaption;
  mItem.Face := mSmallFace;
  Add(mItem);
end;

function TPublishedPainter.SectionOf(AEvents: Boolean): TMemberSection;
begin
  Result.Events := AEvents;
  if AEvents then
  begin
    Result.Caption := FInput.Texts.PublishedEvents;
    Result.MoreFormat := FInput.Texts.PublishedMoreEvents;
    Result.Collapsed := FInput.View.EventsCollapsed;
    Result.ShowAll := FInput.View.AllEvents;
    Result.Toggle := TAtlasHoverPublishedToggle.Events;
    Result.More := TAtlasHoverPublishedToggle.MoreEvents;
    Result.Limit := cEventRows;
  end
  else
  begin
    Result.Caption := FInput.Texts.PublishedProperties;
    Result.MoreFormat := FInput.Texts.PublishedMoreProperties;
    Result.Collapsed := FInput.View.PropertiesCollapsed;
    Result.ShowAll := FInput.View.AllProperties;
    Result.Toggle := TAtlasHoverPublishedToggle.Properties;
    Result.More := TAtlasHoverPublishedToggle.MoreProperties;
    Result.Limit := cPropertyRows;
  end;
end;

procedure TPublishedPainter.SectionHead(const ASection: TMemberSection);
var
  mCaption: string;
  mHeadFace: TAtlasHoverFace;
  mCell: TRect;
  mItem: TAtlasHoverItem;
begin
  // Abschnittstitel mit ▾ (offen) bzw. ▸ (zu); Klick klappt um.
  mHeadFace := Face(TAtlasHoverFont.SmallMono, True);
  if ASection.Collapsed then
  begin
    mCaption := AnsiUpperCase(ASection.Caption) + ' ▸';
  end
  else
  begin
    mCaption := AnsiUpperCase(ASection.Caption) + ' ▾';
  end;
  mCell := Rect(FLeft, FY, FLeft + Width(mHeadFace, mCaption), FY + Height(mHeadFace));
  mItem := NewItem(TAtlasHoverItemKind.Text, mCell, FColors.Muted);
  mItem.Text := mCaption;
  mItem.Face := mHeadFace;
  MakeHot(mItem, TAtlasHoverHitKind.Published, Ord(ASection.Toggle), FColors.Accent);
  Add(mItem);
  AddHit(TAtlasHoverHitKind.Published, Ord(ASection.Toggle), mCell);
  Inc(FY, Height(mHeadFace) + Scale(5));
end;

function TPublishedPainter.MemberColumns(const ARows: TArray<Integer>; AShown: Integer): TMemberColumns;
var
  mRow, mGap: Integer;
  mMonoFace, mSmallFace: TAtlasHoverFace;
begin
  // Spalten nach den breitesten gezeigten Werten; „deklariert in“ rechtsbündig.
  mMonoFace := Face(TAtlasHoverFont.Mono, False);
  mSmallFace := Face(TAtlasHoverFont.SmallUi, False);
  mGap := Scale(12);
  Result.NameX := FLeft;
  Result.TypeX := Result.NameX + Width(mSmallFace, FInput.Texts.PublishedName);
  for mRow := 0 to AShown - 1 do
  begin
    Result.TypeX := Max(Result.TypeX, Result.NameX + Width(mMonoFace, FData.Members[ARows[mRow]].Name));
  end;
  Inc(Result.TypeX, mGap);
  Result.DefaultX := Result.TypeX + Width(mSmallFace, FInput.Texts.PublishedType);
  for mRow := 0 to AShown - 1 do
  begin
    Result.DefaultX := Max(Result.DefaultX, Result.TypeX + Width(mMonoFace, FData.Members[ARows[mRow]].TypeName));
  end;
  Inc(Result.DefaultX, mGap);
end;

function TPublishedPainter.Clipped(const AFace: TAtlasHoverFace; const AText: string; AMax: Integer): string;
var
  mLength: Integer;
begin
  Result := AText;
  if Width(AFace, Result) <= AMax then
  begin
    Exit;
  end;
  mLength := Length(AText);
  while mLength > 0 do
  begin
    Dec(mLength);
    Result := Copy(AText, 1, mLength) + '…';
    if Width(AFace, Result) <= AMax then
    begin
      Exit;
    end;
  end;
  Result := '';
end;

procedure TPublishedPainter.MemberDefault(const AMember: TAtlasHoverMember; AX, ALimit: Integer);
var
  mMonoFace: TAtlasHoverFace;
  mTag: TRect;
begin
  mMonoFace := Face(TAtlasHoverFont.Mono, False);
  FX := AX;
  if AMember.DefaultKind in [hdExplicit, hdImplicit] then
  begin
    // Lange Mengen ([akLeft, akTop] …) nicht in die Spalte „deklariert in“ laufen lassen.
    AddText(FX, FY, Clipped(mMonoFace, AMember.DefaultValue, ALimit - FX), mMonoFace, FColors.Text);
    Inc(FX, Width(mMonoFace, AMember.DefaultValue + ' '));
  end;
  if AMember.DefaultKind = hdImplicit then
  begin
    // Implizit als gedämpfte Marke.
    mTag := Tag(FInput.Texts.PublishedImplicit, FColors.Line, FColors.Muted);
    Inc(FX, mTag.Width + Scale(4));
  end
  else if AMember.DefaultKind = hdNoDefault then
  begin
    AddText(FX, FY, 'nodefault', mMonoFace, FColors.Muted);
    Inc(FX, Width(mMonoFace, 'nodefault '));
  end;
  if (AMember.Stored <> '') and (FX < ALimit) then
  begin
    AddText(FX, FY, Clipped(mMonoFace, 'stored ' + AMember.Stored, ALimit - FX), mMonoFace, FColors.Muted);
  end;
end;

procedure TPublishedPainter.MemberRow(const AMember: TAtlasHoverMember; const AColumns: TMemberColumns;
  AEvents: Boolean);
var
  mMonoFace, mSmallFace, mSmallMonoFace: TAtlasHoverFace;
begin
  mMonoFace := Face(TAtlasHoverFont.Mono, False);
  mSmallFace := Face(TAtlasHoverFont.SmallUi, False);
  mSmallMonoFace := Face(TAtlasHoverFont.SmallMono, False);
  AddText(AColumns.NameX, FY, AMember.Name, mMonoFace, FColors.Text);
  AddText(AColumns.TypeX, FY, AMember.TypeName, mMonoFace, FColors.Accent);
  if not AEvents then
  begin
    MemberDefault(AMember, AColumns.DefaultX, FRight - Width(mSmallMonoFace, AMember.DeclaringClass) - Scale(8));
  end
  // Am Methodenzeiger-Typ erkannt, nicht am Namen: fremde Typnamen kenntlich machen.
  else if not EndsText('Event', AMember.TypeName) then
  begin
    AddText(AColumns.TypeX + Width(mMonoFace, AMember.TypeName + ' '),
      FY + (Height(mMonoFace) - Height(mSmallFace)) div 2, '(of object)', mSmallFace, FColors.Muted);
  end;
  AddText(FRight - Width(mSmallMonoFace, AMember.DeclaringClass),
    FY + (Height(mMonoFace) - Height(mSmallMonoFace)) div 2, AMember.DeclaringClass, mSmallMonoFace,
    FColors.Muted);
  Inc(FY, Height(mMonoFace) + Scale(3));
end;

procedure TPublishedPainter.MoreLinks(const ASection: TMemberSection; AHidden: Integer);
begin
  // „+ n weitere …“ zeigt alle; bei Ereignissen der Hinweis, woran sie erkannt sind.
  FX := FLeft;
  FRowHeight := 0;
  FFlowFont := TAtlasHoverFont.SmallUi;
  if AHidden > 0 then
  begin
    FlowLink(Format(ASection.MoreFormat, [AHidden]), FColors.Accent, TAtlasHoverHitKind.Published,
      Ord(ASection.More));
  end;
  if ASection.Events then
  begin
    if FX > FLeft then
    begin
      Flow(' · ', FColors.Muted, False);
    end;
    Flow(FInput.Texts.PublishedEventsNote, FColors.Muted, False);
  end;
  if FX > FLeft then
  begin
    Inc(FY, Scale(2));
    EndFlow;
  end;
  FFlowFont := TAtlasHoverFont.Ui;
end;

procedure TPublishedPainter.MemberSection(AEvents: Boolean);
var
  mRows: TArray<Integer>;
  mRow, mShown: Integer;
  mSection: TMemberSection;
  mColumns: TMemberColumns;
  mSmallFace: TAtlasHoverFace;
begin
  mRows := FData.VisibleMembers(AEvents, not FInput.View.HideInherited, FInput.View.OnlyDefaults);
  if Length(mRows) = 0 then
  begin
    Exit;
  end;
  mSection := SectionOf(AEvents);
  SectionHead(mSection);
  if mSection.Collapsed then
  begin
    Exit;
  end;
  mShown := Length(mRows);
  if not mSection.ShowAll then
  begin
    mShown := Min(mShown, mSection.Limit);
  end;
  mColumns := MemberColumns(mRows, mShown);
  if not AEvents then
  begin
    mSmallFace := Face(TAtlasHoverFont.SmallUi, False);
    AddText(mColumns.NameX, FY, FInput.Texts.PublishedName, mSmallFace, FColors.Muted);
    AddText(mColumns.TypeX, FY, FInput.Texts.PublishedType, mSmallFace, FColors.Muted);
    AddText(mColumns.DefaultX, FY, FInput.Texts.PublishedDefault, mSmallFace, FColors.Muted);
    AddText(FRight - Width(mSmallFace, FInput.Texts.PublishedDeclared), FY, FInput.Texts.PublishedDeclared,
      mSmallFace, FColors.Muted);
    Inc(FY, Height(mSmallFace) + Scale(4));
  end;
  for mRow := 0 to mShown - 1 do
  begin
    MemberRow(FData.Members[mRows[mRow]], mColumns, AEvents);
  end;
  MoreLinks(mSection, Length(mRows) - mShown);
  Inc(FY, Scale(8));
end;

procedure TPublishedPainter.PublishedSummary;
var
  mSummary: string;
  mSmallFace: TAtlasHoverFace;
  mChipsWidth, mInheritedWidth: Integer;
begin
  // „published: 38 Properties · 24 Ereignisse“, rechts die Schalter; ohne Platz darunter.
  mSmallFace := Face(TAtlasHoverFont.SmallUi, False);
  mSummary := Format(FInput.Texts.PublishedSummary, [FData.MemberCount(False), FData.MemberCount(True)]);
  mInheritedWidth := Width(mSmallFace, FInput.Texts.PublishedInherited) + Scale(cAtlasChipPad);
  mChipsWidth := mInheritedWidth + Scale(6) + Width(mSmallFace, FInput.Texts.PublishedOnlyDefaults) +
    Scale(cAtlasChipPad);
  AddText(FLeft, FY + Scale(1), mSummary, mSmallFace, FColors.Muted);
  if FLeft + Width(mSmallFace, mSummary) + Scale(12) + mChipsWidth > FRight then
  begin
    Inc(FY, Height(mSmallFace) + Scale(6));
  end;
  ToggleChip(FInput.Texts.PublishedInherited, not FInput.View.HideInherited,
    TAtlasHoverPublishedToggle.ShowInherited, FRight - mChipsWidth);
  ToggleChip(FInput.Texts.PublishedOnlyDefaults, FInput.View.OnlyDefaults, TAtlasHoverPublishedToggle.OnlyDefaults,
    FRight - mChipsWidth + mInheritedWidth + Scale(6));
  Inc(FY, Height(mSmallFace) + Scale(10));
end;

procedure TPublishedPainter.DefaultPropertyRow;
var
  mName, mNote: string;
  mSmallFace, mMonoFace, mHeadFace: TAtlasHoverFace;
  mBracket: Integer;
  mCell: TRect;
begin
  // Standard-Property: „default“ heißt an einer Array-Property nicht Vorgabewert.
  mSmallFace := Face(TAtlasHoverFont.SmallUi, False);
  mMonoFace := Face(TAtlasHoverFont.Mono, False);
  mHeadFace := Face(TAtlasHoverFont.SmallMono, True);
  AddText(FLeft, FY, AnsiUpperCase(FInput.Texts.PublishedArrayProperty), mHeadFace, FColors.Muted);
  Inc(FY, Height(mHeadFace) + Scale(5));
  mName := FData.DefaultProperty;
  mBracket := Pos(']', mName);
  if mBracket > 0 then
  begin
    mName := Copy(mName, 1, mBracket);
  end;
  AddText(FLeft, FY, mName, mMonoFace, FColors.Text);
  FX := FLeft + Width(mMonoFace, mName + ' ');
  mCell := Tag(FInput.Texts.PublishedDefaultProperty, FColors.Accent, FColors.Accent);
  mNote := FInput.Texts.PublishedDefaultPropertyNote;
  if mCell.Right + Scale(8) + Width(mSmallFace, mNote) <= FRight then
  begin
    AddText(mCell.Right + Scale(8), FY + Scale(1), mNote, mSmallFace, FColors.Muted);
  end
  else
  begin
    Inc(FY, Height(mMonoFace) + Scale(3));
    AddText(FLeft, FY, mNote, mSmallFace, FColors.Muted);
  end;
  Inc(FY, Height(mMonoFace) + Scale(8));
end;

procedure TPublishedPainter.ClipMembers(ATop, AFirstItem, AFirstHit: Integer);
var
  mItem: TAtlasHoverItem;
begin
  // Rollbereich (#1841): Grenze aus Zeilen und Platz, Bausteine verschieben, verdeckte Klickflächen streichen.
  if not FLayout.Members.Fit(FInput.Members, ATop, FY, FInput.Width, Height(Face(TAtlasHoverFont.Mono, False)) +
    Scale(3)) then
  begin
    Exit;
  end;
  FLayout.Members.Shift(FItems, AFirstItem, FItemCount, FHits, AFirstHit, FHitCount);
  mItem := NewItem(TAtlasHoverItemKind.RoundFill, FLayout.Members.Thumb(Scale(16), Scale(7), Scale(3)),
    FColors.Muted);
  mItem.Radius := 2;
  Add(mItem);
  FY := FLayout.Members.View.Bottom;
end;

procedure TPublishedPainter.PublishedMembers;
var
  mTop, mFirstItem, mFirstHit: Integer;
begin
  // published-Mitglieder einer Komponentenklasse (#110).
  if (Length(FData.Members) = 0) and (FData.DefaultProperty = '') then
  begin
    Exit;
  end;
  HorizontalLine(FY);
  Inc(FY, Scale(7));
  if Length(FData.Members) > 0 then
  begin
    PublishedSummary;
  end;
  // Tabellen und Standard-Property scrollen; Zusammenfassung und Schalter bleiben stehen.
  mTop := FY;
  mFirstItem := FItemCount;
  mFirstHit := FHitCount;
  if Length(FData.Members) > 0 then
  begin
    MemberSection(False);
    MemberSection(True);
  end;
  if FData.DefaultProperty <> '' then
  begin
    DefaultPropertyRow;
  end;
  ClipMembers(mTop, mFirstItem, mFirstHit);
  FX := FLeft;
end;

{ TBuilder }

procedure TBuilder.Chip(const AText: string; ACurrent: Boolean; AIndex: Integer);
var
  mTextFace: TAtlasHoverFace;
  mTextWidth, mTextHeight: Integer;
  mCell: TRect;
  mFrame, mText: TAtlasHoverItem;
begin
  // Glied der Vererbungskette als umrandetes Kästchen; das angezeigte in Akzentfarbe.
  mTextFace := Face(TAtlasHoverFont.Mono, ACurrent);
  mTextWidth := Width(mTextFace, AText);
  mTextHeight := Height(mTextFace) + Scale(2);
  if (FX + mTextWidth + Scale(cAtlasChipPad) > FRight) and (FX > FLeft) then
  begin
    FX := FLeft;
    Inc(FY, FRowHeight + Scale(4));
    FRowHeight := 0;
  end;
  mCell := Rect(FX, FY, FX + mTextWidth + Scale(cAtlasChipPad), FY + mTextHeight);
  mFrame := NewItem(TAtlasHoverItemKind.Frame, mCell, FColors.Accent);
  mText := NewItem(TAtlasHoverItemKind.Text, Rect(mCell.Left + Scale(cAtlasChipPad div 2), mCell.Top + Scale(1),
    mCell.Left + Scale(cAtlasChipPad div 2), mCell.Top + Scale(1)), FColors.Accent);
  if not ACurrent then
  begin
    mFrame.Color := FColors.Line;
    mFrame.HotColor := FColors.Line;
    MakeHot(mFrame, TAtlasHoverHitKind.Ancestor, AIndex, FColors.Accent);
    mText.Color := FColors.Text;
    MakeHot(mText, TAtlasHoverHitKind.Ancestor, AIndex, FColors.Accent);
  end;
  mFrame.Back := FColors.Surface;
  mFrame.Radius := cAtlasChipRadius;
  Add(mFrame);
  mText.Text := AText;
  mText.Face := mTextFace;
  Add(mText);
  if not ACurrent then
  begin
    AddHit(TAtlasHoverHitKind.Ancestor, AIndex, mCell);
  end;
  FX := mCell.Right;
  FRowHeight := Max(FRowHeight, mTextHeight);
end;

procedure TBuilder.ActionItem(const AKey, ACaption: string; AAction: TAtlasHoverAction; AEnabled: Boolean);
var
  mKeyColor: TAtlasColor;
  mTotal, mStart, mHotIndex: Integer;
begin
  // Taste in Akzentfarbe, Beschriftung gedämpft; bleibt in einer Zeile.
  if FX > FLeft then
  begin
    Inc(FX, Scale(14));
  end;
  mTotal := Width(Face(TAtlasHoverFont.SmallUi, True), AKey + ' ') +
    Width(Face(TAtlasHoverFont.SmallUi, False), ACaption);
  if (FX + mTotal > FRight) and (FX > FLeft) then
  begin
    FX := FLeft;
    Inc(FY, FRowHeight + Scale(3));
    FRowHeight := 0;
  end;
  mKeyColor := FColors.Muted;
  mHotIndex := -1;
  if AEnabled then
  begin
    mKeyColor := FColors.Accent;
    mHotIndex := Ord(AAction);
  end;
  mStart := FX;
  Flow(AKey + ' ', mKeyColor, True);
  Flow(ACaption, FColors.Muted, False, HoverHot(TAtlasHoverHitKind.Action, mHotIndex, FColors.Text));
  if AEnabled then
  begin
    AddHit(TAtlasHoverHitKind.Action, Ord(AAction), Rect(mStart, FY, FX, FY + FRowHeight));
  end;
end;

procedure TBuilder.ProblemLink(const ACaption: string; AProblem: Integer; AAction: TAtlasHoverProblemAction);
begin
  if FX > FLeft then
  begin
    Inc(FX, Scale(12));
  end;
  FlowLink(ACaption, FColors.Accent, TAtlasHoverHitKind.ProblemAction,
    TAtlasHoverLayout.ProblemActionCode(AProblem, AAction));
end;

procedure TBuilder.RelatedLinks(const AProblem: TAtlasProblem; AIndex: Integer);
var
  mOldFont: TAtlasHoverFont;
  mItem: Integer;
  mCycle: Boolean;
  mSeparator: string;
begin
  mCycle := AProblem.Code = TAtlasProblem.cUsesCycleCode;
  if (AProblem.Related = nil) and not mCycle then
  begin
    Exit;
  end;
  mSeparator := ' · ';
  if mCycle then
  begin
    mSeparator := ' → ';
  end;
  mOldFont := BeginLinkRow;
  for mItem := 0 to Min(High(AProblem.Related), cMaxRelated - 1) do
  begin
    if mItem > 0 then
    begin
      Flow(mSeparator, FColors.Muted, False);
    end;
    FlowLink(AProblem.Related[mItem].Message, FColors.Accent, TAtlasHoverHitKind.ProblemAction,
      TAtlasHoverLayout.ProblemActionCode(AIndex, TAtlasHoverProblemAction.Related, mItem));
  end;
  if mCycle and (FInput.Texts.ShowGraph <> '') then
  begin
    ProblemLink(FInput.Texts.ShowGraph, AIndex, TAtlasHoverProblemAction.ShowGraph);
  end;
  EndLinkRow(mOldFont);
end;

procedure TBuilder.SeverityPill(const AProblem: TAtlasProblem);
var
  mPillFace: TAtlasHoverFace;
  mCaption: string;
  mColor: TAtlasColor;
  mBox: TRect;
  mItem: TAtlasHoverItem;
begin
  // Farbe und Text wie die Spalten Icon und Art im Fenster „Atlas-Prüfung“: information und hint sind Info.
  case AProblem.Severity of
    TAtlasProblemSeverity.Error:
      begin
        mCaption := FInput.Texts.KindError;
        mColor := FColors.Error;
      end;
    TAtlasProblemSeverity.Warning:
      begin
        mCaption := FInput.Texts.KindWarning;
        mColor := FColors.Warn;
      end;
  else
    mCaption := FInput.Texts.KindInfo;
    mColor := FColors.Accent;
  end;
  if mCaption = '' then
  begin
    Exit;
  end;
  if AProblem.Stale then
  begin
    mColor := TAtlasColorMath.Mix(mColor, FColors.Surface, cAtlasMixFaded);
  end;
  // Kleine UI-Schrift statt Badge: Die Badge-Schrift richtet sich beim Zeichnen nach der Höhe des Kästchens, das
  // Kästchen hier nach der gemessenen Schrift; gemessen wurde sie ohne Kästchen (Windows-Standardschrift), das
  // Kästchen geriet zu groß und der Text darin kleiner.
  mPillFace := Face(TAtlasHoverFont.SmallUi, True);
  mBox := Rect(FLeft, FY + Scale(1), FLeft + Width(mPillFace, mCaption) + Scale(12), FY + Scale(1) +
    Max(Height(mPillFace) + Scale(2), Scale(15)));
  mItem := NewItem(TAtlasHoverItemKind.RoundFill, mBox, TAtlasColorMath.Mix(mColor, FColors.Surface, 0.16));
  mItem.Radius := 7;
  Add(mItem);
  mItem := NewItem(TAtlasHoverItemKind.CenterText, mBox, mColor);
  mItem.Text := mCaption;
  mItem.Face := mPillFace;
  Add(mItem);
  FLeft := mBox.Right + Scale(6);
end;

procedure TBuilder.RuleActions(const AProblem: TAtlasProblem; AIndex: Integer);
var
  mOldFont: TAtlasHoverFont;
  mStart, mCode: Integer;
  mHot: THotSpot;
begin
  // Aktionszeile eines Regelbefunds (#909): Korrektur (nur, wenn die Regel eine hat), unterdrücken, einstellen.
  mOldFont := BeginLinkRow;
  if AProblem.FixTitle <> '' then
  begin
    mStart := FX;
    mCode := TAtlasHoverLayout.ProblemActionCode(AIndex, TAtlasHoverProblemAction.Fix);
    mHot := HoverHot(TAtlasHoverHitKind.ProblemAction, mCode, FColors.Accent);
    Flow('Alt+Enter: ', FColors.Accent, True, mHot);
    Flow(AProblem.FixTitle, FColors.Accent, True, mHot);
    AddHit(TAtlasHoverHitKind.ProblemAction, mCode, Rect(mStart, FY, FX, FY + FRowHeight));
    if FLayout.FixProblem < 0 then
    begin
      FLayout.FixProblem := AIndex;
    end;
  end;
  // Syntaxfehler (#1022) lassen sich nicht unterdrücken, nur beheben oder einstellen.
  if AProblem.CanSuppress then
  begin
    ProblemLink(FInput.Texts.Suppress, AIndex, TAtlasHoverProblemAction.SuppressLine);
  end;
  ProblemLink(FInput.Texts.Configure, AIndex, TAtlasHoverProblemAction.Configure);
  if Explanation(AIndex, mExplanation) then
  begin
    ProblemLink(FInput.Texts.Explain, AIndex, TAtlasHoverProblemAction.Explain);
  end;
  EndLinkRow(mOldFont);
end;

function TBuilder.Explanation(AIndex: Integer; out AExplanation: TAtlasHoverExplanation): Boolean;
begin
  AExplanation := Default(TAtlasHoverExplanation);
  Result := (AIndex <= High(FInput.View.Explanations)) and FInput.View.Explanations[AIndex].Known;
  if Result then
  begin
    AExplanation := FInput.View.Explanations[AIndex];
  end;
end;

procedure TBuilder.Cause(AIndex: Integer);
var
  mExplanation: TAtlasHoverExplanation;
begin
  if Explanation(AIndex, mExplanation) and (mExplanation.Cause <> '') then
  begin
    Block(Format(FInput.Texts.Cause, [mExplanation.Cause]), FColors.Muted, cCauseLines);
  end;
end;

procedure TBuilder.MessageActions(AIndex: Integer);
var
  mOldFont: TAtlasHoverFont;
  mExplanation: TAtlasHoverExplanation;
begin
  if not Explanation(AIndex, mExplanation) then
  begin
    Exit;
  end;
  mOldFont := BeginLinkRow;
  ProblemLink(FInput.Texts.Explain, AIndex, TAtlasHoverProblemAction.Explain);
  if mExplanation.DocWiki <> '' then
  begin
    ProblemLink(FInput.Texts.DocWiki, AIndex, TAtlasHoverProblemAction.DocWiki);
  end;
  EndLinkRow(mOldFont);
end;

procedure TBuilder.UsesActions(const AProblem: TAtlasProblem; AIndex: Integer);
var
  mOldFont: TAtlasHoverFont;
begin
  mOldFont := BeginLinkRow;
  if AProblem.UsesState = TAtlasProblem.cUsesUnused then
  begin
    ProblemLink(FInput.Texts.UsesRemove, AIndex, TAtlasHoverProblemAction.RemoveUses);
    if AProblem.UsesUnusedCount > 1 then
    begin
      ProblemLink(FInput.Texts.UsesRemoveAll, AIndex, TAtlasHoverProblemAction.RemoveAllUses);
    end;
  end
  else
  begin
    ProblemLink(FInput.Texts.UsesMove, AIndex, TAtlasHoverProblemAction.MoveUses);
  end;
  EndLinkRow(mOldFont);
end;

function TBuilder.RuleSource(const AProblem: TAtlasProblem): string;
begin
  // „Atlas · loop-off-by-one“, „dcc · W1036“, „Atlas · syntax“ (#1022). Vom Build bestätigt (#1024):
  // „Atlas + dcc · argument-count-mismatch · vom Compiler bestätigt (E2035)“.
  Result := AProblem.Source;
  if Result = '' then
  begin
    Result := FInput.Texts.SourceAtlas;
  end;
  if AProblem.Confirmed then
  begin
    Result := TAtlasProblem.cConfirmedSource;
  end;
  if AProblem.Code <> '' then
  begin
    Result := Result + ' · ' + AProblem.Code;
  end;
  if not AProblem.Confirmed then
  begin
    Exit;
  end;
  if FInput.HideCompilerCode or (AProblem.ConfirmedCode = '') then
  begin
    Result := Result + ' · ' + FInput.Texts.Confirmed;
  end
  else
  begin
    Result := Result + ' · ' + Format(FInput.Texts.ConfirmedCode, [AProblem.ConfirmedCode]);
  end;
end;

function TBuilder.ProblemSource(const AProblem: TAtlasProblem): string;
begin
  if AProblem.IsUses then
  begin
    Result := FInput.Texts.SourceUses;
  end
  else if AProblem.Unnecessary then
  begin
    Result := FInput.Texts.SourceInactive;
  end
  else
  begin
    Result := RuleSource(AProblem);
  end;
  if AProblem.Stale then
  begin
    Result := Result + ' · ' + FInput.Texts.Stale;
  end;
end;

procedure TBuilder.ProblemDetails(const AProblem: TAtlasProblem; AIndex: Integer);
var
  mSmallFace: TAtlasHoverFace;
begin
  mSmallFace := Face(TAtlasHoverFont.SmallUi, False);
  AddText(FLeft, FY, ProblemSource(AProblem), mSmallFace, FColors.Muted);
  // Konfidenz eines Regeltreffers als eigene Zeile (#144).
  if AIndex <= High(FInput.Texts.Confidences) then
  begin
    AddSmallLine(FInput.Texts.Confidences[AIndex]);
  end;
  // Zusatz der Regel, z. B. der durchsuchte Bereich projektweiter Regeln (#1102).
  AddSmallLine(AProblem.Details);
  Inc(FY, Height(mSmallFace) + Scale(6));
end;

procedure TBuilder.Problem(AIndex: Integer);
var
  mProblem: TAtlasProblem;
  mStart: Integer;
  mIsRule: Boolean;
begin
  mProblem := FInput.View.Problems[AIndex];
  mStart := FY;
  FLeft := Scale(20);
  // uses-Hinweise (#621) und inaktive Zweige (#615) sind keine Befunde: ohne Pille, Meldung mit Code.
  mIsRule := not mProblem.IsUses and not mProblem.Unnecessary;
  if not mIsRule then
  begin
    Block(mProblem.Caption, FColors.Text, 3);
  end
  else if FInput.HideCompilerCode then
  begin
    SeverityPill(mProblem);
    Block(TAtlasProblem.WithoutCompilerCode(mProblem.Message), FColors.Text, 3);
  end
  else
  begin
    SeverityPill(mProblem);
    Block(mProblem.Message, FColors.Text, 3);
  end;
  FLeft := Scale(20);
  Dec(FY, Scale(4));
  ProblemDetails(mProblem, AIndex);
  // Weitere Stellen (#896), z. B. die Units eines Zyklus mit Sprung an ihren uses-Eintrag.
  RelatedLinks(mProblem, AIndex);
  if (mProblem.UsesState = TAtlasProblem.cUsesUnused) or (mProblem.UsesState = TAtlasProblem.cUsesImplementation) then
  begin
    UsesActions(mProblem, AIndex);
  end
  // Aktionszeile nur an Regelbefunden: Compilermeldungen und Syntaxfehler haben keine Regel.
  else if FInput.ProblemActions and mIsRule and not mProblem.IsCompiler and not mProblem.IsIde and
    (mProblem.Code <> '') then
  begin
    RuleActions(mProblem, AIndex);
  end
  // Compilermeldungen (dcc, IDE) mit Katalogeintrag: Ursache, „Erklären“, „DocWiki“ (#54).
  else if mIsRule then
  begin
    Cause(AIndex);
    MessageActions(AIndex);
  end;
  SideBar(mStart, ProblemColor(FColors, mProblem));
end;

procedure TBuilder.Problems;
var
  mIndex: Integer;
begin
  // Probleme an der Mausposition, Fehler zuerst (#909): Farbbalken, Pille mit der Art und Meldung, darunter
  // Herkunft und Regel, bei Regeltreffern die Konfidenz und die Aktionszeile. Klickflächen tragen den Index
  // in View.Problems, nicht die Position im Hover.
  for mIndex in TAtlasHoverLayout.ProblemOrder(FInput.View.Problems) do
  begin
    Problem(mIndex);
  end;
end;

procedure TBuilder.ChainBand;
var
  mChain: TArray<Integer>;
  mItem: Integer;
  mCaption: string;
  mCaptionFace: TAtlasHoverFace;
begin
  Inc(FY, Scale(8));
  if FData.Kind = TAtlasHoverData.cKindClassRef then
  begin
    mCaption := Format(FInput.Texts.TargetType, [FData.ChainOf]);
  end
  else
  begin
    mCaption := FInput.Texts.Inheritance;
  end;
  mCaptionFace := Face(TAtlasHoverFont.SmallMono, True);
  AddText(FLeft, FY, AnsiUpperCase(mCaption), mCaptionFace, FColors.Muted);
  Inc(FY, Height(mCaptionFace) + Scale(6));
  FFlowFont := TAtlasHoverFont.Mono;
  mChain := FData.VisibleChain;
  for mItem := 0 to High(mChain) do
  begin
    if mItem > 0 then
    begin
      Flow(' › ', FColors.Muted, False);
    end;
    if mChain[mItem] < 0 then
    begin
      Flow('…', FColors.Muted, False);
    end
    else
    begin
      Chip(FData.Ancestors[mChain[mItem]].Name, FData.Ancestors[mChain[mItem]].Key = FData.Location.Key,
        mChain[mItem]);
    end;
  end;
  EndFlow;
  Inc(FY, Scale(8));
end;

procedure TBuilder.ActionsBand;
var
  mCaption: string;
begin
  Inc(FY, Scale(6));
  FFlowFont := TAtlasHoverFont.SmallUi;
  ActionItem('F12', Format(FInput.Texts.Navigate, [FData.Title]), TAtlasHoverAction.Navigate, True);
  mCaption := FInput.Texts.Usages;
  if FInput.View.UsagesCount >= 0 then
  begin
    mCaption := Format(FInput.Texts.UsagesCount, [FInput.View.UsagesCount]);
  end;
  ActionItem(FInput.Texts.KeyUsages, mCaption, TAtlasHoverAction.Usages, True);
  // Mit Markierung in der Doku kopiert Strg+C diese, bei Komponentenklassen die Liste (#110), sonst die
  // Deklaration.
  if FInput.HasSelection then
  begin
    mCaption := FInput.Texts.CopySelection;
  end
  else if Length(FData.Members) > 0 then
  begin
    mCaption := FInput.Texts.PublishedCopyList;
  end
  else
  begin
    mCaption := FInput.Texts.Copy;
  end;
  ActionItem(FInput.Texts.KeyCopy, mCaption, TAtlasHoverAction.Copy, True);
  ActionItem('F1', FInput.Texts.Help, TAtlasHoverAction.Help, FData.DocWiki <> '');
  // Geerbte VCL-Mitglieder kennt der Server nur mit den VCL-Quellen im Index (#110).
  if (Length(FData.Members) > 0) and (FInput.Texts.PublishedVclNote <> '') then
  begin
    Inc(FX, Scale(14));
    Flow(FInput.Texts.PublishedVclNote, FColors.Muted, False);
  end;
  EndFlow;
  Inc(FY, Scale(6));
end;

procedure TBuilder.BandContent(AKind: Integer);
begin
  FX := FLeft;
  FRowHeight := 0;
  case AKind of
    cBandChain:
      ChainBand;
    cBandActions:
      ActionsBand;
  end;
  FFlowFont := TAtlasHoverFont.Ui;
end;

procedure TBuilder.Band(AKind: Integer; ALast: Boolean);
var
  mTop, mBandHeight, mFirstItem, mFirstHit: Integer;
begin
  // Abschnitt auf Randfläche mit Linie oben; Fläche und Linie vor den Inhalt, Höhe aus dem Inhalt.
  mTop := FY;
  mFirstItem := FItemCount;
  mFirstHit := FHitCount;
  BandContent(AKind);
  mBandHeight := FY - mTop;
  Insert(mFirstItem, NewItem(TAtlasHoverItemKind.Line, Rect(0, mTop, FInput.Width, mTop), FColors.Line));
  Insert(mFirstItem, NewItem(TAtlasHoverItemKind.Fill, Rect(0, mTop, FInput.Width, mTop + mBandHeight),
    FColors.Gutter));
  if ALast then
  begin
    FLayout.AnchorItem := mFirstItem;
    FLayout.AnchorHit := mFirstHit;
    FLayout.AnchorTop := mTop;
    FLayout.AnchorHeight := mBandHeight;
  end;
end;

procedure TBuilder.DrawPart(AFrom, ATill: Integer);
var
  mItem: TAtlasHoverItem;
begin
  mItem := NewItem(TAtlasHoverItemKind.Styled, Rect(FX, FY, FRight, FY + FLineHeight), FColors.Text);
  mItem.From := AFrom;
  mItem.Till := ATill;
  Add(mItem);
  Inc(FX, FMeasure.DeclarationWidth(AFrom, ATill));
end;

function TBuilder.BackButton(ANavHeight: Integer): TRect;
var
  mItem: TAtlasHoverItem;
begin
  Result := Rect(Scale(8), (ANavHeight - Scale(20)) div 2, Scale(30), (ANavHeight - Scale(20)) div 2 + Scale(20));
  mItem := NewItem(TAtlasHoverItemKind.Frame, Result, FColors.Line);
  mItem.Back := FColors.Surface;
  mItem.Radius := 4;
  if FInput.View.CanGoBack then
  begin
    MakeHot(mItem, TAtlasHoverHitKind.Back, 0, FColors.Accent);
  end;
  Add(mItem);
  mItem := NewItem(TAtlasHoverItemKind.CenterText, Result, FColors.Muted);
  if FInput.View.CanGoBack then
  begin
    mItem.Color := FColors.Text;
    mItem.HotColor := FColors.Text;
  end;
  mItem.Text := '‹';
  mItem.Face := Face(TAtlasHoverFont.Mono, True);
  Add(mItem);
  if FInput.View.CanGoBack then
  begin
    AddHit(TAtlasHoverHitKind.Back, 0, Result);
  end;
end;

procedure TBuilder.PathItems;
var
  mPath: TArray<TAtlasHoverPathItem>;
  mIndex: Integer;
begin
  mPath := FInput.View.Path;
  for mIndex := 0 to High(mPath) do
  begin
    if mIndex > 0 then
    begin
      Flow(' › ', FColors.Muted, False);
    end;
    if mIndex = High(mPath) then
    begin
      Flow(mPath[mIndex].Caption, FColors.Text, True);
    end
    else if mPath[mIndex].Index < 0 then
    begin
      Flow(mPath[mIndex].Caption, FColors.Muted, False);
    end
    else
    begin
      FlowLink(mPath[mIndex].Caption, FColors.Muted, TAtlasHoverHitKind.Path, mPath[mIndex].Index);
    end;
  end;
end;

procedure TBuilder.Navigation;
var
  mNavHeight, mCaptionWidth: Integer;
  mBox: TRect;
  mCaption: string;
  mSmallFace: TAtlasHoverFace;
begin
  // Pfadzeile (nur angeheftet) auf Randfläche: Zurück-Knopf, besuchte Typen, rechts „angeheftet“.
  mNavHeight := Scale(30);
  Add(NewItem(TAtlasHoverItemKind.Fill, Rect(0, 0, FInput.Width, mNavHeight), FColors.Gutter));
  HorizontalLine(mNavHeight - 1);
  mBox := BackButton(mNavHeight);
  FFlowFont := TAtlasHoverFont.Mono;
  FNoWrap := True;
  FY := (mNavHeight - Height(Face(TAtlasHoverFont.Mono, False))) div 2;
  FX := mBox.Right + Scale(6);
  PathItems;
  mSmallFace := Face(TAtlasHoverFont.SmallUi, False);
  mCaption := FInput.Texts.Pinned;
  mCaptionWidth := Width(mSmallFace, mCaption);
  if FX + mCaptionWidth + Scale(12) < FRight then
  begin
    AddText(FRight - mCaptionWidth, (mNavHeight - Height(mSmallFace)) div 2, mCaption, mSmallFace, FColors.Muted);
  end;
  FNoWrap := False;
  FFlowFont := TAtlasHoverFont.Ui;
  FRowHeight := 0;
  FY := mNavHeight + Scale(8);
  FX := FLeft;
end;

procedure TBuilder.DebugValue;
var
  mValue: TAtlasDebugValue;
  mStart: Integer;
  mMonoFace: TAtlasHoverFace;
begin
  // Wert im angehaltenen Debugger (#891): Akzentbalken, Ausdruck in der Editorschrift, darunter der Wert
  // (höchstens sechs Zeilen) bzw. „wird ausgewertet …“.
  mValue := FInput.View.DebugValue;
  mStart := FY;
  FLeft := Scale(20);
  mMonoFace := Face(TAtlasHoverFont.Mono, True);
  AddText(FLeft, FY, mValue.Expression, mMonoFace, FColors.Accent);
  Inc(FY, Height(mMonoFace) + Scale(3));
  if mValue.State = TAtlasDebugValueState.Pending then
  begin
    Block(FInput.Texts.DebugPending, FColors.Muted, 1);
  end
  else if mValue.Explained then
  begin
    DebugNote(mValue.Note);
  end
  else
  begin
    Block(mValue.Text, FColors.Text, 6);
  end;
  SideBar(mStart, FColors.Accent);
end;

procedure TBuilder.DebugNote(const ANote: TAtlasDebugValueNote);
var
  mLine: string;
  mIndex: Integer;
  mOldFont: TAtlasHoverFont;
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
    for mLine in ANote.Checked do
    begin
      Block('• ' + mLine, FColors.Muted, 2);
    end;
  end;
  if Length(ANote.Fixes) = 0 then
  begin
    Exit;
  end;
  mOldFont := BeginLinkRow;
  for mIndex := 0 to High(ANote.Fixes) do
  begin
    if FX > FLeft then
    begin
      Inc(FX, Scale(12));
    end;
    FlowLink(ANote.Fixes[mIndex].Caption, FColors.Accent, TAtlasHoverHitKind.DebugFix, mIndex);
  end;
  EndLinkRow(mOldFont);
end;

procedure TBuilder.Header;
var
  mCaption, mLocation: string;
  mBadge: TAtlasBadgeKind;
  mBox: TRect;
  mItem: TAtlasHoverItem;
  mSmallFace, mLocationFace: TAtlasHoverFace;
begin
  // Kopfzeile: Badge, Art · Herkunft, rechts der Fundort.
  mCaption := FInput.Texts.KindCaption;
  if (mCaption <> '') and (FData.Origin <> '') then
  begin
    mCaption := mCaption + ' · ' + FData.Origin;
  end;
  mLocation := FData.LocationText;
  if (mCaption = '') and (mLocation = '') then
  begin
    Exit;
  end;
  FLineHeight := Max(Height(Face(TAtlasHoverFont.Ui, False)), Scale(17));
  FX := FLeft;
  if FData.Kind <> '' then
  begin
    mBadge := HoverBadgeKind(FData.Badge);
    mBox := Rect(FLeft, FY, FLeft + Scale(24), FY + Scale(17));
    mItem := NewItem(TAtlasHoverItemKind.RoundFill, mBox, FColors.Badges[mBadge].Background);
    mItem.Radius := 4;
    Add(mItem);
    mItem := NewItem(TAtlasHoverItemKind.CenterText, mBox, FColors.Badges[mBadge].Text);
    mItem.Text := FData.Badge;
    mItem.Face := Face(TAtlasHoverFont.Badge, True);
    Add(mItem);
    FX := mBox.Right + Scale(7);
  end;
  mSmallFace := Face(TAtlasHoverFont.SmallUi, False);
  AddText(FX, FY + (FLineHeight - Height(mSmallFace)) div 2, mCaption, mSmallFace, FColors.Muted);
  if mLocation <> '' then
  begin
    mLocationFace := Face(TAtlasHoverFont.SmallMono, False);
    AddText(Max(FX + Width(mSmallFace, mCaption) + Scale(12), FRight - Width(mLocationFace, mLocation)),
      FY + (FLineHeight - Height(mLocationFace)) div 2, mLocation, mLocationFace, FColors.Muted);
  end;
  Inc(FY, FLineHeight + Scale(5));
  FX := FLeft;
end;

function TBuilder.NextLink(APos, ATill: Integer): Integer;
var
  mIndex: Integer;
  mLink: TAtlasHoverLink;
begin
  Result := -1;
  for mIndex := 0 to High(FData.Links) do
  begin
    mLink := FData.Links[mIndex];
    if (mLink.Start + mLink.Length > APos) and (mLink.Start < ATill) and
      ((Result < 0) or (mLink.Start < FData.Links[Result].Start)) then
    begin
      Result := mIndex;
    end;
  end;
end;

function TBuilder.LinkPart(ALink, AFrom, ATill: Integer): Integer;
var
  mLinkFrom, mStart: Integer;
  mArea: TRect;
  mItem: TAtlasHoverItem;
  mMonoFace: TAtlasHoverFace;
begin
  mMonoFace := Face(TAtlasHoverFont.Mono, False);
  mLinkFrom := Max(AFrom, FData.Links[ALink].Start);
  Result := Min(ATill, FData.Links[ALink].Start + FData.Links[ALink].Length);
  if mLinkFrom > AFrom then
  begin
    DrawPart(AFrom, mLinkFrom);
  end;
  mStart := FX;
  Inc(FX, FMeasure.DeclarationWidth(mLinkFrom, Result));
  mArea := Rect(mStart, FY, FX, FY + FLineHeight);
  AddHit(TAtlasHoverHitKind.Link, ALink, mArea);
  AddText(mStart, FY + (FLineHeight - Height(mMonoFace)) div 2,
    Copy(FData.Declaration, mLinkFrom + 1, Result - mLinkFrom), mMonoFace, FColors.Accent);
  mItem := NewItem(TAtlasHoverItemKind.Line, Rect(mArea.Left, mArea.Bottom - Scale(2), mArea.Right,
    mArea.Bottom - Scale(2)), FColors.Accent);
  mItem.HotKind := TAtlasHoverHitKind.Link;
  mItem.HotIndex := ALink;
  mItem.HotPenWidth := Scale(2);
  Add(mItem);
end;

procedure TBuilder.Declaration;
var
  mLines: TArray<TPoint>;
  mLine, mPos, mNext: Integer;
begin
  // Deklaration eingefärbt, an Leerzeichen umbrochen; Typnamen als Verweise in Akzentfarbe, unterstrichen.
  FLineHeight := Height(Face(TAtlasHoverFont.Mono, False)) + Scale(2);
  mLines := FMeasure.DeclarationLines(FRight - FLeft, Scale(16));
  for mLine := 0 to High(mLines) do
  begin
    FX := FLeft;
    if mLine > 0 then
    begin
      FX := FLeft + Scale(16);
    end;
    mPos := mLines[mLine].X;
    while mPos < mLines[mLine].Y do
    begin
      mNext := NextLink(mPos, mLines[mLine].Y);
      if mNext < 0 then
      begin
        DrawPart(mPos, mLines[mLine].Y);
        mPos := mLines[mLine].Y;
      end
      else
      begin
        mPos := LinkPart(mNext, mPos, mLines[mLine].Y);
      end;
    end;
    Inc(FY, FLineHeight);
  end;
  Inc(FY, Scale(6));
  FX := FLeft;
end;

function TBuilder.HasDescription(const AReassigned: string): Boolean;
begin
  Result := (FData.Value <> '') or (FData.Deprecation <> '') or (AReassigned <> '') or FInput.HasDoc;
  if not Result then
  begin
    Result := (FData.LocationText = '') and (FData.UnitName <> '');
  end;
end;

procedure TBuilder.Description;
var
  mReassigned: string;
begin
  // Beschreibung unter einer Linie; nur die XMLDoc scrollt.
  mReassigned := FData.ReassignedText(FInput.Texts.ReassignedOne, FInput.Texts.ReassignedCount);
  if not HasDescription(mReassigned) then
  begin
    Exit;
  end;
  HorizontalLine(FY);
  Inc(FY, Scale(7));
  if FData.LocationText = '' then
  begin
    Block(FData.UnitName, FColors.Muted, 0);
  end;
  if FData.Value <> '' then
  begin
    Block('= ' + FData.Value, FColors.Muted, 0);
  end;
  Block(FData.Deprecation, FColors.Warn, 0);
  Block(mReassigned, FColors.Muted, 0);
  FLayout.DocLeft := FLeft;
  FLayout.DocTop := FY;
  if FInput.HasDoc then
  begin
    Add(NewItem(TAtlasHoverItemKind.Doc, Rect(FLeft, FY, FLeft, FY), FColors.Text));
    Inc(FY, FInput.DocHeight + Scale(6));
  end;
  Inc(FY, Scale(1));
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
  begin
    Navigation;
  end;
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
  begin
    Band(cBandChain, not FData.Location.HasLocation);
  end;
  if FData.Location.HasLocation then
  begin
    Band(cBandActions, True);
  end;
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
  mBuilder: TBuilder;
begin
  mBuilder := TBuilder.Create(AInput, AMeasure);
  try
    Result := mBuilder.Layout;
  finally
    mBuilder.Free;
  end;
end;

function TAtlasHoverLayout.HitAt(const APoint: TPoint): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Hits) do
  begin
    if Hits[mIndex].Rect.Contains(APoint) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasHoverLayout.ProblemActionCode(AProblem: Integer; AAction: TAtlasHoverProblemAction): Integer;
begin
  Result := ProblemActionCode(AProblem, AAction, 0);
end;

class function TAtlasHoverLayout.ProblemActionCode(AProblem: Integer; AAction: TAtlasHoverProblemAction;
  AItem: Integer): Integer;
begin
  Result := (AProblem * cMaxRelated + AItem) * (Ord(High(TAtlasHoverProblemAction)) + 1) + Ord(AAction);
end;

class procedure TAtlasHoverLayout.DecodeProblemAction(ACode: Integer; out AProblem: Integer;
  out AAction: TAtlasHoverProblemAction);
var
  mItem: Integer;
begin
  DecodeProblemAction(ACode, AProblem, AAction, mItem);
end;

class procedure TAtlasHoverLayout.DecodeProblemAction(ACode: Integer; out AProblem: Integer;
  out AAction: TAtlasHoverProblemAction; out AItem: Integer);
var
  mRest: Integer;
begin
  AAction := TAtlasHoverProblemAction(ACode mod (Ord(High(TAtlasHoverProblemAction)) + 1));
  mRest := ACode div (Ord(High(TAtlasHoverProblemAction)) + 1);
  AProblem := mRest div cMaxRelated;
  AItem := mRest mod cMaxRelated;
end;

class function TAtlasHoverLayout.ProblemOrder(const AProblems: TArray<TAtlasProblem>): TArray<Integer>;
var
  mIndex, mCount: Integer;
begin
  // Fehler zuerst, die übrigen in ihrer Reihenfolge (stabil).
  Result := nil;
  SetLength(Result, Length(AProblems));
  mCount := 0;
  for mIndex := 0 to High(AProblems) do
  begin
    if AProblems[mIndex].Severity = TAtlasProblemSeverity.Error then
    begin
      Result[mCount] := mIndex;
      Inc(mCount);
    end;
  end;
  for mIndex := 0 to High(AProblems) do
  begin
    if AProblems[mIndex].Severity <> TAtlasProblemSeverity.Error then
    begin
      Result[mCount] := mIndex;
      Inc(mCount);
    end;
  end;
end;

function TAtlasHoverLayout.NextProblemHit(AHot: Integer; AForward: Boolean): Integer;
var
  mStep, mIndex, mTries: Integer;
begin
  Result := -1;
  if Length(Hits) = 0 then
  begin
    Exit;
  end;
  mStep := 1;
  if not AForward then
  begin
    mStep := -1;
  end;
  mIndex := AHot;
  if (mIndex < 0) and not AForward then
  begin
    mIndex := 0;
  end;
  for mTries := 1 to Length(Hits) do
  begin
    mIndex := (mIndex + mStep + Length(Hits)) mod Length(Hits);
    if Hits[mIndex].Kind = TAtlasHoverHitKind.ProblemAction then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasHoverLayout.IsHot(AHot: Integer; AKind: TAtlasHoverHitKind; AIndex: Integer): Boolean;
begin
  Result := (AHot >= 0) and (AHot <= High(Hits)) and (Hits[AHot].Kind = AKind) and (Hits[AHot].Index = AIndex);
end;

procedure TAtlasHoverLayout.Anchor(AClientHeight: Integer);
var
  mWanted, mDelta, mIndex: Integer;
begin
  if AnchorItem < 0 then
  begin
    Exit;
  end;
  mWanted := Max(0, AClientHeight - AnchorHeight - AnchorTop);
  mDelta := mWanted - AnchorShift;
  if mDelta = 0 then
  begin
    Exit;
  end;
  for mIndex := AnchorItem to High(Items) do
  begin
    Items[mIndex].Rect.Offset(0, mDelta);
  end;
  for mIndex := AnchorHit to High(Hits) do
  begin
    Hits[mIndex].Rect.Offset(0, mDelta);
  end;
  AnchorShift := mWanted;
end;

end.
