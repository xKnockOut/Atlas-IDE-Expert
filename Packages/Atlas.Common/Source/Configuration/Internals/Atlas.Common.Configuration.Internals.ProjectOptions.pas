unit Atlas.Common.Configuration.Internals.ProjectOptions;

// Abschnitte von atlas.json zum Projekt: format (Formatierung), compiler
// (Übersetzen beim Speichern), tests (betroffene Tests, Ordner der Vergleichsdateien), testUnits (Lage der
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
  Atlas.Common.Configuration.Internals.JsonTree,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TProjectOptionsText = (IndentSizeMustBeAWhole, MaxLineLengthMustBeAWhole, AllowedArePreserveLowerAnd,
    AllowedAreLfAndCrlf, AllowedArePreserveNewLineAnd, AllowedAreAutoDccOff, AffectedDepthMustBeAWhole,
    TestUnitsProjectMustBeA, AllowedAreContainsNotContainsEmpty, AllowedAreAutoPromptAnd, ExcludeMustBeAList,
    UnknownEntryInAProperty, APropertyRuleNeedsClass, ThisConditionNeedsAValue, APropertyRuleMustBe,
    DfmPropertyRulesMustBeAList, UnknownSeverityAllowedOffHint, ApprovalFolderMustNotBeEmpty);

const
  cTexts: array[TProjectOptionsText] of TAtlasText = (
    (De: '"indentSize" muss eine ganze Zahl von 1 bis 16 sein';
     En: '"indentSize" must be a whole number from 1 to 16'),
    (De: '"maxLineLength" muss eine ganze Zahl von 0 bis 1000 sein';
     En: '"maxLineLength" must be a whole number from 0 to 1000'),
    (De: 'Erlaubt sind "preserve", "lower" und "upper"'; En: 'Allowed are "preserve", "lower" and "upper"'),
    (De: 'Erlaubt sind "lf" und "crlf"'; En: 'Allowed are "lf" and "crlf"'),
    (De: 'Erlaubt sind "preserve", "newLine" und "sameLine"'; En: 'Allowed are "preserve", "newLine" and "sameLine"'),
    (De: 'Erlaubt sind "auto", "dcc" und "off"'; En: 'Allowed are "auto", "dcc" and "off"'),
    (De: '"affectedDepth" muss eine ganze Zahl von 1 bis 5 sein';
     En: '"affectedDepth" must be a whole number from 1 to 5'),
    (De: '"testUnits.project" muss eine .dproj oder .dpr sein'; En: '"testUnits.project" must be a .dproj or .dpr'),
    (De: 'Erlaubt sind "=", "<>", "contains", "notContains", "empty" und "notEmpty"';
     En: 'Allowed are "=", "<>", "contains", "notContains", "empty" and "notEmpty"'),
    (De: 'Erlaubt sind "auto", "prompt" und "none"'; En: 'Allowed are "auto", "prompt" and "none"'),
    (De: '"exclude" muss eine Liste von Glob-Mustern sein'; En: '"exclude" must be a list of glob patterns'),
    (De: 'Unbekannte Angabe "%s" in einer Eigenschaftsregel'; En: 'Unknown entry "%s" in a property rule'),
    (De: 'Eine Eigenschaftsregel braucht "class" und "property"'; En: 'A property rule needs "class" and "property"'),
    (De: 'Diese Bedingung braucht einen "value"'; En: 'This condition needs a "value"'),
    (De: 'Eine Eigenschaftsregel muss ein Objekt sein: { "class": …, "property": …, "condition": … }';
     En: 'A property rule must be an object: { "class": …, "property": …, "condition": … }'),
    (De: '"dfmPropertyRules" muss eine Liste von Regeln sein'; En: '"dfmPropertyRules" must be a list of rules'),
    (De: 'Unbekannter Schweregrad "%s"; erlaubt: off, hint, info, warning, error';
     En: 'Unknown severity "%s"; allowed: off, hint, info, warning, error'),
    (De: '"approvalFolder" darf nicht leer sein'; En: '"approvalFolder" must not be empty'));

{$SCOPEDENUMS OFF}

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
  if AReader.ExpectInteger(AValue, 1, 16, cTexts[TProjectOptionsText.IndentSizeMustBeAWhole].Text,
    ASettings.Formatting.IndentSize) then
  begin
    Include(ASettings.Formatting.Given, TFormatKey.IndentSize);
  end;
end;

procedure ReadMaxLineLength(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  if AReader.ExpectInteger(AValue, 0, 1000, cTexts[TProjectOptionsText.MaxLineLengthMustBeAWhole].Text,
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
  if AReader.ExpectOneOf(AValue, ['preserve', 'lower', 'upper'],
    cTexts[TProjectOptionsText.AllowedArePreserveLowerAnd].Text,
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
  if AReader.ExpectOneOf(AValue, ['lf', 'crlf'], cTexts[TProjectOptionsText.AllowedAreLfAndCrlf].Text, mIndex) then
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
    cTexts[TProjectOptionsText.AllowedArePreserveNewLineAnd].Text, mIndex) then
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
  // "ide" (Weg über eine Bau-IDE, entfernt mit #1904) bleibt still erlaubt und gilt als "off".
  if AReader.ExpectChoice(AValue, AKey, ['auto', 'dcc', 'off', 'ide'],
    cTexts[TProjectOptionsText.AllowedAreAutoDccOff].Text,
    mIndex) then
  begin
    if mIndex > Ord(High(TCompilerBackendSetting)) then
    begin
      mIndex := Ord(TCompilerBackendSetting.Off);
    end;
    ASettings.Compiler.Backend := TCompilerBackendSetting(mIndex);
  end;
end;

procedure IgnoreIdeCommand(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  // compiler.ideCommand gibt es seit #1904 nicht mehr; ein alter Eintrag wird ohne Meldung übergangen.
end;

const
  cCompilerMembers: array[0..1] of TMemberOption = ((Key: 'backend'; Read: ReadCompilerBackend),
    (Key: 'ideCommand'; Read: IgnoreIdeCommand));

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
  AReader.ExpectInteger(AValue, TTestsSettings.cMinAffectedDepth, TTestsSettings.cMaxAffectedDepth,
    cTexts[TProjectOptionsText.AffectedDepthMustBeAWhole].Text, ASettings.Tests.AffectedDepth);
end;

/// <summary>tests.approvalFolder (#1881): Ordner der Vergleichsdateien; leer bleibt die Vorgabe.</summary>
procedure ReadApprovalFolder(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mText: string;
begin
  if not AReader.ExpectString(AValue, AKey, mText) then
  begin
    Exit;
  end;
  if Trim(mText) = '' then
  begin
    AReader.ReportNode(AValue, cTexts[TProjectOptionsText.ApprovalFolderMustNotBeEmpty].Text);
  end
  else
  begin
    ASettings.Tests.ApprovalFolder := mText;
  end;
end;

const
  cTestsMembers: array[0..1] of TMemberOption = ((Key: 'affectedDepth'; Read: ReadAffectedDepth),
    (Key: 'approvalFolder'; Read: ReadApprovalFolder));

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
    AReader.ReportNode(AValue, cTexts[TProjectOptionsText.TestUnitsProjectMustBeA].Text);
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
    cTexts[TProjectOptionsText.AllowedAreContainsNotContainsEmpty].Text, mIndex) then
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
    AReader.ReportNode(AValue, cTexts[TProjectOptionsText.UnknownSeverityAllowedOffHint].Fmt([mText]));
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
  if AReader.ExpectChoice(AValue, AKey, ['prompt', 'auto', 'none'],
    cTexts[TProjectOptionsText.AllowedAreAutoPromptAnd].Text,
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
    AReader.ReportNode(AValue, cTexts[TProjectOptionsText.ExcludeMustBeAList].Text);
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
    cTexts[TProjectOptionsText.UnknownEntryInAProperty].Fmt([mKey]), False);
end;

/// <summary>Vollständig? Ohne class und property, oder ohne value bei einer Bedingung, die einen braucht,
/// wird die Regel gemeldet und verworfen.</summary>
function CheckRule(AReader: TConfigurationReader; ANode: TJsonNode; const ARule: TDfmPropertyRule): Boolean;
begin
  Result := (ARule.ClassName <> '') and (ARule.PropertyPath <> '');
  if not Result then
  begin
    AReader.ReportNode(ANode, cTexts[TProjectOptionsText.APropertyRuleNeedsClass].Text);
  end
  else if (ARule.Condition in [TDfmCondition.Equal, TDfmCondition.NotEqual, TDfmCondition.Contains,
    TDfmCondition.NotContains]) and (ARule.Value = '') then
  begin
    AReader.ReportNode(ANode, cTexts[TProjectOptionsText.ThisConditionNeedsAValue].Text);
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
    AReader.ReportNode(ANode, cTexts[TProjectOptionsText.APropertyRuleMustBe].Text);
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
    AReader.ReportNode(ANode, cTexts[TProjectOptionsText.DfmPropertyRulesMustBeAList].Text);
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Configuration.Internals.ProjectOptions', cTexts);

end.
