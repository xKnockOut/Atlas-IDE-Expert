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
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
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

initialization
  TDUnitX.RegisterTestFixture(TLspProgressTests);

end.
