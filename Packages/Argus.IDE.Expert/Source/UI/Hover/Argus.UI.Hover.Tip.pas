unit Argus.UI.Hover.Tip;

// Hover-Tooltip auf Bezeichnern (#442) im Stil von Hint und Panel, mit
// Navigation über Typen (#588):
//   - Pfadzeile (nur angeheftet): Zurück-Pfeil, besuchte Typen, „angeheftet“.
//   - Kopfzeile: Badge, Art und Herkunft, rechts der Fundort.
//   - Eingefärbte Deklaration; Typnamen darin unterstrichen und anklickbar.
//   - Wert, Veraltung, Beschreibung (höchstens vier Zeilen).
//   - Vererbung bzw. Zieltyp: Kette mit anklickbaren Gliedern, der angezeigte
//     Typ hervorgehoben; mehr als fünf Glieder als erste vier, „…“, letztes.
//   - Aktionsleiste für den angezeigten Typ: Gehe zu, Verwendungen,
//     Deklaration kopieren, Hilfe.
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
    class function Create(const AData: TArgusHoverData): TArgusHoverView; static;
  end;

  TArgusHoverRefEvent = procedure(Sender: TObject; const ARef: TArgusHoverTypeRef; AControl: Boolean) of object;
  TArgusHoverIndexEvent = procedure(Sender: TObject; AIndex: Integer) of object;
  TArgusHoverActionEvent = procedure(Sender: TObject; AAction: TArgusHoverAction) of object;

  TArgusHoverTip = class(TArgusPopupWindow)
  public const
    MaxWidth = 440;
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
var
  Left, Right, Y, X, LineHeight, Line, Index, From, Till, LinkFrom, LinkTill, Start: Integer;
  Data: TArgusHoverData;
  Declaration: TArgusStyledText;
  Lines: TArray<TPoint>;
  Chain: TArray<Integer>;
  Caption, Location: string;
  Box, Area: TRect;
  Badge: TArgusBadgeKind;

  procedure AddHit(AKind: THitKind; AIndex: Integer; const ARect: TRect);
  var
    Hit: THit;
  begin
    Hit.Kind := AKind;
    Hit.Index := AIndex;
    Hit.Rect := ARect;
    FHits := FHits + [Hit];
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
    if ADraw then
      DrawText(Canvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_END_ELLIPSIS);
    Y := Area.Bottom + Scale(6);
  end;

  procedure Separator;
  begin
    if ADraw then
    begin
      Canvas.Pen.Color := ToColor(Colors.Line);
      Canvas.MoveTo(Scale(1), Y);
      Canvas.LineTo(AWidth - Scale(1), Y);
    end;
    Inc(Y, Scale(6));
  end;

  // Fließtext in UIFont mit Umbruch; AKind/AIndex legen eine Klickfläche an (AIndex < 0: keine).
  procedure Flow(const AText: string; AColor: TArgusColor; ABold: Boolean; AKind: THitKind; AIndex: Integer;
    AUnderline: Boolean = False);
  var
    TextWidth, Height: Integer;
    Cell: TRect;
  begin
    Canvas.Font := UIFont;
    if ABold then
      Canvas.Font.Style := [fsBold];
    if AUnderline then
      Canvas.Font.Style := Canvas.Font.Style + [fsUnderline];
    TextWidth := Canvas.TextWidth(AText);
    Height := Canvas.TextHeight('Wg');
    if (X + TextWidth > Right) and (X > Left) then
    begin
      X := Left;
      Inc(Y, Height + Scale(2));
    end;
    Cell := Rect(X, Y, X + TextWidth, Y + Height);
    if ADraw then
    begin
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := ToColor(AColor);
      Canvas.TextOut(X, Y, AText);
    end;
    if AIndex >= 0 then
      AddHit(AKind, AIndex, Cell);
    Inc(X, TextWidth);
  end;

  procedure EndFlow;
  begin
    Canvas.Font := UIFont;
    Inc(Y, Canvas.TextHeight('Wg') + Scale(6));
    X := Left;
  end;

  procedure ActionItem(const AKey, ACaption: string; AAction: TArgusHoverAction; AEnabled: Boolean);
  var
    Color: TArgusColor;
  begin
    if X > Left then
      Flow('   ', Colors.Muted, False, hkAction, -1);
    if AEnabled then
      Color := Colors.Text
    else
      Color := Colors.Muted;
    Start := X;
    Flow(AKey + ' ', Colors.Muted, True, hkAction, -1);
    Flow(ACaption, Color, False, hkAction, -1, AEnabled and IsHot(hkAction, Ord(AAction)));
    if AEnabled then
      AddHit(hkAction, Ord(AAction), Rect(Start, Y, X, Y + Canvas.TextHeight('Wg')));
  end;

begin
  FHits := nil;
  Data := FView.Data;
  Left := Scale(11);
  Right := AWidth - Scale(11);
  Y := Scale(8);
  X := Left;
  // Pfadzeile (nur angeheftet).
  if FView.Pinned then
  begin
    if FView.CanGoBack then
      Flow('←', Colors.Accent, True, hkBack, 0)
    else
      Flow('←', Colors.Muted, True, hkBack, -1);
    Flow('  ', Colors.Muted, False, hkPath, -1);
    for Index := 0 to High(FView.Path) do
    begin
      if Index > 0 then
        Flow(' › ', Colors.Muted, False, hkPath, -1);
      if Index = High(FView.Path) then
        Flow(FView.Path[Index].Caption, Colors.Text, True, hkPath, -1)
      else if FView.Path[Index].Index < 0 then
        Flow(FView.Path[Index].Caption, Colors.Muted, False, hkPath, -1)
      else
        Flow(FView.Path[Index].Caption, Colors.Accent, False, hkPath, FView.Path[Index].Index,
          IsHot(hkPath, FView.Path[Index].Index));
    end;
    Canvas.Font := UIFont;
    Caption := TArgusStrings.Text(TArgusTextId.HoverPinned);
    if ADraw and (X + Canvas.TextWidth(Caption) + Scale(12) < Right) then
    begin
      Canvas.Font.Color := ToColor(Colors.Muted);
      Canvas.TextOut(Right - Canvas.TextWidth(Caption), Y, Caption);
    end;
    EndFlow;
    Separator;
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
      if ADraw then
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
    Canvas.Font := UIFont;
    if ADraw then
    begin
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := ToColor(Colors.Muted);
      Canvas.TextOut(X, Y + (LineHeight - Canvas.TextHeight('Wg')) div 2, Caption);
      if Location <> '' then
        Canvas.TextOut(Max(X + Canvas.TextWidth(Caption) + Scale(12), Right - Canvas.TextWidth(Location)),
          Y + (LineHeight - Canvas.TextHeight('Wg')) div 2, Location);
    end;
    Inc(Y, LineHeight + Scale(5));
    X := Left;
  end;
  // Deklaration eingefärbt, an Leerzeichen umbrochen; Typnamen unterstrichen.
  Canvas.Font := Font;
  LineHeight := Canvas.TextHeight('Wg') + Scale(2);
  Declaration := TArgusStyledText.Create(Data.Declaration);
  Lines := Declaration.WrapAtSpaces(Canvas, Right - Left, Scale(16));
  for Line := 0 to High(Lines) do
  begin
    X := Left + IfThen(Line > 0, Scale(16));
    From := Lines[Line].X;
    Till := Lines[Line].Y;
    Start := X;
    if ADraw then
      Declaration.Draw(Canvas, Colors, From, Till, X, Rect(X, Y, Right, Y + LineHeight), False, Scale(3));
    for Index := 0 to High(Data.Links) do
    begin
      LinkFrom := Max(From, Data.Links[Index].Start);
      LinkTill := Min(Till, Data.Links[Index].Start + Data.Links[Index].Length);
      if LinkFrom >= LinkTill then
        Continue;
      Canvas.Font := Font;
      Area := Rect(Start + Declaration.Width(Canvas, From, LinkFrom), Y,
        Start + Declaration.Width(Canvas, From, LinkTill), Y + LineHeight);
      AddHit(hkLink, Index, Area);
      if ADraw then
      begin
        Canvas.Pen.Color := ToColor(Colors.Accent);
        Canvas.Pen.Width := IfThen(IsHot(hkLink, Index), Scale(2), 1);
        Canvas.MoveTo(Area.Left, Area.Bottom - Scale(2));
        Canvas.LineTo(Area.Right, Area.Bottom - Scale(2));
        Canvas.Pen.Width := 1;
      end;
    end;
    Inc(Y, LineHeight);
  end;
  Inc(Y, Scale(4));
  X := Left;
  if Location = '' then
    Block(Data.UnitName, Colors.Muted, 0);
  if Data.Value <> '' then
    Block('= ' + Data.Value, Colors.Muted, 2);
  Block(Data.Deprecation, Colors.Warn, 2);
  Block(Data.Documentation, Colors.Text, MaxDocumentationLines);
  // Vererbung bzw. Zieltyp: Kette mit anklickbaren Gliedern.
  if Length(Data.Ancestors) > 0 then
  begin
    if Data.Kind = TArgusHoverData.KindClassRef then
      Caption := TArgusStrings.Fmt(TArgusTextId.HoverTargetType, [Data.ChainOf])
    else
      Caption := TArgusStrings.Text(TArgusTextId.HoverInheritance);
    Flow(Caption, Colors.Muted, True, hkAncestor, -1);
    EndFlow;
    Dec(Y, Scale(3));
    Chain := Data.VisibleChain;
    for Index := 0 to High(Chain) do
    begin
      if Index > 0 then
        Flow(' › ', Colors.Muted, False, hkAncestor, -1);
      if Chain[Index] < 0 then
        Flow('…', Colors.Muted, False, hkAncestor, -1)
      else if Data.Ancestors[Chain[Index]].Key = Data.Location.Key then
        Flow(Data.Ancestors[Chain[Index]].Name, Colors.Accent, True, hkAncestor, Chain[Index])
      else
        Flow(Data.Ancestors[Chain[Index]].Name, Colors.Text, False, hkAncestor, Chain[Index],
          IsHot(hkAncestor, Chain[Index]));
    end;
    EndFlow;
  end;
  // Aktionsleiste für den angezeigten Typ.
  if Data.Location.HasLocation then
  begin
    Separator;
    ActionItem('F12', TArgusStrings.Fmt(TArgusTextId.HoverGoTo, [Data.Title]), TArgusHoverAction.Navigate, True);
    if FView.UsagesCount >= 0 then
      Caption := TArgusStrings.Fmt(TArgusTextId.HoverUsagesCount, [FView.UsagesCount])
    else
      Caption := TArgusStrings.Text(TArgusTextId.HoverUsages);
    ActionItem(TArgusStrings.Text(TArgusTextId.HoverKeyUsages), Caption, TArgusHoverAction.Usages, True);
    ActionItem(TArgusStrings.Text(TArgusTextId.HoverKeyCopy), TArgusStrings.Text(TArgusTextId.HoverCopy),
      TArgusHoverAction.Copy, True);
    ActionItem('F1', TArgusStrings.Text(TArgusTextId.HoverHelp), TArgusHoverAction.Help, Data.DocWiki <> '');
    EndFlow;
    Dec(Y, Scale(3));
  end;
  Result := Y + Scale(3);
end;

function TArgusHoverTip.PreferredWidth: Integer;
var
  Widest: Integer;
begin
  HandleNeeded;
  // Breite: Deklaration in einer Zeile, sonst die Höchstbreite.
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Widest := Canvas.TextWidth(FView.Data.Declaration);
  Canvas.Font := UIFont;
  Widest := Max(Widest, Canvas.TextWidth(FView.Data.UnitName));
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
