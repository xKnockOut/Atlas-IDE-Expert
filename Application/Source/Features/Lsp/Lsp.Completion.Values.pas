unit Lsp.Completion.Values;

// Werte in der Vervollständigung: Aufzählungen und Mengen (#448), fehlende case-Zweige (#449, #50), Muster
// fortsetzen (#671) und „Alle Felder zuweisen“ (#491); unbekannte Namen deklariert Editing (#471). Die
// Aufzählungstypen selbst löst Atlas.Common.Semantics.EnumTypes auf.
// Teil der Vervollständigung (Lsp.Completion).

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Completion.Request,
  Atlas.Common.Completion.Contract;

type
  TCompletionValues = class
  public
    /// <summary>Aufzählungen und Mengen (#448). Erwartet die Stelle einen Aufzählungstyp (Zuweisung, Parameter,
    /// Vergleich, case-Zweig), kommen dessen Werte in Deklarationsreihenfolge (Ordinal, bei {$SCOPEDENUMS ON} mit
    /// Typpräfix im InsertText). In einem Mengenkonstruktor ("Anchors := [akLeft, ") kommen alle Werte des
    /// Elementtyps mit SetOf, SetChecked und SetRange; ASetMode ist dann True. False ohne Aufzählungstyp.</summary>
    class function EnumItems(ARequest: TCompletionRequest; out AItems: TArray<TCompletionItem>;
      out ASetMode: Boolean): Boolean; static;
    /// <summary>„Alle Felder zuweisen (n)“ (#491) hinter "Ausdruck." am Anfang einer Anweisung, wenn der Ausdruck
    /// ein Record oder eine Klasse ist und completion.assignAllFields gilt: je öffentlich beschreibbarem Feld und
    /// jeder Property eine Zuweisung, in Deklarationsreihenfolge; was die folgenden Zeilen schon zuweisen, fällt
    /// weg. Mit ASnippets im Platzhalter-Modus; mehr als 15 Felder kommen als Assignments für die Liste mit
    /// Kontrollkästchen. False außerhalb dieses Kontexts oder ohne Felder.</summary>
    class function AssignAllItem(ARequest: TCompletionRequest; ASnippets: Boolean;
      out AItem: TCompletionItem): Boolean; static;
  end;


implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ExpectedTypes,
  Atlas.Common.Semantics.EnumTypes,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Text.Lines,
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.CaseCompletion,
  Atlas.Common.Semantics.AssignFields,
  Atlas.Common.Completion.FuzzyMatch,
  Lsp.CompletionCollector,
  Atlas.Common.Pascal.EnumSlots,
  Lsp.Completion.Context,
  Atlas.Common.Pascal.TypeTexts;

type
  /// <summary>Texte der Werte-Vervollständigung in beiden Sprachen (#1458).</summary>
  TValuesText = (FillMissing, InsertAll);

const
  cTexts: array[TValuesText] of TAtlasText = (
    (De: 'Fehlende Werte ergänzen (%d)'; En: 'Add missing values (%d)'),
    (De: 'Alle Werte einfügen'; En: 'Insert all values'));

/// <summary>Eintrag für den Wert AIndex von AEnum.</summary>
function EnumItem(const AEnum: TEnumType; AIndex: Integer): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := AEnum.Values[AIndex];
  Result.Kind := cKindEnumMember;
  Result.Detail := AEnum.Name;
  Result.Container := AEnum.Name;
  Result.Ordinal := AIndex + 1;
  Result.Fits := True;
  if AEnum.Scoped then
  begin
    Result.InsertText := AEnum.Name + '.' + AEnum.Values[AIndex];
  end;
  if AEnum.Positions[AIndex].Line >= 0 then
  begin
    Result.SourceFile := AEnum.FileName;
    Result.SourcePosition := AEnum.Positions[AIndex];
  end;
end;

/// <summary>„Alle Werte einfügen“ bzw. „Fehlende Werte ergänzen (n)“ am Anfang eines case-Zweigs (#449).</summary>
function CaseItem(const AEnum: TEnumType; const AText: string; const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition; out AItem: TCompletionItem): Boolean;
var
  mSlot: TCaseBranchSlot;
  mMissing: TArray<string>;
  mPrefix, mLineBreak, mEndText: string;
begin
  AItem := Default(TCompletionItem);
  Result := TCaseCompletion.BranchSlot(AText, ATokens, APosition, mSlot) and
    TCaseCompletion.Missing(AEnum.Values, mSlot.Labels, mMissing) and (mMissing <> nil);
  if not Result then
  begin
    Exit;
  end;
  mLineBreak := TTextLines.LineBreakOf(AText);
  mPrefix := '';
  if AEnum.Scoped then
  begin
    mPrefix := AEnum.Name + '.';
  end;
  AItem.Name := cTexts[TValuesText.FillMissing].Fmt([Length(mMissing)]);
  if mSlot.Labels = nil then
  begin
    AItem.Name := cTexts[TValuesText.InsertAll].Text;
    AItem.Count := Length(mMissing);
  end;
  AItem.Kind := cKindSnippet;
  AItem.Detail := AEnum.Name;
  AItem.Fits := True;
  AItem.Pinned := True;
  // Erzeugt Code: Atlas wertet die Zusatzänderung ("end;") nicht als uses-Ergänzung.
  AItem.Action := 'case';
  AItem.HasTextEdit := True;
  AItem.TextEdit := TTextEdit.Create(mSlot.EditRange, TCaseCompletion.BranchesText(mSlot, mMissing, mPrefix,
    mLineBreak));
  mEndText := TCaseCompletion.EndText(mSlot, mLineBreak);
  if mEndText <> '' then
  begin
    AItem.AdditionalEdits := [TTextEdit.Create(TTextRange.Create(mSlot.EndInsert, mSlot.EndInsert), mEndText)];
  end;
end;

/// <summary>Was die Aufzählungen aus Atlas.Common.Semantics.EnumTypes zur Anfrage brauchen.</summary>
function EnumLookupOf(ARequest: TCompletionRequest): TEnumLookup;
begin
  Result := Default(TEnumLookup);
  Result.Resolver := ARequest.Resolver;
  Result.Index := ARequest.Index;
  Result.Tree := ARequest.Tree;
  Result.Text := ARequest.Text;
  Result.FileName := ARequest.FileName;
  Result.ReadText := ARequest.ReadText;
end;

{ Mengen und Werte }

/// <summary>Typ der Elemente im Mengenkonstruktor: "X in [" nimmt den Typ von X, sonst gilt der erwartete Typ an
/// der Klammer.</summary>
function SetElementType(ARequest: TCompletionRequest; const ASlot: TEnumSetSlot;
  out AType: TResolvedSymbol): Boolean;
var
  mTarget: TResolvedSymbol;
  mExpected: string;
  mLookup: TEnumLookup;
begin
  mLookup := EnumLookupOf(ARequest);
  if ASlot.ElementOf <> nil then
  begin
    mTarget := ARequest.Resolver.ResolveChain(ARequest.Tree, ARequest.FileName, ASlot.ElementOf, ASlot.Offset);
    Result := mTarget.Found and not mTarget.IsType and (mTarget.TypeName <> '');
    mExpected := mTarget.TypeName;
  end
  else
  begin
    mExpected := TExpectedTypes.At(ARequest.Resolver, ARequest.Tree, ARequest.FileName, ASlot.Bracket);
    Result := mExpected <> '';
  end;
  if Result then
  begin
    AType := TEnumTypes.TypeAt(mLookup, ASlot.Offset, mExpected);
  end;
end;

/// <summary>Alle Werte des Elementtyps im Mengenkonstruktor mit SetOf, SetChecked und SetRange.</summary>
function SetItems(ARequest: TCompletionRequest; const ASlot: TEnumSetSlot;
  out AItems: TArray<TCompletionItem>): Boolean;
var
  mType: TResolvedSymbol;
  mEnum: TEnumType;
  mChecked: TArray<Boolean>;
  mIndex: Integer;
  mItem: TCompletionItem;
begin
  AItems := nil;
  Result := SetElementType(ARequest, ASlot, mType) and TEnumTypes.EnumOf(EnumLookupOf(ARequest), mType,
    ASlot.ElementOf = nil, mEnum) and TPascalEnumSlots.Checked(mEnum.Values, ASlot.Present, mChecked);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(mEnum.Values) do
  begin
    mItem := EnumItem(mEnum, mIndex);
    mItem.Expected := 'set of ' + mEnum.Name;
    if mEnum.SetName <> '' then
    begin
      mItem.Expected := mEnum.SetName;
    end;
    mItem.SetOf := mEnum.Name;
    mItem.SetChecked := mChecked[mIndex];
    mItem.SetRange := ASlot.EditRange;
    AItems := AItems + [mItem];
  end;
end;

/// <summary>Werte des erwarteten Aufzählungstyps, am Anfang eines case-Zweigs zuerst die fehlenden Zweige.</summary>
function ValueItems(ARequest: TCompletionRequest; out AItems: TArray<TCompletionItem>): Boolean;
var
  mContext: TCompletionContext;
  mExpected: string;
  mEnum: TEnumType;
  mIndex: Integer;
  mItem: TCompletionItem;
  mLookup: TEnumLookup;
begin
  AItems := nil;
  mLookup := EnumLookupOf(ARequest);
  // Werte: nur ohne Punkt davor ("TAlign." zeigt die Mitglieder selbst).
  mContext := TCompletionContexts.Analyze(ARequest.Tree, ARequest.Position);
  mExpected := '';
  if mContext.Kind = TCompletionContextKind.Scope then
  begin
    mExpected := TExpectedTypes.At(ARequest.Resolver, ARequest.Tree, ARequest.FileName,
      ARequest.Position);
  end;
  Result := (mExpected <> '') and TEnumTypes.EnumOf(mLookup, TEnumTypes.TypeAt(mLookup, mContext.Offset, mExpected),
    False, mEnum);
  if not Result then
  begin
    Exit;
  end;
  // Am Anfang eines case-Zweigs (#449): fehlende Zweige auf einmal, als erster Eintrag.
  if CaseItem(mEnum, ARequest.Text, ARequest.Tree.Tokens, ARequest.Position, mItem) then
  begin
    mItem.Expected := mExpected;
    AItems := AItems + [mItem];
  end;
  for mIndex := 0 to High(mEnum.Values) do
  begin
    if MatchScore(mEnum.Values[mIndex], mContext.Prefix, ARequest.Matching) <> TFuzzyMatch.cNoMatch then
    begin
      mItem := EnumItem(mEnum, mIndex);
      mItem.Expected := mExpected;
      AItems := AItems + [mItem];
    end;
  end;
end;

{ Alle Felder zuweisen }

/// <summary>Steht vor APosition (Anfang einer Kette) der Anfang einer Anweisung? Davor ";", ein Schlüsselwort,
/// nach dem eine Anweisung beginnt, eine case-Marke oder nichts.</summary>
function AtStatementStart(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Boolean;
var
  mIndex: Integer;
begin
  mIndex := -1;
  while (mIndex < High(ATokens)) and (TTextPosition.Compare(ATokens[mIndex + 1].EndPos, APosition) <= 0) do
  begin
    Inc(mIndex);
  end;
  while (mIndex >= 0) and IsTrivia(ATokens[mIndex]) do
  begin
    Dec(mIndex);
  end;
  Result := (mIndex < 0) or ATokens[mIndex].IsSymbol(';') or ATokens[mIndex].IsSymbol(':') or
    MatchText(ATokens[mIndex].Text, ['begin', 'then', 'else', 'do', 'try', 'finally', 'except', 'repeat',
    'otherwise']) and (ATokens[mIndex].Kind = TPascalTokenKind.Keyword);
end;

/// <summary>Vorgabe für eine Aufzählung: ihr erster Wert (mit Typpräfix bei {$SCOPEDENUMS ON}).</summary>
function EnumDefault(ARequest: TCompletionRequest; const AType: TResolvedSymbol; const ATypeName: string;
  out AValue: string): Boolean;
var
  mEnum: TEnumType;
  mFirst: string;
begin
  Result := TEnumTypes.EnumOf(EnumLookupOf(ARequest), AType, False, mEnum);
  if Result then
  begin
    mFirst := mEnum.Values[0];
    if mEnum.Scoped then
    begin
      mFirst := mEnum.Name + '.' + mFirst;
    end;
    AValue := TAssignFields.DefaultValue(TAssignValueKind.Enum, ATypeName, mFirst);
  end;
end;

/// <summary>"TKinds = set of TKind": Die rechte Seite eines Alias steht nur im Quelltext.</summary>
function AliasDefault(ARequest: TCompletionRequest; const AType: TResolvedSymbol; const ATypeName: string;
  out AValue: string): Boolean;
var
  mSource, mDeclaration: string;
  mKind: TAssignValueKind;
begin
  Result := TEnumTypes.SourceOf(EnumLookupOf(ARequest), AType, mSource);
  if Result then
  begin
    mDeclaration := TEnumTypes.RangeText(mSource, AType.Range);
    Result := (Pos('=', mDeclaration) > 0) and TAssignFields.KindOfText(Trim(StringReplace(Copy(mDeclaration,
      Pos('=', mDeclaration) + 1, MaxInt), ';', '', [])), mKind);
  end;
  if Result then
  begin
    AValue := TAssignFields.DefaultValue(mKind, ATypeName, '');
  end;
end;

/// <summary>Vorgabe für den aufgelösten Typ AType: Klasse und Interface nil, Aufzählung ihr erster Wert, Alias
/// einer Menge deren Vorgabe. False, wenn sie sich daraus nicht ergibt.</summary>
function ResolvedDefault(ARequest: TCompletionRequest; const AType: TResolvedSymbol; const ATypeName: string;
  out AValue: string): Boolean;
begin
  if AType.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType] then
  begin
    AValue := 'nil';
    Exit(True);
  end;
  Result := (AType.SymbolKind in [TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias]) and
    EnumDefault(ARequest, AType, ATypeName, AValue);
  Result := Result or (AType.SymbolKind = TIndexSymbolKind.TypeAlias) and
    AliasDefault(ARequest, AType, ATypeName, AValue);
end;

/// <summary>Vorgabe für ein Feld vom Typ ATypeName (#491): eingebaute Typen aus dem Text, sonst über die
/// Namensauflösung (Aufzählung → erster Wert, Klasse und Interface → nil), Aliase verfolgt; sonst Default(T).
/// </summary>
function AssignValue(ARequest: TCompletionRequest; AOffset: Integer; const ATypeName: string): string;
var
  mKind: TAssignValueKind;
  mType: TResolvedSymbol;
  mCurrent: string;
  mStep: Integer;
begin
  mCurrent := ATypeName;
  for mStep := 1 to TEnumTypes.cMaxAliasSteps do
  begin
    if TAssignFields.KindOfText(mCurrent, mKind) then
    begin
      Exit(TAssignFields.DefaultValue(mKind, ATypeName, ''));
    end;
    // Typargumente gehören nicht zum Namen: TList<Integer> ist eine Klasse.
    if Pos('<', mCurrent) > 0 then
    begin
      mCurrent := Trim(Copy(mCurrent, 1, Pos('<', mCurrent) - 1));
    end;
    mType := TEnumTypes.TypeAt(EnumLookupOf(ARequest), AOffset, mCurrent);
    if not mType.Found or not mType.IsType then
    begin
      Break;
    end;
    if ResolvedDefault(ARequest, mType, ATypeName, Result) then
    begin
      Exit;
    end;
    if (mType.SymbolKind <> TIndexSymbolKind.TypeAlias) or (mType.TypeName = '') then
    begin
      Break;
    end;
    mCurrent := mType.TypeName;
    if mType.TypeArgs <> '' then
    begin
      mCurrent := mCurrent + '<' + mType.TypeArgs + '>';
    end;
  end;
  Result := TAssignFields.DefaultValue(TAssignValueKind.Other, ATypeName, '');
end;

/// <summary>Vorfahren zuerst, darin nach der Stelle der Deklaration.</summary>
function DeclaredBefore(const A, B: TResolvedSymbol): Boolean;
begin
  if A.Depth <> B.Depth then
  begin
    Exit(A.Depth > B.Depth);
  end;
  if not SameText(A.FileName, B.FileName) then
  begin
    Exit(CompareText(A.FileName, B.FileName) < 0);
  end;
  Result := TTextPosition.Compare(A.Range.StartPos, B.Range.StartPos) < 0;
end;

/// <summary>Sortiert nach DeclaredBefore; wenige Mitglieder: Einfügen genügt.</summary>
procedure SortByDeclaration(var ACandidates: TArray<TResolvedSymbol>);
var
  mIndex, mOther: Integer;
  mSwap: TResolvedSymbol;
begin
  for mIndex := 1 to High(ACandidates) do
  begin
    mOther := mIndex;
    while (mOther > 0) and DeclaredBefore(ACandidates[mOther], ACandidates[mOther - 1]) do
    begin
      mSwap := ACandidates[mOther];
      ACandidates[mOther] := ACandidates[mOther - 1];
      ACandidates[mOther - 1] := mSwap;
      Dec(mOther);
    end;
  end;
end;

/// <summary>Ist der Ausdruck ein Wert vom Typ Record oder Klasse? TFoo. allein ist ein Typ, TFoo(X). eine
/// Typumwandlung.</summary>
function IsAssignableOwner(const AContext: TCompletionContext; const AOwner, AType: TResolvedSymbol): Boolean;
begin
  Result := (AOwner.Kind <> TResolvedKind.UnitName) and not (AOwner.IsType and not AContext.Called);
  Result := Result and not AType.Builtin and (AType.SymbolKind in [TIndexSymbolKind.ClassType,
    TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType]);
end;

/// <summary>Kandidaten für die Zuweisungen in Deklarationsreihenfolge; "property Caption;" hebt nur die
/// Sichtbarkeit an: Typ, Zugriff und Stelle der Deklaration weiter oben.</summary>
function AssignCandidates(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  const AType: TResolvedSymbol): TArray<TResolvedSymbol>;
var
  mIndex, mDepth: Integer;
  mTyped: TResolvedSymbol;
begin
  Result := ARequest.Resolver.Candidates.MemberCandidates(ARequest.Tree, ARequest.FileName, AContext.Names,
    AContext.Offset);
  for mIndex := 0 to High(Result) do
  begin
    if (Result[mIndex].SymbolKind = TIndexSymbolKind.Property_) and (Result[mIndex].TypeName = '') and
      ARequest.Resolver.Queries.TypedProperty(AType, Result[mIndex].Name, mTyped, mDepth) then
    begin
      mTyped.Visibility := Result[mIndex].Visibility;
      mTyped.Depth := mDepth;
      Result[mIndex] := mTyped;
    end;
  end;
  SortByDeclaration(Result);
end;

/// <summary>Felder und Properties der Kandidaten; generische Typen eingesetzt (TPair&lt;string, Integer&gt;.Key
/// ist ein string).</summary>
function AssignMembers(const ACandidates: TArray<TResolvedSymbol>): TArray<TAssignMember>;
var
  mCandidate: TResolvedSymbol;
  mMember: TAssignMember;
  mTypeText: string;
begin
  Result := nil;
  for mCandidate in ACandidates do
  begin
    if mCandidate.IsHelper or not (mCandidate.SymbolKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) then
    begin
      Continue;
    end;
    mMember := Default(TAssignMember);
    mMember.Name := mCandidate.Name;
    mMember.Kind := mCandidate.SymbolKind;
    mMember.Signature := mCandidate.Signature;
    mTypeText := mCandidate.TypeName;
    if (mTypeText <> '') and (mCandidate.TypeArgs <> '') then
    begin
      mTypeText := mTypeText + '<' + mCandidate.TypeArgs + '>';
    end;
    mMember.TypeName := TPascalTypeTexts.SubstituteWords(mTypeText, mCandidate.Bindings);
    mMember.Visibility := mCandidate.Visibility;
    mMember.MaxArgs := mCandidate.MaxArgs;
    Result := Result + [mMember];
  end;
end;

/// <summary>Beschreibbare Felder mit ihren Vorgaben; je Typ einmal berechnet.</summary>
function AssignableFields(ARequest: TCompletionRequest; AOffset: Integer;
  const AMembers: TArray<TAssignMember>): TArray<TAssignField>;
var
  mValues: TDictionary<string, string>;
  mMember: TAssignMember;
  mField: TAssignField;
begin
  Result := nil;
  mValues := TDictionary<string, string>.Create;
  try
    for mMember in TAssignFields.Merge(AMembers) do
    begin
      if not TAssignFields.Writable(mMember) then
      begin
        Continue;
      end;
      mField.Name := mMember.Name;
      mField.TypeName := mMember.TypeName;
      if not mValues.TryGetValue(LowerCase(mMember.TypeName), mField.Value) then
      begin
        mField.Value := AssignValue(ARequest, AOffset, mMember.TypeName);
        mValues.Add(LowerCase(mMember.TypeName), mField.Value);
      end;
      Result := Result + [mField];
    end;
  finally
    mValues.Free;
  end;
end;

/// <summary>Hinter "Ausdruck." am Anfang einer Anweisung, allein in der Zeile, ein Wert vom Typ Record oder
/// Klasse.</summary>
function AssignSite(ARequest: TCompletionRequest; out AContext: TCompletionContext; out AType: TResolvedSymbol;
  out ALineText: string): Boolean;
var
  mChain: TResolvedChainType;
begin
  AContext := TCompletionContexts.Analyze(ARequest.Tree, ARequest.Position);
  ALineText := ARequest.LineText(ARequest.Position.Line);
  Result := (AContext.Kind = TCompletionContextKind.Member) and (AContext.Prefix = '') and
    (AContext.ChainStart.Line = ARequest.Position.Line) and (AContext.DotPos.Line = ARequest.Position.Line);
  Result := Result and (Trim(Copy(ALineText, 1, AContext.ChainStart.Character)) = '') and
    (Trim(Copy(ALineText, ARequest.Position.Character + 1, MaxInt)) = '') and
    AtStatementStart(ARequest.Tree.Tokens, AContext.ChainStart);
  Result := Result and ARequest.Resolver.ChainType(ARequest.Tree, ARequest.FileName, AContext.Names,
    AContext.Offset, mChain) and mChain.TypeFound and IsAssignableOwner(AContext, mChain.Owner, mChain.TypeInfo);
  AType := mChain.TypeInfo;
end;

/// <summary>Text des Eintrags: Liste mit Kontrollkästchen, Platzhalter oder Klartext.</summary>
procedure FillAssignText(var AItem: TCompletionItem; const AFields: TArray<TAssignField>;
  const AExpr, AIndent, ALineBreak: string; ASnippets: Boolean);
var
  mField: TAssignField;
  mAssignment: TCompletionAssignment;
begin
  if Length(AFields) > TAssignFields.cListThreshold then
  begin
    // Zuerst die Liste mit Kontrollkästchen: je Zeile die Zuweisung samt Umbruch für die nächste.
    AItem.TextEdit.NewText := AExpr + '.';
    for mField in AFields do
    begin
      mAssignment.Name := mField.Name;
      mAssignment.Detail := mField.TypeName;
      mAssignment.Text := TAssignFields.Line(AExpr, mField) + ALineBreak + AIndent;
      AItem.Assignments := AItem.Assignments + [mAssignment];
    end;
  end
  else if ASnippets then
  begin
    // Platzhalter-Modus (#51): Zeilen mit #10, die Einrückung setzt der Editor.
    AItem.Snippet := True;
    AItem.TextEdit.NewText := TAssignFields.Snippet(AExpr, AFields);
  end
  else
  begin
    AItem.TextEdit.NewText := TAssignFields.Plain(AExpr, AIndent, ALineBreak, AFields);
  end;
end;

{ TCompletionValues }

class function TCompletionValues.EnumItems(ARequest: TCompletionRequest; out AItems: TArray<TCompletionItem>;
  out ASetMode: Boolean): Boolean;
var
  mSlot: TEnumSetSlot;
begin
  AItems := nil;
  ASetMode := False;
  if ARequest.Tree = nil then
  begin
    Exit(False);
  end;
  // Mengenkonstruktor: "X in [" nimmt den Typ von X, sonst gilt der erwartete Typ an der Klammer.
  if TPascalEnumSlots.SetSlot(ARequest.Tree.Tokens, ARequest.Position, mSlot) then
  begin
    Result := SetItems(ARequest, mSlot, AItems);
    ASetMode := Result;
  end
  else
  begin
    Result := ValueItems(ARequest, AItems);
  end;
end;

class function TCompletionValues.AssignAllItem(ARequest: TCompletionRequest; ASnippets: Boolean;
  out AItem: TCompletionItem): Boolean;
var
  mContext: TCompletionContext;
  mType: TResolvedSymbol;
  mLineText, mExpr: string;
  mFields: TArray<TAssignField>;
begin
  AItem := Default(TCompletionItem);
  if not ARequest.Settings.AssignAllFields or (ARequest.Tree = nil) or (ARequest.Text = '') or
    not AssignSite(ARequest, mContext, mType, mLineText) then
  begin
    Exit(False);
  end;
  mFields := AssignableFields(ARequest, mContext.Offset, AssignMembers(AssignCandidates(ARequest, mContext, mType)));
  mExpr := Copy(mLineText, mContext.ChainStart.Character + 1, mContext.DotPos.Character -
    mContext.ChainStart.Character);
  // Was die folgenden Zeilen schon zuweisen, fällt weg; die Zahl im Titel zählt nur den Rest.
  mFields := TAssignFields.Without(mFields, TAssignFields.AssignedAfter(TextLines(ARequest.Text),
    ARequest.Position.Line, mExpr));
  Result := Length(mFields) > 0;
  if not Result then
  begin
    Exit;
  end;
  AItem.Name := TAssignFields.Title(Length(mFields));
  AItem.Kind := cKindSnippet;
  AItem.Detail := mType.Name;
  AItem.Fits := True;
  AItem.Pinned := True;
  // Erzeugt Code: Atlas zeigt die Zusatzänderungen nicht als uses-Ergänzung.
  AItem.Action := 'assign';
  AItem.HasTextEdit := True;
  AItem.TextEdit := TTextEdit.Create(TTextRange.Create(mContext.ChainStart, ARequest.Position), '');
  FillAssignText(AItem, mFields, mExpr, Copy(mLineText, 1, mContext.ChainStart.Character), ARequest.LineBreak,
    ASnippets);
end;

initialization
  TAtlasTextTables.Add('Lsp.Completion.Values', cTexts);

end.
