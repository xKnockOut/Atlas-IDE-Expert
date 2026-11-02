unit Atlas.IDE.Notifications.Service;

// Benachrichtigungszentrale in der IDE (#601):
// - Schaltet die Zentrale des Plugins (TAtlasNotificationCenter.Default) nach
//   den Einstellungen ein oder aus und setzt Höchstzahl und Verhalten je
//   Quelle (notifications.*). Ausgeschaltet verhält sich alles wie vor #601.
// - Liste TAtlasNotificationsWindow über dem Atlas-Statusfeld: Klick auf die
//   Plakette im Feld, Befehl Atlas.Notifications in der Befehlspalette oder
//   Tastenkürzel (Vorgabe Strg+Umschalt+Alt+N, Editorbefehl wie #399).
// - Jede Änderung der Zentrale (aus jedem Thread) führt gesammelt im
//   Hauptthread Plakette (OnBadge) und offene Liste nach.
// - Verhalten einer Quelle aus dem Kontextmenü der Liste wird in
//   notifications.sources gespeichert.
// - Einträge der Quellen „Build fertig“ und „Hintergrundprüfung“ nach jedem
//   Lauf (BuildFinished) mit „Zum Fehler“; Builds des Benutzers mit lesbaren
//   Meldungen nach der Bewertung von #530 (BuildEvaluated: Basislinie,
//   build.zeroHints, build.warningsAsErrors). Eine eigene Einblendung „Build
//   fertig“ gibt es noch nicht (#535); dort wirken Show und Collect gleich.
// Die übrigen Quellen melden selbst über IAtlasNotificationCenter.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Verdict,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Build,
  Atlas.UI.Notifications.Window;

type
  /// <summary>Plakette im Statusfeld: Zahl der ungelesenen (0 = keine) und schwerster ungelesener Eintrag.
  /// </summary>
  TAtlasNotificationBadgeEvent = reference to procedure(AUnread: Integer; AWorst: TAtlasNotificationSeverity);

  TAtlasIdeNotifications = class(TComponent)
  private class var
    FInstance: TAtlasIdeNotifications;
  private
    FWindow: TAtlasNotificationsWindow;
    FListener: Integer;
    FPending: Integer;
    FOnAnchor: TFunc<TPoint>;
    FOnBadge: TAtlasNotificationBadgeEvent;
    // Fehler der letzten Hintergrundprüfung je Projekt (für „wieder fehlerfrei“).
    FCheckErrors: TDictionary<string, Integer>;
    procedure Changed;
    procedure Refresh;
    procedure Post(const ANotice: TAtlasBuildNotice; const AProject: TAtlasCompileProject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    class function Instance: TAtlasIdeNotifications; static;
    /// <summary>Zentrale ist an (Einstellung und Sicherung).</summary>
    class function Active: Boolean; static;
    /// <summary>Liste über dem Statusfeld öffnen bzw. schließen (Taste, Befehl); ohne Dienst nichts.</summary>
    class procedure ShowList; static;
    /// <summary>Verhalten von ASource dauerhaft speichern (notifications.sources).</summary>
    class procedure SaveMode(const ASource: string; AMode: TAtlasNotificationMode); static;
    /// <summary>Einstellungen übernehmen: an/aus, Höchstzahl, Verhalten je Quelle.</summary>
    procedure ApplySettings;
    /// <summary>Liste mit der linken unteren Ecke an AAnchor öffnen; offen: schließen.</summary>
    procedure Show(const AAnchor: TPoint); overload;
    /// <summary>Über dem Statusfeld (OnAnchor), sonst unten links im aktiven Fenster.</summary>
    procedure Show; overload;
    /// <summary>Eintrag nach einem Build bzw. einer Hintergrundprüfung (Hauptthread).</summary>
    procedure BuildFinished(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      ASucceeded, AReadable: Boolean);
    /// <summary>Eintrag nach einem Build des Benutzers mit lesbaren Meldungen, bewertet nach #530 (Hauptthread).
    /// </summary>
    procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
    /// <summary>Linke Oberkante des Statusfelds im obersten Editorfenster; (MaxInt, MaxInt) ohne Feld.</summary>
    property OnAnchor: TFunc<TPoint> read FOnAnchor write FOnAnchor;
    /// <summary>Plakette nachführen; läuft im Hauptthread.</summary>
    property OnBadge: TAtlasNotificationBadgeEvent read FOnBadge write FOnBadge;
  end;

implementation

uses
  System.Math,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation;

{ TAtlasIdeNotifications }

constructor TAtlasIdeNotifications.Create(AOwner: TComponent);
var
  Service: TAtlasIdeNotifications;
begin
  inherited Create(AOwner);
  FInstance := Self;
  FCheckErrors := TDictionary<string, Integer>.Create;
  Service := Self;
  FListener := TAtlasNotificationCenter.Default.AddListener(
    procedure
    begin
      // Aus jedem Thread: gesammelt einmal im Hauptthread nachführen.
      if AtomicExchange(Service.FPending, 1) <> 0 then
        Exit;
      TAtlasMainThread.ForceQueue(TAtlasFeature.Notifications,
        procedure
        begin
          if FInstance <> Service then
            Exit;
          AtomicExchange(Service.FPending, 0);
          Service.Refresh;
        end);
    end);
  ApplySettings;
end;

destructor TAtlasIdeNotifications.Destroy;
begin
  // Erst abmelden, dann freigeben (#493).
  TAtlasNotificationCenter.Default.RemoveListener(FListener);
  if FInstance = Self then
    FInstance := nil;
  if FWindow <> nil then
  begin
    FWindow.RemoveFreeNotification(Self);
    FreeAndNil(FWindow);
  end;
  FreeAndNil(FCheckErrors);
  inherited;
end;

procedure TAtlasIdeNotifications.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FWindow) then
    FWindow := nil;
end;

class function TAtlasIdeNotifications.Instance: TAtlasIdeNotifications;
begin
  Result := FInstance;
end;

class function TAtlasIdeNotifications.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Notifications and not TAtlasGuard.Disabled(TAtlasFeature.Notifications);
end;

class procedure TAtlasIdeNotifications.ShowList;
begin
  if (FInstance <> nil) and Active then
    FInstance.Show;
end;

class procedure TAtlasIdeNotifications.SaveMode(const ASource: string; AMode: TAtlasNotificationMode);
var
  Stored: TAtlasPluginSettings;
begin
  Stored := TAtlasIdeSettings.Stored;
  Stored.NotificationsSources := TAtlasNotificationSources.WithMode(Stored.NotificationsSources, ASource, AMode);
  TAtlasIdeSettings.Update(Stored);
end;

procedure TAtlasIdeNotifications.ApplySettings;
var
  Settings: TAtlasPluginSettings;
  Center: TAtlasNotificationCenter;
begin
  Settings := TAtlasIdeSettings.Current;
  Center := TAtlasNotificationCenter.DefaultCenter;
  Center.SetMaxEntries(Settings.NotificationsMaxEntries);
  Center.ApplyModes(Settings.NotificationsSources);
  Center.Enabled := Active;
  if not Center.Enabled then
  begin
    FCheckErrors.Clear;
    if FWindow <> nil then
      FWindow.Dismiss;
  end;
  Changed;
end;

procedure TAtlasIdeNotifications.Changed;
begin
  TAtlasGuard.Run(TAtlasFeature.Notifications, Refresh);
end;

procedure TAtlasIdeNotifications.Refresh;
var
  Center: IAtlasNotificationCenter;
  Worst: TAtlasNotificationSeverity;
  Unread: Integer;
begin
  Center := TAtlasNotificationCenter.Default;
  Unread := 0;
  Worst := TAtlasNotificationSeverity.Info;
  if Active and Center.WorstUnread(Worst) then
    Unread := Center.UnreadCount;
  if Assigned(FOnBadge) then
    FOnBadge(Unread, Worst);
  if FWindow <> nil then
    FWindow.Reload;
end;

procedure TAtlasIdeNotifications.Show(const AAnchor: TPoint);
begin
  // Zweiter Aufruf schließt.
  if FWindow <> nil then
  begin
    FWindow.Dismiss;
    Exit;
  end;
  if not Active then
    Exit;
  FWindow := TAtlasNotificationsWindow.CreateList(Application, TAtlasIdeStyle.Colors,
    TAtlasNotificationCenter.Default);
  FWindow.FreeNotification(Self);
  FWindow.OnModeChange :=
    procedure(const ASource: string; AMode: TAtlasNotificationMode)
    begin
      TAtlasGuard.Run(TAtlasFeature.Notifications,
        procedure
        begin
          SaveMode(ASource, AMode);
        end);
    end;
  FWindow.ShowAbove(AAnchor);
end;

procedure TAtlasIdeNotifications.Show;
var
  Anchor: TPoint;
  Area: TRect;
begin
  Anchor := Point(MaxInt, MaxInt);
  if Assigned(FOnAnchor) then
    Anchor := FOnAnchor();
  if Anchor.X = MaxInt then
  begin
    // Ohne Statusfeld: unten links im aktiven Fenster.
    if Screen.ActiveForm <> nil then
      Area := Screen.ActiveForm.BoundsRect
    else if Application.MainForm <> nil then
      Area := Application.MainForm.BoundsRect
    else
      Area := Screen.WorkAreaRect;
    Anchor := Point(Area.Left + 40, Area.Bottom - 40);
  end;
  Show(Anchor);
end;

procedure TAtlasIdeNotifications.BuildFinished(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; ASucceeded, AReadable: Boolean);
var
  Notice: TAtlasBuildNotice;
  Previous: Integer;
  Key: string;
begin
  if not Active then
    Exit;
  Key := LowerCase(AProject.FileName);
  Previous := -1;
  if AProject.Background and not FCheckErrors.TryGetValue(Key, Previous) then
    Previous := -1;
  Notice := TAtlasBuildNotices.FromRun(AMessages, ASucceeded, AReadable, AProject.Background, Previous);
  if AProject.Background and AReadable then
    FCheckErrors.AddOrSetValue(Key, Notice.Errors);
  Post(Notice, AProject);
end;

procedure TAtlasIdeNotifications.BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict);
begin
  if Active then
    Post(TAtlasBuildNotices.FromVerdict(AMessages, AVerdict), AProject);
end;

procedure TAtlasIdeNotifications.Post(const ANotice: TAtlasBuildNotice; const AProject: TAtlasCompileProject);
var
  Notice: TAtlasBuildNotice;
  Project, Title, Text, Action: string;
  Actions: TArray<TAtlasNotificationAction>;
  Target: TAtlasCompilerMessage;
begin
  Notice := ANotice;
  Project := ChangeFileExt(ExtractFileName(AProject.FileName), '');
  Action := TAtlasStrings.Text(TAtlasTextId.NotificationsGoToError);
  case Notice.Kind of
    TAtlasBuildNoticeKind.Errors:
      Title := TAtlasStrings.Fmt(TAtlasTextId.NotificationsBuildErrors, [Notice.Errors]);
    TAtlasBuildNoticeKind.Warnings:
      Title := TAtlasStrings.Fmt(TAtlasTextId.NotificationsBuildWarnings, [Notice.Warnings]);
    TAtlasBuildNoticeKind.Succeeded:
      Title := TAtlasStrings.Text(TAtlasTextId.NotificationsBuildSucceeded);
    TAtlasBuildNoticeKind.Failed:
      Title := TAtlasStrings.Text(TAtlasTextId.NotificationsBuildFailed);
    TAtlasBuildNoticeKind.CheckErrors:
      Title := TAtlasStrings.Fmt(TAtlasTextId.NotificationsCheckErrors, [Notice.Errors]);
    TAtlasBuildNoticeKind.CheckClean:
      Title := TAtlasStrings.Text(TAtlasTextId.NotificationsCheckClean);
    TAtlasBuildNoticeKind.Rejected:
      begin
        if Notice.Reason = TAtlasBuildVerdictReason.WarningsAsErrors then
          Title := TAtlasStrings.Fmt(TAtlasTextId.NotificationsBuildRejectedCodes, [Notice.PromotedCode])
        else
          Title := TAtlasStrings.Text(TAtlasTextId.NotificationsBuildRejected);
        Action := TAtlasStrings.Text(TAtlasTextId.NotificationsGoToMessage);
      end;
  else
    Exit;
  end;
  Text := TAtlasStrings.Fmt(TAtlasTextId.NotificationsBuildText, [Project, Notice.Errors, Notice.Warnings,
    Notice.Hints]);
  if Notice.Baselined > 0 then
    Text := Text + ' ' + TAtlasStrings.Fmt(TAtlasTextId.NotificationsBuildBaselined, [Notice.Baselined]);
  Actions := nil;
  if Notice.HasTarget then
  begin
    Target := Notice.Target;
    Text := Text + ' · ' + Format('%s(%d): %s', [ExtractFileName(Target.FileName), Target.Line, Target.Text]);
    Actions := [TAtlasNotificationCenter.Action(Action,
      procedure
      begin
        // Meldungen zählen ab 1, der Editor ab 0.
        TAtlasIdeNavigation.GoToLocation(Target.FileName, Max(0, Target.Line - 1), Max(0, Target.Column - 1));
      end)];
  end;
  TAtlasNotificationCenter.Default.Notify(TAtlasBuildNotices.SourceOf(AProject.Background), Notice.Severity, Title,
    Text, Actions);
end;

end.
