unit Atlas.Tests.LeakMonitor;

// Speicherleck-Überwachung für DUnitX. Misst über GetMemoryManagerState des
// eingebauten Speichermanagers (FastMM-basiert), wie viele Bytes Setup, Test
// und TearDown netto belegt haben. DUnitX wertet einen Test mit Rest als
// Speicherleck. Eine Leckmeldung ist ein Befund, kein Grund zum Wiederholen
//: Tests warten auf jeden Thread, den sie starten, und leeren
// Felder im TearDown; Einmal-Belegungen der RTL nimmt ein [SetupFixture]
// vorweg. [IgnoreMemoryLeaks] nur, wo ein Test sein Wachstum selbst misst oder
// Speicher absichtlich über das Testende hinaus lebt, und dann mit Grund.
//
// Die Messung ist prozessweit und sieht deshalb auch andere Threads. Damit
// sie nur Lecks des Tests meldet:
// - Vorwärmen (RegisterLeakMonitor): Die RTL hält Warteobjekte von TMonitor
//   (Wait, TLightweightEvent, Thread-Pool) in einem Zwischenspeicher, dessen
//   Verwaltungsknoten bis Programmende bleiben. Er wächst, sobald erstmals
//   mehr Threads gleichzeitig warten als je zuvor, und zwar in dem Thread, der
//   gerade fertig wird – oft ein Thread-Pool- oder Überwachungs-Thread
//   früherer Tests mitten in einem fremden Test (24 Byte je Knoten unter
//   Win64). Ebenso legt der erste TTask den Standard-Thread-Pool an.
// - Nachwarten: Bleibt nach Test oder TearDown ein Rest, wartet der Monitor
//   kurz, bis Threads des Tests ihre letzten Freigaben erledigt haben (z. B.
//   der Lese-Thread einer JSON-RPC-Verbindung nach ReaderDone oder ein
//   Task nach dem Signal).
// - Lücke nach dem Setup: Die RTL belegt die Startdaten eines Threads (BeginThread, 24 Byte unter Win64) im
//   Aufrufer, frei gibt sie der neue Thread beim Anlaufen. Fällt das zwischen PostSetUp und PreTest, zählt
//   PreTest die Freigabe zum Setup; Belegungen in der Lücke gehören DUnitX und zählen nicht.
// - Ein negativer Saldo (andere Threads geben älteren Speicher frei) ist nie
//   ein Leck des Tests und wird als 0 gemeldet.
// - Anonymes Protokoll (#1478): Das gemeinsame atlas.log (TAtlasGuard.RotatingLog) nummeriert jeden neuen Namen,
//   Pfad und Text und behält die Nummern bis Programmende (höchstens MaxLabels). Jeder Wert zählte so als Leck
//   des Tests, der ihn zuerst schreibt (z. B. FailingProviderTripsOnlyItself, GuardErrorLineHidesMessage).
//   PostTearDown vergisst die Nummern vor der letzten Messung; jeder Test beginnt mit leerer Tabelle.
// Bleibt ein Leck, hängt der Bericht Thread-Anzahl und Wartezeit an.
//
// Der Monitor ist der einzige Haken vor jedem Setup und setzt deshalb auch den gemeinsamen Ausgangszustand:
// Jeder Test beginnt mit deutschen Texten (TAtlasLocale, #1458). Die Sprache gilt prozessweit, und Tests, die
// Einstellungen anwenden (TShellSettings.SetLoose wählt ohne language Englisch), ließen sonst nachfolgende Tests
// je nach Reihenfolge englisch prüfen.

interface

uses
  DUnitX.TestFramework;

type
  TLeakMonitor = class(TInterfacedObject, IMemoryLeakMonitor, IMemoryLeakMonitor2)
  private
    FSetUpBefore: Int64;
    FSetUpAllocated: Int64;
    /// <summary>Stand am Ende des Setups; 0 = keins gemessen.</summary>
    FSetUpEnd: Int64;
    FTestBefore: Int64;
    FTestAllocated: Int64;
    FTearDownBefore: Int64;
    FTearDownAllocated: Int64;
    FStarted: Boolean;
    FThreadsAtStart: Integer;
    FThreadsAtEnd: Integer;
    FWaitedMs: UInt64;
    procedure Start;
    function RawTotal: Int64;
    function Reported(AValue: Int64): Int64;
    procedure Settle(ABefore: Int64; var AAllocated: Int64; AOthers: Int64);
  public
    procedure PreSetup;
    procedure PostSetUp;
    procedure PreTest;
    procedure PostTest;
    procedure PreTearDown;
    procedure PostTearDown;
    function SetUpMemoryAllocated: Int64;
    function TearDownMemoryAllocated: Int64;
    function TestMemoryAllocated: Int64;
    function GetReport: string;
  end;

/// <summary>Aktuell belegte Bytes laut Speichermanager.</summary>
function AllocatedBytes: Int64;

/// <summary>Anzahl der Threads dieses Prozesses (Toolhelp; belegt keinen Delphi-Speicher).</summary>
function ProcessThreadCount: Integer;

/// <summary>Löst Einmal-Belegungen der RTL aus, die sonst in fremden Tests auffallen.</summary>
procedure PrewarmRuntime;

/// <summary>Wärmt die RTL vor und meldet TLeakMonitor als Überwachung bei DUnitX an.</summary>
procedure RegisterLeakMonitor;

implementation

// Delphi 13 liefert DUnitX mit DUnitX.ServiceLocator (TDUnitXServiceLocator)
// statt des früheren DUnitX.IoC (TDUnitXIoC); die Schnittstelle ist gleich.
uses
  Winapi.Windows,
  Winapi.MMSystem,
  Winapi.TlHelp32,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Threading,
  System.DateUtils,
  System.JSON,
  System.Generics.Collections,
  DUnitX.ServiceLocator,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Rules.Catalog,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Transfer,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.TimeLimit;

const
  /// <summary>Höchstens so lange wartet der Monitor auf Freigaben anderer Threads.</summary>
  cSettleTimeoutMs: UInt64 = 250;
  cSettleStepMs = 2;
  /// <summary>So viele gleiche Messungen hintereinander gelten als ruhig.</summary>
  cStableSamples = 3;
  /// <summary>Mindestzahl gleichzeitig wartender Threads beim Vorwärmen.</summary>
  cMinPrewarmWaiters = 64;

function AllocatedBytes: Int64;
var
  mState: TMemoryManagerState;
  I: Integer;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  GetMemoryManagerState(mState);
  {$WARN SYMBOL_PLATFORM DEFAULT}
  Result := Int64(mState.TotalAllocatedMediumBlockSize) + Int64(mState.TotalAllocatedLargeBlockSize);
  for I := Low(mState.SmallBlockTypeStates) to High(mState.SmallBlockTypeStates) do
  begin
    Inc(Result, Int64(mState.SmallBlockTypeStates[I].AllocatedBlockCount) *
      mState.SmallBlockTypeStates[I].UseableBlockSize);
  end;
end;

function ProcessThreadCount: Integer;
var
  mSnapshot: THandle;
  mEntry: TThreadEntry32;
  mProcessId: DWORD;
begin
  Result := 0;
  mSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if mSnapshot = INVALID_HANDLE_VALUE then
  begin
    Exit;
  end;
  try
    mProcessId := GetCurrentProcessId;
    FillChar(mEntry, SizeOf(mEntry), 0);
    mEntry.dwSize := SizeOf(mEntry);
    if Thread32First(mSnapshot, mEntry) then
      repeat
        if mEntry.th32OwnerProcessID = mProcessId then
        begin
          Inc(Result);
        end;
        mEntry.dwSize := SizeOf(mEntry);
      until not Thread32Next(mSnapshot, mEntry);
  finally
    CloseHandle(mSnapshot);
  end;
end;

type
  /// <summary>Lässt viele Threads gleichzeitig in TMonitor.Wait stehen.</summary>
  TWaitGate = class
  private
    FWaiting: Integer;
  public
    procedure Wait;
    function Waiting: Integer;
  end;

procedure TWaitGate.Wait;
begin
  TMonitor.Enter(Self);
  try
    Inc(FWaiting);
    TMonitor.Wait(Self, 10000);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TWaitGate.Waiting: Integer;
begin
  TMonitor.Enter(Self);
  try
    Result := FWaiting;
  finally
    TMonitor.Exit(Self);
  end;
end;

function StartWaiter(AGate: TWaitGate): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    begin
      AGate.Wait;
    end);
  Result.FreeOnTerminate := False;
  Result.Start;
end;

procedure PrewarmWaitObjects;
var
  mGate: TWaitGate;
  mWaiters: TArray<TThread>;
  mIndex: Integer;
  mDeadline: UInt64;
begin
  // Jeder Thread in TMonitor.Wait hält ein Warteobjekt der RTL; beim Freigeben
  // legt die RTL für jedes über den bisherigen Höchststand hinaus einen
  // Verwaltungsknoten an, der bis Programmende bleibt. Einmal viele Threads
  // gleichzeitig warten lassen, dann wächst der Zwischenspeicher in den Tests nicht mehr.
  mGate := TWaitGate.Create;
  try
    SetLength(mWaiters, 4 * TThread.ProcessorCount);
    if Length(mWaiters) < cMinPrewarmWaiters then
    begin
      SetLength(mWaiters, cMinPrewarmWaiters);
    end;
    for mIndex := 0 to High(mWaiters) do
    begin
      mWaiters[mIndex] := StartWaiter(mGate);
    end;
    // Inc steht unter der Sperre vor Wait; wer gezählt ist, wartet also schon.
    mDeadline := TThread.GetTickCount64 + 5000;
    while (mGate.Waiting < Length(mWaiters)) and (TThread.GetTickCount64 < mDeadline) do
    begin
      TThread.Sleep(1);
    end;
    TMonitor.Enter(mGate);
    try
      TMonitor.PulseAll(mGate);
    finally
      TMonitor.Exit(mGate);
    end;
    for mIndex := 0 to High(mWaiters) do
    begin
      mWaiters[mIndex].WaitFor;
      mWaiters[mIndex].Free;
    end;
  finally
    mGate.Free;
  end;
end;

/// <summary>Katalog, Export und Import der Einstellungen (#723) einmal durchlaufen: Was dabei beim ersten
/// Gebrauch bleibt, träfe sonst je nach Reihenfolge einen anderen Test als Leck.</summary>
procedure PrewarmSettingsTransfer;
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
procedure PrewarmFileErrors;
var
  mMissing: string;
  mHeld: TFileStream;
begin
  mMissing := TPath.Combine(TPath.GetTempPath, 'atlas-leckmonitor-fehlt-' + IntToStr(GetCurrentProcessId) + '.bin');
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
procedure PrewarmDataFiles;
var
  mFileName: string;
  mLock: TFileStream;
begin
  mFileName := TPath.Combine(TPath.GetTempPath, 'atlas-leckmonitor-daten-' + IntToStr(GetCurrentProcessId) + '.json');
  try
    TFile.WriteAllText(mFileName, '[1, 2]');
    TAtlasDataFile.Load(mFileName, 'Leckmonitor',
      function(const AText: string): Boolean
      begin
        Result := False;
      end);
    TAtlasDataFile.Write(mFileName, '{}');
    mLock := TFileStream.Create(mFileName, fmOpenRead or fmShareExclusive);
    try
      TAtlasDataFile.Load(mFileName, 'Leckmonitor',
        function(const AText: string): Boolean
        begin
          Result := True;
        end);
      try
        TAtlasDataFile.Write(mFileName, '{}');
      except
        on E: Exception do
          TAtlasDataFile.ReportNotWritten('Leckmonitor', E);
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
procedure PrewarmSlashCommands;
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

procedure PrewarmRuntime;
var
  mTask: ITask;
  mCurrent: TThread;
  mJson: TJSONValue;
begin
  PrewarmWaitObjects;
  PrewarmSlashCommands;
  // Ebenso der gemeinsame Regelkatalog mit Gruppen und Optionen (#909).
  TRuleCatalog.Shared;
  // Legt den Standard-Thread-Pool und seinen Überwachungs-Thread an (bleiben bis Programmende).
  mTask := TTask.Run(
    procedure
    begin
    end);
  mTask.Wait;
  // Hauptthread: TExternalThread für TThread.CurrentThread (bleibt bis Programmende).
  mCurrent := TThread.CurrentThread;
  if mCurrent = nil then
  begin
    raise EInvalidOperation.Create('Kein aktueller Thread');
  end;
  // Lokale Zeitzone (ISO-8601-Zeitstempel) und JSON-Pfade legen beim ersten Gebrauch Daten an,
  // die bis Programmende bleiben.
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
  PrewarmSettingsTransfer;
  PrewarmFileErrors;
  PrewarmDataFiles;
  // Dateien ohne BOM liest TFile.ReadAllText mit TEncoding.Default (Singleton beim ersten Gebrauch, z. B. im
  // Korpustest des Parsers über die RTL-Quellen).
  if TEncoding.Default.GetString(TEncoding.Default.GetBytes('a')) <> 'a' then
  begin
    raise EInvalidOperation.Create('Kodierung');
  end;
end;

procedure RegisterLeakMonitor;
begin
  // Sleep(2) beim Warten auf andere Threads schliefe sonst eine ganze Zeitscheibe (rund 16 ms)
  // und verdreifachte die Laufzeit der Tests.
  timeBeginPeriod(1);
  PrewarmRuntime;
  TDUnitXServiceLocator.DefaultContainer.RegisterType<IMemoryLeakMonitor>(
    function: IMemoryLeakMonitor
    begin
      Result := TLeakMonitor.Create;
    end);
end;

{ TLeakMonitor }

procedure TLeakMonitor.Start;
begin
  if FStarted then
  begin
    Exit;
  end;
  FStarted := True;
  FThreadsAtStart := ProcessThreadCount;
  FThreadsAtEnd := FThreadsAtStart;
end;

function TLeakMonitor.RawTotal: Int64;
begin
  Result := FSetUpAllocated + FTestAllocated + FTearDownAllocated;
end;

function TLeakMonitor.Reported(AValue: Int64): Int64;
begin
  // Mehr freigegeben als belegt: Freigaben anderer Threads, kein Leck.
  if RawTotal <= 0 then
  begin
    Result := 0;
  end
  else
  begin
    Result := AValue;
  end;
end;

procedure TLeakMonitor.Settle(ABefore: Int64; var AAllocated: Int64; AOthers: Int64);
var
  mStarted: UInt64;
  mLast: Int64;
  mStable: Integer;
begin
  // AOthers: Saldo der übrigen Abschnitte; gewartet wird, solange die Summe positiv ist.
  mStarted := TThread.GetTickCount64;
  mLast := AAllocated;
  mStable := 0;
  while (AOthers + AAllocated > 0) and (TThread.GetTickCount64 - mStarted < cSettleTimeoutMs) do
  begin
    TThread.Sleep(cSettleStepMs);
    AAllocated := AllocatedBytes - ABefore;
    if AAllocated = mLast then
    begin
      Inc(mStable);
    end
    else
    begin
      mStable := 0;
      mLast := AAllocated;
    end;
    // Ruhig und keine zusätzlichen Threads mehr: weiteres Warten bringt nichts.
    if (mStable >= cStableSamples) and (ProcessThreadCount <= FThreadsAtStart) then
    begin
      Break;
    end;
  end;
  Inc(FWaitedMs, TThread.GetTickCount64 - mStarted);
  FThreadsAtEnd := ProcessThreadCount;
end;

procedure TLeakMonitor.PreSetup;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Start;
  FSetUpBefore := AllocatedBytes;
end;

procedure TLeakMonitor.PostSetUp;
begin
  FSetUpEnd := AllocatedBytes;
  FSetUpAllocated := FSetUpEnd - FSetUpBefore;
end;

procedure TLeakMonitor.PreTest;
var
  mGap: Int64;
begin
  Start;
  if FSetUpEnd <> 0 then
  begin
    mGap := AllocatedBytes - FSetUpEnd;
    FSetUpEnd := 0;
    if mGap < 0 then
    begin
      Inc(FSetUpAllocated, mGap);
    end;
  end;
  // Arbeiter früherer Tests vor der Messung beenden, damit ihre Freigabe in PostTest kein Leck verdeckt.
  TAtlasTimeLimit.StopAll(1000);
  FTestBefore := AllocatedBytes;
end;

procedure TLeakMonitor.PostTest;
begin
  // Arbeiter des Zeitlimits (#493) bleiben für den nächsten Aufruf stehen; ihr Speicher gehört zu keinem
  // Test. Vor dem Messen beenden, der nächste Aufruf legt neue an.
  TAtlasTimeLimit.StopAll(1000);
  FTestAllocated := AllocatedBytes - FTestBefore;
  // Nur der Test selbst: Was das Setup belegt, gibt meist erst das TearDown frei.
  if FTestAllocated > 0 then
  begin
    Settle(FTestBefore, FTestAllocated, 0);
  end
  else
  begin
    FThreadsAtEnd := ProcessThreadCount;
  end;
end;

procedure TLeakMonitor.PreTearDown;
begin
  FTearDownBefore := AllocatedBytes;
end;

procedure TLeakMonitor.PostTearDown;
begin
  // Nummern des anonymen Protokolls gehören keinem Test (siehe Kopf); vor der Messung vergessen.
  TAtlasGuard.RotatingLog.Redactor.Forget;
  FTearDownAllocated := AllocatedBytes - FTearDownBefore;
  if RawTotal > 0 then
  begin
    Settle(FTearDownBefore, FTearDownAllocated, FSetUpAllocated + FTestAllocated);
  end;
end;

function TLeakMonitor.SetUpMemoryAllocated: Int64;
begin
  Result := Reported(FSetUpAllocated);
end;

function TLeakMonitor.TearDownMemoryAllocated: Int64;
begin
  Result := Reported(FTearDownAllocated);
end;

function TLeakMonitor.TestMemoryAllocated: Int64;
begin
  Result := Reported(FTestAllocated);
end;

function TLeakMonitor.GetReport: string;
begin
  Result := Format(' (Setup %d, Test %d, TearDown %d Byte; Threads am Anfang %d, am Ende %d; ' +
    '%d ms auf andere Threads gewartet)', [FSetUpAllocated, FTestAllocated, FTearDownAllocated,
    FThreadsAtStart, FThreadsAtEnd, FWaitedMs]);
end;

end.
