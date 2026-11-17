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
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Metrics.DuplicateCatalog,
  Atlas.Common.Rules.Catalog,
  Atlas.Core.Diagnostics.WorkerSlot,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Transfer,
  Atlas.UI.Foundation.Theme;

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
/// EInOutError) und
/// behält sie bis Programmende; das träfe sonst den ersten Test mit einer gesperrten oder fehlenden Datei.</summary>
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
  // Gesperrte Datei neu anlegen (EFCreateError), wie die Sperre des Index-Caches.
  mHeld := TFileStream.Create(mMissing, fmCreate or fmShareExclusive);
  try
    try
      TFileStream.Create(mMissing, fmCreate or fmShareExclusive).Free;
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

{ TFirstUse }

class procedure TFirstUse.WarmUp;
begin
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
end;

end.
