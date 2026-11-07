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
  cDebugDisplayPlaceholderRuleId = 'debug-display-placeholder';

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
  Result := TRuleDescriptor.Create(cDebugDisplayPlaceholderRuleId, TRuleSeverity.Warning,
    cTexts[TDebugDisplayRuleText.Title].Text);
end;

/// <summary>Vorlage der Wertdarstellung; False (gemeldet), wenn sie ungültig ist. Ohne Vorlage eine leere.
/// </summary>
function ReadTemplate(const ALines: TArray<string>; const ASource: TDebugDisplaySource; const AReport: IRuleReport;
  out ATemplate: TDebugDisplayTemplate): Boolean;
var
  mSegment: TDebugDisplaySegment;
  mColumn: Integer;
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
    mSegment := Default(TDebugDisplaySegment);
    mSegment.Offset := ATemplate.ErrorOffset;
    mColumn := TDebugDisplayText.SourceColumn(ALines[ASource.TemplateLine], ASource.TemplateColumn, mSegment);
    AReport.Add(TTextRange.Create(ASource.TemplateLine, mColumn, ASource.TemplateLine, mColumn + 1),
      cTexts[TDebugDisplayRuleText.Invalid].Fmt([ATemplate.Error]));
  end;
end;

/// <summary>Meldet Platzhalter, deren erster Name kein Mitglied des Typs ATypeName ist.</summary>
procedure CheckPlaceholders(const ALines: TArray<string>; const ASource: TDebugDisplaySource;
  const ATemplate: TDebugDisplayTemplate; const AMembers: TArray<TTypeMember>; const ATypeName: string;
  const AReport: IRuleReport);
var
  mSegment: TDebugDisplaySegment;
  mRoot: string;
  mColumn: Integer;
begin
  for mSegment in ATemplate.Placeholders do
  begin
    mRoot := mSegment.Root;
    if (mRoot = '') or SameText(mRoot, 'Self') or TTypeMembers.Contains(AMembers, mRoot) then
    begin
      Continue;
    end;
    mColumn := TDebugDisplayText.SourceColumn(ALines[ASource.TemplateLine], ASource.TemplateColumn, mSegment);
    AReport.Add(TTextRange.Create(ASource.TemplateLine, mColumn, ASource.TemplateLine, mColumn + Length(mRoot)),
      cTexts[TDebugDisplayRuleText.NoMember].Fmt([ATypeName, mRoot, mSegment.Text]));
  end;
end;

/// <summary>Spalte (ab 1) des Namens AName in der children-Zeile ALine; 1, wenn er fehlt.</summary>
function ChildColumn(const ALine, AName: string): Integer;
begin
  Result := Pos(LowerCase(TDebugDisplayText.cChildrenKey), LowerCase(ALine));
  if Result > 0 then
  begin
    Result := Result + Length(TDebugDisplayText.cChildrenKey);
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
  mName: string;
  mFound: Integer;
begin
  for mName in ASource.Children do
  begin
    if not TTypeMembers.Contains(AMembers, mName) then
    begin
      mFound := ChildColumn(ALines[ASource.ChildrenLine], mName);
      AReport.Add(TTextRange.Create(ASource.ChildrenLine, mFound - 1, ASource.ChildrenLine, mFound - 1 + Length(mName)),
        cTexts[TDebugDisplayRuleText.NoChildMember].Fmt([ATypeName, mName]));
    end;
  end;
end;

procedure TDebugDisplayPlaceholderRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mLocal: TUnitIndex;
  mLines: TArray<string>;
  mSymbol: TIndexSymbol;
  mSource: TDebugDisplaySource;
  mTemplate: TDebugDisplayTemplate;
  mMembers: TArray<TTypeMember>;
begin
  if (AContext.Tree = nil) or not (ContainsText(AContext.Text, 'atlas-debug')
    or ContainsText(AContext.Text, 'AtlasDebug')) then
  begin
    Exit;
  end;
  mLocal := TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext);
  mLines := TTextLines.SplitLines(AContext.Text);
  for mSymbol in mLocal.Symbols do
  begin
    if not (mSymbol.Kind in TTypeMembers.cRuleKinds) or (mSymbol.FileName <> '')
      or not TDebugDisplayText.RuleAbove(mLines, mSymbol.Range.StartPos.Line, mSource) then
    begin
      Continue;
    end;
    if ReadTemplate(mLines, mSource, AReport, mTemplate) and
      TTypeMembers.Collect(mLocal, AContext.Index, mSymbol, mMembers) then
    begin
      CheckPlaceholders(mLines, mSource, mTemplate, mMembers, mSymbol.Name, AReport);
      CheckChildren(mLines, mSource, mMembers, mSymbol.Name, AReport);
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
