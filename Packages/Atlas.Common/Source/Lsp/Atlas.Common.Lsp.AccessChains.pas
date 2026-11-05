unit Atlas.Common.Lsp.AccessChains;

// Zugriffsketten am Ausführungspunkt (#865, atlas/accessChains): Hält der Debugger wegen einer
// Zugriffsverletzung, zerlegt der Server die Anweisung(en) der Zeile in ihre Zugriffsketten, damit der Editor
// sie von links auswerten und das nil-Glied finden kann.
//   - Anweisungen: einfache Anweisungen, die in der Zeile beginnen (Zuweisung, Aufruf, raise, Inline-Variable),
//     und die Köpfe zusammengesetzter Anweisungen, deren Ausdruck in der Zeile steht (if-, while-, case-,
//     until-Bedingung, for-Grenzen, with-Elemente). Der Debugger nennt nur die Zeile; stehen dort mehrere
//     Anweisungen, kommen alle, und "statements" sagt, wie viele.
//   - Kette: A.B.C, Liste[I].Name, Self.FDaten^, Fn(K).L[2]. Glieder sind die Teile, die der Zugriff
//     dereferenziert (alle außer dem letzten): Auftrag und Auftrag.Kunde bei Auftrag.Kunde.Adresse := …,
//     ein Feld der eigenen Klasse ohne Self davor bekommt Self als erstes Glied. Unit- und Typnamen, Werte von
//     Records und der Name vor einem Aufruf sind keine Glieder.
//   - Je Glied: Ausdruck für den Debugger, Art (Klasse, Interface, Zeiger, dynamisches Array, unbekannt), Typ,
//     ob die Auswertung etwas aufruft (Funktion, Property mit Getter, Default-Property; auch jedes Glied danach),
//     bei dynamischen Arrays mit Index der Index und ob er ohne Aufruf auswertbar ist, bei Klassen die Felder
//     samt geschätztem Versatz (VMT-Zeiger vorn, Vorfahren zuerst, natürliche Ausrichtung bis 8; -1, sobald
//     eine Größe unbekannt ist). Der Editor prüft den Versatz beim Debugger nach.

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
  Atlas.Common.Lsp.References;

type
  {$SCOPEDENUMS ON}
  TAccessLinkKind = (Unknown, ClassRef, InterfaceRef, Pointer, DynArray);
  {$SCOPEDENUMS OFF}

  TAccessField = record
    Name: string;
    /// <summary>Geschätzter Versatz in der Instanz; -1 = unbekannt.</summary>
    Offset: Integer;
  end;

  TAccessLink = record
    /// <summary>Ausdruck für den Debugger, wie im Quelltext (Self bei implizitem Self).</summary>
    Expression: string;
    /// <summary>Letzter Name des Glieds (Kunde bei Auftrag.Kunde).</summary>
    Name: string;
    Range: TTextRange;
    /// <summary>Stelle des Namens, für „Wo wird Kunde zugewiesen?“.</summary>
    NamePosition: TTextPosition;
    Kind: TAccessLinkKind;
    TypeName: string;
    /// <summary>Die Auswertung ruft etwas auf (dieses oder ein früheres Glied).</summary>
    Call: Boolean;
    ImplicitSelf: Boolean;
    /// <summary>Was hinter dem Glied folgt: Name des Mitglieds, '[]', '^' oder '()'.</summary>
    Member: string;
    /// <summary>Dynamisches Array mit Index: der Index wie im Quelltext; '' sonst.</summary>
    IndexText: string;
    IndexPlain: Boolean;
    Fields: TArray<TAccessField>;
  end;

  TAccessChain = record
    /// <summary>Ganze Kette wie im Quelltext (Auftrag.Kunde.Adresse.Ort).</summary>
    Text: string;
    Links: TArray<TAccessLink>;
  end;

  /// <summary>Unit, deren Zeile Collect zerlegt, samt allem, was zum Auflösen der Namen nötig ist.</summary>
  TAccessChainSource = record
    Resolver: TNameResolver;
    Index: ISymbolIndex;
    /// <summary>Quelltext anderer Units (Deklarationen von Typen); darf nil sein.</summary>
    ReadText: TReferenceReadText;
    Tree: TSyntaxTree;
    Text: string;
    FileName: string;
    /// <summary>4 (Win32) oder 8 (Win64); andere Werte gelten als 4.</summary>
    PointerSize: Integer;
  end;

  TAccessChainsResult = record
    /// <summary>Anweisungen in der Zeile.</summary>
    Statements: Integer;
    Chains: TArray<TAccessChain>;
  end;

  TLspAccessChains = class
  public const
    Method = 'atlas/accessChains';
    MaxChains = 50;
    MaxFields = 64;
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: TReferenceReadText;
    FNamespaces: TArray<string>;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    /// <summary>AReadText: Quelltext anderer Units (Deklarationen von Typen); darf nil sein.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AEnsureUnit: TEnsureUnitFunc);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Zugriffsketten der Anweisungen in ALine (0-basiert).</summary>
    class function Collect(const ASource: TAccessChainSource; ALine: Integer): TAccessChainsResult; static;
    /// <summary>Antwort mit "statements" und "chains". Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AResult: TAccessChainsResult): TJSONObject; static;
    class function KindName(AKind: TAccessLinkKind): string; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Internals.Namespaces,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TAccessChainsText = (FieldsTextDocumentUriAndLine);

const
  cTexts: array[TAccessChainsText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "line" fehlen in '; En: 'Fields "textDocument.uri" and "line" missing in '));

{$SCOPEDENUMS OFF}

const
  ChainKinds = [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Dereference, TSyntaxKind.Call];
  ExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess, TSyntaxKind.Dereference, TSyntaxKind.AddressOf, TSyntaxKind.SetConstructor,
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.InheritedExpr,
    TSyntaxKind.RangeExpr, TSyntaxKind.IfExpr];
  /// <summary>Anweisungen, deren Ausdrücke alle zur Zeile ihres Anfangs gehören.</summary>
  SimpleStatements = [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement,
    TSyntaxKind.InlineVar, TSyntaxKind.InlineConst];
  /// <summary>Anweisungen mit Kopf (Bedingung, Grenzen, Elemente); der Kopf zählt zu seiner Zeile.</summary>
  CompoundStatements = [TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement,
    TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement];

type
  /// <summary>Ein Knoten der Kette und was hinter ihm folgt.</summary>
  TLinkStep = record
    Node: TSyntaxNode;
    /// <summary>Folgeknoten; beim letzten Glied eines with-Elements der Knoten selbst.</summary>
    Next: TSyntaxNode;
    /// <summary>Letztes Glied eines with-Elements: Hinter ihm steht kein Knoten.</summary>
    WithLast: Boolean;
  end;

  /// <summary>Symbol und Typ eines Glieds.</summary>
  TLinkTarget = record
    Symbol: TResolvedSymbol;
    TypeSymbol: TResolvedSymbol;
    TypeFound: Boolean;
  end;

  TCollector = class
  private
    FResolver: TNameResolver;
    FIndex: ISymbolIndex;
    FReadText: TReferenceReadText;
    FTree: TSyntaxTree;
    FText: string;
    FFileName: string;
    FPointerSize: Integer;
    FChains: TList<TAccessChain>;
    FTexts: TDictionary<string, string>;
    function TextOf(ANode: TSyntaxNode): string;
    function FileText(const AFileName: string): string;
    /// <summary>Rechte Seite der Typdeklaration (array of TKunde, ^TPunkt); '' wenn unbekannt.</summary>
    function AliasText(const AType: TResolvedSymbol): string;
    function NamePositionOf(ANode: TSyntaxNode): TTextPosition;
    function NameOf(ANode: TSyntaxNode): string;
    function UnitFor(const AType: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
    /// <summary>Größe eines im Index gefundenen Typs; 0 = unbekannt.</summary>
    function ResolvedSize(const AUnit: TUnitIndex; const ATypeName: string): Integer;
    function FieldSize(const AUnit: TUnitIndex; const ATypeName: string; out AAlign: Integer): Integer;
    /// <summary>AType und seine Vorfahren bis vor TObject, der älteste zuerst. AKnown: Der älteste stammt direkt
    /// von TObject ab, die Versätze lassen sich also schätzen.</summary>
    function TypeChain(const AType: TResolvedSymbol; out AKnown: Boolean): TArray<TResolvedSymbol>;
    /// <summary>Felder von ATypeName in AUnit in der Reihenfolge der Deklaration.</summary>
    function OwnFields(const AUnit: TUnitIndex; const ATypeName: string): TArray<TIndexSymbol>;
    /// <summary>Feld mit Versatz ab AOffset (danach hinter dem Feld); AKnown wird False, sobald eine Größe fehlt.
    /// </summary>
    function PlacedField(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol; var AOffset: Integer;
      var AKnown: Boolean): TAccessField;
    function FieldsOf(const AType: TResolvedSymbol): TArray<TAccessField>;
    function KindOf(const ASymbol, AType: TResolvedSymbol; ATypeFound: Boolean; ANode: TSyntaxNode): TAccessLinkKind;
    /// <summary>Elementtyp von Base[I], wenn Base ein dynamisches Array ist.</summary>
    function ElementType(ABase: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
    function IsCallLink(ANode: TSyntaxNode; const ASymbol: TResolvedSymbol): Boolean;
    function PlainIndex(ANode: TSyntaxNode): Boolean;
    function ImplicitSelf(ARoot: TSyntaxNode; out ALink: TAccessLink): Boolean;
    /// <summary>Symbol und Typ von ANode; False, wenn ANode kein Wert ist, der nil sein kann.</summary>
    function ResolveLink(ANode: TSyntaxNode; out ATarget: TLinkTarget): Boolean;
    procedure FillMember(const AStep: TLinkStep; const ATarget: TLinkTarget; var ALink: TAccessLink);
    /// <summary>Glied zu AStep; False, wenn der Zugriff es nicht dereferenziert. ACalled: Ein Glied bis hier
    /// ruft etwas auf.</summary>
    function BuildLink(const AStep: TLinkStep; const ATarget: TLinkTarget; var ACalled: Boolean;
      out ALink: TAccessLink): Boolean;
    /// <summary>Zählt ANode als Anweisung in ALine und sammelt die Ketten ihrer Ausdrücke dort.</summary>
    function VisitSimpleStatement(ANode: TSyntaxNode; ALine: Integer): Boolean;
    /// <summary>Zählt den Kopf von ANode, wenn ein Ausdruck in ALine steht, und sammelt dessen Ketten.</summary>
    function VisitStatementHead(ANode: TSyntaxNode; ALine: Integer): Boolean;
    /// <summary>AWithElement: ATop ist ein with-Element; es wird selbst dereferenziert und ist ein Glied.</summary>
    procedure AddChain(ATop: TSyntaxNode; AWithElement: Boolean);
    procedure Visit(ANode: TSyntaxNode; AAsBase: Boolean);
  public
    constructor Create(const ASource: TAccessChainSource);
    destructor Destroy; override;
    procedure VisitExpression(ANode: TSyntaxNode);
    /// <summary>Element einer with-Anweisung: Die Mitglieder im Rumpf greifen über es zu.</summary>
    procedure VisitWithElement(ANode: TSyntaxNode);
    function Chains: TArray<TAccessChain>;
    /// <summary>Sammelt die Ketten von ANode, wenn es eine Anweisung in ALine ist oder ihr Kopf dort steht.
    /// Ergebnis: ANode zählt als Anweisung der Zeile.</summary>
    function VisitStatement(ANode: TSyntaxNode; ALine: Integer): Boolean;
  end;

function SingleLine(const AText: string): string;
var
  Index: Integer;
  Space: Boolean;
begin
  Result := '';
  Space := False;
  for Index := 1 to Length(AText) do
  begin
    if CharInSet(AText[Index], [#9, #10, #13, ' ']) then
    begin
      Space := Result <> '';
    end
    else
    begin
      if Space then
      begin
        Result := Result + ' ';
      end;
      Space := False;
      Result := Result + AText[Index];
    end;
  end;
end;

function IsPointerText(const AText: string): Boolean;
var
  Text: string;
begin
  Text := LowerCase(Trim(AText));
  Result := Text.StartsWith('^') or (Text = 'pointer') or Text.StartsWith('class of') or
    Text.StartsWith('reference to') or (Text = 'pchar') or (Text = 'pansichar') or (Text = 'pwidechar');
end;

function IsDynArrayText(const AText: string): Boolean;
var
  Text: string;
begin
  Text := LowerCase(Trim(AText));
  Result := Text.StartsWith('array of') or Text.StartsWith('tarray<') or Text.StartsWith('system.tarray<') or
    (Text = 'tbytes') or (Text = 'tstringdynarray') or (Text = 'tintegerdynarray');
end;

const
  cOneByte: array[0..6] of string = ('byte', 'shortint', 'boolean', 'bytebool', 'ansichar', 'int8', 'uint8');
  cTwoBytes: array[0..6] of string = ('word', 'smallint', 'char', 'widechar', 'wordbool', 'int16', 'uint16');
  cFourBytes: array[0..8] of string = ('integer', 'cardinal', 'longint', 'longword', 'longbool', 'single', 'int32',
    'uint32', 'dword');
  cEightBytes: array[0..7] of string = ('int64', 'uint64', 'double', 'currency', 'comp', 'tdatetime', 'tdate',
    'ttime');
  cPointerSized: array[0..11] of string = ('nativeint', 'nativeuint', 'string', 'unicodestring', 'ansistring',
    'widestring', 'rawbytestring', 'utf8string', 'tobject', 'iinterface', 'iunknown', 'tclass');

/// <summary>Größe eingebauter Typen, die nicht von der Zeigergröße abhängt; 0 = keiner davon.</summary>
function FixedBuiltinSize(const AName: string): Integer;
begin
  if MatchStr(AName, cOneByte) then
  begin
    Result := 1;
  end
  else if MatchStr(AName, cTwoBytes) then
  begin
    Result := 2;
  end
  else if MatchStr(AName, cFourBytes) then
  begin
    Result := 4;
  end
  else if MatchStr(AName, cEightBytes) then
  begin
    Result := 8;
  end
  else if AName = 'variant' then
  begin
    Result := 16;
  end
  else
  begin
    Result := 0;
  end;
end;

/// <summary>Größe eingebauter Typen, die von der Zeigergröße abhängt; 0 = keiner davon.</summary>
function PointerBuiltinSize(const AName: string; APointerSize: Integer): Integer;
begin
  if MatchStr(AName, cPointerSized) or IsPointerText(AName) or IsDynArrayText(AName) then
  begin
    Result := APointerSize;
  end
  else if AName <> 'extended' then
  begin
    Result := 0;
  end
  else if APointerSize = 8 then
  begin
    // Win64 rechnet Extended als Double.
    Result := 8;
  end
  else
  begin
    Result := 10;
  end;
end;

/// <summary>Größe eingebauter Typen; 0 = kein eingebauter Typ.</summary>
function BuiltinSize(const ATypeName: string; APointerSize: Integer): Integer;
var
  mName: string;
begin
  mName := LowerCase(Trim(ATypeName));
  if mName.StartsWith('system.') then
  begin
    mName := Copy(mName, 8, MaxInt);
  end;
  Result := FixedBuiltinSize(mName);
  if Result = 0 then
  begin
    Result := PointerBuiltinSize(mName, APointerSize);
  end;
end;

/// <summary>Knoten der Kette von ATop, die Wurzel zuerst.</summary>
function PathOf(ATop: TSyntaxNode): TArray<TSyntaxNode>;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  mNode := ATop;
  while mNode <> nil do
  begin
    Insert(mNode, Result, 0);
    if (mNode.Kind in ChainKinds) and (mNode.ChildCount > 0) then
    begin
      mNode := mNode[0];
    end
    else
    begin
      mNode := nil;
    end;
  end;
end;

function StepAt(const APath: TArray<TSyntaxNode>; AIndex: Integer): TLinkStep;
begin
  Result.Node := APath[AIndex];
  // Beim with-Element steht hinter dem letzten Glied kein Knoten; es zählt wie ein Mitgliedszugriff.
  Result.WithLast := AIndex = High(APath);
  if Result.WithLast then
  begin
    Result.Next := Result.Node;
  end
  else
  begin
    Result.Next := APath[AIndex + 1];
  end;
end;

/// <summary>Knoten, die nie ein Glied sind.</summary>
function IsSkippedStep(const AStep: TLinkStep): Boolean;
begin
  // Der Name vor einem Aufruf ist kein Wert; der Aufruf selbst ist das Glied.
  if (not AStep.WithLast) and (AStep.Next.Kind = TSyntaxKind.Call) and (AStep.Next[0] = AStep.Node) and
    (AStep.Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
  begin
    Exit(True);
  end;
  // Literale und inherited sind nie nil; X^ ist der Wert hinter dem schon geprüften Zeiger.
  Result := AStep.Node.Kind in [TSyntaxKind.Literal, TSyntaxKind.InheritedExpr, TSyntaxKind.Dereference];
end;

/// <summary>Größe eines Typs hinter einem Alias (Zeiger, Methodenzeiger, eingebauter Typ); 0 = unbekannt.</summary>
function AliasSize(const AAlias: string; APointerSize: Integer): Integer;
var
  mLower: string;
begin
  mLower := LowerCase(AAlias);
  if IsPointerText(AAlias) or IsDynArrayText(AAlias) then
  begin
    Result := APointerSize;
  end
  else if not (mLower.StartsWith('procedure') or mLower.StartsWith('function')) then
  begin
    Result := BuiltinSize(AAlias, APointerSize);
  end
  else if Pos('of object', mLower) > 0 then
  begin
    // Methodenzeiger (of object) sind zwei Zeiger, einfache Routinenzeiger einer.
    Result := 2 * APointerSize;
  end
  else
  begin
    Result := APointerSize;
  end;
end;

function MemberAfter(ANext: TSyntaxNode): string;
begin
  case ANext.Kind of
    TSyntaxKind.MemberAccess:
      Result := ANext.Name;
    TSyntaxKind.IndexAccess:
      Result := '[]';
    TSyntaxKind.Dereference:
      Result := '^';
    TSyntaxKind.Call:
      Result := '()';
  else
    Result := '';
  end;
end;

/// <summary>Der Zugriff dereferenziert das Glied (Klasse, Zeiger, Array, unbekannt).</summary>
function IsReference(const AStep: TLinkStep; const ATarget: TLinkTarget; AKind: TAccessLinkKind;
  APointerSize: Integer): Boolean;
begin
  // Records und andere Werte werden nicht dereferenziert (außer über ^, dann ist es ein Zeiger).
  if ATarget.TypeFound and (ATarget.TypeSymbol.SymbolKind in [TIndexSymbolKind.RecordType,
    TIndexSymbolKind.ObjectType, TIndexSymbolKind.EnumType]) and
    (AStep.WithLast or (AStep.Next.Kind <> TSyntaxKind.Dereference)) then
  begin
    Exit(False);
  end;
  // Werte eingebauter Typen ohne Zeigerart (Integer, string) werden nicht dereferenziert.
  Result := ATarget.TypeFound or (ATarget.Symbol.TypeName = '') or
    (BuiltinSize(ATarget.Symbol.TypeName, APointerSize) = 0) or (AKind <> TAccessLinkKind.Unknown);
end;

{ TCollector }

constructor TCollector.Create(const ASource: TAccessChainSource);
begin
  inherited Create;
  FResolver := ASource.Resolver;
  FIndex := ASource.Index;
  FReadText := ASource.ReadText;
  FTree := ASource.Tree;
  FText := ASource.Text;
  FFileName := ASource.FileName;
  FPointerSize := ASource.PointerSize;
  if (FPointerSize <> 4) and (FPointerSize <> 8) then
  begin
    FPointerSize := 4;
  end;
  FChains := TList<TAccessChain>.Create;
  FTexts := TDictionary<string, string>.Create;
end;

destructor TCollector.Destroy;
begin
  FChains.Free;
  FTexts.Free;
  inherited Destroy;
end;

function TCollector.Chains: TArray<TAccessChain>;
begin
  Result := FChains.ToArray;
end;

function TCollector.TextOf(ANode: TSyntaxNode): string;
begin
  Result := SingleLine(Copy(FText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
end;

function TCollector.FileText(const AFileName: string): string;
begin
  if (AFileName = '') or SameText(AFileName, FFileName) then
  begin
    Exit(FText);
  end;
  if FTexts.TryGetValue(AnsiUpperCase(AFileName), Result) then
  begin
    Exit;
  end;
  if not (Assigned(FReadText) and FReadText(AFileName, Result)) then
  begin
    Result := '';
  end;
  FTexts.Add(AnsiUpperCase(AFileName), Result);
end;

function TCollector.AliasText(const AType: TResolvedSymbol): string;
var
  Lines: TArray<string>;
  Line, Start, Stop: Integer;
  Text: string;
begin
  Result := AType.TypeName;
  if (Result <> '') or (AType.SymbolKind <> TIndexSymbolKind.TypeAlias) then
  begin
    Exit;
  end;
  Lines := FileText(AType.FileName).Split([#13#10, #10]);
  Text := '';
  // Die Deklaration steht im Bereich des Symbols; mehrzeilig zusammengefügt.
  for Line := AType.Range.StartPos.Line to Min(AType.Range.EndPos.Line, AType.Range.StartPos.Line + 5) do
  begin
    if (Line >= 0) and (Line <= High(Lines)) then
    begin
      Text := Text + ' ' + Lines[Line];
    end;
  end;
  Start := Pos('=', Text);
  if Start = 0 then
  begin
    Exit;
  end;
  Text := Copy(Text, Start + 1, MaxInt);
  Stop := Pos(';', Text);
  if Stop > 0 then
  begin
    Text := Copy(Text, 1, Stop - 1);
  end;
  Result := SingleLine(Text);
end;

function TCollector.NameOf(ANode: TSyntaxNode): string;
begin
  case ANode.Kind of
    TSyntaxKind.Dereference:
      if ANode.ChildCount > 0 then
      begin
        Result := NameOf(ANode[0]);
      end
      else
      begin
        Result := '';
      end;
    TSyntaxKind.ParenExpr:
      Result := TextOf(ANode);
  else
    Result := ANode.Name;
  end;
end;

function TCollector.NamePositionOf(ANode: TSyntaxNode): TTextPosition;
begin
  case ANode.Kind of
    TSyntaxKind.MemberAccess:
      begin
        // Der Name steht am Ende des Knotens.
        Result := ANode.EndPos;
        Result.Character := Max(0, Result.Character - Length(ANode.Name));
      end;
    TSyntaxKind.IndexAccess, TSyntaxKind.Call, TSyntaxKind.Dereference:
      if ANode.ChildCount > 0 then
      begin
        Result := NamePositionOf(ANode[0]);
      end
      else
      begin
        Result := ANode.StartPos;
      end;
  else
    Result := ANode.StartPos;
  end;
end;

function TCollector.UnitFor(const AType: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  AUnit := Default(TUnitIndex);
  if (AType.FileName = '') or SameText(AType.FileName, FFileName) then
  begin
    AUnit := FResolver.ExtractedUnit(FTree, FFileName);
    Exit(True);
  end;
  Result := (FIndex <> nil) and FIndex.FindFile(AType.FileName, AUnit);
end;

function TCollector.ResolvedSize(const AUnit: TUnitIndex; const ATypeName: string): Integer;
var
  mResolved: TResolvedSymbol;
begin
  Result := 0;
  if not FResolver.ResolveTypeTextFrom(AUnit, ATypeName, mResolved) then
  begin
    Exit;
  end;
  case mResolved.SymbolKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType:
      Result := FPointerSize;
    TIndexSymbolKind.EnumType:
      // Aufzählungen bis 256 Werte; größere sind selten.
      Result := 1;
    TIndexSymbolKind.TypeAlias:
      Result := AliasSize(AliasText(mResolved), FPointerSize);
  else
    // Übrige Arten: Größe unbekannt.
  end;
end;

function TCollector.FieldSize(const AUnit: TUnitIndex; const ATypeName: string; out AAlign: Integer): Integer;
begin
  Result := BuiltinSize(ATypeName, FPointerSize);
  if Result = 0 then
  begin
    Result := ResolvedSize(AUnit, ATypeName);
  end;
  AAlign := Min(Max(Result, 1), 8);
  if Result = 2 * FPointerSize then
  begin
    AAlign := FPointerSize;
  end;
  if Result = 10 then
  begin
    AAlign := 8;
  end;
end;

function TCollector.TypeChain(const AType: TResolvedSymbol; out AKnown: Boolean): TArray<TResolvedSymbol>;
var
  mCurrent, mAncestor: TResolvedSymbol;
begin
  // Vorfahren zuerst: Ihre Felder liegen vorn in der Instanz.
  mCurrent := AType;
  Result := TArray<TResolvedSymbol>.Create(mCurrent);
  while (Length(Result) < 32) and FResolver.AncestorOf(mCurrent, mAncestor) and
    not SameText(mAncestor.Name, 'TObject') do
  begin
    Insert(mAncestor, Result, 0);
    mCurrent := mAncestor;
  end;
  // Ohne bekannten Vorfahren (ausser TObject) stimmen die Versätze nicht.
  AKnown := (mCurrent.Ancestors = nil) or SameText(mCurrent.Ancestors[0], 'TObject') or
    SameText(mCurrent.Ancestors[0], 'System.TObject');
end;

function TCollector.OwnFields(const AUnit: TUnitIndex; const ATypeName: string): TArray<TIndexSymbol>;
var
  mOwn: TList<TIndexSymbol>;
  mSymbol: TIndexSymbol;
begin
  mOwn := TList<TIndexSymbol>.Create;
  try
    for mSymbol in AUnit.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, ATypeName) then
      begin
        mOwn.Add(mSymbol);
      end;
    end;
    mOwn.Sort(TComparer<TIndexSymbol>.Construct(
      function(const A, B: TIndexSymbol): Integer
      begin
        Result := CompareValue(A.Range.StartPos.Line, B.Range.StartPos.Line);
        if Result = 0 then
        begin
          Result := CompareValue(A.Range.StartPos.Character, B.Range.StartPos.Character);
        end;
      end));
    Result := mOwn.ToArray;
  finally
    mOwn.Free;
  end;
end;

function TCollector.PlacedField(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol; var AOffset: Integer;
  var AKnown: Boolean): TAccessField;
var
  mSize, mAlign: Integer;
begin
  Result := Default(TAccessField);
  Result.Name := ASymbol.Name;
  Result.Offset := -1;
  if not AKnown then
  begin
    Exit;
  end;
  mSize := FieldSize(AUnit, ASymbol.TypeName, mAlign);
  if mSize = 0 then
  begin
    AKnown := False;
    Exit;
  end;
  AOffset := ((AOffset + mAlign - 1) div mAlign) * mAlign;
  Result.Offset := AOffset;
  Inc(AOffset, mSize);
end;

function TCollector.FieldsOf(const AType: TResolvedSymbol): TArray<TAccessField>;
var
  mTypes: TArray<TResolvedSymbol>;
  mType: TResolvedSymbol;
  mTypeUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mOffset: Integer;
  mKnown: Boolean;
begin
  Result := nil;
  mTypes := TypeChain(AType, mKnown);
  mOffset := FPointerSize;
  for mType in mTypes do
  begin
    if not UnitFor(mType, mTypeUnit) then
    begin
      mKnown := False;
      Continue;
    end;
    for mSymbol in OwnFields(mTypeUnit, mType.Name) do
    begin
      Result := Result + [PlacedField(mTypeUnit, mSymbol, mOffset, mKnown)];
      if Length(Result) >= TLspAccessChains.MaxFields then
      begin
        Exit;
      end;
    end;
  end;
end;

function TCollector.KindOf(const ASymbol, AType: TResolvedSymbol; ATypeFound: Boolean;
  ANode: TSyntaxNode): TAccessLinkKind;
var
  Text: string;
begin
  Result := TAccessLinkKind.Unknown;
  if ATypeFound then
    case AType.SymbolKind of
      TIndexSymbolKind.ClassType:
        Exit(TAccessLinkKind.ClassRef);
      TIndexSymbolKind.InterfaceType:
        Exit(TAccessLinkKind.InterfaceRef);
      TIndexSymbolKind.TypeAlias:
        begin
          Text := AliasText(AType);
          if IsDynArrayText(Text) then
          begin
            Exit(TAccessLinkKind.DynArray);
          end;
          if IsPointerText(Text) then
          begin
            Exit(TAccessLinkKind.Pointer);
          end;
        end;
    else
      // Übrige Arten: nichts zu tun.
    end;
  Text := ASymbol.TypeName;
  if IsDynArrayText(Text) then
  begin
    Result := TAccessLinkKind.DynArray;
  end
  else if IsPointerText(Text) then
  begin
    Result := TAccessLinkKind.Pointer;
  end
  else if (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.Dereference) then
  begin
    Result := TAccessLinkKind.Pointer;
  end;
end;

function TCollector.ElementType(ABase: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
var
  Symbol, BaseType: TResolvedSymbol;
  Found: Boolean;
  Text: string;
  FromUnit: TUnitIndex;
begin
  AType := Default(TResolvedSymbol);
  Result := False;
  FResolver.NodeType(FTree, FFileName, ABase, Symbol, BaseType, Found);
  if Found then
  begin
    Text := AliasText(BaseType);
  end
  else
  begin
    Text := Symbol.TypeName;
  end;
  Text := Trim(Text);
  if LowerCase(Text).StartsWith('array of') then
  begin
    Text := Trim(Copy(Text, 9, MaxInt));
  end
  else if LowerCase(Text).StartsWith('tarray<') and Text.EndsWith('>') then
  begin
    Text := Trim(Copy(Text, 8, Length(Text) - 8));
  end
  else
  begin
    Exit;
  end;
  if not (Found and UnitFor(BaseType, FromUnit)) then
  begin
    FromUnit := FResolver.ExtractedUnit(FTree, FFileName);
  end;
  Result := FResolver.ResolveTypeTextFrom(FromUnit, Text, AType);
end;

function TCollector.IsCallLink(ANode: TSyntaxNode; const ASymbol: TResolvedSymbol): Boolean;
var
  ReadsField: Boolean;
begin
  if ANode.Kind = TSyntaxKind.Call then
  begin
    Exit(True);
  end;
  case ASymbol.SymbolKind of
    TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_:
      // Funktion ohne Klammern.
      Result := True;
    TIndexSymbolKind.Property_:
      // Getter oder unbekannter Zugriff: Die Auswertung könnte etwas ausführen.
      Result := not (FResolver.PropertyReadsField(ASymbol, ReadsField) and ReadsField);
  else
    Result := False;
  end;
end;

function TCollector.PlainIndex(ANode: TSyntaxNode): Boolean;
var
  Plain: Boolean;
begin
  Plain := True;
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    var
      Symbol: TResolvedSymbol;
    begin
      if AChild.Kind in [TSyntaxKind.Call, TSyntaxKind.AnonymousMethod, TSyntaxKind.InheritedExpr] then
      begin
        Plain := False;
      end
      else if AChild.Kind = TSyntaxKind.Identifier then
      begin
        Symbol := FResolver.Resolve(FTree, FFileName, AChild.StartPos);
        if not ((Symbol.Kind = TResolvedKind.Local) or (Symbol.SymbolKind in [TIndexSymbolKind.Variable,
          TIndexSymbolKind.Field, TIndexSymbolKind.Constant, TIndexSymbolKind.EnumMember])) then
        begin
          Plain := False;
        end;
      end;
      Result := Plain;
    end);
  Result := Plain;
end;

function TCollector.ImplicitSelf(ARoot: TSyntaxNode; out ALink: TAccessLink): Boolean;
var
  Symbol, ClassType: TResolvedSymbol;
  mWith: TResolvedWithMember;
begin
  ALink := Default(TAccessLink);
  Result := False;
  if (ARoot.Kind <> TSyntaxKind.Identifier) or SameText(ARoot.Name, 'Self') then
  begin
    Exit;
  end;
  Symbol := FResolver.Resolve(FTree, FFileName, ARoot.StartPos);
  if (Symbol.Kind <> TResolvedKind.Symbol) or (Symbol.Container = '') or
    not (Symbol.SymbolKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Method]) then
  begin
    Exit;
  end;
  // In with gehört der Name vielleicht zu einem Element, nicht zu Self.
  if FResolver.Queries.WithMember(FTree, FFileName, ARoot.Name, ARoot.StartOffset, mWith) or mWith.Unknown then
  begin
    Exit;
  end;
  ALink.Expression := 'Self';
  ALink.Name := 'Self';
  ALink.Range := TTextRange.Create(ARoot.StartPos, ARoot.EndPos);
  ALink.NamePosition := ARoot.StartPos;
  ALink.Kind := TAccessLinkKind.ClassRef;
  ALink.TypeName := Symbol.Container;
  ALink.ImplicitSelf := True;
  ALink.Member := ARoot.Name;
  if FResolver.ResolveTypeFrom(FResolver.ExtractedUnit(FTree, FFileName), Symbol.Container, ClassType) and
    (ClassType.SymbolKind = TIndexSymbolKind.ClassType) then
  begin
    ALink.Fields := FieldsOf(ClassType);
  end;
  Result := True;
end;

function TCollector.ResolveLink(ANode: TSyntaxNode; out ATarget: TLinkTarget): Boolean;
begin
  ATarget := Default(TLinkTarget);
  if ANode.Kind <> TSyntaxKind.ParenExpr then
  begin
    FResolver.NodeType(FTree, FFileName, ANode, ATarget.Symbol, ATarget.TypeSymbol, ATarget.TypeFound);
  end;
  // Element eines dynamischen Arrays: Typ aus der Deklaration des Arrays.
  if (ANode.Kind = TSyntaxKind.IndexAccess) and not ATarget.TypeFound and (ANode.ChildCount > 0) then
  begin
    ATarget.TypeFound := ElementType(ANode[0], ATarget.TypeSymbol);
  end;
  // Self liefert die Klasse selbst.
  if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'Self') and ATarget.Symbol.IsType then
  begin
    ATarget.TypeSymbol := ATarget.Symbol;
    ATarget.TypeFound := True;
    ATarget.Symbol := Default(TResolvedSymbol);
    ATarget.Symbol.Kind := TResolvedKind.Local;
  end;
  // Nicht auflösbare Namen (etwa Unit-Präfixe ohne Index): nichts zu sagen.
  if (ANode.Kind = TSyntaxKind.Identifier) and not ATarget.Symbol.Found and not ATarget.TypeFound then
  begin
    Exit(False);
  end;
  // Unit- und Typnamen, Konstanten und Aufzählungswerte sind keine Werte, die nil sein können.
  Result := not ((ATarget.Symbol.Kind = TResolvedKind.UnitName) or ATarget.Symbol.IsType or
    (ATarget.Symbol.SymbolKind in [TIndexSymbolKind.Constant, TIndexSymbolKind.EnumMember]));
end;

procedure TCollector.FillMember(const AStep: TLinkStep; const ATarget: TLinkTarget; var ALink: TAccessLink);
begin
  if AStep.WithLast then
  begin
    ALink.Member := 'with';
  end
  else
  begin
    ALink.Member := MemberAfter(AStep.Next);
  end;
  if (not AStep.WithLast) and (ALink.Kind = TAccessLinkKind.DynArray) and
    (AStep.Next.Kind = TSyntaxKind.IndexAccess) and (AStep.Next.ChildCount = 2) then
  begin
    ALink.IndexText := TextOf(AStep.Next[1]);
    ALink.IndexPlain := PlainIndex(AStep.Next[1]);
  end;
  if (ALink.Kind = TAccessLinkKind.ClassRef) and ATarget.TypeFound then
  begin
    ALink.Fields := FieldsOf(ATarget.TypeSymbol);
  end;
end;

function TCollector.BuildLink(const AStep: TLinkStep; const ATarget: TLinkTarget; var ACalled: Boolean;
  out ALink: TAccessLink): Boolean;
begin
  ALink := Default(TAccessLink);
  ALink.Kind := KindOf(ATarget.Symbol, ATarget.TypeSymbol, ATarget.TypeFound, AStep.Node);
  Result := IsReference(AStep, ATarget, ALink.Kind, FPointerSize);
  if not Result then
  begin
    Exit;
  end;
  ALink.Expression := TextOf(AStep.Node);
  ALink.Name := NameOf(AStep.Node);
  ALink.Range := TTextRange.Create(AStep.Node.StartPos, AStep.Node.EndPos);
  ALink.NamePosition := NamePositionOf(AStep.Node);
  if ATarget.TypeFound then
  begin
    ALink.TypeName := ATarget.TypeSymbol.Name;
  end
  else
  begin
    ALink.TypeName := ATarget.Symbol.TypeName;
  end;
  ACalled := ACalled or IsCallLink(AStep.Node, ATarget.Symbol);
  ALink.Call := ACalled;
  FillMember(AStep, ATarget, ALink);
end;

procedure TCollector.AddChain(ATop: TSyntaxNode; AWithElement: Boolean);
var
  mPath: TArray<TSyntaxNode>;
  mChain: TAccessChain;
  mLink: TAccessLink;
  mStep: TLinkStep;
  mTarget: TLinkTarget;
  mCalled: Boolean;
  mIndex, mLast: Integer;
begin
  if FChains.Count >= TLspAccessChains.MaxChains then
  begin
    Exit;
  end;
  mPath := PathOf(ATop);
  mChain := Default(TAccessChain);
  mChain.Text := TextOf(ATop);
  mCalled := False;
  if ImplicitSelf(mPath[0], mLink) then
  begin
    mChain.Links := mChain.Links + [mLink];
  end;
  mLast := High(mPath) - 1;
  if AWithElement then
  begin
    mLast := High(mPath);
  end;
  for mIndex := 0 to mLast do
  begin
    mStep := StepAt(mPath, mIndex);
    if (not IsSkippedStep(mStep)) and ResolveLink(mStep.Node, mTarget) and
      BuildLink(mStep, mTarget, mCalled, mLink) then
    begin
      mChain.Links := mChain.Links + [mLink];
    end;
  end;
  if mChain.Links <> nil then
  begin
    FChains.Add(mChain);
  end;
end;

procedure TCollector.Visit(ANode: TSyntaxNode; AAsBase: Boolean);
var
  Index: Integer;
  Link: TAccessLink;
  Chain: TAccessChain;
begin
  if ANode = nil then
  begin
    Exit;
  end;
  // Rümpfe anonymer Methoden laufen hier nicht.
  if ANode.Kind = TSyntaxKind.AnonymousMethod then
  begin
    Exit;
  end;
  if (ANode.Kind in ChainKinds) and not AAsBase then
  begin
    AddChain(ANode, False);
  end
  else if (ANode.Kind = TSyntaxKind.Identifier) and not AAsBase then
  begin
    // Ein Feld allein (FCount := 1) liest über Self.
    if ImplicitSelf(ANode, Link) and (FChains.Count < TLspAccessChains.MaxChains) then
    begin
      Chain := Default(TAccessChain);
      Chain.Text := TextOf(ANode);
      Chain.Links := [Link];
      FChains.Add(Chain);
    end;
  end;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Visit(ANode[Index], (Index = 0) and (ANode.Kind in ChainKinds));
  end;
end;

procedure TCollector.VisitExpression(ANode: TSyntaxNode);
begin
  Visit(ANode, False);
end;

procedure TCollector.VisitWithElement(ANode: TSyntaxNode);
var
  Index: Integer;
begin
  if ANode.Kind = TSyntaxKind.AnonymousMethod then
  begin
    Exit;
  end;
  AddChain(ANode, True);
  // Ausdrücke im Element (Argumente, Indizes) wie sonst.
  if ANode.Kind in ChainKinds then
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Visit(ANode[Index], Index = 0);
    end;
  end;
end;

function TCollector.VisitSimpleStatement(ANode: TSyntaxNode; ALine: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := ANode.StartPos.Line = ALine;
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind in ExpressionKinds then
    begin
      VisitExpression(ANode[mIndex]);
    end;
  end;
end;

function TCollector.VisitStatementHead(ANode: TSyntaxNode; ALine: Integer): Boolean;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := False;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mChild := ANode[mIndex];
    if not ((mChild.Kind in ExpressionKinds) and (mChild.StartPos.Line = ALine)) then
    begin
      Continue;
    end;
    Result := True;
    if ANode.Kind = TSyntaxKind.WithStatement then
    begin
      VisitWithElement(mChild);
    end
    else
    begin
      VisitExpression(mChild);
    end;
  end;
end;

function TCollector.VisitStatement(ANode: TSyntaxNode; ALine: Integer): Boolean;
begin
  if ANode.Kind in SimpleStatements then
  begin
    Result := VisitSimpleStatement(ANode, ALine);
  end
  else if ANode.Kind in CompoundStatements then
  begin
    Result := VisitStatementHead(ANode, ALine);
  end
  else
  begin
    Result := False;
  end;
end;

{ TLspAccessChains }

constructor TLspAccessChains.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FEnsureUnit := AEnsureUnit;
end;

function TLspAccessChains.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspAccessChains.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

procedure TLspAccessChains.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
end;

class function TLspAccessChains.KindName(AKind: TAccessLinkKind): string;
const
  Names: array[TAccessLinkKind] of string = ('unknown', 'class', 'interface', 'pointer', 'dynArray');
begin
  Result := Names[AKind];
end;

class function TLspAccessChains.Collect(const ASource: TAccessChainSource; ALine: Integer): TAccessChainsResult;
var
  mCollector: TCollector;
  mCount: Integer;
begin
  Result := Default(TAccessChainsResult);
  mCount := 0;
  mCollector := TCollector.Create(ASource);
  ASource.Resolver.PinTree(ASource.Tree, ASource.FileName);
  try
    ASource.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := ANode.Kind <> TSyntaxKind.AnonymousMethod;
        if Result and mCollector.VisitStatement(ANode, ALine) then
        begin
          Inc(mCount);
        end;
      end);
    Result.Statements := mCount;
    Result.Chains := mCollector.Chains;
  finally
    ASource.Resolver.UnpinTree;
    mCollector.Free;
  end;
end;

class function TLspAccessChains.ToJson(const AResult: TAccessChainsResult): TJSONObject;
var
  Chains, Links, Fields: TJSONArray;
  Chain: TAccessChain;
  Link: TAccessLink;
  Field: TAccessField;
  Item, LinkItem, FieldItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('statements', TJSONNumber.Create(AResult.Statements));
  Chains := TJSONArray.Create;
  Result.AddPair('chains', Chains);
  for Chain in AResult.Chains do
  begin
    Item := TJSONObject.Create;
    Chains.AddElement(Item);
    Item.AddPair('text', Chain.Text);
    Links := TJSONArray.Create;
    Item.AddPair('links', Links);
    for Link in Chain.Links do
    begin
      LinkItem := TJSONObject.Create;
      Links.AddElement(LinkItem);
      LinkItem.AddPair('expression', Link.Expression);
      LinkItem.AddPair('name', Link.Name);
      LinkItem.AddPair('range', TLspPositions.RangeToJson(Link.Range));
      LinkItem.AddPair('namePosition', TLspPositions.PositionToJson(Link.NamePosition));
      LinkItem.AddPair('kind', KindName(Link.Kind));
      LinkItem.AddPair('typeName', Link.TypeName);
      LinkItem.AddPair('call', TJSONBool.Create(Link.Call));
      LinkItem.AddPair('implicitSelf', TJSONBool.Create(Link.ImplicitSelf));
      LinkItem.AddPair('member', Link.Member);
      if Link.IndexText <> '' then
      begin
        LinkItem.AddPair('index', Link.IndexText);
        LinkItem.AddPair('indexPlain', TJSONBool.Create(Link.IndexPlain));
      end;
      if Link.Fields <> nil then
      begin
        Fields := TJSONArray.Create;
        LinkItem.AddPair('fields', Fields);
        for Field in Link.Fields do
        begin
          FieldItem := TJSONObject.Create;
          FieldItem.AddPair('name', Field.Name);
          FieldItem.AddPair('offset', TJSONNumber.Create(Field.Offset));
          Fields.AddElement(FieldItem);
        end;
      end;
    end;
  end;
end;

function TLspAccessChains.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mLine: Integer;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mSource: TAccessChainSource;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<Integer>('line', mLine)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TAccessChainsText.FieldsTextDocumentUriAndLine].Text + Method);
  end;
  mSource := Default(TAccessChainSource);
  if not TJSONObject(AParams).TryGetValue<Integer>('pointerSize', mSource.PointerSize) then
  begin
    mSource.PointerSize := 4;
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  ACancellation.ThrowIfCancellationRequested;
  mSource.Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    mSource.Resolver.Namespaces := Namespaces;
    mSource.Index := FIndex;
    mSource.ReadText := FReadText;
    mSource.Tree := mShared.Tree;
    mSource.Text := mDocument.GetText;
    mSource.FileName := TDocumentUris.ToPath(mUri);
    Result := ToJson(Collect(mSource, mLine));
  finally
    mSource.Resolver.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.AccessChains', cTexts);

end.
