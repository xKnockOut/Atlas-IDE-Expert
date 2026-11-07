unit Atlas.Common.Rules.Builtin.TypeDeclarations;

// Regeln zur Deklaration von Klassen- und Interface-Mitgliedern (#909, Gruppe
// Compiler vorab):
//   message-method-invalid
//                        message-Methode einer Klasse (#1070): nicht genau ein
//                        var-Parameter (wie E2138), Nachrichtennummer kleiner
//                        als 1 (wie E2139) oder dieselbe Nummer wie eine
//                        frühere message-Methode derselben Klasse (wie E2140).
//                        Gleich heißt: gleicher Wert über die Konstantenwerte
//                        (Semantics.ConstantValues) oder gleicher Ausdruck.
//                        Methoden in sich ausschließenden {$IF}-Zweigen
//                        (Pascal.ConditionalBranches) gelten nicht als doppelt.
//                        Korrektur für E2138: einen einzelnen Parameter zu
//                        var machen, sonst die Liste durch (var Msg: TMessage)
//                        ersetzen; der Rumpf in derselben Datei wird mit
//                        angepasst.
//   interface-declaration-invalid
//                        unzulässige Deklarationen in Interfaces (#1075):
//                        Felder (wie E2209), Sichtbarkeitsabschnitte und
//                        Direktiven wie virtual (wie E2210), Klauseln stored,
//                        default mit Wert und nodefault an Properties (wie
//                        E2207), Properties, die ein Vorfahr-Interface schon
//                        deklariert und hier ohne Typ nur neu aufführen (wie
//                        E2206; mit Typ übersetzt dcc die Neudeklaration, so
//                        in DUnitX, JCL und Spring4D, #1328), Klassen,
//                        Records und Aufzählungen als Vorfahr eines Interfaces
//                        oder in der Interface-Liste einer Klasse (wie E2205)
//                        und doppelte Einträge dieser Liste (wie E2208).
//                        Typen löst TNameResolver über die uses-Klauseln auf;
//                        Aliase, unbekannte Typen, dispinterface und
//                        Deklarationen in bedingten Zweigen bleiben still.
//   implements-clause-invalid
//                        Delegation mit implements (#1076): nur in Klassen
//                        (wie E2258), nur an Properties mit Klassen- oder
//                        Interface-Typ (wie E2259), nicht mit index (wie
//                        E2260), nur mit read (wie E2261), Getter ohne
//                        Aufrufkonvention außer register (wie E2262) und ohne
//                        dynamic oder message (wie E2263, dazu E2148), jedes Interface nur
//                        einmal (wie E2257) und keine Methodenzuordnung für
//                        ein so umgesetztes Interface (wie E2264).
//   calling-convention-required
//                        Aufrufkonventionen, die der Compiler vorschreibt
//                        (#1078): Konstruktoren und Destruktoren einer Klasse
//                        nur mit register (wie E2236), Getter und Setter
//                        von published-Properties ebenso (wie E2270), varargs
//                        bei external nur mit cdecl (wie E2277). varargs
//                        ohne external meldet dcc nur unter Win32, mit jeder
//                        Konvention (wie E2277, Cm.E2277, #1380); unter Win64
//                        übersetzt es, die Regel richtet sich nach der
//                        Plattform des Baums (TSyntaxTree.Platform).
//                        Korrektur: die Konvention in Deklaration und Rumpf
//                        der Datei entfernen bzw. cdecl setzen.
//   dispinterface-invalid
//                        unzulässige dispinterface-Deklarationen (#1374): ein
//                        Vorfahr in Klammern (wie E2228), keine GUID (wie
//                        E2229), Direktiven an Methoden außer dispid und den
//                        Hinweisen deprecated, platform, library und
//                        experimental (wie E2230; gemeldet werden nur
//                        Aufrufkonventionen und Bindungsdirektiven wie
//                        virtual, overload bleibt still) und read oder write an
//                        Properties (wie E2231). Vorwärtsdeklarationen und
//                        Deklarationen in bedingten Zweigen bleiben still.
//                        Korrekturen: Vorfahren entfernen, GUID einfügen,
//                        Direktive entfernen.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cMessageMethodInvalidRuleId = 'message-method-invalid';
  cInterfaceDeclarationInvalidRuleId = 'interface-declaration-invalid';
  cImplementsClauseInvalidRuleId = 'implements-clause-invalid';
  cCallingConventionRequiredRuleId = 'calling-convention-required';
  cDispinterfaceInvalidRuleId = 'dispinterface-invalid';

type
  TMessageMethodInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInterfaceDeclarationInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TImplementsClauseInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCallingConventionRequiredRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDispinterfaceInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterTypeDeclarationRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Rules.Builtin.General,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTypeDeclarationsText = (MessageTitle, PassAsVar, InsertSignature, MessageParam, MessageNumber, MessageHandled,
    InterfaceTitle, RecordKind, EnumKind, ClassKind, NotInterface, AlreadyListed, ClauseNotAllowed,
    PropertyRedeclared, NoFields, DirectiveNotAllowed, ImplementsTitle, ImplementsType, GetterRegister, GetterNot,
    ImplementsIndex, AlreadyImplemented, ImplementsClassOnly, ImplementsReadable, MethodResolution, ConventionTitle,
    RemoveName, CtorRegister, PublishedRegister, VarargsWin32, VarargsCdecl, SetCdecl, DispTitle, DispAncestor,
    RemoveAncestor, DispGuid, InsertGuid, DispMethodDirective, DispDirective);

const
  cTexts: array[TTypeDeclarationsText] of TAtlasText = (
    (De: 'message-Methode falsch deklariert'; En: 'message method declared incorrectly'),
    (De: 'Parameter %s als var übergeben'; En: 'Pass parameter %s as var'),
    (De: 'Signatur %s einsetzen'; En: 'Insert signature %s'),
    (De: 'Die message-Methode %s braucht genau einen var-Parameter (wie E2138).';
     En: 'The message method %s needs exactly one var parameter (like E2138).'),
    (De: 'Die Nachrichtennummer %s von %s muss mindestens 1 sein (wie E2139).';
     En: 'The message number %s of %s must be at least 1 (like E2139).'),
    (De: '%s wird schon von %s behandelt (wie E2140).'; En: '%s is already handled by %s (like E2140).'),
    (De: 'Unzulässige Deklaration in einem Interface'; En: 'Invalid declaration in an interface'),
    (De: 'ein Record'; En: 'a record'),
    (De: 'eine Aufzählung'; En: 'an enumeration'),
    (De: 'eine Klasse'; En: 'a class'),
    (De: '%s ist %s und kein Interface (wie E2205).'; En: '%s is %s and not an interface (like E2205).'),
    (De: '%s steht schon in der Liste der Interfaces (wie E2208).';
     En: '%s is already in the list of interfaces (like E2208).'),
    (De: 'Die Klausel %s ist in Interfaces nicht erlaubt (wie E2207).';
     En: 'The clause %s is not allowed in interfaces (like E2207).'),
    (De: 'Die Property %s ist schon in %s deklariert; Interfaces dürfen Properties nicht ohne Typ neu aufführen (wie ' +
      'E2206).';
     En: 'The property %s is already declared in %s; interfaces must not list properties again without type (like ' +
      'E2206).'),
    (De: 'Interfaces dürfen keine Felder haben (wie E2209).'; En: 'Interfaces must not have fields (like E2209).'),
    (De: 'Die Direktive %s ist in Interfaces nicht erlaubt (wie E2210).';
     En: 'The directive %s is not allowed in interfaces (like E2210).'),
    (De: 'implements-Klausel unzulässig'; En: 'implements clause invalid'),
    (De: 'implements ist nur an Properties mit Klassen- oder Interface-Typ erlaubt, %s ist keiner (wie E2259).';
     En: 'implements is only allowed on properties with class or interface type, %s is none (like E2259).'),
    (De: 'Der Getter %s einer implements-Property darf nicht %s sein, nur register (wie E2262).';
     En: 'The getter %s of an implements property must not be %s, only register (like E2262).'),
    (De: 'Der Getter %s einer implements-Property darf nicht %s sein (wie E2263 und E2148).';
     En: 'The getter %s of an implements property must not be %s (like E2263 and E2148).'),
    (De: 'implements ist nicht zusammen mit index erlaubt (wie E2260).';
     En: 'implements is not allowed together with index (like E2260).'),
    (De: '%s wird schon von %s per implements umgesetzt (wie E2257).';
     En: '%s is already implemented by %s via implements (like E2257).'),
    (De: 'implements ist nur in Klassen erlaubt (wie E2258).';
     En: 'implements is only allowed in classes (like E2258).'),
    (De: 'implements braucht eine lesbare Property (wie E2261).';
     En: 'implements needs a readable property (like E2261).'),
    (De: 'Für %s gibt es die implements-Property %s; Methodenzuordnungen sind dann nicht erlaubt (wie E2264).';
     En: 'For %s there is the implements property %s; method resolutions are then not allowed (like E2264).'),
    (De: 'Aufrufkonvention passt nicht'; En: 'Calling convention does not fit'),
    (De: '%s entfernen'; En: 'Remove %s'),
    (De: 'Konstruktoren und Destruktoren brauchen register, nicht %s (wie E2236).';
     En: 'Constructors and destructors need register, not %s (like E2236).'),
    (De: 'Der %s %s der published-Property %s braucht register, nicht %s (wie E2270).';
     En: 'The %s %s of the published property %s needs register, not %s (like E2270).'),
    (De: 'varargs ist unter Win32 nur an external-Routinen mit cdecl erlaubt (wie E2277).';
     En: 'varargs is only allowed under Win32 on external routines with cdecl (like E2277).'),
    (De: 'varargs ist nur mit cdecl erlaubt (wie %s).'; En: 'varargs is only allowed with cdecl (like %s).'),
    (De: 'cdecl setzen'; En: 'Set cdecl'),
    (De: 'Unzulässige dispinterface-Deklaration'; En: 'Invalid dispinterface declaration'),
    (De: 'Ein dispinterface kann keinen Vorfahren haben (wie E2228).';
     En: 'A dispinterface cannot have an ancestor (like E2228).'),
    (De: 'Vorfahren entfernen'; En: 'Remove ancestor'),
    (De: 'Das dispinterface %s braucht eine GUID (wie E2229).'; En: 'The dispinterface %s needs a GUID (like E2229).'),
    (De: 'GUID einfügen'; En: 'Insert GUID'),
    (De: 'Methoden eines dispinterface dürfen keine Direktive %s haben (wie E2230).';
     En: 'Methods of a dispinterface must not have the directive %s (like E2230).'),
    (De: 'Die Direktive %s ist in einem dispinterface nicht erlaubt (wie E2231).';
     En: 'The directive %s is not allowed in a dispinterface (like E2231).'));

{$SCOPEDENUMS OFF}

const
  // Knoten, unter denen Klassendeklarationen stehen können (Anweisungen bleiben außen vor).
  cDeclarationKinds = [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile,
    TSyntaxKind.PackageFile, TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
    TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl, TSyntaxKind.ClassType, TSyntaxKind.Visibility];
  cDefaultMessageParameter = '(var Msg: TMessage)';
  // Direktiven, die an Methoden eines Interfaces nicht erlaubt sind (E2210).
  cInterfaceForbiddenDirectives: array[0..5] of string = ('virtual', 'dynamic', 'abstract', 'override', 'message',
    'reintroduce');
  // Aufrufkonventionen, die ein implements-Getter nicht haben darf (E2262).
  cForeignConventions: array[0..4] of string = ('cdecl', 'stdcall', 'pascal', 'safecall', 'winapi');
  // Direktiven, die an Methoden eines dispinterface sicher nicht erlaubt sind (E2230). Erlaubt sind dispid und die
  // Hinweise; overload und übrige Wörter bleiben ungeprüft still (#1328: nie strenger als dcc).
  cDispForbiddenDirectives: array[0..15] of string = ('register', 'pascal', 'cdecl', 'stdcall', 'safecall', 'winapi',
    'virtual', 'dynamic', 'abstract', 'override', 'reintroduce', 'message', 'static', 'final', 'inline', 'varargs');
  // Spezifizierer einer Property nach Name und Typ.
  cPropertySpecifiers: array[0..9] of string = ('read', 'write', 'stored', 'default', 'nodefault', 'index',
    'implements', 'dispid', 'readonly', 'writeonly');
  // Typen, die sicher kein Interface sind (E2205); Aliase können auf ein Interface zeigen.
  cNonInterfaceKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.EnumType];

type
  /// <summary>Eine message-Methode einer Klasse.</summary>
  TMessageMethod = record
    ClassName: string;
    Header: TSyntaxNode;
    Directive: TSyntaxNode;
    /// <summary>Token des Ausdrucks hinter "message"; First > Last ohne Ausdruck.</summary>
    First: Integer;
    Last: Integer;
  end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Einziger Methodenkopf AName im Typ AType; nil ohne oder bei Überladungen.</summary>
function UniqueMethodHeader(AType: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AType.ChildCount - 1 do
  begin
    if (AType[mIndex].Kind = TSyntaxKind.RoutineHeader) and SameText(AType[mIndex].Name, AName) then
    begin
      if Result <> nil then
      begin
        Exit(nil);
      end;
      Result := AType[mIndex];
    end;
  end;
end;

/// <summary>Rumpf AClassName.AMethod im implementation-Teil von ATree; nil ohne oder bei mehreren.</summary>
function MethodBody(ATree: TSyntaxTree; const AClassName, AMethod: string): TSyntaxNode;
var
  mSection: TSyntaxNode;
  mIndex: Integer;
  mMany: Boolean;
begin
  Result := nil;
  mMany := False;
  mSection := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if mSection = nil then
  begin
    mSection := ATree.Root;
  end;
  for mIndex := 0 to mSection.ChildCount - 1 do
  begin
    if (mSection[mIndex].Kind = TSyntaxKind.RoutineDecl) and
      SameText(mSection[mIndex].Name, AClassName + '.' + AMethod) then
    begin
      mMany := Result <> nil;
      Result := mSection[mIndex];
    end;
  end;
  if mMany then
  begin
    Result := nil;
  end;
end;

{ TDeclarationScan }

type
  /// <summary>Token, Zweige bedingter Übersetzung und Namensauflösung einer Datei für die Regeln zu
  /// Typdeklarationen; pinnt den Baum für die Dauer der Prüfung.</summary>
  TDeclarationScan = class
  private
    FTokens: TArray<TPascalToken>;
    FPaths: TArray<string>;
    FResolver: TNameResolver;
    FOwnUnit: TUnitIndex;
  public
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    function FirstToken(ANode: TSyntaxNode): Integer;
    /// <summary>Erstes Token hinter ANode.</summary>
    function StopToken(ANode: TSyntaxNode): Integer;
    /// <summary>Erstes Token ab AIndex, das kein Kommentar und keine Direktive ist (höchstens AStop).</summary>
    function NextCode(AIndex, AStop: Integer): Integer;
    /// <summary>Letztes Token vor AIndex, das kein Kommentar und keine Direktive ist; -1 ohne.</summary>
    function PreviousCode(AIndex: Integer): Integer;
    /// <summary>Löscht die Direktive ADirective samt ihrem Semikolon und dem Leerraum davor.</summary>
    function DirectiveRemoval(ADirective: TSyntaxNode): TTextEdit;
    /// <summary>Token des Schlüsselworts dispinterface am Anfang von AType (InterfaceType); -1 bei
    /// interface.</summary>
    function DispKeyword(AType: TSyntaxNode): Integer;
    /// <summary>Steht ANode außerhalb jeder bedingten Übersetzung?</summary>
    function Unconditional(ANode: TSyntaxNode): Boolean;
    function TokenRange(AIndex: Integer): TTextRange;
    function FirstRange(ANode: TSyntaxNode): TTextRange;
    /// <summary>Token des Property-Namens (erster passender Bezeichner); StopToken ohne.</summary>
    function PropertyNameToken(AProperty: TSyntaxNode): Integer;
    function PropertyRange(AProperty: TSyntaxNode): TTextRange;
    /// <summary>Erstes Semikolon der Property auf Klammerebene 0 (Ende der Spezifizierer).</summary>
    function ClauseEnd(AProperty: TSyntaxNode): Integer;
    /// <summary>Spezifizierer der Property (read, write, stored, default, index, implements …) als Token-Index,
    /// ohne Namen, Parameter, Typ und Argumente der Spezifizierer.</summary>
    function ClauseWords(AProperty: TSyntaxNode): TArray<Integer>;
    /// <summary>Token des Arguments hinter dem Spezifizierer an AIndex; ClauseEnd ohne.</summary>
    function ClauseArgument(AProperty: TSyntaxNode; AIndex: Integer): Integer;
    /// <summary>Text des Knotens ohne Leerraum, Groß-/Kleinschreibung und Unit-Präfix (E2208, E2257).</summary>
    function TypeKey(ANode: TSyntaxNode): string; overload;
    function TypeKey(AFirst, AStop: Integer): string; overload;
    /// <summary>Text der Token AFirst..AStop-1 ohne Kommentare und Leerraum.</summary>
    function Text(AFirst, AStop: Integer): string;
    property Tokens: TArray<TPascalToken> read FTokens;
    property Resolver: TNameResolver read FResolver;
    property OwnUnit: TUnitIndex read FOwnUnit;
  end;

constructor TDeclarationScan.Create(const AContext: TRuleContext);
var
  mFileName: string;
begin
  inherited Create;
  FTokens := AContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(FTokens);
  mFileName := AContext.FileName;
  if mFileName = '' then
  begin
    mFileName := AContext.RelativePath;
  end;
  if mFileName = '' then
  begin
    mFileName := AContext.UnitName + '.pas';
  end;
  FResolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
  FResolver.Namespaces := AContext.Namespaces;
  FResolver.PinTree(AContext.Tree, mFileName);
  FOwnUnit := FResolver.ExtractedUnit(AContext.Tree, mFileName);
end;

destructor TDeclarationScan.Destroy;
begin
  FResolver.UnpinTree;
  FResolver.Free;
  FTokens := nil;
  FPaths := nil;
  inherited;
end;

function TDeclarationScan.FirstToken(ANode: TSyntaxNode): Integer;
begin
  Result := TConstantValues.TokenFrom(FTokens, ANode.StartOffset);
end;

function TDeclarationScan.StopToken(ANode: TSyntaxNode): Integer;
begin
  Result := TConstantValues.TokenFrom(FTokens, ANode.EndOffset);
end;

function TDeclarationScan.NextCode(AIndex, AStop: Integer): Integer;
begin
  Result := AIndex;
  while (Result < AStop) and IsTrivia(FTokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function TDeclarationScan.PreviousCode(AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(FTokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function TDeclarationScan.DirectiveRemoval(ADirective: TSyntaxNode): TTextEdit;
var
  mFirst, mLast, mNext, mBefore: Integer;
begin
  mFirst := FirstToken(ADirective);
  mLast := StopToken(ADirective) - 1;
  mNext := NextCode(mLast + 1, Length(FTokens));
  if (mNext < Length(FTokens)) and FTokens[mNext].IsSymbol(';') then
  begin
    mLast := mNext;
  end;
  mBefore := PreviousCode(mFirst);
  if mBefore < 0 then
  begin
    mBefore := mFirst;
  end;
  Result := TTextEdit.Create(TTextRange.Create(FTokens[mBefore].EndPos, FTokens[mLast].EndPos), '');
end;

function TDeclarationScan.DispKeyword(AType: TSyntaxNode): Integer;
begin
  Result := NextCode(FirstToken(AType), Length(FTokens));
  if (Result >= Length(FTokens)) or not SameText(FTokens[Result].Text, 'dispinterface') then
  begin
    Result := -1;
  end;
end;

function TDeclarationScan.Unconditional(ANode: TSyntaxNode): Boolean;
begin
  Result := TConditionalBranches.PathAt(FPaths, FirstToken(ANode)) = '';
end;

function TDeclarationScan.TokenRange(AIndex: Integer): TTextRange;
begin
  Result := TTextRange.Create(FTokens[AIndex].StartPos, FTokens[AIndex].EndPos);
end;

function TDeclarationScan.FirstRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TokenRange(FirstToken(ANode));
end;

function TDeclarationScan.PropertyNameToken(AProperty: TSyntaxNode): Integer;
var
  mStop: Integer;
begin
  mStop := StopToken(AProperty);
  Result := FirstToken(AProperty);
  while (Result < mStop) and not ((FTokens[Result].Kind = TPascalTokenKind.Identifier) and
    SameText(FTokens[Result].Text, AProperty.Name)) do
  begin
    Inc(Result);
  end;
end;

function TDeclarationScan.PropertyRange(AProperty: TSyntaxNode): TTextRange;
var
  mIndex: Integer;
begin
  mIndex := PropertyNameToken(AProperty);
  if mIndex < StopToken(AProperty) then
  begin
    Result := TokenRange(mIndex);
  end
  else
  begin
    Result := TTextRange.Create(AProperty.StartPos, AProperty.EndPos);
  end;
end;

function TDeclarationScan.ClauseEnd(AProperty: TSyntaxNode): Integer;
var
  mStop, mDepth: Integer;
begin
  mStop := StopToken(AProperty);
  mDepth := 0;
  Result := PropertyNameToken(AProperty);
  while Result < mStop do
  begin
    if FTokens[Result].IsSymbol('[') or FTokens[Result].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if FTokens[Result].IsSymbol(']') or FTokens[Result].IsSymbol(')') then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and FTokens[Result].IsSymbol(';') then
    begin
      Exit;
    end;
    Inc(Result);
  end;
end;

function TDeclarationScan.ClauseWords(AProperty: TSyntaxNode): TArray<Integer>;
var
  mIndex, mStop, mDepth: Integer;
  mArgument: Boolean;
begin
  Result := nil;
  mStop := ClauseEnd(AProperty);
  mDepth := 0;
  // Ein Bezeichner direkt hinter read, write, stored … ist dessen Argument (read Stored), kein Spezifizierer.
  mArgument := False;
  for mIndex := PropertyNameToken(AProperty) + 1 to mStop - 1 do
  begin
    if IsTrivia(FTokens[mIndex]) then
    begin
      Continue;
    end;
    if FTokens[mIndex].IsSymbol('[') or FTokens[mIndex].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if FTokens[mIndex].IsSymbol(']') or FTokens[mIndex].IsSymbol(')') then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and not mArgument and (FTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      MatchText(FTokens[mIndex].Text, cPropertySpecifiers) then
    begin
      Result := Result + [mIndex];
      mArgument := not MatchText(FTokens[mIndex].Text, ['nodefault', 'readonly', 'writeonly']);
      Continue;
    end;
    mArgument := False;
  end;
end;

function TDeclarationScan.ClauseArgument(AProperty: TSyntaxNode; AIndex: Integer): Integer;
begin
  Result := NextCode(AIndex + 1, ClauseEnd(AProperty));
end;

function TDeclarationScan.Text(AFirst, AStop: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := AFirst to AStop - 1 do
  begin
    if not IsTrivia(FTokens[mIndex]) then
    begin
      Result := Result + FTokens[mIndex].Text;
    end;
  end;
end;

function TDeclarationScan.TypeKey(ANode: TSyntaxNode): string;
begin
  Result := TypeKey(FirstToken(ANode), StopToken(ANode));
end;

function TDeclarationScan.TypeKey(AFirst, AStop: Integer): string;
var
  mAngle: Integer;
  mHead: string;
begin
  Result := UpperCase(Text(AFirst, AStop));
  mAngle := Pos('<', Result);
  if mAngle = 0 then
  begin
    mAngle := Length(Result) + 1;
  end;
  mHead := Copy(Result, 1, mAngle - 1);
  Result := Copy(mHead, LastDelimiter('.', mHead) + 1, MaxInt) + Copy(Result, mAngle, MaxInt);
end;

/// <summary>Direktive message am Kopf AHeader (die letzte), nil ohne.</summary>
function MessageDirective(AHeader: TSyntaxNode): TSyntaxNode;
var
  mInner: Integer;
begin
  Result := nil;
  for mInner := 0 to AHeader.ChildCount - 1 do
  begin
    if (AHeader[mInner].Kind = TSyntaxKind.Directive) and (AHeader[mInner].Name = 'message') then
    begin
      Result := AHeader[mInner];
    end;
  end;
end;

/// <summary>Name des Typs ANode innerhalb von AOwner (TAussen.TInnen); bei anderen Knoten AOwner.</summary>
function NestedTypeName(const AOwner: string; ANode: TSyntaxNode): string;
begin
  Result := AOwner;
  if ANode.Kind <> TSyntaxKind.TypeDecl then
  begin
    Exit;
  end;
  if AOwner = '' then
  begin
    Result := ANode.Name;
  end
  else
  begin
    Result := AOwner + '.' + ANode.Name;
  end;
end;

{ TMessageMethodInvalidRule }

function TMessageMethodInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cMessageMethodInvalidRuleId, TRuleSeverity.Error,
    cTexts[TTypeDeclarationsText.MessageTitle].Text);
end;

procedure TMessageMethodInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mMethods: TList<TMessageMethod>;
  mPaths: TArray<string>;
  mFileName: string;

  function FirstToken(ANode: TSyntaxNode): Integer;
  begin
    Result := TConstantValues.TokenFrom(mTokens, ANode.StartOffset);
  end;

  function NextCode(AIndex, AStop: Integer): Integer;
  begin
    Result := AIndex;
    while (Result < AStop) and IsTrivia(mTokens[Result]) do
    begin
      Inc(Result);
    end;
  end;

  procedure AddMethod(AHeader, ADirective: TSyntaxNode; const AClassName: string);
  var
    mStop: Integer;
    mMethod: TMessageMethod;
  begin
    mMethod := Default(TMessageMethod);
    mMethod.ClassName := AClassName;
    mMethod.Header := AHeader;
    mMethod.Directive := ADirective;
    mStop := TConstantValues.TokenFrom(mTokens, ADirective.EndOffset);
    mMethod.First := NextCode(FirstToken(ADirective) + 1, mStop);
    mMethod.Last := mStop - 1;
    while (mMethod.Last >= mMethod.First) and IsTrivia(mTokens[mMethod.Last]) do
    begin
      Dec(mMethod.Last);
    end;
    mMethods.Add(mMethod);
  end;

  /// <summary>Merkt die message-Methoden der Klasse AClass mit dem Namen AClassName.</summary>
  procedure CollectClass(AClass: TSyntaxNode; const AClassName: string);
  var
    mIndex: Integer;
    mDirective: TSyntaxNode;
  begin
    for mIndex := 0 to AClass.ChildCount - 1 do
    begin
      if AClass[mIndex].Kind <> TSyntaxKind.RoutineHeader then
      begin
        Continue;
      end;
      mDirective := MessageDirective(AClass[mIndex]);
      if mDirective <> nil then
      begin
        AddMethod(AClass[mIndex], mDirective, AClassName);
      end;
    end;
  end;

  // Iterativ (Bericht M1).
  procedure Collect(ARoot: TSyntaxNode; const AOwner: string);
  var
    mPending: TStack<TSyntaxNode>;
    mPendingOwner: TStack<string>;
    mNode: TSyntaxNode;
    mIndex: Integer;
    mName: string;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    mPendingOwner := TStack<string>.Create;
    try
      mPending.Push(ARoot);
      mPendingOwner.Push(AOwner);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mName := NestedTypeName(mPendingOwner.Pop, mNode);
        if mNode.Kind = TSyntaxKind.ClassType then
        begin
          CollectClass(mNode, mName);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          if mNode[mIndex].Kind in cDeclarationKinds then
          begin
            mPending.Push(mNode[mIndex]);
            mPendingOwner.Push(mName);
          end;
        end;
      end;
    finally
      mPendingOwner.Free;
      mPending.Free;
    end;
  end;

  /// <summary>Name der Methode im Kopf (Token hinter procedure/function).</summary>
  function NameRange(AHeader: TSyntaxNode): TTextRange;
  var
    mIndex, mStop: Integer;
  begin
    Result := TTextRange.Create(AHeader.StartPos, AHeader.EndPos);
    mStop := TConstantValues.TokenFrom(mTokens, AHeader.EndOffset);
    for mIndex := FirstToken(AHeader) to mStop - 1 do
    begin
      if mTokens[mIndex].Kind = TPascalTokenKind.Identifier then
      begin
        Exit(TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].EndPos));
      end;
    end;
  end;

  function ExpressionText(const AMethod: TMessageMethod): string;
  var
    mIndex: Integer;
  begin
    Result := '';
    for mIndex := AMethod.First to AMethod.Last do
    begin
      if not IsTrivia(mTokens[mIndex]) then
      begin
        if (Result <> '') and (mTokens[mIndex - 1].Offset + Length(mTokens[mIndex -
          1].Text) <> mTokens[mIndex].Offset) then
        begin
          Result := Result + ' ';
        end;
        Result := Result + mTokens[mIndex].Text;
      end;
    end;
  end;

  function MethodName(AHeader: TSyntaxNode): string;
  var
    mDot: Integer;
  begin
    Result := AHeader.Name;
    mDot := LastDelimiter('.', Result);
    if mDot > 0 then
    begin
      Result := Copy(Result, mDot + 1, MaxInt);
    end;
  end;

  /// <summary>Einziger Parameter ohne var: nur den Modifizierer ändern.</summary>
  function SingleParameter(AHeader: TSyntaxNode; out AParam: TSyntaxNode): Boolean;
  var
    mParams: TSyntaxNode;
  begin
    AParam := nil;
    mParams := AHeader.FindChild(TSyntaxKind.Parameters);
    Result := (mParams <> nil) and (mParams.ChildCount = 1) and (Pos(',', mParams[0].Name) = 0) and
      (mParams[0].FindChild(TSyntaxKind.Attribute) = nil);
    if Result then
    begin
      AParam := mParams[0];
    end;
  end;

  function ParameterEdits(AHeader: TSyntaxNode; out AEdits: TArray<TTextEdit>): Boolean;
  var
    mParam, mParams: TSyntaxNode;
    mIndex: Integer;
    mPosition: TTextPosition;
  begin
    AEdits := nil;
    Result := True;
    if SingleParameter(AHeader, mParam) then
    begin
      mIndex := FirstToken(mParam);
      if mParam.Modifier = TParameterModifier.None then
      begin
        AEdits := [TTextEdit.Create(TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].StartPos), 'var ')];
      end
      else
      begin
        AEdits := [TTextEdit.Create(TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].EndPos), 'var')];
      end;
      Exit;
    end;
    mParams := AHeader.FindChild(TSyntaxKind.Parameters);
    if mParams <> nil then
    begin
      AEdits := [TTextEdit.Create(TTextRange.Create(mParams.StartPos, mParams.EndPos), cDefaultMessageParameter)];
    end
    else
    begin
      // Ohne Klammern: direkt hinter dem Namen einfügen.
      mPosition := NameRange(AHeader).EndPos;
      AEdits := [TTextEdit.Create(TTextRange.Create(mPosition, mPosition), cDefaultMessageParameter)];
    end;
  end;

  function SignatureFix(const AMethod: TMessageMethod): TArray<TRuleFix>;
  var
    mEdits, mBodyEdits: TArray<TTextEdit>;
    mDecl, mHeader: TSyntaxNode;
    mParam: TSyntaxNode;
  begin
    Result := nil;
    if not ParameterEdits(AMethod.Header, mEdits) then
    begin
      Exit;
    end;
    mDecl := MethodBody(AContext.Tree, AMethod.ClassName, MethodName(AMethod.Header));
    if mDecl <> nil then
    begin
      mHeader := mDecl.FindChild(TSyntaxKind.RoutineHeader);
      // Rumpf ohne Parameterliste darf so bleiben; sonst gleich anpassen.
      if (mHeader <> nil) and (mHeader.FindChild(TSyntaxKind.Parameters) <> nil) then
      begin
        if SingleParameter(AMethod.Header, mParam) <> SingleParameter(mHeader, mParam) then
        begin
          Exit;
        end;
        if ParameterEdits(mHeader, mBodyEdits) then
        begin
          mEdits := mEdits + mBodyEdits;
        end;
      end;
    end;
    if SingleParameter(AMethod.Header, mParam) then
    begin
      Result := [TRuleFix.Create(cTexts[TTypeDeclarationsText.PassAsVar].Fmt([mParam.Name]), mEdits)];
    end
    else
    begin
      Result := [TRuleFix.Create(cTexts[TTypeDeclarationsText.InsertSignature].Fmt([cDefaultMessageParameter]),
        mEdits)];
    end;
  end;

  procedure CheckParameters(const AMethod: TMessageMethod);
  var
    mParams: TSyntaxNode;
    mKeyword: string;
    mIndex: Integer;
  begin
    // Nur Prozeduren: message an Funktionen ist ein anderer Fall.
    mIndex := NextCode(FirstToken(AMethod.Header), Length(mTokens));
    if (mIndex < Length(mTokens)) and mTokens[mIndex].IsKeyword('class') then
    begin
      Exit;
    end;
    if mIndex >= Length(mTokens) then
    begin
      Exit;
    end;
    mKeyword := LowerCase(mTokens[mIndex].Text);
    if mKeyword <> 'procedure' then
    begin
      Exit;
    end;
    mParams := AMethod.Header.FindChild(TSyntaxKind.Parameters);
    if (mParams <> nil) and (mParams.ChildCount = 1) and (Pos(',', mParams[0].Name) = 0) and
      (mParams[0].Modifier = TParameterModifier.VarParam) then
    begin
      Exit;
    end;
    AReport.Add(NameRange(AMethod.Header), cTexts[TTypeDeclarationsText.MessageParam].Fmt([MethodName(AMethod.Header)]),
      TRuleConfidence.High, SignatureFix(AMethod));
  end;

  function PathOf(const AMethod: TMessageMethod): string;
  begin
    Result := TConditionalBranches.PathAt(mPaths, FirstToken(AMethod.Header));
  end;

  /// <summary>Behandelt eine frühere message-Methode derselben Klasse in derselben Bedingungsvariante die
  /// Nummer mit dem Schlüssel AKeys[AIndex]? Index der früheren, -1 ohne.</summary>
  function EarlierHandler(const AKeys: TArray<string>; const AKnown: TArray<Boolean>; AIndex: Integer): Integer;
  var
    mEarlier: Integer;
  begin
    for mEarlier := 0 to AIndex - 1 do
    begin
      if AKnown[mEarlier] and SameText(mMethods[mEarlier].ClassName, mMethods[AIndex].ClassName) and
        (AKeys[mEarlier] = AKeys[AIndex]) and
        not TConditionalBranches.Exclusive(PathOf(mMethods[mEarlier]), PathOf(mMethods[AIndex])) then
      begin
        Exit(mEarlier);
      end;
    end;
    Result := -1;
  end;

  /// <summary>Prüft die Nummer der Methode AIndex (E2139, E2140) und merkt ihren Schlüssel.</summary>
  procedure CheckNumber(AValues: TConstantValues; AIndex: Integer; var AKeys: TArray<string>;
    var AKnown: TArray<Boolean>);
  var
    mValue: Int64;
    mMethod: TMessageMethod;
    mRange: TTextRange;
    mEarlier: Integer;
  begin
    mMethod := mMethods[AIndex];
    mRange := TTextRange.Create(mTokens[mMethod.First].StartPos, mTokens[mMethod.Last].EndPos);
    if not AValues.Evaluate(mMethod.First, mMethod.Last, mValue) then
    begin
      AKeys[AIndex] := 't' + UpperCase(ExpressionText(mMethod).Replace(' ', ''));
    end
    else if mValue < 1 then
    begin
      AReport.Add(mRange, cTexts[TTypeDeclarationsText.MessageNumber].Fmt(
        [ExpressionText(mMethod), MethodName(mMethod.Header)]), TRuleConfidence.High);
      Exit;
    end
    else
    begin
      AKeys[AIndex] := 'v' + IntToStr(mValue);
    end;
    AKnown[AIndex] := True;
    mEarlier := EarlierHandler(AKeys, AKnown, AIndex);
    if mEarlier >= 0 then
    begin
      AReport.Add(mRange, cTexts[TTypeDeclarationsText.MessageHandled].Fmt([ExpressionText(mMethod),
        MethodName(mMethods[mEarlier].Header)]), TRuleConfidence.High);
    end;
  end;

  procedure CheckNumbers;
  var
    mResolver: TNameResolver;
    mCache: IRuleDerivedCache;
    mValues: TConstantValues;
    mKeys: TArray<string>;
    mKnown: TArray<Boolean>;
    mIndex: Integer;
  begin
    SetLength(mKeys, mMethods.Count);
    SetLength(mKnown, mMethods.Count);
    // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
    mCache := TRuleDerived.Open(AContext);
    mResolver := TRuleDerived.Resolver(mCache, AContext);
    try
      mResolver.PinTree(AContext.Tree, mFileName);
      mValues := TConstantValues.Create(AContext.Tree, mFileName, AContext.Index, mResolver);
      try
        for mIndex := 0 to mMethods.Count - 1 do
        begin
          if mMethods[mIndex].First <= mMethods[mIndex].Last then
          begin
            CheckNumber(mValues, mIndex, mKeys, mKnown);
          end;
        end;
      finally
        mValues.Free;
      end;
    finally
      mResolver.UnpinTree;
    end;
  end;

var
  Method: TMessageMethod;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mFileName := AContext.FileName;
  if mFileName = '' then
  begin
    mFileName := AContext.RelativePath;
  end;
  if mFileName = '' then
  begin
    mFileName := AContext.UnitName + '.pas';
  end;
  mMethods := TList<TMessageMethod>.Create;
  try
    Collect(AContext.Tree.Root, '');
    if mMethods.Count = 0 then
    begin
      Exit;
    end;
    mPaths := TConditionalBranches.Paths(mTokens);
    for Method in mMethods do
    begin
      CheckParameters(Method);
    end;
    CheckNumbers;
  finally
    mMethods.Free;
  end;
end;

{ TInterfaceDeclarationInvalidRule }

function TInterfaceDeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cInterfaceDeclarationInvalidRuleId, TRuleSeverity.Error,
    cTexts[TTypeDeclarationsText.InterfaceTitle].Text);
end;

procedure TInterfaceDeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TDeclarationScan;

  /// <summary>Löst ANode (TypeReference) sicher zu einer Klasse, einem Record oder einer Aufzählung auf?</summary>
  function NotAnInterface(ANode: TSyntaxNode; out AKind: string): Boolean;
  var
    mResolved: TResolvedSymbol;
  begin
    AKind := '';
    Result := (ANode.Name <> '') and mScan.Resolver.ResolveTypeFrom(mScan.OwnUnit, ANode.Name, mResolved) and
      mResolved.Found and not mResolved.Builtin and (mResolved.SymbolKind in cNonInterfaceKinds);
    if not Result then
    begin
      Exit;
    end;
    case mResolved.SymbolKind of
      TIndexSymbolKind.RecordType:
        AKind := cTexts[TTypeDeclarationsText.RecordKind].Text;
      TIndexSymbolKind.EnumType:
        AKind := cTexts[TTypeDeclarationsText.EnumKind].Text;
    else
      AKind := cTexts[TTypeDeclarationsText.ClassKind].Text;
    end;
  end;

  procedure ReportNotInterface(ANode: TSyntaxNode);
  var
    mKind: string;
  begin
    if mScan.Unconditional(ANode) and NotAnInterface(ANode, mKind) then
    begin
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
        cTexts[TTypeDeclarationsText.NotInterface].Fmt([ANode.Name, mKind]), TRuleConfidence.High);
    end;
  end;

  procedure CheckClassList(AClass: TSyntaxNode);
  var
    mIndex, mEarlier, mPosition: Integer;
    mReferences: TArray<TSyntaxNode>;
  begin
    mReferences := nil;
    for mIndex := 0 to AClass.ChildCount - 1 do
    begin
      if AClass[mIndex].Kind = TSyntaxKind.TypeReference then
      begin
        mReferences := mReferences + [AClass[mIndex]];
      end
      else
      begin
        Break;
      end;
    end;
    for mPosition := 1 to High(mReferences) do
    begin
      ReportNotInterface(mReferences[mPosition]);
      for mEarlier := 0 to mPosition - 1 do
      begin
        if (mScan.TypeKey(mReferences[mEarlier]) = mScan.TypeKey(mReferences[mPosition])) and
          mScan.Unconditional(mReferences[mPosition]) then
        begin
          AReport.Add(TTextRange.Create(mReferences[mPosition].StartPos, mReferences[mPosition].EndPos),
            cTexts[TTypeDeclarationsText.AlreadyListed].Fmt([mReferences[mPosition].Name]),
            TRuleConfidence.High);
          Break;
        end;
      end;
    end;
  end;

  /// <summary>Klauseln stored, nodefault und default mit Wert vor dem ersten Semikolon der Property.</summary>
  procedure CheckPropertyClauses(AProperty: TSyntaxNode);
  var
    mIndex: Integer;
    mWord: string;
  begin
    for mIndex in mScan.ClauseWords(AProperty) do
    begin
      mWord := LowerCase(mScan.Tokens[mIndex].Text);
      if (mWord = 'stored') or (mWord = 'nodefault') or
        ((mWord = 'default') and (mScan.ClauseArgument(AProperty, mIndex) < mScan.ClauseEnd(AProperty))) then
      begin
        AReport.Add(mScan.TokenRange(mIndex), cTexts[TTypeDeclarationsText.ClauseNotAllowed].Fmt(
          [mWord]), TRuleConfidence.High);
      end;
    end;
  end;

  /// <summary>Property ohne eigenen Typ (property Name; bzw. property Name read …), die eine geerbte
  /// Property nur neu aufführt. Interfaces erlauben das nicht (E2206); eine Neudeklaration mit Typ ist eine
  /// neue Property und übersetzt (#1328).</summary>
  function WithoutType(AProperty: TSyntaxNode): Boolean;
  var
    mIndex, mStop: Integer;
  begin
    mStop := mScan.StopToken(AProperty);
    mIndex := mScan.PropertyNameToken(AProperty);
    Result := mIndex < mStop;
    if Result then
    begin
      mIndex := mScan.NextCode(mIndex + 1, mStop);
      Result := (mIndex >= mStop) or not MatchText(mScan.Tokens[mIndex].Text, [':', '[']);
    end;
  end;

  // Geerbte Accessoren (property X read GetX mit GetX aus dem Vorfahr-Interface) übersetzt dcc, generisch wie
  // nicht generisch (DUnitX IList<T>; ID1, ID2, ID3; dcc-Lauf vom 29.10.2026, #1328): Die frühere Prüfung auf
  // E2370 ist entfallen.
  procedure CheckInheritedMembers(AType: TSyntaxNode; const AName: string);
  var
    mOwn, mAncestor, mMember: TResolvedSymbol;
    mIndex: Integer;
    mChild: TSyntaxNode;
  begin
    if not mScan.Resolver.ResolveTypeFrom(mScan.OwnUnit, AName, mOwn) or not mOwn.Found or
      (mOwn.SymbolKind <> TIndexSymbolKind.InterfaceType) or not mScan.Resolver.AncestorOf(mOwn, mAncestor) then
    begin
      Exit;
    end;
    for mIndex := 0 to AType.ChildCount - 1 do
    begin
      mChild := AType[mIndex];
      if (mChild.Kind <> TSyntaxKind.PropertyDecl) or not mScan.Unconditional(mChild) then
      begin
        Continue;
      end;
      if WithoutType(mChild) and mScan.Resolver.DeclaredMember(mAncestor, mChild.Name, mMember) and
        (mMember.SymbolKind = TIndexSymbolKind.Property_) then
      begin
        AReport.Add(mScan.PropertyRange(mChild), cTexts[TTypeDeclarationsText.PropertyRedeclared].Fmt([mChild.Name,
          mMember.Container]), TRuleConfidence.High);
      end;
    end;
  end;

  procedure ReportVarSection(ASection: TSyntaxNode);
  var
    mInner: Integer;
  begin
    for mInner := 0 to ASection.ChildCount - 1 do
    begin
      if ASection[mInner].Kind = TSyntaxKind.VarDecl then
      begin
        AReport.Add(mScan.FirstRange(ASection[mInner]), cTexts[TTypeDeclarationsText.NoFields].Text,
          TRuleConfidence.High);
      end;
    end;
  end;

  procedure ReportForbiddenDirectives(AHeader: TSyntaxNode);
  var
    mInner: Integer;
  begin
    for mInner := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[mInner].Kind = TSyntaxKind.Directive) and
        MatchText(AHeader[mInner].Name, cInterfaceForbiddenDirectives) then
      begin
        AReport.Add(mScan.FirstRange(AHeader[mInner]),
          cTexts[TTypeDeclarationsText.DirectiveNotAllowed].Fmt([AHeader[mInner].Name]), TRuleConfidence.High);
      end;
    end;
  end;

  procedure CheckInterfaceMember(AChild: TSyntaxNode);
  begin
    case AChild.Kind of
      TSyntaxKind.Field:
        AReport.Add(mScan.FirstRange(AChild), cTexts[TTypeDeclarationsText.NoFields].Text, TRuleConfidence.High);
      TSyntaxKind.VarSection:
        ReportVarSection(AChild);
      TSyntaxKind.Visibility:
        AReport.Add(TTextRange.Create(AChild.StartPos, AChild.EndPos),
          cTexts[TTypeDeclarationsText.DirectiveNotAllowed].Fmt([AChild.Name]), TRuleConfidence.High);
      TSyntaxKind.RoutineHeader:
        ReportForbiddenDirectives(AChild);
      TSyntaxKind.PropertyDecl:
        CheckPropertyClauses(AChild);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  procedure CheckInterface(AType: TSyntaxNode; const AName: string);
  var
    mIndex: Integer;
  begin
    // dispinterface prüft dispinterface-invalid.
    if mScan.DispKeyword(AType) >= 0 then
    begin
      Exit;
    end;
    if (AType.ChildCount > 0) and (AType[0].Kind = TSyntaxKind.TypeReference) then
    begin
      ReportNotInterface(AType[0]);
    end;
    for mIndex := 0 to AType.ChildCount - 1 do
    begin
      if mScan.Unconditional(AType[mIndex]) then
      begin
        CheckInterfaceMember(AType[mIndex]);
      end;
    end;
    CheckInheritedMembers(AType, AName);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
    mBody: TSyntaxNode;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.TypeDecl then
        begin
          mBody := mNode.FindChild(TSyntaxKind.InterfaceType);
          if mBody <> nil then
          begin
            CheckInterface(mBody, mNode.Name);
          end;
          mBody := mNode.FindChild(TSyntaxKind.ClassType);
          if mBody <> nil then
          begin
            CheckClassList(mBody);
          end;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          if mNode[mIndex].Kind in cDeclarationKinds then
          begin
            mPending.Push(mNode[mIndex]);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mScan := TDeclarationScan.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    mScan.Free;
  end;
end;

{ TImplementsClauseInvalidRule }

function TImplementsClauseInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cImplementsClauseInvalidRuleId, TRuleSeverity.Error,
    cTexts[TTypeDeclarationsText.ImplementsTitle].Text);
end;

procedure TImplementsClauseInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TDeclarationScan;

  function Word(AIndex: Integer): string;
  begin
    Result := LowerCase(mScan.Tokens[AIndex].Text);
  end;

  procedure CheckType(AProperty: TSyntaxNode);
  var
    mReference: TSyntaxNode;
    mResolved: TResolvedSymbol;
  begin
    mReference := AProperty.FindChild(TSyntaxKind.TypeReference);
    if (mReference = nil) or (mReference.Name = '') then
    begin
      Exit;
    end;
    // Eingebaute Typen (Integer, string …) stehen nicht im Index; ein eigener gleichnamiger Typ geht vor.
    if not mScan.Resolver.ResolveTypeFrom(mScan.OwnUnit, mReference.Name, mResolved) or not mResolved.Found then
    begin
      mResolved.Builtin := TResolverText.IsBuiltinTypeName(mReference.Name);
      if not mResolved.Builtin then
      begin
        Exit;
      end;
    end;
    if mResolved.Builtin or (mResolved.SymbolKind in [TIndexSymbolKind.RecordType, TIndexSymbolKind.EnumType]) then
    begin
      AReport.Add(TTextRange.Create(mReference.StartPos, mReference.EndPos),
        cTexts[TTypeDeclarationsText.ImplementsType].Fmt([mReference.Name]),
        TRuleConfidence.High);
    end;
  end;

  procedure CheckGetter(AType: TSyntaxNode; AGetter: Integer);
  var
    mHeader: TSyntaxNode;
    mIndex: Integer;
    mName: string;
  begin
    mHeader := UniqueMethodHeader(AType, mScan.Tokens[AGetter].Text);
    if mHeader = nil then
    begin
      Exit;
    end;
    for mIndex := 0 to mHeader.ChildCount - 1 do
    begin
      if mHeader[mIndex].Kind <> TSyntaxKind.Directive then
      begin
        Continue;
      end;
      mName := mHeader[mIndex].Name;
      if MatchText(mName, cForeignConventions) then
      begin
        AReport.Add(mScan.TokenRange(AGetter),
          cTexts[TTypeDeclarationsText.GetterRegister].Fmt([mScan.Tokens[AGetter].Text, mName]), TRuleConfidence.High);
      end
      else if (mName = 'dynamic') or (mName = 'message') then
      begin
        AReport.Add(mScan.TokenRange(AGetter), cTexts[TTypeDeclarationsText.GetterNot].Fmt([mScan.Tokens[AGetter].Text,
          mName]), TRuleConfidence.High);
      end;
    end;
  end;

  /// <summary>Token des Worts implements unter den Klauselwörtern AWords, -1 ohne; AHasRead bei read.</summary>
  function ImplementsWord(const AWords: TArray<Integer>; out AHasRead: Boolean): Integer;
  var
    mClause: Integer;
  begin
    Result := -1;
    AHasRead := False;
    for mClause in AWords do
    begin
      if Word(mClause) = 'implements' then
      begin
        Result := mClause;
      end
      else if Word(mClause) = 'read' then
      begin
        AHasRead := True;
      end;
    end;
  end;

  // index neben implements (E2260) und Getter hinter read.
  procedure CheckClauses(AType, AProperty: TSyntaxNode; const AWords: TArray<Integer>);
  var
    mClause, mArgument: Integer;
  begin
    for mClause in AWords do
    begin
      mArgument := mScan.ClauseArgument(AProperty, mClause);
      if Word(mClause) = 'index' then
      begin
        AReport.Add(mScan.TokenRange(mClause), cTexts[TTypeDeclarationsText.ImplementsIndex].Text,
          TRuleConfidence.High);
      end
      else if (Word(mClause) = 'read') and (mArgument < mScan.ClauseEnd(AProperty)) and
        (mScan.Tokens[mArgument].Kind = TPascalTokenKind.Identifier) then
      begin
        CheckGetter(AType, mArgument);
      end;
    end;
  end;

  /// <summary>Endet an APosition ein Interface hinter implements (Komma auf Ebene 0 oder Ende AStop)?</summary>
  function EndsInterface(APosition, AStop: Integer; var ADepth: Integer): Boolean;
  begin
    if APosition >= AStop then
    begin
      Exit(True);
    end;
    if mScan.Tokens[APosition].IsSymbol('<') then
    begin
      Inc(ADepth);
    end
    else if mScan.Tokens[APosition].IsSymbol('>') then
    begin
      Dec(ADepth);
    end;
    Result := (ADepth = 0) and mScan.Tokens[APosition].IsSymbol(',');
  end;

  /// <summary>Merkt das Interface zwischen AFirst und AStop als von AOwner umgesetzt; doppelt: E2257.</summary>
  procedure AddInterface(AFirst, AStop: Integer; const AOwner: string; var AKeys, AOwners: TArray<string>);
  var
    mKey: string;
    mClause: Integer;
  begin
    mKey := mScan.TypeKey(AFirst, AStop);
    for mClause := 0 to High(AKeys) do
    begin
      if AKeys[mClause] = mKey then
      begin
        AReport.Add(TTextRange.Create(mScan.Tokens[AFirst].StartPos, mScan.Tokens[AStop - 1].EndPos),
          cTexts[TTypeDeclarationsText.AlreadyImplemented].Fmt([mScan.Text(AFirst, AStop),
          AOwners[mClause]]), TRuleConfidence.High);
        Exit;
      end;
    end;
    AKeys := AKeys + [mKey];
    AOwners := AOwners + [AOwner];
  end;

  // Interfaces hinter implements, durch Kommas getrennt.
  procedure CollectInterfaces(AProperty: TSyntaxNode; AImplements: Integer; var AKeys, AOwners: TArray<string>);
  var
    mFirst, mDepth, mPosition, mStop: Integer;
  begin
    mStop := mScan.ClauseEnd(AProperty);
    mFirst := mScan.NextCode(AImplements + 1, mStop);
    mDepth := 0;
    for mPosition := mFirst to mStop do
    begin
      if not EndsInterface(mPosition, mStop, mDepth) then
      begin
        Continue;
      end;
      if mPosition > mFirst then
      begin
        AddInterface(mFirst, mPosition, AProperty.Name, AKeys, AOwners);
      end;
      mFirst := mScan.NextCode(mPosition + 1, mStop);
    end;
  end;

  procedure CheckProperty(AType, AProperty: TSyntaxNode; var AKeys, AOwners: TArray<string>);
  var
    mWords: TArray<Integer>;
    mImplements: Integer;
    mHasRead: Boolean;
  begin
    mWords := mScan.ClauseWords(AProperty);
    mImplements := ImplementsWord(mWords, mHasRead);
    if mImplements < 0 then
    begin
      Exit;
    end;
    if AType.Kind <> TSyntaxKind.ClassType then
    begin
      AReport.Add(mScan.TokenRange(mImplements), cTexts[TTypeDeclarationsText.ImplementsClassOnly].Text,
        TRuleConfidence.High);
      Exit;
    end;
    CheckType(AProperty);
    CheckClauses(AType, AProperty, mWords);
    if not mHasRead then
    begin
      AReport.Add(mScan.TokenRange(mImplements), cTexts[TTypeDeclarationsText.ImplementsReadable].Text,
        TRuleConfidence.High);
    end;
    CollectInterfaces(AProperty, mImplements, AKeys, AOwners);
  end;

  // Methodenzuordnung (procedure IFoo.Bar = Baz) für ein Interface mit implements-Property: E2264.
  procedure CheckResolution(AHeader: TSyntaxNode; const AKeys, AOwners: TArray<string>);
  var
    mPrefix: string;
    mClause: Integer;
  begin
    mPrefix := UpperCase(Copy(AHeader.Name, 1, LastDelimiter('.', AHeader.Name) - 1));
    mPrefix := Copy(mPrefix, LastDelimiter('.', mPrefix) + 1, MaxInt);
    for mClause := 0 to High(AKeys) do
    begin
      if AKeys[mClause] = mPrefix then
      begin
        AReport.Add(mScan.TokenRange(mScan.NextCode(mScan.FirstToken(AHeader) + 1, mScan.StopToken(AHeader))),
          cTexts[TTypeDeclarationsText.MethodResolution].Fmt([Copy(AHeader.Name, 1, LastDelimiter('.',
            AHeader.Name) - 1), AOwners[mClause]]),
          TRuleConfidence.High);
        Exit;
      end;
    end;
  end;

  procedure CheckClass(AType: TSyntaxNode);
  var
    mIndex: Integer;
    mChild: TSyntaxNode;
    mKeys, mOwners: TArray<string>;
  begin
    mKeys := nil;
    mOwners := nil;
    for mIndex := 0 to AType.ChildCount - 1 do
    begin
      mChild := AType[mIndex];
      if (mChild.Kind = TSyntaxKind.PropertyDecl) and mScan.Unconditional(mChild) then
      begin
        CheckProperty(AType, mChild, mKeys, mOwners);
      end;
    end;
    for mIndex := 0 to AType.ChildCount - 1 do
    begin
      mChild := AType[mIndex];
      if (mChild.Kind = TSyntaxKind.RoutineHeader) and (Pos('.', mChild.Name) > 0) and mScan.Unconditional(mChild) then
      begin
        CheckResolution(mChild, mKeys, mOwners);
      end;
    end;
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.InterfaceType,
          TSyntaxKind.ObjectType, TSyntaxKind.HelperType] then
        begin
          CheckClass(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          if mNode[mIndex].Kind in cDeclarationKinds + [TSyntaxKind.RecordType, TSyntaxKind.InterfaceType,
            TSyntaxKind.ObjectType, TSyntaxKind.HelperType] then
          begin
            mPending.Push(mNode[mIndex]);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mScan := TDeclarationScan.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    mScan.Free;
  end;
end;

{ TCallingConventionRequiredRule }

function TCallingConventionRequiredRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cCallingConventionRequiredRuleId, TRuleSeverity.Error,
    cTexts[TTypeDeclarationsText.ConventionTitle].Text);
end;

procedure TCallingConventionRequiredRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TDeclarationScan;

  function Directive(AHeader: TSyntaxNode; const AName: string): TSyntaxNode;
  var
    mIndex: Integer;
  begin
    Result := nil;
    for mIndex := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(AHeader[mIndex].Name, AName) then
      begin
        Exit(AHeader[mIndex]);
      end;
    end;
  end;

  function Convention(AHeader: TSyntaxNode): TSyntaxNode;
  var
    mIndex: Integer;
  begin
    Result := nil;
    for mIndex := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and MatchText(AHeader[mIndex].Name, cForeignConventions) then
      begin
        Exit(AHeader[mIndex]);
      end;
    end;
  end;

  function Keyword(AHeader: TSyntaxNode): string;
  var
    mIndex: Integer;
  begin
    mIndex := mScan.NextCode(mScan.FirstToken(AHeader), Length(mScan.Tokens));
    Result := '';
    if mIndex < Length(mScan.Tokens) then
    begin
      Result := LowerCase(mScan.Tokens[mIndex].Text);
    end;
  end;

  /// <summary>Korrektur: Konvention an AHeader und am Rumpf der Datei entfernen.</summary>
  function RemoveFix(const AClassName: string; AHeader, AConvention: TSyntaxNode): TArray<TRuleFix>;
  var
    mEdits: TArray<TTextEdit>;
    mBody, mOther: TSyntaxNode;
  begin
    mEdits := [mScan.DirectiveRemoval(AConvention)];
    mBody := MethodBody(AContext.Tree, AClassName, AHeader.Name);
    if mBody <> nil then
    begin
      mBody := mBody.FindChild(TSyntaxKind.RoutineHeader);
    end;
    if mBody <> nil then
    begin
      mOther := Directive(mBody, AConvention.Name);
      if mOther <> nil then
      begin
        mEdits := mEdits + [mScan.DirectiveRemoval(mOther)];
      end;
    end;
    Result := [TRuleFix.Create(cTexts[TTypeDeclarationsText.RemoveName].Fmt([AConvention.Name]), mEdits)];
  end;

  // Konstruktoren und Destruktoren mit fremder Konvention: E2236.
  procedure CheckConstructor(AHeader: TSyntaxNode; const AClassName: string);
  var
    mFound: TSyntaxNode;
  begin
    mFound := Convention(AHeader);
    if mFound <> nil then
    begin
      AReport.Add(mScan.FirstRange(mFound), cTexts[TTypeDeclarationsText.CtorRegister].Fmt([mFound.Name]),
        TRuleConfidence.High, RemoveFix(AClassName, AHeader, mFound));
    end;
  end;

  /// <summary>Methodenkopf hinter der Klausel read/write AClause einer Property von AType, nil ohne.</summary>
  function AccessorHeader(AType, AProperty: TSyntaxNode; AClause: Integer; out AArgument: Integer): TSyntaxNode;
  begin
    Result := nil;
    AArgument := mScan.ClauseArgument(AProperty, AClause);
    if MatchText(mScan.Tokens[AClause].Text, ['read', 'write']) and (AArgument < mScan.ClauseEnd(AProperty)) and
      (mScan.Tokens[AArgument].Kind = TPascalTokenKind.Identifier) then
    begin
      Result := UniqueMethodHeader(AType, mScan.Tokens[AArgument].Text);
    end;
  end;

  // Getter und Setter einer published-Property mit fremder Konvention: E2270.
  procedure CheckPublishedProperty(AType, AProperty: TSyntaxNode; const AClassName: string);
  var
    mClause, mArgument: Integer;
    mHeader, mFound: TSyntaxNode;
    mKind: string;
  begin
    for mClause in mScan.ClauseWords(AProperty) do
    begin
      mHeader := AccessorHeader(AType, AProperty, mClause, mArgument);
      mFound := nil;
      if mHeader <> nil then
      begin
        mFound := Convention(mHeader);
      end;
      if mFound = nil then
      begin
        Continue;
      end;
      mKind := 'Setter';
      if SameText(mScan.Tokens[mClause].Text, 'read') then
      begin
        mKind := 'Getter';
      end;
      AReport.Add(mScan.TokenRange(mArgument), cTexts[TTypeDeclarationsText.PublishedRegister].Fmt([mKind,
        mScan.Tokens[mArgument].Text, AProperty.Name, mFound.Name]),
        TRuleConfidence.High, RemoveFix(AClassName, mHeader, mFound));
    end;
  end;

  procedure CheckClass(AType: TSyntaxNode; const AClassName: string);
  var
    mIndex: Integer;
    mChild: TSyntaxNode;
    mPublished: Boolean;
  begin
    mPublished := False;
    for mIndex := 0 to AType.ChildCount - 1 do
    begin
      mChild := AType[mIndex];
      if mChild.Kind = TSyntaxKind.Visibility then
      begin
        mPublished := mChild.Name = 'published';
      end
      else if not mScan.Unconditional(mChild) then
      begin
        Continue;
      end
      else if (mChild.Kind = TSyntaxKind.RoutineHeader) and MatchText(Keyword(mChild), ['constructor', 'destructor']) then
      begin
        CheckConstructor(mChild, AClassName);
      end
      else if (mChild.Kind = TSyntaxKind.PropertyDecl) and mPublished then
      begin
        CheckPublishedProperty(AType, mChild, AClassName);
      end;
    end;
  end;

  procedure CheckVarargs(AHeader: TSyntaxNode);
  var
    mVarargs, mFound: TSyntaxNode;
    mCode: string;
    mEdit: TTextEdit;
    mPosition: TTextPosition;
  begin
    mVarargs := Directive(AHeader, 'varargs');
    if (mVarargs = nil) or not mScan.Unconditional(AHeader) then
    begin
      Exit;
    end;
    // Ohne external: dcc meldet E2277 unter Win32 auch mit cdecl; Win64 übersetzt es (Cm.E2277, #1380).
    if Directive(AHeader, 'external') = nil then
    begin
      if AContext.Tree.Platform = 'Win32' then
      begin
        AReport.Add(mScan.FirstRange(mVarargs), cTexts[TTypeDeclarationsText.VarargsWin32].Text, TRuleConfidence.High);
      end;
      Exit;
    end;
    if Directive(AHeader, 'cdecl') <> nil then
    begin
      Exit;
    end;
    mCode := 'E2277';
    mFound := Convention(AHeader);
    if mFound = nil then
    begin
      mFound := Directive(AHeader, 'register');
    end;
    if mFound <> nil then
    begin
      mEdit := TTextEdit.Create(mScan.FirstRange(mFound), 'cdecl');
    end
    else
    begin
      mPosition := mScan.FirstRange(mVarargs).StartPos;
      mEdit := TTextEdit.Create(TTextRange.Create(mPosition, mPosition), 'cdecl; ');
    end;
    AReport.Add(mScan.FirstRange(mVarargs), cTexts[TTypeDeclarationsText.VarargsCdecl].Fmt([mCode]),
      TRuleConfidence.High, [TRuleFix.Create(cTexts[TTypeDeclarationsText.SetCdecl].Text, [mEdit])]);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode; const AOwner: string);
  var
    mPending: TStack<TSyntaxNode>;
    mPendingOwner: TStack<string>;
    mNode: TSyntaxNode;
    mIndex: Integer;
    mName: string;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    mPendingOwner := TStack<string>.Create;
    try
      mPending.Push(ARoot);
      mPendingOwner.Push(AOwner);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mName := NestedTypeName(mPendingOwner.Pop, mNode);
        if mNode.Kind = TSyntaxKind.ClassType then
        begin
          CheckClass(mNode, mName);
        end;
        if mNode.Kind = TSyntaxKind.RoutineHeader then
        begin
          CheckVarargs(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          if mNode[mIndex].Kind in cDeclarationKinds + [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader,
            TSyntaxKind.RecordType, TSyntaxKind.ObjectType, TSyntaxKind.HelperType] then
          begin
            mPending.Push(mNode[mIndex]);
            mPendingOwner.Push(mName);
          end;
        end;
      end;
    finally
      mPendingOwner.Free;
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mScan := TDeclarationScan.Create(AContext);
  try
    Visit(AContext.Tree.Root, '');
  finally
    mScan.Free;
  end;
end;

{ TDispinterfaceInvalidRule }

function TDispinterfaceInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDispinterfaceInvalidRuleId, TRuleSeverity.Error,
    cTexts[TTypeDeclarationsText.DispTitle].Text);
end;

procedure TDispinterfaceInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TDeclarationScan;

  /// <summary>Schließende Klammer zur öffnenden an AOpen (Klammerebene 0); Length(Tokens) ohne.</summary>
  function ClosingParen(AOpen: Integer): Integer;
  var
    mDepth: Integer;
  begin
    mDepth := 0;
    Result := AOpen;
    while Result < Length(mScan.Tokens) do
    begin
      if mScan.Tokens[Result].IsSymbol('(') then
      begin
        Inc(mDepth);
      end
      else if mScan.Tokens[Result].IsSymbol(')') then
      begin
        Dec(mDepth);
        if mDepth = 0 then
        begin
          Exit;
        end;
      end;
      Inc(Result);
    end;
  end;

  /// <summary>Vorfahr in Klammern (E2228) und fehlende GUID (E2229). AKeyword ist das Token dispinterface.</summary>
  procedure CheckHeader(ADeclaration: TSyntaxNode; AKeyword: Integer);
  var
    mHeaderEnd, mNext, mClose: Integer;
    mIndent: string;
  begin
    mHeaderEnd := AKeyword;
    mNext := mScan.NextCode(AKeyword + 1, Length(mScan.Tokens));
    if (mNext < Length(mScan.Tokens)) and mScan.Tokens[mNext].IsSymbol('(') then
    begin
      mClose := ClosingParen(mNext);
      if mClose >= Length(mScan.Tokens) then
      begin
        Exit;
      end;
      AReport.Add(TTextRange.Create(mScan.Tokens[mNext].StartPos, mScan.Tokens[mClose].EndPos),
        cTexts[TTypeDeclarationsText.DispAncestor].Text, TRuleConfidence.High,
        [TRuleFix.Create(cTexts[TTypeDeclarationsText.RemoveAncestor].Text,
          [TTextEdit.Create(TTextRange.Create(mScan.Tokens[AKeyword].EndPos,
          mScan.Tokens[mClose].EndPos), '')])]);
      mHeaderEnd := mClose;
      mNext := mScan.NextCode(mClose + 1, Length(mScan.Tokens));
    end;
    // Kurzform "D = dispinterface(I);" hat keinen Rumpf; dazu ist nichts belegt.
    if (mNext >= Length(mScan.Tokens)) or mScan.Tokens[mNext].IsSymbol('[') or mScan.Tokens[mNext].IsSymbol(';') then
    begin
      Exit;
    end;
    mIndent := TTextLines.IndentOf(AContext.Text, mScan.Tokens[mScan.FirstToken(ADeclaration)].StartPos.Line);
    AReport.Add(mScan.FirstRange(ADeclaration), cTexts[TTypeDeclarationsText.DispGuid].Fmt(
      [ADeclaration.Name]), TRuleConfidence.High, [TRuleFix.Create(cTexts[TTypeDeclarationsText.InsertGuid].Text,
      [TTextEdit.Create(TTextRange.Create(mScan.Tokens[mHeaderEnd].EndPos, mScan.Tokens[mHeaderEnd].EndPos),
        TTextLines.LineBreakOf(AContext.Text) + mIndent + '  ' + GuidLine)])]);
  end;

  // Direktiven an Methoden eines dispinterface: E2230.
  procedure CheckMethod(AHeader: TSyntaxNode);
  var
    mInner: Integer;
    mDirective: TSyntaxNode;
  begin
    for mInner := 0 to AHeader.ChildCount - 1 do
    begin
      mDirective := AHeader[mInner];
      if (mDirective.Kind = TSyntaxKind.Directive) and MatchText(mDirective.Name, cDispForbiddenDirectives) then
      begin
        AReport.Add(mScan.FirstRange(mDirective),
          cTexts[TTypeDeclarationsText.DispMethodDirective].Fmt([mDirective.Name]), TRuleConfidence.High,
          [TRuleFix.Create(cTexts[TTypeDeclarationsText.RemoveName].Fmt([mDirective.Name]),
            [mScan.DirectiveRemoval(mDirective)])]);
      end;
    end;
  end;

  // read und write an Properties eines dispinterface: E2231.
  procedure CheckProperty(AProperty: TSyntaxNode);
  var
    mInner: Integer;
    mWord: string;
  begin
    for mInner in mScan.ClauseWords(AProperty) do
    begin
      mWord := LowerCase(mScan.Tokens[mInner].Text);
      if (mWord = 'read') or (mWord = 'write') then
      begin
        AReport.Add(mScan.TokenRange(mInner), cTexts[TTypeDeclarationsText.DispDirective].Fmt([mWord]),
          TRuleConfidence.High);
      end;
    end;
  end;

  procedure CheckMembers(AType: TSyntaxNode);
  var
    mIndex: Integer;
    mChild: TSyntaxNode;
  begin
    for mIndex := 0 to AType.ChildCount - 1 do
    begin
      mChild := AType[mIndex];
      if not mScan.Unconditional(mChild) then
      begin
        Continue;
      end;
      if mChild.Kind = TSyntaxKind.RoutineHeader then
      begin
        CheckMethod(mChild);
      end
      else if mChild.Kind = TSyntaxKind.PropertyDecl then
      begin
        CheckProperty(mChild);
      end;
    end;
  end;

  /// <summary>Prüft die Typdeklaration ADecl, wenn sie ein dispinterface ist.</summary>
  procedure CheckDecl(ADecl: TSyntaxNode);
  var
    mBody: TSyntaxNode;
    mKeyword: Integer;
  begin
    mBody := ADecl.FindChild(TSyntaxKind.InterfaceType);
    if mBody = nil then
    begin
      Exit;
    end;
    mKeyword := mScan.DispKeyword(mBody);
    if mKeyword < 0 then
    begin
      Exit;
    end;
    if mScan.Unconditional(ADecl) then
    begin
      CheckHeader(ADecl, mKeyword);
    end;
    CheckMembers(mBody);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.TypeDecl then
        begin
          CheckDecl(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          if mNode[mIndex].Kind in cDeclarationKinds then
          begin
            mPending.Push(mNode[mIndex]);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mScan := TDeclarationScan.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    mScan.Free;
  end;
end;

procedure RegisterTypeDeclarationRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TMessageMethodInvalidRule.Create);
  ARegistry.Register(TInterfaceDeclarationInvalidRule.Create);
  ARegistry.Register(TImplementsClauseInvalidRule.Create);
  ARegistry.Register(TCallingConventionRequiredRule.Create);
  ARegistry.Register(TDispinterfaceInvalidRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TypeDeclarations', cTexts);

end.
