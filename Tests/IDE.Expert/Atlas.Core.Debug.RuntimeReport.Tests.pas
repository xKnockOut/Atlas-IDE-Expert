unit Atlas.Core.Debug.RuntimeReport.Tests;

// Leck- und Absturzberichte im Editor (#74), Plugin-Seite: Argumente an den Server, Antwort mit Threads bzw.
// Leckgruppen, Stand der Map, unlesbare Antwort, Ort einer Stapelzeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasRuntimeReportTests = class
  public
    [Test]
    procedure ArgumentsCarryProjectAndText;
    [Test]
    procedure ReadsCrashWithThreads;
    [Test]
    procedure ReadsLeakGroups;
    [Test]
    procedure MapStatusDiffers;
    [Test]
    procedure RejectsBadAnswer;
    [Test]
    procedure FrameLocation;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Debug.RuntimeReport;

const
  cCrash = '{"kind":"crash","source":"madExcept","title":"EAccessViolation: Zugriff","mapStatus":"matches",' +
    '"map":"C:\\P\\Kunden.map","diagnostics":2,"crash":{"exceptionClass":"EAccessViolation","message":"Zugriff",' +
    '"address":"$00401112","module":"Kunden.exe"},"threads":[{"name":"main thread ($1a2c)","crashed":true,' +
    '"site":1,"frames":[{"address":"$00401112","module":"Kunden.exe","unit":"System.SysUtils","routine":"RaiseIt",' +
    '"line":900},{"address":"$00401112","module":"Kunden.exe","unit":"Kunden.Liste",' +
    '"routine":"TKundenListe.Lade","line":42,"uri":"file:///C:/P/Kunden.Liste.pas",' +
    '"file":"C:\\P\\Kunden.Liste.pas"}]},{"name":"thread $2b3c","crashed":false,"site":-1,"frames":[]}]}';

  cLeaks = '{"kind":"leaks","source":"FastMM","title":"2 Lecks (1 Arten)","mapStatus":"none","map":"",' +
    '"diagnostics":1,"groups":[{"name":"TStringList","kind":"instance","count":2,"size":40,"site":0,' +
    '"frames":[{"address":"$004C2C10","module":"","unit":"Kunden.Liste","routine":"TKundenListe.Lade",' +
    '"line":42,"file":"C:\\P\\Kunden.Liste.pas"}]}]}';

procedure TAtlasRuntimeReportTests.ArgumentsCarryProjectAndText;
var
  mValue: TJSONValue;
  mArguments: TJSONArray;
begin
  mValue := TJSONObject.ParseJSONValue(TAtlasRuntimeReports.ArgumentsJson('C:\P\Kunden.dproj', 'Bericht'));
  try
    Assert.IsTrue(mValue is TJSONArray);
    mArguments := TJSONArray(mValue);
    Assert.AreEqual(2, mArguments.Count);
    Assert.IsTrue(mArguments.Items[0].Value.EndsWith('Kunden.dproj'), mArguments.Items[0].Value);
    Assert.AreEqual('Bericht', (mArguments.Items[1] as TJSONObject).GetValue<string>('text'));
  finally
    mValue.Free;
  end;
  mValue := TJSONObject.ParseJSONValue(TAtlasRuntimeReports.ClearArgumentsJson('C:\P\Kunden.dproj'));
  try
    Assert.AreEqual(1, TJSONArray(mValue).Count);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasRuntimeReportTests.ReadsCrashWithThreads;
var
  mReport: TAtlasRuntimeReport;
begin
  Assert.IsTrue(TAtlasRuntimeReports.FromJson(cCrash, mReport));
  Assert.AreEqual<TAtlasRuntimeReportKind>(TAtlasRuntimeReportKind.Crash, mReport.Kind);
  Assert.AreEqual('madExcept', mReport.Source);
  Assert.AreEqual('EAccessViolation: Zugriff', mReport.Title);
  Assert.AreEqual<TAtlasRuntimeMapStatus>(TAtlasRuntimeMapStatus.Matches, mReport.MapStatus);
  Assert.AreEqual('C:\P\Kunden.map', mReport.MapName);
  Assert.AreEqual(2, mReport.Diagnostics);
  Assert.AreEqual('EAccessViolation', mReport.ExceptionClass);
  Assert.AreEqual('$00401112', mReport.Address);
  Assert.AreEqual('Kunden.exe', mReport.Module);
  Assert.AreEqual(2, Integer(Length(mReport.Stacks)));
  Assert.IsTrue(mReport.Stacks[0].Crashed);
  Assert.AreEqual(1, mReport.Stacks[0].Site);
  Assert.AreEqual('C:\P\Kunden.Liste.pas', mReport.Stacks[0].Frames[1].FileName);
  Assert.AreEqual(42, mReport.Stacks[0].Frames[1].Line);
  Assert.AreEqual('', mReport.Stacks[0].Frames[0].FileName);
  Assert.IsFalse(mReport.Stacks[1].Crashed);
  Assert.AreEqual(-1, mReport.Stacks[1].Site);
end;

procedure TAtlasRuntimeReportTests.ReadsLeakGroups;
var
  mReport: TAtlasRuntimeReport;
begin
  Assert.IsTrue(TAtlasRuntimeReports.FromJson(cLeaks, mReport));
  Assert.AreEqual<TAtlasRuntimeReportKind>(TAtlasRuntimeReportKind.Leaks, mReport.Kind);
  Assert.AreEqual<TAtlasRuntimeMapStatus>(TAtlasRuntimeMapStatus.None, mReport.MapStatus);
  Assert.AreEqual(1, Integer(Length(mReport.Stacks)));
  Assert.AreEqual('TStringList', mReport.Stacks[0].Name);
  Assert.AreEqual('instance', mReport.Stacks[0].LeakKind);
  Assert.AreEqual(2, mReport.Stacks[0].Count);
  Assert.AreEqual<Int64>(40, mReport.Stacks[0].Size);
  Assert.AreEqual(0, mReport.Stacks[0].Site);
end;

procedure TAtlasRuntimeReportTests.MapStatusDiffers;
var
  mReport: TAtlasRuntimeReport;
begin
  Assert.IsTrue(TAtlasRuntimeReports.FromJson('{"kind":"crash","mapStatus":"entryPointDiffers"}', mReport));
  Assert.AreEqual<TAtlasRuntimeMapStatus>(TAtlasRuntimeMapStatus.Differs, mReport.MapStatus);
  Assert.IsTrue(TAtlasRuntimeReports.FromJson('{"kind":"crash","mapStatus":"missing"}', mReport));
  Assert.AreEqual<TAtlasRuntimeMapStatus>(TAtlasRuntimeMapStatus.Missing, mReport.MapStatus);
end;

procedure TAtlasRuntimeReportTests.RejectsBadAnswer;
var
  mReport: TAtlasRuntimeReport;
begin
  Assert.IsFalse(TAtlasRuntimeReports.FromJson('', mReport));
  Assert.IsFalse(TAtlasRuntimeReports.FromJson('[1]', mReport));
  Assert.IsFalse(TAtlasRuntimeReports.FromJson('{"error":"x"}', mReport));
  // Stelle hinter den gelieferten Zeilen gilt als keine.
  Assert.IsTrue(TAtlasRuntimeReports.FromJson('{"kind":"leaks","groups":[{"name":"T","site":3,"frames":[]}]}',
    mReport));
  Assert.AreEqual(-1, mReport.Stacks[0].Site);
end;

procedure TAtlasRuntimeReportTests.FrameLocation;
var
  mFrame: TAtlasRuntimeFrame;
begin
  mFrame := Default(TAtlasRuntimeFrame);
  mFrame.UnitName := 'Kunden.Liste';
  mFrame.Routine := 'TKundenListe.Lade';
  Assert.AreEqual('Kunden.Liste.TKundenListe.Lade', mFrame.Location);
  mFrame.Routine := 'Kunden.Liste.TKundenListe.Lade';
  Assert.AreEqual('Kunden.Liste.TKundenListe.Lade', mFrame.Location);
  mFrame.Routine := '';
  Assert.AreEqual('Kunden.Liste', mFrame.Location);
  mFrame.UnitName := '';
  mFrame.Address := '$00401112';
  mFrame.Module := 'Kunden.exe';
  Assert.AreEqual('$00401112 Kunden.exe', mFrame.Location);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRuntimeReportTests);

end.
