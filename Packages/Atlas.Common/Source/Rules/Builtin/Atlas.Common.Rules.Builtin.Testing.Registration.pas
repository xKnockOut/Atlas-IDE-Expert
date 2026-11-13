unit Atlas.Common.Rules.Builtin.Testing.Registration;

// Regel aus Atlas.Common.Rules.Builtin.Testing (#1882); angemeldet wird sie dort:
//   dunitx-fixture-not-registered  Testklasse, die DUnitX nie zu sehen bekommt: Ihre Tests fehlen still.
//     1. Nicht registriert: DUnitX findet Testklassen über RegisterTestFixture oder, wenn der Runner der .dpr
//        UseRTTI := True setzt (Vorlage von DUnitX), über das Attribut [TestFixture]. Gemeldet wird eine Klasse
//        mit [Test]-/[TestCase]-Methoden, die weder initialization der Unit noch eine Routine der Unit, die von
//        dort aufgerufen wird, nennt (TDUnitX.RegisterTestFixture(TKlasse), eigene Helfer wie Registriere([TA,
//        TB])) und keine andere Unit ihrer Projekte nennt, und die außerdem kein [TestFixture] hat oder in einem
//        Projekt steht, dessen .dpr einen Runner ohne UseRTTI := True anlegt. Ein Aufruf aus der Option
//        registrationCalls in initialization zählt für alle Klassen der Unit. Generische und abstrakte Klassen
//        sowie Vorfahren anderer Klassen der Datei bleiben still. Korrekturen: TDUnitX.RegisterTestFixture(TKlasse);
//        in initialization ergänzen bzw. den Abschnitt anlegen; bei Projekten mit RTTI auch [TestFixture] davor.
//     2. Unit in keinem Testprojekt: Die Gruppe hat Testprojekte, aber keines enthält die Unit. Korrektur bei
//        genau einem Testprojekt: Unit in uses der .dpr und als DCCReference in die .dproj eintragen.
//   Nur in Testunits und nur mit den Projekten der Gruppe; ohne sie schweigt die Regel.

interface

uses
  Atlas.Common.Rules.Contract;

const
  cDUnitXFixtureNotRegisteredRuleId = 'dunitx-fixture-not-registered';

type
  TDUnitXFixtureNotRegisteredRule = class(TInterfacedObject, IRule)
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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Testing.Classes,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TRegistrationText = (Title, NotRegistered, NoAttribute, Register, AddAttribute, NotInProject, AddToProject);

const
  cTexts: array[TRegistrationText] of TAtlasText = (
    (De: 'DUnitX-Testklasse nie registriert'; En: 'DUnitX fixture never registered'),
    (De: '%s wird nie registriert: DUnitX kennt die Klasse nicht, ihre Tests laufen nie.';
     En: '%s is never registered: DUnitX does not know the class, its tests never run.'),
    (De: '%s hat weder [TestFixture] noch eine Registrierung: DUnitX findet die Klasse nicht, ihre Tests laufen nie.';
     En: '%s has neither [TestFixture] nor a registration: DUnitX does not find the class, its tests never run.'),
    (De: 'TDUnitX.RegisterTestFixture(%s) in initialization ergänzen';
     En: 'Add TDUnitX.RegisterTestFixture(%s) to initialization'),
    (De: '[TestFixture] ergänzen'; En: 'Add [TestFixture]'),
    (De: 'Die Unit steht in keinem Testprojekt (%s): Ihre Tests laufen nie.';
     En: 'The unit is in no test project (%s): its tests never run.'),
    (De: 'Unit in %s eintragen'; En: 'Add the unit to %s'));

{$SCOPEDENUMS OFF}

const
  cTestAttributes: array[0..2] of string = ('Test', 'TestCase', 'NamedTestCase');

type
  /// <summary>Eine Prüfung einer Datei.</summary>
  TRegistrationCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FLineBreak: string;
    FClasses: TArray<TDUnitXClass>;
    FProjectsKnown: Boolean;
    /// <summary>Findet jeder Runner der Projekte der Unit Testklassen über [TestFixture] (UseRTTI)?</summary>
    FDiscovers: Boolean;
    /// <summary>Gehört die Unit zu einem Projekt der Gruppe?</summary>
    FInProject: Boolean;
    /// <summary>Namen (groß), die initialization und die von dort aufgerufenen Routinen der Unit nennen.</summary>
    FMentioned: TDictionary<string, Boolean>;
    FRegistersAll: Boolean;
    procedure CollectMentions;
    function IsAbstract(const AClass: TDUnitXClass): Boolean;
    function IsAncestorInFile(const AClass: TDUnitXClass): Boolean;
    function IsFixture(const AClass: TDUnitXClass): Boolean;
    function MentionedElsewhere(const AName: string): Boolean;
    function NameRange(const AClass: TDUnitXClass): TTextRange;
    function RegisterFix(const AName: string; out AFix: TRuleFix): Boolean;
    function ProjectFix(const AProject: TRuleProject; out AFix: TRuleFix): Boolean;
    procedure CheckProjects(const AFirst: TDUnitXClass);
    procedure ReadProjects;
    function AttributeFix(const AClass: TDUnitXClass): TRuleFix;
    procedure CheckClass(const AClass: TDUnitXClass);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

/// <summary>Letzter Teil eines Namens (TDUnitX.RegisterTestFixture → RegisterTestFixture).</summary>
function BareName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

/// <summary>Pfad AFile relativ zum Ordner ABaseFile mit \ wie in .dpr und .dproj.</summary>
function RelativeTo(const AFile, ABaseFile: string): string;
begin
  Result := StringReplace(ExtractRelativePath(ExtractFilePath(ABaseFile), AFile), PathDelim, '\', [rfReplaceAll]);
end;

{ TRegistrationCheck }

constructor TRegistrationCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mReason: string;
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FLineBreak := TTextLines.LineBreakOf(AContext.Text);
  FClasses := TDUnitXClasses.Collect(AContext.Tree.Root);
  FProjectsKnown := (AContext.ProjectFiles <> nil) and (AContext.FileName <> '') and
    AContext.ProjectFiles.Complete(mReason);
  FMentioned := TDictionary<string, Boolean>.Create;
end;

destructor TRegistrationCheck.Destroy;
begin
  FMentioned.Free;
  inherited Destroy;
end;

/// <summary>Freie Routinen mit Rumpf unter ASection (nicht in Routinen), Name groß → Knoten.</summary>
procedure CollectRoutines(ASection: TSyntaxNode; ARoutines: TDictionary<string, TSyntaxNode>);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ASection);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.RoutineDecl then
      begin
        if Pos('.', mNode.Name) = 0 then
        begin
          ARoutines.AddOrSetValue(UpperCase(mNode.Name), mNode);
        end;
        Continue;
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

/// <summary>Steht AName (auch mit Klasse oder Unit davor) in ACalls?</summary>
function IsRegistrationCall(const AName: string; const ACalls: TArray<string>): Boolean;
var
  mCall: string;
begin
  for mCall in ACalls do
  begin
    if SameText(BareName(mCall), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TRegistrationCheck.CollectMentions;
var
  mRoutines: TDictionary<string, TSyntaxNode>;
  mPending: TStack<TSyntaxNode>;
  mVisited: TDictionary<TSyntaxNode, Boolean>;
  mNode, mRoutine: TSyntaxNode;
  mIndex: Integer;
  mKey: string;
  mCalls: TArray<string>;
begin
  mCalls := TRuleOptions.Strings(FContext.Options, 'registrationCalls', nil);
  mRoutines := TDictionary<string, TSyntaxNode>.Create;
  mPending := TStack<TSyntaxNode>.Create;
  mVisited := TDictionary<TSyntaxNode, Boolean>.Create;
  try
    for mIndex := 0 to FContext.Tree.Root.ChildCount - 1 do
    begin
      mNode := FContext.Tree.Root[mIndex];
      if mNode.Kind = TSyntaxKind.InitializationSection then
      begin
        mPending.Push(mNode);
      end
      else if mNode.Kind = TSyntaxKind.ImplementationSection then
      begin
        CollectRoutines(mNode, mRoutines);
      end;
    end;
    // Namen in initialization und in den Routinen der Unit, die von dort aus aufgerufen werden.
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
      begin
        mKey := UpperCase(mNode.Name);
        FMentioned.AddOrSetValue(mKey, True);
        FRegistersAll := FRegistersAll or IsRegistrationCall(mNode.Name, mCalls);
        if mRoutines.TryGetValue(mKey, mRoutine) and not mVisited.ContainsKey(mRoutine) then
        begin
          mVisited.Add(mRoutine, True);
          mPending.Push(mRoutine);
        end;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mVisited.Free;
    mPending.Free;
    mRoutines.Free;
  end;
end;

function TRegistrationCheck.IsAbstract(const AClass: TDUnitXClass): Boolean;
var
  mIndex: Integer;
  mToken: TPascalToken;
begin
  // class abstract(TBasis): das Wort steht direkt hinter class.
  mIndex := FContext.Tree.FirstTokenFrom(AClass.Body.StartOffset);
  Result := False;
  if (mIndex >= 0) and (mIndex < High(FContext.Tree.Tokens)) then
  begin
    mToken := FContext.Tree.Tokens[mIndex + 1];
    Result := SameText(mToken.Text, 'abstract');
  end;
end;

function TRegistrationCheck.IsAncestorInFile(const AClass: TDUnitXClass): Boolean;
var
  mOther: TDUnitXClass;
begin
  for mOther in FClasses do
  begin
    if SameText(BareName(mOther.Ancestor), AClass.Name) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TRegistrationCheck.IsFixture(const AClass: TDUnitXClass): Boolean;
begin
  if AClass.IsGeneric or IsAbstract(AClass) or IsAncestorInFile(AClass) then
  begin
    Exit(False);
  end;
  Result := AClass.HasAttribute('TestFixture') or AClass.HasMemberWith(cTestAttributes);
end;

function TRegistrationCheck.MentionedElsewhere(const AName: string): Boolean;
var
  mProject: TRuleProject;
  mSource: string;
begin
  for mProject in FContext.ProjectFiles.ProjectsOf(FContext.FileName, False) do
  begin
    for mSource in mProject.Sources do
    begin
      if not SameText(mSource, FContext.FileName) and
        (FContext.ProjectFiles.NameIn(mSource, AName) <> TRuleNameAnswer.Absent) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TRegistrationCheck.NameRange(const AClass: TDUnitXClass): TTextRange;
var
  mStart: TTextPosition;
begin
  mStart := AClass.Decl.StartPos;
  Result := TTextRange.Create(mStart.Line, mStart.Character, mStart.Line, mStart.Character + Length(AClass.Name));
end;

/// <summary>initialization-Abschnitt der Unit; nil ohne. False bei der alten Form begin … end.</summary>
function InitializationOf(ARoot: TSyntaxNode; out ASection: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  ASection := nil;
  for mIndex := 0 to ARoot.ChildCount - 1 do
  begin
    case ARoot[mIndex].Kind of
      TSyntaxKind.Block:
        Exit(False);
      TSyntaxKind.InitializationSection:
        ASection := ARoot[mIndex];
    end;
  end;
  Result := True;
end;

/// <summary>Stelle für einen neuen initialization-Abschnitt: vor finalization bzw. dem abschließenden end.
/// (ein leeres finalization steht nicht im Baum).</summary>
function NewSectionAt(const ATokens: TArray<TPascalToken>; out AAt: TTextPosition): Boolean;
var
  mIndex, mFinal: Integer;
begin
  mFinal := High(ATokens) - 1;
  while (mFinal > 0) and not (SameText(ATokens[mFinal].Text, 'end') and ATokens[mFinal + 1].IsSymbol('.')) do
  begin
    Dec(mFinal);
  end;
  Result := mFinal > 0;
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to mFinal - 1 do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Keyword) and SameText(ATokens[mIndex].Text, 'finalization') then
    begin
      mFinal := mIndex;
      Break;
    end;
  end;
  AAt := ATokens[mFinal].StartPos;
end;

function TRegistrationCheck.RegisterFix(const AName: string; out AFix: TRuleFix): Boolean;
var
  mSection: TSyntaxNode;
  mCall, mText: string;
  mAt: TTextPosition;
begin
  mCall := 'TDUnitX.RegisterTestFixture(' + AName + ');';
  mAt := Default(TTextPosition);
  Result := InitializationOf(FContext.Tree.Root, mSection);
  if Result and (mSection <> nil) then
  begin
    mAt := mSection.EndPos;
    mText := '';
    if (mSection.ChildCount > 0) and (mSection.EndOffset > 0) and (FContext.Text[mSection.EndOffset] <> ';') then
    begin
      mText := ';';
    end;
    mText := mText + FLineBreak + '  ' + mCall;
  end
  else if Result then
  begin
    Result := NewSectionAt(FContext.Tree.Tokens, mAt);
    mText := 'initialization' + FLineBreak + '  ' + mCall + FLineBreak + FLineBreak;
  end;
  if Result then
  begin
    AFix := TRuleFix.Create(cTexts[TRegistrationText.Register].Fmt([AName]), [TTextEdit.Create(TTextRange.Create(
      mAt, mAt), mText)]);
  end;
end;

/// <summary>Edit, der AUnitName samt Pfad hinter den letzten Eintrag in uses der .dpr setzt.</summary>
function DprEdit(const ADprText, AUnitName, APath: string; out AEdit: TTextEdit): Boolean;
var
  mTree: TSyntaxTree;
  mUses, mLast: TSyntaxNode;
  mLineBreak: string;
begin
  Result := False;
  mLineBreak := TTextLines.LineBreakOf(ADprText);
  mTree := TSyntaxTreeCache.Parse(ADprText);
  try
    mUses := mTree.Root.FindChild(TSyntaxKind.UsesClause);
    if (mUses = nil) or (mUses.ChildCount = 0) then
    begin
      Exit;
    end;
    mLast := mUses[mUses.ChildCount - 1];
    AEdit := TTextEdit.Create(TTextRange.Create(mLast.EndPos, mLast.EndPos), ',' + mLineBreak + '  ' + AUnitName +
      ' in ''' + APath + '''');
    Result := True;
  finally
    mTree.Free;
  end;
end;

/// <summary>Edit, der eine DCCReference hinter die letzte der .dproj setzt.</summary>
function DprojEdit(const ADprojText, APath: string; out AEdit: TTextEdit): Boolean;
var
  mLines: TArray<string>;
  mLineBreak: string;
  mIndex, mLast: Integer;
begin
  mLines := TTextLines.SplitLines(ADprojText, mLineBreak);
  mLast := -1;
  for mIndex := 0 to High(mLines) do
  begin
    if ContainsText(mLines[mIndex], '<DCCReference Include=') then
    begin
      mLast := mIndex;
    end;
  end;
  Result := mLast >= 0;
  if Result then
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(mLast + 1, 0, mLast + 1, 0), TTextLines.IndentOf(mLines[mLast]) +
      '<DCCReference Include="' + APath + '"/>' + mLineBreak);
  end;
end;

/// <summary>Testprojekte der Gruppe, wenn keines AFileName enthält (ANames: ihre Dateinamen); sonst nil.</summary>
function TestProjectsWithout(const AFiles: IRuleProjectFiles; const AFileName: string;
  out ANames: string): TArray<TRuleProject>;
var
  mProject: TRuleProject;
  mSource: string;
begin
  Result := nil;
  ANames := '';
  // AFileName '' liefert alle Projekte der Gruppe.
  for mProject in AFiles.ProjectsOf('', True) do
  begin
    if not mProject.IsTest then
    begin
      Continue;
    end;
    for mSource in mProject.Sources do
    begin
      if SameText(mSource, AFileName) then
      begin
        Exit(nil);
      end;
    end;
    Result := Result + [mProject];
    ANames := ANames + IfThen(ANames <> '', ', ') + ExtractFileName(mProject.FileName);
  end;
end;

/// <summary>.dpr unter den Quelltexten eines Projekts; '' ohne.</summary>
function MainSourceOf(const AProject: TRuleProject): string;
var
  mSource: string;
begin
  for mSource in AProject.Sources do
  begin
    if SameText(ExtractFileExt(mSource), '.dpr') then
    begin
      Exit(mSource);
    end;
  end;
  Result := '';
end;

function TRegistrationCheck.ProjectFix(const AProject: TRuleProject; out AFix: TRuleFix): Boolean;
var
  mDpr, mText: string;
  mEdit: TTextEdit;
  mOther: TRuleFileEdits;
begin
  AFix := TRuleFix.Create(cTexts[TRegistrationText.AddToProject].Fmt([ExtractFileName(AProject.FileName)]), nil,
    False);
  mDpr := MainSourceOf(AProject);
  if (mDpr <> '') and FContext.ProjectFiles.ReadText(mDpr, mText) and
    DprEdit(mText, FContext.UnitName, RelativeTo(FContext.FileName, mDpr), mEdit) then
  begin
    mOther.FileName := mDpr;
    mOther.Edits := [mEdit];
    AFix.OtherFiles := AFix.OtherFiles + [mOther];
  end;
  if SameText(ExtractFileExt(AProject.FileName), '.dproj') and
    FContext.ProjectFiles.ReadText(AProject.FileName, mText) and
    DprojEdit(mText, RelativeTo(FContext.FileName, AProject.FileName), mEdit) then
  begin
    mOther.FileName := AProject.FileName;
    mOther.Edits := [mEdit];
    AFix.OtherFiles := AFix.OtherFiles + [mOther];
  end;
  Result := AFix.OtherFiles <> nil;
end;

procedure TRegistrationCheck.CheckProjects(const AFirst: TDUnitXClass);
var
  mTests: TArray<TRuleProject>;
  mNames: string;
  mFix: TRuleFix;
  mFixes: TArray<TRuleFix>;
begin
  mTests := TestProjectsWithout(FContext.ProjectFiles, FContext.FileName, mNames);
  if mTests = nil then
  begin
    Exit;
  end;
  mFixes := nil;
  if (Length(mTests) = 1) and ProjectFix(mTests[0], mFix) then
  begin
    mFixes := [mFix];
  end;
  FReport.Add(NameRange(AFirst), cTexts[TRegistrationText.NotInProject].Fmt([mNames]), TRuleConfidence.Medium,
    mFixes);
end;

/// <summary>Findet der Runner der .dpr Testklassen über [TestFixture]? Nur nicht, wenn sie einen Runner
/// anlegt (TDUnitX.CreateRunner) und UseRTTI nicht auf True setzt; andere Runner (TestInsight, GUI) suchen
/// selbst.</summary>
function DiscoversByAttribute(const ADprText: string): Boolean;
var
  mText: string;
begin
  mText := LowerCase(StringReplace(StringReplace(ADprText, ' ', '', [rfReplaceAll]), #9, '', [rfReplaceAll]));
  Result := (Pos('createrunner', mText) = 0) or (Pos('usertti:=true', mText) > 0);
end;

procedure TRegistrationCheck.ReadProjects;
var
  mProject: TRuleProject;
  mDpr, mText: string;
begin
  FDiscovers := True;
  FInProject := False;
  for mProject in FContext.ProjectFiles.ProjectsOf(FContext.FileName, False) do
  begin
    FInProject := True;
    mDpr := MainSourceOf(mProject);
    if (mDpr <> '') and FContext.ProjectFiles.ReadText(mDpr, mText) and not DiscoversByAttribute(mText) then
    begin
      FDiscovers := False;
    end;
  end;
end;

function TRegistrationCheck.AttributeFix(const AClass: TDUnitXClass): TRuleFix;
var
  mLine: Integer;
begin
  mLine := AClass.Decl.StartPos.Line;
  Result := TRuleFix.Create(cTexts[TRegistrationText.AddAttribute].Text, [TTextEdit.Create(TTextRange.Create(mLine,
    0, mLine, 0), TTextLines.IndentOf(FContext.Text, mLine) + '[TestFixture]' + FLineBreak)]);
  Result.Alternative := True;
end;

procedure TRegistrationCheck.CheckClass(const AClass: TDUnitXClass);
var
  mFix: TRuleFix;
  mFixes: TArray<TRuleFix>;
  mHasAttribute: Boolean;
begin
  mHasAttribute := AClass.HasAttribute('TestFixture');
  if (mHasAttribute and FDiscovers) or FRegistersAll or FMentioned.ContainsKey(UpperCase(AClass.Name)) or
    MentionedElsewhere(AClass.Name) then
  begin
    Exit;
  end;
  mFixes := nil;
  if RegisterFix(AClass.Name, mFix) then
  begin
    mFix.Alternative := FDiscovers;
    mFixes := [mFix];
  end;
  if FDiscovers then
  begin
    mFixes := [AttributeFix(AClass)] + mFixes;
    FReport.Add(NameRange(AClass), cTexts[TRegistrationText.NoAttribute].Fmt([AClass.Name]),
      TRuleConfidence.Medium, mFixes);
  end
  else
  begin
    FReport.Add(NameRange(AClass), cTexts[TRegistrationText.NotRegistered].Fmt([AClass.Name]),
      TRuleConfidence.Medium, mFixes);
  end;
end;

procedure TRegistrationCheck.Run;
var
  mClass: TDUnitXClass;
  mFirst: Boolean;
begin
  if not FProjectsKnown then
  begin
    Exit;
  end;
  ReadProjects;
  CollectMentions;
  mFirst := True;
  for mClass in FClasses do
  begin
    if not IsFixture(mClass) then
    begin
      Continue;
    end;
    if mFirst then
    begin
      CheckProjects(mClass);
    end;
    mFirst := False;
    // Eine Unit außerhalb aller Projekte meldet Teil 2.
    if FInProject then
    begin
      CheckClass(mClass);
    end;
  end;
end;

{ TDUnitXFixtureNotRegisteredRule }

function TDUnitXFixtureNotRegisteredRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDUnitXFixtureNotRegisteredRuleId, TRuleSeverity.Warning,
    cTexts[TRegistrationText.Title].Text);
end;

procedure TDUnitXFixtureNotRegisteredRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TRegistrationCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.Tree.Root.Kind <> TSyntaxKind.UnitFile) or
    not ContainsText(AContext.Text, 'Test') or not TUsesClauses.IsTestUnit(AContext.Tree.Tokens) then
  begin
    Exit;
  end;
  mCheck := TRegistrationCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Testing.Registration', cTexts);

end.
