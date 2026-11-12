unit Atlas.IDE.Editor.GutterColumn;

// Atlas-Spalte in der Zeilenleiste (#768): eine eigene Spalte der Rinne über
// INTACodeEditorServices280.RequestGutterColumn rechts neben den
// Zeilennummern (gclAfterLineNumbers). Haltepunkte, Lesezeichen, Faltung und
// die Marken von TAtlasIdeGutterMarks behalten ihre Plätze; aus = Spalte weg.
// - Symbol je Zeile nach Vorrang (TAtlasGutterColumn.Choose): Problem aus
//   TAtlasProblemsController (✕ Fehler, ▲ Warnung, ● Hinweis), Glühbirne ◆
//   für Code-Aktionen der Cursorzeile (nach einer Tipp-Pause beim Server
//   erfragt, kurze Wartezeit), ↑ überschreibt bzw. ↓ wird überschrieben aus
//   atlas.server.overrideMarks (nur, wenn der Server ohnehin läuft, je Datei
//   und Textstand gemerkt). Zeigt das vorderste Editorfenster den Designer
//   oder die Willkommensseite statt Code, fragt die Spalte den Server nicht.
// - Farben aus dem Grund der Rinne (hell/dunkel), Breite aus der Zeilenhöhe:
//   Ändert sich die Schrift oder die Skalierung, fordert der Zeitgeber die
//   Spalte in der neuen Breite an.
// - Überfahren zeigt nach HoverMs die Tafel des Symbols (TAtlasTitledTip). Ein
//   Klick auf ✕/▲/● zeigt Meldung, Code und die Korrekturen des Servers als
//   Links („Alle Code-Aktionen …“ dahinter), auf ◆ öffnet er die
//   Code-Aktionen der Zeile, auf ↑/↓ springt er zur Methode bzw. listet bei
//   mehreren die Methoden mit Datei und Zeile.
// Abschaltbar über editor.gutterColumn (auch als Schnellschalter) und je Art
// über editor.gutterColumn.problems, .codeActions, .overrides; ausblendbar am
// Element (#628). Sicherung über TAtlasFeature.GutterColumn (#493). Nur im
// Hauptthread.

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
  Atlas.Core.Editor.GutterColumn,
  Atlas.Core.Lsp.Session,
  Atlas.UI.Popup.TitledTip,
  Atlas.IDE.Editor.GutterColumnState;

type
  /// <summary>Code-Aktion anwenden; kommt von der Komposition, damit Editor nicht von Commands abhängt.</summary>
  TAtlasGutterColumnApplyProc = reference to procedure(const AAction: TLspCodeAction);

  TAtlasIdeGutterColumn = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedGutterStages: TPaintGutterStages; override;
    end;
    /// <summary>Gezeichnete Zeile der Spalte (Koordinaten des Editors).</summary>
    TRow = record
      FileName: string;
      /// <summary>0-basiert.</summary>
      Line: Integer;
      Rect: TRect;
      Symbol: TAtlasGutterSymbol;
      TopRow: Integer;
    end;
    /// <summary>Inhalt der Tafel: Titel, Text und Links mit ihren Aktionen.</summary>
    TPanel = record
      Title: string;
      Text: string;
      Captions: TArray<string>;
      Links: TArray<TProc>;
      /// <summary>Zeile an den Text hängen.</summary>
      procedure AddLine(const ALine: string);
      procedure AddLink(const ACaption: string; const AAction: TProc);
    end;
  private const
    cHoverMs = 400;
  private
    FOpenActions: TProc;
    FApply: TAtlasGutterColumnApplyProc;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FColumn: Integer;
    FWidth: Integer;
    FWantedWidth: Integer;
    FTimer: TTimer;
    /// <summary>Anmeldung bei TAtlasIdeGutterColumns: Spalte vor dem Abbau eines Editorfensters abgeben
    /// (#1233).</summary>
    FColumnsHandle: Integer;
    FTip: TAtlasTitledTip;
    FLinks: TArray<TProc>;
    FRows: TDictionary<Integer, TRow>;
    FState: TAtlasIdeGutterColumnState;
    // Überfahren.
    FHover: TRow;
    FHovering: Boolean;
    FHoverSince: UInt64;
    FHoverScreen: TRect;
    function Active: Boolean;
    procedure EnsureColumn;
    procedure DropColumn;
    procedure Tick(Sender: TObject);
    /// <summary>Zeile von AContext mit ihrem Symbol; ALineText: Text der Zeile im Editor.</summary>
    function RowOf(const AContext: INTACodeEditorPaintContext; out ALineText: string): TRow;
    function RowAt(AX, AY: Integer; out ARow: TRow): Boolean;
    procedure PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure CheckHover;
    procedure HideTip;
    procedure ShowPanel(const ARow: TRow; AFetchFixes: Boolean);
    /// <summary>Tafel zu ✕/▲/●: Meldungen, mit AFetchFixes die Korrekturen des Servers; False ohne Problem.</summary>
    function ProblemPanel(const ARow: TRow; AFetchFixes: Boolean; var APanel: TPanel): Boolean;
    /// <summary>Tafel zu ↑/↓: die Methoden als Links; False ohne Überschreibung.</summary>
    function OverridesPanel(const ARow: TRow; var APanel: TPanel): Boolean;
    procedure Click(const ARow: TRow);
    procedure OpenActions(const ARow: TRow);
    function ActionsAction(const ARow: TRow): TProc;
  public
    /// <summary>ASession: laufende Sitzung oder nil; AOpenActions: Code-Aktionen am Cursor anbieten; AApply:
    /// eine Code-Aktion anwenden.</summary>
    constructor Create(const ASession: TAtlasGutterColumnSessionFunc; const AOpenActions: TProc;
      const AApply: TAtlasGutterColumnApplyProc);
    destructor Destroy; override;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Forms,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Editor.Elements,
  Atlas.UI.Editor.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.GutterColumns,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Foundation.EditorBarHost;

type
  /// <summary>Maße eines Symbols in seiner Zelle.</summary>
  TSymbolBox = record
    Left: Integer;
    Top: Integer;
    Size: Integer;
    Mid: Integer;
    Center: Integer;
    Pen: Integer;
    constructor Create(const ARect: TRect);
    /// <summary>Unterste Pixelzeile.</summary>
    function Bottom: Integer;
  end;

constructor TSymbolBox.Create(const ARect: TRect);
begin
  Size := Max(6, Min(ARect.Width, ARect.Height) - 4);
  Left := ARect.Left + (ARect.Width - Size) div 2;
  Top := ARect.Top + (ARect.Height - Size) div 2;
  Mid := Top + Size div 2;
  Center := Left + Size div 2;
  Pen := Max(1, Size div 7);
end;

function TSymbolBox.Bottom: Integer;
begin
  Result := Top + Size - 1;
end;

function Services: INTACodeEditorServices280;
begin
  if not Supports(BorlandIDEServices, INTACodeEditorServices280, Result) then
  begin
    Result := nil;
  end;
end;

function TopView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
end;

function SymbolColor(ASymbol: TAtlasGutterSymbol; const AColors: TAtlasColors; ABack: TAtlasColor): TColor;
begin
  case ASymbol of
    TAtlasGutterSymbol.Error:
      Result := TColor(TAtlasColorMath.Mix(AColors.Error, ABack, 0.95));
    TAtlasGutterSymbol.Warning:
      Result := TColor(TAtlasColorMath.Mix(AColors.Warn, ABack, 0.95));
    TAtlasGutterSymbol.Hint:
      Result := TColor(TAtlasColorMath.Mix(AColors.Muted, ABack, 0.9));
    TAtlasGutterSymbol.Action:
      Result := TColor(TAtlasColorMath.Mix(AColors.Accent, ABack, 0.95));
  else
    Result := TColor(TAtlasColorMath.Mix(AColors.Add, ABack, 0.95));
  end;
end;

/// <summary>↑ (AUp) bzw. ↓: Schaft und gefüllte Spitze.</summary>
procedure PaintArrow(ACanvas: TCanvas; const ABox: TSymbolBox; AUp: Boolean);
var
  mHead: Integer;
begin
  mHead := Max(2, ABox.Size div 3);
  ACanvas.Pen.Width := 1;
  if AUp then
  begin
    ACanvas.Polygon([Point(ABox.Center, ABox.Top), Point(ABox.Center + mHead, ABox.Top + mHead),
      Point(ABox.Center - mHead, ABox.Top + mHead)]);
    ACanvas.Pen.Width := ABox.Pen;
    ACanvas.MoveTo(ABox.Center, ABox.Top + mHead);
    ACanvas.LineTo(ABox.Center, ABox.Bottom);
  end
  else
  begin
    ACanvas.Polygon([Point(ABox.Center, ABox.Bottom), Point(ABox.Center + mHead, ABox.Bottom - mHead),
      Point(ABox.Center - mHead, ABox.Bottom - mHead)]);
    ACanvas.Pen.Width := ABox.Pen;
    ACanvas.MoveTo(ABox.Center, ABox.Top);
    ACanvas.LineTo(ABox.Center, ABox.Bottom - mHead);
  end;
end;

procedure PaintSymbol(ACanvas: TCanvas; const ARect: TRect; ASymbol: TAtlasGutterSymbol; ABack: TAtlasColor);
var
  mBox: TSymbolBox;
  mColor: TColor;
  mQuarter: Integer;
begin
  mBox := TSymbolBox.Create(ARect);
  mColor := SymbolColor(ASymbol, TAtlasColors.ForBackground(ABack), ABack);
  ACanvas.Pen.Color := mColor;
  ACanvas.Pen.Width := mBox.Pen;
  ACanvas.Brush.Color := mColor;
  ACanvas.Brush.Style := bsSolid;
  if ASymbol <> TAtlasGutterSymbol.Error then
  begin
    ACanvas.Pen.Width := 1;
  end;
  mQuarter := mBox.Size div 4;
  case ASymbol of
    TAtlasGutterSymbol.Error:
      begin
        // ✕: zwei Diagonalen.
        ACanvas.MoveTo(mBox.Left + 1, mBox.Top + 1);
        ACanvas.LineTo(mBox.Left + mBox.Size - 1, mBox.Bottom);
        ACanvas.MoveTo(mBox.Left + mBox.Size - 2, mBox.Top + 1);
        ACanvas.LineTo(mBox.Left, mBox.Bottom);
      end;
    TAtlasGutterSymbol.Warning:
      // ▲: gefülltes Dreieck.
      ACanvas.Polygon([Point(mBox.Center, mBox.Top), Point(mBox.Left + mBox.Size - 1, mBox.Bottom),
        Point(mBox.Left, mBox.Bottom)]);
    TAtlasGutterSymbol.Hint:
      // ●: kleiner Punkt.
      ACanvas.Ellipse(mBox.Center - mQuarter, mBox.Mid - mQuarter, mBox.Center + mQuarter + 1,
        mBox.Mid + mQuarter + 1);
    TAtlasGutterSymbol.Action:
      // ◆: Raute.
      ACanvas.Polygon([Point(mBox.Center, mBox.Top), Point(mBox.Left + mBox.Size - 1, mBox.Mid),
        Point(mBox.Center, mBox.Bottom), Point(mBox.Left, mBox.Mid)]);
    TAtlasGutterSymbol.Overrides, TAtlasGutterSymbol.Overridden:
      PaintArrow(ACanvas, mBox, ASymbol = TAtlasGutterSymbol.Overrides);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Symbol in ARect zeichnen, Farben aus dem Grund der Spalte (hell oder dunkel wie das Thema der IDE);
/// Pinsel und Stift der IDE bleiben erhalten.</summary>
procedure PaintCell(ACanvas: TCanvas; const ARect: TRect; ASymbol: TAtlasGutterSymbol);
var
  mSample: COLORREF;
  mBack: TAtlasColor;
  mOldBrush: TBrush;
  mOldPen: TPen;
begin
  mSample := GetPixel(ACanvas.Handle, ARect.Left + 1, ARect.Top + 1);
  mBack := TAtlasColor(mSample);
  if mSample = CLR_INVALID then
  begin
    mBack := TAtlasColor(ColorToRGB(ACanvas.Brush.Color));
  end;
  mOldBrush := TBrush.Create;
  mOldPen := TPen.Create;
  try
    mOldBrush.Assign(ACanvas.Brush);
    mOldPen.Assign(ACanvas.Pen);
    PaintSymbol(ACanvas, ARect, ASymbol, mBack);
  finally
    ACanvas.Brush.Assign(mOldBrush);
    ACanvas.Pen.Assign(mOldPen);
    mOldPen.Free;
    mOldBrush.Free;
  end;
end;

function SeverityText(ASeverity: TAtlasProblemSeverity): string;
begin
  case ASeverity of
    TAtlasProblemSeverity.Error:
      Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.GutterSeverityError);
    TAtlasProblemSeverity.Warning:
      Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.GutterSeverityWarning);
  else
    Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.GutterSeverityHint);
  end;
end;

function FixAction(const AApply: TAtlasGutterColumnApplyProc; const AFix: TLspCodeAction): TProc;
var
  mApply: TAtlasGutterColumnApplyProc;
  mFix: TLspCodeAction;
begin
  mApply := AApply;
  mFix := AFix;
  Result :=
    procedure
    begin
      if Assigned(mApply) then
      begin
        mApply(mFix);
      end;
    end;
end;

function TargetAction(const ATarget: TAtlasGutterTarget): TProc;
var
  mTarget: TAtlasGutterTarget;
begin
  mTarget := ATarget;
  Result :=
    procedure
    begin
      TAtlasIdeNavigation.GoToLocation(mTarget.FileName, mTarget.Line, mTarget.Character);
    end;
end;

/// <summary>Schnellkorrekturen als Links; AError: Meldung, wenn der Server nicht antwortete.</summary>
procedure AddFixes(var APanel: TAtlasIdeGutterColumn.TPanel; const AFixes: TArray<TLspCodeAction>;
  const AError: string; const AApply: TAtlasGutterColumnApplyProc);
var
  mFix: TLspCodeAction;
begin
  if AError <> '' then
  begin
    APanel.AddLine(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.GutterFixesFailed, [AError]));
  end;
  for mFix in AFixes do
  begin
    if (mFix.Disabled = '') and mFix.Kind.StartsWith('quickfix') then
    begin
      APanel.AddLink(mFix.Title, FixAction(AApply, mFix));
    end;
  end;
  if Length(APanel.Captions) = 0 then
  begin
    APanel.AddLine(TAtlasEditorStrings.Text(TAtlasEditorTextId.GutterNoFix));
  end;
end;

/// <summary>Ziele als Links, mit APrefix vor jedem.</summary>
procedure AddTargets(var APanel: TAtlasIdeGutterColumn.TPanel; const ATargets: TArray<TAtlasGutterTarget>;
  const APrefix: string);
var
  mTarget: TAtlasGutterTarget;
begin
  for mTarget in ATargets do
  begin
    APanel.AddLink(APrefix + TAtlasGutterColumn.TargetText(mTarget), TargetAction(mTarget));
  end;
end;

{ TAtlasIdeGutterColumn.TEvents }

function TAtlasIdeGutterColumn.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintGutterEvents, cevMouseEvents];
end;

function TAtlasIdeGutterColumn.TEvents.AllowedGutterStages: TPaintGutterStages;
begin
  // Nur die letzte Stufe: Die Spalte ist dann schon vom Grund der Rinne gefüllt.
  Result := [High(TPaintGutterStage)];
end;

{ TAtlasIdeGutterColumn.TPanel }

procedure TAtlasIdeGutterColumn.TPanel.AddLine(const ALine: string);
begin
  if Text <> '' then
  begin
    Text := Text + #10;
  end;
  Text := Text + ALine;
end;

procedure TAtlasIdeGutterColumn.TPanel.AddLink(const ACaption: string; const AAction: TProc);
begin
  Captions := Captions + [ACaption];
  Links := Links + [AAction];
end;

{ TAtlasIdeGutterColumn }

constructor TAtlasIdeGutterColumn.Create(const ASession: TAtlasGutterColumnSessionFunc; const AOpenActions: TProc;
  const AApply: TAtlasGutterColumnApplyProc);
var
  mEditors: INTACodeEditorServices;
begin
  inherited Create;
  FOpenActions := AOpenActions;
  FApply := AApply;
  FIndex := -1;
  FColumn := -1;
  FState := TAtlasIdeGutterColumnState.Create(ASession);
  FRows := TDictionary<Integer, TRow>.Create;
  FTip := TAtlasTitledTip.Create(nil);
  FTip.GuardFeature := TAtlasFeature.GutterColumn;
  FTip.OnLink :=
    procedure(AIndex: Integer)
    var
      mAction: TProc;
    begin
      HideTip;
      FHovering := False;
      // Die Aktion selbst festhalten: Sie kann eine neue Tafel zeigen und damit FLinks ersetzen.
      mAction := nil;
      if (AIndex >= 0) and (AIndex <= High(FLinks)) then
      begin
        mAction := FLinks[AIndex];
      end;
      if Assigned(mAction) then
      begin
        mAction();
      end;
    end;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintGutter := PaintGutter;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mEditors) then
  begin
    FIndex := mEditors.AddEditorEventsNotifier(FEventsRef);
  end;
  FColumnsHandle := TAtlasIdeGutterColumns.Register(
    procedure
    begin
      DropColumn;
    end);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 100;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeGutterColumn.Destroy;
var
  mEditors: INTACodeEditorServices;
begin
  FTimer.Free;
  TAtlasIdeGutterColumns.Unregister(FColumnsHandle);
  // Erst Spalte und Notifier abmelden, dann freigeben (#493).
  DropColumn;
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mEditors) then
  begin
    mEditors.RemoveEditorEventsNotifier(FIndex);
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
  FLinks := nil;
  FRows.Free;
  FState.Free;
  inherited Destroy;
end;

function TAtlasIdeGutterColumn.Active: Boolean;
begin
  Result := (FIndex >= 0) and not TAtlasGuard.Disabled(TAtlasFeature.GutterColumn) and
    TAtlasIdeSettings.GutterColumnOn;
end;

procedure TAtlasIdeGutterColumn.EnsureColumn;
var
  mEditors: INTACodeEditorServices280;
begin
  if FWantedWidth <= 0 then
  begin
    FWantedWidth := TAtlasGutterColumn.Width(MulDiv(TAtlasGutterColumn.cBaseWidth, Screen.PixelsPerInch, 96));
  end;
  if (FColumn >= 0) and (FWidth = FWantedWidth) then
  begin
    Exit;
  end;
  mEditors := Services;
  // Kurz nach dem Abbau eines Editorfensters nicht wieder anfordern (#1233, TAtlasIdeGutterColumns).
  if (mEditors = nil) or not TAtlasIdeGutterColumns.Allowed then
  begin
    Exit;
  end;
  DropColumn;
  FColumn := mEditors.RequestGutterColumn(FIndex, FWantedWidth, gclAfterLineNumbers);
  FWidth := FWantedWidth;
  FRows.Clear;
  TAtlasIdeEditorRefresh.InvalidateTop(mEditors);
end;

procedure TAtlasIdeGutterColumn.DropColumn;
var
  mEditors: INTACodeEditorServices280;
begin
  if FColumn < 0 then
  begin
    Exit;
  end;
  mEditors := Services;
  if mEditors <> nil then
  begin
    mEditors.RemoveGutterColumn(FColumn);
    TAtlasIdeEditorRefresh.InvalidateTop(mEditors);
  end;
  FColumn := -1;
  FRows.Clear;
end;

procedure TAtlasIdeGutterColumn.Tick(Sender: TObject);
var
  mFileName: string;
begin
  try
    if not Active then
    begin
      HideTip;
      FHovering := False;
      if FColumn >= 0 then
      begin
        DropColumn;
        FState.Clear;
      end;
      Exit;
    end;
    FState.ReadOptions;
    EnsureColumn;
    // Andere Datei oben: Die gemerkten Zeilen gehören zur alten.
    mFileName := FState.FileName;
    // Im Designer und auf der Willkommensseite ist die Spalte nicht zu sehen: keine Anfragen an den Server.
    if TAtlasEditorBarHost.TopCodeShown then
    begin
      FState.Track(TopView);
    end;
    if not SameText(mFileName, FState.FileName) then
    begin
      FRows.Clear;
    end;
    CheckHover;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.GutterColumn, E);
  end;
end;

function TAtlasIdeGutterColumn.RowOf(const AContext: INTACodeEditorPaintContext; out ALineText: string): TRow;
var
  mLineState: INTACodeEditorLineState;
  mOverrides: TAtlasGutterOverrides;
begin
  Result := Default(TRow);
  Result.FileName := AContext.FileName;
  Result.Line := AContext.LogicalLineNum - 1;
  Result.TopRow := AContext.EditView.TopRow;
  Result.Rect := AContext.EditorState.GetGutterColumnRect(AContext.EditControl, AContext.EditorLineNum, FColumn);
  mLineState := AContext.LineState;
  ALineText := '';
  if mLineState <> nil then
  begin
    ALineText := mLineState.Text;
  end;
  Result.Symbol := TAtlasGutterSymbol.None;
  if TAtlasIdeGutterColumnState.IsSource(AContext.FileName) and (Result.Line >= 0) and not Result.Rect.IsEmpty then
  begin
    Result.Symbol := TAtlasGutterColumn.Choose(FState.LineOf(AContext.FileName, Result.Line, ALineText,
      mLineState <> nil, mOverrides), FState.Options);
  end;
  // In .atlas ausgeblendet (#628): ganze Datei oder diese Codezeile.
  if (Result.Symbol <> TAtlasGutterSymbol.None) and
    TAtlasIdeElements.Hidden(TAtlasDrawnElement.GutterColumn, AContext.FileName, ALineText) then
  begin
    Result.Symbol := TAtlasGutterSymbol.None;
  end;
end;

procedure TAtlasIdeGutterColumn.PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mRow: TRow;
  mLineText: string;
begin
  if BeforeEvent or (Stage <> High(TPaintGutterStage)) or (FColumn < 0) or (Context = nil) then
  begin
    Exit;
  end;
  try
    if (Context.EditView = nil) or (Context.EditorState = nil) or not Active then
    begin
      Exit;
    end;
    // Schrift oder Skalierung geändert: Der Zeitgeber fordert die Spalte neu an.
    if Context.CellSize.cy > 0 then
    begin
      FWantedWidth := TAtlasGutterColumn.Width(Context.CellSize.cy);
    end;
    mRow := RowOf(Context, mLineText);
    FRows.AddOrSetValue(Context.EditorLineNum, mRow);
    if mRow.Symbol <> TAtlasGutterSymbol.None then
    begin
      PaintCell(Context.Canvas, mRow.Rect, mRow.Symbol);
      TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.GutterColumn, Context.FileName,
        mRow.Line, mLineText), mRow.Rect, mRow.TopRow, mRow.Rect.Height);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.GutterColumn, E);
  end;
end;

function TAtlasIdeGutterColumn.RowAt(AX, AY: Integer; out ARow: TRow): Boolean;
var
  mRow: TRow;
  mView: IOTAEditView;
begin
  ARow := Default(TRow);
  Result := False;
  mView := TopView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  for mRow in FRows.Values do
  begin
    if (mRow.Symbol <> TAtlasGutterSymbol.None) and PtInRect(mRow.Rect, Point(AX, AY)) then
    begin
      // Nur, wenn die Zeile noch dort steht: gleiche Datei, nicht gescrollt.
      Result := SameText(mRow.FileName, mView.Buffer.FileName) and (mRow.TopRow = mView.TopRow);
      if Result then
      begin
        ARow := mRow;
      end;
      Exit;
    end;
  end;
end;

procedure TAtlasIdeGutterColumn.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  mRow: TRow;
begin
  try
    if not Active or not RowAt(X, Y, mRow) then
    begin
      FHovering := False;
      HideTip;
      Exit;
    end;
    if FHovering and SameText(FHover.FileName, mRow.FileName) and (FHover.Line = mRow.Line) then
    begin
      Exit;
    end;
    HideTip;
    FHover := mRow;
    FHovering := True;
    FHoverSince := TThread.GetTickCount64;
    FHoverScreen := TRect.Create(Editor.ClientToScreen(mRow.Rect.TopLeft),
      Editor.ClientToScreen(mRow.Rect.BottomRight));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.GutterColumn, E);
  end;
end;

procedure TAtlasIdeGutterColumn.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  mRow: TRow;
begin
  try
    if (Button <> mbLeft) or not Active or not RowAt(X, Y, mRow) then
    begin
      Exit;
    end;
    HideTip;
    FHovering := False;
    FHoverScreen := TRect.Create(Editor.ClientToScreen(mRow.Rect.TopLeft),
      Editor.ClientToScreen(mRow.Rect.BottomRight));
    Click(mRow);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.GutterColumn, E);
  end;
end;

procedure TAtlasIdeGutterColumn.CheckHover;
var
  mInside: Boolean;
begin
  if not FHovering then
  begin
    Exit;
  end;
  // Maus hat das Symbol verlassen, ohne dass der Editor es gemeldet hat (anderes Fenster).
  mInside := PtInRect(FHoverScreen, Mouse.CursorPos) or
    (FTip.IsShown and PtInRect(FTip.BoundsRect, Mouse.CursorPos));
  if not mInside then
  begin
    FHovering := False;
    HideTip;
  end
  else if not FTip.IsShown and (TThread.GetTickCount64 - FHoverSince >= cHoverMs) then
  begin
    ShowPanel(FHover, False);
  end;
end;

procedure TAtlasIdeGutterColumn.HideTip;
begin
  if (FTip <> nil) and FTip.IsShown then
  begin
    FTip.HidePopup;
  end;
end;

procedure TAtlasIdeGutterColumn.Click(const ARow: TRow);
var
  mTargets: TArray<TAtlasGutterTarget>;
begin
  case ARow.Symbol of
    TAtlasGutterSymbol.Action:
      OpenActions(ARow);
    TAtlasGutterSymbol.Overrides, TAtlasGutterSymbol.Overridden:
      begin
        // Ein Ziel: gleich hin; mehrere: Liste mit Datei und Zeile.
        mTargets := FState.TargetsOf(ARow.FileName, ARow.Line);
        if Length(mTargets) = 1 then
        begin
          TAtlasIdeNavigation.GoToLocation(mTargets[0].FileName, mTargets[0].Line, mTargets[0].Character);
        end
        else
        begin
          ShowPanel(ARow, False);
        end;
      end;
  else
    ShowPanel(ARow, True);
  end;
end;

procedure TAtlasIdeGutterColumn.OpenActions(const ARow: TRow);
var
  mView: IOTAEditView;
  mPosition: TOTAEditPos;
  mText: string;
  mColumn: Integer;
begin
  mView := TopView;
  if (mView = nil) or (mView.Buffer = nil) or not SameText(mView.Buffer.FileName, ARow.FileName) then
  begin
    Exit;
  end;
  // Cursor an den Anfang des Codes der Zeile, dann die Code-Aktionen wie über das Kontextmenü.
  mText := TAtlasEditorBuffer.LineText(mView, ARow.Line + 1);
  mColumn := 1;
  while (mColumn <= Length(mText)) and CharInSet(mText[mColumn], [' ', #9]) do
  begin
    Inc(mColumn);
  end;
  mPosition.Line := ARow.Line + 1;
  mPosition.Col := mColumn;
  mView.CursorPos := mPosition;
  mView.MoveViewToCursor;
  mView.Paint;
  if Assigned(FOpenActions) then
  begin
    FOpenActions();
  end;
end;

function TAtlasIdeGutterColumn.ActionsAction(const ARow: TRow): TProc;
var
  mRow: TRow;
begin
  mRow := ARow;
  Result :=
    procedure
    begin
      OpenActions(mRow);
    end;
end;

function TAtlasIdeGutterColumn.ProblemPanel(const ARow: TRow; AFetchFixes: Boolean; var APanel: TPanel): Boolean;
var
  mProblems: TArray<TAtlasProblem>;
  mProblem: TAtlasProblem;
  mFixes: TArray<TLspCodeAction>;
  mError: string;
begin
  mProblems := TAtlasGutterColumn.ProblemsAt(FState.ProblemsOf(ARow.FileName), ARow.Line);
  Result := Length(mProblems) > 0;
  if not Result then
  begin
    Exit;
  end;
  APanel.Title := TAtlasGutterColumn.ProblemTitle(mProblems[0], SeverityText(mProblems[0].Severity));
  for mProblem in mProblems do
  begin
    if (mProblem.Code <> '') and (Length(mProblems) > 1) then
    begin
      APanel.AddLine(mProblem.Code + ': ' + mProblem.Message);
    end
    else
    begin
      APanel.AddLine(mProblem.Message);
    end;
  end;
  if AFetchFixes then
  begin
    mFixes := FState.Fixes(ARow.FileName, mProblems[0], mError);
    AddFixes(APanel, mFixes, mError, FApply);
  end;
  APanel.AddLink(TAtlasEditorStrings.Text(TAtlasEditorTextId.GutterAllActions), ActionsAction(ARow));
end;

function TAtlasIdeGutterColumn.OverridesPanel(const ARow: TRow; var APanel: TPanel): Boolean;
var
  mEntry: TAtlasGutterOverrides;
  mUp, mDown: string;
begin
  Result := FState.OverridesAt(ARow.FileName, ARow.Line, mEntry);
  if not Result then
  begin
    Exit;
  end;
  if ARow.Symbol = TAtlasGutterSymbol.Overrides then
  begin
    APanel.Title := TAtlasEditorStrings.Text(TAtlasEditorTextId.GutterOverridesTitle);
  end
  else
  begin
    APanel.Title := TAtlasEditorStrings.Text(TAtlasEditorTextId.GutterOverriddenTitle);
  end;
  // Beide Richtungen: Pfeile vor den Zielen und im Text.
  mUp := '';
  mDown := '';
  if (Length(mEntry.Overrides) > 0) and (Length(mEntry.Overridden) > 0) then
  begin
    mUp := '↑ ';
    mDown := '↓ ';
    APanel.Text := TAtlasEditorStrings.Text(TAtlasEditorTextId.GutterOverridesTitle) + ' ↑ · ' +
      TAtlasEditorStrings.Text(TAtlasEditorTextId.GutterOverriddenTitle) + ' ↓';
  end;
  AddTargets(APanel, mEntry.Overrides, mUp);
  AddTargets(APanel, mEntry.Overridden, mDown);
end;

procedure TAtlasIdeGutterColumn.ShowPanel(const ARow: TRow; AFetchFixes: Boolean);
var
  mPanel: TPanel;
  mShown: Boolean;
begin
  mPanel := Default(TPanel);
  case ARow.Symbol of
    TAtlasGutterSymbol.Error, TAtlasGutterSymbol.Warning, TAtlasGutterSymbol.Hint:
      mShown := ProblemPanel(ARow, AFetchFixes, mPanel);
    TAtlasGutterSymbol.Action:
      begin
        mPanel.Title := TAtlasEditorStrings.Text(TAtlasEditorTextId.GutterActionTitle);
        mPanel.Text := TAtlasEditorStrings.Text(TAtlasEditorTextId.GutterActionText);
        mShown := True;
      end;
    TAtlasGutterSymbol.Overrides, TAtlasGutterSymbol.Overridden:
      mShown := OverridesPanel(ARow, mPanel);
  else
    mShown := False;
  end;
  if not mShown then
  begin
    Exit;
  end;
  FLinks := mPanel.Links;
  FHovering := True;
  FHover := ARow;
  TAtlasIdeStyle.Apply(FTip, FHoverScreen);
  FTip.ShowNote(mPanel.Title, mPanel.Text, mPanel.Captions, Point(FHoverScreen.Right + 4, FHoverScreen.Bottom + 2));
end;

end.
