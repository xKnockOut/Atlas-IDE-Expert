unit Atlas.Common.Editing.InlineAccessor;

// Triviale Zugriffsmethode durch Feld ersetzen (#717), Gegenstück zu #682:
//   - Trivial ist ein Getter, der nur "Result := FX;" (auch "Exit(FX);",
//     "GetX := FX;", Self.FX) enthält, und ein Setter, der nur "FX := Value;"
//     enthält; mit TInlineAccessorOptions.EqualityCheck auch
//     "if FX <> Value then FX := Value;". Alles andere (Changed, Invalidate,
//     lokale Variablen) ist nie trivial.
//   - FX ist ein Feld derselben Klasse mit dem Typ der Property.
//   - Ausgeschlossen: virtual/dynamic/override/abstract, message, class-
//     Methoden, überladene und generische Methoden, Properties mit index,
//     Array-Properties, var/out-Parameter, Methoden eines Interfaces der
//     Klasse (auch über eine Methodenzuordnung IFoo.Bar = GetX) und
//     Methoden, die andere Mitglieder der Klasse aufrufen.
//   - Ersetzen: Jede Property der Klasse, die die Methode als read bzw.
//     write nennt, zeigt danach auf das Feld; Deklaration und Rumpf fallen
//     weg, ein leerer Abschnitt ebenso.
// Aufrufe außerhalb der Klasse prüft die Protokollschicht über die
// Referenzsuche; IsOwnReference sagt, welche Fundstellen dabei nicht zählen.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.ClassLayout;

type
  TInlineAccessorOptions = record
    /// <summary>Setter mit Gleichheitsprüfung ("if FX &lt;&gt; Value then FX := Value") gelten als trivial.
    /// </summary>
    EqualityCheck: Boolean;
    class function Default: TInlineAccessorOptions; static;
  end;

  {$SCOPEDENUMS ON}
  TInterfaceAnswer = (No, Yes, Unknown);
  {$SCOPEDENUMS OFF}

  /// <summary>Deklariert das Interface AInterface (oder einer seiner Vorfahren) eine Methode AMethod? Unknown,
  /// wenn AInterface kein bekanntes Interface ist.</summary>
  TInterfaceDeclares = reference to function(const AInterface, AMethod: string): TInterfaceAnswer;

  TTrivialAccessor = record
    ClassName: string;
    /// <summary>Index der Methode in TClassLayout.Members.</summary>
    Member: Integer;
    Name: string;
    IsGetter: Boolean;
    Field: string;
    /// <summary>Properties der Klasse (Indizes), die die Methode als read bzw. write nennen.</summary>
    Properties: TArray<Integer>;
    /// <summary>Name in der Deklaration, Start für die Referenzsuche.</summary>
    NamePos: TTextPosition;
    NameRange: TTextRange;
  end;

  TInlineAccessor = class
  public
    /// <summary>Ist AMember von ALayout eine triviale Zugriffsmethode? Sonst nennt AReason den Grund ('' wenn
    /// AMember gar keine Zugriffsmethode einer Property ist). AInterfaces darf nil sein; dann zählen nur
    /// Interfaces aus derselben Datei, und eine unbekannte Schnittstelle schließt aus.</summary>
    class function Check(ALayout: TClassLayout; AMember: Integer; const AOptions: TInlineAccessorOptions;
      const AInterfaces: TInterfaceDeclares; out AAccessor: TTrivialAccessor; out AReason: string): Boolean;
      static;
    /// <summary>Alle trivialen Zugriffsmethoden der Klasse.</summary>
    class function InClass(ALayout: TClassLayout; const AOptions: TInlineAccessorOptions;
      const AInterfaces: TInterfaceDeclares): TArray<TTrivialAccessor>; static;
    /// <summary>Triviale Zugriffsmethoden an ALine: auf einer Property ihre trivialen Zugriffsmethoden, auf der
    /// Deklaration oder dem Rumpf einer Zugriffsmethode diese. AReason nennt den Grund, wenn ALine eine
    /// Zugriffsmethode trifft, die nicht trivial ist.</summary>
    class function At(ALayout: TClassLayout; ALine: Integer; const AOptions: TInlineAccessorOptions;
      const AInterfaces: TInterfaceDeclares; out AReason: string): TArray<TTrivialAccessor>; static;
    /// <summary>Properties auf die Felder umstellen, Deklarationen und Rümpfe löschen, leere Abschnitte ebenso.
    /// Alle AAccessors gehören zu ALayout.</summary>
    class function Edits(ALayout: TClassLayout; const AAccessors: TArray<TTrivialAccessor>): TArray<TTextEdit>;
      static;
    /// <summary>Zählt die Fundstelle APosition nicht als Aufruf: Deklaration, eigener Rumpf oder read/write
    /// einer Property der Klasse.</summary>
    class function IsOwnReference(ALayout: TClassLayout; const AAccessor: TTrivialAccessor;
      const APosition: TTextPosition): Boolean; static;
    /// <summary>Interface AInterface aus ATree: Yes/No, ob es AMethod deklariert; Unknown, wenn es dort nicht
    /// steht.</summary>
    class function LocalInterfaceDeclares(ATree: TSyntaxTree; const AInterface, AMethod: string): TInterfaceAnswer;
      static;
    /// <summary>Auskunft über Interfaces aus dem Symbolindex samt ihren Vorfahren; nil ohne Index.</summary>
    class function IndexInterfaces(const AIndex: ISymbolIndex): TInterfaceDeclares; static;
    /// <summary>Ist AMethod im Rumpf der Klasse einer Interface-Methode zugeordnet (IFoo.Bar = AMethod)?</summary>
    class function IsResolution(ALayout: TClassLayout; const AMethod: string): Boolean; static;
    /// <summary>Titel der Code-Aktionen.</summary>
    class function Title(const AAccessors: TArray<TTrivialAccessor>): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.MemberTransfer;

{ TInlineAccessorOptions }

class function TInlineAccessorOptions.Default: TInlineAccessorOptions;
begin
  Result.EqualityCheck := True;
end;

function StripGenerics(const AName: string): string;
begin
  Result := Trim(AName);
  if Pos('<', Result) > 0 then
  begin
    Result := Trim(Copy(Result, 1, Pos('<', Result) - 1));
  end;
end;

/// <summary>FX oder Self.FX; '' sonst.</summary>
function FieldRef(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode = nil then
  begin
    Exit;
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := ANode.Name;
  end
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
  begin
    Result := ANode.Name;
  end;
end;

function IsIdentifierNamed(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName);
end;

/// <summary>Anweisungen des Rumpfs; nil, wenn er mehr als Kopf und Block hat (lokale Deklarationen).</summary>
function BodyBlock(ABody: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ABody <> nil) and (ABody.ChildCount = 2) and (ABody[0].Kind = TSyntaxKind.RoutineHeader) and
    (ABody[1].Kind = TSyntaxKind.Block) then
  begin
    Result := ABody[1];
  end;
end;

/// <summary>Feld, das der Getter-Rumpf liefert; '' wenn er mehr tut.</summary>
function GetterField(ABody: TSyntaxNode; const AMethod: string): string;
var
  Block, Statement: TSyntaxNode;
begin
  Result := '';
  Block := BodyBlock(ABody);
  if (Block = nil) or (Block.ChildCount <> 1) then
  begin
    Exit;
  end;
  Statement := Block[0];
  if (Statement.Kind = TSyntaxKind.AssignStatement) and (Statement.ChildCount = 2) and
    (IsIdentifierNamed(Statement[0], 'Result') or IsIdentifierNamed(Statement[0], AMethod)) then
  begin
    Result := FieldRef(Statement[1]);
  end
  else if (Statement.Kind = TSyntaxKind.CallStatement) and (Statement.ChildCount = 1) and
    (Statement[0].Kind = TSyntaxKind.Call) and (Statement[0].ChildCount = 2) and
    IsIdentifierNamed(Statement[0][0], 'Exit') then
  begin
    Result := FieldRef(Statement[0][1]);
  end;
end;

/// <summary>Feld aus "FX := AParam"; '' sonst.</summary>
function AssignedField(AStatement: TSyntaxNode; const AParam: string): string;
begin
  Result := '';
  if (AStatement <> nil) and (AStatement.Kind = TSyntaxKind.AssignStatement) and (AStatement.ChildCount = 2) and
    IsIdentifierNamed(AStatement[1], AParam) then
  begin
    Result := FieldRef(AStatement[0]);
  end;
end;

/// <summary>Name des einzigen Parameters im Kopf AHeader; False bei anderer Zahl.</summary>
function SingleParameter(AHeader: TSyntaxNode; out AParam: string): Boolean;
var
  mParameters: TSyntaxNode;
begin
  AParam := '';
  mParameters := AHeader.FindChild(TSyntaxKind.Parameters);
  Result := (mParameters <> nil) and (mParameters.ChildCount = 1);
  if Result then
  begin
    AParam := mParameters[0].Name;
  end;
end;

/// <summary>Vergleicht ACondition (A &lt;&gt; B) das Feld AField mit dem Parameter AParam?</summary>
function ComparesWith(ACondition: TSyntaxNode; const AField, AParam: string): Boolean;
var
  mLeft, mRight: string;
begin
  mLeft := FieldRef(ACondition[0]);
  mRight := FieldRef(ACondition[1]);
  Result := (SameText(mLeft, AField) and SameText(mRight, AParam)) or
    (SameText(mLeft, AParam) and SameText(mRight, AField));
end;

/// <summary>Feld aus "if FX &lt;&gt; AParam then FX := AParam"; '' sonst.</summary>
function GuardedField(AStatement: TSyntaxNode; const AParam: string): string;
var
  mCondition, mInner: TSyntaxNode;
begin
  Result := '';
  if (AStatement.Kind <> TSyntaxKind.IfStatement) or (AStatement.ChildCount <> 2) then
  begin
    Exit;
  end;
  mCondition := AStatement[0];
  if (mCondition.Kind <> TSyntaxKind.BinaryExpr) or (mCondition.Name <> '<>') or (mCondition.ChildCount <> 2) then
  begin
    Exit;
  end;
  mInner := AStatement[1];
  if (mInner.Kind = TSyntaxKind.Block) and (mInner.ChildCount = 1) then
  begin
    mInner := mInner[0];
  end;
  Result := AssignedField(mInner, AParam);
  if (Result <> '') and not ComparesWith(mCondition, Result, AParam) then
  begin
    Result := '';
  end;
end;

/// <summary>Feld, das der Setter-Rumpf setzt; '' wenn er mehr tut.</summary>
function SetterField(ABody: TSyntaxNode; AEqualityCheck: Boolean): string;
var
  mBlock, mStatement: TSyntaxNode;
  mParam: string;
begin
  Result := '';
  mBlock := BodyBlock(ABody);
  // Der Rumpf darf den Parameter anders nennen als die Deklaration.
  if (mBlock = nil) or (mBlock.ChildCount <> 1) or not SingleParameter(ABody[0], mParam) then
  begin
    Exit;
  end;
  mStatement := mBlock[0];
  if mStatement.Kind = TSyntaxKind.AssignStatement then
  begin
    Result := AssignedField(mStatement, mParam);
  end
  else if AEqualityCheck then
  begin
    Result := GuardedField(mStatement, mParam);
  end;
end;

/// <summary>Enden die Tokens ASignificant bis ALast mit "Name.Name"?</summary>
function EndsQualifiedName(const ATokens: TArray<TPascalToken>; const ASignificant: TArray<Integer>;
  ALast: Integer): Boolean;
begin
  Result := (ATokens[ASignificant[ALast]].Kind = TPascalTokenKind.Identifier) and
    ATokens[ASignificant[ALast - 1]].IsSymbol('.') and
    (ATokens[ASignificant[ALast - 2]].Kind = TPascalTokenKind.Identifier);
end;

/// <summary>Steht an APos "= AMethod" hinter "IFoo.Bar"?</summary>
function ResolvesTo(const ATokens: TArray<TPascalToken>; const ASignificant: TArray<Integer>; APos: Integer;
  const AMethod: string): Boolean;
begin
  Result := ATokens[ASignificant[APos]].IsSymbol('=') and (APos + 1 <= High(ASignificant)) and
    SameText(ATokens[ASignificant[APos + 1]].Text, AMethod) and EndsQualifiedName(ATokens, ASignificant, APos - 1);
end;

/// <summary>Methodenzuordnung "IFoo.Bar = AMethod;" in der Klasse?</summary>
function HasResolution(ALayout: TClassLayout; const AMethod: string): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mNext: Integer;
  mSignificant: TArray<Integer>;
begin
  mTokens := ALayout.Tree.Tokens;
  mSignificant := nil;
  mIndex := TokenIndexAt(mTokens, ALayout.ClassNode.StartOffset);
  while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < ALayout.ClassNode.EndOffset) do
  begin
    if not IsTrivia(mTokens[mIndex]) then
    begin
      mSignificant := mSignificant + [mIndex];
    end;
    Inc(mIndex);
  end;
  for mNext := 4 to High(mSignificant) do
  begin
    if ResolvesTo(mTokens, mSignificant, mNext, AMethod) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Bereich des Namens AName im Kopf ANode.</summary>
function NameRangeIn(ALayout: TClassLayout; ANode: TSyntaxNode; const AName: string; out ARange: TTextRange):
  Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
begin
  Tokens := ALayout.Tree.Tokens;
  Index := TokenIndexAt(Tokens, ANode.StartOffset);
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < ANode.EndOffset) do
  begin
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AName) then
    begin
      ARange := TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos);
      Exit(True);
    end;
    Inc(Index);
  end;
  Result := False;
end;

function SameType(const A, B: string): Boolean;
begin
  Result := (A <> '') and SameText(CollapseSpace(A), CollapseSpace(B));
end;

{ TInlineAccessor }

class function TInlineAccessor.LocalInterfaceDeclares(ATree: TSyntaxTree; const AInterface,
  AMethod: string): TInterfaceAnswer;
var
  Found: TSyntaxNode;
  Name: string;
  Declared: Boolean;
begin
  Found := nil;
  Name := StripGenerics(AInterface);
  if Pos('.', Name) > 0 then
  begin
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  end;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (Found = nil) and (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(StripGenerics(ANode.Name), Name) and
        (ANode.FindChild(TSyntaxKind.InterfaceType) <> nil) then
      begin
        Found := ANode;
      end;
      Result := Found = nil;
    end);
  if Found = nil then
  begin
    Exit(TInterfaceAnswer.Unknown);
  end;
  Declared := False;
  Found.FindChild(TSyntaxKind.InterfaceType).Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.RoutineHeader) and SameText(ANode.Name, AMethod) then
      begin
        Declared := True;
      end;
      Result := not Declared;
    end);
  if Declared then
  begin
    Exit(TInterfaceAnswer.Yes);
  end;
  Result := TInterfaceAnswer.No;
end;

/// <summary>Properties, die AName als read- bzw. write-Methode nennen; AReads und AWrites zählen sie.</summary>
function AccessingProperties(ALayout: TClassLayout; const AName: string; out AReads, AWrites: Integer):
  TArray<Integer>;
var
  mIndex: Integer;
  mProp: TClassMember;
begin
  Result := nil;
  AReads := 0;
  AWrites := 0;
  for mIndex := 0 to High(ALayout.Members) do
  begin
    mProp := ALayout.Members[mIndex];
    if mProp.Kind <> TClassMemberKind.Property_ then
    begin
      Continue;
    end;
    if SameText(mProp.ReadAccessor, AName) then
    begin
      Inc(AReads);
      Result := Result + [mIndex];
    end
    else if SameText(mProp.WriteAccessor, AName) then
    begin
      Inc(AWrites);
      Result := Result + [mIndex];
    end;
  end;
end;

/// <summary>Warum die Methode AMember keine einfache Zugriffsmethode sein kann (ABoth: Properties lesen und
/// schreiben über sie); '' wenn nichts dagegen spricht.</summary>
function MethodIssue(ALayout: TClassLayout; const AMember: TClassMember; ABoth: Boolean): string;
begin
  Result := '';
  if ABoth then
  begin
    Result := Format('%s ist zugleich Getter und Setter.', [AMember.Name]);
  end
  else if AMember.Kind <> TClassMemberKind.Method then
  begin
    Result := Format('%s ist keine gewöhnliche Methode.', [AMember.Name]);
  end
  else if AMember.IsVirtual or AMember.HasDirective('message') then
  begin
    Result := Format('%s ist virtuell (virtual, dynamic, override oder abstract).', [AMember.Name]);
  end
  else if AMember.IsClassMember then
  begin
    Result := Format('%s ist eine class-Methode.', [AMember.Name]);
  end
  else if AMember.IsGeneric or (Length(ALayout.Find(AMember.Name)) > 1) then
  begin
    Result := Format('%s ist überladen oder generisch.', [AMember.Name]);
  end;
end;

/// <summary>Warum die Property AProp nicht direkt auf ein Feld zeigen kann; '' wenn nichts dagegen spricht.
/// </summary>
function PropertyIssue(const AProp: TClassMember; const AMethod: string): string;
begin
  Result := '';
  if AProp.IndexSpecifier <> '' then
  begin
    Result := Format('Property %s hat einen index; %s braucht ihn als Parameter.', [AProp.Name, AMethod]);
  end
  else if (AProp.Parameters <> '') or AProp.IsClassMember or AProp.IsRedeclaration then
  begin
    Result := Format('Property %s ist eine Array-, class- oder umdeklarierte Property.', [AProp.Name]);
  end
  else if SameText(AProp.StoredSpecifier, AMethod) then
  begin
    Result := Format('Property %s nennt %s auch bei stored.', [AProp.Name, AMethod]);
  end;
end;

/// <summary>Prüft die Properties AProperties zur Methode AMethod; AType ist ihr gemeinsamer Typ.</summary>
function PropertiesIssue(ALayout: TClassLayout; const AProperties: TArray<Integer>; const AMethod: string;
  out AType: string): string;
var
  mIndex: Integer;
  mProp: TClassMember;
begin
  AType := '';
  for mIndex in AProperties do
  begin
    mProp := ALayout.Members[mIndex];
    Result := PropertyIssue(mProp, AMethod);
    if (Result = '') and (AType <> '') and not SameType(AType, mProp.TypeName) then
    begin
      Result := Format('Die Properties zu %s haben verschiedene Typen.', [AMethod]);
    end;
    if Result <> '' then
    begin
      Exit;
    end;
    AType := mProp.TypeName;
  end;
  Result := '';
end;

/// <summary>Passt die Signatur von AMember als Getter bzw. Setter zum Property-Typ AType?</summary>
function SignatureIssue(const AMember: TClassMember; AIsGetter: Boolean; const AType: string): string;
begin
  Result := '';
  if AIsGetter then
  begin
    if not AMember.IsFunction or (AMember.Parameters <> '') or not SameType(AMember.TypeName, AType) then
    begin
      Result := Format('%s passt nicht als Getter zur Property.', [AMember.Name]);
    end;
  end
  else if AMember.IsFunction or (Length(AMember.ParameterTypes) <> 1) or
    not SameType(AMember.ParameterTypes[0], AType) or StartsText('var ', AMember.Parameters) or
    StartsText('out ', AMember.Parameters) then
  begin
    Result := Format('%s passt nicht als Setter zur Property.', [AMember.Name]);
  end;
end;

/// <summary>Ist AMember ein Feld der Instanz?</summary>
function IsInstanceField(const AMember: TClassMember): Boolean;
begin
  Result := (AMember.Kind = TClassMemberKind.Field) and not AMember.IsClassMember;
end;

/// <summary>Prüft das Feld AField, das der Rumpf von AMember liest bzw. setzt; AFieldName ist dann sein deklarierter
/// Name.</summary>
function FieldIssue(ALayout: TClassLayout; const AMember: TClassMember; const AField, AType: string;
  out AFieldName: string): string;
var
  mFields: TArray<Integer>;
begin
  Result := '';
  AFieldName := '';
  if AMember.Body = nil then
  begin
    Result := Format('Der Rumpf von %s steht nicht in dieser Unit.', [AMember.Name]);
  end
  else if AField = '' then
  begin
    Result := Format('%s tut mehr, als ein Feld zu lesen bzw. zu setzen.', [AMember.Name]);
  end
  else
  begin
    mFields := ALayout.Find(AField);
    if (Length(mFields) <> 1) or not IsInstanceField(ALayout.Members[mFields[0]]) then
    begin
      Result := Format('%s ist kein Feld von %s.', [AField, ALayout.Name]);
    end
    else if not SameType(ALayout.Members[mFields[0]].TypeName, AType) then
    begin
      Result := Format('%s hat einen anderen Typ als die Property.', [AField]);
    end
    else
    begin
      AFieldName := ALayout.Members[mFields[0]].Name;
    end;
  end;
end;

/// <summary>Verbietet der Vorfahr AIndex der Klasse, AMethod zu entfernen (Methode eines Interfaces)?</summary>
function AncestorIssue(ALayout: TClassLayout; AIndex: Integer; const AMethod: string;
  const AInterfaces: TInterfaceDeclares): string;
var
  mAnswer: TInterfaceAnswer;
begin
  Result := '';
  mAnswer := TInlineAccessor.LocalInterfaceDeclares(ALayout.Tree, ALayout.Ancestors[AIndex], AMethod);
  if (mAnswer = TInterfaceAnswer.Unknown) and Assigned(AInterfaces) then
  begin
    mAnswer := AInterfaces(ALayout.Ancestors[AIndex], AMethod);
  end;
  if mAnswer = TInterfaceAnswer.Yes then
  begin
    Result := Format('%s implementiert eine Methode von %s.', [AMethod, ALayout.Ancestors[AIndex]]);
  end
  // Nur der erste Eintrag kann eine Klasse sein; ein unbekanntes Interface schließt aus.
  else if (mAnswer = TInterfaceAnswer.Unknown) and (AIndex > 0) then
  begin
    Result := Format('Ob %s eine Methode von %s implementiert, ist unbekannt.', [AMethod,
      ALayout.Ancestors[AIndex]]);
  end;
end;

/// <summary>Methoden eines Interfaces der Klasse müssen bleiben.</summary>
function InterfaceIssue(ALayout: TClassLayout; const AMethod: string; const AInterfaces: TInterfaceDeclares):
  string;
var
  mIndex: Integer;
begin
  if HasResolution(ALayout, AMethod) then
  begin
    Exit(Format('%s ist einer Interface-Methode zugeordnet.', [AMethod]));
  end;
  for mIndex := 0 to High(ALayout.Ancestors) do
  begin
    Result := AncestorIssue(ALayout, mIndex, AMethod, AInterfaces);
    if Result <> '' then
    begin
      Exit;
    end;
  end;
  Result := '';
end;

/// <summary>Benutzt die Klasse AMember außer in seinen Properties AProperties?</summary>
function UserIssue(ALayout: TClassLayout; AMember: Integer; const AProperties: TArray<Integer>): string;
var
  mUser: Integer;
begin
  for mUser in ALayout.UsersOf(AMember) do
  begin
    if not TMemberTransfer.Has(AProperties, mUser) then
    begin
      Exit(Format('%s wird in der Klasse benutzt (%s).', [ALayout.Members[AMember].Name,
        ALayout.Members[mUser].Name]));
    end;
  end;
  Result := '';
end;

/// <summary>Feld, das der Rumpf von AMember liest (Getter) bzw. setzt (Setter); '' wenn er mehr tut.</summary>
function AccessedField(const AMember: TClassMember; AIsGetter, AEqualityCheck: Boolean): string;
begin
  if AIsGetter then
  begin
    Result := GetterField(AMember.Body, AMember.Name);
  end
  else
  begin
    Result := SetterField(AMember.Body, AEqualityCheck);
  end;
end;

class function TInlineAccessor.Check(ALayout: TClassLayout; AMember: Integer;
  const AOptions: TInlineAccessorOptions; const AInterfaces: TInterfaceDeclares; out AAccessor: TTrivialAccessor;
  out AReason: string): Boolean;
var
  mMember: TClassMember;
  mReads, mWrites: Integer;
  mType: string;
begin
  AReason := '';
  AAccessor := Default(TTrivialAccessor);
  mMember := ALayout.Members[AMember];
  if not mMember.IsMethod then
  begin
    Exit(False);
  end;
  AAccessor.ClassName := ALayout.Name;
  AAccessor.Member := AMember;
  AAccessor.Name := mMember.Name;
  AAccessor.Properties := AccessingProperties(ALayout, mMember.Name, mReads, mWrites);
  if AAccessor.Properties = nil then
  begin
    Exit(False);
  end;
  AAccessor.IsGetter := mReads > 0;
  AReason := MethodIssue(ALayout, mMember, (mReads > 0) and (mWrites > 0));
  if AReason = '' then
  begin
    AReason := PropertiesIssue(ALayout, AAccessor.Properties, mMember.Name, mType);
  end;
  if AReason = '' then
  begin
    AReason := SignatureIssue(mMember, AAccessor.IsGetter, mType);
  end;
  if AReason = '' then
  begin
    AReason := FieldIssue(ALayout, mMember, AccessedField(mMember, AAccessor.IsGetter, AOptions.EqualityCheck), mType,
      AAccessor.Field);
  end;
  if AReason = '' then
  begin
    AReason := InterfaceIssue(ALayout, mMember.Name, AInterfaces);
  end;
  if AReason = '' then
  begin
    AReason := UserIssue(ALayout, AMember, AAccessor.Properties);
  end;
  if (AReason = '') and not NameRangeIn(ALayout, mMember.Node, mMember.Name, AAccessor.NameRange) then
  begin
    AReason := Format('Der Name von %s ist nicht zu finden.', [mMember.Name]);
  end;
  Result := AReason = '';
  if Result then
  begin
    AAccessor.NamePos := AAccessor.NameRange.StartPos;
  end;
end;

class function TInlineAccessor.InClass(ALayout: TClassLayout; const AOptions: TInlineAccessorOptions;
  const AInterfaces: TInterfaceDeclares): TArray<TTrivialAccessor>;
var
  Index: Integer;
  Accessor: TTrivialAccessor;
  Reason: string;
begin
  Result := nil;
  for Index := 0 to High(ALayout.Members) do
  begin
    if ALayout.Members[Index].IsMethod and Check(ALayout, Index, AOptions, AInterfaces, Accessor, Reason) then
    begin
      Result := Result + [Accessor];
    end;
  end;
end;

/// <summary>Mitglied in Zeile ALine bzw. Methode, in deren Rumpf ALine liegt; -1 ohne.</summary>
function MemberAt(ALayout: TClassLayout; ALine: Integer): Integer;
var
  mIndex: Integer;
  mMember: TClassMember;
begin
  Result := ALayout.MemberAtLine(ALine);
  if Result >= 0 then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ALayout.Members) do
  begin
    mMember := ALayout.Members[mIndex];
    if mMember.IsMethod and (mMember.Body <> nil) and (ALine >= mMember.BodyFirstLine) and
      (ALine <= mMember.BodyLastLine) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Namen der read- und write-Methode der Property AProperty.</summary>
function AccessorNames(const AProperty: TClassMember): TArray<string>;
begin
  Result := nil;
  if AProperty.ReadAccessor <> '' then
  begin
    Result := Result + [AProperty.ReadAccessor];
  end;
  if AProperty.WriteAccessor <> '' then
  begin
    Result := Result + [AProperty.WriteAccessor];
  end;
end;

/// <summary>Einfache Zugriffsmethoden unter den Methoden ANames; AReason: Grund der ersten, die keine ist.</summary>
function TrivialAmong(ALayout: TClassLayout; const ANames: TArray<string>; const AOptions: TInlineAccessorOptions;
  const AInterfaces: TInterfaceDeclares; out AReason: string): TArray<TTrivialAccessor>;
var
  mName, mReason: string;
  mIndex: Integer;
  mAccessor: TTrivialAccessor;
begin
  Result := nil;
  AReason := '';
  for mName in ANames do
  begin
    for mIndex in ALayout.Find(mName) do
    begin
      if not ALayout.Members[mIndex].IsMethod then
      begin
        Continue;
      end;
      if TInlineAccessor.Check(ALayout, mIndex, AOptions, AInterfaces, mAccessor, mReason) then
      begin
        Result := Result + [mAccessor];
      end
      else if AReason = '' then
      begin
        AReason := mReason;
      end;
    end;
  end;
end;

class function TInlineAccessor.At(ALayout: TClassLayout; ALine: Integer; const AOptions: TInlineAccessorOptions;
  const AInterfaces: TInterfaceDeclares; out AReason: string): TArray<TTrivialAccessor>;
var
  mHit: Integer;
  mMember: TClassMember;
  mAccessor: TTrivialAccessor;
begin
  Result := nil;
  AReason := '';
  mHit := MemberAt(ALayout, ALine);
  if mHit < 0 then
  begin
    Exit;
  end;
  mMember := ALayout.Members[mHit];
  if mMember.IsMethod then
  begin
    if Check(ALayout, mHit, AOptions, AInterfaces, mAccessor, AReason) then
    begin
      Result := [mAccessor];
    end;
  end
  else if mMember.Kind = TClassMemberKind.Property_ then
  begin
    Result := TrivialAmong(ALayout, AccessorNames(mMember), AOptions, AInterfaces, AReason);
    if Result <> nil then
    begin
      AReason := '';
    end;
  end;
end;

class function TInlineAccessor.Edits(ALayout: TClassLayout;
  const AAccessors: TArray<TTrivialAccessor>): TArray<TTextEdit>;
var
  Accessor: TTrivialAccessor;
  Index: Integer;
  Removed: TArray<Integer>;
  Edit: TTextEdit;
  Keyword: string;
begin
  Result := nil;
  Removed := nil;
  for Accessor in AAccessors do
  begin
    Keyword := 'write';
    if Accessor.IsGetter then
    begin
      Keyword := 'read';
    end;
    for Index in Accessor.Properties do
    begin
      if TClassEdits.ReplaceAccessor(ALayout, Index, Keyword, Accessor.Field, Edit) then
      begin
        Result := Result + [Edit];
      end;
    end;
    Removed := Removed + [Accessor.Member];
  end;
  Result := Result + TClassEdits.DeleteMembers(ALayout, Removed, True) +
    TMemberTransfer.EmptiedSections(ALayout, Removed);
end;

class function TInlineAccessor.IsOwnReference(ALayout: TClassLayout; const AAccessor: TTrivialAccessor;
  const APosition: TTextPosition): Boolean;
var
  Member: TClassMember;
  Index: Integer;
begin
  Member := ALayout.Members[AAccessor.Member];
  if (APosition.Line >= Member.FirstLine) and (APosition.Line <= Member.LastLine) then
  begin
    Exit(True);
  end;
  if (Member.Body <> nil) and (APosition.Line >= Member.BodyFirstLine) and (APosition.Line <= Member.BodyLastLine) then
  begin
    Exit(True);
  end;
  for Index in AAccessor.Properties do
  begin
    if (APosition.Line >= ALayout.Members[Index].FirstLine) and (APosition.Line <= ALayout.Members[Index].LastLine) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Name des Interfaces ohne generische Argumente und Unit (System.IFoo&lt;T&gt; wird IFoo).</summary>
function ShortInterfaceName(const AName: string): string;
begin
  Result := StripGenerics(AName);
  if Pos('.', Result) > 0 then
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

function IndexDeclares(const AIndex: ISymbolIndex; const AName, AMethod: string; ADepth: Integer): TInterfaceAnswer;
  forward;

/// <summary>Deklariert ein Vorfahr des Interfaces AName (Kurzname) im Index AMethod? AKnown: Kennt der Index
/// AName?</summary>
function AncestorsDeclare(const AIndex: ISymbolIndex; const AName, AMethod: string; ADepth: Integer;
  out AKnown: Boolean): TInterfaceAnswer;
var
  mLocation: TSymbolLocation;
  mAncestor: string;
  mAnswer: TInterfaceAnswer;
begin
  AKnown := False;
  Result := TInterfaceAnswer.No;
  for mLocation in AIndex.FindSymbols(AName) do
  begin
    if (mLocation.Symbol.Kind <> TIndexSymbolKind.InterfaceType) or (mLocation.Symbol.Container <> '') then
    begin
      Continue;
    end;
    AKnown := True;
    for mAncestor in mLocation.Symbol.Ancestors do
    begin
      mAnswer := IndexDeclares(AIndex, mAncestor, AMethod, ADepth + 1);
      if mAnswer = TInterfaceAnswer.Yes then
      begin
        Exit(TInterfaceAnswer.Yes);
      end;
      if mAnswer = TInterfaceAnswer.Unknown then
      begin
        Result := TInterfaceAnswer.Unknown;
      end;
    end;
  end;
end;

/// <summary>Deklariert das Interface AName (Kurzname) im Index selbst eine Methode AMethod?</summary>
function DeclaresMethod(const AIndex: ISymbolIndex; const AName, AMethod: string): Boolean;
var
  mLocation: TSymbolLocation;
begin
  for mLocation in AIndex.FindSymbols(AMethod) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.Method) and SameText(mLocation.Symbol.Container, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Interface AName im Index: deklariert es AMethod, auch über Vorfahren? ADepth begrenzt Kreise.</summary>
function IndexDeclares(const AIndex: ISymbolIndex; const AName, AMethod: string; ADepth: Integer): TInterfaceAnswer;
var
  mName: string;
  mKnown: Boolean;
begin
  mName := ShortInterfaceName(AName);
  // Die Methoden von IInterface, IUnknown und IDispatch heißen nie wie eine Zugriffsmethode.
  if MatchText(mName, ['IInterface', 'IUnknown', 'IDispatch']) then
  begin
    Result := TInterfaceAnswer.No;
  end
  else if ADepth > 10 then
  begin
    Result := TInterfaceAnswer.Unknown;
  end
  else
  begin
    Result := AncestorsDeclare(AIndex, mName, AMethod, ADepth, mKnown);
    if not mKnown then
    begin
      Result := TInterfaceAnswer.Unknown;
    end
    else if (Result <> TInterfaceAnswer.Yes) and DeclaresMethod(AIndex, mName, AMethod) then
    begin
      Result := TInterfaceAnswer.Yes;
    end;
  end;
end;

class function TInlineAccessor.IndexInterfaces(const AIndex: ISymbolIndex): TInterfaceDeclares;
begin
  Result := nil;
  if AIndex = nil then
  begin
    Exit;
  end;
  Result :=
    function(const AInterface, AMethod: string): TInterfaceAnswer
    begin
      Result := IndexDeclares(AIndex, AInterface, AMethod, 0);
    end;
end;

class function TInlineAccessor.Title(const AAccessors: TArray<TTrivialAccessor>): string;
begin
  if Length(AAccessors) = 1 then
  begin
    Result := Format('Zugriffsmethode %s durch Feld %s ersetzen', [AAccessors[0].Name, AAccessors[0].Field]);
  end
  else
  begin
    Result := Format('Zugriffsmethoden %s und %s durch Feld ersetzen', [AAccessors[0].Name, AAccessors[1].Name]);
  end;
end;

class function TInlineAccessor.IsResolution(ALayout: TClassLayout; const AMethod: string): Boolean;
begin
  Result := HasResolution(ALayout, AMethod);
end;

end.
