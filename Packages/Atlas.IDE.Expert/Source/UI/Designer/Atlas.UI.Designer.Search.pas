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
  private const
    ChipKinds = 0;
    ChipFields = 100;
  private
    FColors: TAtlasColors;
    FOptions: TAtlasComponentSearchOptions;
    FItems: TArray<TAtlasDesignerItem>;
    FPattern: string;
    FKind: TAtlasDesignerKind;
    FFields: TAtlasDesignerFields;
    FGrouping: TAtlasDesignerGrouping;
    FPreviewVisible: Boolean;
    FHits: TArray<Integer>;
    FRows: TArray<TAtlasDesignerRow>;
    FRowTops: TArray<Integer>;
    FSelected: Integer;
    FScroll: Integer;
    FAreas: TList<THitArea>;
    FListRect: TRect;
    FPreviewRect: TRect;
    FUIFont: TFont;
    FSmallFont: TFont;
    FClosing: Boolean;
    FOnAction: TAtlasComponentSearchActionEvent;
    FOnClosed: TProc;
    function S(AValue: Integer): Integer;
    function HeaderHeight: Integer;
    function ChipHeight: Integer;
    function GroupHeight: Integer;
    function EntryHeight: Integer;
    function ActionHeight: Integer;
    function FooterHeight: Integer;
    function KindCaption(AKind: TAtlasDesignerKind): string;
    function FieldCaption(AField: TAtlasDesignerField): string;
    function GroupingCaption(AGrouping: TAtlasDesignerGrouping): string;
    function ActionCaption(AAction: TAtlasComponentSearchAction): string;
    function ActionEnabled(AAction: TAtlasComponentSearchAction): Boolean;
    procedure Refilter(const AKeep: string);
    procedure RebuildRows;
    procedure EnsureVisible;
    procedure FirstItemRow;
    function RowAt(Y: Integer): Integer;
    function HitAt(X, Y: Integer; out AArea: THitArea): Boolean;
    procedure AddArea(AKind: THit; const ARect: TRect; AValue: Integer);
    procedure Layout;
    procedure DrawChip(var X: Integer; Y: Integer; const ACaption: string; AOn: Boolean; AValue: Integer);
    procedure DrawHeader;
    procedure DrawChips;
    procedure DrawList;
    procedure DrawRow(ARow: Integer; const ARect: TRect);
    function DrawHighlighted(const AText: string; const ARect: TRect; ABase: TAtlasColor; AMatch: Boolean): Integer;
    procedure DrawPreview;
    procedure DrawMap(const AArea: TRect; const AItem: TAtlasDesignerItem);
    procedure DrawActions;
    procedure DrawFooter;
    procedure ChipClicked(AValue: Integer);
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
    property Rows: TArray<TAtlasDesignerRow> read FRows;
    property Hits: TArray<Integer> read FHits;
    property Kind: TAtlasDesignerKind read FKind;
    property Fields: TAtlasDesignerFields read FFields;
    property Grouping: TAtlasDesignerGrouping read FGrouping;
    property PreviewVisible: Boolean read FPreviewVisible;
    property OnAction: TAtlasComponentSearchActionEvent read FOnAction write FOnAction;
    /// <summary>Nach dem Schließen; das Fenster gibt sich selbst frei.</summary>
    property OnClosed: TProc read FOnClosed write FOnClosed;
  end;

implementation

uses
  System.Math,
  Winapi.Dwmapi,
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.UI.Strings;

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

{ TAtlasComponentSearchWindow }

constructor TAtlasComponentSearchWindow.CreateSearch(AOwner: TComponent; const AOptions: TAtlasComponentSearchOptions;
  const AItems: TArray<TAtlasDesignerItem>; const AColors: TAtlasColors);
begin
  inherited CreateNew(AOwner);
  FOptions := AOptions;
  FItems := AItems;
  FColors := AColors;
  FAreas := TList<THitArea>.Create;
  BorderStyle := bsNone;
  DoubleBuffered := True;
  Color := C(FColors.Surface);
  Caption := TAtlasStrings.Text(TAtlasTextId.DesignerSearchTitle);
  OnClose := FormClose;
  OnDeactivate := FormDeactivate;
  FUIFont := TFont.Create;
  FUIFont.Name := 'Segoe UI';
  FUIFont.Size := 10;
  FSmallFont := TFont.Create;
  FSmallFont.Name := 'Segoe UI';
  FSmallFont.Size := 8;
  Font.Assign(FUIFont);
  FKind := AOptions.Kind;
  FFields := AOptions.Fields;
  if FFields = [] then
    FFields := [TAtlasDesignerField.Name, TAtlasDesignerField.Caption, TAtlasDesignerField.ClassName];
  FGrouping := AOptions.Grouping;
  FPreviewVisible := AOptions.Preview;
  // Klein: ohne Filter, Gruppen und Vorschau.
  if AOptions.Compact then
  begin
    FKind := TAtlasDesignerKind.All;
    FGrouping := TAtlasDesignerGrouping.Flat;
    FPreviewVisible := False;
  end;
  Refilter(AOptions.Current);
end;

destructor TAtlasComponentSearchWindow.Destroy;
begin
  FAreas.Free;
  FUIFont.Free;
  FSmallFont.Free;
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
  mBorder := DWORD(FColors.Accent);
  DwmSetWindowAttribute(Handle, BorderColorAttribute, @mBorder, SizeOf(mBorder));
end;

function TAtlasComponentSearchWindow.S(AValue: Integer): Integer;
begin
  Result := ScaleValue(AValue);
end;

function TAtlasComponentSearchWindow.HeaderHeight: Integer;
begin
  Result := S(44);
end;

function TAtlasComponentSearchWindow.ChipHeight: Integer;
begin
  Result := 0;
  if not FOptions.Compact then
    Result := S(32);
end;

function TAtlasComponentSearchWindow.GroupHeight: Integer;
begin
  Result := S(24);
end;

function TAtlasComponentSearchWindow.EntryHeight: Integer;
begin
  Result := S(40);
  if FOptions.Compact then
    Result := S(26);
end;

function TAtlasComponentSearchWindow.ActionHeight: Integer;
begin
  Result := 0;
  if not FOptions.Compact then
    Result := S(34);
end;

function TAtlasComponentSearchWindow.FooterHeight: Integer;
begin
  Result := S(24);
end;

procedure TAtlasComponentSearchWindow.ShowOver(const AArea: TRect);
var
  mWidth, mHeight: Integer;
begin
  if FOptions.Compact then
  begin
    mWidth := Min(S(560), AArea.Width - S(40));
    mHeight := HeaderHeight + CompactRows * EntryHeight + FooterHeight + S(4);
    SetBounds(AArea.Left + (AArea.Width - mWidth) div 2, AArea.Top + S(80), mWidth, mHeight);
  end
  else if not FOptions.Bounds.IsEmpty and (Screen.MonitorFromRect(FOptions.Bounds, mdNull) <> nil) then
    SetBounds(FOptions.Bounds.Left, FOptions.Bounds.Top, FOptions.Bounds.Width, FOptions.Bounds.Height)
  else
  begin
    mWidth := Min(S(900), AArea.Width - S(40));
    mHeight := Min(S(580), AArea.Height - S(40));
    SetBounds(AArea.Left + (AArea.Width - mWidth) div 2, AArea.Top + Max(S(20), (AArea.Height - mHeight) div 3),
      mWidth, mHeight);
  end;
  Show;
  SetFocus;
end;

function TAtlasComponentSearchWindow.KindCaption(AKind: TAtlasDesignerKind): string;
begin
  case AKind of
    TAtlasDesignerKind.Controls: Result := TAtlasStrings.Text(TAtlasTextId.DesignerSearchKindControls);
    TAtlasDesignerKind.NonVisual: Result := TAtlasStrings.Text(TAtlasTextId.DesignerSearchKindNonVisual);
    TAtlasDesignerKind.Containers: Result := TAtlasStrings.Text(TAtlasTextId.DesignerSearchKindContainers);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.DesignerSearchKindAll);
  end;
end;

function TAtlasComponentSearchWindow.FieldCaption(AField: TAtlasDesignerField): string;
begin
  case AField of
    TAtlasDesignerField.Caption: Result := TAtlasStrings.Text(TAtlasTextId.DesignerSearchFieldCaption);
    TAtlasDesignerField.ClassName: Result := TAtlasStrings.Text(TAtlasTextId.DesignerSearchFieldClass);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.DesignerSearchFieldName);
  end;
end;

function TAtlasComponentSearchWindow.GroupingCaption(AGrouping: TAtlasDesignerGrouping): string;
begin
  case AGrouping of
    TAtlasDesignerGrouping.ClassName: Result := TAtlasStrings.Text(TAtlasTextId.DesignerSearchGroupClass);
    TAtlasDesignerGrouping.Flat: Result := TAtlasStrings.Text(TAtlasTextId.DesignerSearchGroupFlat);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.DesignerSearchGroupHierarchy);
  end;
end;

function TAtlasComponentSearchWindow.ActionCaption(AAction: TAtlasComponentSearchAction): string;
begin
  case AAction of
    TAtlasComponentSearchAction.Event: Result := TAtlasStrings.Text(TAtlasTextId.DesignerSearchEvent);
    TAtlasComponentSearchAction.CopyName: Result := TAtlasStrings.Text(TAtlasTextId.DesignerSearchCopy);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.DesignerSearchSelect);
  end;
end;

function TAtlasComponentSearchWindow.ActionEnabled(AAction: TAtlasComponentSearchAction): Boolean;
var
  mIndex: Integer;
begin
  mIndex := SelectedItem;
  Result := mIndex >= 0;
  if Result and (AAction = TAtlasComponentSearchAction.Event) then
    Result := Length(FItems[mIndex].Events) > 0;
end;

{ Liste }

procedure TAtlasComponentSearchWindow.Refilter(const AKeep: string);
var
  mRow: Integer;
begin
  FHits := TAtlasDesignerSearch.Find(FItems, FPattern, FFields, FKind);
  RebuildRows;
  FSelected := -1;
  if AKeep <> '' then
    for mRow := 0 to High(FRows) do
      if not FRows[mRow].Header and SameText(FItems[FRows[mRow].Item].Name, AKeep) then
      begin
        FSelected := mRow;
        Break;
      end;
  if FSelected < 0 then
  begin
    FScroll := 0;
    FirstItemRow;
  end;
  EnsureVisible;
  Invalidate;
end;

procedure TAtlasComponentSearchWindow.FirstItemRow;
var
  mRow: Integer;
begin
  FSelected := -1;
  for mRow := 0 to High(FRows) do
    if not FRows[mRow].Header then
    begin
      FSelected := mRow;
      Break;
    end;
end;

procedure TAtlasComponentSearchWindow.RebuildRows;
var
  mRow, mTop: Integer;
begin
  FRows := TAtlasDesignerGroups.Rows(FItems, FHits, FGrouping, FOptions.FormName);
  SetLength(FRowTops, Length(FRows) + 1);
  mTop := 0;
  for mRow := 0 to High(FRows) do
  begin
    FRowTops[mRow] := mTop;
    if FRows[mRow].Header then
      Inc(mTop, GroupHeight)
    else
      Inc(mTop, EntryHeight);
  end;
  FRowTops[Length(FRows)] := mTop;
end;

function TAtlasComponentSearchWindow.SelectedItem: Integer;
begin
  Result := -1;
  if (FSelected >= 0) and (FSelected <= High(FRows)) and not FRows[FSelected].Header then
    Result := FRows[FSelected].Item;
end;

procedure TAtlasComponentSearchWindow.MoveSelection(ADelta: Integer);
var
  mRow, mStep, mCount: Integer;
begin
  if Length(FRows) = 0 then
    Exit;
  mStep := Sign(ADelta);
  if mStep = 0 then
    Exit;
  mRow := FSelected;
  // Um |ADelta| Komponenten weiter, Köpfe zählen nicht; am Rand stehen bleiben.
  for mCount := 1 to Abs(ADelta) do
  begin
    repeat
      mRow := mRow + mStep;
    until (mRow < 0) or (mRow > High(FRows)) or not FRows[mRow].Header;
    if (mRow < 0) or (mRow > High(FRows)) then
      Break;
    FSelected := mRow;
  end;
  EnsureVisible;
  Invalidate;
end;

procedure TAtlasComponentSearchWindow.EnsureVisible;
var
  mVisible: Integer;
begin
  Layout;
  if (FSelected < 0) or (FSelected > High(FRows)) then
    Exit;
  mVisible := FListRect.Height;
  // Kopf der eigenen Gruppe mit zeigen.
  if (FSelected > 0) and FRows[FSelected - 1].Header and (FRowTops[FSelected - 1] < FScroll) then
    FScroll := FRowTops[FSelected - 1]
  else if FRowTops[FSelected] < FScroll then
    FScroll := FRowTops[FSelected]
  else if FRowTops[FSelected + 1] > FScroll + mVisible then
    FScroll := FRowTops[FSelected + 1] - mVisible;
  FScroll := EnsureRange(FScroll, 0, Max(0, FRowTops[Length(FRows)] - mVisible));
end;

procedure TAtlasComponentSearchWindow.SetPattern(const APattern: string);
begin
  FPattern := APattern;
  Refilter('');
end;

procedure TAtlasComponentSearchWindow.SetKind(AKind: TAtlasDesignerKind);
var
  mIndex: Integer;
  mKeep: string;
begin
  mKeep := '';
  mIndex := SelectedItem;
  if mIndex >= 0 then
    mKeep := FItems[mIndex].Name;
  FKind := AKind;
  Refilter(mKeep);
end;

procedure TAtlasComponentSearchWindow.SetFields(AFields: TAtlasDesignerFields);
begin
  // Mindestens ein Feld bleibt gewählt.
  if AFields = [] then
    Exit;
  FFields := AFields;
  Refilter('');
end;

procedure TAtlasComponentSearchWindow.SetGrouping(AGrouping: TAtlasDesignerGrouping);
var
  mIndex: Integer;
  mKeep: string;
begin
  mKeep := '';
  mIndex := SelectedItem;
  if mIndex >= 0 then
    mKeep := FItems[mIndex].Name;
  FGrouping := AGrouping;
  Refilter(mKeep);
end;

procedure TAtlasComponentSearchWindow.ChipClicked(AValue: Integer);
var
  mField: TAtlasDesignerField;
begin
  if AValue >= ChipFields then
  begin
    mField := TAtlasDesignerField(AValue - ChipFields);
    if mField in FFields then
      SetFields(FFields - [mField])
    else
      SetFields(FFields + [mField]);
  end
  else
    SetKind(TAtlasDesignerKind(AValue - ChipKinds));
end;

procedure TAtlasComponentSearchWindow.Run(AAction: TAtlasComponentSearchAction);
var
  mIndex: Integer;
  mItem: TAtlasDesignerItem;
  mHandler: TAtlasComponentSearchActionEvent;
begin
  if not ActionEnabled(AAction) then
    Exit;
  mIndex := SelectedItem;
  mItem := FItems[mIndex];
  if AAction = TAtlasComponentSearchAction.CopyName then
  begin
    Clipboard.AsText := mItem.Name;
    Exit;
  end;
  mHandler := FOnAction;
  // Erst schließen, dann im Designer bzw. Code wirken: Die IDE holt dort den Fokus.
  if HandleAllocated then
    Close;
  if Assigned(mHandler) then
    TAtlasMainThread.ForceQueue(TAtlasFeature.DesignerBar,
      procedure
      begin
        mHandler(AAction, mItem);
      end);
end;

procedure TAtlasComponentSearchWindow.FormClose(Sender: TObject; var Action: TCloseAction);
var
  mClosed: TProc;
begin
  Action := caFree;
  if FClosing then
    Exit;
  FClosing := True;
  mClosed := FOnClosed;
  if Assigned(mClosed) then
    mClosed();
end;

procedure TAtlasComponentSearchWindow.FormDeactivate(Sender: TObject);
begin
  // Klein wie Strg+P: Ein Klick daneben schließt.
  if FOptions.Compact and not FClosing then
    Close;
end;

{ Zeichnen }

procedure TAtlasComponentSearchWindow.AddArea(AKind: THit; const ARect: TRect; AValue: Integer);
var
  mArea: THitArea;
begin
  mArea.Kind := AKind;
  mArea.Rect := ARect;
  mArea.Value := AValue;
  FAreas.Add(mArea);
end;

procedure TAtlasComponentSearchWindow.Layout;
var
  mBody: TRect;
begin
  mBody := Rect(0, HeaderHeight + ChipHeight, ClientWidth, ClientHeight - FooterHeight - ActionHeight);
  FPreviewRect := TRect.Empty;
  if FPreviewVisible then
  begin
    FPreviewRect := Rect(mBody.Right - Min(S(320), mBody.Width div 2), mBody.Top, mBody.Right, mBody.Bottom);
    mBody.Right := FPreviewRect.Left;
  end;
  FListRect := mBody;
end;

procedure TAtlasComponentSearchWindow.Resize;
begin
  inherited;
  if Length(FRowTops) > 0 then
    EnsureVisible;
  Invalidate;
end;

function TAtlasComponentSearchWindow.DrawHighlighted(const AText: string; const ARect: TRect; ABase: TAtlasColor;
  AMatch: Boolean): Integer;
var
  mPos, mLength, mX: Integer;
  mParts: array[0..2] of string;
  mPart: Integer;
  mRect: TRect;
begin
  mPos := 0;
  mLength := Length(Trim(FPattern));
  if AMatch and (mLength > 0) then
    mPos := Pos(LowerCase(Trim(FPattern)), LowerCase(AText));
  if mPos > 0 then
  begin
    mParts[0] := Copy(AText, 1, mPos - 1);
    mParts[1] := Copy(AText, mPos, mLength);
    mParts[2] := Copy(AText, mPos + mLength, MaxInt);
  end
  else
  begin
    mParts[0] := AText;
    mParts[1] := '';
    mParts[2] := '';
  end;
  mX := ARect.Left;
  for mPart := 0 to 2 do
  begin
    if (mParts[mPart] = '') or (mX >= ARect.Right) then
      Continue;
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

procedure TAtlasComponentSearchWindow.DrawChip(var X: Integer; Y: Integer; const ACaption: string; AOn: Boolean;
  AValue: Integer);
var
  mChip: TRect;
begin
  mChip := Rect(X, Y, X + Canvas.TextWidth(ACaption) + S(16), Y + S(22));
  if mChip.Right > ClientWidth - S(10) then
    Exit;
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

procedure TAtlasComponentSearchWindow.DrawHeader;
var
  mInput, mSegment: TRect;
  mX, mSegmentWidth: Integer;
  mText: string;
  mGrouping: TAtlasDesignerGrouping;
begin
  Canvas.Font.Assign(FUIFont);
  mSegmentWidth := 0;
  mX := ClientWidth - S(10);
  if not FOptions.Compact then
  begin
    // Umschalter Hierarchie / Klasse / Flach rechts.
    for mGrouping := Low(TAtlasDesignerGrouping) to High(TAtlasDesignerGrouping) do
      mSegmentWidth := Max(mSegmentWidth, Canvas.TextWidth(GroupingCaption(mGrouping)) + S(20));
    mX := ClientWidth - S(10) - 3 * mSegmentWidth;
    for mGrouping := Low(TAtlasDesignerGrouping) to High(TAtlasDesignerGrouping) do
    begin
      mSegment := Rect(mX, S(9), mX + mSegmentWidth, HeaderHeight - S(9));
      if mGrouping = FGrouping then
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
      Inc(mX, mSegmentWidth);
    end;
    mX := ClientWidth - S(20) - 3 * mSegmentWidth;
  end;
  mInput := Rect(S(10), S(7), mX, HeaderHeight - S(7));
  Canvas.Pen.Color := C(FColors.Accent);
  Canvas.Brush.Color := C(FColors.Gutter);
  Canvas.RoundRect(mInput.Left, mInput.Top, mInput.Right, mInput.Bottom, S(8), S(8));
  InflateRect(mInput, -S(10), 0);
  Canvas.Brush.Style := bsClear;
  if FPattern = '' then
  begin
    Canvas.Font.Color := C(FColors.Muted);
    mText := TAtlasStrings.Text(TAtlasTextId.DesignerSearchPrompt);
    if FOptions.FormName <> '' then
      mText := FOptions.FormName + ': ' + mText;
  end
  else
  begin
    Canvas.Font.Color := C(FColors.Text);
    mText := FPattern + '|';
  end;
  DrawText(Canvas.Handle, PChar(mText), -1, mInput, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasComponentSearchWindow.DrawChips;
var
  mX, mY: Integer;
  mKind: TAtlasDesignerKind;
  mField: TAtlasDesignerField;
  mRect: TRect;
  mText: string;
begin
  if FOptions.Compact then
    Exit;
  Canvas.Font.Assign(FSmallFont);
  mX := S(10);
  mY := HeaderHeight + (ChipHeight - S(22)) div 2 - S(2);
  for mKind := Low(TAtlasDesignerKind) to High(TAtlasDesignerKind) do
    DrawChip(mX, mY, KindCaption(mKind), mKind = FKind, ChipKinds + Ord(mKind));
  Canvas.Pen.Color := C(FColors.Line);
  Canvas.MoveTo(mX + S(2), mY + S(3));
  Canvas.LineTo(mX + S(2), mY + S(19));
  Inc(mX, S(12));
  mText := TAtlasStrings.Text(TAtlasTextId.DesignerSearchIn);
  mRect := Rect(mX, mY, mX + Canvas.TextWidth(mText), mY + S(22));
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := C(FColors.Muted);
  DrawText(Canvas.Handle, PChar(mText), -1, mRect, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  Canvas.Brush.Style := bsSolid;
  mX := mRect.Right + S(6);
  for mField := Low(TAtlasDesignerField) to High(TAtlasDesignerField) do
    DrawChip(mX, mY, FieldCaption(mField), mField in FFields, ChipFields + Ord(mField));
end;

procedure TAtlasComponentSearchWindow.DrawRow(ARow: Integer; const ARect: TRect);
var
  mRow: TAtlasDesignerRow;
  mItem: TAtlasDesignerItem;
  mPart: TRect;
  mText: string;
  mEnd: Integer;
begin
  mRow := FRows[ARow];
  Canvas.Brush.Style := bsClear;
  if mRow.Header then
  begin
    Canvas.Font.Assign(FSmallFont);
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := C(FColors.Muted);
    mText := mRow.Caption + '   ' + IntToStr(mRow.Count);
    mPart := Rect(ARect.Left + S(10), ARect.Top, ARect.Right - S(10), ARect.Bottom);
    DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
    Canvas.Font.Style := [];
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;
  if ARow = FSelected then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := C(FColors.Selection);
    Canvas.FillRect(ARect);
    Canvas.Brush.Style := bsClear;
  end;
  mItem := FItems[mRow.Item];
  mPart := Rect(ARect.Left + S(10), ARect.Top, ARect.Right - S(10), ARect.Bottom);
  Canvas.Font.Assign(FUIFont);
  if FOptions.Compact then
  begin
    // Eine Zeile: Name, Klasse, Caption.
    mEnd := DrawHighlighted(mItem.Name, mPart, FColors.Text, TAtlasDesignerField.Name in FFields);
    Canvas.Font.Assign(FSmallFont);
    mEnd := DrawHighlighted(mItem.TypeName, Rect(mEnd + S(10), mPart.Top, mPart.Right, mPart.Bottom),
      FColors.Muted, TAtlasDesignerField.ClassName in FFields);
    if mItem.Caption <> '' then
      DrawHighlighted('„' + mItem.Caption + '“', Rect(mEnd + S(10), mPart.Top, mPart.Right, mPart.Bottom),
        FColors.Muted, TAtlasDesignerField.Caption in FFields);
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;
  // Zeile 1: Name und Caption; Zeile 2: Klasse und Elternelement.
  mEnd := DrawHighlighted(mItem.Name, Rect(mPart.Left, ARect.Top + S(2), mPart.Right, ARect.Top + S(22)),
    FColors.Text, TAtlasDesignerField.Name in FFields);
  if mItem.Caption <> '' then
    DrawHighlighted('„' + mItem.Caption + '“', Rect(mEnd + S(10), ARect.Top + S(2), mPart.Right, ARect.Top + S(22)),
      FColors.Muted, TAtlasDesignerField.Caption in FFields);
  Canvas.Font.Assign(FSmallFont);
  mEnd := DrawHighlighted(mItem.TypeName, Rect(mPart.Left, ARect.Top + S(21), mPart.Right, ARect.Bottom - S(2)),
    FColors.Muted, TAtlasDesignerField.ClassName in FFields);
  if not mItem.Visual then
    mText := TAtlasStrings.Text(TAtlasTextId.DesignerSearchNonVisual)
  else if mItem.ParentName <> '' then
    mText := mItem.ParentName
  else
    mText := FOptions.FormName;
  if mText <> '' then
    DrawHighlighted('· ' + mText, Rect(mEnd + S(8), ARect.Top + S(21), mPart.Right, ARect.Bottom - S(2)),
      FColors.Muted, False);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasComponentSearchWindow.DrawList;
var
  mRow: Integer;
  mRect: TRect;
  mClip: HRGN;
begin
  Canvas.Font.Assign(FUIFont);
  if Length(FRows) = 0 then
  begin
    Canvas.Font.Color := C(FColors.Muted);
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, '—', -1, FListRect, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;
  mClip := CreateRectRgn(FListRect.Left, FListRect.Top, FListRect.Right, FListRect.Bottom);
  try
    SelectClipRgn(Canvas.Handle, mClip);
    for mRow := 0 to High(FRows) do
    begin
      if FListRect.Top + FRowTops[mRow + 1] - FScroll <= FListRect.Top then
        Continue;
      if FListRect.Top + FRowTops[mRow] - FScroll >= FListRect.Bottom then
        Break;
      mRect := Rect(FListRect.Left + S(4), FListRect.Top + FRowTops[mRow] - FScroll, FListRect.Right - S(6),
        FListRect.Top + FRowTops[mRow + 1] - FScroll);
      DrawRow(mRow, mRect);
      AddArea(THit.Row, mRect, mRow);
    end;
  finally
    SelectClipRgn(Canvas.Handle, 0);
    DeleteObject(mClip);
  end;
end;

procedure TAtlasComponentSearchWindow.DrawMap(const AArea: TRect; const AItem: TAtlasDesignerItem);
var
  mForm, mRect: TRect;
  mScale: Double;
  mOther: TAtlasDesignerItem;

  function Map(const ABounds: TRect): TRect;
  begin
    Result := Rect(mForm.Left + Round(ABounds.Left * mScale), mForm.Top + Round(ABounds.Top * mScale),
      mForm.Left + Max(Round(ABounds.Left * mScale) + 2, Round(ABounds.Right * mScale)),
      mForm.Top + Max(Round(ABounds.Top * mScale) + 2, Round(ABounds.Bottom * mScale)));
  end;

begin
  if FOptions.FormBounds.IsEmpty then
    Exit;
  mScale := Min(AArea.Width / FOptions.FormBounds.Width, AArea.Height / FOptions.FormBounds.Height);
  mForm := Rect(AArea.Left, AArea.Top, AArea.Left + Round(FOptions.FormBounds.Width * mScale),
    AArea.Top + Round(FOptions.FormBounds.Height * mScale));
  Canvas.Brush.Color := C(FColors.Gutter);
  Canvas.Pen.Color := C(FColors.Line);
  Canvas.Rectangle(mForm);
  Canvas.Brush.Style := bsClear;
  for mOther in FItems do
    if mOther.Visual and not mOther.Bounds.IsEmpty and not SameText(mOther.Name, AItem.Name) then
    begin
      mRect := Map(mOther.Bounds);
      Canvas.Rectangle(mRect);
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

procedure TAtlasComponentSearchWindow.DrawPreview;
var
  mIndex, mTop: Integer;
  mItem: TAtlasDesignerItem;
  mArea, mLine: TRect;
  mText: string;

  procedure Head(const ACaption: string);
  begin
    Canvas.Font.Assign(FSmallFont);
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := C(FColors.Muted);
    mLine := Rect(mArea.Left, mTop, mArea.Right, mTop + S(20));
    DrawText(Canvas.Handle, PChar(ACaption), -1, mLine, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
    Canvas.Font.Style := [];
    Inc(mTop, S(20));
  end;

  procedure Line(const AText: string; AColor: TAtlasColor);
  begin
    if mTop + S(18) > mArea.Bottom then
      Exit;
    Canvas.Font.Color := C(AColor);
    mLine := Rect(mArea.Left + S(4), mTop, mArea.Right, mTop + S(18));
    DrawText(Canvas.Handle, PChar(AText), -1, mLine, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
    Inc(mTop, S(18));
  end;

begin
  if not FPreviewVisible then
    Exit;
  Canvas.Pen.Color := C(FColors.Line);
  Canvas.MoveTo(FPreviewRect.Left, FPreviewRect.Top);
  Canvas.LineTo(FPreviewRect.Left, FPreviewRect.Bottom);
  mIndex := SelectedItem;
  if mIndex < 0 then
    Exit;
  mItem := FItems[mIndex];
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
  Line(mItem.TypeName, FColors.Muted);
  Inc(mTop, S(6));
  // Lage: Karte des Formulars, Position und Größe.
  Head(TAtlasStrings.Text(TAtlasTextId.DesignerSearchPosition));
  DrawMap(Rect(mArea.Left, mTop, mArea.Right, mTop + S(120)), mItem);
  Canvas.Brush.Style := bsClear;
  if not FOptions.FormBounds.IsEmpty then
    Inc(mTop, S(126));
  Canvas.Font.Assign(FSmallFont);
  if not mItem.Visual then
    mText := TAtlasStrings.Text(TAtlasTextId.DesignerSearchNonVisual)
  else
    mText := Format('%d, %d · %d × %d', [mItem.Bounds.Left, mItem.Bounds.Top, mItem.Bounds.Width,
      mItem.Bounds.Height]);
  if mItem.ParentName <> '' then
    mText := mText + ' · ' + mItem.ParentName;
  Line(mText, FColors.Text);
  Inc(mTop, S(6));
  if Length(mItem.Properties) > 0 then
  begin
    Head(TAtlasStrings.Text(TAtlasTextId.DesignerSearchProperties));
    Canvas.Font.Assign(FSmallFont);
    for mText in mItem.Properties do
      Line(mText, FColors.Text);
    Inc(mTop, S(6));
  end;
  Head(TAtlasStrings.Text(TAtlasTextId.DesignerSearchEvents));
  Canvas.Font.Assign(FSmallFont);
  if Length(mItem.Events) = 0 then
    Line(TAtlasStrings.Text(TAtlasTextId.DesignerSearchNoEvents), FColors.Muted);
  for mText in mItem.Events do
    Line(mText, FColors.Text);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasComponentSearchWindow.DrawActions;
var
  mBar, mButton: TRect;
  mX: Integer;
  mAction: TAtlasComponentSearchAction;
  mText: string;
  mEnabled: Boolean;
begin
  if FOptions.Compact then
    Exit;
  mBar := Rect(0, ClientHeight - FooterHeight - ActionHeight, ClientWidth, ClientHeight - FooterHeight);
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
      Break;
    mEnabled := ActionEnabled(mAction);
    if (mAction = TAtlasComponentSearchAction.Select) and mEnabled then
    begin
      Canvas.Brush.Color := C(FColors.Accent);
      Canvas.Pen.Color := C(FColors.Accent);
      Canvas.Font.Color := C(FColors.Surface);
    end
    else
    begin
      Canvas.Brush.Color := C(FColors.Gutter);
      Canvas.Pen.Color := C(FColors.Line);
      if mEnabled then
        Canvas.Font.Color := C(FColors.Text)
      else
        Canvas.Font.Color := C(FColors.Muted);
    end;
    Canvas.RoundRect(mButton.Left, mButton.Top, mButton.Right, mButton.Bottom, S(6), S(6));
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(mText), -1, mButton, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
    AddArea(THit.Action, mButton, Ord(mAction));
    mX := mButton.Right + S(6);
  end;
end;

procedure TAtlasComponentSearchWindow.DrawFooter;
var
  mBar, mPart: TRect;
  mText: string;
begin
  mBar := Rect(0, ClientHeight - FooterHeight, ClientWidth, ClientHeight);
  Canvas.Brush.Color := C(FColors.Gutter);
  Canvas.FillRect(mBar);
  Canvas.Font.Assign(FSmallFont);
  Canvas.Font.Color := C(FColors.Muted);
  Canvas.Brush.Style := bsClear;
  mText := TAtlasStrings.Fmt(TAtlasTextId.DesignerSearchCount, [Length(FHits), Length(FItems)]);
  mPart := Rect(mBar.Right - S(10) - Canvas.TextWidth(mText), mBar.Top, mBar.Right - S(10), mBar.Bottom);
  DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  if FOptions.Compact then
    mText := TAtlasStrings.Text(TAtlasTextId.DesignerSearchKeysPopup)
  else
    mText := TAtlasStrings.Text(TAtlasTextId.DesignerSearchKeys);
  mPart := Rect(mBar.Left + S(10), mBar.Top, mPart.Left - S(16), mBar.Bottom);
  DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasComponentSearchWindow.Paint; // lsp-ignore: component-missing-inherited -- zeichnet die ganze Fläche
begin
  FAreas.Clear;
  Layout;
  Canvas.Brush.Color := C(FColors.Surface);
  Canvas.FillRect(ClientRect);
  DrawHeader;
  DrawChips;
  DrawList;
  DrawPreview;
  DrawActions;
  DrawFooter;
  // Rahmen in Akzentfarbe (ältere Windows-Versionen ohne Rahmenfarbe des Fenstermanagers).
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := C(FColors.Accent);
  Canvas.Rectangle(ClientRect);
  Canvas.Brush.Style := bsSolid;
end;

{ Eingabe }

function TAtlasComponentSearchWindow.RowAt(Y: Integer): Integer;
var
  mOffset, mRow: Integer;
begin
  Result := -1;
  if (Y < FListRect.Top) or (Y >= FListRect.Bottom) then
    Exit;
  mOffset := Y - FListRect.Top + FScroll;
  for mRow := 0 to High(FRows) do
    if (mOffset >= FRowTops[mRow]) and (mOffset < FRowTops[mRow + 1]) then
      Exit(mRow);
end;

function TAtlasComponentSearchWindow.HitAt(X, Y: Integer; out AArea: THitArea): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := FAreas.Count - 1 downto 0 do
    if FAreas[mIndex].Rect.Contains(Point(X, Y)) then
    begin
      AArea := FAreas[mIndex];
      Exit(True);
    end;
  AArea := Default(THitArea);
  Result := False;
end;

procedure TAtlasComponentSearchWindow.WMNCHitTest(var Message: TWMNCHitTest);
var
  mPoint: TPoint;
  mEdge: Integer;
  mArea: THitArea;
begin
  inherited;
  if FOptions.Compact then
    Exit;
  mPoint := ScreenToClient(Point(Message.XPos, Message.YPos));
  mEdge := S(6);
  if (mPoint.Y < mEdge) and (mPoint.X < mEdge) then
    Message.Result := HTTOPLEFT
  else if (mPoint.Y < mEdge) and (mPoint.X >= ClientWidth - mEdge) then
    Message.Result := HTTOPRIGHT
  else if (mPoint.Y >= ClientHeight - mEdge) and (mPoint.X < mEdge) then
    Message.Result := HTBOTTOMLEFT
  else if (mPoint.Y >= ClientHeight - mEdge) and (mPoint.X >= ClientWidth - mEdge) then
    Message.Result := HTBOTTOMRIGHT
  else if mPoint.Y < mEdge then
    Message.Result := HTTOP
  else if mPoint.Y >= ClientHeight - mEdge then
    Message.Result := HTBOTTOM
  else if mPoint.X < mEdge then
    Message.Result := HTLEFT
  else if mPoint.X >= ClientWidth - mEdge then
    Message.Result := HTRIGHT
  // Freie Stellen im Kopf verschieben das Fenster.
  else if (mPoint.Y < HeaderHeight) and not HitAt(mPoint.X, mPoint.Y, mArea) and
    ((mPoint.Y < S(7)) or (mPoint.Y > HeaderHeight - S(7))) then
    Message.Result := HTCAPTION
  else
    Message.Result := HTCLIENT;
end;

procedure TAtlasComponentSearchWindow.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  inherited;
  Message.Result := Message.Result or DLGC_WANTALLKEYS or DLGC_WANTARROWS or DLGC_WANTCHARS or DLGC_WANTTAB;
end;

procedure TAtlasComponentSearchWindow.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE:
      Close;
    VK_RETURN:
      if ssCtrl in Shift then
        Run(TAtlasComponentSearchAction.Event)
      else
        Run(TAtlasComponentSearchAction.Select);
    VK_UP:
      MoveSelection(-1);
    VK_DOWN:
      MoveSelection(1);
    VK_PRIOR:
      MoveSelection(-Max(1, FListRect.Height div EntryHeight));
    VK_NEXT:
      MoveSelection(Max(1, FListRect.Height div EntryHeight));
    VK_F4:
      if not FOptions.Compact then
      begin
        FPreviewVisible := not FPreviewVisible;
        EnsureVisible;
        Invalidate;
      end;
    VK_BACK:
      begin
        if FPattern = '' then
          Exit;
        if ssCtrl in Shift then
          SetPattern('')
        else
          SetPattern(Copy(FPattern, 1, Length(FPattern) - 1));
      end;
  else
    if (ssCtrl in Shift) and (Key = Ord('C')) then
      Run(TAtlasComponentSearchAction.CopyName)
    else if (ssCtrl in Shift) and (Key = Ord('G')) and not FOptions.Compact then
      SetGrouping(TAtlasDesignerGrouping((Ord(FGrouping) + 1) mod (Ord(High(TAtlasDesignerGrouping)) + 1)))
    else
      Exit;
  end;
  Key := 0;
end;

procedure TAtlasComponentSearchWindow.KeyPress(var Key: Char);
begin
  if Key >= ' ' then
    SetPattern(FPattern + Key);
  Key := #0;
end;

procedure TAtlasComponentSearchWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mArea: THitArea;
begin
  inherited;
  if (Button <> mbLeft) or not HitAt(X, Y, mArea) then
    Exit;
  case mArea.Kind of
    THit.Chip:
      ChipClicked(mArea.Value);
    THit.Grouping:
      SetGrouping(TAtlasDesignerGrouping(mArea.Value));
    THit.Action:
      Run(TAtlasComponentSearchAction(mArea.Value));
    THit.Row:
      if not FRows[mArea.Value].Header then
      begin
        FSelected := mArea.Value;
        EnsureVisible;
        Invalidate;
      end;
  end;
end;

procedure TAtlasComponentSearchWindow.DblClick;
var
  mPoint: TPoint;
  mRow: Integer;
begin
  inherited;
  mPoint := ScreenToClient(Mouse.CursorPos);
  mRow := RowAt(mPoint.Y);
  if (mRow >= 0) and not FRows[mRow].Header and (mPoint.X < FListRect.Right) then
  begin
    FSelected := mRow;
    Run(TAtlasComponentSearchAction.Select);
  end;
end;

function TAtlasComponentSearchWindow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FScroll := EnsureRange(FScroll - Sign(WheelDelta) * 3 * EntryHeight, 0,
    Max(0, FRowTops[Length(FRows)] - FListRect.Height));
  Invalidate;
  Result := True;
end;

end.
