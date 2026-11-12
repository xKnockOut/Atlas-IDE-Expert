unit Atlas.Common.Configuration.Internals.SuggestionOptions;

// Abschnitt "suggestions" von atlas.json (#1890): eigene Muster der gelernten
// Vorschläge unter "patterns", je Eintrag {"after": Text, "insert": [Zeilen]},
// etwa Hausregeln für das Logging. Ein Muster ohne "after" oder ohne Zeilen
// fällt mit einem Fehler weg. Die Schalter der Vorschläge liegen in den
// Einstellungen des Plugins.

interface

uses
  Atlas.Common.Configuration.Internals.Reader;

/// <summary>Abschnitte dieser Unit.</summary>
function SuggestionSections: TArray<TConfigurationSection>;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Internals.JsonTree,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSuggestionOptionsText = (PatternsMustBeAList, PatternMustBeAnObject, AfterMustBeAText, InsertMustBeAList);

const
  cTexts: array[TSuggestionOptionsText] of TAtlasText = (
    (De: '"suggestions.patterns" muss eine Liste sein'; En: '"suggestions.patterns" must be a list'),
    (De: 'Ein Muster in "suggestions.patterns" braucht "after" und mindestens eine Zeile in "insert"';
     En: 'A pattern in "suggestions.patterns" needs "after" and at least one line in "insert"'),
    (De: '"after" muss ein nicht leerer Text sein'; En: '"after" must be a non-empty text'),
    (De: '"insert" muss eine Liste von Zeilen sein'; En: '"insert" must be a list of lines'));

{$SCOPEDENUMS OFF}

const
  cPatternsKey = 'suggestions.patterns';

/// <summary>Liest ein Muster; False (mit Meldung), wenn es nicht taugt.</summary>
function ReadPattern(AReader: TConfigurationReader; ANode: TJsonNode; out APattern: TSuggestionPattern): Boolean;
var
  mIndex: Integer;
  mValue: TJsonNode;
begin
  APattern := Default(TSuggestionPattern);
  if ANode.Kind = TJsonKind.Object_ then
  begin
    for mIndex := 0 to ANode.Count - 1 do
    begin
      mValue := ANode[mIndex];
      if ANode.Keys[mIndex] = 'after' then
      begin
        if (mValue.Kind = TJsonKind.String_) and (Trim(mValue.Value) <> '') then
        begin
          APattern.After := Trim(mValue.Value);
        end
        else
        begin
          AReader.ReportNode(mValue, cTexts[TSuggestionOptionsText.AfterMustBeAText].Text);
        end;
      end
      else if ANode.Keys[mIndex] = 'insert' then
      begin
        AReader.ExpectStrings(mValue, 'insert', cTexts[TSuggestionOptionsText.InsertMustBeAList].Text,
          APattern.Insert);
      end
      else
      begin
        AReader.ReportUnknown(ANode, mIndex, cPatternsKey);
      end;
    end;
  end;
  Result := (APattern.After <> '') and (Length(APattern.Insert) > 0);
  if not Result then
  begin
    AReader.ReportNode(ANode, cTexts[TSuggestionOptionsText.PatternMustBeAnObject].Text);
  end;
end;

procedure ReadPatterns(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mIndex: Integer;
  mPattern: TSuggestionPattern;
  mPatterns: TArray<TSuggestionPattern>;
begin
  if AValue.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(AValue, cTexts[TSuggestionOptionsText.PatternsMustBeAList].Text);
    Exit;
  end;
  mPatterns := nil;
  for mIndex := 0 to AValue.Count - 1 do
  begin
    if ReadPattern(AReader, AValue[mIndex], mPattern) then
    begin
      mPatterns := mPatterns + [mPattern];
    end;
  end;
  ASettings.Suggestions.Patterns := mPatterns;
end;

const
  cSuggestionMembers: array[0..0] of TMemberOption = ((Key: 'patterns'; Read: ReadPatterns));

procedure ReadSuggestions(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'suggestions', [], cSuggestionMembers, ASettings);
end;

procedure TakeSuggestions(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Suggestions := ASource.Suggestions;
end;

const
  cSections: array[0..0] of TConfigurationSection = (
    (Section: 'suggestions'; Read: ReadSuggestions; Take: TakeSuggestions)
  );

function SuggestionSections: TArray<TConfigurationSection>;
begin
  Result := SectionList(cSections);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Configuration.Internals.SuggestionOptions', cTexts);

end.
