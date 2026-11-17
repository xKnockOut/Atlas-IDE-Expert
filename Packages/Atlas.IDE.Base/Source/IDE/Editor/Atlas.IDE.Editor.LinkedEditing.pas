unit Atlas.IDE.Editor.LinkedEditing;

// Bezeichner live mitziehen (#658, experimentell) im Editor. Was eine Taste
// aus dem Namen macht und wie er in alle Vorkommen kommt, rechnet
// Atlas.Core.Editor.LinkedEditing; den Ablauf der Sitzung im Puffer führt
// Atlas.Core.Editor.LinkedSession über Atlas.IDE.Editor.EditSurface. Hier
// bleiben Anfrage, Tasten, Takt, Statusfeld und Zeichnen.
// - Ruht der Cursor auf einem Bezeichner, fragt Atlas im Hintergrund den
//   Server nach den Vorkommen (linkedEditingRange mit "atlasLocals"). Nur
//   lokale Variablen, Parameter, lokale Konstanten, Inline- und
//   Schleifenvariablen bekommen eine Antwort.
// - Tippt man dann ein Zeichen eines Bezeichners, Rücktaste oder Entf im
//   Namen und gilt die Antwort noch für den Text, beginnt die Sitzung:
//   Application.OnMessage fängt die Taste ab, Atlas schreibt den neuen Namen
//   in alle Vorkommen (ein Schreiber, nur die Namen, damit Haltepunkte und
//   Lesezeichen bleiben). Folgt die nächste Taste, nimmt Atlas den eigenen
//   Schritt zurück und schreibt die ganze Umbenennung neu: Strg+Z nimmt die
//   Sitzung auf einmal zurück (wie Zeilen verschieben, #634).
// - Ändert die IDE den Namen selbst (Einfügen, Vorschlag übernommen), zieht
//   Atlas die übrigen Vorkommen nach; das ist ein eigener Rückgängig-Schritt.
// - Ende: Enter (ohne Zeilenumbruch), Esc, ein Zeichen, das kein Bezeichner
//   ist, Rücktaste am Anfang bzw. Entf am Ende des Namens, Cursor verlässt den
//   Namen, Datei- oder Formularwechsel, Einstellung aus.
// - Konflikt (reserviertes Wort, Name in der Routine schon sichtbar): Rahmen
//   und Marke rot, Hinweis an der Marke und im Statusfeld; Esc stellt den
//   alten Namen wieder her.
// - Zeichnen per PaintLine (plsEndPaint): das bearbeitete Vorkommen
//   durchgezogen, die übrigen gestrichelt, dahinter „4 Vorkommen“.
// - Nie bei offener Vervollständigung, im Platzhalter-Modus oder mit
//   mehreren Einfügemarken (#589).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.AppEvnts,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Editor.LinkedEditing,
  Atlas.Core.Editor.LinkedSession,
  Atlas.IDE.Editor.LinkedEditingQuery;

type
  /// <summary>Statusfeld setzen; AText '' entfernt es.</summary>
  TAtlasLinkedStatusProc = reference to procedure(const AText, AHint: string);

  TAtlasIdeLinkedEditing = class
  private const
    cTickMs = 100;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private class var
    FInstance: TAtlasIdeLinkedEditing;
  private
    FBusy: TFunc<Boolean>;
    FStatus: TAtlasLinkedStatusProc;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FMessages: TApplicationEvents;
    FTimer: TTimer;
    FQuery: TAtlasIdeLinkedEditingQuery;
    FSession: TAtlasLinkedSession;
    FHighSurrogate: Char;
    function IsBusy: Boolean;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure KeyDown(const AMsg: TMsg; var AHandled: Boolean);
    procedure CharTyped(const AMsg: TMsg; var AHandled: Boolean);
    /// <summary>Tiefe Hälfte ATyped eines Zeichens außerhalb der Grundebene zur wartenden hohen einfügen.</summary>
    procedure InsertSurrogates(ATyped: Char; var AHandled: Boolean);
    procedure TimerTick(Sender: TObject);
    /// <summary>Takt mit Sitzung: beenden, wenn sie nicht mehr gilt; ausstehende Änderung nachziehen.</summary>
    procedure CheckRun;
    /// <summary>Datei gewechselt, Formular angezeigt oder abgeschaltet?</summary>
    function Lost(const AView: IOTAEditView): Boolean;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    /// <summary>Sitzung mit der letzten Antwort beginnen; False, wenn sie nicht mehr gilt.</summary>
    function Start(const AView: IOTAEditView): Boolean;
    /// <summary>Taste im Namen ausführen; False gibt sie an die IDE (und beendet die Sitzung).</summary>
    function Edit(AKind: TAtlasLinkedKey; const AInsert: string): Boolean;
    /// <summary>Hinweis zum Konflikt; '' ohne.</summary>
    function ProblemText: string;
    /// <summary>Marke und Statusfeld: Konflikt oder Anzahl der Vorkommen.</summary>
    function Caption: string;
    procedure Refresh;
    /// <summary>Sitzung ist zu Ende: Statusfeld leeren, neu zeichnen.</summary>
    procedure Finished;
    procedure Finish;
  public
    constructor Create(const ABusy: TFunc<Boolean>; const ASession: TAtlasLinkedSessionFunc;
      const AStatus: TAtlasLinkedStatusProc);
    destructor Destroy; override;
    /// <summary>ABusy: Vervollständigung offen, Platzhalter-Modus oder mehrere Einfügemarken? ASession liefert
    /// die laufende Sitzung des Servers (nil ohne), AStatus setzt das Statusfeld.</summary>
    class procedure Install(const ABusy: TFunc<Boolean>; const ASession: TAtlasLinkedSessionFunc;
      const AStatus: TAtlasLinkedStatusProc); static;
    class procedure Uninstall; static;
    /// <summary>editor.linkedEditing an (experimentell, also nur mit experimental.enabled) und Atlas an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Läuft eine Sitzung?</summary>
    class function Active: Boolean; static;
    /// <summary>Sitzung beenden (Ansicht gewechselt).</summary>
    class procedure Dismiss; static;
    /// <summary>Aus EditorViewModified: fremde Änderung nachziehen (in der Warteschlange).</summary>
    class procedure EditorModified(const AView: IOTAEditView); static;
  end;

implementation

uses
  System.Math,
  Vcl.Forms,
  Vcl.Graphics,
  Atlas.Text.Lines,
  Atlas.Core.Editor.LinkedKeys,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Editor.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Editor.EditSurface,
  Atlas.IDE.Editor.PaintedLine;

function CurrentShift: TShiftState;
begin
  Result := [];
  if GetKeyState(VK_SHIFT) < 0 then
  begin
    Include(Result, ssShift);
  end;
  if GetKeyState(VK_CONTROL) < 0 then
  begin
    Include(Result, ssCtrl);
  end;
  if GetKeyState(VK_MENU) < 0 then
  begin
    Include(Result, ssAlt);
  end;
end;

procedure Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

/// <summary>Zeigt der aktuelle Modul ein Formular?</summary>
function FormShown: Boolean;
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mForm: IOTAFormEditor;
begin
  Result := False;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    mModule := mModules.CurrentModule;
    Result := (mModule <> nil) and Supports(mModule.CurrentEditor, IOTAFormEditor, mForm);
  end;
end;

/// <summary>Antwort an die laufende Instanz; nach dem Abbau verworfen.</summary>
function DeliverToInstance: TAtlasLinkedDeliverProc;
begin
  Result :=
    procedure(ARequest: Integer; const AFileName, AText: string; const ARanges: TAtlasLinkedRanges;
      const AConflicts: TAtlasLinkedConflicts)
    begin
      if TAtlasIdeLinkedEditing.FInstance <> nil then
      begin
        TAtlasIdeLinkedEditing.FInstance.FQuery.Accept(ARequest, AFileName, AText, ARanges, AConflicts);
      end;
    end;
end;

/// <summary>Rahmen um das Vorkommen ARange in der Zeile ARect; ein leerer Name bleibt als schmaler Rahmen
/// sichtbar.</summary>
function FrameOf(const AContext: INTACodeEditorPaintContext; const AText: string; const ARange: TAtlasLinkedRange;
  ATabWidth: Integer; const ARect: TRect): TRect;
var
  mFirst, mLast: TRect;
begin
  mFirst := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, ARange.Character, ATabWidth),
    AContext.EditorLineNum);
  mLast := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, ARange.EndCharacter, ATabWidth),
    AContext.EditorLineNum);
  Result := TRect.Create(mFirst.Left - 1, ARect.Top, Max(mLast.Left + 1, mFirst.Left + 2), ARect.Bottom);
end;

/// <summary>Bearbeitetes Vorkommen durchgezogen (ABrush), die übrigen gestrichelt (APen).</summary>
procedure PaintFrame(ADC: HDC; const AFrame: TRect; APrimary: Boolean; ABrush: HBRUSH; APen: HPEN);
var
  mOldPen, mOldBrush: HGDIOBJ;
begin
  if APrimary then
  begin
    FrameRect(ADC, AFrame, ABrush);
    Exit;
  end;
  mOldPen := SelectObject(ADC, APen);
  mOldBrush := SelectObject(ADC, GetStockObject(NULL_BRUSH));
  Winapi.Windows.Rectangle(ADC, AFrame.Left, AFrame.Top, AFrame.Right, AFrame.Bottom);
  SelectObject(ADC, mOldBrush);
  SelectObject(ADC, mOldPen);
end;

/// <summary>Marke ACaption kursiv ab Spalte AColumn der Zeile ARect.</summary>
procedure PaintMark(const AContext: INTACodeEditorPaintContext; AColumn: Integer; const ARect: TRect;
  const ACaption: string; AColor: TColor);
var
  mAt: TRect;
  mFont: TFont;
begin
  mAt := AContext.EditorState.GetCharacterPosPx(AColumn, AContext.EditorLineNum);
  mFont := TFont.Create;
  try
    mFont.Assign(AContext.Canvas.Font);
    AContext.Canvas.Font.Style := [fsItalic];
    AContext.Canvas.Font.Color := AColor;
    AContext.Canvas.Brush.Style := bsClear;
    AContext.Canvas.TextOut(mAt.Left, ARect.Top, ACaption);
    AContext.Canvas.Font.Assign(mFont);
  finally
    mFont.Free;
  end;
end;

/// <summary>Rahmen der Vorkommen in Zeile ALine und (in der Zeile des bearbeiteten) die Marke dahinter.</summary>
procedure PaintRun(const ASession: TAtlasLinkedSession; ATabWidth: Integer; const ACaption: string;
  const ARect: TRect; const AContext: INTACodeEditorPaintContext; ALine: Integer);
var
  mText: string;
  mIndex, mSaved: Integer;
  mRanges: TAtlasLinkedRanges;
  mColor: COLORREF;
  mDC: HDC;
  mCode: TRect;
  mBrush: HBRUSH;
  mPen: HPEN;
begin
  mText := TTextLines.LineAt(ASession.Lines, ALine);
  mRanges := ASession.Ranges;
  mColor := COLORREF(ColorToRGB(TColor(TAtlasIdeStyle.Colors.Accent)));
  if ASession.Problem <> TAtlasLinkedProblem.None then
  begin
    mColor := COLORREF(ColorToRGB(TColor(TAtlasIdeStyle.Colors.Error)));
  end;
  mDC := AContext.Canvas.Handle;
  mCode := AContext.LineState.CodeRect;
  mSaved := SaveDC(mDC);
  mBrush := CreateSolidBrush(mColor);
  mPen := CreatePen(PS_DOT, 1, mColor);
  try
    if mCode.Right > mCode.Left then
    begin
      IntersectClipRect(mDC, mCode.Left, ARect.Top, ARect.Right, ARect.Bottom);
    end;
    for mIndex := 0 to High(mRanges) do
    begin
      if mRanges[mIndex].Line = ALine then
      begin
        PaintFrame(mDC, FrameOf(AContext, mText, mRanges[mIndex], ATabWidth, ARect),
          mIndex = ASession.Primary, mBrush, mPen);
      end;
    end;
    // Marke hinter der Zeile des bearbeiteten Vorkommens: Anzahl bzw. Konflikt.
    if ASession.PrimaryRange.Line = ALine then
    begin
      PaintMark(AContext, TLspSession.IndexToColumn(mText, Length(mText), ATabWidth) + 2, ARect, ACaption,
        TColor(mColor));
    end;
  finally
    DeleteObject(mPen);
    DeleteObject(mBrush);
    RestoreDC(mDC, mSaved);
  end;
end;

{ TAtlasIdeLinkedEditing.TEvents }

function TAtlasIdeLinkedEditing.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeLinkedEditing.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeLinkedEditing }

constructor TAtlasIdeLinkedEditing.Create(const ABusy: TFunc<Boolean>; const ASession: TAtlasLinkedSessionFunc;
  const AStatus: TAtlasLinkedStatusProc);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FBusy := ABusy;
  FStatus := AStatus;
  FIndex := -1;
  FSession := TAtlasLinkedSession.Create(
    procedure
    begin
      Refresh;
    end,
    procedure
    begin
      Finished;
    end);
  FQuery := TAtlasIdeLinkedEditingQuery.Create(ASession, DeliverToInstance());
  FMessages := TApplicationEvents.Create(nil);
  FMessages.OnMessage := AppMessage;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasIdeLinkedEditing.Destroy;
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
  end;
  FEventsRef := nil;
  FreeAndNil(FMessages);
  FreeAndNil(FTimer);
  // Wartet laufende Anfragen ab.
  FreeAndNil(FQuery);
  if Assigned(FStatus) and (FSession <> nil) and FSession.Active then
  begin
    FStatus('', '');
  end;
  FreeAndNil(FSession);
  inherited;
end;

function TAtlasIdeLinkedEditing.IsBusy: Boolean;
begin
  Result := Assigned(FBusy) and FBusy();
end;

procedure TAtlasIdeLinkedEditing.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.LinkedEditing) then
  begin
    Exit;
  end;
  try
    case Msg.message of
      WM_KEYDOWN, WM_SYSKEYDOWN:
        KeyDown(Msg, Handled);
      WM_CHAR:
        CharTyped(Msg, Handled);
    end;
  except
    // Keine Exception an die IDE (#493); die Nachricht geht dann normal weiter.
    on E: Exception do
    begin
      Handled := False;
      TAtlasGuard.Report(TAtlasFeature.LinkedEditing, E);
    end;
  end;
end;

procedure TAtlasIdeLinkedEditing.KeyDown(const AMsg: TMsg; var AHandled: Boolean);
begin
  if not TAtlasEditorBuffer.IsEditorWindow(AMsg.hwnd) then
  begin
    Exit;
  end;
  if not Enabled or IsBusy then
  begin
    Finish;
    Exit;
  end;
  case TAtlasLinkedKeys.KeyStep(Word(AMsg.wParam), CurrentShift <> [], FSession.Active,
    FSession.Problem <> TAtlasLinkedProblem.None) of
    TAtlasLinkedKeyStep.RestoreAndFinish:
      begin
        FSession.Restore;
        Finish;
        AHandled := True;
      end;
    TAtlasLinkedKeyStep.Finish:
      begin
        Finish;
        AHandled := True;
      end;
    TAtlasLinkedKeyStep.Backspace:
      AHandled := Edit(TAtlasLinkedKey.Backspace, '');
    TAtlasLinkedKeyStep.Delete:
      AHandled := Edit(TAtlasLinkedKey.Delete, '');
  end;
end;

procedure TAtlasIdeLinkedEditing.CharTyped(const AMsg: TMsg; var AHandled: Boolean);
var
  mTyped: Char;
begin
  if not TAtlasEditorBuffer.IsEditorWindow(AMsg.hwnd) or not Enabled or IsBusy then
  begin
    Exit;
  end;
  mTyped := Char(AMsg.wParam);
  case TAtlasLinkedKeys.CharStep(mTyped, FHighSurrogate <> #0) of
    TAtlasLinkedCharStep.HighSurrogate:
      // Zeichen außerhalb der Grundebene kommen als zwei WM_CHAR; nur in einer laufenden Sitzung.
      if FSession.Active then
      begin
        FHighSurrogate := mTyped;
        AHandled := True;
      end;
    TAtlasLinkedCharStep.LowSurrogate:
      InsertSurrogates(mTyped, AHandled);
    TAtlasLinkedCharStep.Insert:
      begin
        FHighSurrogate := #0;
        AHandled := Edit(TAtlasLinkedKey.Insert, mTyped);
      end;
    TAtlasLinkedCharStep.Finish:
      begin
        // Leerzeichen, Punkt, Klammer ...: Sitzung zu Ende, das Zeichen schreibt die IDE.
        FHighSurrogate := #0;
        Finish;
      end;
  end;
end;

procedure TAtlasIdeLinkedEditing.InsertSurrogates(ATyped: Char; var AHandled: Boolean);
var
  mPair: string;
begin
  mPair := FHighSurrogate + ATyped;
  FHighSurrogate := #0;
  AHandled := True;
  if not Edit(TAtlasLinkedKey.Insert, mPair) and (TAtlasEditorBuffer.ActiveView <> nil) then
  begin
    TAtlasEditorBuffer.ActiveView.Position.InsertText(mPair);
  end;
end;

procedure TAtlasIdeLinkedEditing.TimerTick(Sender: TObject);
begin
  try
    if TAtlasGuard.Disabled(TAtlasFeature.LinkedEditing) then
    begin
      Exit;
    end;
    FQuery.Prune;
    if FSession.Active then
    begin
      if not FSession.Writing then
      begin
        CheckRun;
      end;
    end
    else if Enabled and not IsBusy and Application.Active then
    begin
      FQuery.Watch(TAtlasEditorBuffer.ActiveView);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LinkedEditing, E);
  end;
end;

procedure TAtlasIdeLinkedEditing.CheckRun;
var
  mView: IOTAEditView;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  // Datei gewechselt, Formular angezeigt oder abgeschaltet: Sitzung zu Ende.
  if Lost(mView) then
  begin
    Finish;
    Exit;
  end;
  FSession.Check(TAtlasIdeEditSurface.Wrap(mView));
end;

function TAtlasIdeLinkedEditing.Lost(const AView: IOTAEditView): Boolean;
begin
  Result := (AView = nil) or (AView.Buffer = nil) or not SameText(AView.Buffer.FileName, FSession.FileName) or
    not Enabled or IsBusy or FormShown;
end;

procedure TAtlasIdeLinkedEditing.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mLine: Integer;
  mView: IOTAEditView;
  mCaption: string;
begin
  if not FSession.Active or TAtlasGuard.Disabled(TAtlasFeature.LinkedEditing) then
  begin
    Exit;
  end;
  try
    // Nur, wenn die Zeile im Editor dem bekannten Stand entspricht (sonst steht gleich ein Reconcile an).
    mView := Context.EditView;
    if (mView <> nil) and (mView.Buffer <> nil) and TAtlasPaintedLine.Resolve(Stage, BeforeEvent, Context,
      FSession.FileName, FSession.Lines, mLine) then
    begin
      // Die Marke steht nur in der Zeile des bearbeiteten Vorkommens.
      mCaption := '';
      if FSession.PrimaryRange.Line = mLine then
      begin
        mCaption := Caption;
      end;
      PaintRun(FSession, TAtlasEditorBuffer.TabWidth(mView.Buffer), mCaption, Rect, Context, mLine);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LinkedEditing, E);
  end;
end;

function TAtlasIdeLinkedEditing.Start(const AView: IOTAEditView): Boolean;
var
  mCandidate: TAtlasLinkedCandidate;
begin
  mCandidate := FQuery.Candidate;
  Result := Enabled and not IsBusy and mCandidate.Valid and FSession.Start(TAtlasIdeEditSurface.Wrap(AView),
    mCandidate.FileName, mCandidate.Text, mCandidate.Ranges, mCandidate.Conflicts);
  if Result then
  begin
    FQuery.Drop;
  end;
end;

function TAtlasIdeLinkedEditing.Edit(AKind: TAtlasLinkedKey; const AInsert: string): Boolean;
var
  mView: IOTAEditView;
begin
  Result := False;
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  if FSession.Active and not SameText(mView.Buffer.FileName, FSession.FileName) then
  begin
    Finish;
  end;
  if not FSession.Active and not Start(mView) then
  begin
    Exit;
  end;
  Result := FSession.Key(TAtlasIdeEditSurface.Wrap(mView), AKind, AInsert);
end;

function TAtlasIdeLinkedEditing.ProblemText: string;
begin
  case FSession.Problem of
    TAtlasLinkedProblem.Reserved:
      Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.LinkedEditingReserved, [FSession.PrimaryName]);
    TAtlasLinkedProblem.Visible:
      Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.LinkedEditingVisible, [FSession.Detail]);
  else
    Result := '';
  end;
end;

function TAtlasIdeLinkedEditing.Caption: string;
begin
  Result := ProblemText;
  if Result = '' then
  begin
    Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.LinkedEditingCount, [Length(FSession.Ranges)]);
  end;
end;

procedure TAtlasIdeLinkedEditing.Refresh;
var
  mHint: string;
begin
  if not FSession.Active then
  begin
    Exit;
  end;
  if Assigned(FStatus) then
  begin
    mHint := '';
    if ProblemText <> '' then
    begin
      mHint := TAtlasEditorStrings.Text(TAtlasEditorTextId.LinkedEditingRestoreHint);
    end;
    FStatus(Caption, mHint);
  end;
  Invalidate;
end;

procedure TAtlasIdeLinkedEditing.Finished;
begin
  if Assigned(FStatus) then
  begin
    FStatus('', '');
  end;
  Invalidate;
end;

procedure TAtlasIdeLinkedEditing.Finish;
begin
  FSession.Finish;
  FHighSurrogate := #0;
end;

class procedure TAtlasIdeLinkedEditing.Install(const ABusy: TFunc<Boolean>; const ASession: TAtlasLinkedSessionFunc;
  const AStatus: TAtlasLinkedStatusProc);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeLinkedEditing.Create(ABusy, ASession, AStatus);
  end;
end;

class procedure TAtlasIdeLinkedEditing.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeLinkedEditing.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.LinkedEditing;
end;

class function TAtlasIdeLinkedEditing.Active: Boolean;
begin
  Result := (FInstance <> nil) and FInstance.FSession.Active;
end;

class procedure TAtlasIdeLinkedEditing.Dismiss;
begin
  if FInstance <> nil then
  begin
    FInstance.Finish;
    FInstance.FQuery.Drop;
  end;
end;

class procedure TAtlasIdeLinkedEditing.EditorModified(const AView: IOTAEditView);
begin
  if (FInstance = nil) or FInstance.FSession.Writing then
  begin
    Exit;
  end;
  // Ohne Sitzung gilt die letzte Antwort nicht mehr; beim nächsten Ruhen fragt Atlas neu.
  if not FInstance.FSession.Active then
  begin
    FInstance.FQuery.Forget;
    Exit;
  end;
  if (AView = nil) or (AView.Buffer = nil) or not SameText(AView.Buffer.FileName, FInstance.FSession.FileName) then
  begin
    Exit;
  end;
  // Nie im Notifier schreiben: nach der Änderung, in der Warteschlange des Hauptthreads.
  TAtlasMainThread.ForceQueue(TAtlasFeature.LinkedEditing,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.LinkedEditing,
        procedure
        begin
          if FInstance <> nil then
          begin
            FInstance.FSession.BufferChanged;
          end;
        end);
    end);
end;

end.
