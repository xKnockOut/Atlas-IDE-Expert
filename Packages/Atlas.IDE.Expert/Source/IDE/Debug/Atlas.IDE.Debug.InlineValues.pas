unit Atlas.IDE.Debug.InlineValues;

// Werte im Editor beim Debuggen (#508) in der IDE:
//   - Auslöser: Halt der Debug-Sitzung (TAtlasIdeDebugSession). Atlas liest
//     den obersten Rahmen des Aufrufstapels (Datei und Zeile des
//     Ausführungspunkts; LLDB liefert ihn verzögert, dann wieder in 50 ms).
//     Nur diese Datei bekommt Werte.
//   - Bezeichner: textDocument/inlineValue des Servers (Syntaxbaum, #262) im
//     Hintergrund-Thread. Den Text der Datei gleicht Atlas vorher im
//     Hauptthread ab. Startet keinen Server.
//   - Werte: IOTAThread.Evaluate über TAtlasIdeDebugValues ohne
//     Nebenwirkungen (eseNone), im Hauptthread in Zeitscheiben von höchstens
//     SliceMs; dazwischen bedient die IDE Tasten und Zeichnen, ein
//     Einzelschritt wird so nicht spürbar länger. Ausgewertet werden nur
//     schlichte Bezeichner (TAtlasInlineValues.IsPlainIdentifier). Antwortet
//     der Debugger verzögert (Win64/LLDB), wartet Atlas höchstens
//     DeferredTimeoutMs auf den Wert und lässt ihn sonst weg.
//   - Zeichnen: nach dem Zeichnen jeder Zeile (plsEndPaint) gedimmt hinter
//     dem Zeilenende („Count = 3, Name = 'Meier'“), seit dem letzten Halt
//     geänderte Werte in der Warnfarbe; nur, wenn die Zeile im Editor dem
//     abgeglichenen Text entspricht. Platz hinter dem Zeilenende über
//     TAtlasLineTail. Reines GDI zwischen SaveDC und RestoreDC.
//   - Fortsetzen, neuer Halt und Ende der Sitzung verwerfen die Werte und
//     laufende Anfragen.
//   - Kein Zugriff (#840): Mit debug.explainUnavailable steht ein Name, dessen
//     Auswertung mit einem bekannten Text scheitert, als „Name = ‹kein
//     Zugriff›“ da (TAtlasIdeDebugUnavailable); die Ursache zeigt der Hover.
// Ohne debug.inlineValues ist nichts angemeldet. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.InlineValues,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Hover.DebugValue;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasInlineValuesSessionFunc = reference to function: TLspSession;

  TAtlasIdeDebugInlineValues = class
  public const
    /// <summary>Höchstens so lange wertet Atlas am Stück aus.</summary>
    SliceMs = 30;
    TickMs = 10;
    /// <summary>So lange wartet Atlas auf einen verzögerten Wert (LLDB).</summary>
    DeferredTimeoutMs = 500;
    RequestTimeoutMs = 3000;
    /// <summary>Versuche, bis der Aufrufstapel bzw. der Editor der Datei da ist (je TickMs * 5).</summary>
    LocationRetries = 20;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
    {$SCOPEDENUMS ON}
    TPhase = (Idle, Location, Request, Evaluate);
    {$SCOPEDENUMS OFF}
  private class var
    FInstance: TAtlasIdeDebugInlineValues;
  private
    FSession: TAtlasInlineValuesSessionFunc;
    FValues: TAtlasInlineValues;
    FEvaluator: TAtlasIdeDebugValues;
    FListener: IAtlasIdeDebugListener;
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FWorkers: TList<TThread>;
    FPhase: TPhase;
    FStop: Integer;
    FRequest: Integer;
    FRetries: Integer;
    FWaitAt: Cardinal;
    FDeferredName: string;
    FInternal: Boolean;
    FFileName: string;
    FContext: string;
    FLine: Integer;
    FText: string;
    FLines: TArray<string>;
    FHintFont: TFont;
    FFontKey: string;
    FBack: COLORREF;
    FBackKnown: Boolean;
    FTextColor: COLORREF;
    FChangedColor: COLORREF;
    constructor Create(const ASession: TAtlasInlineValuesSessionFunc);
    /// <summary>Werte und laufende Arbeit verwerfen; AForget auch die gemerkten Werte (Ende der Sitzung).</summary>
    procedure Drop(AForget: Boolean);
    procedure Stopped;
    procedure Tick(Sender: TObject);
    /// <summary>Datei und Zeile des Ausführungspunkts; False: später noch einmal bzw. aufgeben (FPhase).</summary>
    function ReadLocation: Boolean;
    procedure Ask;
    procedure Accept(ARequest: Integer; const ARefs: TAtlasInlineValueRefs);
    procedure EvaluateSlice;
    procedure DeferredDone(const AValue: TAtlasDebugValue);
    procedure EndInternal;
    function StillStopped: Boolean;
    procedure ReapWorkers(AWait: Boolean);
    procedure EnsureColors(ABack: COLORREF);
    procedure EnsureHintFont(const AEditorFont: TFont);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    class procedure Invalidate; static;
  public
    destructor Destroy; override;
    class procedure Start(const ASession: TAtlasInlineValuesSessionFunc); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.inlineValues an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.LineTail,
  Atlas.Core.Debug.CallStack,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.Unavailable,
  Atlas.IDE.Foundation.EditorRefresh;

{ TAtlasIdeDebugInlineValues.TListener }

procedure TAtlasIdeDebugInlineValues.TListener.DebugStarted;
begin
  if FInstance <> nil then
    FInstance.Drop(True);
end;

procedure TAtlasIdeDebugInlineValues.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  if FInstance <> nil then
    FInstance.Stopped;
end;

procedure TAtlasIdeDebugInlineValues.TListener.DebugResumed;
begin
  if FInstance <> nil then
    FInstance.Drop(False);
end;

procedure TAtlasIdeDebugInlineValues.TListener.DebugEnded;
begin
  if FInstance <> nil then
    FInstance.Drop(True);
end;

{ TAtlasIdeDebugInlineValues.TEvents }

function TAtlasIdeDebugInlineValues.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeDebugInlineValues.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeDebugInlineValues }

constructor TAtlasIdeDebugInlineValues.Create(const ASession: TAtlasInlineValuesSessionFunc);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FIndex := -1;
  FValues := TAtlasInlineValues.Create;
  FEvaluator := TAtlasIdeDebugValues.Create;
  FWorkers := TList<TThread>.Create;
  FHintFont := TFont.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TAtlasIdeDebugInlineValues.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  if FEvents <> nil then
    FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  FreeAndNil(FTimer);
  FEvaluator.Cancel;
  EndInternal;
  // Laufende Anfragen halten die Sitzung als rohen Zeiger: abwarten.
  ReapWorkers(True);
  FreeAndNil(FWorkers);
  FreeAndNil(FEvaluator);
  FreeAndNil(FValues);
  FreeAndNil(FHintFont);
  FText := '';
  FLines := nil;
  inherited Destroy;
end;

class procedure TAtlasIdeDebugInlineValues.Start(const ASession: TAtlasInlineValuesSessionFunc);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugInlineValues.Create(ASession);
    FInstance.FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FInstance.FListener);
  end;
  TAtlasIdeDebugSession.Start;
  // Eingeschaltet, während der Prozess steht: gleich für diesen Halt.
  if TAtlasIdeDebugSession.StoppedThread <> nil then
    FInstance.Stopped;
end;

class procedure TAtlasIdeDebugInlineValues.Release;
var
  Instance: TAtlasIdeDebugInlineValues;
begin
  if FInstance = nil then
    Exit;
  Instance := FInstance;
  FInstance := nil;
  if Instance.FListener <> nil then
    TAtlasIdeDebugSession.RemoveListener(Instance.FListener);
  Instance.FListener := nil;
  Instance.Free;
  Invalidate;
end;

class function TAtlasIdeDebugInlineValues.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugInlineValues.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.DebugInlineValues;
end;

class procedure TAtlasIdeDebugInlineValues.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
end;

procedure TAtlasIdeDebugInlineValues.EndInternal;
begin
  if FInternal then
  begin
    FInternal := False;
    TAtlasIdeDebugSession.EndInternal;
  end;
end;

procedure TAtlasIdeDebugInlineValues.Drop(AForget: Boolean);
var
  Had: Boolean;
begin
  Had := FValues.Active;
  if FTimer <> nil then
    FTimer.Enabled := False;
  FEvaluator.Cancel;
  EndInternal;
  FDeferredName := '';
  // Antworten noch laufender Anfragen verwerfen.
  Inc(FRequest);
  FPhase := TPhase.Idle;
  if AForget then
    FValues.Reset
  else
    FValues.Clear;
  FText := '';
  FLines := nil;
  ReapWorkers(False);
  if Had then
    Invalidate;
end;

function TAtlasIdeDebugInlineValues.StillStopped: Boolean;
begin
  Result := (TAtlasIdeDebugSession.StopCount = FStop) and (TAtlasIdeDebugSession.StoppedThread <> nil);
end;

procedure TAtlasIdeDebugInlineValues.Stopped;
begin
  Drop(False);
  if not Enabled then
    Exit;
  FValues.SetUnavailable(TAtlasIdeDebugUnavailable.InlineCaption, TAtlasIdeDebugUnavailable.Patterns);
  FStop := TAtlasIdeDebugSession.StopCount;
  FRetries := 0;
  FPhase := TPhase.Location;
  if ReadLocation then
    Ask;
end;

function TAtlasIdeDebugInlineValues.ReadLocation: Boolean;
var
  Frames: TAtlasDebugFrames;
  Buffer: IOTAEditBuffer;
begin
  Result := False;
  case TAtlasIdeDebugSession.ReadStack(TAtlasIdeDebugSession.StoppedThread, 1, Frames) of
    TAtlasDebugStackRead.Wait:
      begin
        // LLDB: Stapel kommt später.
        Inc(FRetries);
        FTimer.Interval := TickMs * 5;
        FTimer.Enabled := FRetries <= LocationRetries;
        if not FTimer.Enabled then
          FPhase := TPhase.Idle;
        Exit;
      end;
    TAtlasDebugStackRead.None:
      begin
        FPhase := TPhase.Idle;
        Exit;
      end;
  end;
  if (Length(Frames) = 0) or not Frames[0].HasSource then
  begin
    // Kein Quelltext am Ausführungspunkt (RTL ohne Quellen, Assembler).
    FPhase := TPhase.Idle;
    Exit;
  end;
  TAtlasIdeDebugSources.MarkFrames(Frames);
  Buffer := TAtlasIdeFiles.BufferOf(Frames[0].FileName);
  if Buffer = nil then
  begin
    // Die IDE öffnet die Datei des Halts gleich danach.
    Inc(FRetries);
    FTimer.Interval := TickMs * 5;
    FTimer.Enabled := FRetries <= LocationRetries;
    if not FTimer.Enabled then
      FPhase := TPhase.Idle;
    Exit;
  end;
  FFileName := Buffer.FileName;
  FContext := FFileName + '|' + Frames[0].Routine;
  FLine := Frames[0].Line - 1;
  FText := TAtlasEditorBuffer.Text(Buffer);
  FLines := FText.Split([#13#10, #10]);
  FPhase := TPhase.Request;
  Result := True;
end;

procedure TAtlasIdeDebugInlineValues.Ask;
var
  Session: TLspSession;
  FileName: string;
  Line, Request: Integer;
  Worker: TThread;
begin
  FTimer.Enabled := False;
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  if Session = nil then
  begin
    FPhase := TPhase.Idle;
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  FileName := FFileName;
  Line := FLine;
  Session.Sync(FileName, FText);
  ReapWorkers(False);
  Inc(FRequest);
  Request := FRequest;
  Worker := TThread.CreateAnonymousThread(
    procedure
    var
      Refs: TAtlasInlineValueRefs;
    begin
      Refs := nil;
      try
        // Vom Dateianfang bis zum Halt; der Server beschränkt auf die Routine.
        Refs := Session.InlineValues(FileName, 0, Line, Line, RequestTimeoutMs);
      except
        // Server langsam oder weg: keine Werte.
        Refs := nil;
      end;
      // Atlas gehört der Eintrag: beim Entladen verworfen (Code-Review A-02).
      TAtlasMainThread.Queue(TAtlasFeature.Debugger,
        procedure
        begin
          if FInstance <> nil then
            TAtlasGuard.Run(TAtlasFeature.Debugger,
              procedure
              begin
                if FInstance <> nil then
                  FInstance.Accept(Request, Refs);
              end);
        end);
    end);
  Worker.FreeOnTerminate := False;
  FWorkers.Add(Worker);
  Worker.Start;
end;

procedure TAtlasIdeDebugInlineValues.Accept(ARequest: Integer; const ARefs: TAtlasInlineValueRefs);
begin
  // Nur die jüngste Antwort, und nur, solange derselbe Halt besteht.
  if (ARequest <> FRequest) or (FPhase <> TPhase.Request) then
    Exit;
  if not StillStopped or not Enabled or (Length(ARefs) = 0) then
  begin
    FPhase := TPhase.Idle;
    Exit;
  end;
  FValues.Start(FFileName, FContext, FLine, ARefs, TAtlasIdeSettings.Current.DebugInlineValuesPerLine);
  FPhase := TPhase.Evaluate;
  FTimer.Interval := TickMs;
  FTimer.Enabled := True;
  EvaluateSlice;
end;

procedure TAtlasIdeDebugInlineValues.Tick(Sender: TObject);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  try
    case FPhase of
      TPhase.Location:
        begin
          FTimer.Enabled := False;
          if not StillStopped then
            FPhase := TPhase.Idle
          else if ReadLocation then
            Ask;
        end;
      TPhase.Evaluate:
        EvaluateSlice;
    else
      FTimer.Enabled := False;
    end;
  except
    on E: Exception do
    begin
      FTimer.Enabled := False;
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
    end;
  end;
end;

procedure TAtlasIdeDebugInlineValues.EvaluateSlice;
var
  StartedAt: Cardinal;
  Name: string;
  Value: TAtlasDebugValue;
  Changed: Boolean;
begin
  if not StillStopped then
  begin
    Drop(False);
    Exit;
  end;
  // Verzögerter Wert (LLDB): höchstens DeferredTimeoutMs warten, dann ohne ihn weiter.
  if FDeferredName <> '' then
  begin
    if GetTickCount - FWaitAt < DeferredTimeoutMs then
      Exit;
    FEvaluator.Cancel;
    EndInternal;
    FValues.Put(FDeferredName, '', False);
    FDeferredName := '';
  end;
  Changed := False;
  StartedAt := GetTickCount;
  while FValues.NextPending(Name) do
  begin
    if GetTickCount - StartedAt >= SliceMs then
      Break;
    // Eigene Auswertung: Zustandswechsel dabei sind kein Fortsetzen (TAtlasIdeDebugSession).
    Value := Default(TAtlasDebugValue);
    TAtlasIdeDebugSession.BeginInternal;
    FInternal := True;
    try
      Value := FEvaluator.Evaluate(Name, FFileName, FLine + 1, DeferredDone);
    finally
      if Value.State <> TAtlasDebugValueState.Pending then
        EndInternal;
    end;
    case Value.State of
      TAtlasDebugValueState.Pending:
        begin
          FDeferredName := Name;
          FWaitAt := GetTickCount;
          Break;
        end;
      TAtlasDebugValueState.Value:
        begin
          FValues.Put(Name, Value.Text, True);
          Changed := True;
        end;
      TAtlasDebugValueState.Failed:
        FValues.Put(Name, '', False);
    else
      // Kein angehaltener Prozess mehr.
      Drop(False);
      Exit;
    end;
  end;
  if (FDeferredName = '') and not FValues.NextPending(Name) then
  begin
    FTimer.Enabled := False;
    FPhase := TPhase.Idle;
  end;
  if Changed then
    Invalidate;
end;

procedure TAtlasIdeDebugInlineValues.DeferredDone(const AValue: TAtlasDebugValue);
begin
  if FDeferredName = '' then
    Exit;
  EndInternal;
  FValues.Put(FDeferredName, AValue.Text, AValue.State = TAtlasDebugValueState.Value);
  FDeferredName := '';
  Invalidate;
end;

procedure TAtlasIdeDebugInlineValues.ReapWorkers(AWait: Boolean);
var
  Index: Integer;
begin
  if FWorkers = nil then
    Exit;
  for Index := FWorkers.Count - 1 downto 0 do
    if AWait or FWorkers[Index].Finished then
    begin
      FWorkers[Index].WaitFor;
      FWorkers[Index].Free;
      FWorkers.Delete(Index);
    end;
end;

procedure TAtlasIdeDebugInlineValues.EnsureColors(ABack: COLORREF);
var
  Colors: TAtlasHintColors;
begin
  if FBackKnown and (FBack = ABack) then
    Exit;
  Colors := TAtlasColors.InlayHint(TAtlasColor(ABack));
  FTextColor := COLORREF(ColorToRGB(TColor(Colors.Text)));
  FChangedColor := COLORREF(ColorToRGB(TColor(TAtlasColors.ForBackground(TAtlasColor(ABack)).Warn)));
  FBack := ABack;
  FBackKnown := True;
end;

procedure TAtlasIdeDebugInlineValues.EnsureHintFont(const AEditorFont: TFont);
var
  Key: string;
begin
  Key := AEditorFont.Name + '|' + IntToStr(AEditorFont.Size) + '|' + IntToStr(AEditorFont.PixelsPerInch);
  if Key = FFontKey then
    Exit;
  FHintFont.Assign(AEditorFont);
  FHintFont.Style := [fsItalic];
  FFontKey := Key;
end;

/// <summary>Editorspalte (1-basiert) zum Zeichenindex (0-basiert) in ALine; Tabs aufgelöst.</summary>
function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(Copy(ALine, 1, Max(0, ACharacter)), ATabWidth)) + 1;
end;

procedure TAtlasIdeDebugInlineValues.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Items: TAtlasInlineValueItems;
  Item: TAtlasInlineValueItem;
  LineState: INTACodeEditorLineState;
  Line, TabWidth, X, Top: Integer;
  Stored, Part: string;
  Canvas: TCanvas;
  Cell: TRect;
  Sample: COLORREF;
  DC: HDC;
  Saved, Index: Integer;
  Size: TSize;
  TailKey: string;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) then
    Exit;
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not FValues.Active then
    Exit;
  try
    Line := Context.LogicalLineNum - 1;
    Items := FValues.Line(Context.FileName, Line);
    if (Length(Items) = 0) or (Line < 0) or (Line > High(FLines)) then
      Exit;
    LineState := Context.LineState;
    if (LineState = nil) or (Context.EditView = nil) or (Context.EditView.Buffer = nil) then
      Exit;
    Stored := FLines[Line];
    TabWidth := TAtlasEditorBuffer.TabWidth(Context.EditView.Buffer);
    // Nur, wenn die Zeile im Editor der abgeglichenen entspricht.
    if TrimRight(TAtlasPairs.DisplayLine(LineState.Text, TabWidth)) <>
      TrimRight(TAtlasPairs.DisplayLine(Stored, TabWidth)) then
      Exit;
    Canvas := Context.Canvas;
    DC := Canvas.Handle;
    // Zwei Zeichen Abstand hinter dem letzten Zeichen der Zeile.
    Cell := Context.EditorState.GetCharacterPosPx(ColumnOf(Stored, Length(TrimRight(Stored)), TabWidth) + 2,
      Context.EditorLineNum);
    TailKey := TAtlasLineTail.KeyOf(Context.FileName, Context.LogicalLineNum, Context.EditorLineNum, Rect.Top);
    X := TAtlasLineTail.Start(Self, TailKey, Cell.Left);
    Sample := GetPixel(DC, X, Rect.Top + 1);
    if Sample = CLR_INVALID then
      Sample := COLORREF(ColorToRGB(Canvas.Brush.Color));
    EnsureColors(Sample);
    EnsureHintFont(Canvas.Font);
    Saved := SaveDC(DC);
    try
      SelectObject(DC, FHintFont.Handle);
      SetBkMode(DC, TRANSPARENT);
      GetTextExtentPoint32W(DC, 'Xg', 2, Size);
      Top := Rect.Top + Max(0, (Rect.Bottom - Rect.Top - Size.cy) div 2);
      for Index := 0 to High(Items) do
      begin
        Item := Items[Index];
        Part := Item.Caption;
        if Index < High(Items) then
          Part := Part + ', ';
        if Item.Changed then
          SetTextColor(DC, FChangedColor)
        else
          SetTextColor(DC, FTextColor);
        TextOutW(DC, X, Top, PChar(Part), Length(Part));
        GetTextExtentPoint32W(DC, PChar(Part), Length(Part), Size);
        Inc(X, Size.cx);
      end;
      TAtlasLineTail.Finish(Self, TailKey, X);
    finally
      RestoreDC(DC, Saved);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

end.
