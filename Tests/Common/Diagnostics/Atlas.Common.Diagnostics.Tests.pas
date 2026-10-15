unit Atlas.Common.Diagnostics.Tests;

// Tests für das anonymisierte Diagnoselog (#647): Filter vor dem Schreiben,
// Kurz-IDs, Anfragebereich, Formatierung, Puffer bis Configure, Laufmarken
// und Beobachter des Dispatchers.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDiagnosticLogTests = class
  public
    [Test]
    procedure FilterRejectsPathsDrivesAndExtensions;
    [Test]
    procedure FilterRejectsUserAndMachineNames;
    [Test]
    procedure FilterAllowsMethodNamesAndCodes;
    [Test]
    procedure ShortIdsAreStableWithinRun;
    [Test]
    procedure LibraryUnitsKeepTheirName;
    [Test]
    procedure StackFrameDropsSourceFile;
    [Test]
    procedure RequestScopeCollectsCodes;
    [Test]
    procedure RequestScopeWithoutOpenDoesNothing;
    /// <summary>Slowest behält die längste Dauer samt Namen (langsamste Prüfregel).</summary>
    [Test]
    procedure RequestScopeKeepsSlowest;
    [Test]
    procedure FormatsRequestLine;
    [Test]
    procedure EmptyResultWithoutReasonIsMarked;
    [Test]
    procedure BuffersUntilConfigured;
    [Test]
    procedure DisabledLogWritesNothing;
    [Test]
    procedure EndLineHasReason;
    [Test]
    procedure DroppedLinesAreCounted;
    [Test]
    procedure LoggingCostsLessThanOneMillisecond;
    [Test]
    procedure LogFolderReportsRunsWithoutEnd;
    [Test]
    procedure LogFolderRemovesOldFiles;
    [Test]
    procedure DispatcherReportsRequestsToObserver;
    [Test]
    procedure ServerLogHidesPathsAndNames;
    [Test]
    procedure ServerLogKeepsLibraryUnitsAndNumbers;
    /// <summary>Code-Review P-11: Die einmal übersetzten Muster liefern über viele Zeilen dieselben Marken;
    /// 2000 Zeilen bleiben deutlich unter einer Millisekunde je Zeile.</summary>
    [Test]
    procedure AnonymizeManyLinesSameLabels;
    /// <summary>Code-Review P-11: Die geteilten TRegEx-Instanzen laufen nur unter der Sperre; parallele
    /// Aufrufe liefern dieselben Marken ohne Ausnahme.</summary>
    [Test]
    procedure AnonymizeConcurrent;
  end;

  /// <summary>Speicherrest beim Beenden (#177).</summary>
  [TestFixture]
  TShutdownLeaksTests = class
  public
    [Test]
    procedure CountsAllocatedMemory;
    [Test]
    procedure DescribesWithoutNames;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.StrUtils,
  System.IOUtils,
  System.JSON,
  System.Diagnostics,
  System.DateUtils,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Diagnostics.Contract,
  Atlas.Common.Diagnostics.Anonymizer,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Atlas.Common.Diagnostics.Providers.Log,
  Atlas.Common.Diagnostics.Adapters.LogFolder;

type
  TMemoryWriter = class(TInterfacedObject, IDiagnosticWriter)
  private
    FLines: TStrings;
  public
    constructor Create(ALines: TStrings);
    procedure WriteLine(const ALine: string);
  end;

  TRecordingObserver = class(TInterfacedObject, IJsonRpcRequestObserver)
  public
    Events: TArray<string>;
    procedure Started(const AMethod: string);
    procedure Finished(const AMethod: string; const AParams, AResult: TJSONValue; const AError: Exception;
      AQueueMs, AElapsedMs: Int64);
  end;

constructor TMemoryWriter.Create(ALines: TStrings);
begin
  inherited Create;
  FLines := ALines;
end;

procedure TMemoryWriter.WriteLine(const ALine: string);
begin
  FLines.Add(ALine);
end;

procedure TRecordingObserver.Started(const AMethod: string);
begin
  Events := Events + ['start ' + AMethod];
  TRequestDiagnostics.Open;
end;

procedure TRecordingObserver.Finished(const AMethod: string; const AParams, AResult: TJSONValue;
  const AError: Exception; AQueueMs, AElapsedMs: Int64);
var
  Notes: TRequestNotes;
begin
  Notes := TRequestDiagnostics.Close;
  if AError <> nil then
    Events := Events + ['error ' + AMethod + ' ' + AError.ClassName]
  else
    Events := Events + ['done ' + AMethod + ' ' + Notes.Reason];
end;

/// <summary>Über eine Interface-Variable, nicht TMemoryWriter.Create direkt an den const-Parameter.</summary>
function NewWriter(ALines: TStrings): IDiagnosticWriter;
begin
  Result := TMemoryWriter.Create(ALines);
end;

function NewFolder: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'atlas-diag-' + TGUID.NewGuid.ToString.Substring(1, 8));
  ForceDirectories(Result);
end;

function SampleRequest: TDiagnosticRequest;
begin
  Result := Default(TDiagnosticRequest);
  Result.Time := EncodeDateTime(2026, 10, 14, 12, 1, 3, 120);
  Result.Method := 'textDocument/completion';
  Result.ElapsedMs := 84;
  Result.QueueMs := 3;
  Result.Outcome := TDiagnosticOutcome.Ok;
  Result.Count := 37;
  Result.Document := 'doc#4';
  Result.Version := 17;
  Result.Length_ := 12840;
  Result.Checksum := '9A3F01C2';
  Result.Line := 212;
  Result.LineCount := 1180;
  Result.Column := 14;
  Result.Notes := ['ctx=memberAccess', 'syntaxErr=2'];
  Result.IndexUnits := 1569;
  Result.IndexLibrary := 1239;
  Result.IndexLoading := 63;
  Result.Resolve := 'unitNotFound';
end;

{ TDiagnosticLogTests }

procedure TDiagnosticLogTests.FilterRejectsPathsDrivesAndExtensions;
var
  Filter: TDiagnosticFilter;
begin
  Filter := TDiagnosticFilter.Create(nil);
  try
    Assert.IsFalse(Filter.Accept('open C:\Projekte\Kunde'));
    Assert.IsFalse(Filter.Accept('drive d: only'));
    Assert.IsFalse(Filter.Accept('share \\server\daten'));
    Assert.IsFalse(Filter.Accept('unix path src/main'));
    Assert.IsFalse(Filter.Accept('file Haupt.pas'));
    Assert.IsFalse(Filter.Accept('file Kunde.DPR'));
    Assert.IsFalse(Filter.Accept('file Kunde.dproj'));
    Assert.IsFalse(Filter.Accept('file Kunde.dpk'));
    Assert.IsFalse(Filter.Accept('include Defs.inc'));
    Assert.IsFalse(Filter.Accept('form Main.dfm'));
    Assert.IsFalse(Filter.Accept('mail a@b'));
  finally
    Filter.Free;
  end;
end;

procedure TDiagnosticLogTests.FilterRejectsUserAndMachineNames;
var
  Filter: TDiagnosticFilter;
begin
  Filter := TDiagnosticFilter.Create(['MaxMuster', 'RECHNER-07', 'ab']);
  try
    Assert.IsFalse(Filter.Accept('user maxmuster'));
    Assert.IsFalse(Filter.Accept('host Rechner-07 up'));
    // Kurze Einträge zählen nicht, sonst fiele fast jede Zeile weg.
    Assert.IsTrue(Filter.Accept('about ab'));
  finally
    Filter.Free;
  end;
end;

procedure TDiagnosticLogTests.FilterAllowsMethodNamesAndCodes;
var
  Filter: TDiagnosticFilter;
begin
  Filter := TDiagnosticFilter.Create(nil);
  try
    Assert.IsTrue(Filter.Accept('12:01:03.120 run start version 1.2.3 mem 40 MB threads 5'));
    Assert.IsFalse(Filter.Accept('12:01:03.120 textDocument/hover 3 ms ok:1'));
    Filter.Allowed := ['textDocument/hover'];
    Assert.IsTrue(Filter.Accept('12:01:03.120 textDocument/hover 3 ms ok:1'));
    Assert.IsTrue(Filter.Accept(TDiagnosticLog.FormatRequest(SampleRequest).Replace('textDocument/completion',
      'textDocument/hover')));
  finally
    Filter.Free;
  end;
end;

procedure TDiagnosticLogTests.ShortIdsAreStableWithinRun;
var
  Ids: TDiagnosticIds;
begin
  Ids := TDiagnosticIds.Create;
  try
    Assert.AreEqual('doc#1', Ids.IdOf(TDiagnosticIdKind.Document, 'C:\Kunde\Haupt.pas'));
    Assert.AreEqual('doc#2', Ids.IdOf(TDiagnosticIdKind.Document, 'C:\Kunde\Werkzeug.pas'));
    Assert.AreEqual('doc#1', Ids.IdOf(TDiagnosticIdKind.Document, 'c:/kunde/haupt.pas'));
    Assert.AreEqual('proj#1', Ids.IdOf(TDiagnosticIdKind.Project, 'C:\Kunde\Kunde.dproj'));
    Assert.AreEqual('unit#1', Ids.IdOf(TDiagnosticIdKind.UnitFile, 'C:\Kunde\Haupt.pas'));
    Assert.AreEqual<NativeInt>(4, Length(Ids.MapLines));
  finally
    Ids.Free;
  end;
end;

procedure TDiagnosticLogTests.LibraryUnitsKeepTheirName;
var
  Ids: TDiagnosticIds;
begin
  Ids := TDiagnosticIds.Create;
  try
    Ids.SetLibraryRoots(['C:\Delphi']);
    Assert.AreEqual('System.SysUtils', Ids.UnitLabel('System.SysUtils', 'C:\Delphi\source\rtl\System.SysUtils.pas'));
    // Gleicher Name außerhalb der Installation: nicht am Namen erkannt.
    Assert.AreEqual('unit#1', Ids.UnitLabel('System.SysUtils', 'C:\Kunde\System.SysUtils.pas'));
  finally
    Ids.Free;
  end;
end;

procedure TDiagnosticLogTests.StackFrameDropsSourceFile;
begin
  Assert.AreEqual('AtlasServer.exe+$1A2B Shell.Composition.TServerComposition.Run line 512',
    TDiagnosticFilter.StackFrame('  AtlasServer.exe+$1A2B Shell.Composition.TServerComposition.Run (Shell.Composition.pas:512)'));
  Assert.AreEqual('$0040ABCD', TDiagnosticFilter.StackFrame('$0040ABCD'));
end;

procedure TDiagnosticLogTests.RequestScopeCollectsCodes;
var
  Notes: TRequestNotes;
begin
  TRequestDiagnostics.Open;
  Assert.IsTrue(TRequestDiagnostics.IsOpen);
  TRequestDiagnostics.Reason('noTarget');
  TRequestDiagnostics.DefaultReason('noSymbol');
  TRequestDiagnostics.ResolveFailed('unitNotFound');
  TRequestDiagnostics.ResolveFailed('memberNotFound');
  TRequestDiagnostics.Note('ctx', 'scope');
  TRequestDiagnostics.Note('ctx', 'memberAccess');
  TRequestDiagnostics.Note('inString', False);
  TRequestDiagnostics.Increment('missingUnits');
  TRequestDiagnostics.Increment('missingUnits');
  TRequestDiagnostics.ResultCount(12);
  Notes := TRequestDiagnostics.Close;
  Assert.IsFalse(TRequestDiagnostics.IsOpen);
  Assert.AreEqual('noTarget', Notes.Reason);
  Assert.AreEqual('unitNotFound', Notes.Resolve);
  Assert.AreEqual(12, Notes.Count);
  Assert.AreEqual('ctx=memberAccess inString=false missingUnits=2', string.Join(' ', Notes.Notes));
end;

procedure TDiagnosticLogTests.RequestScopeKeepsSlowest;
var
  Notes: TRequestNotes;
begin
  TRequestDiagnostics.Open;
  TRequestDiagnostics.Slowest('slowRule', 'erste', 120);
  TRequestDiagnostics.Slowest('slowRule', 'kurz', 80);
  TRequestDiagnostics.Slowest('slowRule', 'lang', 900);
  TRequestDiagnostics.Slowest('slowRule', 'gleich', 900);
  Notes := TRequestDiagnostics.Close;
  Assert.AreEqual('slowRule=lang slowRuleMs=900', string.Join(' ', Notes.Notes));
end;

procedure TDiagnosticLogTests.RequestScopeWithoutOpenDoesNothing;
var
  Notes: TRequestNotes;
begin
  TRequestDiagnostics.Reason('noTarget');
  TRequestDiagnostics.Note('ctx', 'scope');
  Notes := TRequestDiagnostics.Close;
  Assert.AreEqual('', Notes.Reason);
  Assert.AreEqual(-1, Notes.Count);
  Assert.AreEqual<NativeInt>(0, Length(Notes.Notes));
end;

procedure TDiagnosticLogTests.FormatsRequestLine;
begin
  Assert.AreEqual('12:01:03.120 textDocument/completion 84 ms queue 3 ms ok:37 doc#4 v17 len 12840 crc 9A3F01C2 ' +
    'line 212 of 1180 col 14 ctx=memberAccess syntaxErr=2 index units 1569 lib 1239 loading 63 % resolve unitNotFound',
    TDiagnosticLog.FormatRequest(SampleRequest));
end;

procedure TDiagnosticLogTests.EmptyResultWithoutReasonIsMarked;
var
  Request: TDiagnosticRequest;
begin
  Request := SampleRequest;
  Request.Outcome := TDiagnosticOutcome.Empty;
  Request.Reason := '';
  Assert.Contains(TDiagnosticLog.FormatRequest(Request), ' empty:unspecified ');
  Request.Reason := 'noCandidates';
  Assert.Contains(TDiagnosticLog.FormatRequest(Request), ' empty:noCandidates ');
end;

procedure TDiagnosticLogTests.BuffersUntilConfigured;
var
  Lines: TStringList;
  Log: IDiagnosticLog;
begin
  Lines := TStringList.Create;
  try
    Log := TDiagnosticLog.Create(NewWriter(Lines), TDiagnosticFilter.Create(nil));
    Log.LogEvent('first');
    Assert.AreEqual(0, Lines.Count);
    Log.Configure(True);
    Assert.AreEqual(1, Lines.Count);
    Log.LogEvent('second');
    Assert.AreEqual(2, Lines.Count);
    Log := nil;
  finally
    Lines.Free;
  end;
end;

procedure TDiagnosticLogTests.DisabledLogWritesNothing;
var
  Lines: TStringList;
  Log: IDiagnosticLog;
  Process: TDiagnosticProcess;
begin
  Lines := TStringList.Create;
  try
    Log := TDiagnosticLog.Create(NewWriter(Lines), TDiagnosticFilter.Create(nil));
    Process := Default(TDiagnosticProcess);
    Log.LogStart('1.0', Process);
    Log.Configure(False);
    Log.LogRequest(SampleRequest);
    Log.LogEnd(TDiagnosticEndReason.Clean, 0, Process);
    Assert.AreEqual(0, Lines.Count);
    Assert.IsFalse(Log.Enabled);
    Log := nil;
  finally
    Lines.Free;
  end;
end;

procedure TDiagnosticLogTests.EndLineHasReason;
var
  Lines: TStringList;
  Log: TDiagnosticLog;
  Ref: IDiagnosticLog;
  Process: TDiagnosticProcess;
begin
  Lines := TStringList.Create;
  try
    Log := TDiagnosticLog.Create(NewWriter(Lines), TDiagnosticFilter.Create(nil));
    Ref := Log;
    Log.Configure(True);
    Process.MemoryBytes := 50 * 1024 * 1024;
    Process.Threads := 7;
    Log.LogEnd(TDiagnosticEndReason.ParentExited, 0, Process);
    Log.LogEnd(TDiagnosticEndReason.Exception_, 1, Process, 'EAccessViolation',
      'AtlasServer.exe+$10 Shell.Composition.TServerComposition.Run (Shell.Composition.pas:9)'#13#10 +
      'C:\Kunde\Fremd.exe+$20');
    Assert.AreEqual(3, Lines.Count);
    Assert.Contains(Lines[0], 'run end reason parentExited exit 0 mem 50 MB threads 7');
    Assert.Contains(Lines[1], 'run end reason exception exit 1');
    Assert.Contains(Lines[1], 'exception EAccessViolation');
    Assert.AreEqual('  at AtlasServer.exe+$10 Shell.Composition.TServerComposition.Run line 9', Lines[2]);
    // Der Rahmen mit Pfad wird verworfen, die übrigen bleiben.
    Assert.AreEqual(1, Log.Dropped);
    Ref := nil;
  finally
    Lines.Free;
  end;
end;

procedure TDiagnosticLogTests.DroppedLinesAreCounted;
var
  Lines: TStringList;
  Log: IDiagnosticLog;
  Process: TDiagnosticProcess;
begin
  Lines := TStringList.Create;
  try
    Log := TDiagnosticLog.Create(NewWriter(Lines), TDiagnosticFilter.Create(nil));
    Log.Configure(True);
    Log.LogEvent('opened C:\Kunde\Haupt.pas');
    Log.LogEvent('opened doc#1');
    Process := Default(TDiagnosticProcess);
    Log.LogEnd(TDiagnosticEndReason.Clean, 0, Process);
    Assert.AreEqual(2, Lines.Count);
    Assert.Contains(Lines[1], 'dropped 1');
    Log := nil;
  finally
    Lines.Free;
  end;
end;

procedure TDiagnosticLogTests.LoggingCostsLessThanOneMillisecond;
const
  Rounds = 2000;
var
  Lines: TStringList;
  Log: TDiagnosticLog;
  Ref: IDiagnosticLog;
  Watch: TStopwatch;
  Index: Integer;
begin
  Lines := TStringList.Create;
  try
    Log := TDiagnosticLog.Create(NewWriter(Lines), TDiagnosticFilter.Create(['MaxMuster', 'RECHNER-07']));
    Ref := Log;
    Log.Filter.Allowed := ['textDocument/completion'];
    Log.Configure(True);
    Watch := TStopwatch.StartNew;
    for Index := 1 to Rounds do
    begin
      TRequestDiagnostics.Open;
      TRequestDiagnostics.Note('ctx', 'memberAccess');
      TRequestDiagnostics.Close;
      Log.LogRequest(SampleRequest);
    end;
    Assert.AreEqual(Rounds, Lines.Count);
    Assert.IsTrue(Watch.Elapsed.TotalMilliseconds / Rounds < 1,
      Format('%.3f ms je Anfrage', [Watch.Elapsed.TotalMilliseconds / Rounds]));
    Ref := nil;
  finally
    Lines.Free;
  end;
end;

procedure TDiagnosticLogTests.LogFolderReportsRunsWithoutEnd;
var
  Folder: string;
  First, Second: TDiagnosticLogFolder;
  FirstRef, SecondRef: IDiagnosticWriter;
  Files: TArray<string>;
begin
  Folder := NewFolder;
  try
    // Marke eines früheren Laufs, der ohne Ende aufhörte (Datei nicht mehr offen).
    TFile.WriteAllText(TPath.Combine(Folder, 'run-111.open'), '');
    First := TDiagnosticLogFolder.Create(Folder, '222');
    FirstRef := First;
    Assert.AreEqual(1, First.BeginRun);
    // Ein noch laufender Server hält seine Marke offen: Sie zählt nicht als abgebrochen.
    Second := TDiagnosticLogFolder.Create(Folder, '333');
    SecondRef := Second;
    Assert.AreEqual(0, Second.BeginRun);
    First.WriteLine('line one');
    Files := TDirectory.GetFiles(Folder, TDiagnosticLogFolder.FilePattern);
    Assert.AreEqual<NativeInt>(1, Length(Files));
    Assert.Contains(ExtractFileName(Files[0]), '-222.log');
    First.EndRun;
    Second.EndRun;
    Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(Folder, TDiagnosticLogFolder.MarkerPattern)));
    FirstRef := nil;
    SecondRef := nil;
    Assert.AreEqual('line one', Trim(TFile.ReadAllText(Files[0], TEncoding.UTF8)));
  finally
    TDirectory.Delete(Folder, True);
  end;
end;

procedure TDiagnosticLogTests.LogFolderRemovesOldFiles;
var
  Folder, Old, Map, Fresh: string;
  Writer: TDiagnosticLogFolder;
  Ref: IDiagnosticWriter;
begin
  Folder := NewFolder;
  try
    Old := TPath.Combine(Folder, 'diag-20260101-1.log');
    Map := TPath.Combine(Folder, 'diag-map-20260101-1.txt');
    Fresh := TPath.Combine(Folder, 'diag-20261014-1.log');
    TFile.WriteAllText(Old, 'x');
    TFile.WriteAllText(Map, 'x');
    TFile.WriteAllText(Fresh, 'x');
    TFile.SetLastWriteTime(Old, IncDay(Now, -10));
    TFile.SetLastWriteTime(Map, IncDay(Now, -10));
    Writer := TDiagnosticLogFolder.Create(Folder, '1');
    Ref := Writer;
    Writer.Cleanup(7);
    Assert.IsFalse(FileExists(Old));
    Assert.IsFalse(FileExists(Map));
    Assert.IsTrue(FileExists(Fresh));
    Ref := nil;
  finally
    TDirectory.Delete(Folder, True);
  end;
end;

procedure TDiagnosticLogTests.DispatcherReportsRequestsToObserver;
var
  Dispatcher: TJsonRpcDispatcher;
  Observer: TRecordingObserver;
  Ref: IJsonRpcRequestObserver;
  Message: TJSONObject;
begin
  Observer := TRecordingObserver.Create;
  Ref := Observer;
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Dispatcher.Observer := Ref;
    Dispatcher.RegisterRequest('test/empty',
      function(const AParams: TJSONValue): TJSONValue
      begin
        TRequestDiagnostics.Reason('noTarget');
        Result := TJSONNull.Create;
      end);
    Dispatcher.RegisterRequest('test/fail',
      function(const AParams: TJSONValue): TJSONValue
      begin
        if AParams = nil then
          raise EConvertError.Create('Kunde');
        Result := TJSONNull.Create;
      end);
    Message := TJSONObject.ParseJSONValue('{"jsonrpc": "2.0", "id": 1, "method": "test/empty"}') as TJSONObject;
    try
      Dispatcher.DispatchMessage(Message).Free;
    finally
      Message.Free;
    end;
    Message := TJSONObject.ParseJSONValue('{"jsonrpc": "2.0", "id": 2, "method": "test/fail"}') as TJSONObject;
    try
      Dispatcher.DispatchMessage(Message).Free;
    finally
      Message.Free;
    end;
    Assert.AreEqual('start test/empty|done test/empty noTarget|start test/fail|error test/fail EConvertError',
      string.Join('|', Observer.Events));
    Assert.AreEqual<NativeInt>(2, Length(Dispatcher.Methods));
  finally
    Dispatcher.Free;
  end;
  Ref := nil;
end;

procedure TDiagnosticLogTests.ServerLogHidesPathsAndNames;
var
  Anonymizer: ILogAnonymizer;
  Line: string;
begin
  // Server-Log (--log) anonym (#647): Pfade, Projekt-, Unit- und Benutzernamen.
  Anonymizer := TLogAnonymizer.Create(['mmuster']);
  Anonymizer.AddNames(['Kundenverwaltung']);
  Anonymizer.AddUnit('Firma.Kunden', 'C:\Projekte\Firma.Kunden.pas');
  Line := Anonymizer.Anonymize('Symbolindex für Kundenverwaltung (Debug, Win64): Cache C:\Users\mmuster\AppData\k.idx');
  Assert.AreEqual('Symbolindex für name#1 (Debug, Win64): Cache datei#1.idx', Line);
  Assert.AreEqual('name#2.TKunde fehlt', Anonymizer.Anonymize('Firma.Kunden.TKunde fehlt'));
  // Pfad mit Leerzeichen ohne Anführungszeichen: auch der Rest verschwindet.
  Line := Anonymizer.Anonymize('Projekt C:\Work Space\Haupt.dproj nicht lesbar');
  Assert.AreEqual(0, Pos('\', Line), Line);
  Assert.AreEqual(0, Pos('Haupt', Line), Line);
  Line := Anonymizer.Anonymize('didOpen file:///c%3A/Projekte/Haupt.pas von mmuster');
  Assert.AreEqual('didOpen datei#4.pas von benutzer#1', Line);
end;

procedure TDiagnosticLogTests.ServerLogKeepsLibraryUnitsAndNumbers;
var
  Anonymizer: ILogAnonymizer;
begin
  Anonymizer := TLogAnonymizer.Create(nil);
  Anonymizer.SetLibraryRoots(['C:\Program Files\Embarcadero\Studio\37.0']);
  Assert.AreEqual('Unit "Vcl.Forms.pas" geladen',
    Anonymizer.Anonymize('Unit "C:\Program Files\Embarcadero\Studio\37.0\source\vcl\Vcl.Forms.pas" geladen'));
  Assert.AreEqual('Stufe "wert#1", Methode "textDocument/hover" nach "1234" ms',
    Anonymizer.Anonymize('Stufe "verbose", Methode "textDocument/hover" nach "1234" ms'));
end;

const
  AnonymizeLine = 'Symbolindex für Kundenverwaltung: "C:\Projekte\Haupt.pas" Firma.Kunden.TKunde nach "12" ms';
  AnonymizedLine = 'Symbolindex für name#1: "datei#1.pas" name#2.TKunde nach "12" ms';

function NewAnonymizer: ILogAnonymizer;
begin
  Result := TLogAnonymizer.Create(['mmuster']);
  Result.AddNames(['Kundenverwaltung']);
  Result.AddUnit('Firma.Kunden', 'C:\Projekte\Firma.Kunden.pas');
end;

procedure TDiagnosticLogTests.AnonymizeManyLinesSameLabels;
const
  Lines = 2000;
var
  Anonymizer: ILogAnonymizer;
  Watch: TStopwatch;
  Index: Integer;
begin
  Anonymizer := NewAnonymizer;
  Watch := TStopwatch.StartNew;
  for Index := 1 to Lines do
    Assert.AreEqual(AnonymizedLine, Anonymizer.Anonymize(AnonymizeLine));
  Watch.Stop;
  Assert.IsTrue(Watch.ElapsedMilliseconds < Lines, Format('%d ms für %d Zeilen', [Watch.ElapsedMilliseconds, Lines]));
  // Ein langer Text mit vielen Treffern (TStringBuilder statt Anhängen) bleibt vollständig.
  Assert.AreEqual(DupeString(AnonymizedLine + ' ', 50), Anonymizer.Anonymize(DupeString(AnonymizeLine + ' ', 50)));
end;

/// <summary>Thread, der ACount Mal AAnonymizer auf AnonymizeLine anwendet und Abweichungen in AFailures^ zählt.
/// </summary>
function AnonymizeThread(const AAnonymizer: ILogAnonymizer; ACount: Integer; AFailures: PInteger): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      Index: Integer;
    begin
      for Index := 1 to ACount do
        try
          if AAnonymizer.Anonymize(AnonymizeLine) <> AnonymizedLine then
            TInterlocked.Increment(AFailures^);
        except
          TInterlocked.Increment(AFailures^);
        end;
    end);
  Result.FreeOnTerminate := False;
end;

procedure TDiagnosticLogTests.AnonymizeConcurrent;
const
  ThreadCount = 4;
  PerThread = 200;
var
  Anonymizer: ILogAnonymizer;
  Failures: Integer;
  Threads: array[0..ThreadCount - 1] of TThread;
  Number: Integer;
begin
  Anonymizer := NewAnonymizer;
  Failures := 0;
  for Number := 0 to ThreadCount - 1 do
    Threads[Number] := AnonymizeThread(Anonymizer, PerThread, @Failures);
  try
    for Number := 0 to ThreadCount - 1 do
      Threads[Number].Start;
    for Number := 0 to ThreadCount - 1 do
      Threads[Number].WaitFor;
  finally
    for Number := 0 to ThreadCount - 1 do
      Threads[Number].Free;
  end;
  Assert.AreEqual(0, Failures);
  Assert.AreEqual(AnonymizedLine, Anonymizer.Anonymize(AnonymizeLine));
end;

{ TShutdownLeaksTests }

procedure TShutdownLeaksTests.CountsAllocatedMemory;
var
  Before: Int64;
  Block: Pointer;
begin
  Before := TShutdownLeaks.AllocatedBytes;
  GetMem(Block, 100000);
  try
    Assert.IsTrue(TShutdownLeaks.AllocatedBytes - Before >= 100000);
  finally
    FreeMem(Block);
  end;
  Assert.IsTrue(TShutdownLeaks.AllocatedBytes - Before < 100000);
end;

procedure TShutdownLeaksTests.DescribesWithoutNames;
begin
  Assert.AreEqual('Speicherrest beim Beenden: 128 Bytes', TShutdownLeaks.Describe(128));
end;

initialization
  TDUnitX.RegisterTestFixture(TDiagnosticLogTests);
  TDUnitX.RegisterTestFixture(TShutdownLeaksTests);

end.
