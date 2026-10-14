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
//   - Code-Vorlagen (#51): eigene Quelle mit den mitgelieferten Vorlagen, den Live Templates
//     der IDE (abschaltbar, ImportIdeTemplates) und denen aus %APPDATA%\Atlas\Snippets (bei
//     Änderung neu gelesen; eigene vor IDE vor mitgelieferten). Übernehmen setzt den Text mit der
//     Einrückung der Zeile ein und startet den Platzhalter-Modus (Atlas.IDE.Completion.Placeholders).

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
  Atlas.Core.Completion.Providers.Snippets,
  Atlas.Core.Completion.Parentheses,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Editor.CloseRules,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Completion.Preview,
  Atlas.IDE.Completion.Placeholders,
  Atlas.UI.Completion.Popup,
  Atlas.IDE.Editor.KeyHook;

type
  /// <summary>Protokoll für die Diagnose (Registry-Wert Diagnose).</summary>
  TAtlasLogProc = reference to procedure(const AMessage: string);

  TAtlasEditorCompletion = class
  private
    FSession: TAtlasSessionFunc;
    FProviders: TAtlasCompletionProviders;
    FProvidersRef: IAtlasCompletionProvider;
    FServerProvider: TAtlasServerCompletionProvider;
    FServerProviderRef: IAtlasCompletionProvider;
    // Code-Vorlagen (#51): Quelle, Stand des Ordners, letzte Prüfung, Platzhalter-Modus.
    FSnippetProvider: TAtlasSnippetCompletionProvider;
    FSnippetProviderRef: IAtlasCompletionProvider;
    // Eigene Postfix-Vorlagen (#188): gehen an den Server, neu nach Änderung, neuem Server oder einer Minute.
    FPostfixSnippets: TAtlasSnippetList;
    FPostfixSession: TLspSession;
    FPostfixSent: UInt64;
    FSnippetStamp: string;
    FSnippetChecked: UInt64;
    FPlaceholders: TAtlasEditorPlaceholders;
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
    // Verzögertes automatisches Öffnen (ARG-046): Ansicht, Zeile, Zeichen und Fenster beim Auslösen.
    FDelayTimer: TTimer;
    FDelayView: IOTAEditView;
    FDelayLine: Integer;
    FDelayCharacter: Integer;
    FDelayWindow: HWND;
    FDelayState: TAtlasEditorWindowState;
    FDelayed: Boolean;
    FKeys: TAtlasKeyClient;
    FNotifierIndex: Integer;
    FLog: TAtlasLogProc;
    // Zustand der offenen Vervollständigung.
    FView: IOTAEditView;
    FEditorWindow: HWND;
    FLine: Integer;
    FWordStart: Integer;
    // Fenster beim Öffnen (Fokus, oberste Zeile, Größe); TAtlasCloseRules vergleicht damit (#414).
    FOpened: TAtlasEditorWindowState;
    // Commit über ein Zeichen: Ende des Worts und Bytes des stehen bleibenden Zeichens.
    FCommitEnd: Integer;
    FCommitSuffixBytes: Integer;
    /// <summary>Freigabe absichern (#489): Zeile (ab 1) und Datei des zuletzt übernommenen Konstruktors; 0 ohne.</summary>
    FGuardLine: Integer;
    FGuardFile: string;
    /// <summary>Das nächste automatische Öffnen kommt vom Enter am Ende der Zeile FGuardLine (#489).</summary>
    FGuardNewLine: Boolean;
    procedure Log(const AMessage: string);
    procedure Recheck;
    procedure TimerTick(Sender: TObject);
    procedure DelayTimerTick(Sender: TObject);
    procedure CancelDelay;
    procedure Commit(const AItem: TAtlasCompletionItem);
    /// <summary>Setzt die Vorlage von AItem statt des Worts bis AEnd (0-basiert) ein.</summary>
    procedure CommitSnippet(const AView: IOTAEditView; const AItem: TAtlasCompletionItem; const AText,
      ALineText: string; ALine, AEnd: Integer);
    /// <summary>Eigene Vorlagen neu lesen, wenn sich der Ordner geändert hat (höchstens alle 3 s).</summary>
    procedure RefreshSnippets;
    /// <summary>Eigene Postfix-Vorlagen (#188) an den Server schicken (atlas/postfixTemplates).</summary>
    procedure SendPostfixTemplates;
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
    /// <summary>Indiziert der Server gerade (#492)?</summary>
    function IndexingNow: Boolean;
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
    /// <summary>Andere Ansicht im Editor: Popup schließen und Platzhalter-Modus beenden.</summary>
    procedure ViewChanged;
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
    /// <summary>Wurde in der Zeile des Cursors gerade ein Konstruktor übernommen (#489)? Dann fragt ";" dort
    /// nach „Mit try…finally absichern“.</summary>
    function GuardPending(const AView: IOTAEditView): Boolean;
    /// <summary>Ordner der eigenen Code-Vorlagen (#51): %APPDATA%\Atlas\Snippets.</summary>
    class function SnippetFolder: string; static;
    /// <summary>Live Templates der laufenden IDE (#51); '' ohne Version.</summary>
    class function IdeTemplateFolder: string; static;
    /// <summary>Hat Enter die Zeile des übernommenen Konstruktors gerade beendet (#489)? Der Cursor steht dann
    /// in einer leeren Zeile direkt darunter.</summary>
    function GuardNewLine(const AView: IOTAEditView): Boolean;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Winapi.Messages,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Vcl.Forms,
  Vcl.Clipbrd,
  Winapi.ShellAPI,
  System.StrUtils,
  DockForm,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Documentation.Layout,
  Atlas.IDE.Hover.Editor,
  Atlas.Core.Completion.Word,
  Atlas.Core.Completion.Matching,
  Atlas.Core.Completion.Providers.XmlDoc,
  Atlas.Core.Completion.LiveTemplates,
  Atlas.Core.Projects.Context,
  Atlas.Core.Completion.Preview,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Completion.History,
  Atlas.IDE.Signature.Editor,
  Atlas.Core.Completion.Ranking,
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Editor.Style,
  Atlas.UI.Strings;

/// <summary>Plattform und Konfiguration des aktiven Projekts („Win32 · Debug“, #476); '' ohne Projekt.</summary>
function ActiveTarget: string;
var
  Project: IOTAProject;
begin
  Result := '';
  Project := GetActiveProject;
  if Project = nil then
    Exit;
  Result := Project.CurrentPlatform;
  if Project.CurrentConfiguration <> '' then
    if Result <> '' then
      Result := Result + ' · ' + Project.CurrentConfiguration
    else
      Result := Project.CurrentConfiguration;
end;

/// <summary>Anzeige der XMLDoc im Panel (#654): hints aus atlas.json meldet der Server, sonst die Optionen.</summary>
function WithDisplay(const ADetails: TAtlasItemDetails): TAtlasItemDetails;
var
  Full: Boolean;
begin
  Result := ADetails;
  if not Result.Display.Known then
    Result.Display := TAtlasDocDisplay.Create(TAtlasIdeSettings.Current.XmlDocFull,
      TAtlasIdeSettings.Current.XmlDocMaxLines);
  // Schnellschalter nur für diese Sitzung (#604) gilt auch über dem Wert aus atlas.json.
  if TAtlasIdeSettings.SessionFlag('XmlDocFull', Full) then
    Result.Display.Full := Full;
end;

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

/// <summary>Zustand für TAtlasCloseRules (#414); AWindow ist das Editorfenster mit dem Caret.</summary>
function WindowState(const AView: IOTAEditView; AWindow: HWND; AFocus: HWND): TAtlasEditorWindowState;
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
    FOwner.ViewChanged;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
  end;
end;

procedure TAtlasEditNotifier.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  try
    FOwner.EditorModified(EditView);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
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
  FSession := ASession;
  FLog := ALog;
  FNotifierIndex := -1;
  FCommitEnd := -1;
  FProviders := TAtlasCompletionProviders.Create;
  FProvidersRef := FProviders;
  FServerProvider := TAtlasServerCompletionProvider.Create(ASession);
  FServerProvider.OnLog :=
    procedure(const AMessage: string)
    begin
      Log(AMessage);
    end;
  FServerProviderRef := FServerProvider;
  FProviders.Add(FServerProviderRef);
  // XMLDoc-Tags in ///-Kommentaren (#435), lokal.
  FProviders.Add(TAtlasXmlDocCompletionProvider.Create as IAtlasCompletionProvider);
  // Code-Vorlagen (#51), lokal; die eigenen liest RefreshSnippets beim ersten Öffnen.
  FSnippetProvider := TAtlasSnippetCompletionProvider.Create(TAtlasSnippets.BuiltIn);
  FSnippetProviderRef := FSnippetProvider;
  FProviders.Add(FSnippetProviderRef);
  FPlaceholders := TAtlasEditorPlaceholders.Create;
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
  // XMLDoc im Panel (#654): Links im Browser, Verweise mit Strg+Klick zur Deklaration.
  FPopup.OnDocLink :=
    procedure(const ALink: TAtlasDocLink; AControl: Boolean)
    begin
      if ALink.Kind = TAtlasDocLinkKind.Url then
      begin
        if StartsText('http://', ALink.Url) or StartsText('https://', ALink.Url) or
          StartsText('mailto:', ALink.Url) then
          ShellExecute(0, 'open', PChar(ALink.Url), nil, nil, SW_SHOWNORMAL);
      end
      else if AControl and ALink.Target.HasLocation then
      begin
        Close;
        TAtlasEditorHover.GoToLocation(ALink.Target.FileName, ALink.Target.Line, ALink.Target.Character);
      end;
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
      Settings := TAtlasIdeSettings.Stored;
      Settings.ListWidth := AListWidth;
      Settings.PanelWidth := APanelWidth;
      TAtlasIdeSettings.Update(Settings);
    end;
  FPopup.OnPanelToggled :=
    procedure(ACollapsed: Boolean)
    var
      Settings: TAtlasPluginSettings;
    begin
      Settings := TAtlasIdeSettings.Stored;
      Settings.PanelCollapsed := ACollapsed;
      TAtlasIdeSettings.Update(Settings);
    end;
  FKeys := TCompletionKeys.Create(Self);
  FPreview := TAtlasEditorPreview.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := 50;
  FTimer.OnTimer := TimerTick;
  FDelayTimer := TTimer.Create(nil);
  FDelayTimer.Enabled := False;
  FDelayTimer.OnTimer := DelayTimerTick;
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
  FreeAndNil(FPlaceholders);
  FreeAndNil(FPreview);
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, Editor) then
    Editor.RemoveNotifier(FNotifierIndex);
  FTimer.Free;
  FDelayTimer.Free;
  Shutdown;
  FController.Free;
  FPopup.Free;
  FKeys.Free;
  FServerProviderRef := nil;
  FSnippetProviderRef := nil;
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
  FSnippetProvider.Shutdown;
end;

function TAtlasEditorCompletion.IndexingNow: Boolean;
var
  Session: TLspSession;
begin
  Result := False;
  if not Assigned(FSession) then
    Exit;
  Session := FSession();
  Result := (Session <> nil) and (Session.IndexingText <> '');
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
  CancelDelay;
  // Verzögerung bis zum Öffnen (ARG-046): nur beim automatischen Auslösen; DelayTimerTick ruft wieder auf.
  if AAutomatic and not FDelayed and (TAtlasIdeSettings.Current.OpenDelayMs > 0) then
  begin
    FDelayView := AView;
    FDelayLine := Cursor.Line;
    FDelayCharacter := Character;
    FDelayWindow := Window;
    FDelayState := WindowState(AView, Window, Window);
    FDelayTimer.Interval := Cardinal(TAtlasIdeSettings.Current.OpenDelayMs);
    FDelayTimer.Enabled := True;
    Exit(True);
  end;
  Context := Default(TAtlasContext);
  Context.FileName := AView.Buffer.FileName;
  Context.Text := TAtlasEditorBuffer.Text(AView.Buffer);
  Context.Line := Cursor.Line - 1;
  Context.Character := Character;
  Context.Prefix := Copy(LineText, WordStart + 1, Character - WordStart);
  Context.Automatic := AAutomatic;
  // Mit Esc geschlossen (#414): im selben Wort nicht automatisch wieder öffnen.
  if AAutomatic and FController.Dismissed(Context) then
    Exit;
  if (WordStart > 0) and (LineText[WordStart] = '.') then
    Context.Kind := TAtlasContextKind.MemberAccess
  else
    Context.Kind := TAtlasContextKind.Identifier;
  // Nach "[" automatisch geöffnet (#448): nur ein Mengenkonstruktor bekommt eine Liste.
  if AAutomatic and (Character > 0) and (Character <= Length(LineText)) and (LineText[Character] = '[') then
    Context.Trigger := '['
  // Nach dem ";" hinter einem übernommenen Konstruktor (#489): nur „Mit try…finally absichern“.
  else if AAutomatic and (Character > 0) and (Character <= Length(LineText)) and (LineText[Character] = ';') and
    GuardPending(AView) then
  begin
    Context.Trigger := ';';
    FGuardLine := 0;
  end
  // Nach dem Zeilenende (Enter) hinter einem übernommenen Konstruktor ohne ";" (#489).
  else if AAutomatic and FGuardNewLine then
    Context.Trigger := #10;
  FGuardNewLine := False;
  ApplyStyle(Anchor);
  FPopup.VisibleRows := TAtlasIdeSettings.Current.VisibleRows;
  FPopup.ManualListWidth := TAtlasIdeSettings.Current.ListWidth;
  FPopup.PanelWidthSetting := TAtlasIdeSettings.Current.PanelWidth;
  FPopup.PanelCollapsed := TAtlasIdeSettings.Current.PanelCollapsed;
  // Gruppen geerbter Member (#419), Chips (#422), lernende Gewichtung (#418).
  FController.GroupInherited := TAtlasIdeSettings.Current.GroupInherited;
  FPopup.DimInherited := TAtlasIdeSettings.Current.GroupInherited;
  // Während der Server indiziert, liefert er den vorhandenen Stand; die Fußzeile sagt es (#492).
  FPopup.Limited := IndexingNow;
  FPopup.Target := ActiveTarget;
  FController.ChipsEnabled := TAtlasIdeSettings.Current.FilterChips;
  FSnippetProvider.Enabled := TAtlasIdeSettings.Current.Snippets;
  // Kontextabhängige Vorlagen des Servers (#51) hängen an derselben Einstellung.
  FServerProvider.Snippets := TAtlasIdeSettings.Current.Snippets;
  // Eigene Vorlagen auch ohne Code-Vorlagen in der Liste lesen: Postfix-Vorlagen (#188) hängen an
  // completion.postfixTemplates.
  RefreshSnippets;
  SendPostfixTemplates;
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
  FOpened := WindowState(AView, FEditorWindow, FEditorWindow);
  // Ohne Datei- und Bezeichnernamen: Das Diagnoselog soll weitergegeben werden können (#647).
  Log(Format('Vervollständigung (%s): Zeile %d, Zeichen %d, Präfix %d Zeichen',
    [ExtractFileExt(Context.FileName), Context.Line + 1, Context.Character, Length(Context.Prefix)]));
  FController.Start(Context);
  ActiveChanged;
  Result := True;
end;

procedure TAtlasEditorCompletion.CancelDelay;
begin
  FDelayTimer.Enabled := False;
  FDelayView := nil;
end;

procedure TAtlasEditorCompletion.DelayTimerTick(Sender: TObject);
var
  View: IOTAEditView;
  LineText: string;
  Character: Integer;
  Same: Boolean;
begin
  View := FDelayView;
  CancelDelay;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  try
    Same := View.CursorPos.Line = FDelayLine;
    LineText := TAtlasEditorBuffer.LineText(View, View.CursorPos.Line);
    Character := TLspSession.ColumnToIndex(LineText, View.CursorPos.Col, TAtlasEditorBuffer.TabWidth(View.Buffer));
    if not TAtlasCloseRules.DelayedOpen(FDelayState, WindowState(View, FDelayWindow, GetFocus), Same, LineText,
      FDelayCharacter, Character) then
    begin
      Log('Vervollständigung: verzögertes Öffnen verworfen');
      Exit;
    end;
    FDelayed := True;
    try
      Invoke(View, True);
    finally
      FDelayed := False;
    end;
  except
    on E: Exception do
    begin
      Log('Vervollständigung: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
    end;
  end;
end;

procedure TAtlasEditorCompletion.Close;
begin
  CancelDelay;
  FController.Close;
  if FPreview <> nil then
    FPreview.Clear;
  ActiveChanged;
end;

procedure TAtlasEditorCompletion.ViewChanged;
begin
  Close;
  if FPlaceholders <> nil then
    FPlaceholders.Stop;
end;

procedure TAtlasEditorCompletion.RefreshSnippets;
var
  Folder, IdeFolder, Stamp: string;
  Errors: TArray<string>;
  Own, Ide: TAtlasSnippetList;
  Stats: TAtlasLiveTemplateStats;
begin
  if (FSnippetChecked <> 0) and (TThread.GetTickCount64 - FSnippetChecked < 3000) then
    Exit;
  FSnippetChecked := TThread.GetTickCount64;
  Folder := TAtlasEditorCompletion.SnippetFolder;
  IdeFolder := '';
  if TAtlasIdeSettings.Current.ImportIdeTemplates then
    IdeFolder := TAtlasEditorCompletion.IdeTemplateFolder;
  Stamp := TAtlasSnippets.FolderStamp(Folder) + '#' + TAtlasLiveTemplates.FolderStamp(IdeFolder);
  if Stamp = FSnippetStamp then
    Exit;
  FSnippetStamp := Stamp;
  Own := TAtlasSnippets.LoadFolder(Folder, Errors);
  // Postfix-Vorlagen (#188) bietet der Server hinter Ausdrücken an, nicht die Liste am Anweisungsanfang.
  FPostfixSnippets := TAtlasSnippets.Postfixes(Own);
  FPostfixSession := nil;
  Own := TAtlasSnippets.WithoutPostfix(Own);
  Ide := TAtlasLiveTemplates.LoadFolder(IdeFolder, Stats);
  // Ohne Datei- und Ordnernamen: Das Diagnoselog nennt keine Namen (#647).
  Log(Format('Code-Vorlagen: %d eigene, %d fehlerhafte übersprungen; %d aus der IDE, %d übersprungen, ' +
    '%d Skripte entfallen', [Integer(Length(Own)), Integer(Length(Errors)), Stats.Templates, Stats.Skipped,
    Stats.Scripts]));
  FSnippetProvider.SetSnippets(TAtlasSnippets.Merge(TAtlasSnippets.Merge(TAtlasSnippets.BuiltIn, Ide), Own));
end;

procedure TAtlasEditorCompletion.SendPostfixTemplates;
var
  Session: TLspSession;
begin
  if not Assigned(FSession) then
    Exit;
  Session := FSession();
  if (Session = nil) or not Session.Initialized then
    Exit;
  if (Session = FPostfixSession) and (TThread.GetTickCount64 - FPostfixSent < 60000) then
    Exit;
  FPostfixSession := Session;
  FPostfixSent := TThread.GetTickCount64;
  // Auch eine leere Liste: Gelöschte Vorlagen verschwinden beim Server.
  Session.Notify('atlas/postfixTemplates', TAtlasSnippets.PostfixParams(FPostfixSnippets));
end;

class function TAtlasEditorCompletion.IdeTemplateFolder: string;
var
  Services: IOTAServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices, Services) then
    Result := TAtlasLiveTemplates.Folder(TAtlasProjectContext.VersionOfRegistryKey(Services.GetBaseRegistryKey));
end;

class function TAtlasEditorCompletion.SnippetFolder: string;
begin
  Result := GetEnvironmentVariable('APPDATA');
  if Result <> '' then
    Result := IncludeTrailingPathDelimiter(Result) + 'Atlas\Snippets';
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
  // Nur Deklarationen eines unbekannten Namens, nichts gewählt (#471): Enter gehört dem Editor.
  else if (AKey = TAtlasNavigationKey.Accept) and FController.Passive then
  begin
    FController.Close;
    Result := False;
  end
  else
    Result := FController.Visible or (FController.Empty and (AKey = TAtlasNavigationKey.Cancel));
end;

function TAtlasEditorCompletion.WantsCommand(AKey: Word; AShift: TShiftState): Boolean;
var
  Item: TAtlasCompletionItem;
begin
  // Strg+Q Panel (#428), Alt+1 … Alt+6 Chips (#422), Strg+C mit markierter Doku im Panel (#654).
  Result := FController.Visible and (((AKey = Ord('Q')) and (AShift = [ssCtrl])) or
    ((AKey = Ord('C')) and (AShift = [ssCtrl]) and (FPopup.SelectedDocText <> '')) or
    (((AKey = VK_UP) or (AKey = VK_DOWN)) and (AShift = [ssAlt]) and FController.SelectedItem(Item) and
      (Item.OverloadCount > 1)) or
    (FController.ChipsEnabled and (AKey >= Ord('1')) and (AKey <= Ord('6')) and (AShift = [ssAlt])));
end;

procedure TAtlasEditorCompletion.HandleCommand(AKey: Word; AShift: TShiftState);
begin
  if (AKey = Ord('Q')) and (AShift = [ssCtrl]) then
    FPopup.TogglePanel
  else if (AKey = Ord('C')) and (AShift = [ssCtrl]) then
    Clipboard.AsText := FPopup.SelectedDocText
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
  View: IOTAEditView;
begin
  if FController.Active then
    Recheck;
  if FPlaceholders <> nil then
    FPlaceholders.EditorModified(AView);
  // Enter am Ende der Zeile eines übernommenen Konstruktors (#489): nach dem Zeilenende anbieten. Nicht im
  // Benachrichtigungsaufruf selbst, sondern gleich danach.
  if not FController.Active and GuardNewLine(AView) then
  begin
    FGuardLine := 0;
    View := AView;
    TThread.ForceQueue(nil,
      procedure
      begin
        if (View.Buffer <> nil) and not FController.Active then
        begin
          FGuardNewLine := True;
          if not Invoke(View, True) then
            FGuardNewLine := False;
        end;
      end);
  end;
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
  Key, Availability: string;
  Resolver: IAtlasCompletionResolver;
  Details: TAtlasItemDetails;
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
  // Im aktiven Ziel nicht deklariert (#476): Hinweis im Panel, auch ohne Details vom Server.
  Availability := '';
  if Item.Unavailable and (Item.Condition <> '') and not SameText(Item.Condition, 'platform') then
    Availability := TAtlasStrings.Fmt(TAtlasTextId.UnavailableHint, [Item.Condition, FPopup.Target]);
  if not Supports(FServerProviderRef, IAtlasCompletionResolver, Resolver) or not Resolver.Resolve(Item,
    procedure(const ADetails: TAtlasItemDetails)
    var
      Shown: TAtlasItemDetails;
    begin
      // Nur zeigen, wenn noch derselbe Eintrag gewählt und die Liste offen ist.
      if (FDetailKey = Key) and FController.Visible then
      begin
        Shown := WithDisplay(ADetails);
        Shown.Availability := Availability;
        FPopup.ShowDetails(Shown);
      end;
    end) then
    if Availability <> '' then
    begin
      Details := Default(TAtlasItemDetails);
      Details.Availability := Availability;
      FPopup.ShowDetails(Details);
    end
    else
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
  Reason: TAtlasCloseReason;
begin
  if not FController.Active or (FView = nil) then
  begin
    ActiveChanged;
    Exit;
  end;
  // IDE inaktiv, anderes Fenster im Fokus, gescrollt, Größe geändert: schließen (#414).
  Reason := TAtlasCloseRules.Popup(FOpened, WindowState(FView, FEditorWindow, GetFocus));
  if Reason <> TAtlasCloseReason.None then
  begin
    Log('Vervollständigung geschlossen: ' + TAtlasCloseRules.Name(Reason));
    Close;
    Exit;
  end;
  Cursor := FView.CursorPos;
  LineText := '';
  Character := 0;
  if Cursor.Line = FLine then
  begin
    LineText := TAtlasEditorBuffer.LineText(FView, Cursor.Line);
    Character := TLspSession.ColumnToIndex(LineText, Cursor.Col, TAtlasEditorBuffer.TabWidth(FView.Buffer));
  end;
  // Andere Zeile, Cursor vor dem Wortanfang oder ein Zeichen, das kein Bezeichner ist: Wort verlassen.
  Reason := TAtlasCloseRules.PopupWord(Cursor.Line = FLine, LineText, FWordStart, Character, Index);
  if Reason <> TAtlasCloseReason.None then
  begin
    if Reason = TAtlasCloseReason.NonIdentifier then
    begin
      // Commit-Zeichen direkt hinter dem Wort (#429): übernehmen, das Zeichen bleibt.
      if TAtlasIdeSettings.Current.CommitCharacters and (Index = Character) and
        CharInSet(LineText[Index], ['(', ';', '.']) and FController.CanCommitOnCharacter then
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
      Log(Format('Vervollständigung geschlossen: Zeichen #%d getippt', [Ord(LineText[Index])]));
      Close;
      Exit;
    end;
    Log('Vervollständigung geschlossen: ' + TAtlasCloseRules.Name(Reason));
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
  // Code-Vorlage (#51): eigener Weg mit Einrückung und Platzhaltern.
  if AItem.Snippet <> '' then
  begin
    CommitSnippet(View, AItem, Text, LineText, Cursor.Line, Character);
    ActiveChanged;
    Exit;
  end;
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
    // uses-Ergänzung u. ä. (#180); abschaltbar auf der Optionsseite (ARG-046).
    if TAtlasIdeSettings.Current.AutoUses then
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
      Log(Format('  Änderung Byte %d bis %d (Wortanfang %d, Zeile %d, Ende %d): %d Zeichen',
        [Edit.Start, Edit.Stop, FWordStart, Cursor.Line, Character, Length(Edit.Text)]));
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
  Log(Format('Übernommen: %d Zeichen (%d weitere Änderungen)', [Length(AItem.Name), Length(AItem.AdditionalEdits)]));
  // Freigabe absichern (#489): nach dem ";" dieser Zeile anbieten. Kam das ";" als Commit-Zeichen (#429), steht es
  // schon da; dann gleich fragen.
  FGuardLine := 0;
  if AItem.Kind = TAtlasItemKind.Constructor_ then
  begin
    FGuardLine := View.CursorPos.Line;
    FGuardFile := View.Buffer.FileName;
    if (FCommitEnd >= 0) and (FCommitEnd < Length(LineText)) and (LineText[FCommitEnd + 1] = ';') then
      TThread.ForceQueue(nil,
        procedure
        begin
          if GuardPending(View) then
            Invoke(View, True);
        end);
  end;
  ActiveChanged;
end;

procedure TAtlasEditorCompletion.CommitSnippet(const AView: IOTAEditView; const AItem: TAtlasCompletionItem;
  const AText, ALineText: string; ALine, AEnd: Integer);
var
  Expansion: TAtlasSnippetExpansion;
  LineBreak, Document: string;
  Writer: IOTAEditWriter;
  Edits: TList<TPendingEdit>;
  Edit: TPendingEdit;
  TextEdit: TAtlasTextEdit;
  WordStart, SnippetChar, CharShift: Integer;
begin
  // Zeilenumbrüche wie im Puffer, Einrückung wie die aktuelle Zeile.
  if Pos(#13#10, AText) > 0 then
    LineBreak := #13#10
  else
    LineBreak := #10;
  Expansion := TAtlasSnippets.Expand(AItem.Snippet, TAtlasSnippets.IndentOf(ALineText), LineBreak);
  // Vorlage des Servers (#51): ab dem Anfang ihres Bereichs; sonst das getippte Wort.
  WordStart := FWordStart;
  if AItem.HasTextEdit and (AItem.TextEdit.StartLine = ALine - 1) then
    WordStart := AItem.TextEdit.StartCharacter;
  SnippetChar := TAtlasEditorBuffer.CharOffset(AText, ALine - 1, WordStart);
  Edits := TList<TPendingEdit>.Create;
  try
    Edit.Start := TAtlasEditorBuffer.ByteOffset(AText, ALine - 1, WordStart);
    Edit.Stop := TAtlasEditorBuffer.ByteOffset(AText, ALine - 1, AEnd);
    Edit.Text := Expansion.Text;
    Edit.IsWord := True;
    Edits.Add(Edit);
    // Setter-Deklaration und -Rumpf der Vorlage „prop“ u. ä.; davor liegende verschieben den Platzhalter-Text.
    CharShift := 0;
    for TextEdit in AItem.AdditionalEdits do
    begin
      Edit.Start := TAtlasEditorBuffer.ByteOffset(AText, TextEdit.StartLine, TextEdit.StartCharacter);
      Edit.Stop := TAtlasEditorBuffer.ByteOffset(AText, TextEdit.EndLine, TextEdit.EndCharacter);
      Edit.Text := TextEdit.NewText;
      Edit.IsWord := False;
      Edits.Add(Edit);
      if Edit.Start < Edits[0].Start then
        Inc(CharShift, Length(TextEdit.NewText) -
          (TAtlasEditorBuffer.CharOffset(AText, TextEdit.EndLine, TextEdit.EndCharacter) -
          TAtlasEditorBuffer.CharOffset(AText, TextEdit.StartLine, TextEdit.StartCharacter)));
    end;
    Edits.Sort(TComparer<TPendingEdit>.Construct(
      function(const A, B: TPendingEdit): Integer
      begin
        Result := A.Start - B.Start;
      end));
    // Ein Schreiber = ein Undo-Schritt für das Einsetzen; er schreibt nur vorwärts.
    Writer := AView.Buffer.CreateUndoableWriter;
    for Edit in Edits do
    begin
      Writer.CopyTo(Edit.Start);
      Writer.DeleteTo(Edit.Stop);
      Writer.Insert(PAnsiChar(UTF8Encode(Edit.Text)));
    end;
    Writer := nil;
  finally
    Edits.Free;
  end;
  Document := TAtlasEditorBuffer.Text(AView.Buffer);
  FPlaceholders.Start(AView, AText, Document, SnippetChar + CharShift, Expansion);
  Log(Format('Code-Vorlage eingesetzt: %d Platzhalter, %d weitere Änderungen',
    [Integer(Length(Expansion.Stops)), Integer(Length(AItem.AdditionalEdits))]));
end;

function TAtlasEditorCompletion.GuardNewLine(const AView: IOTAEditView): Boolean;
begin
  Result := (FGuardLine > 0) and (AView <> nil) and (AView.Buffer <> nil) and
    (AView.CursorPos.Line = FGuardLine + 1) and SameText(AView.Buffer.FileName, FGuardFile) and
    (Trim(TAtlasEditorBuffer.LineText(AView, AView.CursorPos.Line)) = '') and
    not TAtlasEditorBuffer.LineText(AView, FGuardLine).TrimRight.EndsWith(';');
end;

function TAtlasEditorCompletion.GuardPending(const AView: IOTAEditView): Boolean;
begin
  Result := (FGuardLine > 0) and (AView <> nil) and (AView.Buffer <> nil) and (AView.CursorPos.Line = FGuardLine) and
    SameText(AView.Buffer.FileName, FGuardFile);
end;

end.
