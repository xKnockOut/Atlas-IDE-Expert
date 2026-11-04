unit Atlas.Common.Rules.Builtin.Ownership.ComponentInterface;

// Regel aus Atlas.Common.Rules.Builtin.Ownership ausgelagert (Länge der Unit):
//   component-interface-dangling  Ein Nachfahr von TComponent (Option componentClasses) wird als Interface in
//                     einem Feld, einer globalen Variablen oder einer Liste gespeichert (#1090): FAnsicht as IFoo als
//                     Argument von Bus.Anmelden, FListe.Add …, die Zuweisung an ein Ziel außerhalb der Routine bzw.
//                     an ein Interface-Feld, Add/Insert in TList<IFoo>/TInterfaceList. TComponent zählt keine
//                     Referenzen; gibt die Datei dasselbe Objekt frei (Free, Release, DisposeOf, FreeAndNil), zeigt
//                     das Interface danach ins Leere. Still bei einer Abmeldung irgendwo in der Datei
//                     (FreeNotification, anderer Aufruf am selben Empfänger mit dem Objekt, Clear, weitere Zuweisung
//                     an dasselbe Ziel), bei Klassen mit eigenem _Release und wenn die Kette der Vorfahren abbricht.
//                     Korrektur: Empfänger.Abmelden(…) bzw. Ziel := nil vor der ersten Freigabe; Abmelden nur, wenn
//                     der Typ des Empfängers das Gegenstück hat. Ebenso gemeldet (ohne Korrektur): Nachfahren von
//                     TInterfacedObject, die so gespeichert und zusätzlich mit Free freigegeben werden.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TComponentInterfaceDanglingRule = class(TInterfacedObject, IRule)
  public const
    /// <summary>Aufrufe, die ein Interface am Empfänger speichern, und ihr Gegenstück ('' = keins).</summary>
    StoreMethods: array[0..14] of string = ('Add', 'Insert', 'AddOrSetValue', 'Push', 'Enqueue', 'Attach',
      'Subscribe', 'Register', 'RegisterObserver', 'AddObserver', 'AddListener', 'Anmelden', 'Registrieren',
      'Hinzufuegen', 'AddHandler');
    RemoveCounterparts: array[0..14] of string = ('Remove', 'Remove', '', '', '', 'Detach', 'Unsubscribe',
      'Unregister', 'UnregisterObserver', 'RemoveObserver', 'RemoveListener', 'Abmelden', 'Abmelden', 'Entfernen',
      'RemoveHandler');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Gegenstück zum speichernden Aufruf AMethod (Anmelden → Abmelden); '' ohne.</summary>
    class function Counterpart(const AMethod: string): string; static;
  end;

/// <summary>Registriert die Regel component-interface-dangling.</summary>
procedure RegisterOwnershipComponentInterfaceRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.Ownership;

const
  ComponentInterfaceDanglingRuleId = 'component-interface-dangling';

{ TComponentInterfaceDanglingRule }

function TComponentInterfaceDanglingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ComponentInterfaceDanglingRuleId, TRuleSeverity.Warning,
    'Interface auf eine Komponente ohne Referenzzählung bleibt nach der Freigabe gespeichert');
end;

class function TComponentInterfaceDanglingRule.Counterpart(const AMethod: string): string;
var
  Index: Integer;
begin
  for Index := 0 to High(StoreMethods) do
  begin
    if SameText(StoreMethods[Index], AMethod) then
    begin
      Exit(RemoveCounterparts[Index]);
    end;
  end;
  Result := '';
end;

const
  // VCL- und FMX-Klassen, die von TComponent erben: Ohne Index endet die Kette der Vorfahren oft bei ihnen.
  KnownComponents: array[0..16] of string = ('TComponent', 'TControl', 'TWinControl', 'TCustomControl',
    'TGraphicControl', 'TScrollingWinControl', 'TCustomForm', 'TForm', 'TCustomFrame', 'TFrame', 'TDataModule',
    'TCommonCustomForm', 'TCustomPanel', 'TPanel', 'TStyledControl', 'TFmxObject', 'TCustomDataModule');
  FreeMethods: array[0..3] of string = ('Free', 'Release', 'DisposeOf', 'Destroy');

type
  /// <summary>Eine Freigabe in der Datei: Anweisung und freigegebener Ausdruck.</summary>
  TRelease = record
    Statement: TSyntaxNode;
    Target: TSyntaxNode;
  end;

  /// <summary>Eine Speicherung des Objekts als Interface und was die Regel darüber weiß.</summary>
  TInterfaceStore = record
    /// <summary>Gespeicherter Ausdruck samt Klammern ("X as IFoo" oder X).</summary>
    Value: TSyntaxNode;
    /// <summary>Zuweisung oder Aufruf, der speichert.</summary>
    Parent: TSyntaxNode;
    ObjectNode: TSyntaxNode;
    /// <summary>Ziel der Speicherung: Empfänger des Aufrufs bzw. linke Seite der Zuweisung.</summary>
    Holder: TSyntaxNode;
    InterfaceName: string;
    IsCall: Boolean;
    ObjectSymbol: TResolvedSymbol;
    ObjectType: TResolvedSymbol;
    /// <summary>Basisklasse ohne Referenzzählung bzw. TInterfacedObject.</summary>
    Base: string;
    Release: TRelease;
  end;

  /// <summary>Prüft eine Datei auf component-interface-dangling.</summary>
  TComponentInterfaceScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FResolver: TNameResolver;
    FAncestry: TAncestry;
    FFileName: string;
    FBases: TArray<string>;
    FReleases: TArray<TRelease>;
    FCalls: TArray<TSyntaxNode>;
    FAssignments: TArray<TSyntaxNode>;
    FClears: TArray<TSyntaxNode>;
    function NodeText(ANode: TSyntaxNode): string;
    function Normalized(ANode: TSyntaxNode): string;
    function Resolve(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
    function IsLocal(ANode: TSyntaxNode): Boolean;
    function KnownBase(const AName: string): string;
    function DeclaresRelease(const AName: string): Boolean;
    function ComponentBase(const AClass: string): string;
    function Mentions(ANode: TSyntaxNode; const AObject: TResolvedSymbol): Boolean;
    function FreeNotified(const AObject: TResolvedSymbol): Boolean;
    function RemovesObject(ACall: TSyntaxNode; const AObject: TResolvedSymbol): Boolean;
    function RemovedFromHolder(const AStore: TInterfaceStore): Boolean;
    function Reassigned(const AStore: TInterfaceStore): Boolean;
    function Unregistered(const AStore: TInterfaceStore): Boolean;
    function UnregisterCall(const AStore: TInterfaceStore; out ALine: string): Boolean;
    function UnregisterFix(const AStore: TInterfaceStore; out AFix: TRuleFix): Boolean;
    function HolderListType(AHolder: TSyntaxNode): string;
    function AssignTarget(var AStore: TInterfaceStore): Boolean;
    function CallTarget(var AStore: TInterfaceStore): Boolean;
    function StoreOf(AValue: TSyntaxNode; out AStore: TInterfaceStore): Boolean;
    function ComponentObject(var AStore: TInterfaceStore): Boolean;
    function FirstRelease(var AStore: TInterfaceStore): Boolean;
    procedure ReportStore(const AStore: TInterfaceStore);
    procedure Inspect(AValue: TSyntaxNode);
    procedure CollectStatement(ANode: TSyntaxNode);
    procedure Collect(ANode: TSyntaxNode);
    procedure Visit(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
  begin
    Result := Result[0];
  end;
end;

/// <summary>Äußerster Knoten um ANode, der nur aus Klammern besteht.</summary>
function Outer(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Parent <> nil) and (Result.Parent.Kind = TSyntaxKind.ParenExpr) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Ein einfacher Name (X oder Self.X), außer Self selbst.</summary>
function IsObjectName(ANode: TSyntaxNode): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.Identifier:
      Result := not SameText(ANode.Name, 'Self');
    TSyntaxKind.MemberAccess:
      Result := (ANode.ChildCount = 1) and (ANode[0].Kind = TSyntaxKind.Identifier) and
        SameText(ANode[0].Name, 'Self');
  else
    Result := False;
  end;
end;

function SameSymbol(const A, B: TResolvedSymbol): Boolean;
begin
  Result := SameText(A.Name, B.Name) and SameText(A.FileName, B.FileName) and
    (A.Range.StartPos.Line = B.Range.StartPos.Line) and (A.Range.StartPos.Character = B.Range.StartPos.Character);
end;

/// <summary>Zugriff X.Name ohne Argumentklammern, Name aus ANames.</summary>
function IsMemberNamed(ANode: TSyntaxNode; const ANames: array of string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and MatchText(ANode.Name, ANames);
end;

/// <summary>Aufgerufener Ausdruck mit Empfänger (X.Methode).</summary>
function IsMemberCall(ACallee: TSyntaxNode): Boolean;
begin
  Result := (ACallee.Kind = TSyntaxKind.MemberAccess) and (ACallee.ChildCount > 0);
end;

/// <summary>Ausdruck einer Aufrufanweisung; bei X.Methode(…) der Zugriff X.Methode.</summary>
function StatementExpression(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  if (Result.Kind = TSyntaxKind.Call) and (Result.ChildCount > 0) and (Result[0].Kind = TSyntaxKind.MemberAccess) then
  begin
    Result := Result[0];
  end;
end;

/// <summary>Freigegebener Ausdruck in X.Free, X.Release … bzw. FreeAndNil(X); nil sonst.</summary>
function ReleaseTarget(AExpression: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if IsMemberNamed(AExpression, FreeMethods) then
  begin
    Result := AExpression[0];
  end
  else if (AExpression.Kind = TSyntaxKind.Call) and SameText(AExpression.Name, 'FreeAndNil') and
    (AExpression.ChildCount = 2) then
  begin
    Result := AExpression[1];
  end;
end;

/// <summary>Interface der Elemente einer Liste von Interfaces (TList&lt;IFoo&gt;, TInterfaceList); '' sonst.</summary>
function ListInterface(const AListType: string): string;
begin
  Result := '';
  if MatchText(AListType, ['TInterfaceList', 'System.Classes.TInterfaceList', 'Classes.TInterfaceList']) then
  begin
    Result := 'IInterface';
  end
  else if StartsText('TList<', AListType) and EndsText('>', AListType) and
    TSelfAsInterfaceInConstructorRule.IsInterfaceType(Copy(AListType, 7, Length(AListType) - 7)) then
  begin
    Result := Copy(AListType, 7, Length(AListType) - 7);
  end;
end;

/// <summary>Kandidat für eine Speicherung: "X as IFoo" oder ein Name als Wert einer Zuweisung bzw. eines Aufrufs.</summary>
function IsStoreCandidate(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  if (ANode.Kind = TSyntaxKind.BinaryExpr) and SameText(ANode.Name, 'as') and (ANode.ChildCount = 2) then
  begin
    Exit(True);
  end;
  mParent := Outer(ANode).Parent;
  Result := IsObjectName(ANode) and (mParent <> nil) and
    (mParent.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.Call]);
end;

/// <summary>Objekt und Interface aus AValue ("X as IFoo" oder X); False, wenn kein einfacher Name gespeichert
/// wird oder "as" kein Interface nennt.</summary>
function SplitAs(AValue: TSyntaxNode; var AStore: TInterfaceStore): Boolean;
begin
  AStore.ObjectNode := AValue;
  AStore.InterfaceName := '';
  if AValue.Kind = TSyntaxKind.BinaryExpr then
  begin
    AStore.ObjectNode := Unwrapped(AValue[0]);
    if (AValue[1].Kind <> TSyntaxKind.Identifier) or
      not TSelfAsInterfaceInConstructorRule.IsInterfaceType(AValue[1].Name) then
    begin
      Exit(False);
    end;
    AStore.InterfaceName := AValue[1].Name;
  end;
  Result := IsObjectName(AStore.ObjectNode);
end;

/// <summary>Wird der Wert rechts zugewiesen?</summary>
function IsAssignStore(const AStore: TInterfaceStore): Boolean;
begin
  Result := (AStore.Parent.Kind = TSyntaxKind.AssignStatement) and (AStore.Parent.ChildCount = 2) and
    (AStore.Parent[1] = AStore.Value);
end;

/// <summary>Wird der Wert als Argument eines speichernden Aufrufs (Add, Anmelden …) übergeben?</summary>
function IsCallStore(const AStore: TInterfaceStore): Boolean;
begin
  Result := (AStore.Parent.Kind = TSyntaxKind.Call) and (AStore.Parent.ChildCount >= 2) and
    (AStore.Parent[0] <> AStore.Value) and
    IsMemberNamed(AStore.Parent[0], TComponentInterfaceDanglingRule.StoreMethods);
end;

/// <summary>Dateiname für den Namensauflöser: Datei, relativer Pfad oder Unitname.</summary>
function ContextFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
  begin
    Result := AContext.RelativePath;
  end;
  if Result = '' then
  begin
    Result := AContext.UnitName + '.pas';
  end;
end;

{ TComponentInterfaceScan }

constructor TComponentInterfaceScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

function TComponentInterfaceScan.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Text eines Ausdrucks ohne führendes "Self." und ohne Leerraum, zum Vergleichen.</summary>
function TComponentInterfaceScan.Normalized(ANode: TSyntaxNode): string;
begin
  Result := StringReplace(UpperCase(NodeText(ANode)), ' ', '', [rfReplaceAll]);
  if StartsStr('SELF.', Result) then
  begin
    Result := Copy(Result, 6, MaxInt);
  end;
end;

function TComponentInterfaceScan.Resolve(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
var
  mTypeFound: Boolean;
begin
  Result := FResolver.NodeType(FContext.Tree, FFileName, ANode, ASymbol, AType, mTypeFound) and mTypeFound;
end;

/// <summary>Lokale Variable oder Parameter (auch als Empfänger einer Kette L.X)?</summary>
function TComponentInterfaceScan.IsLocal(ANode: TSyntaxNode): Boolean;
var
  mFirst: TSyntaxNode;
begin
  mFirst := ANode;
  while (mFirst.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Call]) and
    (mFirst.ChildCount > 0) do
  begin
    mFirst := mFirst[0];
  end;
  if mFirst.Kind <> TSyntaxKind.Identifier then
  begin
    Exit(True);
  end;
  if SameText(mFirst.Name, 'Self') then
  begin
    Exit(False);
  end;
  Result := FResolver.ResolveChain(FContext.Tree, FFileName, [mFirst.Name], mFirst.StartOffset).Kind =
    TResolvedKind.Local;
end;

/// <summary>AName selbst als Basis ohne Referenzzählung (Option componentClasses, bekannte VCL/FMX-Klasse) bzw.
/// TInterfacedObject; '' sonst.</summary>
function TComponentInterfaceScan.KnownBase(const AName: string): string;
begin
  if MatchText(AName, FBases) then
  begin
    Result := AName;
  end
  else if MatchText('TComponent', FBases) and MatchText(AName, KnownComponents) then
  begin
    Result := 'TComponent';
  end
  else if SameText(AName, 'TInterfacedObject') then
  begin
    Result := AName;
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Deklariert die Klasse AName ein eigenes _Release (zählt also selbst)?</summary>
function TComponentInterfaceScan.DeclaresRelease(const AName: string): Boolean;
var
  mFound: TSymbolLocation;
  mMethod: TIndexSymbol;
begin
  Result := False;
  if FAncestry.FindClass(AName, mFound) then
  begin
    for mMethod in FAncestry.Methods(mFound) do
    begin
      if SameText(mMethod.Name, '_Release') then
      begin
        Exit(True);
      end;
    end;
  end;
end;

/// <summary>Basisklasse ohne Referenzzählung, von der AClass erbt (Option componentClasses), bzw.
/// TInterfacedObject; '' wenn nichts davon oder wenn die Kette abbricht. Deklariert eine Klasse darunter _Release,
/// zählt sie selbst und gilt nicht.</summary>
function TComponentInterfaceScan.ComponentBase(const AClass: string): string;
var
  mName: string;
  mDepth: Integer;
begin
  Result := '';
  mName := AClass;
  mDepth := 0;
  while (mName <> '') and (mDepth < 64) do
  begin
    Result := KnownBase(mName);
    if (Result <> '') or MatchText(mName, ['TObject', 'TInterfacedPersistent']) or DeclaresRelease(mName) then
    begin
      Exit;
    end;
    mName := FAncestry.ParentOf(mName);
    Inc(mDepth);
  end;
end;

/// <summary>Kommt das Objekt AObject in ANode vor (X, X as IFoo, Self.X)?</summary>
function TComponentInterfaceScan.Mentions(ANode: TSyntaxNode; const AObject: TResolvedSymbol): Boolean;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mChild: Integer;
  mSymbol, mType: TResolvedSymbol;
begin
  // Iterativ (Bericht M1).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if IsObjectName(mNode) and SameText(Normalized(mNode), AObject.Name) and Resolve(mNode, mSymbol, mType) and
        SameSymbol(mSymbol, AObject) then
      begin
        Exit(True);
      end;
      for mChild := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mChild]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Meldet die Datei FreeNotification auf dem Objekt an?</summary>
function TComponentInterfaceScan.FreeNotified(const AObject: TResolvedSymbol): Boolean;
var
  mCall, mCallee: TSyntaxNode;
  mSymbol, mType: TResolvedSymbol;
begin
  for mCall in FCalls do
  begin
    mCallee := mCall[0];
    if IsMemberCall(mCallee) and SameText(mCallee.Name, 'FreeNotification') and
      Resolve(mCallee[0], mSymbol, mType) and SameSymbol(mSymbol, AObject) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Leert der Aufruf ACall den Empfänger (Clear) oder bekommt er das Objekt als Argument?</summary>
function TComponentInterfaceScan.RemovesObject(ACall: TSyntaxNode; const AObject: TResolvedSymbol): Boolean;
var
  mArgument: Integer;
begin
  Result := SameText(ACall[0].Name, 'Clear');
  mArgument := 1;
  while not Result and (mArgument < ACall.ChildCount) do
  begin
    Result := Mentions(ACall[mArgument], AObject);
    Inc(mArgument);
  end;
end;

/// <summary>Ein anderer Aufruf am selben Empfänger mit dem Objekt als Argument bzw. Clear (auch ohne Klammern).</summary>
function TComponentInterfaceScan.RemovedFromHolder(const AStore: TInterfaceStore): Boolean;
var
  mCall, mCallee: TSyntaxNode;
  mHolder: string;
begin
  mHolder := Normalized(AStore.Holder);
  for mCall in FCalls do
  begin
    if (mCall <> AStore.Parent) and IsMemberCall(mCall[0]) and (Normalized(mCall[0][0]) = mHolder) and
      RemovesObject(mCall, AStore.ObjectSymbol) then
    begin
      Exit(True);
    end;
  end;
  // Clear ohne Klammern ist eine Anweisung aus MemberAccess.
  for mCallee in FClears do
  begin
    if Normalized(mCallee[0]) = mHolder then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Eine weitere Zuweisung an dieselbe Stelle.</summary>
function TComponentInterfaceScan.Reassigned(const AStore: TInterfaceStore): Boolean;
var
  mAssignment: TSyntaxNode;
  mHolder: string;
begin
  mHolder := Normalized(AStore.Holder);
  for mAssignment in FAssignments do
  begin
    if (mAssignment <> AStore.Parent) and (Normalized(mAssignment[0]) = mHolder) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Gibt es eine Abmeldung? FreeNotification auf dem Objekt, ein anderer Aufruf am selben Empfänger mit
/// dem Objekt als Argument bzw. Clear, eine weitere Zuweisung an dieselbe Stelle.</summary>
function TComponentInterfaceScan.Unregistered(const AStore: TInterfaceStore): Boolean;
begin
  if FreeNotified(AStore.ObjectSymbol) then
  begin
    Result := True;
  end
  else if AStore.IsCall then
  begin
    Result := RemovedFromHolder(AStore);
  end
  else
  begin
    Result := Reassigned(AStore);
  end;
end;

/// <summary>Zeile Empfänger.Gegenstück(Argument); False, wenn der Typ des Empfängers kein Gegenstück hat.</summary>
function TComponentInterfaceScan.UnregisterCall(const AStore: TInterfaceStore; out ALine: string): Boolean;
var
  mMethod: string;
  mSymbol, mType, mMember: TResolvedSymbol;
begin
  ALine := '';
  mMethod := TComponentInterfaceDanglingRule.Counterpart(AStore.Parent[0].Name);
  // Das Gegenstück muss es am Typ des Empfängers geben.
  Result := (mMethod <> '') and Resolve(AStore.Holder, mSymbol, mType) and
    FResolver.FindMember(mType, mMethod, mMember);
  if Result then
  begin
    ALine := NodeText(AStore.Holder) + '.' + mMethod + '(' + NodeText(AStore.Value) + ');';
  end;
end;

/// <summary>Abmeldung vor der Freigabe einfügen: Empfänger.Gegenstück(Argument); bzw. Ziel := nil;.</summary>
function TComponentInterfaceScan.UnregisterFix(const AStore: TInterfaceStore; out AFix: TRuleFix): Boolean;
var
  mStatement: TSyntaxNode;
  mLine: string;
begin
  mStatement := AStore.Release.Statement;
  Result := TRoutineBody.InList(mStatement) and (mStatement.StartPos.Line = mStatement.EndPos.Line);
  if Result and AStore.IsCall then
  begin
    Result := UnregisterCall(AStore, mLine);
  end
  else
  begin
    mLine := NodeText(AStore.Holder) + ' := nil;';
  end;
  if Result then
  begin
    AFix := TRuleFix.Create('Abmeldung vor der Freigabe einfügen',
      [TRoutineBody.InsertBefore(FContext.Text, mStatement, mLine)]);
  end;
end;

/// <summary>Deklarierter Typ der Liste AHolder samt Typargumenten; TList&lt;T&gt; muss nicht im Index stehen.</summary>
function TComponentInterfaceScan.HolderListType(AHolder: TSyntaxNode): string;
var
  mSymbol: TResolvedSymbol;
begin
  if AHolder.Kind = TSyntaxKind.Identifier then
  begin
    mSymbol := FResolver.ResolveChain(FContext.Tree, FFileName, [AHolder.Name], AHolder.StartOffset);
  end
  else
  begin
    mSymbol := FResolver.ResolveChain(FContext.Tree, FFileName, ['Self', AHolder.Name], AHolder.StartOffset);
  end;
  Result := mSymbol.TypeName;
  if (mSymbol.TypeArgs <> '') and (Pos('<', Result) = 0) then
  begin
    Result := Result + '<' + mSymbol.TypeArgs + '>';
  end;
end;

/// <summary>Zuweisung: Ziel ist die linke Seite; ohne "as" muss sie ein Interface sein.</summary>
function TComponentInterfaceScan.AssignTarget(var AStore: TInterfaceStore): Boolean;
var
  mSymbol, mType: TResolvedSymbol;
begin
  AStore.IsCall := False;
  AStore.Holder := AStore.Parent[0];
  Result := True;
  if AStore.InterfaceName = '' then
  begin
    Result := Resolve(AStore.Holder, mSymbol, mType) and (mType.SymbolKind = TIndexSymbolKind.InterfaceType);
    if Result then
    begin
      AStore.InterfaceName := mType.Name;
    end;
  end;
end;

/// <summary>Speichernder Aufruf: Ziel ist der Empfänger; ohne "as" nur Listen von Interfaces (TList&lt;IFoo&gt;,
/// TInterfaceList).</summary>
function TComponentInterfaceScan.CallTarget(var AStore: TInterfaceStore): Boolean;
begin
  AStore.IsCall := True;
  AStore.Holder := AStore.Parent[0][0];
  Result := True;
  if AStore.InterfaceName = '' then
  begin
    Result := MatchText(AStore.Parent[0].Name, ['Add', 'Insert']) and IsObjectName(AStore.Holder);
    if Result then
    begin
      AStore.InterfaceName := ListInterface(HolderListType(AStore.Holder));
      Result := AStore.InterfaceName <> '';
    end;
  end;
end;

/// <summary>Wird hier ein Objekt als Interface gespeichert? AValue ist "X as IFoo" oder X selbst.</summary>
function TComponentInterfaceScan.StoreOf(AValue: TSyntaxNode; out AStore: TInterfaceStore): Boolean;
begin
  AStore := Default(TInterfaceStore);
  AStore.Value := Outer(AValue);
  AStore.Parent := AStore.Value.Parent;
  Result := (AStore.Parent <> nil) and SplitAs(AValue, AStore);
  if Result and IsAssignStore(AStore) then
  begin
    Result := AssignTarget(AStore);
  end
  else if Result and IsCallStore(AStore) then
  begin
    Result := CallTarget(AStore);
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Ist das gespeicherte Objekt ein Feld oder eine Variable einer Klasse ohne Referenzzählung?</summary>
function TComponentInterfaceScan.ComponentObject(var AStore: TInterfaceStore): Boolean;
begin
  Result := Resolve(AStore.ObjectNode, AStore.ObjectSymbol, AStore.ObjectType) and
    (AStore.ObjectSymbol.SymbolKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Variable]) and
    (AStore.ObjectType.SymbolKind = TIndexSymbolKind.ClassType);
  if Result then
  begin
    AStore.Base := ComponentBase(AStore.ObjectType.Name);
    Result := AStore.Base <> '';
  end;
end;

/// <summary>Erste Freigabe desselben Objekts in der Datei.</summary>
function TComponentInterfaceScan.FirstRelease(var AStore: TInterfaceStore): Boolean;
var
  mIndex: Integer;
  mSymbol, mType: TResolvedSymbol;
begin
  for mIndex := 0 to High(FReleases) do
  begin
    if Resolve(FReleases[mIndex].Target, mSymbol, mType) and SameSymbol(mSymbol, AStore.ObjectSymbol) then
    begin
      AStore.Release := FReleases[mIndex];
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TComponentInterfaceScan.ReportStore(const AStore: TInterfaceStore);
var
  mFixes: TArray<TRuleFix>;
  mFix: TRuleFix;
begin
  // Referenzgezählt: Free gibt das Objekt frei, obwohl das gespeicherte Interface es noch hält; eine Abmeldung
  // davor gäbe es schon frei (Zähler 0), Free wäre dann die zweite Freigabe.
  if SameText(AStore.Base, 'TInterfacedObject') then
  begin
    FReport.Add(TTextRange.Create(AStore.Parent.StartPos, AStore.Parent.EndPos), Format('%s ist referenzgezählt ' +
      '(TInterfacedObject); %s gibt es frei, obwohl %s noch ein %s darauf hält.', [AStore.ObjectType.Name,
      NodeText(AStore.Release.Statement), NodeText(AStore.Holder), AStore.InterfaceName]), TRuleConfidence.Medium);
  end
  else if not Unregistered(AStore) then
  begin
    mFixes := nil;
    if UnregisterFix(AStore, mFix) then
    begin
      mFixes := [mFix];
    end;
    FReport.Add(TTextRange.Create(AStore.Parent.StartPos, AStore.Parent.EndPos), Format('%s ist ein %s ohne ' +
      'Referenzzählung; nach %s hält %s ein ungültiges %s.', [AStore.ObjectType.Name, AStore.Base,
      NodeText(AStore.Release.Statement), NodeText(AStore.Holder), AStore.InterfaceName]), TRuleConfidence.Medium,
      mFixes);
  end;
end;

/// <summary>Meldet AValue, wenn es ein Objekt ohne Referenzzählung außerhalb der Routine als Interface speichert
/// und die Datei das Objekt freigibt.</summary>
procedure TComponentInterfaceScan.Inspect(AValue: TSyntaxNode);
var
  mStore: TInterfaceStore;
begin
  // Ziel der Speicherung: Feld, globale Variable oder Liste, kein lokaler Name.
  if StoreOf(AValue, mStore) and not IsLocal(mStore.Holder) and ComponentObject(mStore) and
    FirstRelease(mStore) then
  begin
    ReportStore(mStore);
  end;
end;

/// <summary>Freigaben (X.Free, X.Release …, FreeAndNil(X)) und Clear in einer Aufrufanweisung merken.</summary>
procedure TComponentInterfaceScan.CollectStatement(ANode: TSyntaxNode);
var
  mExpression: TSyntaxNode;
  mRelease: TRelease;
begin
  mExpression := StatementExpression(ANode[0]);
  mRelease.Statement := ANode;
  mRelease.Target := ReleaseTarget(mExpression);
  if (mRelease.Target <> nil) and IsObjectName(mRelease.Target) then
  begin
    FReleases := FReleases + [mRelease];
  end;
  if IsMemberNamed(mExpression, ['Clear']) then
  begin
    FClears := FClears + [mExpression];
  end;
end;

procedure TComponentInterfaceScan.Collect(ANode: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mChild: Integer;
begin
  // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      case mNode.Kind of
        TSyntaxKind.Call:
          FCalls := FCalls + [mNode];
        TSyntaxKind.AssignStatement:
          if mNode.ChildCount = 2 then
          begin
            FAssignments := FAssignments + [mNode];
          end;
        TSyntaxKind.CallStatement:
          if mNode.ChildCount > 0 then
          begin
            CollectStatement(mNode);
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      for mChild := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mChild]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TComponentInterfaceScan.Visit(ANode: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mChild: Integer;
begin
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if IsStoreCandidate(mNode) then
      begin
        Inspect(mNode);
      end;
      for mChild := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mChild]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TComponentInterfaceScan.Run;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FBases := TRuleOptions.Strings(FContext.Options, 'componentClasses', ['TComponent']);
  FFileName := ContextFileName(FContext);
  Collect(FContext.Tree.Root);
  if FReleases = nil then
  begin
    Exit;
  end;
  FResolver := TNameResolver.Create(FContext.Index, FContext.EnsureUnit, FContext.TreeUnits);
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext));
  try
    FResolver.Namespaces := FContext.Namespaces;
    Visit(FContext.Tree.Root);
  finally
    FreeAndNil(FAncestry);
    FreeAndNil(FResolver);
  end;
end;

{ TComponentInterfaceDanglingRule }

procedure TComponentInterfaceDanglingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TComponentInterfaceScan;
begin
  mScan := TComponentInterfaceScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

procedure RegisterOwnershipComponentInterfaceRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TComponentInterfaceDanglingRule.Create);
end;

end.
