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
    [Test]
    procedure FileValuesWithInheritanceDepth;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Lsp.Metrics;

const
  cMainFile = 'C:\P\Main.pas';
  cHelperFile = 'C:\P\Source\Helper.pas';
  cMainText = 'unit Main;'#10'interface'#10'implementation'#10'procedure Run(A, B: Integer);'#10'begin'#10 +
    '  if A > B then'#10'    Exit;'#10'end;'#10'end.';
  cHelperText = 'unit Helper;'#10'interface'#10'implementation'#10'procedure Help;'#10'begin'#10'end;'#10'end.';
  cClassFile = 'C:\P\Klassen.pas';
  cClassText = 'unit Klassen;'#10'interface'#10'type'#10'  TA = class'#10'  end;'#10'  TB = class(TA)'#10'  end;'#10 +
    '  TC = class(TUnbekannt)'#10'  end;'#10'implementation'#10'end.';

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
      begin
        ASource.Files := [cMainFile, cHelperFile, 'C:\P\Main.dfm'];
      end;
      Result := True;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := True;
      if SameText(AFileName, cMainFile) then
      begin
        AText := cMainText;
      end
      else if SameText(AFileName, cHelperFile) then
      begin
        AText := cHelperText;
      end
      else if SameText(AFileName, cClassFile) then
      begin
        AText := cClassText;
      end
      else
      begin
        Result := False;
      end;
    end);
end;

function Arguments(const AFileName, AMode: string): TJSONArray;
begin
  Result := TJSONArray.Create;
  if AFileName = '' then
  begin
    Result.AddElement(TJSONNull.Create);
  end
  else
  begin
    Result.Add(TDocumentUris.FromPath(AFileName));
  end;
  if AMode <> '' then
  begin
    Result.Add(AMode);
  end;
end;

function Run(AMetrics: TLspMetrics; const AFileName, AMode: string): string;
var
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArgs := Arguments(AFileName, AMode);
  try
    mAnswer := AMetrics.Execute(mArgs);
    try
      if mAnswer is TJSONString then
      begin
        Result := mAnswer.Value;
      end
      else
      begin
        Result := mAnswer.ToJSON;
      end;
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
end;

{ TLspMetricsTests }

procedure TLspMetricsTests.FileValuesWithLimitsAndSetting;
var
  mMetrics: TLspMetrics;
  mText: string;
begin
  mMetrics := NewMetrics('{"codeLens": {"metrics": false}, "rules": {"metric-parameter-count": {"max": 1}}}');
  try
    mText := Run(mMetrics, cMainFile, '');
    Assert.Contains(mText, '"enabled":false');
    Assert.Contains(mText, '"parameters":1,"operands":5,"locals":12,"exits":4}');
    Assert.Contains(mText, '"operands":1,"locals":0,"exits":1}');
    Assert.Contains(mText, '"file":"Main.pas"');
    Assert.Contains(mText, '"name":"Run","line":4,"character":11');
    Assert.Contains(mText, '"cyclomatic":2');
    Assert.Contains(mText, '"exceeded":["parameters"]');
    // Aufbau (#939) für die Metrik-Linse.
    Assert.Contains(mText, '"structure":[{"kind":"unitLength","name":"Main","line":1,"character":6,');
    Assert.Contains(mText, '"limit":2000}');
  finally
    mMetrics.Free;
  end;
end;

procedure TLspMetricsTests.SummaryOverProjectFiles;
var
  mMetrics: TLspMetrics;
  mText: string;
begin
  mMetrics := NewMetrics('{}');
  try
    mText := Run(mMetrics, 'C:\P\Demo.dproj', 'summary');
    Assert.Contains(mText, '"format":1');
    Assert.Contains(mText, '"limits":{"length":60');
    Assert.Contains(mText, '"summary":{"files":2,"methods":2,"overLimits":0');
    Assert.IsFalse(mText.Contains('"files":['), 'keine Einzelwerte in der Zusammenfassung');
    Assert.AreEqual(2, mMetrics.Collector.CachedCount);
  finally
    mMetrics.Free;
  end;
end;

procedure TLspMetricsTests.MarkdownAndJson;
var
  mMetrics: TLspMetrics;
  mText: string;
begin
  mMetrics := NewMetrics('{}');
  try
    mText := Run(mMetrics, '', 'markdown');
    Assert.Contains(mText, '# Code-Metriken: Demo');
    Assert.Contains(mText, '| Source/Helper.pas |');
    mText := Run(mMetrics, '', 'json');
    Assert.Contains(mText, '"files":[{"file":"Main.pas"');
  finally
    mMetrics.Free;
  end;
end;

procedure TLspMetricsTests.UnknownModeIsRejected;
var
  mMetrics: TLspMetrics;
begin
  mMetrics := NewMetrics('{}');
  try
    Assert.WillRaise(
      procedure
      begin
        Run(mMetrics, cMainFile, 'html');
      end, EJsonRpcError);
  finally
    mMetrics.Free;
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

procedure TLspMetricsTests.FileValuesWithInheritanceDepth;
var
  mMetrics: TLspMetrics;
  mText: string;
begin
  mMetrics := NewMetrics('{}');
  try
    // Ohne Index keine Vererbungstiefe.
    mText := Run(mMetrics, cClassFile, '');
    Assert.DoesNotContain(mText, 'inheritanceDepth');
    mMetrics.Index := TSymbolIndex.Create;
    mText := Run(mMetrics, cClassFile, '');
    Assert.Contains(mText, '{"kind":"inheritanceDepth","name":"TB","line":6,"character":3,"value":1,"limit":5}');
    // TA hat keine eigenen Vorfahren, TC nur einen unbekannten: beide fehlen.
    Assert.DoesNotContain(mText, '"inheritanceDepth","name":"TA"');
    Assert.DoesNotContain(mText, '"inheritanceDepth","name":"TC"');
  finally
    mMetrics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspMetricsTests);

end.
