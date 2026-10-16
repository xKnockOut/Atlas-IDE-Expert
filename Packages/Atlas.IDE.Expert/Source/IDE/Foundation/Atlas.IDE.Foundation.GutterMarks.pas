unit Atlas.IDE.Foundation.GutterMarks;

// Gemeinsame Zeichenschicht der Rinne (#401) für Markierungen an Codezeilen,
// genutzt von den persönlichen Notizen (#545) und den benannten Lesezeichen
// (#622). Jede Art meldet sich als Schicht (TAtlasGutterLayer) an; ein
// einziger Editor-Notifier zeichnet, zeigt Tooltips und merkt Rechtsklicks:
// - Zeichnen: am Ende des Zeichnens jeder Rinnenzeile (letzte Stufe von
//   TPaintGutterStage, nach der IDE) je Schicht mit Markierung an der Zeile
//   ein kleines Symbol, von links nach rechts in der Reihenfolge der
//   Schichten (IconRect). Rechteck, Zeile und Symbole jeder gezeichneten
//   Rinnenzeile werden gemerkt.
// - Überfahren eines Symbols zeigt nach HoverMs den Tooltip seiner Schicht
//   (TAtlasNoteTip).
// - Rechtsklick in die Rinne merkt die Zeile für die Befehle im
//   Atlas-Untermenü des Kontextmenüs (TakeLine, höchstens LineMs alt, gleiche
//   Datei); jeder andere Klick vergisst sie.
// - Ein Zeitgeber meldet den Schichten die Datei im oberen Editor (neue Datei
//   sofort, Änderungen nach einer Tipp-Pause QuietMs), damit sie ihre
//   Markierungen neu verankern, und zeichnet den Editor bei Bedarf neu.
// Jede Schicht ist über ihre Einstellung (Wanted) abschaltbar und über ihr
// Feature gesichert (#493): Fehler einer Schicht schalten nur diese ab.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Notes.Tip;

type
  /// <summary>Eine Art von Markierung in der Rinne. Alle Aufrufe im Hauptthread; Ausnahmen fängt
  /// TAtlasIdeGutterMarks ab und meldet sie an Feature.</summary>
  TAtlasGutterLayer = class abstract
  public
    /// <summary>Sicherung (#493): Fehler gehen an dieses Feature; ist es abgeschaltet, ruht die Schicht.</summary>
    function Feature: TAtlasFeature; virtual; abstract;
    /// <summary>Einstellung an.</summary>
    function Wanted: Boolean; virtual; abstract;
    /// <summary>Oberer Editor zeigt AFileName mit AText: neu verankern. AOpened: Datei ist gerade nach vorn
    /// gekommen (sonst nach einer Tipp-Pause, nur bei HasMarks).</summary>
    procedure Track(const AFileName, AText: string; AOpened: Boolean); virtual; abstract;
    /// <summary>Hat AFileName Markierungen (ohne IDE-Aufrufe, zum Zeichnen)?</summary>
    function HasMarks(const AFileName: string): Boolean; virtual; abstract;
    /// <summary>Markierung an ALine (0-basiert)? ALineText ist der Text der Zeile im Editor, sofern AHasText:
    /// Passt er nicht mehr zum Anker, wartet das Symbol auf die nächste Verankerung.</summary>
    function MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
      AHasText: Boolean): Boolean; virtual; abstract;
    /// <summary>Symbol in AIcon zeichnen; AColors passt zum Grund ABack.</summary>
    procedure PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
      ABack: TAtlasColor); virtual; abstract;
    /// <summary>Überschrift und Text des Tooltips; False ohne Markierung.</summary>
    function TipText(const AFileName: string; ALine: Integer; out ATitle, AText: string): Boolean; virtual; abstract;
  end;

  TAtlasIdeGutterMarks = class
  public const
    /// <summary>So lange gilt ein Rechtsklick in die Rinne für die Befehle.</summary>
    LineMs = 60000;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedGutterStages: TPaintGutterStages; override;
    end;
    /// <summary>Gezeichnetes Symbol: Index der Schicht und Rechteck (Koordinaten des Editors).</summary>
    TMark = record
      Layer: Integer;
      Rect: TRect;
    end;
    /// <summary>Gezeichnete Rinnenzeile (Koordinaten des Editors).</summary>
    TRow = record
      FileName: string;
      /// <summary>0-basiert.</summary>
      Line: Integer;
      Gutter: TRect;
      Marks: TArray<TMark>;
      TopRow: Integer;
    end;
  private const
    QuietMs = 300;
    HoverMs = 300;
  private class var
    FClickFile: string;
    FClickLine: Integer;
    FClickAt: UInt64;
  private
    FLayers: TObjectList<TAtlasGutterLayer>;
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
    /// <summary>Symbol unter der Maus: Zeile, Schicht, seit wann, Rechteck auf dem Bildschirm.</summary>
    FHover: TRow;
    FHoverLayer: Integer;
    FHovering: Boolean;
    FHoverSince: UInt64;
    FHoverScreen: TRect;
    FShowing: Boolean;
    function Active(ALayer: TAtlasGutterLayer): Boolean;
    function AnyActive: Boolean;
    function GuardFeature: TAtlasFeature;
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
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Schicht anmelden; gehört danach diesem Objekt. Die Reihenfolge bestimmt die Lage der Symbole.</summary>
    procedure Add(ALayer: TAtlasGutterLayer);
    /// <summary>Editor neu zeichnen (etwa nach einer Änderung über einen Befehl).</summary>
    class procedure Invalidate; static;
    /// <summary>Rechteck des Symbols Nummer ASlot (0 = ganz links) in einer Rinnenzeile AGutter: senkrecht
    /// mittig, Höhe nach Zeile.</summary>
    class function IconRect(const AGutter: TRect; ASlot: Integer): TRect; static;
    /// <summary>Rechtsklick in die Rinne an ALine (0-basiert) von AFileName; gilt für die nächsten Befehle.</summary>
    class procedure RememberLine(const AFileName: string; ALine: Integer); static;
    class procedure ForgetLine; static;
    /// <summary>Zeile des letzten Rechtsklicks in die Rinne, wenn er zu AFileName gehört und höchstens LineMs
    /// alt ist; vergisst ihn in jedem Fall (ein Klick gilt für einen Befehl).</summary>
    class function TakeLine(const AFileName: string; out ALine: Integer): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Atlas.Core.Projects.Summary,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle;

{ TAtlasIdeGutterMarks.TEvents }

function TAtlasIdeGutterMarks.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintGutterEvents, cevMouseEvents];
end;

function TAtlasIdeGutterMarks.TEvents.AllowedGutterStages: TPaintGutterStages;
begin
  // Nur die letzte Stufe: Die Symbole liegen über dem, was die IDE gezeichnet hat.
  Result := [High(TPaintGutterStage)];
end;

{ TAtlasIdeGutterMarks }

constructor TAtlasIdeGutterMarks.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FHoverLayer := -1;
  FLayers := TObjectList<TAtlasGutterLayer>.Create(True);
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

destructor TAtlasIdeGutterMarks.Destroy;
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
  FLayers.Free;
  ForgetLine;
  inherited Destroy;
end;

procedure TAtlasIdeGutterMarks.Add(ALayer: TAtlasGutterLayer);
begin
  FLayers.Add(ALayer);
  FRows.Clear;
  // Die neue Schicht soll die Datei vorn sofort kennen.
  FFileName := '';
end;

class procedure TAtlasIdeGutterMarks.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.InvalidateTopEditor;
end;

class function TAtlasIdeGutterMarks.IconRect(const AGutter: TRect; ASlot: Integer): TRect;
var
  Height, Width, Top, Left: Integer;
begin
  Height := Max(6, Min(AGutter.Height - 4, 14));
  Width := Max(5, (Height * 4) div 5);
  Top := AGutter.Top + (AGutter.Height - Height) div 2;
  Left := AGutter.Left + 2 + Max(0, ASlot) * (Width + 2);
  Result := TRect.Create(Left, Top, Left + Width, Top + Height);
end;

class procedure TAtlasIdeGutterMarks.RememberLine(const AFileName: string; ALine: Integer);
begin
  FClickFile := AFileName;
  FClickLine := ALine;
  FClickAt := TThread.GetTickCount64;
end;

class procedure TAtlasIdeGutterMarks.ForgetLine;
begin
  FClickFile := '';
  FClickLine := -1;
end;

class function TAtlasIdeGutterMarks.TakeLine(const AFileName: string; out ALine: Integer): Boolean;
begin
  ALine := FClickLine;
  Result := (FClickFile <> '') and (FClickLine >= 0) and
    (TAtlasProjectSummaries.NormalizedPath(FClickFile) = TAtlasProjectSummaries.NormalizedPath(AFileName)) and
    (TThread.GetTickCount64 - FClickAt <= LineMs);
  if not Result then
    ALine := -1;
  ForgetLine;
end;

function TAtlasIdeGutterMarks.Active(ALayer: TAtlasGutterLayer): Boolean;
begin
  Result := not TAtlasGuard.Disabled(ALayer.Feature) and ALayer.Wanted;
end;

function TAtlasIdeGutterMarks.AnyActive: Boolean;
var
  Layer: TAtlasGutterLayer;
begin
  Result := False;
  for Layer in FLayers do
    if Active(Layer) then
      Exit(True);
end;

function TAtlasIdeGutterMarks.TopView: IOTAEditView;
var
  Editors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Result := Editors.TopView;
end;

function TAtlasIdeGutterMarks.GuardFeature: TAtlasFeature;
var
  Layer: TAtlasGutterLayer;
begin
  // Fehler außerhalb einer Schicht (Puffer lesen, Tooltip) gehen an die erste aktive Schicht.
  for Layer in FLayers do
    if Active(Layer) then
      Exit(Layer.Feature);
  if FLayers.Count > 0 then
    Result := FLayers[0].Feature
  else
    Result := TAtlasFeature.Notes;
end;

procedure TAtlasIdeGutterMarks.Tick(Sender: TObject);
begin
  try
    if not AnyActive then
    begin
      HideTip;
      FHovering := False;
      if FShowing then
      begin
        FShowing := False;
        FRows.Clear;
        // Beim Wiedereinschalten die Datei vorn neu zuordnen.
        FFileName := '';
        Invalidate;
      end;
      Exit;
    end;
    Track;
    CheckHover;
  except
    on E: Exception do
      TAtlasGuard.Report(GuardFeature, E);
  end;
end;

procedure TAtlasIdeGutterMarks.Track;
var
  View: IOTAEditView;
  Text: string;
  Layer: TAtlasGutterLayer;
  Tracked: Boolean;
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
    for Layer in FLayers do
      if Active(Layer) then
        try
          Layer.Track(FFileName, Text, True);
        except
          on E: Exception do
            TAtlasGuard.Report(Layer.Feature, E);
        end;
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
  // Nach der Tipp-Pause neu verankern; nur Dateien mit Markierungen kosten etwas.
  if (FTrackedText = FText) or (TThread.GetTickCount64 - FChangedAt < QuietMs) then
    Exit;
  FTrackedText := FText;
  Tracked := False;
  for Layer in FLayers do
    if Active(Layer) then
      try
        if Layer.HasMarks(FFileName) then
        begin
          Tracked := True;
          Layer.Track(FFileName, FText, False);
        end;
      except
        on E: Exception do
          TAtlasGuard.Report(Layer.Feature, E);
      end;
  // Auch ohne Bewegung neu zeichnen: Die Zeile einer Markierung wurde vielleicht nur bearbeitet.
  if Tracked then
    Invalidate;
end;

function TAtlasIdeGutterMarks.RowAt(X, Y: Integer; out ARow: TRow): Boolean;
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

procedure TAtlasIdeGutterMarks.PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Row: TRow;
  Icon: TMark;
  LineState: INTACodeEditorLineState;
  LineText: string;
  HasText: Boolean;
  Canvas: TCanvas;
  Colors: TAtlasColors;
  Back: TAtlasColor;
  Sample: COLORREF;
  OldBrush: TBrush;
  OldPen: TPen;
  Index: Integer;
  Layer: TAtlasGutterLayer;
  Prepared: Boolean;
begin
  if BeforeEvent or (Stage <> High(TPaintGutterStage)) or (Context = nil) or (Context.EditView = nil) then
    Exit;
  Row := Default(TRow);
  Row.FileName := Context.FileName;
  Row.Line := Context.LogicalLineNum - 1;
  Row.Gutter := Rect;
  Row.TopRow := Context.EditView.TopRow;
  LineState := Context.LineState;
  HasText := LineState <> nil;
  LineText := '';
  if HasText then
    LineText := LineState.Text;
  Canvas := nil;
  Colors := TAtlasColors.Light;
  Back := 0;
  Prepared := False;
  for Index := 0 to FLayers.Count - 1 do
  begin
    Layer := FLayers[Index];
    if TAtlasGuard.Disabled(Layer.Feature) then
      Continue;
    try
      if not Layer.Wanted or not Layer.MarkAt(Context.FileName, Row.Line, LineText, HasText) then
        Continue;
      if not Prepared then
      begin
        // Farben einmal je Zeile aus dem Grund der Rinne.
        Canvas := Context.Canvas;
        Sample := GetPixel(Canvas.Handle, Rect.Left + 1, Rect.Top + 1);
        if Sample = CLR_INVALID then
          Back := TAtlasColor(ColorToRGB(Canvas.Brush.Color))
        else
          Back := TAtlasColor(Sample);
        Colors := TAtlasColors.ForBackground(Back);
        Prepared := True;
      end;
      Icon.Layer := Index;
      Icon.Rect := IconRect(Rect, Length(Row.Marks));
      OldBrush := TBrush.Create;
      OldPen := TPen.Create;
      try
        OldBrush.Assign(Canvas.Brush);
        OldPen.Assign(Canvas.Pen);
        Layer.PaintIcon(Canvas, Icon.Rect, Colors, Back);
      finally
        Canvas.Brush.Assign(OldBrush);
        Canvas.Pen.Assign(OldPen);
        OldPen.Free;
        OldBrush.Free;
      end;
      Row.Marks := Row.Marks + [Icon];
    except
      // Zeichnen darf die IDE nie stören.
      on E: Exception do
        TAtlasGuard.Report(Layer.Feature, E);
    end;
  end;
  FRows.AddOrSetValue(Context.EditorLineNum, Row);
end;

procedure TAtlasIdeGutterMarks.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  Row: TRow;
  Icon: TMark;
  Found: Integer;
begin
  try
    Found := -1;
    if AnyActive and RowAt(X, Y, Row) then
      for Icon in Row.Marks do
        if PtInRect(Icon.Rect, Point(X, Y)) then
        begin
          Found := Icon.Layer;
          Break;
        end;
    if Found < 0 then
    begin
      FHovering := False;
      HideTip;
      Exit;
    end;
    if FHovering and (FHoverLayer = Found) and SameText(FHover.FileName, Row.FileName) and
      (FHover.Line = Row.Line) then
      Exit;
    HideTip;
    FHover := Row;
    FHoverLayer := Found;
    FHovering := True;
    FHoverSince := TThread.GetTickCount64;
    for Icon in Row.Marks do
      if Icon.Layer = Found then
        FHoverScreen := TRect.Create(Editor.ClientToScreen(Icon.Rect.TopLeft),
          Editor.ClientToScreen(Icon.Rect.BottomRight));
  except
    on E: Exception do
      TAtlasGuard.Report(GuardFeature, E);
  end;
end;

procedure TAtlasIdeGutterMarks.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Row: TRow;
begin
  try
    HideTip;
    FHovering := False;
    // Rechtsklick in die Rinne: Diese Zeile gilt für die Befehle im Kontextmenü.
    if (Button = mbRight) and AnyActive and RowAt(X, Y, Row) and (Row.Line >= 0) then
      RememberLine(Row.FileName, Row.Line)
    else
      ForgetLine;
  except
    on E: Exception do
      TAtlasGuard.Report(GuardFeature, E);
  end;
end;

procedure TAtlasIdeGutterMarks.CheckHover;
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

procedure TAtlasIdeGutterMarks.ShowTip;
var
  Layer: TAtlasGutterLayer;
  Title, Text: string;
begin
  if (FHoverLayer < 0) or (FHoverLayer >= FLayers.Count) then
  begin
    FHovering := False;
    Exit;
  end;
  Layer := FLayers[FHoverLayer];
  if not Active(Layer) or not Layer.TipText(FHover.FileName, FHover.Line, Title, Text) then
  begin
    FHovering := False;
    Exit;
  end;
  FTip.GuardFeature := Layer.Feature;
  TAtlasIdeStyle.Apply(FTip, FHoverScreen);
  FTip.ShowNote(Title, Text, Point(FHoverScreen.Right + 4, FHoverScreen.Bottom + 2));
end;

procedure TAtlasIdeGutterMarks.HideTip;
begin
  if (FTip <> nil) and FTip.IsShown then
    FTip.HidePopup;
end;

end.
