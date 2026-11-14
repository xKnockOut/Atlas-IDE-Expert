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
  mRequest: TAtlasDisableWarningRequest;
begin
  Assert.IsTrue(TAtlasDisableWarningRequest.TryParse('["file:///C:/A.pas",7,"W1000","line",true]', mRequest));
  Assert.AreEqual('file:///C:/A.pas', mRequest.Uri);
  Assert.AreEqual(7, mRequest.Line);
  Assert.AreEqual('W1000', mRequest.Code);
  Assert.AreEqual('line', mRequest.Scope);
  Assert.IsTrue(mRequest.AskReason);
  Assert.IsTrue(TAtlasDisableWarningRequest.TryParse('["file:///C:/A.pas",7,"W1000","unit"]', mRequest));
  Assert.IsFalse(mRequest.AskReason);
end;

procedure TAtlasDisableWarningTests.RejectsIncompleteRequest;
var
  mRequest: TAtlasDisableWarningRequest;
begin
  Assert.IsFalse(TAtlasDisableWarningRequest.TryParse('["file:///C:/A.pas",7,"W1000"]', mRequest));
  Assert.IsFalse(TAtlasDisableWarningRequest.TryParse('["file:///C:/A.pas",-1,"W1000","line"]', mRequest));
  Assert.IsFalse(TAtlasDisableWarningRequest.TryParse('{"uri": 1}', mRequest));
  Assert.IsFalse(TAtlasDisableWarningRequest.TryParse('kaputt', mRequest));
end;

procedure TAtlasDisableWarningTests.BuildsApplyArguments;
var
  mRequest: TAtlasDisableWarningRequest;
begin
  Assert.IsTrue(TAtlasDisableWarningRequest.TryParse('["file:///C:/A.pas",7,"W1000","routine",true]', mRequest));
  Assert.AreEqual('["file:///C:/A.pas",7,"W1000","routine","Altlast"]', mRequest.ApplyArguments(' Altlast '));
  Assert.AreEqual('["file:///C:/A.pas",7,"W1000","routine",""]', mRequest.ApplyArguments(''));
end;

procedure TAtlasDisableWarningTests.ParsesProjectRequest;
var
  mRequest: TAtlasDisableWarningProject;
begin
  Assert.IsTrue(TAtlasDisableWarningProject.TryParse('["file:///C:/A.pas","W1000","symbol_deprecated"]', mRequest));
  Assert.AreEqual('W1000', mRequest.Code);
  Assert.AreEqual('DCC_SYMBOL_DEPRECATED', mRequest.OptionName);
  Assert.AreEqual('false', cAtlasWarningOptionOff);
end;

procedure TAtlasDisableWarningTests.RejectsForeignIdentifier;
var
  mRequest: TAtlasDisableWarningProject;
begin
  Assert.IsFalse(TAtlasDisableWarningProject.TryParse('["file:///C:/A.pas","W1000","A>B"]', mRequest));
  Assert.IsFalse(TAtlasDisableWarningProject.TryParse('["file:///C:/A.pas","W1000",""]', mRequest));
  Assert.IsFalse(TAtlasDisableWarningProject.TryParse('["file:///C:/A.pas","W1000"]', mRequest));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDisableWarningTests);

end.
