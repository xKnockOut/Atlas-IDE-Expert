unit Atlas.Testing.Log;

// Protokoll je Test für Atlas (#2168). Der XML-Bericht von DUnitX enthält keine
// Log-Zeilen; dieser Logger schreibt sie in eine Seitendatei neben dem Bericht,
// damit das Fenster „Atlas-Tests“ unter „Protokoll“ genau die Zeilen eines Tests
// zeigt. Diese Unit ins Testprojekt kopieren (oder ihren Ordner in den Suchpfad
// aufnehmen); frei verwendbar unter der MIT-Lizenz.
//
//   uses Atlas.Testing.Log;
//   …
//   runner := TDUnitX.CreateRunner;
//   runner.AddLogger(TAtlasTestLogger.Create);
//
// - Aktiv nur in Läufen aus Atlas: Atlas legt vor dem Start die leere Datei
//   <Bericht>.atlas-log an (Einstellung tests.log). Ohne sie tut der Logger
//   nichts, auch nicht beim Lauf von Hand oder im Build-Server.
// - Je Zeile „Millisekunden<Tab>Art<Tab>Text“: A (Kopf), F+/F- (Fixture),
//   S+/S- (Setup bzw. TearDown der Fixture), T+/T- (Test), I/W/E (Log-Meldung
//   mit Stufe). Mehrzeilige Meldungen stehen als mehrere Zeilen.
// - Auf die Konsole schreibt er Marken um jeden Test („##atlas-test+ Name“,
//   „##atlas-test-“) und „##atlas-log“ je Meldung; so ordnet Atlas Ausgaben mit
//   System.WriteLn (etwa aus der getesteten Klasse) dem richtigen Test zu.
// Nur RTL und DUnitX, ohne Atlas-Packages; übersetzt mit Delphi 12 und neuer.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  DUnitX.TestFramework;

type
  TAtlasTestLogger = class(TInterfacedObject, ITestLogger)
  public const
    cSideExtension = '.atlas-log';
    cFormat = '1';
    cConsoleBegin = '##atlas-test+ ';
    cConsoleEnd = '##atlas-test-';
    cConsoleLog = '##atlas-log';
  private
    FWriter: TStreamWriter;
    FWatch: TStopwatch;
    procedure Put(const AKind, AText: string);
    procedure Mark(const AText: string);
  protected
    procedure OnTestingStarts(const threadId: TThreadID; testCount, testActiveCount: Cardinal);
    procedure OnStartTestFixture(const threadId: TThreadID; const fixture: ITestFixtureInfo);
    procedure OnSetupFixture(const threadId: TThreadID; const fixture: ITestFixtureInfo);
    procedure OnEndSetupFixture(const threadId: TThreadID; const fixture: ITestFixtureInfo);
    procedure OnBeginTest(const threadId: TThreadID; const Test: ITestInfo);
    procedure OnSetupTest(const threadId: TThreadID; const Test: ITestInfo);
    procedure OnEndSetupTest(const threadId: TThreadID; const Test: ITestInfo);
    procedure OnExecuteTest(const threadId: TThreadID; const Test: ITestInfo);
    procedure OnTestSuccess(const threadId: TThreadID; const Test: ITestResult);
    procedure OnTestError(const threadId: TThreadID; const Error: ITestError);
    procedure OnTestFailure(const threadId: TThreadID; const Failure: ITestError);
    procedure OnTestIgnored(const threadId: TThreadID; const AIgnored: ITestResult);
    procedure OnTestMemoryLeak(const threadId: TThreadID; const Test: ITestResult);
    procedure OnLog(const logType: TLogLevel; const msg: string);
    procedure OnTeardownTest(const threadId: TThreadID; const Test: ITestInfo);
    procedure OnEndTeardownTest(const threadId: TThreadID; const Test: ITestInfo);
    procedure OnEndTest(const threadId: TThreadID; const Test: ITestResult);
    procedure OnTearDownFixture(const threadId: TThreadID; const fixture: ITestFixtureInfo);
    procedure OnEndTearDownFixture(const threadId: TThreadID; const fixture: ITestFixtureInfo);
    procedure OnEndTestFixture(const threadId: TThreadID; const results: IFixtureResult);
    procedure OnTestingEnds(const RunResults: IRunResults);
  public
    destructor Destroy; override;
    /// <summary>Seitendatei zum XML-Bericht AReportFile.</summary>
    class function SideFileOf(const AReportFile: string): string; static;
    /// <summary>Zeilen der Seitendatei zu einem Eintrag: je Zeile von AText eine, Tabulatoren als Leerzeichen.
    /// </summary>
    class function Lines(AMs: Int64; const AKind, AText: string): TArray<string>; static;
    /// <summary>Art einer Log-Meldung: I, W oder E.</summary>
    class function KindOf(ALevel: TLogLevel): string; static;
  end;

implementation

const
  cKinds: array[TLogLevel] of string = ('I', 'W', 'E');

{ TAtlasTestLogger }

destructor TAtlasTestLogger.Destroy;
begin
  FreeAndNil(FWriter);
  inherited;
end;

class function TAtlasTestLogger.SideFileOf(const AReportFile: string): string;
begin
  Result := ChangeFileExt(AReportFile, cSideExtension);
end;

class function TAtlasTestLogger.KindOf(ALevel: TLogLevel): string;
begin
  Result := cKinds[ALevel];
end;

class function TAtlasTestLogger.Lines(AMs: Int64; const AKind, AText: string): TArray<string>;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  mParts := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  if Length(mParts) = 0 then
  begin
    mParts := TArray<string>.Create('');
  end;
  SetLength(Result, Length(mParts));
  for mIndex := 0 to High(mParts) do
  begin
    Result[mIndex] := IntToStr(AMs) + #9 + AKind + #9 + mParts[mIndex].Replace(#9, ' ');
  end;
end;

procedure TAtlasTestLogger.Put(const AKind, AText: string);
var
  mLine: string;
begin
  if FWriter = nil then
  begin
    Exit;
  end;
  // Meldungen können aus Threads des Tests kommen.
  System.TMonitor.Enter(Self);
  try
    for mLine in Lines(FWatch.ElapsedMilliseconds, AKind, AText) do
    begin
      FWriter.WriteLine(mLine);
    end;
  finally
    System.TMonitor.Exit(Self);
  end;
end;

procedure TAtlasTestLogger.Mark(const AText: string);
begin
  if FWriter = nil then
  begin
    Exit;
  end;
  // System.WriteLn: In Klassen leitet DUnitX WriteLn auf die Logger um.
  System.Writeln(System.Output, AText); // lsp-ignore: forbidden-symbol
  System.Flush(System.Output);
end;

procedure TAtlasTestLogger.OnTestingStarts(const threadId: TThreadID; testCount, testActiveCount: Cardinal);
var
  mFile: string;
  mStream: TFileStream;
begin
  FreeAndNil(FWriter);
  mFile := '';
  if TDUnitX.Options.XMLOutputFile <> '' then
  begin
    mFile := SideFileOf(ExpandFileName(TDUnitX.Options.XMLOutputFile));
  end;
  if (mFile = '') or not FileExists(mFile) then
  begin
    Exit;
  end;
  mStream := TFileStream.Create(mFile, fmOpenReadWrite or fmShareDenyWrite);
  mStream.Seek(0, soEnd);
  FWriter := TStreamWriter.Create(mStream, TEncoding.UTF8);
  FWriter.OwnStream;
  FWriter.AutoFlush := True;
  FWatch := TStopwatch.StartNew;
  Put('A', cFormat);
end;

procedure TAtlasTestLogger.OnStartTestFixture(const threadId: TThreadID; const fixture: ITestFixtureInfo);
begin
  Put('F+', fixture.FullName);
end;

procedure TAtlasTestLogger.OnSetupFixture(const threadId: TThreadID; const fixture: ITestFixtureInfo);
begin
  Put('S+', '');
end;

procedure TAtlasTestLogger.OnEndSetupFixture(const threadId: TThreadID; const fixture: ITestFixtureInfo);
begin
  Put('S-', '');
end;

procedure TAtlasTestLogger.OnBeginTest(const threadId: TThreadID; const Test: ITestInfo);
begin
  Put('T+', Test.FullName);
  Mark(cConsoleBegin + Test.FullName);
end;

procedure TAtlasTestLogger.OnSetupTest(const threadId: TThreadID; const Test: ITestInfo);
begin
end;

procedure TAtlasTestLogger.OnEndSetupTest(const threadId: TThreadID; const Test: ITestInfo);
begin
end;

procedure TAtlasTestLogger.OnExecuteTest(const threadId: TThreadID; const Test: ITestInfo);
begin
end;

procedure TAtlasTestLogger.OnTestSuccess(const threadId: TThreadID; const Test: ITestResult);
begin
end;

procedure TAtlasTestLogger.OnTestError(const threadId: TThreadID; const Error: ITestError);
begin
end;

procedure TAtlasTestLogger.OnTestFailure(const threadId: TThreadID; const Failure: ITestError);
begin
end;

procedure TAtlasTestLogger.OnTestIgnored(const threadId: TThreadID; const AIgnored: ITestResult);
begin
end;

procedure TAtlasTestLogger.OnTestMemoryLeak(const threadId: TThreadID; const Test: ITestResult);
begin
end;

procedure TAtlasTestLogger.OnLog(const logType: TLogLevel; const msg: string);
begin
  Put(KindOf(logType), msg);
  Mark(cConsoleLog);
end;

procedure TAtlasTestLogger.OnTeardownTest(const threadId: TThreadID; const Test: ITestInfo);
begin
end;

procedure TAtlasTestLogger.OnEndTeardownTest(const threadId: TThreadID; const Test: ITestInfo);
begin
end;

procedure TAtlasTestLogger.OnEndTest(const threadId: TThreadID; const Test: ITestResult);
begin
  Put('T-', '');
  Mark(cConsoleEnd);
end;

procedure TAtlasTestLogger.OnTearDownFixture(const threadId: TThreadID; const fixture: ITestFixtureInfo);
begin
  Put('S+', '');
end;

procedure TAtlasTestLogger.OnEndTearDownFixture(const threadId: TThreadID; const fixture: ITestFixtureInfo);
begin
  Put('S-', '');
end;

procedure TAtlasTestLogger.OnEndTestFixture(const threadId: TThreadID; const results: IFixtureResult);
begin
  Put('F-', '');
end;

procedure TAtlasTestLogger.OnTestingEnds(const RunResults: IRunResults);
begin
  FreeAndNil(FWriter);
end;

end.
