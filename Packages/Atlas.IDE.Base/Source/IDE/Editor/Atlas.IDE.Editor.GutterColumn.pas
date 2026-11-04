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
//   und Textstand gemerkt).
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
  Vcl.Graphics,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Editor.GutterColumn,
  Atlas.Core.Lsp.Session,
  Atlas.UI.Popup.TitledTip;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasGutterColumnSessionFunc = reference to function: TLspSession;
  /// <summary>Code-Aktion anwenden; kommt von der Komposition, damit Editor nicht von Commands abhängt.</summary>
  TAtlasGutterColumnApplyProc = reference to procedure(const AAction: TLspCodeAction);

  TAtlasIdeGutterColumn = class
  public const
    OverridesCommand = 'atlas.server.overrideMarks';
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
  private const
    QuietMs = 600;
    HoverMs = 400;
    OverridesTimeoutMs = 800;
    ActionsTimeoutMs = 600;
    FixesTimeoutMs = 3000;
    RetryMs = 5000;
  private
    FSession: TAtlasGutterColumnSessionFunc;
    FOpenActions: TProc;
    FApply: TAtlasGutterColumnApplyProc;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FColumn: Integer;
    FWidth: Integer;
    FWantedWidth: Integer;
    FTimer: TTimer;
    /// <summary>Anmeldung bei TAtlasIdeGutterColumns: Spalte vor dem Abbau eines Editorfensters abgeben (#1233).</summary>
    FColumnsHandle: Integer;
    FTip: TAtlasTitledTip;
    FLinks: TArray<TProc>;
    FOptions: TAtlasGutterColumnOptions;
    FRows: TDictionary<Integer, TRow>;
    // Oberer Editor und Tipp-Pause.
    FFileName: string;
    FText: string;
    FCaretLine: Integer;
    FChangedAt: UInt64;
    FRetryAt: UInt64;
    // Überschreibungen vom Server.
    FFetchedFile: string;
    FFetchedText: string;
    FOverrides: TAtlasFileOverrides;
    // Glühbirne der Cursorzeile.
    FActionFile: string;
    FActionText: string;
    FActionLine: Integer;
    FActionAsked: Boolean;
    FActionFound: Boolean;
    // Probleme der Datei, neu gelesen bei neuer Version des Speichers.
    FProblemsFile: string;
    FProblemsVersion: Integer;
    FProblems: TArray<TAtlasProblem>;
    // Überfahren.
    FHover: TRow;
    FHovering: Boolean;
    FHoverSince: UInt64;
    FHoverScreen: TRect;
    function Active: Boolean;
    function TopView: IOTAEditView;
    function Services: INTACodeEditorServices280;
    procedure EnsureColumn;
    procedure DropColumn;
    procedure Tick(Sender: TObject);
    procedure ReadOptions;
    procedure Track;
    procedure FetchOverrides(ASession: TLspSession);
    procedure FetchAction(ASession: TLspSession);
    procedure Clear;
    function ProblemsOf(const AFileName: string): TArray<TAtlasProblem>;
    function LineOf(const AFileName: string; ALine: Integer; const ALineText: string; AHasText: Boolean;
      out AOverrides: TAtlasGutterOverrides): TAtlasGutterLine;
    function RowAt(X, Y: Integer; out ARow: TRow): Boolean;
    procedure PaintSymbol(ACanvas: TCanvas; const ARect: TRect; ASymbol: TAtlasGutterSymbol;
      const AColors: TAtlasColors; ABack: TAtlasColor);
    procedure PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure CheckHover;
    procedure HideTip;
    procedure ShowPanel(const ARow: TRow; AFetchFixes: Boolean);
    procedure Click(const ARow: TRow);
    procedure OpenActions(const ARow: TRow);
    function TargetsOf(const ARow: TRow): TArray<TAtlasGutterTarget>;
    procedure AddLink(var ACaptions: TArray<string>; const ACaption: string; const AAction: TProc);
    function FixAction(const AFix: TLspCodeAction): TProc;
    function TargetAction(const ATarget: TAtlasGutterTarget): TProc;
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
  System.JSON,
  Vcl.Forms,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Problems.Store,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.Recursion,
  Atlas.UI.Strings,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.GutterColumns,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorRefresh;

procedure InvalidateTop;
var
  Editors: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Editors) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(Editors);
  end;
end;

function IsSource(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := ExtractFileExt(AFileName);
  Result := SameText(Extension, '.pas') or SameText(Extension, '.dpr') or SameText(Extension, '.dpk') or
    SameText(Extension, '.inc');
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

{ TAtlasIdeGutterColumn }

constructor TAtlasIdeGutterColumn.Create(const ASession: TAtlasGutterColumnSessionFunc; const AOpenActions: TProc;
  const AApply: TAtlasGutterColumnApplyProc);
var
  Editors: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FOpenActions := AOpenActions;
  FApply := AApply;
  FIndex := -1;
  FColumn := -1;
  FActionLine := -1;
  FCaretLine := -1;
  FProblemsVersion := -1;
  FOptions := TAtlasGutterColumnOptions.All;
  FRows := TDictionary<Integer, TRow>.Create;
  FTip := TAtlasTitledTip.Create(nil);
  FTip.GuardFeature := TAtlasFeature.GutterColumn;
  FTip.OnLink :=
    procedure(AIndex: Integer)
    var
      Action: TProc;
    begin
      HideTip;
      FHovering := False;
      if (AIndex >= 0) and (AIndex <= High(FLinks)) then
      begin
        Action := FLinks[AIndex];
        if Assigned(Action) then
        begin
          Action();
        end;
      end;
    end;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintGutter := PaintGutter;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Editors) then
  begin
    FIndex := Editors.AddEditorEventsNotifier(FEventsRef);
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
  Editors: INTACodeEditorServices;
begin
  FTimer.Free;
  TAtlasIdeGutterColumns.Unregister(FColumnsHandle);
  // Erst Spalte und Notifier abmelden, dann freigeben (#493).
  DropColumn;
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Editors) then
  begin
    Editors.RemoveEditorEventsNotifier(FIndex);
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
  inherited Destroy;
end;

function TAtlasIdeGutterColumn.Services: INTACodeEditorServices280;
begin
  if not Supports(BorlandIDEServices, INTACodeEditorServices280, Result) then
  begin
    Result := nil;
  end;
end;

function TAtlasIdeGutterColumn.Active: Boolean;
begin
  Result := (FIndex >= 0) and not TAtlasGuard.Disabled(TAtlasFeature.GutterColumn) and
    TAtlasIdeSettings.GutterColumnOn;
end;

function TAtlasIdeGutterColumn.TopView: IOTAEditView;
var
  Editors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
  begin
    Result := Editors.TopView;
  end;
end;

procedure TAtlasIdeGutterColumn.EnsureColumn;
var
  Editors: INTACodeEditorServices280;
begin
  if FWantedWidth <= 0 then
  begin
    FWantedWidth := TAtlasGutterColumn.Width(MulDiv(TAtlasGutterColumn.BaseWidth, Screen.PixelsPerInch, 96));
  end;
  if (FColumn >= 0) and (FWidth = FWantedWidth) then
  begin
    Exit;
  end;
  Editors := Services;
  // Kurz nach dem Abbau eines Editorfensters nicht wieder anfordern (#1233, TAtlasIdeGutterColumns).
  if (Editors = nil) or not TAtlasIdeGutterColumns.Allowed then
  begin
    Exit;
  end;
  DropColumn;
  FColumn := Editors.RequestGutterColumn(FIndex, FWantedWidth, gclAfterLineNumbers);
  FWidth := FWantedWidth;
  FRows.Clear;
  TAtlasIdeEditorRefresh.InvalidateTop(Editors);
end;

procedure TAtlasIdeGutterColumn.DropColumn;
var
  Editors: INTACodeEditorServices280;
begin
  if FColumn < 0 then
  begin
    Exit;
  end;
  Editors := Services;
  if Editors <> nil then
  begin
    Editors.RemoveGutterColumn(FColumn);
    TAtlasIdeEditorRefresh.InvalidateTop(Editors);
  end;
  FColumn := -1;
  FRows.Clear;
end;

procedure TAtlasIdeGutterColumn.Clear;
begin
  FFetchedFile := '';
  FFetchedText := '';
  FOverrides := Default(TAtlasFileOverrides);
  FActionFile := '';
  FActionFound := False;
  FActionAsked := False;
  FProblemsFile := '';
  FProblems := nil;
  FFileName := '';
end;

procedure TAtlasIdeGutterColumn.ReadOptions;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  FOptions.Problems := Settings.GutterColumnProblems;
  FOptions.CodeActions := Settings.GutterColumnCodeActions;
  FOptions.Overrides := Settings.GutterColumnOverrides;
end;

procedure TAtlasIdeGutterColumn.Tick(Sender: TObject);
begin
  try
    if not Active then
    begin
      HideTip;
      FHovering := False;
      if FColumn >= 0 then
      begin
        DropColumn;
        Clear;
      end;
      Exit;
    end;
    ReadOptions;
    EnsureColumn;
    Track;
    CheckHover;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.GutterColumn, E);
  end;
end;

procedure TAtlasIdeGutterColumn.Track;
var
  View: IOTAEditView;
  Text: string;
  Moment: UInt64;
  Session: TLspSession;
  Store: TAtlasProblemStore;
begin
  View := TopView;
  if (View = nil) or (View.Buffer = nil) or not IsSource(View.Buffer.FileName) then
  begin
    Exit;
  end;
  // Neue Diagnosen: neu zeichnen, damit die Symbole folgen.
  Store := TAtlasProblemsController.Current;
  if (Store <> nil) and SameText(FProblemsFile, View.Buffer.FileName) and (Store.Version <> FProblemsVersion) then
  begin
    InvalidateTop;
  end;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  if not SameText(FFileName, View.Buffer.FileName) or (FText <> Text) or (FCaretLine <> View.CursorPos.Line - 1) then
  begin
    if not SameText(FFileName, View.Buffer.FileName) then
    begin
      FRows.Clear;
    end;
    FFileName := View.Buffer.FileName;
    FText := Text;
    FCaretLine := View.CursorPos.Line - 1;
    FChangedAt := TThread.GetTickCount64;
    Exit;
  end;
  Moment := TThread.GetTickCount64;
  if (Moment - FChangedAt < QuietMs) or (Moment < FRetryAt) then
  begin
    Exit;
  end;
  Session := nil;
  if Assigned(FSession) then
  begin
    Session := FSession();
  end;
  if Session = nil then
  begin
    Exit;
  end;
  if FOptions.Overrides and not (SameText(FFetchedFile, FFileName) and (FFetchedText = FText)) then
  begin
    FetchOverrides(Session);
  end;
  if FOptions.CodeActions and not (FActionAsked and SameText(FActionFile, FFileName) and
    (FActionLine = FCaretLine) and (FActionText = TAtlasRecursionMarks.LineOf(FText, FCaretLine))) then
  begin
    FetchAction(Session);
  end;
end;

procedure TAtlasIdeGutterColumn.FetchOverrides(ASession: TLspSession);
var
  Values: TJSONArray;
  Arguments: string;
  Answer: TJSONValue;
begin
  Values := TJSONArray.Create;
  try
    Values.Add(TLspSession.PathToUri(FFileName));
    Arguments := Values.ToJSON;
  finally
    Values.Free;
  end;
  try
    ASession.Sync(FFileName, FText);
    Answer := ASession.RunCommand(OverridesCommand, Arguments, OverridesTimeoutMs);
  except
    on E: ELspClientError do
    begin
      // Server beschäftigt, weg oder zu alt (Befehl unbekannt): später noch einmal, ohne den Editor zu bremsen.
      FRetryAt := TThread.GetTickCount64 + RetryMs;
      Exit;
    end;
  end;
  try
    FOverrides := TAtlasFileOverrides.FromJson(Answer,
      function(AUri: string): string
      begin
        Result := TLspSession.UriToPath(AUri);
      end);
  finally
    Answer.Free;
  end;
  FFetchedFile := FFileName;
  FFetchedText := FText;
  InvalidateTop;
end;

procedure TAtlasIdeGutterColumn.FetchAction(ASession: TLspSession);
var
  LineText: string;
  Found: TArray<TLspCodeAction>;
  Action: TLspCodeAction;
  Had: Boolean;
begin
  LineText := TAtlasRecursionMarks.LineOf(FText, FCaretLine);
  Had := FActionFound;
  FActionFile := FFileName;
  FActionLine := FCaretLine;
  FActionText := LineText;
  FActionAsked := True;
  FActionFound := False;
  try
    ASession.Sync(FFileName, FText);
    Found := ASession.CodeActions(FFileName, TLspRange.Create(FCaretLine, 0, FCaretLine, Length(LineText)),
      ActionsTimeoutMs);
  except
    on E: ELspClientError do
    begin
      FRetryAt := TThread.GetTickCount64 + RetryMs;
      Found := nil;
    end;
  end;
  for Action in Found do
  begin
    if Action.Disabled = '' then
    begin
      FActionFound := True;
      Break;
    end;
  end;
  if Had or FActionFound then
  begin
    InvalidateTop;
  end;
end;

function TAtlasIdeGutterColumn.ProblemsOf(const AFileName: string): TArray<TAtlasProblem>;
var
  Store: TAtlasProblemStore;
begin
  Store := TAtlasProblemsController.Current;
  Result := nil;
  if Store = nil then
  begin
    Exit;
  end;
  if not SameText(FProblemsFile, AFileName) or (FProblemsVersion <> Store.Version) then
  begin
    FProblemsFile := AFileName;
    FProblemsVersion := Store.Version;
    FProblems := Store.ForFile(AFileName);
  end;
  Result := FProblems;
end;

function TAtlasIdeGutterColumn.LineOf(const AFileName: string; ALine: Integer; const ALineText: string;
  AHasText: Boolean; out AOverrides: TAtlasGutterOverrides): TAtlasGutterLine;
begin
  Result := Default(TAtlasGutterLine);
  AOverrides := Default(TAtlasGutterOverrides);
  if FOptions.Problems then
  begin
    Result.Problem := TAtlasGutterColumn.ProblemSymbol(ProblemsOf(AFileName), ALine);
  end;
  if FOptions.CodeActions and FActionFound and (ALine = FActionLine) and SameText(AFileName, FActionFile) then
  begin
    Result.Action := not AHasText or TAtlasRecursionMarks.LineMatches(ALineText, FActionText);
  end;
  // Zeile seit dem Abruf geändert: Die Pfeile warten auf die nächste Antwort.
  if FOptions.Overrides and SameText(AFileName, FFetchedFile) and FOverrides.At(ALine, AOverrides) and
    (not AHasText or TAtlasRecursionMarks.LineMatches(ALineText, TAtlasRecursionMarks.LineOf(FFetchedText, ALine))) then
  begin
    Result.Overrides := Length(AOverrides.Overrides) > 0;
    Result.Overridden := Length(AOverrides.Overridden) > 0;
  end;
end;

procedure TAtlasIdeGutterColumn.PaintSymbol(ACanvas: TCanvas; const ARect: TRect; ASymbol: TAtlasGutterSymbol;
  const AColors: TAtlasColors; ABack: TAtlasColor);
var
  Size, Left, Top, Mid, Center, Pen, Head: Integer;
  Color: TColor;
begin
  Size := Max(6, Min(ARect.Width, ARect.Height) - 4);
  Left := ARect.Left + (ARect.Width - Size) div 2;
  Top := ARect.Top + (ARect.Height - Size) div 2;
  Mid := Top + Size div 2;
  Center := Left + Size div 2;
  Pen := Max(1, Size div 7);
  case ASymbol of
    TAtlasGutterSymbol.Error:
      Color := TColor(TAtlasColorMath.Mix(AColors.Error, ABack, 0.95));
    TAtlasGutterSymbol.Warning:
      Color := TColor(TAtlasColorMath.Mix(AColors.Warn, ABack, 0.95));
    TAtlasGutterSymbol.Hint:
      Color := TColor(TAtlasColorMath.Mix(AColors.Muted, ABack, 0.9));
    TAtlasGutterSymbol.Action:
      Color := TColor(TAtlasColorMath.Mix(AColors.Accent, ABack, 0.95));
  else
    Color := TColor(TAtlasColorMath.Mix(AColors.Add, ABack, 0.95));
  end;
  ACanvas.Pen.Color := Color;
  ACanvas.Pen.Width := Pen;
  ACanvas.Brush.Color := Color;
  ACanvas.Brush.Style := bsSolid;
  case ASymbol of
    TAtlasGutterSymbol.Error:
      begin
        // ✕: zwei Diagonalen.
        ACanvas.MoveTo(Left + 1, Top + 1);
        ACanvas.LineTo(Left + Size - 1, Top + Size - 1);
        ACanvas.MoveTo(Left + Size - 2, Top + 1);
        ACanvas.LineTo(Left, Top + Size - 1);
      end;
    TAtlasGutterSymbol.Warning:
      begin
        // ▲: gefülltes Dreieck.
        ACanvas.Pen.Width := 1;
        ACanvas.Polygon([Point(Center, Top), Point(Left + Size - 1, Top + Size - 1), Point(Left, Top + Size - 1)]);
      end;
    TAtlasGutterSymbol.Hint:
      begin
        // ●: kleiner Punkt.
        ACanvas.Pen.Width := 1;
        ACanvas.Ellipse(Center - Size div 4, Mid - Size div 4, Center + Size div 4 + 1, Mid + Size div 4 + 1);
      end;
    TAtlasGutterSymbol.Action:
      begin
        // ◆: Raute.
        ACanvas.Pen.Width := 1;
        ACanvas.Polygon([Point(Center, Top), Point(Left + Size - 1, Mid), Point(Center, Top + Size - 1),
          Point(Left, Mid)]);
      end;
    TAtlasGutterSymbol.Overrides, TAtlasGutterSymbol.Overridden:
      begin
        // ↑ bzw. ↓: Schaft und gefüllte Spitze.
        Head := Max(2, Size div 3);
        ACanvas.Pen.Width := 1;
        if ASymbol = TAtlasGutterSymbol.Overrides then
        begin
          ACanvas.Polygon([Point(Center, Top), Point(Center + Head, Top + Head), Point(Center - Head, Top + Head)]);
          ACanvas.Pen.Width := Pen;
          ACanvas.MoveTo(Center, Top + Head);
          ACanvas.LineTo(Center, Top + Size - 1);
        end
        else
        begin
          ACanvas.Polygon([Point(Center, Top + Size - 1), Point(Center + Head, Top + Size - 1 - Head),
            Point(Center - Head, Top + Size - 1 - Head)]);
          ACanvas.Pen.Width := Pen;
          ACanvas.MoveTo(Center, Top);
          ACanvas.LineTo(Center, Top + Size - 1 - Head);
        end;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TAtlasIdeGutterColumn.PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Row: TRow;
  LineState: INTACodeEditorLineState;
  LineText: string;
  HasText: Boolean;
  Overrides: TAtlasGutterOverrides;
  Canvas: TCanvas;
  Sample: COLORREF;
  Back: TAtlasColor;
  OldBrush: TBrush;
  OldPen: TPen;
begin
  if BeforeEvent or (Stage <> High(TPaintGutterStage)) or (FColumn < 0) or (Context = nil) or
    (Context.EditView = nil) or (Context.EditorState = nil) then
  begin
    Exit;
  end;
  try
    if not Active then
    begin
      Exit;
    end;
    // Schrift oder Skalierung geändert: Der Zeitgeber fordert die Spalte neu an.
    if Context.CellSize.cy > 0 then
    begin
      FWantedWidth := TAtlasGutterColumn.Width(Context.CellSize.cy);
    end;
    Row := Default(TRow);
    Row.FileName := Context.FileName;
    Row.Line := Context.LogicalLineNum - 1;
    Row.TopRow := Context.EditView.TopRow;
    Row.Rect := Context.EditorState.GetGutterColumnRect(Context.EditControl, Context.EditorLineNum, FColumn);
    LineState := Context.LineState;
    HasText := LineState <> nil;
    LineText := '';
    if HasText then
    begin
      LineText := LineState.Text;
    end;
    Row.Symbol := TAtlasGutterSymbol.None;
    if IsSource(Context.FileName) and (Row.Line >= 0) and not Row.Rect.IsEmpty then
    begin
      Row.Symbol := TAtlasGutterColumn.Choose(LineOf(Context.FileName, Row.Line, LineText, HasText, Overrides),
        FOptions);
    end;
    // In .atlas ausgeblendet (#628): ganze Datei oder diese Codezeile.
    if (Row.Symbol <> TAtlasGutterSymbol.None) and
      TAtlasIdeElements.Hidden(TAtlasDrawnElement.GutterColumn, Context.FileName, LineText) then
    begin
      Row.Symbol := TAtlasGutterSymbol.None;
    end;
    FRows.AddOrSetValue(Context.EditorLineNum, Row);
    if Row.Symbol = TAtlasGutterSymbol.None then
    begin
      Exit;
    end;
    Canvas := Context.Canvas;
    // Farben aus dem Grund der Spalte: hell oder dunkel wie das Thema der IDE.
    Sample := GetPixel(Canvas.Handle, Row.Rect.Left + 1, Row.Rect.Top + 1);
    if Sample = CLR_INVALID then
    begin
      Back := TAtlasColor(ColorToRGB(Canvas.Brush.Color));
    end
    else
    begin
      Back := TAtlasColor(Sample);
    end;
    OldBrush := TBrush.Create;
    OldPen := TPen.Create;
    try
      OldBrush.Assign(Canvas.Brush);
      OldPen.Assign(Canvas.Pen);
      PaintSymbol(Canvas, Row.Rect, Row.Symbol, TAtlasColors.ForBackground(Back), Back);
    finally
      Canvas.Brush.Assign(OldBrush);
      Canvas.Pen.Assign(OldPen);
      OldPen.Free;
      OldBrush.Free;
    end;
    TAtlasIdeElements.Painted(TAtlasDrawnElement.GutterColumn, Context.FileName, Row.Line, LineText, Row.Rect,
      Row.TopRow, Row.Rect.Height);
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.GutterColumn, E);
  end;
end;

function TAtlasIdeGutterColumn.RowAt(X, Y: Integer; out ARow: TRow): Boolean;
var
  Row: TRow;
  View: IOTAEditView;
begin
  ARow := Default(TRow);
  Result := False;
  View := TopView;
  if (View = nil) or (View.Buffer = nil) then
  begin
    Exit;
  end;
  for Row in FRows.Values do
  begin
    if (Row.Symbol <> TAtlasGutterSymbol.None) and PtInRect(Row.Rect, Point(X, Y)) then
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

procedure TAtlasIdeGutterColumn.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  Row: TRow;
begin
  try
    if not Active or not RowAt(X, Y, Row) then
    begin
      FHovering := False;
      HideTip;
      Exit;
    end;
    if FHovering and SameText(FHover.FileName, Row.FileName) and (FHover.Line = Row.Line) then
    begin
      Exit;
    end;
    HideTip;
    FHover := Row;
    FHovering := True;
    FHoverSince := TThread.GetTickCount64;
    FHoverScreen := TRect.Create(Editor.ClientToScreen(Row.Rect.TopLeft), Editor.ClientToScreen(Row.Rect.BottomRight));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.GutterColumn, E);
  end;
end;

procedure TAtlasIdeGutterColumn.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Row: TRow;
begin
  try
    if (Button <> mbLeft) or not Active or not RowAt(X, Y, Row) then
    begin
      Exit;
    end;
    HideTip;
    FHovering := False;
    FHoverScreen := TRect.Create(Editor.ClientToScreen(Row.Rect.TopLeft), Editor.ClientToScreen(Row.Rect.BottomRight));
    Click(Row);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.GutterColumn, E);
  end;
end;

procedure TAtlasIdeGutterColumn.CheckHover;
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

function TAtlasIdeGutterColumn.TargetsOf(const ARow: TRow): TArray<TAtlasGutterTarget>;
var
  Entry: TAtlasGutterOverrides;
begin
  Result := nil;
  if SameText(ARow.FileName, FFetchedFile) and FOverrides.At(ARow.Line, Entry) then
  begin
    Result := Entry.Overrides + Entry.Overridden;
  end;
end;

procedure TAtlasIdeGutterColumn.Click(const ARow: TRow);
var
  Targets: TArray<TAtlasGutterTarget>;
begin
  case ARow.Symbol of
    TAtlasGutterSymbol.Action:
      OpenActions(ARow);
    TAtlasGutterSymbol.Overrides, TAtlasGutterSymbol.Overridden:
      begin
        // Ein Ziel: gleich hin; mehrere: Liste mit Datei und Zeile.
        Targets := TargetsOf(ARow);
        if Length(Targets) = 1 then
        begin
          TAtlasIdeNavigation.GoToLocation(Targets[0].FileName, Targets[0].Line, Targets[0].Character);
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
  View: IOTAEditView;
  Position: TOTAEditPos;
  Text: string;
  Column: Integer;
begin
  View := TopView;
  if (View = nil) or (View.Buffer = nil) or not SameText(View.Buffer.FileName, ARow.FileName) then
  begin
    Exit;
  end;
  // Cursor an den Anfang des Codes der Zeile, dann die Code-Aktionen wie über das Kontextmenü.
  Text := TAtlasEditorBuffer.LineText(View, ARow.Line + 1);
  Column := 1;
  while (Column <= Length(Text)) and CharInSet(Text[Column], [' ', #9]) do
  begin
    Inc(Column);
  end;
  Position.Line := ARow.Line + 1;
  Position.Col := Column;
  View.CursorPos := Position;
  View.MoveViewToCursor;
  View.Paint;
  if Assigned(FOpenActions) then
  begin
    FOpenActions();
  end;
end;

procedure TAtlasIdeGutterColumn.AddLink(var ACaptions: TArray<string>; const ACaption: string;
  const AAction: TProc);
begin
  ACaptions := ACaptions + [ACaption];
  FLinks := FLinks + [AAction];
end;

function TAtlasIdeGutterColumn.FixAction(const AFix: TLspCodeAction): TProc;
var
  Fix: TLspCodeAction;
begin
  Fix := AFix;
  Result :=
    procedure
    begin
      if Assigned(FApply) then
      begin
        FApply(Fix);
      end;
    end;
end;

function TAtlasIdeGutterColumn.TargetAction(const ATarget: TAtlasGutterTarget): TProc;
var
  Target: TAtlasGutterTarget;
begin
  Target := ATarget;
  Result :=
    procedure
    begin
      TAtlasIdeNavigation.GoToLocation(Target.FileName, Target.Line, Target.Character);
    end;
end;

function TAtlasIdeGutterColumn.ActionsAction(const ARow: TRow): TProc;
var
  Row: TRow;
begin
  Row := ARow;
  Result :=
    procedure
    begin
      OpenActions(Row);
    end;
end;

function SeverityText(ASeverity: TAtlasProblemSeverity): string;
begin
  case ASeverity of
    TAtlasProblemSeverity.Error:
      Result := TAtlasStrings.Text(TAtlasTextId.GutterSeverityError);
    TAtlasProblemSeverity.Warning:
      Result := TAtlasStrings.Text(TAtlasTextId.GutterSeverityWarning);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.GutterSeverityHint);
  end;
end;

procedure TAtlasIdeGutterColumn.ShowPanel(const ARow: TRow; AFetchFixes: Boolean);
var
  Title, Text, Prefix: string;
  Captions: TArray<string>;
  Problems: TArray<TAtlasProblem>;
  Problem: TAtlasProblem;
  Entry: TAtlasGutterOverrides;
  Target: TAtlasGutterTarget;
  Session: TLspSession;
  Fixes: TArray<TLspCodeAction>;
  Fix: TLspCodeAction;
  Row: TRow;
  Both: Boolean;
begin
  Row := ARow;
  Text := '';
  Captions := nil;
  FLinks := nil;
  case Row.Symbol of
    TAtlasGutterSymbol.Error, TAtlasGutterSymbol.Warning, TAtlasGutterSymbol.Hint:
      begin
        Problems := TAtlasGutterColumn.ProblemsAt(ProblemsOf(Row.FileName), Row.Line);
        if Length(Problems) = 0 then
        begin
          Exit;
        end;
        Title := TAtlasGutterColumn.ProblemTitle(Problems[0], SeverityText(Problems[0].Severity));
        for Problem in Problems do
        begin
          if Text <> '' then
          begin
            Text := Text + #10;
          end;
          if (Problem.Code <> '') and (Length(Problems) > 1) then
          begin
            Text := Text + Problem.Code + ': ';
          end;
          Text := Text + Problem.Message;
        end;
        if AFetchFixes then
        begin
          Fixes := nil;
          Session := nil;
          if Assigned(FSession) then
          begin
            Session := FSession();
          end;
          if Session <> nil then
            try
              Session.Sync(FFileName, FText);
              Fixes := Session.CodeActions(Row.FileName, TLspRange.Create(Problems[0].StartLine,
                Problems[0].StartCharacter, Problems[0].EndLine, Problems[0].EndCharacter), FixesTimeoutMs);
            except
              on E: ELspClientError do
              begin
                Fixes := nil;
                Text := Text + #10 + TAtlasStrings.Fmt(TAtlasTextId.GutterFixesFailed, [E.Message]);
              end;
            end;
          for Fix in Fixes do
          begin
            if (Fix.Disabled = '') and Fix.Kind.StartsWith('quickfix') then
            begin
              AddLink(Captions, Fix.Title, FixAction(Fix));
            end;
          end;
          if Length(Captions) = 0 then
          begin
            Text := Text + #10 + TAtlasStrings.Text(TAtlasTextId.GutterNoFix);
          end;
        end;
        AddLink(Captions, TAtlasStrings.Text(TAtlasTextId.GutterAllActions), ActionsAction(Row));
      end;
    TAtlasGutterSymbol.Action:
      begin
        Title := TAtlasStrings.Text(TAtlasTextId.GutterActionTitle);
        Text := TAtlasStrings.Text(TAtlasTextId.GutterActionText);
      end;
    TAtlasGutterSymbol.Overrides, TAtlasGutterSymbol.Overridden:
      begin
        if not SameText(Row.FileName, FFetchedFile) or not FOverrides.At(Row.Line, Entry) then
        begin
          Exit;
        end;
        Both := (Length(Entry.Overrides) > 0) and (Length(Entry.Overridden) > 0);
        if Row.Symbol = TAtlasGutterSymbol.Overrides then
        begin
          Title := TAtlasStrings.Text(TAtlasTextId.GutterOverridesTitle);
        end
        else
        begin
          Title := TAtlasStrings.Text(TAtlasTextId.GutterOverriddenTitle);
        end;
        Prefix := '';
        if Both then
        begin
          Prefix := '↑ ';
        end;
        for Target in Entry.Overrides do
        begin
          AddLink(Captions, Prefix + TAtlasGutterColumn.TargetText(Target), TargetAction(Target));
        end;
        if Both then
        begin
          Prefix := '↓ ';
        end;
        for Target in Entry.Overridden do
        begin
          AddLink(Captions, Prefix + TAtlasGutterColumn.TargetText(Target), TargetAction(Target));
        end;
        if Both then
        begin
          Text := TAtlasStrings.Text(TAtlasTextId.GutterOverridesTitle) + ' ↑ · ' +
            TAtlasStrings.Text(TAtlasTextId.GutterOverriddenTitle) + ' ↓';
        end;
      end;
  else
    Exit;
  end;
  FHovering := True;
  FHover := Row;
  TAtlasIdeStyle.Apply(FTip, FHoverScreen);
  FTip.ShowNote(Title, Text, Captions, Point(FHoverScreen.Right + 4, FHoverScreen.Bottom + 2));
end;

end.
