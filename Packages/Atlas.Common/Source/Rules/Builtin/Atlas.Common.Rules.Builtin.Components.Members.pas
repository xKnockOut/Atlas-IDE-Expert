unit Atlas.Common.Rules.Builtin.Components.Members;

// Prüfregeln zu Zugriffsmethoden und Gleichheit (Teil von Atlas.Common.Rules.Builtin.Components, dort
// registriert): getter-side-effect, equals-without-gethashcode.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract;

type
  TGetterSideEffectRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TEqualsWithoutGetHashCodeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Hashwert des Felds AField vom Typ ATypeName, verkettet mit AInitial; ACompare ist die Funktion, in
    /// der Equals das Feld vergleicht (SameText: ohne Groß-/Kleinschreibung, also auch der Hashwert).</summary>
    class function HashExpression(const AField, ATypeName, ACompare, AInitial: string): string; static;
  end;


implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.Components.Model;

{ TGetterSideEffectRule }

function TGetterSideEffectRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('getter-side-effect', TRuleSeverity.Warning, 'Getter verändert den Zustand');
end;

/// <summary>F bzw. Self.F als Ziel; '' sonst.</summary>
function SelfMemberName(ANode: TSyntaxNode): string;
begin
  Result := '';
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

/// <summary>Namen (F, Self.F, Result, lokale Variablen), denen unter ANode zugewiesen wird.</summary>
procedure CollectAssignedNames(ANode: TSyntaxNode; var ANames: TArray<string>);
var
  Index: Integer;
  Name: string;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount > 0) then
      begin
        Name := SelfMemberName(Node[0]);
        if Name <> '' then
        begin
          ANames := ANames + [Name];
        end;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Nennt ANode einen der Namen (F oder Self.F)?</summary>
function MentionsName(ANode: TSyntaxNode; const ANames: TArray<string>): Boolean;
var
  Index: Integer;
  Name: string;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      Name := SelfMemberName(Node);
      if (Name <> '') and IsIn(Name, ANames) then
      begin
        Exit(True);
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Enthält ANode einen Konstruktoraufruf (X.Create, X.Create(…))?</summary>
function ContainsCreate(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.MemberAccess) and StartsText('Create', Node.Name) then
      begin
        Exit(True);
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Lazy-Initialisierung: Ein umschließendes if (bis ARoot) prüft in der Bedingung etwas, das im Zweig
/// mit ANode zugewiesen wird (if FListe = nil then FListe := …, if Result = nil then … FX := Result).</summary>
function IsLazyInit(ANode, ARoot: TSyntaxNode): Boolean;
var
  Branch, Condition: TSyntaxNode;
  AssignedNames: TArray<string>;
begin
  Branch := ANode;
  while (Branch <> nil) and (Branch <> ARoot) and (Branch.Parent <> nil) do
  begin
    Condition := nil;
    if (Branch.Parent.Kind = TSyntaxKind.IfStatement) and (Branch.Parent.ChildCount > 1) and
      (Branch.Parent[0] <> Branch) then
    begin
      Condition := Branch.Parent[0];
    end;
    if Condition <> nil then
    begin
      AssignedNames := nil;
      CollectAssignedNames(Branch, AssignedNames);
      if MentionsName(Condition, AssignedNames) then
      begin
        Exit(True);
      end;
    end;
    Branch := Branch.Parent;
  end;
  Result := False;
end;

/// <summary>read-Methoden der Properties von AInfo, ohne Doppelte.</summary>
function GetterNames(AModel: TComponentModel; const AInfo: TClassInfo): TArray<string>;
var
  mProp: TPropertyInfo;
begin
  Result := nil;
  for mProp in AModel.Properties(AInfo) do
  begin
    if (mProp.ReadName <> '') and not IsIn(mProp.ReadName, Result) then
    begin
      Result := Result + [mProp.ReadName];
    end;
  end;
end;

/// <summary>Eigene Felder und Properties der Klasse AInfo.</summary>
function StateMembers(const AInfo: TClassInfo): TArray<string>;
var
  mIndex: Integer;
begin
  Result := OwnFields(AInfo);
  for mIndex := 0 to AInfo.Body.ChildCount - 1 do
  begin
    if AInfo.Body[mIndex].Kind = TSyntaxKind.PropertyDecl then
    begin
      Result := Result + [AInfo.Body[mIndex].Name];
    end;
  end;
end;

procedure TGetterSideEffectRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  AllowLazyInit: Boolean;
  Info: TClassInfo;
  Parent: string;
  Members, Locals, Reported: TArray<string>;

  // Feld oder Property des Objekts: eigene aus der Klasse, geerbte über TAncestry.
  function IsState(const AName: string): Boolean;
  var
    Member: TIndexSymbol;
    Unresolved: string;
  begin
    if (AName = '') or SameText(AName, 'Result') or SameText(AName, 'Self') or IsIn(AName, Locals) then
    begin
      Exit(False);
    end;
    if IsIn(AName, Members) then
    begin
      Exit(True);
    end;
    Result := (Parent <> '') and Model.Ancestry.FindMember(Parent, AName, Member, Unresolved) and
      (Member.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]);
  end;

  // Geändertes Mitglied an ANode: Ziel einer Zuweisung, Inc/Dec/Include/Exclude, Methode eines Felds mit neu
  // angelegtem Objekt als Argument (FListe.Add(TEintrag.Create)); nil ohne.
  function ChangedTarget(ANode: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
  begin
    Result := nil;
    if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount > 0) then
    begin
      Result := ANode[0];
    end
    else if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 1) and
      (ANode[0].Kind = TSyntaxKind.Identifier) and IsIn(ANode[0].Name, ['Inc', 'Dec', 'Include', 'Exclude']) then
    begin
      Result := ANode[1];
    end
    else if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 1) and
      (ANode[0].Kind = TSyntaxKind.MemberAccess) and (ANode[0].ChildCount = 1) then
    begin
      for Index := 1 to ANode.ChildCount - 1 do
      begin
        if ContainsCreate(ANode[Index]) then
        begin
          Exit(ANode[0][0]);
        end;
      end;
    end;
  end;

  procedure Visit(ANode, ARoot: TSyntaxNode; const AGetter: string);
  var
    Node, Target: TSyntaxNode;
    Name: string;
    Index: Integer;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Continue;
        end;
        Target := ChangedTarget(Node);
        if Target <> nil then
        begin
          Name := SelfMemberName(Target);
          if IsState(Name) and not IsIn(Name, Reported) and not (AllowLazyInit and IsLazyInit(Node, ARoot)) then
          begin
            Reported := Reported + [Name];
            AReport.Add(TTextRange.Create(Target.StartPos, Target.EndPos),
              Format('Der Getter %s verändert %s; schon das Anzeigen im Debugger ändert den Zustand.', [AGetter, Name]),
              TRuleConfidence.Medium);
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Method: TMethodImpl;
  Getters: TArray<string>;
begin
  Cache := TRuleDerived.Open(AContext);
  if not PrepareModel(Cache, AContext, Model) then
  begin
    Exit;
  end;
  AllowLazyInit := TRuleOptions.Bool(AContext.Options, 'allowLazyInit', True);
  for Info in Model.Classes do
  begin
    Getters := GetterNames(Model, Info);
    if Getters = nil then
    begin
      Continue;
    end;
    Parent := DeclaredParent(Info);
    Members := StateMembers(Info);
    for Method in Model.Methods do
    begin
      if SameText(Method.ClassName, Info.Name) and IsIn(Method.MethodName, Getters) and
        not Model.HasToken(Method.Block, ['with']) then
      begin
        Locals := MethodLocalNames(Method);
        Reported := nil;
        Visit(Method.Block, Method.Block, Method.MethodName);
      end;
    end;
  end;
end;

{ TEqualsWithoutGetHashCodeRule }

const
  // Feldtypen, bei denen der Standard-Comparer für Records (Byte für Byte) nicht zu Equal passt.
  BinaryUnsafeTypes: array[0..12] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString',
    'RawByteString', 'UTF8String', 'ShortString', 'Variant', 'OleVariant', 'Double', 'Single', 'Extended', 'Real');
  // Generische Sammlungen, deren erster Typparameter der Schlüssel ist.
  HashedCollections: array[0..3] of string = ('TDictionary', 'TObjectDictionary', 'THashSet', 'TMultiMap');

function TEqualsWithoutGetHashCodeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('equals-without-gethashcode', TRuleSeverity.Warning,
    'Equals ohne GetHashCode');
end;

/// <summary>Kopf AName im Klassen- bzw. Record-Rumpf ABody; nil ohne.</summary>
function MemberHeader(ABody: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ABody.ChildCount - 1 do
  begin
    if (ABody[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(ABody[Index].Name, AName) then
    begin
      Exit(ABody[Index]);
    end;
  end;
  Result := nil;
end;

/// <summary>Deklariert der Feldknoten AField (auch "FA, FB: T") das Feld AName?</summary>
function DeclaresField(AField: TSyntaxNode; const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in AField.Name.Split([',']) do
  begin
    Result := Result or SameText(Trim(mName), AName);
  end;
end;

/// <summary>Typ des Felds AName im Rumpf ABody (Field "A,B" mit TypeReference); '' ohne.</summary>
function FieldTypeName(ABody: TSyntaxNode; const AName: string): string;
var
  mIndex: Integer;
  mTypeRef: TSyntaxNode;
begin
  Result := '';
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    if (ABody[mIndex].Kind = TSyntaxKind.Field) and DeclaresField(ABody[mIndex], AName) then
    begin
      mTypeRef := ABody[mIndex].FindChild(TSyntaxKind.TypeReference);
      if mTypeRef <> nil then
      begin
        Result := mTypeRef.Name;
      end;
      Exit;
    end;
  end;
end;

class function TEqualsWithoutGetHashCodeRule.HashExpression(const AField, ATypeName, ACompare,
  AInitial: string): string;
var
  Value: string;
begin
  if MatchText(ATypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'UTF8String']) then
  begin
    // Vergleicht Equals ohne Groß-/Kleinschreibung, muss der Hashwert es ebenso tun.
    Value := AField;
    if MatchText(ACompare, ['SameText', 'CompareText']) then
    begin
      Value := 'LowerCase(' + AField + ')';
    end
    else if MatchText(ACompare, ['AnsiSameText', 'AnsiCompareText']) then
    begin
      Value := 'AnsiLowerCase(' + AField + ')';
    end;
    Result := Format('THashBobJenkins.GetHashValue(%s, %s)', [Value, AInitial]);
  end
  else
  begin
    Result := Format('THashBobJenkins.GetHashValue(%s, SizeOf(%s), %s)', [AField, AField, AInitial]);
  end;
end;

/// <summary>Letzte Implementierung AClassName.AMethodName der Datei; False ohne.</summary>
function LastMethod(AModel: TComponentModel; const AClassName, AMethodName: string; out AMethod: TMethodImpl): Boolean;
var
  mMethod: TMethodImpl;
begin
  Result := False;
  for mMethod in AModel.Methods do
  begin
    if SameText(mMethod.ClassName, AClassName) and SameText(mMethod.MethodName, AMethodName) then
    begin
      AMethod := mMethod;
      Result := True;
    end;
  end;
end;

/// <summary>Rumpf von GetHashCode: je Feld aus ANames ein Hashwert, verkettet über Result.</summary>
function HashBody(const AInfo: TClassInfo; const ANames, ACompares: TArray<string>; const ALineBreak: string): string;
var
  mIndex: Integer;
  mInitial: string;
begin
  Result := '';
  mInitial := '0';
  for mIndex := 0 to High(ANames) do
  begin
    Result := Result + '  Result := ' + TEqualsWithoutGetHashCodeRule.HashExpression(ANames[mIndex],
      FieldTypeName(AInfo.Body, ANames[mIndex]), ACompares[mIndex], mInitial) + ';' + ALineBreak;
    mInitial := 'Result';
  end;
end;

/// <summary>Vergleicht der Byte-Vergleich einen Wert des Typs ATypeName falsch (string, Variant, Gleitkomma,
/// Interface, TArray)?</summary>
function IsBinaryUnsafe(const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, BinaryUnsafeTypes) or SameText(ATypeName, 'TArray') or
    ((Length(ATypeName) > 1) and (ATypeName[1] = 'I') and CharInSet(ATypeName[2], ['A'..'Z']));
end;

/// <summary>Hat der Record-Rumpf ABody ein Feld, das der Byte-Vergleich falsch vergleicht?</summary>
function HasUnsafeField(ABody: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    if ABody[mIndex].Kind = TSyntaxKind.Field then
    begin
      Result := Result or IsBinaryUnsafe(FieldTypeName(ABody, Trim(ABody[mIndex].Name.Split([','])[0])));
    end;
  end;
end;

/// <summary>Ist die Typdeklaration ANode ein Record mit class operator Equal und einem Feld, das der Byte-Vergleich
/// falsch vergleicht?</summary>
function IsEqualRecord(AModel: TComponentModel; ANode: TSyntaxNode): Boolean;
var
  mBody, mHeader: TSyntaxNode;
begin
  Result := False;
  mBody := ANode.FindChild(TSyntaxKind.RecordType);
  if mBody <> nil then
  begin
    mHeader := MemberHeader(mBody, 'Equal');
    Result := (mHeader <> nil) and ContainsText(AModel.NodeText(mHeader), 'operator') and HasUnsafeField(mBody);
  end;
end;

/// <summary>Argumente ohne möglichen Comparer: nur Literale und Mengen (Kapazität, Besitz).</summary>
function OnlyConstants(ACall: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  Result := True;
  for mIndex := 1 to ACall.ChildCount - 1 do
  begin
    Result := Result and (ACall[mIndex].Kind in [TSyntaxKind.Literal, TSyntaxKind.SetConstructor]);
  end;
end;

/// <summary>Schlüsseltyp, wenn ANode TDictionary&lt;K, …&gt;.Create &amp; Co. ist (ACollection: der Typ); '' sonst.
/// </summary>
function HashedCreateKey(ANode: TSyntaxNode; out ACollection: TSyntaxNode): string;
var
  mArgs: TSyntaxNode;
begin
  Result := '';
  ACollection := nil;
  if (ANode.Kind <> TSyntaxKind.MemberAccess) or not SameText(ANode.Name, 'Create') or (ANode.ChildCount <> 1) or
    (ANode[0].Kind <> TSyntaxKind.MemberAccess) or not IsIn(ANode[0].Name, HashedCollections) then
  begin
    Exit;
  end;
  ACollection := ANode[0];
  mArgs := ACollection.FindChild(TSyntaxKind.GenericArgs);
  if (mArgs <> nil) and (mArgs.ChildCount > 0) then
  begin
    Result := mArgs[0].Name;
  end;
end;

/// <summary>Legt ANode (TDictionary&lt;…&gt;.Create) die Sammlung ohne Comparer an: ohne Klammern oder nur mit Konstanten?</summary>
function WithoutComparer(ANode: TSyntaxNode): Boolean;
begin
  Result := not ((ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.Call) and (ANode.Parent[0] = ANode)) or
    OnlyConstants(ANode.Parent);
end;

procedure TEqualsWithoutGetHashCodeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;

  // Überschreibt ein Vorfahr (ohne TObject) die Methode AName? AKnown: die Kette ist bekannt.
  function AncestorOverrides(const AClass, AName: string; out AKnown: Boolean): Boolean;
  var
    Chain: TArray<TSymbolLocation>;
    Location: TSymbolLocation;
    Member: TIndexSymbol;
    ObjectMissing: Boolean;
  begin
    Result := False;
    Chain := Model.Ancestry.Ancestors(AClass, AKnown, ObjectMissing);
    for Location in Chain do
    begin
      if not SameText(Location.Symbol.Name, 'TObject') then
      begin
        for Member in Model.Ancestry.Methods(Location) do
        begin
          if SameText(Member.Name, AName) and Member.HasDirective('override') then
          begin
            Exit(True);
          end;
        end;
      end;
    end;
  end;

  // Eigene Felder in der Reihenfolge, in der Equals sie nennt, je mit dem Vergleich (SameText …), in dem sie stehen.
  procedure CollectFields(ARoot: TSyntaxNode; const AFields: TArray<string>; var ANames, ACompares: TArray<string>);
  var
    Index: Integer;
    Compare: string;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1); Vorordnung, damit die Reihenfolge der Felder bleibt.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and IsIn(Node.Name, AFields) and
          not IsIn(Node.Name, ANames) then
        begin
          Compare := '';
          if (Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.Call) and (Node.Parent[0] <> Node) then
          begin
            Compare := Node.Parent.Name;
          end;
          ANames := ANames + [Node.Name];
          ACompares := ACompares + [Compare];
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Korrektur: GetHashCode hinter Equals deklarieren und hinter dem Rumpf von Equals umsetzen.
  function HashFix(const AInfo: TClassInfo; AHeader: TSyntaxNode; out AFix: TRuleFix): Boolean;
  var
    Equals_: TMethodImpl;
    Names, Compares: TArray<string>;
    Body: string;
    Edit, UsesEdit: TRuleEdit;
    Edits: TArray<TRuleEdit>;
    Position: TTextPosition;
  begin
    Result := False;
    if not LastMethod(Model, AInfo.Name, 'Equals', Equals_) then
    begin
      Exit;
    end;
    Names := nil;
    Compares := nil;
    CollectFields(Equals_.Block, OwnFields(AInfo), Names, Compares);
    if Names = nil then
    begin
      Exit;
    end;
    Body := HashBody(AInfo, Names, Compares, Model.LineBreak);
    // Edits in Textreihenfolge: Deklaration, uses der Implementierung, Rumpf.
    Position := TTextPosition.Create(AHeader.EndPos.Line + 1, 0);
    Edits := [TRuleEdit.Create(TTextRange.Create(Position, Position), StringOfChar(' ', AHeader.StartPos.Character) +
      'function GetHashCode: Integer; override;' + Model.LineBreak)];
    if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(AContext.Tree.Tokens), 'System.Hash', AContext.Namespaces) and
      TUsesClauses.AddUnit(AContext.Tree.Tokens, Equals_.Decl.StartOffset, 'System.Hash', Model.LineBreak,
      UsesEdit) then
    begin
      if UsesEdit.Range.StartPos.Line < AHeader.StartPos.Line then
      begin
        Edits := [UsesEdit] + Edits;
      end
      else
      begin
        Edits := Edits + [UsesEdit];
      end;
    end;
    Position := TTextPosition.Create(Equals_.Decl.EndPos.Line + 1, 0);
    Edit := TRuleEdit.Create(TTextRange.Create(Position, Position), Model.LineBreak + 'function ' + AInfo.Name +
      '.GetHashCode: Integer;' + Model.LineBreak + 'begin' + Model.LineBreak + Body + 'end;' + Model.LineBreak);
    Edits := Edits + [Edit];
    AFix := TRuleFix.Create(Format('GetHashCode mit %s überschreiben (THashBobJenkins)',
      [string.Join(', ', Names)]), Edits);
    Result := True;
  end;

  // Equals ohne GetHashCode: melden, mit Korrektur.
  procedure ReportEqualsOnly(const AInfo: TClassInfo);
  var
    Header: TSyntaxNode;
    Known: Boolean;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    if AncestorOverrides(AInfo.Name, 'GetHashCode', Known) or not Known then
    begin
      Exit;
    end;
    Header := MemberHeader(AInfo.Body, 'Equals');
    Fixes := nil;
    if HashFix(AInfo, Header, Fix) then
    begin
      Fixes := [Fix];
    end;
    AReport.Add(TTextRange.Create(Header.StartPos, Header.EndPos), 'Equals ist überschrieben, GetHashCode ' +
      'nicht; als Schlüssel in TDictionary finden sich gleiche Objekte nicht.', TRuleConfidence.High, Fixes);
  end;

  // GetHashCode ohne Equals: melden.
  procedure ReportHashOnly(const AInfo: TClassInfo);
  var
    Header: TSyntaxNode;
    Known: Boolean;
  begin
    if AncestorOverrides(AInfo.Name, 'Equals', Known) or not Known then
    begin
      Exit;
    end;
    Header := MemberHeader(AInfo.Body, 'GetHashCode');
    AReport.Add(TTextRange.Create(Header.StartPos, Header.EndPos), 'GetHashCode ist überschrieben, Equals ' +
      'nicht; als Schlüssel in TDictionary gelten gleiche Objekte weiter als verschieden.', TRuleConfidence.High);
  end;

  procedure CheckClasses;
  var
    Info: TClassInfo;
    HasEquals, HasHash: Boolean;
  begin
    for Info in Model.Classes do
    begin
      HasEquals := Model.DeclaredWith(Info, 'Equals', 'override');
      HasHash := Model.DeclaredWith(Info, 'GetHashCode', 'override');
      if HasEquals and not HasHash then
      begin
        ReportEqualsOnly(Info);
      end
      else if HasHash and not HasEquals then
      begin
        ReportHashOnly(Info);
      end;
    end;
  end;

  // Records der Datei mit class operator Equal und einem Feld, das der Byte-Vergleich falsch vergleicht.
  procedure CollectRecords(ARoot: TSyntaxNode; var ANames: TArray<string>);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.TypeDecl) and IsEqualRecord(Model, Node) then
        begin
          ANames := ANames + [Node.Name];
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure CheckCreates(ARoot: TSyntaxNode; const ARecords: TArray<string>);
  var
    Index: Integer;
    Node, Collection: TSyntaxNode;
    Key: string;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Key := HashedCreateKey(Node, Collection);
        if (Key <> '') and IsIn(Key, ARecords) and WithoutComparer(Node) then
        begin
          AReport.Add(TTextRange.Create(Collection.StartPos, Collection.EndPos), Format('%s hat class operator ' +
            'Equal, %s vergleicht Schlüssel ohne Comparer aber Byte für Byte; gleiche Schlüssel finden sich nicht.',
            [Key, Collection.Name]), TRuleConfidence.High);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Records: TArray<string>;
begin
  Cache := TRuleDerived.Open(AContext);
  if not PrepareModel(Cache, AContext, Model) then
  begin
    Exit;
  end;
  if ContainsText(AContext.Text, 'Equals') or ContainsText(AContext.Text, 'GetHashCode') then
  begin
    CheckClasses;
  end;
  if ContainsText(AContext.Text, 'operator') then
  begin
    Records := nil;
    CollectRecords(AContext.Tree.Root, Records);
    if Records <> nil then
    begin
      CheckCreates(AContext.Tree.Root, Records);
    end;
  end;
end;

end.
