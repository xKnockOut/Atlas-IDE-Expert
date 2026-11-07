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
      procedure ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean; ADurationMs: Int64);
        override;
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
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TCheckOnSaveText = (AtlasCompilerCheck);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TCheckOnSaveText] of string = (
    ('Atlas-Compilerprüfung'),
    ('Atlas compiler check'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TCheckOnSaveText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

function NowMs: Int64;
begin
  Result := GetTickCount64;
end;

{ TAtlasIdeCheckOnSave.TWatcher }

procedure TAtlasIdeCheckOnSave.TWatcher.GroupStarted(AKind: TAtlasCompileKind);
begin
  if (FOwner <> nil) and not FOwner.FChecking then
  begin
    FOwner.FCore.BuildStarted;
  end;
end;

procedure TAtlasIdeCheckOnSave.TWatcher.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
  if (FOwner <> nil) and not FOwner.FChecking then
  begin
    FOwner.FCore.BuildFinished;
  end;
end;

procedure TAtlasIdeCheckOnSave.TWatcher.ProjectStarted(const AProject: TAtlasCompileProject);
begin
  if (FOwner <> nil) and not AProject.Background then
  begin
    FOwner.FCore.BuildStarted;
  end;
end;

procedure TAtlasIdeCheckOnSave.TWatcher.ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
begin
  if (FOwner <> nil) and not AProject.Background then
  begin
    FOwner.FCore.BuildFinished;
  end;
end;

{ TAtlasIdeCheckOnSave.TBinding }

function TAtlasIdeCheckOnSave.TBinding.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TAtlasIdeCheckOnSave.TBinding.GetDisplayName: string;
begin
  Result := UiText(TCheckOnSaveText.AtlasCompilerCheck);
end;

function TAtlasIdeCheckOnSave.TBinding.GetName: string;
begin
  Result := 'Atlas.CheckNow';
end;

procedure TAtlasIdeCheckOnSave.TBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
begin
  if (FOwner <> nil) and (FOwner.FKey <> 0) then
  begin
    BindingServices.AddKeyBinding([FOwner.FKey], Check, nil);
  end;
end;

procedure TAtlasIdeCheckOnSave.TBinding.Check(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  // Nicht im Tastaturhandler compilieren: der Timer holt es ab.
  if FOwner <> nil then
  begin
    FOwner.FManual := True;
  end;
end;

{ TAtlasIdeCheckOnSave }

constructor TAtlasIdeCheckOnSave.Create(AEvents: TAtlasCompileEvents; const AReport: TProc<string>);
var
  mKeyboard: IOTAKeyboardServices;
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
  if Supports(BorlandIDEServices, IOTAKeyboardServices, mKeyboard) then
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
  mKey: Word;
begin
  if FBinding = nil then
  begin
    Exit;
  end;
  mKey := Word(TAtlasIdeSettings.Current.CheckKey);
  if not TAtlasIdeKeys.Decide(mKey, TAtlasIdeSettings.Current.CheckKeyPriority,
    TAtlasStrings.Text(TAtlasTextId.SettingsCheckKey)) then
  begin
    mKey := 0;
  end;
  if (mKey = FKey) and ((FBindingIndex >= 0) = (mKey <> 0)) then
  begin
    Exit;
  end;
  FKey := mKey;
  if FKey = 0 then
  begin
    TAtlasIdeKeys.Unbind(FBindingIndex);
  end
  else
  begin
    TAtlasIdeKeys.Bind(FBinding, FBindingIndex);
  end;
end;

destructor TAtlasIdeCheckOnSave.Destroy;
var
  mKeyboard: IOTAKeyboardServices;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
    FTimer.Free;
  end;
  if FBinding <> nil then
  begin
    FBinding.FOwner := nil;
  end;
  if (FBindingIndex >= 0) and Supports(BorlandIDEServices, IOTAKeyboardServices, mKeyboard) then
  begin
    mKeyboard.RemoveKeyboardBinding(FBindingIndex);
  end;
  FWatcher.FOwner := nil;
  FCore.Free;
  inherited;
end;

class function TAtlasIdeCheckOnSave.ActiveProject: IOTAProject;
var
  mServices: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Result := mServices.GetActiveProject;
  end;
end;

class function TAtlasIdeCheckOnSave.Debugging: Boolean;
var
  mDebugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) and (mDebugger.ProcessCount > 0);
end;

class procedure TAtlasIdeCheckOnSave.AddMessage(const AText: string);
var
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mGroup := mMessages.GetGroup('Atlas');
  if mGroup = nil then
  begin
    mGroup := mMessages.AddMessageGroup('Atlas');
  end;
  mMessages.AddTitleMessage(AText, mGroup);
end;

class procedure TAtlasIdeCheckOnSave.PressProgressOk;
var
  mIndex, mChild: Integer;
  mForm: TForm;
  mButton: TButton;
begin
  // Nur der Fortschrittsdialog des Compilers, nur sein OK (nach dem Ende); Abbrechen nie.
  for mIndex := 0 to Screen.FormCount - 1 do
  begin
    mForm := Screen.Forms[mIndex];
    if not SameText(mForm.ClassName, 'TProgressForm') or not mForm.Visible then
    begin
      Continue;
    end;
    for mChild := 0 to mForm.ComponentCount - 1 do
    begin
      if (mForm.Components[mChild] is TButton) then
      begin
        mButton := TButton(mForm.Components[mChild]);
        if mButton.Visible and mButton.Enabled and (mButton.ModalResult = mrOk) then
        begin
          mButton.Click;
          Exit;
        end;
      end;
    end;
  end;
end;

procedure TAtlasIdeCheckOnSave.Saved(const AFileName: string);
var
  mProject: IOTAProject;
  mIndex: Integer;
  mBelongs: Boolean;
begin
  try
    if FChecking or not TAtlasIdeSettings.Current.CheckOnSave then
    begin
      Exit;
    end;
    mProject := ActiveProject;
    if mProject = nil then
    begin
      Exit;
    end;
    mBelongs := False;
    for mIndex := 0 to mProject.GetModuleCount - 1 do
    begin
      if SameText(mProject.GetModule(mIndex).FileName, AFileName) then
      begin
        mBelongs := True;
      end;
    end;
    if SameText(ChangeFileExt(mProject.FileName, '.dpr'), AFileName) or
      SameText(ChangeFileExt(mProject.FileName, '.dpk'), AFileName) then
    begin
      mBelongs := True;
    end;
    if mBelongs then
    begin
      FCore.Saved(mProject.FileName, NowMs);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.CheckOnSave, E);
  end;
end;

procedure TAtlasIdeCheckOnSave.Tick(Sender: TObject);
var
  mSettings: TAtlasPluginSettings;
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
    mSettings := TAtlasIdeSettings.Current;
    FCore.DelayMs := mSettings.CheckOnSaveDelayMs;
    FCore.MaxMs := mSettings.CheckOnSaveMaxMs;
    if mSettings.CheckOnSave and FCore.Due(NowMs, Debugging) then
    begin
      Run(FCore.Take, False);
    end;
  except
    // Keine Exception an die IDE (#493).
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.CheckOnSave, E);
  end;
end;

procedure TAtlasIdeCheckOnSave.CheckNow;
var
  mProject: IOTAProject;
begin
  mProject := ActiveProject;
  if (mProject <> nil) and not FChecking and not FCore.BuildRunning and not Debugging then
  begin
    Run(mProject.FileName, True);
  end;
end;

procedure TAtlasIdeCheckOnSave.Run(const AProject: string; AManual: Boolean);
var
  mServices: IOTAModuleServices;
  mProject: IOTAProject;
  mStarted, mDuration: Int64;
  mActivity: IInterface;
  mText: string;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) or
    not Supports(mServices.FindModule(AProject), IOTAProject, mProject) or (mProject.ProjectBuilder = nil) then
  begin
    Exit;
  end;
  mActivity := TAtlasActivity.Scope('Compilerprüfung nach dem Speichern');
  FChecking := True;
  FEvents.Background := True;
  mStarted := NowMs;
  try
    mProject.ProjectBuilder.BuildProject(cmOTACheck, False, True);
  finally
    FEvents.Background := False;
    FChecking := False;
  end;
  mDuration := NowMs - mStarted;
  if Assigned(FReport) then
  begin
    FReport(Format('Compilerprüfung %s: %s, %d ms', [IfThen(AManual, 'von Hand', 'nach dem Speichern'),
      ExtractFileName(AProject), mDuration]));
  end;
  if not AManual and FCore.CheckFinished(AProject, mDuration) then
  begin
    mText := TAtlasStrings.Fmt(TAtlasTextId.CheckOnSaveDisabled, [ExtractFileName(AProject), mDuration, FCore.MaxMs]);
    // Benachrichtigungszentrale (#601, Quelle check): Meldungsfenster nur bei „einblenden“.
    if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Check, TAtlasNotificationSeverity.Warning,
      TAtlasStrings.Text(TAtlasTextId.NotificationsCheckDisabled), mText) = TAtlasNotificationMode.Show then
    begin
      AddMessage(mText);
    end;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.IDE.Build.CheckOnSave', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.