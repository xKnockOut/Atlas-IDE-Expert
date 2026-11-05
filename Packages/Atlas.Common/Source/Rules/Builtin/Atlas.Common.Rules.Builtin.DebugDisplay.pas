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
  Atlas.Common.Rules.Derived,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDebugDisplayRuleText = (Title, Invalid, NoMember, NoChildMember);

const
  cTexts: array[TDebugDisplayRuleText] of TAtlasText = (
    (De: 'Wertdarstellung nennt unbekanntes Mitglied'; En: 'Value display names an unknown member'),
    (De: 'Ungültige Wertdarstellung: %s.'; En: 'Invalid value display: %s.'),
    (De: '%s hat kein Mitglied „%s“; der Platzhalter {%s} bleibt beim Debuggen leer.';
     En: '%s has no member “%s”; the placeholder {%s} stays empty while debugging.'),
    (De: '%s hat kein Mitglied „%s“ für die Unterelemente.'; En: '%s has no member “%s” for the child elements.'));

{$SCOPEDENUMS OFF}

{ TDebugDisplayPlaceholderRule }

function TDebugDisplayPlaceholderRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DebugDisplayPlaceholderRuleId, TRuleSeverity.Warning,
    cTexts[TDebugDisplayRuleText.Title].Text);
end;

/// <summary>Vorlage der Wertdarstellung; False (gemeldet), wenn sie ungültig ist. Ohne Vorlage eine leere.
/// </summary>
function ReadTemplate(const ALines: TArray<string>; const ASource: TDebugDisplaySource; const AReport: IRuleReport;
  out ATemplate: TDebugDisplayTemplate): Boolean;
var
  Segment: TDebugDisplaySegment;
  Column: Integer;
begin
  ATemplate := Default(TDebugDisplayTemplate);
  Result := True;
  if not ASource.HasTemplate then
  begin
    Exit;
  end;
  ATemplate := TDebugDisplayTemplate.Parse(ASource.Template);
  Result := ATemplate.Valid;
  if not Result then
  begin
    Segment := Default(TDebugDisplaySegment);
    Segment.Offset := ATemplate.ErrorOffset;
    Column := TDebugDisplayText.SourceColumn(ALines[ASource.TemplateLine], ASource.TemplateColumn, Segment);
    AReport.Add(TTextRange.Create(ASource.TemplateLine, Column, ASource.TemplateLine, Column + 1),
      cTexts[TDebugDisplayRuleText.Invalid].Fmt([ATemplate.Error]));
  end;
end;

/// <summary>Meldet Platzhalter, deren erster Name kein Mitglied des Typs ATypeName ist.</summary>
procedure CheckPlaceholders(const ALines: TArray<string>; const ASource: TDebugDisplaySource;
  const ATemplate: TDebugDisplayTemplate; const AMembers: TArray<TTypeMember>; const ATypeName: string;
  const AReport: IRuleReport);
var
  Segment: TDebugDisplaySegment;
  Root: string;
  Column: Integer;
begin
  for Segment in ATemplate.Placeholders do
  begin
    Root := Segment.Root;
    if (Root = '') or SameText(Root, 'Self') or TTypeMembers.Contains(AMembers, Root) then
    begin
      Continue;
    end;
    Column := TDebugDisplayText.SourceColumn(ALines[ASource.TemplateLine], ASource.TemplateColumn, Segment);
    AReport.Add(TTextRange.Create(ASource.TemplateLine, Column, ASource.TemplateLine, Column + Length(Root)),
      cTexts[TDebugDisplayRuleText.NoMember].Fmt([ATypeName, Root, Segment.Text]));
  end;
end;

/// <summary>Spalte (ab 1) des Namens AName in der children-Zeile ALine; 1, wenn er fehlt.</summary>
function ChildColumn(const ALine, AName: string): Integer;
begin
  Result := Pos(LowerCase(TDebugDisplayText.ChildrenKey), LowerCase(ALine));
  if Result > 0 then
  begin
    Result := Result + Length(TDebugDisplayText.ChildrenKey);
  end
  else
  begin
    Result := Pos('(', ALine) + 1;
  end;
  Result := Pos(LowerCase(AName), LowerCase(ALine), Result);
  if Result = 0 then
  begin
    Result := 1;
  end;
end;

/// <summary>Meldet Namen in children, die der Typ ATypeName nicht hat.</summary>
procedure CheckChildren(const ALines: TArray<string>; const ASource: TDebugDisplaySource;
  const AMembers: TArray<TTypeMember>; const ATypeName: string; const AReport: IRuleReport);
var
  Name: string;
  Found: Integer;
begin
  for Name in ASource.Children do
  begin
    if not TTypeMembers.Contains(AMembers, Name) then
    begin
      Found := ChildColumn(ALines[ASource.ChildrenLine], Name);
      AReport.Add(TTextRange.Create(ASource.ChildrenLine, Found - 1, ASource.ChildrenLine, Found - 1 + Length(Name)),
        cTexts[TDebugDisplayRuleText.NoChildMember].Fmt([ATypeName, Name]));
    end;
  end;
end;

procedure TDebugDisplayPlaceholderRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Local: TUnitIndex;
  Lines: TArray<string>;
  Symbol: TIndexSymbol;
  Source: TDebugDisplaySource;
  Template: TDebugDisplayTemplate;
  Members: TArray<TTypeMember>;
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
    if ReadTemplate(Lines, Source, AReport, Template) and
      TTypeMembers.Collect(Local, AContext.Index, Symbol, Members) then
    begin
      CheckPlaceholders(Lines, Source, Template, Members, Symbol.Name, AReport);
      CheckChildren(Lines, Source, Members, Symbol.Name, AReport);
    end;
  end;
end;

procedure RegisterDebugDisplayRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDebugDisplayPlaceholderRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.DebugDisplay', cTexts);

end.
