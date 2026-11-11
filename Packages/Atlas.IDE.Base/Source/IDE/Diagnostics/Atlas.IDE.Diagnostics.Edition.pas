unit Atlas.IDE.Diagnostics.Edition;

// Kommandozeilen-Compiler der IDE (#1822): TAtlasIdeEdition sieht einmal je Sitzung im Ordner der Installation
// nach (IOTAServices.GetRootDirectory, sonst $(BDS)) und beantwortet für Base und Module, ob er fehlt; die Startzeile
// des Protokolls nennt das Ergebnis (LogNote). TAtlasIdeEditionNotice zeigt ohne Compiler einmal überhaupt einen
// Hinweis mit „Einstellungen“ (Benachrichtigungszentrale, Quelle edition; gemerkt in ui.editionNoticeShown).
// diagnostics.editionCheck aus: der Compiler gilt als vorhanden, kein Hinweis, Startzeile wie vorher.
// Builds für KI-Assistenten laufen ohnehin über IOTAProjectBuilder (Modul Build-Pipeline) und brauchen keinen.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Edition,
  Atlas.UI.Notifications.Notice;

type
  TAtlasIdeEdition = class
  private class var
    FTools: TAtlasCompilerTools;
    FDetected: Boolean;
  public
    /// <summary>Ergebnis der Suche; gesucht wird beim ersten Aufruf.</summary>
    class function Tools: TAtlasCompilerTools; static;
    /// <summary>diagnostics.editionCheck an und kein dcc32/dcc64 gefunden.</summary>
    class function CommandLineMissing: Boolean; static;
    /// <summary>Zusatz der Startzeile (", command-line compiler: …"); '' mit diagnostics.editionCheck aus.</summary>
    class function LogNote: string; static;
  end;

  /// <summary>Einmaliger Hinweis ohne Kommandozeilen-Compiler; besitzt seine Einblendung.</summary>
  TAtlasIdeEditionNotice = class
  private
    FShowSettings: TProc;
    FToast: TAtlasNoticeWindow;
    procedure Show;
  public
    /// <summary>Zeigt den Hinweis sofort, wenn er fällig ist; AShowSettings öffnet die Einstellung.</summary>
    constructor Create(const AShowSettings: TProc);
    destructor Destroy; override;
  end;

implementation

uses
  System.Types,
  ToolsAPI,
  Vcl.Forms,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.UI.Popup.Window,
  Atlas.UI.Diagnostics.Strings;

/// <summary>Ordner der Installation; '' unbekannt.</summary>
function RootDirectory: string;
var
  mServices: IOTAServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Result := mServices.GetRootDirectory;
  end;
  if Result = '' then
  begin
    Result := GetEnvironmentVariable('BDS');
  end;
end;

{ TAtlasIdeEdition }

class function TAtlasIdeEdition.Tools: TAtlasCompilerTools;
begin
  if not FDetected then
  begin
    FTools := TAtlasEdition.Detect(RootDirectory,
      function(const AFileName: string): Boolean
      begin
        Result := FileExists(AFileName);
      end);
    FDetected := True;
  end;
  Result := FTools;
end;

class function TAtlasIdeEdition.CommandLineMissing: Boolean;
begin
  Result := TAtlasEdition.Missing(Tools, TAtlasIdeSettings.Current.DiagnosticsEditionCheck);
end;

class function TAtlasIdeEdition.LogNote: string;
begin
  Result := '';
  if TAtlasIdeSettings.Current.DiagnosticsEditionCheck then
  begin
    Result := ', ' + Tools.LogText;
  end;
end;

{ TAtlasIdeEditionNotice }

constructor TAtlasIdeEditionNotice.Create(const AShowSettings: TProc);
var
  mNext: TAtlasPluginSettings;
begin
  inherited Create;
  FShowSettings := AShowSettings;
  if not TAtlasEdition.ShouldNotify(TAtlasIdeEdition.Tools, TAtlasIdeSettings.Current.DiagnosticsEditionCheck,
    TAtlasIdeSettings.Stored.EditionNoticeShown) then
  begin
    Exit;
  end;
  mNext := TAtlasIdeSettings.Stored;
  mNext.EditionNoticeShown := True;
  TAtlasIdeSettings.Update(mNext);
  Show;
end;

destructor TAtlasIdeEditionNotice.Destroy;
begin
  FToast.Free;
  inherited;
end;

procedure TAtlasIdeEditionNotice.Show;
var
  mTitle, mText, mCaption: string;
  mArea: TRect;
  mShowSettings: TProc;
begin
  mTitle := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.EditionNoticeTitle);
  mText := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.EditionNoticeText);
  mCaption := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.EditionSettings);
  mShowSettings := FShowSettings;
  if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cEdition, TAtlasNotificationSeverity.Info,
    mTitle, mText, [TAtlasNotificationCenter.Action(mCaption, mShowSettings)]) <> TAtlasNotificationMode.Show then
  begin
    Exit;
  end;
  FToast := TAtlasNoticeWindow.Create(nil);
  FToast.OnAction :=
    procedure(AIndex: Integer)
    begin
      if (AIndex = 0) and Assigned(mShowSettings) then
      begin
        mShowSettings;
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
