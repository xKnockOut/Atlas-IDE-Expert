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
  Atlas.Common.Rules.Output;

class function TRuleConventions.IsNamingRule(const ARuleId: string): Boolean;
begin
  Result := (Pos('name', LowerCase(ARuleId)) > 0) or (Pos('naming', LowerCase(ARuleId)) > 0);
end;

class function TRuleConventions.Markdown(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ACatalog: TRuleCatalog): string;
type
  TActive = record
    Id: string;
    Severity: string;
    Text: string;
  end;
var
  Builder: TStringBuilder;
  Rule: IRule;
  Severity: TRuleSeverity;
  Enabled: Boolean;
  Entry: TRuleCatalogEntry;
  Active: TList<TActive>;
  Item: TActive;
  Profile: string;
  Naming: Boolean;
begin
  Active := TList<TActive>.Create;
  Builder := TStringBuilder.Create;
  try
    for Rule in ARules do
    begin
      Severity := TRuleEngine.EffectiveSeverity(Rule.Descriptor, ASettings, '', Enabled);
      // Experimentelle Regeln laufen nur, wenn atlas.json sie einschaltet.
      if (Severity = TRuleSeverity.Off) or (Rule.Descriptor.Experimental and not Enabled) then
        Continue;
      Item.Id := Rule.Descriptor.Id;
      Item.Severity := TFindingsOutput.SeverityName(Severity);
      Item.Text := Rule.Descriptor.Description;
      if (ACatalog <> nil) and ACatalog.TryFind(Item.Id, Entry) then
      begin
        if Entry.Name <> '' then
          Item.Text := Entry.Name;
      end;
      Active.Add(Item);
    end;
    Active.Sort(TComparer<TActive>.Construct(
      function(const A, B: TActive): Integer
      begin
        Result := CompareText(A.Id, B.Id);
      end));
    Profile := ASettings.Profile;
    if Profile = '' then
      Profile := 'standard';
    Builder.AppendLine('# Konventionen des Projekts');
    Builder.AppendLine;
    Builder.AppendLine('Atlas prüft Code nach diesen Regeln. Vor dem Schreiben beachten, danach mit `check_code` prüfen.');
    Builder.AppendLine;
    Builder.AppendFormat('- Regelprofil: `%s`', [Profile]).AppendLine;
    if ASettings.Format <> '' then
      Builder.AppendFormat('- Formatstil (`format` in atlas.json): `%s`', [ASettings.Format]).AppendLine
    else
      Builder.AppendLine('- Formatstil: Vorgaben bzw. `.editorconfig`');
    Builder.AppendLine;
    Builder.AppendLine('## Benennung');
    Builder.AppendLine;
    Naming := False;
    for Item in Active do
      if IsNamingRule(Item.Id) then
      begin
        Builder.AppendFormat('- `%s` (%s): %s', [Item.Id, Item.Severity, Item.Text]).AppendLine;
        Naming := True;
      end;
    if not Naming then
      Builder.AppendLine('- Keine aktive Benennungsregel.');
    Builder.AppendLine;
    Builder.AppendFormat('## Aktive Regeln (%d)', [Active.Count]).AppendLine;
    Builder.AppendLine;
    for Item in Active do
      Builder.AppendFormat('- `%s` (%s): %s', [Item.Id, Item.Severity, Item.Text]).AppendLine;
    Result := TrimRight(Builder.ToString);
  finally
    Builder.Free;
    Active.Free;
  end;
end;

end.
