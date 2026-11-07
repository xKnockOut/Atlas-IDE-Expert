unit Atlas.Core.BuildPipeline.Inbox.Tests;

// Tests für den Eingang der Builds von Claude Code (#261) ohne IDE: Auftrag
// lesen und übernehmen, Antwort im Format von get_last_build schreiben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.BuildPipeline')]
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
  System.Generics.Collections,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.BuildPipeline.Inbox;

/// <summary>Gründe wie in der UI; der Test prüft, dass ParseRequest sie verwendet.</summary>
function Texts: TAtlasBuildInboxTexts;
begin
  Result := Default(TAtlasBuildInboxTexts);
  Result.Unreadable := 'unlesbar';
  Result.NoProject := 'ohne Projekt';
  Result.UnknownMode := 'Art %s unbekannt';
end;

procedure TAtlasBuildInboxTests.Setup;
begin
  FFolder := TAtlasBuildInbox.Folder(TPath.Combine(TPath.GetTempPath, 'Atlas-BuildInbox-' + IntToStr(Random(MaxInt))),
    42);
  ForceDirectories(FFolder);
end;

procedure TAtlasBuildInboxTests.TearDown;
begin
  if TDirectory.Exists(ExtractFileDir(ExtractFileDir(FFolder))) then
  begin
    TDirectory.Delete(ExtractFileDir(ExtractFileDir(FFolder)), True);
  end;
  // Der Leckmonitor misst den Saldo von Setup und TearDown.
  FFolder := '';
end;

procedure TAtlasBuildInboxTests.ReadsRequest;
var
  mRequest: TAtlasBuildRequest;
  mReason: string;
begin
  Assert.IsTrue(TAtlasBuildInbox.ParseRequest('{"project": "C:\\P\\App.dproj", "mode": "build", ' +
    '"configuration": "Release", "platform": "Win64"}', Texts, mRequest, mReason), mReason);
  Assert.AreEqual('C:\P\App.dproj', mRequest.Project);
  Assert.AreEqual(Ord(TAtlasCompileKind.Build), Ord(mRequest.Kind));
  Assert.AreEqual('Release', mRequest.Configuration);
  Assert.AreEqual('Win64', mRequest.Platform);
  // Ohne Art: make; Konfiguration und Plattform wie in der IDE.
  Assert.IsTrue(TAtlasBuildInbox.ParseRequest('{"project": "C:\\P\\App.dproj"}', Texts, mRequest, mReason), mReason);
  Assert.AreEqual(Ord(TAtlasCompileKind.Make), Ord(mRequest.Kind));
  Assert.AreEqual('', mRequest.Configuration);
  Assert.IsTrue(TAtlasBuildInbox.ParseRequest('{"project": "C:\\P\\App.dproj", "mode": "CHECK"}', Texts, mRequest,
    mReason));
  Assert.AreEqual(Ord(TAtlasCompileKind.Check), Ord(mRequest.Kind));
end;

procedure TAtlasBuildInboxTests.RejectsBrokenRequests;
var
  mRequest: TAtlasBuildRequest;
  mReason: string;
begin
  Assert.IsFalse(TAtlasBuildInbox.ParseRequest('kaputt', Texts, mRequest, mReason));
  Assert.AreEqual('unlesbar', mReason);
  Assert.IsFalse(TAtlasBuildInbox.ParseRequest('{"mode": "make"}', Texts, mRequest, mReason));
  Assert.AreEqual('ohne Projekt', mReason);
  Assert.IsFalse(TAtlasBuildInbox.ParseRequest('{"project": "C:\\P\\App.dproj", "mode": "clean"}', Texts, mRequest,
    mReason));
  Assert.AreEqual('Art clean unbekannt', mReason);
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
  mReport: TAtlasBuildReport;
  mValue: TJSONValue;
  mBuild, mFirst: TJSONObject;
  mItems: TJSONArray;
begin
  mReport := Default(TAtlasBuildReport);
  mReport.Project.FileName := 'C:\P\App.dproj';
  mReport.Project.Kind := TAtlasCompileKind.Make;
  mReport.Project.Configuration := 'Debug';
  mReport.Project.Platform := 'Win32';
  mReport.Succeeded := False;
  mReport.DurationMs := 1200;
  mReport.FinishedAt := EncodeDate(2026, 10, 16) + EncodeTime(10, 0, 0, 0);
  mReport.Messages := [Message(TAtlasCompilerSeverity.Error, 'E2003', 12),
    Message(TAtlasCompilerSeverity.Info, '', 0), Message(TAtlasCompilerSeverity.Warning, 'W1036', 20)];
  mValue := TJSONObject.ParseJSONValue(TAtlasBuildInbox.SuccessText(mReport));
  try
    Assert.IsTrue(mValue is TJSONObject);
    Assert.IsTrue((TJSONObject(mValue).GetValue('ok') as TJSONBool).AsBoolean);
    mBuild := TJSONObject(mValue).GetValue('build') as TJSONObject;
    Assert.AreEqual('C:\P\App.dproj', mBuild.GetValue('project').Value);
    Assert.AreEqual('make', mBuild.GetValue('kind').Value);
    Assert.AreEqual('Debug', mBuild.GetValue('configuration').Value);
    Assert.AreEqual('Win32', mBuild.GetValue('platform').Value);
    Assert.IsFalse((mBuild.GetValue('success') as TJSONBool).AsBoolean);
    Assert.AreEqual('1200', mBuild.GetValue('durationMs').Value);
    Assert.IsTrue(mBuild.GetValue('finishedAt').Value.StartsWith('2026-10-16T10:00:00'), mBuild.GetValue('finishedAt').Value);
    Assert.AreEqual('mcp', mBuild.GetValue('requestedBy').Value);
    // Info-Meldungen bleiben weg; Zeilen und Spalten 1-basiert wie in der IDE.
    mItems := mBuild.GetValue('messages') as TJSONArray;
    Assert.AreEqual(2, Integer(mItems.Count));
    mFirst := mItems.Items[0] as TJSONObject;
    Assert.AreEqual('C:\P\Main.pas', mFirst.GetValue('file').Value);
    Assert.AreEqual('12', mFirst.GetValue('line').Value);
    Assert.AreEqual('3', mFirst.GetValue('column').Value);
    Assert.AreEqual('error', mFirst.GetValue('severity').Value);
    Assert.AreEqual('E2003', mFirst.GetValue('code').Value);
    Assert.AreEqual('warning', (mItems.Items[1] as TJSONObject).GetValue('severity').Value);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasBuildInboxTests.WritesRefusal;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(TAtlasBuildInbox.RefusalText('In der IDE läuft der Debugger'));
  try
    Assert.IsFalse((TJSONObject(mValue).GetValue('ok') as TJSONBool).AsBoolean);
    Assert.AreEqual('In der IDE läuft der Debugger', TJSONObject(mValue).GetValue('reason').Value);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasBuildInboxTests.TakesAndAnswersOnce;
var
  mPending: TArray<string>;
  mRequest: TAtlasBuildRequest;
  mReason: string;
begin
  TFile.WriteAllText(TPath.Combine(FFolder, 'b.json'), '{"project": "C:\\P\\B.dproj"}', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'a.json'), '{"project": "C:\\P\\A.dproj"}', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'c.json.tmp'), '{}', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'd.result.json'), '{}', TEncoding.UTF8);
  mPending := TAtlasBuildInbox.Pending(FFolder);
  Assert.AreEqual(2, Integer(Length(mPending)));
  Assert.AreEqual('a.json', ExtractFileName(mPending[0]));
  Assert.IsTrue(TAtlasBuildInbox.Take(mPending[0], Texts, mRequest, mReason), mReason);
  Assert.AreEqual('a', mRequest.Id);
  Assert.AreEqual('C:\P\A.dproj', mRequest.Project);
  Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, 'a.taken')));
  // Wer das Umbenennen verliert, hat den Auftrag nicht.
  Assert.IsFalse(TAtlasBuildInbox.Take(mPending[0], Texts, mRequest, mReason));
  Assert.AreEqual('', mReason);
  TAtlasBuildInbox.Answer(FFolder, 'a', TAtlasBuildInbox.RefusalText('nein'));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, 'a.result.json')));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FFolder, 'a.taken')), 'übernommener Auftrag gelöscht');
  Assert.IsFalse(TFile.Exists(TPath.Combine(FFolder, 'a.result.json.tmp')));
end;

procedure TAtlasBuildInboxTests.AnswersUnreadableRequest;
var
  mRequest: TAtlasBuildRequest;
  mReason: string;
  mAnswer: TJSONValue;
begin
  TFile.WriteAllText(TPath.Combine(FFolder, 'x.json'), 'kaputt', TEncoding.UTF8);
  Assert.IsFalse(TAtlasBuildInbox.Take(TPath.Combine(FFolder, 'x.json'), Texts, mRequest, mReason));
  Assert.IsNotEmpty(mReason);
  mAnswer := TJSONObject.ParseJSONValue(TFile.ReadAllText(TPath.Combine(FFolder, 'x.result.json'), TEncoding.UTF8));
  try
    Assert.IsFalse((TJSONObject(mAnswer).GetValue('ok') as TJSONBool).AsBoolean);
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBuildInboxTests);

end.
