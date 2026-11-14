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
    procedure KnownVersionsForMinDelphiVersion;
    [Test]
    procedure ReadsConfigsAndPlatformsFromDproj;
    [Test]
    procedure ProfilesIncludeOwnOnes;
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
  Atlas.Core.Settings.Validation,
  Atlas.Core.Settings.Baseline,
  Atlas.Core.Files.TextFile;

const
  cLB = #13#10;
  cProjectText =
    '{' + cLB +
    '  // Projekt' + cLB +
    '  "language": "en",' + cLB +
    '  "rules": {' + cLB +
    '    "no-with": "error", // streng' + cLB +
    '    "magic-number": { "severity": "hint", "ignore": [0, 1] }' + cLB +
    '  },' + cLB +
    '  "unknown": [1, 2]' + cLB +
    '}' + cLB;
  cGlobalText =
    '{' + cLB +
    '  "language": "de",' + cLB +
    '  "memoryBudgetMb": 512' + cLB +
    '}' + cLB;

function Model(const AText, AGlobal: string; AGlobalMode: Boolean): TAtlasSettingsModel;
begin
  Result := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), AText, AGlobal, AGlobalMode);
end;

procedure TAtlasSettingsLayersTests.ProjectOverridesGlobalOverridesDefault;
var
  mSettings: TAtlasSettingsModel;
  mLanguage, mBudget, mTimeout: Integer;
begin
  mSettings := Model(cProjectText, cGlobalText, False);
  try
    mLanguage := mSettings.IndexOf('language');
    mBudget := mSettings.IndexOf('memoryBudgetMb');
    mTimeout := mSettings.IndexOf('requestTimeoutMs');
    Assert.AreEqual<TAtlasSettingOrigin>(TAtlasSettingOrigin.Project, mSettings.Origin(mLanguage));
    Assert.AreEqual('"en"', mSettings.Effective(mLanguage));
    Assert.AreEqual('"de"', mSettings.Inherited_(mLanguage));
    Assert.AreEqual<TAtlasSettingOrigin>(TAtlasSettingOrigin.Global, mSettings.Origin(mBudget));
    Assert.AreEqual('512', mSettings.Effective(mBudget));
    Assert.AreEqual<TAtlasSettingOrigin>(TAtlasSettingOrigin.Default_, mSettings.Origin(mTimeout));
    Assert.AreEqual(mSettings.Fields[mTimeout].DefaultJson, mSettings.Effective(mTimeout));
  finally
    mSettings.Free;
  end;
end;

procedure TAtlasSettingsLayersTests.ResetToGlobalRemovesOnlyThatKey;
var
  mSettings: TAtlasSettingsModel;
  mLanguage: Integer;
begin
  mSettings := Model(cProjectText, cGlobalText, False);
  try
    mLanguage := mSettings.IndexOf('language');
    mSettings.Reset(mLanguage);
    Assert.AreEqual<TAtlasSettingOrigin>(TAtlasSettingOrigin.Global, mSettings.Origin(mLanguage));
    Assert.AreEqual('"de"', mSettings.Effective(mLanguage));
    Assert.AreEqual(StringReplace(cProjectText, '  "language": "en",' + cLB, '', []), mSettings.ResultText);
  finally
    mSettings.Free;
  end;
end;

procedure TAtlasSettingsLayersTests.UnchangedFileStaysByteIdentical;
var
  mSettings: TAtlasSettingsModel;
  mLanguage: Integer;
begin
  mSettings := Model(cProjectText, cGlobalText, False);
  try
    Assert.IsFalse(mSettings.Modified);
    Assert.AreEqual(cProjectText, mSettings.ResultText);
    // Derselbe Wert noch einmal gesetzt: keine Änderung.
    mLanguage := mSettings.IndexOf('language');
    mSettings.SetValue(mLanguage, '"en"');
    Assert.AreEqual(cProjectText, mSettings.ResultText);
    // Ein Wert geändert: nur er unterscheidet sich.
    mSettings.SetValue(mLanguage, '"de"');
    Assert.AreEqual(StringReplace(cProjectText, '"language": "en"', '"language": "de"', []), mSettings.ResultText);
  finally
    mSettings.Free;
  end;
end;

procedure TAtlasSettingsLayersTests.GlobalModeEditsGlobalFile;
var
  mSettings: TAtlasSettingsModel;
  mBudget: Integer;
begin
  mSettings := Model(cGlobalText, cProjectText, True);
  try
    mBudget := mSettings.IndexOf('memoryBudgetMb');
    Assert.IsTrue(mSettings.Global);
    Assert.AreEqual<TAtlasSettingOrigin>(TAtlasSettingOrigin.Global, mSettings.Origin(mBudget));
    // Global erbt nichts vom Projekt.
    Assert.AreEqual('', mSettings.Inherited_(mSettings.IndexOf('rules')));
    mSettings.SetValue(mBudget, '1024');
    Assert.AreEqual(StringReplace(cGlobalText, '512', '1024', []), mSettings.ResultText);
  finally
    mSettings.Free;
  end;
end;

procedure TAtlasSettingsLayersTests.ComplexAndMismatchedValuesAreJsonFields;
var
  mSettings: TAtlasSettingsModel;
begin
  mSettings := Model('{"profile": {"editor": "fast"}, "language": "de"}', '', False);
  try
    Assert.IsFalse(mSettings.Typed(mSettings.IndexOf('rules')));
    Assert.IsFalse(mSettings.Typed(mSettings.IndexOf('profile')), 'Profil als Objekt');
    Assert.IsTrue(mSettings.Typed(mSettings.IndexOf('language')));
    // Auch Complex-Felder lassen sich als JSON-Text ändern.
    mSettings.SetValue(mSettings.IndexOf('overrides'), '[{"files": ["Tests/**"], "rules": {"*": "hint"}}]');
    Assert.IsTrue(Pos('"overrides": [{"files"', mSettings.ResultText) > 0);
  finally
    mSettings.Free;
  end;
end;

procedure TAtlasSettingsLayersTests.SchemaReadsControlExamplesRestart;
var
  mFields: TArray<TAtlasSettingField>;
  mField: TAtlasSettingField;
  mSeen: Integer;
begin
  mFields := TAtlasSettingsSchema.Fields(AtlasSchemaJson);
  mSeen := 0;
  for mField in mFields do
  begin
    if mField.Path = 'logFile' then
    begin
      Assert.IsTrue(mField.PicksFile);
      Assert.IsTrue(mField.Restart);
      Inc(mSeen);
    end
    else if mField.Path = 'encoding' then
    begin
      Assert.AreEqual(3, Integer(Length(mField.Examples)));
      Assert.AreEqual('windows-1252', mField.Examples[1]);
      Assert.IsFalse(mField.PicksFile);
      Inc(mSeen);
    end
    else if mField.Path = 'config' then
    begin
      Assert.AreEqual('Auswahl aus der .dproj', mField.Control);
      Inc(mSeen);
    end;
  end;
  Assert.AreEqual(3, mSeen);
end;

procedure TAtlasSettingsLayersTests.DelphiVersionsShowProductAndStoreNumber;
var
  mChoices: TArray<TAtlasSettingChoice>;
begin
  mChoices := TAtlasSettingChoices.DelphiVersions(['23.0', '37.0', '23.0', '99.0']);
  Assert.AreEqual(3, Integer(Length(mChoices)));
  Assert.AreEqual('99.0', mChoices[0].Caption, 'unbekannt: nur die Nummer');
  Assert.AreEqual('Delphi 13 (37.0)', mChoices[1].Caption);
  Assert.AreEqual('"37.0"', mChoices[1].Json);
  Assert.AreEqual('Delphi 12 (23.0)', mChoices[2].Caption);
  Assert.AreEqual('"23.0"', mChoices[2].Json);
  Assert.AreEqual(2, TAtlasSettingChoices.IndexOf(mChoices, '"23.0"'));
  Assert.AreEqual(-1, TAtlasSettingChoices.IndexOf(mChoices, '"12"'));
end;

procedure TAtlasSettingsLayersTests.KnownVersionsForMinDelphiVersion;
var
  mChoices: TArray<TAtlasSettingChoice>;
begin
  // #1126: auch nicht installierte Versionen, neueste zuerst.
  mChoices := TAtlasSettingChoices.DelphiVersions(TAtlasSettingChoices.KnownVersions);
  Assert.AreEqual(Integer(Length(TAtlasSettingChoices.KnownVersions)), Integer(Length(mChoices)));
  Assert.AreEqual('Delphi 13 (37.0)', mChoices[0].Caption);
  Assert.IsTrue(TAtlasSettingChoices.IndexOf(mChoices, '"23.0"') >= 0);
  Assert.IsTrue(TAtlasSettingChoices.IndexOf(mChoices, '"20.0"') >= 0);
end;

procedure TAtlasSettingsLayersTests.ReadsConfigsAndPlatformsFromDproj;
const
  cDproj =
    '<Project>' + cLB +
    '  <ItemGroup>' + cLB +
    '    <BuildConfiguration Include="Base"><Key>Base</Key></BuildConfiguration>' + cLB +
    '    <BuildConfiguration Include="Debug"><Key>Cfg_1</Key></BuildConfiguration>' + cLB +
    '    <BuildConfiguration Include="Release"><Key>Cfg_2</Key></BuildConfiguration>' + cLB +
    '  </ItemGroup>' + cLB +
    '  <Platforms>' + cLB +
    '    <Platform value="Win32">True</Platform>' + cLB +
    '    <Platform value="Win64">True</Platform>' + cLB +
    '    <Platform value="Linux64">False</Platform>' + cLB +
    '  </Platforms>' + cLB +
    '</Project>';
var
  mItems: TArray<string>;
begin
  mItems := TAtlasSettingChoices.DprojConfigs(cDproj);
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('Debug', mItems[0]);
  Assert.AreEqual('Release', mItems[1]);
  mItems := TAtlasSettingChoices.DprojPlatforms(cDproj);
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('Win64', mItems[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasSettingChoices.DprojConfigs(''))));
end;

procedure TAtlasSettingsLayersTests.ProfilesIncludeOwnOnes;
var
  mItems: TArray<string>;
begin
  mItems := TAtlasSettingChoices.Profiles('{"team": {"extends": "fast"}, "strict": {}}');
  Assert.AreEqual(6, Integer(Length(mItems)));
  Assert.AreEqual('standard', mItems[0]);
  Assert.AreEqual('team', mItems[5]);
  Assert.AreEqual(5, Integer(Length(TAtlasSettingChoices.Profiles(''))));
end;

procedure TAtlasSettingsLayersTests.RuleSeverityChangeTouchesOnlyThatRule;
var
  mSettings: TAtlasSettingsModel;
begin
  // Pfade rules.<id> bzw. rules.<id>.severity (Regeltabelle des Moduls Prüfregeln) ändern nur diesen Wert.
  mSettings := Model(cProjectText, '', False);
  try
    mSettings.SetPath('rules.no-with', '"off"');
    Assert.AreEqual(StringReplace(cProjectText, '"no-with": "error"', '"no-with": "off"', []), mSettings.ResultText);
    mSettings.SetPath('rules.magic-number.severity', '"warning"');
    Assert.IsTrue(Pos('{ "severity": "warning", "ignore": [0, 1] }', mSettings.ResultText) > 0);
    Assert.IsTrue(Pos('// streng', mSettings.ResultText) > 0);
  finally
    mSettings.Free;
  end;
end;

procedure TAtlasSettingsLayersTests.ReadsServerCheckAnswer;
var
  mAnswer: TJSONValue;
  mIssues: TArray<TAtlasSettingIssue>;
  mValid: Boolean;
  mLines: TArray<string>;
begin
  mAnswer := TJSONObject.ParseJSONValue('{"valid": false, "issues": [' +
    '{"line": 3, "character": 2, "message": "Unbekannter Schlüssel", "error": false},' +
    '{"line": 1, "character": 14, "message": "Ungültiger Wert", "error": true}]}');
  try
    Assert.IsTrue(TAtlasSettingsValidation.FromAnswer(mAnswer, mIssues, mValid));
    Assert.IsFalse(mValid);
    Assert.AreEqual(2, Integer(Length(mIssues)));
    Assert.IsTrue(mIssues[1].Error);
    mLines := TAtlasSettingsValidation.Lines(mIssues);
    Assert.AreEqual('Zeile 2: Ungültiger Wert', mLines[0]);
    Assert.AreEqual('Zeile 4: Unbekannter Schlüssel', mLines[1]);
  finally
    mAnswer.Free;
  end;
  Assert.IsFalse(TAtlasSettingsValidation.FromAnswer(nil, mIssues, mValid), 'ohne Server');
end;

procedure TAtlasSettingsLayersTests.SyntaxCheckWithoutServer;
var
  mIssues: TArray<TAtlasSettingIssue>;
begin
  Assert.IsTrue(TAtlasSettingsValidation.Syntax(cProjectText, mIssues));
  Assert.IsTrue(TAtlasSettingsValidation.Syntax('', mIssues));
  Assert.IsFalse(TAtlasSettingsValidation.Syntax('{"a": ', mIssues));
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].Error);
end;

procedure TAtlasSettingsLayersTests.CountsBaselineAndSuppressions;
var
  mEntries: Integer;
  mRows: TArray<TAtlasSuppressionRow>;
begin
  Assert.AreEqual(5, TAtlasBaselineInfo.Count('{"version": 1, "findings": [' +
    '{"path": "a.pas", "rule": "x", "fingerprint": "f", "count": 3},' +
    '{"path": "b.pas", "rule": "y", "fingerprint": "g", "count": 2}]}', mEntries));
  Assert.AreEqual(2, mEntries);
  Assert.AreEqual(-1, TAtlasBaselineInfo.Count('kaputt', mEntries));
  mRows := TAtlasBaselineInfo.Suppressions('{"suppressions":[{"rule":"no-with","total":4,"line":3,"file":1,' +
    '"unused":1,"files":2}],"files":10}');
  Assert.AreEqual(1, Integer(Length(mRows)));
  Assert.AreEqual('no-with', mRows[0].Rule);
  Assert.AreEqual(4, mRows[0].Total);
  Assert.AreEqual(1, mRows[0].Unused);
  Assert.AreEqual(2, mRows[0].Files);
end;

procedure TAtlasSettingsLayersTests.GlobalFileUnderAppData;
begin
  Assert.AreEqual('', TAtlasSettingsFiles.GlobalFile(''));
  Assert.IsTrue(TAtlasSettingsFiles.GlobalFile('C:\Users\X\AppData\Roaming').EndsWith('settings.json'));
  Assert.IsTrue(Pos('Atlas', TAtlasSettingsFiles.GlobalFile('C:\Users\X\AppData\Roaming')) > 0);
end;

procedure TAtlasSettingsLayersTests.KeepsEncodingAndLineEndings;
var
  mBytes, mSaved: TBytes;
  mContent: TAtlasTextFileContent;
  mSettings: TAtlasSettingsModel;
  mText: string;
  mIndex: Integer;
  mAnsi: TEncoding;
begin
  // ANSI (Windows-1252) mit Umlaut im Kommentar und LF-Zeilenenden (#121).
  mText := '{'#10'  // Prüfregeln für Größen'#10'  "language": "de"'#10'}'#10;
  mAnsi := TEncoding.GetEncoding(1252);
  try
    mBytes := mAnsi.GetBytes(mText);
  finally
    mAnsi.Free;
  end;
  mContent := TAtlasTextFile.Decode(mBytes, 1252);
  Assert.AreEqual<TAtlasTextEncoding>(TAtlasTextEncoding.Ansi, mContent.Encoding);
  mSettings := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), mContent.Text, '', False);
  try
    mContent.Text := mSettings.ResultText;
    mSaved := TAtlasTextFile.Encode(mContent);
    Assert.AreEqual(Integer(Length(mBytes)), Integer(Length(mSaved)));
    for mIndex := 0 to High(mBytes) do
    begin
      Assert.AreEqual(mBytes[mIndex], mSaved[mIndex]);
    end;
    mSettings.SetValue(mSettings.IndexOf('language'), '"en"');
    mContent.Text := mSettings.ResultText;
    Assert.AreEqual(StringReplace(mText, '"de"', '"en"', []), mContent.Text);
  finally
    mSettings.Free;
  end;
  // UTF-8 mit BOM bleibt mit BOM.
  mBytes := TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes('{"language": "de"}');
  mContent := TAtlasTextFile.Decode(mBytes);
  Assert.AreEqual<TAtlasTextEncoding>(TAtlasTextEncoding.Utf8Bom, mContent.Encoding);
  mSaved := TAtlasTextFile.Encode(mContent);
  Assert.AreEqual(Integer(Length(mBytes)), Integer(Length(mSaved)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsLayersTests);

end.
