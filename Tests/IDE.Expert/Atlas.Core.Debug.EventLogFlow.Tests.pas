unit Atlas.Core.Debug.EventLogFlow.Tests;

// Tests für die Entscheidungen des Ereignisprotokolls außerhalb von Einordnung und Ablage (#579, #1967): Zeilen des
// Fensters, Logpunkte, Symbol eines Eintrags, Zeit seit dem Start, Dateiname; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasEventLogFlowTests = class
  public
    [Test]
    procedure WindowLinesSkippedWhileWatching;
    [Test]
    procedure MergerFollowsPrefix;
    [Test]
    procedure LogpointSteps;
    [Test]
    procedure FindSymbolPrefersFullName;
    [Test]
    procedure ElapsedAndSaveName;
  end;

implementation

uses
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Debug.EventLog,
  Atlas.Core.Debug.Logpoint,
  Atlas.Core.Debug.EventLogFlow;

function Symbol(const AContainer, AName, AFileName: string; ALine: Integer): TAtlasSymbol;
begin
  Result := Default(TAtlasSymbol);
  Result.Container := AContainer;
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.Line := ALine;
end;

{ TAtlasEventLogFlowTests }

procedure TAtlasEventLogFlowTests.WindowLinesSkippedWhileWatching;
begin
  Assert.IsTrue(TAtlasEventLogFlow.SkipFromWindow(True, TAtlasEventKind.Module));
  Assert.IsTrue(TAtlasEventLogFlow.SkipFromWindow(True, TAtlasEventKind.Thread));
  Assert.IsTrue(TAtlasEventLogFlow.SkipFromWindow(True, TAtlasEventKind.Process));
  Assert.IsFalse(TAtlasEventLogFlow.SkipFromWindow(True, TAtlasEventKind.Breakpoint));
  Assert.IsFalse(TAtlasEventLogFlow.SkipFromWindow(False, TAtlasEventKind.Module));
end;

procedure TAtlasEventLogFlowTests.MergerFollowsPrefix;
var
  mMerger: TAtlasLogpointMerger;
begin
  Assert.IsTrue(TAtlasEventLogFlow.NeedsMerger(nil, '[LOG]'));
  mMerger := TAtlasLogpointMerger.Create('[LOG]');
  try
    Assert.IsFalse(TAtlasEventLogFlow.NeedsMerger(mMerger, '[LOG]'));
    Assert.IsTrue(TAtlasEventLogFlow.NeedsMerger(mMerger, '[TRACE]'));
  finally
    mMerger.Free;
  end;
end;

procedure TAtlasEventLogFlowTests.LogpointSteps;
var
  mMerger: TAtlasLogpointMerger;
  mOutput: string;
begin
  mMerger := TAtlasLogpointMerger.Create('[LOG]');
  try
    // Keine Haltepunktzeile und nichts wartet: bleibt.
    Assert.AreEqual<TAtlasLogpointStep>(TAtlasLogpointStep.Keep,
      TAtlasEventLogFlow.LogpointStep(mMerger, TAtlasEventKind.Output, '[LOG] fertig', mOutput));
    Assert.AreEqual<TAtlasLogpointStep>(TAtlasLogpointStep.Keep,
      TAtlasEventLogFlow.LogpointStep(mMerger, TAtlasEventKind.Breakpoint, 'anderer Haltepunkt', mOutput));
    Assert.AreEqual<TAtlasLogpointStep>(TAtlasLogpointStep.Drop,
      TAtlasEventLogFlow.LogpointStep(mMerger, TAtlasEventKind.Breakpoint, '[LOG] x={0} · Unit1.pas:12', mOutput));
    // Die Zeile mit dem Wert ist keine Haltepunktzeile, gehört aber zur wartenden Meldung.
    Assert.AreEqual<TAtlasLogpointStep>(TAtlasLogpointStep.Merged,
      TAtlasEventLogFlow.LogpointStep(mMerger, TAtlasEventKind.Output, 'x: 42', mOutput));
    Assert.AreEqual('[LOG] x=42 · Unit1.pas:12', mOutput);
  finally
    mMerger.Free;
  end;
end;

procedure TAtlasEventLogFlowTests.FindSymbolPrefersFullName;
var
  mFound: TAtlasSymbol;
begin
  Assert.AreEqual('Button1Click', TAtlasEventLogFlow.SymbolName('Main.TForm1.Button1Click'));
  Assert.IsTrue(TAtlasEventLogFlow.FindSymbol([Symbol('TForm2', 'Button1Click', 'B.pas', 1),
    Symbol('TForm1', 'Button1Click', '', 2), Symbol('TForm1', 'button1click', 'A.pas', 3)],
    'Main.TForm1.Button1Click', mFound));
  Assert.AreEqual(3, mFound.Line);
  // Kein ganzer Name passt: der erste mit Datei.
  Assert.IsTrue(TAtlasEventLogFlow.FindSymbol([Symbol('TForm2', 'Button1Click', 'B.pas', 1),
    Symbol('TForm3', 'Button1Click', 'C.pas', 4)], 'Main.TForm1.Button1Click', mFound));
  Assert.AreEqual(1, mFound.Line);
  Assert.IsFalse(TAtlasEventLogFlow.FindSymbol([Symbol('TForm1', 'Button2Click', 'A.pas', 1)],
    'TForm1.Button1Click', mFound));
  Assert.AreEqual('', mFound.Name);
end;

procedure TAtlasEventLogFlowTests.ElapsedAndSaveName;
begin
  Assert.AreEqual<Int64>(0, TAtlasEventLogFlow.Elapsed(0, 5000));
  Assert.AreEqual<Int64>(1500, TAtlasEventLogFlow.Elapsed(3500, 5000));
  Assert.AreEqual('Kunden-events.txt', TAtlasEventLogFlow.SaveName('Kunden.dproj'));
  Assert.AreEqual('-events.txt', TAtlasEventLogFlow.SaveName(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEventLogFlowTests);

end.
