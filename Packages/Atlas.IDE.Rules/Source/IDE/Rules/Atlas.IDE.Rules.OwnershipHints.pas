unit Atlas.IDE.Rules.OwnershipHints;

// Marke „Wer gibt das frei?“ (#1877) am Ende jeder Zeile mit T.Create(…) im
// Modul Prüfregeln: grün „frei in Destroy, Z. 48“, gelb „weitergegeben an
// Registry.Add“, rot „nie freigegeben“. Lesen, Ton und Texte stehen in
// Atlas.Core.Rules.Ownership; hier bleiben Abruf, Zeichnen, Klick und Tooltip.
// - Abruf: Beim Zeichnen einer Zeile fragt die Marke den laufenden Server im
//   Hintergrund (atlas.server.ownership), wenn die Datei eine andere ist oder
//   die normale Prüfung dieser Datei seit dem letzten Abruf neu gelaufen ist
//   (TAtlasProblemsController.LastCheck). Kein eigener Zeitgeber; die Antwort
//   zeichnet den Editor über TAtlasIdeEditorRefresh neu.
// - Zeichnen: nur die Zeilen, die der Editor zeichnet (plsEndPaint), und nur,
//   solange die Zeile noch so lautet wie beim Abruf. Den Platz hinter dem
//   Zeilenende teilt die Marke über TAtlasLineTail mit Inlay-Hints und dem
//   Fehlertext am Zeilenende.
// - Klick springt zur freigebenden Zeile; Überfahren zeigt nach der üblichen
//   Verzögerung einen Tooltip mit dem Weg zur Einstufung (der Zeitgeber dafür
//   läuft nur, solange die Maus auf einer Marke steht).
// Abschaltbar über editor.ownershipHints (Vorgabe aus; aus = keine Anfrage),
// nur Problemfälle über editor.ownershipHints.onlyProblems; gehört zum
// Modulschalter ruleChecks. Ausblenden am Element (#628) je Zeile (Anker ist
// ihr Text) oder je Datei.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI.Editor,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Rules.Ownership,
  Atlas.UI.Popup.TitledTip;

type
  TAtlasIdeOwnershipHints = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;

    /// <summary>Lebt, solange die Marke lebt; Antwort und eingereihter Klick prüfen es. Generation zählt jede
    /// Anfrage: eine ältere Antwort zählt nicht mehr.</summary>
    TState = class(TInterfacedObject)
    public
      Alive: Boolean;
      Generation: Integer;
    end;

    /// <summary>Gezeichnete Marke: Rechteck (Koordinaten des Editors), oberste Zeile dabei, ihre Stellen.</summary>
    THit = record
      Rect: TRect;
      TopRow: Integer;
      Line: Integer;
      Marks: TArray<TAtlasOwnershipMark>;
    end;
  private
    FScope: IAtlasModuleScope;
    FState: TState;
    FStateRef: IInterface;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FFetch: TAtlasOwnershipFetch;
    /// <summary>Datei, zu der FMarks gehören.</summary>
    FFileName: string;
    FMarks: TArray<TAtlasOwnershipMark>;
    FTexts: TAtlasOwnershipTexts;
    FHits: TArray<THit>;
    FTip: TAtlasTitledTip;
    FHoverTimer: TTimer;
    FHover: Integer;
    FHoverSince: UInt64;
    FHoverScreen: TRect;
    procedure Clear;
    procedure AskIfDue(const AFileName: string);
    procedure Answered(AGeneration: Integer; const AFileName, AJson: string);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    /// <summary>Stellen der Zeile von AContext (fragt bei Bedarf neu); nil ohne Marke.</summary>
    function LineMarks(const AContext: INTACodeEditorPaintContext; out ALine: string): TArray<TAtlasOwnershipMark>;
    procedure PaintMarks(const ARect: TRect; const AContext: INTACodeEditorPaintContext; const ALine: string;
      const AMarks: TArray<TAtlasOwnershipMark>);
    procedure Remember(const AHit: THit);
    function HitAt(AX, AY: Integer): Integer;
    function StillShown(const AHit: THit): Boolean;
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure HoverTick(Sender: TObject);
    procedure HideTip;
    procedure QueueJump(ALine: Integer);
  public
    /// <summary>AScope ist der Scope des Moduls: Antworten erreichen die Marke nur, solange er offen ist.</summary>
    constructor Create(const AScope: IAtlasModuleScope);
    destructor Destroy; override;
    /// <summary>Nach geänderten Einstellungen neu zeichnen; aus = Marken weg, ein laufender Abruf zählt nicht mehr.
    /// </summary>
    procedure ApplySettings;
    /// <summary>Marken zeichnen und fragen? editor.ownershipHints an, Atlas an, Prüfung nicht gesperrt.</summary>
    class function Wanted: Boolean; static;
    /// <summary>Texte in der Sprache der IDE.</summary>
    class function Texts: TAtlasOwnershipTexts; static;
  end;

implementation

uses
  System.StrUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Editor.CloseRules,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.LineTail,
  Atlas.Core.Lsp.Session.Json,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Rules.Strings,
  Atlas.IDE.Editor.Lens,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Problems.Controller;

const
  cTimeoutMs = 20000;
  cHoverTickMs = 100;
  /// <summary>Anteil des Tons an Rahmen und Füllung der Marke wie bei der Code Lens der Kennzahlen.</summary>
  cPillBorder = 0.3;
  cPillFill = 0.1;

{ TAtlasIdeOwnershipHints.TEvents }

function TAtlasIdeOwnershipHints.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents];
end;

function TAtlasIdeOwnershipHints.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ Hilfen }

procedure InvalidateEditor;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
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

/// <summary>Antwort an die Marke, solange sie lebt (Regel 3); eigene Routine, damit die Referenz nur Zustand,
/// Generation und Datei einfängt.</summary>
function AnswerFor(AHints: TAtlasIdeOwnershipHints; const AState: IInterface; AGeneration: Integer;
  const AFileName: string): TProc<string>;
var
  mHints: TAtlasIdeOwnershipHints;
  mState: IInterface;
  mGeneration: Integer;
  mFileName: string;
begin
  mHints := AHints;
  mState := AState;
  mGeneration := AGeneration;
  mFileName := AFileName;
  Result :=
    procedure(AJson: string)
    begin
      if TAtlasIdeOwnershipHints.TState(mState as TObject).Alive then
      begin
        mHints.Answered(mGeneration, mFileName, AJson);
      end;
    end;
end;

{ TAtlasIdeOwnershipHints }

constructor TAtlasIdeOwnershipHints.Create(const AScope: IAtlasModuleScope);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FScope := AScope;
  FState := TState.Create;
  FState.Alive := True;
  FStateRef := FState;
  FIndex := -1;
  FHover := -1;
  FTexts := Texts;
  FTip := TAtlasTitledTip.Create(nil);
  FTip.GuardFeature := TAtlasFeature.Problems;
  FHoverTimer := TTimer.Create(nil);
  FHoverTimer.Enabled := False;
  FHoverTimer.Interval := cHoverTickMs;
  FHoverTimer.OnTimer := HoverTick;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
  if Wanted then
  begin
    InvalidateEditor;
  end;
end;

destructor TAtlasIdeOwnershipHints.Destroy;
var
  mServices: INTACodeEditorServices;
  mShowing: Boolean;
begin
  FState.Alive := False;
  FStateRef := nil;
  FHoverTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintLine := nil;
    FEvents.OnEditorMouseDown := nil;
    FEvents.OnEditorMouseMove := nil;
  end;
  FEventsRef := nil;
  FTip.Free;
  mShowing := FMarks <> nil;
  FMarks := nil;
  FHits := nil;
  FScope := nil;
  if mShowing then
  begin
    InvalidateEditor;
  end;
  inherited Destroy;
end;

class function TAtlasIdeOwnershipHints.Wanted: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.OwnershipHints and not TAtlasGuard.Disabled(TAtlasFeature.Problems);
end;

class function TAtlasIdeOwnershipHints.Texts: TAtlasOwnershipTexts;
begin
  Result := Default(TAtlasOwnershipTexts);
  Result.Labels[TAtlasOwnershipKind.InDestroy] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipDestroy);
  Result.Labels[TAtlasOwnershipKind.InFinally] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipFinally);
  Result.Labels[TAtlasOwnershipKind.Freed] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipFreed);
  Result.Labels[TAtlasOwnershipKind.Owner] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipOwner);
  Result.Labels[TAtlasOwnershipKind.OwnedList] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipOwnedList);
  Result.Labels[TAtlasOwnershipKind.RefCounted] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipInterface);
  Result.Labels[TAtlasOwnershipKind.Returned] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipReturned);
  Result.Labels[TAtlasOwnershipKind.Passed] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipPassed);
  Result.Labels[TAtlasOwnershipKind.Unknown] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipUnknown);
  Result.Labels[TAtlasOwnershipKind.Never] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipNever);
  Result.FreedIn := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipFreedIn);
  Result.PassedSomewhere := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipPassedSomewhere);
  Result.Reasons[TAtlasOwnershipKind.InDestroy] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipWhyDestroy);
  Result.Reasons[TAtlasOwnershipKind.InFinally] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipWhyFinally);
  Result.Reasons[TAtlasOwnershipKind.Freed] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipWhyFreed);
  Result.Reasons[TAtlasOwnershipKind.Owner] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipWhyOwner);
  Result.Reasons[TAtlasOwnershipKind.OwnedList] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipWhyOwnedList);
  Result.Reasons[TAtlasOwnershipKind.RefCounted] :=
    TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipWhyInterface);
  Result.Reasons[TAtlasOwnershipKind.Returned] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipWhyReturned);
  Result.Reasons[TAtlasOwnershipKind.Passed] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipWhyPassed);
  Result.Reasons[TAtlasOwnershipKind.Unknown] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipWhyUnknown);
  Result.Reasons[TAtlasOwnershipKind.Never] := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipWhyNever);
  Result.ContainerLabels[TAtlasOwnershipContainer.OwnsElements] :=
    TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipOwnsElements);
  Result.ContainerLabels[TAtlasOwnershipContainer.ElementsOwned] :=
    TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipElementsOwned);
  Result.ContainerReasons[TAtlasOwnershipContainer.OwnsElements] :=
    TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipWhyOwnsElements);
  Result.ContainerReasons[TAtlasOwnershipContainer.ElementsOwned] :=
    TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipWhyElementsOwned);
  Result.Title := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipTipTitle);
  Result.Jump := TAtlasRulesStrings.Text(TAtlasRulesTextId.OwnershipTipJump);
end;

procedure TAtlasIdeOwnershipHints.Clear;
var
  mShowing: Boolean;
begin
  mShowing := FMarks <> nil;
  Inc(FState.Generation);
  FFetch.Reset;
  FFileName := '';
  FMarks := nil;
  FHits := nil;
  HideTip;
  if mShowing then
  begin
    InvalidateEditor;
  end;
end;

procedure TAtlasIdeOwnershipHints.ApplySettings;
begin
  FTexts := Texts;
  if not Wanted then
  begin
    Clear;
    Exit;
  end;
  // An und aus von „nur Problemfälle“ zeichnet nur neu; die Antwort enthält alle Stellen.
  InvalidateEditor;
end;

procedure TAtlasIdeOwnershipHints.AskIfDue(const AFileName: string);
var
  mCheck: TAtlasProblemsCheck;
begin
  mCheck := TAtlasProblemsController.LastCheck;
  if not FFetch.Due(AFileName, mCheck.FileName, mCheck.At) then
  begin
    Exit;
  end;
  // Auch ohne Server gilt der Stand als gefragt: Die nächste Prüfung fragt erneut, nicht jede gezeichnete Zeile.
  FFetch.Asked(AFileName, mCheck.FileName, mCheck.At);
  Inc(FState.Generation);
  TAtlasIdeHost.RunServerCommandAsync(FScope, TAtlasFeature.Problems, TAtlasOwnershipMarks.cCommand,
    TAtlasOwnershipMarks.Arguments(TLspSessionJson.PathToUri(AFileName)), cTimeoutMs,
    AnswerFor(Self, FStateRef, FState.Generation, AFileName));
end;

procedure TAtlasIdeOwnershipHints.Answered(AGeneration: Integer; const AFileName, AJson: string);
begin
  if (AGeneration <> FState.Generation) or not Wanted then
  begin
    Exit;
  end;
  // Keine Antwort (Zeitgrenze, Fehler): die bisherigen Marken der Datei bleiben, ihr Zeilentext schützt sie.
  if AJson = '' then
  begin
    Exit;
  end;
  FFileName := AFileName;
  FMarks := TAtlasOwnershipMarks.Parse(AJson);
  FHits := nil;
  HideTip;
  InvalidateEditor;
end;

function TAtlasIdeOwnershipHints.LineMarks(const AContext: INTACodeEditorPaintContext;
  out ALine: string): TArray<TAtlasOwnershipMark>;
begin
  Result := nil;
  ALine := '';
  if (AContext.LineState = nil) or (AContext.EditView = nil) or (AContext.EditView.Buffer = nil) or
    not MatchText(ExtractFileExt(AContext.FileName), ['.pas', '.dpr']) then
  begin
    Exit;
  end;
  AskIfDue(AContext.FileName);
  if SameText(AContext.FileName, FFileName) then
  begin
    ALine := AContext.LineState.Text;
    Result := TAtlasOwnershipMarks.AtLine(TAtlasOwnershipMarks.Visible(FMarks,
      TAtlasIdeSettings.Current.OwnershipHintsOnlyProblems), AContext.LogicalLineNum - 1, ALine);
  end;
  // Ausgeblendet am Element (#628): Anker ist der Text der Zeile.
  if (Result <> nil) and TAtlasIdeElements.Hidden(TAtlasDrawnElement.OwnershipHints, AContext.FileName, ALine) then
  begin
    Result := nil;
  end;
end;

procedure TAtlasIdeOwnershipHints.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mLine: string;
  mMarks: TArray<TAtlasOwnershipMark>;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
  begin
    Exit;
  end;
  try
    if Wanted then
    begin
      mMarks := LineMarks(Context, mLine);
      if mMarks <> nil then
      begin
        PaintMarks(Rect, Context, mLine, mMarks);
      end;
    end
    else if FMarks <> nil then
    begin
      Clear;
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
  end;
end;

procedure TAtlasIdeOwnershipHints.PaintMarks(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  const ALine: string; const AMarks: TArray<TAtlasOwnershipMark>);
var
  mTailKey: string;
  mCell: TRect;
  mBack, mTone: TAtlasColor;
  mColors: TAtlasColors;
  mHit: THit;
begin
  mCell := TAtlasLensPill.CellAfter(AContext, ALine);
  mTailKey := TAtlasLineTail.KeyOf(AContext.FileName, AContext.LogicalLineNum, AContext.EditorLineNum, ARect.Top);
  mBack := TAtlasLensPill.BackAt(AContext.Canvas, mCell.Left, ARect.Top + 1);
  mColors := TAtlasColors.ForBackground(mBack);
  case TAtlasOwnershipMarks.LineTone(AMarks) of
    TAtlasOwnershipTone.Safe:
      mTone := mColors.Add;
    TAtlasOwnershipTone.Never:
      mTone := mColors.Error;
  else
    mTone := mColors.Warn;
  end;
  mHit := Default(THit);
  mHit.Rect := TAtlasLensPill.Paint(AContext.Canvas, ARect, TAtlasLineTail.Start(Self, mTailKey, mCell.Left),
    TAtlasOwnershipMarks.LineCaption(AMarks, FTexts),
    TAtlasLensPillStyle.Create(mTone, mBack, cPillBorder, cPillFill, []));
  TAtlasLineTail.Finish(Self, mTailKey, mHit.Rect.Right);
  mHit.TopRow := AContext.EditView.TopRow;
  mHit.Line := AContext.LogicalLineNum - 1;
  mHit.Marks := AMarks;
  Remember(mHit);
  TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.OwnershipHints, AContext.FileName,
    mHit.Line, ALine), mHit.Rect, mHit.TopRow, ARect.Height);
end;

/// <summary>Marke merken; ersetzt die derselben Zeile und vergisst die einer anderen obersten Zeile.</summary>
procedure TAtlasIdeOwnershipHints.Remember(const AHit: THit);
var
  mIndex: Integer;
begin
  if (FHits <> nil) and (FHits[0].TopRow <> AHit.TopRow) then
  begin
    FHits := nil;
    HideTip;
  end;
  for mIndex := 0 to High(FHits) do
  begin
    if FHits[mIndex].Line = AHit.Line then
    begin
      FHits[mIndex] := AHit;
      Exit;
    end;
  end;
  SetLength(FHits, Length(FHits) + 1);
  FHits[High(FHits)] := AHit;
end;

function TAtlasIdeOwnershipHints.HitAt(AX, AY: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FHits) do
  begin
    if PtInRect(FHits[mIndex].Rect, Point(AX, AY)) and StillShown(FHits[mIndex]) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Steht die Marke noch dort: gleiche Datei vorn, nicht gescrollt.</summary>
function TAtlasIdeOwnershipHints.StillShown(const AHit: THit): Boolean;
var
  mView: IOTAEditView;
begin
  mView := TopView;
  Result := (mView <> nil) and (mView.Buffer <> nil) and SameText(mView.Buffer.FileName, FFileName) and
    (mView.TopRow = AHit.TopRow);
end;

procedure TAtlasIdeOwnershipHints.QueueJump(ALine: Integer);
var
  mState: IInterface;
  mFileName: string;
  mLine: Integer;
begin
  mState := FStateRef;
  mFileName := FFileName;
  mLine := ALine;
  // Erst nach dem Mausereignis: Der Editor setzt sonst den Cursor danach.
  TAtlasMainThread.ForceQueue(TAtlasFeature.Problems,
    procedure
    begin
      if TState(mState as TObject).Alive then
      begin
        TAtlasIdeNavigation.GoToLocation(mFileName, mLine, 0);
      end;
    end);
end;

procedure TAtlasIdeOwnershipHints.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  mHit, mLine: Integer;
begin
  try
    if (Button <> mbLeft) or (Shift * [ssShift, ssAlt, ssCtrl] <> []) or (FHits = nil) or not Wanted then
    begin
      Exit;
    end;
    mHit := HitAt(X, Y);
    if mHit < 0 then
    begin
      Exit;
    end;
    HideTip;
    mLine := TAtlasOwnershipMarks.JumpLine(FHits[mHit].Marks);
    if mLine >= 0 then
    begin
      QueueJump(mLine);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
  end;
end;

procedure TAtlasIdeOwnershipHints.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  mHit: Integer;
begin
  try
    mHit := -1;
    if (Editor <> nil) and (FHits <> nil) then
    begin
      mHit := HitAt(X, Y);
    end;
    if mHit < 0 then
    begin
      // Über dem Tooltip selbst bleibt er offen (HoverTick).
      if not FTip.IsShown or not PtInRect(FTip.BoundsRect, Mouse.CursorPos) then
      begin
        HideTip;
      end;
      Exit;
    end;
    if mHit = FHover then
    begin
      Exit;
    end;
    HideTip;
    FHover := mHit;
    FHoverSince := TThread.GetTickCount64;
    FHoverScreen := TRect.Create(Editor.ClientToScreen(FHits[mHit].Rect.TopLeft),
      Editor.ClientToScreen(FHits[mHit].Rect.BottomRight));
    FHoverTimer.Enabled := True;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
  end;
end;

procedure TAtlasIdeOwnershipHints.HoverTick(Sender: TObject);
var
  mCursor: TPoint;
begin
  try
    if (FHover < 0) or (FHover > High(FHits)) then
    begin
      HideTip;
      Exit;
    end;
    mCursor := Mouse.CursorPos;
    // Maus hat die Marke verlassen, ohne dass der Editor es gemeldet hat (anderes Fenster).
    if not PtInRect(FHoverScreen, mCursor) and not (FTip.IsShown and PtInRect(FTip.BoundsRect, mCursor)) then
    begin
      HideTip;
    end
    else if not FTip.IsShown and
      (TThread.GetTickCount64 - FHoverSince >= TAtlasCloseRules.cTooltipShowDelayMs) then
    begin
      FTip.ShowNote(TAtlasOwnershipMarks.TipTitle(FHits[FHover].Marks, FTexts),
        TAtlasOwnershipMarks.TipText(FHits[FHover].Marks, FTexts), Point(FHoverScreen.Left, FHoverScreen.Bottom + 2));
    end;
  except
    on E: Exception do
    begin
      HideTip;
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
    end;
  end;
end;

procedure TAtlasIdeOwnershipHints.HideTip;
begin
  FHover := -1;
  if FHoverTimer <> nil then
  begin
    FHoverTimer.Enabled := False;
  end;
  if (FTip <> nil) and FTip.IsShown then
  begin
    FTip.HidePopup;
  end;
end;

end.
