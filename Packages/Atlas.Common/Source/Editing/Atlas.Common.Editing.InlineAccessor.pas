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
  Atlas.Common.Editing.MemberTransfer,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Pascal.TokenCursor;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditingInlineAccessorText = (IsBothGetterAndSetter, IsNotAnOrdinaryMethod, IsVirtualVirtualDynamicOverride,
    IsAClassMethod, IsOverloadedOrGeneric, PropertyHasAnIndexNeeds, PropertyIsAnArrayClass,
    ThePropertiesOfHaveDifferent, DoesNotFitAsGetter, DoesNotFitAsSetter, TheBodyOfIsNot, IsNotAFieldOf,
    HasADifferentTypeThan, ImplementsAMethodOf, WhetherImplementsAMethodOf, IsMappedToAnInterface, IsUsedInTheClass,
    TheNameOfCannotBe, ReplaceAccessorsAndWithThe, PropertyAlsoNamesForStored, DoesMoreThanReadOr,
    ReplaceAccessorWithField);

const
  cTexts: array[TEditingInlineAccessorText] of TAtlasText = (
    (De: '%s ist zugleich Getter und Setter.'; En: '%s is both getter and setter.'),
    (De: '%s ist keine gewöhnliche Methode.'; En: '%s is not an ordinary method.'),
    (De: '%s ist virtuell (virtual, dynamic, override oder abstract).';
     En: '%s is virtual (virtual, dynamic, override or abstract).'),
    (De: '%s ist eine class-Methode.'; En: '%s is a class method.'),
    (De: '%s ist überladen oder generisch.'; En: '%s is overloaded or generic.'),
    (De: 'Property %s hat einen index; %s braucht ihn als Parameter.';
     En: 'Property %s has an index; %s needs it as a parameter.'),
    (De: 'Property %s ist eine Array-, class- oder umdeklarierte Property.';
     En: 'Property %s is an array, class or redeclared property.'),
    (De: 'Die Properties zu %s haben verschiedene Typen.'; En: 'The properties of %s have different types.'),
    (De: '%s passt nicht als Getter zur Property.'; En: '%s does not fit as getter of the property.'),
    (De: '%s passt nicht als Setter zur Property.'; En: '%s does not fit as setter of the property.'),
    (De: 'Der Rumpf von %s steht nicht in dieser Unit.'; En: 'The body of %s is not in this unit.'),
    (De: '%s ist kein Feld von %s.'; En: '%s is not a field of %s.'),
    (De: '%s hat einen anderen Typ als die Property.'; En: '%s has a different type than the property.'),
    (De: '%s implementiert eine Methode von %s.'; En: '%s implements a method of %s.'),
    (De: 'Ob %s eine Methode von %s implementiert, ist unbekannt.';
     En: 'Whether %s implements a method of %s is unknown.'),
    (De: '%s ist einer Interface-Methode zugeordnet.'; En: '%s is mapped to an interface method.'),
    (De: '%s wird in der Klasse benutzt (%s).'; En: '%s is used in the class (%s).'),
    (De: 'Der Name von %s ist nicht zu finden.'; En: 'The name of %s cannot be found.'),
    (De: 'Zugriffsmethoden %s und %s durch Feld ersetzen'; En: 'Replace accessors %s and %s with the field'),
    (De: 'Property %s nennt %s auch bei stored.'; En: 'Property %s also names %s for stored.'),
    (De: '%s tut mehr, als ein Feld zu lesen bzw. zu setzen.'; En: '%s does more than read or set a field.'),
    (De: 'Zugriffsmethode %s durch Feld %s ersetzen'; En: 'Replace accessor %s with field %s'));

{$SCOPEDENUMS OFF}

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
  mBlock, mStatement: TSyntaxNode;
begin
  Result := '';
  mBlock := BodyBlock(ABody);
  if (mBlock = nil) or (mBlock.ChildCount <> 1) then
  begin
    Exit;
  end;
  mStatement := mBlock[0];
  if (mStatement.Kind = TSyntaxKind.AssignStatement) and (mStatement.ChildCount = 2) and
    (IsIdentifierNamed(mStatement[0], 'Result') or IsIdentifierNamed(mStatement[0], AMethod)) then
  begin
    Result := FieldRef(mStatement[1]);
  end
  else if (mStatement.Kind = TSyntaxKind.CallStatement) and (mStatement.ChildCount = 1) and
    (mStatement[0].Kind = TSyntaxKind.Call) and (mStatement[0].ChildCount = 2) and
    IsIdentifierNamed(mStatement[0][0], 'Exit') then
  begin
    Result := FieldRef(mStatement[0][1]);
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
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  mTokens := ALayout.Tree.Tokens;
  mIndex := TokenIndexAt(mTokens, ANode.StartOffset);
  while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < ANode.EndOffset) do
  begin
    if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mIndex].Text, AName) then
    begin
      ARange := TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].EndPos);
      Exit(True);
    end;
    Inc(mIndex);
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
  mFound: TSyntaxNode;
  mName: string;
  mDeclared: Boolean;
begin
  mFound := nil;
  mName := StripGenerics(AInterface);
  if Pos('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (mFound = nil) and (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(StripGenerics(ANode.Name), mName) and
        (ANode.FindChild(TSyntaxKind.InterfaceType) <> nil) then
      begin
        mFound := ANode;
      end;
      Result := mFound = nil;
    end);
  if mFound = nil then
  begin
    Exit(TInterfaceAnswer.Unknown);
  end;
  mDeclared := False;
  mFound.FindChild(TSyntaxKind.InterfaceType).Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.RoutineHeader) and SameText(ANode.Name, AMethod) then
      begin
        mDeclared := True;
      end;
      Result := not mDeclared;
    end);
  if mDeclared then
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
    Result := cTexts[TEditingInlineAccessorText.IsBothGetterAndSetter].Fmt([AMember.Name]);
  end
  else if AMember.Kind <> TClassMemberKind.Method then
  begin
    Result := cTexts[TEditingInlineAccessorText.IsNotAnOrdinaryMethod].Fmt([AMember.Name]);
  end
  else if AMember.IsVirtual or AMember.HasDirective('message') then
  begin
    Result := cTexts[TEditingInlineAccessorText.IsVirtualVirtualDynamicOverride].Fmt([AMember.Name]);
  end
  else if AMember.IsClassMember then
  begin
    Result := cTexts[TEditingInlineAccessorText.IsAClassMethod].Fmt([AMember.Name]);
  end
  else if AMember.IsGeneric or (Length(ALayout.Find(AMember.Name)) > 1) then
  begin
    Result := cTexts[TEditingInlineAccessorText.IsOverloadedOrGeneric].Fmt([AMember.Name]);
  end;
end;

/// <summary>Warum die Property AProp nicht direkt auf ein Feld zeigen kann; '' wenn nichts dagegen spricht.
/// </summary>
function PropertyIssue(const AProp: TClassMember; const AMethod: string): string;
begin
  Result := '';
  if AProp.IndexSpecifier <> '' then
  begin
    Result := cTexts[TEditingInlineAccessorText.PropertyHasAnIndexNeeds].Fmt([AProp.Name, AMethod]);
  end
  else if (AProp.Parameters <> '') or AProp.IsClassMember or AProp.IsRedeclaration then
  begin
    Result := cTexts[TEditingInlineAccessorText.PropertyIsAnArrayClass].Fmt([AProp.Name]);
  end
  else if SameText(AProp.StoredSpecifier, AMethod) then
  begin
    Result := cTexts[TEditingInlineAccessorText.PropertyAlsoNamesForStored].Fmt([AProp.Name, AMethod]);
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
      Result := cTexts[TEditingInlineAccessorText.ThePropertiesOfHaveDifferent].Fmt([AMethod]);
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
      Result := cTexts[TEditingInlineAccessorText.DoesNotFitAsGetter].Fmt([AMember.Name]);
    end;
  end
  else if AMember.IsFunction or (Length(AMember.ParameterTypes) <> 1) or
    not SameType(AMember.ParameterTypes[0], AType) or StartsText('var ', AMember.Parameters) or
    StartsText('out ', AMember.Parameters) then
  begin
    Result := cTexts[TEditingInlineAccessorText.DoesNotFitAsSetter].Fmt([AMember.Name]);
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
    Result := cTexts[TEditingInlineAccessorText.TheBodyOfIsNot].Fmt([AMember.Name]);
  end
  else if AField = '' then
  begin
    Result := cTexts[TEditingInlineAccessorText.DoesMoreThanReadOr].Fmt([AMember.Name]);
  end
  else
  begin
    mFields := ALayout.Find(AField);
    if (Length(mFields) <> 1) or not IsInstanceField(ALayout.Members[mFields[0]]) then
    begin
      Result := cTexts[TEditingInlineAccessorText.IsNotAFieldOf].Fmt([AField, ALayout.Name]);
    end
    else if not SameType(ALayout.Members[mFields[0]].TypeName, AType) then
    begin
      Result := cTexts[TEditingInlineAccessorText.HasADifferentTypeThan].Fmt([AField]);
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
    Result := cTexts[TEditingInlineAccessorText.ImplementsAMethodOf].Fmt([AMethod, ALayout.Ancestors[AIndex]]);
  end
  // Nur der erste Eintrag kann eine Klasse sein; ein unbekanntes Interface schließt aus.
  else if (mAnswer = TInterfaceAnswer.Unknown) and (AIndex > 0) then
  begin
    Result := cTexts[TEditingInlineAccessorText.WhetherImplementsAMethodOf].Fmt([AMethod,
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
    Exit(cTexts[TEditingInlineAccessorText.IsMappedToAnInterface].Fmt([AMethod]));
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
      Exit(cTexts[TEditingInlineAccessorText.IsUsedInTheClass].Fmt([ALayout.Members[AMember].Name,
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
    AReason := cTexts[TEditingInlineAccessorText.TheNameOfCannotBe].Fmt([mMember.Name]);
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
  mIndex: Integer;
  mAccessor: TTrivialAccessor;
  mReason: string;
begin
  Result := nil;
  for mIndex := 0 to High(ALayout.Members) do
  begin
    if ALayout.Members[mIndex].IsMethod and Check(ALayout, mIndex, AOptions, AInterfaces, mAccessor, mReason) then
    begin
      Result := Result + [mAccessor];
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
  mAccessor: TTrivialAccessor;
  mIndex: Integer;
  mRemoved: TArray<Integer>;
  mEdit: TTextEdit;
  mKeyword: string;
begin
  Result := nil;
  mRemoved := nil;
  for mAccessor in AAccessors do
  begin
    mKeyword := 'write';
    if mAccessor.IsGetter then
    begin
      mKeyword := 'read';
    end;
    for mIndex in mAccessor.Properties do
    begin
      if TClassEdits.ReplaceAccessor(ALayout, mIndex, mKeyword, mAccessor.Field, mEdit) then
      begin
        Result := Result + [mEdit];
      end;
    end;
    mRemoved := mRemoved + [mAccessor.Member];
  end;
  Result := Result + TClassEdits.DeleteMembers(ALayout, mRemoved, True) +
    TMemberTransfer.EmptiedSections(ALayout, mRemoved);
end;

class function TInlineAccessor.IsOwnReference(ALayout: TClassLayout; const AAccessor: TTrivialAccessor;
  const APosition: TTextPosition): Boolean;
var
  mMember: TClassMember;
  mIndex: Integer;
begin
  mMember := ALayout.Members[AAccessor.Member];
  if (APosition.Line >= mMember.FirstLine) and (APosition.Line <= mMember.LastLine) then
  begin
    Exit(True);
  end;
  if (mMember.Body <> nil) and (APosition.Line >= mMember.BodyFirstLine) and
    (APosition.Line <= mMember.BodyLastLine) then
  begin
    Exit(True);
  end;
  for mIndex in AAccessor.Properties do
  begin
    if (APosition.Line >= ALayout.Members[mIndex].FirstLine) and
      (APosition.Line <= ALayout.Members[mIndex].LastLine) then
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
    Result := cTexts[TEditingInlineAccessorText.ReplaceAccessorWithField].Fmt([AAccessors[0].Name,
      AAccessors[0].Field]);
  end
  else
  begin
    Result := cTexts[TEditingInlineAccessorText.ReplaceAccessorsAndWithThe].Fmt([AAccessors[0].Name,
      AAccessors[1].Name]);
  end;
end;

class function TInlineAccessor.IsResolution(ALayout: TClassLayout; const AMethod: string): Boolean;
begin
  Result := HasResolution(ALayout, AMethod);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.InlineAccessor', cTexts);

end.
