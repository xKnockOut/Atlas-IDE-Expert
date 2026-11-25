unit Atlas.Common.Editing.ExplicitType;

// „Typ ausschreiben“ (#453): setzt hinter eine Inline-Variable ohne
// Typangabe ": Typ" mit dem abgeleiteten Typ (Semantics.InferredTypes) und
// trägt die Units der Namen im Typ ins uses ein, die dort noch nicht sichtbar
// sind (#180).

interface

uses
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver;

type
  TExplicitType = record
  public
    /// <summary>„Typ ausschreiben“ (#453) für die Inline-Variable, auf deren Namen APosition steht: fügt
    /// ": Typ" ein und trägt fehlende Units des Typs ins uses ein. False ohne Treffer.</summary>
    class function Action(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition; const ALineBreak: string; out AAction: TCodeAction): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Pascal.UsesClauses,
  Atlas.Common.Pascal.UsesEdits,
  Atlas.Common.Semantics.InferredTypes;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TExplicitTypeText = (WriteOutTheType);

const
  cTexts: array[TExplicitTypeText] of TAtlasText = (
    (De: 'Typ ausschreiben'; En: 'Write out the type'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Was „Typ ausschreiben“ für die uses-Einträge braucht.</summary>
  TTypeUnits = record
    Resolver: TNameResolver;
    Tokens: TArray<TPascalToken>;
    /// <summary>Offset des Variablennamens: dort beginnt die Suche nach dem uses-Abschnitt.</summary>
    Offset: Integer;
    Own: TUnitIndex;
    OwnName: string;
    Used: TArray<string>;
    Found: TInferredType;
    /// <summary>Typname ohne Typargumente.</summary>
    Base: string;
  end;

/// <summary>Unit, aus der das Wort AWord des Typs stammt, wenn es hier noch nicht sichtbar ist; '' sonst.</summary>
function UnitOfWord(const AUnits: TTypeUnits; const AWord: string): string;
var
  mResolved: TResolvedSymbol;
  mFromUnit: TUnitIndex;
begin
  Result := '';
  if MatchText(AWord, ['array', 'of', 'string']) or AUnits.Resolver.ResolveTypeFrom(AUnits.Own, AWord, mResolved) then
  begin
    Exit;
  end;
  if SameText(AWord, AUnits.Base) and (AUnits.Found.TypeUnit <> '') then
  begin
    Result := AUnits.Found.TypeUnit;
  end
  else if (AUnits.Found.Origin.Name <> '') and AUnits.Resolver.DeclaringUnit(AUnits.Found.Origin, mFromUnit) and
    AUnits.Resolver.ResolveTypeFrom(mFromUnit, AWord, mResolved) and not mResolved.Builtin then
  begin
    Result := mResolved.UnitName;
  end;
end;

/// <summary>uses-Einträge für die Units der Namen im Typ (#180), die hier noch nicht sichtbar sind.</summary>
function TypeUnitEdits(const AUnits: TTypeUnits; const ALineBreak: string): TArray<TTextEdit>;
var
  mWord, mUnitName: string;
  mAdded: TArray<string>;
  mEdit: TTextEdit;
begin
  Result := nil;
  mAdded := nil;
  for mWord in AUnits.Found.TypeName.Split([' ', '<', '>', ',', '^', '[', ']', '(', ')'],
    TStringSplitOptions.ExcludeEmpty) do
  begin
    mUnitName := UnitOfWord(AUnits, mWord);
    if (mUnitName = '') or MatchText(mUnitName, [AUnits.OwnName, 'System']) or
      TPascalUses.IsUsed(AUnits.Used, mUnitName, AUnits.Resolver.Namespaces) or (IndexText(mUnitName, mAdded) >= 0)
    then
    begin
      Continue;
    end;
    if TPascalUsesEdits.AddUnit(AUnits.Tokens, AUnits.Offset, mUnitName, ALineBreak, mEdit) then
    begin
      Result := Result + [mEdit];
      mAdded := mAdded + [mUnitName];
    end;
  end;
end;

{ TExplicitType }

class function TExplicitType.Action(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; const ALineBreak: string;
  out AAction: TCodeAction): Boolean;
var
  mUnits: TTypeUnits;
begin
  AAction := Default(TCodeAction);
  mUnits := Default(TTypeUnits);
  Result := (ATree <> nil) and (ATree.Root <> nil) and TInferredTypes.At(AResolver, ATree, AFileName, APosition,
    mUnits.Found);
  if not Result then
  begin
    Exit;
  end;
  AAction.Title := cTexts[TExplicitTypeText.WriteOutTheType].Text;
  AAction.Kind := cRewriteKind;
  AAction.Edits := [TTextEdit.Create(TTextRange.Create(mUnits.Found.NameEnd, mUnits.Found.NameEnd),
    ': ' + mUnits.Found.TypeName)];
  mUnits.Resolver := AResolver;
  mUnits.Tokens := ATree.Tokens;
  mUnits.Offset := TokenOffsetAt(mUnits.Tokens, mUnits.Found.NameStart);
  mUnits.Own := AResolver.ExtractedUnit(ATree, AFileName);
  mUnits.OwnName := TPascalUses.OwnName(mUnits.Tokens);
  mUnits.Used := TPascalUses.UsedUnits(mUnits.Tokens);
  mUnits.Base := mUnits.Found.TypeName;
  if Pos('<', mUnits.Base) > 0 then
  begin
    mUnits.Base := Copy(mUnits.Base, 1, Pos('<', mUnits.Base) - 1);
  end;
  AAction.Edits := AAction.Edits + TypeUnitEdits(mUnits, ALineBreak);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.ExplicitType', cTexts);

end.
