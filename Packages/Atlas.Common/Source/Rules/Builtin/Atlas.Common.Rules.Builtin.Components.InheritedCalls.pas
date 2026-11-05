unit Atlas.Common.Rules.Builtin.Components.InheritedCalls;

// Prüfregeln zu inherited-Aufrufen für alle Klassen (Teil von Atlas.Common.Rules.Builtin.Components, dort
// registriert): missing-inherited, message-handler-without-inherited, inherited-order, inherited-wrong-method.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract;

type
  TMissingInheritedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorgabe der Option methods.</summary>
    class function DefaultMethods: TArray<string>; static;
  end;

  TMessageHandlerWithoutInheritedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorgabe der Option swallow: WM_ERASEBKGND.</summary>
    class function DefaultSwallow: TArray<string>; static;
    /// <summary>Folge für die Meldung: was ohne inherited bei der Nachricht AMessage wegfällt.</summary>
    class function Consequence(const AMessage: string): string; static;
  end;

  TInheritedOrderRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInheritedWrongMethodRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Erlaubt die Option allowed (Paare "Methode&gt;geerbte Methode", Muster mit * und ?) den Aufruf
    /// inherited AInherited in AMethod?</summary>
    class function Allowed(const APairs: TArray<string>; const AMethod, AInherited: string): Boolean; static;
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
  Atlas.Common.Rules.Builtin.Components.Model,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TComponentsInheritedCallsText = (CtorTitle, NeverFreed, NeverCreated, AfterConstruction, Insert, MessageTitle,
    DefaultHandling, NoInherited, InsertAtStart, OrderTitle, MoveToEnd, MoveToStart, BeforeFree, BeforeInherited,
    OtherTitle, CallInherited, OtherMethod, Consequence0, Consequence1, Consequence2, Consequence3, Consequence4,
    Consequence5, Consequence6, Consequence7, Consequence8);

const
  cTexts: array[TComponentsInheritedCallsText] of TAtlasText = (
    (De: 'Konstruktor oder Destruktor ohne inherited'; En: 'Constructor or destructor without inherited'),
    (De: '%s ruft inherited nicht auf; die Felder von %s werden nie freigegeben.';
     En: '%s does not call inherited; the fields of %s are never freed.'),
    (De: '%s ruft inherited nicht auf; die Felder von %s werden nie angelegt.';
     En: '%s does not call inherited; the fields of %s are never created.'),
    (De: '%s ruft inherited nicht auf; die Arbeit von %s nach dem Erzeugen entfällt.';
     En: '%s does not call inherited; the work of %s after construction is skipped.'),
    (De: '"%s" einfügen'; En: 'Insert "%s"'),
    (De: 'Message-Handler ohne inherited'; En: 'Message handler without inherited'),
    (De: 'die Standardbehandlung von Windows bzw. der VCL entfällt';
     En: 'the default handling of Windows or the VCL is skipped'),
    (De: '%s ruft inherited nicht auf; %s.'; En: '%s does not call inherited; %s.'),
    (De: '"inherited;" am Anfang einfügen'; En: 'Insert "inherited;" at the start'),
    (De: 'inherited an der falschen Stelle'; En: 'inherited in the wrong place'),
    (De: 'inherited an das Ende des Destruktors verschieben'; En: 'Move inherited to the end of the destructor'),
    (De: 'inherited an den Anfang des Konstruktors verschieben'; En: 'Move inherited to the start of the constructor'),
    (De: 'inherited vor dem Freigeben der eigenen Felder; der Vorfahr kann noch auf %s zugreifen.';
     En: 'inherited before freeing the own fields; the ancestor can still access %s.'),
    (De: '%s greift vor inherited auf %s aus %s zu; der Vorfahr ist noch nicht angelegt.';
     En: '%s accesses %s from %s before inherited; the ancestor is not created yet.'),
    (De: 'inherited ruft eine andere Methode'; En: 'inherited calls a different method'),
    (De: 'inherited %s aufrufen'; En: 'Call inherited %s'),
    (De: '%s ruft inherited %s auf; gemeint ist vermutlich inherited %s.';
     En: '%s calls inherited %s; probably inherited %s is meant.'),
    (De: 'die VCL passt Ausrichtung und Anker nicht mehr an'; En: 'the VCL no longer adjusts alignment and anchors'),
    (De: 'das Fenster schließt nicht mehr'; En: 'the window no longer closes'),
    (De: 'die VCL zeichnet das Steuerelement nicht mehr'; En: 'the VCL no longer paints the control'),
    (De: 'Tastatureingaben erreichen die Standardbehandlung nicht mehr';
     En: 'keyboard input no longer reaches the default handling'),
    (De: 'die Fokusbehandlung der VCL entfällt'; En: 'the focus handling of the VCL is skipped'),
    (De: 'Mausereignisse wie OnClick und OnMouseDown entfallen';
     En: 'mouse events such as OnClick and OnMouseDown are lost'),
    (De: 'die VCL räumt das Fenster nicht mehr auf'; En: 'the VCL no longer cleans up the window'),
    (De: 'Schrift und Skalierung passen sich nicht mehr an'; En: 'font and scaling no longer adapt'),
    (De: 'die Standardbehandlung der VCL entfällt'; En: 'the default handling of the VCL is skipped'));

{$SCOPEDENUMS OFF}

{ TMissingInheritedRule }

function TMissingInheritedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('missing-inherited', TRuleSeverity.Warning,
    cTexts[TComponentsInheritedCallsText.CtorTitle].Text);
end;

class function TMissingInheritedRule.DefaultMethods: TArray<string>;
begin
  Result := ['Create', 'Destroy', 'AfterConstruction', 'BeforeDestruction'];
end;

/// <summary>Kopf der Methode AName in der Klassendeklaration, sonst nil.</summary>
function ClassHeader(const AClass: TClassInfo; const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to AClass.Body.ChildCount - 1 do
  begin
    if (AClass.Body[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(AClass.Body[Index].Name, AName) then
    begin
      Exit(AClass.Body[Index]);
    end;
  end;
  Result := nil;
end;

/// <summary>Legt ein Vorfahr von AName (bis TObject) eigene Felder im Konstruktor an?</summary>
function AncestorConstructs(AModel: TComponentModel; const AName: string): Boolean;
var
  mName: string;
  mDepth: Integer;
begin
  Result := False;
  mName := AName;
  mDepth := 0;
  while not Result and (mName <> '') and not SameText(mName, 'TObject') and (mDepth < 64) do
  begin
    Result := IsIn(mName, ComponentBases) or IsIn(mName, ConstructorBases) or
      AModel.Ancestry.HasConstructor(mName);
    mName := AModel.Ancestry.ParentOf(mName);
    Inc(mDepth);
  end;
end;

/// <summary>Ist ATarget ein Bezeichner oder Self.Bezeichner?</summary>
function IsOwnTarget(ATarget: TSyntaxNode): Boolean;
begin
  Result := (ATarget.Kind = TSyntaxKind.Identifier) or ((ATarget.Kind = TSyntaxKind.MemberAccess) and
    (ATarget.ChildCount = 1) and (ATarget[0].Kind = TSyntaxKind.Identifier) and SameText(ATarget[0].Name, 'Self'));
end;

/// <summary>Ruft die Anweisung AStatement einen Konstruktor aus AConstructors oder AncestorConstructors auf
/// (Create(nil), Self.Create(nil), CreateNew)?</summary>
function CallsConstructor(AStatement: TSyntaxNode; const AConstructors: TArray<string>): Boolean;
var
  mTarget: TSyntaxNode;
begin
  Result := False;
  if (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
  begin
    Exit;
  end;
  mTarget := AStatement[0];
  if (mTarget.Kind = TSyntaxKind.Call) and (mTarget.ChildCount > 0) then
  begin
    mTarget := mTarget[0];
  end;
  Result := IsOwnTarget(mTarget) and (IsIn(mTarget.Name, AConstructors) or
    IsIn(mTarget.Name, AncestorConstructors));
end;

/// <summary>Ruft der Rumpf ARoot einen anderen Konstruktor derselben Klasse auf oder CreateNew?</summary>
function CallsOwnConstructor(ARoot: TSyntaxNode; const AConstructors: TArray<string>): Boolean;
var
  mNode: TSyntaxNode;
  mChild: Integer;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while not Result and (mPending.Count > 0) do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Continue;
      end;
      Result := CallsConstructor(mNode, AConstructors);
      for mChild := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mChild]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Namen der Konstruktoren, die die Klasse AClass deklariert.</summary>
function ConstructorNames(AModel: TComponentModel; const AClass: TClassInfo): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AClass.Body.ChildCount - 1 do
  begin
    if (AClass.Body[mIndex].Kind = TSyntaxKind.RoutineHeader) and
      StartsText('constructor', TrimLeft(AModel.NodeText(AClass.Body[mIndex]))) then
    begin
      Result := Result + [AClass.Body[mIndex].Name];
    end;
  end;
end;

/// <summary>Meldung für AMethodName ohne inherited: was vom Vorfahren AParent ausbleibt.</summary>
function InheritedMessage(const AMethodName, AParent: string; AAtEnd, AIsConstructor: Boolean): string;
begin
  if AAtEnd then
  begin
    Result := cTexts[TComponentsInheritedCallsText.NeverFreed].Fmt([AMethodName, AParent]);
  end
  else if AIsConstructor then
  begin
    Result := cTexts[TComponentsInheritedCallsText.NeverCreated].Fmt([AMethodName, AParent]);
  end
  else
  begin
    Result := cTexts[TComponentsInheritedCallsText.AfterConstruction].Fmt([AMethodName, AParent]);
  end;
end;

/// <summary>Meldet AMessage am Namen von AMethod, mit Korrektur AStatement am Anfang bzw. (AAtEnd) am Ende.
/// </summary>
procedure ReportInherited(AModel: TComponentModel; const AMethod: TMethodImpl; const AMessage, AStatement: string;
  AAtEnd: Boolean; const AReport: IRuleReport);
var
  mToken: TPascalToken;
  mEdit: TRuleEdit;
  mInserted: Boolean;
begin
  if not AModel.NameToken(AMethod, mToken) then
  begin
    Exit;
  end;
  if AAtEnd then
  begin
    mInserted := AModel.InsertBeforeEnd(AMethod.Block, AStatement, mEdit);
  end
  else
  begin
    mInserted := AModel.InsertAfterBegin(AMethod.Block, AStatement, mEdit);
  end;
  if mInserted then
  begin
    AReport.Add(TTextRange.Create(mToken.StartPos, mToken.EndPos), AMessage, TRuleConfidence.High,
      [TRuleFix.Create(cTexts[TComponentsInheritedCallsText.Insert].Fmt([AStatement]), [mEdit])]);
  end
  else
  begin
    AReport.Add(TTextRange.Create(mToken.StartPos, mToken.EndPos), AMessage, TRuleConfidence.High);
  end;
end;

type
  /// <summary>Ein Lauf von missing-inherited über die Klassen einer Datei.</summary>
  TMissingInheritedCheck = class
  private
    FModel: TComponentModel;
    FReport: IRuleReport;
    FMethods: TArray<string>;
    FInfo: TClassInfo;
    FParent: string;
    FConstructors: TArray<string>;
    function Wanted(const AMethod: TMethodImpl; const ASource: string): Boolean;
    function Statement(const AMethod: TMethodImpl; AIsConstructor: Boolean): string;
    procedure CheckMethod(const AMethod: TMethodImpl);
  public
    constructor Create(AModel: TComponentModel; const AReport: IRuleReport; const AMethods: TArray<string>);
    procedure CheckClass(const AInfo: TClassInfo);
  end;

constructor TMissingInheritedCheck.Create(AModel: TComponentModel; const AReport: IRuleReport;
  const AMethods: TArray<string>);
begin
  inherited Create;
  FModel := AModel;
  FReport := AReport;
  FMethods := AMethods;
end;

/// <summary>Prüft die Regel AMethod (Quelltext des Kopfs ASource) überhaupt: Konstruktoren aus der Option, die
/// keinen eigenen Konstruktor aufrufen und einen Vorfahren mit Konstruktor haben; sonst überschriebene Methoden
/// aus der Option, bei Komponenten ohne die von component-missing-inherited.</summary>
function TMissingInheritedCheck.Wanted(const AMethod: TMethodImpl; const ASource: string): Boolean;
begin
  if StartsText('constructor', ASource) then
  begin
    Result := (IsIn(AMethod.MethodName, FMethods) or (IsIn('Create', FMethods) and
      StartsText('Create', AMethod.MethodName))) and not CallsOwnConstructor(AMethod.Block, FConstructors) and
      AncestorConstructs(FModel, FParent);
  end
  else
  begin
    // Komponenten: Destroy meldet component-missing-inherited (keine Doppelmeldung).
    Result := IsIn(AMethod.MethodName, FMethods) and FModel.DeclaredWith(FInfo, AMethod.MethodName, 'override') and
      not (FModel.IsComponent(FInfo.Name) and IsIn(AMethod.MethodName, InheritedMethods));
  end;
end;

/// <summary>inherited; reicht die Parameter weiter. Ein eigener Konstruktor mit Parametern ohne override ruft den
/// des Vorfahren ohne Argumente.</summary>
function TMissingInheritedCheck.Statement(const AMethod: TMethodImpl; AIsConstructor: Boolean): string;
var
  mHeader: TSyntaxNode;
begin
  Result := 'inherited;';
  mHeader := ClassHeader(FInfo, AMethod.MethodName);
  if AIsConstructor and not FModel.DeclaredWith(FInfo, AMethod.MethodName, 'override') and (mHeader <> nil) and
    (Pos('(', FModel.NodeText(mHeader)) > 0) then
  begin
    Result := 'inherited Create;';
  end;
end;

procedure TMissingInheritedCheck.CheckMethod(const AMethod: TMethodImpl);
var
  mSource: string;
  mIsConstructor, mAtEnd: Boolean;
begin
  if not SameText(AMethod.ClassName, FInfo.Name) or FModel.HasToken(AMethod.Block, ['inherited']) then
  begin
    Exit;
  end;
  mSource := TrimLeft(FModel.NodeText(AMethod.Decl));
  // Klassenkonstruktoren und Klassenmethoden haben kein inherited der Instanz.
  if StartsText('class ', mSource) or not Wanted(AMethod, mSource) then
  begin
    Exit;
  end;
  mIsConstructor := StartsText('constructor', mSource);
  mAtEnd := SameText(AMethod.MethodName, 'Destroy') or SameText(AMethod.MethodName, 'BeforeDestruction') or
    StartsText('destructor', mSource);
  ReportInherited(FModel, AMethod, InheritedMessage(AMethod.MethodName, FParent, mAtEnd, mIsConstructor),
    Statement(AMethod, mIsConstructor), mAtEnd, FReport);
end;

procedure TMissingInheritedCheck.CheckClass(const AInfo: TClassInfo);
var
  mMethod: TMethodImpl;
begin
  FInfo := AInfo;
  FParent := DeclaredParent(AInfo);
  // Ohne Vorfahr erbt die Klasse von TObject: dort gibt es nichts aufzurufen.
  if (FParent = '') or SameText(FParent, 'TObject') then
  begin
    Exit;
  end;
  FConstructors := ConstructorNames(FModel, AInfo);
  for mMethod in FModel.Methods do
  begin
    CheckMethod(mMethod);
  end;
end;

procedure TMissingInheritedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TComponentModel;
  mCache: IRuleDerivedCache;
  mCheck: TMissingInheritedCheck;
  mInfo: TClassInfo;
begin
  mCache := TRuleDerived.Open(AContext);
  if not PrepareModel(mCache, AContext, mModel) then
  begin
    Exit;
  end;
  mCheck := TMissingInheritedCheck.Create(mModel, AReport, TRuleOptions.Strings(AContext.Options, 'methods',
    DefaultMethods));
  try
    for mInfo in mModel.Classes do
    begin
      mCheck.CheckClass(mInfo);
    end;
  finally
    mCheck.Free;
  end;
end;

{ TMessageHandlerWithoutInheritedRule }

function TMessageHandlerWithoutInheritedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('message-handler-without-inherited', TRuleSeverity.Warning,
    cTexts[TComponentsInheritedCallsText.MessageTitle].Text);
end;

class function TMessageHandlerWithoutInheritedRule.DefaultSwallow: TArray<string>;
begin
  Result := ['WM_ERASEBKGND'];
end;

const
  // Nachrichten (Komma-Liste, * am Ende: Präfix) und was ohne inherited bei ihnen wegfällt; erste passende Zeile
  // gilt.
  cConsequenceMessages: array[0..8] of string = ('WM_SIZE,WM_WINDOWPOSCHANGED,WM_WINDOWPOSCHANGING',
    'WM_CLOSE,WM_QUERYENDSESSION', 'WM_PAINT,WM_NCPAINT,WM_PRINTCLIENT',
    'WM_KEYDOWN,WM_KEYUP,WM_CHAR,WM_SYSKEYDOWN,WM_SYSCHAR,CM_DIALOGKEY,CM_DIALOGCHAR,CM_WANTSPECIALKEY',
    'WM_SETFOCUS,WM_KILLFOCUS,CM_ENTER,CM_EXIT',
    'WM_LBUTTON*,WM_RBUTTON*,WM_MBUTTON*,WM_MOUSEMOVE,WM_MOUSEWHEEL,CM_MOUSEENTER,CM_MOUSELEAVE',
    'WM_DESTROY,WM_NCDESTROY', 'WM_DPICHANGED,CM_PARENTFONTCHANGED,CM_FONTCHANGED,CM_STYLECHANGED', 'CM_*');
  cConsequenceTexts: array[0..8] of TComponentsInheritedCallsText = (TComponentsInheritedCallsText.Consequence0,
    TComponentsInheritedCallsText.Consequence1, TComponentsInheritedCallsText.Consequence2,
    TComponentsInheritedCallsText.Consequence3, TComponentsInheritedCallsText.Consequence4,
    TComponentsInheritedCallsText.Consequence5, TComponentsInheritedCallsText.Consequence6,
    TComponentsInheritedCallsText.Consequence7, TComponentsInheritedCallsText.Consequence8);

/// <summary>Passt der Nachrichtenname AName zu einem Eintrag der Komma-Liste AList (* am Ende: Präfix)?</summary>
function MatchesMessage(const AName, AList: string): Boolean;
var
  mEntry: string;
begin
  Result := False;
  for mEntry in AList.Split([',']) do
  begin
    if EndsStr('*', mEntry) then
    begin
      Result := Result or StartsStr(Copy(mEntry, 1, Length(mEntry) - 1), AName);
    end
    else
    begin
      Result := Result or (AName = mEntry);
    end;
  end;
end;

class function TMessageHandlerWithoutInheritedRule.Consequence(const AMessage: string): string;
var
  mName: string;
  mIndex: Integer;
begin
  mName := UpperCase(Copy(AMessage, LastDelimiter('.', AMessage) + 1, MaxInt));
  Result := '';
  for mIndex := 0 to High(cConsequenceMessages) do
  begin
    if (Result = '') and MatchesMessage(mName, cConsequenceMessages[mIndex]) then
    begin
      Result := cTexts[cConsequenceTexts[mIndex]].Text;
    end;
  end;
  if Result = '' then
  begin
    Result := cTexts[TComponentsInheritedCallsText.DefaultHandling].Text;
  end;
end;

/// <summary>Setzt der Rumpf ABlock "Msg.Result := …"? Dann beantwortet der Handler die Nachricht bewusst selbst
/// (MA_NOACTIVATE, HTCLIENT).</summary>
function AnswersItself(const AContext: TRuleContext; ABlock: TSyntaxNode): Boolean;
var
  mCode, mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  mCode := nil;
  // Nur die Token des Blocks, binär angesprungen statt die ganze Datei je Handler (#1323).
  mTokens := AContext.Tree.Tokens;
  mIndex := AContext.Tree.FirstTokenFrom(ABlock.StartOffset);
  while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < ABlock.EndOffset) do
  begin
    if not (mTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      mCode := mCode + [mTokens[mIndex]];
    end;
    Inc(mIndex);
  end;
  Result := False;
  for mIndex := 1 to High(mCode) - 1 do
  begin
    Result := Result or (mCode[mIndex - 1].IsSymbol('.') and SameText(mCode[mIndex].Text, 'Result') and
      mCode[mIndex + 1].IsSymbol(':='));
  end;
end;

type
  /// <summary>Ein Lauf von message-handler-without-inherited über die Klassen einer Datei.</summary>
  TMessageHandlerCheck = class
  private
    FContext: TRuleContext;
    FModel: TComponentModel;
    FReport: IRuleReport;
    FSwallow: TArray<string>;
    function MessageOf(AHeader: TSyntaxNode; out AName: string): Boolean;
    function LacksInherited(const AInfo: TClassInfo; AHeader: TSyntaxNode; const AMessageName: string;
      out AMethod: TMethodImpl): Boolean;
    procedure CheckHeader(const AInfo: TClassInfo; AHeader: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; AModel: TComponentModel; const AReport: IRuleReport);
    procedure CheckClass(const AInfo: TClassInfo);
  end;

constructor TMessageHandlerCheck.Create(const AContext: TRuleContext; AModel: TComponentModel;
  const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FModel := AModel;
  FReport := AReport;
  FSwallow := TRuleOptions.Strings(AContext.Options, 'swallow', TMessageHandlerWithoutInheritedRule.DefaultSwallow);
end;

/// <summary>Nachricht des Handlers AHeader ("message WM_X"); False ohne message oder bei einer eigenen Nachricht
/// der Unit (WM_ATLAS_X = WM_APP + 1), die Windows und VCL nicht kennen (#1371).</summary>
function TMessageHandlerCheck.MessageOf(AHeader: TSyntaxNode; out AName: string): Boolean;
var
  mMatch: TMatch;
begin
  AName := '';
  mMatch := TRegEx.Match(FModel.NodeText(AHeader), '\bmessage\s+([\w.]+)', [roIgnoreCase]);
  Result := mMatch.Success;
  if Result then
  begin
    AName := mMatch.Groups[1].Value;
    Result := not TRegEx.IsMatch(FContext.Text, '\b' + TRegEx.Escape(AName) + '\s*=\s*(WM_APP|WM_USER)\b',
      [roIgnoreCase]);
  end;
end;

/// <summary>Hat der Handler AHeader einen Rumpf ohne inherited, DefaultHandler &amp; Co., der Msg.Result nicht
/// selbst setzt, und steht AMessageName nicht in swallow?</summary>
function TMessageHandlerCheck.LacksInherited(const AInfo: TClassInfo; AHeader: TSyntaxNode;
  const AMessageName: string; out AMethod: TMethodImpl): Boolean;
begin
  Result := not MatchText(Copy(AMessageName, LastDelimiter('.', AMessageName) + 1, MaxInt), FSwallow) and
    FModel.FindMethod(AInfo.Name, AHeader.Name, AMethod) and (AMethod.Block <> nil);
  Result := Result and
    not FModel.HasToken(AMethod.Block, ['inherited', 'DefaultHandler', 'DefWindowProc', 'CallWindowProc']) and
    not AnswersItself(FContext, AMethod.Block);
end;

procedure TMessageHandlerCheck.CheckHeader(const AInfo: TClassInfo; AHeader: TSyntaxNode);
var
  mMethod: TMethodImpl;
  mToken: TPascalToken;
  mEdit: TRuleEdit;
  mMessageName, mText: string;
begin
  if (AHeader.Kind <> TSyntaxKind.RoutineHeader) or not MessageOf(AHeader, mMessageName) or
    not LacksInherited(AInfo, AHeader, mMessageName, mMethod) or not FModel.NameToken(mMethod, mToken) then
  begin
    Exit;
  end;
  mText := cTexts[TComponentsInheritedCallsText.NoInherited].Fmt([mMethod.MethodName,
    TMessageHandlerWithoutInheritedRule.Consequence(mMessageName)]);
  if FModel.InsertAfterBegin(mMethod.Block, 'inherited;', mEdit) then
  begin
    FReport.Add(TTextRange.Create(mToken.StartPos, mToken.EndPos), mText, TRuleConfidence.Medium,
      [TRuleFix.Create(cTexts[TComponentsInheritedCallsText.InsertAtStart].Text, [mEdit])]);
  end
  else
  begin
    FReport.Add(TTextRange.Create(mToken.StartPos, mToken.EndPos), mText, TRuleConfidence.Medium);
  end;
end;

procedure TMessageHandlerCheck.CheckClass(const AInfo: TClassInfo);
var
  mParent: string;
  mIndex: Integer;
begin
  // Ohne Vorfahr behandelt TObject.DefaultHandler nichts.
  mParent := DeclaredParent(AInfo);
  if (mParent = '') or SameText(mParent, 'TObject') then
  begin
    Exit;
  end;
  for mIndex := 0 to AInfo.Body.ChildCount - 1 do
  begin
    CheckHeader(AInfo, AInfo.Body[mIndex]);
  end;
end;

procedure TMessageHandlerWithoutInheritedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TComponentModel;
  mCache: IRuleDerivedCache;
  mCheck: TMessageHandlerCheck;
  mInfo: TClassInfo;
begin
  mCache := TRuleDerived.Open(AContext);
  if not ContainsText(AContext.Text, 'message') or not PrepareModel(mCache, AContext, mModel) then
  begin
    Exit;
  end;
  mCheck := TMessageHandlerCheck.Create(AContext, mModel, AReport);
  try
    for mInfo in mModel.Classes do
    begin
      mCheck.CheckClass(mInfo);
    end;
  finally
    mCheck.Free;
  end;
end;

{ TInheritedOrderRule }

function TInheritedOrderRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('inherited-order', TRuleSeverity.Warning,
    cTexts[TComponentsInheritedCallsText.OrderTitle].Text);
end;

/// <summary>Ist AStatement ein Aufruf von inherited (inherited; inherited Name; inherited Name(…))?</summary>
function IsInheritedCall(AStatement: TSyntaxNode; out AName: string): Boolean;
var
  Node: TSyntaxNode;
begin
  Result := False;
  AName := '';
  if (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount <> 1) then
  begin
    Exit;
  end;
  Node := AStatement[0];
  if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 0) then
  begin
    Node := Node[0];
  end;
  if Node.Kind <> TSyntaxKind.InheritedExpr then
  begin
    Exit;
  end;
  AName := Node.Name;
  Result := True;
end;

/// <summary>Namen der Felder, Properties und Methoden der Klasse selbst.</summary>
function OwnMembers(const AClass: TClassInfo): TArray<string>;
var
  Index: Integer;
begin
  Result := OwnFields(AClass);
  for Index := 0 to AClass.Body.ChildCount - 1 do
  begin
    if AClass.Body[Index].Kind in [TSyntaxKind.PropertyDecl, TSyntaxKind.RoutineHeader] then
    begin
      Result := Result + [AClass.Body[Index].Name];
    end;
  end;
end;

/// <summary>Bezeichner F bzw. Self.F als Ziel einer Freigabe: F.Free, F.DisposeOf, F.Destroy, FreeAndNil(F).</summary>
function FreedName(ANode: TSyntaxNode): string;
var
  Target: TSyntaxNode;
begin
  Result := '';
  Target := nil;
  if (ANode.Kind = TSyntaxKind.MemberAccess) and IsIn(ANode.Name, ['Free', 'DisposeOf', 'Destroy']) and
    (ANode.ChildCount = 1) then
  begin
    Target := ANode[0];
  end
  else if (ANode.Kind = TSyntaxKind.Call) and IsIn(ANode.Name, ['FreeAndNil', 'Dispose', 'FreeMem']) and
    (ANode.ChildCount = 2) then
  begin
    Target := ANode[1];
  end;
  if Target = nil then
  begin
    Exit;
  end;
  if (Target.Kind = TSyntaxKind.MemberAccess) and (Target.ChildCount = 1) and
    (Target[0].Kind = TSyntaxKind.Identifier) and SameText(Target[0].Name, 'Self') then
  begin
    Exit(Target.Name);
  end;
  if Target.Kind = TSyntaxKind.Identifier then
  begin
    Result := Target.Name;
  end;
end;

/// <summary>Erstes freigegebenes eigenes Feld in ANode, '' ohne.</summary>
function FirstFreedField(ANode: TSyntaxNode; const AFields: TArray<string>): string;
var
  Index: Integer;
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
      Result := FreedName(Node);
      if (Result <> '') and IsIn(Result, AFields) then
      begin
        Exit;
      end;
      if Node.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Continue;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
    Result := '';
  finally
    Pending.Free;
  end;
end;

/// <summary>Erstes eigenes Feld aus AFields, das eine Anweisung von ABlock ab AFirst freigibt; '' ohne.</summary>
function FreedFrom(ABlock: TSyntaxNode; AFirst: Integer; const AFields: TArray<string>): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := AFirst;
  while (Result = '') and (mIndex < ABlock.ChildCount) do
  begin
    Result := FirstFreedField(ABlock[mIndex], AFields);
    Inc(mIndex);
  end;
end;

/// <summary>Bezeichner F oder Self.F, der kein Aufrufziel ist; '' sonst.</summary>
function AccessedName(ANode: TSyntaxNode): string;
begin
  Result := '';
  if (ANode.Kind = TSyntaxKind.Identifier) and not ((ANode.Parent <> nil) and
    (ANode.Parent.Kind = TSyntaxKind.Call) and (ANode.Parent[0] = ANode)) then
  begin
    Result := ANode.Name;
  end
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
  begin
    Result := ANode.Name;
  end;
end;

procedure TInheritedOrderRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  Lines: TArray<string>;
  LineBreak: string;

  function FindClassInfo(const AName: string; out AInfo: TClassInfo): Boolean;
  var
    Info: TClassInfo;
  begin
    for Info in Model.Classes do
    begin
      if SameText(Info.Name, AName) then
      begin
        AInfo := Info;
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Wartet der Destruktor eines Vorfahren auf etwas (TThread.Destroy beendet und erwartet den Thread)?
  function WaitsInDestructor(const AClassName: string): Boolean;
  var
    Name: string;
    Depth: Integer;
  begin
    Name := AClassName;
    for Depth := 0 to 63 do
    begin
      if ContainsText(Name, 'Thread') then
      begin
        Exit(True);
      end;
      if (Name = '') or SameText(Name, 'TObject') then
      begin
        Break;
      end;
      Name := Model.Ancestry.ParentOf(Name);
    end;
    Result := False;
  end;

  // Steht AStatement allein in seinen Zeilen (höchstens mit ";")?
  function OwnLines(AStatement: TSyntaxNode): Boolean;
  begin
    Result := (AStatement.EndPos.Line <= High(Lines)) and
      (Trim(Copy(Lines[AStatement.StartPos.Line], 1, AStatement.StartPos.Character)) = '') and
      IsIn(Trim(Copy(Lines[AStatement.EndPos.Line], AStatement.EndPos.Character + 1, MaxInt)), ['', ';']);
  end;

  // inherited ans Ende bzw. an den Anfang: Zeilen der Anweisung entfernen, Text neu einfügen.
  function MoveFix(ABlock, AStatement: TSyntaxNode; AToEnd: Boolean; out AFix: TRuleFix): Boolean;
  var
    Insert, Remove: TRuleEdit;
    Text: string;
  begin
    Result := False;
    if not OwnLines(AStatement) then
    begin
      Exit;
    end;
    Text := Model.NodeText(AStatement) + ';';
    if AToEnd then
    begin
      Result := Model.InsertBeforeEnd(ABlock, Text, Insert);
    end
    else
    begin
      Result := Model.InsertAfterBegin(ABlock, Text, Insert);
    end;
    if not Result then
    begin
      Exit;
    end;
    Remove := TRuleEdit.Create(TTextRange.Create(AStatement.StartPos.Line, 0, AStatement.EndPos.Line + 1, 0), '');
    if AToEnd then
    begin
      AFix := TRuleFix.Create(cTexts[TComponentsInheritedCallsText.MoveToEnd].Text, [Remove, Insert]);
    end
    else
    begin
      AFix := TRuleFix.Create(cTexts[TComponentsInheritedCallsText.MoveToStart].Text, [Insert, Remove]);
    end;
  end;

  procedure CheckDestructor(const AMethod: TMethodImpl; const AInfo: TClassInfo);
  var
    Index: Integer;
    Statement: TSyntaxNode;
    Name, Field: string;
    Fix: TRuleFix;
    mFixes: TArray<TRuleFix>;
  begin
    if WaitsInDestructor(AInfo.Name) then
    begin
      Exit;
    end;
    for Index := 0 to AMethod.Block.ChildCount - 1 do
    begin
      Statement := AMethod.Block[Index];
      if not IsInheritedCall(Statement, Name) then
      begin
        Continue;
      end;
      Field := '';
      if (Name = '') or SameText(Name, AMethod.MethodName) then
      begin
        Field := FreedFrom(AMethod.Block, Index + 1, OwnFields(AInfo));
      end;
      if Field <> '' then
      begin
        mFixes := nil;
        if MoveFix(AMethod.Block, Statement, True, Fix) then
        begin
          mFixes := [Fix];
        end;
        AReport.Add(TTextRange.Create(Statement.StartPos, Statement.EndPos),
          cTexts[TComponentsInheritedCallsText.BeforeFree].Fmt([Field]), TRuleConfidence.Medium, mFixes);
      end;
      Exit;
    end;
  end;

  // Erstes geerbtes Feld bzw. erste geerbte Property in ANode (F, Self.F); nil ohne.
  function FirstInheritedAccess(ARoot: TSyntaxNode; const AParent: string; const AExcluded: TArray<string>;
    out AName, AOwner: string): TSyntaxNode;
  var
    Index: Integer;
    Name, Unresolved: string;
    Member: TIndexSymbol;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := nil;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Continue;
        end;
        Name := AccessedName(Node);
        if (Name <> '') and not SameText(Name, 'Self') and not IsIn(Name, AExcluded) and
          Model.Ancestry.FindMember(AParent, Name, Member, Unresolved) and
          (Member.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) then
        begin
          AName := Name;
          AOwner := Member.Container;
          Exit(Node);
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

  // Verwenden die Argumente von inherited Create(…) lokale Variablen, die die Anweisungen davor setzen?
  function ArgumentsUseLocals(ARoot: TSyntaxNode; const ALocals: TArray<string>): Boolean;
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.Identifier) and IsIn(Node.Name, ALocals) then
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

  procedure CheckConstructor(const AMethod: TMethodImpl; const AInfo: TClassInfo);
  var
    Index, Earlier: Integer;
    Statement, Access: TSyntaxNode;
    Name, Member, Owner, Parent: string;
    Locals, Excluded: TArray<string>;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    Parent := DeclaredParent(AInfo);
    if (Parent = '') or SameText(Parent, 'TObject') or Model.HasToken(AMethod.Block, ['with']) then
    begin
      Exit;
    end;
    Locals := MethodLocalNames(AMethod);
    Excluded := Locals + OwnMembers(AInfo);
    for Index := 0 to AMethod.Block.ChildCount - 1 do
    begin
      Statement := AMethod.Block[Index];
      if not IsInheritedCall(Statement, Name) then
      begin
        Continue;
      end;
      for Earlier := 0 to Index - 1 do
      begin
        Access := FirstInheritedAccess(AMethod.Block[Earlier], Parent, Excluded, Member, Owner);
        if Access = nil then
        begin
          Continue;
        end;
        Fixes := nil;
        if not ArgumentsUseLocals(Statement, Locals) and MoveFix(AMethod.Block, Statement, False, Fix) then
        begin
          Fixes := [Fix];
        end;
        AReport.Add(TTextRange.Create(Access.StartPos, Access.EndPos),
          cTexts[TComponentsInheritedCallsText.BeforeInherited].Fmt(
          [AMethod.MethodName, Member, Owner]), TRuleConfidence.Medium, Fixes);
        Exit;
      end;
      Exit;
    end;
  end;

var
  Method: TMethodImpl;
  Info: TClassInfo;
  Source: string;
begin
  Cache := TRuleDerived.Open(AContext);
  if not PrepareModel(Cache, AContext, Model) or not ContainsText(AContext.Text, 'inherited') then
  begin
    Exit;
  end;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  for Method in Model.Methods do
  begin
    if not FindClassInfo(Method.ClassName, Info) then
    begin
      Continue;
    end;
    Source := TrimLeft(Model.NodeText(Method.Decl));
    if StartsText('destructor', Source) then
    begin
      CheckDestructor(Method, Info);
    end
    else if StartsText('constructor', Source) then
    begin
      CheckConstructor(Method, Info);
    end;
  end;
end;

{ TInheritedWrongMethodRule }

function TInheritedWrongMethodRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('inherited-wrong-method', TRuleSeverity.Warning,
    cTexts[TComponentsInheritedCallsText.OtherTitle].Text);
end;

class function TInheritedWrongMethodRule.Allowed(const APairs: TArray<string>;
  const AMethod, AInherited: string): Boolean;
var
  Pair: string;
  Separator: Integer;
begin
  for Pair in APairs do
  begin
    Separator := Pos('>', Pair);
    if (Separator > 0) and MatchesGlob(Trim(Copy(Pair, 1, Separator - 1)), AMethod) and
      MatchesGlob(Trim(Copy(Pair, Separator + 1, MaxInt)), AInherited) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Anzahl der Parameter im Kopf der Methode (A, B: Integer zählt zwei).</summary>
function ParameterCount(const AMethod: TMethodImpl): Integer;
var
  mHeader: TSyntaxNode;
begin
  Result := 0;
  mHeader := AMethod.Decl.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader <> nil then
  begin
    Result := Length(SectionNames(mHeader.FindChild(TSyntaxKind.Parameters)));
  end;
end;

/// <summary>Meldet inherited ACall in AMethod; mit gleicher Zahl an Argumenten wie Parametern passt der eigene
/// Name als Korrektur.</summary>
procedure ReportWrongCall(const AMethod: TMethodImpl; ACall: TSyntaxNode; const AReport: IRuleReport);
var
  mArguments: Integer;
  mFixes: TArray<TRuleFix>;
begin
  mFixes := nil;
  mArguments := 0;
  if ACall.Parent.Kind = TSyntaxKind.Call then
  begin
    mArguments := ACall.Parent.ChildCount - 1;
  end;
  if mArguments = ParameterCount(AMethod) then
  begin
    mFixes := [TRuleFix.Create(cTexts[TComponentsInheritedCallsText.CallInherited].Fmt([AMethod.MethodName]),
      [TRuleEdit.Create(TTextRange.Create(ACall.StartPos, ACall.EndPos), 'inherited ' + AMethod.MethodName)])];
  end;
  AReport.Add(TTextRange.Create(ACall.StartPos, ACall.EndPos),
    cTexts[TComponentsInheritedCallsText.OtherMethod].Fmt(
    [AMethod.MethodName, ACall.Name, AMethod.MethodName]), TRuleConfidence.High, mFixes);
end;

procedure TInheritedWrongMethodRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  Pairs: TArray<string>;

  function FindClassInfo(const AName: string; out AInfo: TClassInfo): Boolean;
  var
    Info: TClassInfo;
  begin
    for Info in Model.Classes do
    begin
      if SameText(Info.Name, AName) then
      begin
        AInfo := Info;
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Aufrufe inherited Name bzw. inherited Name(…) als Anweisung oder mit Klammern; nur sie sind sicher Methoden
  // (inherited Caption ohne Klammern kann eine Property sein).
  procedure CollectCalls(ARoot: TSyntaxNode; var ACalls: TArray<TSyntaxNode>; var ASameName: Boolean;
    const AMethodName: string);
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
        if Node.Kind = TSyntaxKind.InheritedExpr then
        begin
          if (Node.Name = '') or SameText(Node.Name, AMethodName) then
          begin
            ASameName := True;
          end
          else if (Node.Parent <> nil) and ((Node.Parent.Kind = TSyntaxKind.CallStatement) or
            ((Node.Parent.Kind = TSyntaxKind.Call) and (Node.Parent[0] = Node))) then
          begin
            ACalls := ACalls + [Node];
          end;
        end;
        if Node.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Continue;
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
  Info: TClassInfo;
  Calls: TArray<TSyntaxNode>;
  Call: TSyntaxNode;
  SameName: Boolean;
  Source: string;
begin
  Cache := TRuleDerived.Open(AContext);
  if not PrepareModel(Cache, AContext, Model) or not ContainsText(AContext.Text, 'inherited') then
  begin
    Exit;
  end;
  Pairs := TRuleOptions.Strings(AContext.Options, 'allowed', nil);
  for Method in Model.Methods do
  begin
    // Konstruktoren dürfen jeden geerbten Konstruktor aufrufen (inherited Create(nil)).
    Source := TrimLeft(Model.NodeText(Method.Decl));
    if StartsText('constructor', Source) or StartsText('class ', Source) or
      not FindClassInfo(Method.ClassName, Info) or not Model.DeclaredWith(Info, Method.MethodName, 'override') then
    begin
      Continue;
    end;
    Calls := nil;
    SameName := False;
    CollectCalls(Method.Block, Calls, SameName, Method.MethodName);
    // Ruft die Methode auch sich selbst im Vorfahren auf, ist der andere Aufruf gewollt.
    if SameName then
    begin
      Continue;
    end;
    for Call in Calls do
    begin
      if not Allowed(Pairs, Method.MethodName, Call.Name) then
      begin
        ReportWrongCall(Method, Call, AReport);
      end;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Components.InheritedCalls', cTexts);

end.
