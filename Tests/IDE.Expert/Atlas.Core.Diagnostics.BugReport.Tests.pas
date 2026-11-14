unit Atlas.Core.Diagnostics.BugReport.Tests;

// Fehlerbericht des Plugins (#108): Aufbau mit und ohne Server,
// Argumente für den Server, Anonymisierung ohne Projektpfad, Auszug aus
// atlas.log, Fehlerausgabe des Servers.

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
  cRoot = 'C:\Projekte\Kunde';

function Input: TAtlasBugReportInput;
begin
  Result := Default(TAtlasBugReportInput);
  Result.PluginVersion := '0.1.0';
  Result.IdeVersion := '37.0';
  Result.Platform := 'Win32';
  Result.Settings := '{"ServerPath": "C:\\Projekte\\Kunde\\bin\\AtlasServer.exe", "Diagnose": 0}';
  Result.PluginLog := ['2026-10-14 10:00:00.000 Vervollständigung: EAccessViolation in "TKundeForm"',
    '2026-10-14 10:00:01.000 Datei ' + cRoot + '\Main.pas'];
  Result.ServerReport := '# Atlas-Fehlerbericht (Server)' + sLineBreak + sLineBreak + '## Version' + sLineBreak +
    '- Server: 0.1.0';
  Result.Roots := [cRoot];
  Result.Identity := ['marco'];
  Result.Anonymize := True;
  Result.Created := EncodeDate(2026, 10, 14);
end;

procedure TAtlasBugReportTests.BuildsPluginAndServerPart;
var
  mText: string;
begin
  mText := TAtlasBugReport.Build(Input);
  Assert.StartsWith('# Atlas-Fehlerbericht', mText);
  Assert.Contains(mText, '- Atlas: 0.1.0');
  Assert.Contains(mText, '- IDE: 37.0');
  Assert.Contains(mText, '- Plattform: Win32');
  // Anonym bleiben von den Einstellungen Schlüssel, Zahlen und feste Werte (#1478); die Schreibweise des
  // Formatierers zählt nicht.
  Assert.IsTrue(mText.Contains('"Diagnose": 0') or mText.Contains('"Diagnose":0'), mText);
  Assert.Contains(mText, 'letzte 2 Zeilen');
  // Überschriften des Servers eine Ebene tiefer.
  Assert.Contains(mText, '## Atlas-Fehlerbericht (Server)');
  Assert.Contains(mText, '### Version');
  Assert.Contains(mText, TAtlasBugReport.cIssuesUrl);
end;

procedure TAtlasBugReportTests.WithoutServerSaysWhy;
var
  mReport: TAtlasBugReportInput;
  mText: string;
begin
  mReport := Input;
  mReport.ServerReport := '';
  mReport.ServerMissing := 'Der Server läuft nicht.';
  mText := TAtlasBugReport.Build(mReport);
  Assert.Contains(mText, '## Server');
  Assert.Contains(mText, 'Der Server läuft nicht.');
end;

procedure TAtlasBugReportTests.AnonymizedReportHasNoProjectPath;
var
  mText: string;
begin
  mText := TAtlasBugReport.Build(Input);
  Assert.DoesNotContain(mText, 'Projekte', True);
  Assert.DoesNotContain(mText, 'TKundeForm');
  Assert.Contains(mText, '<ws>/<datei>.pas');
  Assert.Contains(mText, '"<wert>"');
  Assert.Contains(mText, 'anonymisiert');
  Assert.AreEqual('<pfad> und <ws>/<datei>.pas', TAtlasBugReport.AnonymizePaths('D:\x\y.dpr und C:/Projekte/Kunde/a.pas',
    [cRoot + '\'], []));
  Assert.AreEqual('Benutzer <benutzer>', TAtlasBugReport.AnonymizePaths('Benutzer MARCO', [], ['marco']));
end;

procedure TAtlasBugReportTests.PlainReportKeepsPaths;
var
  mReport: TAtlasBugReportInput;
  mText: string;
begin
  mReport := Input;
  mReport.Anonymize := False;
  mReport.PluginLogNames := True;
  mText := TAtlasBugReport.Build(mReport);
  Assert.Contains(mText, cRoot + '\Main.pas');
  Assert.Contains(mText, 'TKundeForm');
  Assert.DoesNotContain(mText, 'anonymisiert');
  // Klarnamen nur ausdrücklich, sichtbar vermerkt (#1478).
  Assert.IsTrue(mText.Contains('mit Klarnamen (ausdrücklich gewählt)'), mText);
  Assert.IsTrue(mText.Contains('geschrieben mit Klarnamen (diagnostics.log.names)'), mText);
end;

procedure TAtlasBugReportTests.ServerArgumentsCarryAnonymizeAndClient;
var
  mValue: TJSONValue;
  mOptions: TJSONObject;
begin
  mValue := TJSONObject.ParseJSONValue(TAtlasBugReport.ServerArguments(Input));
  try
    Assert.IsTrue(mValue is TJSONArray);
    mOptions := TJSONArray(mValue).Items[0] as TJSONObject;
    Assert.IsTrue((mOptions.GetValue('anonymize') as TJSONBool).AsBoolean);
    Assert.AreEqual('Atlas-Plugin 0.1.0, IDE 37.0, Win32', mOptions.GetValue('client').Value);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasBugReportTests.TailReadsLastLines;
var
  mFileName: string;
  mLines: TArray<string>;
begin
  mFileName := TPath.Combine(TPath.GetTempPath, 'atlas-bugreport-tail.log');
  TFile.WriteAllText(mFileName, 'a' + sLineBreak + 'b' + sLineBreak + 'c' + sLineBreak + 'd' + sLineBreak,
    TEncoding.UTF8);
  try
    mLines := TAtlasBugReport.Tail(mFileName, 2);
    Assert.AreEqual(2, Integer(Length(mLines)));
    Assert.AreEqual('c', mLines[0]);
    Assert.AreEqual('d', mLines[1]);
    Assert.AreEqual(0, Integer(Length(TAtlasBugReport.Tail(mFileName + '.fehlt', 2))));
  finally
    TFile.Delete(mFileName);
  end;
  Assert.AreEqual('atlas-fehlerbericht-20261014-0000.md', TAtlasBugReport.DefaultFileName(EncodeDate(2026, 10, 14)));
end;

procedure TAtlasBugReportTests.ServerErrorOutputIsAnonymizedSection;
var
  mReport: TAtlasBugReportInput;
  mText: string;
begin
  mReport := Input;
  mText := TAtlasBugReport.Build(mReport);
  Assert.DoesNotContain(mText, 'Fehlerausgabe des Servers', 'ohne stderr kein Abschnitt');
  mReport.ServerErrorOutput := ['---- 2026-10-22 10:00:00 Serverstart ----',
    'Exception EStackOverflow in "TKundeForm" bei ' + cRoot + '\Main.pas'];
  mText := TAtlasBugReport.Build(mReport);
  Assert.Contains(mText, '### Fehlerausgabe des Servers (stderr, letzte 2 Zeilen)');
  Assert.Contains(mText, 'Serverstart');
  Assert.Contains(mText, 'EStackOverflow');
  Assert.DoesNotContain(mText, 'TKundeForm');
  Assert.DoesNotContain(mText, 'Projekte', True);
  // Vor dem Teil des Servers.
  Assert.IsTrue(Pos('Fehlerausgabe des Servers', mText) < Pos('## Atlas-Fehlerbericht (Server)', mText));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBugReportTests);

end.
