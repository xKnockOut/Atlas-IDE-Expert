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
  Atlas.Core.Diagnostics.BugReport;

const
  StepNames: array[TAtlasTimingStep] of string = ('Kontext', 'Quelle', 'Filtern und Sortieren', 'Zeichnen',
    'Bis zur Liste');
  NoValue = '–';

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
  Provider: TAtlasProviderTiming;
begin
  case AStep of
    TAtlasTimingStep.Context:
      Result := ContextMs;
    TAtlasTimingStep.Provider:
      begin
        Result := -1;
        for Provider in Providers do
          Result := Max(Result, Provider.Ms);
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
    if Providers[Result].Name = AName then
      Exit;
  Result := -1;
end;

function TAtlasQueryTiming.Exceeded: Boolean;
var
  Step: TAtlasTimingStep;
begin
  for Step := Low(TAtlasTimingStep) to High(TAtlasTimingStep) do
    if TAtlasTimingBudget.Exceeded(Step, Value(Step)) then
      Exit(True);
  Result := False;
end;

{ TAtlasTimingStat }

procedure TAtlasTimingStat.Add(AValue: Double);
begin
  if AValue < 0 then
    Exit;
  if (Count = 0) or (AValue > Maximum) then
    Maximum := AValue;
  Inc(Count);
  Sum := Sum + AValue;
end;

function TAtlasTimingStat.Mean: Double;
begin
  if Count = 0 then
    Result := -1
  else
    Result := Sum / Count;
end;

function TAtlasTimingStat.Peak: Double;
begin
  if Count = 0 then
    Result := -1
  else
    Result := Maximum;
end;

{ TAtlasTimingStats }

class function TAtlasTimingStats.From(const AQueries: TArray<TAtlasQueryTiming>): TAtlasTimingStats;
var
  Query: TAtlasQueryTiming;
  Provider: TAtlasProviderTiming;
  Step: TAtlasTimingStep;
  Index: Integer;
begin
  Result := Default(TAtlasTimingStats);
  Result.ProviderNames := nil;
  Result.Providers := nil;
  for Query in AQueries do
  begin
    Inc(Result.Queries);
    for Step := Low(TAtlasTimingStep) to High(TAtlasTimingStep) do
      Result.Steps[Step].Add(Query.Value(Step));
    if Query.Count > 0 then
      Result.Entries.Add(Query.Count);
    for Provider in Query.Providers do
    begin
      Index := Length(Result.ProviderNames) - 1;
      while (Index >= 0) and (Result.ProviderNames[Index] <> Provider.Name) do
        Dec(Index);
      if Index < 0 then
      begin
        Result.ProviderNames := Result.ProviderNames + [Provider.Name];
        SetLength(Result.Providers, Length(Result.Providers) + 1);
        Result.Providers[High(Result.Providers)] := Default(TAtlasTimingStat);
        Index := High(Result.Providers);
      end;
      Result.Providers[Index].Add(Provider.Ms);
    end;
  end;
end;

function TAtlasTimingStats.Provider(const AName: string): TAtlasTimingStat;
var
  Index: Integer;
begin
  for Index := 0 to High(ProviderNames) do
    if ProviderNames[Index] = AName then
      Exit(Providers[Index]);
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
  Stats: TAtlasTimingStats;
  Last: TAtlasQueryTiming;
  Row: TAtlasTimingRow;
  Index, At: Integer;
  Step: TAtlasTimingStep;
begin
  Result := nil;
  Stats := TAtlasTimingStats.From(AQueries);
  Last := Default(TAtlasQueryTiming);
  Last.ContextMs := -1;
  Last.FilterSortMs := -1;
  Last.DrawMs := -1;
  Last.FirstVisibleMs := -1;
  Last.Providers := nil;
  if Length(AQueries) > 0 then
    Last := AQueries[High(AQueries)];
  Result := Result + [StepRow(TAtlasTimingStep.Context, Last.ContextMs, Stats.Steps[TAtlasTimingStep.Context])];
  // Je Quelle eine Zeile mit ihrem Namen; fehlt sie in der letzten Abfrage, bleibt „letzte“ leer.
  for Index := 0 to High(Stats.ProviderNames) do
  begin
    Row := StepRow(TAtlasTimingStep.Provider, -1, Stats.Providers[Index]);
    Row.Kind := TAtlasTimingRowKind.Provider;
    Row.Name := Stats.ProviderNames[Index];
    At := Last.ProviderIndex(Row.Name);
    if At >= 0 then
      Row.Last := Last.Providers[At].Ms;
    Row.LastWarn := TAtlasTimingBudget.Exceeded(TAtlasTimingStep.Provider, Row.Last);
    Result := Result + [Row];
  end;
  for Step in [TAtlasTimingStep.FilterSort, TAtlasTimingStep.Draw, TAtlasTimingStep.FirstVisible] do
    Result := Result + [StepRow(Step, Last.Value(Step), Stats.Steps[Step])];
  Row := Default(TAtlasTimingRow);
  Row.Kind := TAtlasTimingRowKind.Entries;
  Row.Name := '';
  Row.Last := -1;
  if Length(AQueries) > 0 then
    Row.Last := Last.Count;
  Row.Mean := Stats.Entries.Mean;
  Row.Maximum := Stats.Entries.Peak;
  Result := Result + [Row];
end;

class function TAtlasTimingRows.Ms(AValue: Double): string;
begin
  if AValue < 0 then
    Result := NoValue
  else
    Result := FormatFloat('0.0', AValue, Invariant);
end;

class function TAtlasTimingRows.CountText(AValue: Double): string;
begin
  if AValue < 0 then
    Result := NoValue
  else
    Result := IntToStr(Round(AValue));
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
    Result := 0;
end;

function TAtlasQueryTimings.IndexOf(AId: Integer): Integer;
begin
  // Neueste zuerst: Meldungen betreffen fast immer die laufende Abfrage.
  for Result := FQueries.Count - 1 downto 0 do
    if FQueries[Result].Id = AId then
      Exit;
  Result := -1;
end;

function TAtlasQueryTimings.BeginQuery(AStart: Int64; const AKind, AFileName: string): Integer;
var
  Query: TAtlasQueryTiming;
begin
  Query := Default(TAtlasQueryTiming);
  Query.Started := Now;
  Query.Kind := AKind;
  Query.FileName := AFileName;
  Query.ContextMs := -1;
  if AStart <> 0 then
    Query.ContextMs := MsSince(AStart);
  Query.Providers := nil;
  Query.FilterSortMs := -1;
  Query.DrawMs := -1;
  Query.FirstVisibleMs := -1;
  FLock.Enter;
  try
    Inc(FNextId);
    Query.Id := FNextId;
    FCurrent := Query.Id;
    FCurrentStart := AStart;
    if FCurrentStart = 0 then
      FCurrentStart := Stamp;
    FQueries.Add(Query);
    while FQueries.Count > Capacity do
      FQueries.Delete(0);
    Inc(FVersion);
    Result := Query.Id;
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
  Index, At: Integer;
  Query: TAtlasQueryTiming;
  Provider: TAtlasProviderTiming;
begin
  FLock.Enter;
  try
    Index := IndexOf(AId);
    if Index < 0 then
      Exit;
    Query := FQueries[Index];
    Provider.Name := AName;
    Provider.Ms := AMs;
    Provider.Count := ACount;
    // Neu fragen (#431) ersetzt die Zeit derselben Quelle; die Liste wird kopiert, die Momentaufnahmen bleiben.
    Query.Providers := Copy(Query.Providers);
    At := Query.ProviderIndex(AName);
    if At >= 0 then
      Query.Providers[At] := Provider
    else
      Query.Providers := Query.Providers + [Provider];
    FQueries[Index] := Query;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasQueryTimings.FilterSorted(AMs: Double; ACount, AShown: Integer);
var
  Index: Integer;
  Query: TAtlasQueryTiming;
begin
  FLock.Enter;
  try
    Index := IndexOf(FCurrent);
    if Index < 0 then
      Exit;
    Query := FQueries[Index];
    Query.FilterSortMs := Max(Query.FilterSortMs, AMs);
    Inc(Query.FilterSortSteps);
    Query.Count := ACount;
    Query.Shown := AShown;
    FQueries[Index] := Query;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasQueryTimings.ListShown;
var
  Index: Integer;
  Query: TAtlasQueryTiming;
begin
  FLock.Enter;
  try
    Index := IndexOf(FCurrent);
    if (Index < 0) or (FQueries[Index].FirstVisibleMs >= 0) then
      Exit;
    Query := FQueries[Index];
    Query.FirstVisibleMs := MsSince(FCurrentStart);
    FQueries[Index] := Query;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasQueryTimings.Drawn(AMs: Double);
var
  Index: Integer;
  Query: TAtlasQueryTiming;
begin
  FLock.Enter;
  try
    Index := IndexOf(FCurrent);
    if Index < 0 then
      Exit;
    Query := FQueries[Index];
    Query.DrawMs := Max(Query.DrawMs, AMs);
    Inc(Query.DrawSteps);
    FQueries[Index] := Query;
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
    Result := ' (!)'
  else
    Result := '';
end;

function QueryLine(const AQuery: TAtlasQueryTiming; AFileNames: Boolean): string;
var
  Provider: TAtlasProviderTiming;
  Step: TAtlasTimingStep;
begin
  Result := FormatDateTime('hh":"nn":"ss', AQuery.Started) + ' ' + AQuery.Kind;
  if AFileNames and (AQuery.FileName <> '') then
    Result := Result + ', ' + AQuery.FileName;
  Result := Result + ' | Kontext ' + TAtlasTimingRows.Ms(AQuery.ContextMs) +
    Mark(TAtlasTimingBudget.Exceeded(TAtlasTimingStep.Context, AQuery.ContextMs));
  for Provider in AQuery.Providers do
    Result := Result + ' | ' + Provider.Name + ' ' + TAtlasTimingRows.Ms(Provider.Ms) +
      Mark(TAtlasTimingBudget.Exceeded(TAtlasTimingStep.Provider, Provider.Ms)) + ' (' + IntToStr(Provider.Count) +
      ')';
  for Step in [TAtlasTimingStep.FilterSort, TAtlasTimingStep.Draw, TAtlasTimingStep.FirstVisible] do
    Result := Result + ' | ' + StepNames[Step] + ' ' + TAtlasTimingRows.Ms(AQuery.Value(Step)) +
      Mark(TAtlasTimingBudget.Exceeded(Step, AQuery.Value(Step)));
  Result := Result + ' | Einträge ' + IntToStr(AQuery.Count) + ', sichtbar ' + IntToStr(AQuery.Shown);
end;

function RowCaption(const ARow: TAtlasTimingRow): string;
begin
  case ARow.Kind of
    TAtlasTimingRowKind.Provider:
      Result := 'Quelle ' + ARow.Name;
    TAtlasTimingRowKind.Entries:
      Result := 'Einträge';
  else
    Result := StepNames[ARow.Step];
  end;
end;

class function TAtlasTimingReport.Build(const AQueries: TArray<TAtlasQueryTiming>;
  const AInput: TAtlasTimingReportInput): string;
var
  Lines: TStringList;
  Rows: TArray<TAtlasTimingRow>;
  Row: TAtlasTimingRow;
  Index: Integer;
  Settings: string;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('# Atlas-Diagnosemodus (#479)');
    Lines.Add('');
    Lines.Add('Erstellt: ' + FormatDateTime('yyyy-mm-dd hh":"nn', AInput.Created));
    Lines.Add('Atlas: ' + AInput.AtlasVersion + ', IDE: ' + AInput.IdeVersion + ', Plattform: ' + AInput.Platform);
    Lines.Add(Format('Budget (#409): Kontext %d ms, Quelle %d ms, Filtern und Sortieren %d ms, Zeichnen %d ms, ' +
      'bis zur Liste %d ms. (!) = über dem Budget.', [TAtlasTimingBudget.ContextMs, TAtlasTimingBudget.ProviderMs,
      TAtlasTimingBudget.FilterSortMs, TAtlasTimingBudget.DrawMs, TAtlasTimingBudget.FirstVisibleMs]));
    Lines.Add('Enthält keinen Quelltext; Dateinamen: ' + BoolToStr(AInput.FileNames, True) + '.');
    Lines.Add('');
    Lines.Add(Format('## Zeiten in ms: letzte Abfrage, Mittelwert und Maximum der letzten %d',
      [Length(AQueries)]));
    Lines.Add('');
    Lines.Add('Schritt | letzte | Mittel | Maximum | Budget');
    Lines.Add('--- | --- | --- | --- | ---');
    Rows := TAtlasTimingRows.Build(AQueries);
    for Row in Rows do
      if Row.Kind = TAtlasTimingRowKind.Entries then
        Lines.Add(RowCaption(Row) + ' | ' + TAtlasTimingRows.CountText(Row.Last) + ' | ' +
          TAtlasTimingRows.CountText(Row.Mean) + ' | ' + TAtlasTimingRows.CountText(Row.Maximum) + ' | ' + NoValue)
      else
        Lines.Add(RowCaption(Row) + ' | ' + TAtlasTimingRows.Ms(Row.Last) + Mark(Row.LastWarn) + ' | ' +
          TAtlasTimingRows.Ms(Row.Mean) + Mark(Row.MeanWarn) + ' | ' + TAtlasTimingRows.Ms(Row.Maximum) +
          Mark(Row.MaxWarn) + ' | ' + TAtlasTimingRows.Ms(Row.Budget));
    Lines.Add('');
    Lines.Add('## Abfragen, neueste zuerst');
    Lines.Add('');
    for Index := High(AQueries) downto 0 do
      Lines.Add(QueryLine(AQueries[Index], AInput.FileNames));
    if Length(AQueries) = 0 then
      Lines.Add('Noch keine Abfrage gemessen.');
    Lines.Add('');
    Lines.Add('## Einstellungen');
    Lines.Add('');
    // Pfade (Serverpfad u. a.) wie im Fehlerbericht kürzen; Benutzer- und Rechnername ersetzen.
    Settings := TAtlasBugReport.AnonymizePaths(AInput.Settings, nil, AInput.Identity);
    Lines.Add(Settings);
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

initialization
  TAtlasQueryTimings.FShared := TAtlasQueryTimings.Create;

finalization
  TAtlasQueryTimings.FEnabled := False;
  FreeAndNil(TAtlasQueryTimings.FShared);

end.
