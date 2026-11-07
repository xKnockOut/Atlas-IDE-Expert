unit Atlas.IDE.Editor.MultiCursor;

// Mehrere Einfügemarken (#589, experimentell) im Editor. Was sich an den
// Marken ändert, rechnet Atlas.Core.Editor.MultiCursor aus; hier bleiben
// Tasten, Maus, Puffer, Zeichnen und Statusfeld.
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
  Atlas.Core.Editor.MultiCursor,
  Atlas.IDE.Editor.MultiCursorState;

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
    FState: TAtlasIdeMultiCursorState;
    function IsBusy: Boolean;
    function IsActive: Boolean;
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
  System.Math,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.Menus,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.EditorRefresh;

const
  // Fehlt in älteren Fassungen von Winapi.Windows.
  cSpiGetClientAreaAnimation = $1042;

{$SCOPEDENUMS ON}

type
  /// <summary>Was eine Taste an allen Marken auslöst.</summary>
  TKeyAction = (None, Finish, Skip, Chord, Backspace, Delete, NewLine, Cut, Copy, Paste, Move);

{$SCOPEDENUMS OFF}

type
  TKeyCommand = record
    Action: TKeyAction;
    Move: TAtlasCaretMove;
    Extend: Boolean;
  end;

  /// <summary>Tastenregel: Key mit Mods (Exact: genau diese Umschalttasten, sonst Umschalt erweitert die
  /// Markierung) löst Action aus.</summary>
  TKeyRule = record
    Key: Word;
    Mods: TShiftState;
    Exact: Boolean;
    Action: TKeyAction;
    Move: TAtlasCaretMove;
  end;

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

const
  // Tasten, die Atlas abfängt, solange Zusatzmarken bestehen; alle anderen gehen an die IDE.
  cKeyRules: array[0..17] of TKeyRule = (
    (Key: VK_ESCAPE; Mods: []; Exact: True; Action: TKeyAction.Finish;
      Move: TAtlasCaretMove.Left),
    (Key: VK_BACK; Mods: []; Exact: False; Action: TKeyAction.Backspace;
      Move: TAtlasCaretMove.Left),
    (Key: VK_DELETE; Mods: []; Exact: True; Action: TKeyAction.Delete;
      Move: TAtlasCaretMove.Left),
    (Key: VK_DELETE; Mods: [ssShift]; Exact: True; Action: TKeyAction.Cut;
      Move: TAtlasCaretMove.Left),
    (Key: VK_RETURN; Mods: []; Exact: False; Action: TKeyAction.NewLine;
      Move: TAtlasCaretMove.Left),
    (Key: VK_LEFT; Mods: []; Exact: False; Action: TKeyAction.Move;
      Move: TAtlasCaretMove.Left),
    (Key: VK_LEFT; Mods: [ssCtrl]; Exact: False; Action: TKeyAction.Move;
      Move: TAtlasCaretMove.WordLeft),
    (Key: VK_RIGHT; Mods: []; Exact: False; Action: TKeyAction.Move;
      Move: TAtlasCaretMove.Right),
    (Key: VK_RIGHT; Mods: [ssCtrl]; Exact: False; Action: TKeyAction.Move;
      Move: TAtlasCaretMove.WordRight),
    (Key: VK_UP; Mods: []; Exact: False; Action: TKeyAction.Move;
      Move: TAtlasCaretMove.Up),
    (Key: VK_DOWN; Mods: []; Exact: False; Action: TKeyAction.Move;
      Move: TAtlasCaretMove.Down),
    (Key: VK_HOME; Mods: []; Exact: False; Action: TKeyAction.Move;
      Move: TAtlasCaretMove.LineStart),
    (Key: VK_END; Mods: []; Exact: False; Action: TKeyAction.Move;
      Move: TAtlasCaretMove.LineEnd),
    (Key: VK_INSERT; Mods: [ssCtrl]; Exact: True; Action: TKeyAction.Copy;
      Move: TAtlasCaretMove.Left),
    (Key: VK_INSERT; Mods: [ssShift]; Exact: True; Action: TKeyAction.Paste;
      Move: TAtlasCaretMove.Left),
    (Key: Ord('C'); Mods: [ssCtrl]; Exact: True; Action: TKeyAction.Copy;
      Move: TAtlasCaretMove.Left),
    (Key: Ord('X'); Mods: [ssCtrl]; Exact: True; Action: TKeyAction.Cut;
      Move: TAtlasCaretMove.Left),
    (Key: Ord('V'); Mods: [ssCtrl]; Exact: True; Action: TKeyAction.Paste;
      Move: TAtlasCaretMove.Left));

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

function IsEditorWindow(AWnd: HWND): Boolean;
var
  mControl: TWinControl;
begin
  mControl := FindControl(AWnd);
  Result := (mControl <> nil) and mControl.ClassNameIs('TEditControl');
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
  mWanted: TShiftState;
begin
  mSettings := TAtlasIdeSettings.Current;
  mWanted := [ssAlt];
  if mSettings.MultiCursorModifier = TAtlasPluginSettings.cMultiCursorModifierCtrl then
  begin
    mWanted := [ssCtrl];
  end;
  Result := (AShift = mWanted) and mSettings.Enabled and mSettings.MultiCursor;
end;

/// <summary>Datei, Zeile (0-basiert) und Spalte des Editors unter dem Klick AMsg; False außerhalb des Textes.
/// </summary>
function ClickedAt(const AMsg: TMsg; out AFileName: string; out ALine, AColumn: Integer): Boolean;
var
  mServices: INTACodeEditorServices;
  mState: INTACodeEditorState;
  mVisibleLine: Integer;
begin
  Result := False;
  AFileName := '';
  ALine := -1;
  AColumn := 0;
  if not Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    Exit;
  end;
  mState := mServices.EditorState[FindControl(AMsg.hwnd)];
  if (mState = nil) or not mState.PointToCharacterPos(Point(SmallInt(LoWord(Cardinal(AMsg.lParam))),
    SmallInt(HiWord(Cardinal(AMsg.lParam)))), AColumn, mVisibleLine) then
  begin
    Exit;
  end;
  ALine := mState.LineState[mVisibleLine].LogicalLineNum - 1;
  Result := (ALine >= 0) and (mState.View <> nil) and (mState.View.Buffer <> nil);
  if Result then
  begin
    AFileName := mState.View.Buffer.FileName;
  end;
end;

/// <summary>Regel für AKey mit AShift; Action None, wenn die Taste der IDE bleibt.</summary>
function KeyCommand(AKey: Word; AShift: TShiftState): TKeyCommand;
var
  mRule: TKeyRule;
  mMods: TShiftState;
begin
  Result := Default(TKeyCommand);
  for mRule in cKeyRules do
  begin
    mMods := AShift - [ssShift];
    if mRule.Exact then
    begin
      mMods := AShift;
    end;
    if (mRule.Key = AKey) and (mMods = mRule.Mods) then
    begin
      Result.Action := mRule.Action;
      Result.Move := mRule.Move;
      Result.Extend := ssShift in AShift;
      Exit;
    end;
  end;
end;

/// <summary>Strg+K, dann die Taste fürs Überspringen (ASkipKey, 0 = aus); jede andere Taste danach wirkt normal.
/// Skip, Chord oder None.</summary>
function ChordAction(var AChord: Boolean; AKey: Word; AShift: TShiftState;
  ASkipKey: Integer): TKeyAction;
begin
  Result := TKeyAction.None;
  if ASkipKey = 0 then
  begin
    AChord := False;
    Exit;
  end;
  if AChord and (ShortCut(AKey, AShift) = TShortCut(ASkipKey)) then
  begin
    Result := TKeyAction.Skip;
  end
  else if (AKey = Ord('K')) and (AShift = [ssCtrl]) then
  begin
    Result := TKeyAction.Chord;
  end;
  AChord := Result = TKeyAction.Chord;
end;

/// <summary>Zeichen außerhalb der Grundebene kommen als zwei WM_CHAR: Ein hohes Surrogat wartet in AHigh
/// (False), sonst steht in AText, was einzufügen ist.</summary>
function Compose(var AHigh: Char; ATyped: Char; out AText: string): Boolean;
begin
  AText := ATyped;
  Result := (ATyped < #$D800) or (ATyped > #$DBFF);
  if not Result then
  begin
    AHigh := ATyped;
    Exit;
  end;
  if (AHigh <> #0) and (ATyped >= #$DC00) and (ATyped <= #$DFFF) then
  begin
    AText := AHigh + ATyped;
  end;
  AHigh := #0;
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

/// <summary>ACommand an allen Marken von AOwner ausführen; False gibt die Taste an die IDE.</summary>
function Perform(AOwner: TAtlasIdeMultiCursor; const ACommand: TKeyCommand): Boolean;
begin
  Result := True;
  case ACommand.Action of
    TKeyAction.Finish:
      AOwner.Finish;
    TKeyAction.Skip:
      AOwner.FState.DoSkip;
    TKeyAction.Chord:
      ;
    TKeyAction.Backspace:
      AOwner.FState.DoEdit(TAtlasCaretEditKind.Backspace, '');
    TKeyAction.Delete:
      AOwner.FState.DoEdit(TAtlasCaretEditKind.Delete, '');
    TKeyAction.NewLine:
      AOwner.FState.DoEdit(TAtlasCaretEditKind.NewLine, '');
    TKeyAction.Cut:
      AOwner.FState.DoCut;
    TKeyAction.Copy:
      Result := AOwner.FState.DoCopy;
    TKeyAction.Paste:
      AOwner.FState.DoPaste;
    TKeyAction.Move:
      AOwner.FState.DoMove(ACommand.Move, ACommand.Extend);
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
  FState := TAtlasIdeMultiCursorState.Create(
    procedure
    begin
      Finish;
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
  FreeAndNil(FState);
  inherited;
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

function TAtlasIdeMultiCursor.IsActive: Boolean;
begin
  Result := (FState <> nil) and FState.Active;
end;

function TAtlasIdeMultiCursor.IsBusy: Boolean;
begin
  Result := Assigned(FBusy) and FBusy();
end;

procedure TAtlasIdeMultiCursor.Refresh;
begin
  if not IsActive then
  begin
    Finish;
    Exit;
  end;
  FWasModified := FState.View.Buffer.IsModified;
  if Assigned(FStatus) then
  begin
    FStatus(TAtlasStrings.Fmt(TAtlasTextId.MultiCursorStatus, [FState.Count]),
      TAtlasStrings.Text(TAtlasTextId.MultiCursorStatusHint));
  end;
  // Nach jedem Schritt sichtbar, dann wieder im Takt.
  FBlink := True;
  FTimer.Enabled := False;
  FTimer.Enabled := True;
  Invalidate;
end;

procedure TAtlasIdeMultiCursor.Finish;
var
  mWas: Boolean;
begin
  mWas := IsActive;
  FState.Clear;
  FInput := Default(TInput);
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  if mWas then
  begin
    if Assigned(FStatus) then
    begin
      FStatus('', '');
    end;
    Invalidate;
  end;
end;

class procedure TAtlasIdeMultiCursor.EditorModified(const AView: IOTAEditView);
begin
  if (FInstance = nil) or not FInstance.IsActive or FInstance.FState.Writing or
    not FInstance.FState.Shows(AView) then
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
          if (FInstance <> nil) and FInstance.IsActive and (FInstance.FState.View <> nil) then
          begin
            FInstance.FState.Reconcile(TAtlasEditorBuffer.Text(FInstance.FState.View.Buffer));
            FInstance.Refresh;
          end;
        end);
    end);
end;

class procedure TAtlasIdeMultiCursor.Dismiss;
begin
  if FInstance <> nil then
  begin
    FInstance.Finish;
  end;
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
    Result := FInstance.FState.Next;
  end;
end;

class function TAtlasIdeMultiCursor.TryLineEnds: Boolean;
begin
  Result := (FInstance <> nil) and Enabled and not FInstance.IsBusy and FInstance.FState.LineEnds;
end;

class function TAtlasIdeMultiCursor.TryVertical(AUp: Boolean): Boolean;
begin
  Result := (FInstance <> nil) and Enabled and not FInstance.IsBusy and FInstance.FState.Vertical(AUp);
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
  mLine, mColumn: Integer;
begin
  if not IsEditorWindow(AMsg.hwnd) then
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
  if ClickedAt(AMsg, mFileName, mLine, mColumn) then
  begin
    AHandled := FState.Toggle(mFileName, mLine, mColumn);
  end;
end;

procedure TAtlasIdeMultiCursor.KeyDown(const AMsg: TMsg; var AHandled: Boolean);
var
  mKey: Word;
  mShift: TShiftState;
  mSettings: TAtlasPluginSettings;
  mCommand: TKeyCommand;
begin
  mKey := Word(AMsg.wParam);
  if not IsEditorWindow(AMsg.hwnd) or IsBusy or (mKey = VK_SHIFT) or (mKey = VK_CONTROL) or (mKey = VK_MENU) then
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
  mCommand := Default(TKeyCommand);
  mCommand.Action := ChordAction(FInput.Chord, mKey, mShift, mSettings.MultiCursorSkipKey);
  if mCommand.Action = TKeyAction.None then
  begin
    mCommand := KeyCommand(mKey, mShift);
  end;
  AHandled := Perform(Self, mCommand);
end;

procedure TAtlasIdeMultiCursor.CharTyped(const AMsg: TMsg; var AHandled: Boolean);
var
  mTyped: Char;
  mText: string;
begin
  mTyped := Char(AMsg.wParam);
  // Steuerzeichen (Strg+Buchstabe, Rücktaste, Enter, Tab) nicht: Tab übernimmt die IDE, Mirror zieht nach.
  if not IsEditorWindow(AMsg.hwnd) or IsBusy or (mTyped < ' ') or (mTyped = #127) then
  begin
    Exit;
  end;
  AHandled := True;
  if not Compose(FInput.HighSurrogate, mTyped, mText) then
  begin
    Exit;
  end;
  // Öffnendes Zeichen bei Markierungen: umschließen (#672) statt überschreiben.
  if (Length(mText) > 1) or not FState.DoWrap(mTyped) then
  begin
    FState.DoEdit(TAtlasCaretEditKind.Insert, mText);
  end;
end;

function TAtlasIdeMultiCursor.Follow: Boolean;
var
  mView: IOTAEditView;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  Result := FState.Shows(mView) and Enabled and not FormShown and
    not (FWasModified and not mView.Buffer.IsModified);
  if not Result then
  begin
    Exit;
  end;
  FWasModified := mView.Buffer.IsModified;
  // Cursor der IDE ohne Atlas bewegt (Bild auf/ab, Suchen): Hauptmarke nachziehen.
  FState.SyncMain;
  Result := IsActive;
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
begin
  if not FState.ShowsFile(AContext.FileName) or (AContext.LineState = nil) then
  begin
    Exit;
  end;
  mRun.Line := AContext.LogicalLineNum - 1;
  mRun.Text := FState.LineText(mRun.Line);
  // Nur, wenn die Zeile im Editor dem bekannten Stand entspricht (sonst steht gleich ein Reconcile an).
  if TrimRight(AContext.LineState.Text) <> TrimRight(mRun.Text) then
  begin
    Exit;
  end;
  mRun.Context := AContext;
  mRun.Rect := ARect;
  mRun.TabWidth := TAtlasEditorBuffer.TabWidth(FState.View.Buffer);
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
    for mIndex := 1 to FState.Count - 1 do
    begin
      PaintCaret(mRun, FState.Carets[mIndex], FBlink);
    end;
  finally
    DeleteObject(mRun.Brush);
    RestoreDC(mRun.DC, mSaved);
  end;
end;

end.
