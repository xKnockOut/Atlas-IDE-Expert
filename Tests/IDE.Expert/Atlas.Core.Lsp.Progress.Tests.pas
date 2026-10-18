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
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    AProgress.Handle(Value);
  finally
    Value.Free;
  end;
end;

procedure TLspProgressTests.TracksBeginReportEnd;
var
  Progress: ILspProgress;
begin
  Progress := TLspProgress.Create;
  Assert.AreEqual('', Progress.Text);
  Send(Progress, '{"token":"atlas-index","value":{"kind":"begin","title":"Index","percentage":0}}');
  Assert.AreEqual('Index 0 %', Progress.Text);
  Send(Progress, '{"token":"atlas-index","value":{"kind":"report","percentage":45,"message":"Units"}}');
  Assert.AreEqual('Index 45 %', Progress.Text);
  Send(Progress, '{"token":"atlas-index","value":{"kind":"end"}}');
  Assert.AreEqual('', Progress.Text);
end;

procedure TLspProgressTests.IgnoresForeignMessages;
var
  Progress: ILspProgress;
begin
  Progress := TLspProgress.Create;
  Send(Progress, '{"token":"x"}');
  Send(Progress, '[1,2]');
  Progress.Handle(nil);
  Assert.AreEqual('', Progress.Text);
  Send(Progress, '{"token":"c","value":{"kind":"begin","title":"Kompilieren"}}');
  Assert.AreEqual('Kompilieren', Progress.Text, 'ohne Prozent nur der Titel');
end;

procedure TLspProgressTests.StatusLinesNameUnitsAndWorkspaces;
var
  Status: TJSONValue;
  Lines: TArray<string>;
begin
  Status := TJSONObject.ParseJSONValue('{"units":120,"symbols":5400,"indexBytes":2097152,' +
    '"workspaces":[{"name":"Demo","lastIndexMs":850,"parsed":3,"fromCache":117,"missing":1}]}');
  try
    Lines := TLspIndexStatus.Lines(Status);
  finally
    Status.Free;
  end;
  Assert.AreEqual(2, Integer(Length(Lines)));
  Assert.Contains(Lines[0], '120 Units');
  Assert.Contains(Lines[0], '5400 Symbole');
  Assert.Contains(Lines[1], 'Demo: letzter Lauf 850 ms, 3 gelesen, 117 aus dem Cache, 1 fehlen');
  Assert.AreEqual(0, Integer(Length(TLspIndexStatus.Lines(nil))));
end;

procedure TLspProgressTests.IndexingTextForStatusBar;
var
  Progress: ILspProgress;
begin
  // #492: Statusleiste „Atlas indiziert … (n %)“, nie modal; leer, wenn nichts läuft.
  Progress := TLspProgress.Create;
  Assert.AreEqual('', Progress.IndexingText);
  Send(Progress, '{"token":"i","value":{"kind":"begin","title":"Symbolindex"}}');
  Assert.AreEqual('Atlas indiziert …', Progress.IndexingText);
  Send(Progress, '{"token":"i","value":{"kind":"report","percentage":45}}');
  Assert.AreEqual('Atlas indiziert … (45 %)', Progress.IndexingText);
  Send(Progress, '{"token":"i","value":{"kind":"end"}}');
  Assert.AreEqual('', Progress.IndexingText);
end;

procedure TLspProgressTests.MetricsForSettingsPage;
var
  Status: TJSONValue;
  Metrics: TLspIndexMetrics;
begin
  // #492: Units, Deklarationen, Größe (Speicher und Platte), letzte Aktualisierung.
  Status := TJSONObject.ParseJSONValue('{"units":1000,"symbols":250000,"indexBytes":104857600,' +
    '"budgetBytes":268435456,"offloadedUnits":12,"diskBytes":52428800,' +
    '"workspaces":[{"name":"A","lastUpdate":"2026-10-14T10:00:00.000Z"},{"name":"B","lastUpdate":""}]}');
  try
    Metrics := TLspIndexStatus.Metrics(Status);
  finally
    Status.Free;
  end;
  Assert.IsTrue(Metrics.Valid);
  Assert.AreEqual(1000, Metrics.Units);
  Assert.AreEqual(250000, Metrics.Declarations);
  Assert.AreEqual(Int64(52428800), Metrics.DiskBytes);
  Assert.AreEqual(12, Metrics.OffloadedUnits);
  Assert.IsTrue(Metrics.LastUpdate > 0, 'jüngste Aktualisierung der Ordner');
  Assert.Contains(Metrics.Text, 'Units: 1000 · Deklarationen: 250000');
  Assert.Contains(Metrics.Text, 'Im Speicher: 100,0 MB von 256,0 MB (Verwendungen von 12 Units ausgelagert)');
  Assert.Contains(Metrics.Text, 'Auf der Platte: 50,0 MB');
  Assert.IsFalse(TLspIndexStatus.Metrics(nil).Valid);
  Assert.Contains(TLspIndexStatus.Metrics(nil).Text, 'nicht verfügbar');
end;

procedure TLspProgressTests.ClearedTextNamesCachesAndSize;
var
  Answer: TJSONValue;
begin
  Answer := TJSONObject.ParseJSONValue('{"removed":3,"freedBytes":2048}');
  try
    Assert.AreEqual('Index gelöscht: 3 Caches, 2,0 KB frei; er wird neu aufgebaut.',
      TLspIndexStatus.ClearedText(Answer));
  finally
    Answer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspProgressTests);

end.
