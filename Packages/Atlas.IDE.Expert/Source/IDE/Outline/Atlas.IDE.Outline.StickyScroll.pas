unit Atlas.IDE.Outline.StickyScroll;

// Mitlaufender Kopf (#506, experimentell) im Editor. Welche Kopfzeilen oben
// stehen, rechnet Atlas.Core.Outline.StickyScroll; hier bleiben Gliederung,
// Zeichnen und Klick.
// - Ein Zeitgeber (100 ms) holt für die aktive Ansicht den Stand von
//   TAtlasIdeOutlineCache (gemeinsam mit Gliederungsfenster und
//   Brotkrumenleiste, keine eigene Serveranfrage). Ändern sich Datei oder
//   Stand, zeichnet der Editor neu.
// - Zeichnen per PaintLine (plsEndPaint): Die ersten Bildschirmzeilen des
//   Codebereichs werden mit der Hintergrundfarbe des Editors übermalt, darauf
//   die Köpfe in seiner Schrift mit ihrer Einrückung; unter der letzten Zeile
//   eine Trennlinie. Ändert sich die oberste Zeile (Bildlauf), zeichnet der
//   Editor ganz neu, weil er beim Bildlauf nur die neuen Zeilen malt.
// - Klick (links, ohne Umschalttasten) auf eine Kopfzeile springt nach dem
//   Mausereignis zum Namen im Kopf.
// - Die oberste Zeile ist View.TopRow; zugeklappte Bereiche darunter zählt
//   der Kopf wie offene.
// editor.stickyScroll aus: nichts wird gezeichnet, kein Klick abgefangen.
// Nur im Hauptthread.

interface

type
  TAtlasIdeStickyScroll = class
  private class var
    FState: TObject;
  public
    /// <summary>Den Server fragt TAtlasIdeOutlineCache (vorher installieren).</summary>
    class procedure Install; static;
    class procedure Uninstall; static;
    /// <summary>Einstellung geändert: Editor neu zeichnen.</summary>
    class procedure ApplySettings; static;
    class function Enabled: Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Math,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.StickyScroll,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache;

const
  TickMs = 100;

var
  /// <summary>Neuzeichnen eingereiht; außerhalb des Zustands, weil der Eintrag ihn nicht kennen soll.</summary>
  InvalidatePending: Boolean;

type
  TEvents = class(TNTACodeEditorNotifier)
  protected
    function AllowedEvents: TCodeEditorEvents; override;
    function AllowedLineStages: TPaintLineStages; override;
  end;

  TStickyState = class
  private
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FOn: Boolean;
    FMaxLines: Integer;
    FFileName: string;
    FStamp: Cardinal;
    FNodes: TAtlasOutlineNodes;
    FLines: TArray<string>;
    /// <summary>Köpfe für die oberste Zeile FRowsTop (0-basiert, -1 = neu rechnen).</summary>
    FRows: TAtlasStickyRows;
    FRowsTop: Integer;
    FRowsMax: Integer;
    /// <summary>Zuletzt gezeichnet: Zeilenhöhe, linker Rand des Codebereichs, oberste Zeile.</summary>
    FRowHeight: Integer;
    FCodeLeft: Integer;
    FPaintedTop: Integer;
    FPaintedRows: Integer;
    /// <summary>Hintergrund des Editors aus einer nicht übermalten Zeile.</summary>
    FBack: TAtlasColor;
    FBackKnown: Boolean;
    procedure Tick(Sender: TObject);
    procedure Clear;
    procedure Update;
    procedure QueueInvalidate;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure PaintRow(const ARect: TRect; const ARow: TAtlasStickyRow; ALast: Boolean;
      const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    procedure ApplySettings;
  end;

procedure InvalidateEditor;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.InvalidateTopEditor;
end;

{ TEvents }

function TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents];
end;

function TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TStickyState }

constructor TStickyState.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FRowsTop := -1;
  FPaintedTop := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  ApplySettings;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TStickyState.Destroy;
var
  Services: INTACodeEditorServices;
  Shown: Boolean;
begin
  FTimer.Free;
  Shown := FPaintedRows > 0;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintLine := nil;
  FEvents.OnEditorMouseDown := nil;
  FEventsRef := nil;
  if Shown then
    InvalidateEditor;
  inherited Destroy;
end;

procedure TStickyState.ApplySettings;
var
  Settings: TAtlasPluginSettings;
  Was: Boolean;
begin
  Settings := TAtlasIdeSettings.Current;
  Was := FOn;
  FOn := Settings.Enabled and Settings.StickyScroll and not TAtlasGuard.Disabled(TAtlasFeature.EditorCommands);
  FMaxLines := TAtlasStickyScroll.ClampLines(Settings.StickyScrollMaxLines);
  FRowsTop := -1;
  if not FOn then
    Clear;
  if Was or FOn then
    InvalidateEditor;
end;

procedure TStickyState.Clear;
begin
  FFileName := '';
  FStamp := 0;
  FNodes := nil;
  FLines := nil;
  FRows := nil;
  FRowsTop := -1;
  FPaintedRows := 0;
end;

procedure TStickyState.QueueInvalidate;
begin
  if InvalidatePending then
    Exit;
  InvalidatePending := True;
  // Nicht während des Malens: nach dem laufenden Ereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.EditorCommands,
    procedure
    begin
      InvalidatePending := False;
      InvalidateEditor;
    end);
end;

procedure TStickyState.Tick(Sender: TObject);
begin
  try
    Update;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

procedure TStickyState.Update;
var
  View: IOTAEditView;
  Snapshot: TAtlasOutlineSnapshot;
  Shown: Boolean;
begin
  // Schnellschalter und Schutzschalter wirken ohne eigenes Ereignis.
  if (TAtlasIdeStickyScroll.Enabled and not TAtlasGuard.Disabled(TAtlasFeature.EditorCommands)) <> FOn then
    ApplySettings;
  if not FOn then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Snapshot := TAtlasIdeOutlineCache.Refresh(View);
  case Snapshot.Status of
    TAtlasOutlineStatus.Waiting:
      Exit;
    TAtlasOutlineStatus.NoFile, TAtlasOutlineStatus.NoServer:
      begin
        Shown := FPaintedRows > 0;
        Clear;
        if Shown then
          InvalidateEditor;
        Exit;
      end;
  end;
  if not SameText(Snapshot.FileName, FFileName) or (Snapshot.Stamp <> FStamp) then
  begin
    FFileName := Snapshot.FileName;
    FStamp := Snapshot.Stamp;
    FNodes := Snapshot.Nodes;
    FLines := TTextLines.SplitLines(Snapshot.Text);
    FRowsTop := -1;
    InvalidateEditor;
  end
  else if (View.TopRow - 1 <> FPaintedTop) and ((FPaintedRows > 0) or (Length(FNodes) > 0)) then
    // Bildlauf ohne Malen der oberen Zeilen (z. B. per Rollrad): ganz neu zeichnen.
    InvalidateEditor;
end;

procedure TStickyState.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  View: IOTAEditView;
  Top, Row, Height: Integer;
  Sample: COLORREF;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not FOn or (FFileName = '') then
    Exit;
  try
    View := Context.EditView;
    if (View = nil) or (View.Buffer = nil) or not SameText(Context.FileName, FFileName) then
      Exit;
    Height := Rect.Bottom - Rect.Top;
    if Height <= 0 then
      Exit;
    Top := View.TopRow - 1;
    if (Top <> FRowsTop) or (FMaxLines <> FRowsMax) then
    begin
      FRows := TAtlasStickyScroll.Rows(FNodes, FLines, Top, FMaxLines,
        TAtlasEditorBuffer.TabWidth(View.Buffer));
      FRowsTop := Top;
      FRowsMax := FMaxLines;
    end;
    // Hat der Editor beim Bildlauf nur einen Teil gemalt, stehen alte Köpfe verschoben: ganz neu zeichnen.
    if (FPaintedTop >= 0) and (Top <> FPaintedTop) and ((FPaintedRows > 0) or (Length(FRows) > 0)) then
      QueueInvalidate;
    FPaintedTop := Top;
    FPaintedRows := Length(FRows);
    FRowHeight := Height;
    Row := (Rect.Top + Height div 2) div Height;
    if Row >= Length(FRows) then
    begin
      // Nicht übermalte Zeile: deren Hintergrund ist der des Editors.
      Sample := GetPixel(Context.Canvas.Handle, Rect.Right - 2, Rect.Top + 1);
      if Sample <> CLR_INVALID then
      begin
        FBack := TAtlasColor(Sample);
        FBackKnown := True;
      end;
      Exit;
    end;
    PaintRow(Rect, FRows[Row], Row = High(FRows), Context);
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

procedure TStickyState.PaintRow(const ARect: TRect; const ARow: TAtlasStickyRow; ALast: Boolean;
  const Context: INTACodeEditorPaintContext);
var
  Canvas: TCanvas;
  LineState: INTACodeEditorLineState;
  Code, Area, Cell: TRect;
  Colors: TAtlasColors;
  Back: TAtlasColor;
  Sample: COLORREF;
  Saved, Left, TextTop: Integer;
  OldFont: TFont;
  OldBrush: TBrush;
  OldPen: TPen;
begin
  Canvas := Context.Canvas;
  LineState := Context.LineState;
  Left := ARect.Left;
  if LineState <> nil then
  begin
    Code := LineState.CodeRect;
    if Code.Right > Code.Left then
      Left := Code.Left;
  end;
  FCodeLeft := Left;
  Area := TRect.Create(Left, ARect.Top, ARect.Right, ARect.Bottom);
  if FBackKnown then
    Back := FBack
  else
  begin
    Sample := GetPixel(Canvas.Handle, ARect.Right - 2, ARect.Top + 1);
    if Sample = CLR_INVALID then
      Back := TAtlasColor(ColorToRGB(Canvas.Brush.Color))
    else
      Back := TAtlasColor(Sample);
  end;
  Colors := TAtlasColors.ForBackground(Back);
  OldFont := TFont.Create;
  OldBrush := TBrush.Create;
  OldPen := TPen.Create;
  OldFont.Assign(Canvas.Font);
  OldBrush.Assign(Canvas.Brush);
  OldPen.Assign(Canvas.Pen);
  Saved := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle, Area.Left, Area.Top, Area.Right, Area.Bottom);
    Canvas.Brush.Style := bsSolid;
    // Leichte Abgrenzung: Hintergrund des Editors, eine Spur zur Schrift hin.
    Canvas.Brush.Color := TColor(TAtlasColorMath.Mix(Colors.Text, Back, 0.04));
    Canvas.FillRect(Area);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Style := [];
    if ARow.Summary then
      Canvas.Font.Color := TColor(Colors.Muted)
    else
      Canvas.Font.Color := TColor(Colors.Text);
    Cell := Context.EditorState.GetCharacterPosPx(ARow.Indent + 1, Context.EditorLineNum);
    TextTop := ARect.Top + Max(0, (ARect.Bottom - ARect.Top - Canvas.TextHeight('Xg')) div 2);
    Canvas.TextOut(Max(Left, Cell.Left), TextTop, ARow.Text);
    if ALast then
    begin
      Canvas.Pen.Style := psSolid;
      Canvas.Pen.Width := 1;
      Canvas.Pen.Color := TColor(Colors.Line);
      Canvas.MoveTo(Area.Left, Area.Bottom - 1);
      Canvas.LineTo(Area.Right, Area.Bottom - 1);
    end;
  finally
    RestoreDC(Canvas.Handle, Saved);
    Canvas.Font.Assign(OldFont);
    Canvas.Brush.Assign(OldBrush);
    Canvas.Pen.Assign(OldPen);
    OldPen.Free;
    OldBrush.Free;
    OldFont.Free;
  end;
end;

procedure TStickyState.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  View: IOTAEditView;
  Row: Integer;
  Target: TAtlasStickyRow;
  FileName: string;
begin
  try
    if not FOn or (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or (FPaintedRows = 0) or
      (FRowHeight <= 0) or (Y < 0) or (X < FCodeLeft) then
      Exit;
    Row := Y div FRowHeight;
    if (Row >= FPaintedRows) or (Row > High(FRows)) then
      Exit;
    // Nur, wenn die Köpfe noch so stehen: gleiche Datei, nicht gescrollt.
    View := TAtlasEditorBuffer.ActiveView;
    if (View = nil) or (View.Buffer = nil) or not SameText(View.Buffer.FileName, FFileName) or
      (View.TopRow - 1 <> FPaintedTop) then
      Exit;
    Target := FRows[Row];
    FileName := FFileName;
    // Erst nach dem Mausereignis: der Editor setzt sonst den Cursor auf die angeklickte Stelle.
    TAtlasMainThread.ForceQueue(TAtlasFeature.EditorCommands,
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            TAtlasIdeNavigation.GoToLocation(FileName, Target.Line, Target.Character);
          end);
      end);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

{ TAtlasIdeStickyScroll }

class procedure TAtlasIdeStickyScroll.Install;
begin
  if FState = nil then
    FState := TStickyState.Create;
end;

class procedure TAtlasIdeStickyScroll.Uninstall;
begin
  FreeAndNil(FState);
end;

class procedure TAtlasIdeStickyScroll.ApplySettings;
begin
  if FState <> nil then
    TStickyState(FState).ApplySettings;
end;

class function TAtlasIdeStickyScroll.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.StickyScroll;
end;

end.
