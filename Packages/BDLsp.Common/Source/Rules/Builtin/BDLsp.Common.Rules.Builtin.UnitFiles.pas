unit BDLsp.Common.Rules.Builtin.UnitFiles;

// Regeln zu Unit-Dateien (#181):
//   unit-name-mismatch  Name in der unit-Zeile passt nicht zum Dateinamen;
//                       der Compiler findet die Unit dann über uses nicht.

interface

uses
  System.SysUtils,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Registry;

type
  TUnitNameMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert alle Regeln zu Unit-Dateien.</summary>
procedure RegisterUnitFileRules(const ARegistry: TRuleRegistry);

implementation

uses
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Editing.UnitFiles;

{ TUnitNameMismatchRule }

function TUnitNameMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unit-name-mismatch', TRuleSeverity.Warning,
    'Der Unit-Name passt nicht zum Dateinamen');
end;

procedure TUnitNameMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Name, Keyword: string;
  Range: TTextRange;
begin
  // Ohne Dateinamen (z. B. ungespeichertes Dokument) gibt es nichts zu vergleichen.
  if (AContext.UnitName = '') or (AContext.Tree = nil) then
    Exit;
  if not TUnitFiles.Header(AContext.Tree.Tokens, Name, Range, Keyword) or (Keyword <> 'unit') then
    Exit;
  if SameText(Name, AContext.UnitName) then
    Exit;
  AReport.Add(Range, Format('Unit "%s" steht in der Datei "%s"; Name und Dateiname müssen übereinstimmen',
    [Name, AContext.UnitName + '.pas']),
    [TRuleFix.Create(Format('Unit in "%s" umbenennen', [AContext.UnitName]),
      [TRuleEdit.Create(Range, AContext.UnitName)])]);
end;

procedure RegisterUnitFileRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUnitNameMismatchRule.Create);
end;

end.
