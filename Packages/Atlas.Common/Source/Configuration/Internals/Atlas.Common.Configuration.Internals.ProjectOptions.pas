unit Atlas.Common.Configuration.Internals.ProjectOptions;

// Abschnitte von atlas.json zum Projekt: format (Formatierung), compiler
// (Übersetzen beim Speichern), tests (betroffene Tests), testUnits (Lage der
// Testunits) und dfmPropertyRules (Regeln für Eigenschaften in Formularen).

interface

uses
  Atlas.Common.Configuration.Internals.Reader;

/// <summary>Abschnitte dieser Unit.</summary>
function ProjectSections: TArray<TConfigurationSection>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Internals.JsonTree;

{ format }

/// <summary>Wahrheitswert, der als ausdrücklich gesetzt gilt (AGiven), wenn er gültig ist.</summary>
procedure ReadGivenFlag(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  AGiven: TFormatKey; var AStyle: TFormatStyle; var ATarget: Boolean);
begin
  if AReader.ExpectBoolean(AValue, AKey, ATarget) then
  begin
    Include(AStyle.Given, AGiven);
  end;
end;

procedure ReadUseTabs(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadGivenFlag(AReader, AValue, AKey, TFormatKey.UseTabs, ASettings.Formatting, ASettings.Formatting.UseTabs);
end;

procedure ReadTrimTrailing(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadGivenFlag(AReader, AValue, AKey, TFormatKey.TrimTrailingWhitespace, ASettings.Formatting,
    ASettings.Formatting.TrimTrailingWhitespace);
end;

procedure ReadFinalNewline(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadGivenFlag(AReader, AValue, AKey, TFormatKey.InsertFinalNewline, ASettings.Formatting,
    ASettings.Formatting.InsertFinalNewline);
end;

procedure ReadSpaceAroundAssignment(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadGivenFlag(AReader, AValue, AKey, TFormatKey.SpaceAroundAssignment, ASettings.Formatting,
    ASettings.Formatting.SpaceAroundAssignment);
end;

procedure ReadSpaceAfterComma(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadGivenFlag(AReader, AValue, AKey, TFormatKey.SpaceAfterComma, ASettings.Formatting,
    ASettings.Formatting.SpaceAfterComma);
end;

procedure ReadIndentSize(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  if AReader.ExpectInteger(AValue, 1, 16, '"indentSize" muss eine ganze Zahl von 1 bis 16 sein',
    ASettings.Formatting.IndentSize) then
  begin
    Include(ASettings.Formatting.Given, TFormatKey.IndentSize);
  end;
end;

procedure ReadMaxLineLength(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  if AReader.ExpectInteger(AValue, 0, 1000, '"maxLineLength" muss eine ganze Zahl von 0 bis 1000 sein',
    ASettings.Formatting.MaxLineLength) then
  begin
    Include(ASettings.Formatting.Given, TFormatKey.MaxLineLength);
  end;
end;

procedure ReadKeywordCase(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mIndex: Integer;
begin
  if AReader.ExpectOneOf(AValue, ['preserve', 'lower', 'upper'], 'Erlaubt sind "preserve", "lower" und "upper"',
    mIndex) then
  begin
    ASettings.Formatting.KeywordCase := TKeywordCase(mIndex);
    Include(ASettings.Formatting.Given, TFormatKey.KeywordCase);
  end;
end;

procedure ReadEndOfLine(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
const
  cBreaks: array[0..1] of string = (#10, #13#10);
var
  mIndex: Integer;
begin
  if AReader.ExpectOneOf(AValue, ['lf', 'crlf'], 'Erlaubt sind "lf" und "crlf"', mIndex) then
  begin
    ASettings.Formatting.EndOfLine := cBreaks[mIndex];
    Include(ASettings.Formatting.Given, TFormatKey.EndOfLine);
  end;
end;

/// <summary>Stellung von begin bzw. else; ungültig bleibt der bisherige Wert.</summary>
procedure ReadPlacement(AReader: TConfigurationReader; AValue: TJsonNode; var ATarget: TBlockPlacement);
var
  mIndex: Integer;
begin
  if AReader.ExpectOneOf(AValue, ['preserve', 'newLine', 'sameLine'],
    'Erlaubt sind "preserve", "newLine" und "sameLine"', mIndex) then
  begin
    ATarget := TBlockPlacement(mIndex);
  end;
end;

procedure ReadBeginPlacement(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadPlacement(AReader, AValue, ASettings.Formatting.BeginPlacement);
end;

procedure ReadElsePlacement(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadPlacement(AReader, AValue, ASettings.Formatting.ElsePlacement);
end;

const
  cFormatMembers: array[0..10] of TMemberOption = ((Key: 'indentSize'; Read: ReadIndentSize),
    (Key: 'useTabs'; Read: ReadUseTabs), (Key: 'trimTrailingWhitespace'; Read: ReadTrimTrailing),
    (Key: 'insertFinalNewline'; Read: ReadFinalNewline),
    (Key: 'spaceAroundAssignment'; Read: ReadSpaceAroundAssignment),
    (Key: 'spaceAfterComma'; Read: ReadSpaceAfterComma), (Key: 'keywordCase'; Read: ReadKeywordCase),
    (Key: 'endOfLine'; Read: ReadEndOfLine), (Key: 'beginPlacement'; Read: ReadBeginPlacement),
    (Key: 'elsePlacement'; Read: ReadElsePlacement), (Key: 'maxLineLength'; Read: ReadMaxLineLength));

// Der Block ersetzt die Formatierung ganz: Was fehlt, gilt als Vorgabe. Der Text geht unverändert an das Plugin.
procedure ReadFormat(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  if not AReader.ExpectObject(ANode, 'format') then
  begin
    Exit;
  end;
  ASettings.Format := AReader.NodeText(ANode);
  ASettings.Formatting := TFormatStyle.Default;
  AReader.ReadObject(ANode, 'format', [TFlagOption.Create('reindent', ASettings.Formatting.Reindent),
    TFlagOption.Create('alignAssignments', ASettings.Formatting.AlignAssignments),
    TFlagOption.Create('alignDeclarations', ASettings.Formatting.AlignDeclarations),
    TFlagOption.Create('alignComments', ASettings.Formatting.AlignComments)], cFormatMembers, ASettings);
end;

procedure TakeFormat(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Format := ASource.Format;
  ATarget.Formatting := ASource.Formatting;
end;

{ compiler }

procedure ReadCompilerBackend(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoice(AValue, AKey, ['auto', 'dcc', 'ide', 'off'], 'Erlaubt sind "auto", "dcc", "ide" und "off"',
    mIndex) then
  begin
    ASettings.Compiler.Backend := TCompilerBackendSetting(mIndex);
  end;
end;

procedure ReadIdeCommand(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ExpectString(AValue, AKey, ASettings.Compiler.IdeCommand);
end;

const
  cCompilerMembers: array[0..1] of TMemberOption = ((Key: 'backend'; Read: ReadCompilerBackend),
    (Key: 'ideCommand'; Read: ReadIdeCommand));

procedure ReadCompiler(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'compiler', [TFlagOption.Create('onSave', ASettings.Compiler.OnSave)], cCompilerMembers,
    ASettings);
end;

procedure TakeCompiler(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Compiler := ASource.Compiler;
end;

{ tests }

procedure ReadAffectedDepth(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ExpectInteger(AValue, TTestsSettings.MinAffectedDepth, TTestsSettings.MaxAffectedDepth,
    '"affectedDepth" muss eine ganze Zahl von 1 bis 5 sein', ASettings.Tests.AffectedDepth);
end;

const
  cTestsMembers: array[0..0] of TMemberOption = ((Key: 'affectedDepth'; Read: ReadAffectedDepth));

procedure ReadTests(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'tests', [TFlagOption.Create('affected', ASettings.Tests.Affected)], cTestsMembers,
    ASettings);
end;

procedure TakeTests(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Tests := ASource.Tests;
end;

{ testUnits }

procedure ReadTestPattern(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mText: string;
begin
  if not AReader.ExpectString(AValue, AKey, mText) then
  begin
    Exit;
  end;
  // Ohne {unit} hätten alle Units dieselbe Testunit.
  if Pos('{unit}', mText) = 0 then
  begin
    AReader.ReportNode(AValue, '"testUnits.pattern" muss {unit} enthalten');
  end
  else
  begin
    ASettings.TestUnits.Pattern := mText;
  end;
end;

procedure ReadTestFolder(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mText: string;
begin
  if AReader.ExpectString(AValue, AKey, mText) then
  begin
    ASettings.TestUnits.Folder := mText;
  end;
end;

procedure ReadTestProject(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mText: string;
begin
  if not AReader.ExpectString(AValue, AKey, mText) then
  begin
    Exit;
  end;
  if (mText <> '') and not MatchText(ExtractFileExt(mText), ['.dproj', '.dpr']) then
  begin
    AReader.ReportNode(AValue, '"testUnits.project" muss eine .dproj oder .dpr sein');
  end
  else
  begin
    ASettings.TestUnits.Project := mText;
  end;
end;

const
  cTestUnitsMembers: array[0..2] of TMemberOption = ((Key: 'pattern'; Read: ReadTestPattern),
    (Key: 'folder'; Read: ReadTestFolder), (Key: 'project'; Read: ReadTestProject));

procedure ReadTestUnits(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'testUnits', [], cTestUnitsMembers, ASettings);
end;

procedure TakeTestUnits(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.TestUnits := ASource.TestUnits;
end;

{ dfmPropertyRules }

type
  TDfmRuleRead = procedure(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
    var ARule: TDfmPropertyRule);

  TDfmRuleMember = record
    Key: string;
    Read: TDfmRuleRead;
  end;

procedure ReadRuleClass(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ARule: TDfmPropertyRule);
begin
  AReader.ExpectString(AValue, AKey, ARule.ClassName);
  ARule.ClassRange := TTextRange.Create(AReader.PositionAt(AValue.Start), AReader.PositionAt(AValue.Stop));
end;

procedure ReadRuleProperty(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ARule: TDfmPropertyRule);
begin
  AReader.ExpectString(AValue, AKey, ARule.PropertyPath);
  ARule.PropertyRange := TTextRange.Create(AReader.PositionAt(AValue.Start), AReader.PositionAt(AValue.Stop));
end;

procedure ReadRuleValue(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ARule: TDfmPropertyRule);
begin
  AReader.ExpectString(AValue, AKey, ARule.Value);
end;

procedure ReadRuleMessage(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ARule: TDfmPropertyRule);
begin
  AReader.ExpectString(AValue, AKey, ARule.Message);
end;

procedure ReadRuleCondition(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ARule: TDfmPropertyRule);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoice(AValue, AKey, ['=', '<>', 'contains', 'notContains', 'empty', 'notEmpty'],
    'Erlaubt sind "=", "<>", "contains", "notContains", "empty" und "notEmpty"', mIndex) then
  begin
    ARule.Condition := TDfmCondition(mIndex);
  end;
end;

procedure ReadRuleSeverity(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ARule: TDfmPropertyRule);
var
  mText: string;
begin
  if AReader.ExpectString(AValue, AKey, mText) and not TryParseRuleSeverity(mText, ARule.Severity) then
  begin
    AReader.ReportNode(AValue, Format('Unbekannter Schweregrad "%s"; erlaubt: off, hint, info, warning, error',
      [mText]));
  end;
end;

procedure ReadRuleDescendants(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ARule: TDfmPropertyRule);
begin
  AReader.ExpectBoolean(AValue, AKey, ARule.IncludeDescendants);
end;

procedure ReadRuleFix(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ARule: TDfmPropertyRule);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoice(AValue, AKey, ['prompt', 'auto', 'none'], 'Erlaubt sind "auto", "prompt" und "none"',
    mIndex) then
  begin
    ARule.Fix := TDfmFixMode(mIndex);
  end;
end;

procedure ReadRuleExclude(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ARule: TDfmPropertyRule);
var
  mItem: Integer;
  mText: string;
begin
  if AValue.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(AValue, '"exclude" muss eine Liste von Glob-Mustern sein');
    Exit;
  end;
  for mItem := 0 to AValue.Count - 1 do
  begin
    if AReader.ExpectString(AValue[mItem], 'exclude', mText) then
    begin
      ARule.Exclude := ARule.Exclude + [mText];
    end;
  end;
end;

const
  cDfmRuleMembers: array[0..8] of TDfmRuleMember = ((Key: 'class'; Read: ReadRuleClass),
    (Key: 'property'; Read: ReadRuleProperty), (Key: 'value'; Read: ReadRuleValue),
    (Key: 'message'; Read: ReadRuleMessage), (Key: 'condition'; Read: ReadRuleCondition),
    (Key: 'severity'; Read: ReadRuleSeverity), (Key: 'includeDescendants'; Read: ReadRuleDescendants),
    (Key: 'fix'; Read: ReadRuleFix), (Key: 'exclude'; Read: ReadRuleExclude));

/// <summary>Eine Angabe einer Eigenschaftsregel; unbekannte Schlüssel werden gemeldet.</summary>
procedure ReadRuleMember(AReader: TConfigurationReader; ANode: TJsonNode; AIndex: Integer;
  var ARule: TDfmPropertyRule);
var
  mMember: TDfmRuleMember;
  mKey: string;
begin
  mKey := ANode.Keys[AIndex];
  for mMember in cDfmRuleMembers do
  begin
    if mMember.Key = mKey then
    begin
      mMember.Read(AReader, ANode[AIndex], mKey, ARule);
      Exit;
    end;
  end;
  AReader.Report(ANode.KeyStarts[AIndex], ANode.KeyStarts[AIndex] + Length(mKey) + 2,
    Format('Unbekannte Angabe "%s" in einer Eigenschaftsregel', [mKey]), False);
end;

/// <summary>Vollständig? Ohne class und property, oder ohne value bei einer Bedingung, die einen braucht,
/// wird die Regel gemeldet und verworfen.</summary>
function CheckRule(AReader: TConfigurationReader; ANode: TJsonNode; const ARule: TDfmPropertyRule): Boolean;
begin
  Result := (ARule.ClassName <> '') and (ARule.PropertyPath <> '');
  if not Result then
  begin
    AReader.ReportNode(ANode, 'Eine Eigenschaftsregel braucht "class" und "property"');
  end
  else if (ARule.Condition in [TDfmCondition.Equal, TDfmCondition.NotEqual, TDfmCondition.Contains,
    TDfmCondition.NotContains]) and (ARule.Value = '') then
  begin
    AReader.ReportNode(ANode, 'Diese Bedingung braucht einen "value"');
    Result := False;
  end;
end;

function ReadDfmPropertyRule(AReader: TConfigurationReader; ANode: TJsonNode; out ARule: TDfmPropertyRule): Boolean;
var
  mIndex: Integer;
begin
  ARule := Default(TDfmPropertyRule);
  ARule.Severity := TRuleSeverity.Warning;
  ARule.IncludeDescendants := True;
  ARule.Fix := TDfmFixMode.Prompt;
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    AReader.ReportNode(ANode, 'Eine Eigenschaftsregel muss ein Objekt sein: { "class": …, "property": …, ' +
      '"condition": … }');
    Exit(False);
  end;
  ARule.ClassRange := TTextRange.Create(AReader.PositionAt(ANode.Start), AReader.PositionAt(ANode.Start + 1));
  ARule.PropertyRange := ARule.ClassRange;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    ReadRuleMember(AReader, ANode, mIndex, ARule);
  end;
  Result := CheckRule(AReader, ANode, ARule);
end;

procedure ReadDfmPropertyRules(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mIndex: Integer;
  mRule: TDfmPropertyRule;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(ANode, '"dfmPropertyRules" muss eine Liste von Regeln sein');
    Exit;
  end;
  ASettings.DfmPropertyRules := nil;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    if ReadDfmPropertyRule(AReader, ANode[mIndex], mRule) then
    begin
      ASettings.DfmPropertyRules := ASettings.DfmPropertyRules + [mRule];
    end;
  end;
end;

procedure TakeDfmPropertyRules(const ASource: TServerSettings; const AFileText: string;
  var ATarget: TServerSettings);
begin
  ATarget.DfmPropertyRules := ASource.DfmPropertyRules;
end;

const
  cSections: array[0..4] of TConfigurationSection = (
    (Section: 'format'; Read: ReadFormat; Take: TakeFormat),
    (Section: 'compiler'; Read: ReadCompiler; Take: TakeCompiler),
    (Section: 'tests'; Read: ReadTests; Take: TakeTests),
    (Section: 'testUnits'; Read: ReadTestUnits; Take: TakeTestUnits),
    (Section: 'dfmPropertyRules'; Read: ReadDfmPropertyRules; Take: TakeDfmPropertyRules)
  );

function ProjectSections: TArray<TConfigurationSection>;
begin
  Result := SectionList(cSections);
end;

end.
