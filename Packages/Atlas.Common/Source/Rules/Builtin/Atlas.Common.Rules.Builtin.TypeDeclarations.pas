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
//                        nur mit cdecl (wie E2277 bei external, sonst E2591).
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
  Atlas.Text.Lines;

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
    if (AType[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(AType[Index].Name, AName) then
    begin
      if Result <> nil then
        Exit(nil);
      Result := AType[Index];
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
    Section := ATree.Root;
  for Index := 0 to Section.ChildCount - 1 do
    if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(Section[Index].Name, AClassName + '.' + AMethod) then
    begin
      Many := Result <> nil;
      Result := Section[Index];
    end;
  if Many then
    Result := nil;
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
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
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
    Inc(Result);
end;

function TDeclarationScan.PreviousCode(AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(FTokens[Result]) do
    Dec(Result);
end;

function TDeclarationScan.DirectiveRemoval(ADirective: TSyntaxNode): TTextEdit;
var
  mFirst, mLast, mNext, mBefore: Integer;
begin
  mFirst := FirstToken(ADirective);
  mLast := StopToken(ADirective) - 1;
  mNext := NextCode(mLast + 1, Length(FTokens));
  if (mNext < Length(FTokens)) and FTokens[mNext].IsSymbol(';') then
    mLast := mNext;
  mBefore := PreviousCode(mFirst);
  if mBefore < 0 then
    mBefore := mFirst;
  Result := TTextEdit.Create(TTextRange.Create(FTokens[mBefore].EndPos, FTokens[mLast].EndPos), '');
end;

function TDeclarationScan.DispKeyword(AType: TSyntaxNode): Integer;
begin
  Result := NextCode(FirstToken(AType), Length(FTokens));
  if (Result >= Length(FTokens)) or not SameText(FTokens[Result].Text, 'dispinterface') then
    Result := -1;
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
    Inc(Result);
end;

function TDeclarationScan.PropertyRange(AProperty: TSyntaxNode): TTextRange;
var
  Index: Integer;
begin
  Index := PropertyNameToken(AProperty);
  if Index < StopToken(AProperty) then
    Result := TokenRange(Index)
  else
    Result := TTextRange.Create(AProperty.StartPos, AProperty.EndPos);
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
      Inc(Depth)
    else if FTokens[Result].IsSymbol(']') or FTokens[Result].IsSymbol(')') then
      Dec(Depth)
    else if (Depth = 0) and FTokens[Result].IsSymbol(';') then
      Exit;
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
      Continue;
    if FTokens[Index].IsSymbol('[') or FTokens[Index].IsSymbol('(') then
      Inc(Depth)
    else if FTokens[Index].IsSymbol(']') or FTokens[Index].IsSymbol(')') then
      Dec(Depth)
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
    if not IsTrivia(FTokens[Index]) then
      Result := Result + FTokens[Index].Text;
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
    Angle := Length(Result) + 1;
  Head := Copy(Result, 1, Angle - 1);
  Result := Copy(Head, LastDelimiter('.', Head) + 1, MaxInt) + Copy(Result, Angle, MaxInt);
end;

{ TMessageMethodInvalidRule }

function TMessageMethodInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(MessageMethodInvalidRuleId, TRuleSeverity.Error,
    'message-Methode falsch deklariert');
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
      Inc(Result);
  end;

  // Iterativ (Bericht M1).
  procedure Collect(ARoot: TSyntaxNode; const AOwner: string);
  var
    Pending: TStack<TSyntaxNode>;
    PendingOwner: TStack<string>;
    Node: TSyntaxNode;
    Owner: string;
    Index, Inner, Stop: Integer;
    Name: string;
    Header, Directive: TSyntaxNode;
    Method: TMessageMethod;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    PendingOwner := TStack<string>.Create;
    try
      Pending.Push(ARoot);
      PendingOwner.Push(AOwner);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Owner := PendingOwner.Pop;
        Name := Owner;
        if Node.Kind = TSyntaxKind.TypeDecl then
        begin
          if Owner = '' then
            Name := Node.Name
          else
            Name := Owner + '.' + Node.Name;
        end;
        if Node.Kind = TSyntaxKind.ClassType then
          for Index := 0 to Node.ChildCount - 1 do
          begin
            Header := Node[Index];
            if Header.Kind <> TSyntaxKind.RoutineHeader then
              Continue;
            Directive := nil;
            for Inner := 0 to Header.ChildCount - 1 do
              if (Header[Inner].Kind = TSyntaxKind.Directive) and (Header[Inner].Name = 'message') then
                Directive := Header[Inner];
            if Directive = nil then
              Continue;
            Method := Default(TMessageMethod);
            Method.ClassName := Name;
            Method.Header := Header;
            Method.Directive := Directive;
            Stop := TConstantValues.TokenFrom(Tokens, Directive.EndOffset);
            Method.First := NextCode(FirstToken(Directive) + 1, Stop);
            Method.Last := Stop - 1;
            while (Method.Last >= Method.First) and IsTrivia(Tokens[Method.Last]) do
              Dec(Method.Last);
            Methods.Add(Method);
          end;
        for Index := Node.ChildCount - 1 downto 0 do
          if Node[Index].Kind in DeclarationKinds then
          begin
            Pending.Push(Node[Index]);
            PendingOwner.Push(Name);
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
      if Tokens[Index].Kind = TPascalTokenKind.Identifier then
        Exit(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos));
  end;

  function ExpressionText(const AMethod: TMessageMethod): string;
  var
    Index: Integer;
  begin
    Result := '';
    for Index := AMethod.First to AMethod.Last do
      if not IsTrivia(Tokens[Index]) then
      begin
        if (Result <> '') and (Tokens[Index - 1].Offset + Length(Tokens[Index - 1].Text) <> Tokens[Index].Offset) then
          Result := Result + ' ';
        Result := Result + Tokens[Index].Text;
      end;
  end;

  function MethodName(AHeader: TSyntaxNode): string;
  var
    Dot: Integer;
  begin
    Result := AHeader.Name;
    Dot := LastDelimiter('.', Result);
    if Dot > 0 then
      Result := Copy(Result, Dot + 1, MaxInt);
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
      AParam := Params[0];
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
        AEdits := [TTextEdit.Create(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].StartPos), 'var ')]
      else
        AEdits := [TTextEdit.Create(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos), 'var')];
      Exit;
    end;
    Params := AHeader.FindChild(TSyntaxKind.Parameters);
    if Params <> nil then
      AEdits := [TTextEdit.Create(TTextRange.Create(Params.StartPos, Params.EndPos), DefaultMessageParameter)]
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
      Exit;
    Decl := MethodBody(AContext.Tree, AMethod.ClassName, MethodName(AMethod.Header));
    if Decl <> nil then
    begin
      Header := Decl.FindChild(TSyntaxKind.RoutineHeader);
      // Rumpf ohne Parameterliste darf so bleiben; sonst gleich anpassen.
      if (Header <> nil) and (Header.FindChild(TSyntaxKind.Parameters) <> nil) then
      begin
        if SingleParameter(AMethod.Header, Param) <> SingleParameter(Header, Param) then
          Exit;
        if ParameterEdits(Header, BodyEdits) then
          Edits := Edits + BodyEdits;
      end;
    end;
    if SingleParameter(AMethod.Header, Param) then
      Result := [TRuleFix.Create(Format('Parameter %s als var übergeben', [Param.Name]), Edits)]
    else
      Result := [TRuleFix.Create(Format('Signatur %s einsetzen', [DefaultMessageParameter]), Edits)];
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
      Exit;
    if Index >= Length(Tokens) then
      Exit;
    Keyword := LowerCase(Tokens[Index].Text);
    if Keyword <> 'procedure' then
      Exit;
    Params := AMethod.Header.FindChild(TSyntaxKind.Parameters);
    if (Params <> nil) and (Params.ChildCount = 1) and (Pos(',', Params[0].Name) = 0) and
      (Params[0].Modifier = TParameterModifier.VarParam) then
      Exit;
    AReport.Add(NameRange(AMethod.Header), Format('Die message-Methode %s braucht genau einen var-Parameter ' +
      '(wie E2138).', [MethodName(AMethod.Header)]), TRuleConfidence.High, SignatureFix(AMethod));
  end;

  function PathOf(const AMethod: TMessageMethod): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, FirstToken(AMethod.Header));
  end;

  procedure CheckNumbers;
  var
    Resolver: TNameResolver;
    Values: TConstantValues;
    Keys: TArray<string>;
    Known: TArray<Boolean>;
    Index, Earlier: Integer;
    Value: Int64;
    Method: TMessageMethod;
    Range: TTextRange;
  begin
    SetLength(Keys, Methods.Count);
    SetLength(Known, Methods.Count);
    Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
    try
      Resolver.Namespaces := AContext.Namespaces;
      Resolver.PinTree(AContext.Tree, FileName);
      Values := TConstantValues.Create(AContext.Tree, FileName, AContext.Index, Resolver);
      try
        for Index := 0 to Methods.Count - 1 do
        begin
          Method := Methods[Index];
          if Method.First > Method.Last then
            Continue;
          Range := TTextRange.Create(Tokens[Method.First].StartPos, Tokens[Method.Last].EndPos);
          if Values.Evaluate(Method.First, Method.Last, Value) then
          begin
            Keys[Index] := 'v' + IntToStr(Value);
            if Value < 1 then
            begin
              AReport.Add(Range, Format('Die Nachrichtennummer %s von %s muss mindestens 1 sein (wie E2139).',
                [ExpressionText(Method), MethodName(Method.Header)]), TRuleConfidence.High);
              Continue;
            end;
          end
          else
            Keys[Index] := 't' + UpperCase(ExpressionText(Method).Replace(' ', ''));
          Known[Index] := True;
          for Earlier := 0 to Index - 1 do
            if Known[Earlier] and SameText(Methods[Earlier].ClassName, Method.ClassName) and
              (Keys[Earlier] = Keys[Index]) and
              not TConditionalBranches.Exclusive(PathOf(Methods[Earlier]), PathOf(Method)) then
            begin
              AReport.Add(Range, Format('%s wird schon von %s behandelt (wie E2140).', [ExpressionText(Method),
                MethodName(Methods[Earlier].Header)]), TRuleConfidence.High);
              Break;
            end;
        end;
      finally
        Values.Free;
      end;
    finally
      Resolver.UnpinTree;
      Resolver.Free;
    end;
  end;

var
  Method: TMessageMethod;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Methods := TList<TMessageMethod>.Create;
  try
    Collect(AContext.Tree.Root, '');
    if Methods.Count = 0 then
      Exit;
    Paths := TConditionalBranches.Paths(Tokens);
    for Method in Methods do
      CheckParameters(Method);
    CheckNumbers;
  finally
    Methods.Free;
  end;
end;

{ TInterfaceDeclarationInvalidRule }

function TInterfaceDeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(InterfaceDeclarationInvalidRuleId, TRuleSeverity.Error,
    'Unzulässige Deklaration in einem Interface');
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
      Exit;
    case Resolved.SymbolKind of
      TIndexSymbolKind.RecordType:
        AKind := 'ein Record';
      TIndexSymbolKind.EnumType:
        AKind := 'eine Aufzählung';
    else
      AKind := 'eine Klasse';
    end;
  end;

  procedure ReportNotInterface(ANode: TSyntaxNode);
  var
    Kind: string;
  begin
    if Scan.Unconditional(ANode) and NotAnInterface(ANode, Kind) then
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('%s ist %s und kein Interface ' +
        '(wie E2205).', [ANode.Name, Kind]), TRuleConfidence.High);
  end;

  procedure CheckClassList(AClass: TSyntaxNode);
  var
    Index, Earlier, Position: Integer;
    References: TArray<TSyntaxNode>;
  begin
    References := nil;
    for Index := 0 to AClass.ChildCount - 1 do
      if AClass[Index].Kind = TSyntaxKind.TypeReference then
        References := References + [AClass[Index]]
      else
        Break;
    for Position := 1 to High(References) do
    begin
      ReportNotInterface(References[Position]);
      for Earlier := 0 to Position - 1 do
        if (Scan.TypeKey(References[Earlier]) = Scan.TypeKey(References[Position])) and
          Scan.Unconditional(References[Position]) then
        begin
          AReport.Add(TTextRange.Create(References[Position].StartPos, References[Position].EndPos),
            Format('%s steht schon in der Liste der Interfaces (wie E2208).', [References[Position].Name]),
            TRuleConfidence.High);
          Break;
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
        AReport.Add(Scan.TokenRange(Index), Format('Die Klausel %s ist in Interfaces nicht erlaubt (wie E2207).',
          [Word]), TRuleConfidence.High);
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
      Exit;
    for Index := 0 to AType.ChildCount - 1 do
    begin
      Child := AType[Index];
      if (Child.Kind <> TSyntaxKind.PropertyDecl) or not Scan.Unconditional(Child) then
        Continue;
      if WithoutType(Child) and Scan.Resolver.DeclaredMember(Ancestor, Child.Name, Member) and
        (Member.SymbolKind = TIndexSymbolKind.Property_) then
        AReport.Add(Scan.PropertyRange(Child), Format('Die Property %s ist schon in %s ' +
          'deklariert; Interfaces dürfen Properties nicht ohne Typ neu aufführen (wie E2206).', [Child.Name,
          Member.Container]), TRuleConfidence.High);
    end;
  end;

  procedure CheckInterface(AType: TSyntaxNode; const AName: string);
  var
    Index, Inner: Integer;
    Child: TSyntaxNode;
    First: Boolean;
  begin
    // dispinterface prüft dispinterface-invalid.
    if Scan.DispKeyword(AType) >= 0 then
      Exit;
    First := True;
    for Index := 0 to AType.ChildCount - 1 do
    begin
      Child := AType[Index];
      if (Child.Kind = TSyntaxKind.TypeReference) and First then
        ReportNotInterface(Child);
      First := False;
      if not Scan.Unconditional(Child) then
        Continue;
      case Child.Kind of
        TSyntaxKind.Field:
          AReport.Add(Scan.FirstRange(Child), 'Interfaces dürfen keine Felder haben (wie E2209).', TRuleConfidence.High);
        TSyntaxKind.VarSection:
          for Inner := 0 to Child.ChildCount - 1 do
            if Child[Inner].Kind = TSyntaxKind.VarDecl then
              AReport.Add(Scan.FirstRange(Child[Inner]), 'Interfaces dürfen keine Felder haben (wie E2209).',
                TRuleConfidence.High);
        TSyntaxKind.Visibility:
          AReport.Add(TTextRange.Create(Child.StartPos, Child.EndPos), Format('Die Direktive %s ist in ' +
            'Interfaces nicht erlaubt (wie E2210).', [Child.Name]), TRuleConfidence.High);
        TSyntaxKind.RoutineHeader:
          for Inner := 0 to Child.ChildCount - 1 do
            if (Child[Inner].Kind = TSyntaxKind.Directive) and
              MatchText(Child[Inner].Name, InterfaceForbiddenDirectives) then
              AReport.Add(Scan.FirstRange(Child[Inner]), Format('Die Direktive %s ist in Interfaces nicht erlaubt ' +
                '(wie E2210).', [Child[Inner].Name]), TRuleConfidence.High);
        TSyntaxKind.PropertyDecl:
          CheckPropertyClauses(Child);
      else
        // Übrige Werte bewusst ohne Wirkung.
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
            CheckInterface(Body, Node.Name);
          Body := Node.FindChild(TSyntaxKind.ClassType);
          if Body <> nil then
            CheckClassList(Body);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          if Node[Index].Kind in DeclarationKinds then
            Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
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
    'implements-Klausel unzulässig');
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
      Exit;
    // Eingebaute Typen (Integer, string …) stehen nicht im Index; ein eigener gleichnamiger Typ geht vor.
    if not Scan.Resolver.ResolveTypeFrom(Scan.OwnUnit, Reference.Name, Resolved) or not Resolved.Found then
    begin
      Resolved.Builtin := TNameResolver.IsBuiltinTypeName(Reference.Name);
      if not Resolved.Builtin then
        Exit;
    end;
    if Resolved.Builtin or (Resolved.SymbolKind in [TIndexSymbolKind.RecordType, TIndexSymbolKind.EnumType]) then
      AReport.Add(TTextRange.Create(Reference.StartPos, Reference.EndPos), Format('implements ist nur an ' +
        'Properties mit Klassen- oder Interface-Typ erlaubt, %s ist keiner (wie E2259).', [Reference.Name]),
        TRuleConfidence.High);
  end;

  procedure CheckGetter(AType: TSyntaxNode; AGetter: Integer);
  var
    Header: TSyntaxNode;
    Index: Integer;
    Name: string;
  begin
    Header := UniqueMethodHeader(AType, Scan.Tokens[AGetter].Text);
    if Header = nil then
      Exit;
    for Index := 0 to Header.ChildCount - 1 do
    begin
      if Header[Index].Kind <> TSyntaxKind.Directive then
        Continue;
      Name := Header[Index].Name;
      if MatchText(Name, ForeignConventions) then
        AReport.Add(Scan.TokenRange(AGetter), Format('Der Getter %s einer implements-Property darf nicht %s ' +
          'sein, nur register (wie E2262).', [Scan.Tokens[AGetter].Text, Name]), TRuleConfidence.High)
      else if (Name = 'dynamic') or (Name = 'message') then
        AReport.Add(Scan.TokenRange(AGetter), Format('Der Getter %s einer implements-Property darf nicht %s ' +
          'sein (wie E2263 und E2148).', [Scan.Tokens[AGetter].Text, Name]), TRuleConfidence.High);
    end;
  end;

  procedure CheckClass(AType: TSyntaxNode);
  var
    Index, Clause, Implements, First, Depth, Position, Stop: Integer;
    Child: TSyntaxNode;
    Words: TArray<Integer>;
    Keys, Owners: TArray<string>;
    Key, Prefix: string;
    HasRead: Boolean;
    Seen: Boolean;
  begin
    Keys := nil;
    Owners := nil;
    for Index := 0 to AType.ChildCount - 1 do
    begin
      Child := AType[Index];
      if (Child.Kind <> TSyntaxKind.PropertyDecl) or not Scan.Unconditional(Child) then
        Continue;
      Words := Scan.ClauseWords(Child);
      Implements := -1;
      HasRead := False;
      for Clause in Words do
        if Word(Clause) = 'implements' then
          Implements := Clause
        else if Word(Clause) = 'read' then
          HasRead := True;
      if Implements < 0 then
        Continue;
      if AType.Kind <> TSyntaxKind.ClassType then
      begin
        AReport.Add(Scan.TokenRange(Implements), 'implements ist nur in Klassen erlaubt (wie E2258).',
          TRuleConfidence.High);
        Continue;
      end;
      CheckType(Child);
      for Clause in Words do
        if Word(Clause) = 'index' then
          AReport.Add(Scan.TokenRange(Clause), 'implements ist nicht zusammen mit index erlaubt (wie E2260).',
            TRuleConfidence.High)
        else if (Word(Clause) = 'read') and (Scan.ClauseArgument(Child, Clause) < Scan.ClauseEnd(Child)) and
          (Scan.Tokens[Scan.ClauseArgument(Child, Clause)].Kind = TPascalTokenKind.Identifier) then
          CheckGetter(AType, Scan.ClauseArgument(Child, Clause));
      if not HasRead then
        AReport.Add(Scan.TokenRange(Implements), 'implements braucht eine lesbare Property (wie E2261).',
          TRuleConfidence.High);
      // Interfaces hinter implements, durch Kommas getrennt.
      Stop := Scan.ClauseEnd(Child);
      First := Scan.NextCode(Implements + 1, Stop);
      Depth := 0;
      for Position := First to Stop do
      begin
        if Position < Stop then
        begin
          if Scan.Tokens[Position].IsSymbol('<') then
            Inc(Depth)
          else if Scan.Tokens[Position].IsSymbol('>') then
            Dec(Depth);
          if (Depth > 0) or not Scan.Tokens[Position].IsSymbol(',') then
            Continue;
        end;
        if Position > First then
        begin
          Key := Scan.TypeKey(First, Position);
          Seen := False;
          for Clause := 0 to High(Keys) do
            if Keys[Clause] = Key then
            begin
              AReport.Add(TTextRange.Create(Scan.Tokens[First].StartPos, Scan.Tokens[Position - 1].EndPos),
                Format('%s wird schon von %s per implements umgesetzt (wie E2257).', [Scan.Text(First, Position),
                Owners[Clause]]), TRuleConfidence.High);
              Seen := True;
              Break;
            end;
          if not Seen then
          begin
            Keys := Keys + [Key];
            Owners := Owners + [Child.Name];
          end;
        end;
        First := Scan.NextCode(Position + 1, Stop);
      end;
    end;
    // Methodenzuordnungen (procedure IFoo.Bar = Baz) für Interfaces mit implements-Property.
    for Index := 0 to AType.ChildCount - 1 do
    begin
      Child := AType[Index];
      if (Child.Kind <> TSyntaxKind.RoutineHeader) or (Pos('.', Child.Name) = 0) or
        not Scan.Unconditional(Child) then
        Continue;
      Prefix := UpperCase(Copy(Child.Name, 1, LastDelimiter('.', Child.Name) - 1));
      Prefix := Copy(Prefix, LastDelimiter('.', Prefix) + 1, MaxInt);
      for Clause := 0 to High(Keys) do
        if Keys[Clause] = Prefix then
        begin
          AReport.Add(Scan.TokenRange(Scan.NextCode(Scan.FirstToken(Child) + 1, Scan.StopToken(Child))),
            Format('Für %s gibt es die implements-Property %s; Methodenzuordnungen sind dann nicht erlaubt ' +
            '(wie E2264).', [Copy(Child.Name, 1, LastDelimiter('.', Child.Name) - 1), Owners[Clause]]),
            TRuleConfidence.High);
          Break;
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
          CheckClass(Node);
        for Index := Node.ChildCount - 1 downto 0 do
          if Node[Index].Kind in DeclarationKinds + [TSyntaxKind.RecordType, TSyntaxKind.InterfaceType,
            TSyntaxKind.ObjectType, TSyntaxKind.HelperType] then
            Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
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
    'Aufrufkonvention passt nicht');
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
      if (AHeader[Index].Kind = TSyntaxKind.Directive) and SameText(AHeader[Index].Name, AName) then
        Exit(AHeader[Index]);
  end;

  function Convention(AHeader: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
  begin
    Result := nil;
    for Index := 0 to AHeader.ChildCount - 1 do
      if (AHeader[Index].Kind = TSyntaxKind.Directive) and MatchText(AHeader[Index].Name, ForeignConventions) then
        Exit(AHeader[Index]);
  end;

  function Keyword(AHeader: TSyntaxNode): string;
  var
    Index: Integer;
  begin
    Index := Scan.NextCode(Scan.FirstToken(AHeader), Length(Scan.Tokens));
    Result := '';
    if Index < Length(Scan.Tokens) then
      Result := LowerCase(Scan.Tokens[Index].Text);
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
      Body := Body.FindChild(TSyntaxKind.RoutineHeader);
    if Body <> nil then
    begin
      Other := Directive(Body, AConvention.Name);
      if Other <> nil then
        Edits := Edits + [Scan.DirectiveRemoval(Other)];
    end;
    Result := [TRuleFix.Create(Format('%s entfernen', [AConvention.Name]), Edits)];
  end;

  procedure CheckClass(AType: TSyntaxNode; const AClassName: string);
  var
    Index, Clause, Argument: Integer;
    Child, Header, Found: TSyntaxNode;
    Published: Boolean;
    Kind: string;
  begin
    Published := False;
    for Index := 0 to AType.ChildCount - 1 do
    begin
      Child := AType[Index];
      if Child.Kind = TSyntaxKind.Visibility then
        Published := Child.Name = 'published'
      else if (Child.Kind = TSyntaxKind.RoutineHeader) and Scan.Unconditional(Child) and
        MatchText(Keyword(Child), ['constructor', 'destructor']) then
      begin
        Found := Convention(Child);
        if Found <> nil then
          AReport.Add(Scan.FirstRange(Found), Format('Konstruktoren und Destruktoren brauchen register, nicht %s ' +
            '(wie E2236).', [Found.Name]), TRuleConfidence.High, RemoveFix(AClassName, Child, Found));
      end
      else if (Child.Kind = TSyntaxKind.PropertyDecl) and Published and Scan.Unconditional(Child) then
        for Clause in Scan.ClauseWords(Child) do
        begin
          if not MatchText(Scan.Tokens[Clause].Text, ['read', 'write']) then
            Continue;
          Argument := Scan.ClauseArgument(Child, Clause);
          if (Argument >= Scan.ClauseEnd(Child)) or (Scan.Tokens[Argument].Kind <> TPascalTokenKind.Identifier) then
            Continue;
          Header := UniqueMethodHeader(AType, Scan.Tokens[Argument].Text);
          if Header = nil then
            Continue;
          Found := Convention(Header);
          if Found = nil then
            Continue;
          if SameText(Scan.Tokens[Clause].Text, 'read') then
            Kind := 'Getter'
          else
            Kind := 'Setter';
          AReport.Add(Scan.TokenRange(Argument), Format('Der %s %s der published-Property %s braucht register, ' +
            'nicht %s (wie E2270).', [Kind, Scan.Tokens[Argument].Text, Child.Name, Found.Name]),
            TRuleConfidence.High, RemoveFix(AClassName, Header, Found));
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
    if (Varargs = nil) or (Directive(AHeader, 'cdecl') <> nil) or not Scan.Unconditional(AHeader) then
      Exit;
    if Directive(AHeader, 'external') <> nil then
      Code := 'E2277'
    else
      Code := 'E2591';
    Found := Convention(AHeader);
    if Found = nil then
      Found := Directive(AHeader, 'register');
    if Found <> nil then
      Edit := TTextEdit.Create(Scan.FirstRange(Found), 'cdecl')
    else
    begin
      Position := Scan.FirstRange(Varargs).StartPos;
      Edit := TTextEdit.Create(TTextRange.Create(Position, Position), 'cdecl; ');
    end;
    AReport.Add(Scan.FirstRange(Varargs), Format('varargs ist nur mit cdecl erlaubt (wie %s).', [Code]),
      TRuleConfidence.High, [TRuleFix.Create('cdecl setzen', [Edit])]);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode; const AOwner: string);
  var
    Pending: TStack<TSyntaxNode>;
    PendingOwner: TStack<string>;
    Node: TSyntaxNode;
    Owner: string;
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
        Owner := PendingOwner.Pop;
        Name := Owner;
        if Node.Kind = TSyntaxKind.TypeDecl then
        begin
          if Owner = '' then
            Name := Node.Name
          else
            Name := Owner + '.' + Node.Name;
        end;
        if Node.Kind = TSyntaxKind.ClassType then
          CheckClass(Node, Name);
        if Node.Kind = TSyntaxKind.RoutineHeader then
          CheckVarargs(Node);
        for Index := Node.ChildCount - 1 downto 0 do
          if Node[Index].Kind in DeclarationKinds + [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader,
            TSyntaxKind.RecordType, TSyntaxKind.ObjectType, TSyntaxKind.HelperType] then
          begin
            Pending.Push(Node[Index]);
            PendingOwner.Push(Name);
          end;
      end;
    finally
      PendingOwner.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
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
    'Unzulässige dispinterface-Deklaration');
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
        Inc(mDepth)
      else if Scan.Tokens[Result].IsSymbol(')') then
      begin
        Dec(mDepth);
        if mDepth = 0 then
          Exit;
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
        Exit;
      AReport.Add(TTextRange.Create(Scan.Tokens[mNext].StartPos, Scan.Tokens[mClose].EndPos),
        'Ein dispinterface kann keinen Vorfahren haben (wie E2228).', TRuleConfidence.High,
        [TRuleFix.Create('Vorfahren entfernen', [TTextEdit.Create(TTextRange.Create(Scan.Tokens[AKeyword].EndPos,
          Scan.Tokens[mClose].EndPos), '')])]);
      mHeaderEnd := mClose;
      mNext := Scan.NextCode(mClose + 1, Length(Scan.Tokens));
    end;
    // Kurzform "D = dispinterface(I);" hat keinen Rumpf; dazu ist nichts belegt.
    if (mNext >= Length(Scan.Tokens)) or Scan.Tokens[mNext].IsSymbol('[') or Scan.Tokens[mNext].IsSymbol(';') then
      Exit;
    mIndent := TTextLines.IndentOf(AContext.Text, Scan.Tokens[Scan.FirstToken(ADeclaration)].StartPos.Line);
    AReport.Add(Scan.FirstRange(ADeclaration), Format('Das dispinterface %s braucht eine GUID (wie E2229).',
      [ADeclaration.Name]), TRuleConfidence.High, [TRuleFix.Create('GUID einfügen',
      [TTextEdit.Create(TTextRange.Create(Scan.Tokens[mHeaderEnd].EndPos, Scan.Tokens[mHeaderEnd].EndPos),
        TTextLines.LineBreakOf(AContext.Text) + mIndent + '  ' + GuidLine)])]);
  end;

  procedure CheckMembers(AType: TSyntaxNode);
  var
    mIndex, mInner: Integer;
    mChild: TSyntaxNode;
    mWord: string;
  begin
    for mIndex := 0 to AType.ChildCount - 1 do
    begin
      mChild := AType[mIndex];
      if not Scan.Unconditional(mChild) then
        Continue;
      case mChild.Kind of
        TSyntaxKind.RoutineHeader:
          for mInner := 0 to mChild.ChildCount - 1 do
            if (mChild[mInner].Kind = TSyntaxKind.Directive) and
              MatchText(mChild[mInner].Name, DispForbiddenDirectives) then
              AReport.Add(Scan.FirstRange(mChild[mInner]), Format('Methoden eines dispinterface dürfen keine ' +
                'Direktive %s haben (wie E2230).', [mChild[mInner].Name]), TRuleConfidence.High,
                [TRuleFix.Create(Format('%s entfernen', [mChild[mInner].Name]),
                [Scan.DirectiveRemoval(mChild[mInner])])]);
        TSyntaxKind.PropertyDecl:
          for mInner in Scan.ClauseWords(mChild) do
          begin
            mWord := LowerCase(Scan.Tokens[mInner].Text);
            if (mWord = 'read') or (mWord = 'write') then
              AReport.Add(Scan.TokenRange(mInner), Format('Die Direktive %s ist in einem dispinterface nicht ' +
                'erlaubt (wie E2231).', [mWord]), TRuleConfidence.High);
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode, mBody: TSyntaxNode;
    mIndex, mKeyword: Integer;
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
            mKeyword := Scan.DispKeyword(mBody)
          else
            mKeyword := -1;
          if mKeyword >= 0 then
          begin
            if Scan.Unconditional(mNode) then
              CheckHeader(mNode, mKeyword);
            CheckMembers(mBody);
          end;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
          if mNode[mIndex].Kind in DeclarationKinds then
            mPending.Push(mNode[mIndex]);
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
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

end.
