unit Atlas.Core.Diagnostics.Timing;

// Diagnosemodus (#479), Teil ohne VCL und Open Tools API: misst je Abfrage der
// Vervollständigung die Dauer der Schritte, für die #409 ein Zeitbudget
// festlegt, und hält die letzten 50 Abfragen vor.
// - Eine Abfrage beginnt mit TAtlasCompletionController.Start (Kontext: vom
//   auslösenden Ereignis bis zur Anfrage). Danach melden sich die Quellen
//   (TAtlasCompletionProviders, Zeit bis Complete samt Anzahl ihrer Einträge),
//   jedes Filtern und Sortieren (Refresh), das erste Zeigen einer Liste (bis
//   zu den ersten Einträgen) und jedes Zeichnen des Popups.
// - Ausgeschaltet (Enabled = False, Vorgabe) prüfen die Messpunkte nur diese
//   Klassenvariable: kein Zeitstempel, keine Sperre, keine Liste.
// - Anonym: Gespeichert werden Art des Kontexts, Name der Quelle, Zeiten und
//   Anzahlen, dazu nur der Dateiname ohne Ordner. Präfix, Zeile und Quelltext
//   kommen nie hinein; der Bericht nennt Dateinamen nur auf Wunsch und kürzt
//   Pfade in den Einstellungen wie der Fehlerbericht (#108).
// - TAtlasTimingRows bereitet die Zeilen des Diagnosefensters auf (letzte
//   Abfrage, Mittelwert und Maximum, Überschreitung je Wert), TAtlasTimingReport
//   den Text für „Bericht kopieren“ und für die letzten Diagnosedaten (#766).
// Threads: Quellen melden sich aus Hintergrund-Threads; alle Methoden des
// Rekorders sind threadsicher.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections;

type
{$SCOPEDENUMS ON}
  /// <summary>Gemessene Schritte einer Abfrage mit Budget aus #409.</summary>
  TAtlasTimingStep = (Context, Provider, FilterSort, Draw, FirstVisible);
  TAtlasTimingRowKind = (Step, Provider, Entries);
{$SCOPEDENUMS OFF}

  /// <summary>Zeitbudget aus #409 je Schritt in Millisekunden.</summary>
  TAtlasTimingBudget = record
  public const
    ContextMs = 8;
    /// <summary>Eine Quelle darf so lange brauchen wie die ganze Abfrage bis zu den ersten Einträgen.</summary>
    ProviderMs = 50;
    FilterSortMs = 12;
    DrawMs = 10;
    FirstVisibleMs = 50;
  public
    class function LimitMs(AStep: TAtlasTimingStep): Double; static;
    /// <summary>Liegt AMs über dem Budget von AStep? Nicht gemessene Werte (&lt; 0) nie.</summary>
    class function Exceeded(AStep: TAtlasTimingStep; AMs: Double): Boolean; static;
  end;

  TAtlasProviderTiming = record
    Name: string;
    Ms: Double;
    /// <summary>Einträge dieser Quelle.</summary>
    Count: Integer;
  end;

  /// <summary>Eine Abfrage; Zeiten in ms, -1 = nicht gemessen.</summary>
  TAtlasQueryTiming = record
    Id: Integer;
    Started: TDateTime;
    /// <summary>Art des Kontexts, z. B. "Bezeichner, automatisch"; nie Text aus dem Editor.</summary>
    Kind: string;
    /// <summary>Dateiname ohne Ordner; im Bericht nur auf Wunsch.</summary>
    FileName: string;
    ContextMs: Double;
    Providers: TArray<TAtlasProviderTiming>;
    /// <summary>Längster Filter- und Sortierschritt und Zahl der Schritte.</summary>
    FilterSortMs: Double;
    FilterSortSteps: Integer;
    /// <summary>Längstes Zeichnen des Popups und Zahl der Zeichenvorgänge.</summary>
    DrawMs: Double;
    DrawSteps: Integer;
    /// <summary>Vom auslösenden Ereignis bis zur ersten sichtbaren Liste.</summary>
    FirstVisibleMs: Double;
    /// <summary>Einträge aller Quellen und davon nach dem Filtern sichtbar (beim letzten Filtern).</summary>
    Count: Integer;
    Shown: Integer;
    /// <summary>Wert eines Schritts; Provider = langsamste Quelle.</summary>
    function Value(AStep: TAtlasTimingStep): Double;
    function ProviderIndex(const AName: string): Integer;
    /// <summary>Liegt irgendein Schritt über dem Budget?</summary>
    function Exceeded: Boolean;
  end;

  TAtlasTimingStat = record
    Count: Integer;
    Sum: Double;
    Maximum: Double;
    procedure Add(AValue: Double);
    /// <summary>Mittelwert; -1 ohne Werte.</summary>
    function Mean: Double;
    /// <summary>Maximum; -1 ohne Werte.</summary>
    function Peak: Double;
  end;

  /// <summary>Mittelwert und Maximum über mehrere Abfragen; nicht gemessene Werte zählen nicht.</summary>
  TAtlasTimingStats = record
    Queries: Integer;
    Steps: array[TAtlasTimingStep] of TAtlasTimingStat;
    Entries: TAtlasTimingStat;
    /// <summary>Quellen in der Reihenfolge ihres ersten Auftretens.</summary>
    ProviderNames: TArray<string>;
    Providers: TArray<TAtlasTimingStat>;
    class function From(const AQueries: TArray<TAtlasQueryTiming>): TAtlasTimingStats; static;
    function Provider(const AName: string): TAtlasTimingStat;
  end;

  /// <summary>Zeile des Diagnosefensters; Werte -1 = keine Angabe.</summary>
  TAtlasTimingRow = record
    Kind: TAtlasTimingRowKind;
    Step: TAtlasTimingStep;
    /// <summary>Name der Quelle (Kind = Provider).</summary>
    Name: string;
    Last: Double;
    Mean: Double;
    Maximum: Double;
    /// <summary>Budget in ms; 0 bei der Zeile „Einträge“.</summary>
    Budget: Double;
    LastWarn: Boolean;
    MeanWarn: Boolean;
    MaxWarn: Boolean;
  end;

  TAtlasTimingRows = record
  public
    /// <summary>Zeilen: Kontext, je Quelle eine, Filtern und Sortieren, Zeichnen, bis zur Liste, Einträge.
    /// AQueries älteste zuerst; „letzte“ ist die neueste.</summary>
    class function Build(const AQueries: TArray<TAtlasQueryTiming>): TArray<TAtlasTimingRow>; static;
    /// <summary>"3.2" bzw. "–" ohne Wert.</summary>
    class function Ms(AValue: Double): string; static;
    /// <summary>Anzahl ohne Nachkommastellen bzw. "–".</summary>
    class function CountText(AValue: Double): string; static;
  end;

  /// <summary>Messpunkte und die letzten Abfragen (#479); eine Instanz je Prozess (Shared).</summary>
  TAtlasQueryTimings = class
  public const
    Capacity = 50;
  private class var
    FEnabled: Boolean;
    FShared: TAtlasQueryTimings;
  private
    FLock: TCriticalSection;
    FQueries: TList<TAtlasQueryTiming>;
    FNextId: Integer;
    FCurrent: Integer;
    FCurrentStart: Int64;
    FVersion: Integer;
    function IndexOf(AId: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Gemeinsame Instanz der Messpunkte; lebt bis zum Entladen des Packages.</summary>
    class function Shared: TAtlasQueryTimings; static;
    /// <summary>Messung an; aus (Vorgabe) tun die Messpunkte nichts.</summary>
    class property Enabled: Boolean read FEnabled write FEnabled;
    /// <summary>Hochauflösender Zeitstempel für MsSince.</summary>
    class function Stamp: Int64; static;
    class function MsSince(AStamp: Int64): Double; static;
    /// <summary>Neue Abfrage; Kontext = Zeit seit AStart (0 = nicht gemessen). Ergebnis: Kennung.</summary>
    function BeginQuery(AStart: Int64; const AKind, AFileName: string): Integer;
    /// <summary>Kennung der laufenden Abfrage; 0 ohne.</summary>
    function Current: Integer;
    /// <summary>Quelle AName der Abfrage AId ist fertig (auch abgebrochen oder über dem Zeitlimit).</summary>
    procedure ProviderDone(AId: Integer; const AName: string; AMs: Double; ACount: Integer);
    procedure FilterSorted(AMs: Double; ACount, AShown: Integer);
    /// <summary>Die laufende Abfrage zeigt ihre erste Liste; zählt nur einmal je Abfrage.</summary>
    procedure ListShown;
    procedure Drawn(AMs: Double);
    procedure Clear;
    /// <summary>Kopie der letzten Abfragen, älteste zuerst.</summary>
    function Snapshot: TArray<TAtlasQueryTiming>;
    /// <summary>Zählt jede Änderung; das Fenster zeichnet nur bei neuem Stand neu.</summary>
    function Version: Integer;
  end;

  TAtlasTimingReportInput = record
    AtlasVersion: string;
    IdeVersion: string;
    Platform: string;
    /// <summary>Einstellungen des Plugins als JSON; Pfade werden gekürzt.</summary>
    Settings: string;
    /// <summary>Benutzer-, Rechner- und Domänenname; werden zu &lt;benutzer&gt;.</summary>
    Identity: TArray<string>;
    /// <summary>Dateinamen der Abfragen aufnehmen (nur auf Wunsch).</summary>
    FileNames: Boolean;
    Created: TDateTime;
    /// <summary>Abschnitt „Plugin-Zeiten“ (TAtlasPluginReport) vor den Einstellungen; '' ohne.</summary>
    Plugin: string;
  end;

  TAtlasTimingReport = record
  public const
    /// <summary>Letzte Diagnosedaten neben den Diagnoselogs (%LOCALAPPDATA%\Atlas\Logs\Diagnose).</summary>
    FileName = 'atlas-diagnosemodus.txt';
  public
    /// <summary>Text für „Bericht kopieren“: Versionen, Budgets, letzte Abfrage, Mittelwert und Maximum, die
    /// Abfragen einzeln (neueste zuerst) und die Einstellungen. Kein Quelltext; Dateinamen nur mit
    /// AInput.FileNames.</summary>
    class function Build(const AQueries: TArray<TAtlasQueryTiming>; const AInput: TAtlasTimingReportInput): string;
      static;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.Math,
  Atlas.Core.Diagnostics.BugReport,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TTimingText = (Context, Entries, Visible, Source, Entries2, StepLastMeanMaximumBudget, AtlasDiagnosticMode479,
    Created, Platform, Budget409ContextMsSource, ContainsNoSourceCodeFile, TimesInMsLastQuery, QueriesNewestFirst,
    NoQueryMeasuredYet, Settings);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TTimingText] of string = (
    (' | Kontext ',
     ' | Einträge ',
     ', sichtbar ',
     'Quelle ',
     'Einträge',
     'Schritt | letzte | Mittel | Maximum | Budget',
     '# Atlas-Diagnosemodus (#479)',
     'Erstellt: ',
     ', Plattform: ',
     'Budget (#409): Kontext %d ms, Quelle %d ms, Filtern und Sortieren %d ms, Zeichnen %d ms, bis zur Liste %d ms. (!) = über dem Budget.',
     'Enthält keinen Quelltext; Dateinamen: ',
     '## Zeiten in ms: letzte Abfrage, Mittelwert und Maximum der letzten %d',
     '## Abfragen, neueste zuerst',
     'Noch keine Abfrage gemessen.',
     '## Einstellungen'),
    (' | Context ',
     ' | Entries ',
     ', visible ',
     'Source ',
     'Entries',
     'Step | last | mean | maximum | budget',
     '# Atlas diagnostic mode (#479)',
     'Created: ',
     ', platform: ',
     'Budget (#409): context %d ms, source %d ms, filter and sort %d ms, draw %d ms, until the list %d ms. (!) = over budget.',
     'Contains no source code; file names: ',
     '## Times in ms: last query, mean and maximum of the last %d',
     '## Queries, newest first',
     'No query measured yet.',
     '## Settings'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TTimingText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

const
  cStepNames: array[TAtlasLanguage, TAtlasTimingStep] of string = (
    ('Kontext', 'Quelle', 'Filtern und Sortieren', 'Zeichnen', 'Bis zur Liste'),
    ('Context', 'Source', 'Filter and sort', 'Draw', 'Until the list'));
  cNoValue = '–';

function Invariant: TFormatSettings;
begin
  Result := FormatSettings;
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := ',';
end;

{ TAtlasTimingBudget }

class function TAtlasTimingBudget.LimitMs(AStep: TAtlasTimingStep): Double;
begin
  case AStep of
    TAtlasTimingStep.Context:
      Result := ContextMs;
    TAtlasTimingStep.Provider:
      Result := ProviderMs;
    TAtlasTimingStep.FilterSort:
      Result := FilterSortMs;
    TAtlasTimingStep.Draw:
      Result := DrawMs;
  else
    Result := FirstVisibleMs;
  end;
end;

class function TAtlasTimingBudget.Exceeded(AStep: TAtlasTimingStep; AMs: Double): Boolean;
begin
  Result := (AMs >= 0) and (AMs > LimitMs(AStep));
end;

{ TAtlasQueryTiming }

function TAtlasQueryTiming.Value(AStep: TAtlasTimingStep): Double;
var
  mProvider: TAtlasProviderTiming;
begin
  case AStep of
    TAtlasTimingStep.Context:
      Result := ContextMs;
    TAtlasTimingStep.Provider:
      begin
        Result := -1;
        for mProvider in Providers do
        begin
          Result := Max(Result, mProvider.Ms);
        end;
      end;
    TAtlasTimingStep.FilterSort:
      Result := FilterSortMs;
    TAtlasTimingStep.Draw:
      Result := DrawMs;
  else
    Result := FirstVisibleMs;
  end;
end;

function TAtlasQueryTiming.ProviderIndex(const AName: string): Integer;
begin
  for Result := 0 to High(Providers) do
  begin
    if Providers[Result].Name = AName then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

function TAtlasQueryTiming.Exceeded: Boolean;
var
  mStep: TAtlasTimingStep;
begin
  for mStep := Low(TAtlasTimingStep) to High(TAtlasTimingStep) do
  begin
    if TAtlasTimingBudget.Exceeded(mStep, Value(mStep)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasTimingStat }

procedure TAtlasTimingStat.Add(AValue: Double);
begin
  if AValue < 0 then
  begin
    Exit;
  end;
  if (Count = 0) or (AValue > Maximum) then
  begin
    Maximum := AValue;
  end;
  Inc(Count);
  Sum := Sum + AValue;
end;

function TAtlasTimingStat.Mean: Double;
begin
  if Count = 0 then
  begin
    Result := -1;
  end
  else
  begin
    Result := Sum / Count;
  end;
end;

function TAtlasTimingStat.Peak: Double;
begin
  if Count = 0 then
  begin
    Result := -1;
  end
  else
  begin
    Result := Maximum;
  end;
end;

{ TAtlasTimingStats }

class function TAtlasTimingStats.From(const AQueries: TArray<TAtlasQueryTiming>): TAtlasTimingStats;
var
  mQuery: TAtlasQueryTiming;
  mProvider: TAtlasProviderTiming;
  mStep: TAtlasTimingStep;
  mIndex: Integer;
begin
  Result := Default(TAtlasTimingStats);
  Result.ProviderNames := nil;
  Result.Providers := nil;
  for mQuery in AQueries do
  begin
    Inc(Result.Queries);
    for mStep := Low(TAtlasTimingStep) to High(TAtlasTimingStep) do
    begin
      Result.Steps[mStep].Add(mQuery.Value(mStep));
    end;
    if mQuery.Count > 0 then
    begin
      Result.Entries.Add(mQuery.Count);
    end;
    for mProvider in mQuery.Providers do
    begin
      mIndex := Length(Result.ProviderNames) - 1;
      while (mIndex >= 0) and (Result.ProviderNames[mIndex] <> mProvider.Name) do
      begin
        Dec(mIndex);
      end;
      if mIndex < 0 then
      begin
        Result.ProviderNames := Result.ProviderNames + [mProvider.Name];
        SetLength(Result.Providers, Length(Result.Providers) + 1);
        Result.Providers[High(Result.Providers)] := Default(TAtlasTimingStat);
        mIndex := High(Result.Providers);
      end;
      Result.Providers[mIndex].Add(mProvider.Ms);
    end;
  end;
end;

function TAtlasTimingStats.Provider(const AName: string): TAtlasTimingStat;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ProviderNames) do
  begin
    if ProviderNames[mIndex] = AName then
    begin
      Exit(Providers[mIndex]);
    end;
  end;
  Result := Default(TAtlasTimingStat);
end;

{ TAtlasTimingRows }

function StepRow(AStep: TAtlasTimingStep; ALast: Double; const AStat: TAtlasTimingStat): TAtlasTimingRow;
begin
  Result := Default(TAtlasTimingRow);
  Result.Kind := TAtlasTimingRowKind.Step;
  Result.Step := AStep;
  Result.Name := '';
  Result.Last := ALast;
  Result.Mean := AStat.Mean;
  Result.Maximum := AStat.Peak;
  Result.Budget := TAtlasTimingBudget.LimitMs(AStep);
  Result.LastWarn := TAtlasTimingBudget.Exceeded(AStep, Result.Last);
  Result.MeanWarn := TAtlasTimingBudget.Exceeded(AStep, Result.Mean);
  Result.MaxWarn := TAtlasTimingBudget.Exceeded(AStep, Result.Maximum);
end;

class function TAtlasTimingRows.Build(const AQueries: TArray<TAtlasQueryTiming>): TArray<TAtlasTimingRow>;
var
  mStats: TAtlasTimingStats;
  mLast: TAtlasQueryTiming;
  mRow: TAtlasTimingRow;
  mIndex, mAt: Integer;
  mStep: TAtlasTimingStep;
begin
  Result := nil;
  mStats := TAtlasTimingStats.From(AQueries);
  mLast := Default(TAtlasQueryTiming);
  mLast.ContextMs := -1;
  mLast.FilterSortMs := -1;
  mLast.DrawMs := -1;
  mLast.FirstVisibleMs := -1;
  mLast.Providers := nil;
  if Length(AQueries) > 0 then
  begin
    mLast := AQueries[High(AQueries)];
  end;
  Result := Result + [StepRow(TAtlasTimingStep.Context, mLast.ContextMs, mStats.Steps[TAtlasTimingStep.Context])];
  // Je Quelle eine Zeile mit ihrem Namen; fehlt sie in der letzten Abfrage, bleibt „letzte“ leer.
  for mIndex := 0 to High(mStats.ProviderNames) do
  begin
    mRow := StepRow(TAtlasTimingStep.Provider, -1, mStats.Providers[mIndex]);
    mRow.Kind := TAtlasTimingRowKind.Provider;
    mRow.Name := mStats.ProviderNames[mIndex];
    mAt := mLast.ProviderIndex(mRow.Name);
    if mAt >= 0 then
    begin
      mRow.Last := mLast.Providers[mAt].Ms;
    end;
    mRow.LastWarn := TAtlasTimingBudget.Exceeded(TAtlasTimingStep.Provider, mRow.Last);
    Result := Result + [mRow];
  end;
  for mStep in [TAtlasTimingStep.FilterSort, TAtlasTimingStep.Draw, TAtlasTimingStep.FirstVisible] do
  begin
    Result := Result + [StepRow(mStep, mLast.Value(mStep), mStats.Steps[mStep])];
  end;
  mRow := Default(TAtlasTimingRow);
  mRow.Kind := TAtlasTimingRowKind.Entries;
  mRow.Name := '';
  mRow.Last := -1;
  if Length(AQueries) > 0 then
  begin
    mRow.Last := mLast.Count;
  end;
  mRow.Mean := mStats.Entries.Mean;
  mRow.Maximum := mStats.Entries.Peak;
  Result := Result + [mRow];
end;

class function TAtlasTimingRows.Ms(AValue: Double): string;
begin
  if AValue < 0 then
  begin
    Result := cNoValue;
  end
  else
  begin
    Result := FormatFloat('0.0', AValue, Invariant);
  end;
end;

class function TAtlasTimingRows.CountText(AValue: Double): string;
begin
  if AValue < 0 then
  begin
    Result := cNoValue;
  end
  else
  begin
    Result := IntToStr(Round(AValue));
  end;
end;

{ TAtlasQueryTimings }

constructor TAtlasQueryTimings.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FQueries := TList<TAtlasQueryTiming>.Create;
end;

destructor TAtlasQueryTimings.Destroy;
begin
  FQueries.Free;
  FLock.Free;
  inherited;
end;

class function TAtlasQueryTimings.Shared: TAtlasQueryTimings;
begin
  Result := FShared;
end;

class function TAtlasQueryTimings.Stamp: Int64;
begin
  Result := TStopwatch.GetTimeStamp;
end;

class function TAtlasQueryTimings.MsSince(AStamp: Int64): Double;
begin
  Result := (TStopwatch.GetTimeStamp - AStamp) * 1000.0 / TStopwatch.Frequency;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

function TAtlasQueryTimings.IndexOf(AId: Integer): Integer;
begin
  // Neueste zuerst: Meldungen betreffen fast immer die laufende Abfrage.
  for Result := FQueries.Count - 1 downto 0 do
  begin
    if FQueries[Result].Id = AId then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

function TAtlasQueryTimings.BeginQuery(AStart: Int64; const AKind, AFileName: string): Integer;
var
  mQuery: TAtlasQueryTiming;
begin
  mQuery := Default(TAtlasQueryTiming);
  mQuery.Started := Now;
  mQuery.Kind := AKind;
  mQuery.FileName := AFileName;
  mQuery.ContextMs := -1;
  if AStart <> 0 then
  begin
    mQuery.ContextMs := MsSince(AStart);
  end;
  mQuery.Providers := nil;
  mQuery.FilterSortMs := -1;
  mQuery.DrawMs := -1;
  mQuery.FirstVisibleMs := -1;
  FLock.Enter;
  try
    Inc(FNextId);
    mQuery.Id := FNextId;
    FCurrent := mQuery.Id;
    FCurrentStart := AStart;
    if FCurrentStart = 0 then
    begin
      FCurrentStart := Stamp;
    end;
    FQueries.Add(mQuery);
    while FQueries.Count > Capacity do
    begin
      FQueries.Delete(0);
    end;
    Inc(FVersion);
    Result := mQuery.Id;
  finally
    FLock.Leave;
  end;
end;

function TAtlasQueryTimings.Current: Integer;
begin
  FLock.Enter;
  try
    Result := FCurrent;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasQueryTimings.ProviderDone(AId: Integer; const AName: string; AMs: Double; ACount: Integer);
var
  mIndex, mAt: Integer;
  mQuery: TAtlasQueryTiming;
  mProvider: TAtlasProviderTiming;
begin
  FLock.Enter;
  try
    mIndex := IndexOf(AId);
    if mIndex < 0 then
    begin
      Exit;
    end;
    mQuery := FQueries[mIndex];
    mProvider.Name := AName;
    mProvider.Ms := AMs;
    mProvider.Count := ACount;
    // Neu fragen (#431) ersetzt die Zeit derselben Quelle; die Liste wird kopiert, die Momentaufnahmen bleiben.
    mQuery.Providers := Copy(mQuery.Providers);
    mAt := mQuery.ProviderIndex(AName);
    if mAt >= 0 then
    begin
      mQuery.Providers[mAt] := mProvider;
    end
    else
    begin
      mQuery.Providers := mQuery.Providers + [mProvider];
    end;
    FQueries[mIndex] := mQuery;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasQueryTimings.FilterSorted(AMs: Double; ACount, AShown: Integer);
var
  mIndex: Integer;
  mQuery: TAtlasQueryTiming;
begin
  FLock.Enter;
  try
    mIndex := IndexOf(FCurrent);
    if mIndex < 0 then
    begin
      Exit;
    end;
    mQuery := FQueries[mIndex];
    mQuery.FilterSortMs := Max(mQuery.FilterSortMs, AMs);
    Inc(mQuery.FilterSortSteps);
    mQuery.Count := ACount;
    mQuery.Shown := AShown;
    FQueries[mIndex] := mQuery;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasQueryTimings.ListShown;
var
  mIndex: Integer;
  mQuery: TAtlasQueryTiming;
begin
  FLock.Enter;
  try
    mIndex := IndexOf(FCurrent);
    if (mIndex < 0) or (FQueries[mIndex].FirstVisibleMs >= 0) then
    begin
      Exit;
    end;
    mQuery := FQueries[mIndex];
    mQuery.FirstVisibleMs := MsSince(FCurrentStart);
    FQueries[mIndex] := mQuery;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasQueryTimings.Drawn(AMs: Double);
var
  mIndex: Integer;
  mQuery: TAtlasQueryTiming;
begin
  FLock.Enter;
  try
    mIndex := IndexOf(FCurrent);
    if mIndex < 0 then
    begin
      Exit;
    end;
    mQuery := FQueries[mIndex];
    mQuery.DrawMs := Max(mQuery.DrawMs, AMs);
    Inc(mQuery.DrawSteps);
    FQueries[mIndex] := mQuery;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasQueryTimings.Clear;
begin
  FLock.Enter;
  try
    FQueries.Clear;
    FCurrent := 0;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

function TAtlasQueryTimings.Snapshot: TArray<TAtlasQueryTiming>;
begin
  FLock.Enter;
  try
    Result := FQueries.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TAtlasQueryTimings.Version: Integer;
begin
  FLock.Enter;
  try
    Result := FVersion;
  finally
    FLock.Leave;
  end;
end;

{ TAtlasTimingReport }

function Mark(AWarn: Boolean): string;
begin
  if AWarn then
  begin
    Result := ' (!)';
  end
  else
  begin
    Result := '';
  end;
end;

function QueryLine(const AQuery: TAtlasQueryTiming; AFileNames: Boolean): string;
var
  mProvider: TAtlasProviderTiming;
  mStep: TAtlasTimingStep;
begin
  Result := FormatDateTime('hh":"nn":"ss', AQuery.Started) + ' ' + AQuery.Kind;
  if AFileNames and (AQuery.FileName <> '') then
  begin
    Result := Result + ', ' + AQuery.FileName;
  end;
  Result := Result + UiText(TTimingText.Context) + TAtlasTimingRows.Ms(AQuery.ContextMs) +
    Mark(TAtlasTimingBudget.Exceeded(TAtlasTimingStep.Context, AQuery.ContextMs));
  for mProvider in AQuery.Providers do
  begin
    Result := Result + ' | ' + mProvider.Name + ' ' + TAtlasTimingRows.Ms(mProvider.Ms) +
      Mark(TAtlasTimingBudget.Exceeded(TAtlasTimingStep.Provider, mProvider.Ms)) + ' (' + IntToStr(mProvider.Count) +
      ')';
  end;
  for mStep in [TAtlasTimingStep.FilterSort, TAtlasTimingStep.Draw, TAtlasTimingStep.FirstVisible] do
  begin
    Result := Result + ' | ' + cStepNames[TAtlasTextLanguage.Current, mStep] + ' ' + TAtlasTimingRows.Ms(AQuery.Value(mStep)) +
      Mark(TAtlasTimingBudget.Exceeded(mStep, AQuery.Value(mStep)));
  end;
  Result := Result + UiText(TTimingText.Entries) + IntToStr(AQuery.Count) + UiText(TTimingText.Visible) + IntToStr(AQuery.Shown);
end;

function RowCaption(const ARow: TAtlasTimingRow): string;
begin
  case ARow.Kind of
    TAtlasTimingRowKind.Provider:
      Result := UiText(TTimingText.Source) + ARow.Name;
    TAtlasTimingRowKind.Entries:
      Result := UiText(TTimingText.Entries2);
  else
    Result := cStepNames[TAtlasTextLanguage.Current, ARow.Step];
  end;
end;

function RowLine(const ARow: TAtlasTimingRow): string;
begin
  if ARow.Kind = TAtlasTimingRowKind.Entries then
  begin
    Result := RowCaption(ARow) + ' | ' + TAtlasTimingRows.CountText(ARow.Last) + ' | ' +
      TAtlasTimingRows.CountText(ARow.Mean) + ' | ' + TAtlasTimingRows.CountText(ARow.Maximum) + ' | ' + cNoValue;
  end
  else
  begin
    Result := RowCaption(ARow) + ' | ' + TAtlasTimingRows.Ms(ARow.Last) + Mark(ARow.LastWarn) + ' | ' +
      TAtlasTimingRows.Ms(ARow.Mean) + Mark(ARow.MeanWarn) + ' | ' + TAtlasTimingRows.Ms(ARow.Maximum) +
      Mark(ARow.MaxWarn) + ' | ' + TAtlasTimingRows.Ms(ARow.Budget);
  end;
end;

/// <summary>Tabelle „Schritt | letzte | Mittel | Maximum | Budget“ des Berichts.</summary>
procedure AddStepTable(ALines: TStrings; const AQueries: TArray<TAtlasQueryTiming>);
var
  mRow: TAtlasTimingRow;
begin
  ALines.Add(UiText(TTimingText.StepLastMeanMaximumBudget));
  ALines.Add('--- | --- | --- | --- | ---');
  for mRow in TAtlasTimingRows.Build(AQueries) do
  begin
    ALines.Add(RowLine(mRow));
  end;
end;

class function TAtlasTimingReport.Build(const AQueries: TArray<TAtlasQueryTiming>;
  const AInput: TAtlasTimingReportInput): string;
var
  mLines: TStringList;
  mIndex: Integer;
  mSettings: string;
begin
  mLines := TStringList.Create;
  try
    mLines.Add(UiText(TTimingText.AtlasDiagnosticMode479));
    mLines.Add('');
    mLines.Add(UiText(TTimingText.Created) + FormatDateTime('yyyy-mm-dd hh":"nn', AInput.Created));
    mLines.Add('Atlas: ' + AInput.AtlasVersion + ', IDE: ' + AInput.IdeVersion + UiText(TTimingText.Platform) + AInput.Platform);
    mLines.Add(Format(UiText(TTimingText.Budget409ContextMsSource), [TAtlasTimingBudget.ContextMs, TAtlasTimingBudget.ProviderMs,
      TAtlasTimingBudget.FilterSortMs, TAtlasTimingBudget.DrawMs, TAtlasTimingBudget.FirstVisibleMs]));
    mLines.Add(UiText(TTimingText.ContainsNoSourceCodeFile) + BoolToStr(AInput.FileNames, True) + '.');
    mLines.Add('');
    mLines.Add(Format(UiText(TTimingText.TimesInMsLastQuery),
      [Length(AQueries)]));
    mLines.Add('');
    AddStepTable(mLines, AQueries);
    mLines.Add('');
    mLines.Add(UiText(TTimingText.QueriesNewestFirst));
    mLines.Add('');
    for mIndex := High(AQueries) downto 0 do
    begin
      mLines.Add(QueryLine(AQueries[mIndex], AInput.FileNames));
    end;
    if Length(AQueries) = 0 then
    begin
      mLines.Add(UiText(TTimingText.NoQueryMeasuredYet));
    end;
    mLines.Add('');
    if AInput.Plugin <> '' then
    begin
      mLines.Add(AInput.Plugin);
    end;
    mLines.Add(UiText(TTimingText.Settings));
    mLines.Add('');
    // Pfade (Serverpfad u. a.) wie im Fehlerbericht kürzen; Benutzer- und Rechnername ersetzen.
    mSettings := TAtlasBugReport.AnonymizePaths(AInput.Settings, nil, AInput.Identity);
    mLines.Add(mSettings);
    Result := mLines.Text;
  finally
    mLines.Free;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Diagnostics.Timing', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);
  TAtlasQueryTimings.FShared := TAtlasQueryTimings.Create;

finalization
  TAtlasQueryTimings.FEnabled := False;
  FreeAndNil(TAtlasQueryTimings.FShared);

end.
