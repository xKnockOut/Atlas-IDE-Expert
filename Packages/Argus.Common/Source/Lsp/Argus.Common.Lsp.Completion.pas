unit Argus.Common.Lsp.Completion;

// Code-Vervollständigung (textDocument/completion), Grundstufe:
//   - nach "A.B." die Mitglieder des Typs von A.B samt geerbter, bei Units deren interface-Symbole,
//   - in uses die bekannten Units,
//   - sonst alle sichtbaren Namen (lokal, eigene Klasse, eigene Unit, Units aus uses).
// Ausgewählt wird unscharf (#229, TFuzzyMatch: Teilfolgen, Kürzel, Wortanfänge) oder mit
// completion.matching = prefix nur nach dem Anfang. Unscharf sortiert die Punktzahl,
// bei Gleichstand der nächste Gültigkeitsbereich; isIncomplete lässt den Editor bei
// jedem Tastendruck neu fragen, filterText verhindert, dass er Treffer verwirft.
// Ab zwei getippten Zeichen kommen Symbole aus noch nicht eingebundenen Units dazu (#180),
// Projekt-Units vor Bibliotheken; additionalTextEdits trägt die Unit beim Annehmen ins uses ein.
// Noch nicht: Sichtbarkeit (private/protected), Generics, Class Helper, Typinferenz bei var X := ….

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  Argus.Common.JsonRpc.Contract,
  Argus.Common.JsonRpc.Dispatcher,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Index.Contract,
  Argus.Common.Configuration.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Semantics.NameResolver;

type
  TCompletionContextKind = (None, Scope, Member, UsesClause);

  TCompletionContext = record
    Kind: TCompletionContextKind;
    /// <summary>Schon getippter Anfang des Namens.</summary>
    Prefix: string;
    /// <summary>Kette vor dem Punkt bei Member, z. B. ['Self', 'Liste'].</summary>
    Names: TArray<string>;
    /// <summary>Offset, an dem die Namen gelten.</summary>
    Offset: Integer;
  end;

  TCompletionItem = record
    Name: string;
    Detail: string;
    /// <summary>CompletionItemKind des LSP.</summary>
    Kind: Integer;
    /// <summary>Text für den Filter des Editors; '' = Name.</summary>
    FilterText: string;
    /// <summary>Weitere Änderungen beim Annehmen, z. B. der uses-Eintrag.</summary>
    AdditionalEdits: TArray<TRuleEdit>;
    /// <summary>Datei und Namensposition der Deklaration für completionItem/resolve; '' ohne.</summary>
    SourceFile: string;
    SourcePosition: TTextPosition;
    /// <summary>Deklarierender Typ bei Mitgliedern (#419); ''.</summary>
    Container: string;
    /// <summary>Vererbungstiefe bei Mitgliedern: 0 = eigener Typ (#419).</summary>
    Depth: Integer;
    /// <summary>Mitglied aus einem Helper (#456).</summary>
    IsHelper: Boolean;
    /// <summary>Namenspositionen weiterer Überladungen in SourceFile (#425).</summary>
    Overloads: TArray<TTextPosition>;
  end;

  TCompletionReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  TCompletionItems = record
    Items: TArray<TCompletionItem>;
    /// <summary>Liste wurde gekürzt; der Editor fragt beim Weitertippen neu.</summary>
    Incomplete: Boolean;
  end;

  TCompletionMatchingFunc = reference to function(const AUri: string): TCompletionMatching;

  TLspCompletion = class
  public const
    Method = 'textDocument/completion';
    ResolveMethod = 'completionItem/resolve';
    MaxItems = 1000;
    /// <summary>Höchstzahl der Vorschläge aus nicht eingebundenen Units.</summary>
    MaxImportItems = 200;
    /// <summary>So viele Zeichen muss der Name haben, bevor nicht eingebundene Units mitsuchen.</summary>
    MinImportPrefix = 2;
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    FMatchingFor: TCompletionMatchingFunc;
    FReadText: TCompletionReadText;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleResolve(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>completionProvider mit Punkt als Auslöser.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Was an APosition vervollständigt wird.</summary>
    class function Analyze(ATree: TSyntaxTree; const APosition: TTextPosition): TCompletionContext; static;
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition;
      AMatching: TCompletionMatching = TCompletionMatching.Fuzzy): TCompletionItems; static;
    class function KindOf(AKind: TIndexSymbolKind): Integer; static;
    /// <summary>CompletionList des LSP. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AItems: TCompletionItems): TJSONObject; static;
    /// <summary>Details zur Deklaration an APosition (Namensposition) in AText für das Detailpanel
    /// von Argus (#405, #424): declaration, unit, container, visibility, directives, deprecated,
    /// summary, params, returns, exceptions, remarks. Der Aufrufer übernimmt das Objekt.</summary>
    class function Details(const AIndex: ISymbolIndex; const AFileName, AText: string;
      const APosition: TTextPosition): TJSONObject; static;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
    /// <summary>Liest Dateien für completionItem/resolve; ohne Zuweisung keine Details.</summary>
    property ReadText: TCompletionReadText read FReadText write FReadText;
    /// <summary>Auswahl je Dokument; ohne Zuweisung unscharf.</summary>
    property MatchingFor: TCompletionMatchingFunc read FMatchingFor write FMatchingFor;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Argus.Common.Documents.Uris,
  Argus.Common.Lsp.Positions,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.TreeCache,
  Argus.Common.Lsp.FuzzyMatch,
  Argus.Common.Editing.UsesClause,
  Argus.Common.Lsp.CompilerDirectives,
  Argus.Common.Lsp.Internals.Cancellation,
  Argus.Common.Pascal.XmlDoc;

const
  // CompletionItemKind
  KindMethod = 2;
  KindFunction = 3;
  KindConstructor = 4;
  KindField = 5;
  KindVariable = 6;
  KindClass = 7;
  KindInterface = 8;
  KindModule = 9;
  KindProperty = 10;
  KindEnum = 13;
  KindEnumMember = 20;
  KindConstant = 21;
  KindStruct = 22;
  KindKeyword = 14;

/// <summary>Text der Zeile von APosition bis zum Cursor.</summary>
function LineBefore(const AText: string; const APosition: TTextPosition): string;
var
  Line, Start, Stop: Integer;
begin
  Start := 1;
  for Line := 1 to APosition.Line do
  begin
    Start := PosEx(#10, AText, Start) + 1;
    if Start = 1 then
      Exit('');
  end;
  Stop := Start;
  while (Stop <= Length(AText)) and (AText[Stop] <> #10) and (AText[Stop] <> #13) do
    Inc(Stop);
  Result := Copy(AText, Start, Min(APosition.Character, Stop - Start));
end;

/// <summary>Vorschläge in einer offenen Direktive (#102); False außerhalb.</summary>
function DirectiveItems(const AText: string; const APosition: TTextPosition; out AItems: TCompletionItems): Boolean;
var
  Names: TArray<string>;
  IsWarning: Boolean;
  Name: string;
  Item: TCompletionItem;
  Info: TDirectiveInfo;
begin
  AItems := Default(TCompletionItems);
  Result := TCompilerDirectives.CompletionAt(LineBefore(AText, APosition), Names, IsWarning);
  if not Result then
    Exit;
  for Name in Names do
  begin
    Item := Default(TCompletionItem);
    Item.Name := Name;
    Item.Kind := KindKeyword;
    if IsWarning then
      Item.Detail := 'Compiler-Warnung'
    else if TCompilerDirectives.Find(Name, Info) then
      Item.Detail := Info.Text;
    AItems.Items := AItems.Items + [Item];
  end;
end;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
    Result := A.Line - B.Line
  else
    Result := A.Character - B.Character;
end;

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
    Result := Copy(AText, 2, MaxInt)
  else
    Result := AText;
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function PreviousIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

function InUsesClause(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  Token: TPascalToken;
begin
  // Rückwärts über Unit-Namen, Punkte, Kommas und "in 'Datei'" bis zum uses.
  while AIndex >= 0 do
  begin
    Token := ATokens[AIndex];
    if Token.IsKeyword('uses') or Token.IsKeyword('contains') or Token.IsKeyword('requires') then
      Exit(True);
    if not ((Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.StringLiteral]) or
      Token.IsSymbol('.') or Token.IsSymbol(',') or Token.IsKeyword('in') or IsTrivia(Token)) then
      Exit(False);
    Dec(AIndex);
  end;
  Result := False;
end;

{ TLspCompletion }

constructor TLspCompletion.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspCompletion.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
  ADispatcher.RegisterConcurrentRequest(ResolveMethod, HandleResolve);
end;

class function TLspCompletion.Capability: TJSONObject;
var
  Triggers: TJSONArray;
begin
  Triggers := TJSONArray.Create;
  Triggers.Add('.');
  // {$ startet die Vervollständigung von Direktiven (#102).
  Triggers.Add('$');
  Result := TJSONObject.Create;
  Result.AddPair('triggerCharacters', Triggers);
  // Details für das Detailpanel von Argus erst für den gewählten Eintrag (#405, #424).
  Result.AddPair('resolveProvider', TJSONBool.Create(True));
end;

class function TLspCompletion.Analyze(ATree: TSyntaxTree; const APosition: TTextPosition): TCompletionContext;
var
  Tokens: TArray<TPascalToken>;
  Index, Last: Integer;
  Token: TPascalToken;
  Names: TList<string>;
begin
  Result := Default(TCompletionContext);
  Result.Kind := TCompletionContextKind.None;
  if ATree = nil then
    Exit;
  Tokens := ATree.Tokens;
  // Letztes Token, das vor dem Cursor beginnt.
  Last := -1;
  for Index := 0 to High(Tokens) do
  begin
    if ComparePositions(Tokens[Index].StartPos, APosition) >= 0 then
      Break;
    Last := Index;
  end;
  Result.Offset := 0;
  if Last >= 0 then
  begin
    Token := Tokens[Last];
    Result.Offset := Token.Offset + Length(Token.Text);
    if ComparePositions(APosition, Token.EndPos) < 0 then
    begin
      // Cursor mitten in einem Token: in Kommentaren, Strings und Zahlen nichts anbieten.
      if Token.Kind <> TPascalTokenKind.Identifier then
        Exit;
    end;
    if (Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      (ComparePositions(APosition, Token.EndPos) <= 0) then
    begin
      // Angefangener Name; auch ein halbes Schlüsselwort wie "beg" gilt als Anfang.
      if Token.Kind = TPascalTokenKind.Identifier then
        Result.Prefix := CleanName(Copy(Token.Text, 1, APosition.Character - Token.StartPos.Character))
      else
        Result.Prefix := Copy(Token.Text, 1, APosition.Character - Token.StartPos.Character);
      Result.Offset := Token.Offset;
      Last := PreviousIndex(Tokens, Last);
    end
    else if IsTrivia(Token) and (ComparePositions(APosition, Token.EndPos) <= 0) and
      Token.Text.StartsWith('//') then
      // Zeilenkommentar reicht bis zum Zeilenende.
      Exit
    else if IsTrivia(Token) then
      Last := PreviousIndex(Tokens, Last + 1);
  end;

  if (Last >= 0) and Tokens[Last].IsSymbol('.') then
  begin
    Names := TList<string>.Create;
    try
      Index := PreviousIndex(Tokens, Last);
      while (Index >= 0) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) do
      begin
        Names.Insert(0, CleanName(Tokens[Index].Text));
        Index := PreviousIndex(Tokens, Index);
        if (Index >= 0) and Tokens[Index].IsSymbol('.') then
          Index := PreviousIndex(Tokens, Index)
        else
          Break;
      end;
      // Foo(1). oder 1.: nicht auflösbar.
      if (Names.Count = 0) or (Index >= 0) and Tokens[Index].IsSymbol('.') then
        Exit;
      if InUsesClause(Tokens, Last) then
      begin
        // uses System.Sys…: der Anfang gehört zum Unit-Namen.
        Result.Kind := TCompletionContextKind.UsesClause;
        Result.Prefix := string.Join('.', Names.ToArray) + '.' + Result.Prefix;
        Exit;
      end;
      Result.Kind := TCompletionContextKind.Member;
      Result.Names := Names.ToArray;
      Result.Offset := Tokens[Last].Offset;
    finally
      Names.Free;
    end;
    Exit;
  end;
  if (Last >= 0) and InUsesClause(Tokens, Last) then
    Result.Kind := TCompletionContextKind.UsesClause
  else
    Result.Kind := TCompletionContextKind.Scope;
end;

class function TLspCompletion.KindOf(AKind: TIndexSymbolKind): Integer;
begin
  case AKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.HelperType, TIndexSymbolKind.TypeAlias:
      Result := KindClass;
    TIndexSymbolKind.RecordType:
      Result := KindStruct;
    TIndexSymbolKind.InterfaceType:
      Result := KindInterface;
    TIndexSymbolKind.EnumType:
      Result := KindEnum;
    TIndexSymbolKind.EnumMember:
      Result := KindEnumMember;
    TIndexSymbolKind.Constant:
      Result := KindConstant;
    TIndexSymbolKind.Field:
      Result := KindField;
    TIndexSymbolKind.Property_:
      Result := KindProperty;
    TIndexSymbolKind.Method:
      Result := KindMethod;
    TIndexSymbolKind.Constructor_:
      Result := KindConstructor;
    TIndexSymbolKind.Routine:
      Result := KindFunction;
  else
    Result := KindVariable;
  end;
end;

type
  TScoredItem = record
    Item: TCompletionItem;
    Score: Integer;
    Order: Integer;
  end;

  TScoredItemComparer = class(TInterfacedObject, IComparer<TScoredItem>)
  public
    function Compare(const Left, Right: TScoredItem): Integer;
  end;

function TScoredItemComparer.Compare(const Left, Right: TScoredItem): Integer;
begin
  // Höhere Punktzahl zuerst, sonst Reihenfolge der Gültigkeitsbereiche.
  if Left.Score <> Right.Score then
    Result := Right.Score - Left.Score
  else
    Result := Left.Order - Right.Order;
end;

/// <summary>Punktzahl von AName; TFuzzyMatch.NoMatch, wenn er nicht passt.</summary>
function MatchScore(const AName, APrefix: string; AMatching: TCompletionMatching): Integer;
begin
  if APrefix = '' then
    Exit(0);
  if AMatching = TCompletionMatching.Prefix then
  begin
    if AName.StartsWith(APrefix, True) then
      Exit(0);
    Exit(TFuzzyMatch.NoMatch);
  end;
  Result := TFuzzyMatch.Score(AName, APrefix);
end;

class function TLspCompletion.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; AMatching: TCompletionMatching): TCompletionItems;
var
  Context: TCompletionContext;
  Candidates: TArray<TResolvedSymbol>;
  Candidate: TResolvedSymbol;
  Units: TArray<TUnitIndex>;
  UnitInfo: TUnitIndex;
  List: TList<TScoredItem>;
  Scored: TScoredItem;
  Index: Integer;
  SourceFile: string;
  SourcePosition: TTextPosition;
  Member: TResolvedSymbol;

  procedure Add(const AName, ADetail: string; AKind: Integer; APenalty: Integer = 0;
    const AEdits: TArray<TRuleEdit> = nil);
  var
    Range: TTextRange;
  begin
    Scored.Score := MatchScore(AName, Context.Prefix, AMatching);
    if Scored.Score = TFuzzyMatch.NoMatch then
      Exit;
    Dec(Scored.Score, APenalty);
    Scored.Item.Name := AName;
    Scored.Item.AdditionalEdits := AEdits;
    Scored.Item.Detail := ADetail;
    Scored.Item.Kind := AKind;
    Scored.Item.SourceFile := SourceFile;
    Scored.Item.SourcePosition := SourcePosition;
    Scored.Item.Container := Member.Container;
    Scored.Item.Depth := Member.Depth;
    Scored.Item.IsHelper := Member.IsHelper;
    Scored.Item.Overloads := nil;
    for Range in Member.Overloads do
      Scored.Item.Overloads := Scored.Item.Overloads + [Range.StartPos];
    // Der Editor filtert selbst nach dem getippten Wort; unscharfe Treffer bekommen es
    // als filterText, damit er sie nicht verwirft.
    if (AMatching = TCompletionMatching.Fuzzy) and not AName.StartsWith(Context.Prefix, True) then
      Scored.Item.FilterText := Context.Prefix
    else
      Scored.Item.FilterText := '';
    Scored.Order := List.Count;
    List.Add(Scored);
  end;

  procedure AddFromOtherUnits;
  var
    Known: TDictionary<string, Boolean>;
    Used: TArray<string>;
    Own: string;
    Existing: TScoredItem;
    // Lokal: Eine for-Schleifenvariable darf nicht aus der äußeren Routine stammen (E1019).
    UnitInfo: TUnitIndex;
    Symbol: TIndexSymbol;
    Edit: TRuleEdit;
    Added, Before: Integer;
  begin
    Known := TDictionary<string, Boolean>.Create;
    try
      for Existing in List do
        Known.AddOrSetValue(UpperCase(Existing.Item.Name), True);
      Used := TUsesClauses.UsedUnits(ATree.Tokens);
      Own := TUsesClauses.OwnName(ATree.Tokens);
      Added := 0;
      for UnitInfo in AIndex.Units do
      begin
        if SameText(UnitInfo.UnitName, Own) or TUsesClauses.IsUsed(Used, UnitInfo.UnitName, AResolver.Namespaces) then
          Continue;
        for Symbol in UnitInfo.Symbols do
        begin
          if not Symbol.InInterface or (Symbol.Container <> '') or Known.ContainsKey(UpperCase(Symbol.Name)) then
            Continue;
          if MatchScore(Symbol.Name, Context.Prefix, AMatching) = TFuzzyMatch.NoMatch then
            Continue;
          if not TUsesClauses.AddUnit(ATree.Tokens, Context.Offset, UnitInfo.UnitName, #13#10, Edit) then
            Exit;
          Before := List.Count;
          // Eingebundenes zuerst, dann Projekt-Units, dann RTL/VCL und andere Bibliotheken.
          if UnitInfo.Library_ then
            Add(Symbol.Name, UnitInfo.UnitName + ' (uses ergänzen)', KindOf(Symbol.Kind), 200, [Edit])
          else
            Add(Symbol.Name, UnitInfo.UnitName + ' (uses ergänzen)', KindOf(Symbol.Kind), 100, [Edit]);
          // Gleichnamige Symbole verschiedener Units bleiben alle wählbar.
          if List.Count > Before then
          begin
            Inc(Added);
            if Added >= MaxImportItems then
              Exit;
          end;
        end;
      end;
    finally
      Known.Free;
    end;
  end;

begin
  Result := Default(TCompletionItems);
  Context := Analyze(ATree, APosition);
  SourceFile := '';
  SourcePosition := Default(TTextPosition);
  Member := Default(TResolvedSymbol);
  List := TList<TScoredItem>.Create(TScoredItemComparer.Create);
  try
    case Context.Kind of
      TCompletionContextKind.UsesClause:
        begin
          Units := AIndex.Units;
          for UnitInfo in Units do
            Add(UnitInfo.UnitName, UnitInfo.FileName, KindModule);
        end;
      TCompletionContextKind.Member, TCompletionContextKind.Scope:
        begin
          if Context.Kind = TCompletionContextKind.Member then
            Candidates := AResolver.MemberCandidates(ATree, AFileName, Context.Names, Context.Offset)
          else
            Candidates := AResolver.ScopeCandidates(ATree, AFileName, Context.Offset);
          for Candidate in Candidates do
          begin
            // Wo die Deklaration steht, für completionItem/resolve.
            SourceFile := Candidate.FileName;
            SourcePosition := Candidate.SelectionRange.StartPos;
            Member := Candidate;
            if Candidate.TypeName <> '' then
              Add(Candidate.Name, Candidate.TypeName, KindOf(Candidate.SymbolKind))
            else if Candidate.Container <> '' then
              Add(Candidate.Name, Candidate.Container, KindOf(Candidate.SymbolKind))
            else
              Add(Candidate.Name, Candidate.UnitName, KindOf(Candidate.SymbolKind));
          end;
          SourceFile := '';
          Member := Default(TResolvedSymbol);
          if (Context.Kind = TCompletionContextKind.Scope) and (Length(Context.Prefix) >= MinImportPrefix) then
            AddFromOtherUnits;
        end;
    end;
    List.Sort;
    // Unscharf fragt der Editor bei jedem Tastendruck neu, weil sich die Reihenfolge ändert.
    Result.Incomplete := (List.Count > MaxItems) or
      ((AMatching = TCompletionMatching.Fuzzy) and (Context.Kind <> TCompletionContextKind.None));
    if List.Count > MaxItems then
      List.Count := MaxItems;
    SetLength(Result.Items, List.Count);
    for Index := 0 to List.Count - 1 do
      Result.Items[Index] := List[Index].Item;
  finally
    List.Free;
  end;
end;

class function TLspCompletion.ToJson(const AItems: TCompletionItems): TJSONObject;
var
  Items, Edits, Overloads: TJSONArray;
  Entry, EditJson, Data: TJSONObject;
  Edit: TRuleEdit;
  Index: Integer;
  Position: TTextPosition;
begin
  Result := TJSONObject.Create;
  Result.AddPair('isIncomplete', TJSONBool.Create(AItems.Incomplete));
  Items := TJSONArray.Create;
  Result.AddPair('items', Items);
  for Index := 0 to High(AItems.Items) do
  begin
    Entry := TJSONObject.Create;
    Items.AddElement(Entry);
    Entry.AddPair('label', AItems.Items[Index].Name);
    Entry.AddPair('kind', TJSONNumber.Create(AItems.Items[Index].Kind));
    if AItems.Items[Index].Detail <> '' then
      Entry.AddPair('detail', AItems.Items[Index].Detail);
    if AItems.Items[Index].FilterText <> '' then
      Entry.AddPair('filterText', AItems.Items[Index].FilterText);
    if Length(AItems.Items[Index].AdditionalEdits) > 0 then
    begin
      Edits := TJSONArray.Create;
      Entry.AddPair('additionalTextEdits', Edits);
      for Edit in AItems.Items[Index].AdditionalEdits do
      begin
        EditJson := TJSONObject.Create;
        Edits.AddElement(EditJson);
        EditJson.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
        EditJson.AddPair('newText', Edit.NewText);
      end;
    end;
    // Reihenfolge wie geliefert: beste Punktzahl, dann nächster Gültigkeitsbereich.
    Entry.AddPair('sortText', Format('%.5d', [Index]));
    if AItems.Items[Index].SourceFile <> '' then
    begin
      Data := TJSONObject.Create;
      Data.AddPair('file', AItems.Items[Index].SourceFile);
      Data.AddPair('line', TJSONNumber.Create(AItems.Items[Index].SourcePosition.Line));
      Data.AddPair('character', TJSONNumber.Create(AItems.Items[Index].SourcePosition.Character));
      // Für die Argus-Oberfläche: Herkunft, Vererbungstiefe, Helper, Überladungen (#419, #425, #456).
      if AItems.Items[Index].Container <> '' then
        Data.AddPair('container', AItems.Items[Index].Container);
      if AItems.Items[Index].Depth > 0 then
        Data.AddPair('depth', TJSONNumber.Create(AItems.Items[Index].Depth));
      if AItems.Items[Index].IsHelper then
        Data.AddPair('helper', TJSONBool.Create(True));
      if Length(AItems.Items[Index].Overloads) > 0 then
      begin
        Overloads := TJSONArray.Create;
        Data.AddPair('overloads', Overloads);
        for Position in AItems.Items[Index].Overloads do
          Overloads.AddElement(TJSONObject.Create.AddPair('line', TJSONNumber.Create(Position.Line))
            .AddPair('character', TJSONNumber.Create(Position.Character)));
      end;
      Entry.AddPair('data', Data);
    end;
  end;
end;

function TLspCompletion.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Matching: TCompletionMatching;
  Directives: TCompletionItems;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen');
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  Cancellation := TRequestCancellation.Create(ACancellation);
  if DirectiveItems(Document.Text, TLspPositions.ReadPosition(PositionValue), Directives) then
    Exit(ToJson(Directives));
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := FNamespaces;
    if Assigned(FMatchingFor) then
      Matching := FMatchingFor(Uri)
    else
      Matching := TCompletionMatching.Fuzzy;
    Result := ToJson(Collect(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri),
      TLspPositions.ReadPosition(PositionValue), Matching));
  finally
    Resolver.Free;
  end;
end;

function VisibilityText(AVisibility: TIndexVisibility): string;
begin
  case AVisibility of
    TIndexVisibility.Published: Result := 'published';
    TIndexVisibility.Protected: Result := 'protected';
    TIndexVisibility.StrictProtected: Result := 'strict protected';
    TIndexVisibility.Private: Result := 'private';
    TIndexVisibility.StrictPrivate: Result := 'strict private';
  else
    Result := 'public';
  end;
end;

/// <summary>Zeilen von AText ohne Zeilenende.</summary>
function TextLines(const AText: string): TArray<string>;
var
  Index: Integer;
begin
  Result := AText.Split([#10]);
  for Index := 0 to High(Result) do
    if Result[Index].EndsWith(#13) then
      Result[Index] := Copy(Result[Index], 1, Length(Result[Index]) - 1);
end;

/// <summary>Deklaration von ARange; über mehr als MaxLines Zeilen (Klassen, Records) nur die erste.</summary>
function DeclarationOf(const ALines: TArray<string>; const ARange: TTextRange): string;
const
  MaxLines = 6;
  MaxLength = 600;
var
  Line, Last: Integer;
begin
  Result := '';
  Last := ARange.EndPos.Line;
  if Last - ARange.StartPos.Line >= MaxLines then
    Last := ARange.StartPos.Line;
  for Line := ARange.StartPos.Line to Last do
  begin
    if (Line < 0) or (Line > High(ALines)) then
      Break;
    if Line = ARange.StartPos.Line then
      Result := Trim(Copy(ALines[Line], ARange.StartPos.Character + 1, MaxInt))
    else
      Result := Result + ' ' + Trim(ALines[Line]);
  end;
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  if Length(Result) > MaxLength then
    Result := Copy(Result, 1, MaxLength) + ' …';
end;

/// <summary>Direktiven einer Deklaration (virtual, override, deprecated ...); ADeprecated: Text
/// hinter deprecated, '' ohne Text; AIsDeprecated: deprecated kommt vor.</summary>
function DirectivesOf(const ADeclaration: string; out ADeprecated: string; out AIsDeprecated: Boolean): TArray<string>;
const
  Known: array[0..13] of string = ('class', 'static', 'virtual', 'dynamic', 'override', 'abstract', 'final',
    'reintroduce', 'overload', 'inline', 'message', 'deprecated', 'platform', 'experimental');
var
  Text, Word: string;
  Index, Start, Quote: Integer;
  Words: TArray<string>;
begin
  Result := nil;
  ADeprecated := '';
  AIsDeprecated := False;
  // Strings ausblenden, damit Wörter darin nicht zählen; den deprecated-Text merken.
  Text := '';
  Index := 1;
  while Index <= Length(ADeclaration) do
  begin
    if ADeclaration[Index] = '''' then
    begin
      Quote := PosEx('''', ADeclaration, Index + 1);
      if Quote = 0 then
        Quote := Length(ADeclaration);
      if EndsText('deprecated', TrimRight(Text)) then
        ADeprecated := Copy(ADeclaration, Index + 1, Quote - Index - 1);
      Text := Text + ' ';
      Index := Quote + 1;
      Continue;
    end;
    Text := Text + ADeclaration[Index];
    Inc(Index);
  end;
  Words := nil;
  Start := 0;
  for Index := 1 to Length(Text) + 1 do
    if (Index > Length(Text)) or not CharInSet(Text[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      if Index - 1 > Start then
        Words := Words + [LowerCase(Copy(Text, Start + 1, Index - 1 - Start))];
      Start := Index;
    end;
  // "class" nur am Anfang (class function), sonst wäre jeder Klassentyp eine Klassenmethode.
  for Index := 0 to High(Words) do
  begin
    Word := Words[Index];
    if not MatchStr(Word, Known) or ((Word = 'class') and (Index > 0)) then
      Continue;
    if (Word = 'class') and ((High(Words) < 1) or not MatchStr(Words[1], ['function', 'procedure', 'property',
      'operator', 'constructor', 'destructor', 'var'])) then
      Continue;
    if Word = 'deprecated' then
      AIsDeprecated := True;
    if IndexStr(Word, Result) < 0 then
      Result := Result + [Word];
  end;
end;

class function TLspCompletion.Details(const AIndex: ISymbolIndex; const AFileName, AText: string;
  const APosition: TTextPosition): TJSONObject;
var
  Lines: TArray<string>;
  UnitInfo: TUnitIndex;
  Symbol, Candidate: TIndexSymbol;
  Found, IsDeprecated: Boolean;
  Declaration, Deprecated: string;
  Directives: TArray<string>;
  Directive: string;
  Doc: TXmlDoc;
  Entry: TXmlDocEntry;
  List: TJSONArray;
  Item: TJSONObject;
  Range: TTextRange;
begin
  Result := TJSONObject.Create;
  Lines := TextLines(AText);
  Found := False;
  Symbol := Default(TIndexSymbol);
  if (AIndex <> nil) and AIndex.FindFile(AFileName, UnitInfo) then
  begin
    Result.AddPair('unit', UnitInfo.UnitName);
    for Candidate in UnitInfo.Symbols do
      if (Candidate.SelectionRange.StartPos.Line = APosition.Line) and
        (Candidate.SelectionRange.StartPos.Character = APosition.Character) then
      begin
        Symbol := Candidate;
        Found := True;
        Break;
      end;
  end;
  if Found then
    Range := Symbol.Range
  else
  begin
    // Nicht im Index (lokale Variable, Parameter): die Zeile ab dem Namen.
    Range.StartPos := APosition;
    Range.EndPos := APosition;
  end;
  Declaration := DeclarationOf(Lines, Range);
  if Declaration <> '' then
    Result.AddPair('declaration', Declaration);
  if Found and (Symbol.Container <> '') then
  begin
    Result.AddPair('container', Symbol.Container);
    Result.AddPair('visibility', VisibilityText(Symbol.Visibility));
  end;
  Directives := DirectivesOf(Declaration, Deprecated, IsDeprecated);
  if Length(Directives) > 0 then
  begin
    List := TJSONArray.Create;
    for Directive in Directives do
      List.Add(Directive);
    Result.AddPair('directives', List);
  end;
  if IsDeprecated then
    Result.AddPair('deprecated', Deprecated);
  Doc := TXmlDoc.Parse(TXmlDoc.CommentAbove(Lines, Range.StartPos.Line));
  if Doc.Summary <> '' then
    Result.AddPair('summary', Doc.Summary);
  if Doc.Returns <> '' then
    Result.AddPair('returns', Doc.Returns);
  if Doc.Remarks <> '' then
    Result.AddPair('remarks', Doc.Remarks);
  if Length(Doc.Params) > 0 then
  begin
    List := TJSONArray.Create;
    for Entry in Doc.Params do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('name', Entry.Name);
      Item.AddPair('text', Entry.Text);
      List.AddElement(Item);
    end;
    Result.AddPair('params', List);
  end;
  if Length(Doc.Exceptions) > 0 then
  begin
    List := TJSONArray.Create;
    for Entry in Doc.Exceptions do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('name', Entry.Name);
      Item.AddPair('text', Entry.Text);
      List.AddElement(Item);
    end;
    Result.AddPair('exceptions', List);
  end;
end;

function TLspCompletion.HandleResolve(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Item, Data, Details: TJSONObject;
  FileName, Text, Summary: string;
  Position: TTextPosition;
begin
  if not (AParams is TJSONObject) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'CompletionItem fehlt in ' + ResolveMethod);
  // Antwort ist der Eintrag selbst, ergänzt um Details; ohne data unverändert.
  Item := TJSONObject(AParams.Clone);
  Result := Item;
  if not (Item.GetValue('data') is TJSONObject) or not Assigned(FReadText) then
    Exit;
  Data := TJSONObject(Item.GetValue('data'));
  if not (Data.TryGetValue<string>('file', FileName) and Data.TryGetValue<Integer>('line', Position.Line) and
    Data.TryGetValue<Integer>('character', Position.Character)) then
    Exit;
  if not FReadText(FileName, Text) then
    Exit;
  Details := TLspCompletion.Details(FIndex, FileName, Text, Position);
  // Für Argus (Detailpanel) strukturiert in data.argus; für andere Clients detail und documentation.
  if Details.TryGetValue<string>('declaration', Text) then
  begin
    Item.RemovePair('detail').Free;
    Item.AddPair('detail', Text);
  end;
  if Details.TryGetValue<string>('summary', Summary) then
    Item.AddPair('documentation', Summary);
  Data.AddPair('argus', Details);
end;

end.