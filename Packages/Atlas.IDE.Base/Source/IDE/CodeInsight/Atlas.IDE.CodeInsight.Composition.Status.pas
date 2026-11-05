unit Atlas.IDE.CodeInsight.Composition.Status;

// Atlas-Statusfeld mit seinen Zeilen (#591), Fenster „Atlas-Server“ (#1356), Fehlerzähler (#509),
// Benachrichtigungszentrale (#601) mit Plakette und Einträgen der Sicherung (#493, Bericht M4) und die
// Schnellschalter (#604) am Feld. Immer angemeldet, auch im abgesicherten Start (#722).

interface

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Status.Field,
  Atlas.IDE.Status.Lines,
  Atlas.IDE.Settings.QuickToggles,
  Atlas.IDE.Notifications.Service;

/// <summary>Atlas-Statusfeld; nil vor RegisterStatusField und nach UnregisterStatusField.</summary>
function StatusField: TAtlasStatusField;
/// <summary>Zeilen des Statusfelds; nil ohne Statusfeld.</summary>
function StatusLines: TAtlasIdeStatusLines;
/// <summary>Benachrichtigungszentrale; nil vor StartNotifications.</summary>
function Notifications: TAtlasIdeNotifications;
/// <summary>Schnellschalter; nil vor StartQuickToggles.</summary>
function QuickToggles: TAtlasIdeQuickToggles;
/// <summary>Statusfeld, Zeilen, Fenster „Atlas-Server“ und Fehlerzähler anmelden.</summary>
procedure RegisterStatusField;
/// <summary>Fenster „Atlas-Server“, Fehlerzähler, Statusfeld und Zeilen abbauen.</summary>
procedure UnregisterStatusField;
/// <summary>Benachrichtigungszentrale (#601): immer, auch abgesichert; an oder aus nach notifications.enabled.
/// </summary>
procedure StartNotifications;
/// <summary>Zentrale und ihre Einträge freigeben; vor dem Statusfeld (die Einträge halten Aktionen, #601).</summary>
procedure StopNotifications;
/// <summary>Schnellschalter (#604) am Statusfeld anlegen.</summary>
procedure StartQuickToggles;
procedure StopQuickToggles;
/// <summary>Statusfeld neu zeichnen lassen (gesammelt, aus jedem Thread).</summary>
procedure RequestStatusRefresh;
/// <summary>Zusatzfeld im Statusfeld setzen; ohne Feld nichts.</summary>
procedure SetStatusExtra(const AId, AText, AHint: string; const AOnClick: TProc<TPoint>);
/// <summary>Letzte Antwort von atlas.server.status; '' ohne Zeilen.</summary>
function StatusJson: string;
/// <summary>Fenster „Atlas-Server“ (#1356) zeigen; abgeschaltet nichts.</summary>
procedure ShowServerWindow;
/// <summary>Ausgelöste Sicherung (#493) als Eintrag in der Benachrichtigungszentrale mit „Wieder einschalten“ und
/// „Protokoll öffnen“ (atlas.log mit Stacktrace): Der Fehler soll auffallen und behoben werden, statt still eine
/// Funktion zu kosten. Aus jedem Thread; die Aktionen laufen im Hauptthread.</summary>
procedure GuardTripped(AFeature: TAtlasFeature; const AMessage: string);
/// <summary>Atlas-Protokoll gestört (Bericht M4), aus dem Thread des Schreibers: über OutputDebugString (DebugView
/// zeigt es, auch wenn atlas.log nichts mehr annimmt) und als Benachrichtigung; '' = schreibt wieder.</summary>
procedure LogError(const AMessage: string);

implementation

uses
  Winapi.Windows,
  System.JSON,
  Atlas.UI.Strings,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Status.Lines,
  Atlas.Core.Status.Server,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Problems.InlineHints,
  Atlas.IDE.Problems.RuleActions,
  Atlas.IDE.Status.ServerWindow,
  Atlas.IDE.StatusBar.Service,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Problems.Service,
  Atlas.IDE.Problems.MessageList,
  Atlas.IDE.Diagnostics.ServerPackage,
  Atlas.IDE.CodeInsight.Composition.Session;

const
  cProblemCountsExtra = 'problemCounts';

var
  // Atlas-Statusfeld mit Server, Index und Datei (#591).
  StatusFieldInstance: TAtlasStatusField;
  StatusLinesInstance: TAtlasIdeStatusLines;
  // Benachrichtigungszentrale mit Liste, Plakette im Statusfeld und Build-Einträgen (#601).
  NotificationsInstance: TAtlasIdeNotifications;
  // Schnellschalter mit Fenster, Taste und Befehlen in der Palette (#604).
  QuickTogglesInstance: TAtlasIdeQuickToggles;

function StatusField: TAtlasStatusField;
begin
  Result := StatusFieldInstance;
end;

function StatusLines: TAtlasIdeStatusLines;
begin
  Result := StatusLinesInstance;
end;

function Notifications: TAtlasIdeNotifications;
begin
  Result := NotificationsInstance;
end;

function QuickToggles: TAtlasIdeQuickToggles;
begin
  Result := QuickTogglesInstance;
end;

procedure RequestStatusRefresh;
begin
  if StatusFieldInstance <> nil then
  begin
    StatusFieldInstance.RequestRefresh;
  end;
end;

procedure SetStatusExtra(const AId, AText, AHint: string; const AOnClick: TProc<TPoint>);
begin
  if StatusFieldInstance <> nil then
  begin
    StatusFieldInstance.SetExtra(AId, AText, AHint, AOnClick);
  end;
end;

function StatusJson: string;
begin
  Result := '';
  if StatusLinesInstance <> nil then
  begin
    Result := StatusLinesInstance.StatusJson;
  end;
end;

/// <summary>Punkt unter dem Statusfeld für Fenster am Feld; ohne Feld weit außerhalb.</summary>
function StatusAnchor: TPoint;
begin
  if (StatusFieldInstance = nil) or not StatusFieldInstance.Anchor(Result) then
  begin
    Result := Point(MaxInt, MaxInt);
  end;
end;

procedure ShowServerWindow;
begin
  TAtlasIdeServerWindow.Show;
end;

/// <summary>Diagnosepaket des Fensters „Atlas-Server“ (#1356): Bericht und Dateien des laufenden Servers im
/// Hintergrund.</summary>
procedure CreateServerPackage;
begin
  TAtlasIdeServerPackage.Execute(
    procedure(const ACommand, AArgumentsJson: string; const ADone: TProc<TJSONValue>)
    begin
      RunServerCommand(ACommand, AArgumentsJson, 30000, ADone);
    end,
    Warnings());
end;

/// <summary>„Index neu aufbauen“ im Fenster „Atlas-Server“; ohne Manager nichts.</summary>
procedure RebuildIndex;
begin
  if Manager = nil then
  begin
    Exit;
  end;
  Manager.ExecuteServerCommandAsync('atlas.server.rebuildIndex', 30000,
    procedure(AAnswer: TJSONValue)
    begin
      if AAnswer = nil then
      begin
        GuardWarning(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
      end
      else
      begin
        GuardWarning(TAtlasStrings.Text(TAtlasTextId.MenuIndexRebuilding));
      end;
    end);
end;

/// <summary>Abfragen des Fensters „Atlas-Server“: liest die Antwort der Statuszeilen, fragt selbst nicht ab.
/// </summary>
procedure ServerWindowQueries(var AHooks: TAtlasIdeServerWindow.THooks);
begin
  AHooks.StatusJson := StatusJson;
  AHooks.Running :=
    function: Boolean
    begin
      Result := (Manager <> nil) and (Manager.ServerInfo.Phase = TAtlasServerPhase.Running);
    end;
  AHooks.Restarts :=
    function: Integer
    begin
      Result := 0;
      if Manager <> nil then
      begin
        Result := Manager.ServerRestarts;
      end;
    end;
  AHooks.QueryNow :=
    function(ADone: TProc): Boolean
    begin
      Result := (StatusLinesInstance <> nil) and StatusLinesInstance.QueryNow(ADone);
    end;
end;

/// <summary>Fenster „Atlas-Server“ (#1356) mit seinen Haken anmelden.</summary>
procedure InstallServerWindow;
var
  mHooks: TAtlasIdeServerWindow.THooks;
begin
  mHooks := Default(TAtlasIdeServerWindow.THooks);
  ServerWindowQueries(mHooks);
  mHooks.Rebuild := RebuildIndex;
  mHooks.Package := CreateServerPackage;
  mHooks.OpenUnit :=
    procedure(AUnit: TAtlasServerSlowUnit)
    begin
      // Ohne Pfad (ältere Antwort) oder gelöscht: nichts zu öffnen.
      OpenInEditor(AUnit.FileName);
    end;
  mHooks.OpenRule :=
    procedure(ARule: string)
    begin
      // Regel einstellen über das Modul Prüfregeln (#1755); ohne Modul nichts.
      TAtlasRuleActions.Configure(ARule);
    end;
  TAtlasIdeServerWindow.Install(mHooks);
end;

/// <summary>Klick auf den Fehlerzähler: mit dem Fenster „Atlas-Prüfung“ (#909) dorthin, sonst in die Liste.
/// </summary>
procedure ShowProblems;
begin
  if TAtlasIdeProblems.Enabled then
  begin
    TAtlasIdeProblems.ShowWindow;
  end
  else
  begin
    TAtlasProblemsList.ShowList;
  end;
end;

/// <summary>Fehlerzähler (#509) als Zusatzfeld des Statusfelds; ohne AShow ausgeblendet.</summary>
procedure ShowProblemCounts(AShow: Boolean; const ACounts: TAtlasProblemCounts);
begin
  if StatusFieldInstance = nil then
  begin
    Exit;
  end;
  if not AShow then
  begin
    StatusFieldInstance.SetExtra(cProblemCountsExtra, '', '', nil);
    Exit;
  end;
  StatusFieldInstance.SetExtra(cProblemCountsExtra, TAtlasStrings.Fmt(TAtlasTextId.ProblemCounterText,
    [ACounts.Errors, ACounts.Warnings, ACounts.Hints]), TAtlasStrings.Fmt(TAtlasTextId.ProblemCounterHint,
    [ACounts.Errors, ACounts.Warnings, ACounts.Hints]),
    procedure(APoint: TPoint)
    begin
      ShowProblems;
    end);
end;

/// <summary>Zeilen des Statusfelds; Klick auf die Zeile „Server“ öffnet das Fenster „Atlas-Server“ (#1356), nur
/// mit server.statusWindow.</summary>
procedure CreateStatusLines;
var
  mSources: TAtlasStatusLineSources;
begin
  mSources.ServerInfo := ServerInfo;
  mSources.Indexing := ServerIndexing;
  mSources.Query :=
    function(const ADone: TProc<string>): Boolean
    begin
      Result := (Manager <> nil) and Manager.QueryStatusAsync(ADone);
    end;
  mSources.Report := Warnings();
  mSources.ServerAction := ShowServerWindow;
  mSources.ServerActionEnabled :=
    function: Boolean
    begin
      Result := TAtlasIdeServerWindow.Enabled;
    end;
  StatusLinesInstance := TAtlasIdeStatusLines.Create(TAtlasStatusRegistry.Default, mSources);
end;

/// <summary>Atlas-Statusfeld mit Aktualisieren, Protokoll, Schnellschaltern und Neustart des Servers.</summary>
procedure CreateStatusField;
begin
  StatusFieldInstance := TAtlasStatusField.Create(TAtlasStatusRegistry.Default);
  StatusFieldInstance.OnRefresh :=
    procedure
    begin
      if StatusLinesInstance <> nil then
      begin
        StatusLinesInstance.Refresh;
      end;
    end;
  StatusFieldInstance.OnOpenLog := OpenLog;
  // Zeigt die Atlas-Statusleiste das Element status, öffnen Statusfenster und Schnellschalter dort (#1155).
  StatusFieldInstance.OnRelocatedAnchor := TAtlasIdeStatusBar.Anchor;
  // Rechtsklick auf das Feld: Schnellschalter (#604).
  StatusFieldInstance.OnContext :=
    procedure(APoint: TPoint)
    begin
      if QuickTogglesInstance <> nil then
      begin
        QuickTogglesInstance.Show(APoint);
      end;
    end;
  StatusFieldInstance.OnRestart :=
    procedure
    begin
      if Manager <> nil then
      begin
        Manager.RestartServer;
      end;
    end;
end;

procedure RegisterStatusField;
begin
  CreateStatusLines;
  InstallServerWindow;
  CreateStatusField;
  // Fehlerzähler (#509) als Zusatzfeld; ein Klick öffnet die Liste „Atlas-Probleme“.
  TAtlasProblemsController.OnCounts := ShowProblemCounts;
end;

procedure UnregisterStatusField;
begin
  TAtlasIdeServerWindow.Release;
  TAtlasProblemsController.OnCounts := nil;
  if Manager <> nil then
  begin
    Manager.OnServerChanged := nil;
  end;
  FreeAndNil(StatusFieldInstance);
  FreeAndNil(StatusLinesInstance);
  TAtlasStatusRegistry.ReleaseDefault;
end;

/// <summary>Farbe der Plakette (#601): Info neutral, Warnung gelb, Fehler rot.</summary>
function BadgeState(ASeverity: TAtlasNotificationSeverity): TAtlasStatusState;
begin
  case ASeverity of
    TAtlasNotificationSeverity.Warning:
      Result := TAtlasStatusState.Yellow;
    TAtlasNotificationSeverity.Error:
      Result := TAtlasStatusState.Red;
  else
    Result := TAtlasStatusState.Neutral;
  end;
end;

/// <summary>Plakette der ungelesenen Benachrichtigungen am Statusfeld; ein Klick öffnet die Liste.</summary>
procedure ShowBadge(AUnread: Integer; AWorst: TAtlasNotificationSeverity);
begin
  if StatusFieldInstance = nil then
  begin
    Exit;
  end;
  StatusFieldInstance.SetBadge(AUnread, BadgeState(AWorst),
    TAtlasStrings.Fmt(TAtlasTextId.NotificationsBadgeHint, [AUnread]),
    procedure(APoint: TPoint)
    begin
      if NotificationsInstance <> nil then
      begin
        NotificationsInstance.Show(APoint);
      end;
    end);
end;

procedure StartNotifications;
begin
  NotificationsInstance := TAtlasIdeNotifications.Create(nil);
  NotificationsInstance.OnAnchor := StatusAnchor;
  NotificationsInstance.OnBadge := ShowBadge;
  // Erst jetzt erreicht die Plakette das Feld.
  NotificationsInstance.ApplySettings;
end;

procedure StopNotifications;
begin
  FreeAndNil(NotificationsInstance);
  TAtlasNotificationCenter.ReleaseDefault;
end;

procedure StartQuickToggles;
begin
  QuickTogglesInstance := TAtlasIdeQuickToggles.Create(nil);
  QuickTogglesInstance.OnAnchor := StatusAnchor;
end;

procedure StopQuickToggles;
begin
  FreeAndNil(QuickTogglesInstance);
end;

procedure GuardTripped(AFeature: TAtlasFeature; const AMessage: string);
var
  mFeature: TAtlasFeature;
  mEnable, mLog: TAtlasNotificationAction;
begin
  mFeature := AFeature;
  mEnable.Caption := TAtlasStrings.Text(TAtlasTextId.FuseTrippedEnable);
  mEnable.Run :=
    procedure
    begin
      TAtlasGuard.Enable(mFeature);
      TAtlasGuard.Log(TAtlasGuard.FeatureName(mFeature) + ': aus der Benachrichtigung wieder eingeschaltet');
    end;
  mLog.Caption := TAtlasStrings.Text(TAtlasTextId.FuseTrippedOpenLog);
  mLog.Run :=
    procedure
    begin
      if TAtlasGuard.RotatingLog <> nil then
      begin
        OpenInEditor(TAtlasGuard.RotatingLog.FileName);
      end;
    end;
  TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Fuse, TAtlasNotificationSeverity.Error,
    TAtlasStrings.Fmt(TAtlasTextId.FuseTrippedTitle, [TAtlasGuard.FeatureName(mFeature)]), AMessage,
    [mEnable, mLog]);
end;

procedure LogError(const AMessage: string);
var
  mReason, mText, mDetail: string;
begin
  if AMessage = '' then
  begin
    OutputDebugString(PChar('Atlas: Protokoll schreibt wieder'));
    Exit;
  end;
  mReason := TAtlasGuard.SafeMessage(AMessage);
  OutputDebugString(PChar('Atlas: Protokoll gestört: ' + mReason));
  mText := TAtlasStrings.Text(TAtlasTextId.LogBrokenTitle);
  mDetail := TAtlasStrings.Fmt(TAtlasTextId.LogBrokenText, [TAtlasGuard.RotatingLog.FileName, mReason]);
  if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Fuse, TAtlasNotificationSeverity.Warning,
    mText, mDetail) <> TAtlasNotificationMode.Show then
  begin
    Exit;
  end;
  mText := mText + ': ' + mDetail;
  TAtlasMainThread.Queue(TAtlasFeature.Status,
    procedure
    begin
      MessageLine(mText);
    end);
end;

end.
