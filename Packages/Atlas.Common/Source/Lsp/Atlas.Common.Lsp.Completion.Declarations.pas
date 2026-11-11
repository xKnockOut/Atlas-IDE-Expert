unit Atlas.Common.Lsp.Completion.Declarations;

// Vervollständigung in Deklarationen: Zugriffe in "property … read/write" (#31) samt Feld und
// Zugriffsmethoden anlegen (#467), überschreibbare Methoden (#443), fehlende Interface-Methoden (#466) und
// String-Literal als resourcestring auslagern (#473). Aus Atlas.Common.Lsp.Completion herausgelöst.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Lsp.CompletionRequest;

type
  TCompletionDeclarations = class
  public
    /// <summary>In "property Name: T read " bzw. "write " im Klassenrumpf (#31): Felder vom Typ T und Methoden
    /// mit passender Signatur (read: Funktion mit Ergebnis T und den Indexparametern; write: Prozedur mit den
    /// Indexparametern und einem Parameter vom Typ T), auch geerbte. Mit completion.createAccessors kommen
    /// davor „Feld F&lt;Name&gt; anlegen“ und „Get&lt;Name&gt;/Set&lt;Name&gt; anlegen“ (#467). False außerhalb
    /// dieses Kontexts.</summary>
    class function PropertyItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; static;
    /// <summary>Strg+Leer im String-Literal (#473): „Als resourcestring auslagern“ und, bei gleichem Text,
    /// „Vorhandenen verwenden“. ASnippets: Name als verknüpfter Platzhalter an Stelle und Deklaration. False
    /// außerhalb eines Literals, an unzulässigen Stellen, mit Auslösezeichen oder abgeschaltet.</summary>
    class function ResourceStringItems(ARequest: TCompletionRequest; ASnippets: Boolean;
      out AItems: TCompletionItems): Boolean; static;
    /// <summary>In einer Klassendeklaration nach "procedure " bzw. "function " (#443): überschreibbare
    /// Methoden der Vorfahren; Übernehmen setzt den Rest der Deklaration mit override und erzeugt den Rumpf
    /// mit inherited. Nach "override " beide Arten (#31). False außerhalb dieses Kontexts.</summary>
    class function OverrideItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; static;
    /// <summary>In der Deklaration einer Klasse mit Interfaces in der Vorfahrenliste (#466), wenn Methoden fehlen.
    /// Leere Zeile bis zum Cursor: je fehlender Methode ein Eintrag mit Kontrollkästchen (Batch), ABatch True.
    /// Angefangenes Wort: je Interface ein Hinweis „n Methoden von I fehlen“ (Hint), der alle seine fehlenden
    /// Methoden anlegt. Deklarationen kommen in den Abschnitt Settings.InterfaceSection (mit Kommentar
    /// "{ I }"), Rümpfe wie bei #443 ohne inherited. False außerhalb dieses Kontexts oder ohne fehlende
    /// Methoden.</summary>
    class function InterfaceItems(ARequest: TCompletionRequest; out AItems: TArray<TCompletionItem>;
      out ABatch: Boolean): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Editing.AccessorCreation,
  Atlas.Common.Editing.ResourceStrings,
  Atlas.Common.Editing.ContextSnippets,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.Internals.CompletionSource,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Deklarations-Vervollständigung in beiden Sprachen (#1458).</summary>
  TDeclarationText = (UseExisting, ExtractResource, MissingMethod, MissingMethods, ImplementInterface, CreateField,
    CreateMethod);

const
  cTexts: array[TDeclarationText] of TAtlasText = (
    (De: 'Vorhandenen verwenden: %s'; En: 'Use existing: %s'),
    (De: 'Als resourcestring auslagern'; En: 'Extract to resourcestring'),
    (De: '1 Methode von %s fehlt'; En: '1 method of %s is missing'),
    (De: '%d Methoden von %s fehlen'; En: '%d methods of %s are missing'),
    (De: 'Interface implementieren'; En: 'Implement interface'),
    (De: 'Feld %s anlegen'; En: 'Create field %s'),
    (De: '%s anlegen'; En: 'Create %s'));
  /// <summary>So viele Zeichen des Literals zeigt das Detail von „Als resourcestring auslagern“.</summary>
  cMaxLiteralPreview = 40;
  /// <summary>Befehl, der den Eintrag in der festgelegten resourcestring-Unit anlegt.</summary>
  cAddResourceCommand = 'atlas.server.addResourceString';
  cInterfaceSections: array[TCompletionInterfaceSection] of string = ('private', 'protected', 'public');
  cAccessorTitles: array[TAccessorKind] of TDeclarationText = (TDeclarationText.CreateField,
    TDeclarationText.CreateMethod, TDeclarationText.CreateMethod);

type
  /// <summary>Eine Property-Zeile "property Name[Index]: Typ read|write Anfang" im Klassenrumpf.</summary>
  TPropertySite = record
    Name: string;
    IndexParameters: string;
    PropertyType: string;
    IsWrite: Boolean;
    Prefix: string;
    TypeName: string;
  end;

  /// <summary>Wo die resourcestring-Deklaration hinkommt: eigene Unit oder festgelegte andere Unit.</summary>
  TResourceTarget = record
    Literal: TResourceLiteral;
    Taken: TArray<string>;
    HasTarget: Boolean;
    Target: TUnitIndex;
    UsesEdits: TArray<TRuleEdit>;
    HasExisting: Boolean;
    Existing: TResourceEntry;
  end;

  /// <summary>Eine Zeile "procedure Na", "class function " oder "override Na" im Klassenrumpf.</summary>
  TOverrideSite = record
    AfterOverride: Boolean;
    TypedClass: Boolean;
    TypedKind: string;
    /// <summary>Einrückung vor "override".</summary>
    IndentLength: Integer;
    TypeName: string;
  end;

  /// <summary>Zerlegte Deklaration einer überschreibbaren Methode.</summary>
  TOverrideDeclaration = record
    Declaration: string;
    IsClass: Boolean;
    Kind: string;
    Head: string;
    Directives: string;
  end;

  /// <summary>Baut die Einträge für fehlende Interface-Methoden (#466) einer Klasse.</summary>
  TInterfaceItemsBuilder = class
  private
    FRequest: TCompletionRequest;
    FBatch: Boolean;
    FItems: TArray<TCompletionItem>;
    FInterfaces: TArray<string>;
    FGroup: TArray<TRuleEdit>;
    FCount: Integer;
    FWordRange: TTextRange;
    FTypeName: string;
    FEndLine: Integer;
    FIndent: string;
    FSection: string;
    FNeedHeader: Boolean;
    function Prepare(out ATypeSymbol: TIndexSymbol): Boolean;
    function StubOf(const AMissing: TResolvedSymbol; const ASourceLines: TArray<string>;
      out AStub: TInterfaceStub): Boolean;
    function StubEdits(const AStub: TInterfaceStub): TArray<TRuleEdit>;
    procedure StartInterface(const AInterface: string);
    procedure AddHint;
    procedure AddBatchItem(const AStub: TInterfaceStub; const AMissing: TResolvedSymbol;
      const AEdits: TArray<TRuleEdit>);
    procedure AddMissing(const AMissing: TArray<TResolvedSymbol>);
    procedure MarkBatch;
  public
    constructor Create(ARequest: TCompletionRequest);
    function Build(out AItems: TArray<TCompletionItem>; out ABatch: Boolean): Boolean;
  end;

{ Property-Zugriffe }

/// <summary>Innerster Klassen- bzw. Objekttyp (mit ARecords auch Record), in dessen Deklaration ALine liegt;
/// ATypeName samt umgebendem Typ.</summary>
function EnclosingType(const AUnit: TUnitIndex; ALine: Integer; ARecords: Boolean; out ATypeName: string): Boolean;
var
  mKinds: TIndexSymbolKinds;
  mTypeSymbol: TIndexSymbol;
begin
  ATypeName := '';
  mKinds := [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType];
  if ARecords then
  begin
    Include(mKinds, TIndexSymbolKind.RecordType);
  end;
  Result := EnclosingTypeAt(AUnit, ALine, mKinds, 0, True, mTypeSymbol);
  if Result then
  begin
    ATypeName := QualifiedTypeName(mTypeSymbol);
  end;
end;

/// <summary>Erkennt "  property Wert[I: Integer]: Double read |", auch mit "index 3" und schon gesetztem read
/// vor write, im Rumpf einer Klasse bzw. eines Records.</summary>
function PropertySiteAt(ARequest: TCompletionRequest; out ASite: TPropertySite): Boolean;
var
  mMatch: TMatch;
begin
  ASite := Default(TPropertySite);
  mMatch := TRegEx.Match(ARequest.LineBefore, '^\s*(?:class\s+)?property\s+(\w+)\s*(\[[^\]]*\])?\s*:\s*' +
    '([\w.<>, ]+?)\s+(?:index\s+\S+\s+)?(?:read\s+\w+\s+)?(read|write)\s+(\w*)$', [roIgnoreCase]);
  Result := mMatch.Success and EnclosingType(ARequest.UnitIndex, ARequest.Position.Line, True, ASite.TypeName);
  if not Result then
  begin
    Exit;
  end;
  ASite.Name := mMatch.Groups[1].Value;
  ASite.IndexParameters := mMatch.Groups[2].Value.Trim(['[', ']']).Trim;
  ASite.PropertyType := mMatch.Groups[3].Value;
  ASite.IsWrite := SameText(mMatch.Groups[4].Value, 'write');
  ASite.Prefix := mMatch.Groups[5].Value;
end;

/// <summary>Zahl der Indexparameter: "I, J: Integer; const S: string" sind drei.</summary>
function IndexParameterCount(const AParameters: string): Integer;
var
  mParam: string;
begin
  Result := 0;
  for mParam in AParameters.Split([';']) do
  begin
    if Pos(':', mParam) > 0 then
    begin
      Inc(Result, Length(Copy(mParam, 1, Pos(':', mParam) - 1).Split([','])));
    end;
  end;
end;

/// <summary>Passt ACandidate als Zugriff: Feld vom Typ (ohne Index), Setter bzw. Getter mit den
/// Indexparametern.</summary>
function AccessorFits(const ACandidate: TResolvedSymbol; const ASite: TPropertySite; AIndexCount: Integer): Boolean;
begin
  if ACandidate.SymbolKind = TIndexSymbolKind.Field then
  begin
    Result := (AIndexCount = 0) and (PlainType(ACandidate.TypeName) = PlainType(ASite.PropertyType));
  end
  else if ASite.IsWrite then
  begin
    Result := (ACandidate.TypeName = '') and (ACandidate.MinArgs <= AIndexCount + 1) and
      (ACandidate.MaxArgs >= AIndexCount + 1) and (Length(ACandidate.ParamTypes) > AIndexCount);
    Result := Result and (PlainType(ACandidate.ParamTypes[AIndexCount]) = PlainType(ASite.PropertyType));
  end
  else
  begin
    Result := (ACandidate.TypeName <> '') and (PlainType(ACandidate.TypeName) = PlainType(ASite.PropertyType)) and
      (ACandidate.MinArgs <= AIndexCount) and (ACandidate.MaxArgs >= AIndexCount);
  end;
end;

/// <summary>Eintrag für ein passendes Feld bzw. eine passende Methode.</summary>
function AccessorCandidateItem(const ACandidate: TResolvedSymbol; const APrefix: string;
  AMatching: TCompletionMatching): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := ACandidate.Name;
  Result.Kind := CompletionKindOf(ACandidate.SymbolKind);
  Result.Detail := ACandidate.TypeName;
  if ACandidate.TypeName = '' then
  begin
    Result.Detail := ACandidate.Container;
  end;
  Result.Container := ACandidate.Container;
  Result.Depth := ACandidate.Depth;
  Result.SourceFile := ACandidate.FileName;
  Result.SourcePosition := ACandidate.SelectionRange.StartPos;
  if (AMatching = TCompletionMatching.Fuzzy) and not ACandidate.Name.StartsWith(APrefix, True) then
  begin
    Result.FilterText := APrefix;
  end;
end;

/// <summary>Arten zum Anlegen: ein Feld nur ohne Indexparameter (read FWert[I] gibt es nicht), dazu Getter
/// bzw. Setter.</summary>
function AccessorKinds(const ASite: TPropertySite): TArray<TAccessorKind>;
begin
  Result := nil;
  if ASite.IndexParameters = '' then
  begin
    Result := [TAccessorKind.Field];
  end;
  if ASite.IsWrite then
  begin
    Result := Result + [TAccessorKind.Setter];
  end
  else
  begin
    Result := Result + [TAccessorKind.Getter];
  end;
end;

/// <summary>Quelle der Klasse am Cursor für TAccessorCreation; der Aufrufer gibt sie frei.</summary>
function AccessorSource(ARequest: TCompletionRequest): TCommandSource;
var
  mSlash: TSlashContext;
  mLines: TArray<string>;
begin
  mLines := ARequest.Lines;
  mSlash := Default(TSlashContext);
  mSlash.Text := ARequest.Text;
  mSlash.Line := ARequest.Position.Line;
  if ARequest.Position.Line <= High(mLines) then
  begin
    mSlash.LineText := mLines[ARequest.Position.Line];
  end;
  mSlash.Index := ARequest.Index;
  Result := TCommandSource.Create(mSlash);
end;

/// <summary>Plan für eine Art: Abschnitt der Methoden aus completion.accessorSection.</summary>
function AccessorPlan(ARequest: TCompletionRequest; const ASite: TPropertySite; AKind: TAccessorKind): TAccessorPlan;
begin
  Result := Default(TAccessorPlan);
  Result.Kind := AKind;
  Result.PropertyName := ASite.Name;
  Result.PropertyType := ASite.PropertyType.Trim;
  Result.IndexParameters := ASite.IndexParameters;
  Result.MethodSection := 'private';
  if ARequest.Settings.AccessorSection = TCompletionAccessorSection.Protected then
  begin
    Result.MethodSection := 'protected';
  end;
end;

/// <summary>Eintrag „Feld F&lt;Name&gt; anlegen“, „Get…“ bzw. „Set… anlegen“ zum Plan.</summary>
function AccessorItem(ARequest: TCompletionRequest; const ASite: TPropertySite; APlan: TAccessorPlan;
  const AEdits: TArray<TTextEdit>; AWithField: Boolean): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := cTexts[cAccessorTitles[APlan.Kind]].Fmt([APlan.Name]);
  Result.Kind := cKindMethod;
  if APlan.Kind = TAccessorKind.Field then
  begin
    Result.Kind := cKindField;
  end;
  Result.Detail := TAccessorCreation.Declaration(APlan);
  Result.Fits := True;
  Result.Pinned := True;
  Result.Action := 'create';
  Result.HasTextEdit := True;
  // Der getippte Anfang wird zum Namen: "read Ca|" → "read FCaption".
  Result.TextEdit := TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(ARequest.Position.Line,
    ARequest.Position.Character - Length(ASite.Prefix)), ARequest.Position), APlan.Name);
  Result.AdditionalEdits := AEdits;
  if AWithField then
  begin
    APlan.Kind := TAccessorKind.Field;
    Result.Detail := Result.Detail + ' + ' + TAccessorCreation.Declaration(APlan);
  end;
end;

/// <summary>„Feld F&lt;Name&gt; anlegen“, „Get&lt;Name&gt; anlegen“ bzw. „Set&lt;Name&gt; anlegen“ (#467).</summary>
function AccessorItems(ARequest: TCompletionRequest; const ASite: TPropertySite): TArray<TCompletionItem>;
var
  mSource: TCommandSource;
  mClass: TIndexSymbol;
  mKind: TAccessorKind;
  mPlan: TAccessorPlan;
  mEdits: TArray<TTextEdit>;
  mWithField: Boolean;
begin
  Result := nil;
  mSource := AccessorSource(ARequest);
  try
    if not mSource.ClassAt(mClass) then
    begin
      Exit;
    end;
    for mKind in AccessorKinds(ASite) do
    begin
      mPlan := AccessorPlan(ARequest, ASite, mKind);
      if TAccessorCreation.Edits(mSource, ARequest.Index, mClass, mPlan, mEdits, mWithField) then
      begin
        Result := Result + [AccessorItem(ARequest, ASite, mPlan, mEdits, mWithField)];
      end;
    end;
  finally
    mSource.Free;
  end;
end;

class function TCompletionDeclarations.PropertyItems(ARequest: TCompletionRequest;
  out AItems: TCompletionItems): Boolean;
var
  mSite: TPropertySite;
  mIndexCount: Integer;
  mCandidate: TResolvedSymbol;
begin
  AItems := Default(TCompletionItems);
  Result := PropertySiteAt(ARequest, mSite);
  if not Result then
  begin
    Exit;
  end;
  // Feld und Zugriffsmethoden anlegen (#467): oben vor den passenden Mitgliedern.
  if ARequest.Settings.CreateAccessors then
  begin
    AItems.Items := AccessorItems(ARequest, mSite);
  end;
  mIndexCount := IndexParameterCount(mSite.IndexParameters);
  for mCandidate in ARequest.Resolver.Queries.AccessorCandidates(ARequest.UnitIndex, mSite.TypeName) do
  begin
    if AccessorFits(mCandidate, mSite, mIndexCount) and
      (MatchScore(mCandidate.Name, mSite.Prefix, ARequest.Matching) <> TFuzzyMatch.cNoMatch) then
    begin
      AItems.Items := AItems.Items + [AccessorCandidateItem(mCandidate, mSite.Prefix, ARequest.Matching)];
    end;
  end;
end;

{ resourcestring }

/// <summary>Namen der Symbole von AUnit und der vorhandenen Einträge, die der neue Name meiden muss.</summary>
function TakenResourceNames(const AUnit: TUnitIndex; const AEntries: TArray<TResourceEntry>): TArray<string>;
var
  mSymbol: TIndexSymbol;
  mEntry: TResourceEntry;
begin
  Result := nil;
  for mSymbol in AUnit.Symbols do
  begin
    Result := Result + [mSymbol.Name];
  end;
  for mEntry in AEntries do
  begin
    Result := Result + [mEntry.Name];
  end;
end;

/// <summary>Literal am Cursor, wenn resourcestrings eingeschaltet sind, ohne Auslösezeichen und an einer Stelle,
/// an der ein resourcestring stehen darf.</summary>
function ResourceLiteralAt(ARequest: TCompletionRequest; out ALiteral: TResourceLiteral): Boolean;
begin
  Result := ARequest.Settings.ResourceStrings and (ARequest.Trigger = '') and (ARequest.Tree <> nil);
  Result := Result and TResourceStrings.LiteralAt(ARequest.Text, ARequest.Tree.Tokens, ARequest.Position, ALiteral);
  Result := Result and TResourceStrings.Allowed(ARequest.Tree, ALiteral.StartOffset);
end;

/// <summary>Festgelegte Unit (completion.resourceStringUnit): nur wenn sie nicht die eigene ist, der Index sie
/// kennt und sie lesbar ist; ATargetText ist ihr Text.</summary>
function ResourceUnit(ARequest: TCompletionRequest; out ATarget: TUnitIndex; out ATargetText: string): Boolean;
var
  mUnitName: string;
begin
  ATargetText := '';
  mUnitName := ARequest.Settings.ResourceStringUnit;
  Result := (mUnitName <> '') and not SameText(mUnitName, TUsesClauses.OwnName(ARequest.Tree.Tokens)) and
    (ARequest.Index <> nil);
  Result := Result and ARequest.Index.FindUnit(mUnitName, ATarget) and Assigned(ARequest.ReadText);
  Result := Result and ARequest.ReadText(ATarget.FileName, ATargetText);
end;

/// <summary>Deklaration in der festgelegten Unit: deren Namen meiden, sie ins uses eintragen und dort nach
/// gleichem Text suchen.</summary>
procedure UseResourceUnit(ARequest: TCompletionRequest; const ATargetText: string; var ATarget: TResourceTarget);
var
  mEntries: TArray<TResourceEntry>;
  mUsesEdit: TTextEdit;
begin
  ATarget.HasTarget := True;
  mEntries := TResourceStrings.Entries(ATargetText, TPascalLexer.Tokenize(ATargetText));
  ATarget.Taken := ATarget.Taken + TakenResourceNames(ATarget.Target, mEntries);
  if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ARequest.Tree.Tokens), ATarget.Target.UnitName,
    ARequest.Resolver.Namespaces) and TUsesClauses.AddUnit(ARequest.Tree.Tokens, ATarget.Literal.StartOffset,
    ATarget.Target.UnitName, ARequest.LineBreak, mUsesEdit) then
  begin
    ATarget.UsesEdits := [mUsesEdit];
  end;
  ATarget.HasExisting := TResourceStrings.SameText(mEntries, ATarget.Literal.Text, True, -1, ATarget.Existing);
end;

/// <summary>Ziel der Deklaration samt vergebener Namen und vorhandenem Eintrag mit gleichem Text.</summary>
function ResourceTargetOf(ARequest: TCompletionRequest; const ALiteral: TResourceLiteral): TResourceTarget;
var
  mEntries: TArray<TResourceEntry>;
  mTargetText: string;
begin
  Result := Default(TResourceTarget);
  Result.Literal := ALiteral;
  mEntries := TResourceStrings.Entries(ARequest.Text, ARequest.Tree.Tokens);
  Result.Taken := TakenResourceNames(ARequest.UnitIndex, mEntries);
  if ResourceUnit(ARequest, Result.Target, mTargetText) then
  begin
    UseResourceUnit(ARequest, mTargetText, Result);
  end
  else
  begin
    Result.HasExisting := TResourceStrings.SameText(mEntries, ALiteral.Text, False, ALiteral.Range.StartPos.Line,
      Result.Existing);
  end;
end;

/// <summary>„Vorhandenen verwenden: Name“ für einen Eintrag mit gleichem Text.</summary>
function ExistingResourceItem(const ATarget: TResourceTarget): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := cTexts[TDeclarationText.UseExisting].Fmt([ATarget.Existing.Name]);
  Result.Kind := cKindConstant;
  Result.Detail := Format('%s = %s', [ATarget.Existing.Name, ATarget.Existing.Value]);
  Result.Fits := True;
  Result.Pinned := True;
  Result.Action := 'create';
  Result.HasTextEdit := True;
  Result.TextEdit := TRuleEdit.Create(ATarget.Literal.Range, ATarget.Existing.Name);
  Result.AdditionalEdits := ATarget.UsesEdits;
end;

/// <summary>Quelltext des Literals, nach cMaxLiteralPreview Zeichen gekürzt.</summary>
function LiteralPreview(const ALiteral: TResourceLiteral): string;
begin
  Result := ALiteral.Source;
  if Length(Result) > cMaxLiteralPreview then
  begin
    Result := Copy(Result, 1, cMaxLiteralPreview - 1) + '…';
  end;
end;

/// <summary>Auslagern in die festgelegte Unit: Der Eintrag dort kommt über den Befehl; deren Puffer ist ein
/// eigener Undo-Schritt.</summary>
procedure ExtractToUnit(var AItem: TCompletionItem; const ATarget: TResourceTarget; const AName: string);
begin
  AItem.Detail := Format('%s = %s in %s', [AName, LiteralPreview(ATarget.Literal), ATarget.Target.UnitName]);
  AItem.TextEdit := TRuleEdit.Create(ATarget.Literal.Range, AName);
  AItem.AdditionalEdits := ATarget.UsesEdits;
  AItem.Command := cAddResourceCommand;
  AItem.CommandTitle := AItem.Name;
  AItem.CommandArguments := [ATarget.Target.FileName, AName, ATarget.Literal.Source];
end;

/// <summary>Auslagern in die eigene Unit; mit ASnippets ist der Name an beiden Stellen derselbe Platzhalter
/// (#51). False, wenn sich keine Stelle für die Deklaration findet.</summary>
function ExtractHere(ARequest: TCompletionRequest; var AItem: TCompletionItem; const ATarget: TResourceTarget;
  const AName: string; ASnippets: Boolean): Boolean;
var
  mEdit: TTextEdit;
begin
  Result := TResourceStrings.Insertion(ARequest.Text, ARequest.Tree.Tokens,
    TResourcePlace.Create(False, ATarget.Literal.Range.StartPos.Line),
    Format('%s = %s;', [AName, ATarget.Literal.Source]), ARequest.LineBreak, mEdit);
  if not Result then
  begin
    Exit;
  end;
  AItem.Detail := Format('%s = %s', [AName, LiteralPreview(ATarget.Literal)]);
  AItem.TextEdit := TRuleEdit.Create(ATarget.Literal.Range, AName);
  if ASnippets then
  begin
    AItem.Snippet := True;
    AItem.LinkedEdits := True;
    AItem.TextEdit.NewText := '${1:' + AName + '}';
    mEdit.NewText := StringReplace(TContextSnippets.Escape(mEdit.NewText), AName + ' = ', '${1:' + AName + '} = ',
      []);
  end;
  AItem.AdditionalEdits := [mEdit];
end;

class function TCompletionDeclarations.ResourceStringItems(ARequest: TCompletionRequest; ASnippets: Boolean;
  out AItems: TCompletionItems): Boolean;
var
  mLiteral: TResourceLiteral;
  mTarget: TResourceTarget;
  mName: string;
  mItem: TCompletionItem;
begin
  AItems := Default(TCompletionItems);
  Result := ResourceLiteralAt(ARequest, mLiteral);
  if not Result then
  begin
    Exit;
  end;
  mTarget := ResourceTargetOf(ARequest, mLiteral);
  // Gleicher Text schon vorhanden: zuerst diesen verwenden.
  if mTarget.HasExisting then
  begin
    AItems.Items := [ExistingResourceItem(mTarget)];
  end;
  mName := TResourceStrings.UniqueName(TResourceStrings.NameFor(mLiteral.Text), mTarget.Taken);
  mItem := Default(TCompletionItem);
  mItem.Name := cTexts[TDeclarationText.ExtractResource].Text;
  mItem.Kind := cKindConstant;
  mItem.Fits := True;
  mItem.Pinned := True;
  mItem.Action := 'create';
  mItem.HasTextEdit := True;
  if mTarget.HasTarget then
  begin
    ExtractToUnit(mItem, mTarget, mName);
  end
  else if not ExtractHere(ARequest, mItem, mTarget, mName, ASnippets) then
  begin
    Exit(Length(AItems.Items) > 0);
  end;
  AItems.Items := AItems.Items + [mItem];
end;

{ override }

/// <summary>Parameternamen aus "Name(const A, B: T; var C: U): R" in Reihenfolge (#443).</summary>
function OverrideParamNames(const AHead: string): TArray<string>;
var
  mOpen, mClose: Integer;
  mGroup, mNames, mName: string;
begin
  Result := nil;
  mOpen := Pos('(', AHead);
  mClose := LastDelimiter(')', AHead);
  if (mOpen = 0) or (mClose <= mOpen) then
  begin
    Exit;
  end;
  for mGroup in Copy(AHead, mOpen + 1, mClose - mOpen - 1).Split([';']) do
  begin
    mNames := mGroup;
    if Pos(':', mNames) > 0 then
    begin
      mNames := Copy(mNames, 1, Pos(':', mNames) - 1);
    end;
    mNames := Trim(mNames);
    for mName in ['const ', 'var ', 'out ', 'constref '] do
    begin
      if StartsText(mName, mNames) then
      begin
        mNames := Trim(Copy(mNames, Length(mName) + 1, MaxInt));
      end;
    end;
    for mName in mNames.Split([',']) do
    begin
      if Trim(mName) <> '' then
      begin
        Result := Result + [Trim(mName)];
      end;
    end;
  end;
end;

/// <summary>"    procedure Ch|", "    function |", "    class procedure |" oder "    override Ch|" (#31) im
/// Rumpf einer Klasse.</summary>
function OverrideSiteAt(ARequest: TCompletionRequest; out ASite: TOverrideSite): Boolean;
var
  mMatch: TMatch;
begin
  ASite := Default(TOverrideSite);
  mMatch := TRegEx.Match(ARequest.LineBefore, '^\s*(class\s+)?(procedure|function)\s+(\w*)$', [roIgnoreCase]);
  if mMatch.Success then
  begin
    ASite.TypedClass := mMatch.Groups[1].Length > 0;
    ASite.TypedKind := LowerCase(mMatch.Groups[2].Value);
  end
  else
  begin
    // Nach override beide Arten; Übernehmen macht aus der Zeile die Deklaration.
    mMatch := TRegEx.Match(ARequest.LineBefore, '^(\s*)override\s+(\w*)$', [roIgnoreCase]);
    ASite.AfterOverride := mMatch.Success;
    if ASite.AfterOverride then
    begin
      ASite.IndentLength := mMatch.Groups[1].Length;
    end;
  end;
  Result := mMatch.Success and EnclosingType(ARequest.UnitIndex, ARequest.Position.Line, False, ASite.TypeName);
end;

/// <summary>Zerlegt die Deklaration des Kandidaten; False, wenn sie nicht zur getippten Art passt.</summary>
function OverrideDeclarationOf(const ASite: TOverrideSite; const ADeclaration: string;
  out ADecl: TOverrideDeclaration): Boolean;
begin
  ADecl := Default(TOverrideDeclaration);
  ADecl.Declaration := ADeclaration;
  Result := TInterfaceStubs.Split(ADeclaration, ADecl.IsClass, ADecl.Kind, ADecl.Head, ADecl.Directives);
  Result := Result and (ASite.AfterOverride or ((ADecl.Kind = ASite.TypedKind) and
    (ADecl.IsClass = ASite.TypedClass)));
end;

/// <summary>Einfügetext "Kopf; [overload;] override;".</summary>
function OverrideInsert(const ADecl: TOverrideDeclaration): string;
begin
  Result := ADecl.Head + ';';
  if ADecl.Directives.Contains(' overload ') then
  begin
    Result := Result + ' overload;';
  end;
  Result := Result + ' override;';
end;

/// <summary>Anweisung im Rumpf: inherited bzw. Result := inherited …; abstrakt ohne inherited.</summary>
function InheritedCall(const ADecl: TOverrideDeclaration; const AMethodName, ALineBreak: string): string;
var
  mArgs: string;
begin
  mArgs := string.Join(', ', OverrideParamNames(ADecl.Head));
  if ADecl.Directives.Contains(' abstract ') then
  begin
    Result := ALineBreak;
  end
  else if ADecl.Kind = 'procedure' then
  begin
    Result := '  inherited;' + ALineBreak;
  end
  else if mArgs <> '' then
  begin
    Result := '  Result := inherited ' + AMethodName + '(' + mArgs + ');' + ALineBreak;
  end
  else
  begin
    Result := '  Result := inherited ' + AMethodName + ';' + ALineBreak;
  end;
end;

/// <summary>Rumpf mit Kopf samt Typ; Standardwerte (ADefaultValue) stehen nur in der Deklaration.</summary>
function OverrideBody(const ADecl: TOverrideDeclaration; const ATypeName, AMethodName, ALineBreak: string;
  const ADefaultValue: TRegEx): string;
begin
  Result := ADecl.Kind + ' ' + ATypeName + '.' + ADefaultValue.Replace(ADecl.Head, '') + ';';
  if ADecl.IsClass then
  begin
    Result := 'class ' + Result;
  end;
  Result := Result + ALineBreak + 'begin' + ALineBreak + InheritedCall(ADecl, AMethodName, ALineBreak) + 'end;';
end;

/// <summary>"override Name" wird zu "procedure Name(...); override;".</summary>
procedure ReplaceOverrideLine(ARequest: TCompletionRequest; var AItem: TCompletionItem; const ASite: TOverrideSite;
  const ADecl: TOverrideDeclaration);
var
  mLead: string;
begin
  mLead := ADecl.Kind + ' ';
  if ADecl.IsClass then
  begin
    mLead := 'class ' + mLead;
  end;
  AItem.HasTextEdit := True;
  AItem.TextEdit := TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(ARequest.Position.Line,
    ASite.IndentLength), ARequest.Position), mLead + AItem.InsertText);
  AItem.InsertText := '';
  AItem.FilterText := 'override ' + AItem.Name;
end;

/// <summary>Eintrag für eine überschreibbare Methode samt Rumpf.</summary>
function OverrideItem(ARequest: TCompletionRequest; const ASite: TOverrideSite; const ACandidate: TResolvedSymbol;
  const ADecl: TOverrideDeclaration; const ADefaultValue: TRegEx): TCompletionItem;
var
  mEdit: TRuleEdit;
begin
  Result := Default(TCompletionItem);
  Result.Name := ACandidate.Name;
  Result.Kind := cKindMethod;
  Result.Detail := ADecl.Declaration;
  Result.InsertText := OverrideInsert(ADecl);
  Result.Action := 'override';
  Result.Container := ACandidate.Container;
  Result.Depth := ACandidate.Depth;
  Result.SourceFile := ACandidate.FileName;
  Result.SourcePosition := ACandidate.SelectionRange.StartPos;
  if ASite.AfterOverride then
  begin
    ReplaceOverrideLine(ARequest, Result, ASite, ADecl);
  end;
  if TClassCompletion.BodyEdit(ARequest.Tree, ARequest.Text, ASite.TypeName,
    OverrideBody(ADecl, ASite.TypeName, ACandidate.Name, ARequest.LineBreak, ADefaultValue), mEdit) then
  begin
    Result.AdditionalEdits := [mEdit];
  end;
end;

class function TCompletionDeclarations.OverrideItems(ARequest: TCompletionRequest;
  out AItems: TCompletionItems): Boolean;
var
  mSite: TOverrideSite;
  mCandidate: TResolvedSymbol;
  mDecl: TOverrideDeclaration;
  mSourceLines: TArray<string>;
  mFiles: TDictionary<string, TArray<string>>;
  mDefaultValue: TRegEx;
begin
  AItems := Default(TCompletionItems);
  Result := OverrideSiteAt(ARequest, mSite);
  if not Result then
  begin
    Exit;
  end;
  // Je Vorfahren-Unit einmal lesen und zerlegen statt je Kandidat; das Muster für
  // Standardwerte einmal übersetzen. Lokal, weil die Vervollständigung nebenläufig läuft.
  mDefaultValue := TRegEx.Create('\s*=\s*[^;)]+');
  mFiles := TDictionary<string, TArray<string>>.Create;
  try
    for mCandidate in ARequest.Resolver.Queries.OverridableMembers(ARequest.UnitIndex, mSite.TypeName) do
    begin
      if CachedLines(mFiles, mCandidate.FileName, ARequest.FileName, ARequest.Text, ARequest.ReadText,
        mSourceLines) and OverrideDeclarationOf(mSite, TInterfaceStubs.DeclarationOf(mSourceLines,
        mCandidate.Range), mDecl) then
      begin
        AItems.Items := AItems.Items + [OverrideItem(ARequest, mSite, mCandidate, mDecl, mDefaultValue)];
      end;
    end;
  finally
    mFiles.Free;
  end;
end;

{ TInterfaceItemsBuilder }

constructor TInterfaceItemsBuilder.Create(ARequest: TCompletionRequest);
begin
  inherited Create;
  FRequest := ARequest;
end;

function TInterfaceItemsBuilder.Prepare(out ATypeSymbol: TIndexSymbol): Boolean;
var
  mMatch: TMatch;
  mLines: TArray<string>;
  mLine: TTextPosition;
begin
  ATypeSymbol := Default(TIndexSymbol);
  mLine := FRequest.Position;
  // "    |" (Strg+Leer auf leerer Zeile) bzw. "    Exp|"
  mMatch := TRegEx.Match(FRequest.LineBefore, '^(\s*)(\w*)$');
  mLines := FRequest.Lines;
  Result := mMatch.Success and (mLine.Line >= 0) and (mLine.Line <= High(mLines));
  if not Result then
  begin
    Exit;
  end;
  FBatch := mMatch.Groups[2].Length = 0;
  FWordRange := TTextRange.Create(mLine.Line, mMatch.Groups[1].Length, mLine.Line, mLine.Character);
  // Leere Zeile nur, wenn auch dahinter nichts steht; vor einer vorhandenen Deklaration bleibt Strg+Leer
  // normal. Nur Klassen mit Interfaces in der Vorfahrenliste; "end" in der Zeile des Cursors zählt nicht mehr
  // dazu.
  Result := not (FBatch and (Trim(Copy(mLines[mLine.Line], mLine.Character + 1, MaxInt)) <> '')) and
    EnclosingTypeAt(FRequest.UnitIndex, mLine.Line, [TIndexSymbolKind.ClassType], 2, False, ATypeSymbol);
  FEndLine := ATypeSymbol.Range.EndPos.Line;
  Result := Result and (FEndLine <= High(mLines)) and TRegEx.IsMatch(mLines[FEndLine], '^\s*end\b',
    [roIgnoreCase]);
  if Result then
  begin
    FIndent := Copy(mLines[FEndLine], 1, Length(mLines[FEndLine]) - Length(TrimLeft(mLines[FEndLine])));
    FTypeName := QualifiedTypeName(ATypeSymbol);
  end;
end;

function TInterfaceItemsBuilder.StubOf(const AMissing: TResolvedSymbol; const ASourceLines: TArray<string>;
  out AStub: TInterfaceStub): Boolean;
begin
  // Generische Interfaces: Typargumente in die Deklaration einsetzen (IComparer<TKunde>: T → TKunde).
  Result := TInterfaceStubs.Make(TInterfaceStubs.GenericName(AMissing.Container, AMissing.Bindings), FTypeName,
    TInterfaceStubs.SubstituteWords(TInterfaceStubs.DeclarationOf(ASourceLines, AMissing.Range),
    AMissing.Bindings), FRequest.LineBreak, AStub);
end;

function TInterfaceItemsBuilder.StubEdits(const AStub: TInterfaceStub): TArray<TRuleEdit>;
var
  mEdit: TRuleEdit;
begin
  Result := TInterfaceStubs.ClassEdits(AStub, FEndLine, FIndent, FSection, FNeedHeader, FRequest.LineBreak);
  if TClassCompletion.BodyEdit(FRequest.Tree, FRequest.Text, FTypeName, AStub.Body, mEdit) then
  begin
    Result := Result + [mEdit];
  end;
end;

procedure TInterfaceItemsBuilder.StartInterface(const AInterface: string);
begin
  if (Length(FInterfaces) > 0) and SameText(FInterfaces[High(FInterfaces)], AInterface) then
  begin
    Exit;
  end;
  if not FBatch then
  begin
    AddHint;
  end;
  FInterfaces := FInterfaces + [AInterface];
  FGroup := nil;
  FCount := 0;
end;

procedure TInterfaceItemsBuilder.AddHint;
var
  mHint: TCompletionItem;
  mInterface: string;
begin
  if (FCount = 0) or (Length(FInterfaces) = 0) then
  begin
    Exit;
  end;
  mInterface := FInterfaces[High(FInterfaces)];
  mHint := Default(TCompletionItem);
  mHint.Name := cTexts[TDeclarationText.MissingMethods].Fmt([FCount, mInterface]);
  if FCount = 1 then
  begin
    mHint.Name := cTexts[TDeclarationText.MissingMethod].Fmt([mInterface]);
  end;
  mHint.Detail := cTexts[TDeclarationText.ImplementInterface].Text;
  mHint.Kind := cKindSnippet;
  mHint.Hint := True;
  mHint.Action := 'implement';
  mHint.Container := mInterface;
  // Das angefangene Wort verschwindet, die Methoden kommen über die weiteren Änderungen.
  mHint.HasTextEdit := True;
  mHint.TextEdit := TRuleEdit.Create(FWordRange, '');
  mHint.AdditionalEdits := TInterfaceStubs.Merge(FGroup);
  FItems := FItems + [mHint];
end;

procedure TInterfaceItemsBuilder.AddBatchItem(const AStub: TInterfaceStub; const AMissing: TResolvedSymbol;
  const AEdits: TArray<TRuleEdit>);
var
  mItem: TCompletionItem;
begin
  mItem := Default(TCompletionItem);
  mItem.Name := AStub.Name;
  mItem.Kind := cKindMethod;
  mItem.Detail := AStub.Declaration;
  mItem.Container := AStub.InterfaceName;
  mItem.Action := 'implement';
  mItem.Batch := True;
  mItem.Ordinal := Length(FItems) + 1;
  mItem.SetChecked := True;
  mItem.SetRange := FWordRange;
  mItem.AdditionalEdits := AEdits;
  mItem.SourceFile := AMissing.FileName;
  mItem.SourcePosition := AMissing.SelectionRange.StartPos;
  FItems := FItems + [mItem];
end;

procedure TInterfaceItemsBuilder.AddMissing(const AMissing: TArray<TResolvedSymbol>);
var
  mFiles: TDictionary<string, TArray<string>>;
  mSourceLines: TArray<string>;
  mMissing: TResolvedSymbol;
  mStub: TInterfaceStub;
  mEdits: TArray<TRuleEdit>;
begin
  // Je Datei einmal lesen, auch wenn die Interfaces abwechselnd aus mehreren Units stammen.
  mFiles := TDictionary<string, TArray<string>>.Create;
  try
    for mMissing in AMissing do
    begin
      if not CachedLines(mFiles, mMissing.FileName, FRequest.FileName, FRequest.Text, FRequest.ReadText,
        mSourceLines) then
      begin
        mSourceLines := TextLines('');
      end;
      if not StubOf(mMissing, mSourceLines, mStub) then
      begin
        Continue;
      end;
      StartInterface(mStub.InterfaceName);
      mEdits := StubEdits(mStub);
      FGroup := FGroup + mEdits;
      Inc(FCount);
      if FBatch then
      begin
        AddBatchItem(mStub, mMissing, mEdits);
      end;
    end;
  finally
    mFiles.Free;
  end;
end;

procedure TInterfaceItemsBuilder.MarkBatch;
var
  mIndex: Integer;
begin
  // Eine Überschrift über der ganzen Liste: „Fehlende Methoden von IExporter, IInterface“.
  for mIndex := 0 to High(FItems) do
  begin
    if FItems[mIndex].Batch then
    begin
      FItems[mIndex].SetOf := string.Join(', ', FInterfaces);
      FItems[mIndex].Expected := FItems[mIndex].SetOf;
      FItems[mIndex].Fits := True;
    end;
  end;
end;

function TInterfaceItemsBuilder.Build(out AItems: TArray<TCompletionItem>; out ABatch: Boolean): Boolean;
var
  mTypeSymbol: TIndexSymbol;
  mMissing: TArray<TResolvedSymbol>;
begin
  AItems := nil;
  Result := Prepare(mTypeSymbol);
  ABatch := FBatch;
  if not Result then
  begin
    Exit;
  end;
  // Vorfahrenliste aus dem Quelltext: Der Index kennt die Typargumente nur beim ersten Vorfahren.
  mMissing := FRequest.Resolver.Queries.MissingInterfaceMembers(FRequest.UnitIndex, FTypeName,
    TInterfaceStubs.HeaderAncestors(FRequest.Lines, mTypeSymbol.Range.StartPos.Line));
  Result := Length(mMissing) > 0;
  if not Result then
  begin
    Exit;
  end;
  FSection := cInterfaceSections[FRequest.Settings.InterfaceSection];
  FNeedHeader := TInterfaceStubs.LastSection(FRequest.Tree.Tokens, mTypeSymbol.Range.StartPos.Line, FEndLine) <>
    FSection;
  AddMissing(mMissing);
  if not FBatch then
  begin
    AddHint;
  end;
  MarkBatch;
  AItems := FItems;
  Result := Length(AItems) > 0;
end;

class function TCompletionDeclarations.InterfaceItems(ARequest: TCompletionRequest;
  out AItems: TArray<TCompletionItem>; out ABatch: Boolean): Boolean;
var
  mBuilder: TInterfaceItemsBuilder;
begin
  mBuilder := TInterfaceItemsBuilder.Create(ARequest);
  try
    Result := mBuilder.Build(AItems, ABatch);
  finally
    mBuilder.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Completion.Declarations', cTexts);

end.
