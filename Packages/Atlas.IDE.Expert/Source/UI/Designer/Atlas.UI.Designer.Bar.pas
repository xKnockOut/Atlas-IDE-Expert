unit Atlas.UI.Designer.Bar;

// Designer-Leiste (#1442), Darstellung: eine Zeile über dem Formular-Designer
// an Stelle von Brotkrumen und Editorleiste. Von links:
// - Suchfeld (TAtlasSearchEdit, behält Bearbeitungstasten wie Entf und Strg+V,
//   sonst löschte der Designer die gewählte Komponente). Jede Änderung meldet
//   OnSearch; Enter bzw. ↓ den nächsten Treffer (OnStep +1), Umschalt+Enter
//   bzw. ↑ den vorigen, Esc leert das Feld.
// - „‹ 2/5 ›“: voriger und nächster Treffer, dazwischen der Zähler bzw.
//   „kein Treffer“. Nur mit Suchwort.
// - „Ausblenden ▾“ öffnet das Menü des Aufrufers (OnHideMenu, Punkt unter dem
//   Knopf), „Alle einblenden (3)“ nur, solange etwas ausgeblendet ist
//   (OnShowAll).
// Höhe, Farben, Hervorhebung, Klick beim Loslassen, Kontextmenü (geht nie an
// den Editor) und OnDisabled kommen vom Vorfahr TAtlasEditorBar (#1248).
// Reine VCL; gesucht, ausgewählt und ausgeblendet wird vom Aufrufer
// (Atlas.IDE.Designer.Bar).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Style.Palette,
  Atlas.UI.Editor.Bar,
  Atlas.UI.Search.Bar;

type
  TAtlasDesignerBar = class(TAtlasEditorBar)
  public const
    PartPrevious = 1;
    PartNext = 2;
    PartHide = 3;
    PartShowAll = 4;
    /// <summary>Breite des Suchfelds bei 96 DPI.</summary>
    SearchWidth = 180;
  private
    FSearch: TAtlasSearchEdit;
    FHitIndex: Integer;
    FHitCount: Integer;
    FHiddenCount: Integer;
    FHitsText: string;
    FNoHitText: string;
    FHideText: string;
    FShowAllText: string;
    FPreviousHint: string;
    FNextHint: string;
    FHiddenHint: string;
    FRects: array[PartPrevious..PartShowAll] of TRect;
    FCounterRect: TRect;
    FOnSearch: TProc<string>;
    FOnStep: TProc<Integer>;
    FOnHideMenu: TProc<TPoint>;
    FOnShowAll: TProc;
    procedure SearchChange(Sender: TObject);
    procedure SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SearchKeyPress(Sender: TObject; var Key: Char);
    procedure Layout;
    function TextWidth(const AText: string): Integer;
    function CounterText: string;
    function ShowAllCaption: string;
    procedure DrawPart(APart: Integer; const AText: string; AEnabled: Boolean);
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
  protected
    function PartAt(X, Y: Integer): Integer; override;
    function PartHint(APart: Integer): string; override;
    function PartEnabled(APart: Integer): Boolean; override;
    procedure PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer); override;
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Farben der Leiste und des Suchfelds.</summary>
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Treffer der Suche: AIndex 0-basiert (-1 = keiner gewählt), ACount Zahl der Treffer.</summary>
    procedure SetHits(AIndex, ACount: Integer);
    /// <summary>Zahl der ausgeblendeten Komponenten; 0 = Knopf „Alle einblenden“ fehlt.</summary>
    procedure SetHiddenCount(ACount: Integer);
    /// <summary>Texte in der Sprache der Oberfläche; AHits mit zwei %d (Nummer, Zahl), AShowAll mit einem.</summary>
    procedure SetTexts(const ASearchHint, AHits, ANoHit, AHide, AShowAll, APreviousHint, ANextHint,
      AHiddenHint: string);
    /// <summary>Fläche eines Teils (Client); leer, wenn er gerade fehlt.</summary>
    function PartRect(APart: Integer): TRect;
    /// <summary>Suchfeld fokussieren und den Text markieren.</summary>
    procedure FocusSearch;
    /// <summary>Klick wie mit der linken Maustaste (Tests).</summary>
    procedure ClickAt(X, Y: Integer);
    property Search: TAtlasSearchEdit read FSearch;
    property HitIndex: Integer read FHitIndex;
    property HitCount: Integer read FHitCount;
    property HiddenCount: Integer read FHiddenCount;
    property OnSearch: TProc<string> read FOnSearch write FOnSearch;
    /// <summary>+1 nächster, -1 voriger Treffer.</summary>
    property OnStep: TProc<Integer> read FOnStep write FOnStep;
    /// <summary>Menü „Ausblenden“ an diesem Bildschirmpunkt öffnen.</summary>
    property OnHideMenu: TProc<TPoint> read FOnHideMenu write FOnHideMenu;
    property OnShowAll: TProc read FOnShowAll write FOnShowAll;
  end;

implementation

uses
  System.Math,
  Vcl.StdCtrls,
  Vcl.Forms;

{ TAtlasDesignerBar }

constructor TAtlasDesignerBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHitIndex := -1;
  FHitsText := '%d/%d';
  FNoHitText := '–';
  FHideText := '▾';
  FShowAllText := '(%d)';
  FSearch := TAtlasSearchEdit.Create(Self);
  FSearch.Parent := Self;
  FSearch.AutoSize := False;
  FSearch.BorderStyle := bsNone;
  FSearch.OnChange := SearchChange;
  FSearch.OnKeyDown := SearchKeyDown;
  FSearch.OnKeyPress := SearchKeyPress;
  Layout;
end;

procedure TAtlasDesignerBar.ApplyColors(const AColors: TAtlasColors);
begin
  SetColors(AColors);
  FSearch.Color := TColor(AColors.Surface);
  FSearch.Font.Color := TColor(AColors.Text);
end;

procedure TAtlasDesignerBar.SetTexts(const ASearchHint, AHits, ANoHit, AHide, AShowAll, APreviousHint, ANextHint,
  AHiddenHint: string);
begin
  FSearch.TextHint := ASearchHint;
  FHitsText := AHits;
  FNoHitText := ANoHit;
  FHideText := AHide;
  FShowAllText := AShowAll;
  FPreviousHint := APreviousHint;
  FNextHint := ANextHint;
  FHiddenHint := AHiddenHint;
  Layout;
  Invalidate;
end;

procedure TAtlasDesignerBar.SetHits(AIndex, ACount: Integer);
begin
  if (AIndex = FHitIndex) and (ACount = FHitCount) then
    Exit;
  FHitIndex := AIndex;
  FHitCount := ACount;
  Layout;
  Invalidate;
end;

procedure TAtlasDesignerBar.SetHiddenCount(ACount: Integer);
begin
  if ACount = FHiddenCount then
    Exit;
  FHiddenCount := ACount;
  Layout;
  Invalidate;
end;

function TAtlasDesignerBar.CounterText: string;
begin
  if FHitCount = 0 then
    Result := FNoHitText
  else
    Result := Format(FHitsText, [FHitIndex + 1, FHitCount]);
end;

function TAtlasDesignerBar.ShowAllCaption: string;
begin
  Result := Format(FShowAllText, [FHiddenCount]);
end;

function TAtlasDesignerBar.TextWidth(const AText: string): Integer;
begin
  // Ohne Fenster kein Canvas: grob schätzen, gezeichnet wird ohnehin erst mit Fenster.
  if not HandleAllocated then
    Exit(Length(AText) * Scale(7));
  Canvas.Font := Font;
  Result := Canvas.TextWidth(AText);
end;

procedure TAtlasDesignerBar.Layout;
var
  mLeft, mGap, mPad, mIndex: Integer;
begin
  mGap := Scale(6);
  mPad := Scale(6);
  mLeft := Scale(4);
  FSearch.SetBounds(mLeft, Scale(3), Scale(SearchWidth), Max(ClientHeight - Scale(6), Scale(14)));
  mLeft := mLeft + FSearch.Width + mGap;
  for mIndex := Low(FRects) to High(FRects) do
    FRects[mIndex] := TRect.Empty;
  FCounterRect := TRect.Empty;
  if Trim(FSearch.Text) <> '' then
  begin
    FRects[PartPrevious] := Rect(mLeft, 0, mLeft + TextWidth('‹') + 2 * mPad, ClientHeight);
    mLeft := FRects[PartPrevious].Right;
    FCounterRect := Rect(mLeft, 0, mLeft + TextWidth(CounterText) + mPad, ClientHeight);
    mLeft := FCounterRect.Right;
    FRects[PartNext] := Rect(mLeft, 0, mLeft + TextWidth('›') + 2 * mPad, ClientHeight);
    mLeft := FRects[PartNext].Right + mGap;
  end;
  FRects[PartHide] := Rect(mLeft, 0, mLeft + TextWidth(FHideText) + 2 * mPad, ClientHeight);
  mLeft := FRects[PartHide].Right + mGap;
  if FHiddenCount > 0 then
    FRects[PartShowAll] := Rect(mLeft, 0, mLeft + TextWidth(ShowAllCaption) + 2 * mPad, ClientHeight);
end;

function TAtlasDesignerBar.PartRect(APart: Integer): TRect;
begin
  if (APart < Low(FRects)) or (APart > High(FRects)) then
    Exit(TRect.Empty);
  Result := FRects[APart];
end;

procedure TAtlasDesignerBar.Resize;
begin
  inherited Resize;
  Layout;
end;

procedure TAtlasDesignerBar.CMFontChanged(var Message: TMessage);
begin
  inherited;
  Layout;
  Invalidate;
end;

procedure TAtlasDesignerBar.DrawPart(APart: Integer; const AText: string; AEnabled: Boolean);
var
  mRect: TRect;
begin
  mRect := FRects[APart];
  if mRect.IsEmpty then
    Exit;
  if AEnabled and (Hot = APart) then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := TColor(Colors.Selection);
    Canvas.FillRect(Rect(mRect.Left, Scale(2), mRect.Right, ClientHeight - Scale(2)));
  end;
  Canvas.Brush.Style := bsClear;
  if AEnabled then
    Canvas.Font.Color := TColor(Colors.Text)
  else
    Canvas.Font.Color := TColor(Colors.Muted);
  DrawText(Canvas.Handle, PChar(AText), -1, mRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

procedure TAtlasDesignerBar.Paint;
var
  mRect: TRect;
begin
  Layout;
  PaintChrome(False);
  Canvas.Font := Font;
  DrawPart(PartPrevious, '‹', FHitCount > 1);
  if not FCounterRect.IsEmpty then
  begin
    mRect := FCounterRect;
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := TColor(Colors.Muted);
    DrawText(Canvas.Handle, PChar(CounterText), -1, mRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  end;
  DrawPart(PartNext, '›', FHitCount > 1);
  DrawPart(PartHide, FHideText, True);
  DrawPart(PartShowAll, ShowAllCaption, True);
end;

function TAtlasDesignerBar.PartAt(X, Y: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := Low(FRects) to High(FRects) do
    if not FRects[mIndex].IsEmpty and PtInRect(FRects[mIndex], Point(X, Y)) then
      Exit(mIndex);
  Result := PartNone;
end;

function TAtlasDesignerBar.PartHint(APart: Integer): string;
begin
  case APart of
    PartPrevious:
      Result := FPreviousHint;
    PartNext:
      Result := FNextHint;
    PartHide, PartShowAll:
      Result := FHiddenHint;
  else
    Result := '';
  end;
end;

function TAtlasDesignerBar.PartEnabled(APart: Integer): Boolean;
begin
  case APart of
    PartPrevious, PartNext:
      Result := FHitCount > 1;
    PartHide:
      Result := True;
    PartShowAll:
      Result := FHiddenCount > 0;
  else
    Result := False;
  end;
end;

procedure TAtlasDesignerBar.PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer);
var
  mPoint: TPoint;
begin
  if not PartEnabled(APart) then
    Exit;
  case APart of
    PartPrevious:
      if Assigned(FOnStep) then
        FOnStep(-1);
    PartNext:
      if Assigned(FOnStep) then
        FOnStep(1);
    PartHide:
      if Assigned(FOnHideMenu) then
      begin
        mPoint := ClientToScreen(Point(FRects[PartHide].Left, ClientHeight));
        FOnHideMenu(mPoint);
      end;
    PartShowAll:
      if Assigned(FOnShowAll) then
        FOnShowAll();
  else
    // Übrige Teile bewusst ohne Wirkung.
  end;
end;

procedure TAtlasDesignerBar.SearchChange(Sender: TObject);
begin
  Layout;
  Invalidate;
  if Assigned(FOnSearch) then
    FOnSearch(Trim(FSearch.Text));
end;

procedure TAtlasDesignerBar.SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mDelta: Integer;
begin
  mDelta := 0;
  case Key of
    VK_RETURN:
      if ssShift in Shift then
        mDelta := -1
      else
        mDelta := 1;
    VK_DOWN:
      mDelta := 1;
    VK_UP:
      mDelta := -1;
    VK_ESCAPE:
      begin
        Key := 0;
        FSearch.Text := '';
        Exit;
      end;
  else
    Exit;
  end;
  Key := 0;
  if Assigned(FOnStep) then
    FOnStep(mDelta);
end;

procedure TAtlasDesignerBar.SearchKeyPress(Sender: TObject; var Key: Char);
begin
  // Kein Signalton bei Enter und Esc.
  if (Key = #13) or (Key = #27) then
    Key := #0;
end;

procedure TAtlasDesignerBar.ClickAt(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
  MouseUp(mbLeft, [], X, Y);
end;

procedure TAtlasDesignerBar.FocusSearch;
var
  mForm: TCustomForm;
begin
  mForm := GetParentForm(Self);
  // Nur mit sichtbarer Form: CanFocus allein lässt eine verborgene durch.
  if FSearch.CanFocus and FSearch.Showing and (mForm <> nil) and mForm.Visible then
  begin
    FSearch.SetFocus;
    FSearch.SelectAll;
  end;
end;

end.
