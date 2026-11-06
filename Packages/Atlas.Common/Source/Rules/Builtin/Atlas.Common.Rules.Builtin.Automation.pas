unit Atlas.Common.Rules.Builtin.Automation;

// Regel zur OLE-Automation (#1373, Gruppe Compiler vorab):
//   automation-invalid
//                     Abschnitt automated einer Klasse: Felder (wie E2175),
//                     Konstruktoren und Destruktoren (wie E2177), dynamic und
//                     message (wie E2178), andere Aufrufkonventionen als
//                     register (wie E2179), dieselbe dispid zweimal in einer
//                     Klasse (wie E2180), Neudeklaration einer Property ohne
//                     Typ (wie E2181), index, stored, default und nodefault an
//                     Properties (wie E2182), read bzw. write auf ein Feld der
//                     Klasse (wie E2096), dispid an einer override-Methode
//                     (wie E2185) sowie Records, Zeiger und Mengen als Typ von
//                     Parametern, Ergebnissen und Properties (wie E2176).
//                     dispid an einer Methode außerhalb von automated meldet
//                     Delphi 13 als E2185 (nicht E2183, Fall Cm.E2183).
//                     Aufrufe über Variant bzw. OleVariant (V.Machen(...),
//                     auch V.Dokument.Oeffnen(...)): ein Record (ohne
//                     Operatoren) oder ein Zeiger als Argument (wie E2160 bei
//                     OleVariant, wie E2281 bei Variant) und ein unbenanntes
//                     Argument nach einem benannten (wie E2166).
//                     Mitglieder in bedingten Zweigen bleiben still; Typen,
//                     die die Namensauflösung nicht sicher kennt, ebenso.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  AutomationInvalidRuleId = 'automation-invalid';

type
  TAutomationInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterAutomationRules(const ARegistry: TRuleRegistry);

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
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TAutomationText = (TypeNotAllowed, DispidTaken, NoCtorDtor, DirectiveNotAllowed, OnlyRegister, OverrideDispid,
    AccessorField, PropertyDirective, RedeclareNoType, DispidOutside, NoFields, NamedOrder, DispatchType, Title,
    OleCall, DispatchCall);

const
  cTexts: array[TAutomationText] of TAtlasText = (
    (De: 'Der Typ %s ist im Abschnitt automated nicht erlaubt (wie E2176).';
     En: 'The type %s is not allowed in the automated section (like E2176).'),
    (De: 'dispid %s ist schon an %s vergeben (wie E2180).'; En: 'dispid %s is already assigned to %s (like E2180).'),
    (De: 'Konstruktoren und Destruktoren sind im Abschnitt automated nicht erlaubt (wie E2177).';
     En: 'Constructors and destructors are not allowed in the automated section (like E2177).'),
    (De: '%s ist im Abschnitt automated nicht erlaubt (wie E2178).';
     En: '%s is not allowed in the automated section (like E2178).'),
    (De: 'Im Abschnitt automated ist nur register erlaubt, nicht %s (wie E2179).';
     En: 'Only register is allowed in the automated section, not %s (like E2179).'),
    (De: 'Die überschriebene Methode %s übernimmt die dispid des Vorfahren und darf keine eigene angeben (wie E2185).';
     En: 'The overridden method %s takes over the dispid of the ancestor and must not specify its own (like E2185).'),
    (De: 'Im Abschnitt automated muss %s auf eine Methode zeigen; %s ist ein Feld (wie E2096).';
     En: 'In the automated section %s must refer to a method; %s is a field (like E2096).'),
    (De: '%s ist an Properties im Abschnitt automated nicht erlaubt (wie E2182).';
     En: '%s is not allowed on properties in the automated section (like E2182).'),
    (De: 'Die Property %s darf im Abschnitt automated nicht ohne Typ neu deklariert werden (wie E2181).';
     En: 'The property %s must not be redeclared without a type in the automated section (like E2181).'),
    (De: 'dispid ist nur im Abschnitt automated erlaubt (wie E2185).';
     En: 'dispid is only allowed in the automated section (like E2185).'),
    (De: 'Felder sind im Abschnitt automated nicht erlaubt (wie E2175).';
     En: 'Fields are not allowed in the automated section (like E2175).'),
    (De: 'Unbenannte Argumente müssen vor den benannten stehen (wie E2166).';
     En: 'Unnamed arguments must come before the named ones (like E2166).'),
    (De: 'Der Typ %s ist in einem %s nicht erlaubt (wie %s).'; En: 'The type %s is not allowed in a %s (like %s).'),
    (De: 'OLE-Automation falsch deklariert oder aufgerufen'; En: 'OLE automation declared or called incorrectly'),
    (De: 'OLE-Automation-Aufruf'; En: 'OLE automation call'),
    (De: 'Variant-Dispatch-Aufruf'; En: 'variant dispatch call'));

{$SCOPEDENUMS OFF}

const
  // Aufrufkonventionen, die im Abschnitt automated nicht erlaubt sind (E2179).
  cForeignConventions: array[0..4] of string = ('stdcall', 'cdecl', 'pascal', 'safecall', 'winapi');
  // Property-Klauseln, die im Abschnitt automated nicht erlaubt sind (E2182).
  cForbiddenClauses: array[0..3] of string = ('index', 'stored', 'default', 'nodefault');
  // Klauseln einer Property, hinter denen ein Argument steht.
  cArgumentClauses: array[0..6] of string = ('read', 'write', 'index', 'stored', 'default', 'implements', 'dispid');
  // Zeichentypen: ein Zeiger darauf (PChar) bleibt still.
  cCharTypes: array[0..3] of string = ('Char', 'AnsiChar', 'WideChar', 'UTF8Char');

type
  /// <summary>Eine dispid im Abschnitt automated: Schlüssel des Werts, Name des Mitglieds.</summary>
  TAutomationDispid = record
    Key: string;
    Member: string;
  end;

  /// <summary>Stand beim Lesen der Klauseln einer Property im Abschnitt automated.</summary>
  TAutomationClause = record
    Owner: TSyntaxNode;
    Prop: TSyntaxNode;
    Dispids: TList<TAutomationDispid>;
    Typed: Boolean;
    Index: Integer;
    Stop: Integer;
  end;

  /// <summary>Prüfung einer Datei; pinnt den Baum für die Dauer der Prüfung.</summary>
  TAutomationCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TArray<TPascalToken>;
    FPaths: TArray<string>;
    FFileName: string;
    FResolver: TNameResolver;
    FOwnUnit: TUnitIndex;
    function FirstToken(ANode: TSyntaxNode): Integer;
    function StopToken(ANode: TSyntaxNode): Integer;
    function NextCode(AIndex, AStop: Integer): Integer;
    function PreviousCode(AIndex: Integer): Integer;
    function Unconditional(ANode: TSyntaxNode): Boolean;
    function TokenRange(AIndex: Integer): TTextRange;
    function NodeText(ANode: TSyntaxNode): string;
    /// <summary>Erstes Token mit dem Namen ANode.Name (bei Feldern der erste Name) ab dem Anfang des Knotens.
    /// </summary>
    function NameRange(ANode: TSyntaxNode): TTextRange;
    /// <summary>Text der Token AFirst..AStop-1 ohne Kommentare und Leerraum.</summary>
    function TokenText(AFirst, AStop: Integer): string;
    function HasDirective(AHeader: TSyntaxNode; const AName: string): Boolean;
    /// <summary>Typ ATypeNode, wenn er im Abschnitt automated sicher nicht erlaubt ist: Record, Zeiger, Menge.
    /// </summary>
    function IllegalAutomatedType(ATypeNode: TSyntaxNode; out AName: string): Boolean;
    procedure CheckTypes(AMember: TSyntaxNode);
    procedure CheckRoutine(AHeader: TSyntaxNode; ADispids: TList<TAutomationDispid>);
    /// <summary>Token des Namens der Property; AStop, wenn er fehlt.</summary>
    function PropertyNameToken(AProperty: TSyntaxNode; AStop: Integer): Integer;
    /// <summary>read bzw. write AWord am Token AIndex: Ziel darf kein Feld sein (E2096).</summary>
    procedure CheckAccessor(AClass: TSyntaxNode; AIndex, AStop: Integer; const AWord: string);
    procedure CheckPropertyDispid(AProperty: TSyntaxNode; AIndex, AStop: Integer;
      ADispids: TList<TAutomationDispid>);
    procedure CheckClause(const AClause: TAutomationClause; const AWord: string);
    procedure CheckProperty(AClass, AProperty: TSyntaxNode; ADispids: TList<TAutomationDispid>);
    /// <summary>dispid an einer Methode außerhalb von automated (E2185).</summary>
    procedure CheckDispidOutside(AMember: TSyntaxNode);
    procedure CheckAutomatedMember(AClass, AMember: TSyntaxNode; ADispids: TList<TAutomationDispid>);
    /// <summary>dispid mit dem Argument AText an ARange für das Mitglied AMember; meldet eine doppelte.</summary>
    procedure CheckDispid(const ARange: TTextRange; const AText, AMember: string; ADispids: TList<TAutomationDispid>);
    procedure CheckClass(AClass: TSyntaxNode);
    /// <summary>Ist ANode ein Ausdruck vom Typ Variant bzw. OleVariant (auch über eine Kette von Aufrufen
    /// darauf)?</summary>
    function VariantReceiver(ANode: TSyntaxNode; out AOle: Boolean): Boolean;
    /// <summary>Typ des Arguments, wenn es eine Variable mit sicher bekanntem Typ ist.</summary>
    function ArgumentType(AArgument: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
    /// <summary>Typ des Arguments AArgument, wenn er sicher nicht über Variant aufgerufen werden kann.</summary>
    function IllegalDispatchArgument(AArgument: TSyntaxNode; out AName: string): Boolean;
    function NamedArgument(AArgument: TSyntaxNode): Boolean;
    procedure CheckDispatchCall(ACall: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Änderung der Klammerebene durch AToken: +1 für ( und [, -1 für ) und ], sonst 0.</summary>
function BracketStep(const AToken: TPascalToken): Integer;
begin
  Result := 0;
  if AToken.IsSymbol('[') or AToken.IsSymbol('(') then
  begin
    Result := 1;
  end
  else if AToken.IsSymbol(']') or AToken.IsSymbol(')') then
  begin
    Result := -1;
  end;
end;

/// <summary>Alle Knoten unter ARoot in Baumreihenfolge über einen eigenen Stapel (Bericht M1).</summary>
function PreOrder(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  mPending: TStack<TSyntaxNode>;
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
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

/// <summary>Wert einer Zahl als Text (dezimal oder $-hex); '' bei anderem Text.</summary>
function NumberKey(const AText: string): string;
var
  mValue: Int64;
begin
  Result := '';
  if (AText <> '') and TryStrToInt64(AText, mValue) then
  begin
    Result := IntToStr(mValue);
  end;
end;

{ TAutomationCheck }

constructor TAutomationCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FTokens := AContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(FTokens);
  FFileName := AContext.FileName;
  if FFileName = '' then
  begin
    FFileName := AContext.RelativePath;
  end;
  if FFileName = '' then
  begin
    FFileName := AContext.UnitName + '.pas';
  end;
  FResolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
  FResolver.Namespaces := AContext.Namespaces;
  FResolver.PinTree(AContext.Tree, FFileName);
  FOwnUnit := FResolver.ExtractedUnit(AContext.Tree, FFileName);
end;

destructor TAutomationCheck.Destroy;
begin
  FResolver.UnpinTree;
  FResolver.Free;
  FTokens := nil;
  FPaths := nil;
  inherited;
end;

function TAutomationCheck.FirstToken(ANode: TSyntaxNode): Integer;
begin
  Result := TConstantValues.TokenFrom(FTokens, ANode.StartOffset);
end;

function TAutomationCheck.StopToken(ANode: TSyntaxNode): Integer;
begin
  Result := TConstantValues.TokenFrom(FTokens, ANode.EndOffset);
end;

function TAutomationCheck.NextCode(AIndex, AStop: Integer): Integer;
begin
  Result := AIndex;
  while (Result < AStop) and IsTrivia(FTokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function TAutomationCheck.PreviousCode(AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(FTokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function TAutomationCheck.Unconditional(ANode: TSyntaxNode): Boolean;
begin
  Result := TConditionalBranches.PathAt(FPaths, FirstToken(ANode)) = '';
end;

function TAutomationCheck.TokenRange(AIndex: Integer): TTextRange;
begin
  Result := TTextRange.Create(FTokens[AIndex].StartPos, FTokens[AIndex].EndPos);
end;

function TAutomationCheck.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TAutomationCheck.NameRange(ANode: TSyntaxNode): TTextRange;
var
  mIndex, mStop: Integer;
  mName: string;
begin
  mName := ANode.Name;
  if Pos(',', mName) > 0 then
  begin
    mName := Copy(mName, 1, Pos(',', mName) - 1);
  end;
  mStop := StopToken(ANode);
  for mIndex := FirstToken(ANode) to mStop - 1 do
  begin
    if (FTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(FTokens[mIndex].Text, mName) then
    begin
      Exit(TokenRange(mIndex));
    end;
  end;
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function TAutomationCheck.TokenText(AFirst, AStop: Integer): string;
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

function TAutomationCheck.HasDirective(AHeader: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(AHeader[mIndex].Name, AName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Rechte Seite einer Typdeklaration aus ihrer Signatur (TFarben = set of TFarbe; → set of TFarbe);
/// '' ohne Gleichheitszeichen.</summary>
function AliasDeclaration(const ASignature: string): string;
begin
  Result := '';
  if Pos('=', ASignature) = 0 then
  begin
    Exit;
  end;
  Result := Trim(Copy(ASignature, Pos('=', ASignature) + 1, MaxInt));
  if EndsStr(';', Result) then
  begin
    Result := Trim(Copy(Result, 1, Length(Result) - 1));
  end;
end;

/// <summary>Zeigt die Deklaration ADeclared auf einen Typ außer einem Zeichentyp (^TPunkt, nicht PChar)?</summary>
function IsDataPointer(const ADeclared: string): Boolean;
begin
  Result := StartsStr('^', ADeclared) and not MatchText(Trim(Copy(ADeclared, 2, MaxInt)), cCharTypes);
end;

function TAutomationCheck.IllegalAutomatedType(ATypeNode: TSyntaxNode; out AName: string): Boolean;
var
  mSymbol: TResolvedSymbol;
  mDeclared: string;
begin
  Result := False;
  AName := Trim(NodeText(ATypeNode));
  if (ATypeNode.Kind <> TSyntaxKind.TypeReference) or (AName = '') or
    not FResolver.ResolveTypeTextFrom(FOwnUnit, AName, mSymbol) or (mSymbol.Condition <> '') then
  begin
    Exit;
  end;
  if mSymbol.Builtin then
  begin
    Result := SameText(mSymbol.Name, 'Pointer');
  end
  else if mSymbol.SymbolKind = TIndexSymbolKind.RecordType then
  begin
    Result := True;
  end
  else if mSymbol.SymbolKind = TIndexSymbolKind.TypeAlias then
  begin
    // Zeiger (PPunkt = ^TPunkt) und Mengen (TFarben = set of TFarbe) aus dem Kopf der Deklaration.
    mDeclared := AliasDeclaration(mSymbol.Signature);
    Result := IsDataPointer(mDeclared) or not StartsStr('^', mDeclared) and StartsText('set of ', mDeclared);
  end;
end;

/// <summary>Hängt die Typen der Parameter in AParameters an ATypes an.</summary>
procedure AddParameterTypes(AParameters: TSyntaxNode; const ATypes: TList<TSyntaxNode>);
var
  mIndex: Integer;
begin
  for mIndex := 0 to AParameters.ChildCount - 1 do
  begin
    if (AParameters[mIndex].Kind = TSyntaxKind.Parameter) and (AParameters[mIndex].ChildCount > 0) then
    begin
      ATypes.Add(AParameters[mIndex][0]);
    end;
  end;
end;

procedure TAutomationCheck.CheckTypes(AMember: TSyntaxNode);
var
  mTypes: TList<TSyntaxNode>;
  mTypeNode: TSyntaxNode;
  mIndex: Integer;
  mName: string;
begin
  mTypes := TList<TSyntaxNode>.Create;
  try
    for mIndex := 0 to AMember.ChildCount - 1 do
    begin
      if AMember[mIndex].Kind = TSyntaxKind.TypeReference then
      begin
        mTypes.Add(AMember[mIndex]);
      end
      else if AMember[mIndex].Kind = TSyntaxKind.Parameters then
      begin
        AddParameterTypes(AMember[mIndex], mTypes);
      end;
    end;
    for mTypeNode in mTypes do
    begin
      if IllegalAutomatedType(mTypeNode, mName) then
      begin
        FReport.Add(TTextRange.Create(mTypeNode.StartPos, mTypeNode.EndPos),
          cTexts[TAutomationText.TypeNotAllowed].Fmt([mName]));
      end;
    end;
  finally
    mTypes.Free;
  end;
end;
procedure TAutomationCheck.CheckDispid(const ARange: TTextRange; const AText, AMember: string;
  ADispids: TList<TAutomationDispid>);
var
  mDispid: TAutomationDispid;
  mKey: string;
begin
  // Schlüssel: der Wert einer Zahl, sonst der Text des Ausdrucks.
  mKey := NumberKey(AText);
  if mKey = '' then
  begin
    mKey := UpperCase(AText);
  end;
  if mKey = '' then
  begin
    Exit;
  end;
  for mDispid in ADispids do
  begin
    if mDispid.Key = mKey then
    begin
      FReport.Add(ARange, cTexts[TAutomationText.DispidTaken].Fmt([AText, mDispid.Member]));
      Exit;
    end;
  end;
  mDispid.Key := mKey;
  mDispid.Member := AMember;
  ADispids.Add(mDispid);
end;

procedure TAutomationCheck.CheckRoutine(AHeader: TSyntaxNode; ADispids: TList<TAutomationDispid>);
var
  mFirst: Integer;
  mWord: string;
  mIndex: Integer;
  mDirective: TSyntaxNode;
begin
  mFirst := NextCode(FirstToken(AHeader), StopToken(AHeader));
  mWord := LowerCase(FTokens[mFirst].Text);
  if (mWord = 'constructor') or (mWord = 'destructor') then
  begin
    FReport.Add(TokenRange(mFirst),
      cTexts[TAutomationText.NoCtorDtor].Text);
  end;
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    mDirective := AHeader[mIndex];
    if mDirective.Kind <> TSyntaxKind.Directive then
    begin
      Continue;
    end;
    if MatchText(mDirective.Name, ['dynamic', 'message']) then
    begin
      FReport.Add(TokenRange(FirstToken(mDirective)),
        cTexts[TAutomationText.DirectiveNotAllowed].Fmt([mDirective.Name]));
    end
    else if MatchText(mDirective.Name, cForeignConventions) then
    begin
      FReport.Add(TokenRange(FirstToken(mDirective)),
        cTexts[TAutomationText.OnlyRegister].Fmt([mDirective.Name]));
    end
    else if SameText(mDirective.Name, 'dispid') then
    begin
      if HasDirective(AHeader, 'override') then
      begin
        FReport.Add(TTextRange.Create(mDirective.StartPos, mDirective.EndPos),
          cTexts[TAutomationText.OverrideDispid].Fmt([AHeader.Name]));
      end
      else
      begin
        CheckDispid(TTextRange.Create(mDirective.StartPos, mDirective.EndPos),
          TokenText(FirstToken(mDirective) + 1, StopToken(mDirective)), AHeader.Name, ADispids);
      end;
    end;
  end;
  CheckTypes(AHeader);
end;

/// <summary>Hat die Klasse AClass ein Feld namens AName?</summary>
function IsClassField(AClass: TSyntaxNode; const AName: string): Boolean;
var
  mMember: Integer;
begin
  Result := False;
  for mMember := 0 to AClass.ChildCount - 1 do
  begin
    if (AClass[mMember].Kind = TSyntaxKind.Field) and MatchText(AName, AClass[mMember].Name.Split([','])) then
    begin
      Exit(True);
    end;
  end;
end;

function TAutomationCheck.PropertyNameToken(AProperty: TSyntaxNode; AStop: Integer): Integer;
begin
  Result := FirstToken(AProperty);
  while (Result < AStop) and not ((FTokens[Result].Kind = TPascalTokenKind.Identifier) and
    SameText(FTokens[Result].Text, AProperty.Name)) do
  begin
    Inc(Result);
  end;
end;

procedure TAutomationCheck.CheckAccessor(AClass: TSyntaxNode; AIndex, AStop: Integer; const AWord: string);
var
  mArgument, mNext: Integer;
begin
  mArgument := NextCode(AIndex + 1, AStop);
  mNext := NextCode(mArgument + 1, AStop);
  // read FPunkt.X ist ein Feldzugriff, aber nicht sicher dasselbe Feld.
  if (mArgument < AStop) and (FTokens[mArgument].Kind = TPascalTokenKind.Identifier) and
    ((mNext >= AStop) or not FTokens[mNext].IsSymbol('.')) and IsClassField(AClass, FTokens[mArgument].Text) then
  begin
    FReport.Add(TokenRange(mArgument),
      cTexts[TAutomationText.AccessorField].Fmt([AWord, FTokens[mArgument].Text]));
  end;
end;

procedure TAutomationCheck.CheckPropertyDispid(AProperty: TSyntaxNode; AIndex, AStop: Integer;
  ADispids: TList<TAutomationDispid>);
var
  mArgument: Integer;
begin
  // Argument bis zur nächsten Klausel bzw. zum Semikolon.
  mArgument := AIndex + 1;
  while (mArgument < AStop) and not FTokens[mArgument].IsSymbol(';') and
    not ((FTokens[mArgument].Kind = TPascalTokenKind.Identifier) and
    MatchText(FTokens[mArgument].Text, cArgumentClauses)) do
  begin
    Inc(mArgument);
  end;
  CheckDispid(TTextRange.Create(FTokens[AIndex].StartPos, FTokens[mArgument - 1].EndPos),
    TokenText(AIndex + 1, mArgument), AProperty.Name, ADispids);
end;

procedure TAutomationCheck.CheckClause(const AClause: TAutomationClause; const AWord: string);
begin
  if MatchText(AWord, cForbiddenClauses) then
  begin
    FReport.Add(TokenRange(AClause.Index),
      cTexts[TAutomationText.PropertyDirective].Fmt([AWord]));
  end;
  if ((AWord = 'read') or (AWord = 'write')) and AClause.Typed then
  begin
    CheckAccessor(AClause.Owner, AClause.Index, AClause.Stop, AWord);
  end;
  if AWord = 'dispid' then
  begin
    CheckPropertyDispid(AClause.Prop, AClause.Index, AClause.Stop, AClause.Dispids);
  end;
end;

procedure TAutomationCheck.CheckProperty(AClass, AProperty: TSyntaxNode; ADispids: TList<TAutomationDispid>);
var
  mClause: TAutomationClause;
  mDepth: Integer;
  mWord: string;
  mExpectArgument: Boolean;
  mToken: TPascalToken;
begin
  mClause.Owner := AClass;
  mClause.Prop := AProperty;
  mClause.Dispids := ADispids;
  mClause.Typed := AProperty.FindChild(TSyntaxKind.TypeReference) <> nil;
  if not mClause.Typed then
  begin
    FReport.Add(NameRange(AProperty),
      cTexts[TAutomationText.RedeclareNoType].Fmt([AProperty.Name]));
  end;
  // Klauseln hinter dem Typ bis zum ersten Semikolon auf Klammerebene 0.
  mClause.Stop := StopToken(AProperty);
  mClause.Index := PropertyNameToken(AProperty, mClause.Stop) + 1;
  mDepth := 0;
  mExpectArgument := False;
  while mClause.Index < mClause.Stop do
  begin
    mToken := FTokens[mClause.Index];
    if (mDepth = 0) and mToken.IsSymbol(';') then
    begin
      Break;
    end;
    if not IsTrivia(mToken) then
    begin
      mDepth := mDepth + BracketStep(mToken);
      if (mDepth = 0) and not mExpectArgument and (mToken.Kind = TPascalTokenKind.Identifier) then
      begin
        mWord := LowerCase(mToken.Text);
        CheckClause(mClause, mWord);
        mExpectArgument := MatchText(mWord, cArgumentClauses);
      end
      else
      begin
        mExpectArgument := False;
      end;
    end;
    Inc(mClause.Index);
  end;
  if mClause.Typed then
  begin
    CheckTypes(AProperty);
  end;
end;

procedure TAutomationCheck.CheckDispidOutside(AMember: TSyntaxNode);
var
  mInner: Integer;
  mDirective: TSyntaxNode;
begin
  // dispid außerhalb von automated: Delphi 13 meldet E2185 (Fall Cm.E2183).
  if AMember.Kind <> TSyntaxKind.RoutineHeader then
  begin
    Exit;
  end;
  for mInner := 0 to AMember.ChildCount - 1 do
  begin
    mDirective := AMember[mInner];
    if (mDirective.Kind = TSyntaxKind.Directive) and SameText(mDirective.Name, 'dispid') then
    begin
      FReport.Add(TTextRange.Create(mDirective.StartPos, mDirective.EndPos),
        cTexts[TAutomationText.DispidOutside].Text);
    end;
  end;
end;

procedure TAutomationCheck.CheckAutomatedMember(AClass, AMember: TSyntaxNode; ADispids: TList<TAutomationDispid>);
begin
  case AMember.Kind of
    TSyntaxKind.Field:
      FReport.Add(NameRange(AMember), cTexts[TAutomationText.NoFields].Text);
    TSyntaxKind.RoutineHeader:
      if not AMember.IsMethodResolution then
      begin
        CheckRoutine(AMember, ADispids);
      end;
    TSyntaxKind.PropertyDecl:
      CheckProperty(AClass, AMember, ADispids);
  else
    // Übrige Mitglieder (Konstanten, Typen, Attribute) bleiben still.
  end;
end;

procedure TAutomationCheck.CheckClass(AClass: TSyntaxNode);
var
  mDispids: TList<TAutomationDispid>;
  mMember: TSyntaxNode;
  mIndex: Integer;
  mAutomated: Boolean;
begin
  mDispids := TList<TAutomationDispid>.Create;
  try
    mAutomated := False;
    for mIndex := 0 to AClass.ChildCount - 1 do
    begin
      mMember := AClass[mIndex];
      if mMember.Kind = TSyntaxKind.Visibility then
      begin
        mAutomated := mMember.Name = 'automated';
      end
      else if not Unconditional(mMember) then
      begin
        // Bedingte Mitglieder bleiben still.
      end
      else if mAutomated then
      begin
        CheckAutomatedMember(AClass, mMember, mDispids);
      end
      else
      begin
        CheckDispidOutside(mMember);
      end;
    end;
  finally
    mDispids.Free;
  end;
end;
function TAutomationCheck.VariantReceiver(ANode: TSyntaxNode; out AOle: Boolean): Boolean;
var
  mNode: TSyntaxNode;
  mSymbol, mType: TResolvedSymbol;
  mFound: Boolean;
begin
  Result := False;
  AOle := False;
  mNode := ANode;
  // Der Wert einer Kette auf einem Variant (V.Dokument.Seiten[1]) ist wieder ein Variant.
  while mNode <> nil do
  begin
    if FResolver.NodeType(FContext.Tree, FFileName, mNode, mSymbol, mType, mFound) then
    begin
      if not mFound or not mType.Builtin or (mSymbol.Condition <> '') then
      begin
        Exit;
      end;
      AOle := SameText(mType.Name, 'OleVariant');
      Exit(AOle or SameText(mType.Name, 'Variant'));
    end;
    if not (mNode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Call, TSyntaxKind.IndexAccess]) or
      (mNode.ChildCount = 0) then
    begin
      Exit;
    end;
    mNode := mNode[0];
  end;
end;

function TAutomationCheck.ArgumentType(AArgument: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
var
  mSymbol: TResolvedSymbol;
  mFound: Boolean;
begin
  Result := (AArgument.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) and
    FResolver.NodeType(FContext.Tree, FFileName, AArgument, mSymbol, AType, mFound) and mFound;
  Result := Result and not mSymbol.IsType and (mSymbol.Condition = '') and (mSymbol.VariantBranch = '');
end;

function TAutomationCheck.IllegalDispatchArgument(AArgument: TSyntaxNode; out AName: string): Boolean;
var
  mType, mOperator: TResolvedSymbol;
begin
  Result := False;
  AName := '';
  if not ArgumentType(AArgument, mType) then
  begin
    Exit;
  end;
  AName := mType.Name;
  if mType.Builtin then
  begin
    Result := SameText(mType.Name, 'Pointer');
  end
  else if mType.SymbolKind = TIndexSymbolKind.RecordType then
  begin
    // Ein Record mit Operatoren (Implicit nach Variant?) bleibt still.
    Result := not FResolver.FindMember(mType, 'Implicit', mOperator) and
      not FResolver.FindMember(mType, 'Explicit', mOperator);
  end
  else if mType.SymbolKind = TIndexSymbolKind.TypeAlias then
  begin
    Result := IsDataPointer(AliasDeclaration(mType.Signature));
  end;
end;

function TAutomationCheck.NamedArgument(AArgument: TSyntaxNode): Boolean;
var
  mPrevious: Integer;
begin
  // Open(FileName := 'a.docx'): Der Parser legt für den Namen keinen Knoten an.
  mPrevious := PreviousCode(FirstToken(AArgument));
  Result := (mPrevious > 0) and FTokens[mPrevious].IsSymbol(':=');
end;

procedure TAutomationCheck.CheckDispatchCall(ACall: TSyntaxNode);
var
  mIndex: Integer;
  mOle, mNamedSeen: Boolean;
  mArgument: TSyntaxNode;
  mName, mCode, mKind: string;
begin
  if (ACall.ChildCount < 2) or (ACall[0].Kind <> TSyntaxKind.MemberAccess) or (ACall[0].ChildCount = 0) or
    not Unconditional(ACall) or not VariantReceiver(ACall[0][0], mOle) then
  begin
    Exit;
  end;
  if mOle then
  begin
    mCode := 'E2160';
    mKind := cTexts[TAutomationText.OleCall].Text;
  end
  else
  begin
    mCode := 'E2281';
    mKind := cTexts[TAutomationText.DispatchCall].Text;
  end;
  mNamedSeen := False;
  for mIndex := 1 to ACall.ChildCount - 1 do
  begin
    mArgument := ACall[mIndex];
    if NamedArgument(mArgument) then
    begin
      mNamedSeen := True;
    end
    else if mNamedSeen then
    begin
      FReport.Add(TTextRange.Create(mArgument.StartPos, mArgument.EndPos),
        cTexts[TAutomationText.NamedOrder].Text);
    end;
    if IllegalDispatchArgument(mArgument, mName) then
    begin
      FReport.Add(TTextRange.Create(mArgument.StartPos, mArgument.EndPos),
        cTexts[TAutomationText.DispatchType].Fmt([mName, mKind, mCode]));
    end;
  end;
end;

procedure TAutomationCheck.Run;
var
  mNode: TSyntaxNode;
begin
  for mNode in PreOrder(FContext.Tree.Root) do
    case mNode.Kind of
      TSyntaxKind.ClassType:
        CheckClass(mNode);
      TSyntaxKind.Call:
        CheckDispatchCall(mNode);
    else
      // Übrige Knoten bewusst ohne Wirkung.
    end;
end;

{ TAutomationInvalidRule }

function TAutomationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(AutomationInvalidRuleId, TRuleSeverity.Error,
    cTexts[TAutomationText.Title].Text);
end;

procedure TAutomationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TAutomationCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mCheck := TAutomationCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

procedure RegisterAutomationRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TAutomationInvalidRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Automation', cTexts);

end.
