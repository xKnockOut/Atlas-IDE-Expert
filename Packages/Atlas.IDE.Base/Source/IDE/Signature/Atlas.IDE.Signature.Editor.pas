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
    // Zeile vor der letzten Änderung (Wieder öffnen nach entfernter ")").
    FLastFile: string;
    FLastLine: Integer;
    FLastLineText: string;
    // Mit Esc geschlossener Aufruf.
    FDismissedFile: string;
    FDismissedParen: Integer;
    // Platzhalter (#451): Färbung, Stand (Text und Cursor) der letzten Anfrage, Takte bis zur nächsten.
    FMarks: TAtlasIdeFormatMarks;
    FFormatText: string;
    FFormatCaret: Integer;
    FFormatDue: Integer;
    procedure ShowFormat(const AFormat: TAtlasSignatureFormat; const AText: string);
    procedure CheckFormat(const AText: string; ALine, ACharacter, ACaret: Integer);
    procedure Reopen(const AView: IOTAEditView);
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
    Result := Point(Area.Width, Area.Height)
  else
    Result := Point(0, 0);
end;

/// <summary>Zustand für TAtlasCloseRules (#414).</summary>
function WindowState(const AView: IOTAEditView; AWindow, AFocus: HWND): TAtlasEditorWindowState;
begin
  Result := Default(TAtlasEditorWindowState);
  Result.AppActive := Application.Active;
  Result.Focus := AFocus;
  Result.Size := EditorSize(AWindow);
  if AView = nil then
    Exit;
  Result.TopRow := AView.TopRow;
  Result.Rows := AView.ViewSize.cy;
  if AView.Buffer <> nil then
    Result.FileName := AView.Buffer.FileName;
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
  FLastLine := -1;
  FDismissedParen := -1;
  FFormatCaret := -1;
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
    Editor.RemoveNotifier(FNotifierIndex);
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
    FLog(AMessage);
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
  Text, LineText: string;
  Cursor: TOTAEditPos;
  Character, Caret: Integer;
  Site: TAtlasCallSite;
  Info: TGUIThreadInfo;
  Anchor: TRect;
begin
  Result := False;
  // Parameter-Hint abgeschaltet (ARG-046): weder bei "(" und "," noch nach dem Übernehmen.
  if (AView = nil) or (AView.Buffer = nil) or not TAtlasIdeSettings.Current.ParameterHints then
    Exit;
  Text := TAtlasEditorBuffer.Text(AView.Buffer);
  Cursor := AView.CursorPos;
  LineText := TAtlasEditorBuffer.LineText(AView, Cursor.Line);
  Character := TLspSession.ColumnToIndex(LineText, Cursor.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer));
  Caret := TAtlasEditorBuffer.CharOffset(Text, Cursor.Line - 1, Character);
  Site := TAtlasCallScanner.Scan(Text, Caret);
  if not Site.Found then
  begin
    Close;
    Exit;
  end;
  // Schon offen für denselben Aufruf (z. B. "," gleich nach "("): nur den Parameter nachziehen.
  if FController.Active and (Site.OpenParen = FOpenParen) and (AView = FView) then
  begin
    FController.UpdateParameter(Site.ActiveParameter);
    Exit(True);
  end;
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if not GetGUIThreadInfo(GetCurrentThreadId, Info) or (Info.hwndCaret = 0) then
    Exit;
  Anchor := Info.rcCaret;
  MapWindowPoints(Info.hwndCaret, 0, Anchor, 2);
  ApplyStyle(Anchor);
  // Linke Kante an der öffnenden Klammer, wenn sie in derselben Zeile vor dem Caret steht.
  FHint.Canvas.Font := FHint.Font;
  if Caret - Site.OpenParen <= Character then
    Anchor.Left := Anchor.Left - FHint.Canvas.TextWidth(Copy(Text, Site.OpenParen + 1, Caret - Site.OpenParen));
  FHint.Anchor := Anchor;
  FHint.Above := Assigned(FCompletionOpen) and FCompletionOpen();
  FHint.FormatPlaceholders := TAtlasIdeSettings.Current.FormatPlaceholders;
  FController.Close;
  FDismissedParen := -1;
  FFormatText := Text;
  FFormatCaret := Caret;
  FFormatDue := 0;
  FView := AView;
  FEditorWindow := Info.hwndCaret;
  FOpenParen := Site.OpenParen;
  FOpened := WindowState(AView, FEditorWindow, FEditorWindow);
  FAnchorLine := Cursor.Line;
  FPending := FProvider.Query(AView.Buffer.FileName, Text, Cursor.Line - 1, Character,
    procedure(const AHelp: TAtlasSignatureHelp)
    var
      Current: TAtlasCallSite;
    begin
      FPending := False;
      if FView = nil then
        Exit;
      // Seit der Anfrage weitergetippt: Parameter lokal neu zählen.
      Current := TAtlasCallScanner.Scan(TAtlasEditorBuffer.Text(FView.Buffer),
        TAtlasEditorBuffer.CharOffset(TAtlasEditorBuffer.Text(FView.Buffer), FView.CursorPos.Line - 1,
          TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(FView, FView.CursorPos.Line), FView.CursorPos.Col,
            TAtlasEditorBuffer.TabWidth(FView.Buffer))));
      if not Current.Found or (Current.OpenParen <> FOpenParen) then
      begin
        Close;
        Exit;
      end;
      FHint.Above := Assigned(FCompletionOpen) and FCompletionOpen();
      FHint.SetPath(Current.Outer, Current.Name);
      FController.Show(AHelp, Current.ActiveParameter);
      // Im Detailpanel gewählte Überladung übernehmen (#425), einmalig.
      if (FPreferredName <> '') and SameText(FPreferredName, Current.Name) and (FPreferredIndex > 0) and
        (FPreferredIndex < Length(AHelp.Signatures)) then
        FController.SelectOverload(FPreferredIndex);
      FPreferredName := '';
      ShowFormat(AHelp.Format, Text);
      Log(Format('Parameter-Hint: %d Signaturen, Parameter %d', [Length(AHelp.Signatures), Current.ActiveParameter]));
      ActiveChanged;
    end);
  ActiveChanged;
  Result := FPending;
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
  FFormatText := '';
  FFormatCaret := -1;
  FFormatDue := 0;
  ActiveChanged;
end;

procedure TAtlasEditorSignature.ShowFormat(const AFormat: TAtlasSignatureFormat; const AText: string);
begin
  if FHint.FormatPlaceholders and AFormat.Found and (FView <> nil) and (FView.Buffer <> nil) then
    FMarks.Show(FView.Buffer.FileName, AText, TAtlasEditorBuffer.TabWidth(FView.Buffer),
      TAtlasSignatureFormats.Marks(AFormat))
  else
    FMarks.Clear;
end;

procedure TAtlasEditorSignature.CheckFormat(const AText: string; ALine, ACharacter, ACaret: Integer);
var
  Text: string;
begin
  if FPending or not FHint.FormatPlaceholders or not FController.Help.Format.Found or (FView = nil) then
    Exit;
  // Erst nach kurzer Ruhe: Jede Anfrage gleicht den Puffer mit dem Server ab.
  if (ACaret <> FFormatCaret) or (AText <> FFormatText) then
  begin
    FFormatText := AText;
    FFormatCaret := ACaret;
    FFormatDue := FormatQuietTicks;
    Exit;
  end;
  if FFormatDue <= 0 then
    Exit;
  Dec(FFormatDue);
  if FFormatDue > 0 then
    Exit;
  Text := AText;
  FProvider.Query(FView.Buffer.FileName, Text, ALine, ACharacter,
    procedure(const AHelp: TAtlasSignatureHelp)
    begin
      // Inzwischen geschlossen oder weitergetippt: Der nächste Takt fragt neu.
      if (FView = nil) or not FController.Active or (Text <> FFormatText) then
        Exit;
      FController.UpdateFormat(AHelp.Format);
      ShowFormat(AHelp.Format, Text);
    end);
end;

procedure TAtlasEditorSignature.ActiveChanged;
begin
  FTimer.Enabled := Active;
  if FController.Active then
    TAtlasKeyHook.Add(FKeys)
  else
    TAtlasKeyHook.Remove(FKeys);
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
    Recheck;
  if (AView = nil) or (AView.Buffer = nil) then
    Exit;
  FileName := AView.Buffer.FileName;
  Line := AView.CursorPos.Line;
  LineText := TAtlasEditorBuffer.LineText(AView, Line);
  Removed := not Active and SameText(FileName, FLastFile) and (Line = FLastLine) and
    TAtlasCallScanner.RemovedClosingParen(FLastLineText, LineText);
  FLastFile := FileName;
  FLastLine := Line;
  FLastLineText := LineText;
  if not Removed then
    Exit;
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
            TAtlasGuard.Report(TAtlasFeature.Signature, E);
        end;
      end;
    end);
end;

procedure TAtlasEditorSignature.Reopen(const AView: IOTAEditView);
var
  Text, LineText: string;
  Cursor: TOTAEditPos;
  Character: Integer;
  Site: TAtlasCallSite;
begin
  if Active or (AView = nil) or (AView.Buffer = nil) or not Application.Active then
    Exit;
  Text := TAtlasEditorBuffer.Text(AView.Buffer);
  Cursor := AView.CursorPos;
  LineText := TAtlasEditorBuffer.LineText(AView, Cursor.Line);
  Character := TLspSession.ColumnToIndex(LineText, Cursor.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer));
  Site := TAtlasCallScanner.Scan(Text, TAtlasEditorBuffer.CharOffset(Text, Cursor.Line - 1, Character));
  if not Site.Found or ((Site.OpenParen = FDismissedParen) and SameText(AView.Buffer.FileName, FDismissedFile)) then
    Exit;
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
  Text, LineText: string;
  Cursor: TOTAEditPos;
  Character: Integer;
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
  Text := TAtlasEditorBuffer.Text(FView.Buffer);
  Cursor := FView.CursorPos;
  LineText := TAtlasEditorBuffer.LineText(FView, Cursor.Line);
  Character := TLspSession.ColumnToIndex(LineText, Cursor.Col, TAtlasEditorBuffer.TabWidth(FView.Buffer));
  Site := TAtlasCallScanner.Scan(Text, TAtlasEditorBuffer.CharOffset(Text, Cursor.Line - 1, Character));
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
    CheckFormat(Text, Cursor.Line - 1, Character,
      TAtlasEditorBuffer.CharOffset(Text, Cursor.Line - 1, Character));
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
          FDismissedFile := FView.Buffer.FileName;
        FDismissedParen := FOpenParen;
        Close;
      end;
    VK_UP:
      FController.PreviousOverload;
    VK_DOWN:
      FController.NextOverload;
  end;
end;

end.
