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
    /// <summary>#2611: Aufrufstatistik der MCP-Prozesse am Ordner, anonym ohne Pfade und Argumente.</summary>
    [Test]
    procedure McpStatisticsWithoutPathsWhenAnonymous;
    [Test]
    procedure McpSectionsOnlyForWorkspaceFolders;
    [Test]
    procedure McpSectionsReadStatusFiles;
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
  System.IOUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Text.LogMarks,
  Atlas.Common.Lsp.StatusFile,
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
  begin
    if mFile.Name = AName then
    begin
      Exit(mFile.Content);
    end;
  end;
  Result := '';
end;

{ TServerPackageTests }

procedure TServerPackageTests.ContainsStatusAndLogWithoutTrace;
var
  mFiles: TArray<TServerPackageFile>;
begin
  mFiles := TServerPackage.Build(Input);
  Assert.AreEqual(2, Integer(Length(mFiles)));
  Assert.AreEqual(TServerPackage.cStatusName, mFiles[0].Name);
  Assert.AreEqual(TServerPackage.cLogName, mFiles[1].Name);
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
  mTrace := FileNamed(TServerPackage.Build(mInput), TServerPackage.cTraceName);
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
  mTrace := FileNamed(TServerPackage.Build(mInput), TServerPackage.cTraceName);
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
  Assert.IsFalse(FileNamed(mFiles, TServerPackage.cStatusName).Contains('Projekte'),
    FileNamed(mFiles, TServerPackage.cStatusName));
  Assert.IsFalse(FileNamed(mFiles, TServerPackage.cStatusName).Contains('marco'),
    FileNamed(mFiles, TServerPackage.cStatusName));
  Assert.IsFalse(FileNamed(mFiles, TServerPackage.cLogName).Contains('Projekte'), FileNamed(mFiles,
    TServerPackage.cLogName));
  Assert.IsFalse(FileNamed(mFiles, TServerPackage.cLogName).Contains('"Haupt"'), FileNamed(mFiles,
    TServerPackage.cLogName));
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
  Assert.IsFalse(FileNamed(mFiles, TServerPackage.cStatusName).Contains('abc123'),
    FileNamed(mFiles, TServerPackage.cStatusName));
  Assert.IsTrue(FileNamed(mFiles, TServerPackage.cStatusName).Contains('https://example.org'),
    FileNamed(mFiles, TServerPackage.cStatusName));
  Assert.IsTrue(TServerPackage.IsSecretKey('Authorization'));
  Assert.IsFalse(TServerPackage.IsSecretKey('method'));
  // Ohne Anonymisierung bleibt der Trace lesbar, nur die Zugangsdaten werden ersetzt.
  Assert.IsFalse(FileNamed(mFiles, TServerPackage.cTraceName).Contains('s3cr3t'),
    FileNamed(mFiles, TServerPackage.cTraceName));
  Assert.IsTrue(FileNamed(mFiles, TServerPackage.cTraceName).Contains(TServerPackage.cSecretLabel),
    FileNamed(mFiles, TServerPackage.cTraceName));
  Assert.IsTrue(FileNamed(mFiles, TServerPackage.cTraceName).Contains('"method":"x"'),
    FileNamed(mFiles, TServerPackage.cTraceName));
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
    Assert.AreEqual(TServerPackage.cStatusName, (mFiles.Items[0] as TJSONObject).GetValue('name').Value);
    Assert.IsTrue((mFiles.Items[1] as TJSONObject).GetValue('content').Value.Contains('Server gestartet'));
  finally
    mJson.Free;
  end;
end;

function McpSection: string;
begin
  Result := '{"client":"Assistent A","project":"C:\\Projekte\\Kunde","calls":[{"kind":"tool",' +
    '"name":"check_code","calls":5,"errors":1,"lastFailed":{"at":"2026-11-18T12:00:00","arguments":' +
    '"file=\"' + TLogMarks.Path('C:\\Projekte\\Kunde\\Haupt.pas') + '\" text=\"' +
    TLogMarks.Text('Quelltext') + '\"","message":"' + TLogMarks.Text('Fehler in Haupt') + '"}}]}';
end;

procedure TServerPackageTests.McpStatisticsWithoutPathsWhenAnonymous;
var
  mInput: TServerPackageInput;
  mText: string;
begin
  mInput := Input;
  mInput.McpStatistics := [McpSection];
  mInput.Anonymize := True;
  mText := FileNamed(TServerPackage.Build(mInput), Format(TServerPackage.cMcpName, [1]));
  Assert.IsTrue(mText.Contains('check_code'), mText);
  Assert.IsFalse(mText.Contains('Projekte'), mText);
  Assert.IsFalse(mText.Contains('Quelltext'), mText);
  Assert.IsFalse(mText.Contains('Haupt'), mText);
  Assert.IsFalse(TLogMarks.HasMarks(mText), mText);
  mInput.Anonymize := False;
  mText := FileNamed(TServerPackage.Build(mInput), Format(TServerPackage.cMcpName, [1]));
  Assert.IsTrue(mText.Contains('Quelltext'), 'ohne Anonymisierung im Klartext');
  Assert.IsFalse(TLogMarks.HasMarks(mText), mText);
end;

procedure TServerPackageTests.McpSectionsOnlyForWorkspaceFolders;
var
  mEntries: TArray<TServerStatusEntry>;
  mSections: TArray<string>;
begin
  SetLength(mEntries, 3);
  mEntries[0] := Default(TServerStatusEntry);
  mEntries[0].Kind := TServerStatusEntry.cKindMcp;
  mEntries[0].Target := 'C:\Projekte\Kunde';
  mEntries[0].Mcp := '{"client":"A"}';
  mEntries[1] := mEntries[0];
  mEntries[1].Target := 'C:\Projekte\Anderes';
  mEntries[1].Mcp := '{"client":"B"}';
  mEntries[2] := Default(TServerStatusEntry);
  mEntries[2].Kind := TServerStatusEntry.cKindLsp;
  mEntries[2].Target := 'C:\Projekte\Kunde';
  mSections := TServerPackage.McpSections(mEntries, ['C:\Projekte\Kunde']);
  Assert.AreEqual(1, Integer(Length(mSections)));
  Assert.AreEqual('{"client":"A"}', mSections[0]);
end;

procedure TServerPackageTests.McpSectionsReadStatusFiles;
var
  mRoot: string;
  mEntry: TServerStatusEntry;
  mSections: TArray<string>;
begin
  mRoot := TPath.Combine(TPath.GetTempPath, 'Atlas-McpSections-' + IntToStr(Random(MaxInt)));
  try
    mEntry := Default(TServerStatusEntry);
    mEntry.Pid := 4711;
    mEntry.Kind := TServerStatusEntry.cKindMcp;
    mEntry.Target := 'C:\Projekte\Kunde';
    mEntry.Started := Now;
    mEntry.Mcp := '{"client":"A","calls":[]}';
    TServerStatusFile.Write(mRoot, mEntry, nil, Now);
    mSections := TServerPackage.McpSectionsIn(mRoot, ['C:\Projekte\Kunde'], Now);
    Assert.AreEqual(1, Integer(Length(mSections)));
    Assert.IsTrue(mSections[0].Contains('"client":"A"'), mSections[0]);
    Assert.AreEqual(0, Integer(Length(TServerPackage.McpSectionsIn(mRoot, ['C:\Anderes'], Now))));
  finally
    if TDirectory.Exists(mRoot) then
    begin
      TDirectory.Delete(mRoot, True);
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TServerPackageTests);

end.
