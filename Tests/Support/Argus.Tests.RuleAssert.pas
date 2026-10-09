unit Argus.Tests.RuleAssert;

// Testhilfe für Prüfregeln: parst einen Quelltext, führt eine Regel über die
// Engine aus und prüft Treffer. Jede Regel braucht mindestens einen
// positiven (Treffer) und einen negativen Testfall (kein Treffer).

interface

uses
  Argus.Common.Configuration.Contract,
  Argus.Common.Rules.Contract;

type
  // ARule ohne const: Tests übergeben TXyzRule.Create direkt. Bei const zählt
  // niemand die Referenz, und das temporäre Array in TRuleEngine.Run gibt die
  // Regel frei, bevor sie hier weiter benutzt wird (Zugriffsverletzung).
  TRuleAssert = class
  public
    /// <summary>Treffer von ARule auf ASource mit Einstellungen aus AConfigJson ('' = Vorgaben).</summary>
    class function Findings(ARule: IRule; const ASource: string;
      const AConfigJson: string = ''; const ARelativePath: string = ''): TArray<TRuleFinding>; static;
    /// <summary>Positiver Testfall: genau ACount Treffer.</summary>
    class procedure Reports(ARule: IRule; const ASource: string; ACount: Integer = 1); static;
    /// <summary>Negativer Testfall: kein Treffer.</summary>
    class procedure Silent(ARule: IRule; const ASource: string); static;
  end;

implementation

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Argus.Common.Configuration.Parser,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Rules.Engine;

class function TRuleAssert.Findings(ARule: IRule; const ASource, AConfigJson,
  ARelativePath: string): TArray<TRuleFinding>;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
  Context: TRuleContext;
  Tree: TSyntaxTree;
begin
  if AConfigJson = '' then
    Settings := TServerSettings.Default
  else
    Settings := TConfigurationParser.Parse(AConfigJson, Issues);
  Tree := TPascalParser.Parse(ASource);
  try
    Context := Default(TRuleContext);
    Context.RelativePath := ARelativePath;
    Context.UnitName := ChangeFileExt(ExtractFileName(ARelativePath), '');
    Context.Text := ASource;
    Context.Tree := Tree;
    Result := TRuleEngine.Run([ARule], Settings, Context);
  finally
    Tree.Free;
  end;
end;

class procedure TRuleAssert.Reports(ARule: IRule; const ASource: string; ACount: Integer);
begin
  Assert.AreEqual(ACount, Integer(Length(Findings(ARule, ASource))),
    'Treffer von ' + ARule.Descriptor.Id);
end;

class procedure TRuleAssert.Silent(ARule: IRule; const ASource: string);
begin
  Reports(ARule, ASource, 0);
end;

end.
