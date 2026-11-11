unit Atlas.UI.Updates.Strings;

// Oberflächentexte der Update-Installation (#1519) auf Deutsch und Englisch:
// Optionsseite, Angebot, Auswahl der Module, Stand, Ergebnis und Fehlercodes
// von AtlasUpdate.exe sowie die Meldung einer gescheiterten Update-Prüfung.
// Die Sprache bestimmt TAtlasStrings.Language; die Texte der Update-Prüfung
// (#495) bleiben in Atlas.UI.Strings.

interface

{ ON}

type
  TAtlasUpdatesTextId = (
    SettingsUpdatesInstall, SettingsUpdatesInstallAsk, SettingsUpdatesInstallAuto, SettingsUpdatesInstallOff,
    SettingsUpdatesChannel, SettingsUpdatesChannelStable, SettingsUpdatesChannelPrerelease,
    SettingsUpdatesNewModules, SettingsUpdatesNewModulesAsk, SettingsUpdatesNewModulesInstall,
    SettingsUpdatesNewModulesSkip, UpdatesOfferTitle, UpdatesOfferText, UpdatesOfferMajor, UpdatesOfferInstall,
    UpdatesOfferChanges, UpdatesOfferLater, UpdatesReadyText, UpdatesReadyModules, UpdatesReadyDiscard,
    UpdatesStagePreparing, UpdatesStageBuilding, UpdatesStageReady, UpdatesStageChoose, UpdatesStageFailed,
    UpdatesPreparedMessage, UpdatesChooseMessage, UpdatesPrepareFailedMessage, UpdatesBlockedMessage,
    UpdatesBlockedGetIt, UpdatesBlockedNoUpdater, UpdatesBlockedFolder, UpdatesSelectionTitle, UpdatesSelectionText,
    UpdatesSelectionNew, UpdatesSelectionRequired, UpdatesSelectionApply, UpdatesSelectionCancel,
    UpdatesOutcomeInstalled, UpdatesOutcomeAdded, UpdatesOutcomeRemoved, UpdatesOutcomeRolledBack,
    UpdatesOutcomeCancelled, UpdatesOutcomeFailed, UpdatesErrorManifest, UpdatesErrorVersion, UpdatesErrorNoPackage,
    UpdatesErrorNoCompiler, UpdatesErrorDownload, UpdatesErrorHash, UpdatesErrorArchive, UpdatesErrorUnsigned,
    UpdatesErrorSignature, UpdatesErrorBuild, UpdatesErrorLocked, UpdatesErrorCopy, UpdatesErrorRegistry,
    UpdatesErrorCancelled, UpdatesErrorElevation, UpdatesErrorSelection, UpdatesErrorUnexpected, UpdatesErrorStart,
    UpdatesCheckFailedMessage);

  TAtlasUpdatesStrings = class
  public
    class function Text(AId: TAtlasUpdatesTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasUpdatesTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasUpdatesTextId] of string = (
    ( 'Updates installieren:',
     'anbieten',
     'ohne Frage vorbereiten',
     'nur melden',
     'Kanal:',
     'stabile Versionen',
     'auch Vorabversionen',
     'Neue Module:',
     'nachfragen',
     'mitinstallieren',
     'nicht installieren',
     'Atlas %s ist verfügbar',
     'Installiert ist Atlas %s. Atlas lädt das Update jetzt im Hintergrund und prüft es. Beim Schließen ' +
     'der IDE spielt ein Konsolenfenster es ein; beim nächsten Start meldet Atlas das Ergebnis.',
     'Neue Hauptversion: Bitte vorher die Änderungen lesen; Einstellungen und Module können sich geändert ' +
     'haben.',
     'Beim Beenden installieren',
     'Änderungen ansehen',
     'Später',
     'Atlas %s wird beim Schließen der IDE installiert.',
     'Module wählen …',
     'Nicht installieren',
     'wird vorbereitet (%d %%)',
     'wird aus dem Quelltext gebaut',
     'wird beim Beenden installiert',
     'bereit, Module wählen',
     'nicht vorbereitet',
     'Atlas %s ist geprüft und wird beim Schließen der IDE installiert.',
     'Atlas %s ist geprüft. Es enthält neue Module: Über „Jetzt aktualisieren“ wählen, was installiert ' +
     'wird.',
     'Atlas-Update %s nicht vorbereitet: %s. Download über %s',
     'Atlas-Update %s: %s Download über %s',
     'Atlas ist über GetIt installiert; Updates kommen über GetIt.',
     'AtlasUpdate.exe fehlt neben AtlasServer.exe; Atlas installiert das Update nicht selbst.',
     'Atlas läuft nicht aus einem Release-Ordner (Win32 bzw. Win64 unter dem Atlas-Ordner); Atlas ' +
     'installiert das Update nicht selbst.',
     'Module für Atlas %s',
     'Gewählte Module werden beim Schließen der IDE installiert bzw. aktualisiert, abgewählte entfernt. ' +
     'Kern und Verträge gehören immer dazu.',
     '%s (neu)',
     '%s (immer)',
     'Übernehmen',
     'Abbrechen',
     'Atlas %s installiert (vorher %s).',
     'Neu installiert: %s',
     'Entfernt: %s',
     'Atlas-Update %s zurückgenommen: %s. Die bisherige Version ist unverändert installiert. Protokoll: %s',
     'Atlas-Update %s abgebrochen; nichts wurde geändert.',
     'Atlas-Update %s nicht eingespielt: %s. Protokoll: %s',
     'Versionsdatei ungültig',
     'die Versionsdatei nennt inzwischen eine andere Version',
     'kein Paket für diese IDE',
     'kein Delphi-Compiler zum Bauen aus dem Quelltext gefunden',
     'Download fehlgeschlagen',
     'Prüfsumme stimmt nicht',
     'Archiv unbrauchbar',
     'Datei nicht signiert',
     'Signatur ungültig oder von einem anderen Herausgeber',
     'Bauen aus dem Quelltext fehlgeschlagen',
     'Datei gesperrt',
     'Kopieren fehlgeschlagen',
     'Registry nicht geschrieben',
     'abgebrochen',
     'der Atlas-Ordner ist nicht beschreibbar; Atlas besser unter AppData\Local\Programs\Atlas ' +
     'installieren',
     'Modulauswahl ungültig',
     'unerwarteter Fehler',
     'AtlasUpdate.exe nicht gestartet',
     'Atlas-Update-Prüfung fehlgeschlagen (%s). Ob es eine neuere Version gibt, ist unbekannt; Atlas versucht ' +
     'es beim nächsten Start der IDE wieder, frühestens in einer Stunde. Releases: %s'),
    ( 'Install updates:',
     'offer',
     'prepare without asking',
     'notify only',
     'Channel:',
     'stable releases',
     'include pre-releases',
     'New modules:',
     'ask',
     'install',
     'skip',
     'Atlas %s is available',
     'Atlas %s is installed. Atlas downloads and verifies the update in the background now. When the IDE ' +
     'closes, a console window applies it; Atlas reports the result on the next start.',
     'New major version: please read the changes first; settings and modules may have changed.',
     'Install on exit',
     'View changes',
     'Later',
     'Atlas %s will be installed when the IDE closes.',
     'Choose modules …',
     'Do not install',
     'being prepared (%d %%)',
     'being built from source',
     'will be installed on exit',
     'ready, choose modules',
     'not prepared',
     'Atlas %s has been verified and will be installed when the IDE closes.',
     'Atlas %s has been verified. It contains new modules: choose what to install via “Update now”.',
     'Atlas update %s not prepared: %s. Download via %s',
     'Atlas update %s: %s Download via %s',
     'Atlas was installed via GetIt; updates come through GetIt.',
     'AtlasUpdate.exe is missing next to AtlasServer.exe; Atlas does not install the update itself.',
     'Atlas is not running from a release folder (Win32 or Win64 below the Atlas folder); Atlas does not ' +
     'install the update itself.',
     'Modules for Atlas %s',
     'Selected modules are installed or updated when the IDE closes, deselected ones are removed. Core ' +
     'and contracts are always included.',
     '%s (new)',
     '%s (always)',
     'Apply',
     'Cancel',
     'Atlas %s installed (previously %s).',
     'Newly installed: %s',
     'Removed: %s',
     'Atlas update %s rolled back: %s. The previous version is still installed. Log: %s',
     'Atlas update %s cancelled; nothing was changed.',
     'Atlas update %s not applied: %s. Log: %s',
     'version file invalid',
     'the version file now names another version',
     'no package for this IDE',
     'no Delphi compiler found to build from source',
     'download failed',
     'checksum does not match',
     'archive unusable',
     'file not signed',
     'signature invalid or from another publisher',
     'building from source failed',
     'file locked',
     'copying failed',
     'registry not written',
     'cancelled',
     'the Atlas folder is not writable; better install Atlas below AppData\Local\Programs\Atlas',
     'module selection invalid',
     'unexpected error',
     'AtlasUpdate.exe not started',
     'Atlas update check failed (%s). Whether a newer version exists is unknown; Atlas tries again at the ' +
     'next IDE start, after one hour at the earliest. Releases: %s'));

{ TAtlasUpdatesStrings }

class function TAtlasUpdatesStrings.Text(AId: TAtlasUpdatesTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasUpdatesStrings.Fmt(AId: TAtlasUpdatesTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
