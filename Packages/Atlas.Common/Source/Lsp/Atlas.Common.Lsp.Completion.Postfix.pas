unit Atlas.Common.Lsp.Completion.Postfix;

// Postfix-Vorlagen (#188): Hinter "Ausdruck." kommen nach den Mitgliedern Kürzel wie for, tryf, ifa und fmt,
// die den Ausdruck ersetzen (textEdit ab Ausdrucksbeginn, filterText "Ausdruck.Kürzel"), sofern der Typ bekannt
// ist und passt. Aus Atlas.Common.Lsp.Completion herausgelöst.

interface

{$SCOPEDENUMS ON}

uses
  System.JSON,
  Atlas.Common.Editing.PostfixTemplates,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest;

type
  /// <summary>Postfix-Vorlagen (#188) je Dokument.</summary>
  TPostfixOptions = record
    Enabled: Boolean;
    /// <summary>for var Item in … (ab Delphi 10.3 und refactoring.inlineVar); sonst Eintrag im var-Abschnitt.
    /// </summary>
    InlineVar: Boolean;
    /// <summary>Als LSP-Snippet mit Platzhaltern und Endposition (snippetSupport des Clients).</summary>
    Snippet: Boolean;
    /// <summary>Eigene Vorlagen des Plugins (atlas/postfixTemplates).</summary>
    Custom: TArray<TPostfixTemplate>;
    class function Default: TPostfixOptions; static;
  end;

  TCompletionPostfix = class
  public
    /// <summary>Postfix-Vorlagen hinter "Ausdruck." am Cursor (AContext) für ACandidates (die Mitglieder des
    /// Ausdrucks); nur einzeilige Ausdrücke mit bekanntem Typ.</summary>
    class function Items(ARequest: TCompletionRequest; const AContext: TCompletionContext;
      const ACandidates: TArray<TResolvedSymbol>; const APostfix: TPostfixOptions): TArray<TCompletionItem>; static;
    /// <summary>Eigene Postfix-Vorlagen: {"templates": [{"key", "description", "body", "type"}]}; Kürzel nur aus
    /// Buchstaben, Ziffern und _.</summary>
    class function ParseTemplates(const AParams: TJSONValue): TArray<TPostfixTemplate>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Lsp.CompletionCollector;

type
  TSymbolKinds = set of TIndexSymbolKind;

  /// <summary>Die Zeile des Ausdrucks: Text davor, Einrückung und der Ausdruck selbst.</summary>
  TPostfixLine = record
    LineText: string;
    Before: string;
    Indent: string;
    Expr: string;
  end;

  /// <summary>Baut die Einträge der Postfix-Vorlagen für einen Ausdruck.</summary>
  TPostfixBuilder = class
  private
    FRequest: TCompletionRequest;
    FContext: TCompletionContext;
    FPostfix: TPostfixOptions;
    FTraits: TPostfixTraits;
    FLine: TPostfixLine;
    FDescends: TFunc<string, Boolean>;
    function Fits(const ATemplate: TPostfixTemplate): Boolean;
    function DeclarationEdit(const ADeclaration: string; out AEdit: TRuleEdit): Boolean;
    function ItemOf(const ATemplate: TPostfixTemplate; out AItem: TCompletionItem): Boolean;
  public
    constructor Create(ARequest: TCompletionRequest; const AContext: TCompletionContext;
      const APostfix: TPostfixOptions);
    function Build(const ACandidates: TArray<TResolvedSymbol>): TArray<TCompletionItem>;
  end;

{ TPostfixOptions }

class function TPostfixOptions.Default: TPostfixOptions;
begin
  Result := System.Default(TPostfixOptions);
  Result.Enabled := True;
  Result.InlineVar := True;
end;

/// <summary>Innerste Routine, die AOffset enthält; nil außerhalb von Routinen. Schleife statt Rekursion
/// (Bericht M1): dem ersten Kind folgen, das AOffset enthält.</summary>
function InnermostRoutine(ARoot: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
  mNode, mChild: TSyntaxNode;
begin
  Result := nil;
  mNode := ARoot;
  while mNode <> nil do
  begin
    mChild := nil;
    for mIndex := 0 to mNode.ChildCount - 1 do
    begin
      if (mNode[mIndex].StartOffset <= AOffset) and (AOffset <= mNode[mIndex].EndOffset) then
      begin
        mChild := mNode[mIndex];
        Break;
      end;
    end;
    if (mChild <> nil) and (mChild.Kind = TSyntaxKind.RoutineDecl) then
    begin
      Result := mChild;
    end;
    mNode := mChild;
  end;
end;

/// <summary>Steht AOffset in einer Funktion (Result verfügbar)?</summary>
function InFunctionAt(ATree: TSyntaxTree; const AText: string; AOffset: Integer): Boolean;
var
  mRoutine: TSyntaxNode;
  mHead: string;
begin
  mRoutine := nil;
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    mRoutine := InnermostRoutine(ATree.Root, AOffset);
  end;
  if mRoutine = nil then
  begin
    Exit(False);
  end;
  mHead := LowerCase(TrimLeft(Copy(AText, mRoutine.StartOffset + 1, 40)));
  if StartsStr('class ', mHead) then
  begin
    mHead := TrimLeft(Copy(mHead, Length('class ') + 1, MaxInt));
  end;
  Result := StartsStr('function', mHead) or StartsStr('operator', mHead);
end;

/// <summary>Typ der Kette am Cursor, wenn sie einen Wert liefert; ein Typ ist kein Wert, außer als
/// Typumwandlung TFoo(X) (#188).</summary>
function ValueChain(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  out AChain: TResolvedChainType): Boolean;
begin
  Result := ARequest.Resolver.ChainType(ARequest.Tree, ARequest.FileName, AContext.Names, AContext.Offset, AChain) and
    (AChain.Owner.Kind <> TResolvedKind.UnitName) and (AContext.Called or not AChain.Owner.IsType);
end;

/// <summary>Typ des Ausdrucks samt Typargumenten (TArray mit TypeArgs Integer); '' ohne.</summary>
function OwnerTypeOf(const AChain: TResolvedChainType): string;
begin
  Result := AChain.Owner.TypeName;
  if AChain.Owner.IsType then
  begin
    Result := AChain.Owner.Name;
  end;
  if AChain.Owner.TypeArgs <> '' then
  begin
    Result := Result + '<' + AChain.Owner.TypeArgs + '>';
  end;
end;

/// <summary>Typ für eine Deklaration im var-Abschnitt; TFoo.Create liefert ein TFoo. Dazu der Elementtyp.
/// </summary>
procedure SetTypeNames(var ATraits: TPostfixTraits; const AChain: TResolvedChainType; const AOwnerType: string);
begin
  if AChain.Owner.SymbolKind = TIndexSymbolKind.Constructor_ then
  begin
    ATraits.IsConstructorCall := True;
    ATraits.TypeName := AChain.Owner.Container;
  end
  else if AOwnerType <> '' then
  begin
    ATraits.TypeName := AOwnerType;
  end
  else if AChain.TypeFound then
  begin
    ATraits.TypeName := AChain.TypeInfo.Name;
  end;
  ATraits.ElementType := TPostfixTemplates.ElementOf(AOwnerType);
  if (ATraits.ElementType = '') and AChain.TypeFound then
  begin
    ATraits.ElementType := TPostfixTemplates.ElementOf(AChain.TypeInfo.TypeName);
  end;
  ATraits.Enumerable := ATraits.ElementType <> '';
end;

/// <summary>Ist der Typ der Kette ein eigener (nicht eingebauter) Typ der Art AKinds?</summary>
function OwnTypeOf(const AChain: TResolvedChainType; const AKinds: TSymbolKinds): Boolean;
begin
  Result := AChain.TypeFound and not AChain.TypeInfo.Builtin and (AChain.TypeInfo.SymbolKind in AKinds);
end;

/// <summary>Elementtyp für die klassische Schleife: Current des Enumerators; '' ohne.</summary>
function EnumeratorElement(ARequest: TCompletionRequest; const AContext: TCompletionContext): string;
var
  mEnumerator: TResolvedSymbol;
begin
  Result := '';
  for mEnumerator in ARequest.Resolver.Candidates.MemberCandidates(ARequest.Tree, ARequest.FileName,
    AContext.Names + ['GetEnumerator'], AContext.Offset) do
  begin
    if SameText(mEnumerator.Name, 'Current') then
    begin
      Result := mEnumerator.TypeName;
    end;
  end;
end;

/// <summary>Hat AMembers ein GetEnumerator?</summary>
function HasEnumerator(const AMembers: TArray<TResolvedSymbol>): Boolean;
var
  mMember: TResolvedSymbol;
begin
  for mMember in AMembers do
  begin
    if SameText(mMember.Name, 'GetEnumerator') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Name des eingebauten Typs der Kette; '' bei eigenen oder unbekannten Typen.</summary>
function BuiltinName(const AChain: TResolvedChainType): string;
begin
  Result := '';
  if AChain.TypeFound and AChain.TypeInfo.Builtin then
  begin
    Result := AChain.TypeInfo.Name;
  end;
end;

/// <summary>Zeichenkette, Wahrheitswert, Klasse oder Referenz (Klasse, Interface, Zeiger)?</summary>
procedure SetKinds(var ATraits: TPostfixTraits; const AChain: TResolvedChainType);
var
  mBuiltin: string;
begin
  mBuiltin := BuiltinName(AChain);
  ATraits.IsString := TPostfixTemplates.IsStringType(AChain.Owner.TypeName) or
    ((mBuiltin <> '') and TPostfixTemplates.IsStringType(mBuiltin));
  ATraits.IsBoolean := TPostfixTemplates.IsBooleanType(AChain.Owner.TypeName) or
    ((mBuiltin <> '') and TPostfixTemplates.IsBooleanType(mBuiltin));
  ATraits.IsClass := OwnTypeOf(AChain, [TIndexSymbolKind.ClassType]);
  ATraits.IsReference := OwnTypeOf(AChain, [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType]) or
    TPostfixTemplates.IsPointerType(AChain.Owner.TypeName) or
    (AChain.TypeFound and TPostfixTemplates.IsPointerType(AChain.TypeInfo.TypeName));
end;

/// <summary>Was über den Typ der Kette bekannt ist; False, wenn er unbekannt ist oder kein Wert vorliegt.</summary>
function PostfixTraits(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  const AMembers: TArray<TResolvedSymbol>; out ATraits: TPostfixTraits): Boolean;
var
  mChain: TResolvedChainType;
  mElement: string;
begin
  ATraits := Default(TPostfixTraits);
  if not ValueChain(ARequest, AContext, mChain) then
  begin
    Exit(False);
  end;
  SetTypeNames(ATraits, mChain, OwnerTypeOf(mChain));
  if OwnTypeOf(mChain, [TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType]) and
    HasEnumerator(AMembers) then
  begin
    ATraits.Enumerable := True;
    mElement := EnumeratorElement(ARequest, AContext);
    if mElement <> '' then
    begin
      ATraits.ElementType := mElement;
    end;
  end;
  SetKinds(ATraits, mChain);
  Result := mChain.TypeFound or ATraits.Enumerable or ATraits.IsString or ATraits.IsReference;
end;

/// <summary>Eigene Vorlagen mit Typname als Bedingung: der Typ selbst oder ein Nachfahr. Eigene Routine, damit
/// die anonyme Methode nur diese Werte einfängt.</summary>
function DescendsFunc(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string; AOffset: Integer;
  const ATypeName: string): TFunc<string, Boolean>;
begin
  Result :=
    function(AAncestor: string): Boolean
    begin
      Result := AResolver.Queries.TypeDescendsFrom(ATree, AFileName, AOffset, ATypeName, AAncestor);
    end;
end;

{ TPostfixBuilder }

constructor TPostfixBuilder.Create(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  const APostfix: TPostfixOptions);
begin
  inherited Create;
  FRequest := ARequest;
  FContext := AContext;
  FPostfix := APostfix;
end;

function TPostfixBuilder.Fits(const ATemplate: TPostfixTemplate): Boolean;
begin
  Result := TPostfixTemplates.Applies(ATemplate, FTraits, FPostfix.InlineVar, FDescends) and
    not (ATemplate.Statement and (Trim(FLine.Before) <> '')) and
    (MatchScore(ATemplate.Key, FContext.Prefix, FRequest.Matching) <> TFuzzyMatch.NoMatch);
end;

function TPostfixBuilder.DeclarationEdit(const ADeclaration: string; out AEdit: TRuleEdit): Boolean;
var
  mSlash: TSlashContext;
  mSource: TCommandSource;
  mRoutine: TSyntaxNode;
begin
  AEdit := Default(TRuleEdit);
  mSlash := Default(TSlashContext);
  mSlash.Text := FRequest.Text;
  mSlash.Line := FRequest.Position.Line;
  mSlash.LineText := FLine.LineText;
  mSource := TCommandSource.Create(mSlash);
  try
    mRoutine := mSource.RoutineAt;
    Result := mRoutine <> nil;
    if Result then
    begin
      AEdit := AddLocal(mSource, mRoutine, TSyntaxKind.VarSection, 'var', ADeclaration);
    end;
  finally
    mSource.Free;
  end;
end;

function TPostfixBuilder.ItemOf(const ATemplate: TPostfixTemplate; out AItem: TCompletionItem): Boolean;
var
  mExpansion: TPostfixExpansion;
  mEdit: TRuleEdit;
begin
  mExpansion := TPostfixTemplates.Expand(ATemplate, FLine.Expr, FTraits,
    TPostfixLayout.Create(FLine.Indent, FRequest.LineBreak, FPostfix.InlineVar, FPostfix.Snippet));
  AItem := Default(TCompletionItem);
  AItem.Name := ATemplate.Key;
  AItem.Detail := ATemplate.Description;
  AItem.Kind := KindSnippet;
  // Der Editor filtert über "Ausdruck.Kürzel"; Atlas kennzeichnet den Eintrag als Postfix.
  AItem.FilterText := FLine.Expr + '.' + ATemplate.Key;
  AItem.Action := 'postfix';
  AItem.Snippet := FPostfix.Snippet;
  AItem.HasTextEdit := True;
  AItem.TextEdit := TRuleEdit.Create(TTextRange.Create(FContext.ChainStart, FRequest.Position), mExpansion.Text);
  Result := True;
  if mExpansion.Declaration <> '' then
  begin
    // Ohne Inline-Variable: Deklaration in den var-Abschnitt der Routine.
    Result := DeclarationEdit(mExpansion.Declaration, mEdit);
    AItem.AdditionalEdits := [mEdit];
  end;
end;

function TPostfixBuilder.Build(const ACandidates: TArray<TResolvedSymbol>): TArray<TCompletionItem>;
var
  mTemplate: TPostfixTemplate;
  mItem: TCompletionItem;
begin
  Result := nil;
  // Nur einzeilige Ausdrücke; der Typ muss bekannt sein.
  if (FContext.ChainStart.Line <> FRequest.Position.Line) or (FContext.DotPos.Line <> FRequest.Position.Line) or
    not PostfixTraits(FRequest, FContext, ACandidates, FTraits) then
  begin
    Exit;
  end;
  FTraits.InFunction := InFunctionAt(FRequest.Tree, FRequest.Text, FContext.Offset);
  FLine.LineText := FRequest.LineText(FRequest.Position.Line);
  FLine.Before := Copy(FLine.LineText, 1, FContext.ChainStart.Character);
  FLine.Indent := Copy(FLine.LineText, 1, Length(FLine.LineText) - Length(TrimLeft(FLine.LineText)));
  FLine.Expr := Copy(FLine.LineText, FContext.ChainStart.Character + 1,
    FContext.DotPos.Character - FContext.ChainStart.Character);
  FDescends := DescendsFunc(FRequest.Resolver, FRequest.Tree, FRequest.FileName, FContext.Offset, FTraits.TypeName);
  for mTemplate in TPostfixTemplates.Templates + FPostfix.Custom do
  begin
    if Fits(mTemplate) and ItemOf(mTemplate, mItem) then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

{ TCompletionPostfix }

class function TCompletionPostfix.Items(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  const ACandidates: TArray<TResolvedSymbol>; const APostfix: TPostfixOptions): TArray<TCompletionItem>;
var
  mBuilder: TPostfixBuilder;
begin
  mBuilder := TPostfixBuilder.Create(ARequest, AContext, APostfix);
  try
    Result := mBuilder.Build(ACandidates);
  finally
    mBuilder.Free;
  end;
end;

class function TCompletionPostfix.ParseTemplates(const AParams: TJSONValue): TArray<TPostfixTemplate>;
var
  mTemplates, mValue: TJSONValue;
  mItem: TJSONObject;
  mKey, mBody: string;
begin
  Result := nil;
  mTemplates := nil;
  if AParams is TJSONObject then
  begin
    mTemplates := TJSONObject(AParams).GetValue('templates');
  end;
  if not (mTemplates is TJSONArray) then
  begin
    Exit;
  end;
  for mValue in TJSONArray(mTemplates) do
  begin
    if not (mValue is TJSONObject) then
    begin
      Continue;
    end;
    mItem := TJSONObject(mValue);
    mKey := mItem.GetValue<string>('key', '');
    mBody := mItem.GetValue<string>('body', '');
    // Nur Kürzel aus Buchstaben, Ziffern und _; sie stehen hinter einem Punkt.
    if (mKey <> '') and (mBody <> '') and IsValidIdent(mKey) then
    begin
      Result := Result + [TPostfixTemplate.Custom(mKey, mItem.GetValue<string>('description', ''), mBody,
        mItem.GetValue<string>('type', ''))];
    end;
  end;
end;

end.
