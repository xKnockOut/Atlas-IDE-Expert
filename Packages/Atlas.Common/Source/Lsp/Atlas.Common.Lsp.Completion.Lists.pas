unit Atlas.Common.Lsp.Completion.Lists;

// Die Vorschlagsliste an einer Stelle (#31, #180, #616): Units in uses, Mitglieder nach "A.", Vorfahrmethoden
// nach "inherited ", sonst eigener Gültigkeitsbereich, Units aus uses und Importe; dazu Typargumente (#450),
// Attribute (#465), Exception-Klassen (#483), Postfix-Vorlagen (#188) und kontextabhängige Code-Vorlagen (#51).
// Aus Atlas.Common.Lsp.Completion herausgelöst.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.Completion.Postfix;

type
  TCompletionLists = class
  public
    /// <summary>Die Liste an APosition, gestaffelt (#616): AOnPartial bekommt zuerst den eigenen
    /// Gültigkeitsbereich, dann die Units aus uses; das Ergebnis enthält nur noch den Rest (Importe, nicht
    /// verfügbare, Postfix-Vorlagen). Ohne AOnPartial alles im Ergebnis. Baum, Resolver, Index, Text, Position und
    /// Matching kommen aus ARequest.</summary>
    class function Collect(ARequest: TCompletionRequest; const APostfix: TPostfixOptions;
      const AOnPartial: TCompletionPartialProc): TCompletionItems; overload; static;
    /// <summary>Wie oben ohne Text, Postfix-Vorlagen und Staffelung.</summary>
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition;
      AMatching: TCompletionMatching): TCompletionItems; overload; static;
    /// <summary>Wie oben mit AMatching = Fuzzy.</summary>
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition): TCompletionItems; overload; static;
    /// <summary>Kontextabhängige Code-Vorlagen (#51) für die Zeile der Position von ARequest: prop, changed,
    /// create, free. Mit ASnippetSupport als LSP-Snippet, sonst als Klartext ohne Platzhalter.</summary>
    class function ContextItems(ARequest: TCompletionRequest; const ANamespaces: TArray<string>;
      ASnippetSupport: Boolean): TArray<TCompletionItem>; overload; static;
    /// <summary>Wie oben, mit Text, Position, Index und Matching einzeln.</summary>
    class function ContextItems(const AIndex: ISymbolIndex; const ANamespaces: TArray<string>; const AText: string;
      const APosition: TTextPosition; AMatching: TCompletionMatching;
      ASnippetSupport: Boolean): TArray<TCompletionItem>; overload; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.ContextSnippets,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.CompletionUses,
  Atlas.Common.Lsp.CompletionGenerics,
  Atlas.Common.Lsp.CompletionAttributes,
  Atlas.Common.Lsp.CompletionExceptions,
  Atlas.Common.Lsp.Completion.Context,
  Atlas.Common.Lsp.Completion.InheritedCalls;

const
  /// <summary>Art der Stelle im Diagnoselog (#647).</summary>
  cContextCodes: array[TCompletionContextKind] of string = ('none', 'scope', 'memberAccess', 'uses');
  cTypeKeywords: array[0..7] of string = ('string', 'array', 'set', 'record', 'packed', 'procedure', 'function',
    'reference');

type
  /// <summary>Baut die Liste für eine Anfrage; hält, was die Schritte teilen.</summary>
  TListBuilder = class
  private
    FRequest: TCompletionRequest;
    FPostfix: TPostfixOptions;
    FContext: TCompletionContext;
    FOnPartial: TCompletionPartialProc;
    FGenericOwner: TResolvedSymbol;
    FCollector: TCompletionCollector;
    FCandidates: TArray<TResolvedSymbol>;
    procedure PrepareGeneric;
    procedure PrepareFilters;
    procedure NoteDiagnostics;
    procedure AddUnits;
    procedure AddMembers;
    procedure AddInherited;
    procedure AddScope;
    procedure AddImports;
    procedure AddNamed;
    function Finish: TCompletionItems;
  public
    constructor Create(ARequest: TCompletionRequest; const APostfix: TPostfixOptions;
      const AOnPartial: TCompletionPartialProc);
    function Build: TCompletionItems;
  end;

/// <summary>Schlüsselwörter passend zur Stelle (#31), erst ab einem getippten Zeichen; ohne Eingabe gingen die
/// Namen darin unter.</summary>
function KeywordsAt(const AContext: TCompletionContext): TArray<string>;
var
  mWord: string;
begin
  Result := nil;
  if AContext.Prefix = '' then
  begin
    Exit;
  end;
  if AContext.Filter <> TCompletionFilter.Types then
  begin
    Result := TCompletionContexts.Keywords(AContext.Place);
    Exit;
  end;
  if AContext.TypeKeywords then
  begin
    for mWord in cTypeKeywords do
    begin
      Result := Result + [mWord];
    end;
  end;
end;

/// <summary>Exception-Klassen, die schon ohne Eingabe aus nicht eingebundenen Units kommen (#483): die gängigen
/// und, nach "on E: ", die aus dem try-Block.</summary>
function ExceptionImportNames(ARequest: TCompletionRequest; const AContext: TCompletionContext): TArray<string>;
var
  mSite: TExceptionSite;
  mName: string;
  mUnits: TArray<string>;
begin
  Result := nil;
  for mName in TCompletionExceptions.cCommonNames do
  begin
    Result := Result + [mName];
  end;
  if not TCompletionExceptions.SiteAt(ARequest.Tree.Tokens, AContext.ExceptionToken, mSite) then
  begin
    Exit;
  end;
  for mName in TCompletionExceptions.TryClasses(ARequest, mSite, mUnits) do
  begin
    if IndexText(mName, Result) < 0 then
    begin
      Result := Result + [mName];
    end;
  end;
end;

/// <summary>Getipptes Wort vor dem Cursor in ALineText; AStart ist die Spalte davor.</summary>
function WordBefore(const ALineText: string; ACharacter: Integer; out AStart: Integer): string;
begin
  AStart := Min(ACharacter, Length(ALineText));
  while (AStart > 0) and CharInSet(ALineText[AStart], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
  begin
    Dec(AStart);
  end;
  Result := Copy(ALineText, AStart + 1, ACharacter - AStart);
end;

/// <summary>Eintrag für ASnippet; ersetzt ab AStart bis zum Cursor.</summary>
function SnippetItem(ARequest: TCompletionRequest; const ASnippet: TContextSnippet; AStart: Integer;
  ASnippetSupport: Boolean): TCompletionItem;
var
  mText: string;
begin
  Result := Default(TCompletionItem);
  Result.Name := ASnippet.Name;
  Result.Detail := ASnippet.Description;
  Result.Kind := cKindSnippet;
  Result.FilterText := ASnippet.Prefix;
  Result.HasTextEdit := True;
  Result.Snippet := ASnippetSupport;
  mText := ASnippet.Text;
  if not ASnippetSupport then
  begin
    mText := TContextSnippets.ToPlain(mText);
  end;
  Result.TextEdit := TRuleEdit.Create(TTextRange.Create(ARequest.Position.Line, AStart, ARequest.Position.Line,
    ARequest.Position.Character), mText);
  Result.AdditionalEdits := ASnippet.AdditionalEdits;
  // Atlas wertet die weiteren Änderungen dann nicht als uses-Ergänzung.
  Result.Action := 'snippet';
end;

{ TListBuilder }

constructor TListBuilder.Create(ARequest: TCompletionRequest; const APostfix: TPostfixOptions;
  const AOnPartial: TCompletionPartialProc);
begin
  inherited Create;
  FRequest := ARequest;
  FPostfix := APostfix;
  FOnPartial := AOnPartial;
  FGenericOwner := Default(TResolvedSymbol);
end;

procedure TListBuilder.PrepareGeneric;
var
  mCandidate: TResolvedSymbol;
begin
  // Typargument (#450): nur Typen, gefiltert nach den Constraints. Nicht gestaffelt, weil erst die ganze
  // Liste gefiltert wird.
  if not FContext.Generic or not FRequest.Settings.GenericConstraints then
  begin
    FContext.Generic := False;
    Exit;
  end;
  FContext.Generic := False;
  for mCandidate in FRequest.Resolver.ResolveAll(FRequest.Tree, FRequest.FileName, FContext.GenericOwnerPos) do
  begin
    if mCandidate.IsType and (mCandidate.TypeParams <> '') then
    begin
      FGenericOwner := mCandidate;
      FContext.Generic := True;
      FContext.Filter := TCompletionFilter.Types;
      FContext.TypeKeywords := False;
      FOnPartial := nil;
      Exit;
    end;
  end;
end;

procedure TListBuilder.PrepareFilters;
begin
  // Attribute (#465) und Exception-Klassen (#483): erst die ganze Liste filtern und sortieren, deshalb nicht
  // gestaffelt; abgeschaltet die gewöhnliche Liste.
  if FContext.Attribute and not FRequest.Settings.Attributes then
  begin
    FContext.Attribute := False;
    FContext.Filter := TCompletionFilter.Any;
  end;
  if FContext.Exceptions and not FRequest.Settings.ExceptionClasses then
  begin
    FContext.Exceptions := False;
    FContext.Filter := TCompletionFilter.Any;
  end;
  if FContext.Attribute or FContext.Exceptions then
  begin
    FOnPartial := nil;
  end;
end;

procedure TListBuilder.NoteDiagnostics;
begin
  // Diagnoselog (#647): nur Art und Längen, nie die Namen selbst.
  TRequestDiagnostics.Note('ctx', cContextCodes[FContext.Kind]);
  TRequestDiagnostics.Note('prefixLen', Length(FContext.Prefix));
  if FContext.Kind = TCompletionContextKind.Member then
  begin
    TRequestDiagnostics.Note('chainLen', Length(FContext.Names));
  end
  else if FContext.Kind = TCompletionContextKind.None then
  begin
    TRequestDiagnostics.Reason('noContext');
  end;
end;

procedure TListBuilder.AddUnits;
var
  mUnit: TUnitIndex;
begin
  // Gruppen, Hinweise und Zirkelbezüge (#469); aus: alle Units als schlichte Liste.
  if FRequest.Settings.UsesDetails then
  begin
    TCompletionUses.Collect(FRequest, FContext, FCollector);
    Exit;
  end;
  for mUnit in FRequest.Index.Units do
  begin
    FCollector.Add(mUnit.UnitName, mUnit.FileName, cKindModule, Default(TResolvedSymbol));
  end;
end;

procedure TListBuilder.AddMembers;
begin
  // Nur passende Namen aufbauen (#616); der Filter gilt nur beim Sammeln, nicht für die Typprüfungen in Add.
  // Die Postfix-Vorlagen brauchen die Mitglieder (GetEnumerator).
  FCollector.SetNameFilter(True);
  try
    FCandidates := FRequest.Resolver.Candidates.MemberCandidates(FRequest.Tree, FRequest.FileName, FContext.Names,
      FContext.Offset);
  finally
    FCollector.SetNameFilter(False);
  end;
  FCollector.AddCandidates(FCandidates);
  FCollector.AddUnavailableMembers(FCandidates);
  // Helper aus nicht eingebundenen Units mit uses-Eintrag (#456), wie Symbole bei #180.
  FCollector.AddHelpersFromOtherUnits(FRequest.Resolver.Candidates.ReceiverTypes(FRequest.Tree, FRequest.FileName,
    FContext.Names, FContext.Offset));
end;

procedure TListBuilder.AddInherited;
begin
  // Nach "inherited " nur Methoden der Vorfahren (#31).
  FCollector.SetNameFilter(True);
  try
    FCandidates := FRequest.Resolver.Candidates.InheritedCandidates(FRequest.Tree, FRequest.FileName,
      FContext.Offset);
  finally
    FCollector.SetNameFilter(False);
  end;
  // Vollständiger Aufruf mit den eigenen Parametern zuerst (#482).
  if FRequest.Settings.InheritedCall then
  begin
    TCompletionInheritedCalls.Add(FRequest, FContext, FCollector, FCandidates);
  end;
  FCollector.AddCandidates(FCandidates);
end;

procedure TListBuilder.AddScope;
begin
  // Eigener Gültigkeitsbereich zuerst (#616): lokal, Self, eigene Unit; dann die Units aus uses.
  FCollector.SetNameFilter(True);
  try
    FCandidates := FRequest.Resolver.Candidates.OwnScopeCandidates(FRequest.Tree, FRequest.FileName,
      FContext.Offset);
  finally
    FCollector.SetNameFilter(False);
  end;
  FCollector.AddCandidates(FCandidates);
  FCollector.MarkUsedShadows;
  FCollector.SendStage;
  FCollector.SetNameFilter(True);
  try
    // Mit Eingabe auch die Bezeichner von System ohne Quelltext (#880): Assigned, SetLength, Integer ... Ohne
    // Eingabe nicht, die Liste ist dann ohnehin unvollständig (Incomplete).
    FCandidates := FRequest.Resolver.Candidates.UsedScopeCandidates(FContext.Prefix <> '');
  finally
    FCollector.SetNameFilter(False);
  end;
  FCollector.AddCandidates(FCandidates);
  // Gleichnamige Bezeichner aus anderen Units direkt hinter der aktiven Variante (#475).
  FCollector.AddSameNameVariants;
end;

procedure TListBuilder.AddImports;
begin
  // Danach die nicht eingebundenen Units.
  FCollector.SendStage;
  if Length(FContext.Prefix) >= cCompletionMinImportPrefix then
  begin
    FCollector.AddFromOtherUnits;
    // Typen aus den Packages der IDE, die der Index nicht kennt (Units ohne Quelltext).
    FCollector.AddIdeTypes;
  end
  else if FContext.Attribute then
  begin
    // Bekannte Attribute (DUnitX, JSON) schon nach "[" mit uses-Eintrag (#465).
    FCollector.AddFromOtherUnits(TCompletionAttributes.KnownClassNames);
  end
  else if FContext.Exceptions then
  begin
    // Gängige Exception-Klassen schon nach "raise " bzw. "on E: " mit uses-Eintrag (#483).
    FCollector.AddFromOtherUnits(ExceptionImportNames(FRequest, FContext));
  end;
  FCollector.AddUnavailable;
  FCollector.AddKeywords(KeywordsAt(FContext));
end;

procedure TListBuilder.AddNamed;
begin
  if FContext.Kind = TCompletionContextKind.Member then
  begin
    AddMembers;
  end
  else if FContext.Filter = TCompletionFilter.InheritedCall then
  begin
    AddInherited;
  end
  else
  begin
    AddScope;
    AddImports;
  end;
end;

function TListBuilder.Finish: TCompletionItems;
var
  mPostfix: TArray<TCompletionItem>;
begin
  // Postfix-Vorlagen stehen immer hinter den echten Mitgliedern.
  mPostfix := nil;
  if (FContext.Kind = TCompletionContextKind.Member) and FPostfix.Enabled and (FRequest.Text <> '') then
  begin
    mPostfix := TCompletionPostfix.Items(FRequest, FContext, FCandidates, FPostfix);
  end;
  Result := Default(TCompletionItems);
  Result.Items := FCollector.Finish(Result.Incomplete);
  if FContext.Generic then
  begin
    Result.Items := TCompletionGenerics.Apply(FRequest, FContext, FGenericOwner, Result.Items);
  end;
  if FContext.Attribute then
  begin
    Result.Items := TCompletionAttributes.Apply(FRequest, FContext, Result.Items);
  end;
  if FContext.Exceptions then
  begin
    // Platzhalter wie bei den Postfix-Vorlagen nach snippetSupport des Clients.
    Result.Items := TCompletionExceptions.Apply(FRequest, FContext, FPostfix.Snippet, Result.Items);
  end;
  Result.Items := Result.Items + mPostfix;
end;

function TListBuilder.Build: TCompletionItems;
var
  mExpected: string;
begin
  FContext := TCompletionContexts.Analyze(FRequest.Tree, FRequest.Position);
  PrepareGeneric;
  PrepareFilters;
  NoteDiagnostics;
  mExpected := '';
  if FContext.Kind in [TCompletionContextKind.Member, TCompletionContextKind.Scope] then
  begin
    mExpected := TCompletionContexts.ExpectedType(FRequest.Resolver, FRequest.Tree, FRequest.FileName,
      FRequest.Position);
  end;
  // Viele Auflösungen auf demselben Baum: einmal auswerten (Code-Review P-02). Hat Handle den Baum schon
  // gepinnt, zählt das nur hoch.
  if FRequest.Tree <> nil then
  begin
    FRequest.Resolver.PinTree(FRequest.Tree, FRequest.FileName);
  end;
  FCollector := TCompletionCollector.Create(FRequest, FContext, mExpected, FOnPartial);
  try
    if FContext.Attribute then
    begin
      FCollector.SetAdmit(TCompletionAttributes.Admit(FRequest.Resolver));
    end;
    if FContext.Exceptions then
    begin
      FCollector.SetAdmit(TCompletionExceptions.Admit(FRequest.Resolver));
    end;
    if FContext.Kind = TCompletionContextKind.UsesClause then
    begin
      AddUnits;
    end
    else if FContext.Kind in [TCompletionContextKind.Member, TCompletionContextKind.Scope] then
    begin
      AddNamed;
    end;
    Result := Finish;
  finally
    FreeAndNil(FCollector);
    if FRequest.Tree <> nil then
    begin
      FRequest.Resolver.UnpinTree;
    end;
  end;
end;

{ TCompletionLists }

class function TCompletionLists.Collect(ARequest: TCompletionRequest; const APostfix: TPostfixOptions;
  const AOnPartial: TCompletionPartialProc): TCompletionItems;
var
  mBuilder: TListBuilder;
begin
  mBuilder := TListBuilder.Create(ARequest, APostfix, AOnPartial);
  try
    Result := mBuilder.Build;
  finally
    mBuilder.Free;
  end;
end;

class function TCompletionLists.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; AMatching: TCompletionMatching): TCompletionItems;
var
  mRequest: TCompletionRequest;
  mPostfix: TPostfixOptions;
begin
  mPostfix := TPostfixOptions.Default;
  mPostfix.Enabled := False;
  mRequest := TCompletionRequest.Create('', AFileName, APosition);
  try
    mRequest.Tree := ATree;
    mRequest.Resolver := AResolver;
    mRequest.Index := AIndex;
    mRequest.Matching := AMatching;
    Result := Collect(mRequest, mPostfix, nil);
  finally
    mRequest.Free;
  end;
end;

class function TCompletionLists.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition): TCompletionItems;
begin
  Result := Collect(AResolver, AIndex, ATree, AFileName, APosition, TCompletionMatching.Fuzzy);
end;

class function TCompletionLists.ContextItems(ARequest: TCompletionRequest; const ANamespaces: TArray<string>;
  ASnippetSupport: Boolean): TArray<TCompletionItem>;
var
  mSlash: TSlashContext;
  mSnippet: TContextSnippet;
  mLineText, mWord: string;
  mStart: Integer;
begin
  Result := nil;
  mLineText := ARequest.LineText(ARequest.Position.Line);
  // TContextSnippets prüft, dass sonst nichts in der Zeile steht.
  mWord := WordBefore(mLineText, ARequest.Position.Character, mStart);
  mSlash := Default(TSlashContext);
  mSlash.Text := ARequest.Text;
  mSlash.Line := ARequest.Position.Line;
  mSlash.LineText := mLineText;
  mSlash.Index := ARequest.Index;
  mSlash.Namespaces := ANamespaces;
  for mSnippet in TContextSnippets.At(mSlash, ARequest.Position.Character) do
  begin
    if (MatchScore(mSnippet.Prefix, mWord, ARequest.Matching) <> TFuzzyMatch.cNoMatch) or
      (MatchScore(mSnippet.Name, mWord, ARequest.Matching) <> TFuzzyMatch.cNoMatch) then
    begin
      Result := Result + [SnippetItem(ARequest, mSnippet, mStart, ASnippetSupport)];
    end;
  end;
end;

class function TCompletionLists.ContextItems(const AIndex: ISymbolIndex; const ANamespaces: TArray<string>;
  const AText: string; const APosition: TTextPosition; AMatching: TCompletionMatching;
  ASnippetSupport: Boolean): TArray<TCompletionItem>;
var
  mRequest: TCompletionRequest;
begin
  mRequest := TCompletionRequest.Create(AText, '', APosition);
  try
    mRequest.Index := AIndex;
    mRequest.Matching := AMatching;
    Result := ContextItems(mRequest, ANamespaces, ASnippetSupport);
  finally
    mRequest.Free;
  end;
end;

end.
