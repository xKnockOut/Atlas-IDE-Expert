unit Atlas.Common.Diagnostics.ServerPackage.Tests;

// Tests für den Teil des Servers im Diagnosepaket (#1356): Dateien, Trace nur
// mit --trace, Anonymisierung wie der Fehlerbericht (#108) und keine
// Zugangsdaten, auch nicht ohne Anonymisierung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TServerPackageTests = class
  public
    [Test]
    procedure ContainsStatusAndLogWithoutTrace;
    [Test]
    procedure ContainsTraceWhenTracing;
    [Test]
    procedure TraceLineKeepsMethodKeysAndNumbers;
    [Test]
    procedure TraceLineWithoutJsonIsDropped;
    [Test]
    procedure LogAndStatusAreAnonymized;
    [Test]
    procedure SecretsNeverLeaveEvenWithoutAnonymizing;
    [Test]
    procedure JsonListsFiles;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Diagnostics.ServerPackage;

function Input: TServerPackageInput;
begin
  Result := Default(TServerPackageInput);
  Result.StatusJson := '{"units":3,"workspaces":[{"name":"Kunde"}]}';
  Result.LogLines := ['12:00:00 INFO Server gestartet'];
  Result.TraceMinutes := 5;
  Result.Workspaces := ['C:\Projekte\Kunde'];
  Result.Identity := ['marco'];
end;

function FileNamed(const AFiles: TArray<TServerPackageFile>; const AName: string): string;
var
  mFile: TServerPackageFile;
begin
  for mFile in AFiles do
    if mFile.Name = AName then
      Exit(mFile.Content);
  Result := '';
end;

procedure TServerPackageTests.ContainsStatusAndLogWithoutTrace;
var
  mFiles: TArray<TServerPackageFile>;
begin
  mFiles := TServerPackage.Build(Input);
  Assert.AreEqual(2, Integer(Length(mFiles)));
  Assert.AreEqual(TServerPackage.StatusName, mFiles[0].Name);
  Assert.AreEqual(TServerPackage.LogName, mFiles[1].Name);
  Assert.IsTrue(mFiles[0].Content.Contains('"units"'), mFiles[0].Content);
  Assert.IsTrue(mFiles[1].Content.Contains('Server gestartet'), mFiles[1].Content);
end;

procedure TServerPackageTests.ContainsTraceWhenTracing;
var
  mInput: TServerPackageInput;
  mTrace: string;
begin
  mInput := Input;
  mInput.Tracing := True;
  mInput.TraceLines := ['2026-10-29 12:00:00.000 --> {"jsonrpc":"2.0","id":4,"method":"textDocument/hover"}'];
  mTrace := FileNamed(TServerPackage.Build(mInput), TServerPackage.TraceName);
  Assert.IsTrue(mTrace.Contains('letzten 5 Minuten'), mTrace);
  Assert.IsTrue(mTrace.Contains('textDocument/hover'), mTrace);
end;

procedure TServerPackageTests.TraceLineKeepsMethodKeysAndNumbers;
var
  mLine: string;
begin
  mLine := TServerPackage.AnonymizeTraceLine('2026-10-29 12:00:00.000 --> {"jsonrpc":"2.0","id":4,' +
    '"method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///C:/Kunde/Geheim.pas",' +
    '"version":2,"text":"unit Geheim;"},"tags":["Kunde",7]}}');
  Assert.IsTrue(mLine.StartsWith('2026-10-29 12:00:00.000 --> {'), mLine);
  Assert.IsTrue(mLine.Contains('"method":"textDocument/didOpen"'), mLine);
  Assert.IsTrue(mLine.Contains('"jsonrpc":"2.0"'), mLine);
  Assert.IsTrue(mLine.Contains('"id":4'), mLine);
  Assert.IsTrue(mLine.Contains('"version":2'), mLine);
  Assert.IsTrue(mLine.Contains('"uri":"<wert>"'), mLine);
  Assert.IsFalse(mLine.Contains('Geheim'), mLine);
  Assert.IsFalse(mLine.Contains('Kunde'), mLine);
  Assert.IsTrue(mLine.Contains('7'), mLine);
end;

procedure TServerPackageTests.TraceLineWithoutJsonIsDropped;
var
  mInput: TServerPackageInput;
  mTrace: string;
begin
  Assert.AreEqual('', TServerPackage.AnonymizeTraceLine('2026-10-29 12:00:00.000 --> !! EReadError: C:\Kunde'));
  mInput := Input;
  mInput.Tracing := True;
  mInput.Anonymize := True;
  mInput.TraceLines := ['2026-10-29 12:00:00.000 --> !! EReadError: C:\Kunde'];
  mTrace := FileNamed(TServerPackage.Build(mInput), TServerPackage.TraceName);
  Assert.IsFalse(mTrace.Contains('Kunde'), mTrace);
  Assert.IsTrue(mTrace.Contains('1 Zeilen ohne JSON ausgelassen'), mTrace);
end;

procedure TServerPackageTests.LogAndStatusAreAnonymized;
var
  mInput: TServerPackageInput;
  mFiles: TArray<TServerPackageFile>;
begin
  mInput := Input;
  mInput.Anonymize := True;
  mInput.StatusJson := '{"workspaces":[{"cacheFile":"C:\\Projekte\\Kunde\\x.atlasidx","user":"C:\\Users\\marco"}]}';
  mInput.LogLines := ['12:00:00 INFO Geöffnet: C:\Projekte\Kunde\Haupt.pas "Haupt"'];
  mFiles := TServerPackage.Build(mInput);
  Assert.IsFalse(FileNamed(mFiles, TServerPackage.StatusName).Contains('Projekte'),
    FileNamed(mFiles, TServerPackage.StatusName));
  Assert.IsFalse(FileNamed(mFiles, TServerPackage.StatusName).Contains('marco'),
    FileNamed(mFiles, TServerPackage.StatusName));
  Assert.IsFalse(FileNamed(mFiles, TServerPackage.LogName).Contains('Projekte'), FileNamed(mFiles,
    TServerPackage.LogName));
  Assert.IsFalse(FileNamed(mFiles, TServerPackage.LogName).Contains('"Haupt"'), FileNamed(mFiles,
    TServerPackage.LogName));
end;

procedure TServerPackageTests.SecretsNeverLeaveEvenWithoutAnonymizing;
var
  mInput: TServerPackageInput;
  mFiles: TArray<TServerPackageFile>;
begin
  mInput := Input;
  mInput.Anonymize := False;
  mInput.Tracing := True;
  mInput.StatusJson := '{"tracker":{"apiToken":"abc123","url":"https://example.org"}}';
  mInput.TraceLines := ['2026-10-29 12:00:00.000 --> {"jsonrpc":"2.0","method":"x","params":{"password":"s3cr3t"}}'];
  mFiles := TServerPackage.Build(mInput);
  Assert.IsFalse(FileNamed(mFiles, TServerPackage.StatusName).Contains('abc123'),
    FileNamed(mFiles, TServerPackage.StatusName));
  Assert.IsTrue(FileNamed(mFiles, TServerPackage.StatusName).Contains('https://example.org'),
    FileNamed(mFiles, TServerPackage.StatusName));
  Assert.IsTrue(TServerPackage.IsSecretKey('Authorization'));
  Assert.IsFalse(TServerPackage.IsSecretKey('method'));
  // Ohne Anonymisierung bleibt der Trace lesbar, nur die Zugangsdaten werden ersetzt.
  Assert.IsFalse(FileNamed(mFiles, TServerPackage.TraceName).Contains('s3cr3t'),
    FileNamed(mFiles, TServerPackage.TraceName));
  Assert.IsTrue(FileNamed(mFiles, TServerPackage.TraceName).Contains(TServerPackage.SecretLabel),
    FileNamed(mFiles, TServerPackage.TraceName));
  Assert.IsTrue(FileNamed(mFiles, TServerPackage.TraceName).Contains('"method":"x"'),
    FileNamed(mFiles, TServerPackage.TraceName));
  Assert.AreEqual('kein JSON', TServerPackage.SecretFreeTraceLine('kein JSON'));
end;

procedure TServerPackageTests.JsonListsFiles;
var
  mJson: TJSONObject;
  mFiles: TJSONArray;
begin
  mJson := TServerPackage.ToJson(TServerPackage.Build(Input));
  try
    mFiles := mJson.GetValue('files') as TJSONArray;
    Assert.AreEqual(2, mFiles.Count);
    Assert.AreEqual(TServerPackage.StatusName, (mFiles.Items[0] as TJSONObject).GetValue('name').Value);
    Assert.IsTrue((mFiles.Items[1] as TJSONObject).GetValue('content').Value.Contains('Server gestartet'));
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TServerPackageTests);

end.
