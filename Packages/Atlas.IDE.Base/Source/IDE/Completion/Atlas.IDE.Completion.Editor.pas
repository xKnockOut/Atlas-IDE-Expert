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
//     Tastatur-Hook (Atlas.IDE.Foundation.KeyHook) ↑ ↓ Bild↑ Bild↓ Pos1 Ende Enter Tab Esc
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
//     Änderung neu gelesen; eigene vor IDE vor mitgelieferten), dazu die des Projekts aus dem Ordner
//     "snippets" der Projektdatei .atlas (#486; vor den eigenen). Übernehmen setzt den Text mit der
//     Einrückung der Zeile ein und startet den Platzhalter-Modus (Atlas.IDE.Completion.Placeholders).
//   - Diagnosemodus (#479): Invoke nimmt nur bei eingeschalteter Messung beim Aufruf einen Zeitstempel
//     (TAtlasContext.Started); der Kontext reicht von dort bis zur Anfrage.
//   - Favoriten (#458, Einstellung Favorites): Strg+D im offenen Popup bzw. Klick auf den Stern heftet den
//     Eintrag an oder löst ihn (TAtlasIdeFavorites, sofort gespeichert); Ergebnis bzw. „Schon 5 Favoriten …“
//     als Hinweis in der Fußzeile. Strg+D gehört bei offener Liste immer dem Popup, nie dem Editor.
// Aufgeteilt in eine Kette von Stufen (Atlas.IDE.Completion.EditorState …EditorCommit); hier Tasten, Weitertippen,
// Detailpanel und Vorschau.

interface

uses
  System.Classes,
  ToolsAPI,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Editor.CloseRules,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Completion.EditorState,
  Atlas.IDE.Completion.EditorCommit;

type
  /// <summary>Protokoll für die Diagnose (Registry-Wert Diagnose).</summary>
  TAtlasLogProc = Atlas.IDE.Completion.EditorState.TAtlasLogProc;
  /// <summary>Quellen der Vervollständigung aus dem Kern; setzt die Kompositionswurzel ein.</summary>
  TAtlasCompletionSources = Atlas.IDE.Completion.EditorState.TAtlasCompletionSources;
  TAtlasCompletionSourcesFactory = Atlas.IDE.Completion.EditorState.TAtlasCompletionSourcesFactory;

  TAtlasEditorCompletion = class(TAtlasEditorCompletionCommit)
  private
    procedure Recheck;
    /// <summary>IDE inaktiv, anderes Fenster im Fokus, gescrollt, Größe geändert (#414): schließt; True dann.
    /// </summary>
    function WindowLeft: Boolean;
    /// <summary>Cursor hat das Wort verlassen: übernehmen über ein Commit-Zeichen (#429) oder schließen.</summary>
    procedure LeaveWord(AReason: TAtlasCloseReason; const ALineText: string; AIndex, ACharacter: Integer);
    /// <summary>Neues Präfix: lokal weiterfiltern, bei Bedarf im Hintergrund neu fragen.</summary>
    procedure Refilter(const ALineText: string; ALine, ACharacter: Integer);
    procedure TimerTick(Sender: TObject);
    procedure UpdateDetails;
    /// <summary>Details zu AItem beim Server nachfragen und zeigen; AKey: Schlüssel des Eintrags.</summary>
    procedure ResolveDetails(const AItem: TAtlasCompletionItem; const AKey: string);
    procedure ChangeOverload(ADelta: Integer);
    procedure UpdatePreview;
    /// <summary>Rest des gewählten Namens hinter dem Cursor (#434); '' ohne Vorschau.</summary>
    function PreviewText: string;
    /// <summary>Gehört die Taste gerade dem Popup?</summary>
    function WantsKey(AKey: TAtlasNavigationKey): Boolean;
    /// <summary>Favorit (#458) an APosition anheften bzw. lösen; APosition &lt; 0 = gewählter Eintrag (Strg+D).
    /// Speichert und zeigt das Ergebnis in der Fußzeile.</summary>
    procedure ToggleFavorite(APosition: Integer);
    /// <summary>Gleich nach der Benachrichtigung automatisch öffnen; AFromGuard: nach dem Enter hinter einem
    /// Konstruktor (#489), sonst nach "(" hinter einem Namen (#472).</summary>
    procedure QueueInvoke(const AView: IOTAEditView; AFromGuard: Boolean);
    procedure SetPending(AFromGuard, AValue: Boolean);
    /// <summary>"(" hinter einem Namen (#472): fragen, ob der Server die Methode anlegen kann; einmal je Stelle.
    /// </summary>
    procedure CheckCallOpened(const AView: IOTAEditView);
    /// <summary>")" vor der automatischen Klammer (#430): diese überspringen.</summary>
    procedure TrackAutoParen(const AView: IOTAEditView);
  public
    /// <summary>ASources legt die Quellen des Kerns an (Kompositionswurzel).</summary>
    constructor Create(const ASession: TAtlasSessionFunc; const ALog: TAtlasLogProc;
      const ASources: TAtlasCompletionSourcesFactory);
    destructor Destroy; override;
    /// <summary>Taste aus dem Tastatur-Hook; True, wenn verbraucht.</summary>
    function HandleKey(AKey: TAtlasNavigationKey): Boolean;
    /// <summary>Befehle im offenen Popup: Strg+Q Panel ein/aus (#428), Alt+1 … Alt+6 Chips (#422), Strg+D
    /// Favorit (#458).</summary>
    function WantsCommand(AKey: Word; AShift: TShiftState): Boolean;
    procedure HandleCommand(AKey: Word; AShift: TShiftState);
    /// <summary>Editortext wurde geändert.</summary>
    procedure EditorModified(const AView: IOTAEditView);
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Clipbrd,
  DockForm,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Completion.Parentheses,
  Atlas.Core.Completion.Preview,
  Atlas.Core.Completion.Favorites,
  Atlas.Core.Completion.Presentation,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Completion.History,
  Atlas.IDE.Completion.Favorites,
  Atlas.IDE.Signature.Editor,
  Atlas.UI.Completion.Strings;

const
  /// <summary>Ruhe nach einem Wechsel der Auswahl, bevor die Details nachgefragt werden (#424).</summary>
  cDetailDelayMs = 80;

/// <summary>Anzeige der XMLDoc im Panel (#654): hints aus settings.json meldet der Server, sonst die
/// Optionen.</summary>
function WithDisplay(const ADetails: TAtlasItemDetails): TAtlasItemDetails;
begin
  Result := ADetails;
  if not Result.Display.Known then
  begin
    Result.Display := TAtlasDocDisplay.Create(TAtlasDocDisplay.ExpandOf(TAtlasIdeSettings.Current.XmlDocExpand),
      TAtlasIdeSettings.Current.XmlDocMaxLines);
  end;
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
  mNavigation: TAtlasNavigationKey;
begin
  Result := ((AShift = []) and NavigationKey(AKey, mNavigation) and FOwner.WantsKey(mNavigation)) or
    FOwner.WantsCommand(AKey, AShift);
end;

procedure TCompletionKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  mNavigation: TAtlasNavigationKey;
begin
  try
    if FOwner.WantsCommand(AKey, AShift) then
    begin
      FOwner.HandleCommand(AKey, AShift);
    end
    else if NavigationKey(AKey, mNavigation) then
    begin
      FOwner.HandleKey(mNavigation);
    end;
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

constructor TAtlasEditorCompletion.Create(const ASession: TAtlasSessionFunc; const ALog: TAtlasLogProc;
  const ASources: TAtlasCompletionSourcesFactory);
var
  mEditor: IOTAEditorServices;
  mNotifier: INTAEditServicesNotifier;
begin
  inherited Create(ASession, ALog, ASources);
  FController.OnCommit :=
    procedure(const AItem: TAtlasCompletionItem)
    begin
      // Die zuletzt gezeigte Überladung gilt auch im Parameter-Hint (#425, #437).
      TAtlasEditorSignature.PreferOverload(AItem.Name, FDetails.OverloadIndex);
      Commit(AItem);
      if FController.Usage <> nil then
      begin
        TAtlasIdeHistory.Committed;
      end;
    end;
  FPopup.OnOverload :=
    procedure(ADelta: Integer)
    begin
      ChangeOverload(ADelta);
    end;
  // Stern einer Zeile (#458).
  FPopup.OnFavorite :=
    procedure(APosition: Integer)
    begin
      ToggleFavorite(APosition);
    end;
  FKeys := TCompletionKeys.Create(Self);
  FTimer.OnTimer := TimerTick;
  FDelay.Timer.OnTimer := DelayTimerTick;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditor) then
  begin
    mNotifier := TAtlasEditNotifier.Create(Self);
    FNotifierIndex := mEditor.AddNotifier(mNotifier);
  end;
end;

destructor TAtlasEditorCompletion.Destroy;
var
  mEditor: IOTAEditorServices;
begin
  // Erst abmelden, dann freigeben: Die IDE ruft sonst noch in freigegebene Objekte (#493).
  RemoveKeyHook;
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, mEditor) then
  begin
    mEditor.RemoveNotifier(FNotifierIndex);
    FNotifierIndex := -1;
  end;
  inherited;
end;

function TAtlasEditorCompletion.WantsKey(AKey: TAtlasNavigationKey): Boolean;
begin
  // Liste offen: alle Navigationstasten, die Leertaste nur im Mengenmodus (#448). Leerer Zustand (#423): nur Esc.
  if AKey = TAtlasNavigationKey.Toggle then
  begin
    Result := FController.Visible and FController.SetMode;
  end
  // Nur Deklarationen eines unbekannten Namens, nichts gewählt (#471): Enter gehört dem Editor.
  else if (AKey = TAtlasNavigationKey.Accept) and FController.Passive then
  begin
    FController.Close;
    Result := False;
  end
  else
  begin
    Result := FController.Visible or (FController.Empty and (AKey = TAtlasNavigationKey.Cancel));
  end;
end;

function TAtlasEditorCompletion.WantsCommand(AKey: Word; AShift: TShiftState): Boolean;
var
  mItem: TAtlasCompletionItem;
begin
  // Strg+Q Panel (#428), Alt+1 … Alt+6 Chips (#422), Strg+C mit markierter Doku im Panel (#654), Strg+D Favorit
  // (#458; bei offener Liste nie an den Editor).
  Result := FController.Visible and (((AKey = Ord('Q')) and (AShift = [ssCtrl])) or
    ((AKey = Ord('D')) and (AShift = [ssCtrl]) and (FController.Favorites <> nil)) or
    ((AKey = Ord('C')) and (AShift = [ssCtrl]) and (FPopup.SelectedDocText <> '')) or
    (((AKey = VK_UP) or (AKey = VK_DOWN)) and (AShift = [ssAlt]) and FController.SelectedItem(mItem) and
      (mItem.OverloadCount > 1)) or
    (FController.ChipsEnabled and (AKey >= Ord('1')) and (AKey <= Ord('6')) and (AShift = [ssAlt]))) or
    // Zweites Strg+Leertaste (#2108): nicht sichtbare Treffer zeigen, auch im leeren Zustand.
    ((AKey = VK_SPACE) and (AShift = [ssCtrl]) and FController.CanRevealInaccessible);
end;

procedure TAtlasEditorCompletion.HandleCommand(AKey: Word; AShift: TShiftState);
begin
  if (AKey = Ord('Q')) and (AShift = [ssCtrl]) then
  begin
    FPopup.TogglePanel;
  end
  else if (AKey = Ord('C')) and (AShift = [ssCtrl]) then
  begin
    Clipboard.AsText := FPopup.SelectedDocText;
  end
  else if (AKey = Ord('D')) and (AShift = [ssCtrl]) then
  begin
    ToggleFavorite(-1);
  end
  else if (AKey = VK_UP) and (AShift = [ssAlt]) then
  begin
    ChangeOverload(-1);
  end
  else if (AKey = VK_DOWN) and (AShift = [ssAlt]) then
  begin
    ChangeOverload(1);
  end
  else if (AKey >= Ord('1')) and (AKey <= Ord('6')) then
  begin
    FController.SelectChipAt(AKey - Ord('1'));
  end
  else if AKey = VK_SPACE then
  begin
    FController.RevealInaccessible;
  end;
end;

procedure TAtlasEditorCompletion.ToggleFavorite(APosition: Integer);
var
  mItem: TAtlasCompletionItem;
  mOutcome: TAtlasFavoriteToggle;
begin
  if APosition < 0 then
  begin
    mOutcome := FController.ToggleSelectedFavorite(mItem);
  end
  else
  begin
    mOutcome := FController.ToggleFavorite(APosition, mItem);
  end;
  case mOutcome of
    TAtlasFavoriteToggle.Added:
      begin
        TAtlasIdeFavorites.Save;
        FPopup.ShowNotice(TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.FavoritePinned, [mItem.Name]));
      end;
    TAtlasFavoriteToggle.Removed:
      begin
        TAtlasIdeFavorites.Save;
        FPopup.ShowNotice(TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.FavoriteUnpinned, [mItem.Name]));
      end;
    // Ein sechster Favorit ersetzt keinen (#458).
    TAtlasFavoriteToggle.Full:
      FPopup.ShowNotice(TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.FavoritesFull, [TAtlasFavorites.cMaxPerType,
        TAtlasFavorites.TypeNameOf(mItem)]));
  else
    if FController.Favorites <> nil then
    begin
      FPopup.ShowNotice(TAtlasCompletionStrings.Text(TAtlasCompletionTextId.FavoriteNotAllowed));
    end;
  end;
  ActiveChanged;
end;

function TAtlasEditorCompletion.HandleKey(AKey: TAtlasNavigationKey): Boolean;
begin
  Result := FController.HandleKey(AKey);
  ActiveChanged;
end;

procedure TAtlasEditorCompletion.SetPending(AFromGuard, AValue: Boolean);
begin
  if AFromGuard then
  begin
    FGuard.NewLine := AValue;
  end
  else
  begin
    FCall.Opened := AValue;
  end;
end;

procedure TAtlasEditorCompletion.QueueInvoke(const AView: IOTAEditView; AFromGuard: Boolean);
var
  mView: IOTAEditView;
begin
  mView := AView;
  // Nicht im Benachrichtigungsaufruf selbst, sondern gleich danach.
  TAtlasMainThread.ForceQueue(TAtlasFeature.Completion,
    procedure
    begin
      if (mView.Buffer <> nil) and not FController.Active then
      begin
        SetPending(AFromGuard, True);
        if not Invoke(mView, True) then
        begin
          SetPending(AFromGuard, False);
        end;
      end;
    end);
end;

procedure TAtlasEditorCompletion.CheckCallOpened(const AView: IOTAEditView);
var
  mLineText: string;
  mLine, mCharacter: Integer;
begin
  mLine := AView.CursorPos.Line;
  mLineText := TAtlasEditorBuffer.LineText(AView, mLine);
  mCharacter := TLspSession.ColumnToIndex(mLineText, AView.CursorPos.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer));
  if not TAtlasParentheses.CallOpened(mLineText, mCharacter) then
  begin
    Exit;
  end;
  if (FCall.Line = mLine) and (FCall.Character = mCharacter) and SameText(FCall.FileName, AView.Buffer.FileName) then
  begin
    Exit;
  end;
  FCall.FileName := AView.Buffer.FileName;
  FCall.Line := mLine;
  FCall.Character := mCharacter;
  QueueInvoke(AView, False);
end;

procedure TAtlasEditorCompletion.TrackAutoParen(const AView: IOTAEditView);
var
  mRemoveAt: Integer;
begin
  if AView.CursorPos.Line <> FAutoParen.Line then
  begin
    FAutoParen.Stop;
    Exit;
  end;
  FAutoParen.Update(TAtlasEditorBuffer.LineText(AView, FAutoParen.Line), mRemoveAt);
  if mRemoveAt >= 0 then
  begin
    SkipAutoParen(AView, mRemoveAt);
  end;
end;

procedure TAtlasEditorCompletion.EditorModified(const AView: IOTAEditView);
var
  mHasBuffer: Boolean;
begin
  if FController.Active then
  begin
    Recheck;
  end;
  if FPlaceholders <> nil then
  begin
    FPlaceholders.EditorModified(AView);
  end;
  mHasBuffer := (AView <> nil) and (AView.Buffer <> nil);
  // Enter am Ende der Zeile eines übernommenen Konstruktors (#489): nach dem Zeilenende anbieten.
  if not FController.Active and GuardNewLine(AView) then
  begin
    FGuard.Line := 0;
    QueueInvoke(AView, True);
  end
  else if not FController.Active and mHasBuffer then
  begin
    CheckCallOpened(AView);
  end;
  if FAutoParen.Active and mHasBuffer then
  begin
    TrackAutoParen(AView);
  end;
end;

procedure TAtlasEditorCompletion.UpdateDetails;
var
  mItem: TAtlasCompletionItem;
  mKey: string;
begin
  if not FController.Visible or not FController.SelectedItem(mItem) then
  begin
    HideDetails;
    Exit;
  end;
  mKey := mItem.Name + #0 + mItem.ResolveData;
  if mKey <> FDetails.Key then
  begin
    // Erst nach 80 ms Ruhe nachfragen, damit schnelles Scrollen nicht flackert (#424).
    FDetails.Key := mKey;
    FDetails.OverloadIndex := 0;
    FPopup.SetOverload(0, mItem.OverloadCount);
    FDetails.Due := TThread.GetTickCount64 + cDetailDelayMs;
    FDetails.Requested := False;
    Exit;
  end;
  if FDetails.Requested or (TThread.GetTickCount64 < FDetails.Due) then
  begin
    Exit;
  end;
  FDetails.Requested := True;
  // Überladung (#425): deren Position statt der ersten nachfragen.
  if (FDetails.OverloadIndex > 0) and (FDetails.OverloadIndex <= Length(mItem.OverloadData)) then
  begin
    mItem.ResolveData := mItem.OverloadData[FDetails.OverloadIndex - 1];
  end;
  // Unit im uses-Abschnitt (#469): alles Nötige liefert schon die Liste.
  if mItem.UsesGroup <> '' then
  begin
    FPopup.ShowDetails(TAtlasItemPresentation.UsesDetails(mItem));
  end
  else
  begin
    ResolveDetails(mItem, mKey);
  end;
end;

procedure TAtlasEditorCompletion.ResolveDetails(const AItem: TAtlasCompletionItem; const AKey: string);
var
  mItem: TAtlasCompletionItem;
  mKey, mAvailability, mAddsUnit: string;
  mResolver: IAtlasCompletionResolver;
  mDetails: TAtlasItemDetails;
begin
  mItem := AItem;
  mKey := AKey;
  // Helper aus nicht eingebundener Unit (#456): Hinweis, dass Enter die uses ergänzt.
  mAddsUnit := '';
  if mItem.IsHelper and TAtlasIdeSettings.Current.AutoUses then
  begin
    mAddsUnit := TAtlasItemPresentation.MissingUnit(mItem);
  end;
  // Im aktiven Ziel nicht deklariert (#476): Hinweis im Panel, auch ohne Details vom Server.
  mAvailability := '';
  if mItem.Unavailable and (mItem.Condition <> '') and not SameText(mItem.Condition, 'platform') then
  begin
    mAvailability := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.UnavailableHint, [mItem.Condition,
      FPopup.Target]);
  end;
  if Supports(FSources.Server, IAtlasCompletionResolver, mResolver) and mResolver.Resolve(mItem,
    procedure(const ADetails: TAtlasItemDetails)
    var
      mShown: TAtlasItemDetails;
    begin
      // Nur zeigen, wenn noch derselbe Eintrag gewählt und die Liste offen ist.
      if (FDetails.Key = mKey) and FController.Visible then
      begin
        mShown := WithDisplay(ADetails);
        mShown.Availability := mAvailability;
        mShown.AddsUnit := mAddsUnit;
        // Gleichnamige Bezeichner (#475): alles Nötige liefert die Liste.
        TAtlasItemPresentation.AddSameName(mItem, mShown);
        FPopup.ShowDetails(mShown);
      end;
    end) then
  begin
    Exit;
  end;
  if (mAvailability <> '') or (Length(mItem.SameNameUnits) > 0) then
  begin
    mDetails := Default(TAtlasItemDetails);
    mDetails.Availability := mAvailability;
    TAtlasItemPresentation.AddSameName(mItem, mDetails);
    FPopup.ShowDetails(mDetails);
  end
  else
  begin
    FPopup.ClearDetails;
  end;
end;

procedure TAtlasEditorCompletion.ChangeOverload(ADelta: Integer);
var
  mItem: TAtlasCompletionItem;
begin
  if not FController.SelectedItem(mItem) or (mItem.OverloadCount < 2) then
  begin
    Exit;
  end;
  FDetails.OverloadIndex := (FDetails.OverloadIndex + ADelta + mItem.OverloadCount) mod mItem.OverloadCount;
  FPopup.SetOverload(FDetails.OverloadIndex, mItem.OverloadCount);
  // Sofort nachfragen, ohne die 80 ms Ruhe beim Blättern in der Liste.
  FDetails.Requested := False;
  FDetails.Due := 0;
  UpdateDetails;
end;

function TAtlasEditorCompletion.PreviewText: string;
var
  mItem: TAtlasCompletionItem;
  mLineText: string;
  mCharacter: Integer;
begin
  Result := '';
  if not TAtlasIdeSettings.Current.Preview or not FController.Visible or not FController.SelectedItem(mItem) then
  begin
    Exit;
  end;
  if (FOpen.View = nil) or (FOpen.View.Buffer = nil) or (FOpen.View.CursorPos.Line <> FOpen.Line) then
  begin
    Exit;
  end;
  mLineText := TAtlasEditorBuffer.LineText(FOpen.View, FOpen.Line);
  mCharacter := TLspSession.ColumnToIndex(mLineText, FOpen.View.CursorPos.Col,
    TAtlasEditorBuffer.TabWidth(FOpen.View.Buffer));
  Result := TAtlasPreview.RestOf(mItem.Name, FController.Prefix, Copy(mLineText, mCharacter + 1, MaxInt));
end;

procedure TAtlasEditorCompletion.UpdatePreview;
var
  mText: string;
begin
  if FPreview = nil then
  begin
    Exit;
  end;
  mText := PreviewText;
  if mText = '' then
  begin
    FPreview.Clear;
  end
  else
  begin
    FPreview.Show(FOpen.View.Buffer.FileName, FOpen.Line, FOpen.View.CursorPos.Col, mText);
  end;
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

function TAtlasEditorCompletion.WindowLeft: Boolean;
var
  mReason: TAtlasCloseReason;
begin
  mReason := TAtlasCloseRules.Popup(FOpen.Opened, WindowState(FOpen.View, FOpen.Window, GetFocus));
  Result := mReason <> TAtlasCloseReason.None;
  if Result then
  begin
    Log('Vervollständigung geschlossen: ' + TAtlasCloseRules.Name(mReason));
    Close;
  end;
end;

procedure TAtlasEditorCompletion.LeaveWord(AReason: TAtlasCloseReason; const ALineText: string; AIndex,
  ACharacter: Integer);
begin
  if AReason <> TAtlasCloseReason.NonIdentifier then
  begin
    Log('Vervollständigung geschlossen: ' + TAtlasCloseRules.Name(AReason));
    Close;
    Exit;
  end;
  // Commit-Zeichen direkt hinter dem Wort (#429): übernehmen, das Zeichen bleibt.
  if TAtlasIdeSettings.Current.CommitCharacters and (AIndex = ACharacter) and
    CharInSet(ALineText[AIndex], ['(', ';', '.']) and FController.CanCommitOnCharacter then
  begin
    FCommitChar.WordEnd := ACharacter - 1;
    FCommitChar.SuffixBytes := TEncoding.UTF8.GetByteCount(string(ALineText[AIndex]));
    try
      FController.CommitSelected;
    finally
      FCommitChar.WordEnd := -1;
    end;
    ActiveChanged;
    Exit;
  end;
  Log(Format('Vervollständigung geschlossen: Zeichen #%d getippt', [Ord(ALineText[AIndex])]));
  Close;
end;

procedure TAtlasEditorCompletion.Refilter(const ALineText: string; ALine, ACharacter: Integer);
var
  mPrefix: string;
begin
  mPrefix := Copy(ALineText, FOpen.WordStart + 1, ACharacter - FOpen.WordStart);
  // Gekürzte Liste (#431) oder Wort nicht mehr Fortsetzung der Anfrage (Rücktaste, #616): lokal weiterfiltern
  // und im Hintergrund neu fragen. Sonst nur lokal; der Server wird beim Tippen nicht mehr gefragt.
  if (mPrefix <> FController.Prefix) and FController.NeedsQuery(mPrefix) then
  begin
    FController.Requery(ContextAt(FOpen.View, ALineText, ALine, ACharacter, FOpen.WordStart));
  end
  else
  begin
    FController.UpdatePrefix(mPrefix);
  end;
end;

procedure TAtlasEditorCompletion.Recheck;
var
  mCursor: TOTAEditPos;
  mLineText: string;
  mCharacter, mIndex: Integer;
  mReason: TAtlasCloseReason;
begin
  if not FController.Active or (FOpen.View = nil) then
  begin
    ActiveChanged;
    Exit;
  end;
  if WindowLeft then
  begin
    Exit;
  end;
  mCursor := FOpen.View.CursorPos;
  mLineText := '';
  mCharacter := 0;
  if mCursor.Line = FOpen.Line then
  begin
    mLineText := TAtlasEditorBuffer.LineText(FOpen.View, mCursor.Line);
    mCharacter := TLspSession.ColumnToIndex(mLineText, mCursor.Col, TAtlasEditorBuffer.TabWidth(FOpen.View.Buffer));
  end;
  // Andere Zeile, Cursor vor dem Wortanfang oder ein Zeichen, das kein Bezeichner ist: Wort verlassen.
  mReason := TAtlasCloseRules.PopupWord(mCursor.Line = FOpen.Line, mLineText, FOpen.WordStart, mCharacter, mIndex);
  if mReason <> TAtlasCloseReason.None then
  begin
    LeaveWord(mReason, mLineText, mIndex, mCharacter);
    Exit;
  end;
  Refilter(mLineText, mCursor.Line, mCharacter);
  ActiveChanged;
end;

end.
