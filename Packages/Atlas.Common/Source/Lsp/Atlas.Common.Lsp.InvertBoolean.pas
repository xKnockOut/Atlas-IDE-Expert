unit Atlas.Common.Lsp.InvertBoolean;

// „Boolean umkehren“ über das Protokoll (#715):
//   - Code-Aktion „Bedeutung umkehren (X → Y)“ auf einer Boolean-Variablen,
//     einem Feld, einer Konstanten, einer Property, einem Parameter oder einer
//     Boolean-Funktion des Projekts, nur mit refactoring.invertBoolean. Sie
//     trägt den Client-Befehl atlas.invertBoolean mit [uri, position,
//     vorgeschlagener Name]; das Plugin fragt den Namen nach.
//   - Befehl atlas.server.invertBoolean [uri, position, neuer Name]:
//     WorkspaceEdit mit Änderungsanmerkung (needsConfirmation) für die
//     Vorschau, dazu Warnungen.
// Welche Stellen dazugehören:
//   - Variable, Feld, Konstante: alle Verweise samt Deklaration. Felder und
//     globale Variablen starten mit False; die umgekehrten bekommen True
//     (Konstruktoren der Klasse bzw. Startwert), sonst eine Warnung.
//   - Funktion: alle Köpfe samt Überschreibungen und Interfaces (wie „Signatur
//     ändern“), ihre Rümpfe liefern das Gegenteil, Aufrufe werden verneint.
//   - Parameter: in allen Köpfen der Routine und ihren Rümpfen; Aufrufer
//     übergeben den verneinten Wert, ein Standardwert wird umgedreht.
//   - Property: Verweise, das gelesene Feld bzw. der Getter, der Setter
//     (umbenannt, sein Wertparameter umgekehrt, Aufrufer übergeben den
//     verneinten Wert) und ein default; ist sie published, mit
//     refactoring.invertBooleanIncludeDfm auch die Formulare der Klasse und
//     ihrer Nachfahren.
// Felder und Getter, die eine Property liest oder schreibt, kehrt nur die
// Property selbst um. Zeichenketten mit dem alten Namen (RTTI, FindComponent)
// und gebundene Ereignisse melden Warnungen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References;

type
  TInvertBooleanContext = record
    Index: ISymbolIndex;
    /// <summary>Dateien des Projekts für Referenzen, Formulare und Zeichenketten.</summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    /// <summary>Eigene Gegensatzpaare "A=B".</summary>
    Antonyms: TArray<string>;
    Prefix: string;
    IncludeDfm: Boolean;
    /// <summary>Neuer Name (nur für Execute).</summary>
    NewName: string;
  end;

  TLspInvertBoolean = class
  public const
    ClientCommand = 'atlas.invertBoolean';
    ApplyCommand = 'atlas.server.invertBoolean';
    Kind = 'refactor.rewrite';
    AnnotationId = 'invertBoolean';
  public
    /// <summary>Steht an APosition ein umkehrbares Boolean-Symbol des Projekts? ASymbol ist dann aufgelöst.</summary>
    class function Target(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition; const AFiles: TArray<string>; out ASymbol: TResolvedSymbol): Boolean; static;
    /// <summary>Die Code-Aktion an APosition oder nil; ob sie eingeschaltet ist, prüft der Aufrufer. Der
    /// Aufrufer übernimmt die Objekte.</summary>
    class function Actions(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AUri: string;
      const APosition: TTextPosition; const AContext: TInvertBooleanContext): TArray<TJSONObject>; static;
    /// <summary>{"edit": WorkspaceEdit, "warnings": [...], "places": n, "files": n}; EJsonRpcError, wenn dort
    /// nichts umkehrbar ist, AContext.NewName ungültig ist oder das Ergebnis nicht parst. Der Aufrufer übernimmt
    /// das Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AContext: TInvertBooleanContext): TJSONObject; static;
    /// <summary>var, out oder '' für Parameter AIndex (ab 0) laut Kopf ASignature.</summary>
    class function ParameterModifier(const ASignature: string; AIndex: Integer): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.InvertBoolean,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.ChangeSignature,
  Atlas.Common.Lsp.Rename,
  Atlas.Text.Lines;

const
  BooleanTypes: array[0..4] of string = ('Boolean', 'System.Boolean', 'ByteBool', 'WordBool', 'LongBool');
  FormExtensions: array[0..1] of string = ('.dfm', '.fmx');

type
  TSourceFile = class
  public
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    OwnsTree: Boolean;
    Lines: TLineTable;
    Targets: TInvertTargets;
    Extra: TArray<TTextEdit>;
    Resolver: TNameResolver;
    destructor Destroy; override;
    function Offset(const APosition: TTextPosition): Integer;
    function TokenAt(const APosition: TTextPosition): Integer;
    function IsVarArgument(ACall: TSyntaxNode; AArgument: Integer): Boolean;
  end;

destructor TSourceFile.Destroy;
begin
  if OwnsTree then
  begin
    Tree.Free;
  end;
  inherited;
end;

function TSourceFile.Offset(const APosition: TTextPosition): Integer;
begin
  Result := Lines.OffsetAt(APosition);
end;

function TSourceFile.TokenAt(const APosition: TTextPosition): Integer;
var
  Index, At: Integer;
  Tokens: TArray<TPascalToken>;
begin
  Tokens := Tree.Tokens;
  At := Offset(APosition);
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Offset = At then
    begin
      Exit(Index);
    end
    else if Tokens[Index].Offset > At then
    begin
      Break;
    end;
  end;
  Result := -1;
end;

function TSourceFile.IsVarArgument(ACall: TSyntaxNode; AArgument: Integer): Boolean;
var
  Callee: TSyntaxNode;
  Candidate: TResolvedSymbol;
  Modifier: string;
  Index: Integer;
  Tokens: TArray<TPascalToken>;
begin
  Result := False;
  if (Resolver = nil) or (ACall.ChildCount = 0) then
  begin
    Exit;
  end;
  Callee := ACall[0];
  // Der Name ist das letzte Token des Aufgerufenen (Obj.Toggle → Toggle).
  Tokens := Tree.Tokens;
  for Index := High(Tokens) downto 0 do
  begin
    if (Tokens[Index].Offset < Callee.EndOffset) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) then
    begin
      for Candidate in Resolver.ResolveAll(Tree, FileName, Tokens[Index].StartPos) do
      begin
        Modifier := TLspInvertBoolean.ParameterModifier(Candidate.Signature, AArgument);
        if (Modifier = 'var') or (Modifier = 'out') then
        begin
          Exit(True);
        end;
      end;
      Exit;
    end;
  end;
end;

function Fail(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, AMessage);
end;

function Where(const AFileName: string; const APosition: TTextPosition): string;
begin
  Result := Format('%s, Zeile %d', [ExtractFileName(AFileName), APosition.Line + 1]);
end;

function IsBooleanType(const ATypeName: string): Boolean;
begin
  Result := IndexText(Trim(ATypeName), BooleanTypes) >= 0;
end;

/// <summary>Vorheriges Token ohne Kommentare; -1 am Anfang.</summary>
function PreviousToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and (ATokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(Result);
  end;
end;

function NextToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and (ATokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(Result);
  end;
  if Result > High(ATokens) then
  begin
    Result := -1;
  end;
end;

/// <summary>Text zwischen der ersten "(" und ihrer passenden ")"; False ohne Parameterliste.</summary>
function ParameterList(const ASignature: string; out AList: string): Boolean;
var
  mOpen, mDepth, mIndex: Integer;
begin
  AList := '';
  mOpen := Pos('(', ASignature);
  mDepth := 0;
  if mOpen = 0 then
  begin
    Exit(False);
  end;
  for mIndex := mOpen to Length(ASignature) do
  begin
    if ASignature[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if ASignature[mIndex] = ')' then
    begin
      Dec(mDepth);
    end;
    if mDepth = 0 then
    begin
      AList := Copy(ASignature, mOpen + 1, mIndex - mOpen - 1);
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Modifier (var, out, const, constref; sonst '') eines Parameterabschnitts "var A, B: T" und in ANames
/// die Namen davor.</summary>
function SplitModifier(const APart: string; out ANames: string): string;
begin
  ANames := Trim(APart);
  // Attribute wie [ref] vorn weglassen.
  while StartsStr('[', ANames) and (Pos(']', ANames) > 0) do
  begin
    ANames := Trim(Copy(ANames, Pos(']', ANames) + 1, MaxInt));
  end;
  Result := LowerCase(Copy(ANames, 1, Pos(' ', ANames + ' ') - 1));
  if MatchStr(Result, ['var', 'out', 'const', 'constref']) then
  begin
    ANames := Trim(Copy(ANames, Length(Result) + 1, MaxInt));
  end
  else
  begin
    Result := '';
  end;
  if Pos(':', ANames) > 0 then
  begin
    ANames := Copy(ANames, 1, Pos(':', ANames) - 1);
  end;
end;

class function TLspInvertBoolean.ParameterModifier(const ASignature: string; AIndex: Integer): string;
var
  mList, mPart, mNames, mModifier: string;
  mCount: Integer;
begin
  Result := '';
  if not ParameterList(ASignature, mList) then
  begin
    Exit;
  end;
  mCount := 0;
  for mPart in mList.Split([';']) do
  begin
    mModifier := SplitModifier(mPart, mNames);
    Inc(mCount, Length(mNames.Split([','])));
    if AIndex < mCount then
    begin
      if MatchStr(mModifier, ['var', 'out']) then
      begin
        Result := mModifier;
      end;
      Exit;
    end;
  end;
end;

/// <summary>Ist ASymbol ein Boolean, das sich umkehren lässt?</summary>
function IsInvertible(const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := False;
  if not ASymbol.Found or (ASymbol.Kind = TResolvedKind.UnitName) or not IsBooleanType(ASymbol.TypeName) then
  begin
    Exit;
  end;
  if MatchText(ASymbol.Name, ['True', 'False', 'Result', 'Self']) then
  begin
    Exit;
  end;
  Result := ASymbol.IsParameter or (ASymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
    TIndexSymbolKind.Constant, TIndexSymbolKind.Property_, TIndexSymbolKind.Method, TIndexSymbolKind.Routine]);
end;

function Inside(const APosition: TTextPosition; const ARange: TTextRange): Boolean;
begin
  Result := ((ARange.StartPos.Line < APosition.Line) or ((ARange.StartPos.Line = APosition.Line) and
    (ARange.StartPos.Character <= APosition.Character))) and ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

/// <summary>Deklaration aus dem Index der Datei, deren Name APosition enthält.</summary>
function DeclarationAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; var AResult: TResolvedSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AResolver.ExtractedUnit(ATree, AFileName).Symbols do
  begin
    if Inside(APosition, mSymbol.SelectionRange) then
    begin
      AResult.Kind := TResolvedKind.Symbol;
      AResult.Name := mSymbol.Name;
      AResult.Container := mSymbol.Container;
      AResult.SymbolKind := mSymbol.Kind;
      AResult.FileName := IfThen(mSymbol.FileName <> '', mSymbol.FileName, AFileName);
      AResult.Range := mSymbol.Range;
      AResult.SelectionRange := mSymbol.SelectionRange;
      AResult.TypeName := mSymbol.TypeName;
      AResult.Visibility := mSymbol.Visibility;
      AResult.Signature := mSymbol.Signature;
      AResult.IsVirtual := mSymbol.IsVirtual;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Innerster Parameter-Knoten namens AToken.Text, der das Token enthält; nil ohne.</summary>
function ParameterNode(ATree: TSyntaxTree; const AToken: TPascalToken): TSyntaxNode;
var
  mFound: TSyntaxNode;
begin
  mFound := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.StartOffset <= AToken.Offset) and (AToken.Offset < ANode.EndOffset);
      if Result and (ANode.Kind = TSyntaxKind.Parameter) and SameText(ANode.Name, AToken.Text) then
      begin
        mFound := ANode;
      end;
    end);
  Result := mFound;
end;

/// <summary>Parameter im Kopf einer Routine an APosition.</summary>
procedure ParameterAt(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  var AResult: TResolvedSymbol);
var
  mToken: TPascalToken;
  mFound, mTypeRef: TSyntaxNode;
begin
  for mToken in ATree.Tokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Identifier) and Inside(APosition, TTextRange.Create(mToken.StartPos,
      mToken.EndPos)) then
    begin
      mFound := ParameterNode(ATree, mToken);
      if mFound = nil then
      begin
        Exit;
      end;
      AResult.Kind := TResolvedKind.Local;
      AResult.Name := mFound.Name;
      AResult.FileName := AFileName;
      AResult.IsParameter := True;
      AResult.SymbolKind := TIndexSymbolKind.Variable;
      AResult.SelectionRange := TTextRange.Create(mToken.StartPos, mToken.EndPos);
      AResult.Range := AResult.SelectionRange;
      mTypeRef := mFound.FindChild(TSyntaxKind.TypeReference);
      if mTypeRef <> nil then
      begin
        AResult.TypeName := mTypeRef.Name;
      end;
      Exit;
    end;
  end;
end;

/// <summary>Wie TNameResolver.Resolve, dazu Namen in Deklarationen: Mitglieder und globale Symbole aus dem
/// Index der Datei, Parameter aus dem Kopf.</summary>
function ResolveAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TResolvedSymbol;
begin
  Result := AResolver.Resolve(ATree, AFileName, APosition);
  if (Result.Kind = TResolvedKind.None) and not DeclarationAt(AResolver, ATree, AFileName, APosition, Result) then
  begin
    ParameterAt(ATree, AFileName, APosition, Result);
  end;
end;

class function TLspInvertBoolean.Target(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; const AFiles: TArray<string>; out ASymbol: TResolvedSymbol): Boolean;
begin
  Result := False;
  ASymbol := Default(TResolvedSymbol);
  if (AResolver = nil) or (ATree = nil) then
  begin
    Exit;
  end;
  ASymbol := ResolveAt(AResolver, ATree, AFileName, APosition);
  if not IsInvertible(ASymbol) then
  begin
    Exit;
  end;
  // Nur, was im Projekt steht: RTL und VCL (TControl.Visible) bleiben.
  Result := (ASymbol.Kind = TResolvedKind.Local) or SameText(ASymbol.FileName, AFileName) or
    (IndexText(ASymbol.FileName, AFiles) >= 0);
end;

class function TLspInvertBoolean.Actions(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AUri: string; const APosition: TTextPosition; const AContext: TInvertBooleanContext): TArray<TJSONObject>;
var
  mSymbol: TResolvedSymbol;
  mSuggested, mTitle: string;
  mArguments: TJSONArray;
  mCommand, mAction: TJSONObject;
begin
  Result := nil;
  if not Target(AResolver, ATree, AFileName, APosition, AContext.Files, mSymbol) then
  begin
    Exit;
  end;
  mSuggested := TInvertBoolean.Suggest(mSymbol.Name, AContext.Antonyms, AContext.Prefix);
  mTitle := Format('Bedeutung umkehren (%s → %s)', [mSymbol.Name, mSuggested]);
  mArguments := TJSONArray.Create;
  mArguments.Add(AUri);
  mArguments.AddElement(TLspPositions.PositionToJson(APosition));
  mArguments.Add(mSuggested);
  mCommand := TJSONObject.Create;
  mCommand.AddPair('title', mTitle);
  mCommand.AddPair('command', ClientCommand);
  mCommand.AddPair('arguments', mArguments);
  mAction := TJSONObject.Create;
  mAction.AddPair('title', mTitle);
  mAction.AddPair('kind', Kind);
  mAction.AddPair('command', mCommand);
  Result := [mAction];
end;

function EditsJson(const AUri: string; const AEdits: TArray<TTextEdit>): TJSONObject;
var
  Document, Item: TJSONObject;
  Items: TJSONArray;
  Edit: TTextEdit;
begin
  Document := TJSONObject.Create;
  Document.AddPair('uri', AUri);
  Document.AddPair('version', TJSONNull.Create);
  Items := TJSONArray.Create;
  for Edit in AEdits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
    Item.AddPair('newText', Edit.NewText);
    Item.AddPair('annotationId', TLspInvertBoolean.AnnotationId);
    Items.AddElement(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', Document);
  Result.AddPair('edits', Items);
end;

type
  /// <summary>Token hinter read, write und default einer Property; -1 ohne.</summary>
  TPropertyClauses = record
    Reader: Integer;
    Writer: Integer;
    Default_: Integer;
  end;

  /// <summary>Sammelt die Stellen je Datei.</summary>
  TInvertPlan = class
  private
    FResolver: TNameResolver;
    FContext: TInvertBooleanContext;
    FFileName: string;
    FText: string;
    FTree: TSyntaxTree;
    FSources: TObjectDictionary<string, TSourceFile>;
    FForms: TDictionary<string, TArray<TTextEdit>>;
  public
    Order: TList<string>;
    FormOrder: TList<string>;
    Warnings: TArray<string>;
    constructor Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const AContext: TInvertBooleanContext);
    destructor Destroy; override;
    function Source(const AFileName: string): TSourceFile;
    function Suggest(const AName: string): string;
    /// <summary>Mitglied AName der Klasse AContainer aus der Datei AFileName.</summary>
    function Member(const AFileName, AContainer, AName: string; out ASymbol: TResolvedSymbol): Boolean;
    /// <summary>Property der Klasse, die AName liest oder schreibt; ''.</summary>
    function AccessingProperty(const AFileName, AContainer, AName: string): string;
    procedure Warn(const AText: string);
    /// <summary>Verweise samt Deklaration; AAccessorCheck: Fail, wenn eine Property es liest oder schreibt.
    /// </summary>
    procedure AddReferences(const AFileName: string; const APosition: TTextPosition; const ANewName: string;
      AInvert, AAccessorCheck: Boolean);
    procedure AddVariable(const ASymbol: TResolvedSymbol; const ANewName: string; AAccessorCheck: Boolean);
    procedure AddFunction(const AFileName: string; const APosition: TTextPosition; const ANewName: string;
      AAccessorCheck: Boolean);
    procedure AddSetter(const AFileName: string; const APosition: TTextPosition; const ANewName: string);
    procedure AddParameter(const ASymbol: TResolvedSymbol; const ANewName: string);
    procedure AddProperty(const ASymbol: TResolvedSymbol; const ANewName: string);
    procedure AddForms(const AClassName, AOld, ANew: string);
    procedure AddStartValue(const ASymbol: TResolvedSymbol; const ANewName: string);
    procedure CheckStrings(const AOld: string);
    function FormEdits(const AFileName: string): TArray<TTextEdit>;
    /// <summary>Quelltext AFileName; Fail, wenn er sich nicht lesen lässt.</summary>
    function ReadableSource(const AFileName: string): TSourceFile;
    function ReferenceToken(const ALocation: TReferenceLocation; out AUnit: TSourceFile; out AToken: Integer): Boolean;
    procedure WarnAll(const ATexts: TArray<string>);
    procedure AddFieldStart(AUnit: TSourceFile; AToken: Integer; const ASymbol: TResolvedSymbol;
      const ANewName: string);
    /// <summary>Fail, wenn die Funktion Zugriffsmethode einer Property ist.</summary>
    procedure CheckFunctionAccessor(const AFamily: TRoutineFamily; AOrigin: TSourceFile;
      const APosition: TTextPosition);
    procedure AddParameterIn(const AItem: TRoutineFamilyHeader; AParameter: Integer; const ASymbol: TResolvedSymbol;
      const ANewName: string);
    procedure AddReader(AUnit: TSourceFile; const AContainer: string; AReader: Integer);
    procedure AddWriter(AUnit: TSourceFile; const AContainer: string; const AClauses: TPropertyClauses);
    procedure AddPublished(const ASymbol: TResolvedSymbol; const ANewName: string);
    procedure AddForm(const AForm: string; const AClasses: TArray<string>; const AOld, ANew: string);
    /// <summary>Stellen für ASymbol unter dem neuen Namen ANewName sammeln.</summary>
    procedure Apply(const ASymbol: TResolvedSymbol; const ANewName: string);
    /// <summary>Änderungen und Rückbau-Prüfung der Unit AFileName.</summary>
    function UnitEdits(const AFileName: string): TArray<TTextEdit>;
    /// <summary>documentChanges aller Dateien. Der Aufrufer übernimmt das Objekt.</summary>
    function DocumentChanges(out APlaces, AFiles: Integer): TJSONArray;
  end;

constructor TInvertPlan.Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
  const AContext: TInvertBooleanContext);
begin
  inherited Create;
  FResolver := AResolver;
  FTree := ATree;
  FFileName := AFileName;
  FText := AText;
  FContext := AContext;
  FSources := TObjectDictionary<string, TSourceFile>.Create([doOwnsValues]);
  FForms := TDictionary<string, TArray<TTextEdit>>.Create;
  Order := TList<string>.Create;
  FormOrder := TList<string>.Create;
end;

destructor TInvertPlan.Destroy;
begin
  FormOrder.Free;
  Order.Free;
  FForms.Free;
  FSources.Free;
  inherited;
end;

function TInvertPlan.Source(const AFileName: string): TSourceFile;
var
  Text: string;
  Created: TSourceFile;
begin
  if FSources.TryGetValue(UpperCase(AFileName), Result) then
  begin
    Exit;
  end;
  Result := nil;
  if SameText(AFileName, FFileName) then
  begin
    Result := TSourceFile.Create;
    Result.Text := FText;
    Result.Tree := FTree;
  end
  else if Assigned(FContext.ReadText) and FContext.ReadText(AFileName, Text) then
  begin
    Result := TSourceFile.Create;
    Result.Text := Text;
    Result.Tree := TSyntaxTreeCache.Parse(Text);
    Result.OwnsTree := True;
  end;
  if Result = nil then
  begin
    Exit;
  end;
  Result.FileName := AFileName;
  Result.Lines := TLineTable.Build(Result.Text);
  Result.Resolver := FResolver;
  // Methodenzeiger über eine lokale Variable: Result lässt sich nicht erfassen (E2555).
  Created := Result;
  Result.Targets.VarArgument := Created.IsVarArgument;
  FSources.Add(UpperCase(AFileName), Result);
  Order.Add(AFileName);
end;

function TInvertPlan.Suggest(const AName: string): string;
begin
  Result := TInvertBoolean.Suggest(AName, FContext.Antonyms, FContext.Prefix);
end;

function TInvertPlan.Member(const AFileName, AContainer, AName: string; out ASymbol: TResolvedSymbol): Boolean;
var
  Unit_: TSourceFile;
  Symbol: TIndexSymbol;
begin
  Result := False;
  ASymbol := Default(TResolvedSymbol);
  Unit_ := Source(AFileName);
  if (Unit_ = nil) or (Unit_.Tree = nil) then
  begin
    Exit;
  end;
  for Symbol in FResolver.ExtractedUnit(Unit_.Tree, AFileName).Symbols do
  begin
    if SameText(Symbol.Container, AContainer) and SameText(Symbol.Name, AName) and
      (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Method]) then
    begin
      ASymbol.Kind := TResolvedKind.Symbol;
      ASymbol.Name := Symbol.Name;
      ASymbol.Container := Symbol.Container;
      ASymbol.SymbolKind := Symbol.Kind;
      ASymbol.FileName := AFileName;
      ASymbol.Range := Symbol.Range;
      ASymbol.SelectionRange := Symbol.SelectionRange;
      ASymbol.TypeName := Symbol.TypeName;
      ASymbol.Visibility := Symbol.Visibility;
      ASymbol.Signature := Symbol.Signature;
      Exit(True);
    end;
  end;
end;

/// <summary>Liegt ANode (Property) in der Klasse AContainer?</summary>
function IsPropertyOf(ANode: TSyntaxNode; const AContainer: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.PropertyDecl) and (ANode.Parent <> nil) and (ANode.Parent.Parent <> nil) and
    SameText(ANode.Parent.Parent.Name, AContainer);
end;

/// <summary>Nennt die Property ANode AName in read oder write?</summary>
function ClauseMentions(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
  mInClause: Boolean;
begin
  mInClause := False;
  mIndex := TSyntaxTree.FirstTokenOf(ATokens, ANode.StartOffset);
  while (mIndex < High(ATokens)) and (ATokens[mIndex].Offset < ANode.EndOffset) do
  begin
    if MatchText(ATokens[mIndex].Text, ['read', 'write']) then
    begin
      mInClause := True;
    end
    else if mInClause and SameText(ATokens[mIndex].Text, AName) then
    begin
      Exit(True);
    end;
    Inc(mIndex);
  end;
  Result := False;
end;

function TInvertPlan.AccessingProperty(const AFileName, AContainer, AName: string): string;
var
  mUnit: TSourceFile;
  mTokens: TArray<TPascalToken>;
  mFound: string;
begin
  Result := '';
  mUnit := Source(AFileName);
  if (mUnit = nil) or (mUnit.Tree = nil) or (AContainer = '') then
  begin
    Exit;
  end;
  mTokens := mUnit.Tree.Tokens;
  mFound := '';
  mUnit.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := mFound = '';
      if Result and IsPropertyOf(ANode, AContainer) and ClauseMentions(mTokens, ANode, AName) then
      begin
        mFound := ANode.Name;
      end;
    end);
  Result := mFound;
end;

procedure TInvertPlan.Warn(const AText: string);
begin
  if IndexStr(AText, Warnings) < 0 then
  begin
    Warnings := Warnings + [AText];
  end;
end;

/// <summary>Datei und Token einer Fundstelle im Quelltext; False bei Formularen und Unlesbarem.</summary>
function TInvertPlan.ReferenceToken(const ALocation: TReferenceLocation; out AUnit: TSourceFile;
  out AToken: Integer): Boolean;
begin
  AUnit := nil;
  AToken := -1;
  if not MatchText(ExtractFileExt(ALocation.FileName), ['.dfm', '.fmx']) then
  begin
    AUnit := Source(ALocation.FileName);
  end;
  if (AUnit <> nil) and (AUnit.Tree <> nil) then
  begin
    AToken := AUnit.TokenAt(ALocation.Range.StartPos);
  end;
  Result := AToken >= 0;
end;

/// <summary>Fail, wenn das Token AToken in AUnit hinter read oder write steht.</summary>
procedure CheckNoAccessor(AUnit: TSourceFile; AToken: Integer; const ALocation: TReferenceLocation);
var
  mTokens: TArray<TPascalToken>;
  mPrevious: Integer;
begin
  mTokens := AUnit.Tree.Tokens;
  mPrevious := PreviousToken(mTokens, AToken);
  if (mPrevious >= 0) and MatchText(mTokens[mPrevious].Text, ['read', 'write']) then
  begin
    raise Fail(Format('%s: %s ist Zugriff einer Property. Bitte die Property umkehren.',
      [Where(ALocation.FileName, ALocation.Range.StartPos), mTokens[AToken].Text]));
  end;
end;

function TInvertPlan.ReadableSource(const AFileName: string): TSourceFile;
begin
  Result := Source(AFileName);
  if (Result = nil) or (Result.Tree = nil) then
  begin
    raise Fail(Format('%s lässt sich nicht lesen.', [ExtractFileName(AFileName)]));
  end;
end;

procedure TInvertPlan.AddReferences(const AFileName: string; const APosition: TTextPosition;
  const ANewName: string; AInvert, AAccessorCheck: Boolean);
var
  mOrigin, mUnit: TSourceFile;
  mLocation: TReferenceLocation;
  mToken: Integer;
begin
  mOrigin := ReadableSource(AFileName);
  for mLocation in TLspReferences.Find(FResolver, FContext.Index, mOrigin.Tree, AFileName, APosition, True,
    FContext.Files, FContext.ReadText) do
  begin
    if not ReferenceToken(mLocation, mUnit, mToken) then
    begin
      Continue;
    end;
    if AAccessorCheck then
    begin
      CheckNoAccessor(mUnit, mToken, mLocation);
    end;
    mUnit.Targets.AddName(mUnit.Tree.Tokens[mToken].Offset, ANewName, AInvert);
  end;
end;

procedure TInvertPlan.AddVariable(const ASymbol: TResolvedSymbol; const ANewName: string; AAccessorCheck: Boolean);
var
  Owner: string;
begin
  if AAccessorCheck and (ASymbol.SymbolKind = TIndexSymbolKind.Field) then
  begin
    Owner := AccessingProperty(ASymbol.FileName, ASymbol.Container, ASymbol.Name);
    if Owner <> '' then
    begin
      raise Fail(Format('%s ist Zugriff der Property %s. Bitte die Property umkehren.', [ASymbol.Name, Owner]));
    end;
  end;
  AddReferences(ASymbol.FileName, ASymbol.SelectionRange.StartPos, ANewName, True, AAccessorCheck);
  AddStartValue(ASymbol, ANewName);
end;

/// <summary>Knoten der Art AKind, dessen Bereich APosition enthält (der innerste).</summary>
function NodeAt(ATree: TSyntaxTree; AKind: TSyntaxKind; AOffset: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.StartOffset <= AOffset) and (AOffset <= ANode.EndOffset);
      if Result and (ANode.Kind = AKind) then
      begin
        Found := ANode;
      end;
    end);
  Result := Found;
end;

/// <summary>Globale Variable: " = True" hinter den Typ. False, wenn das so nicht geht (Warnung nötig).</summary>
function AddVariableStart(AUnit: TSourceFile; AToken: Integer): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mDecl, mTypeRef: TSyntaxNode;
  mPosition: TTextPosition;
begin
  mTokens := AUnit.Tree.Tokens;
  mDecl := NodeAt(AUnit.Tree, TSyntaxKind.VarDecl, mTokens[AToken].Offset);
  // Schon mit Startwert: VisitDeclaration verneint ihn.
  if (mDecl = nil) or (mDecl.ChildCount > 1) then
  begin
    Exit(True);
  end;
  mTypeRef := mDecl.FindChild(TSyntaxKind.TypeReference);
  Result := (mTypeRef <> nil) and (NextToken(mTokens, AToken) >= 0) and mTokens[NextToken(mTokens, AToken)].IsSymbol(':');
  if Result then
  begin
    mPosition := AUnit.Lines.PositionAt(mTypeRef.EndOffset);
    AUnit.Extra := AUnit.Extra + [TTextEdit.Create(TTextRange.Create(mPosition, mPosition), ' = True')];
  end;
end;

/// <summary>Konstruktoren der Klasse AClassName in AUnit (Rümpfe mit Kopf und Block).</summary>
function ClassConstructors(AUnit: TSourceFile; const AClassName: string): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  AUnit.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mHeader: TSyntaxNode;
    begin
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      mHeader := nil;
      if not Result and StartsText(AClassName + '.', ANode.Name) and (ANode.FindChild(TSyntaxKind.Block) <> nil) then
      begin
        mHeader := ANode.FindChild(TSyntaxKind.RoutineHeader);
      end;
      if (mHeader <> nil) and StartsText('constructor', TrimLeft(Copy(AUnit.Text, mHeader.StartOffset + 1,
        mHeader.EndOffset - mHeader.StartOffset))) then
      begin
        mFound := mFound + [ANode];
      end;
    end);
  Result := mFound;
end;

/// <summary>Index des ersten begin ab AOffset; -1 ohne.</summary>
function BeginToken(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    if (ATokens[mIndex].Offset >= AOffset) and ATokens[mIndex].IsKeyword('begin') then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Ende der Anweisung AStatement samt ";".</summary>
function StatementEnd(AUnit: TSourceFile; AStatement: TSyntaxNode): Integer;
var
  mTokens: TArray<TPascalToken>;
  mAt: Integer;
begin
  mTokens := AUnit.Tree.Tokens;
  Result := AStatement.EndOffset;
  mAt := NextToken(mTokens, AUnit.TokenAt(AUnit.Lines.PositionAt(AStatement.StartOffset)));
  while (mAt >= 0) and (mTokens[mAt].Offset < AStatement.EndOffset) do
  begin
    mAt := NextToken(mTokens, mAt);
  end;
  if (mAt >= 0) and mTokens[mAt].IsSymbol(';') then
  begin
    Result := mTokens[mAt].Offset + 1;
  end;
end;

/// <summary>"ANewName := True;" im Konstruktor ARoutine: hinter inherited …, sonst gleich hinter begin.</summary>
procedure AddConstructorStart(AUnit: TSourceFile; ARoutine: TSyntaxNode; const ANewName: string);
var
  mTokens: TArray<TPascalToken>;
  mBlock, mStatement: TSyntaxNode;
  mBegin, mInsert, mIndex: Integer;
  mIndent: string;
  mPosition: TTextPosition;
begin
  mTokens := AUnit.Tree.Tokens;
  mBlock := ARoutine.FindChild(TSyntaxKind.Block);
  mBegin := BeginToken(mTokens, mBlock.StartOffset);
  if mBegin < 0 then
  begin
    Exit;
  end;
  mInsert := mTokens[mBegin].Offset + Length(mTokens[mBegin].Text);
  mIndent := '  ';
  if mBlock.ChildCount > 0 then
  begin
    mIndent := StringOfChar(' ', AUnit.Lines.PositionAt(mBlock[0].StartOffset).Character);
  end;
  for mIndex := 0 to mBlock.ChildCount - 1 do
  begin
    mStatement := mBlock[mIndex];
    if StartsText('inherited', Copy(AUnit.Text, mStatement.StartOffset + 1, 9)) then
    begin
      mInsert := StatementEnd(AUnit, mStatement);
      Break;
    end;
  end;
  mPosition := AUnit.Lines.PositionAt(mInsert);
  AUnit.Extra := AUnit.Extra + [TTextEdit.Create(TTextRange.Create(mPosition, mPosition),
    TTextLines.LineBreakOf(AUnit.Text) + mIndent + ANewName + ' := True;')];
end;

/// <summary>Name der Klasse ohne Typparameter.</summary>
function PlainClassName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
end;

procedure TInvertPlan.AddFieldStart(AUnit: TSourceFile; AToken: Integer; const ASymbol: TResolvedSymbol;
  const ANewName: string);
var
  mTypeDecl, mRoutine: TSyntaxNode;
  mClassName: string;
  mConstructors: TArray<TSyntaxNode>;
begin
  mTypeDecl := NodeAt(AUnit.Tree, TSyntaxKind.TypeDecl, AUnit.Tree.Tokens[AToken].Offset);
  if (mTypeDecl = nil) or (mTypeDecl.FindChild(TSyntaxKind.ClassType) = nil) then
  begin
    Warn(Format('%s: %s beginnt mit False; bitte %s := True setzen, wo der Wert entsteht.',
      [Where(ASymbol.FileName, ASymbol.SelectionRange.StartPos), ASymbol.Name, ANewName]));
    Exit;
  end;
  mClassName := PlainClassName(mTypeDecl.Name);
  mConstructors := ClassConstructors(AUnit, mClassName);
  for mRoutine in mConstructors do
  begin
    AddConstructorStart(AUnit, mRoutine, ANewName);
  end;
  if mConstructors = nil then
  begin
    Warn(Format('%s hat keinen Konstruktor in %s: %s beginnt mit False; bitte im Konstruktor %s := True setzen.',
      [mClassName, ExtractFileName(ASymbol.FileName), ASymbol.Name, ANewName]));
  end;
end;

procedure TInvertPlan.AddStartValue(const ASymbol: TResolvedSymbol; const ANewName: string);
var
  mUnit: TSourceFile;
  mToken: Integer;
begin
  // Felder und globale Variablen beginnen mit False; umgekehrt muss es True sein.
  mUnit := nil;
  mToken := -1;
  if ASymbol.Kind <> TResolvedKind.Local then
  begin
    mUnit := Source(ASymbol.FileName);
  end;
  if (mUnit <> nil) and (mUnit.Tree <> nil) then
  begin
    mToken := mUnit.TokenAt(ASymbol.SelectionRange.StartPos);
  end;
  if mToken < 0 then
  begin
    Exit;
  end;
  if (ASymbol.SymbolKind = TIndexSymbolKind.Variable) and not AddVariableStart(mUnit, mToken) then
  begin
    Warn(Format('%s: %s beginnt mit False; bitte als %s: Boolean = True deklarieren.',
      [Where(ASymbol.FileName, ASymbol.SelectionRange.StartPos), ASymbol.Name, ANewName]));
  end
  else if ASymbol.SymbolKind = TIndexSymbolKind.Field then
  begin
    AddFieldStart(mUnit, mToken, ASymbol, ANewName);
  end;
end;

procedure TInvertPlan.CheckFunctionAccessor(const AFamily: TRoutineFamily; AOrigin: TSourceFile;
  const APosition: TTextPosition);
var
  mOwner: TResolvedSymbol;
  mProperty: string;
begin
  if AFamily.Accessors <> nil then
  begin
    raise Fail(Format('%s ist Zugriffsmethode einer Property (%s). Bitte die Property umkehren.',
      [AFamily.Name, AFamily.Accessors[0]]));
  end;
  mOwner := ResolveAt(FResolver, AOrigin.Tree, AOrigin.FileName, APosition);
  mProperty := '';
  if mOwner.Container <> '' then
  begin
    mProperty := AccessingProperty(mOwner.FileName, mOwner.Container, mOwner.Name);
  end;
  if mProperty <> '' then
  begin
    raise Fail(Format('%s ist Zugriffsmethode der Property %s. Bitte die Property umkehren.',
      [mOwner.Name, mProperty]));
  end;
end;

procedure TInvertPlan.AddFunction(const AFileName: string; const APosition: TTextPosition; const ANewName: string;
  AAccessorCheck: Boolean);
var
  mOrigin, mUnit: TSourceFile;
  mFamily: TRoutineFamily;
  mHeader: TRoutineFamilyHeader;
  mCall: TRoutineFamilyCall;
  mToken: Integer;
begin
  mOrigin := ReadableSource(AFileName);
  mFamily := TLspChangeSignature.Family(FResolver, FContext.Index, mOrigin.Tree, AFileName, APosition,
    FContext.Files, FContext.ReadText, nil);
  if AAccessorCheck then
  begin
    CheckFunctionAccessor(mFamily, mOrigin, APosition);
  end;
  if mFamily.BoundEvent <> '' then
  begin
    raise Fail(Format('%s ist an ein Ereignis gebunden (%s).', [mFamily.Name, mFamily.BoundEvent]));
  end;
  WarnAll(mFamily.Warnings);
  for mHeader in mFamily.Headers do
  begin
    mUnit := Source(mHeader.FileName);
    mToken := -1;
    if mUnit <> nil then
    begin
      mToken := mUnit.TokenAt(mHeader.NamePos);
    end;
    if mToken >= 0 then
    begin
      mUnit.Targets.AddName(mUnit.Tree.Tokens[mToken].Offset, ANewName, True);
      if mHeader.IsBody then
      begin
        mUnit.Targets.AddBody(mUnit.Tree.Tokens[mToken].Offset);
      end;
    end;
  end;
  for mCall in mFamily.Calls do
  begin
    mUnit := Source(mCall.FileName);
    if mUnit <> nil then
    begin
      mUnit.Targets.AddName(mUnit.Offset(mCall.NamePos), ANewName, True);
    end;
  end;
end;

procedure TInvertPlan.WarnAll(const ATexts: TArray<string>);
var
  mText: string;
begin
  for mText in ATexts do
  begin
    Warn(mText);
  end;
end;

procedure TInvertPlan.AddSetter(const AFileName: string; const APosition: TTextPosition; const ANewName: string);
var
  Origin, Unit_: TSourceFile;
  Family: TRoutineFamily;
  Header: TRoutineFamilyHeader;
  Call: TRoutineFamilyCall;
  Last: Integer;
  Name: string;
begin
  Origin := Source(AFileName);
  if (Origin = nil) or (Origin.Tree = nil) then
  begin
    raise Fail(Format('%s lässt sich nicht lesen.', [ExtractFileName(AFileName)]));
  end;
  Family := TLspChangeSignature.Family(FResolver, FContext.Index, Origin.Tree, AFileName, APosition,
    FContext.Files, FContext.ReadText, nil);
  Last := -1;
  for Header in Family.Headers do
  begin
    Unit_ := Source(Header.FileName);
    if Unit_ = nil then
    begin
      Continue;
    end;
    Unit_.Targets.AddName(Unit_.Offset(Header.NamePos), ANewName, False);
    if Header.Parameters = nil then
    begin
      Continue;
    end;
    Last := High(Header.Parameters);
    // Der Wertparameter steht zuletzt; sein Name bleibt, seine Bedeutung kehrt sich um.
    Name := Header.Parameters[Last].Name;
    if Header.IsBody then
    begin
      Unit_.Targets.AddLocal(Unit_.Offset(Header.NamePos), Name, Name);
    end;
  end;
  for Call in Family.Calls do
  begin
    Unit_ := Source(Call.FileName);
    if Unit_ = nil then
    begin
      Continue;
    end;
    Unit_.Targets.AddName(Unit_.Offset(Call.NamePos), ANewName, False);
    if Last >= 0 then
    begin
      Unit_.Targets.AddCall(Unit_.Offset(Call.NamePos), Last);
    end;
  end;
  for Name in Family.Warnings do
  begin
    Warn(Name);
  end;
end;

/// <summary>Literal True/False nach "=" ab Token AFrom bis vor ";" bzw. ")"; -1 ohne.</summary>
function DefaultToken(const ATokens: TArray<TPascalToken>; AFrom: Integer): Integer;
var
  Index: Integer;
begin
  Result := -1;
  Index := AFrom;
  while (Index >= 0) and (Index <= High(ATokens)) do
  begin
    if ATokens[Index].IsSymbol(';') or ATokens[Index].IsSymbol(')') then
    begin
      Exit;
    end;
    if ATokens[Index].IsSymbol('=') then
    begin
      Index := NextToken(ATokens, Index);
      if (Index >= 0) and (TInvertBoolean.NegateLiteral(ATokens[Index].Text) <> '') then
      begin
        Result := Index;
      end;
      Exit;
    end;
    Index := NextToken(ATokens, Index);
  end;
end;

/// <summary>Name der Routine im Kopf AHeader: letzter Bezeichner vor "(" bzw. "&lt;"; -1 ohne.</summary>
function RoutineNameToken(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  mIndex := TSyntaxTree.FirstTokenOf(ATokens, AHeader.StartOffset);
  while (mIndex <= High(ATokens)) and not ATokens[mIndex].IsSymbol('(') and not ATokens[mIndex].IsSymbol('<') do
  begin
    if (ATokens[mIndex].Offset >= AHeader.StartOffset) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Stelle des Routinennamens zum Parameter ASymbol in AOrigin; Fail ohne Routine.</summary>
function ParameterRoutine(AOrigin: TSourceFile; const ASymbol: TResolvedSymbol): TTextPosition;
var
  mTokens: TArray<TPascalToken>;
  mToken, mNameToken: Integer;
  mHeader: TSyntaxNode;
begin
  mTokens := AOrigin.Tree.Tokens;
  mToken := AOrigin.TokenAt(ASymbol.SelectionRange.StartPos);
  mHeader := nil;
  mNameToken := -1;
  if mToken >= 0 then
  begin
    mHeader := NodeAt(AOrigin.Tree, TSyntaxKind.RoutineHeader, mTokens[mToken].Offset);
  end;
  if mHeader <> nil then
  begin
    mNameToken := RoutineNameToken(mTokens, mHeader);
  end;
  if mNameToken < 0 then
  begin
    raise Fail(Format('Zum Parameter %s fehlt die Routine.', [ASymbol.Name]));
  end;
  Result := mTokens[mNameToken].StartPos;
end;

/// <summary>Stelle des Parameters ASymbol in der Familie: über seine Position im Kopf seiner Datei, sonst über
/// den Namen im ersten Kopf; -1 ohne.</summary>
function ParameterIndex(const AFamily: TRoutineFamily; const ASymbol: TResolvedSymbol): Integer;
var
  mItem: TRoutineFamilyHeader;
  mIndex: Integer;
begin
  Result := -1;
  for mItem in AFamily.Headers do
  begin
    for mIndex := 0 to High(mItem.ParameterPos) do
    begin
      if SameText(mItem.FileName, ASymbol.FileName) and (mItem.ParameterPos[mIndex] = ASymbol.SelectionRange.StartPos)
      then
      begin
        Result := mIndex;
      end;
    end;
  end;
  if (Result >= 0) or (AFamily.Headers = nil) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AFamily.Headers[0].Parameters) do
  begin
    if SameText(AFamily.Headers[0].Parameters[mIndex].Name, ASymbol.Name) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Fail, wenn der Parameter AParameter der Familie nicht umkehrbar ist (Ereignis, var, out).</summary>
procedure CheckParameter(const AFamily: TRoutineFamily; AParameter: Integer; const ASymbol: TResolvedSymbol);
var
  mModifier: string;
begin
  if AFamily.BoundEvent <> '' then
  begin
    raise Fail(Format('%s ist an ein Ereignis gebunden (%s); seine Parameter liegen fest.', [AFamily.Name,
      AFamily.BoundEvent]));
  end;
  if AParameter < 0 then
  begin
    raise Fail(Format('Der Parameter %s steht nicht im Kopf von %s.', [ASymbol.Name, AFamily.Name]));
  end;
  mModifier := LowerCase(Trim(AFamily.Headers[0].Parameters[AParameter].Modifier));
  if EndsText('var', mModifier) or EndsText('out', mModifier) then
  begin
    raise Fail(Format('%s ist ein %s-Parameter: Der Aufrufer bekäme den umgekehrten Wert zurück.',
      [ASymbol.Name, mModifier]));
  end;
end;

/// <summary>Standardwert des Parameters an AToken umdrehen: Aufrufer ohne Argument behalten ihr Verhalten.
/// </summary>
procedure InvertDefault(AUnit: TSourceFile; AToken: Integer);
var
  mTokens: TArray<TPascalToken>;
  mLiteral: Integer;
begin
  mTokens := AUnit.Tree.Tokens;
  mLiteral := DefaultToken(mTokens, AToken);
  if mLiteral >= 0 then
  begin
    AUnit.Extra := AUnit.Extra + [TTextEdit.Create(TTextRange.Create(mTokens[mLiteral].StartPos,
      mTokens[mLiteral].EndPos), TInvertBoolean.NegateLiteral(mTokens[mLiteral].Text))];
  end;
end;

procedure TInvertPlan.AddParameterIn(const AItem: TRoutineFamilyHeader; AParameter: Integer;
  const ASymbol: TResolvedSymbol; const ANewName: string);
var
  mUnit: TSourceFile;
  mToken: Integer;
  mName, mNewName: string;
begin
  mUnit := Source(AItem.FileName);
  mToken := -1;
  if (mUnit <> nil) and (AParameter <= High(AItem.Parameters)) and (AItem.ParameterPos[AParameter].Line >= 0) then
  begin
    mToken := mUnit.TokenAt(AItem.ParameterPos[AParameter]);
  end;
  if mToken < 0 then
  begin
    Exit;
  end;
  mName := AItem.Parameters[AParameter].Name;
  mNewName := ANewName;
  if not SameText(mName, ASymbol.Name) then
  begin
    mNewName := Suggest(mName);
  end;
  mUnit.Targets.AddName(mUnit.Tree.Tokens[mToken].Offset, mNewName, True);
  if AItem.IsBody then
  begin
    mUnit.Targets.AddLocal(mUnit.Offset(AItem.NamePos), mName, mNewName);
  end;
  InvertDefault(mUnit, mToken);
end;

procedure TInvertPlan.AddParameter(const ASymbol: TResolvedSymbol; const ANewName: string);
var
  mOrigin, mUnit: TSourceFile;
  mParameter: Integer;
  mFamily: TRoutineFamily;
  mItem: TRoutineFamilyHeader;
  mCall: TRoutineFamilyCall;
begin
  mOrigin := ReadableSource(ASymbol.FileName);
  mFamily := TLspChangeSignature.Family(FResolver, FContext.Index, mOrigin.Tree, ASymbol.FileName,
    ParameterRoutine(mOrigin, ASymbol), FContext.Files, FContext.ReadText, nil);
  mParameter := -1;
  if mFamily.BoundEvent = '' then
  begin
    mParameter := ParameterIndex(mFamily, ASymbol);
  end;
  CheckParameter(mFamily, mParameter, ASymbol);
  for mItem in mFamily.Headers do
  begin
    AddParameterIn(mItem, mParameter, ASymbol, ANewName);
  end;
  for mCall in mFamily.Calls do
  begin
    mUnit := Source(mCall.FileName);
    if mUnit <> nil then
    begin
      mUnit.Targets.AddCall(mUnit.Offset(mCall.NamePos), mParameter);
    end;
  end;
  WarnAll(mFamily.Warnings);
end;

/// <summary>Klauseln der Property ADecl ab dem Namen ANameToken.</summary>
function PropertyClauses(const ATokens: TArray<TPascalToken>; ADecl: TSyntaxNode; ANameToken: Integer):
  TPropertyClauses;
var
  mIndex, mNext: Integer;
begin
  Result.Reader := -1;
  Result.Writer := -1;
  Result.Default_ := -1;
  mIndex := ANameToken + 1;
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ADecl.EndOffset) do
  begin
    mNext := NextToken(ATokens, mIndex);
    if (mNext >= 0) and (ATokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
    begin
      case IndexText(ATokens[mIndex].Text, ['read', 'write', 'default']) of
        0:
          Result.Reader := mNext;
        1:
          Result.Writer := mNext;
        2:
          Result.Default_ := mNext;
      end;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Token des Namens der Property ASymbol und ihre Deklaration; Fail ohne.</summary>
function PropertyDecl(AUnit: TSourceFile; const ASymbol: TResolvedSymbol; out AToken: Integer): TSyntaxNode;
begin
  Result := nil;
  AToken := AUnit.TokenAt(ASymbol.SelectionRange.StartPos);
  if AToken >= 0 then
  begin
    Result := NodeAt(AUnit.Tree, TSyntaxKind.PropertyDecl, AUnit.Tree.Tokens[AToken].Offset);
  end;
  if Result = nil then
  begin
    raise Fail(Format('Die Deklaration von %s fehlt.', [ASymbol.Name]));
  end;
end;

/// <summary>Literal hinter default umdrehen.</summary>
procedure InvertPropertyDefault(AUnit: TSourceFile; ADefault: Integer);
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := AUnit.Tree.Tokens;
  if (ADefault >= 0) and (TInvertBoolean.NegateLiteral(mTokens[ADefault].Text) <> '') then
  begin
    AUnit.Extra := AUnit.Extra + [TTextEdit.Create(TTextRange.Create(mTokens[ADefault].StartPos,
      mTokens[ADefault].EndPos), TInvertBoolean.NegateLiteral(mTokens[ADefault].Text))];
  end;
end;

procedure TInvertPlan.AddReader(AUnit: TSourceFile; const AContainer: string; AReader: Integer);
var
  mAccessor: TResolvedSymbol;
  mTokens: TArray<TPascalToken>;
begin
  mTokens := AUnit.Tree.Tokens;
  if (AReader < 0) or not Member(AUnit.FileName, AContainer, mTokens[AReader].Text, mAccessor) then
  begin
    Exit;
  end;
  if mAccessor.SymbolKind = TIndexSymbolKind.Field then
  begin
    AddVariable(mAccessor, Suggest(mAccessor.Name), False);
  end
  else
  begin
    AddFunction(mAccessor.FileName, mAccessor.SelectionRange.StartPos, Suggest(mAccessor.Name), False);
  end;
  AUnit.Targets.AddName(mTokens[AReader].Offset, Suggest(mAccessor.Name), True);
end;

procedure TInvertPlan.AddWriter(AUnit: TSourceFile; const AContainer: string; const AClauses: TPropertyClauses);
var
  mAccessor: TResolvedSymbol;
  mTokens: TArray<TPascalToken>;
begin
  mTokens := AUnit.Tree.Tokens;
  if (AClauses.Writer < 0) or not Member(AUnit.FileName, AContainer, mTokens[AClauses.Writer].Text, mAccessor) then
  begin
    Exit;
  end;
  if mAccessor.SymbolKind = TIndexSymbolKind.Method then
  begin
    AddSetter(mAccessor.FileName, mAccessor.SelectionRange.StartPos, Suggest(mAccessor.Name));
  end
  else if (AClauses.Reader < 0) or not SameText(mTokens[AClauses.Writer].Text, mTokens[AClauses.Reader].Text) then
  begin
    AddVariable(mAccessor, Suggest(mAccessor.Name), False);
  end;
  AUnit.Targets.AddName(mTokens[AClauses.Writer].Offset, Suggest(mAccessor.Name),
    mAccessor.SymbolKind <> TIndexSymbolKind.Method);
end;

procedure TInvertPlan.AddPublished(const ASymbol: TResolvedSymbol; const ANewName: string);
begin
  if FContext.IncludeDfm then
  begin
    AddForms(ASymbol.Container, ASymbol.Name, ANewName);
  end
  else
  begin
    Warn(Format('%s ist published: Formulare speichern noch %s (Formulare einbeziehen ist abgeschaltet).',
      [ASymbol.Name, ASymbol.Name]));
  end;
  Warn(Format('%s ist published: Formulare außerhalb des Projekts und gespeicherte Einstellungen behalten den ' +
    'alten Namen.', [ASymbol.Name]));
end;

procedure TInvertPlan.AddProperty(const ASymbol: TResolvedSymbol; const ANewName: string);
var
  mUnit: TSourceFile;
  mDecl: TSyntaxNode;
  mToken: Integer;
  mClauses: TPropertyClauses;
begin
  AddReferences(ASymbol.FileName, ASymbol.SelectionRange.StartPos, ANewName, True, False);
  mUnit := Source(ASymbol.FileName);
  mDecl := PropertyDecl(mUnit, ASymbol, mToken);
  mClauses := PropertyClauses(mUnit.Tree.Tokens, mDecl, mToken);
  InvertPropertyDefault(mUnit, mClauses.Default_);
  // Die Klauseln "read FX" und "write SetX" findet die Referenzsuche nicht; sie werden hier umbenannt.
  AddReader(mUnit, ASymbol.Container, mClauses.Reader);
  AddWriter(mUnit, ASymbol.Container, mClauses);
  if ASymbol.Visibility = TIndexVisibility.Published then
  begin
    AddPublished(ASymbol, ANewName);
  end;
end;

/// <summary>Die Klasse und alle Nachfahren: Formulare speichern Objekte unter ihrem eigenen Typ.</summary>
function ClassFamily(const AIndex: ISymbolIndex; const AClassName: string): TArray<string>;
var
  mQueue: TArray<string>;
  mCurrent: string;
  mLocation: TSymbolLocation;
begin
  Result := [AClassName];
  mQueue := [AClassName];
  while (mQueue <> nil) and (AIndex <> nil) do
  begin
    mCurrent := mQueue[0];
    Delete(mQueue, 0, 1);
    for mLocation in AIndex.Descendants(mCurrent) do
    begin
      if IndexText(mLocation.Symbol.Name, Result) < 0 then
      begin
        Result := Result + [mLocation.Symbol.Name];
        mQueue := mQueue + [mLocation.Symbol.Name];
      end;
    end;
  end;
end;

procedure TInvertPlan.AddForm(const AForm: string; const AClasses: TArray<string>; const AOld, ANew: string);
var
  mText: string;
  mEdits: TArray<TTextEdit>;
  mFound: TArray<TInvertWarning>;
  mWarning: TInvertWarning;
begin
  if FForms.ContainsKey(UpperCase(AForm)) or not Assigned(FContext.ReadText) or
    not FContext.ReadText(AForm, mText) or not ContainsText(mText, AOld) then
  begin
    Exit;
  end;
  if TFileEncoding.IsBinaryFormFile(AForm) then
  begin
    Warn(Format('%s ist binär gespeichert und bleibt; bitte in Textform umwandeln.', [ExtractFileName(AForm)]));
    Exit;
  end;
  mEdits := TInvertBoolean.DfmEdits(mText, AClasses, AOld, ANew, mFound);
  for mWarning in mFound do
  begin
    Warn(Format('%s, Zeile %d: %s', [ExtractFileName(AForm), mWarning.Position.Line + 1, mWarning.Text]));
  end;
  if mEdits <> nil then
  begin
    FForms.Add(UpperCase(AForm), mEdits);
    FormOrder.Add(AForm);
  end;
end;

procedure TInvertPlan.AddForms(const AClassName, AOld, ANew: string);
var
  mClasses: TArray<string>;
  mFileName, mExtension: string;
begin
  mClasses := ClassFamily(FContext.Index, AClassName);
  for mFileName in FContext.Files do
  begin
    for mExtension in FormExtensions do
    begin
      AddForm(ChangeFileExt(mFileName, mExtension), mClasses, AOld, ANew);
    end;
  end;
end;

function TInvertPlan.FormEdits(const AFileName: string): TArray<TTextEdit>;
begin
  Result := FForms[UpperCase(AFileName)];
end;

procedure TInvertPlan.CheckStrings(const AOld: string);
var
  FileName, Text: string;
  Tree: TSyntaxTree;
  Token: TPascalToken;
begin
  // Zeichenketten mit dem alten Namen: RTTI (GetPropValue, FindComponent, MethodAddress) findet ihn nicht mehr.
  for FileName in FContext.Files do
  begin
    if not Assigned(FContext.ReadText) or not FContext.ReadText(FileName, Text) or
      not ContainsText(Text, '''' + AOld + '''') then
    begin
      Continue;
    end;
    Tree := TSyntaxTreeCache.Parse(Text);
    try
      for Token in Tree.Tokens do
      begin
        if (Token.Kind = TPascalTokenKind.StringLiteral) and SameText(Token.Text, '''' + AOld + '''') then
        begin
          Warn(Format('%s: Zeichenkette %s (RTTI oder Streaming?) bleibt, bitte prüfen.',
            [Where(FileName, Token.StartPos), Token.Text]));
        end;
      end;
    finally
      Tree.Free;
    end;
  end;
end;

procedure TInvertPlan.Apply(const ASymbol: TResolvedSymbol; const ANewName: string);
begin
  if ASymbol.IsParameter then
  begin
    AddParameter(ASymbol, ANewName);
  end
  else
    case ASymbol.SymbolKind of
      TIndexSymbolKind.Property_:
        AddProperty(ASymbol, ANewName);
      TIndexSymbolKind.Method, TIndexSymbolKind.Routine:
        AddFunction(ASymbol.FileName, ASymbol.SelectionRange.StartPos, ANewName, True);
    else
      AddVariable(ASymbol, ANewName, True);
    end;
  if ASymbol.Kind <> TResolvedKind.Local then
  begin
    CheckStrings(ASymbol.Name);
  end;
end;

/// <summary>Fail, wenn AText mehr Syntaxfehler hat als AUnit vorher.</summary>
procedure CheckParses(AUnit: TSourceFile; const AText: string);
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    if Length(mTree.Diagnostics) > Length(AUnit.Tree.Diagnostics) then
    begin
      raise Fail(Format('Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).',
        [ExtractFileName(AUnit.FileName), mTree.Diagnostics[0].StartPos.Line + 1, mTree.Diagnostics[0].Message]));
    end;
  finally
    mTree.Free;
  end;
end;

function TInvertPlan.UnitEdits(const AFileName: string): TArray<TTextEdit>;
var
  mUnit: TSourceFile;
  mFound: TArray<TInvertWarning>;
  mItem: TInvertWarning;
begin
  mUnit := Source(AFileName);
  Result := mUnit.Extra;
  if not mUnit.Targets.IsEmpty then
  begin
    Result := Result + TInvertBoolean.Rewrite(mUnit.Tree, mUnit.Text, mUnit.Targets, mFound);
    for mItem in mFound do
    begin
      Warn(Format('%s: %s', [Where(AFileName, mItem.Position), mItem.Text]));
    end;
  end;
  if Result <> nil then
  begin
    CheckParses(mUnit, TChangeSignature.ApplyEdits(mUnit.Text, Result));
  end;
end;

function TInvertPlan.DocumentChanges(out APlaces, AFiles: Integer): TJSONArray;
var
  mName: string;
  mEdits: TArray<TTextEdit>;
begin
  APlaces := 0;
  AFiles := 0;
  Result := TJSONArray.Create;
  try
    for mName in Order do
    begin
      mEdits := UnitEdits(mName);
      if mEdits <> nil then
      begin
        Result.AddElement(EditsJson(TDocumentUris.FromPath(mName), mEdits));
        Inc(APlaces, Length(mEdits));
        Inc(AFiles);
      end;
    end;
    for mName in FormOrder do
    begin
      mEdits := FormEdits(mName);
      Result.AddElement(EditsJson(TDocumentUris.FromPath(mName), mEdits));
      Inc(APlaces, Length(mEdits));
      Inc(AFiles);
    end;
  except
    Result.Free;
    raise;
  end;
end;

/// <summary>Antwort von Execute: WorkspaceEdit mit Änderungsanmerkung, Warnungen und Zahlen.</summary>
function Answer(AChanges: TJSONArray; const ADescription: string; const AWarnings: TArray<string>;
  APlaces, AFiles: Integer): TJSONObject;
var
  mAnnotation, mAnnotations, mEdit: TJSONObject;
  mWarnings: TJSONArray;
  mWarning: string;
begin
  mAnnotation := TJSONObject.Create;
  mAnnotation.AddPair('label', 'Boolean umkehren');
  mAnnotation.AddPair('needsConfirmation', TJSONBool.Create(True));
  mAnnotation.AddPair('description', ADescription);
  mAnnotations := TJSONObject.Create;
  mAnnotations.AddPair(TLspInvertBoolean.AnnotationId, mAnnotation);
  mEdit := TJSONObject.Create;
  mEdit.AddPair('documentChanges', AChanges);
  mEdit.AddPair('changeAnnotations', mAnnotations);
  mWarnings := TJSONArray.Create;
  for mWarning in AWarnings do
  begin
    mWarnings.Add(mWarning);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('edit', mEdit);
  Result.AddPair('warnings', mWarnings);
  Result.AddPair('places', TJSONNumber.Create(APlaces));
  Result.AddPair('files', TJSONNumber.Create(AFiles));
end;

{ TLspInvertBoolean }

class function TLspInvertBoolean.Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string; const APosition: TTextPosition; const AContext: TInvertBooleanContext): TJSONObject;
var
  mSymbol: TResolvedSymbol;
  mPlan: TInvertPlan;
  mChanges: TJSONArray;
  mPlaces, mFiles: Integer;
  mWarnings: TArray<string>;
begin
  if not TLspRename.IsValidName(AContext.NewName) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('"%s" ist kein gültiger Bezeichner.',
      [AContext.NewName]));
  end;
  if not Target(AResolver, ATree, AFileName, APosition, AContext.Files, mSymbol) then
  begin
    raise Fail('Hier steht kein Boolean des Projekts.');
  end;
  if SameText(AContext.NewName, mSymbol.Name) then
  begin
    raise Fail('Der neue Name ist der alte.');
  end;
  mPlan := TInvertPlan.Create(AResolver, ATree, AFileName, AText, AContext);
  try
    mPlan.Apply(mSymbol, AContext.NewName);
    mChanges := mPlan.DocumentChanges(mPlaces, mFiles);
    mWarnings := mPlan.Warnings;
  finally
    mPlan.Free;
  end;
  Result := Answer(mChanges, Format('%s → %s: %d Stellen in %d Dateien', [mSymbol.Name, AContext.NewName, mPlaces,
    mFiles]), mWarnings, mPlaces, mFiles);
end;


end.
