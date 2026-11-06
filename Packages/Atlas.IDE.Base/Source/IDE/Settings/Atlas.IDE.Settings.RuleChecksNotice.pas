unit Atlas.IDE.Settings.RuleChecksNotice;

// Hinweis „Prüfregeln sind aus“ (#1454) in der IDE: Ein IDE-Notifier meldet
// geöffnete Projekte und Projektgruppen; legt die nächste atlas.json darüber
// Prüfregeln fest, ist das Modul Prüfregeln (ruleChecks.enabled) aber aus,
// kommt einmal je atlas.json und Sitzung ein Hinweis mit „Prüfregeln
// einschalten“ (Quelle ruleChecks der Benachrichtigungszentrale). Der Knopf
// schaltet wie der Schnellschalter um (TAtlasIdeQuickToggles). Gehört zum
// Kern, nicht zum Modul Prüfregeln: Er meldet sich gerade, wenn das Modul aus
// ist. Beim Start gilt ein schon geladenes Projekt als eben geöffnet.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Settings.RuleChecksNotice,
  Atlas.UI.Notifications.Notice;

type
  TAtlasIdeRuleChecksNotice = class
  private type
    TIdeNotifier = class(TNotifierObject, IOTAIDENotifier)
    private
      FOwner: TAtlasIdeRuleChecksNotice;
    public
      procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
      procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
      procedure AfterCompile(Succeeded: Boolean); overload;
    end;
  private
    FCore: TAtlasRuleChecksNotice;
    FNotifier: TIdeNotifier;
    FNotifierRef: IOTAIDENotifier;
    FNotifierIndex: Integer;
    FToast: TAtlasNoticeWindow;
    procedure Opened(const AFileName: string);
    procedure Show(const AProjectFile: string);
    class function IsProjectFile(const AFileName: string): Boolean; static;
    class function ConfigExists(const AFileName: string): Boolean; static;
    class procedure TurnOn; static;
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  System.Types,
  System.IOUtils,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Settings.QuickToggles,
  Atlas.UI.Popup.Window,
  Atlas.UI.Strings;

const
  cModule = 'ruleChecks';
  cSwitchKey = 'ruleChecks.enabled';

{ TAtlasIdeRuleChecksNotice.TIdeNotifier }

procedure TAtlasIdeRuleChecksNotice.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
var
  mOwner: TAtlasIdeRuleChecksNotice;
  mName: string;
begin
  mOwner := FOwner;
  if (mOwner = nil) or (NotifyCode <> ofnFileOpened) or not IsProjectFile(FileName) then
  begin
    Exit;
  end;
  mName := FileName;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      mOwner.Opened(mName);
    end);
end;

procedure TAtlasIdeRuleChecksNotice.TIdeNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TAtlasIdeRuleChecksNotice.TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ TAtlasIdeRuleChecksNotice }

constructor TAtlasIdeRuleChecksNotice.Create;
var
  mServices: IOTAServices;
  mModules: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
begin
  inherited Create;
  FCore := TAtlasRuleChecksNotice.Create;
  FNotifierIndex := -1;
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    FNotifier := TIdeNotifier.Create;
    FNotifier.FOwner := Self;
    FNotifierRef := FNotifier;
    FNotifierIndex := mServices.AddNotifier(FNotifierRef);
  end;
  // Die IDE lädt das letzte Projekt oft vor dem Plugin: ein schon geladenes gilt als eben geöffnet.
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    mGroup := mModules.MainProjectGroup;
    if (mGroup <> nil) and (mGroup.ActiveProject <> nil) then
    begin
      Opened(mGroup.ActiveProject.FileName);
    end;
  end;
end;

destructor TAtlasIdeRuleChecksNotice.Destroy;
var
  mServices: IOTAServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if FNotifier <> nil then
  begin
    FNotifier.FOwner := nil;
  end;
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    mServices.RemoveNotifier(FNotifierIndex);
  end;
  FNotifierRef := nil;
  FToast.Free;
  FCore.Free;
  inherited;
end;

class function TAtlasIdeRuleChecksNotice.IsProjectFile(const AFileName: string): Boolean;
var
  mExt: string;
begin
  mExt := ExtractFileExt(AFileName);
  Result := SameText(mExt, '.dproj') or SameText(mExt, '.dpr') or SameText(mExt, '.dpk') or
    SameText(mExt, '.groupproj');
end;

class function TAtlasIdeRuleChecksNotice.ConfigExists(const AFileName: string): Boolean;
begin
  Result := TFile.Exists(AFileName);
end;

procedure TAtlasIdeRuleChecksNotice.Opened(const AFileName: string);
var
  mConfig, mText: string;
begin
  // Ist das Modul an, nicht einmal die Datei lesen.
  if TAtlasIdeSettings.ModuleOn(cModule) then
  begin
    Exit;
  end;
  mConfig := TAtlasRuleChecksNotice.ConfigFor(TPath.GetFullPath(AFileName), ConfigExists);
  if mConfig = '' then
  begin
    Exit;
  end;
  try
    mText := TAtlasTextFile.Load(mConfig).Text;
  except
    on Exception do
      Exit;
  end;
  if FCore.Wanted(mConfig, mText, TAtlasIdeSettings.ModuleOn(cModule)) then
  begin
    Show(AFileName);
  end;
end;

class procedure TAtlasIdeRuleChecksNotice.TurnOn;
begin
  // Schon eingeschaltet (z. B. über die Optionsseite): nicht wieder ausschalten.
  if not TAtlasIdeSettings.ModuleOn(cModule) then
  begin
    TAtlasIdeQuickToggles.Switch(cSwitchKey);
  end;
end;

procedure TAtlasIdeRuleChecksNotice.Show(const AProjectFile: string);
var
  mTitle, mText, mCaption: string;
  mArea: TRect;
begin
  mTitle := TAtlasStrings.Text(TAtlasTextId.RuleChecksNoticeTitle);
  mText := TAtlasStrings.Fmt(TAtlasTextId.RuleChecksNoticeText, [ExtractFileName(AProjectFile)]);
  mCaption := TAtlasStrings.Text(TAtlasTextId.RuleChecksTurnOn);
  if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.RuleChecks, TAtlasNotificationSeverity.Info,
    mTitle, mText, [TAtlasNotificationCenter.Action(mCaption, TurnOn)]) <> TAtlasNotificationMode.Show then
  begin
    Exit;
  end;
  if FToast = nil then
  begin
    FToast := TAtlasNoticeWindow.Create(nil);
    FToast.OnAction :=
      procedure(AIndex: Integer)
      begin
        if AIndex = 0 then
        begin
          TurnOn;
        end;
      end;
  end;
  mArea := Screen.WorkAreaRect;
  if Application.MainForm <> nil then
  begin
    mArea := Application.MainForm.BoundsRect;
  end;
  FToast.Colors := TAtlasIdeStyle.Colors;
  FToast.SetScaling(TAtlasPopupWindow.MonitorPPI(mArea.BottomRight), 1, '', 10);
  FToast.ShowNotice(mTitle, mText, [mCaption], mArea);
end;

end.
