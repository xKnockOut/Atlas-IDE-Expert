unit Atlas.Core.Hover.Layout;

// Satz des Hover-Tooltips ohne VCL: Build rechnet aus dem Inhalt (TAtlasHoverView), der Breite und einem
// Mess-Rückruf alle Positionen, Klickflächen und Zeichenbausteine aus; das Fenster (Atlas.UI.Hover.Tip) zeichnet
// nur noch die Bausteine in Reihenfolge. Gebaut wird je Inhalt, Breite und Doku-Höhe, nicht je Paint oder
// Mausbewegung. Der Hot-Zustand (Maus über Link, Kette, Pfad, Aktion) ändert nur Farben, Unterstreichung und
// Linienstärke; dafür trägt ein Baustein Art und Index der Klickfläche.
// Aufbau wie bisher: Pfadzeile (angeheftet), Wert im Debugger (#891), Probleme, Kopfzeile, Deklaration mit
// Verweisen, Beschreibung mit Platz für die XMLDoc, Vererbung bzw. Zieltyp und Aktionsleiste auf Randflächen; die
// letzte Randfläche sitzt beim Zeichnen am unteren Fensterrand (Anchor).
// Unter einem Hinweis zu einem uses-Eintrag (#621) stehen seine Aktionen als Links: Entfernen, Alle ungenutzten
// entfernen (ab zwei), In implementation-uses verschieben; ihre Klickfläche trägt Problem und Aktion
// (TAtlasHoverProblemActionCode).
// Befund-Hover (#909): Fehler zuerst, je Befund eine Schweregrad-Pille (Error, Warnung, Info) vor der Meldung,
// darunter klein „Atlas · Regel-ID“ bzw. „dcc · W1036“, die Konfidenz, wenn sie nicht hoch ist, und mit
// Input.ProblemActions die Aktionszeile „Alt+Enter: <Korrektur>“ (nur mit Korrektur), „Für diese Zeile
// unterdrücken“, „Regel einstellen…“.
// Erklärungen (#54): Zu einer Compilermeldung mit Katalogeintrag (View.Explanations) steht klein „Typische
// Ursache: …“ unter der Meldung, darunter die Links „Erklären“ (Dialog mit Beispiel) und „DocWiki“; Regelbefunde
// bekommen „Erklären“ in ihrer Aktionszeile. Ein fehlgeschlagener Test mit erwartetem und erhaltenem Wert
// (View.Comparisons, #1779) bekommt davor „Vergleichen“.
// Weitere Stellen eines Befunds (relatedInformation, #896) stehen darunter als Links, beim Unit-Zyklus als Pfad
// „uC → uA → uB → uC“ und mit „Graph zeigen“; ihre Klickfläche trägt Problem, Aktion Related und die Stelle.
// Mit Input.RuleExamples (hover.ruleExamples, #145) steht in der Aktionszeile „Beispiel zeigen“; ist
// View.Examples für das Problem gesetzt, folgen über der Aktionszeile Beschreibung und Beispiel falsch/richtig
// aus dem Regelkatalog (je Beispiel höchstens cExampleMaxLines Zeilen) und der Link heißt „Beispiel ausblenden“.
// Bei Komponentenklassen (#110) folgt unter der Beschreibung „published: n Properties · m Ereignisse“ mit den
// Schaltern „geerbte“ und „nur mit default“, dann die Tabellen PROPERTIES (Name, Typ, Vorgabe, deklariert in) und
// EREIGNISSE, je auf- und zuklappbar und auf die ersten Zeilen gekürzt („+ n weitere …“ zeigt alle), und die
// Standard-Property einer Array-Property. Die Schalter tragen die Klickfläche Published mit
// Ord(TAtlasHoverPublishedToggle); TAtlasHoverView.Toggle schaltet um. Strg+C heißt dann „Liste kopieren“.
// Die Tabellen und die Standard-Property bilden einen Rollbereich: Ist er höher als Input.Members.MaxLines
// Tabellenzeilen (hover.membersMaxLines) bzw. als Input.Members.Limit (Platz auf dem Bildschirm), zeigt der
// Tooltip nur Members.View mit einem Daumen am rechten Rand (TAtlasHoverScroll, Atlas.Core.Hover.Items, #1841).

interface

uses
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.Texts,
  Atlas.Core.Hover.View,
  Atlas.Core.Hover.Layout.Contract;

type
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
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Explanation,
  Atlas.Core.Problems.Colors,
  Atlas.Core.Hover.Layout.Painter,
  Atlas.Core.Hover.Layout.Members;

const
  cBandChain = 0;
  cBandActions = 1;
  /// <summary>Höchstens so viele Zeilen „Typische Ursache“ (#54).</summary>
  cCauseLines = 3;
  /// <summary>Beispiel aus dem Regelkatalog (#145): Zeilen je Beispiel und der Beschreibung.</summary>
  cExampleMaxLines = 8;
  cExampleDescriptionLines = 6;
  /// <summary>Abstände eines Beispiels bei 96 dpi: Rand der Fläche oben, unten und rechts, Einzug des Codes,
  /// Abstand darunter.</summary>
  cExamplePadding = 4;
  cExampleIndent = 8;
  cExampleGap = 6;

type
  /// <summary>Abschnitte des Tooltips der Reihe nach.</summary>
  TBuilder = class(TAtlasHoverMembersPainter)
  private
    FLayout: TAtlasHoverLayout;
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
    /// <summary>Beschreibung und Beispiel falsch/richtig unter Problem AIndex, wenn aufgeklappt (#145).</summary>
    procedure RuleExample(AIndex: Integer);
    /// <summary>Überschrift ACaption in AColor und darunter ACode in Festbreitenschrift auf abgesetzter Fläche.
    /// </summary>
    procedure ExampleCode(const ACaption, ACode: string; AColor: TAtlasColor);
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

{ TBuilder }

constructor TBuilder.Create(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure);
begin
  inherited Create(AInput, AMeasure);
  FLayout := Default(TAtlasHoverLayout);
  FLayout.AnchorItem := -1;
  FLayout.AnchorHit := -1;
  FLayout.FixProblem := -1;
end;

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
    TAtlasHoverProblemActionCode.Encode(AProblem, AAction));
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
  for mItem := 0 to Min(High(AProblem.Related), TAtlasHoverProblemActionCode.cMaxRelated - 1) do
  begin
    if mItem > 0 then
    begin
      Flow(mSeparator, FColors.Muted, False);
    end;
    FlowLink(AProblem.Related[mItem].Message, FColors.Accent, TAtlasHoverHitKind.ProblemAction,
      TAtlasHoverProblemActionCode.Encode(AIndex, TAtlasHoverProblemAction.Related, mItem));
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
  mHot: TAtlasHoverHotSpot;
  mExplanation: TAtlasHoverExplanation;
begin
  // Aktionszeile eines Regelbefunds (#909): Korrektur (nur, wenn die Regel eine hat), unterdrücken, einstellen.
  mOldFont := BeginLinkRow;
  if AProblem.FixTitle <> '' then
  begin
    mStart := FX;
    mCode := TAtlasHoverProblemActionCode.Encode(AIndex, TAtlasHoverProblemAction.Fix);
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
  // Beschreibung und Beispiel aus dem Regelkatalog (#145): klappt im Tooltip auf, F1 bleibt bei der Regelseite.
  if FInput.RuleExamples then
  begin
    ProblemLink(IfThen(FInput.View.ExampleShown(AIndex), FInput.Texts.HideExample, FInput.Texts.ShowExample), AIndex,
      TAtlasHoverProblemAction.Example);
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
  if not Explanation(AIndex, mExplanation) and not FInput.View.CanCompare(AIndex) then
  begin
    Exit;
  end;
  mOldFont := BeginLinkRow;
  // Fehlgeschlagener Test mit erwartetem und erhaltenem Wert (#1779).
  if FInput.View.CanCompare(AIndex) then
  begin
    ProblemLink(FInput.Texts.Compare, AIndex, TAtlasHoverProblemAction.Compare);
  end;
  if mExplanation.Known then
  begin
    ProblemLink(FInput.Texts.Explain, AIndex, TAtlasHoverProblemAction.Explain);
  end;
  if mExplanation.DocWiki <> '' then
  begin
    ProblemLink(FInput.Texts.DocWiki, AIndex, TAtlasHoverProblemAction.DocWiki);
  end;
  EndLinkRow(mOldFont);
end;

procedure TBuilder.ExampleCode(const ACaption, ACode: string; AColor: TAtlasColor);
var
  mLines: TArray<string>;
  mCaptionFace, mCodeFace: TAtlasHoverFace;
  mLineHeight, mTop, mBottom, mLine: Integer;
begin
  if ACode = '' then
  begin
    Exit;
  end;
  mCaptionFace := Face(TAtlasHoverFont.SmallUi, True);
  AddText(FLeft, FY, ACaption, mCaptionFace, AColor);
  Inc(FY, Height(mCaptionFace) + Scale(2));
  mLines := TAtlasRuleExplanation.ExampleLines(ACode, cExampleMaxLines);
  mCodeFace := Face(TAtlasHoverFont.SmallMono, False);
  mLineHeight := Height(mCodeFace);
  mTop := FY;
  mBottom := mTop + Length(mLines) * mLineHeight + 2 * Scale(cExamplePadding);
  // Abgesetzte Fläche mit Randstrich in der Farbe von falsch bzw. richtig, wie im Fenster „Regel erklären“.
  Add(NewItem(TAtlasHoverItemKind.Fill, Rect(FLeft, mTop, FRight, mBottom), FColors.Gutter));
  Add(NewItem(TAtlasHoverItemKind.Fill, Rect(FLeft, mTop, FLeft + Scale(2), mBottom), AColor));
  for mLine := 0 to High(mLines) do
  begin
    AddText(FLeft + Scale(cExampleIndent), mTop + Scale(cExamplePadding) + mLine * mLineHeight,
      Clipped(mCodeFace, mLines[mLine], FRight - FLeft - Scale(cExampleIndent + cExamplePadding)), mCodeFace,
      FColors.Text);
  end;
  FY := mBottom + Scale(cExampleGap);
end;

procedure TBuilder.RuleExample(AIndex: Integer);
var
  mExample: TAtlasRuleExplanation;
begin
  if not FInput.RuleExamples or not FInput.View.ExampleShown(AIndex) then
  begin
    Exit;
  end;
  // Ohne Katalogtext setzt der Aufrufer den Hinweis „keine Beschreibung“ als Beschreibung.
  mExample := FInput.View.Examples[AIndex];
  Block(mExample.Description, FColors.Text, cExampleDescriptionLines);
  ExampleCode(FInput.Texts.ExampleBad, mExample.Bad, FColors.Error);
  ExampleCode(FInput.Texts.ExampleGood, mExample.Good, FColors.Add);
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
    RuleExample(AIndex);
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
  for mIndex in FInput.View.ProblemOrder do
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
  Result.Members := FMembers;
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
