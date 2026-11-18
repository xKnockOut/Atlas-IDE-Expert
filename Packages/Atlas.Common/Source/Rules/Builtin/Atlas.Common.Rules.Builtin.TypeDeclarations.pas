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
  Atlas.Common.Pascal.TokenCursor,
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
  Atlas.Common.Rules.Builtin.TypeDeclarations.Scan,
  Atlas.Common.Rules.Builtin.TypeDeclarations.Texts;

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

type
  /// <summary>Ein Lauf von TMessageMethodInvalidRule über eine Unit: Kontext, Bericht und der gemeinsame
  /// Zustand der Prüfschritte. Check legt ihn an und ruft Run.</summary>
  TMessageMethodInvalidScan = record
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TArray<TPascalToken>;
    FMethods: TList<TMessageMethod>;
    FPaths: TArray<string>;
    FFileName: string;
    function FirstToken(ANode: TSyntaxNode): Integer;
    procedure AddMethod(AHeader, ADirective: TSyntaxNode; const AClassName: string);
    procedure CollectClass(AClass: TSyntaxNode; const AClassName: string);
    procedure Collect(ARoot: TSyntaxNode; const AOwner: string);
    function NameRange(AHeader: TSyntaxNode): TTextRange;
    function ExpressionText(const AMethod: TMessageMethod): string;
    function MethodName(AHeader: TSyntaxNode): string;
    function SingleParameter(AHeader: TSyntaxNode; out AParam: TSyntaxNode): Boolean;
    function ParameterEdits(AHeader: TSyntaxNode; out AEdits: TArray<TTextEdit>): Boolean;
    function SignatureFix(const AMethod: TMessageMethod): TArray<TRuleFix>;
    procedure CheckParameters(const AMethod: TMessageMethod);
    function PathOf(const AMethod: TMessageMethod): string;
    function EarlierHandler(const AKeys: TArray<string>; const AKnown: TArray<Boolean>; AIndex: Integer): Integer;
    procedure CheckNumber(AValues: TConstantValues; AIndex: Integer; var AKeys: TArray<string>;
      var AKnown: TArray<Boolean>);
    procedure CheckNumbers;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TMessageMethodInvalidScan }

constructor TMessageMethodInvalidScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  FContext := AContext;
  FReport := AReport;
end;

function TMessageMethodInvalidScan.FirstToken(ANode: TSyntaxNode): Integer;
begin
  Result := TokenFrom(FTokens, ANode.StartOffset);
end;

procedure TMessageMethodInvalidScan.AddMethod(AHeader, ADirective: TSyntaxNode; const AClassName: string);
var
  mStop: Integer;
  mMethod: TMessageMethod;
begin
  mMethod := Default(TMessageMethod);
  mMethod.ClassName := AClassName;
  mMethod.Header := AHeader;
  mMethod.Directive := ADirective;
  mStop := TokenFrom(FTokens, ADirective.EndOffset);
  mMethod.First := NextCode(FTokens, FirstToken(ADirective) + 1);
  if mMethod.First > mStop then
  begin
    mMethod.First := mStop;
  end;
  mMethod.Last := mStop - 1;
  while (mMethod.Last >= mMethod.First) and IsTrivia(FTokens[mMethod.Last]) do
  begin
    Dec(mMethod.Last);
  end;
  FMethods.Add(mMethod);
end;

/// <summary>Merkt die message-Methoden der Klasse AClass mit dem Namen AClassName.</summary>
procedure TMessageMethodInvalidScan.CollectClass(AClass: TSyntaxNode; const AClassName: string);
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

// Iterativ (tiefe Bäume sprengen den Stapel nicht).
procedure TMessageMethodInvalidScan.Collect(ARoot: TSyntaxNode; const AOwner: string);
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
function TMessageMethodInvalidScan.NameRange(AHeader: TSyntaxNode): TTextRange;
var
  mIndex, mStop: Integer;
begin
  Result := TTextRange.Create(AHeader.StartPos, AHeader.EndPos);
  mStop := TokenFrom(FTokens, AHeader.EndOffset);
  for mIndex := FirstToken(AHeader) to mStop - 1 do
  begin
    if FTokens[mIndex].Kind = TPascalTokenKind.Identifier then
    begin
      Exit(TTextRange.Create(FTokens[mIndex].StartPos, FTokens[mIndex].EndPos));
    end;
  end;
end;

function TMessageMethodInvalidScan.ExpressionText(const AMethod: TMessageMethod): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := AMethod.First to AMethod.Last do
  begin
    if not IsTrivia(FTokens[mIndex]) then
    begin
      if (Result <> '') and (FTokens[mIndex - 1].Offset + Length(FTokens[mIndex -
        1].Text) <> FTokens[mIndex].Offset) then
      begin
        Result := Result + ' ';
      end;
      Result := Result + FTokens[mIndex].Text;
    end;
  end;
end;

function TMessageMethodInvalidScan.MethodName(AHeader: TSyntaxNode): string;
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
function TMessageMethodInvalidScan.SingleParameter(AHeader: TSyntaxNode; out AParam: TSyntaxNode): Boolean;
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

function TMessageMethodInvalidScan.ParameterEdits(AHeader: TSyntaxNode; out AEdits: TArray<TTextEdit>): Boolean;
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
      AEdits := [TTextEdit.Create(TTextRange.Create(FTokens[mIndex].StartPos, FTokens[mIndex].StartPos), 'var ')];
    end
    else
    begin
      AEdits := [TTextEdit.Create(TTextRange.Create(FTokens[mIndex].StartPos, FTokens[mIndex].EndPos), 'var')];
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

function TMessageMethodInvalidScan.SignatureFix(const AMethod: TMessageMethod): TArray<TRuleFix>;
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
  mDecl := MethodBody(FContext.Tree, AMethod.ClassName, MethodName(AMethod.Header));
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

procedure TMessageMethodInvalidScan.CheckParameters(const AMethod: TMessageMethod);
var
  mParams: TSyntaxNode;
  mKeyword: string;
  mIndex: Integer;
begin
  // Nur Prozeduren: message an Funktionen ist ein anderer Fall.
  mIndex := NextCode(FTokens, FirstToken(AMethod.Header));
  if (mIndex < Length(FTokens)) and FTokens[mIndex].IsKeyword('class') then
  begin
    Exit;
  end;
  if mIndex >= Length(FTokens) then
  begin
    Exit;
  end;
  mKeyword := LowerCase(FTokens[mIndex].Text);
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
  FReport.Add(NameRange(AMethod.Header), cTexts[TTypeDeclarationsText.MessageParam].Fmt([MethodName(AMethod.Header)]),
    TRuleConfidence.High, SignatureFix(AMethod));
end;

function TMessageMethodInvalidScan.PathOf(const AMethod: TMessageMethod): string;
begin
  Result := TConditionalBranches.PathAt(FPaths, FirstToken(AMethod.Header));
end;

/// <summary>Behandelt eine frühere message-Methode derselben Klasse in derselben Bedingungsvariante die
/// Nummer mit dem Schlüssel AKeys[AIndex]? Index der früheren, -1 ohne.</summary>
function TMessageMethodInvalidScan.EarlierHandler(const AKeys: TArray<string>; const AKnown: TArray<Boolean>;
  AIndex: Integer): Integer;
var
  mEarlier: Integer;
begin
  for mEarlier := 0 to AIndex - 1 do
  begin
    if AKnown[mEarlier] and SameText(FMethods[mEarlier].ClassName, FMethods[AIndex].ClassName) and
      (AKeys[mEarlier] = AKeys[AIndex]) and
      not TConditionalBranches.Exclusive(PathOf(FMethods[mEarlier]), PathOf(FMethods[AIndex])) then
    begin
      Exit(mEarlier);
    end;
  end;
  Result := -1;
end;

/// <summary>Prüft die Nummer der Methode AIndex (E2139, E2140) und merkt ihren Schlüssel.</summary>
procedure TMessageMethodInvalidScan.CheckNumber(AValues: TConstantValues; AIndex: Integer; var AKeys: TArray<string>;
  var AKnown: TArray<Boolean>);
var
  mValue: Int64;
  mMethod: TMessageMethod;
  mRange: TTextRange;
  mEarlier: Integer;
begin
  mMethod := FMethods[AIndex];
  mRange := TTextRange.Create(FTokens[mMethod.First].StartPos, FTokens[mMethod.Last].EndPos);
  if not AValues.Evaluate(mMethod.First, mMethod.Last, mValue) then
  begin
    AKeys[AIndex] := 't' + UpperCase(ExpressionText(mMethod).Replace(' ', ''));
  end
  else if mValue < 1 then
  begin
    FReport.Add(mRange, cTexts[TTypeDeclarationsText.MessageNumber].Fmt(
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
    FReport.Add(mRange, cTexts[TTypeDeclarationsText.MessageHandled].Fmt([ExpressionText(mMethod),
      MethodName(FMethods[mEarlier].Header)]), TRuleConfidence.High);
  end;
end;

procedure TMessageMethodInvalidScan.CheckNumbers;
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mValues: TConstantValues;
  mKeys: TArray<string>;
  mKnown: TArray<Boolean>;
  mIndex: Integer;
begin
  SetLength(mKeys, FMethods.Count);
  SetLength(mKnown, FMethods.Count);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(FContext);
  mResolver := TRuleDerived.Resolver(mCache, FContext);
  try
    mResolver.PinTree(FContext.Tree, FFileName);
    mValues := TConstantValues.Create(FContext.Tree, FFileName, FContext.Index, mResolver);
    try
      for mIndex := 0 to FMethods.Count - 1 do
      begin
        if FMethods[mIndex].First <= FMethods[mIndex].Last then
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

procedure TMessageMethodInvalidScan.Run;
var
  mMethod: TMessageMethod;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FTokens := FContext.Tree.Tokens;
  FFileName := FContext.ResolverFileName;
  FMethods := TList<TMessageMethod>.Create;
  try
    Collect(FContext.Tree.Root, '');
    if FMethods.Count = 0 then
    begin
      Exit;
    end;
    FPaths := TConditionalBranches.Paths(FTokens);
    for mMethod in FMethods do
    begin
      CheckParameters(mMethod);
    end;
    CheckNumbers;
  finally
    FMethods.Free;
  end;
end;

procedure TMessageMethodInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TMessageMethodInvalidScan;
begin
  mScan := TMessageMethodInvalidScan.Create(AContext, AReport);
  mScan.Run;
end;

{ TInterfaceDeclarationInvalidRule }

function TInterfaceDeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cInterfaceDeclarationInvalidRuleId, TRuleSeverity.Error,
    cTexts[TTypeDeclarationsText.InterfaceTitle].Text);
end;

type
  /// <summary>Ein Lauf von TInterfaceDeclarationInvalidRule über eine Unit: Kontext, Bericht und der gemeinsame
  /// Zustand der Prüfschritte. Check legt ihn an und ruft Run.</summary>
  TInterfaceDeclarationInvalidScan = record
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FScan: TDeclarationScan;
    function NotAnInterface(ANode: TSyntaxNode; out AKind: string): Boolean;
    procedure ReportNotInterface(ANode: TSyntaxNode);
    procedure CheckClassList(AClass: TSyntaxNode);
    procedure CheckPropertyClauses(AProperty: TSyntaxNode);
    function WithoutType(AProperty: TSyntaxNode): Boolean;
    procedure CheckInheritedMembers(AType: TSyntaxNode; const AName: string);
    procedure ReportVarSection(ASection: TSyntaxNode);
    procedure ReportForbiddenDirectives(AHeader: TSyntaxNode);
    procedure CheckInterfaceMember(AChild: TSyntaxNode);
    procedure CheckInterface(AType: TSyntaxNode; const AName: string);
    procedure Visit(ARoot: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TInterfaceDeclarationInvalidScan }

constructor TInterfaceDeclarationInvalidScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  FContext := AContext;
  FReport := AReport;
end;

/// <summary>Löst ANode (TypeReference) sicher zu einer Klasse, einem Record oder einer Aufzählung auf?</summary>
function TInterfaceDeclarationInvalidScan.NotAnInterface(ANode: TSyntaxNode; out AKind: string): Boolean;
var
  mResolved: TResolvedSymbol;
begin
  AKind := '';
  Result := (ANode.Name <> '') and FScan.Resolver.ResolveTypeFrom(FScan.OwnUnit, ANode.Name, mResolved) and
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

procedure TInterfaceDeclarationInvalidScan.ReportNotInterface(ANode: TSyntaxNode);
var
  mKind: string;
begin
  if FScan.Unconditional(ANode) and NotAnInterface(ANode, mKind) then
  begin
    FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
      cTexts[TTypeDeclarationsText.NotInterface].Fmt([ANode.Name, mKind]), TRuleConfidence.High);
  end;
end;

procedure TInterfaceDeclarationInvalidScan.CheckClassList(AClass: TSyntaxNode);
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
      if (FScan.TypeKey(mReferences[mEarlier]) = FScan.TypeKey(mReferences[mPosition])) and
        FScan.Unconditional(mReferences[mPosition]) then
      begin
        FReport.Add(TTextRange.Create(mReferences[mPosition].StartPos, mReferences[mPosition].EndPos),
          cTexts[TTypeDeclarationsText.AlreadyListed].Fmt([mReferences[mPosition].Name]),
          TRuleConfidence.High);
        Break;
      end;
    end;
  end;
end;

/// <summary>Klauseln stored, nodefault und default mit Wert vor dem ersten Semikolon der Property.</summary>
procedure TInterfaceDeclarationInvalidScan.CheckPropertyClauses(AProperty: TSyntaxNode);
var
  mIndex: Integer;
  mWord: string;
begin
  for mIndex in FScan.ClauseWords(AProperty) do
  begin
    mWord := LowerCase(FScan.Tokens[mIndex].Text);
    if (mWord = 'stored') or (mWord = 'nodefault') or
      ((mWord = 'default') and (FScan.ClauseArgument(AProperty, mIndex) < FScan.ClauseEnd(AProperty))) then
    begin
      FReport.Add(FScan.TokenRange(mIndex), cTexts[TTypeDeclarationsText.ClauseNotAllowed].Fmt(
        [mWord]), TRuleConfidence.High);
    end;
  end;
end;

/// <summary>Property ohne eigenen Typ (property Name; bzw. property Name read …), die eine geerbte
/// Property nur neu aufführt. Interfaces erlauben das nicht (E2206); eine Neudeklaration mit Typ ist eine
/// neue Property und übersetzt (#1328).</summary>
function TInterfaceDeclarationInvalidScan.WithoutType(AProperty: TSyntaxNode): Boolean;
var
  mIndex, mStop: Integer;
begin
  mStop := FScan.StopToken(AProperty);
  mIndex := FScan.PropertyNameToken(AProperty);
  Result := mIndex < mStop;
  if Result then
  begin
    mIndex := NextCode(FScan.Tokens, mIndex + 1, mStop);
    Result := (mIndex >= mStop) or not MatchText(FScan.Tokens[mIndex].Text, [':', '[']);
  end;
end;

// Geerbte Accessoren (property X read GetX mit GetX aus dem Vorfahr-Interface) übersetzt dcc, generisch wie
// nicht generisch (DUnitX IList<T>; ID1, ID2, ID3, #1328): Deshalb gibt es keine Prüfung auf
// E2370.
procedure TInterfaceDeclarationInvalidScan.CheckInheritedMembers(AType: TSyntaxNode; const AName: string);
var
  mOwn, mAncestor, mMember: TResolvedSymbol;
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  if not FScan.Resolver.ResolveTypeFrom(FScan.OwnUnit, AName, mOwn) or not mOwn.Found or
    (mOwn.SymbolKind <> TIndexSymbolKind.InterfaceType) or not FScan.Resolver.AncestorOf(mOwn, mAncestor) then
  begin
    Exit;
  end;
  for mIndex := 0 to AType.ChildCount - 1 do
  begin
    mChild := AType[mIndex];
    if (mChild.Kind <> TSyntaxKind.PropertyDecl) or not FScan.Unconditional(mChild) then
    begin
      Continue;
    end;
    if WithoutType(mChild) and FScan.Resolver.DeclaredMember(mAncestor, mChild.Name, mMember) and
      (mMember.SymbolKind = TIndexSymbolKind.Property_) then
    begin
      FReport.Add(FScan.PropertyRange(mChild), cTexts[TTypeDeclarationsText.PropertyRedeclared].Fmt([mChild.Name,
        mMember.Container]), TRuleConfidence.High);
    end;
  end;
end;

procedure TInterfaceDeclarationInvalidScan.ReportVarSection(ASection: TSyntaxNode);
var
  mInner: Integer;
begin
  for mInner := 0 to ASection.ChildCount - 1 do
  begin
    if ASection[mInner].Kind = TSyntaxKind.VarDecl then
    begin
      FReport.Add(FScan.FirstRange(ASection[mInner]), cTexts[TTypeDeclarationsText.NoFields].Text,
        TRuleConfidence.High);
    end;
  end;
end;

procedure TInterfaceDeclarationInvalidScan.ReportForbiddenDirectives(AHeader: TSyntaxNode);
var
  mInner: Integer;
begin
  for mInner := 0 to AHeader.ChildCount - 1 do
  begin
    if (AHeader[mInner].Kind = TSyntaxKind.Directive) and
      MatchText(AHeader[mInner].Name, cInterfaceForbiddenDirectives) then
    begin
      FReport.Add(FScan.FirstRange(AHeader[mInner]),
        cTexts[TTypeDeclarationsText.DirectiveNotAllowed].Fmt([AHeader[mInner].Name]), TRuleConfidence.High);
    end;
  end;
end;

procedure TInterfaceDeclarationInvalidScan.CheckInterfaceMember(AChild: TSyntaxNode);
begin
  case AChild.Kind of
    TSyntaxKind.Field:
      FReport.Add(FScan.FirstRange(AChild), cTexts[TTypeDeclarationsText.NoFields].Text, TRuleConfidence.High);
    TSyntaxKind.VarSection:
      ReportVarSection(AChild);
    TSyntaxKind.Visibility:
      FReport.Add(TTextRange.Create(AChild.StartPos, AChild.EndPos),
        cTexts[TTypeDeclarationsText.DirectiveNotAllowed].Fmt([AChild.Name]), TRuleConfidence.High);
    TSyntaxKind.RoutineHeader:
      ReportForbiddenDirectives(AChild);
    TSyntaxKind.PropertyDecl:
      CheckPropertyClauses(AChild);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TInterfaceDeclarationInvalidScan.CheckInterface(AType: TSyntaxNode; const AName: string);
var
  mIndex: Integer;
begin
  // dispinterface prüft dispinterface-invalid.
  if FScan.DispKeyword(AType) >= 0 then
  begin
    Exit;
  end;
  if (AType.ChildCount > 0) and (AType[0].Kind = TSyntaxKind.TypeReference) then
  begin
    ReportNotInterface(AType[0]);
  end;
  for mIndex := 0 to AType.ChildCount - 1 do
  begin
    if FScan.Unconditional(AType[mIndex]) then
    begin
      CheckInterfaceMember(AType[mIndex]);
    end;
  end;
  CheckInheritedMembers(AType, AName);
end;

// Iterativ (tiefe Bäume sprengen den Stapel nicht).
procedure TInterfaceDeclarationInvalidScan.Visit(ARoot: TSyntaxNode);
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

procedure TInterfaceDeclarationInvalidScan.Run;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FScan := TDeclarationScan.Create(FContext);
  try
    Visit(FContext.Tree.Root);
  finally
    FScan.Free;
  end;
end;

procedure TInterfaceDeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TInterfaceDeclarationInvalidScan;
begin
  mScan := TInterfaceDeclarationInvalidScan.Create(AContext, AReport);
  mScan.Run;
end;

{ TImplementsClauseInvalidRule }

function TImplementsClauseInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cImplementsClauseInvalidRuleId, TRuleSeverity.Error,
    cTexts[TTypeDeclarationsText.ImplementsTitle].Text);
end;

type
  /// <summary>Ein Lauf von TImplementsClauseInvalidRule über eine Unit: Kontext, Bericht und der gemeinsame
  /// Zustand der Prüfschritte. Check legt ihn an und ruft Run.</summary>
  TImplementsClauseInvalidScan = record
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FScan: TDeclarationScan;
    function Word(AIndex: Integer): string;
    procedure CheckType(AProperty: TSyntaxNode);
    procedure CheckGetter(AType: TSyntaxNode; AGetter: Integer);
    function ImplementsWord(const AWords: TArray<Integer>; out AHasRead: Boolean): Integer;
    procedure CheckClauses(AType, AProperty: TSyntaxNode; const AWords: TArray<Integer>);
    function EndsInterface(APosition, AStop: Integer; var ADepth: Integer): Boolean;
    procedure AddInterface(AFirst, AStop: Integer; const AOwner: string; var AKeys, AOwners: TArray<string>);
    procedure CollectInterfaces(AProperty: TSyntaxNode; AImplements: Integer; var AKeys, AOwners: TArray<string>);
    procedure CheckProperty(AType, AProperty: TSyntaxNode; var AKeys, AOwners: TArray<string>);
    procedure CheckResolution(AHeader: TSyntaxNode; const AKeys, AOwners: TArray<string>);
    procedure CheckClass(AType: TSyntaxNode);
    procedure Visit(ARoot: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TImplementsClauseInvalidScan }

constructor TImplementsClauseInvalidScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  FContext := AContext;
  FReport := AReport;
end;

function TImplementsClauseInvalidScan.Word(AIndex: Integer): string;
begin
  Result := LowerCase(FScan.Tokens[AIndex].Text);
end;

procedure TImplementsClauseInvalidScan.CheckType(AProperty: TSyntaxNode);
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
  if not FScan.Resolver.ResolveTypeFrom(FScan.OwnUnit, mReference.Name, mResolved) or not mResolved.Found then
  begin
    mResolved.Builtin := TResolverText.IsBuiltinTypeName(mReference.Name);
    if not mResolved.Builtin then
    begin
      Exit;
    end;
  end;
  if mResolved.Builtin or (mResolved.SymbolKind in [TIndexSymbolKind.RecordType, TIndexSymbolKind.EnumType]) then
  begin
    FReport.Add(TTextRange.Create(mReference.StartPos, mReference.EndPos),
      cTexts[TTypeDeclarationsText.ImplementsType].Fmt([mReference.Name]),
      TRuleConfidence.High);
  end;
end;

procedure TImplementsClauseInvalidScan.CheckGetter(AType: TSyntaxNode; AGetter: Integer);
var
  mHeader: TSyntaxNode;
  mIndex: Integer;
  mName: string;
begin
  mHeader := UniqueMethodHeader(AType, FScan.Tokens[AGetter].Text);
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
      FReport.Add(FScan.TokenRange(AGetter),
        cTexts[TTypeDeclarationsText.GetterRegister].Fmt([FScan.Tokens[AGetter].Text, mName]), TRuleConfidence.High);
    end
    else if (mName = 'dynamic') or (mName = 'message') then
    begin
      FReport.Add(FScan.TokenRange(AGetter), cTexts[TTypeDeclarationsText.GetterNot].Fmt([FScan.Tokens[AGetter].Text,
        mName]), TRuleConfidence.High);
    end;
  end;
end;

/// <summary>Token des Worts implements unter den Klauselwörtern AWords, -1 ohne; AHasRead bei read.</summary>
function TImplementsClauseInvalidScan.ImplementsWord(const AWords: TArray<Integer>; out AHasRead: Boolean): Integer;
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
procedure TImplementsClauseInvalidScan.CheckClauses(AType, AProperty: TSyntaxNode; const AWords: TArray<Integer>);
var
  mClause, mArgument: Integer;
begin
  for mClause in AWords do
  begin
    mArgument := FScan.ClauseArgument(AProperty, mClause);
    if Word(mClause) = 'index' then
    begin
      FReport.Add(FScan.TokenRange(mClause), cTexts[TTypeDeclarationsText.ImplementsIndex].Text,
        TRuleConfidence.High);
    end
    else if (Word(mClause) = 'read') and (mArgument < FScan.ClauseEnd(AProperty)) and
      (FScan.Tokens[mArgument].Kind = TPascalTokenKind.Identifier) then
    begin
      CheckGetter(AType, mArgument);
    end;
  end;
end;

/// <summary>Endet an APosition ein Interface hinter implements (Komma auf Ebene 0 oder Ende AStop)?</summary>
function TImplementsClauseInvalidScan.EndsInterface(APosition, AStop: Integer; var ADepth: Integer): Boolean;
begin
  if APosition >= AStop then
  begin
    Exit(True);
  end;
  if FScan.Tokens[APosition].IsSymbol('<') then
  begin
    Inc(ADepth);
  end
  else if FScan.Tokens[APosition].IsSymbol('>') then
  begin
    Dec(ADepth);
  end;
  Result := (ADepth = 0) and FScan.Tokens[APosition].IsSymbol(',');
end;

/// <summary>Merkt das Interface zwischen AFirst und AStop als von AOwner umgesetzt; doppelt: E2257.</summary>
procedure TImplementsClauseInvalidScan.AddInterface(AFirst, AStop: Integer; const AOwner: string; var AKeys,
  AOwners: TArray<string>);
var
  mKey: string;
  mClause: Integer;
begin
  mKey := FScan.TypeKey(AFirst, AStop);
  for mClause := 0 to High(AKeys) do
  begin
    if AKeys[mClause] = mKey then
    begin
      FReport.Add(TTextRange.Create(FScan.Tokens[AFirst].StartPos, FScan.Tokens[AStop - 1].EndPos),
        cTexts[TTypeDeclarationsText.AlreadyImplemented].Fmt([FScan.Text(AFirst, AStop),
        AOwners[mClause]]), TRuleConfidence.High);
      Exit;
    end;
  end;
  AKeys := AKeys + [mKey];
  AOwners := AOwners + [AOwner];
end;

// Interfaces hinter implements, durch Kommas getrennt.
procedure TImplementsClauseInvalidScan.CollectInterfaces(AProperty: TSyntaxNode; AImplements: Integer; var AKeys,
  AOwners: TArray<string>);
var
  mFirst, mDepth, mPosition, mStop: Integer;
begin
  mStop := FScan.ClauseEnd(AProperty);
  mFirst := NextCode(FScan.Tokens, AImplements + 1, mStop);
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
    mFirst := NextCode(FScan.Tokens, mPosition + 1, mStop);
  end;
end;

procedure TImplementsClauseInvalidScan.CheckProperty(AType, AProperty: TSyntaxNode; var AKeys, AOwners: TArray<string>);
var
  mWords: TArray<Integer>;
  mImplements: Integer;
  mHasRead: Boolean;
begin
  mWords := FScan.ClauseWords(AProperty);
  mImplements := ImplementsWord(mWords, mHasRead);
  if mImplements < 0 then
  begin
    Exit;
  end;
  if AType.Kind <> TSyntaxKind.ClassType then
  begin
    FReport.Add(FScan.TokenRange(mImplements), cTexts[TTypeDeclarationsText.ImplementsClassOnly].Text,
      TRuleConfidence.High);
    Exit;
  end;
  CheckType(AProperty);
  CheckClauses(AType, AProperty, mWords);
  if not mHasRead then
  begin
    FReport.Add(FScan.TokenRange(mImplements), cTexts[TTypeDeclarationsText.ImplementsReadable].Text,
      TRuleConfidence.High);
  end;
  CollectInterfaces(AProperty, mImplements, AKeys, AOwners);
end;

// Methodenzuordnung (procedure IFoo.Bar = Baz) für ein Interface mit implements-Property: E2264.
procedure TImplementsClauseInvalidScan.CheckResolution(AHeader: TSyntaxNode; const AKeys, AOwners: TArray<string>);
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
      FReport.Add(FScan.TokenRange(NextCode(FScan.Tokens, FScan.FirstToken(AHeader) + 1, FScan.StopToken(AHeader))),
        cTexts[TTypeDeclarationsText.MethodResolution].Fmt([Copy(AHeader.Name, 1, LastDelimiter('.',
          AHeader.Name) - 1), AOwners[mClause]]),
        TRuleConfidence.High);
      Exit;
    end;
  end;
end;

procedure TImplementsClauseInvalidScan.CheckClass(AType: TSyntaxNode);
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
    if (mChild.Kind = TSyntaxKind.PropertyDecl) and FScan.Unconditional(mChild) then
    begin
      CheckProperty(AType, mChild, mKeys, mOwners);
    end;
  end;
  for mIndex := 0 to AType.ChildCount - 1 do
  begin
    mChild := AType[mIndex];
    if (mChild.Kind = TSyntaxKind.RoutineHeader) and (Pos('.', mChild.Name) > 0) and FScan.Unconditional(mChild) then
    begin
      CheckResolution(mChild, mKeys, mOwners);
    end;
  end;
end;

// Iterativ (tiefe Bäume sprengen den Stapel nicht).
procedure TImplementsClauseInvalidScan.Visit(ARoot: TSyntaxNode);
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

procedure TImplementsClauseInvalidScan.Run;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FScan := TDeclarationScan.Create(FContext);
  try
    Visit(FContext.Tree.Root);
  finally
    FScan.Free;
  end;
end;

procedure TImplementsClauseInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TImplementsClauseInvalidScan;
begin
  mScan := TImplementsClauseInvalidScan.Create(AContext, AReport);
  mScan.Run;
end;

{ TCallingConventionRequiredRule }

function TCallingConventionRequiredRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cCallingConventionRequiredRuleId, TRuleSeverity.Error,
    cTexts[TTypeDeclarationsText.ConventionTitle].Text);
end;

type
  /// <summary>Ein Lauf von TCallingConventionRequiredRule über eine Unit: Kontext, Bericht und der gemeinsame
  /// Zustand der Prüfschritte. Check legt ihn an und ruft Run.</summary>
  TCallingConventionRequiredScan = record
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FScan: TDeclarationScan;
    function Directive(AHeader: TSyntaxNode; const AName: string): TSyntaxNode;
    function Convention(AHeader: TSyntaxNode): TSyntaxNode;
    function Keyword(AHeader: TSyntaxNode): string;
    function RemoveFix(const AClassName: string; AHeader, AConvention: TSyntaxNode): TArray<TRuleFix>;
    procedure CheckConstructor(AHeader: TSyntaxNode; const AClassName: string);
    function AccessorHeader(AType, AProperty: TSyntaxNode; AClause: Integer; out AArgument: Integer): TSyntaxNode;
    procedure CheckPublishedProperty(AType, AProperty: TSyntaxNode; const AClassName: string);
    procedure CheckClass(AType: TSyntaxNode; const AClassName: string);
    procedure CheckVarargs(AHeader: TSyntaxNode);
    procedure Visit(ARoot: TSyntaxNode; const AOwner: string);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TCallingConventionRequiredScan }

constructor TCallingConventionRequiredScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  FContext := AContext;
  FReport := AReport;
end;

function TCallingConventionRequiredScan.Directive(AHeader: TSyntaxNode; const AName: string): TSyntaxNode;
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

function TCallingConventionRequiredScan.Convention(AHeader: TSyntaxNode): TSyntaxNode;
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

function TCallingConventionRequiredScan.Keyword(AHeader: TSyntaxNode): string;
var
  mIndex: Integer;
begin
  mIndex := NextCode(FScan.Tokens, FScan.FirstToken(AHeader));
  Result := '';
  if mIndex < Length(FScan.Tokens) then
  begin
    Result := LowerCase(FScan.Tokens[mIndex].Text);
  end;
end;

/// <summary>Korrektur: Konvention an AHeader und am Rumpf der Datei entfernen.</summary>
function TCallingConventionRequiredScan.RemoveFix(const AClassName: string; AHeader,
  AConvention: TSyntaxNode): TArray<TRuleFix>;
var
  mEdits: TArray<TTextEdit>;
  mBody, mOther: TSyntaxNode;
begin
  mEdits := [FScan.DirectiveRemoval(AConvention)];
  mBody := MethodBody(FContext.Tree, AClassName, AHeader.Name);
  if mBody <> nil then
  begin
    mBody := mBody.FindChild(TSyntaxKind.RoutineHeader);
  end;
  if mBody <> nil then
  begin
    mOther := Directive(mBody, AConvention.Name);
    if mOther <> nil then
    begin
      mEdits := mEdits + [FScan.DirectiveRemoval(mOther)];
    end;
  end;
  Result := [TRuleFix.Create(cTexts[TTypeDeclarationsText.RemoveName].Fmt([AConvention.Name]), mEdits)];
end;

// Konstruktoren und Destruktoren mit fremder Konvention: E2236.
procedure TCallingConventionRequiredScan.CheckConstructor(AHeader: TSyntaxNode; const AClassName: string);
var
  mFound: TSyntaxNode;
begin
  mFound := Convention(AHeader);
  if mFound <> nil then
  begin
    FReport.Add(FScan.FirstRange(mFound), cTexts[TTypeDeclarationsText.CtorRegister].Fmt([mFound.Name]),
      TRuleConfidence.High, RemoveFix(AClassName, AHeader, mFound));
  end;
end;

/// <summary>Methodenkopf hinter der Klausel read/write AClause einer Property von AType, nil ohne.</summary>
function TCallingConventionRequiredScan.AccessorHeader(AType, AProperty: TSyntaxNode; AClause: Integer;
  out AArgument: Integer): TSyntaxNode;
begin
  Result := nil;
  AArgument := FScan.ClauseArgument(AProperty, AClause);
  if MatchText(FScan.Tokens[AClause].Text, ['read', 'write']) and (AArgument < FScan.ClauseEnd(AProperty)) and
    (FScan.Tokens[AArgument].Kind = TPascalTokenKind.Identifier) then
  begin
    Result := UniqueMethodHeader(AType, FScan.Tokens[AArgument].Text);
  end;
end;

// Getter und Setter einer published-Property mit fremder Konvention: E2270.
procedure TCallingConventionRequiredScan.CheckPublishedProperty(AType, AProperty: TSyntaxNode;
  const AClassName: string);
var
  mClause, mArgument: Integer;
  mHeader, mFound: TSyntaxNode;
  mKind: string;
begin
  for mClause in FScan.ClauseWords(AProperty) do
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
    if SameText(FScan.Tokens[mClause].Text, 'read') then
    begin
      mKind := 'Getter';
    end;
    FReport.Add(FScan.TokenRange(mArgument), cTexts[TTypeDeclarationsText.PublishedRegister].Fmt([mKind,
      FScan.Tokens[mArgument].Text, AProperty.Name, mFound.Name]),
      TRuleConfidence.High, RemoveFix(AClassName, mHeader, mFound));
  end;
end;

procedure TCallingConventionRequiredScan.CheckClass(AType: TSyntaxNode; const AClassName: string);
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
    else if not FScan.Unconditional(mChild) then
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

procedure TCallingConventionRequiredScan.CheckVarargs(AHeader: TSyntaxNode);
var
  mVarargs, mFound: TSyntaxNode;
  mCode: string;
  mEdit: TTextEdit;
  mPosition: TTextPosition;
begin
  mVarargs := Directive(AHeader, 'varargs');
  if (mVarargs = nil) or not FScan.Unconditional(AHeader) then
  begin
    Exit;
  end;
  // Ohne external: dcc meldet E2277 unter Win32 auch mit cdecl; Win64 übersetzt es (Cm.E2277, #1380).
  if Directive(AHeader, 'external') = nil then
  begin
    if FContext.Tree.Platform = 'Win32' then
    begin
      FReport.Add(FScan.FirstRange(mVarargs), cTexts[TTypeDeclarationsText.VarargsWin32].Text, TRuleConfidence.High);
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
    mEdit := TTextEdit.Create(FScan.FirstRange(mFound), 'cdecl');
  end
  else
  begin
    mPosition := FScan.FirstRange(mVarargs).StartPos;
    mEdit := TTextEdit.Create(TTextRange.Create(mPosition, mPosition), 'cdecl; ');
  end;
  FReport.Add(FScan.FirstRange(mVarargs), cTexts[TTypeDeclarationsText.VarargsCdecl].Fmt([mCode]),
    TRuleConfidence.High, [TRuleFix.Create(cTexts[TTypeDeclarationsText.SetCdecl].Text, [mEdit])]);
end;

// Iterativ (tiefe Bäume sprengen den Stapel nicht).
procedure TCallingConventionRequiredScan.Visit(ARoot: TSyntaxNode; const AOwner: string);
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

procedure TCallingConventionRequiredScan.Run;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FScan := TDeclarationScan.Create(FContext);
  try
    Visit(FContext.Tree.Root, '');
  finally
    FScan.Free;
  end;
end;

procedure TCallingConventionRequiredRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TCallingConventionRequiredScan;
begin
  mScan := TCallingConventionRequiredScan.Create(AContext, AReport);
  mScan.Run;
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

  /// <summary>Vorfahr in Klammern (E2228) und fehlende GUID (E2229). AKeyword ist das Token dispinterface.</summary>
  procedure CheckHeader(ADeclaration: TSyntaxNode; AKeyword: Integer);
  var
    mHeaderEnd, mNext, mClose: Integer;
    mIndent: string;
  begin
    mHeaderEnd := AKeyword;
    mNext := NextCode(mScan.Tokens, AKeyword + 1);
    if (mNext < Length(mScan.Tokens)) and mScan.Tokens[mNext].IsSymbol('(') then
    begin
      mClose := MatchingParen(mScan.Tokens, mNext);
      if mClose < 0 then
      begin
        Exit;
      end;
      AReport.Add(TTextRange.Create(mScan.Tokens[mNext].StartPos, mScan.Tokens[mClose].EndPos),
        cTexts[TTypeDeclarationsText.DispAncestor].Text, TRuleConfidence.High,
        [TRuleFix.Create(cTexts[TTypeDeclarationsText.RemoveAncestor].Text,
          [TTextEdit.Create(TTextRange.Create(mScan.Tokens[AKeyword].EndPos,
          mScan.Tokens[mClose].EndPos), '')])]);
      mHeaderEnd := mClose;
      mNext := NextCode(mScan.Tokens, mClose + 1);
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

  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
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

end.
