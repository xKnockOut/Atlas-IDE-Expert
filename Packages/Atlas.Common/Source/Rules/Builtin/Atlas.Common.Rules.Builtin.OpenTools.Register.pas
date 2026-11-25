unit Atlas.Common.Rules.Builtin.OpenTools.Register;

// Prüfregel register-does-work (Teil von Atlas.Common.Rules.Builtin.OpenTools, dort registriert): Die Prozedur
// Register eines Packages (bzw. eine Einstiegsroutine aus der Option "entries") startet Arbeit statt nur
// anzumelden: Timer, Thread, Task, Formular, Kindprozess, Netzwerk, Warten. Register läuft beim Start der IDE in
// nicht garantierter Ladereihenfolge der Packages; Arbeit dort verlängert den Start und greift womöglich auf noch
// nicht geladene Packages zu.
//
// Gemeldet wird jeder Aufruf aus "workCalls" und jedes Erzeugen einer Klasse aus "workClasses" (auch ihrer
// Nachfahren) in der Einstiegsroutine und in Routinen der Unit, die nur von dort erreicht werden (freie Routinen
// des implementation-Teils und private Methoden derselben Klasse). Anonyme Methoden laufen später und zählen nicht.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TRegisterDoesWorkRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Passt das Aufrufziel ATarget (Quelltext ohne Leerraum, z. B. TTask.Run oder mForm.ShowModal) zum
/// Muster APattern? Mit Punkt gilt das ganze Ziel, sonst nur der letzte Namensteil; * und ? als Platzhalter.
/// </summary>
function MatchesCallPattern(const ATarget, APattern: string): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Configuration.RuleOptions,
  Atlas.Common.Semantics.Ancestry,
  Atlas.Common.Rules.Builtin.Concurrency.Syntax,
  Atlas.Common.Rules.Builtin.Unused.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen.</summary>
  TRegisterText = (Title, Direct, ViaHelper);

const
  cTexts: array[TRegisterText] of TAtlasText = (
    (De: 'Register startet Arbeit statt nur anzumelden'; En: 'Register starts work instead of only registering'),
    (De: '%0:s startet Arbeit (%1:s). Es läuft beim Start der IDE in ungewisser Reihenfolge der Packages: nur ' +
      'anmelden und den Start in einen Wizard, Notifier bzw. die Feature-Tabelle verlegen.';
     En: '%0:s starts work (%1:s). It runs while the IDE starts, in no guaranteed package order: only register ' +
      'and move the start into a wizard, notifier or the feature table.'),
    (De: '%0:s startet über %2:s Arbeit (%1:s). Es läuft beim Start der IDE in ungewisser Reihenfolge der ' +
      'Packages: nur anmelden und den Start in einen Wizard, Notifier bzw. die Feature-Tabelle verlegen.';
     En: '%0:s starts work through %2:s (%1:s). It runs while the IDE starts, in no guaranteed package order: ' +
      'only register and move the start into a wizard, notifier or the feature table.'));

{$SCOPEDENUMS OFF}

const
  cConstructors: array[0..3] of string = ('Create', 'CreateNew', 'CreateParented', 'CreateFmt');
  /// <summary>Wie oft die Suche nach Hilfsroutinen höchstens nachläuft.</summary>
  cMaxRounds = 16;

function MatchesCallPattern(const ATarget, APattern: string): Boolean;
begin
  if Pos('.', APattern) > 0 then
  begin
    Result := MatchesWildcard(ATarget, APattern);
  end
  else
  begin
    Result := MatchesWildcard(Copy(ATarget, LastDelimiter('.', ATarget) + 1, MaxInt), APattern);
  end;
end;

/// <summary>Vorgabe der Option workCalls.</summary>
function DefaultCalls: TArray<string>;
begin
  Result := TArray<string>.Create('Sleep', 'WaitFor*', 'CreateProcess', 'ShellExecute*', 'Application.CreateForm',
    'ShowModal', 'ShowMessage', 'MessageDlg', 'TTask.Run', 'TThread.CreateAnonymousThread');
end;

/// <summary>Vorgabe der Option workClasses.</summary>
function DefaultClasses: TArray<string>;
begin
  Result := TArray<string>.Create('TTimer', 'TThread', 'TForm', 'THTTPClient', 'TIdHTTP');
end;

/// <summary>Routine auf oberster Ebene des implementation-Teils (keine eingebettete)?</summary>
function IsTopLevel(ARoutine: TSyntaxNode): Boolean;
begin
  Result := (ARoutine.Parent <> nil) and (ARoutine.Parent.Kind = TSyntaxKind.ImplementationSection);
end;

/// <summary>Routine auf oberster Ebene, in der ANode steht; nil außerhalb (initialization usw.).</summary>
function TopRoutineOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  while ANode <> nil do
  begin
    if (ANode.Kind = TSyntaxKind.RoutineDecl) and IsTopLevel(ANode) then
    begin
      Exit(ANode);
    end;
    ANode := ANode.Parent;
  end;
end;

type
  /// <summary>Eine erreichte Routine und die Einstiegsroutine, von der sie kommt.</summary>
  TReached = record
    Routine: TSyntaxNode;
    Entry: string;
  end;

  /// <summary>Ein Lauf der Regel über eine Unit.</summary>
  TRegisterScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FAncestry: TAncestry;
    FRoutines: TArray<TSyntaxNode>;
    FCalls, FClasses, FEntries: TArray<string>;
    FReached: TArray<TReached>;
    function TargetText(ATarget: TSyntaxNode): string;
    function IsEntry(ARoutine: TSyntaxNode): Boolean;
    function IndexOfReached(ARoutine: TSyntaxNode): Integer;
    function IsHidden(ARoutine: TSyntaxNode): Boolean;
    function OnlyFromReached(ARoutine: TSyntaxNode): Boolean;
    function CalledNames(ARoutine: TSyntaxNode): TArray<string>;
    function Callee(ACaller: TSyntaxNode; const AName: string): TSyntaxNode;
    procedure CollectReached;
    function WorkClass(const AClass: string): Boolean;
    function WorkOf(ATarget: TSyntaxNode): string;
    procedure CheckRoutine(const AReached: TReached);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

{ TRegisterScan }

constructor TRegisterScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FRoutines := TRuleDerived.Routines(TRuleDerived.Open(FContext), FContext);
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext));
  FCalls := TRuleOptions.Strings(FContext.Options, 'workCalls', DefaultCalls);
  FClasses := TRuleOptions.Strings(FContext.Options, 'workClasses', DefaultClasses);
  FEntries := TRuleOptions.Strings(FContext.Options, 'entries', ['Register']);
end;

destructor TRegisterScan.Destroy;
begin
  FAncestry.Free;
  FRoutines := nil;
  FReached := nil;
  FCalls := nil;
  FClasses := nil;
  FEntries := nil;
  inherited;
end;

function TRegisterScan.TargetText(ATarget: TSyntaxNode): string;
begin
  Result := StringReplace(SourceText(FContext.Text, ATarget), ' ', '', [rfReplaceAll]);
end;

// Mit Punkt im Muster zählt der ganze Name (TModul.RegisterModule, *.RegisterModule), sonst nur freie Routinen.
function TRegisterScan.IsEntry(ARoutine: TSyntaxNode): Boolean;
var
  mPattern: string;
begin
  for mPattern in FEntries do
  begin
    if ((Pos('.', mPattern) > 0) and MatchesWildcard(ARoutine.Name, mPattern)) or
      ((Pos('.', ARoutine.Name) = 0) and MatchesWildcard(ARoutine.Name, mPattern)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TRegisterScan.IndexOfReached(ARoutine: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FReached) do
  begin
    if FReached[mIndex].Routine = ARoutine then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

// Von außen unsichtbar: freie Routine nur im implementation-Teil, Methode privat.
function TRegisterScan.IsHidden(ARoutine: TSyntaxNode): Boolean;
var
  mSymbol: TIndexSymbol;
  mClass: string;
begin
  mClass := ClassPart(ARoutine.Name);
  for mSymbol in FAncestry.Local.Symbols do
  begin
    if (mClass = '') and (mSymbol.Kind = TIndexSymbolKind.Routine) and (mSymbol.Container = '') and
      SameText(mSymbol.Name, ARoutine.Name) and mSymbol.InInterface then
    begin
      Exit(False);
    end;
    if (mClass <> '') and (mSymbol.Kind = TIndexSymbolKind.Method) and SameText(mSymbol.Container, mClass) and
      SameText(mSymbol.Name, MethodPart(ARoutine.Name)) then
    begin
      Exit(mSymbol.Visibility in [TIndexVisibility.Private, TIndexVisibility.StrictPrivate]);
    end;
  end;
  Result := mClass = '';
end;

// Nennen nur erreichte Routinen (und ARoutine selbst) den Namen von ARoutine?
function TRegisterScan.OnlyFromReached(ARoutine: TSyntaxNode): Boolean;
var
  mName: string;
  mOutside: TSyntaxNode;
begin
  mName := MethodPart(ARoutine.Name);
  mOutside := FContext.Tree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    var
      mOwner: TSyntaxNode;
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and SameText(ANode.Name, mName) then
      begin
        mOwner := TopRoutineOf(ANode);
        if (mOwner <> ARoutine) and ((mOwner = nil) or (IndexOfReached(mOwner) < 0)) then
        begin
          Result := TSyntaxSearchStep.Found;
        end;
      end;
    end);
  Result := mOutside = nil;
end;

// Namen, die ARoutine außerhalb anonymer Methoden aufruft: M, M(…), Self.M, TKlasse.M(…). Als Argument übergebene
// Routinen (ForceQueue(…, AfterStart)) laufen später und zählen nicht.
function TRegisterScan.CalledNames(ARoutine: TSyntaxNode): TArray<string>;
var
  mNames: TArray<string>;
begin
  mNames := nil;
  ARoutine.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind in [TSyntaxKind.Call, TSyntaxKind.CallStatement]) and (ANode.ChildCount > 0) and
        (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and (ANode[0].Name <> '') and
        not MatchText(ANode[0].Name, mNames) then
      begin
        mNames := mNames + [ANode[0].Name];
      end;
    end);
  Result := mNames;
end;

// Routine der Unit namens AName, die ACaller erreichen kann: freie Routine oder Methode derselben Klasse.
function TRegisterScan.Callee(ACaller: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mRoutine: TSyntaxNode;
  mClass: string;
begin
  mClass := ClassPart(ACaller.Name);
  for mRoutine in FRoutines do
  begin
    if IsTopLevel(mRoutine) and (mRoutine <> ACaller) and
      (SameText(mRoutine.Name, AName) or ((mClass <> '') and SameText(mRoutine.Name, mClass + '.' + AName))) then
    begin
      Exit(mRoutine);
    end;
  end;
  Result := nil;
end;

procedure TRegisterScan.CollectReached;
var
  mRoutine, mCallee: TSyntaxNode;
  mRound, mIndex: Integer;
  mName: string;
  mItem: TReached;
  mChanged: Boolean;
begin
  FReached := nil;
  for mRoutine in FRoutines do
  begin
    if IsTopLevel(mRoutine) and IsEntry(mRoutine) then
    begin
      mItem.Routine := mRoutine;
      mItem.Entry := mRoutine.Name;
      FReached := FReached + [mItem];
    end;
  end;
  mRound := 0;
  mChanged := FReached <> nil;
  while mChanged and (mRound < cMaxRounds) do
  begin
    mChanged := False;
    Inc(mRound);
    for mIndex := 0 to High(FReached) do
    begin
      for mName in CalledNames(FReached[mIndex].Routine) do
      begin
        mCallee := Callee(FReached[mIndex].Routine, mName);
        if (mCallee <> nil) and (IndexOfReached(mCallee) < 0) and not IsEntry(mCallee) and IsHidden(mCallee) and
          OnlyFromReached(mCallee) then
        begin
          mItem.Routine := mCallee;
          mItem.Entry := FReached[mIndex].Entry;
          FReached := FReached + [mItem];
          mChanged := True;
        end;
      end;
    end;
  end;
end;

function TRegisterScan.WorkClass(const AClass: string): Boolean;
var
  mPattern: string;
begin
  for mPattern in FClasses do
  begin
    if MatchesWildcard(AClass, mPattern) or ((Pos('*', mPattern) = 0) and (Pos('?', mPattern) = 0) and
      FAncestry.DescendsFrom(AClass, mPattern)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

// Beschreibung der Arbeit, die das Aufrufziel ATarget startet; '' ohne.
function TRegisterScan.WorkOf(ATarget: TSyntaxNode): string;
var
  mText, mPattern: string;
begin
  Result := '';
  if not (ATarget.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
  begin
    Exit;
  end;
  mText := TargetText(ATarget);
  for mPattern in FCalls do
  begin
    if MatchesCallPattern(mText, mPattern) then
    begin
      Exit(mText);
    end;
  end;
  if (ATarget.Kind = TSyntaxKind.MemberAccess) and MatchText(ATarget.Name, cConstructors) and
    (ATarget.ChildCount > 0) and (ATarget[0].Kind = TSyntaxKind.Identifier) and WorkClass(ATarget[0].Name) then
  begin
    Result := mText;
  end;
end;

procedure TRegisterScan.CheckRoutine(const AReached: TReached);
var
  mFound: TArray<TSyntaxNode>;
  mTarget: TSyntaxNode;
  mWork: string;
begin
  mFound := nil;
  AReached.Routine.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind = TSyntaxKind.AnonymousMethod then
      begin
        // Läuft später, nicht in Register.
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind in [TSyntaxKind.Call, TSyntaxKind.CallStatement]) and (ANode.ChildCount > 0) and
        (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
      begin
        mFound := mFound + [ANode[0]];
      end
      else if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
        (ANode[1].Kind = TSyntaxKind.MemberAccess) then
      begin
        // X := TKlasse.Create ohne Klammern.
        mFound := mFound + [ANode[1]];
      end;
    end);
  for mTarget in mFound do
  begin
    mWork := WorkOf(mTarget);
    if mWork = '' then
    begin
      Continue;
    end;
    if AReached.Routine.Name = AReached.Entry then
    begin
      FReport.Add(NodeRange(mTarget), cTexts[TRegisterText.Direct].Fmt([AReached.Entry, mWork]),
        TRuleConfidence.High);
    end
    else
    begin
      FReport.Add(NodeRange(mTarget), cTexts[TRegisterText.ViaHelper].Fmt([AReached.Entry, mWork,
        AReached.Routine.Name]), TRuleConfidence.Medium);
    end;
  end;
end;

procedure TRegisterScan.Run;
var
  mReached: TReached;
begin
  CollectReached;
  for mReached in FReached do
  begin
    CheckRoutine(mReached);
  end;
end;

{ TRegisterDoesWorkRule }

function TRegisterDoesWorkRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('register-does-work', TRuleSeverity.Warning, cTexts[TRegisterText.Title].Text);
end;

procedure TRegisterDoesWorkRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TRegisterScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    (not ContainsText(AContext.Text, 'Register') and (AContext.Options = '')) then
  begin
    Exit;
  end;
  mScan := TRegisterScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.OpenTools.Register', cTexts);

end.
