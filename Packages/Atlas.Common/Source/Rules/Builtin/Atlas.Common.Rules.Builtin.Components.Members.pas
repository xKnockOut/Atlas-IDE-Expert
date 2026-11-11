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
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.Components.Model,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TComponentsMembersText = (GetterTitle, GetterChanges, EqualsTitle, OverrideHash, EqualsOnly, HashOnly, RecordEqual);

const
  cTexts: array[TComponentsMembersText] of TAtlasText = (
    (De: 'Getter verändert den Zustand'; En: 'Getter changes the state'),
    (De: 'Der Getter %s verändert %s; schon das Anzeigen im Debugger ändert den Zustand.';
     En: 'The getter %s changes %s; even displaying it in the debugger changes the state.'),
    (De: 'Equals ohne GetHashCode'; En: 'Equals without GetHashCode'),
    (De: 'GetHashCode mit %s überschreiben (THashBobJenkins)'; En: 'Override GetHashCode with %s (THashBobJenkins)'),
    (De: 'Equals ist überschrieben, GetHashCode nicht; als Schlüssel in TDictionary finden sich gleiche Objekte nicht.';
     En: 'Equals is overridden, GetHashCode is not; as keys in TDictionary equal objects are not found.'),
    (De: 'GetHashCode ist überschrieben, Equals nicht; als Schlüssel in TDictionary gelten gleiche Objekte weiter ' +
      'als verschieden.';
     En: 'GetHashCode is overridden, Equals is not; as keys in TDictionary equal objects still count as different.'),
    (De: '%s hat class operator Equal, %s vergleicht Schlüssel ohne Comparer aber Byte für Byte; gleiche Schlüssel ' +
      'finden sich nicht.';
     En: '%s has class operator Equal, but %s compares keys without a comparer byte by byte; equal keys are not ' +
      'found.'));

{$SCOPEDENUMS OFF}

{ TGetterSideEffectRule }

function TGetterSideEffectRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('getter-side-effect', TRuleSeverity.Warning,
    cTexts[TComponentsMembersText.GetterTitle].Text);
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
  mIndex: Integer;
  mName: string;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode.ChildCount > 0) then
      begin
        mName := SelfMemberName(mNode[0]);
        if mName <> '' then
        begin
          ANames := ANames + [mName];
        end;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Nennt ANode einen der Namen (F oder Self.F)?</summary>
function MentionsName(ANode: TSyntaxNode; const ANames: TArray<string>): Boolean;
var
  mIndex: Integer;
  mName: string;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mName := SelfMemberName(mNode);
      if (mName <> '') and IsIn(mName, ANames) then
      begin
        Exit(True);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Enthält ANode einen Konstruktoraufruf (X.Create, X.Create(…))?</summary>
function ContainsCreate(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.MemberAccess) and StartsText('Create', mNode.Name) then
      begin
        Exit(True);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Lazy-Initialisierung: Ein umschließendes if (bis ARoot) prüft in der Bedingung etwas, das im Zweig
/// mit ANode zugewiesen wird (if FListe = nil then FListe := …, if Result = nil then … FX := Result).</summary>
function IsLazyInit(ANode, ARoot: TSyntaxNode): Boolean;
var
  mBranch, mCondition: TSyntaxNode;
  mAssignedNames: TArray<string>;
begin
  mBranch := ANode;
  while (mBranch <> nil) and (mBranch <> ARoot) and (mBranch.Parent <> nil) do
  begin
    mCondition := nil;
    if (mBranch.Parent.Kind = TSyntaxKind.IfStatement) and (mBranch.Parent.ChildCount > 1) and
      (mBranch.Parent[0] <> mBranch) then
    begin
      mCondition := mBranch.Parent[0];
    end;
    if mCondition <> nil then
    begin
      mAssignedNames := nil;
      CollectAssignedNames(mBranch, mAssignedNames);
      if MentionsName(mCondition, mAssignedNames) then
      begin
        Exit(True);
      end;
    end;
    mBranch := mBranch.Parent;
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
  mModel: TComponentModel;
  mCache: IRuleDerivedCache;
  mAllowLazyInit: Boolean;
  mInfo: TClassInfo;
  mParent: string;
  mMembers, mLocals, mReported: TArray<string>;

  // Feld oder Property des Objekts: eigene aus der Klasse, geerbte über TAncestry.
  function IsState(const AName: string): Boolean;
  var
    mMember: TIndexSymbol;
    mUnresolved: string;
  begin
    if (AName = '') or SameText(AName, 'Result') or SameText(AName, 'Self') or IsIn(AName, mLocals) then
    begin
      Exit(False);
    end;
    if IsIn(AName, mMembers) then
    begin
      Exit(True);
    end;
    Result := (mParent <> '') and mModel.Ancestry.FindMember(mParent, AName, mMember, mUnresolved) and
      (mMember.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]);
  end;

  // Geändertes Mitglied an ANode: Ziel einer Zuweisung, Inc/Dec/Include/Exclude, Methode eines Felds mit neu
  // angelegtem Objekt als Argument (FListe.Add(TEintrag.Create)); nil ohne.
  function ChangedTarget(ANode: TSyntaxNode): TSyntaxNode;
  var
    mIndex: Integer;
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
      for mIndex := 1 to ANode.ChildCount - 1 do
      begin
        if ContainsCreate(ANode[mIndex]) then
        begin
          Exit(ANode[0][0]);
        end;
      end;
    end;
  end;

  procedure Visit(ANode, ARoot: TSyntaxNode; const AGetter: string);
  var
    mNode, mTarget: TSyntaxNode;
    mName: string;
    mIndex: Integer;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Continue;
        end;
        mTarget := ChangedTarget(mNode);
        if mTarget <> nil then
        begin
          mName := SelfMemberName(mTarget);
          if IsState(mName) and not IsIn(mName, mReported) and not (mAllowLazyInit and IsLazyInit(mNode, ARoot)) then
          begin
            mReported := mReported + [mName];
            AReport.Add(TTextRange.Create(mTarget.StartPos, mTarget.EndPos),
              cTexts[TComponentsMembersText.GetterChanges].Fmt([AGetter, mName]),
              TRuleConfidence.Medium);
          end;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

var
  mMethod: TMethodImpl;
  mGetters: TArray<string>;
begin
  mCache := TRuleDerived.Open(AContext);
  if not PrepareModel(mCache, AContext, mModel) then
  begin
    Exit;
  end;
  mAllowLazyInit := TRuleOptions.Bool(AContext.Options, 'allowLazyInit', True);
  for mInfo in mModel.Classes do
  begin
    mGetters := GetterNames(mModel, mInfo);
    if mGetters = nil then
    begin
      Continue;
    end;
    mParent := DeclaredParent(mInfo);
    mMembers := StateMembers(mInfo);
    for mMethod in mModel.Methods do
    begin
      if SameText(mMethod.ClassName, mInfo.Name) and IsIn(mMethod.MethodName, mGetters) and
        not mModel.HasToken(mMethod.Block, ['with']) then
      begin
        mLocals := MethodLocalNames(mMethod);
        mReported := nil;
        Visit(mMethod.Block, mMethod.Block, mMethod.MethodName);
      end;
    end;
  end;
end;

{ TEqualsWithoutGetHashCodeRule }

const
  // Feldtypen, bei denen der Standard-Comparer für Records (Byte für Byte) nicht zu Equal passt.
  cBinaryUnsafeTypes: array[0..12] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString',
    'RawByteString', 'UTF8String', 'ShortString', 'Variant', 'OleVariant', 'Double', 'Single', 'Extended', 'Real');
  // Generische Sammlungen, deren erster Typparameter der Schlüssel ist.
  cHashedCollections: array[0..3] of string = ('TDictionary', 'TObjectDictionary', 'THashSet', 'TMultiMap');

function TEqualsWithoutGetHashCodeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('equals-without-gethashcode', TRuleSeverity.Warning,
    cTexts[TComponentsMembersText.EqualsTitle].Text);
end;

/// <summary>Kopf AName im Klassen- bzw. Record-Rumpf ABody; nil ohne.</summary>
function MemberHeader(ABody: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    if (ABody[mIndex].Kind = TSyntaxKind.RoutineHeader) and SameText(ABody[mIndex].Name, AName) then
    begin
      Exit(ABody[mIndex]);
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
  mValue: string;
begin
  if MatchText(ATypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'UTF8String']) then
  begin
    // Vergleicht Equals ohne Groß-/Kleinschreibung, muss der Hashwert es ebenso tun.
    mValue := AField;
    if MatchText(ACompare, ['SameText', 'CompareText']) then
    begin
      mValue := 'LowerCase(' + AField + ')';
    end
    else if MatchText(ACompare, ['AnsiSameText', 'AnsiCompareText']) then
    begin
      mValue := 'AnsiLowerCase(' + AField + ')';
    end;
    Result := Format('THashBobJenkins.GetHashValue(%s, %s)', [mValue, AInitial]);
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
  Result := MatchText(ATypeName, cBinaryUnsafeTypes) or SameText(ATypeName, 'TArray') or
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
    (ANode[0].Kind <> TSyntaxKind.MemberAccess) or not IsIn(ANode[0].Name, cHashedCollections) then
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

/// <summary>Legt ANode (TDictionary&lt;…&gt;.Create) die Sammlung ohne Comparer an: ohne Klammern oder nur mit
/// Konstanten?</summary>
function WithoutComparer(ANode: TSyntaxNode): Boolean;
begin
  Result := not ((ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.Call) and (ANode.Parent[0] = ANode)) or
    OnlyConstants(ANode.Parent);
end;

procedure TEqualsWithoutGetHashCodeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TComponentModel;
  mCache: IRuleDerivedCache;

  // Überschreibt ein Vorfahr (ohne TObject) die Methode AName? AKnown: die Kette ist bekannt.
  function AncestorOverrides(const AClass, AName: string; out AKnown: Boolean): Boolean;
  var
    mChain: TArray<TSymbolLocation>;
    mLocation: TSymbolLocation;
    mMember: TIndexSymbol;
    mObjectMissing: Boolean;
  begin
    Result := False;
    mChain := mModel.Ancestry.Ancestors(AClass, AKnown, mObjectMissing);
    for mLocation in mChain do
    begin
      if not SameText(mLocation.Symbol.Name, 'TObject') then
      begin
        for mMember in mModel.Ancestry.Methods(mLocation) do
        begin
          if SameText(mMember.Name, AName) and mMember.HasDirective('override') then
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
    mIndex: Integer;
    mCompare: string;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1); Vorordnung, damit die Reihenfolge der Felder bleibt.
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and IsIn(mNode.Name, AFields) and
          not IsIn(mNode.Name, ANames) then
        begin
          mCompare := '';
          if (mNode.Parent <> nil) and (mNode.Parent.Kind = TSyntaxKind.Call) and (mNode.Parent[0] <> mNode) then
          begin
            mCompare := mNode.Parent.Name;
          end;
          ANames := ANames + [mNode.Name];
          ACompares := ACompares + [mCompare];
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  // Korrektur: GetHashCode hinter Equals deklarieren und hinter dem Rumpf von Equals umsetzen.
  function HashFix(const AInfo: TClassInfo; AHeader: TSyntaxNode; out AFix: TRuleFix): Boolean;
  var
    mEquals_: TMethodImpl;
    mNames, mCompares: TArray<string>;
    mBody: string;
    mEdit, mUsesEdit: TRuleEdit;
    mEdits: TArray<TRuleEdit>;
    mPosition: TTextPosition;
  begin
    Result := False;
    if not LastMethod(mModel, AInfo.Name, 'Equals', mEquals_) then
    begin
      Exit;
    end;
    mNames := nil;
    mCompares := nil;
    CollectFields(mEquals_.Block, OwnFields(AInfo), mNames, mCompares);
    if mNames = nil then
    begin
      Exit;
    end;
    mBody := HashBody(AInfo, mNames, mCompares, mModel.LineBreak);
    // Edits in Textreihenfolge: Deklaration, uses der Implementierung, Rumpf.
    mPosition := TTextPosition.Create(AHeader.EndPos.Line + 1, 0);
    mEdits := [TRuleEdit.Create(TTextRange.Create(mPosition, mPosition), StringOfChar(' ', AHeader.StartPos.Character) +
      'function GetHashCode: Integer; override;' + mModel.LineBreak)];
    if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(AContext.Tree.Tokens), 'System.Hash', AContext.Namespaces) and
      TUsesClauses.AddUnit(AContext.Tree.Tokens, mEquals_.Decl.StartOffset, 'System.Hash', mModel.LineBreak,
      mUsesEdit) then
    begin
      if mUsesEdit.Range.StartPos.Line < AHeader.StartPos.Line then
      begin
        mEdits := [mUsesEdit] + mEdits;
      end
      else
      begin
        mEdits := mEdits + [mUsesEdit];
      end;
    end;
    mPosition := TTextPosition.Create(mEquals_.Decl.EndPos.Line + 1, 0);
    mEdit := TRuleEdit.Create(TTextRange.Create(mPosition, mPosition), mModel.LineBreak + 'function ' + AInfo.Name +
      '.GetHashCode: Integer;' + mModel.LineBreak + 'begin' + mModel.LineBreak + mBody + 'end;' + mModel.LineBreak);
    mEdits := mEdits + [mEdit];
    AFix := TRuleFix.Create(cTexts[TComponentsMembersText.OverrideHash].Fmt([string.Join(', ', mNames)]), mEdits);
    Result := True;
  end;

  // Equals ohne GetHashCode: melden, mit Korrektur.
  procedure ReportEqualsOnly(const AInfo: TClassInfo);
  var
    mHeader: TSyntaxNode;
    mKnown: Boolean;
    mFix: TRuleFix;
    mFixes: TArray<TRuleFix>;
  begin
    if AncestorOverrides(AInfo.Name, 'GetHashCode', mKnown) or not mKnown then
    begin
      Exit;
    end;
    mHeader := MemberHeader(AInfo.Body, 'Equals');
    mFixes := nil;
    if HashFix(AInfo, mHeader, mFix) then
    begin
      mFixes := [mFix];
    end;
    AReport.Add(TTextRange.Create(mHeader.StartPos, mHeader.EndPos), cTexts[TComponentsMembersText.EqualsOnly].Text,
      TRuleConfidence.High, mFixes);
  end;

  // GetHashCode ohne Equals: melden.
  procedure ReportHashOnly(const AInfo: TClassInfo);
  var
    mHeader: TSyntaxNode;
    mKnown: Boolean;
  begin
    if AncestorOverrides(AInfo.Name, 'Equals', mKnown) or not mKnown then
    begin
      Exit;
    end;
    mHeader := MemberHeader(AInfo.Body, 'GetHashCode');
    AReport.Add(TTextRange.Create(mHeader.StartPos, mHeader.EndPos), cTexts[TComponentsMembersText.HashOnly].Text,
      TRuleConfidence.High);
  end;

  procedure CheckClasses;
  var
    mInfo: TClassInfo;
    mHasEquals, mHasHash: Boolean;
  begin
    for mInfo in mModel.Classes do
    begin
      mHasEquals := mModel.DeclaredWith(mInfo, 'Equals', 'override');
      mHasHash := mModel.DeclaredWith(mInfo, 'GetHashCode', 'override');
      if mHasEquals and not mHasHash then
      begin
        ReportEqualsOnly(mInfo);
      end
      else if mHasHash and not mHasEquals then
      begin
        ReportHashOnly(mInfo);
      end;
    end;
  end;

  // Records der Datei mit class operator Equal und einem Feld, das der Byte-Vergleich falsch vergleicht.
  procedure CollectRecords(ARoot: TSyntaxNode; var ANames: TArray<string>);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.TypeDecl) and IsEqualRecord(mModel, mNode) then
        begin
          ANames := ANames + [mNode.Name];
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  procedure CheckCreates(ARoot: TSyntaxNode; const ARecords: TArray<string>);
  var
    mIndex: Integer;
    mNode, mCollection: TSyntaxNode;
    mKey: string;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mKey := HashedCreateKey(mNode, mCollection);
        if (mKey <> '') and IsIn(mKey, ARecords) and WithoutComparer(mNode) then
        begin
          AReport.Add(TTextRange.Create(mCollection.StartPos, mCollection.EndPos),
            cTexts[TComponentsMembersText.RecordEqual].Fmt(
            [mKey, mCollection.Name]), TRuleConfidence.High);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

var
  mRecords: TArray<string>;
begin
  mCache := TRuleDerived.Open(AContext);
  if not PrepareModel(mCache, AContext, mModel) then
  begin
    Exit;
  end;
  if ContainsText(AContext.Text, 'Equals') or ContainsText(AContext.Text, 'GetHashCode') then
  begin
    CheckClasses;
  end;
  if ContainsText(AContext.Text, 'operator') then
  begin
    mRecords := nil;
    CollectRecords(AContext.Tree.Root, mRecords);
    if mRecords <> nil then
    begin
      CheckCreates(AContext.Tree.Root, mRecords);
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Components.Members', cTexts);

end.
