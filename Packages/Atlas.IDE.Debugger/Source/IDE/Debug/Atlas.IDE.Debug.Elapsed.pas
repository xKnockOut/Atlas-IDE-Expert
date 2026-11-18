unit Atlas.IDE.Debug.Elapsed;

// Laufzeit zwischen Haltepunkten (#579) in der IDE:
//   - Messung: Die Debug-Sitzung zählt, wie lange der Prozess vor dem gemeldeten Halt lief
//     (TAtlasIdeDebugSession.RunTimeBeforeStop); angehaltene Zeit und eigene Auswertungen zählen nicht.
//   - Ort: oberster Rahmen des angehaltenen Threads (LLDB liefert ihn verzögert, dann erneut über den Takt
//     der Basis); ohne Quelltext keine Anzeige, die Messung steht trotzdem im Verlauf.
//   - Anzeige: „+124 ms“ am Ende der Zeile des Ausführungspunkts, hinter den übrigen Anzeigen am Zeilenende
//     (TAtlasDebugLineEnd), gedimmt wie die Werte im Editor. Am Haltepunkt immer, bei Schritten und Pausen ab
//     1 ms (TAtlasElapsed).
//   - Klick auf den Text: Menü mit dem Hinweis, dass die Zeit Debugger-Aufwand enthält, und den letzten 20
//     Messungen mit Start- und Zielzeile.
//   - Fortsetzen und Ende der Sitzung nehmen die Anzeige weg; eine neue Sitzung leert den Verlauf.
// Ohne debug.showElapsed ist nichts angemeldet. Nur im Hauptthread verwenden.

interface

uses
  System.Types,
  System.Classes,
  Vcl.Controls,
  Vcl.Menus,
  ToolsAPI.Editor,
  Atlas.Core.Debug.Elapsed,
  Atlas.IDE.Debug.StopView,
  Atlas.UI.Debug.InlineValuePainter;

type
  TAtlasIdeDebugElapsed = class(TAtlasIdeDebugStopView)
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private class var
    FInstance: TAtlasIdeDebugElapsed;
  private
    FModel: TAtlasElapsed;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FStyle: TAtlasInlineValuePainter;
    FMenu: TPopupMenu;
    /// <summary>Laufzeit des jüngsten Halts, bis sein Ort gelesen ist.</summary>
    FMicros: Int64;
    FFileName: string;
    FLine: Integer;
    FLineText: string;
    /// <summary>Gezeichneter Text, für den Klick; leer ohne.</summary>
    FHit: TRect;
    constructor Create;
    procedure Drop;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ShowHistory(const APoint: TPoint);
  protected
    procedure SessionStarted; override;
    procedure SessionStopped; override;
    procedure SessionResumed; override;
    procedure SessionEnded; override;
    function ReadLocation: Boolean; override;
    procedure Ask; override;
  public
    destructor Destroy; override;
    class procedure Start; static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.showElapsed an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.StopProgress,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.IDE.Debug.LineEnd,
  Atlas.UI.Debug.Elapsed.Strings;

const
  cTickMs = 10;
  cLocationRetries = 20;
  /// <summary>Wartezeit zwischen zwei Versuchen, den Ausführungspunkt zu lesen: so viele Takte.</summary>
  cLocationTicks = 5;

{ TAtlasIdeDebugElapsed.TEvents }

function TAtlasIdeDebugElapsed.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents];
end;

function TAtlasIdeDebugElapsed.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeDebugElapsed }

constructor TAtlasIdeDebugElapsed.Create;
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FLine := -1;
  FModel := TAtlasElapsed.Create;
  FStyle := TAtlasInlineValuePainter.Create;
  CreateTimer(cTickMs);
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasIdeDebugElapsed.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintLine := nil;
    FEvents.OnEditorMouseDown := nil;
  end;
  FEventsRef := nil;
  FreeAndNil(FMenu);
  FreeAndNil(FModel);
  FreeAndNil(FStyle);
  FFileName := '';
  FLineText := '';
  inherited Destroy;
end;

procedure TAtlasIdeDebugElapsed.Drop;
var
  mHad: Boolean;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FProgress.Discard;
  FHit := Default(TRect);
  mHad := FModel.LineText(FFileName, FLine) <> '';
  FModel.Hide;
  if mHad then
  begin
    TAtlasDebugLineEnd.Invalidate;
  end;
end;

procedure TAtlasIdeDebugElapsed.SessionStarted;
begin
  Drop;
  FModel.Clear;
end;

procedure TAtlasIdeDebugElapsed.SessionStopped;
begin
  Drop;
  if not Enabled then
  begin
    Exit;
  end;
  // Gleich lesen: Die Sitzung zählt bis zum nächsten gemeldeten Halt weiter.
  FMicros := TAtlasIdeDebugSession.RunTimeBeforeStop;
  FProgress.Restart(TAtlasIdeDebugSession.StopCount);
  if ReadLocation then
  begin
    Ask;
  end;
end;

procedure TAtlasIdeDebugElapsed.SessionResumed;
begin
  Drop;
end;

procedure TAtlasIdeDebugElapsed.SessionEnded;
begin
  Drop;
end;

function TAtlasIdeDebugElapsed.ReadLocation: Boolean;
var
  mFrames: TAtlasDebugFrames;
  mBuffer: IOTAEditBuffer;
  mRead: TAtlasDebugStackRead;
  mWithoutSource: Boolean;
  mLines: TArray<string>;
begin
  mBuffer := nil;
  mRead := TAtlasIdeDebugSession.ReadStack(TAtlasIdeDebugSession.StoppedThread, 1, mFrames);
  mWithoutSource := (mRead = TAtlasDebugStackRead.Ready) and ((Length(mFrames) = 0) or not mFrames[0].HasSource);
  if (mRead = TAtlasDebugStackRead.Ready) and not mWithoutSource then
  begin
    TAtlasIdeDebugSources.MarkFrames(mFrames);
    mBuffer := TAtlasIdeFiles.BufferOf(mFrames[0].FileName);
  end;
  case FProgress.Locate(mRead = TAtlasDebugStackRead.None, mWithoutSource, mBuffer <> nil, cLocationRetries) of
    TAtlasStopLocation.Retry:
      begin
        FTimer.Interval := cTickMs * cLocationTicks;
        FTimer.Enabled := True;
        Exit(False);
      end;
    TAtlasStopLocation.GiveUp:
      begin
        // Ohne Quelltext: nur in den Verlauf.
        FModel.Add(FMicros, '', -1, False);
        Exit(False);
      end;
  end;
  FFileName := mBuffer.FileName;
  FLine := mFrames[0].Line - 1;
  mLines := TAtlasEditorBuffer.Text(mBuffer).Split([#13#10, #10]);
  FLineText := '';
  if (FLine >= 0) and (FLine <= High(mLines)) then
  begin
    FLineText := mLines[FLine];
  end;
  Result := True;
end;

procedure TAtlasIdeDebugElapsed.Ask;
begin
  FTimer.Enabled := False;
  FProgress.Phase := TAtlasStopPhase.Idle;
  if FModel.Add(FMicros, FFileName, FLine, TAtlasIdeBreakpoints.Exists(FFileName, FLine)) then
  begin
    TAtlasDebugLineEnd.Invalidate;
  end;
end;

procedure TAtlasIdeDebugElapsed.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mX, mRight: Integer;
  mTailKey, mText: string;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) or BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
  begin
    Exit;
  end;
  try
    mText := FModel.LineText(Context.FileName, Context.LogicalLineNum - 1);
    if (mText = '') or not TAtlasDebugLineEnd.Matches(Context, FLineText) then
    begin
      Exit;
    end;
    // Hinter dem letzten Zeichen der Zeile bzw. hinter den übrigen Anzeigen am Zeilenende.
    mX := TAtlasDebugLineEnd.Start(Self, Context, Rect, FLineText, FStyle, mTailKey);
    mRight := FStyle.DrawText(Context.Canvas.Handle, Rect, mX, mText);
    TAtlasDebugLineEnd.Finish(Self, mTailKey, mRight);
    FHit := TRect.Create(mX, Rect.Top, mRight, Rect.Bottom);
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

/// <summary>Verlauf an APoint zeigen, erst nach dem Mausereignis: Der Editor setzt sonst den Cursor danach.
/// </summary>
procedure QueueHistory(const APoint: TPoint);
begin
  TAtlasMainThread.ForceQueue(TAtlasFeature.Debugger,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger,
        procedure
        begin
          if TAtlasIdeDebugElapsed.FInstance <> nil then
          begin
            TAtlasIdeDebugElapsed.FInstance.ShowHistory(APoint);
          end;
        end);
    end);
end;

procedure TAtlasIdeDebugElapsed.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or FHit.IsEmpty or
    (FModel.LineText(FFileName, FLine) = '') then
  begin
    Exit;
  end;
  if FHit.Contains(Point(X, Y)) then
  begin
    QueueHistory(Editor.ClientToScreen(Point(X, Y)));
  end;
end;

/// <summary>Menüeintrag ohne Wirkung mit ACaption an AMenu anhängen.</summary>
procedure AddInfo(AMenu: TPopupMenu; const ACaption: string);
var
  mItem: TMenuItem;
begin
  mItem := TMenuItem.Create(AMenu);
  mItem.Caption := ACaption;
  mItem.Enabled := False;
  AMenu.Items.Add(mItem);
end;

procedure TAtlasIdeDebugElapsed.ShowHistory(const APoint: TPoint);
var
  mEntry: TAtlasElapsedEntry;
begin
  if FMenu = nil then
  begin
    FMenu := TPopupMenu.Create(nil);
  end;
  FMenu.Items.Clear;
  AddInfo(FMenu, TAtlasElapsedStrings.Text(TAtlasElapsedTextId.ElapsedHint));
  FMenu.Items.NewBottomLine;
  AddInfo(FMenu, TAtlasElapsedStrings.Text(TAtlasElapsedTextId.ElapsedHistory));
  for mEntry in FModel.Entries do
  begin
    AddInfo(FMenu, TAtlasElapsed.HistoryLine(mEntry));
  end;
  FMenu.Popup(APoint.X, APoint.Y);
end;

class procedure TAtlasIdeDebugElapsed.Start;
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugElapsed.Create;
    FInstance.Listen;
  end;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugElapsed.Release;
var
  mInstance: TAtlasIdeDebugElapsed;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  mInstance := FInstance;
  FInstance := nil;
  mInstance.Free;
  TAtlasDebugLineEnd.Invalidate;
end;

class function TAtlasIdeDebugElapsed.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugElapsed.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.DebugShowElapsed;
end;

end.
