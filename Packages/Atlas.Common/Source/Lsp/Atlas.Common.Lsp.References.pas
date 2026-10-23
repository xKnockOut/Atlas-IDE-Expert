unit Atlas.Common.Lsp.References;

// Referenzsuche (textDocument/references, #29): alle Stellen im Projekt, die
// zur selben Deklaration auflösen wie der Bezeichner unter dem Cursor.
//
// Durchsucht werden die Projektdateien und die geöffneten Dokumente; Dateien,
// in denen der Name nicht einmal als Text vorkommt, werden nicht geparst.
// Steht die Deklaration in einer Unit mit Formular, zählen auch Verweise aus
// der .dfm daneben: Ereignis-Handler (OnClick = Button1Click) und
// Komponentennamen (object Button1: TButton).
// Jede Stelle trägt eine Einstufung (#1119, TReferenceClassifier): sicher oder
// erschlossen mit Grund. Die Überladung von Find ohne Einstellungen liefert
// nur sichere Stellen wie bisher; Umbauten wie Methode verschieben nutzen sie.
// Die Antwort nennt die Einstufung je Stelle im Feld atlasConfidence.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Lsp.InactiveRegions,
  Atlas.Common.Lsp.ReferenceConfidence;

type
  TReferenceLocation = record
    FileName: string;
    Range: TTextRange;
    /// <summary>Sicher oder erschlossen mit Grund (#1119).</summary>
    Confidence: TReferenceConfidence;
  end;

  /// <summary>Einstellungen references.* für die Datei AUri.</summary>
  TReferenceSettingsProvider = reference to function(const AUri: string): TReferenceSettings;

  /// <summary>Text einer Datei, geöffnete Dokumente zuerst; False, wenn sie nicht lesbar ist.</summary>
  TReferenceReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Dateien des Projekts, die nach Verweisen durchsucht werden.</summary>
  TReferenceFilesProvider = reference to function: TArray<string>;

  TLspReferences = class
  public const
    Method = 'textDocument/references';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: TReferenceReadText;
    FFiles: TReferenceFilesProvider;
    FNamespaces: TArray<string>;
    FSettingsFor: TReferenceSettingsProvider;
    function HandleReferences(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Stellen in ATree, die zu AWanted auflösen; AName ohne &amp;.</summary>
    class function InTree(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName, AName: string; const AWanted: TDefinitionTarget;
      const ACancellation: IJsonRpcCancellationToken = nil): TArray<TTextRange>; static;
    /// <summary>Wie InTree, je Stelle eingestuft (#1119): Bezeichner über AClassifier.Classify, String-Literale
    /// über TextMatch. AInactive: inaktive Bereiche der Datei. AResolver ist der des Classifiers.</summary>
    class function HitsInTree(AResolver: TNameResolver; AClassifier: TReferenceClassifier; ATree: TSyntaxTree;
      const AFileName, AName: string; const AInactive: TArray<TLspInactiveRegion>;
      const ACancellation: IJsonRpcCancellationToken): TArray<TReferenceHit>; static;
    /// <summary>Alle sicheren Verweise auf das Symbol an APosition; mit ADeclaration auch die Deklaration selbst.
    /// </summary>
    class function Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean;
      const AFiles: TArray<string>; const AReadText: TReferenceReadText;
      const ACancellation: IJsonRpcCancellationToken = nil): TArray<TReferenceLocation>; overload; static;
    /// <summary>Wie oben, mit erschlossenen Stellen nach ASettings (#1119).</summary>
    class function Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean;
      const AFiles: TArray<string>; const AReadText: TReferenceReadText; const ASettings: TReferenceSettings;
      const ACancellation: IJsonRpcCancellationToken): TArray<TReferenceLocation>; overload; static;
    /// <summary>Inaktive Bereiche von AText unter den Symbolen, mit denen der Editor die Datei liest; leer ohne
    /// references.inferred.</summary>
    class function InactiveFor(const AFileName, AText: string;
      const ASettings: TReferenceSettings): TArray<TLspInactiveRegion>; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Einstellungen references.* je Datei; nicht gesetzt: Vorgaben.</summary>
    property SettingsFor: TReferenceSettingsProvider read FSettingsFor write FSettingsFor;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Dfm.FormFiles,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Lsp.Internals.Cancellation;

function CleanName(const AText: string): string;
begin
  // &Begin → Begin
  if (AText <> '') and (AText[1] = '&') then
    Result := Copy(AText, 2, MaxInt)
  else
    Result := AText;
end;

function TokenAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  Index: Integer;
  Token: TPascalToken;
begin
  for Index := 0 to High(ATokens) do
  begin
    Token := ATokens[Index];
    if (Token.StartPos.Line > APosition.Line) or
      ((Token.StartPos.Line = APosition.Line) and (Token.StartPos.Character > APosition.Character)) then
      Break;
    // Cursor auf oder direkt hinter dem Bezeichner.
    if (Token.Kind = TPascalTokenKind.Identifier) and (Token.EndPos.Line = APosition.Line) and
      (APosition.Character <= Token.EndPos.Character) then
      Exit(Index);
  end;
  Result := -1;
end;

/// <summary>Andere Schreibweise eines Attributnamens: Foo zu FooAttribute und umgekehrt.</summary>
function AlternativeName(const AName: string): string;
begin
  if EndsText('Attribute', AName) and (Length(AName) > Length('Attribute')) then
    Result := Copy(AName, 1, Length(AName) - Length('Attribute'))
  else
    Result := AName + 'Attribute';
end;

/// <summary>Ereignis-Handler und Komponentennamen AName in einer Formulardatei, über das
/// Formularmodell (#267).</summary>
function InForm(const AFormText, AName: string): TArray<TTextRange>;
var
  Model: TFormModel;
begin
  Model := TFormModel.Create(AFormText);
  try
    Result := Model.Occurrences(AName);
  finally
    Model.Free;
  end;
end;

{ TLspReferences }

function TLspReferences.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspReferences.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspReferences.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FFiles := AFiles;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspReferences.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, HandleReferences);
end;

class function TLspReferences.InTree(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName, AName: string; const AWanted: TDefinitionTarget;
  const ACancellation: IJsonRpcCancellationToken): TArray<TTextRange>;
var
  Classifier: TReferenceClassifier;
  Hits: TArray<TReferenceHit>;
  Index: Integer;
begin
  Classifier := TReferenceClassifier.Create(AResolver, AIndex, AWanted, Default(TIndexSymbol), False, AName,
    TReferenceSettings.SureOnly);
  try
    Hits := HitsInTree(AResolver, Classifier, ATree, AFileName, AName, nil, ACancellation);
  finally
    Classifier.Free;
  end;
  SetLength(Result, Length(Hits));
  for Index := 0 to High(Hits) do
    Result[Index] := Hits[Index].Range;
end;

class function TLspReferences.HitsInTree(AResolver: TNameResolver; AClassifier: TReferenceClassifier;
  ATree: TSyntaxTree; const AFileName, AName: string; const AInactive: TArray<TLspInactiveRegion>;
  const ACancellation: IJsonRpcCancellationToken): TArray<TReferenceHit>;
var
  Index: Integer;
  Alternative: string;
  Hit: TReferenceHit;
  Hits: TList<TReferenceHit>;
begin
  Result := nil;
  Alternative := AlternativeName(AName);
  Hits := TList<TReferenceHit>.Create;
  // Den Baum einmal auswerten statt je Treffer (Code-Review P-01); verschachtelt zulässig, wenn der
  // Aufrufer ihn schon gepinnt hat.
  AResolver.PinTree(ATree, AFileName);
  try
    // Über den Index statt for-in: keine Kopie des Token-Records je Token.
    for Index := 0 to High(ATree.Tokens) do
    begin
      if ATree.Tokens[Index].Kind = TPascalTokenKind.StringLiteral then
      begin
        // Nur der Name zwischen den Hochkommas, damit die Markierung genau ihn trifft.
        if AClassifier.TextMatch(ATree.Tokens[Index], Hit.Confidence) then
        begin
          Hit.Range := TTextRange.Create(
            TTextPosition.Create(ATree.Tokens[Index].StartPos.Line, ATree.Tokens[Index].StartPos.Character + 1),
            TTextPosition.Create(ATree.Tokens[Index].EndPos.Line, ATree.Tokens[Index].EndPos.Character - 1));
          Hits.Add(Hit);
        end;
        Continue;
      end;
      // Attribute (#119): [TestFixture] verwendet TestFixtureAttribute.
      if (ATree.Tokens[Index].Kind <> TPascalTokenKind.Identifier) or
        not (SameText(CleanName(ATree.Tokens[Index].Text), AName) or
        SameText(CleanName(ATree.Tokens[Index].Text), Alternative)) then
        Continue;
      if ACancellation <> nil then
        ACancellation.ThrowIfCancellationRequested;
      if AClassifier.Classify(ATree, AFileName, Index, AInactive, Hit.Confidence) then
      begin
        Hit.Range := TTextRange.Create(ATree.Tokens[Index].StartPos, ATree.Tokens[Index].EndPos);
        Hits.Add(Hit);
      end;
    end;
    Result := Hits.ToArray;
  finally
    AResolver.UnpinTree;
    Hits.Free;
  end;
end;

class function TLspReferences.InactiveFor(const AFileName, AText: string;
  const ASettings: TReferenceSettings): TArray<TLspInactiveRegion>;
begin
  if ASettings.Inferred then
    Result := TReferenceClassifier.InactiveOf(AText, TSyntaxTreeCache.DefinesOf(TDocumentUris.FromPath(AFileName)))
  else
    Result := nil;
end;


class function TLspReferences.Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean;
  const AFiles: TArray<string>; const AReadText: TReferenceReadText;
  const ACancellation: IJsonRpcCancellationToken): TArray<TReferenceLocation>;
begin
  Result := Find(AResolver, AIndex, ATree, AFileName, APosition, ADeclaration, AFiles, AReadText,
    TReferenceSettings.SureOnly, ACancellation);
end;

class function TLspReferences.Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean;
  const AFiles: TArray<string>; const AReadText: TReferenceReadText; const ASettings: TReferenceSettings;
  const ACancellation: IJsonRpcCancellationToken): TArray<TReferenceLocation>;

var
  Locations: TList<TReferenceLocation>;

  procedure Add(const AFile: string; const ARanges: TArray<TTextRange>);
  var
    Range: TTextRange;
    Location: TReferenceLocation;
  begin
    for Range in ARanges do
    begin
      Location.FileName := AFile;
      Location.Range := Range;
      Location.Confidence := TReferenceConfidence.Sure;
      Locations.Add(Location);
    end;
  end;

  procedure AddHits(const AFile: string; const AHits: TArray<TReferenceHit>);
  var
    Hit: TReferenceHit;
    Location: TReferenceLocation;
  begin
    for Hit in AHits do
    begin
      Location.FileName := AFile;
      Location.Range := Hit.Range;
      Location.Confidence := Hit.Confidence;
      Locations.Add(Location);
    end;
  end;

var
  Index: Integer;
  Name, FileName, Text, DfmName: string;
  Wanted: TArray<TDefinitionTarget>;
  Searched: TDictionary<string, Boolean>;
  Tree: TSyntaxTree;
  Symbol: TIndexSymbol;
  HasSymbol: Boolean;
  Classifier: TReferenceClassifier;
  Inactive: TArray<TLspInactiveRegion>;
begin
  Result := nil;
  Index := TokenAt(ATree.Tokens, APosition);
  if Index < 0 then
    Exit;
  // Listen statt Result := Result + [...] (Code-Review P-08); bei vielen Treffern quadratisch.
  Locations := TList<TReferenceLocation>.Create;
  Searched := TDictionary<string, Boolean>.Create;
  Classifier := nil;
  // Den eigenen Baum einmal auswerten (Code-Review P-01): Targets und HitsInTree nutzen ihn; die Fremdbäume
  // pinnt HitsInTree darüber und löst sie wieder.
  AResolver.PinTree(ATree, AFileName);
  try
    Wanted := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, APosition, True);
    if Length(Wanted) = 0 then
      Exit;
    Name := CleanName(ATree.Tokens[Index].Text);
    // Interface und virtual brauchen die Deklaration; ohne erschlossene Treffer genügt das Ziel.
    HasSymbol := ASettings.Inferred and
      TReferenceClassifier.SymbolOf(AResolver, AIndex, ATree, AFileName, Wanted[0], Symbol);
    if not HasSymbol then
      Symbol := Default(TIndexSymbol);
    Classifier := TReferenceClassifier.Create(AResolver, AIndex, Wanted[0], Symbol, HasSymbol, Name, ASettings);
    // Auch der Baum des Editors (#845) führt die Tokens aller Zweige; welche inaktiv sind, sagen die Bereiche.
    Inactive := nil;
    if ASettings.Inferred and Assigned(AReadText) and AReadText(AFileName, Text) then
      Inactive := InactiveFor(AFileName, Text, ASettings);
    AddHits(AFileName, HitsInTree(AResolver, Classifier, ATree, AFileName, Name, Inactive, ACancellation));
    Searched.AddOrSetValue(AnsiUpperCase(AFileName), True);
    for FileName in AFiles do
    begin
      if Searched.ContainsKey(AnsiUpperCase(FileName)) then
        Continue;
      Searched.Add(AnsiUpperCase(FileName), True);
      // Die kürzere Schreibweise ist in der längeren enthalten.
      if not (Assigned(AReadText) and AReadText(FileName, Text)) or not (ContainsText(Text, Name) or
        ContainsText(Text, AlternativeName(Name))) then
        Continue;
      // Parse liest alle Zweige; die inaktiven erkennt Classify an den Bereichen.
      Tree := TSyntaxTreeCache.Parse(Text);
      try
        AddHits(FileName, HitsInTree(AResolver, Classifier, Tree, FileName, Name,
          InactiveFor(FileName, Text, ASettings), ACancellation));
      finally
        Tree.Free;
      end;
    end;
    // Formulare zur Unit der Deklaration, bei FMX samt Plattformansichten (#87).
    if Assigned(AReadText) then
    begin
      if not AReadText(Wanted[0].FileName, Text) then
        Text := '';
      for DfmName in TFormFiles.FormFiles(Wanted[0].FileName, Text) do
        if AReadText(DfmName, Text) then
          Add(DfmName, InForm(Text, Name));
    end;
    if not ADeclaration then
      for Index := Locations.Count - 1 downto 0 do
        if SameText(Locations[Index].FileName, Wanted[0].FileName) and
          (Locations[Index].Range.StartPos = Wanted[0].SelectionRange.StartPos) then
          Locations.Delete(Index);
    Result := Locations.ToArray;
  finally
    AResolver.UnpinTree;
    Classifier.Free;
    Searched.Free;
    Locations.Free;
  end;
end;

function TLspReferences.HandleReferences(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  IncludeDeclaration: Boolean;
  Document: ITextDocument;
  Tree, OwnTree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Text: string;
  Files: TArray<string>;
  Found: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
  Item: TJSONObject;
  Settings: TReferenceSettings;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen in ' + Method);
  if not TJSONObject(AParams).TryGetValue<Boolean>('context.includeDeclaration', IncludeDeclaration) then
    IncludeDeclaration := True;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  OwnTree := nil;
  if FStore.TryGet(Uri, Document) then
  begin
    Shared := TSyntaxTreeCache.Get(Document, Cancellation);
    Tree := Shared.Tree;
  end
  // Nicht geöffnete Datei (Verwendungen eines Typs aus dem Atlas-Tooltip, #588): selbst lesen.
  else if Assigned(FReadText) and FReadText(TDocumentUris.ToPath(Uri), Text) then
  begin
    OwnTree := TSyntaxTreeCache.Parse(Text, Cancellation);
    Tree := OwnTree;
  end
  else
    Exit(TJSONNull.Create);
  try
    Files := nil;
    if Assigned(FFiles) then
      Files := FFiles();
    ACancellation.ThrowIfCancellationRequested;
    if Assigned(FSettingsFor) then
      Settings := FSettingsFor(Uri)
    else
      Settings := TReferenceSettings.Default;
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := Namespaces;
      Found := Find(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue),
        IncludeDeclaration, Files, FReadText, Settings, ACancellation);
    finally
      Resolver.Free;
    end;
  finally
    OwnTree.Free;
  end;
  Result := TJSONArray.Create;
  for Location in Found do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('uri', TDocumentUris.FromPath(Location.FileName));
    Item.AddPair('range', TLspPositions.RangeToJson(Location.Range));
    // Erweiterung (#1119): sicher oder erschlossen mit Grund; Editoren ohne Kenntnis übergehen das Feld.
    Item.AddPair('atlasConfidence', Location.Confidence.ToJson);
    TJSONArray(Result).AddElement(Item);
  end;
end;

end.
