unit Atlas.IDE.Signature.Editor;

// Parameter-Hint im Editor der IDE (#436, #437, #440): verbindet die Signaturen
// des Servers, den Ablauf (TAtlasSignatureController) und das Hint-Fenster mit
// dem Editor. Der Code Insight-Manager ruft Invoke bei "(", "," und
// Strg+Umschalt+Leer statt der eingebauten Parameterhilfe.
//   - Start: Aufruf am Caret lokal suchen (TAtlasCallScanner), Signaturen beim
//     Server anfragen, Hint an der öffnenden Klammer zeigen.
//   - Weitertippen: EditorViewModified und ein Zeitgeber zählen den aktiven
//     Parameter lokal neu; der Hint wechselt bei Bedarf die Überladung.
//   - Verschachtelt (#438): Pfadzeile mit den äußeren Aufrufen; verlässt der Caret
//     den inneren Aufruf nach vorn (Klammer davor), zeigt der Hint den äußeren.
//   - Schließen (#414): Caret verlässt den Aufruf (auch durch ")"), Esc,
//     Fokusverlust, IDE inaktiv, Scrollen, Tab-Wechsel.
//   - Wieder öffnen: Wird die schließende Klammer entfernt (Rücktaste, Entf) und
//     steht der Caret danach in einem Aufruf, erscheint der Hint erneut; nicht für
//     einen Aufruf, dessen Hint mit Esc geschlossen wurde. Dazu merkt sich jede
//     Änderung die Zeile vorher.
//   - Alle Überladungen stehen untereinander; Klick wählt eine. Tasten über den
//     gemeinsamen Hook: Esc schließt, Alt+↑/↓ wechselt die gewählte Überladung;
//     nach der Vervollständigung, die Esc zuerst bekommt.
//   - Platzhalter (#451): Bei Format und anderen Formatroutinen zeigt der Hint, welchen Platzhalter der Eintrag
//     am Cursor füllt, und TAtlasIdeFormatMarks färbt Platzhalter und Argumente im Editor. Ändern sich Text oder
//     Cursor, fragt der Zeitgeber nach kurzer Ruhe neu; UpdateFormat übernimmt nur die neue Zuordnung.
//     Abschaltbar mit completion.formatPlaceholders.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Signature.Contract,
  Atlas.Core.Signature.Controller,
  Atlas.UI.Signature.Hint,
  Atlas.Core.Editor.CloseRules,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Signature.FormatMarks;

type
  TAtlasLogFunc = reference to procedure(const AMessage: string);
  /// <summary>Ist das Vervollständigungs-Popup offen? Dann steht der Hint über der Zeile (#440).</summary>
  TAtlasBoolFunc = reference to function: Boolean;

  /// <summary>Zeile vor der letzten Änderung (Wieder öffnen nach entfernter „)“).</summary>
  TAtlasSignatureLastLine = record
    FileName: string;
    Line: Integer;
    Text: string;
  end;

  /// <summary>Mit Esc geschlossener Aufruf.</summary>
  TAtlasSignatureDismissed = record
    FileName: string;
    OpenParen: Integer;
  end;

  /// <summary>Stand der letzten Platzhalter-Anfrage (#451): Text, Cursor und Takte bis zur nächsten.</summary>
  TAtlasSignatureFormatState = record
    Text: string;
    Caret: Integer;
    Due: Integer;
  end;

  TAtlasEditorSignature = class
  private const
    /// <summary>Takte ohne Änderung, bis die Platzhalter neu angefragt werden (#451).</summary>
    FormatQuietTicks = 3;
  private
    FProvider: IAtlasSignatureSource;
    FHint: TAtlasSignatureHint;
    FController: TAtlasSignatureController;
    FTimer: TTimer;
    FKeys: TAtlasKeyClient;
    FLog: TAtlasLogFunc;
    FCompletionOpen: TAtlasBoolFunc;
    FNotifierIndex: Integer;
    // Zustand des offenen Hints.
    FView: IOTAEditView;
    FEditorWindow: HWND;
    FOpenParen: Integer;
    // Fenster beim Öffnen bzw. nach dem letzten Mitwandern; TAtlasCloseRules vergleicht damit (#414).
    FOpened: TAtlasEditorWindowState;
    /// <summary>Zeile (ab 1), an der der Hint hängt: Caret-Zeile beim Öffnen.</summary>
    FAnchorLine: Integer;
    FPending: Boolean;
    FLast: TAtlasSignatureLastLine;
    FDismissed: TAtlasSignatureDismissed;
    // Platzhalter (#451): Färbung und Stand der letzten Anfrage.
    FMarks: TAtlasIdeFormatMarks;
    FFormat: TAtlasSignatureFormatState;
    procedure ShowFormat(const AFormat: TAtlasSignatureFormat; const AText: string);
    procedure CheckFormat(const AText: string; ALine, ACharacter, ACaret: Integer);
    procedure Reopen(const AView: IOTAEditView);
    /// <summary>Antwort des Servers auf die Anfrage aus Invoke; AText: Text zur Zeit der Anfrage.</summary>
    procedure HelpArrived(const AHelp: TAtlasSignatureHelp; const AText: string);
    procedure Log(const AMessage: string);
    procedure TimerTick(Sender: TObject);
    procedure Recheck;
    procedure ApplyStyle(const ACaret: TRect);
    procedure ActiveChanged;
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure HandleKey(AKey: Word);
  private class var
    FPreferredName: string;
    FPreferredIndex: Integer;
  public
    /// <summary>Beim nächsten Hint für AName die Überladung AIndex wählen (aus dem Detailpanel, #425).</summary>
    class procedure PreferOverload(const AName: string; AIndex: Integer); static;
    /// <summary>ASource: Server-Anbieter, eingesetzt von der Kompositionswurzel.</summary>
    constructor Create(const ASource: IAtlasSignatureSource; const ACompletionOpen: TAtlasBoolFunc;
      const ALog: TAtlasLogFunc);
    destructor Destroy; override;
    /// <summary>Öffnet den Hint für den Aufruf am Cursor von AView; False ohne Aufruf.</summary>
    function Invoke(const AView: IOTAEditView): Boolean;
    procedure Close;
    procedure EditorModified(const AView: IOTAEditView);
    /// <summary>Bricht laufende Serveranfragen ab und wartet auf sie; vor dem Freigeben der Sitzung.</summary>
    procedure Shutdown;
    function Active: Boolean;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Client,
  Vcl.Forms,
  DockForm,
  Atlas.Core.Signature.CallScanner,
  Atlas.Core.Signature.Format,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Lsp.Session;

/// <summary>Größe des Editorfensters (Client-Bereich); (0, 0) ohne Fenster.</summary>
function EditorSize(AWindow: HWND): TPoint;
var
  Area: TRect;
begin
  if (AWindow <> 0) and GetClientRect(AWindow, Area) then
  begin
    Result := Point(Area.Width, Area.Height);
  end
  else
  begin
    Result := Point(0, 0);
  end;
end;

/// <summary>Zustand für TAtlasCloseRules (#414).</summary>
function WindowState(const AView: IOTAEditView; AWindow, AFocus: HWND): TAtlasEditorWindowState;
begin
  Result := Default(TAtlasEditorWindowState);
  Result.AppActive := Application.Active;
  Result.Focus := AFocus;
  Result.Size := EditorSize(AWindow);
  if AView = nil then
  begin
    Exit;
  end;
  Result.TopRow := AView.TopRow;
  Result.Rows := AView.ViewSize.cy;
  if AView.Buffer <> nil then
  begin
    Result.FileName := AView.Buffer.FileName;
  end;
end;

type
  /// <summary>Cursor eines Editors: Text, Zeile (ab 1), Zeichen in der Zeile und Offset im Text.</summary>
  TCursorSpot = record
    Text: string;
    Line: Integer;
    Character: Integer;
    Caret: Integer;
  end;

function CursorSpot(const AView: IOTAEditView): TCursorSpot;
var
  mCursor: TOTAEditPos;
begin
  Result.Text := TAtlasEditorBuffer.Text(AView.Buffer);
  mCursor := AView.CursorPos;
  Result.Line := mCursor.Line;
  Result.Character := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(AView, mCursor.Line), mCursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  Result.Caret := TAtlasEditorBuffer.CharOffset(Result.Text, mCursor.Line - 1, Result.Character);
end;

/// <summary>Fenster und Rechteck des Carets (Bildschirmkoordinaten); False ohne Caret.</summary>
function CaretAnchor(out AWindow: HWND; out AAnchor: TRect): Boolean;
var
  mInfo: TGUIThreadInfo;
begin
  FillChar(mInfo, SizeOf(mInfo), 0);
  mInfo.cbSize := SizeOf(mInfo);
  Result := GetGUIThreadInfo(GetCurrentThreadId, mInfo) and (mInfo.hwndCaret <> 0);
  AWindow := mInfo.hwndCaret;
  AAnchor := mInfo.rcCaret;
  if Result then
  begin
    MapWindowPoints(AWindow, 0, AAnchor, 2);
  end;
end;

type
  TSignatureKeys = class(TAtlasKeyClient)
  private
    FOwner: TAtlasEditorSignature;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  public
    constructor Create(AOwner: TAtlasEditorSignature);
  end;

  TSignatureNotifier = class(TNotifierObject, INTAEditServicesNotifier)
  private
    FOwner: TAtlasEditorSignature;
  public
    constructor Create(AOwner: TAtlasEditorSignature);
    procedure WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
    procedure WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
    procedure WindowActivated(const EditWindow: INTAEditWindow);
    procedure WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer; var Handled: Boolean);
    procedure EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
  end;

{ TSignatureKeys }

constructor TSignatureKeys.Create(AOwner: TAtlasEditorSignature);
begin
  // Nach der Vervollständigung (Priorität 0): Esc schließt zuerst deren Popup.
  inherited Create(10);
  FOwner := AOwner;
end;

function TSignatureKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := FOwner.WantsKey(AKey, AShift);
end;

procedure TSignatureKeys.HandleKey(AKey: Word; AShift: TShiftState);
begin
  try
    FOwner.HandleKey(AKey);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Signature, E);
  end;
end;

{ TSignatureNotifier }

constructor TSignatureNotifier.Create(AOwner: TAtlasEditorSignature);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TSignatureNotifier.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
begin
end;

procedure TSignatureNotifier.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
end;

procedure TSignatureNotifier.WindowActivated(const EditWindow: INTAEditWindow);
begin
end;

procedure TSignatureNotifier.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);
begin
end;

procedure TSignatureNotifier.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  try
    FOwner.Close;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Signature, E);
  end;
end;

procedure TSignatureNotifier.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  try
    FOwner.EditorModified(EditView);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Signature, E);
  end;
end;

procedure TSignatureNotifier.DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TSignatureNotifier.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TSignatureNotifier.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

{ TAtlasEditorSignature }

constructor TAtlasEditorSignature.Create(const ASource: IAtlasSignatureSource; const ACompletionOpen: TAtlasBoolFunc;
  const ALog: TAtlasLogFunc);
var
  Editor: IOTAEditorServices;
  Notifier: INTAEditServicesNotifier;
begin
  inherited Create;
  FLog := ALog;
  FCompletionOpen := ACompletionOpen;
  FNotifierIndex := -1;
  FOpenParen := -1;
  FLast.Line := -1;
  FDismissed.OpenParen := -1;
  FFormat.Caret := -1;
  FProvider := ASource;
  FMarks := TAtlasIdeFormatMarks.Create;
  FHint := TAtlasSignatureHint.Create(nil);
  FController := TAtlasSignatureController.Create(FHint);
  FHint.OnSelect :=
    procedure(AIndex: Integer)
    begin
      FController.SelectOverload(AIndex);
    end;
  FKeys := TSignatureKeys.Create(Self);
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := 50;
  FTimer.OnTimer := TimerTick;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editor) then
  begin
    Notifier := TSignatureNotifier.Create(Self);
    FNotifierIndex := Editor.AddNotifier(Notifier);
  end;
end;

destructor TAtlasEditorSignature.Destroy;
var
  Editor: IOTAEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  TAtlasKeyHook.Remove(FKeys);
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, Editor) then
  begin
    Editor.RemoveNotifier(FNotifierIndex);
  end;
  FTimer.Free;
  Shutdown;
  FController.Free;
  FHint.Free;
  FMarks.Free;
  FProvider := nil;
  FKeys.Free;
  inherited;
end;

procedure TAtlasEditorSignature.Log(const AMessage: string);
begin
  if Assigned(FLog) then
  begin
    FLog(AMessage);
  end;
end;

procedure TAtlasEditorSignature.Shutdown;
begin
  Close;
  FProvider.Shutdown;
end;

function TAtlasEditorSignature.Active: Boolean;
begin
  Result := FController.Active or FPending;
end;

procedure TAtlasEditorSignature.ApplyStyle(const ACaret: TRect);
begin
  TAtlasIdeStyle.Apply(FHint, ACaret);
end;

function TAtlasEditorSignature.Invoke(const AView: IOTAEditView): Boolean;
var
  mSpot: TCursorSpot;
  mSite: TAtlasCallSite;
  mWindow: HWND;
  mAnchor: TRect;
begin
  Result := False;
  // Parameter-Hint abgeschaltet (ARG-046): weder bei "(" und "," noch nach dem Übernehmen.
  if (AView = nil) or (AView.Buffer = nil) or not TAtlasIdeSettings.Current.ParameterHints then
  begin
    Exit;
  end;
  mSpot := CursorSpot(AView);
  mSite := TAtlasCallScanner.Scan(mSpot.Text, mSpot.Caret);
  if not mSite.Found then
  begin
    Close;
    Exit;
  end;
  // Schon offen für denselben Aufruf (z. B. "," gleich nach "("): nur den Parameter nachziehen.
  if FController.Active and (mSite.OpenParen = FOpenParen) and (AView = FView) then
  begin
    FController.UpdateParameter(mSite.ActiveParameter);
    Exit(True);
  end;
  if not CaretAnchor(mWindow, mAnchor) then
  begin
    Exit;
  end;
  ApplyStyle(mAnchor);
  // Linke Kante an der öffnenden Klammer, wenn sie in derselben Zeile vor dem Caret steht.
  FHint.Canvas.Font := FHint.Font;
  if mSpot.Caret - mSite.OpenParen <= mSpot.Character then
  begin
    mAnchor.Left := mAnchor.Left - FHint.Canvas.TextWidth(Copy(mSpot.Text, mSite.OpenParen + 1,
      mSpot.Caret - mSite.OpenParen));
  end;
  FHint.Anchor := mAnchor;
  FHint.Above := Assigned(FCompletionOpen) and FCompletionOpen();
  FHint.FormatPlaceholders := TAtlasIdeSettings.Current.FormatPlaceholders;
  FController.Close;
  FDismissed.OpenParen := -1;
  FFormat.Text := mSpot.Text;
  FFormat.Caret := mSpot.Caret;
  FFormat.Due := 0;
  FView := AView;
  FEditorWindow := mWindow;
  FOpenParen := mSite.OpenParen;
  FOpened := WindowState(AView, FEditorWindow, FEditorWindow);
  FAnchorLine := mSpot.Line;
  FPending := FProvider.Query(AView.Buffer.FileName, mSpot.Text, mSpot.Line - 1, mSpot.Character,
    procedure(const AHelp: TAtlasSignatureHelp)
    begin
      HelpArrived(AHelp, mSpot.Text);
    end);
  ActiveChanged;
  Result := FPending;
end;

procedure TAtlasEditorSignature.HelpArrived(const AHelp: TAtlasSignatureHelp; const AText: string);
var
  mCurrent: TAtlasCallSite;
  mSpot: TCursorSpot;
begin
  FPending := False;
  if FView = nil then
  begin
    Exit;
  end;
  // Seit der Anfrage weitergetippt: Parameter lokal neu zählen.
  mSpot := CursorSpot(FView);
  mCurrent := TAtlasCallScanner.Scan(mSpot.Text, mSpot.Caret);
  if not mCurrent.Found or (mCurrent.OpenParen <> FOpenParen) then
  begin
    Close;
    Exit;
  end;
  FHint.Above := Assigned(FCompletionOpen) and FCompletionOpen();
  FHint.SetPath(mCurrent.Outer, mCurrent.Name);
  FController.Show(AHelp, mCurrent.ActiveParameter);
  // Im Detailpanel gewählte Überladung übernehmen (#425), einmalig.
  if (FPreferredName <> '') and SameText(FPreferredName, mCurrent.Name) and (FPreferredIndex > 0) and
    (FPreferredIndex < Length(AHelp.Signatures)) then
  begin
    FController.SelectOverload(FPreferredIndex);
  end;
  FPreferredName := '';
  ShowFormat(AHelp.Format, AText);
  Log(Format('Parameter-Hint: %d Signaturen, Parameter %d', [Length(AHelp.Signatures), mCurrent.ActiveParameter]));
  ActiveChanged;
end;

class procedure TAtlasEditorSignature.PreferOverload(const AName: string; AIndex: Integer);
begin
  FPreferredName := AName;
  FPreferredIndex := AIndex;
end;

procedure TAtlasEditorSignature.Close;
begin
  FPending := False;
  FProvider.Cancel;
  FController.Close;
  FMarks.Clear;
  FFormat.Text := '';
  FFormat.Caret := -1;
  FFormat.Due := 0;
  ActiveChanged;
end;

procedure TAtlasEditorSignature.ShowFormat(const AFormat: TAtlasSignatureFormat; const AText: string);
begin
  if FHint.FormatPlaceholders and AFormat.Found and (FView <> nil) and (FView.Buffer <> nil) then
  begin
    FMarks.Show(FView.Buffer.FileName, AText, TAtlasEditorBuffer.TabWidth(FView.Buffer),
      TAtlasSignatureFormats.Marks(AFormat));
  end
  else
  begin
    FMarks.Clear;
  end;
end;

procedure TAtlasEditorSignature.CheckFormat(const AText: string; ALine, ACharacter, ACaret: Integer);
var
  Text: string;
begin
  if FPending or not FHint.FormatPlaceholders or not FController.Help.Format.Found or (FView = nil) then
  begin
    Exit;
  end;
  // Erst nach kurzer Ruhe: Jede Anfrage gleicht den Puffer mit dem Server ab.
  if (ACaret <> FFormat.Caret) or (AText <> FFormat.Text) then
  begin
    FFormat.Text := AText;
    FFormat.Caret := ACaret;
    FFormat.Due := FormatQuietTicks;
    Exit;
  end;
  if FFormat.Due <= 0 then
  begin
    Exit;
  end;
  Dec(FFormat.Due);
  if FFormat.Due > 0 then
  begin
    Exit;
  end;
  Text := AText;
  FProvider.Query(FView.Buffer.FileName, Text, ALine, ACharacter,
    procedure(const AHelp: TAtlasSignatureHelp)
    begin
      // Inzwischen geschlossen oder weitergetippt: Der nächste Takt fragt neu.
      if (FView = nil) or not FController.Active or (Text <> FFormat.Text) then
      begin
        Exit;
      end;
      FController.UpdateFormat(AHelp.Format);
      ShowFormat(AHelp.Format, Text);
    end);
end;

procedure TAtlasEditorSignature.ActiveChanged;
begin
  FTimer.Enabled := Active;
  if FController.Active then
  begin
    TAtlasKeyHook.Add(FKeys);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
  if not Active then
  begin
    FView := nil;
    FOpenParen := -1;
  end;
end;

procedure TAtlasEditorSignature.EditorModified(const AView: IOTAEditView);
var
  FileName, LineText: string;
  Line: Integer;
  Removed: Boolean;
begin
  if Active then
  begin
    Recheck;
  end;
  if (AView = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  FileName := AView.Buffer.FileName;
  Line := AView.CursorPos.Line;
  LineText := TAtlasEditorBuffer.LineText(AView, Line);
  Removed := not Active and SameText(FileName, FLast.FileName) and (Line = FLast.Line) and
    TAtlasCallScanner.RemovedClosingParen(FLast.Text, LineText);
  FLast.FileName := FileName;
  FLast.Line := Line;
  FLast.Text := LineText;
  if not Removed then
  begin
    Exit;
  end;
  // Erst nach der Änderung, wenn die IDE den Caret gesetzt hat.
  TAtlasMainThread.ForceQueue(TAtlasFeature.Signature,
    procedure
    begin
      try
        Reopen(AView);
      except
        on E: Exception do
        begin
          Log('Parameter-Hint: ' + E.Message);
          // Server weg oder Zeitlimit ist erwartbar; anderes zählt die Sicherung (Code-Review S-05).
          if not (E is ELspClientError) then
          begin
            TAtlasGuard.Report(TAtlasFeature.Signature, E);
          end;
        end;
      end;
    end);
end;

procedure TAtlasEditorSignature.Reopen(const AView: IOTAEditView);
var
  mSpot: TCursorSpot;
  mSite: TAtlasCallSite;
begin
  if Active or (AView = nil) or (AView.Buffer = nil) or not Application.Active then
  begin
    Exit;
  end;
  mSpot := CursorSpot(AView);
  mSite := TAtlasCallScanner.Scan(mSpot.Text, mSpot.Caret);
  if not mSite.Found or ((mSite.OpenParen = FDismissed.OpenParen) and
    SameText(AView.Buffer.FileName, FDismissed.FileName)) then
  begin
    Exit;
  end;
  Log('Parameter-Hint: nach entfernter Klammer wieder geöffnet');
  Invoke(AView);
end;

procedure TAtlasEditorSignature.TimerTick(Sender: TObject);
begin
  try
    Recheck;
  except
    on E: Exception do
    begin
      Log('Parameter-Hint: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Signature, E);
      Close;
    end;
  end;
end;

procedure TAtlasEditorSignature.Recheck;
var
  Anchor: TRect;
  mSpot: TCursorSpot;
  Site: TAtlasCallSite;
  View: IOTAEditView;
  Now: TAtlasEditorWindowState;
  Move: Boolean;
begin
  if not Active or (FView = nil) then
  begin
    ActiveChanged;
    Exit;
  end;
  // IDE inaktiv, Fokus woanders, Größe geändert, Ankerzeile außer Sicht: schließen (#414).
  Now := WindowState(FView, FEditorWindow, GetFocus);
  if TAtlasCloseRules.Hint(FOpened, Now, FAnchorLine, Move) <> TAtlasCloseReason.None then
  begin
    Close;
    Exit;
  end;
  // Gescrollt: mitwandern, solange die Ankerzeile sichtbar ist.
  if Move then
  begin
    Anchor := FHint.Anchor;
    Anchor.Offset(0, (FOpened.TopRow - Now.TopRow) * Anchor.Height);
    FHint.MoveTo(Anchor);
    FOpened.TopRow := Now.TopRow;
  end;
  mSpot := CursorSpot(FView);
  Site := TAtlasCallScanner.Scan(mSpot.Text, mSpot.Caret);
  // Aufruf verlassen (auch durch ")") oder in einen anderen gewechselt.
  if not Site.Found or (Site.OpenParen > FOpenParen) then
  begin
    Close;
    Exit;
  end;
  // Inneren Aufruf verlassen: wieder den äußeren zeigen (#438).
  if Site.OpenParen < FOpenParen then
  begin
    View := FView;
    Close;
    Invoke(View);
    Exit;
  end;
  if FController.Active then
  begin
    FHint.Above := Assigned(FCompletionOpen) and FCompletionOpen();
    FController.UpdateParameter(Site.ActiveParameter);
    CheckFormat(mSpot.Text, mSpot.Line - 1, mSpot.Character, mSpot.Caret);
  end;
end;

function TAtlasEditorSignature.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := FController.Active and
    (((AKey = VK_ESCAPE) and (AShift = [])) or
     (((AKey = VK_UP) or (AKey = VK_DOWN)) and (AShift = [ssAlt]) and (Length(FController.Help.Signatures) > 1)));
end;

procedure TAtlasEditorSignature.HandleKey(AKey: Word);
begin
  case AKey of
    VK_ESCAPE:
      begin
        // Für diesen Aufruf nicht von selbst wieder öffnen.
        if FView <> nil then
        begin
          FDismissed.FileName := FView.Buffer.FileName;
        end;
        FDismissed.OpenParen := FOpenParen;
        Close;
      end;
    VK_UP:
      FController.PreviousOverload;
    VK_DOWN:
      FController.NextOverload;
  end;
end;

end.
