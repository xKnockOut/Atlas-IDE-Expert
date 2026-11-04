unit Atlas.Common.Configuration.Internals.RefactoringOptions;

// Abschnitt "refactoring" von atlas.json: Schalter je Refactoring
// (RefactoringFlags), Glieder mit festen Werten (RefactoringChoices; gespeichert
// in der Schreibweise der Tabelle) und Glieder mit eigener Prüfung (Präfixe,
// Gegenteile, Bezeichner).

interface

uses
  Atlas.Common.Configuration.Internals.Reader;

/// <summary>Abschnitte dieser Unit.</summary>
function RefactoringSections: TArray<TConfigurationSection>;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Internals.JsonTree;

function RefactoringFlags(var ARefactoring: TRefactoringSettings): TArray<TFlagOption>;
begin
  Result := [TFlagOption.Create('inlineVar', ARefactoring.InlineVar),
    TFlagOption.Create('changeSignature', ARefactoring.ChangeSignature),
    TFlagOption.Create('virtualOverload', ARefactoring.VirtualOverload),
    TFlagOption.Create('syncSignatures', ARefactoring.SyncSignatures),
    TFlagOption.Create('forwardDeclaration', ARefactoring.ForwardDeclaration),
    TFlagOption.Create('tryFinally', ARefactoring.TryFinally),
    TFlagOption.Create('classActions', ARefactoring.ClassActions),
    TFlagOption.Create('explicitType', ARefactoring.ExplicitType),
    TFlagOption.Create('compilerFixes', ARefactoring.CompilerFixes),
    TFlagOption.Create('missingUnit', ARefactoring.MissingUnit),
    TFlagOption.Create('disableWarning', ARefactoring.DisableWarning),
    TFlagOption.Create('disableWarningReason', ARefactoring.DisableWarningReason),
    TFlagOption.Create('extract', ARefactoring.Extract),
    TFlagOption.Create('completeCase', ARefactoring.CompleteCase),
    TFlagOption.Create('resolveWith', ARefactoring.ResolveWith),
    TFlagOption.Create('inline', ARefactoring.InlineCode),
    TFlagOption.Create('moveClass', ARefactoring.MoveClass),
    TFlagOption.Create('createMethod', ARefactoring.CreateMethod),
    TFlagOption.Create('constParameters', ARefactoring.ConstParameters),
    TFlagOption.Create('propertyFromAccessors', ARefactoring.PropertyFromAccessors),
    TFlagOption.Create('freeFields', ARefactoring.FreeFields),
    TFlagOption.Create('suggestConst', ARefactoring.SuggestConst),
    TFlagOption.Create('invertBoolean', ARefactoring.InvertBoolean),
    TFlagOption.Create('varBlock', ARefactoring.VarBlock),
    TFlagOption.Create('varBlockMerge', ARefactoring.VarBlockMerge),
    TFlagOption.Create('invertBooleanIncludeDfm', ARefactoring.InvertBooleanIncludeDfm),
    TFlagOption.Create('ifCase', ARefactoring.IfCase),
    TFlagOption.Create('conditions', ARefactoring.Conditions),
    TFlagOption.Create('conditionalExpression', ARefactoring.ConditionalExpression),
    TFlagOption.Create('nestedRoutine', ARefactoring.NestedRoutine),
    TFlagOption.Create('promoteVariable', ARefactoring.PromoteVariable),
    TFlagOption.Create('anonymousMethod', ARefactoring.AnonymousMethod),
    TFlagOption.Create('methodKind', ARefactoring.MethodKind),
    TFlagOption.Create('methodKindMarker', ARefactoring.MethodKindMarker),
    TFlagOption.Create('methodKindStatic', ARefactoring.MethodKindStatic),
    TFlagOption.Create('typeAlias', ARefactoring.TypeAlias),
    TFlagOption.Create('enumTables', ARefactoring.EnumTables),
    TFlagOption.Create('enumTablesResourceStrings', ARefactoring.EnumTablesResourceStrings),
    TFlagOption.Create('overloads', ARefactoring.Overloads),
    TFlagOption.Create('extractInterface', ARefactoring.ExtractInterface),
    TFlagOption.Create('extractSuperclass', ARefactoring.ExtractSuperclass),
    TFlagOption.Create('moveMember', ARefactoring.MoveMember),
    TFlagOption.Create('inlineAccessor', ARefactoring.InlineAccessor),
    TFlagOption.Create('inlineAccessorEqualityCheck', ARefactoring.InlineAccessorEqualityCheck),
    TFlagOption.Create('inlineAccessorBulk', ARefactoring.InlineAccessorBulk),
    TFlagOption.Create('inlineAccessorDiagnostic', ARefactoring.InlineAccessorDiagnostic),
    TFlagOption.Create('safeDelete', ARefactoring.SafeDelete),
    TFlagOption.Create('safeDeletePreviewWhenUnused', ARefactoring.SafeDeletePreviewWhenUnused)];
end;

function RefactoringChoices(var ARefactoring: TRefactoringSettings): TArray<TChoiceOption>;
begin
  Result := [TChoiceOption.Create('createMethodSection', ['private', 'protected', 'public'],
    ARefactoring.CreateMethodSection),
    TChoiceOption.Create('propertyFromAccessorsReplaceCalls', ['ask', 'always', 'never'],
    ARefactoring.PropertyFromAccessorsReplaceCalls),
    TChoiceOption.Create('propertyFromAccessorsSection', ['accessor', 'public', 'published'],
    ARefactoring.PropertyFromAccessorsSection),
    TChoiceOption.Create('propertyFromAccessorsHideAccessors', ['off', 'private', 'protected'],
    ARefactoring.PropertyFromAccessorsHideAccessors),
    TChoiceOption.Create('freeFieldsStyle', ['free', 'freeAndNil'], ARefactoring.FreeFieldsStyle),
    TChoiceOption.Create('varBlockSort', ['usage', 'alpha', 'none'], ARefactoring.VarBlockSort),
    TChoiceOption.Create('anonymousMethodDeferredCapture', ['forward', 'fields'],
    ARefactoring.AnonymousMethodDeferredCapture),
    TChoiceOption.Create('typeAliasScope', ['here', 'unit', 'project'], ARefactoring.TypeAliasScope),
    TChoiceOption.Create('extractSuperclassTarget', ['sameUnit', 'newUnit'], ARefactoring.ExtractSuperclassTarget),
    TChoiceOption.Create('extractSuperclassMethodMode', ['move', 'abstract'],
    ARefactoring.ExtractSuperclassMethodMode),
    TChoiceOption.Create('extractSuperclassRaiseVisibility', ['protected', 'strictProtected'],
    ARefactoring.ExtractSuperclassRaiseVisibility),
    TChoiceOption.Create('safeDeleteCascade', ['ask', 'always', 'never'], ARefactoring.SafeDeleteCascade),
    TChoiceOption.Create('safeDeleteIncludeOverrides', ['ask', 'always', 'never'],
    ARefactoring.SafeDeleteIncludeOverrides)];
end;

/// <summary>Einer von zwei Werten AValues (Groß-/Kleinschreibung egal); AFlag wird True beim Wert
/// AValues[ATrueIndex].</summary>
procedure ReadTwoWay(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  const AValues: array of string; ATrueIndex: Integer; var AFlag: Boolean);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoiceText(AValue, AKey, AValues, Format('"refactoring.%s" muss %s sein',
    [AKey, ChoiceText(AValues, 'oder')]), mIndex) then
  begin
    AFlag := mIndex = ATrueIndex;
  end;
end;

procedure ReadNewParameter(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadTwoWay(AReader, AValue, AKey, ['overload', 'updateCallers'], 0, ASettings.Refactoring.NewParameterOverload);
end;

procedure ReadUnitRenameFollowUp(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadTwoWay(AReader, AValue, AKey, ['ask', 'off'], 0, ASettings.Refactoring.UnitRenameFollowUp);
end;

procedure ReadCreateMethodCaret(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadTwoWay(AReader, AValue, AKey, ['call', 'body'], 1, ASettings.Refactoring.CreateMethodCaretInBody);
end;

procedure ReadAccessorPrefixes(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mItem: Integer;
  mText: string;
begin
  if AValue.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(AValue, '"refactoring.propertyFromAccessorsPrefixes" muss eine Liste von Präfixen sein');
    Exit;
  end;
  ASettings.Refactoring.PropertyFromAccessorsPrefixes := nil;
  for mItem := 0 to AValue.Count - 1 do
  begin
    if AReader.ExpectString(AValue[mItem], AKey, mText) and (Trim(mText) <> '') then
    begin
      ASettings.Refactoring.PropertyFromAccessorsPrefixes := ASettings.Refactoring.PropertyFromAccessorsPrefixes +
        [Trim(mText)];
    end;
  end;
end;

/// <summary>{"Hidden": "Visible"}: Name → Gegenteil, beide Richtungen.</summary>
procedure ReadAntonyms(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mItem: Integer;
  mText: string;
begin
  if AValue.Kind <> TJsonKind.Object_ then
  begin
    AReader.ReportNode(AValue, '"refactoring.invertBooleanAntonyms" muss ein Objekt wie {"Hidden": "Visible"} sein');
    Exit;
  end;
  ASettings.Refactoring.InvertBooleanAntonyms := nil;
  for mItem := 0 to AValue.Count - 1 do
  begin
    if not AReader.ExpectString(AValue[mItem], AKey, mText) then
    begin
      Continue;
    end;
    if IsValidIdent(AValue.Keys[mItem]) and IsValidIdent(Trim(mText)) then
    begin
      ASettings.Refactoring.InvertBooleanAntonyms := ASettings.Refactoring.InvertBooleanAntonyms +
        [AValue.Keys[mItem] + '=' + Trim(mText)];
    end
    else
    begin
      AReader.ReportNode(AValue[mItem], Format('"refactoring.invertBooleanAntonyms": "%s" und "%s" müssen ' +
        'Bezeichner sein', [AValue.Keys[mItem], mText]));
    end;
  end;
end;

/// <summary>Bezeichner (ohne Leerraum am Rand) in AIdent; sonst Fehler AMessage.</summary>
procedure ReadIdent(AReader: TConfigurationReader; AValue: TJsonNode; const AKey, AMessage: string;
  var AIdent: string);
var
  mText: string;
begin
  if not AReader.ExpectString(AValue, AKey, mText) then
  begin
    Exit;
  end;
  if IsValidIdent(Trim(mText)) then
  begin
    AIdent := Trim(mText);
  end
  else
  begin
    AReader.ReportNode(AValue, AMessage);
  end;
end;

procedure ReadFallbackPrefix(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadIdent(AReader, AValue, AKey, '"refactoring.invertBooleanFallbackPrefix" muss ein Bezeichner wie "Not" sein',
    ASettings.Refactoring.InvertBooleanFallbackPrefix);
end;

procedure ReadSuperclassSuffix(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadIdent(AReader, AValue, AKey, '"refactoring.extractSuperclassNameSuffix" muss ein Bezeichner wie "Base" sein',
    ASettings.Refactoring.ExtractSuperclassNameSuffix);
end;

const
  cRefactoringMembers: array[0..6] of TMemberOption = ((Key: 'newParameter'; Read: ReadNewParameter),
    (Key: 'unitRenameFollowUp'; Read: ReadUnitRenameFollowUp),
    (Key: 'createMethodCaret'; Read: ReadCreateMethodCaret),
    (Key: 'propertyFromAccessorsPrefixes'; Read: ReadAccessorPrefixes),
    (Key: 'invertBooleanAntonyms'; Read: ReadAntonyms),
    (Key: 'invertBooleanFallbackPrefix'; Read: ReadFallbackPrefix),
    (Key: 'extractSuperclassNameSuffix'; Read: ReadSuperclassSuffix));

procedure ReadRefactoring(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'refactoring', RefactoringFlags(ASettings.Refactoring),
    RefactoringChoices(ASettings.Refactoring), cRefactoringMembers, ASettings);
end;

procedure TakeRefactoring(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Refactoring := ASource.Refactoring;
end;

const
  cSections: array[0..0] of TConfigurationSection = (
    (Section: 'refactoring'; Read: ReadRefactoring; Take: TakeRefactoring)
  );

function RefactoringSections: TArray<TConfigurationSection>;
begin
  Result := SectionList(cSections);
end;

end.
