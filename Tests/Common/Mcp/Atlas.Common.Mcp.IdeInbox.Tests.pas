unit Atlas.Common.Mcp.IdeInbox.Tests;

// Tests für den Austausch des MCP-Servers mit dem IDE-Plugin über einen Auftragsordner (#261, #1874). Die Rolle des
// Plugins spielt der Warte-Rückruf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpIdeInboxTests = class
  private
    FInbox: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReturnsAnswerAndDeletesIt;
    [Test]
    procedure WithdrawsWhenNobodyTakesTheRequest;
    [Test]
    procedure TimesOutWhenTakenButNeverAnswered;
  end;

/// <summary>Auftragsordner AFolder eines Tests samt Inhalt löschen und den Namen leeren (TearDown der Ide-Tests).</summary>
procedure RemoveTestInbox(var AFolder: string);

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Mcp.IdeInbox;

var
  GNow: Int64;

function Clock: Int64;
begin
  Result := GNow;
end;

/// <summary>Wie das Plugin: ersten Auftrag übernehmen (umbenennen), lesen und mit AAnswer beantworten ('' = nicht).
/// </summary>
function Plugin(const AInbox, AAnswer: string; out ARequest: string): Boolean;
var
  mRequest, mTaken: string;
begin
  Result := False;
  if not TDirectory.Exists(AInbox) then
  begin
    Exit;
  end;
  for mRequest in TDirectory.GetFiles(AInbox, '*.json') do
  begin
    if not mRequest.EndsWith('.result.json') then
    begin
      mTaken := ChangeFileExt(mRequest, '.taken');
      TFile.Move(mRequest, mTaken);
      ARequest := TFile.ReadAllText(mTaken, TEncoding.UTF8);
      if AAnswer <> '' then
      begin
        TFile.WriteAllText(ChangeFileExt(mRequest, '') + '.result.json', AAnswer, TEncoding.UTF8);
      end;
      Exit(True);
    end;
  end;
end;

procedure RemoveTestInbox(var AFolder: string);
begin
  if TDirectory.Exists(AFolder) then
  begin
    TDirectory.Delete(AFolder, True);
  end;
  AFolder := '';
end;

{ TMcpIdeInboxTests }

procedure TMcpIdeInboxTests.Setup;
begin
  FInbox := TPath.Combine(TPath.GetTempPath, 'Atlas-IdeInbox-' + IntToStr(Random(MaxInt)));
  GNow := 0;
end;

procedure TMcpIdeInboxTests.TearDown;
begin
  RemoveTestInbox(FInbox);
end;

procedure TMcpIdeInboxTests.ReturnsAnswerAndDeletesIt;
var
  mAnswer, mSeen: string;
  mInbox: string;
begin
  mInbox := FInbox;
  Assert.AreEqual(Ord(TMcpIdeExchangeOutcome.Answered), Ord(TMcpIdeInbox.Exchange(mInbox, '{"a":1}',
    TMcpIdeWaiting.Make(
    procedure
    begin
      Inc(GNow, 100);
      Plugin(mInbox, '{"ok":true}', mSeen);
    end, Clock, 5000, 5000), mAnswer)));
  Assert.AreEqual('{"ok":true}', mAnswer);
  Assert.AreEqual('{"a":1}', mSeen, 'Auftrag unverändert beim Plugin');
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(mInbox, '*.result.json'))), 'Antwort gelesen und gelöscht');
end;

procedure TMcpIdeInboxTests.WithdrawsWhenNobodyTakesTheRequest;
var
  mAnswer: string;
begin
  Assert.AreEqual(Ord(TMcpIdeExchangeOutcome.NotTaken), Ord(TMcpIdeInbox.Exchange(FInbox, '{}',
    TMcpIdeWaiting.Make(
    procedure
    begin
      Inc(GNow, 100);
    end, Clock, 5000, 5000), mAnswer)));
  Assert.AreEqual('', mAnswer);
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(FInbox))), 'Auftrag zurückgezogen');
end;

procedure TMcpIdeInboxTests.TimesOutWhenTakenButNeverAnswered;
var
  mAnswer, mSeen: string;
  mInbox: string;
begin
  mInbox := FInbox;
  Assert.AreEqual(Ord(TMcpIdeExchangeOutcome.TimedOut), Ord(TMcpIdeInbox.Exchange(mInbox, '{}',
    TMcpIdeWaiting.Make(
    procedure
    begin
      Inc(GNow, 1000);
      Plugin(mInbox, '', mSeen);
    end, Clock, 5000, 3000), mAnswer)));
  Assert.AreEqual('', mAnswer);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpIdeInboxTests);

end.
