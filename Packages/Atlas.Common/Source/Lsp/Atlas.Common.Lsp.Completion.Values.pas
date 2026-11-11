unit Atlas.Common.Lsp.Completion.Values;

// Werte und Deklarationen in der Vervollständigung: Aufzählungen und Mengen (#448), fehlende case-Zweige
// (#449, #50), Muster fortsetzen (#671), unbekannte Namen deklarieren (#471) und „Alle Felder zuweisen“
// (#491). Aus Atlas.Common.Lsp.Completion herausgelöst.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest;

type
  /// <summary>Was die Auflösung von Aufzählungstypen braucht: Auflöser, Index, Baum und Text der Datei und das
  /// Lesen anderer Dateien.</summary>
  TEnumLookup = record
    Resolver: TNameResolver;
    Index: ISymbolIndex;
    Tree: TSyntaxTree;
    Text: string;
    FileName: string;
    ReadText: TCompletionReadText;
    class function FromRequest(ARequest: TCompletionRequest): TEnumLookup; static;
  end;

  TCompletionValues = class
  public
    /// <summary>Aufzählungen und Mengen (#448). Erwartet die Stelle einen Aufzählungstyp (Zuweisung, Parameter,
    /// Vergleich, case-Zweig), kommen dessen Werte in Deklarationsreihenfolge (Ordinal, bei {$SCOPEDENUMS ON} mit
    /// Typpräfix im InsertText). In einem Mengenkonstruktor ("Anchors := [akLeft, ") kommen alle Werte des
    /// Elementtyps mit SetOf, SetChecked und SetRange; ASetMode ist dann True. False ohne Aufzählungstyp.</summary>
    class function EnumItems(ARequest: TCompletionRequest; out AItems: TArray<TCompletionItem>;
      out ASetMode: Boolean): Boolean; static;
    /// <summary>„case vervollständigen“ (#50): Werte der Aufzählung, über die die case-Anweisung verzweigt, deren
    /// "of" vor APosition endet; APrefix ist "TAlign." bei {$SCOPEDENUMS ON}. False ohne Aufzählungstyp.</summary>
    class function CaseValues(const ALookup: TEnumLookup; const APosition: TTextPosition;
      out AValues: TArray<string>; out APrefix: string): Boolean; static;
    /// <summary>Muster fortsetzen (#671): alle Werte des Aufzählungstyps, zu dem der Wert an APosition gehört, in
    /// Deklarationsreihenfolge (ohne Typpräfix). False, wenn dort kein Aufzählungswert steht.</summary>
    class function EnumValuesAt(const ALookup: TEnumLookup; const APosition: TTextPosition;
      out AValues: TArray<string>): Boolean; static;
    /// <summary>Unbekannter Name am Cursor im Rumpf einer Routine (#471): lokale Variable (mit AInlineVar auch als
    /// Inline-var), Feld der Klasse (F-Konvention, die Verwendung wird umbenannt) und, wenn der Name als Wert
    /// dient, Konstante in der implementation. Typ aus der rechten Seite einer Zuweisung, sonst aus dem
    /// erwarteten Typ, sonst ein Platzhalter. False, wenn der Name bekannt ist oder in AKnown genau vorkommt.</summary>
    class function DeclareItems(ARequest: TCompletionRequest; AInlineVar: Boolean;
      const AKnown: TArray<TCompletionItem>; out AItems: TArray<TCompletionItem>): Boolean; static;
    /// <summary>„Alle Felder zuweisen (n)“ (#491) hinter "Ausdruck." am Anfang einer Anweisung, wenn der Ausdruck
    /// ein Record oder eine Klasse ist und completion.assignAllFields gilt: je öffentlich beschreibbarem Feld und
    /// jeder Property eine Zuweisung, in Deklarationsreihenfolge; was die folgenden Zeilen schon zuweisen, fällt
    /// weg. Mit ASnippets im Platzhalter-Modus; mehr als 15 Felder kommen als Assignments für die Liste mit
    /// Kontrollkästchen. False außerhalb dieses Kontexts oder ohne Felder.</summary>
    class function AssignAllItem(ARequest: TCompletionRequest; ASnippets: Boolean;
      out AItem: TCompletionItem): Boolean; static;
  end;

/// <summary>uses-Eintrag für ATypeName (#294, #180), wenn der Typ an AOffset nicht sichtbar ist und der Index
/// ihn in einer anderen Unit kennt; sonst leer.</summary>
function TypeUnitEdits(const ALookup: TEnumLookup; const ATypeName, ALineBreak: string;
  AOffset: Integer): TArray<TRuleEdit>;

implementation

uses
  Atlas.Common.Localization.Texts,
  Atlas.Text.Lines,
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Editing.DeclareUnknown,
  Atlas.Common.Editing.CaseCompletion,
  Atlas.Common.Editing.AssignFields,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.CompletionEnums,
  Atlas.Common.Lsp.Completion.Context;

type
  /// <summary>Texte der Werte-Vervollständigung in beiden Sprachen (#1458).</summary>
  TValuesText = (FillMissing, InsertAll, CreateALocalVariable, CreateInlineVariable, CreateField, CreateConstant);

const
  cTexts: array[TValuesText] of TAtlasText = (
    (De: 'Fehlende Werte ergänzen (%d)'; En: 'Add missing values (%d)'),
    (De: 'Alle Werte einfügen'; En: 'Insert all values'),
    (De: 'Lokale Variable anlegen'; En: 'Create a local variable'),
    (De: 'Inline-Variable anlegen'; En: 'Create inline variable'),
    (De: 'Feld %s anlegen'; En: 'Create field %s'),
    (De: 'Konstante anlegen'; En: 'Create constant'));
  /// <summary>So oft folgt die Auflösung Aliasen und Mengen bis zur Aufzählung.</summary>
  cMaxAliasSteps = 4;
  /// <summary>Höchstens so viele Zeilen liest RangeText (lange Aufzählungen stehen über viele Zeilen).</summary>
  cMaxRangeLines = 400;

type
  /// <summary>Aufzählungstyp mit seinen Werten (#448).</summary>
  TEnumType = record
    Name: string;
    /// <summary>Mengentyp, über den er gefunden wurde ("TAnchors"); '' ohne.</summary>
    SetName: string;
    Values: TArray<string>;
    /// <summary>Namenspositionen der Werte in FileName; Line -1, wenn unbekannt.</summary>
    Positions: TArray<TTextPosition>;
    FileName: string;
    /// <summary>{$SCOPEDENUMS ON} an der Deklaration: Werte nur mit Typpräfix.</summary>
    Scoped: Boolean;
  end;

  /// <summary>Baut die Einträge von DeclareItems (#471) für einen unbekannten Namen.</summary>
  TDeclareBuilder = class
  private
    FRequest: TCompletionRequest;
    FSlot: TUnknownSlot;
    FSource: TCommandSource;
    FRoutine: TSyntaxNode;
    FTypeName: string;
    FDeclType: string;
    FBase: TCompletionItem;
    function TypeEdits(AOffset: Integer): TArray<TRuleEdit>;
    function ClassFields(const AClass: TIndexSymbol): TArray<string>;
    function FieldEdit(const AClass: TIndexSymbol; const AField: string): TRuleEdit;
    function ConstantEdit(const ADetail: string): TRuleEdit;
  public
    Items: TArray<TCompletionItem>;
    constructor Create(ARequest: TCompletionRequest; const ASlot: TUnknownSlot; ASource: TCommandSource;
      ARoutine: TSyntaxNode);
    procedure AddLocal(AInlineVar: Boolean);
    procedure AddField;
    procedure AddConstant;
  end;

/// <summary>Text von ARange, über höchstens cMaxRangeLines Zeilen.</summary>
function RangeText(const AText: string; const ARange: TTextRange): string;
var
  mLines: TArray<string>;
  mLine: Integer;
begin
  Result := '';
  mLines := TextLines(AText);
  for mLine := Max(0, ARange.StartPos.Line) to Min(Min(ARange.EndPos.Line, ARange.StartPos.Line + cMaxRangeLines),
    High(mLines)) do
  begin
    if mLine = ARange.StartPos.Line then
    begin
      Result := Copy(mLines[mLine], ARange.StartPos.Character + 1, MaxInt);
    end
    else
    begin
      Result := Result + #10 + mLines[mLine];
    end;
  end;
end;

/// <summary>Offset (0-basiert) von APosition in AText.</summary>
function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  mIndex, mLine: Integer;
begin
  mLine := 0;
  mIndex := 1;
  while (mLine < APosition.Line) and (mIndex <= Length(AText)) do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
    end;
    Inc(mIndex);
  end;
  Result := mIndex - 1 + APosition.Character;
end;

/// <summary>Quelltext der Datei von ASymbol: das offene Dokument oder über ReadText.</summary>
function SourceOf(const ALookup: TEnumLookup; const ASymbol: TResolvedSymbol; out ASource: string): Boolean;
begin
  ASource := '';
  if SameText(ASymbol.FileName, ALookup.FileName) then
  begin
    ASource := ALookup.Text;
    Exit(True);
  end;
  Result := (ASymbol.FileName <> '') and Assigned(ALookup.ReadText) and ALookup.ReadText(ASymbol.FileName, ASource);
end;

/// <summary>Index-Eintrag der Unit von ASymbol; für das offene Dokument aus dessen Baum.</summary>
function OwnerUnit(const ALookup: TEnumLookup; const ASymbol: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  if SameText(ASymbol.FileName, ALookup.FileName) then
  begin
    AUnit := ALookup.Resolver.ExtractedUnit(ALookup.Tree, ALookup.FileName);
    Exit(True);
  end;
  Result := (ALookup.Index <> nil) and ALookup.Index.FindFile(ASymbol.FileName, AUnit);
end;

/// <summary>Typ ATypeName, wie er an AOffset stünde; sonst ein gleichnamiger Typ aus dem Index.</summary>
function TypeAt(const ALookup: TEnumLookup; AOffset: Integer; const ATypeName: string): TResolvedSymbol;
var
  mLocation: TSymbolLocation;
  mOwner: TUnitIndex;
begin
  Result := ALookup.Resolver.ResolveChain(ALookup.Tree, ALookup.FileName, ATypeName.Split(['.']), AOffset);
  // Eingebaute Typen (Integer, string) stehen nicht im Index: nicht danach suchen.
  if (Result.Found and Result.IsType) or (ALookup.Index = nil) or (Pos('.', ATypeName) > 0) or
    TResolverText.IsBuiltinTypeName(ATypeName) then
  begin
    Exit;
  end;
  // Typ einer Eigenschaft aus einer Unit, die hier nicht eingebunden ist (TAnchors aus Vcl.Controls).
  for mLocation in ALookup.Index.FindSymbols(ATypeName) do
  begin
    if (mLocation.Symbol.Container = '') and (mLocation.Symbol.Kind in [TIndexSymbolKind.EnumType,
      TIndexSymbolKind.TypeAlias]) and ALookup.Index.FindUnit(mLocation.UnitName, mOwner) and
      ALookup.Resolver.ResolveTypeFrom(mOwner, ATypeName, Result) then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Ein Schritt von einem Alias oder einer Menge zum Typ dahinter, von der Unit der Deklaration aus;
/// False, wenn er nicht weiterführt.</summary>
function FollowAlias(const ALookup: TEnumLookup; const ADeclaration: string; AAllowSet: Boolean;
  var AType: TResolvedSymbol; var AEnum: TEnumType): Boolean;
var
  mOwner: TUnitIndex;
  mElement: string;
begin
  if not OwnerUnit(ALookup, AType, mOwner) then
  begin
    Exit(False);
  end;
  mElement := TCompletionEnums.SetElement(ADeclaration);
  if mElement = '' then
  begin
    Exit((AType.TypeName <> '') and ALookup.Resolver.ResolveTypeFrom(mOwner, AType.TypeName, AType));
  end;
  Result := AAllowSet and (AEnum.SetName = '');
  if Result then
  begin
    AEnum.SetName := AType.Name;
    Result := ALookup.Resolver.ResolveTypeFrom(mOwner, mElement, AType);
  end;
end;

/// <summary>Folgt Aliasen (und mit AAllowSet einer Menge) bis zur Aufzählung; ASource und ADeclaration sind dann
/// ihr Quelltext und ihre Deklaration.</summary>
function FindEnumDeclaration(const ALookup: TEnumLookup; AAllowSet: Boolean; var AType: TResolvedSymbol;
  var AEnum: TEnumType; out ASource, ADeclaration: string): Boolean;
var
  mStep: Integer;
begin
  ASource := '';
  ADeclaration := '';
  for mStep := 1 to cMaxAliasSteps do
  begin
    // Erst die Art prüfen: Klassen und eingebaute Typen brauchen den Quelltext nicht.
    if not AType.Found or not AType.IsType or not (AType.SymbolKind in [TIndexSymbolKind.EnumType,
      TIndexSymbolKind.TypeAlias]) or not SourceOf(ALookup, AType, ASource) then
    begin
      Exit(False);
    end;
    ADeclaration := RangeText(ASource, AType.Range);
    if AType.SymbolKind = TIndexSymbolKind.EnumType then
    begin
      Exit(True);
    end;
    // Alias oder Menge: von der Unit der Deklaration aus weiter auflösen.
    if not FollowAlias(ALookup, ADeclaration, AAllowSet, AType, AEnum) then
    begin
      Exit(False);
    end;
  end;
  Result := False;
end;

/// <summary>Namenspositionen der Werte für completionItem/resolve.</summary>
procedure FindEnumPositions(const ALookup: TEnumLookup; const AType: TResolvedSymbol; var AEnum: TEnumType);
var
  mOwner: TUnitIndex;
  mSymbol: TIndexSymbol;
  mIndex: Integer;
begin
  SetLength(AEnum.Positions, Length(AEnum.Values));
  for mIndex := 0 to High(AEnum.Positions) do
  begin
    AEnum.Positions[mIndex] := TTextPosition.Create(-1, 0);
  end;
  if not OwnerUnit(ALookup, AType, mOwner) then
  begin
    Exit;
  end;
  for mSymbol in mOwner.Symbols do
  begin
    if (mSymbol.Kind <> TIndexSymbolKind.EnumMember) or not SameText(mSymbol.Container, AType.QualifiedName) then
    begin
      Continue;
    end;
    for mIndex := 0 to High(AEnum.Values) do
    begin
      if SameText(AEnum.Values[mIndex], mSymbol.Name) then
      begin
        AEnum.Positions[mIndex] := mSymbol.SelectionRange.StartPos;
      end;
    end;
  end;
end;

/// <summary>Aufzählung zu AType, Aliase verfolgt; mit AAllowSet auch der Elementtyp einer Menge.</summary>
function EnumOf(const ALookup: TEnumLookup; AType: TResolvedSymbol; AAllowSet: Boolean;
  out AEnum: TEnumType): Boolean;
var
  mSource, mDeclaration: string;
begin
  AEnum := Default(TEnumType);
  Result := FindEnumDeclaration(ALookup, AAllowSet, AType, AEnum, mSource, mDeclaration);
  if Result then
  begin
    AEnum.Values := TCompletionEnums.EnumValues(mDeclaration);
    Result := AEnum.Values <> nil;
  end;
  if Result then
  begin
    AEnum.Name := AType.Name;
    AEnum.FileName := AType.FileName;
    AEnum.Scoped := TCompletionEnums.ScopedAt(mSource, OffsetOf(mSource, AType.Range.StartPos));
    FindEnumPositions(ALookup, AType, AEnum);
  end;
end;

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
  AItem.TextEdit := TRuleEdit.Create(mSlot.EditRange, TCaseCompletion.BranchesText(mSlot, mMissing, mPrefix,
    mLineBreak));
  mEndText := TCaseCompletion.EndText(mSlot, mLineBreak);
  if mEndText <> '' then
  begin
    AItem.AdditionalEdits := [TRuleEdit.Create(TTextRange.Create(mSlot.EndInsert, mSlot.EndInsert), mEndText)];
  end;
end;

/// <summary>Typ eines aufgelösten Ausdrucksteils: Konstruktor → Klasse, Typumwandlung → Typ, sonst sein Typ.</summary>
function TypeOfResolved(const ASymbol: TResolvedSymbol): string;
begin
  Result := '';
  if not ASymbol.Found or (ASymbol.Kind = TResolvedKind.UnitName) then
  begin
    Exit;
  end;
  if ASymbol.SymbolKind = TIndexSymbolKind.Constructor_ then
  begin
    Result := ASymbol.Container;
  end
  else if ASymbol.IsType then
  begin
    Result := ASymbol.Name;
  end
  else if ASymbol.TypeName <> '' then
  begin
    Result := ASymbol.TypeName;
  end
  else if ASymbol.SymbolKind = TIndexSymbolKind.EnumMember then
  begin
    Result := ASymbol.Container;
  end;
end;

/// <summary>Ein schlichter Typname, der einen uses-Eintrag brauchen kann: nicht generisch, nicht qualifiziert,
/// kein Platzhalter, nicht eingebaut.</summary>
function IsImportableName(const ATypeName: string): Boolean;
begin
  Result := (ATypeName <> '') and (Pos('<', ATypeName) = 0) and (Pos('.', ATypeName) = 0) and
    (Pos('{', ATypeName) = 0) and not TResolverText.IsBuiltinTypeName(ATypeName);
end;

/// <summary>Ein Typ aus einer anderen Unit, die ATree noch nicht einbindet.</summary>
function IsForeignType(AResolver: TNameResolver; ATree: TSyntaxTree; const ALocation: TSymbolLocation): Boolean;
begin
  Result := (ALocation.Symbol.Container = '') and (ALocation.Symbol.Kind in [TIndexSymbolKind.ClassType,
    TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType,
    TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias]) and not SameText(ALocation.UnitName, 'System') and
    not SameText(ALocation.UnitName, TUsesClauses.OwnName(ATree.Tokens));
  Result := Result and not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ATree.Tokens), ALocation.UnitName,
    AResolver.Namespaces);
end;

/// <summary>uses-Eintrag für ATypeName (#180), wenn der Typ an AOffset nicht sichtbar ist und der Index ihn
/// in einer anderen Unit kennt; leer sonst.</summary>
function TypeUnitEdits(const ALookup: TEnumLookup; const ATypeName, ALineBreak: string;
  AOffset: Integer): TArray<TRuleEdit>;
var
  mLocation: TSymbolLocation;
  mEdit: TRuleEdit;
begin
  Result := nil;
  if (ALookup.Index = nil) or not IsImportableName(ATypeName) or ALookup.Resolver.ResolveChain(ALookup.Tree,
    ALookup.FileName, [ATypeName], AOffset).Found then
  begin
    Exit;
  end;
  for mLocation in ALookup.Index.FindSymbols(ATypeName) do
  begin
    if IsForeignType(ALookup.Resolver, ALookup.Tree, mLocation) and TUsesClauses.AddUnit(ALookup.Tree.Tokens,
      AOffset, mLocation.UnitName, ALineBreak, mEdit) then
    begin
      Result := [mEdit];
      Exit;
    end;
  end;
end;

/// <summary>Typ für den unbekannten Namen: rechte Seite der Zuweisung, sonst der erwartete Typ.</summary>
function SlotType(ARequest: TCompletionRequest; const ASlot: TUnknownSlot): string;
var
  mTermFirst, mTermLast, mNameToken: Integer;
  mTokens: TArray<TPascalToken>;
begin
  if not ASlot.AssignTarget then
  begin
    Exit(TCompletionContexts.ExpectedType(ARequest.Resolver, ARequest.Tree, ARequest.FileName, ARequest.Position));
  end;
  mTokens := ARequest.Tree.Tokens;
  Result := TDeclareUnknown.Shape(mTokens, ASlot.ValueFirst, ASlot.ValueLast, mTermFirst, mTermLast);
  if (Result = '') and (mTermFirst >= 0) and (mTermFirst = mTermLast) then
  begin
    Result := TDeclareUnknown.LiteralType(mTokens[mTermFirst]);
  end;
  if (Result = '') and (mTermFirst >= 0) then
  begin
    mNameToken := TDeclareUnknown.TermName(mTokens, mTermFirst, mTermLast);
    if mNameToken >= 0 then
    begin
      Result := TypeOfResolved(ARequest.Resolver.Resolve(ARequest.Tree, ARequest.FileName,
        mTokens[mNameToken].StartPos));
    end;
  end;
end;

/// <summary>Ist der Name bekannt: ein Eintrag passt genau oder die Namensauflösung findet ihn?</summary>
function IsKnownName(ARequest: TCompletionRequest; const ASlot: TUnknownSlot;
  const AKnown: TArray<TCompletionItem>): Boolean;
var
  mKnown: TCompletionItem;
begin
  for mKnown in AKnown do
  begin
    if SameText(mKnown.Name, ASlot.Name) then
    begin
      Exit(True);
    end;
  end;
  Result := ARequest.Resolver.Resolve(ARequest.Tree, ARequest.FileName, ASlot.NameRange.StartPos).Found;
end;

/// <summary>Quelle der Befehle für die Zeile des Cursors.</summary>
function CommandSourceFor(ARequest: TCompletionRequest): TCommandSource;
var
  mSlash: TSlashContext;
begin
  mSlash := Default(TSlashContext);
  mSlash.Text := ARequest.Text;
  mSlash.Line := ARequest.Position.Line;
  mSlash.LineText := ARequest.LineText(ARequest.Position.Line);
  Result := TCommandSource.Create(mSlash);
end;

{ TDeclareBuilder }

constructor TDeclareBuilder.Create(ARequest: TCompletionRequest; const ASlot: TUnknownSlot; ASource: TCommandSource;
  ARoutine: TSyntaxNode);
begin
  inherited Create;
  FRequest := ARequest;
  FSlot := ASlot;
  FSource := ASource;
  FRoutine := ARoutine;
  FTypeName := SlotType(ARequest, ASlot);
  FDeclType := FTypeName;
  if FDeclType = '' then
  begin
    FDeclType := TDeclareUnknown.cTypePlaceholder;
  end;
  FBase := Default(TCompletionItem);
  FBase.Action := 'declare';
  FBase.Unknown := ASlot.Name;
  FBase.HasTextEdit := True;
end;

function TDeclareBuilder.TypeEdits(AOffset: Integer): TArray<TRuleEdit>;
begin
  Result := TypeUnitEdits(TEnumLookup.FromRequest(FRequest), FTypeName, FSource.LineBreak, AOffset);
end;

procedure TDeclareBuilder.AddLocal(AInlineVar: Boolean);
var
  mItem: TCompletionItem;
begin
  // Lokale Variable im var-Abschnitt; der Cursor bleibt im Namen.
  mItem := FBase;
  mItem.Name := cTexts[TValuesText.CreateALocalVariable].Text;
  mItem.Kind := cKindVariable;
  mItem.Detail := Format('%s: %s', [FSlot.Name, FDeclType]);
  mItem.TextEdit := TRuleEdit.Create(FSlot.NameRange, TDeclareUnknown.WithCaret(FSlot.Name, FSlot.CursorOffset));
  mItem.AdditionalEdits := [Atlas.Common.Editing.CommandSource.AddLocal(FSource, FRoutine, TSyntaxKind.VarSection,
    'var', Format('%s: %s;', [FSlot.Name, FDeclType]))] + TypeEdits(FRoutine.StartOffset);
  Items := Items + [mItem];
  // Inline-Variable an der Stelle (ab Delphi 10.3): Den Typ leitet der Compiler ab.
  if AInlineVar and FSlot.InlineAllowed then
  begin
    mItem := FBase;
    mItem.Name := cTexts[TValuesText.CreateInlineVariable].Text;
    mItem.Kind := cKindVariable;
    mItem.Detail := Format('var %s := …', [FSlot.Name]);
    mItem.TextEdit := TRuleEdit.Create(FSlot.NameRange, TDeclareUnknown.WithCaret('var ' + FSlot.Name,
      FSlot.CursorOffset + 4));
    Items := Items + [mItem];
  end;
end;

function TDeclareBuilder.ClassFields(const AClass: TIndexSymbol): TArray<string>;
var
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mSymbol in FSource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and (SameText(mSymbol.Container, AClass.QualifiedName) or
      SameText(mSymbol.Container, AClass.Name)) then
    begin
      Result := Result + [mSymbol.Name];
    end;
  end;
end;

function TDeclareBuilder.FieldEdit(const AClass: TIndexSymbol; const AField: string): TRuleEdit;
var
  mLine, mEnd: Integer;
  mDeclaration: string;
begin
  mDeclaration := Format('%s: %s;', [AField, FDeclType]);
  mLine := FSource.PrivateLine(AClass);
  if mLine >= 0 then
  begin
    Exit(FSource.AfterLine(mLine, FSource.Indent(mLine) + '  ' + mDeclaration));
  end;
  mEnd := AClass.Range.EndPos.Line;
  Result := FSource.BeforeLine(mEnd, FSource.Indent(mEnd) + 'private' + FSource.LineBreak + FSource.Indent(mEnd) +
    '  ' + mDeclaration);
end;

procedure TDeclareBuilder.AddField;
var
  mClass: TIndexSymbol;
  mFields: TArray<string>;
  mField: string;
  mItem: TCompletionItem;
begin
  // Feld im private-Abschnitt der Klasse, wenn die Routine eine ihrer Methoden ist.
  if (Pos('.', FRoutine.Name) = 0) or not FSource.ClassAt(mClass) then
  begin
    Exit;
  end;
  mFields := ClassFields(mClass);
  mField := TDeclareUnknown.FieldName(FSlot.Name, TDeclareUnknown.UsesFieldPrefix(mFields));
  if MatchText(mField, mFields) then
  begin
    Exit;
  end;
  mItem := FBase;
  mItem.Name := cTexts[TValuesText.CreateField].Fmt([mField]);
  mItem.Kind := cKindField;
  mItem.Detail := Format('%s: %s', [mField, FDeclType]);
  // Die Verwendung heißt danach wie das Feld; der Cursor bleibt an derselben Stelle im Namen.
  mItem.TextEdit := TRuleEdit.Create(FSlot.NameRange, TDeclareUnknown.WithCaret(mField,
    FSlot.CursorOffset + Length(mField) - Length(FSlot.Name)));
  mItem.AdditionalEdits := [FieldEdit(mClass, mField)] + TypeEdits(FSource.Offset(mClass.Range.StartPos.Line));
  Items := Items + [mItem];
end;

function TDeclareBuilder.ConstantEdit(const ADetail: string): TRuleEdit;
var
  mSection, mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mSection := FSource.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  mNode := nil;
  if mSection <> nil then
  begin
    for mIndex := 0 to mSection.ChildCount - 1 do
    begin
      if (mSection[mIndex].Kind = TSyntaxKind.ConstSection) and (mNode = nil) then
      begin
        mNode := mSection[mIndex];
      end;
    end;
  end;
  if mNode <> nil then
  begin
    Result := FSource.AfterLine(mNode.EndPos.Line, '  ' + ADetail);
  end
  else
  begin
    Result := FSource.AfterLine(FSource.ImplementationStart, FSource.LineBreak + 'const' + FSource.LineBreak + '  ' +
      ADetail);
  end;
end;

procedure TDeclareBuilder.AddConstant;
var
  mItem: TCompletionItem;
begin
  // Konstante in der implementation, wenn der Name als Wert dient; der Wert ist ein Platzhalter.
  if FSlot.AssignTarget or (FSource.ImplementationStart < 0) then
  begin
    Exit;
  end;
  mItem := FBase;
  mItem.Name := cTexts[TValuesText.CreateConstant].Text;
  mItem.Kind := cKindConstant;
  mItem.Detail := Format('%s = %s;', [FSlot.Name, TDeclareUnknown.DefaultValue(FTypeName)]);
  mItem.TextEdit := TRuleEdit.Create(FSlot.NameRange, TDeclareUnknown.WithCaret(FSlot.Name, FSlot.CursorOffset));
  mItem.AdditionalEdits := [ConstantEdit(mItem.Detail)];
  Items := Items + [mItem];
end;

{ TEnumLookup }

class function TEnumLookup.FromRequest(ARequest: TCompletionRequest): TEnumLookup;
begin
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
  mLookup := TEnumLookup.FromRequest(ARequest);
  if ASlot.ElementOf <> nil then
  begin
    mTarget := ARequest.Resolver.ResolveChain(ARequest.Tree, ARequest.FileName, ASlot.ElementOf, ASlot.Offset);
    Result := mTarget.Found and not mTarget.IsType and (mTarget.TypeName <> '');
    mExpected := mTarget.TypeName;
  end
  else
  begin
    mExpected := TCompletionContexts.ExpectedType(ARequest.Resolver, ARequest.Tree, ARequest.FileName, ASlot.Bracket);
    Result := mExpected <> '';
  end;
  if Result then
  begin
    AType := TypeAt(mLookup, ASlot.Offset, mExpected);
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
  Result := SetElementType(ARequest, ASlot, mType) and EnumOf(TEnumLookup.FromRequest(ARequest), mType,
    ASlot.ElementOf = nil, mEnum) and TCompletionEnums.Checked(mEnum.Values, ASlot.Present, mChecked);
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
  mLookup := TEnumLookup.FromRequest(ARequest);
  // Werte: nur ohne Punkt davor ("TAlign." zeigt die Mitglieder selbst).
  mContext := TCompletionContexts.Analyze(ARequest.Tree, ARequest.Position);
  mExpected := '';
  if mContext.Kind = TCompletionContextKind.Scope then
  begin
    mExpected := TCompletionContexts.ExpectedType(ARequest.Resolver, ARequest.Tree, ARequest.FileName,
      ARequest.Position);
  end;
  Result := (mExpected <> '') and EnumOf(mLookup, TypeAt(mLookup, mContext.Offset, mExpected), False, mEnum);
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
  while (mIndex < High(ATokens)) and (ComparePositions(ATokens[mIndex + 1].EndPos, APosition) <= 0) do
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
  Result := EnumOf(TEnumLookup.FromRequest(ARequest), AType, False, mEnum);
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
  Result := SourceOf(TEnumLookup.FromRequest(ARequest), AType, mSource);
  if Result then
  begin
    mDeclaration := RangeText(mSource, AType.Range);
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
  for mStep := 1 to cMaxAliasSteps do
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
    mType := TypeAt(TEnumLookup.FromRequest(ARequest), AOffset, mCurrent);
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
  Result := ComparePositions(A.Range.StartPos, B.Range.StartPos) < 0;
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
    mMember.TypeName := TInterfaceStubs.SubstituteWords(mTypeText, mCandidate.Bindings);
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
  if TCompletionEnums.SetSlot(ARequest.Tree.Tokens, ARequest.Position, mSlot) then
  begin
    Result := SetItems(ARequest, mSlot, AItems);
    ASetMode := Result;
  end
  else
  begin
    Result := ValueItems(ARequest, AItems);
  end;
end;

class function TCompletionValues.CaseValues(const ALookup: TEnumLookup; const APosition: TTextPosition;
  out AValues: TArray<string>; out APrefix: string): Boolean;
var
  mExpected: string;
  mEnum: TEnumType;
begin
  AValues := nil;
  APrefix := '';
  mExpected := '';
  // Am Anfang eines Zweigs ist der erwartete Typ der des Selektors (#448).
  if ALookup.Tree <> nil then
  begin
    mExpected := TCompletionContexts.ExpectedType(ALookup.Resolver, ALookup.Tree, ALookup.FileName, APosition);
  end;
  Result := (mExpected <> '') and EnumOf(ALookup, TypeAt(ALookup, OffsetOf(ALookup.Text, APosition), mExpected),
    False, mEnum);
  if Result then
  begin
    AValues := mEnum.Values;
    if mEnum.Scoped then
    begin
      APrefix := mEnum.Name + '.';
    end;
  end;
end;

class function TCompletionValues.EnumValuesAt(const ALookup: TEnumLookup; const APosition: TTextPosition;
  out AValues: TArray<string>): Boolean;
var
  mMember, mType: TResolvedSymbol;
  mOwner: TUnitIndex;
  mEnum: TEnumType;
begin
  AValues := nil;
  if ALookup.Tree = nil then
  begin
    Exit(False);
  end;
  mMember := ALookup.Resolver.Resolve(ALookup.Tree, ALookup.FileName, APosition);
  if not mMember.Found or (mMember.SymbolKind <> TIndexSymbolKind.EnumMember) or (mMember.Container = '') then
  begin
    Exit(False);
  end;
  // Der Typ, wie er an der Stelle sichtbar ist; sonst von der Unit des Werts aus.
  mType := TypeAt(ALookup, OffsetOf(ALookup.Text, APosition), mMember.Container);
  if not (mType.Found and mType.IsType) and OwnerUnit(ALookup, mMember, mOwner) then
  begin
    ALookup.Resolver.ResolveTypeFrom(mOwner, mMember.Container, mType);
  end;
  Result := EnumOf(ALookup, mType, False, mEnum);
  if Result then
  begin
    AValues := mEnum.Values;
  end;
end;

class function TCompletionValues.DeclareItems(ARequest: TCompletionRequest; AInlineVar: Boolean;
  const AKnown: TArray<TCompletionItem>; out AItems: TArray<TCompletionItem>): Boolean;
var
  mSlot: TUnknownSlot;
  mSource: TCommandSource;
  mBuilder: TDeclareBuilder;
begin
  AItems := nil;
  if (ARequest.Tree = nil) or not TDeclareUnknown.Slot(ARequest.Tree.Tokens, ARequest.Position, mSlot) or
    IsKnownName(ARequest, mSlot, AKnown) then
  begin
    Exit(False);
  end;
  mSource := CommandSourceFor(ARequest);
  try
    // Nur im Rumpf einer Routine: dort sind Variablen, Felder und Konstanten Deklarationen wert.
    if mSource.RoutineAt <> nil then
    begin
      mBuilder := TDeclareBuilder.Create(ARequest, mSlot, mSource, mSource.RoutineAt);
      try
        mBuilder.AddLocal(AInlineVar);
        mBuilder.AddField;
        mBuilder.AddConstant;
        AItems := mBuilder.Items;
      finally
        mBuilder.Free;
      end;
    end;
  finally
    mSource.Free;
  end;
  Result := AItems <> nil;
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
  AItem.TextEdit := TRuleEdit.Create(TTextRange.Create(mContext.ChainStart, ARequest.Position), '');
  FillAssignText(AItem, mFields, mExpr, Copy(mLineText, 1, mContext.ChainStart.Character), ARequest.LineBreak,
    ASnippets);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Completion.Values', cTexts);

end.
