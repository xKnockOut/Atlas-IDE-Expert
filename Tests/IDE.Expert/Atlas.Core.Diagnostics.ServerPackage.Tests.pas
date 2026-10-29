unit Atlas.Core.Diagnostics.ServerPackage.Tests;

// Diagnosepaket des Fensters „Atlas-Server“ (#1356): Argumente an den Server,
// Dateien aus seiner Antwort (nur unter server/), Bericht zuerst, Vorschau
// mit Kürzung und Name der ZIP-Datei.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasServerDiagnosticsTests = class
  public
    [Test]
    procedure ArgumentsCarryAnonymize;
    [Test]
    procedure ReadsServerFilesAndDropsForeignNames;
    [Test]
    procedure ReportComesFirst;
    [Test]
    procedure PreviewListsFilesAndCutsLongOnes;
    [Test]
    procedure ZipNameHasDateAndTime;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  Atlas.Core.Diagnostics.Package,
  Atlas.Core.Diagnostics.ServerPackage;

procedure TAtlasServerDiagnosticsTests.ArgumentsCarryAnonymize;
begin
  Assert.AreEqual('[{"anonymize":true,"traceMinutes":5}]', TAtlasServerDiagnostics.ServerArguments(True));
  Assert.AreEqual('[{"anonymize":false,"traceMinutes":5}]', TAtlasServerDiagnostics.ServerArguments(False));
end;

procedure TAtlasServerDiagnosticsTests.ReadsServerFilesAndDropsForeignNames;
var
  mAnswer: TJSONValue;
  mFiles: TAtlasPackageFiles;
begin
  mAnswer := TJSONObject.ParseJSONValue('{"files":[{"name":"server/status.json","content":"{}"},' +
    '{"name":"server/protokoll.txt","content":"12:00 INFO gestartet"},' +
    '{"name":"../boese.txt","content":"x"},{"name":"server/../x","content":"x"},' +
    '{"name":"C:\\Windows\\x","content":"x"},{"name":"anderes/x.txt","content":"x"},' +
    '{"name":"server/","content":"x"},{"name":7,"content":"x"},{"name":"server/zahl","content":7}]}');
  try
    mFiles := TAtlasServerDiagnostics.ServerFiles(mAnswer);
  finally
    mAnswer.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mFiles)));
  Assert.AreEqual('server/status.json', mFiles[0].Name);
  Assert.AreEqual('12:00 INFO gestartet', mFiles[1].Text);
  Assert.AreEqual(0, Integer(Length(TAtlasServerDiagnostics.ServerFiles(nil))));
end;

procedure TAtlasServerDiagnosticsTests.ReportComesFirst;
var
  mFiles: TAtlasPackageFiles;
begin
  mFiles := TAtlasServerDiagnostics.Build('# Bericht', [TAtlasPackageFile.Create('server/status.json',
    TAtlasPackagePart.Logs, '{}')]);
  Assert.AreEqual(2, Integer(Length(mFiles)));
  Assert.AreEqual(TAtlasServerDiagnostics.ReportName, mFiles[0].Name);
  Assert.AreEqual('# Bericht', mFiles[0].Text);
  Assert.AreEqual('server/status.json', mFiles[1].Name);
  Assert.AreEqual(1, Integer(Length(TAtlasServerDiagnostics.Build('# Bericht', nil))), 'ohne Server nur der Bericht');
end;

procedure TAtlasServerDiagnosticsTests.PreviewListsFilesAndCutsLongOnes;
var
  mPreview: string;
begin
  mPreview := TAtlasServerDiagnostics.Preview(TAtlasServerDiagnostics.Build('# Bericht',
    [TAtlasPackageFile.Create('server/protokoll.txt', TAtlasPackagePart.Logs,
    StringOfChar('a', TAtlasServerDiagnostics.PreviewChars + 10) + 'ENDE')]), '(gekürzt)');
  Assert.IsTrue(mPreview.Contains('== fehlerbericht.md (9 Bytes) =='), mPreview);
  Assert.IsTrue(mPreview.Contains('== server/protokoll.txt ('), mPreview);
  Assert.IsTrue(mPreview.Contains('(gekürzt)'));
  Assert.IsFalse(mPreview.Contains('ENDE'), 'gekürzt');
end;

procedure TAtlasServerDiagnosticsTests.ZipNameHasDateAndTime;
begin
  Assert.AreEqual('Atlas-Server-Diagnose-2026-10-29-1430.zip',
    TAtlasServerDiagnostics.ZipName(EncodeDateTime(2026, 10, 29, 14, 30, 5, 0)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasServerDiagnosticsTests);

end.
