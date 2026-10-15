unit Atlas.Common.Metrics.Collector.Tests;

// Tests der Sammlung über mehrere Dateien (#66): relative Pfade, nur
// Quelltexte, Zwischenspeicher je Datei.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMetricsCollectorTests = class
  public
    [Test]
    procedure RelativePathUsesSlashes;
    [Test]
    procedure CollectsSourcesOnceAndSkipsMissing;
    [Test]
    procedure CacheFollowsText;
    [Test]
    procedure ChecksumDiffers;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Collector;

const
  OneRoutine = 'unit A;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'end;'#10'end.';
  TwoRoutines = 'unit A;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'end;'#10 +
    'procedure Q;'#10'begin'#10'  if X then Y;'#10'end;'#10'end.';

{ TMetricsCollectorTests }

procedure TMetricsCollectorTests.RelativePathUsesSlashes;
begin
  Assert.AreEqual('Source/Main.pas', TMetricsCollector.RelativePath('C:\Projekt', 'C:\Projekt\Source\Main.pas'));
  Assert.AreEqual('Main.pas', TMetricsCollector.RelativePath('C:\Projekt\', 'c:\projekt\Main.pas'));
  Assert.AreEqual('D:\Lib\X.pas', TMetricsCollector.RelativePath('C:\Projekt', 'D:\Lib\X.pas'));
  Assert.AreEqual('D:\Lib\X.pas', TMetricsCollector.RelativePath('', 'D:\Lib\X.pas'));
end;

procedure TMetricsCollectorTests.CollectsSourcesOnceAndSkipsMissing;
var
  Collector: TMetricsCollector;
  Files: TArray<TFileMetrics>;
begin
  Collector := TMetricsCollector.Create;
  try
    Files := Collector.Collect(['C:\P\A.pas', 'C:\P\a.PAS', 'C:\P\Form.dfm', 'C:\P\Fehlt.pas', 'C:\P\App.dpr'],
      'C:\P',
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := not AFileName.EndsWith('Fehlt.pas');
        AText := OneRoutine;
      end);
    Assert.AreEqual(2, Integer(Length(Files)));
    Assert.AreEqual('A.pas', Files[0].Path);
    Assert.AreEqual(1, Integer(Length(Files[0].Routines)));
    Assert.AreEqual('App.dpr', Files[1].Path);
  finally
    Collector.Free;
  end;
end;

procedure TMetricsCollectorTests.CacheFollowsText;
var
  Collector: TMetricsCollector;
begin
  Collector := TMetricsCollector.Create;
  try
    Assert.AreEqual(1, Integer(Length(Collector.FileRoutines('C:\P\A.pas', OneRoutine))));
    Assert.AreEqual(1, Collector.CachedCount);
    Assert.AreEqual(1, Integer(Length(Collector.FileRoutines('c:\p\a.pas', OneRoutine))), 'aus dem Speicher');
    Assert.AreEqual(1, Collector.CachedCount);
    Assert.AreEqual(2, Integer(Length(Collector.FileRoutines('C:\P\A.pas', TwoRoutines))), 'Text geändert');
    Assert.AreEqual(2, Collector.FileRoutines('C:\P\A.pas', TwoRoutines)[1].Values[TMetricKind.Cyclomatic]);
  finally
    Collector.Free;
  end;
end;

procedure TMetricsCollectorTests.ChecksumDiffers;
begin
  Assert.IsTrue(TMetricsCollector.Checksum('ab') <> TMetricsCollector.Checksum('ba'));
  Assert.IsTrue(TMetricsCollector.Checksum('') = 2166136261);
end;

initialization
  TDUnitX.RegisterTestFixture(TMetricsCollectorTests);

end.
