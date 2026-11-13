unit Atlas.Common.Configuration.Internals.RuleOptions;

// Abschnitte von atlas.json zu den Prüfregeln: rules, profile, profiles,
// overrides, excludeTests, testProfile, exclude, minConfidence, fix und
// metrics. Optionen einer Regel prüft eine Folge kleiner Prüfungen
// (cRuleOptionChecks) in fester Reihenfolge; die erste, die den Schlüssel
// übernimmt, beendet die Prüfung des Schlüssels.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Internals.JsonTree,
  Atlas.Common.Configuration.Internals.Reader;

/// <summary>Regeln aus einem Objekt { "regel": "warning" | { "severity": …, Optionen } } (rules,
/// profiles.*.rules, overrides[].rules); False, wenn ANode kein Objekt ist.</summary>
function ParseRules(AReader: TConfigurationReader; ANode: TJsonNode; const AName: string;
  out ARules: TArray<TRuleSetting>): Boolean;
/// <summary>Regeln der Editor-Ebene AEditor, je Regel-Id überschrieben von AFile.</summary>
function MergeRules(const AEditor, AFile: TArray<TRuleSetting>): TArray<TRuleSetting>;
/// <summary>Abschnitte dieser Unit.</summary>
function RuleSections: TArray<TConfigurationSection>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TRuleOptionsText = (KeywordsMustBeAList, AMarkerConsistsOfLetters, KindMustBeRoutineType, MustBeAListOf,
    NameMustBeANon, UnknownKeyAllowedNameKind, SymbolsMustBeAList, AnEntryOfSymbolsIs, MustBeAWholeNumber,
    MustBeTrueOrFalse, AllowedMustBeAList, MustBeAListOf2, TypeLevelMustBeCertainOr, KindsMayOnlyContainDeprecated,
    SearchPathsMustBeProjectAtlas, DefaultEncodingMustBeUTF8Unicode, PairsMustBeAList, PairsMustBeAList2,
    PairsMustBeAList3, RegisterPairsMustBeAList, RuleExpectsASeverityOr, ProfileExpectsANameOr,
    UnknownKeyAllowedEditorCli, UnknownKeyAllowedExtendsCategories, AProfileIsAnObject, UnknownKeyAllowedFilesRules,
    OverridesMustBeAList, APathRuleIsAn, ExcludeMustBeAList, AllowedAreLowMediumAnd, AllowedAreMediumAndHigh,
    UnknownSettingFix, MustBeAText, EntryOfSymbolsWithoutName, MustBeAnObjectRule, ProfilesMustBeAnObject,
    UnknownSeverityAllowedOffHint, UnknownSeverityAllowedOffHint2, PathRuleWithoutFiles);

const
  cTexts: array[TRuleOptionsText] of TAtlasText = (
    (De: '"keywords" muss eine Liste von Marken sein, z. B. ["TODO", "FIXME"]';
     En: '"keywords" must be a list of markers, e.g. ["TODO", "FIXME"]'),
    (De: 'Eine Marke besteht nur aus Buchstaben und ist nicht DONE, z. B. "HACK"';
     En: 'A marker consists of letters only and is not DONE, e.g. "HACK"'),
    (De: '"kind" muss routine, type, constant, field, property, enumValue oder identifier sein';
     En: '"kind" must be routine, type, constant, field, property, enumValue or identifier'),
    (De: '"%s" muss eine Liste von Texten sein'; En: '"%s" must be a list of texts'),
    (De: '"name" muss ein nicht leerer Text sein'; En: '"name" must be a non-empty text'),
    (De: 'Unbekannter Schlüssel "%s"; erlaubt: name, kind, message, replacement, severity, units, firstArgument, ' +
      'allowFirstArgument';
     En: 'Unknown key "%s"; allowed: name, kind, message, replacement, severity, units, firstArgument, ' +
      'allowFirstArgument'),
    (De: '"symbols" muss eine Liste von Objekten mit "name" sein';
     En: '"symbols" must be a list of objects with "name"'),
    (De: 'Ein Eintrag von "symbols" ist ein Objekt mit "name", z. B. {"name": "System.Writeln"}';
     En: 'An entry of "symbols" is an object with "name", e.g. {"name": "System.Writeln"}'),
    (De: '"%s" muss eine ganze Zahl ab %d sein'; En: '"%s" must be a whole number from %d'),
    (De: '"%s" muss true oder false sein'; En: '"%s" must be true or false'),
    (De: '"allowed" muss eine Liste von Texten sein'; En: '"allowed" must be a list of texts'),
    (De: '"%s" muss eine Liste von Zahlen sein'; En: '"%s" must be a list of numbers'),
    (De: '"typeLevel" muss "certain" oder "off" sein'; En: '"typeLevel" must be "certain" or "off"'),
    (De: '"kinds" darf nur "deprecated", "experimental", "platform" und "library" enthalten';
     En: '"kinds" may only contain "deprecated", "experimental", "platform" and "library"'),
    (De: '"searchPaths" muss "project", "atlas" oder "both" sein';
     En: '"searchPaths" must be "project", "atlas" or "both"'),
    (De: '"defaultEncoding" muss UTF8, Unicode, BigEndianUnicode, ANSI, ASCII, UTF7 oder Default sein';
     En: '"defaultEncoding" must be UTF8, Unicode, BigEndianUnicode, ANSI, ASCII, UTF7 or Default'),
    (De: '"pairs" muss eine Liste von Objekten mit "start", "commit" und "rollback" sein';
     En: '"pairs" must be a list of objects with "start", "commit" and "rollback"'),
    (De: '"pairs" muss eine Liste von Texten "Öffnen>Schließen" oder von Objekten mit "open" und "close" sein';
     En: '"pairs" must be a list of texts "Open>Close" or of objects with "open" and "close"'),
    (De: '"pairs" muss eine Liste von Objekten mit "open" und "close" sein';
     En: '"pairs" must be a list of objects with "open" and "close"'),
    (De: '"registerPairs" muss eine Liste von Objekten mit "open" und "close" sein';
     En: '"registerPairs" must be a list of objects with "open" and "close"'),
    (De: 'Regel erwartet einen Schweregrad oder ein Objekt mit "severity"';
     En: 'Rule expects a severity or an object with "severity"'),
    (De: '"profile" erwartet einen Namen oder { "editor": …, "cli": … }';
     En: '"profile" expects a name or { "editor": …, "cli": … }'),
    (De: 'Unbekannter Schlüssel "%s"; erlaubt: editor, cli'; En: 'Unknown key "%s"; allowed: editor, cli'),
    (De: 'Unbekannter Schlüssel "%s"; erlaubt: extends, categories, rules';
     En: 'Unknown key "%s"; allowed: extends, categories, rules'),
    (De: 'Ein Profil ist ein Objekt mit "extends", "categories" und "rules"';
     En: 'A profile is an object with "extends", "categories" and "rules"'),
    (De: 'Unbekannter Schlüssel "%s"; erlaubt: files, rules'; En: 'Unknown key "%s"; allowed: files, rules'),
    (De: '"overrides" muss eine Liste sein: [{ "files": ["Tests/**"], "rules": { … } }]';
     En: '"overrides" must be a list: [{ "files": ["Tests/**"], "rules": { … } }]'),
    (De: 'Eine Pfadregel ist ein Objekt mit "files" und "rules"';
     En: 'A path rule is an object with "files" and "rules"'),
    (De: '"exclude" muss eine Liste von Mustern sein'; En: '"exclude" must be a list of patterns'),
    (De: 'Erlaubt sind "low", "medium" und "high"'; En: 'Allowed are "low", "medium" and "high"'),
    (De: 'Erlaubt sind "medium" und "high"'; En: 'Allowed are "medium" and "high"'),
    (De: 'Unbekannte Einstellung "fix.%s"'; En: 'Unknown setting "fix.%s"'),
    (De: '"%s" muss ein Text sein'; En: '"%s" must be a text'),
    (De: 'Eintrag von "symbols" ohne "name"'; En: 'Entry of "symbols" without "name"'),
    (De: '"%s" muss ein Objekt sein: { "regel": "warning" }'; En: '"%s" must be an object: { "rule": "warning" }'),
    (De: '"profiles" muss ein Objekt sein: { "name": { "extends": …, "rules": … } }';
     En: '"profiles" must be an object: { "name": { "extends": …, "rules": … } }'),
    (De: 'Unbekannter Schweregrad; erlaubt: off, hint, info, warning, error';
     En: 'Unknown severity; allowed: off, hint, info, warning, error'),
    (De: 'Unbekannter Schweregrad "%s"; erlaubt: off, hint, info, warning, error';
     En: 'Unknown severity "%s"; allowed: off, hint, info, warning, error'),
    (De: 'Pfadregel ohne "files"'; En: 'Path rule without "files"'));

{$SCOPEDENUMS OFF}

const
  /// <summary>Optionen von Prüfregeln, die true oder false sein müssen (#909).</summary>
  cBooleanRuleOptions: array[0..24] of string = ('allowCommented', 'requireElse', 'ignoreStrings', 'ignoreComments',
    'includeRecords', 'includeFormVariables', 'checkUses', 'allowLazyInit', 'checkRound', 'includeFields',
    'allowSingleLineExit', 'allowSameLine', 'allowComments', 'onlyAfterRaisingCode', 'allowInProgram', 'unitLevel',
    'testsCountAsUse', 'stringLiteralsCountAsUse', 'allowShareMem', 'ignoreOverrides', 'requirePublic',
    'checkReturns', 'checkFree', 'allowFirstElement', 'implementation');
  /// <summary>Optionen von Prüfregeln, die eine Liste von Texten sein müssen (#909).</summary>
  cStringListRuleOptions: array[0..36] of string = ('countNames', 'mutatingMethods', 'ignoreMethods', 'ignoreTypes',
    'methods', 'allowIn', 'functions', 'sources', 'ignore', 'assertPatterns', 'selfRegistering', 'swallow', 'calls',
    'allowTables', 'types', 'allowProperties', 'threadSafeTypes', 'switchConstants', 'namePatterns', 'kinds',
    'statements', 'disabledChecks', 'componentClasses', 'visibilities', 'memberKinds', 'projectKinds',
    'keepAttributes', 'keepPatterns', 'allowUnits', 'allow', 'allowAttributes', 'allowTypes',
    'formatMethods', 'unitKinds', 'keep', 'pureFunctions', 'factories');
  /// <summary>Erlaubte Einträge von kinds bei deprecated-symbol (#1018).</summary>
  cDeprecationKinds: array[0..3] of string = ('deprecated', 'experimental', 'platform', 'library');
  /// <summary>Erlaubte Arten in symbols von forbidden-symbol (#1133); wie TForbiddenSymbolRule.TryParseKind.</summary>
  cForbiddenSymbolKinds: array[0..6] of string = ('routine', 'type', 'constant', 'field', 'property', 'enumValue',
    'identifier');
  /// <summary>Optionen von Prüfregeln, die eine Liste von Zahlen sein müssen (#937).</summary>
  cNumberListRuleOptions: array[0..0] of string = ('allowed');
  /// <summary>Optionen von Prüfregeln, die ein Text sein müssen (#926).</summary>
  cStringRuleOptions: array[0..10] of string = ('template', 'replacement', 'wrapper', 'okMarker', 'searchPaths',
    'defaultEncoding', 'scope', 'local', 'field', 'parameter', 'constant');
  /// <summary>Kodierungen der Korrektur von load-without-encoding (#1061).</summary>
  cLoadEncodings: array[0..6] of string = ('UTF8', 'Unicode', 'BigEndianUnicode', 'ANSI', 'ASCII', 'UTF7',
    'Default');
  /// <summary>Glieder eines Eintrags von symbols (forbidden-symbol), die eine Liste von Texten sind.</summary>
  cSymbolListMembers: array[0..2] of string = ('units', 'firstArgument', 'allowFirstArgument');

type
  /// <summary>Ganzzahlige Option einer Regel mit Untergrenze.</summary>
  TLimitOption = record
    Key: string;
    Min: Integer;
  end;

const
  /// <summary>max: Grenzwert der Metrik-Regeln (#66); minLines: commented-out-code (#942); min: string-if-chain
  /// (#1066) und prefer-case (#646); minRecordSize: managed-param-without-const (#975); maxSleepMs:
  /// blocking-call-in-main-thread (#959); maxLiteralLength: pos-arguments-swapped (#1045).</summary>
  cLimitOptions: array[0..5] of TLimitOption = ((Key: 'max'; Min: 1), (Key: 'minLines'; Min: 1),
    (Key: 'min'; Min: 2), (Key: 'minRecordSize'; Min: 1), (Key: 'maxSleepMs'; Min: 0),
    (Key: 'maxLiteralLength'; Min: 1));

/// <summary>Array aus Objekten, die alle Texte AKeys haben: "open" und "close" (pair-without-finally, #930),
/// "start", "commit" und "rollback" (transaction-without-rollback, #965).</summary>
function IsPairObject(AItem: TJsonNode; const AKeys: array of string): Boolean;
var
  mInner, mFound: Integer;
begin
  Result := AItem.Kind = TJsonKind.Object_;
  if Result then
  begin
    mFound := 0;
    for mInner := 0 to AItem.Count - 1 do
    begin
      if (IndexStr(AItem.Keys[mInner], AKeys) >= 0) and (AItem[mInner].Kind = TJsonKind.String_) then
      begin
        Inc(mFound);
      end;
    end;
    Result := mFound = Length(AKeys);
  end;
end;

function IsPairList(ANode: TJsonNode; const AKeys: array of string): Boolean;
var
  mIndex: Integer;
begin
  Result := ANode.Kind = TJsonKind.Array_;
  if Result then
  begin
    for mIndex := 0 to ANode.Count - 1 do
    begin
      if not IsPairObject(ANode[mIndex], AKeys) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

/// <summary>Text "Öffnen>Schließen" mit beiden Teilen.</summary>
function IsArrowPair(const AText: string): Boolean;
var
  mArrow: Integer;
begin
  mArrow := Pos('>', AText);
  Result := (mArrow > 1) and (mArrow < Length(AText));
end;

/// <summary>Array aus Texten "Öffnen>Schließen" oder Objekten mit "open" und "close" (handle-leak, #1088).</summary>
function IsArrowPairList(ANode: TJsonNode): Boolean;
var
  mIndex: Integer;
  mItem: TJsonNode;
begin
  Result := ANode.Kind = TJsonKind.Array_;
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mItem := ANode[mIndex];
    if mItem.Kind = TJsonKind.String_ then
    begin
      Result := IsArrowPair(mItem.Value);
    end
    else
    begin
      Result := IsPairObject(mItem, ['open', 'close']);
    end;
    if not Result then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Array, dessen Einträge alle den Typ AKind haben.</summary>
function IsListOf(ANode: TJsonNode; AKind: TJsonKind): Boolean;
var
  mIndex: Integer;
begin
  Result := ANode.Kind = TJsonKind.Array_;
  if Result then
  begin
    for mIndex := 0 to ANode.Count - 1 do
    begin
      if ANode[mIndex].Kind <> AKind then
      begin
        Exit(False);
      end;
    end;
  end;
end;

function IsStringList(ANode: TJsonNode): Boolean;
begin
  Result := IsListOf(ANode, TJsonKind.String_);
end;

/// <summary>Liste von Texten, jeder aus AAllowed.</summary>
function IsStringListOf(ANode: TJsonNode; const AAllowed: array of string): Boolean;
var
  mIndex: Integer;
begin
  Result := IsStringList(ANode);
  if Result then
  begin
    for mIndex := 0 to ANode.Count - 1 do
    begin
      if IndexStr(ANode[mIndex].Value, AAllowed) < 0 then
      begin
        Exit(False);
      end;
    end;
  end;
end;

/// <summary>Ganze Zahl ab AMin?</summary>
function IsIntegerFrom(ANode: TJsonNode; AMin: Integer): Boolean;
var
  mValue: Integer;
begin
  Result := (ANode.Kind = TJsonKind.Number) and TryStrToInt(ANode.Value, mValue) and (mValue >= AMin);
end;

/// <summary>Besteht die Marke nur aus Buchstaben?</summary>
function IsLetters(const AText: string): Boolean;
var
  mChar: Char;
begin
  for mChar in AText do
  begin
    if not CharInSet(mChar, ['A'..'Z', 'a'..'z']) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Marken der Regel todo-comment (#68); die Regel und get_todos lesen sie aus den Optionen.</summary>
procedure CheckTodoKeywords(AReader: TConfigurationReader; ANode: TJsonNode);
var
  mIndex: Integer;
  mKeyword: string;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(ANode, cTexts[TRuleOptionsText.KeywordsMustBeAList].Text);
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mKeyword := '';
    if ANode[mIndex].Kind = TJsonKind.String_ then
    begin
      mKeyword := Trim(ANode[mIndex].Value);
    end;
    if (mKeyword = '') or SameText(mKeyword, 'DONE') or not IsLetters(mKeyword) then
    begin
      AReader.ReportNode(ANode[mIndex], cTexts[TRuleOptionsText.AMarkerConsistsOfLetters].Text);
    end;
  end;
end;

/// <summary>Prüft ein bekanntes Glied eines Eintrags von symbols außer "name"; False für ein unbekanntes.</summary>
function CheckSymbolValue(AReader: TConfigurationReader; const AKey: string; AValue: TJsonNode): Boolean;
var
  mSeverity: TRuleSeverity;
  mValid: Boolean;
  mMessage: string;
begin
  Result := True;
  if AKey = 'kind' then
  begin
    mValid := (AValue.Kind = TJsonKind.String_) and (IndexText(AValue.Value, cForbiddenSymbolKinds) >= 0);
    mMessage := cTexts[TRuleOptionsText.KindMustBeRoutineType].Text;
  end
  else if MatchStr(AKey, ['message', 'replacement']) then
  begin
    mValid := AValue.Kind = TJsonKind.String_;
    mMessage := cTexts[TRuleOptionsText.MustBeAText].Fmt([AKey]);
  end
  else if AKey = 'severity' then
  begin
    mValid := (AValue.Kind = TJsonKind.String_) and TryParseRuleSeverity(AValue.Value, mSeverity);
    mMessage := cTexts[TRuleOptionsText.UnknownSeverityAllowedOffHint].Text;
  end
  else
  begin
    Result := MatchStr(AKey, cSymbolListMembers);
    mValid := not Result or IsStringList(AValue);
    mMessage := cTexts[TRuleOptionsText.MustBeAListOf].Fmt([AKey]);
  end;
  if not mValid then
  begin
    AReader.ReportNode(AValue, mMessage);
  end;
end;

/// <summary>Prüft das Glied AKey eines Eintrags von symbols; True für "name".</summary>
function CheckSymbolMember(AReader: TConfigurationReader; const AKey: string; AValue: TJsonNode): Boolean;
begin
  Result := AKey = 'name';
  if Result then
  begin
    if (AValue.Kind <> TJsonKind.String_) or (Trim(AValue.Value) = '') then
    begin
      AReader.ReportNode(AValue, cTexts[TRuleOptionsText.NameMustBeANon].Text);
    end;
  end
  else if not CheckSymbolValue(AReader, AKey, AValue) then
  begin
    AReader.ReportNode(AValue, cTexts[TRuleOptionsText.UnknownKeyAllowedNameKind].Fmt([AKey]));
  end;
end;

/// <summary>Verbotene Symbole von forbidden-symbol (#1133).</summary>
procedure CheckForbiddenSymbols(AReader: TConfigurationReader; ANode: TJsonNode);
var
  mIndex, mInner: Integer;
  mItem: TJsonNode;
  mHasName: Boolean;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(ANode, cTexts[TRuleOptionsText.SymbolsMustBeAList].Text);
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mItem := ANode[mIndex];
    if mItem.Kind <> TJsonKind.Object_ then
    begin
      AReader.ReportNode(mItem, cTexts[TRuleOptionsText.AnEntryOfSymbolsIs].Text);
      Continue;
    end;
    mHasName := False;
    for mInner := 0 to mItem.Count - 1 do
    begin
      if CheckSymbolMember(AReader, mItem.Keys[mInner], mItem[mInner]) then
      begin
        mHasName := True;
      end;
    end;
    if not mHasName then
    begin
      AReader.ReportNode(mItem, cTexts[TRuleOptionsText.EntryOfSymbolsWithoutName].Text);
    end;
  end;
end;

type
  /// <summary>Prüft die Option AKey einer Regel; True, wenn sie den Schlüssel übernommen hat (gemeldet oder
  /// ganz geprüft), dann entfallen die folgenden Prüfungen.</summary>
  TRuleOptionCheck = function(AReader: TConfigurationReader; const ARuleId, AKey: string;
    AValue: TJsonNode): Boolean;

function CheckLimit(AReader: TConfigurationReader; const ARuleId, AKey: string; AValue: TJsonNode): Boolean;
var
  mLimit: TLimitOption;
begin
  for mLimit in cLimitOptions do
  begin
    if mLimit.Key = AKey then
    begin
      if not IsIntegerFrom(AValue, mLimit.Min) then
      begin
        AReader.ReportNode(AValue, cTexts[TRuleOptionsText.MustBeAWholeNumber].Fmt([AKey, mLimit.Min]));
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

function CheckKeywords(AReader: TConfigurationReader; const ARuleId, AKey: string; AValue: TJsonNode): Boolean;
begin
  Result := AKey = 'keywords';
  if Result then
  begin
    CheckTodoKeywords(AReader, AValue);
  end;
end;

/// <summary>Schalter der Regeln (#909), z. B. allowCommented von empty-statement.</summary>
function CheckBooleanOption(AReader: TConfigurationReader; const ARuleId, AKey: string;
  AValue: TJsonNode): Boolean;
begin
  Result := (IndexStr(AKey, cBooleanRuleOptions) >= 0) and (AValue.Kind <> TJsonKind.Boolean_);
  if Result then
  begin
    AReader.ReportNode(AValue, cTexts[TRuleOptionsText.MustBeTrueOrFalse].Fmt([AKey]));
  end;
end;

function CheckStringListOption(AReader: TConfigurationReader; const ARuleId, AKey: string;
  AValue: TJsonNode): Boolean;
begin
  Result := (IndexStr(AKey, cStringListRuleOptions) >= 0) and not IsStringList(AValue);
  if Result then
  begin
    AReader.ReportNode(AValue, cTexts[TRuleOptionsText.MustBeAListOf].Fmt([AKey]));
  end;
end;

/// <summary>allowed von inherited-wrong-method (#1050) sind Paare "Methode>geerbte Methode", sonst Zahlen.</summary>
function CheckInheritedAllowed(AReader: TConfigurationReader; const ARuleId, AKey: string;
  AValue: TJsonNode): Boolean;
begin
  Result := (AKey = 'allowed') and (ARuleId = 'inherited-wrong-method');
  if Result and not IsStringList(AValue) then
  begin
    AReader.ReportNode(AValue, cTexts[TRuleOptionsText.AllowedMustBeAList].Text);
  end;
end;

function CheckNumberListOption(AReader: TConfigurationReader; const ARuleId, AKey: string;
  AValue: TJsonNode): Boolean;
begin
  Result := (IndexStr(AKey, cNumberListRuleOptions) >= 0) and not IsListOf(AValue, TJsonKind.Number);
  if Result then
  begin
    AReader.ReportNode(AValue, cTexts[TRuleOptionsText.MustBeAListOf2].Fmt([AKey]));
  end;
end;

function CheckStringOption(AReader: TConfigurationReader; const ARuleId, AKey: string;
  AValue: TJsonNode): Boolean;
begin
  Result := (IndexStr(AKey, cStringRuleOptions) >= 0) and (AValue.Kind <> TJsonKind.String_);
  if Result then
  begin
    AReader.ReportNode(AValue, cTexts[TRuleOptionsText.MustBeAText].Fmt([AKey]));
  end;
end;

/// <summary>Stufe T der Gruppe „Compiler vorab“ (#1024).</summary>
function CheckTypeLevel(AReader: TConfigurationReader; const ARuleId, AKey: string; AValue: TJsonNode): Boolean;
begin
  Result := (AKey = 'typeLevel') and
    ((AValue.Kind <> TJsonKind.String_) or (IndexStr(AValue.Value, ['certain', 'off']) < 0));
  if Result then
  begin
    AReader.ReportNode(AValue, cTexts[TRuleOptionsText.TypeLevelMustBeCertainOr].Text);
  end;
end;

/// <summary>Arten von deprecated-symbol (#1018).</summary>
function CheckDeprecationKinds(AReader: TConfigurationReader; const ARuleId, AKey: string;
  AValue: TJsonNode): Boolean;
begin
  Result := (AKey = 'kinds') and (ARuleId = 'deprecated-symbol') and not IsStringListOf(AValue, cDeprecationKinds);
  if Result then
  begin
    AReader.ReportNode(AValue, cTexts[TRuleOptionsText.KindsMayOnlyContainDeprecated].Text);
  end;
end;

function CheckSymbols(AReader: TConfigurationReader; const ARuleId, AKey: string; AValue: TJsonNode): Boolean;
begin
  Result := (AKey = 'symbols') and (ARuleId = 'forbidden-symbol');
  if Result then
  begin
    CheckForbiddenSymbols(AReader, AValue);
  end;
end;

/// <summary>Suchquelle von uses-unit-not-found (#1016).</summary>
function CheckSearchPaths(AReader: TConfigurationReader; const ARuleId, AKey: string;
  AValue: TJsonNode): Boolean;
begin
  Result := (AKey = 'searchPaths') and (IndexStr(AValue.Value, ['project', 'atlas', 'both']) < 0);
  if Result then
  begin
    AReader.ReportNode(AValue, cTexts[TRuleOptionsText.SearchPathsMustBeProjectAtlas].Text);
  end;
end;

/// <summary>Kodierung der Korrektur von load-without-encoding (#1061).</summary>
function CheckDefaultEncoding(AReader: TConfigurationReader; const ARuleId, AKey: string;
  AValue: TJsonNode): Boolean;
begin
  Result := (AKey = 'defaultEncoding') and (IndexText(AValue.Value, cLoadEncodings) < 0);
  if Result then
  begin
    AReader.ReportNode(AValue,
      cTexts[TRuleOptionsText.DefaultEncodingMustBeUTF8Unicode].Text);
  end;
end;

/// <summary>Paare: transaction-without-rollback (#965), handle-leak (#1088, auch als Text
/// "Öffnen>Schließen"), sonst "open" und "close".</summary>
function CheckPairs(AReader: TConfigurationReader; const ARuleId, AKey: string; AValue: TJsonNode): Boolean;
begin
  Result := AKey = 'pairs';
  if not Result then
  begin
    Exit;
  end;
  if ARuleId = 'transaction-without-rollback' then
  begin
    if not IsPairList(AValue, ['start', 'commit', 'rollback']) then
    begin
      AReader.ReportNode(AValue, cTexts[TRuleOptionsText.PairsMustBeAList].Text);
    end;
  end
  else if ARuleId = 'handle-leak' then
  begin
    if not IsArrowPairList(AValue) then
    begin
      AReader.ReportNode(AValue, cTexts[TRuleOptionsText.PairsMustBeAList2].Text);
    end;
  end
  else if not IsPairList(AValue, ['open', 'close']) then
  begin
    AReader.ReportNode(AValue, cTexts[TRuleOptionsText.PairsMustBeAList3].Text);
  end;
end;

/// <summary>Paare von ota-notifier-not-removed (#944).</summary>
function CheckRegisterPairs(AReader: TConfigurationReader; const ARuleId, AKey: string;
  AValue: TJsonNode): Boolean;
begin
  Result := (AKey = 'registerPairs') and not IsPairList(AValue, ['open', 'close']);
  if Result then
  begin
    AReader.ReportNode(AValue, cTexts[TRuleOptionsText.RegisterPairsMustBeAList].Text);
  end;
end;

const
  /// <summary>Reihenfolge zählt: Die Typprüfung der Listen kommt vor den Werten (kinds, searchPaths,
  /// defaultEncoding), allowed von inherited-wrong-method vor der Zahlenliste.</summary>
  cRuleOptionChecks: array[0..13] of TRuleOptionCheck = (CheckLimit, CheckKeywords, CheckBooleanOption,
    CheckStringListOption, CheckInheritedAllowed, CheckNumberListOption, CheckStringOption, CheckTypeLevel,
    CheckDeprecationKinds, CheckSymbols, CheckSearchPaths, CheckDefaultEncoding, CheckPairs, CheckRegisterPairs);

procedure CheckRuleOption(AReader: TConfigurationReader; const ARuleId, AKey: string; AValue: TJsonNode);
var
  mCheck: TRuleOptionCheck;
begin
  for mCheck in cRuleOptionChecks do
  begin
    if mCheck(AReader, ARuleId, AKey, AValue) then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Regel als Objekt mit "severity" und Optionen.</summary>
procedure ReadRuleObject(AReader: TConfigurationReader; AValue: TJsonNode; var ARule: TRuleSetting);
var
  mInner: Integer;
  mSeverity: TRuleSeverity;
begin
  for mInner := 0 to AValue.Count - 1 do
  begin
    if AValue.Keys[mInner] <> 'severity' then
    begin
      CheckRuleOption(AReader, ARule.Id, AValue.Keys[mInner], AValue[mInner]);
    end
    else if (AValue[mInner].Kind = TJsonKind.String_) and TryParseRuleSeverity(AValue[mInner].Value, mSeverity) then
    begin
      ARule.Severity := mSeverity;
    end
    else
    begin
      AReader.ReportNode(AValue[mInner], cTexts[TRuleOptionsText.UnknownSeverityAllowedOffHint].Text);
    end;
  end;
  ARule.Options := AReader.NodeText(AValue);
end;

/// <summary>Eine Regel; False, wenn sie wegen eines Fehlers entfällt.</summary>
function ReadRule(AReader: TConfigurationReader; const AKey: string; AValue: TJsonNode;
  out ARule: TRuleSetting): Boolean;
var
  mSeverity: TRuleSeverity;
begin
  // Frühere Kennungen gelten für die umbenannte Regel (#910).
  ARule.Id := TRuleIdAliases.Current(AKey);
  ARule.Severity := TRuleSeverity.Default;
  ARule.Options := '';
  Result := AValue.Kind in [TJsonKind.String_, TJsonKind.Object_];
  if not Result then
  begin
    AReader.ReportNode(AValue, cTexts[TRuleOptionsText.RuleExpectsASeverityOr].Text);
  end
  else if AValue.Kind = TJsonKind.Object_ then
  begin
    ReadRuleObject(AReader, AValue, ARule);
  end
  else
  begin
    Result := TryParseRuleSeverity(AValue.Value, mSeverity);
    ARule.Severity := mSeverity;
    if not Result then
    begin
      AReader.ReportNode(AValue, cTexts[TRuleOptionsText.UnknownSeverityAllowedOffHint2].Fmt([AValue.Value]));
    end;
  end;
end;

function ParseRules(AReader: TConfigurationReader; ANode: TJsonNode; const AName: string;
  out ARules: TArray<TRuleSetting>): Boolean;
var
  mIndex: Integer;
  mRule: TRuleSetting;
begin
  ARules := nil;
  Result := ANode.Kind = TJsonKind.Object_;
  if not Result then
  begin
    AReader.ReportNode(ANode, cTexts[TRuleOptionsText.MustBeAnObjectRule].Fmt([AName]));
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    if ReadRule(AReader, ANode.Keys[mIndex], ANode[mIndex], mRule) then
    begin
      ARules := ARules + [mRule];
    end;
  end;
end;

function MergeRules(const AEditor, AFile: TArray<TRuleSetting>): TArray<TRuleSetting>;
var
  mEditorRule, mFileRule: TRuleSetting;
  mOverridden: Boolean;
begin
  Result := nil;
  for mEditorRule in AEditor do
  begin
    mOverridden := False;
    for mFileRule in AFile do
    begin
      if SameText(mFileRule.Id, mEditorRule.Id) then
      begin
        mOverridden := True;
      end;
    end;
    if not mOverridden then
    begin
      Result := Result + [mEditorRule];
    end;
  end;
  Result := Result + AFile;
end;

{ rules }

procedure ReadRules(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mRules: TArray<TRuleSetting>;
begin
  if ParseRules(AReader, ANode, 'rules', mRules) then
  begin
    ASettings.Rules := mRules;
  end;
end;

procedure TakeRules(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Rules := MergeRules(ATarget.Rules, ASource.Rules);
end;

{ profile }

procedure ReadProfile(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mIndex: Integer;
  mText: string;
begin
  AReader.ProfileNode := ANode;
  // "profile": "fast" oder { "editor": "fast", "cli": "strict" }
  if ANode.Kind = TJsonKind.String_ then
  begin
    ASettings.Profile := ANode.Value;
    Exit;
  end;
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    AReader.ReportNode(ANode, cTexts[TRuleOptionsText.ProfileExpectsANameOr].Text);
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    if ANode.Keys[mIndex] = 'editor' then
    begin
      if AReader.ExpectString(ANode[mIndex], 'profile.editor', mText) then
      begin
        ASettings.Profile := mText;
      end;
    end
    else if ANode.Keys[mIndex] = 'cli' then
    begin
      if AReader.ExpectString(ANode[mIndex], 'profile.cli', mText) then
      begin
        ASettings.CliProfile := mText;
      end;
    end
    else
    begin
      AReader.ReportNode(ANode[mIndex], cTexts[TRuleOptionsText.UnknownKeyAllowedEditorCli].Fmt([ANode.Keys[mIndex]]));
    end;
  end;
end;

procedure TakeProfile(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Profile := ASource.Profile;
  ATarget.CliProfile := ASource.CliProfile;
end;

{ profiles }

function ReadOneProfile(AReader: TConfigurationReader; const AName: string; AValue: TJsonNode): TRuleProfile;
var
  mInner: Integer;
  mKey: string;
begin
  Result := Default(TRuleProfile);
  Result.Name := AName;
  for mInner := 0 to AValue.Count - 1 do
  begin
    mKey := AValue.Keys[mInner];
    if mKey = 'extends' then
    begin
      AReader.ExpectString(AValue[mInner], 'extends', Result.Extends);
    end
    else if mKey = 'categories' then
    begin
      AReader.ParseStrings(AValue[mInner], 'categories', Result.Categories);
    end
    else if mKey = 'rules' then
    begin
      ParseRules(AReader, AValue[mInner], 'rules', Result.Rules);
    end
    else
    begin
      AReader.ReportNode(AValue[mInner], cTexts[TRuleOptionsText.UnknownKeyAllowedExtendsCategories].Fmt([mKey]));
    end;
  end;
end;

procedure ReadProfiles(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mIndex: Integer;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    AReader.ReportNode(ANode, cTexts[TRuleOptionsText.ProfilesMustBeAnObject].Text);
    Exit;
  end;
  ASettings.Profiles := nil;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    if ANode[mIndex].Kind <> TJsonKind.Object_ then
    begin
      AReader.ReportNode(ANode[mIndex], cTexts[TRuleOptionsText.AProfileIsAnObject].Text);
    end
    else
    begin
      ASettings.Profiles := ASettings.Profiles + [ReadOneProfile(AReader, ANode.Keys[mIndex], ANode[mIndex])];
    end;
  end;
end;

procedure TakeProfiles(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Profiles := ASource.Profiles;
end;

{ overrides }

function ReadOverride(AReader: TConfigurationReader; AValue: TJsonNode): TPathOverride;
var
  mInner: Integer;
  mKey: string;
begin
  Result := Default(TPathOverride);
  for mInner := 0 to AValue.Count - 1 do
  begin
    mKey := AValue.Keys[mInner];
    if mKey = 'files' then
    begin
      AReader.ParseStrings(AValue[mInner], 'files', Result.Files);
    end
    else if mKey = 'rules' then
    begin
      ParseRules(AReader, AValue[mInner], 'rules', Result.Rules);
    end
    else
    begin
      AReader.ReportNode(AValue[mInner], cTexts[TRuleOptionsText.UnknownKeyAllowedFilesRules].Fmt([mKey]));
    end;
  end;
end;

procedure ReadOverrides(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mIndex: Integer;
  mValue: TJsonNode;
  mItem: TPathOverride;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(ANode, cTexts[TRuleOptionsText.OverridesMustBeAList].Text);
    Exit;
  end;
  ASettings.Overrides := nil;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mValue := ANode[mIndex];
    if mValue.Kind <> TJsonKind.Object_ then
    begin
      AReader.ReportNode(mValue, cTexts[TRuleOptionsText.APathRuleIsAn].Text);
      Continue;
    end;
    mItem := ReadOverride(AReader, mValue);
    if mItem.Files = nil then
    begin
      AReader.ReportNode(mValue, cTexts[TRuleOptionsText.PathRuleWithoutFiles].Text);
    end
    else
    begin
      ASettings.Overrides := ASettings.Overrides + [mItem];
    end;
  end;
end;

procedure TakeOverrides(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Overrides := ASource.Overrides;
end;

{ excludeTests, testProfile, exclude }

procedure ReadExcludeTests(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ExpectBoolean(ANode, 'excludeTests', ASettings.ExcludeTests);
end;

procedure TakeExcludeTests(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.ExcludeTests := ASource.ExcludeTests;
end;

procedure ReadTestProfile(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mText: string;
begin
  if not AReader.ExpectString(ANode, 'testProfile', mText) then
  begin
    Exit;
  end;
  if ASettings.IsKnownProfile(mText) or (mText = '') then
  begin
    ASettings.TestProfile := mText;
  end
  else
  begin
    AReader.TestProfileNode := ANode;
  end;
end;

procedure TakeTestProfile(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.TestProfile := ASource.TestProfile;
end;

procedure ReadExclude(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mIndex: Integer;
  mValue: string;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(ANode, cTexts[TRuleOptionsText.ExcludeMustBeAList].Text);
    Exit;
  end;
  ASettings.Exclude := nil;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    if AReader.ExpectString(ANode[mIndex], 'exclude', mValue) then
    begin
      ASettings.Exclude := ASettings.Exclude + [mValue];
    end;
  end;
end;

procedure TakeExclude(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Exclude := ASource.Exclude;
end;

{ minConfidence, fix, metrics }

procedure ReadMinConfidence(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mText: string;
begin
  if not AReader.ExpectString(ANode, 'minConfidence', mText) then
  begin
    Exit;
  end;
  if TryParseRuleConfidence(mText, ASettings.MinConfidence) then
  begin
    ASettings.MinConfidenceGiven := True;
  end
  else
  begin
    AReader.ReportNode(ANode, cTexts[TRuleOptionsText.AllowedAreLowMediumAnd].Text);
  end;
end;

procedure TakeMinConfidence(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.MinConfidence := ASource.MinConfidence;
  ATarget.MinConfidenceGiven := ASource.MinConfidenceGiven;
end;

procedure ReadFixMinConfidence(AReader: TConfigurationReader; AValue: TJsonNode; var ASettings: TServerSettings);
var
  mText: string;
  mConfidence: TRuleConfidence;
begin
  // Sammelkorrekturen (#1352) nie unter mittlerer Konfidenz.
  if not AReader.ExpectString(AValue, 'fix.minConfidence', mText) then
  begin
    Exit;
  end;
  if TryParseRuleConfidence(mText, mConfidence) and (mConfidence <> TRuleConfidence.Low) then
  begin
    ASettings.FixMinConfidence := mConfidence;
  end
  else
  begin
    AReader.ReportNode(AValue, cTexts[TRuleOptionsText.AllowedAreMediumAndHigh].Text);
  end;
end;

procedure ReadFix(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mIndex: Integer;
begin
  if not AReader.ExpectObject(ANode, 'fix') then
  begin
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    if ANode.Keys[mIndex] = 'minConfidence' then
    begin
      ReadFixMinConfidence(AReader, ANode[mIndex], ASettings);
    end
    else
    begin
      AReader.ReportNode(ANode[mIndex], cTexts[TRuleOptionsText.UnknownSettingFix].Fmt([ANode.Keys[mIndex]]));
    end;
  end;
end;

procedure TakeFix(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.FixMinConfidence := ASource.FixMinConfidence;
end;

procedure ReadMetrics(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ExpectBoolean(ANode, 'metrics', ASettings.Metrics);
end;

procedure TakeMetrics(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Metrics := ASource.Metrics;
end;

const
  cSections: array[0..9] of TConfigurationSection = (
    (Section: 'rules'; Read: ReadRules; Take: TakeRules),
    (Section: 'profile'; Read: ReadProfile; Take: TakeProfile),
    (Section: 'profiles'; Read: ReadProfiles; Take: TakeProfiles),
    (Section: 'overrides'; Read: ReadOverrides; Take: TakeOverrides),
    (Section: 'excludeTests'; Read: ReadExcludeTests; Take: TakeExcludeTests),
    (Section: 'testProfile'; Read: ReadTestProfile; Take: TakeTestProfile),
    (Section: 'exclude'; Read: ReadExclude; Take: TakeExclude),
    (Section: 'minConfidence'; Read: ReadMinConfidence; Take: TakeMinConfidence),
    (Section: 'fix'; Read: ReadFix; Take: TakeFix),
    (Section: 'metrics'; Read: ReadMetrics; Take: TakeMetrics)
  );

function RuleSections: TArray<TConfigurationSection>;
begin
  Result := SectionList(cSections);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Configuration.Internals.RuleOptions', cTexts);

end.
