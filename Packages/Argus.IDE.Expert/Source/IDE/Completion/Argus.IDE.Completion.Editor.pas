unit Argus.IDE.Completion.Editor;

// Vervollständigung im Editor der IDE (#410, #414, #407): verbindet Datenquelle
// (#408), Ablauf (TArgusCompletionController) und Popup (Argus.UI) mit dem
// Editor. Der Code Insight-Manager ruft Invoke statt der eingebauten Liste.
//   - Start: Wort vor dem Cursor als Präfix, Caret-Rechteck als Anker des Popups.
//   - Weitertippen: EditorViewModified und ein Zeitgeber (für Cursorbewegungen)
//     lesen die aktuelle Zeile und filtern neu.
//   - Schließen (#414): Cursor verlässt das Wort oder die Zeile, Editor verliert
//     den Fokus, IDE wird inaktiv, Editor scrollt, Ansicht wechselt.
//   - Tasten: Nur solange das Popup offen ist, nimmt es über den gemeinsamen
//     Tastatur-Hook (Argus.IDE.Editor.KeyHook) ↑ ↓ Bild↑ Bild↓ Pos1 Ende Enter Tab Esc
//     ohne Umschalt/Strg/Alt entgegen; sonst gehen alle Tasten an den Editor.
//   - Übernahme: ein Undo-Schritt (CreateUndoableWriter) für Name und uses-Ergänzung.
//   - Detailpanel (#424): 80 ms nach einem Wechsel der Auswahl fragt die Quelle die
//     Details nach (completionItem/resolve); das Panel ist Teil des Popups (rechts der Liste).
//   - Commit-Zeichen (#429): Wird hinter dem Wort "(", ";" oder "." getippt und trifft
//     der gewählte Eintrag klar, wird er übernommen und das Zeichen bleibt stehen;
//     sonst bleibt nur das Zeichen und das Popup schließt. Erkannt nach dem Tippen im
//     Puffer, nicht über eine Tastenbindung: unabhängig vom Tastaturlayout.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.ExtCtrls,
  ToolsAPI,
  Argus.Core.Completion.Contract,
  Argus.Core.Completion.Composite,
  Argus.Core.Completion.Controller,
  Argus.Core.Completion.Providers.Server,
  Argus.UI.Completion.Popup,
  Argus.IDE.Editor.KeyHook;

type
  /// <summary>Protokoll für die Diagnose (Registry-Wert Diagnose).</summary>
  TArgusLogProc = reference to procedure(const AMessage: string);

  TArgusEditorCompletion = class
  private
    FProviders: TArgusCompletionProviders;
    FProvidersRef: IArgusCompletionProvider;
    FServerProvider: TArgusServerCompletionProvider;
    FServerProviderRef: IArgusCompletionProvider;
    FPopup: TArgusCompletionPopup;
    // Detailpanel: Schlüssel der gewählten Einträge, Zeitpunkt der Anfrage, schon angefragt.
    FDetailKey: string;
    FDetailDue: UInt64;
    FDetailRequested: Boolean;
    FController: TArgusCompletionController;
    FTimer: TTimer;
    FKeys: TArgusKeyClient;
    FNotifierIndex: Integer;
    FLog: TArgusLogProc;
    // Zustand der offenen Vervollständigung.
    FView: IOTAEditView;
    FEditorWindow: HWND;
    FLine: Integer;
    FWordStart: Integer;
    FTopRow: Integer;
    // Commit über ein Zeichen: Ende des Worts und Bytes des stehen bleibenden Zeichens.
    FCommitEnd: Integer;
    FCommitSuffixBytes: Integer;
    procedure Log(const AMessage: string);
    procedure Recheck;
    procedure TimerTick(Sender: TObject);
    procedure Commit(const AItem: TArgusCompletionItem);
    procedure ApplyStyle(const ACaret: TRect);
    function CaretRect(out AWindow: HWND; out ARect: TRect): Boolean;
    procedure ActiveChanged;
    procedure UpdateDetails;
    procedure HideDetails;
    procedure InstallKeyHook;
    procedure RemoveKeyHook;
    /// <summary>Gehört die Taste gerade dem Popup?</summary>
    function WantsKey(AKey: TArgusNavigationKey): Boolean;
  public
    constructor Create(const ASession: TArgusSessionFunc; const ALog: TArgusLogProc);
    destructor Destroy; override;
    /// <summary>Öffnet die Vervollständigung an der Cursorstelle von AView; False, wenn nicht möglich.</summary>
    function Invoke(const AView: IOTAEditView): Boolean;
    procedure Close;
    /// <summary>Taste aus dem Tastatur-Hook; True, wenn verbraucht.</summary>
    function HandleKey(AKey: TArgusNavigationKey): Boolean;
    /// <summary>Editortext wurde geändert.</summary>
    procedure EditorModified(const AView: IOTAEditView);
    /// <summary>Bricht laufende Serveranfragen ab und wartet auf sie; vor dem Freigeben der Sitzung.</summary>
    procedure Shutdown;
    function Visible: Boolean;
  end;

implementation

uses
  Winapi.Messages,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Vcl.Forms,
  DockForm,
  Argus.Core.Lsp.Session,
  Argus.Core.Completion.Word,
  Argus.IDE.Editor.Buffer,
  Argus.IDE.Editor.Style;

type
  TArgusEditNotifier = class(TNotifierObject, INTAEditServicesNotifier)
  private
    FOwner: TArgusEditorCompletion;
  public
    constructor Create(AOwner: TArgusEditorCompletion);
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

  TPendingEdit = record
    Start: Integer;
    Stop: Integer;
    Text: string;
    IsWord: Boolean;
  end;

type
  /// <summary>Tasten des Popups über den gemeinsamen Hook; Priorität vor dem Parameter-Hint.</summary>
  TCompletionKeys = class(TArgusKeyClient)
  private
    FOwner: TArgusEditorCompletion;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  public
    constructor Create(AOwner: TArgusEditorCompletion);
  end;

function NavigationKey(AKey: Word; out ANavigation: TArgusNavigationKey): Boolean;
begin
  Result := True;
  case AKey of
    VK_UP: ANavigation := TArgusNavigationKey.Up;
    VK_DOWN: ANavigation := TArgusNavigationKey.Down;
    VK_PRIOR: ANavigation := TArgusNavigationKey.PageUp;
    VK_NEXT: ANavigation := TArgusNavigationKey.PageDown;
    VK_HOME: ANavigation := TArgusNavigationKey.First;
    VK_END: ANavigation := TArgusNavigationKey.Last;
    VK_RETURN, VK_TAB: ANavigation := TArgusNavigationKey.Accept;
    VK_ESCAPE: ANavigation := TArgusNavigationKey.Cancel;
  else
    Result := False;
  end;
end;

{ TCompletionKeys }

constructor TCompletionKeys.Create(AOwner: TArgusEditorCompletion);
begin
  inherited Create(0);
  FOwner := AOwner;
end;

function TCompletionKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
var
  Navigation: TArgusNavigationKey;
begin
  Result := (AShift = []) and NavigationKey(AKey, Navigation) and FOwner.WantsKey(Navigation);
end;

procedure TCompletionKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  Navigation: TArgusNavigationKey;
begin
  if NavigationKey(AKey, Navigation) then
    FOwner.HandleKey(Navigation);
end;
{ TArgusEditNotifier }

constructor TArgusEditNotifier.Create(AOwner: TArgusEditorCompletion);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TArgusEditNotifier.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
begin
end;

procedure TArgusEditNotifier.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
end;

procedure TArgusEditNotifier.WindowActivated(const EditWindow: INTAEditWindow);
begin
end;

procedure TArgusEditNotifier.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);
begin
end;

procedure TArgusEditNotifier.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  // Tab-Wechsel schließt (#414).
  try
    FOwner.Close;
  except
  end;
end;

procedure TArgusEditNotifier.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  try
    FOwner.EditorModified(EditView);
  except
  end;
end;

procedure TArgusEditNotifier.DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TArgusEditNotifier.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TArgusEditNotifier.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

{ TArgusEditorCompletion }

constructor TArgusEditorCompletion.Create(const ASession: TArgusSessionFunc; const ALog: TArgusLogProc);
var
  Editor: IOTAEditorServices;
  Notifier: INTAEditServicesNotifier;
begin
  inherited Create;
  FLog := ALog;
  FNotifierIndex := -1;
  FCommitEnd := -1;
  FProviders := TArgusCompletionProviders.Create;
  FProvidersRef := FProviders;
  FServerProvider := TArgusServerCompletionProvider.Create(ASession);
  FServerProviderRef := FServerProvider;
  FProviders.Add(FServerProviderRef);
  FPopup := TArgusCompletionPopup.Create(nil);
  FController := TArgusCompletionController.Create(FProvidersRef, FPopup);
  FController.OnCommit :=
    procedure(const AItem: TArgusCompletionItem)
    begin
      Commit(AItem);
    end;
  FPopup.OnSelect :=
    procedure(APosition: Integer)
    begin
      FController.Select(APosition);
    end;
  FPopup.OnAccept :=
    procedure(APosition: Integer)
    begin
      FController.Select(APosition);
      FController.CommitSelected;
    end;
  FKeys := TCompletionKeys.Create(Self);
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := 50;
  FTimer.OnTimer := TimerTick;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editor) then
  begin
    Notifier := TArgusEditNotifier.Create(Self);
    FNotifierIndex := Editor.AddNotifier(Notifier);
  end;
end;

destructor TArgusEditorCompletion.Destroy;
var
  Editor: IOTAEditorServices;
begin
  // Erst abmelden, dann freigeben: Die IDE ruft sonst noch in freigegebene Objekte (#493).
  RemoveKeyHook;
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, Editor) then
    Editor.RemoveNotifier(FNotifierIndex);
  FTimer.Free;
  Shutdown;
  FController.Free;
  FPopup.Free;
  FKeys.Free;
  FServerProviderRef := nil;
  FProvidersRef := nil;
  inherited;
end;

procedure TArgusEditorCompletion.Log(const AMessage: string);
begin
  if Assigned(FLog) then
    FLog(AMessage);
end;

procedure TArgusEditorCompletion.Shutdown;
begin
  Close;
  FServerProvider.Shutdown;
end;

function TArgusEditorCompletion.Visible: Boolean;
begin
  // Auch der leere Zustand (#423) nimmt Esc entgegen.
  Result := FController.Visible or FController.Empty;
end;

procedure TArgusEditorCompletion.ApplyStyle(const ACaret: TRect);
begin
  // Farben aus dem Thema der IDE (hell/dunkel), Schrift aus den Editoroptionen, Monitor-DPI und Zoom
  // am Caret (#411, #412, #445).
  Log(TArgusIdeStyle.Apply(FPopup, ACaret));
end;

function TArgusEditorCompletion.CaretRect(out AWindow: HWND; out ARect: TRect): Boolean;
var
  Info: TGUIThreadInfo;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  Result := GetGUIThreadInfo(GetCurrentThreadId, Info) and (Info.hwndCaret <> 0);
  if not Result then
    Exit;
  AWindow := Info.hwndCaret;
  ARect := Info.rcCaret;
  MapWindowPoints(AWindow, 0, ARect, 2);
end;

function TArgusEditorCompletion.Invoke(const AView: IOTAEditView): Boolean;
var
  Context: TArgusContext;
  LineText: string;
  Cursor: TOTAEditPos;
  Character, WordStart: Integer;
  Window: HWND;
  Anchor: TRect;
begin
  Result := False;
  if (AView = nil) or (AView.Buffer = nil) then
    Exit;
  Cursor := AView.CursorPos;
  LineText := TArgusEditorBuffer.LineText(AView, Cursor.Line);
  Character := TLspSession.ColumnToIndex(LineText, Cursor.Col, TArgusEditorBuffer.TabWidth(AView.Buffer));
  WordStart := TArgusWord.StartBefore(LineText, Character);
  if not CaretRect(Window, Anchor) then
  begin
    Log('Vervollständigung: kein Caret gefunden');
    Exit;
  end;
  Context := Default(TArgusContext);
  Context.FileName := AView.Buffer.FileName;
  Context.Text := TArgusEditorBuffer.Text(AView.Buffer);
  Context.Line := Cursor.Line - 1;
  Context.Character := Character;
  Context.Prefix := Copy(LineText, WordStart + 1, Character - WordStart);
  if (WordStart > 0) and (LineText[WordStart] = '.') then
    Context.Kind := TArgusContextKind.MemberAccess
  else
    Context.Kind := TArgusContextKind.Identifier;
  ApplyStyle(Anchor);
  // Das Popup beginnt am Wortanfang, nicht am Caret.
  FPopup.Canvas.Font := FPopup.Font;
  Anchor.Left := Anchor.Left - FPopup.Canvas.TextWidth(Context.Prefix);
  FPopup.Anchor := Anchor;
  FView := AView;
  FEditorWindow := Window;
  FLine := Cursor.Line;
  FWordStart := WordStart;
  FTopRow := AView.TopRow;
  Log(Format('Vervollständigung in %s, Zeile %d, Zeichen %d, Präfix "%s"',
    [ExtractFileName(Context.FileName), Context.Line + 1, Context.Character, Context.Prefix]));
  FController.Start(Context);
  ActiveChanged;
  Result := True;
end;

procedure TArgusEditorCompletion.Close;
begin
  FController.Close;
  ActiveChanged;
end;

procedure TArgusEditorCompletion.ActiveChanged;
begin
  FTimer.Enabled := FController.Active;
  if FController.Active then
    InstallKeyHook
  else
  begin
    RemoveKeyHook;
    HideDetails;
    FView := nil;
  end;
end;

procedure TArgusEditorCompletion.InstallKeyHook;
begin
  TArgusKeyHook.Add(FKeys);
  if not TArgusKeyHook.Installed then
    Log('Vervollständigung: Tastatur-Hook nicht möglich: ' + SysErrorMessage(GetLastError));
end;

procedure TArgusEditorCompletion.RemoveKeyHook;
begin
  TArgusKeyHook.Remove(FKeys);
end;

function TArgusEditorCompletion.WantsKey(AKey: TArgusNavigationKey): Boolean;
begin
  // Liste offen: alle Navigationstasten. Leerer Zustand (#423): nur Esc.
  Result := FController.Visible or (FController.Empty and (AKey = TArgusNavigationKey.Cancel));
end;

function TArgusEditorCompletion.HandleKey(AKey: TArgusNavigationKey): Boolean;
begin
  Result := FController.HandleKey(AKey);
  ActiveChanged;
end;

procedure TArgusEditorCompletion.EditorModified(const AView: IOTAEditView);
begin
  if FController.Active then
    Recheck;
end;

procedure TArgusEditorCompletion.HideDetails;
begin
  FPopup.ClearDetails;
  FDetailKey := '';
  FDetailRequested := False;
end;

procedure TArgusEditorCompletion.UpdateDetails;
var
  Item: TArgusCompletionItem;
  Key: string;
  Resolver: IArgusCompletionResolver;
begin
  if not FController.Visible or not FController.SelectedItem(Item) then
  begin
    HideDetails;
    Exit;
  end;
  Key := Item.Name + #0 + Item.ResolveData;
  if Key <> FDetailKey then
  begin
    // Erst nach 80 ms Ruhe nachfragen, damit schnelles Scrollen nicht flackert (#424).
    FDetailKey := Key;
    FDetailDue := TThread.GetTickCount64 + 80;
    FDetailRequested := False;
    Exit;
  end;
  if FDetailRequested or (TThread.GetTickCount64 < FDetailDue) then
    Exit;
  FDetailRequested := True;
  if not Supports(FServerProviderRef, IArgusCompletionResolver, Resolver) or not Resolver.Resolve(Item,
    procedure(const ADetails: TArgusItemDetails)
    begin
      // Nur zeigen, wenn noch derselbe Eintrag gewählt und die Liste offen ist.
      if (FDetailKey = Key) and FController.Visible then
        FPopup.ShowDetails(ADetails);
    end) then
    FPopup.ClearDetails;
end;

procedure TArgusEditorCompletion.TimerTick(Sender: TObject);
begin
  try
    Recheck;
    UpdateDetails;
  except
    on E: Exception do
    begin
      Log('Vervollständigung: ' + E.Message);
      Close;
    end;
  end;
end;

procedure TArgusEditorCompletion.Recheck;
var
  Cursor: TOTAEditPos;
  LineText, Prefix: string;
  Character, Index: Integer;
  Context: TArgusContext;
begin
  if not FController.Active or (FView = nil) then
  begin
    ActiveChanged;
    Exit;
  end;
  // IDE inaktiv, anderes Fenster im Fokus, gescrollt: schließen (#414).
  if not Application.Active or (GetFocus <> FEditorWindow) or (FView.TopRow <> FTopRow) then
  begin
    Close;
    Exit;
  end;
  Cursor := FView.CursorPos;
  if Cursor.Line <> FLine then
  begin
    Close;
    Exit;
  end;
  LineText := TArgusEditorBuffer.LineText(FView, Cursor.Line);
  Character := TLspSession.ColumnToIndex(LineText, Cursor.Col, TArgusEditorBuffer.TabWidth(FView.Buffer));
  // Cursor vor dem Wortanfang oder ein Zeichen, das kein Bezeichner ist: Wort verlassen.
  if Character < FWordStart then
  begin
    Close;
    Exit;
  end;
  for Index := FWordStart + 1 to Character do
    if not TArgusWord.IsIdentifierChar(LineText[Index]) then
    begin
      // Commit-Zeichen direkt hinter dem Wort (#429): übernehmen, das Zeichen bleibt.
      if (Index = Character) and CharInSet(LineText[Index], ['(', ';', '.']) and
        FController.CanCommitOnCharacter then
      begin
        FCommitEnd := Character - 1;
        FCommitSuffixBytes := TEncoding.UTF8.GetByteCount(string(LineText[Index]));
        try
          FController.CommitSelected;
        finally
          FCommitEnd := -1;
        end;
        ActiveChanged;
        Exit;
      end;
      Close;
      Exit;
    end;
  Prefix := Copy(LineText, FWordStart + 1, Character - FWordStart);
  // Gekürzte Liste (#431): lokal weiterfiltern und im Hintergrund neu fragen.
  if FController.Incomplete and (Prefix <> FController.Prefix) then
  begin
    Context := Default(TArgusContext);
    Context.FileName := FView.Buffer.FileName;
    Context.Text := TArgusEditorBuffer.Text(FView.Buffer);
    Context.Line := Cursor.Line - 1;
    Context.Character := Character;
    Context.Prefix := Prefix;
    if (FWordStart > 0) and (LineText[FWordStart] = '.') then
      Context.Kind := TArgusContextKind.MemberAccess
    else
      Context.Kind := TArgusContextKind.Identifier;
    FController.Requery(Context);
  end
  else
    FController.UpdatePrefix(Prefix);
  ActiveChanged;
end;

procedure TArgusEditorCompletion.Commit(const AItem: TArgusCompletionItem);
var
  View: IOTAEditView;
  Text, NewText, LineText: string;
  Edits: TList<TPendingEdit>;
  Edit: TPendingEdit;
  TextEdit: TArgusTextEdit;
  Writer: IOTAEditWriter;
  Cursor: TOTAEditPos;
  Character, Shift, CursorByte: Integer;
  CharPos: TOTACharPos;
begin
  View := FView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Text := TArgusEditorBuffer.Text(View.Buffer);
  Cursor := View.CursorPos;
  LineText := TArgusEditorBuffer.LineText(View, Cursor.Line);
  Character := TLspSession.ColumnToIndex(LineText, Cursor.Col, TArgusEditorBuffer.TabWidth(View.Buffer));
  // Über ein Commit-Zeichen: Das Wort endet davor, das Zeichen bleibt stehen.
  if FCommitEnd >= 0 then
    Character := FCommitEnd
  else
    // Mitten im Wort: bis zu seinem Ende ersetzen, sonst bliebe der Rest stehen.
    Character := TArgusWord.EndAfter(LineText, Character);
  NewText := AItem.InsertText;
  if NewText = '' then
    NewText := AItem.Name;
  Edits := TList<TPendingEdit>.Create;
  try
    // Das getippte Wort durch den Eintrag ersetzen.
    Edit.Start := TArgusEditorBuffer.ByteOffset(Text, Cursor.Line - 1, FWordStart);
    Edit.Stop := TArgusEditorBuffer.ByteOffset(Text, Cursor.Line - 1, Character);
    Edit.Text := NewText;
    Edit.IsWord := True;
    Edits.Add(Edit);
    // uses-Ergänzung u. ä. (#180).
    for TextEdit in AItem.AdditionalEdits do
    begin
      Edit.Start := TArgusEditorBuffer.ByteOffset(Text, TextEdit.StartLine, TextEdit.StartCharacter);
      Edit.Stop := TArgusEditorBuffer.ByteOffset(Text, TextEdit.EndLine, TextEdit.EndCharacter);
      Edit.Text := TextEdit.NewText;
      Edit.IsWord := False;
      Edits.Add(Edit);
    end;
    Edits.Sort(TComparer<TPendingEdit>.Construct(
      function(const A, B: TPendingEdit): Integer
      begin
        Result := A.Start - B.Start;
      end));
    // Ein Schreiber = ein Undo-Schritt. Er schreibt nur vorwärts, deshalb aufsteigend.
    Writer := View.Buffer.CreateUndoableWriter;
    Shift := 0;
    CursorByte := -1;
    for Edit in Edits do
    begin
      Writer.CopyTo(Edit.Start);
      Writer.DeleteTo(Edit.Stop);
      Writer.Insert(PAnsiChar(UTF8Encode(Edit.Text)));
      if Edit.IsWord then
      begin
        CursorByte := Edit.Start + Shift + Length(UTF8Encode(Edit.Text));
        if FCommitEnd >= 0 then
          Inc(CursorByte, FCommitSuffixBytes);
      end;
      Inc(Shift, Length(UTF8Encode(Edit.Text)) - (Edit.Stop - Edit.Start));
    end;
    Writer := nil;
  finally
    Edits.Free;
  end;
  // Cursor hinter den übernommenen Namen.
  if CursorByte >= 0 then
  begin
    CharPos := View.PosToCharPos(CursorByte);
    View.ConvertPos(False, Cursor, CharPos);
    View.CursorPos := Cursor;
    View.MoveViewToCursor;
    View.Paint;
  end;
  Log(Format('Übernommen: %s (%d weitere Änderungen)', [AItem.Name, Length(AItem.AdditionalEdits)]));
  ActiveChanged;
end;

end.
