unit Atlas.IDE.Foundation.GutterMarks;

// Gemeinsame Zeichenschicht der Rinne (#401) für Markierungen an Codezeilen,
// genutzt von den persönlichen Notizen (#545) und den benannten Lesezeichen
// (#622). Jede Art meldet sich als Schicht (IAtlasGutterLayer) an: Base
// über Add, Module über ihren Scope (#1455; die Liste folgt der Registry
// sofort, ein abgemeldetes Modul erreicht keine Zeichnung mehr); ein
// einziger Editor-Notifier zeichnet, zeigt Tooltips und merkt Rechtsklicks:
// - Zeichnen: am Ende des Zeichnens jeder Rinnenzeile (letzte Stufe von
//   TPaintGutterStage, nach der IDE) je Schicht mit Markierung an der Zeile
//   ein kleines Symbol, von links nach rechts in der Reihenfolge der
//   Schichten (IconRect). Rechteck, Zeile und Symbole jeder gezeichneten
//   Rinnenzeile werden gemerkt.
// - Überfahren eines Symbols zeigt nach HoverMs den Tooltip seiner Schicht
//   (TAtlasTitledTip), auf Wunsch der Schicht mit anklickbaren Links darunter
//   (TipLinks, OpenLink; etwa die Kette der Rekursionssymbole #623).
// - Rechtsklick in die Rinne merkt die Zeile für die Befehle im
//   Atlas-Untermenü des Kontextmenüs (TakeLine, höchstens LineMs alt, gleiche
//   Datei); jeder andere Klick vergisst sie.
// - Ein Zeitgeber meldet den Schichten die Datei im oberen Editor (neue Datei
//   sofort, Änderungen nach einer Tipp-Pause QuietMs), damit sie ihre
//   Markierungen neu verankern, und zeichnet den Editor bei Bedarf neu.
// Jede Schicht ist über ihre Einstellung (Wanted) abschaltbar und über ihr
// Feature gesichert (#493): Fehler einer Schicht schalten nur diese ab.
// Ausblenden am Element (#628): Jede Schicht nennt ihr Element; ein in .atlas
// ausgeblendetes Symbol (Datei oder Zeilentext) entfällt, jedes gezeichnete
// meldet sich bei TAtlasIdeElements.
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
  Atlas.Core.Editor.Elements,
  Atlas.Core.Modules.Watch,
  Atlas.UI.Popup.TitledTip;

type
  /// <summary>Eine Art von Markierung in der Rinne. Alle Aufrufe im Hauptthread; Ausnahmen fängt
  /// TAtlasIdeGutterMarks ab und meldet sie an Feature. Module stellen ihre Schichten über den Scope bereit
  /// (#1455).</summary>
  IAtlasGutterLayer = interface
    ['{786A046F-579E-44EA-AF15-1EBA159AF606}']
    /// <summary>Sicherung (#493): Fehler gehen an dieses Feature; ist es abgeschaltet, ruht die Schicht.</summary>
    function Feature: TAtlasFeature;
    /// <summary>Gezeichnetes Element für „Ausblenden“ (#628).</summary>
    function Element: TAtlasDrawnElement;
    /// <summary>Einstellung an.</summary>
    function Wanted: Boolean;
    /// <summary>Oberer Editor zeigt AFileName mit AText: neu verankern. AOpened: Datei ist gerade nach vorn
    /// gekommen (sonst nach einer Tipp-Pause, nur bei HasMarks).</summary>
    procedure Track(const AFileName, AText: string; AOpened: Boolean);
    /// <summary>Hat AFileName Markierungen (ohne IDE-Aufrufe, zum Zeichnen)?</summary>
    function HasMarks(const AFileName: string): Boolean;
    /// <summary>Markierung an ALine (0-basiert)? ALineText ist der Text der Zeile im Editor, sofern AHasText:
    /// Passt er nicht mehr zum Anker, wartet das Symbol auf die nächste Verankerung.</summary>
    function MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
      AHasText: Boolean): Boolean;
    /// <summary>Symbol in AIcon zeichnen; AColors passt zum Grund ABack.</summary>
    procedure PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
      ABack: TAtlasColor);
    /// <summary>Überschrift und Text des Tooltips; False ohne Markierung.</summary>
    function TipText(const AFileName: string; ALine: Integer; out ATitle, AText: string): Boolean;
    /// <summary>Links unter dem Text des Tooltips; ohne Überschreiben keine.</summary>
    function TipLinks(const AFileName: string; ALine: Integer): TArray<string>;
    /// <summary>Klick auf Link Nummer AIndex (ab 0) des Tooltips an ALine.</summary>
    procedure OpenLink(const AFileName: string; ALine, AIndex: Integer);
  end;

  /// <summary>Grundlage einer Schicht: ohne Links im Tooltip.</summary>
  TAtlasGutterLayer = class abstract(TInterfacedObject, IAtlasGutterLayer)
  public
    function Feature: TAtlasFeature; virtual; abstract;
    function Element: TAtlasDrawnElement; virtual; abstract;
    function Wanted: Boolean; virtual; abstract;
    procedure Track(const AFileName, AText: string; AOpened: Boolean); virtual; abstract;
    function HasMarks(const AFileName: string): Boolean; virtual; abstract;
    function MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
      AHasText: Boolean): Boolean; virtual; abstract;
    procedure PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
      ABack: TAtlasColor); virtual; abstract;
    function TipText(const AFileName: string; ALine: Integer; out ATitle, AText: string): Boolean; virtual; abstract;
    function TipLinks(const AFileName: string; ALine: Integer): TArray<string>; virtual;
    procedure OpenLink(const AFileName: string; ALine, AIndex: Integer); virtual;
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
    /// <summary>Schichten von Base (Add) und der Module (FWatch); FLayers ist beides in dieser Reihenfolge:
    /// Module zuerst, wie bis #1455 Notizen und Lesezeichen vor den Rekursionssymbolen.</summary>
    FOwn: TArray<IAtlasGutterLayer>;
    FWatch: TAtlasProvidedWatch;
    FLayers: TArray<IAtlasGutterLayer>;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FTimer: TTimer;
    FTip: TAtlasTitledTip;
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
    function Active(const ALayer: IAtlasGutterLayer): Boolean;
    procedure LayersChanged;
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
    /// <summary>Schicht von Base anmelden. Die Reihenfolge bestimmt die Lage der Symbole.</summary>
    procedure Add(const ALayer: IAtlasGutterLayer);
    /// <summary>Will eine der Schichten der Module zeichnen (für den abgesicherten Start, #722)?</summary>
    class function ModuleLayersWanted: Boolean; static;
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
  Atlas.Core.Modules.Registry,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorRefresh;

{ TAtlasGutterLayer }

function TAtlasGutterLayer.TipLinks(const AFileName: string; ALine: Integer): TArray<string>;
begin
  Result := nil;
end;

procedure TAtlasGutterLayer.OpenLink(const AFileName: string; ALine, AIndex: Integer);
begin
  // Ohne Links nichts zu tun.
end;

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
  FWatch := TAtlasProvidedWatch.Create(AtlasModuleRegistry, IAtlasGutterLayer);
  FWatch.OnChanged := LayersChanged;
  FRows := TDictionary<Integer, TRow>.Create;
  FTip := TAtlasTitledTip.Create(nil);
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintGutter := PaintGutter;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 100;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  // Schichten der schon angemeldeten Module.
  LayersChanged;
end;

destructor TAtlasIdeGutterMarks.Destroy;
var
  Services: INTACodeEditorServices;
begin
  FTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    Services.RemoveEditorEventsNotifier(FIndex);
  end;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintGutter := nil;
    FEvents.OnEditorMouseMove := nil;
    FEvents.OnEditorMouseDown := nil;
  end;
  FEventsRef := nil;
  FTip.OnLink := nil;
  FTip.Free;
  FRows.Free;
  FreeAndNil(FWatch);
  FLayers := nil;
  FOwn := nil;
  ForgetLine;
  inherited Destroy;
end;

procedure TAtlasIdeGutterMarks.Add(const ALayer: IAtlasGutterLayer);
begin
  FOwn := FOwn + [ALayer];
  LayersChanged;
end;

procedure TAtlasIdeGutterMarks.LayersChanged;
var
  mItem: IInterface;
  mLayer: IAtlasGutterLayer;
begin
  // Gemerkte Zeilen und der Tooltip zeigen auf Schichten nach ihrer Nummer; nach einer Änderung gilt keine mehr.
  HideTip;
  if FTip <> nil then
  begin
    FTip.OnLink := nil;
  end;
  FHovering := False;
  FHoverLayer := -1;
  FLayers := nil;
  if FWatch <> nil then
  begin
    for mItem in FWatch.Items do
    begin
      if Supports(mItem, IAtlasGutterLayer, mLayer) then
      begin
        FLayers := FLayers + [mLayer];
      end;
    end;
  end;
  FLayers := FLayers + FOwn;
  if FRows <> nil then
  begin
    FRows.Clear;
  end;
  // Eine neue Schicht soll die Datei vorn sofort kennen.
  FFileName := '';
  Invalidate;
end;

class function TAtlasIdeGutterMarks.ModuleLayersWanted: Boolean;
var
  mItem: IInterface;
  mLayer: IAtlasGutterLayer;
begin
  Result := False;
  if AtlasModuleRegistry = nil then
  begin
    Exit;
  end;
  for mItem in AtlasModuleRegistry.FindAll(IAtlasGutterLayer) do
  begin
    if Supports(mItem, IAtlasGutterLayer, mLayer) and mLayer.Wanted then
    begin
      Exit(True);
    end;
  end;
end;

class procedure TAtlasIdeGutterMarks.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
  end;
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
  begin
    ALine := -1;
  end;
  ForgetLine;
end;

function TAtlasIdeGutterMarks.Active(const ALayer: IAtlasGutterLayer): Boolean;
begin
  Result := not TAtlasGuard.Disabled(ALayer.Feature) and ALayer.Wanted;
end;

function TAtlasIdeGutterMarks.AnyActive: Boolean;
var
  Layer: IAtlasGutterLayer;
begin
  Result := False;
  for Layer in FLayers do
  begin
    if Active(Layer) then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasIdeGutterMarks.TopView: IOTAEditView;
var
  Editors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
  begin
    Result := Editors.TopView;
  end;
end;

function TAtlasIdeGutterMarks.GuardFeature: TAtlasFeature;
var
  Layer: IAtlasGutterLayer;
begin
  // Fehler außerhalb einer Schicht (Puffer lesen, Tooltip) gehen an die erste aktive Schicht.
  for Layer in FLayers do
  begin
    if Active(Layer) then
    begin
      Exit(Layer.Feature);
    end;
  end;
  if Length(FLayers) > 0 then
  begin
    Result := FLayers[0].Feature;
  end
  else
  begin
    Result := TAtlasFeature.Notes;
  end;
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
  Layer: IAtlasGutterLayer;
  Tracked: Boolean;
begin
  View := TopView;
  if (View = nil) or (View.Buffer = nil) or (View.Buffer.FileName = '') then
  begin
    Exit;
  end;
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
    begin
      if Active(Layer) then
        try
          Layer.Track(FFileName, Text, True);
        except
          on E: Exception do
            TAtlasGuard.Report(Layer.Feature, E);
        end;
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
  begin
    Exit;
  end;
  FTrackedText := FText;
  Tracked := False;
  for Layer in FLayers do
  begin
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
  end;
  // Auch ohne Bewegung neu zeichnen: Die Zeile einer Markierung wurde vielleicht nur bearbeitet.
  if Tracked then
  begin
    Invalidate;
  end;
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
  begin
    Exit;
  end;
  for Row in FRows.Values do
  begin
    if PtInRect(Row.Gutter, Point(X, Y)) then
    begin
      // Nur, wenn die Zeile noch dort steht: gleiche Datei, nicht gescrollt.
      if not SameText(Row.FileName, View.Buffer.FileName) or (Row.TopRow <> View.TopRow) then
      begin
        Exit;
      end;
      ARow := Row;
      Exit(True);
    end;
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
  Layer: IAtlasGutterLayer;
  Prepared: Boolean;
begin
  if BeforeEvent or (Stage <> High(TPaintGutterStage)) or (Context = nil) or (Context.EditView = nil) then
  begin
    Exit;
  end;
  Row := Default(TRow);
  Row.FileName := Context.FileName;
  Row.Line := Context.LogicalLineNum - 1;
  Row.Gutter := Rect;
  Row.TopRow := Context.EditView.TopRow;
  LineState := Context.LineState;
  HasText := LineState <> nil;
  LineText := '';
  if HasText then
  begin
    LineText := LineState.Text;
  end;
  Canvas := nil;
  Colors := TAtlasColors.Light;
  Back := 0;
  Prepared := False;
  for Index := 0 to High(FLayers) do
  begin
    Layer := FLayers[Index];
    if TAtlasGuard.Disabled(Layer.Feature) then
    begin
      Continue;
    end;
    try
      if not Layer.Wanted or not Layer.MarkAt(Context.FileName, Row.Line, LineText, HasText) then
      begin
        Continue;
      end;
      // In .atlas ausgeblendet (#628): ganze Datei oder diese Codezeile.
      if TAtlasIdeElements.Hidden(Layer.Element, Context.FileName, LineText) then
      begin
        Continue;
      end;
      if not Prepared then
      begin
        // Farben einmal je Zeile aus dem Grund der Rinne.
        Canvas := Context.Canvas;
        Sample := GetPixel(Canvas.Handle, Rect.Left + 1, Rect.Top + 1);
        if Sample = CLR_INVALID then
        begin
          Back := TAtlasColor(ColorToRGB(Canvas.Brush.Color));
        end
        else
        begin
          Back := TAtlasColor(Sample);
        end;
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
      TAtlasIdeElements.Painted(Layer.Element, Context.FileName, Row.Line, LineText, Icon.Rect, Row.TopRow,
        Rect.Height);
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
    begin
      for Icon in Row.Marks do
      begin
        if PtInRect(Icon.Rect, Point(X, Y)) then
        begin
          Found := Icon.Layer;
          Break;
        end;
      end;
    end;
    if Found < 0 then
    begin
      FHovering := False;
      HideTip;
      Exit;
    end;
    if FHovering and (FHoverLayer = Found) and SameText(FHover.FileName, Row.FileName) and
      (FHover.Line = Row.Line) then
    begin
      Exit;
    end;
    HideTip;
    FHover := Row;
    FHoverLayer := Found;
    FHovering := True;
    FHoverSince := TThread.GetTickCount64;
    for Icon in Row.Marks do
    begin
      if Icon.Layer = Found then
      begin
        FHoverScreen := TRect.Create(Editor.ClientToScreen(Icon.Rect.TopLeft),
          Editor.ClientToScreen(Icon.Rect.BottomRight));
      end;
    end;
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
    begin
      RememberLine(Row.FileName, Row.Line);
    end
    else
    begin
      ForgetLine;
    end;
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
  begin
    Exit;
  end;
  // Maus hat das Symbol verlassen, ohne dass der Editor es gemeldet hat (anderes Fenster).
  Inside := PtInRect(FHoverScreen, Mouse.CursorPos) or (FTip.IsShown and PtInRect(FTip.BoundsRect, Mouse.CursorPos));
  if not Inside then
  begin
    FHovering := False;
    HideTip;
    Exit;
  end;
  if not FTip.IsShown and (TThread.GetTickCount64 - FHoverSince >= HoverMs) then
  begin
    ShowTip;
  end;
end;

procedure TAtlasIdeGutterMarks.ShowTip;
var
  Layer: IAtlasGutterLayer;
  Title, Text, FileName: string;
  Line: Integer;
begin
  if (FHoverLayer < 0) or (FHoverLayer > High(FLayers)) then
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
  FileName := FHover.FileName;
  Line := FHover.Line;
  // Ein Klick auf einen Link geht an die Schicht; danach schließt der Tooltip.
  FTip.OnLink :=
    procedure(AIndex: Integer)
    begin
      HideTip;
      FHovering := False;
      Layer.OpenLink(FileName, Line, AIndex);
    end;
  TAtlasIdeStyle.Apply(FTip, FHoverScreen);
  FTip.ShowNote(Title, Text, Layer.TipLinks(FileName, Line), Point(FHoverScreen.Right + 4, FHoverScreen.Bottom + 2));
end;

procedure TAtlasIdeGutterMarks.HideTip;
begin
  if (FTip <> nil) and FTip.IsShown then
  begin
    FTip.HidePopup;
  end;
end;

end.
