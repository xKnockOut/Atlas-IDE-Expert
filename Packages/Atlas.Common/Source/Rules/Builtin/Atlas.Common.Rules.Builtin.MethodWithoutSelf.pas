unit Atlas.Common.Rules.Builtin.MethodWithoutSelf;

// Methode ohne Self (#686):
//   method-without-self  Methode einer Klasse oder eines Records, die weder
//                        Self noch Instanzmitglieder braucht; Hinweis,
//                        experimentell (nur eingeschaltet in atlas.json).
//                        Korrektur „In class-Methode umwandeln“ (nicht
//                        sicher): Aufrufe über Instanzen bleiben gültig,
//                        darum ändert sie nur die Unit selbst. Die übrigen
//                        Umwandlungen (freie Routine, Record-Helper, Aufrufe
//                        über die Klasse) ändern auch andere Units und gibt
//                        es nur als Code-Aktion mit Vorschau.
//
// Erkennung und Änderungen liefert TMethodWithoutSelf (Editing), Mitglieder
// über die Namensauflösung. Mit refactoring.methodKind aus schweigt die
// Regel.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TMethodWithoutSelfRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterMethodWithoutSelfRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.MethodWithoutSelf;

const
  MethodWithoutSelfRuleId = 'method-without-self';

function TMethodWithoutSelfRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(MethodWithoutSelfRuleId, TRuleSeverity.Hint, 'Methode braucht Self nicht',
    True);
end;

/// <summary>Dateiname für die Namensauflösung: Pfad, sonst relativer Pfad, sonst Unit-Name.</summary>
function RuleFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
    Result := AContext.RelativePath;
  if Result = '' then
    Result := AContext.UnitName + '.pas';
end;

/// <summary>Steht AName als ganzes Wort (ohne Groß-/Kleinschreibung) in AText?</summary>
function MentionsWord(const AText, AName: string): Boolean;
var
  Position: Integer;
  Before, After: Char;
begin
  Result := False;
  Position := Pos(UpperCase(AName), UpperCase(AText));
  while Position > 0 do
  begin
    Before := ' ';
    After := ' ';
    if Position > 1 then
      Before := AText[Position - 1];
    if Position + Length(AName) <= Length(AText) then
      After := AText[Position + Length(AName)];
    if not CharInSet(Before, ['A'..'Z', 'a'..'z', '0'..'9', '_']) and
      not CharInSet(After, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Exit(True);
    Position := Pos(UpperCase(AName), UpperCase(AText), Position + 1);
  end;
end;

/// <summary>Verwendungen von AName in der Unit: jeder Bezeichner gleichen Namens außer dem Namen direkt hinter
/// procedure/function. Lieber zu viele: Eine fremde Verwendung macht die Umwandlung höchstens unmöglich.</summary>
function NameOffsets(ATree: TSyntaxTree; const AName: string): TArray<Integer>;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
begin
  Result := nil;
  Tokens := ATree.Tokens;
  for Index := 0 to High(Tokens) do
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AName) and
      not ((Index > 0) and (Tokens[Index - 1].IsKeyword('function') or Tokens[Index - 1].IsKeyword('procedure'))) then
      Result := Result + [Tokens[Index].Offset];
end;

procedure TMethodWithoutSelfRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  FileName, FormText, Reason: string;
  Lookup: TMethodLookup;
  Target: TMethodTarget;
  Converted: TMethodResult;
  Fixes: TArray<TRuleFix>;
  Item: TMethodFileEdits;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or AContext.NoMethodKind then
    Exit;
  FileName := RuleFileName(AContext);
  FormText := AContext.FormText;
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Lookup := TMethodLookup.FromResolver(Resolver, AContext.Tree, FileName);
      // Ereignisse der Formulardatei brauchen eine Methode des Objekts.
      Lookup.InForm :=
        function(const AName: string): Boolean
        begin
          Result := MentionsWord(FormText, AName);
        end;
      for Target in TMethodWithoutSelf.Candidates(AContext.Text, AContext.Tree, Lookup) do
      begin
        Fixes := nil;
        if TMethodWithoutSelf.Execute(TMethodSource.Create(FileName, AContext.Text, AContext.Tree,
          NameOffsets(AContext.Tree, Target.Name)), nil, Target.NamePosition, TMethodConversion.ClassMethod,
          AContext.MethodKindStatic, Lookup, AContext.Formatting, Converted, Reason) then
          for Item in Converted.Files do
            if SameText(Item.FileName, FileName) and (Item.Edits <> nil) then
              Fixes := [TRuleFix.Create(TMethodWithoutSelf.ClassMethodTitle, Item.Edits, False)];
        // Mittel: Aufrufe über Methodenzeiger in anderen Units sieht die Regel nicht.
        AReport.Add(TTextRange.Create(Target.NamePosition, TTextPosition.Create(Target.NamePosition.Line,
          Target.NamePosition.Character + Length(Target.Name))), Format('%s.%s braucht Self nicht: als ' +
          'class-Methode, freie Routine oder Record-Helper möglich.', [Target.ClassName, Target.Name]),
          TRuleConfidence.Medium, Fixes);
      end;
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

procedure RegisterMethodWithoutSelfRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TMethodWithoutSelfRule.Create);
end;

end.
