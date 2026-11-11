unit Atlas.UI.Editor.Unwrap;

// Umschließung entfernen (#657), Fensterteil (nur VCL): kleine Liste an der
// Schreibmarke, das innerste Konstrukt zuerst.
//   Umschließung entfernen
//   › try … finally … end – finally-Teil behalten   Zeile 12
//     try … finally … end – finally-Teil verwerfen  Zeile 12
//     for … do                                      Zeile 10
//       Bezüge auf die Schleifenvariable I bleiben stehen.
//   Entfernen (Enter)  ·  Abbrechen (Esc)
// Überfahren mit der Maus oder ↑/↓ wählt einen Eintrag und meldet ihn über
// OnSelect (Vorschau im Editor); die IDE-Seite leitet die Tasten weiter, das
// Fenster bekommt nie den Fokus. Nicht übernehmbare Einträge (with nicht
// auflösbar) stehen gedämpft mit Grund da und lassen sich nicht wählen. Bei
// nur einem Eintrag entfällt die Liste: Überschrift ist dann das Konstrukt.

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
  Atlas.Core.Editor.Unwrap,
  Atlas.UI.Popup.Window;

type
  TAtlasUnwrapIndexEvent = reference to procedure(AIndex: Integer);

  TAtlasUnwrapWindow = class(TAtlasPopupWindow)
  public const
    /// <summary>Abstand unter der Schreibmarke, logische Pixel.</summary>
    cGap = 4;
  private
    FEntries: TArray<TAtlasUnwrapEntry>;
    FRow: Integer;
    FCompact: Boolean;
    FRowRects: TArray<TRect>;
    FAcceptRect: TRect;
    FCancelRect: TRect;
    FOnSelect: TAtlasUnwrapIndexEvent;
    FOnAccept: TAtlasUnwrapIndexEvent;
    FOnCancel: TProc;
    function Layout(ADraw: Boolean): TSize;
    procedure LayoutRow(ADraw: Boolean; AIndex, ATextHeight: Integer; var AY, AWidth: Integer);
    procedure LayoutEntry(ADraw: Boolean; AIndex, ATextHeight: Integer; var AY, AWidth: Integer);
    procedure LayoutFooter(ADraw: Boolean; AY, ATextHeight: Integer; var AWidth: Integer);
    procedure Put(ADraw: Boolean; AX, AY: Integer; const AText: string; AColor: TAtlasColor);
    function Title: string;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>„try … finally … end – finally-Teil behalten“ usw.</summary>
    class function EntryCaption(const AEntry: TAtlasUnwrapEntry): string; static;
    /// <summary>Hinweis zum Eintrag (raise, Schleifenvariable, with); '' ohne.</summary>
    class function EntryNote(const AEntry: TAtlasUnwrapEntry): string; static;
    /// <summary>Zeigt AEntries unter APoint (Bildschirm) und wählt den ersten übernehmbaren Eintrag.</summary>
    procedure ShowFor(const AEntries: TArray<TAtlasUnwrapEntry>; const APoint: TPoint);
    procedure Dismiss;
    /// <summary>Nächster bzw. voriger übernehmbarer Eintrag; False ohne solche.</summary>
    function MoveRow(ADelta: Integer): Boolean;
    /// <summary>Eintrag AIndex wählen und melden; nicht übernehmbare bleiben ohne Wirkung.</summary>
    procedure Select(AIndex: Integer);
    /// <summary>Fläche von Eintrag AIndex; leer in der Kurzform oder ohne den Eintrag.</summary>
    function RowRect(AIndex: Integer): TRect;
    function AcceptRect: TRect;
    /// <summary>Gewählten Eintrag übernehmen (OnAccept); ohne Wahl nichts.</summary>
    procedure Accept;
    procedure Cancel;
    property Entries: TArray<TAtlasUnwrapEntry> read FEntries;
    property Row: Integer read FRow;
    /// <summary>Nur ein Eintrag: ohne Liste.</summary>
    property Compact: Boolean read FCompact;
    property Caption: string read Title;
    property OnSelect: TAtlasUnwrapIndexEvent read FOnSelect write FOnSelect;
    property OnAccept: TAtlasUnwrapIndexEvent read FOnAccept write FOnAccept;
    property OnCancel: TProc read FOnCancel write FOnCancel;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Editor.Strings,
  Atlas.UI.Popup.Accessibility;

const
  cPad = 10;
  cRowGap = 4;
  cSeparator = '  ·  ';
  cMarker = '› ';
  cDash = ' – ';

{ TAtlasUnwrapWindow }

constructor TAtlasUnwrapWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Unwrap;
  FRow := -1;
  SetAccessible(cUiaListControlType, TAtlasStrings.Text(TAtlasTextId.UnwrapCommand));
end;

type
  TKindText = record
    Kind: string;
    Text: TAtlasTextId;
  end;

const
  cKindTexts: array[0..9] of TKindText = (
    (Kind: 'beginEnd'; Text: TAtlasTextId.UnwrapBeginEnd),
    (Kind: 'tryFinally'; Text: TAtlasTextId.UnwrapTryFinally),
    (Kind: 'tryExcept'; Text: TAtlasTextId.UnwrapTryExcept),
    (Kind: 'ifThen'; Text: TAtlasTextId.UnwrapIfThen),
    (Kind: 'withDo'; Text: TAtlasTextId.UnwrapWith),
    (Kind: 'forDo'; Text: TAtlasTextId.UnwrapFor),
    (Kind: 'whileDo'; Text: TAtlasTextId.UnwrapWhile),
    (Kind: 'repeatUntil'; Text: TAtlasTextId.UnwrapRepeat),
    (Kind: 'ifdef'; Text: TAtlasTextId.UnwrapIfDef),
    (Kind: 'region'; Text: TAtlasTextId.UnwrapRegion));

/// <summary>„try … finally … end“ usw.; unbekannte Arten stehen, wie sie heißen.</summary>
function KindCaption(const AEntry: TAtlasUnwrapEntry): string;
var
  mItem: TKindText;
begin
  if (AEntry.Kind = 'ifThen') and (AEntry.VariantCount > 1) then
  begin
    Exit(TAtlasEditorStrings.Text(TAtlasEditorTextId.UnwrapIfElse));
  end;
  for mItem in cKindTexts do
  begin
    if mItem.Kind = AEntry.Kind then
    begin
      Exit(TAtlasStrings.Text(mItem.Text));
    end;
  end;
  Result := AEntry.Kind;
end;

/// <summary>Welcher Zweig einer Bedingung bleibt: AFirst (then bzw. erster Zweig, nur bei mehreren Varianten) oder
/// AElse; '' sonst.</summary>
function BranchSuffix(const AEntry: TAtlasUnwrapEntry; AFirst, AElse: TAtlasTextId): string;
begin
  Result := '';
  if (AEntry.VariantCount > 1) and (AEntry.VariantKind = 'then') then
  begin
    Result := TAtlasStrings.Text(AFirst);
  end
  else if AEntry.VariantKind = 'else' then
  begin
    Result := TAtlasStrings.Text(AElse);
  end;
end;

/// <summary>Was von der Variante bleibt („finally-Teil behalten“ usw.); '' ohne.</summary>
function VariantSuffix(const AEntry: TAtlasUnwrapEntry): string;
begin
  if AEntry.VariantKind = 'keepFinally' then
  begin
    Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.UnwrapKeepFinally);
  end
  else if AEntry.VariantKind = 'dropFinally' then
  begin
    Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.UnwrapDropFinally);
  end
  else if AEntry.Kind = 'ifThen' then
  begin
    Result := BranchSuffix(AEntry, TAtlasTextId.UnwrapKeepThen, TAtlasTextId.UnwrapKeepElse);
  end
  else if AEntry.Kind = 'ifdef' then
  begin
    Result := BranchSuffix(AEntry, TAtlasTextId.UnwrapKeepFirst, TAtlasTextId.UnwrapKeepIfDefElse);
  end
  else
  begin
    Result := '';
  end;
  if (Result = '') and (AEntry.VariantKind = 'branch') then
  begin
    Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.UnwrapKeepBranch, [AEntry.Branch + 1]);
  end;
end;

class function TAtlasUnwrapWindow.EntryCaption(const AEntry: TAtlasUnwrapEntry): string;
var
  mSuffix: string;
begin
  Result := KindCaption(AEntry);
  mSuffix := VariantSuffix(AEntry);
  if mSuffix <> '' then
  begin
    Result := Result + cDash + mSuffix;
  end;
end;

class function TAtlasUnwrapWindow.EntryNote(const AEntry: TAtlasUnwrapEntry): string;
begin
  if AEntry.Note = 'multipleRaise' then
  begin
    Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.UnwrapRaiseNote, [AEntry.NoteText]);
  end
  else if AEntry.Note = 'loopVariable' then
  begin
    Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.UnwrapLoopNote, [AEntry.NoteText]);
  end
  else if AEntry.Note = 'withUnresolved' then
  begin
    Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.UnwrapWithNote, [AEntry.NoteText]);
  end
  else
  begin
    Result := '';
  end;
end;

function TAtlasUnwrapWindow.Title: string;
begin
  if FCompact and (Length(FEntries) = 1) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapCommand) + ': ' + EntryCaption(FEntries[0]);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapCommand);
  end;
end;

procedure TAtlasUnwrapWindow.Put(ADraw: Boolean; AX, AY: Integer; const AText: string; AColor: TAtlasColor);
begin
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(AColor);
    Canvas.TextOut(AX, AY, AText);
  end;
end;

/// <summary>Zeile von Eintrag AIndex unter AY: Beschriftung (gewählt mit Marke) und Zeilennummer.</summary>
procedure TAtlasUnwrapWindow.LayoutRow(ADraw: Boolean; AIndex, ATextHeight: Integer; var AY, AWidth: Integer);
var
  mEntry: TAtlasUnwrapEntry;
  mX, mTop: Integer;
  mText, mLine: string;
  mColor: TAtlasColor;
begin
  mEntry := FEntries[AIndex];
  AY := AY + ATextHeight + Scale(cRowGap);
  mTop := AY;
  mX := Scale(cPad);
  mText := EntryCaption(mEntry);
  mColor := Colors.Muted;
  if mEntry.Available then
  begin
    mColor := Colors.Text;
  end;
  if AIndex = FRow then
  begin
    mText := cMarker + mText;
    mColor := Colors.Accent;
  end
  else
  begin
    mX := mX + Canvas.TextWidth(cMarker);
  end;
  Put(ADraw, mX, AY, mText, mColor);
  Inc(mX, Canvas.TextWidth(mText));
  mLine := cSeparator + TAtlasEditorStrings.Fmt(TAtlasEditorTextId.UnwrapLine, [mEntry.Line + 1]);
  Put(ADraw, mX, AY, mLine, Colors.Muted);
  Inc(mX, Canvas.TextWidth(mLine));
  AWidth := Max(AWidth, mX);
  FRowRects[AIndex] := Rect(Scale(cPad), mTop, mX, AY + ATextHeight);
end;

/// <summary>Eintrag AIndex: Zeile (nicht in der Kurzform) und Hinweis darunter.</summary>
procedure TAtlasUnwrapWindow.LayoutEntry(ADraw: Boolean; AIndex, ATextHeight: Integer; var AY, AWidth: Integer);
var
  mNote: string;
  mX: Integer;
begin
  FRowRects[AIndex] := TRect.Empty;
  if not FCompact then
  begin
    LayoutRow(ADraw, AIndex, ATextHeight, AY, AWidth);
  end;
  mNote := EntryNote(FEntries[AIndex]);
  if mNote = '' then
  begin
    Exit;
  end;
  AY := AY + ATextHeight + Scale(cRowGap);
  mX := Scale(cPad) + 2 * Canvas.TextWidth(cMarker);
  Put(ADraw, mX, AY, mNote, Colors.Warn);
  AWidth := Max(AWidth, mX + Canvas.TextWidth(mNote));
  if not FCompact then
  begin
    FRowRects[AIndex].Bottom := AY + ATextHeight;
  end;
end;

/// <summary>Fußzeile mit den beiden Links in Zeile AY.</summary>
procedure TAtlasUnwrapWindow.LayoutFooter(ADraw: Boolean; AY, ATextHeight: Integer; var AWidth: Integer);
var
  mX: Integer;
  mAccept, mCancel: string;
  mColor: TAtlasColor;
begin
  mX := Scale(cPad);
  mAccept := TAtlasEditorStrings.Text(TAtlasEditorTextId.UnwrapAccept);
  mCancel := TAtlasEditorStrings.Text(TAtlasEditorTextId.UnwrapCancel);
  FAcceptRect := Rect(mX, AY, mX + Canvas.TextWidth(mAccept), AY + ATextHeight);
  mColor := Colors.Muted;
  if FRow >= 0 then
  begin
    mColor := Colors.Accent;
  end;
  Put(ADraw, mX, AY, mAccept, mColor);
  Put(ADraw, FAcceptRect.Right, AY, cSeparator, Colors.Muted);
  mX := FAcceptRect.Right + Canvas.TextWidth(cSeparator);
  FCancelRect := Rect(mX, AY, mX + Canvas.TextWidth(mCancel), AY + ATextHeight);
  Put(ADraw, mX, AY, mCancel, Colors.Accent);
  AWidth := Max(AWidth, FCancelRect.Right);
end;

function TAtlasUnwrapWindow.Layout(ADraw: Boolean): TSize;
var
  mY, mWidth, mIndex, mTextHeight: Integer;
  mTitle: string;
begin
  Canvas.Font := UIFont;
  mTextHeight := Canvas.TextHeight('Wg');
  if ADraw then
  begin
    Canvas.Brush.Style := bsClear;
  end;
  mY := Scale(cPad);
  mTitle := Title;
  Canvas.Font.Style := [fsBold];
  Put(ADraw, Scale(cPad), mY, mTitle, Colors.Text);
  mWidth := Scale(cPad) + Canvas.TextWidth(mTitle);
  Canvas.Font.Style := [];
  SetLength(FRowRects, Length(FEntries));
  for mIndex := 0 to High(FEntries) do
  begin
    LayoutEntry(ADraw, mIndex, mTextHeight, mY, mWidth);
  end;
  mY := mY + mTextHeight + Scale(cRowGap) * 2;
  LayoutFooter(ADraw, mY, mTextHeight, mWidth);
  if ADraw then
  begin
    Canvas.Brush.Style := bsSolid;
  end;
  Result.cx := mWidth + Scale(cPad);
  Result.cy := mY + mTextHeight + Scale(cPad);
end;

procedure TAtlasUnwrapWindow.ShowFor(const AEntries: TArray<TAtlasUnwrapEntry>; const APoint: TPoint);
var
  mSize: TSize;
  mArea: TRect;
  mLeft, mTop: Integer;
begin
  FEntries := AEntries;
  FCompact := TAtlasUnwrap.SingleEntry(FEntries);
  FRow := TAtlasUnwrap.NextAvailable(FEntries, 0, 1);
  HandleNeeded;
  mSize := Layout(False);
  mArea := WorkAreaAt(APoint);
  mLeft := Min(APoint.X, mArea.Right - mSize.cx);
  mTop := APoint.Y + Scale(cGap);
  if mTop + mSize.cy > mArea.Bottom then
  begin
    mTop := APoint.Y - Scale(cGap) - mSize.cy;
  end;
  ShowAt(Rect(Max(mLeft, mArea.Left), Max(mTop, mArea.Top), Max(mLeft, mArea.Left) + mSize.cx,
    Max(mTop, mArea.Top) + mSize.cy));
  Announce(Title);
  if FRow >= 0 then
  begin
    if not FCompact then
    begin
      Announce(EntryCaption(FEntries[FRow]));
    end;
    if Assigned(FOnSelect) then
    begin
      FOnSelect(FRow);
    end;
  end;
end;

procedure TAtlasUnwrapWindow.Dismiss;
begin
  HidePopup;
end;

procedure TAtlasUnwrapWindow.Select(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FEntries)) or not FEntries[AIndex].Available or (AIndex = FRow) then
  begin
    Exit;
  end;
  FRow := AIndex;
  Invalidate;
  Announce(EntryCaption(FEntries[FRow]));
  if Assigned(FOnSelect) then
  begin
    FOnSelect(FRow);
  end;
end;

function TAtlasUnwrapWindow.MoveRow(ADelta: Integer): Boolean;
var
  mNext: Integer;
begin
  mNext := TAtlasUnwrap.NextAvailable(FEntries, FRow + ADelta, ADelta);
  Result := mNext >= 0;
  if Result then
  begin
    Select(mNext);
  end;
end;

function TAtlasUnwrapWindow.RowRect(AIndex: Integer): TRect;
begin
  Result := TRect.Empty;
  if (AIndex >= 0) and (AIndex <= High(FRowRects)) then
  begin
    Result := FRowRects[AIndex];
  end;
end;

function TAtlasUnwrapWindow.AcceptRect: TRect;
begin
  Result := FAcceptRect;
end;

procedure TAtlasUnwrapWindow.Accept;
var
  mChosen: Integer;
begin
  mChosen := FRow;
  if (mChosen < 0) or (mChosen > High(FEntries)) or not FEntries[mChosen].Available then
  begin
    Exit;
  end;
  Dismiss;
  if Assigned(FOnAccept) then
  begin
    FOnAccept(mChosen);
  end;
end;

procedure TAtlasUnwrapWindow.Cancel;
begin
  Dismiss;
  if Assigned(FOnCancel) then
  begin
    FOnCancel();
  end;
end;

procedure TAtlasUnwrapWindow.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Layout(True);
  PaintBorder;
end;

procedure TAtlasUnwrapWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
  mPoint: TPoint;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mPoint := TPoint.Create(X, Y);
  if PtInRect(FAcceptRect, mPoint) then
  begin
    Accept;
    Exit;
  end;
  if PtInRect(FCancelRect, mPoint) then
  begin
    Cancel;
    Exit;
  end;
  for mIndex := 0 to High(FRowRects) do
  begin
    if PtInRect(FRowRects[mIndex], mPoint) and FEntries[mIndex].Available then
    begin
      Select(mIndex);
      Accept;
      Exit;
    end;
  end;
end;

procedure TAtlasUnwrapWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
  mHot: Boolean;
  mPoint: TPoint;
begin
  inherited;
  mPoint := TPoint.Create(X, Y);
  mHot := PtInRect(FAcceptRect, mPoint) or PtInRect(FCancelRect, mPoint);
  // Überfahren wählt den Eintrag und wechselt die Vorschau.
  for mIndex := 0 to High(FRowRects) do
  begin
    if PtInRect(FRowRects[mIndex], mPoint) and FEntries[mIndex].Available then
    begin
      mHot := True;
      Select(mIndex);
    end;
  end;
  if mHot then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
end;

end.
