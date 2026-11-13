unit Atlas.Common.Editing.MethodWithoutSelf.Analysis;

// Analyse für „Methode ohne Self“ (#686): ob die Methode umgewandelt werden kann, welche Namen im Rumpf die Klasse
// brauchen und ob eine freie Routine bzw. ein Record-Helper geht. Die Umwandlung selbst steht in
// Atlas.Common.Editing.MethodWithoutSelf.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.MethodWithoutSelf.Lookup,
  Atlas.Common.Pascal.TreeCache,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.RoutineParts,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.MethodWithoutSelf.Contract;

type
  /// <summary>Analyse der Methode in ihrer Unit.</summary>
  TMethodPlan = class
  public
    Text: string;
    Tree: TSyntaxTree;
    Tokens: TArray<TPascalToken>;
    Lines: TLineTable;
    Lookup: TMethodLookup;
    Cache: TLocalsCache;
    Routine: TSyntaxNode;
    Header: TSyntaxNode;
    Body: TSyntaxNode;
    Declaration: TSyntaxNode;
    TypeBody: TSyntaxNode;
    Target: TMethodTarget;
    Visibility: string;
    ClassInInterface: Boolean;
    IsFunction: Boolean;
    Parameters: TArray<TParameterText>;
    /// <summary>Namen im Rumpf und im Kopf, die ohne Klasse die Klasse davor brauchen.</summary>
    Statics: TArray<TSyntaxNode>;
    /// <summary>Kopf der Deklaration nennt einen Typ der Klasse.</summary>
    HeadUsesClassType: Boolean;
    UsesClassLevel: Boolean;
    StrictName: string;
    constructor Create(const AText: string; ATree: TSyntaxTree; const ALookup: TMethodLookup);
    destructor Destroy; override;
    function Analyze(AOffset: Integer; out AReason: string): Boolean;
    /// <summary>Virtuell, Teil eines Interfaces, Zugriffsmethode oder Ereignis der Formulardatei?</summary>
    function DeclarationIssue: string;
    /// <summary>Stehen Attribute ([Test]) direkt vor der Deklaration?</summary>
    function HasAttributes: Boolean;
    /// <summary>Namen im Rumpf: Self, inherited, with und Instanzmitglieder verhindern die Umwandlung.</summary>
    function NamesIssue: string;
    function NameIssue(ANode: TSyntaxNode): string;
    procedure NoteStatic(ANode: TSyntaxNode; ALevel: TMemberLevel; AVisible: TIndexVisibility; AInHead: Boolean);
    /// <summary>Methodenzeiger in den Methoden der Klasse.</summary>
    function LocalUsesIssue: string;
    procedure CheckRoutine;
    procedure CheckHelper;
    function UnitName: string;
    /// <summary>Als Methodenzeiger benutzt: @X, bei Prozeduren und Funktionen mit Parametern jede Verwendung als
    /// Wert.</summary>
    function IsPointer(AUse: TMethodUse): Boolean;
    /// <summary>Wird der erste Parameter im Rumpf geschrieben oder in einer anonymen Methode benutzt?</summary>
    function FirstParameterUses(out AReason: string): Boolean;
    /// <summary>Bezeichner im Rumpf, die den ersten Parameter meinen.</summary>
    function FirstParameterNodes: TArray<TSyntaxNode>;
    /// <summary>AReason nach AOut, Ergebnis False (Abbruch mit Grund).</summary>
    class function Fail(const AReason: string; out AOut: string): Boolean; static;
    /// <summary>„Zeile n“ bzw. „Datei, Zeile n“ (ALine 0-basiert).</summary>
    class function Where(const AFileName: string; ALine: Integer): string; static;
    /// <summary>Verwendung des Namens AName, der an AOffset beginnt; ACall: der Aufruf mit Argumenten oder nil.
    /// </summary>
    class function UseAt(ATree: TSyntaxTree; AOffset: Integer; const AName: string; out ACallee,
      ACall: TSyntaxNode): TMethodUse; static;
    /// <summary>Einfacher Typ für einen Record-Helper?</summary>
    class function IsSimpleType(const ATypeName: string): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.MethodWithoutSelf.Texts;

const
  cSimpleTypes: array[0..27] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'Char',
    'WideChar', 'AnsiChar', 'Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt', 'Byte', 'Word',
    'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Double', 'Single', 'Extended', 'Currency', 'Boolean',
    'TDateTime', 'TDate', 'TTime', 'TGUID');

class function TMethodPlan.Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

class function TMethodPlan.Where(const AFileName: string; ALine: Integer): string;
begin
  if AFileName = '' then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.Line].Fmt([ALine + 1]);
  end
  else
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.Line2].Fmt([ExtractFileName(AFileName), ALine + 1]);
  end;
end;

/// <summary>Verwendung des gefundenen Namens nach seinem Elternknoten; ACall: der Aufruf mit Argumenten.</summary>
function FoundUse(AFound: TSyntaxNode; out ACall: TSyntaxNode): TMethodUse;
var
  mParent: TSyntaxNode;
begin
  ACall := nil;
  mParent := AFound.Parent;
  if mParent = nil then
  begin
    Result := TMethodUse.Value;
  end
  else if (mParent.Kind = TSyntaxKind.Call) and (mParent[0] = AFound) then
  begin
    ACall := mParent;
    Result := TMethodUse.Call;
  end
  else if mParent.Kind = TSyntaxKind.CallStatement then
  begin
    Result := TMethodUse.Call;
  end
  else if mParent.Kind = TSyntaxKind.AddressOf then
  begin
    Result := TMethodUse.Pointer;
  end
  else
  begin
    Result := TMethodUse.Value;
  end;
end;

class function TMethodPlan.UseAt(ATree: TSyntaxTree; AOffset: Integer; const AName: string;
  out ACallee, ACall: TSyntaxNode): TMethodUse;
var
  mScan: TMethodUseScan;
begin
  ACallee := nil;
  ACall := nil;
  mScan := TMethodUseScan.Scan(ATree, AOffset, AName);
  if mScan.InProperty then
  begin
    Result := TMethodUse.Accessor;
  end
  else if mScan.InInherited then
  begin
    Result := TMethodUse.Inherited_;
  end
  else if mScan.Found = nil then
  begin
    Result := TMethodUse.Unknown;
  end
  else
  begin
    ACallee := mScan.Found;
    Result := FoundUse(mScan.Found, ACall);
  end;
end;


{ TMethodPlan }

constructor TMethodPlan.Create(const AText: string; ATree: TSyntaxTree; const ALookup: TMethodLookup);
begin
  inherited Create;
  Text := AText;
  Tree := ATree;
  Tokens := ATree.Tokens;
  Lines := TLineTable.Build(AText);
  Lookup := ALookup;
  Cache := TLocalsCache.Create(AText, ATree);
end;

destructor TMethodPlan.Destroy;
begin
  Cache.Free;
  inherited;
end;

function TMethodPlan.UnitName: string;
begin
  Result := Tree.Root.Name;
end;

function TMethodPlan.IsPointer(AUse: TMethodUse): Boolean;
begin
  Result := (AUse = TMethodUse.Pointer) or ((AUse = TMethodUse.Value) and (not IsFunction or (Parameters <> nil)));
end;

function ClassNameIssue(const AClassName: string): string;
begin
  Result := '';
  if AClassName = '' then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.NoMethod].Text;
  end
  else if (Pos('<', AClassName) > 0) or (Pos('.', AClassName) > 0) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.MethodOfAGenericOr].Text;
  end;
end;

/// <summary>Methode mit Rumpf im implementation-Teil an AOffset.</summary>
function RoutineIssue(APlan: TMethodPlan; AOffset: Integer): string;
begin
  if (APlan.Tree = nil) or (APlan.Tree.Root = nil) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.NoTree].Text);
  end;
  APlan.Routine := TRoutineParts.TopRoutineAt(APlan.Tree, AOffset, APlan.Declaration);
  if (APlan.Routine = nil) or (APlan.Routine.Parent = nil) or
    (APlan.Routine.Parent.Kind <> TSyntaxKind.ImplementationSection) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.NoMethodWithABody].Text);
  end;
  APlan.Header := TRoutineParts.HeaderOf(APlan.Routine);
  APlan.Body := TRoutineBody.BodyOf(APlan.Routine);
  if (APlan.Header = nil) or (APlan.Body = nil) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.MethodWithoutBody].Text);
  end;
  APlan.Target.Name := TRoutineBody.ShortNameOf(APlan.Routine.Name);
  APlan.Target.ClassName := TRoutineBody.QualifierOf(APlan.Routine.Name);
  Result := ClassNameIssue(APlan.Target.ClassName);
end;

function IsSpecialRoutine(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  Result := (mIndex <= High(ATokens)) and (ATokens[mIndex].IsKeyword('constructor') or
    ATokens[mIndex].IsKeyword('destructor') or ATokens[mIndex].IsKeyword('operator'));
end;

function HeaderIssue(APlan: TMethodPlan): string;
begin
  Result := '';
  if IsSpecialRoutine(APlan.Tokens, APlan.Header) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.ConstructorDestructorOrOperator].Text;
  end
  else if TRoutineParts.IsClassHeader(APlan.Tokens, APlan.Header) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.AlreadyAClassMethod].Text;
  end
  else if TRoutineParts.HasWord(APlan.Tokens, APlan.Header, ['forward', 'external', 'assembler']) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.UnsupportedForm].Text;
  end;
end;

/// <summary>Anzahl der Deklarationen namens AName im Typrumpf (ohne Methodenzuordnungen); ADeclaration: die
/// letzte.</summary>
function DeclarationsOf(ATypeBody: TSyntaxNode; const AName: string; out ADeclaration: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  ADeclaration := nil;
  for mIndex := 0 to ATypeBody.ChildCount - 1 do
  begin
    if (ATypeBody[mIndex].Kind = TSyntaxKind.RoutineHeader) and not ATypeBody[mIndex].IsMethodResolution and
      SameText(ATypeBody[mIndex].Name, AName) then
    begin
      Inc(Result);
      ADeclaration := ATypeBody[mIndex];
    end;
  end;
end;

/// <summary>Klasse in der Datei und genau eine Deklaration der Methode.</summary>
function TypeIssue(APlan: TMethodPlan): string;
var
  mFound: Integer;
begin
  Result := '';
  APlan.TypeBody := TRoutineBody.TypeBody(APlan.Tree.Root, APlan.Target.ClassName);
  if (APlan.TypeBody = nil) or not (APlan.TypeBody.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.ClassNotInTheFile].Fmt([APlan.Target.ClassName]));
  end;
  APlan.Target.IsRecord := APlan.TypeBody.Kind = TSyntaxKind.RecordType;
  mFound := DeclarationsOf(APlan.TypeBody, APlan.Target.Name, APlan.Declaration);
  if mFound > 1 then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.Overloaded].Text;
  end
  else if APlan.Declaration = nil then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.DeclarationMissing].Text;
  end;
end;

/// <summary>Sichtbarkeit, Lage der Klasse, Art und Parameter der Methode.</summary>
function SignatureIssue(APlan: TMethodPlan): string;
var
  mSection, mParameters: TSyntaxNode;
begin
  Result := '';
  APlan.Visibility := TRoutineBody.VisibilityOf(APlan.TypeBody, APlan.Declaration);
  mSection := APlan.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  APlan.ClassInInterface := (mSection <> nil) and TRoutineBody.Within(APlan.TypeBody, mSection);
  APlan.IsFunction := TRoutineParts.IsFunction(APlan.Routine);
  APlan.Parameters := TRoutineParts.ParameterTexts(APlan.Text, APlan.Declaration);
  mParameters := APlan.Declaration.FindChild(TSyntaxKind.Parameters);
  if (APlan.Parameters = nil) and (mParameters <> nil) and (mParameters.ChildCount > 0) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.UnsupportedParameters].Text;
  end;
end;

function NamePositionIssue(APlan: TMethodPlan): string;
var
  mFirst, mLast: Integer;
begin
  Result := '';
  if not TRoutineParts.NameTokens(APlan.Tokens, APlan.Header, mFirst, mLast) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.NameNotFoundInThe].Text);
  end;
  APlan.Target.NamePosition := APlan.Tokens[mLast].StartPos;
  APlan.Target.HeaderEnd := APlan.Header.EndPos;
end;

function TMethodPlan.Analyze(AOffset: Integer; out AReason: string): Boolean;
begin
  AReason := RoutineIssue(Self, AOffset);
  if AReason = '' then
  begin
    AReason := HeaderIssue(Self);
  end;
  if AReason = '' then
  begin
    AReason := TypeIssue(Self);
  end;
  if AReason = '' then
  begin
    AReason := SignatureIssue(Self);
  end;
  if AReason = '' then
  begin
    AReason := DeclarationIssue;
  end;
  if AReason = '' then
  begin
    AReason := NamesIssue;
  end;
  if AReason = '' then
  begin
    AReason := LocalUsesIssue;
  end;
  if AReason = '' then
  begin
    AReason := NamePositionIssue(Self);
  end;
  Result := AReason = '';
  if Result then
  begin
    CheckRoutine;
    CheckHelper;
  end;
end;

/// <summary>Nennt die Property ANode AName hinter read, write oder stored?</summary>
function IsAccessorOf(const ATokens: TArray<TPascalToken>; AProperty: TSyntaxNode; const AName: string): Boolean;
var
  mToken: Integer;
  mInClause: Boolean;
begin
  mInClause := False;
  mToken := TRoutineBody.TokenAt(ATokens, AProperty.StartOffset);
  while (mToken <= High(ATokens)) and (ATokens[mToken].Offset < AProperty.EndOffset) do
  begin
    if MatchText(ATokens[mToken].Text, ['read', 'write', 'stored']) then
    begin
      mInClause := True;
    end
    else if mInClause and SameText(ATokens[mToken].Text, AName) then
    begin
      Exit(True);
    end;
    Inc(mToken);
  end;
  Result := False;
end;

/// <summary>Bindet ein Element des Typrumpfs die Methode (Methodenzuordnung, Interface, Property)?</summary>
function MemberIssue(APlan: TMethodPlan; AChild: TSyntaxNode): string;
begin
  Result := '';
  // Methodenzuordnung "procedure IFoo.Bar = Name".
  if (AChild.Kind = TSyntaxKind.RoutineHeader) and AChild.IsMethodResolution and
    SameText(AChild.ResolutionTarget, APlan.Target.Name) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.MethodOfAnInterface].Fmt([AChild.Name]);
  end
  // Vorfahrenliste: Interfaces, deren Mitglied die Methode ist.
  else if (AChild.Kind = TSyntaxKind.TypeReference) and Assigned(APlan.Lookup.InterfaceMember) and
    APlan.Lookup.InterfaceMember(AChild.Name, APlan.Target.Name, AChild.StartOffset) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.BelongsToTheInterface].Text + AChild.Name;
  end
  else if (AChild.Kind = TSyntaxKind.PropertyDecl) and IsAccessorOf(APlan.Tokens, AChild, APlan.Target.Name) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.AccessorOfTheProperty].Text + AChild.Name;
  end;
end;

function TMethodPlan.HasAttributes: Boolean;
var
  mIndex: Integer;
begin
  mIndex := PreviousCode(Tokens, TRoutineBody.TokenAt(Tokens, Declaration.StartOffset));
  Result := (mIndex >= 0) and Tokens[mIndex].IsSymbol(']');
end;

function TMethodPlan.DeclarationIssue: string;
var
  mIndex: Integer;
begin
  if TRoutineParts.HasWord(Tokens, Declaration, ['virtual', 'dynamic', 'override', 'abstract', 'message',
    'reintroduce', 'final']) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.VirtualOverrideOrMessage].Text);
  end;
  // Attribute ([Test], [Setup] …) und published: Aufruf über RTTI an der Instanz (DUnitX, MethodAddress).
  if HasAttributes or SameText(Visibility, 'published') then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.CalledViaRtti].Text);
  end;
  for mIndex := 0 to TypeBody.ChildCount - 1 do
  begin
    Result := MemberIssue(Self, TypeBody[mIndex]);
    if Result <> '' then
    begin
      Exit;
    end;
  end;
  Result := '';
  if Assigned(Lookup.InForm) and Lookup.InForm(Target.Name) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.IsAnEventInThe].Text;
  end;
end;

/// <summary>Kommt das Schlüsselwort AKeyword in ARoutine vor?</summary>
function HasKeyword(const ATokens: TArray<TPascalToken>; ARoutine: TSyntaxNode; const AKeyword: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TRoutineBody.TokenAt(ATokens, ARoutine.StartOffset);
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ARoutine.EndOffset) do
  begin
    if ATokens[mIndex].IsKeyword(AKeyword) then
    begin
      Exit(True);
    end;
    Inc(mIndex);
  end;
  Result := False;
end;

function TMethodPlan.NamesIssue: string;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Statics := nil;
  if not Assigned(Lookup.MemberLevel) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.NamesCannotBeResolved].Text);
  end;
  if HasKeyword(Tokens, Routine, 'inherited') then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.UsesInherited].Text);
  end;
  Result := '';
  if TRoutineLocals.HasKind(Routine, TSyntaxKind.WithStatement) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.UsesWith].Text);
  end;
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Routine, TSyntaxKind.Identifier, mNodes);
    TRoutineLocals.CollectKind(Routine, TSyntaxKind.TypeReference, mNodes);
    // Typen im Kopf der Deklaration gelten in der Klasse.
    TRoutineLocals.CollectKind(Declaration, TSyntaxKind.TypeReference, mNodes);
    for mNode in mNodes do
    begin
      Result := NameIssue(mNode);
      if Result <> '' then
      begin
        Break;
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

/// <summary>Namen, die nichts über die Klasse sagen: Typen im Kopf der Implementierung, qualifizierte Typen,
/// lokal verdeckte Namen.</summary>
function IsNeutralName(APlan: TMethodPlan; ANode: TSyntaxNode; AInHead: Boolean): Boolean;
begin
  if ANode.Kind = TSyntaxKind.TypeReference then
  begin
    if TRoutineBody.Within(ANode, APlan.Header) or (Pos('.', ANode.Name) > 0) then
    begin
      Exit(True);
    end;
  end;
  Result := not AInHead and TRoutineParts.Shadowed(APlan.Cache, ANode, APlan.Routine,
    TMethodLookup.HeadName(ANode.Name), True);
end;

/// <summary>Art des Namens; ein Typname ist nie ein Instanzmitglied, unbekannte Typen ändern nichts.</summary>
function NodeLevel(APlan: TMethodPlan; ANode: TSyntaxNode; out AVisible: TIndexVisibility): TMemberLevel;
begin
  Result := APlan.Lookup.MemberLevel(ANode, AVisible);
  if (ANode.Kind = TSyntaxKind.TypeReference) and (Result in [TMemberLevel.Instance, TMemberLevel.Unknown]) then
  begin
    Result := TMemberLevel.NotMember;
  end;
end;

function TMethodPlan.NameIssue(ANode: TSyntaxNode): string;
var
  mInHead: Boolean;
  mLevel: TMemberLevel;
  mVisible: TIndexVisibility;
begin
  Result := '';
  if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'Self') then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.UsesSelf].Fmt([TMethodPlan.Where('', ANode.StartPos.Line)]));
  end;
  mInHead := TRoutineBody.Within(ANode, Declaration) or TRoutineBody.Within(ANode, Header);
  if IsNeutralName(Self, ANode, mInHead) then
  begin
    Exit;
  end;
  mLevel := NodeLevel(Self, ANode, mVisible);
  case mLevel of
    TMemberLevel.Instance:
      Result := cTexts[TEditingMethodWithoutSelfText.UsesText].Fmt([ANode.Name, Where('', ANode.StartPos.Line)]);
    TMemberLevel.Unknown:
      Result := cTexts[TEditingMethodWithoutSelfText.IsUnknown].Fmt([TMethodLookup.HeadName(ANode.Name),
        TMethodPlan.Where('', ANode.StartPos.Line)]);
    TMemberLevel.ClassLevel, TMemberLevel.StaticLevel:
      NoteStatic(ANode, mLevel, mVisible, mInHead);
    TMemberLevel.NotMember: ;
  end;
end;

procedure TMethodPlan.NoteStatic(ANode: TSyntaxNode; ALevel: TMemberLevel; AVisible: TIndexVisibility;
  AInHead: Boolean);
begin
  if ALevel = TMemberLevel.ClassLevel then
  begin
    UsesClassLevel := True;
  end;
  if AInHead then
  begin
    HeadUsesClassType := True;
  end
  else
  begin
    Statics := Statics + [ANode];
  end;
  if (StrictName = '') and (AVisible in [TIndexVisibility.StrictPrivate, TIndexVisibility.StrictProtected]) then
  begin
    StrictName := TMethodLookup.HeadName(ANode.Name);
  end;
end;

/// <summary>Benutzt die Methode AOther die Methode als Methodenzeiger?</summary>
function PointerUseIssue(APlan: TMethodPlan; AOther: TSyntaxNode): string;
var
  mUses: TList<TSyntaxNode>;
  mNode, mCallee, mCall: TSyntaxNode;
begin
  Result := '';
  mUses := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(AOther, TSyntaxKind.Identifier, mUses);
    for mNode in mUses do
    begin
      if SameText(mNode.Name, APlan.Target.Name) and not TRoutineBody.Within(mNode, TRoutineParts.HeaderOf(AOther))
        and APlan.IsPointer(TMethodPlan.UseAt(APlan.Tree, mNode.StartOffset, APlan.Target.Name, mCallee,
        mCall)) then
      begin
        Exit(cTexts[TEditingMethodWithoutSelfText.IsUsedAsAMethod].Fmt([TMethodPlan.Where('', mNode.StartPos.Line)]));
      end;
    end;
  finally
    mUses.Free;
  end;
end;

function TMethodPlan.LocalUsesIssue: string;
var
  mIndex: Integer;
  mOther: TSyntaxNode;
begin
  // In den Methoden der Datei: Methodenzeiger ohne Self. davor (OnClick := Name) sieht schon die Datei. Auch
  // Methoden anderer Klassen zählen: Eine abgeleitete Klasse (Fenster aus einem Formular) übergibt geerbte
  // Ereignisse ohne Self.
  Result := '';
  for mIndex := 0 to Routine.Parent.ChildCount - 1 do
  begin
    mOther := Routine.Parent[mIndex];
    if (mOther.Kind = TSyntaxKind.RoutineDecl) and (TRoutineBody.QualifierOf(mOther.Name) <> '') then
    begin
      Result := PointerUseIssue(Self, mOther);
      if Result <> '' then
      begin
        Exit;
      end;
    end;
  end;
end;

/// <summary>Was in der Klasse bleiben muss: strict-Mitglieder oder Typen der Klasse im Kopf.</summary>
function ClassBoundIssue(APlan: TMethodPlan): string;
begin
  Result := '';
  if APlan.StrictName <> '' then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.UsesStrict].Fmt([APlan.StrictName]);
  end
  else if APlan.HeadUsesClassType then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.TheHeaderNamesAType].Text;
  end;
end;

procedure TMethodPlan.CheckRoutine;
begin
  Target.RoutineReason := ClassBoundIssue(Self);
  if (Target.RoutineReason = '') and (IndexText(Target.Name, TRoutineParts.UnitNames(Tree.Root)) >= 0) then
  begin
    Target.RoutineReason := Target.Name + cTexts[TEditingMethodWithoutSelfText.AlreadyExistsInTheUnit].Text;
  end;
end;

function TMethodPlan.FirstParameterNodes: TArray<TSyntaxNode>;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Result := nil;
  if Parameters = nil then
  begin
    Exit;
  end;
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Body, TSyntaxKind.Identifier, mNodes);
    for mNode in mNodes do
    begin
      if SameText(mNode.Name, Parameters[0].Name) and not TRoutineParts.Shadowed(Cache, mNode, Routine,
        Parameters[0].Name, False) then
      begin
        Result := Result + [mNode];
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

function TMethodPlan.FirstParameterUses(out AReason: string): Boolean;
var
  mNode: TSyntaxNode;
begin
  Result := False;
  AReason := '';
  for mNode in FirstParameterNodes do
  begin
    // const schreibt der Compiler ohnehin nicht; ein Wertparameter würde als Self den Wert des Aufrufers ändern.
    if (Parameters[0].Modifier = '') and (TRoutineLocals.AccessOf(mNode, Lookup.Flow) <> TLocalAccess.Read) then
    begin
      Exit(not TMethodPlan.Fail(Parameters[0].Name + cTexts[TEditingMethodWithoutSelfText.IsWritten].Text, AReason));
    end;
    if (mNode.Parent <> nil) and (mNode.Parent.Kind = TSyntaxKind.AddressOf) then
    begin
      Exit(not TMethodPlan.Fail('@' + Parameters[0].Name, AReason));
    end;
    if TRoutineParts.InAnonymous(mNode, Routine) then
    begin
      Exit(not Fail(Parameters[0].Name + cTexts[TEditingMethodWithoutSelfText.InAnAnonymousMethod].Text,
        AReason));
    end;
  end;
end;

/// <summary>Taugt der erste Parameter als Self eines Helpers (ohne var/out, mit Typ, ohne Vorgabewert)?</summary>
function FirstParameterIssue(const AParameters: TArray<TParameterText>): string;
begin
  Result := '';
  if AParameters = nil then
  begin
    Result := 'ohne Parameter';
  end
  else if not MatchText(AParameters[0].Modifier, ['', 'const']) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.FirstParameterIs].Text + AParameters[0].Modifier;
  end
  else if (AParameters[0].Rest = '') or (Pos('=', AParameters[0].Rest) > 0) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.FirstParameterWithoutTypeOr].Text;
  end;
end;

function HelperIssue(APlan: TMethodPlan; out ATypeName: string): string;
begin
  ATypeName := '';
  Result := ClassBoundIssue(APlan);
  if Result = '' then
  begin
    Result := FirstParameterIssue(APlan.Parameters);
  end;
  if Result <> '' then
  begin
    Exit;
  end;
  ATypeName := Trim(Copy(APlan.Parameters[0].Rest, 3, MaxInt));
  if not TMethodPlan.IsSimpleType(ATypeName) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.FirstParameterHasNoSimple].Text);
  end;
  APlan.FirstParameterUses(Result);
end;

procedure TMethodPlan.CheckHelper;
var
  mTypeName: string;
begin
  Target.HelperType := '';
  Target.HelperReason := HelperIssue(Self, mTypeName);
  if Target.HelperReason = '' then
  begin
    Target.HelperType := mTypeName;
  end;
end;

class function TMethodPlan.IsSimpleType(const ATypeName: string): Boolean;
begin
  Result := IndexText(Trim(ATypeName), cSimpleTypes) >= 0;
end;

end.
