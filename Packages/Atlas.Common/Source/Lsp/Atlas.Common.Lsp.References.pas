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

  /// <summary>Was die Referenzsuche sucht: das Symbol an Position in FileName, in Files über ReadText.</summary>
  TReferenceSearch = record
    FileName: string;
    Position: TTextPosition;
    /// <summary>Auch die Deklaration selbst.</summary>
    Declaration: Boolean;
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    class function Create(const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean;
      const AFiles: TArray<string>; const AReadText: TReferenceReadText): TReferenceSearch; static;
  end;

  TLspReferences = class
  public const
    cMethod = 'textDocument/references';
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
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Alle sicheren Verweise auf das Symbol an ASearch.Position; mit ASearch.Declaration auch die
    /// Deklaration selbst.</summary>
    class function Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ASearch: TReferenceSearch; const ACancellation: IJsonRpcCancellationToken): TArray<TReferenceLocation>;
      overload; static;
    /// <summary>Wie oben ohne Abbruch (ACancellation = nil).</summary>
    class function Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ASearch: TReferenceSearch): TArray<TReferenceLocation>; overload; static;
    /// <summary>Wie oben, mit erschlossenen Stellen nach ASettings (#1119).</summary>
    class function Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ASearch: TReferenceSearch; const ASettings: TReferenceSettings;
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
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TReferencesText = (FieldsTextDocumentUriAndPosition);

const
  cTexts: array[TReferencesText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen in ';
     En: 'Fields "textDocument.uri" and "position" missing in '));

{$SCOPEDENUMS OFF}

function CleanName(const AText: string): string;
begin
  // &Begin → Begin
  if (AText <> '') and (AText[1] = '&') then
  begin
    Result := Copy(AText, 2, MaxInt);
  end
  else
  begin
    Result := AText;
  end;
end;

function TokenAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
  mToken: TPascalToken;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    mToken := ATokens[mIndex];
    if (mToken.StartPos.Line > APosition.Line) or
      ((mToken.StartPos.Line = APosition.Line) and (mToken.StartPos.Character > APosition.Character)) then
    begin
      Break;
    end;
    // Cursor auf oder direkt hinter dem Bezeichner.
    if (mToken.Kind = TPascalTokenKind.Identifier) and (mToken.EndPos.Line = APosition.Line) and
      (APosition.Character <= mToken.EndPos.Character) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Andere Schreibweise eines Attributnamens: Foo zu FooAttribute und umgekehrt.</summary>
function AlternativeName(const AName: string): string;
begin
  if EndsText('Attribute', AName) and (Length(AName) > Length('Attribute')) then
  begin
    Result := Copy(AName, 1, Length(AName) - Length('Attribute'));
  end
  else
  begin
    Result := AName + 'Attribute';
  end;
end;

/// <summary>Ereignis-Handler und Komponentennamen AName in einer Formulardatei, über das
/// Formularmodell (#267).</summary>
function InForm(const AFormText, AName: string): TArray<TTextRange>;
var
  mModel: TFormModel;
begin
  mModel := TFormModel.Create(AFormText);
  try
    Result := mModel.Occurrences(AName);
  finally
    mModel.Free;
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
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider);
begin
  Create(AStore, AIndex, AReadText, AFiles, nil);
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
  ADispatcher.RegisterConcurrentRequest(cMethod, HandleReferences);
end;

/// <summary>Stellen in ATree mit dem Namen AName, je eingestuft (#1119): Bezeichner über AClassifier.Classify,
/// String-Literale über TextMatch. AInactive: inaktive Bereiche der Datei.</summary>
function HitsInTree(AClassifier: TReferenceClassifier; ATree: TSyntaxTree; const AFileName, AName: string;
  const AInactive: TArray<TLspInactiveRegion>; const ACancellation: IJsonRpcCancellationToken):
  TArray<TReferenceHit>;
var
  mIndex: Integer;
  mAlternative: string;
  mHit: TReferenceHit;
  mHits: TList<TReferenceHit>;
begin
  Result := nil;
  mAlternative := AlternativeName(AName);
  mHits := TList<TReferenceHit>.Create;
  // Den Baum einmal auswerten statt je Treffer (Code-Review P-01); verschachtelt zulässig, wenn der
  // Aufrufer ihn schon gepinnt hat.
  AClassifier.Resolver.PinTree(ATree, AFileName);
  try
    // Über den Index statt for-in: keine Kopie des Token-Records je Token.
    for mIndex := 0 to High(ATree.Tokens) do
    begin
      if ATree.Tokens[mIndex].Kind = TPascalTokenKind.StringLiteral then
      begin
        // Nur der Name zwischen den Hochkommas, damit die Markierung genau ihn trifft.
        if AClassifier.TextMatch(ATree.Tokens[mIndex], mHit.Confidence) then
        begin
          mHit.Range := TTextRange.Create(
            TTextPosition.Create(ATree.Tokens[mIndex].StartPos.Line, ATree.Tokens[mIndex].StartPos.Character + 1),
            TTextPosition.Create(ATree.Tokens[mIndex].EndPos.Line, ATree.Tokens[mIndex].EndPos.Character - 1));
          mHits.Add(mHit);
        end;
        Continue;
      end;
      // Attribute (#119): [TestFixture] verwendet TestFixtureAttribute.
      if (ATree.Tokens[mIndex].Kind <> TPascalTokenKind.Identifier) or
        not (SameText(CleanName(ATree.Tokens[mIndex].Text), AName) or
        SameText(CleanName(ATree.Tokens[mIndex].Text), mAlternative)) then
      begin
        Continue;
      end;
      if ACancellation <> nil then
      begin
        ACancellation.ThrowIfCancellationRequested;
      end;
      if AClassifier.Classify(ATree, AFileName, mIndex, AInactive, mHit.Confidence) then
      begin
        mHit.Range := TTextRange.Create(ATree.Tokens[mIndex].StartPos, ATree.Tokens[mIndex].EndPos);
        mHits.Add(mHit);
      end;
    end;
    Result := mHits.ToArray;
  finally
    AClassifier.Resolver.UnpinTree;
    mHits.Free;
  end;
end;

class function TLspReferences.InactiveFor(const AFileName, AText: string;
  const ASettings: TReferenceSettings): TArray<TLspInactiveRegion>;
begin
  if ASettings.Inferred then
  begin
    Result := TReferenceClassifier.InactiveOf(AText, TSyntaxTreeCache.DefinesOf(TDocumentUris.FromPath(AFileName)));
  end
  else
  begin
    Result := nil;
  end;
end;


type
  /// <summary>Ein Lauf der Referenzsuche: Fundstellen und schon durchsuchte Dateien.</summary>
  TReferenceRun = class
  private
    FResolver: TNameResolver;
    FIndex: ISymbolIndex;
    FSearch: TReferenceSearch;
    FSettings: TReferenceSettings;
    FCancellation: IJsonRpcCancellationToken;
    FClassifier: TReferenceClassifier;
    FName: string;
    // Listen statt Result := Result + [...] (Code-Review P-08); bei vielen Treffern quadratisch.
    FLocations: TList<TReferenceLocation>;
    FSearched: TDictionary<string, Boolean>;
    procedure AddRanges(const AFile: string; const ARanges: TArray<TTextRange>);
    procedure AddHits(const AFile: string; const AHits: TArray<TReferenceHit>);
    procedure SearchFile(const AFileName: string);
  public
    constructor Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; const ASearch: TReferenceSearch;
      const ASettings: TReferenceSettings; const ACancellation: IJsonRpcCancellationToken);
    destructor Destroy; override;
    /// <summary>Einstufung für AWanted mit dem Namen AName (ohne &amp;).</summary>
    procedure Prepare(ATree: TSyntaxTree; const AWanted: TDefinitionTarget; const AName: string);
    procedure SearchOwn(ATree: TSyntaxTree);
    procedure SearchFiles;
    /// <summary>Formulare zur Unit der Deklaration, bei FMX samt Plattformansichten (#87).</summary>
    procedure SearchForms(const AWanted: TDefinitionTarget);
    /// <summary>Die Fundstellen; ohne FSearch.Declaration ohne die Deklaration AWanted.</summary>
    function Locations(const AWanted: TDefinitionTarget): TArray<TReferenceLocation>;
  end;

constructor TReferenceRun.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; const ASearch: TReferenceSearch;
  const ASettings: TReferenceSettings; const ACancellation: IJsonRpcCancellationToken);
begin
  inherited Create;
  FResolver := AResolver;
  FIndex := AIndex;
  FSearch := ASearch;
  FSettings := ASettings;
  FCancellation := ACancellation;
  FLocations := TList<TReferenceLocation>.Create;
  FSearched := TDictionary<string, Boolean>.Create;
end;

destructor TReferenceRun.Destroy;
begin
  FClassifier.Free;
  FSearched.Free;
  FLocations.Free;
  inherited;
end;

procedure TReferenceRun.AddRanges(const AFile: string; const ARanges: TArray<TTextRange>);
var
  mRange: TTextRange;
  mLocation: TReferenceLocation;
begin
  for mRange in ARanges do
  begin
    mLocation.FileName := AFile;
    mLocation.Range := mRange;
    mLocation.Confidence := TReferenceConfidence.Sure;
    FLocations.Add(mLocation);
  end;
end;

procedure TReferenceRun.AddHits(const AFile: string; const AHits: TArray<TReferenceHit>);
var
  mHit: TReferenceHit;
  mLocation: TReferenceLocation;
begin
  for mHit in AHits do
  begin
    mLocation.FileName := AFile;
    mLocation.Range := mHit.Range;
    mLocation.Confidence := mHit.Confidence;
    FLocations.Add(mLocation);
  end;
end;

procedure TReferenceRun.Prepare(ATree: TSyntaxTree; const AWanted: TDefinitionTarget; const AName: string);
var
  mSymbol: TIndexSymbol;
begin
  FName := AName;
  // Interface und virtual brauchen die Deklaration; ohne erschlossene Treffer genügt das Ziel.
  if FSettings.Inferred and TReferenceClassifier.SymbolOf(FResolver, FIndex, ATree, FSearch.FileName, AWanted,
    mSymbol) then
  begin
    FClassifier := TReferenceClassifier.Create(FResolver, FIndex, AWanted, mSymbol, AName, FSettings);
  end
  else
  begin
    FClassifier := TReferenceClassifier.Create(FResolver, FIndex, AWanted, AName, FSettings);
  end;
end;

procedure TReferenceRun.SearchOwn(ATree: TSyntaxTree);
var
  mText: string;
  mInactive: TArray<TLspInactiveRegion>;
begin
  // Auch der Baum des Editors (#845) führt die Tokens aller Zweige; welche inaktiv sind, sagen die Bereiche.
  mInactive := nil;
  if FSettings.Inferred and Assigned(FSearch.ReadText) and FSearch.ReadText(FSearch.FileName, mText) then
  begin
    mInactive := TLspReferences.InactiveFor(FSearch.FileName, mText, FSettings);
  end;
  AddHits(FSearch.FileName, HitsInTree(FClassifier, ATree, FSearch.FileName, FName, mInactive, FCancellation));
  FSearched.AddOrSetValue(AnsiUpperCase(FSearch.FileName), True);
end;

procedure TReferenceRun.SearchFile(const AFileName: string);
var
  mText: string;
  mTree: TSyntaxTree;
begin
  if FSearched.ContainsKey(AnsiUpperCase(AFileName)) then
  begin
    Exit;
  end;
  FSearched.Add(AnsiUpperCase(AFileName), True);
  // Die kürzere Schreibweise ist in der längeren enthalten.
  if not (Assigned(FSearch.ReadText) and FSearch.ReadText(AFileName, mText)) or not (ContainsText(mText, FName) or
    ContainsText(mText, AlternativeName(FName))) then
  begin
    Exit;
  end;
  // Parse liest alle Zweige; die inaktiven erkennt Classify an den Bereichen.
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    AddHits(AFileName, HitsInTree(FClassifier, mTree, AFileName, FName,
      TLspReferences.InactiveFor(AFileName, mText, FSettings), FCancellation));
  finally
    mTree.Free;
  end;
end;

procedure TReferenceRun.SearchFiles;
var
  mFileName: string;
begin
  for mFileName in FSearch.Files do
  begin
    SearchFile(mFileName);
  end;
end;

procedure TReferenceRun.SearchForms(const AWanted: TDefinitionTarget);
var
  mText, mDfmName: string;
begin
  if not Assigned(FSearch.ReadText) then
  begin
    Exit;
  end;
  if not FSearch.ReadText(AWanted.FileName, mText) then
  begin
    mText := '';
  end;
  for mDfmName in TFormFiles.FormFiles(AWanted.FileName, mText) do
  begin
    if FSearch.ReadText(mDfmName, mText) then
    begin
      AddRanges(mDfmName, InForm(mText, FName));
    end;
  end;
end;

function TReferenceRun.Locations(const AWanted: TDefinitionTarget): TArray<TReferenceLocation>;
var
  mIndex: Integer;
begin
  if not FSearch.Declaration then
  begin
    for mIndex := FLocations.Count - 1 downto 0 do
    begin
      if SameText(FLocations[mIndex].FileName, AWanted.FileName) and
        (FLocations[mIndex].Range.StartPos = AWanted.SelectionRange.StartPos) then
      begin
        FLocations.Delete(mIndex);
      end;
    end;
  end;
  Result := FLocations.ToArray;
end;

{ TReferenceSearch }

class function TReferenceSearch.Create(const AFileName: string; const APosition: TTextPosition;
  ADeclaration: Boolean; const AFiles: TArray<string>; const AReadText: TReferenceReadText): TReferenceSearch;
begin
  Result.FileName := AFileName;
  Result.Position := APosition;
  Result.Declaration := ADeclaration;
  Result.Files := AFiles;
  Result.ReadText := AReadText;
end;

{ TLspReferences }

class function TLspReferences.Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ASearch: TReferenceSearch): TArray<TReferenceLocation>;
begin
  Result := Find(AResolver, AIndex, ATree, ASearch, nil);
end;

class function TLspReferences.Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ASearch: TReferenceSearch; const ACancellation: IJsonRpcCancellationToken): TArray<TReferenceLocation>;
begin
  Result := Find(AResolver, AIndex, ATree, ASearch, TReferenceSettings.SureOnly, ACancellation);
end;

class function TLspReferences.Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ASearch: TReferenceSearch; const ASettings: TReferenceSettings;
  const ACancellation: IJsonRpcCancellationToken): TArray<TReferenceLocation>;
var
  mIndex: Integer;
  mWanted: TArray<TDefinitionTarget>;
  mRun: TReferenceRun;
begin
  Result := nil;
  mIndex := TokenAt(ATree.Tokens, ASearch.Position);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mRun := TReferenceRun.Create(AResolver, AIndex, ASearch, ASettings, ACancellation);
  // Den eigenen Baum einmal auswerten (Code-Review P-01): Targets und HitsInTree nutzen ihn; die Fremdbäume
  // pinnt HitsInTree darüber und löst sie wieder.
  AResolver.PinTree(ATree, ASearch.FileName);
  try
    mWanted := TLspDefinition.Targets(AResolver, AIndex, ATree, ASearch.FileName, ASearch.Position, True);
    if Length(mWanted) = 0 then
    begin
      Exit;
    end;
    mRun.Prepare(ATree, mWanted[0], CleanName(ATree.Tokens[mIndex].Text));
    mRun.SearchOwn(ATree);
    mRun.SearchFiles;
    mRun.SearchForms(mWanted[0]);
    Result := mRun.Locations(mWanted[0]);
  finally
    AResolver.UnpinTree;
    mRun.Free;
  end;
end;

/// <summary>Baum zu AUri: geöffnet aus dem Speicher (AShared), sonst selbst gelesen (AOwnTree, gehört dem
/// Aufrufer); nil, wenn die Datei nicht lesbar ist.</summary>
function TreeOf(const AStore: IDocumentStore; const AReadText: TReferenceReadText; const AUri: string;
  const ACancellation: IPascalCancellation; out AShared: ISharedSyntaxTree; out AOwnTree: TSyntaxTree): TSyntaxTree;
var
  mDocument: ITextDocument;
  mText: string;
begin
  AShared := nil;
  AOwnTree := nil;
  Result := nil;
  if AStore.TryGet(AUri, mDocument) then
  begin
    AShared := TSyntaxTreeCache.Get(mDocument, ACancellation);
    Result := AShared.Tree;
  end
  // Nicht geöffnete Datei (Verwendungen eines Typs aus dem Atlas-Tooltip, #588): selbst lesen.
  else if Assigned(AReadText) and AReadText(TDocumentUris.ToPath(AUri), mText) then
  begin
    AOwnTree := TSyntaxTreeCache.Parse(mText, ACancellation);
    Result := AOwnTree;
  end;
end;

/// <summary>Antwort auf textDocument/references zu AFound.</summary>
function LocationsJson(const AFound: TArray<TReferenceLocation>): TJSONArray;
var
  mLocation: TReferenceLocation;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mLocation in AFound do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('uri', TDocumentUris.FromPath(mLocation.FileName));
    mItem.AddPair('range', TLspPositions.RangeToJson(mLocation.Range));
    // Erweiterung (#1119): sicher oder erschlossen mit Grund; Editoren ohne Kenntnis übergehen das Feld.
    mItem.AddPair('atlasConfidence', mLocation.Confidence.ToJson);
    Result.AddElement(mItem);
  end;
end;

function TLspReferences.HandleReferences(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mPositionValue: TJSONValue;
  mIncludeDeclaration: Boolean;
  mTree, mOwnTree: TSyntaxTree;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mFiles: TArray<string>;
  mFound: TArray<TReferenceLocation>;
  mSettings: TReferenceSettings;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TReferencesText.FieldsTextDocumentUriAndPosition].Text + cMethod);
  end;
  if not TJSONObject(AParams).TryGetValue<Boolean>('context.includeDeclaration', mIncludeDeclaration) then
  begin
    mIncludeDeclaration := True;
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  mCancellation := TRequestCancellation.Create(ACancellation);
  mTree := TreeOf(FStore, FReadText, mUri, mCancellation, mShared, mOwnTree);
  if mTree = nil then
  begin
    Exit(TJSONNull.Create);
  end;
  try
    mFiles := nil;
    if Assigned(FFiles) then
    begin
      mFiles := FFiles();
    end;
    ACancellation.ThrowIfCancellationRequested;
    mSettings := TReferenceSettings.Default;
    if Assigned(FSettingsFor) then
    begin
      mSettings := FSettingsFor(mUri);
    end;
    mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      mResolver.Namespaces := Namespaces;
      mFound := Find(mResolver, FIndex, mTree, TReferenceSearch.Create(TDocumentUris.ToPath(mUri),
        TLspPositions.ReadPosition(mPositionValue), mIncludeDeclaration, mFiles, FReadText), mSettings,
        ACancellation);
    finally
      mResolver.Free;
    end;
  finally
    mOwnTree.Free;
  end;
  Result := LocationsJson(mFound);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.References', cTexts);

end.
