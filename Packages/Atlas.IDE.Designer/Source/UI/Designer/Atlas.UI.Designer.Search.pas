unit Atlas.UI.Designer.Search;

// Fenster „Komponenten suchen“ (#1442) für das Formular im Designer, im Stil
// von „Units suchen“ (#777): Akzentrahmen, runde Ecken, Farben aus
// TAtlasColors. Zwei Arten (editor.designerBar.searchStyle):
// - Groß (Vorgabe): nicht modal, verschieb- und vergrößerbar.
//     Kopf:     Suchfeld, rechts Hierarchie / Klasse / Flach.
//     Chips:    Art (Alle, Steuerelemente, Nichtvisuelle, Container) und
//               Suche in (Name, Caption, Klasse).
//     Liste:    selbst gezeichnet, zwei Zeilen je Komponente (Name mit
//               Treffer und Caption; Klasse und Elternelement), Gruppenköpfe
//               mit Trefferzahl.
//     Vorschau: Lage im Formular als kleine Karte mit hervorgehobener
//               Komponente, Position und Größe, Eigenschaften, Ereignisse (F4).
//     Aktionen: Im Designer auswählen, Zum Ereignis, Name kopieren; Fußzeile
//               mit Tasten und „n von m“.
// - Klein wie Strg+P: nur Suchfeld und einzeilige, flache Liste; schließt,
//   sobald es den Fokus verliert.
// Was die Aktionen in der IDE tun, entscheidet Atlas.IDE.Designer.Bar
// (OnAction); Name kopieren erledigt das Fenster selbst.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Designer.Components;

type
{$SCOPEDENUMS ON}
  TAtlasComponentSearchAction = (Select, Event, CopyName);
{$SCOPEDENUMS OFF}

  TAtlasComponentSearchOptions = record
    /// <summary>Klein wie Strg+P statt groß mit Filtern und Vorschau.</summary>
    Compact: Boolean;
    /// <summary>Name des Formulars: Titel und Gruppe der Komponenten direkt darauf.</summary>
    FormName: string;
    /// <summary>Client des Formulars für die Karte der Vorschau.</summary>
    FormBounds: TRect;
    Kind: TAtlasDesignerKind;
    Fields: TAtlasDesignerFields;
    Grouping: TAtlasDesignerGrouping;
    Preview: Boolean;
    /// <summary>Gemerkte Lage des großen Fensters (Bildschirm); leer = mittig.</summary>
    Bounds: TRect;
    /// <summary>Komponente, die zuerst gewählt ist (Auswahl im Designer); '' = die erste.</summary>
    Current: string;
  end;

  TAtlasComponentSearchActionEvent = reference to procedure(AAction: TAtlasComponentSearchAction;
    const AItem: TAtlasDesignerItem);

  TAtlasComponentSearchWindow = class(TForm)
  private type
    THit = (None, Chip, Grouping, Row, Action);
    THitArea = record
      Kind: THit;
      Rect: TRect;
      Value: Integer;
    end;
    /// <summary>Höhen der Bereiche in Pixeln (skaliert).</summary>
    TMetrics = record
      Header: Integer;
      Chips: Integer;
      Group: Integer;
      Entry: Integer;
      Actions: Integer;
      Footer: Integer;
    end;
    /// <summary>Suche und Liste: Suchwort, Filter, Treffer, Zeilen, Auswahl und Bildlauf.</summary>
    TState = record
      Pattern: string;
      Kind: TAtlasDesignerKind;
      Fields: TAtlasDesignerFields;
      Grouping: TAtlasDesignerGrouping;
      PreviewVisible: Boolean;
      Hits: TArray<Integer>;
      Rows: TArray<TAtlasDesignerRow>;
      /// <summary>Oberkante je Zeile in der Liste; ein Eintrag mehr als Rows (Gesamthöhe).</summary>
      RowTops: TArray<Integer>;
      Selected: Integer;
      Scroll: Integer;
      procedure Rebuild(const AItems: TArray<TAtlasDesignerItem>; const AFormName: string;
        const AMetrics: TMetrics);
      procedure SelectFirstItem;
      procedure SelectName(const AItems: TArray<TAtlasDesignerItem>; const AName: string);
      function SelectedItem: Integer;
      function SelectedName(const AItems: TArray<TAtlasDesignerItem>): string;
      function ActionEnabled(const AItems: TArray<TAtlasDesignerItem>; AAction: TAtlasComponentSearchAction): Boolean;
      procedure Move(ADelta: Integer);
      procedure Reveal(AVisible: Integer);
      procedure ScrollBy(ADelta, AVisible: Integer);
    end;
    /// <summary>Rückrufe und Schließzustand.</summary>
    THooks = record
      OnAction: TAtlasComponentSearchActionEvent;
      OnClosed: TProc;
      Closing: Boolean;
    end;
    /// <summary>Zeichnet das Fenster und merkt sich, wo Chips, Zeilen und Aktionen liegen.</summary>
    TPainter = class
    private
      FWindow: TAtlasComponentSearchWindow;
      FColors: TAtlasColors;
      FUIFont: TFont;
      FSmallFont: TFont;
      FAreas: TList<THitArea>;
      FListRect: TRect;
      FPreviewRect: TRect;
      function Canvas: TCanvas;
      function S(AValue: Integer): Integer;
      procedure AddArea(AKind: THit; const ARect: TRect; AValue: Integer);
      procedure DrawChip(var X: Integer; Y: Integer; const ACaption: string; AOn: Boolean; AValue: Integer);
      function DrawGroupings: Integer;
      procedure DrawHeader;
      procedure DrawChips;
      procedure DrawList;
      procedure DrawRow(ARow: Integer; const ARect: TRect);
      procedure DrawCompactRow(const AItem: TAtlasDesignerItem; const APart: TRect);
      procedure DrawFullRow(const AItem: TAtlasDesignerItem; const ARect, APart: TRect);
      function DrawHighlighted(const AText: string; const ARect: TRect; ABase: TAtlasColor; AMatch: Boolean): Integer;
      procedure DrawPreview;
      procedure PreviewHead(const ACaption: string; const AArea: TRect; var ATop: Integer);
      procedure PreviewLine(const AText: string; AColor: TAtlasColor; const AArea: TRect; var ATop: Integer);
      procedure PreviewPlace(const AItem: TAtlasDesignerItem; const AArea: TRect; var ATop: Integer);
      procedure PreviewDetails(const AItem: TAtlasDesignerItem; const AArea: TRect; var ATop: Integer);
      procedure DrawMap(const AArea: TRect; const AItem: TAtlasDesignerItem);
      procedure DrawActions;
      procedure DrawFooter;
    public
      constructor Create(AWindow: TAtlasComponentSearchWindow; const AColors: TAtlasColors);
      destructor Destroy; override;
      function Metrics: TMetrics;
      procedure Layout;
      procedure Paint;
      function HitAt(X, Y: Integer; out AArea: THitArea): Boolean;
      function RowAt(Y: Integer): Integer;
      property Colors: TAtlasColors read FColors;
      property ListRect: TRect read FListRect;
      property UIFont: TFont read FUIFont;
    end;
  private const
    ChipKinds = 0;
    ChipFields = 100;
  private
    FOptions: TAtlasComponentSearchOptions;
    FItems: TArray<TAtlasDesignerItem>;
    FState: TState;
    FHooks: THooks;
    FPainter: TPainter;
    procedure Refilter(const AKeep: string);
    procedure EnsureVisible;
    function EditKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormDeactivate(Sender: TObject);
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure CreateWnd; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor CreateSearch(AOwner: TComponent; const AOptions: TAtlasComponentSearchOptions;
      const AItems: TArray<TAtlasDesignerItem>; const AColors: TAtlasColors);
    destructor Destroy; override;
    /// <summary>Zeigen: gemerkte Lage oder über AArea (Arbeitsfläche des Monitors).</summary>
    procedure ShowOver(const AArea: TRect);
    /// <summary>Suchwort setzen wie getippt (Tests).</summary>
    procedure SetPattern(const APattern: string);
    procedure SetKind(AKind: TAtlasDesignerKind);
    procedure SetFields(AFields: TAtlasDesignerFields);
    procedure SetGrouping(AGrouping: TAtlasDesignerGrouping);
    /// <summary>Gewählte Zeile um ADelta verschieben; Gruppenköpfe werden übersprungen.</summary>
    procedure MoveSelection(ADelta: Integer);
    /// <summary>Aktion für die gewählte Komponente; Auswählen und Zum Ereignis schließen das Fenster.</summary>
    procedure Run(AAction: TAtlasComponentSearchAction);
    /// <summary>Index der gewählten Komponente in den Einträgen; -1 ohne.</summary>
    function SelectedItem: Integer;
    property Rows: TArray<TAtlasDesignerRow> read FState.Rows;
    property Hits: TArray<Integer> read FState.Hits;
    property Kind: TAtlasDesignerKind read FState.Kind;
    property Fields: TAtlasDesignerFields read FState.Fields;
    property Grouping: TAtlasDesignerGrouping read FState.Grouping;
    property PreviewVisible: Boolean read FState.PreviewVisible;
    property OnAction: TAtlasComponentSearchActionEvent read FHooks.OnAction write FHooks.OnAction;
    /// <summary>Nach dem Schließen; das Fenster gibt sich selbst frei.</summary>
    property OnClosed: TProc read FHooks.OnClosed write FHooks.OnClosed;
  end;

implementation

uses
  System.Math,
  Winapi.Dwmapi,
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.UI.Designer.Strings;

const
  // Ab Windows 11; ältere Systeme ignorieren die Attribute.
  CornerPreference = 33;
  RoundCorners = 2;
  BorderColorAttribute = 34;
  CompactRows = 12;

function C(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

function KindCaption(AKind: TAtlasDesignerKind): string;
begin
  case AKind of
    TAtlasDesignerKind.Controls: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchKindControls);
    TAtlasDesignerKind.NonVisual: Result := TAtlasDesignerStrings.Text(
      TAtlasDesignerTextId.DesignerSearchKindNonVisual);
    TAtlasDesignerKind.Containers: Result := TAtlasDesignerStrings.Text(
      TAtlasDesignerTextId.DesignerSearchKindContainers);
  else
    Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchKindAll);
  end;
end;

function FieldCaption(AField: TAtlasDesignerField): string;
begin
  case AField of
    TAtlasDesignerField.Caption: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchFieldCaption);
    TAtlasDesignerField.ClassName: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchFieldClass);
  else
    Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchFieldName);
  end;
end;

function GroupingCaption(AGrouping: TAtlasDesignerGrouping): string;
begin
  case AGrouping of
    TAtlasDesignerGrouping.ClassName: Result := TAtlasDesignerStrings.Text(
      TAtlasDesignerTextId.DesignerSearchGroupClass);
    TAtlasDesignerGrouping.Flat: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchGroupFlat);
  else
    Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchGroupHierarchy);
  end;
end;

function ActionCaption(AAction: TAtlasComponentSearchAction): string;
begin
  case AAction of
    TAtlasComponentSearchAction.Event: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchEvent);
    TAtlasComponentSearchAction.CopyName: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchCopy);
  else
    Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchSelect);
  end;
end;

/// <summary>Randzone von AClient unter APoint (HTLEFT … HTBOTTOMRIGHT); HTNOWHERE innen.</summary>
function EdgeHit(const APoint: TPoint; const AClient: TRect; AEdge: Integer): Integer;
var
  mTop, mBottom, mLeft, mRight: Boolean;
begin
  mTop := APoint.Y < AEdge;
  mBottom := APoint.Y >= AClient.Bottom - AEdge;
  mLeft := APoint.X < AEdge;
  mRight := APoint.X >= AClient.Right - AEdge;
  Result := HTNOWHERE;
  if mTop then
  begin
    Result := HTTOP;
    if mLeft then
    begin
      Result := HTTOPLEFT;
    end
    else if mRight then
    begin
      Result := HTTOPRIGHT;
    end;
  end
  else if mBottom then
  begin
    Result := HTBOTTOM;
    if mLeft then
    begin
      Result := HTBOTTOMLEFT;
    end
    else if mRight then
    begin
      Result := HTBOTTOMRIGHT;
    end;
  end
  else if mLeft then
  begin
    Result := HTLEFT;
  end
  else if mRight then
  begin
    Result := HTRIGHT;
  end;
end;

{ TAtlasComponentSearchWindow.TState }

procedure TAtlasComponentSearchWindow.TState.Rebuild(const AItems: TArray<TAtlasDesignerItem>;
  const AFormName: string; const AMetrics: TMetrics);
var
  mRow, mTop: Integer;
begin
  Rows := TAtlasDesignerGroups.Rows(AItems, Hits, Grouping, AFormName);
  SetLength(RowTops, Length(Rows) + 1);
  mTop := 0;
  for mRow := 0 to High(Rows) do
  begin
    RowTops[mRow] := mTop;
    if Rows[mRow].Header then
    begin
      Inc(mTop, AMetrics.Group);
    end
    else
    begin
      Inc(mTop, AMetrics.Entry);
    end;
  end;
  RowTops[Length(Rows)] := mTop;
end;

procedure TAtlasComponentSearchWindow.TState.SelectFirstItem;
var
  mRow: Integer;
begin
  Selected := -1;
  for mRow := 0 to High(Rows) do
  begin
    if not Rows[mRow].Header then
    begin
      Selected := mRow;
      Break;
    end;
  end;
end;

procedure TAtlasComponentSearchWindow.TState.SelectName(const AItems: TArray<TAtlasDesignerItem>;
  const AName: string);
var
  mRow: Integer;
begin
  Selected := -1;
  if AName = '' then
  begin
    Exit;
  end;
  for mRow := 0 to High(Rows) do
  begin
    if not Rows[mRow].Header and SameText(AItems[Rows[mRow].Item].Name, AName) then
    begin
      Selected := mRow;
      Break;
    end;
  end;
end;

function TAtlasComponentSearchWindow.TState.SelectedItem: Integer;
begin
  Result := -1;
  if (Selected >= 0) and (Selected <= High(Rows)) and not Rows[Selected].Header then
  begin
    Result := Rows[Selected].Item;
  end;
end;

function TAtlasComponentSearchWindow.TState.SelectedName(const AItems: TArray<TAtlasDesignerItem>): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := SelectedItem;
  if mIndex >= 0 then
  begin
    Result := AItems[mIndex].Name;
  end;
end;

function TAtlasComponentSearchWindow.TState.ActionEnabled(const AItems: TArray<TAtlasDesignerItem>;
  AAction: TAtlasComponentSearchAction): Boolean;
var
  mIndex: Integer;
begin
  mIndex := SelectedItem;
  Result := mIndex >= 0;
  if Result and (AAction = TAtlasComponentSearchAction.Event) then
  begin
    Result := Length(AItems[mIndex].Events) > 0;
  end;
end;

procedure TAtlasComponentSearchWindow.TState.Move(ADelta: Integer);
var
  mRow, mStep, mCount: Integer;
begin
  mStep := Sign(ADelta);
  if (Length(Rows) = 0) or (mStep = 0) then
  begin
    Exit;
  end;
  mRow := Selected;
  // Um |ADelta| Komponenten weiter, Köpfe zählen nicht; am Rand stehen bleiben.
  for mCount := 1 to Abs(ADelta) do
  begin
    repeat
      mRow := mRow + mStep;
    until (mRow < 0) or (mRow > High(Rows)) or not Rows[mRow].Header;
    if (mRow < 0) or (mRow > High(Rows)) then
    begin
      Break;
    end;
    Selected := mRow;
  end;
end;

procedure TAtlasComponentSearchWindow.TState.Reveal(AVisible: Integer);
begin
  if (Selected < 0) or (Selected > High(Rows)) then
  begin
    Exit;
  end;
  // Kopf der eigenen Gruppe mit zeigen.
  if (Selected > 0) and Rows[Selected - 1].Header and (RowTops[Selected - 1] < Scroll) then
  begin
    Scroll := RowTops[Selected - 1];
  end
  else if RowTops[Selected] < Scroll then
  begin
    Scroll := RowTops[Selected];
  end
  else if RowTops[Selected + 1] > Scroll + AVisible then
  begin
    Scroll := RowTops[Selected + 1] - AVisible;
  end;
  Scroll := EnsureRange(Scroll, 0, Max(0, RowTops[Length(Rows)] - AVisible));
end;

procedure TAtlasComponentSearchWindow.TState.ScrollBy(ADelta, AVisible: Integer);
begin
  Scroll := EnsureRange(Scroll + ADelta, 0, Max(0, RowTops[Length(Rows)] - AVisible));
end;

{ TAtlasComponentSearchWindow.TPainter }

constructor TAtlasComponentSearchWindow.TPainter.Create(AWindow: TAtlasComponentSearchWindow;
  const AColors: TAtlasColors);
begin
  inherited Create;
  FWindow := AWindow;
  FColors := AColors;
  FAreas := TList<THitArea>.Create;
  FUIFont := TFont.Create;
  FUIFont.Name := 'Segoe UI';
  FUIFont.Size := 10;
  FSmallFont := TFont.Create;
  FSmallFont.Name := 'Segoe UI';
  FSmallFont.Size := 8;
end;

destructor TAtlasComponentSearchWindow.TPainter.Destroy;
begin
  FAreas.Free;
  FUIFont.Free;
  FSmallFont.Free;
  inherited Destroy;
end;

function TAtlasComponentSearchWindow.TPainter.Canvas: TCanvas;
begin
  Result := FWindow.Canvas;
end;

function TAtlasComponentSearchWindow.TPainter.S(AValue: Integer): Integer;
begin
  Result := FWindow.ScaleValue(AValue);
end;

function TAtlasComponentSearchWindow.TPainter.Metrics: TMetrics;
begin
  Result.Header := S(44);
  Result.Group := S(24);
  Result.Footer := S(24);
  if FWindow.FOptions.Compact then
  begin
    Result.Chips := 0;
    Result.Entry := S(26);
    Result.Actions := 0;
  end
  else
  begin
    Result.Chips := S(32);
    Result.Entry := S(40);
    Result.Actions := S(34);
  end;
end;

procedure TAtlasComponentSearchWindow.TPainter.AddArea(AKind: THit; const ARect: TRect; AValue: Integer);
var
  mArea: THitArea;
begin
  mArea.Kind := AKind;
  mArea.Rect := ARect;
  mArea.Value := AValue;
  FAreas.Add(mArea);
end;

procedure TAtlasComponentSearchWindow.TPainter.Layout;
var
  mBody: TRect;
  mMetrics: TMetrics;
begin
  mMetrics := Metrics;
  mBody := Rect(0, mMetrics.Header + mMetrics.Chips, FWindow.ClientWidth,
    FWindow.ClientHeight - mMetrics.Footer - mMetrics.Actions);
  FPreviewRect := TRect.Empty;
  if FWindow.FState.PreviewVisible then
  begin
    FPreviewRect := Rect(mBody.Right - Min(S(320), mBody.Width div 2), mBody.Top, mBody.Right, mBody.Bottom);
    mBody.Right := FPreviewRect.Left;
  end;
  FListRect := mBody;
end;

function TAtlasComponentSearchWindow.TPainter.DrawHighlighted(const AText: string; const ARect: TRect;
  ABase: TAtlasColor; AMatch: Boolean): Integer;
var
  mPos, mLength, mX: Integer;
  mParts: array[0..2] of string;
  mPart: Integer;
  mRect: TRect;
  mPattern: string;
begin
  mPos := 0;
  mPattern := Trim(FWindow.FState.Pattern);
  mLength := Length(mPattern);
  if AMatch and (mLength > 0) then
  begin
    mPos := Pos(LowerCase(mPattern), LowerCase(AText));
  end;
  mParts[0] := AText;
  mParts[1] := '';
  mParts[2] := '';
  if mPos > 0 then
  begin
    mParts[0] := Copy(AText, 1, mPos - 1);
    mParts[1] := Copy(AText, mPos, mLength);
    mParts[2] := Copy(AText, mPos + mLength, MaxInt);
  end;
  mX := ARect.Left;
  for mPart := 0 to 2 do
  begin
    if (mParts[mPart] = '') or (mX >= ARect.Right) then
    begin
      Continue;
    end;
    if mPart = 1 then
    begin
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := C(FColors.Accent);
    end
    else
    begin
      Canvas.Font.Style := [];
      Canvas.Font.Color := C(ABase);
    end;
    mRect := Rect(mX, ARect.Top, ARect.Right, ARect.Bottom);
    DrawText(Canvas.Handle, PChar(mParts[mPart]), -1, mRect, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
      DT_END_ELLIPSIS);
    Inc(mX, Canvas.TextWidth(mParts[mPart]));
  end;
  Canvas.Font.Style := [];
  Result := Min(mX, ARect.Right);
end;

procedure TAtlasComponentSearchWindow.TPainter.DrawChip(var X: Integer; Y: Integer; const ACaption: string;
  AOn: Boolean; AValue: Integer);
var
  mChip: TRect;
begin
  mChip := Rect(X, Y, X + Canvas.TextWidth(ACaption) + S(16), Y + S(22));
  if mChip.Right > FWindow.ClientWidth - S(10) then
  begin
    Exit;
  end;
  if AOn then
  begin
    Canvas.Brush.Color := C(FColors.AccentSoft);
    Canvas.Pen.Color := C(FColors.Accent);
    Canvas.Font.Color := C(FColors.Text);
  end
  else
  begin
    Canvas.Brush.Color := C(FColors.Surface);
    Canvas.Pen.Color := C(FColors.Line);
    Canvas.Font.Color := C(FColors.Muted);
  end;
  Canvas.RoundRect(mChip.Left, mChip.Top, mChip.Right, mChip.Bottom, S(22), S(22));
  Canvas.Brush.Style := bsClear;
  DrawText(Canvas.Handle, PChar(ACaption), -1, mChip, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
  Canvas.Brush.Style := bsSolid;
  AddArea(THit.Chip, mChip, AValue);
  X := mChip.Right + S(6);
end;

/// <summary>Umschalter Hierarchie / Klasse / Flach rechts im Kopf; liefert die Breite eines Segments.</summary>
function TAtlasComponentSearchWindow.TPainter.DrawGroupings: Integer;
var
  mSegment: TRect;
  mX, mHeader: Integer;
  mGrouping: TAtlasDesignerGrouping;
begin
  Result := 0;
  for mGrouping := Low(TAtlasDesignerGrouping) to High(TAtlasDesignerGrouping) do
  begin
    Result := Max(Result, Canvas.TextWidth(GroupingCaption(mGrouping)) + S(20));
  end;
  mHeader := Metrics.Header;
  mX := FWindow.ClientWidth - S(10) - 3 * Result;
  for mGrouping := Low(TAtlasDesignerGrouping) to High(TAtlasDesignerGrouping) do
  begin
    mSegment := Rect(mX, S(9), mX + Result, mHeader - S(9));
    if mGrouping = FWindow.FState.Grouping then
    begin
      Canvas.Brush.Color := C(FColors.Selection);
      Canvas.Font.Color := C(FColors.Text);
    end
    else
    begin
      Canvas.Brush.Color := C(FColors.Gutter);
      Canvas.Font.Color := C(FColors.Muted);
    end;
    Canvas.Pen.Color := C(FColors.Line);
    Canvas.Rectangle(mSegment);
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(GroupingCaption(mGrouping)), -1, mSegment, DT_SINGLELINE or DT_VCENTER or
      DT_CENTER or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
    AddArea(THit.Grouping, mSegment, Ord(mGrouping));
    Inc(mX, Result);
  end;
end;

procedure TAtlasComponentSearchWindow.TPainter.DrawHeader;
var
  mInput: TRect;
  mX: Integer;
  mText: string;
begin
  Canvas.Font.Assign(FUIFont);
  mX := FWindow.ClientWidth - S(10);
  if not FWindow.FOptions.Compact then
  begin
    mX := FWindow.ClientWidth - S(20) - 3 * DrawGroupings;
  end;
  mInput := Rect(S(10), S(7), mX, Metrics.Header - S(7));
  Canvas.Pen.Color := C(FColors.Accent);
  Canvas.Brush.Color := C(FColors.Gutter);
  Canvas.RoundRect(mInput.Left, mInput.Top, mInput.Right, mInput.Bottom, S(8), S(8));
  InflateRect(mInput, -S(10), 0);
  Canvas.Brush.Style := bsClear;
  if FWindow.FState.Pattern = '' then
  begin
    Canvas.Font.Color := C(FColors.Muted);
    mText := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchPrompt);
    if FWindow.FOptions.FormName <> '' then
    begin
      mText := FWindow.FOptions.FormName + ': ' + mText;
    end;
  end
  else
  begin
    Canvas.Font.Color := C(FColors.Text);
    mText := FWindow.FState.Pattern + '|';
  end;
  DrawText(Canvas.Handle, PChar(mText), -1, mInput, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasComponentSearchWindow.TPainter.DrawChips;
var
  mX, mY: Integer;
  mKind: TAtlasDesignerKind;
  mField: TAtlasDesignerField;
  mRect: TRect;
  mText: string;
  mMetrics: TMetrics;
begin
  if FWindow.FOptions.Compact then
  begin
    Exit;
  end;
  mMetrics := Metrics;
  Canvas.Font.Assign(FSmallFont);
  mX := S(10);
  mY := mMetrics.Header + (mMetrics.Chips - S(22)) div 2 - S(2);
  for mKind := Low(TAtlasDesignerKind) to High(TAtlasDesignerKind) do
  begin
    DrawChip(mX, mY, KindCaption(mKind), mKind = FWindow.FState.Kind, ChipKinds + Ord(mKind));
  end;
  Canvas.Pen.Color := C(FColors.Line);
  Canvas.MoveTo(mX + S(2), mY + S(3));
  Canvas.LineTo(mX + S(2), mY + S(19));
  Inc(mX, S(12));
  mText := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchIn);
  mRect := Rect(mX, mY, mX + Canvas.TextWidth(mText), mY + S(22));
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := C(FColors.Muted);
  DrawText(Canvas.Handle, PChar(mText), -1, mRect, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  Canvas.Brush.Style := bsSolid;
  mX := mRect.Right + S(6);
  for mField := Low(TAtlasDesignerField) to High(TAtlasDesignerField) do
  begin
    DrawChip(mX, mY, FieldCaption(mField), mField in FWindow.FState.Fields, ChipFields + Ord(mField));
  end;
end;

/// <summary>Eine Zeile: Name, Klasse, Caption.</summary>
procedure TAtlasComponentSearchWindow.TPainter.DrawCompactRow(const AItem: TAtlasDesignerItem; const APart: TRect);
var
  mEnd: Integer;
  mFields: TAtlasDesignerFields;
begin
  mFields := FWindow.FState.Fields;
  mEnd := DrawHighlighted(AItem.Name, APart, FColors.Text, TAtlasDesignerField.Name in mFields);
  Canvas.Font.Assign(FSmallFont);
  mEnd := DrawHighlighted(AItem.TypeName, Rect(mEnd + S(10), APart.Top, APart.Right, APart.Bottom),
    FColors.Muted, TAtlasDesignerField.ClassName in mFields);
  if AItem.Caption <> '' then
  begin
    DrawHighlighted('„' + AItem.Caption + '“', Rect(mEnd + S(10), APart.Top, APart.Right, APart.Bottom),
      FColors.Muted, TAtlasDesignerField.Caption in mFields);
  end;
end;

/// <summary>Zeile 1: Name und Caption; Zeile 2: Klasse und Elternelement.</summary>
procedure TAtlasComponentSearchWindow.TPainter.DrawFullRow(const AItem: TAtlasDesignerItem;
  const ARect, APart: TRect);
var
  mEnd: Integer;
  mText: string;
  mFields: TAtlasDesignerFields;
begin
  mFields := FWindow.FState.Fields;
  mEnd := DrawHighlighted(AItem.Name, Rect(APart.Left, ARect.Top + S(2), APart.Right, ARect.Top + S(22)),
    FColors.Text, TAtlasDesignerField.Name in mFields);
  if AItem.Caption <> '' then
  begin
    DrawHighlighted('„' + AItem.Caption + '“', Rect(mEnd + S(10), ARect.Top + S(2), APart.Right, ARect.Top + S(22)),
      FColors.Muted, TAtlasDesignerField.Caption in mFields);
  end;
  Canvas.Font.Assign(FSmallFont);
  mEnd := DrawHighlighted(AItem.TypeName, Rect(APart.Left, ARect.Top + S(21), APart.Right, ARect.Bottom - S(2)),
    FColors.Muted, TAtlasDesignerField.ClassName in mFields);
  if not AItem.Visual then
  begin
    mText := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchNonVisual);
  end
  else if AItem.ParentName <> '' then
  begin
    mText := AItem.ParentName;
  end
  else
  begin
    mText := FWindow.FOptions.FormName;
  end;
  if mText <> '' then
  begin
    DrawHighlighted('· ' + mText, Rect(mEnd + S(8), ARect.Top + S(21), APart.Right, ARect.Bottom - S(2)),
      FColors.Muted, False);
  end;
end;

procedure TAtlasComponentSearchWindow.TPainter.DrawRow(ARow: Integer; const ARect: TRect);
var
  mRow: TAtlasDesignerRow;
  mPart: TRect;
  mText: string;
begin
  mRow := FWindow.FState.Rows[ARow];
  mPart := Rect(ARect.Left + S(10), ARect.Top, ARect.Right - S(10), ARect.Bottom);
  Canvas.Brush.Style := bsClear;
  if mRow.Header then
  begin
    Canvas.Font.Assign(FSmallFont);
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := C(FColors.Muted);
    mText := mRow.Caption + '   ' + IntToStr(mRow.Count);
    DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
    Canvas.Font.Style := [];
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;
  if ARow = FWindow.FState.Selected then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := C(FColors.Selection);
    Canvas.FillRect(ARect);
    Canvas.Brush.Style := bsClear;
  end;
  Canvas.Font.Assign(FUIFont);
  if FWindow.FOptions.Compact then
  begin
    DrawCompactRow(FWindow.FItems[mRow.Item], mPart);
  end
  else
  begin
    DrawFullRow(FWindow.FItems[mRow.Item], ARect, mPart);
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasComponentSearchWindow.TPainter.DrawList;
var
  mRow: Integer;
  mRect: TRect;
  mClip: HRGN;
  mTops: TArray<Integer>;
  mScroll: Integer;
begin
  Canvas.Font.Assign(FUIFont);
  if Length(FWindow.FState.Rows) = 0 then
  begin
    Canvas.Font.Color := C(FColors.Muted);
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, '—', -1, FListRect, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;
  mTops := FWindow.FState.RowTops;
  mScroll := FWindow.FState.Scroll;
  mClip := CreateRectRgn(FListRect.Left, FListRect.Top, FListRect.Right, FListRect.Bottom);
  try
    SelectClipRgn(Canvas.Handle, mClip);
    for mRow := 0 to High(FWindow.FState.Rows) do
    begin
      if FListRect.Top + mTops[mRow + 1] - mScroll <= FListRect.Top then
      begin
        Continue;
      end;
      if FListRect.Top + mTops[mRow] - mScroll >= FListRect.Bottom then
      begin
        Break;
      end;
      mRect := Rect(FListRect.Left + S(4), FListRect.Top + mTops[mRow] - mScroll, FListRect.Right - S(6),
        FListRect.Top + mTops[mRow + 1] - mScroll);
      DrawRow(mRow, mRect);
      AddArea(THit.Row, mRect, mRow);
    end;
  finally
    SelectClipRgn(Canvas.Handle, 0);
    DeleteObject(mClip);
  end;
end;

procedure TAtlasComponentSearchWindow.TPainter.DrawMap(const AArea: TRect; const AItem: TAtlasDesignerItem);
var
  mForm, mRect, mBounds: TRect;
  mScale: Double;
  mOther: TAtlasDesignerItem;

  function Map(const ABounds: TRect): TRect;
  begin
    Result := Rect(mForm.Left + Round(ABounds.Left * mScale), mForm.Top + Round(ABounds.Top * mScale),
      mForm.Left + Max(Round(ABounds.Left * mScale) + 2, Round(ABounds.Right * mScale)),
      mForm.Top + Max(Round(ABounds.Top * mScale) + 2, Round(ABounds.Bottom * mScale)));
  end;

begin
  mBounds := FWindow.FOptions.FormBounds;
  if mBounds.IsEmpty then
  begin
    Exit;
  end;
  mScale := Min(AArea.Width / mBounds.Width, AArea.Height / mBounds.Height);
  mForm := Rect(AArea.Left, AArea.Top, AArea.Left + Round(mBounds.Width * mScale),
    AArea.Top + Round(mBounds.Height * mScale));
  Canvas.Brush.Color := C(FColors.Gutter);
  Canvas.Pen.Color := C(FColors.Line);
  Canvas.Rectangle(mForm);
  Canvas.Brush.Style := bsClear;
  for mOther in FWindow.FItems do
  begin
    if mOther.Visual and not mOther.Bounds.IsEmpty and not SameText(mOther.Name, AItem.Name) then
    begin
      mRect := Map(mOther.Bounds);
      Canvas.Rectangle(mRect);
    end;
  end;
  if not AItem.Bounds.IsEmpty then
  begin
    mRect := Map(AItem.Bounds);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := C(FColors.AccentSoft);
    Canvas.Pen.Color := C(FColors.Accent);
    Canvas.Pen.Width := Max(1, S(2));
    Canvas.Rectangle(mRect);
    Canvas.Pen.Width := 1;
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasComponentSearchWindow.TPainter.PreviewHead(const ACaption: string; const AArea: TRect;
  var ATop: Integer);
var
  mLine: TRect;
begin
  Canvas.Font.Assign(FSmallFont);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := C(FColors.Muted);
  mLine := Rect(AArea.Left, ATop, AArea.Right, ATop + S(20));
  DrawText(Canvas.Handle, PChar(ACaption), -1, mLine, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  Canvas.Font.Style := [];
  Inc(ATop, S(20));
end;

procedure TAtlasComponentSearchWindow.TPainter.PreviewLine(const AText: string; AColor: TAtlasColor;
  const AArea: TRect; var ATop: Integer);
var
  mLine: TRect;
begin
  if ATop + S(18) > AArea.Bottom then
  begin
    Exit;
  end;
  Canvas.Font.Color := C(AColor);
  mLine := Rect(AArea.Left + S(4), ATop, AArea.Right, ATop + S(18));
  DrawText(Canvas.Handle, PChar(AText), -1, mLine, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  Inc(ATop, S(18));
end;

/// <summary>Lage: Karte des Formulars, Position und Größe.</summary>
procedure TAtlasComponentSearchWindow.TPainter.PreviewPlace(const AItem: TAtlasDesignerItem; const AArea: TRect;
  var ATop: Integer);
var
  mText: string;
begin
  PreviewHead(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchPosition), AArea, ATop);
  DrawMap(Rect(AArea.Left, ATop, AArea.Right, ATop + S(120)), AItem);
  Canvas.Brush.Style := bsClear;
  if not FWindow.FOptions.FormBounds.IsEmpty then
  begin
    Inc(ATop, S(126));
  end;
  Canvas.Font.Assign(FSmallFont);
  if not AItem.Visual then
  begin
    mText := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchNonVisual);
  end
  else
  begin
    mText := Format('%d, %d · %d × %d', [AItem.Bounds.Left, AItem.Bounds.Top, AItem.Bounds.Width,
      AItem.Bounds.Height]);
  end;
  if AItem.ParentName <> '' then
  begin
    mText := mText + ' · ' + AItem.ParentName;
  end;
  PreviewLine(mText, FColors.Text, AArea, ATop);
  Inc(ATop, S(6));
end;

/// <summary>Gesetzte Eigenschaften und belegte Ereignisse.</summary>
procedure TAtlasComponentSearchWindow.TPainter.PreviewDetails(const AItem: TAtlasDesignerItem; const AArea: TRect;
  var ATop: Integer);
var
  mText: string;
begin
  if Length(AItem.Properties) > 0 then
  begin
    PreviewHead(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchProperties), AArea, ATop);
    Canvas.Font.Assign(FSmallFont);
    for mText in AItem.Properties do
    begin
      PreviewLine(mText, FColors.Text, AArea, ATop);
    end;
    Inc(ATop, S(6));
  end;
  PreviewHead(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchEvents), AArea, ATop);
  Canvas.Font.Assign(FSmallFont);
  if Length(AItem.Events) = 0 then
  begin
    PreviewLine(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchNoEvents), FColors.Muted, AArea, ATop);
  end;
  for mText in AItem.Events do
  begin
    PreviewLine(mText, FColors.Text, AArea, ATop);
  end;
end;

procedure TAtlasComponentSearchWindow.TPainter.DrawPreview;
var
  mIndex, mTop: Integer;
  mItem: TAtlasDesignerItem;
  mArea, mLine: TRect;
begin
  if not FWindow.FState.PreviewVisible then
  begin
    Exit;
  end;
  Canvas.Pen.Color := C(FColors.Line);
  Canvas.MoveTo(FPreviewRect.Left, FPreviewRect.Top);
  Canvas.LineTo(FPreviewRect.Left, FPreviewRect.Bottom);
  mIndex := FWindow.FState.SelectedItem;
  if mIndex < 0 then
  begin
    Exit;
  end;
  mItem := FWindow.FItems[mIndex];
  mArea := Rect(FPreviewRect.Left + S(12), FPreviewRect.Top + S(8), FPreviewRect.Right - S(12),
    FPreviewRect.Bottom - S(8));
  mTop := mArea.Top;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(FUIFont);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := C(FColors.Text);
  mLine := Rect(mArea.Left, mTop, mArea.Right, mTop + S(22));
  DrawText(Canvas.Handle, PChar(mItem.Name), -1, mLine, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  Canvas.Font.Style := [];
  Inc(mTop, S(22));
  Canvas.Font.Assign(FSmallFont);
  PreviewLine(mItem.TypeName, FColors.Muted, mArea, mTop);
  Inc(mTop, S(6));
  PreviewPlace(mItem, mArea, mTop);
  PreviewDetails(mItem, mArea, mTop);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasComponentSearchWindow.TPainter.DrawActions;
var
  mBar, mButton: TRect;
  mX: Integer;
  mAction: TAtlasComponentSearchAction;
  mText: string;
  mEnabled: Boolean;
  mMetrics: TMetrics;
begin
  if FWindow.FOptions.Compact then
  begin
    Exit;
  end;
  mMetrics := Metrics;
  mBar := Rect(0, FWindow.ClientHeight - mMetrics.Footer - mMetrics.Actions, FWindow.ClientWidth,
    FWindow.ClientHeight - mMetrics.Footer);
  Canvas.Pen.Color := C(FColors.Line);
  Canvas.MoveTo(mBar.Left, mBar.Top);
  Canvas.LineTo(mBar.Right, mBar.Top);
  Canvas.Font.Assign(FSmallFont);
  mX := S(10);
  for mAction := Low(TAtlasComponentSearchAction) to High(TAtlasComponentSearchAction) do
  begin
    mText := ActionCaption(mAction);
    mButton := Rect(mX, mBar.Top + S(6), mX + Canvas.TextWidth(mText) + S(18), mBar.Bottom - S(6));
    if mButton.Right > mBar.Right - S(10) then
    begin
      Break;
    end;
    mEnabled := FWindow.FState.ActionEnabled(FWindow.FItems, mAction);
    Canvas.Brush.Color := C(FColors.Gutter);
    Canvas.Pen.Color := C(FColors.Line);
    Canvas.Font.Color := C(FColors.Muted);
    if (mAction = TAtlasComponentSearchAction.Select) and mEnabled then
    begin
      Canvas.Brush.Color := C(FColors.Accent);
      Canvas.Pen.Color := C(FColors.Accent);
      Canvas.Font.Color := C(FColors.Surface);
    end
    else if mEnabled then
    begin
      Canvas.Font.Color := C(FColors.Text);
    end;
    Canvas.RoundRect(mButton.Left, mButton.Top, mButton.Right, mButton.Bottom, S(6), S(6));
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(mText), -1, mButton, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
    AddArea(THit.Action, mButton, Ord(mAction));
    mX := mButton.Right + S(6);
  end;
end;

procedure TAtlasComponentSearchWindow.TPainter.DrawFooter;
var
  mBar, mPart: TRect;
  mText: string;
begin
  mBar := Rect(0, FWindow.ClientHeight - Metrics.Footer, FWindow.ClientWidth, FWindow.ClientHeight);
  Canvas.Brush.Color := C(FColors.Gutter);
  Canvas.FillRect(mBar);
  Canvas.Font.Assign(FSmallFont);
  Canvas.Font.Color := C(FColors.Muted);
  Canvas.Brush.Style := bsClear;
  mText := TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSearchCount, [Length(FWindow.FState.Hits),
    Length(FWindow.FItems)]);
  mPart := Rect(mBar.Right - S(10) - Canvas.TextWidth(mText), mBar.Top, mBar.Right - S(10), mBar.Bottom);
  DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  if FWindow.FOptions.Compact then
  begin
    mText := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchKeysPopup);
  end
  else
  begin
    mText := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchKeys);
  end;
  mPart := Rect(mBar.Left + S(10), mBar.Top, mPart.Left - S(16), mBar.Bottom);
  DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasComponentSearchWindow.TPainter.Paint;
begin
  FAreas.Clear;
  Layout;
  Canvas.Brush.Color := C(FColors.Surface);
  Canvas.FillRect(FWindow.ClientRect);
  DrawHeader;
  DrawChips;
  DrawList;
  DrawPreview;
  DrawActions;
  DrawFooter;
  // Rahmen in Akzentfarbe (ältere Windows-Versionen ohne Rahmenfarbe des Fenstermanagers).
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := C(FColors.Accent);
  Canvas.Rectangle(FWindow.ClientRect);
  Canvas.Brush.Style := bsSolid;
end;

function TAtlasComponentSearchWindow.TPainter.RowAt(Y: Integer): Integer;
var
  mOffset, mRow: Integer;
  mTops: TArray<Integer>;
begin
  Result := -1;
  if (Y < FListRect.Top) or (Y >= FListRect.Bottom) then
  begin
    Exit;
  end;
  mTops := FWindow.FState.RowTops;
  mOffset := Y - FListRect.Top + FWindow.FState.Scroll;
  for mRow := 0 to High(FWindow.FState.Rows) do
  begin
    if (mOffset >= mTops[mRow]) and (mOffset < mTops[mRow + 1]) then
    begin
      Exit(mRow);
    end;
  end;
end;

function TAtlasComponentSearchWindow.TPainter.HitAt(X, Y: Integer; out AArea: THitArea): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := FAreas.Count - 1 downto 0 do
  begin
    if FAreas[mIndex].Rect.Contains(Point(X, Y)) then
    begin
      AArea := FAreas[mIndex];
      Exit(True);
    end;
  end;
  AArea := Default(THitArea);
  Result := False;
end;

{ TAtlasComponentSearchWindow }

constructor TAtlasComponentSearchWindow.CreateSearch(AOwner: TComponent; const AOptions: TAtlasComponentSearchOptions;
  const AItems: TArray<TAtlasDesignerItem>; const AColors: TAtlasColors);
begin
  inherited CreateNew(AOwner);
  FOptions := AOptions;
  FItems := AItems;
  FPainter := TPainter.Create(Self, AColors);
  BorderStyle := bsNone;
  DoubleBuffered := True;
  Color := C(AColors.Surface);
  Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchTitle);
  OnClose := FormClose;
  OnDeactivate := FormDeactivate;
  Font.Assign(FPainter.UIFont);
  FState.Kind := AOptions.Kind;
  FState.Fields := AOptions.Fields;
  if FState.Fields = [] then
  begin
    FState.Fields := [TAtlasDesignerField.Name, TAtlasDesignerField.Caption, TAtlasDesignerField.ClassName];
  end;
  FState.Grouping := AOptions.Grouping;
  FState.PreviewVisible := AOptions.Preview;
  // Klein: ohne Filter, Gruppen und Vorschau.
  if AOptions.Compact then
  begin
    FState.Kind := TAtlasDesignerKind.All;
    FState.Grouping := TAtlasDesignerGrouping.Flat;
    FState.PreviewVisible := False;
  end;
  Refilter(AOptions.Current);
end;

destructor TAtlasComponentSearchWindow.Destroy;
begin
  FPainter.Free;
  inherited Destroy;
end;

procedure TAtlasComponentSearchWindow.CreateParams(var Params: TCreateParams);
begin
  inherited;
  // Ohne Systemrahmen; vergrößert wird über WM_NCHITTEST. Schatten wie die Palette.
  Params.Style := (Params.Style and not (WS_CAPTION or WS_THICKFRAME)) or WS_POPUP;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
end;

procedure TAtlasComponentSearchWindow.CreateWnd;
var
  mPreference, mBorder: DWORD;
begin
  inherited CreateWnd;
  mPreference := RoundCorners;
  DwmSetWindowAttribute(Handle, CornerPreference, @mPreference, SizeOf(mPreference));
  mBorder := DWORD(FPainter.Colors.Accent);
  DwmSetWindowAttribute(Handle, BorderColorAttribute, @mBorder, SizeOf(mBorder));
end;

procedure TAtlasComponentSearchWindow.ShowOver(const AArea: TRect);
var
  mWidth, mHeight: Integer;
  mMetrics: TMetrics;
begin
  mMetrics := FPainter.Metrics;
  if FOptions.Compact then
  begin
    mWidth := Min(ScaleValue(560), AArea.Width - ScaleValue(40));
    mHeight := mMetrics.Header + CompactRows * mMetrics.Entry + mMetrics.Footer + ScaleValue(4);
    SetBounds(AArea.Left + (AArea.Width - mWidth) div 2, AArea.Top + ScaleValue(80), mWidth, mHeight);
  end
  else if not FOptions.Bounds.IsEmpty and (Screen.MonitorFromRect(FOptions.Bounds, mdNull) <> nil) then
  begin
    SetBounds(FOptions.Bounds.Left, FOptions.Bounds.Top, FOptions.Bounds.Width, FOptions.Bounds.Height);
  end
  else
  begin
    mWidth := Min(ScaleValue(900), AArea.Width - ScaleValue(40));
    mHeight := Min(ScaleValue(580), AArea.Height - ScaleValue(40));
    SetBounds(AArea.Left + (AArea.Width - mWidth) div 2,
      AArea.Top + Max(ScaleValue(20), (AArea.Height - mHeight) div 3), mWidth, mHeight);
  end;
  Show;
  SetFocus;
end;

{ Liste }

procedure TAtlasComponentSearchWindow.Refilter(const AKeep: string);
begin
  FState.Hits := TAtlasDesignerSearch.Find(FItems, FState.Pattern, FState.Fields, FState.Kind);
  FState.Rebuild(FItems, FOptions.FormName, FPainter.Metrics);
  FState.SelectName(FItems, AKeep);
  if FState.Selected < 0 then
  begin
    FState.Scroll := 0;
    FState.SelectFirstItem;
  end;
  EnsureVisible;
  Invalidate;
end;

function TAtlasComponentSearchWindow.SelectedItem: Integer;
begin
  Result := FState.SelectedItem;
end;

procedure TAtlasComponentSearchWindow.MoveSelection(ADelta: Integer);
begin
  if (Length(FState.Rows) = 0) or (ADelta = 0) then
  begin
    Exit;
  end;
  FState.Move(ADelta);
  EnsureVisible;
  Invalidate;
end;

procedure TAtlasComponentSearchWindow.EnsureVisible;
begin
  FPainter.Layout;
  FState.Reveal(FPainter.ListRect.Height);
end;

procedure TAtlasComponentSearchWindow.SetPattern(const APattern: string);
begin
  FState.Pattern := APattern;
  Refilter('');
end;

procedure TAtlasComponentSearchWindow.SetKind(AKind: TAtlasDesignerKind);
var
  mKeep: string;
begin
  mKeep := FState.SelectedName(FItems);
  FState.Kind := AKind;
  Refilter(mKeep);
end;

procedure TAtlasComponentSearchWindow.SetFields(AFields: TAtlasDesignerFields);
begin
  // Mindestens ein Feld bleibt gewählt.
  if AFields = [] then
  begin
    Exit;
  end;
  FState.Fields := AFields;
  Refilter('');
end;

procedure TAtlasComponentSearchWindow.SetGrouping(AGrouping: TAtlasDesignerGrouping);
var
  mKeep: string;
begin
  mKeep := FState.SelectedName(FItems);
  FState.Grouping := AGrouping;
  Refilter(mKeep);
end;

procedure TAtlasComponentSearchWindow.Run(AAction: TAtlasComponentSearchAction);
var
  mItem: TAtlasDesignerItem;
  mHandler: TAtlasComponentSearchActionEvent;
begin
  if not FState.ActionEnabled(FItems, AAction) then
  begin
    Exit;
  end;
  mItem := FItems[FState.SelectedItem];
  if AAction = TAtlasComponentSearchAction.CopyName then
  begin
    Clipboard.AsText := mItem.Name;
    Exit;
  end;
  mHandler := FHooks.OnAction;
  // Erst schließen, dann im Designer bzw. Code wirken: Die IDE holt dort den Fokus.
  if HandleAllocated then
  begin
    Close;
  end;
  if Assigned(mHandler) then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.DesignerBar,
      procedure
      begin
        mHandler(AAction, mItem);
      end);
  end;
end;

procedure TAtlasComponentSearchWindow.FormClose(Sender: TObject; var Action: TCloseAction);
var
  mClosed: TProc;
begin
  Action := caFree;
  if FHooks.Closing then
  begin
    Exit;
  end;
  FHooks.Closing := True;
  mClosed := FHooks.OnClosed;
  if Assigned(mClosed) then
  begin
    mClosed();
  end;
end;

procedure TAtlasComponentSearchWindow.FormDeactivate(Sender: TObject);
begin
  // Klein wie Strg+P: Ein Klick daneben schließt.
  if FOptions.Compact and not FHooks.Closing then
  begin
    Close;
  end;
end;

procedure TAtlasComponentSearchWindow.Resize;
begin
  inherited;
  if Length(FState.RowTops) > 0 then
  begin
    EnsureVisible;
  end;
  Invalidate;
end;

procedure TAtlasComponentSearchWindow.Paint;
begin
  FPainter.Paint;
end;

{ Eingabe }

procedure TAtlasComponentSearchWindow.WMNCHitTest(var Message: TWMNCHitTest);
var
  mPoint: TPoint;
  mArea: THitArea;
  mHeader: Integer;
begin
  inherited;
  if FOptions.Compact then
  begin
    Exit;
  end;
  mPoint := ScreenToClient(Point(Message.XPos, Message.YPos));
  Message.Result := EdgeHit(mPoint, ClientRect, ScaleValue(6));
  if Message.Result <> HTNOWHERE then
  begin
    Exit;
  end;
  mHeader := FPainter.Metrics.Header;
  // Freie Stellen im Kopf verschieben das Fenster.
  if (mPoint.Y < mHeader) and not FPainter.HitAt(mPoint.X, mPoint.Y, mArea) and
    ((mPoint.Y < ScaleValue(7)) or (mPoint.Y > mHeader - ScaleValue(7))) then
  begin
    Message.Result := HTCAPTION;
  end
  else
  begin
    Message.Result := HTCLIENT;
  end;
end;

procedure TAtlasComponentSearchWindow.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  inherited;
  Message.Result := Message.Result or DLGC_WANTALLKEYS or DLGC_WANTARROWS or DLGC_WANTCHARS or DLGC_WANTTAB;
end;

/// <summary>Tasten, die Suchwort und Ansicht ändern; False, wenn die Taste nichts tut.</summary>
function TAtlasComponentSearchWindow.EditKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := True;
  if (AKey = VK_F4) and not FOptions.Compact then
  begin
    FState.PreviewVisible := not FState.PreviewVisible;
    EnsureVisible;
    Invalidate;
  end
  else if (AKey = VK_BACK) and (FState.Pattern <> '') and (ssCtrl in AShift) then
  begin
    SetPattern('');
  end
  else if (AKey = VK_BACK) and (FState.Pattern <> '') then
  begin
    SetPattern(Copy(FState.Pattern, 1, Length(FState.Pattern) - 1));
  end
  else if (ssCtrl in AShift) and (AKey = Ord('C')) then
  begin
    Run(TAtlasComponentSearchAction.CopyName);
  end
  else if (ssCtrl in AShift) and (AKey = Ord('G')) and not FOptions.Compact then
  begin
    SetGrouping(TAtlasDesignerGrouping((Ord(FState.Grouping) + 1) mod (Ord(High(TAtlasDesignerGrouping)) + 1)));
  end
  else
  begin
    Result := AKey in [VK_F4, VK_BACK];
  end;
end;

procedure TAtlasComponentSearchWindow.KeyDown(var Key: Word; Shift: TShiftState);
var
  mPage: Integer;
begin
  mPage := Max(1, FPainter.ListRect.Height div FPainter.Metrics.Entry);
  case Key of
    VK_ESCAPE:
      Close;
    VK_RETURN:
      if ssCtrl in Shift then
      begin
        Run(TAtlasComponentSearchAction.Event);
      end
      else
      begin
        Run(TAtlasComponentSearchAction.Select);
      end;
    VK_UP:
      MoveSelection(-1);
    VK_DOWN:
      MoveSelection(1);
    VK_PRIOR:
      MoveSelection(-mPage);
    VK_NEXT:
      MoveSelection(mPage);
  else
    if not EditKey(Key, Shift) then
    begin
      Exit;
    end;
  end;
  Key := 0;
end;

procedure TAtlasComponentSearchWindow.KeyPress(var Key: Char);
begin
  if Key >= ' ' then
  begin
    SetPattern(FState.Pattern + Key);
  end;
  Key := #0;
end;

procedure TAtlasComponentSearchWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mArea: THitArea;
  mField: TAtlasDesignerField;
begin
  inherited;
  if (Button <> mbLeft) or not FPainter.HitAt(X, Y, mArea) then
  begin
    Exit;
  end;
  case mArea.Kind of
    THit.Chip:
      if mArea.Value < ChipFields then
      begin
        SetKind(TAtlasDesignerKind(mArea.Value - ChipKinds));
      end
      else
      begin
        mField := TAtlasDesignerField(mArea.Value - ChipFields);
        if mField in FState.Fields then
        begin
          SetFields(FState.Fields - [mField]);
        end
        else
        begin
          SetFields(FState.Fields + [mField]);
        end;
      end;
    THit.Grouping:
      SetGrouping(TAtlasDesignerGrouping(mArea.Value));
    THit.Action:
      Run(TAtlasComponentSearchAction(mArea.Value));
    THit.Row:
      if not FState.Rows[mArea.Value].Header then
      begin
        FState.Selected := mArea.Value;
        EnsureVisible;
        Invalidate;
      end;
    THit.None: ;
  end;
end;

procedure TAtlasComponentSearchWindow.DblClick;
var
  mPoint: TPoint;
  mRow: Integer;
begin
  inherited;
  mPoint := ScreenToClient(Mouse.CursorPos);
  mRow := FPainter.RowAt(mPoint.Y);
  if (mRow >= 0) and not FState.Rows[mRow].Header and (mPoint.X < FPainter.ListRect.Right) then
  begin
    FState.Selected := mRow;
    Run(TAtlasComponentSearchAction.Select);
  end;
end;

function TAtlasComponentSearchWindow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FState.ScrollBy(-Sign(WheelDelta) * 3 * FPainter.Metrics.Entry, FPainter.ListRect.Height);
  Invalidate;
  Result := True;
end;

end.
