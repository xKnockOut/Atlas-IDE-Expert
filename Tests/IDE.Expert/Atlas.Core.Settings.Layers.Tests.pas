unit Atlas.Core.Settings.Layers.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Ebenen, Auswahllisten, Regeltabelle, Prüfung und Baseline des Einstellungsdialogs (#227).</summary>
  [TestFixture]
  TAtlasSettingsLayersTests = class
  public
    [Test]
    procedure ProjectOverridesGlobalOverridesDefault;
    [Test]
    procedure ResetToGlobalRemovesOnlyThatKey;
    [Test]
    procedure UnchangedFileStaysByteIdentical;
    [Test]
    procedure GlobalModeEditsGlobalFile;
    [Test]
    procedure ComplexAndMismatchedValuesAreJsonFields;
    [Test]
    procedure SchemaReadsControlExamplesRestart;
    [Test]
    procedure DelphiVersionsShowProductAndStoreNumber;
    [Test]
    procedure ReadsConfigsAndPlatformsFromDproj;
    [Test]
    procedure ProfilesIncludeOwnOnes;
    [Test]
    procedure RuleRowsFromCatalogAndFile;
    [Test]
    procedure RuleSeverityKeepsOptions;
    [Test]
    procedure RuleSeverityChangeTouchesOnlyThatRule;
    [Test]
    procedure ReadsServerCheckAnswer;
    [Test]
    procedure SyntaxCheckWithoutServer;
    [Test]
    procedure CountsBaselineAndSuppressions;
    [Test]
    procedure GlobalFileUnderAppData;
    [Test]
    procedure KeepsEncodingAndLineEndings;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Settings.Schema,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.Layers,
  Atlas.Core.Settings.Choices,
  Atlas.Core.Settings.RuleTable,
  Atlas.Core.Settings.Validation,
  Atlas.Core.Settings.Baseline,
  Atlas.Core.Files.TextFile;

const
  LB = #13#10;
  ProjectText =
    '{' + LB +
    '  // Projekt' + LB +
    '  "language": "en",' + LB +
    '  "rules": {' + LB +
    '    "no-with": "error", // streng' + LB +
    '    "magic-number": { "severity": "hint", "ignore": [0, 1] }' + LB +
    '  },' + LB +
    '  "unknown": [1, 2]' + LB +
    '}' + LB;
  GlobalText =
    '{' + LB +
    '  "language": "de",' + LB +
    '  "memoryBudgetMb": 512' + LB +
    '}' + LB;

function Model(const AText, AGlobal: string; AGlobalMode: Boolean): TAtlasSettingsModel;
begin
  Result := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), AText, AGlobal, AGlobalMode);
end;

procedure TAtlasSettingsLayersTests.ProjectOverridesGlobalOverridesDefault;
var
  Settings: TAtlasSettingsModel;
  Language, Budget, Timeout: Integer;
begin
  Settings := Model(ProjectText, GlobalText, False);
  try
    Language := Settings.IndexOf('language');
    Budget := Settings.IndexOf('memoryBudgetMb');
    Timeout := Settings.IndexOf('requestTimeoutMs');
    Assert.IsTrue(Settings.Origin(Language) = TAtlasSettingOrigin.Project);
    Assert.AreEqual('"en"', Settings.Effective(Language));
    Assert.AreEqual('"de"', Settings.Inherited_(Language));
    Assert.IsTrue(Settings.Origin(Budget) = TAtlasSettingOrigin.Global);
    Assert.AreEqual('512', Settings.Effective(Budget));
    Assert.IsTrue(Settings.Origin(Timeout) = TAtlasSettingOrigin.Default_);
    Assert.AreEqual(Settings.Fields[Timeout].DefaultJson, Settings.Effective(Timeout));
  finally
    Settings.Free;
  end;
end;

procedure TAtlasSettingsLayersTests.ResetToGlobalRemovesOnlyThatKey;
var
  Settings: TAtlasSettingsModel;
  Language: Integer;
begin
  Settings := Model(ProjectText, GlobalText, False);
  try
    Language := Settings.IndexOf('language');
    Settings.Reset(Language);
    Assert.IsTrue(Settings.Origin(Language) = TAtlasSettingOrigin.Global);
    Assert.AreEqual('"de"', Settings.Effective(Language));
    Assert.AreEqual(StringReplace(ProjectText, '  "language": "en",' + LB, '', []), Settings.ResultText);
  finally
    Settings.Free;
  end;
end;

procedure TAtlasSettingsLayersTests.UnchangedFileStaysByteIdentical;
var
  Settings: TAtlasSettingsModel;
  Language: Integer;
begin
  Settings := Model(ProjectText, GlobalText, False);
  try
    Assert.IsFalse(Settings.Modified);
    Assert.AreEqual(ProjectText, Settings.ResultText);
    // Derselbe Wert noch einmal gesetzt: keine Änderung.
    Language := Settings.IndexOf('language');
    Settings.SetValue(Language, '"en"');
    Assert.AreEqual(ProjectText, Settings.ResultText);
    // Ein Wert geändert: nur er unterscheidet sich.
    Settings.SetValue(Language, '"de"');
    Assert.AreEqual(StringReplace(ProjectText, '"language": "en"', '"language": "de"', []), Settings.ResultText);
  finally
    Settings.Free;
  end;
end;

procedure TAtlasSettingsLayersTests.GlobalModeEditsGlobalFile;
var
  Settings: TAtlasSettingsModel;
  Budget: Integer;
begin
  Settings := Model(GlobalText, ProjectText, True);
  try
    Budget := Settings.IndexOf('memoryBudgetMb');
    Assert.IsTrue(Settings.Global);
    Assert.IsTrue(Settings.Origin(Budget) = TAtlasSettingOrigin.Global);
    // Global erbt nichts vom Projekt.
    Assert.AreEqual('', Settings.Inherited_(Settings.IndexOf('rules')));
    Settings.SetValue(Budget, '1024');
    Assert.AreEqual(StringReplace(GlobalText, '512', '1024', []), Settings.ResultText);
  finally
    Settings.Free;
  end;
end;

procedure TAtlasSettingsLayersTests.ComplexAndMismatchedValuesAreJsonFields;
var
  Settings: TAtlasSettingsModel;
begin
  Settings := Model('{"profile": {"editor": "fast"}, "language": "de"}', '', False);
  try
    Assert.IsFalse(Settings.Typed(Settings.IndexOf('rules')));
    Assert.IsFalse(Settings.Typed(Settings.IndexOf('profile')), 'Profil als Objekt');
    Assert.IsTrue(Settings.Typed(Settings.IndexOf('language')));
    // Auch Complex-Felder lassen sich als JSON-Text ändern.
    Settings.SetValue(Settings.IndexOf('overrides'), '[{"files": ["Tests/**"], "rules": {"*": "hint"}}]');
    Assert.IsTrue(Pos('"overrides": [{"files"', Settings.ResultText) > 0);
  finally
    Settings.Free;
  end;
end;

procedure TAtlasSettingsLayersTests.SchemaReadsControlExamplesRestart;
var
  Fields: TArray<TAtlasSettingField>;
  Field: TAtlasSettingField;
  Seen: Integer;
begin
  Fields := TAtlasSettingsSchema.Fields(AtlasSchemaJson);
  Seen := 0;
  for Field in Fields do
    if Field.Path = 'logFile' then
    begin
      Assert.IsTrue(Field.PicksFile);
      Assert.IsTrue(Field.Restart);
      Inc(Seen);
    end
    else if Field.Path = 'encoding' then
    begin
      Assert.AreEqual(3, Integer(Length(Field.Examples)));
      Assert.AreEqual('windows-1252', Field.Examples[1]);
      Assert.IsFalse(Field.PicksFile);
      Inc(Seen);
    end
    else if Field.Path = 'config' then
    begin
      Assert.AreEqual('Auswahl aus der .dproj', Field.Control);
      Inc(Seen);
    end;
  Assert.AreEqual(3, Seen);
end;

procedure TAtlasSettingsLayersTests.DelphiVersionsShowProductAndStoreNumber;
var
  Choices: TArray<TAtlasSettingChoice>;
begin
  Choices := TAtlasSettingChoices.DelphiVersions(['23.0', '37.0', '23.0', '99.0']);
  Assert.AreEqual(3, Integer(Length(Choices)));
  Assert.AreEqual('99.0', Choices[0].Caption, 'unbekannt: nur die Nummer');
  Assert.AreEqual('Delphi 13 (37.0)', Choices[1].Caption);
  Assert.AreEqual('"37.0"', Choices[1].Json);
  Assert.AreEqual('Delphi 12 (23.0)', Choices[2].Caption);
  Assert.AreEqual('"23.0"', Choices[2].Json);
  Assert.AreEqual(2, TAtlasSettingChoices.IndexOf(Choices, '"23.0"'));
  Assert.AreEqual(-1, TAtlasSettingChoices.IndexOf(Choices, '"12"'));
end;

procedure TAtlasSettingsLayersTests.ReadsConfigsAndPlatformsFromDproj;
const
  Dproj =
    '<Project>' + LB +
    '  <ItemGroup>' + LB +
    '    <BuildConfiguration Include="Base"><Key>Base</Key></BuildConfiguration>' + LB +
    '    <BuildConfiguration Include="Debug"><Key>Cfg_1</Key></BuildConfiguration>' + LB +
    '    <BuildConfiguration Include="Release"><Key>Cfg_2</Key></BuildConfiguration>' + LB +
    '  </ItemGroup>' + LB +
    '  <Platforms>' + LB +
    '    <Platform value="Win32">True</Platform>' + LB +
    '    <Platform value="Win64">True</Platform>' + LB +
    '    <Platform value="Linux64">False</Platform>' + LB +
    '  </Platforms>' + LB +
    '</Project>';
var
  Items: TArray<string>;
begin
  Items := TAtlasSettingChoices.DprojConfigs(Dproj);
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual('Debug', Items[0]);
  Assert.AreEqual('Release', Items[1]);
  Items := TAtlasSettingChoices.DprojPlatforms(Dproj);
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual('Win64', Items[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasSettingChoices.DprojConfigs(''))));
end;

procedure TAtlasSettingsLayersTests.ProfilesIncludeOwnOnes;
var
  Items: TArray<string>;
begin
  Items := TAtlasSettingChoices.Profiles('{"team": {"extends": "fast"}, "strict": {}}');
  Assert.AreEqual(6, Integer(Length(Items)));
  Assert.AreEqual('standard', Items[0]);
  Assert.AreEqual('team', Items[5]);
  Assert.AreEqual(5, Integer(Length(TAtlasSettingChoices.Profiles(''))));
end;

procedure TAtlasSettingsLayersTests.RuleRowsFromCatalogAndFile;
var
  Catalog: TJSONValue;
  Rows: TArray<TAtlasRuleRow>;
begin
  Catalog := TJSONObject.ParseJSONValue('{"rules": [' +
    '{"id": "no-with", "name": "Kein with", "category": "code-smell", "severity": "warning"},' +
    '{"id": "empty-except", "name": "Leeres except", "category": "bug", "severity": "error"}]}');
  try
    Rows := TAtlasRuleTable.Rows(Catalog, '{"no-with": "off", "own-rule": {"severity": "hint", "x": 1}}');
    Assert.AreEqual(3, Integer(Length(Rows)));
    Assert.AreEqual('no-with', Rows[0].Id);
    Assert.AreEqual('off', Rows[0].Severity);
    Assert.AreEqual('warning', Rows[0].DefaultSeverity);
    Assert.IsTrue(Rows[0].Known);
    Assert.AreEqual('', Rows[1].Severity);
    Assert.AreEqual('own-rule', Rows[2].Id);
    Assert.IsFalse(Rows[2].Known);
    Assert.IsTrue(Rows[2].HasOptions);
    Assert.AreEqual('hint', Rows[2].Severity);
    // Ohne Server: nur die Regeln aus der Datei.
    Assert.AreEqual(2, Integer(Length(TAtlasRuleTable.Rows(nil, '{"a": "off", "b": "error"}'))));
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsLayersTests.RuleSeverityKeepsOptions;
var
  Rules: string;
begin
  Rules := TAtlasRuleTable.WithSeverity('{"magic-number": {"severity": "hint", "ignore": [0]}}', 'magic-number',
    'error');
  Assert.IsTrue(Pos('"ignore":[0]', Rules) > 0);
  Assert.IsTrue(Pos('"severity":"error"', Rules) > 0);
  Rules := TAtlasRuleTable.WithSeverity('{"no-with": "error"}', 'no-with', '');
  Assert.AreEqual('', Rules);
  Rules := TAtlasRuleTable.WithSeverity('', 'no-with', 'off');
  Assert.AreEqual('{"no-with":"off"}', Rules);
end;

procedure TAtlasSettingsLayersTests.RuleSeverityChangeTouchesOnlyThatRule;
var
  Settings: TAtlasSettingsModel;
  Path, Json: string;
begin
  TAtlasRuleTable.SeverityChange('{"magic-number": {"severity": "hint"}}', 'magic-number', 'off', Path, Json);
  Assert.AreEqual('rules.magic-number.severity', Path);
  Assert.AreEqual('"off"', Json);
  TAtlasRuleTable.SeverityChange('{"no-with": "error"}', 'no-with', '', Path, Json);
  Assert.AreEqual('rules.no-with', Path);
  Assert.AreEqual('', Json);
  Settings := Model(ProjectText, '', False);
  try
    Settings.SetPath('rules.no-with', '"off"');
    Assert.AreEqual(StringReplace(ProjectText, '"no-with": "error"', '"no-with": "off"', []), Settings.ResultText);
    Settings.SetPath('rules.magic-number.severity', '"warning"');
    Assert.IsTrue(Pos('{ "severity": "warning", "ignore": [0, 1] }', Settings.ResultText) > 0);
    Assert.IsTrue(Pos('// streng', Settings.ResultText) > 0);
  finally
    Settings.Free;
  end;
end;

procedure TAtlasSettingsLayersTests.ReadsServerCheckAnswer;
var
  Answer: TJSONValue;
  Issues: TArray<TAtlasSettingIssue>;
  Valid: Boolean;
  Lines: TArray<string>;
begin
  Answer := TJSONObject.ParseJSONValue('{"valid": false, "issues": [' +
    '{"line": 3, "character": 2, "message": "Unbekannter Schlüssel", "error": false},' +
    '{"line": 1, "character": 14, "message": "Ungültiger Wert", "error": true}]}');
  try
    Assert.IsTrue(TAtlasSettingsValidation.FromAnswer(Answer, Issues, Valid));
    Assert.IsFalse(Valid);
    Assert.AreEqual(2, Integer(Length(Issues)));
    Assert.IsTrue(Issues[1].Error);
    Lines := TAtlasSettingsValidation.Lines(Issues);
    Assert.AreEqual('Zeile 2: Ungültiger Wert', Lines[0]);
    Assert.AreEqual('Zeile 4: Unbekannter Schlüssel', Lines[1]);
  finally
    Answer.Free;
  end;
  Assert.IsFalse(TAtlasSettingsValidation.FromAnswer(nil, Issues, Valid), 'ohne Server');
end;

procedure TAtlasSettingsLayersTests.SyntaxCheckWithoutServer;
var
  Issues: TArray<TAtlasSettingIssue>;
begin
  Assert.IsTrue(TAtlasSettingsValidation.Syntax(ProjectText, Issues));
  Assert.IsTrue(TAtlasSettingsValidation.Syntax('', Issues));
  Assert.IsFalse(TAtlasSettingsValidation.Syntax('{"a": ', Issues));
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.IsTrue(Issues[0].Error);
end;

procedure TAtlasSettingsLayersTests.CountsBaselineAndSuppressions;
var
  Entries: Integer;
  Rows: TArray<TAtlasSuppressionRow>;
begin
  Assert.AreEqual(5, TAtlasBaselineInfo.Count('{"version": 1, "findings": [' +
    '{"path": "a.pas", "rule": "x", "fingerprint": "f", "count": 3},' +
    '{"path": "b.pas", "rule": "y", "fingerprint": "g", "count": 2}]}', Entries));
  Assert.AreEqual(2, Entries);
  Assert.AreEqual(-1, TAtlasBaselineInfo.Count('kaputt', Entries));
  Rows := TAtlasBaselineInfo.Suppressions('{"suppressions":[{"rule":"no-with","total":4,"line":3,"file":1,' +
    '"unused":1,"files":2}],"files":10}');
  Assert.AreEqual(1, Integer(Length(Rows)));
  Assert.AreEqual('no-with', Rows[0].Rule);
  Assert.AreEqual(4, Rows[0].Total);
  Assert.AreEqual(1, Rows[0].Unused);
  Assert.AreEqual(2, Rows[0].Files);
end;

procedure TAtlasSettingsLayersTests.GlobalFileUnderAppData;
begin
  Assert.AreEqual('', TAtlasSettingsFiles.GlobalFile(''));
  Assert.IsTrue(TAtlasSettingsFiles.GlobalFile('C:\Users\X\AppData\Roaming').EndsWith('settings.json'));
  Assert.IsTrue(Pos('Atlas', TAtlasSettingsFiles.GlobalFile('C:\Users\X\AppData\Roaming')) > 0);
end;

procedure TAtlasSettingsLayersTests.KeepsEncodingAndLineEndings;
var
  Bytes, Saved: TBytes;
  Content: TAtlasTextFileContent;
  Settings: TAtlasSettingsModel;
  Text: string;
  Index: Integer;
  Ansi: TEncoding;
begin
  // ANSI (Windows-1252) mit Umlaut im Kommentar und LF-Zeilenenden (#121).
  Text := '{'#10'  // Prüfregeln für Größen'#10'  "language": "de"'#10'}'#10;
  Ansi := TEncoding.GetEncoding(1252);
  try
    Bytes := Ansi.GetBytes(Text);
  finally
    Ansi.Free;
  end;
  Content := TAtlasTextFile.Decode(Bytes, 1252);
  Assert.IsTrue(Content.Encoding = TAtlasTextEncoding.Ansi);
  Settings := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), Content.Text, '', False);
  try
    Content.Text := Settings.ResultText;
    Saved := TAtlasTextFile.Encode(Content);
    Assert.AreEqual(Integer(Length(Bytes)), Integer(Length(Saved)));
    for Index := 0 to High(Bytes) do
      Assert.AreEqual(Bytes[Index], Saved[Index]);
    Settings.SetValue(Settings.IndexOf('language'), '"en"');
    Content.Text := Settings.ResultText;
    Assert.AreEqual(StringReplace(Text, '"de"', '"en"', []), Content.Text);
  finally
    Settings.Free;
  end;
  // UTF-8 mit BOM bleibt mit BOM.
  Bytes := TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes('{"language": "de"}');
  Content := TAtlasTextFile.Decode(Bytes);
  Assert.IsTrue(Content.Encoding = TAtlasTextEncoding.Utf8Bom);
  Saved := TAtlasTextFile.Encode(Content);
  Assert.AreEqual(Integer(Length(Bytes)), Integer(Length(Saved)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsLayersTests);

end.
