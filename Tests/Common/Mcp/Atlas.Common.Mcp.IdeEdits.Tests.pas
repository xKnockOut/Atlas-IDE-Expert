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
    /// <summary>Nicht zu eng (Last), nicht zu weit (Antwortzeit).</summary>
    [Test]
    procedure PollIntervalStaysWithinBounds;
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
  mRequest: string;
begin
  Result := False;
  for mRequest in TDirectory.GetFiles(AInbox, '*.json') do
  begin
    if not mRequest.EndsWith('.result.json') then
    begin
      RenameFile(mRequest, ChangeFileExt(mRequest, '.taken'));
      ARequest := TFile.ReadAllText(ChangeFileExt(mRequest, '.taken'), TEncoding.UTF8);
      if AAnswer <> '' then
      begin
        TFile.WriteAllText(ChangeFileExt(mRequest, '') + '.result.json', AAnswer, TEncoding.UTF8);
      end;
      Exit(True);
    end;
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
  begin
    TDirectory.Delete(FInbox, True);
  end;
  FInbox := '';
end;

procedure TMcpIdeEditsTests.WritesItselfWhenNobodyTakesTheRequest;
var
  mReason: string;
begin
  Assert.AreEqual<TMcpIdeEditOutcome>(TMcpIdeEditOutcome.WriteYourself,
    TMcpIdeEdits.Send(FInbox, TMcpIdeEdit.Make('C:\P\A.pas', 'alt', 'neu'),
    procedure
    begin
      Inc(Now_, 100);
    end, Clock, mReason));
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(FInbox))), 'Auftrag zurückgezogen');
end;

procedure TMcpIdeEditsTests.ReportsAppliedChange;
var
  mReason, mSeen: string;
  mJson: TJSONValue;
begin
  Assert.AreEqual<TMcpIdeEditOutcome>(TMcpIdeEditOutcome.Applied,
    TMcpIdeEdits.Send(FInbox, TMcpIdeEdit.Make('C:\P\A.pas', 'alt', 'neu'),
    procedure
    begin
      Inc(Now_, 100);
      Plugin(FInbox, '{"applied":true}', mSeen);
    end, Clock, mReason));
  mJson := TJSONObject.ParseJSONValue(mSeen);
  try
    Assert.AreEqual('C:\P\A.pas', mJson.GetValue<string>('file'));
    Assert.AreEqual('alt', mJson.GetValue<string>('expected'));
    Assert.AreEqual('neu', mJson.GetValue<string>('text'));
  finally
    mJson.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(FInbox, '*.result.json'))), 'Antwort gelesen und gelöscht');
end;

procedure TMcpIdeEditsTests.WritesItselfWhenTheFileIsNoLongerOpen;
var
  mReason, mSeen: string;
begin
  Assert.AreEqual<TMcpIdeEditOutcome>(TMcpIdeEditOutcome.WriteYourself,
    TMcpIdeEdits.Send(FInbox, TMcpIdeEdit.Make('C:\P\A.pas', 'alt', 'neu'),
    procedure
    begin
      Inc(Now_, 100);
      Plugin(FInbox, '{"applied":false,"notOpen":true,"reason":"nicht offen"}', mSeen);
    end, Clock, mReason));
  Assert.AreEqual<TMcpIdeEditOutcome>(TMcpIdeEditOutcome.Failed,
    TMcpIdeEdits.Send(FInbox, TMcpIdeEdit.Make('C:\P\A.pas', 'alt', 'neu'),
    procedure
    begin
      Inc(Now_, 100);
      Plugin(FInbox, '{"applied":false,"reason":"gesperrt"}', mSeen);
    end, Clock, mReason));
  Assert.AreEqual('gesperrt', mReason);
end;

procedure TMcpIdeEditsTests.FailsWhenTakenButNeverAnswered;
var
  mReason, mSeen: string;
begin
  Assert.AreEqual<TMcpIdeEditOutcome>(TMcpIdeEditOutcome.Failed,
    TMcpIdeEdits.Send(FInbox, TMcpIdeEdit.Make('C:\P\A.pas', 'alt', 'neu'),
    procedure
    begin
      Inc(Now_, 1000);
      Plugin(FInbox, '', mSeen);
    end, Clock, mReason));
  Assert.IsNotEmpty(mReason);
end;

procedure TMcpIdeEditsTests.PollIntervalStaysWithinBounds;
var
  mMs: Integer;
begin
  // Über eine Variable: Ein Vergleich zweier Konstanten wäre ein konstanter Ausdruck.
  mMs := TMcpIdeEdits.cPollMs;
  Assert.IsTrue(mMs >= 50, IntToStr(mMs));
  Assert.IsTrue(mMs <= 100, IntToStr(mMs));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpIdeEditsTests);

end.
