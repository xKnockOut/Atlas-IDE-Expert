unit Atlas.IDE.Build.CheckOnSave;

// Compilerprüfung im Hintergrund nach dem Speichern (#548). Speichern einer
// Unit des aktiven Projekts (erkannt über den Reloader, #536) merkt eine
// Syntaxprüfung vor (TAtlasCheckOnSave); fällig startet sie über
// IOTAProjectBuilder.BuildProject(cmOTACheck). Die Meldungen liest danach der
// Reiter-Leser aus #528. Während der eigenen Prüfung gelten die
// Compile-Ereignisse als Hintergrund (#527); Builds des Benutzers sperren die
// Prüfung. Der Compiler läuft im Hauptthread; die Prüfung meldet sich beim
// Einfrier-Wächter als Atlas-Aktion an (#501).
// Vorab in RAD Studio 13 geprüft: Die Syntaxprüfung schreibt keine .exe und
// keine .dcu (nur die .res des Ressourcencompilers), Mini-Projekt ~0,9 s.
// Schlägt sie fehl, wartet der Fortschrittsdialog der IDE auf OK; nur während
// der eigenen Prüfung drückt Atlas dort OK (nie Abbrechen, nie fremde Dialoge).
// Strg+Alt+F9 prüft von Hand, auch wenn die Automatik abgeschaltet ist.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.CheckOnSave;

type
  TAtlasIdeCheckOnSave = class
  private type
    TWatcher = class(TAtlasCompileParticipant)
    private
      FOwner: TAtlasIdeCheckOnSave;
    public
      procedure GroupStarted(AKind: TAtlasCompileKind); override;
      procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); override;
      procedure ProjectStarted(const AProject: TAtlasCompileProject); override;
      procedure ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean; ADurationMs: Int64); override;
    end;

    TBinding = class(TNotifierObject, IOTAKeyboardBinding)
    private
      FOwner: TAtlasIdeCheckOnSave;
      procedure Check(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
    public
      function GetBindingType: TBindingType;
      function GetDisplayName: string;
      function GetName: string;
      procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
    end;
  private
    FCore: TAtlasCheckOnSave;
    FEvents: TAtlasCompileEvents;
    FWatcher: TWatcher;
    FTimer: TTimer;
    FChecking: Boolean;
    FManual: Boolean;
    FReport: TProc<string>;
    FBinding: TBinding;
    // Hält das Binding am Leben: Abmelden gibt die Referenz der IDE frei, Rebind meldet es neu an.
    FBindingRef: IOTAKeyboardBinding;
    FBindingIndex: Integer;
    FKey: Word;
    procedure Tick(Sender: TObject);
    procedure Run(const AProject: string; AManual: Boolean);
    class function ActiveProject: IOTAProject; static;
    class function Debugging: Boolean; static;
    class procedure AddMessage(const AText: string); static;
  public
    /// <summary>AEvents gehört dem Aufrufer und muss länger leben; der Wächter wird dort angemeldet.</summary>
    constructor Create(AEvents: TAtlasCompileEvents; const AReport: TProc<string>);
    destructor Destroy; override;
    /// <summary>Tastenkürzel nach den Einstellungen (neu) belegen; bei Konflikt ohne Vorrang keins (#494).</summary>
    procedure Rebind;
    /// <summary>Eine Datei wurde gespeichert.</summary>
    procedure Saved(const AFileName: string);
    /// <summary>Aktives Projekt jetzt prüfen.</summary>
    procedure CheckNow;
    /// <summary>Drückt OK im Fortschrittsdialog des Compilers (nur dort, nie Abbrechen). Nur während eines eigenen
    /// Laufs aufrufen (auch vom Build-Läufer, #261).</summary>
    class procedure PressProgressOk; static;
  end;

implementation

uses
  Atlas.IDE.Foundation.Keys,
  Atlas.Core.Diagnostics.Guard,
  Winapi.Windows,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Menus,
  System.StrUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources;

function NowMs: Int64;
begin
  Result := GetTickCount64;
end;

{ TAtlasIdeCheckOnSave.TWatcher }

procedure TAtlasIdeCheckOnSave.TWatcher.GroupStarted(AKind: TAtlasCompileKind);
begin
  if (FOwner <> nil) and not FOwner.FChecking then
    FOwner.FCore.BuildStarted;
end;

procedure TAtlasIdeCheckOnSave.TWatcher.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
  if (FOwner <> nil) and not FOwner.FChecking then
    FOwner.FCore.BuildFinished;
end;

procedure TAtlasIdeCheckOnSave.TWatcher.ProjectStarted(const AProject: TAtlasCompileProject);
begin
  if (FOwner <> nil) and not AProject.Background then
    FOwner.FCore.BuildStarted;
end;

procedure TAtlasIdeCheckOnSave.TWatcher.ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
begin
  if (FOwner <> nil) and not AProject.Background then
    FOwner.FCore.BuildFinished;
end;

{ TAtlasIdeCheckOnSave.TBinding }

function TAtlasIdeCheckOnSave.TBinding.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TAtlasIdeCheckOnSave.TBinding.GetDisplayName: string;
begin
  Result := 'Atlas-Compilerprüfung';
end;

function TAtlasIdeCheckOnSave.TBinding.GetName: string;
begin
  Result := 'Atlas.CheckNow';
end;

procedure TAtlasIdeCheckOnSave.TBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
begin
  if (FOwner <> nil) and (FOwner.FKey <> 0) then
    BindingServices.AddKeyBinding([FOwner.FKey], Check, nil);
end;

procedure TAtlasIdeCheckOnSave.TBinding.Check(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  // Nicht im Tastaturhandler compilieren: der Timer holt es ab.
  if FOwner <> nil then
    FOwner.FManual := True;
end;

{ TAtlasIdeCheckOnSave }

constructor TAtlasIdeCheckOnSave.Create(AEvents: TAtlasCompileEvents; const AReport: TProc<string>);
var
  Keyboard: IOTAKeyboardServices;
begin
  inherited Create;
  FEvents := AEvents;
  FReport := AReport;
  FCore := TAtlasCheckOnSave.Create;
  FWatcher := TWatcher.Create;
  FWatcher.FOwner := Self;
  // Der Dienst übernimmt den Wächter; Destroy trennt ihn nur von uns.
  FEvents.Add(FWatcher);
  FBindingIndex := -1;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
  begin
    FBinding := TBinding.Create;
    FBindingRef := FBinding;
    FBinding.FOwner := Self;
    Rebind;
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeCheckOnSave.Rebind;
var
  Key: Word;
begin
  if FBinding = nil then
    Exit;
  Key := Word(TAtlasIdeSettings.Current.CheckKey);
  if not TAtlasIdeKeys.Decide(Key, TAtlasIdeSettings.Current.CheckKeyPriority,
    TAtlasStrings.Text(TAtlasTextId.SettingsCheckKey)) then
    Key := 0;
  if (Key = FKey) and ((FBindingIndex >= 0) = (Key <> 0)) then
    Exit;
  FKey := Key;
  if FKey = 0 then
    TAtlasIdeKeys.Unbind(FBindingIndex)
  else
    TAtlasIdeKeys.Bind(FBinding, FBindingIndex);
end;

destructor TAtlasIdeCheckOnSave.Destroy;
var
  Keyboard: IOTAKeyboardServices;
begin
  FTimer.Enabled := False;
  FTimer.Free;
  if FBinding <> nil then
    FBinding.FOwner := nil;
  if (FBindingIndex >= 0) and Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
    Keyboard.RemoveKeyboardBinding(FBindingIndex);
  FWatcher.FOwner := nil;
  FCore.Free;
  inherited;
end;

class function TAtlasIdeCheckOnSave.ActiveProject: IOTAProject;
var
  Services: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Result := Services.GetActiveProject;
end;

class function TAtlasIdeCheckOnSave.Debugging: Boolean;
var
  Debugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) and (Debugger.ProcessCount > 0);
end;

class procedure TAtlasIdeCheckOnSave.AddMessage(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Group := Messages.GetGroup('Atlas');
  if Group = nil then
    Group := Messages.AddMessageGroup('Atlas');
  Messages.AddTitleMessage(AText, Group);
end;

class procedure TAtlasIdeCheckOnSave.PressProgressOk;
var
  Index, Child: Integer;
  Form: TForm;
  Button: TButton;
begin
  // Nur der Fortschrittsdialog des Compilers, nur sein OK (nach dem Ende); Abbrechen nie.
  for Index := 0 to Screen.FormCount - 1 do
  begin
    Form := Screen.Forms[Index];
    if not SameText(Form.ClassName, 'TProgressForm') or not Form.Visible then
      Continue;
    for Child := 0 to Form.ComponentCount - 1 do
      if (Form.Components[Child] is TButton) then
      begin
        Button := TButton(Form.Components[Child]);
        if Button.Visible and Button.Enabled and (Button.ModalResult = mrOk) then
        begin
          Button.Click;
          Exit;
        end;
      end;
  end;
end;

procedure TAtlasIdeCheckOnSave.Saved(const AFileName: string);
var
  Project: IOTAProject;
  Index: Integer;
  Belongs: Boolean;
begin
  try
    if FChecking or not TAtlasIdeSettings.Current.CheckOnSave then
      Exit;
    Project := ActiveProject;
    if Project = nil then
      Exit;
    Belongs := False;
    for Index := 0 to Project.GetModuleCount - 1 do
      if SameText(Project.GetModule(Index).FileName, AFileName) then
        Belongs := True;
    if SameText(ChangeFileExt(Project.FileName, '.dpr'), AFileName) or
      SameText(ChangeFileExt(Project.FileName, '.dpk'), AFileName) then
      Belongs := True;
    if Belongs then
      FCore.Saved(Project.FileName, NowMs);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.CheckOnSave, E);
  end;
end;

procedure TAtlasIdeCheckOnSave.Tick(Sender: TObject);
var
  Settings: TAtlasPluginSettings;
begin
  try
    // Läuft auch in der modalen Schleife des Compilers weiter.
    if FChecking then
    begin
      PressProgressOk;
      Exit;
    end;
    if FManual then
    begin
      FManual := False;
      CheckNow;
      Exit;
    end;
    Settings := TAtlasIdeSettings.Current;
    FCore.DelayMs := Settings.CheckOnSaveDelayMs;
    FCore.MaxMs := Settings.CheckOnSaveMaxMs;
    if Settings.CheckOnSave and FCore.Due(NowMs, Debugging) then
      Run(FCore.Take, False);
  except
    // Keine Exception an die IDE (#493).
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.CheckOnSave, E);
  end;
end;

procedure TAtlasIdeCheckOnSave.CheckNow;
var
  Project: IOTAProject;
begin
  Project := ActiveProject;
  if (Project <> nil) and not FChecking and not FCore.BuildRunning and not Debugging then
    Run(Project.FileName, True);
end;

procedure TAtlasIdeCheckOnSave.Run(const AProject: string; AManual: Boolean);
var
  Services: IOTAModuleServices;
  Project: IOTAProject;
  Started, Duration: Int64;
  Activity: IInterface;
  Text: string;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) or
    not Supports(Services.FindModule(AProject), IOTAProject, Project) or (Project.ProjectBuilder = nil) then
    Exit;
  Activity := TAtlasActivity.Scope('Compilerprüfung nach dem Speichern');
  FChecking := True;
  FEvents.Background := True;
  Started := NowMs;
  try
    Project.ProjectBuilder.BuildProject(cmOTACheck, False, True);
  finally
    FEvents.Background := False;
    FChecking := False;
  end;
  Duration := NowMs - Started;
  if Assigned(FReport) then
    FReport(Format('Compilerprüfung %s: %s, %d ms', [IfThen(AManual, 'von Hand', 'nach dem Speichern'),
      ExtractFileName(AProject), Duration]));
  if not AManual and FCore.CheckFinished(AProject, Duration) then
  begin
    Text := TAtlasStrings.Fmt(TAtlasTextId.CheckOnSaveDisabled, [ExtractFileName(AProject), Duration, FCore.MaxMs]);
    // Benachrichtigungszentrale (#601, Quelle check): Meldungsfenster nur bei „einblenden“.
    if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Check, TAtlasNotificationSeverity.Warning,
      TAtlasStrings.Text(TAtlasTextId.NotificationsCheckDisabled), Text) = TAtlasNotificationMode.Show then
      AddMessage(Text);
  end;
end;

end.