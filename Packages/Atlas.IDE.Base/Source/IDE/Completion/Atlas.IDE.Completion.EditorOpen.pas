unit Atlas.IDE.Completion.EditorOpen;

// Vervollständigung im Editor (#410), Stufe Öffnen: Wort vor dem Cursor als Präfix, Caret-Rechteck als Anker des
// Popups, Einstellungen ins Popup, verzögertes automatisches Öffnen (ARG-046). Kette:
// Atlas.IDE.Completion.EditorState.

interface

uses
  Winapi.Windows,
  System.Types,
  ToolsAPI,
  Atlas.Core.Completion.Contract,
  Atlas.IDE.Completion.EditorSnippets;

type
  TAtlasEditorCompletionOpen = class(TAtlasEditorCompletionSnippets)
  protected
    procedure DelayTimerTick(Sender: TObject);
    /// <summary>Kontext an der Cursorstelle; ALine ab 1, ACharacter und AWordStart 0-basiert.</summary>
    function ContextAt(const AView: IOTAEditView; const ALineText: string; ALine, ACharacter,
      AWordStart: Integer): TAtlasContext;
  private
    procedure ApplyStyle(const ACaret: TRect);
    function CaretRect(out AWindow: HWND; out ARect: TRect): Boolean;
    /// <summary>Einstellungen der Liste in Popup und Ablauf übernehmen (vor jedem Öffnen).</summary>
    procedure ApplyOptions;
    /// <summary>Popup am Wortanfang verankern (ACaret: Caret-Rechteck) und die offene Stelle merken.</summary>
    procedure Anchor(const AView: IOTAEditView; AWindow: HWND; ACaret: TRect; ALine, AWordStart: Integer;
      const APrefix: string);
    /// <summary>Verzögertes Öffnen vormerken (ARG-046); DelayTimerTick ruft Invoke wieder auf.</summary>
    procedure StartDelay(const AView: IOTAEditView; ALine, ACharacter: Integer; AWindow: HWND);
    /// <summary>Zeichen, nach dem die IDE automatisch geöffnet hat ('' ohne besonderes).</summary>
    function AutomaticTrigger(const AView: IOTAEditView; const ALineText: string; ACharacter: Integer): string;
  public
    /// <summary>Öffnet die Vervollständigung an der Cursorstelle von AView; False, wenn nicht möglich.
    /// AAutomatic: von der IDE nach einem Zeichen ausgelöst, nicht über Strg+Leer. Steht dann "[" vor dem
    /// Cursor, fragt Atlas nur nach Mengenwerten (#448).</summary>
    function Invoke(const AView: IOTAEditView; AAutomatic: Boolean): Boolean; overload;
    /// <summary>Wie oben über Strg+Leer (AAutomatic = False).</summary>
    function Invoke(const AView: IOTAEditView): Boolean; overload;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Timing,
  Atlas.Core.Completion.Word,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Editor.CloseRules,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Completion.History,
  Atlas.IDE.Completion.Favorites,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle;

/// <summary>Plattform und Konfiguration des aktiven Projekts („Win32 · Debug“, #476); '' ohne Projekt.</summary>
function ActiveTarget: string;
var
  mProject: IOTAProject;
begin
  Result := '';
  mProject := GetActiveProject;
  if mProject = nil then
  begin
    Exit;
  end;
  Result := mProject.CurrentPlatform;
  if mProject.CurrentConfiguration <> '' then
  begin
    if Result <> '' then
    begin
      Result := Result + ' · ' + mProject.CurrentConfiguration;
    end
    else
    begin
      Result := mProject.CurrentConfiguration;
    end;
  end;
end;

/// <summary>Steht ein AChar direkt vor dem Cursor (ACharacter 0-basiert)?</summary>
function TypedBefore(const ALineText: string; ACharacter: Integer; AChar: Char): Boolean;
begin
  Result := (ACharacter > 0) and (ACharacter <= Length(ALineText)) and (ALineText[ACharacter] = AChar);
end;

{ TAtlasEditorCompletionOpen }

procedure TAtlasEditorCompletionOpen.ApplyStyle(const ACaret: TRect);
begin
  // Farben aus dem Thema der IDE (hell/dunkel), Schrift aus den Editoroptionen, Monitor-DPI und Zoom
  // am Caret (#411, #412, #445).
  Log(TAtlasIdeStyle.Apply(FPopup, ACaret));
end;

function TAtlasEditorCompletionOpen.CaretRect(out AWindow: HWND; out ARect: TRect): Boolean;
var
  mInfo: TGUIThreadInfo;
begin
  FillChar(mInfo, SizeOf(mInfo), 0);
  mInfo.cbSize := SizeOf(mInfo);
  Result := GetGUIThreadInfo(GetCurrentThreadId, mInfo) and (mInfo.hwndCaret <> 0);
  if not Result then
  begin
    Exit;
  end;
  AWindow := mInfo.hwndCaret;
  ARect := mInfo.rcCaret;
  MapWindowPoints(AWindow, 0, ARect, 2);
end;

function TAtlasEditorCompletionOpen.ContextAt(const AView: IOTAEditView; const ALineText: string; ALine,
  ACharacter, AWordStart: Integer): TAtlasContext;
begin
  Result := Default(TAtlasContext);
  Result.FileName := AView.Buffer.FileName;
  Result.Text := TAtlasEditorBuffer.Text(AView.Buffer);
  Result.Line := ALine - 1;
  Result.Character := ACharacter;
  Result.Prefix := Copy(ALineText, AWordStart + 1, ACharacter - AWordStart);
  if (AWordStart > 0) and (ALineText[AWordStart] = '.') then
  begin
    Result.Kind := TAtlasContextKind.MemberAccess;
  end
  else
  begin
    Result.Kind := TAtlasContextKind.Identifier;
  end;
end;

function TAtlasEditorCompletionOpen.AutomaticTrigger(const AView: IOTAEditView; const ALineText: string;
  ACharacter: Integer): string;
begin
  Result := '';
  // Nach "[" automatisch geöffnet (#448): nur ein Mengenkonstruktor bekommt eine Liste.
  if TypedBefore(ALineText, ACharacter, '[') then
  begin
    Result := '[';
  end
  // Nach dem ";" hinter einem übernommenen Konstruktor (#489): nur „Mit try…finally absichern“.
  else if TypedBefore(ALineText, ACharacter, ';') and GuardPending(AView) then
  begin
    Result := ';';
    FGuard.Line := 0;
  end
  // Nach dem Zeilenende (Enter) hinter einem übernommenen Konstruktor ohne ";" (#489).
  else if FGuard.NewLine then
  begin
    Result := #10;
  end
  // Nach "(" hinter einem Namen (#472): nur „Methode anlegen“, wenn der Name unbekannt ist.
  else if FCall.Opened then
  begin
    Result := '(';
  end;
end;

procedure TAtlasEditorCompletionOpen.ApplyOptions;
begin
  FPopup.VisibleRows := TAtlasIdeSettings.Current.VisibleRows;
  FPopup.ManualListWidth := TAtlasIdeSettings.Current.ListWidth;
  FPopup.PanelWidthSetting := TAtlasIdeSettings.Current.PanelWidth;
  FPopup.PanelCollapsed := TAtlasIdeSettings.Current.PanelCollapsed;
  // Gruppen geerbter Member (#419), Chips (#422), lernende Gewichtung (#418).
  FController.GroupInherited := TAtlasIdeSettings.Current.GroupInherited;
  FPopup.DimInherited := TAtlasIdeSettings.Current.GroupInherited;
  // Marke „Zweig 0“ an Feldern varianter Records (#846).
  FPopup.ShowVariantBranch := TAtlasIdeSettings.Current.CompletionVariantBranch;
  // Einträge ohne Treffer zeigen (#497).
  FController.ListMode := TAtlasListModes.ModeOf(TAtlasIdeSettings.Current.CompletionListMode);
  FController.ListScope := TAtlasListModes.ScopeOf(TAtlasIdeSettings.Current.CompletionListScope);
  // Während der Server indiziert, liefert er den vorhandenen Stand; die Fußzeile sagt es (#492).
  FPopup.Limited := IndexingNow;
  FPopup.Target := ActiveTarget;
  FController.ChipsEnabled := TAtlasIdeSettings.Current.FilterChips;
  // Kontextabhängige Vorlagen des Servers (#51) hängen an derselben Einstellung.
  FSources.SetSnippetsEnabled(TAtlasIdeSettings.Current.Snippets);
  // Eigene Vorlagen auch ohne Code-Vorlagen in der Liste lesen: Postfix-Vorlagen (#188) hängen an
  // completion.postfixTemplates.
  RefreshSnippets;
  SendPostfixTemplates;
  if TAtlasIdeSettings.Current.Learning then
  begin
    FController.Usage := TAtlasIdeHistory.Instance;
  end
  else
  begin
    FController.Usage := nil;
  end;
  // Favoriten (#458): abgeschaltet weder Stern noch Sonderstellung.
  FPopup.FavoritesEnabled := TAtlasIdeSettings.Current.Favorites;
  FPopup.SelectionMarker := TAtlasIdeSettings.Current.SelectionMarker;
  if TAtlasIdeSettings.Current.Favorites then
  begin
    FController.Favorites := TAtlasIdeFavorites.Instance;
  end
  else
  begin
    FController.Favorites := nil;
  end;
end;

procedure TAtlasEditorCompletionOpen.StartDelay(const AView: IOTAEditView; ALine, ACharacter: Integer;
  AWindow: HWND);
begin
  FDelay.View := AView;
  FDelay.Line := ALine;
  FDelay.Character := ACharacter;
  FDelay.Window := AWindow;
  FDelay.State := WindowState(AView, AWindow, AWindow);
  FDelay.Timer.Interval := Cardinal(TAtlasIdeSettings.Current.OpenDelayMs);
  FDelay.Timer.Enabled := True;
end;

procedure TAtlasEditorCompletionOpen.Anchor(const AView: IOTAEditView; AWindow: HWND; ACaret: TRect; ALine,
  AWordStart: Integer; const APrefix: string);
begin
  // Das Popup beginnt am Wortanfang, nicht am Caret.
  FPopup.Canvas.Font := FPopup.Font;
  ACaret.Left := ACaret.Left - FPopup.Canvas.TextWidth(APrefix);
  FPopup.Anchor := ACaret;
  FOpen.View := AView;
  FOpen.Window := AWindow;
  FOpen.Line := ALine;
  FOpen.WordStart := AWordStart;
  FOpen.Opened := WindowState(AView, AWindow, AWindow);
end;

function TAtlasEditorCompletionOpen.Invoke(const AView: IOTAEditView): Boolean;
begin
  Result := Invoke(AView, False);
end;

function TAtlasEditorCompletionOpen.Invoke(const AView: IOTAEditView; AAutomatic: Boolean): Boolean;
var
  mContext: TAtlasContext;
  mLineText: string;
  mCursor: TOTAEditPos;
  mCharacter, mWordStart: Integer;
  mWindow: HWND;
  mAnchor: TRect;
  mStarted: Int64;
begin
  Result := False;
  // Diagnosemodus (#479): Kontext ab hier messen.
  mStarted := 0;
  if TAtlasQueryTimings.Enabled then
  begin
    mStarted := TAtlasQueryTimings.Stamp;
  end;
  if (AView = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  mCursor := AView.CursorPos;
  mLineText := TAtlasEditorBuffer.LineText(AView, mCursor.Line);
  mCharacter := TLspSession.ColumnToIndex(mLineText, mCursor.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer));
  mWordStart := TAtlasWord.StartBefore(mLineText, mCharacter);
  if not CaretRect(mWindow, mAnchor) then
  begin
    Log('Vervollständigung: kein Caret gefunden');
    Exit;
  end;
  CancelDelay;
  // Verzögerung bis zum Öffnen (ARG-046): nur beim automatischen Auslösen; DelayTimerTick ruft wieder auf.
  if AAutomatic and not FDelay.Running and (TAtlasIdeSettings.Current.OpenDelayMs > 0) then
  begin
    StartDelay(AView, mCursor.Line, mCharacter, mWindow);
    Exit(True);
  end;
  mContext := ContextAt(AView, mLineText, mCursor.Line, mCharacter, mWordStart);
  mContext.Automatic := AAutomatic;
  mContext.Started := mStarted;
  // Mit Esc geschlossen (#414): im selben Wort nicht automatisch wieder öffnen.
  if AAutomatic and FController.Dismissed(mContext) then
  begin
    Exit;
  end;
  if AAutomatic then
  begin
    mContext.Trigger := AutomaticTrigger(AView, mLineText, mCharacter);
  end;
  FGuard.NewLine := False;
  FCall.Opened := False;
  ApplyStyle(mAnchor);
  ApplyOptions;
  Anchor(AView, mWindow, mAnchor, mCursor.Line, mWordStart, mContext.Prefix);
  // Ohne Datei- und Bezeichnernamen: Das Diagnoselog soll weitergegeben werden können (#647).
  Log(Format('Vervollständigung (%s): Zeile %d, Zeichen %d, Präfix %d Zeichen',
    [ExtractFileExt(mContext.FileName), mContext.Line + 1, mContext.Character, Length(mContext.Prefix)]));
  FController.Start(mContext);
  ActiveChanged;
  Result := True;
end;

procedure TAtlasEditorCompletionOpen.DelayTimerTick(Sender: TObject);
var
  mView: IOTAEditView;
  mLineText: string;
  mCharacter: Integer;
  mSame: Boolean;
begin
  mView := FDelay.View;
  CancelDelay;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  try
    mSame := mView.CursorPos.Line = FDelay.Line;
    mLineText := TAtlasEditorBuffer.LineText(mView, mView.CursorPos.Line);
    mCharacter := TLspSession.ColumnToIndex(mLineText, mView.CursorPos.Col,
      TAtlasEditorBuffer.TabWidth(mView.Buffer));
    if not TAtlasCloseRules.DelayedOpen(FDelay.State, WindowState(mView, FDelay.Window, GetFocus), mSame,
      mLineText, FDelay.Character, mCharacter) then
    begin
      Log('Vervollständigung: verzögertes Öffnen verworfen');
      Exit;
    end;
    FDelay.Running := True;
    try
      Invoke(mView, True);
    finally
      FDelay.Running := False;
    end;
  except
    on E: Exception do
    begin
      Log('Vervollständigung: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
    end;
  end;
end;

end.
