unit Atlas.IDE.Notes.Gutter;

// Persönliche Notizen in der Rinne (#545), Zeichenschicht wie #401:
// - Zeichnen: am Ende des Zeichnens jeder Rinnenzeile (letzte Stufe von
//   TPaintGutterStage, nach der IDE) ein kleines Notizblatt links in der
//   Rinne, wenn an der Zeile eine Notiz steht und der Zeileninhalt noch zum
//   Anker passt (sonst wartet das Symbol auf die nächste Verankerung).
//   Rechteck und Zeile jeder gezeichneten Rinnenzeile werden gemerkt.
// - Überfahren des Symbols zeigt nach HoverMs den Text (TAtlasNoteTip), bei
//   mehreren Notizen an der Zeile alle untereinander.
// - Rechtsklick in die Rinne merkt die Zeile für „Notiz an dieser Zeile…“
//   im Atlas-Untermenü des Kontextmenüs (TAtlasIdeNotes.RememberGutterLine);
//   jeder andere Klick vergisst sie.
// - Ein Zeitgeber verankert die Notizen der Datei im oberen Editor nach
//   einer Tipp-Pause (QuietMs) neu, damit sie eingefügten und gelöschten
//   Zeilen folgen, und zeichnet den Editor bei Bedarf neu.
// Abschaltbar über die Einstellung „Notizen“; Sicherung über
// TAtlasFeature.Notes (#493).

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Notes.Store,
  Atlas.UI.Notes.Tip;

type
  TAtlasIdeNotesGutter = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedGutterStages: TPaintGutterStages; override;
    end;
    /// <summary>Gezeichnete Rinnenzeile (Koordinaten des Editors).</summary>
    TRow = record
      FileName: string;
      /// <summary>0-basiert.</summary>
      Line: Integer;
      Gutter: TRect;
      /// <summary>Symbol; leer ohne Notiz.</summary>
      Icon: TRect;
      TopRow: Integer;
    end;
  private const
    QuietMs = 300;
    HoverMs = 300;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FTimer: TTimer;
    FTip: TAtlasNoteTip;
    /// <summary>Je Bildschirmzeile des Editors (EditorLineNum) die zuletzt gezeichnete Rinnenzeile.</summary>
    FRows: TDictionary<Integer, TRow>;
    FFileName: string;
    FText: string;
    FTrackedText: string;
    FChangedAt: UInt64;
    /// <summary>Symbol unter der Maus: Zeile, seit wann, Rechteck auf dem Bildschirm.</summary>
    FHover: TRow;
    FHovering: Boolean;
    FHoverSince: UInt64;
    FHoverScreen: TRect;
    FShowing: Boolean;
    function Wanted: Boolean;
    function TopView: IOTAEditView;
    function RowAt(X, Y: Integer; out ARow: TRow): Boolean;
    procedure Tick(Sender: TObject);
    procedure Track;
    procedure CheckHover;
    procedure ShowTip;
    procedure HideTip;
    procedure PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    class procedure Invalidate; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Rechteck des Symbols in einer Rinnenzeile AGutter: links, senkrecht mittig, Höhe nach Zeile.</summary>
    class function IconRect(const AGutter: TRect): TRect; static;
    /// <summary>Überschrift und Text des Tooltips für die Notizen einer Zeile.</summary>
    class procedure TipText(const ANotes: TArray<TAtlasNote>; out ATitle, AText: string); static;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.DateUtils,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Notes.Anchor,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Strings,
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Editor.Style,
  Atlas.IDE.Notes.Service,
  Atlas.IDE.Settings.Store;

{ TAtlasIdeNotesGutter.TEvents }

function TAtlasIdeNotesGutter.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintGutterEvents, cevMouseEvents];
end;

function TAtlasIdeNotesGutter.TEvents.AllowedGutterStages: TPaintGutterStages;
begin
  // Nur die letzte Stufe: Das Symbol liegt über dem, was die IDE gezeichnet hat.
  Result := [High(TPaintGutterStage)];
end;

{ TAtlasIdeNotesGutter }

constructor TAtlasIdeNotesGutter.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FRows := TDictionary<Integer, TRow>.Create;
  FTip := TAtlasNoteTip.Create(nil);
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintGutter := PaintGutter;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 100;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeNotesGutter.Destroy;
var
  Services: INTACodeEditorServices;
begin
  FTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintGutter := nil;
  FEvents.OnEditorMouseMove := nil;
  FEvents.OnEditorMouseDown := nil;
  FEventsRef := nil;
  FTip.Free;
  FRows.Free;
  inherited Destroy;
end;

class procedure TAtlasIdeNotesGutter.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.InvalidateTopEditor;
end;

function TAtlasIdeNotesGutter.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Notes and not TAtlasGuard.Disabled(TAtlasFeature.Notes);
end;

function TAtlasIdeNotesGutter.TopView: IOTAEditView;
var
  Editors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Result := Editors.TopView;
end;

class function TAtlasIdeNotesGutter.IconRect(const AGutter: TRect): TRect;
var
  Height, Width, Top: Integer;
begin
  Height := Max(6, Min(AGutter.Height - 4, 14));
  Width := Max(5, (Height * 4) div 5);
  Top := AGutter.Top + (AGutter.Height - Height) div 2;
  Result := TRect.Create(AGutter.Left + 2, Top, AGutter.Left + 2 + Width, Top + Height);
end;

class procedure TAtlasIdeNotesGutter.TipText(const ANotes: TArray<TAtlasNote>; out ATitle, AText: string);
var
  Note: TAtlasNote;
  Stamp: TDateTime;
begin
  ATitle := '';
  AText := '';
  if Length(ANotes) = 0 then
    Exit;
  if Length(ANotes) = 1 then
  begin
    Stamp := ANotes[0].Changed;
    if Stamp = 0 then
      Stamp := ANotes[0].Created;
    ATitle := TAtlasStrings.Fmt(TAtlasTextId.NotesTipTitle, [DateToStr(TTimeZone.Local.ToLocalTime(Stamp))]);
    AText := ANotes[0].Text;
    Exit;
  end;
  ATitle := TAtlasStrings.Fmt(TAtlasTextId.NotesTipMore, [Length(ANotes)]);
  for Note in ANotes do
  begin
    if AText <> '' then
      AText := AText + #10#10;
    AText := AText + Note.Text;
  end;
end;

procedure TAtlasIdeNotesGutter.Tick(Sender: TObject);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Notes) then
    Exit;
  try
    if not Wanted then
    begin
      HideTip;
      if FShowing then
      begin
        FShowing := False;
        FRows.Clear;
        Invalidate;
      end;
      Exit;
    end;
    Track;
    CheckHover;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Notes, E);
  end;
end;

procedure TAtlasIdeNotesGutter.Track;
var
  View: IOTAEditView;
  Text: string;
begin
  View := TopView;
  if (View = nil) or (View.Buffer = nil) or (View.Buffer.FileName = '') then
    Exit;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  if not SameText(FFileName, View.Buffer.FileName) then
  begin
    // Andere Datei vorn: gleich zuordnen, damit ihre Symbole erscheinen.
    FFileName := View.Buffer.FileName;
    FText := Text;
    FTrackedText := Text;
    FRows.Clear;
    HideTip;
    TAtlasIdeNotes.Track(FFileName, Text);
    FShowing := True;
    Invalidate;
    Exit;
  end;
  if FText <> Text then
  begin
    FText := Text;
    FChangedAt := TThread.GetTickCount64;
    Exit;
  end;
  // Nach der Tipp-Pause neu verankern; nur Dateien mit Notizen kosten etwas.
  if (FTrackedText = FText) or (TThread.GetTickCount64 - FChangedAt < QuietMs) then
    Exit;
  FTrackedText := FText;
  if not TAtlasIdeNotes.HasNotes(FFileName) then
    Exit;
  TAtlasIdeNotes.Track(FFileName, FText);
  // Auch ohne Bewegung neu zeichnen: Die Zeile einer Notiz wurde vielleicht nur bearbeitet.
  Invalidate;
end;

function TAtlasIdeNotesGutter.RowAt(X, Y: Integer; out ARow: TRow): Boolean;
var
  Row: TRow;
  View: IOTAEditView;
begin
  ARow := Default(TRow);
  ARow.Line := -1;
  Result := False;
  View := TopView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  for Row in FRows.Values do
    if PtInRect(Row.Gutter, Point(X, Y)) then
    begin
      // Nur, wenn die Zeile noch dort steht: gleiche Datei, nicht gescrollt.
      if not SameText(Row.FileName, View.Buffer.FileName) or (Row.TopRow <> View.TopRow) then
        Exit;
      ARow := Row;
      Exit(True);
    end;
end;

procedure TAtlasIdeNotesGutter.PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Row: TRow;
  Notes: TArray<TAtlasNote>;
  LineState: INTACodeEditorLineState;
  Canvas: TCanvas;
  Icon: TRect;
  Colors: TAtlasColors;
  Back: TAtlasColor;
  Sample: COLORREF;
  OldBrush: TBrush;
  OldPen: TPen;
  Fold, Step, Y: Integer;
begin
  if BeforeEvent or (Stage <> High(TPaintGutterStage)) or (Context = nil) then
    Exit;
  if TAtlasGuard.Disabled(TAtlasFeature.Notes) then
    Exit;
  try
    if not Wanted or (Context.EditView = nil) then
      Exit;
    Row := Default(TRow);
    Row.FileName := Context.FileName;
    Row.Line := Context.LogicalLineNum - 1;
    Row.Gutter := Rect;
    Row.TopRow := Context.EditView.TopRow;
    Notes := TAtlasIdeNotes.NotesAt(Context.FileName, Row.Line);
    // Nur, wenn die Zeile im Editor noch zum Anker passt; nach dem Tippen folgt die Verankerung.
    LineState := Context.LineState;
    if (Length(Notes) > 0) and (LineState <> nil) and
      (TAtlasNoteAnchors.Normalize(LineState.Text) <> Notes[0].Anchor.Text) then
      Notes := nil;
    if Length(Notes) > 0 then
    begin
      Canvas := Context.Canvas;
      Icon := IconRect(Rect);
      Row.Icon := Icon;
      Sample := GetPixel(Canvas.Handle, Rect.Left + 1, Rect.Top + 1);
      if Sample = CLR_INVALID then
        Back := TAtlasColor(ColorToRGB(Canvas.Brush.Color))
      else
        Back := TAtlasColor(Sample);
      Colors := TAtlasColors.ForBackground(Back);
      OldBrush := TBrush.Create;
      OldPen := TPen.Create;
      try
        OldBrush.Assign(Canvas.Brush);
        OldPen.Assign(Canvas.Pen);
        // Notizblatt mit umgeknickter Ecke und zwei Textzeilen, im Akzent.
        Fold := Max(2, Icon.Width div 3);
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := TColor(TAtlasColorMath.Mix(Colors.Accent, Back, 0.25));
        Canvas.Pen.Color := TColor(TAtlasColorMath.Mix(Colors.Accent, Back, 0.9));
        Canvas.Pen.Width := 1;
        Canvas.Polygon([Point(Icon.Left, Icon.Top), Point(Icon.Right - Fold, Icon.Top),
          Point(Icon.Right, Icon.Top + Fold), Point(Icon.Right, Icon.Bottom), Point(Icon.Left, Icon.Bottom)]);
        Canvas.MoveTo(Icon.Right - Fold, Icon.Top);
        Canvas.LineTo(Icon.Right - Fold, Icon.Top + Fold);
        Canvas.LineTo(Icon.Right, Icon.Top + Fold);
        Step := Max(2, Icon.Height div 4);
        Y := Icon.Top + Fold + Step - 1;
        while Y < Icon.Bottom - 1 do
        begin
          Canvas.MoveTo(Icon.Left + 2, Y);
          Canvas.LineTo(Icon.Right - 1, Y);
          Inc(Y, Step);
        end;
      finally
        Canvas.Brush.Assign(OldBrush);
        Canvas.Pen.Assign(OldPen);
        OldPen.Free;
        OldBrush.Free;
      end;
    end;
    FRows.AddOrSetValue(Context.EditorLineNum, Row);
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Notes, E);
  end;
end;

procedure TAtlasIdeNotesGutter.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  Row: TRow;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Notes) then
    Exit;
  try
    if not Wanted or not RowAt(X, Y, Row) or Row.Icon.IsEmpty or not PtInRect(Row.Icon, Point(X, Y)) then
    begin
      FHovering := False;
      HideTip;
      Exit;
    end;
    if FHovering and SameText(FHover.FileName, Row.FileName) and (FHover.Line = Row.Line) then
      Exit;
    HideTip;
    FHover := Row;
    FHovering := True;
    FHoverSince := TThread.GetTickCount64;
    FHoverScreen := TRect.Create(Editor.ClientToScreen(Row.Icon.TopLeft), Editor.ClientToScreen(Row.Icon.BottomRight));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Notes, E);
  end;
end;

procedure TAtlasIdeNotesGutter.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Row: TRow;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Notes) then
    Exit;
  try
    HideTip;
    FHovering := False;
    // Rechtsklick in die Rinne: Diese Zeile gilt für die Notiz-Befehle im Kontextmenü.
    if Wanted and (Button = mbRight) and RowAt(X, Y, Row) and (Row.Line >= 0) then
      TAtlasIdeNotes.RememberGutterLine(Row.FileName, Row.Line)
    else
      TAtlasIdeNotes.ForgetGutterLine;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Notes, E);
  end;
end;

procedure TAtlasIdeNotesGutter.CheckHover;
var
  Inside: Boolean;
begin
  if not FHovering then
    Exit;
  // Maus hat das Symbol verlassen, ohne dass der Editor es gemeldet hat (anderes Fenster).
  Inside := PtInRect(FHoverScreen, Mouse.CursorPos) or (FTip.IsShown and PtInRect(FTip.BoundsRect, Mouse.CursorPos));
  if not Inside then
  begin
    FHovering := False;
    HideTip;
    Exit;
  end;
  if not FTip.IsShown and (TThread.GetTickCount64 - FHoverSince >= HoverMs) then
    ShowTip;
end;

procedure TAtlasIdeNotesGutter.ShowTip;
var
  Notes: TArray<TAtlasNote>;
  Title, Text: string;
begin
  Notes := TAtlasIdeNotes.NotesAt(FHover.FileName, FHover.Line);
  if Length(Notes) = 0 then
  begin
    FHovering := False;
    Exit;
  end;
  TipText(Notes, Title, Text);
  TAtlasIdeStyle.Apply(FTip, FHoverScreen);
  FTip.ShowNote(Title, Text, Point(FHoverScreen.Right + 4, FHoverScreen.Bottom + 2));
end;

procedure TAtlasIdeNotesGutter.HideTip;
begin
  if (FTip <> nil) and FTip.IsShown then
    FTip.HidePopup;
end;

end.
