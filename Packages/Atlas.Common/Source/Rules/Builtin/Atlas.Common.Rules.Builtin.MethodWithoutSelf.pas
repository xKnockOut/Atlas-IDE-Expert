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
  Atlas.Common.Rules.Derived,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.MethodWithoutSelf,
  Atlas.Common.Editing.MethodWithoutSelf.Lookup,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TMethodWithoutSelfText = (Title, NoSelf);

const
  cTexts: array[TMethodWithoutSelfText] of TAtlasText = (
    (De: 'Methode braucht Self nicht'; En: 'Method does not need Self'),
    (De: '%s.%s braucht Self nicht: als class-Methode, freie Routine oder Record-Helper möglich.';
     En: '%s.%s does not need Self: possible as class method, free routine or record helper.'));

{$SCOPEDENUMS OFF}

const
  MethodWithoutSelfRuleId = 'method-without-self';

function TMethodWithoutSelfRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(MethodWithoutSelfRuleId, TRuleSeverity.Hint,
    cTexts[TMethodWithoutSelfText.Title].Text,
    True);
end;

/// <summary>Dateiname für die Namensauflösung: Pfad, sonst relativer Pfad, sonst Unit-Name.</summary>
function RuleFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
  begin
    Result := AContext.RelativePath;
  end;
  if Result = '' then
  begin
    Result := AContext.UnitName + '.pas';
  end;
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
    begin
      Before := AText[Position - 1];
    end;
    if Position + Length(AName) <= Length(AText) then
    begin
      After := AText[Position + Length(AName)];
    end;
    if not CharInSet(Before, ['A'..'Z', 'a'..'z', '0'..'9', '_']) and
      not CharInSet(After, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      Exit(True);
    end;
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
  begin
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AName) and
      not ((Index > 0) and (Tokens[Index - 1].IsKeyword('function') or Tokens[Index - 1].IsKeyword('procedure'))) then
    begin
      Result := Result + [Tokens[Index].Offset];
    end;
  end;
end;

/// <summary>Korrektur „als class-Methode“ für die geprüfte Datei; leer, wenn die Umformung scheitert.</summary>
function ClassMethodFixes(const AContext: TRuleContext; const AFileName: string; const ATarget: TMethodTarget;
  const ALookup: TMethodLookup): TArray<TRuleFix>;
var
  mConverted: TMethodResult;
  mReason: string;
  mItem: TMethodFileEdits;
begin
  Result := nil;
  if not TMethodWithoutSelf.Execute(TMethodSource.Create(AFileName, AContext.Text, AContext.Tree,
    NameOffsets(AContext.Tree, ATarget.Name)), nil, TMethodRequest.Create(ATarget.NamePosition,
    TMethodConversion.ClassMethod, AContext.MethodKindStatic, ALookup, AContext.Formatting), mConverted,
    mReason) then
  begin
    Exit;
  end;
  for mItem in mConverted.Files do
  begin
    if SameText(mItem.FileName, AFileName) and (mItem.Edits <> nil) then
    begin
      Result := [TRuleFix.Create(TMethodWithoutSelf.ClassMethodTitle, mItem.Edits, False)];
    end;
  end;
end;

procedure TMethodWithoutSelfRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  FileName, FormText: string;
  Lookup: TMethodLookup;
  Target: TMethodTarget;
  Fixes: TArray<TRuleFix>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or AContext.NoMethodKind then
  begin
    Exit;
  end;
  FileName := RuleFileName(AContext);
  FormText := AContext.FormText;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
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
      Fixes := ClassMethodFixes(AContext, FileName, Target, Lookup);
      // Mittel: Aufrufe über Methodenzeiger in anderen Units sieht die Regel nicht.
      AReport.Add(TTextRange.Create(Target.NamePosition, TTextPosition.Create(Target.NamePosition.Line,
        Target.NamePosition.Character + Length(Target.Name))),
          cTexts[TMethodWithoutSelfText.NoSelf].Fmt([Target.ClassName, Target.Name]),
        TRuleConfidence.Medium, Fixes);
    end;
  finally
    Resolver.UnpinTree;
  end;
end;

procedure RegisterMethodWithoutSelfRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TMethodWithoutSelfRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.MethodWithoutSelf', cTexts);

end.
