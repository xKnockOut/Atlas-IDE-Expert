unit Atlas.IDE.Completion.EditorState;

// Vervollständigung im Editor (#410), unterste Stufe: Verträge zur Kompositionswurzel, Zustand der offenen Liste
// und Schließen. Die Klasse ist nach Aufgaben in eine Kette geteilt, damit jede Stufe überschaubar bleibt:
//   TAtlasEditorCompletionState (Zustand, Schließen, Tastatur-Hook) → TAtlasEditorCompletionSnippets (Code-Vorlagen
//   lesen, Postfix-Vorlagen) → TAtlasEditorCompletionOpen (Öffnen, Verzögerung) → TAtlasEditorCompletionCommit
//   (Übernehmen, Vorlagen einsetzen) → TAtlasEditorCompletion (Atlas.IDE.Completion.Editor: Tasten, Weitertippen,
//   Detailpanel, Vorschau). Aufrufer verwenden nur TAtlasEditorCompletion; Beschreibung des Ablaufs dort.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Types,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Composite,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Completion.Parentheses,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Editor.CloseRules,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Completion.Preview,
  Atlas.IDE.Completion.Placeholders,
  Atlas.UI.Completion.Popup,
  Atlas.IDE.Foundation.KeyHook;

type
  /// <summary>Protokoll für die Diagnose (Registry-Wert Diagnose).</summary>
  TAtlasLogProc = reference to procedure(const AMessage: string);

  /// <summary>Quellen der Vervollständigung aus dem Kern (Server, XMLDoc, Code-Vorlagen); setzt die
  /// Kompositionswurzel ein (A-09). Die Funktionen wirken auf Server- und Vorlagenquelle.</summary>
  TAtlasCompletionSources = record
    /// <summary>Server; unterstützt auch IAtlasCompletionResolver.</summary>
    Server: IAtlasCompletionProvider;
    XmlDoc: IAtlasCompletionProvider;
    Snippets: IAtlasCompletionProvider;
    /// <summary>Bricht laufende Anfragen von Server und Vorlagen ab und wartet auf sie.</summary>
    Shutdown: TProc;
    /// <summary>Code-Vorlagen in der Liste und kontextabhängige Vorlagen des Servers ein/aus.</summary>
    SetSnippetsEnabled: TProc<Boolean>;
    SetSnippetList: TProc<TAtlasSnippetList>;
    SnippetList: TFunc<TAtlasSnippetList>;
  end;

  TAtlasCompletionSourcesFactory = reference to function(const ASession: TAtlasSessionFunc;
    const ALog: TAtlasLogProc): TAtlasCompletionSources;

  /// <summary>Eigene Code-Vorlagen (#51): Stand des Ordners, letzte Prüfung; Postfix-Vorlagen (#188) gehen an den
  /// Server, neu nach Änderung, neuem Server oder einer Minute; Dateivorlagen (#759) für „Neu mit Atlas“.</summary>
  TAtlasEditorSnippetState = record
    Postfix: TAtlasSnippetList;
    Files: TAtlasSnippetList;
    PostfixSession: TLspSession;
    PostfixSent: UInt64;
    Stamp: string;
    Checked: UInt64;
  end;

  /// <summary>Detailpanel (#424): Schlüssel des gewählten Eintrags, Zeitpunkt der Anfrage, schon angefragt;
  /// gezeigte Überladung (#425).</summary>
  TAtlasEditorDetailState = record
    Key: string;
    Due: UInt64;
    Requested: Boolean;
    OverloadIndex: Integer;
  end;

  /// <summary>Verzögertes automatisches Öffnen (ARG-046): Ansicht, Zeile, Zeichen und Fenster beim Auslösen.
  /// </summary>
  TAtlasEditorDelay = record
    Timer: TTimer;
    View: IOTAEditView;
    Line: Integer;
    Character: Integer;
    Window: HWND;
    State: TAtlasEditorWindowState;
    /// <summary>Invoke kommt gerade aus dem Zeitgeber.</summary>
    Running: Boolean;
  end;

  /// <summary>Zustand der offenen Vervollständigung; Fenster beim Öffnen (Fokus, oberste Zeile, Größe) für
  /// TAtlasCloseRules (#414).</summary>
  TAtlasEditorOpenState = record
    View: IOTAEditView;
    Window: HWND;
    Line: Integer;
    WordStart: Integer;
    Opened: TAtlasEditorWindowState;
  end;

  /// <summary>Commit über ein Zeichen (#429): Ende des Worts (-1 ohne) und Bytes des stehen bleibenden Zeichens.
  /// </summary>
  TAtlasEditorCommitChar = record
    WordEnd: Integer;
    SuffixBytes: Integer;
  end;

  /// <summary>Freigabe absichern (#489): Zeile (ab 1) und Datei des zuletzt übernommenen Konstruktors (0 ohne);
  /// NewLine: Das nächste automatische Öffnen kommt vom Enter am Ende dieser Zeile.</summary>
  TAtlasEditorGuard = record
    Line: Integer;
    FileName: string;
    NewLine: Boolean;
  end;

  /// <summary>"(" hinter einem Namen (#472): Das nächste automatische Öffnen kommt von dort; Stelle des zuletzt
  /// gefragten "(" (Datei, Zeile ab 1, Zeichen), damit Atlas nicht doppelt fragt.</summary>
  TAtlasEditorCall = record
    Opened: Boolean;
    FileName: string;
    Line: Integer;
    Character: Integer;
  end;

  TAtlasEditorCompletionState = class
  protected
    FSession: TAtlasSessionFunc;
    FProviders: TAtlasCompletionProviders;
    FProvidersRef: IAtlasCompletionProvider;
    FSources: TAtlasCompletionSources;
    FSnippets: TAtlasEditorSnippetState;
    FPlaceholders: TAtlasEditorPlaceholders;
    FPopup: TAtlasCompletionPopup;
    FDetails: TAtlasEditorDetailState;
    // Automatisch eingefügte ")" nach dem Übernehmen (#430).
    FAutoParen: TAtlasAutoParen;
    FOnOpenSignature: TProc;
    // Vorschau des gewählten Eintrags im Editor (#434).
    FPreview: TAtlasEditorPreview;
    FController: TAtlasCompletionController;
    FTimer: TTimer;
    FDelay: TAtlasEditorDelay;
    FKeys: TAtlasKeyClient;
    FNotifierIndex: Integer;
    FLog: TAtlasLogProc;
    FOpen: TAtlasEditorOpenState;
    FCommitChar: TAtlasEditorCommitChar;
    FGuard: TAtlasEditorGuard;
    FCall: TAtlasEditorCall;
    /// <summary>Ereignisse des Popups, die nur Ablauf, Einstellungen und Navigation brauchen.</summary>
    procedure WirePopup;
    procedure Log(const AMessage: string);
    procedure CancelDelay;
    procedure ActiveChanged;
    procedure HideDetails;
    procedure InstallKeyHook;
    procedure RemoveKeyHook;
    /// <summary>Indiziert der Server gerade (#492)?</summary>
    function IndexingNow: Boolean;
    /// <summary>Zustand für TAtlasCloseRules (#414); AWindow ist das Editorfenster mit dem Caret.</summary>
    class function WindowState(const AView: IOTAEditView; AWindow, AFocus: HWND): TAtlasEditorWindowState; static;
  public
    /// <summary>ASources legt die Quellen des Kerns an (Kompositionswurzel).</summary>
    constructor Create(const ASession: TAtlasSessionFunc; const ALog: TAtlasLogProc;
      const ASources: TAtlasCompletionSourcesFactory);
    destructor Destroy; override;
    procedure Close;
    /// <summary>Andere Ansicht im Editor: Popup schließen und Platzhalter-Modus beenden.</summary>
    procedure ViewChanged;
    /// <summary>Bricht laufende Serveranfragen ab und wartet auf sie; vor dem Freigeben der Sitzung.</summary>
    procedure Shutdown;
    function Visible: Boolean;
    /// <summary>Läuft gerade der Platzhalter-Modus einer Vorlage (#51)?</summary>
    function PlaceholdersActive: Boolean;
    /// <summary>Wurde in der Zeile des Cursors gerade ein Konstruktor übernommen (#489)? Dann fragt ";" dort
    /// nach „Mit try…finally absichern“.</summary>
    function GuardPending(const AView: IOTAEditView): Boolean;
    /// <summary>Hat Enter die Zeile des übernommenen Konstruktors gerade beendet (#489)? Der Cursor steht dann
    /// in einer leeren Zeile direkt darunter.</summary>
    function GuardNewLine(const AView: IOTAEditView): Boolean;
    /// <summary>Nach dem Übernehmen mit Klammern den Parameter-Hint öffnen (#430).</summary>
    property OnOpenSignature: TProc read FOnOpenSignature write FOnOpenSignature;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  Winapi.ShellAPI,
  Vcl.Forms,
  Atlas.Core.Documentation.Layout,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.EditorBuffer;

const
  /// <summary>Takt, in dem die offene Liste Cursor, Details und Vorschau prüft.</summary>
  cTickMs = 50;

/// <summary>Größe des Editorfensters (Client-Bereich); (0, 0) ohne Fenster.</summary>
function EditorSize(AWindow: HWND): TPoint;
var
  mArea: TRect;
begin
  if (AWindow <> 0) and GetClientRect(AWindow, mArea) then
  begin
    Result := Point(mArea.Width, mArea.Height);
  end
  else
  begin
    Result := Point(0, 0);
  end;
end;

/// <summary>Gezogene Breiten (#416) und eingeklapptes Panel (#428) gelten auch beim nächsten Mal.</summary>
procedure WireSettings(APopup: TAtlasCompletionPopup);
begin
  APopup.OnWidthsChanged :=
    procedure(AListWidth, APanelWidth: Integer)
    var
      mSettings: TAtlasPluginSettings;
    begin
      mSettings := TAtlasIdeSettings.Stored;
      mSettings.ListWidth := AListWidth;
      mSettings.PanelWidth := APanelWidth;
      TAtlasIdeSettings.Update(mSettings);
    end;
  APopup.OnPanelToggled :=
    procedure(ACollapsed: Boolean)
    var
      mSettings: TAtlasPluginSettings;
    begin
      mSettings := TAtlasIdeSettings.Stored;
      mSettings.PanelCollapsed := ACollapsed;
      TAtlasIdeSettings.Update(mSettings);
    end;
end;

{ TAtlasEditorCompletionState }

constructor TAtlasEditorCompletionState.Create(const ASession: TAtlasSessionFunc; const ALog: TAtlasLogProc;
  const ASources: TAtlasCompletionSourcesFactory);
begin
  inherited Create;
  FSession := ASession;
  FLog := ALog;
  FNotifierIndex := -1;
  FCommitChar.WordEnd := -1;
  FProviders := TAtlasCompletionProviders.Create;
  FProvidersRef := FProviders;
  FSources := ASources(ASession,
    procedure(const AMessage: string)
    begin
      Log(AMessage);
    end);
  FProviders.Add(FSources.Server);
  // XMLDoc-Tags in ///-Kommentaren (#435), lokal.
  FProviders.Add(FSources.XmlDoc);
  // Code-Vorlagen (#51), lokal; die eigenen liest RefreshSnippets beim ersten Öffnen.
  FProviders.Add(FSources.Snippets);
  FPlaceholders := TAtlasEditorPlaceholders.Create;
  FPopup := TAtlasCompletionPopup.Create(nil);
  FController := TAtlasCompletionController.Create(FProvidersRef, FPopup);
  WirePopup;
  FPreview := TAtlasEditorPreview.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTickMs;
  FDelay.Timer := TTimer.Create(nil);
  FDelay.Timer.Enabled := False;
end;

destructor TAtlasEditorCompletionState.Destroy;
begin
  // Erst schließen und Anfragen beenden, solange Zeitgeber und Vorschau noch bestehen; dann freigeben.
  Shutdown;
  RemoveKeyHook;
  FreeAndNil(FPlaceholders);
  FreeAndNil(FPreview);
  FTimer.Free;
  FDelay.Timer.Free;
  FController.Free;
  FPopup.Free;
  FKeys.Free;
  FSources := Default(TAtlasCompletionSources);
  FProvidersRef := nil;
  inherited;
end;

procedure TAtlasEditorCompletionState.WirePopup;
begin
  FPopup.OnSelect :=
    procedure(APosition: Integer)
    begin
      FController.Select(APosition);
    end;
  // XMLDoc im Panel (#654): Links im Browser, Verweise mit Strg+Klick zur Deklaration.
  FPopup.OnDocLink :=
    procedure(const ALink: TAtlasDocLink; AControl: Boolean)
    begin
      if ALink.Kind = TAtlasDocLinkKind.Url then
      begin
        if StartsText('http://', ALink.Url) or StartsText('https://', ALink.Url) or
          StartsText('mailto:', ALink.Url) then
        begin
          ShellExecute(0, 'open', PChar(ALink.Url), nil, nil, SW_SHOWNORMAL);
        end;
      end
      else if AControl and ALink.Target.HasLocation then
      begin
        Close;
        TAtlasIdeNavigation.GoToLocation(ALink.Target.FileName, ALink.Target.Line, ALink.Target.Character);
      end;
    end;
  // Zeilenangabe der Warnleiste (#457): Liste schließen, Caret an den Fehler.
  FPopup.OnSyntaxLine :=
    procedure(ALine, ACharacter: Integer)
    begin
      Close;
      TAtlasIdeNavigation.GoToPosition(ALine, Max(0, ACharacter));
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
  WireSettings(FPopup);
end;

class function TAtlasEditorCompletionState.WindowState(const AView: IOTAEditView; AWindow,
  AFocus: HWND): TAtlasEditorWindowState;
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

procedure TAtlasEditorCompletionState.Log(const AMessage: string);
begin
  if Assigned(FLog) then
  begin
    FLog(AMessage);
  end;
end;

procedure TAtlasEditorCompletionState.Shutdown;
begin
  Close;
  if Assigned(FSources.Shutdown) then
  begin
    FSources.Shutdown();
  end;
end;

function TAtlasEditorCompletionState.IndexingNow: Boolean;
var
  mSession: TLspSession;
begin
  Result := False;
  if not Assigned(FSession) then
  begin
    Exit;
  end;
  mSession := FSession();
  Result := (mSession <> nil) and (mSession.IndexingText <> '');
end;

function TAtlasEditorCompletionState.PlaceholdersActive: Boolean;
begin
  Result := (FPlaceholders <> nil) and FPlaceholders.Active;
end;

function TAtlasEditorCompletionState.Visible: Boolean;
begin
  // Auch der leere Zustand (#423) nimmt Esc entgegen.
  Result := FController.Visible or FController.Empty;
end;

procedure TAtlasEditorCompletionState.CancelDelay;
begin
  FDelay.Timer.Enabled := False;
  FDelay.View := nil;
end;

procedure TAtlasEditorCompletionState.Close;
begin
  CancelDelay;
  FController.Close;
  if FPreview <> nil then
  begin
    FPreview.Clear;
  end;
  ActiveChanged;
end;

procedure TAtlasEditorCompletionState.ViewChanged;
begin
  Close;
  if FPlaceholders <> nil then
  begin
    FPlaceholders.Stop;
  end;
end;

procedure TAtlasEditorCompletionState.ActiveChanged;
begin
  FTimer.Enabled := FController.Active;
  if not FController.Active and (FPreview <> nil) then
  begin
    FPreview.Clear;
  end;
  if FController.Active then
  begin
    InstallKeyHook;
  end
  else
  begin
    RemoveKeyHook;
    HideDetails;
    FOpen.View := nil;
  end;
end;

procedure TAtlasEditorCompletionState.InstallKeyHook;
begin
  TAtlasKeyHook.Add(FKeys);
  if not TAtlasKeyHook.Installed then
  begin
    Log('Vervollständigung: Tastatur-Hook nicht möglich: ' + SysErrorMessage(GetLastError));
  end;
end;

procedure TAtlasEditorCompletionState.RemoveKeyHook;
begin
  TAtlasKeyHook.Remove(FKeys);
end;

procedure TAtlasEditorCompletionState.HideDetails;
begin
  FPopup.ClearDetails;
  FDetails.Key := '';
  FDetails.Requested := False;
end;

function TAtlasEditorCompletionState.GuardNewLine(const AView: IOTAEditView): Boolean;
begin
  Result := (FGuard.Line > 0) and (AView <> nil) and (AView.Buffer <> nil) and
    (AView.CursorPos.Line = FGuard.Line + 1) and SameText(AView.Buffer.FileName, FGuard.FileName) and
    (Trim(TAtlasEditorBuffer.LineText(AView, AView.CursorPos.Line)) = '') and
    not TAtlasEditorBuffer.LineText(AView, FGuard.Line).TrimRight.EndsWith(';');
end;

function TAtlasEditorCompletionState.GuardPending(const AView: IOTAEditView): Boolean;
begin
  Result := (FGuard.Line > 0) and (AView <> nil) and (AView.Buffer <> nil) and
    (AView.CursorPos.Line = FGuard.Line) and SameText(AView.Buffer.FileName, FGuard.FileName);
end;

end.
