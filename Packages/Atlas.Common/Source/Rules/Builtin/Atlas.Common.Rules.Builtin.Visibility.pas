unit Atlas.Common.Rules.Builtin.Visibility;

// Regeln zur Sichtbarkeit von Klassenmitgliedern (#909, Gruppe Compiler vorab):
//   inaccessible-member  Zugriff auf ein Mitglied, das an der Stelle nicht
//                        sichtbar ist (#1008): A.B mit B private bzw. strict
//                        private einer anderen Unit oder Klasse (wie E2361),
//                        protected bzw. strict protected außerhalb der Unit und
//                        der Nachfahren (wie E2362); Instanzmitglieder in einer
//                        Klassenmethode oder statischen Methode (wie E2124);
//                        Properties, die auf ein private-Mitglied eines
//                        Vorfahren derselben Unit verweisen (wie W1045, als
//                        Warnung).
//   unused-private-member
//                        private bzw. strict private Feld, Methode, Konstante
//                        oder Property, die in der Unit nirgends vorkommt
//                        (#1020, wie H2219, aber auch für Felder; Option
//                        includeFields). Ausnahmen kommen aus dem Dienst „gilt
//                        als verwendet“ (Rules.ConsideredUsed, #1102): u. a.
//                        message, virtual, dynamic, override, abstract,
//                        Konstruktoren, Operatoren, Mitglieder mit Attributen
//                        (RTTI), Zugriffsmethoden und Interface-Methoden. Ist
//                        die Vorfahrenkette nicht bekannt, gelten Methoden von
//                        Typen mit Interfaces als verwendet. Dazu Namen aus der
//                        Formulardatei und Units mit Include-Dateien.
//                        deadCode.keepAttributes und deadCode.keepPatterns
//                        (#64) gelten auch hier.
//                        Verwendung ist jedes Vorkommen des Namens als
//                        Bezeichner außer Deklarationen und Methodenköpfen,
//                        auch in inaktiven Zweigen. Korrektur: Deklaration
//                        (samt ///-Doku) und den Rumpf einer Methode entfernen.
//
// Grundlage ist die Namensauflösung: Ein Zugriff gilt erst als unsichtbar, wenn
// die Auflösung den Empfänger und seinen Typ sicher kennt, das Mitglied mit
// Rücksicht auf die Sichtbarkeit nicht findet und ohne sie (DeclaredMember)
// schon. Deklarationen in bedingten Zweigen, Methoden von Helfern und
// verschachtelten Typen (die mehr sehen dürfen) bleiben still.
//
// Nicht strenger als dcc (#1328, Minimalfälle in Tests/DccFaelle): Ein class
// constructor bzw. class destructor ist nie Ziel eines Aufrufs; TX.Create
// meint dann den geerbten Konstruktor (IM4). In einer Klassenmethode gilt ein
// Aufruf als erreichbar, sobald eine Überladung eine Klassenmethode ist (IM5).
// protected-Mitglieder eines generischen Empfängers (TKnoten<T>) übersetzt
// dcc aus generischem Code fremder Units (Spring4D, IM1, IM2); aus nicht
// generischem Code (SG3) und bei strict protected meldet es E2362.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  InaccessibleMemberRuleId = 'inaccessible-member';
  UnusedPrivateMemberRuleId = 'unused-private-member';

type
  TInaccessibleMemberRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnusedPrivateMemberRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterVisibilityRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.ConsideredUsed,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TVisibilityText = (InstanceField, InstanceProperty, InstanceMethod, NotVisible, NotInClassMethod, PrivateInAncestor,
    AccessTitle, PrivateField, PrivateConstant, PrivateMethod, RemoveName, NeverUsed, Title, PrivateProperty);

const
  cTexts: array[TVisibilityText] of TAtlasText = (
    (De: 'ein Instanzfeld'; En: 'an instance field'),
    (De: 'eine Instanz-Property'; En: 'an instance property'),
    (De: 'eine Instanzmethode'; En: 'an instance method'),
    (De: '%s.%s ist %s und hier nicht sichtbar (wie %s).'; En: '%s.%s is %s and not visible here (like %s).'),
    (De: '%s ist %s und in der Klassenmethode %s nicht erreichbar (wie E2124).';
     En: '%s is %s and not reachable in the class method %s (like E2124).'),
    (De: 'Die Property %s verweist auf %s.%s, das im Vorfahren private ist (wie W1045).';
     En: 'The property %s refers to %s.%s, which is private in the ancestor (like W1045).'),
    (De: 'Zugriff auf ein nicht sichtbares Mitglied'; En: 'Access to a member that is not visible'),
    (De: 'Privates Feld'; En: 'Private field'),
    (De: 'Private Konstante'; En: 'Private constant'),
    (De: 'Private Methode'; En: 'Private method'),
    (De: '%s entfernen'; En: 'Remove %s'),
    (De: '%s %s wird nie verwendet (wie H2219).'; En: '%s %s is never used (like H2219).'),
    (De: 'Privates Mitglied wird nie verwendet'; En: 'Private member is never used'),
    (De: 'Private Property'; En: 'Private property'));

{$SCOPEDENUMS OFF}

const
  Restricted = [TIndexVisibility.Private, TIndexVisibility.StrictPrivate, TIndexVisibility.Protected,
    TIndexVisibility.StrictProtected];

function VisibilityText(AVisibility: TIndexVisibility): string;
begin
  case AVisibility of
    TIndexVisibility.Private:
      Result := 'private';
    TIndexVisibility.StrictPrivate:
      Result := 'strict private';
    TIndexVisibility.Protected:
      Result := 'protected';
    TIndexVisibility.StrictProtected:
      Result := 'strict protected';
  else
    Result := 'public';
  end;
end;

/// <summary>Trägt ADirectives die Direktive ADirective?</summary>
function HasDirective(const ADirectives: TArray<string>; const ADirective: string): Boolean;
var
  Directive: string;
begin
  for Directive in ADirectives do
  begin
    if SameText(Directive, ADirective) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Dateiname des Laufs für die Namensauflösung: FileName, sonst RelativePath, sonst Unit.pas.</summary>
function RuleFileName(const AContext: TRuleContext): string;
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

/// <summary>Methode, in der ANode steht (äußerste Routine mit Punkt im Namen); nil außerhalb.</summary>
function EnclosingMethod(ANode: TSyntaxNode): TSyntaxNode;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  mNode := ANode.Parent;
  while mNode <> nil do
  begin
    if (mNode.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', mNode.Name) > 0) then
    begin
      Result := mNode;
    end;
    mNode := mNode.Parent;
  end;
end;

/// <summary>Steht ANode in generischem Code, also in einer Routine oder Methode mit Typparametern im Kopf
/// (TListe&lt;T&gt;.Zweiter, Sortiere&lt;T&gt;)?</summary>
function InGenericCode(ANode: TSyntaxNode): Boolean;
var
  mNode, mHeader: TSyntaxNode;
begin
  mNode := ANode.Parent;
  while mNode <> nil do
  begin
    if mNode.Kind = TSyntaxKind.RoutineDecl then
    begin
      mHeader := mNode.FindChild(TSyntaxKind.RoutineHeader);
      if (mHeader <> nil) and (mHeader.FindChild(TSyntaxKind.GenericParams) <> nil) then
      begin
        Exit(True);
      end;
    end;
    mNode := mNode.Parent;
  end;
  Result := False;
end;

/// <summary>Bereich des Mitgliedsnamens hinter dem Punkt in A.B.</summary>
function MemberRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.EndPos.Line, ANode.EndPos.Character - Length(ANode.Name), ANode.EndPos.Line,
    ANode.EndPos.Character);
end;

/// <summary>Wörter hinter read und write einer Property-Signatur (bei read FPunkt.X nur FPunkt).</summary>
function AccessorNames(const ASignature: string): TArray<string>;
var
  mWords: TArray<string>;
  mIndex: Integer;
  mName: string;
begin
  Result := nil;
  mWords := ASignature.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty);
  for mIndex := 0 to High(mWords) - 1 do
  begin
    if SameText(mWords[mIndex], 'read') or SameText(mWords[mIndex], 'write') then
    begin
      mName := mWords[mIndex + 1];
      if Pos('.', mName) > 0 then
      begin
        mName := Copy(mName, 1, Pos('.', mName) - 1);
      end;
      Result := Result + [mName];
    end;
  end;
end;

/// <summary>Sucht das Mitglied AName unter den Mitgliedern von AType.</summary>
function FindTypeMember(AAncestry: TAncestry; const AType: TSymbolLocation; const AName: string;
  out AMember: TIndexSymbol): Boolean;
var
  mMember: TIndexSymbol;
begin
  for mMember in AAncestry.Members(AType) do
  begin
    if SameText(mMember.Name, AName) then
    begin
      AMember := mMember;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Text der Art eines Instanzmitglieds für E2124.</summary>
function InstanceKindText(AKind: TIndexSymbolKind): string;
begin
  case AKind of
    TIndexSymbolKind.Field:
      Result := cTexts[TVisibilityText.InstanceField].Text;
    TIndexSymbolKind.Property_:
      Result := cTexts[TVisibilityText.InstanceProperty].Text;
  else
    Result := cTexts[TVisibilityText.InstanceMethod].Text;
  end;
end;

type
  /// <summary>Ein Lauf von inaccessible-member über eine Datei.</summary>
  TInaccessibleMemberCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FLocal: TUnitIndex;
    FTokens: TArray<TPascalToken>;
    FResolver: TNameResolver;
    FFileName: string;
    // Name -> gibt es ein nicht öffentliches Mitglied dieses Namens (Datei oder Index)?
    FSuspects: TDictionary<string, Boolean>;
    function Suspect(const AName: string): Boolean;
    function IndexHasRestricted(const AName: string): Boolean;
    function WiderScope(AMethod: TSyntaxNode): Boolean;
    function IsClassMethod(ANode: TSyntaxNode): Boolean;
    function TokenAt(AOffset: Integer): Integer;
    function HiddenMember(ANode: TSyntaxNode; out AReceiverType, AMember: TResolvedSymbol): Boolean;
    function NestedSomewhere(const AName: string): Boolean;
    function ReceiverTyped(ANode: TSyntaxNode; out AReceiverType: TResolvedSymbol): Boolean;
    function Tolerated(ANode: TSyntaxNode; const AReceiverType, AMember: TResolvedSymbol): Boolean;
    procedure CheckMemberAccess(ANode: TSyntaxNode);
    function HasClassOverload(ANode: TSyntaxNode): Boolean;
    function InstanceMember(ANode: TSyntaxNode; out ASymbol: TResolvedSymbol): Boolean;
    function Reachable(ANode: TSyntaxNode; const ASymbol: TResolvedSymbol): Boolean;
    procedure CheckInstanceMember(ANode, AMethod: TSyntaxNode);
    function VisitNode(ANode, AClassMethod: TSyntaxNode): TSyntaxNode;
    procedure Visit(ARoot: TSyntaxNode);
    function OwnProperty(AAncestry: TAncestry; const ASymbol: TIndexSymbol; out AOwner: TSymbolLocation): Boolean;
    function ReportPrivateAncestor(AAncestry: TAncestry; const ASymbol: TIndexSymbol; const AOwner: TSymbolLocation;
      const AName: string): Boolean;
    procedure CheckProperty(AAncestry: TAncestry; const ASymbol: TIndexSymbol; const AOwner: TSymbolLocation);
    procedure CheckPropertyAccessors;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

  /// <summary>Zu besuchende Knoten samt der Klassenmethode, in der sie stehen (nil außerhalb).</summary>
  TVisibilityPending = class
  private
    FNodes: TStack<TSyntaxNode>;
    FMethods: TStack<TSyntaxNode>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Push(ANode, AClassMethod: TSyntaxNode);
    function Pop(out AClassMethod: TSyntaxNode): TSyntaxNode;
    function Empty: Boolean;
    procedure PushChildren(ANode, AClassMethod: TSyntaxNode);
  end;

{ TVisibilityPending }

constructor TVisibilityPending.Create;
begin
  inherited Create;
  FNodes := TStack<TSyntaxNode>.Create;
  FMethods := TStack<TSyntaxNode>.Create;
end;

destructor TVisibilityPending.Destroy;
begin
  FMethods.Free;
  FNodes.Free;
  inherited Destroy;
end;

procedure TVisibilityPending.Push(ANode, AClassMethod: TSyntaxNode);
begin
  FNodes.Push(ANode);
  FMethods.Push(AClassMethod);
end;

function TVisibilityPending.Pop(out AClassMethod: TSyntaxNode): TSyntaxNode;
begin
  Result := FNodes.Pop;
  AClassMethod := FMethods.Pop;
end;

function TVisibilityPending.Empty: Boolean;
begin
  Result := FNodes.Count = 0;
end;

procedure TVisibilityPending.PushChildren(ANode, AClassMethod: TSyntaxNode);
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  for mIndex := ANode.ChildCount - 1 downto 0 do
  begin
    mChild := ANode[mIndex];
    // Kopf der Klassenmethode (Parameter, Ergebnistyp) ist kein Zugriff.
    if (ANode.Kind <> TSyntaxKind.RoutineDecl) or (AClassMethod = nil) or
      (mChild.Kind in [TSyntaxKind.Block, TSyntaxKind.RoutineDecl]) then
    begin
      Push(mChild, AClassMethod);
    end
    else if mChild.Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection] then
    begin
      Push(mChild, nil);
    end;
  end;
end;

{ TInaccessibleMemberCheck }

constructor TInaccessibleMemberCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FSuspects := TDictionary<string, Boolean>.Create;
end;

destructor TInaccessibleMemberCheck.Destroy;
begin
  FSuspects.Free;
  inherited Destroy;
end;

function TInaccessibleMemberCheck.IndexHasRestricted(const AName: string): Boolean;
begin
  Result := (FContext.Index <> nil) and FContext.Index.HasSymbol(AName,
    function(const ASymbol: TIndexSymbol): Boolean
    begin
      Result := (ASymbol.Container <> '') and (ASymbol.Visibility in Restricted);
    end);
end;

function TInaccessibleMemberCheck.Suspect(const AName: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  if FSuspects.TryGetValue(LowerCase(AName), Result) then
  begin
    Exit;
  end;
  Result := False;
  for mSymbol in FLocal.Symbols do
  begin
    if (mSymbol.Container <> '') and (mSymbol.Visibility in Restricted) and SameText(mSymbol.Name, AName) then
    begin
      Result := True;
    end;
  end;
  if not Result then
  begin
    Result := IndexHasRestricted(AName);
  end;
  FSuspects.Add(LowerCase(AName), Result);
end;

/// <summary>Darf die Methode AMethod mehr sehen als die Regel prüft? Methoden von Helfern (protected
/// des erweiterten Typs) und verschachtelten Typen (Mitglieder des äußeren Typs).</summary>
function TInaccessibleMemberCheck.WiderScope(AMethod: TSyntaxNode): Boolean;
var
  mTypeName: string;
  mSymbol: TIndexSymbol;
begin
  if AMethod = nil then
  begin
    Exit(False);
  end;
  mTypeName := Copy(AMethod.Name, 1, LastDelimiter('.', AMethod.Name) - 1);
  Result := Pos('.', mTypeName) > 0;
  for mSymbol in FLocal.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.HelperType) and SameText(mSymbol.Name, mTypeName) then
    begin
      Result := True;
    end;
  end;
end;

/// <summary>Erstes Token, das nicht vor AOffset beginnt (binäre Suche).</summary>
function TInaccessibleMemberCheck.TokenAt(AOffset: Integer): Integer;
var
  mHigh, mMiddle: Integer;
begin
  Result := 0;
  mHigh := High(FTokens);
  while Result < mHigh do
  begin
    mMiddle := (Result + mHigh) div 2;
    if FTokens[mMiddle].Offset < AOffset then
    begin
      Result := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
end;

/// <summary>Beginnt die Routine ANode mit "class" (class function/procedure)?</summary>
function TInaccessibleMemberCheck.IsClassMethod(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TokenAt(ANode.StartOffset);
  Result := (mIndex < High(FTokens)) and (FTokens[mIndex].Offset = ANode.StartOffset) and
    FTokens[mIndex].IsKeyword('class');
  Result := Result and (FTokens[mIndex + 1].IsKeyword('function') or FTokens[mIndex + 1].IsKeyword('procedure'));
end;

/// <summary>Ist der Empfänger ANode sicher bekannt und hat einen Typ, der keine Unit und nicht eingebaut ist?
/// </summary>
function TInaccessibleMemberCheck.NestedSomewhere(const AName: string): Boolean;
const
  Kinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType];
var
  mLocation: TSymbolLocation;
begin
  Result := False;
  if FContext.Index = nil then
  begin
    Exit;
  end;
  for mLocation in FContext.Index.FindSymbols(AName) do
  begin
    if (mLocation.Symbol.Container <> '') and (mLocation.Symbol.Kind in Kinds) then
    begin
      Exit(True);
    end;
  end;
end;

function TInaccessibleMemberCheck.ReceiverTyped(ANode: TSyntaxNode; out AReceiverType: TResolvedSymbol): Boolean;
var
  mReceiver: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  Result := FResolver.NodeType(FContext.Tree, FFileName, ANode, mReceiver, AReceiverType, mTypeFound) and
    mTypeFound;
  Result := Result and (mReceiver.Kind <> TResolvedKind.UnitName) and not AReceiverType.Builtin;
  // var APanel: TPanel mit geschachteltem record TPanel: Der Auflöser fände sonst Vcl.ExtCtrls.TPanel.
  Result := Result and not NestedSomewhere(AReceiverType.Name);
end;

/// <summary>Ist ANode ein Zugriff A.B, dessen Mitglied B die Auflösung mit Sichtbarkeit nicht findet, ohne sie
/// aber als nicht öffentliches Mitglied ohne Bedingung kennt?</summary>
function TInaccessibleMemberCheck.HiddenMember(ANode: TSyntaxNode; out AReceiverType,
  AMember: TResolvedSymbol): Boolean;
var
  mSymbol, mTypeInfo: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  Result := (ANode.ChildCount = 1) and (ANode.Name <> '') and (ANode.EndPos.Line = ANode[0].EndPos.Line) and
    Suspect(ANode.Name);
  Result := Result and not FResolver.NodeType(FContext.Tree, FFileName, ANode, mSymbol, mTypeInfo, mTypeFound) and
    ReceiverTyped(ANode[0], AReceiverType);
  // Sichtbar über Helfer oder Vorfahren: kein Fall für diese Regel.
  Result := Result and not FResolver.FindMember(AReceiverType, ANode.Name, AMember) and
    FResolver.DeclaredMember(AReceiverType, ANode.Name, AMember);
  Result := Result and (AMember.Visibility in Restricted) and (AMember.Condition = '');
end;

/// <summary>Fälle, die dcc trotz unsichtbarem Mitglied übersetzt oder die die Regel nicht sicher beurteilt.
/// </summary>
function TInaccessibleMemberCheck.Tolerated(ANode: TSyntaxNode; const AReceiverType,
  AMember: TResolvedSymbol): Boolean;
begin
  // class constructor Create verdeckt den geerbten Konstruktor nicht (Spring4D, IM4).
  Result := (AMember.SymbolKind = TIndexSymbolKind.Constructor_) and HasDirective(AMember.Directives, 'class');
  Result := Result or ((AMember.Visibility <> TIndexVisibility.Private) and WiderScope(EnclosingMethod(ANode)));
  // protected über einen generischen Empfänger (TKnoten<T>, TBaum<T>) übersetzt dcc aus generischem Code
  // einer anderen Unit (Spring4D TLinkedListNode<T>, TRedBlackTree<T>; IM1, IM2); aus nicht generischem Code
  // meldet es E2362 (SG3, dcc-Lauf vom 29.10.2026, #1328).
  Result := Result or ((AMember.Visibility = TIndexVisibility.Protected) and (AReceiverType.TypeParams <> '') and
    InGenericCode(ANode));
end;

procedure TInaccessibleMemberCheck.CheckMemberAccess(ANode: TSyntaxNode);
var
  mReceiverType, mMember: TResolvedSymbol;
  mCode: string;
begin
  if not HiddenMember(ANode, mReceiverType, mMember) or Tolerated(ANode, mReceiverType, mMember) then
  begin
    Exit;
  end;
  mCode := 'E2361';
  if mMember.Visibility in [TIndexVisibility.Protected, TIndexVisibility.StrictProtected] then
  begin
    mCode := 'E2362';
  end;
  FReport.Add(MemberRange(ANode), cTexts[TVisibilityText.NotVisible].Fmt([mMember.Container,
    mMember.Name, VisibilityText(mMember.Visibility), mCode]), TRuleConfidence.High);
end;

/// <summary>Hat der Aufruf ANode eine Überladung, die eine Klassenmethode ist (DMVC, JCL, IM5)?</summary>
function TInaccessibleMemberCheck.HasClassOverload(ANode: TSyntaxNode): Boolean;
var
  mCandidate: TResolvedSymbol;
begin
  for mCandidate in FResolver.CallCandidates(FContext.Tree, FFileName, ANode) do
  begin
    if HasDirective(mCandidate.Directives, 'class') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Löst ANode sicher zu einem Feld, einer Property oder Methode einer Instanz ohne Bedingung auf?
/// </summary>
function TInaccessibleMemberCheck.InstanceMember(ANode: TSyntaxNode; out ASymbol: TResolvedSymbol): Boolean;
var
  mTypeInfo: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  Result := FResolver.NodeType(FContext.Tree, FFileName, ANode, ASymbol, mTypeInfo, mTypeFound) and
    (ASymbol.Kind = TResolvedKind.Symbol) and (ASymbol.Container <> '');
  Result := Result and (ASymbol.SymbolKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_,
    TIndexSymbolKind.Method]);
  Result := Result and not HasDirective(ASymbol.Directives, 'class') and (ASymbol.Condition = '');
end;

/// <summary>Ist das Instanzmitglied in der Klassenmethode doch erreichbar (with, Überladung als Klassenmethode)?
/// </summary>
function TInaccessibleMemberCheck.Reachable(ANode: TSyntaxNode; const ASymbol: TResolvedSymbol): Boolean;
var
  mWith: TResolvedWithMember;
begin
  // Mitglied eines with-Ausdrucks (with Result do Pfad := …) ist erreichbar.
  Result := FResolver.Queries.WithMember(FContext.Tree, FFileName, ANode.Name, ANode.StartOffset, mWith) or
    mWith.Unknown;
  Result := Result or ((ASymbol.SymbolKind = TIndexSymbolKind.Method) and HasClassOverload(ANode));
end;

procedure TInaccessibleMemberCheck.CheckInstanceMember(ANode, AMethod: TSyntaxNode);
var
  mSymbol: TResolvedSymbol;
  mMethodName: string;
begin
  if not InstanceMember(ANode, mSymbol) or Reachable(ANode, mSymbol) then
  begin
    Exit;
  end;
  mMethodName := Copy(AMethod.Name, LastDelimiter('.', AMethod.Name) + 1, MaxInt);
  FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
    cTexts[TVisibilityText.NotInClassMethod].Fmt([mSymbol.Name, InstanceKindText(mSymbol.SymbolKind), mMethodName]),
    TRuleConfidence.High);
end;

/// <summary>Prüft ANode und liefert die Klassenmethode für seine Kinder.</summary>
function TInaccessibleMemberCheck.VisitNode(ANode, AClassMethod: TSyntaxNode): TSyntaxNode;
begin
  Result := AClassMethod;
  case ANode.Kind of
    TSyntaxKind.RoutineDecl:
      if (Pos('.', ANode.Name) > 0) and IsClassMethod(ANode) then
      begin
        Result := ANode;
      end;
    TSyntaxKind.MemberAccess:
      CheckMemberAccess(ANode);
    TSyntaxKind.Identifier:
      if (AClassMethod <> nil) and (ANode.Name <> '') then
      begin
        CheckInstanceMember(ANode, AClassMethod);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

// Iterativ (Bericht M1).
procedure TInaccessibleMemberCheck.Visit(ARoot: TSyntaxNode);
var
  mPending: TVisibilityPending;
  mNode, mClassMethod: TSyntaxNode;
begin
  mPending := TVisibilityPending.Create;
  try
    mPending.Push(ARoot, nil);
    while not mPending.Empty do
    begin
      mNode := mPending.Pop(mClassMethod);
      if mNode.Kind <> TSyntaxKind.InheritedExpr then
      begin
        mClassMethod := VisitNode(mNode, mClassMethod);
        mPending.PushChildren(mNode, mClassMethod);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Ist ASymbol eine Property ohne Bedingung einer Klasse dieser Datei (AOwner)?</summary>
function TInaccessibleMemberCheck.OwnProperty(AAncestry: TAncestry; const ASymbol: TIndexSymbol;
  out AOwner: TSymbolLocation): Boolean;
begin
  Result := (ASymbol.Kind = TIndexSymbolKind.Property_) and (ASymbol.Container <> '') and not ASymbol.Unavailable;
  Result := Result and (ASymbol.Condition = '') and AAncestry.FindClass(ASymbol.Container, AOwner) and
    (AOwner.FileName = '');
end;

/// <summary>Meldet W1045, wenn der nächste Vorfahr mit dem Mitglied AName es private in derselben Unit
/// deklariert.</summary>
function TInaccessibleMemberCheck.ReportPrivateAncestor(AAncestry: TAncestry; const ASymbol: TIndexSymbol;
  const AOwner: TSymbolLocation; const AName: string): Boolean;
var
  mChain: TArray<TSymbolLocation>;
  mComplete, mObjectMissing: Boolean;
  mLevel: Integer;
  mMember: TIndexSymbol;
begin
  Result := False;
  mChain := AAncestry.Ancestors(AOwner.Symbol.Name, mComplete, mObjectMissing);
  for mLevel := 0 to High(mChain) do
  begin
    if FindTypeMember(AAncestry, mChain[mLevel], AName, mMember) then
    begin
      Result := (mMember.Visibility = TIndexVisibility.Private) and (mChain[mLevel].FileName = '') and
        not mMember.Unavailable and (mMember.Condition = '');
      if Result then
      begin
        FReport.AddWithSeverity(ASymbol.SelectionRange, cTexts[TVisibilityText.PrivateInAncestor].Fmt([ASymbol.Name,
          mChain[mLevel].Symbol.Name, mMember.Name]),
          TRuleSeverity.Warning, nil);
      end;
      Exit;
    end;
  end;
end;

procedure TInaccessibleMemberCheck.CheckProperty(AAncestry: TAncestry; const ASymbol: TIndexSymbol;
  const AOwner: TSymbolLocation);
var
  mReported: TArray<string>;
  mName: string;
  mMember: TIndexSymbol;
begin
  mReported := nil;
  for mName in AccessorNames(ASymbol.Signature) do
  begin
    // Im eigenen Typ deklariert: kein Fall für W1045.
    if (IndexText(mName, mReported) < 0) and not FindTypeMember(AAncestry, AOwner, mName, mMember) and
      ReportPrivateAncestor(AAncestry, ASymbol, AOwner, mName) then
    begin
      mReported := mReported + [mName];
    end;
  end;
end;

/// <summary>W1045: Property einer Klasse der Datei verweist auf ein private-Mitglied eines Vorfahren, der in
/// derselben Unit steht.</summary>
procedure TInaccessibleMemberCheck.CheckPropertyAccessors;
var
  mAncestry: TAncestry;
  mSymbol: TIndexSymbol;
  mOwner: TSymbolLocation;
begin
  mAncestry := TAncestry.Create(FContext.Index, FLocal);
  try
    for mSymbol in FLocal.Symbols do
    begin
      if OwnProperty(mAncestry, mSymbol, mOwner) then
      begin
        CheckProperty(mAncestry, mSymbol, mOwner);
      end;
    end;
  finally
    mAncestry.Free;
  end;
end;

procedure TInaccessibleMemberCheck.Run;
begin
  FCache := TRuleDerived.Open(FContext);
  FLocal := TRuleDerived.UnitIndex(FCache, FContext);
  FTokens := TRuleDerived.CodeTokens(FCache, FContext);
  FFileName := RuleFileName(FContext);
  CheckPropertyAccessors;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  FResolver := TRuleDerived.Resolver(FCache, FContext);
  FResolver.PinTree(FContext.Tree, FFileName);
  try
    Visit(FContext.Tree.Root);
  finally
    FResolver.UnpinTree;
  end;
end;

{ TInaccessibleMemberRule }

function TInaccessibleMemberRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(InaccessibleMemberRuleId, TRuleSeverity.Error,
    cTexts[TVisibilityText.AccessTitle].Text);
end;

procedure TInaccessibleMemberRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TInaccessibleMemberCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mCheck := TInaccessibleMemberCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

{ Hilfen für unused-private-member }

function SamePosition(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line = B.Line) and (A.Character = B.Character);
end;

/// <summary>Bindet die Datei Include-Dateien ein ({$I}, {$INCLUDE})?</summary>
function HasIncludes(const AContext: TRuleContext): Boolean;
var
  mToken: TPascalToken;
  mName: string;
begin
  for mToken in AContext.Tree.Tokens do
  begin
    if mToken.Kind = TPascalTokenKind.Directive then
    begin
      mName := TDirectiveNames.LeadingName(TDirectiveNames.Body(mToken.Text));
      if SameText(mName, 'I') or SameText(mName, 'INCLUDE') then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Ist der Name des ersten Vorfahren (ohne Unit und Typparameter) ein Interface-Name I…?</summary>
function InterfaceLikeName(const AAncestor: string): Boolean;
var
  mShort: string;
  mPosition: Integer;
begin
  mShort := Copy(AAncestor, LastDelimiter('.', AAncestor) + 1, MaxInt);
  mPosition := Pos('<', mShort);
  if mPosition > 0 then
  begin
    mShort := Copy(mShort, 1, mPosition - 1);
  end;
  Result := (Length(mShort) > 1) and (mShort[1] = 'I') and CharInSet(mShort[2], ['A'..'Z']);
end;

function PrivateKindText(const ASymbol: TIndexSymbol): string;
begin
  case ASymbol.Kind of
    TIndexSymbolKind.Field:
      Result := cTexts[TVisibilityText.PrivateField].Text;
    TIndexSymbolKind.Constant:
      Result := cTexts[TVisibilityText.PrivateConstant].Text;
    TIndexSymbolKind.Property_:
      Result := cTexts[TVisibilityText.PrivateProperty].Text;
  else
    Result := cTexts[TVisibilityText.PrivateMethod].Text;
  end;
end;

/// <summary>Trägt APosition unter AName in ADictionary (Name -> Positionen) ein.</summary>
procedure NotePosition(ADictionary: TDictionary<string, TList<TTextPosition>>; const AName: string;
  const APosition: TTextPosition);
var
  mList: TList<TTextPosition>;
begin
  if not ADictionary.TryGetValue(LowerCase(AName), mList) then
  begin
    mList := TList<TTextPosition>.Create;
    ADictionary.Add(LowerCase(AName), mList);
  end;
  mList.Add(APosition);
end;

/// <summary>Gibt die Listen in ADictionary frei (das Wörterbuch selbst nicht).</summary>
procedure FreePositionLists(ADictionary: TDictionary<string, TList<TTextPosition>>);
var
  mList: TList<TTextPosition>;
begin
  for mList in ADictionary.Values do
  begin
    mList.Free;
  end;
end;

/// <summary>Kommt APosition in AList vor?</summary>
function ContainsPosition(AList: TList<TTextPosition>; const APosition: TTextPosition): Boolean;
var
  mOther: TTextPosition;
begin
  for mOther in AList do
  begin
    if SamePosition(mOther, APosition) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

const
  cMemberKinds = [TIndexSymbolKind.Field, TIndexSymbolKind.Method, TIndexSymbolKind.Constant,
    TIndexSymbolKind.Property_];

type
  /// <summary>Ein Lauf von unused-private-member über eine Datei.</summary>
  TUnusedPrivateMemberCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FLocal: TUnitIndex;
    FLines: TArray<string>;
    FIncludeFields: Boolean;
    // Name -> Positionen aller Bezeichner dieses Namens
    FOccurrences: TDictionary<string, TList<TTextPosition>>;
    // Name -> Positionen, die keine Verwendung sind (Deklarationen, Methodenköpfe)
    FDeclared: TDictionary<string, TList<TTextPosition>>;
    // Dienst „gilt als verwendet“, geteilt mit unused-public-member (#1102).
    FConsidered: TConsideredUsed;
    function Used(const AName: string): Boolean;
    function HasInterfaces(const AName: string): Boolean;
    function DeleteLines(AFirst, ALast: Integer): TTextEdit;
    function Body(const ASymbol: TIndexSymbol; out AMany: Boolean): TSyntaxNode;
    function StandsAlone(const ASymbol: TIndexSymbol): Boolean;
    function SharesLines(const ASymbol: TIndexSymbol): Boolean;
    function AddBodyEdit(const ASymbol: TIndexSymbol; var AEdits: TArray<TTextEdit>): Boolean;
    function RemoveFix(const ASymbol: TIndexSymbol): TArray<TRuleFix>;
    function Candidate(const ASymbol: TIndexSymbol): Boolean;
    function Excused(const ASymbol: TIndexSymbol): Boolean;
    procedure CheckMember(const ASymbol: TIndexSymbol);
    procedure CollectNames(const ATokens: TArray<TPascalToken>);
    procedure CheckMembers;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

{ TUnusedPrivateMemberCheck }

constructor TUnusedPrivateMemberCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FOccurrences := TDictionary<string, TList<TTextPosition>>.Create;
  FDeclared := TDictionary<string, TList<TTextPosition>>.Create;
end;

destructor TUnusedPrivateMemberCheck.Destroy;
begin
  FreePositionLists(FOccurrences);
  FreePositionLists(FDeclared);
  FOccurrences.Free;
  FDeclared.Free;
  FConsidered.Free;
  inherited Destroy;
end;

function TUnusedPrivateMemberCheck.Used(const AName: string): Boolean;
var
  mPositions, mSkip: TList<TTextPosition>;
  mPosition: TTextPosition;
begin
  if not FOccurrences.TryGetValue(LowerCase(AName), mPositions) then
  begin
    Exit(False);
  end;
  if not FDeclared.TryGetValue(LowerCase(AName), mSkip) then
  begin
    Exit(True);
  end;
  for mPosition in mPositions do
  begin
    if not ContainsPosition(mSkip, mPosition) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Kann der Typ AName Interfaces umsetzen (mehr als ein Vorfahr oder ein Vorfahr I…)? Unbekannte
/// Typen gelten als ja.</summary>
function TUnusedPrivateMemberCheck.HasInterfaces(const AName: string): Boolean;
var
  mOwner: TIndexSymbol;
begin
  for mOwner in FLocal.Symbols do
  begin
    if (mOwner.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType]) and
      SameText(mOwner.QualifiedName, AName) then
    begin
      Result := (Length(mOwner.Ancestors) > 1) or
        ((mOwner.Ancestors <> nil) and InterfaceLikeName(mOwner.Ancestors[0]));
      Exit;
    end;
  end;
  Result := True;
end;

/// <summary>Entfernt die Zeilen AFirst..ALast samt ///-Doku darüber.</summary>
function TUnusedPrivateMemberCheck.DeleteLines(AFirst, ALast: Integer): TTextEdit;
begin
  while (AFirst > 0) and StartsStr('///', TrimLeft(FLines[AFirst - 1])) do
  begin
    Dec(AFirst);
  end;
  Result := TTextEdit.Create(TTextRange.Create(AFirst, 0, ALast + 1, 0), '');
end;

/// <summary>Rumpf der Methode ASymbol (Routine TFoo.Name nach der Deklaration); nil ohne oder bei mehreren.
/// </summary>
function TUnusedPrivateMemberCheck.Body(const ASymbol: TIndexSymbol; out AMany: Boolean): TSyntaxNode;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  AMany := False;
  for mNode in TRuleDerived.Routines(FCache, FContext) do
  begin
    if SameText(mNode.Name, ASymbol.Container + '.' + ASymbol.Name) and
      (mNode.StartPos.Line > ASymbol.Range.EndPos.Line) then
    begin
      AMany := AMany or (Result <> nil);
      Result := mNode;
    end;
  end;
end;

/// <summary>Hat die Deklaration ihre Zeilen für sich (nichts davor in der ersten, nichts danach in der letzten)?
/// </summary>
function TUnusedPrivateMemberCheck.StandsAlone(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Range.EndPos.Line < Length(FLines)) and
    (Trim(Copy(FLines[ASymbol.Range.StartPos.Line], 1, ASymbol.Range.StartPos.Character)) = '') and
    (Trim(Copy(FLines[ASymbol.Range.EndPos.Line], ASymbol.Range.EndPos.Character + 1, MaxInt)) = '');
end;

/// <summary>Stehen weitere Deklarationen in denselben Zeilen (FA, FB: Integer)?</summary>
function TUnusedPrivateMemberCheck.SharesLines(const ASymbol: TIndexSymbol): Boolean;
var
  mOther: TIndexSymbol;
begin
  for mOther in FLocal.Symbols do
  begin
    if (mOther.Container <> '') and not SamePosition(mOther.SelectionRange.StartPos,
      ASymbol.SelectionRange.StartPos) and (mOther.SelectionRange.StartPos.Line >= ASymbol.Range.StartPos.Line) and
      (mOther.SelectionRange.StartPos.Line <= ASymbol.Range.EndPos.Line) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Hängt für eine Methode das Entfernen ihres einen Rumpfs an; False, wenn sie überladen ist oder
/// mehrere Rümpfe hat.</summary>
function TUnusedPrivateMemberCheck.AddBodyEdit(const ASymbol: TIndexSymbol; var AEdits: TArray<TTextEdit>): Boolean;
var
  mNode: TSyntaxNode;
  mMany: Boolean;
  mLast: Integer;
begin
  mNode := Body(ASymbol, mMany);
  Result := not mMany and not HasDirective(ASymbol.Directives, 'overload');
  if Result and (mNode <> nil) then
  begin
    mLast := mNode.EndPos.Line;
    // Eine Leerzeile danach mit entfernen.
    if (mLast + 1 < Length(FLines)) and (Trim(FLines[mLast + 1]) = '') then
    begin
      Inc(mLast);
    end;
    AEdits := AEdits + [DeleteLines(mNode.StartPos.Line, mLast)];
  end;
end;

/// <summary>"Name entfernen": nur, wenn die Deklaration ihre Zeilen allein hat; bei Methoden mit dem einen
/// Rumpf.</summary>
function TUnusedPrivateMemberCheck.RemoveFix(const ASymbol: TIndexSymbol): TArray<TRuleFix>;
var
  mEdits: TArray<TTextEdit>;
begin
  Result := nil;
  if not StandsAlone(ASymbol) or SharesLines(ASymbol) then
  begin
    Exit;
  end;
  mEdits := [DeleteLines(ASymbol.Range.StartPos.Line, ASymbol.Range.EndPos.Line)];
  if (ASymbol.Kind = TIndexSymbolKind.Method) and not AddBodyEdit(ASymbol, mEdits) then
  begin
    Exit;
  end;
  Result := [TRuleFix.Create(cTexts[TVisibilityText.RemoveName].Fmt([ASymbol.Name]), mEdits)];
end;

/// <summary>Ist ASymbol ein privates Mitglied (Felder nur mit includeFields), das nie vorkommt?</summary>
function TUnusedPrivateMemberCheck.Candidate(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Visibility in [TIndexVisibility.Private, TIndexVisibility.StrictPrivate]) and
    ((ASymbol.Kind <> TIndexSymbolKind.Field) or FIncludeFields);
  Result := Result and not ASymbol.Unavailable and not Used(ASymbol.Name);
end;

/// <summary>Gilt das ungenutzte Mitglied trotzdem als verwendet?</summary>
function TUnusedPrivateMemberCheck.Excused(const ASymbol: TIndexSymbol): Boolean;
var
  mReason: TConsideredUsedReason;
begin
  mReason := FConsidered.Reason(ASymbol);
  Result := (mReason <> TConsideredUsedReason.None) and (mReason <> TConsideredUsedReason.UnknownAncestor);
  // Kette unbekannt (Vorfahr nicht im Index): Methoden von Typen mit Interfaces können sie umsetzen.
  Result := Result or ((mReason = TConsideredUsedReason.UnknownAncestor) and
    (ASymbol.Kind = TIndexSymbolKind.Method) and HasInterfaces(ASymbol.Container));
  // Komponenten und Ereignisse aus der Formulardatei.
  Result := Result or ((FContext.FormText <> '') and ContainsText(FContext.FormText, ASymbol.Name));
end;

procedure TUnusedPrivateMemberCheck.CheckMember(const ASymbol: TIndexSymbol);
begin
  if Candidate(ASymbol) and not Excused(ASymbol) then
  begin
    FReport.Add(ASymbol.SelectionRange, cTexts[TVisibilityText.NeverUsed].Fmt([PrivateKindText(ASymbol),
      ASymbol.Name]), TRuleConfidence.High, RemoveFix(ASymbol));
  end;
end;

/// <summary>Merkt alle Bezeichner und die Stellen, die keine Verwendung sind.</summary>
procedure TUnusedPrivateMemberCheck.CollectNames(const ATokens: TArray<TPascalToken>);
var
  mToken: TPascalToken;
  mSymbol: TIndexSymbol;
  mName: string;
begin
  for mToken in ATokens do
  begin
    if mToken.Kind = TPascalTokenKind.Identifier then
    begin
      mName := mToken.Text;
      if StartsStr('&', mName) then
      begin
        mName := Copy(mName, 2, MaxInt);
      end;
      NotePosition(FOccurrences, mName, mToken.StartPos);
    end;
  end;
  // Deklarationen von Mitgliedern und Methodenköpfe (TFoo.Name) sind keine Verwendung.
  for mSymbol in FLocal.Symbols do
  begin
    if (mSymbol.Container <> '') and (mSymbol.Kind in cMemberKinds + [TIndexSymbolKind.Constructor_]) then
    begin
      NotePosition(FDeclared, mSymbol.Name, mSymbol.SelectionRange.StartPos);
    end;
  end;
end;

/// <summary>Prüft je Mitglied nur die Deklaration im Typ (sie steht vor dem Rumpf).</summary>
procedure TUnusedPrivateMemberCheck.CheckMembers;
var
  mSeen: TDictionary<string, Boolean>;
  mSymbol: TIndexSymbol;
  mKey: string;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mSymbol in FLocal.Symbols do
    begin
      mKey := LowerCase(mSymbol.Container + '.' + mSymbol.Name);
      if (mSymbol.Container <> '') and (mSymbol.Kind in cMemberKinds) and not mSeen.ContainsKey(mKey) then
      begin
        mSeen.Add(mKey, True);
        CheckMember(mSymbol);
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

procedure TUnusedPrivateMemberCheck.Run;
var
  mTokens: TArray<TPascalToken>;
begin
  FCache := TRuleDerived.Open(FContext);
  FLocal := TRuleDerived.UnitIndex(FCache, FContext);
  mTokens := TRuleDerived.CodeTokens(FCache, FContext);
  FLines := TTextLines.SplitLines(FContext.Text);
  FIncludeFields := TRuleOptions.Bool(FContext.Options, 'includeFields', True);
  // deadCode.keepAttributes und deadCode.keepPatterns (#64).
  FConsidered := TConsideredUsed.Create(FContext.Index, FLocal, mTokens, FContext.KeepAttributes,
    FContext.KeepPatterns);
  CollectNames(mTokens);
  CheckMembers;
end;

{ TUnusedPrivateMemberRule }

function TUnusedPrivateMemberRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UnusedPrivateMemberRuleId, TRuleSeverity.Hint,
    cTexts[TVisibilityText.Title].Text);
end;

procedure TUnusedPrivateMemberRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TUnusedPrivateMemberCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or HasIncludes(AContext) then
  begin
    Exit;
  end;
  mCheck := TUnusedPrivateMemberCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

procedure RegisterVisibilityRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TInaccessibleMemberRule.Create);
  ARegistry.Register(TUnusedPrivateMemberRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Visibility', cTexts);

end.
