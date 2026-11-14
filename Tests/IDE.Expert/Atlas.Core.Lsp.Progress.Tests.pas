unit Atlas.Core.Lsp.Progress.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Fortschritt und Kennzahlen des Server-Index im Plugin (#492).</summary>
  [TestFixture]
  TLspProgressTests = class
  public
    [Test]
    procedure TracksBeginReportEnd;
    [Test]
    procedure IgnoresForeignMessages;
    /// <summary>#2142: Stand je Token, auch wenn ein anderer Vorgang zuletzt gemeldet hat.</summary>
    [Test]
    procedure ActiveOfFollowsEachToken;
    [Test]
    procedure StatusLinesNameUnitsAndWorkspaces;
    [Test]
    procedure IndexingTextForStatusBar;
    [Test]
    procedure MetricsForSettingsPage;
    [Test]
    procedure ClearedTextNamesCachesAndSize;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Lsp.Progress;

procedure Send(const AProgress: ILspProgress; const AJson: string);
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    AProgress.Handle(mValue);
  finally
    mValue.Free;
  end;
end;

procedure TLspProgressTests.TracksBeginReportEnd;
var
  mProgress: ILspProgress;
begin
  mProgress := TLspProgress.Create;
  Assert.AreEqual('', mProgress.Text);
  Send(mProgress, '{"token":"atlas-index","value":{"kind":"begin","title":"Index","percentage":0}}');
  Assert.AreEqual('Index 0 %', mProgress.Text);
  Send(mProgress, '{"token":"atlas-index","value":{"kind":"report","percentage":45,"message":"Units"}}');
  Assert.AreEqual('Index 45 %', mProgress.Text);
  Send(mProgress, '{"token":"atlas-index","value":{"kind":"end"}}');
  Assert.AreEqual('', mProgress.Text);
end;

procedure TLspProgressTests.IgnoresForeignMessages;
var
  mProgress: ILspProgress;
begin
  mProgress := TLspProgress.Create;
  Send(mProgress, '{"token":"x"}');
  Send(mProgress, '[1,2]');
  mProgress.Handle(nil);
  Assert.AreEqual('', mProgress.Text);
  Send(mProgress, '{"token":"c","value":{"kind":"begin","title":"Kompilieren"}}');
  Assert.AreEqual('Kompilieren', mProgress.Text, 'ohne Prozent nur der Titel');
end;

procedure TLspProgressTests.ActiveOfFollowsEachToken;
var
  mProgress: ILspProgress;
  mPercent: Integer;
begin
  mProgress := TLspProgress.Create;
  Assert.IsFalse(mProgress.ActiveOf('atlas-index-1', mPercent));
  Assert.AreEqual(-1, mPercent);
  Send(mProgress, '{"token":"atlas-index-1","value":{"kind":"begin","title":"Symbolindex","percentage":0}}');
  Send(mProgress, '{"token":"atlas-index-1","value":{"kind":"report","percentage":30}}');
  Send(mProgress, '{"token":"atlas-index-1-1","value":{"kind":"begin","title":"Symbolindex"}}');
  Assert.IsTrue(mProgress.ActiveOf('atlas-index-1', mPercent));
  Assert.AreEqual(30, mPercent);
  Assert.IsTrue(mProgress.ActiveOf('atlas-index-1-1', mPercent));
  Assert.AreEqual(-1, mPercent, 'ohne Prozent');
  Send(mProgress, '{"token":"atlas-index-1","value":{"kind":"end"}}');
  Assert.IsFalse(mProgress.ActiveOf('atlas-index-1', mPercent));
  Assert.IsTrue(mProgress.ActiveOf('atlas-index-1-1', mPercent));
end;

procedure TLspProgressTests.StatusLinesNameUnitsAndWorkspaces;
var
  mStatus: TJSONValue;
  mLines: TArray<string>;
begin
  mStatus := TJSONObject.ParseJSONValue('{"units":120,"symbols":5400,"indexBytes":2097152,' +
    '"workspaces":[{"name":"Demo","lastIndexMs":850,"parsed":3,"fromCache":117,"missing":1}]}');
  try
    mLines := TLspIndexStatus.Lines(mStatus);
  finally
    mStatus.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mLines)));
  Assert.Contains(mLines[0], '120 Units');
  Assert.Contains(mLines[0], '5400 Symbole');
  Assert.Contains(mLines[1], 'Demo: letzter Lauf 850 ms, 3 gelesen, 117 aus dem Cache, 1 fehlen');
  Assert.AreEqual(0, Integer(Length(TLspIndexStatus.Lines(nil))));
end;

procedure TLspProgressTests.IndexingTextForStatusBar;
var
  mProgress: ILspProgress;
begin
  // #492: Statusleiste „Atlas indiziert … (n %)“, nie modal; leer, wenn nichts läuft.
  mProgress := TLspProgress.Create;
  Assert.AreEqual('', mProgress.IndexingText);
  Send(mProgress, '{"token":"i","value":{"kind":"begin","title":"Symbolindex"}}');
  Assert.AreEqual('Atlas indiziert …', mProgress.IndexingText);
  Send(mProgress, '{"token":"i","value":{"kind":"report","percentage":45}}');
  Assert.AreEqual('Atlas indiziert … (45 %)', mProgress.IndexingText);
  Send(mProgress, '{"token":"i","value":{"kind":"end"}}');
  Assert.AreEqual('', mProgress.IndexingText);
end;

procedure TLspProgressTests.MetricsForSettingsPage;
var
  mStatus: TJSONValue;
  mMetrics: TLspIndexMetrics;
begin
  // #492: Units, Deklarationen, Größe (Speicher und Platte), letzte Aktualisierung.
  mStatus := TJSONObject.ParseJSONValue('{"units":1000,"symbols":250000,"indexBytes":104857600,' +
    '"budgetBytes":268435456,"offloadedUnits":12,"diskBytes":52428800,' +
    '"workspaces":[{"name":"A","lastUpdate":"2026-10-14T10:00:00.000Z"},{"name":"B","lastUpdate":""}]}');
  try
    mMetrics := TLspIndexStatus.Metrics(mStatus);
  finally
    mStatus.Free;
  end;
  Assert.IsTrue(mMetrics.Valid);
  Assert.AreEqual(1000, mMetrics.Units);
  Assert.AreEqual(250000, mMetrics.Declarations);
  Assert.AreEqual(Int64(52428800), mMetrics.DiskBytes);
  Assert.AreEqual(12, mMetrics.OffloadedUnits);
  Assert.IsTrue(mMetrics.LastUpdate > 0, 'jüngste Aktualisierung der Ordner');
  Assert.Contains(mMetrics.Text, 'Units: 1000 · Deklarationen: 250000');
  Assert.Contains(mMetrics.Text, 'Im Speicher: 100,0 MB von 256,0 MB (Verwendungen von 12 Units ausgelagert)');
  Assert.Contains(mMetrics.Text, 'Auf der Platte: 50,0 MB');
  Assert.IsFalse(TLspIndexStatus.Metrics(nil).Valid);
  Assert.Contains(TLspIndexStatus.Metrics(nil).Text, 'nicht verfügbar');
end;

procedure TLspProgressTests.ClearedTextNamesCachesAndSize;
var
  mAnswer: TJSONValue;
begin
  mAnswer := TJSONObject.ParseJSONValue('{"removed":3,"freedBytes":2048}');
  try
    Assert.AreEqual('Index gelöscht: 3 Caches, 2,0 KB frei; er wird neu aufgebaut.',
      TLspIndexStatus.ClearedText(mAnswer));
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspProgressTests);

end.
