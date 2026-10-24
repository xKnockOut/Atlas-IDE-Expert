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
  Atlas.Core.Hover.Layout,
  Atlas.UI.Documentation.View,
  Atlas.UI.Popup.Styled,
  Atlas.UI.Popup.Window;

type

  TAtlasHoverRefEvent = procedure(Sender: TObject; const ARef: TAtlasHoverTypeRef; AControl: Boolean) of object;
  TAtlasHoverIndexEvent = procedure(Sender: TObject; AIndex: Integer) of object;
  TAtlasHoverActionEvent = procedure(Sender: TObject; AAction: TAtlasHoverAction) of object;
  TAtlasHoverUrlEvent = procedure(Sender: TObject; const AUrl: string) of object;
  /// <summary>Klick auf eine Aktion unter einem Problem (#621); AProblem ist der Index in View.Problems.</summary>
  TAtlasHoverProblemActionEvent = procedure(Sender: TObject; AProblem: Integer;
    AAction: TAtlasHoverProblemAction) of object;

  TAtlasHoverTip = class(TAtlasPopupWindow)
  public const
    MaxWidth = 460;
  private
    FView: TAtlasHoverView;
    /// <summary>Satz des Inhalts (P-09); FLayoutKey: Breite, Doku, Schrift, Farben, für die er gilt.</summary>
    FLayout: TAtlasHoverLayout;
    FLayoutKey: string;
    FDeclaration: TAtlasStyledText;
    FHot: Integer;
    FOnLink: TAtlasHoverRefEvent;
    FOnPath: TAtlasHoverIndexEvent;
    FOnBack: TNotifyEvent;
    FOnAction: TAtlasHoverActionEvent;
    FOnUrl: TAtlasHoverUrlEvent;
    FOnProblemAction: TAtlasHoverProblemActionEvent;
    FOnDebugFix: TAtlasHoverIndexEvent;
    FProblemActions: Boolean;
    FHideCompilerCode: Boolean;
    FDoc: TAtlasDocView;
    /// <summary>Linke obere Ecke der Doku beim letzten Zeichnen bzw. Messen.</summary>
    FDocLeft: Integer;
    FDocTop: Integer;
    /// <summary>Über dem Wort gezeigt: Beim Auf- und Zuklappen bleibt der untere Rand.</summary>
    FAbove: Boolean;
    /// <summary>Setzt die Doku für die Fensterbreite AWidth (volle Höhe).</summary>
    procedure PrepareDoc(AWidth: Integer);
    /// <summary>Höhe für AWidth mit höchstens AAvailable Pixeln: begrenzt die Doku (scrollt dann).</summary>
    function FitHeight(AWidth, AAvailable: Integer): Integer;
    function InDoc(AX, AY: Integer): Boolean;
    function DocLinkAt(AX, AY: Integer): Integer;
    /// <summary>Klick in die Doku: Verweis, Link oder Beginn einer Markierung.</summary>
    procedure DocMouseDown(Shift: TShiftState; X, Y: Integer);
    /// <summary>„Mehr/Weniger anzeigen“ (#770): klappt um, merkt den Zustand und passt die Höhe an.</summary>
    procedure ToggleDoc;
    /// <summary>Schalter der published-Mitglieder (#110): schaltet um und passt die Höhe an.</summary>
    procedure TogglePublished(AToggle: TAtlasHoverPublishedToggle);
    /// <summary>Höhe neu nach dem Inhalt, Breite bleibt; wächst nach unten, über dem Wort nach oben.</summary>
    procedure Refit;
    procedure SetProblemActions(AValue: Boolean);
    procedure SetHideCompilerCode(AValue: Boolean);
    /// <summary>Löst die Aktion der Klickfläche AHit (Index in FLayout.Hits) aus, wenn sie zu einem Problem gehört.
    /// </summary>
    function FireProblemAction(AHit: Integer): Boolean;
    function LayoutKey(AWidth: Integer): string;
    function Texts: TAtlasHoverTexts;
    /// <summary>Setzt FLayout für die Fensterbreite AWidth mit der jetzigen Doku-Höhe.</summary>
    procedure BuildLayout(AWidth: Integer);
    /// <summary>Wählt die Schrift AFace in die Zeichenfläche.</summary>
    procedure ApplyFace(const AFace: TAtlasHoverFace; ABadgeHeight: Integer);
    procedure PaintItem(const AItem: TAtlasHoverItem);
    function HitAt(AX, AY: Integer): Integer;
    function PreferredWidth: Integer;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Markierter Text der Doku (#654); '' ohne Markierung.</summary>
    function SelectedText: string;
    function HasSelection: Boolean;
    /// <summary>Scrollt die Doku um ASteps Rasterstufen des Mausrads (negativ nach oben).</summary>
    function ScrollDoc(ASteps: Integer): Boolean;
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
    /// <summary>Zeigt AView unter AWord (Bildschirmrechteck des Bezeichners).</summary>
    procedure ShowContent(const AView: TAtlasHoverView; const AWord: TRect);
    /// <summary>Tauscht den Inhalt; Position bleibt, Breite und Höhe wachsen höchstens.</summary>
    procedure UpdateContent(const AView: TAtlasHoverView);
    /// <summary>Text der Art für die Kopfzeile (Klasse, Methode …); '' wenn unbekannt.</summary>
    class function KindCaption(const AKind: string): string; static;
    property View: TAtlasHoverView read FView;
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
    /// <summary>Aktionszeile unter Regelbefunden (hover.problemActions, #909).</summary>
    property ProblemActions: Boolean read FProblemActions write SetProblemActions;
    /// <summary>problems.showCompilerCode aus (#1024).</summary>
    property HideCompilerCode: Boolean read FHideCompilerCode write SetHideCompilerCode;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  System.StrUtils,
  Atlas.Core.Style.Palette,
  Atlas.Core.Documentation.Layout,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Draw,
  Atlas.UI.Popup.Accessibility;

type
  /// <summary>Messen über die Zeichenfläche des Tooltips für TAtlasHoverLayout.</summary>
  TTipMeasure = class(TInterfacedObject, IAtlasHoverMeasure)
  private
    FTip: TAtlasHoverTip;
  public
    constructor Create(ATip: TAtlasHoverTip);
    function TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
    function TextHeight(const AFace: TAtlasHoverFace): Integer;
    function BlockHeight(const AText: string; AWidth: Integer): Integer;
    function DeclarationWidth(AFrom, ATill: Integer): Integer;
    function DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
  end;

{ TTipMeasure }

constructor TTipMeasure.Create(ATip: TAtlasHoverTip);
begin
  inherited Create;
  FTip := ATip;
end;

function TTipMeasure.TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
begin
  FTip.ApplyFace(AFace, 0);
  Result := FTip.Canvas.TextWidth(AText);
end;

function TTipMeasure.TextHeight(const AFace: TAtlasHoverFace): Integer;
begin
  FTip.ApplyFace(AFace, 0);
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

{ TAtlasHoverTip }

constructor TAtlasHoverTip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Hover;
  FHot := -1;
  FDoc := TAtlasDocView.Create;
end;

destructor TAtlasHoverTip.Destroy;
begin
  FDoc.Free;
  inherited Destroy;
end;

procedure TAtlasHoverTip.PrepareDoc(AWidth: Integer);
var
  Doc: TAtlasDoc;
begin
  // Fremde Server liefern nur Klartext: als Beschreibung setzen, ohne Kürzen.
  Doc := FView.Data.Doc;
  if Doc.IsEmpty then
    Doc := TAtlasDoc.FromText(FView.Data.Documentation);
  if Doc.IsEmpty then
  begin
    FDoc.Clear;
    Exit;
  end;
  HandleNeeded;
  FDoc.Build(Canvas, Doc, AWidth - Scale(22), Font, UIFont, PPI, TAtlasStrings.DocLabels,
    TAtlasDocSignature.Parse(FView.Data.Declaration),
    TAtlasDocExpandState.Initial(FView.Display.Expand, TAtlasDocSurface.Tooltip));
end;

procedure TAtlasHoverTip.ToggleDoc;
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

procedure TAtlasHoverTip.Refit;
var
  Area, Bounds: TRect;
  NewHeight: Integer;
begin
  Area := WorkAreaAt(BoundsRect.TopLeft);
  NewHeight := FitHeight(Width, Area.Height - Scale(8));
  Bounds := TRect.Create(BoundsRect.TopLeft, Width, NewHeight);
  // Wächst nach unten; über dem Wort bzw. ohne Platz darunter nach oben.
  if FAbove or (Bounds.Bottom > Area.Bottom) then
    Bounds.SetLocation(Bounds.Left, Max(Area.Top, BoundsRect.Bottom - NewHeight));
  ShowAt(Bounds);
  Invalidate;
end;

function TAtlasHoverTip.FitHeight(AWidth, AAvailable: Integer): Integer;
var
  Natural: Integer;
begin
  FDoc.FitHeight(FView.Display.MaxLines, 0);
  BuildLayout(AWidth);
  Natural := FLayout.Height;
  if (Natural > AAvailable) and not FDoc.IsEmpty then
  begin
    FDoc.FitHeight(FView.Display.MaxLines, FDoc.Height - (Natural - AAvailable));
    BuildLayout(AWidth);
    Natural := FLayout.Height;
  end;
  Result := Natural;
end;

function TAtlasHoverTip.InDoc(AX, AY: Integer): Boolean;
begin
  Result := not FDoc.IsEmpty and (AX >= FDocLeft - Scale(4)) and (AX < FDocLeft + FDoc.Width + Scale(8)) and
    (AY >= FDocTop) and (AY < FDocTop + FDoc.Height);
end;

function TAtlasHoverTip.DocLinkAt(AX, AY: Integer): Integer;
begin
  Result := -1;
  if InDoc(AX, AY) then
    Result := FDoc.LinkAt(AX - FDocLeft, AY - FDocTop);
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
      ToggleDoc
    else if Link.Kind = TAtlasDocLinkKind.Url then
    begin
      if Assigned(FOnUrl) then
        FOnUrl(Self, Link.Url);
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
    FDoc.StartSelection(Canvas, X - FDocLeft, Y - FDocTop)
  else
    FDoc.ClearSelection;
  Invalidate;
end;

function TAtlasHoverTip.SelectedText: string;
begin
  Result := FDoc.SelectedText;
end;

function TAtlasHoverTip.HasSelection: Boolean;
begin
  Result := FDoc.HasSelection;
end;

function TAtlasHoverTip.ScrollDoc(ASteps: Integer): Boolean;
begin
  Result := FDoc.ScrollBy(ASteps * FDoc.WheelStep);
  if Result then
    Invalidate;
end;

class function TAtlasHoverTip.KindCaption(const AKind: string): string;
const
  Kinds: array[0..15] of string = ('class', 'classref', 'object', 'record', 'interface', 'helper', 'enum', 'type',
    'method', 'constructor', 'routine', 'property', 'field', 'variable', 'constant', 'enumMember');
  Ids: array[0..15] of TAtlasTextId = (TAtlasTextId.KindClass, TAtlasTextId.KindClassRef, TAtlasTextId.KindObject,
    TAtlasTextId.KindRecord, TAtlasTextId.KindInterface, TAtlasTextId.KindHelper, TAtlasTextId.KindEnum,
    TAtlasTextId.KindType, TAtlasTextId.KindMethod, TAtlasTextId.KindConstructor, TAtlasTextId.KindRoutine,
    TAtlasTextId.KindProperty, TAtlasTextId.KindField, TAtlasTextId.KindVariable, TAtlasTextId.KindConstant,
    TAtlasTextId.KindEnumMember);
var
  Index: Integer;
begin
  Index := IndexStr(AKind, Kinds);
  if Index < 0 then
    Result := ''
  else
    Result := TAtlasStrings.Text(Ids[Index]);
end;

function TAtlasHoverTip.Texts: TAtlasHoverTexts;
var
  Index: Integer;
begin
  Result := Default(TAtlasHoverTexts);
  Result.KindCaption := KindCaption(FView.Data.Kind);
  Result.Pinned := TAtlasStrings.Text(TAtlasTextId.HoverPinned);
  Result.Inheritance := TAtlasStrings.Text(TAtlasTextId.HoverInheritance);
  Result.TargetType := TAtlasStrings.Text(TAtlasTextId.HoverTargetType);
  Result.Navigate := TAtlasStrings.Text(TAtlasTextId.HoverGoTo);
  Result.Usages := TAtlasStrings.Text(TAtlasTextId.HoverUsages);
  Result.UsagesCount := TAtlasStrings.Text(TAtlasTextId.HoverUsagesCount);
  Result.Copy := TAtlasStrings.Text(TAtlasTextId.HoverCopy);
  Result.CopySelection := TAtlasStrings.Text(TAtlasTextId.HoverCopySelection);
  Result.Help := TAtlasStrings.Text(TAtlasTextId.HoverHelp);
  Result.KeyUsages := TAtlasStrings.Text(TAtlasTextId.HoverKeyUsages);
  Result.KeyCopy := TAtlasStrings.Text(TAtlasTextId.HoverKeyCopy);
  Result.SourceAtlas := TAtlasStrings.Text(TAtlasTextId.ProblemsSourceAtlas);
  Result.Confirmed := TAtlasStrings.Text(TAtlasTextId.ProblemsCompilerConfirmed);
  Result.ConfirmedCode := TAtlasStrings.Text(TAtlasTextId.ProblemsCompilerConfirmedCode);
  Result.SourceCompiler := TAtlasStrings.Text(TAtlasTextId.ProblemsSourceCompiler);
  Result.SourceInactive := TAtlasStrings.Text(TAtlasTextId.ProblemsSourceInactive);
  Result.SourceUses := TAtlasStrings.Text(TAtlasTextId.ProblemsSourceUses);
  Result.UsesRemove := TAtlasStrings.Text(TAtlasTextId.UsesRemove);
  Result.UsesRemoveAll := TAtlasStrings.Text(TAtlasTextId.UsesRemoveAll);
  Result.UsesMove := TAtlasStrings.Text(TAtlasTextId.UsesMove);
  Result.KindError := TAtlasStrings.Text(TAtlasTextId.ProblemsKindError);
  Result.KindWarning := TAtlasStrings.Text(TAtlasTextId.ProblemsKindWarning);
  Result.KindInfo := TAtlasStrings.Text(TAtlasTextId.ProblemsKindInfo);
  Result.Suppress := TAtlasStrings.Text(TAtlasTextId.ProblemsMenuSuppress);
  Result.Configure := TAtlasStrings.Text(TAtlasTextId.ProblemsMenuConfigure);
  Result.Stale := TAtlasStrings.Text(TAtlasTextId.ProblemsStale);
  Result.DebugPending := TAtlasStrings.Text(TAtlasTextId.HoverDebugPending);
  Result.DebugExplaining := TAtlasStrings.Text(TAtlasTextId.HoverDebugExplaining);
  Result.DebugChecked := TAtlasStrings.Text(TAtlasTextId.HoverDebugChecked);
  Result.PublishedSummary := TAtlasStrings.Text(TAtlasTextId.PublishedSummary);
  Result.PublishedInherited := TAtlasStrings.Text(TAtlasTextId.PublishedInherited);
  Result.PublishedOnlyDefaults := TAtlasStrings.Text(TAtlasTextId.PublishedOnlyDefaults);
  Result.PublishedProperties := TAtlasStrings.Text(TAtlasTextId.PublishedProperties);
  Result.PublishedEvents := TAtlasStrings.Text(TAtlasTextId.PublishedEvents);
  Result.PublishedName := TAtlasStrings.Text(TAtlasTextId.PublishedName);
  Result.PublishedType := TAtlasStrings.Text(TAtlasTextId.PublishedType);
  Result.PublishedDefault := TAtlasStrings.Text(TAtlasTextId.PublishedDefault);
  Result.PublishedDeclared := TAtlasStrings.Text(TAtlasTextId.PublishedDeclared);
  Result.PublishedImplicit := TAtlasStrings.Text(TAtlasTextId.PublishedImplicit);
  Result.PublishedMoreProperties := TAtlasStrings.Text(TAtlasTextId.PublishedMoreProperties);
  Result.PublishedMoreEvents := TAtlasStrings.Text(TAtlasTextId.PublishedMoreEvents);
  Result.PublishedEventsNote := TAtlasStrings.Text(TAtlasTextId.PublishedEventsNote);
  Result.PublishedArrayProperty := TAtlasStrings.Text(TAtlasTextId.PublishedArrayProperty);
  Result.PublishedDefaultProperty := TAtlasStrings.Text(TAtlasTextId.PublishedDefaultProperty);
  Result.PublishedDefaultPropertyNote := TAtlasStrings.Text(TAtlasTextId.PublishedDefaultPropertyNote);
  Result.PublishedCopyList := TAtlasStrings.Text(TAtlasTextId.PublishedCopyList);
  Result.PublishedVclNote := TAtlasStrings.Text(TAtlasTextId.PublishedVclNote);
  Result.Confidences := nil;
  SetLength(Result.Confidences, Length(FView.Problems));
  // Hohe Konfidenz ist der Normalfall und bekommt keine eigene Zeile (#909).
  for Index := 0 to High(FView.Problems) do
    if not SameText(FView.Problems[Index].Confidence, 'high') then
      Result.Confidences[Index] := TAtlasStrings.Confidence(FView.Problems[Index].Confidence);
end;

function TAtlasHoverTip.LayoutKey(AWidth: Integer): string;
begin
  Result := Format('%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d', [AWidth, FDoc.Height, Ord(FDoc.IsEmpty),
    Ord(FDoc.HasSelection), Ord(FProblemActions), Ord(FHideCompilerCode), PPI, Font.Height, UIFont.Height, Integer(Colors.Surface), Integer(Colors.Text), Integer(Colors.Accent)]);
end;

procedure TAtlasHoverTip.BuildLayout(AWidth: Integer);
var
  Input: TAtlasHoverInput;
begin
  HandleNeeded;
  Input := Default(TAtlasHoverInput);
  Input.View := FView;
  Input.Width := AWidth;
  Input.PPI := PPI;
  Input.Colors := Colors;
  Input.Texts := Texts;
  Input.HasDoc := not FDoc.IsEmpty;
  Input.DocHeight := FDoc.Height;
  Input.HasSelection := FDoc.HasSelection;
  Input.ProblemActions := FProblemActions;
  Input.HideCompilerCode := FHideCompilerCode;
  FLayout := TAtlasHoverLayout.Build(Input, TTipMeasure.Create(Self));
  FLayoutKey := LayoutKey(AWidth);
  FDocLeft := FLayout.DocLeft;
  FDocTop := FLayout.DocTop;
end;

procedure TAtlasHoverTip.ApplyFace(const AFace: TAtlasHoverFace; ABadgeHeight: Integer);
begin
  // Kleinere Schrift für Beschriftungen (UI) bzw. Abschnittstitel (Editorschrift).
  case AFace.Font of
    TAtlasHoverFont.Mono:
      Canvas.Font := Font;
    TAtlasHoverFont.SmallUi:
      begin
        Canvas.Font := UIFont;
        Canvas.Font.Height := Round(UIFont.Height * 0.88);
      end;
    TAtlasHoverFont.SmallMono:
      begin
        Canvas.Font := Font;
        Canvas.Font.Height := Round(Font.Height * 0.8);
      end;
    TAtlasHoverFont.Badge:
      begin
        Canvas.Font := Font;
        Canvas.Font.Height := -Round(ABadgeHeight * 0.62);
      end;
  else
    Canvas.Font := UIFont;
  end;
  Canvas.Font.Style := [];
  if AFace.Bold then
    Canvas.Font.Style := [fsBold];
  if AFace.Underline then
    Canvas.Font.Style := Canvas.Font.Style + [fsUnderline];
end;

procedure TAtlasHoverTip.PaintItem(const AItem: TAtlasHoverItem);
var
  Hot: Boolean;
  Color: TAtlasColor;
  Face: TAtlasHoverFace;
  Area: TRect;
  X: Integer;
begin
  Hot := (AItem.HotIndex >= 0) and FLayout.IsHot(FHot, AItem.HotKind, AItem.HotIndex);
  Color := AItem.Color;
  if Hot then
    Color := AItem.HotColor;
  Face := AItem.Face;
  if Hot and AItem.HotUnderline then
    Face.Underline := True;
  case AItem.Kind of
    TAtlasHoverItemKind.Fill:
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := ToColor(Color);
        Canvas.FillRect(AItem.Rect);
      end;
    TAtlasHoverItemKind.Line:
      begin
        Canvas.Pen.Color := ToColor(Color);
        if Hot then
          Canvas.Pen.Width := AItem.HotPenWidth
        else
          Canvas.Pen.Width := AItem.PenWidth;
        Canvas.MoveTo(AItem.Rect.Left, AItem.Rect.Top);
        Canvas.LineTo(AItem.Rect.Right, AItem.Rect.Top);
        Canvas.Pen.Width := 1;
      end;
    TAtlasHoverItemKind.Text:
      begin
        ApplyFace(Face, 0);
        Canvas.Font.Color := ToColor(Color);
        Canvas.Brush.Style := bsClear;
        Canvas.TextOut(AItem.Rect.Left, AItem.Rect.Top, AItem.Text);
      end;
    TAtlasHoverItemKind.CenterText:
      begin
        ApplyFace(Face, AItem.Rect.Height);
        Canvas.Font.Color := ToColor(Color);
        Canvas.Brush.Style := bsClear;
        Area := AItem.Rect;
        DrawText(Canvas.Handle, PChar(AItem.Text), -1, Area, DT_CENTER or DT_VCENTER or DT_SINGLELINE or
          DT_NOPREFIX);
      end;
    TAtlasHoverItemKind.Frame:
      FrameRounded(AItem.Rect, Color, AItem.Radius, ToColor(AItem.Back));
    TAtlasHoverItemKind.RoundFill:
      FillRounded(AItem.Rect, Color, AItem.Radius);
    TAtlasHoverItemKind.Block:
      begin
        Canvas.Font := UIFont;
        Canvas.Font.Color := ToColor(Color);
        Canvas.Brush.Style := bsClear;
        Area := AItem.Rect;
        DrawText(Canvas.Handle, PChar(AItem.Text), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_END_ELLIPSIS);
      end;
    TAtlasHoverItemKind.Styled:
      begin
        Canvas.Font := Font;
        X := AItem.Rect.Left;
        FDeclaration.Draw(Canvas, Colors, AItem.From, AItem.Till, X, AItem.Rect, False, Scale(3));
      end;
    TAtlasHoverItemKind.Doc:
      FDoc.Paint(Canvas, Colors, AItem.Rect.Left, AItem.Rect.Top);
  end;
end;

function TAtlasHoverTip.PreferredWidth: Integer;
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
    Widest := Max(Widest, Canvas.TextWidth(FView.DebugValue.Expression) + Scale(9));
  Canvas.Font := UIFont;
  if FView.DebugValue.Visible then
    Widest := Max(Widest, Canvas.TextWidth(FView.DebugValue.Text) + Scale(9));
  Widest := Max(Widest, Canvas.TextWidth(FView.Data.UnitName));
  for Problem in FView.Problems do
    Widest := Max(Widest, Canvas.TextWidth(Problem.Caption) + Scale(9));
  if (FView.Data.Documentation <> '') or not FView.Data.Doc.IsEmpty or (Length(FView.Data.Ancestors) > 0) or
    FView.Data.Location.HasLocation or FView.Pinned or (Length(FView.Data.Members) > 0) then
    Widest := Scale(MaxWidth);
  Result := EnsureRange(Widest + Scale(26), Scale(200), Scale(MaxWidth));
end;

procedure TAtlasHoverTip.ShowContent(const AView: TAtlasHoverView; const AWord: TRect);
var
  Width, Height: Integer;
  Spoken: string;
  Area, Bounds: TRect;
begin
  FView := AView;
  FDeclaration := TAtlasStyledText.Create(AView.Data.Declaration);
  FHot := -1;
  Width := PreferredWidth;
  PrepareDoc(Width);
  Area := WorkAreaAt(AWord.TopLeft);
  // Höchstens so hoch wie der größere Platz unter bzw. über dem Wort; darüber scrollt die Doku.
  Height := FitHeight(Width, Max(Area.Bottom - AWord.Bottom, AWord.Top - Area.Top) - Scale(12));
  Bounds := TRect.Create(Point(AWord.Left, AWord.Bottom + Scale(4)), Width, Height);
  FAbove := Bounds.Bottom > Area.Bottom;
  if FAbove then
    Bounds.SetLocation(Bounds.Left, AWord.Top - Height - Scale(4));
  if Bounds.Right > Area.Right then
    Bounds.SetLocation(Max(Area.Left, Area.Right - Width), Bounds.Top);
  ShowAt(Bounds);
  // Sprachausgabe (#447): Deklaration und Anfang der Doku.
  SetAccessible(UiaToolTipControlType, TAtlasStrings.Text(TAtlasTextId.AccessHover));
  Spoken := Trim(AView.Data.Declaration + '. ' + Copy(AView.Data.Documentation, 1, 300));
  // Wert im Debugger (#891) zuerst.
  if AView.DebugValue.PlainText <> '' then
    Spoken := AView.DebugValue.PlainText + '. ' + Spoken;
  Announce(Spoken);
end;

procedure TAtlasHoverTip.UpdateContent(const AView: TAtlasHoverView);
var
  Width, Height: Integer;
  Bounds, Area: TRect;
begin
  if not IsShown then
    Exit;
  FView := AView;
  FDeclaration := TAtlasStyledText.Create(AView.Data.Declaration);
  FHot := -1;
  Width := Max(BoundsRect.Width, PreferredWidth);
  PrepareDoc(Width);
  Area := WorkAreaAt(BoundsRect.TopLeft);
  Height := Max(BoundsRect.Height, FitHeight(Width, Area.Bottom - BoundsRect.Top - Scale(4)));
  Height := Min(Height, Max(Area.Bottom - BoundsRect.Top, Scale(80)));
  Bounds := TRect.Create(BoundsRect.TopLeft, Width, Height);
  ShowAt(Bounds);
  Invalidate;
end;

function TAtlasHoverTip.HitAt(AX, AY: Integer): Integer;
begin
  Result := FLayout.HitAt(Point(AX, AY));
end;

procedure TAtlasHoverTip.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hot, DocHot: Integer;
begin
  inherited;
  // Markieren in der Doku (#654).
  if FDoc.Selecting and (ssLeft in Shift) then
  begin
    FDoc.ExtendSelection(Canvas, X - FDocLeft, Y - FDocTop);
    Invalidate;
    Exit;
  end;
  Hot := HitAt(X, Y);
  DocHot := DocLinkAt(X, Y);
  if (Hot >= 0) or (DocHot >= 0) then
    Cursor := crHandPoint
  else if InDoc(X, Y) then
    Cursor := crIBeam
  else
    Cursor := crDefault;
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

function TAtlasHoverTip.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  // Nur die Doku scrollt; Deklaration und Aktionsleiste bleiben stehen.
  Result := True;
  if WheelDelta > 0 then
    ScrollDoc(-Max(1, WheelDelta div WHEEL_DELTA))
  else if WheelDelta < 0 then
    ScrollDoc(Max(1, -WheelDelta div WHEEL_DELTA));
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

procedure TAtlasHoverTip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
  Hit: TAtlasHoverHit;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  Index := HitAt(X, Y);
  if Index < 0 then
  begin
    DocMouseDown(Shift, X, Y);
    Exit;
  end;
  Hit := FLayout.Hits[Index];
  case Hit.Kind of
    TAtlasHoverHitKind.Link:
      if Assigned(FOnLink) then
        FOnLink(Self, FView.Data.Links[Hit.Index].Target, ssCtrl in Shift);
    TAtlasHoverHitKind.Ancestor:
      if Assigned(FOnLink) then
        FOnLink(Self, FView.Data.Ancestors[Hit.Index], ssCtrl in Shift);
    TAtlasHoverHitKind.Path:
      if Assigned(FOnPath) then
        FOnPath(Self, Hit.Index);
    TAtlasHoverHitKind.Back:
      if Assigned(FOnBack) then
        FOnBack(Self);
    TAtlasHoverHitKind.Action:
      if Assigned(FOnAction) then
        FOnAction(Self, TAtlasHoverAction(Hit.Index));
    TAtlasHoverHitKind.ProblemAction:
      FireProblemAction(Index);
    // Schalter und Abschnitte der published-Mitglieder (#110).
    TAtlasHoverHitKind.Published:
      TogglePublished(TAtlasHoverPublishedToggle(Hit.Index));
    TAtlasHoverHitKind.DebugFix:
      if Assigned(FOnDebugFix) then
        FOnDebugFix(Self, Hit.Index);
  end;
end;

procedure TAtlasHoverTip.SetProblemActions(AValue: Boolean);
begin
  if FProblemActions = AValue then
    Exit;
  FProblemActions := AValue;
  FHot := -1;
  FLayoutKey := '';
  Invalidate;
end;

procedure TAtlasHoverTip.SetHideCompilerCode(AValue: Boolean);
begin
  if FHideCompilerCode = AValue then
    Exit;
  FHideCompilerCode := AValue;
  FLayoutKey := '';
  Invalidate;
end;

function TAtlasHoverTip.FireProblemAction(AHit: Integer): Boolean;
var
  ProblemIndex: Integer;
  ProblemAction: TAtlasHoverProblemAction;
begin
  Result := (AHit >= 0) and (AHit <= High(FLayout.Hits)) and
    (FLayout.Hits[AHit].Kind = TAtlasHoverHitKind.ProblemAction) and Assigned(FOnProblemAction);
  if not Result then
    Exit;
  TAtlasHoverLayout.DecodeProblemAction(FLayout.Hits[AHit].Index, ProblemIndex, ProblemAction);
  FOnProblemAction(Self, ProblemIndex, ProblemAction);
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
    FOnProblemAction(Self, FLayout.FixProblem, TAtlasHoverProblemAction.Fix);
end;

procedure TAtlasHoverTip.Paint;
var
  Index: Integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  // Nur neu setzen, wenn sich Breite, Doku-Höhe, Markierung, Schrift oder Farben geändert haben.
  if LayoutKey(ClientWidth) <> FLayoutKey then
    BuildLayout(ClientWidth);
  // Letzte Randfläche am unteren Fensterrand.
  FLayout.Anchor(ClientHeight);
  for Index := 0 to High(FLayout.Items) do
    PaintItem(FLayout.Items[Index]);
  Canvas.Brush.Style := bsSolid;
  PaintBorder;
end;

end.
