unit Atlas.Common.Lsp.Metrics.Tests;

// Tests des Befehls atlas.server.metrics (#66): Werte einer Datei für die
// Code Lens, Zusammenfassung für die Projekt-Zusammenfassung (#758), Bericht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspMetricsTests = class
  public
    [Test]
    procedure FileValuesWithLimitsAndSetting;
    [Test]
    procedure SummaryOverProjectFiles;
    [Test]
    procedure MarkdownAndJson;
    [Test]
    procedure UnknownModeIsRejected;
    [Test]
    procedure ProjectUrisMeanSummary;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Lsp.Metrics;

const
  MainFile = 'C:\P\Main.pas';
  HelperFile = 'C:\P\Source\Helper.pas';
  MainText = 'unit Main;'#10'interface'#10'implementation'#10'procedure Run(A, B: Integer);'#10'begin'#10 +
    '  if A > B then'#10'    Exit;'#10'end;'#10'end.';
  HelperText = 'unit Helper;'#10'interface'#10'implementation'#10'procedure Help;'#10'begin'#10'end;'#10'end.';

function NewMetrics(const AConfig: string): TLspMetrics;
begin
  Result := TLspMetrics.Create(
    function(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean
    var
      Issues: TArray<TConfigurationIssue>;
    begin
      ASource := Default(TLspMetricsSource);
      ASource.Settings := TConfigurationParser.Parse(AConfig, Issues);
      ASource.Root := 'C:\P';
      ASource.Title := 'Demo';
      if AProject then
        ASource.Files := [MainFile, HelperFile, 'C:\P\Main.dfm'];
      Result := True;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := True;
      if SameText(AFileName, MainFile) then
        AText := MainText
      else if SameText(AFileName, HelperFile) then
        AText := HelperText
      else
        Result := False;
    end);
end;

function Arguments(const AFileName, AMode: string): TJSONArray;
begin
  Result := TJSONArray.Create;
  if AFileName = '' then
    Result.AddElement(TJSONNull.Create)
  else
    Result.Add(TDocumentUris.FromPath(AFileName));
  if AMode <> '' then
    Result.Add(AMode);
end;

function Run(AMetrics: TLspMetrics; const AFileName, AMode: string): string;
var
  Args: TJSONArray;
  Answer: TJSONValue;
begin
  Args := Arguments(AFileName, AMode);
  try
    Answer := AMetrics.Execute(Args);
    try
      if Answer is TJSONString then
        Result := Answer.Value
      else
        Result := Answer.ToJSON;
    finally
      Answer.Free;
    end;
  finally
    Args.Free;
  end;
end;

{ TLspMetricsTests }

procedure TLspMetricsTests.FileValuesWithLimitsAndSetting;
var
  Metrics: TLspMetrics;
  Text: string;
begin
  Metrics := NewMetrics('{"codeLens": {"metrics": false}, "rules": {"metric-parameter-count": {"max": 1}}}');
  try
    Text := Run(Metrics, MainFile, '');
    Assert.Contains(Text, '"enabled":false');
    Assert.Contains(Text, '"parameters":1}');
    Assert.Contains(Text, '"file":"Main.pas"');
    Assert.Contains(Text, '"name":"Run","line":4,"character":11');
    Assert.Contains(Text, '"cyclomatic":2');
    Assert.Contains(Text, '"exceeded":["parameters"]');
  finally
    Metrics.Free;
  end;
end;

procedure TLspMetricsTests.SummaryOverProjectFiles;
var
  Metrics: TLspMetrics;
  Text: string;
begin
  Metrics := NewMetrics('{}');
  try
    Text := Run(Metrics, 'C:\P\Demo.dproj', 'summary');
    Assert.Contains(Text, '"format":1');
    Assert.Contains(Text, '"limits":{"length":60');
    Assert.Contains(Text, '"summary":{"files":2,"methods":2,"overLimits":0');
    Assert.IsFalse(Text.Contains('"files":['), 'keine Einzelwerte in der Zusammenfassung');
    Assert.AreEqual(2, Metrics.Collector.CachedCount);
  finally
    Metrics.Free;
  end;
end;

procedure TLspMetricsTests.MarkdownAndJson;
var
  Metrics: TLspMetrics;
  Text: string;
begin
  Metrics := NewMetrics('{}');
  try
    Text := Run(Metrics, '', 'markdown');
    Assert.Contains(Text, '# Code-Metriken: Demo');
    Assert.Contains(Text, '| Source/Helper.pas |');
    Text := Run(Metrics, '', 'json');
    Assert.Contains(Text, '"files":[{"file":"Main.pas"');
  finally
    Metrics.Free;
  end;
end;

procedure TLspMetricsTests.UnknownModeIsRejected;
var
  Metrics: TLspMetrics;
begin
  Metrics := NewMetrics('{}');
  try
    Assert.WillRaise(
      procedure
      begin
        Run(Metrics, MainFile, 'html');
      end, EJsonRpcError);
  finally
    Metrics.Free;
  end;
end;

procedure TLspMetricsTests.ProjectUrisMeanSummary;
begin
  Assert.IsTrue(TLspMetrics.IsProject('C:\P\Demo.dproj'));
  Assert.IsTrue(TLspMetrics.IsProject('C:\P\Demo.dpr'));
  Assert.IsTrue(TLspMetrics.IsProject('C:\P'));
  Assert.IsTrue(TLspMetrics.IsProject(''));
  Assert.IsFalse(TLspMetrics.IsProject('C:\P\Main.pas'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspMetricsTests);

end.
