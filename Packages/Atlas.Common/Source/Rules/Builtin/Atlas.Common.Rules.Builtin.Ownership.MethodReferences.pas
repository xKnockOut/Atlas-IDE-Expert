unit Atlas.Common.Rules.Builtin.Ownership.MethodReferences;

// Leckregeln für Methodenreferenzen und Ereignisse (#1876):
//   anonymous-method-self-cycle  Eine lokale Variable erhält eine anonyme Methode der Routine, und eine anonyme
//                                Methode derselben Routine fängt die Variable ein: Alle anonymen Methoden einer
//                                Routine teilen einen Rahmen, der dann über die Variable sich selbst festhält und nie
//                                freigegeben wird. Still, wenn die Variable in der Routine auf nil gesetzt wird.
//   event-handler-not-unhooked   Eine Methode weist eine eigene Methode dem Ereignis OnXyz eines fremden Objekts zu
//                                (Parameter oder Feld, das die Klasse nicht selbst erzeugt und das nicht im
//                                published-Teil steht), und weder Destroy, BeforeDestruction, Notification noch Release
//                                (Abmelden einer Klasse mit Klassenmethoden) der Klasse setzen dieses Ereignis zurück. Lebt das fremde Objekt länger, ruft es nach
//                                dem Freigeben die Methode eines toten Objekts auf. Korrektur bei Feldern: im
//                                Destruktor der Datei "if Assigned(FFeld) then FFeld.OnXyz := nil;" einfügen.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cAnonymousMethodSelfCycleRuleId = 'anonymous-method-self-cycle';
  cEventHandlerNotUnhookedRuleId = 'event-handler-not-unhooked';

type
  TAnonymousMethodSelfCycleRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TEventHandlerNotUnhookedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert anonymous-method-self-cycle und event-handler-not-unhooked.</summary>
procedure RegisterOwnershipMethodReferenceRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.EventAssignments,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TMethodReferenceText = (CycleTitle, Cycle, EventTitle, Event, Unhook);

const
  cTexts: array[TMethodReferenceText] of TAtlasText = (
    (De: 'Anonyme Methode hält ihren eigenen Rahmen fest'; En: 'Anonymous method keeps its own frame alive'),
    (De: '%s hält eine anonyme Methode dieser Routine und wird selbst von einer anonymen Methode eingefangen: Der ' +
      'gemeinsame Rahmen hält sich selbst fest und wird nie freigegeben. Die Methodenreferenz in einer eigenen ' +
      'Routine bauen oder %s vor dem Ende auf nil setzen.';
     En: '%s holds an anonymous method of this routine and is itself captured by an anonymous method: the shared ' +
      'frame keeps itself alive and is never released. Build the method reference in a routine of its own or set ' +
      '%s to nil before the end.'),
    (De: 'Ereignis eines fremden Objekts nicht zurückgesetzt'; En: 'Event of a foreign object not unhooked'),
    (De: '%s.%s zeigt auf %s, wird beim Freigeben von %s aber nicht zurückgesetzt; lebt %s länger, ruft es die ' +
      'Methode eines freigegebenen Objekts auf.';
     En: '%s.%s points to %s but is not reset when %s is released; if %s lives longer, it calls the method of a ' +
      'released object.'),
    (De: 'Im Destruktor %s.%s := nil setzen'; En: 'Set %s.%s := nil in the destructor'));

{$SCOPEDENUMS OFF}

const
  // Routinen, in denen eine Klasse ihre Ereignisse an fremden Objekten zurücksetzt; Release ist das Abmelden einer
  // Klasse, die nur aus Klassenmethoden und -feldern besteht und deshalb keinen Destruktor hat.
  cTeardownMethods: array[0..4] of string = ('Destroy', 'BeforeDestruction', 'Notification', 'FreeNotification',
    'Release');

/// <summary>Alle Bezeichner AName unter ANode (nicht als Mitglied hinter einem Punkt), ohne lokale Routinen.
/// </summary>
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

/// <summary>Steht ANode in einer anonymen Methode unterhalb von ARoutine?</summary>
function InsideAnonymous(ANode, ARoutine: TSyntaxNode): Boolean;
var
  mCurrent: TSyntaxNode;
begin
  mCurrent := ANode.Parent;
  while (mCurrent <> nil) and (mCurrent <> ARoutine) do
  begin
    if mCurrent.Kind = TSyntaxKind.AnonymousMethod then
    begin
      Exit(True);
    end;
    mCurrent := mCurrent.Parent;
  end;
  Result := False;
end;

/// <summary>Wert ohne Klammern: (procedure … end) wird zur anonymen Methode.</summary>
function Unwrapped(AValue: TSyntaxNode): TSyntaxNode;
begin
  Result := AValue;
  while (Result <> nil) and (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
  begin
    Result := Result[0];
  end;
end;

{ anonymous-method-self-cycle }

type
  TSelfCycleScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    procedure CheckVariable(ARoutine: TSyntaxNode; const AName: string; AInline: TSyntaxNode);
    procedure CheckVarSection(ARoutine, ASection: TSyntaxNode);
    procedure CheckRoutine(ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

constructor TSelfCycleScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

/// <summary>Wert der Zuweisung, deren linke Seite ANode ist (ohne Klammern); sonst nil.</summary>
function AssignedValue(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ANode.Parent.Kind = TSyntaxKind.AssignStatement) and (ANode.Parent[0] = ANode) and
    (ANode.Parent.ChildCount > 1) then
  begin
    Result := Unwrapped(ANode.Parent[1]);
  end;
end;

function IsNilValue(AValue: TSyntaxNode): Boolean;
begin
  Result := (AValue <> nil) and (AValue.Kind in [TSyntaxKind.Literal, TSyntaxKind.Identifier]) and
    SameText(AValue.Name, 'nil');
end;

/// <summary>Inline-Variablen der Routine mit einem einzelnen Namen (ohne lokale Routinen).</summary>
function InlineVars(ARoutine: TSyntaxNode): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  ARoutine.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.InlineVar) and not ANode.Name.Contains(',') then
      begin
        mFound := mFound + [ANode];
      end;
      Result := (ANode = ARoutine) or (ANode.Kind <> TSyntaxKind.RoutineDecl);
    end);
  Result := mFound;
end;

/// <summary>Prüft die lokale Variable AName; AInline ist ihre Inline-Deklaration oder nil.</summary>
procedure TSelfCycleScan.CheckVariable(ARoutine: TSyntaxNode; const AName: string; AInline: TSyntaxNode);
var
  mNode, mStore, mValue: TSyntaxNode;
  mCaptured: Boolean;
begin
  mStore := nil;
  if (AInline <> nil) and (AInline.ChildCount > 0) and
    (Unwrapped(AInline[AInline.ChildCount - 1]).Kind = TSyntaxKind.AnonymousMethod) then
  begin
    mStore := AInline;
  end;
  mCaptured := False;
  for mNode in Occurrences(ARoutine, AName) do
  begin
    mValue := AssignedValue(mNode);
    // V := nil löst den Kreis auf.
    if IsNilValue(mValue) then
    begin
      Exit;
    end;
    if (mValue <> nil) and (mValue.Kind = TSyntaxKind.AnonymousMethod) and (mStore = nil) then
    begin
      mStore := mNode.Parent;
    end;
    mCaptured := mCaptured or InsideAnonymous(mNode, ARoutine);
  end;
  if mCaptured and (mStore <> nil) then
  begin
    FReport.Add(TTextRange.Create(mStore.StartPos, mStore[0].EndPos),
      cTexts[TMethodReferenceText.Cycle].Fmt([AName, AName]), TRuleConfidence.High);
  end;
end;

procedure TSelfCycleScan.CheckVarSection(ARoutine, ASection: TSyntaxNode);
var
  mDecl: Integer;
  mName: string;
begin
  for mDecl := 0 to ASection.ChildCount - 1 do
  begin
    for mName in ASection[mDecl].Name.Split([',']) do
    begin
      if (ASection[mDecl].Kind = TSyntaxKind.VarDecl) and (Trim(mName) <> '') then
      begin
        CheckVariable(ARoutine, Trim(mName), nil);
      end;
    end;
  end;
end;

procedure TSelfCycleScan.CheckRoutine(ARoutine: TSyntaxNode);
var
  mIndex: Integer;
  mInline: TSyntaxNode;
begin
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if ARoutine[mIndex].Kind = TSyntaxKind.VarSection then
    begin
      CheckVarSection(ARoutine, ARoutine[mIndex]);
    end;
  end;
  for mInline in InlineVars(ARoutine) do
  begin
    CheckVariable(ARoutine, mInline.Name, mInline);
  end;
end;

procedure TSelfCycleScan.Run;
var
  mDerived: IRuleDerivedCache;
  mRoutine: TSyntaxNode;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) or not ContainsText(FContext.Text, 'procedure') and
    not ContainsText(FContext.Text, 'function') then
  begin
    Exit;
  end;
  mDerived := TRuleDerived.Open(FContext);
  for mRoutine in TRuleDerived.Routines(mDerived, FContext) do
  begin
    CheckRoutine(mRoutine);
  end;
end;

{ event-handler-not-unhooked }

type
  /// <summary>Eine Zuweisung Fremd.OnXyz := Methode in einer Methode der Klasse.</summary>
  THook = record
    Statement: TSyntaxNode;
    ClassName: string;
    ObjectName: string;
    EventName: string;
    Handler: string;
    IsField: Boolean;
  end;

  TEventHookScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FLines: TArray<string>;
    FLineBreak: string;
    FRoutines: TArray<TSyntaxNode>;
    function ClassRoutines(const AClassName: string): TArray<TSyntaxNode>;
    function HasMethod(ABody: TSyntaxNode; const AName: string): Boolean;
    function ForeignField(ABody: TSyntaxNode; const AClassName, AName: string): Boolean;
    function TakesField(const AClassName, AName: string): Boolean;
    function ResetsEvent(const AClassName, AEventName: string): Boolean;
    function HookAt(ARoutine, AStatement: TSyntaxNode; out AHook: THook): Boolean;
    function UnhookFix(const AHook: THook; out AFix: TRuleFix): Boolean;
    procedure ReportHook(const AHook: THook);
    procedure CheckRoutine(ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

/// <summary>Klasse einer Methode TKlasse.Name (auch TAussen.TInnen.Name); '' für freie Routinen.</summary>
function ClassOf(ARoutine: TSyntaxNode): string;
var
  mName: string;
begin
  mName := ARoutine.Name;
  Result := '';
  if mName.Contains('.') then
  begin
    Result := Copy(mName, 1, mName.LastIndexOf('.'));
  end;
end;

function MethodOf(ARoutine: TSyntaxNode): string;
begin
  Result := ARoutine.Name;
  if Result.Contains('.') then
  begin
    Result := Copy(Result, Result.LastIndexOf('.') + 2, MaxInt);
  end;
end;

constructor TEventHookScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

function TEventHookScan.ClassRoutines(const AClassName: string): TArray<TSyntaxNode>;
var
  mRoutine: TSyntaxNode;
begin
  Result := nil;
  for mRoutine in FRoutines do
  begin
    if SameText(ClassOf(mRoutine), AClassName) then
    begin
      Result := Result + [mRoutine];
    end;
  end;
end;

/// <summary>Deklariert der Klassenrumpf ABody eine Methode AName?</summary>
function TEventHookScan.HasMethod(ABody: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    if (ABody[mIndex].Kind = TSyntaxKind.RoutineHeader) and SameText(ABody[mIndex].Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Ist AName ein Feld der Klasse außerhalb des published-Teils (Komponenten der Formulardatei gehören dem
/// Formular) und nicht vom Typ Interface?</summary>
function TEventHookScan.ForeignField(ABody: TSyntaxNode; const AClassName, AName: string): Boolean;
var
  mIndex: Integer;
  mPublished: Boolean;
  mNode: TSyntaxNode;
begin
  Result := False;
  // Ohne Sichtbarkeit beginnt eine Klasse published (bei Formularen, Frames und Datenmodulen die Komponenten).
  mPublished := True;
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    mNode := ABody[mIndex];
    if mNode.Kind = TSyntaxKind.Visibility then
    begin
      mPublished := SameText(mNode.Name, 'published');
    end
    else if (mNode.Kind = TSyntaxKind.Field) and SameText(mNode.Name, AName) then
    begin
      Exit(not mPublished and TakesField(AClassName, AName));
    end;
  end;
end;

/// <summary>Ist AName ein Parameter der Routine ARoutine?</summary>
function IsParameter(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  mParameters: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mParameters := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mParameters <> nil then
  begin
    mParameters := mParameters.FindChild(TSyntaxKind.Parameters);
  end;
  if mParameters <> nil then
  begin
    for mIndex := 0 to mParameters.ChildCount - 1 do
    begin
      Result := Result or MatchText(AName, mParameters[mIndex].Name.Replace(' ', '').Split([',']));
    end;
  end;
end;

/// <summary>Übernimmt eine Methode der Klasse das Feld aus einem Parameter (FFeld := AQuelle) und erzeugt es keine
/// selbst (FFeld := T.Create…)? Nur dann gehört das Objekt sicher jemand anderem; Felder aus Hilfsfunktionen
/// (FKnopf := AddButton(…)) sind meist eigene Steuerelemente.</summary>
function TEventHookScan.TakesField(const AClassName, AName: string): Boolean;
var
  mRoutine: TSyntaxNode;
  mCreated, mTaken: Boolean;
begin
  mCreated := False;
  mTaken := False;
  for mRoutine in ClassRoutines(AClassName) do
  begin
    mRoutine.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        mValue: TSyntaxNode;
      begin
        if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount > 1) and
          SameText(ANode[0].Name, AName) and (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
        begin
          mValue := ANode[1];
          mTaken := mTaken or ((mValue.Kind = TSyntaxKind.Identifier) and IsParameter(mRoutine, mValue.Name));
          if mValue.Kind = TSyntaxKind.Call then
          begin
            mValue := mValue[0];
          end;
          mCreated := mCreated or ((mValue.Kind = TSyntaxKind.MemberAccess) and StartsText('Create', mValue.Name));
        end;
        Result := not mCreated;
      end);
  end;
  Result := mTaken and not mCreated;
end;

/// <summary>Setzt Destroy, BeforeDestruction oder Notification der Klasse ein Ereignis AEventName (an irgendeinem
/// Objekt) zurück?</summary>
function TEventHookScan.ResetsEvent(const AClassName, AEventName: string): Boolean;
var
  mRoutine: TSyntaxNode;
  mFound: Boolean;
begin
  mFound := False;
  for mRoutine in ClassRoutines(AClassName) do
  begin
    if MatchText(MethodOf(mRoutine), cTeardownMethods) then
    begin
      mRoutine.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          mFound := mFound or ((ANode.Kind = TSyntaxKind.AssignStatement) and (ANode[0].Kind =
            TSyntaxKind.MemberAccess) and SameText(ANode[0].Name, AEventName));
          Result := not mFound;
        end);
    end;
  end;
  Result := mFound;
end;

/// <summary>Ist AStatement eine Zuweisung Fremd.OnXyz := Methode an ein fremdes Objekt (Parameter der Routine oder
/// Feld ohne eigenes Create)?</summary>
function TEventHookScan.HookAt(ARoutine, AStatement: TSyntaxNode; out AHook: THook): Boolean;
var
  mTarget, mValue, mBody: TSyntaxNode;
begin
  Result := False;
  AHook := Default(THook);
  if (AStatement.ChildCount < 2) or (AStatement[0].Kind <> TSyntaxKind.MemberAccess) or
    not TEventAssignments.IsEventName(AStatement[0].Name) then
  begin
    Exit;
  end;
  mTarget := AStatement[0];
  mValue := AStatement[1];
  if (mTarget.ChildCount = 0) or (mTarget[0].Kind <> TSyntaxKind.Identifier) or SameText(mTarget[0].Name, 'Self') then
  begin
    Exit;
  end;
  // Rechts eine eigene Methode: Name oder Self.Name.
  if (mValue.Kind = TSyntaxKind.MemberAccess) and (mValue.ChildCount > 0) and SameText(mValue[0].Name, 'Self') then
  begin
    AHook.Handler := mValue.Name;
  end
  else if mValue.Kind = TSyntaxKind.Identifier then
  begin
    AHook.Handler := mValue.Name;
  end;
  AHook.ClassName := ClassOf(ARoutine);
  mBody := TRoutineBody.TypeBody(FContext.Tree.Root, AHook.ClassName);
  if (AHook.Handler = '') or (mBody = nil) or not HasMethod(mBody, AHook.Handler) then
  begin
    Exit;
  end;
  AHook.Statement := AStatement;
  AHook.ObjectName := mTarget[0].Name;
  AHook.EventName := mTarget.Name;
  AHook.IsField := ForeignField(mBody, AHook.ClassName, AHook.ObjectName);
  Result := AHook.IsField or IsParameter(ARoutine, AHook.ObjectName);
end;

/// <summary>"if Assigned(FFeld) then FFeld.OnXyz := nil;" am Anfang des Destruktors der Datei.</summary>
function TEventHookScan.UnhookFix(const AHook: THook; out AFix: TRuleFix): Boolean;
var
  mRoutine, mBlock: TSyntaxNode;
  mIndent, mUnit, mText: string;
begin
  Result := False;
  if not AHook.IsField then
  begin
    Exit;
  end;
  for mRoutine in ClassRoutines(AHook.ClassName) do
  begin
    mBlock := TRoutineBody.BodyOf(mRoutine);
    if SameText(MethodOf(mRoutine), 'Destroy') and (mBlock <> nil) and (mBlock.StartPos.Line < High(FLines)) and
      SameText(Trim(FLines[mBlock.StartPos.Line]), 'begin') then
    begin
      mIndent := Copy(FLines[mBlock.StartPos.Line], 1, mBlock.StartPos.Character);
      mUnit := TRoutineBody.IndentUnit(FContext.Formatting);
      mText := mIndent + mUnit + 'if Assigned(' + AHook.ObjectName + ') then' + FLineBreak + mIndent + mUnit + mUnit +
        AHook.ObjectName + '.' + AHook.EventName + ' := nil;' + FLineBreak;
      AFix := TRuleFix.Create(cTexts[TMethodReferenceText.Unhook].Fmt([AHook.ObjectName, AHook.EventName]),
        [TTextEdit.Create(TTextRange.Create(mBlock.StartPos.Line + 1, 0, mBlock.StartPos.Line + 1, 0), mText)]);
      Exit(True);
    end;
  end;
end;

procedure TEventHookScan.ReportHook(const AHook: THook);
var
  mFix: TRuleFix;
  mFixes: TArray<TRuleFix>;
begin
  mFixes := nil;
  if UnhookFix(AHook, mFix) then
  begin
    mFixes := [mFix];
  end;
  FReport.Add(TTextRange.Create(AHook.Statement.StartPos, AHook.Statement.EndPos),
    cTexts[TMethodReferenceText.Event].Fmt([AHook.ObjectName, AHook.EventName, AHook.Handler, AHook.ClassName,
    AHook.ObjectName]), TRuleConfidence.Medium, mFixes);
end;

procedure TEventHookScan.CheckRoutine(ARoutine: TSyntaxNode);
var
  mStatements: TArray<TSyntaxNode>;
  mStatement: TSyntaxNode;
  mHook: THook;
begin
  if (ClassOf(ARoutine) = '') or MatchText(MethodOf(ARoutine), cTeardownMethods) then
  begin
    Exit;
  end;
  mStatements := nil;
  ARoutine.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.AssignStatement then
      begin
        mStatements := mStatements + [ANode];
      end;
      Result := not (ANode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.WithStatement]) and
        ((ANode = ARoutine) or (ANode.Kind <> TSyntaxKind.RoutineDecl));
    end);
  for mStatement in mStatements do
  begin
    if HookAt(ARoutine, mStatement, mHook) and not ResetsEvent(mHook.ClassName, mHook.EventName) then
    begin
      ReportHook(mHook);
    end;
  end;
end;

procedure TEventHookScan.Run;
var
  mDerived: IRuleDerivedCache;
  mRoutine: TSyntaxNode;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) or not ContainsText(FContext.Text, '.On') then
  begin
    Exit;
  end;
  mDerived := TRuleDerived.Open(FContext);
  FRoutines := TRuleDerived.Routines(mDerived, FContext);
  FLines := TTextLines.SplitLines(FContext.Text, FLineBreak);
  for mRoutine in FRoutines do
  begin
    CheckRoutine(mRoutine);
  end;
end;

{ TAnonymousMethodSelfCycleRule }

function TAnonymousMethodSelfCycleRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cAnonymousMethodSelfCycleRuleId, TRuleSeverity.Warning,
    cTexts[TMethodReferenceText.CycleTitle].Text);
end;

procedure TAnonymousMethodSelfCycleRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TSelfCycleScan;
begin
  mScan := TSelfCycleScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

{ TEventHandlerNotUnhookedRule }

function TEventHandlerNotUnhookedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cEventHandlerNotUnhookedRuleId, TRuleSeverity.Hint,
    cTexts[TMethodReferenceText.EventTitle].Text);
end;

procedure TEventHandlerNotUnhookedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TEventHookScan;
begin
  mScan := TEventHookScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

procedure RegisterOwnershipMethodReferenceRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TAnonymousMethodSelfCycleRule.Create);
  ARegistry.Register(TEventHandlerNotUnhookedRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Ownership.MethodReferences', cTexts);

end.
