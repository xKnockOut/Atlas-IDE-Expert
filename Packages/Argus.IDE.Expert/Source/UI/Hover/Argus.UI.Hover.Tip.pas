unit Argus.UI.Hover.Tip;

// Hover-Tooltip auf Bezeichnern (#442) im Stil von Hint und Panel, mit
// Navigation über Typen (#588):
//   - Pfadzeile (nur angeheftet) auf Randfläche: Zurück-Knopf, besuchte Typen,
//     rechts „angeheftet“.
//   - Kopfzeile: Badge, Art und Herkunft, rechts der Fundort.
//   - Eingefärbte Deklaration; Typnamen darin in Akzentfarbe unterstrichen
//     und anklickbar.
//   - Unter einer Linie: Wert, Veraltung, Beschreibung (höchstens vier Zeilen).
//   - Vererbung bzw. Zieltyp auf Randfläche: Glieder als Kästchen, das
//     angezeigte in Akzentfarbe; mehr als fünf als erste vier, „…“, letztes.
//   - Aktionsleiste auf Randfläche am unteren Rand: Gehe zu, Verwendungen,
//     Deklaration kopieren, Hilfe; Tasten in Akzentfarbe.
// Probleme an der Mausposition (#398) stehen ganz oben, je mit Farbbalken nach
// Schweregrad, Meldung, Regel-ID bzw. Meldungsnummer und Herkunft; ohne
// Bezeichner zeigt der Tooltip nur sie.
// Ohne Fokus wie alle Argus-Fenster; Klicks kommen trotzdem an (MA_NOACTIVATE).
// Beim Wechsel des Inhalts bleibt die Position, das Fenster wächst höchstens.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Argus.Core.Style.Color,
  Argus.Core.Hover.Contract,
  Argus.Core.Hover.History,
  Argus.Core.Problems.Contract,
  Argus.UI.Popup.Window;

type
  {$SCOPEDENUMS ON}
  TArgusHoverAction = (Navigate, Usages, Copy, Help);
  {$SCOPEDENUMS OFF}

  /// <summary>Was der Tooltip zeigt: Inhalt, Pfad und Zustand.</summary>
  TArgusHoverView = record
    Data: TArgusHoverData;
    Path: TArray<TArgusHoverPathItem>;
    Pinned: Boolean;
    CanGoBack: Boolean;
    /// <summary>Anzahl der Verwendungen, wenn bekannt; sonst -1.</summary>
    UsagesCount: Integer;
    /// <summary>Probleme an der Mausposition (#398).</summary>
    Problems: TArray<TArgusProblem>;
    class function Create(const AData: TArgusHoverData): TArgusHoverView; static;
  end;

  TArgusHoverRefEvent = procedure(Sender: TObject; const ARef: TArgusHoverTypeRef; AControl: Boolean) of object;
  TArgusHoverIndexEvent = procedure(Sender: TObject; AIndex: Integer) of object;
  TArgusHoverActionEvent = procedure(Sender: TObject; AAction: TArgusHoverAction) of object;

  TArgusHoverTip = class(TArgusPopupWindow)
  public const
    MaxWidth = 460;
    MaxDocumentationLines = 4;
  private type
    THitKind = (hkLink, hkAncestor, hkPath, hkBack, hkAction);
    THit = record
      Kind: THitKind;
      Index: Integer;
      Rect: TRect;
    end;
  private
    FView: TArgusHoverView;
    FHits: TArray<THit>;
    FHot: Integer;
    FOnLink: TArgusHoverRefEvent;
    FOnPath: TArgusHoverIndexEvent;
    FOnBack: TNotifyEvent;
    FOnAction: TArgusHoverActionEvent;
    /// <summary>Zeichnet bzw. misst bei ADraw = False; liefert die Höhe und sammelt die Klickflächen.</summary>
    function Render(AWidth: Integer; ADraw: Boolean): Integer;
    function HitAt(AX, AY: Integer): Integer;
    function IsHot(AKind: THitKind; AIndex: Integer): Boolean;
    function PreferredWidth: Integer;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeigt AView unter AWord (Bildschirmrechteck des Bezeichners).</summary>
    procedure ShowContent(const AView: TArgusHoverView; const AWord: TRect);
    /// <summary>Tauscht den Inhalt; Position bleibt, Breite und Höhe wachsen höchstens.</summary>
    procedure UpdateContent(const AView: TArgusHoverView);
    /// <summary>Text der Art für die Kopfzeile (Klasse, Methode …); '' wenn unbekannt.</summary>
    class function KindCaption(const AKind: string): string; static;
    property View: TArgusHoverView read FView;
    property OnLink: TArgusHoverRefEvent read FOnLink write FOnLink;
    property OnPath: TArgusHoverIndexEvent read FOnPath write FOnPath;
    property OnBack: TNotifyEvent read FOnBack write FOnBack;
    property OnAction: TArgusHoverActionEvent read FOnAction write FOnAction;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Argus.Core.Style.Palette,
  Argus.UI.Strings,
  Argus.UI.Popup.Styled;

{ TArgusHoverView }

class function TArgusHoverView.Create(const AData: TArgusHoverData): TArgusHoverView;
begin
  Result := Default(TArgusHoverView);
  Result.Data := AData;
  Result.UsagesCount := -1;
end;

{ TArgusHoverTip }

constructor TArgusHoverTip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHot := -1;
end;

class function TArgusHoverTip.KindCaption(const AKind: string): string;
const
  Kinds: array[0..15] of string = ('class', 'classref', 'object', 'record', 'interface', 'helper', 'enum', 'type',
    'method', 'constructor', 'routine', 'property', 'field', 'variable', 'constant', 'enumMember');
  Ids: array[0..15] of TArgusTextId = (TArgusTextId.KindClass, TArgusTextId.KindClassRef, TArgusTextId.KindObject,
    TArgusTextId.KindRecord, TArgusTextId.KindInterface, TArgusTextId.KindHelper, TArgusTextId.KindEnum,
    TArgusTextId.KindType, TArgusTextId.KindMethod, TArgusTextId.KindConstructor, TArgusTextId.KindRoutine,
    TArgusTextId.KindProperty, TArgusTextId.KindField, TArgusTextId.KindVariable, TArgusTextId.KindConstant,
    TArgusTextId.KindEnumMember);
var
  Index: Integer;
begin
  Index := IndexStr(AKind, Kinds);
  if Index < 0 then
    Result := ''
  else
    Result := TArgusStrings.Text(Ids[Index]);
end;

function BadgeKind(const ACode: string): TArgusBadgeKind;
begin
  case IndexStr(ACode, ['ty', 'fn', 'pp', 'fd', 'va', 'co', 'un']) of
    0: Result := TArgusBadgeKind.Type_;
    1: Result := TArgusBadgeKind.Function_;
    2: Result := TArgusBadgeKind.Property_;
    3: Result := TArgusBadgeKind.Field;
    4: Result := TArgusBadgeKind.Variable;
    5: Result := TArgusBadgeKind.Constant;
    6: Result := TArgusBadgeKind.Unit_;
  else
    Result := TArgusBadgeKind.Keyword;
  end;
end;

function TArgusHoverTip.IsHot(AKind: THitKind; AIndex: Integer): Boolean;
begin
  Result := (FHot >= 0) and (FHot <= High(FHits)) and (FHits[FHot].Kind = AKind) and (FHits[FHot].Index = AIndex);
end;

function TArgusHoverTip.Render(AWidth: Integer; ADraw: Boolean): Integer;
const
  FontUI = 0;
  FontMono = 1;
  FontSmall = 2;
  BandChain = 0;
  BandActions = 1;
var
  Left, Right, Y, X, LineHeight, RowHeight, Line, Index, From, Till, Pos, Next, LinkFrom, LinkTill, Start,
    NavHeight, FlowFont: Integer;
  Data: TArgusHoverData;
  Declaration: TArgusStyledText;
  Lines: TArray<TPoint>;
  Caption, Location: string;
  Box, Area: TRect;
  Badge: TArgusBadgeKind;
  Drawing, NoWrap: Boolean;
  Problem: TArgusProblem;

  function SeverityColor(const AProblem: TArgusProblem): TArgusColor;
  begin
    case AProblem.Severity of
      TArgusProblemSeverity.Error:
        Result := Colors.Error;
      TArgusProblemSeverity.Warning:
        Result := Colors.Warn;
      TArgusProblemSeverity.Information:
        Result := Colors.Accent;
    else
      Result := Colors.Muted;
    end;
    if AProblem.Stale then
      Result := TArgusColorMath.Mix(Result, Colors.Surface, 0.5);
  end;

  procedure AddHit(AKind: THitKind; AIndex: Integer; const ARect: TRect);
  var
    Hit: THit;
  begin
    Hit.Kind := AKind;
    Hit.Index := AIndex;
    Hit.Rect := ARect;
    FHits := FHits + [Hit];
  end;

  // Kleinere Schrift für Beschriftungen (UI) bzw. Abschnittstitel (Editorschrift).
  procedure SmallFont(AMono: Boolean);
  begin
    if AMono then
    begin
      Canvas.Font := Font;
      Canvas.Font.Height := Round(Font.Height * 0.8);
    end
    else
    begin
      Canvas.Font := UIFont;
      Canvas.Font.Height := Round(UIFont.Height * 0.88);
    end;
  end;

  procedure SetFlowFont(ABold, AUnderline: Boolean);
  begin
    case FlowFont of
      FontMono:
        Canvas.Font := Font;
      FontSmall:
        SmallFont(False);
    else
      Canvas.Font := UIFont;
    end;
    Canvas.Font.Style := [];
    if ABold then
      Canvas.Font.Style := [fsBold];
    if AUnderline then
      Canvas.Font.Style := Canvas.Font.Style + [fsUnderline];
  end;

  procedure Block(const AText: string; AColor: TArgusColor; AMaxLines: Integer);
  var
    Area: TRect;
  begin
    if AText = '' then
      Exit;
    Canvas.Font := UIFont;
    Canvas.Font.Color := ToColor(AColor);
    Canvas.Brush.Style := bsClear;
    Area := Rect(Left, Y, Right, Y);
    DrawText(Canvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
    Area.Right := Right;
    if AMaxLines > 0 then
      Area.Bottom := Min(Area.Bottom, Y + AMaxLines * Canvas.TextHeight('Wg'));
    if Drawing then
      DrawText(Canvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_END_ELLIPSIS);
    Y := Area.Bottom + Scale(6);
  end;

  procedure HorizontalLine(ATop: Integer);
  begin
    if Drawing then
    begin
      Canvas.Pen.Color := ToColor(Colors.Line);
      Canvas.Pen.Width := 1;
      Canvas.MoveTo(0, ATop);
      Canvas.LineTo(AWidth, ATop);
    end;
  end;

  // Fließtext mit Umbruch; AKind/AIndex legen eine Klickfläche an (AIndex < 0: keine).
  procedure Flow(const AText: string; AColor: TArgusColor; ABold: Boolean; AKind: THitKind; AIndex: Integer;
    AUnderline: Boolean = False);
  var
    TextWidth, Height: Integer;
    Cell: TRect;
  begin
    SetFlowFont(ABold, AUnderline);
    TextWidth := Canvas.TextWidth(AText);
    Height := Canvas.TextHeight('Wg');
    if not NoWrap and (X + TextWidth > Right) and (X > Left) then
    begin
      X := Left;
      Inc(Y, RowHeight + Scale(4));
      RowHeight := 0;
    end;
    Cell := Rect(X, Y, X + TextWidth, Y + Height);
    if Drawing then
    begin
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := ToColor(AColor);
      Canvas.TextOut(X, Y, AText);
    end;
    if AIndex >= 0 then
      AddHit(AKind, AIndex, Cell);
    Inc(X, TextWidth);
    RowHeight := Max(RowHeight, Height);
  end;

  procedure EndFlow;
  begin
    Inc(Y, RowHeight);
    RowHeight := 0;
    X := Left;
  end;

  // Glied der Vererbungskette als umrandetes Kästchen; das angezeigte in Akzentfarbe.
  procedure Chip(const AText: string; ACurrent: Boolean; AIndex: Integer);
  var
    TextWidth, Height: Integer;
    Cell: TRect;
    Marked: Boolean;
  begin
    Canvas.Font := Font;
    if ACurrent then
      Canvas.Font.Style := [fsBold];
    TextWidth := Canvas.TextWidth(AText);
    Height := Canvas.TextHeight('Wg') + Scale(2);
    if (X + TextWidth + Scale(12) > Right) and (X > Left) then
    begin
      X := Left;
      Inc(Y, RowHeight + Scale(4));
      RowHeight := 0;
    end;
    Cell := Rect(X, Y, X + TextWidth + Scale(12), Y + Height);
    if Drawing then
    begin
      Marked := ACurrent or IsHot(hkAncestor, AIndex);
      if Marked then
        FrameRounded(Cell, Colors.Accent, 4, ToColor(Colors.Surface))
      else
        FrameRounded(Cell, Colors.Line, 4, ToColor(Colors.Surface));
      Canvas.Brush.Style := bsClear;
      if Marked then
        Canvas.Font.Color := ToColor(Colors.Accent)
      else
        Canvas.Font.Color := ToColor(Colors.Text);
      Canvas.TextOut(Cell.Left + Scale(6), Cell.Top + Scale(1), AText);
    end;
    if not ACurrent then
      AddHit(hkAncestor, AIndex, Cell);
    X := Cell.Right;
    RowHeight := Max(RowHeight, Height);
  end;

  // Eintrag der Aktionsleiste: Taste in Akzentfarbe, Beschriftung gedämpft; bleibt in einer Zeile.
  procedure ActionItem(const AKey, ACaption: string; AAction: TArgusHoverAction; AEnabled: Boolean);
  var
    KeyColor, TextColor: TArgusColor;
    Total: Integer;
  begin
    if X > Left then
      Inc(X, Scale(14));
    SmallFont(False);
    Canvas.Font.Style := [fsBold];
    Total := Canvas.TextWidth(AKey + ' ');
    Canvas.Font.Style := [];
    Inc(Total, Canvas.TextWidth(ACaption));
    if (X + Total > Right) and (X > Left) then
    begin
      X := Left;
      Inc(Y, RowHeight + Scale(3));
      RowHeight := 0;
    end;
    if AEnabled then
      KeyColor := Colors.Accent
    else
      KeyColor := Colors.Muted;
    TextColor := Colors.Muted;
    if AEnabled and IsHot(hkAction, Ord(AAction)) then
      TextColor := Colors.Text;
    Start := X;
    Flow(AKey + ' ', KeyColor, True, hkAction, -1);
    Flow(ACaption, TextColor, False, hkAction, -1, AEnabled and IsHot(hkAction, Ord(AAction)));
    if AEnabled then
      AddHit(hkAction, Ord(AAction), Rect(Start, Y, X, Y + RowHeight));
  end;

  procedure BandContent(AKind: Integer);
  var
    Chain: TArray<Integer>;
    Item: Integer;
  begin
    X := Left;
    RowHeight := 0;
    case AKind of
      BandChain:
        begin
          Inc(Y, Scale(8));
          if Data.Kind = TArgusHoverData.KindClassRef then
            Caption := TArgusStrings.Fmt(TArgusTextId.HoverTargetType, [Data.ChainOf])
          else
            Caption := TArgusStrings.Text(TArgusTextId.HoverInheritance);
          SmallFont(True);
          Canvas.Font.Style := [fsBold];
          if Drawing then
          begin
            Canvas.Brush.Style := bsClear;
            Canvas.Font.Color := ToColor(Colors.Muted);
            Canvas.TextOut(Left, Y, AnsiUpperCase(Caption));
          end;
          Inc(Y, Canvas.TextHeight('Wg') + Scale(6));
          FlowFont := FontMono;
          Chain := Data.VisibleChain;
          for Item := 0 to High(Chain) do
          begin
            if Item > 0 then
              Flow(' › ', Colors.Muted, False, hkAncestor, -1);
            if Chain[Item] < 0 then
              Flow('…', Colors.Muted, False, hkAncestor, -1)
            else
              Chip(Data.Ancestors[Chain[Item]].Name, Data.Ancestors[Chain[Item]].Key = Data.Location.Key,
                Chain[Item]);
          end;
          EndFlow;
          Inc(Y, Scale(8));
        end;
      BandActions:
        begin
          Inc(Y, Scale(6));
          FlowFont := FontSmall;
          ActionItem('F12', TArgusStrings.Fmt(TArgusTextId.HoverGoTo, [Data.Title]), TArgusHoverAction.Navigate,
            True);
          if FView.UsagesCount >= 0 then
            Caption := TArgusStrings.Fmt(TArgusTextId.HoverUsagesCount, [FView.UsagesCount])
          else
            Caption := TArgusStrings.Text(TArgusTextId.HoverUsages);
          ActionItem(TArgusStrings.Text(TArgusTextId.HoverKeyUsages), Caption, TArgusHoverAction.Usages, True);
          ActionItem(TArgusStrings.Text(TArgusTextId.HoverKeyCopy), TArgusStrings.Text(TArgusTextId.HoverCopy),
            TArgusHoverAction.Copy, True);
          ActionItem('F1', TArgusStrings.Text(TArgusTextId.HoverHelp), TArgusHoverAction.Help, Data.DocWiki <> '');
          EndFlow;
          Inc(Y, Scale(6));
        end;
    end;
    FlowFont := FontUI;
  end;

  // Abschnitt auf Randfläche mit Linie oben; der letzte sitzt am unteren Fensterrand.
  procedure Band(AKind: Integer; ALast: Boolean);
  var
    Top, Height, Saved: Integer;
  begin
    Top := Y;
    if Drawing then
    begin
      Saved := Length(FHits);
      Drawing := False;
      BandContent(AKind);
      SetLength(FHits, Saved);
      Drawing := True;
      Height := Y - Top;
      if ALast then
        Top := Max(Top, ClientHeight - Height);
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(Colors.Gutter);
      Canvas.FillRect(Rect(0, Top, AWidth, Top + Height));
      HorizontalLine(Top);
      Y := Top;
    end;
    BandContent(AKind);
  end;

  procedure DrawPart(AFrom, ATill: Integer);
  begin
    Canvas.Font := Font;
    if Drawing then
      Declaration.Draw(Canvas, Colors, AFrom, ATill, X, Rect(X, Y, Right, Y + LineHeight), False, Scale(3))
    else
      Inc(X, Declaration.Width(Canvas, AFrom, ATill));
  end;

begin
  FHits := nil;
  Data := FView.Data;
  Drawing := ADraw;
  NoWrap := False;
  FlowFont := FontUI;
  RowHeight := 0;
  Left := Scale(11);
  Right := AWidth - Scale(11);
  Y := Scale(8);
  X := Left;
  // Pfadzeile (nur angeheftet) auf Randfläche: Zurück-Knopf, besuchte Typen, rechts „angeheftet“.
  if FView.Pinned then
  begin
    NavHeight := Scale(30);
    if Drawing then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(Colors.Gutter);
      Canvas.FillRect(Rect(0, 0, AWidth, NavHeight));
      HorizontalLine(NavHeight - 1);
    end;
    Box := Rect(Scale(8), (NavHeight - Scale(20)) div 2, Scale(30), (NavHeight - Scale(20)) div 2 + Scale(20));
    if Drawing then
    begin
      if FView.CanGoBack and IsHot(hkBack, 0) then
        FrameRounded(Box, Colors.Accent, 4, ToColor(Colors.Surface))
      else
        FrameRounded(Box, Colors.Line, 4, ToColor(Colors.Surface));
      Canvas.Font := Font;
      Canvas.Font.Style := [fsBold];
      if FView.CanGoBack then
        Canvas.Font.Color := ToColor(Colors.Text)
      else
        Canvas.Font.Color := ToColor(Colors.Muted);
      Canvas.Brush.Style := bsClear;
      Area := Box;
      DrawText(Canvas.Handle, PChar('‹'), -1, Area, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    end;
    if FView.CanGoBack then
      AddHit(hkBack, 0, Box);
    FlowFont := FontMono;
    NoWrap := True;
    Canvas.Font := Font;
    Y := (NavHeight - Canvas.TextHeight('Wg')) div 2;
    X := Box.Right + Scale(6);
    for Index := 0 to High(FView.Path) do
    begin
      if Index > 0 then
        Flow(' › ', Colors.Muted, False, hkPath, -1);
      if Index = High(FView.Path) then
        Flow(FView.Path[Index].Caption, Colors.Text, True, hkPath, -1)
      else if FView.Path[Index].Index < 0 then
        Flow(FView.Path[Index].Caption, Colors.Muted, False, hkPath, -1)
      else
        Flow(FView.Path[Index].Caption, Colors.Muted, False, hkPath, FView.Path[Index].Index,
          IsHot(hkPath, FView.Path[Index].Index));
    end;
    SmallFont(False);
    Caption := TArgusStrings.Text(TArgusTextId.HoverPinned);
    if Drawing and (X + Canvas.TextWidth(Caption) + Scale(12) < Right) then
    begin
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := ToColor(Colors.Muted);
      Canvas.TextOut(Right - Canvas.TextWidth(Caption), (NavHeight - Canvas.TextHeight('Wg')) div 2, Caption);
    end;
    NoWrap := False;
    FlowFont := FontUI;
    RowHeight := 0;
    Y := NavHeight + Scale(8);
    X := Left;
  end;
  // Probleme an der Mausposition: Farbbalken, Meldung, darunter Code und Herkunft.
  if Length(FView.Problems) > 0 then
  begin
    for Problem in FView.Problems do
    begin
      Start := Y;
      Left := Scale(20);
      Block(Problem.Caption, Colors.Text, 3);
      Dec(Y, Scale(4));
      if Problem.IsCompiler then
        Caption := TArgusStrings.Text(TArgusTextId.ProblemsSourceCompiler)
      else
        Caption := TArgusStrings.Text(TArgusTextId.ProblemsSourceArgus);
      if Problem.Stale then
        Caption := Caption + ' · ' + TArgusStrings.Text(TArgusTextId.ProblemsStale);
      SmallFont(False);
      if Drawing then
      begin
        Canvas.Brush.Style := bsClear;
        Canvas.Font.Color := ToColor(Colors.Muted);
        Canvas.TextOut(Left, Y, Caption);
      end;
      Inc(Y, Canvas.TextHeight('Wg') + Scale(6));
      Left := Scale(11);
      if Drawing then
        FillRounded(Rect(Left, Start + Scale(1), Left + Scale(3), Y - Scale(7)), SeverityColor(Problem), 1);
    end;
    if Data.Declaration = '' then
      Exit(Y + Scale(2));
    HorizontalLine(Y);
    Inc(Y, Scale(8));
  end;
  // Kopfzeile: Badge, Art · Herkunft, rechts der Fundort.
  Caption := KindCaption(Data.Kind);
  if (Caption <> '') and (Data.Origin <> '') then
    Caption := Caption + ' · ' + Data.Origin;
  Location := Data.LocationText;
  if (Caption <> '') or (Location <> '') then
  begin
    Canvas.Font := UIFont;
    LineHeight := Max(Canvas.TextHeight('Wg'), Scale(17));
    X := Left;
    if Data.Kind <> '' then
    begin
      Badge := BadgeKind(Data.Badge);
      Box := Rect(Left, Y, Left + Scale(24), Y + Scale(17));
      if Drawing then
      begin
        FillRounded(Box, Colors.Badges[Badge].Background, 4);
        Canvas.Font := Font;
        Canvas.Font.Style := [fsBold];
        Canvas.Font.Height := -Round(Box.Height * 0.62);
        Canvas.Font.Color := ToColor(Colors.Badges[Badge].Text);
        Canvas.Brush.Style := bsClear;
        Area := Box;
        DrawText(Canvas.Handle, PChar(Data.Badge), -1, Area, DT_CENTER or DT_VCENTER or DT_SINGLELINE or
          DT_NOPREFIX);
      end;
      X := Box.Right + Scale(7);
    end;
    if Drawing then
    begin
      SmallFont(False);
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := ToColor(Colors.Muted);
      Canvas.TextOut(X, Y + (LineHeight - Canvas.TextHeight('Wg')) div 2, Caption);
      if Location <> '' then
      begin
        Start := X + Canvas.TextWidth(Caption) + Scale(12);
        SmallFont(True);
        Canvas.Font.Color := ToColor(Colors.Muted);
        Canvas.TextOut(Max(Start, Right - Canvas.TextWidth(Location)),
          Y + (LineHeight - Canvas.TextHeight('Wg')) div 2, Location);
      end;
    end;
    Inc(Y, LineHeight + Scale(5));
    X := Left;
  end;
  // Deklaration eingefärbt, an Leerzeichen umbrochen; Typnamen als Verweise in Akzentfarbe, unterstrichen.
  Canvas.Font := Font;
  LineHeight := Canvas.TextHeight('Wg') + Scale(2);
  Declaration := TArgusStyledText.Create(Data.Declaration);
  Lines := Declaration.WrapAtSpaces(Canvas, Right - Left, Scale(16));
  for Line := 0 to High(Lines) do
  begin
    X := Left + IfThen(Line > 0, Scale(16));
    From := Lines[Line].X;
    Till := Lines[Line].Y;
    Pos := From;
    while Pos < Till do
    begin
      // Nächster Verweis, der in [Pos, Till) hineinreicht.
      Next := -1;
      for Index := 0 to High(Data.Links) do
        if (Data.Links[Index].Start + Data.Links[Index].Length > Pos) and (Data.Links[Index].Start < Till) and
          ((Next < 0) or (Data.Links[Index].Start < Data.Links[Next].Start)) then
          Next := Index;
      if Next < 0 then
      begin
        DrawPart(Pos, Till);
        Pos := Till;
        Continue;
      end;
      LinkFrom := Max(Pos, Data.Links[Next].Start);
      LinkTill := Min(Till, Data.Links[Next].Start + Data.Links[Next].Length);
      if LinkFrom > Pos then
        DrawPart(Pos, LinkFrom);
      Canvas.Font := Font;
      Start := X;
      Inc(X, Declaration.Width(Canvas, LinkFrom, LinkTill));
      Area := Rect(Start, Y, X, Y + LineHeight);
      AddHit(hkLink, Next, Area);
      if Drawing then
      begin
        Canvas.Font := Font;
        Canvas.Font.Color := ToColor(Colors.Accent);
        Canvas.Brush.Style := bsClear;
        Canvas.TextOut(Start, Y + (LineHeight - Canvas.TextHeight('Wg')) div 2,
          Copy(Data.Declaration, LinkFrom + 1, LinkTill - LinkFrom));
        Canvas.Pen.Color := ToColor(Colors.Accent);
        Canvas.Pen.Width := IfThen(IsHot(hkLink, Next), Scale(2), 1);
        Canvas.MoveTo(Area.Left, Area.Bottom - Scale(2));
        Canvas.LineTo(Area.Right, Area.Bottom - Scale(2));
        Canvas.Pen.Width := 1;
      end;
      Pos := LinkTill;
    end;
    Inc(Y, LineHeight);
  end;
  Inc(Y, Scale(6));
  X := Left;
  // Beschreibung unter einer Linie.
  if ((Location = '') and (Data.UnitName <> '')) or (Data.Value <> '') or (Data.Deprecation <> '') or
    (Data.Documentation <> '') then
  begin
    HorizontalLine(Y);
    Inc(Y, Scale(7));
    if Location = '' then
      Block(Data.UnitName, Colors.Muted, 0);
    if Data.Value <> '' then
      Block('= ' + Data.Value, Colors.Muted, 2);
    Block(Data.Deprecation, Colors.Warn, 2);
    Block(Data.Documentation, Colors.Text, MaxDocumentationLines);
    Inc(Y, Scale(1));
  end;
  // Vererbung bzw. Zieltyp und Aktionsleiste auf eigener Randfläche.
  if Length(Data.Ancestors) > 0 then
    Band(BandChain, not Data.Location.HasLocation);
  if Data.Location.HasLocation then
    Band(BandActions, True);
  Result := Y;
end;

function TArgusHoverTip.PreferredWidth: Integer;
var
  Widest: Integer;
  Problem: TArgusProblem;
begin
  HandleNeeded;
  // Breite: Deklaration in einer Zeile, sonst die Höchstbreite.
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Widest := Canvas.TextWidth(FView.Data.Declaration);
  Canvas.Font := UIFont;
  Widest := Max(Widest, Canvas.TextWidth(FView.Data.UnitName));
  for Problem in FView.Problems do
    Widest := Max(Widest, Canvas.TextWidth(Problem.Caption) + Scale(9));
  if (FView.Data.Documentation <> '') or (Length(FView.Data.Ancestors) > 0) or FView.Data.Location.HasLocation or
    FView.Pinned then
    Widest := Scale(MaxWidth);
  Result := EnsureRange(Widest + Scale(26), Scale(200), Scale(MaxWidth));
end;

procedure TArgusHoverTip.ShowContent(const AView: TArgusHoverView; const AWord: TRect);
var
  Width, Height: Integer;
  Area, Bounds: TRect;
begin
  FView := AView;
  FHot := -1;
  Width := PreferredWidth;
  Height := Render(Width, False);
  Area := WorkAreaAt(AWord.TopLeft);
  Bounds := TRect.Create(Point(AWord.Left, AWord.Bottom + Scale(4)), Width, Height);
  if Bounds.Bottom > Area.Bottom then
    Bounds.SetLocation(Bounds.Left, AWord.Top - Height - Scale(4));
  if Bounds.Right > Area.Right then
    Bounds.SetLocation(Max(Area.Left, Area.Right - Width), Bounds.Top);
  ShowAt(Bounds);
end;

procedure TArgusHoverTip.UpdateContent(const AView: TArgusHoverView);
var
  Width, Height: Integer;
  Bounds: TRect;
begin
  if not IsShown then
    Exit;
  FView := AView;
  FHot := -1;
  Width := Max(BoundsRect.Width, PreferredWidth);
  Height := Max(BoundsRect.Height, Render(Width, False));
  Bounds := TRect.Create(BoundsRect.TopLeft, Width, Height);
  ShowAt(Bounds);
  Invalidate;
end;

function TArgusHoverTip.HitAt(AX, AY: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FHits) do
    if PtInRect(FHits[Index].Rect, Point(AX, AY)) then
      Exit(Index);
  Result := -1;
end;

procedure TArgusHoverTip.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hot: Integer;
begin
  inherited;
  Hot := HitAt(X, Y);
  if Hot >= 0 then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  if Hot <> FHot then
  begin
    FHot := Hot;
    Invalidate;
  end;
end;

procedure TArgusHoverTip.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if FHot >= 0 then
  begin
    FHot := -1;
    Invalidate;
  end;
end;

procedure TArgusHoverTip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
  Hit: THit;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  Index := HitAt(X, Y);
  if Index < 0 then
    Exit;
  Hit := FHits[Index];
  case Hit.Kind of
    hkLink:
      if Assigned(FOnLink) then
        FOnLink(Self, FView.Data.Links[Hit.Index].Target, ssCtrl in Shift);
    hkAncestor:
      if Assigned(FOnLink) then
        FOnLink(Self, FView.Data.Ancestors[Hit.Index], ssCtrl in Shift);
    hkPath:
      if Assigned(FOnPath) then
        FOnPath(Self, Hit.Index);
    hkBack:
      if Assigned(FOnBack) then
        FOnBack(Self);
    hkAction:
      if Assigned(FOnAction) then
        FOnAction(Self, TArgusHoverAction(Hit.Index));
  end;
end;

procedure TArgusHoverTip.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Render(ClientWidth, True);
  Canvas.Brush.Style := bsSolid;
  PaintBorder;
end;

end.
