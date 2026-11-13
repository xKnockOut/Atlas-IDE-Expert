unit Atlas.IDE.Designer.DesktopLayout;

// Eigenes Desktop-Layout im Formular-Designer (#2079) in der IDE: Ein Takt
// (100 ms) erhebt, was die IDE zeigt, und gibt es an TAtlasDesktopSwitch;
// verlangt der ein anderes Layout, lädt die Unit es über das
// Desktop-Auswahlfeld der Titelleiste (AppBuilder.cbDesktop).
// - Laden: ItemIndex setzen und Click wie bei einer Auswahl mit der Maus.
//   Eine CBN_SELCHANGE-Nachricht ändert nur den Text, lädt aber nichts. Die
//   ToolsAPI kennt kein Laden eines Layouts.
// - Ansicht: Designer, wenn TAtlasIdeDesignerView einen Formular-Editor im
//   vordersten Editorfenster zeigt; sonst Code, solange ein Modul offen ist.
// - Layouts: Einträge des Auswahlfelds (Anzeigenamen in der Sprache der
//   IDE). Das Standard-Layout steht in der Registry (Session\DefaultDesktopName)
//   englisch und wird über TAtlasDesktopLayouts.DisplayName zugeordnet.
// - Debuggen: IOTADebuggerServices.ProcessCount; Projekt laden: zwischen
//   ofnBeginProjectGroupOpen und ofnEndProjectGroupOpen.
// - Speichern: Die IDE speichert ein Layout nur über ihren Dialog
//   (ViewSaveDesktopCommand); der Befehl öffnet ihn.
// Nur im Hauptthread.

interface

uses
  System.SysUtils;

type
  TAtlasIdeDesktopLayout = class
  public
    /// <summary>Takt starten; Meldungen (fehlendes Layout) gehen an AOnMessage.</summary>
    class procedure Install(const AOnMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>Dialog „Desktop speichern“ der IDE öffnen.</summary>
    class procedure SaveCurrent; static;
    /// <summary>Ist designer.layout an?</summary>
    class function Enabled: Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.Win.Registry,
  System.Actions,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Designer.DesktopSwitch,
  Atlas.UI.Designer.ViewStrings,
  Atlas.IDE.Foundation.DesignerView,
  Atlas.IDE.Foundation.Settings;

const
  cTickMilliseconds = 100;
  cRegistryMilliseconds = 5000;
  cComboName = 'cbDesktop';
  cSaveAction = 'ViewSaveDesktopCommand';
  cSessionKey = '\Session';
  cDefaultValue = 'DefaultDesktopName';

type
  TComboAccess = class(TCustomComboBox);

  TRunner = class;

  TProjectNotifier = class(TNotifierObject, IOTAIDENotifier)
  private
    FOwner: TRunner;
  public
    procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
    procedure AfterCompile(Succeeded: Boolean); overload;
  end;

  TRunner = class
  private
    FOnMessage: TProc<string>;
    FSwitch: TAtlasDesktopSwitch;
    FTimer: TTimer;
    FNotifier: TProjectNotifier;
    FNotifierIndex: Integer;
    FProjectLoading: Boolean;
    FDefaultLayout: string;
    FDefaultRead: UInt64;
    FDefaultReadOnce: Boolean;
    FComboMissingLogged: Boolean;
    procedure TimerTick(Sender: TObject);
    procedure Tick;
    function DefaultLayout(ANow: UInt64): string;
    procedure Load(ACombo: TCustomComboBox; const AAction: TAtlasDesktopAction);
  public
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
  end;

var
  GRunner: TRunner;

/// <summary>Desktop-Auswahlfeld der Titelleiste; nil ohne (oder noch ohne Fenster).</summary>
function DesktopCombo: TCustomComboBox;

  function Search(AControl: TWinControl): TCustomComboBox;
  var
    mIndex: Integer;
  begin
    Result := nil;
    for mIndex := 0 to AControl.ControlCount - 1 do
    begin
      if (AControl.Controls[mIndex] is TCustomComboBox) and SameText(AControl.Controls[mIndex].Name, cComboName) then
      begin
        Exit(TCustomComboBox(AControl.Controls[mIndex]));
      end;
      if AControl.Controls[mIndex] is TWinControl then
      begin
        Result := Search(TWinControl(AControl.Controls[mIndex]));
        if Result <> nil then
        begin
          Exit;
        end;
      end;
    end;
  end;

var
  mComponent: TComponent;
begin
  Result := nil;
  if Application.MainForm = nil then
  begin
    Exit;
  end;
  mComponent := Application.MainForm.FindComponent(cComboName);
  if mComponent is TCustomComboBox then
  begin
    Result := TCustomComboBox(mComponent);
  end
  else
  begin
    Result := Search(Application.MainForm);
  end;
  // Items braucht das Fenster („hat kein übergeordnetes Fenster“).
  if (Result <> nil) and not Result.HandleAllocated then
  begin
    Result := nil;
  end;
end;

function ItemsOf(ACombo: TCustomComboBox): TArray<string>;
begin
  Result := TAtlasDesktopLayouts.Usable(ACombo.Items.ToStringArray);
end;

function CurrentView: TAtlasDesktopView;
var
  mModules: IOTAModuleServices;
begin
  if TAtlasIdeDesignerView.CurrentFormEditor <> nil then
  begin
    Exit(TAtlasDesktopView.Designer);
  end;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) and (mModules.CurrentModule <> nil) then
  begin
    Exit(TAtlasDesktopView.Code);
  end;
  Result := TAtlasDesktopView.Unknown;
end;

function Debugging: Boolean;
var
  mDebugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) and (mDebugger.ProcessCount > 0);
end;

function CurrentOptions: TAtlasDesktopSwitchOptions;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasDesktopSwitchOptions.Defaults;
  Result.Enabled := mSettings.DesignerLayout;
  Result.DesignerLayout := mSettings.DesignerLayoutName;
  if mSettings.DesignerLayoutReturnTo = TAtlasPluginSettings.cDesignerLayoutDefault then
  begin
    Result.ReturnTo := TAtlasDesktopReturn.IdeDefault;
  end;
  Result.SkipWhileDebugging := mSettings.DesignerLayoutSkipWhileDebugging;
end;

/// <summary>Gespeicherter Name des Standard-Layouts der IDE; leer ohne.</summary>
function StoredDefaultLayout: string;
var
  mServices: IOTAServices;
  mRegistry: TRegistry;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Exit;
  end;
  mRegistry := TRegistry.Create(KEY_READ);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    if mRegistry.OpenKeyReadOnly(mServices.GetBaseRegistryKey + cSessionKey) and
      mRegistry.ValueExists(cDefaultValue) then
    begin
      Result := mRegistry.ReadString(cDefaultValue);
    end;
  finally
    mRegistry.Free;
  end;
end;

function FindAction(const AName: string): TContainedAction;
var
  mServices: INTAServices;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
  begin
    if SameText(mServices.ActionList.Actions[mIndex].Name, AName) then
    begin
      Exit(mServices.ActionList.Actions[mIndex]);
    end;
  end;
end;

{ TProjectNotifier }

procedure TProjectNotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
begin
  if FOwner = nil then
  begin
    Exit;
  end;
  if NotifyCode = ofnBeginProjectGroupOpen then
  begin
    FOwner.FProjectLoading := True;
  end
  else if NotifyCode = ofnEndProjectGroupOpen then
  begin
    FOwner.FProjectLoading := False;
  end;
end;

procedure TProjectNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TProjectNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ TRunner }

constructor TRunner.Create(const AOnMessage: TProc<string>);
var
  mServices: IOTAServices;
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FSwitch := TAtlasDesktopSwitch.Create;
  FNotifierIndex := -1;
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    FNotifier := TProjectNotifier.Create;
    FNotifier.FOwner := Self;
    FNotifierIndex := mServices.AddNotifier(FNotifier);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMilliseconds;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

destructor TRunner.Destroy;
var
  mServices: IOTAServices;
begin
  FTimer.Free;
  if FNotifier <> nil then
  begin
    FNotifier.FOwner := nil;
    // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter.
    if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
    begin
      mServices.RemoveNotifier(FNotifierIndex);
    end;
    FNotifier := nil;
  end;
  FSwitch.Free;
  FOnMessage := nil;
  inherited Destroy;
end;

procedure TRunner.TimerTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.DesignerBar, Tick);
end;

function TRunner.DefaultLayout(ANow: UInt64): string;
begin
  // Die Registry nicht in jedem Takt lesen.
  if not FDefaultReadOnce or (ANow < FDefaultRead) or (ANow - FDefaultRead >= cRegistryMilliseconds) then
  begin
    FDefaultLayout := StoredDefaultLayout;
    FDefaultRead := ANow;
    FDefaultReadOnce := True;
  end;
  Result := FDefaultLayout;
end;

procedure TRunner.Tick;
var
  mOptions: TAtlasDesktopSwitchOptions;
  mState: TAtlasDesktopState;
  mCombo: TCustomComboBox;
  mAction: TAtlasDesktopAction;
begin
  mOptions := CurrentOptions;
  mState := Default(TAtlasDesktopState);
  mCombo := nil;
  if mOptions.Enabled and (mOptions.DesignerLayout <> '') then
  begin
    mCombo := DesktopCombo;
    if mCombo = nil then
    begin
      if not FComboMissingLogged then
      begin
        FComboMissingLogged := True;
        TAtlasGuard.Log('Designer layout: desktop combo box of the IDE not found');
      end;
      Exit;
    end;
    mState.View := CurrentView;
    mState.Ticks := GetTickCount64;
    mState.Debugging := Debugging;
    mState.ProjectLoading := FProjectLoading;
    mState.CurrentLayout := mCombo.Text;
    mState.Layouts := ItemsOf(mCombo);
    if mOptions.ReturnTo = TAtlasDesktopReturn.IdeDefault then
    begin
      mState.DefaultLayout := TAtlasDesktopLayouts.DisplayName(mState.Layouts, DefaultLayout(mState.Ticks));
    end;
  end;
  mAction := FSwitch.Step(mOptions, mState);
  if mAction.Kind = TAtlasDesktopActionKind.Load then
  begin
    Load(mCombo, mAction);
  end
  else if (mAction.Kind = TAtlasDesktopActionKind.Missing) and Assigned(FOnMessage) then
  begin
    FOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.DesktopMissing, [mAction.Layout]));
  end;
end;

procedure TRunner.Load(ACombo: TCustomComboBox; const AAction: TAtlasDesktopAction);
var
  mIndex: Integer;
  mEditor: IOTAFormEditor;
begin
  mIndex := ACombo.Items.IndexOf(AAction.Layout);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mEditor := nil;
  if AAction.ToDesigner then
  begin
    mEditor := TAtlasIdeDesignerView.CurrentFormEditor;
  end;
  ACombo.ItemIndex := mIndex;
  TComboAccess(ACombo).Click;
  TComboAccess(ACombo).Select;
  // Hat das neue Layout den Designer verdeckt, ihn wieder nach vorn holen.
  if (mEditor <> nil) and (TAtlasIdeDesignerView.CurrentFormEditor = nil) then
  begin
    mEditor.Show;
  end;
end;

{ TAtlasIdeDesktopLayout }

class procedure TAtlasIdeDesktopLayout.Install(const AOnMessage: TProc<string>);
begin
  if GRunner = nil then
  begin
    GRunner := TRunner.Create(AOnMessage);
  end;
end;

class procedure TAtlasIdeDesktopLayout.Uninstall;
begin
  FreeAndNil(GRunner);
end;

class procedure TAtlasIdeDesktopLayout.SaveCurrent;
var
  mAction: TContainedAction;
begin
  mAction := FindAction(cSaveAction);
  if mAction = nil then
  begin
    TAtlasGuard.Log('Designer layout: action ' + cSaveAction + ' not found');
    Exit;
  end;
  mAction.Execute;
end;

class function TAtlasIdeDesktopLayout.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DesignerLayout;
end;

end.
