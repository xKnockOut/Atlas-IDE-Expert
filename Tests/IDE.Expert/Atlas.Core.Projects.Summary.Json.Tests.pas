unit Atlas.Core.Projects.Summary.Json.Tests;

// Abschnitt der Projekt-Zusammenfassung ersetzen (ReplaceSection): übrige
// Felder bleiben in ihrer Reihenfolge, nil entfernt den Abschnitt, ungültiger
// Text gilt als leeres Objekt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSummaryJsonTests = class
  public
    [Test]
    procedure ReplacesTheSectionAndKeepsTheRest;
    [Test]
    procedure AddsAMissingSection;
    [Test]
    procedure NilRemovesTheSection;
    [Test]
    procedure InvalidTextCountsAsEmpty;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Projects.Summary.Json;

{ TAtlasSummaryJsonTests }

function Section(const AName: string; AValue: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair(AName, TJSONNumber.Create(AValue));
end;

procedure TAtlasSummaryJsonTests.ReplacesTheSectionAndKeepsTheRest;
begin
  Assert.AreEqual('{"format":1,"other":{"a":1},"z":"x","continue":{"n":2}}',
    ReplaceSection('{"format":1,"continue":{"n":1},"other":{"a":1},"z":"x"}', 'continue', Section('n', 2)));
end;

procedure TAtlasSummaryJsonTests.AddsAMissingSection;
begin
  Assert.AreEqual('{"format":1,"issues":{"n":3}}', ReplaceSection('{"format":1}', 'issues', Section('n', 3)));
end;

procedure TAtlasSummaryJsonTests.NilRemovesTheSection;
begin
  Assert.AreEqual('{"format":1,"continue":{"n":1}}',
    ReplaceSection('{"format":1,"issueWork":[1],"continue":{"n":1}}', 'issueWork', nil));
end;

procedure TAtlasSummaryJsonTests.InvalidTextCountsAsEmpty;
begin
  Assert.AreEqual('{"unsaved":{"n":4}}', ReplaceSection('kein JSON', 'unsaved', Section('n', 4)));
  Assert.AreEqual('{"unsaved":{"n":5}}', ReplaceSection('', 'unsaved', Section('n', 5)));
  Assert.AreEqual('{}', ReplaceSection('[1,2]', 'unsaved', nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSummaryJsonTests);

end.
