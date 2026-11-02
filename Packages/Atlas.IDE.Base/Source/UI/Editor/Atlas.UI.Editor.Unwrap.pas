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
  Atlas.Core.Editor.Unwrap,
  Atlas.UI.Popup.Window;

type
  TAtlasUnwrapIndexEvent = reference to procedure(AIndex: Integer);

  TAtlasUnwrapWindow = class(TAtlasPopupWindow)
  public const
    /// <summary>Abstand unter der Schreibmarke, logische Pixel.</summary>
    Gap = 4;
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
  Atlas.UI.Popup.Accessibility;

const
  Pad = 10;
  RowGap = 4;
  Separator = '  ·  ';
  Marker = '› ';
  Dash = ' – ';

{ TAtlasUnwrapWindow }

constructor TAtlasUnwrapWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Unwrap;
  FRow := -1;
  SetAccessible(UiaListControlType, TAtlasStrings.Text(TAtlasTextId.UnwrapCommand));
end;

class function TAtlasUnwrapWindow.EntryCaption(const AEntry: TAtlasUnwrapEntry): string;
var
  Suffix: string;
begin
  Suffix := '';
  if AEntry.Kind = 'beginEnd' then
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapBeginEnd)
  else if AEntry.Kind = 'tryFinally' then
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapTryFinally)
  else if AEntry.Kind = 'tryExcept' then
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapTryExcept)
  else if (AEntry.Kind = 'ifThen') and (AEntry.VariantCount > 1) then
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapIfElse)
  else if AEntry.Kind = 'ifThen' then
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapIfThen)
  else if AEntry.Kind = 'withDo' then
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapWith)
  else if AEntry.Kind = 'forDo' then
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapFor)
  else if AEntry.Kind = 'whileDo' then
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapWhile)
  else if AEntry.Kind = 'repeatUntil' then
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapRepeat)
  else if AEntry.Kind = 'ifdef' then
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapIfDef)
  else if AEntry.Kind = 'region' then
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapRegion)
  else
    Result := AEntry.Kind;
  if AEntry.VariantKind = 'keepFinally' then
    Suffix := TAtlasStrings.Text(TAtlasTextId.UnwrapKeepFinally)
  else if AEntry.VariantKind = 'dropFinally' then
    Suffix := TAtlasStrings.Text(TAtlasTextId.UnwrapDropFinally)
  else if (AEntry.Kind = 'ifThen') and (AEntry.VariantCount > 1) and (AEntry.VariantKind = 'then') then
    Suffix := TAtlasStrings.Text(TAtlasTextId.UnwrapKeepThen)
  else if (AEntry.Kind = 'ifThen') and (AEntry.VariantKind = 'else') then
    Suffix := TAtlasStrings.Text(TAtlasTextId.UnwrapKeepElse)
  else if (AEntry.Kind = 'ifdef') and (AEntry.VariantCount > 1) and (AEntry.VariantKind = 'then') then
    Suffix := TAtlasStrings.Text(TAtlasTextId.UnwrapKeepFirst)
  else if (AEntry.Kind = 'ifdef') and (AEntry.VariantKind = 'else') then
    Suffix := TAtlasStrings.Text(TAtlasTextId.UnwrapKeepIfDefElse)
  else if AEntry.VariantKind = 'branch' then
    Suffix := TAtlasStrings.Fmt(TAtlasTextId.UnwrapKeepBranch, [AEntry.Branch + 1]);
  if Suffix <> '' then
    Result := Result + Dash + Suffix;
end;

class function TAtlasUnwrapWindow.EntryNote(const AEntry: TAtlasUnwrapEntry): string;
begin
  if AEntry.Note = 'multipleRaise' then
    Result := TAtlasStrings.Fmt(TAtlasTextId.UnwrapRaiseNote, [AEntry.NoteText])
  else if AEntry.Note = 'loopVariable' then
    Result := TAtlasStrings.Fmt(TAtlasTextId.UnwrapLoopNote, [AEntry.NoteText])
  else if AEntry.Note = 'withUnresolved' then
    Result := TAtlasStrings.Fmt(TAtlasTextId.UnwrapWithNote, [AEntry.NoteText])
  else
    Result := '';
end;

function TAtlasUnwrapWindow.Title: string;
begin
  if FCompact and (Length(FEntries) = 1) then
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapCommand) + ': ' + EntryCaption(FEntries[0])
  else
    Result := TAtlasStrings.Text(TAtlasTextId.UnwrapCommand);
end;

function TAtlasUnwrapWindow.Layout(ADraw: Boolean): TSize;
var
  X, Y, TextHeight, mWidth, Index: Integer;
  mText, Line, Note, Accept, Cancel: string;
  Entry: TAtlasUnwrapEntry;
  mTop: Integer;
begin
  Canvas.Font := UIFont;
  TextHeight := Canvas.TextHeight('Wg');
  if ADraw then
    Canvas.Brush.Style := bsClear;
  X := Scale(Pad);
  Y := Scale(Pad);
  mText := Title;
  Canvas.Font.Style := [fsBold];
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.TextOut(X, Y, mText);
  end;
  mWidth := X + Canvas.TextWidth(mText);
  Canvas.Font.Style := [];
  SetLength(FRowRects, Length(FEntries));
  for Index := 0 to High(FEntries) do
  begin
    Entry := FEntries[Index];
    FRowRects[Index] := TRect.Empty;
    Note := EntryNote(Entry);
    if not FCompact then
    begin
      Y := Y + TextHeight + Scale(RowGap);
      mTop := Y;
      X := Scale(Pad);
      mText := EntryCaption(Entry);
      if Index = FRow then
        mText := Marker + mText
      else
        X := X + Canvas.TextWidth(Marker);
      if ADraw then
      begin
        if Index = FRow then
          Canvas.Font.Color := ToColor(Colors.Accent)
        else if Entry.Available then
          Canvas.Font.Color := ToColor(Colors.Text)
        else
          Canvas.Font.Color := ToColor(Colors.Muted);
        Canvas.TextOut(X, Y, mText);
      end;
      Inc(X, Canvas.TextWidth(mText));
      Line := Separator + TAtlasStrings.Fmt(TAtlasTextId.UnwrapLine, [Entry.Line + 1]);
      if ADraw then
      begin
        Canvas.Font.Color := ToColor(Colors.Muted);
        Canvas.TextOut(X, Y, Line);
      end;
      Inc(X, Canvas.TextWidth(Line));
      mWidth := Max(mWidth, X);
      FRowRects[Index] := Rect(Scale(Pad), mTop, X, Y + TextHeight);
    end;
    if Note <> '' then
    begin
      Y := Y + TextHeight + Scale(RowGap);
      X := Scale(Pad) + 2 * Canvas.TextWidth(Marker);
      if ADraw then
      begin
        Canvas.Font.Color := ToColor(Colors.Warn);
        Canvas.TextOut(X, Y, Note);
      end;
      mWidth := Max(mWidth, X + Canvas.TextWidth(Note));
      if not FCompact then
        FRowRects[Index].Bottom := Y + TextHeight;
    end;
  end;
  // Fußzeile mit den beiden Links.
  Y := Y + TextHeight + Scale(RowGap) * 2;
  X := Scale(Pad);
  Accept := TAtlasStrings.Text(TAtlasTextId.UnwrapAccept);
  Cancel := TAtlasStrings.Text(TAtlasTextId.UnwrapCancel);
  FAcceptRect := Rect(X, Y, X + Canvas.TextWidth(Accept), Y + TextHeight);
  if ADraw then
  begin
    if FRow >= 0 then
      Canvas.Font.Color := ToColor(Colors.Accent)
    else
      Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.TextOut(X, Y, Accept);
    Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.TextOut(FAcceptRect.Right, Y, Separator);
  end;
  X := FAcceptRect.Right + Canvas.TextWidth(Separator);
  FCancelRect := Rect(X, Y, X + Canvas.TextWidth(Cancel), Y + TextHeight);
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Accent);
    Canvas.TextOut(X, Y, Cancel);
  end;
  mWidth := Max(mWidth, FCancelRect.Right);
  if ADraw then
    Canvas.Brush.Style := bsSolid;
  Result.cx := mWidth + Scale(Pad);
  Result.cy := Y + TextHeight + Scale(Pad);
end;

procedure TAtlasUnwrapWindow.ShowFor(const AEntries: TArray<TAtlasUnwrapEntry>; const APoint: TPoint);
var
  Size: TSize;
  Area: TRect;
  mLeft, mTop: Integer;
begin
  FEntries := AEntries;
  FCompact := TAtlasUnwrap.SingleEntry(FEntries);
  FRow := TAtlasUnwrap.NextAvailable(FEntries, 0, 1);
  HandleNeeded;
  Size := Layout(False);
  Area := WorkAreaAt(APoint);
  mLeft := Min(APoint.X, Area.Right - Size.cx);
  mTop := APoint.Y + Scale(Gap);
  if mTop + Size.cy > Area.Bottom then
    mTop := APoint.Y - Scale(Gap) - Size.cy;
  ShowAt(Rect(Max(mLeft, Area.Left), Max(mTop, Area.Top), Max(mLeft, Area.Left) + Size.cx,
    Max(mTop, Area.Top) + Size.cy));
  Announce(Title);
  if FRow >= 0 then
  begin
    if not FCompact then
      Announce(EntryCaption(FEntries[FRow]));
    if Assigned(FOnSelect) then
      FOnSelect(FRow);
  end;
end;

procedure TAtlasUnwrapWindow.Dismiss;
begin
  HidePopup;
end;

procedure TAtlasUnwrapWindow.Select(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FEntries)) or not FEntries[AIndex].Available or (AIndex = FRow) then
    Exit;
  FRow := AIndex;
  Invalidate;
  Announce(EntryCaption(FEntries[FRow]));
  if Assigned(FOnSelect) then
    FOnSelect(FRow);
end;

function TAtlasUnwrapWindow.MoveRow(ADelta: Integer): Boolean;
var
  Next: Integer;
begin
  Next := TAtlasUnwrap.NextAvailable(FEntries, FRow + ADelta, ADelta);
  Result := Next >= 0;
  if Result then
    Select(Next);
end;

function TAtlasUnwrapWindow.RowRect(AIndex: Integer): TRect;
begin
  Result := TRect.Empty;
  if (AIndex >= 0) and (AIndex <= High(FRowRects)) then
    Result := FRowRects[AIndex];
end;

function TAtlasUnwrapWindow.AcceptRect: TRect;
begin
  Result := FAcceptRect;
end;

procedure TAtlasUnwrapWindow.Accept;
var
  Chosen: Integer;
begin
  Chosen := FRow;
  if (Chosen < 0) or (Chosen > High(FEntries)) or not FEntries[Chosen].Available then
    Exit;
  Dismiss;
  if Assigned(FOnAccept) then
    FOnAccept(Chosen);
end;

procedure TAtlasUnwrapWindow.Cancel;
begin
  Dismiss;
  if Assigned(FOnCancel) then
    FOnCancel();
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
  Index: Integer;
  Point: TPoint;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  Point := TPoint.Create(X, Y);
  if PtInRect(FAcceptRect, Point) then
  begin
    Accept;
    Exit;
  end;
  if PtInRect(FCancelRect, Point) then
  begin
    Cancel;
    Exit;
  end;
  for Index := 0 to High(FRowRects) do
    if PtInRect(FRowRects[Index], Point) and FEntries[Index].Available then
    begin
      Select(Index);
      Accept;
      Exit;
    end;
end;

procedure TAtlasUnwrapWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
  Hot: Boolean;
  Point: TPoint;
begin
  inherited;
  Point := TPoint.Create(X, Y);
  Hot := PtInRect(FAcceptRect, Point) or PtInRect(FCancelRect, Point);
  // Überfahren wählt den Eintrag und wechselt die Vorschau.
  for Index := 0 to High(FRowRects) do
    if PtInRect(FRowRects[Index], Point) and FEntries[Index].Available then
    begin
      Hot := True;
      Select(Index);
    end;
  if Hot then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
end;

end.
