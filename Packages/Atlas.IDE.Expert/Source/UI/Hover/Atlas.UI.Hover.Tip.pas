unit Atlas.UI.Hover.Tip;

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
// Ohne Fokus wie alle Atlas-Fenster; Klicks kommen trotzdem an (MA_NOACTIVATE).
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
  Atlas.Core.Style.Color,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.History,
  Atlas.Core.Problems.Contract,
  Atlas.UI.Popup.Window;

type
  {$SCOPEDENUMS ON}
  TAtlasHoverAction = (Navigate, Usages, Copy, Help);
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
    class function Create(const AData: TAtlasHoverData): TAtlasHoverView; static;
  end;

  TAtlasHoverRefEvent = procedure(Sender: TObject; const ARef: TAtlasHoverTypeRef; AControl: Boolean) of object;
  TAtlasHoverIndexEvent = procedure(Sender: TObject; AIndex: Integer) of object;
  TAtlasHoverActionEvent = procedure(Sender: TObject; AAction: TAtlasHoverAction) of object;

  TAtlasHoverTip = class(TAtlasPopupWindow)
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
    FView: TAtlasHoverView;
    FHits: TArray<THit>;
    FHot: Integer;
    FOnLink: TAtlasHoverRefEvent;
    FOnPath: TAtlasHoverIndexEvent;
    FOnBack: TNotifyEvent;
    FOnAction: TAtlasHoverActionEvent;
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
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Core.Style.Palette,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Styled,
  Atlas.UI.Popup.Accessibility;

{ TAtlasHoverView }

class function TAtlasHoverView.Create(const AData: TAtlasHoverData): TAtlasHoverView;
begin
  Result := Default(TAtlasHoverView);
  Result.Data := AData;
  Result.UsagesCount := -1;
end;

{ TAtlasHoverTip }

constructor TAtlasHoverTip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHot := -1;
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

function BadgeKind(const ACode: string): TAtlasBadgeKind;
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

function TAtlasHoverTip.IsHot(AKind: THitKind; AIndex: Integer): Boolean;
begin
  Result := (FHot >= 0) and (FHot <= High(FHits)) and (FHits[FHot].Kind = AKind) and (FHits[FHot].Index = AIndex);
end;

function TAtlasHoverTip.Render(AWidth: Integer; ADraw: Boolean): Integer;
const
  FontUI = 0;
  FontMono = 1;
  FontSmall = 2;
  BandChain = 0;
  BandActions = 1;
var
  Left, Right, Y, X, LineHeight, RowHeight, Line, Index, From, Till, Pos, Next, LinkFrom, LinkTill, Start,
    NavHeight, FlowFont: Integer;
  Data: TAtlasHoverData;
  Declaration: TAtlasStyledText;
  Lines: TArray<TPoint>;
  Caption, Location: string;
  Box, Area: TRect;
  Badge: TAtlasBadgeKind;
  Drawing, NoWrap: Boolean;
  Problem: TAtlasProblem;

  function SeverityColor(const AProblem: TAtlasProblem): TAtlasColor;
  begin
    case AProblem.Severity of
      TAtlasProblemSeverity.Error:
        Result := Colors.Error;
      TAtlasProblemSeverity.Warning:
        Result := Colors.Warn;
      TAtlasProblemSeverity.Information:
        Result := Colors.Accent;
    else
      Result := Colors.Muted;
    end;
    if AProblem.Stale then
      Result := TAtlasColorMath.Mix(Result, Colors.Surface, 0.5);
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

  procedure Block(const AText: string; AColor: TAtlasColor; AMaxLines: Integer);
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
  procedure Flow(const AText: string; AColor: TAtlasColor; ABold: Boolean; AKind: THitKind; AIndex: Integer;
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
  procedure ActionItem(const AKey, ACaption: string; AAction: TAtlasHoverAction; AEnabled: Boolean);
  var
    KeyColor, TextColor: TAtlasColor;
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
          if Data.Kind = TAtlasHoverData.KindClassRef then
            Caption := TAtlasStrings.Fmt(TAtlasTextId.HoverTargetType, [Data.ChainOf])
          else
            Caption := TAtlasStrings.Text(TAtlasTextId.HoverInheritance);
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
          ActionItem('F12', TAtlasStrings.Fmt(TAtlasTextId.HoverGoTo, [Data.Title]), TAtlasHoverAction.Navigate,
            True);
          if FView.UsagesCount >= 0 then
            Caption := TAtlasStrings.Fmt(TAtlasTextId.HoverUsagesCount, [FView.UsagesCount])
          else
            Caption := TAtlasStrings.Text(TAtlasTextId.HoverUsages);
          ActionItem(TAtlasStrings.Text(TAtlasTextId.HoverKeyUsages), Caption, TAtlasHoverAction.Usages, True);
          ActionItem(TAtlasStrings.Text(TAtlasTextId.HoverKeyCopy), TAtlasStrings.Text(TAtlasTextId.HoverCopy),
            TAtlasHoverAction.Copy, True);
          ActionItem('F1', TAtlasStrings.Text(TAtlasTextId.HoverHelp), TAtlasHoverAction.Help, Data.DocWiki <> '');
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
    Caption := TAtlasStrings.Text(TAtlasTextId.HoverPinned);
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
        Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsSourceCompiler)
      else
        Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsSourceAtlas);
      if Problem.Stale then
        Caption := Caption + ' · ' + TAtlasStrings.Text(TAtlasTextId.ProblemsStale);
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
  Declaration := TAtlasStyledText.Create(Data.Declaration);
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
  Canvas.Font := UIFont;
  Widest := Max(Widest, Canvas.TextWidth(FView.Data.UnitName));
  for Problem in FView.Problems do
    Widest := Max(Widest, Canvas.TextWidth(Problem.Caption) + Scale(9));
  if (FView.Data.Documentation <> '') or (Length(FView.Data.Ancestors) > 0) or FView.Data.Location.HasLocation or
    FView.Pinned then
    Widest := Scale(MaxWidth);
  Result := EnsureRange(Widest + Scale(26), Scale(200), Scale(MaxWidth));
end;

procedure TAtlasHoverTip.ShowContent(const AView: TAtlasHoverView; const AWord: TRect);
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
  // Sprachausgabe (#447): Deklaration und Anfang der Doku.
  SetAccessible(UiaToolTipControlType, TAtlasStrings.Text(TAtlasTextId.AccessHover));
  Announce(Trim(AView.Data.Declaration + '. ' + Copy(AView.Data.Documentation, 1, 300)));
end;

procedure TAtlasHoverTip.UpdateContent(const AView: TAtlasHoverView);
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

function TAtlasHoverTip.HitAt(AX, AY: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FHits) do
    if PtInRect(FHits[Index].Rect, Point(AX, AY)) then
      Exit(Index);
  Result := -1;
end;

procedure TAtlasHoverTip.MouseMove(Shift: TShiftState; X, Y: Integer);
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

procedure TAtlasHoverTip.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if FHot >= 0 then
  begin
    FHot := -1;
    Invalidate;
  end;
end;

procedure TAtlasHoverTip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
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
        FOnAction(Self, TAtlasHoverAction(Hit.Index));
  end;
end;

procedure TAtlasHoverTip.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Render(ClientWidth, True);
  Canvas.Brush.Style := bsSolid;
  PaintBorder;
end;

end.
