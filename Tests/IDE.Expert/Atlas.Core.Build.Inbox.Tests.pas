unit Atlas.Core.Build.Inbox.Tests;

// Tests für den Eingang der Builds von Claude Code (#261) ohne IDE: Auftrag
// lesen und übernehmen, Antwort im Format von get_last_build schreiben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBuildInboxTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsRequest;
    [Test]
    procedure RejectsBrokenRequests;
    [Test]
    procedure WritesBuildLikeTheServer;
    [Test]
    procedure WritesRefusal;
    [Test]
    procedure TakesAndAnswersOnce;
    [Test]
    procedure AnswersUnreadableRequest;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Inbox;

procedure TAtlasBuildInboxTests.Setup;
begin
  FFolder := TAtlasBuildInbox.Folder(TPath.Combine(TPath.GetTempPath, 'Atlas-BuildInbox-' + IntToStr(Random(MaxInt))),
    42);
  ForceDirectories(FFolder);
end;

procedure TAtlasBuildInboxTests.TearDown;
begin
  if TDirectory.Exists(ExtractFileDir(ExtractFileDir(FFolder))) then
    TDirectory.Delete(ExtractFileDir(ExtractFileDir(FFolder)), True);
end;

procedure TAtlasBuildInboxTests.ReadsRequest;
var
  Request: TAtlasBuildRequest;
  Reason: string;
begin
  Assert.IsTrue(TAtlasBuildInbox.ParseRequest('{"project": "C:\\P\\App.dproj", "mode": "build", ' +
    '"configuration": "Release", "platform": "Win64"}', Request, Reason), Reason);
  Assert.AreEqual('C:\P\App.dproj', Request.Project);
  Assert.AreEqual(Ord(TAtlasCompileKind.Build), Ord(Request.Kind));
  Assert.AreEqual('Release', Request.Configuration);
  Assert.AreEqual('Win64', Request.Platform);
  // Ohne Art: make; Konfiguration und Plattform wie in der IDE.
  Assert.IsTrue(TAtlasBuildInbox.ParseRequest('{"project": "C:\\P\\App.dproj"}', Request, Reason), Reason);
  Assert.AreEqual(Ord(TAtlasCompileKind.Make), Ord(Request.Kind));
  Assert.AreEqual('', Request.Configuration);
  Assert.IsTrue(TAtlasBuildInbox.ParseRequest('{"project": "C:\\P\\App.dproj", "mode": "CHECK"}', Request, Reason));
  Assert.AreEqual(Ord(TAtlasCompileKind.Check), Ord(Request.Kind));
end;

procedure TAtlasBuildInboxTests.RejectsBrokenRequests;
var
  Request: TAtlasBuildRequest;
  Reason: string;
begin
  Assert.IsFalse(TAtlasBuildInbox.ParseRequest('kaputt', Request, Reason));
  Assert.IsNotEmpty(Reason);
  Assert.IsFalse(TAtlasBuildInbox.ParseRequest('{"mode": "make"}', Request, Reason));
  Assert.IsTrue(Pos('Projekt', Reason) > 0, Reason);
  Assert.IsFalse(TAtlasBuildInbox.ParseRequest('{"project": "C:\\P\\App.dproj", "mode": "clean"}', Request, Reason));
  Assert.IsTrue(Pos('clean', Reason) > 0, Reason);
end;

function Message(ASeverity: TAtlasCompilerSeverity; const ACode: string; ALine: Integer): TAtlasCompilerMessage;
begin
  Result := Default(TAtlasCompilerMessage);
  Result.FileName := 'C:\P\Main.pas';
  Result.Line := ALine;
  Result.Column := 3;
  Result.Severity := ASeverity;
  Result.Code := ACode;
  Result.Text := 'Text ' + ACode;
end;

procedure TAtlasBuildInboxTests.WritesBuildLikeTheServer;
var
  Report: TAtlasBuildReport;
  Value: TJSONValue;
  Build, First: TJSONObject;
  Items: TJSONArray;
begin
  Report := Default(TAtlasBuildReport);
  Report.Project.FileName := 'C:\P\App.dproj';
  Report.Project.Kind := TAtlasCompileKind.Make;
  Report.Project.Configuration := 'Debug';
  Report.Project.Platform := 'Win32';
  Report.Succeeded := False;
  Report.DurationMs := 1200;
  Report.FinishedAt := EncodeDate(2026, 10, 16) + EncodeTime(10, 0, 0, 0);
  Report.Messages := [Message(TAtlasCompilerSeverity.Error, 'E2003', 12),
    Message(TAtlasCompilerSeverity.Info, '', 0), Message(TAtlasCompilerSeverity.Warning, 'W1036', 20)];
  Value := TJSONObject.ParseJSONValue(TAtlasBuildInbox.SuccessText(Report));
  try
    Assert.IsTrue(Value is TJSONObject);
    Assert.IsTrue((TJSONObject(Value).GetValue('ok') as TJSONBool).AsBoolean);
    Build := TJSONObject(Value).GetValue('build') as TJSONObject;
    Assert.AreEqual('C:\P\App.dproj', Build.GetValue('project').Value);
    Assert.AreEqual('make', Build.GetValue('kind').Value);
    Assert.AreEqual('Debug', Build.GetValue('configuration').Value);
    Assert.AreEqual('Win32', Build.GetValue('platform').Value);
    Assert.IsFalse((Build.GetValue('success') as TJSONBool).AsBoolean);
    Assert.AreEqual('1200', Build.GetValue('durationMs').Value);
    Assert.IsTrue(Build.GetValue('finishedAt').Value.StartsWith('2026-10-16T10:00:00'), Build.GetValue('finishedAt').Value);
    Assert.AreEqual('mcp', Build.GetValue('requestedBy').Value);
    // Info-Meldungen bleiben weg; Zeilen und Spalten 1-basiert wie in der IDE.
    Items := Build.GetValue('messages') as TJSONArray;
    Assert.AreEqual(2, Items.Count);
    First := Items.Items[0] as TJSONObject;
    Assert.AreEqual('C:\P\Main.pas', First.GetValue('file').Value);
    Assert.AreEqual('12', First.GetValue('line').Value);
    Assert.AreEqual('3', First.GetValue('column').Value);
    Assert.AreEqual('error', First.GetValue('severity').Value);
    Assert.AreEqual('E2003', First.GetValue('code').Value);
    Assert.AreEqual('warning', (Items.Items[1] as TJSONObject).GetValue('severity').Value);
  finally
    Value.Free;
  end;
end;

procedure TAtlasBuildInboxTests.WritesRefusal;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(TAtlasBuildInbox.RefusalText('In der IDE läuft der Debugger'));
  try
    Assert.IsFalse((TJSONObject(Value).GetValue('ok') as TJSONBool).AsBoolean);
    Assert.AreEqual('In der IDE läuft der Debugger', TJSONObject(Value).GetValue('reason').Value);
  finally
    Value.Free;
  end;
end;

procedure TAtlasBuildInboxTests.TakesAndAnswersOnce;
var
  Pending: TArray<string>;
  Request: TAtlasBuildRequest;
  Reason: string;
begin
  TFile.WriteAllText(TPath.Combine(FFolder, 'b.json'), '{"project": "C:\\P\\B.dproj"}', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'a.json'), '{"project": "C:\\P\\A.dproj"}', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'c.json.tmp'), '{}', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'd.result.json'), '{}', TEncoding.UTF8);
  Pending := TAtlasBuildInbox.Pending(FFolder);
  Assert.AreEqual(2, Integer(Length(Pending)));
  Assert.AreEqual('a.json', ExtractFileName(Pending[0]));
  Assert.IsTrue(TAtlasBuildInbox.Take(Pending[0], Request, Reason), Reason);
  Assert.AreEqual('a', Request.Id);
  Assert.AreEqual('C:\P\A.dproj', Request.Project);
  Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, 'a.taken')));
  // Wer das Umbenennen verliert, hat den Auftrag nicht.
  Assert.IsFalse(TAtlasBuildInbox.Take(Pending[0], Request, Reason));
  Assert.AreEqual('', Reason);
  TAtlasBuildInbox.Answer(FFolder, 'a', TAtlasBuildInbox.RefusalText('nein'));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, 'a.result.json')));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FFolder, 'a.taken')), 'übernommener Auftrag gelöscht');
  Assert.IsFalse(TFile.Exists(TPath.Combine(FFolder, 'a.result.json.tmp')));
end;

procedure TAtlasBuildInboxTests.AnswersUnreadableRequest;
var
  Request: TAtlasBuildRequest;
  Reason: string;
  Answer: TJSONValue;
begin
  TFile.WriteAllText(TPath.Combine(FFolder, 'x.json'), 'kaputt', TEncoding.UTF8);
  Assert.IsFalse(TAtlasBuildInbox.Take(TPath.Combine(FFolder, 'x.json'), Request, Reason));
  Assert.IsNotEmpty(Reason);
  Answer := TJSONObject.ParseJSONValue(TFile.ReadAllText(TPath.Combine(FFolder, 'x.result.json'), TEncoding.UTF8));
  try
    Assert.IsFalse((TJSONObject(Answer).GetValue('ok') as TJSONBool).AsBoolean);
  finally
    Answer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBuildInboxTests);

end.
