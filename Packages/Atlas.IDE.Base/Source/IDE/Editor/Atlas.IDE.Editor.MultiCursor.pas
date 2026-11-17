unit Atlas.IDE.Editor.MultiCursor;

// Mehrere Einfügemarken (#589, experimentell) im Editor. Was sich an den
// Marken ändert, rechnet Atlas.Core.Editor.MultiCursor aus; den Ablauf im
// Puffer führt Atlas.Core.Editor.MultiCursorSession über
// Atlas.IDE.Editor.EditSurface. Hier bleiben Tasten, Maus, Zwischenablage,
// Takt, Zeichnen und Statusfeld.
// - Marken setzen: Strg+D, Alt+Umschalt+I und Strg+Alt+↑/↓ sind Editorbefehle
//   (Atlas.IDE.Commands.Bindings) mit Rückfall: Ohne Treffer geht die Taste an
//   die IDE, Strg+D ohne Wort am Cursor also an „Quelltext formatieren“.
//   Alt+Klick (bzw. Strg+Klick, editor.multiCursorModifier) fängt
//   Application.OnMessage ab, bevor der Editor ihn sieht (sonst Spaltenblock
//   bzw. Gehe zu Deklaration).
// - Solange Zusatzmarken bestehen, fängt Application.OnMessage im Editor
//   Zeichen (WM_CHAR, also auch tote Tasten und AltGr), Rücktaste, Entf,
//   Enter, Pfeile, Pos1/Ende (mit Umschalt bzw. Strg), Kopieren, Ausschneiden,
//   Einfügen, Esc und Strg+K mit der Taste fürs Überspringen ab und führt sie
//   an allen Marken aus: ein Schreiber je Tastendruck, also ein
//   Rückgängig-Schritt. Derselbe Weg in Delphi 12 und 13, denn EditorKeyDown
//   (nur Delphi 13) liefert keine Zeichen.
// - Ein öffnendes Zeichen bei Markierungen umschließt sie an allen Marken
//   (#672, Atlas.Core.Editor.WrapSelection), solange editor.wrapSelection an
//   ist; Marken ohne Markierung bekommen das Zeichen.
// - Andere Änderungen an der Hauptmarke (Übernahme eines Vorschlags, Tab,
//   Vorlagen der IDE) laufen in der IDE; danach führt Mirror sie an den
//   Zusatzmarken aus (eigener Rückgängig-Schritt). Änderungen anderswo
//   verschieben die Marken (Shift).
// - Rückgängig und Wiederholen der IDE: Steht der Text danach auf dem Stand
//   vor bzw. nach einem eigenen Schritt, kehren dessen Marken zurück.
// - Die Hauptmarke ist der Cursor der IDE samt Markierung; Atlas liest sie
//   vor jedem Schritt und setzt sie danach.
// - Während die Vervollständigung offen ist oder ein Platzhalter-Modus läuft,
//   fängt Atlas keine Taste ab und Strg+D wirkt nicht.
// - Beenden: Esc, Klick ohne Taste, Speichern, Datei- oder Formularwechsel,
//   Einstellung aus.
// - Zeichnen per PaintLine (plsEndPaint): Markierungen der Zusatzmarken halb
//   durchsichtig in der Akzentfarbe, die Marken als 2 Pixel breite Striche,
//   blinkend im Takt des System-Carets; bei abgeschalteten Animationen von
//   Windows statisch.
// - Statusfeld „3 Einfügemarken“, solange mehr als eine Marke aktiv ist.
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
  Atlas.Core.Editor.EditSurface,
  Atlas.Core.Editor.MultiCursorSession;

type
  /// <summary>Statusfeld setzen; AText '' entfernt es.</summary>
  TAtlasMultiCursorStatusProc = reference to procedure(const AText, AHint: string);

  TAtlasIdeMultiCursor = class
  private const
    /// <summary>Deckkraft der Markierungen über dem Text (0–255).</summary>
    cSelectionAlpha = 70;
    /// <summary>Breite der gezeichneten Marken in Pixeln.</summary>
    cCaretWidth = 2;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;

    /// <summary>Eingabe zwischen zwei Nachrichten: Strg+K wartet auf die Taste fürs Überspringen, ein hohes
    /// Surrogat auf sein tiefes.</summary>
    TInput = record
      Chord: Boolean;
      HighSurrogate: Char;
    end;
  private class var
    FInstance: TAtlasIdeMultiCursor;
  private
    FBusy: TFunc<Boolean>;
    FStatus: TAtlasMultiCursorStatusProc;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FMessages: TApplicationEvents;
    FTimer: TTimer;
    FBlink: Boolean;
    FWasModified: Boolean;
    FInput: TInput;
    FSession: TAtlasMultiCursorSession;
    function IsBusy: Boolean;
    function IsActive: Boolean;
    /// <summary>Puffer der aktiven Ansicht; nil ohne.</summary>
    class function ActiveSurface: IAtlasEditSurface; static;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure MouseDown(const AMsg: TMsg; var AHandled: Boolean);
    procedure KeyDown(const AMsg: TMsg; var AHandled: Boolean);
    procedure CharTyped(const AMsg: TMsg; var AHandled: Boolean);
    procedure TimerTick(Sender: TObject);
    /// <summary>Hauptmarke und Zustand der IDE nachziehen; False, wenn die Zusatzmarken enden (Datei gewechselt,
    /// Formular angezeigt, gespeichert, abgeschaltet).</summary>
    function Follow: Boolean;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure PaintCarets(const AContext: INTACodeEditorPaintContext; const ARect: TRect);
    procedure Refresh;
    /// <summary>Die Zusatzmarken sind zu Ende: Eingabe vergessen, Takt aus, Statusfeld leeren.</summary>
    procedure Finished;
    procedure Finish;
  public
    constructor Create(const ABusy: TFunc<Boolean>; const AStatus: TAtlasMultiCursorStatusProc);
    destructor Destroy; override;
    /// <summary>ABusy: Vervollständigung offen oder Platzhalter-Modus aktiv? AStatus setzt das Statusfeld.</summary>
    class procedure Install(const ABusy: TFunc<Boolean>; const AStatus: TAtlasMultiCursorStatusProc); static;
    class procedure Uninstall; static;
    /// <summary>editor.multiCursor an (experimentell, also nur mit experimental.enabled) und Atlas an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Mehr als eine Marke aktiv?</summary>
    class function Active: Boolean; static;
    /// <summary>Strg+D: Wort markieren bzw. nächstes Vorkommen hinzufügen; False gibt die Taste an die IDE.</summary>
    class function TryNext: Boolean; static;
    /// <summary>Alt+Umschalt+I: Marken an die Zeilenenden der Markierung; False ohne Markierung.</summary>
    class function TryLineEnds: Boolean; static;
    /// <summary>Strg+Alt+↑/↓: Marke in der Zeile darüber bzw. darunter.</summary>
    class function TryVertical(AUp: Boolean): Boolean; static;
    /// <summary>Zusatzmarken entfernen (Ansicht gewechselt).</summary>
    class procedure Dismiss; static;
    /// <summary>Aus EditorViewModified: fremde Änderung nachziehen (in der Warteschlange).</summary>
    class procedure EditorModified(const AView: IOTAEditView); static;
  end;

implementation

uses
  Atlas.Core.Editor.MultiCursor,
  Atlas.Core.Editor.MultiCursorKeys,
  System.Math,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.Clipbrd,
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
  Atlas.IDE.Editor.WrapSelection;

const
  // Fehlt in älteren Fassungen von Winapi.Windows.
  cSpiGetClientAreaAnimation = $1042;

type
  /// <summary>Was eine Zeile zum Zeichnen der Zusatzmarken braucht.</summary>
  TPaintRun = record
    Context: INTACodeEditorPaintContext;
    DC: HDC;
    Rect: TRect;
    Line: Integer;
    Text: string;
    TabWidth: Integer;
    Color: COLORREF;
    Brush: HBRUSH;
  end;

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

/// <summary>Blinkt der Caret laut Windows (Animationen an)?</summary>
function Blinking: Boolean;
var
  mAnimate: BOOL;
begin
  mAnimate := True;
  if not SystemParametersInfo(cSpiGetClientAreaAnimation, 0, @mAnimate, 0) then
  begin
    mAnimate := True;
  end;
  Result := mAnimate;
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

/// <summary>Zeigt die IDE gerade ein Formular statt des Quelltexts?</summary>
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

/// <summary>Setzt ein Klick mit AShift eine Marke (editor.multiCursorModifier, Funktion an)?</summary>
function ClickWanted(AShift: TShiftState): Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasMultiCursorKeys.ClickWanted(AShift,
    mSettings.MultiCursorModifier = TAtlasPluginSettings.cMultiCursorModifierCtrl,
    mSettings.Enabled and mSettings.MultiCursor);
end;

/// <summary>Datei, Zeile und Zeichen (0-basiert) des Editors unter dem Klick AMsg; False außerhalb des Textes.
/// </summary>
function ClickedAt(const AMsg: TMsg; out AFileName: string; out ALine, ACharacter: Integer): Boolean;
var
  mServices: INTACodeEditorServices;
  mState: INTACodeEditorState;
  mVisibleLine, mColumn: Integer;
  mLineText: string;
begin
  Result := False;
  AFileName := '';
  ALine := -1;
  ACharacter := 0;
  mColumn := 0;
  if not Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    Exit;
  end;
  mState := mServices.EditorState[FindControl(AMsg.hwnd)];
  if (mState = nil) or not mState.PointToCharacterPos(Point(SmallInt(LoWord(Cardinal(AMsg.lParam))),
    SmallInt(HiWord(Cardinal(AMsg.lParam)))), mColumn, mVisibleLine) then
  begin
    Exit;
  end;
  ALine := mState.LineState[mVisibleLine].LogicalLineNum - 1;
  Result := (ALine >= 0) and (mState.View <> nil) and (mState.View.Buffer <> nil);
  if Result then
  begin
    AFileName := mState.View.Buffer.FileName;
    mLineText := TAtlasEditorBuffer.LineText(mState.View, ALine + 1);
    ACharacter := Min(TLspSession.ColumnToIndex(mLineText, mColumn, TAtlasEditorBuffer.TabWidth(mState.View.Buffer)),
      Length(mLineText));
  end;
end;

/// <summary>ARect halb durchsichtig mit AColor überziehen; der Text bleibt lesbar.</summary>
procedure Blend(ADC: HDC; const ARect: TRect; AColor: COLORREF);
var
  mMemory: HDC;
  mBitmap, mOld: HBITMAP;
  mFunc: TBlendFunction;
begin
  if (ARect.Right <= ARect.Left) or (ARect.Bottom <= ARect.Top) then
  begin
    Exit;
  end;
  mMemory := CreateCompatibleDC(ADC);
  mBitmap := CreateCompatibleBitmap(ADC, 1, 1);
  mOld := SelectObject(mMemory, mBitmap);
  try
    SetPixel(mMemory, 0, 0, AColor);
    mFunc.BlendOp := AC_SRC_OVER;
    mFunc.BlendFlags := 0;
    mFunc.SourceConstantAlpha := TAtlasIdeMultiCursor.cSelectionAlpha;
    mFunc.AlphaFormat := 0;
    AlphaBlend(ADC, ARect.Left, ARect.Top, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top, mMemory, 0, 0, 1, 1,
      mFunc);
  finally
    SelectObject(mMemory, mOld);
    DeleteObject(mBitmap);
    DeleteDC(mMemory);
  end;
end;

/// <summary>Bildschirmrechteck des Zeichens ACharacter (0-basiert) der Zeile.</summary>
function PixelAt(const ARun: TPaintRun; ACharacter: Integer): TRect;
begin
  Result := ARun.Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(ARun.Text, ACharacter,
    ARun.TabWidth), ARun.Context.EditorLineNum);
end;

/// <summary>Den Teil der Markierung von ACaret, der in der Zeile liegt, halb durchsichtig überziehen.</summary>
procedure PaintSelection(const ARun: TPaintRun; const ACaret: TAtlasCaret);
var
  mStartLine, mStartCharacter, mEndLine, mEndCharacter, mFrom, mTill: Integer;
  mFirst, mLast: TRect;
begin
  ACaret.Bounds(mStartLine, mStartCharacter, mEndLine, mEndCharacter);
  if (ARun.Line < mStartLine) or (ARun.Line > mEndLine) then
  begin
    Exit;
  end;
  mFrom := 0;
  if ARun.Line = mStartLine then
  begin
    mFrom := mStartCharacter;
  end;
  mTill := Length(ARun.Text) + 1;
  if ARun.Line = mEndLine then
  begin
    mTill := mEndCharacter;
  end;
  mFirst := PixelAt(ARun, mFrom);
  mLast := PixelAt(ARun, mTill);
  Blend(ARun.DC, TRect.Create(mFirst.Left, ARun.Rect.Top, Max(mLast.Left, mFirst.Left + 1), ARun.Rect.Bottom),
    ARun.Color);
end;

/// <summary>Markierung und (wenn ABlink) Strich einer Zusatzmarke in der Zeile.</summary>
procedure PaintCaret(const ARun: TPaintRun; const ACaret: TAtlasCaret; ABlink: Boolean);
var
  mFirst: TRect;
begin
  if ACaret.HasSelection then
  begin
    PaintSelection(ARun, ACaret);
  end;
  if (ACaret.Line = ARun.Line) and ABlink then
  begin
    mFirst := PixelAt(ARun, ACaret.Character);
    FillRect(ARun.DC, TRect.Create(mFirst.Left, ARun.Rect.Top, mFirst.Left + TAtlasIdeMultiCursor.cCaretWidth,
      ARun.Rect.Bottom), ARun.Brush);
  end;
end;

/// <summary>Markierungen aller Marken in die Zwischenablage; False ohne Markierung (Kopieren bleibt der IDE).
/// </summary>
function CopyTo(const ASession: TAtlasMultiCursorSession; const ASurface: IAtlasEditSurface): Boolean;
var
  mSelected: string;
begin
  Result := ASession.Selected(ASurface, mSelected);
  if Result then
  begin
    Clipboard.AsText := mSelected;
  end;
end;

/// <summary>Text der Zwischenablage an allen Marken einfügen.</summary>
procedure PasteFrom(const ASession: TAtlasMultiCursorSession; const ASurface: IAtlasEditSurface);
begin
  if Clipboard.HasFormat(CF_UNICODETEXT) or Clipboard.HasFormat(CF_TEXT) then
  begin
    ASession.DoPaste(ASurface, Clipboard.AsText);
  end;
end;

/// <summary>Bearbeitende Taste ACommand an allen Marken von ASession ausführen; False gibt sie an die IDE.</summary>
function PerformEdit(const ASession: TAtlasMultiCursorSession; const ASurface: IAtlasEditSurface;
  const ACommand: TAtlasMultiCursorKeyCommand): Boolean;
begin
  Result := True;
  case ACommand.Action of
    TAtlasMultiCursorKeyAction.Skip:
      ASession.DoSkip(ASurface);
    TAtlasMultiCursorKeyAction.Chord:
      ;
    TAtlasMultiCursorKeyAction.Backspace:
      ASession.DoEdit(ASurface, TAtlasCaretEditKind.Backspace, '');
    TAtlasMultiCursorKeyAction.Delete:
      ASession.DoEdit(ASurface, TAtlasCaretEditKind.Delete, '');
    TAtlasMultiCursorKeyAction.NewLine:
      ASession.DoEdit(ASurface, TAtlasCaretEditKind.NewLine, '');
    TAtlasMultiCursorKeyAction.Cut:
      if CopyTo(ASession, ASurface) then
      begin
        ASession.DoEdit(ASurface, TAtlasCaretEditKind.Insert, '');
      end;
    TAtlasMultiCursorKeyAction.Copy:
      Result := CopyTo(ASession, ASurface);
    TAtlasMultiCursorKeyAction.Paste:
      PasteFrom(ASession, ASurface);
    TAtlasMultiCursorKeyAction.Move:
      ASession.DoMove(ASurface, ACommand.Move, ACommand.Extend);
  else
    Result := False;
  end;
end;

{ TAtlasIdeMultiCursor.TEvents }

function TAtlasIdeMultiCursor.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeMultiCursor.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeMultiCursor }

constructor TAtlasIdeMultiCursor.Create(const ABusy: TFunc<Boolean>; const AStatus: TAtlasMultiCursorStatusProc);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FBusy := ABusy;
  FStatus := AStatus;
  FIndex := -1;
  FSession := TAtlasMultiCursorSession.Create(
    procedure
    begin
      Finished;
    end,
    procedure
    begin
      Refresh;
    end);
  FMessages := TApplicationEvents.Create(nil);
  FMessages.OnMessage := AppMessage;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := Max(200, Integer(GetCaretBlinkTime));
  FTimer.OnTimer := TimerTick;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasIdeMultiCursor.Destroy;
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
  if Assigned(FStatus) and IsActive then
  begin
    FStatus('', '');
  end;
  FreeAndNil(FSession);
  inherited;
end;

function TAtlasIdeMultiCursor.IsBusy: Boolean;
begin
  Result := Assigned(FBusy) and FBusy();
end;

function TAtlasIdeMultiCursor.IsActive: Boolean;
begin
  Result := (FSession <> nil) and FSession.Active;
end;

class function TAtlasIdeMultiCursor.ActiveSurface: IAtlasEditSurface;
begin
  Result := TAtlasIdeEditSurface.Wrap(TAtlasEditorBuffer.ActiveView);
end;

procedure TAtlasIdeMultiCursor.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.MultiCursor) then
  begin
    Exit;
  end;
  try
    case Msg.message of
      WM_LBUTTONDOWN:
        MouseDown(Msg, Handled);
      WM_KEYDOWN, WM_SYSKEYDOWN:
        if IsActive then
        begin
          KeyDown(Msg, Handled);
        end;
      WM_CHAR:
        if IsActive then
        begin
          CharTyped(Msg, Handled);
        end;
    end;
  except
    // Keine Exception an die IDE (#493); die Nachricht geht dann normal weiter.
    on E: Exception do
    begin
      Handled := False;
      TAtlasGuard.Report(TAtlasFeature.MultiCursor, E);
    end;
  end;
end;

procedure TAtlasIdeMultiCursor.MouseDown(const AMsg: TMsg; var AHandled: Boolean);
var
  mShift: TShiftState;
  mFileName: string;
  mLine, mCharacter: Integer;
begin
  if not TAtlasEditorBuffer.IsEditorWindow(AMsg.hwnd) then
  begin
    Exit;
  end;
  mShift := CurrentShift;
  if not ClickWanted(mShift) or IsBusy then
  begin
    // Ein einfacher Klick beendet die Zusatzmarken; der Klick selbst gehört der IDE.
    if IsActive and (mShift = []) then
    begin
      Finish;
    end;
    Exit;
  end;
  if ClickedAt(AMsg, mFileName, mLine, mCharacter) then
  begin
    AHandled := FSession.Toggle(ActiveSurface, mFileName, mLine, mCharacter);
  end;
end;

procedure TAtlasIdeMultiCursor.KeyDown(const AMsg: TMsg; var AHandled: Boolean);
var
  mKey: Word;
  mShift: TShiftState;
  mSettings: TAtlasPluginSettings;
  mCommand: TAtlasMultiCursorKeyCommand;
begin
  mKey := Word(AMsg.wParam);
  if not TAtlasEditorBuffer.IsEditorWindow(AMsg.hwnd) or IsBusy
    or (mKey = VK_SHIFT) or (mKey = VK_CONTROL) or (mKey = VK_MENU) then
  begin
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Current;
  if not mSettings.Enabled or not mSettings.MultiCursor then
  begin
    Finish;
    Exit;
  end;
  mShift := CurrentShift;
  mCommand := Default(TAtlasMultiCursorKeyCommand);
  mCommand.Action := TAtlasMultiCursorKeys.Chord(FInput.Chord, mKey, mShift, mSettings.MultiCursorSkipKey);
  if mCommand.Action = TAtlasMultiCursorKeyAction.None then
  begin
    mCommand := TAtlasMultiCursorKeys.Command(mKey, mShift);
  end;
  if mCommand.Action = TAtlasMultiCursorKeyAction.Finish then
  begin
    Finish;
    AHandled := True;
  end
  else
  begin
    AHandled := PerformEdit(FSession, ActiveSurface, mCommand);
  end;
end;

procedure TAtlasIdeMultiCursor.CharTyped(const AMsg: TMsg; var AHandled: Boolean);
var
  mTyped: Char;
  mText: string;
  mSurface: IAtlasEditSurface;
begin
  mTyped := Char(AMsg.wParam);
  // Steuerzeichen (Strg+Buchstabe, Rücktaste, Enter, Tab) nicht: Tab übernimmt die IDE, Mirror zieht nach.
  if not TAtlasEditorBuffer.IsEditorWindow(AMsg.hwnd) or IsBusy or TAtlasMultiCursorKeys.IsControlChar(mTyped) then
  begin
    Exit;
  end;
  AHandled := True;
  if not TAtlasMultiCursorKeys.Compose(FInput.HighSurrogate, mTyped, mText) then
  begin
    Exit;
  end;
  // Öffnendes Zeichen bei Markierungen: umschließen (#672) statt überschreiben.
  mSurface := ActiveSurface;
  if (Length(mText) > 1) or not TAtlasIdeWrapSelection.Enabled or
    not FSession.DoWrap(mSurface, mTyped, TAtlasIdeWrapSelection.Chars) then
  begin
    FSession.DoEdit(mSurface, TAtlasCaretEditKind.Insert, mText);
  end;
end;

procedure TAtlasIdeMultiCursor.TimerTick(Sender: TObject);
begin
  try
    if not IsActive then
    begin
      FTimer.Enabled := False;
    end
    else if not Follow then
    begin
      Finish;
    end
    else
    begin
      FBlink := not FBlink or not Blinking;
      Invalidate;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.MultiCursor, E);
  end;
end;

function TAtlasIdeMultiCursor.Follow: Boolean;
var
  mView: IOTAEditView;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  Result := (mView <> nil) and (mView.Buffer <> nil) and FSession.ShowsFile(mView.Buffer.FileName) and Enabled and
    not FormShown and
    not (FWasModified and not mView.Buffer.IsModified);
  if not Result then
  begin
    Exit;
  end;
  FWasModified := mView.Buffer.IsModified;
  // Cursor der IDE ohne Atlas bewegt (Bild auf/ab, Suchen): Hauptmarke nachziehen.
  FSession.SyncMain;
  Result := IsActive;
end;

procedure TAtlasIdeMultiCursor.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not IsActive or
    TAtlasGuard.Disabled(TAtlasFeature.MultiCursor) then
  begin
    Exit;
  end;
  try
    PaintCarets(Context, Rect);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.MultiCursor, E);
  end;
end;

procedure TAtlasIdeMultiCursor.PaintCarets(const AContext: INTACodeEditorPaintContext; const ARect: TRect);
var
  mRun: TPaintRun;
  mCode: TRect;
  mSaved, mIndex: Integer;
  mCarets: TAtlasCarets;
begin
  if not FSession.ShowsFile(AContext.FileName) or (AContext.LineState = nil) then
  begin
    Exit;
  end;
  mRun.Line := AContext.LogicalLineNum - 1;
  mRun.Text := FSession.LineText(mRun.Line);
  // Nur, wenn die Zeile im Editor dem bekannten Stand entspricht (sonst steht gleich ein Reconcile an).
  if TrimRight(AContext.LineState.Text) <> TrimRight(mRun.Text) then
  begin
    Exit;
  end;
  mRun.Context := AContext;
  mRun.Rect := ARect;
  mRun.TabWidth := FSession.Surface.TabWidth;
  mRun.Color := COLORREF(ColorToRGB(TColor(TAtlasIdeStyle.Colors.Accent)));
  mRun.DC := AContext.Canvas.Handle;
  mCode := AContext.LineState.CodeRect;
  mSaved := SaveDC(mRun.DC);
  mRun.Brush := CreateSolidBrush(mRun.Color);
  try
    if mCode.Right > mCode.Left then
    begin
      IntersectClipRect(mRun.DC, mCode.Left, ARect.Top, ARect.Right, ARect.Bottom);
    end;
    // Die Hauptmarke zeichnet die IDE.
    mCarets := FSession.Carets;
    for mIndex := 1 to High(mCarets) do
    begin
      PaintCaret(mRun, mCarets[mIndex], FBlink);
    end;
  finally
    DeleteObject(mRun.Brush);
    RestoreDC(mRun.DC, mSaved);
  end;
end;

procedure TAtlasIdeMultiCursor.Refresh;
begin
  if not IsActive then
  begin
    Finish;
    Exit;
  end;
  FWasModified := FSession.Surface.IsModified;
  if Assigned(FStatus) then
  begin
    FStatus(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.MultiCursorStatus, [FSession.Count]),
      TAtlasEditorStrings.Text(TAtlasEditorTextId.MultiCursorStatusHint));
  end;
  // Nach jedem Schritt sichtbar, dann wieder im Takt.
  FBlink := True;
  FTimer.Enabled := False;
  FTimer.Enabled := True;
  Invalidate;
end;

procedure TAtlasIdeMultiCursor.Finished;
begin
  FInput := Default(TInput);
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  if Assigned(FStatus) then
  begin
    FStatus('', '');
  end;
  Invalidate;
end;

procedure TAtlasIdeMultiCursor.Finish;
begin
  FSession.Finish;
  FInput := Default(TInput);
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
end;

class procedure TAtlasIdeMultiCursor.Install(const ABusy: TFunc<Boolean>; const AStatus: TAtlasMultiCursorStatusProc);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeMultiCursor.Create(ABusy, AStatus);
  end;
end;

class procedure TAtlasIdeMultiCursor.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeMultiCursor.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.MultiCursor;
end;

class function TAtlasIdeMultiCursor.Active: Boolean;
begin
  Result := (FInstance <> nil) and FInstance.IsActive;
end;

class function TAtlasIdeMultiCursor.TryNext: Boolean;
begin
  Result := (FInstance <> nil) and Enabled;
  // Platzhalter-Modus oder SyncEdit-ähnliche Zustände: Strg+D wirkungslos (die Taste bleibt bei Atlas).
  if Result and FInstance.IsBusy then
  begin
    Result := FInstance.IsActive;
  end
  else if Result then
  begin
    Result := FInstance.FSession.Next(ActiveSurface);
  end;
end;

class function TAtlasIdeMultiCursor.TryLineEnds: Boolean;
begin
  Result := (FInstance <> nil) and Enabled and not FInstance.IsBusy and FInstance.FSession.LineEnds(ActiveSurface);
end;

class function TAtlasIdeMultiCursor.TryVertical(AUp: Boolean): Boolean;
begin
  Result := (FInstance <> nil) and Enabled and not FInstance.IsBusy and
    FInstance.FSession.Vertical(ActiveSurface, AUp);
end;

class procedure TAtlasIdeMultiCursor.Dismiss;
begin
  if FInstance <> nil then
  begin
    FInstance.Finish;
  end;
end;

class procedure TAtlasIdeMultiCursor.EditorModified(const AView: IOTAEditView);
begin
  if (FInstance = nil) or not FInstance.IsActive or FInstance.FSession.Writing then
  begin
    Exit;
  end;
  if (AView = nil) or (AView.Buffer = nil) or not FInstance.FSession.ShowsFile(AView.Buffer.FileName) then
  begin
    Exit;
  end;
  // Nie im Notifier schreiben: nach der Änderung, in der Warteschlange des Hauptthreads.
  TAtlasMainThread.ForceQueue(TAtlasFeature.MultiCursor,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.MultiCursor,
        procedure
        begin
          if (FInstance <> nil) and FInstance.IsActive then
          begin
            FInstance.FSession.BufferChanged;
            FInstance.Refresh;
          end;
        end);
    end);
end;

end.
