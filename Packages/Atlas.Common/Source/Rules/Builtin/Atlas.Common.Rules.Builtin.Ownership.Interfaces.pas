unit Atlas.Common.Rules.Builtin.Ownership.Interfaces;

// Leckregeln für Objekte mit Referenzzählung (#1876):
//   interface-object-mixed        Eine lokale Objektvariable einer Klasse mit Referenzzählung (Nachfahre von
//                                 TInterfacedObject ohne eigenes _AddRef/_Release in der Kette) wird als Interface
//                                 weitergegeben und zusätzlich mit Free freigegeben (doppelte Freigabe), oder nur
//                                 vorübergehend als Interface weitergegeben (X as IFoo, IFoo(X) als Argument) und danach
//                                 weiter über die Objektvariable benutzt: Mit dem letzten Interface-Verweis ist das
//                                 Objekt schon freigegeben.
//   interface-cycle-without-weak  Zwei Klassen der Datei halten sich über Interface-Felder gegenseitig fest (direkt
//                                 oder über eine Liste bzw. ein Array von Interfaces), auch eine Klasse mit sich selbst
//                                 (Baum mit Rückverweis), und keines der Felder ist [weak] oder [unsafe]. Experimentell.
//                                 Korrektur: [weak] am Rückverweis, wenn genau eine Seite ein einzelnes Feld ist.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cInterfaceObjectMixedRuleId = 'interface-object-mixed';
  cInterfaceCycleWithoutWeakRuleId = 'interface-cycle-without-weak';

type
  TInterfaceObjectMixedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInterfaceCycleWithoutWeakRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert interface-object-mixed und interface-cycle-without-weak.</summary>
procedure RegisterOwnershipInterfaceRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TInterfaceText = (MixedTitle, DoubleFree, FreedByInterface, CycleTitle, Cycle, AddWeak);

const
  cTexts: array[TInterfaceText] of TAtlasText = (
    (De: 'Objekt mit Referenzzählung als Objekt und als Interface benutzt';
     En: 'Reference-counted object used as object and as interface'),
    (De: '%s (%s mit Referenzzählung) wird als Interface weitergegeben und zusätzlich freigegeben: Der letzte ' +
      'Interface-Verweis gibt das Objekt ein zweites Mal frei.';
     En: '%s (%s with reference counting) is passed on as interface and released as well: the last interface ' +
      'reference releases the object a second time.'),
    (De: '%s (%s mit Referenzzählung) wurde in Zeile %d nur vorübergehend als Interface weitergegeben; mit diesem ' +
      'Verweis ist das Objekt schon freigegeben. Eine Interface-Variable für %s verwenden.';
     En: '%s (%s with reference counting) was passed on only temporarily as interface in line %d; the object was ' +
      'released with that reference. Use an interface variable for %s.'),
    (De: 'Interfaces halten sich gegenseitig ohne [weak]'; En: 'Interfaces reference each other without [weak]'),
    (De: '%s.%s und %s.%s halten sich über Interfaces gegenseitig fest; ohne [weak] auf einer Seite wird keines der ' +
      'Objekte freigegeben.';
     En: '%s.%s and %s.%s keep each other alive through interfaces; without [weak] on one side neither object is ' +
      'released.'),
    (De: '[weak] an %s setzen'; En: 'Add [weak] to %s'));

{$SCOPEDENUMS OFF}

const
  cReleaseMembers: array[0..2] of string = ('Free', 'Destroy', 'DisposeOf');

/// <summary>Folgt AName der Namensregel für Interfaces (IName, auch Unit.IName)?</summary>
function LooksLikeInterface(const AName: string): Boolean;
var
  mName: string;
begin
  mName := AName;
  if mName.Contains('.') then
  begin
    mName := Copy(mName, mName.LastIndexOf('.') + 2, MaxInt);
  end;
  Result := (Length(mName) > 1) and (mName[1] = 'I') and CharInSet(mName[2], ['A'..'Z']);
end;

/// <summary>Bezeichner AName unter ANode (nicht als Mitglied hinter einem Punkt), ohne lokale Routinen.</summary>
function Occurrences(ANode: TSyntaxNode; const AName: string): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      if (AChild.Kind = TSyntaxKind.Identifier) and SameText(AChild.Name, AName) and
        not ((AChild.Parent <> nil) and (AChild.Parent.Kind = TSyntaxKind.MemberAccess) and
        (AChild.Parent[0] <> AChild)) then
      begin
        mFound := mFound + [AChild];
      end;
      Result := (AChild = ANode) or (AChild.Kind <> TSyntaxKind.RoutineDecl);
    end);
  Result := mFound;
end;

/// <summary>Die Anweisung, die ANode enthält.</summary>
function StatementOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Parent <> nil) and not (Result.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.AssignStatement,
    TSyntaxKind.InlineVar, TSyntaxKind.RaiseStatement]) do
  begin
    Result := Result.Parent;
  end;
end;

{ interface-object-mixed }

type
  /// <summary>Wie eine Objektvariable an einer Stelle vorkommt.</summary>
{$SCOPEDENUMS ON}
  TMixedUse = (Use, Release, HeldInterface, TemporaryInterface, Other);
{$SCOPEDENUMS OFF}

  /// <summary>Gemerkte Vorkommen einer Objektvariablen: zuletzt als Interface gehalten, erste vorübergehende
  /// Weitergabe, zuletzt freigegeben, erste Benutzung nach der vorübergehenden Weitergabe.</summary>
  TMixedTrack = record
    Held: TSyntaxNode;
    Temporary: TSyntaxNode;
    Free: TSyntaxNode;
    Later: TSyntaxNode;
  end;

  TMixedScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FAncestry: TAncestry;
    FDerived: IRuleDerivedCache;
    FInterfaceLocals: TArray<string>;
    function Counted(const AClassName: string): Boolean;
    function IsInterfaceTarget(ATarget: TSyntaxNode): Boolean;
    function MemberUse(AParent: TSyntaxNode; ACast: Boolean): TMixedUse;
    function CallStep(AParent, ACurrent: TSyntaxNode; var ACast: Boolean; out AUse: TMixedUse): Boolean;
    function StepUp(AParent, ACurrent: TSyntaxNode; var ACast: Boolean; out AUse: TMixedUse): Boolean;
    function Classify(ANode: TSyntaxNode): TMixedUse;
    procedure CollectSection(ASection: TSyntaxNode; var AObjects: TArray<TPair<string, string>>);
    procedure CheckVariable(ARoutine: TSyntaxNode; const AName, AClassName: string);
    procedure CheckRoutine(ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

constructor TMixedScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

destructor TMixedScan.Destroy;
begin
  FAncestry.Free;
  inherited Destroy;
end;

/// <summary>Zählt die Klasse Verweise wie TInterfacedObject? Die Kette muss TInterfacedObject erreichen, ohne dass
/// eine Stufe _AddRef oder _Release selbst deklariert (TComponent, eigene Zählung).</summary>
function TMixedScan.Counted(const AClassName: string): Boolean;
var
  mName: string;
  mDepth: Integer;
  mType: TSymbolLocation;
  mMethod: TIndexSymbol;
begin
  Result := False;
  mName := AClassName;
  mDepth := 0;
  while (mName <> '') and (mDepth < 64) and not Result do
  begin
    if SameText(mName, 'TInterfacedObject') then
    begin
      Result := True;
    end
    else if FAncestry.FindClass(mName, mType) then
    begin
      for mMethod in FAncestry.Methods(mType) do
      begin
        if MatchText(mMethod.Name, ['_AddRef', '_Release']) then
        begin
          Exit(False);
        end;
      end;
    end;
    mName := FAncestry.ParentOf(mName);
    Inc(mDepth);
  end;
end;

/// <summary>Ist ATarget eine Interface-Variable der Routine oder Result einer Funktion mit Interface-Ergebnis?
/// </summary>
function TMixedScan.IsInterfaceTarget(ATarget: TSyntaxNode): Boolean;
begin
  Result := (ATarget.Kind = TSyntaxKind.Identifier) and MatchText(ATarget.Name, FInterfaceLocals);
end;

/// <summary>X.Free, X.Destroy, X.DisposeOf geben frei (nicht nach einer Umwandlung in ein Interface); jedes andere
/// Mitglied benutzt das Objekt.</summary>
function TMixedScan.MemberUse(AParent: TSyntaxNode; ACast: Boolean): TMixedUse;
begin
  Result := TMixedUse.Use;
  if MatchText(AParent.Name, cReleaseMembers) and not ACast then
  begin
    Result := TMixedUse.Release;
  end;
end;

/// <summary>Vorkommen als Argument von AParent: IFoo(X) wandelt um (weiter nach oben), FreeAndNil(X) gibt frei,
/// ein umgewandeltes Argument einer Routine ist eine vorübergehende Interface-Referenz. Methoden anderer Objekte
/// (Liste.Add(X as IFoo), Registry.Subscribe(…)) behalten den Verweis meist wie eine Interface-Variable.</summary>
function TMixedScan.CallStep(AParent, ACurrent: TSyntaxNode; var ACast: Boolean; out AUse: TMixedUse): Boolean;
begin
  Result := False;
  AUse := TMixedUse.Other;
  if AParent[0] = ACurrent then
  begin
    Exit;
  end;
  if (AParent.ChildCount = 2) and LooksLikeInterface(AParent.Name) then
  begin
    ACast := True;
    Result := True;
  end
  else if SameText(AParent.Name, 'FreeAndNil') then
  begin
    AUse := TMixedUse.Release;
  end
  else if ACast and (AParent[0].Kind = TSyntaxKind.MemberAccess) then
  begin
    AUse := TMixedUse.HeldInterface;
  end
  else if ACast then
  begin
    AUse := TMixedUse.TemporaryInterface;
  end;
end;

/// <summary>Ein Schritt von ACurrent zu AParent: True, wenn weiter nach oben zu gehen ist; sonst steht AUse fest.
/// </summary>
function TMixedScan.StepUp(AParent, ACurrent: TSyntaxNode; var ACast: Boolean; out AUse: TMixedUse): Boolean;
begin
  Result := False;
  AUse := TMixedUse.Other;
  case AParent.Kind of
    TSyntaxKind.MemberAccess:
      AUse := MemberUse(AParent, ACast);
    TSyntaxKind.BinaryExpr:
      begin
        Result := SameText(AParent.Name, 'as') and LooksLikeInterface(AParent[1].Name);
        ACast := ACast or Result;
        AUse := TMixedUse.Use;
      end;
    TSyntaxKind.ParenExpr:
      Result := True;
    TSyntaxKind.Call:
      Result := CallStep(AParent, ACurrent, ACast, AUse);
    TSyntaxKind.AssignStatement:
      if (AParent[0] <> ACurrent) and (ACast or IsInterfaceTarget(AParent[0])) then
      begin
        AUse := TMixedUse.HeldInterface;
      end;
  else
    Result := False;
  end;
end;

/// <summary>Art des Vorkommens ANode vom Knoten aus nach oben.</summary>
function TMixedScan.Classify(ANode: TSyntaxNode): TMixedUse;
var
  mCurrent: TSyntaxNode;
  mCast, mUp: Boolean;
  mUse: TMixedUse;
begin
  Result := TMixedUse.Use;
  mCurrent := ANode;
  mCast := False;
  mUp := True;
  while mUp and (mCurrent.Parent <> nil) do
  begin
    mUp := StepUp(mCurrent.Parent, mCurrent, mCast, mUse);
    if not mUp then
    begin
      Result := mUse;
    end;
    mCurrent := mCurrent.Parent;
  end;
end;

/// <summary>Merkt das Vorkommen ANode der Art AUse in ATrack.</summary>
procedure Track(var ATrack: TMixedTrack; ANode: TSyntaxNode; AUse: TMixedUse);
begin
  if AUse = TMixedUse.HeldInterface then
  begin
    ATrack.Held := ANode;
  end
  else if (AUse = TMixedUse.TemporaryInterface) and (ATrack.Temporary = nil) then
  begin
    ATrack.Temporary := ANode;
  end
  else if AUse = TMixedUse.Release then
  begin
    ATrack.Free := ANode;
  end;
  if (ATrack.Temporary <> nil) and (ATrack.Later = nil) and (AUse <> TMixedUse.TemporaryInterface) and
    (ANode.StartOffset > StatementOf(ATrack.Temporary).EndOffset) then
  begin
    ATrack.Later := ANode;
  end;
end;

procedure TMixedScan.CheckVariable(ARoutine: TSyntaxNode; const AName, AClassName: string);
var
  mNode: TSyntaxNode;
  mTrack: TMixedTrack;
begin
  mTrack := Default(TMixedTrack);
  for mNode in Occurrences(TRoutineBody.BodyOf(ARoutine), AName) do
  begin
    // X := … nach der Weitergabe: ab hier ein anderes Objekt.
    if (mTrack.Temporary <> nil) and (mNode.Parent.Kind = TSyntaxKind.AssignStatement) and
      (mNode.Parent[0] = mNode) then
    begin
      Break;
    end;
    Track(mTrack, mNode, Classify(mNode));
  end;
  if (mTrack.Free <> nil) and ((mTrack.Held <> nil) or (mTrack.Temporary <> nil)) then
  begin
    FReport.Add(TTextRange.Create(StatementOf(mTrack.Free).StartPos, StatementOf(mTrack.Free).EndPos),
      cTexts[TInterfaceText.DoubleFree].Fmt([AName, AClassName]), TRuleConfidence.Medium);
  end
  else if (mTrack.Later <> nil) and (mTrack.Held = nil) then
  begin
    FReport.Add(TTextRange.Create(StatementOf(mTrack.Later).StartPos, StatementOf(mTrack.Later).EndPos),
      cTexts[TInterfaceText.FreedByInterface].Fmt([AName, AClassName, mTrack.Temporary.StartPos.Line + 1, AName]),
      TRuleConfidence.Medium);
  end;
end;

/// <summary>Hat die Funktion ARoutine ein Interface als Ergebnis?</summary>
function ResultIsInterface(ARoutine: TSyntaxNode): Boolean;
var
  mType: TSyntaxNode;
begin
  mType := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mType <> nil then
  begin
    mType := mType.FindChild(TSyntaxKind.TypeReference);
  end;
  Result := (mType <> nil) and LooksLikeInterface(mType.Name);
end;

/// <summary>Interface-Variablen des var-Abschnitts nach FInterfaceLocals, Objekte gezählter Klassen nach AObjects
/// (Name, Klasse).</summary>
procedure TMixedScan.CollectSection(ASection: TSyntaxNode; var AObjects: TArray<TPair<string, string>>);
var
  mDecl: Integer;
  mName, mType: string;
begin
  for mDecl := 0 to ASection.ChildCount - 1 do
  begin
    if (ASection[mDecl].Kind <> TSyntaxKind.VarDecl) or (ASection[mDecl].ChildCount = 0) or
      (ASection[mDecl][0].Kind <> TSyntaxKind.TypeReference) then
    begin
      Continue;
    end;
    mType := ASection[mDecl][0].Name;
    for mName in ASection[mDecl].Name.Split([',']) do
    begin
      if LooksLikeInterface(mType) then
      begin
        FInterfaceLocals := FInterfaceLocals + [Trim(mName)];
      end
      else if Counted(mType) then
      begin
        AObjects := AObjects + [TPair<string, string>.Create(Trim(mName), mType)];
      end;
    end;
  end;
end;

procedure TMixedScan.CheckRoutine(ARoutine: TSyntaxNode);
var
  mIndex: Integer;
  mObjects: TArray<TPair<string, string>>;
  mObject: TPair<string, string>;
begin
  if TRoutineBody.BodyOf(ARoutine) = nil then
  begin
    Exit;
  end;
  FInterfaceLocals := nil;
  mObjects := nil;
  if ResultIsInterface(ARoutine) then
  begin
    FInterfaceLocals := ['Result'];
  end;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if ARoutine[mIndex].Kind = TSyntaxKind.VarSection then
    begin
      CollectSection(ARoutine[mIndex], mObjects);
    end;
  end;
  for mObject in mObjects do
  begin
    CheckVariable(ARoutine, mObject.Key, mObject.Value);
  end;
end;

procedure TMixedScan.Run;
var
  mRoutine: TSyntaxNode;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FDerived := TRuleDerived.Open(FContext);
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(FDerived, FContext));
  for mRoutine in TRuleDerived.Routines(FDerived, FContext) do
  begin
    CheckRoutine(mRoutine);
  end;
end;

{ interface-cycle-without-weak }

type
  /// <summary>Ein Interface-Feld einer Klasse der Datei.</summary>
  TInterfaceField = record
    Node: TSyntaxNode;
    ClassName: string;
    Name: string;
    /// <summary>Interface, auf das das Feld verweist (auch Elementtyp einer Liste).</summary>
    Target: string;
    IsList: Boolean;
    Weak: Boolean;
  end;

  /// <summary>Eine Klasse der Datei mit ihren Interfaces und Interface-Feldern.</summary>
  TCycleClass = record
    Name: string;
    Interfaces: TArray<string>;
    Fields: TArray<TInterfaceField>;
  end;

  TCycleScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FClasses: TArray<TCycleClass>;
    procedure CollectClass(ADecl: TSyntaxNode);
    function IsCycle(AX, AY: Integer; const A, B: TInterfaceField): Boolean;
    procedure ReportPair(const A, B: TInterfaceField);
    procedure CheckClassPair(AX, AY: Integer; ADone: TList<string>);
    procedure CheckPairs;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

constructor TCycleScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

/// <summary>Interface, auf das ein Feldtyp verweist: IFoo, TList&lt;IFoo&gt;, IList&lt;IFoo&gt;,
/// TArray&lt;IFoo&gt; oder array of IFoo; '' sonst.</summary>
function FieldTarget(AType: TSyntaxNode; out AIsList: Boolean): string;
var
  mArgs: TSyntaxNode;
begin
  Result := '';
  AIsList := False;
  if AType.Kind = TSyntaxKind.ArrayType then
  begin
    AType := AType.FindChild(TSyntaxKind.TypeReference);
    AIsList := True;
    if AType = nil then
    begin
      Exit;
    end;
  end;
  if AType.Kind <> TSyntaxKind.TypeReference then
  begin
    Exit;
  end;
  mArgs := AType.FindChild(TSyntaxKind.GenericArgs);
  if (mArgs <> nil) and (mArgs.ChildCount = 1) and LooksLikeInterface(mArgs[0].Name) then
  begin
    AIsList := True;
    Result := mArgs[0].Name;
  end
  else if (mArgs = nil) and LooksLikeInterface(AType.Name) then
  begin
    Result := AType.Name;
  end;
end;

/// <summary>Legt für jeden Namen der Felddeklaration ANode, deren Typ auf ein Interface verweist, ein Feld in
/// AClass an.</summary>
procedure AddFields(var AClass: TCycleClass; ANode: TSyntaxNode; AWeak: Boolean);
var
  mField: TInterfaceField;
  mIsList: Boolean;
  mName, mTarget: string;
begin
  mTarget := FieldTarget(ANode[0], mIsList);
  if mTarget = '' then
  begin
    Exit;
  end;
  for mName in ANode.Name.Split([',']) do
  begin
    mField := Default(TInterfaceField);
    mField.Node := ANode;
    mField.ClassName := AClass.Name;
    mField.Name := Trim(mName);
    mField.Target := mTarget;
    mField.IsList := mIsList;
    mField.Weak := AWeak;
    AClass.Fields := AClass.Fields + [mField];
  end;
end;

procedure TCycleScan.CollectClass(ADecl: TSyntaxNode);
var
  mBody, mNode: TSyntaxNode;
  mClass: TCycleClass;
  mIndex: Integer;
  mWeak: Boolean;
begin
  mBody := ADecl.FindChild(TSyntaxKind.ClassType);
  if mBody = nil then
  begin
    Exit;
  end;
  mClass := Default(TCycleClass);
  mClass.Name := ADecl.Name;
  mWeak := False;
  for mIndex := 0 to mBody.ChildCount - 1 do
  begin
    mNode := mBody[mIndex];
    if (mNode.Kind = TSyntaxKind.TypeReference) and LooksLikeInterface(mNode.Name) then
    begin
      mClass.Interfaces := mClass.Interfaces + [mNode.Name];
    end
    else if (mNode.Kind = TSyntaxKind.Field) and (mNode.ChildCount > 0) then
    begin
      AddFields(mClass, mNode, mWeak);
    end;
    // Ein Attribut gilt für die folgende Deklaration.
    mWeak := (mNode.Kind = TSyntaxKind.Attribute) and (mWeak or MatchText(mNode.Name, ['weak', 'unsafe']));
  end;
  if (mClass.Interfaces <> nil) and (mClass.Fields <> nil) then
  begin
    FClasses := FClasses + [mClass];
  end;
end;

/// <summary>Meldung an beiden Feldern; [weak] am einzelnen Feld, wenn die andere Seite eine Liste ist.</summary>
procedure TCycleScan.ReportPair(const A, B: TInterfaceField);

  procedure ReportAt(const AField, AOther: TInterfaceField);
  var
    mFixes: TArray<TRuleFix>;
    mPos: TTextPosition;
  begin
    mFixes := nil;
    if not AField.IsList and AOther.IsList and not AField.Node.Name.Contains(',') then
    begin
      mPos := AField.Node.StartPos;
      mFixes := [TRuleFix.Create(cTexts[TInterfaceText.AddWeak].Fmt([AField.Name]),
        [TTextEdit.Create(TTextRange.Create(mPos, mPos), '[weak] ')])];
    end;
    FReport.Add(TTextRange.Create(AField.Node.StartPos, AField.Node.EndPos),
      cTexts[TInterfaceText.Cycle].Fmt([AField.ClassName, AField.Name, AOther.ClassName, AOther.Name]),
      TRuleConfidence.Medium, mFixes);
  end;

begin
  ReportAt(A, B);
  if A.Node <> B.Node then
  begin
    ReportAt(B, A);
  end;
end;

/// <summary>Feld A der Klasse AX zeigt auf ein Interface von AY, Feld B von AY auf ein Interface von AX, keins
/// ist [weak]. In derselben Klasse (Baum) muss eine Seite eine Liste und die andere ein einzelnes Feld sein.
/// </summary>
function TCycleScan.IsCycle(AX, AY: Integer; const A, B: TInterfaceField): Boolean;
begin
  Result := not A.Weak and not B.Weak and MatchText(A.Target, FClasses[AY].Interfaces) and
    MatchText(B.Target, FClasses[AX].Interfaces);
  if AX = AY then
  begin
    Result := Result and (A.IsList <> B.IsList);
  end;
end;

/// <summary>Meldet jeden Kreis zwischen Feldern der Klassen AX und AY einmal (ADone merkt gemeldete Paare).
/// </summary>
procedure TCycleScan.CheckClassPair(AX, AY: Integer; ADone: TList<string>);
var
  mA, mB: TInterfaceField;
begin
  for mA in FClasses[AX].Fields do
  begin
    for mB in FClasses[AY].Fields do
    begin
      if IsCycle(AX, AY, mA, mB) and not ADone.Contains(mB.ClassName + '.' + mB.Name + '|' + mA.ClassName + '.' +
        mA.Name) then
      begin
        ADone.Add(mA.ClassName + '.' + mA.Name + '|' + mB.ClassName + '.' + mB.Name);
        ReportPair(mA, mB);
      end;
    end;
  end;
end;

procedure TCycleScan.CheckPairs;
var
  mX, mY: Integer;
  mDone: TList<string>;
begin
  mDone := TList<string>.Create;
  try
    for mX := 0 to High(FClasses) do
    begin
      for mY := mX to High(FClasses) do
      begin
        CheckClassPair(mX, mY, mDone);
      end;
    end;
  finally
    mDone.Free;
  end;
end;

procedure TCycleScan.Run;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.TypeDecl then
      begin
        CollectClass(ANode);
      end;
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
    end);
  CheckPairs;
end;

{ TInterfaceObjectMixedRule }

function TInterfaceObjectMixedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cInterfaceObjectMixedRuleId, TRuleSeverity.Warning,
    cTexts[TInterfaceText.MixedTitle].Text);
end;

procedure TInterfaceObjectMixedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TMixedScan;
begin
  mScan := TMixedScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

{ TInterfaceCycleWithoutWeakRule }

function TInterfaceCycleWithoutWeakRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cInterfaceCycleWithoutWeakRuleId, TRuleSeverity.Hint,
    cTexts[TInterfaceText.CycleTitle].Text);
end;

procedure TInterfaceCycleWithoutWeakRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TCycleScan;
begin
  mScan := TCycleScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

procedure RegisterOwnershipInterfaceRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TInterfaceObjectMixedRule.Create);
  ARegistry.Register(TInterfaceCycleWithoutWeakRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Ownership.Interfaces', cTexts);

end.
