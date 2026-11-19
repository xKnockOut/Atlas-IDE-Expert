unit Atlas.Common.Mcp.DocsTools.Tests;

// Tests für das MCP-Werkzeug search_atlas_docs (#2376) mit dem eingebetteten Index: Parameter, genaue Kennung mit
// ganzem Abschnitt, Schweregrad einer Regel mit Herkunft, Wert einer Einstellung mit Herkunft (Projekt, global,
// Vorgabe), Plugin-Einstellungen, Tastenkürzel, beide Sprachen, ohne Treffer ähnliche Kennungen, JSON.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Localization.Texts;

type
  [TestFixture]
  TMcpDocsToolsTests = class
  private
    FLanguage: TTextLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsArguments;
    [Test]
    procedure RejectsBadArguments;
    [Test]
    procedure ExactRuleWithWholeSection;
    [Test]
    procedure RuleSeverityFromProject;
    [Test]
    procedure SettingValueWithOrigin;
    [Test]
    procedure PluginSettingAndShortCut;
    [Test]
    procedure QuestionFindsSetting;
    [Test]
    procedure AnswersInEnglish;
    [Test]
    procedure NoHitsNamesSimilarIds;
    [Test]
    procedure JsonHasTheSameFields;
  end;

implementation

uses
  System.SysUtils,
  // Inline-Funktionen von TJSONArray und TJSONObject (H2443).
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.DocsIndex,
  Atlas.Common.Mcp.DocsTools;

function RequestFor(const AJson: string): TMcpDocsRequest;
var
  mArguments: TJSONObject;
begin
  mArguments := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  try
    Result := TMcpDocsTools.RequestOf(mArguments);
  finally
    mArguments.Free;
  end;
end;

function SearchFor(const AJson: string): string;
begin
  Result := TMcpDocsTools.Search(RequestFor(AJson));
end;

function RuleSetting(const AId: string; ASeverity: TRuleSeverity): TRuleSetting;
begin
  Result := Default(TRuleSetting);
  Result.Id := AId;
  Result.Severity := ASeverity;
end;

{ TMcpDocsToolsTests }

procedure TMcpDocsToolsTests.Setup;
begin
  FLanguage := TAtlasLocale.Language;
  TAtlasLocale.Use(TTextLanguage.English);
end;

procedure TMcpDocsToolsTests.TearDown;
begin
  TAtlasLocale.Use(FLanguage);
end;

procedure TMcpDocsToolsTests.ReadsArguments;
var
  mRequest: TMcpDocsRequest;
begin
  mRequest := RequestFor('{"query":" Brotkrumen ","kind":"setting","language":"en","limit":50,"format":"json"}');
  Assert.AreEqual('Brotkrumen', mRequest.Query);
  Assert.AreEqual('setting', TDocsIndex.KindName(mRequest.Kind));
  Assert.AreEqual('en', TAtlasLocale.Code(mRequest.Language));
  Assert.AreEqual(TMcpDocsTools.cMaxLimit, mRequest.Limit);
  Assert.IsTrue(mRequest.Json);
  mRequest := RequestFor('{"query":"x"}');
  Assert.AreEqual('all', TDocsIndex.KindName(mRequest.Kind));
  Assert.AreEqual('de', TAtlasLocale.Code(mRequest.Language));
  Assert.AreEqual(TMcpDocsTools.cDefaultLimit, mRequest.Limit);
  Assert.IsFalse(mRequest.Json);
end;

procedure TMcpDocsToolsTests.RejectsBadArguments;
begin
  Assert.WillRaise(
    procedure
    begin
      RequestFor('{"query":"  "}');
    end, EMcpToolError);
  Assert.WillRaise(
    procedure
    begin
      RequestFor('{"query":"x","kind":"menu"}');
    end, EMcpToolError);
  Assert.WillRaise(
    procedure
    begin
      RequestFor('{"query":"x","language":"fr"}');
    end, EMcpToolError);
end;

procedure TMcpDocsToolsTests.ExactRuleWithWholeSection;
var
  mText: string;
begin
  mText := SearchFor('{"query":"empty-except"}');
  Assert.IsTrue(Pos(' Treffer' + sLineBreak + '1. Regel `empty-except` ', mText) > 0, mText);
  Assert.IsTrue(Pos('Im Projekt: ', mText) > 0, mText);
  Assert.IsTrue(Pos('Profil standard', mText) > 0, mText);
  Assert.IsTrue(Pos('Beispiel falsch:', mText) > 0, mText);
  Assert.IsTrue(Pos('```pascal', mText) > 0, mText);
end;

procedure TMcpDocsToolsTests.RuleSeverityFromProject;
var
  mRequest: TMcpDocsRequest;
  mText: string;
begin
  mRequest := RequestFor('{"query":"empty-except","kind":"rule"}');
  mRequest.Settings.Rules := [RuleSetting('empty-except', TRuleSeverity.Off)];
  mText := TMcpDocsTools.Search(mRequest);
  Assert.IsTrue(Pos('Im Projekt: off (gesetzt unter "rules")', mText) > 0, mText);
  mRequest.Settings.Rules := nil;
  mRequest.Settings.Profile := 'strict';
  mText := TMcpDocsTools.Search(mRequest);
  Assert.IsTrue(Pos('(Profil strict)', mText) > 0, mText);
end;

procedure TMcpDocsToolsTests.SettingValueWithOrigin;
var
  mRequest: TMcpDocsRequest;
begin
  mRequest := RequestFor('{"query":"minConfidence","kind":"setting"}');
  Assert.IsTrue(Pos('Aktuell: medium (Vorgabe)', TMcpDocsTools.Search(mRequest)) > 0);
  mRequest.ProjectText := '{"minConfidence": "high"}';
  Assert.IsTrue(Pos('Aktuell: high (atlas.json des Projekts)', TMcpDocsTools.Search(mRequest)) > 0);
  // Ein globaler Schlüssel kommt aus settings.json, auch wenn atlas.json ihn nennt.
  mRequest := RequestFor('{"query":"inlayHints.parameterNames","kind":"setting"}');
  mRequest.ProjectText := '{"inlayHints": {"parameterNames": true}}';
  mRequest.GlobalText := '{"inlayHints": {"parameterNames": false}}';
  Assert.IsTrue(Pos('Aktuell: false (settings.json für alle Projekte)', TMcpDocsTools.Search(mRequest)) > 0,
    TMcpDocsTools.Search(mRequest));
end;

procedure TMcpDocsToolsTests.PluginSettingAndShortCut;
var
  mText: string;
begin
  mText := SearchFor('{"query":"editor.breadcrumbs"}');
  Assert.IsTrue(Pos('1. Einstellung `editor.breadcrumbs` – Brotkrumenleiste', mText) > 0, mText);
  Assert.IsTrue(Pos('IDE-Plugins', mText) > 0, mText);
  mText := SearchFor('{"query":"navigation.dataFlow"}');
  Assert.IsTrue(Pos('Steht in: ', mText) > 0, mText);
  mText := SearchFor('{"query":"keys.breadcrumbs"}');
  Assert.IsTrue(Pos('Tastenkürzel: Strg+Umschalt+. (Vorgabe)', mText) > 0, mText);
  mText := SearchFor('{"query":"keys.breadcrumbs","language":"en"}');
  Assert.IsTrue(Pos('Shortcut: Ctrl+Shift+. (default)', mText) > 0, mText);
end;

procedure TMcpDocsToolsTests.QuestionFindsSetting;
var
  mText: string;
begin
  mText := SearchFor('{"query":"Wie schalte ich die Brotkrumen ab?","limit":3}');
  Assert.IsTrue(Pos('`editor.breadcrumbs`', mText) > 0, mText);
  mText := SearchFor('{"query":"Gliederung","kind":"window"}');
  Assert.IsTrue(Pos('docs/features/de/Navigieren.md#window-atlasoutline', mText) > 0, mText);
end;

procedure TMcpDocsToolsTests.AnswersInEnglish;
var
  mText: string;
begin
  mText := SearchFor('{"query":"empty-except","language":"en"}');
  Assert.IsTrue(Pos(' hits' + sLineBreak + '1. Rule `empty-except` ', mText) > 0, mText);
  Assert.IsTrue(Pos('In the project: ', mText) > 0, mText);
  mText := SearchFor('{"query":"outline","kind":"window","language":"en"}');
  Assert.IsTrue(Pos('docs/features/en/', mText) > 0, mText);
end;

procedure TMcpDocsToolsTests.NoHitsNamesSimilarIds;
var
  mText: string;
begin
  mText := SearchFor('{"query":"empty-exept"}');
  Assert.AreEqual(1, Pos('Keine Treffer für „empty-exept“.', mText), mText);
  Assert.IsTrue(Pos('empty-except', mText) > 0, mText);
end;

procedure TMcpDocsToolsTests.JsonHasTheSameFields;
var
  mRequest: TMcpDocsRequest;
  mRoot: TJSONObject;
  mHit: TJSONObject;
begin
  mRequest := RequestFor('{"query":"minConfidence","format":"json"}');
  mRequest.ProjectText := '{"minConfidence": "low"}';
  mRoot := TJSONObject.ParseJSONValue(TMcpDocsTools.Search(mRequest)) as TJSONObject;
  try
    mHit := mRoot.GetValue<TJSONArray>('results').Items[0] as TJSONObject;
    Assert.AreEqual('setting', mHit.GetValue<string>('kind'));
    Assert.AreEqual('minConfidence', mHit.GetValue<string>('id'));
    Assert.IsTrue(mHit.GetValue<Boolean>('exact'));
    Assert.AreEqual('low', mHit.GetValue<string>('value'));
    Assert.AreEqual('project', mHit.GetValue<string>('valueOrigin'));
    Assert.AreEqual('medium', mHit.GetValue<string>('default'));
  finally
    mRoot.Free;
  end;
  mRequest := RequestFor('{"query":"empty-except","format":"json"}');
  mRoot := TJSONObject.ParseJSONValue(TMcpDocsTools.Search(mRequest)) as TJSONObject;
  try
    mHit := mRoot.GetValue<TJSONArray>('results').Items[0] as TJSONObject;
    Assert.AreEqual('rule', mHit.GetValue<string>('kind'));
    Assert.AreEqual('profile', mHit.GetValue<string>('origin'));
    Assert.AreEqual('standard', mHit.GetValue<string>('originDetail'));
  finally
    mRoot.Free;
  end;
end;

end.
