unit Argus.IDE.Completion.Editor;

// Vervollständigung im Editor der IDE (#410, #414, #407): verbindet Datenquelle
// (#408), Ablauf (TArgusCompletionController) und Popup (Argus.UI) mit dem
// Editor. Der Code Insight-Manager ruft Invoke statt der eingebauten Liste.
//   - Start: Wort vor dem Cursor als Präfix, Caret-Rechteck als Anker des Popups.
//   - Weitertippen: EditorViewModified und ein Zeitgeber (für Cursorbewegungen)
//     lesen die aktuelle Zeile und filtern neu.
//   - Schließen (#414): Cursor verlässt das Wort oder die Zeile, Editor verliert
//     den Fokus, IDE wird inaktiv, Editor scrollt, Ansicht wechselt.
//   - Tasten: Eine Tastaturbindung leitet ↑ ↓ Bild↑ Bild↓ Pos1 Ende Enter Tab Esc
//     an das Popup, aber nur, solange es offen ist; sonst gehen sie an den Editor.
//   - Übernahme: ein Undo-Schritt (CreateUndoableWriter) für Name und uses-Ergänzung.
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
  Argus.UI.Completion.Popup;

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
    FController: TArgusCompletionController;
    FTimer: TTimer;
    FKeyBindingIndex: Integer;
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
    procedure ApplyStyle;
    function CaretRect(out AWindow: HWND; out ARect: TRect): Boolean;
    procedure ActiveChanged;
  public
    constructor Create(const ASession: TArgusSessionFunc; const ALog: TArgusLogProc);
    destructor Destroy; override;
    /// <summary>Öffnet die Vervollständigung an der Cursorstelle von AView; False, wenn nicht möglich.</summary>
    function Invoke(const AView: IOTAEditView): Boolean;
    procedure Close;
    /// <summary>Taste aus der Tastaturbindung; True, wenn verbraucht.</summary>
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
  Vcl.Menus,
  Vcl.Graphics,
  Vcl.Themes,
  DockForm,
  Argus.UI.Popup.Window,
  Argus.Core.Lsp.Session,
  Argus.IDE.Editor.Buffer;

type
  TArgusCompletionKeyBinding = class(TNotifierObject, IOTAKeyboardBinding)
  private
    FOwner: TArgusEditorCompletion;
    procedure KeyProc(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
  public
    constructor Create(AOwner: TArgusEditorCompletion);
    function GetBindingType: TBindingType;
    function GetDisplayName: string;
    function GetName: string;
    procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
  end;

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

function IsIdentifierChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

{ TArgusCompletionKeyBinding }

constructor TArgusCompletionKeyBinding.Create(AOwner: TArgusEditorCompletion);
begin
  inherited Create;
  FOwner := AOwner;
end;

function TArgusCompletionKeyBinding.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TArgusCompletionKeyBinding.GetDisplayName: string;
begin
  Result := 'Argus IDE Expert: Vervollständigung';
end;

function TArgusCompletionKeyBinding.GetName: string;
begin
  Result := 'Argus.Completion.Keys';
end;

procedure TArgusCompletionKeyBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
const
  Keys: array[0..8] of Word = (VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT, VK_HOME, VK_END, VK_RETURN, VK_TAB, VK_ESCAPE);
var
  Key: Word;
begin
  // Ohne kfImplicitShift: Umschalt+↑ markiert weiter im Editor.
  for Key in Keys do
    BindingServices.AddKeyBinding([ShortCut(Key, [])], KeyProc, nil, kfImplicitKeypad);
end;

procedure TArgusCompletionKeyBinding.KeyProc(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
var
  Key: TArgusNavigationKey;
begin
  BindingResult := krUnhandled;
  try
    if not FOwner.Visible then
      Exit;
    case KeyCode and $FF of
      VK_UP: Key := TArgusNavigationKey.Up;
      VK_DOWN: Key := TArgusNavigationKey.Down;
      VK_PRIOR: Key := TArgusNavigationKey.PageUp;
      VK_NEXT: Key := TArgusNavigationKey.PageDown;
      VK_HOME: Key := TArgusNavigationKey.First;
      VK_END: Key := TArgusNavigationKey.Last;
      VK_RETURN, VK_TAB: Key := TArgusNavigationKey.Accept;
      VK_ESCAPE: Key := TArgusNavigationKey.Cancel;
    else
      Exit;
    end;
    if FOwner.HandleKey(Key) then
      BindingResult := krHandled;
  except
    // Keine Exception an die IDE (#493); die Taste geht dann an den Editor.
    BindingResult := krUnhandled;
  end;
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
  Keyboard: IOTAKeyboardServices;
  Editor: IOTAEditorServices;
  Binding: IOTAKeyboardBinding;
  Notifier: INTAEditServicesNotifier;
begin
  inherited Create;
  FLog := ALog;
  FKeyBindingIndex := -1;
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
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := 50;
  FTimer.OnTimer := TimerTick;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
  begin
    Binding := TArgusCompletionKeyBinding.Create(Self);
    FKeyBindingIndex := Keyboard.AddKeyboardBinding(Binding);
  end;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editor) then
  begin
    Notifier := TArgusEditNotifier.Create(Self);
    FNotifierIndex := Editor.AddNotifier(Notifier);
  end;
end;

destructor TArgusEditorCompletion.Destroy;
var
  Keyboard: IOTAKeyboardServices;
  Editor: IOTAEditorServices;
begin
  // Erst abmelden, dann freigeben: Die IDE ruft sonst noch in freigegebene Objekte (#493).
  if (FKeyBindingIndex >= 0) and Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
    Keyboard.RemoveKeyboardBinding(FKeyBindingIndex);
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, Editor) then
    Editor.RemoveNotifier(FNotifierIndex);
  FTimer.Free;
  Shutdown;
  FController.Free;
  FPopup.Free;
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

procedure TArgusEditorCompletion.ApplyStyle;
var
  Theming: IOTAIDEThemingServices;
  Editor: IOTAEditorServices;
  Colors: TArgusPopupColors;
begin
  Colors := TArgusPopupColors.FromStyle;
  // Farben aus dem Thema der IDE (hell/dunkel), Schrift aus den Editoroptionen (#411, #445 folgen).
  if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) and Theming.IDEThemingEnabled then
  begin
    Colors.Background := Theming.StyleServices.GetSystemColor(clWindow);
    Colors.Text := Theming.StyleServices.GetSystemColor(clWindowText);
    Colors.SecondaryText := Theming.StyleServices.GetSystemColor(clGrayText);
    Colors.SelectionBackground := Theming.StyleServices.GetSystemColor(clHighlight);
    Colors.SelectionText := Theming.StyleServices.GetSystemColor(clHighlightText);
    Colors.Border := Theming.StyleServices.GetSystemColor(clBtnShadow);
    Colors.Accent := Theming.StyleServices.GetSystemColor(clHighlight);
  end;
  FPopup.Colors := Colors;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editor) and (Editor.EditOptions <> nil) then
  begin
    FPopup.Font.Name := Editor.EditOptions.FontName;
    FPopup.Font.Size := Editor.EditOptions.FontSize;
  end;
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
  WordStart := Character;
  while (WordStart > 0) and IsIdentifierChar(LineText[WordStart]) do
    Dec(WordStart);
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
  ApplyStyle;
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
  if not FController.Active then
    FView := nil;
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

procedure TArgusEditorCompletion.TimerTick(Sender: TObject);
begin
  try
    Recheck;
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
    if not IsIdentifierChar(LineText[Index]) then
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
    Character := FCommitEnd;
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
