unit Argus.IDE.Signature.Editor;

// Parameter-Hint im Editor der IDE (#436, #437, #440): verbindet die Signaturen
// des Servers, den Ablauf (TArgusSignatureController) und das Hint-Fenster mit
// dem Editor. Der Code Insight-Manager ruft Invoke bei "(", "," und
// Strg+Umschalt+Leer statt der eingebauten Parameterhilfe.
//   - Start: Aufruf am Caret lokal suchen (TArgusCallScanner), Signaturen beim
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

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.ExtCtrls,
  ToolsAPI,
  Argus.Core.Signature.Contract,
  Argus.Core.Signature.Controller,
  Argus.Core.Signature.Providers.Server,
  Argus.Core.Completion.Providers.Server,
  Argus.UI.Signature.Hint,
  Argus.IDE.Editor.KeyHook;

type
  TArgusLogFunc = reference to procedure(const AMessage: string);
  /// <summary>Ist das Vervollständigungs-Popup offen? Dann steht der Hint über der Zeile (#440).</summary>
  TArgusBoolFunc = reference to function: Boolean;

  TArgusEditorSignature = class
  private
    FProvider: TArgusServerSignatureProvider;
    FHint: TArgusSignatureHint;
    FController: TArgusSignatureController;
    FTimer: TTimer;
    FKeys: TArgusKeyClient;
    FLog: TArgusLogFunc;
    FCompletionOpen: TArgusBoolFunc;
    FNotifierIndex: Integer;
    // Zustand des offenen Hints.
    FView: IOTAEditView;
    FEditorWindow: HWND;
    FOpenParen: Integer;
    FTopRow: Integer;
    FPending: Boolean;
    // Zeile vor der letzten Änderung (Wieder öffnen nach entfernter ")").
    FLastFile: string;
    FLastLine: Integer;
    FLastLineText: string;
    // Mit Esc geschlossener Aufruf.
    FDismissedFile: string;
    FDismissedParen: Integer;
    procedure Reopen(const AView: IOTAEditView);
    procedure Log(const AMessage: string);
    procedure TimerTick(Sender: TObject);
    procedure Recheck;
    procedure ApplyStyle;
    procedure ActiveChanged;
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure HandleKey(AKey: Word; AShift: TShiftState);
  public
    constructor Create(const ASession: TArgusSessionFunc; const ACompletionOpen: TArgusBoolFunc;
      const ALog: TArgusLogFunc);
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
  Vcl.Forms,
  DockForm,
  Argus.Core.Signature.CallScanner,
  Argus.Core.Lsp.Session,
  Argus.IDE.Editor.Buffer,
  Argus.IDE.Editor.Style;

type
  TSignatureKeys = class(TArgusKeyClient)
  private
    FOwner: TArgusEditorSignature;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  public
    constructor Create(AOwner: TArgusEditorSignature);
  end;

  TSignatureNotifier = class(TNotifierObject, INTAEditServicesNotifier)
  private
    FOwner: TArgusEditorSignature;
  public
    constructor Create(AOwner: TArgusEditorSignature);
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

constructor TSignatureKeys.Create(AOwner: TArgusEditorSignature);
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
  FOwner.HandleKey(AKey, AShift);
end;

{ TSignatureNotifier }

constructor TSignatureNotifier.Create(AOwner: TArgusEditorSignature);
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
  end;
end;

procedure TSignatureNotifier.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  try
    FOwner.EditorModified(EditView);
  except
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

{ TArgusEditorSignature }

constructor TArgusEditorSignature.Create(const ASession: TArgusSessionFunc; const ACompletionOpen: TArgusBoolFunc;
  const ALog: TArgusLogFunc);
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
  FProvider := TArgusServerSignatureProvider.Create(ASession);
  FHint := TArgusSignatureHint.Create(nil);
  FController := TArgusSignatureController.Create(FHint);
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

destructor TArgusEditorSignature.Destroy;
var
  Editor: IOTAEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  TArgusKeyHook.Remove(FKeys);
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, Editor) then
    Editor.RemoveNotifier(FNotifierIndex);
  FTimer.Free;
  Shutdown;
  FController.Free;
  FHint.Free;
  FProvider.Free;
  FKeys.Free;
  inherited;
end;

procedure TArgusEditorSignature.Log(const AMessage: string);
begin
  if Assigned(FLog) then
    FLog(AMessage);
end;

procedure TArgusEditorSignature.Shutdown;
begin
  Close;
  FProvider.Shutdown;
end;

function TArgusEditorSignature.Active: Boolean;
begin
  Result := FController.Active or FPending;
end;

procedure TArgusEditorSignature.ApplyStyle;
begin
  TArgusIdeStyle.Apply(FHint);
end;

function TArgusEditorSignature.Invoke(const AView: IOTAEditView): Boolean;
var
  Text, LineText: string;
  Cursor: TOTAEditPos;
  Character, Caret: Integer;
  Site: TArgusCallSite;
  Info: TGUIThreadInfo;
  Anchor: TRect;
begin
  Result := False;
  if (AView = nil) or (AView.Buffer = nil) then
    Exit;
  Text := TArgusEditorBuffer.Text(AView.Buffer);
  Cursor := AView.CursorPos;
  LineText := TArgusEditorBuffer.LineText(AView, Cursor.Line);
  Character := TLspSession.ColumnToIndex(LineText, Cursor.Col, TArgusEditorBuffer.TabWidth(AView.Buffer));
  Caret := TArgusEditorBuffer.CharOffset(Text, Cursor.Line - 1, Character);
  Site := TArgusCallScanner.Scan(Text, Caret);
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
  ApplyStyle;
  // Linke Kante an der öffnenden Klammer, wenn sie in derselben Zeile vor dem Caret steht.
  FHint.Canvas.Font := FHint.Font;
  if Caret - Site.OpenParen <= Character then
    Anchor.Left := Anchor.Left - FHint.Canvas.TextWidth(Copy(Text, Site.OpenParen + 1, Caret - Site.OpenParen));
  FHint.Anchor := Anchor;
  FHint.Above := Assigned(FCompletionOpen) and FCompletionOpen();
  FController.Close;
  FDismissedParen := -1;
  FView := AView;
  FEditorWindow := Info.hwndCaret;
  FOpenParen := Site.OpenParen;
  FTopRow := AView.TopRow;
  FPending := FProvider.Query(AView.Buffer.FileName, Text, Cursor.Line - 1, Character,
    procedure(const AHelp: TArgusSignatureHelp)
    var
      Current: TArgusCallSite;
    begin
      FPending := False;
      if FView = nil then
        Exit;
      // Seit der Anfrage weitergetippt: Parameter lokal neu zählen.
      Current := TArgusCallScanner.Scan(TArgusEditorBuffer.Text(FView.Buffer),
        TArgusEditorBuffer.CharOffset(TArgusEditorBuffer.Text(FView.Buffer), FView.CursorPos.Line - 1,
          TLspSession.ColumnToIndex(TArgusEditorBuffer.LineText(FView, FView.CursorPos.Line), FView.CursorPos.Col,
            TArgusEditorBuffer.TabWidth(FView.Buffer))));
      if not Current.Found or (Current.OpenParen <> FOpenParen) then
      begin
        Close;
        Exit;
      end;
      FHint.Above := Assigned(FCompletionOpen) and FCompletionOpen();
      FHint.SetPath(Current.Outer, Current.Name);
      FController.Show(AHelp, Current.ActiveParameter);
      Log(Format('Parameter-Hint: %d Signaturen, Parameter %d', [Length(AHelp.Signatures), Current.ActiveParameter]));
      ActiveChanged;
    end);
  ActiveChanged;
  Result := FPending;
end;

procedure TArgusEditorSignature.Close;
begin
  FPending := False;
  FProvider.Cancel;
  FController.Close;
  ActiveChanged;
end;

procedure TArgusEditorSignature.ActiveChanged;
begin
  FTimer.Enabled := Active;
  if FController.Active then
    TArgusKeyHook.Add(FKeys)
  else
    TArgusKeyHook.Remove(FKeys);
  if not Active then
  begin
    FView := nil;
    FOpenParen := -1;
  end;
end;

procedure TArgusEditorSignature.EditorModified(const AView: IOTAEditView);
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
  LineText := TArgusEditorBuffer.LineText(AView, Line);
  Removed := not Active and SameText(FileName, FLastFile) and (Line = FLastLine) and
    TArgusCallScanner.RemovedClosingParen(FLastLineText, LineText);
  FLastFile := FileName;
  FLastLine := Line;
  FLastLineText := LineText;
  if not Removed then
    Exit;
  // Erst nach der Änderung, wenn die IDE den Caret gesetzt hat.
  TThread.ForceQueue(nil,
    procedure
    begin
      try
        Reopen(AView);
      except
        on E: Exception do
          Log('Parameter-Hint: ' + E.Message);
      end;
    end);
end;

procedure TArgusEditorSignature.Reopen(const AView: IOTAEditView);
var
  Text, LineText: string;
  Cursor: TOTAEditPos;
  Character: Integer;
  Site: TArgusCallSite;
begin
  if Active or (AView = nil) or (AView.Buffer = nil) or not Application.Active then
    Exit;
  Text := TArgusEditorBuffer.Text(AView.Buffer);
  Cursor := AView.CursorPos;
  LineText := TArgusEditorBuffer.LineText(AView, Cursor.Line);
  Character := TLspSession.ColumnToIndex(LineText, Cursor.Col, TArgusEditorBuffer.TabWidth(AView.Buffer));
  Site := TArgusCallScanner.Scan(Text, TArgusEditorBuffer.CharOffset(Text, Cursor.Line - 1, Character));
  if not Site.Found or ((Site.OpenParen = FDismissedParen) and SameText(AView.Buffer.FileName, FDismissedFile)) then
    Exit;
  Log('Parameter-Hint: nach entfernter Klammer wieder geöffnet');
  Invoke(AView);
end;

procedure TArgusEditorSignature.TimerTick(Sender: TObject);
begin
  try
    Recheck;
  except
    on E: Exception do
    begin
      Log('Parameter-Hint: ' + E.Message);
      Close;
    end;
  end;
end;

procedure TArgusEditorSignature.Recheck;
var
  Text, LineText: string;
  Cursor: TOTAEditPos;
  Character: Integer;
  Site: TArgusCallSite;
  View: IOTAEditView;
begin
  if not Active or (FView = nil) then
  begin
    ActiveChanged;
    Exit;
  end;
  if not Application.Active or (GetFocus <> FEditorWindow) or (FView.TopRow <> FTopRow) then
  begin
    Close;
    Exit;
  end;
  Text := TArgusEditorBuffer.Text(FView.Buffer);
  Cursor := FView.CursorPos;
  LineText := TArgusEditorBuffer.LineText(FView, Cursor.Line);
  Character := TLspSession.ColumnToIndex(LineText, Cursor.Col, TArgusEditorBuffer.TabWidth(FView.Buffer));
  Site := TArgusCallScanner.Scan(Text, TArgusEditorBuffer.CharOffset(Text, Cursor.Line - 1, Character));
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
  end;
end;

function TArgusEditorSignature.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := FController.Active and
    (((AKey = VK_ESCAPE) and (AShift = [])) or
     (((AKey = VK_UP) or (AKey = VK_DOWN)) and (AShift = [ssAlt]) and (Length(FController.Help.Signatures) > 1)));
end;

procedure TArgusEditorSignature.HandleKey(AKey: Word; AShift: TShiftState);
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
