unit Atlas.Common.Editing.MethodWithoutSelf.Lookup;

// Namensauflösung für „Methode ohne Self“ (#686): Welche Namen im Rumpf
// Instanzmitglieder sind, ob ein Interface ein Mitglied hat, welcher Helper
// für einen Typ sichtbar ist und ob ein Name schon sichtbar ist. Mit
// Namensauflösung über TNameResolver, sonst über die Klasse in der Datei.
//
// Interfaces der Vorfahrenliste: Das Mitglied zählt auch aus geerbten
// Interfaces. Ist ein Interface unbekannt (ToolsAPI, RTL ohne Index), kann
// die Methode zu ihm gehören und bleibt unangetastet: alle Einträge hinter dem
// ersten (dort stehen nur Interfaces) und ein erster Eintrag der Form IFoo.
// IInterface, IUnknown und IDispatch kennt die Unit selbst.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow.Signatures,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.PromoteVariable;

type
{$SCOPEDENUMS ON}
  /// <summary>Art eines Namens im Rumpf einer Methode.</summary>
  TMemberLevel = (NotMember, Instance, ClassLevel, StaticLevel, Unknown);
{$SCOPEDENUMS OFF}

  /// <summary>Art des Bezeichners bzw. Typnamens ANode im Rumpf; AVisibility bei Mitgliedern.</summary>
  TMemberLevelFunc = reference to function(ANode: TSyntaxNode; out AVisibility: TIndexVisibility): TMemberLevel;
  /// <summary>Kann AName zum Interface ATypeName gehören, das an AOffset in der Vorfahrenliste steht? Auch bei
  /// einem unbekannten Interface; AOffset außerhalb einer Vorfahrenliste zählt wie ein erster Eintrag.</summary>
  TMethodTypeMemberFunc = reference to function(const ATypeName, AName: string; AOffset: Integer): Boolean;
  /// <summary>Name des an AOffset sichtbaren Helpers für ATypeName, '' ohne.</summary>
  TMethodHelperFunc = reference to function(const ATypeName: string; AOffset: Integer): string;
  /// <summary>Ist der Name AName an AOffset schon sichtbar (Typ einer anderen Unit)?</summary>
  TMethodNameVisibleFunc = reference to function(const AName: string; AOffset: Integer): Boolean;

  TMethodLookup = record
    MemberLevel: TMemberLevelFunc;
    InterfaceMember: TMethodTypeMemberFunc;
    /// <summary>Steht AName in der Formulardatei? Derselbe Typ wie bei „Variable befördern“, weil
    /// TLspMethodWithoutSelf.Lookup das Feld von dort übernimmt (Delphi 12 lehnt gleich aufgebaute, aber
    /// verschieden deklarierte Methodenreferenztypen ab).</summary>
    InForm: TPromoteInFormFunc;
    VisibleHelper: TMethodHelperFunc;
    NameVisible: TMethodNameVisibleFunc;
    /// <summary>Art der Argumente bekannter Aufrufe (var-Argumente schreiben).</summary>
    Flow: TFlowSignatureLookup;
    /// <summary>Ohne Namensauflösung: Mitglieder der Klasse in der Datei; bei einem Vorfahren außer TObject
    /// sind andere Namen unbekannt.</summary>
    class function FromTree(ATree: TSyntaxTree): TMethodLookup; static;
    /// <summary>Über AResolver für ATree der Datei AFileName (Baum festhalten, solange gebraucht).</summary>
    class function FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName: string): TMethodLookup; static;
    /// <summary>Erster Teil eines Typ- oder Bezeichnernamens: TInner aus TInner&lt;X&gt;, A aus A.B.</summary>
    class function HeadName(const AName: string): string; static;
    /// <summary>Heißt der Typ wie ein Interface (IFoo, auch Unit.IFoo&lt;T&gt;)?</summary>
    class function IsInterfaceName(const ATypeName: string): Boolean; static;
  end;

  /// <summary>Stelle des Namens Name, der an Offset beginnt: Knoten des Namens und ob er in einer Property oder in
  /// inherited steht (für TMethodWithoutSelf.UseAt).</summary>
  TMethodUseScan = record
    Offset: Integer;
    Name: string;
    Found: TSyntaxNode;
    InProperty: Boolean;
    InInherited: Boolean;
    class function Scan(ATree: TSyntaxTree; AOffset: Integer; const AName: string): TMethodUseScan; static;
  private
    function IsNameAt(ANode: TSyntaxNode): Boolean;
    function Visit(ANode: TSyntaxNode): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.SystemIntrinsics,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineParts,
  Atlas.Common.Editing.NestedRoutines,
  Atlas.Common.Pascal.TokenCursor;

{$SCOPEDENUMS ON}

type
  /// <summary>Gehört ein Name zu einem Interface: nein, ja, unbekannt (Interface oder Vorfahr nicht bekannt).
  /// </summary>
  TInterfaceMembership = (No, Yes, Unknown);

{$SCOPEDENUMS OFF}

  /// <summary>Wo nach Interface-Mitgliedern gefragt wird: Auflöser, Baum und Datei, sichtbar an Offset.</summary>
  TInterfaceQuery = record
    Resolver: TNameResolver;
    Tree: TSyntaxTree;
    FileName: string;
    Offset: Integer;
  end;

const
  /// <summary>Interfaces aus System, die auch ohne Index bekannt sind, und ihre Mitglieder.</summary>
  cBaseInterfaces: array[0..2] of string = ('IInterface', 'IUnknown', 'IDispatch');
  cBaseInterfaceMembers: array[0..6] of string = ('QueryInterface', '_AddRef', '_Release', 'GetTypeInfoCount',
    'GetTypeInfo', 'GetIDsOfNames', 'Invoke');
  /// <summary>Tiefe der Interface-Vererbung, bis zu der gesucht wird.</summary>
  cInterfaceDepth = 8;
  // Helper der RTL (System.SysUtils, System.Character), falls der Index sie nicht kennt.
  cRtlHelpedTypes: array[0..14] of string = ('string', 'UnicodeString', 'Integer', 'Cardinal', 'Int64', 'UInt64',
    'NativeInt', 'NativeUInt', 'Byte', 'Word', 'ShortInt', 'SmallInt', 'Double', 'Single', 'Boolean');
  cRtlHelpers: array[0..14] of string = ('TStringHelper', 'TStringHelper', 'TIntegerHelper', 'TCardinalHelper',
    'TInt64Helper', 'TUInt64Helper', 'TNativeIntHelper', 'TNativeUIntHelper', 'TByteHelper', 'TWordHelper',
    'TShortIntHelper', 'TSmallIntHelper', 'TDoubleHelper', 'TSingleHelper', 'TBooleanHelper');

/// <summary>Klasse bzw. Record, zu dessen Methode ANode gehört; nil außerhalb.</summary>
function OwnerBody(ATree: TSyntaxTree; ANode: TSyntaxNode): TSyntaxNode;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  mNode := ANode;
  while mNode <> nil do
  begin
    if mNode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType] then
    begin
      Exit(mNode);
    end;
    if (mNode.Kind = TSyntaxKind.RoutineDecl) and (mNode.Parent <> nil) and
      (mNode.Parent.Kind = TSyntaxKind.ImplementationSection) then
    begin
      if TRoutineBody.QualifierOf(mNode.Name) <> '' then
      begin
        Result := TRoutineBody.TypeBody(ATree.Root, TRoutineBody.QualifierOf(mNode.Name));
      end;
      Exit;
    end;
    mNode := mNode.Parent;
  end;
end;

/// <summary>Beginnt der Knoten (Abschnitt oder Kopf) mit class?</summary>
function StartsWithClass(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TRoutineBody.TokenAt(ATokens, ANode.StartOffset);
  if (mIndex <= High(ATokens)) and ATokens[mIndex].IsKeyword('class') then
  begin
    Exit(True);
  end;
  // class var: Der Abschnitt beginnt erst bei var.
  mIndex := PreviousCode(ATokens, mIndex);
  Result := (mIndex >= 0) and ATokens[mIndex].IsKeyword('class');
end;

function TrimmedNames(const ANames: TArray<string>): TArray<string>;
var
  mIndex: Integer;
begin
  Result := Copy(ANames, 0, MaxInt);
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := Trim(Result[mIndex]);
  end;
end;

/// <summary>Sichtbarkeit aus dem Text des Abschnitts (strict private …); public ohne.</summary>
function VisibilityOf(const AVisibility: string): TIndexVisibility;
begin
  Result := TIndexVisibility.Public;
  if AVisibility = 'strict private' then
  begin
    Result := TIndexVisibility.StrictPrivate;
  end
  else if AVisibility = 'strict protected' then
  begin
    Result := TIndexVisibility.StrictProtected;
  end
  else if AVisibility = 'private' then
  begin
    Result := TIndexVisibility.Private;
  end
  else if AVisibility = 'protected' then
  begin
    Result := TIndexVisibility.Protected;
  end;
end;

/// <summary>Namen, die ein Element des Typrumpfs deklariert.</summary>
function MemberNames(AChild: TSyntaxNode): TArray<string>;
begin
  Result := nil;
  case AChild.Kind of
    TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
      Result := TRoutineParts.ChildNames(AChild);
    TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl:
      Result := TArray<string>.Create(AChild.Name);
    TSyntaxKind.Field:
      Result := AChild.Name.Split([',']);
  else
    // Übrige Arten: nichts zu tun.
  end;
end;

/// <summary>Mit class davor statisch, sonst Instanz.</summary>
function ClassOrInstance(const ATokens: TArray<TPascalToken>; AChild: TSyntaxNode): TMemberLevel;
begin
  Result := TMemberLevel.Instance;
  if StartsWithClass(ATokens, AChild) then
  begin
    Result := TMemberLevel.StaticLevel;
  end;
end;

function RoutineLevel(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TMemberLevel;
begin
  if not StartsWithClass(ATokens, AHeader) then
  begin
    Result := TMemberLevel.Instance;
  end
  else if TRoutineParts.HasWord(ATokens, AHeader, ['static']) then
  begin
    Result := TMemberLevel.StaticLevel;
  end
  else
  begin
    Result := TMemberLevel.ClassLevel;
  end;
end;

/// <summary>Art eines Elements des Typrumpfs.</summary>
function LevelOf(const ATokens: TArray<TPascalToken>; AChild: TSyntaxNode): TMemberLevel;
begin
  case AChild.Kind of
    TSyntaxKind.Field:
      Result := TMemberLevel.Instance;
    TSyntaxKind.VarSection, TSyntaxKind.PropertyDecl:
      Result := ClassOrInstance(ATokens, AChild);
    TSyntaxKind.RoutineHeader:
      Result := RoutineLevel(ATokens, AChild);
  else
    // Konstanten und Typen der Klasse.
    Result := TMemberLevel.StaticLevel;
  end;
end;

/// <summary>Art des Mitglieds AName, wie es in ABody deklariert ist; False, wenn ABody es nicht deklariert.</summary>
function DeclaredLevel(const ATokens: TArray<TPascalToken>; ABody: TSyntaxNode; const AName: string;
  out ALevel: TMemberLevel; out AVisibility: TIndexVisibility): Boolean;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
  mVisibility: string;
begin
  mVisibility := '';
  AVisibility := TIndexVisibility.Public;
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    mChild := ABody[mIndex];
    if mChild.Kind = TSyntaxKind.Visibility then
    begin
      mVisibility := LowerCase(mChild.Name);
    end
    else if IndexText(AName, TrimmedNames(MemberNames(mChild))) >= 0 then
    begin
      AVisibility := VisibilityOf(mVisibility);
      ALevel := LevelOf(ATokens, mChild);
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Hat der Typ ABody einen Vorfahren außer TObject (dessen Mitglieder die Datei nicht kennt)?</summary>
function HasUnknownAncestor(ABody: TSyntaxNode): Boolean;
begin
  Result := (ABody.Kind = TSyntaxKind.ClassType) and (ABody.ChildCount > 0) and
    (ABody[0].Kind = TSyntaxKind.TypeReference) and not MatchText(ABody[0].Name, ['TObject', 'System.TObject']);
end;

/// <summary>Art von ANode ohne Namensauflösung; ANames: Namen der Unit.</summary>
function TreeLevel(ATree: TSyntaxTree; const ANames: TArray<string>; ANode: TSyntaxNode;
  out AVisibility: TIndexVisibility): TMemberLevel;
var
  mBody: TSyntaxNode;
  mName: string;
begin
  AVisibility := TIndexVisibility.Public;
  mName := TMethodLookup.HeadName(ANode.Name);
  mBody := OwnerBody(ATree, ANode);
  if (mBody <> nil) and DeclaredLevel(ATree.Tokens, mBody, mName, Result, AVisibility) then
  begin
    Exit;
  end;
  Result := TMemberLevel.NotMember;
  if (ANode.Kind <> TSyntaxKind.TypeReference) and (IndexText(mName, ANames) < 0) and
    not TSystemIntrinsics.IsKnown(mName) and (mBody <> nil) and HasUnknownAncestor(mBody) then
  begin
    Result := TMemberLevel.Unknown;
  end;
end;

function TreeMemberLevel(ATree: TSyntaxTree; const ANames: TArray<string>): TMemberLevelFunc;
var
  mNames: TArray<string>;
begin
  mNames := ANames;
  Result :=
    function(ANode: TSyntaxNode; out AVisibility: TIndexVisibility): TMemberLevel
    begin
      Result := TreeLevel(ATree, mNames, ANode, AVisibility);
    end;
end;

/// <summary>Rumpf des Interfaces AName in der Datei; nil ohne.</summary>
function InterfaceBody(ATree: TSyntaxTree; const AName: string): TSyntaxNode;
var
  mName: string;
begin
  mName := AName;
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.InterfaceType) and (ANode.Parent <> nil) and SameText(ANode.Parent.Name, mName)
      then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

/// <summary>Typname ohne Typargumente: IComparer aus IComparer&lt;T&gt;, Namensraum bleibt.</summary>
function WithoutTypeArgs(const ATypeName: string): string;
begin
  Result := ATypeName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := Trim(Result);
end;

/// <summary>Letzter Teil eines Typnamens ohne Namensraum und Typargumente.</summary>
function LastTypePart(const ATypeName: string): string;
var
  mParts: TArray<string>;
begin
  mParts := WithoutTypeArgs(ATypeName).Split(['.']);
  Result := '';
  if mParts <> nil then
  begin
    Result := mParts[High(mParts)];
  end;
end;

/// <summary>Ist ATypeName IInterface, IUnknown oder IDispatch? Dann sagt AMembership, ob AName dazugehört.
/// </summary>
function BaseInterfaceMembership(const ATypeName, AName: string; out AMembership: TInterfaceMembership): Boolean;
begin
  Result := MatchText(LastTypePart(ATypeName), cBaseInterfaces);
  AMembership := TInterfaceMembership.No;
  if Result and MatchText(AName, cBaseInterfaceMembers) then
  begin
    AMembership := TInterfaceMembership.Yes;
  end;
end;

/// <summary>Vereinigt AMembership des Vorfahren mit dem bisherigen Stand AResult (ja vor unbekannt vor nein).
/// </summary>
function Merged(AResult, AMembership: TInterfaceMembership): TInterfaceMembership;
begin
  Result := AResult;
  if (AMembership = TInterfaceMembership.Yes) or (Result = TInterfaceMembership.No) then
  begin
    Result := AMembership;
  end;
end;

/// <summary>Deklariert die Datei einen Typ AName (gleich welcher Art)?</summary>
function DeclaredInFile(ATree: TSyntaxTree; const AName: string): Boolean;
var
  mName: string;
begin
  mName := AName;
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, mName) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Gehört AName zum Interface ATypeName der Datei oder einem seiner Vorfahren? Unbekannt, wenn die
/// Datei den Typ nicht deklariert.</summary>
function TreeMembership(ATree: TSyntaxTree; const ATypeName, AName: string; ADepth: Integer): TInterfaceMembership;
var
  mBody: TSyntaxNode;
  mIndex: Integer;
begin
  if BaseInterfaceMembership(ATypeName, AName, Result) then
  begin
    Exit;
  end;
  mBody := InterfaceBody(ATree, TMethodLookup.HeadName(ATypeName));
  if mBody = nil then
  begin
    Result := TInterfaceMembership.Unknown;
    if DeclaredInFile(ATree, TMethodLookup.HeadName(ATypeName)) then
    begin
      Result := TInterfaceMembership.No;
    end;
    Exit;
  end;
  Result := TInterfaceMembership.No;
  for mIndex := 0 to mBody.ChildCount - 1 do
  begin
    if (mBody[mIndex].Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl]) and
      SameText(mBody[mIndex].Name, AName) then
    begin
      Exit(TInterfaceMembership.Yes);
    end;
    if (mBody[mIndex].Kind = TSyntaxKind.TypeReference) and (ADepth < cInterfaceDepth) then
    begin
      Result := Merged(Result, TreeMembership(ATree, mBody[mIndex].Name, AName, ADepth + 1));
    end;
  end;
end;

/// <summary>Steht an AOffset ein Eintrag der Vorfahrenliste einer Klasse hinter dem ersten? Dort stehen nur
/// Interfaces.</summary>
function IsLaterHeritage(ATree: TSyntaxTree; AOffset: Integer): Boolean;
var
  mOffset: Integer;
begin
  mOffset := AOffset;
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.StartOffset > mOffset) or (ANode.EndOffset < mOffset) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind = TSyntaxKind.TypeReference) and (ANode.StartOffset = mOffset) and
        (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.ClassType) and
        (ANode.Parent.FindChild(TSyntaxKind.TypeReference) <> ANode) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Bindet AMembership die Methode? Ein unbekannter Typ bindet, wenn er ein Interface sein muss (Eintrag
/// hinter dem ersten) oder so heißt (IFoo).</summary>
function MembershipBinds(ATree: TSyntaxTree; const ATypeName: string; AMembership: TInterfaceMembership;
  AOffset: Integer): Boolean;
begin
  Result := (AMembership = TInterfaceMembership.Yes) or ((AMembership = TInterfaceMembership.Unknown) and
    (TMethodLookup.IsInterfaceName(ATypeName) or IsLaterHeritage(ATree, AOffset)));
end;

function TreeInterfaceMember(ATree: TSyntaxTree): TMethodTypeMemberFunc;
begin
  Result :=
    function(const ATypeName, AName: string; AOffset: Integer): Boolean
    begin
      Result := MembershipBinds(ATree, ATypeName, TreeMembership(ATree, ATypeName, AName, 0), AOffset);
    end;
end;

/// <summary>Bindet die Unit System.SysUtils ein (Helper der RTL)?</summary>
function UsesSysUtils(ATree: TSyntaxTree): Boolean;
var
  mSection: Integer;
  mClause: TSyntaxNode;
begin
  for mSection := 0 to ATree.Root.ChildCount - 1 do
  begin
    mClause := ATree.Root[mSection].FindChild(TSyntaxKind.UsesClause);
    if (mClause <> nil) and MatchText('System.SysUtils', TRoutineParts.ChildNames(mClause)) then
    begin
      Exit(True);
    end;
    if (mClause <> nil) and MatchText('SysUtils', TRoutineParts.ChildNames(mClause)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function RtlHelperFor(ATree: TSyntaxTree; const ATypeName: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := IndexText(ATypeName, cRtlHelpedTypes);
  if (mIndex >= 0) and UsesSysUtils(ATree) then
  begin
    Result := cRtlHelpers[mIndex];
  end;
end;

function TreeVisibleHelper(ATree: TSyntaxTree): TMethodHelperFunc;
begin
  Result :=
    function(const ATypeName: string; AOffset: Integer): string
    begin
      Result := RtlHelperFor(ATree, ATypeName);
    end;
end;

/// <summary>Art eines aufgelösten Mitglieds.</summary>
function SymbolLevel(const AResolved: TResolvedSymbol): TMemberLevel;
var
  mIsClass, mIsStatic: Boolean;
begin
  mIsClass := IndexText('class', AResolved.Directives) >= 0;
  mIsStatic := IndexText('static', AResolved.Directives) >= 0;
  case AResolved.SymbolKind of
    TIndexSymbolKind.Field, TIndexSymbolKind.Property_:
      if mIsClass then
      begin
        Result := TMemberLevel.StaticLevel;
      end
      else
      begin
        Result := TMemberLevel.Instance;
      end;
    TIndexSymbolKind.Method:
      if mIsClass and mIsStatic then
      begin
        Result := TMemberLevel.StaticLevel;
      end
      else if mIsClass then
      begin
        Result := TMemberLevel.ClassLevel;
      end
      else
      begin
        Result := TMemberLevel.Instance;
      end;
    TIndexSymbolKind.Constructor_, TIndexSymbolKind.Variable:
      Result := TMemberLevel.Instance;
    TIndexSymbolKind.Routine:
      Result := TMemberLevel.NotMember;
  else
    // Konstanten, Aufzählungswerte und Typen der Klasse.
    Result := TMemberLevel.StaticLevel;
  end;
end;

function ResolvedLevel(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  out AVisibility: TIndexVisibility): TMemberLevel;
var
  mResolved: TResolvedSymbol;
begin
  AVisibility := TIndexVisibility.Public;
  mResolved := AResolver.Resolve(ATree, AFileName, ANode.StartPos);
  if mResolved.Kind = TResolvedKind.None then
  begin
    Result := TMemberLevel.Unknown;
    if TSystemIntrinsics.IsKnown(TMethodLookup.HeadName(ANode.Name)) and
      not AResolver.MayBeHiddenMember(ATree, AFileName, ANode, mResolved) then
    begin
      Result := TMemberLevel.NotMember;
    end;
  end
  else if (mResolved.Kind <> TResolvedKind.Symbol) or mResolved.Builtin or (mResolved.Container = '') then
  begin
    // Eine freie oder eingebaute Routine verdeckt ein Mitglied eines Vorfahren außerhalb des Index nicht: Close
    // in einem Formular ist TCustomForm.Close, nicht System.Close.
    Result := TMemberLevel.NotMember;
    if AResolver.MayBeHiddenMember(ATree, AFileName, ANode, mResolved) then
    begin
      Result := TMemberLevel.Unknown;
    end;
  end
  else
  begin
    AVisibility := mResolved.Visibility;
    Result := SymbolLevel(mResolved);
  end;
end;

function ResolverMemberLevel(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TMemberLevelFunc;
var
  mFileName: string;
begin
  mFileName := AFileName;
  Result :=
    function(ANode: TSyntaxNode; out AVisibility: TIndexVisibility): TMemberLevel
    begin
      Result := ResolvedLevel(AResolver, ATree, mFileName, ANode, AVisibility);
    end;
end;

function ResolvedMembership(const AQuery: TInterfaceQuery; const ATypeName, AName: string;
  ADepth: Integer): TInterfaceMembership; forward;

/// <summary>Gehört AName zum aufgelösten Interface AInterface (Teile des Namens AParts) oder einem Vorfahren?
/// </summary>
function ResolvedInterfaceMembership(const AQuery: TInterfaceQuery; const AInterface: TResolvedSymbol;
  const AParts: TArray<string>; const AName: string; ADepth: Integer): TInterfaceMembership;
var
  mAncestor: string;
begin
  if AQuery.Resolver.ResolveChain(AQuery.Tree, AQuery.FileName, AParts + [AName], AQuery.Offset).Found then
  begin
    Exit(TInterfaceMembership.Yes);
  end;
  Result := TInterfaceMembership.No;
  if ADepth >= cInterfaceDepth then
  begin
    Exit;
  end;
  for mAncestor in AInterface.Ancestors do
  begin
    Result := Merged(Result, ResolvedMembership(AQuery, mAncestor, AName, ADepth + 1));
  end;
end;

/// <summary>Wie TreeMembership über AResolver (an AOffset sichtbar); Typen, die er nicht kennt, sucht es in der
/// Datei. Eine Klasse bindet nicht.</summary>
function ResolvedMembership(const AQuery: TInterfaceQuery; const ATypeName, AName: string;
  ADepth: Integer): TInterfaceMembership;
var
  mResolved: TResolvedSymbol;
  mParts: TArray<string>;
begin
  if BaseInterfaceMembership(ATypeName, AName, Result) then
  begin
    Exit;
  end;
  mParts := WithoutTypeArgs(ATypeName).Split(['.']);
  mResolved := AQuery.Resolver.ResolveChain(AQuery.Tree, AQuery.FileName, mParts, AQuery.Offset);
  if not mResolved.Found then
  begin
    Result := TreeMembership(AQuery.Tree, ATypeName, AName, ADepth);
  end
  else if mResolved.SymbolKind = TIndexSymbolKind.InterfaceType then
  begin
    Result := ResolvedInterfaceMembership(AQuery, mResolved, mParts, AName, ADepth);
  end
  else
  begin
    Result := TInterfaceMembership.No;
  end;
end;

function ResolverInterfaceMember(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TMethodTypeMemberFunc;
var
  mFileName: string;
begin
  mFileName := AFileName;
  Result :=
    function(const ATypeName, AName: string; AOffset: Integer): Boolean
    var
      mQuery: TInterfaceQuery;
    begin
      mQuery.Resolver := AResolver;
      mQuery.Tree := ATree;
      mQuery.FileName := mFileName;
      mQuery.Offset := AOffset;
      Result := MembershipBinds(ATree, ATypeName, ResolvedMembership(mQuery, ATypeName, AName, 0), AOffset);
    end;
end;

function ResolverVisibleHelper(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const AFallback: TMethodHelperFunc): TMethodHelperFunc;
var
  mFileName: string;
  mFallback: TMethodHelperFunc;
begin
  mFileName := AFileName;
  mFallback := AFallback;
  Result :=
    function(const ATypeName: string; AOffset: Integer): string
    var
      mHelper: TResolvedSymbol;
    begin
      if AResolver.VisibleHelper(ATree, mFileName, ATypeName, AOffset, mHelper) then
      begin
        Exit(mHelper.Name);
      end;
      Result := mFallback(ATypeName, AOffset);
    end;
end;

function ResolverNameVisible(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TMethodNameVisibleFunc;
var
  mFileName: string;
begin
  mFileName := AFileName;
  Result :=
    function(const AName: string; AOffset: Integer): Boolean
    begin
      Result := AResolver.ResolveChain(ATree, mFileName, [AName], AOffset).Found;
    end;
end;

{ TMethodLookup }

class function TMethodLookup.FromTree(ATree: TSyntaxTree): TMethodLookup;
begin
  Result := Default(TMethodLookup);
  if ATree = nil then
  begin
    Exit;
  end;
  Result.Flow := TNestedRoutineLookup.FromTree(ATree).Flow;
  Result.MemberLevel := TreeMemberLevel(ATree, TRoutineParts.UnitNames(ATree.Root));
  Result.InterfaceMember := TreeInterfaceMember(ATree);
  Result.VisibleHelper := TreeVisibleHelper(ATree);
end;

class function TMethodLookup.FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TMethodLookup;
begin
  Result := FromTree(ATree);
  Result.MemberLevel := ResolverMemberLevel(AResolver, ATree, AFileName);
  Result.InterfaceMember := ResolverInterfaceMember(AResolver, ATree, AFileName);
  Result.VisibleHelper := ResolverVisibleHelper(AResolver, ATree, AFileName, Result.VisibleHelper);
  Result.NameVisible := ResolverNameVisible(AResolver, ATree, AFileName);
end;

class function TMethodLookup.HeadName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  if Pos('.', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('.', Result) - 1);
  end;
  Result := Trim(Result);
end;

class function TMethodLookup.IsInterfaceName(const ATypeName: string): Boolean;
var
  mName: string;
begin
  mName := LastTypePart(ATypeName);
  Result := (Length(mName) > 1) and (mName[1] = 'I') and CharInSet(mName[2], ['A'..'Z']);
end;

function TMethodUseScan.IsNameAt(ANode: TSyntaxNode): Boolean;
begin
  if not SameText(ANode.Name, Name) then
  begin
    Exit(False);
  end;
  case ANode.Kind of
    TSyntaxKind.Identifier:
      Result := ANode.StartOffset = Offset;
    TSyntaxKind.MemberAccess:
      Result := ANode.EndOffset = Offset + Length(Name);
  else
    Result := False;
  end;
end;

function TMethodUseScan.Visit(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.StartOffset <= Offset) and (Offset < ANode.EndOffset);
  if not Result then
  begin
    Exit;
  end;
  if ANode.Kind = TSyntaxKind.PropertyDecl then
  begin
    InProperty := True;
  end
  else if (ANode.Kind = TSyntaxKind.InheritedExpr) and SameText(ANode.Name, Name) then
  begin
    InInherited := True;
  end
  else if IsNameAt(ANode) then
  begin
    Found := ANode;
  end;
end;

class function TMethodUseScan.Scan(ATree: TSyntaxTree; AOffset: Integer; const AName: string): TMethodUseScan;
var
  mScan: TMethodUseScan;
begin
  mScan := Default(TMethodUseScan);
  mScan.Offset := AOffset;
  mScan.Name := AName;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := mScan.Visit(ANode);
    end);
  Result := mScan;
end;

end.
