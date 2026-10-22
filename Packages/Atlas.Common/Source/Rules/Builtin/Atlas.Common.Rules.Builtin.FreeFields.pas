unit Atlas.Common.Rules.Builtin.FreeFields;

// Felder im Destruktor freigeben (#666):
//   field-not-freed           im Konstruktor erzeugtes Objektfeld, das die
//                             Klasse nirgends freigibt; Korrektur „Im
//                             Destruktor freigeben“. Bis #918 hieß die Regel
//                             owned-field-not-freed (Alias). Komponenten mit
//                             Owner, Interfaces und Klassen aus ignoreTypes
//                             bleiben stumm.
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
  Atlas.Common.Rules.Registry,
  Atlas.Common.Editing.FreeFields;

type
  TOwnedFieldNotFreedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>True, wenn AField eine Klasse aus AIgnoreTypes erzeugt oder so deklariert ist (#918).</summary>
    class function Ignored(const AField: TOwnedField; const AIgnoreTypes: TArray<string>): Boolean; static;
  end;

  TOwnedFieldFreeUnclearRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterFreeFieldRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Options;

{ TOwnedFieldNotFreedRule }

function TOwnedFieldNotFreedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('field-not-freed', TRuleSeverity.Warning,
    'Im Konstruktor erzeugtes Feld wird nicht freigegeben');
end;

class function TOwnedFieldNotFreedRule.Ignored(const AField: TOwnedField; const AIgnoreTypes: TArray<string>): Boolean;
var
  Declared: string;
begin
  // Generische Typen vergleichen ohne Typparameter: TObjectList<TFoo> -> TObjectList.
  Declared := AField.TypeName;
  if Pos('<', Declared) > 0 then
    Declared := Copy(Declared, 1, Pos('<', Declared) - 1);
  Result := MatchText(Trim(AField.CreatedType), AIgnoreTypes) or MatchText(Trim(Declared), AIgnoreTypes) or
    MatchText(Trim(AField.TypeName), AIgnoreTypes);
end;

procedure TOwnedFieldNotFreedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Field: TOwnedField;
  Style: TFreeFieldsStyle;
  Edits: TArray<TTextEdit>;
  Fixes: TArray<TRuleFix>;
  IgnoreTypes: TArray<string>;
begin
  if (AContext.Tree = nil) or AContext.NoFreeFields then
    Exit;
  IgnoreTypes := TRuleOptions.Strings(AContext.Options, 'ignoreTypes', nil);
  Style := TFreeFieldsStyle.Free;
  if AContext.FreeFieldsFreeAndNil then
    Style := TFreeFieldsStyle.FreeAndNil;
  for Field in TFreeFields.Analyze(AContext.Tree, AContext.Text, AContext.Index) do
  begin
    if (Field.State <> TOwnedFieldState.NotFreed) or Ignored(Field, IgnoreTypes) then
      Continue;
    Fixes := nil;
    // Nicht sicher: Ob die Klasse das Objekt besitzt, weiß nur der Entwickler.
    if TFreeFields.Edits(AContext.Tree, AContext.Text, [Field], Style, Edits) then
      Fixes := [TRuleFix.Create(TFreeFields.FieldTitle, Edits, False)];
    // Mittel: Ob das Objekt anderswo freigegeben wird, sieht die Regel nicht immer.
    AReport.Add(Field.Range, Format('%s wird im Konstruktor erzeugt, aber im Destruktor nicht freigegeben ' +
      '(Speicherleck).', [Field.Name]), TRuleConfidence.Medium, Fixes);
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
