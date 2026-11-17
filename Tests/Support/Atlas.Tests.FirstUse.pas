unit Atlas.Tests.FirstUse;

// Bekannte Einmal-Belegungen des Testlaufs an einer Stelle. Der Leckmonitor misst je Test, was netto belegt
// bleibt; was beim ersten Gebrauch entsteht, bis zum Programmende lebt und dort freigegeben wird (gemeinsame
// Kataloge, Ressourcentexte der RTL, Zwischenspeicher), sähe für ihn wie ein Leck des ersten Tests aus, der es
// benutzt. TFirstUse.WarmUp legt es deshalb einmal vor dem ersten Test an (RegisterLeakMonitor).
//
// Jeder Eintrag nennt seinen Besitzer und, wo er freigegeben wird. Ob das stimmt, prüft der Speicherrest beim
// Beenden (TShutdownLeaks.Expect in Atlas.Tests.dpr): Was hier angelegt und nie freigegeben wird, lässt den
// Debug-Lauf scheitern. Neue Einträge gehören hierher statt in ein [SetupFixture] einer Testklasse, das den
// eigenen Test einmal ungemessen vorweg laufen lässt; dort bliebe ungenannt, was belegt wird.

interface

type
  TFirstUse = class
  public
    /// <summary>Einmal vor dem ersten Test: legt an, was bis zum Programmende lebt und dort freigegeben wird.
    /// Ein zweiter Aufruf belegt nichts mehr.</summary>
    class procedure WarmUp; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  System.JSON,
  System.Generics.Collections,
  System.Messaging,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Metrics.DuplicateCatalog,
  Atlas.Common.Rules.Catalog,
  Atlas.Core.Diagnostics.WorkerSlot,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Transfer,
  Atlas.UI.Foundation.Theme,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.Section,
  Atlas.UI.Settings.Page,
  Vcl.Forms,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Settings.Keys,
  Atlas.UI.Settings.Overview,
  Atlas.Common.Projects.PackageLocator,
  Atlas.Windows.Diagnostics.StackTrace;

/// <summary>Katalog, Export und Import der Einstellungen (#723) einmal durchlaufen: Was dabei beim ersten
/// Gebrauch bleibt, träfe sonst je nach Reihenfolge einen anderen Test als Leck.</summary>
procedure WarmUpSettingsTransfer;
var
  mCatalog: TAtlasSettingsCatalog;
  mState: TAtlasSettingsState;
  mExported: TAtlasExportResult;
  mEnvironment: TAtlasSettingsEnvironment;
  mIndex: Integer;
begin
  mEnvironment :=
    function(const AName: string): string
    begin
      Result := '';
    end;
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  try
    mState := TAtlasSettingsState.Create(TAtlasPluginSettings.Defaults, '');
    // Gemeinsamer Speicher mit allen Standardwerten (DefaultValues): entsteht beim ersten DefaultJson.
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      TAtlasSettingsTransfer.DefaultJson(mCatalog, mIndex);
    end;
    mExported := TAtlasSettingsTransfer.ExportSettings(mCatalog, mState, TAtlasExportOptions.ForBackup, mEnvironment);
    TAtlasSettingsTransfer.Apply(mCatalog, mState, TAtlasSettingsTransfer.Preview(mCatalog, mState,
      TAtlasSettingsTransfer.ParseFile(mExported.Text), TAtlasImportOptions.Create(imMerge, nil, mEnvironment)));
  finally
    mCatalog.Free;
  end;
end;

/// <summary>Dateifehler einmal auslösen: Die RTL lädt dabei Ressourcen-Strings (EFOpenError, EFCreateError,
/// EInOutError) und behält sie bis Programmende; das träfe sonst den ersten Test mit einer gesperrten oder fehlenden
/// Datei (z. B. die Protokolldatei in TRotatingFileStream, die Sperre des Index-Caches).</summary>
procedure WarmUpFileErrors;
var
  mMissing: string;
  mHeld: TFileStream;
begin
  mMissing := TPath.Combine(TPath.GetTempPath, 'atlas-erstgebrauch-fehlt-' + IntToStr(GetCurrentProcessId) + '.bin');
  try
    TFile.ReadAllBytes(mMissing);
  except
    on Exception do
      ;
  end;
  try
    TFileStream.Create(mMissing, fmOpenRead or fmShareDenyNone).Free;
  except
    on Exception do
      ;
  end;
  // Gesperrte Datei neu anlegen (EFCreateError), wie die Sperre des Index-Caches, und zum Schreiben öffnen
  // (EFOpenError wegen Freigabeverletzung), wie eine Protokolldatei, die ein anderer Prozess hält.
  mHeld := TFileStream.Create(mMissing, fmCreate or fmShareExclusive);
  try
    try
      TFileStream.Create(mMissing, fmCreate or fmShareExclusive).Free;
    except
      on Exception do
        ;
    end;
    try
      TFileStream.Create(mMissing, fmOpenWrite or fmShareDenyWrite).Free;
    except
      on Exception do
        ;
    end;
  finally
    mHeld.Free;
    System.SysUtils.DeleteFile(mMissing);
  end;
end;

/// <summary>Datendatei einmal unbrauchbar beiseitelegen und gesperrt lesen und schreiben: Was die
/// Melde- und Fehlerpfade beim ersten Mal anlegen, träfe sonst den ersten Test mit einer gesperrten Datei.</summary>
procedure WarmUpDataFiles;
var
  mFileName: string;
  mLock: TFileStream;
begin
  mFileName := TPath.Combine(TPath.GetTempPath, 'atlas-erstgebrauch-daten-' + IntToStr(GetCurrentProcessId) + '.json');
  try
    TFile.WriteAllText(mFileName, '[1, 2]');
    TAtlasDataFile.Load(mFileName, 'Erstgebrauch',
      function(const AText: string): Boolean
      begin
        Result := False;
      end);
    TAtlasDataFile.Write(mFileName, '{}');
    mLock := TFileStream.Create(mFileName, fmOpenRead or fmShareExclusive);
    try
      TAtlasDataFile.Load(mFileName, 'Erstgebrauch',
        function(const AText: string): Boolean
        begin
          Result := True;
        end);
      try
        TAtlasDataFile.Write(mFileName, '{}');
      except
        on E: Exception do
          TAtlasDataFile.ReportNotWritten('Erstgebrauch', E);
      end;
    finally
      mLock.Free;
    end;
  finally
    System.SysUtils.DeleteFile(mFileName);
    System.SysUtils.DeleteFile(mFileName + TAtlasDataFile.cDefectExtension);
    TAtlasDataFile.ForgetReports;
  end;
end;

/// <summary>Gemeinsame Befehlsliste je Sprache (#1458): entsteht beim ersten Zugriff in der jeweiligen Sprache und
/// bleibt; sonst trifft das je nach Reihenfolge einen anderen Test als Leck (die englische etwa
/// EnglishTextsWithoutGerman über die Regel slash-command, rund 23 KB).</summary>
procedure WarmUpSlashCommands;
var
  mLanguage: TTextLanguage;
begin
  try
    for mLanguage := Low(TTextLanguage) to High(TTextLanguage) do
    begin
      TAtlasLocale.Use(mLanguage);
      TSlashCommandRegistry.Shared;
    end;
  finally
    TAtlasLocale.Use(TTextLanguage.German);
  end;
end;


/// <summary>Gemeinsame Regelkataloge mit Gruppen und Optionen (#909): TRuleCatalog.Shared (englisch) und
/// TRuleCatalog.Localized (deutsche Überlagerung) entstehen beim ersten Zugriff und werden in der Finalisierung von
/// Atlas.Common.Rules.Catalog freigegeben.</summary>
procedure WarmUpRuleCatalogs;
begin
  // Localized liefert nur unter Deutsch die Überlagerung; die Tests beginnen ohnehin deutsch (TLeakMonitor).
  TAtlasLocale.Use(TTextLanguage.German);
  TRuleCatalog.Localized;
  TRuleCatalog.Shared;
end;

/// <summary>Lokale Zeitzone der RTL (ISO-8601-Zeitstempel) und Pfadauswertung von System.JSON legen beim ersten
/// Gebrauch Daten an, die bis zum Programmende bleiben.</summary>
procedure WarmUpTimeZoneAndJsonPath;
var
  mJson: TJSONValue;
begin
  if DateToISO8601(Now, False) = '' then
  begin
    raise EInvalidOperation.Create('Keine Zeitzone');
  end;
  mJson := TJSONObject.ParseJSONValue('{"a":{"b":true}}');
  try
    if not mJson.GetValue<Boolean>('a.b') then
    begin
      raise EInvalidOperation.Create('JSON-Pfad');
    end;
  finally
    mJson.Free;
  end;
end;

/// <summary>TEncoding.Default: Singleton der RTL beim ersten Gebrauch; TFile.ReadAllText liest Dateien ohne BOM
/// damit (z. B. im Korpustest des Parsers über die RTL-Quellen).</summary>
procedure WarmUpDefaultEncoding;
begin
  if TEncoding.Default.GetString(TEncoding.Default.GetBytes('a')) <> 'a' then
  begin
    raise EInvalidOperation.Create('Kodierung');
  end;
end;

/// <summary>Verzeichnis der wortgleichen Rümpfe (TDuplicateBodyCatalog.Shared, angelegt und freigegeben von
/// Atlas.Common.Metrics.DuplicateCatalog): Sein Sperrobjekt bekommt beim ersten Sperren den Monitor-Datensatz
/// der RTL, der mit dem Objekt freigegeben wird.</summary>
procedure WarmUpDuplicateCatalog;
begin
  TDuplicateBodyCatalog.Shared.Clear;
end;

/// <summary>Abonnenten des IDE-Themas (TAtlasUiTheme): Die Liste entsteht beim ersten Abonnenten und wird im
/// Klassendestruktor freigegeben; ihre Kapazität wächst beim ersten Eintrag.</summary>
procedure WarmUpThemeListeners;
var
  mOwner: TObject;
begin
  mOwner := TObject.Create;
  try
    TAtlasUiTheme.Subscribe(mOwner,
      procedure
      begin
      end);
    TAtlasUiTheme.Unsubscribe(mOwner);
  finally
    mOwner.Free;
  end;
end;

/// <summary>Liste der überfälligen Arbeiter-Threads (TAtlasOverdueThreads, freigegeben im Klassendestruktor):
/// Ihre Kapazität wächst beim ersten übernommenen Thread. Ein beendeter Thread wird übernommen und gleich wieder
/// freigegeben.</summary>
procedure WarmUpOverdueThreads;
var
  mThread: TThread;
begin
  mThread := TThread.CreateAnonymousThread(
    procedure
    begin
    end);
  mThread.FreeOnTerminate := False;
  mThread.Start;
  mThread.WaitFor;
  // Adopt gibt beendete Threads sofort frei.
  TAtlasOverdueThreads.Adopt(mThread, 0);
end;

/// <summary>Einstellungsseite (TAtlasSettingsPage) mit einem Abschnitt, einmal ohne und einmal mit Fenster: Die erste
/// Anmeldung legt die Listen der Modul-Registry an (frei mit der Registry in der Finalisierung von Base), das erste
/// Erzeugen der Steuerelemente legt einmalige Daten der VCL an (Themes, Schriften, Fensterklassen; frei in der
/// Finalisierung der VCL).</summary>
procedure WarmUpSettingsPage;
var
  mRegistration: IAtlasRegistration;
  mHost: TForm;
  mPage: TAtlasSettingsPage;
begin
  mRegistration := AtlasModuleRegistry.Provide(IAtlasSettingsSectionProvider,
    TAtlasSettingsSectionFactory.Create(TAtlasSettingsSection) as IAtlasSettingsSectionProvider);
  mRegistration.Revoke;
  TAtlasSettingsPage.Create(nil).Free;
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
  finally
    mHost.Free;
  end;
end;

/// <summary>IDE-Thema auf ein Formular anwenden (TAtlasUiTheme): Farben und erstes Formular der VCL legen
/// einmalige Daten an, frei in der Finalisierung der VCL.</summary>
procedure WarmUpThemeApply;
var
  mForm: TForm;
begin
  // Erste Benutzung (VCL-Formular, Liste der Abonnenten) nicht dem ersten Test anrechnen.
  TAtlasUiTheme.Subscribed(nil);
  TAtlasUiTheme.Uninstall;
  TAtlasUiTheme.Colors;
  TAtlasUiTheme.Apply(nil);
  mForm := TForm.CreateNew(nil);
  try
    TAtlasUiTheme.Apply(mForm);
  finally
    mForm.Free;
  end;
end;

/// <summary>Erster Dialog mit Fenster (TAtlasDialog): einmalige Daten der VCL (Fensterklasse, Schrift), frei in deren
/// Finalisierung.</summary>
procedure WarmUpDialog;
var
  mDialog: TAtlasDialog;
begin
  // Erste Benutzung (VCL-Formular, Liste der Abonnenten des Themendienstes) nicht dem ersten Test anrechnen.
  mDialog := TAtlasDialog.CreateDialog(nil, 'Aufwärmen', 300);
  try
    mDialog.HandleNeeded;
  finally
    mDialog.Free;
  end;
end;

/// <summary>Seite der Tastenkürzel (TAtlasKeysPage): einmalige Daten ihrer Steuerelemente.</summary>
procedure WarmUpKeysPage;
begin
  TAtlasKeysPage.Create(nil).Free;
end;

/// <summary>Übersicht der Einstellungen einmal laden und durchsuchen: Katalog und Texte legen dabei einen
/// Zwischenspeicher bis Prozessende an.</summary>
procedure WarmUpSettingsOverview;
var
  mPage: TAtlasSettingsOverview;
begin
  mPage := TAtlasSettingsOverview.Create(nil);
  try
    mPage.Load(1, 1, 1);
    mPage.SearchFor('enabled');
  finally
    mPage.Free;
  end;
end;

/// <summary>Package-Suche mit .dcp auf der Platte einmal durchlaufen: Datei- und Zeitfunktionen legen beim ersten
/// Aufruf Objekte bis Prozessende an (z. B. die Zeitzone).</summary>
procedure WarmUpPackageLocator;
var
  mFolder: string;
  mLocator: TPackageLocator;
  mContains: Boolean;
begin
  // Einmal der ganze Weg der Tests mit .dcp auf der Platte (Ordner, Zeitstempel, geteiltes Lesen).
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasDcpWarmUp' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(mFolder);
  TFile.WriteAllBytes(TPath.Combine(mFolder, 'Warm.dcp'), TEncoding.ASCII.GetBytes('WARM'));
  mLocator := TPackageLocator.Create([mFolder]);
  try
    mLocator.Provides('Warm', 'Warm', mContains);
  finally
    mLocator.Free;
    TPackageCompiledFiles.Clear;
    TDirectory.Delete(mFolder, True);
  end;
end;

/// <summary>Zwischenspeicher der Feldadressen von System.Classes (TFieldsCache) aus: Benennt ein Test eine
/// Komponente, sucht TComponent.SetReference das gleichnamige Feld im Besitzer und legt dafür je Klasse des
/// Besitzers einen Eintrag an (Feldtabelle als Wörterbuch, je nach Klasse 240 bis 340 Byte), der bis zum
/// Programmende bleibt. Jeder Test mit einer neuen Besitzerklasse zählte das als Leck. Ohne Zwischenspeicher sucht
/// die RTL das Feld direkt (FieldAddress), mit demselben Ergebnis; schon angelegte Einträge gibt Clear frei.
/// Der Zwischenspeicher selbst gehört der RTL und wird in ihrem Klassendestruktor freigegeben.</summary>
/// <summary>Einmal-Belegungen der RTL, die Tests über Atlas-Code treffen: die Kodierungen UTF-16 LE und BE
/// (TEncoding.Unicode, BigEndianUnicode; TParser beim Lesen von DFM-Text), der Nachrichtenverteiler
/// TMessageManager.DefaultManager (VCL beim DPI-Wechsel) und der Ressourcentext, den die RTL beim ersten UTF-8-Fehler
/// lädt und bis zum Ende behält (TEncoding.GetString mit ungültigen Bytes). Freigegeben in der Finalisierung von
/// System.SysUtils bzw. System.Messaging.</summary>
procedure WarmUpRtlSingletons;
begin
  TEncoding.Unicode;
  TEncoding.BigEndianUnicode;
  TMessageManager.DefaultManager;
  try
    TEncoding.UTF8.GetString(TBytes.Create($C3, $28, $FF));
  except
    on Exception do
      ;
  end;
end;

/// <summary>Map-Datei der Test-EXE einmal lesen. Atlas.Windows.Diagnostics.StackTrace lädt sie beim ersten
/// Auflösen eines Stapels (Exception.StackTrace, Leckbericht mit ATLAS_LEAK_TRACE) für die ganze Sitzung und gibt
/// sie in seiner Finalisierung frei; das wären sonst rund 65 MB Leck im ersten Test, der einen Stapel nennt.
/// Ohne .map-Datei kostet der Schritt nichts.</summary>
procedure WarmUpStackTraceMap;
begin
  TStackTrace.Current;
end;

procedure SwitchOffComponentFieldCache;
begin
  SetComponentFieldAddressCache(True, 0);
end;

/// <summary>Erstes Datenmodul des Prozesses (TDataModule, z. B. als Formular der Designer-Fälschung): Es meldet sich
/// bei Screen an (Vcl.Forms, TScreen.FDataModules wächst auf 4 Einträge und schrumpft nicht, frei mit Screen in der
/// Finalisierung der VCL); beim Freigeben nimmt es GlobalNameSpace zum Schreiben (Zähler je Thread, frei mit
/// GlobalNameSpace in der Finalisierung von System.Classes) und sperrt die Liste der offenen Verweise
/// (GlobalFixupList, Monitor-Datensatz, frei mit der Liste).</summary>
procedure WarmUpDataModule;
begin
  TDataModule.CreateNew(nil).Free;
end;

{ TFirstUse }

/// <summary>Windows-Version der RTL (System.SysUtils, Win32Platform und Win32CSDVersion): InitPlatformId legt beim
/// ersten Zugriff den Text des Service Packs an, den SysUtils bis zur Finalisierung hält. Ausgelöst etwa von
/// TRegistry.GetKeyInfo (TDelphiInstallation.Versions beim Lesen der globalen Einstellungen).</summary>
procedure ShellWarmUpPlatformId;
begin
  if Win32Platform < 0 then
  begin
    raise EInvalidOperation.Create('Plattform');
  end;
end;

class procedure TFirstUse.WarmUp;
begin
  SwitchOffComponentFieldCache;
  WarmUpDataModule;
  WarmUpSlashCommands;
  WarmUpRuleCatalogs;
  WarmUpTimeZoneAndJsonPath;
  WarmUpSettingsTransfer;
  WarmUpFileErrors;
  WarmUpDataFiles;
  WarmUpDefaultEncoding;
  WarmUpDuplicateCatalog;
  WarmUpThemeListeners;
  WarmUpOverdueThreads;
  WarmUpSettingsPage;
  WarmUpThemeApply;
  WarmUpDialog;
  WarmUpKeysPage;
  WarmUpSettingsOverview;
  WarmUpPackageLocator;
  WarmUpStackTraceMap;
  WarmUpRtlSingletons;
  ShellWarmUpPlatformId;
end;

end.
