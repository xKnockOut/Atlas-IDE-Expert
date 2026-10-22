unit Atlas.Core.Diagnostics.BugReport.Tests;

// Fehlerbericht des Plugins (#108): Aufbau mit und ohne Server,
// Argumente für den Server, Anonymisierung ohne Projektpfad, Auszug aus
// atlas.log, Fehlerausgabe des Servers (Bericht H5).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBugReportTests = class
  public
    [Test]
    procedure BuildsPluginAndServerPart;
    [Test]
    procedure WithoutServerSaysWhy;
    [Test]
    procedure AnonymizedReportHasNoProjectPath;
    [Test]
    procedure PlainReportKeepsPaths;
    [Test]
    procedure ServerArgumentsCarryAnonymizeAndClient;
    [Test]
    procedure TailReadsLastLines;
    [Test]
    procedure ServerErrorOutputIsAnonymizedSection;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Diagnostics.BugReport;

const
  Root = 'C:\Projekte\Kunde';

function Input: TAtlasBugReportInput;
begin
  Result := Default(TAtlasBugReportInput);
  Result.PluginVersion := '0.1.0';
  Result.IdeVersion := '37.0';
  Result.Platform := 'Win32';
  Result.Settings := '{"ServerPath": "C:\\Projekte\\Kunde\\bin\\AtlasServer.exe", "Diagnose": 0}';
  Result.PluginLog := ['2026-10-14 10:00:00.000 Vervollständigung: EAccessViolation in "TKundeForm"',
    '2026-10-14 10:00:01.000 Datei ' + Root + '\Main.pas'];
  Result.ServerReport := '# Atlas-Fehlerbericht (Server)' + sLineBreak + sLineBreak + '## Version' + sLineBreak +
    '- Server: 0.1.0';
  Result.Roots := [Root];
  Result.Identity := ['marco'];
  Result.Anonymize := True;
  Result.Created := EncodeDate(2026, 10, 14);
end;

procedure TAtlasBugReportTests.BuildsPluginAndServerPart;
var
  Text: string;
begin
  Text := TAtlasBugReport.Build(Input);
  Assert.StartsWith('# Atlas-Fehlerbericht', Text);
  Assert.Contains(Text, '- Atlas: 0.1.0');
  Assert.Contains(Text, '- IDE: 37.0');
  Assert.Contains(Text, '- Plattform: Win32');
  Assert.Contains(Text, '"Diagnose": 0');
  Assert.Contains(Text, 'letzte 2 Zeilen');
  // Überschriften des Servers eine Ebene tiefer.
  Assert.Contains(Text, '## Atlas-Fehlerbericht (Server)');
  Assert.Contains(Text, '### Version');
  Assert.Contains(Text, TAtlasBugReport.IssuesUrl);
end;

procedure TAtlasBugReportTests.WithoutServerSaysWhy;
var
  Report: TAtlasBugReportInput;
  Text: string;
begin
  Report := Input;
  Report.ServerReport := '';
  Report.ServerMissing := 'Der Server läuft nicht.';
  Text := TAtlasBugReport.Build(Report);
  Assert.Contains(Text, '## Server');
  Assert.Contains(Text, 'Der Server läuft nicht.');
end;

procedure TAtlasBugReportTests.AnonymizedReportHasNoProjectPath;
var
  Text: string;
begin
  Text := TAtlasBugReport.Build(Input);
  Assert.DoesNotContain(Text, 'Projekte', True);
  Assert.DoesNotContain(Text, 'TKundeForm');
  Assert.Contains(Text, '<ws>\Main.pas');
  Assert.Contains(Text, '"<wert>"');
  Assert.Contains(Text, 'anonymisiert');
  Assert.AreEqual('<pfad> und <ws>/a.pas', TAtlasBugReport.AnonymizePaths('D:\x\y.dpr und C:/Projekte/Kunde/a.pas',
    [Root + '\'], []));
  Assert.AreEqual('Benutzer <benutzer>', TAtlasBugReport.AnonymizePaths('Benutzer MARCO', [], ['marco']));
end;

procedure TAtlasBugReportTests.PlainReportKeepsPaths;
var
  Report: TAtlasBugReportInput;
  Text: string;
begin
  Report := Input;
  Report.Anonymize := False;
  Text := TAtlasBugReport.Build(Report);
  Assert.Contains(Text, Root + '\Main.pas');
  Assert.Contains(Text, 'TKundeForm');
  Assert.DoesNotContain(Text, 'anonymisiert');
end;

procedure TAtlasBugReportTests.ServerArgumentsCarryAnonymizeAndClient;
var
  Value: TJSONValue;
  Options: TJSONObject;
begin
  Value := TJSONObject.ParseJSONValue(TAtlasBugReport.ServerArguments(Input));
  try
    Assert.IsTrue(Value is TJSONArray);
    Options := TJSONArray(Value).Items[0] as TJSONObject;
    Assert.IsTrue((Options.GetValue('anonymize') as TJSONBool).AsBoolean);
    Assert.AreEqual('Atlas-Plugin 0.1.0, IDE 37.0, Win32', Options.GetValue('client').Value);
  finally
    Value.Free;
  end;
end;

procedure TAtlasBugReportTests.TailReadsLastLines;
var
  FileName: string;
  Lines: TArray<string>;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'atlas-bugreport-tail.log');
  TFile.WriteAllText(FileName, 'a' + sLineBreak + 'b' + sLineBreak + 'c' + sLineBreak + 'd' + sLineBreak,
    TEncoding.UTF8);
  try
    Lines := TAtlasBugReport.Tail(FileName, 2);
    Assert.AreEqual(2, Integer(Length(Lines)));
    Assert.AreEqual('c', Lines[0]);
    Assert.AreEqual('d', Lines[1]);
    Assert.AreEqual(0, Integer(Length(TAtlasBugReport.Tail(FileName + '.fehlt', 2))));
  finally
    TFile.Delete(FileName);
  end;
  Assert.AreEqual('atlas-fehlerbericht-20261014-0000.md', TAtlasBugReport.DefaultFileName(EncodeDate(2026, 10, 14)));
end;

procedure TAtlasBugReportTests.ServerErrorOutputIsAnonymizedSection;
var
  Report: TAtlasBugReportInput;
  Text: string;
begin
  Report := Input;
  Text := TAtlasBugReport.Build(Report);
  Assert.DoesNotContain(Text, 'Fehlerausgabe des Servers', 'ohne stderr kein Abschnitt');
  Report.ServerErrorOutput := ['---- 2026-10-22 10:00:00 Serverstart ----',
    'Exception EStackOverflow in "TKundeForm" bei ' + Root + '\Main.pas'];
  Text := TAtlasBugReport.Build(Report);
  Assert.Contains(Text, '### Fehlerausgabe des Servers (stderr, letzte 2 Zeilen)');
  Assert.Contains(Text, 'Serverstart');
  Assert.Contains(Text, 'EStackOverflow');
  Assert.DoesNotContain(Text, 'TKundeForm');
  Assert.DoesNotContain(Text, 'Projekte', True);
  // Vor dem Teil des Servers.
  Assert.IsTrue(Pos('Fehlerausgabe des Servers', Text) < Pos('## Atlas-Fehlerbericht (Server)', Text));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBugReportTests);

end.
