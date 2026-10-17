unit Atlas.UI.Editor.Peek;

// Fenster für Definition und Referenzen einblenden (#505), nur VCL:
// - Nimmt dem Editor nie den Fokus (TAtlasPopupWindow, #410); Tasten kommen
//   über den Tastatur-Hook aus Atlas.IDE.Results.Peek.
// - Kopfzeile mit Titel und Tastenhinweis, bei mehreren Zielen links eine
//   Liste (Datei:Zeile, darunter der Auszug), rechts der Ausschnitt mit
//   Zeilennummern, Syntaxfarben (TAtlasSyntax.LineTokens), Editorschrift und
//   Zoom (#445). Die Zielzeile ist hinterlegt, der Name darin hervorgehoben;
//   vor der Implementierung steht eine Trennzeile mit Datei und Zeile.
// - Klick in die Liste wählt, Doppelklick öffnet (OnOpen).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Atlas.Core.Style.Syntax,
  Atlas.Core.Editor.Peek,
  Atlas.UI.Popup.Window;

type
  TAtlasPeekWindow = class(TAtlasPopupWindow)
  private
    FView: TAtlasPeekView;
    FTokens: TArray<TAtlasTokens>;
    FTokensOf: Integer;
    FOnOpen: TNotifyEvent;
    function RowHeight: Integer;
    function HeaderHeight: Integer;
    function ListWidth: Integer;
    function EntryHeight: Integer;
    function CodeRect: TRect;
    procedure UpdatePage;
    procedure PrepareTokens;
    procedure PaintHeader;
    procedure PaintList;
    procedure PaintCode;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Übernimmt AView (gibt das vorige frei) und zeigt es an ABounds (Bildschirm).</summary>
    procedure ShowView(AView: TAtlasPeekView; const ABounds: TRect);
    /// <summary>Schließt und gibt den Zustand frei.</summary>
    procedure Dismiss;
    /// <summary>Höhe des Fensters für ALines Codezeilen in der aktuellen Schrift.</summary>
    function HeightForLines(ALines: Integer): Integer;
    /// <summary>Nach einer Änderung an View (Auswahl, Scrollen) neu zeichnen.</summary>
    procedure ViewChanged;
    /// <summary>Eintrag der Liste an der Stelle (Client); -1 außerhalb.</summary>
    function EntryAt(const APoint: TPoint): Integer;
    property View: TAtlasPeekView read FView;
    /// <summary>Doppelklick in Liste oder Ausschnitt: die gewählte Stelle öffnen.</summary>
    property OnOpen: TNotifyEvent read FOnOpen write FOnOpen;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Styled,
  Atlas.UI.Popup.Accessibility;

const
  Pad = 8;
  ListMax = 300;

{ TAtlasPeekWindow }

constructor TAtlasPeekWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTokensOf := -1;
  SetAccessible(UiaToolTipControlType, TAtlasStrings.Text(TAtlasTextId.PeekDefinitionCommand));
end;

destructor TAtlasPeekWindow.Destroy;
begin
  FreeAndNil(FView);
  inherited Destroy;
end;

procedure TAtlasPeekWindow.ShowView(AView: TAtlasPeekView; const ABounds: TRect);
begin
  if AView <> FView then
  begin
    FView.Free;
    FView := AView;
  end;
  FTokensOf := -1;
  FTokens := nil;
  ShowAt(ABounds);
  UpdatePage;
  Invalidate;
  if FView <> nil then
    Announce(FView.Title);
end;

procedure TAtlasPeekWindow.Dismiss;
begin
  HidePopup;
  FreeAndNil(FView);
  FTokens := nil;
  FTokensOf := -1;
end;

function TAtlasPeekWindow.RowHeight: Integer;
begin
  Canvas.Font.Assign(Font);
  Result := Canvas.TextHeight('Wg') + Scale(2);
end;

function TAtlasPeekWindow.HeaderHeight: Integer;
begin
  Canvas.Font.Assign(UIFont);
  Result := Canvas.TextHeight('Wg') + Scale(2 * 5);
end;

function TAtlasPeekWindow.EntryHeight: Integer;
begin
  Canvas.Font.Assign(UIFont);
  Result := 2 * Canvas.TextHeight('Wg') + Scale(8);
end;

function TAtlasPeekWindow.ListWidth: Integer;
begin
  Result := 0;
  if (FView <> nil) and (FView.Count > 1) then
    Result := Min(Scale(ListMax), ClientWidth div 3);
end;

function TAtlasPeekWindow.CodeRect: TRect;
begin
  Result := Rect(ListWidth + 1, HeaderHeight + 1, ClientWidth - 1, ClientHeight - 1);
end;

function TAtlasPeekWindow.HeightForLines(ALines: Integer): Integer;
begin
  Result := HeaderHeight + 2 + Max(1, ALines) * RowHeight;
end;

procedure TAtlasPeekWindow.UpdatePage;
begin
  if FView = nil then
    Exit;
  FView.PageRows := Max(1, CodeRect.Height div Max(1, RowHeight));
end;

procedure TAtlasPeekWindow.Resize;
begin
  inherited;
  UpdatePage;
end;

procedure TAtlasPeekWindow.ViewChanged;
begin
  UpdatePage;
  Invalidate;
  if (FView <> nil) and (FView.Count > 0) then
    Announce(ExtractFileName(FView.Current.Target.Place.FileName) + ' ' + FView.Current.Excerpt);
end;

procedure TAtlasPeekWindow.PrepareTokens;
var
  Rows: TArray<TAtlasPeekRow>;
  Lines: TArray<string>;
  Index: Integer;
begin
  if (FView = nil) or (FView.Count = 0) or (FTokensOf = FView.Selected) then
    Exit;
  Rows := FView.Current.Rows;
  SetLength(Lines, Length(Rows));
  for Index := 0 to High(Rows) do
    Lines[Index] := Rows[Index].Text;
  FTokens := TAtlasSyntax.LineTokens(Lines);
  FTokensOf := FView.Selected;
end;

function TAtlasPeekWindow.EntryAt(const APoint: TPoint): Integer;
begin
  Result := -1;
  if (FView = nil) or (ListWidth = 0) or (APoint.X >= ListWidth) or (APoint.Y < HeaderHeight) then
    Exit;
  Result := (APoint.Y - HeaderHeight) div EntryHeight;
  if Result >= FView.Count then
    Result := -1;
end;

procedure TAtlasPeekWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  Index := EntryAt(Point(X, Y));
  if (Index >= 0) and (Index <> FView.Selected) then
  begin
    FView.Select(Index);
    ViewChanged;
  end;
end;

procedure TAtlasPeekWindow.DblClick;
begin
  inherited;
  if Assigned(FOnOpen) and (FView <> nil) and (FView.Count > 0) then
    FOnOpen(Self);
end;

procedure TAtlasPeekWindow.PaintHeader;
var
  Area: TRect;
  KeysHint: string;
  HintWidth: Integer;
begin
  Area := Rect(0, 0, ClientWidth, HeaderHeight);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Gutter);
  Canvas.FillRect(Area);
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(0, Area.Bottom);
  Canvas.LineTo(ClientWidth, Area.Bottom);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(UIFont);
  KeysHint := TAtlasStrings.Text(TAtlasTextId.PeekKeysHint);
  Canvas.Font.Color := ToColor(Colors.Muted);
  HintWidth := Canvas.TextWidth(KeysHint);
  Area.Inflate(-Scale(Pad), 0);
  if HintWidth < Area.Width div 2 then
  begin
    DrawText(Canvas.Handle, PChar(KeysHint), Length(KeysHint), Area,
      DT_RIGHT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    Dec(Area.Right, HintWidth + Scale(Pad));
  end;
  Canvas.Font.Color := ToColor(Colors.Text);
  Canvas.Font.Style := [fsBold];
  if FView <> nil then
    DrawText(Canvas.Handle, PChar(FView.Title), Length(FView.Title), Area,
      DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  Canvas.Font.Style := [];
end;

procedure TAtlasPeekWindow.PaintList;
var
  Width, Height, Index, Top, Half: Integer;
  Area, Line: TRect;
  Entry: TAtlasPeekEntry;
  Place: string;
begin
  Width := ListWidth;
  if Width = 0 then
    Exit;
  Height := EntryHeight;
  Area := Rect(0, HeaderHeight + 1, Width, ClientHeight);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Gutter);
  Canvas.FillRect(Area);
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(Width, Area.Top);
  Canvas.LineTo(Width, ClientHeight);
  Canvas.Font.Assign(UIFont);
  Half := Canvas.TextHeight('Wg');
  // Die gewählte Zeile bleibt sichtbar: bei langen Listen weiterschieben.
  Top := 0;
  if (FView.Selected + 1) * Height > Area.Height then
    Top := FView.Selected - Area.Height div Height + 1;
  for Index := Top to FView.Count - 1 do
  begin
    Line := Rect(0, Area.Top + (Index - Top) * Height, Width, Area.Top + (Index - Top + 1) * Height);
    if Line.Top >= ClientHeight then
      Break;
    Entry := FView.Entry(Index);
    if Index = FView.Selected then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(Colors.Selection);
      Canvas.FillRect(Line);
    end;
    Canvas.Brush.Style := bsClear;
    Line.Inflate(-Scale(Pad), 0);
    Place := Format('%s:%d', [ExtractFileName(Entry.Target.Place.FileName), Entry.Target.Place.Line + 1]);
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.Font.Style := [fsBold];
    Line.Top := Line.Top + Scale(4);
    Line.Bottom := Line.Top + Half;
    DrawText(Canvas.Handle, PChar(Place), Length(Place), Line,
      DT_LEFT or DT_TOP or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
    Canvas.Font.Style := [];
    Canvas.Font.Color := ToColor(Colors.Muted);
    Line.Offset(0, Half);
    DrawText(Canvas.Handle, PChar(Entry.Excerpt), Length(Entry.Excerpt), Line,
      DT_LEFT or DT_TOP or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  end;
end;

procedure TAtlasPeekWindow.PaintCode;
var
  Area, Row, Number: TRect;
  Rows: TArray<TAtlasPeekRow>;
  Height, Index, Gutter, X, Thumb, ThumbTop: Integer;
  Styled: TAtlasStyledText;
  Value: string;
begin
  Area := CodeRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(Area);
  if (FView = nil) or (FView.Count = 0) then
    Exit;
  PrepareTokens;
  Rows := FView.Current.Rows;
  Height := RowHeight;
  Canvas.Font.Assign(Font);
  Gutter := Canvas.TextWidth('99999') + Scale(Pad);
  for Index := FView.Top to Min(High(Rows), FView.Top + FView.PageRows - 1) do
  begin
    Row := Rect(Area.Left, Area.Top + (Index - FView.Top) * Height, Area.Right, Area.Top + (Index - FView.Top + 1) *
      Height);
    if Rows[Index].Target then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(Colors.Selection);
      Canvas.FillRect(Row);
    end;
    Canvas.Brush.Style := bsClear;
    if Rows[Index].Kind = TAtlasPeekRowKind.Separator then
    begin
      Canvas.Pen.Color := ToColor(Colors.Line);
      Canvas.MoveTo(Row.Left + Scale(Pad), Row.CenterPoint.Y);
      Canvas.LineTo(Row.Right - Scale(Pad), Row.CenterPoint.Y);
      Canvas.Font.Assign(UIFont);
      Canvas.Font.Color := ToColor(Colors.Muted);
      Value := ' ' + TAtlasStrings.Fmt(TAtlasTextId.PeekImplementation,
        [ExtractFileName(Rows[Index].FileName), Rows[Index].Line + 1]) + ' ';
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(Colors.Surface);
      Number := Rect(Row.Left + Gutter, Row.Top, Row.Left + Gutter + Canvas.TextWidth(Value), Row.Bottom);
      DrawText(Canvas.Handle, PChar(Value), Length(Value), Number, DT_LEFT or DT_VCENTER or DT_SINGLELINE or
        DT_NOPREFIX);
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Assign(Font);
      Continue;
    end;
    // Zeilennummer, 1-basiert wie im Editor.
    Canvas.Font.Assign(Font);
    Canvas.Font.Color := ToColor(Colors.Muted);
    Number := Rect(Row.Left, Row.Top, Row.Left + Gutter - Scale(Pad div 2), Row.Bottom);
    Value := IntToStr(Rows[Index].Line + 1);
    DrawText(Canvas.Handle, PChar(Value), Length(Value), Number, DT_RIGHT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    Styled := TAtlasStyledText.Create(Rows[Index].Text);
    if Index <= High(FTokens) then
      Styled.Tokens := FTokens[Index];
    Styled.MutedRanges := nil;
    Styled.ActiveStart := Rows[Index].NameStart;
    Styled.ActiveStop := Rows[Index].NameStop;
    Styled.ActiveFill := True;
    X := Row.Left + Gutter;
    Canvas.Font.Assign(Font);
    Canvas.Font.Color := ToColor(Colors.Text);
    Styled.Draw(Canvas, Colors, 0, Length(Styled.Text), X, Row, False, Scale(3));
  end;
  // Lage im Ausschnitt, wenn er länger ist als das Fenster.
  if Length(Rows) > FView.PageRows then
  begin
    Thumb := Max(Scale(12), Area.Height * FView.PageRows div Length(Rows));
    ThumbTop := Area.Top + (Area.Height - Thumb) * FView.Top div Max(1, FView.MaxTop);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(TAtlasColorMath.Mix(Colors.Muted, Colors.Surface, AtlasMixThumb));
    Canvas.FillRect(Rect(Area.Right - Scale(4), ThumbTop, Area.Right - Scale(1), ThumbTop + Thumb));
  end;
end;

procedure TAtlasPeekWindow.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  PaintHeader;
  PaintList;
  PaintCode;
  PaintBorder;
end;

end.
