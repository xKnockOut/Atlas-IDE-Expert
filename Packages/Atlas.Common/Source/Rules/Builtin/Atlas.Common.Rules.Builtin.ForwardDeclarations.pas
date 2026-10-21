unit Atlas.Common.Rules.Builtin.ForwardDeclarations;

// Forward-Deklarationen (#685):
//   type-used-before-declaration   Typ in einer Typdeklaration benutzt, bevor er
//                                  deklariert ist (sonst erst E2003)
//   unneeded-forward-declaration   Forward-Deklaration, die niemand braucht
//
// Erkennung und Korrekturen liefert TForwardDeclarations (Editing). Mit
// refactoring.forwardDeclaration aus schweigen beide Regeln.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TTypeUsedBeforeDeclarationRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnneededForwardDeclarationRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterForwardDeclarationRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.ForwardDeclarations;

function FixesOf(const AFinding: TForwardFinding): TArray<TRuleFix>;
var
  Safe: Boolean;
begin
  Result := nil;
  if AFinding.Fix = TForwardFix.NoFix then
    Exit;
  // Ergänzen und Entfernen ändern nur eine Zeile und sind immer richtig.
  Safe := AFinding.Fix in [TForwardFix.AddForward, TForwardFix.RemoveForward];
  Result := [TRuleFix.Create(TForwardDeclarations.FixTitle(AFinding.Fix), AFinding.Edits, Safe)];
end;

{ TTypeUsedBeforeDeclarationRule }

function TTypeUsedBeforeDeclarationRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('type-used-before-declaration', TRuleSeverity.Error,
    'Typ wird benutzt, bevor er deklariert ist');
end;

procedure TTypeUsedBeforeDeclarationRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Finding: TForwardFinding;
  Message: string;
begin
  if (AContext.Tree = nil) or AContext.NoForwardDeclaration then
    Exit;
  for Finding in TForwardDeclarations.Analyze(AContext.Tree, AContext.Text) do
  begin
    if Finding.Issue <> TForwardIssue.UsedBeforeDeclaration then
      Continue;
    Message := Format('"%s" wird in %s benutzt, bevor es deklariert ist', [Finding.TypeName, Finding.UserName]);
    if Finding.Reason <> '' then
      Message := Message + Format(' (keine Korrektur: %s)', [Finding.Reason]);
    AReport.Add(Finding.Range, Message, FixesOf(Finding));
  end;
end;

{ TUnneededForwardDeclarationRule }

function TUnneededForwardDeclarationRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unneeded-forward-declaration', TRuleSeverity.Hint,
    'Überflüssige Forward-Deklaration');
end;

procedure TUnneededForwardDeclarationRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Finding: TForwardFinding;
begin
  if (AContext.Tree = nil) or AContext.NoForwardDeclaration then
    Exit;
  for Finding in TForwardDeclarations.Analyze(AContext.Tree, AContext.Text) do
    if Finding.Issue = TForwardIssue.UnneededForward then
      AReport.Add(Finding.Range, Format('Die Forward-Deklaration von "%s" wird nicht gebraucht: ' +
        '%s wird vor seiner Deklaration nicht benutzt', [Finding.TypeName, Finding.TypeName]), FixesOf(Finding));
end;

procedure RegisterForwardDeclarationRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TTypeUsedBeforeDeclarationRule.Create);
  ARegistry.Register(TUnneededForwardDeclarationRule.Create);
end;

end.
