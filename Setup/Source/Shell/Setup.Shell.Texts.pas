unit Setup.Shell.Texts;

// Installer (#495): Texte der Oberfläche auf Deutsch und Englisch, je nach
// Sprache der Windows-Oberfläche (die Shell setzt TSetupTexts.Language).
// Ohne Windows und VCL, damit die Tests jeden Text und jeden Schritt prüfen.

interface

uses
  System.SysUtils,
  Setup.Core.Ides,
  Setup.Core.Installer;

type
{$SCOPEDENUMS ON}
  TSetupLanguage = (German, English);
  TSetupTextId = (Title, UninstallTitle, IdesLabel, NoIdes, TargetLabel, InstalledVersion, InstallButton,
    UpdateButton, UninstallButton, CloseButton, NothingSelected, Running, InstallDone, UninstallDone, Aborted,
    DataLabel, DataSettings, DataIndex, DataSnippets, ConfirmUninstall, StateInstalled, StateUnsupported,
    StatePackageMissing, StepFileCopied, StepRegistered, StepRegistrationRemoved, StepUninstallEntryWritten,
    StepUninstallEntryRemoved, StepFilesRemoved, StepFilesRemovedLater, StepDataRemoved, StepFailed);
{$SCOPEDENUMS OFF}

  TSetupTexts = class
  private
    class var FLanguage: TSetupLanguage;
  public
    class function Get(AId: TSetupTextId): string; static;
    class function Fmt(AId: TSetupTextId; const AArgs: array of const): string; static;
    /// <summary>Eine Zeile je IDE in der Auswahl, mit Grund, wenn sie nicht angeboten wird.</summary>
    class function IdeCaption(const AIde: TSetupIde): string; static;
    /// <summary>Eine Protokollzeile je Schritt des Installers.</summary>
    class function StepText(const AStep: TSetupStep): string; static;
    class function DataName(AData: TSetupData): string; static;
    class property Language: TSetupLanguage read FLanguage write FLanguage;
  end;

implementation

const
  German: array[TSetupTextId] of string = (
    'Atlas IDE Expert %s – Installation',
    'Atlas IDE Expert – Deinstallation',
    'Atlas für diese Delphi-Versionen einrichten:',
    'Keine Delphi-Installation gefunden.',
    'Zielordner: %s',
    'Installiert: Version %s',
    'Installieren',
    'Aktualisieren',
    'Entfernen',
    'Schließen',
    'Bitte mindestens eine Delphi-Version auswählen.',
    'Bitte zuerst diese IDE schließen:%s%s%s„Wiederholen“, wenn sie geschlossen ist.',
    'Fertig. Atlas wird beim nächsten Start der IDE geladen.',
    'Atlas wurde entfernt.',
    'Abgebrochen. Die Ursache steht oben.',
    'Zusätzlich entfernen (sonst bleiben sie erhalten):',
    'Einstellungen',
    'Index und Protokolle',
    'Eigene Snippets',
    'Atlas aus allen Delphi-Versionen entfernen?',
    'installiert',
    'nicht unterstützt',
    'Paket fehlt im Download',
    'Kopiert: %s',
    'Registriert in %s',
    'Registrierung entfernt: %s',
    'Eintrag unter „Apps und Features“ angelegt',
    'Eintrag unter „Apps und Features“ entfernt',
    'Programmdateien entfernt: %s',
    'Programmordner wird nach dem Beenden entfernt: %s',
    'Entfernt: %s',
    'Fehler: %s');
  English: array[TSetupTextId] of string = (
    'Atlas IDE Expert %s Setup',
    'Atlas IDE Expert Uninstall',
    'Set up Atlas for these Delphi versions:',
    'No Delphi installation found.',
    'Target folder: %s',
    'Installed: version %s',
    'Install',
    'Update',
    'Remove',
    'Close',
    'Please select at least one Delphi version.',
    'Please close this IDE first:%s%s%sChoose "Retry" once it is closed.',
    'Done. Atlas is loaded the next time the IDE starts.',
    'Atlas has been removed.',
    'Cancelled. The cause is shown above.',
    'Also remove (kept otherwise):',
    'Settings',
    'Index and logs',
    'Own snippets',
    'Remove Atlas from all Delphi versions?',
    'installed',
    'not supported',
    'package missing from download',
    'Copied: %s',
    'Registered in %s',
    'Registration removed: %s',
    'Entry under "Apps & features" created',
    'Entry under "Apps & features" removed',
    'Program files removed: %s',
    'Program folder is removed after exit: %s',
    'Removed: %s',
    'Error: %s');

{ TSetupTexts }

class function TSetupTexts.Get(AId: TSetupTextId): string;
begin
  if FLanguage = TSetupLanguage.German then
    Result := German[AId]
  else
    Result := English[AId];
end;

class function TSetupTexts.Fmt(AId: TSetupTextId; const AArgs: array of const): string;
begin
  Result := Format(Get(AId), AArgs);
end;

class function TSetupTexts.IdeCaption(const AIde: TSetupIde): string;
begin
  Result := AIde.Info.ProductName + ' (' + TSetupIdes.PlatformFolder(AIde.Platform) + ')';
  case AIde.Unavailable of
    TSetupUnavailable.VersionUnsupported:
      Result := Result + ' – ' + Get(TSetupTextId.StateUnsupported);
    TSetupUnavailable.PackageMissing:
      Result := Result + ' – ' + Get(TSetupTextId.StatePackageMissing);
  else
    if AIde.Installed then
      Result := Result + ' – ' + Get(TSetupTextId.StateInstalled);
  end;
end;

class function TSetupTexts.DataName(AData: TSetupData): string;
begin
  case AData of
    TSetupData.Settings:
      Result := Get(TSetupTextId.DataSettings);
    TSetupData.IndexAndLogs:
      Result := Get(TSetupTextId.DataIndex);
  else
    Result := Get(TSetupTextId.DataSnippets);
  end;
end;

class function TSetupTexts.StepText(const AStep: TSetupStep): string;
const
  Ids: array[TSetupStepKind] of TSetupTextId = (TSetupTextId.StepFileCopied, TSetupTextId.StepRegistered,
    TSetupTextId.StepRegistrationRemoved, TSetupTextId.StepUninstallEntryWritten,
    TSetupTextId.StepUninstallEntryRemoved, TSetupTextId.StepFilesRemoved, TSetupTextId.StepFilesRemovedLater,
    TSetupTextId.StepDataRemoved, TSetupTextId.StepFailed);
var
  Data: TSetupData;
  Subject: string;
begin
  Subject := AStep.Subject;
  // Der Kern meldet entfernte Daten mit dem Namen der Aufzählung.
  if AStep.Kind = TSetupStepKind.DataRemoved then
    for Data := Low(TSetupData) to High(TSetupData) do
      if SameText(Subject, TSetupInstaller.DataId(Data)) then
        Subject := DataName(Data);
  Result := Format(Get(Ids[AStep.Kind]), [Subject]);
end;

end.
