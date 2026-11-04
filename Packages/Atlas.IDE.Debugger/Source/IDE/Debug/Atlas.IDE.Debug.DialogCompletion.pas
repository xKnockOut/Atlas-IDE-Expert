unit Atlas.IDE.Debug.DialogCompletion;

// Vervollständigung in den Debugger-Dialogen (#538) in der IDE:
//   - Ein Zeitgeber (100 ms) sieht nach dem Eingabefeld mit dem Fokus. Gehört
//     es zu einem VCL-Formular, das TAtlasDebugDialogs als „Auswerten/Ändern“,
//     Überwachung oder Haltepunkt erkennt, und ist es das Feld für Ausdruck,
//     Bedingung oder Log-Ausdruck (Beschriftung über FocusControl, sonst das
//     nächste Label links bzw. darüber), folgt Atlas ihm. Klasse, Titel und
//     Beschriftungen eines erkannten Dialogs stehen einmal im Diagnoselog,
//     damit sich die Erkennung für neue Delphi-Versionen nachziehen lässt.
//   - Getippt wird wie im Editor: Ein Buchstabe am Wortanfang oder „.“ öffnet
//     das Atlas-Popup (#410) über TAtlasCompletionController, Weitertippen
//     filtert, Strg+Leer öffnet von Hand. Pfeiltasten, Bild auf/ab, Enter, Tab
//     und Esc gehören dem Popup, solange es offen ist (TAtlasKeyHook, auch in
//     modalen Dialogen). Übernehmen ersetzt das Wort an der Schreibmarke über
//     EM_SETSEL/EM_REPLACESEL (Strg+Z im Feld nimmt es zurück).
//   - Gültigkeitsbereich: im Haltepunktdialog Datei und Zeilennummer aus
//     dessen Feldern, bei angehaltenem Programm der Ausführungspunkt, sonst die
//     Cursorzeile im Editor. Die Datei wird im Hauptthread abgeglichen
//     (Editorpuffer, sonst von der Platte); die Anfrage
//     atlas/expressionCompletion läuft im Hintergrund. Ohne laufenden Server
//     bleibt die Liste leer; Atlas startet keinen.
//   - Verlauf: Ausdrücke, die ausgewertet wurden (das Feld ist danach ganz
//     markiert) oder mit denen das Feld verlassen wurde, kommen in
//     %LOCALAPPDATA%\Atlas\debug-expressions.json, 20 je Projekt. Pfeil nach
//     unten im leeren Feld zeigt sie; Übernehmen ersetzt das ganze Feld.
//   - Fenster „Auswerten“ (#784): Sein Eingabefeld meldet OwnField; es gilt
//     als Ausdrucksfeld von „Auswerten/Ändern“. Verlauf (50 je Projekt) und
//     Pfeil nach unten im leeren Feld übernimmt dort das Fenster selbst.
// Ohne debug.completionInDialogs läuft kein Zeitgeber und kein Hook. Nur im
// Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Debug.DialogCompletion,
  Atlas.UI.Completion.Popup,
  Atlas.IDE.Foundation.KeyHook;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasDialogSessionFunc = TAtlasSessionFunc;

  /// <summary>Datenquelle des Popups; AHistory liefert den Verlauf des aktuellen Projekts (auch im Hintergrund).
  /// Die Komposition erzeugt sie (Rollenmatrix: Providers nur dort).</summary>
  TAtlasDialogProviderFactory = reference to function(const AHistory: TFunc<TArray<string>>):
    IAtlasCompletionProvider;

  TAtlasIdeDebugDialogCompletion = class
  public const
    TickMs = 100;
    HistoryFileName = 'debug-expressions.json';
  private type
    TKeys = class(TAtlasKeyClient)
    protected
      function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
      procedure HandleKey(AKey: Word; AShift: TShiftState); override;
    end;
    /// <summary>Verlauf der Ausdrücke je Projekt; Items auch im Hintergrund (unter der Sperre).</summary>
    THistoryStore = class
    private
      FHistory: TAtlasExpressionHistory;
      FLock: TCriticalSection;
      FLoaded: Boolean;
      FKept: Boolean;
      FProject: string;
    public
      constructor Create;
      destructor Destroy; override;
      /// <summary>Einmal aus HistoryFile lesen.</summary>
      procedure Load;
      /// <summary>Projekt, dessen Ausdrücke Items liefert.</summary>
      procedure UseProject(const AProject: string);
      function Items: TArray<string>;
      /// <summary>AExpression zum aktuellen Projekt aufnehmen und speichern.</summary>
      procedure Add(const AExpression: string);
    end;
  public class var
    /// <summary>True für das Eingabefeld des Fensters „Auswerten“ (#784); setzt TAtlasIdeDebugEvaluate.</summary>
    OwnField: TFunc<TWinControl, Boolean>;
  private class var
    FInstance: TAtlasIdeDebugDialogCompletion;
  private
    FSession: TAtlasDialogSessionFunc;
    FLog: TProc<string>;
    FTimer: TTimer;
    FProviderRef: IAtlasCompletionProvider;
    FPopup: TAtlasCompletionPopup;
    FController: TAtlasCompletionController;
    FKeys: TKeys;
    FHistory: THistoryStore;
    // Verfolgtes Feld.
    FEdit: HWND;
    FForm: TCustomForm;
    FDialog: TAtlasDebugDialog;
    FText: string;
    FCaret: Integer;
    FAllSelected: Boolean;
    FWordStart: Integer;
    FHistoryMode: Boolean;
    // Feld des Atlas-Fensters „Auswerten“: ohne eigenen Verlauf.
    FOwnField: Boolean;
    FLogged: TStringList;
    constructor Create(const ASession: TAtlasDialogSessionFunc; const ALog: TProc<string>;
      const AProvider: TAtlasDialogProviderFactory);
    procedure Tick(Sender: TObject);
    procedure Step;
    /// <summary>Text oder Schreibmarke des Felds geändert: Popup öffnen, filtern oder schließen.</summary>
    procedure Follow(const AText: string; ACaret: Integer);
    procedure Track(AFocus: HWND);
    procedure Untrack;
    procedure Remember(const AExpression: string);
    procedure Query(AHistory, AAutomatic: Boolean);
    procedure Commit(const AItem: TAtlasCompletionItem);
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure HandleKey(AKey: Word);
    procedure Say(const AText: string);
    procedure LogDialog(AForm: TCustomForm);
  public
    destructor Destroy; override;
    /// <summary>ALog: Zeile fürs Diagnoselog.</summary>
    class procedure Start(const ASession: TAtlasDialogSessionFunc; const ALog: TProc<string>;
      const AProvider: TAtlasDialogProviderFactory); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.completionInDialogs an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
    class procedure ApplySettings; static;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  Winapi.Messages,
  Vcl.StdCtrls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Sources;

type
  // FocusControl ist in TCustomLabel geschützt.
  TLabelAccess = class(TCustomLabel);

function NavigationOf(AKey: Word; out ANavigation: TAtlasNavigationKey): Boolean;
begin
  Result := True;
  case AKey of
    VK_UP: ANavigation := TAtlasNavigationKey.Up;
    VK_DOWN: ANavigation := TAtlasNavigationKey.Down;
    VK_PRIOR: ANavigation := TAtlasNavigationKey.PageUp;
    VK_NEXT: ANavigation := TAtlasNavigationKey.PageDown;
    VK_RETURN, VK_TAB: ANavigation := TAtlasNavigationKey.Accept;
    VK_ESCAPE: ANavigation := TAtlasNavigationKey.Cancel;
  else
    Result := False;
  end;
end;

function WindowText(AWindow: HWND): string;
var
  mCount: Integer;
begin
  Result := '';
  mCount := SendMessage(AWindow, WM_GETTEXTLENGTH, 0, 0);
  if mCount <= 0 then
  begin
    Exit;
  end;
  SetLength(Result, mCount + 1);
  mCount := SendMessage(AWindow, WM_GETTEXT, mCount + 1, LPARAM(PChar(Result)));
  SetLength(Result, Max(mCount, 0));
end;

procedure Selection(AWindow: HWND; out AStart, AStop: Integer);
var
  mStart, mStop: DWORD;
begin
  mStart := 0;
  mStop := 0;
  SendMessage(AWindow, EM_GETSEL, WPARAM(@mStart), LPARAM(@mStop));
  AStart := Integer(mStart);
  AStop := Integer(mStop);
end;

function EditControl(AFocus: HWND): TWinControl;
begin
  // Ein Kombinationsfeld hat das Eingabefeld als eigenes Fenster ohne VCL-Objekt.
  Result := FindControl(AFocus);
  if Result = nil then
  begin
    Result := FindControl(GetParent(AFocus));
  end;
  if (Result <> nil) and not ((Result is TCustomEdit) or (Result is TCustomComboBox)) then
  begin
    Result := nil;
  end;
end;

function HistoryFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TAtlasIdeDebugDialogCompletion.HistoryFileName);
end;

function CurrentProject: string;
var
  mProject: IOTAProject;
begin
  // Beim Debuggen das gestartete Projekt, sonst das aktive.
  Result := TAtlasIdeDebugSession.LaunchProject;
  if Result <> '' then
  begin
    Exit;
  end;
  mProject := GetActiveProject;
  if mProject <> nil then
  begin
    Result := mProject.FileName;
  end;
end;

/// <summary>Label mit FocusControl = AControl; False ohne.</summary>
function FocusLabel(AForm: TCustomForm; AControl: TWinControl; out ACaption: string): Boolean;
var
  mIndex: Integer;
  mComponent: TComponent;
begin
  Result := False;
  ACaption := '';
  mIndex := 0;
  while not Result and (mIndex < AForm.ComponentCount) do
  begin
    mComponent := AForm.Components[mIndex];
    if (mComponent is TCustomLabel) and (TLabelAccess(mComponent).FocusControl = AControl) then
    begin
      ACaption := TLabelAccess(mComponent).Caption;
      Result := True;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Abstand des Labels ABounds zum Feld AOwn: links in derselben Höhe oder direkt darüber; False sonst.
/// </summary>
function LabelDistance(const ABounds, AOwn: TRect; out ADistance: Integer): Boolean;
begin
  Result := True;
  ADistance := 0;
  if (ABounds.Right <= AOwn.Left + 4) and (ABounds.Bottom > AOwn.Top) and (ABounds.Top < AOwn.Bottom) then
  begin
    ADistance := AOwn.Left - ABounds.Right;
  end
  else if (ABounds.Bottom <= AOwn.Top + 4) and (ABounds.Left < AOwn.Right) and (ABounds.Right > AOwn.Left) then
  begin
    ADistance := AOwn.Top - ABounds.Bottom;
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Nächstes sichtbares Label im selben Container wie AControl; '' ohne.</summary>
function NearestLabel(AControl: TWinControl): string;
var
  mIndex, mDistance, mBest: Integer;
  mControl: TControl;
begin
  Result := '';
  if AControl.Parent = nil then
  begin
    Exit;
  end;
  mBest := MaxInt;
  for mIndex := 0 to AControl.Parent.ControlCount - 1 do
  begin
    mControl := AControl.Parent.Controls[mIndex];
    if (mControl is TCustomLabel) and mControl.Visible and
      LabelDistance(mControl.BoundsRect, AControl.BoundsRect, mDistance) and (mDistance < mBest) then
    begin
      mBest := mDistance;
      Result := TLabelAccess(mControl).Caption;
    end;
  end;
end;

/// <summary>Beschriftung von AControl: Label mit FocusControl, sonst das nächste links bzw. darüber.</summary>
function LabelOf(AForm: TCustomForm; AControl: TWinControl): string;
begin
  if not FocusLabel(AForm, AControl, Result) then
  begin
    Result := NearestLabel(AControl);
  end;
end;

/// <summary>Datei und Zeile aus den Feldern des Haltepunktdialogs AForm.</summary>
function BreakpointScope(AForm: TCustomForm; ADialog: TAtlasDebugDialog; out AFileName: string;
  out ALine: Integer): Boolean;
var
  mIndex: Integer;
  mComponent: TComponent;
  mControl: TWinControl;
  mFileText, mLineText: string;
begin
  mFileText := '';
  mLineText := '';
  for mIndex := 0 to AForm.ComponentCount - 1 do
  begin
    mComponent := AForm.Components[mIndex];
    if ((mComponent is TCustomEdit) or (mComponent is TCustomComboBox)) and
      TWinControl(mComponent).HandleAllocated then
    begin
      mControl := TWinControl(mComponent);
      case TAtlasDebugDialogs.FieldOf(ADialog, LabelOf(AForm, mControl)) of
        TAtlasDebugField.FileName: mFileText := Trim(WindowText(mControl.Handle));
        TAtlasDebugField.LineNumber: mLineText := WindowText(mControl.Handle);
      end;
    end;
  end;
  ALine := TAtlasDebugDialogs.ScopeLine(mLineText);
  AFileName := '';
  if mFileText <> '' then
  begin
    AFileName := TAtlasIdeDebugSources.Resolve(mFileText);
  end;
  Result := (AFileName <> '') and (ALine >= 0);
end;

/// <summary>Ausführungspunkt des angehaltenen Programms; False ohne Halt mit Quelltext.</summary>
function StopScope(out AFileName: string; out ALine: Integer): Boolean;
var
  mFrames: TAtlasDebugFrames;
begin
  AFileName := '';
  ALine := -1;
  Result := (TAtlasIdeDebugSession.StoppedThread <> nil) and
    (TAtlasIdeDebugSession.ReadStack(TAtlasIdeDebugSession.StoppedThread, 1, mFrames) = TAtlasDebugStackRead.Ready)
    and (Length(mFrames) > 0) and mFrames[0].HasSource;
  if Result then
  begin
    TAtlasIdeDebugSources.MarkFrames(mFrames);
    AFileName := mFrames[0].FileName;
    ALine := mFrames[0].Line - 1;
  end;
end;

/// <summary>Cursorzeile im Editor; False ohne Editor.</summary>
function EditorScope(out AFileName: string; out ALine: Integer): Boolean;
var
  mView: IOTAEditView;
begin
  AFileName := '';
  ALine := -1;
  mView := TAtlasEditorBuffer.ActiveView;
  Result := (mView <> nil) and (mView.Buffer <> nil);
  if Result then
  begin
    AFileName := mView.Buffer.FileName;
    ALine := mView.CursorPos.Line - 1;
  end;
end;

/// <summary>Gültigkeitsbereich: Haltepunktdialog, sonst Ausführungspunkt, sonst die Cursorzeile im Editor.</summary>
function Scope(AForm: TCustomForm; ADialog: TAtlasDebugDialog; out AFileName: string; out ALine: Integer): Boolean;
begin
  Result := ((ADialog = TAtlasDebugDialog.Breakpoint) and BreakpointScope(AForm, ADialog, AFileName, ALine)) or
    StopScope(AFileName, ALine) or EditorScope(AFileName, ALine);
end;

/// <summary>Quelltext von AFileName: Editorpuffer, sonst von der Platte; False, wenn unlesbar.</summary>
function SourceOf(const AFileName: string; out ASource: string): Boolean;
var
  mBuffer: IOTAEditBuffer;
begin
  Result := True;
  mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
  if mBuffer <> nil then
  begin
    ASource := TAtlasEditorBuffer.Text(mBuffer);
  end
  else
    try
      ASource := TAtlasTextFile.LoadText(AFileName);
    except
      on Exception do
      begin
        ASource := '';
        Result := False;
      end;
    end;
end;

/// <summary>AContext für den Server ergänzen (Datei, Zeile, Auslöser) und die Datei im Hauptthread abgleichen;
/// False ohne Gültigkeitsbereich oder Quelltext.</summary>
function ServerContext(ASession: TLspSession; AForm: TCustomForm; ADialog: TAtlasDebugDialog;
  var AContext: TAtlasContext): Boolean;
var
  mFileName, mSource: string;
  mLine, mWordStart: Integer;
begin
  Result := Scope(AForm, ADialog, mFileName, mLine) and SourceOf(mFileName, mSource);
  if not Result then
  begin
    Exit;
  end;
  // Im Hauptthread abgleichen: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  ASession.Sync(mFileName, mSource);
  AContext.FileName := mFileName;
  AContext.Line := mLine;
  // Nach "." Mitgliederliste (#497): Zeichen vor dem Wortanfang, 1-basiert an der Stelle des Wortanfangs.
  mWordStart := AContext.Character - Length(AContext.Prefix);
  if (mWordStart > 0) and (mWordStart <= Length(AContext.Text)) and (AContext.Text[mWordStart] = '.') then
  begin
    AContext.Trigger := '.';
  end;
end;

/// <summary>Bildschirmstelle für das Popup: linke Kante des Worts ab AWordStart in AEdit (Text AText).</summary>
function Anchor(AEdit: HWND; AWordStart: Integer; const AText: string): TRect;
var
  mCaret, mOrigin: TPoint;
  mWindow: TRect;
  mPosition: LRESULT;
begin
  GetWindowRect(AEdit, mWindow);
  Result := mWindow;
  // Linke Kante des Worts: EM_POSFROMCHAR gilt nur für vorhandene Zeichen, am Ende die Schreibmarke.
  mPosition := -1;
  if (AWordStart >= 0) and (AWordStart < Length(AText)) then
  begin
    mPosition := SendMessage(AEdit, EM_POSFROMCHAR, WPARAM(AWordStart), 0);
  end;
  if mPosition <> -1 then
  begin
    mCaret := Point(SmallInt(LoWord(DWORD(mPosition))), SmallInt(HiWord(DWORD(mPosition))));
  end
  else if not GetCaretPos(mCaret) then
  begin
    mCaret := Point(0, 0);
  end;
  mOrigin := Point(0, 0);
  ClientToScreen(AEdit, mOrigin);
  Result.Left := mOrigin.X + mCaret.X;
  Result.Right := Result.Left + 1;
end;

{ TAtlasIdeDebugDialogCompletion.THistoryStore }

constructor TAtlasIdeDebugDialogCompletion.THistoryStore.Create;
begin
  inherited Create;
  FHistory := TAtlasExpressionHistory.Create;
  FLock := TCriticalSection.Create;
end;

destructor TAtlasIdeDebugDialogCompletion.THistoryStore.Destroy;
begin
  FLock.Free;
  FHistory.Free;
  inherited;
end;

procedure TAtlasIdeDebugDialogCompletion.THistoryStore.Load;
begin
  if FLoaded then
  begin
    Exit;
  end;
  FLoaded := True;
  // Gesperrt: leer beginnen und die Datei nicht überschreiben; TAtlasDataFile protokolliert ohne Pfad.
  FKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(HistoryFile, 'Verlauf der Debug-Ausdrücke',
    function(const AText: string): Boolean
    begin
      FLock.Acquire;
      try
        Result := FHistory.LoadFromText(AText);
      finally
        FLock.Release;
      end;
    end));
end;

procedure TAtlasIdeDebugDialogCompletion.THistoryStore.UseProject(const AProject: string);
begin
  FLock.Acquire;
  try
    FProject := AProject;
  finally
    FLock.Release;
  end;
end;

function TAtlasIdeDebugDialogCompletion.THistoryStore.Items: TArray<string>;
begin
  FLock.Acquire;
  try
    Result := FHistory.Items(FProject);
  finally
    FLock.Release;
  end;
end;

procedure TAtlasIdeDebugDialogCompletion.THistoryStore.Add(const AExpression: string);
var
  mChanged: Boolean;
  mText: string;
begin
  Load;
  FLock.Acquire;
  try
    mChanged := FHistory.Add(CurrentProject, AExpression);
    mText := FHistory.ToText;
  finally
    FLock.Release;
  end;
  if not mChanged or FKept then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(HistoryFile, mText);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Verlauf der Debug-Ausdrücke', E);
  end;
end;

{ TAtlasIdeDebugDialogCompletion.TKeys }

function TAtlasIdeDebugDialogCompletion.TKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := (TAtlasIdeDebugDialogCompletion.FInstance <> nil) and
    TAtlasIdeDebugDialogCompletion.FInstance.WantsKey(AKey, AShift);
end;

procedure TAtlasIdeDebugDialogCompletion.TKeys.HandleKey(AKey: Word; AShift: TShiftState);
begin
  try
    if TAtlasIdeDebugDialogCompletion.FInstance <> nil then
    begin
      TAtlasIdeDebugDialogCompletion.FInstance.HandleKey(AKey);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

{ TAtlasIdeDebugDialogCompletion }

constructor TAtlasIdeDebugDialogCompletion.Create(const ASession: TAtlasDialogSessionFunc;
  const ALog: TProc<string>; const AProvider: TAtlasDialogProviderFactory);
begin
  inherited Create;
  FSession := ASession;
  FLog := ALog;
  FHistory := THistoryStore.Create;
  FLogged := TStringList.Create;
  FLogged.Sorted := True;
  FLogged.Duplicates := dupIgnore;
  FProviderRef := AProvider(
    function: TArray<string>
    begin
      // Im Hintergrund: nur unter der Sperre lesen. Destroy gibt die Quelle vor der Sperre frei; sie wartet dabei
      // auf ihre Threads.
      Result := FHistory.Items;
    end);
  FPopup := TAtlasCompletionPopup.Create(nil);
  FController := TAtlasCompletionController.Create(FProviderRef, FPopup);
  FController.OnCommit :=
    procedure(const AItem: TAtlasCompletionItem)
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
  FKeys := TKeys.Create(0);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  TAtlasKeyHook.Add(FKeys);
end;

destructor TAtlasIdeDebugDialogCompletion.Destroy;
begin
  // Erst abmelden, dann freigeben: Hook und Zeitgeber riefen sonst in freigegebene Objekte.
  TAtlasKeyHook.Remove(FKeys);
  FTimer.Free;
  if FController <> nil then
  begin
    FController.Close;
  end;
  FController.Free;
  FPopup.Free;
  FProviderRef := nil;
  FKeys.Free;
  FLogged.Free;
  FHistory.Free;
  inherited;
end;

class procedure TAtlasIdeDebugDialogCompletion.Start(const ASession: TAtlasDialogSessionFunc;
  const ALog: TProc<string>; const AProvider: TAtlasDialogProviderFactory);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugDialogCompletion.Create(ASession, ALog, AProvider);
  end;
end;

class procedure TAtlasIdeDebugDialogCompletion.Release;
var
  Instance: TAtlasIdeDebugDialogCompletion;
begin
  Instance := FInstance;
  FInstance := nil;
  Instance.Free;
end;

class function TAtlasIdeDebugDialogCompletion.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugDialogCompletion.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.DebugCompletionInDialogs;
end;

class procedure TAtlasIdeDebugDialogCompletion.ApplySettings;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  FInstance.FPopup.ManualListWidth := TAtlasIdeSettings.Current.ListWidth;
  FInstance.FPopup.PanelWidthSetting := TAtlasIdeSettings.Current.PanelWidth;
  FInstance.FPopup.PanelCollapsed := TAtlasIdeSettings.Current.PanelCollapsed;
  if not Enabled then
  begin
    FInstance.Untrack;
  end;
end;

procedure TAtlasIdeDebugDialogCompletion.Say(const AText: string);
begin
  if Assigned(FLog) then
  begin
    FLog(AText);
  end;
end;

procedure TAtlasIdeDebugDialogCompletion.Remember(const AExpression: string);
begin
  // Das Fenster „Auswerten“ führt seinen Verlauf selbst.
  if not FOwnField then
  begin
    FHistory.Add(AExpression);
  end;
end;

procedure TAtlasIdeDebugDialogCompletion.LogDialog(AForm: TCustomForm);
var
  Key, Labels: string;
  Index: Integer;
begin
  // Ohne Ausdrücke und Pfade: Klasse, Titel und Beschriftungen des Dialogs.
  Key := AForm.ClassName + '|' + AForm.Caption;
  if FLogged.IndexOf(Key) >= 0 then
  begin
    Exit;
  end;
  FLogged.Add(Key);
  Labels := '';
  for Index := 0 to AForm.ComponentCount - 1 do
  begin
    if AForm.Components[Index] is TCustomLabel then
    begin
      Labels := Labels + ' [' + TLabelAccess(AForm.Components[Index]).Caption + ']';
    end;
  end;
  Say(Format('Debug-Dialog erkannt: %s „%s“, Beschriftungen:%s', [AForm.ClassName, AForm.Caption, Labels]));
end;

procedure TAtlasIdeDebugDialogCompletion.Track(AFocus: HWND);
var
  Control: TWinControl;
  Form: TCustomForm;
  Dialog: TAtlasDebugDialog;
  Field: TAtlasDebugField;
  Start, Stop: Integer;
begin
  Control := EditControl(AFocus);
  if Control = nil then
  begin
    Exit;
  end;
  Form := GetParentForm(Control);
  if Form = nil then
  begin
    Exit;
  end;
  FOwnField := Assigned(OwnField) and OwnField(Control);
  if FOwnField then
  begin
    // Angedockt ist Form das Hauptfenster der IDE: an Titel und Klasse nicht zu erkennen.
    Dialog := TAtlasDebugDialog.Evaluate;
    Field := TAtlasDebugField.Expression;
  end
  else
  begin
    Dialog := TAtlasDebugDialogs.DialogOf(Form.ClassName, Form.Caption);
    if Dialog = TAtlasDebugDialog.None then
    begin
      Exit;
    end;
    LogDialog(Form);
    Field := TAtlasDebugDialogs.FieldOf(Dialog, LabelOf(Form, Control));
  end;
  if not TAtlasDebugDialogs.Completes(Field) then
  begin
    Exit;
  end;
  FEdit := AFocus;
  FForm := Form;
  FDialog := Dialog;
  FText := WindowText(FEdit);
  Selection(FEdit, Start, Stop);
  FAllSelected := (FText <> '') and (Start = 0) and (Stop = Length(FText));
  FCaret := Max(Stop, 0);
  FWordStart := -1;
  FHistoryMode := False;
end;

procedure TAtlasIdeDebugDialogCompletion.Untrack;
begin
  if FEdit = 0 then
  begin
    Exit;
  end;
  FController.Close;
  // Mit einem Ausdruck verlassen: in den Verlauf.
  if IsWindow(FEdit) then
  begin
    Remember(WindowText(FEdit));
  end
  else
  begin
    Remember(FText);
  end;
  FEdit := 0;
  FForm := nil;
  FDialog := TAtlasDebugDialog.None;
  FOwnField := False;
  FText := '';
end;

procedure TAtlasIdeDebugDialogCompletion.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      Step;
    end);
end;

procedure TAtlasIdeDebugDialogCompletion.Step;
var
  mFocus: HWND;
  mText: string;
  mStart, mStop: Integer;
  mAllSelected: Boolean;
begin
  if not Enabled then
  begin
    Untrack;
    Exit;
  end;
  mFocus := GetFocus;
  if mFocus <> FEdit then
  begin
    Untrack;
    if mFocus <> 0 then
    begin
      Track(mFocus);
    end;
  end;
  if (FEdit = 0) or not IsWindow(FEdit) then
  begin
    Exit;
  end;
  mText := WindowText(FEdit);
  Selection(FEdit, mStart, mStop);
  mAllSelected := (mText <> '') and (mStart = 0) and (mStop = Length(mText));
  // Ausgewertet: Die IDE markiert danach das ganze Feld.
  if (mText = FText) and mAllSelected and not FAllSelected then
  begin
    Remember(mText);
  end;
  FAllSelected := mAllSelected;
  if (mText <> FText) or (mStop <> FCaret) then
  begin
    Follow(mText, mStop);
  end;
end;

procedure TAtlasIdeDebugDialogCompletion.Follow(const AText: string; ACaret: Integer);
var
  mPrefix: string;
  mOpens: Boolean;
begin
  mOpens := TAtlasExpressionEdit.OpensAfter(FText, AText, ACaret);
  FText := AText;
  FCaret := ACaret;
  mPrefix := TAtlasExpressionEdit.PrefixAt(AText, ACaret);
  if FController.Active then
  begin
    if FHistoryMode or (ACaret - Length(mPrefix) <> FWordStart) then
    begin
      FController.Close;
    end
    else if FController.NeedsQuery(mPrefix) then
    begin
      Query(False, True);
    end
    else
    begin
      FController.UpdatePrefix(mPrefix);
    end;
  end;
  if not FController.Active and mOpens then
  begin
    Query(False, True);
  end;
end;

procedure TAtlasIdeDebugDialogCompletion.Query(AHistory, AAutomatic: Boolean);
var
  mContext: TAtlasContext;
  mSession: TLspSession;
begin
  mContext := Default(TAtlasContext);
  mContext.Automatic := AAutomatic;
  mContext.Text := FText;
  mContext.Character := FCaret;
  mContext.Prefix := TAtlasExpressionEdit.PrefixAt(FText, FCaret);
  FHistory.UseProject(CurrentProject);
  if AHistory then
  begin
    FHistory.Load;
    if Length(FHistory.Items) = 0 then
    begin
      Exit;
    end;
    mContext.Trigger := TAtlasTriggers.History;
    mContext.Prefix := '';
  end
  else
  begin
    mSession := nil;
    if Assigned(FSession) then
    begin
      mSession := FSession();
    end;
    if (mSession = nil) or not ServerContext(mSession, FForm, FDialog, mContext) then
    begin
      Exit;
    end;
  end;
  FHistoryMode := AHistory;
  FWordStart := FCaret - Length(mContext.Prefix);
  FPopup.Anchor := Anchor(FEdit, FWordStart, FText);
  // Ohne Ausdruck, Datei und Zeile: Das Diagnoselog soll weitergegeben werden können (#647).
  Say(Format('Debug-Dialog: Vervollständigung (Verlauf %s, Präfix %d Zeichen)',
    [BoolToStr(AHistory, True), Length(mContext.Prefix)]));
  if FController.Active and not AHistory then
  begin
    FController.Requery(mContext);
  end
  else
  begin
    FController.Start(mContext);
  end;
end;

procedure TAtlasIdeDebugDialogCompletion.Commit(const AItem: TAtlasCompletionItem);
var
  Insert, Text: string;
  Caret, Stop: Integer;
begin
  if (FEdit = 0) or not IsWindow(FEdit) then
  begin
    Exit;
  end;
  Insert := AItem.InsertText;
  if Insert = '' then
  begin
    Insert := AItem.Name;
  end;
  if FHistoryMode then
  begin
    SendMessage(FEdit, EM_SETSEL, 0, -1);
    Caret := Length(Insert);
  end
  else
  begin
    // Das ganze Wort an der Schreibmarke, wie TAtlasExpressionEdit.Apply.
    TAtlasExpressionEdit.Apply(FText, FCaret, FCaret - Max(FWordStart, 0), Insert, Text, Caret);
    Stop := Length(FText) - (Length(Text) - Caret);
    SendMessage(FEdit, EM_SETSEL, WPARAM(Max(FWordStart, 0)), LPARAM(Stop));
  end;
  // Mit Rückgängig-Eintrag (wParam = 1): Strg+Z im Feld nimmt es zurück.
  SendMessage(FEdit, EM_REPLACESEL, 1, LPARAM(PChar(Insert)));
  SendMessage(FEdit, EM_SETSEL, WPARAM(Caret), LPARAM(Caret));
  FText := WindowText(FEdit);
  FCaret := Caret;
  FHistoryMode := False;
end;

function TAtlasIdeDebugDialogCompletion.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
var
  Navigation: TAtlasNavigationKey;
begin
  Result := False;
  if (FEdit = 0) or (GetFocus <> FEdit) or not Enabled then
  begin
    Exit;
  end;
  if (AKey = VK_SPACE) and (AShift = [ssCtrl]) then
  begin
    Exit(True);
  end;
  if AShift <> [] then
  begin
    Exit;
  end;
  if FController.Visible and NavigationOf(AKey, Navigation) then
  begin
    Exit(True);
  end;
  // Verlauf (#538): Pfeil nach unten im leeren Feld; im Fenster „Auswerten“ zeigt das Fenster seinen eigenen.
  Result := (AKey = VK_DOWN) and not FOwnField and not FController.Active and (WindowText(FEdit) = '');
end;

procedure TAtlasIdeDebugDialogCompletion.HandleKey(AKey: Word);
var
  Navigation: TAtlasNavigationKey;
begin
  if AKey = VK_SPACE then
  begin
    FText := WindowText(FEdit);
    Selection(FEdit, FWordStart, FCaret);
    Query(False, False);
  end
  else if FController.Visible and NavigationOf(AKey, Navigation) then
  begin
    FController.HandleKey(Navigation);
  end
  else if AKey = VK_DOWN then
  begin
    FText := '';
    FCaret := 0;
    Query(True, False);
  end;
end;

end.
