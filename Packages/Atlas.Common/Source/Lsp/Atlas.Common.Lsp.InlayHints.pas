unit Atlas.Common.Lsp.InlayHints;

// Inlay Hints (textDocument/inlayHint):
//   - Parameternamen vor den Argumenten eines Aufrufs (über die Parameterhilfe, #32);
//     entfällt, wenn das Argument schon so heißt,
//   - abgeleiteter Typ hinter var X := …, const X = … und for var X in … (Literale, Konstruktoren, Funktionen,
//     Variablen, Elemente von Arrays und Enumeratoren; #453), dazu die Aktion „Typ ausschreiben“
//     (ExplicitTypeAction) mit uses-Eintrag für die Unit des Typs,
//   - Endmarkierungen hinter dem end langer Blöcke: Routine, Typ, if/while/for/with/case/try,
//   - hinter {$I datei.inc} die Symbole, die die Datei dort setzt und die eine Bedingung dieser Unit
//     prüft: „definiert COMPLIB_VCL“ (#860), aus dem Präprozessor-Lauf des gemeinsamen Baums,
//   - hinter Steuerzeichen wie ^C im Wert einer Konstanten ihr Code „#3“ (#862).
// Was erscheint, steuert "inlayHints" in atlas.json.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Lsp.Hover;

type
  TInlayHint = record
    Position: TTextPosition;
    Text: string;
    /// <summary>InlayHintKind des LSP: 1 Typ, 2 Parameter, 0 ohne.</summary>
    Kind: Integer;
    PaddingLeft: Boolean;
    PaddingRight: Boolean;
    /// <summary>Endmarke (#620): Anfang des Blocks, zu dem ein Klick springt; nur mit HasBlockStart.</summary>
    BlockStart: TTextPosition;
    HasBlockStart: Boolean;
    /// <summary>Hinweis hinter {$I} (#860): gesetzte Symbole und Name der Include-Datei; leer sonst.</summary>
    Defines: TArray<string>;
    IncludeFile: string;
    /// <summary>Code eines Steuerzeichens wie ^C (#862); nur mit ControlChar.</summary>
    CharCode: Integer;
    ControlChar: Boolean;
    /// <summary>Marke „braucht kein Self“ am Ende des Kopfs einer Methode (#686).</summary>
    MethodWithoutSelf: Boolean;
  end;

  /// <summary>Abgeleiteter Typ einer Inline-Variablen ohne Typangabe (#453).</summary>
  TInferredType = record
    Name: string;
    NameStart: TTextPosition;
    /// <summary>Ende des Namens: Stelle der Marke und von ": Typ".</summary>
    NameEnd: TTextPosition;
    /// <summary>Typ wie im Quelltext, z. B. "TList&lt;TKunde&gt;".</summary>
    TypeName: string;
    /// <summary>Laufvariable in for var X in ….</summary>
    ForIn: Boolean;
    /// <summary>Unit der Typdeklaration, wenn die Namensauflösung sie kennt; '' sonst.</summary>
    TypeUnit: string;
    /// <summary>Symbol, von dessen Unit aus TypeName gilt (Funktion, Feld, Enumerator); Name '' ohne.</summary>
    Origin: TResolvedSymbol;
  end;

  /// <summary>Woraus die Hinweise entstehen: Baum mit Text und Datei, Namensauflösung und Index.</summary>
  TInlayHintSource = record
    Resolver: TNameResolver;
    Index: ISymbolIndex;
    Tree: TSyntaxTree;
    /// <summary>Text, aus dem Tree gelesen wurde.</summary>
    TreeText: string;
    FileName: string;
    ReadText: THoverReadText;
    class function Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ATreeText, AFileName: string; const AReadText: THoverReadText): TInlayHintSource; overload; static;
    /// <summary>Ohne Index, Text und Dateizugriff (abgeleitete Typen).</summary>
    class function Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string): TInlayHintSource;
      overload; static;
  end;

  /// <summary>Einstellungen für das Dokument AUri.</summary>
  TInlayHintSettingsProvider = reference to function(const AUri: string): TInlayHintSettings;

  TLspInlayHints = class
  public const
    Method = 'textDocument/inlayHint';
    MaxLabelLength = 50;
    /// <summary>Längste Bedingung einer Endmarke (#620), danach „…“.</summary>
    MaxEndLabelLength = 40;
    /// <summary>Mindestlänge des Blocks aus der Anfrage (#620, editor.blockEndLabels.minLines im Plugin); geht
    /// inlayHints.endMarkerMinLines vor.</summary>
    MinLinesParam = 'atlas.endMarkerMinLines';
    /// <summary>Anfang der Beschriftung hinter {$I} (#860).</summary>
    DefinesPrefix = 'definiert ';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: THoverReadText;
    FSettings: TInlayHintSettingsProvider;
    FNamespaces: TArray<string>;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: THoverReadText;
      const ASettings: TInlayHintSettingsProvider; const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: THoverReadText;
      const ASettings: TInlayHintSettingsProvider); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    class function ParameterNames(const ASource: TInlayHintSource; const ARange: TTextRange): TArray<TInlayHint>;
      static;
    class function InferredTypes(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const ARange: TTextRange): TArray<TInlayHint>; static;
    /// <summary>Inline-Variablen, -Konstanten und for-in-Laufvariablen ohne Typangabe in ARange mit ihrem
    /// abgeleiteten Typ (#453).</summary>
    class function Inferred(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const ARange: TTextRange): TArray<TInferredType>; static;
    /// <summary>„Typ ausschreiben“ (#453) für die Inline-Variable, auf deren Namen APosition steht: fügt
    /// ": Typ" ein und trägt fehlende Units des Typs ins uses ein. False ohne Treffer.</summary>
    class function ExplicitTypeAction(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition; const ALineBreak: string; out AAction: TCodeAction): Boolean; static;
    class function EndMarkers(ATree: TSyntaxTree; const ARange: TTextRange; AMinLines: Integer): TArray<TInlayHint>; static;
    /// <summary>Hinter jedem {$I datei} in ARange die Symbole, die die Include-Datei setzt und die eine
    /// $IFDEF/$IF-Bedingung von ATree prüft (#860); AProcessed ist der Präprozessor-Lauf zum Baum.</summary>
    class function IncludeDefines(ATree: TSyntaxTree; const AProcessed: TPreprocessorResult;
      const ARange: TTextRange): TArray<TInlayHint>; static;
    /// <summary>Hinter jedem Steuerzeichen wie ^C im Wert einer Konstanten in ARange sein Code „#3“ (#862);
    /// ATreeText ist der Text, aus dem ATree gelesen wurde.</summary>
    class function ControlChars(ATree: TSyntaxTree; const ATreeText: string;
      const ARange: TTextRange): TArray<TInlayHint>; static;
    /// <summary>Hinter dem Kopf jeder Methode in ARange, die Self nicht braucht, die Marke „braucht kein Self“ (#686);
    /// Mitglieder, Interfaces und Formular über AResolver und AReadText.</summary>
    class function MethodMarkers(AResolver: TNameResolver; ATree: TSyntaxTree; const ATreeText, AFileName: string;
      const ARange: TTextRange; const AReadText: THoverReadText): TArray<TInlayHint>; static;
    /// <summary>Alle eingeschalteten Hinweise in ARange, nach Position sortiert.</summary>
    class function Collect(const ASource: TInlayHintSource; const ARange: TTextRange;
      const ASettings: TInlayHintSettings): TArray<TInlayHint>; overload; static;
    /// <summary>Wie oben, dazu die Symbole hinter {$I} aus dem Präprozessor-Lauf AProcessed (#860).</summary>
    class function Collect(const ASource: TInlayHintSource; const ARange: TTextRange;
      const ASettings: TInlayHintSettings; const AProcessed: TPreprocessorResult): TArray<TInlayHint>; overload;
      static;
    /// <summary>InlayHint[] des LSP. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AHints: TArray<TInlayHint>): TJSONArray; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  System.StrUtils,
  Atlas.Common.Editing.MethodWithoutSelf,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.MethodWithoutSelf,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.SignatureHelp,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Editing.PostfixTemplates,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Text.Chars;

type
  TSyntaxKinds = set of TSyntaxKind;

const
  KindType = 1;
  KindParameter = 2;
  ParameterModifiers: array[0..4] of string = ('const ', 'var ', 'out ', 'constref ', '[ref] ');

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
  begin
    Result := A.Line - B.Line;
  end
  else
  begin
    Result := A.Character - B.Character;
  end;
end;

function InRange(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := (ComparePositions(ARange.StartPos, APosition) <= 0) and (ComparePositions(APosition, ARange.EndPos) <= 0);
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
  begin
    Result := Copy(AText, 2, MaxInt);
  end
  else
  begin
    Result := AText;
  end;
end;

/// <summary>Index des ersten Tokens mit Offset >= AOffset.</summary>
function FirstTokenAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(ATokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if ATokens[Middle].Offset < AOffset then
    begin
      Low := Middle + 1;
    end
    else
    begin
      High := Middle;
    end;
  end;
  Result := Low;
end;

procedure CollectNodes(ANode: TSyntaxNode; const AKinds: TSyntaxKinds; AList: TList<TSyntaxNode>);
var
  Kinds: TSyntaxKinds;
  List: TList<TSyntaxNode>;
begin
  Kinds := AKinds;
  List := AList;
  // Walk statt Rekursion (Bericht M1).
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      if AChild.Kind in Kinds then
      begin
        List.Add(AChild);
      end;
      Result := True;
    end);
end;

/// <summary>Parametername aus "const A: Integer = 1" bzw. "A".</summary>
function ParameterName(const AText: string): string;
var
  Modifier: string;
  Colon: Integer;
begin
  Result := Trim(AText);
  for Modifier in ParameterModifiers do
  begin
    if StartsText(Modifier, Result) then
    begin
      Delete(Result, 1, Length(Modifier));
    end;
  end;
  Colon := Pos(':', Result);
  if Colon > 0 then
  begin
    Result := Copy(Result, 1, Colon - 1);
  end;
  Colon := Pos('=', Result);
  if Colon > 0 then
  begin
    Result := Copy(Result, 1, Colon - 1);
  end;
  Result := Trim(Result);
end;

/// <summary>True für ) ] , . ; : davor kein Leerzeichen.</summary>
function IsClosingSymbol(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(')') or AToken.IsSymbol(']') or AToken.IsSymbol(',') or AToken.IsSymbol('.') or
    AToken.IsSymbol(';');
end;

/// <summary>True für ( und [.</summary>
function IsOpeningSymbol(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol('(') or AToken.IsSymbol('[');
end;

/// <summary>Kopfzeile eines Blocks als Text, z. B. "if Assigned(FTheme)".</summary>
function HeaderText(const ATokens: TArray<TPascalToken>; AFirst, ALast, AMaxLength: Integer): string;
var
  mIndex: Integer;
  mToken: TPascalToken;
  mGlue, mAfterName: Boolean;
begin
  Result := '';
  mGlue := True;
  mAfterName := False;
  for mIndex := AFirst to ALast do
  begin
    mToken := ATokens[mIndex];
    if IsTrivia(mToken) then
    begin
      Continue;
    end;
    if mToken.IsKeyword('then') or mToken.IsKeyword('do') or mToken.IsKeyword('of') then
    begin
      Break;
    end;
    // Kein Leerzeichen nach ( [ . und vor ) ] , . ; sowie zwischen Name und Aufrufklammer.
    if not (mGlue or IsClosingSymbol(mToken) or mAfterName and IsOpeningSymbol(mToken)) then
    begin
      Result := Result + ' ';
    end;
    Result := Result + mToken.Text;
    mGlue := IsOpeningSymbol(mToken) or mToken.IsSymbol('.');
    mAfterName := mToken.Kind = TPascalTokenKind.Identifier;
    if Length(Result) > AMaxLength then
    begin
      Exit(TrimRight(Copy(Result, 1, AMaxLength)) + '…');
    end;
  end;
end;

/// <summary>Letztes Token der Kette ab AFirst (Name.Name.Name), höchstens bis ALimit.</summary>
function ChainEnd(const ATokens: TArray<TPascalToken>; AFirst, ALimit: Integer): Integer;
var
  mDot, mName: Integer;
begin
  Result := AFirst;
  mDot := NextToken(ATokens, Result);
  mName := NextToken(ATokens, mDot);
  while (mName <= ALimit) and ATokens[mDot].IsSymbol('.') and (ATokens[mName].Kind = TPascalTokenKind.Identifier) do
  begin
    Result := mName;
    mDot := NextToken(ATokens, Result);
    mName := NextToken(ATokens, mDot);
  end;
end;

/// <summary>True, wenn AOffset in einem der Blöcke liegt.</summary>
function InAnyBlock(ABlocks: TList<TSyntaxNode>; AOffset: Integer): Boolean;
var
  mBlock: TSyntaxNode;
begin
  for mBlock in ABlocks do
  begin
    if (mBlock.StartOffset <= AOffset) and (AOffset < mBlock.EndOffset) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Anfänge der Argumente hinter der Klammer AOpen bis zur passenden Klammer.</summary>
function ArgumentStarts(const ATokens: TArray<TPascalToken>; AOpen: Integer): TArray<Integer>;
var
  mScan, mDepth: Integer;
begin
  Result := nil;
  mDepth := 0;
  mScan := NextToken(ATokens, AOpen);
  if (mScan <= High(ATokens)) and not ATokens[mScan].IsSymbol(')') then
  begin
    Result := [mScan];
  end;
  while (mScan <= High(ATokens)) and (mDepth >= 0) and not ((mDepth = 0) and ATokens[mScan].IsSymbol(';')) do
  begin
    if IsOpeningSymbol(ATokens[mScan]) then
    begin
      Inc(mDepth);
    end
    else if ATokens[mScan].IsSymbol(')') or ATokens[mScan].IsSymbol(']') then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and ATokens[mScan].IsSymbol(',') then
    begin
      Result := Result + [NextToken(ATokens, mScan)];
    end;
    mScan := NextToken(ATokens, mScan);
  end;
end;

/// <summary>Erste Signatur mit mindestens ACount Parametern; Compiler-Routinen (Assigned(P), Inc(X) ...) haben
/// nichtssagende Parameternamen und zählen nicht (#880).</summary>
function ChooseSignature(const AHelp: TSignatureHelp; ACount: Integer; out ASignature: TSignature): Boolean;
var
  mIndex: Integer;
begin
  ASignature := Default(TSignature);
  if AHelp.Intrinsic then
  begin
    Exit(False);
  end;
  for mIndex := 0 to High(AHelp.Signatures) do
  begin
    if Length(AHelp.Signatures[mIndex].Parameters) >= ACount then
    begin
      ASignature := AHelp.Signatures[mIndex];
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>True, wenn das Argument ab AStart schon wie der Parameter AName heißt (auch Self.Name, FName, AName).
/// </summary>
function NamedLikeParameter(const ATokens: TArray<TPascalToken>; AStart: Integer; const AName: string): Boolean;
var
  mLast: Integer;
  mText: string;
begin
  mLast := ChainEnd(ATokens, AStart, High(ATokens));
  mText := CleanName(ATokens[mLast].Text);
  Result := (ATokens[mLast].Kind = TPascalTokenKind.Identifier) and (SameText(mText, AName) or
    SameText(mText, 'F' + AName) or SameText(mText, 'A' + AName));
end;

/// <summary>Name des Parameters AIndex der Signatur.</summary>
function SignatureParameter(const ASignature: TSignature; AIndex: Integer): string;
var
  mParameter: TSignatureParameter;
begin
  mParameter := ASignature.Parameters[AIndex];
  Result := ParameterName(Copy(ASignature.Text, mParameter.StartIndex + 1, mParameter.EndIndex - mParameter.StartIndex));
end;

/// <summary>Hinweise mit den Parameternamen der Signatur vor den Argumenten ab AStarts.</summary>
procedure AddArgumentHints(AList: TList<TInlayHint>; const ATokens: TArray<TPascalToken>;
  const AStarts: TArray<Integer>; const ASignature: TSignature);
var
  mArgument: Integer;
  mName: string;
  mHint: TInlayHint;
begin
  for mArgument := 0 to High(AStarts) do
  begin
    if AStarts[mArgument] > High(ATokens) then
    begin
      Continue;
    end;
    mName := SignatureParameter(ASignature, mArgument);
    if (mName = '') or NamedLikeParameter(ATokens, AStarts[mArgument], mName) then
    begin
      Continue;
    end;
    mHint := Default(TInlayHint);
    mHint.Position := ATokens[AStarts[mArgument]].StartPos;
    mHint.Text := mName + ':';
    mHint.Kind := KindParameter;
    mHint.PaddingRight := True;
    AList.Add(mHint);
  end;
end;

/// <summary>Klammer eines Aufrufs hinter dem Bezeichner AIndex in ARange; -1 ohne.</summary>
function CallOpen(const ATokens: TArray<TPascalToken>; AIndex: Integer; const ARange: TTextRange): Integer;
begin
  Result := -1;
  if ATokens[AIndex].Kind = TPascalTokenKind.Identifier then
  begin
    Result := NextToken(ATokens, AIndex);
  end;
  if (Result < 0) or (Result > High(ATokens)) or not ATokens[Result].IsSymbol('(') or
    not InRange(ARange, ATokens[Result].EndPos) then
  begin
    Result := -1;
  end;
end;

{ TInlayHintSource }

class function TInlayHintSource.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ATreeText, AFileName: string; const AReadText: THoverReadText): TInlayHintSource;
begin
  Result.Resolver := AResolver;
  Result.Index := AIndex;
  Result.Tree := ATree;
  Result.TreeText := ATreeText;
  Result.FileName := AFileName;
  Result.ReadText := AReadText;
end;

class function TInlayHintSource.Create(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TInlayHintSource;
begin
  Result := Create(AResolver, nil, ATree, '', AFileName, nil);
end;

/// <summary>Hinweise vor den Argumenten des Aufrufs mit der Klammer AOpen.</summary>
procedure AddCallHints(AList: TList<TInlayHint>; const ASource: TInlayHintSource; AOpen: Integer);
var
  mTokens: TArray<TPascalToken>;
  mStarts: TArray<Integer>;
  mSignature: TSignature;
begin
  mTokens := ASource.Tree.Tokens;
  mStarts := ArgumentStarts(mTokens, AOpen);
  if (mStarts <> nil) and ChooseSignature(TLspSignatureHelp.HelpAt(
    TSignatureHelpRequest.Create(ASource.Resolver, ASource.Index, ASource.Tree, ASource.TreeText, ASource.FileName,
    ASource.ReadText), mTokens[AOpen].EndPos), Length(mStarts), mSignature) then
  begin
    AddArgumentHints(AList, mTokens, mStarts, mSignature);
  end;
end;

{ TLspInlayHints }

function TLspInlayHints.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspInlayHints.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspInlayHints.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: THoverReadText; const ASettings: TInlayHintSettingsProvider);
begin
  Create(AStore, AIndex, AReadText, ASettings, nil);
end;

constructor TLspInlayHints.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: THoverReadText; const ASettings: TInlayHintSettingsProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FSettings := ASettings;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspInlayHints.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
end;

class function TLspInlayHints.ParameterNames(const ASource: TInlayHintSource;
  const ARange: TTextRange): TArray<TInlayHint>;
var
  mTokens: TArray<TPascalToken>;
  mBlocks: TList<TSyntaxNode>;
  mIndex, mOpen: Integer;
  mList: TList<TInlayHint>;
begin
  mTokens := ASource.Tree.Tokens;
  mBlocks := TList<TSyntaxNode>.Create;
  mList := TList<TInlayHint>.Create;
  try
    // Nur Anweisungen: Köpfe von Routinen haben auch Bezeichner vor "(".
    CollectNodes(ASource.Tree.Root, [TSyntaxKind.Block], mBlocks);
    for mIndex := 0 to High(mTokens) - 1 do
    begin
      mOpen := CallOpen(mTokens, mIndex, ARange);
      if (mOpen >= 0) and InAnyBlock(mBlocks, mTokens[mIndex].Offset) then
      begin
        AddCallHints(mList, ASource, mOpen);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mBlocks.Free;
  end;
end;

/// <summary>Typ wie im Quelltext: eingebaut mit Namen, generisch mit eingesetzten Typargumenten ohne Unit.</summary>
function TypeDisplay(AResolver: TNameResolver; const AType: TResolvedSymbol): string;
var
  Binding: string;
  Values: TArray<string>;
begin
  Result := AType.Name;
  if Length(AType.Bindings) = 0 then
  begin
    Exit;
  end;
  Values := nil;
  for Binding in AType.Bindings do
  begin
    Values := Values + [AResolver.Queries.UnqualifyType(Copy(Binding, Pos('=', Binding) + 1, MaxInt))];
  end;
  Result := Result + '<' + string.Join(', ', Values) + '>';
end;

/// <summary>Typtext mit eingesetzten Bindungen ("T" wird zu "TKunde"), ohne Unit davor.</summary>
function BoundText(AResolver: TNameResolver; const AText: string; const ABindings: TArray<string>): string;
var
  Binding: string;
  Unqualified: TArray<string>;
begin
  Unqualified := nil;
  for Binding in ABindings do
  begin
    Unqualified := Unqualified + [Copy(Binding, 1, Pos('=', Binding)) +
      AResolver.Queries.UnqualifyType(Copy(Binding, Pos('=', Binding) + 1, MaxInt))];
  end;
  Result := TInterfaceStubs.SubstituteWords(AText, Unqualified);
end;

/// <summary>Namen der Kette A.B.C von AFirst bis ALast; False, wenn dort etwas anderes steht (z. B. ein Aufruf).
/// </summary>
function ChainNames(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer; out ANames: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  ANames := nil;
  mIndex := AFirst;
  Result := AFirst <= ALast;
  while Result and (mIndex <= ALast) do
  begin
    Result := ATokens[mIndex].Kind = TPascalTokenKind.Identifier;
    ANames := ANames + [CleanName(ATokens[mIndex].Text)];
    mIndex := NextToken(ATokens, mIndex);
    if Result and (mIndex <= ALast) then
    begin
      Result := ATokens[mIndex].IsSymbol('.');
      mIndex := NextToken(ATokens, mIndex);
    end;
  end;
end;

/// <summary>Elementtyp eines Arrays oder Strings aus dem Typ der Kette; '' wenn er keiner ist.</summary>
function DirectElement(const AOwner, ATypeInfo: TResolvedSymbol; ATypeFound: Boolean): string;
var
  mOwnerType: string;
begin
  mOwnerType := AOwner.TypeName;
  if AOwner.TypeArgs <> '' then
  begin
    mOwnerType := mOwnerType + '<' + AOwner.TypeArgs + '>';
  end;
  Result := TPostfixTemplates.ElementOf(mOwnerType);
  if (Result = '') and ATypeFound then
  begin
    Result := TPostfixTemplates.ElementOf(ATypeInfo.TypeName);
  end;
  if (Result = '') and (TPostfixTemplates.IsStringType(AOwner.TypeName) or
    (ATypeFound and ATypeInfo.Builtin and TPostfixTemplates.IsStringType(ATypeInfo.Name))) then
  begin
    Result := 'Char';
  end;
end;

/// <summary>Enumerator: Current von GetEnumerator, mit eingesetzten Typparametern; '' ohne.</summary>
function EnumeratorElement(const ASource: TInlayHintSource; const ANames: TArray<string>; AOffset: Integer;
  var AOrigin: TResolvedSymbol): string;
var
  mMember: TResolvedSymbol;
begin
  Result := '';
  for mMember in ASource.Resolver.Candidates.MemberCandidates(ASource.Tree, ASource.FileName, ANames + ['GetEnumerator'],
    AOffset) do
  begin
    if SameText(mMember.Name, 'Current') and (mMember.TypeName <> '') then
    begin
      AOrigin := mMember;
      Exit(BoundText(ASource.Resolver, mMember.TypeName, mMember.Bindings));
    end;
  end;
end;

/// <summary>Elementtyp für "for var X in Ausdruck" (#453): Kette A.B.C von AFirst bis ALast; Array-Typen, string
/// und GetEnumerator.Current.</summary>
function ForInElement(const ASource: TInlayHintSource; AFirst, ALast: Integer; out AOrigin: TResolvedSymbol): string;
var
  mTokens: TArray<TPascalToken>;
  mNames: TArray<string>;
  mChain: TResolvedChainType;
begin
  Result := '';
  AOrigin := Default(TResolvedSymbol);
  mTokens := ASource.Tree.Tokens;
  // Nur eine Kette A.B.C ohne Aufruf.
  if not ChainNames(mTokens, AFirst, ALast, mNames) or not ASource.Resolver.ChainType(ASource.Tree, ASource.FileName,
    mNames, mTokens[ALast].Offset, mChain) then
  begin
    Exit;
  end;
  AOrigin := mChain.Owner;
  Result := DirectElement(mChain.Owner, mChain.TypeInfo, mChain.TypeFound);
  if (Result = '') and mChain.TypeFound and not mChain.TypeInfo.Builtin then
  begin
    Result := EnumeratorElement(ASource, mNames, mTokens[ALast].Offset, AOrigin);
  end;
end;

/// <summary>Trägt Name und Stelle des Tokens ANameToken in AFound ein.</summary>
procedure SetFoundName(var AFound: TInferredType; const AToken: TPascalToken);
begin
  AFound.NameStart := AToken.StartPos;
  AFound.NameEnd := AToken.EndPos;
  AFound.Name := CleanName(AToken.Text);
end;

/// <summary>for var X in Ausdruck do: "var", Name, dann "in" ohne ":" dazwischen.</summary>
function InferForIn(const ASource: TInlayHintSource; ANode: TSyntaxNode; var AFound: TInferredType): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mNameToken, mFirst, mLast: Integer;
begin
  mTokens := ASource.Tree.Tokens;
  mIndex := FirstTokenAt(mTokens, ANode.StartOffset);
  if (mIndex + 3 > High(mTokens)) or not mTokens[mIndex].IsKeyword('for') or
    not mTokens[NextToken(mTokens, mIndex)].IsKeyword('var') then
  begin
    Exit(False);
  end;
  mNameToken := NextToken(mTokens, NextToken(mTokens, mIndex));
  mFirst := NextToken(mTokens, mNameToken);
  if (mFirst > High(mTokens)) or not mTokens[mFirst].IsKeyword('in') or (NextToken(mTokens, mFirst) > High(mTokens))
  then
  begin
    Exit(False);
  end;
  mFirst := NextToken(mTokens, mFirst);
  mLast := mFirst;
  while (NextToken(mTokens, mLast) <= High(mTokens)) and not mTokens[NextToken(mTokens, mLast)].IsKeyword('do') and
    (mTokens[NextToken(mTokens, mLast)].Offset < ANode.EndOffset) do
  begin
    mLast := NextToken(mTokens, mLast);
  end;
  SetFoundName(AFound, mTokens[mNameToken]);
  AFound.ForIn := True;
  AFound.TypeName := ForInElement(ASource, mFirst, mLast, AFound.Origin);
  Result := AFound.TypeName <> '';
end;

/// <summary>var X := …: Name, dann ":=" ohne ":" davor; const X = … mit "=". False ohne Zuweisung oder mit
/// Typangabe.</summary>
function FindAssignment(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode;
  out ANameToken, AAssign: Integer): Boolean;
var
  mIndex: Integer;
  mTyped: Boolean;
begin
  ANameToken := -1;
  AAssign := -1;
  mTyped := False;
  mIndex := FirstTokenAt(ATokens, ANode.StartOffset);
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ANode.EndOffset) and (AAssign < 0) do
  begin
    if (ANameToken < 0) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) then
    begin
      ANameToken := mIndex;
    end
    else if ATokens[mIndex].IsSymbol(':') then
    begin
      mTyped := True;
    end
    else if ATokens[mIndex].IsSymbol(':=') or ((ANode.Kind = TSyntaxKind.InlineConst) and
      ATokens[mIndex].IsSymbol('=')) then
    begin
      AAssign := mIndex;
    end;
    Inc(mIndex);
  end;
  Result := not mTyped and (ANameToken >= 0) and (AAssign >= 0);
end;

/// <summary>Typ eines einzelnen Literals (Zahl, String, Zeichen, True/False); '' sonst.</summary>
function LiteralType(const AToken: TPascalToken): string;
begin
  case AToken.Kind of
    TPascalTokenKind.Number:
      if CharInSet(AToken.Text[1], ['$', '%']) or ((Pos('.', AToken.Text) = 0) and
        (Pos('e', LowerCase(AToken.Text)) = 0)) then
      begin
        Result := 'Integer';
      end
      else
      begin
        Result := 'Extended';
      end;
    TPascalTokenKind.StringLiteral:
      if (Length(AToken.Text) = 3) or (AToken.Text = '''''''''') then
      begin
        Result := 'Char';
      end
      else
      begin
        Result := 'string';
      end;
    TPascalTokenKind.CharLiteral:
      Result := 'Char';
    TPascalTokenKind.Identifier:
      if SameText(AToken.Text, 'True') or SameText(AToken.Text, 'False') then
      begin
        Result := 'Boolean';
      end
      else
      begin
        Result := '';
      end;
  else
    // Andere Token haben keinen Literaltyp.
    Result := '';
  end;
end;

/// <summary>Typ der Variablen ANameToken über die Namensauflösung (#453): auch generisch, TList&lt;TKunde&gt;.Create.
/// </summary>
function ResolvedVariableType(const ASource: TInlayHintSource; ANameToken, AEndOffset: Integer;
  var AFound: TInferredType): Boolean;
var
  mChain: TResolvedChainType;
begin
  Result := ASource.Resolver.ChainType(ASource.Tree, ASource.FileName,
    [CleanName(ASource.Tree.Tokens[ANameToken].Text)], AEndOffset, mChain) and mChain.TypeFound and
    (mChain.TypeInfo.Name <> '');
  if not Result then
  begin
    Exit;
  end;
  AFound.TypeName := TypeDisplay(ASource.Resolver, mChain.TypeInfo);
  if not mChain.TypeInfo.Builtin then
  begin
    AFound.TypeUnit := mChain.TypeInfo.UnitName;
  end;
  AFound.Origin := mChain.TypeInfo;
end;

/// <summary>Index der schließenden Klammer zu der hinter AIndex (bis ALast); AIndex, wenn keine folgt.</summary>
function CallEnd(const ATokens: TArray<TPascalToken>; AIndex, ALast: Integer): Integer;
var
  mDepth: Integer;
begin
  Result := AIndex;
  if (Result >= ALast) or not ATokens[NextToken(ATokens, Result)].IsSymbol('(') then
  begin
    Exit;
  end;
  mDepth := 0;
  Result := NextToken(ATokens, Result);
  while Result <= ALast do
  begin
    if ATokens[Result].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol(')') then
    begin
      Dec(mDepth);
    end;
    if mDepth = 0 then
    begin
      Exit;
    end;
    Result := NextToken(ATokens, Result);
  end;
end;

/// <summary>Typ, den ein Ausdruck aus dem aufgelösten Symbol AResolved hat; '' wenn unbekannt.</summary>
function SymbolType(AResolver: TNameResolver; const AResolved: TResolvedSymbol): string;
begin
  Result := '';
  if AResolved.SymbolKind = TIndexSymbolKind.Constructor_ then
  begin
    Result := AResolved.Container;
  end
  else if AResolved.IsType then
  begin
    // Typumwandlung TFoo(X)
    Result := AResolved.Name;
  end
  else if AResolved.TypeName <> '' then
  begin
    Result := BoundText(AResolver, AResolved.TypeName, AResolved.Bindings);
  end
  else if AResolved.SymbolKind = TIndexSymbolKind.EnumMember then
  begin
    // Enum-Werte stehen im Index unter ihrem Typ.
    Result := AResolved.Container;
  end;
end;

/// <summary>Typ des Ausdrucks von AFirst bis ALast: Kette A.B.C, optional mit einem Aufruf (…) am Ende.</summary>
function ExpressionType(const ASource: TInlayHintSource; AFirst, ALast: Integer; var AFound: TInferredType): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mScan: Integer;
  mResolved: TResolvedSymbol;
begin
  mTokens := ASource.Tree.Tokens;
  Result := False;
  if mTokens[AFirst].Kind <> TPascalTokenKind.Identifier then
  begin
    Exit;
  end;
  mScan := ChainEnd(mTokens, AFirst, ALast);
  if CallEnd(mTokens, mScan, ALast) <> ALast then
  begin
    Exit;
  end;
  mResolved := ASource.Resolver.Resolve(ASource.Tree, ASource.FileName, mTokens[mScan].StartPos);
  if mResolved.Found and (mResolved.Kind <> TResolvedKind.UnitName) then
  begin
    AFound.Origin := mResolved;
    AFound.TypeName := SymbolType(ASource.Resolver, mResolved);
    Result := AFound.TypeName <> '';
  end;
end;

/// <summary>Inline-Variable oder -Konstante ohne Typangabe: Typ aus Literal, Namensauflösung oder Ausdruck.
/// </summary>
function InferInline(const ASource: TInlayHintSource; ANode: TSyntaxNode; var AFound: TInferredType): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mNameToken, mAssign, mFirst, mLast: Integer;
begin
  mTokens := ASource.Tree.Tokens;
  if not FindAssignment(mTokens, ANode, mNameToken, mAssign) then
  begin
    Exit(False);
  end;
  mFirst := NextToken(mTokens, mAssign);
  if mFirst > High(mTokens) then
  begin
    Exit(False);
  end;
  mLast := mFirst;
  while (NextToken(mTokens, mLast) <= High(mTokens)) and (mTokens[NextToken(mTokens, mLast)].Offset < ANode.EndOffset)
    and not mTokens[NextToken(mTokens, mLast)].IsSymbol(';') do
  begin
    mLast := NextToken(mTokens, mLast);
  end;
  SetFoundName(AFound, mTokens[mNameToken]);
  if mFirst = mLast then
  begin
    AFound.TypeName := LiteralType(mTokens[mFirst]);
  end;
  Result := (AFound.TypeName <> '') or ResolvedVariableType(ASource, mNameToken, ANode.EndOffset, AFound) or
    ExpressionType(ASource, mFirst, mLast, AFound);
end;

class function TLspInlayHints.Inferred(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const ARange: TTextRange): TArray<TInferredType>;
var
  mSource: TInlayHintSource;
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mFound: TInferredType;
  mList: TList<TInferredType>;
  mOk: Boolean;
begin
  mSource := TInlayHintSource.Create(AResolver, ATree, AFileName);
  mNodes := TList<TSyntaxNode>.Create;
  mList := TList<TInferredType>.Create;
  try
    CollectNodes(ATree.Root, [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.ForInStatement], mNodes);
    for mNode in mNodes do
    begin
      if not InRange(ARange, mNode.StartPos) or (Pos(',', mNode.Name) > 0) then
      begin
        Continue;
      end;
      mFound := Default(TInferredType);
      if mNode.Kind = TSyntaxKind.ForInStatement then
      begin
        mOk := InferForIn(mSource, mNode, mFound);
      end
      else
      begin
        mOk := InferInline(mSource, mNode, mFound);
      end;
      if mOk then
      begin
        mList.Add(mFound);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mNodes.Free;
  end;
end;

class function TLspInlayHints.InferredTypes(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const ARange: TTextRange): TArray<TInlayHint>;
var
  Found: TInferredType;
  Hint: TInlayHint;
  List: TList<TInlayHint>;
begin
  List := TList<TInlayHint>.Create;
  try
    for Found in Inferred(AResolver, ATree, AFileName, ARange) do
    begin
      Hint := Default(TInlayHint);
      Hint.Position := Found.NameEnd;
      Hint.Text := ': ' + Found.TypeName;
      Hint.Kind := KindType;
      List.Add(Hint);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

/// <summary>Abgeleiteter Typ der Inline-Variablen, auf deren Namen APosition steht.</summary>
function InferredAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; out AFound: TInferredType): Boolean;
var
  mCandidate: TInferredType;
begin
  AFound := Default(TInferredType);
  for mCandidate in TLspInlayHints.Inferred(AResolver, ATree, AFileName, TTextRange.Create(APosition.Line, 0,
    APosition.Line, MaxInt)) do
  begin
    if (mCandidate.NameStart.Line = APosition.Line) and (mCandidate.NameStart.Character <= APosition.Character) and
      (APosition.Character <= mCandidate.NameEnd.Character) then
    begin
      AFound := mCandidate;
      Exit(True);
    end;
  end;
  Result := False;
end;

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

/// <summary>Offset des Tokens, das bei APosition beginnt; 0 ohne.</summary>
function OffsetAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mToken: TPascalToken;
begin
  for mToken in ATokens do
  begin
    if (mToken.StartPos.Line = APosition.Line) and (mToken.StartPos.Character = APosition.Character) then
    begin
      Exit(mToken.Offset);
    end;
  end;
  Result := 0;
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
      TUsesClauses.IsUsed(AUnits.Used, mUnitName, AUnits.Resolver.Namespaces) or (IndexText(mUnitName, mAdded) >= 0)
    then
    begin
      Continue;
    end;
    if TUsesClauses.AddUnit(AUnits.Tokens, AUnits.Offset, mUnitName, ALineBreak, mEdit) then
    begin
      Result := Result + [mEdit];
      mAdded := mAdded + [mUnitName];
    end;
  end;
end;

class function TLspInlayHints.ExplicitTypeAction(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; const ALineBreak: string;
  out AAction: TCodeAction): Boolean;
var
  mUnits: TTypeUnits;
begin
  AAction := Default(TCodeAction);
  mUnits := Default(TTypeUnits);
  Result := (ATree <> nil) and (ATree.Root <> nil) and InferredAt(AResolver, ATree, AFileName, APosition,
    mUnits.Found);
  if not Result then
  begin
    Exit;
  end;
  AAction.Title := 'Typ ausschreiben';
  AAction.Kind := RewriteKind;
  AAction.Edits := [TTextEdit.Create(TTextRange.Create(mUnits.Found.NameEnd, mUnits.Found.NameEnd),
    ': ' + mUnits.Found.TypeName)];
  mUnits.Resolver := AResolver;
  mUnits.Tokens := ATree.Tokens;
  mUnits.Offset := OffsetAt(mUnits.Tokens, mUnits.Found.NameStart);
  mUnits.Own := AResolver.ExtractedUnit(ATree, AFileName);
  mUnits.OwnName := TUsesClauses.OwnName(mUnits.Tokens);
  mUnits.Used := TUsesClauses.UsedUnits(mUnits.Tokens);
  mUnits.Base := mUnits.Found.TypeName;
  if Pos('<', mUnits.Base) > 0 then
  begin
    mUnits.Base := Copy(mUnits.Base, 1, Pos('<', mUnits.Base) - 1);
  end;
  AAction.Edits := AAction.Edits + TypeUnitEdits(mUnits, ALineBreak);
end;

/// <summary>Token "end" am Ende von ANode (bei Routinen das des Rumpfs); -1 ohne.</summary>
function BlockEndToken(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Integer;
var
  mBody: TSyntaxNode;
begin
  mBody := ANode;
  if ANode.Kind = TSyntaxKind.RoutineDecl then
  begin
    mBody := ANode.FindChild(TSyntaxKind.Block);
  end;
  if mBody = nil then
  begin
    Exit(-1);
  end;
  Result := FirstTokenAt(ATokens, mBody.EndOffset) - 1;
  while (Result >= 0) and (IsTrivia(ATokens[Result]) or ATokens[Result].IsSymbol(';')) do
  begin
    Dec(Result);
  end;
  if (Result >= 0) and not ATokens[Result].IsKeyword('end') then
  begin
    Result := -1;
  end;
end;

/// <summary>Woran ein try-Block endet: try (finally) bzw. try (except).</summary>
function TryLabel(ANode: TSyntaxNode): string;
begin
  if ANode.FindChild(TSyntaxKind.FinallyBlock) <> nil then
  begin
    Result := 'try (finally)';
  end
  else if ANode.FindChild(TSyntaxKind.ExceptBlock) <> nil then
  begin
    Result := 'try (except)';
  end
  else
  begin
    Result := 'try';
  end;
end;

/// <summary>Beschriftung der Endmarke von ANode, dessen end bei AEndToken steht.</summary>
function EndLabel(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode; AEndToken: Integer): string;
begin
  case ANode.Kind of
    TSyntaxKind.RoutineDecl, TSyntaxKind.TypeDecl:
      Result := ANode.Name;
    TSyntaxKind.TryStatement:
      Result := TryLabel(ANode);
  else
    Result := HeaderText(ATokens, FirstTokenAt(ATokens, ANode.StartOffset), AEndToken,
      TLspInlayHints.MaxEndLabelLength);
  end;
end;

/// <summary>Endmarke für ANode in ARange; False, wenn keine hingehört.</summary>
function TryEndMarker(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode; const ARange: TTextRange;
  out AHint: TInlayHint): Boolean;
var
  mEndToken, mNext: Integer;
  mText: string;
begin
  AHint := Default(TInlayHint);
  mEndToken := BlockEndToken(ATokens, ANode);
  if mEndToken < 0 then
  begin
    Exit(False);
  end;
  mText := EndLabel(ATokens, ANode, mEndToken);
  AHint.Position := ATokens[mEndToken].EndPos;
  mNext := NextToken(ATokens, mEndToken);
  if (mNext <= High(ATokens)) and (ATokens[mNext].IsSymbol(';') or ATokens[mNext].IsSymbol('.')) and
    (ATokens[mNext].StartPos.Line = ATokens[mEndToken].EndPos.Line) then
  begin
    AHint.Position := ATokens[mNext].EndPos;
    mEndToken := mNext;
  end;
  // Steht hinter dem end schon ein Kommentar, sagt der genug.
  mNext := mEndToken + 1;
  Result := (mText <> '') and InRange(ARange, AHint.Position) and not ((mNext <= High(ATokens)) and
    (ATokens[mNext].Kind = TPascalTokenKind.Comment) and (ATokens[mNext].StartPos.Line = AHint.Position.Line));
  AHint.Text := '// ' + mText;
  AHint.PaddingLeft := True;
  AHint.BlockStart := ANode.StartPos;
  AHint.HasBlockStart := True;
end;

class function TLspInlayHints.EndMarkers(ATree: TSyntaxTree; const ARange: TTextRange;
  AMinLines: Integer): TArray<TInlayHint>;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mHint: TInlayHint;
  mList: TList<TInlayHint>;
begin
  mNodes := TList<TSyntaxNode>.Create;
  mList := TList<TInlayHint>.Create;
  try
    CollectNodes(ATree.Root, [TSyntaxKind.RoutineDecl, TSyntaxKind.TypeDecl, TSyntaxKind.IfStatement,
      TSyntaxKind.WhileStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WithStatement,
      TSyntaxKind.CaseStatement, TSyntaxKind.TryStatement], mNodes);
    for mNode in mNodes do
    begin
      if (mNode.EndPos.Line - mNode.StartPos.Line + 1 >= AMinLines) and TryEndMarker(ATree.Tokens, mNode, ARange,
        mHint) then
      begin
        mList.Add(mHint);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mNodes.Free;
  end;
end;

/// <summary>Text einer Direktive hinter {$ bzw. (*$, groß geschrieben; False bei anderen Token.</summary>
function DirectiveBody(const AToken: TPascalToken; out AText: string): Boolean;
begin
  AText := UpperCase(AToken.Text);
  Result := AToken.Kind = TPascalTokenKind.Directive;
  if Result and AText.StartsWith('{$') then
  begin
    AText := Copy(AText, 3, MaxInt);
  end
  else if Result and AText.StartsWith('(*$') then
  begin
    AText := Copy(AText, 4, MaxInt);
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Ende des Bezeichners, der in AText bei AIndex beginnt (erstes Zeichen dahinter).</summary>
function IdentEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and TTextChars.IsIdentChar(AText[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Trägt alle Bezeichner in AText ab AIndex in AWords ein.</summary>
procedure AddWords(AWords: TDictionary<string, Boolean>; const AText: string; AIndex: Integer);
var
  mIndex, mEnd: Integer;
begin
  mIndex := AIndex;
  while mIndex <= Length(AText) do
  begin
    if TTextChars.IsIdentStart(AText[mIndex]) then
    begin
      mEnd := IdentEnd(AText, mIndex);
      AWords.AddOrSetValue(Copy(AText, mIndex, mEnd - mIndex), True);
      mIndex := mEnd;
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
end;

/// <summary>Bezeichner in den Bedingungen ($IFDEF, $IFNDEF, $IF, $ELSEIF) der Datei, groß geschrieben.</summary>
function ConditionWords(ATree: TSyntaxTree): TDictionary<string, Boolean>;
var
  mToken: TPascalToken;
  mText: string;
  mIndex: Integer;
begin
  Result := TDictionary<string, Boolean>.Create;
  for mToken in ATree.Tokens do
  begin
    if not DirectiveBody(mToken, mText) then
    begin
      Continue;
    end;
    mIndex := IdentEnd(mText, 1);
    if MatchStr(Copy(mText, 1, mIndex - 1), ['IFDEF', 'IFNDEF', 'IF', 'ELSEIF']) then
    begin
      AddWords(Result, mText, mIndex);
    end;
  end;
end;

/// <summary>Symbole, die die Include-Datei an ARootPos setzt und eine Bedingung prüft (AUsed); Stand nach der
/// Datei: ein späteres $UNDEF dort nimmt das Symbol wieder heraus.</summary>
function DefinedNames(const AProcessed: TPreprocessorResult; AUsed: TDictionary<string, Boolean>;
  const ARootPos: TTextPosition): TArray<string>;
var
  mSite: TDefineSite;
  mIndex: Integer;
begin
  Result := nil;
  for mSite in AProcessed.DefineSites do
  begin
    if (mSite.FileIndex = 0) or (mSite.RootPos <> ARootPos) or not AUsed.ContainsKey(UpperCase(mSite.Name)) then
    begin
      Continue;
    end;
    mIndex := IndexText(mSite.Name, Result);
    if mSite.Undefine and (mIndex >= 0) then
    begin
      Delete(Result, mIndex, 1);
    end
    else if not mSite.Undefine and (mIndex < 0) then
    begin
      Result := Result + [mSite.Name];
    end;
  end;
end;

/// <summary>Hinweis hinter der Include-Direktive AToken mit den Symbolen ANames.</summary>
function DefinesHint(const AToken: TPascalToken; const ANames: TArray<string>; const AIncludeName: string): TInlayHint;
begin
  Result := Default(TInlayHint);
  Result.Position := AToken.EndPos;
  Result.Text := TLspInlayHints.DefinesPrefix + string.Join(', ', ANames);
  if Length(Result.Text) > TLspInlayHints.MaxLabelLength then
  begin
    Result.Text := Copy(Result.Text, 1, TLspInlayHints.MaxLabelLength - 1) + '…';
  end;
  Result.PaddingLeft := True;
  Result.Defines := ANames;
  Result.IncludeFile := ExtractFileName(StringReplace(Trim(AIncludeName), '''', '', [rfReplaceAll]));
end;

class function TLspInlayHints.IncludeDefines(ATree: TSyntaxTree; const AProcessed: TPreprocessorResult;
  const ARange: TTextRange): TArray<TInlayHint>;
var
  mUsed: TDictionary<string, Boolean>;
  mToken: TPascalToken;
  mNames: TArray<string>;
  mIncludeName: string;
begin
  Result := nil;
  if Length(AProcessed.DefineSites) = 0 then
  begin
    Exit;
  end;
  mUsed := ConditionWords(ATree);
  try
    for mToken in ATree.Tokens do
    begin
      if (mToken.Kind <> TPascalTokenKind.Directive) or not InRange(ARange, mToken.StartPos) or
        not TPascalPreprocessor.IncludeFileOf(mToken.Text, mIncludeName) then
      begin
        Continue;
      end;
      mNames := DefinedNames(AProcessed, mUsed, mToken.StartPos);
      if Length(mNames) > 0 then
      begin
        Result := Result + [DefinesHint(mToken, mNames, mIncludeName)];
      end;
    end;
  finally
    mUsed.Free;
  end;
end;

/// <summary>Liegt ANode im Wert einer Konstanten (const-Abschnitt oder Inline-Konstante)?</summary>
function InConstant(ANode: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := ANode.Parent;
  while (Node <> nil) and not (Node.Kind in [TSyntaxKind.ConstDecl, TSyntaxKind.InlineConst]) do
  begin
    Node := Node.Parent;
  end;
  Result := Node <> nil;
end;

/// <summary>Ein Literal aus genau einem ^X: der Parser schreibt es als #Code (#862).</summary>
function IsCaretLiteral(ANode: TSyntaxNode; const ATreeText: string): Boolean;
begin
  Result := (ANode.EndOffset - ANode.StartOffset = 2) and (ANode.StartOffset < Length(ATreeText)) and
    (ATreeText[ANode.StartOffset + 1] = '^') and ANode.Name.StartsWith('#');
end;

class function TLspInlayHints.ControlChars(ATree: TSyntaxTree; const ATreeText: string;
  const ARange: TTextRange): TArray<TInlayHint>;
var
  mLiterals: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mHint: TInlayHint;
begin
  Result := nil;
  mLiterals := TList<TSyntaxNode>.Create;
  try
    CollectNodes(ATree.Root, [TSyntaxKind.Literal], mLiterals);
    for mNode in mLiterals do
    begin
      if not IsCaretLiteral(mNode, ATreeText) or not InRange(ARange, mNode.StartPos) or not InConstant(mNode) then
      begin
        Continue;
      end;
      mHint := Default(TInlayHint);
      mHint.Position := mNode.EndPos;
      mHint.Text := mNode.Name;
      mHint.PaddingLeft := True;
      mHint.ControlChar := True;
      mHint.CharCode := StrToIntDef(Copy(mNode.Name, 2, MaxInt), 0);
      Result := Result + [mHint];
    end;
  finally
    mLiterals.Free;
  end;
end;

class function TLspInlayHints.MethodMarkers(AResolver: TNameResolver; ATree: TSyntaxTree;
  const ATreeText, AFileName: string; const ARange: TTextRange; const AReadText: THoverReadText): TArray<TInlayHint>;
var
  ReadText: TReferenceReadText;
  Position: TTextPosition;
  Hint: TInlayHint;
begin
  Result := nil;
  ReadText :=
    function(const AName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := Assigned(AReadText) and AReadText(AName, AText);
    end;
  AResolver.PinTree(ATree, AFileName);
  try
    for Position in TLspMethodWithoutSelf.Markers(ATree, ATreeText, ARange,
      TLspMethodWithoutSelf.Lookup(AResolver, ATree, AFileName, ReadText)) do
    begin
      Hint := Default(TInlayHint);
      Hint.Position := Position;
      // Text für Clients; das Plugin beschriftet die Marke selbst in der Sprache der IDE.
      Hint.Text := TMethodWithoutSelf.MarkerText;
      Hint.PaddingLeft := True;
      Hint.MethodWithoutSelf := True;
      Result := Result + [Hint];
    end;
  finally
    AResolver.UnpinTree;
  end;
end;

function CompareHints(const A, B: TInlayHint): Integer;
begin
  Result := ComparePositions(A.Position, B.Position);
end;

class function TLspInlayHints.Collect(const ASource: TInlayHintSource; const ARange: TTextRange;
  const ASettings: TInlayHintSettings): TArray<TInlayHint>;
begin
  Result := Collect(ASource, ARange, ASettings, Default(TPreprocessorResult));
end;

class function TLspInlayHints.Collect(const ASource: TInlayHintSource; const ARange: TTextRange;
  const ASettings: TInlayHintSettings; const AProcessed: TPreprocessorResult): TArray<TInlayHint>;
var
  mList: TList<TInlayHint>;
begin
  mList := TList<TInlayHint>.Create(TComparer<TInlayHint>.Construct(CompareHints));
  try
    if ASettings.ParameterNames then
    begin
      mList.AddRange(ParameterNames(ASource, ARange));
    end;
    if ASettings.InferredTypes then
    begin
      mList.AddRange(InferredTypes(ASource.Resolver, ASource.Tree, ASource.FileName, ARange));
    end;
    if ASettings.EndMarkers then
    begin
      mList.AddRange(EndMarkers(ASource.Tree, ARange, ASettings.EndMarkerMinLines));
    end;
    if ASettings.IncludeDefines then
    begin
      mList.AddRange(IncludeDefines(ASource.Tree, AProcessed, ARange));
    end;
    if ASettings.ControlChars then
    begin
      mList.AddRange(ControlChars(ASource.Tree, ASource.TreeText, ARange));
    end;
    if ASettings.MethodWithoutSelf and (ASource.Resolver <> nil) then
    begin
      mList.AddRange(MethodMarkers(ASource.Resolver, ASource.Tree, ASource.TreeText, ASource.FileName, ARange,
        ASource.ReadText));
    end;
    mList.Sort;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

/// <summary>Zusatzdaten des Hinweises für das Plugin ("data"); nil ohne.</summary>
function HintData(const AHint: TInlayHint): TJSONObject;
var
  mDefines: TJSONArray;
  mName: string;
begin
  Result := nil;
  // Blockanfang für den Sprung per Klick (#620).
  if AHint.HasBlockStart then
  begin
    Result := TJSONObject.Create(TJSONPair.Create('blockStart', TLspPositions.PositionToJson(AHint.BlockStart)));
  end
  // Symbole hinter {$I} (#860), für das Plugin getrennt von Endmarken.
  else if Length(AHint.Defines) > 0 then
  begin
    mDefines := TJSONArray.Create;
    for mName in AHint.Defines do
    begin
      mDefines.Add(mName);
    end;
    Result := TJSONObject.Create(TJSONPair.Create('includeDefines',
      TJSONObject.Create.AddPair('file', AHint.IncludeFile).AddPair('names', mDefines)));
  end
  // Code eines Steuerzeichens (#862), für das Plugin getrennt von Endmarken.
  else if AHint.ControlChar then
  begin
    Result := TJSONObject.Create(TJSONPair.Create('controlChar',
      TJSONObject.Create(TJSONPair.Create('code', TJSONNumber.Create(AHint.CharCode)))));
  end
  // Methode ohne Self (#686): Das Plugin beschriftet die Marke in der Sprache der IDE.
  else if AHint.MethodWithoutSelf then
  begin
    Result := TJSONObject.Create(TJSONPair.Create('methodWithoutSelf', TJSONBool.Create(True)));
  end;
end;

class function TLspInlayHints.ToJson(const AHints: TArray<TInlayHint>): TJSONArray;
var
  mHint: TInlayHint;
  mEntry, mData: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mHint in AHints do
  begin
    mEntry := TJSONObject.Create;
    Result.AddElement(mEntry);
    mEntry.AddPair('position', TLspPositions.PositionToJson(mHint.Position));
    mEntry.AddPair('label', mHint.Text);
    if mHint.Kind <> 0 then
    begin
      mEntry.AddPair('kind', TJSONNumber.Create(mHint.Kind));
    end;
    if mHint.PaddingLeft then
    begin
      mEntry.AddPair('paddingLeft', TJSONBool.Create(True));
    end;
    if mHint.PaddingRight then
    begin
      mEntry.AddPair('paddingRight', TJSONBool.Create(True));
    end;
    mData := HintData(mHint);
    if mData <> nil then
    begin
      mEntry.AddPair('data', mData);
    end;
  end;
end;

function TLspInlayHints.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  RangeValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Settings: TInlayHintSettings;
  MinLines: Integer;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('range', RangeValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Felder "textDocument.uri" und "range" fehlen');
  end;
  if not FStore.TryGet(Uri, Document) then
  begin
    Exit(TJSONNull.Create);
  end;
  if Assigned(FSettings) then
  begin
    Settings := FSettings(Uri);
  end
  else
  begin
    Settings := TInlayHintSettings.Default;
  end;
  // Mindestlänge des Plugins (#620).
  if TJSONObject(AParams).TryGetValue<Integer>(MinLinesParam, MinLines) and (MinLines > 0) then
  begin
    Settings.EndMarkerMinLines := MinLines;
  end;
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := Namespaces;
    Result := ToJson(Collect(TInlayHintSource.Create(Resolver, FIndex, Tree, Document.Text,
      TDocumentUris.ToPath(Uri), FReadText), TLspPositions.ReadRange(RangeValue), Settings, Shared.Processed));
  finally
    Resolver.Free;
  end;
end;

end.
