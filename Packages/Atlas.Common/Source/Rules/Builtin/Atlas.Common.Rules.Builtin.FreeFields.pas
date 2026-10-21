unit Atlas.Common.Rules.Builtin.FreeFields;

// Felder im Destruktor freigeben (#666):
//   owned-field-not-freed     im Konstruktor erzeugtes Objektfeld, das die
//                             Klasse nirgends freigibt; Korrektur „Im
//                             Destruktor freigeben“
//   owned-field-free-unclear  erzeugtes Feld, das zurückgegeben oder
//                             weitergereicht wird; ob die Klasse es freigeben
//                             muss, entscheidet der Entwickler (ohne Aktion)
//
// Erkennung und Änderungen liefert TFreeFields (Editing). Mit
// refactoring.freeFields aus schweigen beide Regeln.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TOwnedFieldNotFreedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TOwnedFieldFreeUnclearRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterFreeFieldRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.FreeFields;

{ TOwnedFieldNotFreedRule }

function TOwnedFieldNotFreedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('owned-field-not-freed', TRuleSeverity.Warning,
    'Im Konstruktor erzeugtes Feld wird nicht freigegeben');
end;

procedure TOwnedFieldNotFreedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Field: TOwnedField;
  Style: TFreeFieldsStyle;
  Edits: TArray<TTextEdit>;
  Fixes: TArray<TRuleFix>;
begin
  if (AContext.Tree = nil) or AContext.NoFreeFields then
    Exit;
  Style := TFreeFieldsStyle.Free;
  if AContext.FreeFieldsFreeAndNil then
    Style := TFreeFieldsStyle.FreeAndNil;
  for Field in TFreeFields.Analyze(AContext.Tree, AContext.Text, AContext.Index) do
  begin
    if Field.State <> TOwnedFieldState.NotFreed then
      Continue;
    Fixes := nil;
    // Nicht sicher: Ob die Klasse das Objekt besitzt, weiß nur der Entwickler.
    if TFreeFields.Edits(AContext.Tree, AContext.Text, [Field], Style, Edits) then
      Fixes := [TRuleFix.Create(TFreeFields.FieldTitle, Edits, False)];
    AReport.Add(Field.Range, Format('"%s" wird in %s erzeugt, aber in %s nirgends freigegeben',
      [Field.Name, Field.CreatedIn, Field.ClassName]), Fixes);
  end;
end;

{ TOwnedFieldFreeUnclearRule }

function TOwnedFieldFreeUnclearRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('owned-field-free-unclear', TRuleSeverity.Hint,
    'Unklar, ob ein erzeugtes Feld freigegeben werden muss');
end;

procedure TOwnedFieldFreeUnclearRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Field: TOwnedField;
begin
  if (AContext.Tree = nil) or AContext.NoFreeFields then
    Exit;
  for Field in TFreeFields.Analyze(AContext.Tree, AContext.Text, AContext.Index) do
    if Field.State = TOwnedFieldState.Unclear then
      AReport.Add(Field.Range, Format('"%s" wird in %s erzeugt und nicht freigegeben; ob %s es freigeben muss, ' +
        'ist unklar: Es %s', [Field.Name, Field.CreatedIn, Field.ClassName, Field.Reason]));
end;

procedure RegisterFreeFieldRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOwnedFieldNotFreedRule.Create);
  ARegistry.Register(TOwnedFieldFreeUnclearRule.Create);
end;

end.
