unit Atlas.Common.Editing.MethodWithoutSelf.Lookup;

// Namensauflösung für „Methode ohne Self“ (#686): Welche Namen im Rumpf
// Instanzmitglieder sind, ob ein Interface ein Mitglied hat, welcher Helper
// für einen Typ sichtbar ist und ob ein Name schon sichtbar ist. Mit
// Namensauflösung über TNameResolver, sonst über die Klasse in der Datei.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.PromoteVariable;

type
{$SCOPEDENUMS ON}
  /// <summary>Art eines Namens im Rumpf einer Methode.</summary>
  TMemberLevel = (NotMember, Instance, ClassLevel, StaticLevel, Unknown);
{$SCOPEDENUMS OFF}

  /// <summary>Art des Bezeichners bzw. Typnamens ANode im Rumpf; AVisibility bei Mitgliedern.</summary>
  TMemberLevelFunc = reference to function(ANode: TSyntaxNode; out AVisibility: TIndexVisibility): TMemberLevel;
  /// <summary>Hat das Interface ATypeName ein Mitglied AName (sichtbar an AOffset)?</summary>
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
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.SystemIntrinsics,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineParts,
  Atlas.Common.Editing.NestedRoutines;

const
  // Helper der RTL (System.SysUtils, System.Character), falls der Index sie nicht kennt.
  RtlHelpedTypes: array[0..14] of string = ('string', 'UnicodeString', 'Integer', 'Cardinal', 'Int64', 'UInt64',
    'NativeInt', 'NativeUInt', 'Byte', 'Word', 'ShortInt', 'SmallInt', 'Double', 'Single', 'Boolean');
  RtlHelpers: array[0..14] of string = ('TStringHelper', 'TStringHelper', 'TIntegerHelper', 'TCardinalHelper',
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
  mIndex := TRoutineBody.PreviousToken(ATokens, mIndex);
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

function InterfaceHasMember(ATree: TSyntaxTree; const ATypeName, AName: string): Boolean;
var
  mBody: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mBody := InterfaceBody(ATree, TMethodLookup.HeadName(ATypeName));
  if mBody = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mBody.ChildCount - 1 do
  begin
    if (mBody[mIndex].Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl]) and
      SameText(mBody[mIndex].Name, AName) then
    begin
      Exit(True);
    end;
  end;
end;

function TreeInterfaceMember(ATree: TSyntaxTree): TMethodTypeMemberFunc;
begin
  Result :=
    function(const ATypeName, AName: string; AOffset: Integer): Boolean
    begin
      Result := InterfaceHasMember(ATree, ATypeName, AName);
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
  mIndex := IndexText(ATypeName, RtlHelpedTypes);
  if (mIndex >= 0) and UsesSysUtils(ATree) then
  begin
    Result := RtlHelpers[mIndex];
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
    if TSystemIntrinsics.IsKnown(TMethodLookup.HeadName(ANode.Name)) then
    begin
      Result := TMemberLevel.NotMember;
    end;
  end
  else if (mResolved.Kind <> TResolvedKind.Symbol) or mResolved.Builtin or (mResolved.Container = '') then
  begin
    Result := TMemberLevel.NotMember;
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

function ResolverInterfaceMember(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const AFallback: TMethodTypeMemberFunc): TMethodTypeMemberFunc;
var
  mFileName: string;
  mFallback: TMethodTypeMemberFunc;
begin
  mFileName := AFileName;
  mFallback := AFallback;
  Result :=
    function(const ATypeName, AName: string; AOffset: Integer): Boolean
    var
      mResolved: TResolvedSymbol;
    begin
      mResolved := AResolver.ResolveChain(ATree, mFileName, TMethodLookup.HeadName(ATypeName).Split(['.']), AOffset);
      if not mResolved.Found then
      begin
        Exit(mFallback(ATypeName, AName, AOffset));
      end;
      Result := (mResolved.SymbolKind = TIndexSymbolKind.InterfaceType) and AResolver.ResolveChain(ATree,
        mFileName, [TMethodLookup.HeadName(ATypeName), AName], AOffset).Found;
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
  Result.InterfaceMember := ResolverInterfaceMember(AResolver, ATree, AFileName, Result.InterfaceMember);
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

end.
