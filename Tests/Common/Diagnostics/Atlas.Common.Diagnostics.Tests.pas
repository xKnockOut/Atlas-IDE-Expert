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
    /// <summary>#1094: Unit und Regel bleiben bis zum Ende offen, Fehlschläge stehen als Notiz.</summary>
    [Test]
    procedure RequestScopeNamesFailingUnitAndRule;
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
    [Category('Benchmark')]
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
    /// <summary>Die einmal übersetzten Muster liefern über viele Zeilen dieselben Marken;
    /// 2000 Zeilen bleiben deutlich unter einer Millisekunde je Zeile.</summary>
    [Test]
    procedure AnonymizeManyLinesSameLabels;
    /// <summary>Die geteilten TRegEx-Instanzen laufen nur unter der Sperre; parallele
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
  mNotes: TRequestNotes;
begin
  mNotes := TRequestDiagnostics.Close;
  if AError <> nil then
  begin
    Events := Events + ['error ' + AMethod + ' ' + AError.ClassName];
  end
  else
  begin
    Events := Events + ['done ' + AMethod + ' ' + mNotes.Reason];
  end;
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
  mFilter: TDiagnosticFilter;
begin
  mFilter := TDiagnosticFilter.Create(nil);
  try
    Assert.IsFalse(mFilter.Accept('open C:\Projekte\Kunde'));
    Assert.IsFalse(mFilter.Accept('drive d: only'));
    Assert.IsFalse(mFilter.Accept('share \\server\daten'));
    Assert.IsFalse(mFilter.Accept('unix path src/main'));
    Assert.IsFalse(mFilter.Accept('file Haupt.pas'));
    Assert.IsFalse(mFilter.Accept('file Kunde.DPR'));
    Assert.IsFalse(mFilter.Accept('file Kunde.dproj'));
    Assert.IsFalse(mFilter.Accept('file Kunde.dpk'));
    Assert.IsFalse(mFilter.Accept('include Defs.inc'));
    Assert.IsFalse(mFilter.Accept('form Main.dfm'));
    Assert.IsFalse(mFilter.Accept('mail a@b'));
  finally
    mFilter.Free;
  end;
end;

procedure TDiagnosticLogTests.FilterRejectsUserAndMachineNames;
var
  mFilter: TDiagnosticFilter;
begin
  mFilter := TDiagnosticFilter.Create(['MaxMuster', 'RECHNER-07', 'ab']);
  try
    Assert.IsFalse(mFilter.Accept('user maxmuster'));
    Assert.IsFalse(mFilter.Accept('host Rechner-07 up'));
    // Kurze Einträge zählen nicht, sonst fiele fast jede Zeile weg.
    Assert.IsTrue(mFilter.Accept('about ab'));
  finally
    mFilter.Free;
  end;
end;

procedure TDiagnosticLogTests.FilterAllowsMethodNamesAndCodes;
var
  mFilter: TDiagnosticFilter;
begin
  mFilter := TDiagnosticFilter.Create(nil);
  try
    Assert.IsTrue(mFilter.Accept('12:01:03.120 run start version 1.2.3 mem 40 MB threads 5'));
    Assert.IsFalse(mFilter.Accept('12:01:03.120 textDocument/hover 3 ms ok:1'));
    mFilter.Allowed := ['textDocument/hover'];
    Assert.IsTrue(mFilter.Accept('12:01:03.120 textDocument/hover 3 ms ok:1'));
    Assert.IsTrue(mFilter.Accept(TDiagnosticLog.FormatRequest(SampleRequest).Replace('textDocument/completion',
      'textDocument/hover')));
  finally
    mFilter.Free;
  end;
end;

procedure TDiagnosticLogTests.ShortIdsAreStableWithinRun;
var
  mIds: TDiagnosticIds;
begin
  mIds := TDiagnosticIds.Create;
  try
    Assert.AreEqual('doc#1', mIds.IdOf(TDiagnosticIdKind.Document, 'C:\Kunde\Haupt.pas'));
    Assert.AreEqual('doc#2', mIds.IdOf(TDiagnosticIdKind.Document, 'C:\Kunde\Werkzeug.pas'));
    Assert.AreEqual('doc#1', mIds.IdOf(TDiagnosticIdKind.Document, 'c:/kunde/haupt.pas'));
    Assert.AreEqual('proj#1', mIds.IdOf(TDiagnosticIdKind.Project, 'C:\Kunde\Kunde.dproj'));
    Assert.AreEqual('unit#1', mIds.IdOf(TDiagnosticIdKind.UnitFile, 'C:\Kunde\Haupt.pas'));
    Assert.AreEqual<NativeInt>(4, Length(mIds.MapLines));
  finally
    mIds.Free;
  end;
end;

procedure TDiagnosticLogTests.LibraryUnitsKeepTheirName;
var
  mIds: TDiagnosticIds;
begin
  mIds := TDiagnosticIds.Create;
  try
    mIds.SetLibraryRoots(['C:\Delphi']);
    Assert.AreEqual('System.SysUtils', mIds.UnitLabel('System.SysUtils', 'C:\Delphi\source\rtl\System.SysUtils.pas'));
    // Gleicher Name außerhalb der Installation: nicht am Namen erkannt.
    Assert.AreEqual('unit#1', mIds.UnitLabel('System.SysUtils', 'C:\Kunde\System.SysUtils.pas'));
  finally
    mIds.Free;
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
  mNotes: TRequestNotes;
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
  mNotes := TRequestDiagnostics.Close;
  Assert.IsFalse(TRequestDiagnostics.IsOpen);
  Assert.AreEqual('noTarget', mNotes.Reason);
  Assert.AreEqual('unitNotFound', mNotes.Resolve);
  Assert.AreEqual(12, Integer(mNotes.Count));
  Assert.AreEqual('ctx=memberAccess inString=false missingUnits=2', string.Join(' ', mNotes.Notes));
end;

procedure TDiagnosticLogTests.RequestScopeKeepsSlowest;
var
  mNotes: TRequestNotes;
begin
  TRequestDiagnostics.Open;
  TRequestDiagnostics.Slowest('slowRule', 'erste', 120);
  TRequestDiagnostics.Slowest('slowRule', 'kurz', 80);
  TRequestDiagnostics.Slowest('slowRule', 'lang', 900);
  TRequestDiagnostics.Slowest('slowRule', 'gleich', 900);
  mNotes := TRequestDiagnostics.Close;
  Assert.AreEqual('slowRule=lang slowRuleMs=900', string.Join(' ', mNotes.Notes));
end;

procedure TDiagnosticLogTests.RequestScopeNamesFailingUnitAndRule;
var
  mNotes: TRequestNotes;
begin
  TRequestDiagnostics.Open;
  TRequestDiagnostics.Subject('unit#4');
  TRequestDiagnostics.CurrentRule('hides-virtual');
  TRequestDiagnostics.RuleFailed('hides-virtual', 'EStackOverflow');
  TRequestDiagnostics.CurrentRule('');
  TRequestDiagnostics.UnitFailed('EAccessViolation');
  TRequestDiagnostics.Subject('unit#9');
  TRequestDiagnostics.TreeTooDeep(1200);
  TRequestDiagnostics.CurrentRule('empty-except');
  mNotes := TRequestDiagnostics.Close;
  Assert.AreEqual('failedRules=1 failRule=hides-virtual failRuleUnit=unit#4 failRuleClass=EStackOverflow ' +
    'failedUnits=1 failUnit=unit#4 failUnitClass=EAccessViolation deepUnits=1 deepUnit=unit#9 deepUnitDepth=1200',
    string.Join(' ', mNotes.Notes));
  // Beim Schließen noch offen: so nennt das Diagnoselog bei einem Fehler Unit und Regel.
  Assert.AreEqual('unit#9', mNotes.Subject);
  Assert.AreEqual('empty-except', mNotes.Rule);
  // Ohne offenen Bereich wirkungslos.
  TRequestDiagnostics.Subject('unit#1');
  TRequestDiagnostics.RuleFailed('x', 'Exception');
  mNotes := TRequestDiagnostics.Close;
  Assert.AreEqual('', mNotes.Subject);
  Assert.AreEqual<NativeInt>(0, Length(mNotes.Notes));
end;

procedure TDiagnosticLogTests.RequestScopeWithoutOpenDoesNothing;
var
  mNotes: TRequestNotes;
begin
  TRequestDiagnostics.Reason('noTarget');
  TRequestDiagnostics.Note('ctx', 'scope');
  mNotes := TRequestDiagnostics.Close;
  Assert.AreEqual('', mNotes.Reason);
  Assert.AreEqual(-1, Integer(mNotes.Count));
  Assert.AreEqual<NativeInt>(0, Length(mNotes.Notes));
end;

procedure TDiagnosticLogTests.FormatsRequestLine;
begin
  Assert.AreEqual('12:01:03.120 textDocument/completion 84 ms queue 3 ms ok:37 doc#4 v17 len 12840 crc 9A3F01C2 ' +
    'line 212 of 1180 col 14 ctx=memberAccess syntaxErr=2 index units 1569 lib 1239 loading 63 % resolve unitNotFound',
    TDiagnosticLog.FormatRequest(SampleRequest));
end;

procedure TDiagnosticLogTests.EmptyResultWithoutReasonIsMarked;
var
  mRequest: TDiagnosticRequest;
begin
  mRequest := SampleRequest;
  mRequest.Outcome := TDiagnosticOutcome.Empty;
  mRequest.Reason := '';
  Assert.Contains(TDiagnosticLog.FormatRequest(mRequest), ' empty:unspecified ');
  mRequest.Reason := 'noCandidates';
  Assert.Contains(TDiagnosticLog.FormatRequest(mRequest), ' empty:noCandidates ');
end;

procedure TDiagnosticLogTests.BuffersUntilConfigured;
var
  mLines: TStringList;
  mLog: IDiagnosticLog;
begin
  mLines := TStringList.Create;
  try
    mLog := TDiagnosticLog.Create(NewWriter(mLines), TDiagnosticFilter.Create(nil));
    mLog.LogEvent('first');
    Assert.AreEqual(0, Integer(mLines.Count));
    mLog.Configure(True);
    Assert.AreEqual(1, Integer(mLines.Count));
    mLog.LogEvent('second');
    Assert.AreEqual(2, Integer(mLines.Count));
    mLog := nil;
  finally
    mLines.Free;
  end;
end;

procedure TDiagnosticLogTests.DisabledLogWritesNothing;
var
  mLines: TStringList;
  mLog: IDiagnosticLog;
  mProcess: TDiagnosticProcess;
begin
  mLines := TStringList.Create;
  try
    mLog := TDiagnosticLog.Create(NewWriter(mLines), TDiagnosticFilter.Create(nil));
    mProcess := Default(TDiagnosticProcess);
    mLog.LogStart('1.0', mProcess);
    mLog.Configure(False);
    mLog.LogRequest(SampleRequest);
    mLog.LogEnd(TDiagnosticEndReason.Clean, 0, mProcess);
    Assert.AreEqual(0, Integer(mLines.Count));
    Assert.IsFalse(mLog.Enabled);
    mLog := nil;
  finally
    mLines.Free;
  end;
end;

procedure TDiagnosticLogTests.EndLineHasReason;
var
  mLines: TStringList;
  mLog: TDiagnosticLog;
  mRef: IDiagnosticLog;
  mProcess: TDiagnosticProcess;
begin
  mLines := TStringList.Create;
  try
    mLog := TDiagnosticLog.Create(NewWriter(mLines), TDiagnosticFilter.Create(nil));
    mRef := mLog;
    mLog.Configure(True);
    mProcess.MemoryBytes := 50 * 1024 * 1024;
    mProcess.Threads := 7;
    mLog.LogEnd(TDiagnosticEndReason.ParentExited, 0, mProcess);
    mLog.LogEnd(TDiagnosticEndReason.Exception_, 1, mProcess, 'EAccessViolation',
      'AtlasServer.exe+$10 Shell.Composition.TServerComposition.Run (Shell.Composition.pas:9)'#13#10 +
      'C:\Kunde\Fremd.exe+$20');
    Assert.AreEqual(3, Integer(mLines.Count));
    Assert.Contains(mLines[0], 'run end reason parentExited exit 0 mem 50 MB threads 7');
    Assert.Contains(mLines[1], 'run end reason exception exit 1');
    Assert.Contains(mLines[1], 'exception EAccessViolation');
    Assert.AreEqual('  at AtlasServer.exe+$10 Shell.Composition.TServerComposition.Run line 9', mLines[2]);
    // Der Rahmen mit Pfad wird verworfen, die übrigen bleiben.
    Assert.AreEqual(1, mLog.Dropped);
    mRef := nil;
  finally
    mLines.Free;
  end;
end;

procedure TDiagnosticLogTests.DroppedLinesAreCounted;
var
  mLines: TStringList;
  mLog: IDiagnosticLog;
  mProcess: TDiagnosticProcess;
begin
  mLines := TStringList.Create;
  try
    mLog := TDiagnosticLog.Create(NewWriter(mLines), TDiagnosticFilter.Create(nil));
    mLog.Configure(True);
    mLog.LogEvent('opened C:\Kunde\Haupt.pas');
    mLog.LogEvent('opened doc#1');
    mProcess := Default(TDiagnosticProcess);
    mLog.LogEnd(TDiagnosticEndReason.Clean, 0, mProcess);
    Assert.AreEqual(2, Integer(mLines.Count));
    Assert.Contains(mLines[1], 'dropped 1');
    mLog := nil;
  finally
    mLines.Free;
  end;
end;

procedure TDiagnosticLogTests.LoggingCostsLessThanOneMillisecond;
const
  cRounds = 2000;
var
  mLines: TStringList;
  mLog: TDiagnosticLog;
  mRef: IDiagnosticLog;
  mWatch: TStopwatch;
  mIndex: Integer;
begin
  mLines := TStringList.Create;
  try
    mLog := TDiagnosticLog.Create(NewWriter(mLines), TDiagnosticFilter.Create(['MaxMuster', 'RECHNER-07']));
    mRef := mLog;
    mLog.Filter.Allowed := ['textDocument/completion'];
    mLog.Configure(True);
    mWatch := TStopwatch.StartNew;
    for mIndex := 1 to cRounds do
    begin
      TRequestDiagnostics.Open;
      TRequestDiagnostics.Note('ctx', 'memberAccess');
      TRequestDiagnostics.Close;
      mLog.LogRequest(SampleRequest);
    end;
    Assert.AreEqual(cRounds, Integer(mLines.Count));
    Assert.IsTrue(mWatch.Elapsed.TotalMilliseconds / cRounds < 1,
      Format('%.3f ms je Anfrage', [mWatch.Elapsed.TotalMilliseconds / cRounds]));
    mRef := nil;
  finally
    mLines.Free;
  end;
end;

procedure TDiagnosticLogTests.LogFolderReportsRunsWithoutEnd;
var
  mFolder: string;
  mFirst, mSecond: TDiagnosticLogFolder;
  mFirstRef, mSecondRef: IDiagnosticWriter;
  mFiles: TArray<string>;
begin
  mFolder := NewFolder;
  try
    // Marke eines früheren Laufs, der ohne Ende aufhörte (Datei nicht mehr offen).
    TFile.WriteAllText(TPath.Combine(mFolder, 'run-111.open'), '');
    mFirst := TDiagnosticLogFolder.Create(mFolder, '222');
    mFirstRef := mFirst;
    Assert.AreEqual(1, mFirst.BeginRun);
    // Ein noch laufender Server hält seine Marke offen: Sie zählt nicht als abgebrochen.
    mSecond := TDiagnosticLogFolder.Create(mFolder, '333');
    mSecondRef := mSecond;
    Assert.AreEqual(0, mSecond.BeginRun);
    mFirst.WriteLine('line one');
    mFiles := TDirectory.GetFiles(mFolder, TDiagnosticLogFolder.cFilePattern);
    Assert.AreEqual<NativeInt>(1, Length(mFiles));
    Assert.Contains(ExtractFileName(mFiles[0]), '-222.log');
    mFirst.EndRun;
    mSecond.EndRun;
    Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(mFolder, TDiagnosticLogFolder.cMarkerPattern)));
    mFirstRef := nil;
    mSecondRef := nil;
    Assert.AreEqual('line one', Trim(TFile.ReadAllText(mFiles[0], TEncoding.UTF8)));
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TDiagnosticLogTests.LogFolderRemovesOldFiles;
var
  mFolder, mOld, mMap, mFresh: string;
  mWriter: TDiagnosticLogFolder;
  mRef: IDiagnosticWriter;
begin
  mFolder := NewFolder;
  try
    mOld := TPath.Combine(mFolder, 'diag-20260101-1.log');
    mMap := TPath.Combine(mFolder, 'diag-map-20260101-1.txt');
    mFresh := TPath.Combine(mFolder, 'diag-20261014-1.log');
    TFile.WriteAllText(mOld, 'x');
    TFile.WriteAllText(mMap, 'x');
    TFile.WriteAllText(mFresh, 'x');
    TFile.SetLastWriteTime(mOld, IncDay(Now, -10));
    TFile.SetLastWriteTime(mMap, IncDay(Now, -10));
    mWriter := TDiagnosticLogFolder.Create(mFolder, '1');
    mRef := mWriter;
    mWriter.Cleanup(7);
    Assert.IsFalse(FileExists(mOld));
    Assert.IsFalse(FileExists(mMap));
    Assert.IsTrue(FileExists(mFresh));
    mRef := nil;
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TDiagnosticLogTests.DispatcherReportsRequestsToObserver;
var
  mDispatcher: TJsonRpcDispatcher;
  mObserver: TRecordingObserver;
  mRef: IJsonRpcRequestObserver;
  mMessage: TJSONObject;
begin
  mObserver := TRecordingObserver.Create;
  mRef := mObserver;
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mDispatcher.Observer := mRef;
    mDispatcher.RegisterRequest('test/empty',
      function(const AParams: TJSONValue): TJSONValue
      begin
        TRequestDiagnostics.Reason('noTarget');
        Result := TJSONNull.Create;
      end);
    mDispatcher.RegisterRequest('test/fail',
      function(const AParams: TJSONValue): TJSONValue
      begin
        if AParams = nil then
        begin
          raise EConvertError.Create('Kunde');
        end;
        Result := TJSONNull.Create;
      end);
    mMessage := TJSONObject.ParseJSONValue('{"jsonrpc": "2.0", "id": 1, "method": "test/empty"}') as TJSONObject;
    try
      mDispatcher.DispatchMessage(mMessage).Free;
    finally
      mMessage.Free;
    end;
    mMessage := TJSONObject.ParseJSONValue('{"jsonrpc": "2.0", "id": 2, "method": "test/fail"}') as TJSONObject;
    try
      mDispatcher.DispatchMessage(mMessage).Free;
    finally
      mMessage.Free;
    end;
    Assert.AreEqual('start test/empty|done test/empty noTarget|start test/fail|error test/fail EConvertError',
      string.Join('|', mObserver.Events));
    Assert.AreEqual<NativeInt>(2, Length(mDispatcher.Methods));
  finally
    mDispatcher.Free;
  end;
  mRef := nil;
end;

procedure TDiagnosticLogTests.ServerLogHidesPathsAndNames;
var
  mAnonymizer: ILogAnonymizer;
  mLine: string;
begin
  // Server-Log (--log) anonym (#647): Pfade, Projekt-, Unit- und Benutzernamen.
  mAnonymizer := TLogAnonymizer.Create(['mmuster']);
  mAnonymizer.AddNames(['Kundenverwaltung']);
  mAnonymizer.AddUnit('Firma.Kunden', 'C:\Projekte\Firma.Kunden.pas');
  mLine := mAnonymizer.Anonymize('Symbolindex für Kundenverwaltung (Debug, Win64): Cache C:\Users\mmuster\AppData\k.idx');
  Assert.AreEqual('Symbolindex für name#1 (Debug, Win64): Cache datei#1.idx', mLine);
  Assert.AreEqual('name#2.TKunde fehlt', mAnonymizer.Anonymize('Firma.Kunden.TKunde fehlt'));
  // Pfad mit Leerzeichen ohne Anführungszeichen: auch der Rest verschwindet.
  mLine := mAnonymizer.Anonymize('Projekt C:\Work Space\Haupt.dproj nicht lesbar');
  Assert.AreEqual(0, Pos('\', mLine), mLine);
  Assert.AreEqual(0, Pos('Haupt', mLine), mLine);
  mLine := mAnonymizer.Anonymize('didOpen file:///c%3A/Projekte/Haupt.pas von mmuster');
  Assert.AreEqual('didOpen datei#4.pas von benutzer#1', mLine);
end;

procedure TDiagnosticLogTests.ServerLogKeepsLibraryUnitsAndNumbers;
var
  mAnonymizer: ILogAnonymizer;
begin
  mAnonymizer := TLogAnonymizer.Create(nil);
  mAnonymizer.SetLibraryRoots(['C:\Program Files\Embarcadero\Studio\37.0']);
  Assert.AreEqual('Unit "Vcl.Forms.pas" geladen',
    mAnonymizer.Anonymize('Unit "C:\Program Files\Embarcadero\Studio\37.0\source\vcl\Vcl.Forms.pas" geladen'));
  Assert.AreEqual('Stufe "wert#1", Methode "textDocument/hover" nach "1234" ms',
    mAnonymizer.Anonymize('Stufe "verbose", Methode "textDocument/hover" nach "1234" ms'));
end;

const
  cAnonymizeLine = 'Symbolindex für Kundenverwaltung: "C:\Projekte\Haupt.pas" Firma.Kunden.TKunde nach "12" ms';
  cAnonymizedLine = 'Symbolindex für name#1: "datei#1.pas" name#2.TKunde nach "12" ms';

function NewAnonymizer: ILogAnonymizer;
begin
  Result := TLogAnonymizer.Create(['mmuster']);
  Result.AddNames(['Kundenverwaltung']);
  Result.AddUnit('Firma.Kunden', 'C:\Projekte\Firma.Kunden.pas');
end;

procedure TDiagnosticLogTests.AnonymizeManyLinesSameLabels;
const
  cLines = 2000;
var
  mAnonymizer: ILogAnonymizer;
  mWatch: TStopwatch;
  mIndex: Integer;
begin
  mAnonymizer := NewAnonymizer;
  mWatch := TStopwatch.StartNew;
  for mIndex := 1 to cLines do
  begin
    Assert.AreEqual(cAnonymizedLine, mAnonymizer.Anonymize(cAnonymizeLine));
  end;
  mWatch.Stop;
  Assert.IsTrue(mWatch.ElapsedMilliseconds < cLines, Format('%d ms für %d Zeilen', [mWatch.ElapsedMilliseconds, cLines]));
  // Ein langer Text mit vielen Treffern (TStringBuilder statt Anhängen) bleibt vollständig.
  Assert.AreEqual(DupeString(cAnonymizedLine + ' ', 50), mAnonymizer.Anonymize(DupeString(cAnonymizeLine + ' ', 50)));
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
          if AAnonymizer.Anonymize(cAnonymizeLine) <> cAnonymizedLine then
          begin
            TInterlocked.Increment(AFailures^);
          end;
        except
          TInterlocked.Increment(AFailures^);
        end;
    end);
  Result.FreeOnTerminate := False;
end;

procedure TDiagnosticLogTests.AnonymizeConcurrent;
const
  cThreadCount = 4;
  cPerThread = 200;
var
  mAnonymizer: ILogAnonymizer;
  mFailures: Integer;
  mThreads: array[0..cThreadCount - 1] of TThread;
  mNumber: Integer;
begin
  mAnonymizer := NewAnonymizer;
  mFailures := 0;
  for mNumber := 0 to cThreadCount - 1 do
  begin
    mThreads[mNumber] := AnonymizeThread(mAnonymizer, cPerThread, @mFailures);
  end;
  try
    for mNumber := 0 to cThreadCount - 1 do
    begin
      mThreads[mNumber].Start;
    end;
    for mNumber := 0 to cThreadCount - 1 do
    begin
      mThreads[mNumber].WaitFor;
    end;
  finally
    for mNumber := 0 to cThreadCount - 1 do
    begin
      mThreads[mNumber].Free;
    end;
  end;
  Assert.AreEqual(0, mFailures);
  Assert.AreEqual(cAnonymizedLine, mAnonymizer.Anonymize(cAnonymizeLine));
end;

{ TShutdownLeaksTests }

procedure TShutdownLeaksTests.CountsAllocatedMemory;
var
  mBefore: Int64;
  mBlock: Pointer;
begin
  mBefore := TShutdownLeaks.AllocatedBytes;
  GetMem(mBlock, 100000);
  try
    Assert.IsTrue(TShutdownLeaks.AllocatedBytes - mBefore >= 100000);
  finally
    FreeMem(mBlock);
  end;
  Assert.IsTrue(TShutdownLeaks.AllocatedBytes - mBefore < 100000);
end;

procedure TShutdownLeaksTests.DescribesWithoutNames;
begin
  Assert.AreEqual('Speicherrest beim Beenden: 128 Bytes', TShutdownLeaks.Describe(128));
end;

initialization
  TDUnitX.RegisterTestFixture(TDiagnosticLogTests);
  TDUnitX.RegisterTestFixture(TShutdownLeaksTests);

end.
