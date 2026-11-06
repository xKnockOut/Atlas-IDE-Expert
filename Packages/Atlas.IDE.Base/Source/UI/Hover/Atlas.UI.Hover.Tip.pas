unit Atlas.UI.Hover.Tip;

// Hover-Tooltip auf Bezeichnern (#442) im Stil von Hint und Panel, mit
// Navigation über Typen (#588):
//   - Pfadzeile (nur angeheftet) auf Randfläche: Zurück-Knopf, besuchte Typen,
//     rechts „angeheftet“.
//   - Kopfzeile: Badge, Art und Herkunft, rechts der Fundort.
//   - Eingefärbte Deklaration; Typnamen darin in Akzentfarbe unterstrichen
//     und anklickbar.
//   - Unter einer Linie: Wert, Veraltung und die XMLDoc (#654, #770) formatiert:
//     Abschnitte unter Überschriften, Parameter dreispaltig in der Reihenfolge der
//     Signatur, Rückgabe, Ausnahmen, Hinweise, Beispiel mit Code, Listen,
//     Tabellen. Zugeklappt nur die Beschreibung mit „Mehr anzeigen ▾“ (Einstellung
//     hints.xmlDocExpand); der Klick klappt auf, das Fenster wächst nach unten
//     (ohne Platz dort nach oben), „Weniger anzeigen ▴“ klappt wieder zu. Ist sie höher als der Platz auf dem
//     Bildschirm bzw. als hints.xmlDocMaxLines, scrollt nur sie mit dem
//     Mausrad; Deklaration und Aktionsleiste bleiben stehen. Verweise (cref)
//     zeigen den Typ im Tooltip, mit Strg zur Deklaration; Links öffnen den
//     Browser. Text lässt sich markieren, Strg+C kopiert dann die Markierung.
//   - published-Mitglieder großer Komponenten (#110): Die Tabellen scrollen mit dem
//     Mausrad, wenn sie höher sind als hover.membersMaxLines Zeilen bzw. als der Platz
//     auf dem Bildschirm; Zusammenfassung, Schalter und Aktionsleiste bleiben stehen.
//   - Vererbung bzw. Zieltyp auf Randfläche: Glieder als Kästchen, das
//     angezeigte in Akzentfarbe; mehr als fünf als erste vier, „…“, letztes.
//   - Aktionsleiste auf Randfläche am unteren Rand: Gehe zu, Verwendungen,
//     Deklaration kopieren, Hilfe; Tasten in Akzentfarbe.
// Probleme an der Mausposition (#398) stehen ganz oben, je mit Farbbalken nach
// Schweregrad, Meldung, Regel-ID bzw. Meldungsnummer und Herkunft; ohne
// Bezeichner zeigt der Tooltip nur sie.
// Im angehaltenen Debugger steht darüber der Wert des Ausdrucks unter der Maus
// (#891): Akzentbalken, Ausdruck, Wert bzw. „wird ausgewertet …“; bei „kein
// Zugriff“ die Ursache mit Korrekturen als Verweise (#840, OnDebugFix).
// Ohne Fokus wie alle Atlas-Fenster; Klicks kommen trotzdem an (MA_NOACTIVATE).
// Beim Wechsel des Inhalts bleibt die Position, das Fenster wächst höchstens.
// Satz (P-09): Positionen, Klickflächen und Bausteine rechnet
// Atlas.Core.Hover.Layout ohne VCL einmal je Inhalt, Breite und Doku-Höhe;
// Paint zeichnet nur die Bausteine und färbt den Hot-Zustand.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Atlas.Core.Style.Color,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.History,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.Layout,
  Atlas.Core.Hover.Texts,
  Atlas.UI.Documentation.View,
  Atlas.UI.Popup.Styled,
  Atlas.UI.Popup.Window;

type

  TAtlasHoverRefEvent = procedure(Sender: TObject; const ARef: TAtlasHoverTypeRef; AControl: Boolean) of object;
  TAtlasHoverIndexEvent = procedure(Sender: TObject; AIndex: Integer) of object;
  TAtlasHoverActionEvent = procedure(Sender: TObject; AAction: TAtlasHoverAction) of object;
  TAtlasHoverUrlEvent = procedure(Sender: TObject; const AUrl: string) of object;
  /// <summary>Klick auf eine Aktion unter einem Problem (#621); AProblem ist der Index in View.Problems.
  /// AItem: Stelle in Problem.Related bei der Aktion Related (#896), sonst 0.</summary>
  TAtlasHoverProblemActionEvent = procedure(Sender: TObject; AProblem: Integer;
    AAction: TAtlasHoverProblemAction; AItem: Integer) of object;

  /// <summary>Inhalt des Tooltips: Satz, Doku und Zeichnen (P-09).</summary>
  TAtlasHoverTipView = class(TAtlasPopupWindow)
  public const
    MaxWidth = 460;
  private
    FDeclaration: TAtlasStyledText;
    FProblemActions: Boolean;
    FHideCompilerCode: Boolean;
    /// <summary>Über dem Wort gezeigt: Beim Auf- und Zuklappen bleibt der untere Rand.</summary>
    FAbove: Boolean;
    /// <summary>Rollbereich der published-Mitglieder: Zeilen aus hover.membersMaxLines, Grenze aus dem Platz auf
    /// dem Bildschirm (0 = keine) und Versatz.</summary>
    FMembers: TAtlasHoverScrollRequest;
    /// <summary>Setzt die Doku für die Fensterbreite AWidth (volle Höhe).</summary>
    procedure PrepareDoc(AWidth: Integer);
    /// <summary>Höhe für AWidth mit höchstens AAvailable Pixeln: begrenzt die Doku (scrollt dann).</summary>
    function FitHeight(AWidth, AAvailable: Integer): Integer;
    procedure SetProblemActions(AValue: Boolean);
    procedure SetHideCompilerCode(AValue: Boolean);
    function LayoutKey(AWidth: Integer): string;
    /// <summary>Setzt FLayout für die Fensterbreite AWidth mit der jetzigen Doku-Höhe.</summary>
    procedure BuildLayout(AWidth: Integer);
    procedure PaintLine(const AItem: TAtlasHoverItem; AHot: Boolean; AColor: TAtlasColor);
    procedure PaintText(const AItem: TAtlasHoverItem; const AFace: TAtlasHoverFace; AColor: TAtlasColor);
    procedure PaintCenterText(const AItem: TAtlasHoverItem; const AFace: TAtlasHoverFace; AColor: TAtlasColor);
    procedure PaintBlock(const AItem: TAtlasHoverItem; AColor: TAtlasColor);
    procedure PaintItem(const AItem: TAtlasHoverItem);
    function PreferredWidth: Integer;
  protected
    FView: TAtlasHoverView;
    /// <summary>Satz des Inhalts (P-09); FLayoutKey: Breite, Doku, Schrift, Farben, für die er gilt.</summary>
    FLayout: TAtlasHoverLayout;
    FLayoutKey: string;
    FHot: Integer;
    FDoc: TAtlasDocView;
    function InDoc(AX, AY: Integer): Boolean;
    function DocLinkAt(AX, AY: Integer): Integer;
    /// <summary>„Mehr/Weniger anzeigen“ (#770): klappt um, merkt den Zustand und passt die Höhe an.</summary>
    procedure ToggleDoc;
    /// <summary>Höhe neu nach dem Inhalt, Breite bleibt; wächst nach unten, über dem Wort nach oben.</summary>
    procedure Refit;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Markierter Text der Doku (#654); '' ohne Markierung.</summary>
    function SelectedText: string;
    function HasSelection: Boolean;
    /// <summary>Scrollt die Doku um ASteps Rasterstufen des Mausrads (negativ nach oben).</summary>
    function ScrollDoc(ASteps: Integer): Boolean;
    /// <summary>Scrollt die published-Mitglieder um ASteps Rasterstufen des Mausrads (je drei Zeilen).</summary>
    function ScrollMembers(ASteps: Integer): Boolean;
    /// <summary>Zeigt AView unter AWord (Bildschirmrechteck des Bezeichners).</summary>
    procedure ShowContent(const AView: TAtlasHoverView; const AWord: TRect);
    /// <summary>Tauscht den Inhalt; Position bleibt, Breite und Höhe wachsen höchstens.</summary>
    procedure UpdateContent(const AView: TAtlasHoverView);
    property View: TAtlasHoverView read FView;
    /// <summary>Aktionszeile unter Regelbefunden (hover.problemActions, #909).</summary>
    property ProblemActions: Boolean read FProblemActions write SetProblemActions;
    /// <summary>problems.showCompilerCode aus (#1024).</summary>
    property HideCompilerCode: Boolean read FHideCompilerCode write SetHideCompilerCode;
    /// <summary>hover.membersMaxLines: Zeilen der Mitgliedertabellen ohne Scrollen, 0 = bis zur Bildschirmhöhe.
    /// </summary>
    property MembersMaxLines: Integer read FMembers.MaxLines write FMembers.MaxLines;
  end;

  /// <summary>Tooltip mit Maus, Tastatur im Befund-Hover und Ereignissen.</summary>
  TAtlasHoverTip = class(TAtlasHoverTipView)
  private
    FOnLink: TAtlasHoverRefEvent;
    FOnPath: TAtlasHoverIndexEvent;
    FOnBack: TNotifyEvent;
    FOnAction: TAtlasHoverActionEvent;
    FOnUrl: TAtlasHoverUrlEvent;
    FOnProblemAction: TAtlasHoverProblemActionEvent;
    FOnDebugFix: TAtlasHoverIndexEvent;
    /// <summary>Klick in die Doku: Verweis, Link oder Beginn einer Markierung.</summary>
    procedure DocMouseDown(Shift: TShiftState; X, Y: Integer);
    /// <summary>Schalter der published-Mitglieder (#110): schaltet um und passt die Höhe an.</summary>
    procedure TogglePublished(AToggle: TAtlasHoverPublishedToggle);
    /// <summary>Löst die Aktion der Klickfläche AHit (Index in FLayout.Hits) aus, wenn sie zu einem Problem gehört.
    /// </summary>
    function FireProblemAction(AHit: Integer): Boolean;
    /// <summary>Klick auf die Klickfläche AHit (Index in FLayout.Hits).</summary>
    procedure FireHit(AHit: Integer; Shift: TShiftState);
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    /// <summary>Mausrad um ASteps Stufen: über den Mitgliedern diese, sonst die Doku, ohne Doku die Mitglieder.
    /// </summary>
    procedure Wheel(ASteps: Integer; const AClientPos: TPoint);
  public
    /// <summary>Tastatur im Befund-Hover (#909): Tab bzw. Umschalt+Tab markiert die nächste bzw. vorige Aktion
    /// unter einem Problem; False ohne Aktionen.</summary>
    function StepProblemAction(AForward: Boolean): Boolean;
    /// <summary>Enter: löst die per Tab markierte Aktion aus; False, wenn keine markiert ist.</summary>
    function ActivateProblemAction: Boolean;
    /// <summary>Alt+Enter: Schnellkorrektur des ersten Befunds mit Korrektur; False ohne.</summary>
    function ApplyFix: Boolean;
    function HasProblemActions: Boolean;
    function HasFix: Boolean;
    function ProblemActionMarked: Boolean;
    property OnLink: TAtlasHoverRefEvent read FOnLink write FOnLink;
    property OnPath: TAtlasHoverIndexEvent read FOnPath write FOnPath;
    property OnBack: TNotifyEvent read FOnBack write FOnBack;
    property OnAction: TAtlasHoverActionEvent read FOnAction write FOnAction;
    /// <summary>Klick auf einen Link (href) in der Doku.</summary>
    property OnUrl: TAtlasHoverUrlEvent read FOnUrl write FOnUrl;
    /// <summary>Aktion unter einem uses-Hinweis (#621).</summary>
    property OnProblemAction: TAtlasHoverProblemActionEvent read FOnProblemAction write FOnProblemAction;
    /// <summary>Klick auf eine Korrektur unter „kein Zugriff“ (#840); AIndex in View.DebugValue.Note.Fixes.
    /// </summary>
    property OnDebugFix: TAtlasHoverIndexEvent read FOnDebugFix write FOnDebugFix;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  System.StrUtils,
  Atlas.Core.Style.Palette,
  Atlas.Core.Documentation.Layout,
  Atlas.Core.Documentation.Typeset,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Draw,
  Atlas.UI.Popup.Accessibility;

function HoverKindCaption(const AKind: string): string;
const
  Kinds: array[0..15] of string = ('class', 'classref', 'object', 'record', 'interface', 'helper', 'enum', 'type',
    'method', 'constructor', 'routine', 'property', 'field', 'variable', 'constant', 'enumMember');
  Ids: array[0..15] of TAtlasTextId = (TAtlasTextId.KindClass, TAtlasTextId.KindClassRef, TAtlasTextId.KindObject,
    TAtlasTextId.KindRecord, TAtlasTextId.KindInterface, TAtlasTextId.KindHelper, TAtlasTextId.KindEnum,
    TAtlasTextId.KindType, TAtlasTextId.KindMethod, TAtlasTextId.KindConstructor, TAtlasTextId.KindRoutine,
    TAtlasTextId.KindProperty, TAtlasTextId.KindField, TAtlasTextId.KindVariable, TAtlasTextId.KindConstant,
    TAtlasTextId.KindEnumMember);
var
  mIndex: Integer;
begin
  mIndex := IndexStr(AKind, Kinds);
  if mIndex < 0 then
  begin
    Result := '';
  end
  else
  begin
    Result := TAtlasStrings.Text(Ids[mIndex]);
  end;
end;

/// <summary>Kopfzeile, Navigation und Aktionsleiste.</summary>
procedure SetActionTexts(var ATexts: TAtlasHoverTexts);
begin
  ATexts.Pinned := TAtlasStrings.Text(TAtlasTextId.HoverPinned);
  ATexts.Inheritance := TAtlasStrings.Text(TAtlasTextId.HoverInheritance);
  ATexts.TargetType := TAtlasStrings.Text(TAtlasTextId.HoverTargetType);
  ATexts.Navigate := TAtlasStrings.Text(TAtlasTextId.HoverGoTo);
  ATexts.Usages := TAtlasStrings.Text(TAtlasTextId.HoverUsages);
  ATexts.UsagesCount := TAtlasStrings.Text(TAtlasTextId.HoverUsagesCount);
  ATexts.Copy := TAtlasStrings.Text(TAtlasTextId.HoverCopy);
  ATexts.CopySelection := TAtlasStrings.Text(TAtlasTextId.HoverCopySelection);
  ATexts.Help := TAtlasStrings.Text(TAtlasTextId.HoverHelp);
  ATexts.KeyUsages := TAtlasStrings.Text(TAtlasTextId.HoverKeyUsages);
  ATexts.KeyCopy := TAtlasStrings.Text(TAtlasTextId.HoverKeyCopy);
  ATexts.DebugPending := TAtlasStrings.Text(TAtlasTextId.HoverDebugPending);
  ATexts.DebugExplaining := TAtlasStrings.Text(TAtlasTextId.HoverDebugExplaining);
  ATexts.DebugChecked := TAtlasStrings.Text(TAtlasTextId.HoverDebugChecked);
  ATexts.ReassignedOne := TAtlasStrings.Text(TAtlasTextId.ReassignedOne);
  ATexts.ReassignedCount := TAtlasStrings.Text(TAtlasTextId.ReassignedCount);
end;

/// <summary>Probleme, uses-Hinweise und Befund-Hover (#621, #909, #1024).</summary>
procedure SetProblemTexts(var ATexts: TAtlasHoverTexts);
begin
  ATexts.SourceAtlas := TAtlasStrings.Text(TAtlasTextId.ProblemsSourceAtlas);
  ATexts.Confirmed := TAtlasStrings.Text(TAtlasTextId.ProblemsCompilerConfirmed);
  ATexts.ConfirmedCode := TAtlasStrings.Text(TAtlasTextId.ProblemsCompilerConfirmedCode);
  ATexts.SourceCompiler := TAtlasStrings.Text(TAtlasTextId.ProblemsSourceCompiler);
  ATexts.SourceInactive := TAtlasStrings.Text(TAtlasTextId.ProblemsSourceInactive);
  ATexts.SourceUses := TAtlasStrings.Text(TAtlasTextId.ProblemsSourceUses);
  ATexts.UsesRemove := TAtlasStrings.Text(TAtlasTextId.UsesRemove);
  ATexts.UsesRemoveAll := TAtlasStrings.Text(TAtlasTextId.UsesRemoveAll);
  ATexts.UsesMove := TAtlasStrings.Text(TAtlasTextId.UsesMove);
  ATexts.ShowGraph := TAtlasStrings.Text(TAtlasTextId.HoverShowGraph);
  ATexts.KindError := TAtlasStrings.Text(TAtlasTextId.ProblemsKindError);
  ATexts.KindWarning := TAtlasStrings.Text(TAtlasTextId.ProblemsKindWarning);
  ATexts.KindInfo := TAtlasStrings.Text(TAtlasTextId.ProblemsKindInfo);
  ATexts.Suppress := TAtlasStrings.Text(TAtlasTextId.ProblemsMenuSuppress);
  ATexts.Configure := TAtlasStrings.Text(TAtlasTextId.ProblemsMenuConfigure);
  ATexts.Stale := TAtlasStrings.Text(TAtlasTextId.ProblemsStale);
end;

/// <summary>published-Mitglieder (#110).</summary>
procedure SetPublishedTexts(var ATexts: TAtlasHoverTexts);
begin
  ATexts.PublishedSummary := TAtlasStrings.Text(TAtlasTextId.PublishedSummary);
  ATexts.PublishedInherited := TAtlasStrings.Text(TAtlasTextId.PublishedInherited);
  ATexts.PublishedOnlyDefaults := TAtlasStrings.Text(TAtlasTextId.PublishedOnlyDefaults);
  ATexts.PublishedProperties := TAtlasStrings.Text(TAtlasTextId.PublishedProperties);
  ATexts.PublishedEvents := TAtlasStrings.Text(TAtlasTextId.PublishedEvents);
  ATexts.PublishedName := TAtlasStrings.Text(TAtlasTextId.PublishedName);
  ATexts.PublishedType := TAtlasStrings.Text(TAtlasTextId.PublishedType);
  ATexts.PublishedDefault := TAtlasStrings.Text(TAtlasTextId.PublishedDefault);
  ATexts.PublishedDeclared := TAtlasStrings.Text(TAtlasTextId.PublishedDeclared);
  ATexts.PublishedImplicit := TAtlasStrings.Text(TAtlasTextId.PublishedImplicit);
  ATexts.PublishedMoreProperties := TAtlasStrings.Text(TAtlasTextId.PublishedMoreProperties);
  ATexts.PublishedMoreEvents := TAtlasStrings.Text(TAtlasTextId.PublishedMoreEvents);
  ATexts.PublishedEventsNote := TAtlasStrings.Text(TAtlasTextId.PublishedEventsNote);
  ATexts.PublishedArrayProperty := TAtlasStrings.Text(TAtlasTextId.PublishedArrayProperty);
  ATexts.PublishedDefaultProperty := TAtlasStrings.Text(TAtlasTextId.PublishedDefaultProperty);
  ATexts.PublishedDefaultPropertyNote := TAtlasStrings.Text(TAtlasTextId.PublishedDefaultPropertyNote);
  ATexts.PublishedCopyList := TAtlasStrings.Text(TAtlasTextId.PublishedCopyList);
  ATexts.PublishedVclNote := TAtlasStrings.Text(TAtlasTextId.PublishedVclNote);
end;

/// <summary>Texte des Satzes in der Sprache der Oberfläche.</summary>
function HoverTexts(const AView: TAtlasHoverView): TAtlasHoverTexts;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasHoverTexts);
  Result.KindCaption := HoverKindCaption(AView.Data.Kind);
  SetActionTexts(Result);
  SetProblemTexts(Result);
  SetPublishedTexts(Result);
  Result.Confidences := nil;
  SetLength(Result.Confidences, Length(AView.Problems));
  // Hohe Konfidenz ist der Normalfall und bekommt keine eigene Zeile (#909).
  for mIndex := 0 to High(AView.Problems) do
  begin
    if not SameText(AView.Problems[mIndex].Confidence, 'high') then
    begin
      Result.Confidences[mIndex] := TAtlasStrings.Confidence(AView.Problems[mIndex].Confidence);
    end;
  end;
end;

/// <summary>Wählt die Schrift AFace in ACanvas; Kleinere Schrift für Beschriftungen (UI) bzw. Abschnittstitel
/// (Editorschrift).</summary>
procedure ApplyHoverFace(ACanvas: TCanvas; AFont, AUIFont: TFont; const AFace: TAtlasHoverFace;
  ABadgeHeight: Integer);
begin
  case AFace.Font of
    TAtlasHoverFont.Mono:
      ACanvas.Font := AFont;
    TAtlasHoverFont.SmallUi:
      begin
        ACanvas.Font := AUIFont;
        ACanvas.Font.Height := Round(AUIFont.Height * 0.88);
      end;
    TAtlasHoverFont.SmallMono:
      begin
        ACanvas.Font := AFont;
        ACanvas.Font.Height := Round(AFont.Height * 0.8);
      end;
    TAtlasHoverFont.Badge:
      begin
        // Größe aus der Höhe des Kästchens: nur für Kästchen fester Größe (Kopfzeile), nicht zum Messen.
        ACanvas.Font := AFont;
        ACanvas.Font.Height := -Round(ABadgeHeight * 0.62);
      end;
  else
    ACanvas.Font := AUIFont;
  end;
  ACanvas.Font.Style := [];
  if AFace.Bold then
  begin
    ACanvas.Font.Style := [fsBold];
  end;
  if AFace.Underline then
  begin
    ACanvas.Font.Style := ACanvas.Font.Style + [fsUnderline];
  end;
end;

/// <summary>Braucht der Inhalt die volle Breite (Doku, Kette, Fundort, Pfad, published-Mitglieder)?</summary>
function NeedsFullWidth(const AView: TAtlasHoverView): Boolean;
begin
  Result := (AView.Data.Documentation <> '') or not AView.Data.Doc.IsEmpty or (Length(AView.Data.Ancestors) > 0);
  Result := Result or AView.Data.Location.HasLocation or AView.Pinned or (Length(AView.Data.Members) > 0);
end;

type
  /// <summary>Messen über die Zeichenfläche des Tooltips für TAtlasHoverLayout.</summary>
  TTipMeasure = class(TInterfacedObject, IAtlasHoverMeasure)
  private
    FTip: TAtlasHoverTipView;
  public
    constructor Create(ATip: TAtlasHoverTipView);
    function TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
    function TextHeight(const AFace: TAtlasHoverFace): Integer;
    function BlockHeight(const AText: string; AWidth: Integer): Integer;
    function DeclarationWidth(AFrom, ATill: Integer): Integer;
    function DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
  end;

{ TTipMeasure }

constructor TTipMeasure.Create(ATip: TAtlasHoverTipView);
begin
  inherited Create;
  FTip := ATip;
end;

function TTipMeasure.TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
begin
  ApplyHoverFace(FTip.Canvas, FTip.Font, FTip.UIFont, AFace, 0);
  Result := FTip.Canvas.TextWidth(AText);
end;

function TTipMeasure.TextHeight(const AFace: TAtlasHoverFace): Integer;
begin
  ApplyHoverFace(FTip.Canvas, FTip.Font, FTip.UIFont, AFace, 0);
  Result := FTip.Canvas.TextHeight('Wg');
end;

function TTipMeasure.BlockHeight(const AText: string; AWidth: Integer): Integer;
var
  Area: TRect;
begin
  FTip.Canvas.Font := FTip.UIFont;
  Area := Rect(0, 0, AWidth, 0);
  DrawText(FTip.Canvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
  Result := Area.Bottom;
end;

function TTipMeasure.DeclarationWidth(AFrom, ATill: Integer): Integer;
begin
  FTip.Canvas.Font := FTip.Font;
  Result := FTip.FDeclaration.Width(FTip.Canvas, AFrom, ATill);
end;

function TTipMeasure.DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
begin
  FTip.Canvas.Font := FTip.Font;
  Result := FTip.FDeclaration.WrapAtSpaces(FTip.Canvas, AWidth, AIndent);
end;

{ TAtlasHoverTipView }

constructor TAtlasHoverTipView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Hover;
  FHot := -1;
  FDoc := TAtlasDocView.Create;
end;

destructor TAtlasHoverTipView.Destroy;
begin
  FDoc.Free;
  inherited Destroy;
end;

procedure TAtlasHoverTipView.PrepareDoc(AWidth: Integer);
var
  Doc: TAtlasDoc;
begin
  // Fremde Server liefern nur Klartext: als Beschreibung setzen, ohne Kürzen.
  Doc := FView.Data.Doc;
  if Doc.IsEmpty then
  begin
    Doc := TAtlasDoc.FromText(FView.Data.Documentation);
  end;
  if Doc.IsEmpty then
  begin
    FDoc.Clear;
    Exit;
  end;
  HandleNeeded;
  FDoc.Build(Canvas, TAtlasDocContent.Create(Doc, TAtlasDocSignature.Parse(FView.Data.Declaration),
    TAtlasDocExpandState.Initial(FView.Display.Expand, TAtlasDocSurface.Tooltip)), AWidth - Scale(22),
    TAtlasDocFonts.Create(Font, UIFont, PPI), TAtlasStrings.DocLabels);
end;

procedure TAtlasHoverTipView.ToggleDoc;
begin
  TAtlasDocExpandState.Remember(TAtlasDocSurface.Tooltip, FDoc.Toggle(Canvas));
  FDoc.ClearSelection;
  FDoc.HotLink := -1;
  Refit;
end;

procedure TAtlasHoverTip.TogglePublished(AToggle: TAtlasHoverPublishedToggle);
begin
  FView.Toggle(AToggle);
  FHot := -1;
  FLayoutKey := '';
  Refit;
end;

procedure TAtlasHoverTipView.Refit;
var
  Area, Bounds: TRect;
  NewHeight: Integer;
begin
  Area := WorkAreaAt(BoundsRect.TopLeft);
  NewHeight := FitHeight(Width, Area.Height - Scale(8));
  Bounds := TRect.Create(BoundsRect.TopLeft, Width, NewHeight);
  // Wächst nach unten; über dem Wort bzw. ohne Platz darunter nach oben.
  if FAbove or (Bounds.Bottom > Area.Bottom) then
  begin
    Bounds.SetLocation(Bounds.Left, Max(Area.Top, BoundsRect.Bottom - NewHeight));
  end;
  ShowAt(Bounds);
  Invalidate;
end;

function TAtlasHoverTipView.FitHeight(AWidth, AAvailable: Integer): Integer;
var
  Natural: Integer;
begin
  FDoc.FitHeight(FView.Display.MaxLines, 0);
  FMembers.Limit := 0;
  BuildLayout(AWidth);
  Natural := FLayout.Height;
  // Mitglieder zuerst kürzen (#1841): Sie sind aufgeklappt, um gelesen zu werden; die Doku teilt sich den Rest.
  if (Natural > AAvailable) and (FLayout.Members.View.Height > 0) then
  begin
    FMembers.Limit := Max(1, FLayout.Members.View.Height - (Natural - AAvailable));
    BuildLayout(AWidth);
    Natural := FLayout.Height;
  end;
  if (Natural > AAvailable) and not FDoc.IsEmpty then
  begin
    FDoc.FitHeight(FView.Display.MaxLines, FDoc.Height - (Natural - AAvailable));
    BuildLayout(AWidth);
    Natural := FLayout.Height;
  end;
  Result := Natural;
end;

function TAtlasHoverTipView.InDoc(AX, AY: Integer): Boolean;
begin
  Result := not FDoc.IsEmpty and (AX >= FLayout.DocLeft - Scale(4)) and (AX < FLayout.DocLeft + FDoc.Width + Scale(8)) and
    (AY >= FLayout.DocTop) and (AY < FLayout.DocTop + FDoc.Height);
end;

function TAtlasHoverTipView.DocLinkAt(AX, AY: Integer): Integer;
begin
  Result := -1;
  if InDoc(AX, AY) then
  begin
    Result := FDoc.LinkAt(AX - FLayout.DocLeft, AY - FLayout.DocTop);
  end;
end;

procedure TAtlasHoverTip.DocMouseDown(Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
  Link: TAtlasDocLink;
  Ref: TAtlasHoverTypeRef;
begin
  Index := DocLinkAt(X, Y);
  if Index >= 0 then
  begin
    Link := FDoc.Link(Index);
    if Link.Kind = TAtlasDocLinkKind.Toggle then
    begin
      ToggleDoc;
    end
    else if Link.Kind = TAtlasDocLinkKind.Url then
    begin
      if Assigned(FOnUrl) then
      begin
        FOnUrl(Self, Link.Url);
      end;
    end
    else if Assigned(FOnLink) then
    begin
      // Wie Typnamen der Deklaration (#588): Klick zeigt den Typ, Strg+Klick springt hin.
      Ref := Default(TAtlasHoverTypeRef);
      Ref.Name := Link.Target.Name;
      Ref.UnitName := Link.Target.UnitName;
      Ref.FileName := Link.Target.FileName;
      Ref.Line := Link.Target.Line;
      Ref.Character := Link.Target.Character;
      FOnLink(Self, Ref, ssCtrl in Shift);
    end;
    Exit;
  end;
  if InDoc(X, Y) then
  begin
    FDoc.StartSelection(Canvas, X - FLayout.DocLeft, Y - FLayout.DocTop);
  end
  else
  begin
    FDoc.ClearSelection;
  end;
  Invalidate;
end;

function TAtlasHoverTipView.SelectedText: string;
begin
  Result := FDoc.SelectedText;
end;

function TAtlasHoverTipView.HasSelection: Boolean;
begin
  Result := FDoc.HasSelection;
end;

function TAtlasHoverTipView.ScrollDoc(ASteps: Integer): Boolean;
begin
  Result := FDoc.ScrollBy(ASteps * FDoc.WheelStep);
  if Result then
  begin
    Invalidate;
  end;
end;

function TAtlasHoverTipView.ScrollMembers(ASteps: Integer): Boolean;
var
  mScroll: Integer;
begin
  mScroll := EnsureRange(FLayout.Members.Scroll + ASteps * 3 * FLayout.Members.Row, 0, FLayout.Members.MaxScroll);
  Result := mScroll <> FLayout.Members.Scroll;
  if Result then
  begin
    FMembers.Scroll := mScroll;
    // Sofort neu setzen: Klickflächen unter der Maus gelten schon vor dem nächsten Paint.
    BuildLayout(ClientWidth);
    FLayout.Anchor(ClientHeight);
    Invalidate;
  end;
end;

function TAtlasHoverTipView.LayoutKey(AWidth: Integer): string;
begin
  Result := Format('%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d', [AWidth, FDoc.Height, Ord(FDoc.IsEmpty),
    Ord(FDoc.HasSelection), Ord(FProblemActions), Ord(FHideCompilerCode), PPI, Font.Height, UIFont.Height,
    Integer(Colors.Surface), Integer(Colors.Text), Integer(Colors.Accent), FMembers.MaxLines, FMembers.Limit,
    FMembers.Scroll]);
end;

procedure TAtlasHoverTipView.BuildLayout(AWidth: Integer);
var
  Input: TAtlasHoverInput;
begin
  HandleNeeded;
  Input := Default(TAtlasHoverInput);
  Input.View := FView;
  Input.Width := AWidth;
  Input.PPI := PPI;
  Input.Colors := Colors;
  Input.Texts := HoverTexts(FView);
  Input.HasDoc := not FDoc.IsEmpty;
  Input.DocHeight := FDoc.Height;
  Input.HasSelection := FDoc.HasSelection;
  Input.ProblemActions := FProblemActions;
  Input.HideCompilerCode := FHideCompilerCode;
  Input.Members := FMembers;
  FLayout := TAtlasHoverLayout.Build(Input, TTipMeasure.Create(Self));
  // Nach Umschalten oder Kürzen kann der Versatz zu groß sein; der Satz hat ihn begrenzt.
  FMembers.Scroll := FLayout.Members.Scroll;
  FLayoutKey := LayoutKey(AWidth);
end;

procedure TAtlasHoverTipView.PaintLine(const AItem: TAtlasHoverItem; AHot: Boolean; AColor: TAtlasColor);
begin
  Canvas.Pen.Color := ToColor(AColor);
  if AHot then
  begin
    Canvas.Pen.Width := AItem.HotPenWidth;
  end
  else
  begin
    Canvas.Pen.Width := AItem.PenWidth;
  end;
  Canvas.MoveTo(AItem.Rect.Left, AItem.Rect.Top);
  Canvas.LineTo(AItem.Rect.Right, AItem.Rect.Top);
  Canvas.Pen.Width := 1;
end;

procedure TAtlasHoverTipView.PaintText(const AItem: TAtlasHoverItem; const AFace: TAtlasHoverFace;
  AColor: TAtlasColor);
begin
  ApplyHoverFace(Canvas, Font, UIFont, AFace, 0);
  Canvas.Font.Color := ToColor(AColor);
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(AItem.Rect.Left, AItem.Rect.Top, AItem.Text);
end;

procedure TAtlasHoverTipView.PaintCenterText(const AItem: TAtlasHoverItem; const AFace: TAtlasHoverFace;
  AColor: TAtlasColor);
var
  mArea: TRect;
begin
  ApplyHoverFace(Canvas, Font, UIFont, AFace, AItem.Rect.Height);
  Canvas.Font.Color := ToColor(AColor);
  Canvas.Brush.Style := bsClear;
  mArea := AItem.Rect;
  DrawText(Canvas.Handle, PChar(AItem.Text), -1, mArea, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

procedure TAtlasHoverTipView.PaintBlock(const AItem: TAtlasHoverItem; AColor: TAtlasColor);
var
  mArea: TRect;
begin
  Canvas.Font := UIFont;
  Canvas.Font.Color := ToColor(AColor);
  Canvas.Brush.Style := bsClear;
  mArea := AItem.Rect;
  DrawText(Canvas.Handle, PChar(AItem.Text), -1, mArea, DT_WORDBREAK or DT_NOPREFIX or DT_END_ELLIPSIS);
end;

procedure TAtlasHoverTipView.PaintItem(const AItem: TAtlasHoverItem);
var
  mHot: Boolean;
  mColor: TAtlasColor;
  mFace: TAtlasHoverFace;
  mX: Integer;
begin
  mHot := (AItem.HotIndex >= 0) and FLayout.IsHot(FHot, AItem.HotKind, AItem.HotIndex);
  mColor := AItem.Color;
  mFace := AItem.Face;
  if mHot then
  begin
    mColor := AItem.HotColor;
    mFace.Underline := mFace.Underline or AItem.HotUnderline;
  end;
  case AItem.Kind of
    TAtlasHoverItemKind.Fill:
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := ToColor(mColor);
        Canvas.FillRect(AItem.Rect);
      end;
    TAtlasHoverItemKind.Line:
      PaintLine(AItem, mHot, mColor);
    TAtlasHoverItemKind.Text:
      PaintText(AItem, mFace, mColor);
    TAtlasHoverItemKind.CenterText:
      PaintCenterText(AItem, mFace, mColor);
    TAtlasHoverItemKind.Frame:
      FrameRounded(AItem.Rect, mColor, AItem.Radius, ToColor(AItem.Back));
    TAtlasHoverItemKind.RoundFill:
      FillRounded(AItem.Rect, mColor, AItem.Radius);
    TAtlasHoverItemKind.Block:
      PaintBlock(AItem, mColor);
    TAtlasHoverItemKind.Styled:
      begin
        Canvas.Font := Font;
        mX := AItem.Rect.Left;
        FDeclaration.Draw(TAtlasStyledTarget.Create(Canvas, Colors, Scale(3)), Point(AItem.From, AItem.Till), mX,
          AItem.Rect, False);
      end;
    TAtlasHoverItemKind.Doc:
      FDoc.Paint(Canvas, Colors, AItem.Rect.Left, AItem.Rect.Top);
  end;
end;

function TAtlasHoverTipView.PreferredWidth: Integer;
var
  Widest: Integer;
  Problem: TAtlasProblem;
begin
  HandleNeeded;
  // Breite: Deklaration in einer Zeile, sonst die Höchstbreite.
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Widest := Canvas.TextWidth(FView.Data.Declaration);
  if FView.DebugValue.Visible then
  begin
    Widest := Max(Widest, Canvas.TextWidth(FView.DebugValue.Expression) + Scale(9));
  end;
  Canvas.Font := UIFont;
  if FView.DebugValue.Visible then
  begin
    Widest := Max(Widest, Canvas.TextWidth(FView.DebugValue.Text) + Scale(9));
  end;
  Widest := Max(Widest, Canvas.TextWidth(FView.Data.UnitName));
  for Problem in FView.Problems do
  begin
    Widest := Max(Widest, Canvas.TextWidth(Problem.Caption) + Scale(9));
  end;
  if NeedsFullWidth(FView) then
  begin
    Widest := Scale(MaxWidth);
  end;
  Result := EnsureRange(Widest + Scale(26), Scale(200), Scale(MaxWidth));
end;

procedure TAtlasHoverTipView.ShowContent(const AView: TAtlasHoverView; const AWord: TRect);
var
  mWidth, mHeight: Integer;
  Spoken: string;
  Area, Bounds: TRect;
begin
  FView := AView;
  FDeclaration := TAtlasStyledText.Create(AView.Data.Declaration);
  FHot := -1;
  FMembers.Scroll := 0;
  mWidth := PreferredWidth;
  PrepareDoc(mWidth);
  Area := WorkAreaAt(AWord.TopLeft);
  // Höchstens so hoch wie der größere Platz unter bzw. über dem Wort; darüber scrollt die Doku.
  mHeight := FitHeight(mWidth, Max(Area.Bottom - AWord.Bottom, AWord.Top - Area.Top) - Scale(12));
  Bounds := TRect.Create(Point(AWord.Left, AWord.Bottom + Scale(4)), mWidth, mHeight);
  FAbove := Bounds.Bottom > Area.Bottom;
  if FAbove then
  begin
    Bounds.SetLocation(Bounds.Left, AWord.Top - mHeight - Scale(4));
  end;
  if Bounds.Right > Area.Right then
  begin
    Bounds.SetLocation(Max(Area.Left, Area.Right - mWidth), Bounds.Top);
  end;
  ShowAt(Bounds);
  // Sprachausgabe (#447): Deklaration und Anfang der Doku.
  SetAccessible(UiaToolTipControlType, TAtlasStrings.Text(TAtlasTextId.AccessHover));
  Spoken := Trim(AView.Data.Declaration + '. ' + Copy(AView.Data.Documentation, 1, 300));
  // Wert im Debugger (#891) zuerst.
  if AView.DebugValue.PlainText <> '' then
  begin
    Spoken := AView.DebugValue.PlainText + '. ' + Spoken;
  end;
  Announce(Spoken);
end;

procedure TAtlasHoverTipView.UpdateContent(const AView: TAtlasHoverView);
var
  mWidth, mHeight: Integer;
  Bounds, Area: TRect;
begin
  if not IsShown then
  begin
    Exit;
  end;
  FView := AView;
  FDeclaration := TAtlasStyledText.Create(AView.Data.Declaration);
  FHot := -1;
  FMembers.Scroll := 0;
  mWidth := Max(BoundsRect.Width, PreferredWidth);
  PrepareDoc(mWidth);
  Area := WorkAreaAt(BoundsRect.TopLeft);
  mHeight := Max(BoundsRect.Height, FitHeight(mWidth, Area.Bottom - BoundsRect.Top - Scale(4)));
  mHeight := Min(mHeight, Max(Area.Bottom - BoundsRect.Top, Scale(80)));
  Bounds := TRect.Create(BoundsRect.TopLeft, mWidth, mHeight);
  ShowAt(Bounds);
  Invalidate;
end;

procedure TAtlasHoverTip.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hot, DocHot: Integer;
begin
  inherited;
  // Markieren in der Doku (#654).
  if FDoc.Selecting and (ssLeft in Shift) then
  begin
    FDoc.ExtendSelection(Canvas, X - FLayout.DocLeft, Y - FLayout.DocTop);
    Invalidate;
    Exit;
  end;
  Hot := FLayout.HitAt(Point(X, Y));
  DocHot := DocLinkAt(X, Y);
  if (Hot >= 0) or (DocHot >= 0) then
  begin
    Cursor := crHandPoint;
  end
  else if InDoc(X, Y) then
  begin
    Cursor := crIBeam;
  end
  else
  begin
    Cursor := crDefault;
  end;
  if (Hot <> FHot) or (DocHot <> FDoc.HotLink) then
  begin
    FHot := Hot;
    FDoc.HotLink := DocHot;
    Invalidate;
  end;
end;

procedure TAtlasHoverTip.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if FDoc.Selecting then
  begin
    FDoc.EndSelection;
    Invalidate;
  end;
end;

procedure TAtlasHoverTip.Wheel(ASteps: Integer; const AClientPos: TPoint);
begin
  if FLayout.Members.Scrollable and FLayout.Members.View.Contains(AClientPos) then
  begin
    ScrollMembers(ASteps);
  end
  else if not ScrollDoc(ASteps) and FLayout.Members.Scrollable then
  begin
    ScrollMembers(ASteps);
  end;
end;

function TAtlasHoverTip.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  mPos: TPoint;
begin
  // Nur Doku und Mitglieder scrollen; Deklaration und Aktionsleiste bleiben stehen.
  Result := True;
  mPos := ScreenToClient(MousePos);
  if WheelDelta > 0 then
  begin
    Wheel(-Max(1, WheelDelta div WHEEL_DELTA), mPos);
  end
  else if WheelDelta < 0 then
  begin
    Wheel(Max(1, -WheelDelta div WHEEL_DELTA), mPos);
  end;
end;

procedure TAtlasHoverTip.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if (FHot >= 0) or (FDoc.HotLink >= 0) then
  begin
    FHot := -1;
    FDoc.HotLink := -1;
    Invalidate;
  end;
end;

procedure TAtlasHoverTip.FireHit(AHit: Integer; Shift: TShiftState);
var
  mHit: TAtlasHoverHit;
begin
  mHit := FLayout.Hits[AHit];
  case mHit.Kind of
    TAtlasHoverHitKind.Link:
      if Assigned(FOnLink) then
      begin
        FOnLink(Self, FView.Data.Links[mHit.Index].Target, ssCtrl in Shift);
      end;
    TAtlasHoverHitKind.Ancestor:
      if Assigned(FOnLink) then
      begin
        FOnLink(Self, FView.Data.Ancestors[mHit.Index], ssCtrl in Shift);
      end;
    TAtlasHoverHitKind.Path:
      if Assigned(FOnPath) then
      begin
        FOnPath(Self, mHit.Index);
      end;
    TAtlasHoverHitKind.Back:
      if Assigned(FOnBack) then
      begin
        FOnBack(Self);
      end;
    TAtlasHoverHitKind.Action:
      if Assigned(FOnAction) then
      begin
        FOnAction(Self, TAtlasHoverAction(mHit.Index));
      end;
    TAtlasHoverHitKind.ProblemAction:
      FireProblemAction(AHit);
    // Schalter und Abschnitte der published-Mitglieder (#110).
    TAtlasHoverHitKind.Published:
      TogglePublished(TAtlasHoverPublishedToggle(mHit.Index));
    TAtlasHoverHitKind.DebugFix:
      if Assigned(FOnDebugFix) then
      begin
        FOnDebugFix(Self, mHit.Index);
      end;
  end;
end;

procedure TAtlasHoverTip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mIndex := FLayout.HitAt(Point(X, Y));
  if mIndex < 0 then
  begin
    DocMouseDown(Shift, X, Y);
  end
  else
  begin
    FireHit(mIndex, Shift);
  end;
end;

procedure TAtlasHoverTipView.SetProblemActions(AValue: Boolean);
begin
  if FProblemActions = AValue then
  begin
    Exit;
  end;
  FProblemActions := AValue;
  FHot := -1;
  FLayoutKey := '';
  Invalidate;
end;

procedure TAtlasHoverTipView.SetHideCompilerCode(AValue: Boolean);
begin
  if FHideCompilerCode = AValue then
  begin
    Exit;
  end;
  FHideCompilerCode := AValue;
  FLayoutKey := '';
  Invalidate;
end;

function TAtlasHoverTip.FireProblemAction(AHit: Integer): Boolean;
var
  ProblemIndex, Item: Integer;
  ProblemAction: TAtlasHoverProblemAction;
begin
  Result := (AHit >= 0) and (AHit <= High(FLayout.Hits)) and
    (FLayout.Hits[AHit].Kind = TAtlasHoverHitKind.ProblemAction) and Assigned(FOnProblemAction);
  if not Result then
  begin
    Exit;
  end;
  TAtlasHoverLayout.DecodeProblemAction(FLayout.Hits[AHit].Index, ProblemIndex, ProblemAction, Item);
  FOnProblemAction(Self, ProblemIndex, ProblemAction, Item);
end;

function TAtlasHoverTip.HasProblemActions: Boolean;
begin
  Result := FLayout.NextProblemHit(-1, True) >= 0;
end;

function TAtlasHoverTip.HasFix: Boolean;
begin
  Result := FLayout.FixProblem >= 0;
end;

function TAtlasHoverTip.ProblemActionMarked: Boolean;
begin
  Result := (FHot >= 0) and (FHot <= High(FLayout.Hits)) and
    (FLayout.Hits[FHot].Kind = TAtlasHoverHitKind.ProblemAction);
end;

function TAtlasHoverTip.StepProblemAction(AForward: Boolean): Boolean;
var
  Next: Integer;
begin
  Next := FLayout.NextProblemHit(FHot, AForward);
  Result := Next >= 0;
  if Result and (Next <> FHot) then
  begin
    FHot := Next;
    Invalidate;
  end;
end;

function TAtlasHoverTip.ActivateProblemAction: Boolean;
begin
  Result := ProblemActionMarked and FireProblemAction(FHot);
end;

function TAtlasHoverTip.ApplyFix: Boolean;
begin
  Result := HasFix and Assigned(FOnProblemAction);
  if Result then
  begin
    FOnProblemAction(Self, FLayout.FixProblem, TAtlasHoverProblemAction.Fix, 0);
  end;
end;

procedure TAtlasHoverTipView.Paint;
var
  mIndex: Integer;
  mView: TRect;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  // Nur neu setzen, wenn sich Breite, Doku-Höhe, Markierung, Schrift, Farben oder Rollbereich geändert haben.
  if LayoutKey(ClientWidth) <> FLayoutKey then
  begin
    BuildLayout(ClientWidth);
  end;
  // Letzte Randfläche am unteren Fensterrand.
  FLayout.Anchor(ClientHeight);
  mView := FLayout.Members.View;
  for mIndex := 0 to High(FLayout.Items) do
  begin
    // Rollbereich der Mitglieder (#1841) über die Clip-Region beschneiden; die gewählten Objekte bleiben.
    if mIndex = FLayout.Members.ClipFrom then
    begin
      IntersectClipRect(Canvas.Handle, mView.Left, mView.Top, mView.Right, mView.Bottom);
    end
    else if (mIndex = FLayout.Members.ClipTill) and (FLayout.Members.ClipFrom >= 0) then
    begin
      SelectClipRgn(Canvas.Handle, 0);
    end;
    PaintItem(FLayout.Items[mIndex]);
  end;
  SelectClipRgn(Canvas.Handle, 0);
  Canvas.Brush.Style := bsSolid;
  PaintBorder;
end;

end.
