unit Atlas.Common.Configuration.Internals.EditorOptions;

// Abschnitte von atlas.json zum Editor: inlayHints, codeLens, smartIndent, classCompletion, references,
// navigation, directives, hints, stringLiteral, memberOrder, highlight und
// completion. Jeder Abschnitt ist ein Objekt; Schalter, feste Werte und
// eigene Glieder liest TConfigurationReader.ReadObject.

interface

uses
  Atlas.Common.Configuration.Internals.Reader;

/// <summary>Abschnitte dieser Unit.</summary>
function EditorSections: TArray<TConfigurationSection>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Internals.JsonTree,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditorOptionsText = (EndMarkerMinLinesMustBeAWhole, ImpactDepthMustBeAWhole, XmlDocExpandMustBeCollapsedLast,
    HintsXmlDocFullIsDeprecatedUse, XmlDocMaxLinesMustBeAWhole, RationaleMarkersMustBeAList,
    RationaleMarkersMustNotContainAn, AllowedAreAutoMultilineAnd, AllowedAreSLineBreak1310, MaxLineLengthMustBeAWhole,
    MemberOrderMustBeAList, ExitKeywordsMustBeAList, AllowedAreFuzzyAndPrefix, AllowedArePrivateProtectedAnd,
    AllowedAreAsAndCast, AllowedArePrivateAndProtected, AllowedArePrefixAndUses, AllowedAreOffHelperAnd,
    AllowedAreFreeAndFreeAndNil, ExpectedIsAUnitName, UnknownEntryInMemberOrder, UnitContentsMustBeOffTypes);

const
  cTexts: array[TEditorOptionsText] of TAtlasText = (
    (De: '"endMarkerMinLines" muss eine ganze Zahl ab 1 sein';
     En: '"endMarkerMinLines" must be a whole number from 1'),
    (De: '"impactDepth" muss eine ganze Zahl von 1 bis 5 sein';
     En: '"impactDepth" must be a whole number from 1 to 5'),
    (De: '"xmlDocExpand" muss "collapsed", "last" oder "expanded" sein';
     En: '"xmlDocExpand" must be "collapsed", "last" or "expanded"'),
    (De: '"hints.xmlDocFull" ist veraltet, stattdessen "hints.xmlDocExpand" verwenden';
     En: '"hints.xmlDocFull" is deprecated, use "hints.xmlDocExpand" instead'),
    (De: '"xmlDocMaxLines" muss eine ganze Zahl von 0 bis %d sein';
     En: '"xmlDocMaxLines" must be a whole number from 0 to %d'),
    (De: '"rationaleMarkers" muss eine Liste von Marken sein'; En: '"rationaleMarkers" must be a list of markers'),
    (De: '"rationaleMarkers" darf keine leere Marke enthalten';
     En: '"rationaleMarkers" must not contain an empty marker'),
    (De: 'Erlaubt sind "auto", "multiline" und "concat"'; En: 'Allowed are "auto", "multiline" and "concat"'),
    (De: 'Erlaubt sind "sLineBreak", "#13#10", "#10", "space" und "none"';
     En: 'Allowed are "sLineBreak", "#13#10", "#10", "space" and "none"'),
    (De: '"maxLineLength" muss eine ganze Zahl ab 0 sein'; En: '"maxLineLength" must be a whole number from 0'),
    (De: '"memberOrder.%s" muss eine Liste sein'; En: '"memberOrder.%s" must be a list'),
    (De: '"exitKeywords" muss eine Liste von Namen sein'; En: '"exitKeywords" must be a list of names'),
    (De: 'Erlaubt sind "fuzzy" und "prefix"'; En: 'Allowed are "fuzzy" and "prefix"'),
    (De: 'Erlaubt sind "private", "protected" und "public"'; En: 'Allowed are "private", "protected" and "public"'),
    (De: 'Erlaubt sind "as" und "cast"'; En: 'Allowed are "as" and "cast"'),
    (De: 'Erlaubt sind "private" und "protected"'; En: 'Allowed are "private" and "protected"'),
    (De: 'Erlaubt sind "prefix" und "uses"'; En: 'Allowed are "prefix" and "uses"'),
    (De: 'Erlaubt sind "off", "helper" und "function"'; En: 'Allowed are "off", "helper" and "function"'),
    (De: 'Erlaubt sind "free" und "freeAndNil"'; En: 'Allowed are "free" and "freeAndNil"'),
    (De: 'Erwartet wird ein Unit-Name wie "App.Texte" oder ""'; En: 'Expected is a unit name like "App.Texts" or ""'),
    (De: 'Unbekannter Eintrag "%s" in "memberOrder.%s"'; En: 'Unknown entry "%s" in "memberOrder.%s"'),
    (De: '"unitContents" muss "off", "types", "usedFirst" oder "all" sein';
     En: '"unitContents" must be "off", "types", "usedFirst" or "all"'));

{$SCOPEDENUMS OFF}

{ inlayHints, codeLens, references, navigation, directives }

procedure ReadEndMarkerMinLines(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ExpectInteger(AValue, 1, MaxInt, cTexts[TEditorOptionsText.EndMarkerMinLinesMustBeAWhole].Text,
    ASettings.InlayHints.EndMarkerMinLines);
end;

const
  cInlayHintMembers: array[0..0] of TMemberOption = ((Key: 'endMarkerMinLines'; Read: ReadEndMarkerMinLines));

procedure ReadInlayHints(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'inlayHints', [TFlagOption.Create('parameterNames', ASettings.InlayHints.ParameterNames),
    TFlagOption.Create('inferredTypes', ASettings.InlayHints.InferredTypes),
    TFlagOption.Create('endMarkers', ASettings.InlayHints.EndMarkers),
    TFlagOption.Create('includeDefines', ASettings.InlayHints.IncludeDefines),
    TFlagOption.Create('controlChars', ASettings.InlayHints.ControlChars)], cInlayHintMembers, ASettings);
end;

procedure TakeInlayHints(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.InlayHints := ASource.InlayHints;
end;

procedure ReadCodeLens(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'codeLens', [TFlagOption.Create('metrics', ASettings.CodeLens.Metrics)], [], ASettings);
end;

procedure TakeCodeLens(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.CodeLens := ASource.CodeLens;
end;

procedure ReadSmartIndent(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'smartIndent', [TFlagOption.Create('enabled', ASettings.SmartIndent.Enabled),
    TFlagOption.Create('afterEnter', ASettings.SmartIndent.AfterEnter),
    TFlagOption.Create('outdentClosers', ASettings.SmartIndent.OutdentClosers),
    TFlagOption.Create('splitStrings', ASettings.SmartIndent.SplitStrings)],
    [TChoiceOption.Create('splitStringsIndent', ['indent', 'align'], ASettings.SmartIndent.SplitStringsIndent)], [],
    ASettings);
end;

procedure TakeSmartIndent(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.SmartIndent := ASource.SmartIndent;
end;

procedure ReadClassCompletion(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'classCompletion', [TFlagOption.Create('bodyStubs', ASettings.ClassCompletion.BodyStubs),
    TFlagOption.Create('lifecycleFirst', ASettings.ClassCompletion.LifecycleFirst)],
    [TChoiceOption.Create('typeComment', ['brace', 'line', 'summary', 'region', 'off'],
    ASettings.ClassCompletion.TypeComment)], [], ASettings);
end;

procedure TakeClassCompletion(const ASource: TServerSettings; const AFileText: string;
  var ATarget: TServerSettings);
begin
  ATarget.ClassCompletion := ASource.ClassCompletion;
end;

procedure ReadReferences(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'references', [TFlagOption.Create('inferred', ASettings.References.Inferred),
    TFlagOption.Create('textMatches', ASettings.References.TextMatches)], [], ASettings);
end;

procedure TakeReferences(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.References := ASource.References;
end;

procedure ReadImpactDepth(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ExpectInteger(AValue, 1, 5, cTexts[TEditorOptionsText.ImpactDepthMustBeAWhole].Text,
    ASettings.Navigation.ImpactDepth);
end;

const
  cNavigationMembers: array[0..0] of TMemberOption = ((Key: 'impactDepth'; Read: ReadImpactDepth));

procedure ReadNavigation(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'navigation', [TFlagOption.Create('symbolPath', ASettings.Navigation.SymbolPath),
    TFlagOption.Create('impact', ASettings.Navigation.Impact)], cNavigationMembers, ASettings);
end;

procedure TakeNavigation(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Navigation := ASource.Navigation;
end;

procedure ReadDirectives(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'directives', [TFlagOption.Create('completion', ASettings.Directives.Completion),
    TFlagOption.Create('hover', ASettings.Directives.Hover)], [], ASettings);
end;

procedure TakeDirectives(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Directives := ASource.Directives;
end;

{ hints }

/// <summary>xmlDocExpand; True, wenn der Wert gilt.</summary>
function ReadXmlDocExpand(AReader: TConfigurationReader; AValue: TJsonNode; var AHints: THintSettings): Boolean;
var
  mIndex: Integer;
begin
  Result := AReader.ExpectChoice(AValue, 'xmlDocExpand', [THintSettings.cExpandCollapsed, THintSettings.cExpandLast,
    THintSettings.cExpandExpanded], cTexts[TEditorOptionsText.XmlDocExpandMustBeCollapsedLast].Text, mIndex);
  if Result then
  begin
    AHints.XmlDocExpand := AValue.Value;
  end;
end;

/// <summary>Veraltet seit #770: true = expanded, false = collapsed, solange xmlDocExpand fehlt.</summary>
procedure ReadXmlDocFull(AReader: TConfigurationReader; ANode: TJsonNode; AIndex: Integer; AExpandSet: Boolean;
  var AHints: THintSettings);
var
  mFull: Boolean;
begin
  mFull := True;
  if not AReader.ExpectBoolean(ANode[AIndex], 'xmlDocFull', mFull) then
  begin
    Exit;
  end;
  AReader.Report(ANode.KeyStarts[AIndex], ANode.KeyStarts[AIndex] + Length(ANode.Keys[AIndex]) + 2,
    cTexts[TEditorOptionsText.HintsXmlDocFullIsDeprecatedUse].Text, False);
  if AExpandSet then
  begin
    Exit;
  end;
  if mFull then
  begin
    AHints.XmlDocExpand := THintSettings.cExpandExpanded;
  end
  else
  begin
    AHints.XmlDocExpand := THintSettings.cExpandCollapsed;
  end;
end;

procedure ReadXmlDocMaxLines(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ExpectInteger(AValue, 0, THintSettings.cMaxXmlDocLines,
    cTexts[TEditorOptionsText.XmlDocMaxLinesMustBeAWhole].Fmt([THintSettings.cMaxXmlDocLines]),
    ASettings.Hints.XmlDocMaxLines);
end;

/// <summary>Inhalt der Unit im Hover über Unit-Namen (#1921).</summary>
procedure ReadUnitContents(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
const
  cNames: array[0..3] of string = (THintSettings.cUnitContentsOff, THintSettings.cUnitContentsTypes,
    THintSettings.cUnitContentsUsedFirst, THintSettings.cUnitContentsAll);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoice(AValue, AKey, cNames, cTexts[TEditorOptionsText.UnitContentsMustBeOffTypes].Text,
    mIndex) then
  begin
    ASettings.Hints.UnitContents := cNames[mIndex];
  end;
end;

/// <summary>Begründungen (#1123): eigene Marken ersetzen die Vorgabe.</summary>
procedure ReadRationaleMarkers(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mItem: Integer;
  mText: string;
begin
  if AValue.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(AValue, cTexts[TEditorOptionsText.RationaleMarkersMustBeAList].Text);
    Exit;
  end;
  ASettings.Hints.RationaleMarkers := nil;
  for mItem := 0 to AValue.Count - 1 do
  begin
    if not AReader.ExpectString(AValue[mItem], 'rationaleMarkers', mText) then
    begin
      Continue;
    end;
    if Trim(mText) = '' then
    begin
      AReader.ReportNode(AValue[mItem], cTexts[TEditorOptionsText.RationaleMarkersMustNotContainAn].Text);
    end
    else
    begin
      ASettings.Hints.RationaleMarkers := ASettings.Hints.RationaleMarkers + [Trim(mText)];
    end;
  end;
end;

procedure ReadAdrFolder(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mText: string;
begin
  if AReader.ExpectString(AValue, AKey, mText) then
  begin
    ASettings.Hints.AdrFolder := Trim(mText);
  end;
end;

const
  cHintMembers: array[0..3] of TMemberOption = ((Key: 'xmlDocMaxLines'; Read: ReadXmlDocMaxLines),
    (Key: 'rationaleMarkers'; Read: ReadRationaleMarkers), (Key: 'adrFolder'; Read: ReadAdrFolder),
    (Key: 'unitContents'; Read: ReadUnitContents));

procedure ReadHints(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mIndex: Integer;
  mExpandSet: Boolean;
  mFlags: TArray<TFlagOption>;
begin
  if not AReader.ExpectObject(ANode, 'hints') then
  begin
    Exit;
  end;
  mFlags := [TFlagOption.Create('publishedMembers', ASettings.Hints.PublishedMembers),
    TFlagOption.Create('rationale', ASettings.Hints.Rationale)];
  mExpandSet := False;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    // xmlDocFull wirkt nur, wenn davor kein gültiges xmlDocExpand stand.
    if ANode.Keys[mIndex] = 'xmlDocExpand' then
    begin
      mExpandSet := ReadXmlDocExpand(AReader, ANode[mIndex], ASettings.Hints) or mExpandSet;
    end
    else if ANode.Keys[mIndex] = 'xmlDocFull' then
    begin
      ReadXmlDocFull(AReader, ANode, mIndex, mExpandSet, ASettings.Hints);
    end
    else if not AReader.ReadFlag(ANode, mIndex, mFlags) and
      not AReader.ReadMember(ANode, mIndex, cHintMembers, ASettings) then
    begin
      AReader.ReportUnknown(ANode, mIndex, 'hints');
    end;
  end;
end;

procedure TakeHints(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Hints := ASource.Hints;
end;

{ stringLiteral }

procedure ReadLiteralStyle(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
const
  cNames: array[0..2] of string = ('auto', 'multiline', 'concat');
  cStyles: array[0..2] of TStringLiteralStyle = (TStringLiteralStyle.Auto, TStringLiteralStyle.Multiline,
    TStringLiteralStyle.Concat);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoice(AValue, AKey, cNames, cTexts[TEditorOptionsText.AllowedAreAutoMultilineAnd].Text, mIndex) then
  begin
    ASettings.StringLiteral.Style := cStyles[mIndex];
  end;
end;

procedure ReadLiteralBreak(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
const
  cNames: array[0..4] of string = ('sLineBreak', '#13#10', '#10', 'space', 'none');
  cBreaks: array[0..4] of TStringLiteralBreak = (TStringLiteralBreak.SLineBreak, TStringLiteralBreak.CrLf,
    TStringLiteralBreak.Lf, TStringLiteralBreak.Space, TStringLiteralBreak.None);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoice(AValue, AKey, cNames, cTexts[TEditorOptionsText.AllowedAreSLineBreak1310].Text,
    mIndex) then
  begin
    ASettings.StringLiteral.LineBreak := cBreaks[mIndex];
  end;
end;

procedure ReadMaxLineLength(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ExpectInteger(AValue, 0, MaxInt, cTexts[TEditorOptionsText.MaxLineLengthMustBeAWhole].Text,
    ASettings.StringLiteral.MaxLineLength);
end;

const
  cStringLiteralMembers: array[0..2] of TMemberOption = ((Key: 'style'; Read: ReadLiteralStyle),
    (Key: 'lineBreak'; Read: ReadLiteralBreak), (Key: 'maxLineLength'; Read: ReadMaxLineLength));

procedure ReadStringLiteral(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'stringLiteral', [], cStringLiteralMembers, ASettings);
end;

procedure TakeStringLiteral(const ASource: TServerSettings; const AFileText: string;
  var ATarget: TServerSettings);
begin
  ATarget.StringLiteral := ASource.StringLiteral;
end;

{ memberOrder }

/// <summary>Liste von Namen aus AAllowed (Groß-/Kleinschreibung egal), klein geschrieben; andere meldet sie.
/// False, wenn AValue keine Liste ist.</summary>
function ReadOrderNames(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  const AAllowed: array of string; out ANames: TArray<string>): Boolean;
var
  mItem: Integer;
  mText: string;
begin
  ANames := nil;
  Result := AValue.Kind = TJsonKind.Array_;
  if not Result then
  begin
    AReader.ReportNode(AValue, cTexts[TEditorOptionsText.MemberOrderMustBeAList].Fmt([AKey]));
    Exit;
  end;
  for mItem := 0 to AValue.Count - 1 do
  begin
    if not AReader.ExpectString(AValue[mItem], AKey, mText) then
    begin
      Continue;
    end;
    if MatchText(mText, AAllowed) then
    begin
      ANames := ANames + [LowerCase(mText)];
    end
    else
    begin
      AReader.ReportNode(AValue[mItem], cTexts[TEditorOptionsText.UnknownEntryInMemberOrder].Fmt([mText, AKey]));
    end;
  end;
end;

procedure ReadOrderSections(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mNames: TArray<string>;
begin
  if ReadOrderNames(AReader, AValue, AKey, ['strict private', 'private', 'strict protected', 'protected', 'public',
    'published'], mNames) then
  begin
    ASettings.MemberOrder.Sections := mNames;
  end;
end;

procedure ReadOrderMembers(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mNames: TArray<string>;
begin
  if ReadOrderNames(AReader, AValue, AKey, ['field', 'constructor', 'destructor', 'method', 'property'],
    mNames) then
  begin
    ASettings.MemberOrder.Members := mNames;
  end;
end;

const
  cMemberOrderMembers: array[0..1] of TMemberOption = ((Key: 'sections'; Read: ReadOrderSections),
    (Key: 'members'; Read: ReadOrderMembers));

procedure ReadMemberOrder(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'memberOrder', [TFlagOption.Create('sortFields', ASettings.MemberOrder.SortFields),
    TFlagOption.Create('sortPublished', ASettings.MemberOrder.SortPublished)], cMemberOrderMembers, ASettings);
end;

procedure TakeMemberOrder(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.MemberOrder := ASource.MemberOrder;
end;

{ highlight }

procedure ReadExitKeywords(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mItems: TArray<string>;
begin
  if AReader.ExpectStrings(AValue, AKey, cTexts[TEditorOptionsText.ExitKeywordsMustBeAList].Text, mItems) then
  begin
    ASettings.Highlight.ExitKeywords := mItems;
  end;
end;

const
  cHighlightMembers: array[0..0] of TMemberOption = ((Key: 'exitKeywords'; Read: ReadExitKeywords));

procedure ReadHighlight(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'highlight', [TFlagOption.Create('blockPairs', ASettings.Highlight.BlockPairs),
    TFlagOption.Create('directives', ASettings.Highlight.Directives),
    TFlagOption.Create('exitPoints', ASettings.Highlight.ExitPoints)], cHighlightMembers, ASettings);
end;

procedure TakeHighlight(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Highlight := ASource.Highlight;
end;

{ completion }

procedure ReadMatching(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
const
  cNames: array[0..1] of string = ('fuzzy', 'prefix');
  cValues: array[0..1] of TCompletionMatching = (TCompletionMatching.Fuzzy, TCompletionMatching.Prefix);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoice(AValue, AKey, cNames, cTexts[TEditorOptionsText.AllowedAreFuzzyAndPrefix].Text, mIndex) then
  begin
    ASettings.Completion.Matching := cValues[mIndex];
  end;
end;

procedure ReadInterfaceSection(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
const
  cNames: array[0..2] of string = ('private', 'protected', 'public');
  cValues: array[0..2] of TCompletionInterfaceSection = (TCompletionInterfaceSection.Private,
    TCompletionInterfaceSection.Protected, TCompletionInterfaceSection.Public);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoice(AValue, AKey, cNames, cTexts[TEditorOptionsText.AllowedArePrivateProtectedAnd].Text,
    mIndex) then
  begin
    ASettings.Completion.InterfaceSection := cValues[mIndex];
  end;
end;

procedure ReadSenderCast(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
const
  cNames: array[0..1] of string = ('as', 'cast');
  cValues: array[0..1] of TCompletionSenderCast = (TCompletionSenderCast.AsOperator, TCompletionSenderCast.HardCast);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoice(AValue, AKey, cNames, cTexts[TEditorOptionsText.AllowedAreAsAndCast].Text, mIndex) then
  begin
    ASettings.Completion.SenderCast := cValues[mIndex];
  end;
end;

procedure ReadAccessorSection(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
const
  cNames: array[0..1] of string = ('private', 'protected');
  cValues: array[0..1] of TCompletionAccessorSection = (TCompletionAccessorSection.Private,
    TCompletionAccessorSection.Protected);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoice(AValue, AKey, cNames, cTexts[TEditorOptionsText.AllowedArePrivateAndProtected].Text,
    mIndex) then
  begin
    ASettings.Completion.AccessorSection := cValues[mIndex];
  end;
end;

procedure ReadSameNameInsert(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
const
  cNames: array[0..1] of string = ('prefix', 'uses');
  cValues: array[0..1] of TCompletionSameNameInsert = (TCompletionSameNameInsert.Prefix,
    TCompletionSameNameInsert.Uses_);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoice(AValue, AKey, cNames, cTexts[TEditorOptionsText.AllowedArePrefixAndUses].Text, mIndex) then
  begin
    ASettings.Completion.SameNameInsert := cValues[mIndex];
  end;
end;

procedure ReadTypeConversion(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
const
  cNames: array[0..2] of string = ('off', 'helper', 'function');
  cValues: array[0..2] of TCompletionTypeConversion = (TCompletionTypeConversion.Off,
    TCompletionTypeConversion.Helper, TCompletionTypeConversion.Function_);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoice(AValue, AKey, cNames, cTexts[TEditorOptionsText.AllowedAreOffHelperAnd].Text, mIndex) then
  begin
    ASettings.Completion.TypeConversion := cValues[mIndex];
  end;
end;

procedure ReadFreeStyle(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
const
  cNames: array[0..1] of string = ('free', 'freeAndNil');
  cValues: array[0..1] of TCompletionFreeStyle = (TCompletionFreeStyle.Free, TCompletionFreeStyle.FreeAndNil);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoice(AValue, AKey, cNames, cTexts[TEditorOptionsText.AllowedAreFreeAndFreeAndNil].Text,
    mIndex) then
  begin
    ASettings.Completion.FreeStyle := cValues[mIndex];
  end;
end;

procedure ReadResourceStringUnit(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mText: string;
begin
  if not AReader.ExpectString(AValue, AKey, mText) then
  begin
    Exit;
  end;
  if (mText = '') or IsValidIdent(mText, True) then
  begin
    ASettings.Completion.ResourceStringUnit := mText;
  end
  else
  begin
    AReader.ReportNode(AValue, cTexts[TEditorOptionsText.ExpectedIsAUnitName].Text);
  end;
end;

const
  cCompletionMembers: array[0..7] of TMemberOption = ((Key: 'matching'; Read: ReadMatching),
    (Key: 'interfaceSection'; Read: ReadInterfaceSection), (Key: 'senderCast'; Read: ReadSenderCast),
    (Key: 'accessorSection'; Read: ReadAccessorSection), (Key: 'sameNameInsert'; Read: ReadSameNameInsert),
    (Key: 'typeConversion'; Read: ReadTypeConversion), (Key: 'resourceStringUnit'; Read: ReadResourceStringUnit),
    (Key: 'freeStyle'; Read: ReadFreeStyle));

function CompletionFlags(var ACompletion: TCompletionSettings): TArray<TFlagOption>;
begin
  Result := [TFlagOption.Create('offerTryFinally', ACompletion.OfferTryFinally),
    TFlagOption.Create('keywords', ACompletion.Keywords),
    TFlagOption.Create('postfixTemplates', ACompletion.PostfixTemplates),
    TFlagOption.Create('genericConstraints', ACompletion.GenericConstraints),
    TFlagOption.Create('nameSuggestions', ACompletion.NameSuggestions),
    TFlagOption.Create('createAccessors', ACompletion.CreateAccessors),
    TFlagOption.Create('resourceStrings', ACompletion.ResourceStrings),
    TFlagOption.Create('assignAllFields', ACompletion.AssignAllFields),
    TFlagOption.Create('usesDetails', ACompletion.UsesDetails),
    TFlagOption.Create('inheritedCall', ACompletion.InheritedCall),
    TFlagOption.Create('attributes', ACompletion.Attributes),
    TFlagOption.Create('anonymousMethods', ACompletion.AnonymousMethods),
    TFlagOption.Create('withOrigin', ACompletion.WithOrigin),
    TFlagOption.Create('exceptionClasses', ACompletion.ExceptionClasses),
    TFlagOption.Create('syntaxNotice', ACompletion.SyntaxNotice),
    TFlagOption.Create('sameNameVariants', ACompletion.SameNameVariants),
    TFlagOption.Create('showFmxUnits', ACompletion.ShowFmxUnits),
    TFlagOption.Create('typeGuards', ACompletion.TypeGuards),
    TFlagOption.Create('hiddenMembers', ACompletion.HiddenMembers),
    TFlagOption.Create('projectFrequency', ACompletion.ProjectFrequency)];
end;

procedure ReadCompletion(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'completion', CompletionFlags(ASettings.Completion), cCompletionMembers, ASettings);
end;

procedure TakeCompletion(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Completion := ASource.Completion;
end;

const
  cSections: array[0..11] of TConfigurationSection = (
    (Section: 'inlayHints'; Read: ReadInlayHints; Take: TakeInlayHints),
    (Section: 'codeLens'; Read: ReadCodeLens; Take: TakeCodeLens),
    (Section: 'smartIndent'; Read: ReadSmartIndent; Take: TakeSmartIndent),
    (Section: 'classCompletion'; Read: ReadClassCompletion; Take: TakeClassCompletion),
    (Section: 'references'; Read: ReadReferences; Take: TakeReferences),
    (Section: 'navigation'; Read: ReadNavigation; Take: TakeNavigation),
    (Section: 'directives'; Read: ReadDirectives; Take: TakeDirectives),
    (Section: 'hints'; Read: ReadHints; Take: TakeHints),
    (Section: 'stringLiteral'; Read: ReadStringLiteral; Take: TakeStringLiteral),
    (Section: 'memberOrder'; Read: ReadMemberOrder; Take: TakeMemberOrder),
    (Section: 'highlight'; Read: ReadHighlight; Take: TakeHighlight),
    (Section: 'completion'; Read: ReadCompletion; Take: TakeCompletion)
  );

function EditorSections: TArray<TConfigurationSection>;
begin
  Result := SectionList(cSections);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Configuration.Internals.EditorOptions', cTexts);

end.
