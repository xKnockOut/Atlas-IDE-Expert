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

function Fail(out AReason: string; const AMessage: string): Boolean;
begin
  AReason := AMessage;
  Result := False;
end;

function StripGenerics(const AName: string): string;
begin
  Result := Trim(AName);
  if Pos('<', Result) > 0 then
    Result := Trim(Copy(Result, 1, Pos('<', Result) - 1));
end;

/// <summary>FX oder Self.FX; '' sonst.</summary>
function FieldRef(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode = nil then
    Exit;
  if ANode.Kind = TSyntaxKind.Identifier then
    Result := ANode.Name
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
    Result := ANode.Name;
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
    Result := ABody[1];
end;

/// <summary>Feld, das der Getter-Rumpf liefert; '' wenn er mehr tut.</summary>
function GetterField(ABody: TSyntaxNode; const AMethod: string): string;
var
  Block, Statement: TSyntaxNode;
begin
  Result := '';
  Block := BodyBlock(ABody);
  if (Block = nil) or (Block.ChildCount <> 1) then
    Exit;
  Statement := Block[0];
  if (Statement.Kind = TSyntaxKind.AssignStatement) and (Statement.ChildCount = 2) and
    (IsIdentifierNamed(Statement[0], 'Result') or IsIdentifierNamed(Statement[0], AMethod)) then
    Result := FieldRef(Statement[1])
  else if (Statement.Kind = TSyntaxKind.CallStatement) and (Statement.ChildCount = 1) and
    (Statement[0].Kind = TSyntaxKind.Call) and (Statement[0].ChildCount = 2) and
    IsIdentifierNamed(Statement[0][0], 'Exit') then
    Result := FieldRef(Statement[0][1]);
end;

/// <summary>Feld aus "FX := AParam"; '' sonst.</summary>
function AssignedField(AStatement: TSyntaxNode; const AParam: string): string;
begin
  Result := '';
  if (AStatement <> nil) and (AStatement.Kind = TSyntaxKind.AssignStatement) and (AStatement.ChildCount = 2) and
    IsIdentifierNamed(AStatement[1], AParam) then
    Result := FieldRef(AStatement[0]);
end;

/// <summary>Feld, das der Setter-Rumpf setzt; '' wenn er mehr tut.</summary>
function SetterField(ABody: TSyntaxNode; AEqualityCheck: Boolean): string;
var
  Block, Header, Parameters, Statement, Condition, Inner: TSyntaxNode;
  Param, Left, Right: string;
begin
  Result := '';
  Block := BodyBlock(ABody);
  if (Block = nil) or (Block.ChildCount <> 1) then
    Exit;
  Header := ABody[0];
  Parameters := Header.FindChild(TSyntaxKind.Parameters);
  if (Parameters = nil) or (Parameters.ChildCount <> 1) then
    Exit;
  // Der Rumpf darf den Parameter anders nennen als die Deklaration.
  Param := Parameters[0].Name;
  Statement := Block[0];
  if Statement.Kind = TSyntaxKind.AssignStatement then
    Exit(AssignedField(Statement, Param));
  if not AEqualityCheck or (Statement.Kind <> TSyntaxKind.IfStatement) or (Statement.ChildCount <> 2) then
    Exit;
  Condition := Statement[0];
  if (Condition.Kind <> TSyntaxKind.BinaryExpr) or (Condition.Name <> '<>') or (Condition.ChildCount <> 2) then
    Exit;
  Inner := Statement[1];
  if (Inner.Kind = TSyntaxKind.Block) and (Inner.ChildCount = 1) then
    Inner := Inner[0];
  Result := AssignedField(Inner, Param);
  if Result = '' then
    Exit;
  Left := FieldRef(Condition[0]);
  Right := FieldRef(Condition[1]);
  if not ((SameText(Left, Result) and SameText(Right, Param)) or (SameText(Left, Param) and
    SameText(Right, Result))) then
    Result := '';
end;

/// <summary>Methodenzuordnung "IFoo.Bar = AMethod;" in der Klasse?</summary>
function HasResolution(ALayout: TClassLayout; const AMethod: string): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index, Next: Integer;
  Significant: TArray<Integer>;
begin
  Tokens := ALayout.Tree.Tokens;
  Significant := nil;
  Index := TokenIndexAt(Tokens, ALayout.ClassNode.StartOffset);
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < ALayout.ClassNode.EndOffset) do
  begin
    if not IsTrivia(Tokens[Index]) then
      Significant := Significant + [Index];
    Inc(Index);
  end;
  for Next := 4 to High(Significant) do
    if Tokens[Significant[Next]].IsSymbol('=') and (Next + 1 <= High(Significant)) and
      SameText(Tokens[Significant[Next + 1]].Text, AMethod) and Tokens[Significant[Next - 2]].IsSymbol('.') and
      (Tokens[Significant[Next - 1]].Kind = TPascalTokenKind.Identifier) and
      (Tokens[Significant[Next - 3]].Kind = TPascalTokenKind.Identifier) then
      Exit(True);
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
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (Found = nil) and (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(StripGenerics(ANode.Name), Name) and
        (ANode.FindChild(TSyntaxKind.InterfaceType) <> nil) then
        Found := ANode;
      Result := Found = nil;
    end);
  if Found = nil then
    Exit(TInterfaceAnswer.Unknown);
  Declared := False;
  Found.FindChild(TSyntaxKind.InterfaceType).Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.RoutineHeader) and SameText(ANode.Name, AMethod) then
        Declared := True;
      Result := not Declared;
    end);
  if Declared then
    Exit(TInterfaceAnswer.Yes);
  Result := TInterfaceAnswer.No;
end;

class function TInlineAccessor.Check(ALayout: TClassLayout; AMember: Integer;
  const AOptions: TInlineAccessorOptions; const AInterfaces: TInterfaceDeclares; out AAccessor: TTrivialAccessor;
  out AReason: string): Boolean;
var
  Member, Prop, FieldMember: TClassMember;
  Index, Reads, Writes: Integer;
  PropertyType, Field: string;
  Fields: TArray<Integer>;
  Answer: TInterfaceAnswer;
  Users: TArray<Integer>;
  User: Integer;
begin
  Result := False;
  AReason := '';
  AAccessor := Default(TTrivialAccessor);
  Member := ALayout.Members[AMember];
  if not Member.IsMethod then
    Exit;
  AAccessor.ClassName := ALayout.Name;
  AAccessor.Member := AMember;
  AAccessor.Name := Member.Name;
  Reads := 0;
  Writes := 0;
  for Index := 0 to High(ALayout.Members) do
  begin
    Prop := ALayout.Members[Index];
    if Prop.Kind <> TClassMemberKind.Property_ then
      Continue;
    if SameText(Prop.ReadAccessor, Member.Name) then
      Inc(Reads)
    else if SameText(Prop.WriteAccessor, Member.Name) then
      Inc(Writes)
    else
      Continue;
    AAccessor.Properties := AAccessor.Properties + [Index];
  end;
  if AAccessor.Properties = nil then
    Exit;
  AAccessor.IsGetter := Reads > 0;
  if (Reads > 0) and (Writes > 0) then
    Exit(Fail(AReason, Format('%s ist zugleich Getter und Setter.', [Member.Name])));
  if Member.Kind <> TClassMemberKind.Method then
    Exit(Fail(AReason, Format('%s ist keine gewöhnliche Methode.', [Member.Name])));
  if Member.IsVirtual or Member.HasDirective('message') then
    Exit(Fail(AReason, Format('%s ist virtuell (virtual, dynamic, override oder abstract).',
      [Member.Name])));
  if Member.IsClassMember then
    Exit(Fail(AReason, Format('%s ist eine class-Methode.', [Member.Name])));
  if Member.IsGeneric or (Length(ALayout.Find(Member.Name)) > 1) then
    Exit(Fail(AReason, Format('%s ist überladen oder generisch.', [Member.Name])));
  PropertyType := '';
  for Index in AAccessor.Properties do
  begin
    Prop := ALayout.Members[Index];
    if Prop.IndexSpecifier <> '' then
      Exit(Fail(AReason, Format('Property %s hat einen index; %s braucht ihn als Parameter.',
        [Prop.Name, Member.Name])));
    if (Prop.Parameters <> '') or Prop.IsClassMember or Prop.IsRedeclaration then
      Exit(Fail(AReason, Format('Property %s ist eine Array-, class- oder umdeklarierte Property.',
        [Prop.Name])));
    if SameText(Prop.StoredSpecifier, Member.Name) then
      Exit(Fail(AReason, Format('Property %s nennt %s auch bei stored.', [Prop.Name, Member.Name])));
    if (PropertyType <> '') and not SameType(PropertyType, Prop.TypeName) then
      Exit(Fail(AReason, Format('Die Properties zu %s haben verschiedene Typen.', [Member.Name])));
    PropertyType := Prop.TypeName;
  end;
  if AAccessor.IsGetter then
  begin
    if not Member.IsFunction or (Member.Parameters <> '') or not SameType(Member.TypeName, PropertyType) then
      Exit(Fail(AReason, Format('%s passt nicht als Getter zur Property.', [Member.Name])));
    Field := GetterField(Member.Body, Member.Name);
  end
  else
  begin
    if Member.IsFunction or (Length(Member.ParameterTypes) <> 1) or
      not SameType(Member.ParameterTypes[0], PropertyType) or StartsText('var ', Member.Parameters) or
      StartsText('out ', Member.Parameters) then
      Exit(Fail(AReason, Format('%s passt nicht als Setter zur Property.', [Member.Name])));
    Field := SetterField(Member.Body, AOptions.EqualityCheck);
  end;
  if Member.Body = nil then
    Exit(Fail(AReason, Format('Der Rumpf von %s steht nicht in dieser Unit.', [Member.Name])));
  if Field = '' then
    Exit(Fail(AReason, Format('%s tut mehr, als ein Feld zu lesen bzw. zu setzen.', [Member.Name])));
  Fields := ALayout.Find(Field);
  if Length(Fields) <> 1 then
    Exit(Fail(AReason, Format('%s ist kein Feld von %s.', [Field, ALayout.Name])));
  FieldMember := ALayout.Members[Fields[0]];
  if (FieldMember.Kind <> TClassMemberKind.Field) or FieldMember.IsClassMember then
    Exit(Fail(AReason, Format('%s ist kein Feld von %s.', [Field, ALayout.Name])));
  if not SameType(FieldMember.TypeName, PropertyType) then
    Exit(Fail(AReason, Format('%s hat einen anderen Typ als die Property.', [Field])));
  AAccessor.Field := FieldMember.Name;
  // Methoden eines Interfaces der Klasse müssen bleiben.
  if HasResolution(ALayout, Member.Name) then
    Exit(Fail(AReason, Format('%s ist einer Interface-Methode zugeordnet.', [Member.Name])));
  for Index := 0 to High(ALayout.Ancestors) do
  begin
    Answer := LocalInterfaceDeclares(ALayout.Tree, ALayout.Ancestors[Index], Member.Name);
    if (Answer = TInterfaceAnswer.Unknown) and Assigned(AInterfaces) then
      Answer := AInterfaces(ALayout.Ancestors[Index], Member.Name);
    if Answer = TInterfaceAnswer.Yes then
      Exit(Fail(AReason, Format('%s implementiert eine Methode von %s.', [Member.Name,
        ALayout.Ancestors[Index]])));
    // Nur der erste Eintrag kann eine Klasse sein; ein unbekanntes Interface schließt aus.
    if (Answer = TInterfaceAnswer.Unknown) and (Index > 0) then
      Exit(Fail(AReason, Format('Ob %s eine Methode von %s implementiert, ist unbekannt.',
        [Member.Name, ALayout.Ancestors[Index]])));
  end;
  Users := ALayout.UsersOf(AMember);
  for User in Users do
    if not TMemberTransfer.Has(AAccessor.Properties, User) then
      Exit(Fail(AReason, Format('%s wird in der Klasse benutzt (%s).', [Member.Name,
        ALayout.Members[User].Name])));
  if not NameRangeIn(ALayout, Member.Node, Member.Name, AAccessor.NameRange) then
    Exit(Fail(AReason, Format('Der Name von %s ist nicht zu finden.', [Member.Name])));
  AAccessor.NamePos := AAccessor.NameRange.StartPos;
  Result := True;
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
    if ALayout.Members[Index].IsMethod and Check(ALayout, Index, AOptions, AInterfaces, Accessor, Reason) then
      Result := Result + [Accessor];
end;

class function TInlineAccessor.At(ALayout: TClassLayout; ALine: Integer; const AOptions: TInlineAccessorOptions;
  const AInterfaces: TInterfaceDeclares; out AReason: string): TArray<TTrivialAccessor>;
var
  Index, Hit: Integer;
  Member: TClassMember;
  Accessor: TTrivialAccessor;
  Reason: string;
  Names: TArray<string>;
  Name: string;
begin
  Result := nil;
  AReason := '';
  Hit := ALayout.MemberAtLine(ALine);
  if Hit < 0 then
    // Im Rumpf einer Methode der Klasse.
    for Index := 0 to High(ALayout.Members) do
      if ALayout.Members[Index].IsMethod and (ALayout.Members[Index].Body <> nil) and
        (ALine >= ALayout.Members[Index].BodyFirstLine) and (ALine <= ALayout.Members[Index].BodyLastLine) then
        Hit := Index;
  if Hit < 0 then
    Exit;
  Member := ALayout.Members[Hit];
  if Member.IsMethod then
  begin
    if Check(ALayout, Hit, AOptions, AInterfaces, Accessor, AReason) then
      Result := [Accessor];
    Exit;
  end;
  if Member.Kind <> TClassMemberKind.Property_ then
    Exit;
  Names := nil;
  if Member.ReadAccessor <> '' then
    Names := Names + [Member.ReadAccessor];
  if Member.WriteAccessor <> '' then
    Names := Names + [Member.WriteAccessor];
  for Name in Names do
    for Index in ALayout.Find(Name) do
      if ALayout.Members[Index].IsMethod then
      begin
        if Check(ALayout, Index, AOptions, AInterfaces, Accessor, Reason) then
          Result := Result + [Accessor]
        else if AReason = '' then
          AReason := Reason;
      end;
  if Result <> nil then
    AReason := '';
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
      Keyword := 'read';
    for Index in Accessor.Properties do
      if TClassEdits.ReplaceAccessor(ALayout, Index, Keyword, Accessor.Field, Edit) then
        Result := Result + [Edit];
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
    Exit(True);
  if (Member.Body <> nil) and (APosition.Line >= Member.BodyFirstLine) and (APosition.Line <= Member.BodyLastLine) then
    Exit(True);
  for Index in AAccessor.Properties do
    if (APosition.Line >= ALayout.Members[Index].FirstLine) and (APosition.Line <= ALayout.Members[Index].LastLine) then
      Exit(True);
  Result := False;
end;

/// <summary>Interface AName im Index: deklariert es AMethod, auch über Vorfahren? ADepth begrenzt Kreise.</summary>
function IndexDeclares(const AIndex: ISymbolIndex; const AName, AMethod: string; ADepth: Integer): TInterfaceAnswer;
var
  Name, Ancestor: string;
  Location: TSymbolLocation;
  Known: Boolean;
  Answer: TInterfaceAnswer;
begin
  Name := StripGenerics(AName);
  if Pos('.', Name) > 0 then
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  // Die Methoden von IInterface, IUnknown und IDispatch heißen nie wie eine Zugriffsmethode.
  if MatchText(Name, ['IInterface', 'IUnknown', 'IDispatch']) then
    Exit(TInterfaceAnswer.No);
  if ADepth > 10 then
    Exit(TInterfaceAnswer.Unknown);
  Known := False;
  Result := TInterfaceAnswer.No;
  for Location in AIndex.FindSymbols(Name) do
  begin
    if (Location.Symbol.Kind <> TIndexSymbolKind.InterfaceType) or (Location.Symbol.Container <> '') then
      Continue;
    Known := True;
    for Ancestor in Location.Symbol.Ancestors do
    begin
      Answer := IndexDeclares(AIndex, Ancestor, AMethod, ADepth + 1);
      if Answer = TInterfaceAnswer.Yes then
        Exit(TInterfaceAnswer.Yes);
      if Answer = TInterfaceAnswer.Unknown then
        Result := TInterfaceAnswer.Unknown;
    end;
  end;
  if not Known then
    Exit(TInterfaceAnswer.Unknown);
  for Location in AIndex.FindSymbols(AMethod) do
    if (Location.Symbol.Kind = TIndexSymbolKind.Method) and SameText(Location.Symbol.Container, Name) then
      Exit(TInterfaceAnswer.Yes);
end;

class function TInlineAccessor.IndexInterfaces(const AIndex: ISymbolIndex): TInterfaceDeclares;
begin
  Result := nil;
  if AIndex = nil then
    Exit;
  Result :=
    function(const AInterface, AMethod: string): TInterfaceAnswer
    begin
      Result := IndexDeclares(AIndex, AInterface, AMethod, 0);
    end;
end;

class function TInlineAccessor.Title(const AAccessors: TArray<TTrivialAccessor>): string;
begin
  if Length(AAccessors) = 1 then
    Result := Format('Zugriffsmethode %s durch Feld %s ersetzen', [AAccessors[0].Name, AAccessors[0].Field])
  else
    Result := Format('Zugriffsmethoden %s und %s durch Feld ersetzen', [AAccessors[0].Name, AAccessors[1].Name]);
end;

end.
