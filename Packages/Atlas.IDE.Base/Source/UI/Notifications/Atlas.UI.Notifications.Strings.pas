unit Atlas.UI.Notifications.Strings;

// Oberflächentexte des Features Benachrichtigungen auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasNotificationsTextId = (
    NotificationsUnread, NotificationsEmpty, NotificationsAllRead, NotificationsClear, NotificationsFilterAll,
    NotificationsMarkRead, NotificationsModeMenu, NotificationsSourceBuild, NotificationsSourceCheck,
    NotificationsSourceReload, NotificationsSourceServer, NotificationsSourceShortcutTips, NotificationsBuildErrors,
    NotificationsBuildWarnings, NotificationsBuildSucceeded, NotificationsBuildFailed, NotificationsBuildText,
    NotificationsCheckErrors, NotificationsCheckClean, NotificationsGoToError, NotificationsSourceBuildServer,
    NotificationsSourceOpenBuild, NotificationsSourceHidden, NotificationsBuildRejected,
    NotificationsBuildRejectedCodes, NotificationsGoToMessage, NotificationsBuildBaselined,
    NotificationsSourceIssues, NotificationsSourceRuleChecks);

  TAtlasNotificationsStrings = class
  public
    class function Text(AId: TAtlasNotificationsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasNotificationsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasNotificationsTextId] of string = (
    ('%d ungelesen',
     'Keine Benachrichtigungen',
     'Alle gelesen',
     'Liste leeren',
     'Alle Quellen',
     'Als gelesen markieren',
     'Hinweise von „%s“',
     'Build fertig',
     'Prüfung im Hintergrund',
     'Dateien neu geladen',
     'Server',
     'Tastenkürzel-Tipps',
     'Build fertig: %d Fehler',
     'Build fertig: %d Warnungen',
     'Build fertig',
     'Build fehlgeschlagen',
     '%s: %d Fehler, %d Warnungen, %d Hinweise',
     'Prüfung: %d Fehler',
     'Prüfung: wieder fehlerfrei',
     'Zum Fehler',
     'Build-Server',
     'Bauen beim Öffnen',
     'Ausblenden am Element',
     'Build gilt als gescheitert (build.zeroHints)',
     'Build gilt als gescheitert: %s zählt als Fehler',
     'Zur Meldung',
     '(%d in der Basislinie)',
     'Issues',
     'Prüfregeln aus'),
    ('%d unread',
     'No notifications',
     'Mark all read',
     'Clear list',
     'All sources',
     'Mark as read',
     'Notices from “%s”',
     'Build finished',
     'Background check',
     'Files reloaded',
     'Server',
     'Keyboard shortcut tips',
     'Build finished: %d errors',
     'Build finished: %d warnings',
     'Build finished',
     'Build failed',
     '%s: %d errors, %d warnings, %d hints',
     'Check: %d errors',
     'Check: no errors again',
     'Go to error',
     'Build server',
     'Build on opening',
     'Hiding at the element',
     'Build counts as failed (build.zeroHints)',
     'Build counts as failed: %s counts as an error',
     'Go to message',
     '(%d in the baseline)',
     'Issues',
     'Rule checks off'));

{ TAtlasNotificationsStrings }

class function TAtlasNotificationsStrings.Text(AId: TAtlasNotificationsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasNotificationsStrings.Fmt(AId: TAtlasNotificationsTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
