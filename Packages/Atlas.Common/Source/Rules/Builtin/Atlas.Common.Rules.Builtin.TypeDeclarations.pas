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
  MessageMethodInvalidRuleId = 'message-method-invalid';
  InterfaceDeclarationInvalidRuleId = 'interface-declaration-invalid';
  ImplementsClauseInvalidRuleId = 'implements-clause-invalid';
  CallingConventionRequiredRuleId = 'calling-convention-required';
  DispinterfaceInvalidRuleId = 'dispinterface-invalid';

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
  DeclarationKinds = [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile,
    TSyntaxKind.PackageFile, TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
    TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl, TSyntaxKind.ClassType, TSyntaxKind.Visibility];
  DefaultMessageParameter = '(var Msg: TMessage)';
  // Direktiven, die an Methoden eines Interfaces nicht erlaubt sind (E2210).
  InterfaceForbiddenDirectives: array[0..5] of string = ('virtual', 'dynamic', 'abstract', 'override', 'message',
    'reintroduce');
  // Aufrufkonventionen, die ein implements-Getter nicht haben darf (E2262).
  ForeignConventions: array[0..4] of string = ('cdecl', 'stdcall', 'pascal', 'safecall', 'winapi');
  // Direktiven, die an Methoden eines dispinterface sicher nicht erlaubt sind (E2230). Erlaubt sind dispid und die
  // Hinweise; overload und übrige Wörter bleiben ungeprüft still (#1328: nie strenger als dcc).
  DispForbiddenDirectives: array[0..15] of string = ('register', 'pascal', 'cdecl', 'stdcall', 'safecall', 'winapi',
    'virtual', 'dynamic', 'abstract', 'override', 'reintroduce', 'message', 'static', 'final', 'inline', 'varargs');
  // Spezifizierer einer Property nach Name und Typ.
  PropertySpecifiers: array[0..9] of string = ('read', 'write', 'stored', 'default', 'nodefault', 'index',
    'implements', 'dispid', 'readonly', 'writeonly');
  // Typen, die sicher kein Interface sind (E2205); Aliase können auf ein Interface zeigen.
  NonInterfaceKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
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
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to AType.ChildCount - 1 do
  begin
    if (AType[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(AType[Index].Name, AName) then
    begin
      if Result <> nil then
      begin
        Exit(nil);
      end;
      Result := AType[Index];
    end;
  end;
end;

/// <summary>Rumpf AClassName.AMethod im implementation-Teil von ATree; nil ohne oder bei mehreren.</summary>
function MethodBody(ATree: TSyntaxTree; const AClassName, AMethod: string): TSyntaxNode;
var
  Section: TSyntaxNode;
  Index: Integer;
  Many: Boolean;
begin
  Result := nil;
  Many := False;
  Section := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Section = nil then
  begin
    Section := ATree.Root;
  end;
  for Index := 0 to Section.ChildCount - 1 do
  begin
    if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(Section[Index].Name, AClassName + '.' + AMethod) then
    begin
      Many := Result <> nil;
      Result := Section[Index];
    end;
  end;
  if Many then
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
  FileName: string;
begin
  inherited Create;
  FTokens := AContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(FTokens);
  FileName := AContext.FileName;
  if FileName = '' then
  begin
    FileName := AContext.RelativePath;
  end;
  if FileName = '' then
  begin
    FileName := AContext.UnitName + '.pas';
  end;
  FResolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
  FResolver.Namespaces := AContext.Namespaces;
  FResolver.PinTree(AContext.Tree, FileName);
  FOwnUnit := FResolver.ExtractedUnit(AContext.Tree, FileName);
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
  Stop: Integer;
begin
  Stop := StopToken(AProperty);
  Result := FirstToken(AProperty);
  while (Result < Stop) and not ((FTokens[Result].Kind = TPascalTokenKind.Identifier) and
    SameText(FTokens[Result].Text, AProperty.Name)) do
  begin
    Inc(Result);
  end;
end;

function TDeclarationScan.PropertyRange(AProperty: TSyntaxNode): TTextRange;
var
  Index: Integer;
begin
  Index := PropertyNameToken(AProperty);
  if Index < StopToken(AProperty) then
  begin
    Result := TokenRange(Index);
  end
  else
  begin
    Result := TTextRange.Create(AProperty.StartPos, AProperty.EndPos);
  end;
end;

function TDeclarationScan.ClauseEnd(AProperty: TSyntaxNode): Integer;
var
  Stop, Depth: Integer;
begin
  Stop := StopToken(AProperty);
  Depth := 0;
  Result := PropertyNameToken(AProperty);
  while Result < Stop do
  begin
    if FTokens[Result].IsSymbol('[') or FTokens[Result].IsSymbol('(') then
    begin
      Inc(Depth);
    end
    else if FTokens[Result].IsSymbol(']') or FTokens[Result].IsSymbol(')') then
    begin
      Dec(Depth);
    end
    else if (Depth = 0) and FTokens[Result].IsSymbol(';') then
    begin
      Exit;
    end;
    Inc(Result);
  end;
end;

function TDeclarationScan.ClauseWords(AProperty: TSyntaxNode): TArray<Integer>;
var
  Index, Stop, Depth: Integer;
  Argument: Boolean;
begin
  Result := nil;
  Stop := ClauseEnd(AProperty);
  Depth := 0;
  // Ein Bezeichner direkt hinter read, write, stored … ist dessen Argument (read Stored), kein Spezifizierer.
  Argument := False;
  for Index := PropertyNameToken(AProperty) + 1 to Stop - 1 do
  begin
    if IsTrivia(FTokens[Index]) then
    begin
      Continue;
    end;
    if FTokens[Index].IsSymbol('[') or FTokens[Index].IsSymbol('(') then
    begin
      Inc(Depth);
    end
    else if FTokens[Index].IsSymbol(']') or FTokens[Index].IsSymbol(')') then
    begin
      Dec(Depth);
    end
    else if (Depth = 0) and not Argument and (FTokens[Index].Kind = TPascalTokenKind.Identifier) and
      MatchText(FTokens[Index].Text, PropertySpecifiers) then
    begin
      Result := Result + [Index];
      Argument := not MatchText(FTokens[Index].Text, ['nodefault', 'readonly', 'writeonly']);
      Continue;
    end;
    Argument := False;
  end;
end;

function TDeclarationScan.ClauseArgument(AProperty: TSyntaxNode; AIndex: Integer): Integer;
begin
  Result := NextCode(AIndex + 1, ClauseEnd(AProperty));
end;

function TDeclarationScan.Text(AFirst, AStop: Integer): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := AFirst to AStop - 1 do
  begin
    if not IsTrivia(FTokens[Index]) then
    begin
      Result := Result + FTokens[Index].Text;
    end;
  end;
end;

function TDeclarationScan.TypeKey(ANode: TSyntaxNode): string;
begin
  Result := TypeKey(FirstToken(ANode), StopToken(ANode));
end;

function TDeclarationScan.TypeKey(AFirst, AStop: Integer): string;
var
  Angle: Integer;
  Head: string;
begin
  Result := UpperCase(Text(AFirst, AStop));
  Angle := Pos('<', Result);
  if Angle = 0 then
  begin
    Angle := Length(Result) + 1;
  end;
  Head := Copy(Result, 1, Angle - 1);
  Result := Copy(Head, LastDelimiter('.', Head) + 1, MaxInt) + Copy(Result, Angle, MaxInt);
end;

/// <summary>Direktive message am Kopf AHeader (die letzte), nil ohne.</summary>
function MessageDirective(AHeader: TSyntaxNode): TSyntaxNode;
var
  Inner: Integer;
begin
  Result := nil;
  for Inner := 0 to AHeader.ChildCount - 1 do
  begin
    if (AHeader[Inner].Kind = TSyntaxKind.Directive) and (AHeader[Inner].Name = 'message') then
    begin
      Result := AHeader[Inner];
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
  Result := TRuleDescriptor.Create(MessageMethodInvalidRuleId, TRuleSeverity.Error,
    cTexts[TTypeDeclarationsText.MessageTitle].Text);
end;

procedure TMessageMethodInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Methods: TList<TMessageMethod>;
  Paths: TArray<string>;
  FileName: string;

  function FirstToken(ANode: TSyntaxNode): Integer;
  begin
    Result := TConstantValues.TokenFrom(Tokens, ANode.StartOffset);
  end;

  function NextCode(AIndex, AStop: Integer): Integer;
  begin
    Result := AIndex;
    while (Result < AStop) and IsTrivia(Tokens[Result]) do
    begin
      Inc(Result);
    end;
  end;

  procedure AddMethod(AHeader, ADirective: TSyntaxNode; const AClassName: string);
  var
    Stop: Integer;
    Method: TMessageMethod;
  begin
    Method := Default(TMessageMethod);
    Method.ClassName := AClassName;
    Method.Header := AHeader;
    Method.Directive := ADirective;
    Stop := TConstantValues.TokenFrom(Tokens, ADirective.EndOffset);
    Method.First := NextCode(FirstToken(ADirective) + 1, Stop);
    Method.Last := Stop - 1;
    while (Method.Last >= Method.First) and IsTrivia(Tokens[Method.Last]) do
    begin
      Dec(Method.Last);
    end;
    Methods.Add(Method);
  end;

  /// <summary>Merkt die message-Methoden der Klasse AClass mit dem Namen AClassName.</summary>
  procedure CollectClass(AClass: TSyntaxNode; const AClassName: string);
  var
    Index: Integer;
    Directive: TSyntaxNode;
  begin
    for Index := 0 to AClass.ChildCount - 1 do
    begin
      if AClass[Index].Kind <> TSyntaxKind.RoutineHeader then
      begin
        Continue;
      end;
      Directive := MessageDirective(AClass[Index]);
      if Directive <> nil then
      begin
        AddMethod(AClass[Index], Directive, AClassName);
      end;
    end;
  end;

  // Iterativ (Bericht M1).
  procedure Collect(ARoot: TSyntaxNode; const AOwner: string);
  var
    Pending: TStack<TSyntaxNode>;
    PendingOwner: TStack<string>;
    Node: TSyntaxNode;
    Index: Integer;
    Name: string;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    PendingOwner := TStack<string>.Create;
    try
      Pending.Push(ARoot);
      PendingOwner.Push(AOwner);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Name := NestedTypeName(PendingOwner.Pop, Node);
        if Node.Kind = TSyntaxKind.ClassType then
        begin
          CollectClass(Node, Name);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          if Node[Index].Kind in DeclarationKinds then
          begin
            Pending.Push(Node[Index]);
            PendingOwner.Push(Name);
          end;
        end;
      end;
    finally
      PendingOwner.Free;
      Pending.Free;
    end;
  end;

  /// <summary>Name der Methode im Kopf (Token hinter procedure/function).</summary>
  function NameRange(AHeader: TSyntaxNode): TTextRange;
  var
    Index, Stop: Integer;
  begin
    Result := TTextRange.Create(AHeader.StartPos, AHeader.EndPos);
    Stop := TConstantValues.TokenFrom(Tokens, AHeader.EndOffset);
    for Index := FirstToken(AHeader) to Stop - 1 do
    begin
      if Tokens[Index].Kind = TPascalTokenKind.Identifier then
      begin
        Exit(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos));
      end;
    end;
  end;

  function ExpressionText(const AMethod: TMessageMethod): string;
  var
    Index: Integer;
  begin
    Result := '';
    for Index := AMethod.First to AMethod.Last do
    begin
      if not IsTrivia(Tokens[Index]) then
      begin
        if (Result <> '') and (Tokens[Index - 1].Offset + Length(Tokens[Index - 1].Text) <> Tokens[Index].Offset) then
        begin
          Result := Result + ' ';
        end;
        Result := Result + Tokens[Index].Text;
      end;
    end;
  end;

  function MethodName(AHeader: TSyntaxNode): string;
  var
    Dot: Integer;
  begin
    Result := AHeader.Name;
    Dot := LastDelimiter('.', Result);
    if Dot > 0 then
    begin
      Result := Copy(Result, Dot + 1, MaxInt);
    end;
  end;

  /// <summary>Einziger Parameter ohne var: nur den Modifizierer ändern.</summary>
  function SingleParameter(AHeader: TSyntaxNode; out AParam: TSyntaxNode): Boolean;
  var
    Params: TSyntaxNode;
  begin
    AParam := nil;
    Params := AHeader.FindChild(TSyntaxKind.Parameters);
    Result := (Params <> nil) and (Params.ChildCount = 1) and (Pos(',', Params[0].Name) = 0) and
      (Params[0].FindChild(TSyntaxKind.Attribute) = nil);
    if Result then
    begin
      AParam := Params[0];
    end;
  end;

  function ParameterEdits(AHeader: TSyntaxNode; out AEdits: TArray<TTextEdit>): Boolean;
  var
    Param, Params: TSyntaxNode;
    Index: Integer;
    Position: TTextPosition;
  begin
    AEdits := nil;
    Result := True;
    if SingleParameter(AHeader, Param) then
    begin
      Index := FirstToken(Param);
      if Param.Modifier = TParameterModifier.None then
      begin
        AEdits := [TTextEdit.Create(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].StartPos), 'var ')];
      end
      else
      begin
        AEdits := [TTextEdit.Create(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos), 'var')];
      end;
      Exit;
    end;
    Params := AHeader.FindChild(TSyntaxKind.Parameters);
    if Params <> nil then
    begin
      AEdits := [TTextEdit.Create(TTextRange.Create(Params.StartPos, Params.EndPos), DefaultMessageParameter)];
    end
    else
    begin
      // Ohne Klammern: direkt hinter dem Namen einfügen.
      Position := NameRange(AHeader).EndPos;
      AEdits := [TTextEdit.Create(TTextRange.Create(Position, Position), DefaultMessageParameter)];
    end;
  end;

  function SignatureFix(const AMethod: TMessageMethod): TArray<TRuleFix>;
  var
    Edits, BodyEdits: TArray<TTextEdit>;
    Decl, Header: TSyntaxNode;
    Param: TSyntaxNode;
  begin
    Result := nil;
    if not ParameterEdits(AMethod.Header, Edits) then
    begin
      Exit;
    end;
    Decl := MethodBody(AContext.Tree, AMethod.ClassName, MethodName(AMethod.Header));
    if Decl <> nil then
    begin
      Header := Decl.FindChild(TSyntaxKind.RoutineHeader);
      // Rumpf ohne Parameterliste darf so bleiben; sonst gleich anpassen.
      if (Header <> nil) and (Header.FindChild(TSyntaxKind.Parameters) <> nil) then
      begin
        if SingleParameter(AMethod.Header, Param) <> SingleParameter(Header, Param) then
        begin
          Exit;
        end;
        if ParameterEdits(Header, BodyEdits) then
        begin
          Edits := Edits + BodyEdits;
        end;
      end;
    end;
    if SingleParameter(AMethod.Header, Param) then
    begin
      Result := [TRuleFix.Create(cTexts[TTypeDeclarationsText.PassAsVar].Fmt([Param.Name]), Edits)];
    end
    else
    begin
      Result := [TRuleFix.Create(cTexts[TTypeDeclarationsText.InsertSignature].Fmt([DefaultMessageParameter]), Edits)];
    end;
  end;

  procedure CheckParameters(const AMethod: TMessageMethod);
  var
    Params: TSyntaxNode;
    Keyword: string;
    Index: Integer;
  begin
    // Nur Prozeduren: message an Funktionen ist ein anderer Fall.
    Index := NextCode(FirstToken(AMethod.Header), Length(Tokens));
    if (Index < Length(Tokens)) and Tokens[Index].IsKeyword('class') then
    begin
      Exit;
    end;
    if Index >= Length(Tokens) then
    begin
      Exit;
    end;
    Keyword := LowerCase(Tokens[Index].Text);
    if Keyword <> 'procedure' then
    begin
      Exit;
    end;
    Params := AMethod.Header.FindChild(TSyntaxKind.Parameters);
    if (Params <> nil) and (Params.ChildCount = 1) and (Pos(',', Params[0].Name) = 0) and
      (Params[0].Modifier = TParameterModifier.VarParam) then
    begin
      Exit;
    end;
    AReport.Add(NameRange(AMethod.Header), cTexts[TTypeDeclarationsText.MessageParam].Fmt([MethodName(AMethod.Header)]),
      TRuleConfidence.High, SignatureFix(AMethod));
  end;

  function PathOf(const AMethod: TMessageMethod): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, FirstToken(AMethod.Header));
  end;

  /// <summary>Behandelt eine frühere message-Methode derselben Klasse in derselben Bedingungsvariante die
  /// Nummer mit dem Schlüssel AKeys[AIndex]? Index der früheren, -1 ohne.</summary>
  function EarlierHandler(const AKeys: TArray<string>; const AKnown: TArray<Boolean>; AIndex: Integer): Integer;
  var
    Earlier: Integer;
  begin
    for Earlier := 0 to AIndex - 1 do
    begin
      if AKnown[Earlier] and SameText(Methods[Earlier].ClassName, Methods[AIndex].ClassName) and
        (AKeys[Earlier] = AKeys[AIndex]) and
        not TConditionalBranches.Exclusive(PathOf(Methods[Earlier]), PathOf(Methods[AIndex])) then
      begin
        Exit(Earlier);
      end;
    end;
    Result := -1;
  end;

  /// <summary>Prüft die Nummer der Methode AIndex (E2139, E2140) und merkt ihren Schlüssel.</summary>
  procedure CheckNumber(AValues: TConstantValues; AIndex: Integer; var AKeys: TArray<string>;
    var AKnown: TArray<Boolean>);
  var
    Value: Int64;
    Method: TMessageMethod;
    Range: TTextRange;
    Earlier: Integer;
  begin
    Method := Methods[AIndex];
    Range := TTextRange.Create(Tokens[Method.First].StartPos, Tokens[Method.Last].EndPos);
    if not AValues.Evaluate(Method.First, Method.Last, Value) then
    begin
      AKeys[AIndex] := 't' + UpperCase(ExpressionText(Method).Replace(' ', ''));
    end
    else if Value < 1 then
    begin
      AReport.Add(Range, cTexts[TTypeDeclarationsText.MessageNumber].Fmt(
        [ExpressionText(Method), MethodName(Method.Header)]), TRuleConfidence.High);
      Exit;
    end
    else
    begin
      AKeys[AIndex] := 'v' + IntToStr(Value);
    end;
    AKnown[AIndex] := True;
    Earlier := EarlierHandler(AKeys, AKnown, AIndex);
    if Earlier >= 0 then
    begin
      AReport.Add(Range, cTexts[TTypeDeclarationsText.MessageHandled].Fmt([ExpressionText(Method),
        MethodName(Methods[Earlier].Header)]), TRuleConfidence.High);
    end;
  end;

  procedure CheckNumbers;
  var
    Resolver: TNameResolver;
    mCache: IRuleDerivedCache;
    Values: TConstantValues;
    Keys: TArray<string>;
    Known: TArray<Boolean>;
    Index: Integer;
  begin
    SetLength(Keys, Methods.Count);
    SetLength(Known, Methods.Count);
    // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
    mCache := TRuleDerived.Open(AContext);
    Resolver := TRuleDerived.Resolver(mCache, AContext);
    try
      Resolver.PinTree(AContext.Tree, FileName);
      Values := TConstantValues.Create(AContext.Tree, FileName, AContext.Index, Resolver);
      try
        for Index := 0 to Methods.Count - 1 do
        begin
          if Methods[Index].First <= Methods[Index].Last then
          begin
            CheckNumber(Values, Index, Keys, Known);
          end;
        end;
      finally
        Values.Free;
      end;
    finally
      Resolver.UnpinTree;
    end;
  end;

var
  Method: TMessageMethod;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  FileName := AContext.FileName;
  if FileName = '' then
  begin
    FileName := AContext.RelativePath;
  end;
  if FileName = '' then
  begin
    FileName := AContext.UnitName + '.pas';
  end;
  Methods := TList<TMessageMethod>.Create;
  try
    Collect(AContext.Tree.Root, '');
    if Methods.Count = 0 then
    begin
      Exit;
    end;
    Paths := TConditionalBranches.Paths(Tokens);
    for Method in Methods do
    begin
      CheckParameters(Method);
    end;
    CheckNumbers;
  finally
    Methods.Free;
  end;
end;

{ TInterfaceDeclarationInvalidRule }

function TInterfaceDeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(InterfaceDeclarationInvalidRuleId, TRuleSeverity.Error,
    cTexts[TTypeDeclarationsText.InterfaceTitle].Text);
end;

procedure TInterfaceDeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Scan: TDeclarationScan;

  /// <summary>Löst ANode (TypeReference) sicher zu einer Klasse, einem Record oder einer Aufzählung auf?</summary>
  function NotAnInterface(ANode: TSyntaxNode; out AKind: string): Boolean;
  var
    Resolved: TResolvedSymbol;
  begin
    AKind := '';
    Result := (ANode.Name <> '') and Scan.Resolver.ResolveTypeFrom(Scan.OwnUnit, ANode.Name, Resolved) and
      Resolved.Found and not Resolved.Builtin and (Resolved.SymbolKind in NonInterfaceKinds);
    if not Result then
    begin
      Exit;
    end;
    case Resolved.SymbolKind of
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
    Kind: string;
  begin
    if Scan.Unconditional(ANode) and NotAnInterface(ANode, Kind) then
    begin
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
        cTexts[TTypeDeclarationsText.NotInterface].Fmt([ANode.Name, Kind]), TRuleConfidence.High);
    end;
  end;

  procedure CheckClassList(AClass: TSyntaxNode);
  var
    Index, Earlier, Position: Integer;
    References: TArray<TSyntaxNode>;
  begin
    References := nil;
    for Index := 0 to AClass.ChildCount - 1 do
    begin
      if AClass[Index].Kind = TSyntaxKind.TypeReference then
      begin
        References := References + [AClass[Index]];
      end
      else
      begin
        Break;
      end;
    end;
    for Position := 1 to High(References) do
    begin
      ReportNotInterface(References[Position]);
      for Earlier := 0 to Position - 1 do
      begin
        if (Scan.TypeKey(References[Earlier]) = Scan.TypeKey(References[Position])) and
          Scan.Unconditional(References[Position]) then
        begin
          AReport.Add(TTextRange.Create(References[Position].StartPos, References[Position].EndPos),
            cTexts[TTypeDeclarationsText.AlreadyListed].Fmt([References[Position].Name]),
            TRuleConfidence.High);
          Break;
        end;
      end;
    end;
  end;

  /// <summary>Klauseln stored, nodefault und default mit Wert vor dem ersten Semikolon der Property.</summary>
  procedure CheckPropertyClauses(AProperty: TSyntaxNode);
  var
    Index: Integer;
    Word: string;
  begin
    for Index in Scan.ClauseWords(AProperty) do
    begin
      Word := LowerCase(Scan.Tokens[Index].Text);
      if (Word = 'stored') or (Word = 'nodefault') or
        ((Word = 'default') and (Scan.ClauseArgument(AProperty, Index) < Scan.ClauseEnd(AProperty))) then
      begin
        AReport.Add(Scan.TokenRange(Index), cTexts[TTypeDeclarationsText.ClauseNotAllowed].Fmt(
          [Word]), TRuleConfidence.High);
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
    mStop := Scan.StopToken(AProperty);
    mIndex := Scan.PropertyNameToken(AProperty);
    Result := mIndex < mStop;
    if Result then
    begin
      mIndex := Scan.NextCode(mIndex + 1, mStop);
      Result := (mIndex >= mStop) or not MatchText(Scan.Tokens[mIndex].Text, [':', '[']);
    end;
  end;

  // Geerbte Accessoren (property X read GetX mit GetX aus dem Vorfahr-Interface) übersetzt dcc, generisch wie
  // nicht generisch (DUnitX IList<T>; ID1, ID2, ID3; dcc-Lauf vom 29.10.2026, #1328): Die frühere Prüfung auf
  // E2370 ist entfallen.
  procedure CheckInheritedMembers(AType: TSyntaxNode; const AName: string);
  var
    Own, Ancestor, Member: TResolvedSymbol;
    Index: Integer;
    Child: TSyntaxNode;
  begin
    if not Scan.Resolver.ResolveTypeFrom(Scan.OwnUnit, AName, Own) or not Own.Found or
      (Own.SymbolKind <> TIndexSymbolKind.InterfaceType) or not Scan.Resolver.AncestorOf(Own, Ancestor) then
    begin
      Exit;
    end;
    for Index := 0 to AType.ChildCount - 1 do
    begin
      Child := AType[Index];
      if (Child.Kind <> TSyntaxKind.PropertyDecl) or not Scan.Unconditional(Child) then
      begin
        Continue;
      end;
      if WithoutType(Child) and Scan.Resolver.DeclaredMember(Ancestor, Child.Name, Member) and
        (Member.SymbolKind = TIndexSymbolKind.Property_) then
      begin
        AReport.Add(Scan.PropertyRange(Child), cTexts[TTypeDeclarationsText.PropertyRedeclared].Fmt([Child.Name,
          Member.Container]), TRuleConfidence.High);
      end;
    end;
  end;

  procedure ReportVarSection(ASection: TSyntaxNode);
  var
    Inner: Integer;
  begin
    for Inner := 0 to ASection.ChildCount - 1 do
    begin
      if ASection[Inner].Kind = TSyntaxKind.VarDecl then
      begin
        AReport.Add(Scan.FirstRange(ASection[Inner]), cTexts[TTypeDeclarationsText.NoFields].Text,
          TRuleConfidence.High);
      end;
    end;
  end;

  procedure ReportForbiddenDirectives(AHeader: TSyntaxNode);
  var
    Inner: Integer;
  begin
    for Inner := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[Inner].Kind = TSyntaxKind.Directive) and
        MatchText(AHeader[Inner].Name, InterfaceForbiddenDirectives) then
      begin
        AReport.Add(Scan.FirstRange(AHeader[Inner]),
          cTexts[TTypeDeclarationsText.DirectiveNotAllowed].Fmt([AHeader[Inner].Name]), TRuleConfidence.High);
      end;
    end;
  end;

  procedure CheckInterfaceMember(AChild: TSyntaxNode);
  begin
    case AChild.Kind of
      TSyntaxKind.Field:
        AReport.Add(Scan.FirstRange(AChild), cTexts[TTypeDeclarationsText.NoFields].Text, TRuleConfidence.High);
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
    Index: Integer;
  begin
    // dispinterface prüft dispinterface-invalid.
    if Scan.DispKeyword(AType) >= 0 then
    begin
      Exit;
    end;
    if (AType.ChildCount > 0) and (AType[0].Kind = TSyntaxKind.TypeReference) then
    begin
      ReportNotInterface(AType[0]);
    end;
    for Index := 0 to AType.ChildCount - 1 do
    begin
      if Scan.Unconditional(AType[Index]) then
      begin
        CheckInterfaceMember(AType[Index]);
      end;
    end;
    CheckInheritedMembers(AType, AName);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
    Body: TSyntaxNode;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.TypeDecl then
        begin
          Body := Node.FindChild(TSyntaxKind.InterfaceType);
          if Body <> nil then
          begin
            CheckInterface(Body, Node.Name);
          end;
          Body := Node.FindChild(TSyntaxKind.ClassType);
          if Body <> nil then
          begin
            CheckClassList(Body);
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          if Node[Index].Kind in DeclarationKinds then
          begin
            Pending.Push(Node[Index]);
          end;
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Scan := TDeclarationScan.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    Scan.Free;
  end;
end;

{ TImplementsClauseInvalidRule }

function TImplementsClauseInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ImplementsClauseInvalidRuleId, TRuleSeverity.Error,
    cTexts[TTypeDeclarationsText.ImplementsTitle].Text);
end;

procedure TImplementsClauseInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Scan: TDeclarationScan;

  function Word(AIndex: Integer): string;
  begin
    Result := LowerCase(Scan.Tokens[AIndex].Text);
  end;

  procedure CheckType(AProperty: TSyntaxNode);
  var
    Reference: TSyntaxNode;
    Resolved: TResolvedSymbol;
  begin
    Reference := AProperty.FindChild(TSyntaxKind.TypeReference);
    if (Reference = nil) or (Reference.Name = '') then
    begin
      Exit;
    end;
    // Eingebaute Typen (Integer, string …) stehen nicht im Index; ein eigener gleichnamiger Typ geht vor.
    if not Scan.Resolver.ResolveTypeFrom(Scan.OwnUnit, Reference.Name, Resolved) or not Resolved.Found then
    begin
      Resolved.Builtin := TResolverText.IsBuiltinTypeName(Reference.Name);
      if not Resolved.Builtin then
      begin
        Exit;
      end;
    end;
    if Resolved.Builtin or (Resolved.SymbolKind in [TIndexSymbolKind.RecordType, TIndexSymbolKind.EnumType]) then
    begin
      AReport.Add(TTextRange.Create(Reference.StartPos, Reference.EndPos),
        cTexts[TTypeDeclarationsText.ImplementsType].Fmt([Reference.Name]),
        TRuleConfidence.High);
    end;
  end;

  procedure CheckGetter(AType: TSyntaxNode; AGetter: Integer);
  var
    Header: TSyntaxNode;
    Index: Integer;
    Name: string;
  begin
    Header := UniqueMethodHeader(AType, Scan.Tokens[AGetter].Text);
    if Header = nil then
    begin
      Exit;
    end;
    for Index := 0 to Header.ChildCount - 1 do
    begin
      if Header[Index].Kind <> TSyntaxKind.Directive then
      begin
        Continue;
      end;
      Name := Header[Index].Name;
      if MatchText(Name, ForeignConventions) then
      begin
        AReport.Add(Scan.TokenRange(AGetter),
          cTexts[TTypeDeclarationsText.GetterRegister].Fmt([Scan.Tokens[AGetter].Text, Name]), TRuleConfidence.High);
      end
      else if (Name = 'dynamic') or (Name = 'message') then
      begin
        AReport.Add(Scan.TokenRange(AGetter), cTexts[TTypeDeclarationsText.GetterNot].Fmt([Scan.Tokens[AGetter].Text,
          Name]), TRuleConfidence.High);
      end;
    end;
  end;

  /// <summary>Token des Worts implements unter den Klauselwörtern AWords, -1 ohne; AHasRead bei read.</summary>
  function ImplementsWord(const AWords: TArray<Integer>; out AHasRead: Boolean): Integer;
  var
    Clause: Integer;
  begin
    Result := -1;
    AHasRead := False;
    for Clause in AWords do
    begin
      if Word(Clause) = 'implements' then
      begin
        Result := Clause;
      end
      else if Word(Clause) = 'read' then
      begin
        AHasRead := True;
      end;
    end;
  end;

  // index neben implements (E2260) und Getter hinter read.
  procedure CheckClauses(AType, AProperty: TSyntaxNode; const AWords: TArray<Integer>);
  var
    Clause, Argument: Integer;
  begin
    for Clause in AWords do
    begin
      Argument := Scan.ClauseArgument(AProperty, Clause);
      if Word(Clause) = 'index' then
      begin
        AReport.Add(Scan.TokenRange(Clause), cTexts[TTypeDeclarationsText.ImplementsIndex].Text,
          TRuleConfidence.High);
      end
      else if (Word(Clause) = 'read') and (Argument < Scan.ClauseEnd(AProperty)) and
        (Scan.Tokens[Argument].Kind = TPascalTokenKind.Identifier) then
      begin
        CheckGetter(AType, Argument);
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
    if Scan.Tokens[APosition].IsSymbol('<') then
    begin
      Inc(ADepth);
    end
    else if Scan.Tokens[APosition].IsSymbol('>') then
    begin
      Dec(ADepth);
    end;
    Result := (ADepth = 0) and Scan.Tokens[APosition].IsSymbol(',');
  end;

  /// <summary>Merkt das Interface zwischen AFirst und AStop als von AOwner umgesetzt; doppelt: E2257.</summary>
  procedure AddInterface(AFirst, AStop: Integer; const AOwner: string; var AKeys, AOwners: TArray<string>);
  var
    Key: string;
    Clause: Integer;
  begin
    Key := Scan.TypeKey(AFirst, AStop);
    for Clause := 0 to High(AKeys) do
    begin
      if AKeys[Clause] = Key then
      begin
        AReport.Add(TTextRange.Create(Scan.Tokens[AFirst].StartPos, Scan.Tokens[AStop - 1].EndPos),
          cTexts[TTypeDeclarationsText.AlreadyImplemented].Fmt([Scan.Text(AFirst, AStop),
          AOwners[Clause]]), TRuleConfidence.High);
        Exit;
      end;
    end;
    AKeys := AKeys + [Key];
    AOwners := AOwners + [AOwner];
  end;

  // Interfaces hinter implements, durch Kommas getrennt.
  procedure CollectInterfaces(AProperty: TSyntaxNode; AImplements: Integer; var AKeys, AOwners: TArray<string>);
  var
    First, Depth, Position, Stop: Integer;
  begin
    Stop := Scan.ClauseEnd(AProperty);
    First := Scan.NextCode(AImplements + 1, Stop);
    Depth := 0;
    for Position := First to Stop do
    begin
      if not EndsInterface(Position, Stop, Depth) then
      begin
        Continue;
      end;
      if Position > First then
      begin
        AddInterface(First, Position, AProperty.Name, AKeys, AOwners);
      end;
      First := Scan.NextCode(Position + 1, Stop);
    end;
  end;

  procedure CheckProperty(AType, AProperty: TSyntaxNode; var AKeys, AOwners: TArray<string>);
  var
    Words: TArray<Integer>;
    Implements: Integer;
    HasRead: Boolean;
  begin
    Words := Scan.ClauseWords(AProperty);
    Implements := ImplementsWord(Words, HasRead);
    if Implements < 0 then
    begin
      Exit;
    end;
    if AType.Kind <> TSyntaxKind.ClassType then
    begin
      AReport.Add(Scan.TokenRange(Implements), cTexts[TTypeDeclarationsText.ImplementsClassOnly].Text,
        TRuleConfidence.High);
      Exit;
    end;
    CheckType(AProperty);
    CheckClauses(AType, AProperty, Words);
    if not HasRead then
    begin
      AReport.Add(Scan.TokenRange(Implements), cTexts[TTypeDeclarationsText.ImplementsReadable].Text,
        TRuleConfidence.High);
    end;
    CollectInterfaces(AProperty, Implements, AKeys, AOwners);
  end;

  // Methodenzuordnung (procedure IFoo.Bar = Baz) für ein Interface mit implements-Property: E2264.
  procedure CheckResolution(AHeader: TSyntaxNode; const AKeys, AOwners: TArray<string>);
  var
    Prefix: string;
    Clause: Integer;
  begin
    Prefix := UpperCase(Copy(AHeader.Name, 1, LastDelimiter('.', AHeader.Name) - 1));
    Prefix := Copy(Prefix, LastDelimiter('.', Prefix) + 1, MaxInt);
    for Clause := 0 to High(AKeys) do
    begin
      if AKeys[Clause] = Prefix then
      begin
        AReport.Add(Scan.TokenRange(Scan.NextCode(Scan.FirstToken(AHeader) + 1, Scan.StopToken(AHeader))),
          cTexts[TTypeDeclarationsText.MethodResolution].Fmt([Copy(AHeader.Name, 1, LastDelimiter('.',
            AHeader.Name) - 1), AOwners[Clause]]),
          TRuleConfidence.High);
        Exit;
      end;
    end;
  end;

  procedure CheckClass(AType: TSyntaxNode);
  var
    Index: Integer;
    Child: TSyntaxNode;
    Keys, Owners: TArray<string>;
  begin
    Keys := nil;
    Owners := nil;
    for Index := 0 to AType.ChildCount - 1 do
    begin
      Child := AType[Index];
      if (Child.Kind = TSyntaxKind.PropertyDecl) and Scan.Unconditional(Child) then
      begin
        CheckProperty(AType, Child, Keys, Owners);
      end;
    end;
    for Index := 0 to AType.ChildCount - 1 do
    begin
      Child := AType[Index];
      if (Child.Kind = TSyntaxKind.RoutineHeader) and (Pos('.', Child.Name) > 0) and Scan.Unconditional(Child) then
      begin
        CheckResolution(Child, Keys, Owners);
      end;
    end;
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.InterfaceType,
          TSyntaxKind.ObjectType, TSyntaxKind.HelperType] then
        begin
          CheckClass(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          if Node[Index].Kind in DeclarationKinds + [TSyntaxKind.RecordType, TSyntaxKind.InterfaceType,
            TSyntaxKind.ObjectType, TSyntaxKind.HelperType] then
          begin
            Pending.Push(Node[Index]);
          end;
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Scan := TDeclarationScan.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    Scan.Free;
  end;
end;

{ TCallingConventionRequiredRule }

function TCallingConventionRequiredRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(CallingConventionRequiredRuleId, TRuleSeverity.Error,
    cTexts[TTypeDeclarationsText.ConventionTitle].Text);
end;

procedure TCallingConventionRequiredRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Scan: TDeclarationScan;

  function Directive(AHeader: TSyntaxNode; const AName: string): TSyntaxNode;
  var
    Index: Integer;
  begin
    Result := nil;
    for Index := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[Index].Kind = TSyntaxKind.Directive) and SameText(AHeader[Index].Name, AName) then
      begin
        Exit(AHeader[Index]);
      end;
    end;
  end;

  function Convention(AHeader: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
  begin
    Result := nil;
    for Index := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[Index].Kind = TSyntaxKind.Directive) and MatchText(AHeader[Index].Name, ForeignConventions) then
      begin
        Exit(AHeader[Index]);
      end;
    end;
  end;

  function Keyword(AHeader: TSyntaxNode): string;
  var
    Index: Integer;
  begin
    Index := Scan.NextCode(Scan.FirstToken(AHeader), Length(Scan.Tokens));
    Result := '';
    if Index < Length(Scan.Tokens) then
    begin
      Result := LowerCase(Scan.Tokens[Index].Text);
    end;
  end;

  /// <summary>Korrektur: Konvention an AHeader und am Rumpf der Datei entfernen.</summary>
  function RemoveFix(const AClassName: string; AHeader, AConvention: TSyntaxNode): TArray<TRuleFix>;
  var
    Edits: TArray<TTextEdit>;
    Body, Other: TSyntaxNode;
  begin
    Edits := [Scan.DirectiveRemoval(AConvention)];
    Body := MethodBody(AContext.Tree, AClassName, AHeader.Name);
    if Body <> nil then
    begin
      Body := Body.FindChild(TSyntaxKind.RoutineHeader);
    end;
    if Body <> nil then
    begin
      Other := Directive(Body, AConvention.Name);
      if Other <> nil then
      begin
        Edits := Edits + [Scan.DirectiveRemoval(Other)];
      end;
    end;
    Result := [TRuleFix.Create(cTexts[TTypeDeclarationsText.RemoveName].Fmt([AConvention.Name]), Edits)];
  end;

  // Konstruktoren und Destruktoren mit fremder Konvention: E2236.
  procedure CheckConstructor(AHeader: TSyntaxNode; const AClassName: string);
  var
    Found: TSyntaxNode;
  begin
    Found := Convention(AHeader);
    if Found <> nil then
    begin
      AReport.Add(Scan.FirstRange(Found), cTexts[TTypeDeclarationsText.CtorRegister].Fmt([Found.Name]),
        TRuleConfidence.High, RemoveFix(AClassName, AHeader, Found));
    end;
  end;

  /// <summary>Methodenkopf hinter der Klausel read/write AClause einer Property von AType, nil ohne.</summary>
  function AccessorHeader(AType, AProperty: TSyntaxNode; AClause: Integer; out AArgument: Integer): TSyntaxNode;
  begin
    Result := nil;
    AArgument := Scan.ClauseArgument(AProperty, AClause);
    if MatchText(Scan.Tokens[AClause].Text, ['read', 'write']) and (AArgument < Scan.ClauseEnd(AProperty)) and
      (Scan.Tokens[AArgument].Kind = TPascalTokenKind.Identifier) then
    begin
      Result := UniqueMethodHeader(AType, Scan.Tokens[AArgument].Text);
    end;
  end;

  // Getter und Setter einer published-Property mit fremder Konvention: E2270.
  procedure CheckPublishedProperty(AType, AProperty: TSyntaxNode; const AClassName: string);
  var
    Clause, Argument: Integer;
    Header, Found: TSyntaxNode;
    Kind: string;
  begin
    for Clause in Scan.ClauseWords(AProperty) do
    begin
      Header := AccessorHeader(AType, AProperty, Clause, Argument);
      Found := nil;
      if Header <> nil then
      begin
        Found := Convention(Header);
      end;
      if Found = nil then
      begin
        Continue;
      end;
      Kind := 'Setter';
      if SameText(Scan.Tokens[Clause].Text, 'read') then
      begin
        Kind := 'Getter';
      end;
      AReport.Add(Scan.TokenRange(Argument), cTexts[TTypeDeclarationsText.PublishedRegister].Fmt([Kind,
        Scan.Tokens[Argument].Text, AProperty.Name, Found.Name]),
        TRuleConfidence.High, RemoveFix(AClassName, Header, Found));
    end;
  end;

  procedure CheckClass(AType: TSyntaxNode; const AClassName: string);
  var
    Index: Integer;
    Child: TSyntaxNode;
    Published: Boolean;
  begin
    Published := False;
    for Index := 0 to AType.ChildCount - 1 do
    begin
      Child := AType[Index];
      if Child.Kind = TSyntaxKind.Visibility then
      begin
        Published := Child.Name = 'published';
      end
      else if not Scan.Unconditional(Child) then
      begin
        Continue;
      end
      else if (Child.Kind = TSyntaxKind.RoutineHeader) and MatchText(Keyword(Child), ['constructor', 'destructor']) then
      begin
        CheckConstructor(Child, AClassName);
      end
      else if (Child.Kind = TSyntaxKind.PropertyDecl) and Published then
      begin
        CheckPublishedProperty(AType, Child, AClassName);
      end;
    end;
  end;

  procedure CheckVarargs(AHeader: TSyntaxNode);
  var
    Varargs, Found: TSyntaxNode;
    Code: string;
    Edit: TTextEdit;
    Position: TTextPosition;
  begin
    Varargs := Directive(AHeader, 'varargs');
    if (Varargs = nil) or not Scan.Unconditional(AHeader) then
    begin
      Exit;
    end;
    // Ohne external: dcc meldet E2277 unter Win32 auch mit cdecl; Win64 übersetzt es (Cm.E2277, #1380).
    if Directive(AHeader, 'external') = nil then
    begin
      if AContext.Tree.Platform = 'Win32' then
      begin
        AReport.Add(Scan.FirstRange(Varargs), cTexts[TTypeDeclarationsText.VarargsWin32].Text, TRuleConfidence.High);
      end;
      Exit;
    end;
    if Directive(AHeader, 'cdecl') <> nil then
    begin
      Exit;
    end;
    Code := 'E2277';
    Found := Convention(AHeader);
    if Found = nil then
    begin
      Found := Directive(AHeader, 'register');
    end;
    if Found <> nil then
    begin
      Edit := TTextEdit.Create(Scan.FirstRange(Found), 'cdecl');
    end
    else
    begin
      Position := Scan.FirstRange(Varargs).StartPos;
      Edit := TTextEdit.Create(TTextRange.Create(Position, Position), 'cdecl; ');
    end;
    AReport.Add(Scan.FirstRange(Varargs), cTexts[TTypeDeclarationsText.VarargsCdecl].Fmt([Code]),
      TRuleConfidence.High, [TRuleFix.Create(cTexts[TTypeDeclarationsText.SetCdecl].Text, [Edit])]);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode; const AOwner: string);
  var
    Pending: TStack<TSyntaxNode>;
    PendingOwner: TStack<string>;
    Node: TSyntaxNode;
    Index: Integer;
    Name: string;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    PendingOwner := TStack<string>.Create;
    try
      Pending.Push(ARoot);
      PendingOwner.Push(AOwner);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Name := NestedTypeName(PendingOwner.Pop, Node);
        if Node.Kind = TSyntaxKind.ClassType then
        begin
          CheckClass(Node, Name);
        end;
        if Node.Kind = TSyntaxKind.RoutineHeader then
        begin
          CheckVarargs(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          if Node[Index].Kind in DeclarationKinds + [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader,
            TSyntaxKind.RecordType, TSyntaxKind.ObjectType, TSyntaxKind.HelperType] then
          begin
            Pending.Push(Node[Index]);
            PendingOwner.Push(Name);
          end;
        end;
      end;
    finally
      PendingOwner.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Scan := TDeclarationScan.Create(AContext);
  try
    Visit(AContext.Tree.Root, '');
  finally
    Scan.Free;
  end;
end;

{ TDispinterfaceInvalidRule }

function TDispinterfaceInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DispinterfaceInvalidRuleId, TRuleSeverity.Error,
    cTexts[TTypeDeclarationsText.DispTitle].Text);
end;

procedure TDispinterfaceInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Scan: TDeclarationScan;

  /// <summary>Schließende Klammer zur öffnenden an AOpen (Klammerebene 0); Length(Tokens) ohne.</summary>
  function ClosingParen(AOpen: Integer): Integer;
  var
    mDepth: Integer;
  begin
    mDepth := 0;
    Result := AOpen;
    while Result < Length(Scan.Tokens) do
    begin
      if Scan.Tokens[Result].IsSymbol('(') then
      begin
        Inc(mDepth);
      end
      else if Scan.Tokens[Result].IsSymbol(')') then
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
    mNext := Scan.NextCode(AKeyword + 1, Length(Scan.Tokens));
    if (mNext < Length(Scan.Tokens)) and Scan.Tokens[mNext].IsSymbol('(') then
    begin
      mClose := ClosingParen(mNext);
      if mClose >= Length(Scan.Tokens) then
      begin
        Exit;
      end;
      AReport.Add(TTextRange.Create(Scan.Tokens[mNext].StartPos, Scan.Tokens[mClose].EndPos),
        cTexts[TTypeDeclarationsText.DispAncestor].Text, TRuleConfidence.High,
        [TRuleFix.Create(cTexts[TTypeDeclarationsText.RemoveAncestor].Text,
          [TTextEdit.Create(TTextRange.Create(Scan.Tokens[AKeyword].EndPos,
          Scan.Tokens[mClose].EndPos), '')])]);
      mHeaderEnd := mClose;
      mNext := Scan.NextCode(mClose + 1, Length(Scan.Tokens));
    end;
    // Kurzform "D = dispinterface(I);" hat keinen Rumpf; dazu ist nichts belegt.
    if (mNext >= Length(Scan.Tokens)) or Scan.Tokens[mNext].IsSymbol('[') or Scan.Tokens[mNext].IsSymbol(';') then
    begin
      Exit;
    end;
    mIndent := TTextLines.IndentOf(AContext.Text, Scan.Tokens[Scan.FirstToken(ADeclaration)].StartPos.Line);
    AReport.Add(Scan.FirstRange(ADeclaration), cTexts[TTypeDeclarationsText.DispGuid].Fmt(
      [ADeclaration.Name]), TRuleConfidence.High, [TRuleFix.Create(cTexts[TTypeDeclarationsText.InsertGuid].Text,
      [TTextEdit.Create(TTextRange.Create(Scan.Tokens[mHeaderEnd].EndPos, Scan.Tokens[mHeaderEnd].EndPos),
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
      if (mDirective.Kind = TSyntaxKind.Directive) and MatchText(mDirective.Name, DispForbiddenDirectives) then
      begin
        AReport.Add(Scan.FirstRange(mDirective),
          cTexts[TTypeDeclarationsText.DispMethodDirective].Fmt([mDirective.Name]), TRuleConfidence.High,
          [TRuleFix.Create(cTexts[TTypeDeclarationsText.RemoveName].Fmt([mDirective.Name]),
            [Scan.DirectiveRemoval(mDirective)])]);
      end;
    end;
  end;

  // read und write an Properties eines dispinterface: E2231.
  procedure CheckProperty(AProperty: TSyntaxNode);
  var
    mInner: Integer;
    mWord: string;
  begin
    for mInner in Scan.ClauseWords(AProperty) do
    begin
      mWord := LowerCase(Scan.Tokens[mInner].Text);
      if (mWord = 'read') or (mWord = 'write') then
      begin
        AReport.Add(Scan.TokenRange(mInner), cTexts[TTypeDeclarationsText.DispDirective].Fmt([mWord]),
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
      if not Scan.Unconditional(mChild) then
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
    mKeyword := Scan.DispKeyword(mBody);
    if mKeyword < 0 then
    begin
      Exit;
    end;
    if Scan.Unconditional(ADecl) then
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
          if mNode[mIndex].Kind in DeclarationKinds then
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
  Scan := TDeclarationScan.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    Scan.Free;
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
