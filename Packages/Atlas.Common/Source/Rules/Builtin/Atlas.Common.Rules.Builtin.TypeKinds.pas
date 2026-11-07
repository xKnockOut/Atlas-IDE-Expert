unit Atlas.Common.Rules.Builtin.TypeKinds;

// Ausdruck oder Deklaration hat nicht die geforderte Typart (Gruppe „Compiler
// vorab“, #1024, #1370). Regel type-kind-required, Stufe T; die Typart kommt
// aus TResolvedTypeKinds (Semantics.TypeKinds). Gemeldet wird nur, was dcc 13
// in den Fällen aus Tests/Compilermeldungen meldet (#1328: nie strenger als
// dcc):
//   - Index auf einer Variablen, einem Feld oder einer Konstante einfacher Art
//     (Zahl, Boolean, Zeichen, Aufzählung) (wie E2016).
//   - ^ auf einem Wert einfacher Art, einer Klasse, einem Record oder einem
//     Interface (wie E2017). Korrektur bei Klasse, Record und Interface vor
//     einem Punkt: ^ entfernen.
//   - Punkt bzw. with auf einem Wert einfacher Art (wie E2018).
//   - object mit Vorfahr, der kein object-Typ ist; TypeOf und Dispose mit
//     Destruktor auf einem Wert bzw. Zeiger einfacher Art (wie E2019).
//   - Klasse mit Vorfahr, der keine Klasse und kein Interface ist (Record,
//     Klassenreferenz, Aufzählung, einfacher Typ) (wie E2021).
//   - Class-Helper mit Vorfahr, der kein Helfer ist (wie E2022).
//   - New mit Konstruktor auf einem Zeiger einfacher Art (wie E2467).
//   - Record-Helper für eine Klasse oder ein Interface (wie E2474).
//   - Methode ohne class über den Klassentyp aufgerufen (TBasis.Machen)
//     außerhalb von Methoden der Klasse und ihrer Nachfahren (wie E2076).
//   - Slice außerhalb eines Arguments bzw. an einen Parameter mit einfachem
//     Typ (wie E2193).
//   - Record als Element eines Arrays an array of const (wie E2150).
//   - Write/Writeln bzw. Read/Readln mit Klasse, Record oder Interface (wie
//     E2054 bzw. E2055). Korrektur bei Klassen in Write/Writeln: ToString.
// Still bleibt die Regel bei unbekanntem Typ, bei Aliasen ohne bekannten Text,
// in bedingten Deklarationen, wenn ein Helfer für den Typ sichtbar ist oder
// eine Unit aus uses nicht im Index steht (sie könnte einen Helfer bzw. eine
// eigene Routine gleichen Namens deklarieren), bei Records mit Implicit-
// Operator und bei unbekannten Vorfahren.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cTypeKindRequiredRuleId = 'type-kind-required';

type
  TTypeKindRequiredRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterTypeKindRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.TypeIdentity,
  Atlas.Common.Semantics.TypeKinds,
  Atlas.Common.Semantics.UnresolvedNames,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTypeKindsText = (NotArray, RemoveCaret, NotPointer, NotStructured, WithNeeds, ObjectAncestor, ClassAncestor,
    HelperAncestor, RecordHelper, NewCtor, DisposeDtor, PointsTo, TypeOf, Slice, RecordConst, CannotRead, CannotWrite,
    NotClassMethod, Title);

const
  cTexts: array[TTypeKindsText] of TAtlasText = (
    (De: '%s ist %s (%s), kein Array; ein Index ist hier nicht möglich (wie E2016).';
     En: '%s is %s (%s), not an array; an index is not possible here (like E2016).'),
    (De: '^ entfernen'; En: 'Remove ^'),
    (De: '%s ist %s (%s), kein Zeiger; ^ ist hier nicht möglich (wie E2017).';
     En: '%s is %s (%s), not a pointer; ^ is not possible here (like E2017).'),
    (De: '%s ist %s (%s), kein Record, keine Klasse und kein object-Typ; .%s ist hier nicht möglich (wie E2018).';
     En: '%s is %s (%s), not a record, class or object type; .%s is not possible here (like E2018).'),
    (De: 'with braucht einen Record, eine Klasse oder einen object-Typ; %s ist %s (%s) (wie E2018).';
     En: 'with needs a record, a class or an object type; %s is %s (%s) (like E2018).'),
    (De: 'Der Vorfahr eines object-Typs muss ein object-Typ sein; %s ist %s (wie E2019).';
     En: 'The ancestor of an object type must be an object type; %s is %s (like E2019).'),
    (De: 'Der Vorfahr einer Klasse muss eine Klasse sein; %s ist %s (wie E2021).';
     En: 'The ancestor of a class must be a class; %s is %s (like E2021).'),
    (De: 'Der Vorfahr eines Class-Helpers muss ein Class-Helper sein; %s ist %s (wie E2022).';
     En: 'The ancestor of a class helper must be a class helper; %s is %s (like E2022).'),
    (De: 'Ein Record-Helper braucht einen Record oder einfachen Typ; %s ist %s, dafür gibt es class helper (wie ' +
      'E2474).';
     En: 'A record helper needs a record or simple type; %s is %s, there is class helper for that (like E2474).'),
    (De: 'New mit Konstruktor braucht einen Zeiger auf einen Record oder object-Typ';
     En: 'New with constructor needs a pointer to a record or object type'),
    (De: 'Dispose mit Destruktor braucht einen Zeiger auf einen object-Typ';
     En: 'Dispose with destructor needs a pointer to an object type'),
    (De: '%s; %s zeigt auf %s (wie %s).'; En: '%s; %s points to %s (like %s).'),
    (De: 'TypeOf braucht einen object-Typ mit VMT; %s ist %s (%s) (wie E2019).';
     En: 'TypeOf needs an object type with VMT; %s is %s (%s) (like E2019).'),
    (De: 'Slice ist nur als Argument für einen offenen Array-Parameter möglich (wie E2193).';
     En: 'Slice is only possible as argument for an open array parameter (like E2193).'),
    (De: '%s ist ein Record (%s); array of const nimmt keine Records (wie E2150).';
     En: '%s is a record (%s); array of const takes no records (like E2150).'),
    (De: '%s kann %s nicht einlesen: %s ist %s (wie E2055).'; En: '%s cannot read %s: %s is %s (like E2055).'),
    (De: '%s kann %s nicht ausgeben: %s ist %s (wie E2054).'; En: '%s cannot write %s: %s is %s (like E2054).'),
    (De: '%s ist keine Klassenmethode; %s.%s geht nur in Methoden von %s und seinen Nachfahren (wie E2076).';
     En: '%s is not a class method; %s.%s works only in methods of %s and its descendants (like E2076).'),
    (De: 'Ausdruck oder Deklaration hat nicht die geforderte Typart';
     En: 'Expression or declaration does not have the required type kind'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Ein Prüflauf über einen Baum; hält Namensauflösung und Ziel der Meldungen.</summary>
  TTypeKindChecker = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FResolver: TNameResolver;
    FFileName: string;
    FUsesKnown: Boolean;
    function NodeText(ANode: TSyntaxNode): string;
    function Range(ANode: TSyntaxNode): TTextRange;
    /// <summary>Wert ANode (kein Typ, keine Unit, nicht bedingt deklariert) samt Typ und Typart.</summary>
    function ValueType(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol;
      out AKind: TResolvedTypeKind): Boolean;
    /// <summary>Typart des Typnamens ATypeRef (TypeReference) an seiner Stelle; Unknown ohne sichere Auflösung.
    /// </summary>
    function ReferencedKind(ATypeRef: TSyntaxNode; out AType: TResolvedSymbol): TResolvedTypeKind;
    /// <summary>Kann ein Helfer für den Typ AType des Werts ASymbol an ANode Mitglieder liefern? Auch, wenn eine
    /// Unit aus uses fehlt. Gesucht wird für den Typ, seinen eingebauten Zielnamen und den deklarierten Alias.
    /// </summary>
    function HelperPossible(const ASymbol, AType: TResolvedSymbol; ANode: TSyntaxNode): Boolean;
    /// <summary>Record mit class operator Implicit: Der Compiler kann ihn umwandeln.</summary>
    function HasImplicit(const AType: TResolvedSymbol): Boolean;
    /// <summary>Ruft ACall die eingebaute Routine AName auf (nicht von einer eigenen gleichen Namens verdeckt)?
    /// </summary>
    function IsIntrinsic(ACall: TSyntaxNode; const AName: string): Boolean;
    /// <summary>Deklarierter Typ von ASymbol als Quelltext ("^Byte", "TextFile"): TypeName, sonst der Kopf aus
    /// dem Index, sonst die Deklaration im Baum (lokale Namen); '' ohne.</summary>
    function DeclaredTypeText(const ASymbol: TResolvedSymbol): string;
    /// <summary>Typname des Ziels des Zeigers ANode (^Integer, PInteger = ^Integer); '' ohne.</summary>
    function PointeeName(ANode: TSyntaxNode): string;
    /// <summary>Ist ANode eine Variable bzw. ein Parameter vom Typ Text oder TextFile (auch ohne System im
    /// Index)?</summary>
    function IsTextFile(ANode: TSyntaxNode): Boolean;
    procedure CheckIndex(ANode: TSyntaxNode);
    procedure CheckDereference(ANode: TSyntaxNode);
    procedure CheckMember(ANode: TSyntaxNode);
    procedure CheckWith(ANode: TSyntaxNode);
    procedure CheckObjectType(ANode: TSyntaxNode);
    procedure CheckClassType(ANode: TSyntaxNode);
    procedure CheckHelperType(ANode: TSyntaxNode);
    procedure CheckCall(ANode: TSyntaxNode);
    procedure CheckConstructorForm(ANode: TSyntaxNode);
    procedure CheckTypeOf(ANode: TSyntaxNode);
    procedure CheckSlice(ANode: TSyntaxNode);
    procedure CheckConstArray(ANode: TSyntaxNode);
    /// <summary>Erwartet jede mögliche Routine des Aufrufs von ACallee an der Stelle APosition einen Parameter
    /// einfacher Art (kein offenes Array, nicht unbekannt)?</summary>
    function AllSimpleParams(ACallee: TSyntaxNode; APosition: Integer): Boolean;
    procedure CheckTextIo(ANode: TSyntaxNode; AWrite: Boolean);
    /// <summary>Erstes Argument von Write/Read, das ausgegeben bzw. eingelesen wird: hinter einer Textdatei 2,
    /// sonst 1; False bei unbekanntem erstem Argument oder typisierter Datei.</summary>
    function FirstTextArgument(ANode: TSyntaxNode; out AFirst: Integer): Boolean;
    procedure CheckTextArgument(const ARoutine: string; AArg: TSyntaxNode; AWrite: Boolean);
    /// <summary>Basis von TBasis.Machen als Klasse: Bezeichner, nicht generisch, nicht bedingt.</summary>
    function ClassBase(ANode: TSyntaxNode; out ABaseType: TResolvedSymbol): Boolean;
    /// <summary>Ist ANode sicher eine Instanzmethode (alle möglichen Routinen ohne class und static)?</summary>
    function InstanceMethod(ANode: TSyntaxNode; out AMember: TResolvedSymbol): Boolean;
    /// <summary>Steht ANode in einer Methode, deren Klasse ABaseType oder ein Nachfahre ist, oder ist das nicht
    /// sicher zu sagen?</summary>
    function InsideOwnClass(ANode: TSyntaxNode; const ABaseType: TResolvedSymbol): Boolean;
    /// <summary>Gehört die Methode ARoutine (TKlasse.Name) zu ABaseType oder einem Nachfahren, oder ist das nicht
    /// sicher?</summary>
    function OwnClassMethod(ARoutine: TSyntaxNode; const ABaseType: TResolvedSymbol): Boolean;
    procedure CheckClassMethodForm(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport; AResolver: TNameResolver);
    procedure Run;
  end;

const
  cValueKinds = [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Constant,
    TIndexSymbolKind.Property_, TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.EnumMember];
  cExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference];
  // Standarddateien der Unit System für Write/Read ohne Dateiargument davor.
  cStandardTextFiles: array[0..2] of string = ('Input', 'Output', 'ErrOutput');

function ResolverFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
  begin
    Result := AContext.RelativePath;
  end;
  if Result = '' then
  begin
    Result := AContext.UnitName + '.pas';
  end;
end;

/// <summary>Alle Knoten unter ARoot in Pre-Order über einen eigenen Stapel (tiefe Ausdrucksketten, Bericht M1).
/// </summary>
function PreOrder(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  mPending: TStack<TSyntaxNode>;
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  if ARoot = nil then
  begin
    Exit;
  end;
  mPending := TStack<TSyntaxNode>.Create;
  mNodes := TList<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mNodes.Add(mNode);
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
    Result := mNodes.ToArray;
  finally
    mNodes.Free;
    mPending.Free;
  end;
end;

/// <summary>Liegt APosition im Bereich von ANode?</summary>
function Covers(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := ((ANode.StartPos.Line < APosition.Line) or ((ANode.StartPos.Line = APosition.Line) and
    (ANode.StartPos.Character <= APosition.Character))) and ((ANode.EndPos.Line > APosition.Line) or
    ((ANode.EndPos.Line = APosition.Line) and (ANode.EndPos.Character >= APosition.Character)));
end;

/// <summary>Direkte Kinder von ANode, die Typnamen sind (Vorfahren, Helferziel).</summary>
function TypeReferences(ANode: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind = TSyntaxKind.TypeReference then
    begin
      Result := Result + [ANode[mIndex]];
    end;
  end;
end;

/// <summary>Position von ANode unter den Argumenten seines Aufrufs (1 = erstes); 0, wenn ANode kein Argument ist.
/// </summary>
function ArgumentPosition(ANode: TSyntaxNode): Integer;
var
  mParent: TSyntaxNode;
  mIndex: Integer;
begin
  Result := 0;
  mParent := ANode.Parent;
  if (mParent = nil) or (mParent.Kind <> TSyntaxKind.Call) then
  begin
    Exit;
  end;
  for mIndex := 1 to mParent.ChildCount - 1 do
  begin
    if mParent[mIndex] = ANode then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Erwartet ACandidate an der Stelle APosition (ab 1) einen Parameter bekannter Art außer Array?</summary>
function SimpleParamAt(const ACandidate: TResolvedSymbol; APosition: Integer): Boolean;
var
  mKind: TResolvedTypeKind;
begin
  Result := not ACandidate.Builtin and (ACandidate.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]);
  Result := Result and (Length(ACandidate.ParamTypes) >= APosition);
  if Result then
  begin
    mKind := TResolvedTypeKinds.OfText(ACandidate.ParamTypes[APosition - 1]);
    Result := (mKind <> TResolvedTypeKind.Unknown) and (mKind <> TResolvedTypeKind.Array_);
  end;
end;

/// <summary>Steht ANode als Anweisung oder als Ziel eines Aufrufs (vor Klammern)?</summary>
function IsCalledForm(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.ChildCount = 1) and (ANode.Parent <> nil);
  Result := Result and ((ANode.Parent.Kind = TSyntaxKind.CallStatement) or
    ((ANode.Parent.Kind = TSyntaxKind.Call) and (ANode.Parent[0] = ANode)));
end;

/// <summary>Ist ACandidate eine Methode ohne class und static?</summary>
function IsInstanceCandidate(const ACandidate: TResolvedSymbol): Boolean;
begin
  Result := (ACandidate.SymbolKind = TIndexSymbolKind.Method) and not MatchText('class', ACandidate.Directives);
  Result := Result and not MatchText('static', ACandidate.Directives) and
    not StartsText('class ', Trim(ACandidate.Signature));
end;

{ TTypeKindChecker }

constructor TTypeKindChecker.Create(const AContext: TRuleContext; const AReport: IRuleReport;
  AResolver: TNameResolver);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FResolver := AResolver;
  FFileName := ResolverFileName(AContext);
  FUsesKnown := (AContext.Index <> nil) and TUnresolvedNames.UsesKnown(AContext.Index,
    TUsesClauses.UsedUnits(AContext.Tree.Tokens), AContext.Namespaces, AContext.EnsureUnit);
end;

function TTypeKindChecker.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TTypeKindChecker.Range(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function TTypeKindChecker.ValueType(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol;
  out AKind: TResolvedTypeKind): Boolean;
var
  mNode: TSyntaxNode;
  mFound: Boolean;
begin
  AKind := TResolvedTypeKind.Unknown;
  mNode := ANode;
  while (mNode.Kind = TSyntaxKind.ParenExpr) and (mNode.ChildCount = 1) do
  begin
    mNode := mNode[0];
  end;
  Result := (mNode.Kind in cExpressionKinds) and
    FResolver.NodeType(FContext.Tree, FFileName, mNode, ASymbol, AType, mFound) and mFound and
    not ASymbol.IsType and (ASymbol.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and
    (ASymbol.SymbolKind in cValueKinds) and (ASymbol.Condition = '') and (ASymbol.VariantBranch = '') and
    (AType.TypeParams = '');
  if Result then
  begin
    AKind := TResolvedTypeKinds.OfType(AType);
    Result := AKind <> TResolvedTypeKind.Unknown;
  end;
end;

function TTypeKindChecker.ReferencedKind(ATypeRef: TSyntaxNode; out AType: TResolvedSymbol): TResolvedTypeKind;
var
  mResolved: TResolvedSymbol;
  mName: string;
begin
  Result := TResolvedTypeKind.Unknown;
  AType := Default(TResolvedSymbol);
  mName := Trim(ATypeRef.Name);
  if (mName = '') or ContainsStr(mName, '<') then
  begin
    Exit;
  end;
  if (Pos('.', mName) = 0) and TResolverText.IsBuiltinTypeName(mName) then
  begin
    Result := TResolvedTypeKinds.OfBuiltin(mName);
    AType.Name := mName;
    Exit;
  end;
  mResolved := FResolver.ResolveChain(FContext.Tree, FFileName, mName.Split(['.']), ATypeRef.StartOffset);
  if not mResolved.Found or not mResolved.IsType or (mResolved.Condition <> '') or
    not FResolver.TypeOf(mResolved, AType) then
  begin
    Exit;
  end;
  if AType.TypeParams <> '' then
  begin
    Exit;
  end;
  Result := TResolvedTypeKinds.OfType(AType);
end;

function TTypeKindChecker.HelperPossible(const ASymbol, AType: TResolvedSymbol; ANode: TSyntaxNode): Boolean;
var
  mHelper: TResolvedSymbol;
  mNames: TArray<string>;
  mName: string;
begin
  if not FUsesKnown then
  begin
    Exit(True);
  end;
  // Helfer gelten auch für eingebaute Aliase (TIntegerHelper für LongInt) und für den Alias, mit dem der Wert
  // deklariert ist (record helper for TZahl mit TZahl = Integer).
  mNames := TArray<string>.Create(AType.Name, TTypeIdentity.BuiltinName(AType.Name), DeclaredTypeText(ASymbol));
  for mName in mNames do
  begin
    if (mName <> '') and IsValidIdent(mName, True) and
      FResolver.VisibleHelper(FContext.Tree, FFileName, mName, ANode.StartOffset, mHelper) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TTypeKindChecker.HasImplicit(const AType: TResolvedSymbol): Boolean;
var
  mMember: TResolvedSymbol;
begin
  Result := FResolver.FindMember(AType, 'Implicit', mMember);
end;

function TTypeKindChecker.IsIntrinsic(ACall: TSyntaxNode; const AName: string): Boolean;
var
  mCallee: TSyntaxNode;
  mSymbol, mType: TResolvedSymbol;
  mFound: Boolean;
begin
  Result := False;
  if (ACall.Kind <> TSyntaxKind.Call) or (ACall.ChildCount = 0) then
  begin
    Exit;
  end;
  mCallee := ACall[0];
  if (mCallee.Kind <> TSyntaxKind.Identifier) or not SameText(mCallee.Name, AName) then
  begin
    Exit;
  end;
  // Ohne Deklaration im Index ist es die eingebaute Routine, sofern keine unbekannte Unit eine gleichnamige bringt.
  if not FResolver.NodeType(FContext.Tree, FFileName, mCallee, mSymbol, mType, mFound) then
  begin
    Exit(FUsesKnown);
  end;
  Result := mSymbol.Builtin or SameText(mSymbol.UnitName, 'System');
end;

function TTypeKindChecker.DeclaredTypeText(const ASymbol: TResolvedSymbol): string;
var
  mNode, mDecl: TSyntaxNode;
  mIndex: Integer;
begin
  Result := Trim(ASymbol.TypeName);
  if Result <> '' then
  begin
    Exit;
  end;
  Result := TResolvedTypeKinds.DeclaredText(ASymbol.Signature);
  if (Result <> '') or (ASymbol.Kind <> TResolvedKind.Local) then
  begin
    Exit;
  end;
  // Lokale Variable mit Typ ohne Namen (mZeiger: ^Byte): Text des Typknotens ihrer Deklaration, die innerste
  // um den Namen.
  mDecl := nil;
  for mNode in PreOrder(FContext.Tree.Root) do
  begin
    if (mNode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.Field, TSyntaxKind.InlineVar]) and
      Covers(mNode, ASymbol.SelectionRange.StartPos) then
    begin
      mDecl := mNode;
    end;
  end;
  if mDecl <> nil then
  begin
    for mIndex := 0 to mDecl.ChildCount - 1 do
    begin
      if mDecl[mIndex].Kind in [TSyntaxKind.TypeReference, TSyntaxKind.PointerType, TSyntaxKind.ArrayType,
        TSyntaxKind.FileType, TSyntaxKind.SetType] then
      begin
        Exit(Trim(NodeText(mDecl[mIndex])));
      end;
    end;
  end;
end;

function TTypeKindChecker.PointeeName(ANode: TSyntaxNode): string;
var
  mSymbol, mType: TResolvedSymbol;
  mFound: Boolean;
  mText: string;
begin
  Result := '';
  if not (ANode.Kind in cExpressionKinds) or
    not FResolver.NodeType(FContext.Tree, FFileName, ANode, mSymbol, mType, mFound) or mSymbol.IsType or
    not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) or (mSymbol.Condition <> '') then
  begin
    Exit;
  end;
  mText := DeclaredTypeText(mSymbol);
  if not StartsStr('^', mText) and mFound and not mType.Builtin and
    (mType.SymbolKind = TIndexSymbolKind.TypeAlias) then
  begin
    mText := TResolvedTypeKinds.DeclaredText(mType.Signature);
  end;
  if StartsStr('^', mText) then
  begin
    Result := Trim(Copy(mText, 2, MaxInt));
  end;
end;

function TTypeKindChecker.IsTextFile(ANode: TSyntaxNode): Boolean;
var
  mSymbol, mType: TResolvedSymbol;
  mFound: Boolean;
  mText: string;
begin
  Result := False;
  if not (ANode.Kind in cExpressionKinds) or
    not FResolver.NodeType(FContext.Tree, FFileName, ANode, mSymbol, mType, mFound) or mSymbol.IsType or
    not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) then
  begin
    Exit;
  end;
  mText := DeclaredTypeText(mSymbol);
  if StartsText('System.', mText) then
  begin
    mText := Copy(mText, 8, MaxInt);
  end;
  Result := MatchText(mText, ['Text', 'TextFile']);
  if not Result and mFound and not mType.Builtin and (mType.SymbolKind = TIndexSymbolKind.TypeAlias) then
  begin
    Result := MatchText(TResolvedTypeKinds.DeclaredText(mType.Signature), ['Text', 'TextFile']);
  end;
end;

procedure TTypeKindChecker.CheckIndex(ANode: TSyntaxNode);
var
  mSymbol, mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
begin
  // Properties mit Index und Funktionen ohne Klammern sehen im Baum gleich aus; nur Variablen, Felder, Konstanten.
  if (ANode.ChildCount = 0) or not ValueType(ANode[0], mSymbol, mType, mKind) or
    not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Constant]) or
    not TResolvedTypeKinds.IsSimpleValue(mKind) or HelperPossible(mSymbol, mType, ANode) then
  begin
    Exit;
  end;
  FReport.Add(Range(ANode), cTexts[TTypeKindsText.NotArray].Fmt(
    [NodeText(ANode[0]), TResolvedTypeKinds.Describe(mKind), mType.Name]), TRuleConfidence.High);
end;

procedure TTypeKindChecker.CheckDereference(ANode: TSyntaxNode);
var
  mSymbol, mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
  mFixes: TArray<TRuleFix>;
  mBase: string;
begin
  if (ANode.ChildCount <> 1) or not ValueType(ANode[0], mSymbol, mType, mKind) then
  begin
    Exit;
  end;
  if not TResolvedTypeKinds.IsSimpleValue(mKind) and not (mKind in [TResolvedTypeKind.Class_,
    TResolvedTypeKind.Record_, TResolvedTypeKind.Interface_]) then
  begin
    Exit;
  end;
  mBase := NodeText(ANode[0]);
  mFixes := nil;
  // Obj^.Feld: Klassen und Interfaces sind schon Verweise, Records erreicht der Punkt direkt.
  if not TResolvedTypeKinds.IsSimpleValue(mKind) and (ANode.Parent <> nil) and
    (ANode.Parent.Kind = TSyntaxKind.MemberAccess) and (ANode.Parent.ChildCount > 0) and
    (ANode.Parent[0] = ANode) then
  begin
    mFixes := [TRuleFix.Create(cTexts[TTypeKindsText.RemoveCaret].Text, [TTextEdit.Create(Range(ANode), mBase)], True)];
  end;
  FReport.Add(Range(ANode), cTexts[TTypeKindsText.NotPointer].Fmt(
    [mBase, TResolvedTypeKinds.Describe(mKind), mType.Name]), TRuleConfidence.High, mFixes);
end;

procedure TTypeKindChecker.CheckMember(ANode: TSyntaxNode);
var
  mSymbol, mType, mMember: TResolvedSymbol;
  mKind: TResolvedTypeKind;
begin
  // X.TryGetValue<Integer>: Der Parser legt um X.TryGetValue einen Knoten gleichen Namens mit den Typargumenten;
  // das ist kein Punkt auf dem Ergebnis.
  if (ANode.ChildCount > 1) and (ANode[ANode.ChildCount - 1].Kind = TSyntaxKind.GenericArgs) then
  begin
    Exit;
  end;
  if (ANode.ChildCount = 0) or not ValueType(ANode[0], mSymbol, mType, mKind) or
    not TResolvedTypeKinds.IsSimpleValue(mKind) or HelperPossible(mSymbol, mType, ANode) or
    FResolver.FindMember(mType, ANode.Name, mMember) then
  begin
    Exit;
  end;
  FReport.Add(Range(ANode), cTexts[TTypeKindsText.NotStructured].Fmt([NodeText(ANode[0]),
    TResolvedTypeKinds.Describe(mKind), mType.Name, ANode.Name]),
    TRuleConfidence.High);
end;

procedure TTypeKindChecker.CheckWith(ANode: TSyntaxNode);
var
  mIndex: Integer;
  mElement: TSyntaxNode;
  mSymbol, mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mElement := ANode[mIndex];
    if not (mElement.Kind in cExpressionKinds + [TSyntaxKind.ParenExpr]) or
      not ValueType(mElement, mSymbol, mType, mKind) or not TResolvedTypeKinds.IsSimpleValue(mKind) or
      HelperPossible(mSymbol, mType, mElement) then
    begin
      Continue;
    end;
    FReport.Add(Range(mElement), cTexts[TTypeKindsText.WithNeeds].Fmt([NodeText(mElement),
      TResolvedTypeKinds.Describe(mKind), mType.Name]),
      TRuleConfidence.High);
  end;
end;

procedure TTypeKindChecker.CheckObjectType(ANode: TSyntaxNode);
var
  mRefs: TArray<TSyntaxNode>;
  mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
begin
  mRefs := TypeReferences(ANode);
  if Length(mRefs) = 0 then
  begin
    Exit;
  end;
  mKind := ReferencedKind(mRefs[0], mType);
  if not (mKind in [TResolvedTypeKind.Class_, TResolvedTypeKind.Record_, TResolvedTypeKind.Interface_,
    TResolvedTypeKind.Helper]) then
  begin
    Exit;
  end;
  FReport.Add(Range(mRefs[0]), cTexts[TTypeKindsText.ObjectAncestor].Fmt([mRefs[0].Name,
    TResolvedTypeKinds.Describe(mKind)]), TRuleConfidence.High);
end;

procedure TTypeKindChecker.CheckClassType(ANode: TSyntaxNode);
var
  mRefs: TArray<TSyntaxNode>;
  mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
begin
  mRefs := TypeReferences(ANode);
  if Length(mRefs) = 0 then
  begin
    Exit;
  end;
  mKind := ReferencedKind(mRefs[0], mType);
  if (mKind in [TResolvedTypeKind.Unknown, TResolvedTypeKind.Class_, TResolvedTypeKind.Interface_,
    TResolvedTypeKind.Helper, TResolvedTypeKind.Object_]) then
  begin
    Exit;
  end;
  FReport.Add(Range(mRefs[0]), cTexts[TTypeKindsText.ClassAncestor].Fmt(
    [mRefs[0].Name, TResolvedTypeKinds.Describe(mKind)]), TRuleConfidence.High);
end;

procedure TTypeKindChecker.CheckHelperType(ANode: TSyntaxNode);
var
  mRefs: TArray<TSyntaxNode>;
  mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
  mTarget: TSyntaxNode;
begin
  mRefs := TypeReferences(ANode);
  if Length(mRefs) = 0 then
  begin
    Exit;
  end;
  mTarget := mRefs[High(mRefs)];
  if SameText(ANode.Name, 'class') and (Length(mRefs) = 2) then
  begin
    // class helper (TVorfahr) for TZiel: Der Vorfahr muss selbst ein Class-Helper sein.
    mKind := ReferencedKind(mRefs[0], mType);
    if mKind in [TResolvedTypeKind.Class_, TResolvedTypeKind.Record_, TResolvedTypeKind.Interface_,
      TResolvedTypeKind.Object_] then
    begin
      FReport.Add(Range(mRefs[0]), cTexts[TTypeKindsText.HelperAncestor].Fmt([mRefs[0].Name,
        TResolvedTypeKinds.Describe(mKind)]), TRuleConfidence.High);
    end;
  end
  else if SameText(ANode.Name, 'record') then
  begin
    mKind := ReferencedKind(mTarget, mType);
    if mKind in [TResolvedTypeKind.Class_, TResolvedTypeKind.Interface_] then
    begin
      FReport.Add(Range(mTarget), cTexts[TTypeKindsText.RecordHelper].Fmt([mTarget.Name,
        TResolvedTypeKinds.Describe(mKind)]),
        TRuleConfidence.High);
    end;
  end;
end;

procedure TTypeKindChecker.CheckConstructorForm(ANode: TSyntaxNode);
var
  mPointee, mRoutine, mCode: string;
  mKind: TResolvedTypeKind;
begin
  // New(P, Init) bzw. Dispose(P, Done): erweiterte Form nur für Zeiger auf object-Typen.
  if ANode.ChildCount < 3 then
  begin
    Exit;
  end;
  if IsIntrinsic(ANode, 'New') then
  begin
    mRoutine := cTexts[TTypeKindsText.NewCtor].Text;
    mCode := 'E2467';
  end
  else if IsIntrinsic(ANode, 'Dispose') then
  begin
    mRoutine := cTexts[TTypeKindsText.DisposeDtor].Text;
    mCode := 'E2019';
  end
  else
  begin
    Exit;
  end;
  mPointee := PointeeName(ANode[1]);
  if (mPointee = '') or not TResolverText.IsBuiltinTypeName(mPointee) then
  begin
    Exit;
  end;
  mKind := TResolvedTypeKinds.OfBuiltin(mPointee);
  if not TResolvedTypeKinds.IsSimpleValue(mKind) then
  begin
    Exit;
  end;
  FReport.Add(Range(ANode[1]), cTexts[TTypeKindsText.PointsTo].Fmt([mRoutine, NodeText(ANode[1]), mPointee,
    mCode]), TRuleConfidence.High);
end;

procedure TTypeKindChecker.CheckTypeOf(ANode: TSyntaxNode);
var
  mSymbol, mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
begin
  if (ANode.ChildCount <> 2) or not IsIntrinsic(ANode, 'TypeOf') or
    not ValueType(ANode[1], mSymbol, mType, mKind) or not TResolvedTypeKinds.IsSimpleValue(mKind) then
  begin
    Exit;
  end;
  FReport.Add(Range(ANode[1]), cTexts[TTypeKindsText.TypeOf].Fmt(
    [NodeText(ANode[1]), TResolvedTypeKinds.Describe(mKind), mType.Name]), TRuleConfidence.High);
end;

function TTypeKindChecker.AllSimpleParams(ACallee: TSyntaxNode; APosition: Integer): Boolean;
var
  mCandidates: TArray<TResolvedSymbol>;
  mCandidate: TResolvedSymbol;
begin
  mCandidates := FResolver.CallCandidates(FContext.Tree, FFileName, ACallee);
  Result := Length(mCandidates) > 0;
  for mCandidate in mCandidates do
  begin
    if not SimpleParamAt(mCandidate, APosition) then
    begin
      Exit(False);
    end;
  end;
end;

procedure TTypeKindChecker.CheckSlice(ANode: TSyntaxNode);
var
  mPosition: Integer;
  mMisplaced: Boolean;
begin
  if not IsIntrinsic(ANode, 'Slice') or (ANode.Parent = nil) then
  begin
    Exit;
  end;
  mPosition := ArgumentPosition(ANode);
  if mPosition = 0 then
  begin
    // Als Wert einer Zuweisung, in einem Ausdruck oder als Startwert einer Inline-Variablen.
    mMisplaced := ANode.Parent.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.BinaryExpr, TSyntaxKind.InlineVar];
  end
  else
  begin
    // Argument eines Aufrufs: nur, wenn jede mögliche Routine dort einen Parameter einfacher Art erwartet.
    mMisplaced := AllSimpleParams(ANode.Parent[0], mPosition);
  end;
  if mMisplaced then
  begin
    FReport.Add(Range(ANode), cTexts[TTypeKindsText.Slice].Text,
      TRuleConfidence.High);
  end;
end;

procedure TTypeKindChecker.CheckConstArray(ANode: TSyntaxNode);
var
  mPosition, mIndex: Integer;
  mCandidates: TArray<TResolvedSymbol>;
  mCandidate, mSymbol, mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
  mElement: TSyntaxNode;
begin
  mPosition := ArgumentPosition(ANode);
  if mPosition = 0 then
  begin
    Exit;
  end;
  mCandidates := FResolver.CallCandidates(FContext.Tree, FFileName, ANode.Parent[0]);
  if Length(mCandidates) = 0 then
  begin
    Exit;
  end;
  for mCandidate in mCandidates do
  begin
    if mCandidate.Builtin or (Length(mCandidate.ParamTypes) < mPosition) or
      not SameText(Trim(mCandidate.ParamTypes[mPosition - 1]), 'array of const') then
    begin
      Exit;
    end;
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mElement := ANode[mIndex];
    if not ValueType(mElement, mSymbol, mType, mKind) or (mKind <> TResolvedTypeKind.Record_) or
      HasImplicit(mType) then
    begin
      Continue;
    end;
    FReport.Add(Range(mElement), cTexts[TTypeKindsText.RecordConst].Fmt(
      [NodeText(mElement), mType.Name]), TRuleConfidence.High);
  end;
end;

function TTypeKindChecker.FirstTextArgument(ANode: TSyntaxNode; out AFirst: Integer): Boolean;
var
  mArg: TSyntaxNode;
  mSymbol, mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
begin
  Result := True;
  AFirst := 2;
  mArg := ANode[1];
  if (mArg.Kind = TSyntaxKind.Identifier) and MatchText(mArg.Name, cStandardTextFiles) and
    not ValueType(mArg, mSymbol, mType, mKind) then
  begin
    // Input, Output, ErrOutput aus System, auch ohne System im Index.
    Exit;
  end;
  if IsTextFile(mArg) then
  begin
    Exit;
  end;
  AFirst := 1;
  // Unbekanntes erstes Argument oder typisierte Datei (Write(F, Datensatz)).
  Result := ValueType(mArg, mSymbol, mType, mKind) and (mKind <> TResolvedTypeKind.File_);
end;

procedure TTypeKindChecker.CheckTextArgument(const ARoutine: string; AArg: TSyntaxNode; AWrite: Boolean);
var
  mSymbol, mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
  mText: string;
  mFixes: TArray<TRuleFix>;
begin
  if not ValueType(AArg, mSymbol, mType, mKind) or not (mKind in [TResolvedTypeKind.Class_,
    TResolvedTypeKind.Record_, TResolvedTypeKind.Interface_]) or
    ((mKind = TResolvedTypeKind.Record_) and HasImplicit(mType)) then
  begin
    Exit;
  end;
  mText := NodeText(AArg);
  if not AWrite then
  begin
    FReport.Add(Range(AArg), cTexts[TTypeKindsText.CannotRead].Fmt([ARoutine, mText,
      mType.Name, TResolvedTypeKinds.Describe(mKind)]), TRuleConfidence.High);
    Exit;
  end;
  mFixes := nil;
  if mKind = TResolvedTypeKind.Class_ then
  begin
    mFixes := [TRuleFix.Create(mText + '.ToString', [TTextEdit.Create(Range(AArg), mText + '.ToString')])];
  end;
  FReport.Add(Range(AArg), cTexts[TTypeKindsText.CannotWrite].Fmt([ARoutine, mText,
    mType.Name, TResolvedTypeKinds.Describe(mKind)]), TRuleConfidence.High, mFixes);
end;

procedure TTypeKindChecker.CheckTextIo(ANode: TSyntaxNode; AWrite: Boolean);
var
  mFirst, mIndex: Integer;
begin
  if (ANode.ChildCount < 2) or not FirstTextArgument(ANode, mFirst) then
  begin
    Exit;
  end;
  for mIndex := mFirst to ANode.ChildCount - 1 do
  begin
    CheckTextArgument(ANode[0].Name, ANode[mIndex], AWrite);
  end;
end;

function TTypeKindChecker.ClassBase(ANode: TSyntaxNode; out ABaseType: TResolvedSymbol): Boolean;
var
  mBase: TSyntaxNode;
  mBaseSymbol: TResolvedSymbol;
  mFound: Boolean;
begin
  mBase := ANode[0];
  Result := (mBase.Kind = TSyntaxKind.Identifier) and
    FResolver.NodeType(FContext.Tree, FFileName, mBase, mBaseSymbol, ABaseType, mFound);
  Result := Result and mBaseSymbol.IsType and (mBaseSymbol.SymbolKind = TIndexSymbolKind.ClassType);
  Result := Result and (mBaseSymbol.TypeParams = '') and (mBaseSymbol.Condition = '');
end;

function TTypeKindChecker.InstanceMethod(ANode: TSyntaxNode; out AMember: TResolvedSymbol): Boolean;
var
  mMemberType, mCandidate: TResolvedSymbol;
  mCandidates: TArray<TResolvedSymbol>;
  mFound: Boolean;
begin
  Result := FResolver.NodeType(FContext.Tree, FFileName, ANode, AMember, mMemberType, mFound) and
    (AMember.SymbolKind = TIndexSymbolKind.Method) and (AMember.Condition = '');
  if not Result then
  begin
    Exit;
  end;
  mCandidates := FResolver.CallCandidates(FContext.Tree, FFileName, ANode);
  Result := Length(mCandidates) > 0;
  for mCandidate in mCandidates do
  begin
    if not IsInstanceCandidate(mCandidate) then
    begin
      Exit(False);
    end;
  end;
end;

function TTypeKindChecker.OwnClassMethod(ARoutine: TSyntaxNode; const ABaseType: TResolvedSymbol): Boolean;
var
  mOwner, mOwnerType: TResolvedSymbol;
  mClassPart: string;
  mComplete: Boolean;
  mAncestors: TArray<string>;
begin
  mClassPart := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
  mOwner := FResolver.ResolveChain(FContext.Tree, FFileName, mClassPart.Split(['.']), ARoutine.StartOffset);
  Result := not mOwner.Found or not FResolver.TypeOf(mOwner, mOwnerType) or
    (mOwnerType.SymbolKind <> TIndexSymbolKind.ClassType);
  if Result or SameText(mOwnerType.QualifiedName, ABaseType.QualifiedName) then
  begin
    Exit(True);
  end;
  mAncestors := FResolver.Queries.AncestorNames(mOwnerType, mComplete);
  Result := not mComplete or MatchText(ABaseType.Name, mAncestors);
end;

function TTypeKindChecker.InsideOwnClass(ANode: TSyntaxNode; const ABaseType: TResolvedSymbol): Boolean;
var
  mOuter: TSyntaxNode;
begin
  mOuter := ANode.Parent;
  while mOuter <> nil do
  begin
    if (mOuter.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', mOuter.Name) > 0) and
      OwnClassMethod(mOuter, ABaseType) then
    begin
      Exit(True);
    end;
    mOuter := mOuter.Parent;
  end;
  Result := False;
end;

procedure TTypeKindChecker.CheckClassMethodForm(ANode: TSyntaxNode);
var
  mBaseType, mMember: TResolvedSymbol;
begin
  // TBasis.Machen als Anweisung oder vor Klammern.
  if not IsCalledForm(ANode) or not ClassBase(ANode, mBaseType) or not InstanceMethod(ANode, mMember) then
  begin
    Exit;
  end;
  // In Methoden der Klasse und ihrer Nachfahren ruft TBasis.Machen die Methode mit Self auf.
  if not InsideOwnClass(ANode, mBaseType) then
  begin
    FReport.Add(Range(ANode), cTexts[TTypeKindsText.NotClassMethod].Fmt([mMember.Name, ANode[0].Name, ANode.Name,
      mBaseType.Name]), TRuleConfidence.High);
  end;
end;

procedure TTypeKindChecker.CheckCall(ANode: TSyntaxNode);
var
  mCallee: string;
begin
  if (ANode.ChildCount = 0) or (ANode[0].Kind <> TSyntaxKind.Identifier) then
  begin
    Exit;
  end;
  mCallee := ANode[0].Name;
  if MatchText(mCallee, ['New', 'Dispose']) then
  begin
    CheckConstructorForm(ANode);
  end
  else if SameText(mCallee, 'TypeOf') then
  begin
    CheckTypeOf(ANode);
  end
  else if SameText(mCallee, 'Slice') then
  begin
    CheckSlice(ANode);
  end
  else if MatchText(mCallee, ['Write', 'Writeln']) and IsIntrinsic(ANode, mCallee) then
  begin
    CheckTextIo(ANode, True);
  end
  else if MatchText(mCallee, ['Read', 'Readln']) and IsIntrinsic(ANode, mCallee) then
  begin
    CheckTextIo(ANode, False);
  end;
end;

procedure TTypeKindChecker.Run;
var
  mNode: TSyntaxNode;
begin
  for mNode in PreOrder(FContext.Tree.Root) do
    case mNode.Kind of
      TSyntaxKind.IndexAccess:
        CheckIndex(mNode);
      TSyntaxKind.Dereference:
        CheckDereference(mNode);
      TSyntaxKind.MemberAccess:
        begin
          CheckMember(mNode);
          CheckClassMethodForm(mNode);
        end;
      TSyntaxKind.WithStatement:
        CheckWith(mNode);
      TSyntaxKind.ObjectType:
        CheckObjectType(mNode);
      TSyntaxKind.ClassType:
        CheckClassType(mNode);
      TSyntaxKind.HelperType:
        CheckHelperType(mNode);
      TSyntaxKind.Call:
        CheckCall(mNode);
      TSyntaxKind.SetConstructor:
        CheckConstArray(mNode);
    else
      // Übrige Knoten verlangen keine Typart.
    end;
end;

{ TTypeKindRequiredRule }

function TTypeKindRequiredRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cTypeKindRequiredRuleId, TRuleSeverity.Error,
    cTexts[TTypeKindsText.Title].Text);
end;

procedure TTypeKindRequiredRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mChecker: TTypeKindChecker;
  mFileName: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mFileName := ResolverFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mResolver.PinTree(AContext.Tree, mFileName);
  try
    mChecker := TTypeKindChecker.Create(AContext, AReport, mResolver);
    try
      mChecker.Run;
    finally
      mChecker.Free;
    end;
  finally
    mResolver.UnpinTree;
  end;
end;

procedure RegisterTypeKindRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TTypeKindRequiredRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TypeKinds', cTexts);

end.
