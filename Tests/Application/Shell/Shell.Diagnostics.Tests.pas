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
    /// <summary>Gemeinsame Logdatei für LSP und MCP (D-08): ohne Namen nichts, nicht anlegbar ein Fehler im Log.</summary>
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
  Markers: array[0..6] of string = ('MarkerPfadXq7', 'MarkerProjektBn6', 'MarkerUnitZk3', 'TMarkerKlasseWv5',
    'MarkerMethodeJp2', 'MarkerVariableHt4', 'MarkerStringQm8');

  MarkerUnit =
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
  Queries: array[0..7] of TQuery = (
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
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', AUri)));
  Params.AddPair('position', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ALine))
    .AddPair('character', TJSONNumber.Create(ACharacter)));
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('id', TJSONNumber.Create(AId));
  Result.AddPair('method', AMethod);
  Result.AddPair('params', Params);
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
    TDirectory.Delete(FRoot, True);
  // Strings aus Setup freigeben, sonst zählt der Lecktest sie mit.
  FRoot := '';
  FLogFolder := '';
end;

procedure TShellDiagnosticsTests.RunSession(AEnabled: Boolean);
var
  Folder, FileName, Uri: string;
  Store: IDocumentStore;
  Index: ISymbolIndex;
  Hover: TLspHover;
  Completion: TLspCompletion;
  Dispatcher: TJsonRpcDispatcher;
  Diagnostics: TShellDiagnostics;
  Ref: IJsonRpcRequestObserver;
  Settings: TServerSettings;
  Message: TJSONObject;
  Id: Integer;
begin
  Folder := TPath.Combine(TPath.Combine(FRoot, 'MarkerPfadXq7'), 'MarkerProjektBn6');
  ForceDirectories(Folder);
  FileName := TPath.Combine(Folder, 'MarkerUnitZk3.pas');
  TFile.WriteAllText(FileName, MarkerUnit, TEncoding.UTF8);
  Uri := TDocumentUris.FromPath(FileName);
  Store := TDocumentStore.Create;
  Store.Open(Uri, 'delphi', 3, MarkerUnit);
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(MarkerUnit, FileName, nil));
  Hover := TLspHover.Create(Store, Index,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := SameText(AFileName, FileName);
      AText := MarkerUnit;
    end,
    function(const AUnitName: string): Boolean
    begin
      Result := False;
    end);
  Completion := TLspCompletion.Create(Store, Index,
    function(const AUnitName: string): Boolean
    begin
      Result := False;
    end);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Hover.Attach(Dispatcher);
    Completion.Attach(Dispatcher);
    Diagnostics := TShellDiagnostics.Create(FLogFolder, 'test', Store, Index);
    Ref := Diagnostics;
    Dispatcher.Observer := Ref;
    Diagnostics.AllowMethods(Dispatcher.Methods);
    Diagnostics.BeginRun('1.0.0', 1024 * 1024);
    Settings := TServerSettings.Default;
    Settings.DiagnosticsLog := AEnabled;
    Diagnostics.ApplySettings(Settings);
    for Id := 0 to High(Queries) do
    begin
      Message := Request(Id + 1, Queries[Id].Method, Uri, Queries[Id].Line, Queries[Id].Character);
      try
        Dispatcher.DispatchMessage(Message).Free;
      finally
        Message.Free;
      end;
    end;
    Diagnostics.EndRun(TDiagnosticEndReason.ParentExited, 0, 2 * 1024 * 1024);
    Dispatcher.Observer := nil;
    Ref := nil;
  finally
    Dispatcher.Free;
    Completion.Free;
    Hover.Free;
  end;
end;

function TShellDiagnosticsTests.AllLogText: string;
var
  FileName: string;
begin
  Result := '';
  for FileName in TDirectory.GetFiles(FLogFolder, '*', TSearchOption.soAllDirectories) do
    Result := Result + ExtractFileName(FileName) + #13#10 + TFile.ReadAllText(FileName, TEncoding.UTF8);
end;

procedure TShellDiagnosticsTests.NoMarkerReachesLogOrExport;
var
  Text, Preview, Target, Marker, Exported: string;
  Files: TArray<string>;
  Zip: TZipFile;
  Index: Integer;
  Bytes: TBytes;
begin
  RunSession(True);
  Text := AllLogText;
  Assert.Contains(Text, 'textDocument/hover');
  Assert.Contains(Text, 'textDocument/completion');
  Files := TAtlasDiagnosticExport.Files(FLogFolder, 7, Now);
  Assert.AreEqual<NativeInt>(1, Length(Files));
  Preview := TAtlasDiagnosticExport.Preview(Files);
  Target := TPath.Combine(FRoot, 'export.zip');
  TAtlasDiagnosticExport.WriteZip(Files, Target);
  Exported := '';
  Zip := TZipFile.Create;
  try
    Zip.Open(Target, TZipMode.zmRead);
    for Index := 0 to Zip.FileCount - 1 do
    begin
      Zip.Read(Index, Bytes);
      Exported := Exported + Zip.FileNames[Index] + #13#10 + TEncoding.UTF8.GetString(Bytes);
    end;
  finally
    Zip.Free;
  end;
  Assert.Contains(Exported, 'textDocument/hover');
  for Marker in Markers do
  begin
    Assert.DoesNotContain(Text, Marker, False, 'Log enthält ' + Marker);
    Assert.DoesNotContain(Preview, Marker, False, 'Vorschau enthält ' + Marker);
    Assert.DoesNotContain(Exported, Marker, False, 'Export enthält ' + Marker);
  end;
  Assert.DoesNotContain(Text, 'FehltBeiAllenYc9', False);
  if Length(GetEnvironmentVariable('USERNAME')) >= 3 then
    Assert.DoesNotContain(Text, GetEnvironmentVariable('USERNAME'), False);
end;

procedure TShellDiagnosticsTests.EveryEmptyAnswerHasReason;
var
  Line: string;
  Empty: Integer;
begin
  RunSession(True);
  Empty := 0;
  for Line in AllLogText.Split([#13#10, #10]) do
    if Line.Contains(' empty') then
    begin
      Inc(Empty);
      Assert.DoesNotContain(Line, 'empty:unspecified', False, Line);
    end;
  Assert.IsTrue(Empty >= 3, Format('%d leere Antworten', [Empty]));
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
  Diagnostics: TShellDiagnostics;
  Ref: IJsonRpcRequestObserver;
  Settings: TServerSettings;
  Text: string;
  Store: IDocumentStore;
  Index: ISymbolIndex;
begin
  // Die Endzeile kommt schon beim Ende der Eingabe; der Aufruf nach dem Warten auf laufende
  // Anfragen schreibt keine zweite (#647).
  // Erst in Variablen halten: Bei Übergabe als const würden die Objekte nie freigegeben.
  Store := TDocumentStore.Create;
  Index := TSymbolIndex.Create;
  Diagnostics := TShellDiagnostics.Create(FLogFolder, 'test', Store, Index);
  Ref := Diagnostics;
  Diagnostics.BeginRun('1.0.0', 1024 * 1024);
  Settings := TServerSettings.Default;
  Settings.DiagnosticsLog := True;
  Diagnostics.ApplySettings(Settings);
  Diagnostics.EndRun(TDiagnosticEndReason.InputClosed, 0, 1024 * 1024);
  Diagnostics.EndRun(TDiagnosticEndReason.ParentExited, 1, 1024 * 1024);
  Ref := nil;
  Text := AllLogText;
  Assert.Contains(Text, 'run end reason inputClosed exit 0');
  Assert.DoesNotContain(Text, 'parentExited');
  Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(FLogFolder, 'run-*.open')));
end;

procedure TShellDiagnosticsTests.PreviousRunsWithoutEndAreCounted;
var
  Diagnostics: TShellDiagnostics;
  Ref: IJsonRpcRequestObserver;
  Store: IDocumentStore;
  Index: ISymbolIndex;
begin
  // Zwei liegen gebliebene Marken: Die IDE hat zwei Server hart beendet (#175).
  TFile.WriteAllText(TPath.Combine(FLogFolder, 'run-alt1.open'), '');
  TFile.WriteAllText(TPath.Combine(FLogFolder, 'run-alt2.open'), '');
  Store := TDocumentStore.Create;
  Index := TSymbolIndex.Create;
  Diagnostics := TShellDiagnostics.Create(FLogFolder, 'test', Store, Index);
  Ref := Diagnostics;
  Assert.AreEqual(2, Diagnostics.BeginRun('1.0.0', 1024 * 1024));
  Diagnostics.EndRun(TDiagnosticEndReason.Clean, 0, 1024 * 1024);
  Ref := nil;
  Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(FLogFolder, 'run-*.open')));
end;

procedure TShellDiagnosticsTests.EveryEndReasonHasText;
var
  Reason, Other: TDiagnosticEndReason;
begin
  for Reason := Low(TDiagnosticEndReason) to High(TDiagnosticEndReason) do
  begin
    Assert.AreNotEqual('', TShellDiagnostics.EndReasonText(Reason));
    for Other := Succ(Reason) to High(TDiagnosticEndReason) do
      Assert.AreNotEqual(TShellDiagnostics.EndReasonText(Reason), TShellDiagnostics.EndReasonText(Other));
  end;
  Assert.Contains(TShellDiagnostics.EndReasonText(TDiagnosticEndReason.InputClosed), 'ohne exit');
end;


procedure TShellDiagnosticsTests.AddLogFile_EmptyName_DoesNothing;
var
  Logger: TLogger;
  Keep: ILogger;
  Anonymizer: ILogAnonymizer;
begin
  Logger := TLogger.Create;
  Keep := Logger;
  Assert.IsTrue(TShellDiagnostics.AddLogFile(Logger, '', '1', False, TLogLevel.Info, Anonymizer));
  Assert.IsNull(Anonymizer);
end;

procedure TShellDiagnosticsTests.AddLogFile_BadPath_LogsError;
var
  Logger: TLogger;
  Keep: ILogger;
  Sink: TCaptureSink;
  KeepSink: ILogSink;
  Anonymizer: ILogAnonymizer;
  Blocker: string;
begin
  Logger := TLogger.Create;
  Keep := Logger;
  Sink := TCaptureSink.Create;
  KeepSink := Sink;
  Logger.AddSink(KeepSink, TLogLevel.Debug);
  // Eine Datei an der Stelle des Ordners: Die Logdatei lässt sich nicht anlegen.
  Blocker := TPath.Combine(FLogFolder, 'Blocker');
  TDirectory.CreateDirectory(FLogFolder);
  TFile.WriteAllText(Blocker, 'x');
  Assert.IsFalse(TShellDiagnostics.AddLogFile(Logger, TPath.Combine(Blocker, 'server.log'), '1', True,
    TLogLevel.Info, Anonymizer));
  Assert.Contains(Sink.Text, 'kann nicht geöffnet werden');
end;

procedure TShellDiagnosticsTests.ErrorLineNamesUnitAndRule;
var
  Diagnostics: TShellDiagnostics;
  Ref: IJsonRpcRequestObserver;
  Settings: TServerSettings;
  Error: Exception;
  FileName, UnitLabel, Text: string;
begin
  FileName := TPath.Combine(TPath.Combine(FRoot, 'MarkerPfadXq7'), 'MarkerUnitZk3.pas');
  Diagnostics := TShellDiagnostics.Create(FLogFolder, 'test', nil, nil);
  Ref := Diagnostics;
  Diagnostics.AllowMethods(['workspace/diagnostic']);
  Diagnostics.BeginRun('1.0.0', 1024 * 1024);
  Settings := TServerSettings.Default;
  Settings.DiagnosticsLog := True;
  Diagnostics.ApplySettings(Settings);
  UnitLabel := Diagnostics.FileLabel(FileName);
  Assert.StartsWith('unit#', UnitLabel);
  Assert.AreEqual(UnitLabel, Diagnostics.FileLabel(FileName), 'gleiche Datei, gleiches Kennzeichen');
  Diagnostics.Started('workspace/diagnostic');
  TRequestDiagnostics.Open;
  TRequestDiagnostics.Subject(UnitLabel);
  TRequestDiagnostics.CurrentRule('hides-virtual');
  Error := EStackOverflow.Create('Stapel');
  try
    Diagnostics.Finished('workspace/diagnostic', nil, nil, Error, 0, 77);
  finally
    Error.Free;
  end;
  Diagnostics.EndRun(TDiagnosticEndReason.ParentExited, 0, 2 * 1024 * 1024);
  Ref := nil;
  Text := AllLogText;
  Assert.Contains(Text, 'error:EStackOverflow');
  Assert.Contains(Text, 'unit=' + UnitLabel);
  Assert.Contains(Text, 'rule=hides-virtual');
  Assert.DoesNotContain(Text, 'MarkerUnitZk3', False);
  Assert.DoesNotContain(Text, 'MarkerPfadXq7', False);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellDiagnosticsTests);

end.
