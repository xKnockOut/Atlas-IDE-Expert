unit Atlas.Common.Rules.Conventions;

// Projektkonventionen für KI-Assistenten (#272), als MCP-Ressource
// atlas://conventions: Regelprofil (#146), Formatstil (#43), Benennungsregeln
// und jede aktive Regel mit Schweregrad und Kurztext aus dem Katalog (#145).
// Damit hält sich ein Assistent beim Schreiben an die Konventionen, bevor
// check_code (#178) prüft.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Catalog;

type
  TRuleConventions = class
  public
    /// <summary>Konventionen als Markdown; ACatalog darf nil sein.</summary>
    class function Markdown(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ACatalog: TRuleCatalog): string; static;
    /// <summary>Gehört die Regel zu den Benennungsregeln (Kennung enthält „name“ bzw. „naming“)?</summary>
    class function IsNamingRule(const ARuleId: string): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Output,
  Atlas.Common.Rules.Profiles,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TConventionsText = (Heading, Intro, Profile, FormatStyle, FormatDefault, Naming, NoNamingRule, ActiveRules);

const
  cTexts: array[TConventionsText] of TAtlasText = (
    (De: '# Konventionen des Projekts'; En: '# Project conventions'),
    (De: 'Atlas prüft Code nach diesen Regeln. Vor dem Schreiben beachten, danach mit `check_code` prüfen.';
     En: 'Atlas checks code against these rules. Follow them before writing, then check with `check_code`.'),
    (De: '- Regelprofil: `%s`'; En: '- Rule profile: `%s`'),
    (De: '- Formatstil (`format` in atlas.json): `%s`'; En: '- Format style (`format` in atlas.json): `%s`'),
    (De: '- Formatstil: Vorgaben bzw. `.editorconfig`'; En: '- Format style: defaults or `.editorconfig`'),
    (De: '## Benennung'; En: '## Naming'),
    (De: '- Keine aktive Benennungsregel.'; En: '- No active naming rule.'),
    (De: '## Aktive Regeln (%d)'; En: '## Active rules (%d)'));

{$SCOPEDENUMS OFF}

class function TRuleConventions.IsNamingRule(const ARuleId: string): Boolean;
begin
  Result := (Pos('name', LowerCase(ARuleId)) > 0) or (Pos('naming', LowerCase(ARuleId)) > 0);
end;

type
  /// <summary>Aktive Regel für den Bericht: Kennung, Schwere und Name aus dem Katalog.</summary>
  TConventionRule = record
    Id: string;
    Severity: string;
    Text: string;
  end;

/// <summary>Die aktiven Regeln aus ARules nach Kennung sortiert; experimentelle nur, wenn atlas.json sie
/// einschaltet.</summary>
function ActiveRules(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ACatalog: TRuleCatalog): TArray<TConventionRule>;
var
  mRule: IRule;
  mSeverity: TRuleSeverity;
  mEnabled: Boolean;
  mEntry: TRuleCatalogEntry;
  mItem: TConventionRule;
begin
  Result := nil;
  for mRule in ARules do
  begin
    mSeverity := TRuleEngine.EffectiveSeverity(mRule.Descriptor, ASettings, '', mEnabled);
    if (mSeverity <> TRuleSeverity.Off) and (mEnabled or not TRuleProfiles.IsExperimental(mRule.Descriptor.Id)) then
    begin
      mItem.Id := mRule.Descriptor.Id;
      mItem.Severity := TFindingsOutput.SeverityName(mSeverity);
      mItem.Text := mRule.Descriptor.Description;
      if (ACatalog <> nil) and ACatalog.TryFind(mItem.Id, mEntry) and (mEntry.Name <> '') then
      begin
        mItem.Text := mEntry.Name;
      end;
      Result := Result + [mItem];
    end;
  end;
  TArray.Sort<TConventionRule>(Result, TComparer<TConventionRule>.Construct(
    function(const A, B: TConventionRule): Integer
    begin
      Result := CompareText(A.Id, B.Id);
    end));
end;

procedure AppendHeader(ABuilder: TStringBuilder; const ASettings: TServerSettings);
var
  mProfile: string;
begin
  mProfile := ASettings.Profile;
  if mProfile = '' then
  begin
    mProfile := 'standard';
  end;
  ABuilder.AppendLine(cTexts[TConventionsText.Heading].Text);
  ABuilder.AppendLine;
  ABuilder.AppendLine(cTexts[TConventionsText.Intro].Text);
  ABuilder.AppendLine;
  ABuilder.AppendFormat(cTexts[TConventionsText.Profile].Text, [mProfile]).AppendLine;
  if ASettings.Format <> '' then
  begin
    ABuilder.AppendFormat(cTexts[TConventionsText.FormatStyle].Text, [ASettings.Format]).AppendLine;
  end
  else
  begin
    ABuilder.AppendLine(cTexts[TConventionsText.FormatDefault].Text);
  end;
end;

procedure AppendRule(ABuilder: TStringBuilder; const AItem: TConventionRule);
begin
  ABuilder.AppendFormat('- `%s` (%s): %s', [AItem.Id, AItem.Severity, AItem.Text]).AppendLine;
end;

class function TRuleConventions.Markdown(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ACatalog: TRuleCatalog): string;
var
  mBuilder: TStringBuilder;
  mActive: TArray<TConventionRule>;
  mItem: TConventionRule;
  mNaming: Boolean;
begin
  mActive := ActiveRules(ARules, ASettings, ACatalog);
  mBuilder := TStringBuilder.Create;
  try
    AppendHeader(mBuilder, ASettings);
    mBuilder.AppendLine;
    mBuilder.AppendLine(cTexts[TConventionsText.Naming].Text);
    mBuilder.AppendLine;
    mNaming := False;
    for mItem in mActive do
    begin
      if IsNamingRule(mItem.Id) then
      begin
        AppendRule(mBuilder, mItem);
        mNaming := True;
      end;
    end;
    if not mNaming then
    begin
      mBuilder.AppendLine(cTexts[TConventionsText.NoNamingRule].Text);
    end;
    mBuilder.AppendLine;
    mBuilder.AppendFormat(cTexts[TConventionsText.ActiveRules].Text, [Length(mActive)]).AppendLine;
    mBuilder.AppendLine;
    for mItem in mActive do
    begin
      AppendRule(mBuilder, mItem);
    end;
    Result := TrimRight(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Conventions', cTexts);

end.
