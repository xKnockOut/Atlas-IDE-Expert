unit Atlas.Tests.FirstUse;

// Bekannte Einmal-Belegungen des Testlaufs an einer Stelle. Der Leckmonitor misst je Test, was netto belegt
// bleibt; was beim ersten Gebrauch entsteht, bis zum Programmende lebt und dort freigegeben wird (gemeinsame
// Kataloge, Ressourcentexte der RTL, Zwischenspeicher), sähe für ihn wie ein Leck des ersten Tests aus, der es
// benutzt. TFirstUse.WarmUp legt es deshalb einmal vor dem ersten Test an (RegisterLeakMonitor); die Schritte für
// VCL und Oberfläche stehen in Atlas.Tests.FirstUse.Vcl.
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
  System.RegularExpressions,
  System.RegularExpressionsCore,
  System.Messaging,
  System.NetEncoding,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Metrics.DuplicateCatalog,
  Atlas.Common.Rules.Catalog,
  Atlas.Plugin.Diagnostics.WorkerSlot,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Transfer,
  Atlas.Common.Projects.PackageLocator,
  Atlas.Windows.Diagnostics.StackTrace,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Tools,
  Atlas.Text.IndexCache,
  Atlas.Tests.FirstUse.Vcl;

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

/// <summary>TFile.Replace mit fehlendem Ziel und fehlender Quelle: Die RTL lädt dabei den Ressourcentext von
/// EFileNotFoundException und behält ihn bis Programmende. Im Index-Cache tritt das nur im Wettlauf zweier
/// Schreiber auf (TDiskIndexFileSystem.WriteBytes, Test ConcurrentWritersLeaveReadableCache) und träfe dann
/// zufällig den Test, in dem das Ziel gerade fehlt.</summary>
procedure WarmUpIndexCacheReplace;
var
  mFolder: string;
  mExisting: string;
  mMissing: string;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-erstgebrauch-ersetzen-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(mFolder);
  try
    mExisting := TPath.Combine(mFolder, 'vorhanden.json');
    mMissing := TPath.Combine(mFolder, 'fehlt.json');
    TFile.WriteAllText(mExisting, '{}');
    try
      TFile.Replace(mExisting, mMissing, mExisting + '.bak');
    except
      on EFileNotFoundException do
        ;
    end;
    try
      TFile.Replace(mMissing, mExisting, mExisting + '.bak');
    except
      on EFileNotFoundException do
        ;
    end;
  finally
    TDirectory.Delete(mFolder, True);
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
  // TLocalTimeZone merkt die Umstellungen je Jahr in einem Wörterbuch. Leere Zeitstempel (Datum 0, Jahr 1899)
  // treffen sonst den ersten Test, der sie schreibt oder liest (TMcpBuildTools.Report, TTextTimestamp.TryParseIso
  // im Testlauf-Stand).
  if ISO8601ToDate(DateToISO8601(0, False), False) > 1 then
  begin
    raise EInvalidOperation.Create('Zeitzone 1899');
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
/// Atlas.Common.Metrics.DuplicateCatalog): Clear bringt seine Tabelle auf die kleinste Größe (TrimExcess); die
/// legt der erste Aufruf an, und sie bleibt bis zur Freigabe des Verzeichnisses.</summary>
procedure WarmUpDuplicateCatalog;
begin
  TDuplicateBodyCatalog.Shared.Clear;
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
/// TMessageManager.DefaultManager (VCL beim DPI-Wechsel), die URL-Kodierung TNetEncoding.URL (Dateiadressen im
/// Anonymisierer des Server-Logs) und der Ressourcentext, den die RTL beim ersten UTF-8-Fehler lädt und bis zum Ende
/// behält (TEncoding.GetString mit ungültigen Bytes). Freigegeben in der Finalisierung von System.SysUtils,
/// System.Messaging bzw. System.NetEncoding.</summary>
procedure WarmUpRtlSingletons;
begin
  TEncoding.Unicode;
  TEncoding.BigEndianUnicode;
  TMessageManager.DefaultManager;
  TNetEncoding.URL.Decode('');
  // Base64 (Handschlag der Assistenten-Verbindung, TAtlasLinkHandshake.AcceptOf).
  TNetEncoding.Base64.Encode('');
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

/// <summary>Fehlerpfade der Regex-Engine (System.RegularExpressions) einmal durchlaufen: Ein ungültiger Ausdruck
/// und ein unbekannter Gruppenname lösen ERegularExpressionError aus; die RTL lädt dabei die Ressourcentexte der
/// Meldungen und behält sie bis zum Programmende. Das träfe sonst den ersten Test mit einem ungültigen Suchmuster
/// (Suche/Ersetzen, eigene Muster der Projektaufgaben, Filter des Ereignisprotokolls) oder einem Ersatztext mit
/// unbekannter Gruppe.</summary>
procedure WarmUpRegexErrors;
var
  mFound: TMatch;
begin
  try
    TRegEx.Create('(abc', [roIgnoreCase]).IsMatch('');
  except
    on ERegularExpressionError do
      ;
  end;
  mFound := TRegEx.Create('(?<name>\w+)').Match('Wert');
  try
    if mFound.Groups['gibt_es_nicht'].Success then
    begin
      raise EInvalidOperation.Create('Unbekannte Gruppe passt');
    end;
  except
    on ERegularExpressionError do
      ;
  end;
end;

/// <summary>Erster Systemfehler (RaiseLastOSError, z. B. ein Serverstart mit fehlender Datei): EOSError holt seinen
/// Meldungstext (SOSError) über den Zwischenspeicher der Ressourcentexte von System.SysUtils (ResStringLoad). Der
/// Text bleibt dort bis zum Programmende und wird in der Finalisierung von System.SysUtils freigegeben.</summary>
procedure WarmUpOsErrorText;
begin
  try
    RaiseLastOSError(ERROR_PATH_NOT_FOUND);
  except
    on EOSError do
      ;
  end;
end;

/// <summary>Ressourcentexte, die die RTL beim ersten Laden (LoadResString) bis zum Programmende behält: die Meldung
/// von Abort (SOperationAborted, etwa im Befehlsschutz) und die des beschädigten Index-Caches
/// (TIndexCacheReader.Fail, sIndexCacheDamaged). Sonst träfe es den ersten Test, der die Ausnahme auslöst.</summary>
procedure WarmUpResourceTexts;
begin
  try
    Abort;
  except
    on EAbort do
      ;
  end;
  try
    TIndexCacheReader.Fail;
  except
    on EIndexCacheFormat do
      ;
  end;
end;

{ TFirstUse }

/// <summary>Fundorte von git und svn (TAtlasVcsTools.Where): gemerkt bis Programmende in Klassenvariablen von
/// Atlas.Core.VersionControl.Tools, freigegeben mit deren Finalisierung. Tests, die einen Fundort vorgeben, stellen
/// den echten danach mit Remember wieder her, statt ihn zu vergessen.</summary>
procedure WarmUpVcsTools;
var
  mKind: TAtlasVcsKind;
begin
  for mKind := Low(TAtlasVcsKind) to High(TAtlasVcsKind) do
  begin
    TAtlasVcsTools.Where(mKind);
  end;
end;

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
  WarmUpSlashCommands;
  WarmUpRuleCatalogs;
  WarmUpTimeZoneAndJsonPath;
  WarmUpSettingsTransfer;
  WarmUpFileErrors;
  WarmUpOsErrorText;
  WarmUpResourceTexts;
  WarmUpDataFiles;
  WarmUpIndexCacheReplace;
  WarmUpDefaultEncoding;
  WarmUpDuplicateCatalog;
  WarmUpOverdueThreads;
  WarmUpPackageLocator;
  WarmUpRegexErrors;
  WarmUpVcsTools;
  WarmUpStackTraceMap;
  WarmUpRtlSingletons;
  ShellWarmUpPlatformId;
  TFirstUseVcl.WarmUp;
end;

end.
