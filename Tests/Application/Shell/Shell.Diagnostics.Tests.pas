unit Shell.Diagnostics.Tests;

// Abnahme des Diagnoselogs (#647) über den ganzen Weg: Ein Testprojekt mit
// eindeutigen Markernamen (Pfad, Projekt, Unit, Klasse, Bezeichner,
// String-Inhalt) wird indiziert und über den Dispatcher mit Hover und
// Vervollständigung abgefragt. Keiner der Marker darf in den geschriebenen
// Dateien oder im Export (ZIP und Vorschau) stehen; jede leere Antwort hat
// einen Grundcode, jedes Ende einen Grund.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellDiagnosticsTests = class
  private
    FRoot: string;
    FLogFolder: string;
    /// <summary>Indiziert das Markerprojekt, fragt ab und beendet den Lauf (Grund parentExited).</summary>
    procedure RunSession(AEnabled: Boolean);
    function AllLogText: string;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure NoMarkerReachesLogOrExport;
    [Test]
    procedure EveryEmptyAnswerHasReason;
    [Test]
    procedure EveryRunEndHasReason;
    [Test]
    procedure DisabledLogWritesNothing;
    [Test]
    procedure FirstRunEndWins;
    [Test]
    procedure PreviousRunsWithoutEndAreCounted;
    [Test]
    procedure EveryEndReasonHasText;
    /// <summary>Gemeinsame Logdatei für LSP und MCP: ohne Namen nichts, nicht anlegbar ein Fehler im
    /// Log.</summary>
    [Test]
    procedure AddLogFile_EmptyName_DoesNothing;
    [Test]
    procedure AddLogFile_BadPath_LogsError;
    /// <summary>#1094: Ein Fehler nennt die Unit (anonym) und die Prüfregel, an der die Anfrage scheiterte.</summary>
    [Test]
    procedure ErrorLineNamesUnitAndRule;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  System.Zip,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Diagnostics.Contract,
  Atlas.Common.Lsp.Hover,
  Atlas.Common.Lsp.Completion,
  Atlas.Core.Diagnostics.Export,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Diagnostics.Anonymizer,
  Atlas.Common.Diagnostics.RequestScope,
  Shell.Diagnostics;

type
  /// <summary>Gleichnamig zur veralteten RTL-Klasse (W1000): Atlas erkennt den Überlauf am Namen.</summary>
  EStackOverflow = class(Exception);

type
  /// <summary>Sammelt die Logeinträge als Text.</summary>
  TCaptureSink = class(TInterfacedObject, ILogSink)
  public
    Text: string;
    procedure Write(const AEntry: TLogEntry);
  end;

procedure TCaptureSink.Write(const AEntry: TLogEntry);
begin
  Text := Text + AEntry.ToText + sLineBreak;
end;

const
  cMarkers: array[0..6] of string = ('MarkerPfadXq7', 'MarkerProjektBn6', 'MarkerUnitZk3', 'TMarkerKlasseWv5',
    'MarkerMethodeJp2', 'MarkerVariableHt4', 'MarkerStringQm8');

  cMarkerUnit =
    'unit MarkerUnitZk3;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TMarkerKlasseWv5 = class'#13#10 +
    '    procedure MarkerMethodeJp2;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'uses FehltBeiAllenYc9;'#13#10 +
    'procedure TMarkerKlasseWv5.MarkerMethodeJp2;'#13#10 +
    'const'#13#10 +
    '  Text = ''MarkerStringQm8'';'#13#10 +
    'var'#13#10 +
    '  MarkerVariableHt4: TMarkerKlasseWv5;'#13#10 +
    'begin'#13#10 +
    '  MarkerVariableHt4.Mark'#13#10 +
    '  FehltBeiAllenYc9.Irgendwas;'#13#10 +
    'end;'#13#10 +
    'end.';

type
  TQuery = record
    Method: string;
    Line: Integer;
    Character: Integer;
  end;

const
  cQueries: array[0..7] of TQuery = (
    // Treffer: Methode in der Implementierung, Klasse in der Variablendeklaration.
    (Method: 'textDocument/hover'; Line: 8; Character: 30),
    (Method: 'textDocument/hover'; Line: 12; Character: 24),
    // Leer: im String, hinter dem Zeilenende, in der fehlenden Unit.
    (Method: 'textDocument/hover'; Line: 10; Character: 12),
    (Method: 'textDocument/hover'; Line: 1; Character: 30),
    (Method: 'textDocument/hover'; Line: 15; Character: 20),
    // Vervollständigung: Member der Klasse, im String, nach unbekannter Unit.
    (Method: 'textDocument/completion'; Line: 14; Character: 24),
    (Method: 'textDocument/completion'; Line: 10; Character: 14),
    (Method: 'textDocument/completion'; Line: 15; Character: 23));

function Request(AId: Integer; const AMethod, AUri: string; ALine, ACharacter: Integer): TJSONObject;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', AUri)));
  mParams.AddPair('position', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ALine))
    .AddPair('character', TJSONNumber.Create(ACharacter)));
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('id', TJSONNumber.Create(AId));
  Result.AddPair('method', AMethod);
  Result.AddPair('params', mParams);
end;

{ TShellDiagnosticsTests }

procedure TShellDiagnosticsTests.WarmUpFirstUse;
begin
  Setup;
  try
    NoMarkerReachesLogOrExport;
  finally
    TearDown;
  end;
  Setup;
  try
    AddLogFile_BadPath_LogsError;
  finally
    TearDown;
  end;
end;

procedure TShellDiagnosticsTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'atlas-' + TGUID.NewGuid.ToString.Substring(1, 8));
  FLogFolder := TPath.Combine(FRoot, 'Diagnose');
  ForceDirectories(FLogFolder);
end;

procedure TShellDiagnosticsTests.TearDown;
begin
  if TDirectory.Exists(FRoot) then
  begin
    TDirectory.Delete(FRoot, True);
  end;
  // Strings aus Setup freigeben, sonst zählt der Lecktest sie mit.
  FRoot := '';
  FLogFolder := '';
end;

/// <summary>Schickt alle Anfragen aus Queries für AUri an ADispatcher.</summary>
procedure SendQueries(ADispatcher: TJsonRpcDispatcher; const AUri: string);
var
  mMessage: TJSONObject;
  mId: Integer;
begin
  for mId := 0 to High(cQueries) do
  begin
    mMessage := Request(mId + 1, cQueries[mId].Method, AUri, cQueries[mId].Line, cQueries[mId].Character);
    try
      ADispatcher.DispatchMessage(mMessage).Free;
    finally
      mMessage.Free;
    end;
  end;
end;

procedure TShellDiagnosticsTests.RunSession(AEnabled: Boolean);
var
  mFolder, mFileName, mUri: string;
  mStore: IDocumentStore;
  mIndex: ISymbolIndex;
  mHover: TLspHover;
  mCompletion: TLspCompletion;
  mDispatcher: TJsonRpcDispatcher;
  mDiagnostics: TShellDiagnostics;
  mRef: IJsonRpcRequestObserver;
  mSettings: TServerSettings;
begin
  mFolder := TPath.Combine(TPath.Combine(FRoot, 'MarkerPfadXq7'), 'MarkerProjektBn6');
  ForceDirectories(mFolder);
  mFileName := TPath.Combine(mFolder, 'MarkerUnitZk3.pas');
  TFile.WriteAllText(mFileName, cMarkerUnit, TEncoding.UTF8);
  mUri := TDocumentUris.FromPath(mFileName);
  mStore := TDocumentStore.Create;
  mStore.Open(mUri, 'delphi', 3, cMarkerUnit);
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cMarkerUnit, mFileName, nil));
  mHover := TLspHover.Create(mStore, mIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := SameText(AFileName, mFileName);
      AText := cMarkerUnit;
    end,
    function(const AUnitName: string): Boolean
    begin
      Result := False;
    end);
  mCompletion := TLspCompletion.Create(mStore, mIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := False;
    end);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mHover.Attach(mDispatcher);
    mCompletion.Attach(mDispatcher);
    mDiagnostics := TShellDiagnostics.Create(FLogFolder, 'test', mStore, mIndex);
    mRef := mDiagnostics;
    mDispatcher.Observer := mRef;
    mDiagnostics.AllowMethods(mDispatcher.Methods);
    mDiagnostics.BeginRun('1.0.0', 1024 * 1024);
    mSettings := TServerSettings.Default;
    mSettings.DiagnosticsLog := AEnabled;
    mDiagnostics.ApplySettings(mSettings);
    SendQueries(mDispatcher, mUri);
    mDiagnostics.EndRun(TDiagnosticEndReason.ParentExited, 0, 2 * 1024 * 1024);
    mDispatcher.Observer := nil;
    mRef := nil;
  finally
    mDispatcher.Free;
    mCompletion.Free;
    mHover.Free;
  end;
end;

function TShellDiagnosticsTests.AllLogText: string;
var
  mFileName: string;
begin
  Result := '';
  for mFileName in TDirectory.GetFiles(FLogFolder, '*', TSearchOption.soAllDirectories) do
  begin
    Result := Result + ExtractFileName(mFileName) + #13#10 + TFile.ReadAllText(mFileName, TEncoding.UTF8);
  end;
end;

procedure TShellDiagnosticsTests.NoMarkerReachesLogOrExport;
var
  mText, mPreview, mTarget, mMarker, mExported: string;
  mFiles: TArray<string>;
  mZip: TZipFile;
  mIndex: Integer;
  mBytes: TBytes;
begin
  RunSession(True);
  mText := AllLogText;
  Assert.Contains(mText, 'textDocument/hover');
  Assert.Contains(mText, 'textDocument/completion');
  mFiles := TAtlasDiagnosticExport.Files(FLogFolder, 7, Now);
  Assert.AreEqual<NativeInt>(1, Length(mFiles));
  mPreview := TAtlasDiagnosticExport.Preview(mFiles);
  mTarget := TPath.Combine(FRoot, 'export.zip');
  TAtlasDiagnosticExport.WriteZip(mFiles, mTarget);
  mExported := '';
  mZip := TZipFile.Create;
  try
    mZip.Open(mTarget, TZipMode.zmRead);
    for mIndex := 0 to mZip.FileCount - 1 do
    begin
      mZip.Read(mIndex, mBytes);
      mExported := mExported + mZip.FileNames[mIndex] + #13#10 + TEncoding.UTF8.GetString(mBytes);
    end;
  finally
    mZip.Free;
  end;
  Assert.Contains(mExported, 'textDocument/hover');
  for mMarker in cMarkers do
  begin
    Assert.DoesNotContain(mText, mMarker, False, 'Log enthält ' + mMarker);
    Assert.DoesNotContain(mPreview, mMarker, False, 'Vorschau enthält ' + mMarker);
    Assert.DoesNotContain(mExported, mMarker, False, 'Export enthält ' + mMarker);
  end;
  Assert.DoesNotContain(mText, 'FehltBeiAllenYc9', False);
  if Length(GetEnvironmentVariable('USERNAME')) >= 3 then
  begin
    Assert.DoesNotContain(mText, GetEnvironmentVariable('USERNAME'), False);
  end;
end;

procedure TShellDiagnosticsTests.EveryEmptyAnswerHasReason;
var
  mLine: string;
  mEmpty: Integer;
begin
  RunSession(True);
  mEmpty := 0;
  for mLine in AllLogText.Split([#13#10, #10]) do
  begin
    if mLine.Contains(' empty') then
    begin
      Inc(mEmpty);
      Assert.DoesNotContain(mLine, 'empty:unspecified', False, mLine);
    end;
  end;
  Assert.IsTrue(mEmpty >= 3, Format('%d leere Antworten', [mEmpty]));
end;

procedure TShellDiagnosticsTests.EveryRunEndHasReason;
begin
  RunSession(True);
  Assert.Contains(AllLogText, 'run end reason parentExited exit 0');
  // Nach dem Ende bleibt keine Laufmarke liegen.
  Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(FLogFolder, 'run-*.open')));
end;

procedure TShellDiagnosticsTests.DisabledLogWritesNothing;
begin
  RunSession(False);
  Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(FLogFolder, '*', TSearchOption.soAllDirectories)));
end;

procedure TShellDiagnosticsTests.FirstRunEndWins;
var
  mDiagnostics: TShellDiagnostics;
  mRef: IJsonRpcRequestObserver;
  mSettings: TServerSettings;
  mText: string;
  mStore: IDocumentStore;
  mIndex: ISymbolIndex;
begin
  // Die Endzeile kommt schon beim Ende der Eingabe; der Aufruf nach dem Warten auf laufende
  // Anfragen schreibt keine zweite (#647).
  // Erst in Variablen halten: Bei Übergabe als const würden die Objekte nie freigegeben.
  mStore := TDocumentStore.Create;
  mIndex := TSymbolIndex.Create;
  mDiagnostics := TShellDiagnostics.Create(FLogFolder, 'test', mStore, mIndex);
  mRef := mDiagnostics;
  mDiagnostics.BeginRun('1.0.0', 1024 * 1024);
  mSettings := TServerSettings.Default;
  mSettings.DiagnosticsLog := True;
  mDiagnostics.ApplySettings(mSettings);
  mDiagnostics.EndRun(TDiagnosticEndReason.InputClosed, 0, 1024 * 1024);
  mDiagnostics.EndRun(TDiagnosticEndReason.ParentExited, 1, 1024 * 1024);
  mRef := nil;
  mText := AllLogText;
  Assert.Contains(mText, 'run end reason inputClosed exit 0');
  Assert.DoesNotContain(mText, 'parentExited');
  Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(FLogFolder, 'run-*.open')));
end;

procedure TShellDiagnosticsTests.PreviousRunsWithoutEndAreCounted;
var
  mDiagnostics: TShellDiagnostics;
  mRef: IJsonRpcRequestObserver;
  mStore: IDocumentStore;
  mIndex: ISymbolIndex;
begin
  // Zwei liegen gebliebene Marken: Die IDE hat zwei Server hart beendet (#175).
  TFile.WriteAllText(TPath.Combine(FLogFolder, 'run-alt1.open'), '');
  TFile.WriteAllText(TPath.Combine(FLogFolder, 'run-alt2.open'), '');
  mStore := TDocumentStore.Create;
  mIndex := TSymbolIndex.Create;
  mDiagnostics := TShellDiagnostics.Create(FLogFolder, 'test', mStore, mIndex);
  mRef := mDiagnostics;
  Assert.AreEqual(2, mDiagnostics.BeginRun('1.0.0', 1024 * 1024));
  mDiagnostics.EndRun(TDiagnosticEndReason.Clean, 0, 1024 * 1024);
  mRef := nil;
  Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(FLogFolder, 'run-*.open')));
end;

procedure TShellDiagnosticsTests.EveryEndReasonHasText;
var
  mReason, mOther: TDiagnosticEndReason;
begin
  for mReason := Low(TDiagnosticEndReason) to High(TDiagnosticEndReason) do
  begin
    Assert.AreNotEqual('', TShellDiagnostics.EndReasonText(mReason));
    for mOther := Succ(mReason) to High(TDiagnosticEndReason) do
    begin
      Assert.AreNotEqual(TShellDiagnostics.EndReasonText(mReason), TShellDiagnostics.EndReasonText(mOther));
    end;
  end;
  Assert.Contains(TShellDiagnostics.EndReasonText(TDiagnosticEndReason.InputClosed), 'ohne exit');
end;


procedure TShellDiagnosticsTests.AddLogFile_EmptyName_DoesNothing;
var
  mLogger: TLogger;
  mKeep: ILogger;
  mAnonymizer: ILogAnonymizer;
begin
  mLogger := TLogger.Create;
  mKeep := mLogger;
  Assert.IsTrue(TShellDiagnostics.AddLogFile(mLogger, '', '1', False, TLogLevel.Info, mAnonymizer));
  Assert.IsNull(mAnonymizer);
end;

procedure TShellDiagnosticsTests.AddLogFile_BadPath_LogsError;
var
  mLogger: TLogger;
  mKeep: ILogger;
  mSink: TCaptureSink;
  mKeepSink: ILogSink;
  mAnonymizer: ILogAnonymizer;
  mBlocker: string;
begin
  mLogger := TLogger.Create;
  mKeep := mLogger;
  mSink := TCaptureSink.Create;
  mKeepSink := mSink;
  mLogger.AddSink(mKeepSink, TLogLevel.Debug);
  // Eine Datei an der Stelle des Ordners: Die Logdatei lässt sich nicht anlegen.
  mBlocker := TPath.Combine(FLogFolder, 'Blocker');
  TDirectory.CreateDirectory(FLogFolder);
  TFile.WriteAllText(mBlocker, 'x');
  Assert.IsFalse(TShellDiagnostics.AddLogFile(mLogger, TPath.Combine(mBlocker, 'server.log'), '1', True,
    TLogLevel.Info, mAnonymizer));
  Assert.Contains(mSink.Text, 'kann nicht geöffnet werden');
end;

procedure TShellDiagnosticsTests.ErrorLineNamesUnitAndRule;
var
  mDiagnostics: TShellDiagnostics;
  mRef: IJsonRpcRequestObserver;
  mSettings: TServerSettings;
  mError: Exception;
  mFileName, mUnitLabel, mText: string;
begin
  mFileName := TPath.Combine(TPath.Combine(FRoot, 'MarkerPfadXq7'), 'MarkerUnitZk3.pas');
  mDiagnostics := TShellDiagnostics.Create(FLogFolder, 'test', nil, nil);
  mRef := mDiagnostics;
  mDiagnostics.AllowMethods(['workspace/diagnostic']);
  mDiagnostics.BeginRun('1.0.0', 1024 * 1024);
  mSettings := TServerSettings.Default;
  mSettings.DiagnosticsLog := True;
  mDiagnostics.ApplySettings(mSettings);
  mUnitLabel := mDiagnostics.FileLabel(mFileName);
  Assert.StartsWith('unit#', mUnitLabel);
  Assert.AreEqual(mUnitLabel, mDiagnostics.FileLabel(mFileName), 'gleiche Datei, gleiches Kennzeichen');
  mDiagnostics.Started('workspace/diagnostic');
  TRequestDiagnostics.Open;
  TRequestDiagnostics.Subject(mUnitLabel);
  TRequestDiagnostics.CurrentRule('hides-virtual');
  mError := EStackOverflow.Create('Stapel');
  try
    mDiagnostics.Finished('workspace/diagnostic', nil, nil, mError, 0, 77);
  finally
    mError.Free;
  end;
  mDiagnostics.EndRun(TDiagnosticEndReason.ParentExited, 0, 2 * 1024 * 1024);
  mRef := nil;
  mText := AllLogText;
  Assert.Contains(mText, 'error:EStackOverflow');
  Assert.Contains(mText, 'unit=' + mUnitLabel);
  Assert.Contains(mText, 'rule=hides-virtual');
  Assert.DoesNotContain(mText, 'MarkerUnitZk3', False);
  Assert.DoesNotContain(mText, 'MarkerPfadXq7', False);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellDiagnosticsTests);

end.
