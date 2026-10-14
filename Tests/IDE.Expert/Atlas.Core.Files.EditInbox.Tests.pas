unit Atlas.Core.Files.EditInbox.Tests;

// Tests für den Eingang schreibender MCP-Werkzeuge im Plugin (#397).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasEditInboxTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ListsOnlyWaitingRequests;
    [Test]
    procedure TakesARequestOnlyOnce;
    [Test]
    procedure AnswersAndRemovesTheTakenRequest;
    [Test]
    procedure AnswersUnreadableRequests;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Files.EditInbox;

procedure TAtlasEditInboxTests.Setup;
begin
  FFolder := TAtlasEditInbox.Folder(TPath.Combine(TPath.GetTempPath, 'Atlas-EditInbox-' + IntToStr(Random(MaxInt))), 7);
  TDirectory.CreateDirectory(FFolder);
end;

procedure TAtlasEditInboxTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
end;

procedure Put(const AFolder, AName, AText: string);
begin
  TFile.WriteAllText(TPath.Combine(AFolder, AName), AText, TEncoding.UTF8);
end;

procedure TAtlasEditInboxTests.ListsOnlyWaitingRequests;
var
  Pending: TArray<string>;
begin
  Put(FFolder, 'b.json', '{}');
  Put(FFolder, 'a.json', '{}');
  Put(FFolder, 'c.json.tmp', '{}');
  Put(FFolder, 'd.taken', '{}');
  Put(FFolder, 'e.result.json', '{}');
  Pending := TAtlasEditInbox.Pending(FFolder);
  Assert.AreEqual(2, Integer(Length(Pending)));
  Assert.AreEqual('a.json', ExtractFileName(Pending[0]));
  Assert.AreEqual('b.json', ExtractFileName(Pending[1]));
  Assert.AreEqual(0, Integer(Length(TAtlasEditInbox.Pending(TPath.Combine(FFolder, 'fehlt')))));
end;

procedure TAtlasEditInboxTests.TakesARequestOnlyOnce;
var
  Request: TAtlasEditRequest;
  FileName: string;
begin
  FileName := TPath.Combine(FFolder, 'r1.json');
  Put(FFolder, 'r1.json', '{"file":"C:\\P\\A.pas","expected":"alt","text":"neu"}');
  Assert.IsTrue(TAtlasEditInbox.Take(FileName, Request));
  Assert.AreEqual('r1', Request.Id);
  Assert.AreEqual('C:\P\A.pas', Request.FileName);
  Assert.AreEqual('alt', Request.Expected);
  Assert.AreEqual('neu', Request.Text);
  Assert.IsTrue(FileExists(TPath.Combine(FFolder, 'r1.taken')));
  // Schon übernommen oder vom MCP-Server zurückgezogen.
  Assert.IsFalse(TAtlasEditInbox.Take(FileName, Request));
end;

procedure TAtlasEditInboxTests.AnswersAndRemovesTheTakenRequest;
var
  Request: TAtlasEditRequest;
  Json: TJSONValue;
begin
  Put(FFolder, 'r2.json', '{"file":"A.pas","expected":"","text":"x"}');
  Assert.IsTrue(TAtlasEditInbox.Take(TPath.Combine(FFolder, 'r2.json'), Request));
  TAtlasEditInbox.Answer(FFolder, Request, False, True, 'nicht offen');
  Assert.IsFalse(FileExists(TPath.Combine(FFolder, 'r2.taken')));
  Json := TJSONObject.ParseJSONValue(TFile.ReadAllText(TPath.Combine(FFolder, 'r2.result.json'), TEncoding.UTF8));
  try
    Assert.IsFalse(Json.GetValue<Boolean>('applied'));
    Assert.IsTrue(Json.GetValue<Boolean>('notOpen'));
    Assert.AreEqual('nicht offen', Json.GetValue<string>('reason'));
  finally
    Json.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasEditInbox.Pending(FFolder))), 'Antwort ist kein Auftrag');
end;

procedure TAtlasEditInboxTests.AnswersUnreadableRequests;
var
  Request: TAtlasEditRequest;
begin
  Put(FFolder, 'r3.json', 'kein JSON');
  Assert.IsFalse(TAtlasEditInbox.Take(TPath.Combine(FFolder, 'r3.json'), Request));
  Assert.IsTrue(FileExists(TPath.Combine(FFolder, 'r3.result.json')));
  Assert.IsFalse(FileExists(TPath.Combine(FFolder, 'r3.taken')));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditInboxTests);

end.
