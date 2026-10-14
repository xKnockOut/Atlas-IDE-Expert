unit Atlas.IDE.Completion.Editor;

// Vervollständigung im Editor der IDE (#410, #414, #407): verbindet Datenquelle
// (#408), Ablauf (TAtlasCompletionController) und Popup (Atlas.UI) mit dem
// Editor. Der Code Insight-Manager ruft Invoke statt der eingebauten Liste.
//   - Start: Wort vor dem Cursor als Präfix, Caret-Rechteck als Anker des Popups.
//   - Weitertippen: EditorViewModified und ein Zeitgeber (für Cursorbewegungen)
//     lesen die aktuelle Zeile und filtern neu.
//   - Schließen (#414): Cursor verlässt das Wort oder die Zeile, Editor verliert
//     den Fokus, IDE wird inaktiv, Editor scrollt, Ansicht wechselt.
//   - Tasten: Nur solange das Popup offen ist, nimmt es über den gemeinsamen
//     Tastatur-Hook (Atlas.IDE.Editor.KeyHook) ↑ ↓ Bild↑ Bild↓ Pos1 Ende Enter Tab Esc
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
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Composite,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Completion.Providers.Server,
  Atlas.Core.Completion.Parentheses,
  Atlas.IDE.Completion.Preview,
  Atlas.UI.Completion.Popup,
  Atlas.IDE.Editor.KeyHook;

type
  /// <summary>Protokoll für die Diagnose (Registry-Wert Diagnose).</summary>
  TAtlasLogProc = reference to procedure(const AMessage: string);

  TAtlasEditorCompletion = class
  private
    FProviders: TAtlasCompletionProviders;
    FProvidersRef: IAtlasCompletionProvider;
    FServerProvider: TAtlasServerCompletionProvider;
    FServerProviderRef: IAtlasCompletionProvider;
    FPopup: TAtlasCompletionPopup;
    // Detailpanel: Schlüssel der gewählten Einträge, Zeitpunkt der Anfrage, schon angefragt.
    FDetailKey: string;
    FDetailDue: UInt64;
    FDetailRequested: Boolean;
    // Gezeigte Überladung des gewählten Eintrags (#425).
    FOverloadIndex: Integer;
    // Automatisch eingefügte ")" nach dem Übernehmen (#430).
    FAutoParen: TAtlasAutoParen;
    FOnOpenSignature: TProc;
    // Vorschau des gewählten Eintrags im Editor (#434).
    FPreview: TAtlasEditorPreview;
    FController: TAtlasCompletionController;
    FTimer: TTimer;
    FKeys: TAtlasKeyClient;
    FNotifierIndex: Integer;
    FLog: TAtlasLogProc;
    // Zustand der offenen Vervollständigung.
    FView: IOTAEditView;
    FEditorWindow: HWND;
    FLine: Integer;
    FWordStart: Integer;
    FTopRow: Integer;
    // Größe des Editors beim Öffnen; ändert sie sich, schließt das Popup (#414).
    FEditorSize: TPoint;
    // Commit über ein Zeichen: Ende des Worts und Bytes des stehen bleibenden Zeichens.
    FCommitEnd: Integer;
    FCommitSuffixBytes: Integer;
    procedure Log(const AMessage: string);
    procedure Recheck;
    procedure TimerTick(Sender: TObject);
    procedure Commit(const AItem: TAtlasCompletionItem);
    procedure ApplyStyle(const ACaret: TRect);
    function CaretRect(out AWindow: HWND; out ARect: TRect): Boolean;
    procedure ActiveChanged;
    procedure UpdateDetails;
    procedure ChangeOverload(ADelta: Integer);
    procedure SkipAutoParen(const AView: IOTAEditView; ARemoveAt: Integer);
    procedure UpdatePreview;
    procedure HideDetails;
    procedure InstallKeyHook;
    procedure RemoveKeyHook;
    /// <summary>Gehört die Taste gerade dem Popup?</summary>
    function WantsKey(AKey: TAtlasNavigationKey): Boolean;
  public
    /// <summary>Nach dem Übernehmen mit Klammern den Parameter-Hint öffnen (#430).</summary>
    property OnOpenSignature: TProc read FOnOpenSignature write FOnOpenSignature;
    constructor Create(const ASession: TAtlasSessionFunc; const ALog: TAtlasLogProc);
    destructor Destroy; override;
    /// <summary>Öffnet die Vervollständigung an der Cursorstelle von AView; False, wenn nicht möglich.
    /// AAutomatic: von der IDE nach einem Zeichen ausgelöst, nicht über Strg+Leer. Steht dann "[" vor dem
    /// Cursor, fragt Atlas nur nach Mengenwerten (#448).</summary>
    function Invoke(const AView: IOTAEditView; AAutomatic: Boolean = False): Boolean;
    procedure Close;
    /// <summary>Taste aus dem Tastatur-Hook; True, wenn verbraucht.</summary>
    function HandleKey(AKey: TAtlasNavigationKey): Boolean;
    /// <summary>Befehle im offenen Popup: Strg+Q Panel ein/aus (#428), Alt+1 … Alt+6 Chips (#422).</summary>
    function WantsCommand(AKey: Word; AShift: TShiftState): Boolean;
    procedure HandleCommand(AKey: Word; AShift: TShiftState);
    /// <summary>Editortext wurde geändert.</summary>
    procedure EditorModified(const AView: IOTAEditView);
    /// <summary>Bricht laufende Serveranfragen ab und wartet auf sie; vor dem Freigeben der Sitzung.</summary>
    procedure Shutdown;
    function Visible: Boolean;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Winapi.Messages,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Vcl.Forms,
  DockForm,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Completion.Word,
  Atlas.Core.Completion.Matching,
  Atlas.Core.Completion.Providers.XmlDoc,
  Atlas.Core.Completion.Preview,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Completion.History,
  Atlas.IDE.Signature.Editor,
  Atlas.Core.Completion.Ranking,
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Editor.Style;

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


type
  TAtlasEditNotifier = class(TNotifierObject, INTAEditServicesNotifier)
  private
    FOwner: TAtlasEditorCompletion;
  public
    constructor Create(AOwner: TAtlasEditorCompletion);
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
  TCompletionKeys = class(TAtlasKeyClient)
  private
    FOwner: TAtlasEditorCompletion;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  public
    constructor Create(AOwner: TAtlasEditorCompletion);
  end;

function NavigationKey(AKey: Word; out ANavigation: TAtlasNavigationKey): Boolean;
begin
  Result := True;
  case AKey of
    VK_UP: ANavigation := TAtlasNavigationKey.Up;
    VK_DOWN: ANavigation := TAtlasNavigationKey.Down;
    VK_PRIOR: ANavigation := TAtlasNavigationKey.PageUp;
    VK_NEXT: ANavigation := TAtlasNavigationKey.PageDown;
    VK_HOME: ANavigation := TAtlasNavigationKey.First;
    VK_END: ANavigation := TAtlasNavigationKey.Last;
    VK_RETURN, VK_TAB: ANavigation := TAtlasNavigationKey.Accept;
    VK_ESCAPE: ANavigation := TAtlasNavigationKey.Cancel;
    // Mengenmodus (#448): anhaken; sonst gehört die Leertaste dem Editor (WantsKey).
    VK_SPACE: ANavigation := TAtlasNavigationKey.Toggle;
  else
    Result := False;
  end;
end;

{ TCompletionKeys }

constructor TCompletionKeys.Create(AOwner: TAtlasEditorCompletion);
begin
  inherited Create(0);
  FOwner := AOwner;
end;

function TCompletionKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
var
  Navigation: TAtlasNavigationKey;
begin
  Result := ((AShift = []) and NavigationKey(AKey, Navigation) and FOwner.WantsKey(Navigation)) or
    FOwner.WantsCommand(AKey, AShift);
end;

procedure TCompletionKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  Navigation: TAtlasNavigationKey;
begin
  try
    if FOwner.WantsCommand(AKey, AShift) then
      FOwner.HandleCommand(AKey, AShift)
    else if NavigationKey(AKey, Navigation) then
      FOwner.HandleKey(Navigation);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
  end;
end;
{ TAtlasEditNotifier }

constructor TAtlasEditNotifier.Create(AOwner: TAtlasEditorCompletion);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TAtlasEditNotifier.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
begin
end;

procedure TAtlasEditNotifier.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
end;

procedure TAtlasEditNotifier.WindowActivated(const EditWindow: INTAEditWindow);
begin
end;

procedure TAtlasEditNotifier.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);
begin
end;

procedure TAtlasEditNotifier.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  // Tab-Wechsel schließt (#414).
  try
    FOwner.Close;
  except
  end;
end;

procedure TAtlasEditNotifier.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  try
    FOwner.EditorModified(EditView);
  except
  end;
end;

procedure TAtlasEditNotifier.DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TAtlasEditNotifier.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TAtlasEditNotifier.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

{ TAtlasEditorCompletion }

constructor TAtlasEditorCompletion.Create(const ASession: TAtlasSessionFunc; const ALog: TAtlasLogProc);
var
  Editor: IOTAEditorServices;
  Notifier: INTAEditServicesNotifier;
begin
  inherited Create;
  FLog := ALog;
  FNotifierIndex := -1;
  FCommitEnd := -1;
  FProviders := TAtlasCompletionProviders.Create;
  FProvidersRef := FProviders;
  FServerProvider := TAtlasServerCompletionProvider.Create(ASession);
  FServerProviderRef := FServerProvider;
  FProviders.Add(FServerProviderRef);
  // XMLDoc-Tags in ///-Kommentaren (#435), lokal.
  FProviders.Add(TAtlasXmlDocCompletionProvider.Create as IAtlasCompletionProvider);
  FPopup := TAtlasCompletionPopup.Create(nil);
  FController := TAtlasCompletionController.Create(FProvidersRef, FPopup);
  FController.OnCommit :=
    procedure(const AItem: TAtlasCompletionItem)
    begin
      // Die zuletzt gezeigte Überladung gilt auch im Parameter-Hint (#425, #437).
      TAtlasEditorSignature.PreferOverload(AItem.Name, FOverloadIndex);
      Commit(AItem);
      if FController.Usage <> nil then
        TAtlasIdeHistory.Committed;
    end;
  FPopup.OnSelect :=
    procedure(APosition: Integer)
    begin
      FController.Select(APosition);
    end;
  FPopup.OnOverload :=
    procedure(ADelta: Integer)
    begin
      ChangeOverload(ADelta);
    end;
  FPopup.OnChip :=
    procedure(AChip: TAtlasChip)
    begin
      FController.SelectChip(AChip);
    end;
  FPopup.OnAccept :=
    procedure(APosition: Integer)
    begin
      FController.Select(APosition);
      FController.CommitSelected;
    end;
  // Gezogene Breiten (#416) und eingeklapptes Panel (#428) gelten auch beim nächsten Mal.
  FPopup.OnWidthsChanged :=
    procedure(AListWidth, APanelWidth: Integer)
    var
      Settings: TAtlasPluginSettings;
    begin
      Settings := TAtlasIdeSettings.Current;
      Settings.ListWidth := AListWidth;
      Settings.PanelWidth := APanelWidth;
      TAtlasIdeSettings.Update(Settings);
    end;
  FPopup.OnPanelToggled :=
    procedure(ACollapsed: Boolean)
    var
      Settings: TAtlasPluginSettings;
    begin
      Settings := TAtlasIdeSettings.Current;
      Settings.PanelCollapsed := ACollapsed;
      TAtlasIdeSettings.Update(Settings);
    end;
  FKeys := TCompletionKeys.Create(Self);
  FPreview := TAtlasEditorPreview.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := 50;
  FTimer.OnTimer := TimerTick;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editor) then
  begin
    Notifier := TAtlasEditNotifier.Create(Self);
    FNotifierIndex := Editor.AddNotifier(Notifier);
  end;
end;

destructor TAtlasEditorCompletion.Destroy;
var
  Editor: IOTAEditorServices;
begin
  // Erst abmelden, dann freigeben: Die IDE ruft sonst noch in freigegebene Objekte (#493).
  RemoveKeyHook;
  FreeAndNil(FPreview);
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

procedure TAtlasEditorCompletion.Log(const AMessage: string);
begin
  if Assigned(FLog) then
    FLog(AMessage);
end;

procedure TAtlasEditorCompletion.Shutdown;
begin
  Close;
  FServerProvider.Shutdown;
end;

function TAtlasEditorCompletion.Visible: Boolean;
begin
  // Auch der leere Zustand (#423) nimmt Esc entgegen.
  Result := FController.Visible or FController.Empty;
end;

procedure TAtlasEditorCompletion.ApplyStyle(const ACaret: TRect);
begin
  // Farben aus dem Thema der IDE (hell/dunkel), Schrift aus den Editoroptionen, Monitor-DPI und Zoom
  // am Caret (#411, #412, #445).
  Log(TAtlasIdeStyle.Apply(FPopup, ACaret));
end;

function TAtlasEditorCompletion.CaretRect(out AWindow: HWND; out ARect: TRect): Boolean;
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

function TAtlasEditorCompletion.Invoke(const AView: IOTAEditView; AAutomatic: Boolean): Boolean;
var
  Context: TAtlasContext;
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
  LineText := TAtlasEditorBuffer.LineText(AView, Cursor.Line);
  Character := TLspSession.ColumnToIndex(LineText, Cursor.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer));
  WordStart := TAtlasWord.StartBefore(LineText, Character);
  if not CaretRect(Window, Anchor) then
  begin
    Log('Vervollständigung: kein Caret gefunden');
    Exit;
  end;
  Context := Default(TAtlasContext);
  Context.FileName := AView.Buffer.FileName;
  Context.Text := TAtlasEditorBuffer.Text(AView.Buffer);
  Context.Line := Cursor.Line - 1;
  Context.Character := Character;
  Context.Prefix := Copy(LineText, WordStart + 1, Character - WordStart);
  if (WordStart > 0) and (LineText[WordStart] = '.') then
    Context.Kind := TAtlasContextKind.MemberAccess
  else
    Context.Kind := TAtlasContextKind.Identifier;
  // Nach "[" automatisch geöffnet (#448): nur ein Mengenkonstruktor bekommt eine Liste.
  if AAutomatic and (Character > 0) and (Character <= Length(LineText)) and (LineText[Character] = '[') then
    Context.Trigger := '[';
  ApplyStyle(Anchor);
  FPopup.VisibleRows := TAtlasIdeSettings.Current.VisibleRows;
  FPopup.ManualListWidth := TAtlasIdeSettings.Current.ListWidth;
  FPopup.PanelWidthSetting := TAtlasIdeSettings.Current.PanelWidth;
  FPopup.PanelCollapsed := TAtlasIdeSettings.Current.PanelCollapsed;
  // Gruppen geerbter Member (#419), Chips (#422), lernende Gewichtung (#418).
  FController.GroupInherited := TAtlasIdeSettings.Current.GroupInherited;
  FPopup.DimInherited := TAtlasIdeSettings.Current.GroupInherited;
  FController.ChipsEnabled := TAtlasIdeSettings.Current.FilterChips;
  if TAtlasIdeSettings.Current.Learning then
    FController.Usage := TAtlasIdeHistory.Instance
  else
    FController.Usage := nil;
  // Das Popup beginnt am Wortanfang, nicht am Caret.
  FPopup.Canvas.Font := FPopup.Font;
  Anchor.Left := Anchor.Left - FPopup.Canvas.TextWidth(Context.Prefix);
  FPopup.Anchor := Anchor;
  FView := AView;
  FEditorWindow := Window;
  FLine := Cursor.Line;
  FWordStart := WordStart;
  FTopRow := AView.TopRow;
  FEditorSize := EditorSize(FEditorWindow);
  Log(Format('Vervollständigung in %s, Zeile %d, Zeichen %d, Präfix "%s"',
    [ExtractFileName(Context.FileName), Context.Line + 1, Context.Character, Context.Prefix]));
  FController.Start(Context);
  ActiveChanged;
  Result := True;
end;

procedure TAtlasEditorCompletion.Close;
begin
  FController.Close;
  if FPreview <> nil then
    FPreview.Clear;
  ActiveChanged;
end;

procedure TAtlasEditorCompletion.ActiveChanged;
begin
  FTimer.Enabled := FController.Active;
  if not FController.Active and (FPreview <> nil) then
    FPreview.Clear;
  if FController.Active then
    InstallKeyHook
  else
  begin
    RemoveKeyHook;
    HideDetails;
    FView := nil;
  end;
end;

procedure TAtlasEditorCompletion.InstallKeyHook;
begin
  TAtlasKeyHook.Add(FKeys);
  if not TAtlasKeyHook.Installed then
    Log('Vervollständigung: Tastatur-Hook nicht möglich: ' + SysErrorMessage(GetLastError));
end;

procedure TAtlasEditorCompletion.RemoveKeyHook;
begin
  TAtlasKeyHook.Remove(FKeys);
end;

function TAtlasEditorCompletion.WantsKey(AKey: TAtlasNavigationKey): Boolean;
begin
  // Liste offen: alle Navigationstasten, die Leertaste nur im Mengenmodus (#448). Leerer Zustand (#423): nur Esc.
  if AKey = TAtlasNavigationKey.Toggle then
    Result := FController.Visible and FController.SetMode
  else
    Result := FController.Visible or (FController.Empty and (AKey = TAtlasNavigationKey.Cancel));
end;

function TAtlasEditorCompletion.WantsCommand(AKey: Word; AShift: TShiftState): Boolean;
var
  Item: TAtlasCompletionItem;
begin
  // Strg+Q Panel (#428), Alt+1 … Alt+6 Chips (#422).
  Result := FController.Visible and (((AKey = Ord('Q')) and (AShift = [ssCtrl])) or
    (((AKey = VK_UP) or (AKey = VK_DOWN)) and (AShift = [ssAlt]) and FController.SelectedItem(Item) and
      (Item.OverloadCount > 1)) or
    (FController.ChipsEnabled and (AKey >= Ord('1')) and (AKey <= Ord('6')) and (AShift = [ssAlt])));
end;

procedure TAtlasEditorCompletion.HandleCommand(AKey: Word; AShift: TShiftState);
begin
  if (AKey = Ord('Q')) and (AShift = [ssCtrl]) then
    FPopup.TogglePanel
  else if (AKey = VK_UP) and (AShift = [ssAlt]) then
    ChangeOverload(-1)
  else if (AKey = VK_DOWN) and (AShift = [ssAlt]) then
    ChangeOverload(1)
  else if (AKey >= Ord('1')) and (AKey <= Ord('6')) then
    FController.SelectChipAt(AKey - Ord('1'));
end;

function TAtlasEditorCompletion.HandleKey(AKey: TAtlasNavigationKey): Boolean;
begin
  Result := FController.HandleKey(AKey);
  ActiveChanged;
end;

procedure TAtlasEditorCompletion.EditorModified(const AView: IOTAEditView);
var
  RemoveAt: Integer;
begin
  if FController.Active then
    Recheck;
  // ")" vor der automatischen Klammer (#430): diese überspringen.
  if FAutoParen.Active and (AView <> nil) and (AView.Buffer <> nil) then
    if AView.CursorPos.Line <> FAutoParen.Line then
      FAutoParen.Stop
    else
    begin
      FAutoParen.Update(TAtlasEditorBuffer.LineText(AView, FAutoParen.Line), RemoveAt);
      if RemoveAt >= 0 then
        SkipAutoParen(AView, RemoveAt);
    end;
end;

procedure TAtlasEditorCompletion.SkipAutoParen(const AView: IOTAEditView; ARemoveAt: Integer);
var
  View: IOTAEditView;
  Line: Integer;
begin
  View := AView;
  Line := FAutoParen.Line;
  if Line = 0 then
    Line := View.CursorPos.Line;
  // Nicht im Benachrichtigungsaufruf selbst ändern, sondern gleich danach.
  TThread.ForceQueue(nil,
    procedure
    var
      Text: string;
      Offset: Integer;
      Writer: IOTAEditWriter;
      Cursor: TOTAEditPos;
    begin
      Text := TAtlasEditorBuffer.Text(View.Buffer);
      Offset := TAtlasEditorBuffer.ByteOffset(Text, Line - 1, ARemoveAt);
      Cursor := View.CursorPos;
      Writer := View.Buffer.CreateUndoableWriter;
      Writer.CopyTo(Offset);
      Writer.DeleteTo(Offset + 1);
      Writer := nil;
      View.CursorPos := Cursor;
      View.Paint;
    end);
end;

procedure TAtlasEditorCompletion.HideDetails;
begin
  FPopup.ClearDetails;
  FDetailKey := '';
  FDetailRequested := False;
end;

procedure TAtlasEditorCompletion.UpdateDetails;
var
  Item: TAtlasCompletionItem;
  Key: string;
  Resolver: IAtlasCompletionResolver;
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
    FOverloadIndex := 0;
    FPopup.SetOverload(0, Item.OverloadCount);
    FDetailDue := TThread.GetTickCount64 + 80;
    FDetailRequested := False;
    Exit;
  end;
  if FDetailRequested or (TThread.GetTickCount64 < FDetailDue) then
    Exit;
  FDetailRequested := True;
  // Überladung (#425): deren Position statt der ersten nachfragen.
  if (FOverloadIndex > 0) and (FOverloadIndex <= Length(Item.OverloadData)) then
    Item.ResolveData := Item.OverloadData[FOverloadIndex - 1];
  if not Supports(FServerProviderRef, IAtlasCompletionResolver, Resolver) or not Resolver.Resolve(Item,
    procedure(const ADetails: TAtlasItemDetails)
    begin
      // Nur zeigen, wenn noch derselbe Eintrag gewählt und die Liste offen ist.
      if (FDetailKey = Key) and FController.Visible then
        FPopup.ShowDetails(ADetails);
    end) then
    FPopup.ClearDetails;
end;

procedure TAtlasEditorCompletion.ChangeOverload(ADelta: Integer);
var
  Item: TAtlasCompletionItem;
begin
  if not FController.SelectedItem(Item) or (Item.OverloadCount < 2) then
    Exit;
  FOverloadIndex := (FOverloadIndex + ADelta + Item.OverloadCount) mod Item.OverloadCount;
  FPopup.SetOverload(FOverloadIndex, Item.OverloadCount);
  // Sofort nachfragen, ohne die 80 ms Ruhe beim Blättern in der Liste.
  FDetailRequested := False;
  FDetailDue := 0;
  UpdateDetails;
end;

procedure TAtlasEditorCompletion.UpdatePreview;
var
  Item: TAtlasCompletionItem;
  LineText, Text: string;
  Character: Integer;
begin
  if FPreview = nil then
    Exit;
  Text := '';
  if TAtlasIdeSettings.Current.Preview and FController.Visible and FController.SelectedItem(Item) and
    (FView <> nil) and (FView.Buffer <> nil) and (FView.CursorPos.Line = FLine) then
  begin
    LineText := TAtlasEditorBuffer.LineText(FView, FLine);
    Character := TLspSession.ColumnToIndex(LineText, FView.CursorPos.Col, TAtlasEditorBuffer.TabWidth(FView.Buffer));
    Text := TAtlasPreview.RestOf(Item.Name, FController.Prefix, Copy(LineText, Character + 1, MaxInt));
  end;
  if Text = '' then
    FPreview.Clear
  else
    FPreview.Show(FView.Buffer.FileName, FLine, FView.CursorPos.Col, Text);
end;

procedure TAtlasEditorCompletion.TimerTick(Sender: TObject);
begin
  try
    Recheck;
    UpdateDetails;
    UpdatePreview;
  except
    on E: Exception do
    begin
      Log('Vervollständigung: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
      Close;
    end;
  end;
end;

procedure TAtlasEditorCompletion.Recheck;
var
  Cursor: TOTAEditPos;
  LineText, Prefix: string;
  Character, Index: Integer;
  Context: TAtlasContext;
begin
  if not FController.Active or (FView = nil) then
  begin
    ActiveChanged;
    Exit;
  end;
  // IDE inaktiv, anderes Fenster im Fokus, gescrollt: schließen (#414).
  if not Application.Active or (GetFocus <> FEditorWindow) or (FView.TopRow <> FTopRow) or
    (EditorSize(FEditorWindow) <> FEditorSize) then
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
  LineText := TAtlasEditorBuffer.LineText(FView, Cursor.Line);
  Character := TLspSession.ColumnToIndex(LineText, Cursor.Col, TAtlasEditorBuffer.TabWidth(FView.Buffer));
  // Cursor vor dem Wortanfang oder ein Zeichen, das kein Bezeichner ist: Wort verlassen.
  if Character < FWordStart then
  begin
    Close;
    Exit;
  end;
  for Index := FWordStart + 1 to Character do
    if not TAtlasWord.IsIdentifierChar(LineText[Index]) then
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
  // Gekürzte Liste (#431) oder Wort nicht mehr Fortsetzung der Anfrage (Rücktaste, #616): lokal weiterfiltern
  // und im Hintergrund neu fragen. Sonst nur lokal; der Server wird beim Tippen nicht mehr gefragt.
  if (Prefix <> FController.Prefix) and FController.NeedsQuery(Prefix) then
  begin
    Context := Default(TAtlasContext);
    Context.FileName := FView.Buffer.FileName;
    Context.Text := TAtlasEditorBuffer.Text(FView.Buffer);
    Context.Line := Cursor.Line - 1;
    Context.Character := Character;
    Context.Prefix := Prefix;
    if (FWordStart > 0) and (LineText[FWordStart] = '.') then
      Context.Kind := TAtlasContextKind.MemberAccess
    else
      Context.Kind := TAtlasContextKind.Identifier;
    FController.Requery(Context);
  end
  else
    FController.UpdatePrefix(Prefix);
  ActiveChanged;
end;

procedure TAtlasEditorCompletion.Commit(const AItem: TAtlasCompletionItem);
var
  View: IOTAEditView;
  Text, NewText, LineText: string;
  Edits: TList<TPendingEdit>;
  Edit: TPendingEdit;
  TextEdit: TAtlasTextEdit;
  Writer: IOTAEditWriter;
  Cursor: TOTAEditPos;
  Character, Shift, CursorByte, CaretMarker: Integer;
  NextChar: Char;
  AutoParen: Boolean;
  CharPos: TOTACharPos;
begin
  View := FView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Cursor := View.CursorPos;
  LineText := TAtlasEditorBuffer.LineText(View, Cursor.Line);
  Character := TLspSession.ColumnToIndex(LineText, Cursor.Col, TAtlasEditorBuffer.TabWidth(View.Buffer));
  // Über ein Commit-Zeichen: Das Wort endet davor, das Zeichen bleibt stehen.
  if FCommitEnd >= 0 then
    Character := FCommitEnd
  else
    // Mitten im Wort: bis zu seinem Ende ersetzen, sonst bliebe der Rest stehen.
    Character := TAtlasWord.EndAfter(LineText, Character);
  NewText := AItem.InsertText;
  if NewText = '' then
    NewText := AItem.Name;
  // Schreibweise (#433): abgeschaltet bleibt das Getippte, nur der Rest kommt dazu.
  if (FWordStart >= 0) and (Character >= FWordStart) then
    NewText := TAtlasCompletionMatcher.CommitText(Copy(LineText, FWordStart + 1, Character - FWordStart), NewText,
      TAtlasIdeSettings.Current.FixCase);
  if AItem.HasTextEdit then
    NewText := AItem.TextEdit.NewText;
  // Klammern (#430): Methode mit Parametern, nicht über ein Commit-Zeichen, keine "(" dahinter.
  if Character < Length(LineText) then
    NextChar := LineText[Character + 1]
  else
    NextChar := #0;
  AutoParen := TAtlasIdeSettings.Current.AutoParentheses and (FCommitEnd < 0) and (Pos('$0', NewText) = 0) and
    not AItem.HasTextEdit and
    TAtlasParentheses.Wanted(AItem.Kind in [TAtlasItemKind.Method, TAtlasItemKind.Function_,
      TAtlasItemKind.Procedure_, TAtlasItemKind.Constructor_], AItem.HasParameters, NextChar);
  if AutoParen then
    NewText := NewText + '($0)';
  // "$0" im Einfügetext (XMLDoc-Tags, #435, Klammern): dort steht der Cursor danach.
  CaretMarker := Pos('$0', NewText);
  if CaretMarker > 0 then
    Delete(NewText, CaretMarker, 2);
  Edits := TList<TPendingEdit>.Create;
  try
    // Das getippte Wort durch den Eintrag ersetzen; mit textEdit ab dessen Anfang (Postfix-Vorlagen, #188).
    if AItem.HasTextEdit then
      Edit.Start := TAtlasEditorBuffer.ByteOffset(Text, AItem.TextEdit.StartLine, AItem.TextEdit.StartCharacter)
    else
      Edit.Start := TAtlasEditorBuffer.ByteOffset(Text, Cursor.Line - 1, FWordStart);
    Edit.Stop := TAtlasEditorBuffer.ByteOffset(Text, Cursor.Line - 1, Character);
    // Reicht der textEdit über das Wort hinaus (Mengenklammer bis "]", #448), bis zu seinem Ende ersetzen.
    if AItem.HasTextEdit then
      Edit.Stop := Max(Edit.Stop, TAtlasEditorBuffer.ByteOffset(Text, AItem.TextEdit.EndLine,
        AItem.TextEdit.EndCharacter));
    Edit.Text := NewText;
    Edit.IsWord := True;
    Edits.Add(Edit);
    // uses-Ergänzung u. ä. (#180).
    for TextEdit in AItem.AdditionalEdits do
    begin
      Edit.Start := TAtlasEditorBuffer.ByteOffset(Text, TextEdit.StartLine, TextEdit.StartCharacter);
      Edit.Stop := TAtlasEditorBuffer.ByteOffset(Text, TextEdit.EndLine, TextEdit.EndCharacter);
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
      Log(Format('  Änderung Byte %d bis %d (Wortanfang %d, Zeile %d, Ende %d): "%s"',
        [Edit.Start, Edit.Stop, FWordStart, Cursor.Line, Character, Edit.Text]));
      Writer.CopyTo(Edit.Start);
      Writer.DeleteTo(Edit.Stop);
      Writer.Insert(PAnsiChar(UTF8Encode(Edit.Text)));
      if Edit.IsWord then
      begin
        if CaretMarker > 0 then
          CursorByte := Edit.Start + Shift + Length(UTF8Encode(Copy(Edit.Text, 1, CaretMarker - 1)))
        else
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
  if AutoParen and (CursorByte >= 0) then
  begin
    // Die ")" steht direkt hinter dem Cursor; ihre Lage verfolgen und den Hint öffnen.
    LineText := TAtlasEditorBuffer.LineText(View, View.CursorPos.Line);
    FAutoParen := TAtlasAutoParen.Start(View.CursorPos.Line, TLspSession.ColumnToIndex(LineText,
      View.CursorPos.Col, TAtlasEditorBuffer.TabWidth(View.Buffer)), LineText);
    if Assigned(FOnOpenSignature) then
      TThread.ForceQueue(nil,
        procedure
        begin
          if Assigned(FOnOpenSignature) then
            FOnOpenSignature();
        end);
  end;
  Log(Format('Übernommen: %s (%d weitere Änderungen)', [AItem.Name, Length(AItem.AdditionalEdits)]));
  ActiveChanged;
end;

end.
