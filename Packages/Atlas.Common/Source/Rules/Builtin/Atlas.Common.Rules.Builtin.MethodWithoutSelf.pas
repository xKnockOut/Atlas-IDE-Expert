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
  System.StrUtils,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.MethodWithoutSelf,
  Atlas.Common.Editing.MethodWithoutSelf.Contract,
  Atlas.Common.Editing.MethodWithoutSelf.Lookup,
  Atlas.Common.Editing.PromoteVariable,
  Atlas.Common.Pascal.EventAssignments,
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
  cMethodWithoutSelfRuleId = 'method-without-self';

function TMethodWithoutSelfRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cMethodWithoutSelfRuleId, TRuleSeverity.Hint,
    cTexts[TMethodWithoutSelfText.Title].Text);
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
  mPosition: Integer;
  mBefore, mAfter: Char;
begin
  Result := False;
  mPosition := Pos(UpperCase(AName), UpperCase(AText));
  while mPosition > 0 do
  begin
    mBefore := ' ';
    mAfter := ' ';
    if mPosition > 1 then
    begin
      mBefore := AText[mPosition - 1];
    end;
    if mPosition + Length(AName) <= Length(AText) then
    begin
      mAfter := AText[mPosition + Length(AName)];
    end;
    if not CharInSet(mBefore, ['A'..'Z', 'a'..'z', '0'..'9', '_']) and
      not CharInSet(mAfter, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      Exit(True);
    end;
    mPosition := Pos(UpperCase(AName), UpperCase(AText), mPosition + 1);
  end;
end;

/// <summary>Verwendungen von AName in der Unit: jeder Bezeichner gleichen Namens außer dem Namen direkt hinter
/// procedure/function. Lieber zu viele: Eine fremde Verwendung macht die Umwandlung höchstens unmöglich.</summary>
function NameOffsets(ATree: TSyntaxTree; const AName: string): TArray<Integer>;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  Result := nil;
  mTokens := ATree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mIndex].Text, AName) and
      not ((mIndex > 0) and (mTokens[mIndex - 1].IsKeyword('function') or mTokens[mIndex - 1].IsKeyword('procedure'))) then
    begin
      Result := Result + [mTokens[mIndex].Offset];
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

/// <summary>Ist AName ein Ereignis der Formulardatei AFormText oder wird es in ATree einem Ereignis zugewiesen?
/// </summary>
function EventCheck(const AFormText: string; ATree: TSyntaxTree): TPromoteInFormFunc;
var
  mAssigned: TArray<string>;
begin
  mAssigned := TEventAssignments.Names(ATree.Tokens);
  Result :=
    function(const AName: string): Boolean
    begin
      Result := MentionsWord(AFormText, AName) or (IndexText(AName, mAssigned) >= 0);
    end;
end;

procedure TMethodWithoutSelfRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName, mFormText: string;
  mLookup: TMethodLookup;
  mTarget: TMethodTarget;
  mFixes: TArray<TRuleFix>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or AContext.NoMethodKind then
  begin
    Exit;
  end;
  mFileName := RuleFileName(AContext);
  mFormText := AContext.FormText;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mResolver.PinTree(AContext.Tree, mFileName);
  try
    mLookup := TMethodLookup.FromResolver(mResolver, AContext.Tree, mFileName);
    // Ereignisse der Formulardatei und im Code zugewiesene Ereignisse brauchen eine Methode des Objekts.
    mLookup.InForm := EventCheck(mFormText, AContext.Tree);
    for mTarget in TMethodWithoutSelf.Candidates(AContext.Text, AContext.Tree, mLookup) do
    begin
      mFixes := ClassMethodFixes(AContext, mFileName, mTarget, mLookup);
      // Mittel: Aufrufe über Methodenzeiger in anderen Units sieht die Regel nicht.
      AReport.Add(TTextRange.Create(mTarget.NamePosition, TTextPosition.Create(mTarget.NamePosition.Line,
        mTarget.NamePosition.Character + Length(mTarget.Name))),
          cTexts[TMethodWithoutSelfText.NoSelf].Fmt([mTarget.ClassName, mTarget.Name]),
        TRuleConfidence.Medium, mFixes);
    end;
  finally
    mResolver.UnpinTree;
  end;
end;

procedure RegisterMethodWithoutSelfRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TMethodWithoutSelfRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.MethodWithoutSelf', cTexts);

end.
