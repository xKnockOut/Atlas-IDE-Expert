unit Atlas.Common.Mcp.IdeEdits.Tests;

// Tests für MCP-Änderungen über den Eingang des IDE-Plugins (#397). Die
// Rolle des Plugins spielt der Warte-Rückruf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpIdeEditsTests = class
  private
    FInbox: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure WritesItselfWhenNobodyTakesTheRequest;
    [Test]
    procedure ReportsAppliedChange;
    [Test]
    procedure WritesItselfWhenTheFileIsNoLongerOpen;
    [Test]
    procedure FailsWhenTakenButNeverAnswered;
  end;

implementation

uses
  Winapi.Windows,
  System.Generics.Collections,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Mcp.IdeEdits;

var
  Now_: Int64;

function Clock: Int64;
begin
  Result := Now_;
end;

/// <summary>Wie das Plugin: Auftrag übernehmen, lesen und mit AAnswer beantworten.</summary>
function Plugin(const AInbox, AAnswer: string; out ARequest: string): Boolean;
var
  Request: string;
begin
  Result := False;
  for Request in TDirectory.GetFiles(AInbox, '*.json') do
    if not Request.EndsWith('.result.json') then
    begin
      RenameFile(Request, ChangeFileExt(Request, '.taken'));
      ARequest := TFile.ReadAllText(ChangeFileExt(Request, '.taken'), TEncoding.UTF8);
      if AAnswer <> '' then
        TFile.WriteAllText(ChangeFileExt(Request, '') + '.result.json', AAnswer, TEncoding.UTF8);
      Exit(True);
    end;
end;

procedure TMcpIdeEditsTests.Setup;
begin
  FInbox := TMcpIdeEdits.InboxOf(TPath.Combine(TPath.GetTempPath, 'Atlas-IdeEdits-' + IntToStr(Random(MaxInt))), 42);
  Now_ := 0;
end;

procedure TMcpIdeEditsTests.TearDown;
begin
  if TDirectory.Exists(FInbox) then
    TDirectory.Delete(FInbox, True);
  FInbox := '';
end;

procedure TMcpIdeEditsTests.WritesItselfWhenNobodyTakesTheRequest;
var
  Reason: string;
begin
  Assert.IsTrue(TMcpIdeEdits.Send(FInbox, 'C:\P\A.pas', 'alt', 'neu',
    procedure
    begin
      Inc(Now_, 100);
    end, Clock, Reason) = TMcpIdeEditOutcome.WriteYourself);
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(FInbox))), 'Auftrag zurückgezogen');
end;

procedure TMcpIdeEditsTests.ReportsAppliedChange;
var
  Reason, Seen: string;
  Json: TJSONValue;
begin
  Assert.IsTrue(TMcpIdeEdits.Send(FInbox, 'C:\P\A.pas', 'alt', 'neu',
    procedure
    begin
      Inc(Now_, 100);
      Plugin(FInbox, '{"applied":true}', Seen);
    end, Clock, Reason) = TMcpIdeEditOutcome.Applied);
  Json := TJSONObject.ParseJSONValue(Seen);
  try
    Assert.AreEqual('C:\P\A.pas', Json.GetValue<string>('file'));
    Assert.AreEqual('alt', Json.GetValue<string>('expected'));
    Assert.AreEqual('neu', Json.GetValue<string>('text'));
  finally
    Json.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(FInbox, '*.result.json'))), 'Antwort gelesen und gelöscht');
end;

procedure TMcpIdeEditsTests.WritesItselfWhenTheFileIsNoLongerOpen;
var
  Reason, Seen: string;
begin
  Assert.IsTrue(TMcpIdeEdits.Send(FInbox, 'C:\P\A.pas', 'alt', 'neu',
    procedure
    begin
      Inc(Now_, 100);
      Plugin(FInbox, '{"applied":false,"notOpen":true,"reason":"nicht offen"}', Seen);
    end, Clock, Reason) = TMcpIdeEditOutcome.WriteYourself);
  Assert.IsTrue(TMcpIdeEdits.Send(FInbox, 'C:\P\A.pas', 'alt', 'neu',
    procedure
    begin
      Inc(Now_, 100);
      Plugin(FInbox, '{"applied":false,"reason":"gesperrt"}', Seen);
    end, Clock, Reason) = TMcpIdeEditOutcome.Failed);
  Assert.AreEqual('gesperrt', Reason);
end;

procedure TMcpIdeEditsTests.FailsWhenTakenButNeverAnswered;
var
  Reason, Seen: string;
begin
  Assert.IsTrue(TMcpIdeEdits.Send(FInbox, 'C:\P\A.pas', 'alt', 'neu',
    procedure
    begin
      Inc(Now_, 1000);
      Plugin(FInbox, '', Seen);
    end, Clock, Reason) = TMcpIdeEditOutcome.Failed);
  Assert.IsNotEmpty(Reason);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpIdeEditsTests);

end.
