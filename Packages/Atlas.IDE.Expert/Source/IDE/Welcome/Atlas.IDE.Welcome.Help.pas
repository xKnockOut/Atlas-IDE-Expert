unit Atlas.IDE.Welcome.Help;

// Bereich „Hilfe und Rückmeldung“ in der IDE (#766): Quelle des Bereichs
// (IAtlasHelpSource) und Bereich atlas.help der Willkommensseite.
// - „Atlas-Doku“ öffnet Doku\index.html aus dem Installationsordner im
//   Browser, ohne Installation die Doku-Seite des Repositorys.
// - „Tastenkürzel“ öffnet die Übersicht aus #520 (alle Kürzel); ausgegraut
//   mit keys.overview aus.
// - „Problem melden …“ zeigt den Dialog mit dem Diagnosepaket: Logs von
//   Plugin (atlas.log) und Server (Diagnoselogs der letzten 7 Tage, #647),
//   Versionen, Einstellungen ohne Pfade und optional die letzten
//   Diagnosedaten (#479). Ziel der ZIP ist welcomePage.help.reportFolder
//   (leer: Desktop), Ziel der Issue-Seite welcomePage.help.reportUrl.
//   Explorer, Zwischenablage und Browser öffnet nur ein Klick des Nutzers;
//   Atlas selbst greift nicht aufs Netz zu und sendet nichts.
// - welcomePage.help aus: kein Bereich.
// Protokoll anonym: nur, dass der Dialog geöffnet wurde.

interface

uses
  System.SysUtils,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Diagnostics.Package,
  Atlas.UI.Welcome.Help;

type
  TAtlasIdeHelp = class(TInterfacedObject, IAtlasHelpSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts: zuletzt in der rechten Spalte.</summary>
    Order = 90;
  private
    FShowKeys: TProc;
    FStarted: Boolean;
    FTitle: string;
    FActive: Boolean;
  public
    /// <summary>AShowKeys: Tastenkürzel-Übersicht (#520) zeigen; nil = ohne.</summary>
    constructor Create(const AShowKeys: TProc);
    /// <summary>Bereich und Fabrik anmelden.</summary>
    procedure Start;
    /// <summary>Bereich und Fabrik abmelden (beim Entladen).</summary>
    procedure Stop;
    /// <summary>Nach geänderten Einstellungen: Sichtbarkeit und Knöpfe neu.</summary>
    procedure Refresh;
    function Section: TAtlasWelcomeSection;
    /// <summary>welcomePage.enabled und welcomePage.help an?</summary>
    class function Active: Boolean; static;
    /// <summary>Doku\index.html neben dem Plugin oder die Doku-Seite des Repositorys.</summary>
    class function DocsTarget: string; static;
    /// <summary>Ordner für die ZIP: welcomePage.help.reportFolder, sonst der Desktop.</summary>
    class function ReportFolder: string; static;
    /// <summary>Alles für das Diagnosepaket außer den gewählten Teilen.</summary>
    class function PackageInput: TAtlasPackageInput; static;
    { IAtlasHelpSource }
    function KeysAvailable: Boolean;
    procedure OpenDocs;
    procedure ShowKeys;
    procedure ReportProblem;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  Winapi.ShlObj,
  System.Classes,
  System.IOUtils,
  Vcl.Clipbrd,
  Atlas.Core.Product.Version,
  Atlas.Core.Updates.Check,
  Atlas.Core.Settings.Choices,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Export,
  Atlas.Core.Welcome.Help,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Diagnostics.ReportDialog,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Diagnostics.BugReport,
  Atlas.IDE.Diagnostics.Timing;

/// <summary>Datei oder Webadresse mit dem zuständigen Programm öffnen (Browser).</summary>
procedure OpenTarget(const ATarget: string);
begin
  ShellExecute(0, 'open', PChar(ATarget), nil, nil, SW_SHOWNORMAL);
end;

function DesktopFolder: string;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  Result := '';
  if SHGetFolderPath(0, CSIDL_DESKTOPDIRECTORY, 0, 0, @Buffer[0]) = S_OK then
    Result := Buffer;
  if Result = '' then
    Result := TPath.GetDocumentsPath;
end;

{ TAtlasIdeHelp }

constructor TAtlasIdeHelp.Create(const AShowKeys: TProc);
begin
  inherited Create;
  FShowKeys := AShowKeys;
end;

class function TAtlasIdeHelp.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.WelcomePage and TAtlasIdeSettings.Current.WelcomePageHelp;
end;

procedure TAtlasIdeHelp.Start;
begin
  FStarted := True;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.Help,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeHelpFrame;
    begin
      Frame := TAtlasWelcomeHelpFrame.Create(AOwner);
      Frame.Source := Self;
      Result := Frame;
    end);
  FTitle := '';
  Refresh;
end;

procedure TAtlasIdeHelp.Stop;
begin
  FStarted := False;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.Help);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.Help);
end;

function TAtlasIdeHelp.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.Help, TAtlasWelcomeHelpFrame.TitleText, Order,
    TAtlasWelcomeColumn.Right,
    function: Boolean
    begin
      Result := Active;
    end);
end;

procedure TAtlasIdeHelp.Refresh;
var
  Next: TAtlasWelcomeSection;
begin
  if not FStarted then
    Exit;
  Next := Section;
  // Nur beim ersten Mal (oder nach einem Sprachwechsel) anmelden: Add meldet allen Beobachtern.
  if Next.Title <> FTitle then
  begin
    FTitle := Next.Title;
    FActive := Active;
    TAtlasWelcomeSections.Default.Add(Next);
    Exit;
  end;
  // welcomePage.help umgeschaltet: Auswahl neu; sonst nur die Knöpfe (keys.overview).
  if FActive <> Active then
  begin
    FActive := Active;
    TAtlasWelcomeSections.Default.Changed;
  end;
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Help);
end;

function TAtlasIdeHelp.KeysAvailable: Boolean;
begin
  Result := Assigned(FShowKeys) and TAtlasIdeSettings.Current.KeyOverview;
end;

class function TAtlasIdeHelp.DocsTarget: string;
begin
  Result := TAtlasHelp.DocsTarget(ExtractFilePath(GetModuleName(HInstance)),
    function(AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end);
end;

procedure TAtlasIdeHelp.OpenDocs;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if not Active then
        Exit;
      OpenTarget(DocsTarget);
    end);
end;

procedure TAtlasIdeHelp.ShowKeys;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if Active and KeysAvailable then
        FShowKeys();
    end);
end;

class function TAtlasIdeHelp.ReportFolder: string;
begin
  Result := TAtlasIdeSettings.Current.WelcomePageHelpReportFolder;
  if Result = '' then
    Result := DesktopFolder;
end;

class function TAtlasIdeHelp.PackageInput: TAtlasPackageInput;
begin
  Result := Default(TAtlasPackageInput);
  Result.AtlasVersion := TAtlasPluginVersion.Version;
  Result.IdeVersion := TAtlasSettingChoices.DelphiCaption(TAtlasUpdates.IdeVersion);
  Result.WindowsVersion := TOSVersion.ToString;
  {$IFDEF WIN64}
  Result.Platform := 'Win64';
  {$ELSE}
  Result.Platform := 'Win32';
  {$ENDIF}
  Result.PluginLog := TPath.Combine(TAtlasRotatingLog.DefaultFolder, 'atlas.log');
  Result.ServerLogs := TAtlasDiagnosticExport.Files(TAtlasDiagnosticExport.DefaultFolder,
    TAtlasDiagnosticExport.DefaultDays, Now);
  Result.SettingsJson := TAtlasIdeBugReport.SettingsJson;
  Result.LastDataFile := TAtlasIdeDiagnosticMode.LastDataFile;
  Result.Roots := TAtlasIdeBugReport.ProjectRoots;
  Result.Identity := TAtlasIdeBugReport.Identity;
  Result.Created := Now;
end;

procedure TAtlasIdeHelp.ReportProblem;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Actions: TAtlasReportActions;
    begin
      if not Active then
        Exit;
      Actions := Default(TAtlasReportActions);
      Actions.ShowFile :=
        procedure(AFileName: string)
        begin
          // Ordner im Explorer, die neue ZIP markiert.
          ShellExecute(0, nil, 'explorer.exe', PChar('/select,"' + AFileName + '"'), nil, SW_SHOWNORMAL);
        end;
      Actions.CopyText :=
        procedure(AText: string)
        begin
          Clipboard.AsText := AText;
        end;
      Actions.OpenUrl :=
        procedure(AUrl: string)
        begin
          // Nur Webadressen; der Dialog hat sie schon geprüft.
          if TAtlasDiagnosticPackage.IsWebUrl(AUrl) then
            OpenTarget(AUrl);
        end;
      TAtlasGuard.Log('Problem melden (#766): Dialog geöffnet');
      TAtlasReportDialog.Execute(PackageInput, ReportFolder, TAtlasIdeSettings.Current.WelcomePageHelpReportUrl,
        Actions);
    end);
end;

end.
