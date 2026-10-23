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
    FHistory: TAtlasExpressionHistory;
    FHistoryLock: TCriticalSection;
    FHistoryLoaded: Boolean;
    FHistoryKept: Boolean;
    FProject: string;
    // Verfolgtes Feld.
    FEdit: HWND;
    FForm: TCustomForm;
    FDialog: TAtlasDebugDialog;
    FText: string;
    FCaret: Integer;
    FAllSelected: Boolean;
    FWordStart: Integer;
    FHistoryMode: Boolean;
    FLogged: TStringList;
    constructor Create(const ASession: TAtlasDialogSessionFunc; const ALog: TProc<string>;
      const AProvider: TAtlasDialogProviderFactory);
    procedure Tick(Sender: TObject);
    procedure Track(AFocus: HWND);
    procedure Untrack;
    procedure Remember(const AExpression: string);
    procedure LoadHistory;
    function HistoryItems: TArray<string>;
    procedure Query(AHistory, AAutomatic: Boolean);
    procedure Commit(const AItem: TAtlasCompletionItem);
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure HandleKey(AKey: Word; AShift: TShiftState);
    procedure Say(const AText: string);
    procedure LogDialog(AForm: TCustomForm);
    function Scope(out AFileName: string; out ALine: Integer): Boolean;
    function BreakpointScope(out AFileName: string; out ALine: Integer): Boolean;
    function Anchor: TRect;
    class function HistoryFile: string; static;
    class function CurrentProject: string; static;
    class function WindowText(AWindow: HWND): string; static;
    class procedure Selection(AWindow: HWND; out AStart, AStop: Integer); static;
    /// <summary>Beschriftung von AControl: Label mit FocusControl, sonst das nächste links bzw. darüber.</summary>
    class function LabelOf(AForm: TCustomForm; AControl: TWinControl): string; static;
    class function EditControl(AFocus: HWND): TWinControl; static;
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
      TAtlasIdeDebugDialogCompletion.FInstance.HandleKey(AKey, AShift);
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
  FHistory := TAtlasExpressionHistory.Create;
  FHistoryLock := TCriticalSection.Create;
  FLogged := TStringList.Create;
  FLogged.Sorted := True;
  FLogged.Duplicates := dupIgnore;
  FProviderRef := AProvider(
    function: TArray<string>
    begin
      // Im Hintergrund: nur unter der Sperre lesen. Destroy gibt die Quelle vor der Sperre frei; sie wartet dabei
      // auf ihre Threads.
      Result := HistoryItems;
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
  FController.Close;
  FController.Free;
  FPopup.Free;
  FProviderRef := nil;
  FKeys.Free;
  FLogged.Free;
  FHistoryLock.Free;
  FHistory.Free;
  inherited;
end;

class procedure TAtlasIdeDebugDialogCompletion.Start(const ASession: TAtlasDialogSessionFunc;
  const ALog: TProc<string>; const AProvider: TAtlasDialogProviderFactory);
begin
  if FInstance = nil then
    FInstance := TAtlasIdeDebugDialogCompletion.Create(ASession, ALog, AProvider);
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
    Exit;
  FInstance.FPopup.ManualListWidth := TAtlasIdeSettings.Current.ListWidth;
  FInstance.FPopup.PanelWidthSetting := TAtlasIdeSettings.Current.PanelWidth;
  FInstance.FPopup.PanelCollapsed := TAtlasIdeSettings.Current.PanelCollapsed;
  if not Enabled then
    FInstance.Untrack;
end;

procedure TAtlasIdeDebugDialogCompletion.Say(const AText: string);
begin
  if Assigned(FLog) then
    FLog(AText);
end;

class function TAtlasIdeDebugDialogCompletion.HistoryFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), HistoryFileName);
end;

class function TAtlasIdeDebugDialogCompletion.CurrentProject: string;
var
  Project: IOTAProject;
begin
  // Beim Debuggen das gestartete Projekt, sonst das aktive.
  Result := TAtlasIdeDebugSession.LaunchProject;
  if Result <> '' then
    Exit;
  Project := GetActiveProject;
  if Project <> nil then
    Result := Project.FileName;
end;

procedure TAtlasIdeDebugDialogCompletion.LoadHistory;
begin
  if FHistoryLoaded then
    Exit;
  FHistoryLoaded := True;
  // Gesperrt: leer beginnen und die Datei nicht überschreiben; TAtlasDataFile protokolliert ohne Pfad.
  FHistoryKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(HistoryFile, 'Verlauf der Debug-Ausdrücke',
    function(const AText: string): Boolean
    begin
      FHistoryLock.Acquire;
      try
        Result := FHistory.LoadFromText(AText);
      finally
        FHistoryLock.Release;
      end;
    end));
end;

function TAtlasIdeDebugDialogCompletion.HistoryItems: TArray<string>;
begin
  FHistoryLock.Acquire;
  try
    Result := FHistory.Items(FProject);
  finally
    FHistoryLock.Release;
  end;
end;

procedure TAtlasIdeDebugDialogCompletion.Remember(const AExpression: string);
var
  Changed: Boolean;
  Text: string;
begin
  LoadHistory;
  FHistoryLock.Acquire;
  try
    Changed := FHistory.Add(CurrentProject, AExpression);
    Text := FHistory.ToText;
  finally
    FHistoryLock.Release;
  end;
  if not Changed or FHistoryKept then
    Exit;
  try
    TAtlasDataFile.Write(HistoryFile, Text);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Verlauf der Debug-Ausdrücke', E);
  end;
end;

class function TAtlasIdeDebugDialogCompletion.WindowText(AWindow: HWND): string;
var
  Count: Integer;
begin
  Result := '';
  Count := SendMessage(AWindow, WM_GETTEXTLENGTH, 0, 0);
  if Count <= 0 then
    Exit;
  SetLength(Result, Count + 1);
  Count := SendMessage(AWindow, WM_GETTEXT, Count + 1, LPARAM(PChar(Result)));
  SetLength(Result, Max(Count, 0));
end;

class procedure TAtlasIdeDebugDialogCompletion.Selection(AWindow: HWND; out AStart, AStop: Integer);
var
  Start, Stop: DWORD;
begin
  Start := 0;
  Stop := 0;
  SendMessage(AWindow, EM_GETSEL, WPARAM(@Start), LPARAM(@Stop));
  AStart := Integer(Start);
  AStop := Integer(Stop);
end;

class function TAtlasIdeDebugDialogCompletion.EditControl(AFocus: HWND): TWinControl;
begin
  // Ein Kombinationsfeld hat das Eingabefeld als eigenes Fenster ohne VCL-Objekt.
  Result := FindControl(AFocus);
  if Result = nil then
    Result := FindControl(GetParent(AFocus));
  if (Result <> nil) and not ((Result is TCustomEdit) or (Result is TCustomComboBox)) then
    Result := nil;
end;

class function TAtlasIdeDebugDialogCompletion.LabelOf(AForm: TCustomForm; AControl: TWinControl): string;
var
  Index, Distance, Best: Integer;
  Component: TComponent;
  Candidate: TCustomLabel;
  Bounds, Own: TRect;
begin
  Result := '';
  for Index := 0 to AForm.ComponentCount - 1 do
  begin
    Component := AForm.Components[Index];
    if (Component is TCustomLabel) and (TLabelAccess(Component).FocusControl = AControl) then
      Exit(TLabelAccess(Component).Caption);
  end;
  // Ohne FocusControl: nächstes Label im selben Container links in derselben Höhe oder direkt darüber.
  if AControl.Parent = nil then
    Exit;
  Own := AControl.BoundsRect;
  Best := MaxInt;
  for Index := 0 to AControl.Parent.ControlCount - 1 do
  begin
    if not (AControl.Parent.Controls[Index] is TCustomLabel) then
      Continue;
    Candidate := TCustomLabel(AControl.Parent.Controls[Index]);
    if not Candidate.Visible then
      Continue;
    Bounds := Candidate.BoundsRect;
    if (Bounds.Right <= Own.Left + 4) and (Bounds.Bottom > Own.Top) and (Bounds.Top < Own.Bottom) then
      Distance := Own.Left - Bounds.Right
    else if (Bounds.Bottom <= Own.Top + 4) and (Bounds.Left < Own.Right) and (Bounds.Right > Own.Left) then
      Distance := Own.Top - Bounds.Bottom
    else
      Continue;
    if Distance < Best then
    begin
      Best := Distance;
      Result := TLabelAccess(Candidate).Caption;
    end;
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
    Exit;
  FLogged.Add(Key);
  Labels := '';
  for Index := 0 to AForm.ComponentCount - 1 do
    if AForm.Components[Index] is TCustomLabel then
      Labels := Labels + ' [' + TLabelAccess(AForm.Components[Index]).Caption + ']';
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
    Exit;
  Form := GetParentForm(Control);
  if Form = nil then
    Exit;
  Dialog := TAtlasDebugDialogs.DialogOf(Form.ClassName, Form.Caption);
  if Dialog = TAtlasDebugDialog.None then
    Exit;
  LogDialog(Form);
  Field := TAtlasDebugDialogs.FieldOf(Dialog, LabelOf(Form, Control));
  if not TAtlasDebugDialogs.Completes(Field) then
    Exit;
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
    Exit;
  FController.Close;
  // Mit einem Ausdruck verlassen: in den Verlauf.
  if IsWindow(FEdit) then
    Remember(WindowText(FEdit))
  else
    Remember(FText);
  FEdit := 0;
  FForm := nil;
  FDialog := TAtlasDebugDialog.None;
  FText := '';
end;

procedure TAtlasIdeDebugDialogCompletion.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    var
      Focus: HWND;
      Text, Prefix: string;
      Start, Stop, WordStart: Integer;
      AllSelected, Opens: Boolean;
    begin
      if not Enabled then
      begin
        Untrack;
        Exit;
      end;
      Focus := GetFocus;
      if Focus <> FEdit then
      begin
        Untrack;
        if Focus <> 0 then
          Track(Focus);
      end;
      if (FEdit = 0) or not IsWindow(FEdit) then
        Exit;
      Text := WindowText(FEdit);
      Selection(FEdit, Start, Stop);
      AllSelected := (Text <> '') and (Start = 0) and (Stop = Length(Text));
      // Ausgewertet: Die IDE markiert danach das ganze Feld.
      if (Text = FText) and AllSelected and not FAllSelected then
        Remember(Text);
      FAllSelected := AllSelected;
      if (Text = FText) and (Stop = FCaret) then
        Exit;
      Opens := TAtlasExpressionEdit.OpensAfter(FText, Text, Stop);
      FText := Text;
      FCaret := Stop;
      Prefix := TAtlasExpressionEdit.PrefixAt(Text, Stop);
      WordStart := Stop - Length(Prefix);
      if FController.Active then
      begin
        if FHistoryMode or (WordStart <> FWordStart) then
          FController.Close
        else if FController.NeedsQuery(Prefix) then
          Query(False, True)
        else
          FController.UpdatePrefix(Prefix);
      end;
      if not FController.Active and Opens then
        Query(False, True);
    end);
end;

function TAtlasIdeDebugDialogCompletion.BreakpointScope(out AFileName: string; out ALine: Integer): Boolean;
var
  Index: Integer;
  Component: TComponent;
  Control: TWinControl;
  FileText, LineText: string;
begin
  FileText := '';
  LineText := '';
  for Index := 0 to FForm.ComponentCount - 1 do
  begin
    Component := FForm.Components[Index];
    if not ((Component is TCustomEdit) or (Component is TCustomComboBox)) then
      Continue;
    Control := TWinControl(Component);
    if not Control.HandleAllocated then
      Continue;
    case TAtlasDebugDialogs.FieldOf(FDialog, LabelOf(FForm, Control)) of
      TAtlasDebugField.FileName: FileText := Trim(WindowText(Control.Handle));
      TAtlasDebugField.LineNumber: LineText := WindowText(Control.Handle);
    end;
  end;
  ALine := TAtlasDebugDialogs.ScopeLine(LineText);
  AFileName := '';
  if FileText <> '' then
    AFileName := TAtlasIdeDebugSources.Resolve(FileText);
  Result := (AFileName <> '') and (ALine >= 0);
end;

function TAtlasIdeDebugDialogCompletion.Scope(out AFileName: string; out ALine: Integer): Boolean;
var
  Frames: TAtlasDebugFrames;
  View: IOTAEditView;
begin
  if (FDialog = TAtlasDebugDialog.Breakpoint) and BreakpointScope(AFileName, ALine) then
    Exit(True);
  if (TAtlasIdeDebugSession.StoppedThread <> nil) and
    (TAtlasIdeDebugSession.ReadStack(TAtlasIdeDebugSession.StoppedThread, 1, Frames) = TAtlasDebugStackRead.Ready) and
    (Length(Frames) > 0) and Frames[0].HasSource then
  begin
    TAtlasIdeDebugSources.MarkFrames(Frames);
    AFileName := Frames[0].FileName;
    ALine := Frames[0].Line - 1;
    Exit(True);
  end;
  // Weder Haltepunkt noch Halt: die Cursorzeile im Editor.
  View := TAtlasEditorBuffer.ActiveView;
  Result := (View <> nil) and (View.Buffer <> nil);
  if not Result then
    Exit;
  AFileName := View.Buffer.FileName;
  ALine := View.CursorPos.Line - 1;
end;

function TAtlasIdeDebugDialogCompletion.Anchor: TRect;
var
  Caret, Origin: TPoint;
  Window: TRect;
  Position: LRESULT;
begin
  GetWindowRect(FEdit, Window);
  Result := Window;
  // Linke Kante des Worts: EM_POSFROMCHAR gilt nur für vorhandene Zeichen, am Ende die Schreibmarke.
  Position := -1;
  if (FWordStart >= 0) and (FWordStart < Length(FText)) then
    Position := SendMessage(FEdit, EM_POSFROMCHAR, WPARAM(FWordStart), 0);
  if Position <> -1 then
    Caret := Point(SmallInt(LoWord(DWORD(Position))), SmallInt(HiWord(DWORD(Position))))
  else if not GetCaretPos(Caret) then
    Caret := Point(0, 0);
  Origin := Point(0, 0);
  ClientToScreen(FEdit, Origin);
  Result.Left := Origin.X + Caret.X;
  Result.Right := Result.Left + 1;
end;

procedure TAtlasIdeDebugDialogCompletion.Query(AHistory, AAutomatic: Boolean);
var
  Context: TAtlasContext;
  Session: TLspSession;
  Buffer: IOTAEditBuffer;
  FileName, Source: string;
  Line, WordStart: Integer;
begin
  Context := Default(TAtlasContext);
  Context.Automatic := AAutomatic;
  Context.Text := FText;
  Context.Character := FCaret;
  Context.Prefix := TAtlasExpressionEdit.PrefixAt(FText, FCaret);
  FHistoryLock.Acquire;
  try
    FProject := CurrentProject;
  finally
    FHistoryLock.Release;
  end;
  if AHistory then
  begin
    LoadHistory;
    if Length(HistoryItems) = 0 then
      Exit;
    Context.Trigger := TAtlasTriggers.History;
    Context.Prefix := '';
  end
  else
  begin
    Session := nil;
    if Assigned(FSession) then
      Session := FSession();
    if (Session = nil) or not Scope(FileName, Line) then
      Exit;
    // Im Hauptthread abgleichen: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
    Buffer := TAtlasIdeFiles.BufferOf(FileName);
    if Buffer <> nil then
      Source := TAtlasEditorBuffer.Text(Buffer)
    else
      try
        Source := TAtlasTextFile.LoadText(FileName);
      except
        on Exception do
          Exit;
      end;
    Session.Sync(FileName, Source);
    Context.FileName := FileName;
    Context.Line := Line;
    // Nach "." Mitgliederliste (#497): Zeichen vor dem Wortanfang, 1-basiert an der Stelle des Wortanfangs.
    WordStart := FCaret - Length(Context.Prefix);
    if (WordStart > 0) and (WordStart <= Length(FText)) and (FText[WordStart] = '.') then
      Context.Trigger := '.';
  end;
  FHistoryMode := AHistory;
  FWordStart := FCaret - Length(Context.Prefix);
  FPopup.Anchor := Anchor;
  // Ohne Ausdruck, Datei und Zeile: Das Diagnoselog soll weitergegeben werden können (#647).
  Say(Format('Debug-Dialog: Vervollständigung (Verlauf %s, Präfix %d Zeichen)',
    [BoolToStr(AHistory, True), Length(Context.Prefix)]));
  if FController.Active and not AHistory then
    FController.Requery(Context)
  else
    FController.Start(Context);
end;

procedure TAtlasIdeDebugDialogCompletion.Commit(const AItem: TAtlasCompletionItem);
var
  Insert, Text: string;
  Caret, Stop: Integer;
begin
  if (FEdit = 0) or not IsWindow(FEdit) then
    Exit;
  Insert := AItem.InsertText;
  if Insert = '' then
    Insert := AItem.Name;
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
    Exit;
  if (AKey = VK_SPACE) and (AShift = [ssCtrl]) then
    Exit(True);
  if AShift <> [] then
    Exit;
  if FController.Visible and NavigationOf(AKey, Navigation) then
    Exit(True);
  // Verlauf (#538): Pfeil nach unten im leeren Feld.
  Result := (AKey = VK_DOWN) and not FController.Active and (WindowText(FEdit) = '');
end;

procedure TAtlasIdeDebugDialogCompletion.HandleKey(AKey: Word; AShift: TShiftState);
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
    FController.HandleKey(Navigation)
  else if AKey = VK_DOWN then
  begin
    FText := '';
    FCaret := 0;
    Query(True, False);
  end;
end;

end.
