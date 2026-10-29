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
    /// <summary>Zugriffsketten der Anweisungen in ALine (0-basiert). APointerSize: 4 (Win32) oder 8 (Win64).
    /// </summary>
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      ATree: TSyntaxTree; const AText, AFileName: string; ALine, APointerSize: Integer): TAccessChainsResult; static;
    /// <summary>Antwort mit "statements" und "chains". Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AResult: TAccessChainsResult): TJSONObject; static;
    class function KindName(AKind: TAccessLinkKind): string; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Internals.Namespaces,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache;

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
    function MemberAfter(ANext: TSyntaxNode): string;
    function UnitFor(const AType: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
    function FieldSize(const AUnit: TUnitIndex; const ATypeName: string; out AAlign: Integer): Integer;
    function FieldsOf(const AType: TResolvedSymbol): TArray<TAccessField>;
    function KindOf(const ASymbol, AType: TResolvedSymbol; ATypeFound: Boolean; ANode: TSyntaxNode): TAccessLinkKind;
    /// <summary>Elementtyp von Base[I], wenn Base ein dynamisches Array ist.</summary>
    function ElementType(ABase: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
    function IsCallLink(ANode: TSyntaxNode; const ASymbol: TResolvedSymbol): Boolean;
    function PlainIndex(ANode: TSyntaxNode): Boolean;
    function ImplicitSelf(ARoot: TSyntaxNode; out ALink: TAccessLink): Boolean;
    /// <summary>AWithElement: ATop ist ein with-Element; es wird selbst dereferenziert und ist ein Glied.</summary>
    procedure AddChain(ATop: TSyntaxNode; AWithElement: Boolean);
    procedure Visit(ANode: TSyntaxNode; AAsBase: Boolean);
  public
    constructor Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      ATree: TSyntaxTree; const AText, AFileName: string; APointerSize: Integer);
    destructor Destroy; override;
    procedure VisitExpression(ANode: TSyntaxNode);
    /// <summary>Element einer with-Anweisung: Die Mitglieder im Rumpf greifen über es zu.</summary>
    procedure VisitWithElement(ANode: TSyntaxNode);
    function Chains: TArray<TAccessChain>;
  end;

function SingleLine(const AText: string): string;
var
  Index: Integer;
  Space: Boolean;
begin
  Result := '';
  Space := False;
  for Index := 1 to Length(AText) do
    if CharInSet(AText[Index], [#9, #10, #13, ' ']) then
      Space := Result <> ''
    else
    begin
      if Space then
        Result := Result + ' ';
      Space := False;
      Result := Result + AText[Index];
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

/// <summary>Größe eingebauter Typen; 0 = kein eingebauter Typ.</summary>
function BuiltinSize(const ATypeName: string; APointerSize: Integer): Integer;
var
  Name: string;
begin
  Name := LowerCase(Trim(ATypeName));
  if Name.StartsWith('system.') then
    Name := Copy(Name, 8, MaxInt);
  if (Name = 'byte') or (Name = 'shortint') or (Name = 'boolean') or (Name = 'bytebool') or (Name = 'ansichar') or
    (Name = 'int8') or (Name = 'uint8') then
    Result := 1
  else if (Name = 'word') or (Name = 'smallint') or (Name = 'char') or (Name = 'widechar') or (Name = 'wordbool') or
    (Name = 'int16') or (Name = 'uint16') then
    Result := 2
  else if (Name = 'integer') or (Name = 'cardinal') or (Name = 'longint') or (Name = 'longword') or
    (Name = 'longbool') or (Name = 'single') or (Name = 'int32') or (Name = 'uint32') or (Name = 'dword') then
    Result := 4
  else if (Name = 'int64') or (Name = 'uint64') or (Name = 'double') or (Name = 'currency') or (Name = 'comp') or
    (Name = 'tdatetime') or (Name = 'tdate') or (Name = 'ttime') then
    Result := 8
  else if (Name = 'nativeint') or (Name = 'nativeuint') or (Name = 'string') or (Name = 'unicodestring') or
    (Name = 'ansistring') or (Name = 'widestring') or (Name = 'rawbytestring') or (Name = 'utf8string') or
    (Name = 'tobject') or (Name = 'iinterface') or (Name = 'iunknown') or (Name = 'tclass') or
    IsPointerText(Name) or IsDynArrayText(Name) then
    Result := APointerSize
  else if Name = 'extended' then
  begin
    // Win64 rechnet Extended als Double.
    if APointerSize = 8 then
      Result := 8
    else
      Result := 10;
  end
  else if Name = 'variant' then
    Result := 16
  else
    Result := 0;
end;

{ TCollector }

constructor TCollector.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; ATree: TSyntaxTree; const AText, AFileName: string; APointerSize: Integer);
begin
  inherited Create;
  FResolver := AResolver;
  FIndex := AIndex;
  FReadText := AReadText;
  FTree := ATree;
  FText := AText;
  FFileName := AFileName;
  FPointerSize := APointerSize;
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
    Exit(FText);
  if FTexts.TryGetValue(AnsiUpperCase(AFileName), Result) then
    Exit;
  if not (Assigned(FReadText) and FReadText(AFileName, Result)) then
    Result := '';
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
    Exit;
  Lines := FileText(AType.FileName).Split([#13#10, #10]);
  Text := '';
  // Die Deklaration steht im Bereich des Symbols; mehrzeilig zusammengefügt.
  for Line := AType.Range.StartPos.Line to Min(AType.Range.EndPos.Line, AType.Range.StartPos.Line + 5) do
    if (Line >= 0) and (Line <= High(Lines)) then
      Text := Text + ' ' + Lines[Line];
  Start := Pos('=', Text);
  if Start = 0 then
    Exit;
  Text := Copy(Text, Start + 1, MaxInt);
  Stop := Pos(';', Text);
  if Stop > 0 then
    Text := Copy(Text, 1, Stop - 1);
  Result := SingleLine(Text);
end;

function TCollector.NameOf(ANode: TSyntaxNode): string;
begin
  case ANode.Kind of
    TSyntaxKind.Dereference:
      if ANode.ChildCount > 0 then
        Result := NameOf(ANode[0])
      else
        Result := '';
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
        Result := NamePositionOf(ANode[0])
      else
        Result := ANode.StartPos;
  else
    Result := ANode.StartPos;
  end;
end;

function TCollector.MemberAfter(ANext: TSyntaxNode): string;
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

function TCollector.FieldSize(const AUnit: TUnitIndex; const ATypeName: string; out AAlign: Integer): Integer;
var
  Resolved: TResolvedSymbol;
  Alias: string;
begin
  Result := BuiltinSize(ATypeName, FPointerSize);
  if Result = 0 then
    if FResolver.ResolveTypeTextFrom(AUnit, ATypeName, Resolved) then
      case Resolved.SymbolKind of
        TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType:
          Result := FPointerSize;
        TIndexSymbolKind.EnumType:
          // Aufzählungen bis 256 Werte; größere sind selten.
          Result := 1;
        TIndexSymbolKind.TypeAlias:
          begin
            Alias := AliasText(Resolved);
            if IsPointerText(Alias) or IsDynArrayText(Alias) then
              Result := FPointerSize
            else if LowerCase(Alias).StartsWith('procedure') or LowerCase(Alias).StartsWith('function') then
            begin
              // Methodenzeiger (of object) sind zwei Zeiger, einfache Routinenzeiger einer.
              if Pos('of object', LowerCase(Alias)) > 0 then
                Result := 2 * FPointerSize
              else
                Result := FPointerSize;
            end
            else
              Result := BuiltinSize(Alias, FPointerSize);
          end;
      end;
  AAlign := Min(Max(Result, 1), 8);
  if Result = 2 * FPointerSize then
    AAlign := FPointerSize;
  if Result = 10 then
    AAlign := 8;
end;

function TCollector.FieldsOf(const AType: TResolvedSymbol): TArray<TAccessField>;
var
  Types: TList<TResolvedSymbol>;
  Current, Ancestor: TResolvedSymbol;
  TypeUnit: TUnitIndex;
  Symbol: TIndexSymbol;
  Own: TList<TIndexSymbol>;
  Field: TAccessField;
  Offset, Size, Align, Index: Integer;
  Known: Boolean;
begin
  Result := nil;
  Types := TList<TResolvedSymbol>.Create;
  Own := TList<TIndexSymbol>.Create;
  try
    // Vorfahren zuerst: Ihre Felder liegen vorn in der Instanz.
    Current := AType;
    Types.Insert(0, Current);
    while (Types.Count < 32) and FResolver.AncestorOf(Current, Ancestor) do
    begin
      if SameText(Ancestor.Name, 'TObject') then
        Break;
      Types.Insert(0, Ancestor);
      Current := Ancestor;
    end;
    // Ohne bekannten Vorfahren (ausser TObject) stimmen die Versätze nicht.
    Known := (Current.Ancestors = nil) or SameText(Current.Ancestors[0], 'TObject') or
      SameText(Current.Ancestors[0], 'System.TObject');
    Offset := FPointerSize;
    for Index := 0 to Types.Count - 1 do
    begin
      Own.Clear;
      if not UnitFor(Types[Index], TypeUnit) then
      begin
        Known := False;
        Continue;
      end;
      for Symbol in TypeUnit.Symbols do
        if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, Types[Index].Name) then
          Own.Add(Symbol);
      Own.Sort(TComparer<TIndexSymbol>.Construct(
        function(const A, B: TIndexSymbol): Integer
        begin
          Result := CompareValue(A.Range.StartPos.Line, B.Range.StartPos.Line);
          if Result = 0 then
            Result := CompareValue(A.Range.StartPos.Character, B.Range.StartPos.Character);
        end));
      for Symbol in Own do
      begin
        Field := Default(TAccessField);
        Field.Name := Symbol.Name;
        Field.Offset := -1;
        if Known then
        begin
          Size := FieldSize(TypeUnit, Symbol.TypeName, Align);
          if Size = 0 then
            Known := False
          else
          begin
            Offset := ((Offset + Align - 1) div Align) * Align;
            Field.Offset := Offset;
            Inc(Offset, Size);
          end;
        end;
        Result := Result + [Field];
        if Length(Result) >= TLspAccessChains.MaxFields then
          Exit;
      end;
    end;
  finally
    Own.Free;
    Types.Free;
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
            Exit(TAccessLinkKind.DynArray);
          if IsPointerText(Text) then
            Exit(TAccessLinkKind.Pointer);
        end;
    end;
  Text := ASymbol.TypeName;
  if IsDynArrayText(Text) then
    Result := TAccessLinkKind.DynArray
  else if IsPointerText(Text) then
    Result := TAccessLinkKind.Pointer
  else if (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.Dereference) then
    Result := TAccessLinkKind.Pointer;
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
    Text := AliasText(BaseType)
  else
    Text := Symbol.TypeName;
  Text := Trim(Text);
  if LowerCase(Text).StartsWith('array of') then
    Text := Trim(Copy(Text, 9, MaxInt))
  else if LowerCase(Text).StartsWith('tarray<') and Text.EndsWith('>') then
    Text := Trim(Copy(Text, 8, Length(Text) - 8))
  else
    Exit;
  if not (Found and UnitFor(BaseType, FromUnit)) then
    FromUnit := FResolver.ExtractedUnit(FTree, FFileName);
  Result := FResolver.ResolveTypeTextFrom(FromUnit, Text, AType);
end;

function TCollector.IsCallLink(ANode: TSyntaxNode; const ASymbol: TResolvedSymbol): Boolean;
var
  ReadsField: Boolean;
begin
  if ANode.Kind = TSyntaxKind.Call then
    Exit(True);
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
        Plain := False
      else if AChild.Kind = TSyntaxKind.Identifier then
      begin
        Symbol := FResolver.Resolve(FTree, FFileName, AChild.StartPos);
        if not ((Symbol.Kind = TResolvedKind.Local) or (Symbol.SymbolKind in [TIndexSymbolKind.Variable,
          TIndexSymbolKind.Field, TIndexSymbolKind.Constant, TIndexSymbolKind.EnumMember])) then
          Plain := False;
      end;
      Result := Plain;
    end);
  Result := Plain;
end;

function TCollector.ImplicitSelf(ARoot: TSyntaxNode; out ALink: TAccessLink): Boolean;
var
  Symbol, ClassType: TResolvedSymbol;
  With_: TSyntaxNode;
  Element: Integer;
  Unknown: Boolean;
begin
  ALink := Default(TAccessLink);
  Result := False;
  if (ARoot.Kind <> TSyntaxKind.Identifier) or SameText(ARoot.Name, 'Self') then
    Exit;
  Symbol := FResolver.Resolve(FTree, FFileName, ARoot.StartPos);
  if (Symbol.Kind <> TResolvedKind.Symbol) or (Symbol.Container = '') or
    not (Symbol.SymbolKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Method]) then
    Exit;
  // In with gehört der Name vielleicht zu einem Element, nicht zu Self.
  if FResolver.WithMember(FTree, FFileName, ARoot.Name, ARoot.StartOffset, With_, Element, Unknown) or Unknown then
    Exit;
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
    ALink.Fields := FieldsOf(ClassType);
  Result := True;
end;

procedure TCollector.AddChain(ATop: TSyntaxNode; AWithElement: Boolean);
var
  Path: TList<TSyntaxNode>;
  Node, Next: TSyntaxNode;
  Chain: TAccessChain;
  Link: TAccessLink;
  Symbol, AType: TResolvedSymbol;
  TypeFound, Called, WithLast: Boolean;
  Index, Last: Integer;
begin
  if FChains.Count >= TLspAccessChains.MaxChains then
    Exit;
  Path := TList<TSyntaxNode>.Create;
  try
    Node := ATop;
    while Node <> nil do
    begin
      Path.Insert(0, Node);
      if (Node.Kind in ChainKinds) and (Node.ChildCount > 0) then
        Node := Node[0]
      else
        Node := nil;
    end;
    Chain := Default(TAccessChain);
    Chain.Text := TextOf(ATop);
    Called := False;
    if ImplicitSelf(Path[0], Link) then
      Chain.Links := Chain.Links + [Link];
    Last := Path.Count - 2;
    if AWithElement then
      Last := Path.Count - 1;
    for Index := 0 to Last do
    begin
      Node := Path[Index];
      // Beim with-Element steht hinter dem letzten Glied kein Knoten; es zählt wie ein Mitgliedszugriff.
      WithLast := Index = Path.Count - 1;
      if WithLast then
        Next := Node
      else
        Next := Path[Index + 1];
      // Der Name vor einem Aufruf ist kein Wert; der Aufruf selbst ist das Glied.
      if (not WithLast) and (Next.Kind = TSyntaxKind.Call) and (Next[0] = Node) and
        (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
        Continue;
      // Literale und inherited sind nie nil; X^ ist der Wert hinter dem schon geprüften Zeiger.
      if Node.Kind in [TSyntaxKind.Literal, TSyntaxKind.InheritedExpr, TSyntaxKind.Dereference] then
        Continue;
      Symbol := Default(TResolvedSymbol);
      AType := Default(TResolvedSymbol);
      TypeFound := False;
      if Node.Kind <> TSyntaxKind.ParenExpr then
        FResolver.NodeType(FTree, FFileName, Node, Symbol, AType, TypeFound);
      // Element eines dynamischen Arrays: Typ aus der Deklaration des Arrays.
      if (Node.Kind = TSyntaxKind.IndexAccess) and not TypeFound and (Node.ChildCount > 0) then
        TypeFound := ElementType(Node[0], AType);
      // Self liefert die Klasse selbst.
      if (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, 'Self') and Symbol.IsType then
      begin
        AType := Symbol;
        TypeFound := True;
        Symbol := Default(TResolvedSymbol);
        Symbol.Kind := TResolvedKind.Local;
      end;
      // Nicht auflösbare Namen (etwa Unit-Präfixe ohne Index): nichts zu sagen.
      if (Node.Kind = TSyntaxKind.Identifier) and not Symbol.Found and not TypeFound then
        Continue;
      // Unit- und Typnamen, Konstanten und Aufzählungswerte sind keine Werte, die nil sein können.
      if (Symbol.Kind = TResolvedKind.UnitName) or Symbol.IsType or
        (Symbol.SymbolKind in [TIndexSymbolKind.Constant, TIndexSymbolKind.EnumMember]) then
        Continue;
      Link := Default(TAccessLink);
      Link.Expression := TextOf(Node);
      Link.Name := NameOf(Node);
      Link.Range := TTextRange.Create(Node.StartPos, Node.EndPos);
      Link.NamePosition := NamePositionOf(Node);
      Link.Kind := KindOf(Symbol, AType, TypeFound, Node);
      // Records und andere Werte werden nicht dereferenziert (außer über ^, dann ist es ein Zeiger).
      if TypeFound and (AType.SymbolKind in [TIndexSymbolKind.RecordType, TIndexSymbolKind.ObjectType,
        TIndexSymbolKind.EnumType]) and (WithLast or (Next.Kind <> TSyntaxKind.Dereference)) then
        Continue;
      if (not TypeFound) and (Symbol.TypeName <> '') and (BuiltinSize(Symbol.TypeName, FPointerSize) > 0) and
        (Link.Kind = TAccessLinkKind.Unknown) then
        Continue;
      if TypeFound then
        Link.TypeName := AType.Name
      else
        Link.TypeName := Symbol.TypeName;
      Called := Called or IsCallLink(Node, Symbol);
      Link.Call := Called;
      if WithLast then
        Link.Member := 'with'
      else
        Link.Member := MemberAfter(Next);
      if (not WithLast) and (Link.Kind = TAccessLinkKind.DynArray) and (Next.Kind = TSyntaxKind.IndexAccess) and
        (Next.ChildCount = 2) then
      begin
        Link.IndexText := TextOf(Next[1]);
        Link.IndexPlain := PlainIndex(Next[1]);
      end;
      if (Link.Kind = TAccessLinkKind.ClassRef) and TypeFound then
        Link.Fields := FieldsOf(AType);
      Chain.Links := Chain.Links + [Link];
    end;
    if Chain.Links <> nil then
      FChains.Add(Chain);
  finally
    Path.Free;
  end;
end;

procedure TCollector.Visit(ANode: TSyntaxNode; AAsBase: Boolean);
var
  Index: Integer;
  Link: TAccessLink;
  Chain: TAccessChain;
begin
  if ANode = nil then
    Exit;
  // Rümpfe anonymer Methoden laufen hier nicht.
  if ANode.Kind = TSyntaxKind.AnonymousMethod then
    Exit;
  if (ANode.Kind in ChainKinds) and not AAsBase then
    AddChain(ANode, False)
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
    Visit(ANode[Index], (Index = 0) and (ANode.Kind in ChainKinds));
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
    Exit;
  AddChain(ANode, True);
  // Ausdrücke im Element (Argumente, Indizes) wie sonst.
  if ANode.Kind in ChainKinds then
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index], Index = 0);
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

class function TLspAccessChains.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; ATree: TSyntaxTree; const AText, AFileName: string; ALine,
  APointerSize: Integer): TAccessChainsResult;
var
  Collector: TCollector;
  Count: Integer;
begin
  Result := Default(TAccessChainsResult);
  if (APointerSize <> 4) and (APointerSize <> 8) then
    APointerSize := 4;
  Count := 0;
  Collector := TCollector.Create(AResolver, AIndex, AReadText, ATree, AText, AFileName, APointerSize);
  AResolver.PinTree(ATree, AFileName);
  try
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        Index: Integer;
        Child: TSyntaxNode;
        Counted: Boolean;
      begin
        Result := ANode.Kind <> TSyntaxKind.AnonymousMethod;
        if not Result then
          Exit;
        if (ANode.Kind in SimpleStatements) and (ANode.StartPos.Line = ALine) then
        begin
          Inc(Count);
          for Index := 0 to ANode.ChildCount - 1 do
            if ANode[Index].Kind in ExpressionKinds then
              Collector.VisitExpression(ANode[Index]);
        end
        else if ANode.Kind in CompoundStatements then
        begin
          Counted := False;
          for Index := 0 to ANode.ChildCount - 1 do
          begin
            Child := ANode[Index];
            if (Child.Kind in ExpressionKinds) and (Child.StartPos.Line = ALine) then
            begin
              if not Counted then
                Inc(Count);
              Counted := True;
              if ANode.Kind = TSyntaxKind.WithStatement then
                Collector.VisitWithElement(Child)
              else
                Collector.VisitExpression(Child);
            end;
          end;
        end;
      end);
    Result.Statements := Count;
    Result.Chains := Collector.Chains;
  finally
    AResolver.UnpinTree;
    Collector.Free;
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
  Cancellation: IPascalCancellation;
  Uri: string;
  Line, PointerSize: Integer;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<Integer>('line', Line)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "line" fehlen in ' + Method);
  if not TJSONObject(AParams).TryGetValue<Integer>('pointerSize', PointerSize) then
    PointerSize := 4;
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  ACancellation.ThrowIfCancellationRequested;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := Namespaces;
    Result := ToJson(Collect(Resolver, FIndex, FReadText, Shared.Tree, Document.GetText, TDocumentUris.ToPath(Uri),
      Line, PointerSize));
  finally
    Resolver.Free;
  end;
end;

end.
