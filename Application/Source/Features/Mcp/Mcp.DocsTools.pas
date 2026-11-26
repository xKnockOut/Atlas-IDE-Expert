unit Mcp.DocsTools;

// MCP-Werkzeug search_atlas_docs (#2376): durchsucht Regeln, Einstellungen, Fenster, Abschnitte der Funktionsseiten
// und Tastenkürzel von Atlas, auch ohne Repository (Index eingebettet, Mcp.DocsIndex). Je Treffer die
// Beschreibung; bei Regeln der wirksame Schweregrad im Projekt mit Herkunft, bei Einstellungen des Servers der Wert
// aus atlas.json bzw. settings.json mit Herkunft. Eine genaue Kennung kommt zuerst und mit dem ganzen Abschnitt.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Localization.Texts,
  Mcp.Contract.RuleDocs,
  Mcp.DocsIndex;

type
  TMcpDocsRequest = record
    Query: string;
    Kind: TDocsKind;
    Language: TTextLanguage;
    /// <summary>Höchstzahl der Treffer, 1 bis 20.</summary>
    Limit: Integer;
    Json: Boolean;
    /// <summary>Wirksame Einstellungen des Projekts (Schweregrade der Regeln).</summary>
    Settings: TServerSettings;
    /// <summary>Inhalt von atlas.json des Projekts; '' ohne Datei.</summary>
    ProjectText: string;
    /// <summary>Inhalt der globalen settings.json; '' ohne Datei oder abgeschaltet.</summary>
    GlobalText: string;
    /// <summary>Regelkatalog; nil = ohne Regeln.</summary>
    RuleDocs: IMcpRuleDocs;
  end;

  TMcpDocsTools = class
  public const
    cDefaultLimit = 5;
    cMaxLimit = 20;
  public
    /// <summary>Anfrage aus den Argumenten query, kind, language, limit, format; EMcpToolError ohne query oder
    /// bei unbekannter Art bzw. Sprache. Settings, ProjectText und GlobalText setzt der Aufrufer.</summary>
    class function RequestOf(const AArguments: TJSONObject): TMcpDocsRequest; static;
    /// <summary>Antwort des Werkzeugs als Text bzw. JSON.</summary>
    class function Search(const ARequest: TMcpDocsRequest): string; static;
  end;

implementation

uses
  System.StrUtils,
  // Inline-Funktionen von TJSONArray und TJSONObject (H2443).
  System.Generics.Collections,
  Atlas.Text.Json,
  Atlas.Common.Findings.Contract,
  Mcp.Server,
  Mcp.DocsIndexData;

type
{$SCOPEDENUMS ON}
  TDocsText = (NoQuery, BadKind, BadLanguage, Hits, NoHits, SimilarIds, KindRule, KindSetting, KindWindow,
    KindFeature, KindCommand, Experimental, InProject, ProjectOff, OriginRules, OriginGroup, OriginMetrics,
    OriginProfile, Options, OptionsInProject, Example, ExampleGood, Docs, TypeDefault, Values, Current,
    OriginProjectFile, OriginGlobalFile, OriginDefault, PluginValue, ProjectOverride, ShortCut, NoShortCut,
    SettingsOfSection, Sections, DependsOn);
{$SCOPEDENUMS OFF}

  /// <summary>Wert einer Einstellung des Servers und woher er kommt.</summary>
  TSettingValue = record
    Value: string;
    Origin: TDocsText;
  end;

  /// <summary>Was eine Antwort braucht: Anfrage, Index und die Abschnitte, die Schlüssel erwähnen.</summary>
  TDocsAnswer = record
    Request: TMcpDocsRequest;
    Index: TDocsIndex;
  end;

const
  cExcerptLength = 220;
  cSimilarCount = 5;
  cFeaturePages = 'docs/features/%s/%s#%s';
  cSeverityNames: array[TRuleSeverity] of string = ('default', 'off', 'hint', 'information', 'warning', 'error');
  // Herkunft in der JSON-Ausgabe, unabhängig von der Sprache.
  cOriginCodes: array[TFindingRuleOrigin] of string = ('rules', 'group', 'metrics', 'profile');
  cOriginTexts: array[TFindingRuleOrigin] of TDocsText = (TDocsText.OriginRules, TDocsText.OriginGroup,
    TDocsText.OriginMetrics, TDocsText.OriginProfile);
  cValueOriginCodes: array[TDocsText.OriginProjectFile..TDocsText.OriginDefault] of string = ('project', 'global',
    'default');

  cTexts: array[TDocsText] of TAtlasText = (
    (De: 'Keine Anfrage: query angeben.'; En: 'No query: give query.'),
    (De: 'Unbekannte Art "%s": rule, setting, window, feature, command oder all.';
     En: 'Unknown kind "%s": rule, setting, window, feature, command or all.'),
    (De: 'Unbekannte Sprache "%s": de oder en.'; En: 'Unknown language "%s": de or en.'),
    (De: '%d Treffer'; En: '%d hits'),
    (De: 'Keine Treffer für „%s“.'; En: 'No hits for “%s”.'),
    (De: 'Ähnliche Kennungen: %s'; En: 'Similar ids: %s'),
    (De: 'Regel'; En: 'Rule'),
    (De: 'Einstellung'; En: 'Setting'),
    (De: 'Fenster'; En: 'Window'),
    (De: 'Abschnitt'; En: 'Section'),
    (De: 'Befehl'; En: 'Command'),
    (De: 'experimentell'; En: 'experimental'),
    (De: 'Im Projekt: %s (%s)'; En: 'In the project: %s (%s)'),
    (De: 'aus'; En: 'off'),
    (De: 'gesetzt unter "rules"'; En: 'set under "rules"'),
    (De: 'Gruppe abgeschaltet mit "%s": "off"'; En: 'group switched off with "%s": "off"'),
    (De: 'Kennzahlen abgeschaltet mit "metrics": false'; En: 'metrics switched off with "metrics": false'),
    (De: 'Profil %s'; En: 'profile %s'),
    (De: 'Optionen: %s'; En: 'Options: %s'),
    (De: 'Optionen im Projekt: %s'; En: 'Options in the project: %s'),
    (De: 'Beispiel falsch:'; En: 'Example wrong:'),
    (De: 'Richtig:'; En: 'Right:'),
    (De: 'Doku: %s'; En: 'Docs: %s'),
    (De: 'Typ %s · Vorgabe %s'; En: 'Type %s · default %s'),
    (De: 'Werte: %s'; En: 'Values: %s'),
    (De: 'Aktuell: %s (%s)'; En: 'Current: %s (%s)'),
    (De: 'atlas.json des Projekts'; En: 'atlas.json of the project'),
    (De: 'settings.json für alle Projekte'; En: 'settings.json for all projects'),
    (De: 'Vorgabe'; En: 'default'),
    (De: 'Der Wert steht in den Einstellungen des IDE-Plugins (Optionen › Atlas); der Server sieht ihn nicht.';
     En: 'The value is in the settings of the IDE plugin (Options › Atlas); the server does not see it.'),
    (De: 'atlas.json überdeckt ihn mit "%s": %s'; En: 'atlas.json overrides it with "%s": %s'),
    (De: 'Tastenkürzel: %s (Vorgabe)'; En: 'Shortcut: %s (default)'),
    (De: 'ohne Vorgabe'; En: 'none by default'),
    (De: 'Einstellungen: %s'; En: 'Settings: %s'),
    (De: 'Steht in: %s'; En: 'Described in: %s'),
    (De: 'Hängt an: %s'; En: 'Depends on: %s'));

function Tx(const AAnswer: TDocsAnswer; AText: TDocsText): string;
begin
  Result := cTexts[AText].TextIn(AAnswer.Request.Language);
end;

function Fx(const AAnswer: TDocsAnswer; AText: TDocsText; const AArgs: array of const): string;
begin
  Result := Format(Tx(AAnswer, AText), AArgs);
end;

function IsGerman(const AAnswer: TDocsAnswer): Boolean;
begin
  Result := AAnswer.Request.Language = TTextLanguage.German;
end;

/// <summary>AText bis zum ersten Satzende nach etwa ALength Zeichen.</summary>
function Excerpt(const AText: string; ALength: Integer): string;
var
  mEnd: Integer;
begin
  Result := AText;
  if Length(Result) <= ALength then
  begin
    Exit;
  end;
  mEnd := PosEx('. ', Result, ALength div 2);
  if (mEnd = 0) or (mEnd > ALength) then
  begin
    Result := TrimRight(Copy(Result, 1, ALength)) + ' …';
  end
  else
  begin
    Result := Copy(Result, 1, mEnd);
  end;
end;

{ Werte der Einstellungen }

/// <summary>Wert unter dem Pfad AKey ("a.b") in AText als Text; False ohne.</summary>
function TryValueIn(const AText, AKey: string; out AValue: string): Boolean;
var
  mRoot: TJSONObject;
  mValue: TJSONValue;
  mPart: string;
begin
  AValue := '';
  Result := False;
  mRoot := TJsonRead.ParseObjectOrEmpty(AText);
  try
    mValue := mRoot;
    for mPart in AKey.Split(['.']) do
    begin
      if not (mValue is TJSONObject) then
      begin
        Exit;
      end;
      mValue := TJSONObject(mValue).GetValue(mPart);
    end;
    if mValue = nil then
    begin
      Exit;
    end;
    if mValue is TJSONString then
    begin
      AValue := TJSONString(mValue).Value;
    end
    else
    begin
      AValue := mValue.ToJSON;
    end;
    Result := True;
  finally
    mRoot.Free;
  end;
end;

function SettingValue(const ARequest: TMcpDocsRequest; AItem: TJSONObject): TSettingValue;
var
  mKey, mSource: string;
begin
  mKey := TJsonRead.Text(AItem, 'id');
  mSource := TJsonRead.Text(AItem, 'source');
  Result.Origin := TDocsText.OriginProjectFile;
  if (mSource <> 'global') and TryValueIn(ARequest.ProjectText, mKey, Result.Value) then
  begin
    Exit;
  end;
  Result.Origin := TDocsText.OriginGlobalFile;
  if (mSource <> 'project') and TryValueIn(ARequest.GlobalText, mKey, Result.Value) then
  begin
    Exit;
  end;
  Result.Origin := TDocsText.OriginDefault;
  Result.Value := TJsonRead.Text(AItem, 'default');
end;

{ Regeln }

function OptionsText(const ARule: TFindingRuleInfo): string;
var
  mOption: TFindingRuleOption;
  mItems: TArray<string>;
begin
  mItems := nil;
  for mOption in ARule.Options do
  begin
    mItems := mItems + [mOption.Name + ' = ' + mOption.DefaultJson];
  end;
  Result := string.Join(', ', mItems);
end;

function RuleHeading(const AAnswer: TDocsAnswer; const ARule: TFindingRuleInfo): string;
begin
  Result := Format('%s `%s` · %s · %s · %s', [Tx(AAnswer, TDocsText.KindRule), ARule.Id, ARule.Name,
    ARule.Category, cSeverityNames[ARule.DefaultSeverity]]);
  if ARule.Experimental then
  begin
    Result := Result + ' · ' + Tx(AAnswer, TDocsText.Experimental);
  end;
end;

procedure AddRuleText(ALines: TStringBuilder; const AAnswer: TDocsAnswer; const AHit: TDocsHit);
var
  mRule: TFindingRuleInfo;
  mState: TFindingRuleState;
begin
  mRule := AHit.Entry.Rule;
  ALines.AppendLine(RuleHeading(AAnswer, mRule));
  mState := AAnswer.Request.RuleDocs.State(mRule.Id, AAnswer.Request.Settings);
  ALines.AppendLine('   ' + Fx(AAnswer, TDocsText.InProject, [cSeverityNames[mState.Severity],
    Fx(AAnswer, cOriginTexts[mState.Origin], [mState.Detail])]));
  if not AHit.Exact then
  begin
    ALines.AppendLine('   ' + Excerpt(mRule.Description, cExcerptLength));
    Exit;
  end;
  ALines.AppendLine('   ' + mRule.Description);
  if mRule.Options <> nil then
  begin
    ALines.AppendLine('   ' + Fx(AAnswer, TDocsText.Options, [OptionsText(mRule)]));
  end;
  if mState.ProjectOptions <> '' then
  begin
    ALines.AppendLine('   ' + Fx(AAnswer, TDocsText.OptionsInProject, [mState.ProjectOptions]));
  end;
  if mRule.Bad <> '' then
  begin
    ALines.AppendLine('   ' + Tx(AAnswer, TDocsText.Example));
    ALines.AppendLine('```pascal').AppendLine(mRule.Bad).AppendLine('```');
    ALines.AppendLine('   ' + Tx(AAnswer, TDocsText.ExampleGood));
    ALines.AppendLine('```pascal').AppendLine(mRule.Good).AppendLine('```');
  end;
  ALines.AppendLine('   ' + Fx(AAnswer, TDocsText.Docs, [mRule.HelpUri]));
end;

function RuleJson(const AAnswer: TDocsAnswer; const AHit: TDocsHit): TJSONObject;
var
  mRule: TFindingRuleInfo;
  mState: TFindingRuleState;
  mOption: TFindingRuleOption;
  mOptions: TJSONObject;
begin
  mRule := AHit.Entry.Rule;
  mState := AAnswer.Request.RuleDocs.State(mRule.Id, AAnswer.Request.Settings);
  Result := TJSONObject.Create;
  Result.AddPair('name', mRule.Name);
  Result.AddPair('category', mRule.Category);
  Result.AddPair('group', mRule.Group);
  Result.AddPair('defaultSeverity', cSeverityNames[mRule.DefaultSeverity]);
  Result.AddPair('experimental', TJSONBool.Create(mRule.Experimental));
  Result.AddPair('severity', cSeverityNames[mState.Severity]);
  Result.AddPair('origin', cOriginCodes[mState.Origin]);
  if mState.Detail <> '' then
  begin
    Result.AddPair('originDetail', mState.Detail);
  end;
  Result.AddPair('description', mRule.Description);
  mOptions := TJSONObject.Create;
  Result.AddPair('options', mOptions);
  for mOption in mRule.Options do
  begin
    mOptions.AddPair(mOption.Name, mOption.DefaultJson);
  end;
  Result.AddPair('projectOptions', mState.ProjectOptions);
  Result.AddPair('bad', mRule.Bad);
  Result.AddPair('good', mRule.Good);
  Result.AddPair('docs', mRule.HelpUri);
end;

{ Einstellungen und Befehle }

function Localized(const AAnswer: TDocsAnswer; AItem: TJSONObject; const AName: string): string;
begin
  Result := '';
  if not IsGerman(AAnswer) then
  begin
    Result := TJsonRead.Text(AItem, AName + 'En');
  end;
  if Result = '' then
  begin
    Result := TJsonRead.Text(AItem, AName);
  end;
end;

function Place(const AAnswer: TDocsAnswer; AItem: TJSONObject): string;
var
  mNode: string;
begin
  Result := Localized(AAnswer, AItem, 'page');
  mNode := Localized(AAnswer, AItem, 'node');
  if mNode <> '' then
  begin
    Result := Result + ' › ' + mNode;
  end;
  Result := Result + ', ' + TJsonRead.Text(AItem, 'source');
end;

/// <summary>Abschnitte der Funktionsseiten in der Sprache der Anfrage, die AKey erwähnen.</summary>
function SectionsOf(const AAnswer: TDocsAnswer; const AKey: string): TArray<string>;
var
  mEntry: TDocsEntry;
begin
  Result := nil;
  for mEntry in AAnswer.Index.Entries do
  begin
    if (mEntry.Item <> nil) and (mEntry.Kind in [TDocsKind.Window, TDocsKind.Feature]) and
      (IndexStr(AKey, TJsonRead.Strings(mEntry.Item, 'settings')) >= 0) then
    begin
      Result := Result + [TJsonRead.Text(mEntry.Item, 'path')];
    end;
  end;
end;

procedure AddPluginLines(ALines: TStringBuilder; const AAnswer: TDocsAnswer; AItem: TJSONObject);
var
  mProject, mValue: string;
begin
  ALines.AppendLine('   ' + Tx(AAnswer, TDocsText.PluginValue));
  mProject := TJsonRead.Text(AItem, 'project');
  if (mProject <> '') and TryValueIn(AAnswer.Request.ProjectText, mProject, mValue) then
  begin
    ALines.AppendLine('   ' + Fx(AAnswer, TDocsText.ProjectOverride, [mProject, mValue]));
  end;
end;

procedure AddSettingText(ALines: TStringBuilder; const AAnswer: TDocsAnswer; const AHit: TDocsHit);
var
  mItem: TJSONObject;
  mValue: TSettingValue;
  mTitle, mDescription: string;
  mSections: TArray<string>;
begin
  mItem := AHit.Entry.Item;
  mTitle := Localized(AAnswer, mItem, 'caption');
  if mTitle <> '' then
  begin
    mTitle := ' – ' + mTitle;
  end;
  ALines.AppendLine(Format('%s `%s`%s  (%s)', [Tx(AAnswer, TDocsText.KindSetting), AHit.Entry.Id, mTitle,
    Place(AAnswer, mItem)]));
  mDescription := Localized(AAnswer, mItem, 'description');
  if not AHit.Exact then
  begin
    mDescription := Excerpt(mDescription, cExcerptLength);
  end;
  if mDescription <> '' then
  begin
    ALines.AppendLine('   ' + mDescription);
  end;
  ALines.AppendLine('   ' + Fx(AAnswer, TDocsText.TypeDefault, [TJsonRead.Text(mItem, 'type'),
    TJsonRead.Text(mItem, 'default')]));
  if TJsonRead.Strings(mItem, 'values') <> nil then
  begin
    ALines.AppendLine('   ' + Fx(AAnswer, TDocsText.Values, [string.Join(', ', TJsonRead.Strings(mItem, 'values'))]));
  end;
  if TJsonRead.Text(mItem, 'source') = 'plugin' then
  begin
    AddPluginLines(ALines, AAnswer, mItem);
  end
  else
  begin
    mValue := SettingValue(AAnswer.Request, mItem);
    ALines.AppendLine('   ' + Fx(AAnswer, TDocsText.Current, [mValue.Value, Tx(AAnswer, mValue.Origin)]));
  end;
  if AHit.Exact then
  begin
    if TJsonRead.Text(mItem, 'parent') <> '' then
    begin
      ALines.AppendLine('   ' + Fx(AAnswer, TDocsText.DependsOn, [TJsonRead.Text(mItem, 'parent')]));
    end;
    mSections := SectionsOf(AAnswer, AHit.Entry.Id);
    if mSections <> nil then
    begin
      ALines.AppendLine('   ' + Fx(AAnswer, TDocsText.Sections, [string.Join('; ', mSections)]));
    end;
  end;
end;

function ShortCutOf(const AAnswer: TDocsAnswer; AItem: TJSONObject): string;
begin
  Result := Localized(AAnswer, AItem, 'default');
  if Result = '' then
  begin
    Result := Tx(AAnswer, TDocsText.NoShortCut);
  end;
end;

procedure AddCommandText(ALines: TStringBuilder; const AAnswer: TDocsAnswer; const AHit: TDocsHit);
var
  mItem: TJSONObject;
  mDescription: string;
begin
  mItem := AHit.Entry.Item;
  ALines.AppendLine(Format('%s `%s` – %s  (%s)', [Tx(AAnswer, TDocsText.KindCommand), AHit.Entry.Id,
    Localized(AAnswer, mItem, 'caption'), Place(AAnswer, mItem)]));
  mDescription := Localized(AAnswer, mItem, 'description');
  if mDescription <> '' then
  begin
    ALines.AppendLine('   ' + mDescription);
  end;
  ALines.AppendLine('   ' + Fx(AAnswer, TDocsText.ShortCut, [ShortCutOf(AAnswer, mItem)]));
end;

procedure AddSectionText(ALines: TStringBuilder; const AAnswer: TDocsAnswer; const AHit: TDocsHit);
var
  mItem: TJSONObject;
  mKind: TDocsText;
  mSettings: TArray<string>;
begin
  mItem := AHit.Entry.Item;
  mKind := TDocsText.KindFeature;
  if AHit.Entry.Kind = TDocsKind.Window then
  begin
    mKind := TDocsText.KindWindow;
  end;
  ALines.AppendLine(Format('%s %s  (%s)', [Tx(AAnswer, mKind), TJsonRead.Text(mItem, 'path'),
    Format(cFeaturePages, [TJsonRead.Text(mItem, 'language'), TJsonRead.Text(mItem, 'page'),
    TJsonRead.Text(mItem, 'anchor')])]));
  ALines.AppendLine('   ' + TJsonRead.Text(mItem, 'text'));
  mSettings := TJsonRead.Strings(mItem, 'settings');
  if mSettings <> nil then
  begin
    ALines.AppendLine('   ' + Fx(AAnswer, TDocsText.SettingsOfSection, [string.Join(', ', mSettings)]));
  end;
end;

function ItemJson(const AAnswer: TDocsAnswer; const AHit: TDocsHit): TJSONObject;
var
  mValue: TSettingValue;
begin
  Result := AHit.Entry.Item.Clone as TJSONObject;
  Result.RemovePair('kind').Free;
  Result.RemovePair('id').Free;
  if (AHit.Entry.Kind = TDocsKind.Setting) and (TJsonRead.Text(AHit.Entry.Item, 'source') <> 'plugin') then
  begin
    mValue := SettingValue(AAnswer.Request, AHit.Entry.Item);
    Result.AddPair('value', mValue.Value);
    Result.AddPair('valueOrigin', cValueOriginCodes[mValue.Origin]);
  end;
  if AHit.Exact and (AHit.Entry.Kind = TDocsKind.Setting) then
  begin
    Result.AddPair('sections', TJsonBuild.Strings(SectionsOf(AAnswer, AHit.Entry.Id)));
  end;
end;

{ Antwort }

procedure AddHitText(ALines: TStringBuilder; const AAnswer: TDocsAnswer; const AHit: TDocsHit);
begin
  case AHit.Entry.Kind of
    TDocsKind.Rule:
      AddRuleText(ALines, AAnswer, AHit);
    TDocsKind.Setting:
      AddSettingText(ALines, AAnswer, AHit);
    TDocsKind.Command:
      AddCommandText(ALines, AAnswer, AHit);
    TDocsKind.Window, TDocsKind.Feature:
      AddSectionText(ALines, AAnswer, AHit);
    TDocsKind.All:
      ALines.AppendLine(AHit.Entry.Id);
  end;
end;

function HitJson(const AAnswer: TDocsAnswer; const AHit: TDocsHit): TJSONObject;
begin
  if AHit.Entry.Kind = TDocsKind.Rule then
  begin
    Result := RuleJson(AAnswer, AHit);
  end
  else
  begin
    Result := ItemJson(AAnswer, AHit);
  end;
  Result.AddPair('kind', TDocsIndex.KindName(AHit.Entry.Kind));
  Result.AddPair('id', AHit.Entry.Id);
  Result.AddPair('exact', TJSONBool.Create(AHit.Exact));
  Result.AddPair('score', TJSONNumber.Create(AHit.Score));
end;

function JsonAnswer(const AAnswer: TDocsAnswer; const AHits: TArray<TDocsHit>): string;
var
  mRoot: TJSONObject;
  mItems: TJSONArray;
  mHit: TDocsHit;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('query', AAnswer.Request.Query);
    mRoot.AddPair('kind', TDocsIndex.KindName(AAnswer.Request.Kind));
    mRoot.AddPair('language', TAtlasLocale.Code(AAnswer.Request.Language));
    mItems := TJSONArray.Create;
    mRoot.AddPair('results', mItems);
    for mHit in AHits do
    begin
      mItems.AddElement(HitJson(AAnswer, mHit));
    end;
    if AHits = nil then
    begin
      mRoot.AddPair('similar', TJsonBuild.Strings(AAnswer.Index.Similar(AAnswer.Request.Query,
        AAnswer.Request.Kind, cSimilarCount)));
    end;
    Result := mRoot.Format(2);
  finally
    mRoot.Free;
  end;
end;

function TextAnswer(const AAnswer: TDocsAnswer; const AHits: TArray<TDocsHit>): string;
var
  mLines: TStringBuilder;
  mIndex: Integer;
  mSimilar: TArray<string>;
begin
  mLines := TStringBuilder.Create;
  try
    if AHits = nil then
    begin
      mLines.AppendLine(Fx(AAnswer, TDocsText.NoHits, [AAnswer.Request.Query]));
      mSimilar := AAnswer.Index.Similar(AAnswer.Request.Query, AAnswer.Request.Kind, cSimilarCount);
      if mSimilar <> nil then
      begin
        mLines.AppendLine(Fx(AAnswer, TDocsText.SimilarIds, [string.Join(', ', mSimilar)]));
      end;
    end
    else
    begin
      mLines.AppendLine(Fx(AAnswer, TDocsText.Hits, [Length(AHits)]));
    end;
    for mIndex := 0 to High(AHits) do
    begin
      mLines.Append(IntToStr(mIndex + 1) + '. ');
      AddHitText(mLines, AAnswer, AHits[mIndex]);
    end;
    Result := TrimRight(mLines.ToString);
  finally
    mLines.Free;
  end;
end;

{ TMcpDocsTools }

class function TMcpDocsTools.RequestOf(const AArguments: TJSONObject): TMcpDocsRequest;
var
  mText: string;
begin
  Result := Default(TMcpDocsRequest);
  Result.Settings := TServerSettings.Default;
  Result.Query := Trim(TJsonRead.Text(AArguments, 'query'));
  if Result.Query = '' then
  begin
    raise EMcpToolError.Create(cTexts[TDocsText.NoQuery].Text);
  end;
  mText := TJsonRead.Text(AArguments, 'kind');
  if (mText <> '') and not TDocsIndex.TryParseKind(mText, Result.Kind) then
  begin
    raise EMcpToolError.Create(cTexts[TDocsText.BadKind].Fmt([mText]));
  end;
  Result.Language := TTextLanguage.German;
  mText := TJsonRead.Text(AArguments, 'language');
  if (mText <> '') and not TAtlasLocale.TryParse(mText, Result.Language) then
  begin
    raise EMcpToolError.Create(cTexts[TDocsText.BadLanguage].Fmt([mText]));
  end;
  Result.Limit := TJsonRead.IntOr(AArguments, 'limit', cDefaultLimit);
  if Result.Limit < 1 then
  begin
    Result.Limit := 1;
  end;
  if Result.Limit > cMaxLimit then
  begin
    Result.Limit := cMaxLimit;
  end;
  Result.Json := SameText(TJsonRead.Text(AArguments, 'format'), 'json');
end;

class function TMcpDocsTools.Search(const ARequest: TMcpDocsRequest): string;
var
  mAnswer: TDocsAnswer;
  mHits: TArray<TDocsHit>;
  mRules, mOther: TArray<TFindingRuleInfo>;
begin
  mRules := nil;
  mOther := nil;
  if ARequest.RuleDocs <> nil then
  begin
    mRules := ARequest.RuleDocs.Rules(TAtlasLocale.Code(ARequest.Language));
    if ARequest.Language = TTextLanguage.German then
    begin
      mOther := ARequest.RuleDocs.Rules(TAtlasLocale.Code(TTextLanguage.English));
    end
    else
    begin
      mOther := ARequest.RuleDocs.Rules(TAtlasLocale.Code(TTextLanguage.German));
    end;
  end;
  mAnswer.Request := ARequest;
  mAnswer.Index := TDocsIndex.Create(AtlasDocsIndexJson, ARequest.Language, mRules, mOther);
  try
    mHits := mAnswer.Index.Search(ARequest.Query, ARequest.Kind, ARequest.Limit);
    if ARequest.Json then
    begin
      Result := JsonAnswer(mAnswer, mHits);
    end
    else
    begin
      Result := TextAnswer(mAnswer, mHits);
    end;
  finally
    mAnswer.Index.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Mcp.DocsTools', cTexts);

end.
