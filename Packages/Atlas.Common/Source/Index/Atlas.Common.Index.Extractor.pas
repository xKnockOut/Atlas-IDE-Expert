unit Atlas.Common.Index.Extractor;

// Liest aus dem Syntaxbaum einer Unit die Einträge für den Symbolindex:
// Typen mit Mitgliedern und Vorfahren, Konstanten, Variablen, Routinen und
// die uses-Listen. Lokale Deklarationen in Routinen gehören nicht dazu.
//
// Vor dem Parsen werden die inaktiven Zweige der bedingten Kompilierung
// durch Leerzeichen ersetzt (Zeilenumbrüche bleiben), damit nur aktive
// Deklarationen erscheinen und alle Positionen stimmen.
//
// Mit Include-Auflösung kommen die Deklarationen aktiver $I-Dateien dazu
// (#500): Jede Datei wird für sich geparst (ein Fragment ohne unit-Kopf
// liefert seine Deklarationen), ihre Symbole tragen die .inc als FileName
// und zählen zum Abschnitt, in dem die Direktive steht. Steht die Direktive
// mitten in einem type-, const- oder var-Abschnitt und beginnt die Datei
// nicht selbst mit einem Abschnitt, wird das Schlüsselwort vorangestellt.
// Zyklen und zu tiefe Verschachtelung überspringt der Extractor; die
// Diagnose dazu kommt aus dem Präprozessor.
//
// Vorwärtsdeklarationen (TFoo = class;) erscheinen nur, wenn die Unit den Typ
// nicht vollständig deklariert. Sonst fänden Hover, Vererbungskette und
// Gehe zu Definition die Vorwärtsdeklaration (ohne Vorfahren) statt des Typs.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Index.Contract;

type
  TIndexExtractor = class
  private
    FTokens: TArray<TPascalToken>;
    FSymbols: TList<TIndexSymbol>;
    FInInterface: Boolean;
    FVisibility: TIndexVisibility;
    // Typargumente der Vorfahren für den nächsten Add aus AddType.
    FAncestorArgs: TArray<string>;
    // Der nächste Add aus AddType ist eine Vorwärtsdeklaration; FForwards hält deren Nummern in FSymbols.
    FForward: Boolean;
    /// <summary>Zweig des varianten Record-Teils, in dem AddMembers gerade steht (#846).</summary>
    FVariant: string;
    /// <summary>AddMembers steht in einem Abschnitt "class var" (#1001).</summary>
    FClassVar: Boolean;
    FForwards: TList<Integer>;
    /// <summary>Der nächste Add gehört zu einer Aufzählung unter {$SCOPEDENUMS ON} (#849).</summary>
    FScoped: Boolean;
    /// <summary>Stellen der {$SCOPEDENUMS}-Schalter in FTokens (Offset, ON?); FScopedKnown nach dem ersten Lesen.
    /// </summary>
    FScopedOffsets: TArray<Integer>;
    FScopedOn: TArray<Boolean>;
    FScopedKnown: Boolean;
    /// <summary>Nummer des Typs in FSymbols, dessen Rumpf AddMembers gerade liest; -1 ohne. Methodenzuordnungen
    /// landen in seinen Resolutions.</summary>
    FResolutionOwner: Integer;
    /// <summary>Gilt {$SCOPEDENUMS ON} an AOffset?</summary>
    function ScopedAt(AOffset: Integer): Boolean;
    function IsDefaultProperty(ANode: TSyntaxNode): Boolean;
    /// <summary>Methodenkopf mit virtual, dynamic, abstract oder override?</summary>
    class function IsVirtualHeader(ANode: TSyntaxNode): Boolean; static;
    function TokenIndexAt(AOffset: Integer): Integer;
    function NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
    function IsConstructor(ANode: TSyntaxNode): Boolean;
    /// <summary>Beginnt die Deklaration mit "class" oder steht "class" direkt davor ("class property",
    /// "class var" vor dem var-Abschnitt)?</summary>
    function IsClassMember(ANode: TSyntaxNode): Boolean;
    procedure Add(ANode: TSyntaxNode; const AName, AContainer: string; AKind: TIndexSymbolKind;
      const AAncestors: TArray<string> = nil);
    /// <summary>Tokens AFrom..ATo (ohne Kommentare und Compiler-Direktiven) als eine Zeile; mit
    /// AFirstLine endet der Text am Ende der ersten Zeile außerhalb von Klammern.</summary>
    function TokenText(AFrom, ATo: Integer; AFirstLine: Boolean): string;
    function SignatureOf(ANode: TSyntaxNode; AKind: TIndexSymbolKind; const AName, ATypeText: string): string;
    /// <summary>Prozedurtyp, den die Typdeklaration ANode deklariert (TEreignis = procedure … of object); nil bei
    /// anderen Typen.</summary>
    class function ProcedureTypeOf(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Art des Prozedurtyps AType (#1326): 'of object' bei Methodenzeigern, 'reference to' bei
    /// Methodenreferenzen, sonst ''. Gelesen aus den Tokens, also unabhängig von Zeilenumbrüchen.</summary>
    function ProcedureKindOf(AType: TSyntaxNode): string;
    /// <summary>Direktiven der Deklaration; ADeprecatedText: Grund hinter deprecated 'Grund' (#38), sonst ''.
    /// </summary>
    function DirectivesOf(ANode: TSyntaxNode; AKind: TIndexSymbolKind; out ADeprecatedText: string): TArray<string>;
    function SummaryOf(ANode: TSyntaxNode): string;
    procedure AddNames(ANode: TSyntaxNode; const AContainer: string; AKind: TIndexSymbolKind);
    procedure AddType(ADecl: TSyntaxNode; const AContainer: string);
    /// <summary>Hängt die Methodenzuordnung AHeader als "IFoo.Bar=Baz" an die Resolutions des Typs an.</summary>
    procedure AddResolution(AHeader: TSyntaxNode);
    procedure AddMembers(ABody: TSyntaxNode; const AContainer: string);
    procedure AddDeclarations(ANode: TSyntaxNode);
    procedure AddRoutine(ANode: TSyntaxNode);
    /// <summary>Vorwärtsdeklarationen entfernen, deren Typ in der Unit vollständig deklariert ist.</summary>
    procedure DropForwards;
    /// <summary>Verweise des Rumpfs ANode einer inline-Routine (#1017), siehe TIndexSymbol.InlineRefs; nil, wenn
    /// die Routine nicht einbettbar ist. AContainer: Klasse der Methode, '' bei freien Routinen.</summary>
    function InlineRefsOf(ANode: TSyntaxNode; const AContainer, AContainerParams: string): TArray<string>;
    /// <summary>Trägt InlineRefs an Deklaration und Implementierung der inline-Routinen aus ASection ein.</summary>
    procedure AddInlineRefs(ASection: TSyntaxNode);
    /// <summary>Typparameter des Typs AContainer (TList&lt;T&gt; → 'T'), '' ohne.</summary>
    function ContainerParams(const AContainer: string): string;
    procedure SetInlineRefs(APosition: Integer; const ARefs: TArray<string>);
    /// <summary>Hinweise zwischen unit Name und ";" (#1018).</summary>
    procedure AddUnitHints(var AUnit: TUnitIndex);
    procedure Walk(ARoot: TSyntaxNode; var AUnit: TUnitIndex);
    class function UsesOf(ASection: TSyntaxNode): TArray<string>; static;
    class function ExtractLevel(const AText, AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver; const AStack: TArray<string>; AUsages: Boolean): TUnitIndex; static;
    class procedure AddIncluded(ATree: TSyntaxTree; const AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver; const AStack: TArray<string>; var AUnit: TUnitIndex); static;
  public
    /// <summary>Erster direkter Typverweis eines Knotens (A: TFoo, function F: TFoo); sonst ''.</summary>
    class function DeclaredType(ANode: TSyntaxNode): string; static;
    /// <summary>Knoten des ersten direkten Typverweises; sonst nil.</summary>
    class function DeclaredTypeNode(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Typ als Text samt Typargumenten: TDictionary&lt;string, TList&lt;TKunde&gt;&gt; (#263).</summary>
    class function TypeText(ANode: TSyntaxNode): string; static;
    /// <summary>Typargumente eines Typverweises kommagetrennt ('' ohne).</summary>
    class function GenericArgsText(ATypeRef: TSyntaxNode): string; static;
    /// <summary>Typparameter aus GenericParams eines Knotens kommagetrennt ('' ohne).</summary>
    class function TypeParamsOf(ANode: TSyntaxNode): string; static;
    /// <summary>Parameterzahlen und -typen eines Routinenkopfs oder einer indizierten Property.</summary>
    class procedure ParamInfo(ANode: TSyntaxNode; out AMin, AMax: Integer; out ATypes: TArray<string>); static;
    constructor Create(const ATokens: TArray<TPascalToken>);
    destructor Destroy; override;
    /// <summary>Index-Eintrag aus einem fertigen Syntaxbaum (ohne Stamp und Hash).</summary>
    class function Extract(ATree: TSyntaxTree; const AFileName: string): TUnitIndex; static;
    /// <summary>Parst AText mit den aktiven Symbolen ADefines und liefert den Eintrag. Mit AResolver werden
    /// $I-Dateien gelesen (#264): ihre $DEFINEs gelten, Includes listet sie auf. Mit AUsages kommen die
    /// Verwendungen der Bezeichner dazu (#492).</summary>
    class function ExtractText(const AText, AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver = nil; AUsages: Boolean = False): TUnitIndex; static;
    /// <summary>Verwendungen aller Bezeichner in ATokens außer an den Deklarationsstellen von ASymbols
    /// (#492), nach Name sortiert; Schlüsselwörter, Direktiven, Self und Result zählen nicht.</summary>
    class function CollectUsages(const ATokens: TArray<TPascalToken>;
      const ASymbols: TArray<TIndexSymbol>): TArray<TIndexUsage>; static;
    /// <summary>Ersetzt inaktive Zweige durch Leerzeichen; Zeilen und Spalten bleiben erhalten.</summary>
    class function BlankInactive(const AText: string; const ADefines: TArray<string>): string; overload; static;
    /// <summary>Wie oben, mit Include-Auflösung; AIncludes erhält die eingebundenen Dateien.</summary>
    class function BlankInactive(const AText, AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver; out AIncludes: TArray<string>): string; overload; static;
    /// <summary>Wie oben, zusätzlich die bedingten Zweige der Hauptdatei (#476).</summary>
    class function BlankInactive(const AText, AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver; out AIncludes: TArray<string>;
      out AConditionals: TArray<TConditionalRange>): string; overload; static;
    /// <summary>Bedingungen an die Symbole schreiben und Deklarationen aus nicht geltenden Zweigen
    /// als Unavailable erfassen (#476).</summary>
    class procedure AnnotateConditions(var AUnit: TUnitIndex; const AText: string;
      const AConditionals: TArray<TConditionalRange>); static;
    /// <summary>Beginnt AName mit APrefix vor einem Großbuchstaben (FName, AValue, LIndex)?</summary>
    class function HasNamePrefix(const AName, APrefix: string): Boolean; static;
    /// <summary>Felder (auch in Records und var-Abschnitten von Klassen), Parameter und lokale Variablen
    /// (var-Abschnitte von Routinen und Inline-Variablen) unter ARoot, gezählt mit Präfix (#452).</summary>
    class function NamingOf(ARoot: TSyntaxNode): TNamingCounts; static;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  System.RegularExpressions,
  System.Generics.Defaults,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rationale.Contract,
  Atlas.Common.Rationale.Scanner,
  Atlas.Text.Lines;

const
  // Direktiven nach Routinenköpfen und Hinweise (wie im Parser); zählen nicht als Verwendung.
  DirectiveWords: array[0..32] of string = (
    'abstract', 'assembler', 'cdecl', 'deprecated', 'dispid', 'dynamic', 'experimental',
    'export', 'external', 'far', 'final', 'forward', 'inline', 'library', 'local',
    'near', 'noreturn', 'overload', 'override', 'pascal', 'platform',
    'register', 'reintroduce', 'safecall', 'static', 'stdcall', 'unsafe', 'varargs',
    'virtual', 'winapi', 'delayed', 'sealed', 'nodefault');
  HintDirectives: array[0..3] of string = ('deprecated', 'platform', 'library', 'experimental');

function VisibilityOf(const AText: string): TIndexVisibility;
var
  Text: string;
begin
  Text := LowerCase(Trim(AText));
  if Text = 'strict private' then
    Result := TIndexVisibility.StrictPrivate
  else if Text = 'private' then
    Result := TIndexVisibility.Private
  else if Text = 'strict protected' then
    Result := TIndexVisibility.StrictProtected
  else if Text = 'protected' then
    Result := TIndexVisibility.Protected
  else if Text = 'published' then
    Result := TIndexVisibility.Published
  else
    Result := TIndexVisibility.Public;
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function FileNameToUnitName(const AFileName: string): string;
var
  Start, Stop: Integer;
begin
  Start := LastDelimiter('\/', AFileName) + 1;
  Stop := LastDelimiter('.', AFileName);
  if Stop < Start then
    Stop := Length(AFileName) + 1;
  Result := Copy(AFileName, Start, Stop - Start);
end;

{ TIndexExtractor }

constructor TIndexExtractor.Create(const ATokens: TArray<TPascalToken>);
begin
  inherited Create;
  FTokens := ATokens;
  FSymbols := TList<TIndexSymbol>.Create;
  FForwards := TList<Integer>.Create;
  FResolutionOwner := -1;
end;

destructor TIndexExtractor.Destroy;
begin
  FForwards.Free;
  FSymbols.Free;
  inherited;
end;

function TIndexExtractor.TokenIndexAt(AOffset: Integer): Integer;
var
  Left, Right, Middle: Integer;
begin
  Left := 0;
  Right := Length(FTokens);
  while Left < Right do
  begin
    Middle := (Left + Right) div 2;
    if FTokens[Middle].Offset < AOffset then
      Left := Middle + 1
    else
      Right := Middle;
  end;
  Result := Left;
end;

function TIndexExtractor.ScopedAt(AOffset: Integer): Boolean;
var
  Token: TPascalToken;
  Text: string;
  Index: Integer;
begin
  if not FScopedKnown then
  begin
    FScopedKnown := True;
    for Token in FTokens do
      if Token.Kind = TPascalTokenKind.Directive then
      begin
        Text := UpperCase(Token.Text);
        if Text.StartsWith('{$SCOPEDENUMS') or Text.StartsWith('(*$SCOPEDENUMS') then
        begin
          Text := Trim(Copy(Text, Pos('SCOPEDENUMS', Text) + Length('SCOPEDENUMS'), MaxInt));
          FScopedOffsets := FScopedOffsets + [Token.Offset];
          FScopedOn := FScopedOn + [Text.StartsWith('ON')];
        end;
      end;
  end;
  Result := False;
  for Index := 0 to High(FScopedOffsets) do
    if FScopedOffsets[Index] < AOffset then
      Result := FScopedOn[Index]
    else
      Break;
end;

function TIndexExtractor.NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
var
  Index: Integer;
begin
  Index := TokenIndexAt(ANode.StartOffset);
  while (Index < Length(FTokens)) and (FTokens[Index].Offset < ANode.EndOffset) do
  begin
    if (FTokens[Index].Kind = TPascalTokenKind.Identifier) and
      (SameText(FTokens[Index].Text, AName) or SameText(FTokens[Index].Text, '&' + AName)) then
      Exit(TTextRange.Create(FTokens[Index].StartPos, FTokens[Index].EndPos));
    Inc(Index);
  end;
  Result := NodeRange(ANode);
end;

function TIndexExtractor.IsConstructor(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := TokenIndexAt(ANode.StartOffset);
  while (Index < Length(FTokens)) and (FTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Inc(Index);
  if (Index < Length(FTokens)) and FTokens[Index].IsKeyword('class') then
    Inc(Index);
  Result := (Index < Length(FTokens)) and
    (FTokens[Index].IsKeyword('constructor') or FTokens[Index].IsKeyword('destructor'));
end;

function TIndexExtractor.IsClassMember(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := TokenIndexAt(ANode.StartOffset);
  while (Index < Length(FTokens)) and (FTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Inc(Index);
  if (Index < Length(FTokens)) and FTokens[Index].IsKeyword('class') then
    Exit(True);
  Index := TokenIndexAt(ANode.StartOffset) - 1;
  while (Index >= 0) and (FTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Dec(Index);
  if (Index < 0) or not FTokens[Index].IsKeyword('class') then
    Exit(False);
  // "TFoo = class" bzw. "= packed class" direkt vor dem ersten Mitglied ist der Typ selbst.
  Dec(Index);
  while (Index >= 0) and (FTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Dec(Index);
  Result := (Index >= 0) and not FTokens[Index].IsSymbol('=') and not FTokens[Index].IsKeyword('packed');
end;

/// <summary>Höchstens TRationale.MaxEntries Begründungen für den Index.</summary>
function RationaleOf(const AEntries: TArray<TRationaleEntry>): TArray<string>;
begin
  Result := TRationale.EncodeAll(Copy(AEntries, 0, TRationale.MaxEntries));
end;

procedure TIndexExtractor.Add(ANode: TSyntaxNode; const AName, AContainer: string; AKind: TIndexSymbolKind;
  const AAncestors: TArray<string>);
var
  Symbol: TIndexSymbol;
  TypeText_, mProcedureKind: string;
begin
  if AName = '' then
    Exit;
  // Der Index führt die Namen ohne Escape-&, wie die Namensauflösung sie sucht (#1137).
  Symbol.Name := TPascalLexer.PlainName(AName);
  Symbol.Container := TPascalLexer.PlainName(AContainer);
  Symbol.Kind := AKind;
  Symbol.Range := NodeRange(ANode);
  Symbol.SelectionRange := NameRange(ANode, Symbol.Name);
  Symbol.InInterface := FInInterface;
  Symbol.Ancestors := AAncestors;
  Symbol.TypeArgs := '';
  if AKind in [TIndexSymbolKind.TypeAlias, TIndexSymbolKind.Constant, TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
    TIndexSymbolKind.Property_, TIndexSymbolKind.Method, TIndexSymbolKind.Routine] then
  begin
    Symbol.TypeName := DeclaredType(ANode);
    // type AnsiString(Codepage) ist ein eigener Stringtyp (RawByteString, UTF8String): Die Namensauflösung darf
    // ihn nicht bis AnsiString verfolgen, sonst meldet z. B. suspicious-string-pointer-cast "R ist AnsiString".
    if (AKind = TIndexSymbolKind.TypeAlias) and SameText(Symbol.TypeName, 'AnsiString') and
      (DeclaredTypeNode(ANode).ChildCount > 0) then
      Symbol.TypeName := '';
    if Symbol.TypeName <> '' then
      Symbol.TypeArgs := GenericArgsText(DeclaredTypeNode(ANode));
  end
  else
    Symbol.TypeName := '';
  // Erweiterungen für die Namensauflösung, Stufe 2 (#263).
  Symbol.AncestorArgs := FAncestorArgs;
  Symbol.TypeParams := TypeParamsOf(ANode);
  if (AContainer <> '') and (AKind <> TIndexSymbolKind.EnumMember) then
    Symbol.Visibility := FVisibility
  else
    Symbol.Visibility := TIndexVisibility.Public;
  Symbol.MinArgs := 0;
  Symbol.MaxArgs := 0;
  Symbol.ParamTypes := nil;
  Symbol.IsDefault := False;
  if AKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine,
    TIndexSymbolKind.Property_] then
    ParamInfo(ANode, Symbol.MinArgs, Symbol.MaxArgs, Symbol.ParamTypes);
  if AKind = TIndexSymbolKind.Property_ then
    Symbol.IsDefault := IsDefaultProperty(ANode);
  Symbol.IsVirtual := (AKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and IsVirtualHeader(ANode);
  Symbol.FileName := '';
  if FForward then
    FForwards.Add(FSymbols.Count);
  Symbol.Condition := '';
  Symbol.Unavailable := False;
  Symbol.VariantBranch := FVariant;
  Symbol.ScopedEnum := FScoped;
  // Inhalt für Hover, Detailpanel und Verwendungen ohne erneutes Lesen der Datei (#492).
  TypeText_ := '';
  if Symbol.TypeName <> '' then
    TypeText_ := TypeText(DeclaredTypeNode(ANode));
  Symbol.Signature := SignatureOf(ANode, AKind, AName, TypeText_);
  Symbol.Directives := DirectivesOf(ANode, AKind, Symbol.DeprecatedText);
  if Symbol.IsDefault and (IndexText('default', Symbol.Directives) < 0) then
    Symbol.Directives := Symbol.Directives + ['default'];
  // Methodenzeiger und Methodenreferenzen als Merkmal (#1326): Die Signatur kann bei langen Parameterlisten
  // vor "of object" abgeschnitten sein (TIndexSymbol.MaxSignature).
  if AKind = TIndexSymbolKind.TypeAlias then
  begin
    mProcedureKind := ProcedureKindOf(ProcedureTypeOf(ANode));
    if mProcedureKind <> '' then
      Symbol.Directives := Symbol.Directives + [mProcedureKind];
  end;
  // Klassenmitglieder (class var, class property, class function) tragen "class" vorn, damit Regeln wie
  // property-accessor-invalid (#1001) sie ohne die Datei erkennen.
  if (AContainer <> '') and (((AKind = TIndexSymbolKind.Field) and FClassVar) or
    ((AKind in [TIndexSymbolKind.Property_, TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and
    IsClassMember(ANode))) then
    Symbol.Directives := ['class'] + Symbol.Directives;
  Symbol.Summary := SummaryOf(ANode);
  Symbol.Rationale := RationaleOf(TRationaleScanner.ForNode(FTokens, ANode));
  FSymbols.Add(Symbol);
end;

function TIndexExtractor.TokenText(AFrom, ATo: Integer; AFirstLine: Boolean): string;
const
  NoSpaceBefore: array[0..9] of string = (';', ',', ')', ']', ':', '.', '(', '[', '^', '>');
  NoSpaceAfter: array[0..4] of string = ('(', '[', '.', '<', '@');
var
  Builder: TStringBuilder;
  Index, Depth, FirstLine: Integer;
  Token: TPascalToken;
  Previous, IncludeName: string;
begin
  Builder := TStringBuilder.Create;
  try
    Depth := 0;
    FirstLine := -1;
    Previous := '';
    for Index := AFrom to ATo do
    begin
      if (Index < 0) or (Index >= Length(FTokens)) then
        Continue;
      Token := FTokens[Index];
      // {$I datei.inc} als Wert (#849) bleibt stehen; AddIncluded setzt den Inhalt ein.
      if (Token.Kind = TPascalTokenKind.Comment) or
        ((Token.Kind = TPascalTokenKind.Directive) and
        not TPascalPreprocessor.IncludeFileOf(Token.Text, IncludeName)) then
        Continue;
      if FirstLine < 0 then
        FirstLine := Token.StartPos.Line;
      if AFirstLine and (Depth = 0) and (Token.StartPos.Line > FirstLine) then
        Break;
      // ":" vor "=" (Zuweisung im Standardwert) bleibt ein Wort.
      if (Builder.Length > 0) and (Token.Text <> '') then
        if not ((Token.Kind = TPascalTokenKind.Symbol) and (IndexStr(Token.Text, NoSpaceBefore) >= 0)) and
          (IndexStr(Previous, NoSpaceAfter) < 0) then
          Builder.Append(' ');
      // Ein Doppelpunkt trennt Name und Typ: "A: Integer".
      Builder.Append(Token.Text);
      if Token.Kind = TPascalTokenKind.Symbol then
      begin
        if (Token.Text = '(') or (Token.Text = '[') then
          Inc(Depth)
        else if ((Token.Text = ')') or (Token.Text = ']')) and (Depth > 0) then
          Dec(Depth);
      end;
      Previous := Token.Text;
      if Builder.Length > TIndexSymbol.MaxSignature then
        Break;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
  if Length(Result) > TIndexSymbol.MaxSignature then
    Result := Copy(Result, 1, TIndexSymbol.MaxSignature - 1) + '…';
end;

function TIndexExtractor.SignatureOf(ANode: TSyntaxNode; AKind: TIndexSymbolKind;
  const AName, ATypeText: string): string;
var
  Node, TypeRef: TSyntaxNode;
  First, Last: Integer;
  Suffix: string;
begin
  Node := ANode;
  if (Node.Kind = TSyntaxKind.RoutineDecl) and (Node.FindChild(TSyntaxKind.RoutineHeader) <> nil) then
    Node := Node.FindChild(TSyntaxKind.RoutineHeader);
  case AKind of
    TIndexSymbolKind.EnumMember:
      Exit(AName);
    TIndexSymbolKind.Field, TIndexSymbolKind.Variable:
      // A, B: Integer: je Name eine eigene Signatur.
      if ATypeText <> '' then
      begin
        // string[8]: Die Länge gehört zur Signatur (Anzeige, string-length-limit #1036); der Typname bleibt
        // string, damit die Namensauflösung ihn findet.
        Suffix := '';
        TypeRef := DeclaredTypeNode(ANode);
        if (TypeRef <> nil) and SameText(TypeRef.Name, 'string') and (TypeRef.ChildCount = 1) and
          (TypeRef[0].Kind <> TSyntaxKind.GenericArgs) then
          Suffix := '[' + TokenText(TokenIndexAt(TypeRef[0].StartOffset), TokenIndexAt(TypeRef[0].EndOffset) - 1,
            False) + ']';
        Exit(AName + ': ' + ATypeText + Suffix);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  First := TokenIndexAt(Node.StartOffset);
  Last := TokenIndexAt(Node.EndOffset) - 1;
  // Ein Prozedurtyp über mehrere Zeilen gehört ganz in die Signatur, sonst fehlt "of object" (#1326).
  Result := TokenText(First, Last, (AKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
    TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType,
    TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias]) and
    not ((AKind = TIndexSymbolKind.TypeAlias) and (ProcedureTypeOf(Node) <> nil)));
  // Ein abschließendes Semikolon gehört nicht zur Anzeige.
  while Result.EndsWith(';') do
    Result := Copy(Result, 1, Length(Result) - 1).TrimRight;
end;

class function TIndexExtractor.ProcedureTypeOf(ANode: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  if (ANode = nil) or (ANode.Kind <> TSyntaxKind.TypeDecl) then
    Exit;
  // Rumpf ist das erste Kind außer Typparametern und Attributen (wie in AddType).
  for mIndex := 0 to ANode.ChildCount - 1 do
    if not (ANode[mIndex].Kind in [TSyntaxKind.GenericParams, TSyntaxKind.Attribute]) then
    begin
      if ANode[mIndex].Kind = TSyntaxKind.ProcedureType then
        Result := ANode[mIndex];
      Exit;
    end;
end;

function TIndexExtractor.ProcedureKindOf(AType: TSyntaxNode): string;
var
  mIndex, mLast, mDepth: Integer;
  mToken: TPascalToken;
begin
  Result := '';
  if AType = nil then
    Exit;
  if SameText(AType.Name, 'reference') then
    Exit('reference to');
  mDepth := 0;
  mLast := TokenIndexAt(AType.EndOffset) - 1;
  mIndex := TokenIndexAt(AType.StartOffset);
  while mIndex < mLast do
  begin
    mToken := FTokens[mIndex];
    if mToken.Kind = TPascalTokenKind.Symbol then
    begin
      if (mToken.Text = '(') or (mToken.Text = '[') then
        Inc(mDepth)
      else if ((mToken.Text = ')') or (mToken.Text = ']')) and (mDepth > 0) then
        Dec(mDepth);
    end
    else if (mDepth = 0) and mToken.IsKeyword('of') then
    begin
      // Kommentare und Direktiven zwischen "of" und "object" überspringen.
      Inc(mIndex);
      while (mIndex <= mLast) and (FTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
        Inc(mIndex);
      if (mIndex <= mLast) and SameText(FTokens[mIndex].Text, 'object') then
        Result := 'of object';
      Exit;
    end;
    Inc(mIndex);
  end;
end;

function TIndexExtractor.DirectivesOf(ANode: TSyntaxNode; AKind: TIndexSymbolKind;
  out ADeprecatedText: string): TArray<string>;
var
  Node: TSyntaxNode;
  Index, Last: Integer;
  Word: string;

  procedure AddWord(const AWord: string);
  begin
    if IndexText(AWord, Result) < 0 then
      Result := Result + [LowerCase(AWord)];
  end;

  function IsHintAt(APos: Integer): Boolean;
  begin
    Result := (APos >= 0) and (APos < Length(FTokens)) and
      (FTokens[APos].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      (IndexText(FTokens[APos].Text, HintDirectives) >= 0);
  end;

  function NextCode(APos: Integer): Integer;
  begin
    Result := APos + 1;
    while (Result < Length(FTokens)) and (FTokens[Result].Kind in [TPascalTokenKind.Comment,
      TPascalTokenKind.Directive]) do
      Inc(Result);
  end;

  // Grund hinter deprecated am Token APos: deprecated 'Stattdessen Bar verwenden'.
  procedure TakeReason(APos: Integer);
  var
    Next: Integer;
    Text: string;
  begin
    if (APos < 0) or (APos >= Length(FTokens)) or not SameText(FTokens[APos].Text, 'deprecated') then
      Exit;
    Next := NextCode(APos);
    if (Next >= Length(FTokens)) or (FTokens[Next].Kind <> TPascalTokenKind.StringLiteral) then
      Exit;
    Text := FTokens[Next].Text;
    if (Length(Text) >= 2) and (Text[1] = '''') and (Text[Length(Text)] = '''') then
      Text := StringReplace(Copy(Text, 2, Length(Text) - 2), '''''', '''', [rfReplaceAll]);
    ADeprecatedText := Text;
  end;

  function EndsHint(APos: Integer): Boolean;
  begin
    // Hinter einem Hinweis folgt ";", "," oder der Grund als String, sonst ist es ein Bezeichner
    // (z. B. ein Feld "platform: Integer").
    Result := (APos >= Length(FTokens)) or FTokens[APos].IsSymbol(';') or FTokens[APos].IsSymbol(',') or
      (FTokens[APos].Kind = TPascalTokenKind.StringLiteral) or IsHintAt(APos);
  end;

begin
  Result := nil;
  ADeprecatedText := '';
  Node := ANode;
  if (Node.Kind = TSyntaxKind.RoutineDecl) and (Node.FindChild(TSyntaxKind.RoutineHeader) <> nil) then
    Node := Node.FindChild(TSyntaxKind.RoutineHeader);
  if Node.Kind = TSyntaxKind.RoutineHeader then
  begin
    for Index := 0 to Node.ChildCount - 1 do
      if Node[Index].Kind = TSyntaxKind.Directive then
      begin
        AddWord(Node[Index].Name);
        TakeReason(TokenIndexAt(Node[Index].StartOffset));
      end;
    Exit;
  end;
  if AKind = TIndexSymbolKind.EnumMember then
    Exit;
  // Hinweise hinter der Deklaration: "X = 1 deprecated;", "end platform;", "A: Integer platform;".
  Last := TokenIndexAt(Node.EndOffset) - 1;
  Index := Last;
  while (Index > 0) and ((FTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive,
    TPascalTokenKind.StringLiteral]) or FTokens[Index].IsSymbol(';')) do
    Dec(Index);
  while (Index > 0) and IsHintAt(Index) do
  begin
    Word := FTokens[Index].Text;
    AddWord(Word);
    TakeReason(Index);
    Dec(Index);
    while (Index > 0) and ((FTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.StringLiteral]) or
      FTokens[Index].IsSymbol(',')) do
      Dec(Index);
  end;
  // Steht der Hinweis hinter dem Ende des Knotens, gehört er trotzdem dazu.
  Index := Last + 1;
  while (Index < Length(FTokens)) and (FTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive,
    TPascalTokenKind.StringLiteral]) do
    Inc(Index);
  while IsHintAt(Index) and EndsHint(NextCode(Index)) do
  begin
    AddWord(FTokens[Index].Text);
    TakeReason(Index);
    Index := NextCode(Index);
    while (Index < Length(FTokens)) and ((FTokens[Index].Kind = TPascalTokenKind.StringLiteral) or
      FTokens[Index].IsSymbol(',')) do
      Index := NextCode(Index);
  end;
end;

function TIndexExtractor.SummaryOf(ANode: TSyntaxNode): string;
var
  Index, Depth: Integer;
  Lines: TArray<string>;
  Text: string;
  Doc: TXmlDoc;
begin
  Result := '';
  Index := TokenIndexAt(ANode.StartOffset) - 1;
  // Attribute zwischen Doku und Deklaration überspringen: [Weak] /// steht darüber.
  while (Index >= 0) and FTokens[Index].IsSymbol(']') do
  begin
    Depth := 0;
    repeat
      if FTokens[Index].IsSymbol(']') then
        Inc(Depth)
      else if FTokens[Index].IsSymbol('[') then
        Dec(Depth);
      Dec(Index);
    until (Index < 0) or (Depth = 0);
  end;
  Lines := nil;
  while (Index >= 0) and (FTokens[Index].Kind = TPascalTokenKind.Comment) and
    FTokens[Index].Text.StartsWith('///') do
  begin
    Lines := [Copy(FTokens[Index].Text, 4, MaxInt)] + Lines;
    Dec(Index);
  end;
  if Length(Lines) = 0 then
    Exit;
  Doc := TXmlDoc.Parse(String.Join(#10, Lines));
  Text := Doc.Summary;
  // Eine Zeile, Leerraum zusammengefasst.
  Text := TRegEx.Replace(Text, '\s+', ' ').Trim;
  if Length(Text) > TIndexSymbol.MaxSummary then
    Text := Copy(Text, 1, TIndexSymbol.MaxSummary - 1) + '…';
  Result := Text;
end;

class function TIndexExtractor.DeclaredTypeNode(ANode: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  // Erster direkter Typverweis: A: TFoo, property P: TFoo, function F: TFoo.
  // Bei RoutineDecl steht der Typ im Kopf.
  if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.RoutineHeader) <> nil) then
    ANode := ANode.FindChild(TSyntaxKind.RoutineHeader);
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode[Index].Kind = TSyntaxKind.TypeReference then
      Exit(ANode[Index]);
  Result := nil;
end;

class function TIndexExtractor.DeclaredType(ANode: TSyntaxNode): string;
var
  Node: TSyntaxNode;
begin
  Node := DeclaredTypeNode(ANode);
  if Node <> nil then
    Result := Node.Name
  else
    Result := '';
end;

class function TIndexExtractor.GenericArgsText(ATypeRef: TSyntaxNode): string;
var
  Args: TSyntaxNode;
  Index: Integer;
begin
  Result := '';
  if ATypeRef = nil then
    Exit;
  Args := ATypeRef.FindChild(TSyntaxKind.GenericArgs);
  if Args = nil then
    Exit;
  for Index := 0 to Args.ChildCount - 1 do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + TypeText(Args[Index]);
  end;
end;

class function TIndexExtractor.TypeText(ANode: TSyntaxNode): string;
var
  Args: string;
begin
  Result := '';
  if ANode = nil then
    Exit;
  case ANode.Kind of
    TSyntaxKind.TypeReference:
      begin
        Result := ANode.Name;
        Args := GenericArgsText(ANode);
        if Args <> '' then
          Result := Result + '<' + Args + '>';
      end;
    TSyntaxKind.ArrayType:
      if ANode.FindChild(TSyntaxKind.TypeReference) <> nil then
        Result := 'array of ' + TypeText(ANode[ANode.ChildCount - 1]);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TIndexExtractor.TypeParamsOf(ANode: TSyntaxNode): string;
var
  Params: TSyntaxNode;
  Index: Integer;
begin
  Result := '';
  if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.RoutineHeader) <> nil) then
    ANode := ANode.FindChild(TSyntaxKind.RoutineHeader);
  Params := ANode.FindChild(TSyntaxKind.GenericParams);
  if Params = nil then
    Exit;
  for Index := 0 to Params.ChildCount - 1 do
    if Params[Index].Name <> '' then
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + Params[Index].Name;
    end;
end;

class procedure TIndexExtractor.ParamInfo(ANode: TSyntaxNode; out AMin, AMax: Integer; out ATypes: TArray<string>);
var
  Params, Param, TypeNode: TSyntaxNode;
  Index, Child, Count: Integer;
  ParamType: string;
  HasDefault: Boolean;
begin
  AMin := 0;
  AMax := 0;
  ATypes := nil;
  if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.RoutineHeader) <> nil) then
    ANode := ANode.FindChild(TSyntaxKind.RoutineHeader);
  Params := ANode.FindChild(TSyntaxKind.Parameters);
  if Params = nil then
    Exit;
  for Index := 0 to Params.ChildCount - 1 do
  begin
    Param := Params[Index];
    if Param.Kind <> TSyntaxKind.Parameter then
      Continue;
    // Kinder: Typ (fehlt bei untypisierten Parametern), danach ggf. der Standardwert.
    TypeNode := nil;
    HasDefault := False;
    for Child := 0 to Param.ChildCount - 1 do
      if (TypeNode = nil) and (Param[Child].Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType]) then
        TypeNode := Param[Child]
      else
        HasDefault := True;
    ParamType := TypeText(TypeNode);
    // A, B: Integer zählt zweimal.
    for Count := 1 to Length(Param.Name.Split([','])) do
    begin
      Inc(AMax);
      if not HasDefault then
        Inc(AMin);
      ATypes := ATypes + [ParamType];
    end;
  end;
end;

class function TIndexExtractor.IsVirtualHeader(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if ANode.Kind <> TSyntaxKind.RoutineHeader then
    Exit;
  for Index := 0 to ANode.ChildCount - 1 do
    if (ANode[Index].Kind = TSyntaxKind.Directive) and (SameText(ANode[Index].Name, 'virtual') or
      SameText(ANode[Index].Name, 'dynamic') or SameText(ANode[Index].Name, 'abstract') or
      SameText(ANode[Index].Name, 'override')) then
      Exit(True);
end;

function TIndexExtractor.IsDefaultProperty(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  // property Items[I: Integer]: T read Get; default;  Anders als "default 0" (gespeicherter
  // Standardwert) folgt "default" hier auf ein Semikolon.
  Result := False;
  Index := TokenIndexAt(ANode.StartOffset);
  while (Index + 1 < Length(FTokens)) and (FTokens[Index].Offset <= ANode.EndOffset) do
  begin
    if FTokens[Index].IsSymbol(';') and SameText(FTokens[Index + 1].Text, 'default') then
      Exit(True);
    Inc(Index);
  end;
end;

procedure TIndexExtractor.AddNames(ANode: TSyntaxNode; const AContainer: string; AKind: TIndexSymbolKind);
var
  Name: string;
begin
  // A, B: Integer
  for Name in ANode.Name.Split([',']) do
    Add(ANode, Name.Trim, AContainer, AKind);
end;

procedure TIndexExtractor.AddMembers(ABody: TSyntaxNode; const AContainer: string);
var
  Index: Integer;
  Child: TSyntaxNode;
  Kind: TIndexSymbolKind;
  Outer: string;
  ClassVar: Boolean;
begin
  for Index := 0 to ABody.ChildCount - 1 do
  begin
    Child := ABody[Index];
    case Child.Kind of
      TSyntaxKind.Visibility:
        begin
          FVisibility := VisibilityOf(Child.Name);
          AddMembers(Child, AContainer);
        end;
      TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VariantPart:
        AddMembers(Child, AContainer);
      TSyntaxKind.VarSection:
        begin
          ClassVar := FClassVar;
          FClassVar := (AContainer <> '') and IsClassMember(Child);
          try
            AddMembers(Child, AContainer);
          finally
            FClassVar := ClassVar;
          end;
        end;
      TSyntaxKind.CaseItem:
        begin
          // Zweig eines varianten Teils (#846); das Selektorfeld davor steht im äußeren Zweig.
          Outer := FVariant;
          if FVariant = '' then
            FVariant := Child.Name
          else
            FVariant := FVariant + ' › ' + Child.Name;
          try
            AddMembers(Child, AContainer);
          finally
            FVariant := Outer;
          end;
        end;
      TSyntaxKind.TypeDecl:
        AddType(Child, AContainer);
      TSyntaxKind.ConstDecl:
        Add(Child, Child.Name, AContainer, TIndexSymbolKind.Constant);
      TSyntaxKind.VarDecl, TSyntaxKind.Field:
        AddNames(Child, AContainer, TIndexSymbolKind.Field);
      TSyntaxKind.PropertyDecl:
        Add(Child, Child.Name, AContainer, TIndexSymbolKind.Property_);
      TSyntaxKind.RoutineHeader:
        // Methodenzuordnung procedure IFoo.Bar = MyBar ist kein Mitglied (#849), sondern steht am Typ.
        if Child.IsMethodResolution then
          AddResolution(Child)
        else
        begin
          if IsConstructor(Child) then
            Kind := TIndexSymbolKind.Constructor_
          else
            Kind := TIndexSymbolKind.Method;
          Add(Child, Child.Name, AContainer, Kind);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

procedure TIndexExtractor.AddType(ADecl: TSyntaxNode; const AContainer: string);
var
  Body: TSyntaxNode;
  Index: Integer;
  Kind: TIndexSymbolKind;
  Ancestors: TList<string>;
  Qualified, Args: string;
  AncestorArgs: TArray<string>;
  WithArgs: Boolean;
  Visibility: TIndexVisibility;
  Owner, Count: Integer;
begin
  Body := nil;
  AncestorArgs := nil;
  WithArgs := False;
  for Index := 0 to ADecl.ChildCount - 1 do
    if not (ADecl[Index].Kind in [TSyntaxKind.GenericParams, TSyntaxKind.Attribute]) then
    begin
      Body := ADecl[Index];
      Break;
    end;
  Kind := TIndexSymbolKind.TypeAlias;
  Ancestors := TList<string>.Create;
  try
    if Body <> nil then
    begin
      case Body.Kind of
        TSyntaxKind.ClassType, TSyntaxKind.ClassOfType, TSyntaxKind.ForwardType:
          Kind := TIndexSymbolKind.ClassType;
        TSyntaxKind.ObjectType:
          Kind := TIndexSymbolKind.ObjectType;
        TSyntaxKind.HelperType:
          Kind := TIndexSymbolKind.HelperType;
        TSyntaxKind.RecordType:
          Kind := TIndexSymbolKind.RecordType;
        TSyntaxKind.InterfaceType:
          Kind := TIndexSymbolKind.InterfaceType;
        TSyntaxKind.EnumType:
          Kind := TIndexSymbolKind.EnumType;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      // Vorfahren: direkte Typverweise des Rumpfs (class(TBase, IFoo), helper for T).
      if Body.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.InterfaceType,
        TSyntaxKind.HelperType] then
        for Index := 0 to Body.ChildCount - 1 do
          if (Body[Index].Kind = TSyntaxKind.TypeReference) and (Body[Index].Name <> '') then
          begin
            // Typargumente jedes Vorfahren: IComparer<TKunde> an zweiter Stelle braucht sie für den
            // Vergleich der Signaturen genauso wie der erste.
            Args := GenericArgsText(Body[Index]);
            WithArgs := WithArgs or (Args <> '');
            AncestorArgs := AncestorArgs + [Args];
            Ancestors.Add(Body[Index].Name);
          end;
    end;
    if not WithArgs then
      AncestorArgs := nil;
    FAncestorArgs := AncestorArgs;
    FForward := (Body <> nil) and (Body.Kind = TSyntaxKind.ForwardType);
    FScoped := (Kind = TIndexSymbolKind.EnumType) and ScopedAt(ADecl.StartOffset);
    Count := FSymbols.Count;
    try
      Add(ADecl, ADecl.Name, AContainer, Kind, Ancestors.ToArray);
    finally
      FAncestorArgs := nil;
      FForward := False;
    end;
  finally
    Ancestors.Free;
  end;
  if Body = nil then
    Exit;
  if AContainer = '' then
    Qualified := ADecl.Name
  else
    Qualified := AContainer + '.' + ADecl.Name;
  if Body.Kind = TSyntaxKind.EnumType then
  begin
    // Enum-Werte sind ohne SCOPEDENUMS auch auf Unit-Ebene sichtbar; der
    // Container hält den Typ fest, ScopedEnum den Schalter (#849), die Namensauflösung entscheidet.
    try
      for Index := 0 to Body.ChildCount - 1 do
        if Body[Index].Kind = TSyntaxKind.Identifier then
          Add(Body[Index], Body[Index].Name, Qualified, TIndexSymbolKind.EnumMember);
    finally
      FScoped := False;
    end;
  end
  else if Body.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.HelperType,
    TSyntaxKind.RecordType, TSyntaxKind.InterfaceType] then
  begin
    // Verschachtelte Typen haben ihre eigene Sichtbarkeit; danach gilt wieder die äußere.
    Visibility := FVisibility;
    FVisibility := TIndexVisibility.Public;
    Owner := FResolutionOwner;
    FResolutionOwner := -1;
    if FSymbols.Count > Count then
      FResolutionOwner := Count;
    try
      AddMembers(Body, Qualified);
    finally
      FVisibility := Visibility;
      FResolutionOwner := Owner;
    end;
  end;
end;

procedure TIndexExtractor.AddResolution(AHeader: TSyntaxNode);
var
  Symbol: TIndexSymbol;
begin
  if (FResolutionOwner < 0) or (AHeader.Name = '') or (AHeader.ResolutionTarget = '') then
    Exit;
  Symbol := FSymbols[FResolutionOwner];
  Symbol.Resolutions := Symbol.Resolutions + [AHeader.Name + '=' + AHeader.ResolutionTarget];
  FSymbols[FResolutionOwner] := Symbol;
end;

procedure TIndexExtractor.AddRoutine(ANode: TSyntaxNode);
var
  Name, Container: string;
  Dot: Integer;
  Kind: TIndexSymbolKind;
begin
  // TFoo.Bar in implementation: Methode von TFoo; sonst freie Routine.
  Name := ANode.Name;
  Dot := Name.LastIndexOf('.');
  if Dot >= 0 then
  begin
    Container := Name.Substring(0, Dot);
    Name := Name.Substring(Dot + 1);
    if IsConstructor(ANode) then
      Kind := TIndexSymbolKind.Constructor_
    else
      Kind := TIndexSymbolKind.Method;
  end
  else
  begin
    Container := '';
    Kind := TIndexSymbolKind.Routine;
  end;
  Add(ANode, Name, Container, Kind);
end;

procedure TIndexExtractor.AddDeclarations(ANode: TSyntaxNode);
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    case Child.Kind of
      TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection:
        AddDeclarations(Child);
      TSyntaxKind.TypeDecl:
        AddType(Child, '');
      TSyntaxKind.ConstDecl:
        Add(Child, Child.Name, '', TIndexSymbolKind.Constant);
      TSyntaxKind.VarDecl:
        AddNames(Child, '', TIndexSymbolKind.Variable);
      TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl:
        AddRoutine(Child);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

class function TIndexExtractor.UsesOf(ASection: TSyntaxNode): TArray<string>;
var
  Clause: TSyntaxNode;
  Names: TList<string>;
  Index: Integer;
begin
  Result := nil;
  if ASection = nil then
    Exit;
  Clause := ASection.FindChild(TSyntaxKind.UsesClause);
  if Clause = nil then
    Exit;
  Names := TList<string>.Create;
  try
    for Index := 0 to Clause.ChildCount - 1 do
      if (Clause[Index].Kind = TSyntaxKind.UsedUnit) and (Clause[Index].Name <> '') then
        Names.Add(Clause[Index].Name);
    Result := Names.ToArray;
  finally
    Names.Free;
  end;
end;

procedure TIndexExtractor.DropForwards;
var
  Index: Integer;
  Forwards: TArray<Boolean>;
  Full: TDictionary<string, Boolean>;
begin
  if FForwards.Count = 0 then
    Exit;
  SetLength(Forwards, FSymbols.Count);
  for Index in FForwards do
    Forwards[Index] := True;
  Full := TDictionary<string, Boolean>.Create;
  try
    for Index := 0 to FSymbols.Count - 1 do
      if not Forwards[Index] then
        Full.AddOrSetValue(UpperCase(FSymbols[Index].QualifiedName), True);
    for Index := FForwards.Count - 1 downto 0 do
      if Full.ContainsKey(UpperCase(FSymbols[FForwards[Index]].QualifiedName)) then
        FSymbols.Delete(FForwards[Index]);
  finally
    Full.Free;
  end;
  FForwards.Clear;
end;

/// <summary>Namen einer Liste "A, B" bzw. "A,B" in ANames eintragen (klein).</summary>
procedure AddNameList(ANames: TDictionary<string, Boolean>; const AList: string);
var
  Name: string;
begin
  for Name in AList.Split([',']) do
    if Name.Trim <> '' then
      ANames.AddOrSetValue(LowerCase(TPascalLexer.PlainName(Name.Trim)), True);
end;

/// <summary>Liegt ANode in AOuter (oder ist es selbst)?</summary>
function IsInside(ANode, AOuter: TSyntaxNode): Boolean;
begin
  Result := False;
  if AOuter = nil then
    Exit;
  while ANode <> nil do
  begin
    if ANode = AOuter then
      Exit(True);
    ANode := ANode.Parent;
  end;
end;

function TIndexExtractor.InlineRefsOf(ANode: TSyntaxNode; const AContainer, AContainerParams: string): TArray<string>;
var
  Locals: TDictionary<string, Boolean>;
  Refs: TList<string>;
  Seen: TDictionary<string, Boolean>;
  Own: TDictionary<string, TIndexSymbol>;
  Members: TDictionary<string, TIndexSymbol>;
  Header: TSyntaxNode;
  Symbol: TIndexSymbol;
  Blocked: Boolean;
  Nodes: TList<TSyntaxNode>;
  Stack: TStack<TSyntaxNode>;
  Child: TSyntaxNode;
  Index: Integer;

  procedure AddRef(const ARef: string);
  begin
    if (ARef = '') or Seen.ContainsKey(LowerCase(ARef)) then
      Exit;
    Seen.Add(LowerCase(ARef), True);
    Refs.Add(ARef);
  end;

  function TypeRefOf(const ASymbol: TIndexSymbol): string;
  begin
    Result := ':' + ASymbol.TypeName;
    if ASymbol.TypeArgs <> '' then
      Result := Result + '<' + ASymbol.TypeArgs + '>';
  end;

  // Wird ANode als Wert weiter benutzt (A.B, A[i])? Dann braucht der Rumpf die Unit seines Typs.
  function IsDereferenced(AIdent: TSyntaxNode): Boolean;
  var
    Parent: TSyntaxNode;
  begin
    Parent := AIdent.Parent;
    Result := (Parent <> nil) and (Parent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) and
      (Parent.ChildCount > 0) and (Parent[0] = AIdent) and (Parent.FindChild(TSyntaxKind.GenericArgs) = nil);
  end;

  procedure Identifier(AIdent: TSyntaxNode);
  var
    Name, Key: string;
    Member: TIndexSymbol;
  begin
    Name := TPascalLexer.PlainName(AIdent.Name);
    Key := LowerCase(Name);
    if (Name = '') or Locals.ContainsKey(Key) then
      Exit;
    if (AContainer <> '') and Members.TryGetValue(Key, Member) then
    begin
      if Member.Visibility = TIndexVisibility.StrictPrivate then
        AddRef('!' + Member.Name);
      if IsDereferenced(AIdent) and (Member.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and
        (Member.TypeName <> '') then
        AddRef(TypeRefOf(Member));
      Exit;
    end;
    if Own.TryGetValue(Key, Member) then
    begin
      if IsDereferenced(AIdent) and (Member.Kind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Constant]) and
        (Member.TypeName <> '') then
        AddRef(TypeRefOf(Member));
      Exit;
    end;
    AddRef(Name);
  end;

  procedure TypeReference(AType: TSyntaxNode);
  var
    Name: string;
  begin
    Name := TPascalLexer.PlainName(AType.Name);
    if (Name = '') or SameText(Name, 'string') or SameText(Name, 'const') or SameText(Name, 'file') or
      Locals.ContainsKey(LowerCase(Name)) or Own.ContainsKey(LowerCase(Name)) or
      ((AContainer <> '') and Members.ContainsKey(LowerCase(Name))) then
      Exit;
    AddRef(':' + Name);
  end;

begin
  Result := nil;
  Locals := TDictionary<string, Boolean>.Create;
  Refs := TList<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  Own := TDictionary<string, TIndexSymbol>.Create;
  Members := TDictionary<string, TIndexSymbol>.Create;
  try
    for Symbol in FSymbols do
      if Symbol.Container = '' then
        Own.AddOrSetValue(LowerCase(Symbol.Name), Symbol)
      else if (AContainer <> '') and SameText(Symbol.Container, AContainer) and
        not Members.ContainsKey(LowerCase(Symbol.Name)) then
        Members.Add(LowerCase(Symbol.Name), Symbol);
    Locals.Add('result', True);
    Locals.Add('self', True);
    AddNameList(Locals, AContainerParams);
    Header := ANode.FindChild(TSyntaxKind.RoutineHeader);
    if Header <> nil then
      AddNameList(Locals, TypeParamsOf(Header));
    Blocked := False;
    Nodes := TList<TSyntaxNode>.Create;
    try
      // Lokale Namen zuerst, damit die Reihenfolge im Rumpf keine Rolle spielt. Ohne anonyme Methode, weil
      // die lokalen Prozeduren dieselben Variablen benutzen.
      Stack := TStack<TSyntaxNode>.Create;
      try
        Stack.Push(ANode);
        while Stack.Count > 0 do
        begin
          Child := Stack.Pop;
          case Child.Kind of
            TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.InlineVar,
            TSyntaxKind.InlineConst, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.TypeDecl:
              AddNameList(Locals, Child.Name);
            TSyntaxKind.AsmBlock, TSyntaxKind.WithStatement:
              Blocked := True;
            TSyntaxKind.RoutineDecl:
              if Child <> ANode then
                Blocked := True;
            TSyntaxKind.ArrayType:
              // Offene Array-Parameter verhindern das Einbetten.
              if (Child.Parent <> nil) and (Child.Parent.Kind = TSyntaxKind.Parameter) then
                Blocked := True;
          else
            // Übrige Werte bewusst ohne Wirkung.
          end;
          // Den Kopf (Parameter- und Ergebnistypen) kennt der Aufrufer ohnehin.
          if (Child.Kind in [TSyntaxKind.Identifier, TSyntaxKind.TypeReference]) and not IsInside(Child, Header) then
            Nodes.Add(Child);
          for Index := Child.ChildCount - 1 downto 0 do
            Stack.Push(Child[Index]);
        end;
      finally
        Stack.Free;
      end;
      if Blocked then
        Exit;
      for Child in Nodes do
        if Child.Kind = TSyntaxKind.Identifier then
          Identifier(Child)
        else
          TypeReference(Child);
    finally
      Nodes.Free;
    end;
    Result := Refs.ToArray;
    // nil heißt „nicht einbettbar“; ohne Verweise bleibt die Routine trotzdem als inline erkennbar (#1381).
    if Length(Result) = 0 then
      Result := TArray<string>.Create(TIndexSymbol.InlineWithoutRefs);
  finally
    Members.Free;
    Own.Free;
    Seen.Free;
    Refs.Free;
    Locals.Free;
  end;
end;

/// <summary>Direktiven eines Routinenkopfs in Kleinschreibung.</summary>
function DirectivesOfHeader(AHeader: TSyntaxNode): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to AHeader.ChildCount - 1 do
    if AHeader[Index].Kind = TSyntaxKind.Directive then
      Result := Result + [LowerCase(AHeader[Index].Name)];
end;

function SameParamTypes(const A, B: TArray<string>): Boolean;
var
  Index: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for Index := 0 to High(A) do
      if not SameText(A[Index], B[Index]) then
        Exit(False);
end;

function TIndexExtractor.ContainerParams(const AContainer: string): string;
var
  Symbol: TIndexSymbol;
begin
  Result := '';
  if AContainer = '' then
    Exit;
  for Symbol in FSymbols do
    if (Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType]) and SameText(Symbol.QualifiedName, AContainer) then
      Exit(Symbol.TypeParams);
end;

procedure TIndexExtractor.SetInlineRefs(APosition: Integer; const ARefs: TArray<string>);
var
  Symbol: TIndexSymbol;
begin
  Symbol := FSymbols[APosition];
  Symbol.InlineRefs := ARefs;
  FSymbols[APosition] := Symbol;
end;

procedure TIndexExtractor.AddInlineRefs(ASection: TSyntaxNode);
const
  NotInlined: array[0..5] of string = ('virtual', 'dynamic', 'override', 'abstract', 'message', 'external');
var
  Index, Position, Found: Integer;
  Node, Header: TSyntaxNode;
  Name, Container: string;
  Dot, Min, Max: Integer;
  Types: TArray<string>;
  Inline_, Skip: Boolean;
  Symbol: TIndexSymbol;
  Refs: TArray<string>;
  Directive: string;
begin
  if ASection = nil then
    Exit;
  for Index := 0 to ASection.ChildCount - 1 do
  begin
    Node := ASection[Index];
    if Node.Kind <> TSyntaxKind.RoutineDecl then
      Continue;
    Header := Node.FindChild(TSyntaxKind.RoutineHeader);
    if (Header = nil) or (Node.FindChild(TSyntaxKind.Block) = nil) or IsConstructor(Node) then
      Continue;
    Name := Node.Name;
    Container := '';
    Dot := Name.LastIndexOf('.');
    if Dot >= 0 then
    begin
      Container := Name.Substring(0, Dot);
      Name := Name.Substring(Dot + 1);
    end;
    ParamInfo(Header, Min, Max, Types);
    // Deklaration suchen: gleicher Name und Typ, bei Überladungen dieselben Parametertypen.
    Found := -1;
    Inline_ := False;
    Skip := False;
    for Directive in DirectivesOfHeader(Header) do
    begin
      Inline_ := Inline_ or SameText(Directive, 'inline');
      Skip := Skip or (IndexText(Directive, NotInlined) >= 0);
    end;
    for Position := 0 to FSymbols.Count - 1 do
    begin
      Symbol := FSymbols[Position];
      if not (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) or
        not SameText(Symbol.Name, Name) or not SameText(Symbol.Container, Container) or
        (Symbol.Range.StartPos = Node.StartPos) then
        Continue;
      if (Length(Types) > 0) and not SameParamTypes(Symbol.ParamTypes, Types) then
        Continue;
      if Found >= 0 then
      begin
        // Mehrdeutig (Überladungen ohne Parameterliste in der Implementierung).
        Found := -2;
        Break;
      end;
      Found := Position;
    end;
    if Found = -2 then
      Continue;
    if Found >= 0 then
      for Directive in FSymbols[Found].Directives do
      begin
        Inline_ := Inline_ or SameText(Directive, 'inline');
        Skip := Skip or (IndexText(Directive, NotInlined) >= 0);
      end;
    if not Inline_ or Skip then
      Continue;
    Refs := InlineRefsOf(Node, Container, ContainerParams(Container));
    if Refs = nil then
      Continue;
    if Found >= 0 then
      SetInlineRefs(Found, Refs);
    for Position := 0 to FSymbols.Count - 1 do
      if (FSymbols[Position].Range.StartPos = Node.StartPos) and SameText(FSymbols[Position].Name, Name) then
        SetInlineRefs(Position, Refs);
  end;
end;

procedure TIndexExtractor.AddUnitHints(var AUnit: TUnitIndex);
var
  Index, Next: Integer;
  Started, InName, AfterPart: Boolean;
  Text: string;
begin
  // unit A.B deprecated 'Grund' platform;  Kommentare und Direktiven dazwischen überspringen.
  // Der Unit-Name zählt nicht als Hinweis: Atlas.Settings.Experimental ist nicht experimental.
  Started := False;
  InName := True;
  AfterPart := False;
  for Index := 0 to High(FTokens) do
  begin
    if FTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
      Continue;
    if not Started then
    begin
      if not ((FTokens[Index].Kind = TPascalTokenKind.Keyword) and SameText(FTokens[Index].Text, 'unit')) then
        Exit;
      Started := True;
      Continue;
    end;
    if FTokens[Index].IsSymbol(';') then
      Exit;
    if InName then
    begin
      // Name aus Teilen mit Punkt dazwischen; nach einem Teil ohne folgenden Punkt beginnen die Hinweise.
      if AfterPart and not FTokens[Index].IsSymbol('.') then
        InName := False
      else
      begin
        AfterPart := not FTokens[Index].IsSymbol('.');
        Continue;
      end;
    end;
    if not (FTokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) or
      (IndexText(FTokens[Index].Text, HintDirectives) < 0) then
      Continue;
    if IndexText(FTokens[Index].Text, AUnit.Directives) < 0 then
      AUnit.Directives := AUnit.Directives + [LowerCase(FTokens[Index].Text)];
    if not SameText(FTokens[Index].Text, 'deprecated') then
      Continue;
    Next := Index + 1;
    while (Next <= High(FTokens)) and (FTokens[Next].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
      Inc(Next);
    if (Next > High(FTokens)) or (FTokens[Next].Kind <> TPascalTokenKind.StringLiteral) then
      Continue;
    Text := FTokens[Next].Text;
    if (Length(Text) >= 2) and (Text[1] = '''') and (Text[Length(Text)] = '''') then
      Text := StringReplace(Copy(Text, 2, Length(Text) - 2), '''''', '''', [rfReplaceAll]);
    AUnit.DeprecatedText := Text;
  end;
end;

procedure TIndexExtractor.Walk(ARoot: TSyntaxNode; var AUnit: TUnitIndex);
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  AUnit.InterfaceUses := nil;
  AUnit.ImplementationUses := nil;
  AUnit.Directives := nil;
  AUnit.DeprecatedText := '';
  AUnit.Rationale := RationaleOf(TRationaleScanner.ForUnit(FTokens, ARoot));
  AUnit.HasInitialization := (ARoot.FindChild(TSyntaxKind.InitializationSection) <> nil) or
    (ARoot.FindChild(TSyntaxKind.FinalizationSection) <> nil);
  if ARoot.Kind = TSyntaxKind.UnitFile then
  begin
    AddUnitHints(AUnit);
    AUnit.InterfaceUses := UsesOf(ARoot.FindChild(TSyntaxKind.InterfaceSection));
    AUnit.ImplementationUses := UsesOf(ARoot.FindChild(TSyntaxKind.ImplementationSection));
  end
  else
    // program, library, package: alles gilt als implementation.
    AUnit.ImplementationUses := UsesOf(ARoot);
  for Index := 0 to ARoot.ChildCount - 1 do
  begin
    Child := ARoot[Index];
    if Child.Kind = TSyntaxKind.InterfaceSection then
    begin
      FInInterface := True;
      AddDeclarations(Child);
    end
    else if Child.Kind = TSyntaxKind.ImplementationSection then
    begin
      FInInterface := False;
      AddDeclarations(Child);
    end;
  end;
  if ARoot.Kind <> TSyntaxKind.UnitFile then
  begin
    FInInterface := False;
    AddDeclarations(ARoot);
  end;
  DropForwards;
  if ARoot.Kind = TSyntaxKind.UnitFile then
    AddInlineRefs(ARoot.FindChild(TSyntaxKind.ImplementationSection));
  AUnit.Symbols := FSymbols.ToArray;
  AUnit.Naming := NamingOf(ARoot);
end;

class function TIndexExtractor.HasNamePrefix(const AName, APrefix: string): Boolean;
begin
  Result := (APrefix <> '') and (Length(AName) > Length(APrefix)) and StartsStr(APrefix, AName) and
    CharInSet(AName[Length(APrefix) + 1], ['A'..'Z']);
end;

/// <summary>Art der Namen in ANode (Field, VarDecl, Parameter, InlineVar); False für globale Variablen,
/// Konstanten und alles andere.</summary>
function NamingKindOf(ANode: TSyntaxNode; out AKind: TNamingKind): Boolean;
var
  Owner: TSyntaxNode;
begin
  Result := True;
  AKind := TNamingKind.Local;
  case ANode.Kind of
    TSyntaxKind.Field:
      AKind := TNamingKind.Field;
    TSyntaxKind.Parameter:
      AKind := TNamingKind.Parameter;
    TSyntaxKind.InlineVar:
      AKind := TNamingKind.Local;
    TSyntaxKind.VarDecl:
      begin
        // Nächster Besitzer entscheidet: Typ = Feld, Routine = lokal, sonst global.
        Owner := ANode.Parent;
        while (Owner <> nil) and not (Owner.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType,
          TSyntaxKind.RecordType, TSyntaxKind.HelperType, TSyntaxKind.RoutineDecl]) do
          Owner := Owner.Parent;
        if Owner = nil then
          Exit(False);
        if Owner.Kind = TSyntaxKind.RoutineDecl then
          AKind := TNamingKind.Local
        else
          AKind := TNamingKind.Field;
      end;
  else
    Result := False;
  end;
end;

class function TIndexExtractor.NamingOf(ARoot: TSyntaxNode): TNamingCounts;
var
  Counts: TNamingCounts;
begin
  Counts := Default(TNamingCounts);
  if ARoot <> nil then
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        Kind: TNamingKind;
        Name: string;
      begin
        Result := True;
        if not NamingKindOf(ANode, Kind) then
          Exit;
        for Name in ANode.Name.Split([',']) do
          if Trim(Name) <> '' then
          begin
            Inc(Counts[Kind].Total);
            if HasNamePrefix(Trim(Name), NamingPrefixes[Kind]) then
              Inc(Counts[Kind].Prefixed);
          end;
      end);
  Result := Counts;
end;

class function TIndexExtractor.Extract(ATree: TSyntaxTree; const AFileName: string): TUnitIndex;
var
  Extractor: TIndexExtractor;
begin
  Result := Default(TUnitIndex);
  Result.FileName := AFileName;
  Result.UnitName := ATree.Root.Name;
  if Result.UnitName = '' then
    Result.UnitName := FileNameToUnitName(AFileName);
  Extractor := TIndexExtractor.Create(ATree.Tokens);
  try
    Extractor.Walk(ATree.Root, Result);
  finally
    Extractor.Free;
  end;
end;

class function TIndexExtractor.BlankInactive(const AText: string; const ADefines: TArray<string>): string;
var
  Includes: TArray<string>;
begin
  Result := BlankInactive(AText, '', ADefines, nil, Includes);
end;

class function TIndexExtractor.BlankInactive(const AText, AFileName: string; const ADefines: TArray<string>;
  const AResolver: TIncludeResolver; out AIncludes: TArray<string>): string;
var
  Conditionals: TArray<TConditionalRange>;
begin
  Result := BlankInactive(AText, AFileName, ADefines, AResolver, AIncludes, Conditionals);
end;

class function TIndexExtractor.BlankInactive(const AText, AFileName: string; const ADefines: TArray<string>;
  const AResolver: TIncludeResolver; out AIncludes: TArray<string>;
  out AConditionals: TArray<TConditionalRange>): string;
var
  Conditional: TConditionalRange;
  Options: TPreprocessorOptions;
  Processed: TPreprocessorResult;
  LineStarts: TList<Integer>;
  Range: TInactiveRange;
  Index, StartOffset, EndOffset: Integer;

  function OffsetOf(const APosition: TTextPosition): Integer;
  begin
    // 1-basiert; über das Textende hinaus wird abgeschnitten.
    if APosition.Line >= LineStarts.Count then
      Exit(Length(AText) + 1);
    Result := LineStarts[APosition.Line] + APosition.Character;
    if Result > Length(AText) + 1 then
      Result := Length(AText) + 1;
  end;

begin
  Result := AText;
  AIncludes := nil;
  AConditionals := nil;
  if Pos('{$', AText) + Pos('(*$', AText) = 0 then
    Exit;
  Options := TPreprocessorOptions.Default;
  Options.Defines := ADefines;
  Options.FileName := AFileName;
  Options.ResolveInclude := AResolver;
  Processed := TPascalPreprocessor.Process(AText, Options);
  for Index := 1 to High(Processed.Files) do
    if IndexText(Processed.Files[Index], AIncludes) < 0 then
      AIncludes := AIncludes + [Processed.Files[Index]];
  for Conditional in Processed.Conditionals do
    if Conditional.FileIndex = 0 then
      AConditionals := AConditionals + [Conditional];
  if Length(Processed.InactiveRanges) = 0 then
    Exit;
  LineStarts := TList<Integer>.Create;
  try
    LineStarts.Add(1);
    Index := 1;
    while Index <= Length(AText) do
    begin
      if AText[Index] = #13 then
      begin
        if (Index < Length(AText)) and (AText[Index + 1] = #10) then
          Inc(Index);
        LineStarts.Add(Index + 1);
      end
      else if AText[Index] = #10 then
        LineStarts.Add(Index + 1);
      Inc(Index);
    end;
    for Range in Processed.InactiveRanges do
    begin
      if Range.FileIndex <> 0 then
        Continue;
      StartOffset := OffsetOf(Range.Range.StartPos);
      EndOffset := OffsetOf(Range.Range.EndPos);
      for Index := StartOffset to EndOffset - 1 do
        if (Index >= 1) and (Index <= Length(Result)) and not CharInSet(Result[Index], [#10, #13]) then
          Result[Index] := ' ';
    end;
  finally
    LineStarts.Free;
  end;
end;

class function TIndexExtractor.ExtractText(const AText, AFileName: string;
  const ADefines: TArray<string>; const AResolver: TIncludeResolver; AUsages: Boolean): TUnitIndex;
begin
  Result := ExtractLevel(AText, AFileName, ADefines, AResolver, [AFileName], AUsages);
end;

type
  TUsageBucket = class
    Name: string;
    Positions: TList<TTextPosition>;
    constructor Create(const AName: string);
    destructor Destroy; override;
  end;

constructor TUsageBucket.Create(const AName: string);
begin
  inherited Create;
  Name := AName;
  Positions := TList<TTextPosition>.Create;
end;

destructor TUsageBucket.Destroy;
begin
  Positions.Free;
  inherited;
end;

class function TIndexExtractor.CollectUsages(const ATokens: TArray<TPascalToken>;
  const ASymbols: TArray<TIndexSymbol>): TArray<TIndexUsage>;
var
  Declared: TDictionary<Int64, Boolean>;
  Buckets: TObjectDictionary<string, TUsageBucket>;
  Bucket: TUsageBucket;
  Names: TArray<string>;
  Symbol: TIndexSymbol;
  Token: TPascalToken;
  Name, Key: string;
  Index: Integer;

  function PositionKey(const APosition: TTextPosition): Int64;
  begin
    Result := (Int64(APosition.Line) shl 32) or Cardinal(APosition.Character);
  end;

begin
  Result := nil;
  Declared := TDictionary<Int64, Boolean>.Create;
  Buckets := TObjectDictionary<string, TUsageBucket>.Create([doOwnsValues]);
  try
    // Die Deklaration selbst ist keine Verwendung; Symbole aus $I-Dateien stehen woanders.
    for Symbol in ASymbols do
      if Symbol.FileName = '' then
        Declared.AddOrSetValue(PositionKey(Symbol.SelectionRange.StartPos), True);
    for Token in ATokens do
    begin
      if Token.Kind <> TPascalTokenKind.Identifier then
        Continue;
      Name := Token.Text;
      if Name.StartsWith('&') then
        Name := Copy(Name, 2, MaxInt);
      if (Name = '') or SameText(Name, 'Self') or SameText(Name, 'Result') or
        (IndexText(Name, DirectiveWords) >= 0) or Declared.ContainsKey(PositionKey(Token.StartPos)) then
        Continue;
      Key := UpperCase(Name);
      if not Buckets.TryGetValue(Key, Bucket) then
      begin
        Bucket := TUsageBucket.Create(Name);
        Buckets.Add(Key, Bucket);
      end;
      Bucket.Positions.Add(Token.StartPos);
    end;
    Names := Buckets.Keys.ToArray;
    TArray.Sort<string>(Names);
    SetLength(Result, Length(Names));
    for Index := 0 to High(Names) do
    begin
      Bucket := Buckets[Names[Index]];
      Result[Index].Name := Bucket.Name;
      Result[Index].Positions := Bucket.Positions.ToArray;
    end;
  finally
    Buckets.Free;
    Declared.Free;
  end;
end;

/// <summary>Liegt APosition in ARange (Ende ausgeschlossen)?</summary>
function InRange(const APosition: TTextPosition; const ARange: TTextRange): Boolean;
begin
  Result := ((APosition.Line > ARange.StartPos.Line) or
    ((APosition.Line = ARange.StartPos.Line) and (APosition.Character >= ARange.StartPos.Character))) and
    ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character < ARange.EndPos.Character)));
end;

class procedure TIndexExtractor.AnnotateConditions(var AUnit: TUnitIndex; const AText: string;
  const AConditionals: TArray<TConditionalRange>);
var
  Lines: TArray<string>;
  Index, LineIndex, Best, ImplementationLine, Indent: Integer;
  Conditional: TConditionalRange;
  Symbol: TIndexSymbol;
  Section, Line, Code, Keyword, Owner: string;
  Match: TMatch;
  Known: TDictionary<string, Boolean>;
  // Abschnitt (type/const/var …) am Anfang jeder Zeile; einmal für die ganze Datei bestimmt.
  Sections: TArray<string>;

  procedure AddUnavailable(const AName: string; AKind: TIndexSymbolKind; ALine, AColumn: Integer;
    const ACondition: string; const AContainer: string = '');
  var
    Item: TIndexSymbol;
    Key: string;
  begin
    // Mitglieder je Typ: gleichnamige Mitglieder anderer Typen sind etwas anderes.
    Key := UpperCase(AName);
    if AContainer <> '' then
      Key := UpperCase(AContainer) + '.' + Key;
    if Known.ContainsKey(Key) then
      Exit;
    Known.Add(Key, True);
    Item := Default(TIndexSymbol);
    Item.Name := AName;
    Item.Kind := AKind;
    Item.Container := AContainer;
    Item.Range := TTextRange.Create(TTextPosition.Create(ALine, 0), TTextPosition.Create(ALine, Length(Lines[ALine])));
    Item.SelectionRange := TTextRange.Create(TTextPosition.Create(ALine, AColumn),
      TTextPosition.Create(ALine, AColumn + Length(AName)));
    Item.InInterface := (ImplementationLine < 0) or (ALine < ImplementationLine);
    Item.Visibility := TIndexVisibility.Public;
    Item.Condition := ACondition;
    Item.Unavailable := True;
    AUnit.Unavailable := AUnit.Unavailable + [Item];
  end;

  // Innerster Klassen-, Record- oder Interface-Typ, in dessen Rumpf ALine liegt; '' = keiner.
  function OwnerOf(ALine: Integer): string;
  var
    Candidate: TIndexSymbol;
    Best: TTextRange;
  begin
    Result := '';
    for Candidate in AUnit.Symbols do
      if (Candidate.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
        TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType]) and (Candidate.FileName = '') and
        (Candidate.Range.StartPos.Line < ALine) and (Candidate.Range.EndPos.Line >= ALine) then
        if (Result = '') or (Candidate.Range.StartPos.Line >= Best.StartPos.Line) then
        begin
          Result := Candidate.QualifiedName;
          Best := Candidate.Range;
        end;
  end;

  // Mitglied in einem nicht geltenden Zweig innerhalb eines Typrumpfs (#476): Methoden, Properties, Felder.
  procedure AddMember(const ACode: string; ALine: Integer; const AOwner, ACondition: string);
  var
    Found: TMatch;
    Words: string;
    Kind: TIndexSymbolKind;
    Name: string;
    Column: Integer;
  begin
    Found := TRegEx.Match(ACode,
      '^\s*(class\s+)?(procedure|function|constructor|destructor|operator)\s+([A-Za-z_]\w*)', [roIgnoreCase]);
    if Found.Success then
    begin
      Words := LowerCase(Found.Groups[2].Value);
      if Words = 'constructor' then
        Kind := TIndexSymbolKind.Constructor_
      else
        Kind := TIndexSymbolKind.Method;
      AddUnavailable(Found.Groups[3].Value, Kind, ALine, Found.Groups[3].Index - 1, ACondition, AOwner);
      Exit;
    end;
    Found := TRegEx.Match(ACode, '^\s*(class\s+)?property\s+([A-Za-z_]\w*)', [roIgnoreCase]);
    if Found.Success then
    begin
      AddUnavailable(Found.Groups[2].Value, TIndexSymbolKind.Property_, ALine, Found.Groups[2].Index - 1,
        ACondition, AOwner);
      Exit;
    end;
    // Felder "A, B: Integer;" (auch nach "class var" / "var"); Schlüsselwörter sind keine Felder.
    Found := TRegEx.Match(ACode, '^\s*((class\s+)?var\s+)?([A-Za-z_]\w*(\s*,\s*[A-Za-z_]\w*)*)\s*:[^=]',
      [roIgnoreCase]);
    if not Found.Success then
      Exit;
    Column := Found.Groups[3].Index - 1;
    for Name in Found.Groups[3].Value.Split([',']) do
    begin
      Words := Trim(Name);
      if MatchText(Words, ['private', 'protected', 'public', 'published', 'strict', 'case', 'end']) then
        Continue;
      AddUnavailable(Words, TIndexSymbolKind.Field, ALine, Column + Pos(Words, Found.Groups[3].Value) - 1,
        ACondition, AOwner);
    end;
  end;

  procedure AddType(const AMatch: TMatch; ALine: Integer; const ACondition: string);
  var
    Kind: TIndexSymbolKind;
  begin
    Keyword := LowerCase(AMatch.Groups[4].Value);
    if Keyword = 'class' then
      Kind := TIndexSymbolKind.ClassType
    else if Keyword = 'record' then
      Kind := TIndexSymbolKind.RecordType
    else if (Keyword = 'interface') or (Keyword = 'dispinterface') then
      Kind := TIndexSymbolKind.InterfaceType
    else if Keyword = '(' then
      Kind := TIndexSymbolKind.EnumType
    else
      Kind := TIndexSymbolKind.TypeAlias;
    AddUnavailable(AMatch.Groups[1].Value, Kind, ALine, AMatch.Groups[1].Index - 1, ACondition);
  end;

begin
  AUnit.Unavailable := nil;
  Lines := AText.Replace(#13#10, #10).Split([#10]);
  // Geltende Zweige: der innerste umgebende Zweig bestimmt die Bedingung.
  for Index := 0 to High(AUnit.Symbols) do
  begin
    if AUnit.Symbols[Index].FileName <> '' then
      Continue;
    Best := -1;
    for LineIndex := 0 to High(AConditionals) do
      if AConditionals[LineIndex].Active and InRange(AUnit.Symbols[Index].SelectionRange.StartPos,
        AConditionals[LineIndex].Range) then
        if (Best < 0) or InRange(AConditionals[LineIndex].Range.StartPos, AConditionals[Best].Range) then
          Best := LineIndex;
    if Best >= 0 then
      AUnit.Symbols[Index].Condition := AConditionals[Best].Condition
    else
    begin
      // Direktive platform an der Deklaration (erste Zeile).
      LineIndex := AUnit.Symbols[Index].SelectionRange.StartPos.Line;
      if (LineIndex >= 0) and (LineIndex <= High(Lines)) and
        TRegEx.IsMatch(Lines[LineIndex], '\bplatform\s*;', [roIgnoreCase]) then
        AUnit.Symbols[Index].Condition := 'platform';
    end;
  end;
  // Nur wenn ein Zweig nicht gilt, lohnt die Suche nach Deklarationen darin.
  Best := 0;
  for Conditional in AConditionals do
    if not Conditional.Active then
      Inc(Best);
  if Best = 0 then
    Exit;
  // Ein Durchlauf über die Datei: Abschnitt je Zeile und Beginn des implementation-Teils.
  // Große Units (System.pas) haben tausende Zweige; je Zweig neu zu suchen wäre quadratisch.
  ImplementationLine := -1;
  SetLength(Sections, Length(Lines));
  Section := '';
  for LineIndex := 0 to High(Lines) do
  begin
    Sections[LineIndex] := Section;
    Line := TrimLeft(Lines[LineIndex]);
    if (Line = '') or not CharInSet(Line[1], ['a'..'z', 'A'..'Z']) then
      Continue;
    Match := TRegEx.Match(Line, '^(type|const|var|threadvar|resourcestring|implementation|interface)\b',
      [roIgnoreCase]);
    if not Match.Success then
      Continue;
    Keyword := LowerCase(Match.Groups[1].Value);
    if (Keyword = 'implementation') or (Keyword = 'interface') then
    begin
      Section := '';
      if (Keyword = 'implementation') and (ImplementationLine < 0) then
        ImplementationLine := LineIndex;
    end
    else
      Section := Keyword;
  end;
  Known := TDictionary<string, Boolean>.Create;
  try
    // Was in geltenden Zweigen schon deklariert ist, nicht noch einmal (IFDEF WIN32 ... ELSE ... gleicher Name).
    for Symbol in AUnit.Symbols do
      if Symbol.Container = '' then
        Known.AddOrSetValue(UpperCase(Symbol.Name), True)
      else
        Known.AddOrSetValue(UpperCase(Symbol.Container) + '.' + UpperCase(Symbol.Name), True);
    for Conditional in AConditionals do
    begin
      if Conditional.Active then
        Continue;
      // Abschnitt am Anfang des Zweigs aus dem einen Durchlauf oben.
      if (Conditional.Range.StartPos.Line >= 0) and (Conditional.Range.StartPos.Line < Length(Sections) - 1) then
        Section := Sections[Conditional.Range.StartPos.Line + 1]
      else
        Section := '';
      // Im implementation-Teil nur Routinen der Unit (eigene Unit, z. B. "procedure ApplyAppIcon;" unter
      // {$IFDEF FPC}): ein billiger Vergleich am Zeilenanfang je Zeile, denn lange Zweige mit ganzen
      // Implementierungen (System.pas) sollen nichts kosten. Methodenrümpfe "TFoo.Bar" zählen nicht.
      if (ImplementationLine >= 0) and (Conditional.Range.StartPos.Line > ImplementationLine) then
      begin
        for LineIndex := Conditional.Range.StartPos.Line + 1 to Min(Conditional.Range.EndPos.Line, High(Lines)) do
        begin
          Line := Lines[LineIndex];
          if not (StartsText('procedure ', Line) or StartsText('function ', Line)) then
            Continue;
          Match := TRegEx.Match(Line, '^(procedure|function)\s+([A-Za-z_]\w*)\s*[(:;]', [roIgnoreCase]);
          if Match.Success then
            AddUnavailable(Match.Groups[2].Value, TIndexSymbolKind.Routine, LineIndex, Match.Groups[2].Index - 1,
              Conditional.Condition);
        end;
        Continue;
      end;
      // Zweig im Rumpf einer Klasse, eines Records oder Interfaces: Mitglieder dieses Typs.
      Owner := OwnerOf(Conditional.Range.StartPos.Line);
      if Owner <> '' then
      begin
        for LineIndex := Conditional.Range.StartPos.Line + 1 to Min(Conditional.Range.EndPos.Line, High(Lines)) do
        begin
          Code := Lines[LineIndex];
          if Pos('//', Code) > 0 then
            Code := Copy(Code, 1, Pos('//', Code) - 1);
          AddMember(Code, LineIndex, Owner, Conditional.Condition);
        end;
        Continue;
      end;
      for LineIndex := Conditional.Range.StartPos.Line + 1 to Min(Conditional.Range.EndPos.Line, High(Lines)) do
      begin
        Line := Lines[LineIndex];
        Code := Line;
        if Pos('//', Code) > 0 then
          Code := Copy(Code, 1, Pos('//', Code) - 1);
        Match := TRegEx.Match(Code, '^\s*(type|const|var|threadvar|resourcestring)\b', [roIgnoreCase]);
        if Match.Success then
        begin
          Section := LowerCase(Match.Groups[1].Value);
          Code := Copy(Code, Match.Length + 1, MaxInt);
          if Trim(Code) = '' then
            Continue;
        end;
        Indent := TTextLines.IndentLength(Line);
        // Routinen auf Unit-Ebene stehen am Zeilenanfang.
        Match := TRegEx.Match(Code, '^(procedure|function)\s+([A-Za-z_]\w*)\s*[(:;]', [roIgnoreCase]);
        if Match.Success then
        begin
          AddUnavailable(Match.Groups[2].Value, TIndexSymbolKind.Routine, LineIndex, Match.Groups[2].Index - 1,
            Conditional.Condition);
          Section := '';
          Continue;
        end;
        if Indent > 2 then
          Continue;
        if Section = 'type' then
        begin
          // Vorwärtsdeklaration "TFoo = class;" zählt nicht.
          if TRegEx.IsMatch(Code, '=\s*(packed\s+)?(class|interface)\s*;', [roIgnoreCase]) then
            Continue;
          Match := TRegEx.Match(Code, '^\s*([A-Za-z_]\w*)\s*(<[^>]*>)?\s*=\s*(packed\s+)?(\w+|\()', [roIgnoreCase]);
          if Match.Success then
            AddType(Match, LineIndex, Conditional.Condition);
        end
        else if (Section = 'const') or (Section = 'resourcestring') then
        begin
          Match := TRegEx.Match(Code, '^\s*([A-Za-z_]\w*)\s*(:[^=]+)?=', [roIgnoreCase]);
          if Match.Success then
            AddUnavailable(Match.Groups[1].Value, TIndexSymbolKind.Constant, LineIndex, Match.Groups[1].Index - 1,
              Conditional.Condition);
        end
        else if (Section = 'var') or (Section = 'threadvar') then
        begin
          Match := TRegEx.Match(Code, '^\s*([A-Za-z_]\w*)\s*:', [roIgnoreCase]);
          if Match.Success then
            AddUnavailable(Match.Groups[1].Value, TIndexSymbolKind.Variable, LineIndex, Match.Groups[1].Index - 1,
              Conditional.Condition);
        end;
      end;
    end;
  finally
    Known.Free;
  end;
end;

class function TIndexExtractor.ExtractLevel(const AText, AFileName: string; const ADefines: TArray<string>;
  const AResolver: TIncludeResolver; const AStack: TArray<string>; AUsages: Boolean): TUnitIndex;
var
  Tree: TSyntaxTree;
  Includes: TArray<string>;
  Conditionals: TArray<TConditionalRange>;
begin
  Tree := TSyntaxTreeCache.Parse(BlankInactive(AText, AFileName, ADefines, AResolver, Includes, Conditionals));
  try
    Result := Extract(Tree, AFileName);
    Result.Includes := Includes;
    AnnotateConditions(Result, AText, Conditionals);
    if AUsages then
    begin
      Result.Usages := CollectUsages(Tree.Tokens, Result.Symbols);
      Result.UsagesIndexed := True;
    end;
    AddIncluded(Tree, AFileName, ADefines, AResolver, AStack, Result);
  finally
    Tree.Free;
  end;
end;

/// <summary>Erstes Wort von AText hinter Leerraum und Kommentaren, klein.</summary>
function FirstWord(const AText: string): string;
var
  Index, Start: Integer;
begin
  Result := '';
  Index := 1;
  while Index <= Length(AText) do
  begin
    if CharInSet(AText[Index], [#1..' ']) then
      Inc(Index)
    else if AText[Index] = '{' then
    begin
      Index := PosEx('}', AText, Index);
      if Index = 0 then
        Exit;
      Inc(Index);
    end
    else if Copy(AText, Index, 2) = '(*' then
    begin
      Index := PosEx('*)', AText, Index);
      if Index = 0 then
        Exit;
      Inc(Index, 2);
    end
    else if Copy(AText, Index, 2) = '//' then
    begin
      while (Index <= Length(AText)) and not CharInSet(AText[Index], [#10, #13]) do
        Inc(Index);
    end
    else
    begin
      Start := Index;
      while (Index <= Length(AText)) and CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(Index);
      Exit(LowerCase(Copy(AText, Start, Index - Start)));
    end;
  end;
end;

function Shifted(const APosition: TTextPosition; ALines: Integer): TTextPosition;
begin
  Result := TTextPosition.Create(APosition.Line - ALines, APosition.Character);
end;

const
  /// <summary>Name des Hilfstyps, in den AddIncluded eine .inc aus einem Klassenrumpf einbettet (#849).</summary>
  IncludeHost = 'TAtlasIncludeHost__';

/// <summary>Innerster Rumpf (class, object, record, interface, helper) unter ANode, der AOffset enthält; sonst nil.
/// </summary>
function BodyAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Index: Integer;
  Inner: TSyntaxNode;
begin
  Result := nil;
  for Index := 0 to ANode.ChildCount - 1 do
    if (ANode[Index].StartOffset < AOffset) and (AOffset < ANode[Index].EndOffset) then
    begin
      if ANode[Index].Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
        TSyntaxKind.InterfaceType, TSyntaxKind.HelperType] then
        Result := ANode[Index];
      Inner := BodyAt(ANode[Index], AOffset);
      if Inner <> nil then
        Result := Inner;
      Exit;
    end;
end;

/// <summary>Kopf des Hilfstyps für eine .inc an AOffset in ABody: Art des Rumpfs und die dort geltende
/// Sichtbarkeit, z. B. "type TAtlasIncludeHost__ = class public" und ein Zeilenumbruch.</summary>
function HostHead(ABody: TSyntaxNode; AOffset: Integer): string;
var
  Index: Integer;
  Visibility: string;
begin
  Visibility := '';
  for Index := 0 to ABody.ChildCount - 1 do
    if (ABody[Index].Kind = TSyntaxKind.Visibility) and (ABody[Index].StartOffset < AOffset) then
      Visibility := ABody[Index].Name;
  case ABody.Kind of
    TSyntaxKind.RecordType:
      Result := 'record';
    TSyntaxKind.InterfaceType:
      Result := 'interface';
    TSyntaxKind.ObjectType:
      Result := 'object';
  else
    Result := 'class';
  end;
  Result := 'type' + #10 + IncludeHost + ' = ' + Result + ' ' + Visibility + #10;
end;

/// <summary>Inhalt einer .inc als eine Zeile für die Signatur einer Konstanten (#849).</summary>
function OneLine(const AText: string): string;
var
  Index: Integer;
begin
  Result := AText;
  for Index := 1 to Length(Result) do
    if CharInSet(Result[Index], [#9, #10, #13]) then
      Result[Index] := ' ';
  Result := Trim(Result);
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  while Result.EndsWith(';') do
    Result := Copy(Result, 1, Length(Result) - 1).TrimRight;
end;

class procedure TIndexExtractor.AddIncluded(ATree: TSyntaxTree; const AFileName: string;
  const ADefines: TArray<string>; const AResolver: TIncludeResolver; const AStack: TArray<string>;
  var AUnit: TUnitIndex);
const
  MaxDepth = 16;
  SectionWords: array[0..4] of string = ('type', 'const', 'var', 'resourcestring', 'threadvar');
  StartWords: array[0..13] of string = ('type', 'const', 'var', 'resourcestring', 'threadvar', 'procedure',
    'function', 'constructor', 'destructor', 'class', 'operator', 'uses', 'begin', 'exports');
var
  Token, Previous: TPascalToken;
  ImplementationOffset, Shift, Position: Integer;
  IsUnit, InInterface: Boolean;
  Section, Name, IncFile, IncText, HostType: string;
  Included: TUnitIndex;
  Symbol, Copied: TIndexSymbol;
  Symbols: TList<TIndexSymbol>;
  Body: TSyntaxNode;
begin
  if not Assigned(AResolver) or (Length(AStack) > MaxDepth) then
    Exit;
  IsUnit := ATree.Root.Kind = TSyntaxKind.UnitFile;
  ImplementationOffset := MaxInt;
  for Token in ATree.Tokens do
    if Token.IsKeyword('implementation') then
    begin
      ImplementationOffset := Token.Offset;
      Break;
    end;
  Section := '';
  Previous := Default(TPascalToken);
  Previous.Kind := TPascalTokenKind.Unknown;
  Symbols := TList<TIndexSymbol>.Create;
  try
    Symbols.AddRange(AUnit.Symbols);
    for Token in ATree.Tokens do
    begin
      // Zuletzt geöffneter Deklarationsabschnitt, für Dateien ohne eigenes Schlüsselwort.
      if (Token.Kind = TPascalTokenKind.Keyword) and (IndexText(Token.Text, SectionWords) >= 0) then
        Section := LowerCase(Token.Text)
      else if Token.IsKeyword('begin') or Token.IsKeyword('implementation') or Token.IsKeyword('interface') then
        Section := '';
      if Token.Kind <> TPascalTokenKind.Directive then
      begin
        if Token.Kind <> TPascalTokenKind.Comment then
          Previous := Token;
        Continue;
      end;
      if not TPascalPreprocessor.IncludeFileOf(Token.Text, Name) then
        Continue;
      // Nicht gefunden oder Zyklus: überspringen, die Diagnose kommt aus dem Präprozessor.
      if not AResolver(Name, AFileName, IncFile, IncText) or (IndexText(IncFile, AStack) >= 0) then
        Continue;
      if IndexText(IncFile, AUnit.Includes) < 0 then
        AUnit.Includes := AUnit.Includes + [IncFile];
      // Wert einer Konstanten (V = {$I commit.inc};, #849): Inhalt in die Signatur, keine Deklarationen.
      if TPascalParser.IncludeAsValue(Previous) then
      begin
        for Position := 0 to Symbols.Count - 1 do
          if (Symbols[Position].Kind = TIndexSymbolKind.Constant) and (Symbols[Position].FileName = '') and
            InRange(Token.StartPos, Symbols[Position].Range) then
          begin
            Copied := Symbols[Position];
            Copied.Signature := StringReplace(Copied.Signature, Token.Text, OneLine(IncText), []);
            if Length(Copied.Signature) > TIndexSymbol.MaxSignature then
              Copied.Signature := Copy(Copied.Signature, 1, TIndexSymbol.MaxSignature - 1) + '…';
            Symbols[Position] := Copied;
          end;
        Continue;
      end;
      InInterface := IsUnit and (Token.Offset < ImplementationOffset);
      Shift := 0;
      HostType := '';
      Body := BodyAt(ATree.Root, Token.Offset);
      if Body <> nil then
      begin
        // Mitten im Klassenrumpf (#849): die .inc in einen Hilfstyp derselben Art einbetten; ihre
        // Mitglieder gehören danach zum umgebenden Typ.
        HostType := Body.EnclosingTypeName;
        IncText := HostHead(Body, Token.Offset) + IncText + #10 + 'end;';
        Shift := 2;
      end
      else if (Section <> '') and (IndexText(FirstWord(IncText), StartWords) < 0) then
      begin
        IncText := Section + #10 + IncText;
        Shift := 1;
      end;
      Included := ExtractLevel(IncText, IncFile, ADefines, AResolver, AStack + [IncFile], False);
      for Symbol in Included.Symbols do
      begin
        Copied := Symbol;
        if HostType <> '' then
        begin
          if SameText(Copied.Container, '') and SameText(Copied.Name, IncludeHost) then
            Continue;
          if SameText(Copied.Container, IncludeHost) then
            Copied.Container := HostType
          else if StartsText(IncludeHost + '.', Copied.Container) then
            Copied.Container := HostType + Copy(Copied.Container, Length(IncludeHost) + 1, MaxInt);
        end;
        if Copied.FileName = '' then
        begin
          Copied.FileName := IncFile;
          Copied.Range := TTextRange.Create(Shifted(Copied.Range.StartPos, Shift), Shifted(Copied.Range.EndPos, Shift));
          Copied.SelectionRange := TTextRange.Create(Shifted(Copied.SelectionRange.StartPos, Shift),
            Shifted(Copied.SelectionRange.EndPos, Shift));
        end;
        Copied.InInterface := InInterface;
        Symbols.Add(Copied);
      end;
      for Name in Included.Includes do
        if IndexText(Name, AUnit.Includes) < 0 then
          AUnit.Includes := AUnit.Includes + [Name];
    end;
    AUnit.Symbols := Symbols.ToArray;
  finally
    Symbols.Free;
  end;
end;
end.
