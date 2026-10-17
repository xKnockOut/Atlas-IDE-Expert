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
  Atlas.Core.Editor.MultiCursor;

type
  /// <summary>Statusfeld setzen; AText '' entfernt es.</summary>
  TAtlasMultiCursorStatusProc = reference to procedure(const AText, AHint: string);

  TAtlasIdeMultiCursor = class
  private const
    /// <summary>So viele eigene Schritte merkt sich Atlas für Rückgängig und Wiederholen.</summary>
    StepLimit = 20;
    /// <summary>Deckkraft der Markierungen über dem Text (0–255).</summary>
    SelectionAlpha = 70;
    /// <summary>Breite der gezeichneten Marken in Pixeln.</summary>
    CaretWidth = 2;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;

    /// <summary>Ein eigener Schritt: Text und Marken davor und danach.</summary>
    TStep = record
      Before: string;
      After: string;
      BeforeCarets: TAtlasCarets;
      AfterCarets: TAtlasCarets;
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
    // Aktiver Zustand: Ansicht, Pufferinhalt nach dem letzten bekannten Stand, Marken ([0] = Hauptmarke).
    FView: IOTAEditView;
    FText: string;
    FLines: TArray<string>;
    FCarets: TAtlasCarets;
    FWasModified: Boolean;
    FChord: Boolean;
    FWriting: Boolean;
    FHighSurrogate: Char;
    FSteps: TArray<TStep>;
    FStep: Integer;
    function IsBusy: Boolean;
    function IsActive: Boolean;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure MouseDown(const Msg: TMsg; var Handled: Boolean);
    procedure KeyDown(const Msg: TMsg; var Handled: Boolean);
    procedure CharTyped(const Msg: TMsg; var Handled: Boolean);
    procedure TimerTick(Sender: TObject);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    /// <summary>Aktive Ansicht, ihr Text und die Marken mit der Hauptmarke aus der IDE; False ohne Ansicht oder
    /// bei schreibgeschütztem Puffer.</summary>
    function Prepare(out AView: IOTAEditView; out AText: string): Boolean;
    /// <summary>Marken an eine Änderung durch andere anpassen (Rückgängig, Mirror, Shift).</summary>
    procedure Reconcile(const AText: string);
    procedure Apply(const AView: IOTAEditView; const AText, ANewText: string; const ACarets: TAtlasCarets);
    procedure SetCarets(const AView: IOTAEditView; const AText: string; const ACarets: TAtlasCarets);
    procedure WriteBuffer(const ABuffer: IOTAEditBuffer; const AText, ANewText: string);
    procedure AddStep(const ABefore, AAfter: string; const ABeforeCarets, AAfterCarets: TAtlasCarets);
    procedure SetText(const AText: string);
    /// <summary>Hauptmarke aus der IDE übernehmen, wenn sich der Text nicht geändert hat.</summary>
    procedure SyncMain;
    procedure Refresh;
    procedure Finish;
    procedure DoEdit(AKind: TAtlasCaretEditKind; const AInsert: string);
    procedure DoMove(AMove: TAtlasCaretMove; AExtend: Boolean);
    function DoCopy: Boolean;
    procedure DoCut;
    procedure DoPaste;
    procedure DoSkip;
    function Next: Boolean;
    function LineEnds: Boolean;
    function Vertical(AUp: Boolean): Boolean;
    /// <summary>Hauptmarke aus Cursor und Markierung der IDE.</summary>
    class function ReadMain(const AView: IOTAEditView): TAtlasCaret; static;
    /// <summary>Cursor und Markierung der IDE auf ACaret setzen.</summary>
    class procedure WriteMain(const AView: IOTAEditView; const ALines: TArray<string>; const ACaret: TAtlasCaret);
      static;
    /// <summary>Zeile ALine (0-basiert) in den sichtbaren Bereich holen, ohne den Cursor zu bewegen.</summary>
    class procedure EnsureVisible(const AView: IOTAEditView; ALine: Integer); static;
    class procedure Invalidate; static;
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
  Vcl.Clipbrd,
  Vcl.Menus,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.LineMove,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle;

const
  // Fehlt in älteren Fassungen von Winapi.Windows.
  SpiGetClientAreaAnimation = $1042;

function CurrentShift: TShiftState;
begin
  Result := [];
  if GetKeyState(VK_SHIFT) < 0 then
    Include(Result, ssShift);
  if GetKeyState(VK_CONTROL) < 0 then
    Include(Result, ssCtrl);
  if GetKeyState(VK_MENU) < 0 then
    Include(Result, ssAlt);
end;

function IsEditorWindow(AWnd: HWND): Boolean;
var
  Control: TWinControl;
begin
  Control := FindControl(AWnd);
  Result := (Control <> nil) and Control.ClassNameIs('TEditControl');
end;

/// <summary>Blinkt der Caret laut Windows (Animationen an)?</summary>
function Blinking: Boolean;
var
  Animate: BOOL;
begin
  Animate := True;
  if not SystemParametersInfo(SpiGetClientAreaAnimation, 0, @Animate, 0) then
    Animate := True;
  Result := Animate;
end;

/// <summary>ARect halb durchsichtig mit AColor überziehen; der Text bleibt lesbar.</summary>
procedure Blend(ADC: HDC; const ARect: TRect; AColor: COLORREF);
var
  Memory: HDC;
  Bitmap, Old: HBITMAP;
  Func: TBlendFunction;
begin
  if (ARect.Right <= ARect.Left) or (ARect.Bottom <= ARect.Top) then
    Exit;
  Memory := CreateCompatibleDC(ADC);
  Bitmap := CreateCompatibleBitmap(ADC, 1, 1);
  Old := SelectObject(Memory, Bitmap);
  try
    SetPixel(Memory, 0, 0, AColor);
    Func.BlendOp := AC_SRC_OVER;
    Func.BlendFlags := 0;
    Func.SourceConstantAlpha := TAtlasIdeMultiCursor.SelectionAlpha;
    Func.AlphaFormat := 0;
    AlphaBlend(ADC, ARect.Left, ARect.Top, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top, Memory, 0, 0, 1, 1,
      Func);
  finally
    SelectObject(Memory, Old);
    DeleteObject(Bitmap);
    DeleteDC(Memory);
  end;
end;

function LineOf(const ALines: TArray<string>; ALine: Integer): string;
begin
  Result := '';
  if (ALine >= 0) and (ALine < Length(ALines)) then
    Result := ALines[ALine];
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
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FBusy := ABusy;
  FStatus := AStatus;
  FIndex := -1;
  FMessages := TApplicationEvents.Create(nil);
  FMessages.OnMessage := AppMessage;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := Max(200, Integer(GetCaretBlinkTime));
  FTimer.OnTimer := TimerTick;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TAtlasIdeMultiCursor.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  FreeAndNil(FMessages);
  FreeAndNil(FTimer);
  if Assigned(FStatus) and IsActive then
    FStatus('', '');
  FView := nil;
  FCarets := nil;
  FSteps := nil;
  inherited;
end;

class procedure TAtlasIdeMultiCursor.Install(const ABusy: TFunc<Boolean>; const AStatus: TAtlasMultiCursorStatusProc);
begin
  if FInstance = nil then
    FInstance := TAtlasIdeMultiCursor.Create(ABusy, AStatus);
end;

class procedure TAtlasIdeMultiCursor.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeMultiCursor.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.MultiCursor;
end;

class function TAtlasIdeMultiCursor.Active: Boolean;
begin
  Result := (FInstance <> nil) and FInstance.IsActive;
end;

function TAtlasIdeMultiCursor.IsActive: Boolean;
begin
  Result := Length(FCarets) > 1;
end;

function TAtlasIdeMultiCursor.IsBusy: Boolean;
begin
  Result := Assigned(FBusy) and FBusy();
end;

class procedure TAtlasIdeMultiCursor.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.InvalidateTopEditor;
end;

class function TAtlasIdeMultiCursor.ReadMain(const AView: IOTAEditView): TAtlasCaret;
var
  Cursor: TOTAEditPos;
  Block: IOTAEditBlock;
  TabWidth, Line, Character, StartLine, StartCharacter, EndLine, EndCharacter: Integer;
  LineText: string;
begin
  TabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  Cursor := AView.CursorPos;
  Line := Max(0, Cursor.Line - 1);
  LineText := TAtlasEditorBuffer.LineText(AView, Line + 1);
  Character := Min(TLspSession.ColumnToIndex(LineText, Cursor.Col, TabWidth), Length(LineText));
  Result := TAtlasCaret.At(Line, Character);
  Block := AView.Block;
  if (Block = nil) or not Block.IsValid or (Block.Size = 0) then
    Exit;
  StartLine := Block.StartingRow - 1;
  StartCharacter := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(AView, StartLine + 1),
    Block.StartingColumn, TabWidth);
  EndLine := Block.EndingRow - 1;
  EndCharacter := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(AView, EndLine + 1), Block.EndingColumn,
    TabWidth);
  // Der Anker ist das Ende, an dem der Cursor nicht steht.
  if (Line = StartLine) and (Character = StartCharacter) then
    Result := TAtlasCaret.Range(EndLine, EndCharacter, StartLine, StartCharacter)
  else
    Result := TAtlasCaret.Range(StartLine, StartCharacter, EndLine, EndCharacter);
end;

class procedure TAtlasIdeMultiCursor.WriteMain(const AView: IOTAEditView; const ALines: TArray<string>;
  const ACaret: TAtlasCaret);
var
  TabWidth: Integer;
  Position: TOTAEditPos;
begin
  TabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  if ACaret.HasSelection then
  begin
    AView.Block.Style := btNonInclusive;
    Position.Line := ACaret.AnchorLine + 1;
    Position.Col := TLspSession.IndexToColumn(LineOf(ALines, ACaret.AnchorLine), ACaret.AnchorCharacter, TabWidth);
    AView.CursorPos := Position;
    AView.Block.BeginBlock;
    Position.Line := ACaret.Line + 1;
    Position.Col := TLspSession.IndexToColumn(LineOf(ALines, ACaret.Line), ACaret.Character, TabWidth);
    AView.CursorPos := Position;
    AView.Block.EndBlock;
  end
  else
  begin
    AView.Block.Reset;
    Position.Line := ACaret.Line + 1;
    Position.Col := TLspSession.IndexToColumn(LineOf(ALines, ACaret.Line), ACaret.Character, TabWidth);
    AView.CursorPos := Position;
  end;
  AView.MoveViewToCursor;
end;

class procedure TAtlasIdeMultiCursor.EnsureVisible(const AView: IOTAEditView; ALine: Integer);
var
  Rows: Integer;
begin
  Rows := Max(1, AView.ViewSize.cy);
  if (ALine + 1 >= AView.TopRow) and (ALine + 1 < AView.TopRow + Rows) then
    Exit;
  AView.SetTopLeft(Max(1, ALine + 1 - Rows div 2), AView.LeftColumn);
end;

function TAtlasIdeMultiCursor.Prepare(out AView: IOTAEditView; out AText: string): Boolean;
var
  Main: TAtlasCaret;
begin
  Result := False;
  AText := '';
  AView := TAtlasEditorBuffer.ActiveView;
  if (AView = nil) or (AView.Buffer = nil) or AView.Buffer.IsReadOnly then
    Exit;
  if IsActive and ((FView = nil) or not SameText(FView.Buffer.FileName, AView.Buffer.FileName)) then
    Finish;
  AText := TAtlasEditorBuffer.Text(AView.Buffer);
  // Eine Änderung, deren Meldung noch aussteht, zuerst nachziehen.
  if IsActive and (AText <> FText) then
  begin
    Reconcile(AText);
    AText := FText;
  end;
  Main := ReadMain(AView);
  if IsActive then
  begin
    FCarets[0] := Main;
    FCarets := TAtlasMultiCursor.Merge(FCarets);
  end
  else
  begin
    FCarets := [Main];
    FView := AView;
    SetText(AText);
  end;
  Result := True;
end;

procedure TAtlasIdeMultiCursor.WriteBuffer(const ABuffer: IOTAEditBuffer; const AText, ANewText: string);
var
  Writer: IOTAEditWriter;
  Start, OldLength: Integer;
  Insert: string;
begin
  if not TAtlasLineMover.Difference(AText, ANewText, Start, OldLength, Insert) then
    Exit;
  FWriting := True;
  try
    // Ein Schreiber: ein Rückgängig-Schritt für alle Marken.
    Writer := ABuffer.CreateUndoableWriter;
    Writer.CopyTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, Start)));
    Writer.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, Start + OldLength)));
    if Insert <> '' then
      Writer.Insert(PAnsiChar(UTF8Encode(Insert)));
    Writer := nil;
  finally
    FWriting := False;
  end;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

procedure TAtlasIdeMultiCursor.AddStep(const ABefore, AAfter: string; const ABeforeCarets,
  AAfterCarets: TAtlasCarets);
var
  Step: TStep;
begin
  // Ein neuer Schritt verwirft, was nach dem aktuellen wiederholt werden könnte.
  SetLength(FSteps, FStep);
  Step.Before := ABefore;
  Step.After := AAfter;
  Step.BeforeCarets := Copy(ABeforeCarets);
  Step.AfterCarets := Copy(AAfterCarets);
  FSteps := FSteps + [Step];
  if Length(FSteps) > StepLimit then
    Delete(FSteps, 0, 1);
  FStep := Length(FSteps);
end;

procedure TAtlasIdeMultiCursor.Apply(const AView: IOTAEditView; const AText, ANewText: string;
  const ACarets: TAtlasCarets);
begin
  WriteBuffer(AView.Buffer, AText, ANewText);
  AddStep(AText, ANewText, FCarets, ACarets);
  SetCarets(AView, ANewText, ACarets);
end;

procedure TAtlasIdeMultiCursor.SetCarets(const AView: IOTAEditView; const AText: string;
  const ACarets: TAtlasCarets);
begin
  FCarets := Copy(ACarets);
  FView := AView;
  SetText(AText);
  if Length(FCarets) > 0 then
    WriteMain(AView, FLines, FCarets[0]);
  Refresh;
end;

procedure TAtlasIdeMultiCursor.SetText(const AText: string);
begin
  FText := AText;
  FLines := TAtlasMultiCursor.Lines(AText);
end;

procedure TAtlasIdeMultiCursor.SyncMain;
begin
  if not IsActive or (FView = nil) or (FView.Buffer = nil) then
    Exit;
  FCarets[0] := ReadMain(FView);
  FCarets := TAtlasMultiCursor.Merge(FCarets);
end;

procedure TAtlasIdeMultiCursor.Refresh;
begin
  if not IsActive then
  begin
    Finish;
    Exit;
  end;
  FWasModified := FView.Buffer.IsModified;
  if Assigned(FStatus) then
    FStatus(TAtlasStrings.Fmt(TAtlasTextId.MultiCursorStatus, [Length(FCarets)]),
      TAtlasStrings.Text(TAtlasTextId.MultiCursorStatusHint));
  // Nach jedem Schritt sichtbar, dann wieder im Takt.
  FBlink := True;
  FTimer.Enabled := False;
  FTimer.Enabled := True;
  Invalidate;
end;

procedure TAtlasIdeMultiCursor.Finish;
var
  Was: Boolean;
begin
  Was := IsActive;
  FCarets := nil;
  FSteps := nil;
  FStep := 0;
  FChord := False;
  FHighSurrogate := #0;
  FView := nil;
  FText := '';
  FLines := nil;
  if FTimer <> nil then
    FTimer.Enabled := False;
  if Was then
  begin
    if Assigned(FStatus) then
      FStatus('', '');
    Invalidate;
  end;
end;

procedure TAtlasIdeMultiCursor.Reconcile(const AText: string);
var
  Mirrored: string;
  Carets: TAtlasCarets;
begin
  if not IsActive or (AText = FText) then
    Exit;
  // Rückgängig bzw. Wiederholen eines eigenen Schritts: dessen Marken.
  if (FStep > 0) and (AText = FSteps[FStep - 1].Before) then
  begin
    FCarets := Copy(FSteps[FStep - 1].BeforeCarets);
    Dec(FStep);
    SetText(AText);
    Exit;
  end;
  if (FStep < Length(FSteps)) and (AText = FSteps[FStep].After) then
  begin
    FCarets := Copy(FSteps[FStep].AfterCarets);
    Inc(FStep);
    SetText(AText);
    Exit;
  end;
  // Fremde Änderung: an der Hauptmarke an allen Marken ausführen, sonst die Marken verschieben.
  FSteps := nil;
  FStep := 0;
  if TAtlasMultiCursor.Mirror(FText, AText, FCarets, Mirrored, Carets) then
  begin
    WriteBuffer(FView.Buffer, AText, Mirrored);
    SetText(Mirrored);
    FCarets := Carets;
    WriteMain(FView, FLines, FCarets[0]);
  end
  else
  begin
    FCarets := TAtlasMultiCursor.Shift(FText, AText, FCarets);
    SetText(AText);
  end;
end;

class procedure TAtlasIdeMultiCursor.EditorModified(const AView: IOTAEditView);
begin
  if (FInstance = nil) or not FInstance.IsActive or FInstance.FWriting or (AView = nil) or
    (AView.Buffer = nil) or (FInstance.FView = nil) or
    not SameText(AView.Buffer.FileName, FInstance.FView.Buffer.FileName) then
    Exit;
  // Nie im Notifier schreiben: nach der Änderung, in der Warteschlange des Hauptthreads.
  TAtlasMainThread.ForceQueue(TAtlasFeature.EditorCommands,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.EditorCommands,
        procedure
        begin
          if (FInstance <> nil) and FInstance.IsActive and (FInstance.FView <> nil) then
          begin
            FInstance.Reconcile(TAtlasEditorBuffer.Text(FInstance.FView.Buffer));
            FInstance.Refresh;
          end;
        end);
    end);
end;

class procedure TAtlasIdeMultiCursor.Dismiss;
begin
  if FInstance <> nil then
    FInstance.Finish;
end;

procedure TAtlasIdeMultiCursor.DoEdit(AKind: TAtlasCaretEditKind; const AInsert: string);
var
  View: IOTAEditView;
  Text, NewText: string;
  Carets: TAtlasCarets;
begin
  if not Prepare(View, Text) then
    Exit;
  if TAtlasMultiCursor.Edit(Text, FCarets, AKind, AInsert, NewText, Carets) then
    Apply(View, Text, NewText, Carets);
end;

procedure TAtlasIdeMultiCursor.DoMove(AMove: TAtlasCaretMove; AExtend: Boolean);
var
  View: IOTAEditView;
  Text: string;
begin
  if not Prepare(View, Text) then
    Exit;
  SetCarets(View, Text, TAtlasMultiCursor.Move(FLines, FCarets, AMove, AExtend,
    TAtlasEditorBuffer.TabWidth(View.Buffer)));
end;

function TAtlasIdeMultiCursor.DoCopy: Boolean;
var
  View: IOTAEditView;
  Text, Selected: string;
begin
  Result := False;
  if not Prepare(View, Text) then
    Exit;
  Selected := TAtlasMultiCursor.SelectedText(Text, FCarets, TAtlasMultiCursor.LineBreakOf(Text));
  // Ohne Markierung bleibt Kopieren der IDE.
  if Selected = '' then
    Exit;
  Clipboard.AsText := Selected;
  Result := True;
end;

procedure TAtlasIdeMultiCursor.DoCut;
begin
  if DoCopy then
    DoEdit(TAtlasCaretEditKind.Insert, '');
end;

procedure TAtlasIdeMultiCursor.DoPaste;
var
  View: IOTAEditView;
  Text, NewText, Clip: string;
  Carets: TAtlasCarets;
begin
  if not Clipboard.HasFormat(CF_UNICODETEXT) and not Clipboard.HasFormat(CF_TEXT) then
    Exit;
  Clip := Clipboard.AsText;
  if (Clip = '') or not Prepare(View, Text) then
    Exit;
  if TAtlasMultiCursor.Paste(Text, FCarets, Clip, NewText, Carets) then
    Apply(View, Text, NewText, Carets);
end;

procedure TAtlasIdeMultiCursor.DoSkip;
var
  View: IOTAEditView;
  Text: string;
  Carets: TAtlasCarets;
begin
  if not Prepare(View, Text) then
    Exit;
  if TAtlasMultiCursor.SkipOccurrence(FLines, FCarets, False, False, Carets) then
  begin
    SetCarets(View, Text, Carets);
    if Length(Carets) > 0 then
      EnsureVisible(View, Carets[High(Carets)].Line);
  end;
end;

function TAtlasIdeMultiCursor.Next: Boolean;
var
  View: IOTAEditView;
  Text: string;
  Carets: TAtlasCarets;
  Was: Boolean;
begin
  Result := False;
  // Platzhalter-Modus oder SyncEdit-ähnliche Zustände: Strg+D wirkungslos (die Taste bleibt bei Atlas).
  if IsBusy then
    Exit(IsActive);
  Was := IsActive;
  if not Prepare(View, Text) then
    Exit;
  case TAtlasMultiCursor.NextOccurrence(FLines, FCarets, False, False, Carets) of
    TAtlasOccurrence.WordSelected:
      begin
        WriteMain(View, FLines, Carets[0]);
        FCarets := Carets;
        View.Paint;
        Result := True;
      end;
    TAtlasOccurrence.Added:
      begin
        SetCarets(View, Text, Carets);
        EnsureVisible(View, Carets[High(Carets)].Line);
        Result := True;
      end;
  else
    // Kein Wort am Cursor: ohne Marken bekommt die IDE die Taste (Quelltext formatieren).
    Result := Was;
    if not Was then
      FCarets := nil;
  end;
end;

function TAtlasIdeMultiCursor.LineEnds: Boolean;
var
  View: IOTAEditView;
  Text: string;
begin
  Result := False;
  if IsBusy or not Prepare(View, Text) or not FCarets[0].HasSelection then
    Exit;
  SetCarets(View, Text, TAtlasMultiCursor.LineEnds(FLines, FCarets[0]));
  View.Paint;
  Result := True;
end;

function TAtlasIdeMultiCursor.Vertical(AUp: Boolean): Boolean;
var
  View: IOTAEditView;
  Text: string;
  Carets: TAtlasCarets;
begin
  Result := False;
  if IsBusy or not Prepare(View, Text) then
    Exit;
  if not TAtlasMultiCursor.AddVertical(FLines, FCarets, AUp,
    TAtlasEditorBuffer.TabWidth(View.Buffer), Carets) then
    Exit;
  SetCarets(View, Text, Carets);
  EnsureVisible(View, Carets[High(Carets)].Line);
  Result := True;
end;

class function TAtlasIdeMultiCursor.TryNext: Boolean;
begin
  Result := (FInstance <> nil) and Enabled and FInstance.Next;
end;

class function TAtlasIdeMultiCursor.TryLineEnds: Boolean;
begin
  Result := (FInstance <> nil) and Enabled and FInstance.LineEnds;
end;

class function TAtlasIdeMultiCursor.TryVertical(AUp: Boolean): Boolean;
begin
  Result := (FInstance <> nil) and Enabled and FInstance.Vertical(AUp);
end;

procedure TAtlasIdeMultiCursor.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.EditorCommands) then
    Exit;
  try
    case Msg.message of
      WM_LBUTTONDOWN:
        MouseDown(Msg, Handled);
      WM_KEYDOWN, WM_SYSKEYDOWN:
        if IsActive then
          KeyDown(Msg, Handled);
      WM_CHAR:
        if IsActive then
          CharTyped(Msg, Handled);
    end;
  except
    // Keine Exception an die IDE (#493); die Nachricht geht dann normal weiter.
    on E: Exception do
    begin
      Handled := False;
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
    end;
  end;
end;

procedure TAtlasIdeMultiCursor.MouseDown(const Msg: TMsg; var Handled: Boolean);
var
  Settings: TAtlasPluginSettings;
  Services: INTACodeEditorServices;
  State: INTACodeEditorState;
  Control: TWinControl;
  View: IOTAEditView;
  Text, LineText: string;
  Shift: TShiftState;
  Wanted: TShiftState;
  Column, VisibleLine, Line, Character: Integer;
begin
  if not IsEditorWindow(Msg.hwnd) then
    Exit;
  Settings := TAtlasIdeSettings.Current;
  Wanted := [ssAlt];
  if Settings.MultiCursorModifier = TAtlasPluginSettings.MultiCursorModifierCtrl then
    Wanted := [ssCtrl];
  Shift := CurrentShift;
  if (Shift <> Wanted) or not Settings.Enabled or not Settings.MultiCursor or IsBusy then
  begin
    // Ein einfacher Klick beendet die Zusatzmarken; der Klick selbst gehört der IDE.
    if IsActive and (Shift = []) then
      Finish;
    Exit;
  end;
  Control := FindControl(Msg.hwnd);
  if not Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Exit;
  State := Services.EditorState[Control];
  if (State = nil) or not State.PointToCharacterPos(Point(SmallInt(LoWord(Cardinal(Msg.lParam))),
    SmallInt(HiWord(Cardinal(Msg.lParam)))), Column, VisibleLine) then
    Exit;
  Line := State.LineState[VisibleLine].LogicalLineNum - 1;
  if (Line < 0) or not Prepare(View, Text) or (State.View = nil) or (State.View.Buffer = nil) or
    not SameText(State.View.Buffer.FileName, View.Buffer.FileName) then
    Exit;
  LineText := LineOf(FLines, Line);
  Character := Min(TLspSession.ColumnToIndex(LineText, Column, TAtlasEditorBuffer.TabWidth(View.Buffer)),
    Length(LineText));
  SetCarets(View, Text, TAtlasMultiCursor.Toggle(FCarets, Line, Character));
  View.Paint;
  Handled := True;
end;

procedure TAtlasIdeMultiCursor.KeyDown(const Msg: TMsg; var Handled: Boolean);
var
  Key: Word;
  Shift, Plain: TShiftState;
  Settings: TAtlasPluginSettings;
begin
  if not IsEditorWindow(Msg.hwnd) or IsBusy then
    Exit;
  Key := Word(Msg.wParam);
  if (Key = VK_SHIFT) or (Key = VK_CONTROL) or (Key = VK_MENU) then
    Exit;
  Shift := CurrentShift;
  Plain := Shift - [ssShift];
  Settings := TAtlasIdeSettings.Current;
  if not Settings.Enabled or not Settings.MultiCursor then
  begin
    Finish;
    Exit;
  end;
  // Strg+K, dann die Taste fürs Überspringen; jede andere Taste danach wirkt normal.
  if FChord then
  begin
    FChord := False;
    if (Settings.MultiCursorSkipKey <> 0) and (ShortCut(Key, Shift) = TShortCut(Settings.MultiCursorSkipKey)) then
    begin
      DoSkip;
      Handled := True;
      Exit;
    end;
  end;
  if (Key = Ord('K')) and (Shift = [ssCtrl]) and (Settings.MultiCursorSkipKey <> 0) then
  begin
    FChord := True;
    Handled := True;
    Exit;
  end;
  Handled := True;
  case Key of
    VK_ESCAPE:
      if Shift = [] then
        Finish
      else
        Handled := False;
    VK_BACK:
      if Plain = [] then
        DoEdit(TAtlasCaretEditKind.Backspace, '')
      else
        Handled := False;
    VK_DELETE:
      if Shift = [] then
        DoEdit(TAtlasCaretEditKind.Delete, '')
      else if Shift = [ssShift] then
        DoCut
      else
        Handled := False;
    VK_RETURN:
      if Plain = [] then
        DoEdit(TAtlasCaretEditKind.NewLine, '')
      else
        Handled := False;
    VK_LEFT:
      if Plain = [] then
        DoMove(TAtlasCaretMove.Left, ssShift in Shift)
      else if Plain = [ssCtrl] then
        DoMove(TAtlasCaretMove.WordLeft, ssShift in Shift)
      else
        Handled := False;
    VK_RIGHT:
      if Plain = [] then
        DoMove(TAtlasCaretMove.Right, ssShift in Shift)
      else if Plain = [ssCtrl] then
        DoMove(TAtlasCaretMove.WordRight, ssShift in Shift)
      else
        Handled := False;
    VK_UP:
      if Plain = [] then
        DoMove(TAtlasCaretMove.Up, ssShift in Shift)
      else
        Handled := False;
    VK_DOWN:
      if Plain = [] then
        DoMove(TAtlasCaretMove.Down, ssShift in Shift)
      else
        Handled := False;
    VK_HOME:
      if Plain = [] then
        DoMove(TAtlasCaretMove.LineStart, ssShift in Shift)
      else
        Handled := False;
    VK_END:
      if Plain = [] then
        DoMove(TAtlasCaretMove.LineEnd, ssShift in Shift)
      else
        Handled := False;
    VK_INSERT:
      if Shift = [ssCtrl] then
        Handled := DoCopy
      else if Shift = [ssShift] then
        DoPaste
      else
        Handled := False;
  else
    if (Key = Ord('C')) and (Shift = [ssCtrl]) then
      Handled := DoCopy
    else if (Key = Ord('X')) and (Shift = [ssCtrl]) then
      DoCut
    else if (Key = Ord('V')) and (Shift = [ssCtrl]) then
      DoPaste
    else
      Handled := False;
  end;
end;

procedure TAtlasIdeMultiCursor.CharTyped(const Msg: TMsg; var Handled: Boolean);
var
  Typed: Char;
begin
  if not IsEditorWindow(Msg.hwnd) or IsBusy then
    Exit;
  Typed := Char(Msg.wParam);
  // Steuerzeichen (Strg+Buchstabe, Rücktaste, Enter, Tab) nicht: Tab übernimmt die IDE, Mirror zieht nach.
  if (Typed < ' ') or (Typed = #127) then
    Exit;
  Handled := True;
  // Zeichen außerhalb der Grundebene kommen als zwei WM_CHAR.
  if (Typed >= #$D800) and (Typed <= #$DBFF) then
  begin
    FHighSurrogate := Typed;
    Exit;
  end;
  if (FHighSurrogate <> #0) and (Typed >= #$DC00) and (Typed <= #$DFFF) then
  begin
    DoEdit(TAtlasCaretEditKind.Insert, FHighSurrogate + Typed);
    FHighSurrogate := #0;
    Exit;
  end;
  FHighSurrogate := #0;
  DoEdit(TAtlasCaretEditKind.Insert, Typed);
end;

procedure TAtlasIdeMultiCursor.TimerTick(Sender: TObject);
var
  View: IOTAEditView;
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Form: IOTAFormEditor;
begin
  try
    if not IsActive then
    begin
      FTimer.Enabled := False;
      Exit;
    end;
    View := TAtlasEditorBuffer.ActiveView;
    // Datei gewechselt, Formular angezeigt, gespeichert oder abgeschaltet: Zusatzmarken weg.
    if (View = nil) or (View.Buffer = nil) or (FView = nil) or
      not SameText(View.Buffer.FileName, FView.Buffer.FileName) or not Enabled then
    begin
      Finish;
      Exit;
    end;
    if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    begin
      Module := Modules.CurrentModule;
      if (Module <> nil) and Supports(Module.CurrentEditor, IOTAFormEditor, Form) then
      begin
        Finish;
        Exit;
      end;
    end;
    if FWasModified and not View.Buffer.IsModified then
    begin
      Finish;
      Exit;
    end;
    FWasModified := View.Buffer.IsModified;
    // Cursor der IDE ohne Atlas bewegt (Bild auf/ab, Suchen): Hauptmarke nachziehen.
    SyncMain;
    if not IsActive then
    begin
      Finish;
      Exit;
    end;
    FBlink := not FBlink or not Blinking;
    Invalidate;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

procedure TAtlasIdeMultiCursor.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  LineState: INTACodeEditorLineState;
  Caret: TAtlasCaret;
  Text: string;
  Line, Index, TabWidth, StartLine, StartCharacter, EndLine, EndCharacter, From, Till: Integer;
  Color: COLORREF;
  DC: HDC;
  Saved: Integer;
  First, Last, Code, Area: TRect;
  Brush: HBRUSH;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not IsActive or
    TAtlasGuard.Disabled(TAtlasFeature.EditorCommands) then
    Exit;
  try
    if (FView = nil) or not SameText(Context.FileName, FView.Buffer.FileName) then
      Exit;
    LineState := Context.LineState;
    if LineState = nil then
      Exit;
    Line := Context.LogicalLineNum - 1;
    Text := LineOf(FLines, Line);
    // Nur, wenn die Zeile im Editor dem bekannten Stand entspricht (sonst steht gleich ein Reconcile an).
    if TrimRight(LineState.Text) <> TrimRight(Text) then
      Exit;
    TabWidth := TAtlasEditorBuffer.TabWidth(FView.Buffer);
    Color := COLORREF(ColorToRGB(TColor(TAtlasIdeStyle.Colors.Accent)));
    DC := Context.Canvas.Handle;
    Code := LineState.CodeRect;
    Saved := SaveDC(DC);
    Brush := CreateSolidBrush(Color);
    try
      if Code.Right > Code.Left then
        IntersectClipRect(DC, Code.Left, Rect.Top, Rect.Right, Rect.Bottom);
      // Die Hauptmarke zeichnet die IDE.
      for Index := 1 to High(FCarets) do
      begin
        Caret := FCarets[Index];
        if Caret.HasSelection then
        begin
          Caret.Bounds(StartLine, StartCharacter, EndLine, EndCharacter);
          if (Line >= StartLine) and (Line <= EndLine) then
          begin
            From := 0;
            if Line = StartLine then
              From := StartCharacter;
            Till := Length(Text) + 1;
            if Line = EndLine then
              Till := EndCharacter;
            First := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(Text, From, TabWidth),
              Context.EditorLineNum);
            Last := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(Text, Till, TabWidth),
              Context.EditorLineNum);
            Blend(DC, TRect.Create(First.Left, Rect.Top, Max(Last.Left, First.Left + 1), Rect.Bottom), Color);
          end;
        end;
        if (Caret.Line = Line) and FBlink then
        begin
          First := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(Text, Caret.Character, TabWidth),
            Context.EditorLineNum);
          Area := TRect.Create(First.Left, Rect.Top, First.Left + CaretWidth, Rect.Bottom);
          FillRect(DC, Area, Brush);
        end;
      end;
    finally
      DeleteObject(Brush);
      RestoreDC(DC, Saved);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

end.
