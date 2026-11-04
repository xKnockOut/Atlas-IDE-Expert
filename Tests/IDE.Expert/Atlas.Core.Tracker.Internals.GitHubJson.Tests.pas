unit Atlas.Core.Tracker.Internals.GitHubJson.Tests;

// Einzelwerte aus Antworten der GitHub-API (TAtlasGitHubJson): Text, Zahl,
// Schalter und Zeit nur bei passendem Typ, Kürzen auf eine Zeile, Zuständige
// aus "assignees" bzw. "assignee".

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasGitHubJsonTests = class
  public
    [Test]
    procedure ValuesOnlyWithMatchingType;
    [Test]
    procedure ShortenToOneLine;
    [Test]
    procedure AssigneesFromListOrSingle;
    [Test]
    procedure TimeAsUtc;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.JSON,
  Atlas.Core.Tracker.Internals.GitHubJson;

function Parsed(const AJson: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
end;

procedure TAtlasGitHubJsonTests.ValuesOnlyWithMatchingType;
var
  mObject: TJSONObject;
begin
  mObject := Parsed('{"title":"Kasse","number":753,"big":3000000000,"neg":-1,"draft":true,"text":"true"}');
  try
    Assert.AreEqual('Kasse', TAtlasGitHubJson.TextOf(mObject, 'title'));
    Assert.AreEqual('', TAtlasGitHubJson.TextOf(mObject, 'draft'), 'Schalter ist kein Text');
    Assert.AreEqual(753, TAtlasGitHubJson.IntOf(mObject, 'number'));
    Assert.AreEqual(0, TAtlasGitHubJson.IntOf(mObject, 'big'), 'außerhalb von Integer');
    Assert.AreEqual(0, TAtlasGitHubJson.IntOf(mObject, 'neg'));
    Assert.AreEqual(0, TAtlasGitHubJson.IntOf(mObject, 'title'));
    Assert.IsTrue(TAtlasGitHubJson.FlagOf(mObject, 'draft'));
    Assert.IsFalse(TAtlasGitHubJson.FlagOf(mObject, 'text'), 'Text "true" ist kein Schalter');
    Assert.IsFalse(TAtlasGitHubJson.FlagOf(mObject, 'fehlt'));
  finally
    mObject.Free;
  end;
end;

procedure TAtlasGitHubJsonTests.ShortenToOneLine;
begin
  Assert.AreEqual('erste  zweite', TAtlasGitHubJson.Shorten('  erste'#13#10'zweite ', 20), 'je Umbruchzeichen ein Leerzeichen');
  Assert.AreEqual('abc…', TAtlasGitHubJson.Shorten('abcdef', 4));
  Assert.AreEqual('abcd', TAtlasGitHubJson.Shorten('abcd', 4));
end;

procedure TAtlasGitHubJsonTests.AssigneesFromListOrSingle;
var
  mObject: TJSONObject;
begin
  mObject := Parsed('{"assignees":[{"login":"anna"},{"name":"ohne"},{"login":"bert"}],"assignee":{"login":"x"}}');
  try
    Assert.AreEqual('anna, bert', TAtlasGitHubJson.AssigneesOf(mObject));
  finally
    mObject.Free;
  end;
  mObject := Parsed('{"assignees":[],"assignee":{"login":"carla"}}');
  try
    Assert.AreEqual('carla', TAtlasGitHubJson.AssigneesOf(mObject));
    Assert.AreEqual('carla', TAtlasGitHubJson.LoginOf(mObject.Values['assignee']));
    Assert.AreEqual('', TAtlasGitHubJson.LoginOf(mObject.Values['assignees']));
  finally
    mObject.Free;
  end;
end;

procedure TAtlasGitHubJsonTests.TimeAsUtc;
var
  mObject: TJSONObject;
begin
  mObject := Parsed('{"updated_at":"2026-10-28T10:40:49Z","bad":"gestern"}');
  try
    Assert.AreEqual(Double(EncodeDateTime(2026, 10, 28, 10, 40, 49, 0)),
      Double(TAtlasGitHubJson.TimeOf(mObject, 'updated_at')), 1 / SecsPerDay);
    Assert.AreEqual(Double(0), Double(TAtlasGitHubJson.TimeOf(mObject, 'bad')));
    Assert.AreEqual(Double(0), Double(TAtlasGitHubJson.TimeOf(mObject, 'fehlt')));
  finally
    mObject.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGitHubJsonTests);

end.
