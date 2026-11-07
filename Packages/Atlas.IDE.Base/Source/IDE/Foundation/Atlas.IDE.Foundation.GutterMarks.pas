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
    /// <summary>Symbol unter der Maus: Zeile, Schicht, seit wann, Rechteck auf dem Bildschirm.</summary>
    THover = record
      Row: TRow;
      Layer: Integer;
      Active: Boolean;
      Since: UInt64;
      Screen: TRect;
    end;
  private const
    cQuietMs = 300;
    cHoverMs = 300;
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
    FHover: THover;
    FShowing: Boolean;
    procedure LayersChanged;
    function AnyActive: Boolean;
    function GuardFeature: TAtlasFeature;
    function RowAt(AX, AY: Integer; out ARow: TRow): Boolean;
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
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorRefresh;

function LayerActive(const ALayer: IAtlasGutterLayer): Boolean;
begin
  Result := not TAtlasGuard.Disabled(ALayer.Feature) and ALayer.Wanted;
end;

function TopEditView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
end;

/// <summary>Aktive Schichten neu verankern; mit AOnlyMarked nur die mit Markierungen in AFileName. True, wenn
/// eine Schicht verankert hat.</summary>
function TrackLayers(const ALayers: TArray<IAtlasGutterLayer>; const AFileName, AText: string;
  AOnlyMarked: Boolean): Boolean;
var
  mLayer: IAtlasGutterLayer;
begin
  Result := False;
  for mLayer in ALayers do
  begin
    if LayerActive(mLayer) then
      try
        if not AOnlyMarked or mLayer.HasMarks(AFileName) then
        begin
          Result := True;
          mLayer.Track(AFileName, AText, not AOnlyMarked);
        end;
      except
        on E: Exception do
          TAtlasGuard.Report(mLayer.Feature, E);
      end;
  end;
end;

/// <summary>Zeigt ALayer an der Zeile ein Symbol (gewollt, Markierung, nicht in .atlas ausgeblendet, #628)?</summary>
function LayerMarks(const ALayer: IAtlasGutterLayer; const AFileName: string; ALine: Integer;
  const ALineText: string; AHasText: Boolean): Boolean;
begin
  Result := ALayer.Wanted and ALayer.MarkAt(AFileName, ALine, ALineText, AHasText) and
    not TAtlasIdeElements.Hidden(ALayer.Element, AFileName, ALineText);
end;

/// <summary>Farben aus dem Grund der Rinne.</summary>
function GutterColors(ACanvas: TCanvas; const ARect: TRect; out ABack: TAtlasColor): TAtlasColors;
var
  mSample: COLORREF;
begin
  mSample := GetPixel(ACanvas.Handle, ARect.Left + 1, ARect.Top + 1);
  if mSample = CLR_INVALID then
  begin
    ABack := TAtlasColor(ColorToRGB(ACanvas.Brush.Color));
  end
  else
  begin
    ABack := TAtlasColor(mSample);
  end;
  Result := TAtlasColors.ForBackground(ABack);
end;

/// <summary>Symbol der Schicht zeichnen; Pinsel und Stift des Editors bleiben unverändert.</summary>
procedure PaintLayerIcon(const ALayer: IAtlasGutterLayer; ACanvas: TCanvas; const ARect: TRect;
  const AColors: TAtlasColors; ABack: TAtlasColor);
var
  mOldBrush: TBrush;
  mOldPen: TPen;
begin
  mOldBrush := TBrush.Create;
  mOldPen := TPen.Create;
  try
    mOldBrush.Assign(ACanvas.Brush);
    mOldPen.Assign(ACanvas.Pen);
    ALayer.PaintIcon(ACanvas, ARect, AColors, ABack);
  finally
    ACanvas.Brush.Assign(mOldBrush);
    ACanvas.Pen.Assign(mOldPen);
    mOldPen.Free;
    mOldBrush.Free;
  end;
end;

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
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FHover.Layer := -1;
  FWatch := TAtlasProvidedWatch.Create(AtlasModuleRegistry, IAtlasGutterLayer);
  FWatch.OnChanged := LayersChanged;
  FRows := TDictionary<Integer, TRow>.Create;
  FTip := TAtlasTitledTip.Create(nil);
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintGutter := PaintGutter;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
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
  mServices: INTACodeEditorServices;
begin
  FTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
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
  FHover.Active := False;
  FHover.Layer := -1;
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
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

class function TAtlasIdeGutterMarks.IconRect(const AGutter: TRect; ASlot: Integer): TRect;
var
  mHeight, mWidth, mTop, mLeft: Integer;
begin
  mHeight := Max(6, Min(AGutter.Height - 4, 14));
  mWidth := Max(5, (mHeight * 4) div 5);
  mTop := AGutter.Top + (AGutter.Height - mHeight) div 2;
  mLeft := AGutter.Left + 2 + Max(0, ASlot) * (mWidth + 2);
  Result := TRect.Create(mLeft, mTop, mLeft + mWidth, mTop + mHeight);
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


function TAtlasIdeGutterMarks.AnyActive: Boolean;
var
  mLayer: IAtlasGutterLayer;
begin
  Result := False;
  for mLayer in FLayers do
  begin
    if LayerActive(mLayer) then
    begin
      Exit(True);
    end;
  end;
end;


function TAtlasIdeGutterMarks.GuardFeature: TAtlasFeature;
var
  mLayer: IAtlasGutterLayer;
begin
  // Fehler außerhalb einer Schicht (Puffer lesen, Tooltip) gehen an die erste aktive Schicht.
  for mLayer in FLayers do
  begin
    if LayerActive(mLayer) then
    begin
      Exit(mLayer.Feature);
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
      FHover.Active := False;
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
  mView: IOTAEditView;
  mText: string;
begin
  mView := TopEditView;
  if (mView = nil) or (mView.Buffer = nil) or (mView.Buffer.FileName = '') then
  begin
    Exit;
  end;
  mText := TAtlasEditorSnapshots.Get(mView).Text;
  if not SameText(FFileName, mView.Buffer.FileName) then
  begin
    // Andere Datei vorn: gleich zuordnen, damit ihre Symbole erscheinen.
    FFileName := mView.Buffer.FileName;
    FText := mText;
    FTrackedText := mText;
    FRows.Clear;
    HideTip;
    TrackLayers(FLayers, FFileName, mText, False);
    FShowing := True;
    Invalidate;
  end
  else if FText <> mText then
  begin
    FText := mText;
    FChangedAt := TThread.GetTickCount64;
  end
  // Nach der Tipp-Pause neu verankern; nur Dateien mit Markierungen kosten etwas. Auch ohne Bewegung neu
  // zeichnen: Die Zeile einer Markierung wurde vielleicht nur bearbeitet.
  else if (FTrackedText <> FText) and (TThread.GetTickCount64 - FChangedAt >= cQuietMs) then
  begin
    FTrackedText := FText;
    if TrackLayers(FLayers, FFileName, FText, True) then
    begin
      Invalidate;
    end;
  end;
end;

function TAtlasIdeGutterMarks.RowAt(AX, AY: Integer; out ARow: TRow): Boolean;
var
  mRow: TRow;
  mView: IOTAEditView;
begin
  ARow := Default(TRow);
  ARow.Line := -1;
  Result := False;
  mView := TopEditView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  for mRow in FRows.Values do
  begin
    if PtInRect(mRow.Gutter, Point(AX, AY)) then
    begin
      // Nur, wenn die Zeile noch dort steht: gleiche Datei, nicht gescrollt.
      if not SameText(mRow.FileName, mView.Buffer.FileName) or (mRow.TopRow <> mView.TopRow) then
      begin
        Exit;
      end;
      ARow := mRow;
      Exit(True);
    end;
  end;
end;

procedure TAtlasIdeGutterMarks.PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mRow: TRow;
  mIcon: TMark;
  mLineState: INTACodeEditorLineState;
  mLineText: string;
  mColors: TAtlasColors;
  mBack: TAtlasColor;
  mIndex: Integer;
  mLayer: IAtlasGutterLayer;
  mPrepared: Boolean;
begin
  if BeforeEvent or (Stage <> High(TPaintGutterStage)) or (Context = nil) or (Context.EditView = nil) then
  begin
    Exit;
  end;
  mRow := Default(TRow);
  mRow.FileName := Context.FileName;
  mRow.Line := Context.LogicalLineNum - 1;
  mRow.Gutter := Rect;
  mRow.TopRow := Context.EditView.TopRow;
  mLineState := Context.LineState;
  mLineText := '';
  if mLineState <> nil then
  begin
    mLineText := mLineState.Text;
  end;
  mColors := TAtlasColors.Light;
  mBack := 0;
  mPrepared := False;
  for mIndex := 0 to High(FLayers) do
  begin
    mLayer := FLayers[mIndex];
    try
      if not TAtlasGuard.Disabled(mLayer.Feature) and
        LayerMarks(mLayer, Context.FileName, mRow.Line, mLineText, mLineState <> nil) then
      begin
        // Farben einmal je Zeile aus dem Grund der Rinne.
        if not mPrepared then
        begin
          mColors := GutterColors(Context.Canvas, Rect, mBack);
          mPrepared := True;
        end;
        mIcon.Layer := mIndex;
        mIcon.Rect := IconRect(Rect, Length(mRow.Marks));
        PaintLayerIcon(mLayer, Context.Canvas, mIcon.Rect, mColors, mBack);
        mRow.Marks := mRow.Marks + [mIcon];
        TAtlasIdeElements.Painted(
          TAtlasIdeElements.Target(mLayer.Element, Context.FileName, mRow.Line, mLineText), mIcon.Rect, mRow.TopRow,
          Rect.Height);
      end;
    except
      // Zeichnen darf die IDE nie stören.
      on E: Exception do
        TAtlasGuard.Report(mLayer.Feature, E);
    end;
  end;
  FRows.AddOrSetValue(Context.EditorLineNum, mRow);
end;

procedure TAtlasIdeGutterMarks.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  mRow: TRow;
  mIcon: TMark;
  mFound: Integer;
begin
  try
    mFound := -1;
    if AnyActive and RowAt(X, Y, mRow) then
    begin
      for mIcon in mRow.Marks do
      begin
        if PtInRect(mIcon.Rect, Point(X, Y)) then
        begin
          mFound := mIcon.Layer;
          Break;
        end;
      end;
    end;
    if mFound < 0 then
    begin
      FHover.Active := False;
      HideTip;
      Exit;
    end;
    if FHover.Active and (FHover.Layer = mFound) and SameText(FHover.Row.FileName, mRow.FileName) and
      (FHover.Row.Line = mRow.Line) then
    begin
      Exit;
    end;
    HideTip;
    FHover.Row := mRow;
    FHover.Layer := mFound;
    FHover.Active := True;
    FHover.Since := TThread.GetTickCount64;
    for mIcon in mRow.Marks do
    begin
      if mIcon.Layer = mFound then
      begin
        FHover.Screen := TRect.Create(Editor.ClientToScreen(mIcon.Rect.TopLeft),
          Editor.ClientToScreen(mIcon.Rect.BottomRight));
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
  mRow: TRow;
begin
  try
    HideTip;
    FHover.Active := False;
    // Rechtsklick in die Rinne: Diese Zeile gilt für die Befehle im Kontextmenü.
    if (Button = mbRight) and AnyActive and RowAt(X, Y, mRow) and (mRow.Line >= 0) then
    begin
      RememberLine(mRow.FileName, mRow.Line);
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
  mInside: Boolean;
begin
  if not FHover.Active then
  begin
    Exit;
  end;
  // Maus hat das Symbol verlassen, ohne dass der Editor es gemeldet hat (anderes Fenster).
  mInside := PtInRect(FHover.Screen, Mouse.CursorPos) or (FTip.IsShown and PtInRect(FTip.BoundsRect, Mouse.CursorPos));
  if not mInside then
  begin
    FHover.Active := False;
    HideTip;
    Exit;
  end;
  if not FTip.IsShown and (TThread.GetTickCount64 - FHover.Since >= cHoverMs) then
  begin
    ShowTip;
  end;
end;

procedure TAtlasIdeGutterMarks.ShowTip;
var
  mLayer: IAtlasGutterLayer;
  mTitle, mText, mFileName: string;
  mLine: Integer;
begin
  if (FHover.Layer < 0) or (FHover.Layer > High(FLayers)) then
  begin
    FHover.Active := False;
    Exit;
  end;
  mLayer := FLayers[FHover.Layer];
  if not LayerActive(mLayer) or not mLayer.TipText(FHover.Row.FileName, FHover.Row.Line, mTitle, mText) then
  begin
    FHover.Active := False;
    Exit;
  end;
  FTip.GuardFeature := mLayer.Feature;
  mFileName := FHover.Row.FileName;
  mLine := FHover.Row.Line;
  // Ein Klick auf einen Link geht an die Schicht; danach schließt der Tooltip.
  FTip.OnLink :=
    procedure(AIndex: Integer)
    begin
      HideTip;
      FHover.Active := False;
      mLayer.OpenLink(mFileName, mLine, AIndex);
    end;
  TAtlasIdeStyle.Apply(FTip, FHover.Screen);
  FTip.ShowNote(mTitle, mText, mLayer.TipLinks(mFileName, mLine), Point(FHover.Screen.Right + 4, FHover.Screen.Bottom + 2));
end;

procedure TAtlasIdeGutterMarks.HideTip;
begin
  if (FTip <> nil) and FTip.IsShown then
  begin
    FTip.HidePopup;
  end;
end;

end.
