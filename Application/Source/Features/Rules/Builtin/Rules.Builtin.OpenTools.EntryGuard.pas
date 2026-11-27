unit Rules.Builtin.OpenTools.EntryGuard;

// Prüfregel ota-entry-without-guard (Teil von Rules.Builtin.OpenTools, dort registriert): Eine
// Methode, die die IDE aufruft, kann eine Ausnahme in die IDE durchlassen. Die IDE zeigt sie als Fehlermeldung,
// im schlimmsten Fall bricht sie Speichern oder Laden ab.
//
// Einstiegspunkte sind
//   - die public- und published-Methoden einer Klasse, die (auch über Vorfahren) ein Interface aus der Option
//     "interfaces" implementiert (Vorgabe IOTA*Notifier*, INTA*Notifier*, IOTA*Wizard*, IOTAKeyboardBinding …),
//   - Methoden, die eine solche Klasse an AddKeyBinding bzw. AddMenuCommand übergibt (gebundene Tasten),
//   - in Units eines Packages Methoden, die als OnClick bzw. OnExecute eines TMenuItem oder TAction zugewiesen
//     werden, das die Routine anlegt oder nennt.
//
// Gemeldet wird ein Rumpf, der werfen kann (Aufruf, raise, Umwandlung mit as), außerhalb eines try … except, das
// alle Ausnahmen fängt, und außerhalb einer Schutzroutine aus "guards". Nicht als Wurf zählen eingebaute und
// reine RTL-Routinen, Typumwandlungen, inherited, anonyme Methoden (laufen später) und Aufrufe von Routinen der
// Unit, deren Rumpf selbst nicht werfen kann. Rümpfe, die nur Werte zuweisen (Felder, Result), bleiben still.

interface

uses
  Rules.Contract;

type
  TOtaEntryWithoutGuardRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.RoutineBody,
  Rules.Derived,
  Atlas.Common.Configuration.RuleOptions,
  Atlas.Common.Semantics.Ancestry,
  Rules.Builtin.Concurrency.Syntax,
  Rules.Builtin.Concurrency.ThreadExecute,
  Rules.Builtin.Flow.Shared,
  Rules.Builtin.Unused.Shared,
  Rules.Builtin.OpenTools.Register,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Names,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Projects.Contract.Group;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen.</summary>
  TEntryGuardText = (Title, EscapesCall, EscapesRaise, EscapesAs, WrapGuard, WrapTry);

  /// <summary>Was im Rumpf werfen kann.</summary>
  TEntryRisk = (None, Call, Raising, AsCast);

const
  cTexts: array[TEntryGuardText] of TAtlasText = (
    (De: 'Einstiegspunkt der IDE lässt Ausnahmen durch'; En: 'IDE entry point lets exceptions through'),
    (De: 'Die IDE ruft %0:s auf; eine Ausnahme aus %1:s erreicht die IDE. Den Rumpf in try … except legen oder ' +
      'über eine Schutzroutine laufen lassen.';
     En: 'The IDE calls %0:s; an exception from %1:s reaches the IDE. Put the body into try … except or run it ' +
      'through a guard routine.'),
    (De: 'Die IDE ruft %0:s auf; raise erreicht die IDE. Den Rumpf in try … except legen oder über eine ' +
      'Schutzroutine laufen lassen.';
     En: 'The IDE calls %0:s; raise reaches the IDE. Put the body into try … except or run it through a guard ' +
      'routine.'),
    (De: 'Die IDE ruft %0:s auf; eine fehlschlagende Umwandlung mit as erreicht die IDE. Den Rumpf in try … except ' +
      'legen oder über eine Schutzroutine laufen lassen.';
     En: 'The IDE calls %0:s; a failing cast with as reaches the IDE. Put the body into try … except or run it ' +
      'through a guard routine.'),
    (De: 'Rumpf über %s laufen lassen'; En: 'Run the body through %s'),
    (De: 'Rumpf in try … except mit Meldung über %s einschließen';
     En: 'Wrap the body in try … except with a message via %s'));

{$SCOPEDENUMS OFF}

const
  /// <summary>Eingebaute und reine RTL-Routinen, die nicht werfen (Typen, Zeichenketten, Mengen).</summary>
  cSafeRoutines: array[0..39] of string = ('Exit', 'Break', 'Continue', 'Assigned', 'Length', 'High', 'Low',
    'SizeOf', 'Ord', 'Chr', 'Inc', 'Dec', 'Include', 'Exclude', 'Succ', 'Pred', 'Odd', 'Abs', 'Default', 'Supports',
    'Min', 'Max', 'SameText', 'SameStr', 'CompareText', 'CompareStr', 'Pos', 'Copy', 'LowerCase', 'UpperCase',
    'Trim', 'TrimLeft', 'TrimRight', 'IntToStr', 'BoolToStr', 'StartsText', 'EndsText', 'ContainsText',
    'ExtractFileName', 'ExtractFileExt');
  /// <summary>Einfache Typen für Umwandlungen T(x).</summary>
  cCastTypes: array[0..9] of string = ('string', 'Pointer', 'TObject', 'NativeInt', 'NativeUInt', 'Integer',
    'Cardinal', 'Boolean', 'Byte', 'Word');
  cBindings: array[0..1] of string = ('AddKeyBinding', 'AddMenuCommand');
  cMenuEvents: array[0..1] of string = ('OnClick', 'OnExecute');
  cMenuClasses: array[0..1] of string = ('TMenuItem', 'TAction');
  /// <summary>Namen, über die eine Unit Menüeinträge in die IDE hängt (Hauptmenü über INTAServices, Editor- und
  /// Projektmenü). MainMenu und TMainMenu allein zählen nicht: Jede VCL-Anwendung hat ein Hauptmenü, auch ein
  /// Laufzeit-Package, das es baut (BuildMainMenu(AMenu: TMainMenu)).</summary>
  cIdeMenuHooks: array[0..4] of string = ('INTAServices', 'AddActionMenu', 'GetEditorLocalMenu', 'EditorLocalMenu',
    'IOTAProjectManagerMenu');
  /// <summary>Wie tief die Regel Aufrufen von Routinen der Unit folgt.</summary>
  cMaxDepth = 4;

/// <summary>Vorgabe der Option interfaces.</summary>
function DefaultInterfaces: TArray<string>;
begin
  Result := TArray<string>.Create('IOTA*Notifier*', 'INTA*Notifier*', 'IOTA*Wizard*', 'IOTAKeyboardBinding',
    'INTACustomDrawMessage', 'IOTALocalMenu', 'IOTAProjectManagerMenu');
end;

/// <summary>Text vor einer Klammer, ohne Leerraum: TAtlasGuard.Run(TAtlasFeature.Menu, → TAtlasGuard.Run.</summary>
function GuardName(const AGuard: string): string;
begin
  Result := AGuard;
  if Pos('(', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('(', Result) - 1);
  end;
  Result := StringReplace(Result, ' ', '', [rfReplaceAll]);
end;

type
  /// <summary>Ein Lauf der Regel über eine Unit.</summary>
  TEntryGuardScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FAncestry: TAncestry;
    FRoutines: TArray<TSyntaxNode>;
    FGuards, FInterfaces: TArray<string>;
    /// <summary>Einstiegspunkte als Klasse.Methode.</summary>
    FEntries: TArray<string>;
    /// <summary>Routinen der Unit, deren Rumpf werfen kann (True) bzw. nicht (False); in Arbeit gilt als sicher.
    /// </summary>
    FThrows: TDictionary<TSyntaxNode, Boolean>;
    FRisk: TEntryRisk;
    FRiskText: string;
    /// <summary>Aufrufe übergehen (Rumpf nur aus Zuweisungen: nur raise und as zählen).</summary>
    FIgnoreCalls: Boolean;
    function TargetText(ATarget: TSyntaxNode): string;
    function ClassSymbol(const AClass: string; out AType: TSymbolLocation): Boolean;
    function ImplementsEntryInterface(const AClass: string): Boolean;
    function PublicMethods(const AClass: string): TArray<string>;
    procedure AddBindings(ARoutine: TSyntaxNode);
    procedure AddMenuHandlers(ARoutine: TSyntaxNode);
    function HooksIdeMenu: Boolean;
    procedure CollectEntries;
    function IsGuardCall(ATarget: TSyntaxNode): Boolean;
    function IsCast(ATarget: TSyntaxNode): Boolean;
    function UnitRoutine(ACaller: TSyntaxNode; ATarget: TSyntaxNode): TSyntaxNode;
    function CalleeThrows(ACaller, ATarget: TSyntaxNode; ADepth: Integer): Boolean;
    function SafeTarget(ACaller, ATarget: TSyntaxNode; ADepth: Integer): Boolean;
    class function HandlerRaises(AExcept: TSyntaxNode): Boolean; static;
    function TryStep(ATry: TSyntaxNode; var ARisk: TEntryRisk): TSyntaxSearchStep;
    function CallStep(ACaller, ACall: TSyntaxNode; ADepth: Integer; var ARisk: TEntryRisk;
      var AText: string): TSyntaxSearchStep;
    function FindRisk(ACaller, ANode: TSyntaxNode; ADepth: Integer): TSyntaxNode;
    function OnlyAssigns(ABody: TSyntaxNode): Boolean;
    function LoggerField(const AClass: string): string;
    function CanWrap(ARoutine: TSyntaxNode): Boolean;
    function GuardFix(ARoutine, ABody: TSyntaxNode): TArray<TRuleFix>;
    function Fixes(ARoutine, ABody: TSyntaxNode): TArray<TRuleFix>;
    procedure CheckEntry(ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

{ TEntryGuardScan }

constructor TEntryGuardScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FRoutines := TRuleDerived.Routines(TRuleDerived.Open(FContext), FContext);
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext));
  FGuards := TRuleOptions.Strings(FContext.Options, 'guards', []);
  FInterfaces := TRuleOptions.Strings(FContext.Options, 'interfaces', DefaultInterfaces);
  FThrows := TDictionary<TSyntaxNode, Boolean>.Create;
end;

destructor TEntryGuardScan.Destroy;
begin
  FThrows.Free;
  FAncestry.Free;
  FRoutines := nil;
  FGuards := nil;
  FInterfaces := nil;
  FEntries := nil;
  FRiskText := '';
  inherited;
end;

function TEntryGuardScan.TargetText(ATarget: TSyntaxNode): string;
begin
  Result := StringReplace(SourceText(FContext.Text, ATarget), ' ', '', [rfReplaceAll]);
end;

// Klasse AClass dieser Unit, auch eingebettet (TAußen.TInnen).
function TEntryGuardScan.ClassSymbol(const AClass: string; out AType: TSymbolLocation): Boolean;
begin
  if Pos('.', AClass) > 0 then
  begin
    Result := FAncestry.FindNestedType(ClassPart(AClass), MethodPart(AClass), AType);
  end
  else
  begin
    Result := FAncestry.FindClass(AClass, AType);
  end;
end;

function TEntryGuardScan.ImplementsEntryInterface(const AClass: string): Boolean;
var
  mType, mStep: TSymbolLocation;
  mChain: TArray<TSymbolLocation>;
  mComplete, mMissing: Boolean;
  mAncestor, mPattern: string;
begin
  Result := False;
  if not ClassSymbol(AClass, mType) then
  begin
    Exit;
  end;
  mChain := TArray<TSymbolLocation>.Create(mType) + FAncestry.Ancestors(mType, mComplete, mMissing);
  for mStep in mChain do
  begin
    for mAncestor in mStep.Symbol.Ancestors do
    begin
      for mPattern in FInterfaces do
      begin
        if MatchesWildcard(TTextNames.BareTypeName(mAncestor), mPattern) then
        begin
          Exit(True);
        end;
      end;
    end;
  end;
end;

// Nur die Deklarationen in der Klasse zählen: Die Symbole der Methodenrümpfe tragen keine Sichtbarkeit.
function TEntryGuardScan.PublicMethods(const AClass: string): TArray<string>;
var
  mType: TSymbolLocation;
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  if not ClassSymbol(AClass, mType) then
  begin
    Exit;
  end;
  for mSymbol in FAncestry.Local.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Method) and SameText(mSymbol.Container, ShortName(AClass)) and
      (mSymbol.Visibility in [TIndexVisibility.Public, TIndexVisibility.Published]) and
      mType.Symbol.Range.Contains(mSymbol.SelectionRange.StartPos) and not SameText(mSymbol.Name, 'Destroy') then
    begin
      Result := Result + [AClass + '.' + mSymbol.Name];
    end;
  end;
end;

// Methoden der eigenen Klasse, die ARoutine an AddKeyBinding bzw. AddMenuCommand übergibt.
procedure TEntryGuardScan.AddBindings(ARoutine: TSyntaxNode);
var
  mClass: string;
  mFound: TArray<string>;
  mName: string;
begin
  mClass := ClassPart(ARoutine.Name);
  mFound := nil;
  ARoutine.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mIndex: Integer;
    begin
      Result := True;
      if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 1) and
        MatchText(ShortName(TargetText(ANode[0])), cBindings) then
      begin
        for mIndex := 1 to ANode.ChildCount - 1 do
        begin
          if ANode[mIndex].Kind = TSyntaxKind.Identifier then
          begin
            mFound := mFound + [mClass + '.' + ANode[mIndex].Name];
          end;
        end;
      end;
    end);
  for mName in mFound do
  begin
    if not MatchText(mName, FEntries) then
    begin
      FEntries := FEntries + [mName];
    end;
  end;
end;

// In Packages: Methoden, die ARoutine einem OnClick/OnExecute zuweist, wenn sie TMenuItem oder TAction nennt.
procedure TEntryGuardScan.AddMenuHandlers(ARoutine: TSyntaxNode);
var
  mClass: string;
  mNamesMenu: Boolean;
  mFound: TArray<string>;
  mName: string;
begin
  mClass := ClassPart(ARoutine.Name);
  mNamesMenu := ARoutine.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.TypeReference]) and
        MatchText(ShortName(ANode.Name), cMenuClasses) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
  if not mNamesMenu then
  begin
    Exit;
  end;
  mFound := nil;
  ARoutine.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mValue: string;
    begin
      Result := True;
      if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
        (ANode[0].Kind = TSyntaxKind.MemberAccess) and MatchText(ANode[0].Name, cMenuEvents) then
      begin
        mValue := VariableName(ANode[1]);
        if mValue <> '' then
        begin
          mFound := mFound + [mValue];
        end;
      end;
    end);
  for mName in mFound do
  begin
    if (mClass <> '') and not MatchText(mClass + '.' + mName, FEntries) then
    begin
      FEntries := FEntries + [mClass + '.' + mName];
    end;
  end;
end;

// Hängt die Unit Menüeinträge in die IDE? Handler eigener Kontextmenüs fängt die Anwendung wie gewohnt.
function TEntryGuardScan.HooksIdeMenu: Boolean;
var
  mRoutine: TSyntaxNode;
begin
  for mRoutine in FRoutines do
  begin
    if mRoutine.Search(
      function(ANode: TSyntaxNode): TSyntaxSearchStep
      begin
        Result := TSyntaxSearchStep.Descend;
        if (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.TypeReference, TSyntaxKind.MemberAccess]) and
          MatchText(ShortName(ANode.Name), cIdeMenuHooks) then
        begin
          Result := TSyntaxSearchStep.Found;
        end;
      end) <> nil then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TEntryGuardScan.CollectEntries;
var
  mRoutine: TSyntaxNode;
  mClass, mName: string;
  mClasses: TArray<string>;
  mPackage: Boolean;
begin
  FEntries := nil;
  mClasses := nil;
  mPackage := (FContext.Application = TApplicationKind.Package) and HooksIdeMenu;
  for mRoutine in FRoutines do
  begin
    mClass := ClassPart(mRoutine.Name);
    if mClass = '' then
    begin
      Continue;
    end;
    if not MatchText(mClass, mClasses) then
    begin
      mClasses := mClasses + [mClass];
      if ImplementsEntryInterface(mClass) then
      begin
        for mName in PublicMethods(mClass) do
        begin
          FEntries := FEntries + [mName];
        end;
      end;
    end;
    if MatchText(mRoutine.Name, FEntries) then
    begin
      AddBindings(mRoutine);
    end;
    if mPackage then
    begin
      AddMenuHandlers(mRoutine);
    end;
  end;
end;

function TEntryGuardScan.IsGuardCall(ATarget: TSyntaxNode): Boolean;
var
  mText, mGuard: string;
begin
  mText := TargetText(ATarget);
  for mGuard in FGuards do
  begin
    if (GuardName(mGuard) <> '') and MatchesCallPattern(mText, GuardName(mGuard)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

// Name nach der Typkonvention (TMenuItem, IOTAModule): Ohne Quelltext der VCL kennt der Index den Typ nicht.
function TypeLikeName(const AName: string): Boolean;
begin
  Result := (Length(AName) > 2) and CharInSet(AName[1], ['T', 'I']) and CharInSet(AName[2], ['A'..'Z']) and
    (Pos('.', AName) = 0);
end;

// T(x): Typumwandlung mit einem eingebauten Typ, einem Typ der Datei bzw. des Index oder einem Typnamen.
function TEntryGuardScan.IsCast(ATarget: TSyntaxNode): Boolean;
begin
  Result := (ATarget.Kind = TSyntaxKind.Identifier) and (ATarget.Parent <> nil) and
    (ATarget.Parent.ChildCount = 2) and (MatchText(ATarget.Name, cCastTypes) or TypeLikeName(ATarget.Name) or
    FAncestry.IsDeclaredType(ATarget.Name) or FAncestry.IsTypeAlias(ATarget.Name));
end;

// Routine der Unit hinter dem Aufrufziel: freie Routine M oder Methode der Klasse des Aufrufers (M, Self.M).
function TEntryGuardScan.UnitRoutine(ACaller: TSyntaxNode; ATarget: TSyntaxNode): TSyntaxNode;
var
  mRoutine, mTop: TSyntaxNode;
  mClass: string;
begin
  Result := nil;
  if (ATarget.Kind = TSyntaxKind.MemberAccess) and ((ATarget.ChildCount = 0) or
    not ((ATarget[0].Kind = TSyntaxKind.Identifier) and SameText(ATarget[0].Name, 'Self'))) then
  begin
    Exit;
  end;
  mTop := ACaller;
  while (mTop.Parent <> nil) and (mTop.Parent.Kind <> TSyntaxKind.ImplementationSection) do
  begin
    mTop := mTop.Parent;
  end;
  mClass := ClassPart(mTop.Name);
  for mRoutine in FRoutines do
  begin
    if (mRoutine.Parent <> nil) and ((mRoutine.Parent.Kind = TSyntaxKind.ImplementationSection) or
      (mRoutine.Parent = ACaller)) and (SameText(mRoutine.Name, ATarget.Name) or
      ((mClass <> '') and SameText(mRoutine.Name, mClass + '.' + ATarget.Name))) then
    begin
      Exit(mRoutine);
    end;
  end;
end;

function TEntryGuardScan.CalleeThrows(ACaller, ATarget: TSyntaxNode; ADepth: Integer): Boolean;
var
  mCallee, mBody: TSyntaxNode;
begin
  mCallee := UnitRoutine(ACaller, ATarget);
  if (mCallee = nil) or (ADepth >= cMaxDepth) then
  begin
    Exit(True);
  end;
  if FThrows.TryGetValue(mCallee, Result) then
  begin
    Exit;
  end;
  // Rekursion: in Arbeit gilt als sicher, der Rumpf entscheidet.
  FThrows.Add(mCallee, False);
  mBody := mCallee.FindChild(TSyntaxKind.Block);
  Result := (mBody = nil) or (FindRisk(mCallee, mBody, ADepth + 1) <> nil);
  FThrows[mCallee] := Result;
end;

function TEntryGuardScan.SafeTarget(ACaller, ATarget: TSyntaxNode; ADepth: Integer): Boolean;
begin
  case ATarget.Kind of
    TSyntaxKind.InheritedExpr:
      Result := True;
    TSyntaxKind.Identifier, TSyntaxKind.MemberAccess:
      Result := MatchText(ATarget.Name, cSafeRoutines) or IsCast(ATarget) or
        not CalleeThrows(ACaller, ATarget, ADepth);
  else
    Result := False;
  end;
end;

// Löst der except-Teil AExcept selbst wieder aus (raise, auch raise;)?
class function TEntryGuardScan.HandlerRaises(AExcept: TSyntaxNode): Boolean;
begin
  Result := AExcept.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if ANode.Kind = TSyntaxKind.RaiseStatement then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

// Schritt der Suche an einem try: Fängt es jede Ausnahme, ist sein Inhalt geschützt; nur ein raise im Handler
// erreicht die IDE.
function TEntryGuardScan.TryStep(ATry: TSyntaxNode; var ARisk: TEntryRisk): TSyntaxSearchStep;
var
  mExcept: TSyntaxNode;
begin
  Result := TSyntaxSearchStep.Descend;
  if not CatchesAll(ATry) then
  begin
    Exit;
  end;
  mExcept := ATry.FindChild(TSyntaxKind.ExceptBlock);
  if (mExcept <> nil) and HandlerRaises(mExcept) then
  begin
    ARisk := TEntryRisk.Raising;
    Result := TSyntaxSearchStep.Found;
  end
  else
  begin
    Result := TSyntaxSearchStep.Skip;
  end;
end;

// Schritt der Suche an einem Aufruf: Schutzroutinen übergehen, sichere Ziele weitersuchen, sonst gefunden.
function TEntryGuardScan.CallStep(ACaller, ACall: TSyntaxNode; ADepth: Integer; var ARisk: TEntryRisk;
  var AText: string): TSyntaxSearchStep;
begin
  Result := TSyntaxSearchStep.Descend;
  if (ACall.ChildCount = 0) or FIgnoreCalls or
    ((ACall.Kind = TSyntaxKind.CallStatement) and (ACall[0].Kind = TSyntaxKind.Call)) then
  begin
    // Bei CallStatement um einen Call ist der Aufruf selbst das Kind.
    Exit;
  end;
  if IsGuardCall(ACall[0]) then
  begin
    Result := TSyntaxSearchStep.Skip;
  end
  else if not SafeTarget(ACaller, ACall[0], ADepth) then
  begin
    ARisk := TEntryRisk.Call;
    AText := TargetText(ACall[0]);
    Result := TSyntaxSearchStep.Found;
  end;
end;

// Erster Knoten unter ANode, der werfen kann; nil ohne. Setzt FRisk und FRiskText.
function TEntryGuardScan.FindRisk(ACaller, ANode: TSyntaxNode; ADepth: Integer): TSyntaxNode;
var
  mRisk: TEntryRisk;
  mText: string;
begin
  mRisk := TEntryRisk.None;
  mText := '';
  Result := ANode.Search(
    function(AItem: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      case AItem.Kind of
        TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl, TSyntaxKind.VarSection, TSyntaxKind.ConstSection,
        TSyntaxKind.TypeSection:
          if AItem <> ANode then
          begin
            Result := TSyntaxSearchStep.Skip;
          end;
        TSyntaxKind.RaiseStatement:
          begin
            mRisk := TEntryRisk.Raising;
            Result := TSyntaxSearchStep.Found;
          end;
        TSyntaxKind.BinaryExpr:
          if SameText(AItem.Name, 'as') then
          begin
            mRisk := TEntryRisk.AsCast;
            Result := TSyntaxSearchStep.Found;
          end;
        TSyntaxKind.TryStatement:
          Result := TryStep(AItem, mRisk);
        TSyntaxKind.Call, TSyntaxKind.CallStatement:
          Result := CallStep(ACaller, AItem, ADepth, mRisk, mText);
      end;
    end);
  if (Result <> nil) and (ADepth = 0) then
  begin
    FRisk := mRisk;
    FRiskText := mText;
  end;
end;

// Besteht der Rumpf nur aus Zuweisungen (Felder setzen, Wert zurückgeben) und ist das gefundene Risiko ein Aufruf?
// Dann zählen nur raise und as.
function TEntryGuardScan.OnlyAssigns(ABody: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    if not (ABody[mIndex].Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.EmptyStatement]) then
    begin
      Exit(False);
    end;
  end;
  Result := FRisk = TEntryRisk.Call;
end;

/// <summary>Name eines Felds vom Typ ILogger der Klasse; '' ohne.</summary>
function TEntryGuardScan.LoggerField(const AClass: string): string;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FAncestry.Local.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, ShortName(AClass)) and
      SameText(ShortName(mSymbol.TypeName), 'ILogger') then
    begin
      Exit(mSymbol.Name);
    end;
  end;
  Result := '';
end;

// Lässt sich der Rumpf in eine anonyme Methode legen? Nicht mit Result, var- und out-Parametern (nicht
// einfangbar) und inherited.
function TEntryGuardScan.CanWrap(ARoutine: TSyntaxNode): Boolean;
var
  mBlocked: TArray<string>;
  mBody: TSyntaxNode;
begin
  mBlocked := ['Result'];
  ARoutine.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := ANode.Kind <> TSyntaxKind.Block;
      if (ANode.Kind = TSyntaxKind.Parameter) and (ANode.Modifier in [TParameterModifier.VarParam,
        TParameterModifier.OutParam]) then
      begin
        mBlocked := mBlocked + [ANode.Name];
      end;
    end);
  mBody := ARoutine.FindChild(TSyntaxKind.Block);
  Result := (mBody <> nil) and (mBody.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.InheritedExpr) or ((ANode.Kind = TSyntaxKind.Identifier) and
        MatchText(ANode.Name, mBlocked)) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) = nil);
end;

// Korrektur: Rumpf als anonyme Methode an die erste Schutzroutine übergeben.
function TEntryGuardScan.GuardFix(ARoutine, ABody: TSyntaxNode): TArray<TRuleFix>;
var
  mLines: TArray<string>;
  mLineBreak, mIndent, mStep, mPrefix, mText: string;
  mLine: Integer;
begin
  Result := nil;
  if (Length(FGuards) = 0) or (GuardName(FGuards[0]) = '') or (ABody.EndPos.Line - ABody.StartPos.Line < 2) or
    not CanWrap(ARoutine) then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(FContext.Text, mLineBreak);
  if (Trim(mLines[ABody.StartPos.Line]) <> 'begin') or not MatchText(Trim(mLines[ABody.EndPos.Line]),
    ['end;', 'end']) then
  begin
    Exit;
  end;
  mPrefix := TrimRight(FGuards[0]);
  if Pos('(', mPrefix) = 0 then
  begin
    mPrefix := mPrefix + '(';
  end;
  mIndent := TTextLines.IndentOf(mLines[ABody.StartPos.Line]);
  mStep := TRoutineBody.IndentUnit(FContext.Formatting);
  mText := mIndent + mStep + mPrefix + mLineBreak + mIndent + mStep + mStep + 'procedure' + mLineBreak +
    mIndent + mStep + mStep + 'begin' + mLineBreak;
  for mLine := ABody.StartPos.Line + 1 to ABody.EndPos.Line - 1 do
  begin
    if Trim(mLines[mLine]) = '' then
    begin
      mText := mText + mLines[mLine] + mLineBreak;
    end
    else
    begin
      mText := mText + mStep + mStep + mLines[mLine] + mLineBreak;
    end;
  end;
  mText := mText + mIndent + mStep + mStep + 'end);' + mLineBreak;
  Result := [TRuleFix.Create(cTexts[TEntryGuardText.WrapGuard].Fmt([GuardName(FGuards[0])]),
    [TTextEdit.Create(TTextRange.Create(ABody.StartPos.Line + 1, 0, ABody.EndPos.Line, 0), mText)])];
end;

function TEntryGuardScan.Fixes(ARoutine, ABody: TSyntaxNode): TArray<TRuleFix>;
var
  mLogger: string;
  mEdits: TArray<TTextEdit>;
begin
  Result := GuardFix(ARoutine, ABody);
  mLogger := LoggerField(ClassPart(ARoutine.Name));
  if TryExceptEdits(FContext, ABody, mLogger, MethodPart(ARoutine.Name), mEdits) then
  begin
    Result := Result + [TRuleFix.Create(cTexts[TEntryGuardText.WrapTry].Fmt([mLogger]), mEdits)];
  end;
end;

procedure TEntryGuardScan.CheckEntry(ARoutine: TSyntaxNode);
var
  mBody, mRisk: TSyntaxNode;
  mName: string;
begin
  mBody := ARoutine.FindChild(TSyntaxKind.Block);
  if mBody = nil then
  begin
    Exit;
  end;
  FRisk := TEntryRisk.None;
  mRisk := FindRisk(ARoutine, mBody, 0);
  if (mRisk <> nil) and OnlyAssigns(mBody) then
  begin
    FIgnoreCalls := True;
    try
      mRisk := FindRisk(ARoutine, mBody, 0);
    finally
      FIgnoreCalls := False;
    end;
  end;
  if mRisk = nil then
  begin
    Exit;
  end;
  mName := MethodPart(ARoutine.Name);
  case FRisk of
    TEntryRisk.Raising:
      FReport.Add(HeaderNameRange(FContext, ARoutine), cTexts[TEntryGuardText.EscapesRaise].Fmt([mName]),
        TRuleConfidence.High, Fixes(ARoutine, mBody));
    TEntryRisk.AsCast:
      FReport.Add(HeaderNameRange(FContext, ARoutine), cTexts[TEntryGuardText.EscapesAs].Fmt([mName]),
        TRuleConfidence.High, Fixes(ARoutine, mBody));
  else
    FReport.Add(HeaderNameRange(FContext, ARoutine), cTexts[TEntryGuardText.EscapesCall].Fmt([mName, FRiskText]),
      TRuleConfidence.High, Fixes(ARoutine, mBody));
  end;
end;

procedure TEntryGuardScan.Run;
var
  mRoutine: TSyntaxNode;
begin
  CollectEntries;
  if FEntries = nil then
  begin
    Exit;
  end;
  for mRoutine in FRoutines do
  begin
    if (mRoutine.Parent <> nil) and (mRoutine.Parent.Kind = TSyntaxKind.ImplementationSection) and
      MatchText(mRoutine.Name, FEntries) then
    begin
      CheckEntry(mRoutine);
    end;
  end;
end;

{ TOtaEntryWithoutGuardRule }

function TOtaEntryWithoutGuardRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('ota-entry-without-guard', TRuleSeverity.Warning,
    cTexts[TEntryGuardText.Title].Text);
end;

procedure TOtaEntryWithoutGuardRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TEntryGuardScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mScan := TEntryGuardScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Rules.Builtin.OpenTools.EntryGuard', cTexts);

end.
