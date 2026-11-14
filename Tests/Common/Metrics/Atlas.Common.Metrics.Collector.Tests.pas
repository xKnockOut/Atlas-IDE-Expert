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
  cOneRoutine = 'unit A;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'end;'#10'end.';
  cTwoRoutines = 'unit A;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'end;'#10 +
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
  mCollector: TMetricsCollector;
  mFiles: TArray<TFileMetrics>;
begin
  mCollector := TMetricsCollector.Create;
  try
    mFiles := mCollector.Collect(['C:\P\A.pas', 'C:\P\a.PAS', 'C:\P\Form.dfm', 'C:\P\Fehlt.pas', 'C:\P\App.dpr'],
      'C:\P',
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := not AFileName.EndsWith('Fehlt.pas');
        AText := cOneRoutine;
      end);
    Assert.AreEqual(2, Integer(Length(mFiles)));
    Assert.AreEqual('A.pas', mFiles[0].Path);
    Assert.AreEqual(1, Integer(Length(mFiles[0].Routines)));
    Assert.AreEqual('App.dpr', mFiles[1].Path);
  finally
    mCollector.Free;
  end;
end;

procedure TMetricsCollectorTests.CacheFollowsText;
var
  mCollector: TMetricsCollector;
begin
  mCollector := TMetricsCollector.Create;
  try
    Assert.AreEqual(1, Integer(Length(mCollector.FileRoutines('C:\P\A.pas', cOneRoutine))));
    Assert.AreEqual(1, mCollector.CachedCount);
    Assert.AreEqual(1, Integer(Length(mCollector.FileRoutines('c:\p\a.pas', cOneRoutine))), 'aus dem Speicher');
    Assert.AreEqual(1, mCollector.CachedCount);
    Assert.AreEqual(2, Integer(Length(mCollector.FileRoutines('C:\P\A.pas', cTwoRoutines))), 'Text geändert');
    Assert.AreEqual(2, mCollector.FileRoutines('C:\P\A.pas', cTwoRoutines)[1].Values[TMetricKind.Cyclomatic]);
  finally
    mCollector.Free;
  end;
end;

procedure TMetricsCollectorTests.ChecksumDiffers;
begin
  Assert.AreNotEqual<Cardinal>(TMetricsCollector.Checksum('ab'), TMetricsCollector.Checksum('ba'));
  Assert.AreEqual<Cardinal>(2166136261, TMetricsCollector.Checksum(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TMetricsCollectorTests);

end.
