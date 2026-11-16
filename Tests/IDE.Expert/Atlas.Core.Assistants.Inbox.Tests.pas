unit Atlas.Core.Assistants.Inbox.Tests;

// Gemeinsamer Teil der Eingänge für Aufträge des MCP-Servers (TAtlasFileInbox):
// wartende Aufträge, Übernahme und Antwort.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasFileInboxTests = class
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
    procedure ClaimsARequestOnlyOnce;
    [Test]
    procedure AnswerReplacesTheResultAndRemovesTheTakenRequest;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Assistants.Inbox,
  Atlas.Tests.TempFolder;

{ TAtlasFileInboxTests }

procedure TAtlasFileInboxTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-FileInbox-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(FFolder);
end;

procedure TAtlasFileInboxTests.TearDown;
begin
  TTestTempFolder.Remove(FFolder);
end;

procedure Put(const AFolder, AName, AText: string);
begin
  TFile.WriteAllText(TPath.Combine(AFolder, AName), AText, TEncoding.UTF8);
end;

procedure TAtlasFileInboxTests.ListsOnlyWaitingRequests;
var
  mPending: TArray<string>;
begin
  Put(FFolder, 'b.json', '{}');
  Put(FFolder, 'a.json', '{}');
  Put(FFolder, 'c.json.tmp', '{}');
  Put(FFolder, 'd.taken', '{}');
  Put(FFolder, 'e.result.json', '{}');
  mPending := TAtlasFileInbox.Pending(FFolder);
  Assert.AreEqual(2, Integer(Length(mPending)));
  Assert.AreEqual('a.json', ExtractFileName(mPending[0]));
  Assert.AreEqual('b.json', ExtractFileName(mPending[1]));
  Assert.AreEqual(0, Integer(Length(TAtlasFileInbox.Pending(TPath.Combine(FFolder, 'fehlt')))));
end;

procedure TAtlasFileInboxTests.ClaimsARequestOnlyOnce;
var
  mId, mText: string;
begin
  Put(FFolder, 'r1.json', '{"x":1}');
  Assert.IsTrue(TAtlasFileInbox.Claim(TPath.Combine(FFolder, 'r1.json'), mId, mText));
  Assert.AreEqual('r1', mId);
  Assert.AreEqual('{"x":1}', mText);
  Assert.IsTrue(FileExists(TPath.Combine(FFolder, 'r1.taken')));
  Assert.IsFalse(FileExists(TPath.Combine(FFolder, 'r1.json')));
  // Schon übernommen oder vom MCP-Server zurückgezogen: kein Zuschlag, aber die Kennung.
  Assert.IsFalse(TAtlasFileInbox.Claim(TPath.Combine(FFolder, 'r1.json'), mId, mText));
  Assert.AreEqual('r1', mId);
  Assert.AreEqual('', mText);
end;

procedure TAtlasFileInboxTests.AnswerReplacesTheResultAndRemovesTheTakenRequest;
var
  mId, mText: string;
begin
  Put(FFolder, 'r2.json', '{}');
  Put(FFolder, 'r2.result.json', 'alt');
  Assert.IsTrue(TAtlasFileInbox.Claim(TPath.Combine(FFolder, 'r2.json'), mId, mText));
  TAtlasFileInbox.Answer(FFolder, mId, '{"ok":true}');
  Assert.AreEqual('{"ok":true}', TFile.ReadAllText(TPath.Combine(FFolder, 'r2.result.json'), TEncoding.UTF8));
  Assert.IsFalse(FileExists(TPath.Combine(FFolder, 'r2.taken')));
  Assert.IsFalse(FileExists(TPath.Combine(FFolder, 'r2.result.json.tmp')));
  Assert.AreEqual(0, Integer(Length(TAtlasFileInbox.Pending(FFolder))), 'Antwort ist kein Auftrag');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFileInboxTests);

end.
