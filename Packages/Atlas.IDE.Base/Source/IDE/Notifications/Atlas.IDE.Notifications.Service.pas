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
  mService: TAtlasIdeNotifications;
begin
  inherited Create(AOwner);
  FInstance := Self;
  FCheckErrors := TDictionary<string, Integer>.Create;
  mService := Self;
  FListener := TAtlasNotificationCenter.Default.AddListener(
    procedure
    begin
      // Aus jedem Thread: gesammelt einmal im Hauptthread nachführen.
      if AtomicExchange(mService.FPending, 1) <> 0 then
      begin
        Exit;
      end;
      TAtlasMainThread.ForceQueue(TAtlasFeature.Notifications,
        procedure
        begin
          if FInstance <> mService then
          begin
            Exit;
          end;
          AtomicExchange(mService.FPending, 0);
          mService.Refresh;
        end);
    end);
  ApplySettings;
end;

destructor TAtlasIdeNotifications.Destroy;
begin
  // Erst abmelden, dann freigeben (#493).
  TAtlasNotificationCenter.Default.RemoveListener(FListener);
  if FInstance = Self then
  begin
    FInstance := nil;
  end;
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
  begin
    FWindow := nil;
  end;
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
  begin
    FInstance.Show;
  end;
end;

class procedure TAtlasIdeNotifications.SaveMode(const ASource: string; AMode: TAtlasNotificationMode);
var
  mStored: TAtlasPluginSettings;
begin
  mStored := TAtlasIdeSettings.Stored;
  mStored.NotificationsSources := TAtlasNotificationSources.WithMode(mStored.NotificationsSources, ASource, AMode);
  TAtlasIdeSettings.Update(mStored);
end;

procedure TAtlasIdeNotifications.ApplySettings;
var
  mSettings: TAtlasPluginSettings;
  mCenter: TAtlasNotificationCenter;
begin
  mSettings := TAtlasIdeSettings.Current;
  mCenter := TAtlasNotificationCenter.DefaultCenter;
  mCenter.SetMaxEntries(mSettings.NotificationsMaxEntries);
  mCenter.ApplyModes(mSettings.NotificationsSources);
  mCenter.Enabled := Active;
  if not mCenter.Enabled then
  begin
    FCheckErrors.Clear;
    if FWindow <> nil then
    begin
      FWindow.Dismiss;
    end;
  end;
  Changed;
end;

procedure TAtlasIdeNotifications.Changed;
begin
  TAtlasGuard.Run(TAtlasFeature.Notifications, Refresh);
end;

procedure TAtlasIdeNotifications.Refresh;
var
  mCenter: IAtlasNotificationCenter;
  mWorst: TAtlasNotificationSeverity;
  mUnread: Integer;
begin
  mCenter := TAtlasNotificationCenter.Default;
  mUnread := 0;
  mWorst := TAtlasNotificationSeverity.Info;
  if Active and mCenter.WorstUnread(mWorst) then
  begin
    mUnread := mCenter.UnreadCount;
  end;
  if Assigned(FOnBadge) then
  begin
    FOnBadge(mUnread, mWorst);
  end;
  if FWindow <> nil then
  begin
    FWindow.Reload;
  end;
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
  begin
    Exit;
  end;
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
  mAnchor: TPoint;
  mArea: TRect;
begin
  mAnchor := Point(MaxInt, MaxInt);
  if Assigned(FOnAnchor) then
  begin
    mAnchor := FOnAnchor();
  end;
  if mAnchor.X = MaxInt then
  begin
    // Ohne Statusfeld: unten links im aktiven Fenster.
    if Screen.ActiveForm <> nil then
    begin
      mArea := Screen.ActiveForm.BoundsRect;
    end
    else if Application.MainForm <> nil then
    begin
      mArea := Application.MainForm.BoundsRect;
    end
    else
    begin
      mArea := Screen.WorkAreaRect;
    end;
    mAnchor := Point(mArea.Left + 40, mArea.Bottom - 40);
  end;
  Show(mAnchor);
end;

procedure TAtlasIdeNotifications.BuildFinished(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; ASucceeded, AReadable: Boolean);
var
  mNotice: TAtlasBuildNotice;
  mPrevious: Integer;
  mKey: string;
begin
  if not Active then
  begin
    Exit;
  end;
  mKey := LowerCase(AProject.FileName);
  mPrevious := -1;
  if AProject.Background and not FCheckErrors.TryGetValue(mKey, mPrevious) then
  begin
    mPrevious := -1;
  end;
  mNotice := TAtlasBuildNotices.FromRun(AMessages, ASucceeded, AReadable, AProject.Background, mPrevious);
  if AProject.Background and AReadable then
  begin
    FCheckErrors.AddOrSetValue(mKey, mNotice.Errors);
  end;
  Post(mNotice, AProject);
end;

procedure TAtlasIdeNotifications.BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict);
begin
  if Active then
  begin
    Post(TAtlasBuildNotices.FromVerdict(AMessages, AVerdict), AProject);
  end;
end;

procedure TAtlasIdeNotifications.Post(const ANotice: TAtlasBuildNotice; const AProject: TAtlasCompileProject);
var
  mNotice: TAtlasBuildNotice;
  mProject, mTitle, mText, mAction: string;
  mActions: TArray<TAtlasNotificationAction>;
  mTarget: TAtlasCompilerMessage;
begin
  mNotice := ANotice;
  mProject := ChangeFileExt(ExtractFileName(AProject.FileName), '');
  mAction := TAtlasStrings.Text(TAtlasTextId.NotificationsGoToError);
  case mNotice.Kind of
    TAtlasBuildNoticeKind.Errors:
      mTitle := TAtlasStrings.Fmt(TAtlasTextId.NotificationsBuildErrors, [mNotice.Errors]);
    TAtlasBuildNoticeKind.Warnings:
      mTitle := TAtlasStrings.Fmt(TAtlasTextId.NotificationsBuildWarnings, [mNotice.Warnings]);
    TAtlasBuildNoticeKind.Succeeded:
      mTitle := TAtlasStrings.Text(TAtlasTextId.NotificationsBuildSucceeded);
    TAtlasBuildNoticeKind.Failed:
      mTitle := TAtlasStrings.Text(TAtlasTextId.NotificationsBuildFailed);
    TAtlasBuildNoticeKind.CheckErrors:
      mTitle := TAtlasStrings.Fmt(TAtlasTextId.NotificationsCheckErrors, [mNotice.Errors]);
    TAtlasBuildNoticeKind.CheckClean:
      mTitle := TAtlasStrings.Text(TAtlasTextId.NotificationsCheckClean);
    TAtlasBuildNoticeKind.Rejected:
      begin
        if mNotice.Reason = TAtlasBuildVerdictReason.WarningsAsErrors then
        begin
          mTitle := TAtlasStrings.Fmt(TAtlasTextId.NotificationsBuildRejectedCodes, [mNotice.PromotedCode]);
        end
        else
        begin
          mTitle := TAtlasStrings.Text(TAtlasTextId.NotificationsBuildRejected);
        end;
        mAction := TAtlasStrings.Text(TAtlasTextId.NotificationsGoToMessage);
      end;
  else
    Exit;
  end;
  mText := TAtlasStrings.Fmt(TAtlasTextId.NotificationsBuildText, [mProject, mNotice.Errors, mNotice.Warnings,
    mNotice.Hints]);
  if mNotice.Baselined > 0 then
  begin
    mText := mText + ' ' + TAtlasStrings.Fmt(TAtlasTextId.NotificationsBuildBaselined, [mNotice.Baselined]);
  end;
  mActions := nil;
  if mNotice.HasTarget then
  begin
    mTarget := mNotice.Target;
    mText := mText + ' · ' + Format('%s(%d): %s', [ExtractFileName(mTarget.FileName), mTarget.Line, mTarget.Text]);
    mActions := [TAtlasNotificationCenter.Action(mAction,
      procedure
      begin
        // Meldungen zählen ab 1, der Editor ab 0.
        TAtlasIdeNavigation.GoToLocation(mTarget.FileName, Max(0, mTarget.Line - 1), Max(0, mTarget.Column - 1));
      end)];
  end;
  TAtlasNotificationCenter.Default.Notify(TAtlasBuildNotices.SourceOf(AProject.Background), mNotice.Severity, mTitle,
    mText, mActions);
end;

end.
