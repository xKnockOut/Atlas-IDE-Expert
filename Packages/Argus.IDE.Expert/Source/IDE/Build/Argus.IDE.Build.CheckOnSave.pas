unit Argus.IDE.Build.CheckOnSave;

// Compilerprüfung im Hintergrund nach dem Speichern (#548). Speichern einer
// Unit des aktiven Projekts (erkannt über den Reloader, #536) merkt eine
// Syntaxprüfung vor (TArgusCheckOnSave); fällig startet sie über
// IOTAProjectBuilder.BuildProject(cmOTACheck). Die Meldungen liest danach der
// Reiter-Leser aus #528. Während der eigenen Prüfung gelten die
// Compile-Ereignisse als Hintergrund (#527); Builds des Benutzers sperren die
// Prüfung. Der Compiler läuft im Hauptthread; die Prüfung meldet sich beim
// Einfrier-Wächter als Argus-Aktion an (#501).
// Vorab in RAD Studio 13 geprüft: Die Syntaxprüfung schreibt keine .exe und
// keine .dcu (nur die .res des Ressourcencompilers), Mini-Projekt ~0,9 s.
// Schlägt sie fehl, wartet der Fortschrittsdialog der IDE auf OK; nur während
// der eigenen Prüfung drückt Argus dort OK (nie Abbrechen, nie fremde Dialoge).
// Strg+Alt+F9 prüft von Hand, auch wenn die Automatik abgeschaltet ist.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  ToolsAPI,
  Argus.Core.Build.Events,
  Argus.Core.Build.CheckOnSave;

type
  TArgusIdeCheckOnSave = class
  private type
    TWatcher = class(TArgusCompileParticipant)
    private
      FOwner: TArgusIdeCheckOnSave;
    public
      procedure GroupStarted(AKind: TArgusCompileKind); override;
      procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); override;
      procedure ProjectStarted(const AProject: TArgusCompileProject); override;
      procedure ProjectFinished(const AProject: TArgusCompileProject; ASucceeded: Boolean; ADurationMs: Int64); override;
    end;

    TBinding = class(TNotifierObject, IOTAKeyboardBinding)
    private
      FOwner: TArgusIdeCheckOnSave;
      procedure Check(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
    public
      function GetBindingType: TBindingType;
      function GetDisplayName: string;
      function GetName: string;
      procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
    end;
  private
    FCore: TArgusCheckOnSave;
    FEvents: TArgusCompileEvents;
    FWatcher: TWatcher;
    FTimer: TTimer;
    FChecking: Boolean;
    FManual: Boolean;
    FReport: TProc<string>;
    FBinding: TBinding;
    FBindingIndex: Integer;
    procedure Tick(Sender: TObject);
    procedure Run(const AProject: string; AManual: Boolean);
    class function ActiveProject: IOTAProject; static;
    class function Debugging: Boolean; static;
    class procedure PressProgressOk; static;
    class procedure AddMessage(const AText: string); static;
  public
    /// <summary>AEvents gehört dem Aufrufer und muss länger leben; der Wächter wird dort angemeldet.</summary>
    constructor Create(AEvents: TArgusCompileEvents; const AReport: TProc<string>);
    destructor Destroy; override;
    /// <summary>Eine Datei wurde gespeichert.</summary>
    procedure Saved(const AFileName: string);
    /// <summary>Aktives Projekt jetzt prüfen.</summary>
    procedure CheckNow;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Menus,
  System.StrUtils,
  Argus.Core.Settings.Plugin,
  Argus.UI.Strings,
  Argus.IDE.Settings.Store,
  Argus.Core.Diagnostics.Hangs;

function NowMs: Int64;
begin
  Result := GetTickCount64;
end;

{ TArgusIdeCheckOnSave.TWatcher }

procedure TArgusIdeCheckOnSave.TWatcher.GroupStarted(AKind: TArgusCompileKind);
begin
  if (FOwner <> nil) and not FOwner.FChecking then
    FOwner.FCore.BuildStarted;
end;

procedure TArgusIdeCheckOnSave.TWatcher.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
  if (FOwner <> nil) and not FOwner.FChecking then
    FOwner.FCore.BuildFinished;
end;

procedure TArgusIdeCheckOnSave.TWatcher.ProjectStarted(const AProject: TArgusCompileProject);
begin
  if (FOwner <> nil) and not AProject.Background then
    FOwner.FCore.BuildStarted;
end;

procedure TArgusIdeCheckOnSave.TWatcher.ProjectFinished(const AProject: TArgusCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
begin
  if (FOwner <> nil) and not AProject.Background then
    FOwner.FCore.BuildFinished;
end;

{ TArgusIdeCheckOnSave.TBinding }

function TArgusIdeCheckOnSave.TBinding.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TArgusIdeCheckOnSave.TBinding.GetDisplayName: string;
begin
  Result := 'Argus-Compilerprüfung';
end;

function TArgusIdeCheckOnSave.TBinding.GetName: string;
begin
  Result := 'Argus.CheckNow';
end;

procedure TArgusIdeCheckOnSave.TBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
begin
  BindingServices.AddKeyBinding([ShortCut(VK_F9, [ssCtrl, ssAlt])], Check, nil);
end;

procedure TArgusIdeCheckOnSave.TBinding.Check(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  // Nicht im Tastaturhandler compilieren: der Timer holt es ab.
  if FOwner <> nil then
    FOwner.FManual := True;
end;

{ TArgusIdeCheckOnSave }

constructor TArgusIdeCheckOnSave.Create(AEvents: TArgusCompileEvents; const AReport: TProc<string>);
var
  Keyboard: IOTAKeyboardServices;
begin
  inherited Create;
  FEvents := AEvents;
  FReport := AReport;
  FCore := TArgusCheckOnSave.Create;
  FWatcher := TWatcher.Create;
  FWatcher.FOwner := Self;
  // Der Dienst übernimmt den Wächter; Destroy trennt ihn nur von uns.
  FEvents.Add(FWatcher);
  FBindingIndex := -1;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
  begin
    FBinding := TBinding.Create;
    FBinding.FOwner := Self;
    FBindingIndex := Keyboard.AddKeyboardBinding(FBinding);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TArgusIdeCheckOnSave.Destroy;
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

class function TArgusIdeCheckOnSave.ActiveProject: IOTAProject;
var
  Services: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Result := Services.GetActiveProject;
end;

class function TArgusIdeCheckOnSave.Debugging: Boolean;
var
  Debugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) and (Debugger.ProcessCount > 0);
end;

class procedure TArgusIdeCheckOnSave.AddMessage(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Group := Messages.GetGroup('Argus');
  if Group = nil then
    Group := Messages.AddMessageGroup('Argus');
  Messages.AddTitleMessage(AText, Group);
end;

class procedure TArgusIdeCheckOnSave.PressProgressOk;
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

procedure TArgusIdeCheckOnSave.Saved(const AFileName: string);
var
  Project: IOTAProject;
  Index: Integer;
  Belongs: Boolean;
begin
  if FChecking or not TArgusIdeSettings.Current.CheckOnSave then
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
end;

procedure TArgusIdeCheckOnSave.Tick(Sender: TObject);
var
  Settings: TArgusPluginSettings;
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
    Settings := TArgusIdeSettings.Current;
    FCore.DelayMs := Settings.CheckOnSaveDelayMs;
    FCore.MaxMs := Settings.CheckOnSaveMaxMs;
    if Settings.CheckOnSave and FCore.Due(NowMs, Debugging) then
      Run(FCore.Take, False);
  except
    // Keine Exception an die IDE (#493).
  end;
end;

procedure TArgusIdeCheckOnSave.CheckNow;
var
  Project: IOTAProject;
begin
  Project := ActiveProject;
  if (Project <> nil) and not FChecking and not FCore.BuildRunning and not Debugging then
    Run(Project.FileName, True);
end;

procedure TArgusIdeCheckOnSave.Run(const AProject: string; AManual: Boolean);
var
  Services: IOTAModuleServices;
  Project: IOTAProject;
  Started, Duration: Int64;
  Activity: IInterface;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) or
    not Supports(Services.FindModule(AProject), IOTAProject, Project) or (Project.ProjectBuilder = nil) then
    Exit;
  Activity := TArgusActivity.Scope('Compilerprüfung nach dem Speichern');
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
    AddMessage(TArgusStrings.Fmt(TArgusTextId.CheckOnSaveDisabled, [ExtractFileName(AProject), Duration,
      FCore.MaxMs]));
end;

end.