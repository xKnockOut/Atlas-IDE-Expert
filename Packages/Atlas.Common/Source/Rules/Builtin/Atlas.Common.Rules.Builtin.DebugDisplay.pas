unit Atlas.Common.Rules.Builtin.DebugDisplay;

// Regel debug-display-placeholder (#854): Wertdarstellungen beim Debuggen
// (// atlas-debug: '…', [AtlasDebugDisplay('…')], // atlas-debug-children: …)
// nennen nur Mitglieder, die der Typ hat. Gemeldet werden
// - eine ungültige Vorlage (offene oder leere Klammer) an der Fehlerstelle,
// - ein Platzhalter, dessen erster Name kein Feld, keine Eigenschaft und
//   keine Methode des Typs oder eines Vorfahren ist,
// - ein Name in children, den der Typ nicht hat.
// Vorfahren kommen aus der eigenen Unit oder dem Index. Ist ein Vorfahr
// unbekannt (kein Index, Unit nicht indiziert), schweigt die Regel für den
// Typ; für TObject gelten seine bekannten Methoden.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  DebugDisplayPlaceholderRuleId = 'debug-display-placeholder';

type
  TDebugDisplayPlaceholderRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterDebugDisplayRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Text.DebugDisplay,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.TypeMembers,
  Atlas.Common.Rules.Derived;

{ TDebugDisplayPlaceholderRule }

function TDebugDisplayPlaceholderRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DebugDisplayPlaceholderRuleId, TRuleSeverity.Warning,
    'Wertdarstellung nennt unbekanntes Mitglied');
end;

procedure TDebugDisplayPlaceholderRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Local: TUnitIndex;
  Lines: TArray<string>;
  Symbol: TIndexSymbol;
  Source: TDebugDisplaySource;
  Template: TDebugDisplayTemplate;
  Segment: TDebugDisplaySegment;
  Members: TArray<TTypeMember>;
  Line, Name, Root: string;
  Column, Found: Integer;
begin
  if (AContext.Tree = nil) or not (ContainsText(AContext.Text, 'atlas-debug')
    or ContainsText(AContext.Text, 'AtlasDebug')) then
  begin
    Exit;
  end;
  Local := TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext);
  Lines := TTextLines.SplitLines(AContext.Text);
  for Symbol in Local.Symbols do
  begin
    if not (Symbol.Kind in TTypeMembers.RuleKinds) or (Symbol.FileName <> '')
      or not TDebugDisplayText.RuleAbove(Lines, Symbol.Range.StartPos.Line, Source) then
    begin
      Continue;
    end;
    Template := Default(TDebugDisplayTemplate);
    if Source.HasTemplate then
    begin
      Line := Lines[Source.TemplateLine];
      Template := TDebugDisplayTemplate.Parse(Source.Template);
      if not Template.Valid then
      begin
        Segment := Default(TDebugDisplaySegment);
        Segment.Offset := Template.ErrorOffset;
        Column := TDebugDisplayText.SourceColumn(Line, Source.TemplateColumn, Segment);
        AReport.Add(TTextRange.Create(Source.TemplateLine, Column, Source.TemplateLine, Column + 1),
          Format('Ungültige Wertdarstellung: %s.', [Template.Error]));
        Continue;
      end;
    end;
    if not TTypeMembers.Collect(Local, AContext.Index, Symbol, Members) then
    begin
      Continue;
    end;
    for Segment in Template.Placeholders do
    begin
      Root := Segment.Root;
      if (Root = '') or SameText(Root, 'Self') or TTypeMembers.Contains(Members, Root) then
      begin
        Continue;
      end;
      Column := TDebugDisplayText.SourceColumn(Lines[Source.TemplateLine], Source.TemplateColumn, Segment);
      AReport.Add(TTextRange.Create(Source.TemplateLine, Column, Source.TemplateLine, Column + Length(Root)),
        Format('%s hat kein Mitglied „%s“; der Platzhalter {%s} bleibt beim Debuggen leer.',
        [Symbol.Name, Root, Segment.Text]));
    end;
    for Name in Source.Children do
    begin
      if TTypeMembers.Contains(Members, Name) then
      begin
        Continue;
      end;
      Line := Lines[Source.ChildrenLine];
      Found := Pos(LowerCase(TDebugDisplayText.ChildrenKey), LowerCase(Line));
      if Found > 0 then
      begin
        Found := Found + Length(TDebugDisplayText.ChildrenKey);
      end
      else
      begin
        Found := Pos('(', Line) + 1;
      end;
      Found := Pos(LowerCase(Name), LowerCase(Line), Found);
      if Found = 0 then
      begin
        Found := 1;
      end;
      AReport.Add(TTextRange.Create(Source.ChildrenLine, Found - 1, Source.ChildrenLine, Found - 1 + Length(Name)),
        Format('%s hat kein Mitglied „%s“ für die Unterelemente.', [Symbol.Name, Name]));
    end;
  end;
end;

procedure RegisterDebugDisplayRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDebugDisplayPlaceholderRule.Create);
end;

end.
