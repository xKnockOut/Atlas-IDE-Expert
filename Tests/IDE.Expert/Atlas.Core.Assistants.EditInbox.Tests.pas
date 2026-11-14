unit Atlas.Core.Assistants.EditInbox.Tests;

// Tests für den Eingang schreibender MCP-Werkzeuge im Plugin (#397).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
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
  System.Generics.Collections,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Assistants.EditInbox;

procedure TAtlasEditInboxTests.Setup;
begin
  FFolder := TAtlasEditInbox.Folder(TPath.Combine(TPath.GetTempPath, 'Atlas-EditInbox-' + IntToStr(Random(MaxInt))), 7);
  TDirectory.CreateDirectory(FFolder);
end;

procedure TAtlasEditInboxTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure Put(const AFolder, AName, AText: string);
begin
  TFile.WriteAllText(TPath.Combine(AFolder, AName), AText, TEncoding.UTF8);
end;

procedure TAtlasEditInboxTests.ListsOnlyWaitingRequests;
var
  mPending: TArray<string>;
begin
  Put(FFolder, 'b.json', '{}');
  Put(FFolder, 'a.json', '{}');
  Put(FFolder, 'c.json.tmp', '{}');
  Put(FFolder, 'd.taken', '{}');
  Put(FFolder, 'e.result.json', '{}');
  mPending := TAtlasEditInbox.Pending(FFolder);
  Assert.AreEqual(2, Integer(Length(mPending)));
  Assert.AreEqual('a.json', ExtractFileName(mPending[0]));
  Assert.AreEqual('b.json', ExtractFileName(mPending[1]));
  Assert.AreEqual(0, Integer(Length(TAtlasEditInbox.Pending(TPath.Combine(FFolder, 'fehlt')))));
end;

procedure TAtlasEditInboxTests.TakesARequestOnlyOnce;
var
  mRequest: TAtlasEditRequest;
  mFileName: string;
begin
  mFileName := TPath.Combine(FFolder, 'r1.json');
  Put(FFolder, 'r1.json', '{"file":"C:\\P\\A.pas","expected":"alt","text":"neu"}');
  Assert.IsTrue(TAtlasEditInbox.Take(mFileName, mRequest));
  Assert.AreEqual('r1', mRequest.Id);
  Assert.AreEqual('C:\P\A.pas', mRequest.FileName);
  Assert.AreEqual('alt', mRequest.Expected);
  Assert.AreEqual('neu', mRequest.Text);
  Assert.IsTrue(FileExists(TPath.Combine(FFolder, 'r1.taken')));
  // Schon übernommen oder vom MCP-Server zurückgezogen.
  Assert.IsFalse(TAtlasEditInbox.Take(mFileName, mRequest));
end;

procedure TAtlasEditInboxTests.AnswersAndRemovesTheTakenRequest;
var
  mRequest: TAtlasEditRequest;
  mJson: TJSONValue;
begin
  Put(FFolder, 'r2.json', '{"file":"A.pas","expected":"","text":"x"}');
  Assert.IsTrue(TAtlasEditInbox.Take(TPath.Combine(FFolder, 'r2.json'), mRequest));
  TAtlasEditInbox.Answer(FFolder, mRequest, False, True, 'nicht offen');
  Assert.IsFalse(FileExists(TPath.Combine(FFolder, 'r2.taken')));
  mJson := TJSONObject.ParseJSONValue(TFile.ReadAllText(TPath.Combine(FFolder, 'r2.result.json'), TEncoding.UTF8));
  try
    Assert.IsFalse(mJson.GetValue<Boolean>('applied'));
    Assert.IsTrue(mJson.GetValue<Boolean>('notOpen'));
    Assert.AreEqual('nicht offen', mJson.GetValue<string>('reason'));
  finally
    mJson.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasEditInbox.Pending(FFolder))), 'Antwort ist kein Auftrag');
end;

procedure TAtlasEditInboxTests.AnswersUnreadableRequests;
var
  mRequest: TAtlasEditRequest;
begin
  Put(FFolder, 'r3.json', 'kein JSON');
  Assert.IsFalse(TAtlasEditInbox.Take(TPath.Combine(FFolder, 'r3.json'), mRequest));
  Assert.IsTrue(FileExists(TPath.Combine(FFolder, 'r3.result.json')));
  Assert.IsFalse(FileExists(TPath.Combine(FFolder, 'r3.taken')));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditInboxTests);

end.
