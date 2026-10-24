unit Atlas.Core.Editor.DisableWarning.Tests;

// Tests für die Argumente der Client-Befehle „Warnung abschalten“ (#531).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDisableWarningTests = class
  public
    [Test]
    procedure ParsesRequest;
    [Test]
    procedure RejectsIncompleteRequest;
    [Test]
    procedure BuildsApplyArguments;
    [Test]
    procedure ParsesProjectRequest;
    /// <summary>Der Bezeichner wird Teil einer Projektoption: nur A–Z, 0–9 und _.</summary>
    [Test]
    procedure RejectsForeignIdentifier;
  end;

implementation

uses
  Atlas.Core.Editor.DisableWarning;

procedure TAtlasDisableWarningTests.ParsesRequest;
var
  Request: TAtlasDisableWarningRequest;
begin
  Assert.IsTrue(TAtlasDisableWarningRequest.TryParse('["file:///C:/A.pas",7,"W1000","line",true]', Request));
  Assert.AreEqual('file:///C:/A.pas', Request.Uri);
  Assert.AreEqual(7, Request.Line);
  Assert.AreEqual('W1000', Request.Code);
  Assert.AreEqual('line', Request.Scope);
  Assert.IsTrue(Request.AskReason);
  Assert.IsTrue(TAtlasDisableWarningRequest.TryParse('["file:///C:/A.pas",7,"W1000","unit"]', Request));
  Assert.IsFalse(Request.AskReason);
end;

procedure TAtlasDisableWarningTests.RejectsIncompleteRequest;
var
  Request: TAtlasDisableWarningRequest;
begin
  Assert.IsFalse(TAtlasDisableWarningRequest.TryParse('["file:///C:/A.pas",7,"W1000"]', Request));
  Assert.IsFalse(TAtlasDisableWarningRequest.TryParse('["file:///C:/A.pas",-1,"W1000","line"]', Request));
  Assert.IsFalse(TAtlasDisableWarningRequest.TryParse('{"uri": 1}', Request));
  Assert.IsFalse(TAtlasDisableWarningRequest.TryParse('kaputt', Request));
end;

procedure TAtlasDisableWarningTests.BuildsApplyArguments;
var
  Request: TAtlasDisableWarningRequest;
begin
  Assert.IsTrue(TAtlasDisableWarningRequest.TryParse('["file:///C:/A.pas",7,"W1000","routine",true]', Request));
  Assert.AreEqual('["file:///C:/A.pas",7,"W1000","routine","Altlast"]', Request.ApplyArguments(' Altlast '));
  Assert.AreEqual('["file:///C:/A.pas",7,"W1000","routine",""]', Request.ApplyArguments(''));
end;

procedure TAtlasDisableWarningTests.ParsesProjectRequest;
var
  Request: TAtlasDisableWarningProject;
begin
  Assert.IsTrue(TAtlasDisableWarningProject.TryParse('["file:///C:/A.pas","W1000","symbol_deprecated"]', Request));
  Assert.AreEqual('W1000', Request.Code);
  Assert.AreEqual('DCC_SYMBOL_DEPRECATED', Request.OptionName);
  Assert.AreEqual('false', AtlasWarningOptionOff);
end;

procedure TAtlasDisableWarningTests.RejectsForeignIdentifier;
var
  Request: TAtlasDisableWarningProject;
begin
  Assert.IsFalse(TAtlasDisableWarningProject.TryParse('["file:///C:/A.pas","W1000","A>B"]', Request));
  Assert.IsFalse(TAtlasDisableWarningProject.TryParse('["file:///C:/A.pas","W1000",""]', Request));
  Assert.IsFalse(TAtlasDisableWarningProject.TryParse('["file:///C:/A.pas","W1000"]', Request));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDisableWarningTests);

end.
