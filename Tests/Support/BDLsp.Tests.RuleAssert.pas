unit BDLsp.Tests.RuleAssert;

// Testhilfe für Prüfregeln: parst einen Quelltext, führt eine Regel über die
// Engine aus und prüft Treffer. Jede Regel braucht mindestens einen
// positiven (Treffer) und einen negativen Testfall (kein Treffer).

interface

uses
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Rules.Contract;

type
  TRuleAssert = class
  public
    /// <summary>Treffer von ARule auf ASource mit Einstellungen aus AConfigJson ('' = Vorgaben).</summary>
    class function Findings(const ARule: IRule; const ASource: string;
      const AConfigJson: string = ''; const ARelativePath: string = ''): TArray<TRuleFinding>; static;
    /// <summary>Positiver Testfall: genau ACount Treffer.</summary>
    class procedure Reports(const ARule: IRule; const ASource: string; ACount: Integer = 1); static;
    /// <summary>Negativer Testfall: kein Treffer.</summary>
    class procedure Silent(const ARule: IRule; const ASource: string); static;
  end;

implementation

uses
  System.SysUtils,
  DUnitX.TestFramework,
  BDLsp.Common.Configuration.Parser,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Rules.Engine;

class function TRuleAssert.Findings(const ARule: IRule; const ASource, AConfigJson,
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

class procedure TRuleAssert.Reports(const ARule: IRule; const ASource: string; ACount: Integer);
begin
  Assert.AreEqual(ACount, Integer(Length(Findings(ARule, ASource))),
    'Treffer von ' + ARule.Descriptor.Id);
end;

class procedure TRuleAssert.Silent(const ARule: IRule; const ASource: string);
begin
  Reports(ARule, ASource, 0);
end;

end.
